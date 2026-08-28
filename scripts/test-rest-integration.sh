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
  AVAILABLE=$(echo "$WALLET" | jq -r '.[0].available_coin // empty')

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

  if [[ "$(echo "$REPLAY" | jq -r '.replayed // empty')" != "true" ]]; then
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
  SEEN=$(api "$OUTSIDER_TOKEN" GET "question?id=eq.$QUESTION_ID&select=id" | jq -r 'length')
  [[ "$SEEN" == "0" ]] && ok "คนนอกอ่าน question ไม่เห็น" || bad "คนนอกอ่าน question ไม่เห็น" "เห็น $SEEN แถว"

  SEEN_MSG=$(api "$OUTSIDER_TOKEN" GET "question_message?question_id=eq.$QUESTION_ID&select=id" | jq -r 'length')
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
echo "── สรุป: ผ่าน $PASS · ไม่ผ่าน $FAIL"
[[ $FAIL -eq 0 ]]
