-- =============================================================================
-- payout_account — บัญชีธนาคารที่หมอดูให้โอนเงินเข้า
--
-- นี่คือ PII การเงิน ตารางจึง deny-all: client อ่านตรงไม่ได้เลย
-- เห็นได้แค่ 4 ตัวท้ายผ่าน view และเลขเต็มอ่านได้ทางเดียวคือ RPC ของแอดมิน
-- ซึ่ง**บันทึก audit ทุกครั้งที่เปิดดู**
--
-- เบี่ยงจาก chata-database-design.md §4.9.2 ที่เขียนว่าใช้ pgsodium เข้ารหัสคอลัมน์:
--   Supabase ประกาศเลิกแนะนำ pgsodium และ Transparent Column Encryption แล้ว
--   (เหตุผลของเขา: ซับซ้อนเกินและตั้งค่าผิดได้ง่าย) พร้อมระบุว่าโปรเจกต์เข้ารหัส
--   at rest อยู่แล้ว → v1 ใช้ deny-all + จำกัดทางเข้าถึง + audit แทน
--   ถ้าภายหลังต้องการมากกว่านี้ ใช้ pgcrypto โดยเก็บ key ใน Supabase Vault
--   ซึ่งเปลี่ยนได้โดยไม่กระทบ interface ของ RPC ที่วางไว้ตรงนี้
-- =============================================================================

