# 08: ปุ่มเติมเหรียญโหมด dev

**What to build:** นักพัฒนากดปุ่มเติมเหรียญในแอป → แอปยิง Edge Function `verify-iap` โหมด `local_test`
→ เหรียญเพิ่มในกระเป๋าจริงตามแพ็กที่เลือกจาก `coin_package` · ปุ่มนี้ต้องหายไปเองเมื่อระบบไม่ได้อยู่โหมด `local_test`

คุณค่าของก้อนนี้ไม่ใช่แค่ความสะดวก — มันปิดช่องว่าง "ยังไม่เคยมี client เรียก `verify-iap` เลยสักครั้ง"
โดยไม่ต้องมีบัญชี Apple Developer

**Blocked by:** 02 (Login + wallet)

**Status:** ready-for-agent

- [ ] รายการแพ็กมาจากตาราง `coin_package` จริง ไม่ hardcode
- [ ] เติมสำเร็จ → ยอดเหรียญเพิ่มตรงตามแพ็ก และหน้าจออ่านยอดใหม่จาก server
- [ ] ปุ่ม/หน้าจอนี้ไม่ปรากฏเมื่อ `payment.iap_mode` ไม่ใช่ `local_test`
- [ ] ถ้า server ปฏิเสธ (เช่นไม่มี env `ALLOW_UNVERIFIED_IAP`) → แอปแสดงเหตุผลที่อ่านรู้เรื่อง ไม่ crash และเหรียญไม่เพิ่ม
- [ ] integration test: เติมสำเร็จ / โหมดไม่ใช่ local_test แล้วถูกปฏิเสธ
