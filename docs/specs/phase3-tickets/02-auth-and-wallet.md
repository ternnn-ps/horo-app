# 02: Login จริง + เห็นยอดเหรียญจาก DB

**What to build:** ผู้ใช้เปิดแอป สมัครด้วยอีเมล+รหัสผ่าน แล้วเห็นยอดเหรียญของตัวเองที่มาจากฐานข้อมูลจริง
ปิดแอปเปิดใหม่ยังอยู่ในระบบ กด logout แล้วกลับไปหน้า login ได้ · session หมดอายุแล้วแอปพากลับหน้า login เอง
ไม่ค้างที่หน้าจอว่าง

ก้อนนี้เป็นก้อนแรกที่แตะ backend จริง จึงมาพร้อม: Supabase Swift SDK, seam `ChataClient` (protocol เดียวที่รวม auth
เข้าไว้ด้วย), `SupabaseChataClient` + `FakeChataClient`, และการสลับ local/cloud ด้วยค่าตั้งต้นที่เดียว

ของเดิมยังอยู่ครบ ไม่ลบอะไรในก้อนนี้ (ดู ticket 09)

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] สมัครใหม่แล้วมีแถว `account` + `wallet` เกิดขึ้นเอง (trigger `handle_new_user`) และแอปแสดงยอด 0 ได้ถูกต้อง
- [ ] ยอดเหรียญอ่านจาก view `v_my_wallet` แสดง available และ reserved แยกกัน
- [ ] ปิดแอปแล้วเปิดใหม่ยัง login อยู่ (session อยู่ใน Keychain ผ่าน SDK) — **ห้ามเก็บรหัสผ่านลงเครื่อง**
- [ ] logout แล้ว state ในแอปถูกล้าง ไม่มีข้อมูลบัญชีเดิมค้างให้เห็น
- [ ] session หมดอายุ/ถูกเพิกถอน → แอปพากลับหน้า login พร้อมข้อความบอกเหตุผล
- [ ] สลับระหว่าง Supabase local กับ cloud ได้โดยไม่แก้โค้ด
- [ ] unit test ของ ViewModel รันผ่าน `FakeChataClient` ได้โดยไม่ต้องมี Supabase
- [ ] integration test: signup → อ่าน wallet ได้ → logout → อ่าน wallet ไม่ได้ (skip เองถ้าไม่มี local stack)
