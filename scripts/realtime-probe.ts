// เชื่อม Supabase Realtime ในนามผู้ใช้จริง แล้วรอ event ของห้องที่ระบุ
// พิมพ์ READY เมื่อพร้อมรับจริง (ไม่ใช่แค่เข้าห้องได้) แล้ว RECEIVED เมื่อได้ event
// exit 0 = ได้รับ · exit 1 = หมดเวลา / เข้าห้องไม่ได้
//
// ใช้: deno run -A scripts/realtime-probe.ts <url> <anonKey> <jwt> <questionId> <timeoutMs> [changes|broadcast]

const [url, anonKey, jwt, questionId, timeoutMsRaw, modeRaw] = Deno.args
const timeoutMs = Number(timeoutMsRaw ?? 10000)
const mode = modeRaw ?? 'changes'

const topic = mode === 'broadcast' ? `realtime:question:${questionId}` : 'realtime:probe'

const config = mode === 'broadcast'
  ? { private: true, broadcast: { self: true } }
  : {
      broadcast: { self: false },
      presence: { key: '' },
      postgres_changes: [{
        event: 'INSERT',
        schema: 'public',
        table: 'question_message',
        filter: `question_id=eq.${questionId}`,
      }],
    }

const socket = new WebSocket(`${url.replace(/^http/, 'ws')}/realtime/v1/websocket?apikey=${anonKey}&vsn=1.0.0`)

const done = (code: number, message: string) => {
  console.log(message)
  try { socket.close() } catch { /* ปิดไปแล้ว */ }
  Deno.exit(code)
}

const timer = setTimeout(() => done(1, 'TIMEOUT'), timeoutMs)

socket.onopen = () => {
  socket.send(JSON.stringify({
    topic,
    event: 'phx_join',
    ref: '1',
    payload: { config, access_token: jwt },
  }))
}

socket.onmessage = (event) => {
  const frame = JSON.parse(event.data)
  if (Deno.env.get('PROBE_DEBUG')) console.log('FRAME', event.data)

  if (frame.event === 'phx_reply' && frame.ref === '1') {
    if (frame.payload?.status !== 'ok') done(1, `JOIN_FAILED ${JSON.stringify(frame.payload)}`)
    // broadcast: เข้าห้องได้ = ผ่าน RLS ของ realtime.messages แล้ว พร้อมรับทันที
    // postgres_changes: ยังไม่พร้อม ต้องรอเฟรม system ข้างล่างก่อน
    if (mode === 'broadcast') console.log('READY')
    return
  }

  // postgres_changes: เข้าห้องได้ไม่ได้แปลว่าพร้อมรับ event
  // ถ้าเขียนข้อมูลก่อนเฟรมนี้ event จะหายเงียบโดยไม่มี error
  if (frame.event === 'system' && frame.payload?.extension === 'postgres_changes') {
    if (frame.payload?.status !== 'ok') done(1, `SUBSCRIBE_FAILED ${frame.payload?.message}`)
    console.log('READY')
    return
  }

  if (frame.event === 'postgres_changes') {
    clearTimeout(timer)
    done(0, `RECEIVED ${JSON.stringify(frame.payload?.data?.record ?? {})}`)
  }

  if (frame.event === 'broadcast') {
    clearTimeout(timer)
    done(0, `RECEIVED ${JSON.stringify(frame.payload ?? {})}`)
  }
}

socket.onerror = () => done(1, 'SOCKET_ERROR')

// private channel ที่ไม่มีสิทธิ์ บางกรณี server ตอบ Unauthorized แต่บางกรณีเงียบแล้วปิดไปเฉย ๆ
// ถ้าไม่ดัก onclose จะแยกไม่ออกเลยว่า "ถูกปฏิเสธ" หรือ "เน็ตค้าง"
socket.onclose = (e) => done(1, `SOCKET_CLOSED ${e.code} ${e.reason ?? ''}`)
