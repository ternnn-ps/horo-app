---
tags: [chata, ios, swift, supabase, realtime, testing]
updated: 2026-08-29
status: pr-open
---

# Chata เฟส 3 — ต่อ iOS เข้ากับ Supabase จริง

hub: [[Chata]] · สถาปัตยกรรม: [[Chata Architecture]]
spec ในโปรเจค: `docs/specs/phase3-ios-supabase.md` · ticket: `docs/specs/phase3-tickets/` (12 ใบ)
branch: `feat/ios-supabase` · **PR #3 เปิดแล้ว** https://github.com/ternnn-ps/horo-app/pull/3 (+2,829 / −1,189, 36 ไฟล์)

## เป้าหมายของเฟสนี้

ระบบหลังบ้าน 19 migration ผ่านเทสหมด **แต่ยังไม่เคยมี client จริงเรียกสักครั้ง** —
เทส SQL ทุกชุดรันในนามเจ้าของฐานข้อมูล ซึ่ง[[Chata|บทเรียน 20260827000007]] พิสูจน์แล้วว่า
พิสูจน์เรื่องสิทธิ์ไม่ได้เลย เฟสนี้จึงทำ vertical slice สองฝั่งให้เดินครบวงจรเงินจาก client จริง

## สถานะ (2026-08-29)

| ticket | สถานะ |
|---|---|
| 01 fixture ด้วยคำสั่งเดียว | ✅ `scripts/seed-dev-fixture.sh` |
| 02 login + กระเป๋าเงิน | ✅ (SDK Auth + เทส integration ในแอป) |
| 03 รายชื่อหมอดูจาก DB | ✅ (เพื่อนร่วมทีมทำไว้ + เทสยืนยัน) |
| 04 ซื้อคำถาม escrow | ✅ + แก้บั๊กหักเหรียญซ้ำ |
| 05 แชท + Realtime | ✅ ทั้ง migration และฝั่ง client |
| 06 คิวหมอดู + ตอบ | ✅ (โค้ดเดิม + realtime ทำให้อัปเดตเอง) |
| 07 ปิดงาน เงินถึงหมอดู | ✅ แถบจัดการงานในแชททั้งสองฝั่ง |
| 08 ปุ่มเติมเหรียญ dev | ✅ ถามสิทธิ์จาก verify-iap ด้วย GET |
| 09 ลบ domain เก่า | ✅ −1,079 บรรทัด |
| 10 Google Sign-In | ⬜ รอ OAuth credential จาก user |
| 11 smoke cloud + PR | ✅ **PR #3** · SQL 6/6 · REST local 31 / cloud 25 · iOS local 18 / cloud 18 |
| 12 เอาข้อมูลโดเมนออกจาก UserDefaults | ⬜ แตกออกมาจาก 09 |

## ข้อตัดสินใจใหญ่: ลง SDK แค่ `Auth` + `Realtime`

เพื่อนร่วมทีม (Pacharapol) เขียน REST เองด้วย `URLSession` ไว้ 680 บรรทัด **DTO map ตรงกับ
ตารางจริงถูกต้อง** จึงไม่รื้อ — เปลี่ยนแค่ที่มาของ access token

เหตุผลที่ต้องมี SDK: **Realtime อย่างเดียว** ที่เหลือเป็นของแถม
เขียน WebSocket เองต้องทำ Phoenix protocol + heartbeat + reconnect/backoff + rejoin ทุกห้อง
+ ยัด token ใหม่เข้า channel ทุกครั้งที่ refresh + ตั้ง join timeout เอง (private channel ที่ไม่มีสิทธิ์
บางกรณี server เงียบไปเลย) — SDK ทำให้หมด รวมถึง reconnect ตอนกลับมา foreground

`supabase-swift` แตกเป็น product แยก 6 ตัว เลือกลงเฉพาะที่ใช้ได้ · iOS 16+ (แอปตั้ง 26.1)

## 3 บั๊กที่เจอในโค้ดที่ต่อ Supabase (แก้แล้วทั้งหมด)

