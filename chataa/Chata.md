---
tags: [project, chata, horo, ios, swift, supabase, astrology]
status: active
started: 2026-08-26
updated: 2026-08-29
updated_session: 2026-08-28 (เฟส 3 — ต่อ iOS เข้า Supabase จริง)
---

# Renamed Hub

> [!info] Product name update — 2026-08-29
> The app/product name is now **Chataa**. Use [[Chataa]] as the current hub.
> This note remains as historical context for the earlier `Chata` / `Horo` naming period.

# Chata / Horo — แอปดูดวง

Hub note ของโปรเจคแอปดูดวง/ปรึกษาหมอดูสำหรับตลาดไทย
สร้างใหม่ทั้งหมด (clean-room) โดยยืม **โครงระบบเชิงตรรกะ** ที่ reverse มาจาก DuangLive 1.5.35
เพื่อให้ได้ระบบบัญชี/ธุรกรรมที่แน่นหนาตั้งแต่วันแรก — ไม่ใช่การ copy schema จริง

> ⚠️ **ชื่อโปรเจคยังไม่นิ่ง** — งาน database ใช้ `chata` (`app.chata.coin150`, `chata://wallet`)
> แต่ repo/แอปใช้ `horo` (`HoroTest`, `com.pacharapol.HoroTest`)
> **ต้องเลือกอันเดียวก่อนทำ IAP** เพราะ bundle id ผูกกับ IAP product id แก้ทีหลังเจ็บ

> [!info] ประเมินความคืบหน้าล่าสุด (2026-08-29)
> **scope v1 เต็ม ~25–30%** · ถ้าตัดเหลือ MVP แชทถามหมอดูแบบจ่ายเงิน ~55–60% · เฟส 3 ~95%
> รายละเอียดและหลักฐาน: [[Chata Progress 2026-08-29]]
> ~~จุดที่ใหญ่ที่สุด: หมอดูยังเอาเงินออกไม่ได้เลย~~ → **แก้แล้วท้ายวันเดียวกัน**
> เฟส 4 ticket 01–04 เสร็จ: [[Chata Phase 4 Payout and Call]] · payout ครบวงจรบนเครื่อง
> (ยังไม่ขึ้น cloud · หน้าจอยังไม่มีใครเห็นด้วยตา)
> ตัวเลขปรับใหม่: scope v1 เต็ม **~30–33%** · MVP **~65%**

## ที่อยู่ของงาน

