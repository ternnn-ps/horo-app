-- =============================================================================
-- ⚠️⚠️ DEV SEED ONLY — ห้ามรันบน production ⚠️⚠️
-- ไฟล์นี้ seed ค่าเริ่มต้นสำหรับ local dev / StoreKit local testing เท่านั้น
-- ก่อน deploy prod: ย้าย app_config ที่จำเป็นไป migration จริง แล้วตัด skill/coin_package
-- ตัวอย่างออก (product id จริงต้องมาจาก App Store Connect)
-- =============================================================================

-- ------------------------------------------------------------- app_config ----
insert into public.app_config (key, value, is_public, description) values
  ('question.reply_deadline_hours', '24', true,
   'ชั่วโมงที่ seer ต้องตอบคำถามแรกก่อนถูก auto-refund (cron เฟส 2)'),
  ('question.max_active_hours', '72', true,
   'อายุสูงสุดของคำถาม active ก่อน auto-close (cron เฟส 2)'),
  ('seer.default_revenue_share_bps', '7000', false,
   'ส่วนแบ่ง seer เป็น basis points (7000 = 70%) — เฟส 2 จะย้ายไป seer_level'),
  ('service.price_bounds',
   '{"chat_question": {"min_coin": 0, "max_coin": 100000}}', true,
   'ช่วงราคาที่ seer ตั้งได้ต่อ service type (validate ใน trigger) — เฟส 2 ย้ายไปตาราง service_type'),
  ('payment.method_psp_matrix', '{"apple_iap": ["apple"]}', false,
   'method → PSP ที่ใช้ได้เรียงตาม priority — เฟส 1 มี Apple IAP ทางเดียว'),
  ('feature.live_enabled', 'false', true, 'เปิด/ปิด domain live stream ทั้งก้อน (เฟส 2)'),
  ('feature.ai_horoscope_enabled', 'false', true, 'เปิด/ปิด domain horoscope/AI (เฟส 2)'),
  ('client.min_supported_version', '{"ios": "1.0.0", "android": null}', true,
   'เวอร์ชันแอปต่ำสุดที่รองรับ — client เช็คตอน bootstrap');

-- ------------------------------------------------------------------ skill ----
insert into public.skill (name, sort_order) values
  ('ไพ่ยิปซี', 1),
  ('ไพ่ออราเคิล', 2),
  ('โหราศาสตร์ไทย', 3),
  ('โหราศาสตร์สากล', 4),
  ('เลขศาสตร์', 5),
  ('ลายมือ', 6),
  ('ฮวงจุ้ย', 7),
  ('สัมผัสที่หก', 8),
  ('ทำนายฝัน', 9);

-- ----------------------------------------------------------- coin_package ----
-- ราคาอิง price tier ไทยของ App Store (satang); product id เป็นค่า dev สำหรับ
-- StoreKit configuration file ใน Xcode — ของจริงต้องตรงกับ App Store Connect
insert into public.coin_package
  (code, coin_amount, bonus_coin, price_minor, currency, apple_product_id, allowed_methods, sort_order)
values
  ('coin_050',  50,  0,  6900, 'THB', 'app.chata.coin050', '{apple_iap}', 1),
  ('coin_150', 150, 10, 17900, 'THB', 'app.chata.coin150', '{apple_iap}', 2),
  ('coin_300', 300, 30, 34900, 'THB', 'app.chata.coin300', '{apple_iap}', 3),
  ('coin_650', 650, 80, 69900, 'THB', 'app.chata.coin650', '{apple_iap}', 4);
