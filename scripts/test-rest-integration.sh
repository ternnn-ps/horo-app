#!/usr/bin/env bash
# Integration test ที่ยิง Supabase REST API จริงด้วยสิทธิ์ authenticated (ไม่ใช่ postgres/service_role)
#
# ทำไมต้องมีทั้งที่มี db/tests/*.test.sql อยู่แล้ว: เทส SQL รันในนามเจ้าของฐานข้อมูล
# ซึ่งพิสูจน์เรื่องสิทธิ์ไม่ได้เลย (บทเรียน 20260827000007 — service_role เรียก RPC ไม่ได้
# ทั้งชุดโดยที่เทส SQL ไม่แดงสักตัว) ชุดนี้เดินผ่านเส้นทางเดียวกับที่แอปมือถือเดินจริง
#
# ใช้: ./scripts/test-rest-integration.sh     (ต้องรัน seed-dev-fixture.sh ก่อน)
# ข้ามตัวเองถ้าไม่มี Supabase local รันอยู่

set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-fixture.env

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
ANON_KEY="${ANON_KEY:-}"

if [[ -z "$ANON_KEY" ]]; then
  ANON_KEY=$(supabase status -o env 2>/dev/null | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')
fi

# ข้ามเมื่อ "ต่อไม่ติด" เท่านั้น ไม่ใช่เมื่อ server ตอบ error
# (cloud ตอบ 401 ที่ root ทำให้ curl -f ล้ม แล้วเทสข้ามตัวเองทั้งชุดโดยไม่มีใครรู้)
if ! curl -s -m 5 -o /dev/null "$SUPABASE_URL/auth/v1/health"; then
  echo "SKIP: ไม่มี Supabase ที่ $SUPABASE_URL — ข้ามชุดนี้ (ไม่ถือว่าล้มเหลว)"
  exit 0
fi

# ชุดนี้กินเหรียญของบัญชีทดสอบทุกรอบ จึงเรียก fixture ก่อนเสมอเพื่อเติมกลับให้ครบ
# (fixture รันซ้ำได้ ไม่สร้างของซ้ำ) — ข้ามได้ด้วย SKIP_FIXTURE=1
if [[ "${SKIP_FIXTURE:-0}" != "1" ]]; then
  if ! ./scripts/seed-dev-fixture.sh >/dev/null 2>&1; then
    echo "❌ เตรียม fixture ไม่สำเร็จ — ลองรัน ./scripts/seed-dev-fixture.sh ดูข้อความเต็ม"
    exit 1
  fi
fi

IS_LOCAL=0
case "$SUPABASE_URL" in *127.0.0.1*|*localhost*) IS_LOCAL=1 ;; esac

# `supabase start` เสิร์ฟ function ให้ แต่ไม่โหลด .env.local — verify-iap จะตอบ 403 ตลอด
# จึงต้องยกตัวเสิร์ฟที่มี env ขึ้นมาเอง (เฉพาะ local; บน cloud ใช้ที่ deploy ไว้)
FN_SERVE_PID=""
cleanup() { [[ -n "$FN_SERVE_PID" ]] && kill "$FN_SERVE_PID" 2>/dev/null; return 0; }
trap cleanup EXIT

if (( IS_LOCAL )); then
  ./scripts/serve-functions.sh >/dev/null 2>&1 &
  FN_SERVE_PID=$!
  for _ in $(seq 1 30); do
    curl -s -m 2 -o /dev/null "$SUPABASE_URL/functions/v1/verify-iap" && break
    sleep 1
  done
fi

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; [[ -n "${2:-}" ]] && echo "     └─ $2"; }

# คืน access token ของบัญชี หรือสตริงว่างถ้า login ไม่ผ่าน
login() {
  curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.access_token // empty'
}

api() {
  local token=$1 method=$2 path=$3 body=${4:-}
  if [[ -n "$body" ]]; then
    curl -s -X "$method" "$SUPABASE_URL/rest/v1/$path" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -s -X "$method" "$SUPABASE_URL/rest/v1/$path" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token"
  fi
}

# เรียก Edge Function — คนละ base path กับ REST และตอบ error คนละรูป (`{error,detail}`)
fn() {
  local token=$1 method=$2 name=$3 body=${4:-}
  if [[ -n "$body" ]]; then
    curl -s -X "$method" "$SUPABASE_URL/functions/v1/$name" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -s -X "$method" "$SUPABASE_URL/functions/v1/$name" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token"
  fi
}

# เปลี่ยนโหมด IAP ในฐาน — ทำได้เฉพาะ local (ตาราง app_config เป็น deny-all สำหรับ client)
set_iap_mode() {
  docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
    "update public.app_config set value = '\"$1\"'::jsonb where key = 'payment.iap_mode'" >/dev/null 2>&1
}

echo "── 1. fixture user login แล้วอ่านกระเป๋าตัวเองได้"

USER_TOKEN=$(login "$FIXTURE_USER_EMAIL" "$FIXTURE_USER_PASSWORD")
if [[ -z "$USER_TOKEN" ]]; then
  bad "login ด้วยบัญชี fixture ($FIXTURE_USER_EMAIL)" "ยังไม่มีบัญชีนี้ — รัน ./scripts/seed-dev-fixture.sh ก่อน"
else
  ok "login ด้วยบัญชี fixture"

  WALLET=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin,reserved_coin")
  # 0 เป็นยอดที่ถูกต้อง — `// empty` จะทำให้กระเป๋าว่างถูกรายงานว่า "อ่านไม่ได้"
  AVAILABLE=$(echo "$WALLET" | jq -r 'if type == "array" and length > 0 then (.[0].available_coin | tostring) else "" end')

  if [[ -z "$AVAILABLE" ]]; then
    bad "อ่าน v_my_wallet ได้" "$WALLET"
  elif (( AVAILABLE < FIXTURE_USER_START_COIN )); then
    bad "กระเป๋ามีเหรียญตั้งต้นอย่างน้อย $FIXTURE_USER_START_COIN" "ได้ $AVAILABLE"
  else
    ok "กระเป๋ามีเหรียญตั้งต้น $AVAILABLE"
  fi
fi

echo
echo "── 2. เห็นหมอดูที่เปิดรับงาน แล้วซื้อคำถามได้ (เหรียญเข้า escrow)"

