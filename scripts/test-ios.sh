#!/usr/bin/env bash
# รันเทสฝั่ง iOS ทั้งหมด — unit ทุกตัว + integration ที่ยิง Supabase local จริง
# ถ้าไม่มี local stack ชุด integration จะข้ามตัวเอง (ไม่ถือว่าล้มเหลว)
#
# ใช้: ./scripts/test-ios.sh [ชื่อ simulator]

set -uo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${1:-iPhone 17}"
SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
ANON_KEY="${ANON_KEY:-$(supabase status -o env 2>/dev/null | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')}"

export TEST_RUNNER_SUPABASE_URL="$SUPABASE_URL"
export TEST_RUNNER_SUPABASE_PUBLISHABLE_KEY="$ANON_KEY"
export TEST_RUNNER_SUPABASE_TEST_PASSWORD="${FIXTURE_USER_PASSWORD:-HoroTest123!}"

xcodebuild -project HoroTest.xcodeproj \
  -scheme HoroTest \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  test "$@" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
