# Chata — Database Design Specification (v1)

> เอกสารนี้คือ design spec ฉบับเต็มของ database สำหรับ Chata บน Supabase (Postgres)
> อ่านคู่กับ `00-design-brief.md` ซึ่งเป็น source of truth ของข้อตัดสินใจที่เคาะแล้ว
> เอกสารนี้ละเอียดพอให้ derive DBML / Mermaid ERD / SQL migration ได้โดยไม่ต้องเดา

---

## ส่วนที่ 1 — บทนำ

### 1.1 ขอบเขต

- ออกแบบ logical + physical schema ของ Postgres ทั้งหมดสำหรับ Chata v1:
  ทุก parity domain (identity, seer catalog, consultation, appointment, call, wallet/ledger,
  payment, voucher/referral, seer earning/payout, review, block, notification/outbox, moderation)
  บวก 2 domain ใหม่ (horoscope/AI, live stream/gift)
- นิยาม transaction boundary, RPC `SECURITY DEFINER` contract, Edge Function ที่ต้องมี
- RLS strategy (policy intent — ไม่ใช่ SQL policy เต็ม), realtime mapping, outbox/cron,
  index/partition plan, data lifecycle/PDPA, cross-platform contract

### 1.2 Non-goals

- **ไม่ใช่** SQL migration จริง (จะ derive จากเอกสารนี้ภายหลัง)
- **ไม่ใช่** โค้ด Swift/Kotlin หรือ API DTO spec ของ client
- **ไม่เขียน** RLS policy เต็มทุกบรรทัด — ระบุเป็น posture + policy intent
- **ไม่ตัดสิน** เรื่องที่ brief ระบุว่ายังไม่เคาะ (media provider, AI provider, ระดับ KYC) —
  ออกแบบ schema ให้รองรับทุกทางเลือกแล้วยกไปส่วนที่ 14

### 1.3 สมมติฐาน

- Supabase cloud, เริ่ม free tier, Postgres 15+ พร้อม extension: `pg_cron`, `pg_net`,
  `pgcrypto` (`gen_random_uuid()` เป็น built-in อยู่แล้ว)
- Auth ใช้ `auth.users` ของ Supabase (phone OTP, Apple, Google, email) — เราไม่สร้างตาราง
  session/refresh token/OTP เอง
- Client คือ iOS (Swift) ก่อน, Android ตาม — ใช้ contract เดียวกัน, state ทั้งหมดอยู่ฝั่ง server
- เงินในระบบ = **coin** (หน่วยภายใน, integer) และ **fiat THB** (integer satang) เท่านั้น
- Media (call/live video) ใช้ provider ภายนอก — DB เก็บเฉพาะ metadata และ token audit

### 1.4 คำเตือน clean-room

เอกสารนี้ออกแบบ **ระบบใหม่ทั้งหมด** สิ่งที่ยืมมาจากงาน reverse DuangLive 1.5.35 คือ
*โครงสร้างเชิงตรรกะของ domain ที่สังเกตได้จาก client contract* เท่านั้น (มี flow อะไร,
operation ไหนเป็น financial-write, state machine เดินยังไง) — **ไม่ใช่** schema จริง,
ชื่อตารางจริง, หรือ business rule ภายในของ DuangLive ซึ่งไม่มีทางรู้ได้จาก APK
ทุกตารางในเอกสารนี้เขียนในเชิง "สังเกตพฤติกรรมจาก client contract แล้วเราออกแบบใหม่เป็นแบบนี้"

---

## ส่วนที่ 2 — หลักการออกแบบ

### 2.1 Naming convention

- **snake_case ทั้งหมด** — ตาราง, column, function, index, enum value
- **ชื่อตารางเป็นเอกพจน์** (`question`, `ledger_entry`, `payment_order`) — สอดคล้องกับ
  แนวคิด "หนึ่งแถว = หนึ่ง entity" และตัดปัญหาพหูพจน์ภาษาอังกฤษ (person/people)
- FK column ตั้งชื่อ `<referenced_entity>_id` (`seer_id`, `question_id`); ถ้าอ้าง `account`
  ในบทบาทเฉพาะ ใช้ชื่อบทบาท (`user_id`, `seer_id`, `sender_id`, `reviewed_by`)
- Index ตั้งชื่อ `<table>_<columns/purpose>_idx`, unique constraint `<table>_<columns>_key`,
  CHECK constraint `<table>_<rule>_chk`
- RPC function ขึ้นต้นด้วยกริยา (`submit_question`, `charge_call`); function ภายในที่ client
  เรียกไม่ได้ prefix `internal_` (`internal_post_ledger`)
- ทุกตาราง app อยู่ schema `public`; view ที่เปิดให้ client อ่านข้อมูล money อยู่ schema
  `public` เช่นกันแต่ prefix `v_` (`v_my_wallet`, `v_my_coin_history`)

### 2.2 Canonical types

| ชนิดข้อมูล | Type ที่ใช้ | เหตุผล |
|---|---|---|
| PK ของ aggregate/entity ที่ client อ้างถึง | `uuid DEFAULT gen_random_uuid()` | กัน enumeration, สร้างจาก client ไม่ได้ชนกัน, สอดคล้อง `auth.uid()` |
| PK ของตาราง append-only ปริมาณสูงที่ access ด้วย cursor | `bigint GENERATED ALWAYS AS IDENTITY` | แถวเล็กกว่า (8 vs 16 byte), index locality ดี, ใช้เป็น keyset cursor ได้ตรง ๆ — ใช้กับ `question_message`, `appointment_message`, `ledger_entry`, `notification_inbox`, `gift_transaction`, `audit_log`, `outbox_event`, `seer_earning` |
| PK ของ lookup ขนาดเล็ก | `integer GENERATED ALWAYS AS IDENTITY` | `skill`, `service_type`, `seer_level`, `review_tag`, `gift` |
| เวลา | `timestamptz` **เสมอ** | ไม่มีข้อยกเว้น; `timestamp` เปล่าห้ามใช้ |
| วันเกิด/วันที่ล้วน | `date` | birthdate, horoscope date ไม่มี timezone semantics |
| เวลาในตาราง schedule | `time` + `smallint day_of_week` | ตารางเวลาประจำสัปดาห์ |
| เงิน coin | `bigint` (หน่วย coin เต็ม) | ไม่มีทศนิยม, ห้าม float |
| เงิน fiat | `bigint` หน่วย **satang** + `currency char(3)` (v1 = 'THB') | integer minor unit ตาม brief |
| enum/status | **`text` + CHECK constraint** | ดูเหตุผล 2.3 |
| ข้อความอิสระ | `text` (+ CHECK ความยาวเมื่อจำเป็น) | ไม่ใช้ `varchar(n)` |
| payload โครงสร้างหลวม | `jsonb` | outbox payload, notification payload, AI content |
| hash | `bytea` (SHA-256) | token/code hash — ไม่เก็บ plaintext |

**กฎ id เพิ่มเติม:** ห้ามใช้ค่า PK ทำ arithmetic หรือสื่อความหมายลำดับทางธุรกิจ
(ยกเว้น keyset pagination บน bigint identity ซึ่งเป็นลำดับ insert เท่านั้น)

### 2.3 ทำไม text + CHECK ไม่ใช่ Postgres enum

ตัดสินใจ: **สถานะทุกตัวเป็น `text NOT NULL` + `CHECK (status IN (...))`**

- เพิ่ม/เลิกใช้ค่าได้ด้วย migration ธรรมดา (`ALTER TABLE ... DROP/ADD CONSTRAINT`) —
  Postgres enum เพิ่มค่าได้แต่**ลบ/เปลี่ยนชื่อไม่ได้**โดยไม่สร้าง type ใหม่ทั้งก้อน
- PostgREST/Supabase client ได้ string ตรง ๆ ทั้งสองทางโดยไม่มี cast edge case
- Performance ต่างกันระดับ byte ต่อแถว ไม่มีนัยสำคัญที่ scale ของเรา
- Trade-off ที่ยอมรับ: typo protection อยู่ที่ CHECK constraint แทน type system —
  ยังกันค่าผิดที่ DB ได้เหมือนกัน
- ค่าใน CHECK เขียนเป็น snake_case เสมอ และ **ห้าม reuse ชุดค่าข้ามตาราง** —
  แต่ละ aggregate มี status set ของตัวเอง (บทเรียนตรงจาก reverse: DuangLive ใช้เลข
  status ปนกันหลาย domain จนตีความผิดง่าย เราไม่ทำซ้ำ)

### 2.4 Audit column policy

ทุกตารางมี `created_at timestamptz NOT NULL DEFAULT now()` ยกเว้น pure-lookup ที่ seed ด้วย migration

| Column | ใช้กับ | กฎ |
|---|---|---|
| `created_at` | ทุกตาราง | ตั้งครั้งเดียว ไม่แก้ |
| `updated_at` | ตารางที่ mutable | trigger `set_updated_at()` BEFORE UPDATE เดียวใช้ร่วมทุกตาราง |
| `version integer NOT NULL DEFAULT 1` | ตารางที่มี state machine หรือแก้พร้อมกันได้ (`question`, `appointment`, `call_transaction`, `seer_service`, `seer_profile`, `user_profile`, `payment_order`, `payout_request`, `live_room`, `wallet`) | optimistic lock: ทุก UPDATE ต้อง `WHERE version = $expected` แล้ว `SET version = version + 1`; RPC ใช้ row lock เป็นหลักและ version เป็น guard ชั้นสอง |
| `deleted_at` | **ไม่ใช้เป็น global policy** | soft delete เฉพาะจุดที่ product ต้องการ undo/audit จริง: `profile_photo`, `seer_document`, `payout_account`, `birth_profile` — ที่เหลือใช้ status (`account.status='deleted'`) หรือ hard delete + `audit_log` |

เหตุผลไม่ทำ global soft delete: RLS ทุก policy ต้องแปะ `deleted_at IS NULL` เพิ่มทุกตาราง
(พลาดครั้งเดียว = data leak), unique constraint ต้องกลายเป็น partial ทุกตัว, และตาราง
การเงินเป็น append-only อยู่แล้วจึงไม่มีคำว่าลบ

**Append-only tables** (ห้าม UPDATE/DELETE — enforce ด้วย trigger ที่ RAISE EXCEPTION
และไม่ grant UPDATE/DELETE ให้ role ใดเลย): `ledger_transaction`, `ledger_entry`,
`gift_transaction`, `audit_log`, `payment_webhook_event`, `voucher_redemption`,
`account_agreement` — แก้ไขด้วย reversing entry / แถวใหม่เท่านั้น

### 2.5 Tenancy / ownership rules (ออกแบบเพื่อ RLS)

1. **ทุกตารางที่ client อ่านตรงต้องมี ownership column ตรง ๆ ในตารางนั้นเอง**
   (`account_id` / `user_id` / `seer_id`) — RLS แบบ `auth.uid() = account_id` เร็วและพิสูจน์ถูกง่าย
   ห้ามออกแบบให้ RLS ต้อง join เกิน 1 ชั้น
2. ตาราง 2-participant (`question`, `call_transaction`, `appointment_room`) เก็บทั้ง
   `user_id` และ `seer_id` เสมอ → policy `participant-read` = `auth.uid() IN (user_id, seer_id)`
3. ตารางลูกของ 2-participant (`question_message`) ใช้ helper `is_question_participant(question_id)`
   (`SECURITY DEFINER`, `STABLE`) แทนการ join ใน policy
4. **Money tables ทั้งหมด RLS deny-all** — client อ่านผ่าน view/RPC, เขียนผ่าน RPC เท่านั้น (brief §4)
5. Role ผูกกับ `account.role` ฝั่ง server; client ไม่มีสิทธิ์ประกาศ role เอง —
  helper `current_account_role()` อ่านจากตาราง `account`
6. Admin ไม่ login ผ่าน app row-level: งาน admin ใช้ `service_role` ผ่าน backend/console
   เท่านั้น จึง**ไม่มี** policy พิเศษสำหรับ admin ใน RLS (ลดพื้นที่ผิดพลาด)

### 2.6 กฎเหล็กด้านเงิน (ยกจาก brief — ทวนเพื่อผูกกับ schema)

- ledger เป็น append-only double-entry, ทุก transaction sum = 0 (constraint trigger)
- ราคาอ่านจาก `seer_service` / `coin_package` / `gift` ฝั่ง server เสมอ
- ทุก financial RPC รับ `p_idempotency_key` และมี unique constraint กันซ้ำสองชั้น
  (`idempotency_key` ระดับ API + `ledger_transaction` ระดับบัญชี)
- balance เป็น projection ในตาราง `wallet` ที่ maintain ใน transaction เดียวกับ ledger (ส่วนที่ 5)

---

## ส่วนที่ 3 — Domain map (bounded contexts)

รวม **57 ตาราง** — มากกว่าประมาณการใน brief (48–52) อยู่ 5 ตาราง เหตุผล:
(ก) ตัดตาราง auth 4 ตัวที่ reverse target มี (`login_identity`, `session`, `refresh_token`,
`otp_challenge`) เพราะ Supabase `auth.*` ทำให้แล้ว แต่ (ข) เพิ่มตาราง compliance/ops
ที่ประมาณการเดิมไม่ได้นับ: `account_deletion_request` (PDPA), `audit_log`,
`rate_limit_counter` (brief §5 กำหนดให้ rate limit ใช้ตาราง), `app_config` —
ของเหล่านี้จำเป็นต่อการรันจริง ไม่ตัด

| # | Bounded context | ตาราง | จำนวน |
|---|---|---|---|
| 1 | **identity** | `account`, `user_profile`, `profile_photo`, `seer_profile`, `device_token`, `agreement`, `account_agreement`, `account_deletion_request` | 8 |
| 2 | **seer catalog** | `seer_level`, `skill`, `seer_skill`, `service_type`, `seer_service`, `seer_schedule`, `seer_document`, `favorite_seer` | 8 |
| 3 | **consultation** (question/chat/review) | `question`, `question_message`, `review`, `review_tag` | 4 |
| 4 | **appointment** | `appointment_room`, `appointment`, `appointment_message` | 3 |
| 5 | **call** | `call_transaction`, `call_extension`, `media_session` | 3 |
| 6 | **wallet & ledger** | `wallet`, `ledger_transaction`, `ledger_entry`, `idempotency_key` | 4 |
| 7 | **payment** | `coin_package`, `payment_order`, `iap_receipt`, `bank_transfer_proof`, `payment_webhook_event` | 5 |
| 8 | **promotion** | `voucher`, `voucher_redemption`, `referral_attribution` | 3 |
| 9 | **seer earning & payout** | `seer_earning`, `payout_account`, `payout_request` | 3 |
| 10 | **horoscope & AI** (ใหม่) | `birth_profile`, `horoscope_content`, `ai_reading_session`, `ai_reading_message`, `ai_usage_quota` | 5 |
| 11 | **live stream & gift** (ใหม่, feature-flagged) | `live_room`, `gift`, `gift_transaction` | 3 |
| 12 | **notification & outbox** | `notification_inbox`, `outbox_event` | 2 |
| 13 | **config & ops** | `app_config`, `rate_limit_counter` | 2 |
| 14 | **moderation & audit** | `block_relation`, `user_report`, `moderation_action`, `audit_log` | 4 |

ความสัมพันธ์ข้าม context ที่สำคัญ:

- ทุก context อ้าง `account(id)` เป็นแกน identity เดียว
- **wallet & ledger เป็น hub การเงิน**: consultation, call, payment, promotion, live/gift,
  AI (แบบเสียเงิน), payout — ทุก context ที่แตะเงิน post เข้า `ledger_transaction`/`ledger_entry`
  ผ่าน function เดียว `internal_post_ledger()` เท่านั้น
- `outbox_event` เป็นทางออกเดียวของ side effect (push, email, media cleanup) —
  ทุก RPC ที่เปลี่ยน state สำคัญ insert outbox ใน transaction เดียวกัน
- live stream & gift ตัดออกได้ทั้ง context ด้วย `app_config` key `feature.live_enabled`
  โดยไม่มี FK จาก context อื่นชี้เข้ามา (มีแต่ `gift_transaction` ชี้ออกไปหา ledger)

---

## ส่วนที่ 4 — นิยามตารางครบทุกตัว

รูปแบบ: ทุกตารางมีคำอธิบาย, ตาราง column, constraints, indexes, RLS posture (+ policy intent),
และ state machine ถ้ามี — `PK` ระบุใน column table; FK เขียน `→ table(col) [ON DELETE ...]`

### 4.1 Identity

#### 4.1.1 `account`

ตอบคำถาม: "uuid นี้คือใคร มีบทบาทอะไร ยัง active ไหม" — แถวคู่ขนานกับ `auth.users` หนึ่งต่อหนึ่ง
สร้างโดย trigger `AFTER INSERT ON auth.users` (SECURITY DEFINER)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | — | PK, FK → `auth.users(id)` ON DELETE CASCADE |
| `role` | `text` | NO | `'user'` | CHECK IN (`user`,`seer`,`admin`) — บทบาทหลักหนึ่งเดียวต่อบัญชี |
| `status` | `text` | NO | `'active'` | CHECK IN (`active`,`suspended`,`deleted`) |
| `phone_e164` | `text` | YES | — | สำเนา phone จาก auth (E.164) เพื่อ query/uniqueness ฝั่งเรา |
| `referral_code` | `text` | YES | — | โค้ดชวนเพื่อนของบัญชีนี้ (สร้างตอน insert, 8 ตัว A–Z0–9) |
| `created_at` | `timestamptz` | NO | `now()` | |
| `updated_at` | `timestamptz` | NO | `now()` | trigger |

- Constraints: `UNIQUE (phone_e164)`, `UNIQUE (referral_code)`
- ตัดสินใจ: **user กับ seer เป็น account คนละแถว** (แยกเบอร์/แยก auth identity) ตาม
  พฤติกรรมที่สังเกตจาก client contract ที่แยก mode ชัดเจน; ห้ามบัญชีเดียวสลับ role
- Indexes: PK พอ (`phone_e164`, `referral_code` มี unique index อยู่แล้ว)
- RLS: **owner-read** (`auth.uid() = id`); เขียน: **deny-all** — ทุกการเปลี่ยน role/status
  ทำผ่าน service role / RPC เท่านั้น (client แก้ profile ที่ตาราง profile ไม่ใช่ที่นี่)
- State: `active → suspended → active` (admin), `active|suspended → deleted` (ผ่าน
  `account_deletion_request` เท่านั้น, terminal)

#### 4.1.2 `user_profile`

ตอบคำถาม: "ข้อมูลแสดงผลและ preference ของผู้ใช้ฝั่งลูกค้าคืออะไร"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `account_id` | `uuid` | NO | — | PK, FK → `account(id)` ON DELETE CASCADE |
| `display_name` | `text` | NO | — | CHECK `char_length(display_name) BETWEEN 1 AND 50` |
| `avatar_url` | `text` | YES | — | storage path รูป avatar |
| `birthdate` | `date` | YES | — | PII — ใช้ทำ horoscope ได้ (ดู `birth_profile` สำหรับข้อมูลละเอียด) |
| `gender` | `text` | YES | — | CHECK IN (`male`,`female`,`other`,`undisclosed`) |
| `notify_message` | `boolean` | NO | `true` | push เมื่อมีข้อความ |
| `notify_seer_online` | `boolean` | NO | `true` | push เมื่อหมอดูที่ favorite ออนไลน์ |
| `notify_daily_horoscope` | `boolean` | NO | `true` | push ดวงรายวัน |
| `referred_by_code` | `text` | YES | — | โค้ดที่ใช้ตอนสมัคร (snapshot; attribution จริงอยู่ `referral_attribution`) |
| `version` | `integer` | NO | `1` | optimistic lock |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Indexes: PK พอ
- RLS: อ่าน **owner-read**; เขียน **owner-write ผ่าน RLS ตรง** (ไม่แตะเงิน) โดยมี
  CHECK/trigger กันแก้ `referred_by_code` หลังตั้งค่าแล้ว (เขียนได้ครั้งเดียวจาก NULL)

#### 4.1.3 `profile_photo`

ตอบคำถาม: "บัญชีนี้มีรูปอะไรบ้าง ลำดับไหน ผ่าน moderation หรือยัง" — ใช้ทั้งรูปแกลเลอรีของ
seer และรูปโปรไฟล์เพิ่มเติมของ user

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `position` | `smallint` | NO | `0` | CHECK `position BETWEEN 0 AND 9` |
| `object_key` | `text` | NO | — | path ใน Supabase Storage bucket `profile-photos` |
| `moderation_status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`approved`,`rejected`) |
| `deleted_at` | `timestamptz` | YES | — | soft delete |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (account_id, position) WHERE deleted_at IS NULL` (partial),
  `UNIQUE (object_key)`
- Indexes: `(account_id) WHERE deleted_at IS NULL`
- RLS: อ่าน — **public-read เมื่อ `moderation_status='approved'` และเจ้าของเป็น seer ที่
  approved**; เจ้าของอ่านของตัวเองได้ทุกสถานะ; เขียน — owner insert/update (จำกัด column
  ผ่าน trigger: client แก้ได้แค่ `position`, `deleted_at`)
- State: `pending → approved | rejected` (service role เท่านั้น)

#### 4.1.4 `seer_profile`