create table public.payout_account (
  id                   uuid primary key default gen_random_uuid(),
  seer_id              uuid not null references public.account (id) on delete restrict,
  bank_code            text not null,
  account_number       text not null,
  account_number_last4 text not null
                       constraint payout_account_last4_chk check (account_number_last4 ~ '^[0-9]{4}$'),
  account_holder_name  text not null,
  verify_status        text not null default 'pending'
                       constraint payout_account_status_chk
                       check (verify_status in ('pending', 'verified', 'rejected')),
  reject_reason        text,
  reviewed_by_label    text,
  reviewed_at          timestamptz,
  -- soft delete: ต้องเก็บไว้เพราะ payout_request เก่าอ้างถึงบัญชีปลายทาง ณ ตอนนั้น
  deleted_at           timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.payout_account is
  'บัญชีธนาคารของหมอดู (PII การเงิน) — deny-all; เห็น 4 ตัวท้ายผ่าน v_my_payout_account, '
  'เลขเต็มอ่านได้ทางเดียวคือ admin_reveal_payout_account ซึ่ง audit ทุกครั้ง';

-- บัญชีรับเงินที่ใช้งานอยู่ทีละหนึ่งต่อหมอดูหนึ่งคน
create unique index payout_account_active_uniq
  on public.payout_account (seer_id) where deleted_at is null;

create index payout_account_review_idx
  on public.payout_account (verify_status) where deleted_at is null and verify_status = 'pending';

create trigger payout_account_set_updated_at
  before update on public.payout_account
  for each row execute function public.set_updated_at();

alter table public.payout_account enable row level security;
-- ไม่มี policy ใด ๆ = deny-all สำหรับ anon/authenticated ทุกคำสั่ง

-- --------------------------------------------------- v_my_payout_account ----
-- definer view เพราะตารางฐาน deny-all — invoker view จะอ่านไม่ได้เลย
create view public.v_my_payout_account
with (security_invoker = false, security_barrier = true) as
select
  a.id,
  a.bank_code,
  a.account_number_last4,
  a.account_holder_name,
  a.verify_status,
  a.reject_reason,
  a.reviewed_at,
  a.updated_at
from public.payout_account a
where a.seer_id = (select auth.uid())
  and a.deleted_at is null;

comment on view public.v_my_payout_account is
  'บัญชีรับเงินของฉัน — **ไม่มีคอลัมน์ account_number โดยตั้งใจ** เห็นได้แค่ 4 ตัวท้าย';

grant select on public.v_my_payout_account to authenticated;

-- ------------------------------------------------------------- app_config ----
insert into public.app_config (key, value, is_public, description) values
  ('payout.bank_codes',
   '["scb","kbank","ktb","bbl","bay","gsb","ttb","uob","kkp","cimb","lhb","tisco","baac"]'::jsonb,
   true, 'รหัสธนาคารไทยที่รับโอนได้ — ตรวจใน set_payout_account')
on conflict (key) do nothing;

-- =============================================================================
-- set_payout_account — หมอดูบันทึก/แก้บัญชีรับเงิน
--
-- แก้แล้วสถานะกลับไป pending เสมอ: ถ้าปล่อยให้ยัง verified อยู่ด้วยเลขบัญชีใหม่
-- ที่ยังไม่มีใครดู = ช่องโอนเงินเข้าบัญชีที่ไม่เคยผ่าน KYC
-- ทำด้วยการ soft delete ของเดิมแล้วออกแถวใหม่ เพื่อให้ payout_request เก่ายังชี้ถูก
-- =============================================================================
create or replace function public.set_payout_account(
  p_bank_code           text,
  p_account_number      text,
  p_account_holder_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me    uuid := (select auth.uid());
  v_role  text;
  v_num   text := regexp_replace(coalesce(p_account_number, ''), '[\s-]', '', 'g');
  v_banks jsonb;
  v_id    uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select role into v_role from public.account where id = v_me;
  if v_role is distinct from 'seer' then
    raise exception 'seer_only' using errcode = 'P0001';
  end if;

  v_banks := public.get_config('payout.bank_codes');
  if v_banks is null or not (v_banks ? coalesce(p_bank_code, '')) then
    raise exception 'unknown_bank_code: %', p_bank_code using errcode = 'P0001';
  end if;

  if v_num !~ '^[0-9]{8,15}$' then
    raise exception 'invalid_account_number' using errcode = 'P0001';
  end if;

  if coalesce(btrim(p_account_holder_name), '') = '' then
    raise exception 'missing_account_holder_name' using errcode = 'P0001';
  end if;

  update public.payout_account
  set deleted_at = now()
  where seer_id = v_me and deleted_at is null;

  insert into public.payout_account
    (seer_id, bank_code, account_number, account_number_last4, account_holder_name)
  values
    (v_me, p_bank_code, v_num, right(v_num, 4), btrim(p_account_holder_name))
  returning id into v_id;

  -- detail ต้องไม่มี PII — เก็บแค่ 4 ตัวท้ายพอให้ตามรอยได้
  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('seer', v_me, 'payout_account.saved', 'payout_account', v_id::text,
          jsonb_build_object('bank_code', p_bank_code, 'last4', right(v_num, 4)));

  return jsonb_build_object('payout_account_id', v_id, 'verify_status', 'pending');
end;
$$;

grant execute on function public.set_payout_account(text, text, text) to authenticated;

-- =============================================================================
-- admin_review_payout_account — แอดมินตรวจว่าชื่อบัญชีตรงกับเอกสาร KYC ไหม
-- =============================================================================
create or replace function public.admin_review_payout_account(
  p_payout_account_id uuid,
  p_approve           boolean,
  p_reviewer_label    text,
  p_reject_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acc public.payout_account%rowtype;
begin
  if coalesce(btrim(p_reviewer_label), '') = '' then
    raise exception 'missing_reviewer_label' using errcode = 'P0001';
  end if;
  if not p_approve and coalesce(btrim(p_reject_reason), '') = '' then
    raise exception 'missing_reject_reason' using errcode = 'P0001';
  end if;

  select * into v_acc from public.payout_account
  where id = p_payout_account_id and deleted_at is null
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if v_acc.verify_status <> 'pending' then
    return jsonb_build_object('payout_account_id', v_acc.id,
                              'verify_status', v_acc.verify_status, 'replayed', true);
  end if;

  update public.payout_account
  set verify_status  = case when p_approve then 'verified' else 'rejected' end,
      reject_reason  = case when p_approve then null else btrim(p_reject_reason) end,
      reviewed_by_label = btrim(p_reviewer_label),
      reviewed_at    = now()
  where id = v_acc.id;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('admin', null,
          case when p_approve then 'payout_account.verified' else 'payout_account.rejected' end,
          'payout_account', v_acc.id::text,
          jsonb_build_object('reviewer', btrim(p_reviewer_label),
                             'reason', p_reject_reason,
                             'last4', v_acc.account_number_last4));

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_acc.seer_id, 'system',
          case when p_approve then 'บัญชีรับเงินผ่านการตรวจแล้ว' else 'บัญชีรับเงินไม่ผ่านการตรวจ' end,
          case when p_approve then 'ถอนเงินได้แล้วเมื่อยอดถึงขั้นต่ำ' else btrim(p_reject_reason) end,
          'chata://seer/payout',
          jsonb_build_object('payout_account_id', v_acc.id));

  return jsonb_build_object('payout_account_id', v_acc.id,
                            'verify_status', case when p_approve then 'verified' else 'rejected' end,
                            'replayed', false);
end;
$$;

-- =============================================================================
-- admin_reveal_payout_account — ทางเดียวที่จะอ่านเลขบัญชีเต็ม
--
-- แยกออกจาก review เพราะการ "เปิดดูเลขบัญชี" คือเหตุการณ์ที่ต้องนับได้เอง
-- ไม่ใช่ผลข้างเคียงของอย่างอื่น — แอดมินโอนเงินต้องเปิดดู และทุกครั้งต้องมีร่องรอย
-- =============================================================================
create or replace function public.admin_reveal_payout_account(
  p_payout_account_id uuid,
  p_reviewer_label    text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acc public.payout_account%rowtype;
begin
  if coalesce(btrim(p_reviewer_label), '') = '' then
    raise exception 'missing_reviewer_label' using errcode = 'P0001';
  end if;

  select * into v_acc from public.payout_account where id = p_payout_account_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  insert into public.audit_log (actor_type, actor_id, action, target_type, target_id, detail)
  values ('admin', null, 'payout_account.revealed', 'payout_account', v_acc.id::text,
          jsonb_build_object('reviewer', btrim(p_reviewer_label),
                             'last4', v_acc.account_number_last4));

  return jsonb_build_object(
    'payout_account_id', v_acc.id,
    'bank_code', v_acc.bank_code,
    'account_number', v_acc.account_number,
    'account_holder_name', v_acc.account_holder_name,
    'verify_status', v_acc.verify_status);
end;
$$;

revoke all on function public.admin_review_payout_account(uuid, boolean, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_reveal_payout_account(uuid, text)
  from public, anon, authenticated;
