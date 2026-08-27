-- =============================================================================
-- Chata — regression test: เส้นทางเติมเหรียญ IAP + เครื่องมือ dev
--
-- ครอบ: สร้าง order+credit ใน txn เดียว · idempotent ที่ transaction id ·
--        product ปลอมถูกปฏิเสธ · dev_grant_coins ปิดตัวเองเมื่อไม่ใช่โหมด dev ·
--        client เรียก RPC ฝั่ง server ไม่ได้
--
-- วิธีรัน:
--   supabase db reset
--   docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
--     -f - < db/tests/iap-credit.test.sql
--
-- ผ่าน = ไม่มีบรรทัด WARNING/ERROR
-- =============================================================================

\set ON_ERROR_STOP on
\set U '11111111-1111-1111-1111-111111111111'

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values (:'U','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
        'buyer@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ลูกค้า"}');

create or replace function pg_temp.chk(p_label text, p_ok boolean, p_extra text default '')
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok  %  %', p_label, p_extra;
  else raise warning '!! %  %', p_label, p_extra; end if;
end $$;

\echo '████ 1: เติมเหรียญจากใบเสร็จ (สร้าง order + credit ใน txn เดียว) ████'
do $$
declare v jsonb; n_order int;
begin
  v := public.internal_credit_iap(
    '11111111-1111-1111-1111-111111111111','apple_iap','app.chata.coin150',
    'txn-0001','deadbeef01', '{"env":"local"}'::jsonb);
  perform pg_temp.chk('เติมสำเร็จ 160 (150+bonus 10)', (v->>'coin_credited')::int = 160, v::text);
  perform pg_temp.chk('ยอดในกระเป๋าตรง',
    (select available_coin from public.wallet
      where account_id='11111111-1111-1111-1111-111111111111') = 160);
  select count(*) into n_order from public.payment_order;
  perform pg_temp.chk('สร้าง order 1 ใบ สถานะ credited',
    n_order = 1 and exists(select 1 from public.payment_order where status='credited'));
  perform pg_temp.chk('มีใบเสร็จผูกกับ order',
    (select count(*) from public.iap_receipt) = 1);
end $$;

\echo '████ 2: ใบเสร็จเดิมยิงซ้ำ → ต้องไม่สร้าง order ใหม่และไม่เพิ่มเหรียญ ████'
do $$
declare v jsonb; n_order int; n_ledger int;
begin
  select count(*) into n_ledger from public.ledger_transaction;
  v := public.internal_credit_iap(
    '11111111-1111-1111-1111-111111111111','apple_iap','app.chata.coin150',
    'txn-0001','deadbeef01');
  perform pg_temp.chk('คืน already_credited', (v->>'already_credited')::boolean, v::text);
  select count(*) into n_order from public.payment_order;
  perform pg_temp.chk('order ยังมีใบเดียว (ไม่มีขยะค้าง)', n_order = 1, n_order::text);
  perform pg_temp.chk('ledger ไม่เพิ่ม',
    (select count(*) from public.ledger_transaction) = n_ledger);
  perform pg_temp.chk('ยอดยังเป็น 160',
    (select available_coin from public.wallet
      where account_id='11111111-1111-1111-1111-111111111111') = 160);
end $$;

\echo '████ 3: product id ที่ไม่มีในระบบ → ปฏิเสธและไม่ทิ้ง order ขยะ ████'
do $$
declare n_order int;
begin
  begin
    perform public.internal_credit_iap(
      '11111111-1111-1111-1111-111111111111','apple_iap','app.chata.NOPE',
      'txn-0002','deadbeef02');
    raise warning '!! product ที่ไม่มีในระบบผ่านได้';
  exception when others then
    perform pg_temp.chk('ปฏิเสธ product ที่ไม่รู้จัก', sqlerrm like 'unknown_product%', sqlerrm);
  end;
  select count(*) into n_order from public.payment_order;
  perform pg_temp.chk('ไม่มี order ขยะเหลือ', n_order = 1, n_order::text);
end $$;

\echo '████ 4: token hash ซ้ำแต่คนละ transaction id → ต้องถูกกัน ████'
do $$
begin
  begin
    perform public.internal_credit_iap(
      '11111111-1111-1111-1111-111111111111','apple_iap','app.chata.coin150',
      'txn-0003','deadbeef01');   -- hash เดิม
    raise warning '!! ใบเสร็จ token เดิมใช้ซ้ำได้ = เติมเหรียญฟรีไม่จำกัด';
  exception when others then
    perform pg_temp.chk('token ซ้ำถูกกันด้วย unique constraint', true, sqlerrm);
  end;
  perform pg_temp.chk('ยอดยังเป็น 160',
    (select available_coin from public.wallet
      where account_id='11111111-1111-1111-1111-111111111111') = 160);
end $$;

\echo '████ 5: dev_grant_coins ทำงานเฉพาะโหมด local_test ████'
do $$
declare v jsonb; v_detail text;
begin
  v := public.dev_grant_coins('11111111-1111-1111-1111-111111111111', 500, 'ทดสอบ');
  perform pg_temp.chk('โหมด local_test เติมได้', (v->>'coin_granted')::int = 500, v::text);
  perform pg_temp.chk('ยอดเป็น 660', (select available_coin from public.wallet
      where account_id='11111111-1111-1111-1111-111111111111') = 660);
  perform pg_temp.chk('มี audit_log',
    exists(select 1 from public.audit_log where action='dev.coins_granted'));

  -- สลับเป็นโหมดจริง แล้วต้องปิดตัวเองทันที
  update public.app_config set value='"production"'::jsonb where key='payment.iap_mode';
  begin
    perform public.dev_grant_coins('11111111-1111-1111-1111-111111111111', 999);
    raise warning '!! ช่องโหว่ร้ายแรง: เติมเหรียญฟรีได้ในโหมด production';
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.chk('โหมด production ปิดตัวเอง', sqlerrm='dev_grant_disabled', v_detail);
  end;
  update public.app_config set value='"local_test"'::jsonb where key='payment.iap_mode';
end $$;

\echo '████ 6: client เรียก RPC ฝั่ง server ไม่ได้ ████'
do $$
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  begin
    perform public.internal_credit_iap(
      '11111111-1111-1111-1111-111111111111','apple_iap','app.chata.coin650','x','y');
    raise warning '!! ผู้ใช้เติมเหรียญให้ตัวเองได้';
  exception when others then
    perform pg_temp.chk('เรียก internal_credit_iap ไม่ได้', true, sqlerrm);
  end;
  begin
    perform public.dev_grant_coins('11111111-1111-1111-1111-111111111111', 999);
    raise warning '!! ผู้ใช้เรียก dev_grant_coins ได้';
  exception when others then
    perform pg_temp.chk('เรียก dev_grant_coins ไม่ได้', true, sqlerrm);
  end;
  perform set_config('role','postgres',true);
end $$;

\echo '████ INVARIANT ████'
select public.job_reconcile_wallets() as reconcile;

\echo '--- wallet ตรงกับ ledger (ต้องว่าง) ---'
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

\echo '--- ทุก transaction รวมเป็นศูนย์ (ต้องว่าง) ---'
select t.operation, sum(e.amount) from public.ledger_transaction t
join public.ledger_entry e on e.transaction_id=t.id group by 1 having sum(e.amount) <> 0;