# เจาะจง service ของหมอดูใน fixture เสมอ — ถ้าเลือกแบบ limit=1 เฉย ๆ จะไปได้หมอดูเก่าที่ค้าง
# ในฐานจากการรันครั้งก่อน แล้วเทสจะล้มแบบงง ๆ ตอนหมอดูของเราเข้าไปตอบไม่ได้
SEER_TOKEN=$(login "$FIXTURE_SEER_EMAIL" "$FIXTURE_SEER_PASSWORD")
SEER_ACCOUNT_ID=$(curl -s "$SUPABASE_URL/auth/v1/user" -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $SEER_TOKEN" | jq -r '.id // empty')
SERVICE=$(api "$USER_TOKEN" GET "seer_service?seer_id=eq.$SEER_ACCOUNT_ID&is_enabled=eq.true&select=id,seer_id,price_coin&limit=1")
SERVICE_ID=$(echo "$SERVICE" | jq -r '.[0].id // empty')
PRICE=$(echo "$SERVICE" | jq -r '.[0].price_coin // empty')

if [[ -z "$SERVICE_ID" ]]; then
  bad "เห็น service ของหมอดูที่เปิดรับงาน" "ไม่มีแถวที่มองเห็นผ่าน RLS — fixture ยังไม่ได้สร้างหมอดู"
else
  ok "เห็น service ของหมอดู ราคา $PRICE เหรียญ"

  BEFORE=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin,reserved_coin")
  BEFORE_AVAILABLE=$(echo "$BEFORE" | jq -r '.[0].available_coin')
  BEFORE_RESERVED=$(echo "$BEFORE" | jq -r '.[0].reserved_coin')

  REQ_ID=$(uuidgen | tr 'A-Z' 'a-z')
  MSG_ID=$(uuidgen | tr 'A-Z' 'a-z')
  SUBMIT=$(api "$USER_TOKEN" POST "rpc/submit_question" \
    "{\"p_seer_service_id\":\"$SERVICE_ID\",\"p_first_message\":\"ทดสอบซื้อคำถามจาก REST\",\"p_client_message_id\":\"$MSG_ID\",\"p_client_request_id\":\"$REQ_ID\"}")
  QUESTION_ID=$(echo "$SUBMIT" | jq -r '.question_id // empty')

  if [[ -z "$QUESTION_ID" ]]; then
    bad "submit_question สำเร็จ" "$SUBMIT"
  else
    ok "ซื้อคำถามสำเร็จ (status=$(echo "$SUBMIT" | jq -r .status))"

    AFTER=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin,reserved_coin")
    AFTER_AVAILABLE=$(echo "$AFTER" | jq -r '.[0].available_coin')
    AFTER_RESERVED=$(echo "$AFTER" | jq -r '.[0].reserved_coin')

    if (( AFTER_AVAILABLE == BEFORE_AVAILABLE - PRICE )) && (( AFTER_RESERVED == BEFORE_RESERVED + PRICE )); then
      ok "เหรียญเข้า escrow ถูกต้อง (available ${BEFORE_AVAILABLE}→$AFTER_AVAILABLE, reserved ${BEFORE_RESERVED}→$AFTER_RESERVED)"
    else
      bad "เหรียญเข้า escrow ถูกต้อง" "available ${BEFORE_AVAILABLE}→$AFTER_AVAILABLE, reserved ${BEFORE_RESERVED}→$AFTER_RESERVED, ราคา $PRICE"
    fi
  fi
fi

echo
echo "── 3. ยิงซ้ำด้วย client_request_id เดิม ต้องไม่หักเหรียญรอบสอง"

if [[ -n "${QUESTION_ID:-}" ]]; then
  REPLAY=$(api "$USER_TOKEN" POST "rpc/submit_question" \
    "{\"p_seer_service_id\":\"$SERVICE_ID\",\"p_first_message\":\"ทดสอบซื้อคำถามจาก REST\",\"p_client_message_id\":\"$MSG_ID\",\"p_client_request_id\":\"$REQ_ID\"}")

  # ห้าม `// empty` กับ boolean — jq ถือว่า false เป็น falsy แล้วตกไปเป็นค่าว่าง
  # แยกไม่ออกจากกรณีที่ไม่มีฟิลด์เลย ทำให้ข้อความบอกสาเหตุผิด
  if [[ "$(echo "$REPLAY" | jq -r '.replayed')" != "true" ]]; then
    bad "ยิงซ้ำแล้วได้ replayed=true" "$REPLAY"
  elif [[ "$(echo "$REPLAY" | jq -r '.question_id')" != "$QUESTION_ID" ]]; then
    bad "ยิงซ้ำแล้วได้ question เดิม" "ได้ $(echo "$REPLAY" | jq -r '.question_id') แทน $QUESTION_ID"
  else
    ok "ยิงซ้ำได้ question เดิม (replayed=true)"
  fi

  REPLAY_WALLET=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin,reserved_coin")
  REPLAY_AVAILABLE=$(echo "$REPLAY_WALLET" | jq -r '.[0].available_coin')

  if (( REPLAY_AVAILABLE == AFTER_AVAILABLE )); then
    ok "ยอดเหรียญไม่ขยับหลังยิงซ้ำ (คงที่ $REPLAY_AVAILABLE)"
  else
    bad "ยอดเหรียญไม่ขยับหลังยิงซ้ำ" "$AFTER_AVAILABLE → $REPLAY_AVAILABLE (หักซ้ำ)"
  fi

  NEW_REQ=$(uuidgen | tr 'A-Z' 'a-z')
  NEW_MSG=$(uuidgen | tr 'A-Z' 'a-z')
  FRESH=$(api "$USER_TOKEN" POST "rpc/submit_question" \
    "{\"p_seer_service_id\":\"$SERVICE_ID\",\"p_first_message\":\"ทดสอบซื้อคำถามจาก REST\",\"p_client_message_id\":\"$NEW_MSG\",\"p_client_request_id\":\"$NEW_REQ\"}")
  FRESH_ID=$(echo "$FRESH" | jq -r '.question_id // empty')

  if [[ -n "$FRESH_ID" && "$FRESH_ID" != "$QUESTION_ID" ]]; then
    ok "key ใหม่ = คำถามใหม่จริง (พิสูจน์ว่า replay ข้างบนไม่ได้มาจากการที่ RPC ปฏิเสธทุกอย่าง)"
  else
    bad "key ใหม่ต้องได้คำถามใหม่" "$FRESH"
  fi
else
  bad "ทดสอบ replay ได้" "ข้ามเพราะซื้อคำถามในข้อ 2 ไม่สำเร็จ"
fi

echo
echo "── 4. คนนอกห้องต้องอ่านไม่เห็นและเขียนไม่ได้ (RLS ผ่าน HTTP จริง)"

OUTSIDER_TOKEN=$(login "$FIXTURE_OUTSIDER_EMAIL" "$FIXTURE_OUTSIDER_PASSWORD")
if [[ -z "$OUTSIDER_TOKEN" || -z "${QUESTION_ID:-}" ]]; then
  bad "เตรียมบัญชีคนนอกได้" "ไม่มี token หรือไม่มีคำถามให้ทดสอบ"
else
  # ต้องยืนยันว่าเป็น "อาเรย์ว่าง" จริง ๆ — `length` บน error object นับ key ได้ ไม่ใช่ 0
  # ข้อพวกนี้คือข้อที่พิสูจน์เรื่องสิทธิ์ ปล่อยให้คลุมเครือไม่ได้
  SEEN=$(api "$OUTSIDER_TOKEN" GET "question?id=eq.$QUESTION_ID&select=id" | jq -r 'if type == "array" then length else "ไม่ใช่อาเรย์: " + tostring end')
  [[ "$SEEN" == "0" ]] && ok "คนนอกอ่าน question ไม่เห็น" || bad "คนนอกอ่าน question ไม่เห็น" "เห็น $SEEN แถว"

  SEEN_MSG=$(api "$OUTSIDER_TOKEN" GET "question_message?question_id=eq.$QUESTION_ID&select=id" | jq -r 'if type == "array" then length else "ไม่ใช่อาเรย์: " + tostring end')
  [[ "$SEEN_MSG" == "0" ]] && ok "คนนอกอ่านข้อความไม่เห็น" || bad "คนนอกอ่านข้อความไม่เห็น" "เห็น $SEEN_MSG แถว"

  OUTSIDER_ID=$(curl -s "$SUPABASE_URL/auth/v1/user" -H "apikey: $ANON_KEY" \
    -H "Authorization: Bearer $OUTSIDER_TOKEN" | jq -r '.id')
  INTRUDE=$(api "$OUTSIDER_TOKEN" POST "question_message" \
    "{\"question_id\":\"$QUESTION_ID\",\"sender_id\":\"$OUTSIDER_ID\",\"client_message_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"message_type\":\"text\",\"content\":\"แทรกห้องคนอื่น\"}")
  if [[ -n "$(echo "$INTRUDE" | jq -r '.code // empty')" ]]; then
    ok "คนนอกเขียนข้อความเข้าห้องไม่ได้ ($(echo "$INTRUDE" | jq -r '.code'))"
  else
    bad "คนนอกเขียนข้อความเข้าห้องไม่ได้" "$INTRUDE"
  fi
fi

echo
echo "── 5. ครบวงจรเงิน: หมอดูตอบ → ขอปิดงาน → ผู้ใช้ยืนยัน → เงินถึงหมอดู"

if [[ -z "$SEER_TOKEN" || -z "${QUESTION_ID:-}" ]]; then
  bad "เตรียมบัญชีหมอดูได้" "ไม่มี token หรือไม่มีคำถามให้ทดสอบ"
else
  IN_QUEUE=$(api "$SEER_TOKEN" GET "question?id=eq.$QUESTION_ID&select=id,status" | jq -r '.[0].status // empty')
  [[ "$IN_QUEUE" == "submitted" ]] && ok "หมอดูเห็นคำถามในคิว (status=submitted)" \
    || bad "หมอดูเห็นคำถามในคิว" "ได้ '$IN_QUEUE'"

  REPLY=$(api "$SEER_TOKEN" POST "question_message" \
    "{\"question_id\":\"$QUESTION_ID\",\"sender_id\":\"$SEER_ACCOUNT_ID\",\"client_message_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"message_type\":\"text\",\"content\":\"คำตอบสำหรับการทดสอบ\"}")
  if [[ -n "$(echo "$REPLY" | jq -r '.code // empty')" ]]; then
    bad "หมอดูตอบข้อความได้" "$REPLY"
  else
    ok "หมอดูตอบข้อความได้"
  fi

  STATUS_AFTER_REPLY=$(api "$SEER_TOKEN" GET "question?id=eq.$QUESTION_ID&select=status" | jq -r '.[0].status')
  [[ "$STATUS_AFTER_REPLY" == "active" ]] && ok "ตอบแล้วสถานะเลื่อนเป็น active เอง" \
    || bad "ตอบแล้วสถานะเลื่อนเป็น active เอง" "ได้ '$STATUS_AFTER_REPLY'"

  SEER_BEFORE=$(api "$SEER_TOKEN" GET "v_my_wallet?select=payable_coin" | jq -r '.[0].payable_coin')
  USER_RESERVED_BEFORE=$(api "$USER_TOKEN" GET "v_my_wallet?select=reserved_coin" | jq -r '.[0].reserved_coin')

  CLOSE_REQ=$(api "$SEER_TOKEN" POST "rpc/request_close_question" "{\"p_question_id\":\"$QUESTION_ID\"}")
  [[ -z "$(echo "$CLOSE_REQ" | jq -r '.code // empty')" ]] && ok "หมอดูขอปิดงานได้" \
    || bad "หมอดูขอปิดงานได้" "$CLOSE_REQ"

  ACCEPT=$(api "$USER_TOKEN" POST "rpc/respond_close_question" \
    "{\"p_question_id\":\"$QUESTION_ID\",\"p_accept\":true}")
  [[ -z "$(echo "$ACCEPT" | jq -r '.code // empty')" ]] && ok "ผู้ใช้ยืนยันปิดงานได้" \
    || bad "ผู้ใช้ยืนยันปิดงานได้" "$ACCEPT"

  FINAL_STATUS=$(api "$USER_TOKEN" GET "question?id=eq.$QUESTION_ID&select=status" | jq -r '.[0].status')
  [[ "$FINAL_STATUS" == "completed" ]] && ok "คำถามปิดเป็น completed" \
    || bad "คำถามปิดเป็น completed" "ได้ '$FINAL_STATUS'"

  SEER_AFTER=$(api "$SEER_TOKEN" GET "v_my_wallet?select=payable_coin" | jq -r '.[0].payable_coin')
  USER_RESERVED_AFTER=$(api "$USER_TOKEN" GET "v_my_wallet?select=reserved_coin" | jq -r '.[0].reserved_coin')

  SHARE_BPS=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
    "select public.get_config('seer.default_revenue_share_bps') #>> '{}'" 2>/dev/null || echo 7000)
  EXPECTED_SHARE=$(( PRICE * SHARE_BPS / 10000 ))

  if (( SEER_AFTER == SEER_BEFORE + EXPECTED_SHARE )); then
    ok "หมอดูได้ส่วนแบ่ง $EXPECTED_SHARE เหรียญ (payable ${SEER_BEFORE}→$SEER_AFTER)"
  else
    bad "หมอดูได้ส่วนแบ่ง $EXPECTED_SHARE เหรียญ" "payable ${SEER_BEFORE}→$SEER_AFTER"
  fi

  if (( USER_RESERVED_AFTER == USER_RESERVED_BEFORE - PRICE )); then
    ok "เหรียญออกจาก escrow ของผู้ใช้ครบ (reserved ${USER_RESERVED_BEFORE}→$USER_RESERVED_AFTER)"
  else
    bad "เหรียญออกจาก escrow ของผู้ใช้ครบ" "reserved ${USER_RESERVED_BEFORE}→$USER_RESERVED_AFTER, ราคา $PRICE"
  fi

  # รายได้ต้องถูกบันทึกเป็นรายการที่หมอดูอ่านเองได้ ไม่ใช่มีแต่ยอดรวมใน wallet
  # (ยอดรวมบอกไม่ได้ว่าเงินมาจากงานไหน และระยะรอก่อนถอนต้องคิดจากวันที่ของแต่ละก้อน)
  EARNING=$(api "$SEER_TOKEN" GET "seer_earning?source_type=eq.question&source_id=eq.$QUESTION_ID&select=gross_coin,seer_coin,revenue_share_bps,ledger_transaction_id")
  E_GROSS=$(echo "$EARNING" | jq -r '.[0].gross_coin // empty')
  E_SEER=$(echo "$EARNING" | jq -r '.[0].seer_coin // empty')
  E_BPS=$(echo "$EARNING" | jq -r '.[0].revenue_share_bps // empty')
  E_TX=$(echo "$EARNING" | jq -r '.[0].ledger_transaction_id // empty')

  if [[ "$E_GROSS" == "$PRICE" && "$E_SEER" == "$EXPECTED_SHARE" ]]; then
    ok "หมอดูเห็นรายการรายได้ของงานนี้ (ลูกค้าจ่าย $E_GROSS → เข้าหมอดู $E_SEER)"
  else
    bad "หมอดูเห็นรายการรายได้ของงานนี้ (คาด gross=$PRICE seer=$EXPECTED_SHARE)" "$EARNING"
  fi

  [[ "$E_BPS" == "$SHARE_BPS" ]] \
    && ok "รายการเก็บอัตราส่วนแบ่ง ณ ตอนนั้นไว้ ($E_BPS bps)" \
    || bad "รายการเก็บอัตราส่วนแบ่ง ณ ตอนนั้น" "ได้ '$E_BPS' คาด '$SHARE_BPS'"

  [[ -n "$E_TX" && "$E_TX" != "null" ]] \
    && ok "รายการโยงกลับไปหาหลักฐานใน ledger ได้" \
    || bad "รายการโยงกลับไปหาหลักฐานใน ledger" "$EARNING"

  # ผลรวมรายได้ทุกก้อนต้องเท่ากับยอดค้างจ่าย ไม่งั้นแปลว่ามีรายได้ที่ไม่ได้ถูกบันทึกเป็นรายการ
  # (ดักเคสลืม backfill ของเก่าที่ปิดงานไปก่อนมีตารางนี้)
  SUM_EARN=$(api "$SEER_TOKEN" GET "seer_earning?select=seer_coin" | jq '[.[].seer_coin] | add // 0')
  if [[ "$SUM_EARN" == "$SEER_AFTER" ]]; then
    ok "ผลรวมรายการรายได้ตรงกับยอดค้างจ่าย ($SUM_EARN)"
  else
    bad "ผลรวมรายการรายได้ต้องตรงกับยอดค้างจ่าย" "รวมรายการได้ $SUM_EARN แต่ payable = $SEER_AFTER"
  fi

  # ต้องได้ "อาเรย์ว่าง" เท่านั้น — ถ้าเป็น error object แล้วนับ key ได้ 0 ก็จะเขียวทั้งที่ไม่ได้พิสูจน์อะไร
  OUT_EARN=$(api "$OUTSIDER_TOKEN" GET "seer_earning?select=id" | jq -r 'if type == "array" then length else "ไม่ใช่อาเรย์: " + tostring end')
  [[ "$OUT_EARN" == "0" ]] \
    && ok "คนอื่นอ่านรายได้ของหมอดูไม่เห็น (อาเรย์ว่าง)" \
    || bad "คนอื่นอ่านรายได้ของหมอดูไม่เห็น" "ได้ $OUT_EARN"

  WRITE_EARN=$(api "$SEER_TOKEN" POST "seer_earning" \
    "{\"seer_id\":\"$SEER_ACCOUNT_ID\",\"source_type\":\"tip\",\"source_id\":\"$(uuidgen)\",\"gross_coin\":999999,\"seer_coin\":999999,\"revenue_share_bps\":10000}")
  # ต้องเป็น 42501 (ไม่มีสิทธิ์) เท่านั้น — ถ้ารับ error อะไรก็ได้ เทสจะเขียวตอนตารางยังไม่มีด้วย
  WRITE_CODE=$(echo "$WRITE_EARN" | jq -r '.code // "ไม่มี code"')
  [[ "$WRITE_CODE" == "42501" ]] \
    && ok "หมอดูเขียนรายได้ให้ตัวเองไม่ได้ (42501)" \
    || bad "หมอดูเขียนรายได้ให้ตัวเองไม่ได้ ต้องได้ 42501" "ได้ '$WRITE_CODE' · $WRITE_EARN"

  # ตรวจ ledger ต้องเข้าฐานตรง ๆ (ตาราง deny-all ไม่มีทางอ่านผ่าน API) — ทำได้เฉพาะ local
  if [[ "$SUPABASE_URL" == *"127.0.0.1"* || "$SUPABASE_URL" == *"localhost"* ]]; then
    LEDGER=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select count(*) from (select transaction_id from public.ledger_entry group by transaction_id having sum(amount) <> 0) t" 2>/dev/null || echo "?")
    [[ "$LEDGER" == "0" ]] && ok "ledger สมดุลทุกธุรกรรม" || bad "ledger สมดุลทุกธุรกรรม" "พบ $LEDGER รายการไม่สมดุล"
  else
    echo "  ⏭  ข้ามการตรวจ ledger (ต่อ psql เข้า remote ตรง ๆ ไม่ได้)"
  fi
