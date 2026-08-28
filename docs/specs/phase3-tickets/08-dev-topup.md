# 08: ปุ่มเติมเหรียญโหมด dev

**What to build:** นักพัฒนากดปุ่มเติมเหรียญในแอป → แอปยิง Edge Function `verify-iap` โหมด `local_test`
→ เหรียญเพิ่มในกระเป๋าจริงตามแพ็กที่เลือกจาก `coin_package` · ปุ่มนี้ต้องหายไปเองเมื่อระบบไม่ได้อยู่โหมด `local_test`

คุณค่าของก้อนนี้ไม่ใช่แค่ความสะดวก — มันปิดช่องว่าง "ยังไม่เคยมี client เรียก `verify-iap` เลยสักครั้ง"
โดยไม่ต้องมีบัญชี Apple Developer

**Blocked by:** 02 (Login + wallet)

**Status:** done (2026-08-29)

- [x] รายการแพ็กมาจากตาราง `coin_package` จริง ไม่ hardcode
- [x] เติมสำเร็จ → ยอดเหรียญเพิ่มตรงตามแพ็ก และหน้าจออ่านยอดใหม่จาก server
- [x] ปุ่ม/หน้าจอนี้ไม่ปรากฏเมื่อ `payment.iap_mode` ไม่ใช่ `local_test`
- [x] ถ้า server ปฏิเสธ (เช่นไม่มี env `ALLOW_UNVERIFIED_IAP`) → แอปแสดงเหตุผลที่อ่านรู้เรื่อง ไม่ crash และเหรียญไม่เพิ่ม
- [x] integration test: เติมสำเร็จ / โหมดไม่ใช่ local_test แล้วถูกปฏิเสธ

## ที่ตัดสินใจระหว่างทาง

**แอปถามเซิร์ฟเวอร์ว่าเติมได้ไหม แทนที่จะอ่าน config เอง** — `GET /functions/v1/verify-iap`
คืน `{ mode, dev_topup_allowed }`

เหตุผล: เงื่อนไขมีสองชั้นและอยู่คนละที่ที่ client มองไม่เห็นทั้งคู่
`app_config.payment.iap_mode` ตั้ง `is_public = false` ไว้ (RLS ปิด แอปอ่านไม่ได้โดยตั้งใจ)
ส่วน `ALLOW_UNVERIFIED_IAP` เป็น env ของ Edge Function เท่านั้น ไม่มีทางที่ client จะรู้

ทางเลือกที่ไม่เลือก: เปิด `payment.iap_mode` เป็น public — ทำได้ด้วย migration บรรทัดเดียว
แต่แอปจะรู้แค่โหมด ไม่รู้เรื่อง env → บน cloud ที่ config ยังเป็น `local_test` แต่ไม่มี env
ปุ่มจะโผล่แล้วกดไม่ได้ และต้องเปิด config ภายในให้ anon อ่านถาวร

**ไม่มี migration ในก้อนนี้** — ทั้งหมดเป็น Edge Function + client

## หลักฐาน

| ชั้น | ผล |
|---|---|
| REST (`scripts/test-rest-integration.sh` ข้อ 8) | 31/31 — เติมจริง, ยิงซ้ำไม่เติมรอบสอง, สลับเป็นโหมด production แล้วถูกปฏิเสธ |
| iOS (`ChataAuthIntegrationTests`) | 21/21 — `testDevTopUpFollowsWhatTheServerAllows` เดินได้ทั้งขา "อนุญาต" และ "ไม่อนุญาต" |
