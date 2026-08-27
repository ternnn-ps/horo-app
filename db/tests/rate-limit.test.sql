-- =============================================================================
-- Chata — regression test: rate limiting (เฟส 2 ส่วนที่ 2)
--
-- พิสูจน์ว่า: เกินเพดานถูกปฏิเสธ · retry ไม่กินโควตา · ข้อความระบบไม่นับ ·
--             คนละบัญชีมีโควตาแยกกัน · client แตะตารางนับไม่ได้ ·
--             ที่สำคัญที่สุด — **เงินต้องไม่รั่วตอนโดนปฏิเสธ**
--
-- วิธีรัน:
--   supabase db reset
--   docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
--     -f - < db/tests/rate-limit.test.sql
--
-- ห้ามรันกับฐานข้อมูลที่มีข้อมูลจริง
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------- setup ----
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'user1@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ลูกค้า 1"}'),
 ('44444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'user2@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ลูกค้า 2"}'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'seer@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"หมอดูทดสอบ"}');

update public.account set role='seer' where id='22222222-2222-2222-2222-222222222222';
insert into public.seer_profile (account_id, display_name, approval_status, is_active, accepts_question)
values ('22222222-2222-2222-2222-222222222222','หมอดูทดสอบ','approved',true,true);
-- ราคา 1 เหรียญ เพื่อให้ทดสอบเรื่องโควตาได้โดยไม่ติดเรื่องเงินไม่พอ
insert into public.seer_service (seer_id, service_type_code, price_coin, is_enabled)
values ('22222222-2222-2222-2222-222222222222','chat_question',1,true);

-- เติมเงินให้ user1 แบบไม่ผ่าน IAP (โพสต์ ledger ตรงในนามระบบ)
insert into public.payment_order (id,user_id,coin_package_id,method,psp_code,status,coin_amount,bonus_coin,price_minor,expires_at)
select '33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
       cp.id,'apple_iap','apple','verified',cp.coin_amount,cp.bonus_coin,79900,now()+interval '1 hour'
from public.coin_package cp where cp.code='coin_650';
select public.internal_credit_payment('33333333-3333-3333-3333-333333333333','t1',
  '{"store_product_id":"app.chata.coin650","provider_transaction_id":"t1","purchase_token_hash_hex":"aa01"}'::jsonb) as setup;

-- ตั้งเพดานให้ต่ำ ๆ เพื่อทดสอบได้เร็ว
update public.app_config
set value = '{"submit_question": {"limit": 3, "window_seconds": 3600},
              "question_message": {"limit": 5, "window_seconds": 3600},
              "close_action": {"limit": 60, "window_seconds": 3600}}'::jsonb
where key = 'ratelimit.buckets';

\echo '======== TEST 1: submit_question เพดาน 3 — ครั้งที่ 4 ต้องถูกปฏิเสธ ========'
do $$
declare i int; v_err text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  for i in 1..3 loop
    perform public.submit_question((select id from public.seer_service limit 1),
      format('คำถาม %s', i), gen_random_uuid(), gen_random_uuid());
  end loop;
  raise notice 'ครั้งที่ 1-3 ผ่านตามคาด';
  begin
    perform public.submit_question((select id from public.seer_service limit 1),
      'คำถามที่ 4 ต้องโดนบล็อก', gen_random_uuid(), gen_random_uuid());
    raise warning '!! ช่องโหว่: ครั้งที่ 4 ผ่านได้ทั้งที่เกินเพดาน';
  exception when others then
    raise notice 'ครั้งที่ 4 ถูกปฏิเสธถูกต้อง: %', sqlerrm;
  end;
end $$;
reset role;

\echo '--- คาดหวัง: question 3 ใบ, reserved 3 เหรียญ ---'
select (select count(*) from public.question) as จำนวนคำถาม,
       available_coin, reserved_coin
from public.wallet where account_id='11111111-1111-1111-1111-111111111111';

\echo '======== TEST 2 (สำคัญสุด): เงินต้องไม่รั่วตอนถูกปฏิเสธ ========'
\echo '--- ถ้า ledger มี reserve เกิน 3 รายการ = เหรียญถูกหักแต่ไม่ได้คำถาม ---'
select count(*) as จำนวน_reserve_ในledger
from public.ledger_transaction where operation='reserve';

\echo '======== TEST 3: retry (client_request_id เดิม) ต้องไม่กินโควตา ========'
-- หมายเหตุ: อ่าน rate_limit_counter นอก role authenticated เพราะตารางเป็น deny-all
-- (การที่อ่านในนามผู้ใช้ไม่ได้ คือพฤติกรรมที่ถูกต้อง — พิสูจน์ใน TEST 7)
delete from public.rate_limit_counter;

create temp table t_rid as select gen_random_uuid() as rid;

do $$
declare v_rid uuid := (select rid from t_rid); i int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  -- ครั้งแรก = ของจริง
  perform public.submit_question((select id from public.seer_service limit 1),
    'คำถามที่จะ retry', gen_random_uuid(), v_rid);
end $$;
reset role;

create temp table t_hits_before as
select hits from public.rate_limit_counter
where account_id='11111111-1111-1111-1111-111111111111' and bucket='submit_question';

