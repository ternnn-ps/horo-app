#!/usr/bin/env bash
# =============================================================================
# รันเทสชั้น SQL ทุกชุดใน db/tests/
#
# ทำไมต้องมีสคริปต์นี้ ทั้งที่รัน psql เองก็ได้:
#   ตรวจผลด้วยมือแล้ว**อ่านผิดมาแล้วสองครั้ง** — เทสที่ผ่านขึ้นแดงเพราะ pattern หลวมเกิน
#     · `grep -i FAIL` ไปโดน `"failed": 0` ในเอาต์พุต JSON ของ job
#     · `grep '^psql:'` ไปโดนบรรทัด NOTICE ที่ psql ขึ้นต้นให้เอง ("ปฏิเสธถูกต้อง: ...")
#   ตัวตัดสินที่ถูกคือ **ระดับความรุนแรงจริงของ psql** ซึ่งอยู่ในรูป `: ERROR:` / `: WARNING:`
#   ส่วน NOTICE เป็นเสียงปกติของเทสพวกนี้ — มันใช้ raise notice บอกว่า "ปฏิเสธถูกต้อง"
#
# ทุกไฟล์สร้าง user ด้วย uuid คงที่ จึงต้อง `db reset` คั่นทุกไฟล์ ไม่งั้นชนกันเอง
#
# ใช้: ./scripts/test-sql.sh [ชื่อไฟล์เฉพาะ เช่น money-flow]
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_project-chata}"

# ชุดนี้ล้างฐานทุกรอบ — ยิงใส่ remote ไม่ได้เด็ดขาด
case "$SUPABASE_URL" in
  *127.0.0.1*|*localhost*) ;;
  *)
    echo "❌ $SUPABASE_URL ไม่ใช่เครื่อง local — เทสชุดนี้ล้างฐานทุกรอบ ห้ามรันกับ remote"
    exit 1
    ;;
esac

if ! docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -c 'select 1' >/dev/null 2>&1; then
  echo "SKIP: ต่อ $DB_CONTAINER ไม่ได้ — รัน supabase start ก่อน (ไม่ถือว่าล้มเหลว)"
  exit 0
fi

FILTER="${1:-}"
PASS=0
FAIL=0

for f in db/tests/*.test.sql; do
  NAME=$(basename "$f" .test.sql)
  [[ -n "$FILTER" && "$NAME" != *"$FILTER"* ]] && continue

  supabase db reset >/dev/null 2>&1

  OUT=$(docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -f - < "$f" 2>&1)

  # เฉพาะระดับความรุนแรงจริงเท่านั้น — NOTICE คือเสียงปกติของเทสพวกนี้
  PROBLEMS=$(echo "$OUT" | grep -E ": (ERROR|WARNING|FATAL):")

  if [[ -z "$PROBLEMS" ]]; then
    PASS=$((PASS+1))
    echo "  ✅ $NAME"
  else
    FAIL=$((FAIL+1))
    echo "  ❌ $NAME"
    echo "$PROBLEMS" | head -5 | sed 's/^/     /'
  fi
done

if [[ $PASS -eq 0 && $FAIL -eq 0 ]]; then
  echo "❌ ไม่มีไฟล์เทสที่ตรงกับ '$FILTER'"
  exit 1
fi

# ฐานเพิ่งถูกล้างไปกับ reset รอบสุดท้าย — เติม fixture กลับให้ชุดอื่นใช้ต่อได้
./scripts/seed-dev-fixture.sh >/dev/null 2>&1 || echo "⚠️  เติม fixture กลับไม่สำเร็จ"

echo
echo "── สรุป SQL: ผ่าน $PASS · ไม่ผ่าน $FAIL"
[[ $FAIL -eq 0 ]]
