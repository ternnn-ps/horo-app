-- =============================================================================
-- Chata — แก้บั๊ก: settle พังเมื่อส่วนแบ่งฝ่ายใดฝ่ายหนึ่งปัดลงเป็นศูนย์
--
-- อาการ: internal_settle_question สร้างขา ledger ของ seer_payable ด้วย amount = 0
--   ชน constraint ledger_entry_amount_chk (amount <> 0) → ทั้ง transaction ล้ม
--
-- เกิดเมื่อไหร่: floor(price_coin * share_bps / 10000) = 0
--   ที่ share 70% คือคำถามราคา 1 เหรียญ (floor(0.7) = 0)
--   ยิ่ง share ต่ำ ยิ่งกินช่วงราคากว้างขึ้น เช่น share 10% พังทุกราคา 1–9 เหรียญ
--
-- ทำไมอันตราย: เจอเฉพาะตอนมีราคาจริง ไม่เจอตอนเทสต์ด้วยราคากลม ๆ
--   และเมื่อเกิด คำถามนั้นจะปิดไม่ได้ตลอดกาล — cron พยายามซ้ำทุก 15 นาที
--   เหรียญค้างใน user_reserved ไม่มีวันหลุด ซึ่งคือปัญหาเดิมที่เฟส 2 ตั้งใจแก้
--
-- วิธีแก้: ข้ามขาที่เป็นศูนย์ (ทำแบบเดียวกับที่ขา platform_revenue ทำอยู่แล้ว)
--   ยอดรวมยังเป็นศูนย์เสมอเพราะอีกขารับไปเต็มจำนวน
-- =============================================================================

create or replace function public.internal_settle_question(
  p_question_id uuid,
  p_system      boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_q         public.question%rowtype;
  v_share_bps int;
  v_seer_coin bigint;
  v_fee_coin  bigint;
  v_entries   jsonb;
begin
  select * into v_q from public.question where id = p_question_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if v_q.status = 'completed' then
    return jsonb_build_object('question_id', v_q.id, 'status', v_q.status, 'replayed', true);
  end if;
  if v_q.status not in ('active', 'close_requested') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  -- lock กระเป๋าทั้งสองฝั่งเรียงตาม account_id — global lock order กัน deadlock
  perform 1 from public.wallet
  where account_id in (v_q.user_id, v_q.seer_id)
  order by account_id
  for update;

  if v_q.price_coin > 0 then
    v_share_bps := coalesce((public.get_config('seer.default_revenue_share_bps') #>> '{}')::int, 7000);
    v_seer_coin := (v_q.price_coin * v_share_bps) / 10000;
    v_fee_coin  := v_q.price_coin - v_seer_coin;

    -- ขาที่ผู้ใช้จ่ายออกมีเสมอ
    v_entries := jsonb_build_array(
      jsonb_build_object('ledger_account', 'user_reserved', 'account_id', v_q.user_id,
                         'amount', -v_q.price_coin));

    -- ขาปลายทางใส่เฉพาะที่ไม่เป็นศูนย์ — ledger ห้ามมีแถว amount = 0
    if v_seer_coin > 0 then
      v_entries := v_entries
        || jsonb_build_object('ledger_account', 'seer_payable', 'account_id', v_q.seer_id,
                              'amount', v_seer_coin);
    end if;
    if v_fee_coin > 0 then
      v_entries := v_entries
        || jsonb_build_object('ledger_account', 'platform_revenue', 'account_id', null,
                              'amount', v_fee_coin);
    end if;

    perform public.internal_post_ledger('question', v_q.id::text, 'settle', v_entries);
  end if;

  update public.question
  set status = 'completed', completed_at = now()
  where id = v_q.id;

  update public.seer_profile
  set question_count = question_count + 1
  where account_id = v_q.seer_id;

  insert into public.question_message
    (question_id, sender_id, client_message_id, message_type, system_event)
  values (v_q.id, null, gen_random_uuid(), 'system',
          case when p_system then 'auto_closed' else 'close_confirmed' end);

  insert into public.notification_inbox
    (account_id, notification_type, title, body, deep_link, payload)
  values (v_q.user_id, 'question_update',
          case when p_system then 'คำถามถูกปิดอัตโนมัติ' else 'คำถามของคุณปิดแล้ว' end,
          case when p_system then 'ครบกำหนดเวลาของการปรึกษาแล้ว'
               else 'การปรึกษาเสร็จสิ้น ขอบคุณที่ใช้บริการ' end,
          'chata://question/' || v_q.id,
          jsonb_build_object('question_id', v_q.id));

  insert into public.outbox_event (aggregate_type, aggregate_id, event_type, payload)
  values ('question', v_q.id::text, 'question.completed',
          jsonb_build_object('question_id', v_q.id, 'user_id', v_q.user_id,
                             'seer_id', v_q.seer_id, 'price_coin', v_q.price_coin,
                             'auto_closed', p_system));

  return jsonb_build_object('question_id', v_q.id, 'status', 'completed',
                            'auto_closed', p_system);
end;
$$;

revoke all on function public.internal_settle_question(uuid, boolean) from public, anon, authenticated;

comment on function public.internal_settle_question(uuid, boolean) is
  'แหล่งความจริงเดียวของการตัดจบจ่าย seer — เรียกจาก respond_close_question และ cron เท่านั้น. '
  'ข้ามขา ledger ที่ปัดลงเป็นศูนย์ (คำถามราคาต่ำ) เพราะ ledger_entry ห้าม amount = 0';