**1. กดส่งซ้ำ = หักเหรียญสองรอบ** — `SupabaseQuestionDraft` มี default `clientRequestID = UUID()`
และ UI สร้าง draft ใหม่ทุกครั้งที่กดส่ง → retry ได้ key ใหม่ = ซื้อสองครั้ง
ทั้งที่ `submit_question` กันไว้ให้แล้ว (ยิง key เดิมได้ `replayed:true` ไม่แตะกระเป๋า)
→ ตัด default UUID ออกจาก init ให้สร้างได้ทางเดียวคือ `startDraft()` ตอนเริ่มร่าง
แล้วแยกกติกาเป็น `QuestionDraftPolicy` ให้เทสได้

นี่คือเคสเป๊ะ ๆ ที่ reverse ของ DuangLive เตือน: client ยิงคำขอเดิมซ้ำเองหลัง auto-login
โดยผู้ใช้ไม่รู้ตัว → ทุก mutation ต้อง idempotent **ทั้งฝั่ง server และฝั่ง client**

**2. session อยู่ใน memory ล้วน** → ปิดแอปหลุด login ทุกครั้ง → SDK เก็บ Keychain
(ห้ามเก็บรหัสผ่านเองแบบ DuangLive ที่เก็บ plaintext ใน SQLite)

**3. refresh token เก็บไว้แต่ไม่เคยใช้** → ใช้ครบ 1 ชม. แล้ว 401 ทั้งแอป กู้เองไม่ได้
ที่เขียนเองแล้วพลาดง่ายคือตอนหลายคำขอชน 401 พร้อมกันแล้วแย่งกัน refresh

## สถาปัตยกรรมเทส 3 ชั้น

| ชั้น | ตอบคำถามว่า | ที่อยู่ | จำนวน |
|---|---|---|---|
| SQL | logic ในฐานถูกไหม | `db/tests/*.test.sql` | 6 ชุด |
| REST (curl) | contract ถูกไหมด้วยสิทธิ์ `authenticated` จริง | `scripts/test-rest-integration.sh` | 31 ข้อ |
| iOS | **แอปคุยกับ Supabase ได้จริงไหม** | `HoroTestTests/` | 21 ตัว |

ชั้น iOS สำคัญเพราะรันในโปรเซสของแอปเอง เลยพิสูจน์สิ่งที่ mock พิสูจน์ไม่ได้:
ATS ยอมให้ต่อ 127.0.0.1, SDK auth ทำงาน, RLS ตอบถูก, และผู้ถามได้รับข้อความของหมอดู
ผ่าน Realtime ภายใน 1.1 วินาที

**กฎ:** `FakeChataClient` ห้ามจำลองกฎเรื่องเงิน — ความจริงเรื่องเงินมีที่เดียวคือ Postgres
ของปลอมที่ฉลาดเกินไปทำให้เทสเขียวทั้งที่ระบบจริงพัง

## ผลทดสอบบน cloud (chata-dev, 2026-08-28)

| ชั้น | ผล |
|---|---|
| migration | 22/22 sync |
| fixture | สร้างบัญชี + อนุมัติหมอดูผ่านเส้นทางจริง + เติมเหรียญ สำเร็จ |
| REST | 23 ข้อผ่าน (ข้ามตรวจ ledger เพราะต่อ psql เข้า remote ไม่ได้) |
| iOS | 20 ตัวผ่าน รวม Realtime ที่วิ่งผ่าน wss จริง |

บัญชีทดสอบมีบน cloud แล้ว: `customer@horo.test` / `seer@horo.test` / `outsider@horo.test`
(`HoroTest123!`) — เพื่อนร่วมทีมใช้ login ในแอปที่ชี้ cloud ได้เลย

⚠️ cloud ยังตั้ง `payment.iap_mode = local_test` แปลว่า `dev_grant_coins` ใช้ได้อยู่
(service_role เท่านั้น) — ก่อนเปิดใช้จริงต้องสลับเป็น production ซึ่งจะปิดตัวเองทันที

## บทเรียนจากการให้ user ทดสอบด้วยมือ (2026-08-28)

user รายงานว่า "ปิดงานแล้วยอดยังเหลือ 850 เท่าเดิม" — **ตัวเลขถูกต้อง** (ผู้ถามจ่ายไปแล้ว
เงินไม่กลับมา สิ่งที่ขยับคือ reserved → payable ของหมอดู) แต่ UI ไม่ได้บอกอะไรเลย

