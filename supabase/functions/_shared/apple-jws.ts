// =============================================================================
// ตรวจลายเซ็น JWS ของ Apple (signed transaction / signed renewal info)
//
// ประวัติการลองที่ล้มเหลว — เก็บไว้กันคนหลังเดินซ้ำรอย:
//
// 1) `@apple/app-store-server-library` (library ทางการ)
//    โหลดได้ แต่พังตอน verifyCertificateChain ด้วย
//    `ERR_NOT_IMPLEMENTED: crypto.X509Certificate.prototype.toString`
//    → Supabase Edge Runtime (Deno) ไม่มี Node API ตัวนั้น
//
// 2) `pkijs.CertificateChainValidationEngine`
//    ต้องเรียก `pkijs.setEngine()` ก่อน แต่ตัวมันไปเขียน property บน global
//    ซึ่งรันไทม์นี้ห้าม → `Cannot assign to read only property of '#<Window>'`
//
// ทั้งสองอันอันตรายตรงที่ **มันปฏิเสธทุกอย่างเหมือนกันหมด** ดูเผิน ๆ เหมือนปลอดภัย
// ทั้งที่จริงคือใบเสร็จจริงของ Apple ก็ไม่ผ่าน — เจอได้เพราะทดสอบฝั่งบวกด้วย
//
// วิธีที่ใช้จริง: pkijs แกะ ASN.1 อย่างเดียว ส่วนการตรวจลายเซ็นใช้ WebCrypto ตรง ๆ
//   1. chain ต้องมี leaf + intermediate + root
//   2. **root ต้องตรงไบต์ต่อไบต์** กับ Apple Root CA ที่ปักหมุดไว้
//      (ไม่ใช่แค่ชื่อเหมือน — ใครก็ตั้ง CN=Apple Inc. ได้)
//   3. ทุกข้อต่อ: ลายเซ็นถูกต้อง + issuer ตรงกับ subject ของใบแม่ + ยังไม่หมดอายุ
//   4. ลายเซ็น JWS ตรงกับ public key ของ leaf
//   5. bundleId / environment ตรงกับที่ระบบตั้งไว้
//
// ข้อ 2 คือหัวใจ ถ้าข้ามไป ใครเซ็น cert เองก็ปลอมใบเสร็จได้ทันที
// =============================================================================

import * as pkijs from 'npm:pkijs@3.0.15'

export interface AppleJwsClaims {
  productId?: string
  transactionId?: string
  originalTransactionId?: string
  bundleId?: string
  environment?: string
  purchaseDate?: number
  [k: string]: unknown
}

// ---------------------------------------------------------------- helpers ----

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64.replace(/-/g, '+').replace(/_/g, '/'))
  return Uint8Array.from(bin, (c) => c.charCodeAt(0))
}

function b64urlDecodeJson(part: string): Record<string, unknown> {
  return JSON.parse(
    new TextDecoder().decode(b64ToBytes(part + '='.repeat((4 - (part.length % 4)) % 4))),
  )
}

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}

function toArrayBuffer(u8: Uint8Array): ArrayBuffer {
  return u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength) as ArrayBuffer
}

/** OID ของเส้นโค้ง → ชื่อที่ WebCrypto รู้จัก + ความยาว r/s ต่อค่า */
const CURVES: Record<string, { name: string; size: number }> = {
  '1.2.840.10045.3.1.7': { name: 'P-256', size: 32 },
  '1.3.132.0.34':        { name: 'P-384', size: 48 }, // Apple Root CA G3 ใช้เส้นนี้
  '1.3.132.0.35':        { name: 'P-521', size: 66 },
}

/** OID ของ signature algorithm → hash ที่ใช้ */
const SIG_HASH: Record<string, string> = {
  '1.2.840.10045.4.3.2': 'SHA-256',
  '1.2.840.10045.4.3.3': 'SHA-384',
  '1.2.840.10045.4.3.4': 'SHA-512',
}

