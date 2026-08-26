-- =============================================================================
-- Chata — regression test: seer onboarding (เฟส 2 ส่วนที่ 4)
--
-- ครอบ: ใบสมัครไม่ครบต้องบอกว่าขาดอะไร · อนุมัติแล้ว side effect ครบทุกตาราง ·
--        ผู้ใช้ธรรมดาเรียก RPC ฝั่งอนุมัติไม่ได้ · เอกสารเป็น PII ต้องไม่รั่ว ·
--        ลาออกทั้งที่มีงานค้างไม่ได้ · หมอดูที่ลาออกหายจาก catalog
--
-- วิธีรัน:
--   supabase db reset
--   docker exec -i supabase_db_project-chata psql -U postgres -d postgres \
--     -f - < db/tests/seer-onboarding.test.sql
--
-- ผ่าน = ไม่มีบรรทัด WARNING/ERROR
-- ห้ามรันกับฐานข้อมูลที่มีข้อมูลจริง
-- =============================================================================

\set ON_ERROR_STOP on
\set A '11111111-1111-1111-1111-111111111111'
\set B '22222222-2222-2222-2222-222222222222'
\set C '33333333-3333-3333-3333-333333333333'

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
 (:'A','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'apply@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ผู้สมัคร"}'),
 (:'B','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'reject@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ผู้สมัคร 2"}'),
 (:'C','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'buyer@chata.test','x',now(),now(),now(),'{"provider":"email"}','{"display_name":"ลูกค้า"}');

create or replace function pg_temp.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', p_uid), true);
end $$;

create or replace function pg_temp.as_pg() returns void
language plpgsql as $$ begin perform set_config('role','postgres',true); end $$;

create or replace function pg_temp.chk(p_label text, p_ok boolean, p_extra text default '')
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok  %  %', p_label, p_extra;
  else raise warning '!! %  %', p_label, p_extra; end if;
end $$;

\echo '████ 1: ส่งใบสมัครที่ยังไม่ครบ → ต้องบอกว่าขาดอะไร ████'
do $$
declare v jsonb;
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  v := public.save_seer_application('หมอดูสมชาย', 'สั้นไป', 1, array[1], 100);
  perform pg_temp.chk('สร้างใบร่างได้', (v->>'status') = 'draft', v::text);
  begin
    perform public.submit_seer_application();
    raise warning '!! ส่งใบที่ไม่ครบได้';
  exception when others then
    perform pg_temp.chk('ปฏิเสธใบไม่ครบ', sqlerrm = 'incomplete_application', sqlerrm);
  end;
  perform pg_temp.as_pg();
end $$;

\echo '--- รายละเอียดที่ขาด (ควรบอก bio สั้น + เอกสาร 2 ชนิด) ---'
do $$
declare v_detail text;
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  begin perform public.submit_seer_application();
  exception when others then get stacked diagnostics v_detail = pg_exception_detail;
  end;
  raise notice 'ขาด: %', v_detail;
  perform pg_temp.as_pg();
end $$;

\echo '████ 2: แนบเอกสาร (insert ตรงผ่าน RLS) แล้วส่งใหม่ ████'
do $$
declare v jsonb;
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  insert into public.seer_document (account_id, document_type, object_key)
  values ('11111111-1111-1111-1111-111111111111','national_id',
          '11111111-1111-1111-1111-111111111111/id.jpg');
  insert into public.seer_document (account_id, document_type, object_key)
  values ('11111111-1111-1111-1111-111111111111','portrait',
          '11111111-1111-1111-1111-111111111111/face.jpg');

  v := public.save_seer_application('หมอดูสมชาย',
        'ดูดวงด้วยไพ่ยิปซีและโหราศาสตร์ไทยมากว่าสิบปี ยินดีให้คำปรึกษาทุกเรื่อง',
        1, array[1,2], 100);
  v := public.submit_seer_application();
  perform pg_temp.chk('ส่งใบสมัครได้', (v->>'status') = 'submitted', v::text);

  v := public.submit_seer_application();
  perform pg_temp.chk('ส่งซ้ำ = replayed', (v->>'replayed')::boolean, v::text);
  perform pg_temp.as_pg();
end $$;

\echo '████ 3: แนบเอกสารที่ path ไม่ใช่ของตัวเอง → ต้องถูกปฏิเสธ ████'
do $$
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  begin
    insert into public.seer_document (account_id, document_type, object_key)
    values ('11111111-1111-1111-1111-111111111111','other',
            '22222222-2222-2222-2222-222222222222/steal.jpg');
    raise warning '!! แนบไฟล์ที่ path ของคนอื่นได้';
  exception when others then
    perform pg_temp.chk('path ต้องเป็นของตัวเอง', true, sqlerrm);
  end;
  begin
    insert into public.seer_document (account_id, document_type, object_key)
    values ('22222222-2222-2222-2222-222222222222','other','22222222-2222-2222-2222-222222222222/x.jpg');
    raise warning '!! แนบเอกสารในนามคนอื่นได้';
  exception when others then
    perform pg_temp.chk('แนบในนามคนอื่นไม่ได้', true, sqlerrm);
  end;
  perform pg_temp.as_pg();
end $$;

\echo '████ 4: ผู้ใช้ธรรมดาเรียก RPC ฝั่งอนุมัติไม่ได้ ████'
do $$
declare v_app uuid;
begin
  select id into v_app from public.seer_application where status='submitted' limit 1;
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  begin
    perform public.admin_review_seer_application(v_app, true, 'self-approve');
    raise warning '!! ผู้ใช้อนุมัติใบสมัครตัวเองได้ = ช่องโหว่ร้ายแรง';
  exception when others then
    perform pg_temp.chk('อนุมัติเองไม่ได้', true, sqlerrm);
  end;
  perform pg_temp.as_pg();
end $$;

\echo '████ 5: อนุมัติ → side effect ต้องครบทุกตาราง ████'
do $$
declare v_app uuid; v jsonb; v_role text; n int;
begin
  select id into v_app from public.seer_application where status='submitted' limit 1;
  v := public.admin_review_seer_application(v_app, true, 'ray@studio');
  perform pg_temp.chk('อนุมัติสำเร็จ', (v->>'status') = 'approved', v::text);

  select role into v_role from public.account where id='11111111-1111-1111-1111-111111111111';
  perform pg_temp.chk('role เปลี่ยนเป็น seer', v_role = 'seer', v_role);

  perform pg_temp.chk('มี seer_profile และ approved',
    exists(select 1 from public.seer_profile
           where account_id='11111111-1111-1111-1111-111111111111'
             and approval_status='approved' and is_active = false));

  select count(*) into n from public.seer_skill where seer_id='11111111-1111-1111-1111-111111111111';
  perform pg_temp.chk('seer_skill ถูกสร้าง 2 แถว', n = 2, n::text);
  perform pg_temp.chk('main skill ถูกตั้งถูกตัว',
    exists(select 1 from public.seer_skill
           where seer_id='11111111-1111-1111-1111-111111111111' and skill_id=1 and is_main));

  perform pg_temp.chk('seer_service สร้างแบบยังไม่เปิด (ต้องเข้าแอปมาเปิดเอง)',
    exists(select 1 from public.seer_service
           where seer_id='11111111-1111-1111-1111-111111111111'
             and price_coin=100 and is_enabled = false));

  perform pg_temp.chk('เอกสารถูก mark approved',
    (select count(*) from public.seer_document
      where account_id='11111111-1111-1111-1111-111111111111'
        and review_status='approved') = 2);

  perform pg_temp.chk('มี audit trail พร้อมชื่อผู้อนุมัติ',
    exists(select 1 from public.audit_log
           where action='seer.approved' and detail->>'reviewer'='ray@studio'));

  v := public.admin_review_seer_application(v_app, true, 'ray@studio');
  perform pg_temp.chk('อนุมัติซ้ำ = replayed', (v->>'replayed')::boolean, v::text);
end $$;

\echo '████ 6: สมัครซ้ำหลังเป็นหมอดูแล้ว → ต้องไม่ได้ ████'
do $$
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  begin
    perform public.save_seer_application('ชื่อใหม่','x',1,array[1],50);
    raise warning '!! หมอดูสมัครซ้ำได้';
  exception when others then
    perform pg_temp.chk('หมอดูสมัครซ้ำไม่ได้', sqlerrm in ('not_eligible','already_seer'), sqlerrm);
  end;
  perform pg_temp.as_pg();
end $$;

\echo '████ 7: ปฏิเสธใบสมัคร — ต้องมีเหตุผลเสมอ ████'
do $$
declare v_app uuid; v jsonb;
begin
  perform pg_temp.as_user('22222222-2222-2222-2222-222222222222');
  insert into public.seer_document (account_id, document_type, object_key)
  values ('22222222-2222-2222-2222-222222222222','national_id','22222222-2222-2222-2222-222222222222/id.jpg');
  insert into public.seer_document (account_id, document_type, object_key)
  values ('22222222-2222-2222-2222-222222222222','portrait','22222222-2222-2222-2222-222222222222/face.jpg');
  perform public.save_seer_application('หมอดูสมหญิง',
    'ดูดวงลายมือและเลขศาสตร์ ประสบการณ์ยาวนาน ให้คำปรึกษาอย่างตรงไปตรงมา', 2, array[2], 200);
  perform public.submit_seer_application();
  perform pg_temp.as_pg();

  select id into v_app from public.seer_application
  where account_id='22222222-2222-2222-2222-222222222222' and status='submitted';

  begin
    perform public.admin_review_seer_application(v_app, false, 'ray@studio', null);
    raise warning '!! ปฏิเสธโดยไม่ให้เหตุผลได้';
  exception when others then
    perform pg_temp.chk('ปฏิเสธต้องมีเหตุผล', sqlerrm = 'missing_reject_reason', sqlerrm);
  end;

  v := public.admin_review_seer_application(v_app, false, 'ray@studio', 'รูปบัตรไม่ชัด');
  perform pg_temp.chk('ปฏิเสธสำเร็จ', (v->>'status')='rejected', v::text);
  perform pg_temp.chk('role ยังเป็น user',
    (select role from public.account where id='22222222-2222-2222-2222-222222222222') = 'user');
  perform pg_temp.chk('ผู้สมัครได้รับแจ้งเหตุผล',
    exists(select 1 from public.notification_inbox
           where account_id='22222222-2222-2222-2222-222222222222'
             and body='รูปบัตรไม่ชัด'));
end $$;

\echo '████ 8: เอกสารเป็น PII — คนอื่นต้องมองไม่เห็น ████'
do $$
declare n int;
begin
  perform pg_temp.as_user('33333333-3333-3333-3333-333333333333');
  select count(*) into n from public.seer_document;
  perform pg_temp.chk('บุคคลที่สามมองไม่เห็นเอกสารใคร', n = 0, n::text);
  perform pg_temp.as_pg();

  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  select count(*) into n from public.seer_document;
  perform pg_temp.chk('เจ้าของเห็นเฉพาะของตัวเอง', n = 2, n::text);
  begin
    update public.seer_document set review_status='approved';
    raise warning '!! เจ้าของอนุมัติเอกสารตัวเองได้';
  exception when others then
    perform pg_temp.chk('เจ้าของแก้สถานะตรวจไม่ได้', true, sqlerrm);
  end;
  perform pg_temp.as_pg();
end $$;

\echo '████ 9: หมอดูเปิดบริการแล้วรับงานได้จริง ████'
do $$
declare v jsonb;
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  update public.seer_profile set is_active = true, accepts_question = true
   where account_id='11111111-1111-1111-1111-111111111111';
  update public.seer_service set is_enabled = true
   where seer_id='11111111-1111-1111-1111-111111111111';
  perform pg_temp.as_pg();

  -- เติมเงินให้ลูกค้า
  insert into public.payment_order (id,user_id,coin_package_id,method,psp_code,status,
                                    coin_amount,bonus_coin,price_minor,expires_at)
  select '44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333',
         cp.id,'apple_iap','apple','verified',cp.coin_amount,cp.bonus_coin,79900,now()+interval '1 hour'
  from public.coin_package cp where cp.code='coin_650';
  perform public.internal_credit_payment('44444444-4444-4444-4444-444444444444','t9',
    '{"store_product_id":"app.chata.coin650","provider_transaction_id":"t9","purchase_token_hash_hex":"bb01"}'::jsonb);

  perform pg_temp.as_user('33333333-3333-3333-3333-333333333333');
  v := public.submit_question((select id from public.seer_service
                               where seer_id='11111111-1111-1111-1111-111111111111'),
        'ขอถามเรื่องการงานหน่อยค่ะ', gen_random_uuid(), gen_random_uuid());
  perform pg_temp.chk('ลูกค้าซื้อคำถามกับหมอดูใหม่ได้', (v->>'question_id') is not null, v::text);
  perform pg_temp.as_pg();
end $$;

\echo '████ 10: ลาออกทั้งที่มีงานค้าง → ต้องไม่ได้ (ห้ามลอยแพลูกค้า) ████'
do $$
declare v_detail text;
begin
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  begin
    perform public.retire_seer();
    raise warning '!! ลาออกทิ้งงานค้างได้ = ลูกค้าโดนลอยแพ';
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.chk('ลาออกไม่ได้เมื่อมีงานค้าง', sqlerrm='open_work_exists', v_detail);
  end;
  perform pg_temp.as_pg();
end $$;

\echo '████ 11: เคลียร์งานแล้วลาออก → หายจาก catalog ████'
do $$
declare v jsonb; n int;
begin
  -- ปิดงานค้างให้จบก่อน (submitted = ยังไม่ตอบ ต้องคืนเงิน ไม่ใช่ settle)
  perform public.internal_refund_question(id, 'admin')
  from public.question where status = 'submitted';
  perform public.internal_settle_question(id, true)
  from public.question where status in ('active','close_requested');

  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  v := public.retire_seer();
  perform pg_temp.chk('ลาออกสำเร็จ', (v->>'retired_at') is not null, v::text);
  perform pg_temp.as_pg();

  perform pg_temp.chk('บริการถูกปิดทั้งหมด',
    not exists(select 1 from public.seer_service
               where seer_id='11111111-1111-1111-1111-111111111111' and is_enabled));

  -- คนทั่วไปต้องมองไม่เห็นแล้ว
  -- ต้องล้าง jwt claims ด้วย ไม่งั้น auth.uid() ยังคืนค่าเดิมและ policy
  -- จะปล่อยผ่านทางสาขา "เจ้าของเห็นโปรไฟล์ตัวเอง"
  perform set_config('request.jwt.claims','',true);
  perform set_config('role','anon',true);
  select count(*) into n from public.seer_profile
   where account_id='11111111-1111-1111-1111-111111111111';
  perform pg_temp.chk('หายจาก catalog สาธารณะ', n = 0, n::text);
  perform pg_temp.as_pg();

  -- เจ้าของยังเห็นโปรไฟล์ตัวเอง
  perform pg_temp.as_user('11111111-1111-1111-1111-111111111111');
  select count(*) into n from public.seer_profile;
  perform pg_temp.chk('เจ้าของยังเห็นโปรไฟล์ตัวเอง', n = 1, n::text);
  perform pg_temp.as_pg();
end $$;

\echo '████ 12: ซื้อคำถามกับหมอดูที่ลาออกแล้วไม่ได้ ████'
do $$
begin
  perform pg_temp.as_user('33333333-3333-3333-3333-333333333333');
  begin
    perform public.submit_question(
      (select id from public.seer_service where seer_id='11111111-1111-1111-1111-111111111111'),
      'ยังรับงานอยู่ไหม', gen_random_uuid(), gen_random_uuid());
    raise warning '!! ซื้อกับหมอดูที่ลาออกแล้วได้';
  exception when others then
    perform pg_temp.chk('หมอดูลาออกแล้วซื้อไม่ได้', sqlerrm='seer_unavailable', sqlerrm);
  end;
  perform pg_temp.as_pg();
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

\echo '--- audit trail ทั้งหมด ---'
select action, count(*) from public.audit_log group by 1 order by 1;