fi

echo
echo "── 6. Realtime: ข้อความใหม่ต้องส่งถึงอีกฝ่ายเองโดยไม่ต้องรีเฟรช"

if ! command -v deno >/dev/null 2>&1; then
  echo "  ⏭  ข้าม (ไม่มี deno ในเครื่อง)"
elif [[ -z "${FRESH_ID:-}" ]]; then
  bad "ทดสอบ realtime ได้" "ไม่มีคำถามที่ยังเปิดอยู่ให้ทดสอบ"
else
  PROBE_OUT=$(mktemp)
  deno run -A --quiet scripts/realtime-probe.ts \
    "$SUPABASE_URL" "$ANON_KEY" "$USER_TOKEN" "$FRESH_ID" 12000 >"$PROBE_OUT" 2>&1 &
  PROBE_PID=$!

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q "READY" "$PROBE_OUT" 2>/dev/null && break
    perl -e 'select undef, undef, undef, 0.5'
  done

  api "$SEER_TOKEN" POST "question_message" \
    "{\"question_id\":\"$FRESH_ID\",\"sender_id\":\"$SEER_ACCOUNT_ID\",\"client_message_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"message_type\":\"text\",\"content\":\"ข้อความทดสอบ realtime\"}" >/dev/null

  if wait $PROBE_PID; then
    ok "ผู้ใช้ได้รับข้อความของหมอดูผ่าน Realtime"
  else
    bad "ผู้ใช้ได้รับข้อความของหมอดูผ่าน Realtime" "$(cat "$PROBE_OUT")"
  fi
  rm -f "$PROBE_OUT"
