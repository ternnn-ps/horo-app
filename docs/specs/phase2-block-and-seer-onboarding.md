# Chata — เฟส 2 (ส่วนที่ 3): Block user + Seer onboarding

> สถานะ: **spec สำหรับ implement** — ยังไม่มี migration ใด ๆ ถูกเขียนจากเอกสารนี้
> ผู้เขียน: product/backend architect agent · 2026-08-27
> ต้องอ่านคู่กัน: `00-design-brief.md`, `chata-database-design.md` (§4.1, §4.2, §4.14),
> migration จริงที่รันอยู่บน cloud แล้ว 16 ไฟล์ (โดยเฉพาะ `20260826000002`, `20260826000006`,
> `20260826000007`, `20260826000009`, `20260827000001`, `20260827000002`)

## 0. หลักการร่วมของทั้งสองฟีเจอร์

1. **ทุกเส้นทางที่แตะเงินหรือ state ที่มีผลทางบัญชี = RPC `SECURITY DEFINER`**
   (`set search_path = ''`, lock wallet ก่อนแตะเงิน, error เป็น message code) — ตาราง money
   ยัง deny-all เหมือนเดิม ไม่มีข้อยกเว้น
2. **การ block ต้องไม่ใช่เครื่องมือทำเงิน** — กฎเหล็กของเฟสนี้คือ *"คนกดบล็อกเป็นฝ่ายเสีย
   ไม่มีทางได้"* (blocker forfeits) ทุก state ของ question ต้องพิสูจน์ได้ว่า
   ไม่มีฝ่ายไหนกดบล็อกแล้วรวยขึ้น
3. logic เรื่องเงิน**ห้ามเขียนใหม่** — ใช้ `internal_refund_question` /
   `internal_settle_question` ที่มีอยู่ (`20260827000001`) เป็นทางเดียว
4. ของใหม่ทุกตารางเดินตาม convention เดิม: `(select auth.uid())` ใน policy,
   deny-all = enable RLS ไม่มี policy, ไม่มี default grant (โปรเจกต์ปิด auto-expose),
   `touch_versioned_row` / `set_updated_at` ตามว่ามี `version` ไหม

---

# A. Block user

## A.1 ปัญหาและเป้าหมาย

เฟส 1 ตัด `block_relation` ออก (comment หัวไฟล์ `20260826000003` บอกไว้ตรง ๆ ว่า
"การเช็ค block ใน submit_question จึงยังไม่มี") ตอนนี้:

- ผู้ใช้ที่ก่อกวน seer ซ้ำ ๆ ส่งคำถามใหม่ได้เรื่อย ๆ ตราบใดที่มีเหรียญ
- แอป UGC ที่มีแชท **ต้องมีปุ่ม block ทั้งสองฝั่ง** ตาม App Store Review Guideline 1.2
  (ability to block abusive users) — ไม่มีคือความเสี่ยงโดน reject ตอน submit iOS

เป้าหมาย: block ได้ทั้งสองทิศ, จัดการ escrow ที่ค้างอยู่ให้จบใน transaction เดียวกับการ block,
และไม่มี state ไหนที่เงิน "ค้างลอย" หรือถูกโกงได้

## A.2 ทางเลือกที่พิจารณา

### A.2.1 ใครบล็อกใครได้

| ทาง | ข้อดี | ข้อเสีย |
|---|---|---|
| (ก) seer → user ทางเดียว (ตาม spec §4.14.1 เดิม ที่ reverse มาจาก DuangLive) | ตรง reverse target, ง่ายสุด | user โดน seer ตามรังควานในแชทไม่มีทางป้องกันตัว → เสี่ยง App Store guideline 1.2 |
| (ข) **สองทิศ, ตารางเดียว generic (`blocker_id`, `blocked_id`)** ✅ | ครอบทุกกรณีด้วย schema เดียว, enforcement จุดเดียว, ผ่าน App Review | ต่างจาก spec §4.14.1 เดิม (ต้องอัปเดต design doc ตาม) |
| (ค) สองตารางแยกทิศ | ไม่มีข้อดีเหนือ (ข) | ซ้ำซ้อน, เช็คสองตาราง |

**ตัดสินใจ: (ข)** — `block_relation` เป็น `(blocker_id, blocked_id)` ไม่สน role
เหตุผลหลักคือ App Store guideline + ความสมมาตรของกฎเงิน (A.5) ที่เขียนได้สวยเมื่อ
ตารางสมมาตร นี่คือการ**แก้ spec §4.14.1 อย่างตั้งใจ** ให้ implement ตามเอกสารนี้
แล้วอัปเดต `chata-database-design.md` §4.14.1 ตาม

### A.2.2 บล็อกแล้ว question ที่ค้างอยู่ทำอย่างไร

| ทาง | ปัญหา |
|---|---|
| (ก) ไม่แตะงานค้างเลย — block มีผลเฉพาะงานใหม่ | คู่กรณียังต้องคุยกันต่อในงานเก่า = block ไม่ปกป้องใครจริง; แชทค้างเปิดกับคนที่บล็อกกันแล้ว |
| (ข) แช่แข็งแชทแต่ปล่อยงานเดินตาม cron เดิม | งาน `active` จะ auto-settle จ่าย seer ตอน `expires_at` → seer "ตอบหนึ่งครั้ง แล้วบล็อกทิ้ง" ก็ยังได้เงิน = ฟาร์มได้; user ถูกปิดปากระหว่างรอ |
| (ค) **ปิดงานค้างทั้งหมดทันทีใน transaction เดียวกับ block ตามกฎ blocker-forfeits** ✅ | ต้อง loop งานค้างใน RPC (มีเพดานธรรมชาติจาก rate limit `submit_question` 10/ชม. อยู่แล้ว) |

**ตัดสินใจ: (ค)** — หลัง block สำเร็จ **ไม่เหลือ question เปิดค้างระหว่างคู่นั้นเลย**
ผลพลอยได้สำคัญ: ไม่ต้องแก้ `can_post_question_message` / RLS ของแชทเลย เพราะ
ข้อความโพสต์ได้เฉพาะ question ที่ status ยังเปิด ซึ่งไม่มีเหลือแล้ว

## A.3 ตารางใหม่: `block_relation`

ตอบคำถาม: "บัญชีไหน block บัญชีไหน ทิศไหน เมื่อไหร่ เพราะอะไร"

