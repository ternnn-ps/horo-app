-- =============================================================================
-- payout_request — คำขอถอนเงินของหมอดู
--
-- หัวใจ 3 ข้อ:
--   1) เหรียญออกจาก seer_payable **ตอน requested ทันที** ไม่ใช่ตอนโอนจริง
--      ไม่งั้นหมอดูขอถอนซ้อนได้ระหว่างรอแอดมิน แล้วยอดรวมเกินที่มีจริง
--      ถ้าถูกปฏิเสธ/ยกเลิก ค่อยทำ reversing entry คืน (ticket 04)
--   2) ยอดที่ถอนได้ = min(ยอดค้างจ่ายจริง, รายได้ที่สุกแล้ว − ที่ขอไปแล้ว)
--      สองเงื่อนไขคนละเรื่อง: อันแรกกันถอนเกินที่มี อันหลังกันถอนเงินที่ยังไม่พ้นระยะรอ
--   3) อัตราแลก/ค่าธรรมเนียม/ภาษี **snapshot ลงคำขอ** — เปลี่ยนค่ากลางทีหลัง
--      ต้องไม่กระทบคำขอที่ยื่นไปแล้ว
--
-- ระยะรอมีไว้กันเคสซื้อ-ใช้-ถอน-แล้วขอคืนเงินกับ Apple ภายในไม่กี่วัน
-- (ไม่ได้ปิดความเสี่ยง 90 วันของ Apple ทั้งหมด — ยอมรับส่วนที่เหลือใน v1)
-- =============================================================================

insert into public.app_config (key, value, is_public, description) values
  ('payout.conversion_rate_micro', '1000000'::jsonb, true,
   'สตางค์ต่อ 1 coin คูณ 10^6 — 1000000 = 1 coin ต่อ 1 บาท'),
  ('payout.fee_minor', '0'::jsonb, true,
   'ค่าธรรมเนียมต่อคำขอถอน หน่วยสตางค์'),
  ('payout.withholding_bps', '0'::jsonb, true,
   'ภาษีหัก ณ ที่จ่าย เป็น basis points — ตั้ง 0 ไว้ก่อน รอนักบัญชีเคาะ 40(2) vs 40(8)'),
  ('payout.min_coin', '500'::jsonb, true,
   'จำนวนเหรียญขั้นต่ำต่อคำขอถอน'),
  ('payout.hold_days', '7'::jsonb, true,
   'รายได้ต้องเก่ากว่ากี่วันถึงถอนได้')
on conflict (key) do nothing;