/**
 * แปลงลายเซ็น ECDSA จากรูป DER (SEQUENCE{INTEGER r, INTEGER s})
 * เป็นรูป raw r||s ที่ WebCrypto ต้องการ
 * certificate ใช้ DER ส่วน JWS ใช้ raw — คนละรูปแบบกัน
 */
function derSigToRaw(der: Uint8Array, size: number): Uint8Array {
  let p = 0
  if (der[p++] !== 0x30) throw new Error('bad_der_signature: ไม่ใช่ SEQUENCE')
  if (der[p] & 0x80) p += 1 + (der[p] & 0x7f); else p += 1
  const readInt = (): Uint8Array => {
    if (der[p++] !== 0x02) throw new Error('bad_der_signature: ไม่ใช่ INTEGER')
    const len = der[p++]
    let v = der.subarray(p, p + len)
    p += len
    while (v.length > 0 && v[0] === 0x00) v = v.subarray(1)
    if (v.length > size) throw new Error('bad_der_signature: ค่ายาวเกินขนาดเส้นโค้ง')
    const out = new Uint8Array(size)
    out.set(v, size - v.length)
    return out
  }
  const r = readInt()
  const s = readInt()
  const raw = new Uint8Array(size * 2)
  raw.set(r, 0)
  raw.set(s, size)
  return raw
}

/** ตรวจว่า `child` ถูกเซ็นด้วย private key ของ `parent` จริง */
async function verifySignedBy(
  child: pkijs.Certificate,
  parent: pkijs.Certificate,
): Promise<void> {
  const curveOid = (parent.subjectPublicKeyInfo.algorithm.algorithmParams as
    { valueBlock?: { toString(): string } } | undefined)?.valueBlock?.toString() ?? ''
  const curve = CURVES[curveOid]
  if (!curve) throw new Error(`unsupported_curve: ${curveOid || '(อ่านไม่ได้)'}`)

  const hash = SIG_HASH[child.signatureAlgorithm.algorithmId]
  if (!hash) throw new Error(`unsupported_sig_alg: ${child.signatureAlgorithm.algorithmId}`)

  const spki = parent.subjectPublicKeyInfo.toSchema().toBER(false)
  const key = await crypto.subtle.importKey(
    'spki', spki, { name: 'ECDSA', namedCurve: curve.name }, false, ['verify'],
  )
  const sigRaw = derSigToRaw(
    new Uint8Array(child.signatureValue.valueBlock.valueHexView), curve.size,
  )
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash }, key, sigRaw, toArrayBuffer(child.tbsView),
  )
  if (!ok) {
    throw new Error(
      `chain_invalid: "${child.subject.typesAndValues[0]?.value?.valueBlock?.value ?? '?'}" ` +
      'ไม่ได้ถูกเซ็นโดยใบแม่ที่อ้าง',
    )
  }
}

function assertNotExpired(cert: pkijs.Certificate, now: Date): void {
  if (now < cert.notBefore.value || now > cert.notAfter.value) {
    throw new Error('certificate_expired: มี certificate ใน chain ที่หมดอายุหรือยังไม่เริ่มใช้')
  }
}

function assertIssuerMatches(child: pkijs.Certificate, parent: pkijs.Certificate): void {
  const a = new Uint8Array(child.issuer.toSchema().toBER(false))
  const b = new Uint8Array(parent.subject.toSchema().toBER(false))
  if (!sameBytes(a, b)) throw new Error('chain_invalid: issuer ไม่ตรงกับ subject ของใบแม่')
}

/**
 * ตรวจว่า certificate ที่ปักหมุดไว้ "ใช้งานได้" จริง — ลายเซ็นของตัวมันเอง verify ผ่าน
 * ใช้ในชุดทดสอบเพื่อยืนยันว่าโค้ดรองรับเส้นโค้งของ Apple (G3 เป็น P-384)
 * ไม่ใช่รองรับแต่ P-256 แล้วไปพังเอาตอนเจอใบเสร็จจริง
 */
