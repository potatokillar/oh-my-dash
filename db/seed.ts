import "dotenv/config";
import { getDb } from "../api/queries/connection";
import { devices, projects, sessions, messages } from "./schema";
import { DEFAULT_MODEL } from "../contracts/models";

// 幂等种子：内置演示主机 + 示例项目/会话
async function main() {
  const db = getDb();
  const existing = await db.select().from(devices);
  if (existing.length > 0) {
    console.log("已存在设备，跳过种子");
    return;
  }

  const [{ id: demoId }] = await db
    .insert(devices)
    .values({ name: "开发工作站", address: "builtin://demo", kind: "builtin" })
    .$returningId();

  await db.insert(projects).values([
    { deviceId: demoId, path: "/home/dev/projects/dsh-client", title: "DSH 手机客户端" },
    { deviceId: demoId, path: "/home/dev/projects/notes", title: null },
    { deviceId: demoId, path: "/home/dev/projects/web-lab", title: null }, // 空项目
  ]);

  const now = Date.now();
  const mk = (title: string, cwd: string | null, minutesAgo: number) => ({
    deviceId: demoId,
    title,
    cwd,
    provider: DEFAULT_MODEL.provider,
    model: DEFAULT_MODEL.model,
    effort: DEFAULT_MODEL.effort,
    createdAt: new Date(now - minutesAgo * 60_000 - 60_000),
    updatedAt: new Date(now - minutesAgo * 60_000),
  });

  const [s1, s2, s3] = await db
    .insert(sessions)
    .values([
      mk("Flutter 事件流重连方案", "/home/dev/projects/dsh-client", 25),
      mk("审批协议打点讨论", "/home/dev/projects/dsh-client", 60 * 26),
      mk("周报素材整理", "/home/dev/projects/notes", 60 * 50),
    ])
    .$returningId();

  await db.insert(messages).values([
    {
      sessionId: s1.id, role: "user", seq: 1,
      content: "解释一下 WebSocket 断线后指数退避重连的原理",
      createdAt: new Date(now - 25 * 60_000),
    },
    {
      sessionId: s1.id, role: "assistant", seq: 2,
      reasoning: "用户问的是重连策略的原理，需要分点说明。",
      content: "指数退避的核心是**失败后等待时间按 2 的幂增长**，避免服务端故障时被客户端洪水般的重试打垮。\n\n典型序列：0.5s → 1s → 2s → 4s …… 到达上限（如 15s）后保持。\n\n加上随机抖动（jitter）可以防止大量客户端同时重连造成的「惊群」。",
      status: "done",
      createdAt: new Date(now - 24 * 60_000),
    },
    {
      sessionId: s2.id, role: "user", seq: 1,
      content: "远程审批的 rpcId 为什么要原样回显？",
      createdAt: new Date(now - 60 * 26 * 60_000 / 60),
    },
    {
      sessionId: s2.id, role: "assistant", seq: 2,
      content: "原样回显 rpcId 是为了**请求-应答配对**：主机可能同时发出多个审批请求，客户端必须告知「这次允许的是哪一个」。同时它也是重放去重的键——重连后重复的待审批帧按 rpcId 判重，不会重复弹窗。",
      status: "done",
      createdAt: new Date(now - 60 * 26 * 60_000 / 60 + 60_000),
    },
  ]);

  console.log("种子完成：demo device id =", demoId);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
