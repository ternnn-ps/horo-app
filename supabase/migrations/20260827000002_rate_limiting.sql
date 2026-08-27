-- =============================================================================
-- Chata เฟส 2 (ส่วนที่ 2) — rate limiting
--
-- ปัญหา: เฟส 1 ไม่มีอะไรจำกัดความถี่เลย ผู้ใช้ที่ login แล้วยิง submit_question
--   หรือ insert question_message รัวได้ไม่จำกัด — เปลืองพื้นที่ free tier,
--   สร้าง notification สแปมใส่ seer, และทำให้ระบบช้าลงทั้งระบบ
--
-- วิธี: fixed-window counter เก็บในตาราง อ่านเพดานจาก app_config
--   เปลี่ยนเพดานได้โดยไม่ต้อง migration (ปรับจริงตอนเจอ traffic จริง)
--
-- ⚠️ ขอบเขตที่ทำได้จริง — ต้องเข้าใจก่อนใช้:
--   counter เพิ่มใน transaction เดียวกับงาน ถ้างานถูกปฏิเสธ counter ก็ rollback ด้วย
--   → จำกัด "งานที่สำเร็จ" ไม่ได้จำกัด "จำนวนครั้งที่ยิงเข้ามา"
--   ป้องกันสแปม/abuse ได้ แต่**ไม่ใช่เครื่องมือกัน DoS**
--   การกัน DoS จริงต้องทำที่ขอบ (Supabase API gateway / Cloudflare) ไม่ใช่ในฐานข้อมูล
--
--   ข้อจำกัดของ fixed window: ยิงเต็มโควตาท้ายหน้าต่างเก่าแล้วต่อด้วยต้นหน้าต่างใหม่
--   จะได้ 2 เท่าในช่วงสั้น ๆ ยอมรับได้สำหรับ use case นี้ (sliding window แพงกว่ามาก)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ตารางนับ — deny-all ไม่ให้ client มองเห็นหรือแตะ
-- -----------------------------------------------------------------------------
create table public.rate_limit_counter (
  account_id   uuid        not null references public.account (id) on delete cascade,
  bucket       text        not null,
  window_start timestamptz not null,
  hits         integer     not null default 0
               constraint rate_limit_hits_chk check (hits >= 0),
  primary key (account_id, bucket, window_start)
);

comment on table public.rate_limit_counter is
  'ตัวนับ fixed-window ต่อ (บัญชี, bucket, ช่วงเวลา) — เขียนโดย consume_rate_limit เท่านั้น';

-- index สำหรับ job เก็บกวาดของเก่า
create index rate_limit_window_idx on public.rate_limit_counter (window_start);

alter table public.rate_limit_counter enable row level security;
-- ไม่มี policy = deny-all; ไม่มี GRANT ให้ anon/authenticated

-- -----------------------------------------------------------------------------
-- เพดานเริ่มต้น — ปรับได้ทาง app_config โดยไม่ต้อง migration
-- ตัวเลขตั้งจากพฤติกรรมปกติของคนใช้จริง ไม่ใช่จากความสามารถของเครื่อง
-- -----------------------------------------------------------------------------
insert into public.app_config (key, value, is_public, description) values
  ('ratelimit.buckets',
   '{
      "submit_question":  {"limit": 10,  "window_seconds": 3600},
      "question_message": {"limit": 120, "window_seconds": 3600},
      "close_action":     {"limit": 60,  "window_seconds": 3600}
    }'::jsonb,
   false,
   'เพดาน rate limit ต่อบัญชีต่อ bucket — limit ครั้งต่อ window_seconds วินาที')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- consume_rate_limit — นับหนึ่งครั้ง; เกินเพดานให้ raise 'rate_limited'
