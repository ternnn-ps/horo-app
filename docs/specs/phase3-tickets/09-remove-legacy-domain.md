# 09: ลบ domain เก่าทิ้งทั้งชุด (contract step)

**What to build:** เมื่อทุกหน้าจอย้ายมาใช้ domain ใหม่หมดแล้ว ลบของเก่าออกให้เหลือคำศัพท์ชุดเดียวในโค้ดเบส:
`ReadingRequest`, `ChatThread`, `ChatMessageRecord`, `SeerReview`, `HoroDataServicing`,
`MockHoroDataService`, `RecordStoring`, `UserDefaultsRecordStore` และ CRUD ที่เก็บใน `UserDefaults`
พร้อมเทสเก่าที่ผูกกับของเหล่านี้

นี่คือขั้น contract ของ expand→contract ที่ตั้งใจไว้ตั้งแต่ ticket 02 — ทำท้ายเพื่อให้ระหว่างทาง
โค้ดคอมไพล์ผ่านตลอดและเราไม่ต้องทำงานตาบอด

**Blocked by:** 07 (Close and settle)

**Status:** ready-for-agent

- [ ] ไม่มีสัญลักษณ์ของ domain เก่าเหลือในโปรเจกต์ (ค้นแล้วต้องไม่เจอ)
- [ ] ไม่มีการอ้าง `UserDefaults` สำหรับข้อมูลโดเมนเหลืออยู่ (session ของ SDK ไม่นับ)
- [ ] เทสเก่าที่ถูกลบ ถูกแทนด้วยเทสใหม่ที่ครอบพฤติกรรมเดียวกันบน seam ใหม่แล้ว
- [ ] แอปคอมไพล์ผ่านและเดินครบลูปได้เหมือนก่อนลบ

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
