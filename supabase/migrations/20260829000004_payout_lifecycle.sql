-- =============================================================================
-- ปิดวงจรการถอน — อนุมัติ / ปฏิเสธ / โอนจริง / หมอดูยกเลิกเอง
--
-- กติกาเรื่องเงินของก้อนนี้มีข้อเดียวแต่สำคัญมาก:
--   เหรียญออกจาก seer_payable ไปแล้วตั้งแต่ตอน `requested` (ดู 20260829000003)
--   ดังนั้น **การจ่ายจริงไม่แตะเงินอีก** — สิ่งที่แตะเงินคือทางที่ "ไม่ได้จ่าย" เท่านั้น
--   คือ reject กับ cancel ซึ่งต้องคืนด้วย **reversing entry** ไม่ใช่โพสต์ขาบวกใหม่
--
-- ทำไมต้อง reversing entry: ledger เป็น append-only ห้ามแก้แถวเดิม และการชี้
-- `reversal_of` กลับไปต้นฉบับทำให้ตรวจสอบย้อนหลังได้ว่าเงินก้อนไหนถูกกลับรายการ
-- ส่วนตัวกันกลับซ้ำคือ unique index บน reversal_of ที่มีอยู่แล้ว ไม่ใช่โค้ด
-- =============================================================================

