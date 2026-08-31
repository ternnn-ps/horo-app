---
tags: [chata, assessment, scope, progress]
updated: 2026-08-29
status: superseded-in-part
---

# Chata — ประเมินความคืบหน้าแบบไม่เข้าข้างตัวเอง (2026-08-29)

> [!warning] อัปเดตท้ายวันเดียวกัน
> ประเมินนี้ทำ**ตอนเช้า** ก่อนลงมือเฟส 4 · ตอนนี้ **payout ทำเสร็จแล้ว (ticket 01–04)**
> ข้อ "หมอดูยังเอาเงินออกไม่ได้เลย" ข้างล่างจึง**ไม่จริงแล้วบนเครื่อง** — แต่ยังจริงในแง่ที่ว่า
> ยังไม่ขึ้น cloud และยังไม่มีใครเห็นหน้าจอด้วยตา · ดู [[Chata Phase 4 Payout and Call]]
>
> ตัวเลขปรับใหม่: scope v1 เต็ม **~30–33%** · MVP แชทถามหมอดูแบบจ่ายเงิน **~65%**
> (ตาราง 22 → 25 ใบ และปิดโดเมนที่เคยเป็นช่องโหว่ใหญ่สุดไปหนึ่งอัน)

hub: [[Chata]] · เฟสล่าสุด: [[Chata iOS Phase 3]] · สถาปัตยกรรม: [[Chata Architecture]]

ตอบคำถาม "ระบบภาพรวมถึงกี่ % แล้ว" — ยึด scope v1 ที่เคาะไว้ใน `docs/specs/00-design-brief.md`
ไม่ใช่ยึดว่าเฟส 3 เสร็จแล้ว (สองอันนี้ต่างกันมาก และเป็นที่มาของการหลอกตัวเอง)

## ตัวเลข

| ถ้านิยาม "ระบบ" ว่า… | % |
|---|---|
| **scope v1 เต็มตามที่เคาะไว้** (parity ทั้ง 15 domain + horoscope/AI + live stream) | **~25–30%** |
| ถ้าตัดเหลือ **MVP แชทถามหมอดูแบบจ่ายเงิน** อย่างเดียว | **~55–60%** |
| เฟส 3 (ต่อ iOS เข้า Supabase) | ~95% (เหลือ Google Sign-In ที่ติด credential) |

**ตัวเลขที่ตอบคำถามคือ 25–30%** — เพราะ design brief เคาะ scope v1 ไว้ว่า "full parity + 2 domain ใหม่"
ไม่ใช่ MVP

## หลักฐานที่ใช้คิด

**ฐานข้อมูล: 22 ตาราง จากที่ประมาณไว้ 48–52**

มีจริง — `account` `user_profile` `seer_profile` `skill` `seer_skill` `seer_service`
`question` `question_message` `wallet` `ledger_transaction` `ledger_entry`
`coin_package` `payment_order` `iap_receipt` `app_config` `notification_inbox`
`outbox_event` `audit_log` `rate_limit_counter` `block_relation` `seer_application` `seer_document`

**ยังไม่มีเลยแม้แต่ตารางเดียว** — appointment · voice/video call + call extension · voucher ·
referral · **payout** · review/rating · moderation · horoscope/AI (birth chart, content,
AI session, quota, cost tracking) · live stream + gift

⚠️ ระวังหลงตัวเอง: หลาย domain **มีร่องรอยอยู่ในโค้ดแต่ไม่มีของจริง** — เป็น enum value,
คอลัมน์ flag, หรือคอมเมนต์ "เติมกลับเฟส 2" เท่านั้น เช่น
- `seer_profile.accepts_appointment` มีคอลัมน์ แต่ไม่มีตาราง appointment
- `seer_profile.rating_avg` / `rating_count` มีคอลัมน์ **แต่ไม่มีตาราง review** → ค่าจะเป็น 0 ตลอดกาล
- `ledger_entry` enum มีค่า `payout` `gift` `referral_bonus` `ai_charge` แต่ไม่มี domain ไหนสร้างมันได้

**ค้นเจอคำในโค้ดไม่เท่ากับมีฟีเจอร์** — บทเรียนตอนประเมินรอบนี้

**iOS: 80 `struct ... : View` ต่อของจริงแล้วราว 12–15 ตัว**

ต่อจริงแล้ว: login · กระเป๋าเงิน · รายชื่อหมอดู + ค้นหา · ซื้อคำถาม (escrow) ·
แชท + Realtime · คิวหมอดู + ตอบ · ขอปิด/ยืนยัน/ปฏิเสธ · ยกเลิกแล้วคืนเหรียญ · เติมเหรียญโหมด dev