ตอบคำถาม: "หมอดูคนนี้คือใคร สถานะ approve/เปิดรับงานเป็นอย่างไร" — สังเกตจาก contract ว่า
approval, active, รับ appointment, รับ tip, รองรับ call เป็น**แกนอิสระ** ห้ามยุบเป็น enum เดียว

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `account_id` | `uuid` | NO | — | PK, FK → `account(id)` ON DELETE CASCADE |
| `display_name` | `text` | NO | — | CHECK length 1–50 |
| `bio` | `text` | NO | `''` | คำแนะนำตัว CHECK length ≤ 2000 |
| `avatar_url` | `text` | YES | — | |
| `approval_status` | `text` | NO | `'draft'` | CHECK IN (`draft`,`submitted`,`approved`,`rejected`) |
| `is_active` | `boolean` | NO | `false` | เปิดรับงานหรือไม่ (seer สลับเอง) |
| `accepts_question` | `boolean` | NO | `false` | เปิดรับคำถามแชท |
| `accepts_appointment` | `boolean` | NO | `false` | เปิดรับนัดหมาย |
| `accepts_tip` | `boolean` | NO | `false` | รับ tip |
| `accepts_call_extension` | `boolean` | NO | `true` | ยอมให้ต่อเวลาสาย |
| `level_id` | `integer` | YES | — | FK → `seer_level(id)` ON DELETE SET NULL |
| `rating_avg` | `numeric(3,2)` | YES | — | projection จาก `review` CHECK 0–5 |
| `rating_count` | `integer` | NO | `0` | projection |
| `question_count` | `integer` | NO | `0` | projection งานที่จบแล้ว (แสดงบน card) |
| `main_skill_id` | `integer` | YES | — | FK → `skill(id)` ON DELETE SET NULL (denorm เพื่อ card query) |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(approval_status, is_active)` — หน้า discovery query
  `WHERE approval_status='approved' AND is_active`; `(main_skill_id)` สำหรับ filter ตามศาสตร์
- RLS: อ่าน — **public-read เมื่อ `approval_status='approved'`** (แม้ยังไม่ login เพื่อทำ
  landing/SEO ได้); เจ้าของอ่านตัวเองได้ทุกสถานะ; เขียน — เจ้าของแก้ได้เฉพาะ column ชุด
  `display_name, bio, avatar_url, is_active, accepts_*` (trigger บังคับ);
  `approval_status`, `level_id`, `rating_*` เขียนโดย service role/trigger เท่านั้น
- State (`approval_status`): `draft → submitted → approved | rejected`,
  `rejected → submitted` (ยื่นใหม่), `approved → submitted` (แก้ข้อมูลสำคัญแล้วรอตรวจซ้ำ)
- Presence (ออนไลน์/กำลังคุย) **ไม่อยู่ในตารางนี้** — เป็น ephemeral ใน Realtime Presence (ส่วนที่ 8)

#### 4.1.5 `device_token`

ตอบคำถาม: "จะส่ง push หาบัญชีนี้ที่ device ไหนบ้าง"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `platform` | `text` | NO | — | CHECK IN (`ios`,`android`) |
| `provider` | `text` | NO | `'fcm'` | CHECK IN (`fcm`,`apns`) — เผื่อ APNs direct |
| `token` | `text` | NO | — | push token (ไม่ใช่ secret ระดับ credential แต่ห้าม public) |
| `is_enabled` | `boolean` | NO | `true` | ปิดเมื่อ provider ตอบ token ตาย |
| `last_seen_at` | `timestamptz` | NO | `now()` | อัปเดตทุกครั้งที่ app เปิด — ใช้ purge token ค้าง |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (token)` — token ย้ายเครื่อง/บัญชี = upsert ทับแถวเดิม (จับ conflict
  แล้วย้าย `account_id`)
- Indexes: `(account_id) WHERE is_enabled`
- RLS: **owner-read / owner-write** (insert/update/delete ของตัวเอง); push sender ใช้ service role

#### 4.1.6 `agreement`

ตอบคำถาม: "เอกสารข้อตกลง (ToS, privacy, seer contract) เวอร์ชันไหน มีผลเมื่อไหร่"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `integer` | NO | identity | PK |
| `code` | `text` | NO | — | เช่น `tos`, `privacy`, `seer_terms` |
| `version` | `text` | NO | — | เช่น `2026-08-01` |
| `title` | `text` | NO | — | |
| `content_url` | `text` | NO | — | ชี้ storage/เว็บ ไม่เก็บเนื้อหายาวใน DB |
| `is_required` | `boolean` | NO | `true` | ต้อง accept ก่อนใช้งานไหม |
| `effective_at` | `timestamptz` | NO | — | |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (code, version)`
- RLS: **public-read**; เขียน service role เท่านั้น

#### 4.1.7 `account_agreement`

ตอบคำถาม: "ใคร accept ข้อตกลงฉบับไหนเมื่อไหร่" — append-only (หลักฐาน consent PDPA)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `account_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `account(id)` ON DELETE CASCADE |
| `agreement_id` | `integer` | NO | — | PK ส่วนสอง, FK → `agreement(id)` ON DELETE RESTRICT |
| `accepted_at` | `timestamptz` | NO | `now()` | |

- PK: `(account_id, agreement_id)`; append-only
- RLS: อ่าน owner-read; เขียน — owner insert เท่านั้น (UPDATE/DELETE ไม่ grant)

#### 4.1.8 `account_deletion_request`

ตอบคำถาม: "ใครขอลบบัญชี ตอนนี้อยู่ขั้นไหน จะ execute เมื่อไหร่" — PDPA มาตรา 33 (สิทธิขอลบ)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `status` | `text` | NO | `'requested'` | CHECK IN (`requested`,`cancelled`,`processing`,`completed`) |
| `reason` | `text` | YES | — | เหตุผลจากผู้ใช้ (optional) |
| `scheduled_purge_at` | `timestamptz` | NO | — | `now() + interval '7 days'` — grace period ยกเลิกได้ |
| `completed_at` | `timestamptz` | YES | — | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (account_id) WHERE status IN ('requested','processing')` — คำขอค้างได้ทีละหนึ่ง
- ข้อบังคับ: seer ที่มี `wallet.payable_coin > 0` หรือ `payout_request` ค้าง ต้องเคลียร์ก่อน
  (ตรวจใน RPC `request_account_deletion`)
- RLS: owner-read; เขียนผ่าน RPC (`request_account_deletion`, `cancel_account_deletion`)
- State: `requested → cancelled` (user, ก่อน purge) | `requested → processing → completed`
  (cron + Edge Function ลบ/anonymize — ดูส่วนที่ 11)

### 4.2 Seer catalog

#### 4.2.1 `seer_level`

ตอบคำถาม: "หมอดูระดับนี้ได้ส่วนแบ่งเท่าไหร่ แสดง badge อะไร"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `integer` | NO | identity | PK |
| `code` | `text` | NO | — | `standard`, `pro`, `master` ฯลฯ |
| `name` | `text` | NO | — | ชื่อแสดงผล |
| `revenue_share_bps` | `integer` | NO | — | ส่วนแบ่งของ seer เป็น basis points CHECK 0–10000 เช่น 7000 = 70% |
| `badge_url` | `text` | YES | — | |
| `sort_order` | `integer` | NO | `0` | |
| `is_enabled` | `boolean` | NO | `true` | |

- Constraints: `UNIQUE (code)`
- RLS: public-read; เขียน service role
- หมายเหตุ: settlement snapshot `revenue_share_bps` ลงใน ledger metadata ตอนจบงานเสมอ —
  เปลี่ยน level ภายหลังไม่กระทบงานที่จบไปแล้ว

#### 4.2.2 `skill`

ตอบคำถาม: "ศาสตร์ดูดวงที่ระบบรู้จักมีอะไรบ้าง" (ไพ่ยิปซี, เลข 7 ตัว, ลายมือ, โหราศาสตร์ไทย ฯลฯ)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `integer` | NO | identity | PK |
| `name` | `text` | NO | — | UNIQUE |
| `icon_url` | `text` | YES | — | |
| `sort_order` | `integer` | NO | `0` | |
| `is_enabled` | `boolean` | NO | `true` | |

- RLS: public-read; เขียน service role

#### 4.2.3 `seer_skill`

ตอบคำถาม: "หมอดูคนนี้ถนัดศาสตร์ไหนบ้าง อันไหนเป็นศาสตร์หลัก"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `seer_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `seer_profile(account_id)` ON DELETE CASCADE |
| `skill_id` | `integer` | NO | — | PK ส่วนสอง, FK → `skill(id)` ON DELETE RESTRICT |
| `is_main` | `boolean` | NO | `false` | |

- PK `(seer_id, skill_id)`; `UNIQUE (seer_id) WHERE is_main` — main skill ได้หนึ่งเดียว
- Indexes: `(skill_id)` — filter หมอดูตามศาสตร์
- RLS: อ่าน public-read (join ผ่าน seer ที่ approved — leak แค่ skill id ของ seer
  ที่ยังไม่ approve ไม่ถือเป็นความเสี่ยง จึงยอมให้อ่านทั้งตารางเพื่อให้ policy ถูกและเร็ว);
  เขียน — owner (seer) insert/delete ของตัวเอง

#### 4.2.4 `service_type`

ตอบคำถาม: "ระบบมีรูปแบบบริการอะไรบ้าง และแต่ละแบบ consult ผ่านช่องทางไหน"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `integer` | NO | identity | PK |
| `code` | `text` | NO | — | UNIQUE: `chat_question`, `voice_call`, `video_call` |
| `consultation_mode` | `text` | NO | — | CHECK IN (`question`,`call`) — ตัวกำหนดว่า flow ไปลง `question` หรือ `call_transaction` |
| `name` | `text` | NO | — | ชื่อแสดงผล |
| `min_price_coin` | `bigint` | NO | `0` | เพดานล่างราคาที่ seer ตั้งได้ |
| `max_price_coin` | `bigint` | NO | — | เพดานบน CHECK `max >= min` |
| `base_duration_seconds` | `integer` | YES | — | สำหรับ call: ระยะเวลาต่อ 1 หน่วยราคา (เช่น 900 = 15 นาที); NULL สำหรับ question |
| `is_enabled` | `boolean` | NO | `true` | |

- RLS: public-read; เขียน service role

#### 4.2.5 `seer_service`

ตอบคำถาม: "หมอดูคนนี้ขายบริการอะไร ราคาเท่าไหร่ เปิดอยู่ไหม" — **แหล่งราคาเดียวของระบบ**

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `seer_id` | `uuid` | NO | — | FK → `seer_profile(account_id)` ON DELETE CASCADE |
| `service_type_id` | `integer` | NO | — | FK → `service_type(id)` ON DELETE RESTRICT |
| `price_coin` | `bigint` | NO | — | CHECK `price_coin >= 0` (0 = โปรโมชันฟรีได้) |
| `is_enabled` | `boolean` | NO | `false` | |
| `trial_quota_per_user` | `smallint` | NO | `0` | จำนวนครั้งทดลองฟรีต่อ user (0 = ไม่มี) |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (seer_id, service_type_id)`; trigger ตรวจ `price_coin` อยู่ในช่วง
  `service_type.min/max_price_coin`
- Indexes: `(seer_id) WHERE is_enabled`
- RLS: อ่าน public-read; เขียน — owner แก้ได้เฉพาะ `price_coin`, `is_enabled` (trigger จำกัด)
- กฎ: RPC ฝั่งซื้อ**อ่านราคาจากแถวนี้ ณ เวลา commit เสมอ** และ snapshot `price_coin`
  ลง `question.price_coin` / `call_transaction.reserved_coin` เป็นหลักฐานราคาที่ตกลง

#### 4.2.6 `seer_schedule`

ตอบคำถาม: "หมอดูประกาศเวลาออนไลน์ประจำสัปดาห์ไว้ว่าอย่างไร" (แสดงผล ไม่ใช่ enforcement)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `seer_id` | `uuid` | NO | — | FK → `seer_profile(account_id)` ON DELETE CASCADE |
| `day_of_week` | `smallint` | NO | — | CHECK 0–6 (0 = อาทิตย์) |
| `start_time` | `time` | NO | — | เวลาท้องถิ่นไทย (ระบบตีความด้วย `Asia/Bangkok` คงที่) |
| `end_time` | `time` | NO | — | CHECK `end_time > start_time` |

- Constraints: `UNIQUE (seer_id, day_of_week, start_time)`
- Indexes: `(seer_id)`
- RLS: public-read; owner-write (insert/delete แถวของตัวเอง)

#### 4.2.7 `seer_document`

ตอบคำถาม: "เอกสารสมัคร/KYC ของหมอดูคนนี้มีอะไร สถานะตรวจเป็นอย่างไร" — PII อ่อนไหวสูง

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `seer_id` | `uuid` | NO | — | FK → `seer_profile(account_id)` ON DELETE CASCADE |
| `document_type` | `text` | NO | — | CHECK IN (`national_id`,`bank_book`,`certificate`,`portrait`,`other`) |
| `object_key` | `text` | NO | — | path ใน **private** bucket `seer-documents` UNIQUE |
| `review_status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`approved`,`rejected`) |
| `reject_reason` | `text` | YES | — | |
| `reviewed_by` | `uuid` | YES | — | FK → `account(id)` ON DELETE SET NULL |
| `reviewed_at` | `timestamptz` | YES | — | |
| `deleted_at` | `timestamptz` | YES | — | soft delete (seer ลบเอกสารเองได้ก่อน approve) |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(seer_id) WHERE deleted_at IS NULL`, `(review_status) WHERE review_status='pending'`
  (คิวงาน admin)
- RLS: **owner-read เท่านั้น** (เจ้าของเห็น metadata ตัวเอง); เขียน — owner insert +
  soft-delete ก่อน approve; `review_*` เขียนโดย service role; Storage bucket เป็น private,
  ออก signed URL อายุสั้นผ่าน service role เท่านั้น
- State: `pending → approved | rejected`; `rejected` → seer อัปโหลดแถวใหม่ (ไม่แก้แถวเดิม)

#### 4.2.8 `favorite_seer`

ตอบคำถาม: "user คนไหนติดตามหมอดูคนไหน และอยากได้แจ้งเตือนตอนออนไลน์ไหม" —
รองรับหน้า favorites และ push `notify_seer_online`

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `user_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `account(id)` ON DELETE CASCADE |
| `seer_id` | `uuid` | NO | — | PK ส่วนสอง, FK → `account(id)` ON DELETE CASCADE |
| `notify_online` | `boolean` | NO | `false` | push เมื่อ seer คนนี้เริ่มเปิดรับงาน |
| `created_at` | `timestamptz` | NO | `now()` | |

- PK `(user_id, seer_id)`; `CHECK (user_id <> seer_id)`
- Indexes: `(seer_id) WHERE notify_online` — fan-out ผู้รับ push ตอน seer เปลี่ยน
  `is_active` เป็น true (trigger บน `seer_profile` → outbox `seer.online`)
- RLS: **owner-read / owner-write** (user insert/update/delete ของตัวเอง; ไม่แตะเงิน);
  seer ไม่เห็นรายชื่อคนติดตาม (เห็นเฉพาะจำนวนผ่าน view สรุปถ้า product ต้องการภายหลัง)

### 4.3 Consultation (question / chat / review)

#### 4.3.1 `question`

ตอบคำถาม: "การปรึกษาแบบคำถามครั้งนี้ ใครถามใคร ราคาเท่าไหร่ อยู่สถานะไหน" —
aggregate หลักของ flow แชทถาม-ตอบ escrow coin ไว้จนกว่างานจบ

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `user_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT (ผู้ถาม) |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT (หมอดู) |
| `seer_service_id` | `uuid` | NO | — | FK → `seer_service(id)` ON DELETE RESTRICT |
| `status` | `text` | NO | `'submitted'` | CHECK IN (`submitted`,`active`,`close_requested`,`completed`,`cancelled_refunded`) |
| `price_coin` | `bigint` | NO | — | snapshot ราคา ณ ตอนซื้อ CHECK `>= 0` |
| `is_trial` | `boolean` | NO | `false` | ใช้โควตาทดลองฟรี (price_coin = 0) |
| `client_request_id` | `uuid` | NO | — | idempotency key จาก client ต่อ 1 intent; `UNIQUE (user_id, client_request_id)` — retry submit คืน question เดิม (ทำงานคู่กับ `idempotency_key` ชั้น API ซึ่งเก็บ response cache) |
| `close_requested_by` | `uuid` | YES | — | FK → `account(id)`; ใครขอปิด |
| `close_requested_at` | `timestamptz` | YES | — | |
| `cancel_reason` | `text` | YES | — | CHECK IN (`user_cancel`,`seer_timeout`,`seer_reject`,`admin`) เมื่อ status=`cancelled_refunded` |
| `user_last_read_message_id` | `bigint` | NO | `0` | read cursor ฝั่ง user (แทนตาราง cursor แยก — มีผู้อ่านแค่ 2 คนเสมอ) |
| `seer_last_read_message_id` | `bigint` | NO | `0` | read cursor ฝั่ง seer |
| `expires_at` | `timestamptz` | NO | — | เส้นตายที่ seer ต้องตอบก่อนโดน auto-refund (คำนวณจาก config ตอน submit) |
| `completed_at` | `timestamptz` | YES | — | |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `CHECK (user_id <> seer_id)`;
  `CHECK (status <> 'completed' OR completed_at IS NOT NULL)`; `UNIQUE (user_id, client_request_id)`
- Indexes: `(user_id, created_at DESC)` — ประวัติฝั่ง user;
  `(seer_id, status, created_at DESC)` — task list ของ seer;
  `(expires_at) WHERE status IN ('submitted','active')` — cron auto-refund/auto-close
- RLS: **participant-read** (`auth.uid() IN (user_id, seer_id)`); เขียน **deny-all** —
  ทุก transition ผ่าน RPC (แตะ escrow ทุกทาง)
- State machine (ตรงกับที่สังเกตจาก client contract):

```
submitted ──(seer ตอบครั้งแรก)──> active
submitted ──(user ยกเลิก / หมดเวลา seer ไม่ตอบ)──> cancelled_refunded   [refund escrow]
active ──(ฝ่ายใดขอปิด)──> close_requested
close_requested ──(อีกฝ่ายปฏิเสธ / ผู้ขอถอนคำขอ)──> active
close_requested ──(อีกฝ่ายยอมรับ)──> completed                          [settle escrow]
active ──(หมดเวลารวม + policy อนุญาต auto-complete)──> completed        [settle escrow]
```
  terminal = `completed`, `cancelled_refunded`; transition ทุกครั้ง lock แถว + ตรวจ state
  ปัจจุบันก่อน (compare-and-set)

#### 4.3.2 `question_message`

ตอบคำถาม: "บทสนทนาในคำถามนี้มีอะไรบ้าง" — append-heavy, โตเร็วที่สุดในระบบ (ดู partition ส่วนที่ 10)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK — ใช้เป็น keyset cursor (`min_message_id` pattern) |
| `question_id` | `uuid` | NO | — | FK → `question(id)` ON DELETE CASCADE |
| `sender_id` | `uuid` | YES | — | FK → `account(id)` ON DELETE SET NULL; NULL = system message |
| `client_message_id` | `uuid` | NO | — | idempotency จากฝั่ง client (retry แล้วไม่ซ้ำ) |
| `message_type` | `text` | NO | `'text'` | CHECK IN (`text`,`photo`,`audio`,`system`) |
| `content` | `text` | YES | — | ข้อความ (CHECK length ≤ 4000) หรือ NULL เมื่อเป็น media |
| `object_key` | `text` | YES | — | storage path เมื่อ type เป็น photo/audio; CHECK คู่กับ type |
| `system_event` | `text` | YES | — | เมื่อ type=`system`: `close_requested`,`close_confirmed`,`close_cancelled`,`refunded`,`expired_warning` |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (question_id, client_message_id)`;
  `CHECK ((message_type IN ('photo','audio')) = (object_key IS NOT NULL))`
- Indexes: `(question_id, id)` — เปิดห้องอ่านไล่จาก cursor (ครอบ query หลักทั้งหมด)
- RLS: อ่าน — participant ผ่าน `is_question_participant(question_id)`;
  เขียน — **direct INSERT ผ่าน RLS ได้** (ไม่แตะเงิน) โดย policy บังคับ:
  `sender_id = auth.uid()` AND เป็น participant AND question.status IN
  (`submitted`,`active`,`close_requested`) AND `message_type <> 'system'`
  (system message insert โดย RPC/trigger เท่านั้น); UPDATE/DELETE ไม่ grant
- Trigger AFTER INSERT: insert `outbox_event` (`question.message.created`) เพื่อส่ง push

#### 4.3.3 `review`

