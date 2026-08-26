-- =============================================================================
-- Chata เฟส 2 (ส่วนที่ 4) — เส้นทางสมัครเป็นหมอดู (seer onboarding)
-- implement ตาม docs/specs/phase2-block-and-seer-onboarding.md ส่วน B
--
-- ปัญหาเดิม: seer_profile INSERT ได้เฉพาะ service_role → ผู้ใช้กดสมัครเองไม่ได้
--   ต้องให้ทีมงานสร้างให้ทาง Studio ซึ่ง scale ไม่ได้ = ไม่มีหมอดู = ไม่มีของขาย
--
-- โมเดล role ที่ user เคาะ: **one-way promotion**
--   บัญชี role='user' ยื่นใบสมัคร → อนุมัติแล้ว flip เป็น role='seer' ถาวร สลับกลับไม่ได้
--   เลือกทางนี้เพราะแตะของที่รันบน cloud อยู่แล้วน้อยที่สุด (policy/CHECK เดิมทำงานถูกพอดี)
--   คนที่อยากแยกตัวตนลูกค้า/หมอดู ยังสมัครอีกบัญชีได้ตามเดิม
--
-- ใบสมัครแยกจาก seer_profile โดยตั้งใจ — seer_profile จะมีแถวก็ต่อเมื่ออนุมัติแล้ว
--   ทำให้ catalog สะอาด: ทุก join/policy/submit_question ที่แตะ seer_profile
--   ไม่ต้องรับรู้แถวครึ่ง ๆ กลาง ๆ และเก็บประวัติสมัคร-ถูกปฏิเสธ-สมัครใหม่เป็นคนละแถวได้
-- =============================================================================

-- =============================================================================
-- 1. ลาออกถาวร — column ใหม่บน seer_profile
-- =============================================================================
alter table public.seer_profile add column retired_at timestamptz;

comment on column public.seer_profile.retired_at is
  'เวลาที่หมอดูลาออกถาวร — หายจาก catalog แต่ประวัติงาน/ยอดค้างจ่ายยังอยู่ครบ';

-- หายจาก catalog แต่เจ้าของยังเห็นโปรไฟล์ตัวเอง
drop policy seer_profile_public_select on public.seer_profile;
create policy seer_profile_public_select on public.seer_profile
  for select to anon, authenticated
  using ((approval_status = 'approved' and retired_at is null)
         or account_id = (select auth.uid()));

-- =============================================================================
-- 2. ตาราง seer_application — ใบสมัคร
-- =============================================================================
create table public.seer_application (
  id                uuid primary key default gen_random_uuid(),
  account_id        uuid not null references public.account (id) on delete cascade,
  status            text not null default 'draft'
                    constraint seer_application_status_chk
                    check (status in ('draft','submitted','approved','rejected','withdrawn')),
  display_name      text constraint seer_application_name_chk
                    check (display_name is null or char_length(display_name) between 1 and 50),
  bio               text constraint seer_application_bio_chk
                    check (bio is null or char_length(bio) <= 2000),
  main_skill_id     integer references public.skill (id) on delete set null,
  skill_ids         integer[] not null default '{}'
                    constraint seer_application_skills_chk
                    check (coalesce(array_length(skill_ids, 1), 0) <= 10),
  price_coin        bigint constraint seer_application_price_chk
                    check (price_coin is null or price_coin >= 0),
  submitted_at      timestamptz,
  reject_reason     text constraint seer_application_reject_chk
                    check (reject_reason is null or char_length(reject_reason) <= 1000),
  decided_at        timestamptz,
  decided_by_label  text,
  version           integer not null default 1,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint seer_application_reject_reason_required_chk
    check (status <> 'rejected' or reject_reason is not null),
  constraint seer_application_decided_chk
    check ((status in ('approved','rejected')) = (decided_at is not null))
);

