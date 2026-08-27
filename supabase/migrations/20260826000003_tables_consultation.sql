-- =============================================================================
-- Chata phase 1 — consultation tables: question, question_message
--
-- ตัดจาก spec (เติมกลับเฟส 2): review, review_tag, block_relation (การเช็ค block
-- ใน submit_question จึงยังไม่มี), ตาราง idempotency_key
-- → แทน idempotency ระดับ API ของ submit_question ด้วย question.client_request_id
--   (uuid จาก client + UNIQUE (user_id, client_request_id)) — retry คืน question เดิม
-- =============================================================================

-- --------------------------------------------------------------- question ----
create table public.question (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references public.account (id) on delete restrict,
  seer_id                   uuid not null references public.account (id) on delete restrict,
  seer_service_id           uuid not null references public.seer_service (id) on delete restrict,
  status                    text not null default 'submitted'
                            constraint question_status_chk
                            check (status in ('submitted', 'active', 'close_requested',
                                              'completed', 'cancelled_refunded')),
  price_coin                bigint not null
                            constraint question_price_chk check (price_coin >= 0),
  is_trial                  boolean not null default false,
  client_request_id         uuid not null,
  close_requested_by        uuid references public.account (id),
  close_requested_at        timestamptz,
  cancel_reason             text
                            constraint question_cancel_reason_chk
                            check (cancel_reason in ('user_cancel', 'seer_timeout',
                                                     'seer_reject', 'admin')),
  user_last_read_message_id bigint not null default 0,
  seer_last_read_message_id bigint not null default 0,
  expires_at                timestamptz not null,
  completed_at              timestamptz,
  version                   integer not null default 1,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint question_participants_chk check (user_id <> seer_id),
  constraint question_completed_chk
    check (status <> 'completed' or completed_at is not null),
  unique (user_id, client_request_id)
);

comment on table public.question is
  'การปรึกษาแบบคำถาม — escrow coin ตั้งแต่ submit จนถึง terminal; ทุก transition ผ่าน RPC (deny-all)';
comment on column public.question.client_request_id is
  'idempotency key จาก client (แทนตาราง idempotency_key ที่มาเฟส 2) — retry submit ได้ question เดิม';
comment on column public.question.expires_at is 'เส้นตายที่ seer ต้องตอบก่อนโดน auto-refund (cron เฟส 2)';

create index question_user_created_idx on public.question (user_id, created_at desc);
create index question_seer_status_idx on public.question (seer_id, status, created_at desc);
create index question_expiry_idx on public.question (expires_at)
  where status in ('submitted', 'active');

create trigger question_touch
  before update on public.question
  for each row execute function public.touch_versioned_row();

-- ------------------------------------------------------- question_message ----
create table public.question_message (
  id                bigint generated always as identity primary key,
  question_id       uuid not null references public.question (id) on delete cascade,
  sender_id         uuid references public.account (id) on delete set null,
  client_message_id uuid not null,
  message_type      text not null default 'text'
                    constraint question_message_type_chk
                    check (message_type in ('text', 'photo', 'audio', 'system')),
  content           text
                    constraint question_message_content_chk
                    check (content is null or char_length(content) <= 4000),
  object_key        text,
  system_event      text
                    constraint question_message_system_event_chk
                    check (system_event in ('close_requested', 'close_confirmed',
                                            'close_cancelled', 'refunded', 'expired_warning')),
  created_at        timestamptz not null default now(),
  constraint question_message_media_chk
    check ((message_type in ('photo', 'audio')) = (object_key is not null)),
  constraint question_message_system_chk
    check ((message_type = 'system') = (system_event is not null)),
  unique (question_id, client_message_id)
);

comment on table public.question_message is
  'บทสนทนาในคำถาม (append-heavy) — id เป็น keyset cursor; sender_id NULL = system message';

create index question_message_cursor_idx on public.question_message (question_id, id);

create trigger question_message_after_insert
  after insert on public.question_message
  for each row execute function public.question_message_after_insert();
