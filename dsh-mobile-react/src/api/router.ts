// 应用路由：与原演示后端同名同签名，数据源换成本地 dsh RPC + localStorage
import { createRouter, publicQuery } from "./trpc";
import { devicesRouter } from "./devices";
import { sessionsRouter } from "./sessions";
import { browseRouter } from "./browse";

export const appRouter = createRouter({
  ping: publicQuery.query(() => ({ ok: true, ts: Date.now() })),
  devices: devicesRouter,
  sessions: sessionsRouter,
  browse: browseRouter,
});

export type AppRouter = typeof appRouter;