do $$
declare v_rid uuid := (select rid from t_rid); i int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  -- ยิงซ้ำด้วย request id เดิม 5 ครั้ง (จำลอง network หลุดแล้ว retry)
  for i in 1..5 loop
    perform public.submit_question((select id from public.seer_service limit 1),
      'คำถามที่จะ retry', gen_random_uuid(), v_rid);
  end loop;
end $$;
reset role;

do $$
declare v_before int; v_after int;
begin
  select hits into v_before from t_hits_before;
  select hits into v_after from public.rate_limit_counter
   where account_id='11111111-1111-1111-1111-111111111111' and bucket='submit_question';
  if coalesce(v_before,0) = coalesce(v_after,0) then
    raise notice 'ถูกต้อง: retry 5 ครั้งไม่กินโควตาเลย (hits คงที่ที่ %)', v_after;
  else
    raise warning '!! retry กินโควตา: % -> %', v_before, v_after;
  end if;
end $$;

\echo '======== TEST 4: ข้อความในแชท เพดาน 5 ========'
do $$
declare i int; v_qid uuid;
begin
  select id into v_qid from public.question order by created_at limit 1;
  update public.question set status='active' where id=v_qid;
  delete from public.rate_limit_counter;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  for i in 1..5 loop
    insert into public.question_message (question_id, sender_id, client_message_id, message_type, content)
    values (v_qid, '11111111-1111-1111-1111-111111111111', gen_random_uuid(), 'text', format('ข้อความ %s', i));
  end loop;
  raise notice 'ข้อความ 1-5 ผ่านตามคาด';
  begin
    insert into public.question_message (question_id, sender_id, client_message_id, message_type, content)
    values (v_qid, '11111111-1111-1111-1111-111111111111', gen_random_uuid(), 'text', 'ข้อความที่ 6');
    raise warning '!! ช่องโหว่: ข้อความที่ 6 ผ่านได้';
  exception when others then
    raise notice 'ข้อความที่ 6 ถูกปฏิเสธถูกต้อง: %', sqlerrm;
  end;
end $$;
reset role;

\echo '======== TEST 5: ข้อความระบบ (sender_id null) ต้องไม่ถูกนับ ========'
do $$
declare v_qid uuid; v_hits_before int; v_hits_after int;
begin
  select id into v_qid from public.question where status='active' limit 1;
  select hits into v_hits_before from public.rate_limit_counter
   where bucket='question_message' and account_id='11111111-1111-1111-1111-111111111111';

  -- ระบบยังปิดงานได้แม้ผู้ใช้ชนเพดานแล้ว (คำสั่งนี้สร้าง system message)
  perform public.internal_settle_question(v_qid, true);

  select hits into v_hits_after from public.rate_limit_counter
   where bucket='question_message' and account_id='11111111-1111-1111-1111-111111111111';
  if coalesce(v_hits_before,0) = coalesce(v_hits_after,0) then
    raise notice 'ถูกต้อง: ข้อความระบบไม่กินโควตาของผู้ใช้ (hits คงที่)';
  else
    raise warning '!! ข้อความระบบกินโควตา: % -> %', v_hits_before, v_hits_after;
  end if;
end $$;

\echo '======== TEST 6: คนละบัญชี โควตาต้องแยกกัน ========'
do $$
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
  begin
    -- user2 ไม่มีเงิน จึงคาดหวัง insufficient_coin ไม่ใช่ rate_limited
    perform public.submit_question((select id from public.seer_service limit 1),
      'user2 ถามครั้งแรก', gen_random_uuid(), gen_random_uuid());
    raise notice 'user2 ผ่าน (โควตาแยกกันจริง)';
  exception when others then
    if sqlerrm = 'rate_limited' then
      raise warning '!! ช่องโหว่: โควตาของ user1 ไปกระทบ user2';
    else
      raise notice 'ถูกต้อง: user2 ไม่ติด rate limit (ติด % ซึ่งเป็นคนละเรื่อง)', sqlerrm;
    end if;
  end;
end $$;
reset role;

\echo '======== TEST 7: client ต้องแตะตารางนับไม่ได้เลย ========'
do $$
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
  begin
    delete from public.rate_limit_counter;
    raise warning '!! ช่องโหว่: ผู้ใช้ลบตัวนับตัวเองได้ = rate limit ไร้ความหมาย';
  exception when others then
    raise notice 'บล็อกถูกต้อง: %', sqlerrm;
  end;
  begin
    perform public.consume_rate_limit('11111111-1111-1111-1111-111111111111','submit_question');
    raise warning '!! ช่องโหว่: ผู้ใช้เรียก consume_rate_limit เองได้';
  exception when others then
    raise notice 'บล็อกถูกต้อง: %', sqlerrm;
  end;
end $$;
reset role;

\echo '======== JOB: เก็บกวาด counter เก่า ========'
insert into public.rate_limit_counter (account_id, bucket, window_start, hits)
values ('11111111-1111-1111-1111-111111111111','old_bucket', now() - interval '10 days', 1);
select public.job_purge_rate_limit_counters();
\echo '--- คาดหวัง: แถวเก่าหายไป แถวปัจจุบันยังอยู่ ---'
select bucket, window_start < now() - interval '2 days' as เป็นของเก่า
from public.rate_limit_counter order by bucket;

\echo '======== INVARIANT: wallet ตรงกับ ledger (ต้องว่าง) ========'
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
