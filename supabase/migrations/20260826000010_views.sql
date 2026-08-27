-- =============================================================================
-- Chata phase 1 — views สำหรับอ่านข้อมูลที่ตารางฐานเป็น deny-all
--
-- ทุก view เป็น SECURITY DEFINER view (security_invoker = false — ค่า default ของ
-- Postgres, ประกาศชัดเพื่อกันเข้าใจผิด) + security_barrier และ**กรอง auth.uid()
-- ในตัว view เอง**เป็น predicate แรกเสมอ (spec §7.3 ข้อ 3)
-- เหตุที่ใช้ definer: ตารางฐาน (wallet, ledger, payment_order) deny-all —
-- invoker view จะอ่านไม่ได้เลย
-- =============================================================================

-- ------------------------------------------------------------ v_my_wallet ----
create view public.v_my_wallet
with (security_invoker = false, security_barrier = true) as
select
  w.account_id,
  w.available_coin,
  w.reserved_coin,
  w.payable_coin,
  w.updated_at
from public.wallet w
where w.account_id = (select auth.uid());

comment on view public.v_my_wallet is 'balance ของฉัน (definer view ครอบ wallet ที่ deny-all)';

-- ------------------------------------------------------ v_my_coin_history ----
create view public.v_my_coin_history
with (security_invoker = false, security_barrier = true) as
select
  e.id,
  e.ledger_account,
  e.amount,
  e.balance_after,
  t.reference_type,
  t.reference_id,
  t.operation,
  e.created_at
from public.ledger_entry e
join public.ledger_transaction t on t.id = e.transaction_id
where e.account_id = (select auth.uid());

comment on view public.v_my_coin_history is
  'ประวัติ coin ของฉันจาก ledger — client เรียงด้วย order=id.desc + keyset (id=lt.cursor)';

-- -------------------------------------------------- v_my_payment_history ----
create view public.v_my_payment_history
with (security_invoker = false, security_barrier = true) as
select
  o.id,
  o.method,
  o.status,
  o.coin_amount,
  o.bonus_coin,
  o.price_minor,
  o.currency,
  o.failure_reason,
  o.created_at,
  o.credited_at
from public.payment_order o
where o.user_id = (select auth.uid());

comment on view public.v_my_payment_history is 'ประวัติการเติมเงินของฉัน (ไม่เปิด psp_reference/psp_code)';

-- ---------------------------------------------------------------- grants ----
grant select on public.v_my_wallet          to authenticated;
grant select on public.v_my_coin_history    to authenticated;
grant select on public.v_my_payment_history to authenticated;
