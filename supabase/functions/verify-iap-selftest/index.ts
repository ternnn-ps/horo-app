// =============================================================================
// verify-iap-selftest — พิสูจน์ว่าตัวตรวจลายเซ็นทำงานถูกจริง ไม่ใช่ปฏิเสธทุกอย่าง
//
// ทำไมต้องมี: การทดสอบว่า "ใบเสร็จปลอมถูกปฏิเสธ" อย่างเดียว **พิสูจน์อะไรไม่ได้เลย**
//   ถ้าโค้ดพังหรือ library โหลดไม่ขึ้น มันก็ปฏิเสธทุกอย่างเหมือนกัน แล้วเทสต์จะเขียว
//   (เจอกับตัวมาแล้วตอนใช้ @apple/app-store-server-library ซึ่ง throw
//    ERR_NOT_IMPLEMENTED บน Deno — ดูเหมือน "ปลอดภัย" ทั้งที่ของจริงก็ใช้ไม่ได้)
//
// จึงต้องทดสอบคู่กันเสมอ:
//   A. chain ที่ถูกต้อง + root ที่ปักหมุดตรงกัน  → **ต้องผ่าน**
//   B. chain เดียวกันนั้น + root ของ Apple จริง   → **ต้องไม่ผ่าน** (untrusted_root)
//
// ผ่านทั้งคู่ = กลไกทำงานจริง ไม่ใช่บังเอิญ
//
// ⚠️ endpoint นี้เปิดเฉพาะตอนพัฒนา — ต้องตั้ง ALLOW_UNVERIFIED_IAP=true
//    ห้ามตั้ง env นี้บน cloud (ดู supabase/functions/README.md)
// =============================================================================

import * as pkijs from 'npm:pkijs@3.0.15'
import { APPLE_ROOT_CAS } from '../_shared/apple-root-cas.ts'
import { assertAppleRootUsable, verifyAppleJws } from '../_shared/apple-jws.ts'

const ALLOW_UNVERIFIED = Deno.env.get('ALLOW_UNVERIFIED_IAP') === 'true'

function b64ToBytes(b64: string): Uint8Array {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
}

Deno.serve(async (req) => {
  if (!ALLOW_UNVERIFIED) {
    return new Response(JSON.stringify({ error: 'selftest_disabled' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const { jws, trustedRootB64, expectedBundleId } = await req.json()
  const results: Record<string, unknown> = {}

  // ---- A. root ที่ตรงกับ chain → ต้องผ่าน ----
  try {
    const claims = await verifyAppleJws(jws, [b64ToBytes(trustedRootB64)], {
      expectedBundleId,
      expectedEnvironment: 'Sandbox',
    })
    results.trustedRoot = { accepted: true, productId: claims.productId }
  } catch (e) {
    results.trustedRoot = { accepted: false, reason: (e as Error).message }
  }

  // ---- B. root ของ Apple จริง → ต้องถูกปฏิเสธที่ขั้นตอนปักหมุด ----
  try {
    await verifyAppleJws(jws, APPLE_ROOT_CAS, { expectedBundleId })
    results.appleRoot = { accepted: true }
  } catch (e) {
    results.appleRoot = { accepted: false, reason: (e as Error).message }
  }

  // ---- C. payload ถูกแก้หลังเซ็น → ลายเซ็นต้องไม่ผ่าน ----
  try {
    const [h, p, s] = String(jws).split('.')
    const pad = (x: string) => x + '='.repeat((4 - (x.length % 4)) % 4)
    const claims = JSON.parse(
      new TextDecoder().decode(b64ToBytes(pad(p.replace(/-/g, '+').replace(/_/g, '/')))),
    )
    claims.productId = 'app.chata.coin650' // แอบเปลี่ยนเป็นแพ็กแพงสุด
    const tampered = btoa(JSON.stringify(claims))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
    await verifyAppleJws(`${h}.${tampered}.${s}`, [b64ToBytes(trustedRootB64)], {
      expectedBundleId,
      expectedEnvironment: 'Sandbox',
    })
    results.tamperedPayload = { accepted: true }
  } catch (e) {
    results.tamperedPayload = { accepted: false, reason: (e as Error).message }
  }

  // ---- D. cert ของ Apple ที่ฝังไว้ ใช้งานได้จริงไหม ----
  // สำคัญ: Apple Root CA G3 เป็น **P-384** คนละเส้นโค้งกับ test chain (P-256)
  // ถ้าโค้ดรองรับแต่ P-256 จะพังเฉพาะตอนเจอใบเสร็จจริง ซึ่งสายเกินไปที่จะรู้
  const rootChecks: unknown[] = []
  for (const der of APPLE_ROOT_CAS) {
    try {
      const cert = pkijs.Certificate.fromBER(
        der.buffer.slice(der.byteOffset, der.byteOffset + der.byteLength),
      )
      const cn = cert.subject.typesAndValues
        .map((t) => String(t.value.valueBlock.value)).join(', ')
      const oid = (cert.subjectPublicKeyInfo.algorithm.algorithmParams as
        { valueBlock?: { toString(): string } } | undefined)?.valueBlock?.toString()
      await assertAppleRootUsable(cert)
      rootChecks.push({ subject: cn, curveOid: oid, selfSignatureValid: true })
    } catch (e) {
      rootChecks.push({ error: (e as Error).message })
    }
  }
  results.pinnedAppleRoots = rootChecks

  return new Response(JSON.stringify(results, null, 2), {
    headers: { 'Content-Type': 'application/json' },
  })
})
