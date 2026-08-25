#!/usr/bin/env node
/**
 * dsh /api 协议验证脚本（零依赖，Node >= 22）
 *
 * 验证第三方客户端（如手机 App）接入 dsh 所需的全部链路：
 *   1. host.describe          —— 握手
 *   2. session.list           —— 会话列表
 *   3. session.create         —— 新建会话
 *   4. session.history        —— 读历史
 *   5. WebSocket /api/events.mux —— 事件下行流
 *   6. session.prompt         —— 发一句话，收流式事件直到 turn/end
 *
 * 用法: node probe.mjs [baseUrl]
 *   默认 http://127.0.0.1:3080；手机场景换成 http://100.103.29.13:3080
 */

const base = process.argv[2] ?? 'http://127.0.0.1:3080';

let rpcSeq = 0;

/** 一元调用：POST /api/<method> */
async function rpc(method, payload = {}) {
  const rpcId = `probe-${++rpcSeq}`;
  const res = await fetch(`${base}/api/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'client-request', rpcId, method, payload }),
  });
  if (!res.ok) throw new Error(`${method}: HTTP ${res.status} ${await res.text()}`);
  const msg = await res.json();
  if (msg.type !== 'server-response') throw new Error(`${method}: 意外报文 ${JSON.stringify(msg)}`);
  if (!msg.result.ok) throw new Error(`${method}: RPC 错误 ${JSON.stringify(msg.result.error)}`);
  return msg.result.value;
}

/** 打开事件下行流（只收不发） */
function openEvents(onFrame) {
  const ws = new WebSocket(`${base.replace(/^http/, 'ws')}/api/events.mux`);
  ws.addEventListener('open', () => console.log('[ws] events.mux 已连接'));
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type !== 'server-request') return;
    onFrame(msg.payload);
  });
  ws.addEventListener('error', (e) => console.error('[ws] 错误:', e.message ?? e));
  ws.addEventListener('close', () => console.log('[ws] 已断开'));
  return ws;
}

const text = (f) => `[frame] ${f.type}${f.sessionId ? ` (${f.sessionId.slice(0, 20)}…)` : ''}`;

async function main() {
  // 1. 握手
  const desc = await rpc('host.describe');
  console.log('[1] host.describe ✓', JSON.stringify(desc).slice(0, 200));

  // 2. 会话列表
  const list = await rpc('session.list');
  console.log(`[2] session.list ✓ 共 ${list.items.length} 个会话`);
  for (const s of list.items.slice(0, 5)) {
    console.log(`    - ${s.id}  ${s.title ?? '(无标题)'}  ${s.updatedAt ?? ''}`);
  }

  // 3. 新建会话
  const { sessionId } = await rpc('session.create', { cwd: process.cwd() });
  console.log(`[3] session.create ✓ sessionId = ${sessionId}`);

  // 4. 事件流（先连上，再发 prompt，免得漏事件）
  let done;
  const finished = new Promise((resolve) => (done = resolve));
  const ws = openEvents((f) => {
    if (f.type === 'session/event' && f.sessionId === sessionId) {
      const ev = f.event;
      if (ev.type === 'assistant/message') {
        const blocks = ev.data?.message?.content ?? [];
        const answer = blocks.filter((b) => b.type === 'text').map((b) => b.text).join('');
        console.log(`\n[assistant] ${answer}`);
      } else {
        console.log(`\n${text(f)} -> ${ev.type}`);
      }
      if (ev.type === 'turn/end') done();
    } else {
      console.log(text(f));
    }
  });
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));

  // 5. 读历史（新会话应为空）
  const hist = await rpc('session.history', { sessionId });
  console.log(`[5] session.history ✓ 事件数 ${hist.events.length}, hasMore=${hist.hasMore}`);

  // 6. 发 prompt，等一轮对话结束
  const question = process.argv[3] ?? '用一句中文回答：2+2 等于几？';
  console.log(`[6] session.prompt -> "${question}"`);
  const ack = await rpc('session.prompt', {
    sessionId,
    mode: 'queue',
    content: [{ type: 'text', text: question }],
  });
  console.log('    已受理:', JSON.stringify(ack));

  const timeout = setTimeout(() => {
    console.error('\n超时（120s 未收到 turn/end）');
    process.exit(1);
  }, 120_000);

  await finished;
  clearTimeout(timeout);
  console.log('\n[✓] 一轮对话完成，协议链路全部打通');
  ws.close();
  process.exit(0);
}

main().catch((err) => {
  console.error('失败:', err.message);
  process.exit(1);
});