ตอบคำถาม: "งานที่จบแล้วได้รีวิว/ดาว/ทิปเท่าไหร่ หมอดูตอบกลับว่าอะไร"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `user_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE (ผู้รีวิว) |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `question_id` | `uuid` | YES | — | FK → `question(id)` ON DELETE SET NULL |
| `call_transaction_id` | `uuid` | YES | — | FK → `call_transaction(id)` ON DELETE SET NULL |
| `rating` | `smallint` | NO | — | CHECK 1–5 |
| `comment` | `text` | YES | — | CHECK length ≤ 1000 |
| `tag_ids` | `integer[]` | NO | `'{}'` | รายการ tag จาก `review_tag` (ดูเหตุผลด้านล่าง) |
| `tip_coin` | `bigint` | NO | `0` | ทิปที่แนบมากับรีวิว (โพสต์ ledger ผ่าน RPC เดียวกัน) CHECK `>= 0` |
| `seer_reply` | `text` | YES | — | คำตอบกลับจากหมอดู CHECK length ≤ 1000 |
| `seer_replied_at` | `timestamptz` | YES | — | |
| `is_hidden` | `boolean` | NO | `false` | moderation ซ่อนรีวิว |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `CHECK ((question_id IS NOT NULL)::int + (call_transaction_id IS NOT NULL)::int = 1)`
  — รีวิวผูก consultation เดียวชนิดเดียว;
  `UNIQUE (question_id) WHERE question_id IS NOT NULL`;
  `UNIQUE (call_transaction_id) WHERE call_transaction_id IS NOT NULL` — งานละหนึ่งรีวิว
- Indexes: `(seer_id, created_at DESC) WHERE NOT is_hidden` — หน้ารีวิวของ seer;
  GIN `(tag_ids)` — นับ tag summary ต่อ seer
- เหตุผล `tag_ids` เป็น array ไม่ใช่ join table: tag เป็น display/summary เท่านั้น
  (นับจำนวนต่อ seer) ไม่มี lifecycle ของตัวเอง ไม่มี FK ลูกโยงเข้า — GIN index ตอบ
  query ที่มีจริงได้ครบ; validation ค่า id ทำใน RPC `submit_review`; แลก referential
  integrity ระดับ FK กับการลดตาราง join ที่ไม่มีใคร query ตรง
- RLS: อ่าน — public-read เมื่อ `NOT is_hidden` (โชว์หน้า seer); เขียน — **RPC เท่านั้น**
  (`submit_review` เพราะมี tip → แตะเงิน + ตรวจว่างานจบและเป็นของ user จริง;
  `reply_review` สำหรับ seer แก้ `seer_reply` ของตัวเอง)

#### 4.3.4 `review_tag`

ตอบคำถาม: "แท็กชมเชย/ติที่เลือกได้ตอนรีวิวมีอะไรบ้าง" (เช่น "ตอบเร็ว", "แม่นมาก")

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `integer` | NO | identity | PK |
| `label` | `text` | NO | — | UNIQUE |
| `sentiment` | `text` | NO | `'positive'` | CHECK IN (`positive`,`negative`) |
| `sort_order` | `integer` | NO | `0` | |
| `is_enabled` | `boolean` | NO | `true` | |

- RLS: public-read; เขียน service role

### 4.4 Appointment

Appointment ใน Chata คือ**การนัดเวลา** ระหว่าง user–seer (ห้องแชทฟรีสำหรับตกลงเวลา)
ไม่แตะเงินโดยตรง — เงินเกิดตอนบริการจริง (question/call) เริ่ม

#### 4.4.1 `appointment_room`

ตอบคำถาม: "user กับ seer คู่นี้มีห้องนัดหมายกันหรือยัง" — ห้องถาวรต่อคู่ (สร้างครั้งเดียว ใช้ซ้ำ)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `user_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `user_last_read_message_id` | `bigint` | NO | `0` | read cursor |
| `seer_last_read_message_id` | `bigint` | NO | `0` | read cursor |
| `last_message_at` | `timestamptz` | YES | — | denorm สำหรับเรียง inbox |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (user_id, seer_id)`, `CHECK (user_id <> seer_id)`
- Indexes: `(user_id, last_message_at DESC)`, `(seer_id, last_message_at DESC)` — inbox ทั้งสองฝั่ง
- RLS: participant-read; insert โดย user ฝั่งเดียว (policy: `user_id = auth.uid()` และ seer
  ต้อง `accepts_appointment`); update — เฉพาะ read cursor ของฝั่งตัวเอง (trigger จำกัด column)

#### 4.4.2 `appointment`

ตอบคำถาม: "คำเสนอนัดเวลาในห้องนี้ ใครเสนอ เวลาไหน สถานะอะไร"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `room_id` | `uuid` | NO | — | FK → `appointment_room(id)` ON DELETE CASCADE |
| `proposed_by` | `uuid` | NO | — | FK → `account(id)`; ใครเป็นคนเสนอเวลานี้ |
| `scheduled_at` | `timestamptz` | NO | — | เวลานัด CHECK `scheduled_at > created_at` |
| `status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`accepted`,`denied`,`cancelled`) |
| `responded_by` | `uuid` | YES | — | FK → `account(id)`; ใครตอบ (accept/deny) |
| `responded_at` | `timestamptz` | YES | — | |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (room_id) WHERE status = 'pending'` — เสนอค้างได้ทีละหนึ่งต่อห้อง
- Indexes: `(room_id, created_at DESC)`;
  `(scheduled_at) WHERE status = 'accepted'` — cron ส่ง reminder
- RLS: participant-read (ผ่าน helper `is_room_participant(room_id)`); เขียน — **RPC**
  (`propose_appointment`, `respond_appointment`, `cancel_appointment`) เพราะ transition
  ต้อง compare-and-set + กันคนเสนอตอบรับข้อเสนอตัวเอง (`responded_by <> proposed_by`)
- State: `pending → accepted | denied | cancelled(โดยผู้เสนอ)`, `accepted → cancelled`
  (ฝ่ายใดฝ่ายหนึ่ง, ก่อนเวลานัด); terminal = `denied`, `cancelled`, และ `accepted` ที่เลยเวลานัด

#### 4.4.3 `appointment_message`

ตอบคำถาม: "แชทตกลงเวลาในห้องนี้คุยอะไรกัน" — โครงเดียวกับ `question_message` แต่ text เท่านั้น

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK (keyset cursor) |
| `room_id` | `uuid` | NO | — | FK → `appointment_room(id)` ON DELETE CASCADE |
| `sender_id` | `uuid` | YES | — | FK → `account(id)` ON DELETE SET NULL; NULL = system |
| `client_message_id` | `uuid` | NO | — | idempotency |
| `content` | `text` | NO | — | CHECK length 1–2000 |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (room_id, client_message_id)`
- Indexes: `(room_id, id)`
- RLS: อ่าน participant (`is_room_participant`); เขียน — direct INSERT ผ่าน RLS
  (`sender_id = auth.uid()` + participant + ไม่ถูก block); trigger อัปเดต
  `appointment_room.last_message_at` + insert outbox push

### 4.5 Call

#### 4.5.1 `call_transaction`

ตอบคำถาม: "สายโทรครั้งนี้ ใครโทรหาใคร จองกี่ coin ถูก charge จริงกี่ coin อยู่สถานะไหน" —
aggregate การเงิน + state ของ call; **ตารางนี้คือ authority ของ call state** (Realtime เป็นแค่ signaling)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `user_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `seer_service_id` | `uuid` | NO | — | FK → `seer_service(id)` ON DELETE RESTRICT |
| `call_kind` | `text` | NO | — | CHECK IN (`voice`,`video`) — snapshot จาก service_type |
| `status` | `text` | NO | `'reserved'` | CHECK IN (`reserved`,`offered`,`accepted`,`active`,`completed`,`cancelled`,`rejected`,`expired`,`failed`) |
| `reserved_coin` | `bigint` | NO | — | escrow ตอนจอง (ราคา base duration) CHECK `>= 0` |
| `charged_coin` | `bigint` | NO | `0` | ยอดที่ settle แล้วรวม extension CHECK `>= 0` |
| `base_duration_seconds` | `integer` | NO | — | snapshot จาก `service_type.base_duration_seconds` |
| `total_duration_seconds` | `integer` | NO | `0` | รวม extension ที่ charge สำเร็จ |
| `is_trial` | `boolean` | NO | `false` | สายทดลองฟรี |
| `end_reason` | `text` | YES | — | CHECK IN (`user_end`,`seer_end`,`timeout`,`media_failure`,`admin`) เมื่อ terminal |
| `offered_at` / `accepted_at` / `started_at` / `ended_at` | `timestamptz` | YES | — | เวลาแต่ละ milestone |
| `reservation_expires_at` | `timestamptz` | NO | — | เส้นตาย seer รับสาย (เช่น now()+90s) — cron/RPC ปล่อย escrow เมื่อเลย |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `CHECK (user_id <> seer_id)`;
  `CHECK (status NOT IN ('completed') OR ended_at IS NOT NULL)`
- Indexes: `(user_id, created_at DESC)`, `(seer_id, status, created_at DESC)`;
  `(reservation_expires_at) WHERE status IN ('reserved','offered')` — cron release;
  `(status) WHERE status = 'active'` — cron settle สายค้าง
- Unique การกันโทรซ้อน: `UNIQUE (user_id) WHERE status IN ('reserved','offered','accepted','active')`
  และ `UNIQUE (seer_id) WHERE status IN ('accepted','active')` — คนหนึ่งมีสายเป็น ๆ ได้สายเดียว
- RLS: participant-read; เขียน **deny-all** — ทุก transition ผ่าน RPC (แตะ escrow ทุกจุด)
- State machine (สังเคราะห์จาก call-state protocol ที่ reverse ได้):

```
reserved ──(แจ้ง seer สำเร็จ)──> offered
reserved|offered ──(user ยกเลิก)──> cancelled          [release escrow]
reserved|offered ──(หมดเวลารับสาย)──> expired          [release escrow]
offered ──(seer ปฏิเสธ)──> rejected                    [release escrow]
offered ──(seer รับ)──> accepted
accepted ──(สองฝั่ง join media แล้ว / server สั่ง start)──> active   [charge ครั้งแรกจาก escrow]
accepted ──(join ไม่สำเร็จใน grace)──> failed          [release escrow]
active ──(จบสาย: user/seer วางสาย หรือหมดเวลา)──> completed  [settle: escrow → seer_payable + revenue]
active ──(media ล่มเกิน grace)──> completed            [settle ตามเวลาที่ใช้จริงเชิง policy]
```
  terminal = `completed`, `cancelled`, `rejected`, `expired`, `failed`
  reconnect ไม่เป็น state ใน DB — เป็นเรื่อง Presence/client; DB สนใจแค่ accounting milestones

#### 4.5.2 `call_extension`

ตอบคำถาม: "สายนี้ต่อเวลากี่ครั้ง ครั้งละเท่าไหร่ charge สำเร็จไหม"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `call_transaction_id` | `uuid` | NO | — | FK → `call_transaction(id)` ON DELETE CASCADE |
| `sequence_no` | `integer` | NO | — | CHECK `> 0`; ลำดับต่อเวลาในสายนั้น |
| `duration_seconds` | `integer` | NO | — | CHECK `> 0` |
| `coin_amount` | `bigint` | NO | — | CHECK `> 0` snapshot ราคา ณ ตอนต่อ |
| `status` | `text` | NO | `'charged'` | CHECK IN (`charged`,`reversed`) — insert เกิดหลัง charge สำเร็จเสมอ |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (call_transaction_id, sequence_no)` — idempotency ระดับบัญชีของการต่อเวลา
- Indexes: FK index `(call_transaction_id)`
- RLS: อ่าน — participant (helper `is_call_participant`); เขียน deny-all (RPC `extend_call`)
- หมายเหตุ: ไม่มี state `requested` — RPC `extend_call` ตัดเงิน + insert แถวใน transaction
  เดียว สำเร็จคือได้แถว ล้มเหลวคือไม่มีแถว; `reversed` ใช้เมื่อ admin คืนเงิน (reversing entry)

#### 4.5.3 `media_session`

ตอบคำถาม: "สายนี้ใช้ห้อง media ของ provider ไหน room id อะไร token หมดอายุเมื่อไหร่"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `call_transaction_id` | `uuid` | NO | — | PK, FK → `call_transaction(id)` ON DELETE CASCADE (1:1) |
| `provider` | `text` | NO | — | CHECK IN (`livekit`,`agora`,`twilio`) — เผื่อทุกทางจนกว่าจะเคาะ |
| `room_name` | `text` | NO | — | ชื่อห้องฝั่ง provider UNIQUE |
| `user_token_issued_at` | `timestamptz` | YES | — | audit การออก token ฝั่ง user |
| `seer_token_issued_at` | `timestamptz` | YES | — | audit ฝั่ง seer |
| `expires_at` | `timestamptz` | NO | — | อายุห้อง |
| `created_at` | `timestamptz` | NO | `now()` | |

- RLS: **deny-all** — client ไม่อ่านตารางนี้; token ออกผ่าน Edge Function `media-token`
  ซึ่งตรวจว่า caller เป็น participant ของ call ที่ non-terminal แล้ว mint token ให้
  (ตัว JWT ไม่เก็บใน DB — เก็บเฉพาะเวลา issue เพื่อ audit)

### 4.6 Wallet & ledger

> ตารางกลุ่มนี้ **RLS deny-all ทั้งหมด** — client อ่าน balance ผ่าน view `v_my_wallet`
> และประวัติผ่าน `v_my_coin_history`; เขียนผ่าน RPC เท่านั้น (brief §4 กฎเหล็ก)

#### 4.6.1 `wallet`

ตอบคำถาม: "บัญชีนี้มี coin ใช้ได้/ถูกจองไว้/ค้างจ่าย (seer) เท่าไหร่ตอนนี้" —
**projection** ของ ledger ที่ maintain ใน transaction เดียวกัน (เหตุผลในส่วนที่ 5.4)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `account_id` | `uuid` | NO | — | PK, FK → `account(id)` ON DELETE RESTRICT |
| `available_coin` | `bigint` | NO | `0` | coin ใช้จ่ายได้ |
| `reserved_coin` | `bigint` | NO | `0` | coin ถูก escrow (question/call ที่ยังไม่จบ) |
| `payable_coin` | `bigint` | NO | `0` | ยอดค้างจ่ายของ seer (รอ payout) — 0 เสมอสำหรับ user |
| `version` | `integer` | NO | `1` | |
| `updated_at` | `timestamptz` | NO | `now()` | |
| `created_at` | `timestamptz` | NO | `now()` | สร้างพร้อม account (trigger) |

- Constraints: `CHECK (available_coin >= 0)`, `CHECK (reserved_coin >= 0)`,
  `CHECK (payable_coin >= 0)` — ยกเว้นกรณี chargeback ที่ยอมให้ available ติดลบ
  **ไม่ทำ** ที่ CHECK แต่ทำที่ RPC: chargeback โพสต์ผ่าน `internal_post_ledger` โหมด
  `allow_negative` ซึ่ง SET CONSTRAINTS ไม่ได้กับ CHECK ธรรมดา → ตัดสินใจ: CHECK คงไว้
  และ chargeback ที่จะทำให้ติดลบให้หักเท่าที่มีแล้วบันทึกส่วนขาดใน `moderation_action`
  (หนี้เชิง moderation ไม่ใช่ balance ติดลบ) — DB ไม่เคยมี balance ติดลบ
- RLS: deny-all; client อ่านผ่าน view `v_my_wallet` (`security_invoker=false` อ่านเฉพาะ
  `auth.uid()`)
- Concurrency: **ทุก financial RPC เริ่มด้วย `SELECT ... FROM wallet WHERE account_id = $x FOR UPDATE`**
  — แถว wallet คือ serialization point ต่อบัญชี (ดู 5.5)

#### 4.6.2 `ledger_transaction`

ตอบคำถาม: "เหตุการณ์ทางบัญชีนี้คืออะไร อ้างอิง business event ไหน" — หัวของ double-entry
หนึ่งเหตุการณ์ = หนึ่งแถว = หลาย `ledger_entry` ที่ sum เป็นศูนย์

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `reference_type` | `text` | NO | — | ชนิด business object: `payment_order`,`question`,`call_transaction`,`call_extension`,`voucher_redemption`,`referral_attribution`,`gift_transaction`,`ai_reading_session`,`payout_request`,`review`,`manual_adjustment` |
| `reference_id` | `text` | NO | — | id ของ object นั้น (text เพื่อรับได้ทั้ง uuid/bigint) |
| `operation` | `text` | NO | — | กริยาทางบัญชี: `credit_purchase`,`reserve`,`settle`,`refund`,`tip`,`gift`,`redeem`,`referral_bonus`,`ai_charge`,`payout`,`reversal`,`adjustment` |
| `reversal_of` | `uuid` | YES | — | FK → `ledger_transaction(id)`; ชี้ transaction ที่ถูกกลับรายการ |
| `note` | `text` | YES | — | คำอธิบาย (admin adjustment ต้องใส่) |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (reference_type, reference_id, operation)` —
  **idempotency ระดับบัญชี**: เหตุการณ์เดียว post ซ้ำไม่ได้ (webhook replay, RPC retry);
  `UNIQUE (reversal_of) WHERE reversal_of IS NOT NULL` — กลับรายการได้ครั้งเดียว
- Append-only (trigger ห้าม UPDATE/DELETE)
- RLS: deny-all

#### 4.6.3 `ledger_entry`

ตอบคำถาม: "เงินขา debit/credit ของเหตุการณ์นั้นลงบัญชีไหนเท่าไหร่"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `transaction_id` | `uuid` | NO | — | FK → `ledger_transaction(id)` ON DELETE RESTRICT |
| `ledger_account` | `text` | NO | — | ชื่อบัญชีในผังบัญชี (ดู 5.1): `user_available`,`user_reserved`,`seer_payable`,`platform_revenue`,`platform_promotion`,`coin_supply` |
| `account_id` | `uuid` | YES | — | FK → `account(id)` ON DELETE RESTRICT; เจ้าของบัญชีย่อย (NULL สำหรับบัญชี system) |
| `amount` | `bigint` | NO | — | หน่วย coin; **บวก = เงินเข้าบัญชีนั้น, ลบ = เงินออก**; CHECK `amount <> 0` |
| `balance_after` | `bigint` | YES | — | snapshot balance ของ (ledger_account, account_id) หลัง post — เฉพาะบัญชีที่มี wallet projection เพื่อ audit trail; NULL สำหรับบัญชี system |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `CHECK ((ledger_account IN ('user_available','user_reserved','seer_payable')) = (account_id IS NOT NULL))`
  — บัญชี per-account ต้องมีเจ้าของ, บัญชี system ห้ามมี
- **Zero-sum invariant**: `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` ตรวจ
  `SUM(amount) = 0` ต่อ `transaction_id` ตอน commit
- Indexes: `(account_id, id DESC) WHERE account_id IS NOT NULL` — ประวัติ coin ต่อบัญชี
  (keyset cursor); `(transaction_id)`
- Append-only; RLS: deny-all — client อ่านผ่าน view `v_my_coin_history`
  (แปลงเป็นรายการ "ได้/ใช้ coin" ที่อ่านง่าย เฉพาะแถวของ `auth.uid()`)

#### 4.6.4 `idempotency_key`

ตอบคำถาม: "request ทางการเงินนี้เคยประมวลผลแล้วหรือยัง ผลลัพธ์เดิมคืออะไร" —
idempotency ชั้น API (คู่กับชั้นบัญชีที่ `ledger_transaction`)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `account_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `account(id)` ON DELETE CASCADE |
| `operation` | `text` | NO | — | PK ส่วนสอง — ชื่อ RPC เช่น `submit_question` |
| `key` | `uuid` | NO | — | PK ส่วนสาม — client สร้างต่อ 1 user intent |
| `request_hash` | `bytea` | NO | — | SHA-256 ของ input ที่ normalize แล้ว |
| `response` | `jsonb` | YES | — | ผลลัพธ์ที่คืน client (บันทึกเมื่อสำเร็จ) |
| `status` | `text` | NO | `'in_progress'` | CHECK IN (`in_progress`,`succeeded`,`failed`) |
| `created_at` | `timestamptz` | NO | `now()` | |
| `expires_at` | `timestamptz` | NO | — | `now() + interval '24 hours'` — cron purge |

- PK `(account_id, operation, key)`
- พฤติกรรมใน RPC: INSERT ... ON CONFLICT → ถ้าชนและ `request_hash` ตรง คืน `response` เดิม
  (หรือ error `retry_in_progress` ถ้ายัง in_progress); ถ้าชนแต่ hash ไม่ตรง → error `409 idempotency_conflict`
- Indexes: `(expires_at)` — purge
- RLS: deny-all (จัดการภายใน RPC ล้วน ๆ)

### 4.7 Payment

> เงิน fiat เข้า → coin ออก. ตารางทั้งกลุ่มนี้ RLS deny-all ยกเว้น `coin_package` (catalog สาธารณะ)
> การ verify ทุกช่องทางเกิดใน Edge Function แล้วเรียก RPC ภายในตัวเดียว: `internal_credit_payment`

#### 4.7.1 `coin_package`

