import { createRouter, publicQuery } from "./middleware";
import { devicesRouter } from "./devicesRouter";
import { sessionsRouter } from "./sessionsRouter";
import { browseRouter } from "./browseRouter";

export const appRouter = createRouter({
  ping: publicQuery.query(() => ({ ok: true, ts: Date.now() })),
  devices: devicesRouter,
  sessions: sessionsRouter,
  browse: browseRouter,
});

export type AppRouter = typeof appRouter;
