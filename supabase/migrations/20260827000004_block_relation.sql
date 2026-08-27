-- =============================================================================
-- Chata เฟส 2 (ส่วนที่ 3) — block user
-- implement ตาม docs/specs/phase2-block-and-seer-onboarding.md ส่วน A
--
-- กฎเงิน "blocker forfeits" — ฝ่ายที่กดบล็อกเป็นฝ่ายเสียประโยชน์เสมอ:
--   | state ตอนบล็อก      | seer กด        | user กด        |
--   | submitted           | refund → user  | refund → user  |
--   | active/close_req    | refund → user  | settle → seer  |
--   | completed/cancelled | ไม่แตะ          | ไม่แตะ          |
--
-- ทำไมออกแบบแบบนี้: ลบแรงจูงใจทางการเงินของการบล็อกทิ้งทั้งหมด
--   - seer ฟาร์มเงิน (ตอบหนึ่งบรรทัดแล้วบล็อก) → ได้ 0
--   - user ชักดาบ (ได้คำตอบแล้วบล็อกหนี) → seer ยังได้เงิน
--
-- ⚠️ ผลข้างเคียงที่ user รับทราบและยืนยันแล้ว: คนที่ถูกคุกคามและกดบล็อกเอง
--   จะเป็นฝ่ายเสียเงินด้วย — ต้องมีคำเตือนชัดเจนใน UI ก่อนกดปุ่มบล็อก
--   ทางแก้ระยะยาวคือแยกปุ่ม "รายงาน" ให้ทีมงานตัดสิน (เฟสหน้า ต้องมี admin console ก่อน)
--
-- หลักการ implement: ห้าม copy สูตรเงินมาไว้ในนี้ — เรียก internal_* เท่านั้น
--   (เหตุผลเดียวกับหัวไฟล์ 20260827000001)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ตาราง — การมีแถว = blocked, ลบแถว = unblocked (ไม่มี status column)
-- สองทิศเป็นอิสระต่อกัน: A→B และ B→A อยู่ร่วมกันได้
-- -----------------------------------------------------------------------------
create table public.block_relation (
  blocker_id uuid        not null references public.account (id) on delete cascade,
  blocked_id uuid        not null references public.account (id) on delete cascade,
  reason     text        constraint block_reason_chk check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint block_not_self_chk check (blocker_id <> blocked_id)
);

comment on table public.block_relation is
  'ใครบล็อกใคร ทิศเดียวต่อหนึ่งแถว — เขียนผ่าน RPC เท่านั้นเพราะการบล็อกมีผลต่อเงินที่ escrow ค้าง';
comment on column public.block_relation.reason is
  'บันทึกส่วนตัวของผู้บล็อก ไม่แสดงให้อีกฝ่ายเห็น';

-- PK ครอบทิศ (blocker → blocked) แล้ว; อันนี้สำหรับค้นทิศกลับ
create index block_relation_blocked_idx on public.block_relation (blocked_id);

alter table public.block_relation enable row level security;

-- ผู้บล็อกเห็นรายการของตัวเอง; ฝ่ายที่ถูกบล็อก "อ่านไม่เจอ" ว่าตัวเองโดน
-- (ลด retaliation — ผลของการโดนบล็อกโผล่เป็น error ตอนพยายามซื้อเท่านั้น)
create policy block_relation_blocker_select on public.block_relation
  for select to authenticated
  using (blocker_id = (select auth.uid()));

grant select on public.block_relation to authenticated;
-- ไม่ grant insert/update/delete ให้ใคร — ทุกการเขียนผ่าน RPC

-- -----------------------------------------------------------------------------
-- ขยาย cancel_reason ให้รับ 'blocked'
-- ไม่ยืมค่าเดิม ('seer_reject'/'user_cancel') เพราะระบบเงินจริงต้อง audit ย้อนหลังได้
-- ว่าการคืนเงินก้อนไหนเกิดจากการบล็อก
-- -----------------------------------------------------------------------------
alter table public.question drop constraint question_cancel_reason_chk;
alter table public.question
  add constraint question_cancel_reason_chk
  check (cancel_reason in ('user_cancel', 'seer_timeout', 'seer_reject', 'admin', 'blocked'));

-- -----------------------------------------------------------------------------
-- internal_refund_question — เพิ่ม 'blocked' ใน whitelist
-- ข้อความแจ้งเตือนตกลง else branch (generic) โดยตั้งใจ: ไม่เปิดเผยคำว่า "บล็อก"
-- ให้ฝ่ายที่ถูกบล็อกรู้ตัว
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
  if p_reason not in ('user_cancel', 'seer_timeout', 'seer_reject', 'admin', 'blocked') then
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