ตอบคำถาม: "แพ็กเกจเติม coin ที่ขายอยู่มีอะไรบ้าง ราคาเท่าไหร่ ผูก store product ไหน"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `code` | `text` | NO | — | UNIQUE เช่น `coin_100` |
| `coin_amount` | `bigint` | NO | — | CHECK `> 0` |
| `bonus_coin` | `bigint` | NO | `0` | โบนัสแถม CHECK `>= 0` (โพสต์แยกขาจาก `platform_promotion`) |
| `price_minor` | `bigint` | NO | — | ราคา fiat หน่วย satang CHECK `> 0` |
| `currency` | `char(3)` | NO | `'THB'` | |
| `apple_product_id` | `text` | YES | — | product id ฝั่ง App Store (NULL = ไม่ขายผ่าน Apple) |
| `google_product_id` | `text` | YES | — | product id ฝั่ง Play (แยก column ตาม brief §6 — price tier คนละชุด) |
| `allowed_methods` | `text[]` | NO | — | ซับเซ็ตของ method: (`apple_iap`,`google_play`,`bank_transfer`,`promptpay`,`card`,`truemoney`,`linepay`,`internet_banking`) — package ผูกกับ**วิธีจ่าย** ไม่ใช่ PSP |
| `sort_order` | `integer` | NO | `0` | |
| `is_enabled` | `boolean` | NO | `true` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (apple_product_id) WHERE apple_product_id IS NOT NULL`,
  `UNIQUE (google_product_id) WHERE google_product_id IS NOT NULL`
- RLS: **public-read เมื่อ `is_enabled`**; เขียน service role

#### 4.7.2 `payment_order`

ตอบคำถาม: "ความพยายามเติมเงินครั้งนี้ ใคร ซื้อแพ็กไหน ผ่านช่องทางไหน ไปถึงขั้นตอนไหนแล้ว"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `user_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `coin_package_id` | `uuid` | NO | — | FK → `coin_package(id)` ON DELETE RESTRICT |
| `method` | `text` | NO | — | **วิธีจ่ายที่ user เลือก** CHECK IN (`apple_iap`,`google_play`,`bank_transfer`,`promptpay`,`card`,`truemoney`,`linepay`,`internet_banking`) |
| `psp_code` | `text` | NO | — | **ใครเคลียร์เงิน** CHECK IN (`apple`,`google`,`chillpay`,`siampay`,`mol`,`epos`,`omise`,`manual`) — `manual` = โอนเงิน+ตรวจสลิปเอง |
| `status` | `text` | NO | `'created'` | CHECK IN (`created`,`pending_provider`,`verified`,`credited`,`failed`,`expired`,`refunded`) |
| `coin_amount` | `bigint` | NO | — | snapshot รวม `coin_amount` ของแพ็ก ณ ตอนสั่ง |
| `bonus_coin` | `bigint` | NO | `0` | snapshot |
| `price_minor` | `bigint` | NO | — | snapshot ราคา satang |
| `currency` | `char(3)` | NO | `'THB'` | |
| `psp_reference` | `text` | YES | — | order id/charge id ฝั่ง PSP |
| `referral_code_used` | `text` | YES | — | โค้ดชวนที่แนบมา (validate แล้ว) — ตัวจุด referral bonus |
| `failure_reason` | `text` | YES | — | |
| `expires_at` | `timestamptz` | NO | — | order ค้างเกินนี้ → cron ตั้ง `expired` |
| `credited_at` | `timestamptz` | YES | — | |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (psp_code, psp_reference) WHERE psp_reference IS NOT NULL`
  — callback ซ้ำจับได้ที่นี่อีกชั้น
- **ทำไมแยก `method` กับ `psp_code`**: method เดียวกันวิ่งได้หลาย PSP และย้าย PSP ได้
  (ค่าธรรมเนียม/PSP ล่ม/A-B rate) — ตลาดไทยมี pattern นี้จริง (เช่น PromptPay เคลียร์ได้ทั้ง
  ChillPay และ ePOS, บัตรได้ทั้ง ChillPay และ SiamPay ตามหลักฐาน client contract ที่ reverse ได้)
  ถ้ายุบเป็น column เดียวจะ backfill เจ็บตอนมี order จริง
- **การ validate คู่ (method, psp_code)**: ผ่าน `app_config` key `payment.method_psp_matrix`
  (jsonb: `{method: [psp_code ที่ใช้ได้ เรียงตาม priority]}`) ตรวจใน RPC/Edge ตอนสร้าง order —
  **ไม่ทำเป็น CHECK คู่ค่าใน DB** เพราะ matrix เปลี่ยนตามดีลธุรกิจ (เพิ่ม PSP, สลับ priority)
  ไม่ควรต้อง migration; CHECK รายค่าของแต่ละ column ยังกัน typo ที่ชั้น DB ให้อยู่
  ส่วน order แถวเก่าที่ psp_code หลุด matrix ไปแล้วคือประวัติศาสตร์ที่ถูกต้อง ไม่ผิด constraint
- Indexes: `(user_id, created_at DESC)`;
  `(status, expires_at) WHERE status IN ('created','pending_provider')` — cron reconcile/expire;
  `(psp_code, status, created_at DESC)` — reconcile/รายงานราย PSP
- RLS: deny-all; user เห็นประวัติผ่าน view `v_my_payment_history`; สร้าง order ผ่าน RPC
  `create_payment_order` (method ฝั่งเว็บ/โอน — server เลือก psp_code จาก matrix) หรือ
  Edge Function (IAP สร้างตอน verify เลยเพราะ Apple/Google เป็นคน initiate —
  psp_code = `apple`/`google` ตายตัวต่อ method นั้น)
- State: `created → pending_provider → verified → credited` |
  `created|pending_provider → failed|expired` | `credited → refunded` (chargeback — ทำ
  reversing ledger); **`credited` เกิดพร้อม ledger post ใน transaction เดียวเสมอ**

#### 4.7.3 `iap_receipt`

ตอบคำถาม: "หลักฐานการซื้อจาก Apple/Google ใบนี้ ถูก verify แล้วหรือยัง ผูก order ไหน" —
รองรับสอง store ที่รูปแบบต่างกันสิ้นเชิง (brief §6)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `payment_order_id` | `uuid` | NO | — | FK → `payment_order(id)` ON DELETE RESTRICT |
| `provider` | `text` | NO | — | CHECK IN (`apple_iap`,`google_play`) |
| `store_product_id` | `text` | NO | — | product id ที่ store ยืนยันกลับมา |
| `provider_transaction_id` | `text` | NO | — | Apple: `original_transaction_id`; Google: `order_id` |
| `purchase_token_hash` | `bytea` | NO | — | SHA-256 ของ Apple JWS / Google `purchase_token` — **ไม่เก็บ token ดิบ** |
| `raw_payload` | `jsonb` | NO | — | decoded receipt ที่ verify แล้ว (JWS claims / Play purchase resource) — ไว้ reconcile/dispute |
| `verified_at` | `timestamptz` | NO | `now()` | |
| `consumed_at` | `timestamptz` | YES | — | เวลา acknowledge/consume ฝั่ง store สำเร็จ |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (provider, purchase_token_hash)` — **กัน replay purchase token**
  (invariant ตรงจาก reverse: idempotency ต้องอยู่ที่ token);
  `UNIQUE (provider, provider_transaction_id)`
- RLS: deny-all; เขียนโดย Edge Function (service role) เท่านั้น

#### 4.7.4 `bank_transfer_proof`

ตอบคำถาม: "สลิปโอนของ order นี้อยู่ไหน ใครตรวจ ผลเป็นอย่างไร" — PII (สลิปมีชื่อ/เลขบัญชี)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `payment_order_id` | `uuid` | NO | — | PK, FK → `payment_order(id)` ON DELETE RESTRICT (1:1) |
| `bank_code` | `text` | NO | — | ธนาคารปลายทางที่ user เลือก (จาก `app_config` key `payment.banks`) |
| `object_key` | `text` | NO | — | path สลิปใน private bucket `payment-proofs` UNIQUE |
| `content_hash` | `bytea` | NO | — | SHA-256 ของไฟล์ — จับสลิปซ้ำ |
| `review_status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`approved`,`rejected`) |
| `reject_reason` | `text` | YES | — | |
| `reviewed_by` | `uuid` | YES | — | FK → `account(id)` ON DELETE SET NULL |
| `reviewed_at` | `timestamptz` | YES | — | |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (content_hash)` — สลิปเดียวใช้ซ้ำหลาย order ไม่ได้
- Indexes: `(review_status) WHERE review_status='pending'` — คิว admin
- RLS: deny-all (user อัปโหลดผ่าน Storage + RPC `attach_transfer_proof`; admin ตรวจผ่าน
  service role → `internal_credit_payment`)
- State: `pending → approved` (order → verified → credited) | `pending → rejected`
  (order → failed + push แจ้ง user)

#### 4.7.5 `payment_webhook_event`

ตอบคำถาม: "callback จาก PSP/store ใบนี้เคยรับและประมวลผลแล้วหรือยัง" — replay guard + audit

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `psp_code` | `text` | NO | — | PK ส่วนแรก — ชุดค่าเดียวกับ `payment_order.psp_code` (`apple` = App Store Server Notifications v2, `google` = Play RTDN, ที่เหลือคือ webhook ของ PSP นั้น) |
| `event_id` | `text` | NO | — | PK ส่วนสอง — id ของ event ฝั่ง PSP |
| `event_type` | `text` | NO | — | เช่น `charge.succeeded`, `REFUND` ฯลฯ ตามศัพท์ของ PSP |
| `payload_hash` | `bytea` | NO | — | SHA-256 ของ raw body |
| `payload` | `jsonb` | NO | — | body ที่ verify signature แล้ว (redact field อ่อนไหวก่อนเก็บ) |
| `processing_result` | `text` | NO | — | CHECK IN (`processed`,`ignored`,`error`) |
| `processed_at` | `timestamptz` | NO | `now()` | |

- PK `(psp_code, event_id)` — insert ก่อนประมวลผล; ชน = เคยรับแล้ว ตอบ 200 ทิ้ง
- Append-only; RLS: deny-all (Edge Function เขียน)

### 4.8 Promotion

#### 4.8.1 `voucher`

ตอบคำถาม: "โค้ด voucher ใบนี้มีค่าเท่าไหร่ ใช้ได้กี่ครั้ง หมดอายุเมื่อไหร่" —
แถวเดียวรองรับทั้งโค้ดเฉพาะคน (single-use) และโค้ดแคมเปญ (multi-use)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `code_hash` | `bytea` | NO | — | SHA-256(upper(code)) — **ไม่เก็บโค้ด plaintext** UNIQUE |
| `code_hint` | `text` | NO | — | 4 ตัวท้ายของโค้ด — ให้ admin ระบุใบได้โดยไม่เห็นโค้ดเต็ม |
| `campaign` | `text` | NO | — | ชื่อแคมเปญ (จัดกลุ่ม/รายงานแทนตาราง batch) |
| `coin_amount` | `bigint` | NO | — | CHECK `> 0` |
| `max_redemptions` | `integer` | NO | `1` | CHECK `> 0`; 1 = โค้ดใช้ครั้งเดียว |
| `redeemed_count` | `integer` | NO | `0` | projection CHECK `redeemed_count <= max_redemptions` |
| `per_user_limit` | `smallint` | NO | `1` | จำนวนครั้งต่อ user CHECK `> 0` |
| `status` | `text` | NO | `'active'` | CHECK IN (`active`,`disabled`) |
| `valid_from` | `timestamptz` | NO | `now()` | |
| `valid_until` | `timestamptz` | NO | — | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(campaign)`; unique index บน `code_hash` ครอบ lookup ตอน redeem แล้ว
- RLS: deny-all — redeem ผ่าน RPC `redeem_voucher(code)` (hash ในตัว function);
  ห้ามให้ client enumerate voucher
- State: `active → disabled` (admin); การหมดอายุตัดสินด้วย `valid_until` ตอน redeem
  (ไม่มี state `expired` แยก — ลด state ซ้ำซ้อนกับข้อมูลเวลา)

#### 4.8.2 `voucher_redemption`

ตอบคำถาม: "ใคร redeem voucher ใบไหนเมื่อไหร่ ได้ ledger transaction อะไร" — append-only

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `voucher_id` | `uuid` | NO | — | FK → `voucher(id)` ON DELETE RESTRICT |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `coin_amount` | `bigint` | NO | — | snapshot มูลค่าตอน redeem |
| `redeemed_at` | `timestamptz` | NO | `now()` | |

- Constraints: unique บางส่วนตาม `per_user_limit` — enforce ใน RPC ด้วย
  `SELECT count(*) ... FOR UPDATE` บนแถว voucher; สำหรับกรณี limit = 1 (default)
  มี `UNIQUE (voucher_id, account_id)` ช่วยกันชั้น DB (ยอมรับว่า limit > 1 ตรวจใน RPC —
  บันทึกเป็น design note ใน DBML)
- ledger เชื่อมด้วย `ledger_transaction (reference_type='voucher_redemption', reference_id=id, operation='redeem')`
- RLS: deny-all; user เห็นผลใน `v_my_coin_history`

#### 4.8.3 `referral_attribution`

ตอบคำถาม: "ใครชวนใครมา และจ่ายโบนัสไปหรือยัง" — attribution เกิดตอนสมัคร,
โบนัสจ่ายเมื่อผู้ถูกชวนเติมเงินสำเร็จครั้งแรก (กัน fraud แบบสมัครทิ้ง)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `referrer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT (คนชวน) |
| `referee_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT (คนถูกชวน) UNIQUE — ถูกชวนได้ครั้งเดียวในชีวิต |
| `referral_code` | `text` | NO | — | snapshot โค้ดที่ใช้ |
| `status` | `text` | NO | `'attributed'` | CHECK IN (`attributed`,`rewarded`,`voided`) |
| `referrer_bonus_coin` | `bigint` | YES | — | snapshot โบนัสฝั่งคนชวน (ตอนจ่าย) |
| `referee_bonus_coin` | `bigint` | YES | — | snapshot โบนัสฝั่งคนถูกชวน |
| `rewarded_at` | `timestamptz` | YES | — | |
| `qualifying_payment_order_id` | `uuid` | YES | — | FK → `payment_order(id)`; order แรกที่ทำให้เข้าเงื่อนไข |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `CHECK (referrer_id <> referee_id)`; `UNIQUE (referee_id)`
- Indexes: `(referrer_id, created_at DESC)` — หน้าสรุป "ฉันชวนไปกี่คน"
- RLS: deny-all; ทั้งสองฝ่ายเห็นสรุปผ่าน view `v_my_referral_summary`
- State: `attributed → rewarded` (จุดจากใน `internal_credit_payment` เมื่อเป็น order
  เติมเงินแรกของ referee) | `attributed|rewarded → voided` (admin จับ fraud —
  rewarded ที่ void ต้องทำ reversing ledger คู่กัน)

### 4.9 Seer earning & payout

#### 4.9.1 `seer_earning`

ตอบคำถาม: "รายได้ของ seer รายการนี้มาจากงานไหน กี่ coin คิดเป็นเงินเท่าไหร่" —
**reporting projection** เขียนใน transaction เดียวกับ ledger settle (income history/summary
query ได้โดยไม่ scan ledger); source of truth เชิงบัญชียังคือ ledger

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `source_type` | `text` | NO | — | CHECK IN (`question`,`call`,`call_extension`,`tip`,`gift`) |
| `source_id` | `text` | NO | — | id ของงานต้นทาง |
| `gross_coin` | `bigint` | NO | — | coin ที่ user จ่ายทั้งก้อน CHECK `> 0` |
| `seer_coin` | `bigint` | NO | — | ส่วนของ seer หลังหักแพลตฟอร์ม CHECK `>= 0 AND seer_coin <= gross_coin` |
| `revenue_share_bps` | `integer` | NO | — | snapshot อัตราส่วนแบ่ง ณ ตอน settle |
| `ledger_transaction_id` | `uuid` | NO | — | FK → `ledger_transaction(id)` — โยงกลับหลักฐานบัญชี |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (source_type, source_id)` — งานเดียวเกิดรายได้ครั้งเดียว
- Indexes: `(seer_id, created_at DESC)` — income history + summary ช่วงเวลา
- Append-only; RLS: **owner-read** (seer อ่านของตัวเองได้ตรง — เป็น projection ไม่ใช่บัญชีจริง
  จึงเปิด read ได้โดยไม่ผิดกฎ deny-all ของ money core); เขียน deny (internal เท่านั้น)

#### 4.9.2 `payout_account`

ตอบคำถาม: "seer คนนี้ให้โอนเงินเข้าบัญชีธนาคารไหน" — PII การเงิน

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `bank_code` | `text` | NO | — | รหัสธนาคารไทย (`scb`,`kbank`,...) จาก `app_config` |
| `account_number_encrypted` | `bytea` | NO | — | เข้ารหัส (pgsodium/Vault — ดูส่วนที่ 11) |
| `account_number_last4` | `text` | NO | — | แสดงผล |
| `account_holder_name` | `text` | NO | — | ชื่อบัญชี (ต้องตรง KYC) |
| `verify_status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`verified`,`rejected`) |
| `deleted_at` | `timestamptz` | YES | — | soft delete (เก็บไว้ audit payout เก่า) |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (seer_id) WHERE deleted_at IS NULL` — บัญชีรับเงิน active ทีละหนึ่ง
- RLS: owner-read (เห็นเฉพาะ last4 ผ่าน view `v_my_payout_account` — ตาราง raw deny-all);
  เขียนผ่าน RPC `set_payout_account` (encrypt ในนั้น)
- State: `pending → verified | rejected` (admin ตรวจกับเอกสาร KYC)

#### 4.9.3 `payout_request`

ตอบคำถาม: "คำขอถอนเงินของ seer อยู่ขั้นไหน จ่ายจริงเมื่อไหร่ เท่าไหร่"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `payout_account_id` | `uuid` | NO | — | FK → `payout_account(id)` ON DELETE RESTRICT (snapshot ปลายทาง) |
| `coin_amount` | `bigint` | NO | — | coin ที่ถอน CHECK `> 0` |
| `fiat_amount_minor` | `bigint` | NO | — | เงินโอนจริง (satang) = coin × rate − fee − withholding |
| `conversion_rate_micro` | `bigint` | NO | — | satang ต่อ coin × 10^6 (snapshot อัตราแปลง) |
| `fee_minor` | `bigint` | NO | `0` | ค่าธรรมเนียม CHECK `>= 0` |
| `withholding_tax_minor` | `bigint` | NO | `0` | ภาษีหัก ณ ที่จ่าย CHECK `>= 0` |
| `currency` | `char(3)` | NO | `'THB'` | |
| `status` | `text` | NO | `'requested'` | CHECK IN (`requested`,`approved`,`paid`,`rejected`,`cancelled`) |
| `provider_reference` | `text` | YES | — | อ้างอิงรายการโอน (เลขที่โอน/batch) |
| `reject_reason` | `text` | YES | — | |
| `reviewed_by` | `uuid` | YES | — | FK → `account(id)` ON DELETE SET NULL |
| `paid_at` | `timestamptz` | YES | — | |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (seer_id) WHERE status IN ('requested','approved')` — ถอนค้างทีละรายการ
- Indexes: `(seer_id, created_at DESC)`; `(status) WHERE status IN ('requested','approved')` — คิว admin
- RLS: deny-all; seer สร้างผ่าน RPC `request_payout` (lock wallet → ย้าย `payable_coin`
  ออกทันทีด้วย ledger `payout` operation ตอน `requested` เลย เพื่อกันถอนซ้อน — ถ้า
  rejected/cancelled ทำ reversing คืน), อ่านผ่าน `v_my_payout_history`
- State: `requested → approved → paid` | `requested → rejected|cancelled(seer)` |
  `approved → rejected` (ก่อนโอนจริง); `paid` terminal

### 4.10 Horoscope & AI (domain ใหม่)

#### 4.10.1 `birth_profile`

ตอบคำถาม: "ข้อมูลดวงกำเนิดที่ user บันทึกไว้ (ของตัวเองหรือคนใกล้ตัว) มีอะไรบ้าง" — PII อ่อนไหว

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `label` | `text` | NO | — | ชื่อเรียก เช่น "ตัวเอง", "แม่" CHECK length 1–50 |
| `is_self` | `boolean` | NO | `false` | โปรไฟล์ของเจ้าของบัญชีเอง |
| `birth_date` | `date` | NO | — | |
| `birth_time` | `time` | YES | — | NULL = ไม่ทราบเวลาเกิด |
| `birth_time_known` | `boolean` | NO | `false` | |
| `birth_place` | `text` | YES | — | ชื่อจังหวัด/เมือง (แสดงผล) |
| `latitude` / `longitude` | `numeric(9,6)` | YES | — | พิกัดสำหรับผูกดวง (optional) |
| `gender` | `text` | YES | — | CHECK IN (`male`,`female`,`other`) |
| `zodiac_sign` | `text` | NO | — | GENERATED-equivalent: คำนวณใน trigger จาก `birth_date` — ราศีสุริยคติ 12 ค่า (`aries`..`pisces`) |
| `chinese_zodiac` | `text` | YES | — | นักษัตร 12 ค่า คำนวณจากปีเกิด |
| `deleted_at` | `timestamptz` | YES | — | soft delete |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (account_id) WHERE is_self AND deleted_at IS NULL` — โปรไฟล์ตัวเองหนึ่งเดียว;
  จำนวนโปรไฟล์ต่อบัญชี ≤ 10 (ตรวจใน trigger)
- Indexes: `(account_id) WHERE deleted_at IS NULL`
- RLS: **owner-read / owner-write** (insert/update/soft-delete ของตัวเอง; `zodiac_*` trigger คุม)

#### 4.10.2 `horoscope_content`

