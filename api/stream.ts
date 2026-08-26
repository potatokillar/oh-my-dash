import type { Hono } from "hono";
import type { HttpBindings } from "@hono/node-server";
import { stream } from "hono/streaming";
import { eq, desc } from "drizzle-orm";
import { getDb } from "./queries/connection";
import { messages, sessions } from "@db/schema";
import { subscribe, getPendingApprovals } from "./agent";

type App = Hono<{ Bindings: HttpBindings }>;

// SSE：进入会话后订阅事件流（实时流式 + 多端同步）
export function registerStreamRoutes(app: App) {
  app.get("/api/stream/session/:id", async (c) => {
    const sessionId = Number(c.req.param("id"));
    if (!Number.isFinite(sessionId)) return c.json({ error: "bad id" }, 400);
    const db = getDb();
    const [session] = await db.select().from(sessions).where(eq(sessions.id, sessionId));
    if (!session) return c.json({ error: "not found" }, 404);

    c.header("Content-Type", "text/event-stream");
    c.header("Cache-Control", "no-cache");
    c.header("Connection", "keep-alive");

    return stream(c, async (s) => {
      // 快照：最近消息 + 会话状态 + 待审批（重连重放，客户端按 rpcId 去重）
      const recent = await db
        .select()
        .from(messages)
        .where(eq(messages.sessionId, sessionId))
        .orderBy(desc(messages.seq))
        .limit(30);
      await s.write(
        `data: ${JSON.stringify({
          type: "snapshot",
          session,
          messages: recent.reverse(),
          pendingApprovals: getPendingApprovals(sessionId),
        })}\n\n`,
      );

      const unsub = subscribe(sessionId, (ev) => {
        void s.write(`data: ${JSON.stringify(ev)}\n\n`).catch(() => {});
      });
      const heartbeat = setInterval(() => {
        void s.write(`: ping\n\n`).catch(() => {});
      }, 15000);

      // 保持连接直到客户端断开
      await new Promise<void>((resolve) => {
        c.req.raw.signal.addEventListener("abort", () => resolve(), { once: true });
      });
      clearInterval(heartbeat);
      unsub();
    });
  });
}