revoke all on function public.internal_refund_question(uuid, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- block_account
-- -----------------------------------------------------------------------------
create or replace function public.block_account(
  p_blocked_id uuid,
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_status   text;
  v_q        record;
  v_resolved jsonb := '[]'::jsonb;
  v_result   jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_blocked_id = v_uid then raise exception 'cannot_block_self'; end if;

  perform 1 from public.account where id = p_blocked_id;
  if not found then raise exception 'not_found'; end if;

  select status into v_status from public.account where id = v_uid;
  if v_status <> 'active' then raise exception 'account_not_active'; end if;

  -- idempotent: บล็อกอยู่แล้ว → คืนเลย ไม่วนงานซ้ำ ไม่กินโควตา
  perform 1 from public.block_relation
  where blocker_id = v_uid and blocked_id = p_blocked_id;
  if found then
    return jsonb_build_object('blocked_id', p_blocked_id, 'replayed', true);
  end if;

  perform public.consume_rate_limit(v_uid, 'block_action');

  insert into public.block_relation (blocker_id, blocked_id, reason)
  values (v_uid, p_blocked_id, p_reason);

  -- ปิดงานค้างของคู่นี้ทั้งสองบทบาท เรียงตาม id เพื่อกัน deadlock
  for v_q in
    select id, user_id, seer_id, status
    from public.question
    where status in ('submitted', 'active', 'close_requested')
      and ((user_id = v_uid and seer_id = p_blocked_id)
        or (user_id = p_blocked_id and seer_id = v_uid))
    order by id
    for update
  loop
    if v_q.seer_id = v_uid then
      -- ผู้กดคือหมอดูของงานนี้ → สละรายได้ คืนเงินผู้ถามเสมอ
      perform public.internal_refund_question(v_q.id, 'blocked');
      v_resolved := v_resolved || jsonb_build_object(
        'question_id', v_q.id, 'resolution', 'refunded');
    elsif v_q.status = 'submitted' then
      -- ผู้กดคือผู้ถาม และหมอดูยังไม่ได้ตอบ → คืนเงิน (เท่ากับยกเลิกเอง)
      perform public.internal_refund_question(v_q.id, 'blocked');
      v_resolved := v_resolved || jsonb_build_object(
        'question_id', v_q.id, 'resolution', 'refunded');
    else
      -- ผู้กดคือผู้ถาม และหมอดูตอบแล้ว → สละ escrow จ่ายหมอดูตามส่วนแบ่ง
      perform public.internal_settle_question(v_q.id, true);
      v_resolved := v_resolved || jsonb_build_object(
        'question_id', v_q.id, 'resolution', 'settled');
    end if;
  end loop;

  v_result := jsonb_build_object('blocked_id', p_blocked_id,
                                 'resolved_questions', v_resolved,
                                 'replayed', false);

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values (coalesce(public.current_account_role(), 'user'), v_uid, 'account.blocked',
          'account', p_blocked_id::text,
          jsonb_build_object('resolved_questions', v_resolved));

  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- unblock_account — ไม่แตะเงิน และไม่ undo งานที่ถูกปิดไปตอนบล็อก
-- (ledger เป็น append-only; อยากคุยกันใหม่ = ซื้อคำถามใหม่)
-- -----------------------------------------------------------------------------
create or replace function public.unblock_account(p_blocked_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  perform 1 from public.block_relation
  where blocker_id = v_uid and blocked_id = p_blocked_id;
  if not found then
    return jsonb_build_object('blocked_id', p_blocked_id, 'replayed', true);
  end if;

  perform public.consume_rate_limit(v_uid, 'block_action');

  delete from public.block_relation
  where blocker_id = v_uid and blocked_id = p_blocked_id;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values (coalesce(public.current_account_role(), 'user'), v_uid, 'account.unblocked',
          'account', p_blocked_id::text, '{}'::jsonb);

  return jsonb_build_object('blocked_id', p_blocked_id, 'replayed', false);
end;
$$;

revoke all on function public.block_account(uuid, text) from public, anon;
revoke all on function public.unblock_account(uuid)     from public, anon;
grant execute on function public.block_account(uuid, text) to authenticated;
grant execute on function public.unblock_account(uuid)     to authenticated;

-- -----------------------------------------------------------------------------
-- submit_question — เพิ่มการเช็ค block สองทิศ
-- ฐานคือเวอร์ชันล่าสุดใน 20260827000002 (ที่มี rate limit แล้ว) ห้ามย้อนไปใช้ตัวใน ...09
--
-- ทิศทางของ error ต่างกันโดยตั้งใจ:
--   seer บล็อก user → 'seer_unavailable' (ไม่เผยว่าโดนบล็อก)
--   user บล็อก seer → 'blocked_by_you'  (ผู้ใช้รู้อยู่แล้วว่าตัวเองบล็อกใคร บอกตรง ๆ
--                                        เพื่อให้ UI ชวนปลดบล็อกได้)
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

  -- หมอดูบล็อกเราไว้ → ทำให้เหมือนหมอดูไม่ว่าง ไม่เปิดเผยว่าโดนบล็อก
  perform 1 from public.block_relation
  where blocker_id = v_service.seer_id and blocked_id = v_uid;
  if found then
    raise exception 'seer_unavailable';
  end if;

  -- เราบล็อกหมอดูไว้เอง → บอกตรง ๆ ให้ client ชวนปลดบล็อก
  perform 1 from public.block_relation
  where blocker_id = v_uid and blocked_id = v_service.seer_id;
  if found then
    raise exception 'blocked_by_you';
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
-- rate limit bucket — ครอบทั้ง block และ unblock กัน block/unblock cycling
-- -----------------------------------------------------------------------------
update public.app_config
set value = value || '{"block_action": {"limit": 20, "window_seconds": 3600}}'::jsonb
where key = 'ratelimit.buckets';
