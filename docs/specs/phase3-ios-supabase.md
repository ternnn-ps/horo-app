# Chata — เฟส 3: ต่อ iOS เข้ากับ Supabase จริง (vertical slice สองฝั่ง)

> สถานะ: **spec สำหรับ implement** — ยังไม่มีโค้ดใดถูกเขียนจากเอกสารนี้
> ที่มา: บทสนทนา `/grill-me` 2026-08-27 (ทุกข้อในนี้ user เคาะแล้ว)
> ต้องอ่านคู่กัน: `00-design-brief.md` (§4 เส้นแบ่ง read/write), `chata-database-design.md`,
> `phase2-block-and-seer-onboarding.md`, vault `[[Chata]]` + `[[Chata Architecture]]`

## Problem Statement

ระบบหลังบ้านเดินมาถึง 19 migration / 22 ตาราง / RPC 42 ตัว และผ่านเทส SQL 6 ชุด
แต่ **ยังไม่เคยมี client จริงเรียกมันสักครั้งเดียว** — ทุกอย่างที่พิสูจน์ไปแล้วพิสูจน์ด้วย
`psql` ที่รันในนามเจ้าของฐานข้อมูล ซึ่งบทเรียนจาก `20260827000007` บอกไว้ตรง ๆ ว่า
**การทดสอบด้วยสิทธิ์เจ้าของฐานข้อมูล พิสูจน์เรื่องสิทธิ์ไม่ได้เลย** (ตอนนั้น Edge Function
เรียก RPC ไม่ได้สักตัวเพราะ `revoke ... from public` ตัด `service_role` ไปด้วย โดยเทสไม่แดง)

ฝั่งแอป `HoroTest` เป็น prototype ที่เก็บข้อมูลใน `UserDefaults` ไม่มี backend เลย และ
domain model ที่มีอยู่ (`ReadingRequest`, `ChatThread`, `SeerReview`) **ไม่ตรงกับตารางจริง** —
ที่สำคัญที่สุดคือ **ไม่มีเรื่องเงินอยู่ในโมเดลฝั่งแอปเลยแม้แต่ field เดียว** ทั้งที่ escrow
คือหัวใจของโปรดักต์

ผลคือความเสี่ยงสองข้อที่ทบกันทุกวัน:

1. ถ้าไปสร้าง domain ใหม่ (review, payout, call) ต่อ เท่ากับเดิมพันเพิ่มบน contract
   ที่ยังไม่เคยถูกพิสูจน์
2. ยิ่งเขียนโค้ด Swift บน domain model ที่ผิดมากเท่าไหร่ ค่ารื้อยิ่งแพงขึ้นเท่านั้น

## Solution

ทำ **vertical slice ที่ทะลุทุก layer และครบวงจรเงิน** ให้เดินได้จริงบน Simulator ต่อ
Supabase local: สมัคร → login → เห็นหมอดูจาก DB จริง → เติมเหรียญ (dev) → ซื้อคำถาม
(เหรียญเข้า escrow) → หมอดูตอบ → ปิดงาน → **เหรียญออกจาก escrow เข้ากระเป๋าหมอดูจริง**

slice นี้ไม่ได้ตั้งเป้าให้แอปสวยหรือครบฟีเจอร์ เป้าหมายเดียวคือ **ทำให้ contract ที่ออกแบบไว้
ถูกเรียกโดย client จริงด้วยสิทธิ์ `authenticated` จริง แล้วพิสูจน์ว่าเงินถูกต้อง**
ทุกอย่างที่ไม่รับใช้เป้าหมายนี้ถูกตัดออก (ดู Out of Scope)

## User Stories

### ตัวตนและการเข้าใช้งาน

1. As a ผู้ใช้ใหม่, I want สมัครบัญชีด้วยอีเมล + รหัสผ่าน, so that ผมเริ่มใช้แอปได้โดยไม่ต้องรอ SMS หรือบัญชี Apple
2. As a ผู้ใช้, I want ให้แอปจำ session ไว้หลังปิดแอป, so that ผมไม่ต้อง login ใหม่ทุกครั้ง
3. As a ผู้ใช้, I want กด logout ได้, so that ผมส่งเครื่องให้คนอื่นดูได้อย่างปลอดภัย
4. As a ผู้ใช้, I want ให้แอปพาไปหน้า login เองเมื่อ session หมดอายุ, so that ผมไม่เจอหน้าจอว่างที่ไม่รู้ว่าเกิดอะไรขึ้น
5. As a ผู้ใช้ที่เพิ่งสมัคร, I want ให้บัญชีและกระเป๋าเงินถูกสร้างให้อัตโนมัติ, so that ผมใช้งานต่อได้ทันทีโดยไม่ต้องตั้งค่าอะไร
6. As a เจ้าของโปรเจกต์, I want ให้ layer auth ถูกแยกเป็น seam เดียว, so that วันที่เพิ่ม Google/OTP ไม่ต้องรื้อทั้งแอป