create table public.payout_request (
  id                    uuid primary key default gen_random_uuid(),
  seer_id               uuid not null references public.account (id) on delete restrict,
  payout_account_id     uuid not null references public.payout_account (id) on delete restrict,
  coin_amount           bigint not null
                        constraint payout_request_coin_chk check (coin_amount > 0),
  fiat_amount_minor     bigint not null
                        constraint payout_request_fiat_chk check (fiat_amount_minor >= 0),
  conversion_rate_micro bigint not null
                        constraint payout_request_rate_chk check (conversion_rate_micro > 0),
  fee_minor             bigint not null default 0
                        constraint payout_request_fee_chk check (fee_minor >= 0),
  withholding_tax_minor bigint not null default 0
                        constraint payout_request_wht_chk check (withholding_tax_minor >= 0),
  currency              char(3) not null default 'THB',
  status                text not null default 'requested'
                        constraint payout_request_status_chk
                        check (status in ('requested', 'approved', 'paid', 'rejected', 'cancelled')),
  provider_reference    text,
  reject_reason         text,
  reviewed_by_label     text,
  paid_at               timestamptz,
  version               integer not null default 1,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.payout_request is
  'คำขอถอนเงินของหมอดู — deny-all; สร้างผ่าน request_payout, อ่านผ่าน v_my_payout_history';

-- ถอนค้างได้ทีละรายการ — ตัวกันถอนซ้อนที่แท้จริงอยู่ตรงนี้ ไม่ใช่ที่โค้ด
create unique index payout_request_open_uniq
  on public.payout_request (seer_id) where status in ('requested', 'approved');

create index payout_request_owner_idx on public.payout_request (seer_id, created_at desc);
create index payout_request_queue_idx on public.payout_request (created_at)
  where status in ('requested', 'approved');

create trigger payout_request_set_updated_at
  before update on public.payout_request
  for each row execute function public.set_updated_at();

alter table public.payout_request enable row level security;
-- ไม่มี policy = deny-all

-- --------------------------------------------------- v_my_payout_history ----
create view public.v_my_payout_history
with (security_invoker = false, security_barrier = true) as
select
  r.id,
  r.coin_amount,
  r.fiat_amount_minor,
  r.conversion_rate_micro,
  r.fee_minor,
  r.withholding_tax_minor,
  r.currency,
  r.status,
  r.provider_reference,
  r.reject_reason,
  r.paid_at,
  r.created_at
from public.payout_request r
where r.seer_id = (select auth.uid());

grant select on public.v_my_payout_history to authenticated;

-- --------------------------------------------------- v_my_payout_summary ----
-- ตอบคำถามเดียวที่หน้าจอต้องการ: "ตอนนี้ถอนได้เท่าไหร่ และที่เหลือจะถอนได้เมื่อไหร่"
create view public.v_my_payout_summary
with (security_invoker = false, security_barrier = true) as
with me as (select (select auth.uid()) as id),
-- อ่าน app_config ตรง ๆ ไม่ผ่าน get_config โดยตั้งใจ:
-- definer view ใช้สิทธิ์เจ้าของกับ**ตาราง** แต่การเรียก**ฟังก์ชัน** ยังเช็คสิทธิ์ของผู้เรียก
-- get_config ถูก revoke จาก authenticated ไว้ → view จะพังด้วย permission denied
cfg as (
  select
    coalesce(max(case when c.key = 'payout.hold_days' then (c.value #>> '{}')::int end), 7)                 as hold_days,
    coalesce(max(case when c.key = 'payout.min_coin' then (c.value #>> '{}')::bigint end), 500)             as min_coin,
    coalesce(max(case when c.key = 'payout.conversion_rate_micro' then (c.value #>> '{}')::bigint end), 1000000) as rate_micro
  from public.app_config c
  where c.key in ('payout.hold_days', 'payout.min_coin', 'payout.conversion_rate_micro')
),
matured as (
  select coalesce(sum(e.seer_coin), 0) as coin
  from public.seer_earning e, me, cfg
  where e.seer_id = me.id
    and e.created_at <= now() - make_interval(days => cfg.hold_days)
),
locked as (
  select coalesce(sum(r.coin_amount), 0) as coin
  from public.payout_request r, me
  where r.seer_id = me.id and r.status in ('requested', 'approved', 'paid')
),
pending as (
  select coalesce(sum(r.coin_amount), 0) as coin
  from public.payout_request r, me
  where r.seer_id = me.id and r.status in ('requested', 'approved')
)
select
  me.id                                             as account_id,
  coalesce(w.payable_coin, 0)                       as payable_coin,
  -- ต้องผ่านทั้งสองเงื่อนไข: มีเงินจริง และเงินนั้นสุกแล้ว
  greatest(least(coalesce(w.payable_coin, 0), matured.coin - locked.coin), 0) as withdrawable_coin,
  pending.coin                                      as pending_coin,
  cfg.min_coin,
  cfg.hold_days,
  cfg.rate_micro                                    as conversion_rate_micro,
  (select min(e.created_at) + make_interval(days => cfg.hold_days)
   from public.seer_earning e
   where e.seer_id = me.id
     and e.created_at > now() - make_interval(days => cfg.hold_days)) as next_matures_at
from me
cross join cfg
cross join matured
cross join locked
cross join pending
left join public.wallet w on w.account_id = me.id;

comment on view public.v_my_payout_summary is
  'ยอดถอนได้ของฉัน — withdrawable = min(ยอดค้างจ่ายจริง, รายได้ที่สุกแล้ว − ที่ขอไปแล้ว)';

grant select on public.v_my_payout_summary to authenticated;

-- =============================================================================
-- internal_payout_quote — คิดตัวเลขเงินของคำขอ
--
-- แยกออกมาเป็นฟังก์ชันเดียวเพราะทั้งหน้าจอ (preview) และการบันทึกจริง (request)
-- ต้องได้ตัวเลขชุดเดียวกันเป๊ะ — ถ้าคิดกันคนละที่ วันหนึ่งจะเพี้ยนแล้วผู้ใช้เห็นเลขหนึ่ง
-- แต่ถูกบันทึกอีกเลขหนึ่ง ซึ่งเป็นบั๊กที่เถียงกันไม่จบ
-- =============================================================================
create or replace function public.internal_payout_quote(p_coin_amount bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with cfg as (
    select
      coalesce((public.get_config('payout.conversion_rate_micro') #>> '{}')::bigint, 1000000) as rate_micro,
      coalesce((public.get_config('payout.fee_minor') #>> '{}')::bigint, 0)                   as fee_minor,
      coalesce((public.get_config('payout.withholding_bps') #>> '{}')::int, 0)                as wht_bps
  ), gross as (
    select (p_coin_amount * cfg.rate_micro) / 1000000 as gross_minor, cfg.*
    from cfg
  )
  select jsonb_build_object(
    'coin_amount', p_coin_amount,
    'gross_minor', gross.gross_minor,
    'conversion_rate_micro', gross.rate_micro,
    'fee_minor', gross.fee_minor,
    'withholding_tax_minor', (gross.gross_minor * gross.wht_bps) / 10000,
    'fiat_amount_minor', greatest(
      gross.gross_minor - gross.fee_minor - (gross.gross_minor * gross.wht_bps) / 10000, 0),
    'currency', 'THB')
  from gross;
$$;

-- =============================================================================
-- preview_payout — หน้าจอถามว่า "ถอนเท่านี้จะได้เงินจริงเท่าไหร่"
-- =============================================================================
create or replace function public.preview_payout(p_coin_amount bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_coin_amount is null or p_coin_amount <= 0 then
    raise exception 'invalid_amount' using errcode = 'P0001';
  end if;

  return public.internal_payout_quote(p_coin_amount);
end;
$$;

grant execute on function public.preview_payout(bigint) to authenticated;

-- =============================================================================
-- request_payout — หมอดูขอถอนเงิน
-- =============================================================================
create or replace function public.request_payout(p_coin_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me        uuid := (select auth.uid());
  v_acc       public.payout_account%rowtype;
  v_quote     jsonb;
  v_min       bigint;
  v_hold      int;
  v_matured   bigint;
  v_locked    bigint;
  v_payable   bigint;
  v_available bigint;
  v_id        uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_coin_amount is null or p_coin_amount <= 0 then
    raise exception 'invalid_amount' using errcode = 'P0001';
  end if;

  select * into v_acc from public.payout_account
  where seer_id = v_me and deleted_at is null;
  if not found then
    raise exception 'payout_account_missing' using errcode = 'P0001';
  end if;
  if v_acc.verify_status <> 'verified' then
    raise exception 'payout_account_not_verified: %', v_acc.verify_status using errcode = 'P0001';
  end if;

  v_min  := coalesce((public.get_config('payout.min_coin') #>> '{}')::bigint, 500);
  v_hold := coalesce((public.get_config('payout.hold_days') #>> '{}')::int, 7);

  if p_coin_amount < v_min then
    raise exception 'below_minimum: ขั้นต่ำ % เหรียญ', v_min using errcode = 'P0001';
  end if;

  -- ล็อกกระเป๋าก่อนอ่านยอด กัน request สองอันวิ่งพร้อมกันแล้วเห็นยอดเดียวกัน
  select payable_coin into v_payable from public.wallet
  where account_id = v_me for update;
  if not found then
    raise exception 'wallet_missing' using errcode = 'P0002';
  end if;

  select coalesce(sum(seer_coin), 0) into v_matured
  from public.seer_earning
  where seer_id = v_me and created_at <= now() - make_interval(days => v_hold);

  select coalesce(sum(coin_amount), 0) into v_locked
  from public.payout_request
  where seer_id = v_me and status in ('requested', 'approved', 'paid');

  v_available := greatest(least(v_payable, v_matured - v_locked), 0);

  if p_coin_amount > v_available then
    raise exception 'insufficient_withdrawable: ถอนได้ % เหรียญ', v_available using errcode = 'P0001';
  end if;

  v_quote := public.internal_payout_quote(p_coin_amount);

  insert into public.payout_request
    (seer_id, payout_account_id, coin_amount, fiat_amount_minor, conversion_rate_micro,
     fee_minor, withholding_tax_minor, currency)
  values
    (v_me, v_acc.id, p_coin_amount,
     (v_quote ->> 'fiat_amount_minor')::bigint,
     (v_quote ->> 'conversion_rate_micro')::bigint,
     (v_quote ->> 'fee_minor')::bigint,
     (v_quote ->> 'withholding_tax_minor')::bigint,
     v_quote ->> 'currency')
  returning id into v_id;

  -- เหรียญออกจากระบบทันทีตอนขอ — coin_supply เป็นบัญชี contra ที่รับกลับ
  perform public.internal_post_ledger(
    'payout_request', v_id::text, 'payout',
    jsonb_build_array(
      jsonb_build_object('ledger_account', 'seer_payable', 'account_id', v_me,
                         'amount', -p_coin_amount),
      jsonb_build_object('ledger_account', 'coin_supply', 'account_id', null,
                         'amount', p_coin_amount)));

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('seer', v_me, 'payout_request.created', 'payout_request', v_id::text,
          jsonb_build_object('coin_amount', p_coin_amount,
                             'fiat_amount_minor', (v_quote ->> 'fiat_amount_minor')::bigint,
                             'last4', v_acc.account_number_last4));

  return v_quote
      || jsonb_build_object('payout_request_id', v_id, 'status', 'requested');
exception
  when unique_violation then
    -- ชน payout_request_open_uniq = มีคำขอค้างอยู่แล้ว
    raise exception 'payout_already_pending' using errcode = 'P0001';
end;
$$;

grant execute on function public.request_payout(bigint) to authenticated;