fi

echo
echo "── 7. Broadcast แบบ domain event: สถานะ question เปลี่ยน ต้องรู้ว่าเปลี่ยนจากอะไรเป็นอะไร"

if ! command -v deno >/dev/null 2>&1; then
  echo "  ⏭  ข้าม (ไม่มี deno ในเครื่อง)"
else
  BC_REQ=$(uuidgen | tr 'A-Z' 'a-z')
  BC_MSG=$(uuidgen | tr 'A-Z' 'a-z')
  BC=$(api "$USER_TOKEN" POST "rpc/submit_question" \
    "{\"p_seer_service_id\":\"$SERVICE_ID\",\"p_first_message\":\"ทดสอบ broadcast\",\"p_client_message_id\":\"$BC_MSG\",\"p_client_request_id\":\"$BC_REQ\"}")
  BC_ID=$(echo "$BC" | jq -r '.question_id // empty')

  if [[ -z "$BC_ID" ]]; then
    bad "เตรียมคำถามสำหรับทดสอบ broadcast" "$BC"
  else
    BC_OUT=$(mktemp)
    deno run -A --quiet scripts/realtime-probe.ts \
      "$SUPABASE_URL" "$ANON_KEY" "$USER_TOKEN" "$BC_ID" 12000 broadcast >"$BC_OUT" 2>&1 &
    BC_PID=$!

    for _ in 1 2 3 4 5 6 7 8 9 10; do
      grep -q "READY" "$BC_OUT" 2>/dev/null && break
      perl -e 'select undef, undef, undef, 0.5'
    done

    api "$SEER_TOKEN" POST "question_message" \
      "{\"question_id\":\"$BC_ID\",\"sender_id\":\"$SEER_ACCOUNT_ID\",\"client_message_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"message_type\":\"text\",\"content\":\"ตอบเพื่อให้สถานะเปลี่ยน\"}" >/dev/null

    if wait $BC_PID; then
      BC_EVENT=$(grep '^RECEIVED' "$BC_OUT" | sed 's/^RECEIVED //')
      EVENT_NAME=$(echo "$BC_EVENT" | jq -r '.event // empty')
      FROM=$(echo "$BC_EVENT" | jq -r '.payload.from // empty')
      TO=$(echo "$BC_EVENT" | jq -r '.payload.to // empty')

      [[ "$EVENT_NAME" == "status_changed" ]] && ok "ได้รับ event ชื่อ status_changed" \
        || bad "ได้รับ event ชื่อ status_changed" "ได้ '$EVENT_NAME'"

      if [[ "$FROM" == "submitted" && "$TO" == "active" ]]; then
        ok "payload บอกได้ว่าเปลี่ยนจาก submitted → active (ไม่ใช่แค่ส่งแถวดิบมา)"
      else
        bad "payload บอกได้ว่าเปลี่ยนจาก submitted → active" "from='$FROM' to='$TO' · $BC_EVENT"
      fi
    else
      bad "ผู้ใช้ได้รับ broadcast ของสถานะที่เปลี่ยน" "$(cat "$BC_OUT")"
    fi

    OUT_BC=$(mktemp)
    deno run -A --quiet scripts/realtime-probe.ts \
      "$SUPABASE_URL" "$ANON_KEY" "$OUTSIDER_TOKEN" "$BC_ID" 4000 broadcast >"$OUT_BC" 2>&1
    if grep -q "RECEIVED" "$OUT_BC"; then
      bad "คนนอกต้องไม่ได้รับ broadcast ของห้องคนอื่น" "$(cat "$OUT_BC")"
    else
      ok "คนนอกไม่ได้รับ broadcast ของห้องคนอื่น ($(head -1 "$OUT_BC"))"
    fi
    rm -f "$BC_OUT" "$OUT_BC"
  fi