export async function assertAppleRootUsable(cert: pkijs.Certificate): Promise<void> {
  await verifySignedBy(cert, cert)
}

// ------------------------------------------------------------------- main ----

export async function verifyAppleJws(
  jws: string,
  trustedRootsDer: Uint8Array[],
  opts: { expectedBundleId?: string; expectedEnvironment?: 'Sandbox' | 'Production' } = {},
): Promise<AppleJwsClaims> {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new Error('malformed_jws: ต้องมี 3 ส่วนคั่นด้วยจุด')

  const header = b64urlDecodeJson(parts[0]) as { alg?: string; x5c?: string[] }
  if (header.alg !== 'ES256') {
    throw new Error(`unsupported_alg: ${header.alg} (Apple ใช้ ES256 เท่านั้น)`)
  }
  if (!Array.isArray(header.x5c) || header.x5c.length < 3) {
    throw new Error('missing_cert_chain: x5c ต้องมี leaf + intermediate + root')
  }

  const chainDer = header.x5c.map(b64ToBytes)
  const chain = chainDer.map((der) => pkijs.Certificate.fromBER(toArrayBuffer(der)))

  // ---- root ต้องเป็นใบที่เราปักหมุดไว้เท่านั้น ----
  const rootDer = chainDer[chainDer.length - 1]
  if (!trustedRootsDer.some((r) => sameBytes(r, rootDer))) {
    throw new Error('untrusted_root: root ใน x5c ไม่ตรงกับ Apple Root CA ที่ปักหมุดไว้')
  }

  // ---- ไล่ตรวจทุกข้อต่อ leaf ← intermediate ← ... ← root ----
  const now = new Date()
  for (let i = 0; i < chain.length; i++) {
    assertNotExpired(chain[i], now)
    if (i + 1 < chain.length) {
      assertIssuerMatches(chain[i], chain[i + 1])
      await verifySignedBy(chain[i], chain[i + 1])
    }
  }
  // root ต้องเซ็นตัวเอง (ยืนยันว่าไม่ได้เอาใบอื่นมาสวม)
  await verifySignedBy(chain[chain.length - 1], chain[chain.length - 1])

  // ---- ลายเซ็นของ JWS ต้องมาจาก leaf ----
  const leafCurveOid = (chain[0].subjectPublicKeyInfo.algorithm.algorithmParams as
    { valueBlock?: { toString(): string } } | undefined)?.valueBlock?.toString() ?? ''
  const leafCurve = CURVES[leafCurveOid]
  if (!leafCurve) throw new Error(`unsupported_curve: ${leafCurveOid || '(อ่านไม่ได้)'}`)

  const leafKey = await crypto.subtle.importKey(
    'spki', chain[0].subjectPublicKeyInfo.toSchema().toBER(false),
    { name: 'ECDSA', namedCurve: leafCurve.name }, false, ['verify'],
  )
  const sigOk = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    leafKey,
    toArrayBuffer(b64ToBytes(parts[2] + '='.repeat((4 - (parts[2].length % 4)) % 4))),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  )
  if (!sigOk) throw new Error('bad_signature: ลายเซ็นไม่ตรงกับ public key ของ leaf certificate')

  const claims = b64urlDecodeJson(parts[1]) as AppleJwsClaims

  if (opts.expectedBundleId && claims.bundleId !== opts.expectedBundleId) {
    throw new Error(
      `bundle_mismatch: ใบเสร็จเป็นของ ${claims.bundleId} ไม่ใช่ ${opts.expectedBundleId}`,
    )
  }
  if (opts.expectedEnvironment && claims.environment !== opts.expectedEnvironment) {
    throw new Error(
      `environment_mismatch: ใบเสร็จมาจาก ${claims.environment} ` +
      `แต่ระบบตั้งเป็น ${opts.expectedEnvironment}`,
    )
  }

  return claims
}
