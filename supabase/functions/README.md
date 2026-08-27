# Edge Functions

## รายการ

| function | สถานะ |
|---|---|
| `verify-iap` | ตรวจใบเสร็จ IAP แล้วเติมเหรียญ — **ตรวจลายเซ็นจริงแล้ว ทดสอบผ่านแล้ว** |
| `verify-iap-selftest` | ชุดพิสูจน์ว่าตัวตรวจลายเซ็นทำงานถูก (เปิดเฉพาะตอนพัฒนา) |
| `push-sender` | ยังไม่เขียน — APNs key ต้องมี Apple Developer Program |
| `outbox-dispatcher` | **ตั้งใจยังไม่ทำ** — ปลายทางเดียวของมันคือ push ซึ่งยังไม่มี |

`outbox_event` สะสมไว้เฉย ๆ ไม่มีผลเสีย แจ้งเตือนในแอปใช้ตาราง `notification_inbox`
ที่แอปอ่านตรงผ่าน RLS อยู่แล้ว

## `verify-iap` — สามโหมด

อ่านจาก `app_config` key `payment.iap_mode`

| โหมด | ตรวจอะไร | ต้องมี |
|---|---|---|
| `local_test` | **ไม่ตรวจลายเซ็น** — ใช้กับ StoreKit Testing ใน Xcode | env `ALLOW_UNVERIFIED_IAP=true` |
| `sandbox` | ตรวจเต็มรูปแบบ, environment ต้องเป็น Sandbox | `APPLE_BUNDLE_ID` |
| `production` | ตรวจเต็มรูปแบบ, environment ต้องเป็น Production | `APPLE_BUNDLE_ID`, `APPLE_APP_APPLE_ID` |

### กันเหรียญฟรีสองชั้น

โหมด `local_test` ต้องผ่าน **ทั้ง** config และ env — ถ้า deploy ขึ้น cloud
โดยไม่ตั้ง `ALLOW_UNVERIFIED_IAP` มันจะตอบ `unverified_mode_not_allowed` (403)
ทดสอบไว้แล้ว: ยิงขอแพ็ก 730 เหรียญโดยไม่มี env → ปฏิเสธ เหรียญไม่เพิ่ม

**ห้ามตั้ง `ALLOW_UNVERIFIED_IAP` บน cloud เด็ดขาด**

### การตรวจลายเซ็นทำอะไรบ้าง

อยู่ใน `_shared/apple-jws.ts` — เขียนเองด้วย pkijs (แกะ ASN.1) + WebCrypto (ตรวจลายเซ็น)
เพราะทั้ง `@apple/app-store-server-library` และ `pkijs.CertificateChainValidationEngine`
รันบน Supabase Edge Runtime ไม่ได้ (เหตุผลละเอียดอยู่หัวไฟล์นั้น)

1. `x5c` ต้องมี leaf + intermediate + root
2. **root ต้องตรงไบต์ต่อไบต์กับ Apple Root CA G3 ที่ฝังไว้** ← หัวใจ
3. ทุกข้อต่อ: ลายเซ็นถูก + issuer ตรง subject ของใบแม่ + ยังไม่หมดอายุ
4. ลายเซ็น JWS ตรงกับ public key ของ leaf
5. `bundleId` / `environment` ตรงกับที่ระบบตั้ง

## ทดสอบ

```bash
supabase start
supabase functions serve --no-verify-jwt --env-file supabase/functions/.env.local &
./scripts/test-iap-verifier.sh
```

ยืนยัน 4 ข้อ — **ข้อ A สำคัญที่สุด**:

| | |
|---|---|
| A | chain ถูกต้อง + root ตรง → **ยอมรับ** |
| B | chain เดียวกัน + root ของ Apple → ปฏิเสธ (`untrusted_root`) |
| C | payload ถูกแก้หลังเซ็น → ปฏิเสธ (`bad_signature`) |
| D | Apple Root CA G3 ที่ฝังไว้ verify ตัวเองผ่าน (ยืนยันว่ารองรับ P-384) |

> ถ้าทดสอบแต่ข้อ B/C จะไม่มีทางรู้ว่าโค้ดพัง — **โค้ดที่พังก็ปฏิเสธทุกอย่างเหมือนกัน**
> เจอมาแล้วสองรอบ ทั้ง library ของ Apple เองและ pkijs engine

### เติมเหรียญเร็ว ๆ ตอนทำ UI

```sql
select dev_grant_coins('<account_id>', 1000, 'ทดสอบหน้าซื้อคำถาม');
```

ทำงานเฉพาะตอน `payment.iap_mode = 'local_test'` — สลับเป็น production แล้วปิดตัวเอง

## ตอนขึ้นจริง (หลังมี Apple Developer Program)

```bash
supabase secrets set APPLE_BUNDLE_ID=com.yourcompany.chata
supabase secrets set APPLE_APP_APPLE_ID=<app id ตัวเลขจาก App Store Connect>
supabase functions deploy verify-iap
# ห้าม deploy verify-iap-selftest ขึ้น production
```

แล้วค่อยสลับโหมด (ทำเป็นขั้นตอน**สุดท้าย** — สลับก่อน deploy จะทำให้แอปที่ยังใช้
StoreKit local ซื้อไม่ได้):

```sql
update app_config set value = '"sandbox"' where key = 'payment.iap_mode';
-- ทดสอบซื้อจริงใน sandbox ให้ผ่านก่อน แล้วค่อย:
update app_config set value = '"production"' where key = 'payment.iap_mode';
```

### ยังเหลือให้ทำก่อน production

- ยังไม่ได้ตรวจกับใบเสร็จจริงจาก Apple sandbox (ต้องมีบัญชีก่อน) —
  กลไกทดสอบครบแล้วแต่ **ข้อมูลจริงยังไม่เคยผ่านเส้นทางนี้**
- ยังไม่ได้ตรวจ OCSP/CRL ว่า certificate ถูกเพิกถอนหรือยัง
  (Apple หมุน intermediate ไม่บ่อย ความเสี่ยงต่ำ แต่ควรเพิ่มเมื่อมีเวลา)
- `originalTransactionId` ยังไม่ได้ใช้ — จำเป็นตอนทำ subscription ไม่ใช่ consumable
