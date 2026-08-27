-- =============================================================================
-- Chata เฟส 2 (ส่วนที่ 1) — cron + วงจรชีวิตของคำถาม/ออเดอร์
--
-- ปัญหาที่แก้: เฟส 1 จอง (escrow) เหรียญตอนซื้อคำถาม แต่**ไม่มีอะไรปลดล็อกคืน**
--   ถ้า seer ไม่ตอบหรือ user หายไป เหรียญค้างใน user_reserved ตลอดกาล
--   `question.expires_at` และ `payment_order.expires_at` เก็บครบแล้วแต่ไม่มีใครอ่าน
--
-- หลักการ: logic เรื่องเงินต้องอยู่ที่เดียว
--   cron กับ RPC ฝั่ง client ต้องเรียก function ตัวเดียวกัน ไม่งั้นสูตรจะ drift
--   ไฟล์นี้จึงดึง settle/refund ออกมาเป็น internal_* แล้ว replace RPC เดิมให้เรียกมัน
--
-- นโยบายที่ใช้ (ตามที่บันทึกไว้ใน design brief):
--   status='submitted' เกินกำหนด = seer ยังไม่รับงาน  → **คืนเงิน user**
--   status='active'/'close_requested' เกินกำหนด = seer ทำงานแล้ว → **settle ให้ seer**
-- =============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- -----------------------------------------------------------------------------
-- ขยาย system_event: เพิ่ม 'auto_closed' สำหรับงานที่ cron ตัดจบให้
-- (แยกจาก 'close_confirmed' เพื่อให้ดูย้อนหลังได้ว่าใครเป็นคนปิด — คนหรือระบบ)
-- -----------------------------------------------------------------------------
alter table public.question_message
  drop constraint question_message_system_event_chk;
alter table public.question_message
  add constraint question_message_system_event_chk
  check (system_event in ('close_requested', 'close_confirmed', 'close_cancelled',
                          'refunded', 'expired_warning', 'auto_closed'));

-- =============================================================================
-- ส่วนที่ 1 — logic กลาง (แหล่งความจริงเดียวของการคืนเงิน/ตัดจบ)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- internal_refund_question — ปลด escrow คืน user แล้วปิดงานเป็น cancelled_refunded
-- idempotent: เรียกซ้ำกับงานที่คืนแล้วจะคืนสถานะเดิมเฉย ๆ
-- -----------------------------------------------------------------------------
create or replace function public.internal_refund_question(
  p_question_id uuid,
  p_reason      text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_q public.question%rowtype;
begin
  if p_reason not in ('user_cancel', 'seer_timeout', 'seer_reject', 'admin') then
    raise exception 'invalid_refund_reason: %', p_reason using errcode = 'P0001';
  end if;

  select * into v_q from public.question where id = p_question_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if v_q.status = 'cancelled_refunded' then
    return jsonb_build_object('question_id', v_q.id, 'status', v_q.status, 'replayed', true);
  end if;
  if v_q.status in ('completed') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform 1 from public.wallet where account_id = v_q.user_id for update;

  if v_q.price_coin > 0 then
    -- unique (reference_type, reference_id, operation) ทำให้คืนซ้ำไม่ได้แม้ race
    perform public.internal_post_ledger(
      'question', v_q.id::text, 'refund',
      jsonb_build_array(
        jsonb_build_object('ledger_account', 'user_reserved', 'account_id', v_q.user_id,
                           'amount', -v_q.price_coin),
        jsonb_build_object('ledger_account', 'user_available', 'account_id', v_q.user_id,
                           'amount', v_q.price_coin)));
  end if;

  update public.question
  set status = 'cancelled_refunded', cancel_reason = p_reason
  where id = v_q.id;

  insert into public.question_message
    (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system', 'refunded');

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_q.user_id, 'question_update',
          case p_reason
            when 'seer_timeout' then 'คืนเหรียญแล้ว — หมอดูไม่ได้ตอบในเวลาที่กำหนด'
            else 'คำถามถูกยกเลิกและคืนเหรียญแล้ว'
          end,
          format('คืน %s เหรียญเข้ากระเป๋าของคุณแล้ว', v_q.price_coin),
          'chata://question/' || v_q.id,
          jsonb_build_object('question_id', v_q.id, 'reason', p_reason));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_q.id::text, 'question.refunded',
          jsonb_build_object('question_id', v_q.id, 'user_id', v_q.user_id,
                             'seer_id', v_q.seer_id, 'reason', p_reason,
                             'price_coin', v_q.price_coin));

  return jsonb_build_object('question_id', v_q.id, 'status', 'cancelled_refunded',
                            'reason', p_reason, 'refunded_coin', v_q.price_coin);
