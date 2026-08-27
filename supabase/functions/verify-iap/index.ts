// =============================================================================
// verify-iap — ตรวจใบเสร็จ In-App Purchase แล้วเติมเหรียญเข้ากระเป๋า
//
// ทำไมต้องเป็น Edge Function ไม่ใช่ RPC ในฐานข้อมูล:
//   1) ต้องถือ secret (Apple key) ซึ่งห้ามอยู่ในฐานข้อมูล
//   2) ต้องยิง HTTP ออกไปหา Apple ซึ่ง Postgres ไม่ควรทำ
//
// สามโหมด อ่านจาก app_config key `payment.iap_mode`:
//   local_test  — StoreKit Testing ใน Xcode: ตรวจโครงสร้าง ไม่ตรวจลายเซ็น
//                 **ใช้พัฒนาเท่านั้น ไม่ต้องมีบัญชี Apple Developer**
//   sandbox     — Apple sandbox (ต้องมีบัญชี $99)
//   production  — ของจริง
//
// ⚠️⚠️ ก่อนสลับเป็น sandbox/production ต้องทำ checklist ท้ายไฟล์ให้ครบ
//      เส้นทาง verify ลายเซ็นในไฟล์นี้ยังไม่เคยรันกับข้อมูลจริงจาก Apple
//      เพราะยังไม่ได้ซื้อ Developer Program — ห้ามเชื่อว่าใช้ได้จนกว่าจะทดสอบ
// =============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2'
import * as jose from 'https://deno.land/x/jose@v5.9.6/index.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

// bundle id ของแอป — ต้องตรงกับที่ตั้งใน Xcode ไม่งั้นใบเสร็จจากแอปอื่นจะใช้ได้
const EXPECTED_BUNDLE_ID = Deno.env.get('APPLE_BUNDLE_ID') ?? ''

// ลายนิ้วมือ (SHA-256) ของ Apple Root CA G3 — ใช้ปักหมุดปลายทางของ certificate chain
// ที่มา: https://www.apple.com/certificateauthority/  (AppleRootCA-G3.cer)
const APPLE_ROOT_G3_SHA256 =
  'invalid-until-verified-with-real-data'

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

/** decode payload ของ JWS โดยยังไม่ตรวจลายเซ็น (ใช้ได้ทุกโหมด) */
function decodeJwsPayload(jws: string): Record<string, unknown> {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new Error('malformed_jws')
  const pad = (s: string) => s + '='.repeat((4 - (s.length % 4)) % 4)
  const raw = atob(pad(parts[1].replace(/-/g, '+').replace(/_/g, '/')))
  return JSON.parse(raw)
}

/**
 * ตรวจลายเซ็นของ signed transaction จาก Apple
 *
 * Apple เซ็น JWS ด้วย certificate chain ใน header `x5c`
 * ขั้นตอนที่ถูกต้องคือ:
 *   1) เอา leaf cert (x5c[0]) มาดึง public key แล้วตรวจลายเซ็นของ JWS
 *   2) ไล่ตรวจว่า chain ต่อกันจริงจนถึง Apple Root CA G3
 *   3) เทียบ root กับค่าที่ปักหมุดไว้ (ห้ามเชื่อ root ที่มากับ payload เฉย ๆ)
 *
 * ⚠️ ตอนนี้ทำครบแค่ข้อ 1 — ข้อ 2/3 ยังไม่ได้ทำเพราะยังไม่มีข้อมูลจริงมาทดสอบ
 *    จึงตั้งใจให้ throw เมื่อถูกเรียกในโหมด sandbox/production
 *    ดีกว่าปล่อยให้ผ่านแบบครึ่ง ๆ กลาง ๆ แล้วเข้าใจผิดว่าปลอดภัยแล้ว
 */
