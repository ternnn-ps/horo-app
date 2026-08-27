# 10: Google Sign-In

**What to build:** ผู้ใช้กดปุ่มเดียวเพื่อ login ด้วยบัญชี Google แล้วเข้าใช้งานได้เหมือน login ด้วยอีเมล
บัญชีที่ได้ผูกกับ `auth.users` เดียวกัน จึงมี `account` + `wallet` เหมือนกันทุกประการ

⚠️ **บล็อกจากภายนอก** — ต้องได้ OAuth client id + secret จาก Google Cloud Console ของเจ้าของโปรเจกต์ก่อน
ผมเข้าบัญชี Google ให้ไม่ได้ · เมื่อถึงคิวจะมีคำแนะนำทีละขั้นว่าต้องกดอะไรบ้าง

**Blocked by:** 02 (Login + wallet) · และ credential จากเจ้าของโปรเจกต์

**Status:** ready-for-agent

- [ ] login ด้วย Google สำเร็จแล้วเห็นยอดเหรียญของบัญชีตัวเองได้
- [ ] บัญชีที่สมัครด้วย Google มี `account` + `wallet` เกิดขึ้นเองเหมือนทาง email
- [ ] logout แล้ว login ด้วย Google ใหม่ ได้บัญชีเดิม (ไม่เกิดบัญชีซ้ำ)
- [ ] การเพิ่มทางนี้ไม่ต้องแก้ DB สักบรรทัด (พิสูจน์ว่า seam ที่วางไว้ถูก)
- [ ] เอกสารบอกขั้นตอนตั้งค่าฝั่ง Google Cloud + Supabase ไว้ให้ทำซ้ำได้