ตอบคำถาม: "คำทำนายสำเร็จรูป (รายวัน/รายสัปดาห์ ต่อราศี) วันนี้คืออะไร" — content ที่ทีม/AI
ผลิตล่วงหน้าแล้ว publish; ทุก user ราศีเดียวกันอ่านชิ้นเดียวกัน (ต้นทุน AI คงที่ต่อวัน ไม่โตตาม user)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `content_type` | `text` | NO | — | CHECK IN (`daily`,`weekly`,`monthly`) |
| `zodiac_sign` | `text` | NO | — | 12 ราศี หรือ `all` (บทความรวม) |
| `for_date` | `date` | NO | — | วันที่ (daily) หรือวันแรกของช่วง (weekly/monthly) |
| `title` | `text` | NO | — | |
| `body` | `jsonb` | NO | — | โครงสร้างคำทำนาย: `{overall, love, work, finance, lucky_number, lucky_color}` |
| `author_type` | `text` | NO | `'ai'` | CHECK IN (`ai`,`editorial`) |
| `status` | `text` | NO | `'draft'` | CHECK IN (`draft`,`published`,`archived`) |
| `published_at` | `timestamptz` | YES | — | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (content_type, zodiac_sign, for_date)`
- Indexes: unique ข้างบนครอบ query หลัก (`WHERE content_type='daily' AND zodiac_sign=$1 AND for_date=current_date`)
- RLS: **public-read เมื่อ `status='published'`**; เขียน service role (job ผลิตดวงรายวัน)
- State: `draft → published → archived`

#### 4.10.3 `ai_reading_session`

ตอบคำถาม: "การดูดวงด้วย AI ครั้งนี้ ของใคร หัวข้ออะไร ใช้โมเดลไหน เสร็จหรือยัง ต้นทุนเท่าไหร่"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `birth_profile_id` | `uuid` | YES | — | FK → `birth_profile(id)` ON DELETE SET NULL |
| `topic` | `text` | NO | — | CHECK IN (`overall`,`love`,`career`,`finance`,`health`,`custom`) |
| `status` | `text` | NO | `'created'` | CHECK IN (`created`,`generating`,`completed`,`failed`) |
| `charge_type` | `text` | NO | — | CHECK IN (`free_quota`,`coin`) |
| `price_coin` | `bigint` | NO | `0` | CHECK `(charge_type='coin') = (price_coin > 0)` |
| `provider` | `text` | YES | — | AI provider ที่ใช้ (เช่น `anthropic`) — NULL จนเริ่ม generate |
| `model` | `text` | YES | — | model id ที่ใช้จริง |
| `input_tokens` / `output_tokens` | `integer` | YES | — | usage จริง |
| `cost_micro_usd` | `bigint` | YES | — | ต้นทุน provider หน่วย micro-USD (10^-6) — cost tracking ตาม brief |
| `error_code` | `text` | YES | — | เมื่อ failed |
| `completed_at` | `timestamptz` | YES | — | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(account_id, created_at DESC)` — ประวัติ; `(status, created_at) WHERE status IN ('created','generating')` — cron เก็บ session ค้าง
- RLS: owner-read; เขียน — สร้างผ่าน RPC `start_ai_reading` (ตัด quota/coin ใน transaction
  เดียว) แล้ว Edge Function `ai-reading` (service role) เป็นคน update ระหว่าง generate
- State: `created → generating → completed | failed`; `failed` ที่ charge_type=`coin`
  → RPC ภายในทำ refund (reversing ledger, reference เดิม operation `refund`)

#### 4.10.4 `ai_reading_message`

ตอบคำถาม: "บทสนทนา/ผลคำทำนายใน session นี้คืออะไร" — เก็บทั้ง prompt แบบ structured
และคำตอบ (ไม่เก็บ system prompt เต็ม — เก็บ version อ้างอิง)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `session_id` | `uuid` | NO | — | FK → `ai_reading_session(id)` ON DELETE CASCADE |
| `role` | `text` | NO | — | CHECK IN (`user`,`assistant`) |
| `content` | `text` | NO | — | CHECK length ≤ 20000 |
| `prompt_version` | `text` | YES | — | อ้างอิงเวอร์ชัน system prompt (เก็บตัว prompt ใน repo ไม่ใช่ DB) |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(session_id, id)`
- RLS: อ่าน — owner ผ่าน helper `is_ai_session_owner(session_id)`; เขียน — deny
  (RPC/Edge Function เท่านั้น — user ส่งคำถาม custom ผ่าน `start_ai_reading` ไม่ใช่ insert ตรง)

#### 4.10.5 `ai_usage_quota`

ตอบคำถาม: "วันนี้ user คนนี้ใช้สิทธิ์ AI ฟรีไปกี่ครั้งแล้ว" — counter ต่อวัน (atomic increment)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `account_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `account(id)` ON DELETE CASCADE |
| `quota_date` | `date` | NO | — | PK ส่วนสอง (วันตาม `Asia/Bangkok`) |
| `free_used` | `smallint` | NO | `0` | CHECK `free_used >= 0` |
| `paid_used` | `smallint` | NO | `0` | นับรวมเพื่อ rate cap ต่อวัน |
| `updated_at` | `timestamptz` | NO | `now()` | |

- PK `(account_id, quota_date)`; เพดานฟรี/วัน อ่านจาก `app_config` key `ai.free_quota_per_day`
  ใน RPC (`INSERT ... ON CONFLICT DO UPDATE SET free_used = free_used + 1 WHERE free_used < cap`)
- RLS: owner-read (โชว์ "เหลือสิทธิ์ฟรี x ครั้ง"); เขียน deny (RPC)
- Retention: cron ลบแถวเก่ากว่า 90 วัน

### 4.11 Live stream & gift (domain ใหม่ — feature-flagged)

> เปิด/ปิดทั้ง context ด้วย `app_config` key `feature.live_enabled`; ไม่มี FK จาก context อื่น
> ชี้เข้ามา ตัดออกแล้วระบบที่เหลือทำงานครบ
> **ตัดสินใจสำคัญ: แชทในไลฟ์เป็น Realtime broadcast ephemeral — ไม่เก็บลง DB**
> (เหตุผล: ห้องดูฟรีเพื่อ campaign, ข้อความไม่มีมูลค่า replay, ปริมาณเขียนจะกิน free tier
> เร็วที่สุดในระบบ; การ report ข้อความแนบ snapshot จาก client ลง `user_report.evidence`)
> สิ่งที่เก็บ = สิ่งที่เป็นเงินหรือ audit: ห้อง, gift

#### 4.11.1 `live_room`

ตอบคำถาม: "ไลฟ์ครั้งนี้ใครจัด เมื่อไหร่ สถานะอะไร คนดูสูงสุดเท่าไหร่"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT (เจ้าของไลฟ์) |
| `title` | `text` | NO | — | CHECK length 1–100 |
| `cover_url` | `text` | YES | — | |
| `status` | `text` | NO | `'scheduled'` | CHECK IN (`scheduled`,`live`,`ended`,`cancelled`) |
| `provider` | `text` | YES | — | media provider (`livekit`,`agora`,`mux`) — NULL จน start |
| `provider_room_name` | `text` | YES | — | UNIQUE WHERE NOT NULL |
| `scheduled_at` | `timestamptz` | YES | — | เวลานัดไลฟ์ (โชว์ล่วงหน้า) |
| `started_at` / `ended_at` | `timestamptz` | YES | — | |
| `peak_viewer_count` | `integer` | NO | `0` | สถิติ (อัปเดตเป็นช่วง ๆ จาก presence โดย Edge Function) |
| `total_gift_coin` | `bigint` | NO | `0` | projection ยอด gift รวม (อัปเดตใน RPC `send_gift`) |
| `version` | `integer` | NO | `1` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (seer_id) WHERE status IN ('scheduled','live')` — ไลฟ์ค้างทีละห้อง
- Indexes: `(status, started_at DESC) WHERE status='live'` — หน้ารวมไลฟ์ที่กำลังฉาย;
  `(seer_id, created_at DESC)`
- RLS: อ่าน public-read (ห้องดูฟรี); เขียน — RPC (`create_live_room`, `start_live`,
  `end_live`) เพราะต้อง mint media room + คุม unique ห้องค้าง
- State: `scheduled → live → ended` | `scheduled → cancelled`; cron ปิดห้องที่ `live`
  ค้างเกิน max duration

#### 4.11.2 `gift`

ตอบคำถาม: "ของขวัญที่ส่งในไลฟ์มีอะไรบ้าง ราคากี่ coin" — catalog

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `integer` | NO | identity | PK |
| `code` | `text` | NO | — | UNIQUE เช่น `rose`, `crystal_ball` |
| `name` | `text` | NO | — | |
| `asset_url` | `text` | NO | — | ภาพ/animation |
| `price_coin` | `bigint` | NO | — | CHECK `> 0` |
| `sort_order` | `integer` | NO | `0` | |
| `is_enabled` | `boolean` | NO | `true` | |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- RLS: public-read เมื่อ `is_enabled`; เขียน service role

#### 4.11.3 `gift_transaction`

ตอบคำถาม: "ใครส่ง gift อะไรในไลฟ์ไหน กี่ชิ้น กี่ coin" — append-only, ledger-backed

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `live_room_id` | `uuid` | NO | — | FK → `live_room(id)` ON DELETE RESTRICT |
| `sender_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT |
| `seer_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE RESTRICT (denorm จากห้อง — RLS/รายงานไม่ต้อง join) |
| `gift_id` | `integer` | NO | — | FK → `gift(id)` ON DELETE RESTRICT |
| `quantity` | `integer` | NO | `1` | CHECK `quantity BETWEEN 1 AND 99` |
| `total_coin` | `bigint` | NO | — | snapshot `price_coin × quantity` CHECK `> 0` |
| `client_gift_id` | `uuid` | NO | — | idempotency จาก client |
| `created_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (sender_id, client_gift_id)` — spam กดรัวไม่ post ซ้ำ
- Indexes: `(live_room_id, id)` — feed gift ในห้อง; `(seer_id, created_at DESC)` — รายได้ gift
- Append-only; RLS: อ่าน — public-read (โชว์ gift feed ในห้อง — ไม่มี PII เกิน display);
  เขียน deny-all (RPC `send_gift`: lock wallet → ตัด coin → settle เข้า seer_payable +
  revenue ทันที (ไม่มี escrow — gift จบในตัว) → insert แถวนี้ + outbox broadcast)

### 4.12 Notification & outbox

#### 4.12.1 `notification_inbox`

ตอบคำถาม: "กระดิ่งของบัญชีนี้มีแจ้งเตือนอะไร อ่านหรือยัง"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `notification_type` | `text` | NO | — | CHECK IN (`message`,`question_update`,`appointment`,`call`,`coin_credited`,`payout`,`system`,`live_started`,`horoscope`) |
| `title` | `text` | NO | — | |
| `body` | `text` | NO | — | |
| `deep_link` | `text` | YES | — | route แบบ platform-neutral เช่น `chata://question/{uuid}` |
| `payload` | `jsonb` | NO | `'{}'` | aggregate id/version สำหรับ client reconcile |
| `read_at` | `timestamptz` | YES | — | |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(account_id, id DESC)` — เปิดกระดิ่ง; `(account_id) WHERE read_at IS NULL` — badge count
- RLS: owner-read; เขียน — UPDATE ได้เฉพาะ `read_at` ของตัวเอง (mark-as-read ตรงผ่าน RLS
  ตาม brief §4 — เขียนไม่แตะเงิน); INSERT โดย worker/trigger เท่านั้น
- Retention: cron ลบแถวอ่านแล้วเก่ากว่า 90 วัน / ยังไม่อ่านเก่ากว่า 180 วัน

#### 4.12.2 `outbox_event`

ตอบคำถาม: "side effect อะไรที่ commit แล้วแต่ยังไม่ถูกส่งออก" — หัวใจ delivery (ดูส่วนที่ 9)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `aggregate_type` | `text` | NO | — | `question`,`call`,`payment_order`,`payout_request`,`live_room`,`account`,... |
| `aggregate_id` | `text` | NO | — | |
| `event_type` | `text` | NO | — | `question.message.created`, `payment.credited`, `call.offered`, ... |
| `payload` | `jsonb` | NO | — | ข้อมูลพอสำหรับ consumer — **ห้ามมี token/secret/เนื้อความส่วนตัวเต็ม** |
| `status` | `text` | NO | `'pending'` | CHECK IN (`pending`,`processing`,`published`,`dead`) |
| `attempts` | `smallint` | NO | `0` | |
| `next_attempt_at` | `timestamptz` | NO | `now()` | backoff scheduling |
| `last_error` | `text` | YES | — | |
| `published_at` | `timestamptz` | YES | — | |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(next_attempt_at) WHERE status IN ('pending','processing')` — dispatcher claim;
  `(aggregate_type, aggregate_id)` — debug ต่อ aggregate
- RLS: deny-all
- State: `pending → processing → published` | `processing → pending` (retry+backoff) |
  `→ dead` เมื่อ `attempts >= 8` (ดู 9.3)

### 4.13 Config & ops

#### 4.13.1 `app_config`

ตอบคำถาม: "ค่า config/feature flag ฝั่ง server ปัจจุบันคืออะไร" — แทน bootstrap catalog
ที่สังเกตได้จาก client contract (tip amounts, ธนาคารรับโอน, เพดานต่าง ๆ) + feature flags

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `key` | `text` | NO | — | PK เช่น `feature.live_enabled`, `ai.free_quota_per_day`, `payment.banks`, `tip.amounts`, `question.reply_deadline_hours`, `call.reservation_ttl_seconds`, `payout.min_coin`, `payout.conversion_rate_micro`, `payment.method_psp_matrix` |
| `value` | `jsonb` | NO | — | ค่า (type ตาม key — validate ในโค้ดที่อ่าน) |
| `is_public` | `boolean` | NO | `false` | true = client อ่านได้ (bootstrap) |
| `description` | `text` | NO | — | อธิบายว่า key นี้คุมอะไร |
| `updated_at` | `timestamptz` | NO | `now()` | |

- RLS: อ่าน — `is_public = true` เท่านั้น (config ภายในเช่น cost cap ไม่ leak); เขียน service role
- RPC ทุกตัวอ่าน config ผ่าน helper `get_config(key)` (STABLE, SECURITY DEFINER)

#### 4.13.2 `rate_limit_counter`

ตอบคำถาม: "หน่วยนับ rate limit ของ (ใคร, bucket, หน้าต่างเวลา) นี้ ใช้ไปเท่าไหร่" —
fixed-window counter บนตารางตาม brief §5 (ไม่มี Redis)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `subject` | `text` | NO | — | PK ส่วนแรก — `acct:<uuid>` หรือ `ip:<addr>` (ip เฉพาะทาง Edge Function) |
| `bucket` | `text` | NO | — | PK ส่วนสอง — `financial`,`consultation_write`,`standard_write`,`auth_abuse`,`ai`,`gift` (ชุด bucket ตาม policy ที่ reverse ยืนยัน) |
| `window_start` | `timestamptz` | NO | — | PK ส่วนสาม — ปัดลงเป็นนาที |
| `count` | `integer` | NO | `1` | |

- PK `(subject, bucket, window_start)`; helper `check_rate_limit(bucket, limit, window)` —
  `INSERT ... ON CONFLICT DO UPDATE SET count = count + 1 RETURNING count` แล้วเทียบ limit
  → เรียกที่ต้น RPC ทุกตัวที่เป็น write
- Indexes: `(window_start)` — cron ลบแถวเก่ากว่า 1 วัน ทุกชั่วโมง
- RLS: deny-all

### 4.14 Moderation & audit

#### 4.14.1 `block_relation`

ตอบคำถาม: "seer คนไหน block user คนไหน" — ทิศทางเดียว (seer → user) ตาม flow ที่สังเกตได้

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `seer_id` | `uuid` | NO | — | PK ส่วนแรก, FK → `account(id)` ON DELETE CASCADE |
| `user_id` | `uuid` | NO | — | PK ส่วนสอง, FK → `account(id)` ON DELETE CASCADE |
| `reason` | `text` | YES | — | |
| `created_at` | `timestamptz` | NO | `now()` | |

- PK `(seer_id, user_id)`; `CHECK (seer_id <> user_id)`
- Indexes: `(user_id)` — ตอน user จะซื้อบริการ ตรวจโดน block ไหม
- RLS: อ่าน — seer เห็นรายการ block ของตัวเอง (owner-read ฝั่ง seer เท่านั้น —
  user **ไม่เห็น**ว่าตัวเองโดน block ผ่านการอ่านตรง; ผลโผล่เป็น error ตอนซื้อ); เขียน —
  seer insert/delete ของตัวเอง; RPC ฝั่งซื้อ/ส่งข้อความตรวจตารางนี้เสมอ

#### 4.14.2 `user_report`

ตอบคำถาม: "ใคร report ใคร/อะไร ด้วยเหตุอะไร ทีมจัดการถึงไหนแล้ว"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `reporter_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `target_type` | `text` | NO | — | CHECK IN (`account`,`question`,`review`,`live_room`) |
| `target_id` | `text` | NO | — | id ของสิ่งที่ถูก report |
| `reason` | `text` | NO | — | CHECK IN (`inappropriate`,`scam`,`harassment`,`spam`,`other`) |
| `detail` | `text` | YES | — | CHECK length ≤ 2000 |
| `evidence` | `jsonb` | NO | `'{}'` | snapshot หลักฐานจาก client (เช่น ข้อความไลฟ์ที่เป็น ephemeral) |
| `status` | `text` | NO | `'open'` | CHECK IN (`open`,`reviewing`,`actioned`,`dismissed`) |
| `created_at` / `updated_at` | `timestamptz` | NO | `now()` | |

- Constraints: `UNIQUE (reporter_id, target_type, target_id)` — report ซ้ำเรื่องเดิมไม่ได้
- Indexes: `(status, created_at) WHERE status IN ('open','reviewing')` — คิวทีม
- RLS: อ่าน — owner-read (คน report เห็นสถานะคำร้องตัวเอง); เขียน — owner insert;
  `status` เปลี่ยนโดย service role
- State: `open → reviewing → actioned | dismissed`

#### 4.14.3 `moderation_action`

ตอบคำถาม: "แพลตฟอร์มเคยลงโทษ/แทรกแซงบัญชีหรือ content ไหน อย่างไร โดยใคร"

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | PK |
| `target_account_id` | `uuid` | NO | — | FK → `account(id)` ON DELETE CASCADE |
| `action_type` | `text` | NO | — | CHECK IN (`warn`,`suspend`,`unsuspend`,`hide_content`,`live_ban`,`debt_flag`) — `live_ban` แบน join ไลฟ์ (Edge Function ตรวจก่อน mint token); `debt_flag` = ส่วนขาดจาก chargeback (4.6.1) |
| `scope_type` | `text` | YES | — | CHECK IN (`live_room`,`review`,`question`) เมื่อ action จำกัดขอบเขต |
| `scope_id` | `text` | YES | — | |
| `reason` | `text` | NO | — | |
| `user_report_id` | `uuid` | YES | — | FK → `user_report(id)` ON DELETE SET NULL — action นี้มาจาก report ไหน |
| `expires_at` | `timestamptz` | YES | — | โทษชั่วคราว (NULL = ถาวรจน revoke) |
| `revoked_at` | `timestamptz` | YES | — | |
| `created_by` | `uuid` | YES | — | FK → `account(id)` (admin) ON DELETE SET NULL |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(target_account_id) WHERE revoked_at IS NULL` — ตรวจโทษ active
- RLS: deny-all (admin ผ่าน service role; ผลโทษสื่อสารผ่าน notification)

#### 4.14.4 `audit_log`

ตอบคำถาม: "เหตุการณ์สำคัญเชิงระบบ/แอดมินอะไรเกิดขึ้น เมื่อไหร่ โดยใคร" — append-only,
เก็บเหตุการณ์ที่ไม่ใช่บัญชีเงิน (เงินมี ledger เป็น audit ในตัวแล้ว)

| column | type | null? | default | คำอธิบาย |
|---|---|---|---|---|
| `id` | `bigint` | NO | identity | PK |
| `actor_type` | `text` | NO | — | CHECK IN (`user`,`seer`,`admin`,`system`) |
| `actor_id` | `uuid` | YES | — | FK → `account(id)` ON DELETE SET NULL; NULL = system |
| `action` | `text` | NO | — | `account.suspended`, `payout.approved`, `config.changed`, `seer.approved`, `deletion.purged`, ... |
| `target_type` | `text` | YES | — | |
| `target_id` | `text` | YES | — | |
| `detail` | `jsonb` | NO | `'{}'` | ค่าเดิม/ค่าใหม่ (redact PII ตามนโยบายส่วนที่ 11) |
| `created_at` | `timestamptz` | NO | `now()` | |

- Indexes: `(target_type, target_id, created_at DESC)`; `(actor_id, created_at DESC)`
- Append-only; RLS: deny-all

---

## ส่วนที่ 5 — Money & ledger

### 5.1 ผังบัญชี (chart of accounts)

Ledger ทำงานใน**หน่วย coin เท่านั้น** (fiat อยู่ที่ `payment_order`/`payout_request` เป็น
snapshot การแลกเปลี่ยนกับโลกภายนอก) บัญชีมี 2 ระดับ:

