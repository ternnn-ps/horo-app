-- =============================================================================
-- เปิด Realtime ให้ตารางฝั่งการปรึกษา — แชทต้องเด้งเองโดยไม่ต้องรีเฟรช
--
-- Realtime ของ Supabase เคารพ RLS ที่มีอยู่แล้ว (question_participant_select /
-- question_message_participant_select) จึงไม่ต้องเพิ่ม policy อะไรทั้งสิ้น:
-- ผู้ใช้ที่ไม่ใช่คู่สนทนา subscribe ได้แต่จะไม่ได้รับ event ของห้องนั้น
--
-- ไม่ใส่ตาราง money เข้า publication เด็ดขาด — client ไม่มีสิทธิ์อ่านมันอยู่แล้ว
-- และการ stream การเคลื่อนไหวของ ledger ออกไปคือการเปิดพื้นผิวโดยไม่จำเป็น
-- ยอดเหรียญให้อ่านซ้ำจาก v_my_wallet หลังทุก operation ที่แตะเงินแทน
-- =============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'question'
  ) then
    alter publication supabase_realtime add table public.question;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'question_message'
  ) then
    alter publication supabase_realtime add table public.question_message;
  end if;
end
$$;

-- question ต้องส่ง old record ตอน UPDATE ด้วย ไม่งั้นฝั่งที่ subscribe แยกไม่ออกว่า
-- สถานะเปลี่ยนจากอะไรเป็นอะไร (submitted → active ต่างจาก active → close_requested
-- ในเชิง UI คนละเรื่องกัน) — question_message เป็น append-only จึงไม่ต้อง
alter table public.question replica identity full;
