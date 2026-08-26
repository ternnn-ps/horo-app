-- =============================================================================
-- Chata — regression test: block user (เฟส 2 ส่วนที่ 3)
--
-- หัวใจคือกฎ "blocker forfeits" — ฝ่ายที่กดบล็อกเป็นฝ่ายเสียเสมอ
-- ทุกเคสตรวจยอดเหรียญเป๊ะ ๆ เพราะนี่คือจุดที่คนจะพยายามโกง
--
-- วิธีรัน:
--   supabase db reset
--   docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
--     -f - < db/tests/block.test.sql
--
-- ผ่าน = ไม่มีบรรทัด WARNING/ERROR และ INVARIANT คืน 0 rows
-- ห้ามรันกับฐานข้อมูลที่มีข้อมูลจริง
-- =============================================================================

\set ON_ERROR_STOP on
\set U '11111111-1111-1111-1111-111111111111'
\set S '22222222-2222-2222-2222-222222222222'

-- ---------------------------------------------------------------- setup ----
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
 (:'U','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'user@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ลูกค้า"}'),
 (:'S','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'seer@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"หมอดู"}');

update public.account set role='seer' where id=:'S';
insert into public.seer_profile (account_id, display_name, approval_status, is_active, accepts_question)
values (:'S','หมอดูทดสอบ','approved',true,true);
insert into public.seer_service (seer_id, service_type_code, price_coin, is_enabled)
values (:'S','chat_question',100,true);

insert into public.payment_order (id,user_id,coin_package_id,method,psp_code,status,coin_amount,bonus_coin,price_minor,expires_at)
select '33333333-3333-3333-3333-333333333333',:'U',cp.id,'apple_iap','apple','verified',
       cp.coin_amount,cp.bonus_coin,79900,now()+interval '1 hour'
from public.coin_package cp where cp.code='coin_650';
select public.internal_credit_payment('33333333-3333-3333-3333-333333333333','t1',
  '{"store_product_id":"app.chata.coin650","provider_transaction_id":"t1","purchase_token_hash_hex":"aa01"}'::jsonb) as setup;

-- helper: ซื้อคำถามในนาม user แล้วคืน id
create or replace function pg_temp.buy_question(p_active boolean default false)
returns uuid language plpgsql as $$
declare v_id uuid; v_res jsonb;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  v_res := public.submit_question((select id from public.seer_service limit 1),
             'คำถามทดสอบ', gen_random_uuid(), gen_random_uuid());
  perform set_config('role','postgres',true);
  v_id := (v_res ->> 'question_id')::uuid;
  if p_active then
    update public.question set status='active' where id=v_id;
  end if;
  return v_id;
end $$;

-- helper: กดบล็อกในนามใครก็ได้
create or replace function pg_temp.act_block(p_actor uuid, p_target uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', p_actor), true);
  v := public.block_account(p_target);
  perform set_config('role','postgres',true);
  return v;
end $$;

create or replace function pg_temp.act_unblock(p_actor uuid, p_target uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', p_actor), true);
  v := public.unblock_account(p_target);
  perform set_config('role','postgres',true);
  return v;
end $$;

create or replace function pg_temp.chk(p_label text, p_got bigint, p_want bigint)
returns void language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise warning '!! % : ได้ % ควรได้ %', p_label, p_got, p_want;
  else
    raise notice 'ok  % = %', p_label, p_got;
  end if;
end $$;

\echo '████ เคส 1: seer บล็อก ขณะยังไม่ตอบ (submitted) → คืนเงินผู้ถาม ████'
do $$
declare q uuid; av bigint; rs bigint; pa bigint;
begin
  q := pg_temp.buy_question(false);
  perform pg_temp.act_block('22222222-2222-2222-2222-222222222222'::uuid,
                            '11111111-1111-1111-1111-111111111111'::uuid);
  select available_coin, reserved_coin into av, rs from public.wallet
   where account_id='11111111-1111-1111-1111-111111111111';
  select payable_coin into pa from public.wallet
   where account_id='22222222-2222-2222-2222-222222222222';
  perform pg_temp.chk('ผู้ถาม available (คืนครบ)', av, 730);
  perform pg_temp.chk('ผู้ถาม reserved', rs, 0);
  perform pg_temp.chk('หมอดู payable (ต้องไม่ได้อะไร)', pa, 0);
  if (select status from public.question where id=q) <> 'cancelled_refunded'
     or (select cancel_reason from public.question where id=q) <> 'blocked' then
    raise warning '!! สถานะ/เหตุผลไม่ถูก';
  else raise notice 'ok  question = cancelled_refunded reason=blocked'; end if;
  perform pg_temp.act_unblock('22222222-2222-2222-2222-222222222222'::uuid,
                              '11111111-1111-1111-1111-111111111111'::uuid);
end $$;

\echo '████ เคส 2: seer บล็อก "หลังตอบแล้ว" (active) → ยังต้องคืนผู้ถาม (ฟาร์มเงินไม่ได้) ████'
do $$
declare q uuid; av bigint; pa bigint;
begin
  q := pg_temp.buy_question(true);
  perform pg_temp.act_block('22222222-2222-2222-2222-222222222222'::uuid,
                            '11111111-1111-1111-1111-111111111111'::uuid);
  select available_coin into av from public.wallet
   where account_id='11111111-1111-1111-1111-111111111111';
  select payable_coin into pa from public.wallet
   where account_id='22222222-2222-2222-2222-222222222222';
  perform pg_temp.chk('ผู้ถาม available (คืนครบ)', av, 730);
  perform pg_temp.chk('หมอดู payable (ตอบแล้วแต่กดบล็อกเอง = ได้ 0)', pa, 0);
  perform pg_temp.act_unblock('22222222-2222-2222-2222-222222222222'::uuid,
                              '11111111-1111-1111-1111-111111111111'::uuid);
end $$;

\echo '████ เคส 3: user บล็อก หลังได้คำตอบ (active) → จ่ายหมอดู (ชักดาบไม่ได้) ████'
do $$
declare q uuid; av bigint; rs bigint; pa bigint;
begin
  q := pg_temp.buy_question(true);
  perform pg_temp.act_block('11111111-1111-1111-1111-111111111111'::uuid,
                            '22222222-2222-2222-2222-222222222222'::uuid);
  select available_coin, reserved_coin into av, rs from public.wallet
   where account_id='11111111-1111-1111-1111-111111111111';
  select payable_coin into pa from public.wallet
   where account_id='22222222-2222-2222-2222-222222222222';
  perform pg_temp.chk('ผู้ถาม available (จ่ายไป 100)', av, 630);
  perform pg_temp.chk('ผู้ถาม reserved', rs, 0);
  perform pg_temp.chk('หมอดู payable (ได้ส่วนแบ่ง 70%)', pa, 70);
  if (select status from public.question where id=q) <> 'completed' then
    raise warning '!! ควรเป็น completed';
  else raise notice 'ok  question = completed'; end if;
end $$;

\echo '████ เคส 4: บล็อกซ้ำ (retry) → replayed ไม่มี ledger เพิ่ม ████'
do $$
declare n_before int; n_after int; v jsonb;
begin
  select count(*) into n_before from public.ledger_transaction;
  v := pg_temp.act_block('11111111-1111-1111-1111-111111111111'::uuid,
                         '22222222-2222-2222-2222-222222222222'::uuid);
  select count(*) into n_after from public.ledger_transaction;
  if (v ->> 'replayed')::boolean and n_before = n_after then
    raise notice 'ok  replayed=true และ ledger ไม่เพิ่ม (% แถวเท่าเดิม)', n_after;
  else
    raise warning '!! replayed=% ledger %->%', v->>'replayed', n_before, n_after;
  end if;
end $$;

\echo '████ เคส 5: ขณะถูกบล็อก ซื้อคำถามไม่ได้ (ทั้งสองทิศ) ████'
do $$
begin
  -- ตอนนี้ user บล็อก seer อยู่ (จากเคส 3)
  begin
    perform pg_temp.buy_question(false);
    raise warning '!! ช่องโหว่: ซื้อได้ทั้งที่ตัวเองบล็อกหมอดูไว้';
  exception when others then
    if sqlerrm = 'blocked_by_you' then raise notice 'ok  ฝั่งเราบล็อกเขา → blocked_by_you';
    else raise warning '!! error ไม่ตรง: %', sqlerrm; end if;
  end;
  perform pg_temp.act_unblock('11111111-1111-1111-1111-111111111111'::uuid,
                              '22222222-2222-2222-2222-222222222222'::uuid);

  -- สลับเป็นหมอดูบล็อกเรา
  perform pg_temp.act_block('22222222-2222-2222-2222-222222222222'::uuid,
                            '11111111-1111-1111-1111-111111111111'::uuid);
  begin
    perform pg_temp.buy_question(false);
    raise warning '!! ช่องโหว่: ซื้อได้ทั้งที่โดนหมอดูบล็อก';
  exception when others then
    if sqlerrm = 'seer_unavailable' then
      raise notice 'ok  โดนเขาบล็อก → seer_unavailable (ไม่เปิดเผยว่าโดนบล็อก)';
    else raise warning '!! error ไม่ตรง: %', sqlerrm; end if;
  end;
  perform pg_temp.act_unblock('22222222-2222-2222-2222-222222222222'::uuid,
                              '11111111-1111-1111-1111-111111111111'::uuid);
end $$;

\echo '████ เคส 6: หลายคำถามค้างพร้อมกัน คนละ state → ปิดครบทุกใบถูกทิศ ████'
do $$
declare q1 uuid; q2 uuid; av bigint; pa_before bigint; pa bigint;
begin
  select payable_coin into pa_before from public.wallet
   where account_id='22222222-2222-2222-2222-222222222222';
  q1 := pg_temp.buy_question(false);   -- submitted
  q2 := pg_temp.buy_question(true);    -- active
  perform pg_temp.act_block('22222222-2222-2222-2222-222222222222'::uuid,
                            '11111111-1111-1111-1111-111111111111'::uuid);
  select available_coin into av from public.wallet
   where account_id='11111111-1111-1111-1111-111111111111';
  select payable_coin into pa from public.wallet
   where account_id='22222222-2222-2222-2222-222222222222';
  -- seer เป็นคนกด → คืนทั้งสองใบ ยอดกลับไปเท่าก่อนซื้อ (630)
  perform pg_temp.chk('ผู้ถาม available (คืนทั้ง 2 ใบ)', av, 630);
  perform pg_temp.chk('หมอดู payable (ไม่เพิ่ม)', pa, pa_before);
  if (select count(*) from public.question
      where id in (q1,q2) and status='cancelled_refunded') = 2 then
    raise notice 'ok  ปิดครบทั้ง 2 ใบ';
  else raise warning '!! ปิดไม่ครบ'; end if;
  perform pg_temp.act_unblock('22222222-2222-2222-2222-222222222222'::uuid,
                              '11111111-1111-1111-1111-111111111111'::uuid);
end $$;

\echo '████ เคส 7: input ผิด ████'
do $$
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  begin
    perform public.block_account('11111111-1111-1111-1111-111111111111'::uuid);
    raise warning '!! บล็อกตัวเองได้';
  exception when others then raise notice 'ok  บล็อกตัวเอง → %', sqlerrm; end;
  begin
    perform public.block_account('99999999-9999-9999-9999-999999999999'::uuid);
    raise warning '!! บล็อก uuid ที่ไม่มีตัวตนได้';
  exception when others then raise notice 'ok  uuid ไม่มีจริง → %', sqlerrm; end;
  perform set_config('role','postgres',true);
end $$;

\echo '████ เคส 8: RLS — ฝ่ายถูกบล็อกต้องมองไม่เห็น และห้ามเขียนตรง ████'
do $$
declare n int;
begin
  perform pg_temp.act_block('22222222-2222-2222-2222-222222222222'::uuid,
                            '11111111-1111-1111-1111-111111111111'::uuid);

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  select count(*) into n from public.block_relation;
  if n = 0 then raise notice 'ok  ฝ่ายถูกบล็อกมองไม่เห็นแถวเลย';
  else raise warning '!! ฝ่ายถูกบล็อกเห็น % แถว = รู้ตัวว่าโดนบล็อก', n; end if;
  begin
    delete from public.block_relation;
    raise warning '!! ผู้ใช้ลบแถวบล็อกได้เอง';
  exception when others then raise notice 'ok  ลบตรงไม่ได้ → %', sqlerrm; end;
  begin
    insert into public.block_relation (blocker_id, blocked_id)
    values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
    raise warning '!! ผู้ใช้ insert แถวบล็อกตรงได้ (ข้าม logic เรื่องเงิน)';
  exception when others then raise notice 'ok  insert ตรงไม่ได้ → %', sqlerrm; end;
  perform set_config('role','postgres',true);

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}',true);
  select count(*) into n from public.block_relation;
  if n = 1 then raise notice 'ok  ผู้บล็อกเห็นแถวของตัวเอง';
  else raise warning '!! ผู้บล็อกเห็น % แถว ควรเป็น 1', n; end if;
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

\echo '--- ไม่มี drift ใน audit_log (ต้องว่าง) ---'
select action, count(*) from public.audit_log
where action in ('wallet_ledger_drift','ledger_zero_sum_violation') group by 1;

\echo '--- audit trail ของการบล็อก ---'
select action, count(*) from public.audit_log
where action in ('account.blocked','account.unblocked') group by 1 order by 1;
