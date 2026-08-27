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
