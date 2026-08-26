-- =============================================================================
-- Chata — regression test: money flow ครบวงจร + invariant ของบัญชี
--
-- วิธีรัน (ต้อง reset ก่อนเสมอ เพราะ test สร้าง user ด้วย uuid คงที่):
--   supabase db reset
--   docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
--     -f - < db/tests/money-flow.test.sql
--
-- ผ่าน = ทุกบล็อก INVARIANT คืน 0 rows และทุก NEGATIVE ขึ้น "ปฏิเสธถูกต้อง"
-- ห้ามรันกับฐานข้อมูลที่มีข้อมูลจริง
-- =============================================================================

\set ON_ERROR_STOP on
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

insert into public.payment_order (id,user_id,coin_package_id,method,psp_code,status,coin_amount,bonus_coin,price_minor,expires_at)
select '33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
       cp.id,'apple_iap','apple','verified',cp.coin_amount,cp.bonus_coin,17900,now()+interval '1 hour'
from public.coin_package cp where cp.code='coin_150';

\echo '######## NEGATIVE 1: credit โดยไม่มี receipt (ต้องถูกปฏิเสธ) ########'
do $$ begin
  perform public.internal_credit_payment('33333333-3333-3333-3333-333333333333','ref',null);
  raise warning '!! ช่องโหว่: credit ผ่านทั้งที่ไม่มี receipt';
exception when others then raise notice 'ปฏิเสธถูกต้อง: %', sqlerrm; end $$;

\echo '######## NEGATIVE 2: receipt product id ผิดแพ็ก (ต้องถูกปฏิเสธ) ########'
do $$ begin
  perform public.internal_credit_payment('33333333-3333-3333-3333-333333333333','ref',
    '{"store_product_id":"app.chata.coin050","provider_transaction_id":"t1","purchase_token_hash_hex":"aabb"}'::jsonb);
  raise warning '!! ช่องโหว่: ใบเสร็จแพ็ก 50 credit เป็นแพ็ก 150 ได้';
exception when others then raise notice 'ปฏิเสธถูกต้อง: %', sqlerrm; end $$;

\echo '######## POSITIVE: receipt ถูกต้อง ########'
select public.internal_credit_payment('33333333-3333-3333-3333-333333333333','apple-txn-0001',
  '{"store_product_id":"app.chata.coin150","provider_transaction_id":"apple-txn-0001","purchase_token_hash_hex":"deadbeef"}'::jsonb) as r;

\echo '--- ยอดหลังเติม (ควร 160 = 150 + bonus 10) ---'
select available_coin, reserved_coin from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

\echo '######## REPLAY: เรียกซ้ำ order เดิม (ต้อง idempotent ไม่เพิ่มเหรียญ) ########'
select public.internal_credit_payment('33333333-3333-3333-3333-333333333333','apple-txn-0001',
  '{"store_product_id":"app.chata.coin150","provider_transaction_id":"apple-txn-0001","purchase_token_hash_hex":"deadbeef"}'::jsonb) as r;
select available_coin as ยอดหลัง_replay from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

\set ON_ERROR_STOP on
\echo '######## ซื้อคำถาม 100 เหรียญ (ในนาม user) ########'
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select public.submit_question((select id from public.seer_service limit 1),
    'ช่วงนี้การงานจะเป็นยังไงคะ', gen_random_uuid(), gen_random_uuid()) as r;
commit;
\echo '--- ควรเป็น available 60 / reserved 100 ---'
select available_coin, reserved_coin from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

update public.question set status='active';

\echo '######## seer ขอปิดงาน ########'
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select public.request_close_question((select id from public.question limit 1)) as r;
commit;

\echo '######## user กดยอมรับ → settle ########'
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select public.respond_close_question((select id from public.question limit 1), true) as r;
commit;

\echo '======== ยอดสุดท้าย ========'
select a.role, w.available_coin, w.reserved_coin
from public.wallet w join public.account a on a.id=w.account_id order by a.role;

\echo '======== รายการบัญชีทั้งหมด ========'
select t.operation, e.ledger_account, e.amount from public.ledger_transaction t
join public.ledger_entry e on e.transaction_id=t.id order by t.created_at, e.amount desc;

\echo '======== INVARIANT 1: ทุก transaction รวมเป็นศูนย์ (ต้องว่าง) ========'
select t.operation, sum(e.amount) from public.ledger_transaction t
join public.ledger_entry e on e.transaction_id=t.id group by 1 having sum(e.amount)<>0;

\echo '======== INVARIANT 2: wallet ทุกคอลัมน์ตรงกับ ledger (ต้องว่าง) ========'
-- หมายเหตุ: ledger_account แต่ละตัว map กับคนละคอลัมน์ใน wallet
--   user_available -> available_coin | user_reserved -> reserved_coin | seer_payable -> payable_coin
with led as (
  select account_id,
         sum(amount) filter (where ledger_account='user_available') av,
         sum(amount) filter (where ledger_account='user_reserved')  rs,
         sum(amount) filter (where ledger_account='seer_payable')   pa
  from public.ledger_entry where account_id is not null group by 1
)
select w.account_id,
       w.available_coin, coalesce(l.av,0) as ledger_available,
       w.reserved_coin,  coalesce(l.rs,0) as ledger_reserved,
       w.payable_coin,   coalesce(l.pa,0) as ledger_payable
from public.wallet w left join led l on l.account_id=w.account_id
where w.available_coin <> coalesce(l.av,0)
   or w.reserved_coin  <> coalesce(l.rs,0)
   or w.payable_coin   <> coalesce(l.pa,0);

\echo '======== INVARIANT 2b: balance_after ต้องมีทุกแถวที่มีเจ้าของ (ต้องเป็น 0) ========'
select count(*) as ขาด_balance_after from public.ledger_entry
where account_id is not null and balance_after is null;

\echo '======== INVARIANT 3: ระบบทั้งระบบรวมเป็นศูนย์ ========'
select sum(amount) as ยอดรวมทุกบัญชี from public.ledger_entry;

\echo '======== INVARIANT 4: append-only — ลองแก้ ledger (ต้องถูกบล็อก) ========'
do $$ begin
  update public.ledger_entry set amount = 999999;
  raise warning '!! ช่องโหว่: แก้ ledger ได้';
exception when others then raise notice 'บล็อกถูกต้อง: %', sqlerrm; end $$;

\echo '======== INVARIANT 5: ยอดติดลบ — ลองซื้อเกินเงินที่มี (ต้องถูกปฏิเสธ) ========'
do $$ begin
  begin
    perform set_config('role','authenticated',true);
    perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
    perform public.submit_question((select id from public.seer_service limit 1),
      'ถามอีกรอบทั้งที่เงินไม่พอ', gen_random_uuid(), gen_random_uuid());
    raise warning '!! ช่องโหว่: ซื้อได้ทั้งที่เงินไม่พอ';
  exception when others then raise notice 'ปฏิเสธถูกต้อง: %', sqlerrm;
  end;
end $$;
