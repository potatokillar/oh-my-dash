import { EventEmitter } from "events";
import { eq, desc, sql } from "drizzle-orm";
import { getDb } from "./queries/connection";
import { messages, sessions } from "@db/schema";

// ---------- 事件中心（驱动 SSE，多端同步） ----------

export interface StreamEvent {
  type:
    | "user_message"
    | "message_start"
    | "reasoning_delta"
    | "content_delta"
    | "message_final"
    | "session_updated"
    | "approval_request"
    | "approval_resolved";
  [key: string]: unknown;
}

const hub = new EventEmitter();
hub.setMaxListeners(200);

export function sessionChannel(sessionId: number) {
  return `session:${sessionId}`;
}

export function emit(sessionId: number, ev: StreamEvent) {
  hub.emit(sessionChannel(sessionId), ev);
}

export function subscribe(sessionId: number, fn: (ev: StreamEvent) => void) {
  const ch = sessionChannel(sessionId);
  hub.on(ch, fn);
  return () => hub.off(ch, fn);
}

// ---------- 运行时状态 ----------

const stopFlags = new Map<number, boolean>();

interface PendingApproval {
  rpcId: string;
  sessionId: number;
  tool: string;
  description: string;
  resolve: (allow: boolean) => void;
}

const pendingApprovals = new Map<string, PendingApproval>();

export function getPendingApprovals(sessionId: number) {
  return [...pendingApprovals.values()]
    .filter((a) => a.sessionId === sessionId)
    .map(({ rpcId, tool, description }) => ({ rpcId, tool, description }));
}

// 应答协议：原样回显请求 rpcId
export function respondApproval(rpcId: string, allow: boolean): boolean {
  const pending = pendingApprovals.get(rpcId);
  if (!pending) return false;
  pendingApprovals.delete(rpcId);
  pending.resolve(allow);
  emit(pending.sessionId, { type: "approval_resolved", rpcId, allow });
  return true;
}