fi

echo
echo "── 8. เติมเหรียญโหมด dev ผ่าน Edge Function verify-iap"

# แพ็กต้องมาจากตารางจริง — apple_product_id คือค่าที่ verify-iap ใช้หาว่าเติมกี่เหรียญ
PKG=$(api "$USER_TOKEN" GET "coin_package?is_enabled=eq.true&apple_product_id=not.is.null&order=sort_order.asc&select=apple_product_id,coin_amount,bonus_coin&limit=1")
PRODUCT_ID=$(echo "$PKG" | jq -r '.[0].apple_product_id // empty')
PKG_COIN=$(( $(echo "$PKG" | jq -r '.[0].coin_amount // 0') + $(echo "$PKG" | jq -r '.[0].bonus_coin // 0') ))

if [[ -z "$PRODUCT_ID" ]]; then
  bad "อ่านแพ็กเติมเหรียญจากตาราง coin_package ได้" "$PKG"
else
  ok "แพ็กมาจากตารางจริง: $PRODUCT_ID (+$PKG_COIN เหรียญ)"

  AVAIL=$(fn "$USER_TOKEN" GET "verify-iap")
  MODE=$(echo "$AVAIL" | jq -r '.mode // empty')
  # ห้ามใช้ `// empty` กับค่า boolean — jq ถือว่า false เป็น falsy แล้วตกไปเป็น empty
  ALLOWED=$(echo "$AVAIL" | jq -r '.dev_topup_allowed')

  if [[ -z "$MODE" ]]; then
    bad "ถามเซิร์ฟเวอร์ได้ว่าเปิดให้เติมแบบ dev ไหม" "$AVAIL"
  else
    ok "เซิร์ฟเวอร์ตอบโหมด '$MODE' · เติมแบบ dev ได้: $ALLOWED"
  fi

  if [[ "$ALLOWED" == "true" ]]; then
    BEFORE_TOPUP=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin" | jq -r '.[0].available_coin')
    TXN="dev-topup-$(uuidgen | tr 'A-Z' 'a-z')"
    CREDIT=$(fn "$USER_TOKEN" POST "verify-iap" "{\"productId\":\"$PRODUCT_ID\",\"transactionId\":\"$TXN\"}")
    CREDITED=$(echo "$CREDIT" | jq -r '.coin_credited // empty')
    AFTER_TOPUP=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin" | jq -r '.[0].available_coin')

    if [[ "$CREDITED" == "$PKG_COIN" ]] && (( AFTER_TOPUP == BEFORE_TOPUP + PKG_COIN )); then
      ok "เติมสำเร็จ เหรียญเพิ่มเท่าแพ็กพอดี (${BEFORE_TOPUP}→$AFTER_TOPUP)"
    else
      bad "เติมสำเร็จ เหรียญเพิ่มเท่าแพ็ก $PKG_COIN" "ได้ credited='$CREDITED' ${BEFORE_TOPUP}→$AFTER_TOPUP · $CREDIT"
    fi

    # ใบเสร็จซ้ำต้องไม่เติมรอบสอง — ตัวกันอยู่ที่ unique constraint ของ iap_receipt
    REPLAY=$(fn "$USER_TOKEN" POST "verify-iap" "{\"productId\":\"$PRODUCT_ID\",\"transactionId\":\"$TXN\"}")
    REPLAYED=$(echo "$REPLAY" | jq -r '.already_credited // empty')
    REPLAY_AFTER=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin" | jq -r '.[0].available_coin')

    if [[ "$REPLAYED" == "true" ]] && (( REPLAY_AFTER == AFTER_TOPUP )); then
      ok "ยิงใบเสร็จเดิมซ้ำ → already_credited และเหรียญไม่ขยับรอบสอง"
    else
      bad "ยิงใบเสร็จเดิมซ้ำแล้วเหรียญต้องไม่ขยับ" "already_credited='$REPLAYED' ${AFTER_TOPUP}→$REPLAY_AFTER · $REPLAY"
    fi
  else
    echo "  ⏭  ข้ามการเติมจริง (เซิร์ฟเวอร์ไม่เปิดให้ — ถูกต้องแล้วถ้าเป็น cloud)"
  fi

  # โหมดที่ไม่ใช่ local_test ต้องปฏิเสธ — สลับโหมดได้เฉพาะ local เพราะ app_config เป็น deny-all
  if (( IS_LOCAL )); then
    ORIGINAL_MODE="$MODE"
    set_iap_mode "production"

    GUARD=$(fn "$USER_TOKEN" GET "verify-iap")
    GUARD_ALLOWED=$(echo "$GUARD" | jq -r '.dev_topup_allowed')
    [[ "$GUARD_ALLOWED" == "false" ]] \
      && ok "โหมด production → เซิร์ฟเวอร์บอกว่าเติมแบบ dev ไม่ได้ (ปุ่มในแอปจะหายเอง)" \
      || bad "โหมด production → dev_topup_allowed ต้องเป็น false" "ได้ '$GUARD_ALLOWED' · $GUARD"

    GUARD_BEFORE=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin" | jq -r '.[0].available_coin')
    REJECT=$(fn "$USER_TOKEN" POST "verify-iap" "{\"productId\":\"$PRODUCT_ID\",\"transactionId\":\"must-be-rejected-$(uuidgen | tr 'A-Z' 'a-z')\"}")
    GUARD_AFTER=$(api "$USER_TOKEN" GET "v_my_wallet?select=available_coin" | jq -r '.[0].available_coin')
    REJECT_ERROR=$(echo "$REJECT" | jq -r '.error // empty')

    if [[ -n "$REJECT_ERROR" ]] && (( GUARD_AFTER == GUARD_BEFORE )); then
      ok "โหมด production → ยิงเติมแบบ dev ถูกปฏิเสธ ('$REJECT_ERROR') และเหรียญไม่ขยับ"
    else
      bad "โหมด production → ต้องปฏิเสธและเหรียญห้ามขยับ" "$REJECT · ${GUARD_BEFORE}→$GUARD_AFTER"
    fi

    set_iap_mode "${ORIGINAL_MODE:-local_test}"
    RESTORED=$(fn "$USER_TOKEN" GET "verify-iap" | jq -r '.mode // empty')
    [[ "$RESTORED" == "${ORIGINAL_MODE:-local_test}" ]] \
      && ok "คืนโหมดเดิม '$RESTORED' ให้ฐานเรียบร้อย" \
      || bad "คืนโหมดเดิมให้ฐาน" "ตอนนี้เป็น '$RESTORED' — แก้ด้วยมือ: update app_config set value='\"local_test\"' where key='payment.iap_mode'"
  else
    echo "  ⏭  ข้ามการทดสอบสลับโหมด (แก้ app_config บน remote ตรง ๆ ไม่ได้)"
  fi
