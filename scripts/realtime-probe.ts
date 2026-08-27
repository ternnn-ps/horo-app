// เชื่อม Supabase Realtime ในนามผู้ใช้จริง แล้วรอ INSERT ของ question_message ในห้องที่ระบุ
// คืน exit 0 พร้อมพิมพ์ RECEIVED เมื่อได้รับ, exit 1 เมื่อหมดเวลา
//
// ใช้: deno run -A scripts/realtime-probe.ts <url> <anonKey> <jwt> <questionId> <timeoutMs>

const [url, anonKey, jwt, questionId, timeoutMsRaw] = Deno.args
const timeoutMs = Number(timeoutMsRaw ?? 10000)

const wsUrl = `${url.replace(/^http/, 'ws')}/realtime/v1/websocket?apikey=${anonKey}&vsn=1.0.0`
const socket = new WebSocket(wsUrl)

const done = (code: number, message: string) => {
  console.log(message)
  try { socket.close() } catch { /* ปิดไปแล้ว */ }
  Deno.exit(code)
}

const timer = setTimeout(() => done(1, 'TIMEOUT'), timeoutMs)

socket.onopen = () => {
  socket.send(JSON.stringify({
    topic: 'realtime:probe',
    event: 'phx_join',
    ref: '1',
    payload: {
      config: {
        broadcast: { self: false },
        presence: { key: '' },
        postgres_changes: [{
          event: 'INSERT',
          schema: 'public',
          table: 'question_message',
          filter: `question_id=eq.${questionId}`,
        }],
      },
      access_token: jwt,
    },
  }))
}

socket.onmessage = (event) => {
  const frame = JSON.parse(event.data)
  if (Deno.env.get('PROBE_DEBUG')) console.log('FRAME', event.data)

  if (frame.event === 'phx_reply' && frame.ref === '1') {
    if (frame.payload?.status !== 'ok') done(1, `JOIN_FAILED ${JSON.stringify(frame.payload)}`)
    return
  }

  // เข้าห้องสำเร็จยังไม่พอ — ต้องรอจนกว่า replication จะ subscribe จริง
  // ถ้าแทรกข้อความก่อนเฟรมนี้ event จะหายไปเลยและดูเหมือน Realtime พัง
  if (frame.event === 'system' && frame.payload?.extension === 'postgres_changes') {
    if (frame.payload?.status !== 'ok') done(1, `SUBSCRIBE_FAILED ${frame.payload?.message}`)
    console.log('READY')
    return
  }

  if (frame.event === 'postgres_changes') {
    clearTimeout(timer)
    done(0, `RECEIVED ${JSON.stringify(frame.payload?.data?.record ?? {})}`)
  }
}

socket.onerror = () => done(1, 'SOCKET_ERROR')