### กระเป๋าเงิน

7. As a ผู้ใช้, I want เห็นยอดเหรียญที่ใช้ได้ของตัวเอง, so that ผมรู้ว่าซื้อคำถามได้ไหม
8. As a ผู้ใช้, I want เห็นยอดเหรียญที่ถูกกันไว้ (reserved) แยกจากยอดที่ใช้ได้, so that ผมเข้าใจว่าเหรียญไม่ได้หายไปไหน แค่ถูกกันไว้ระหว่างรอคำตอบ
9. As a ผู้ใช้, I want ให้ยอดเหรียญอัปเดตทันทีหลังทุกธุรกรรม, so that ผมไม่เห็นยอดค้างที่ทำให้ตัดสินใจผิด
10. As a ผู้ใช้, I want เห็นประวัติการเคลื่อนไหวของเหรียญ, so that ผมตรวจสอบได้ว่าเหรียญหายไปไหน
11. As a นักพัฒนา, I want ปุ่มเติมเหรียญโหมด dev, so that ผมทดสอบการซื้อได้โดยไม่ต้องมีบัญชี Apple Developer
12. As a เจ้าของโปรเจกต์, I want ให้ปุ่มเติมเหรียญ dev หายไปเองเมื่อไม่ได้อยู่โหมด `local_test`, so that ไม่มีทางที่ปุ่มแจกเหรียญฟรีจะโผล่บน production

### ค้นหาหมอดู

13. As a ผู้ใช้, I want เห็นรายชื่อหมอดูที่เปิดรับงานจริงจากฐานข้อมูล, so that ผมเลือกคนที่ตอบได้จริง
14. As a ผู้ใช้, I want เห็นราคาของแต่ละบริการเป็นจำนวนเหรียญที่ server กำหนด, so that ผมไม่เจอราคาที่ไม่ตรงตอนจ่ายจริง
15. As a ผู้ใช้, I want ค้นหาหมอดูจากชื่อหรือความถนัด, so that ผมหาคนที่ตรงเรื่องที่อยากถามได้
16. As a ผู้ใช้, I want เห็นรายละเอียดหมอดูก่อนตัดสินใจ, so that ผมมั่นใจก่อนจ่ายเหรียญ
17. As a ผู้ใช้, I want เห็นหน้าจอ "ยังไม่มีหมอดู" ที่บอกสถานะชัดเจน, so that ผมแยกออกว่าไม่มีข้อมูล ไม่ใช่แอปค้าง

### ซื้อคำถาม (เงินเข้า escrow)

18. As a ผู้ใช้, I want ส่งคำถามแรกพร้อมจ่ายเหรียญในขั้นตอนเดียว, so that ผมไม่สับสนว่าจ่ายแล้วหรือยัง
19. As a ผู้ใช้, I want เห็นยืนยันว่าเหรียญถูกหักไปกันไว้เท่าไหร่, so that ผมรู้ว่าเกิดอะไรขึ้นกับเงินของผม
20. As a ผู้ใช้, I want ให้แอปบอกว่าเหรียญไม่พอ **ก่อน** ที่ผมจะพิมพ์คำถามยาว ๆ, so that ผมไม่เสียเวลาฟรี
21. As a ผู้ใช้, I want ให้การกดส่งซ้ำ/เน็ตหลุดแล้วลองใหม่ **ไม่หักเหรียญสองรอบ**, so that ผมไม่โดนคิดเงินซ้ำ
22. As a ผู้ใช้, I want เห็นข้อความบอกเหตุผลที่ส่งไม่สำเร็จเป็นภาษาคน, so that ผมรู้ว่าต้องทำอะไรต่อ
23. As a ผู้ใช้, I want เห็นเวลาหมดอายุของคำถาม, so that ผมรู้ว่าต้องรอถึงเมื่อไหร่

### แชท

