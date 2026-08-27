# Chata — Design Brief (settled decisions)

> อ่านไฟล์นี้ก่อนเสมอ เป็น source of truth ของการตัดสินใจที่ user เคาะแล้ว
> ห้ามเปลี่ยนข้อตัดสินใจในนี้เอง ถ้าเจอปัญหาให้ระบุเป็น open question ท้ายเอกสาร

## 1. โปรดักต์

Chata = แอปดูดวง (astrology / fortune-telling consultation marketplace) สำหรับตลาดไทย
สร้างใหม่ทั้งหมด (clean-room) โดยอ้างอิง **โครงระบบ** ที่ reverse มาจาก DuangLive 1.5.35
เพื่อให้ได้ระบบบัญชี/ธุรกรรม/สถานะที่แน่นหนา — **ไม่ใช่การ copy โค้ดหรือ schema จริงของ DuangLive**

Business model: ผู้ใช้เติม **coin** → จ่ายค่าปรึกษาหมอดู (seer) ผ่านคำถาม/แชท/โทร
แพลตฟอร์มหักส่วนแบ่ง → seer ได้ยอดค้างจ่ายและถอนได้

## 2. Platform (เคาะแล้ว)

- **Supabase (cloud, เริ่มจาก free tier)** — Postgres + Auth + Realtime + Storage + Edge Functions
- เหตุผล: กำลังปั้น startup ต้องการต้นทุนต่ำและ ship เร็ว
- **Client: iOS (Swift) ก่อน → Android ตามทีหลัง ใช้ database และ contract ตัวเดียวกัน**
- ⚠️ ห้ามออกแบบอะไรที่ผูกกับ platform ใด platform หนึ่ง state ทุกอย่างอยู่ฝั่ง server

## 3. Scope v1 (เคาะแล้ว: full parity + 2 domain ใหม่)

ยกมาทั้งระบบจาก reverse target แล้วเพิ่มของใหม่:

**Parity domains (จาก DuangLive reverse):**
identity/auth/OTP/session · seer catalog (skill, service, price, schedule) ·
question + chat message · appointment · voice/video call + call extension ·
coin wallet + double-entry ledger · payment (Apple IAP, Google Play, โอนเงิน/สลิป, PromptPay/บัตร) ·
voucher · referral · seer income + payout · review/rating · block · notification + outbox · moderation

**Domain ใหม่ที่ไม่มีใน DuangLive:**
1. **Horoscope / AI ดูดวง** — ดวงรายวัน, ดวงตามราศี/วันเกิด, AI reading (ต้องมี birth-chart data, content table, AI session + quota, cost tracking)
2. **Live stream / ห้องดูดวงสด + gift** — ห้องดูฟรีเพื่อทำ campaign, ของขวัญ/gift ระหว่างไลฟ์
   - ⚠️ ออกแบบให้เป็น **domain ที่ตัดออกได้ด้วย feature flag** เพราะ Supabase free tier มีเพดาน realtime/egress
     และวิดีโอสตรีมต้องพึ่ง provider ภายนอก (LiveKit / Agora / Mux) — DB เก็บแค่ metadata

ประมาณการ **48–52 ตาราง**

## 4. สถาปัตยกรรม: Hybrid boundary (แนวทาง C — เคาะแล้ว)

เส้นแบ่งคือคำถามเดียว: **operation นี้แตะเงินหรือ state ที่มีผลทางบัญชีไหม**

| เส้นทาง | กลไก | ตัวอย่าง |
|---|---|---|
| อ่าน | RLS ตรงจาก client | seer catalog, chat history, ดวงรายวัน, notification |
| Realtime | Supabase Realtime + Presence | chat, call signaling, live viewer count |
| เขียนที่ไม่แตะเงิน | RLS + CHECK constraint | แก้โปรไฟล์, favorite, mark-as-read |
| **เขียนที่แตะเงิน/state** | **RPC `SECURITY DEFINER`** (RLS ตารางนั้น deny-all) | ซื้อคำถาม, charge call, extend call, redeem voucher, ส่ง gift, tip |
| External / secret | **Edge Function** | payment webhook, Apple/Google receipt verify, LiveKit token mint, AI provider call |

**กฎเหล็ก:**
- ตาราง money (`wallet`, `ledger_entry`, `payment_order`, `payout`) ตั้ง RLS **deny-all** ทั้งหมด
  client อ่านได้ผ่าน **view / RPC เท่านั้น** และห้ามเขียนตรงเด็ดขาด
- ราคามาจาก `seer_service` ฝั่ง server เสมอ ไม่เชื่อราคาที่ client ส่งมา
- ทุก RPC ที่แตะเงินต้องรับ **idempotency key** และมี unique constraint กันเรียกซ้ำ
- ledger เป็น **append-only double-entry** ห้าม UPDATE/DELETE แถวที่ post แล้ว แก้ด้วย reversing entry
- เก็บเป็น **integer minor unit** เท่านั้น ห้าม float

