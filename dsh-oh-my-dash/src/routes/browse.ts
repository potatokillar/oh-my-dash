import { Hono } from "hono";
import type { DshContext } from "../index.js";

interface FsLike {
  readdir?(path: string): Promise<{ name: string; isDir: boolean }[]>;
  stat?(path: string): Promise<{ isDir: boolean; size: number; mtime: number }>;
}

/**
 * 目录浏览:走 ctx.fs(带工作区边界的安全读),而非裸 node fs。
 */
export function browseRoutes(ctx: DshContext) {
  const app = new Hono();

  app.get("/", async (c) => {
    const path = c.req.query("path") ?? ".";
    const fs = ctx.get("fs") as FsLike | undefined;
    if (!fs?.readdir) {
      return c.json({ error: "fs service unavailable in this DSH profile" }, 503);
    }
    try {
      const entries = await fs.readdir(path);
      return c.json({ path, entries });
    } catch (e) {
      return c.json({ error: String(e) }, 400);
    }
  });

  return app;
}
