-- =============================================================================
-- Chata phase 1 — extensions + helper functions
-- อ้างอิง: docs/specs/chata-database-design.md (spec เป็น source of truth)
-- ทุก function: SECURITY DEFINER + SET search_path = '' + อ้างชื่อเต็ม public./auth.
-- =============================================================================

-- SQL-language helpers ด้านล่างอ้างตารางที่สร้างในไฟล์ถัดไป —
-- ปิด body validation เฉพาะ session ของ migration นี้ (plpgsql ไม่ validate อยู่แล้ว)
set check_function_bodies = off;

-- pg_cron / pg_net ยังไม่ใช้ในเฟส 1 (ไม่มี cron job) — จะเปิดตอนเฟส 2
-- gen_random_uuid() เป็น built-in ของ PG15 (pg_catalog) ไม่ต้องลง extension

-- -----------------------------------------------------------------------------
-- touch_versioned_row: BEFORE UPDATE — set updated_at + bump version อัตโนมัติ
-- ใช้กับตารางที่มีทั้ง updated_at และ version (RPC ไม่ต้อง bump เอง)
-- -----------------------------------------------------------------------------
create or replace function public.touch_versioned_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.version := old.version + 1;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- set_updated_at: BEFORE UPDATE — ตารางที่มี updated_at แต่ไม่มี version
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- forbid_change: BEFORE UPDATE OR DELETE — enforce append-only
-- (ledger_transaction, ledger_entry, audit_log)
-- -----------------------------------------------------------------------------
create or replace function public.forbid_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'table % is append-only (% not allowed)', tg_table_name, tg_op
    using errcode = 'raise_exception';
end;
$$;

-- -----------------------------------------------------------------------------
-- get_config: อ่านค่า app_config (jsonb) — ใช้ใน RPC/trigger เท่านั้น
-- -----------------------------------------------------------------------------
create or replace function public.get_config(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select value from public.app_config where key = p_key;
$$;

-- -----------------------------------------------------------------------------
-- current_account_role: role ของ auth.uid() จากตาราง account
-- -----------------------------------------------------------------------------
create or replace function public.current_account_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.account where id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- is_question_participant: ผู้เรียกเป็นคู่สนทนาของ question นี้ไหม (ใช้ใน RLS)
-- -----------------------------------------------------------------------------
create or replace function public.is_question_participant(p_question_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.question q
    where q.id = p_question_id
      and auth.uid() in (q.user_id, q.seer_id)
  );
$$;

-- -----------------------------------------------------------------------------
-- can_post_question_message: participant + สถานะยังเปิดรับข้อความ (ใช้ใน RLS insert)
-- -----------------------------------------------------------------------------
create or replace function public.can_post_question_message(p_question_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.question q
    where q.id = p_question_id
      and auth.uid() in (q.user_id, q.seer_id)
      and q.status in ('submitted', 'active', 'close_requested')
  );
$$;

-- -----------------------------------------------------------------------------
-- check_ledger_balance: constraint trigger (deferred) — SUM(amount) ต่อ transaction = 0
-- -----------------------------------------------------------------------------
create or replace function public.check_ledger_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sum bigint;
begin
  select coalesce(sum(amount), 0) into v_sum
  from public.ledger_entry
  where transaction_id = new.transaction_id;

  if v_sum <> 0 then
    raise exception 'ledger transaction % is not balanced (sum = %)', new.transaction_id, v_sum;
  end if;
  return null;
end;
$$;

-- -----------------------------------------------------------------------------
-- question_message_after_insert:
--   1) seer ตอบครั้งแรก → question: submitted -> active
--   2) insert outbox event (ไม่มีเนื้อความส่วนตัวใน payload)
-- -----------------------------------------------------------------------------
create or replace function public.question_message_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.question q
  set status = 'active'
  where q.id = new.question_id
    and q.status = 'submitted'
    and q.seer_id = new.sender_id;

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values (
    'question', new.question_id::text, 'question.message.created',
    jsonb_build_object(
      'question_id', new.question_id,
      'message_id', new.id,
      'sender_id', new.sender_id,
      'message_type', new.message_type
    )
  );
  return null;
end;
$$;

-- -----------------------------------------------------------------------------
-- protect_user_profile: referred_by_code เขียนได้ครั้งเดียวจาก NULL (spec 4.1.2)
-- -----------------------------------------------------------------------------
create or replace function public.protect_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.referred_by_code is not null
     and new.referred_by_code is distinct from old.referred_by_code then
    raise exception 'referred_by_code can only be set once';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- validate_seer_service_price: ราคาต้องอยู่ในช่วงของ service type
-- (เฟส 1: service_type เป็นตาราง config — อ่าน bounds จาก app_config
--  key 'service.price_bounds' = {"chat_question": {"min_coin": .., "max_coin": ..}})
-- -----------------------------------------------------------------------------
create or replace function public.validate_seer_service_price()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bounds jsonb;
begin
  v_bounds := public.get_config('service.price_bounds') -> new.service_type_code;
  if v_bounds is null then
    raise exception 'unknown or disabled service type %', new.service_type_code;
  end if;
  if new.price_coin < (v_bounds ->> 'min_coin')::bigint
     or new.price_coin > (v_bounds ->> 'max_coin')::bigint then
    raise exception 'price_coin % out of range for %', new.price_coin, new.service_type_code;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- handle_new_user: AFTER INSERT ON auth.users → account + user_profile + wallet
-- (trigger ตัวจริงสร้างในไฟล์ตาราง identity เพราะต้องมีตารางก่อน)
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_attempt int := 0;
  v_display_name text;
begin
  loop
    v_attempt := v_attempt + 1;
    -- 8 ตัวจากชุดที่ตัดตัวกำกวม (I, L, O, 0, 1) ออก
    select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
    into v_code
    from generate_series(1, 8);

    begin
      insert into public.account (id, role, phone_e164, referral_code)
      values (new.id, 'user', new.phone, v_code);
      exit;
    exception when unique_violation then
      if v_attempt >= 5 then
        raise exception 'could not create account row for auth user % (unique violation)', new.id;
      end if;
      -- ชน referral_code → วนสร้างใหม่ (ถ้าชน phone จะชนซ้ำจน raise ที่ attempt 5)
    end;
  end loop;

  v_display_name := left(coalesce(nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'user'), 50);

  insert into public.user_profile (account_id, display_name)
  values (new.id, v_display_name);

  insert into public.wallet (account_id)
  values (new.id);

  return new;
end;
$$;

-- helper ทั้งหมดห้าม client เรียกตรง ยกเว้นตัวที่ RLS policy ใช้ (ต้อง EXECUTE ได้)
revoke all on function public.get_config(text) from public, anon, authenticated;
revoke all on function public.touch_versioned_row() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.forbid_change() from public, anon, authenticated;
revoke all on function public.check_ledger_balance() from public, anon, authenticated;
revoke all on function public.question_message_after_insert() from public, anon, authenticated;
revoke all on function public.protect_user_profile() from public, anon, authenticated;
revoke all on function public.validate_seer_service_price() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
-- ใช้ใน RLS policy — authenticated ต้อง execute ได้
grant execute on function public.current_account_role() to authenticated;
grant execute on function public.is_question_participant(uuid) to authenticated;
grant execute on function public.can_post_question_message(uuid) to authenticated;