async function verifyAppleSignature(jws: string): Promise<Record<string, unknown>> {
  const header = JSON.parse(
    atob(jws.split('.')[0].replace(/-/g, '+').replace(/_/g, '/')),
  ) as { x5c?: string[]; alg?: string }

  if (!header.x5c || header.x5c.length < 3) throw new Error('missing_cert_chain')

  if (APPLE_ROOT_G3_SHA256 === 'invalid-until-verified-with-real-data') {
    throw new Error(
      'apple_chain_verification_not_configured: ' +
        'ต้องใส่ลายนิ้วมือ Apple Root CA G3 และทดสอบกับใบเสร็จจริงก่อนใช้โหมดนี้',
    )
  }

  const leafDer = Uint8Array.from(atob(header.x5c[0]), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'spki',
    leafDer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  )
  const { payload } = await jose.compactVerify(jws, key)
  return JSON.parse(new TextDecoder().decode(payload))
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) return json({ error: 'not_authenticated' }, 401)

  // ---- ใครเป็นคนเรียก ----
  const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await asCaller.auth.getUser()
  if (userErr || !userData?.user) return json({ error: 'not_authenticated' }, 401)
  const accountId = userData.user.id

  // ---- input ----
  let body: { jws?: string; productId?: string; transactionId?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid_json' }, 400)
  }
  if (!body.jws && !body.productId) return json({ error: 'missing_receipt' }, 400)

  // ---- โหมดปัจจุบัน (อ่านด้วย service role เพราะ app_config ตัวนี้ไม่ public) ----
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: cfg, error: cfgErr } = await admin
    .from('app_config').select('value').eq('key', 'payment.iap_mode').single()
  if (cfgErr) return json({ error: 'config_unavailable' }, 500)
  const mode = String(cfg.value).replaceAll('"', '')

  // ---- ตรวจใบเสร็จตามโหมด ----
  let claims: Record<string, unknown>
  try {
    if (mode === 'local_test') {
      // StoreKit Testing เซ็นด้วย cert ทดสอบในเครื่อง ตรวจ chain ของ Apple ไม่ได้อยู่แล้ว
      // จึงอ่าน payload ตรง ๆ — ปลอดภัยเพราะโหมดนี้ใช้เฉพาะตอนพัฒนา
      claims = body.jws
        ? decodeJwsPayload(body.jws)
        : { productId: body.productId, transactionId: body.transactionId ?? crypto.randomUUID() }
    } else if (mode === 'sandbox' || mode === 'production') {
      if (!body.jws) return json({ error: 'missing_jws' }, 400)
      claims = await verifyAppleSignature(body.jws)

      if (EXPECTED_BUNDLE_ID && claims.bundleId !== EXPECTED_BUNDLE_ID) {
        return json({ error: 'bundle_mismatch' }, 400)
      }
      const env = String(claims.environment ?? '').toLowerCase()
      const wantSandbox = mode === 'sandbox'
      if ((env === 'sandbox') !== wantSandbox) {
        return json({ error: 'environment_mismatch', detail: { env, mode } }, 400)
      }
    } else {
      return json({ error: 'unknown_iap_mode', detail: mode }, 500)
    }
  } catch (e) {
    return json({ error: 'receipt_verification_failed', detail: String(e) }, 400)
  }

  const productId = String(claims.productId ?? body.productId ?? '')
  const transactionId = String(claims.transactionId ?? body.transactionId ?? '')
  if (!productId || !transactionId) return json({ error: 'incomplete_receipt' }, 400)

  // hash ของใบเสร็จ — เก็บ hash ไม่เก็บตัวใบเสร็จดิบ (เป็นตัวกัน replay ในฐานข้อมูล)
  const tokenHashHex = await sha256Hex(body.jws ?? `${accountId}:${transactionId}`)

  // ---- เติมเหรียญ (สร้าง order + credit ใน transaction เดียว idempotent) ----
  const { data, error } = await admin.rpc('internal_credit_iap', {
    p_account_id: accountId,
    p_provider: 'apple_iap',
    p_store_product_id: productId,
    p_provider_transaction_id: transactionId,
    p_purchase_token_hash_hex: tokenHashHex,
    p_raw_payload: { mode, claims },
  })

  if (error) {
    // unknown_product / product ไม่ตรงแพ็ก = ข้อมูลผิด ไม่ใช่ระบบพัง
    const isClientError = /unknown_product|receipt|product/i.test(error.message)
    return json({ error: 'credit_failed', detail: error.message }, isClientError ? 400 : 500)
  }

  return json({ ok: true, mode, ...data })
})

// =============================================================================
// ✅ Checklist ก่อนสลับเป็น sandbox/production (ห้ามข้าม)
//
// 1. ซื้อ Apple Developer Program แล้วสร้าง In-App Purchase ใน App Store Connect
//    ให้ product id ตรงกับ coin_package.apple_product_id ทุกตัว
// 2. ตั้ง env ของ Edge Function: APPLE_BUNDLE_ID = bundle id จริงของแอป
// 3. ดาวน์โหลด AppleRootCA-G3.cer จาก apple.com/certificateauthority
//    คำนวณ SHA-256 แล้วใส่ใน APPLE_ROOT_G3_SHA256
// 4. เติมโค้ดตรวจ certificate chain (ข้อ 2/3 ใน verifyAppleSignature) ให้ครบ
//    แล้วทดสอบกับใบเสร็จจริงจาก sandbox — ต้องผ่านทั้งเคสถูกและเคสปลอม
// 5. ทดสอบ: ใบเสร็จซ้ำต้องได้ already_credited และเหรียญไม่เพิ่ม
// 6. ทดสอบ: ใบเสร็จของแอปอื่น / product id ไม่ตรงแพ็ก ต้องถูกปฏิเสธ
// 7. ตั้ง app_config payment.iap_mode = 'production'
//    (ซึ่งจะปิด dev_grant_coins ไปโดยอัตโนมัติ)
// =============================================================================
