-- =============================================================================
-- Chata phase 1 — ops tables: app_config, notification_inbox, outbox_event, audit_log
-- (spec เรียก "notification" ใน context ว่า notification_inbox — ใช้ชื่อตาม spec)
--
-- ตัดจาก spec (เติมกลับเฟส 2): rate_limit_counter (RPC เฟสนี้จึงยังไม่มี rate limit
-- ระดับ DB), device_token (push ต้องรอ Apple Developer Program)
-- =============================================================================

-- ------------------------------------------------------------- app_config ----
create table public.app_config (
  key         text primary key,
  value       jsonb not null,
  is_public   boolean not null default false,
  description text not null,
  updated_at  timestamptz not null default now()
);

comment on table public.app_config is
  'config + feature flag ฝั่ง server — client อ่านได้เฉพาะ is_public=true; RPC อ่านผ่าน get_config()';

create trigger app_config_set_updated_at
  before update on public.app_config
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------- notification_inbox ----
create table public.notification_inbox (
  id                bigint generated always as identity primary key,
  account_id        uuid not null references public.account (id) on delete cascade,
  notification_type text not null
                    constraint notification_type_chk
                    check (notification_type in ('message', 'question_update', 'appointment',
                                                 'call', 'coin_credited', 'payout', 'system',
                                                 'live_started', 'horoscope')),
  title             text not null,
  body              text not null,
  deep_link         text,
  payload           jsonb not null default '{}',
  read_at           timestamptz,
  created_at        timestamptz not null default now()
);

comment on table public.notification_inbox is
  'กระดิ่งในแอปต่อบัญชี — owner-read; owner แก้ได้เฉพาะ read_at (column-level grant); INSERT โดย worker/trigger';
comment on column public.notification_inbox.deep_link is 'route กลาง platform-neutral เช่น chata://question/{uuid}';

create index notification_inbox_cursor_idx on public.notification_inbox (account_id, id desc);
create index notification_inbox_unread_idx on public.notification_inbox (account_id)
  where read_at is null;

-- ----------------------------------------------------------- outbox_event ----
create table public.outbox_event (
  id              bigint generated always as identity primary key,
  aggregate_type  text not null,
  aggregate_id    text not null,
  event_type      text not null,
  payload         jsonb not null,
  status          text not null default 'pending'
                  constraint outbox_status_chk
                  check (status in ('pending', 'processing', 'published', 'dead')),
  attempts        smallint not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error      text,
  published_at    timestamptz,
  created_at      timestamptz not null default now()
);

comment on table public.outbox_event is
  'transactional outbox — insert ใน txn เดียวกับ domain change; dispatcher (เฟส 2: pg_cron+Edge) '
  'claim ด้วย SKIP LOCKED; payload ห้ามมี token/secret/เนื้อความส่วนตัว';

create index outbox_dispatch_idx on public.outbox_event (next_attempt_at)
  where status in ('pending', 'processing');
create index outbox_aggregate_idx on public.outbox_event (aggregate_type, aggregate_id);

-- -------------------------------------------------------------- audit_log ----
create table public.audit_log (
  id          bigint generated always as identity primary key,
  actor_type  text not null
              constraint audit_actor_type_chk
              check (actor_type in ('user', 'seer', 'admin', 'system')),
  actor_id    uuid references public.account (id) on delete set null,
  action      text not null,
  target_type text,
  target_id   text,
  detail      jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

comment on table public.audit_log is
  'เหตุการณ์สำคัญเชิงระบบ/แอดมิน (เงินมี ledger เป็น audit อยู่แล้ว) — append-only; detail ต้อง redact PII';

create index audit_log_target_idx on public.audit_log (target_type, target_id, created_at desc);
create index audit_log_actor_idx on public.audit_log (actor_id, created_at desc);

create trigger audit_log_append_only
  before update or delete on public.audit_log
  for each row execute function public.forbid_change();

-- -----------------------------------------------------------------------------
-- auth trigger: สร้าง account + user_profile + wallet ทันทีที่สมัคร
-- (อยู่ไฟล์นี้เพราะต้องรอทุกตารางที่ handle_new_user แตะถูกสร้างก่อน)
-- -----------------------------------------------------------------------------
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