fi

echo
echo "── 9. บัญชีรับเงินของหมอดู + การตรวจ KYC"

SAVE_ACC=$(api "$SEER_TOKEN" POST "rpc/set_payout_account" \
  "{\"p_bank_code\":\"kbank\",\"p_account_number\":\"1234567890\",\"p_account_holder_name\":\"หมอดูทดสอบ\"}")
ACC_ID=$(echo "$SAVE_ACC" | jq -r '.payout_account_id // empty')

if [[ -z "$ACC_ID" ]]; then
  bad "หมอดูบันทึกบัญชีรับเงินได้" "$SAVE_ACC"
else
  ok "หมอดูบันทึกบัญชีรับเงินได้"

  MYACC=$(api "$SEER_TOKEN" GET "v_my_payout_account?select=bank_code,account_number_last4,verify_status,reject_reason")
  LAST4=$(echo "$MYACC" | jq -r '.[0].account_number_last4 // empty')
  VSTATUS=$(echo "$MYACC" | jq -r '.[0].verify_status // empty')

  [[ "$LAST4" == "7890" && "$VSTATUS" == "pending" ]] \
    && ok "หมอดูเห็นแค่ 4 ตัวท้าย ($LAST4) และสถานะรอตรวจ" \
    || bad "หมอดูเห็นแค่ 4 ตัวท้ายและสถานะรอตรวจ" "$MYACC"

  # เลขบัญชีเต็มต้องไม่มีทางอ่านได้จากฝั่ง client ไม่ว่าทางไหน
  echo "$MYACC" | grep -q "1234567890" \
    && bad "view ต้องไม่หลุดเลขบัญชีเต็ม" "$MYACC" \
    || ok "view ไม่หลุดเลขบัญชีเต็ม"

  RAW=$(api "$SEER_TOKEN" GET "payout_account?select=account_number")
  echo "$RAW" | grep -q "1234567890" \
    && bad "อ่านตาราง payout_account ตรง ๆ ต้องไม่ได้เลขบัญชี" "$RAW" \
    || ok "อ่านตาราง payout_account ตรง ๆ ไม่ได้เลขบัญชี"

  OUT_ACC=$(api "$OUTSIDER_TOKEN" GET "v_my_payout_account?select=account_number_last4" | jq -r 'if type == "array" then length else "ไม่ใช่อาเรย์: " + tostring end')
  [[ "$OUT_ACC" == "0" ]] \
    && ok "คนอื่นอ่านบัญชีรับเงินของหมอดูไม่เห็น (อาเรย์ว่าง)" \
    || bad "คนอื่นอ่านบัญชีรับเงินของหมอดูไม่เห็น" "ได้ $OUT_ACC"

  # ผู้ใช้ทั่วไปต้องเรียกคำสั่งแอดมินไม่ได้
  ADMIN_BY_USER=$(api "$USER_TOKEN" POST "rpc/admin_review_payout_account" \
    "{\"p_payout_account_id\":\"$ACC_ID\",\"p_approve\":true,\"p_reviewer_label\":\"แอบทำ\"}")
  ADMIN_CODE=$(echo "$ADMIN_BY_USER" | jq -r '.code // "ไม่มี code"')
  [[ "$ADMIN_CODE" == "42501" ]] \
    && ok "ผู้ใช้ทั่วไปเรียกคำสั่งตรวจบัญชีไม่ได้ (42501)" \
    || bad "ผู้ใช้ทั่วไปเรียกคำสั่งตรวจบัญชีไม่ได้ ต้องได้ 42501" "ได้ '$ADMIN_CODE' · $ADMIN_BY_USER"

  if (( IS_LOCAL )); then
    # แอดมินปฏิเสธพร้อมเหตุผล
    docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select public.admin_review_payout_account('$ACC_ID'::uuid, false, 'แอดมินทดสอบ', 'ชื่อบัญชีไม่ตรงกับบัตรประชาชน')" >/dev/null 2>&1

    AFTER_REJECT=$(api "$SEER_TOKEN" GET "v_my_payout_account?select=verify_status,reject_reason")
    R_STATUS=$(echo "$AFTER_REJECT" | jq -r '.[0].verify_status // empty')
    R_REASON=$(echo "$AFTER_REJECT" | jq -r '.[0].reject_reason // empty')

    [[ "$R_STATUS" == "rejected" && -n "$R_REASON" ]] \
      && ok "ถูกปฏิเสธแล้วหมอดูเห็นเหตุผล ('$R_REASON')" \
      || bad "ถูกปฏิเสธแล้วหมอดูต้องเห็นเหตุผล" "$AFTER_REJECT"

    AUDIT=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select count(*) from public.audit_log where target_type = 'payout_account' and target_id = '$ACC_ID'" 2>/dev/null)
    [[ "$AUDIT" -ge 1 ]] 2>/dev/null \
      && ok "การตรวจของแอดมินถูกบันทึกไว้ใน audit ($AUDIT รายการ)" \
      || bad "การตรวจของแอดมินต้องถูกบันทึกใน audit" "นับได้ '$AUDIT'"

    # แอดมินอ่านเลขบัญชีเต็มได้ แต่ต้องทิ้งร่องรอยไว้ทุกครั้ง
    AUDIT_BEFORE=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select count(*) from public.audit_log where action = 'payout_account.revealed'" 2>/dev/null)
    FULL=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select public.admin_reveal_payout_account('$ACC_ID'::uuid, 'แอดมินทดสอบ') ->> 'account_number'" 2>/dev/null)
    AUDIT_AFTER=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select count(*) from public.audit_log where action = 'payout_account.revealed'" 2>/dev/null)

    [[ "$FULL" == "1234567890" ]] \
      && ok "แอดมินอ่านเลขบัญชีเต็มได้ผ่านคำสั่งเฉพาะ" \
      || bad "แอดมินอ่านเลขบัญชีเต็มได้ผ่านคำสั่งเฉพาะ" "ได้ '$FULL'"

    (( AUDIT_AFTER > AUDIT_BEFORE )) \
      && ok "ทุกครั้งที่เปิดดูเลขบัญชีถูกบันทึกไว้ (${AUDIT_BEFORE}→$AUDIT_AFTER)" \
      || bad "การเปิดดูเลขบัญชีต้องถูกบันทึกไว้" "${AUDIT_BEFORE}→$AUDIT_AFTER"
  else
    echo "  ⏭  ข้ามส่วนของแอดมิน (เรียก RPC ที่เป็นของ service_role บน remote ตรง ๆ ไม่ได้)"
  fi

  # แก้บัญชีแล้วต้องกลับไปรอตรวจใหม่ ไม่ใช่ยังผ่านอยู่ด้วยข้อมูลใหม่ที่ยังไม่มีใครดู
  api "$SEER_TOKEN" POST "rpc/set_payout_account" \
    "{\"p_bank_code\":\"scb\",\"p_account_number\":\"9876543210\",\"p_account_holder_name\":\"หมอดูทดสอบ\"}" >/dev/null
  REEDIT=$(api "$SEER_TOKEN" GET "v_my_payout_account?select=bank_code,account_number_last4,verify_status")
  [[ "$(echo "$REEDIT" | jq -r '.[0].verify_status')" == "pending" \
     && "$(echo "$REEDIT" | jq -r '.[0].account_number_last4')" == "3210" ]] \
    && ok "แก้บัญชีแล้วกลับไปรอตรวจใหม่เอง" \
    || bad "แก้บัญชีแล้วต้องกลับไปรอตรวจใหม่" "$REEDIT"

  ACTIVE_COUNT=$(api "$SEER_TOKEN" GET "v_my_payout_account?select=bank_code" | jq -r 'if type == "array" then length else "ไม่ใช่อาเรย์" end')
  [[ "$ACTIVE_COUNT" == "1" ]] \
    && ok "หมอดูมีบัญชีรับเงินที่ใช้งานอยู่ทีละหนึ่ง" \
    || bad "หมอดูต้องมีบัญชีรับเงินที่ใช้งานอยู่ทีละหนึ่ง" "ได้ $ACTIVE_COUNT"