| ledger_account | ระดับ | ความหมาย | sign ปกติ |
|---|---|---|---|
| `user_available` | per-account | coin ใช้จ่ายได้ของ user | เพิ่ม = ได้ coin |
| `user_reserved` | per-account | coin ถูก escrow ระหว่างงานยังไม่จบ | เพิ่ม = ถูกจอง |
| `seer_payable` | per-account | ยอดค้างจ่ายของ seer | เพิ่ม = รายได้เข้า |
| `platform_revenue` | system | ส่วนแบ่งแพลตฟอร์มสะสม | เพิ่ม = รายได้แพลตฟอร์ม |
| `platform_promotion` | system | แหล่ง coin โปรโมชัน (voucher/referral/bonus) — contra ฝั่งค่าใช้จ่ายการตลาด | ลบสะสม |
| `coin_supply` | system | coin ทั้งหมดที่หมุนเวียนในระบบ (contra: ออกตอนซื้อ กลับตอน payout/คืนเงิน fiat) | ลบสะสม |

Invariant ระดับระบบ (job reconcile ตรวจรายวัน):
`SUM(user_available) + SUM(user_reserved) + SUM(seer_payable) + platform_revenue
+ platform_promotion + coin_supply = 0` และ balance ทุกบัญชี per-account ตรงกับ `wallet`

### 5.2 ตารางเหตุการณ์ → debit/credit → idempotency reference

สัญกรณ์: `+` = amount บวก (เงินเข้าบัญชีนั้น), `-` = ลบ; ทุกแถวรวมเป็นศูนย์
`share` = `seer_coin` ตาม `revenue_share_bps`, `fee` = ส่วนแพลตฟอร์ม

| เหตุการณ์ | ขาบัญชี | reference (`type`, `id`, `operation`) |
|---|---|---|
| เติมเงินสำเร็จ (IAP/โอน/PromptPay/card) | `coin_supply −(coin)`, `user_available +(coin)`; ถ้ามี bonus: `platform_promotion −(bonus)`, `user_available +(bonus)` (ขา bonus อยู่ transaction เดียวกัน) | `payment_order`, order id, `credit_purchase` |
| ซื้อคำถาม (submit_question) | `user_available −P`, `user_reserved +P` | `question`, question id, `reserve` |
| จบคำถาม (settle) | `user_reserved −P`, `seer_payable +share`, `platform_revenue +fee` | `question`, question id, `settle` |
| ยกเลิก/คืนเงินคำถาม | `user_reserved −P`, `user_available +P` | `question`, question id, `refund` |
| จอง call (reserve) | `user_available −R`, `user_reserved +R` | `call_transaction`, call id, `reserve` |
| charge call ครั้งแรก (เริ่ม active) | `user_reserved −R`, `seer_payable +share`, `platform_revenue +fee` | `call_transaction`, call id, `settle` |
| ปล่อย reservation (cancel/reject/expire/fail) | `user_reserved −R`, `user_available +R` | `call_transaction`, call id, `refund` |
| extend call ครั้งที่ n | `user_available −E`, `seer_payable +share`, `platform_revenue +fee` (ไม่ผ่าน escrow — จ่ายจบทันที) | `call_extension`, extension id, `settle` |
| tip (แนบรีวิว) | `user_available −T`, `seer_payable +share`, `platform_revenue +fee` | `review`, review id, `tip` |
| gift ในไลฟ์ | `user_available −G`, `seer_payable +share`, `platform_revenue +fee` | `gift_transaction`, gift tx id, `gift` |
| redeem voucher | `platform_promotion −V`, `user_available +V` | `voucher_redemption`, redemption id, `redeem` |
| referral bonus (สองฝั่ง — คนละ transaction) | `platform_promotion −B`, `user_available +B` | `referral_attribution`, attribution id, `referral_bonus` (ฝั่ง referee ใช้ operation `referral_bonus_referee`) |
| ซื้อ AI reading | `user_available −A`, `platform_revenue +A` | `ai_reading_session`, session id, `ai_charge` |
| AI reading ล้มเหลว (คืน) | reversing ของแถวบน | `ai_reading_session`, session id, `refund` |
| payout ให้ seer (ตอน `requested`) | `seer_payable −C`, `coin_supply +C` | `payout_request`, payout id, `payout` |
| payout ถูก reject/cancel | reversing: `coin_supply −C`, `seer_payable +C` | `payout_request`, payout id, `reversal` |
| chargeback/refund fiat | reversing ของ `credit_purchase` (`reversal_of` ชี้ transaction เดิม): `user_available −(coin)`, `coin_supply +(coin)` — หักเท่าที่ available มี ส่วนขาดลง `moderation_action(debt_flag)` | `payment_order`, order id, `reversal` |
| admin ปรับยอด (ต้องมี note) | ขาตามกรณี | `manual_adjustment`, adjustment uuid, `adjustment` |

กติกา reversal: reversing transaction คือ transaction ใหม่ที่ทุกขาเป็นค่าลบกลับด้านของต้นฉบับ
`reversal_of` ชี้กลับ และ unique บน `reversal_of` กันกลับซ้ำ — **ห้าม** UPDATE/DELETE ต้นฉบับ

### 5.3 Function เดียวที่เขียน ledger: `internal_post_ledger`

```
internal_post_ledger(
  p_reference_type text, p_reference_id text, p_operation text,
  p_entries jsonb,          -- [{ledger_account, account_id, amount}, ...]
  p_reversal_of uuid default null, p_note text default null
) returns uuid              -- ledger_transaction.id
```

ภายใน (เรียกได้จาก RPC อื่น/service role เท่านั้น — `REVOKE EXECUTE FROM authenticated`):

1. INSERT `ledger_transaction` — ถ้าชน unique `(reference_type, reference_id, operation)`
   → คืน id เดิม (idempotent, ไม่ post ซ้ำ)
2. INSERT `ledger_entry` ทุกขา (constraint trigger ตรวจ sum=0 ตอน commit)
3. อัปเดต `wallet` ของทุก `account_id` ที่โผล่ในขา (แถวถูก lock ไว้แล้วโดย RPC ผู้เรียก —
   ดู 5.5) พร้อมเขียน `balance_after` ลง entry
4. คืน transaction id ให้ผู้เรียกเก็บอ้างอิง (`seer_earning.ledger_transaction_id` ฯลฯ)

### 5.4 วิธีเก็บ balance: projection ใน transaction เดียวกัน

ตัดสินใจ: **`wallet` เป็น projection ที่อัปเดตพร้อม ledger ใน transaction เดียว** ไม่ derive สด

- อ่าน balance คือ query ที่ถี่ที่สุดของระบบ (ทุกหน้าจอ, ทุกครั้งก่อนซื้อ) — `SUM(ledger_entry)`
  ต่อครั้งไม่มีเหตุผลเชิงต้นทุน และบน free tier ยิ่งต้องประหยัด compute
- แถว `wallet` เป็น row-lock anchor กัน double-spend อยู่แล้ว (5.5) — ได้สองหน้าที่ในแถวเดียว
- ความเสี่ยง drift แก้ด้วย (ก) เขียนได้จาก `internal_post_ledger` ทางเดียว
  (ข) `balance_after` ใน entry ทำให้ตรวจย้อนได้ทุกจุด (ค) cron reconcile รายวันเทียบ
  `wallet` กับ `SUM(ledger_entry)` — ไม่ตรง = alert + หยุด payout อัตโนมัติ

### 5.5 Locking / concurrency / กัน double-spend

ตัดสินใจ: **row lock บน `wallet` (`SELECT ... FOR UPDATE`) + isolation `READ COMMITTED`**
ไม่ใช้ SERIALIZABLE ทั้งระบบ

- ทุก financial RPC เปิดฉากด้วย lock แถว `wallet` ของ**ทุกบัญชีที่จะแตะ** เรียงตาม
  `account_id` (กัน deadlock ด้วย global lock order); บัญชี system ไม่มีแถว wallet
  จึงไม่ต้อง lock (append-only ล้วน)
- ลำดับใน RPC: lock wallet → ตรวจ rate limit → ตรวจ idempotency_key → ตรวจ state/เงื่อนไข
  (block, service enabled, ราคา) → post ledger → update state ของ aggregate → insert outbox
  → บันทึก idempotency response → commit
- Double-spend กัน 3 ชั้น: (1) wallet lock ทำให้การหักเงินต่อบัญชี serialize,
  (2) CHECK `available_coin >= 0` — ต่อให้ logic พลาด ยอดไม่มีวันติดลบ,
  (3) `ledger_transaction` unique — เหตุการณ์เดียว post ซ้ำไม่ได้แม้ retry จากคนละ connection
- เหตุผลไม่ใช้ SERIALIZABLE: ต้อง retry-loop ทุก client ของ RPC (PostgREST ไม่ retry ให้),
  ประโยชน์ที่ได้ทับซ้อนกับ wallet lock ซึ่งแคบกว่าและคาดเดา contention ได้; hot row
  ต่อ user คือพฤติกรรมปกติของ wallet app — lock สั้นระดับ ms ต่อ transaction รับได้

---

## ส่วนที่ 6 — Transaction boundary & RPC contract

### 6.1 RPC `SECURITY DEFINER` (client เรียกผ่าน PostgREST `/rpc/...`)

กติการ่วมทุกตัว: `SECURITY DEFINER`, `search_path = public, pg_temp`; แถว wallet ถูก lock
ก่อนแตะเงิน; ทุก error เป็น `RAISE EXCEPTION USING ERRCODE, MESSAGE = code ที่ client แปลได้`
(`insufficient_coin`, `invalid_state`, `not_participant`, `blocked`, `rate_limited`,
`idempotency_conflict`, ...) — ตารางนี้ระบุเฉพาะ error เชิง domain

| function | input | ทำใน transaction เดียว | idempotency key | error หลัก |
|---|---|---|---|---|
| `submit_question` | `seer_service_id, first_message text, client_message_id uuid, p_key uuid` | ตรวจ seer approved+active+service enabled+ไม่โดน block → อ่านราคา → lock wallet user → ledger `reserve` → insert `question`(expires_at จาก config) + `question_message` แรก → outbox `question.submitted` | `p_key` + ledger(`question`,id,`reserve`) | `insufficient_coin`, `seer_unavailable`, `blocked` |
| `cancel_question` | `question_id, p_key` | CAS status `submitted→cancelled_refunded` (เฉพาะ user, ก่อน seer ตอบ) → ledger `refund` → system message → outbox | `p_key` + ledger `refund` | `invalid_state`, `not_participant` |
| `request_close_question` | `question_id, p_key` | CAS `active→close_requested` บันทึกผู้ขอ → system message → outbox | `p_key` | `invalid_state` |
| `cancel_close_request` | `question_id, p_key` | CAS `close_requested→active` (เฉพาะผู้ขอเดิม) | `p_key` | `invalid_state` |
| `respond_close_question` | `question_id, accept boolean, p_key` | ผู้ตอบต้องไม่ใช่ผู้ขอ; accept: CAS →`completed` → ledger `settle` (แบ่งตาม level snapshot) → insert `seer_earning` → อัปเดต `seer_profile.question_count` → outbox; reject: CAS →`active` | `p_key` + ledger `settle` | `invalid_state`, `not_participant` |
| `submit_review` | `question_id?/call_transaction_id?, rating, comment?, tag_ids?, tip_coin, p_key` | ตรวจงาน completed + เป็นของ user + ยังไม่รีวิว → insert `review`; ถ้า tip>0: lock wallet → ledger `tip` + `seer_earning` → อัปเดต `rating_avg/count` → outbox | `p_key` + ledger(`review`,id,`tip`) | `invalid_state`, `already_reviewed`, `insufficient_coin` |
| `reply_review` | `review_id, reply text` | seer เจ้าของงานตั้ง `seer_reply` ครั้งเดียว | — (ไม่แตะเงิน, เขียนซ้ำ = error) | `not_owner`, `already_replied` |
| `propose_appointment` | `room_id?, seer_id?, scheduled_at, p_key` | สร้าง room ถ้ายังไม่มี → insert `appointment` pending (unique partial กันซ้อน) → outbox | `p_key` | `pending_exists` |
| `respond_appointment` | `appointment_id, accept, p_key` | CAS `pending→accepted/denied` (ผู้ตอบ ≠ ผู้เสนอ) → outbox + reminder schedule | `p_key` | `invalid_state`, `self_response` |
| `cancel_appointment` | `appointment_id, p_key` | CAS `pending/accepted→cancelled` (participant) → outbox | `p_key` | `invalid_state` |
| `reserve_call` | `seer_service_id, call_kind, p_key` | ตรวจ seer พร้อมรับ + ไม่ block + ไม่มีสายค้าง → อ่านราคา → lock wallet → ledger `reserve` → insert `call_transaction` reserved (`reservation_expires_at`) → outbox `call.requested` (แจ้ง seer → status `offered` โดย worker/broadcast) | `p_key` + ledger(`call`,id,`reserve`) | `insufficient_coin`, `seer_busy`, `user_busy` |
| `cancel_call` | `call_transaction_id, p_key` | CAS `reserved/offered→cancelled` (user) → ledger `refund` → outbox | `p_key` + ledger `refund` | `invalid_state` |
| `respond_call` | `call_transaction_id, accept, p_key` | seer: accept → CAS `offered→accepted` (ตรวจไม่เลย expiry); reject → CAS →`rejected` + ledger `refund` → outbox | `p_key` | `invalid_state`, `expired` |
| `start_call` | `call_transaction_id, p_key` | CAS `accepted→active` (เรียกโดย Edge Function media-token หลังทั้งคู่ join หรือโดย participant แรกที่ join สำเร็จ ตาม provider callback) → ledger `settle` ครั้งแรก + `seer_earning` → ตั้ง `started_at` → outbox | `p_key` + ledger(`call`,id,`settle`) | `invalid_state` |
| `extend_call` | `call_transaction_id, sequence_no, p_key` | ตรวจ status=`active` + seer เปิดรับ extension → อ่านราคาต่อช่วงจาก service → lock wallet → ledger extension `settle` → insert `call_extension` (unique sequence) → บวก `total_duration_seconds` → outbox | `p_key` + unique `(call_id, sequence_no)` + ledger(`call_extension`,id,`settle`) | `insufficient_coin`, `invalid_state`, `duplicate_sequence` |
| `end_call` | `call_transaction_id, end_reason, p_key` | CAS `active→completed` ตั้ง `ended_at`, `end_reason` (เรียกได้ทั้งสองฝั่ง — ครั้งแรก win, ครั้งถัดมาคืนผลเดิม) → outbox `call.completed` + media cleanup | `p_key` | `invalid_state` |
| `send_gift` | `live_room_id, gift_id, quantity, client_gift_id, p_key` | ตรวจ room `live` + feature flag + ไม่โดน live_ban → อ่านราคา gift → lock wallet → ledger `gift` (settle ทันที) → insert `gift_transaction` + `seer_earning` → บวก `total_gift_coin` → outbox broadcast | `p_key` + unique `(sender_id, client_gift_id)` + ledger `gift` | `insufficient_coin`, `room_not_live`, `banned` |
| `redeem_voucher` | `code text, p_key` | hash code → lock แถว `voucher` FOR UPDATE → ตรวจ active/ช่วงเวลา/จำนวนสิทธิ์/per-user → insert `voucher_redemption` → ledger `redeem` → บวก `redeemed_count` → outbox | `p_key` + unique `(voucher_id, account_id)` + ledger `redeem` | `invalid_code`, `voucher_exhausted`, `already_redeemed` |
| `start_ai_reading` | `topic, birth_profile_id?, custom_question?, p_key` | ตรวจ quota (`ai_usage_quota` upsert-increment) → ถ้าเกินฟรี: lock wallet + ledger `ai_charge` → insert `ai_reading_session`(`created`) + message user → outbox `ai.reading.requested` (worker เรียก Edge Function) | `p_key` + ledger(`ai_reading_session`,id,`ai_charge`) | `quota_exceeded`, `insufficient_coin` |
| `create_payment_order` | `coin_package_id, method, referral_code?, p_key` | ตรวจ package enabled + method อยู่ใน `allowed_methods` → เลือก `psp_code` ตัว active จาก `payment.method_psp_matrix` → validate referral → insert `payment_order`(`created`, snapshot ราคา/coin/method/psp) → คืน order id (+ ข้อมูลไปเปิด PSP checkout ผ่าน Edge Function) | `p_key` | `package_disabled`, `method_not_allowed`, `invalid_referral` |
| `attach_transfer_proof` | `payment_order_id, object_key, content_hash, bank_code, p_key` | ตรวจ order เป็นของ user + method=`bank_transfer` (psp_code=`manual`) + status `created` → insert `bank_transfer_proof` → CAS order →`pending_provider` → outbox แจ้ง admin | `p_key` + unique `content_hash` | `invalid_state`, `duplicate_slip` |
| `set_payout_account` | `bank_code, account_number, holder_name, p_key` | encrypt เลขบัญชี → soft-delete แถวเดิม → insert ใหม่ `pending` → outbox แจ้ง admin ตรวจ | `p_key` | `invalid_bank` |
| `request_payout` | `coin_amount, p_key` | ตรวจ payout_account `verified` + ไม่มีคำขอค้าง + `coin_amount >= min` → lock wallet → ledger `payout` (หัก payable ทันที) → insert `payout_request`(`requested`, snapshot rate/fee/tax จาก config) → outbox แจ้ง admin | `p_key` + ledger(`payout_request`,id,`payout`) | `insufficient_payable`, `pending_exists`, `account_not_verified` |
| `request_account_deletion` | `reason?, p_key` | ตรวจไม่มีเงินค้าง/งานค้าง → insert `account_deletion_request` (`scheduled_purge_at`=+7d) → outbox | `p_key` | `outstanding_balance`, `pending_exists` |
| `cancel_account_deletion` | `p_key` | CAS `requested→cancelled` | `p_key` | `invalid_state` |
| `create_live_room` / `start_live` / `end_live` | `(title, scheduled_at?) / (live_room_id) / (live_room_id)` + `p_key` | ตรวจ role seer + feature flag → CAS state + mint/ปิด provider room (ผ่าน outbox → Edge Function) → outbox `live.started/ended` | `p_key` | `live_disabled`, `room_exists`, `invalid_state` |

RPC ภายใน (`REVOKE FROM authenticated` — เรียกโดย Edge Function ผ่าน service role เท่านั้น):

| function | ผู้เรียก | ทำใน transaction เดียว |
|---|---|---|
| `internal_post_ledger` | ทุก RPC การเงิน | ดู 5.3 |
| `internal_credit_payment(payment_order_id, psp_reference, receipt jsonb?)` | Edge Functions verify ทั้งหมด + admin approve slip | lock order → CAS `→verified→credited` → insert `iap_receipt` (ถ้า IAP) → lock wallet → ledger `credit_purchase` (+bonus) → ตรวจ referral แรก → ledger `referral_bonus` ×2 + CAS `referral_attribution→rewarded` → outbox `payment.credited` (push + coin alert) |
| `internal_fail_payment(payment_order_id, reason)` | Edge Function / admin reject | CAS `→failed` → outbox แจ้ง user |
| `internal_settle_stale_call(call_transaction_id)` | cron | สาย `active` ที่เลยเวลารวม → เรียก logic เดียวกับ `end_call(end_reason='timeout')` |
| `internal_expire_question(question_id)` | cron | `submitted` เลย `expires_at` → CAS →`cancelled_refunded(seer_timeout)` + ledger `refund` + outbox |
| `internal_complete_ai_reading(session_id, content, usage jsonb)` / `internal_fail_ai_reading(session_id, error)` | Edge Function `ai-reading` | insert assistant message → CAS →`completed` (หรือ `failed` + ledger `refund`) → outbox push |
| `internal_finalize_deletion(request_id)` | cron/Edge Function | anonymize + purge ตามส่วนที่ 11 → CAS →`completed` → audit_log |

### 6.2 Edge Functions

| function | trigger | หน้าที่ | เหตุที่ต้องเป็น Edge (ไม่ใช่ RPC) |
|---|---|---|---|
| `payment-webhook` | HTTPS จาก PSP — path ราย PSP `/payment-webhook/{psp_code}` (รวม Apple ASN v2 / Google RTDN) | verify signature ตามสเปกของ PSP นั้น → insert `payment_webhook_event` (PK กัน replay) → map ไป order ด้วย `(psp_code, psp_reference)` → `internal_credit_payment` / `internal_fail_payment` | secret ต่อ PSP + รับ traffic ภายนอก; เพิ่ม PSP ใหม่ = เพิ่ม verifier ใน function เดิม ไม่แตะ schema |
| `verify-apple-iap` | client เรียกหลังซื้อ | ตรวจ JWS กับ App Store Server API → หา/สร้าง order (`apple_iap`) → `internal_credit_payment` | ต้องคุยกับ Apple API ด้วย key ลับ |
| `verify-google-iap` | client เรียกหลังซื้อ + RTDN | ตรวจ purchase token กับ Play Developer API → `internal_credit_payment` → acknowledge/consume แล้วอัปเดต `iap_receipt.consumed_at` | Google service account key |
| `media-token` | client ขอเข้าห้อง call/live | ตรวจเป็น participant ของ call non-terminal (หรือ live room `live` + ไม่โดน `live_ban`) → mint token provider → บันทึกเวลา issue ใน `media_session` → เรียก `start_call` เมื่อเงื่อนไข join ครบ | signing key ของ media provider |
| `ai-reading` | outbox worker (`ai.reading.requested`) | อ่าน session + birth profile → เรียก AI provider → stream ผล → `internal_complete_ai_reading` / `internal_fail_ai_reading` พร้อม usage/cost | API key ของ AI provider + งานยาวเกิน statement timeout |
| `push-sender` | outbox worker (event ที่มี push) | อ่าน `device_token` ของเป้าหมาย → ยิง FCM/APNs → ปิด token ที่ตาย (`is_enabled=false`) → insert `notification_inbox` | FCM server key; fan-out I/O |
| `outbox-dispatcher` | `pg_cron` + `pg_net` ทุก 10s | claim `outbox_event` (`FOR UPDATE SKIP LOCKED`) → route ไป handler (push-sender, ai-reading, media cleanup, ...) → mark published/retry | ศูนย์รวม delivery (ดู 9.1) |
| `daily-horoscope` | `pg_cron` รายวัน 03:00 | generate/ดึงดวงรายวัน 12 ราศี → insert `horoscope_content` → publish → outbox push ผู้เปิดรับ | เรียก AI provider |
| `account-purge` | cron รายชั่วโมง | `account_deletion_request` ที่ถึง `scheduled_purge_at` → `internal_finalize_deletion` + ลบไฟล์ Storage | ต้องลบ object ใน Storage หลาย bucket |