-- =============================================================================
-- internal_reverse_payout — คืนเหรียญเข้ายอดค้างจ่ายด้วยรายการกลับรายการ
-- =============================================================================
create or replace function public.internal_reverse_payout(p_payout_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req    public.payout_request%rowtype;
  v_origin uuid;
begin
  select * into v_req from public.payout_request where id = p_payout_request_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  select id into v_origin from public.ledger_transaction
  where reference_type = 'payout_request'
    and reference_id = p_payout_request_id::text
    and operation = 'payout';
  if not found then
    raise exception 'origin_transaction_missing' using errcode = 'P0002';
  end if;

  return public.internal_post_ledger(
    'payout_request', p_payout_request_id::text, 'reversal',
    jsonb_build_array(
      jsonb_build_object('ledger_account', 'coin_supply', 'account_id', null,
                         'amount', -v_req.coin_amount),
      jsonb_build_object('ledger_account', 'seer_payable', 'account_id', v_req.seer_id,
                         'amount', v_req.coin_amount)),
    v_origin,
    'คืนเหรียญจากคำขอถอนที่ไม่ได้จ่าย');
end;
$$;

revoke all on function public.internal_reverse_payout(uuid) from public, anon, authenticated;

-- =============================================================================
-- cancel_payout_request — หมอดูยกเลิกคำขอของตัวเองก่อนเงินโอนออก
-- =============================================================================
create or replace function public.cancel_payout_request(p_payout_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me  uuid := (select auth.uid());
  v_req public.payout_request%rowtype;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select * into v_req from public.payout_request
  where id = p_payout_request_id and seer_id = v_me
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if v_req.status = 'paid' then
    raise exception 'already_paid' using errcode = 'P0001';
  end if;
  if v_req.status in ('cancelled', 'rejected') then
    -- ยกเลิกซ้ำต้องไม่คืนเหรียญรอบสอง
    return jsonb_build_object('payout_request_id', v_req.id,
                              'status', v_req.status, 'replayed', true);
  end if;

  perform 1 from public.wallet where account_id = v_me for update;
  perform public.internal_reverse_payout(v_req.id);

  update public.payout_request
  set status = 'cancelled'
  where id = v_req.id;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('seer', v_me, 'payout_request.cancelled', 'payout_request', v_req.id::text,
          jsonb_build_object('coin_amount', v_req.coin_amount));

  return jsonb_build_object('payout_request_id', v_req.id, 'status', 'cancelled',
                            'replayed', false);
end;
$$;

grant execute on function public.cancel_payout_request(uuid) to authenticated;

-- =============================================================================
-- admin_review_payout — อนุมัติ / ปฏิเสธ / บันทึกว่าโอนแล้ว
--
-- รวมสามการกระทำไว้ใน RPC เดียวโดยตั้งใจ: ทั้งสามเป็นการเลื่อนสถานะของคำขอเดียวกัน
-- และต้องล็อกแถวเดียวกัน แยกเป็นสาม RPC จะเปิดช่องให้เรียกสลับลำดับกันได้
-- =============================================================================
create or replace function public.admin_review_payout(
  p_payout_request_id uuid,
  p_action            text,
  p_reviewer_label    text,
  p_reason            text default null,
  p_provider_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.payout_request%rowtype;
begin
  if p_action not in ('approve', 'reject', 'mark_paid') then
    raise exception 'unknown_action: %', p_action using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_reviewer_label), '') = '' then
    raise exception 'missing_reviewer_label' using errcode = 'P0001';
  end if;

  select * into v_req from public.payout_request
  where id = p_payout_request_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if p_action = 'approve' then
    if v_req.status = 'approved' then
      return jsonb_build_object('payout_request_id', v_req.id, 'status', 'approved', 'replayed', true);
    end if;
    if v_req.status <> 'requested' then
      raise exception 'invalid_state: %', v_req.status using errcode = 'P0001';
    end if;

    update public.payout_request
    set status = 'approved', reviewed_by_label = btrim(p_reviewer_label)
    where id = v_req.id;

  elsif p_action = 'reject' then
    if coalesce(btrim(p_reason), '') = '' then
      raise exception 'missing_reject_reason' using errcode = 'P0001';
    end if;
    if v_req.status = 'rejected' then
      return jsonb_build_object('payout_request_id', v_req.id, 'status', 'rejected', 'replayed', true);
    end if;
    if v_req.status not in ('requested', 'approved') then
      raise exception 'invalid_state: %', v_req.status using errcode = 'P0001';
    end if;

    perform 1 from public.wallet where account_id = v_req.seer_id for update;
    perform public.internal_reverse_payout(v_req.id);

    update public.payout_request
    set status = 'rejected',
        reject_reason = btrim(p_reason),
        reviewed_by_label = btrim(p_reviewer_label)
    where id = v_req.id;

  else -- mark_paid
    -- เลขอ้างอิงคือหลักฐานเดียวที่โยงรายการนี้กับ statement ธนาคาร ปล่อยว่างไม่ได้
    if coalesce(btrim(p_provider_reference), '') = '' then
      raise exception 'missing_provider_reference' using errcode = 'P0001';
    end if;
    if v_req.status = 'paid' then
      return jsonb_build_object('payout_request_id', v_req.id, 'status', 'paid', 'replayed', true);
    end if;
    if v_req.status <> 'approved' then
      raise exception 'invalid_state: ต้องอนุมัติก่อนถึงจะบันทึกว่าโอนแล้ว (%)', v_req.status
        using errcode = 'P0001';
    end if;

    -- ไม่แตะ ledger เลย: เหรียญออกไปตั้งแต่ตอนขอแล้ว
    update public.payout_request
    set status = 'paid',
        provider_reference = btrim(p_provider_reference),
        paid_at = now(),
        reviewed_by_label = btrim(p_reviewer_label)
    where id = v_req.id;
  end if;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('admin', null, 'payout_request.' || p_action, 'payout_request', v_req.id::text,
          jsonb_build_object('reviewer', btrim(p_reviewer_label),
                             'reason', p_reason,
                             'provider_reference', p_provider_reference,
                             'coin_amount', v_req.coin_amount));

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_req.seer_id, 'payout',
          case p_action
            when 'approve'   then 'คำขอถอนได้รับการอนุมัติ'
            when 'reject'    then 'คำขอถอนไม่ผ่าน'
            else                  'โอนเงินเรียบร้อยแล้ว'
          end,
          case p_action
            when 'approve'   then 'กำลังดำเนินการโอน'
            when 'reject'    then btrim(p_reason)
            else                  'เลขอ้างอิง ' || btrim(p_provider_reference)
          end,
          'chata://seer/payout',
          jsonb_build_object('payout_request_id', v_req.id));

  return jsonb_build_object('payout_request_id', v_req.id, 'action', p_action, 'replayed', false);
end;
$$;

-- =============================================================================
-- admin_payout_queue — คิวของแอดมิน เรียงตามรอนานสุด
--
-- `p_stale_hours` ใช้หาคำขอที่ค้างเกินกำหนด — ส่ง 0 เพื่อดูทั้งคิว
-- =============================================================================
create or replace function public.admin_payout_queue(p_stale_hours int default 168)
returns table (
  payout_request_id uuid,
  seer_id           uuid,
  status            text,
  coin_amount       bigint,
  fiat_amount_minor bigint,
  bank_code         text,
  account_last4     text,
  holder_name       text,
  waiting_hours     numeric,
  created_at        timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    r.id, r.seer_id, r.status, r.coin_amount, r.fiat_amount_minor,
    a.bank_code, a.account_number_last4, a.account_holder_name,
    round(extract(epoch from (now() - r.created_at)) / 3600, 1),
    r.created_at
  from public.payout_request r
  join public.payout_account a on a.id = r.payout_account_id
  where r.status in ('requested', 'approved')
    and r.created_at <= now() - make_interval(hours => coalesce(p_stale_hours, 0))
  order by r.created_at;
$$;

revoke all on function public.admin_review_payout(uuid, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_payout_queue(int)
  from public, anon, authenticated;
