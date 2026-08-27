# Edge Functions

## ⛔ ยังไม่ deploy ขึ้น cloud โดยตั้งใจ — อ่านก่อน

`verify-iap` ตอนนี้ตั้ง `payment.iap_mode = 'local_test'` ซึ่งแปลว่า
**มันรับใบเสร็จโดยไม่ตรวจลายเซ็น**

ถ้า deploy ขึ้น cloud ตอนนี้ ใครก็ตามที่สมัครบัญชีได้ (ใครก็ได้บนอินเทอร์เน็ต)
จะยิง `POST /functions/v1/verify-iap` ด้วย product id ของแพ็กที่แพงที่สุด
แล้วได้เหรียญฟรีไม่จำกัด

**ใช้แบบ local ระหว่างพัฒนาไปก่อน** — deploy เมื่อสลับเป็นโหมด `production` แล้วเท่านั้น

## รันตอนพัฒนา

```bash
supabase start
supabase functions serve verify-iap
```

จะได้ endpoint ที่ `http://127.0.0.1:54321/functions/v1/verify-iap`
iOS Simulator เรียก `127.0.0.1` ได้ตรง ๆ (เครื่องจริงต้องใช้ IP ของ Mac ในวง LAN เดียวกัน)

### ทดสอบด้วย curl

```bash
ANON=<anon key จาก supabase start>
TOKEN=<access_token จากการ login>

curl -X POST 'http://127.0.0.1:54321/functions/v1/verify-iap' \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON" \
  -H 'Content-Type: application/json' \
  -d '{"productId":"app.chata.coin150","transactionId":"local-txn-0001"}'
```

ยิงซ้ำด้วย `transactionId` เดิมต้องได้ `already_credited: true` และเหรียญไม่เพิ่ม

### เติมเหรียญเร็ว ๆ โดยไม่ผ่าน IAP

รันใน Supabase Studio (SQL Editor) หรือ psql:

```sql
select dev_grant_coins('<account_id>', 1000, 'ทดสอบหน้าจอซื้อคำถาม');
```

ทำงานเฉพาะตอน `payment.iap_mode = 'local_test'` — พอสลับเป็น `production`
มันจะปิดตัวเองอัตโนมัติ (ทดสอบไว้แล้วใน `db/tests/iap-credit.test.sql`)

## รายการ function

| function | สถานะ | ติดอะไร |
|---|---|---|
| `verify-iap` | ใช้ได้ในโหมด `local_test`; เส้นทาง `sandbox`/`production` เขียนไว้แล้วแต่ **ยังไม่เคยทดสอบ** | ต้องมี Apple Developer Program ($99) + ทำ checklist ท้ายไฟล์ `verify-iap/index.ts` ให้ครบ |
| `push-sender` | ยังไม่เขียน | APNs key ต้องมี $99 |
| `outbox-dispatcher` | ยังไม่เขียน — **ตั้งใจไม่ทำตอนนี้** เพราะปลายทางเดียวของมันคือ push ซึ่งยังไม่มี | รอ push |

`outbox_event` สะสมไว้เฉย ๆ ไม่มีผลอะไร แจ้งเตือนในแอปใช้ตาราง `notification_inbox`
ที่แอปอ่านตรงผ่าน RLS อยู่แล้ว

## ตอน deploy จริง (หลังมี $99)

```bash
supabase secrets set APPLE_BUNDLE_ID=com.yourcompany.chata
supabase functions deploy verify-iap
# แล้วค่อยสลับโหมดใน Studio:
# update app_config set value = '"production"' where key = 'payment.iap_mode';
```

สลับโหมดเป็นขั้นตอน**สุดท้าย** — ทำก่อน deploy จะทำให้แอปที่ยังใช้ StoreKit local ซื้อไม่ได้
