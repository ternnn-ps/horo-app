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

OUT=$(mktemp)
# ปิด parallel testing: ค่าเริ่มต้นของ xcodebuild จะโคลน simulator ขึ้นมาหลายตัวพร้อมกัน
# (เห็นเป็น "Clone 1 of iPhone 17") ซึ่งกินแรมและ CPU หนักมากบนเครื่องที่ swap ตึงอยู่แล้ว
# ชุดนี้เป็น integration test ที่ยิงฐานเดียวกัน รันขนานไม่ได้ช่วยอะไรอยู่แล้ว
# เปิดกลับด้วย PARALLEL_TESTS=1 ถ้าวันหนึ่งเครื่องไหว
PARALLEL_FLAGS=(-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1)
[[ "${PARALLEL_TESTS:-0}" == "1" ]] && PARALLEL_FLAGS=()

xcodebuild -project HoroTest.xcodeproj \
  -scheme HoroTest \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  "${PARALLEL_FLAGS[@]}" \
  test "$@" 2>&1 | tee "$OUT" | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"

# เทสที่ข้ามตัวเองไม่แดง แต่ก็ไม่ได้พิสูจน์อะไร — ถ้าไม่โชว์จะเข้าใจผิดว่าครอบครบแล้ว
# (เจอมาแล้ว: ตัวที่ต้องมีเงินสุกในกระเป๋าข้ามตัวเองทุกรอบที่สอง แต่ขึ้น TEST SUCCEEDED)
# `grep -c` คืน 0 พร้อม exit 1 เมื่อไม่เจอ — `|| echo 0` จะได้เลข 0 สองตัวติดกัน
SKIPPED=$(grep -E "was skipped|skipped on" "$OUT" | wc -l | tr -d " ")
if [[ "$SKIPPED" != "0" ]]; then
  echo
  echo "⚠️  มีเทสข้ามตัวเอง $SKIPPED ตัว — ไม่แดง แต่ไม่ได้พิสูจน์อะไร:"
  grep -oE "'"'"'[A-Za-z]+\.[A-Za-z]+\(\)'"'"' skipped" "$OUT" | sed "s/^/     /"
  [[ "${ALLOW_SKIPPED:-0}" == "1" ]] || { rm -f "$OUT"; exit 1; }
fi
rm -f "$OUT"
