---
tags: [chata, architecture, mobile, supabase, learning]
updated: 2026-08-27
---

# Chata Architecture — frontend/backend ของแอปมือถือ

โน้ตนี้ตอบคำถาม "structure ถูกไหม / แอปมือถือต้องมี backend-frontend เหมือน web ไหม"
เขียนไว้อ่านซ้ำเวลาลืม — hub: [[Chata]]

## โครง repo

```
horo-app/
├── HoroTest/              ← FRONTEND  (แอปที่ติดตั้งอยู่ในมือถือคน)
│   ├── ContentView.swift
│   └── *ViewModel.swift
│
├── supabase/              ← BACKEND
│   └── migrations/        ← ตาราง + RLS + RPC = ตัว backend จริง ๆ
│
├── db/                    ← DBML + regression test
└── docs/specs/            ← design spec
```

เป็น **monorepo** (frontend + backend repo เดียว) — สำหรับทีมเล็กคือแบบที่ถูกที่สุด
เพราะแก้ API กับแก้แอปจบใน PR เดียว ไม่ต้องไล่ sync สอง repo

ตอนเพิ่ม Android ค่อยขยับเป็น:

```
horo-app/
├── ios/          ← ย้าย HoroTest เข้ามา
├── android/
├── supabase/     ← ใช้ร่วมกันทั้งสอง platform
└── docs/
```

ย้ายทีหลังไม่เจ็บ (ต่างจาก bundle id ที่ย้ายทีหลังเจ็บ)

## backend อยู่ไหน ทำไมไม่มีโค้ด server

เว็บทั่วไปต้องมี: `database + API server (Node/Go) + auth + file storage + push`

**Supabase ยกมาให้ทั้งแถว** เลยไม่ต้องเขียน server เอง

backend ของเราคือ **SQL** ใน `supabase/migrations/`:

| ของ Supabase | เทียบเท่าใน backend ปกติ |
|---|---|
| `RLS policy` | middleware ตรวจสิทธิ์ |
| `RPC function (SECURITY DEFINER)` | API endpoint / service layer |
| `Edge Function` | webhook handler, งานที่ต้องใช้ secret |
| `pg_cron + pg_net` | background worker / cron job |

แอป iOS ยิงเข้า Supabase **ตรง ๆ ไม่มี server ของเราคั่นกลาง**
→ **RLS คือยามคนเดียวที่มี** เลยต้องแน่นเป็นพิเศษ

## ข้อต่างที่สำคัญที่สุด: web vs mobile

| | Web | **Mobile** |
|---|---|---|
| frontend อยู่ไหน | server เรา | **เครื่องของผู้ใช้** |
| แก้ bug หน้าบ้าน | deploy → เห็นทันที | **ส่ง App Store รอรีวิว 1-3 วัน + ผู้ใช้ต้องกดอัปเดต** |
| เวอร์ชันที่ใช้งานอยู่ | อันเดียว | **หลายเวอร์ชันพร้อมกัน** |

> ### backend ต้องรองรับแอปเวอร์ชันเก่าตลอดไป
> เพราะบังคับให้คนอัปเดตไม่ได้ — ลบ column หรือเปลี่ยนความหมาย field วันนี้
> แอปเวอร์ชันเก่าในมือคนอื่นพังทันที และแก้อะไรไม่ได้จนกว่าเขาจะอัปเดต

**นี่คือเหตุผลที่ลงทุนกับ database design หนักก่อนเขียนแอปสักบรรทัด**
บน mobile ความผิดพลาดของ backend แพงกว่า web มาก

## เส้นแบ่ง read/write (สถาปัตยกรรม Hybrid ที่เลือกใช้)

คำถามเดียว: **operation นี้แตะเงินหรือ state ที่มีผลทางบัญชีไหม**

| เส้นทาง | กลไก | ตัวอย่าง |
|---|---|---|
| อ่าน | RLS ตรงจาก client | seer catalog, chat history, notification |
| Realtime | Supabase Realtime + Presence | chat, call signaling, live viewer |
| เขียนไม่แตะเงิน | RLS + column-level GRANT | แก้โปรไฟล์, mark-as-read |
| **เขียนแตะเงิน** | **RPC `SECURITY DEFINER`** (ตาราง RLS deny-all) | ซื้อคำถาม, charge call, gift, voucher |
| external / secret | **Edge Function** | payment webhook, IAP verify, media token, AI |