24. As a ผู้ใช้, I want เห็นข้อความของหมอดูโผล่เองโดยไม่ต้องกดรีเฟรช, so that มันรู้สึกเป็นแชทจริง
25. As a หมอดู, I want เห็นคำถามใหม่เข้าคิวเองโดยไม่ต้องกดรีเฟรช, so that ผมตอบได้เร็ว
26. As a ผู้ใช้, I want ส่งข้อความต่อเนื่องในคำถามที่เปิดอยู่, so that ผมให้รายละเอียดเพิ่มได้
27. As a ผู้ใช้, I want เห็นว่าข้อความของผมกำลังส่ง / ส่งแล้ว / ส่งไม่สำเร็จ, so that ผมไม่เดาเอาเอง
28. As a ผู้ใช้, I want กดส่งข้อความที่ล้มเหลวซ้ำได้โดยไม่เกิดข้อความซ้ำสองอัน, so that ห้องแชทไม่รก
29. As a ผู้ใช้, I want ให้แอปกันไม่ให้พิมพ์ต่อในคำถามที่ปิดไปแล้ว, so that ผมไม่พิมพ์ทิ้งไปเปล่า ๆ
30. As a ผู้ใช้, I want เห็นเหตุการณ์ระบบ (ขอปิดงาน/ปิดแล้ว/คืนเงิน) ในสายแชทเดียวกัน, so that ผมตามเรื่องได้ครบในที่เดียว

### ฝั่งหมอดู (เงินออกจาก escrow)

31. As a หมอดู, I want เห็นคิวคำถามที่ยังไม่ได้ตอบ, so that ผมรู้ว่ามีงานค้างกี่ชิ้น
32. As a หมอดู, I want ตอบคำถามแล้วสถานะเปลี่ยนเป็นกำลังคุยเอง, so that ผมไม่ต้องกดอะไรเพิ่ม
33. As a หมอดู, I want กดขอปิดงานเมื่อตอบครบแล้ว, so that ผมได้รับเงินส่วนแบ่ง
34. As a ผู้ใช้, I want กดยืนยันหรือปฏิเสธคำขอปิดงาน, so that ผมไม่ถูกปิดงานทั้งที่ยังไม่ได้คำตอบ
35. As a หมอดู, I want เห็นยอดค้างจ่าย (payable) ของตัวเองเพิ่มขึ้นหลังงานปิด, so that ผมเชื่อใจว่าระบบจ่ายเงินจริง
36. As a ผู้ใช้, I want ยกเลิกคำถามที่หมอดูยังไม่ตอบแล้วได้เหรียญคืนเต็ม, so that ผมไม่เสียเงินฟรีเมื่อไม่มีใครตอบ
37. As a หมอดู, I want เห็นหน้าจอ "ไม่มีงานค้าง" ที่ชัดเจน, so that ผมแยกออกว่าว่างจริง ไม่ใช่โหลดไม่ขึ้น

### คุณภาพ / ความเชื่อถือได้

38. As a เจ้าของโปรเจกต์, I want เทสที่พิสูจน์ว่าเงินถูกต้องรันกับ Postgres จริงเท่านั้น, so that เทสสีเขียวแปลว่าระบบใช้ได้จริง
39. As a เจ้าของโปรเจกต์, I want script สร้างบัญชีทดสอบ (ผู้ใช้ + หมอดูที่อนุมัติแล้ว) ได้ในคำสั่งเดียว, so that ทีมไม่ขี้เกียจ `db reset` แล้วเทสบนฐานสกปรก
40. As a นักพัฒนา, I want สลับระหว่าง Supabase local กับ cloud ด้วยค่าตัวแปรเดียว, so that ผมไม่ต้องแก้โค้ดตอนย้ายไปเทสบน cloud
41. As a นักพัฒนา, I want ให้ integration test ข้ามตัวเองเมื่อไม่มี Supabase local รันอยู่, so that CI ไม่แดงโดยไม่มีสาเหตุ
42. As a เจ้าของ repo, I want PR ที่อธิบายเหตุผลของการรื้อโค้ดเดิมเป็นภาษาอังกฤษ, so that ทีมรีวิวได้โดยไม่ต้องมานั่งเดา

## Implementation Decisions

### D1. Seam เดียว: protocol `ChataClient`

