import { Hono } from "hono";
import type { DshContext } from "../index.js";

interface SessionsLike {
  list?(): Promise<unknown[]>;
  create?(opts: { cwd?: string; title?: string }): Promise<{ id: string }>;
  followup?(id: string, msg: unknown): Promise<void>;
  stop?(id: string): Promise<void>;
}

/**
 * 会话路由:列表/创建/发消息/停止 → ctx.sessions
 * 消息流与审批通过 SSE 端点下发。
 */
export function sessionsRoutes(ctx: DshContext) {
  const app = new Hono();
  const sessions = () => ctx.get("sessions") as SessionsLike | undefined;

  app.get("/", async (c) => {
    const s = sessions();
    if (!s?.list) return c.json({ error: "sessions service unavailable" }, 503);
    return c.json({ sessions: await s.list() });
  });

  app.post("/", async (c) => {
    const s = sessions();
    if (!s?.create) return c.json({ error: "sessions service unavailable" }, 503);
    const body = await c.req.json().catch(() => ({}));
    const created = await s.create({ cwd: body.cwd, title: body.title });
    return c.json(created, 201);
  });

  app.post("/:id/messages", async (c) => {
    const s = sessions();
    if (!s?.followup) return c.json({ error: "sessions service unavailable" }, 503);
    const body = await c.req.json();
    await s.followup(c.req.param("id"), { role: "user", text: body.text, images: body.images });
    return c.json({ ok: true });
  });

  app.post("/:id/stop", async (c) => {
    const s = sessions();
    if (!s?.stop) return c.json({ error: "sessions service unavailable" }, 503);
    await s.stop(c.req.param("id"));
    return c.json({ ok: true });
  });

  // SSE:转发 session/event(assistant/chunk 的 text-delta)与 tools/pre-execute 审批请求
  app.get("/:id/stream", (c) => {
    const id = c.req.param("id");
    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      start(controller) {
        const send = (event: string, data: unknown) => {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
        };
        const off1 = ctx.on("session/event", (e: { sessionId?: string; type?: string; delta?: string }) => {
          if (e.sessionId === id) send("message", e);
        });
        const off2 = ctx.on("tools/pre-execute", (e: { sessionId?: string; rpcId?: string; tool?: string }) => {
          if (e.sessionId === id) send("approval", e);
        });
        // 心跳,防止代理断连
        const hb = setInterval(() => controller.enqueue(encoder.encode(": hb\n\n")), 15000);
        return () => {
          off1();
          off2();
          clearInterval(hb);
        };
      },
    });
    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  });

  return app;
}