comment on table public.seer_application is
  'ใบสมัครเป็นหมอดู — แยกจาก seer_profile เพื่อให้ catalog มีแต่คนที่อนุมัติแล้ว';

-- เปิดใบได้ทีละหนึ่ง; สมัครใหม่หลังถูกปฏิเสธ = แถวใหม่ ประวัติเดิมคงอยู่
create unique index seer_application_open_uniq
  on public.seer_application (account_id)
  where status in ('draft','submitted');
create index seer_application_account_idx
  on public.seer_application (account_id, created_at desc);
create index seer_application_queue_idx
  on public.seer_application (status) where status = 'submitted';

create trigger seer_application_touch
  before update on public.seer_application
  for each row execute function public.touch_versioned_row();

alter table public.seer_application enable row level security;

create policy seer_application_owner_select on public.seer_application
  for select to authenticated
  using (account_id = (select auth.uid()));

grant select on public.seer_application to authenticated;
-- ไม่ grant เขียน — ทุก transition ผ่าน RPC เพราะ approve มี side effect ใหญ่

-- =============================================================================
-- 3. ตาราง seer_document — เอกสารยืนยันตัวตน (PII สูง)
--
-- ต่างจาก design doc เดิมหนึ่งจุดโดยตั้งใจ: FK ชี้ account(id) ไม่ใช่ seer_profile
-- เพราะเอกสารถูกอัปโหลด "ตอนสมัคร" ซึ่ง seer_profile ยังไม่มีแถว
-- =============================================================================
create table public.seer_document (
  id                 uuid primary key default gen_random_uuid(),
  account_id         uuid not null references public.account (id) on delete cascade,
  document_type      text not null
                     constraint seer_document_type_chk
                     check (document_type in ('national_id','bank_book','certificate',
                                              'portrait','other')),
  object_key         text not null unique,
  review_status      text not null default 'pending'
                     constraint seer_document_review_chk
                     check (review_status in ('pending','approved','rejected')),
  reject_reason      text,
  reviewed_at        timestamptz,
  reviewed_by_label  text,
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  -- กันแนบไฟล์ของคนอื่น: path ต้องขึ้นต้นด้วย account_id ของตัวเอง
  constraint seer_document_path_chk
    check (object_key like account_id::text || '/%')
);

comment on table public.seer_document is
  'เอกสารยืนยันตัวตนของผู้สมัคร/หมอดู — PII สูง owner-read เท่านั้น ไม่มี public ทุกกรณี';

create index seer_document_account_idx
  on public.seer_document (account_id) where deleted_at is null;
create index seer_document_queue_idx
  on public.seer_document (review_status) where review_status = 'pending';

alter table public.seer_document enable row level security;

create policy seer_document_owner_select on public.seer_document
  for select to authenticated
  using (account_id = (select auth.uid()));

-- insert ตรงได้ (ไม่แตะเงิน) แต่ต้องเป็นของตัวเองและเริ่มที่ pending เสมอ
create policy seer_document_owner_insert on public.seer_document
  for insert to authenticated
  with check (account_id = (select auth.uid()) and review_status = 'pending');

-- เจ้าของทำได้อย่างเดียวคือ soft delete ก่อนถูกตรวจ
create policy seer_document_owner_update on public.seer_document
  for update to authenticated
  using (account_id = (select auth.uid()));

grant select on public.seer_document to authenticated;
grant insert (account_id, document_type, object_key) on public.seer_document to authenticated;
grant update (deleted_at) on public.seer_document to authenticated;

-- บังคับว่าเจ้าของแก้ได้เฉพาะ deleted_at NULL→now และเฉพาะตอนยังไม่ถูกตรวจ
create or replace function public.protect_seer_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.review_status <> 'pending' then
    raise exception 'document_already_reviewed';
  end if;
  if new.deleted_at is null or old.deleted_at is not null then
    raise exception 'only_soft_delete_allowed';
  end if;
  return new;
end;
$$;
revoke all on function public.protect_seer_document() from public, anon, authenticated;