## 5. ผลจากการอยู่บน Supabase (ต่างจาก reverse target ที่ Codex ทำไว้)

| เรื่อง | reverse target เดิม | Chata บน Supabase |
|---|---|---|
| Account PK | `bigint GENERATED ALWAYS AS IDENTITY` | **`uuid` references `auth.users(id)`** — จำเป็นเพื่อให้ `auth.uid()` ใน RLS ใช้ได้ |
| Auth / OTP | ตาราง `login_identity`, `otp_challenge`, `session`, `refresh_token` ทำเอง | **ใช้ `auth.*` ของ Supabase เป็นหลัก** (phone OTP, Apple, Google, email) แล้วเก็บเฉพาะส่วนที่ Supabase ไม่ให้ ในตารางของเราเอง |
| Realtime | Socket.IO + Redis presence | **Supabase Realtime (postgres_changes / broadcast / presence)** — authoritative state ยังอยู่ในตาราง |
| Worker / outbox | worker process แยก | **`pg_cron` + `pg_net`** เรียก Edge Function |
| Redis | presence, rate limit, pub/sub | ไม่มี Redis ใน v1 → presence ใช้ Realtime Presence, rate limit ใช้ตาราง + index |

## 6. Cross-platform (iOS ก่อน, Android ตาม — DB เดียวกัน)

| เรื่อง | ข้อกำหนดต่อ schema |
|---|---|
| IAP สองเจ้า | `payment_order.provider` รับ `apple_iap`, `google_play`, `bank_transfer`, `promptpay`, `card` — และตาราง purchase token ต้องเก็บได้ทั้ง Apple (`original_transaction_id`, JWS) และ Google (`purchase_token`, `order_id`) ซึ่งรูปแบบต่างกันสิ้นเชิง |
| ราคาต่อ store | Apple/Google ใช้ price tier คนละชุด → แยก `store_product_id` ต่อ platform อย่าใช้ column เดียว |
| Push | `device_token.platform ∈ {ios, android}`; FCM คุมได้ทั้งคู่ แต่เผื่อ APNs direct |
| Deep link | routing ต้อง platform-neutral |
| ห้ามมี | ตาราง/column ที่ผูกกับ client ตัวใดตัวหนึ่ง |

## 7. Deliverable ที่ user ต้องการรอบนี้

1. `docs/specs/chata-database-design.md` — **design spec เอกสารเต็ม** (ละเอียด)
2. `db/chata.dbml` — **DBML** paste เข้า https://dbdiagram.io ได้เลย (user จะดูที่ dbdiagram.io)
3. `docs/specs/chata-erd.md` — **Mermaid ERD** ดูใน Obsidian/GitHub ได้

**ยังไม่ต้องทำรอบนี้:** SQL migration จริง, โค้ด Swift, RLS policy เต็มทุกบรรทัด (ระบุเป็น policy intent พอ)

## 8. แหล่งข้อมูลอ้างอิง (reverse artifacts)

ทั้งหมดอยู่ที่ `/Users/ray/private/reverse-dounglive/`

| ไฟล์ | ใช้ทำอะไร |
|---|---|
| `REVERSE-INDEX.md` | สารบัญรวม |
| `DuangLive-Reconstructed-Backend-ERD.md` | ERD ตั้งต้น 30+ entity |
| `database-constraints.reconstructed.sql` | target schema 35 ตาราง พร้อม constraint (สำคัญที่สุด) |
| `DuangLive-Normalization-and-Index-Plan.md` | กฎ canonical type + index plan |
| `DuangLive-Coin-Ledger-Spec.md` | double-entry ledger + idempotency |
| `DuangLive-Payment-System-Reverse.md` | payment provider flow |
| `DuangLive-Backend-Data-Dictionary.md` / `backend-data-dictionary.json` | data dictionary ราย field |
| `DuangLive-Domain-State-Machines.md` | state machine ของ question/appointment/call |
| `call-state-machine.json`, `DuangLive-SocketIO-and-Call-Protocol.md` | call state + realtime protocol |
| `DuangLive-API-Validation-and-Idempotency-Policy.md` | validation + idempotency scope + rate-limit bucket |
| `DuangLive-Auth-and-Session-Lifecycle.md`, `auth-session-hardening.sql` | auth/session |
| `DuangLive-Numeric-Status-Catalog.md` | ความหมายของ status ตัวเลข |
| `DuangLive-Transaction-Outbox-Worker-Map.md` | transaction boundary + outbox |
| `DuangLive-Backend-Reference-Architecture.md` | สถาปัตยกรรมอ้างอิง |
| `openapi.reconstructed.json` | 88 path / 138 schema |

## 9. Open questions (เติมท้ายเอกสารถ้าเจอ)

- ยังไม่เคาะ: media provider สำหรับ call/live (LiveKit vs Agora vs Twilio)
- ยังไม่เคาะ: AI provider สำหรับดูดวง และวิธีคิด quota/cost
- ยังไม่เคาะ: payout / KYC ของ seer ต้องรองรับข้อกำหนดไทยระดับไหน
