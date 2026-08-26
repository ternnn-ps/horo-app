-- =============================================================================
-- Chata phase 1 — identity + catalog tables
-- account, user_profile, seer_profile, skill, seer_skill, seer_service
--
-- ตัดจาก spec เพราะตารางเฟส 2 ยังไม่มี (ต้องเติมกลับตอนเฟส 2):
--   - seer_profile.level_id (FK -> seer_level) → ส่วนแบ่งใช้ app_config
--     'seer.default_revenue_share_bps' ไปก่อน
--   - seer_service.service_type_id (FK -> service_type) → แทนด้วย
--     service_type_code text CHECK ('chat_question') + bounds จาก app_config
-- =============================================================================

-- ---------------------------------------------------------------- account ----
create table public.account (
  id            uuid primary key references auth.users (id) on delete cascade,
  role          text not null default 'user'
                constraint account_role_chk check (role in ('user', 'seer', 'admin')),
  status        text not null default 'active'
                constraint account_status_chk check (status in ('active', 'suspended', 'deleted')),
  phone_e164    text unique,
  referral_code text unique,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.account is
  'แถวคู่ขนาน auth.users 1:1 (สร้างโดย trigger) — role/status ของบัญชี; user กับ seer เป็นคนละบัญชี';
comment on column public.account.referral_code is 'โค้ดชวนเพื่อนของบัญชีนี้ (8 ตัว, สร้างอัตโนมัติ)';

create trigger account_set_updated_at
  before update on public.account
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------- user_profile ----
create table public.user_profile (
  account_id             uuid primary key references public.account (id) on delete cascade,
  display_name           text not null
                         constraint user_profile_display_name_chk
                         check (char_length(display_name) between 1 and 50),
  avatar_url             text,
  birthdate              date,
  gender                 text
                         constraint user_profile_gender_chk
                         check (gender in ('male', 'female', 'other', 'undisclosed')),
  notify_message         boolean not null default true,
  notify_seer_online     boolean not null default true,
  notify_daily_horoscope boolean not null default true,
  referred_by_code       text,
  version                integer not null default 1,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.user_profile is 'ข้อมูลแสดงผล + preference ฝั่งผู้ใช้ (owner-read/owner-write)';
comment on column public.user_profile.referred_by_code is
  'โค้ดชวนที่กรอกตอนสมัคร (เขียนได้ครั้งเดียวจาก NULL — trigger บังคับ); attribution จริงอยู่เฟส 2';

create trigger user_profile_touch
  before update on public.user_profile
  for each row execute function public.touch_versioned_row();

create trigger user_profile_protect
  before update on public.user_profile
  for each row execute function public.protect_user_profile();

-- ----------------------------------------------------------- seer_profile ----
create table public.seer_profile (
  account_id             uuid primary key references public.account (id) on delete cascade,
  display_name           text not null
                         constraint seer_profile_display_name_chk
                         check (char_length(display_name) between 1 and 50),
  bio                    text not null default ''
                         constraint seer_profile_bio_chk check (char_length(bio) <= 2000),
  avatar_url             text,
  approval_status        text not null default 'draft'
                         constraint seer_profile_approval_chk
                         check (approval_status in ('draft', 'submitted', 'approved', 'rejected')),
  is_active              boolean not null default false,
  accepts_question       boolean not null default false,
  accepts_appointment    boolean not null default false,
  accepts_tip            boolean not null default false,
  accepts_call_extension boolean not null default true,
  rating_avg             numeric(3,2)
                         constraint seer_profile_rating_chk check (rating_avg between 0 and 5),
  rating_count           integer not null default 0,
  question_count         integer not null default 0,
  main_skill_id          integer, -- FK สร้างหลังตาราง skill (ด้านล่าง)
  version                integer not null default 1,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.seer_profile is
  'โปรไฟล์หมอดู — approval_status / is_active / accepts_* เป็นแกนอิสระ ห้ามยุบรวม; public-read เมื่อ approved';
comment on column public.seer_profile.is_active is 'เปิดรับงานหรือไม่ (seer สลับเอง) — คนละเรื่องกับ online presence';
-- เฟส 2: เพิ่ม level_id references seer_level(id) — เฟสนี้ใช้ app_config seer.default_revenue_share_bps

create index seer_profile_discovery_idx on public.seer_profile (approval_status, is_active);

create trigger seer_profile_touch
  before update on public.seer_profile
  for each row execute function public.touch_versioned_row();

-- ------------------------------------------------------------------ skill ----
create table public.skill (
  id         integer generated always as identity primary key,
  name       text not null unique,
  icon_url   text,
  sort_order integer not null default 0,
  is_enabled boolean not null default true
);

comment on table public.skill is 'ศาสตร์ดูดวงที่ระบบรู้จัก (public-read, seed โดย migration/admin)';

alter table public.seer_profile
  add constraint seer_profile_main_skill_fkey
  foreign key (main_skill_id) references public.skill (id) on delete set null;

create index seer_profile_main_skill_idx on public.seer_profile (main_skill_id);

-- ------------------------------------------------------------- seer_skill ----
create table public.seer_skill (
  seer_id  uuid    not null references public.seer_profile (account_id) on delete cascade,
  skill_id integer not null references public.skill (id) on delete restrict,
  is_main  boolean not null default false,
  primary key (seer_id, skill_id)
);

comment on table public.seer_skill is 'หมอดูถนัดศาสตร์ไหน (is_main ได้หนึ่งเดียวต่อ seer — partial unique)';

create unique index seer_skill_one_main_idx on public.seer_skill (seer_id) where is_main;
create index seer_skill_skill_idx on public.seer_skill (skill_id);

-- ----------------------------------------------------------- seer_service ----
create table public.seer_service (
  id                   uuid primary key default gen_random_uuid(),
  seer_id              uuid not null references public.seer_profile (account_id) on delete cascade,
  service_type_code    text not null default 'chat_question'
                       constraint seer_service_type_chk
                       check (service_type_code in ('chat_question')),
  price_coin           bigint not null
                       constraint seer_service_price_chk check (price_coin >= 0),
  is_enabled           boolean not null default false,
  trial_quota_per_user smallint not null default 0
                       constraint seer_service_trial_chk check (trial_quota_per_user >= 0),
  version              integer not null default 1,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (seer_id, service_type_code)
);

comment on table public.seer_service is
  'บริการ + ราคาของหมอดู — แหล่งราคาเดียวของระบบ (RPC ฝั่งซื้ออ่านจากแถวนี้เสมอ)';
comment on column public.seer_service.service_type_code is
  'เฟส 1 มีเฉพาะ chat_question; เฟส 2 จะ migrate เป็น FK -> service_type (voice_call/video_call)';

create index seer_service_enabled_idx on public.seer_service (seer_id) where is_enabled;

create trigger seer_service_touch
  before update on public.seer_service
  for each row execute function public.touch_versioned_row();

create trigger seer_service_validate_price
  before insert or update of price_coin, service_type_code on public.seer_service
  for each row execute function public.validate_seer_service_price();