-- bucket ที่ไม่มีใน config = ไม่จำกัด (fail-open โดยตั้งใจ:
--   config พังไม่ควรทำให้ทั้งแอปใช้งานไม่ได้ — แต่ต้องมี alert ถ้าเกิดขึ้น)
-- -----------------------------------------------------------------------------
create or replace function public.consume_rate_limit(
  p_account_id uuid,
  p_bucket     text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg    jsonb;
  v_limit  int;
  v_window int;
  v_start  timestamptz;
  v_hits   int;
begin
  if p_account_id is null then
    raise exception 'not_authenticated';
  end if;

  v_cfg := public.get_config('ratelimit.buckets') -> p_bucket;
  if v_cfg is null then
    return; -- ไม่ได้ตั้งเพดานไว้ = ไม่จำกัด
  end if;

  v_limit  := coalesce((v_cfg ->> 'limit')::int, 0);
  v_window := coalesce((v_cfg ->> 'window_seconds')::int, 3600);
  if v_limit <= 0 or v_window <= 0 then
    return;
  end if;

  -- ต้นหน้าต่างปัจจุบัน = ปัดเวลาลงตามความยาวหน้าต่าง
  v_start := to_timestamp(floor(extract(epoch from now()) / v_window) * v_window);

  insert into public.rate_limit_counter (account_id, bucket, window_start, hits)
  values (p_account_id, p_bucket, v_start, 1)
  on conflict (account_id, bucket, window_start)
  do update set hits = public.rate_limit_counter.hits + 1
  returning hits into v_hits;

  if v_hits > v_limit then
    raise exception 'rate_limited'
      using errcode = 'P0001',
            detail  = format('bucket=%s limit=%s per %ss', p_bucket, v_limit, v_window),
            hint    = format('ลองใหม่หลัง %s', v_start + make_interval(secs => v_window));
  end if;
end;
$$;

revoke all on function public.consume_rate_limit(uuid, text) from public, anon, authenticated;

comment on function public.consume_rate_limit(uuid, text) is
  'นับและบังคับเพดานความถี่ — เรียกจาก RPC/trigger ที่เป็น SECURITY DEFINER เท่านั้น. '
  'จำกัดงานที่สำเร็จ ไม่ใช่จำนวนครั้งที่ยิงเข้ามา (ดูหมายเหตุหัวไฟล์)';

-- =============================================================================
-- ผูกเข้ากับเส้นทางที่ถูกใช้งานจริง
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) submit_question — จุดเช็คอยู่ "หลัง" idempotent retry
--    retry จาก network ที่หลุดไม่ควรกินโควตาของผู้ใช้
--    และอยู่ "ก่อน" ทุกอย่างที่แพง (lock wallet, ledger, insert)
-- -----------------------------------------------------------------------------
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

  -- idempotent retry — ต้องมาก่อน rate limit
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
         p.approval_status, p.is_active, p.accepts_question
  into v_service
  from public.seer_service s
  join public.seer_profile p on p.account_id = s.seer_id
  where s.id = p_seer_service_id
    and s.service_type_code = 'chat_question';

  if not found or not v_service.is_enabled
     or v_service.approval_status <> 'approved'
     or not v_service.is_active
     or not v_service.accepts_question then
    raise exception 'seer_unavailable';
  end if;
  if v_service.seer_id = v_uid then
    raise exception 'cannot_ask_yourself';
  end if;

  -- lock wallet ผู้ซื้อ (serialization point) แล้วเช็คยอดให้ error สะอาด
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

-- -----------------------------------------------------------------------------
-- 2) question_message — insert ตรงผ่าน RLS ไม่ผ่าน RPC จึงต้องใช้ trigger
--    นับเฉพาะข้อความที่คนส่ง; ข้อความระบบ (sender_id is null) ไม่นับ
-- -----------------------------------------------------------------------------
create or replace function public.enforce_message_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.sender_id is not null then
    perform public.consume_rate_limit(new.sender_id, 'question_message');
  end if;
  return new;
end;
$$;

create trigger question_message_rate_limit
  before insert on public.question_message
  for each row execute function public.enforce_message_rate_limit();

-- -----------------------------------------------------------------------------
-- 3) close flow — ป้องกันการกดขอปิด/ยกเลิกรัวจนสร้าง system message ท่วม
-- -----------------------------------------------------------------------------
create or replace function public.request_close_question(p_question_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_q   public.question%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_q from public.question where id = p_question_id for update;
  if not found or v_uid not in (v_q.user_id, v_q.seer_id) then
    raise exception 'not_found';
  end if;
  if v_q.status = 'close_requested' and v_q.close_requested_by = v_uid then
    return jsonb_build_object('question_id', v_q.id, 'status', v_q.status, 'replayed', true);
  end if;
  if v_q.status <> 'active' then
    raise exception 'invalid_state';
  end if;

  -- บรรทัดเดียวที่เพิ่มจากเดิม: นับโควตาหลังผ่าน replay/state check แล้ว
  perform public.consume_rate_limit(v_uid, 'close_action');

  update public.question
  set status = 'close_requested', close_requested_by = v_uid, close_requested_at = now()
  where id = v_q.id;

  insert into public.question_message (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system', 'close_requested');

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_q.id::text, 'question.close_requested',
          jsonb_build_object('question_id', v_q.id, 'requested_by', v_uid));

  return jsonb_build_object('question_id', v_q.id, 'status', 'close_requested');
end;
$$;

revoke all on function public.request_close_question(uuid) from public, anon;
grant execute on function public.request_close_question(uuid) to authenticated;

-- =============================================================================
-- เก็บกวาด counter เก่า — ไม่ลบก็โตไม่หยุด (free tier มีแค่ 500MB)
-- เก็บย้อนหลัง 2 วันไว้ debug/ดู pattern การ abuse
-- =============================================================================
create or replace function public.job_purge_rate_limit_counters(p_keep_days int default 2)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  delete from public.rate_limit_counter
  where window_start < now() - make_interval(days => p_keep_days);
  get diagnostics v_count = row_count;
  return jsonb_build_object('job', 'purge_rate_limit_counters', 'deleted', v_count);
end;
$$;

revoke all on function public.job_purge_rate_limit_counters(int) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'chata_purge_rate_limit_counters') then
    perform cron.unschedule('chata_purge_rate_limit_counters');
  end if;
end $$;

-- ทุกวัน 20:00 UTC = 03:00 เวลาไทย
select cron.schedule('chata_purge_rate_limit_counters', '0 20 * * *',
  $$select public.job_purge_rate_limit_counters();$$);
