-- =============================================================================
-- Chata — เส้นทางเติมเหรียญผ่าน IAP (ฝั่งฐานข้อมูล)
--
-- ปัญหา: internal_credit_payment ต้องการ payment_order ที่มีอยู่แล้ว
--   แต่ใน IAP **Apple เป็นฝ่ายเริ่ม** ไม่ใช่เรา — ตอนใบเสร็จมาถึง ยังไม่มี order
--   ถ้าให้ Edge Function สร้าง order แล้วค่อยเรียก credit เป็นสองสเต็ป
--   จังหวะที่ credit ล้ม (เช่นใบเสร็จซ้ำ) จะเหลือ order ค้างเป็นขยะทุกครั้ง
--
-- แก้ด้วย RPC เดียวที่สร้าง order + เติมเหรียญใน transaction เดียว และ idempotent
-- ที่ระดับ transaction id ของ store — ยิงซ้ำกี่ครั้งก็ได้ผลเดียว
--
-- ⚠️ ตัวนี้ไม่ verify ใบเสร็จเอง — การพิสูจน์ว่าใบเสร็จจริงหรือปลอมเป็นหน้าที่ของ
--   Edge Function `verify-iap` ที่ถือ secret และคุยกับ Apple
--   RPC นี้ล็อกไว้ให้ service_role เท่านั้น client เรียกตรงไม่ได้เด็ดขาด
-- =============================================================================

-- โหมดการรับใบเสร็จ — Edge Function อ่านค่านี้ไปตัดสินว่าจะ verify เข้มแค่ไหน
-- 'local_test'  = StoreKit Testing ใน Xcode (ไม่มีบัญชี Apple Developer ก็ทดสอบได้)
-- 'sandbox'     = Apple sandbox (ต้องมีบัญชี $99)
-- 'production'  = ของจริง
insert into public.app_config (key, value, is_public, description) values
  ('payment.iap_mode', '"local_test"'::jsonb, false,
   'โหมดตรวจใบเสร็จ IAP: local_test | sandbox | production — ' ||
   'ต้องเป็น production ก่อนเปิดขายจริงเท่านั้น')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- internal_credit_iap — สร้าง order + เติมเหรียญ ใน transaction เดียว