โค้ดเบสมี seam ที่ดีอยู่แล้วคือ protocol `HoroDataServicing` — **คงไว้เส้นเดียว ไม่เพิ่มเส้นใหม่**
เปลี่ยนชื่อเป็น `ChataClient` และยุบ auth เข้ามาอยู่ในเส้นเดียวกันนี้ด้วย (แทนที่จะแตกเป็น
seam ที่สองสำหรับ auth) เพื่อให้วันที่เพิ่ม Google/OTP แตะ implementation ตัวเดียว

```
SwiftUI Views ──► ViewModel ──► ChataClient (protocol) ──┬─► SupabaseChataClient → Postgres
                                     ▲ seam เดียว        └─► FakeChataClient     → in-memory
```

### D2. `FakeChataClient` ห้ามจำลองกฎเรื่องเงิน

fake ตอบตามสคริปต์ที่เทสกำหนดเท่านั้น (เช่น "ครั้งนี้ตอบ `insufficient_coin`")
**ห้ามคำนวณหักเหรียญ / escrow / ส่วนแบ่งเอง** เหตุผลคือบทเรียนจากงาน IAP:
ของปลอมที่ฉลาดเกินไปทำให้เทสเขียวทั้งที่ระบบจริงพัง — ความจริงเรื่องเงินมีที่เดียวคือ Postgres

### D3. ตั้งชื่อด้วยคำว่า `Chata`

type ใหม่ทั้งหมดใช้ `Chata*` ให้ตรงกับ database / DBML / product id ที่ seed ไว้
(`app.chata.coin150`) ส่วนชื่อ Xcode target `HoroTest` และ bundle id `com.pacharapol.HoroTest`
**ยังไม่แตะในเฟสนี้** — โหมด `local_test` ของ `verify-iap` ไม่ตรวจ bundle id (ตรวจแค่ product id
ให้ตรง `coin_package`) จึงไม่บล็อกอะไร และตอนซื้อบัญชี Apple ต้องตั้ง bundle id ใหม่อยู่แล้ว
เพราะของเดิมเป็นชื่อส่วนตัวของเพื่อนร่วมทีม

### D4. เขียน domain model ใหม่ให้ตรงตารางจริง 1:1 แล้วทิ้งของเดิม

`ReadingRequest` → `Question` · `ChatThread` → **ลบทิ้ง** (ข้อความห้อยกับ `question` ตรง ๆ
ไม่มีตาราง thread) · `ChatMessageRecord.id: UUID` → `QuestionMessage.id: Int64` (ต้องเรียงได้
เพราะเป็น cursor) · `SeerProfile.id`+`userId` → `accountId` เป็น PK เดี่ยว ·
`rateLabel: String` → `priceCoin: Int64` (ราคามาจาก server เสมอ) · `skills: [String]` →
อ้าง `skill(id)` · `SeerProfile.isOnline` → **ตัดทิ้ง** (presence เป็น ephemeral ผ่าน Realtime
ไม่ใช่ค่าใน profile) · `SeerReview` → **ตัดทิ้ง** (ยังไม่มีตาราง review)

`RecordStoring` / `UserDefaultsRecordStore` / CRUD บันทึกในเครื่อง — **ลบทั้งชุด** ไม่มีที่ยืน
ในระบบจริง

เหตุผลที่ไม่ทำ adapter ครอบของเดิม: จะเหลือคำศัพท์สองชุดถาวรในโค้ดเบสเดียว ทุกครั้งที่อ่านโค้ด
ต้องแปลในหัวว่า `ReadingRequest` คือ `question` — หนี้ที่ดอกเบี้ยทบทุกไฟล์ที่เขียนต่อจากนี้

### D5. ชั้นในแอปตาม `[[Chata Architecture]]`

`View (SwiftUI) → ViewModel → ChataClient → Supabase` โดย ViewModel ถือ state ของหน้าจอ
และไม่รู้จัก Supabase เลย · comment ในโค้ดเขียนเท่าที่จำเป็น (อธิบาย *ทำไม* ไม่ใช่ *ทำอะไร*)

### D6. เส้นทางเรียก backend — ยึดกฎ "operation นี้แตะเงินไหม" ของ design brief §4