---

## ส่วนที่ 7 — RLS strategy

### 7.1 Helper functions (ทั้งหมด `STABLE`, `SECURITY DEFINER`, `search_path` ล็อก)

| helper | คืนค่า | ใช้ใน policy ของ |
|---|---|---|
| `current_account_role()` | `text` — role จาก `account` ของ `auth.uid()` | policy ที่จำกัดฝั่ง seer/user |
| `is_question_participant(p_question_id uuid)` | `boolean` | `question_message` |
| `is_room_participant(p_room_id uuid)` | `boolean` | `appointment_message` |
| `is_call_participant(p_call_id uuid)` | `boolean` | `call_extension` (read) |
| `is_ai_session_owner(p_session_id uuid)` | `boolean` | `ai_reading_message` |
| `is_approved_seer(p_account_id uuid)` | `boolean` | `profile_photo` public read |
| `get_config(p_key text)` | `jsonb` | ใช้ใน RPC ไม่ใช่ policy |
| `check_rate_limit(p_bucket text, p_limit int, p_window interval)` | `boolean` | เรียกใน RPC |

ข้อบังคับ helper: parameter ต้อง**เทียบกับ column ที่มี index** และ function ห้าม query
ตารางที่ตัวเองถูกใช้เป็น policy (กัน recursion)

### 7.2 ตารางสรุป policy ทุกตาราง

Legend เขียน: `direct` = INSERT/UPDATE ผ่าน RLS ได้ (ระบุเงื่อนไข), `rpc` = ผ่าน RPC เท่านั้น,
`service` = service role เท่านั้น, `—` = ไม่มีใครเขียน (append จาก trigger)

| table | posture | ใครอ่าน | ใครเขียน | เขียนผ่าน |
|---|---|---|---|---|
| `account` | owner-read | เจ้าของ | — | service/trigger |
| `user_profile` | owner-read | เจ้าของ | เจ้าของ | direct (จำกัด column) |
| `profile_photo` | public-read บางส่วน | ทุกคน (approved+seer approved), เจ้าของ (ทั้งหมด) | เจ้าของ | direct (จำกัด column) |
| `seer_profile` | public-read บางส่วน | ทุกคน (approved), เจ้าของ | เจ้าของ | direct (จำกัด column) |
| `device_token` | owner-read | เจ้าของ | เจ้าของ | direct |
| `agreement` | public-read | ทุกคน | admin | service |
| `account_agreement` | owner-read | เจ้าของ | เจ้าของ (insert) | direct |
| `account_deletion_request` | owner-read | เจ้าของ | เจ้าของ | rpc |
| `seer_level`, `skill`, `service_type`, `review_tag`, `gift` | public-read | ทุกคน | admin | service |
| `seer_skill` | public-read | ทุกคน | seer เจ้าของ | direct |
| `seer_service` | public-read | ทุกคน | seer เจ้าของ | direct (จำกัด column) |
| `seer_schedule` | public-read | ทุกคน | seer เจ้าของ | direct |
| `favorite_seer` | owner-read | user เจ้าของ | user เจ้าของ | direct |
| `seer_document` | owner-read | seer เจ้าของ | seer เจ้าของ (insert/soft-del), admin (review) | direct + service |
| `question` | participant-read | คู่สนทนา | — | rpc |
| `question_message` | participant-read | คู่สนทนา | ผู้ส่ง (participant) | direct (insert only, มีเงื่อนไข state) |
| `review` | public-read (`NOT is_hidden`) | ทุกคน | user/seer | rpc |
| `appointment_room` | participant-read | คู่สนทนา | user (insert), participant (cursor) | direct (จำกัด column) |
| `appointment` | participant-read | คู่สนทนา | participant | rpc |
| `appointment_message` | participant-read | คู่สนทนา | ผู้ส่ง | direct (insert only) |
| `call_transaction` | participant-read | คู่สาย | — | rpc |
| `call_extension` | participant-read | คู่สาย | — | rpc |
| `media_session` | deny-all | — | — | service |
| `wallet`, `ledger_transaction`, `ledger_entry`, `idempotency_key` | **deny-all** | ผ่าน view `v_my_*` | — | rpc/internal |
| `coin_package` | public-read (`is_enabled`) | ทุกคน | admin | service |
| `payment_order`, `iap_receipt`, `bank_transfer_proof`, `payment_webhook_event` | **deny-all** | order ผ่าน `v_my_payment_history` | — | rpc/service |
| `voucher`, `voucher_redemption` | deny-all | ผลผ่าน coin history | — | rpc |
| `referral_attribution` | deny-all | ผ่าน `v_my_referral_summary` | — | internal |
| `seer_earning` | owner-read | seer เจ้าของ | — | internal |
| `payout_account` | deny-all | ผ่าน `v_my_payout_account` (last4) | seer | rpc |
| `payout_request` | deny-all | ผ่าน `v_my_payout_history` | seer/admin | rpc/service |
| `birth_profile` | owner-read | เจ้าของ | เจ้าของ | direct |
| `horoscope_content` | public-read (`published`) | ทุกคน | job | service |
| `ai_reading_session` | owner-read | เจ้าของ | — | rpc/service |
| `ai_reading_message` | owner-read (helper) | เจ้าของ session | — | rpc/service |
| `ai_usage_quota` | owner-read | เจ้าของ | — | rpc |
| `live_room` | public-read | ทุกคน | seer เจ้าของ | rpc |
| `gift_transaction` | public-read | ทุกคน | — | rpc |
| `notification_inbox` | owner-read | เจ้าของ | เจ้าของ (`read_at` เท่านั้น) | direct (จำกัด column) |
| `outbox_event`, `app_config`(non-public), `rate_limit_counter`, `moderation_action`, `audit_log` | deny-all | — | — | service/internal |
| `app_config` (`is_public`) | public-read | ทุกคน | admin | service |
| `block_relation` | owner-read (seer) | seer เจ้าของ | seer เจ้าของ | direct |
| `user_report` | owner-read | ผู้ report | ผู้ report (insert) | direct + service |

### 7.3 กับดัก RLS บน Supabase ที่ออกแบบรับไว้แล้ว

1. **`auth.uid()` ถูกเรียกซ้ำต่อแถว** — ทุก policy เขียน `(SELECT auth.uid())` (initplan,
   ประเมินครั้งเดียว) ไม่ใช่ `auth.uid()` เปล่า; กติกานี้บังคับใน migration review
2. **Policy join แพง** — ownership column อยู่ในตารางเองตามกฎ 2.5; helper ที่ join ใช้กับ
   ตารางลูกเท่านั้น และ query ภายใน helper ยิงบน PK/unique index เสมอ
3. **`security_invoker` ของ view** — view `v_my_*` ทั้งหมดตั้ง `security_invoker = false`
   (definer) โดยกรอง `auth.uid()` ภายใน view เอง เพราะตารางฐาน deny-all; ห้ามสร้าง
   definer view ที่ไม่กรอง owner เด็ดขาด — ทุก view ต้องมี `WHERE account_id = (SELECT auth.uid())`
   เป็นบรรทัดแรกของ predicate
4. **Existence leak ผ่าน FK error** — RPC โหลด resource ก่อนแล้วตอบ `not_found` เดียวกัน
   ทั้งกรณีไม่มีจริงและกรณีไม่ใช่เจ้าของ (นโยบายจาก validation policy ที่ reverse ยืนยัน)
5. **Realtime เคารพ RLS** — `postgres_changes` ส่งเฉพาะแถวที่ policy อ่านได้; ตาราง
   deny-all จึงห้ามใช้ postgres_changes กับ client (ใช้ broadcast แทน — ส่วนที่ 8)
6. **Index รองรับ policy** — ทุก column ที่โผล่ใน policy (`user_id`, `seer_id`, `account_id`)
   มี index จาก access pattern หลักอยู่แล้ว; ห้ามสร้าง functional index บน `auth.uid()`
   (เป็น volatile ต่อ session — ใช้ไม่ได้)
7. **`anon` role** — เปิดเฉพาะตาราง public-read ที่ตั้งใจให้คนยังไม่ login เห็น
   (`seer_profile` approved, `skill`, `horoscope_content` published, `app_config` public,
   `agreement`) — ที่เหลือ REVOKE จาก `anon` ทั้ง schema แล้ว grant รายตาราง

---

## ส่วนที่ 8 — Realtime & presence

หลักการ: **ตารางคือ authority, Realtime คือการแจ้งข่าว** — client ที่ reconnect ต้อง
reconcile ด้วยการอ่านตาราง/REST เสมอ (ตรงกับ invariant ที่สรุปจาก reverse: signaling
ห้ามเป็น source of truth ของ accounting)

### 8.1 Mapping จากโปรโตคอล Socket.IO เดิม → Supabase Realtime

| ความสามารถเดิม (สังเกตจาก client) | กลไกใน Chata | channel | เหตุผล |
|---|---|---|---|
| แชทในคำถาม (ข้อความใหม่) | **postgres_changes** บน `question_message` filter `question_id=eq.{id}` | `question:{id}` | ข้อความ persist อยู่แล้ว; RLS กรองผู้รับให้ฟรี |
| สถานะคำถาม (ปิด/คืนเงิน) | postgres_changes บน `question` (UPDATE) | `question:{id}` | state อยู่ในแถวเดียว |
| แชทห้องนัดหมาย | postgres_changes บน `appointment_message` + `appointment` | `appointment_room:{id}` | เหมือน question |
| call signaling (request/accept/reject/start) | **broadcast** event (`call.offered`, `call.accepted`, `call.started`, `call.ended`) ยิงจาก RPC ผ่าน `realtime.send()` ใน transaction + postgres_changes บน `call_transaction` เป็น fallback sync | `call:{id}` (private channel) | latency ต่ำกว่า WAL polling; แต่ state จริงอ่านจากตารางเสมอเมื่อ reconnect |
| เสียงเรียกเข้าฝั่ง seer | broadcast บน channel ส่วนตัว `inbox:{seer_id}` + push (FCM/APNs) สำหรับตอน app ปิด | `inbox:{account_id}` | seer ต้องได้ยินโดยไม่ subscribe ทุก call id |
| presence หมอดูออนไลน์ | **Presence** — seer join channel `presence:seers` เมื่อเปิดรับงาน; client หน้า discovery subscribe อ่าน state | `presence:seers` | แทน Redis presence เดิม; ไม่เขียน DB (จุดต่างจากเดิม: `is_active` คือ "เปิดรับงาน" ตั้งใจ, presence คือ "ต่อเน็ตอยู่" — สองแกนแยกกันตามบทเรียน reverse) |
| viewer count ในไลฟ์ | Presence บน `live:{room_id}` + Edge Function sample เป็นช่วง ๆ ลง `peak_viewer_count` | `live:{room_id}` | นับสดไม่ผ่าน DB |
| แชทในไลฟ์ | **broadcast เท่านั้น** (ephemeral — ไม่ persist ตามข้อตัดสินใจ 4.11) | `live:{room_id}` | ประหยัด DB/WAL ที่สุด |
| gift ในไลฟ์ | RPC `send_gift` → broadcast `gift.sent` จาก transaction + แถว `gift_transaction` | `live:{room_id}` | เงินอยู่ในตาราง, animation อยู่บน broadcast |
| แจ้งเตือน in-app (กระดิ่ง/badge) | postgres_changes บน `notification_inbox` filter `account_id=eq.{uid}` | `inbox:{account_id}` | |

### 8.2 ตารางที่ต้องเปิด replication (`supabase_realtime` publication)

`question`, `question_message`, `appointment`, `appointment_room`, `appointment_message`,
`call_transaction`, `notification_inbox` — **เท่านั้น** ตารางอื่นไม่เข้า publication
(ยิ่งเปิดมาก WAL fan-out ยิ่งแพงบน free tier); ตาราง deny-all ห้ามเข้า publication เด็ดขาด

### 8.3 Channel authorization

ทุก channel เป็น **private channel** (Realtime authorization): policy บน
`realtime.messages` — `question:{id}`/`appointment_room:{id}`/`call:{id}` ตรวจ participant
ด้วย helper เดียวกับ RLS; `inbox:{account_id}` ตรวจ `account_id = auth.uid()`;
`presence:seers` และ `live:{room_id}` เปิด subscribe แบบ authenticated ทุกคน แต่ **publish
broadcast ได้เฉพาะ**: live chat = ทุก authenticated (ephemeral, ตรวจ `live_ban` ที่ policy),
ส่วน event เงิน/สถานะ (gift, call.*) publish จากฝั่ง server เท่านั้น (RPC / service role)

### 8.4 Call state machine กับ realtime

การเดิน state ทั้งหมดเกิดใน RPC (ตาราง = authority); broadcast เป็น projection ของ
transition ที่ commit แล้วเท่านั้น (ยิงหลัง commit ผ่าน outbox หรือ `realtime.send` ใน
transaction — เลือก `realtime.send` เพราะ latency; ถ้า broadcast หลุด client จะ resync
จาก `call_transaction` ตอน subscribe/reconnect ด้วย `SELECT` ตรง)
Timeout ทุกชนิด (seer ไม่รับใน TTL, สาย active เลยเวลา) ตัดสินโดย **cron ฝั่ง server**
ไม่ใช่ timer ฝั่ง client (client timer เป็นแค่ UI countdown)

---

## ส่วนที่ 9 — Outbox, cron & background jobs

### 9.1 Delivery pipeline

1. RPC/trigger insert `outbox_event` ใน transaction เดียวกับ domain change (atomicity)
2. `pg_cron` ทุก 10 วินาที เรียก `outbox-dispatcher` ผ่าน `pg_net` (`net.http_post` ไป
   Edge Function พร้อม service key จาก Vault)
3. dispatcher claim batch: `UPDATE outbox_event SET status='processing' WHERE id IN
   (SELECT id FROM outbox_event WHERE status='pending' AND next_attempt_at <= now()
   ORDER BY id LIMIT 50 FOR UPDATE SKIP LOCKED) RETURNING *`
4. route ตาม `event_type` → handler (push, AI, media cleanup, admin notify)
5. สำเร็จ → `published` + `published_at`; ล้มเหลว → `attempts+1`,
   `next_attempt_at = now() + (2^attempts) * interval '10 seconds'` (10s→20s→40s→…~21m), status กลับ `pending`
6. `attempts >= 8` → `dead` — มี cron แจ้ง admin เมื่อ dead > 0 และหน้า ops replay ได้
   (reset เป็น `pending`)

Consumer ทุกตัว **idempotent ต่อ `outbox_event.id` + handler name** (เช่น push-sender กันส่งซ้ำ
ด้วย dedupe key ใน notification insert: unique partial ตาม `payload->>'outbox_id'`)

### 9.2 Cron schedule (pg_cron)

| job | ความถี่ | ทำอะไร |
|---|---|---|
| `dispatch_outbox` | 10s | ตาม 9.1 |
| `expire_questions` | 1 นาที | `question` `submitted` ที่เลย `expires_at` → `internal_expire_question` (refund) |
| `auto_close_questions` | 5 นาที | `active` เกินอายุ max (config) → policy: แจ้งเตือนก่อน 24h แล้ว settle อัตโนมัติ (`respond_close_question` โดย system) |
| `release_call_reservations` | 30s | `reserved/offered` เลย `reservation_expires_at` → refund + `expired` |
| `settle_stale_calls` | 1 นาที | `active` เกิน `total_duration + grace` → `internal_settle_stale_call` |
| `reconcile_payments` | 15 นาที | order `pending_provider` ค้างนาน → query สถานะกับ PSP (ผ่าน Edge) / เลย `expires_at` → `expired` |
| `reconcile_wallets` | รายวัน 04:00 | เทียบ `wallet` กับ `SUM(ledger_entry)` ทุกบัญชี + invariant 5.1 — ผิด = alert + หยุด approve payout |
| `close_stale_lives` | 5 นาที | `live_room` `live` เกิน max duration → `end_live` โดย system |
| `expire_ai_sessions` | 5 นาที | `created/generating` ค้างเกิน 10 นาที → `internal_fail_ai_reading` (คืน coin) |
| `send_appointment_reminders` | 5 นาที | `appointment` accepted ที่ใกล้ถึงเวลา (30 นาที) → outbox push (กันซ้ำด้วย dedupe key) |
| `publish_daily_horoscope` | รายวัน 03:00 | เรียก Edge `daily-horoscope` |
| `purge_expired_rows` | รายชั่วโมง | `idempotency_key` เลย expiry, `rate_limit_counter` เก่า, `notification_inbox` ตาม retention, `ai_usage_quota` > 90 วัน |
| `purge_deleted_accounts` | รายชั่วโมง | เรียก Edge `account-purge` |
| `rollup_seer_income` | รายวัน 04:30 | สรุปรายได้รายวันต่อ seer ลง materialized view `mv_seer_income_daily` (refresh concurrently) สำหรับหน้า income summary |

กติกา job ทุกตัว: **re-check state จริงก่อน act** (แถวอาจเปลี่ยนไปแล้วระหว่างรอ),
ทำงานเป็น batch จำกัดขนาด, และ idempotent (เรียกซ้ำไม่เกิดผลซ้ำ — อาศัย CAS + ledger unique)

### 9.3 Dead-letter & observability

- `outbox_event` status `dead` คือ dead-letter ในตัว (ไม่มีตารางแยก — replay ง่ายกว่า)
- ทุก job เขียนแถว `audit_log` (`system` actor) เมื่อทำ action ที่มีผลเงิน (expire/settle)
- Metric ขั้นต่ำที่ ops ต้องดู: outbox backlog (`pending` count + อายุแถวแรก), dead count,
  wallet reconcile diff, cron job ล้มเหลว (ดูจาก `cron.job_run_details`)

---

## ส่วนที่ 10 — Index & performance plan

### 10.1 Index สำคัญรวมทุกตาราง (นอกเหนือ PK/unique ที่ระบุในส่วนที่ 4)

| index | ชนิด | รองรับ query |
|---|---|---|
| `question(user_id, created_at DESC)` | btree | ประวัติคำถามของ user (หน้า history, keyset ด้วย created_at+id) |
| `question(seer_id, status, created_at DESC)` | btree composite | task list ของ seer แยกแท็บตาม status — เรียง column ตาม equality→equality→sort |
| `question(expires_at) WHERE status IN ('submitted','active')` | partial | cron expiry — scan เฉพาะงานเป็น ๆ ซึ่งเป็นส่วนน้อยของตาราง |
| `question_message(question_id, id)` | btree composite | เปิดห้อง + โหลดเพิ่มจาก cursor (`WHERE question_id=$1 AND id > $2 ORDER BY id LIMIT n`) — index เดียวครอบทุก query ของตาราง |
| `appointment_room(user_id, last_message_at DESC)` / `(seer_id, last_message_at DESC)` | btree | inbox สองฝั่ง |
| `appointment(room_id, created_at DESC)` | btree | ประวัติการนัดในห้อง |
| `appointment(scheduled_at) WHERE status='accepted'` | partial | cron reminder |
| `appointment_message(room_id, id)` | btree | cursor เหมือน question_message |
| `call_transaction(user_id, created_at DESC)` / `(seer_id, status, created_at DESC)` | btree | ประวัติ + งานค้างฝั่ง seer |
| `call_transaction(reservation_expires_at) WHERE status IN ('reserved','offered')` | partial | cron release |
| `call_transaction(status) WHERE status='active'` | partial | cron settle — แถว active มีหลักสิบ ไม่ใช่หลักล้าน |
| `ledger_entry(account_id, id DESC) WHERE account_id IS NOT NULL` | partial composite | coin history ต่อบัญชี (keyset) |
| `ledger_entry(transaction_id)` | btree | ประกอบ transaction + reconcile |
| `payment_order(user_id, created_at DESC)` | btree | ประวัติเติมเงิน |
| `payment_order(status, expires_at) WHERE status IN ('created','pending_provider')` | partial | cron reconcile/expire |
| `payment_order(psp_code, status, created_at DESC)` | btree composite | reconcile/รายงาน/สลับ traffic ราย PSP |
| `iap_receipt(provider, purchase_token_hash)` | unique | replay guard — จุดชนที่ตั้งใจให้ชน |
| `bank_transfer_proof(review_status) WHERE review_status='pending'` | partial | คิว admin |
| `seer_earning(seer_id, created_at DESC)` | btree | income history + summary ช่วงเวลา (range scan) |
| `payout_request(status) WHERE status IN ('requested','approved')` | partial | คิว admin |
| `notification_inbox(account_id, id DESC)` | btree | กระดิ่ง (keyset) |
| `notification_inbox(account_id) WHERE read_at IS NULL` | partial | badge count — count บน index-only |
| `outbox_event(next_attempt_at) WHERE status IN ('pending','processing')` | partial | dispatcher claim — heap ส่วน published ไม่ถูกแตะ |
| `gift_transaction(live_room_id, id)` | btree | gift feed ในห้อง |
| `gift_transaction(seer_id, created_at DESC)` | btree | รายได้ gift ของ seer |
| `review(seer_id, created_at DESC) WHERE NOT is_hidden` | partial | หน้ารีวิว seer |
| `review USING gin(tag_ids)` | GIN | นับ tag summary ต่อ seer |
| `seer_profile(approval_status, is_active)` | btree | discovery หน้าแรก |
| `seer_skill(skill_id)` | btree | filter ตามศาสตร์ |
| `live_room(status, started_at DESC) WHERE status='live'` | partial | หน้ารวมไลฟ์ |
| `ai_reading_session(account_id, created_at DESC)` | btree | ประวัติ AI |
| `rate_limit_counter(window_start)` | btree | purge |
| `block_relation(user_id)` | btree | ตรวจ block ตอนซื้อ |
| `favorite_seer(seer_id) WHERE notify_online` | partial | fan-out push ตอน seer ออนไลน์ |
| `audit_log(target_type, target_id, created_at DESC)` | btree | สืบเหตุการณ์ต่อ object |

