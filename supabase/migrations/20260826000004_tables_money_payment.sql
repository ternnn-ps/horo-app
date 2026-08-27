-- =============================================================================
-- Chata phase 1 — money + payment tables
-- wallet, ledger_transaction, ledger_entry, coin_package, payment_order, iap_receipt
--
-- RLS deny-all ทั้งกลุ่ม (ยกเว้น coin_package public-read) — client อ่านผ่าน view,
-- เขียนผ่าน RPC/internal เท่านั้น (spec §4.6-4.7)
--
-- ตัดจาก spec (เติมกลับเฟส 2): bank_transfer_proof, payment_webhook_event,
-- idempotency_key, referral logic ใน credit path
-- เฟส 1 payment = Apple IAP ทางเดียว (method/psp CHECK ยังรองรับครบตาม spec
-- เพื่อไม่ต้องแก้ schema ตอนเพิ่ม PSP)
-- =============================================================================

-- ----------------------------------------------------------------- wallet ----
create table public.wallet (
  account_id     uuid primary key references public.account (id) on delete restrict,
  available_coin bigint not null default 0
                 constraint wallet_available_chk check (available_coin >= 0),
  reserved_coin  bigint not null default 0
                 constraint wallet_reserved_chk check (reserved_coin >= 0),
  payable_coin   bigint not null default 0
                 constraint wallet_payable_chk check (payable_coin >= 0),
  version        integer not null default 1,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.wallet is
  'balance projection (maintain ใน txn เดียวกับ ledger โดย internal_post_ledger เท่านั้น) — '
  'แถวนี้คือ row-lock serialization point ของทุก financial RPC';

create trigger wallet_touch
  before update on public.wallet
  for each row execute function public.touch_versioned_row();

-- ----------------------------------------------------- ledger_transaction ----
create table public.ledger_transaction (
  id             uuid primary key default gen_random_uuid(),
  reference_type text not null
                 constraint ledger_tx_reference_type_chk
                 check (reference_type in ('payment_order', 'question', 'call_transaction',
                                           'call_extension', 'voucher_redemption',
                                           'referral_attribution', 'gift_transaction',
                                           'ai_reading_session', 'payout_request', 'review',
                                           'manual_adjustment')),
  reference_id   text not null,
  operation      text not null
                 constraint ledger_tx_operation_chk
                 check (operation in ('credit_purchase', 'reserve', 'settle', 'refund', 'tip',
                                      'gift', 'redeem', 'referral_bonus', 'ai_charge', 'payout',
                                      'reversal', 'adjustment')),
  reversal_of    uuid references public.ledger_transaction (id),
  note           text,
  created_at     timestamptz not null default now(),
  unique (reference_type, reference_id, operation)
);

comment on table public.ledger_transaction is
  'หัว double-entry — unique (reference_type, reference_id, operation) คือ idempotency ระดับบัญชี; append-only';

create unique index ledger_tx_reversal_once_idx on public.ledger_transaction (reversal_of)
  where reversal_of is not null;

create trigger ledger_transaction_append_only
  before update or delete on public.ledger_transaction
  for each row execute function public.forbid_change();

-- ----------------------------------------------------------- ledger_entry ----
create table public.ledger_entry (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.ledger_transaction (id) on delete restrict,
  ledger_account text not null
                 constraint ledger_entry_account_chk
                 check (ledger_account in ('user_available', 'user_reserved', 'seer_payable',
                                           'platform_revenue', 'platform_promotion', 'coin_supply')),
  account_id     uuid references public.account (id) on delete restrict,
  amount         bigint not null
                 constraint ledger_entry_amount_chk check (amount <> 0),
  balance_after  bigint,
  created_at     timestamptz not null default now(),
  constraint ledger_entry_owner_chk
    check ((ledger_account in ('user_available', 'user_reserved', 'seer_payable'))
           = (account_id is not null))
);

comment on table public.ledger_entry is
  'ขา debit/credit หน่วย coin (+เข้า -ออก) — SUM ต่อ transaction = 0 (deferred constraint trigger); append-only';

create index ledger_entry_owner_idx on public.ledger_entry (account_id, id desc)
  where account_id is not null;
create index ledger_entry_tx_idx on public.ledger_entry (transaction_id);

create trigger ledger_entry_append_only
  before update or delete on public.ledger_entry
  for each row execute function public.forbid_change();

create constraint trigger ledger_entry_zero_sum
  after insert on public.ledger_entry
  deferrable initially deferred
  for each row execute function public.check_ledger_balance();

-- ----------------------------------------------------------- coin_package ----
create table public.coin_package (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  coin_amount       bigint not null
                    constraint coin_package_amount_chk check (coin_amount > 0),
  bonus_coin        bigint not null default 0
                    constraint coin_package_bonus_chk check (bonus_coin >= 0),
  price_minor       bigint not null
                    constraint coin_package_price_chk check (price_minor > 0),
  currency          char(3) not null default 'THB',
  apple_product_id  text,
  google_product_id text,
  allowed_methods   text[] not null,
  sort_order        integer not null default 0,
  is_enabled        boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.coin_package is 'แพ็กเกจเติม coin (public-read เมื่อ is_enabled) — เฟส 1 ขายผ่าน Apple IAP เท่านั้น';
comment on column public.coin_package.price_minor is 'ราคา fiat หน่วย satang (integer minor unit)';
comment on column public.coin_package.allowed_methods is
  'วิธีจ่ายที่แพ็กนี้รองรับ (ซับเซ็ตของ payment_order.method) — เฟส 1 คือ {apple_iap}';

create unique index coin_package_apple_product_idx on public.coin_package (apple_product_id)
  where apple_product_id is not null;
create unique index coin_package_google_product_idx on public.coin_package (google_product_id)
  where google_product_id is not null;

create trigger coin_package_set_updated_at
  before update on public.coin_package
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------- payment_order ----
create table public.payment_order (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.account (id) on delete restrict,
  coin_package_id    uuid not null references public.coin_package (id) on delete restrict,
  method             text not null
                     constraint payment_order_method_chk
                     check (method in ('apple_iap', 'google_play', 'bank_transfer', 'promptpay',
                                       'card', 'truemoney', 'linepay', 'internet_banking')),
  psp_code           text not null
                     constraint payment_order_psp_chk
                     check (psp_code in ('apple', 'google', 'chillpay', 'siampay', 'mol',
                                         'epos', 'omise', 'manual')),
  status             text not null default 'created'
                     constraint payment_order_status_chk
                     check (status in ('created', 'pending_provider', 'verified', 'credited',
                                       'failed', 'expired', 'refunded')),
  coin_amount        bigint not null,
  bonus_coin         bigint not null default 0,
  price_minor        bigint not null,
  currency           char(3) not null default 'THB',
  psp_reference      text,
  referral_code_used text,
  failure_reason     text,
  expires_at         timestamptz not null,
  credited_at        timestamptz,
  version            integer not null default 1,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.payment_order is
  'ความพยายามเติมเงินหนึ่งครั้ง — method (วิธีจ่าย) แยกจาก psp_code (ผู้เคลียร์เงิน); '
  'credited เกิดพร้อม ledger post ใน txn เดียวเสมอ; deny-all';
comment on column public.payment_order.referral_code_used is
  'snapshot โค้ดชวน — logic จ่ายโบนัสมาเฟส 2 (referral_attribution)';

create unique index payment_order_psp_ref_key on public.payment_order (psp_code, psp_reference)
  where psp_reference is not null;
create index payment_order_user_idx on public.payment_order (user_id, created_at desc);
create index payment_order_reconcile_idx on public.payment_order (status, expires_at)
  where status in ('created', 'pending_provider');
create index payment_order_psp_idx on public.payment_order (psp_code, status, created_at desc);

create trigger payment_order_touch
  before update on public.payment_order
  for each row execute function public.touch_versioned_row();

-- ------------------------------------------------------------ iap_receipt ----
create table public.iap_receipt (
  id                      uuid primary key default gen_random_uuid(),
  payment_order_id        uuid not null references public.payment_order (id) on delete restrict,
  provider                text not null
                          constraint iap_receipt_provider_chk
                          check (provider in ('apple_iap', 'google_play')),
  store_product_id        text not null,
  provider_transaction_id text not null,
  purchase_token_hash     bytea not null,
  raw_payload             jsonb not null,
  verified_at             timestamptz not null default now(),
  consumed_at             timestamptz,
  created_at              timestamptz not null default now(),
  unique (provider, purchase_token_hash),
  unique (provider, provider_transaction_id)
);

comment on table public.iap_receipt is
  'หลักฐานซื้อ IAP — unique (provider, purchase_token_hash) กัน replay; ไม่เก็บ token ดิบ (เก็บ SHA-256)';
comment on column public.iap_receipt.provider_transaction_id is
  'Apple: original_transaction_id / Google: order_id';