export function requestStop(sessionId: number): boolean {
  if (!stopFlags.has(sessionId)) return false;
  stopFlags.set(sessionId, true);
  return true;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---------- 回复生成（内置演示主机的模拟智能体） ----------

function buildReasoning(text: string): string {
  return `用户的问题：「${text.slice(0, 40)}${text.length > 40 ? "…" : ""}」\n\n1. 先判断意图——这更像一个需要展开解释/产出的请求，而不是简单问答。\n2. 拆解关键点，确定回复结构：先给结论，再给步骤或示例。\n3. 检查是否有遗漏的约束条件，组织语言，开始输出。`;
}

function buildReply(text: string): string {
  const t = text.toLowerCase();
  if (/写代码|代码|code|实现|函数/.test(t)) {
    return `好的，这是一个可直接运行的示例实现：

\`\`\`typescript
// 指数退避重连：断线后自动恢复事件流
export async function connectWithBackoff(
  connect: () => Promise<void>,
  maxRetries = 8,
) {
  let attempt = 0;
  while (attempt < maxRetries) {
    try {
      await connect();
      return; // 连接成功
    } catch {
      const delay = Math.min(2 ** attempt * 500, 15000);
      await new Promise((r) => setTimeout(r, delay));
      attempt++;
    }
  }
  throw new Error("重连次数已用尽");
}
\`\`\`

**要点：**

- 每次失败等待 \`2^n × 500ms\`，上限 15 秒，避免雪崩
- 连接成功后重置计数，长期运行更稳定

需要我把它改造成带心跳检测的版本吗？`;
  }
  if (/解释|概念|是什么|原理|为什么/.test(t)) {
    return `这个概念可以拆成三层来理解：

**一句话版本**：它解决的是「状态在多处保持一致」的问题。

**展开来说：**

1. **单一数据源**——所有客户端读写的都是服务端这一份数据，本地只是它的投影
2. **事件驱动**——变化以事件（新增 / 增量 / 完成）的形式推送到各端，而不是各端轮询猜测
3. **幂等回放**——断线重连后按序号补齐缺失事件，重复事件直接丢弃，保证最终一致

**一个类比**：像多人协作文档——你看到的永远是服务器那份文档的实时镜像，网络抖动只是让镜像晚到几秒，而不会产生两个版本。

想继续深入哪一层，我可以再展开。`;
  }
  if (/头脑风暴| brainstorm|想法|点子|创意/.test(t)) {
    return `围绕这个方向，给你 5 个可以立刻往下推进的点子：

1. **会话模板库**——把高质量的提示词前缀沉淀成模板，跨会话复用，一键注入
2. **语音输入 + 流式转写**——移动端打字成本高，按住说话直接转成 composer 文本
3. **审批策略**——按工具类型记住选择（如「读文件永久允许」），减少打断
4. **会话摘要卡**——长会话自动生成 TL;DR 置顶，多端打开都能快速进入上下文
5. **离线队列**——弱网时消息先入本地队列，恢复后自动补发并标注发送时间

如果只能选一个先做，我建议第 3 个：它直接降低远程审批的打断成本，实现也最简单。想细化哪个？`;
  }
  if (/总结|概括|summary|摘要/.test(t)) {
    return `这段内容的核心结论如下：

**TL;DR**：整体思路是用一套统一协议把「设备—项目—会话—消息」串起来，手机端只做展示与交互。

**三个要点：**

- **聚合自动化**：项目不需要手工维护，按工作目录自动归组，空目录靠注册补齐
- **状态实时化**：消息、运行状态、审批请求都走同一条事件流，多端天然同步
- **降级明确**：主机离线、模型不可用、连接中断都有独立的提示与恢复路径

如果需要，我可以把它压缩成一段可以放进 README 的介绍文案。`;
  }
  return `收到。关于「${text.slice(0, 50)}${text.length > 50 ? "…" : ""}」，我的看法是：

这件事可以分成两步走——先明确目标和约束，再选择实现路径。从当前上下文看，最关键的是先把核心链路跑通，再逐步完善细节。

**建议的推进顺序：**

1. 先做一个最小可用版本，验证主流程
2. 跑通后补充异常处理（断线、超时、并发）
3. 最后打磨体验细节（动效、空状态、提示文案）

你可以继续给我更具体的指令，比如「写代码」「解释一下原理」「头脑风暴」，我会按对应方式展开。`;
}

// 命中这些关键词时，智能体会请求工具权限（远程审批演示）
const TOOL_TRIGGER = /运行|执行|跑一下|删除|安装|部署|restart|run|exec/i;

// ---------- Turn 执行 ----------

let rpcCounter = 0;

async function nextSeq(sessionId: number): Promise<number> {
  const db = getDb();
  const [row] = await db
    .select({ max: sql<number | null>`max(seq)` })
    .from(messages)
    .where(eq(messages.sessionId, sessionId));
  return (row?.max ?? 0) + 1;
}

export async function startTurn(sessionId: number): Promise<void> {
  const db = getDb();
  const [session] = await db.select().from(sessions).where(eq(sessions.id, sessionId));
  if (!session) return;

  stopFlags.set(sessionId, false);
  await db.update(sessions).set({ running: true }).where(eq(sessions.id, sessionId));
  emit(sessionId, { type: "session_updated" });

  const seq = await nextSeq(sessionId);
  const [{ id: msgId }] = await db
    .insert(messages)
    .values({ sessionId, role: "assistant", content: "", status: "streaming", seq })
    .$returningId();
  emit(sessionId, { type: "message_start", messageId: msgId, seq });

  const recent = await db
    .select()
    .from(messages)
    .where(eq(messages.sessionId, sessionId))
    .orderBy(desc(messages.seq))
    .limit(4);
  const userMsg = recent.find((m) => m.role === "user");
  const userText = userMsg?.content || "你好";

  const isStopped = () => stopFlags.get(sessionId) === true;
  const finalize = async (status: "done" | "interrupted") => {
    await db.update(messages).set({ status }).where(eq(messages.id, msgId));
    await db
      .update(sessions)
      .set({ running: false, updatedAt: new Date() })
      .where(eq(sessions.id, sessionId));
    stopFlags.delete(sessionId);
    emit(sessionId, { type: "message_final", messageId: msgId, status });
    emit(sessionId, { type: "session_updated" });
  };

  try {
    // 1. 思考过程（推理强度非 Off 的模型先输出 reasoning）
    if (session.effort !== "off") {
      const reasoning = buildReasoning(userText);
      let acc = "";
      for (const ch of reasoning.match(/[\s\S]{1,6}/g) ?? []) {
        if (isStopped()) return await finalize("interrupted");
        acc += ch;
        await db.update(messages).set({ reasoning: acc }).where(eq(messages.id, msgId));
        emit(sessionId, { type: "reasoning_delta", messageId: msgId, delta: ch });
        await sleep(28);
      }
      await sleep(400);
    }

    // 2. 远程审批：请求工具权限，等待手机端应答
    if (TOOL_TRIGGER.test(userText)) {
      const rpcId = `rpc-${Date.now()}-${++rpcCounter}`;
      const description = `智能体请求在主机上执行 shell 命令，以完成「${userText.slice(0, 24)}」相关操作`;
      emit(sessionId, {
        type: "approval_request",
        rpcId,
        tool: "shell.exec",
        description,
      });
      const allow = await new Promise<boolean>((resolve) => {
        pendingApprovals.set(rpcId, {
          rpcId,
          sessionId,
          tool: "shell.exec",
          description,
          resolve,
        });
        setTimeout(() => {
          if (pendingApprovals.delete(rpcId)) resolve(false);
        }, 120_000);
      });
      if (!allow) {
        const note = "好的，已取消该操作。权限被拒绝后我不会执行任何命令——如果你改变主意，随时再发一次指令。";
        let acc = "";
        for (const ch of note.match(/[\s\S]{1,8}/g) ?? []) {
          if (isStopped()) return await finalize("interrupted");
          acc += ch;
          await db.update(messages).set({ content: acc }).where(eq(messages.id, msgId));
          emit(sessionId, { type: "content_delta", messageId: msgId, delta: ch });
          await sleep(24);
        }
        return await finalize("done");
      }
      await sleep(600); // 模拟命令执行
    }

    // 3. 正文流式输出
    const reply = buildReply(userText);
    let acc = "";
    for (const ch of reply.match(/[\s\S]{1,4}/g) ?? []) {
      if (isStopped()) return await finalize("interrupted");
      acc += ch;
      await db.update(messages).set({ content: acc }).where(eq(messages.id, msgId));
      emit(sessionId, { type: "content_delta", messageId: msgId, delta: ch });
      await sleep(18);
    }
    await finalize("done");
  } catch (err) {
    console.error("turn failed", err);
    await finalize("interrupted");
  }
}
