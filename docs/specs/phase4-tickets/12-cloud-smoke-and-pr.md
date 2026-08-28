# 12: Smoke test บน cloud + เปิด PR

**What to build:** สลับไปที่ Supabase cloud แล้วเดินครบทั้งสองลูปจากแอปจริง:
หมอดูผูกบัญชี → แอดมินตรวจ → รับงาน → ถอนเงินออก · และ ผู้ใช้โทร → หมอดูรับ →
คุยกัน → ต่อเวลา → วางสาย → เงินถึงหมอดู · แล้วเปิด PR เข้า `main`

**Blocked by:** 04 (ปิดวงจร payout), 11 (จบสาย)

**Status:** ready-for-agent

- [ ] `git fetch origin && git pull` ก่อน ทำงานบน branch ของเฟสนี้ — ห้าม push เข้า `main` ตรง ๆ
- [ ] migration ที่เพิ่มในเฟสนี้ push ขึ้น cloud แล้วและ sync ครบ
- [ ] เดินครบลูป payout บน cloud พร้อมหลักฐานยอดก่อน/หลัง และเลขอ้างอิงการโอน
- [ ] เดินครบลูป call บน cloud ด้วยเครื่องจริงสองเครื่อง พร้อมหลักฐานยอดก่อน/หลัง
- [ ] ยืนยันว่าโควตา LiveKit ที่ใช้อยู่ยังไม่เกิน free tier
- [ ] เทส SQL ทุกชุดยังผ่านหมด ไม่มี WARNING/ERROR
- [ ] เทส REST และ iOS ผ่านทั้งบน local และ cloud
- [ ] PR description ภาษาอังกฤษ อธิบายว่าทำไม payout ต้องมาก่อน call
