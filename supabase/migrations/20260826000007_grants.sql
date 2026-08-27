-- =============================================================================
-- Chata phase 1 — GRANT รายตาราง
-- โปรเจกต์ตั้ง "Automatically expose new tables" = ปิด → ไม่มี default grant
-- ต้อง grant เองทุกตารางที่ client ควรเห็น; ตาราง deny-all ไม่ grant ให้ anon/authenticated
-- (RLS เป็นชั้นที่สอง — ถึง grant พลาด RLS ก็ยังกัน แต่เราตั้งใจให้สองชั้นตรงกัน)
-- =============================================================================

-- เคลียร์ให้แน่ใจว่าไม่มี default privilege หลงมา
revoke all on all tables in schema public from anon, authenticated;

grant usage on schema public to anon, authenticated, service_role;

-- service_role: งาน admin/Edge Function — เข้าถึงทุกตาราง (มี bypassrls อยู่แล้ว
-- แต่ privilege ระดับ table ต้อง grant เอง)
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- authenticated ต้องใช้ sequence ของ identity column ที่ insert ตรง (question_message)
grant usage on all sequences in schema public to authenticated;

-- ---------------------------------------------------------------- anon ----
-- public-read สำหรับ landing/ยังไม่ login (RLS กรองซ้ำอีกชั้น)
grant select on public.skill        to anon;
grant select on public.seer_profile to anon;
grant select on public.seer_skill   to anon;
grant select on public.seer_service to anon;
grant select on public.coin_package to anon;
grant select on public.app_config   to anon;

-- ------------------------------------------------------- authenticated ----
-- read
grant select on public.account            to authenticated;
grant select on public.user_profile       to authenticated;
grant select on public.seer_profile       to authenticated;
grant select on public.skill              to authenticated;
grant select on public.seer_skill         to authenticated;
grant select on public.seer_service       to authenticated;
grant select on public.question           to authenticated;
grant select on public.question_message   to authenticated;
grant select on public.coin_package       to authenticated;
grant select on public.app_config         to authenticated;
grant select on public.notification_inbox to authenticated;

-- write (คู่กับ RLS policy; column-level grant = ชั้นจำกัด column)
grant update (display_name, avatar_url, birthdate, gender,
              notify_message, notify_seer_online, notify_daily_horoscope,
              referred_by_code)
  on public.user_profile to authenticated;

grant update (display_name, bio, avatar_url, is_active,
              accepts_question, accepts_appointment, accepts_tip, accepts_call_extension)
  on public.seer_profile to authenticated;

grant insert (seer_id, skill_id, is_main) on public.seer_skill to authenticated;
grant delete on public.seer_skill to authenticated;

grant insert (seer_id, service_type_code, price_coin, is_enabled)
  on public.seer_service to authenticated;
grant update (price_coin, is_enabled) on public.seer_service to authenticated;

grant insert (question_id, sender_id, client_message_id, message_type, content, object_key)
  on public.question_message to authenticated;

grant update (read_at) on public.notification_inbox to authenticated;

-- deny-all: ไม่มี grant ให้ anon/authenticated เลย —
-- wallet, ledger_transaction, ledger_entry, payment_order, iap_receipt,
-- outbox_event, audit_log (client อ่านผ่าน view ในไฟล์ views)