| column | type | null? | default | constraint |
|---|---|---|---|---|
| `blocker_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `account(id)` ON DELETE CASCADE |
| `blocked_id` | `uuid` | NO | — | PK ส่วนสอง, FK → `account(id)` ON DELETE CASCADE |
| `reason` | `text` | YES | — | CHECK `char_length(reason) <= 500` — บันทึกส่วนตัวของ blocker ไม่แสดงให้อีกฝ่าย |
| `created_at` | `timestamptz` | NO | `now()` | |

- PK `(blocker_id, blocked_id)`; `CHECK (blocker_id <> blocked_id)`
- Indexes: PK พอสำหรับเช็คทิศเดียว + `(blocked_id)` สำหรับเช็คทิศกลับ
  (`submit_question` ต้องเช็คทั้ง (seer,user) และ (user,seer))
- แถวสองทิศเป็นอิสระต่อกัน (A block B และ B block A อยู่ร่วมกันได้)
- **RLS posture:**
  - SELECT: `blocker_owner_select` — `blocker_id = (select auth.uid())`
    (blocker เห็นรายการของตัวเอง; **ฝ่ายถูก block ไม่มีทางอ่านเจอว่าตัวเองโดน** —
    ผลโผล่เป็น error ตอนซื้อเท่านั้น ตาม posture เดิมใน design doc)
  - INSERT/UPDATE/DELETE: **ไม่มี policy + ไม่มี grant เขียน** — เขียนผ่าน RPC เท่านั้น
    เหตุผล: การ insert มี side effect เรื่องเงิน (ปิดงานค้าง) ห้ามให้ client แตะตรง
- GRANT (ไฟล์ grants ใหม่): `grant select on public.block_relation to authenticated;`
  — ไม่ grant ให้ anon, ไม่ grant insert/update/delete ให้ใครนอกจาก service_role

## A.4 State machine

`block_relation` ไม่มี status — การมีแถว = blocked, ลบแถว = unblocked

| transition | ใครทำได้ | ผ่านอะไร |
|---|---|---|
| (ไม่มีแถว) → blocked | เจ้าของ `blocker_id` (บัญชี `active` เท่านั้น) | RPC `block_account` |
| blocked → (ไม่มีแถว) | เจ้าของ `blocker_id` | RPC `unblock_account` |

- unblock ได้เสมอ ไม่มีเงื่อนไข ไม่มี cooldown (การกัน block/unblock รัว ๆ ใช้ rate limit
  bucket เดียวกันทั้งสอง RPC — ดู A.8)
- unblock **ไม่ undo** งานที่ถูกปิดไปตอน block (เงินจบแล้วจบเลย — ledger เป็น append-only
  ตาม design brief §4 อยู่แล้ว) อยากคุยกันใหม่ = user ซื้อคำถามใหม่

## A.5 กฎเรื่องเงิน — blocker forfeits (หัวใจของฟีเจอร์)

หลักคิด: state ของ question บอกว่า "seer ลงแรงหรือยัง" (`submitted` = ยังไม่ตอบเลย,
`active`/`close_requested` = ตอบแล้วอย่างน้อยหนึ่งครั้ง — trigger
`question_message_after_insert` เป็นคนเลื่อน state ให้ตอนนี้อยู่แล้ว)
เมื่อมีงานลงแรงแล้วต้องเลือกว่าเงินไปทางไหน ให้ **ฝ่ายที่กดบล็อกเป็นฝ่ายเสียประโยชน์เสมอ**

| question state ณ เวลา block | seer กด block user | user กด block seer |
|---|---|---|
| `submitted` (seer ยังไม่ตอบ) | **refund → user** (`internal_refund_question`, reason `'blocked'`) — seer ไม่ได้ทำงาน ไม่มีสิทธิ์ได้เงินอยู่แล้ว | **refund → user** (reason `'blocked'`) — เทียบเท่า `cancel_question` ที่ user ทำเองได้อยู่แล้ว ไม่มีช่องโกง |
| `active` | **refund → user** — seer สละรายได้ของงานนี้ | **settle → seer ได้ส่วนแบ่ง** (`internal_settle_question(id, true)`) — user สละ escrow; seer ตอบแล้วจึงสมควรได้ ตามนโยบายเดียวกับ auto-close เดิม |
| `close_requested` | **refund → user** (เหมือน active) | **settle → seer** (เหมือน active) |
| `completed` | ไม่แตะ (เงิน settle ไปแล้ว) | ไม่แตะ |
| `cancelled_refunded` | ไม่แตะ | ไม่แตะ |

พิสูจน์กันโกงทีละช่อง:

- **seer ฟาร์มเงิน** ("ตอบหนึ่งบรรทัดแล้วบล็อก"): active + seer block → refund user →
  seer ได้ 0 ❌ ฟาร์มไม่ได้
- **user ชักดาบ** ("ได้คำตอบแล้วบล็อกหนี"): active + user block → settle → seer ได้เงิน
  ❌ หนีไม่ได้
- **user ยั่วให้ seer บล็อก** เพื่อเอาคำตอบฟรี: เป็นไปได้ในทางทฤษฎี แต่ (1) user ไม่ได้กำไร
  ได้แค่เงินตัวเองคืน (2) seer ที่รู้ระบบมี**ทางเลือกที่ไม่เสียเงินเลย**: ปล่อยงานไว้เฉย ๆ
  ให้ `job_autoclose_stale_questions` settle ตอน `expires_at` (ได้เงินตามนโยบายเดิม)
  แล้วค่อยกด block หลังงานจบ → **ต้องเขียนคำแนะนำนี้ใน UI ฝั่ง seer**
  ("บล็อกตอนนี้ = คืนเหรียญให้ผู้ถาม ถ้าต้องการรับค่าตอบให้ปิดงานก่อนแล้วจึงบล็อก")
- **block เพื่อหนีรีวิวแย่**: เฟสนี้ยังไม่มีตาราง `review` — วางกฎล่วงหน้าเป็นพันธะของเฟสรีวิว:
  *สิทธิ์รีวิวผูกกับ question ที่ `completed` และต้องไม่ถูกริบด้วย block ที่เกิดทีหลัง*
  (`submit_review` ในอนาคตห้ามเช็ค `block_relation`) — จดลง design doc §4.3.3 ด้วย

การเลือก reason `'blocked'` (ค่าใหม่) แทนการยืม `'seer_reject'`/`'user_cancel'`:
ระบบเงินจริงต้อง audit ย้อนหลังได้ว่าการคืนเงินก้อนไหนมาจากการบล็อก — แลกกับการแก้
constraint หนึ่งตัวและ whitelist ใน function เดียว (ดู A.7) ถือว่าคุ้ม

## A.6 RPC

### A.6.1 `block_account`

| หัวข้อ | รายละเอียด |
|---|---|
| signature | `public.block_account(p_blocked_id uuid, p_reason text default null) returns jsonb` |
| สิทธิ์ | `authenticated` เท่านั้น (revoke public/anon ตามแบบ `20260826000009`) |
| ทำใน transaction เดียว | 1) auth + `p_blocked_id <> auth.uid()` + target มีแถวใน `account` (ไม่งั้น `not_found`) 2) เช็คบัญชีตัวเอง `status='active'` (ไม่งั้น `account_not_active`) 3) idempotent: มีแถว PK อยู่แล้ว → คืน `{replayed:true}` **ก่อน** rate limit 4) `consume_rate_limit(uid,'block_action')` 5) `insert into block_relation` 6) loop question เปิดค้างของคู่นี้ **ทั้งสองบทบาท** (`(user_id,seer_id)=(blocked,blocker)` และ `(blocker,blocked)`) ที่ `status in ('submitted','active','close_requested')` — `for update skip locked` ไม่ต้อง เพราะเราต้องปิดครบ ใช้ `for update` ธรรมดา เรียงตาม `id` กัน deadlock — แล้วยิงตามตาราง A.5: ผู้กดเป็น seer ของงาน → `internal_refund_question(id,'blocked')`; ผู้กดเป็น user ของงาน → `submitted` = refund, `active`/`close_requested` = `internal_settle_question(id,true)` 7) คืน `{blocked_id, resolved_questions:[{question_id, resolution}], replayed:false}` |
| idempotency | PK `(blocker_id, blocked_id)`; retry คืนแถวเดิม ไม่ loop งานซ้ำ (internal_* ก็ idempotent ในตัวอีกชั้น) |
| error case | `not_authenticated`, `not_found`, `cannot_block_self`, `account_not_active`, `rate_limited` |

หมายเหตุ implement: ห้าม copy สูตร refund/settle มาไว้ในนี้ — เรียก `internal_*` เท่านั้น
(เหตุผลเดียวกับหัวไฟล์ `20260827000001`: สูตรเงินต้องมีที่เดียว)
race กับ `question_message` insert: ข้อความที่ insert ขนานกับ block อาจหลุดเข้ามาได้
หนึ่งช่วง MVCC — ยอมรับได้ (งานถูกปิดแล้ว client แสดงเป็นแชทปิด) ไม่ต้องกัน

การแจ้งเตือน: **ไม่แจ้งฝ่ายถูก block ว่าโดนบล็อก** — แต่ notification จาก
`internal_refund_question` ("คำถามถูกยกเลิกและคืนเหรียญแล้ว") / `internal_settle_question`
ยิงตามปกติ ซึ่งไม่เปิดเผยคำว่า block (ตรวจแล้ว: ข้อความเดิมใน `20260827000001` กลาง ๆ พอ
ไม่ต้องแก้ ยกเว้นเพิ่ม case reason `'blocked'` ให้ใช้ข้อความ generic ตัวเดียวกับ else เดิม)

### A.6.2 `unblock_account`

| หัวข้อ | รายละเอียด |
|---|---|
| signature | `public.unblock_account(p_blocked_id uuid) returns jsonb` |
| สิทธิ์ | `authenticated` |
| ทำอะไร | ลบแถว `(auth.uid(), p_blocked_id)`; ไม่มีแถว → `{replayed:true}` (idempotent, ไม่นับ rate limit); มีแถว → `consume_rate_limit(uid,'block_action')` แล้วลบ |
| เงิน | ไม่แตะเลย |
| error case | `not_authenticated`, `rate_limited` |

## A.7 ผลกระทบต่อของเดิม

| ของเดิม | ไฟล์ที่นิยามล่าสุด | แก้อย่างไร |
|---|---|---|
| `question.question_cancel_reason_chk` | `20260826000003` | migration ใหม่: drop + add ให้รวม `'blocked'` (แบบเดียวกับที่ `20260827000001` ขยาย `system_event`) |
| `internal_refund_question` | `20260827000001` | `create or replace`: เพิ่ม `'blocked'` ใน whitelist reason; notification ใช้ข้อความ generic เดิม (ตกลง else branch เดิมอยู่แล้ว — เช็คว่า `case p_reason` ครอบ) |
| `submit_question` | **`20260827000002` (ตัวล่าสุด — ห้ามแก้จากตัวใน 09)** | `create or replace`: หลังเช็ค `seer_unavailable` เดิม เพิ่ม (1) block เช็คสองทิศ: มีแถว `(seer→user)` → raise `'seer_unavailable'` (ไม่เผยว่าโดน block); มีแถว `(user→seer)` → raise `'blocked_by_you'` (client รู้อยู่แล้วว่าตัวเองบล็อกใคร บอกตรง ๆ ให้ UX ชวน unblock ได้) (2) เช็ค `retired_at is null` (ดู B.9) |
| `chata-database-design.md` §4.14.1 | docs | อัปเดตให้ตรง schema ใหม่ (สองทิศ) + จดกฎ blocker-forfeits และพันธะเรื่อง review |
| grants | `20260826000007` เป็น pattern | ไฟล์ migration ใหม่ grant select ให้ authenticated ตาม A.3 |

**ไม่ต้องแก้:** `can_post_question_message`, RLS ของ `question`/`question_message`,
cron jobs ทุกตัว, `internal_settle_question` — เพราะ block ปิดงานค้างหมดใน RPC แล้ว

## A.8 Rate limit bucket (เพิ่มใน `app_config` key `ratelimit.buckets` ที่มีอยู่)

```json
"block_action": {"limit": 20, "window_seconds": 3600}
```

ครอบทั้ง block และ unblock รวมกัน — กันทั้งสแปมบล็อกและ block/unblock cycling
(ปรับได้ทาง config โดยไม่ migration ตาม design ของ `20260827000002`)

## A.9 Test cases (เพิ่มไฟล์ `db/tests/block.test.sql` ตามแบบ 3 ไฟล์เดิม)

เงิน (สำคัญสุด — ทุกข้อ assert ยอด `v_my_wallet` + แถว `ledger_transaction` ตรงเป๊ะ):
1. seer block user ขณะ `submitted` → user ได้เหรียญคืนเต็ม, question เป็น
   `cancelled_refunded` + `cancel_reason='blocked'`, seer ได้ 0
2. seer block user ขณะ `active` → refund user เต็ม, seer ได้ 0 (พิสูจน์ฟาร์มไม่ได้)
3. user block seer ขณะ `active` → settle: seer ได้ตาม share_bps, platform ได้ fee,
   user_reserved เป็น 0
4. user block seer ขณะ `submitted` → refund user
5. block ขณะ `close_requested` → ตามข้อ 2/3 แล้วแต่ทิศ
6. block ขณะ `completed` → เงินไม่ขยับ ไม่มี ledger แถวใหม่
7. คู่ที่มีหลาย question ค้างพร้อมกัน (เช่น 3 ใบ คนละ state) → ปิดครบทุกใบถูกทิศ
8. เรียก `block_account` ซ้ำ (retry) → `replayed:true`, ไม่มี ledger ซ้ำ, ไม่กินโควตา
9. `job_reconcile_wallets` หลังทุกเทสข้างบน → ไม่พบ drift

พฤติกรรม:
10. หลัง block: `submit_question` จากฝั่ง user ที่โดน seer บล็อก → `seer_unavailable`
11. หลัง user บล็อก seer: `submit_question` → `blocked_by_you`
12. หลัง block: insert `question_message` ลง question ที่ถูกปิด → โดน RLS/`can_post` ปฏิเสธ
13. unblock แล้ว submit_question ใหม่ → ผ่าน; งานเก่าที่ถูกปิดยังปิดอยู่ (ไม่ undo)
14. block ตัวเอง → `cannot_block_self`; block uuid มั่ว → `not_found`
15. A block B และ B block A พร้อมกัน (สองแถว) → unblock ฝั่งเดียวแล้วอีกฝั่งยังกันอยู่
16. RLS: blocker อ่านแถวตัวเองได้; ฝ่ายถูก block select ไม่เจอแถว; client insert/delete
    ตรงโดน permission denied
17. rate limit: ครั้งที่ 21 ใน 1 ชม. → `rate_limited`; retry ที่ replayed ไม่กินโควตา
18. บัญชี `suspended` เรียก `block_account` → `account_not_active`

## A.10 สิ่งที่จงใจไม่ทำในเฟสนี้

- **admin force-block / global ban** — มีกลไก `moderation_action` + `account.status='suspended'` อยู่แล้วใน design ใช้ทางนั้น
- **ซ่อน seer ที่เรา block ออกจาก catalog ฝั่ง server** — จะต้องแก้ policy `seer_profile_public_select` ให้ subquery ต่อ row ซึ่งแพงและพัง cache; ให้ client กรองเอง (อ่าน block list ของตัวเองได้อยู่แล้ว) ส่วน enforcement จริงอยู่ที่ `submit_question` ซึ่งกันไว้แล้ว
- **แจ้งเตือน/ตัวบ่งชี้ว่าโดน block** — ตั้งใจไม่บอก (ลด retaliation) ตาม posture ใน design doc เดิม
- **block แบบมีอายุ (temporary block)** — ยังไม่มี use case; unblock มือทำแทนได้

---

# B. Seer onboarding (เส้นทางสมัครเป็นหมอดู)

## B.1 ปัญหาและเป้าหมาย

ตอนนี้ `seer_profile` INSERT ได้เฉพาะ service_role (comment ใน `20260826000006`:
"INSERT (สมัครเป็น seer) ยังไม่มีในเฟส 1") — ผู้ใช้สมัครเองไม่ได้ ต้องให้คนไปกดใน Studio
ซึ่งไม่ scale และไม่มี audit trail

เป้าหมาย: ผู้ใช้ยื่นใบสมัครเองจากแอปครบวงจร (กรอกข้อมูล + แนบเอกสาร KYC) →
ทีมงานอนุมัติผ่าน RPC ที่บันทึก audit ครบ (ยังไม่มี admin console — ใช้ Studio SQL
เรียก RPC ไปก่อนได้) → อนุมัติแล้วกลายเป็น seer ที่เปิดขายได้ทันที

## B.2 ⚠️ จุดที่ต้องให้ user เคาะ — โมเดลความสัมพันธ์ user/seer

`account.role` เป็นค่าเดียวต่อบัญชี และ design เดิมเคาะไว้ว่า "user กับ seer เป็นคนละบัญชี
สลับ role ไม่ได้" (design doc §4.1.1) แต่การให้ผู้ใช้สมัครเป็น seer เองย่อมหมายความว่า
*บัญชีที่เกิดมาเป็น user ต้องเปลี่ยนสถานะบางอย่าง* — เลี่ยงไม่ได้ที่จะต้องตีความข้อตัดสินใจเดิมใหม่
**สามทางเลือก ห้าม implement จนกว่า user เคาะ:**

### ทาง 1 — One-way promotion: บัญชีเดิมเลื่อนขั้นเป็น seer ถาวร (แนะนำ ✅)

บัญชี `role='user'` ยื่นใบสมัครได้ → ตอนอนุมัติ RPC เปลี่ยน `role` เป็น `'seer'`
**ทางเดียว ถาวร ไม่มีสลับกลับ** — คนที่อยากเป็นทั้งลูกค้าและหมอดูแบบแยกตัวตน
ก็ยังทำแบบเดิมได้ (สมัครอีเมลใหม่เป็นบัญชีที่สอง แล้วยื่นสมัครจากบัญชีนั้น)

- **กระทบของเดิม: เกือบศูนย์** — `current_account_role()`, policy `seer_skill_owner_insert`
  / `seer_service_owner_insert` (เช็ค role='seer'), CHECK ของ `account.role`,
  ไม่ต้องแก้อะไรเลย; `handle_new_user` สร้าง `user_profile`+`wallet` ให้ทุกคนอยู่แล้ว
  (แถว `user_profile` ของบัญชีที่เลื่อนเป็น seer คงอยู่เฉย ๆ ไม่มีโทษ)
- ข้อเท็จจริงที่ค้นพบระหว่างรีวิวโค้ดจริง: `submit_question` **ไม่เช็ค role ผู้ซื้อ**
  (เช็คแค่ไม่ถามตัวเอง) — แปลว่าวันนี้บัญชี seer ก็ซื้อคำถามจาก seer อื่นได้อยู่แล้ว
  ทาง 1 จึงไม่ได้ "เพิ่ม" ความสามารถสลับโหมดอะไรเกินที่ระบบเป็นอยู่
- ข้อเสีย: คำว่า "สลับ role ไม่ได้" ใน design doc ต้องถูกตีความเป็น
  "เลื่อนขั้นทางเดียวได้ สลับไปมาไม่ได้" — เป็นการ**ผ่อนข้อตัดสินใจเดิมเล็กน้อย ต้องให้ user
  ยืนยัน**; wallet เดียวปนบทบาท (available จากการเติม + payable จากการรับงาน)
  แต่ ledger แยก `ledger_account` ชัดอยู่แล้ว ไม่ปนทางบัญชี

### ทาง 2 — แยกบัญชีเคร่งครัด: สมัคร seer ได้เฉพาะบัญชีที่ยังไม่เคยเป็นลูกค้า

เหมือนทาง 1 แต่ RPC `submit_seer_application` ปฏิเสธบัญชีที่มีประวัติฝั่งลูกค้า
(เคยมี `question` เป็น user_id หรือเคยเติมเหรียญ) → บังคับให้ตัวตน seer สะอาดจริง

- ข้อดี: ตรงเจตนารมณ์ design เดิมที่สุด, ตัวตนสองฝั่งไม่ปนกันเลย
- ข้อเสีย: UX โหดกับผู้ใช้จริง (ลูกค้าที่อยากผันตัวเป็นหมอดูต้องทิ้งบัญชี/เหรียญเดิม),
  เช็ค "ไม่เคยเป็นลูกค้า" นิยามยากขึ้นเรื่อย ๆ เมื่อ domain โต (horoscope, live, gift)

### ทาง 3 — role เป็น set: บัญชีเดียวถือได้ทั้งสอง profile

`account.role` เปลี่ยนความหมายเป็น "แค่ admin flag" แล้วให้ capability มาจากการมีแถว
`seer_profile` (approved) / `user_profile` — หรือทำตาราง `account_role` แยก

- ข้อดี: UX ดีสุดระยะยาว (แอปเดียว สลับโหมดในตัว), ตรงกับที่หลาย marketplace ทำ
- ข้อเสีย: **แพงสุดและย้อนแย้งกับข้อตัดสินใจที่เคาะแล้วโดยตรง** — ต้องแก้
  `current_account_role()` + 2 policy + CHECK + client ต้องทำ mode switcher +
  design doc §4.1.1 ต้องรื้อ; ความเสี่ยง regression บน migration ที่ขึ้น cloud แล้ว
- ถ้าจะไปทางนี้ควรเป็นการตัดสินใจ product ระดับ pivot ไม่ใช่ side effect ของ onboarding

**ข้อเสนอแนะของผม: ทาง 1** — ได้ self-serve onboarding โดยแตะของที่รันอยู่บน cloud
น้อยที่สุด และไม่ปิดทางอัปเกรดไปทาง 3 ในอนาคต (schema ใบสมัคร B.3 ใช้ได้กับทุกทาง —
ต่างกันแค่ 2 บรรทัดใน `admin_review_seer_application` ว่า flip role หรือไม่)
ส่วนที่เหลือของ spec เขียนบนสมมติฐานทาง 1 และ mark จุดที่แปรผันตามทางเลือกไว้

## B.3 ตารางใหม่: `seer_application`

ใบสมัครแยกจาก `seer_profile` — **`seer_profile` จะมีแถวก็ต่อเมื่ออนุมัติแล้วเท่านั้น**

ทำไมไม่ใช้ `seer_profile.approval_status` (มี `draft/submitted/...` อยู่แล้ว) เป็นใบสมัคร:
(1) catalog สะอาด — ทุก join/policy/`submit_question` ที่แตะ `seer_profile` ไม่ต้องรับรู้
แถวครึ่ง ๆ กลาง ๆ (2) ประวัติสมัคร-ถูกปฏิเสธ-สมัครใหม่เก็บเป็นคนละแถว audit ได้
(3) เปิดทางเฟสหน้า: ใบสมัครชนิด `update` สำหรับ re-approve การแก้ข้อมูลสำคัญ ใช้ตารางเดิมได้
(`approval_status` บน `seer_profile` คงไว้ตามเดิม — มันเป็นแกนของ RLS/`submit_question`
ที่รันอยู่ แต่หลังเฟสนี้ค่าที่เกิดจริงจะมีแค่ `'approved'`)

| column | type | null? | default | constraint |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `status` | `text` | NO | `'draft'` | CHECK IN (`draft`,`submitted`,`approved`,`rejected`,`withdrawn`) |
| `display_name` | `text` | YES | — | CHECK NULL หรือ length 1–50 (ตอน submit บังคับ NOT NULL ใน RPC) |
| `bio` | `text` | YES | — | CHECK NULL หรือ length ≤ 2000 |
| `main_skill_id` | `integer` | YES | — | FK → `skill(id)` ON DELETE SET NULL |
| `skill_ids` | `integer[]` | NO | `'{}'` | CHECK `array_length ≤ 10`; validate รายตัวใน RPC ตอน submit (draft payload — ยอมเป็น array ได้เพราะจะ materialize เป็นแถว `seer_skill` จริงตอนอนุมัติ) |
| `price_coin` | `bigint` | YES | — | CHECK NULL หรือ `>= 0`; ตรวจ bounds กับ `service.price_bounds` ใน RPC ตอน submit (สูตรเดียวกับ `validate_seer_service_price`) |
| `submitted_at` | `timestamptz` | YES | — | |
| `reject_reason` | `text` | YES | — | CHECK length ≤ 1000 |
| `decided_at` | `timestamptz` | YES | — | |
| `decided_by_label` | `text` | YES | — | ตัวตนผู้ตัดสิน เช่น `'ray@studio'` (ยังไม่มี admin account จริง — ดู B.7) |
| `version` | `integer` | NO | `1` | trigger `touch_versioned_row` |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `CHECK (status <> 'rejected' or reject_reason is not null)`;
  `CHECK ((status in ('approved','rejected')) = (decided_at is not null))`
- **Partial unique:** `UNIQUE (account_id) WHERE status IN ('draft','submitted')` —
  เปิดได้ทีละหนึ่งใบ (สมัครใหม่หลัง rejected/withdrawn = แถวใหม่ ประวัติเดิมคงอยู่)
- Indexes: `(account_id, created_at desc)`; `(status) WHERE status='submitted'` (คิวรีวิว)
- **RLS posture:** SELECT — owner-read (`account_id = (select auth.uid())`);
  INSERT/UPDATE/DELETE — ไม่มี policy ไม่มี grant เขียน: **ทุก transition ผ่าน RPC**
  (ใบสมัครไม่แตะเงินก็จริง แต่ approve มี side effect ใหญ่ และ state machine
  ต้องบังคับจากจุดเดียว) · GRANT: `select` ให้ authenticated เท่านั้น

## B.4 ตารางใหม่: `seer_document` (เพิ่มในเฟสนี้ — เลื่อนไม่ได้)

ตัดสินใจ: **ต้องมาพร้อม onboarding** — การอนุมัติคนแปลกหน้าเข้ามารับเงินจริงบนแพลตฟอร์ม
โดยไม่มีเอกสารยืนยันตัวตนเลย เปิดช่อง scam ตั้งแต่วันแรก (และ payout เฟสหน้าต้องใช้ KYC ต่อ)

ตาม design doc §4.2.7 แต่**แก้หนึ่งจุดโดยตั้งใจ**: FK จาก `seer_id → seer_profile` เป็น
`account_id → account` — เพราะเอกสารถูกอัปโหลด*ตอนสมัคร* ซึ่ง `seer_profile` ยังไม่มีแถว

| column | type | null? | default | constraint |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `document_type` | `text` | NO | — | CHECK IN (`national_id`,`bank_book`,`certificate`,`portrait`,`other`) |
| `object_key` | `text` | NO | — | UNIQUE; path ใน private bucket; CHECK `object_key LIKE account_id::text \|\| '/%'` (กันชี้ไฟล์คนอื่น) |
| `review_status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`approved`,`rejected`) |
| `reject_reason` | `text` | YES | — | |
| `reviewed_at` | `timestamptz` | YES | — | |
| `reviewed_by_label` | `text` | YES | — | เหมือน `decided_by_label` |
| `deleted_at` | `timestamptz` | YES | — | soft delete โดยเจ้าของ ก่อนถูก review เท่านั้น |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(account_id) WHERE deleted_at IS NULL`;
  `(review_status) WHERE review_status='pending'` (คิว admin)
- State: `pending → approved | rejected` (โดยฝั่งรีวิวเท่านั้น); `rejected` → เจ้าของ
  อัปโหลด**แถวใหม่** (ห้ามแก้แถวเดิม — ตาม pattern §4.2.7)
- **RLS posture:** SELECT — owner-read เท่านั้น (ไม่มี public ทุกกรณี — PII);
  INSERT — owner insert ตรงได้ (ไม่แตะเงิน) ด้วย policy
  `with check (account_id = (select auth.uid()) and review_status = 'pending')`
  + column-level grant เฉพาะ (`account_id`,`document_type`,`object_key`)
  + **BEFORE INSERT trigger** เรียก `consume_rate_limit(account_id,'seer_document')`;
  UPDATE — owner ทำได้อย่างเดียวคือ soft delete: policy
  `using (account_id = (select auth.uid()))` + grant update เฉพาะ column `deleted_at`
  + trigger `protect_seer_document` บังคับ (แก้ได้เฉพาะ `deleted_at` จาก NULL → now
  และเฉพาะตอน `review_status='pending'`); ฝั่งรีวิวเขียนผ่าน RPC/service_role
- **Storage:** bucket ใหม่ `seer-documents` เป็น **private** — storage policy:
  authenticated INSERT ได้เฉพาะ path `auth.uid()::text || '/%'` และ SELECT ได้เฉพาะ
  path ของตัวเอง (เจ้าของดูเอกสารตัวเองในแอปได้); ทีมรีวิวเปิดไฟล์ผ่าน Studio /
  signed URL จาก service role เท่านั้น; จำกัด mime `image/*`,`application/pdf`,
  ขนาดตาม bucket file size limit (แนะนำ 10MB)

## B.5 State machine ของใบสมัคร

```
draft ──submit──▶ submitted ──approve──▶ approved   (terminal)
  ▲                  │  │
  │                  │  └──reject──▶ rejected       (terminal — สมัครใหม่ = แถวใหม่)
  └───แก้ draft ─────┘
        (withdraw จาก draft/submitted ─▶ withdrawn — terminal)
```

| transition | ใครทำ | ผ่าน RPC |
|---|---|---|
| (ไม่มีใบเปิดอยู่) → `draft` / แก้ field ใน `draft` | เจ้าของ (`role='user'`, `status='active'`, ยังไม่มี `seer_profile`) | `save_seer_application` |
| `draft` → `submitted` | เจ้าของ | `submit_seer_application` |
| `submitted` → `draft` | เจ้าของ (ดึงกลับมาแก้ก่อนถูกตัดสิน) | `save_seer_application` (เรียกตอน status=submitted = ดึงกลับเป็น draft พร้อมแก้) |
| `draft`/`submitted` → `withdrawn` | เจ้าของ | `withdraw_seer_application` |
| `submitted` → `approved` | ทีมงาน (service_role) | `admin_review_seer_application` |
| `submitted` → `rejected` | ทีมงาน (service_role) | `admin_review_seer_application` |
| `rejected`/`withdrawn` → สมัครใหม่ | เจ้าของ (แถวใหม่; นับ rate limit + เพดานรวม) | `save_seer_application` |

เงื่อนไข submit ผ่าน (ตรวจใน `submit_seer_application` ทั้งหมด):
`display_name`, `bio` (≥ 30 ตัวอักษร — กันใบสมัครขยะ), `main_skill_id` ที่ enabled,
`skill_ids` ทุกตัว valid + มี main อยู่ในชุด, `price_coin` อยู่ใน bounds ของ
`service.price_bounds -> 'chat_question'`, และ**เอกสารบังคับครบ**: มีแถว `seer_document`
ที่ `deleted_at is null and review_status <> 'rejected'` ครบทุก type ใน config ใหม่
`seer.application_required_documents` (ค่าเริ่ม `["national_id","portrait"]` — `bank_book`
ยังไม่บังคับ ไปบังคับตอนเฟส payout)

## B.6 RPC ฝั่งผู้สมัคร

### B.6.1 `save_seer_application`

| หัวข้อ | รายละเอียด |
|---|---|
| signature | `public.save_seer_application(p_display_name text, p_bio text, p_main_skill_id int, p_skill_ids int[], p_price_coin bigint) returns jsonb` |
| สิทธิ์ | `authenticated` |
| ทำใน transaction เดียว | 1) auth + `account.status='active'` + `role='user'` (ทาง 1; ถ้า user เคาะทางอื่นเปลี่ยนเงื่อนไขนี้จุดเดียว) 2) ยังไม่มีแถว `seer_profile` (มี = `already_seer`) 3) หาใบเปิดอยู่ (`draft`/`submitted`): ไม่มี → เช็คเพดานรวม `count(*) < get_config('seer.application_max_total')` (default 5) แล้ว `consume_rate_limit(uid,'seer_apply')` แล้ว insert draft; มี → update field + ถ้าเดิม `submitted` ให้ดึงกลับเป็น `draft` (`submitted_at=null`) 4) validate field แบบหลวม (แค่ CHECK ผ่าน — ความครบไปเข้มตอน submit) 5) คืน `{application_id, status}` |
| idempotency | เป็น upsert โดยธรรมชาติ — เรียกซ้ำได้ผลเท่าเดิม (แถวเปิดมีได้ใบเดียวจาก partial unique) |
| error case | `not_authenticated`, `account_not_active`, `not_eligible` (role ไม่ใช่ user), `already_seer`, `application_limit_reached`, `rate_limited` |

### B.6.2 `submit_seer_application`

| หัวข้อ | รายละเอียด |
|---|---|
| signature | `public.submit_seer_application() returns jsonb` (ไม่ต้องส่ง id — ใบเปิดมีใบเดียว) |
| ทำอะไร | หาใบ `draft` ของตัวเอง `for update` (ไม่มี → `not_found`; เป็น `submitted` อยู่แล้ว → `{replayed:true}`) → ตรวจความครบตาม B.5 ทุกข้อ → `status='submitted', submitted_at=now()` → insert `audit_log` (`actor_type='user'`, action `'seer_application.submitted'`) → notification ถึงตัวเอง (`'system'`: "ส่งใบสมัครแล้ว รอตรวจสอบ") |
| error case | `not_found`, `incomplete_application` (พร้อม detail ว่าขาด field/เอกสารไหน — ใส่ใน `errdetail` ให้ client แสดงได้), `invalid_price`, `invalid_skill` |
| เงิน | ไม่แตะ |

### B.6.3 `withdraw_seer_application`

`public.withdraw_seer_application() returns jsonb` — ใบเปิดของตัวเอง → `withdrawn`;
ไม่มีใบเปิด → `{replayed:true}`. ไม่แตะเงิน ไม่มี rate limit (ทำได้จำกัดโดยธรรมชาติ)

## B.7 RPC ฝั่งอนุมัติ (ยังไม่มี admin console — เรียกผ่าน Studio SQL editor)

### B.7.1 `admin_review_seer_application`

| หัวข้อ | รายละเอียด |
|---|---|
| signature | `public.admin_review_seer_application(p_application_id uuid, p_approve boolean, p_reviewer_label text, p_note text default null) returns jsonb` |
| สิทธิ์ | **`service_role` เท่านั้น** (revoke จาก public/anon/authenticated — แบบเดียวกับ `internal_credit_payment` ใน `20260826000008`) — Studio SQL editor รันเป็น postgres จึงเรียกได้; วันหน้า admin console เรียกผ่าน Edge Function ด้วย service key ได้เลยไม่ต้องแก้ |
| ทำใน transaction เดียว (approve) | 1) `p_reviewer_label` ต้องไม่ว่าง (บังคับ audit trail) 2) lock ใบสมัคร; status ต้องเป็น `submitted` (เป็น `approved` แล้ว → `{replayed:true}`) 3) mark เอกสารบังคับที่ pending ของบัญชีนั้นเป็น `approved` (reviewed_at/label) 4) `insert seer_profile` (account_id, display_name, bio, main_skill_id จากใบสมัคร, `approval_status='approved'`, `is_active=false`, `accepts_question=false`) 5) insert `seer_skill` จาก `skill_ids` (main ตาม `main_skill_id`) 6) insert `seer_service` (`'chat_question'`, `price_coin` จากใบสมัคร, **`is_enabled=false`** — seer ต้องเข้าแอปมาเปิดเองเมื่อพร้อม; trigger `validate_seer_service_price` ตรวจ bounds ซ้ำให้ฟรี) 7) **[แปรตามทางเลือก B.2 — ทาง 1]** `update account set role='seer'` 8) ใบสมัคร → `approved`, `decided_at`, `decided_by_label` 9) `audit_log` action `'seer.approved'` (actor_type `'admin'`, actor_id NULL, detail มี reviewer_label + application_id) 10) notification `'system'` ถึงผู้สมัคร ("ใบสมัครได้รับอนุมัติ เปิดรับงานได้เลย") + `outbox_event` `seer.approved` |
| ทำใน transaction เดียว (reject) | ใบสมัคร → `rejected` + `reject_reason=p_note` (บังคับไม่ว่าง) + decided_*; เอกสารที่ pending → `rejected` เฉพาะที่ระบุปัญหา (หรือคงไว้ pending ถ้าปัญหาอยู่ที่ field — ให้ p_note สื่อ); `audit_log` `'seer.rejected'`; notification บอกเหตุผล |
| idempotency | ใบที่ตัดสินแล้ว → `{replayed:true}` (approve ซ้ำไม่ insert ซ้ำเพราะเจอ status ไม่ใช่ submitted ก่อนถึง insert) |
| error case | `not_found`, `invalid_state`, `missing_reviewer_label`, `missing_reject_reason`, `profile_exists` (กันข้อมูลค้างผิดปกติ — มี seer_profile อยู่แล้วทั้งที่ใบเพิ่ง submitted) |
| เงิน | ไม่แตะ (wallet มีอยู่แล้วจาก `handle_new_user`) |

### B.7.2 `admin_review_seer_document` (แยกจากใบสมัคร — ใช้ตอนขอเอกสารใหม่เฉพาะใบ)

`public.admin_review_seer_document(p_document_id uuid, p_approve boolean,
p_reviewer_label text, p_reject_reason text default null) returns jsonb` —
service_role เท่านั้น; `pending → approved|rejected` + audit_log
(`'seer_document.approved'`/`'.rejected'`); rejected → notification บอกผู้สมัครให้อัปโหลดใหม่
(ใบสมัครที่ `submitted` ค้างอยู่**ไม่เด้งกลับอัตโนมัติ** — ผู้สมัครอัปโหลดแถวใหม่ได้เลย
เพราะเงื่อนไขเอกสารครบเช็คซ้ำตอน approve ใบสมัครเสมอ)

## B.8 การปิดร้าน/ลาออกของ seer ที่ approved แล้ว

พักชั่วคราว: มีอยู่แล้ว — `is_active=false` (owner update ผ่าน RLS เดิม) หยุดรับงานใหม่ทันที
(`submit_question` เช็คอยู่แล้ว) — ไม่ต้องสร้างอะไร

ลาออกถาวร: column ใหม่ `seer_profile.retired_at timestamptz null` + RPC:

### `retire_seer`

| หัวข้อ | รายละเอียด |
|---|---|
| signature | `public.retire_seer() returns jsonb` |
| สิทธิ์ | `authenticated` (ตรวจว่าเป็นเจ้าของ seer_profile ที่ approved) |
| เงื่อนไข | **ห้ามมีงานค้าง**: มี `question` ที่ตัวเองเป็น seer_id status ใน (`submitted`,`active`,`close_requested`) → raise `open_work_exists` พร้อมจำนวนใน errdetail — ให้ seer เคลียร์เอง (ตอบให้จบ/ปล่อยหมดอายุ) ก่อน **ไม่ auto-refund แทน** เพราะการลาออกไม่ควรเป็นปุ่มลัดยกเลิกงานหมู่ (ผู้ใช้ที่รอคำตอบอยู่โดนลอยแพเงียบ ๆ) |
| ทำอะไร | `retired_at=now(), is_active=false, accepts_question=false, accepts_appointment=false, accepts_tip=false` + ปิด `seer_service` ทุกแถว (`is_enabled=false`) + `audit_log` `'seer.retired'` |
| idempotency | retired อยู่แล้ว → `{replayed:true}` |
| เงิน | **ไม่แตะ** — `payable_coin` ค้างอยู่ในกระเป๋าตามเดิม รอระบบ payout (เฟสหน้า) มาถอน; ledger ไม่มีการย้ายใด ๆ ตอนลาออก |
| กลับมาเปิดใหม่ | เฟสนี้ทำผ่าน service role (ล้าง `retired_at` ใน Studio + audit_log) — self-service un-retire จงใจไม่ทำ (ดู B.12) |

## B.9 ผลกระทบต่อของเดิม (รวมทั้งฝั่ง onboarding)

| ของเดิม | ไฟล์ | แก้อย่างไร |
|---|---|---|
| `seer_profile` | `20260826000002` | `alter table add column retired_at timestamptz` |
| policy `seer_profile_public_select` | `20260826000006` | drop/create ใหม่: `using ((approval_status='approved' and retired_at is null) or account_id=(select auth.uid()))` — seer ลาออกแล้วหายจาก catalog แต่ยังเห็นโปรไฟล์ตัวเอง |
| `submit_question` | `20260827000002` | ใน `create or replace` เดียวกับที่เพิ่ม block เช็ค (A.7): เพิ่ม `and p.retired_at is null` ในเงื่อนไข `seer_unavailable` |
| `handle_new_user` | `20260826000001` | **ไม่แก้** (สร้าง user_profile+wallet ให้ทุกบัญชีอยู่แล้ว — ครอบคลุมผู้สมัคร seer) |
| `current_account_role`, policy `seer_skill_owner_insert`, `seer_service_owner_insert` | `20260826000001`, `20260826000006` | **ไม่แก้ภายใต้ทาง 1** (role ถูก flip เป็น 'seer' ตอนอนุมัติ ทำให้ policy เดิมทำงานถูกพอดี); ทาง 3 เท่านั้นที่ต้องรื้อ |
| `app_config` | seed ใน `20260826000011`/`20260827000002` | เพิ่ม key: `seer.application_required_documents` (`["national_id","portrait"]`, is_public=true — client ต้องรู้ว่าต้องแนบอะไร), `seer.application_max_total` (`5`, is_public=false), และ bucket ใหม่ใน `ratelimit.buckets` (B.10) |
| audit การแก้โปรไฟล์หลัง approve | ใหม่ | trigger `AFTER UPDATE OF display_name, avatar_url ON seer_profile` → insert `audit_log` action `'seer_profile.identity_changed'` (detail เก็บค่าเก่า/ใหม่) — คำตอบของโจทย์ "แก้โปรไฟล์แล้วกลายเป็นคนละคน": **เฟสนี้ไม่บังคับ re-approve** (ยังไม่มี admin console จะไป re-approve — จะกลายเป็นบล็อกรายได้ seer ด้วยคิวที่ไม่มีคนเคลียร์) แต่เก็บหลักฐานครบเพื่อ moderation ย้อนหลัง + rate limit `seer_profile_update` กันเปลี่ยนตัวตนรัว ๆ; re-approval จริงเป็นเฟสหน้าผ่าน `seer_application` ชนิด `update` (schema รองรับแล้วโดยเพิ่มค่า enum ทีหลัง) |
| Storage | ใหม่ (ทำใน migration ผ่าน `storage.buckets`/`storage.objects` policy หรือ dashboard — ระบุใน implementation notes ให้เลือกทางที่ reproducible คือ migration) | bucket `seer-documents` private + policies ตาม B.4 |
| `chata-database-design.md` §4.2.7 | docs | อัปเดต FK ของ `seer_document` เป็น account(id) + คอลัมน์ `reviewed_by_label` แทน `reviewed_by` uuid |

## B.10 Rate limit buckets (เพิ่มใน `ratelimit.buckets`)

```json
"seer_apply":          {"limit": 3,  "window_seconds": 86400},
"seer_document":       {"limit": 30, "window_seconds": 86400},
"seer_profile_update": {"limit": 20, "window_seconds": 3600}
```

- `seer_apply` นับเฉพาะการ**สร้างใบใหม่** (ไม่นับ save ซ้ำบนใบเดิม)
- `seer_document` บังคับผ่าน BEFORE INSERT trigger (B.4) เพราะ insert เป็น RLS ตรง
- `seer_profile_update` บังคับผ่าน trigger บน `seer_profile` (update เป็น RLS ตรงเช่นกัน) —
  BEFORE UPDATE เรียก `consume_rate_limit` เฉพาะเมื่อ column แสดงตัวตนเปลี่ยน

## B.11 Test cases (`db/tests/seer-onboarding.test.sql`)

Happy path:
1. user สร้าง draft → แนบเอกสารครบ → submit → admin approve → มี `seer_profile`
   (approved, is_active=false), `seer_skill` ครบตาม array, `seer_service`
   (is_enabled=false, ราคาตรงใบสมัคร), `account.role='seer'`, มี `audit_log` 2 แถว
   (submitted, approved), notification ถึงผู้สมัคร
2. seer ใหม่เปิด `is_active=true` + `accepts_question=true` + enable service →
   user อื่น `submit_question` สำเร็จ

State machine / negative:
3. submit ทั้งที่เอกสารบังคับไม่ครบ → `incomplete_application`; แนบครบแล้ว submit ผ่าน
4. submit ราคานอก bounds → `invalid_price`; skill_id ปลอม → `invalid_skill`
5. เปิดใบที่สองทั้งที่มี draft ค้าง → ชน partial unique (save คืนใบเดิมแทน ไม่ error)
6. rejected แล้วสมัครใหม่ → แถวใหม่สร้างได้ ประวัติเก่ายังอยู่; ครบเพดาน
   `seer.application_max_total` → `application_limit_reached`
7. `admin_review_seer_application` ซ้ำบนใบที่ approved แล้ว → `{replayed:true}`
   ไม่เกิด seer_profile/seer_skill/seer_service ซ้ำ
8. approve โดยไม่ส่ง reviewer_label / reject โดยไม่ส่งเหตุผล → error
9. บัญชีที่เป็น seer อยู่แล้วเรียก `save_seer_application` → `already_seer`
10. `withdraw` จาก submitted → withdrawn; withdraw ซ้ำ → replayed

RLS / สิทธิ์:
11. authenticated เรียก `admin_review_seer_application` ตรง → permission denied
12. insert/update `seer_application` ตรงจาก client → permission denied; อ่านใบคนอื่นไม่เจอ
13. `seer_document`: insert path ของบัญชีอื่น (object_key ไม่ขึ้นต้นด้วย uuid ตัวเอง) →
    CHECK ปฏิเสธ; อ่านเอกสารคนอื่นไม่เจอ; soft-delete หลัง approved → trigger ปฏิเสธ
14. ผู้สมัคร (role='user') ยังเพิ่ม `seer_skill`/`seer_service` ตรงไม่ได้ก่อนอนุมัติ
    (policy role='seer' เดิมต้องยังกันอยู่)

Retire / เงิน:
15. seer มีงานค้าง 1 ใบ เรียก `retire_seer` → `open_work_exists`; ปิดงานแล้วเรียกใหม่ → สำเร็จ,
    หายจาก catalog (select ในนาม user อื่นไม่เจอ), `submit_question` ใส่ seer นี้ →
    `seer_unavailable`, service ถูกปิดหมด
16. retire แล้ว `payable_coin` ไม่ขยับ, `job_reconcile_wallets` ไม่พบ drift
17. rate limit: สร้างใบใหม่ครั้งที่ 4 ใน 24 ชม. → `rate_limited`; upload เอกสารเกิน 30/วัน →
    `rate_limited`
18. แก้ `display_name` ของ seer ที่ approved → เกิด `audit_log`
    `'seer_profile.identity_changed'` พร้อมค่าเก่า/ใหม่

## B.12 สิ่งที่จงใจไม่ทำในเฟสนี้ (พร้อมเหตุผล)

- **admin console UI** — RPC ฝั่งรีวิวออกแบบให้เรียกจาก Studio ได้วันนี้ และเป็น API
  ให้ console ในอนาคตโดยไม่ต้องแก้ DB
- **re-approval เมื่อแก้โปรไฟล์สำคัญ** — เก็บ audit + rate limit แทน (เหตุผลใน B.9);
  schema `seer_application` เผื่อชนิด `update` ไว้แล้ว
- **`seer_level` / ส่วนแบ่งต่อ seer** — ยังใช้ `seer.default_revenue_share_bps` ตาม
  comment ใน `20260826000002`; onboarding ไม่พึ่งมัน
- **payout / KYC ระดับธนาคาร** — `bank_book` อัปโหลดได้แต่ไม่บังคับ จนกว่าเฟส payout
  (design brief §9 ระบุว่าข้อกำหนดไทยยังไม่เคาะ)
- **self-service un-retire** — เคสหายาก ให้ service role ทำ พร้อม audit; กันความซับซ้อน
  ของ state ที่ยังไม่มีผู้ใช้จริงมายืนยันว่าจำเป็น
- **OCR/automated KYC ตรวจเอกสาร** — ตรวจมือผ่าน Studio พอสำหรับ scale ปัจจุบัน
- **การลบไฟล์จริงใน storage เมื่อ soft delete** — เก็บไว้ตามนโยบาย retention
  (ไปเข้ากับงาน `account_deletion_request` เฟสหน้า)

---

# C. ลำดับ implement ที่แนะนำ (หนึ่ง migration ต่อหนึ่งก้อน ตาม pattern เดิม)

1. `2026xxxx_block_relation.sql` — ตาราง + RLS + grants + แก้ `question_cancel_reason_chk`
   + replace `internal_refund_question` + RPC block/unblock + rate limit config
2. `2026xxxx_seer_onboarding_tables.sql` — `seer_application`, `seer_document`,
   `seer_profile.retired_at`, triggers, RLS, grants, config keys, storage bucket+policies
3. `2026xxxx_seer_onboarding_rpc.sql` — RPC ฝั่งผู้สมัคร + ฝั่งรีวิว + `retire_seer`
   + replace `submit_question` (รวม block เช็ค + retired เช็คในตัวเดียว — replace ครั้งเดียว)
   + replace policy `seer_profile_public_select`
4. เทส 2 ไฟล์ใหม่ใน `db/tests/`
5. อัปเดต `chata-database-design.md` (§4.1.1 บันทึกทางเลือกที่ user เคาะ, §4.2.7, §4.14.1)

# D. เรื่องที่ต้องให้ user เคาะก่อนลงมือ

1. **โมเดล user/seer (B.2)** — ผมแนะนำทาง 1 (one-way promotion) แต่มันผ่อนคลาย
   ข้อตัดสินใจ "ห้ามสลับ role" ใน design doc เดิม จึงต้องได้คำยืนยันก่อน implement ข้อ 7
   ของ `admin_review_seer_application`
2. **ยืนยันกฎ blocker-forfeits (A.5)** — โดยเฉพาะช่อง "seer บล็อกตอน active = คืนเงิน user"
   (ทางเลือกอีกฝั่งคือจ่าย seer ซึ่งเปิดช่องฟาร์ม — ผมยืนยันไม่แนะนำ) เพราะเป็นนโยบายเงิน
   ที่ user ต้องอธิบายกับหมอดูจริงได้
3. **เอกสารบังคับตอนสมัคร** — เสนอ `national_id + portrait`; ถ้า user มองว่าแรงไป
   ช่วง soft launch จะลดเหลือ `portrait` อย่างเดียวก็แก้ที่ config key เดียว ไม่แตะ schema
4. **ข้อความ UI ฝั่ง seer ตอนกดบล็อก** (A.5) — ต้องบอกชัดว่าบล็อกตอนมีงานค้างจะคืนเหรียญ
   ให้ผู้ถาม — เป็น requirement ต่อทีม iOS ไม่ใช่ DB แต่ถ้าไม่มีจะเกิด dispute แน่นอน
