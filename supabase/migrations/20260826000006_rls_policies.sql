-- =============================================================================
-- Chata phase 1 — RLS: enable ทุกตาราง + policy ตาม posture ใน spec §7.2
--
-- หลัก:
--   - ทุก policy ใช้ (select auth.uid()) (initplan — ประเมินครั้งเดียว ไม่ per-row)
--   - ตาราง deny-all = enable RLS แต่ไม่มี policy เลย (wallet, ledger_*, payment_order,
--     iap_receipt, outbox_event, audit_log, app_config ส่วน non-public)
--   - ไม่ใช้ FORCE ROW LEVEL SECURITY — trigger/RPC (SECURITY DEFINER, owner=postgres)
--     ต้อง bypass ได้
-- =============================================================================

alter table public.account            enable row level security;
alter table public.user_profile       enable row level security;
alter table public.seer_profile       enable row level security;
alter table public.skill              enable row level security;
alter table public.seer_skill         enable row level security;
alter table public.seer_service       enable row level security;
alter table public.question           enable row level security;
alter table public.question_message   enable row level security;
alter table public.wallet             enable row level security;
alter table public.ledger_transaction enable row level security;
alter table public.ledger_entry       enable row level security;
alter table public.coin_package       enable row level security;
alter table public.payment_order      enable row level security;
alter table public.iap_receipt        enable row level security;
alter table public.app_config         enable row level security;
alter table public.notification_inbox enable row level security;
alter table public.outbox_event       enable row level security;
alter table public.audit_log          enable row level security;

-- ---------------------------------------------------------------- account ----
-- owner-read; ไม่มี write policy (เปลี่ยน role/status ผ่าน service role เท่านั้น)
create policy account_owner_select on public.account
  for select to authenticated
  using (id = (select auth.uid()));

-- ----------------------------------------------------------- user_profile ----
create policy user_profile_owner_select on public.user_profile
  for select to authenticated
  using (account_id = (select auth.uid()));

create policy user_profile_owner_update on public.user_profile
  for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));
-- column ที่แก้ได้ถูกจำกัดด้วย column-level GRANT (ไฟล์ grants)

-- ----------------------------------------------------------- seer_profile ----
-- public-read เมื่อ approved (รวม anon); เจ้าของเห็นตัวเองทุกสถานะ
create policy seer_profile_public_select on public.seer_profile
  for select to anon, authenticated
  using (approval_status = 'approved' or account_id = (select auth.uid()));

create policy seer_profile_owner_update on public.seer_profile
  for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));
-- INSERT (สมัครเป็น seer) ยังไม่มีในเฟส 1 — ทำผ่าน service role

-- ------------------------------------------------------------------ skill ----
create policy skill_public_select on public.skill
  for select to anon, authenticated
  using (true);

-- ------------------------------------------------------------- seer_skill ----
create policy seer_skill_public_select on public.seer_skill
  for select to anon, authenticated
  using (true);

create policy seer_skill_owner_insert on public.seer_skill
  for insert to authenticated
  with check (seer_id = (select auth.uid())
              and public.current_account_role() = 'seer');

create policy seer_skill_owner_delete on public.seer_skill
  for delete to authenticated
  using (seer_id = (select auth.uid()));

-- ----------------------------------------------------------- seer_service ----
create policy seer_service_public_select on public.seer_service
  for select to anon, authenticated
  using (true);

create policy seer_service_owner_insert on public.seer_service
  for insert to authenticated
  with check (seer_id = (select auth.uid())
              and public.current_account_role() = 'seer');

create policy seer_service_owner_update on public.seer_service
  for update to authenticated
  using (seer_id = (select auth.uid()))
  with check (seer_id = (select auth.uid()));

-- --------------------------------------------------------------- question ----
-- participant-read; เขียนผ่าน RPC เท่านั้น (ไม่มี insert/update policy)
create policy question_participant_select on public.question
  for select to authenticated
  using ((select auth.uid()) in (user_id, seer_id));

-- ------------------------------------------------------- question_message ----
create policy question_message_participant_select on public.question_message
  for select to authenticated
  using (public.is_question_participant(question_id));

-- insert ตรงได้ (ไม่แตะเงิน): ต้องเป็นผู้ส่งเอง + participant + สถานะเปิด + ห้าม system
create policy question_message_participant_insert on public.question_message
  for insert to authenticated
  with check (sender_id = (select auth.uid())
              and message_type in ('text', 'photo', 'audio')
              and public.can_post_question_message(question_id));

-- ----------------------------------------------------------- coin_package ----
create policy coin_package_public_select on public.coin_package
  for select to anon, authenticated
  using (is_enabled);

-- ------------------------------------------------------------- app_config ----
create policy app_config_public_select on public.app_config
  for select to anon, authenticated
  using (is_public);

-- ----------------------------------------------------- notification_inbox ----
create policy notification_owner_select on public.notification_inbox
  for select to authenticated
  using (account_id = (select auth.uid()));

-- mark-as-read เท่านั้น (column-level grant จำกัดที่ read_at)
create policy notification_owner_update on public.notification_inbox
  for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

-- deny-all (ไม่มี policy): wallet, ledger_transaction, ledger_entry,
-- payment_order, iap_receipt, outbox_event, audit_log