ยัง mock หรือยังไม่มี: จองสาย 15/30/60 นาที · นัดหมาย · รีวิว/ให้ดาว · ปุ่ม block ·
หน้าจอสมัครเป็นหมอดู · ซื้อ IAP จริง · แก้โปรไฟล์ให้ถึงเซิร์ฟเวอร์ ([[Chata iOS Phase 3|ticket 12]]) ·
แจ้งเตือน push · voucher · referral · ดวงราย/AI · live

## จุดที่สำคัญกว่าตัวเลข

**1. หมอดูยังเอาเงินออกไม่ได้เลย** — วงจรเงินจบที่ `payable_coin` เพิ่มขึ้นเท่านั้น
ไม่มีตาราง payout ไม่มี RPC ขอถอน ไม่มีเส้นทางโอนออก **นี่ไม่ใช่ฟีเจอร์ที่ขาด แต่คือด้านที่หายไป
ครึ่งหนึ่งของตลาด** — ที่ผ่านมาโฟกัสฝั่ง "เงินเข้า" ล้วน

**2. Apple IAP ยังไม่เคยเจอ Apple จริงสักครั้ง** — ตัวตรวจลายเซ็นเขียนเองและทดสอบด้วย CA
ที่สร้างเองผ่านครบ แต่ยังไม่มีบัญชี Apple Developer ($99) จึงยังไม่เคยมีใบเสร็จจริงวิ่งผ่าน
โหมดที่ใช้อยู่คือ `local_test` ซึ่ง **ไม่ตรวจลายเซ็นเลย**

**3. push notification ยังไม่มี** — `outbox_event` สะสมไว้เฉย ๆ ปลายทางเดียวของมันคือ push
ซึ่งต้องมี APNs key ซึ่งต้องมีบัญชี Apple Developer อีกเหมือนกัน

**4. Android = 0%** — design brief เขียนว่า "iOS ก่อน Android ตาม DB เดียวกัน"
DB ใช้ร่วมได้จริง แต่แอปยังไม่มีบรรทัดเดียว

**5. ยังไม่มีอะไรที่พร้อมให้ผู้ใช้จริงแตะ** — ไม่มี monitoring, ไม่มี CI, ไม่มี privacy policy,
ไม่มี asset สำหรับ App Store, `payment.iap_mode` บน cloud ยังเป็น `local_test`

## ที่แข็งแรงจริง (ไม่ควรลดค่า)

ส่วนที่ทำไปแล้วคือส่วนที่**ยากที่สุดและแก้ทีหลังแพงที่สุด** — double-entry ledger แบบ append-only,
escrow, idempotency ทุก mutation ที่แตะเงิน, RLS ที่พิสูจน์ด้วยบัญชีจริงสามบัญชี, rate limiting,
lifecycle job, และเทสสามชั้นที่ยิงฐานจริง ไม่ใช่ mock

domain ที่เหลือส่วนใหญ่เป็นการ**ต่อยอดบนโครงนี้** ไม่ใช่การรื้อ — voucher/referral/payout
ล้วนเป็น ledger entry ชนิดใหม่บนกลไกเดิม ส่วน call/live ต้องพึ่ง provider ภายนอกซึ่ง DB เก็บแค่ metadata

เพราะงั้น 25–30% นี้ **ไม่ใช่ 25% ของความพยายาม** — น่าจะผ่านงานที่ยากที่สุดมาแล้วเกินครึ่ง
แต่ถ้าวัดเป็น "ผู้ใช้ทำอะไรได้บ้าง" ก็คือ 25–30% จริง ๆ

## ก้อนใหญ่ที่เหลือ เรียงตามที่ควรทำก่อน

1. **payout** — หมอดูถอนเงินได้ (ปิดวงจรเงินให้ครบสองด้าน)
2. **บัญชี Apple Developer** — ปลดล็อก IAP จริง + push พร้อมกัน ติดอยู่สองอย่างเพราะเรื่องเดียว
3. **review/rating** — มีคอลัมน์รออยู่แล้ว ขาดแค่ตาราง + RPC
4. **หน้าจอสมัครเป็นหมอดู** — backend เฟส 2 ทำไว้ครบแล้ว แต่ยังไม่มี UI
5. **call/appointment** — ก้อนใหญ่ ต้องเลือก provider ก่อน
6. horoscope/AI · live+gift — domain ใหม่ทั้งคู่ ยังไม่เริ่ม