**บทเรียน: เทสผ่านหมดทุกชั้นแล้วยังไม่พอ ถ้าหน้าจอไม่เล่าเรื่องเงินให้ครบ**
integration test ตรวจ `reserved_coin` กับ `payable_coin` ทุกข้อ แต่ไม่มีเทสไหนถามว่า
"ผู้ใช้มองเห็นตัวเลขนี้ไหม" — view model เก็บค่าไว้ตั้งแต่แรกแต่ลืมเอาขึ้นจอ
ทั้งที่เขียน user story ข้อ 8 กับ 35 ไว้ใน spec เอง

→ แก้แล้ว: ฝั่งผู้ถามเห็น `850 coins · 300 held` · ฝั่งหมอดูเห็น `ยอดค้างจ่าย 210 เหรียญ`
→ ยืนยันด้วยตาบนจอจริงแล้ว (screenshot)

**เงินในระบบตอนนี้ (cloud):** customer available=850 reserved=300 · seer payable=210
(2 งานปิดแล้ว × 105 = 70% ของ 150 · แพลตฟอร์มได้ 45/งาน)

## ticket 08 — เติมเหรียญโหมด dev (2026-08-29)

**ไม่มี migration เลย** ทั้งก้อนเป็น Edge Function + client

**ที่ตัดสินใจ: แอปถามเซิร์ฟเวอร์ว่าเติมได้ไหม แทนที่จะอ่าน config เอง**
`GET /functions/v1/verify-iap` → `{ mode, dev_topup_allowed }`

เงื่อนไขมีสองชั้นและอยู่คนละที่ที่ client มองไม่เห็นทั้งคู่ — `app_config.payment.iap_mode`
ตั้ง `is_public = false` (RLS ปิด ตั้งใจ) ส่วน `ALLOW_UNVERIFIED_IAP` เป็น env ของ function
ทางเลือกที่ไม่เลือกคือเปิด `payment.iap_mode` เป็น public ด้วย migration บรรทัดเดียว
แต่แอปจะรู้แค่โหมด ไม่รู้เรื่อง env → **บน cloud ที่ config ยังเป็น `local_test` แต่ไม่มี env
ปุ่มจะโผล่แล้วกดไม่ได้** และต้องเปิด config ภายในให้ anon อ่านถาวร

หลักการที่ได้: **เมื่อเงื่อนไขกระจายอยู่หลายที่ ให้ที่ที่เห็นครบเป็นคนตอบ อย่าให้ปลายทางประกอบเอง**

**ซ่อนแผ่นชำระเงินจำลองเมื่อเติมของจริงได้** — ปล่อยให้ปุ่ม "ชำระ THB" ปลอม (บวกยอดในเครื่อง)
อยู่ข้างปุ่มที่เติมเงินจริง คือการสร้างบั๊กแบบเดียวกับบทเรียนเมื่อวาน: หน้าจอเล่าเรื่องเงินผิด

## ticket 09 "domain เก่า" คืออะไรกันแน่ (สำรวจ 2026-08-29)

**คำตอบสั้น:** โมเดล+service ชุดแรกที่เขียนไว้ตอนแอปยังเป็น mock ล้วน ยังไม่ได้ต่อ Supabase
พอเฟส 3 ต่อของจริงเข้าไป เกิดคำศัพท์ชุดที่สองทับหน้าที่กันทั้งชุด แต่ยังไม่ได้ลบของเดิม
(เป็น **contract step ของ expand→contract** ที่ตั้งใจไว้ตั้งแต่ ticket 02 — ทำท้ายเพื่อให้ระหว่างทาง
โค้ดคอมไพล์ผ่านตลอด ไม่ต้องรื้อไปเขียนไป)