## ชั้นในแอป iOS (frontend architecture)

```
View (SwiftUI)  →  ViewModel  →  Repository  →  Supabase client
                                      ↑
                                   Model (map กับตารางใน DB)
```

`HoroTest` ที่มีอยู่เดินมาทางนี้แล้ว (มี `ContentView` + `*ViewModel`)
ที่ต้องเพิ่มคือชั้น **Repository** ที่เรียก RPC/RLS แทน CRUD ในเครื่อง

## Realtime: สองโหมด และทำไมไม่ทำ socket server เอง

ตัดสินใจ 2026-08-27 หลังไปอ่านว่า DuangLive ทำ socket ยังไง

| ใช้กับ | กลไก | เหตุผล |
|---|---|---|
| ข้อความแชท | `postgres_changes` | `question_message` เป็น append-only schema ไม่ขยับ ต้นทุนเป็นศูนย์ |
| สถานะคำถาม · call signaling (อนาคต) | **broadcast จาก trigger** (`realtime.send`) | server กำหนด payload เอง มี `v` เวอร์ชัน บอกได้ว่าเปลี่ยน "จากอะไรเป็นอะไร" |

**แก่นของเรื่อง:** `postgres_changes` ส่งแถวในตารางออกไปตรง ๆ = **schema คือ wire protocol**
ซึ่งอันตรายบน mobile เพราะบังคับให้คนอัปเดตแอปไม่ได้ — เปลี่ยนความหมาย column วันนี้
แอปเวอร์ชันเก่าในมือคนอื่นพังทันที · broadcast ให้ trigger เป็นตัวแปลงระหว่าง schema กับ contract

DuangLive ใช้ Socket.IO แยกเครื่อง (`chat.duanglive.com:2053`) มี event ตั้งชื่อเป็นภาษาโดเมน
13 client-emitted + 12 server-emitted — **โมเดล event ถูก แต่ต้นทุนการเป็นเจ้าของโปรโตคอลแพง**:
ฝั่งส่ง `coinAmount` ฝั่งรับ `coin_amount`, `requestCall()` ตอนหลุด connection สั่ง `connect()`
แล้ว return เฉย ๆ ไม่ยิงคำขอซ้ำ, reconnect แล้วไม่ rejoin ห้องเอง
→ เราเอาโมเดล ไม่เอาเซิร์ฟเวอร์

**สิ่งที่เขาทำถูกและเราทำตามอยู่แล้ว:** socket ไม่ใช่แหล่งความจริงเรื่องเงิน
(เอกสาร reverse เขียนไว้ตรง ๆ ว่า *"Socket signaling is not safe as the accounting source of truth"*)
เงินวิ่ง REST/RPC เสมอ แล้วค่อย emit event ตามหลัง

**ข้อจำกัดที่ client ต้องรู้:**
- `realtime.messages` เก็บแค่ 3 วันแล้วลบ — ท่อส่ง ไม่ใช่ที่เก็บประวัติ
- private channel ที่ไม่มีสิทธิ์ บางกรณี **server เงียบไปเลย** แยกไม่ออกจากเน็ตค้าง ต้องตั้ง timeout เอง
- ต้องยัด token ใหม่เข้า channel ทุกครั้งที่ refresh ไม่งั้น socket เงียบตอน token หมดอายุ

## ความยากจริง ๆ อยู่ตรงไหน

ไม่ใช่ frontend vs backend — แต่คือ:

| เรื่อง | ยากแค่ไหน |
|---|---|
| เงินกับ ledger ห้ามผิด | **ยากสุด** — ทำเสร็จแล้ว |
| ใครเห็นข้อมูลใครได้ (RLS) | ยาก — ทำเสร็จแล้ว |
| แชท realtime | ปานกลาง |
| IAP + App Store review | น่ารำคาญกว่ายาก |
| หน้าจอ SwiftUI | **ง่ายสุด** |

ของยากที่สุดทำเสร็จไปแล้ว ที่เหลือคือแรงกับเวลา
