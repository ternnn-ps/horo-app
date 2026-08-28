#!/usr/bin/env bash
# รันเทสฝั่ง iOS ทั้งหมด — unit ทุกตัว + integration ที่ยิง Supabase local จริง
# ถ้าไม่มี local stack ชุด integration จะข้ามตัวเอง (ไม่ถือว่าล้มเหลว)
#
# ใช้: ./scripts/test-ios.sh [ชื่อ simulator]

set -uo pipefail
cd "$(dirname "$0")/.."

# ชุด integration กินเหรียญของบัญชีทดสอบทุกรอบ จึงเติมกลับด้วย fixture ก่อนเสมอ
# (เหมือน test-rest-integration.sh) — ข้ามได้ด้วย SKIP_FIXTURE=1
if [[ "${SKIP_FIXTURE:-0}" != "1" ]]; then
  ./scripts/seed-dev-fixture.sh >/dev/null 2>&1 || echo "⚠️  เตรียม fixture ไม่สำเร็จ — ชุด integration อาจล้ม"
fi

# arg แรกเป็นชื่อ simulator ได้ ที่เหลือส่งต่อให้ xcodebuild ตรง ๆ (เช่น -only-testing:...)
# ต้อง shift ออก ไม่งั้นชื่อ simulator จะถูกส่งไปเป็น build action แล้ว xcodebuild ตาย
if [[ "${1:-}" == -* ]]; then
  SIMULATOR="iPhone 17"
else
  SIMULATOR="${1:-iPhone 17}"
  [[ $# -gt 0 ]] && shift
fi
SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
ANON_KEY="${ANON_KEY:-$(supabase status -o env 2>/dev/null | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')}"

export TEST_RUNNER_SUPABASE_URL="$SUPABASE_URL"
export TEST_RUNNER_SUPABASE_PUBLISHABLE_KEY="$ANON_KEY"
export TEST_RUNNER_SUPABASE_TEST_PASSWORD="${FIXTURE_USER_PASSWORD:-HoroTest123!}"

# เทสเติมเหรียญยิง Edge Function ซึ่ง `supabase start` เสิร์ฟให้แต่ไม่โหลด .env.local
# ถ้าไม่ยกตัวเสิร์ฟที่มี env ขึ้นมา verify-iap จะตอบ 403 แล้วเทสจะเข้าทาง "ไม่อนุญาต" แทน
FN_SERVE_PID=""
cleanup() { [[ -n "$FN_SERVE_PID" ]] && kill "$FN_SERVE_PID" 2>/dev/null; return 0; }
trap cleanup EXIT

case "$SUPABASE_URL" in
  *127.0.0.1*|*localhost*)
    ./scripts/serve-functions.sh >/dev/null 2>&1 &
    FN_SERVE_PID=$!
    for _ in $(seq 1 30); do
      curl -s -m 2 -o /dev/null "$SUPABASE_URL/functions/v1/verify-iap" && break
      sleep 1
    done
    ;;
esac

xcodebuild -project HoroTest.xcodeproj \
  -scheme HoroTest \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  test "$@" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