| ของเก่า (mock, `UserDefaults`) | ของใหม่ (Supabase จริง) |
|---|---|
| `ReadingRequest` / `ReadingRequestDraft` / `ReadingRequestStatus` | `SupabaseQuestion` / `SupabaseQuestionDraft` / `SupabaseQuestionLifecycle` |
| `ChatThread` | `SupabaseQuestion` (คำถาม = ห้องแชท ไม่มี thread แยก) |
| `ChatMessageRecord` | `SupabaseQuestionMessage` |
| `SeerProfile` / `CustomerProfile` / `HoroUser` | `SupabaseSeerListing` / `SupabaseAccount` |
| `SeerReview` | ยังไม่มี (เฟส 2 ของ backend) |
| `HoroDataServicing` + `MockHoroDataService` | `SupabaseHoroDataService` |

**สิ่งที่พบตอนสำรวจจริง — ของเก่าเป็น dead code ไปแล้วเกือบทั้งหมด**

`ContentView.swift` (5,749 บรรทัด = UI ทั้งแอป) อ้างถึง type จาก `HoroDomainModels.swift`
**ศูนย์ครั้ง** ทุกตัว — `ReadingRequest`, `ChatThread`, `SeerProfile`, `HoroUser`, `CustomerProfile`
ไม่มีสักตัวที่หน้าจอยังใช้ ของพวกนี้ยังคอมไพล์อยู่ได้เพราะอ้างกันเองในกลุ่ม + มีเทสเก่าค้ำไว้

ยอดที่จะหายไปถ้าลบ:

| ไฟล์ | บรรทัด |
|---|---|
| `HoroTest/Models/HoroDomainModels.swift` | 394 |
| `HoroTest/Services/MockHoroDataService.swift` | 372 |
| `HoroTest/Services/HoroDataService.swift` (protocol + `HoroDataError`) | 52 |
| `HoroTestTests/HoroDataServiceTests.swift` | 82 |
| ส่วนที่ `SupabaseHoroDataService` implement protocol เก่า (บรรทัด 562–714) | 153 |
| **รวม** | **~1,050** |

⚠️ `HoroDataError` อยู่ในไฟล์เดียวกับ protocol เก่า **แต่โค้ดใหม่ใช้อยู่ทั้งระบบ** ต้องย้ายออกก่อนลบไฟล์

**ข้อยกเว้นที่ไม่ใช่ dead code:** `RecordStoring` / `UserDefaultsRecordStore` / `TestRecord`
ยัง**มีชีวิต**อยู่ — เป็นตัวขับ Dashboard ฝั่งหมอดู (บันทึกงาน/โน้ต เก็บใน `UserDefaults`)
ลบทิ้งเฉย ๆ ไม่ได้ ต้องตัดสินใจก่อนว่า **ทิ้งฟีเจอร์ไปเลย** หรือ **ย้ายขึ้น Supabase**
ticket เขียนรวมไว้ในลิสต์ที่จะลบ ซึ่งตอนเขียนยังไม่รู้ว่ามันยังถูกใช้อยู่

**ยังไม่ได้คุยกับเพื่อนร่วมทีม** — `HoroDomainModels.swift` เป็นงานของเขา และพันกับเรื่องชื่อ
`Chata` vs `Horo` ที่ยังไม่ตกลงกัน

## ticket 09 ทำจริงแล้ว (2026-08-29) — commit `eee2661`

**−1,079 / +83 บรรทัด** · iOS 18/18 เขียว

ลบ `HoroDomainModels.swift` (394) · `MockHoroDataService.swift` (372) · `HoroDataService.swift` (52)
· `HoroDataServiceTests.swift` (82) · บล็อกที่ `SupabaseHoroDataService` implement protocol เก่า (153)
· `project.pbxproj` (16) · โฟลเดอร์ `HoroTest/Models/` หายไปทั้งอัน

`HoroDataError` ย้ายไปอยู่ใน `SupabaseHoroDataService.swift` ซึ่งเป็นที่เดียวที่ throw มัน
(เดิมอยู่ในไฟล์เดียวกับ protocol ยุค mock ที่โดนลบ)

**เทสเก่า 5 → ใหม่ 2** อีก 3 ตัวซ้ำกับที่ชุด REST + เทส realtime ครอบอยู่แล้ว
ตัวใหม่ที่มีค่าที่สุดคือ `testCancellingAnUnansweredQuestionRefundsEveryCoin` —
**เส้นทางคืนเหรียญจาก escrow ไม่เคยถูกเทสจากฝั่งแอปมาก่อน** มีแค่ระดับ SQL