| การกระทำ | เรียกอะไร | ประเภท |
|---|---|---|
| สมัคร / login / logout | Supabase Auth (`auth.users`) | SDK |
| ดูรายชื่อ/รายละเอียดหมอดู, skill | `select` ตรงผ่าน RLS | อ่าน |
| ยอดเหรียญ | `select` จาก view `v_my_wallet` | อ่าน |
| ประวัติเหรียญ | `select` จาก view `v_my_coin_history` | อ่าน |
| รายการคำถาม / ข้อความ | `select` ตรงผ่าน RLS (`question`, `question_message`) | อ่าน |
| **ซื้อคำถาม** | RPC `submit_question` | **แตะเงิน** |
| ส่งข้อความต่อเนื่อง | `insert` ตรงผ่าน RLS (มี column grant เฉพาะที่จำเป็น) | เขียน ไม่แตะเงิน |
| ขอปิดงาน / ตอบรับปิดงาน / ยกเลิกคำขอ | RPC `request_close_question`, `respond_close_question`, `cancel_close_request` | **แตะเงิน** |
| ยกเลิกคำถาม (คืนเหรียญ) | RPC `cancel_question` | **แตะเงิน** |
| เติมเหรียญ (dev) | Edge Function `verify-iap` โหมด `local_test` | external |

**ห้ามให้แอปคำนวณราคา ส่วนแบ่ง หรือยอดคงเหลือเอง** ทุกตัวเลขเรื่องเงินอ่านจาก server เท่านั้น

### D7. ⭐ Idempotency key ต้องสร้างก่อนยิงครั้งแรก และคงค่าเดิมตลอดอายุของ intent นั้น

`submit_question` รับ `p_client_request_id` + `p_client_message_id` และ **คืน `replayed: true`
เมื่อเจอ key ซ้ำ** (ไม่หักเหรียญรอบสอง) — กลไกนี้จะไร้ค่าทันทีถ้า client สุ่ม UUID ใหม่ตอน retry

ข้อบังคับ: ViewModel สร้าง UUID **ตอนผู้ใช้เริ่มร่างคำถาม** ไม่ใช่ตอนกดส่ง, เก็บไว้กับ draft นั้น,
และ retry ทุกครั้งต้องส่งค่าเดิม จนกว่าจะสำเร็จหรือผู้ใช้ทิ้ง draft · ข้อความต่อเนื่องใช้
`client_message_id` แบบเดียวกัน (มี unique `(question_id, client_message_id)` รองรับอยู่แล้ว)

ที่มา: reverse ของ DuangLive พบว่า client **ยิงคำขอเดิมซ้ำเองอัตโนมัติ** หลัง auto-login
(`res_code=2`) โดยผู้ใช้ไม่รู้ตัว — เอกสารเตือนตรง ๆ ว่าทุก mutation จึงต้อง idempotent

### D8. ยอดเหรียญเป็นภาพฉายจาก server เสมอ

หลังทุก operation ที่แตะเงินสำเร็จ **ต้องอ่าน `v_my_wallet` ใหม่** ห้ามลบยอดในเครื่องเอาเอง
(DuangLive เก็บ `remaining_coin` ใน Room แล้วให้ server ทับค่าได้ตลอดผ่าน
`UPDATE user SET remaining_coin = ?` และแนบ `coin_alert` มากับ response ที่ไม่เกี่ยวกับเหรียญด้วยซ้ำ)

### D9. Realtime สองโหมด — แชทใช้ postgres_changes, domain event ใช้ broadcast

**(ปรับปรุงหลัง implement — เดิมเขียนไว้ว่าใช้ postgres_changes อย่างเดียว)**

หลังไปอ่านว่า DuangLive ทำ socket ยังไง (`DuangLive-SocketIO-and-Call-Protocol.md`)
พบว่าสิ่งที่เขาออกแบบถูกคือ **client subscribe "เรื่องที่เกิดขึ้น" ไม่ใช่ "แถวไหนเปลี่ยน"**
— event ชื่อเป็นภาษาโดเมน (`se_start_call`) payload เป็นสิ่งที่ server กำหนด

`postgres_changes` ส่งแถวในตารางออกไปตรง ๆ = **schema คือ wire protocol** ซึ่งชนกับกฎ
"backend ต้องรองรับแอปเวอร์ชันเก่าตลอดไป" — เปลี่ยนความหมาย column วันนี้ แอปในมือคนอื่นพังทันที

| ใช้กับ | กลไก | เหตุผล |
|---|---|---|
| ข้อความแชท | `postgres_changes` (`20260827000008`) | `question_message` เป็น append-only ที่ schema จะไม่ขยับ ความเสี่ยงต่ำสุด ต้นทุนเป็นศูนย์ |
| สถานะคำถาม + (อนาคต) call signaling | **broadcast จาก trigger** (`20260827000009`) | server กำหนด payload เอง มี `v` สำหรับเวอร์ชัน บอกได้ว่า "เปลี่ยนจากอะไรเป็นอะไร" |

