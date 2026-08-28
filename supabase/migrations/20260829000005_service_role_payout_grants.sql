-- =============================================================================
-- คืนสิทธิ์ EXECUTE ของ RPC ฝั่งแอดมินให้ service_role
--
-- เหตุผลเดียวกับ 20260827000007: `revoke all on function ... from public`
-- ตัดสิทธิ์ของ service_role ไปด้วย เพราะ Postgres ให้ EXECUTE กับ PUBLIC เป็นค่าเริ่มต้น
--
-- ที่ต้องมีตอนนี้: fixture ต้องตั้งบัญชีรับเงินให้อยู่ในสถานะ "ตรวจแล้ว" ทุกครั้ง
-- ไม่งั้นชุดเทสที่ต้องใช้บัญชีที่ผ่านการตรวจจะเข้าขาสำรองถาวร แล้วขาที่ควรทดสอบจริง
-- ไม่เคยถูกเดินเลย (เจอมาแล้วกับเทสยกเลิกคำขอถอน)
-- =============================================================================

grant execute on function public.admin_review_payout_account(uuid, boolean, text, text) to service_role;
grant execute on function public.admin_reveal_payout_account(uuid, text)                to service_role;
grant execute on function public.admin_review_payout(uuid, text, text, text, text)      to service_role;
grant execute on function public.admin_payout_queue(int)                                to service_role;

-- fixture ต้องสร้าง "รายได้ที่สุกแล้ว" ให้หมอดูทดสอบได้ ไม่งั้นชุดเทสเรื่องการถอน
-- ต้องไปพึ่งผลข้างเคียงของชุดอื่นที่รันก่อนหน้า ซึ่งเปราะและอธิบายยาก
grant execute on function
  public.internal_post_ledger(text, text, text, jsonb, uuid, text) to service_role;
grant insert, select on public.seer_earning to service_role;
