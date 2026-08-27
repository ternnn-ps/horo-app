-- =============================================================================
-- Chata phase 1 — money internals
-- internal_post_ledger / internal_credit_payment / internal_fail_payment
-- ทั้งหมด: SECURITY DEFINER, search_path='', ห้าม authenticated เรียก (service_role/RPC อื่นเท่านั้น)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- internal_post_ledger — ทางเขียน ledger ทางเดียวของทั้งระบบ (spec §5.3)
-- p_entries: [{"ledger_account": "...", "account_id": "uuid|null", "amount": 123}, ...]
-- เงื่อนไข: ผู้เรียกต้อง lock แถว wallet ของทุกบัญชีที่แตะไว้แล้ว (FOR UPDATE)
-- idempotent: business reference ชน → คืน transaction id เดิม ไม่ post ซ้ำ
-- -----------------------------------------------------------------------------
create or replace function public.internal_post_ledger(
  p_reference_type text,
  p_reference_id   text,
  p_operation      text,
  p_entries        jsonb,
  p_reversal_of    uuid default null,
  p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tx      uuid;
  v_entry   jsonb;
  v_account text;
  v_owner   uuid;
  v_amount  bigint;
  v_balance bigint;
begin
  insert into public.ledger_transaction (reference_type, reference_id, operation, reversal_of, note)
  values (p_reference_type, p_reference_id, p_operation, p_reversal_of, p_note)
  on conflict (reference_type, reference_id, operation) do nothing
  returning id into v_tx;

  if v_tx is null then
    -- เหตุการณ์นี้ post ไปแล้ว — idempotent คืนของเดิม
    select id into v_tx
    from public.ledger_transaction
    where reference_type = p_reference_type
      and reference_id = p_reference_id
      and operation = p_operation;
    return v_tx;
  end if;

  if p_entries is null or jsonb_array_length(p_entries) < 2 then
    raise exception 'ledger transaction needs at least 2 entries';
  end if;

  for v_entry in select * from jsonb_array_elements(p_entries) loop
    v_account := v_entry ->> 'ledger_account';
    v_owner   := nullif(v_entry ->> 'account_id', '')::uuid;
    v_amount  := (v_entry ->> 'amount')::bigint;
    v_balance := null;

    -- อัปเดต wallet projection ใน txn เดียวกัน (CHECK >= 0 ของ wallet คือกันติดลบชั้นสุดท้าย)
    if v_account = 'user_available' then
      update public.wallet set available_coin = available_coin + v_amount
      where account_id = v_owner
      returning available_coin into v_balance;
    elsif v_account = 'user_reserved' then
      update public.wallet set reserved_coin = reserved_coin + v_amount
      where account_id = v_owner
      returning reserved_coin into v_balance;
    elsif v_account = 'seer_payable' then
      update public.wallet set payable_coin = payable_coin + v_amount
      where account_id = v_owner
      returning payable_coin into v_balance;
    end if;

    if v_account in ('user_available', 'user_reserved', 'seer_payable') and v_balance is null then
      raise exception 'wallet row not found for account %', v_owner;
    end if;

    insert into public.ledger_entry (transaction_id, ledger_account, account_id, amount, balance_after)
    values (v_tx, v_account, v_owner, v_amount, v_balance);
  end loop;

  -- zero-sum ตรวจโดย constraint trigger (deferred) ตอน commit
  return v_tx;
end;
$$;

-- -----------------------------------------------------------------------------
-- internal_credit_payment — จุดเดียวที่ payment ทุกช่องทางบรรจบ (spec §6.1)
-- เรียกโดย Edge Function verify-apple-iap (service role) หลัง verify กับ Apple สำเร็จ
-- p_receipt (jsonb): { "provider", "store_product_id", "provider_transaction_id",
--                      "purchase_token_hash_hex", "raw_payload" }
-- ตัดจาก spec เฟส 1: referral bonus (referral_attribution มาเฟส 2)
-- -----------------------------------------------------------------------------
create or replace function public.internal_credit_payment(
  p_payment_order_id uuid,
  p_psp_reference    text,
  p_receipt          jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order   public.payment_order%rowtype;
  v_entries jsonb;
begin
  select * into v_order
  from public.payment_order
  where id = p_payment_order_id
  for update;

  if not found then
    raise exception 'payment order % not found', p_payment_order_id;
  end if;

  if v_order.status = 'credited' then
    -- replay — idempotent
    return jsonb_build_object('payment_order_id', v_order.id, 'status', 'credited',
                              'already_credited', true);
  end if;

  if v_order.status not in ('created', 'pending_provider', 'verified') then
    raise exception 'payment order % in state % cannot be credited', v_order.id, v_order.status
      using errcode = 'P0001';
  end if;

  -- หลักฐาน IAP (unique token hash = replay guard ชั้นบัญชีของ store)
  if p_receipt is not null then
    insert into public.iap_receipt
      (payment_order_id, provider, store_product_id, provider_transaction_id,
       purchase_token_hash, raw_payload)
    values
      (v_order.id,
       p_receipt ->> 'provider',
       p_receipt ->> 'store_product_id',
       p_receipt ->> 'provider_transaction_id',
       decode(p_receipt ->> 'purchase_token_hash_hex', 'hex'),
       coalesce(p_receipt -> 'raw_payload', '{}'::jsonb));
    -- token ซ้ำกับ order อื่น → unique_violation เด้งออกทั้ง transaction (ตั้งใจ)
  end if;

  -- lock wallet ผู้ซื้อ (serialization point)
  perform 1 from public.wallet where account_id = v_order.user_id for update;

  v_entries := jsonb_build_array(
    jsonb_build_object('ledger_account', 'coin_supply', 'account_id', null,
                       'amount', -v_order.coin_amount),
    jsonb_build_object('ledger_account', 'user_available', 'account_id', v_order.user_id,
                       'amount', v_order.coin_amount)
  );
  if v_order.bonus_coin > 0 then
    v_entries := v_entries
      || jsonb_build_object('ledger_account', 'platform_promotion', 'account_id', null,
                            'amount', -v_order.bonus_coin)
      || jsonb_build_object('ledger_account', 'user_available', 'account_id', v_order.user_id,
                            'amount', v_order.bonus_coin);
  end if;

  perform public.internal_post_ledger(
    'payment_order', v_order.id::text, 'credit_purchase', v_entries);

  update public.payment_order
  set status = 'credited',
      psp_reference = coalesce(p_psp_reference, psp_reference),
      credited_at = now()
  where id = v_order.id;

  insert into public.notification_inbox (account_id, notification_type, title, body, deep_link, payload)
  values (v_order.user_id, 'coin_credited',
          'เติมเหรียญสำเร็จ',
          format('ได้รับ %s เหรียญ', v_order.coin_amount + v_order.bonus_coin),
          'chata://wallet',
          jsonb_build_object('payment_order_id', v_order.id));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('payment_order', v_order.id::text, 'payment.credited',
          jsonb_build_object('payment_order_id', v_order.id, 'user_id', v_order.user_id,
                             'coin_amount', v_order.coin_amount, 'bonus_coin', v_order.bonus_coin));

  return jsonb_build_object('payment_order_id', v_order.id, 'status', 'credited',
                            'coin_credited', v_order.coin_amount + v_order.bonus_coin);
end;
$$;

-- -----------------------------------------------------------------------------
-- internal_fail_payment
-- -----------------------------------------------------------------------------
create or replace function public.internal_fail_payment(
  p_payment_order_id uuid,
  p_reason           text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.payment_order%rowtype;
begin
  select * into v_order
  from public.payment_order
  where id = p_payment_order_id
  for update;

  if not found then
    raise exception 'payment order % not found', p_payment_order_id;
  end if;

  if v_order.status in ('failed', 'expired') then
    return jsonb_build_object('payment_order_id', v_order.id, 'status', v_order.status);
  end if;

  if v_order.status not in ('created', 'pending_provider', 'verified') then
    raise exception 'payment order % in state % cannot be failed', v_order.id, v_order.status;
  end if;

  update public.payment_order
  set status = 'failed', failure_reason = p_reason
  where id = v_order.id;

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('payment_order', v_order.id::text, 'payment.failed',
          jsonb_build_object('payment_order_id', v_order.id, 'reason', p_reason));

  return jsonb_build_object('payment_order_id', v_order.id, 'status', 'failed');
end;
$$;

-- internal_* ห้าม client เรียกเด็ดขาด
revoke all on function public.internal_post_ledger(text, text, text, jsonb, uuid, text)
  from public, anon, authenticated;
revoke all on function public.internal_credit_payment(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.internal_fail_payment(uuid, text)
  from public, anon, authenticated;
grant execute on function public.internal_credit_payment(uuid, text, jsonb) to service_role;
grant execute on function public.internal_fail_payment(uuid, text) to service_role;
-- internal_post_ledger ไม่ grant ให้ service_role ด้วยซ้ำ — ให้เรียกผ่าน credit/fail เท่านั้น
-- (postgres owner เรียกได้จากใน RPC อื่นอยู่แล้ว)