-- ทำงานเฉพาะตอน client เป็นคนแก้ (ฝั่งรีวิวใช้ service_role ซึ่งข้าม RLS แต่ไม่ข้าม trigger
-- จึงต้องกันด้วย pg_trigger_depth/role — ที่นี่ใช้วิธีง่ายกว่า: ฝั่งรีวิวแก้ผ่าน RPC
-- ที่ set local role ไม่ได้ จึงเช็คจาก current_user แทน)
create trigger seer_document_protect
  before update on public.seer_document
  for each row
  when (current_user = 'authenticated')
  execute function public.protect_seer_document();

create or replace function public.enforce_seer_document_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.consume_rate_limit(new.account_id, 'seer_document');
  return new;
end;
$$;
revoke all on function public.enforce_seer_document_rate_limit() from public, anon, authenticated;

create trigger seer_document_rate_limit
  before insert on public.seer_document
  for each row
  when (current_user = 'authenticated')
  execute function public.enforce_seer_document_rate_limit();

-- =============================================================================
-- 4. Storage bucket — private, เจ้าของเข้าถึงได้เฉพาะโฟลเดอร์ตัวเอง
--    ทีมรีวิวเปิดไฟล์ผ่าน signed URL จาก service role เท่านั้น
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('seer-documents', 'seer-documents', false, 10485760,
        array['image/jpeg','image/png','image/heic','image/webp','application/pdf'])
on conflict (id) do nothing;

create policy seer_documents_owner_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'seer-documents'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy seer_documents_owner_select on storage.objects
  for select to authenticated
  using (bucket_id = 'seer-documents'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

-- =============================================================================
-- 5. config
-- =============================================================================
insert into public.app_config (key, value, is_public, description) values
  ('seer.application_required_documents', '["national_id","portrait"]'::jsonb, true,
   'เอกสารที่ต้องแนบครบก่อนส่งใบสมัครหมอดู — client ต้องรู้เพื่อแสดงในหน้าสมัคร'),
  ('seer.application_max_total', '5'::jsonb, false,
   'จำนวนใบสมัครสูงสุดต่อบัญชีตลอดกาล (กันสมัครวนไม่จบ)')
on conflict (key) do nothing;

update public.app_config
set value = value || '{
      "seer_apply":          {"limit": 3,  "window_seconds": 86400},
      "seer_document":       {"limit": 30, "window_seconds": 86400},
      "seer_profile_update": {"limit": 20, "window_seconds": 3600}
    }'::jsonb
where key = 'ratelimit.buckets';

-- =============================================================================
-- 6. RPC ฝั่งผู้สมัคร
-- =============================================================================

