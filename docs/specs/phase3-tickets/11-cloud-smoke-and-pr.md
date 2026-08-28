# 11: Smoke test บน cloud + เปิด PR

**What to build:** สลับ config ไปที่ Supabase cloud `chata-dev` แล้วเดินครบลูปจริงจากแอป:
สมัคร → เห็นหมอดู → ซื้อคำถาม → แชท → ปิดงาน → เงินเข้ากระเป๋าหมอดู · แล้วเปิด PR เข้า `main`

**Blocked by:** 07 (Close and settle), 09 (Remove legacy domain)

**Status:** done (2026-08-29) — PR #3

- [x] `git fetch origin && git pull` ก่อน แล้วทำงานบน branch `feat/ios-supabase` — ไม่มี commit ไหนเข้า `main` ตรง ๆ
- [x] migration sync ครบ **22/22** (`supabase migration list` — local ตรงกับ remote ทุกใบ)
- [x] เดินครบลูปบน cloud สำเร็จ พร้อมหลักฐานยอดเหรียญก่อน/หลัง
- [x] ยืนยันว่า **ไม่มี** `ALLOW_UNVERIFIED_IAP` บน cloud (`supabase secrets list` ว่างเปล่า) และปุ่มไม่โผล่
- [x] เทส SQL 6 ชุดผ่านหมด ไม่มี WARNING/ERROR (รัน `db reset` คั่นทุกไฟล์ เพราะใช้ uuid คงที่)
- [x] PR description ภาษาอังกฤษ อธิบายเหตุผลที่รื้อ `HoroDomainModels.swift` ให้ชัด


## ผลรัน (2026-08-29) — PR #3

https://github.com/ternnn-ps/horo-app/pull/3 · 36 ไฟล์ · +2,829 / −1,189

| ชั้น | local | cloud (`chata-dev`) |
|---|---|---|
| SQL `db/tests/*.test.sql` | 6/6 | — |
| REST `scripts/test-rest-integration.sh` | 31/31 | 25/25 |
| iOS `HoroTestTests/` | 18/18 | 18/18 |

ข้อที่ข้ามบน cloud 4 ข้อ มีเหตุผลจริงทุกข้อ: ตรวจ ledger ต้องต่อ psql ตรง · เติมเหรียญจริง
กับสลับโหมด IAP ต้องแก้ `app_config` ซึ่ง client ทำไม่ได้ (ถูกต้องแล้ว)

**หลักฐานเงินบน cloud**

```
ซื้อคำถาม     available 1000→850 · reserved 450→600
ยิงซ้ำ key เดิม  คงที่ 850 (replayed=true)
ปิดงาน        seer payable 210→315 (+105 = 70% ของ 150) · reserved 750→600
สุดท้าย       customer available=850 reserved=900 · seer payable=315
```

**เรื่องที่เพิ่งรู้ตอนทำ: `verify-iap` ไม่เคยถูก deploy ขึ้น cloud เลย** (404 NOT_FOUND)
แปลว่าเกณฑ์ "ยืนยันว่าไม่มี ALLOW_UNVERIFIED_IAP" พิสูจน์ไม่ได้เพราะไม่มีตัวฟังก์ชันให้ถาม
→ deploy แล้ว (เฉพาะ `verify-iap` ไม่เอา `verify-iap-selftest`) แล้วยืนยันสองชั้น:

```
GET  /functions/v1/verify-iap → {"mode":"local_test","dev_topup_allowed":false}
POST /functions/v1/verify-iap → 403 unverified_mode_not_allowed · ยอด 700→700 ไม่ขยับ
supabase secrets list         → ว่างเปล่า
```

⚠️ cloud ยังตั้ง `payment.iap_mode = local_test` — ก่อนเปิดใช้จริงต้องสลับเป็น `production`