**ไม่ทำเซิร์ฟเวอร์ Socket.IO เอง** — ต้องมีเครื่องรันตลอด + Redis สำหรับ presence + จัดการ
scale เอง คือของที่เลือก Supabase มาเพื่อไม่ต้องทำ และจะได้มรดกบั๊กแบบเดียวกับที่เห็นใน
โค้ด DuangLive (wire format ไม่ตรงกันสองฝั่ง, reconnect แล้วไม่ rejoin, `requestCall()`
ตอนหลุด connection สั่ง `connect()` แล้ว return เฉย ๆ ไม่ยิงคำขอซ้ำ)

**ข้อจำกัดที่ client ต้องรู้:**
- `realtime.messages` เก็บข้อความแค่ **3 วัน** แล้วลบ — เป็นท่อส่ง ไม่ใช่ที่เก็บประวัติ
  ประวัติจริงอยู่ใน `question` / `question_message` เสมอ เปิดแอปมาต้อง fetch ก่อน
- private channel ที่ไม่มีสิทธิ์ **บางกรณี server เงียบไปเลยไม่ตอบอะไร** แยกไม่ออกจากเน็ตค้าง
  ถ้าไม่ตั้ง timeout เอง (อีกเหตุผลที่ควรใช้ SDK ซึ่งจัดการ timeout/CHANNEL_ERROR ให้)
- private channel ต้องยัด token ใหม่เข้า channel ทุกครั้งที่ refresh ไม่งั้น socket เงียบเมื่อ token หมดอายุ

### D9.1 รายละเอียด migration แชท

ยังไม่มี migration ไหน `alter publication supabase_realtime add table ...` เลย ต้องเพิ่มไฟล์ใหม่
ให้ `question_message` และ `question` · Realtime เคารพ RLS ที่มีอยู่แล้ว (participant เท่านั้น)
จึงไม่ต้องเขียน policy เพิ่ม · แอป subscribe เฉพาะห้องที่เปิดอยู่ และ **ยังต้องมี fetch ปกติตอนเข้าห้อง**
(Realtime ส่งเฉพาะของใหม่ ไม่ส่งประวัติ)

### D10. ไม่มี local database ในเครื่อง

เก็บลงเครื่องแค่ session (Keychain ผ่าน Supabase SDK) และ draft ที่ยังส่งไม่สำเร็จ (พร้อม
idempotency key) — **คำถาม/ข้อความ/ธุรกรรม ดึงจาก server ทุกครั้ง** ตามที่ DuangLive ทำ
(Room ของเขามีแค่ `login`/`user`/`seer`/`photos` ไม่มีตารางบทสนทนาเลย)

**ห้ามเก็บรหัสผ่านลงเครื่องเด็ดขาด** (ตาราง `login` ของ DuangLive เก็บ password เป็น plaintext
ใน SQLite เพื่อ auto re-login — เราใช้ session refresh ของ Supabase แทน)

### D11. ข้อความ error แปลที่ชั้นเดียว

RPC โยน error เป็นรหัส (`insufficient_coin`, `seer_unavailable`, `blocked_by_you`,
`rate_limited`, `invalid_state`, `not_authenticated`, `account_not_active`, `cannot_ask_yourself`,
`invalid_message`, `not_found`) · แปลงเป็นข้อความไทยที่จุดเดียวใน mapper ห้ามกระจายตาม ViewModel
· รหัสที่ไม่รู้จักต้องมีข้อความสำรอง ไม่ใช่หน้าจอว่าง

### D12. auth: email + password ก่อน, Google เป็น ticket ท้ายเฟส

`handle_new_user` สร้าง `account` + `wallet` ให้อัตโนมัติอยู่แล้ว ไม่ว่าจะ login ด้วยวิธีไหน
`auth.uid()` ก็เป็น uuid เดียวกัน — เปลี่ยนวิธี login ทีหลังไม่ต้องแตะ DB สักบรรทัด
Google ถูกวางไว้ท้ายเฟสเพราะ**บล็อกด้วยคนอื่น** (ต้องได้ OAuth client จาก Google Cloud Console
ของ user ก่อน) ไม่ควรเอามาขวางการพิสูจน์ money loop