end;
$$;

-- -----------------------------------------------------------------------------
-- internal_settle_question — ตัดจบงาน จ่าย seer + เก็บส่วนแบ่งแพลตฟอร์ม
-- p_system = true เมื่อมาจาก cron (ข้อความ/แจ้งเตือนต่างจากตอน user กดยอมรับ)
-- -----------------------------------------------------------------------------
create or replace function public.internal_settle_question(
  p_question_id uuid,
  p_system      boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_q         public.question%rowtype;
  v_share_bps int;
  v_seer_coin bigint;
  v_fee_coin  bigint;
  v_entries   jsonb;
begin
  select * into v_q from public.question where id = p_question_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if v_q.status = 'completed' then
    return jsonb_build_object('question_id', v_q.id, 'status', v_q.status, 'replayed', true);
  end if;
  if v_q.status not in ('active', 'close_requested') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  -- lock กระเป๋าทั้งสองฝั่งเรียงตาม account_id — global lock order กัน deadlock
  perform 1 from public.wallet
  where account_id in (v_q.user_id, v_q.seer_id)
  order by account_id
  for update;

  if v_q.price_coin > 0 then
    v_share_bps := coalesce((public.get_config('seer.default_revenue_share_bps') #>> '{}')::int, 7000);
    v_seer_coin := (v_q.price_coin * v_share_bps) / 10000;
    v_fee_coin  := v_q.price_coin - v_seer_coin;

    v_entries := jsonb_build_array(
      jsonb_build_object('ledger_account', 'user_reserved', 'account_id', v_q.user_id,
                         'amount', -v_q.price_coin),
      jsonb_build_object('ledger_account', 'seer_payable', 'account_id', v_q.seer_id,
                         'amount', v_seer_coin));
    if v_fee_coin > 0 then
      v_entries := v_entries
        || jsonb_build_object('ledger_account', 'platform_revenue', 'account_id', null,
                              'amount', v_fee_coin);
    end if;

    perform public.internal_post_ledger('question', v_q.id::text, 'settle', v_entries);
  end if;

  update public.question
  set status = 'completed', completed_at = now()
  where id = v_q.id;

  update public.seer_profile
  set question_count = question_count + 1
  where account_id = v_q.seer_id;

  insert into public.question_message
    (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system',
          case when p_system then 'auto_closed' else 'close_confirmed' end);

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_q.user_id, 'question_update',
          case when p_system then 'คำถามถูกปิดอัตโนมัติ' else 'คำถามของคุณปิดแล้ว' end,
          case when p_system then 'ครบกำหนดเวลาของการปรึกษาแล้ว'
               else 'การปรึกษาเสร็จสิ้น ขอบคุณที่ใช้บริการ' end,
          'chata://question/' || v_q.id,
          jsonb_build_object('question_id', v_q.id));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_q.id::text, 'question.completed',
          jsonb_build_object('question_id', v_q.id, 'user_id', v_q.user_id,
                             'seer_id', v_q.seer_id, 'price_coin', v_q.price_coin,
                             'auto_closed', p_system));

  return jsonb_build_object('question_id', v_q.id, 'status', 'completed',
                            'auto_closed', p_system);
end;
$$;

revoke all on function public.internal_refund_question(uuid, text) from public, anon, authenticated;
revoke all on function public.internal_settle_question(uuid, boolean) from public, anon, authenticated;

-- =============================================================================
-- ส่วนที่ 2 — replace RPC เดิมให้เรียก logic กลาง (เลิกมีสูตรเงินสองที่)
-- =============================================================================

create or replace function public.cancel_question(p_question_id uuid)
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
  if not found or v_q.user_id <> v_uid then
    raise exception 'not_found';
  end if;
  if v_q.status = 'cancelled_refunded' then
    return jsonb_build_object('question_id', v_q.id, 'status', v_q.status, 'replayed', true);
  end if;
  -- ยกเลิกเองได้เฉพาะตอนที่ seer ยังไม่รับงาน
  if v_q.status <> 'submitted' then
    raise exception 'invalid_state';
  end if;

  return public.internal_refund_question(v_q.id, 'user_cancel');
end;
$$;

create or replace function public.respond_close_question(
  p_question_id uuid,
  p_accept      boolean
)
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
  if v_q.status = 'completed' then
    return jsonb_build_object('question_id', v_q.id, 'status', v_q.status, 'replayed', true);
  end if;
  if v_q.status <> 'close_requested' then
    raise exception 'invalid_state';
  end if;
  if v_q.close_requested_by = v_uid then
    raise exception 'self_response'; -- คนขอปิดตอบรับคำขอตัวเองไม่ได้
  end if;

  if not p_accept then
    update public.question
    set status = 'active', close_requested_by = null, close_requested_at = null
    where id = v_q.id;

    insert into public.question_message
      (question_id, sender_id, client_message_id, message_type, system_event)
    values (v_q.id, null, gen_random_uuid(), 'system', 'close_cancelled');

    return jsonb_build_object('question_id', v_q.id, 'status', 'active');
  end if;

  return public.internal_settle_question(v_q.id, false);
end;
$$;

revoke all on function public.cancel_question(uuid) from public, anon;
revoke all on function public.respond_close_question(uuid, boolean) from public, anon;
grant execute on function public.cancel_question(uuid) to authenticated;
grant execute on function public.respond_close_question(uuid, boolean) to authenticated;

-- =============================================================================
-- ส่วนที่ 3 — job (แต่ละตัวรับ p_limit กันงานค้างยาวและ lock นาน)
-- ทุก job จับ exception รายแถว: หนึ่งงานพังต้องไม่ทำให้ทั้ง batch ล้ม
-- =============================================================================

-- -----------------------------------------------------------------------------
-- seer ไม่รับงานภายในกำหนด → คืนเงิน
-- -----------------------------------------------------------------------------
create or replace function public.job_refund_unanswered_questions(p_limit int default 200)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id       uuid;
  v_ok       int := 0;
  v_failed   int := 0;
  v_deadline int;
begin
  v_deadline := coalesce((public.get_config('question.reply_deadline_hours') #>> '{}')::int, 24);

  for v_id in
    select id from public.question
    where status = 'submitted'
      and created_at < now() - make_interval(hours => v_deadline)
    order by created_at
    limit p_limit
    for update skip locked
  loop
    begin
      perform public.internal_refund_question(v_id, 'seer_timeout');
      v_ok := v_ok + 1;
    exception when others then
      v_failed := v_failed + 1;
      insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
      values ('system', null, 'job_refund_unanswered_failed', 'question', v_id::text,
              jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('job', 'refund_unanswered_questions',
                            'deadline_hours', v_deadline, 'refunded', v_ok, 'failed', v_failed);
end;
$$;

-- -----------------------------------------------------------------------------
-- งานที่ seer ทำแล้วแต่ค้างเกินอายุสูงสุด → ตัดจบจ่าย seer
-- -----------------------------------------------------------------------------
create or replace function public.job_autoclose_stale_questions(p_limit int default 200)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid;
  v_ok     int := 0;
  v_failed int := 0;
  v_maxage int;
begin
  v_maxage := coalesce((public.get_config('question.max_active_hours') #>> '{}')::int, 72);

  for v_id in
    select id from public.question
    where status in ('active', 'close_requested')
      and created_at < now() - make_interval(hours => v_maxage)
    order by created_at
    limit p_limit
    for update skip locked
  loop
    begin
      perform public.internal_settle_question(v_id, true);
      v_ok := v_ok + 1;
    exception when others then
      v_failed := v_failed + 1;
      insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
      values ('system', null, 'job_autoclose_failed', 'question', v_id::text,
              jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('job', 'autoclose_stale_questions',
                            'max_active_hours', v_maxage, 'closed', v_ok, 'failed', v_failed);
end;
$$;

-- -----------------------------------------------------------------------------
-- ออเดอร์เติมเงินที่ค้างเกินอายุ → ปิดเป็น expired
-- ไม่แตะ ledger เพราะยังไม่เคย credit — แค่เก็บกวาดสถานะ
-- -----------------------------------------------------------------------------
create or replace function public.job_expire_payment_orders(p_limit int default 500)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with stale as (
    select id from public.payment_order
    where status in ('created', 'pending_provider')
      and expires_at < now()
    order by expires_at
    limit p_limit
    for update skip locked
  )
  update public.payment_order o
  set status = 'expired',
      failure_reason = coalesce(o.failure_reason, 'expired_by_cron')
  from stale
  where o.id = stale.id;

  get diagnostics v_count = row_count;
  return jsonb_build_object('job', 'expire_payment_orders', 'expired', v_count);
end;
$$;

-- -----------------------------------------------------------------------------
-- reconcile: wallet ต้องตรงกับ ledger เสมอ ไม่ตรง = มีบั๊กเรื่องเงิน
-- ตรวจอย่างเดียว ไม่แก้ยอดอัตโนมัติ — ยอดเงินผิดต้องมีคนดู ไม่ใช่ให้เครื่องเดา
-- -----------------------------------------------------------------------------
create or replace function public.job_reconcile_wallets()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_drift   int := 0;
  v_zerosum bigint;
  v_row     record;
begin
  for v_row in
    with led as (
      select account_id,
             coalesce(sum(amount) filter (where ledger_account = 'user_available'), 0) av,
             coalesce(sum(amount) filter (where ledger_account = 'user_reserved'), 0)  rs,
             coalesce(sum(amount) filter (where ledger_account = 'seer_payable'), 0)   pa
      from public.ledger_entry
      where account_id is not null
      group by account_id
    )
    select w.account_id, w.available_coin, w.reserved_coin, w.payable_coin,
           coalesce(l.av, 0) av, coalesce(l.rs, 0) rs, coalesce(l.pa, 0) pa
    from public.wallet w
    left join led l on l.account_id = w.account_id
    where w.available_coin <> coalesce(l.av, 0)
       or w.reserved_coin  <> coalesce(l.rs, 0)
       or w.payable_coin   <> coalesce(l.pa, 0)
  loop
    v_drift := v_drift + 1;
    insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
    values ('system', null, 'wallet_ledger_drift', 'wallet', v_row.account_id::text,
            jsonb_build_object(
              'wallet', jsonb_build_object('available', v_row.available_coin,
                                           'reserved', v_row.reserved_coin,
                                           'payable', v_row.payable_coin),
              'ledger', jsonb_build_object('available', v_row.av,
                                           'reserved', v_row.rs,
                                           'payable', v_row.pa)));
  end loop;

  -- invariant ระดับระบบ: ทุกขาของทุก transaction รวมกันต้องเป็นศูนย์
  select coalesce(sum(amount), 0) into v_zerosum from public.ledger_entry;
  if v_zerosum <> 0 then
    insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
    values ('system', null, 'ledger_zero_sum_violation', 'ledger', 'global',
            jsonb_build_object('sum', v_zerosum));
  end if;

  return jsonb_build_object('job', 'reconcile_wallets',
                            'drift_accounts', v_drift, 'ledger_sum', v_zerosum);
end;
$$;

revoke all on function public.job_refund_unanswered_questions(int) from public, anon, authenticated;
revoke all on function public.job_autoclose_stale_questions(int)  from public, anon, authenticated;
revoke all on function public.job_expire_payment_orders(int)      from public, anon, authenticated;
revoke all on function public.job_reconcile_wallets()             from public, anon, authenticated;

-- =============================================================================
-- ส่วนที่ 4 — ตั้งเวลา
-- เวลาทั้งหมดเป็น UTC; unschedule ก่อนเพื่อให้ migration รันซ้ำได้
-- =============================================================================

do $$
declare
  v_job text;
begin
  foreach v_job in array array[
    'chata_refund_unanswered_questions',
    'chata_autoclose_stale_questions',
    'chata_expire_payment_orders',
    'chata_reconcile_wallets'
  ] loop
    if exists (select 1 from cron.job where jobname = v_job) then
      perform cron.unschedule(v_job);
    end if;
  end loop;
end $$;

-- ทุก 10 นาที: เหรียญที่ควรได้คืน ไม่ควรค้างนานกว่านี้
select cron.schedule('chata_refund_unanswered_questions', '*/10 * * * *',
  $$select public.job_refund_unanswered_questions();$$);

-- ทุก 15 นาที
select cron.schedule('chata_autoclose_stale_questions', '*/15 * * * *',
  $$select public.job_autoclose_stale_questions();$$);

-- ทุก 15 นาที
select cron.schedule('chata_expire_payment_orders', '*/15 * * * *',
  $$select public.job_expire_payment_orders();$$);

-- ทุกวัน 19:00 UTC = 02:00 ตามเวลาไทย (ช่วงคนใช้งานน้อย)
select cron.schedule('chata_reconcile_wallets', '0 19 * * *',
  $$select public.job_reconcile_wallets();$$);

comment on function public.internal_refund_question(uuid, text) is
  'แหล่งความจริงเดียวของการคืนเหรียญคำถาม — เรียกจาก cancel_question และ cron เท่านั้น';
comment on function public.internal_settle_question(uuid, boolean) is
  'แหล่งความจริงเดียวของการตัดจบจ่าย seer — เรียกจาก respond_close_question และ cron เท่านั้น';