**สิ่งที่ ticket เขียนผิดตั้งแต่แรก แล้วต้องแตกเป็น ticket 12:**
`RecordStoring` / `UserDefaultsRecordStore` / `UserDefaultsUserProfileStore` **ยังมีชีวิต**
มีหน้าจอใช้อยู่จริง ลบทิ้งเฉย ๆ = ลบฟีเจอร์ · ตัวโปรไฟล์อันตรายกว่า — ชื่อจริงอยู่บนเซิร์ฟเวอร์
แต่หน้าจอให้แก้แล้วเก็บลงเครื่อง แก้ไปอีกฝั่งไม่เห็น เป็นบั๊กพันธุ์เดียวกับ "ปิดงานแล้วยอดไม่ขยับ"

บทเรียน: **ticket ที่เขียนตอนยังไม่ได้เปิดโค้ดดู จะรวมของที่ตายแล้วกับของที่ยังมีชีวิตไว้ในกองเดียวกัน**
สำรวจก่อนลงมือ แล้วแตก ticket ใหม่ ดีกว่าฝืนทำให้ครบเกณฑ์เดิม

## เครื่องพัฒนา thrash แล้วเทสล้มสลับตัว (2026-08-29)

เทส integration ล้มคนละตัวกันสองรอบติด (realtime / signOut / devTopUp) ขุด xcresult ได้
`Processing this request timed out` · log ของ GoTrue บอก `context deadline exceeded`
ใช้เวลา 10 วินาทีต่อ request

ต้นเหตุไม่ใช่โค้ดเลย: **swap ใช้ไป 12.2 GB จาก 13.3 GB · pageouts 381k · load average 501/674/830**
ทั้งที่ CPU ของทุก container รวมกันไม่ถึง 5% — load สูงเพราะติด I/O wait จากการ swap
ปิด simulator + ตัดตัวเสิร์ฟ function ที่ซ้อนกัน + restart auth container แล้วรันใหม่ → 18/18 เขียว
และเวลาต่อเทสกลับจาก 15–45 วินาที เหลือ 0.2–0.8 วินาที

**สัญญาณที่ใช้แยกได้เร็ว: เทสล้มไม่ซ้ำตัวเดิม + เวลาต่อเทสพองผิดปกติ = เรื่องเครื่อง ไม่ใช่โค้ด**
ถ้าเป็นบั๊กจริงมันจะล้มตัวเดิมทุกรอบ

## ticket 11 — cloud smoke + PR (2026-08-29)

PR #3 → `main` · 36 ไฟล์ · **+2,829 / −1,189**

| ชั้น | local | cloud |
|---|---|---|
| SQL | 6/6 | — |
| REST | 31/31 | 25/25 |
| iOS | 18/18 | 18/18 |

**หลักฐานเงินบน cloud:** ซื้อ available 1000→850 reserved 450→600 · ยิงซ้ำคงที่ 850 ·
ปิดงาน seer payable 210→315 · สุดท้าย customer available=850 reserved=900, seer payable=315

**สิ่งที่เพิ่งรู้: `verify-iap` ไม่เคยถูก deploy ขึ้น cloud เลย** (404 NOT_FOUND) —
เอกสารเขียนไว้ว่า "ทดสอบไว้แล้ว: ยิงขอแพ็ก 730 เหรียญโดยไม่มี env → ปฏิเสธ" ซึ่งเป็นการทดสอบ
บนเครื่อง ไม่ใช่บน cloud · แปลว่าเกณฑ์ "ยืนยันว่าไม่มี ALLOW_UNVERIFIED_IAP บน cloud"
พิสูจน์ไม่ได้มาตลอด เพราะไม่มีตัวฟังก์ชันให้ถาม → deploy แล้วยืนยันสองชั้นจริง:
GET ตอบ `dev_topup_allowed:false` · POST ได้ 403 · ยอด 700→700 · `supabase secrets list` ว่างเปล่า

