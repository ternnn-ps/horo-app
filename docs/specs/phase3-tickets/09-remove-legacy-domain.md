# 09: ลบ domain เก่าทิ้งทั้งชุด (contract step)

**What to build:** เมื่อทุกหน้าจอย้ายมาใช้ domain ใหม่หมดแล้ว ลบของเก่าออกให้เหลือคำศัพท์ชุดเดียวในโค้ดเบส:
`ReadingRequest`, `ChatThread`, `ChatMessageRecord`, `SeerReview`, `HoroDataServicing`,
`MockHoroDataService`, `RecordStoring`, `UserDefaultsRecordStore` และ CRUD ที่เก็บใน `UserDefaults`
พร้อมเทสเก่าที่ผูกกับของเหล่านี้

นี่คือขั้น contract ของ expand→contract ที่ตั้งใจไว้ตั้งแต่ ticket 02 — ทำท้ายเพื่อให้ระหว่างทาง
โค้ดคอมไพล์ผ่านตลอดและเราไม่ต้องทำงานตาบอด

**Blocked by:** 07 (Close and settle)

**Status:** done (2026-08-29)

- [x] ไม่มีสัญลักษณ์ของ domain เก่าเหลือในโปรเจกต์ (ค้นแล้วเจอแต่ในคอมเมนต์ที่เล่าประวัติ)
- [x] เทสเก่าที่ถูกลบ ถูกแทนด้วยเทสใหม่ที่ครอบพฤติกรรมเดียวกันบน seam ใหม่แล้ว
- [x] แอปคอมไพล์ผ่านและเดินครบลูปได้เหมือนก่อนลบ (iOS 18/18)
- [→] ~~ไม่มีการอ้าง `UserDefaults` สำหรับข้อมูลโดเมนเหลืออยู่~~ **ย้ายไป ticket 12**
      เพราะที่เหลือไม่ใช่ domain เก่าที่ตายแล้ว แต่เป็นฟีเจอร์ที่ยังมีหน้าจอใช้อยู่จริง
      และต้องมี backend รองรับก่อน — ไม่ใช่งานลบ

## สำรวจของจริงก่อนลงมือ (2026-08-29)

`ContentView.swift` (UI ทั้งแอป 5,749 บรรทัด) อ้างถึง type จาก `HoroDomainModels.swift`
**ศูนย์ครั้งทุกตัว** — ของเก่าเป็น dead code ไปแล้ว ยังคอมไพล์อยู่ได้เพราะอ้างกันเองในกลุ่ม
บวกกับเทสเก่าที่ค้ำไว้ ลบแล้วจะหายไปราว 1,050 บรรทัด (394 + 372 + 52 + 82 + 153 ที่
`SupabaseHoroDataService` implement protocol เก่า)

**สองเรื่องที่ ticket นี้เขียนไว้ตอนยังไม่รู้:**

1. `HoroDataError` อยู่ในไฟล์เดียวกับ protocol เก่า (`HoroDataService.swift`) แต่**โค้ดใหม่ใช้อยู่
   ทั้งระบบ** — ต้องย้ายออกก่อน ลบทั้งไฟล์ไม่ได้
2. `RecordStoring` / `UserDefaultsRecordStore` / `TestRecord` **ยังมีชีวิต** — เป็นตัวขับ
   Dashboard ฝั่งหมอดู (บันทึกงาน เก็บใน `UserDefaults`) ไม่ใช่ของตายเหมือนตัวอื่น
   ต้องตัดสินใจก่อนว่าทิ้งฟีเจอร์ หรือย้ายขึ้น Supabase — **ไม่ใช่การลบแบบกลไก**


## ผลลัพธ์ (2026-08-29)

commit `eee2661` — **-1,079 / +83 บรรทัด**

| ลบ | บรรทัด |
|---|---|
| `HoroTest/Models/HoroDomainModels.swift` | 394 |
| `HoroTest/Services/MockHoroDataService.swift` | 372 |
| `HoroTest/Services/HoroDataService.swift` | 52 |
| `HoroTestTests/HoroDataServiceTests.swift` | 82 |
| บล็อกที่ `SupabaseHoroDataService` implement protocol เก่า | 153 |
| `project.pbxproj` | 16 |

`HoroDataError` ย้ายไปอยู่ใน `SupabaseHoroDataService.swift` ซึ่งเป็นที่เดียวที่ throw มัน
โฟลเดอร์ `HoroTest/Models/` หายไปทั้งอัน

**เทสเก่า 5 ตัว → ใหม่ 2 ตัว** (อีก 3 ตัวซ้ำกับที่ชุด REST + เทส realtime ครอบอยู่แล้ว)

| เทสเก่าที่ลบ | ตัวแทน |
|---|---|
| `testFetchSeersSearchesSkillsAndHeadline` | `testSeerSearchMatchesByName` — ค้นผ่าน RLS จริง |
| `testDeleteReadingRequestRemovesRelatedThread` | `testCancellingAnUnansweredQuestionRefundsEveryCoin` — พิสูจน์ว่าเหรียญออกจาก escrow กลับเข้ากระเป๋าครบ (เส้นทางนี้ไม่เคยถูกเทสจากฝั่งแอปมาก่อน) |
| `testSignInMockReturnsRequestedRole` | ไม่มีพฤติกรรมนี้บน seam ใหม่ (mock login หายไปพร้อมกัน) |
| `testCreateReadingRequestCreatesThreadForBothRoles` | ชุด REST ข้อ 2 + `testRealtimeDeliversTheSeerReplyToTheCustomer` |
| `testSendMessagePersistsAndUpdatesThreadPreview` | ชุด REST ข้อ 5 + เทส realtime |
