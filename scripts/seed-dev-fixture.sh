#!/usr/bin/env bash
# สร้างสถานะตั้งต้นสำหรับ dev/test ด้วยคำสั่งเดียว — ผู้ใช้ทดสอบ + หมอดูที่อนุมัติแล้ว + เหรียญตั้งต้น
#
# ทำไมต้องเป็น script ไม่ใช่ migration: auth.users seed ผ่าน migration ไม่ได้
# ต้องสร้างผ่าน Auth admin API เท่านั้น
#
# ใช้: ./scripts/seed-dev-fixture.sh
# ชี้ไป cloud: SUPABASE_URL=... SERVICE_ROLE_KEY=... FIXTURE_ALLOW_REMOTE=1 ./scripts/seed-dev-fixture.sh

set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-fixture.env

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
ANON_KEY="${ANON_KEY:-}"
SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY:-}"

if [[ -z "$ANON_KEY" || -z "$SERVICE_ROLE_KEY" ]]; then
  STATUS=$(supabase status -o env 2>/dev/null)
  [[ -z "$ANON_KEY" ]] && ANON_KEY=$(sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' <<<"$STATUS")
  [[ -z "$SERVICE_ROLE_KEY" ]] && SERVICE_ROLE_KEY=$(sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p' <<<"$STATUS")
fi

if [[ -z "$ANON_KEY" || -z "$SERVICE_ROLE_KEY" ]]; then
  echo "❌ หา ANON_KEY / SERVICE_ROLE_KEY ไม่เจอ — รัน supabase start หรือส่งมาทาง env"
  exit 1
fi

# กันยิงใส่ production โดยไม่ตั้งใจ
if [[ "$SUPABASE_URL" != *"127.0.0.1"* && "$SUPABASE_URL" != *"localhost"* && "${FIXTURE_ALLOW_REMOTE:-0}" != "1" ]]; then
  echo "❌ $SUPABASE_URL ไม่ใช่เครื่อง local — ถ้าตั้งใจจริงต้องตั้ง FIXTURE_ALLOW_REMOTE=1"
  exit 1
fi

MODE=$(curl -s "$SUPABASE_URL/rest/v1/app_config?key=eq.payment.iap_mode&select=value" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" | jq -r '.[0].value // empty')
if [[ "$MODE" != "local_test" ]]; then
  echo "❌ payment.iap_mode = ${MODE:-?} — fixture ใช้ได้เฉพาะโหมด local_test"
  exit 1
fi

admin() {
  local method=$1 path=$2 body=${3:-}
  if [[ -n "$body" ]]; then
    curl -s -X "$method" "$SUPABASE_URL$path" \
      -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -s -X "$method" "$SUPABASE_URL$path" \
      -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY"
  fi
}

login() {
  curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.access_token // empty'
}

# สร้างบัญชีถ้ายังไม่มี แล้วคืน account id เสมอ (รันซ้ำได้)
ensure_account() {
  local email=$1 password=$2
  local created
  created=$(admin POST /auth/v1/admin/users \
    "{\"email\":\"$email\",\"password\":\"$password\",\"email_confirm\":true}")

  local id
  id=$(jq -r '.id // empty' <<<"$created")
  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi

  admin GET "/auth/v1/admin/users?filter=$email" | jq -r --arg e "$email" '.users[] | select(.email == $e) | .id'
}

echo "▶ fixture → $SUPABASE_URL"

USER_ID=$(ensure_account "$FIXTURE_USER_EMAIL" "$FIXTURE_USER_PASSWORD")
[[ -z "$USER_ID" ]] && { echo "❌ สร้างบัญชีผู้ใช้ไม่สำเร็จ"; exit 1; }
echo "  ผู้ใช้ทดสอบ  $FIXTURE_USER_EMAIL  ($USER_ID)"

WALLET=$(admin GET "/rest/v1/wallet?account_id=eq.$USER_ID&select=available_coin")
AVAILABLE=$(jq -r '.[0].available_coin // 0' <<<"$WALLET")

if (( AVAILABLE < FIXTURE_USER_START_COIN )); then
  TOPUP=$(( FIXTURE_USER_START_COIN - AVAILABLE ))
  GRANT=$(admin POST /rest/v1/rpc/dev_grant_coins \
    "{\"p_account_id\":\"$USER_ID\",\"p_coin\":$TOPUP,\"p_note\":\"fixture top-up\"}")
  if [[ "$(jq -r 'type' <<<"$GRANT")" != "object" ]] || [[ "$(jq -r '.message // empty' <<<"$GRANT")" != "" ]]; then
    echo "❌ เติมเหรียญไม่สำเร็จ: $GRANT"
    exit 1
  fi
  echo "  เติมเหรียญ    +$TOPUP"
fi

FINAL=$(admin GET "/rest/v1/wallet?account_id=eq.$USER_ID&select=available_coin" | jq -r '.[0].available_coin')
echo "  เหรียญคงเหลือ $FINAL"

SEER_ID=$(ensure_account "$FIXTURE_SEER_EMAIL" "$FIXTURE_SEER_PASSWORD")
[[ -z "$SEER_ID" ]] && { echo "❌ สร้างบัญชีหมอดูไม่สำเร็จ"; exit 1; }
echo "  หมอดูทดสอบ   $FIXTURE_SEER_EMAIL  ($SEER_ID)"

SEER_TOKEN=$(login "$FIXTURE_SEER_EMAIL" "$FIXTURE_SEER_PASSWORD")
[[ -z "$SEER_TOKEN" ]] && { echo "❌ login หมอดูไม่สำเร็จ"; exit 1; }

seer_api() {
  local method=$1 path=$2 body=${3:-} prefer=${4:-}
  local args=(-s -X "$method" "$SUPABASE_URL/rest/v1/$path"
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $SEER_TOKEN" -H "Content-Type: application/json")
  [[ -n "$prefer" ]] && args+=(-H "Prefer: $prefer")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

ROLE=$(admin GET "/rest/v1/account?id=eq.$SEER_ID&select=role" | jq -r '.[0].role // empty')

if [[ "$ROLE" != "seer" ]]; then
  SKILL_ID=$(admin GET "/rest/v1/skill?select=id&order=sort_order&limit=1" | jq -r '.[0].id')
  [[ -z "$SKILL_ID" || "$SKILL_ID" == "null" ]] && { echo "❌ ไม่มี skill ในฐานข้อมูล (seed_dev หายไป?)"; exit 1; }

  DRAFT=$(seer_api POST "rpc/save_seer_application" \
    "{\"p_display_name\":\"$FIXTURE_SEER_DISPLAY_NAME\",\"p_bio\":\"หมอดูสำหรับทดสอบระบบ Chata ใช้กับ fixture ของนักพัฒนาเท่านั้น ไม่ใช่หมอดูจริง\",\"p_main_skill_id\":$SKILL_ID,\"p_skill_ids\":[$SKILL_ID],\"p_price_coin\":$FIXTURE_SEER_PRICE_COIN}")
  if [[ -n "$(jq -r '.message // empty' <<<"$DRAFT")" ]]; then
    echo "❌ save_seer_application: $DRAFT"; exit 1
  fi

  for DOC in national_id portrait; do
    EXISTS=$(seer_api GET "seer_document?account_id=eq.$SEER_ID&document_type=eq.$DOC&select=id" | jq -r '.[0].id // empty')
    if [[ -z "$EXISTS" ]]; then
      DOC_RES=$(seer_api POST "seer_document" \
        "{\"account_id\":\"$SEER_ID\",\"document_type\":\"$DOC\",\"object_key\":\"$SEER_ID/$DOC.jpg\"}")
      if [[ -n "$(jq -r '.message // empty' <<<"$DOC_RES")" ]]; then
        echo "❌ แนบเอกสาร $DOC: $DOC_RES"; exit 1
      fi
    fi
  done

  SUBMITTED=$(seer_api POST "rpc/submit_seer_application" "{}")
  if [[ -n "$(jq -r '.message // empty' <<<"$SUBMITTED")" ]]; then
    echo "❌ submit_seer_application: $SUBMITTED"; exit 1
  fi

  APP_ID=$(jq -r '.application_id // empty' <<<"$SUBMITTED")
  [[ -z "$APP_ID" ]] && { echo "❌ submit_seer_application ไม่คืน application_id: $SUBMITTED"; exit 1; }

  REVIEW=$(admin POST /rest/v1/rpc/admin_review_seer_application \
    "{\"p_application_id\":\"$APP_ID\",\"p_approve\":true,\"p_reviewer_label\":\"fixture\"}")
  if [[ -n "$(jq -r '.message // empty' <<<"$REVIEW")" ]]; then
    echo "❌ admin_review_seer_application: $REVIEW"; exit 1
  fi
  echo "  อนุมัติหมอดู  ใบสมัคร $APP_ID"
fi

seer_api PATCH "seer_profile?account_id=eq.$SEER_ID" \
  '{"is_active":true,"accepts_question":true}' >/dev/null
seer_api PATCH "seer_service?seer_id=eq.$SEER_ID" \
  "{\"is_enabled\":true,\"price_coin\":$FIXTURE_SEER_PRICE_COIN}" >/dev/null

SERVICE=$(admin GET "/rest/v1/seer_service?seer_id=eq.$SEER_ID&select=id,price_coin,is_enabled")
SERVICE_ID=$(jq -r '.[0].id // empty' <<<"$SERVICE")
[[ -z "$SERVICE_ID" ]] && { echo "❌ หมอดูยังไม่มี service"; exit 1; }
echo "  service       $SERVICE_ID ราคา $(jq -r '.[0].price_coin' <<<"$SERVICE") เหรียญ"

OUTSIDER_ID=$(ensure_account "$FIXTURE_OUTSIDER_EMAIL" "$FIXTURE_OUTSIDER_PASSWORD")
echo "  บัญชีคนนอก    $FIXTURE_OUTSIDER_EMAIL  ($OUTSIDER_ID)"

# ล้างตัวนับ rate limit ของบัญชีทดสอบ ไม่งั้นรันชุดเทสซ้ำเกิน 10 ครั้ง/ชม. จะติดเพดานเอง
# ทำได้เฉพาะ local (ตาราง rate_limit_counter deny-all ไม่มี grant ให้ใครนอกจาก postgres)
if [[ "$SUPABASE_URL" == *"127.0.0.1"* || "$SUPABASE_URL" == *"localhost"* ]]; then
  docker exec -i supabase_db_project-chata psql -U postgres -d postgres -q -c \
    "delete from public.rate_limit_counter where account_id in ('$USER_ID','$SEER_ID','$OUTSIDER_ID');" >/dev/null 2>&1
fi

# ---------------------------------------------------------- บัญชีรับเงิน ----
# ชุดเทสที่ต้องใช้บัญชี "ตรวจแล้ว" จะเข้าขาสำรองถาวรถ้า fixture ไม่กำหนดสถานะตั้งต้นให้
# (เทสตัวก่อนหน้าบันทึกบัญชีใหม่ ซึ่งรีเซ็ตกลับเป็น "รอตรวจ" ตามพฤติกรรมที่ถูกต้องของระบบ)
PAYOUT_STATUS=$(seer_api GET "v_my_payout_account?select=verify_status" | jq -r '.[0].verify_status // empty')
if [[ "$PAYOUT_STATUS" != "verified" ]]; then
  seer_api POST "rpc/set_payout_account" \
    "{\"p_bank_code\":\"kbank\",\"p_account_number\":\"1234567890\",\"p_account_holder_name\":\"$FIXTURE_SEER_DISPLAY_NAME\"}" >/dev/null
  PAYOUT_ID=$(seer_api GET "v_my_payout_account?select=id" | jq -r '.[0].id // empty')
  if [[ -n "$PAYOUT_ID" ]]; then
    admin POST "/rest/v1/rpc/admin_review_payout_account" \
      "{\"p_payout_account_id\":\"$PAYOUT_ID\",\"p_approve\":true,\"p_reviewer_label\":\"fixture\"}" >/dev/null
  fi
fi
echo "  บัญชีรับเงิน  $(seer_api GET "v_my_payout_account?select=bank_code,account_number_last4,verify_status" | jq -r '.[0] | "\(.bank_code) ····\(.account_number_last4) (\(.verify_status))"')"

# --------------------------------------- เคลียร์คำขอถอนที่ค้างจากรอบก่อน ----
# คำขอถอนค้างได้ทีละรายการ ถ้าไม่เคลียร์ ชุดเทสรอบถัดไปจะขอถอนไม่ได้เลย
# ปฏิเสธผ่าน RPC จริงเพื่อให้เหรียญถูกคืนด้วยรายการกลับรายการตามกติกา ไม่ใช่ลบแถวทิ้ง
OPEN_REQS=$(admin GET "/rest/v1/payout_request?seer_id=eq.$SEER_ID&status=in.(requested,approved)&select=id" | jq -r '.[]?.id // empty')
for RID in $OPEN_REQS; do
  admin POST "/rest/v1/rpc/admin_review_payout" \
    "{\"p_payout_request_id\":\"$RID\",\"p_action\":\"reject\",\"p_reviewer_label\":\"fixture\",\"p_reason\":\"คืนสถานะตั้งต้นให้ชุดเทส\"}" >/dev/null
done

# ----------------------------------------------- รายได้ที่พ้นระยะรอแล้ว ----
# ชุดเทสเรื่องการถอนต้องมีเงินที่ "สุก" แล้ว (พ้นระยะรอ) เป็นจำนวนที่แน่นอน
# ถ้าไม่กำหนดตรงนี้ มันจะไปพึ่งผลข้างเคียงของชุดที่รันก่อนหน้า ซึ่งเปราะมาก
FIXTURE_MATURED_COIN="${FIXTURE_MATURED_COIN:-2000}"
# ต้องได้ตัวเลขเสมอ — ถ้าอ่านไม่ได้แล้วปล่อยเป็นค่าว่าง สคริปต์จะเติมซ้ำทุกรอบ (ไม่ idempotent)
MATURED_NOW=$(admin GET "/rest/v1/seer_earning?seer_id=eq.$SEER_ID&source_type=eq.tip&select=seer_coin" \
  | jq 'if type == "array" then ([.[].seer_coin] | add // 0) else -1 end')
if [[ "$MATURED_NOW" == "-1" ]]; then
  echo "❌ อ่านรายได้ของหมอดูไม่ได้ — ตรวจสิทธิ์ service_role บน seer_earning"
  exit 1
fi
if (( MATURED_NOW < FIXTURE_MATURED_COIN )); then
  GAP=$(( FIXTURE_MATURED_COIN - MATURED_NOW ))
  FIX_REF="fixture-matured-$(uuidgen | tr 'A-Z' 'a-z')"
  TX=$(admin POST "/rest/v1/rpc/internal_post_ledger" \
    "{\"p_reference_type\":\"manual_adjustment\",\"p_reference_id\":\"$FIX_REF\",\"p_operation\":\"adjustment\",
      \"p_entries\":[{\"ledger_account\":\"seer_payable\",\"account_id\":\"$SEER_ID\",\"amount\":$GAP},
                     {\"ledger_account\":\"platform_revenue\",\"account_id\":null,\"amount\":-$GAP}],
      \"p_note\":\"fixture: รายได้ตั้งต้นที่พ้นระยะรอแล้ว\"}" | tr -d '"')
  if [[ -n "$TX" && "$TX" != "null" ]]; then
    admin POST "/rest/v1/seer_earning" \
      "{\"seer_id\":\"$SEER_ID\",\"source_type\":\"tip\",\"source_id\":\"$FIX_REF\",\"gross_coin\":$GAP,
        \"seer_coin\":$GAP,\"revenue_share_bps\":10000,\"ledger_transaction_id\":\"$TX\",
        \"created_at\":\"$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)\"}" >/dev/null
  fi
fi
echo "  เงินที่ถอนได้  $(seer_api GET "v_my_payout_summary?select=withdrawable_coin,payable_coin" | jq -r '.[0] | "ถอนได้ \(.withdrawable_coin) จากยอดค้างจ่าย \(.payable_coin)"')"

echo
echo "พร้อมใช้งาน — login ด้วย:"
echo "  ผู้ใช้  $FIXTURE_USER_EMAIL / $FIXTURE_USER_PASSWORD"
echo "  หมอดู  $FIXTURE_SEER_EMAIL / $FIXTURE_SEER_PASSWORD"
echo "  คนนอก  $FIXTURE_OUTSIDER_EMAIL / $FIXTURE_OUTSIDER_PASSWORD"
