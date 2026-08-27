-- =============================================================================
-- Chata phase 1 — consultation RPCs (client เรียกผ่าน /rpc/*)
-- submit_question, cancel_question, request_close_question,
-- cancel_close_request, respond_close_question
--
-- กติการ่วม: SECURITY DEFINER + search_path='' + lock wallet ก่อนแตะเงิน +
-- compare-and-set state + error เป็น message code ที่ client แปลได้
-- ตัดจาก spec เฟส 1: rate limit (ตาราง rate_limit_counter มาเฟส 2),
-- block_relation check, trial logic (is_trial = false เสมอ), seer_earning projection
-- =============================================================================

-- -----------------------------------------------------------------------------
-- submit_question — ซื้อคำถาม (escrow coin)
-- idempotency: (user_id, client_request_id) unique — retry คืน question เดิม
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

  -- idempotent retry
  select * into v_question
  from public.question
  where user_id = v_uid and client_request_id = p_client_request_id;
  if found then
    return jsonb_build_object('question_id', v_question.id, 'status', v_question.status,
                              'price_coin', v_question.price_coin,
                              'expires_at', v_question.expires_at, 'replayed', true);
  end if;

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

-- -----------------------------------------------------------------------------
-- cancel_question — user ยกเลิกก่อน seer ตอบ (submitted เท่านั้น) → refund
-- -----------------------------------------------------------------------------
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
  if v_q.status <> 'submitted' then
    raise exception 'invalid_state';
  end if;

  perform 1 from public.wallet where account_id = v_q.user_id for update;

  if v_q.price_coin > 0 then
    perform public.internal_post_ledger(
      'question', v_q.id::text, 'refund',
      jsonb_build_array(
        jsonb_build_object('ledger_account', 'user_reserved', 'account_id', v_q.user_id,
                           'amount', -v_q.price_coin),
        jsonb_build_object('ledger_account', 'user_available', 'account_id', v_q.user_id,
                           'amount', v_q.price_coin)));
  end if;

  update public.question
  set status = 'cancelled_refunded', cancel_reason = 'user_cancel'
  where id = v_q.id;

  insert into public.question_message (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system', 'refunded');

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_q.id::text, 'question.refunded',
          jsonb_build_object('question_id', v_q.id, 'reason', 'user_cancel'));

  return jsonb_build_object('question_id', v_q.id, 'status', 'cancelled_refunded');
end;
$$;

-- -----------------------------------------------------------------------------
-- request_close_question — ฝ่ายใดฝ่ายหนึ่งขอปิด (active → close_requested)
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

-- -----------------------------------------------------------------------------
-- cancel_close_request — ผู้ขอถอนคำขอปิดเอง (close_requested → active)
-- -----------------------------------------------------------------------------
create or replace function public.cancel_close_request(p_question_id uuid)
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
  if v_q.status <> 'close_requested' or v_q.close_requested_by <> v_uid then
    raise exception 'invalid_state';
  end if;

  update public.question
  set status = 'active', close_requested_by = null, close_requested_at = null
  where id = v_q.id;

  insert into public.question_message (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system', 'close_cancelled');

  return jsonb_build_object('question_id', v_q.id, 'status', 'active');
end;
$$;

-- -----------------------------------------------------------------------------
-- respond_close_question — อีกฝ่ายตอบคำขอปิด
--   accept=true  → settle escrow → completed (แบ่งตาม seer.default_revenue_share_bps)
--   accept=false → กลับ active
-- -----------------------------------------------------------------------------
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
  v_uid       uuid := auth.uid();
  v_q         public.question%rowtype;
  v_share_bps int;
  v_seer_coin bigint;
  v_fee_coin  bigint;
  v_entries   jsonb;
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

    insert into public.question_message (question_id, sender_id, client_message_id, message_type, system_event)
    values (v_q.id, null, gen_random_uuid(), 'system', 'close_cancelled');

    return jsonb_build_object('question_id', v_q.id, 'status', 'active');
  end if;

  -- settle: lock wallet ทั้งสองฝั่งเรียงตาม account_id (global lock order กัน deadlock)
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

  insert into public.question_message (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system', 'close_confirmed');

  insert into public.notification_inbox (account_id, notification_type, title, body, deep_link, payload)
  values (v_q.user_id, 'question_update', 'คำถามของคุณปิดแล้ว',
          'การปรึกษาเสร็จสิ้น ขอบคุณที่ใช้บริการ', 'chata://question/' || v_q.id,
          jsonb_build_object('question_id', v_q.id));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_q.id::text, 'question.completed',
          jsonb_build_object('question_id', v_q.id, 'seer_id', v_q.seer_id,
                             'price_coin', v_q.price_coin));

  return jsonb_build_object('question_id', v_q.id, 'status', 'completed');
end;
$$;

-- ---------------------------------------------------------------- grants ----
revoke all on function public.submit_question(uuid, text, uuid, uuid) from public, anon;
revoke all on function public.cancel_question(uuid) from public, anon;
revoke all on function public.request_close_question(uuid) from public, anon;
revoke all on function public.cancel_close_request(uuid) from public, anon;
revoke all on function public.respond_close_question(uuid, boolean) from public, anon;

grant execute on function public.submit_question(uuid, text, uuid, uuid) to authenticated;
grant execute on function public.cancel_question(uuid) to authenticated;
grant execute on function public.request_close_question(uuid) to authenticated;
grant execute on function public.cancel_close_request(uuid) to authenticated;
grant execute on function public.respond_close_question(uuid, boolean) to authenticated;
