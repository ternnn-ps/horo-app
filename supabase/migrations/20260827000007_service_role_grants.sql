-- =============================================================================
-- Chata — คืนสิทธิ์ EXECUTE ให้ service_role
--
-- บั๊กที่เจอตอนยิง Edge Function จริงครั้งแรก:
--   `revoke all on function ... from public` ตัดสิทธิ์ของ **service_role ไปด้วย**
--   เพราะ Postgres ให้ EXECUTE กับ PUBLIC เป็นค่าเริ่มต้น และ service_role
--   อาศัยสิทธิ์ก้อนนั้นอยู่ พอ revoke จาก public มันจึงหลุดไปพร้อมกัน
--
--   ที่ผ่านมาไม่มีอาการ เพราะ internal_* ถูกเรียกจากใน SECURITY DEFINER ตัวอื่น
--   (ซึ่งรันในนามเจ้าของ function) และเทสต์ทั้งหมดรันเป็น postgres = เจ้าของ
--   อาการโผล่ครั้งแรกตอน Edge Function เรียกผ่าน PostgREST ด้วย service key จริง
--
-- บทเรียน: การทดสอบด้วยสิทธิ์เจ้าของฐานข้อมูล พิสูจน์เรื่องสิทธิ์ไม่ได้เลย
--
-- ไฟล์นี้ระบุให้ชัดว่า "โค้ดฝั่ง server ที่เชื่อถือได้" เรียกอะไรได้บ้าง
-- ไม่ใช้ `grant to public` เพื่อให้ anon/authenticated ยังถูกกันอยู่เหมือนเดิม
-- =============================================================================

-- ---- เงิน: เรียกจาก Edge Function (verify-iap, payment webhook ในอนาคต) ----
grant execute on function public.internal_credit_iap(uuid, text, text, text, text, jsonb)
  to service_role;
grant execute on function public.internal_credit_payment(uuid, text, jsonb)
  to service_role;
grant execute on function public.internal_fail_payment(uuid, text)
  to service_role;

-- ---- วงจรชีวิตงาน: เรียกจาก worker/ops เมื่อจำเป็นต้องแทรกแซงมือ ----
grant execute on function public.internal_refund_question(uuid, text) to service_role;
grant execute on function public.internal_settle_question(uuid, boolean) to service_role;

-- ---- งานตามเวลา: ปกติ pg_cron เรียกในนาม postgres อยู่แล้ว
--      grant เพิ่มเพื่อให้สั่งรันเองได้ตอนแก้ปัญหาหน้างาน ----
grant execute on function public.job_refund_unanswered_questions(int) to service_role;
grant execute on function public.job_autoclose_stale_questions(int)  to service_role;
grant execute on function public.job_expire_payment_orders(int)      to service_role;
grant execute on function public.job_reconcile_wallets()             to service_role;
grant execute on function public.job_purge_rate_limit_counters(int)  to service_role;

-- ---- ฝั่งอนุมัติหมอดู: วันนี้ใช้ผ่าน Studio (postgres) แต่พอมี admin console
--      จะเรียกผ่าน Edge Function ด้วย service key ต้องมีสิทธิ์ไว้ก่อน ----
grant execute on function public.admin_review_seer_application(uuid, boolean, text, text)
  to service_role;
grant execute on function public.admin_review_seer_document(uuid, boolean, text, text)
  to service_role;

-- ---- เครื่องมือ dev (ตัวมันเองกันตัวเองด้วย payment.iap_mode อีกชั้น) ----
grant execute on function public.dev_grant_coins(uuid, bigint, text) to service_role;

-- ยืนยันว่ายังไม่มีอะไรหลุดถึง client: ตัวที่ห้ามให้ client แตะยังถูก revoke ไว้
-- จากไฟล์ก่อนหน้าทั้งหมด (anon/authenticated ไม่ได้ถูกแตะในไฟล์นี้เลย)