หลักการ: ทุก index ต้องชี้ query ที่มีจริงในเอกสารนี้ได้; ไม่สร้าง index เผื่อ
(free tier 500MB — index กินพื้นที่เท่า data ได้ง่าย ๆ); ตรวจ `pg_stat_user_indexes`
รายเดือน index ที่ scan = 0 ให้ตัดออก

### 10.2 Query pattern หลักที่ระบบต้อง serve เร็ว

1. Discovery: seer approved+active เรียงตาม rating/ล่าสุด + filter skill → index 10.1 + Presence (ไม่แตะ DB)
2. เปิดห้องแชท: `question_message` cursor — index-only-ish scan สั้น
3. Balance: `v_my_wallet` = PK lookup แถวเดียว
4. Coin history: keyset บน `ledger_entry(account_id, id DESC)`
5. Seer task list: `question(seer_id, status, created_at DESC)`
6. Badge: partial index count
7. Income summary ช่วงเวลา: `seer_earning(seer_id, created_at)` range + `mv_seer_income_daily`

### 10.3 Partition strategy

ตัดสินใจ: **v1 ยังไม่ partition ตารางใด** แต่เตรียมทางไว้ให้ partition ได้โดยไม่แตก contract:

- ตารางโตเร็ว: `question_message`, `ledger_entry`, `gift_transaction`, `notification_inbox`,
  `outbox_event`, `audit_log`
- เหตุผลที่ยังไม่ทำ: (ก) declarative partition บังคับให้ partition key อยู่ในทุก PK/unique —
  จะทำลาย unique ที่เป็น idempotency guard (`(question_id, client_message_id)`,
  `(sender_id, client_gift_id)`) หรือบังคับ composite ที่ client ต้องรู้;
  (ข) ที่ scale ก่อน 10M แถว btree ธรรมดา + keyset pagination เพียงพอ;
  (ค) free tier ตายด้วย disk 500MB ก่อนจะตายด้วย index depth — ทางแก้คือ retention ไม่ใช่ partition
- การเตรียมทาง: ทุกตารางกลุ่มนี้ access ผ่าน `(parent_id, id)` หรือ `(account_id, id)` เท่านั้น
  (ไม่มี global scan ใน hot path) → เมื่อย้าย tier แล้วค่อย partition แบบ **RANGE บน `id`**
  (หรือ `created_at` รายเดือนสำหรับ `audit_log`/`outbox_event` ที่ unique ไม่ผูก business key)
  ด้วย pattern สร้างตารางใหม่ + backfill + swap ใน maintenance window
- Retention แทน partition ใน v1: `outbox_event` published > 14 วัน ลบ, `notification_inbox`
  ตาม 4.12.1, `rate_limit_counter` > 1 วัน, `audit_log` > 1 ปี export ออก Storage แล้วลบ

### 10.4 กฎ pagination

ทุก list API ใช้ **keyset** (`id <`/`>` cursor หรือ `(created_at, id)`) — ห้าม OFFSET;
สอดคล้อง pattern `min_message_id`/`loaded_ids` ที่สังเกตจาก client contract เดิม
แต่เราทำให้เป็น cursor เดียวสะอาด ๆ แทน list ของ id

---

## ส่วนที่ 11 — Data lifecycle & compliance (PDPA)

### 11.1 การจัดชั้นข้อมูล

| ชั้น | ตัวอย่าง | มาตรการ |
|---|---|---|
| ความลับระบบ | PSP/Apple/Google/AI/media keys | อยู่ใน Supabase Vault / Edge Function secrets เท่านั้น — **ไม่มีในตาราง** |
| PII ตรง | เบอร์โทร (`account.phone_e164`), ชื่อบัญชีธนาคาร, เลขบัญชี, เอกสาร KYC, สลิป | เลขบัญชี encrypt (`pgsodium` ผ่าน Vault key) เก็บ last4 แยก; ไฟล์อยู่ private bucket + signed URL อายุ ≤ 5 นาที ออกผ่าน service role; ห้ามลง log/outbox/audit detail |
| PII อ่อนไหวเชิงบริบท | `birth_profile` (วันเวลาเกิด), เนื้อหาแชท, AI reading | RLS owner/participant เท่านั้น; ไม่เข้า analytics; redact ใน audit |
| ข้อมูล pseudonymous | ledger, earning, review | ผูก uuid — เมื่อลบบัญชีจะ anonymize เจ้าของแทนการลบแถว (ภาระทางบัญชี/ภาษีต้องเก็บ) |
| สาธารณะ | seer catalog, horoscope content | public-read |

### 11.2 สิ่งที่ hash / ไม่เก็บ plaintext

- voucher code → `code_hash` (SHA-256 upper-case) + `code_hint`
- IAP purchase token / JWS → `purchase_token_hash` (raw payload ที่ decode แล้วเก็บใน
  `iap_receipt.raw_payload` ซึ่งเป็นข้อมูล receipt ไม่ใช่ credential)
- ไฟล์ทุกไฟล์ → `content_hash` สำหรับ dedupe
- push `device_token.token`: เก็บ plaintext (จำเป็นต่อการยิง push) แต่ posture owner-only
  + ไม่เข้า log — ยอมรับเป็น trade-off มาตรฐานของ push infrastructure
- ไม่เก็บ: รหัสผ่าน (Supabase auth ถือ), OTP (Supabase ถือ), เลขบัตรเครดิต (PSP ถือ —
  เราเก็บแค่ provider reference)

### 11.3 Retention

| ข้อมูล | เก็บนาน | แล้วทำอะไร |
|---|---|---|
| แชท (`question_message`, `appointment_message`) | 2 ปีหลังงานปิด | ลบ (cron รายเดือน) — แจ้งใน privacy policy |
| ledger / payment / payout / iap_receipt | 10 ปี | ภาระบัญชี-ภาษี (พ.ร.บ.การบัญชี) — ไม่ลบ, anonymize เจ้าของได้ |
| `audit_log` | 1 ปีใน DB | export NDJSON ไป Storage แล้วลบแถว |
| `notification_inbox` | 90/180 วัน | ลบ |
| `outbox_event` published | 14 วัน | ลบ |
| media ในแชท (Storage) | อายุเท่าข้อความ | ลบพร้อมข้อความ |
| เอกสาร KYC | ตลอดสถานะ seer + 1 ปีหลังปิดบัญชี | ลบไฟล์ |

### 11.4 การลบบัญชี (สิทธิ PDPA)

Flow `request_account_deletion` (grace 7 วัน) → `internal_finalize_deletion`:

1. `auth.users` → ปิด identity (ลบ provider identities + ban) — ทำผ่าน Admin API ใน Edge
2. `account`: `status='deleted'`, `phone_e164=NULL`, `referral_code=NULL`
3. `user_profile`/`seer_profile`: display_name → `"ผู้ใช้ที่ลบแล้ว"`, ล้าง avatar/bio/birthdate/gender
4. ลบแถว: `device_token`, `birth_profile`, `favorite_seer`, `ai_reading_message`,
   `seer_schedule`; ลบไฟล์: profile photos, KYC docs (ตาม retention), แชท media คงตาม
   retention แชทเพราะเป็นข้อมูลของคู่สนทนาด้วย
5. คงแบบ anonymized: ledger, payment/payout history, review (แสดง "ผู้ใช้ที่ลบแล้ว"),
   question/message text คงจน retention ปกติ (คู่กรณีมีสิทธิในบทสนทนา) — ระบุใน privacy policy
6. `audit_log` บันทึกการ purge (ไม่มี PII ใน detail)

เงื่อนไขก่อนรับคำขอ: ไม่มี coin ค้างจำนวนมีนัย (< เกณฑ์ config), ไม่มี escrow ค้าง,
seer ต้องไม่มี payable/payout ค้าง — แจ้งให้ถอน/ใช้ให้จบก่อน

### 11.5 การเข้ารหัสและขอบเขต

- At-rest: Supabase เข้ารหัส disk ให้ทั้งโปรเจกต์อยู่แล้ว; ชั้น application-level เพิ่มเฉพาะ
  `payout_account.account_number_encrypted` (pgsodium, key ใน Vault — ไม่อยู่ใน DB dump)
- In-transit: TLS ทุกทาง (PostgREST/Realtime/Storage/Edge)
- Logs: Edge Function ห้าม log token/PII (มี lint checklist); Postgres `log_statement`
  ปิดสำหรับ RPC ที่รับ PII (ใช้ `SET LOCAL log_statement = 'none'` ใน function ที่จำเป็น)

---

## ส่วนที่ 12 — Cross-platform contract (iOS ก่อน, Android ตาม)

### 12.1 ผลของ IAP สองเจ้า (สรุปสิ่งที่ schema รองรับแล้ว)

- `payment_order.method` ครอบ 8 วิธีจ่าย และ `psp_code` แยกผู้เคลียร์เงินออกจากวิธีจ่าย
  (IAP: method `apple_iap`/`google_play` คู่กับ psp `apple`/`google` ตายตัว);
  `coin_package` แยก `apple_product_id` / `google_product_id` คนละ column
  (price tier คนละชุด — brief §6)
- `iap_receipt` เก็บได้ทั้งสอง format: Apple (`provider_transaction_id` =
  `original_transaction_id`, hash ของ JWS) และ Google (`order_id`, hash ของ `purchase_token`)
  โดย unique ที่ `(provider, purchase_token_hash)` ใช้ตรรกะเดียวกันทั้งคู่
- Flow ต่างกันแต่บรรจบที่จุดเดียว: ทั้ง `verify-apple-iap` และ `verify-google-iap` จบด้วย
  `internal_credit_payment` — ledger ไม่รู้จักคำว่า platform
- Refund/chargeback: Apple App Store Server Notifications v2 (psp_code `apple`) และ
  Google RTDN (psp_code `google`) เข้าตาราง `payment_webhook_event` เดียวกันกับ PSP อื่น
  → reversing entry เดียวกัน

### 12.2 Push & deep link

- `device_token` ผูก `platform` + `provider`; ยิงผ่าน FCM ได้ทั้งสอง platform, ช่อง `apns`
  เผื่อยิงตรง — push-sender เลือก endpoint จาก `provider`
- Deep link ใน `notification_inbox.deep_link` เป็น scheme กลาง `chata://<entity>/<uuid>`
  — client แต่ละ platform map เป็น route ตัวเอง; **id ใน deep link เป็น uuid เสมอ**
  และ server ตรวจสิทธิ์ตอนเปิดหน้า (บทเรียนจาก reverse: deep link เดิม crash กับ id
  ที่ parse ไม่ได้และเชื่อ id ฝั่ง client — เราบังคับ parse-safe + authorize ฝั่ง server)

### 12.3 Versioning ของ contract

- Client ส่ง header `x-app-version` + `x-platform` ทุก request (Edge/PostgREST pre-request
  hook อ่านได้) — เก็บเป็น context ใน `audit_log.detail` เมื่อจำเป็น
- `app_config` key `client.min_supported_version.{ios,android}` → client เช็คตอน bootstrap
  แล้วบังคับอัปเดต; ตัด breaking change ของ RPC ด้วยการ**เพิ่ม function ใหม่**
  (`submit_question_v2`) ไม่แก้ signature เดิมจนกว่า min version จะพ้น
- Enum/status ใหม่: client ต้อง tolerant ต่อค่าที่ไม่รู้จัก (แสดง fallback) — ระบุใน
  client contract doc; ฝั่ง DB เพิ่มค่าใน CHECK ได้โดยไม่ break

### 12.4 กฎ "ห้ามมี state ฝั่ง client"

- ทุก state ที่มีผลเงิน/สิทธิ์อยู่ในตาราง; client cache เป็นแค่ read model — เปิด app
  ต้อง reconcile จาก server เสมอ (สอดคล้อง reverse ที่พบว่า client เดิมเก็บ credential/
  state ใน Room DB แล้วเกิดช่องโหว่ — เราไม่ให้มีอะไรน่าขโมยฝั่ง client)
- Timer ทั้งหมด (หมดเวลาตอบ, หมดเวลาสาย, countdown) มีคู่จริงเป็น `expires_at`/cron
  ฝั่ง server; client render จากค่า server เท่านั้น
- Idempotency key สร้างฝั่ง client ต่อ intent (uuid) — นี่คือ state ฝั่ง client
  ชนิดเดียวที่ยอมให้มี และมันหายได้โดยไม่เสียความถูกต้อง (แค่ retry ภายใต้ key ใหม่
  จะเจอ guard ชั้นบัญชีอยู่ดี)

---

## ส่วนที่ 13 — Supabase free-tier reality check

ตัวเลขเพดาน free tier (ณ ปัจจุบัน — ตรวจซ้ำก่อน launch):
DB 500MB / egress รวม ~5GB/เดือน / Realtime 200 concurrent connections, 2M messages/เดือน /
Edge Functions 500K invocations/เดือน / Storage 1GB / โปรเจกต์ pause เมื่อ idle 7 วัน

| ความเสี่ยง | domain ที่ชนก่อน | การออกแบบที่รับไว้แล้ว | migration path ตอนโต |
|---|---|---|---|
| Realtime concurrent 200 | **live stream** (คนดูพร้อมกัน = connection ตรง ๆ) | live เป็น feature flag ปิดได้ทั้ง domain; แชทไลฟ์เป็น broadcast (ไม่กิน WAL); จำกัดจำนวนห้อง live พร้อมกันผ่าน config | Pro tier (500) → ถัดไปย้าย live chat ไป service แยก (Centrifugo/LiveKit data channel) โดย schema ไม่เปลี่ยนเพราะ DB เก็บแค่เงิน+metadata อยู่แล้ว |
| Realtime 2M msg/เดือน | live chat, call signaling | นับเฉพาะ channel ที่จำเป็น; discovery ใช้ Presence เดียวรวม ไม่ per-seer | เท่าเดิม |
| Edge invocations 500K | `outbox-dispatcher` ทุก 10s = ~260K/เดือน ก็กินครึ่งแล้ว | dispatcher batch 50 event/ครั้ง; ปรับ interval ได้ทาง config; push รวมเป็น batch ต่อ invocation | Pro (2M) หรือย้าย dispatcher ไป worker นอก (fly.io ฯลฯ) — สัญญา DB ไม่เปลี่ยน (ตาราง outbox คือ contract) |
| DB 500MB | `question_message`, `ledger_entry`, `outbox_event` | retention 10.3/11.3; media อยู่ Storage ไม่อยู่ตาราง; ไม่เก็บ live chat | Pro (8GB) แล้วค่อยว่าด้วย partition (10.3) |
| Egress 5GB | รูปในแชท/โปรไฟล์ผ่าน Storage | client cache รูป + `transform` ย่อรูป; signed URL อายุสั้นแต่ cacheable ต่อ client | Storage CDN บน Pro |
| Project pause 7 วัน idle | ทั้งระบบช่วง pre-launch | `pg_cron` ยังนับเป็น activity — ตั้ง healthcheck ping | อัปเกรดก่อน launch จริงอยู่ดี |

ข้อสรุปเชิงนโยบาย: **free tier ใช้สำหรับ dev/alpha เท่านั้น** — launch จริงต้อง Pro
($25/เดือน) เป็นอย่างน้อย; การออกแบบทั้งหมดข้างบนทำให้ *ไม่มีการตัดสินใจ schema
ที่ต้องรื้อ* ตอนอัปเกรด มีแต่เปิด flag เพิ่มและขยับ config

---

## ส่วนที่ 14 — Open questions & risks (ให้ user เคาะ)

1. **Media provider (call + live)** — schema เผื่อไว้แล้ว (`media_session.provider`,
   `live_room.provider`) แต่ต้องเคาะเพื่อเขียน Edge `media-token` จริง
   ข้อเสนอ: **LiveKit Cloud** (free tier ใจดี, token model ง่าย, ทำได้ทั้ง call และ live)
2. **AI provider + ราคา AI reading** — เสนอ Anthropic API (Haiku สำหรับดวงรายวัน batch,
   Sonnet สำหรับ AI reading ส่วนตัว); ต้องเคาะ: ราคา coin ต่อ reading, ฟรีโควตา/วัน
   (`ai.free_quota_per_day`), เพดาน cost ต่อเดือนที่ยอมรับ
3. **อัตราแปลง coin → THB ตอน payout + ค่าธรรมเนียม + หัก ณ ที่จ่าย** — schema รับแล้ว
   (`conversion_rate_micro`, `fee_minor`, `withholding_tax_minor`) แต่ตัวเลขเป็น business
   decision; แนะนำปรึกษาบัญชีเรื่อง 40(2) vs 40(8) และ VAT ของแพลตฟอร์ม
4. **ระดับ KYC ของ seer** — v1 ออกแบบเป็น manual review เอกสาร (บัตร ปชช. + หน้าบัญชี);
   ถ้าเงินหมุนโตต้องประเมินภาระตามกฎหมาย e-payment/ปปง. อีกครั้ง
5. **Commission structure** — `seer_level.revenue_share_bps` รองรับหลายระดับ; ต้องเคาะ
   ตัวเลขจริงและเงื่อนไขเลื่อนระดับ (ตอนนี้เลื่อนโดย admin เท่านั้น)
6. **นโยบาย auto-close คำถาม active** — เอกสารนี้เลือก "แจ้งเตือน 24 ชม. แล้ว settle
   ให้ seer" (คุ้มครองฝั่ง seer ที่ตอบแล้ว) — กลับด้านเป็น refund ได้ถ้า product เห็นต่าง
   ต้องเคาะพร้อมระยะเวลา (`question.reply_deadline_hours`, max active age)
7. **Trial (ดูดวงฟรีครั้งแรก)** — schema มี `trial_quota_per_user` + `is_trial` แล้ว
   แต่เงื่อนไขเปิดใช้ (seer สมัครใจ? แพลตฟอร์ม subsidize?) ยังไม่เคาะ
8. **PSP เจ้าแรกตอน launch** — schema/matrix รองรับหลาย PSP แล้ว แต่ต้องเคาะว่าเริ่มด้วย
   เจ้าไหน (มีผลต่อ verifier ตัวแรกใน Edge `payment-webhook` และค่า
   `payment.method_psp_matrix` เริ่มต้น) — ตัวเลือกที่ตลาดไทยใช้จริง: Omise, ChillPay, GB Prime Pay, 2C2P
9. **สลิปโอนเงิน: OCR/automation** — v1 เป็น manual admin review; ถ้า volume โตค่อยต่อ
   slip-verification API (มี `content_hash` กันสลิปซ้ำรออยู่แล้ว)
10. **Admin console** — เอกสารนี้สมมติ service role ผ่าน backend/console แยก (ไม่มี RLS
   admin) — ต้องเคาะว่าจะสร้าง admin app เมื่อไหร่ ก่อนหน้านั้นใช้ Supabase Studio + SQL
   ที่มี audit_log ครอบ
11. **ความเสี่ยงที่ต้องเฝ้า**: (ก) pg_cron 10s ละเอียดสุดที่ 1 นาทีบนบางเวอร์ชัน —
    ถ้าใช้ 10s ไม่ได้ต้องใช้ 1m + loop ภายใน Edge; (ข) Realtime authorization
    (private channel) ยังเป็นฟีเจอร์ที่ API ขยับบ่อย — ตรึงเวอร์ชัน SDK ตอน implement;
    (ค) `realtime.send()` ใน transaction คือ at-most-once — ระบบนี้ถือว่า broadcast
    หายได้เสมอและ reconcile จากตาราง จึงปลอดภัยโดยดีไซน์

---

*จบเอกสาร — derive ต่อ: `db/chata.dbml` และ `docs/specs/chata-erd.md` (เฟสถัดไป)*
