-- =============================================================================
-- seer_earning — รายได้ของหมอดูรายก้อน (reporting projection)
--
-- ทำไมต้องมีทั้งที่ ledger เก็บครบอยู่แล้ว:
--   1) ledger เป็น deny-all หมอดูอ่านเองไม่ได้ และไม่ควรอ่านได้ด้วย
--   2) ledger ตอบไม่ได้ว่า "เงินก้อนนี้มาจากงานไหน" โดยไม่ต้อง join ข้ามหลายตาราง
--   3) **ระยะรอก่อนถอนได้คิดจากวันที่ของรายได้แต่ละก้อน** — ยอดรวมใน wallet บอกไม่ได้
--      ว่าเหรียญก้อนไหนสุกแล้ว (ดู docs/specs/phase4-tickets/01)
--
-- source of truth เชิงบัญชียังคงเป็น ledger เสมอ ตารางนี้เป็น projection ที่เขียน
-- ในทรานแซกชันเดียวกันเท่านั้น — ห้ามเขียนแยกจังหวะ ไม่งั้นสองที่จะไม่ตรงกัน
-- =============================================================================

create table public.seer_earning (
  id                    bigint generated always as identity primary key,
  seer_id               uuid not null references public.account (id) on delete restrict,
  source_type           text not null
                        constraint seer_earning_source_chk
                        check (source_type in ('question', 'call', 'call_extension', 'tip', 'gift')),
  source_id             text not null,
  gross_coin            bigint not null
                        constraint seer_earning_gross_chk check (gross_coin > 0),
  seer_coin             bigint not null
                        constraint seer_earning_seer_chk check (seer_coin >= 0),
  revenue_share_bps     integer not null
                        constraint seer_earning_bps_chk check (revenue_share_bps between 0 and 10000),
  ledger_transaction_id uuid not null references public.ledger_transaction (id) on delete restrict,
  created_at            timestamptz not null default now(),
  constraint seer_earning_share_chk check (seer_coin <= gross_coin),
  -- งานเดียวเกิดรายได้ครั้งเดียว — ตัวกัน settle ซ้ำในระดับบัญชี
  constraint seer_earning_source_uniq unique (source_type, source_id)
);

comment on table public.seer_earning is
  'รายได้ของหมอดูรายก้อน (projection เขียนคู่กับ ledger settle) — '
  'owner-read ได้เพราะเป็น projection ไม่ใช่บัญชีจริง; ระยะรอก่อนถอนคิดจาก created_at';
comment on column public.seer_earning.revenue_share_bps is
  'snapshot อัตราส่วนแบ่ง ณ ตอน settle — เปลี่ยนอัตราทีหลังต้องไม่กระทบรายการเก่า';

create index seer_earning_owner_idx on public.seer_earning (seer_id, created_at desc);

-- ----------------------------------------------------------------------- RLS --
alter table public.seer_earning enable row level security;

-- อ่านได้เฉพาะของตัวเอง; ไม่มี policy สำหรับ insert/update/delete = เขียนไม่ได้เลย
create policy seer_earning_owner_select on public.seer_earning
  for select to authenticated
  using (seer_id = (select auth.uid()));

grant select on public.seer_earning to authenticated;

-- -----------------------------------------------------------------------------
-- internal_settle_question — เพิ่มการเขียน projection ในทรานแซกชันเดียวกับ ledger
--
-- ของเดิม `perform internal_post_ledger(...)` ทิ้งค่าที่คืนมา ทั้งที่มันคืน transaction id
-- ซึ่งเป็นสิ่งที่ projection ต้องใช้โยงกลับไปหาหลักฐาน
-- -----------------------------------------------------------------------------
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
  v_tx_id     uuid;
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

  perform 1 from public.wallet
  where account_id in (v_q.user_id, v_q.seer_id)
  order by account_id
  for update;

  if v_q.price_coin > 0 then
    v_share_bps := coalesce((public.get_config('seer.default_revenue_share_bps') #>> '{}')::int, 7000);
    v_seer_coin := (v_q.price_coin * v_share_bps) / 10000;
    v_fee_coin  := v_q.price_coin - v_seer_coin;

    v_entries := jsonb_build_array(
      jsonb_build_object('ledger_account', 'user_reserved', 'account_id', v_q.user_id,
                         'amount', -v_q.price_coin),
      jsonb_build_object('ledger_account', 'seer_payable', 'account_id', v_q.seer_id,
                         'amount', v_seer_coin));
    if v_fee_coin > 0 then
      v_entries := v_entries
        || jsonb_build_object('ledger_account', 'platform_revenue', 'account_id', null,
                              'amount', v_fee_coin);
    end if;

    v_tx_id := public.internal_post_ledger('question', v_q.id::text, 'settle', v_entries);

    -- projection ต้องอยู่ในทรานแซกชันเดียวกับ ledger เสมอ
    insert into public.seer_earning
      (seer_id, source_type, source_id, gross_coin, seer_coin, revenue_share_bps, ledger_transaction_id)
    values
      (v_q.seer_id, 'question', v_q.id::text, v_q.price_coin, v_seer_coin, v_share_bps, v_tx_id)
    on conflict (source_type, source_id) do nothing;
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

-- -----------------------------------------------------------------------------
-- Backfill — งานที่ปิดไปแล้วก่อนมีตารางนี้
--
-- ที่มาของตัวเลขคือ ledger ไม่ใช่การคำนวณใหม่จากอัตราปัจจุบัน — ถ้าคิดใหม่
-- รายการเก่าจะเพี้ยนทันทีที่มีใครเปลี่ยน seer.default_revenue_share_bps
-- อัตราส่วนแบ่งจึงถอดกลับจากตัวเลขจริงที่ post ไว้
-- -----------------------------------------------------------------------------
insert into public.seer_earning
  (seer_id, source_type, source_id, gross_coin, seer_coin, revenue_share_bps,
   ledger_transaction_id, created_at)
select
  e.account_id,
  'question',
  t.reference_id,
  q.price_coin,
  e.amount,
  (e.amount * 10000) / nullif(q.price_coin, 0),
  t.id,
  t.created_at
from public.ledger_transaction t
join public.ledger_entry e
  on e.transaction_id = t.id
 and e.ledger_account = 'seer_payable'
 and e.amount > 0
join public.question q
  on q.id = t.reference_id::uuid
where t.reference_type = 'question'
  and t.operation = 'settle'
  and q.price_coin > 0
on conflict (source_type, source_id) do nothing;