| อะไร | ที่ไหน |
|---|---|
| local repo | `~/private/project-chata` (อยู่บน `main` แล้ว) |
| GitHub | https://github.com/ternnn-ps/horo-app (**private, เจ้าของคือคนอื่น**) |
| PR ที่ merge แล้ว | [#1](https://github.com/ternnn-ps/horo-app/pull/1) · [#2](https://github.com/ternnn-ps/horo-app/pull/2) — **งาน database ทั้งหมดอยู่บน `main` แล้ว** |
| Supabase project | `chata-dev` ref `ycbuwrhnhdsbutbfzsvn` · Singapore · free tier |
| dbdiagram | https://dbdiagram.io/d/6a8eecdca1687f63dbda3313 |
| reverse artifacts | `~/private/reverse-dounglive` — ดู [[DuangLive 1.5.35 Android Reverse]] |

## ⚠️ เรื่องทีม (สำคัญ)

**ไม่ใช่โปรเจคเดี่ยว** — repo เจ้าของคือ `ternnn-ps`, commit ทั้งหมดมาจาก
**Pacharapol Sukchom** `<pacharapol.s@motiftech.com>` เรามีสิทธิ์ push แต่ไม่ใช่ admin

→ **ห้าม push เข้า `main` ตรง ๆ** ใช้ branch + PR เสมอ

มี iOS prototype ชื่อ `HoroTest` อยู่แล้ว (SwiftUI, CRUD เก็บในเครื่อง, ไม่มี backend, min iOS 26.1)

## สถานะ (2026-08-27 — ดูสถานะล่าสุดที่กล่องบนสุด)

**เฟส database เสร็จสมบูรณ์** — ขึ้น cloud แล้ว ทดสอบผ่าน

| Deliverable | สถานะ |
|---|---|
| design spec 57 ตาราง (`docs/specs/chata-database-design.md`) | ✅ 2,133 บรรทัด |
| DBML (`db/chata.dbml`) | ✅ 58 Table / 80 Ref / 15 TableGroup |
| Mermaid ERD (`docs/specs/chata-erd.md`) | ✅ 26 diagram |
| migration เฟส 1 — 18 ตาราง | ✅ 13 ไฟล์ |
| `supabase db push` ขึ้น cloud | ✅ **20/20 sync** |
| regression test 6 ชุด (`db/tests/*.test.sql`) | ✅ ผ่านหมด ไม่มี warning |
| **`verify-iap` Edge Function** | ✅ ตรวจลายเซ็นจริงได้แล้ว + ชุดทดสอบพิสูจน์ว่าทำงาน (ยังไม่ deploy) |
| `push-sender`, `outbox-dispatcher` | ⬜ รอ $99 / รอ push |
| **iOS ต่อ Supabase จริง** | ✅ login/กระเป๋า/ซื้อคำถาม/แชท/ปิดงาน เดินครบจากในแอป — ดู [[Chata iOS Phase 3]] |
| **Supabase SDK (Auth + Realtime)** | ✅ ลงเฉพาะสอง product · แก้บั๊ก session หลุด + 401 หลัง 1 ชม. |
| **เทส iOS 20 ตัว** | ✅ รวม integration ที่ยิง Supabase จริงจากในโปรเซสแอป |
| **fixture dev ด้วยคำสั่งเดียว** (`scripts/seed-dev-fixture.sh`) | ✅ ผู้ใช้ + หมอดูอนุมัติแล้ว + เหรียญ + บัญชีคนนอก |
| **integration test ผ่าน REST จริง** (`scripts/test-rest-integration.sh`) | ✅ 21 ข้อ — money loop ครบวงด้วยสิทธิ์ authenticated |
| **Realtime publication** (`20260827000008`) | ✅ question + question_message เด้งจริง พิสูจน์ด้วย WebSocket |
| **Broadcast domain event** (`20260827000009`) | ✅ `status_changed` แบบ DuangLive — server กำหนด payload เอง |
| **migration ขึ้น cloud** | ✅ 22/22 sync (push 2026-08-28) |
| **smoke test บน cloud** | ✅ seed + REST 23 + iOS 20 ผ่านบน chata-dev จริง |
| **เฟส 2 — cron ปลดล็อก escrow** | ✅ 4 job + test ผ่าน ขึ้น cloud แล้ว |
| **เฟส 2 — rate limit** | ✅ 3 bucket + 7 test ผ่าน ขึ้น cloud แล้ว |
| **เฟส 2 — block user** | ✅ blocker forfeits + 8 test ผ่าน |
| **เฟส 2 — สมัครเป็นหมอดู** | ✅ one-way promotion + 12 test ผ่าน |
| เฟส 2 ที่เหลือ (call, appointment, review, payout) | ⬜ |


## ▶️ กลับมาทำต่อยังไง (อ่านตรงนี้ก่อน)

```bash
cd ~/private/project-chata
supabase start                     # ปลุก local stack (Docker ต้องเปิดอยู่)
supabase db reset                  # สร้าง schema ใหม่จาก migration ทั้ง 20 ไฟล์

# ถ้าจะทดสอบ Edge Function ด้วย (เติมเหรียญ / ตรวจใบเสร็จ)
supabase functions serve --no-verify-jwt --env-file supabase/functions/.env.local &
./scripts/test-iap-verifier.sh     # พิสูจน์ว่าตัวตรวจลายเซ็นยังทำงาน
```

> `supabase/functions/.env.local` ถูก gitignore ไว้ ถ้าหายให้สร้างใหม่:
> ```
> ALLOW_UNVERIFIED_IAP=true
> APPLE_BUNDLE_ID=app.chata.dev
> ```

รัน regression test ทั้ง 5 ชุด (ต้องไม่มี WARNING/ERROR สักบรรทัด):

```bash
for t in money-flow lifecycle-jobs rate-limit block seer-onboarding iap-credit; do
  supabase db reset >/dev/null 2>&1
  echo -n "$t → "
  docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
    -f - < db/tests/$t.test.sql 2>&1 | grep -cE "WARNING|ERROR|ช่องโหว่"
done
```

**ธงต่อไป (อัปเดต 2026-08-28):**

1. ticket 08 ปุ่มเติมเหรียญ dev · ticket 09 ลบ domain เก่า · ticket 10 Google (รอ OAuth credential)
2. เปิด PR (ticket 11 — smoke test บน cloud ผ่านแล้ว)
3. เคาะชื่อ `chata` vs `horo` — ยังไม่ได้คุยกับเพื่อนร่วมทีม

<details><summary>ธงเดิมก่อนเฟส 3</summary>

**ธงต่อไป 3 อย่าง เรียงตามความเร่งด่วน:**

1. **เคาะชื่อโปรเจค `chata` vs `horo`** ← ทำก่อนแตะโค้ดแอป
   bundle id ผูกกับ IAP product id ที่ seed ไว้ (`app.chata.coin150`) แก้ทีหลังเจ็บ
2. **คุยกับเจ้าของ repo เรื่อง PR #1** — `HoroTest` จะต่อยอดหรือเขียนใหม่
   (ตอนนี้เป็น mock เก็บข้อมูลในเครื่อง ไม่มี backend เลย)
3. **เริ่ม iOS** — Xcode 26.6 + simulator พร้อมแล้ว (ตรวจ `xcrun simctl list devices available`)

</details>

**สิ่งที่ต้องทำเองก่อนเปิดให้คนใช้จริง (ไม่ใช่งานโค้ด):**
- ใส่คำเตือนใน UI ก่อนกดบล็อก (ดูหัวข้อ ⛔ ด้านล่าง)
- ซื้อ Apple Developer Program $99/ปี ตอนจะขึ้น TestFlight
- เติมเหรียญตอนพัฒนา (ไม่ต้องมี IAP): `select dev_grant_coins('<account_id>', 1000);`
  ทำงานเฉพาะตอน `payment.iap_mode = 'local_test'` — สลับเป็น production แล้วปิดตัวเอง
- `verify-iap` กันเหรียญฟรีสองชั้น (config + env `ALLOW_UNVERIFIED_IAP`)
  **ห้ามตั้ง env ตัวนี้บน cloud** — ทดสอบแล้วว่าถ้าไม่ตั้ง จะปฏิเสธทุกคำขอ
  ทดสอบตัวตรวจลายเซ็น: `./scripts/test-iap-verifier.sh`
- อนุมัติหมอดูยังต้องทำมือใน Supabase Studio:
  `select admin_review_seer_application('<application_id>', true, 'ray');`
  ดูคิว: `select * from seer_application where status='submitted';`


## ⚠️ ช่องว่างระหว่าง Swift model กับ schema จริง (ยังไม่ได้คุยกัน)

เพื่อนร่วมทีมเพิ่ม `HoroTest/Models/HoroDomainModels.swift` (394 บรรทัด) +
`SupabaseHoroDataService.swift` (ยังเป็น stub ทุก method `throw unavailable()`)
ตัว service ยังไม่ต่อจริงเลยยังไม่พัง **แต่ model กำหนดรูปร่างไว้แล้วและไม่ตรงกับ DB**

| Swift model | ตารางจริง | ปัญหา |
|---|---|---|
| `ReadingRequest` | `question` | **ไม่มีเรื่องเงินเลย** — ขาด `price_coin`, `client_request_id` (idempotency), `expires_at` ซึ่งเป็นหัวใจของ escrow |
| `ChatThread` (มี `unreadForCustomer/Seer` เป็นตัวนับ) | **ไม่มีตารางนี้** | ข้อความห้อยกับ `question` ตรง ๆ; การอ่านถึงไหนใช้ cursor `user_last_read_message_id` ไม่ใช่ตัวนับ |
| `ChatMessageRecord.id: UUID` | `question_message.id bigint` | ต้องเรียงลำดับได้เพื่อให้ cursor ทำงาน |
| `SeerProfile.id` + `userId` แยกกัน | `seer_profile.account_id` เป็น PK | 1:1 กับ account ไม่มี id แยก |
| `SeerProfile.isOnline` | **จงใจไม่เก็บใน profile** | presence ต้องเป็น ephemeral ผ่าน Realtime — หลักฐานจาก reverse ชี้ว่า approval/active/reply/online เป็นแกนอิสระ |
| `skills: [String]`, `styles: [String]` | `seer_skill` → `skill(id)` | ของเรา normalize แล้ว |
| `rateLabel: String` | `seer_service.price_coin bigint` | ราคาต้องมาจาก server เสมอ ไม่ให้ client จัดรูปแบบเอง |

→ **ต้องคุยกันก่อนที่เขาจะลงมือต่อ `SupabaseHoroDataService` จริง** ไม่งั้นเสียเวลาสองฝั่ง

## ข้อตัดสินใจที่เคาะแล้ว

- **Supabase** (cloud, free tier ก่อน — ยังไม่มีทุน) · **iOS ก่อน → Android ตาม DB เดียวกัน**
- **Scope v1: full parity** + 2 domain ใหม่ (horoscope/AI, live stream + gift)
- **เฟส 1 ตัดเหลือ 18 ตาราง** — ไม่ build ครบ 57 ตารางก่อนมีผู้ใช้คนแรก
- **auth เฟส 1 = email + password** (Sign in with Apple ต้องมี Developer Program $99 ซึ่งยังไม่ซื้อ)
- **payment เฟส 1 = Apple IAP อย่างเดียว** (ทดสอบด้วย StoreKit local ใน Xcode ไม่ต้องจ่าย $99)
- **สถาปัตยกรรม Hybrid** — เส้นแบ่งคือ "operation นี้แตะเงินไหม" ดู [[Chata Architecture]]

## บทเรียน / จุดที่เกือบพลาด

**Realtime: `phx_reply` ตอบ ok ไม่ได้แปลว่าพร้อมรับ event**
ต้องรอเฟรม `system` ที่บอก "Subscribed to PostgreSQL" ก่อน ถ้าเขียนข้อความก่อนหน้านั้น
event หายเงียบ ไม่มี error ใด ๆ — ดูเหมือน Realtime พังทั้งที่ config ถูกหมด
เสียเวลาไล่ publication/RLS อยู่นานทั้งที่ต้นเหตุคือ race ในตัวเทสเอง

**publication ของ Supabase Realtime เริ่มต้นว่างเปล่า**
`supabase_realtime` มีอยู่แต่ไม่มีตารางสักตัว ต้อง `alter publication ... add table` เอง
ไม่มีอะไรเตือน แค่ไม่มี event มาเฉย ๆ

**`service_role` ไม่มี SELECT บน `seer_application` / `seer_document`**
(20260827000007 grant แค่ execute ของ RPC) → admin console หรือ Edge Function
ที่จะ query คิวใบสมัครในอนาคตจะเจอ 42501 · fixture เลี่ยงได้เพราะ RPC คืน
`application_id` มาให้อยู่แล้ว แต่ต้องแก้ตอนทำ admin console

**เทสที่กินทรัพยากรของตัวเองต้องเรียก fixture เองทุกรอบ**
ชุด REST หักเหรียญจริงทุกครั้งที่รัน รอบสองเลยล้มเพราะเหรียญไม่ถึงเกณฑ์
แก้ด้วยการให้ตัวเทสเรียก fixture ก่อนเสมอ (fixture เติมกลับให้ถึงเป้า + ล้าง rate limit counter
ไม่งั้นรันเกิน 10 ครั้ง/ชม. จะติดเพดานตัวเอง)

**bash 3.2 ของ macOS ไม่ multibyte-safe ใน `$VAR` ที่ตามด้วยอักษรไทย/ยูนิโค้ด**
`"$FOO→"` ถูกอ่านเป็นชื่อตัวแปร `FOO→` แล้ว unbound — ต้องเขียน `"${FOO}→"` เสมอ


**payment: อย่ายุบ "วิธีจ่าย" กับ "ใครเคลียร์เงิน" เป็น field เดียว**
ตลาดไทย method เดียวกันวิ่งได้หลาย PSP — PromptPay ผ่านได้ทั้ง ChillPay และ ePOS,
บัตรผ่านได้ทั้ง ChillPay และ SiamPay, TrueMoney ผ่านได้ทั้ง ChillPay และ MOL
→ แยก `method` กับ `psp_code` ตั้งแต่แรก ไม่งั้นตอนย้าย PSP ต้อง backfill

**approval / active / reply_enable / online เป็นแกนอิสระ ห้ามยุบเป็น enum เดียว**
หลักฐาน live จาก DuangLive: เจอ `online_status=0` พร้อม `active=1`, `reply_enable=1`

**iOS-first เจอกำแพง Apple IAP หัก 30%** (15% ถ้า Small Business Program)
DuangLive เป็น Android-first ถึงมี gateway ไทยครบ 8 เจ้า — พอมาทาง iOS
AI reading กับ gift หนีไม่พ้น IAP แน่นอน ส่วนโทร/แชทสดตัวต่อตัวอาจเข้าข้อยกเว้น 3.1.3(e)
→ **ต้องคำนวณ revenue share ใหม่บนฐาน 30% ไม่ใช่ 3% ของ PSP**

**RLS ไม่กัน TRUNCATE** — default privilege ของ Postgres แจก `TRUNCATE/REFERENCES/TRIGGER`
ให้ `anon` กับทุกตารางที่สร้างใหม่ ต้อง `ALTER DEFAULT PRIVILEGES ... REVOKE ALL` ปิดที่ต้นทาง

**logic เรื่องเงินต้องอยู่ที่เดียว** — ตอนทำ cron ต้องดึง settle/refund ออกมาเป็น
`internal_settle_question` / `internal_refund_question` แล้วให้ทั้ง RPC และ cron เรียกตัวเดียวกัน
ถ้าปล่อยให้ cron เขียนสูตรส่วนแบ่งเองจะ drift กับ RPC แน่นอน

**อย่าให้ RPC เชื่อ payload ในสิ่งที่ server รู้อยู่แล้ว**
`internal_credit_payment` เดิมรับ `provider` จาก payload และ credit ได้แม้ไม่มีใบเสร็จ
→ ใบเสร็จแพ็ก 50 เหรียญเคลมเป็น 150 ได้ แก้แล้วใน `20260826000013`

**หารส่วนแบ่งด้วย integer division ทำให้ขา ledger เป็นศูนย์แล้วชน `amount <> 0`**
ที่ share 70% คำถามราคา 1 เหรียญได้ `floor(0.7) = 0` → settle ล้มถาวร cron วนซ้ำตลอดกาล
เจอเฉพาะตอนมีราคาจริง ไม่เจอตอนเทสต์ด้วยราคากลม ๆ → ต้องข้ามขาที่เป็นศูนย์เสมอ
(`20260827000003`)

**การทดสอบว่า "ของปลอมถูกปฏิเสธ" อย่างเดียว พิสูจน์อะไรไม่ได้เลย**
โค้ดที่พังก็ปฏิเสธทุกอย่างเหมือนกัน แล้วเทสต์จะเขียว — **ต้องทดสอบฝั่งบวกคู่กันเสมอ**
เจอสองรอบตอนทำ IAP: `@apple/app-store-server-library` และ `pkijs.setEngine`
ทั้งคู่รันบน Supabase Edge Runtime (Deno) ไม่ได้ แต่ทำให้ระบบดู "ปลอดภัย"
ทั้งที่ใบเสร็จจริงของ Apple ก็ไม่ผ่าน
→ วิธีพิสูจน์: สร้าง CA เองครบ 3 ชั้น ทดสอบว่า chain ที่ถูกต้อง**ถูกยอมรับ**ด้วย

**Apple Root CA G3 เป็น P-384 ไม่ใช่ P-256**
ถ้าเขียนโค้ดรองรับแต่ P-256 จะพังเฉพาะตอนเจอใบเสร็จจริง ซึ่งสายเกินไป
→ ชุดทดสอบต้องมีข้อที่ verify cert ของ Apple เองด้วย

**`revoke all on function ... from public` ตัดสิทธิ์ `service_role` ไปด้วย**
Postgres ให้ EXECUTE กับ PUBLIC เป็นค่าเริ่มต้น และ service_role อาศัยก้อนนั้นอยู่
→ Edge Function เรียก RPC ไม่ได้เลยสักตัว ต้อง `grant execute ... to service_role` คืน
**ไม่มีอาการตอนเทสต์ เพราะเทสต์รันเป็น `postgres` = เจ้าของ function**
→ บทเรียน: ทดสอบด้วยสิทธิ์เจ้าของฐานข้อมูล พิสูจน์เรื่องสิทธิ์ไม่ได้เลย ต้องยิงผ่าน API จริง
(`20260827000007`)

**`text[] || 'literal'` ใน plpgsql — Postgres ตีความ literal เป็น array ไม่ใช่ element**
ได้ error `malformed array literal` ต้อง cast `::text` เสมอ
พังเฉพาะ error path (เส้นที่บอกผู้ใช้ว่ากรอกอะไรไม่ครบ) จึงไม่เจอถ้าเทสต์แต่ happy path

**`information_schema.role_table_grants` ไม่โชว์ column-level grant**
เกือบรายงานผิดว่า "policy มีแต่ grant ไม่มี" — ต้องดู `role_column_grants` ด้วย

## ⛔ ยังห้ามเปิดให้ผู้ใช้จริง

เฟส 1 ยังไม่มี:
- ~~cron auto-refund / auto-close~~ ✅ **แก้แล้ว** (`20260827000001`) — 4 job:
  refund_unanswered (10 นาที) · autoclose_stale (15 นาที) · expire_payment_orders (15 นาที) ·
  reconcile_wallets (ทุกวัน 02:00 ไทย)
- ~~rate limit~~ ✅ **แก้แล้ว** (`20260827000002`) — submit_question 10/ชม. · ข้อความ 120/ชม. · close 60/ชม.
  ปรับเพดานได้ที่ `app_config` key `ratelimit.buckets` ไม่ต้อง migration
  ⚠️ จำกัด *งานที่สำเร็จ* ไม่ใช่จำนวนครั้งที่ยิง — กัน DoS จริงต้องทำที่ขอบ ไม่ใช่ใน DB
- ~~block_relation~~ ✅ **แก้แล้ว** (`20260827000004`)
- ~~เส้นทางสมัครเป็นหมอดู~~ ✅ **แก้แล้ว** (`20260827000005`)
- **admin console** — ตอนนี้อนุมัติหมอดูต้องรันคำสั่งใน Supabase Studio:
  `select admin_review_seer_application('<id>', true, 'ชื่อผู้อนุมัติ');`
- **ปุ่ม "รายงาน" แยกจากบล็อก** — ตอนนี้คนถูกคุกคามที่กดบล็อกเองต้องเสียเงินด้วย
  (user ยืนยันรับได้ในเฟสนี้ แต่ต้องมีคำเตือนใน UI) ทางแก้ต้องรอ admin console

`20260826000011_seed_dev.sql` เป็น migration ปกติ → **ต้องย้ายออกก่อนสร้าง project prod**
ไม่งั้นข้อมูลทดสอบขึ้น prod

## เรื่องที่ยังไม่เคาะ

- ชื่อโปรเจค `chata` vs `horo` (**เร่งด่วนสุด**)
- **การ map ระหว่าง Swift model กับ schema** (ดูตารางด้านบน) — เร่งด่วนพอ ๆ กัน
- ~~โมเดล role user/seer~~ ✅ เคาะแล้ว: **one-way promotion** อนุมัติแล้ว flip เป็น seer ถาวร
- `HoroTest` จะต่อยอดหรือเขียนใหม่ (ตอนนี้เป็น mock ไม่มี backend)
- bundle id — `com.pacharapol.HoroTest` เป็นของส่วนตัวคนอื่น
- บัญชี user/seer แยกกันคนละ account หรือสลับ role ได้ (ตอนนี้ออกแบบเป็นแยก)
- คำถามค้าง auto-close แล้ว settle ให้ seer หรือ refund ให้ user (ตอนนี้เลือก settle)
- media provider สำหรับ call + live (เสนอ LiveKit Cloud)
- AI provider + ราคา coin ต่อ reading + free quota
- อัตราแปลง coin → THB ตอน payout, ค่าธรรมเนียม, หัก ณ ที่จ่าย (ต้องปรึกษาบัญชี)
- ระดับ KYC ของ seer, commission ต่อ level
- PSP เจ้าแรก (ถ้า iOS ใช้ IAP อย่างเดียวช่วงแรก → ยังไม่ต้องเลือก)

## Related

- [[Chata Progress 2026-08-29]] — ประเมิน % แบบอิงหลักฐาน (ตาราง 22/48–52, View ต่อจริง 12–15/80)
- [[Chata Phase 4 Payout and Call]] — spec + 11 ticket: ปิดวงจรเงินก่อน แล้วต่อด้วยโทรคุยดูดวง

- [[Chata iOS Phase 3]] — งานต่อ iOS เข้า Supabase, ข้อตัดสินใจเรื่อง SDK, บทเรียนจากการเทส
- [[Chata Architecture]] — โครง frontend/backend, ทำไม mobile ต่างจาก web
- [[DuangLive 1.5.35 Android Reverse]]
- [[DuangLive Security Audit]]