-- -----------------------------------------------------------------------------
create or replace function public.internal_credit_iap(
  p_account_id             uuid,
  p_provider               text,     -- 'apple_iap' | 'google_play'
  p_store_product_id       text,
  p_provider_transaction_id text,
  p_purchase_token_hash_hex text,
  p_raw_payload            jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pkg      public.coin_package%rowtype;
  v_order_id uuid;
  v_existing uuid;
  v_method   text;
  v_psp      text;
begin
  if p_provider not in ('apple_iap','google_play') then
    raise exception 'unsupported_provider: %', p_provider using errcode = 'P0001';
  end if;
  if coalesce(p_provider_transaction_id,'') = '' then
    raise exception 'missing_transaction_id' using errcode = 'P0001';
  end if;
  if coalesce(p_purchase_token_hash_hex,'') = '' then
    raise exception 'missing_token_hash' using errcode = 'P0001';
  end if;

  -- idempotent: ใบเสร็จใบนี้เคยเข้ามาแล้ว → คืนผลเดิม ไม่สร้าง order ใหม่
  select payment_order_id into v_existing
  from public.iap_receipt
  where provider = p_provider and provider_transaction_id = p_provider_transaction_id;
  if found then
    return jsonb_build_object('payment_order_id', v_existing, 'status', 'credited',
                              'already_credited', true);
  end if;

  select * into v_pkg from public.coin_package
  where is_enabled
    and case p_provider
          when 'apple_iap'   then apple_product_id
          when 'google_play' then google_product_id
        end = p_store_product_id;
  if not found then
    raise exception 'unknown_product: %', p_store_product_id using errcode = 'P0002';
  end if;

  v_method := p_provider;
  v_psp    := case p_provider when 'apple_iap' then 'apple' else 'google' end;

  insert into public.payment_order
    (user_id, coin_package_id, method, psp_code, status,
     coin_amount, bonus_coin, price_minor, currency, expires_at)
  values
    (p_account_id, v_pkg.id, v_method, v_psp, 'verified',
     v_pkg.coin_amount, v_pkg.bonus_coin, v_pkg.price_minor, v_pkg.currency,
     now() + interval '1 hour')
  returning id into v_order_id;

  -- ตัวนี้ตรวจซ้ำอีกชั้นว่า product id ตรงแพ็ก และกัน token ซ้ำด้วย unique constraint
  return public.internal_credit_payment(
    v_order_id,
    p_provider_transaction_id,
    jsonb_build_object(
      'store_product_id', p_store_product_id,
      'provider_transaction_id', p_provider_transaction_id,
      'purchase_token_hash_hex', p_purchase_token_hash_hex,
      'raw_payload', p_raw_payload));
end;
$$;

revoke all on function public.internal_credit_iap(uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;

comment on function public.internal_credit_iap(uuid, text, text, text, text, jsonb) is
  'สร้าง payment_order + เติมเหรียญจากใบเสร็จ store ใน transaction เดียว — '
  'เรียกจาก Edge Function verify-iap (service_role) เท่านั้น. '
  'ไม่ได้ตรวจว่าใบเสร็จจริงหรือปลอม — นั่นเป็นหน้าที่ของ Edge Function';

-- -----------------------------------------------------------------------------
-- dev_grant_coins — เติมเหรียญให้ตัวเองตอนพัฒนา โดยไม่ต้องมีบัญชี Apple
--
-- ป้องกันหลุดขึ้น prod สามชั้น:
--   1) service_role เท่านั้น (client เรียกไม่ได้)
--   2) ทำงานเฉพาะเมื่อ app_config 'payment.iap_mode' = 'local_test'
--   3) ลง audit_log ทุกครั้ง จะได้เห็นทันทีถ้ามีใครใช้ผิดที่
-- -----------------------------------------------------------------------------
create or replace function public.dev_grant_coins(
  p_account_id uuid,
  p_coin       bigint,
  p_note       text default 'dev top-up'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mode text;
  v_tx   uuid;
begin
  v_mode := public.get_config('payment.iap_mode') #>> '{}';
  if v_mode is distinct from 'local_test' then
    raise exception 'dev_grant_disabled'
      using errcode = 'P0001',
            detail = format('payment.iap_mode = %s — ใช้ได้เฉพาะตอน local_test', v_mode);
  end if;
  if p_coin is null or p_coin <= 0 then
    raise exception 'invalid_amount' using errcode = 'P0001';
  end if;

  perform 1 from public.wallet where account_id = p_account_id for update;
  if not found then raise exception 'wallet_not_found' using errcode = 'P0002'; end if;

  -- ใช้ reference_type/operation ที่มีอยู่แล้วในผังบัญชี: การเติมมือของทีมงาน
  -- ถือเป็น manual_adjustment ไม่ใช่ credit_purchase (ไม่มีเงินจริงเข้ามา)
  v_tx := public.internal_post_ledger(
    'manual_adjustment', gen_random_uuid()::text, 'adjustment',
    jsonb_build_array(
      jsonb_build_object('ledger_account', 'platform_promotion', 'account_id', null,
                         'amount', -p_coin),
      jsonb_build_object('ledger_account', 'user_available', 'account_id', p_account_id,
                         'amount', p_coin)),
    null, p_note);

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('admin', null, 'dev.coins_granted', 'account', p_account_id::text,
          jsonb_build_object('coin', p_coin, 'note', p_note,
                             'ledger_transaction_id', v_tx));

  return jsonb_build_object('account_id', p_account_id, 'coin_granted', p_coin,
                            'ledger_transaction_id', v_tx);
end;
$$;

revoke all on function public.dev_grant_coins(uuid, bigint, text)
  from public, anon, authenticated;

comment on function public.dev_grant_coins(uuid, bigint, text) is
  'เติมเหรียญสำหรับ dev เท่านั้น — ทำงานเฉพาะเมื่อ payment.iap_mode = local_test. '
  'ก่อนเปิดขายจริงต้องตั้ง mode เป็น production ซึ่งจะปิดตัวนี้ไปเอง';
