#!/usr/bin/env bash
# =============================================================================
# ทดสอบตัวตรวจลายเซ็นใบเสร็จ IAP — รันได้โดยไม่ต้องมีบัญชี Apple Developer
#
# ทำไมต้องทดสอบ "ฝั่งบวก" ด้วย ไม่ใช่แค่ดูว่าใบปลอมถูกปฏิเสธ:
#   ถ้าโค้ดพัง/library โหลดไม่ขึ้น มันจะปฏิเสธทุกอย่างเหมือนกัน แล้วเทสต์จะเขียว
#   ทั้งที่จริงใบเสร็จจริงของ Apple ก็ใช้ไม่ได้ (เจอมาแล้ว 2 รอบ — ดู apple-jws.ts)
#
# สคริปต์นี้สร้าง CA ครบ 3 ชั้นของตัวเอง แล้วยืนยัน 4 ข้อ:
#   A. chain ถูกต้อง + root ตรงกับที่ปักหมุด        → ต้องผ่าน
#   B. chain เดียวกัน + root ของ Apple จริง         → ต้องถูกปฏิเสธ (untrusted_root)
#   C. payload ถูกแก้หลังเซ็น                       → ต้องถูกปฏิเสธ (bad_signature)
#   D. Apple Root CA G3 ที่ฝังไว้ verify ตัวเองผ่าน  → ยืนยันว่ารองรับ P-384 จริง
#
# วิธีรัน:
#   supabase start
#   supabase functions serve --no-verify-jwt --env-file supabase/functions/.env.local &
#   ./scripts/test-iap-verifier.sh
# =============================================================================
set -euo pipefail

ENDPOINT="${ENDPOINT:-http://127.0.0.1:54321/functions/v1/verify-iap-selftest}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > ca.cnf <<'EOF'
[req]
distinguished_name=dn
[dn]
[ca_ext]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
[leaf_ext]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
EOF

# ---- สร้าง CA 3 ชั้น (ต้องใช้ -sha256; ค่า default ของ LibreSSL คือ SHA-1 ซึ่งเราปฏิเสธถูกแล้ว)
for n in root int leaf; do openssl ecparam -genkey -name prime256v1 -noout -out $n.key 2>/dev/null; done
openssl req -new -x509 -sha256 -key root.key -out root.pem -days 3650 \
  -subj "/CN=Test Root CA" -config ca.cnf -extensions ca_ext 2>/dev/null
openssl req -new -key int.key -out int.csr -subj "/CN=Test Intermediate CA" -config ca.cnf 2>/dev/null
openssl x509 -req -sha256 -in int.csr -CA root.pem -CAkey root.key -set_serial 2 -days 3650 \
  -out int.pem -extfile ca.cnf -extensions ca_ext 2>/dev/null
openssl req -new -key leaf.key -out leaf.csr -subj "/CN=Test Leaf" -config ca.cnf 2>/dev/null
openssl x509 -req -sha256 -in leaf.csr -CA int.pem -CAkey int.key -set_serial 3 -days 3650 \
  -out leaf.pem -extfile ca.cnf -extensions leaf_ext 2>/dev/null
for n in root int leaf; do openssl x509 -in $n.pem -outform DER -out $n.der; done
openssl verify -CAfile root.pem -untrusted int.pem leaf.pem >/dev/null

# ---- ประกอบ JWS เซ็นด้วย leaf ----
python3 - <<'PY'
import base64, json, subprocess, pathlib
b64u = lambda b: base64.urlsafe_b64encode(b).decode().rstrip('=')
certs = [pathlib.Path(f'{n}.der').read_bytes() for n in ('leaf','int','root')]
header  = {"alg":"ES256","x5c":[base64.b64encode(c).decode() for c in certs]}
payload = {"productId":"app.chata.coin150","transactionId":"chain-txn-0001",
           "bundleId":"app.chata.dev","environment":"Sandbox","quantity":1}
si = b64u(json.dumps(header,separators=(',',':')).encode()) + '.' + \
     b64u(json.dumps(payload,separators=(',',':')).encode())
pathlib.Path('si.txt').write_text(si)
subprocess.run('printf %s "$(cat si.txt)" | openssl dgst -sha256 -sign leaf.key -out sig.der',
               shell=True, check=True)
d = pathlib.Path('sig.der').read_bytes(); i = 2 if d[1] < 0x80 else 3
def rd(b,p):
    assert b[p]==0x02
    ln=b[p+1]; v=b[p+2:p+2+ln].lstrip(b'\x00'); return v.rjust(32,b'\x00'), p+2+ln
r,p = rd(d,i); s,_ = rd(d,p)
pathlib.Path('body.json').write_text(json.dumps({
  "jws": si + '.' + b64u(r+s),
  "trustedRootB64": base64.b64encode(certs[2]).decode(),
  "expectedBundleId": "app.chata.dev"}))
PY

RESULT="$(curl -sS -X POST "$ENDPOINT" -H 'Content-Type: application/json' -d @body.json)"
echo "$RESULT" | python3 -m json.tool

python3 - <<PY
import json, sys
r = json.loads('''$RESULT''')
fails = []
def want(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label + ('  ' + str(detail) if detail else ''))
    if not cond: fails.append(label)

print()
want('A. chain ถูกต้อง + root ตรง → ยอมรับ',
     r.get('trustedRoot',{}).get('accepted') is True, r.get('trustedRoot'))
want('B. root ของ Apple → ปฏิเสธด้วย untrusted_root',
     'untrusted_root' in str(r.get('appleRoot',{}).get('reason','')))
want('C. payload ถูกแก้ → ปฏิเสธด้วย bad_signature',
     'bad_signature' in str(r.get('tamperedPayload',{}).get('reason','')))
roots = r.get('pinnedAppleRoots') or []
want('D. Apple Root CA G3 ที่ฝังไว้ verify ตัวเองผ่าน (P-384)',
     len(roots) >= 1 and all(x.get('selfSignatureValid') for x in roots), roots)
print()
if fails:
    print('ไม่ผ่าน:', ', '.join(fails)); sys.exit(1)
print('ผ่านทั้งหมด — ตัวตรวจลายเซ็นทำงานจริง ไม่ใช่ปฏิเสธทุกอย่าง')
PY
