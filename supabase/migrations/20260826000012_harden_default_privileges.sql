-- =============================================================================
-- Chata phase 1 — ปิดช่อง default privilege ที่หลงเหลือ
--
-- ปัญหาที่พบตอน audit local DB:
--   pg_default_acl ยังมีรายการที่ให้ anon/authenticated ได้ Dxtm
--   (TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) กับ "ทุกตาราง/view ที่ postgres
--   สร้างใหม่ใน schema public" — เห็นผลจริงที่ v_my_wallet / v_my_coin_history /
--   v_my_payment_history ซึ่งถูกสร้างหลังไฟล์ grants จึงติดสิทธิ์ชุดนี้มา
--
-- ทำไมต้องแก้: RLS **ไม่กัน TRUNCATE** — policy ไม่มีผลกับคำสั่งนี้เลย
--   ตอนนี้ยังใช้โจมตีผ่าน Data API ไม่ได้ (PostgREST ไม่ expose TRUNCATE)
--   แต่เป็นสิทธิ์ที่ไม่มีเหตุผลต้องมี และตารางใหม่ทุกตัวในเฟส 2-3 จะติดมาด้วย
--   ถือเป็น defense in depth: ตัดที่ต้นทางดีกว่าไล่ revoke รายตารางตลอดไป
-- =============================================================================

-- ต้นทาง: ตัด default privilege ของ role ที่สร้าง object (postgres และ supabase_admin)
-- เพื่อให้ตาราง/view/sequence/function ที่สร้างใหม่ "ไม่ได้อะไรเลย" โดยอัตโนมัติ
-- ต่อจากนี้ทุกสิทธิ์ต้อง grant ตรง ๆ ในไฟล์ migration เท่านั้น
alter default privileges in schema public
  revoke all on tables from anon, authenticated;
alter default privileges in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges in schema public
  revoke all on functions from anon, authenticated;

-- ปลายทาง: เก็บกวาดของที่หลุดมาแล้ว (view 3 ตัวจากไฟล์ 000010)
revoke all on public.v_my_wallet          from anon, authenticated;
revoke all on public.v_my_coin_history    from anon, authenticated;
revoke all on public.v_my_payment_history from anon, authenticated;

-- แล้วคืนเฉพาะสิทธิ์ที่ต้องการจริง: เจ้าของบัญชีอ่าน view ของตัวเอง
-- (view เป็น security_invoker → RLS ของตารางต้นทางยังทำงาน + view กรอง auth.uid() ซ้ำ)
grant select on public.v_my_wallet          to authenticated;
grant select on public.v_my_coin_history    to authenticated;
grant select on public.v_my_payment_history to authenticated;

-- anon ไม่ได้อะไรจาก view เหล่านี้ — ยังไม่ login ไม่มีกระเป๋าเงินให้ดู

comment on view public.v_my_wallet is
  'ยอด coin ของผู้ใช้ที่ login อยู่ — ทางเดียวที่ client อ่านยอดเงินได้ (ตาราง wallet เป็น deny-all)';
