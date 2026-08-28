#!/usr/bin/env bash
# =============================================================================
# เสิร์ฟ Edge Function ในเครื่องพร้อม env ของ dev
#
# ทำไมต้องมีสคริปต์นี้: `supabase start` เสิร์ฟ function ให้ก็จริง แต่ **ไม่โหลด
# supabase/functions/.env.local** ผลคือ verify-iap ตอบ 403 unverified_mode_not_allowed
# ทั้งที่ config เป็น local_test อยู่แล้ว — ไล่หาสาเหตุนี้เสียเวลามาก เพราะฝั่ง DB ถูกหมด
#
# ไฟล์ env ถูก .gitignore ไว้ ถ้ายังไม่มีจะสร้างให้จาก template
# **ค่าในนั้นใช้ได้เฉพาะเครื่องพัฒนา ห้ามตั้ง ALLOW_UNVERIFIED_IAP บน cloud เด็ดขาด**
# (ดูเหตุผลสองชั้นใน supabase/functions/README.md)
#
# ใช้: ./scripts/serve-functions.sh            # ค้างไว้เป็น foreground
#      ./scripts/serve-functions.sh &          # เบื้องหลัง (test script ทำแบบนี้)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=supabase/functions/.env.local

if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'EOF'
# dev เท่านั้น — ไฟล์นี้ถูก .gitignore ไว้ ห้าม commit และห้ามใช้บน cloud
ALLOW_UNVERIFIED_IAP=true
APPLE_BUNDLE_ID=com.pacharapol.HoroTest
EOF
  echo "สร้าง $ENV_FILE ให้แล้ว (dev เท่านั้น)"
fi

exec supabase functions serve --env-file "$ENV_FILE" "$@"