### D13. config สลับ local/cloud ด้วยค่าเดียว

พัฒนาบน `supabase start` เป็นหลัก (Simulator ต่อ `http://127.0.0.1:54321` ได้ตรง ๆ)
แล้วสลับไป cloud `chata-dev` ตอนเทสจริง โดยเปลี่ยนค่าตั้งต้นที่เดียว ไม่แก้โค้ด

### D14. git: branch + PR เสมอ

repo เจ้าของคือ `ternnn-ps` เราไม่ใช่ admin → **ห้าม push เข้า `main` ตรง ๆ**
ก่อนเปิด PR ต้อง `git fetch origin && git pull` ให้เป็นล่าสุดก่อนทุกครั้ง
**PR description เขียนเป็นภาษาอังกฤษ** และต้องอธิบายเหตุผลของการรื้อ `HoroDomainModels.swift`
(งานของเพื่อนร่วมทีม) ให้ชัด

## Testing Decisions

### เทสที่ดีในเฟสนี้คืออะไร

เทสพฤติกรรมที่มองเห็นจากภายนอก seam เท่านั้น — "กดซื้อคำถามแล้วยอดเหรียญเปลี่ยนยังไง"
ไม่ใช่ "ViewModel เรียกเมธอดไหนกี่ครั้ง" · เทสที่ผูกกับโครงสร้างภายในจะพังทุกครั้งที่ refactor
โดยไม่ได้จับ bug จริงสักตัว

**กฎเหล็กของเฟสนี้: เทสที่พิสูจน์เรื่องเงิน ต้องรันกับ Postgres จริงเท่านั้น**
เพราะ fake ที่จำลองกฎเงินเองจะเขียวทั้งที่ระบบจริงพัง (บทเรียน IAP + บทเรียน `service_role`)

### สองชั้น

| ชั้น | ตอบคำถามว่า | รันด้วย | ครอบคลุม |
|---|---|---|---|
| unit | หน้าจอแสดงผล/แปลง error/สถานะถูกไหม | `FakeChataClient` | ViewModel ทุกตัว, error mapper, การคง idempotency key ตอน retry |
| integration | **เงินถูกไหม สิทธิ์ถูกไหม** | Supabase local จริง | `SupabaseChataClient` ทุกเส้นทางใน slice |

integration test **ต้อง skip ตัวเองอัตโนมัติ** เมื่อไม่มี Supabase local รันอยู่ (ไม่ใช่ fail)
และต้องรันด้วยสิทธิ์ `authenticated` จริง ไม่ใช่ service_role — เพราะบทเรียน `20260827000007`
พิสูจน์แล้วว่าเทสที่รันด้วยสิทธิ์สูงกว่าผู้ใช้จริง พิสูจน์เรื่องสิทธิ์ไม่ได้เลย

### สิ่งที่ integration test ต้องพิสูจน์เป็นอย่างน้อย

- ซื้อคำถาม → `available_coin` ลด, `reserved_coin` เพิ่มเท่าราคา, ผลรวมไม่เปลี่ยน
- ยิง `submit_question` ซ้ำด้วย key เดิม → `replayed: true` และ **ยอดเหรียญไม่ขยับรอบสอง**
- หมอดูตอบ → question เลื่อนเป็น `active` เอง
- ปิดงานครบวง → `reserved_coin` ของผู้ใช้ลดเป็น 0, `payable_coin` ของหมอดูเพิ่ม, ledger สมดุล
- ยกเลิกก่อนหมอดูตอบ → คืนเหรียญเต็มจำนวน
- เหรียญไม่พอ → error `insufficient_coin` และ **ไม่มีแถว question เกิดขึ้น**
- ผู้ใช้ที่ไม่ใช่คู่สนทนา **อ่านข้อความห้องนั้นไม่เห็น** (RLS)
- ผู้ใช้เรียก RPC ที่เป็นของ service_role → ถูกปฏิเสธ

### Fixture

script สร้างสถานะตั้งต้นในคำสั่งเดียว: บัญชีผู้ใช้ + บัญชีหมอดูที่ **อนุมัติแล้ว** พร้อม service
และเหรียญตั้งต้น (`auth.users` seed ผ่าน migration ไม่ได้ ต้องสร้างผ่าน API/CLI)
ถือเป็น deliverable ที่มีชื่อของตัวเอง — ถ้าไม่มี ทีมจะเลี่ยงการ `db reset` แล้วเทสบนฐานสกปรก