**บทเรียน: "ยังไม่ deploy" กับ "deploy แล้วและกันไว้ถูกต้อง" ให้ผลหน้าตาเหมือนกันจากฝั่ง client**
(ปุ่มไม่โผล่ทั้งคู่) ต้องแยกให้ออกด้วยการถามเซิร์ฟเวอร์ตรง ๆ ไม่ใช่ดูว่าแอปทำงานถูกไหม
— failure mode เดียวกับ "เทสข้ามตัวเองเงียบ ๆ": ไม่แดง แต่ไม่ได้พิสูจน์อะไร

**grep ที่แมตช์กว้างไป ทำให้เทสที่ผ่านขึ้นแดง** — ตัวนับผลของ SQL test ใช้ `grep -icE "...|FAIL"`
ไปโดน `"failed": 0` ในเอาต์พุต JSON ของ `lifecycle-jobs.test.sql` เข้า · คู่กับเรื่อง `jq // empty`
ที่พังกับ boolean เมื่อเช้า = **แพตเทิร์นเดียวกัน: เขียน matcher หลวมแล้วอ่านผลผิด**
ตรวจให้ตรงเสมอ (`^ERROR`, `\bFAIL\b`) ไม่ใช่ substring ลอย ๆ

## บทเรียนใหม่จากรอบนี้

**`phx_reply` ตอบ ok ไม่ได้แปลว่าพร้อมรับ event** — postgres_changes ต้องรอเฟรม `system`
ที่บอก "Subscribed to PostgreSQL" ก่อน ถ้าเขียนข้อมูลก่อนหน้านั้น **event หายเงียบ ไม่มี error**
เสียเวลาไล่ publication/RLS นานทั้งที่ต้นเหตุคือ race ในตัวเทสเอง

**publication ของ Supabase Realtime เริ่มต้นว่างเปล่า** ต้อง `alter publication ... add table` เอง
ไม่มีอะไรเตือน แค่ไม่มี event มา

**private channel ที่ไม่มีสิทธิ์ บางกรณี server เงียบไปเลย** ไม่ตอบสักเฟรม แยกไม่ออกจากเน็ตค้าง
(ตอนยังไม่มี policy ตอบ `Unauthorized` ชัดเจน แต่พอมี policy แล้วไม่ผ่าน กลับเงียบ)
→ ต้องดัก `onclose` + ตั้ง timeout เอง ถ้าไม่ใช้ SDK

**สอง `AuthClient` ในโปรเซสเดียวกันใช้ storage key เดียวกัน** → login บัญชีที่สองทับ session
บัญชีแรก เทสสองบัญชีจะผ่านด้วยเหตุผลผิด ๆ → เพิ่ม `storageKey` แยก

**เทสที่กินทรัพยากรของตัวเองต้องเรียก fixture ทุกรอบ** — ชุด REST/iOS หักเหรียญจริง
รันซ้ำแล้วเจอ `insufficient_coin` → ให้ตัวเทสเรียก fixture ก่อนเสมอ (เติมกลับ + ล้าง rate limit counter
ไม่งั้นเกิน 10 ครั้ง/ชม. จะติดเพดานตัวเอง)

**เทสที่หยิบข้อมูล "ใบแรกที่เจอ" เปราะมาก** — `seer_service?limit=1` ไปได้หมอดูเก่าที่ค้างในฐาน
แล้วล้มแบบงง ๆ ตอนหมอดูของเราตอบไม่ได้ (RLS ปฏิเสธ) เจอทั้งฝั่ง shell และฝั่ง Swift
→ เจาะจง id ของ fixture เสมอ

**`xcodebuild` ไม่พิมพ์ข้อความ assertion ที่ล้ม** — ต้องขุดจาก xcresult:
```bash
xcrun xcresulttool get test-results test-details --test-id "Suite/testName()" --path <xcresult> \
  | tr ',' '\n' | grep -i message
```
ถ้าไม่รู้ทริกนี้จะไล่บั๊กแบบตาบอด (ของจริงคือ `insufficient_coin` ไม่ใช่ realtime พัง)

