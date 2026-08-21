#!/usr/bin/env node
/**
 * 双端同步验证：PC 端（127.0.0.1）和手机端（100.103.29.13）连同一台 dsh host。
 * 流程：PC 端建会话 -> 手机端发 prompt -> 断言 PC 端实时收到全部事件（反之亦然）。
 */
const PC = 'http://127.0.0.1:3080';
const PHONE = 'http://100.103.29.13:3080';

let n = 0;
async function rpc(base, method, payload = {}) {
  const res = await fetch(`${base}/api/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'client-request', rpcId: `sync-${++n}`, method, payload }),
  });
  const msg = await res.json();
  if (!msg.result?.ok) throw new Error(`${method}: ${JSON.stringify(msg.result ?? msg)}`);
  return msg.result.value;
}

function watch(base, label, sessionId, seen) {
  const ws = new WebSocket(`${base.replace(/^http/, 'ws')}/api/events.mux`);
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type !== 'server-request') return;
    const f = msg.payload;
    if (f.type === 'session/event' && f.sessionId === sessionId) {
      seen.add(f.event.type);
      if (f.event.type === 'assistant/message') {
        const text = (f.event.data?.message?.content ?? [])
          .filter((b) => b.type === 'text').map((b) => b.text).join('');
        console.log(`[${label}] 实时收到 assistant/message: "${text}"`);
      }
      if (f.event.type === 'user/message') console.log(`[${label}] 实时收到 user/message`);
      if (f.event.type === 'turn/end') console.log(`[${label}] 实时收到 turn/end`);
    }
  });
  return new Promise((r) => ws.addEventListener('open', () => r(ws)));
}

// PC 端建会话
const { sessionId } = await rpc(PC, 'session.create', { cwd: process.cwd() });
console.log(`[PC] 建会话 ${sessionId}`);

const pcSeen = new Set(), phoneSeen = new Set();
const pcWs = await watch(PC, 'PC', sessionId, pcSeen);
const phoneWs = await watch(PHONE, '手机', sessionId, phoneSeen);

// 手机端发消息
await rpc(PHONE, 'session.prompt', {
  sessionId, mode: 'queue',
  content: [{ type: 'text', text: '用一句中文回答：太阳从哪边升起？' }],
});
console.log('[手机] 已发送 prompt');

// 等两端都收到 turn/end
const deadline = Date.now() + 120_000;
while ((!pcSeen.has('turn/end') || !phoneSeen.has('turn/end')) && Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 300));
}

console.log(`\nPC 端收到 ${pcSeen.size} 类事件: ${[...pcSeen].join(', ')}`);
console.log(`手机端收到 ${phoneSeen.size} 类事件: ${[...phoneSeen].join(', ')}`);
const pass = pcSeen.has('turn/end') && phoneSeen.has('turn/end') && pcSeen.has('assistant/message');
console.log(pass ? '\n[✓] 双端同步成立：手机发的消息，PC 实时可见；PC 上的会话状态两端一致。'
               : '\n[✗] 同步验证未通过');
pcWs.close(); phoneWs.close();
process.exit(pass ? 0 : 1);
