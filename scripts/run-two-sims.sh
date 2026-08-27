#!/usr/bin/env bash
# เปิดแอปบน simulator สองเครื่องพร้อมกัน — เครื่องหนึ่งเป็นผู้ถาม อีกเครื่องเป็นหมอดู
# ต้องมีสองฝั่งถึงจะเห็นเงินย้ายจาก escrow เข้ากระเป๋าหมอดูจริง
#
# ใช้: ./scripts/run-two-sims.sh            # ต่อ cloud (ค่าใน SupabaseConfig.plist)
#      ./scripts/run-two-sims.sh local      # ต่อ Supabase ในเครื่อง

set -uo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-cloud}"
SIM_A="${SIM_A:-iPhone 17}"
SIM_B="${SIM_B:-iPhone 17 Pro}"
BUNDLE_ID="com.pacharapol.HoroTest"
DERIVED="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/chata-run}"

echo "▶ build..."
xcodebuild -project HoroTest.xcodeproj -scheme HoroTest \
  -destination "platform=iOS Simulator,name=$SIM_A" \
  -derivedDataPath "$DERIVED" build >/dev/null 2>&1 || { echo "❌ build ไม่ผ่าน"; exit 1; }

APP="$DERIVED/Build/Products/Debug-iphonesimulator/HoroTest.app"

if [[ "$TARGET" == "local" ]]; then
  export SIMCTL_CHILD_SUPABASE_URL="http://127.0.0.1:54321"
  export SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=$(supabase status -o env 2>/dev/null | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')
  echo "▶ ชี้ไป Supabase ในเครื่อง"
else
  echo "▶ ชี้ไป cloud (ค่าใน SupabaseConfig.plist)"
fi
export SIMCTL_CHILD_SUPABASE_TEST_PASSWORD="${FIXTURE_USER_PASSWORD:-HoroTest123!}"

for SIM in "$SIM_A" "$SIM_B"; do
  xcrun simctl boot "$SIM" 2>/dev/null
  xcrun simctl install "$SIM" "$APP" >/dev/null 2>&1
  xcrun simctl launch "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 && echo "  ✅ เปิดแล้วบน $SIM"
done

open -a Simulator

cat <<'EOT'

พร้อมทดสอบแล้ว — ทำตามนี้:

  เครื่อง A  พิมพ์ "customer"  รหัสผ่านเว้นว่างไว้  แล้วกด Login
  เครื่อง B  พิมพ์ "seer"      รหัสผ่านเว้นว่างไว้  แล้วกด Login

  1. เครื่อง A: ดูยอดเหรียญ → เลือกหมอดู → ส่งคำถาม
     ยอดจะลดลง 150 (เข้า escrow ยังไม่ถึงมือหมอดู)
  2. เครื่อง B: คำถามเด้งเข้าคิวเอง → พิมพ์ตอบ
     เครื่อง A จะเห็นข้อความโผล่เองโดยไม่ต้องดึงลงรีเฟรช
  3. เครื่อง B: กด "ขอปิดงาน"
  4. เครื่อง A: กด "ยืนยันปิดงาน"  ← จุดที่เงินย้ายจริง
     เครื่อง B จะเห็นยอดค้างจ่ายเพิ่ม 105 เหรียญ (70% ของ 150)

  ลองกดส่งคำถามรัว ๆ ตอนเน็ตช้าดูได้ — ต้องไม่หักเหรียญซ้ำ

EOT
