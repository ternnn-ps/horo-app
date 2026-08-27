-- =============================================================================
-- Domain event ผ่าน Realtime Broadcast — "สถานะคำถามเปลี่ยน"
--
-- ทำไมไม่ใช้ postgres_changes ที่เปิดไว้แล้ว (20260827000008):
-- postgres_changes ส่ง "แถวในตาราง" ออกไปตรง ๆ แปลว่า schema ของเราคือ wire protocol
-- ซึ่งชนกับข้อจำกัดของ mobile: บังคับให้ผู้ใช้อัปเดตแอปไม่ได้ แอปเวอร์ชันเก่าจึงต้อง
-- ใช้งานได้ตลอดไป — วันที่เราเปลี่ยนความหมาย column แอปในมือคนอื่นพังทันทีและแก้ไม่ได้
--
-- broadcast ให้ server เป็นคนกำหนดรูปร่าง payload (มี v สำหรับเวอร์ชัน) ตารางเปลี่ยนได้
-- โดยไม่กระทบ contract — เป็นโมเดลเดียวกับที่ DuangLive ใช้ (event ชื่อเป็นภาษาโดเมน
-- เช่น se_start_call) แต่ไม่ต้องมีเซิร์ฟเวอร์ socket ของตัวเอง
--
-- ยังไม่ทิ้ง postgres_changes: ข้อความแชทเป็น append-only ที่ schema จะไม่ขยับ
-- ความเสี่ยงต่ำสุดและต้นทุนเป็นศูนย์ จึงคงไว้
--
-- ⚠️ realtime.messages เก็บข้อความไว้แค่ 3 วันแล้วลบทิ้ง — นี่คือ "ท่อส่ง" ไม่ใช่ที่เก็บประวัติ
-- ประวัติจริงอยู่ใน question / question_message เสมอ client ที่เพิ่งเปิดแอปต้อง fetch เอง
-- =============================================================================

-- ------------------------------------------------------------------ policy ----
-- ใครอ่าน topic 'question:<id>' ได้ = คู่สนทนาของคำถามนั้นเท่านั้น
-- (ไม่มี policy สำหรับ insert — client ห้าม broadcast เอง มีแต่ trigger ที่ยิงได้)
create policy question_participant_read_broadcast
  on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1 from public.question q
      where 'question:' || q.id::text = (select realtime.topic())
        and (select auth.uid()) in (q.user_id, q.seer_id)
    )
  );

-- ----------------------------------------------------------------- trigger ----
create or replace function public.broadcast_question_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is not distinct from new.status then
    return null;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'v',           1,
      'question_id', new.id,
      'from',        old.status,
      'to',          new.status,
      'at',          new.updated_at,
      'actor',       case
                       when new.status = 'close_requested' then new.close_requested_by
                       else null
                     end
    ),
    'status_changed',
    'question:' || new.id::text,
    true
  );

  return null;
end;
$$;

revoke all on function public.broadcast_question_status_change() from public, anon, authenticated;

create trigger question_broadcast_status_change
  after update on public.question
  for each row execute function public.broadcast_question_status_change();

comment on function public.broadcast_question_status_change() is
  'ยิง domain event status_changed ไป topic question:<id> — payload มี v สำหรับเวอร์ชัน '
  'เพื่อให้แอปเวอร์ชันเก่าอ่านได้ต่อไปแม้ schema จะเปลี่ยน';
