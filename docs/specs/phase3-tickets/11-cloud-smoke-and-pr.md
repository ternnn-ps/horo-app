# 11: Smoke test บน cloud + เปิด PR

**What to build:** สลับ config ไปที่ Supabase cloud `chata-dev` แล้วเดินครบลูปจริงจากแอป:
สมัคร → เห็นหมอดู → ซื้อคำถาม → แชท → ปิดงาน → เงินเข้ากระเป๋าหมอดู · แล้วเปิด PR เข้า `main`

**Blocked by:** 07 (Close and settle), 09 (Remove legacy domain)

**Status:** ready-for-agent

- [ ] `git fetch origin && git pull` ก่อน แล้วทำงานบน branch `feat/ios-supabase` — **ห้าม push เข้า `main` ตรง ๆ**
- [ ] migration ที่เพิ่มในเฟสนี้ push ขึ้น cloud แล้วและ sync ครบ
- [ ] เดินครบลูปบน cloud สำเร็จ พร้อมหลักฐานยอดเหรียญก่อน/หลัง
- [ ] ยืนยันว่า **ไม่มี** `ALLOW_UNVERIFIED_IAP` บน cloud และปุ่มเติมเหรียญ dev ไม่โผล่
- [ ] เทส SQL 6 ชุดเดิมยังผ่านหมด ไม่มี WARNING/ERROR
- [ ] PR description **ภาษาอังกฤษ** อธิบายเหตุผลที่รื้อ `HoroDomainModels.swift` (งานของเพื่อนร่วมทีม) ให้ชัด
