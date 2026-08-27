import { Hono } from "hono";
import { serve } from "./http-adapter.js";
import { sessionsRoutes } from "./routes/sessions.js";
import { browseRoutes } from "./routes/browse.js";
import { hostRoutes } from "./routes/host.js";
import type { DshContext } from "./index.js";

/**
 * 插件的 HTTP 服务:对外暴露与 oh-my-dash 前端 contracts 一致的 API,
 * 数据源全部改为 DSH 的 Cordis 服务(ctx.sessions / ctx.fs / 事件流)。
 */
export function createApp(ctx: DshContext) {
  const app = new Hono();

  app.route("/api/host", hostRoutes(ctx));
  app.route("/api/sessions", sessionsRoutes(ctx));
  app.route("/api/browse", browseRoutes(ctx));

  app.get("/healthz", (c) => c.json({ ok: true, plugin: "dsh-oh-my-dash" }));

  return {
    fetch: serve(app),
  };
}