**ตัวเช็ค "มี server ไหม" ที่เขียนผิด ทำให้เทสข้ามตัวเองเงียบ ๆ**
ใช้ `curl -f` กับ `/rest/v1/` ซึ่ง cloud ตอบ 401 → curl ล้ม → ทั้งชุดขึ้น SKIP
โดยไม่มีใครรู้ว่าไม่ได้รันอะไรเลย · **failure mode เดียวกับตอน IAP: ไม่แดง แต่ไม่ได้พิสูจน์อะไร**
→ ข้ามเฉพาะเมื่อ *ต่อไม่ติดจริง ๆ* (`curl` คืน non-zero) ไม่ใช่เมื่อ server ตอบ error code

**`supabase start` เสิร์ฟ Edge Function ให้ แต่ไม่โหลด `supabase/functions/.env.local`**
`verify-iap` ตอบ 403 `unverified_mode_not_allowed` ทั้งที่ `payment.iap_mode` เป็น `local_test`
อยู่แล้ว → หลงไปไล่ฝั่ง DB ทั้งที่ทุกอย่างถูก ต้อง `supabase functions serve --env-file` เอง
(ทำเป็น `scripts/serve-functions.sh` แล้ว และให้ชุดเทสยกตัวเสิร์ฟ + kill ให้เอง)

**`jq -r '.field // empty'` ใช้กับค่า boolean ไม่ได้** — `false` เป็น falsy ของตัวดำเนินการ `//`
เลยตกไปเป็น `empty` เหมือนกับตอนไม่มีฟิลด์ ทำให้เทสที่ตรวจ "ต้องเป็น false" ล้มแบบงง ๆ
ทั้งที่เซิร์ฟเวอร์ตอบถูก → อ่านตรง ๆ `jq -r '.field'`

**`scripts/test-ios.sh` ส่ง arg แรกไปให้ xcodebuild เป็น build action** — ใส่ชื่อ simulator
แล้วตาย `Unknown build action 'iPhone 17'` เพราะลืม `shift` (แก้แล้ว)

**macOS bash 3.2 ไม่ multibyte-safe** — `"$FOO→"` ถูกอ่านเป็นชื่อตัวแปร `FOO→` แล้ว unbound
ต้องเขียน `"${FOO}→"` เสมอ

## วิธีทำงานต่อ

```bash
cd ~/private/project-chata && git checkout feat/ios-supabase
supabase start && supabase db reset
./scripts/seed-dev-fixture.sh          # ผู้ใช้ + หมอดูอนุมัติแล้ว + เหรียญ + บัญชีคนนอก
./scripts/test-rest-integration.sh     # 31 ข้อ (เรียก fixture + ยกตัวเสิร์ฟ function ให้เอง)
./scripts/test-ios.sh                  # เทส iOS 21 ตัว (เรียก fixture + ยกตัวเสิร์ฟให้เอง)
```

บัญชีทดสอบตรงกับ `TestAccount` ในแอป: `customer@horo.test` / `seer@horo.test` /
`outsider@horo.test` — รหัสผ่าน `HoroTest123!`

รันแอปต่อ local Supabase:
```bash
SIMCTL_CHILD_SUPABASE_URL="http://127.0.0.1:54321" \
SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY="$(supabase status -o env | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')" \
xcrun simctl launch "iPhone 17" com.pacharapol.HoroTest
```

## เรื่องทีม

repo เจ้าของคือ `ternnn-ps` — **ห้าม push เข้า main ตรง ๆ** ใช้ branch + PR เสมอ
เพื่อนร่วมทีมไฟเขียวให้ลง SDK `Auth` + `Realtime` แล้ว ("ai มันแนะนำ Rest/Auth")
และตกลงว่าเราลุยฝั่งแอปต่อ เขาจะ pull มาดู

**ยังไม่ได้คุยกัน 2 เรื่อง** (จงใจเก็บไว้ ไม่โยนพร้อมกันจะเถียงสามเรื่องแล้วไม่จบสักเรื่อง):
- รื้อ `HoroDomainModels.swift` (ticket 09) ซึ่งเป็นงานของเขา
- ชื่อ `Chata` vs `Horo` — เอกสารเขาเขียนว่า "the mobile app can keep the Horo brand"
  ซึ่งสวนกับที่ user เคาะไว้ว่าโค้ดใหม่ใช้ `Chata`
