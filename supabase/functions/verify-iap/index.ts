// =============================================================================
// verify-iap — ตรวจใบเสร็จ In-App Purchase แล้วเติมเหรียญเข้ากระเป๋า
//
// ทำไมต้องเป็น Edge Function ไม่ใช่ RPC ในฐานข้อมูล:
//   1) ต้องถือ secret และปักหมุด certificate ของ Apple
//   2) ต้องยิง HTTP ออกไปหา Apple ซึ่ง Postgres ไม่ควรทำ
//
// การตรวจลายเซ็นอยู่ใน ../_shared/apple-jws.ts
// (เคยลองใช้ @apple/app-store-server-library แล้วแต่รันบน Deno ไม่ได้ — เหตุผลอยู่ในไฟล์นั้น)
//
// โหมดอ่านจาก app_config key `payment.iap_mode`:
//   local_test  — StoreKit Testing ใน Xcode (ยังไม่มีบัญชี Apple Developer)
//                 **ต้องตั้ง env ALLOW_UNVERIFIED_IAP=true ด้วย ไม่งั้นปฏิเสธ**
//                 สองชั้นนี้ทำให้ deploy ขึ้น cloud แล้วไม่กลายเป็นแจกเหรียญฟรี
//   sandbox     — Apple sandbox: ตรวจลายเซ็นเต็มรูปแบบ
//   production  — ของจริง: ตรวจลายเซ็นเต็มรูปแบบ + ต้องมี APPLE_APP_APPLE_ID
// =============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2'
import { APPLE_ROOT_CAS } from '../_shared/apple-root-cas.ts'
import { verifyAppleJws } from '../_shared/apple-jws.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

const APPLE_BUNDLE_ID = Deno.env.get('APPLE_BUNDLE_ID') ?? ''
const APPLE_APP_APPLE_ID = Deno.env.get('APPLE_APP_APPLE_ID') ?? ''
// สวิตช์ชั้นที่สองของโหมด local_test — ต้องตั้งเองในเครื่องพัฒนาเท่านั้น
const ALLOW_UNVERIFIED = Deno.env.get('ALLOW_UNVERIFIED_IAP') === 'true'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** อ่าน payload ของ JWS โดยไม่ตรวจลายเซ็น — ใช้เฉพาะโหมด local_test เท่านั้น */
function decodeJwsPayloadUnsafe(jws: string): Record<string, unknown> {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new Error('malformed_jws')
  const pad = (s: string) => s + '='.repeat((4 - (s.length % 4)) % 4)
  return JSON.parse(atob(pad(parts[1].replace(/-/g, '+').replace(/_/g, '/'))))
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'not_authenticated' }, 401)

  const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await asCaller.auth.getUser()
  if (userErr || !userData?.user) return json({ error: 'not_authenticated' }, 401)
  const accountId = userData.user.id

  let body: { jws?: string; productId?: string; transactionId?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid_json' }, 400)
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: cfg, error: cfgErr } = await admin
    .from('app_config').select('value').eq('key', 'payment.iap_mode').single()
  if (cfgErr) return json({ error: 'config_unavailable' }, 500)
  const mode = String(cfg.value).replaceAll('"', '')

  // ---- ตรวจใบเสร็จ ----
  let claims: Record<string, unknown>
  try {
    if (mode === 'local_test') {
      // ชั้นที่สอง: ต่อให้ config เป็น local_test ถ้า env ไม่อนุญาตก็ไม่ผ่าน
      // ทำให้ deploy ขึ้น cloud โดยไม่ตั้ง env นี้ = ปลอดภัยเสมอ
      if (!ALLOW_UNVERIFIED) {
        return json({
          error: 'unverified_mode_not_allowed',
          detail: 'payment.iap_mode=local_test แต่ ALLOW_UNVERIFIED_IAP ไม่ได้ตั้งเป็น true',
        }, 403)
      }
      claims = body.jws
        ? decodeJwsPayloadUnsafe(body.jws)
        : {
            productId: body.productId,
            transactionId: body.transactionId ?? crypto.randomUUID(),
          }
    } else if (mode === 'sandbox' || mode === 'production') {
      if (!body.jws) return json({ error: 'missing_jws' }, 400)
      if (!APPLE_BUNDLE_ID) {
        throw new Error('APPLE_BUNDLE_ID ไม่ได้ตั้ง — ไม่มีทางรู้ว่าใบเสร็จมาจากแอปเราจริงไหม')
      }
      if (mode === 'production' && !APPLE_APP_APPLE_ID) {
        throw new Error('APPLE_APP_APPLE_ID ไม่ได้ตั้ง — จำเป็นสำหรับ production')
      }
      claims = await verifyAppleJws(body.jws, APPLE_ROOT_CAS, {
        expectedBundleId: APPLE_BUNDLE_ID,
        expectedEnvironment: mode === 'production' ? 'Production' : 'Sandbox',
      }) as Record<string, unknown>
    } else {
      return json({ error: 'unknown_iap_mode', detail: mode }, 500)
    }
  } catch (e) {
    // ไม่ส่งรายละเอียดภายในกลับไปให้ client มากเกินจำเป็น แต่ log ไว้ดูเอง
    const reason = e instanceof Error ? e.message : String(e)
    console.error('[verify-iap] verification failed:', reason)
    return json({ error: 'receipt_verification_failed', detail: reason.slice(0, 300) }, 400)
  }

  const productId = String(claims.productId ?? body.productId ?? '')
  const transactionId = String(claims.transactionId ?? body.transactionId ?? '')
  if (!productId || !transactionId) return json({ error: 'incomplete_receipt' }, 400)

  // เก็บ hash ไม่เก็บใบเสร็จดิบ — ตัวกัน replay อยู่ที่ unique constraint ในฐานข้อมูล
  const tokenHashHex = await sha256Hex(body.jws ?? `${accountId}:${transactionId}`)

  const { data, error } = await admin.rpc('internal_credit_iap', {
    p_account_id: accountId,
    p_provider: 'apple_iap',
    p_store_product_id: productId,
    p_provider_transaction_id: transactionId,
    p_purchase_token_hash_hex: tokenHashHex,
    p_raw_payload: { mode, claims },
  })

  if (error) {
    const isClientError = /unknown_product|receipt|product/i.test(error.message)
    return json({ error: 'credit_failed', detail: error.message }, isClientError ? 400 : 500)
  }

  return json({ ok: true, mode, ...data })
})

// =============================================================================
// ✅ Checklist ตอนย้ายไป sandbox/production
//
// 1. ซื้อ Apple Developer Program แล้วสร้าง In-App Purchase ใน App Store Connect
//    ให้ product id ตรงกับ coin_package.apple_product_id ทุกตัว
// 2. supabase secrets set APPLE_BUNDLE_ID=<bundle id จริง>
// 3. (production เท่านั้น) supabase secrets set APPLE_APP_APPLE_ID=<app id ตัวเลข>
// 4. **ห้ามตั้ง ALLOW_UNVERIFIED_IAP บน cloud เด็ดขาด**
// 5. update app_config set value='"sandbox"' where key='payment.iap_mode';
//    ทดสอบซื้อจริงใน sandbox แล้วค่อยเปลี่ยนเป็น production
// 6. ตรวจว่า dev_grant_coins ปิดตัวเองแล้ว (มันผูกกับ payment.iap_mode)
// =============================================================================
