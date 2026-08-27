-- =============================================================================
-- Chata — regression test: cron lifecycle jobs (เฟส 2)
--
-- พิสูจน์ว่าเหรียญที่ถูก escrow ไว้ไม่ค้างตลอดกาล:
--   submitted เกินกำหนด → คืน user | active เกินอายุ → จ่าย seer
--   และของที่ยังไม่ถึงกำหนด ต้องไม่ถูกแตะ
--
-- วิธีรัน:
--   supabase db reset
--   docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
--     -f - < db/tests/lifecycle-jobs.test.sql
--
-- ผ่าน = ทุกบรรทัด "ผลลัพธ์" ตรงกับ "คาดหวัง" และ INVARIANT คืน 0 rows
-- ห้ามรันกับฐานข้อมูลที่มีข้อมูลจริง
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------- setup ----
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'user@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ลูกค้าทดสอบ"}'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'seer@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"หมอดูทดสอบ"}');

update public.account set role='seer' where id='22222222-2222-2222-2222-222222222222';
insert into public.seer_profile (account_id, display_name, approval_status, is_active, accepts_question)
values ('22222222-2222-2222-2222-222222222222','หมอดูทดสอบ','approved',true,true);
insert into public.seer_service (seer_id, service_type_code, price_coin, is_enabled)
values ('22222222-2222-2222-2222-222222222222','chat_question',100,true);

-- เติม 650+80 = 730 เหรียญ พอซื้อ 3 คำถาม
insert into public.payment_order (id,user_id,coin_package_id,method,psp_code,status,coin_amount,bonus_coin,price_minor,expires_at)
select '33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
       cp.id,'apple_iap','apple','verified',cp.coin_amount,cp.bonus_coin,79900,now()+interval '1 hour'
from public.coin_package cp where cp.code='coin_650';

select public.internal_credit_payment('33333333-3333-3333-3333-333333333333','apple-txn-0001',
  '{"store_product_id":"app.chata.coin650","provider_transaction_id":"apple-txn-0001","purchase_token_hash_hex":"deadbeef"}'::jsonb) as setup_credit;

\echo '--- ยอดเริ่มต้น (คาดหวัง available 730 / reserved 0) ---'
select available_coin, reserved_coin from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

-- ซื้อ 3 คำถาม คำถามละ 100
do $$
declare i int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  for i in 1..3 loop
    perform public.submit_question((select id from public.seer_service limit 1),
      format('คำถามที่ %s', i), gen_random_uuid(), gen_random_uuid());
  end loop;
end $$;
reset role;

\echo '--- หลังซื้อ 3 คำถาม (คาดหวัง available 430 / reserved 300) ---'
select available_coin, reserved_coin from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

-- จัดฉาก: A = submitted ค้าง 48 ชม. | B = active ค้าง 100 ชม. | C = submitted เพิ่งสร้าง
create temp table t_q as
select id, row_number() over (order by created_at) rn from public.question;

update public.question set created_at = now() - interval '48 hours'
where id = (select id from t_q where rn = 1);

update public.question set status = 'active', created_at = now() - interval '100 hours'
where id = (select id from t_q where rn = 2);
-- rn = 3 ปล่อยไว้ใหม่เอี่ยม

-- ------------------------------------------------------------ job run ----
\echo '======== JOB 1: คืนเงินคำถามที่ seer ไม่ตอบ ========'
select public.job_refund_unanswered_questions();

\echo '======== JOB 2: ตัดจบคำถามที่ค้างเกินอายุ ========'
select public.job_autoclose_stale_questions();

\echo '--- สถานะคำถามทั้ง 3 (คาดหวัง: cancelled_refunded / completed / submitted) ---'
select t.rn, q.status, q.cancel_reason, q.completed_at is not null as มี_completed_at
from public.question q join t_q t on t.id = q.id order by t.rn;

\echo '--- ยอด user (คาดหวัง available 530 = 430+100คืน / reserved 100 = เหลือ C) ---'
select available_coin, reserved_coin from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

\echo '--- ยอด seer (คาดหวัง payable 70 จากคำถาม B) ---'
select payable_coin from public.wallet where account_id='22222222-2222-2222-2222-222222222222';

\echo '======== IDEMPOTENT: รัน job ซ้ำ ต้องไม่มีอะไรเปลี่ยน ========'
select public.job_refund_unanswered_questions();
select public.job_autoclose_stale_questions();
\echo '--- ยอดหลังรันซ้ำ (ต้องเท่าเดิม 530/100 และ payable 70) ---'
select w.available_coin, w.reserved_coin, w.payable_coin, a.role
from public.wallet w join public.account a on a.id = w.account_id order by a.role;

\echo '======== JOB 3: ปิดออเดอร์เติมเงินที่หมดอายุ ========'
insert into public.payment_order (user_id,coin_package_id,method,psp_code,status,coin_amount,bonus_coin,price_minor,expires_at)
select '11111111-1111-1111-1111-111111111111', cp.id,'apple_iap','apple','created',
       cp.coin_amount,cp.bonus_coin,17900, now() - interval '2 hours'
from public.coin_package cp where cp.code='coin_150';
select public.job_expire_payment_orders();
\echo '--- คาดหวัง: มี 1 order เป็น expired และ order ที่ credited แล้วต้องไม่ถูกแตะ ---'
select status, count(*) from public.payment_order group by status order by status;

\echo '======== JOB 4: reconcile (คาดหวัง drift 0, ledger_sum 0) ========'
select public.job_reconcile_wallets();

\echo '======== INVARIANT: wallet ตรงกับ ledger ทุกคอลัมน์ (ต้องว่าง) ========'
with led as (
  select account_id,
         coalesce(sum(amount) filter (where ledger_account='user_available'),0) av,
         coalesce(sum(amount) filter (where ledger_account='user_reserved'),0)  rs,
         coalesce(sum(amount) filter (where ledger_account='seer_payable'),0)   pa
  from public.ledger_entry where account_id is not null group by 1
)
select w.account_id, w.available_coin, l.av, w.reserved_coin, l.rs, w.payable_coin, l.pa
from public.wallet w left join led l on l.account_id=w.account_id
where w.available_coin <> coalesce(l.av,0)
   or w.reserved_coin  <> coalesce(l.rs,0)
   or w.payable_coin   <> coalesce(l.pa,0);

\echo '======== INVARIANT: ทุก transaction รวมเป็นศูนย์ (ต้องว่าง) ========'
select t.operation, sum(e.amount) from public.ledger_transaction t
join public.ledger_entry e on e.transaction_id=t.id group by 1 having sum(e.amount) <> 0;

\echo '======== INVARIANT: ไม่มี drift/violation ถูกบันทึกใน audit_log (ต้องว่าง) ========'
select action, count(*) from public.audit_log
where action in ('wallet_ledger_drift','ledger_zero_sum_violation',
                 'job_refund_unanswered_failed','job_autoclose_failed')
group by 1;

\echo '======== cron job ที่ตั้งไว้ (คาดหวัง 4 ตัว active) ========'
select jobname, schedule, active from cron.job where jobname like 'chata\_%' order by jobname;