### Prior art

`db/tests/*.test.sql` 6 ชุด (โดยเฉพาะ `money-flow.test.sql` — รูปแบบ "ตรวจยอดก่อน/หลัง
+ ตรวจ ledger สมดุล") และ `scripts/test-iap-verifier.sh` (รูปแบบ "ต้องพิสูจน์ฝั่งบวกด้วย
ไม่ใช่พิสูจน์แต่ว่าของปลอมถูกปฏิเสธ") — เทสใหม่ทั้งหมดต้องเดินตามสองแบบนี้

## Out of Scope

ตัดออกจากเฟสนี้ พร้อมเหตุผล:

- **สมัครเป็นหมอดูในแอป** — RPC มีครบแล้ว แต่ไม่จำเป็นต่อการพิสูจน์ money loop; หมอดูในเฟสนี้
  ใช้บัญชีที่ fixture สร้างและอนุมัติให้
- **admin console อนุมัติหมอดู** — ยังทำผ่าน Supabase Studio ตามเดิม
- **block / unblock ในแอป** — DB พร้อมแล้ว แต่ต้องมีคำเตือน UI เรื่องเงินที่ยังไม่ได้ออกแบบ
- **IAP จริง / StoreKit** — เติมเหรียญใช้โหมด `local_test` เท่านั้น
- **review / rating** — ยังไม่มีตารางในฐานข้อมูล
- **push notification** — ต้องมี Apple Developer Program; แจ้งเตือนอ่านจาก `notification_inbox` แทน
- **cursor "อ่านถึงไหนแล้ว" / unread badge** — ตาราง `question` ให้ `authenticated` แค่ `SELECT`
  ยังไม่มี RPC ให้ client ขยับ `user_last_read_message_id` (DuangLive มี `readMessages` เป็น
  command เต็มตัว) ต้องเพิ่ม RPC ในเฟสถัดไป
- **อัปโหลดรูป/เสียงในแชท** — schema รองรับแล้ว (`object_key`) แต่ต้องตั้ง storage bucket + policy
- **appointment / call / live / horoscope** — ยังไม่มีตาราง
- **offline mode / local cache ของบทสนทนา** — DuangLive เองก็ไม่ทำ (ดู D10)
- **Google Sign-In** — อยู่ในเฟสนี้แต่เป็น ticket สุดท้าย และบล็อกด้วย credential จาก user
- **เปลี่ยนชื่อ Xcode target / bundle id** — ทำตอนซื้อบัญชี Apple
- **ปรับดีไซน์หน้าจอ** — ใช้ UI เดิมที่มีอยู่ ต่อสายใหม่เข้าไปเท่านั้น

## Further Notes

**ทำไมต้องเป็น slice สองฝั่ง ไม่ใช่ฝั่งผู้ใช้อย่างเดียว** — money loop ของ Chata พิสูจน์ด้วย
ฝั่งเดียวไม่ได้: เหรียญเข้า escrow ตอนซื้อ, question เลื่อนเป็น `active` ก็ต่อเมื่อหมอดูตอบ,
เงินถึงมือหมอดูก็ต่อเมื่อปิดงาน หยุดที่ฝั่งผู้ใช้เท่ากับพิสูจน์ได้แค่ครึ่งเดียวของส่วนที่พังแล้วเจ็บที่สุด

**การทดสอบสองฝั่งพร้อมกัน** ใช้ Simulator สองเครื่อง (คนละบัญชี) หรือ Simulator + Supabase Studio
ก็ได้ — ประเด็นคือต้องเห็นเงินขยับจากสองมุมในเวลาเดียวกัน

**หนี้ที่รู้ตัวและตั้งใจก่อ:** unit test เดิม 12 ตัวจะถูกลบ/เขียนใหม่ทั้งหมด เพราะมันเทส
`MockHoroDataService` บน domain ที่กำลังจะไม่มีอยู่ — นี่คือราคาของ D4 ที่จ่ายครั้งเดียวตอนนี้
แทนที่จะจ่ายทุกไฟล์ไปตลอด

**ของที่ยังไม่เคาะและจะโผล่มาแน่ในเฟสถัดไป:** อัตราแปลง coin → THB ตอน payout,
ระดับ KYC ของหมอดู, media provider สำหรับ call/live, AI provider สำหรับดูดวง
(ดู `00-design-brief.md` §9)