-- -----------------------------------------------------------------------------
-- save_seer_application — สร้าง/แก้ใบร่าง (upsert โดยธรรมชาติ)
-- เรียกตอนใบเป็น submitted = ดึงกลับมาแก้เป็น draft
-- -----------------------------------------------------------------------------
create or replace function public.save_seer_application(
  p_display_name text,
  p_bio          text,
  p_main_skill_id integer,
  p_skill_ids    integer[],
  p_price_coin   bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_acc    record;
  v_app    public.seer_application%rowtype;
  v_total  int;
  v_max    int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select status, role into v_acc from public.account where id = v_uid;
  if v_acc.status <> 'active' then raise exception 'account_not_active'; end if;
  if v_acc.role <> 'user' then raise exception 'not_eligible'; end if;

  perform 1 from public.seer_profile where account_id = v_uid;
  if found then raise exception 'already_seer'; end if;

  select * into v_app from public.seer_application
  where account_id = v_uid and status in ('draft','submitted')
  for update;

  if not found then
    v_max := coalesce((public.get_config('seer.application_max_total') #>> '{}')::int, 5);
    select count(*) into v_total from public.seer_application where account_id = v_uid;
    if v_total >= v_max then raise exception 'application_limit_reached'; end if;

    perform public.consume_rate_limit(v_uid, 'seer_apply');

    insert into public.seer_application
      (account_id, status, display_name, bio, main_skill_id, skill_ids, price_coin)
    values (v_uid, 'draft', p_display_name, p_bio, p_main_skill_id,
            coalesce(p_skill_ids, '{}'), p_price_coin)
    returning * into v_app;
  else
    update public.seer_application
    set display_name = p_display_name,
        bio          = p_bio,
        main_skill_id = p_main_skill_id,
        skill_ids    = coalesce(p_skill_ids, '{}'),
        price_coin   = p_price_coin,
        status       = 'draft',
        submitted_at = null
    where id = v_app.id
    returning * into v_app;
  end if;

  return jsonb_build_object('application_id', v_app.id, 'status', v_app.status);
end;
$$;

-- -----------------------------------------------------------------------------
-- submit_seer_application — ตรวจความครบทั้งหมดแล้วส่งเข้าคิว
-- error บอกชัดว่าขาดอะไรผ่าน errdetail เพื่อให้ client แสดงได้ตรงจุด
-- -----------------------------------------------------------------------------
create or replace function public.submit_seer_application()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_app     public.seer_application%rowtype;
  v_bounds  jsonb;
  v_missing text[] := '{}';
  v_reqdocs text[];
  v_doc     text;
  v_sid     integer;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_app from public.seer_application
  where account_id = v_uid and status in ('draft','submitted')
  for update;
  if not found then raise exception 'not_found'; end if;
  if v_app.status = 'submitted' then
    return jsonb_build_object('application_id', v_app.id, 'status', 'submitted',
                              'replayed', true);
  end if;

  if v_app.display_name is null or char_length(btrim(v_app.display_name)) = 0 then
    v_missing := v_missing || 'display_name'::text;
  end if;
  -- bio ต้องยาวพอสมควร กันใบสมัครขยะ
  if v_app.bio is null or char_length(btrim(v_app.bio)) < 30 then
    v_missing := v_missing || 'bio(อย่างน้อย 30 ตัวอักษร)'::text;
  end if;
  if v_app.price_coin is null then
    v_missing := v_missing || 'price_coin'::text;
  end if;
  if v_app.main_skill_id is null then
    v_missing := v_missing || 'main_skill_id'::text;
  elsif not exists (select 1 from public.skill
                    where id = v_app.main_skill_id and is_enabled) then
    v_missing := v_missing || 'main_skill_id(ไม่มีหรือปิดอยู่)'::text;
  elsif not (v_app.main_skill_id = any(v_app.skill_ids)) then
    v_missing := v_missing || 'main_skill_id(ต้องอยู่ในชุด skill_ids)'::text;
  end if;

  foreach v_sid in array coalesce(v_app.skill_ids, '{}') loop
    if not exists (select 1 from public.skill where id = v_sid and is_enabled) then
      v_missing := v_missing || (format('skill_id %s(ไม่มีหรือปิดอยู่)', v_sid)::text);
    end if;
  end loop;

  -- เอกสารบังคับต้องครบ (ยังไม่ถูกลบ และยังไม่ถูกปฏิเสธ)
  select array(select jsonb_array_elements_text(
           public.get_config('seer.application_required_documents')))
    into v_reqdocs;
  foreach v_doc in array coalesce(v_reqdocs, '{}') loop
    if not exists (select 1 from public.seer_document
                   where account_id = v_uid and document_type = v_doc
                     and deleted_at is null and review_status <> 'rejected') then
      v_missing := v_missing || (format('document:%s', v_doc)::text);
    end if;
  end loop;

  if array_length(v_missing, 1) is not null then
    raise exception 'incomplete_application'
      using errcode = 'P0001', detail = array_to_string(v_missing, ', ');
  end if;

  -- ราคาใช้กฎเดียวกับ seer_service (validate_seer_service_price) เพื่อไม่ให้สองที่เพี้ยนกัน
  v_bounds := public.get_config('service.price_bounds') -> 'chat_question';
  if v_bounds is null then raise exception 'service_type_unavailable'; end if;
  if v_app.price_coin < (v_bounds ->> 'min_coin')::bigint
     or v_app.price_coin > (v_bounds ->> 'max_coin')::bigint then
    raise exception 'invalid_price'
      using errcode = 'P0001',
            detail = format('ต้องอยู่ระหว่าง %s ถึง %s',
                            v_bounds ->> 'min_coin', v_bounds ->> 'max_coin');
  end if;

  update public.seer_application
  set status = 'submitted', submitted_at = now()
  where id = v_app.id;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('user', v_uid, 'seer_application.submitted', 'seer_application',
          v_app.id::text, '{}'::jsonb);

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_uid, 'system', 'ส่งใบสมัครแล้ว',
          'ทีมงานกำลังตรวจสอบใบสมัครของคุณ', 'chata://seer/application',
          jsonb_build_object('application_id', v_app.id));

  return jsonb_build_object('application_id', v_app.id, 'status', 'submitted',
                            'replayed', false);
end;
$$;

-- -----------------------------------------------------------------------------
-- withdraw_seer_application
-- -----------------------------------------------------------------------------
create or replace function public.withdraw_seer_application()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_app public.seer_application%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_app from public.seer_application
  where account_id = v_uid and status in ('draft','submitted')
  for update;
  if not found then
    return jsonb_build_object('status', 'withdrawn', 'replayed', true);
  end if;

  update public.seer_application set status = 'withdrawn' where id = v_app.id;
  return jsonb_build_object('application_id', v_app.id, 'status', 'withdrawn',
                            'replayed', false);
end;
$$;

revoke all on function public.save_seer_application(text, text, integer, integer[], bigint)
  from public, anon;
revoke all on function public.submit_seer_application()   from public, anon;
revoke all on function public.withdraw_seer_application() from public, anon;
grant execute on function public.save_seer_application(text, text, integer, integer[], bigint)
  to authenticated;
grant execute on function public.submit_seer_application()   to authenticated;
grant execute on function public.withdraw_seer_application() to authenticated;

-- =============================================================================
-- 7. RPC ฝั่งอนุมัติ — service_role เท่านั้น
--    ยังไม่มี admin console: เรียกผ่าน Studio SQL editor (รันเป็น postgres)
--    วันหน้าทำ console แล้วเรียกผ่าน Edge Function ด้วย service key ได้เลย ไม่ต้องแก้
-- =============================================================================
create or replace function public.admin_review_seer_application(
  p_application_id  uuid,
  p_approve         boolean,
  p_reviewer_label  text,
  p_note            text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app   public.seer_application%rowtype;
  v_sid   integer;
begin
  if p_reviewer_label is null or char_length(btrim(p_reviewer_label)) = 0 then
    raise exception 'missing_reviewer_label';
  end if;

  select * into v_app from public.seer_application
  where id = p_application_id for update;
  if not found then raise exception 'not_found'; end if;

  if v_app.status in ('approved','rejected') then
    return jsonb_build_object('application_id', v_app.id, 'status', v_app.status,
                              'replayed', true);
  end if;
  if v_app.status <> 'submitted' then raise exception 'invalid_state'; end if;

  if not p_approve then
    if p_note is null or char_length(btrim(p_note)) = 0 then
      raise exception 'missing_reject_reason';
    end if;
    update public.seer_application
    set status = 'rejected', reject_reason = p_note,
        decided_at = now(), decided_by_label = p_reviewer_label
    where id = v_app.id;

    insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
    values ('admin', null, 'seer.rejected', 'seer_application', v_app.id::text,
            jsonb_build_object('reviewer', p_reviewer_label, 'reason', p_note));

    insert into public.notification_inbox
      (account_id, notification_type, title, body, deep_link, payload)
    values (v_app.account_id, 'system', 'ใบสมัครยังไม่ผ่าน', p_note,
            'chata://seer/application', jsonb_build_object('application_id', v_app.id));

    return jsonb_build_object('application_id', v_app.id, 'status', 'rejected',
                              'replayed', false);
  end if;

  -- ---- approve ----
  perform 1 from public.seer_profile where account_id = v_app.account_id;
  if found then raise exception 'profile_exists'; end if;

  -- เอกสารที่ยังค้างตรวจของบัญชีนี้ถือว่าผ่านไปพร้อมใบสมัคร
  update public.seer_document
  set review_status = 'approved', reviewed_at = now(), reviewed_by_label = p_reviewer_label
  where account_id = v_app.account_id and review_status = 'pending' and deleted_at is null;

  insert into public.seer_profile
    (account_id, display_name, bio, approval_status, is_active,
     accepts_question, main_skill_id)
  values (v_app.account_id, v_app.display_name, coalesce(v_app.bio, ''),
          'approved', false, false, v_app.main_skill_id);

  foreach v_sid in array coalesce(v_app.skill_ids, '{}') loop
    insert into public.seer_skill (seer_id, skill_id, is_main)
    values (v_app.account_id, v_sid, v_sid = v_app.main_skill_id)
    on conflict do nothing;
  end loop;

  -- is_enabled=false โดยตั้งใจ — หมอดูต้องเข้าแอปมาเปิดรับงานเองเมื่อพร้อม
  insert into public.seer_service (seer_id, service_type_code, price_coin, is_enabled)
  values (v_app.account_id, 'chat_question', coalesce(v_app.price_coin, 0), false);

  -- one-way promotion ตามโมเดลที่เคาะไว้
  update public.account set role = 'seer' where id = v_app.account_id;

  update public.seer_application
  set status = 'approved', decided_at = now(), decided_by_label = p_reviewer_label
  where id = v_app.id;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('admin', null, 'seer.approved', 'account', v_app.account_id::text,
          jsonb_build_object('reviewer', p_reviewer_label, 'application_id', v_app.id));

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_app.account_id, 'system', 'ใบสมัครได้รับอนุมัติ',
          'เปิดรับงานได้จากหน้าโปรไฟล์หมอดูของคุณ', 'chata://seer/profile',
          jsonb_build_object('application_id', v_app.id));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('account', v_app.account_id::text, 'seer.approved',
          jsonb_build_object('account_id', v_app.account_id, 'application_id', v_app.id));

  return jsonb_build_object('application_id', v_app.id, 'status', 'approved',
                            'replayed', false);
end;
$$;

create or replace function public.admin_review_seer_document(
  p_document_id    uuid,
  p_approve        boolean,
  p_reviewer_label text,
  p_reject_reason  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.seer_document%rowtype;
begin
  if p_reviewer_label is null or char_length(btrim(p_reviewer_label)) = 0 then
    raise exception 'missing_reviewer_label';
  end if;

  select * into v_doc from public.seer_document where id = p_document_id for update;
  if not found then raise exception 'not_found'; end if;
  if v_doc.review_status <> 'pending' then
    return jsonb_build_object('document_id', v_doc.id,
                              'review_status', v_doc.review_status, 'replayed', true);
  end if;
  if not p_approve and (p_reject_reason is null or char_length(btrim(p_reject_reason)) = 0) then
    raise exception 'missing_reject_reason';
  end if;

  update public.seer_document
  set review_status = case when p_approve then 'approved' else 'rejected' end,
      reject_reason = case when p_approve then null else p_reject_reason end,
      reviewed_at = now(), reviewed_by_label = p_reviewer_label
  where id = v_doc.id;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('admin', null,
          case when p_approve then 'seer_document.approved' else 'seer_document.rejected' end,
          'seer_document', v_doc.id::text,
          jsonb_build_object('reviewer', p_reviewer_label, 'reason', p_reject_reason));

  if not p_approve then
    insert into public.notification_inbox
      (account_id, notification_type, title, body, deep_link, payload)
    values (v_doc.account_id, 'system', 'เอกสารไม่ผ่านการตรวจสอบ',
            p_reject_reason, 'chata://seer/application',
            jsonb_build_object('document_id', v_doc.id));
  end if;

  return jsonb_build_object('document_id', v_doc.id,
                            'review_status', case when p_approve then 'approved' else 'rejected' end,
                            'replayed', false);
end;
$$;

revoke all on function public.admin_review_seer_application(uuid, boolean, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_review_seer_document(uuid, boolean, text, text)
  from public, anon, authenticated;

-- =============================================================================
-- 8. retire_seer — ลาออกถาวร
--    ห้ามมีงานค้าง: การลาออกต้องไม่เป็นปุ่มลัดยกเลิกงานหมู่
--    (ผู้ใช้ที่รอคำตอบอยู่จะโดนลอยแพเงียบ ๆ) — ให้เคลียร์งานเองก่อน
-- =============================================================================
create or replace function public.retire_seer()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_prof public.seer_profile%rowtype;
  v_open int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_prof from public.seer_profile where account_id = v_uid for update;
  if not found then raise exception 'not_found'; end if;
  if v_prof.retired_at is not null then
    return jsonb_build_object('retired_at', v_prof.retired_at, 'replayed', true);
  end if;

  select count(*) into v_open from public.question
  where seer_id = v_uid and status in ('submitted','active','close_requested');
  if v_open > 0 then
    raise exception 'open_work_exists'
      using errcode = 'P0001',
            detail = format('ยังมีงานค้าง %s รายการ ต้องเคลียร์ให้จบก่อน', v_open);
  end if;

  update public.seer_profile
  set retired_at = now(), is_active = false, accepts_question = false,
      accepts_appointment = false, accepts_tip = false
  where account_id = v_uid;

  update public.seer_service set is_enabled = false where seer_id = v_uid;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('seer', v_uid, 'seer.retired', 'account', v_uid::text, '{}'::jsonb);

  return jsonb_build_object('retired_at', now(), 'replayed', false);
end;
$$;

revoke all on function public.retire_seer() from public, anon;
grant execute on function public.retire_seer() to authenticated;

-- =============================================================================
-- 9. audit + rate limit การแก้ตัวตนของหมอดูหลังอนุมัติ
--    เฟสนี้ไม่บังคับ re-approve (ยังไม่มีคิว/คนเคลียร์ จะกลายเป็นบล็อกรายได้ seer)
--    แต่เก็บหลักฐานครบเพื่อ moderation ย้อนหลัง + กันเปลี่ยนตัวตนรัว ๆ
-- =============================================================================
create or replace function public.audit_seer_identity_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.display_name is distinct from old.display_name
     or new.avatar_url is distinct from old.avatar_url then
    perform public.consume_rate_limit(new.account_id, 'seer_profile_update');
    insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
    values ('seer', new.account_id, 'seer_profile.identity_changed',
            'seer_profile', new.account_id::text,
            jsonb_build_object(
              'old', jsonb_build_object('display_name', old.display_name,
                                        'avatar_url', old.avatar_url),
              'new', jsonb_build_object('display_name', new.display_name,
                                        'avatar_url', new.avatar_url)));
  end if;
  return new;
end;
$$;
revoke all on function public.audit_seer_identity_change() from public, anon, authenticated;

create trigger seer_profile_identity_audit
  before update on public.seer_profile
  for each row
  when (current_user = 'authenticated')
  execute function public.audit_seer_identity_change();

-- =============================================================================
-- 10. submit_question — เพิ่มเงื่อนไข retired_at
--     ฐานคือเวอร์ชันใน 20260827000004 (ที่มี rate limit + block เช็คแล้ว)
-- =============================================================================
create or replace function public.submit_question(
  p_seer_service_id   uuid,
  p_first_message     text,
  p_client_message_id uuid,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_service   record;
  v_available bigint;
  v_question  public.question%rowtype;
  v_deadline  int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_first_message is null or char_length(btrim(p_first_message)) not between 1 and 4000 then
    raise exception 'invalid_message';
  end if;

  select * into v_question
  from public.question
  where user_id = v_uid and client_request_id = p_client_request_id;
  if found then
    return jsonb_build_object('question_id', v_question.id, 'status', v_question.status,
                              'price_coin', v_question.price_coin,
                              'expires_at', v_question.expires_at, 'replayed', true);
  end if;

  perform public.consume_rate_limit(v_uid, 'submit_question');

  select s.id, s.seer_id, s.price_coin, s.is_enabled,
         p.approval_status, p.is_active, p.accepts_question, p.retired_at
  into v_service
  from public.seer_service s
  join public.seer_profile p on p.account_id = s.seer_id
  where s.id = p_seer_service_id
    and s.service_type_code = 'chat_question';

  if not found or not v_service.is_enabled
     or v_service.approval_status <> 'approved'
     or v_service.retired_at is not null
     or not v_service.is_active
     or not v_service.accepts_question then
    raise exception 'seer_unavailable';
  end if;
  if v_service.seer_id = v_uid then
    raise exception 'cannot_ask_yourself';
  end if;

  perform 1 from public.block_relation
  where blocker_id = v_service.seer_id and blocked_id = v_uid;
  if found then
    raise exception 'seer_unavailable';
  end if;

  perform 1 from public.block_relation
  where blocker_id = v_uid and blocked_id = v_service.seer_id;
  if found then
    raise exception 'blocked_by_you';
  end if;

  select available_coin into v_available
  from public.wallet where account_id = v_uid for update;
  if v_available is null then
    raise exception 'wallet_not_found';
  end if;
  if v_available < v_service.price_coin then
    raise exception 'insufficient_coin';
  end if;

  v_deadline := coalesce((public.get_config('question.reply_deadline_hours') #>> '{}')::int, 24);

  insert into public.question
    (user_id, seer_id, seer_service_id, price_coin, client_request_id, expires_at)
  values
    (v_uid, v_service.seer_id, v_service.id, v_service.price_coin, p_client_request_id,
     now() + make_interval(hours => v_deadline))
  returning * into v_question;

  if v_service.price_coin > 0 then
    perform public.internal_post_ledger(
      'question', v_question.id::text, 'reserve',
      jsonb_build_array(
        jsonb_build_object('ledger_account', 'user_available', 'account_id', v_uid,
                           'amount', -v_service.price_coin),
        jsonb_build_object('ledger_account', 'user_reserved', 'account_id', v_uid,
                           'amount', v_service.price_coin)));
  end if;

  insert into public.question_message (question_id, sender_id, client_message_id, message_type, content)
  values (v_question.id, v_uid, p_client_message_id, 'text', btrim(p_first_message));

  insert into public.notification_inbox (account_id, notification_type, title, body, deep_link, payload)
  values (v_service.seer_id, 'question_update', 'มีคำถามใหม่',
          'มีผู้ใช้ส่งคำถามถึงคุณ', 'chata://question/' || v_question.id,
          jsonb_build_object('question_id', v_question.id));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_question.id::text, 'question.submitted',
          jsonb_build_object('question_id', v_question.id, 'seer_id', v_service.seer_id,
                             'price_coin', v_service.price_coin));

  return jsonb_build_object('question_id', v_question.id, 'status', v_question.status,
                            'price_coin', v_question.price_coin,
                            'expires_at', v_question.expires_at, 'replayed', false);
end;
$$;

revoke all on function public.submit_question(uuid, text, uuid, uuid) from public, anon;
grant execute on function public.submit_question(uuid, text, uuid, uuid) to authenticated;