fi

echo
echo "── 10. หมอดูขอถอนเงิน"

# ต่อจากหัวข้อ 9 บัญชีล่าสุดของหมอดูเป็น scb/3210 และสถานะ pending
PAY_ACC_ID=$(api "$SEER_TOKEN" GET "v_my_payout_account?select=id" | jq -r '.[0].id // empty')

if [[ -z "$PAY_ACC_ID" ]]; then
  bad "มีบัญชีรับเงินไว้ทดสอบการถอน" "อ่าน v_my_payout_account ไม่ได้"
else
  # --- บัญชียังไม่ผ่านการตรวจ ต้องถอนไม่ได้ ---
  NOT_VERIFIED=$(api "$SEER_TOKEN" POST "rpc/request_payout" "{\"p_coin_amount\":500}")
  echo "$NOT_VERIFIED" | grep -q "payout_account_not_verified" \
    && ok "บัญชียังไม่ผ่านการตรวจ → ขอถอนไม่ได้" \
    || bad "บัญชียังไม่ผ่านการตรวจต้องขอถอนไม่ได้" "$NOT_VERIFIED"

  if (( IS_LOCAL )); then
    docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select public.admin_review_payout_account('$PAY_ACC_ID'::uuid, true, 'แอดมินทดสอบ')" >/dev/null 2>&1

    SUMMARY=$(api "$SEER_TOKEN" GET "v_my_payout_summary?select=payable_coin,withdrawable_coin,pending_coin,min_coin,hold_days")
    W_NOW=$(echo "$SUMMARY" | jq -r '.[0].withdrawable_coin // empty')
    PAYABLE_NOW=$(echo "$SUMMARY" | jq -r '.[0].payable_coin // empty')
    MIN_COIN=$(echo "$SUMMARY" | jq -r '.[0].min_coin // empty')

    # --- รายได้ที่เพิ่งเกิดต้องยังไม่สุก ---
    if [[ "$W_NOW" == "0" && "$PAYABLE_NOW" != "0" ]]; then
      ok "รายได้ที่เพิ่งเกิดยังถอนไม่ได้ (มียอดค้างจ่าย $PAYABLE_NOW แต่ถอนได้ 0)"
    else
      bad "รายได้ที่เพิ่งเกิดต้องยังถอนไม่ได้" "payable=$PAYABLE_NOW withdrawable=$W_NOW"
    fi

    TOO_EARLY=$(api "$SEER_TOKEN" POST "rpc/request_payout" "{\"p_coin_amount\":$MIN_COIN}")
    echo "$TOO_EARLY" | grep -q "insufficient_withdrawable" \
      && ok "ขอถอนก่อนเงินสุก → ถูกปฏิเสธ" \
      || bad "ขอถอนก่อนเงินสุกต้องถูกปฏิเสธ" "$TOO_EARLY"

    # --- ทำให้รายได้สุก แล้วเติมให้ถึงขั้นต่ำ ---
    docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "update public.seer_earning set created_at = now() - interval '30 days' where seer_id = '$SEER_ACCOUNT_ID'" >/dev/null 2>&1

    SEER_PAYABLE=$(api "$SEER_TOKEN" GET "v_my_wallet?select=payable_coin" | jq -r '.[0].payable_coin')
    if (( SEER_PAYABLE < MIN_COIN )); then
      # เติมยอดให้ถึงขั้นต่ำผ่าน ledger จริง เพื่อไม่ให้ wallet กับ ledger ไม่ตรงกัน
      # เผื่อไว้ให้ขอได้สองรอบ — ถ้าเหลือพอดีรอบเดียว การทดสอบ "ขอซ้อน" จะแดงเพราะเงินหมด
      # แทนที่จะแดงเพราะตัวกันถอนซ้อน = ผ่านด้วยเหตุผลผิด
      TOPUP=$(( MIN_COIN * 3 - SEER_PAYABLE ))
      docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
        "select public.internal_post_ledger('manual_adjustment', gen_random_uuid()::text, 'adjustment',
           jsonb_build_array(
             jsonb_build_object('ledger_account','seer_payable','account_id','$SEER_ACCOUNT_ID','amount',$TOPUP),
             jsonb_build_object('ledger_account','platform_revenue','account_id',null,'amount',-$TOPUP)),
           null, 'เติมยอดให้ถึงขั้นต่ำสำหรับเทสการถอน')" >/dev/null 2>&1
      docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
        "insert into public.seer_earning (seer_id, source_type, source_id, gross_coin, seer_coin, revenue_share_bps, ledger_transaction_id, created_at)
         select '$SEER_ACCOUNT_ID', 'tip', gen_random_uuid()::text, $TOPUP, $TOPUP, 10000, t.id, now() - interval '30 days'
         from public.ledger_transaction t where t.reference_type = 'manual_adjustment' order by t.created_at desc limit 1" >/dev/null 2>&1
    fi

    # --- ต่ำกว่าขั้นต่ำ ---
    BELOW=$(api "$SEER_TOKEN" POST "rpc/request_payout" "{\"p_coin_amount\":1}")
    echo "$BELOW" | grep -q "below_minimum" \
      && ok "ต่ำกว่าขั้นต่ำ → ถูกปฏิเสธ" \
      || bad "ต่ำกว่าขั้นต่ำต้องถูกปฏิเสธ" "$BELOW"

    # --- ขอเกินยอดที่ถอนได้ ---
    W_READY=$(api "$SEER_TOKEN" GET "v_my_payout_summary?select=withdrawable_coin" | jq -r '.[0].withdrawable_coin')
    BEFORE_PAYABLE=$(api "$SEER_TOKEN" GET "v_my_wallet?select=payable_coin" | jq -r '.[0].payable_coin')
    OVER=$(api "$SEER_TOKEN" POST "rpc/request_payout" "{\"p_coin_amount\":$(( W_READY + 1 ))}")
    AFTER_OVER=$(api "$SEER_TOKEN" GET "v_my_wallet?select=payable_coin" | jq -r '.[0].payable_coin')
    if echo "$OVER" | grep -q "insufficient_withdrawable" && [[ "$AFTER_OVER" == "$BEFORE_PAYABLE" ]]; then
      ok "ขอเกินยอดที่ถอนได้ → ถูกปฏิเสธ และเหรียญไม่ขยับ"
    else
      bad "ขอเกินยอดที่ถอนได้ต้องถูกปฏิเสธและเหรียญไม่ขยับ" "$OVER · payable ${BEFORE_PAYABLE}→$AFTER_OVER"
    fi

    # --- ตัวเลขที่แสดงก่อนยืนยัน ต้องตรงกับที่บันทึกจริง ---
    # ขอแค่ขั้นต่ำ ไม่ขอทั้งหมด เพื่อให้ยังเหลือเงินพอทดสอบการขอซ้อนต่อ
    ASK=$MIN_COIN
    QUOTE=$(api "$SEER_TOKEN" POST "rpc/preview_payout" "{\"p_coin_amount\":$ASK}")
    Q_FIAT=$(echo "$QUOTE" | jq -r '.fiat_amount_minor // empty')
    Q_RATE=$(echo "$QUOTE" | jq -r '.conversion_rate_micro // empty')

    REQ=$(api "$SEER_TOKEN" POST "rpc/request_payout" "{\"p_coin_amount\":$ASK}")
    REQ_ID=$(echo "$REQ" | jq -r '.payout_request_id // empty')
    AFTER_REQ=$(api "$SEER_TOKEN" GET "v_my_wallet?select=payable_coin" | jq -r '.[0].payable_coin')

    if [[ -n "$REQ_ID" ]]; then
      ok "ขอถอนสำเร็จ ($ASK เหรียญ)"
    else
      bad "ขอถอนสำเร็จ" "$REQ"
    fi

    # ถ้าอ่านยอดไม่ได้ต้องแดง — ปล่อยให้ค่าว่างกลายเป็น 0 แล้วเทียบ จะเขียวทั้งที่ไม่ได้พิสูจน์อะไร
    if [[ -z "$ASK" || -z "$BEFORE_PAYABLE" || -z "$AFTER_REQ" ]]; then
      bad "เหรียญต้องออกจากยอดค้างจ่ายทันทีตอนขอ" "อ่านยอดไม่ได้: ขอ='$ASK' ก่อน='$BEFORE_PAYABLE' หลัง='$AFTER_REQ'"
    elif (( ASK > 0 && AFTER_REQ == BEFORE_PAYABLE - ASK )); then
      ok "เหรียญออกจากยอดค้างจ่ายทันทีตอนขอ (${BEFORE_PAYABLE}→$AFTER_REQ ลด $ASK)"
    else
      bad "เหรียญต้องออกจากยอดค้างจ่ายทันทีตอนขอ" "${BEFORE_PAYABLE}→$AFTER_REQ คาดลด $ASK"
    fi

    HIST=$(api "$SEER_TOKEN" GET "v_my_payout_history?select=coin_amount,fiat_amount_minor,conversion_rate_micro,fee_minor,withholding_tax_minor,status&order=created_at.desc&limit=1")
    H_FIAT=$(echo "$HIST" | jq -r '.[0].fiat_amount_minor // empty')
    H_RATE=$(echo "$HIST" | jq -r '.[0].conversion_rate_micro // empty')
    H_STATUS=$(echo "$HIST" | jq -r '.[0].status // empty')

    [[ "$H_FIAT" == "$Q_FIAT" && "$H_RATE" == "$Q_RATE" && -n "$Q_FIAT" ]] \
      && ok "ตัวเลขที่แสดงก่อนยืนยันตรงกับที่บันทึกจริง ($Q_FIAT สตางค์)" \
      || bad "ตัวเลขที่แสดงก่อนยืนยันต้องตรงกับที่บันทึกจริง" "preview=$Q_FIAT/$Q_RATE บันทึก=$H_FIAT/$H_RATE"

    [[ "$H_STATUS" == "requested" ]] \
      && ok "คำขออยู่สถานะรอตรวจ" \
      || bad "คำขอต้องอยู่สถานะ requested" "ได้ '$H_STATUS'"

    # --- ขอซ้อน ---
    # ต้องยังมีเงินเหลือพอขอรอบสอง ไม่งั้นข้อนี้จะผ่านเพราะเงินหมด ไม่ใช่เพราะตัวกันถอนซ้อน
    LEFT=$(api "$SEER_TOKEN" GET "v_my_payout_summary?select=withdrawable_coin" | jq -r '.[0].withdrawable_coin')
    if (( LEFT < MIN_COIN )); then
      bad "ต้องเหลือเงินพอขอรอบสอง เพื่อทดสอบตัวกันถอนซ้อนให้ตรงเหตุผล" "เหลือ $LEFT ขั้นต่ำ $MIN_COIN"
    else
      DUP=$(api "$SEER_TOKEN" POST "rpc/request_payout" "{\"p_coin_amount\":$MIN_COIN}")
      echo "$DUP" | grep -q "payout_already_pending" \
        && ok "มีคำขอค้างอยู่แล้วขออีก → ถูกปฏิเสธด้วยตัวกันถอนซ้อน (ยังเหลือ $LEFT เหรียญ)" \
        || bad "ขอซ้อนต้องถูกปฏิเสธด้วย payout_already_pending ไม่ใช่เพราะเงินหมด" "$DUP"
    fi

    OUT_HIST=$(api "$OUTSIDER_TOKEN" GET "v_my_payout_history?select=coin_amount" | jq -r 'if type == "array" then length else "ไม่ใช่อาเรย์: " + tostring end')
    [[ "$OUT_HIST" == "0" ]] \
      && ok "คนอื่นอ่านประวัติการถอนของหมอดูไม่เห็น (อาเรย์ว่าง)" \
      || bad "คนอื่นอ่านประวัติการถอนของหมอดูไม่เห็น" "ได้ $OUT_HIST"

    LEDGER2=$(docker exec -i supabase_db_project-chata psql -U postgres -d postgres -tAc \
      "select count(*) from (select transaction_id from public.ledger_entry group by transaction_id having sum(amount) <> 0) t" 2>/dev/null || echo "?")
    [[ "$LEDGER2" == "0" ]] \
      && ok "ledger สมดุลหลังขอถอน" \
      || bad "ledger สมดุลหลังขอถอน" "พบ $LEDGER2 รายการไม่สมดุล"
  else
    echo "  ⏭  ข้ามส่วนที่ต้องอนุมัติบัญชีและปรับวันที่ (ต้องใช้ psql/service_role)"
  fi
fi

echo
echo "── สรุป: ผ่าน $PASS · ไม่ผ่าน $FAIL"
[[ $FAIL -eq 0 ]]
