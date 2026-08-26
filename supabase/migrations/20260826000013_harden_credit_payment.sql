-- =============================================================================
-- Chata phase 1 — ปิดช่องโหว่ใน internal_credit_payment
--
-- พบตอนทดสอบ end-to-end บน local DB สามข้อ:
--
-- (1) receipt เป็น optional — `if p_receipt is not null` แปลว่า order IAP
--     ถูก credit ได้โดยไม่มีหลักฐานการซื้อเลย ทั้งที่ระบบกัน replay ทั้งหมด
--     พึ่ง unique (provider, purchase_token_hash) ใน iap_receipt
--     → ถ้า Edge Function พลาดไม่ส่ง receipt มา เหรียญออกฟรีและกันซ้ำไม่ได้
--
-- (2) provider มาจาก payload ที่ผู้เรียกส่งมา ทั้งที่ order รู้อยู่แล้วจาก method
--     → บันทึกใบเสร็จ Google ทับ order ของ Apple ได้ ทำให้ unique guard
--       ที่ผูกกับ provider ใช้ไม่ได้จริง
--
-- (3) ไม่ตรวจว่า store_product_id ในใบเสร็จ ตรงกับแพ็กเกจที่สั่งซื้อไหม
--     → ใบเสร็จแพ็ก 50 เหรียญ credit เป็น order 500 เหรียญได้
--
-- หลักการที่ใช้แก้: ข้อมูลที่ฝั่งเรารู้อยู่แล้ว ห้ามรับจากผู้เรียก
-- =============================================================================

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
  v_order            public.payment_order%rowtype;
  v_entries          jsonb;
  v_provider         text;
  v_expected_product text;
  v_token_hash       bytea;
begin
  select * into v_order
  from public.payment_order
  where id = p_payment_order_id
  for update;

  if not found then
    raise exception 'payment order % not found', p_payment_order_id
      using errcode = 'P0002';
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

  -- ---------------------------------------------------------------------------
  -- (2) provider มาจาก order ไม่ใช่ payload
  -- ---------------------------------------------------------------------------
  v_provider := case v_order.method
                  when 'apple_iap'   then 'apple_iap'
                  when 'google_play' then 'google_play'
                  else null
                end;

  -- ---------------------------------------------------------------------------
  -- (1) order ที่มาจาก store ต้องมีใบเสร็จเสมอ — ไม่มี = ไม่ credit
  -- ---------------------------------------------------------------------------
  if v_provider is not null then
    if p_receipt is null then
      raise exception 'order % เป็น % แต่ไม่มี receipt — ปฏิเสธการ credit',
        v_order.id, v_order.method using errcode = 'P0001';
    end if;

    v_token_hash := decode(nullif(p_receipt ->> 'purchase_token_hash_hex', ''), 'hex');
    if v_token_hash is null then
      raise exception 'receipt ของ order % ไม่มี purchase_token_hash_hex', v_order.id
        using errcode = 'P0001';
    end if;

    if coalesce(p_receipt ->> 'provider_transaction_id', '') = '' then
      raise exception 'receipt ของ order % ไม่มี provider_transaction_id', v_order.id
        using errcode = 'P0001';
    end if;

    -- -------------------------------------------------------------------------
    -- (3) product id ในใบเสร็จต้องตรงกับแพ็กเกจที่สั่ง
    -- -------------------------------------------------------------------------
    select case v_provider
             when 'apple_iap'   then cp.apple_product_id
             when 'google_play' then cp.google_product_id
           end
      into v_expected_product
    from public.coin_package cp
    where cp.id = v_order.coin_package_id;

    if v_expected_product is null then
      raise exception 'แพ็กเกจของ order % ไม่ได้ตั้ง product id สำหรับ %',
        v_order.id, v_provider using errcode = 'P0001';
    end if;

    if p_receipt ->> 'store_product_id' is distinct from v_expected_product then
      raise exception 'receipt ของ order % เป็น product % แต่แพ็กเกจคาดหวัง %',
        v_order.id, coalesce(p_receipt ->> 'store_product_id', '(null)'), v_expected_product
        using errcode = 'P0001';
    end if;

    insert into public.iap_receipt
      (payment_order_id, provider, store_product_id, provider_transaction_id,
       purchase_token_hash, raw_payload)
    values
      (v_order.id,
       v_provider,                                   -- จาก order ไม่ใช่ payload
       v_expected_product,                           -- จากแพ็กเกจ ไม่ใช่ payload
       p_receipt ->> 'provider_transaction_id',
       v_token_hash,
       coalesce(p_receipt -> 'raw_payload', '{}'::jsonb));
    -- token ซ้ำกับ order อื่น → unique_violation เด้งออกทั้ง transaction (ตั้งใจ)

  elsif p_receipt is not null then
    -- order ที่ไม่ใช่ store แต่ส่ง receipt มา = ผู้เรียกเข้าใจผิด ปฏิเสธไว้ก่อน
    raise exception 'order % method % ไม่ควรมี IAP receipt', v_order.id, v_order.method
      using errcode = 'P0001';
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

revoke all on function public.internal_credit_payment(uuid, text, jsonb) from public, anon, authenticated;

comment on function public.internal_credit_payment(uuid, text, jsonb) is
  'credit เหรียญเข้ากระเป๋าหลัง verify การชำระเงิน — เรียกจาก Edge Function (service_role) เท่านั้น. '
  'order ที่มาจาก store ต้องแนบ receipt ที่ product id ตรงกับแพ็กเกจ มิฉะนั้นปฏิเสธ.';
