import { Hono } from "hono";
import type { DshContext } from "../index.js";

/**
 * 主机信息:插件跑在 DSH 进程内,本机即设备。
 * 对应前端 devicesRouter 的探活/设备列表。
 */
export function hostRoutes(ctx: DshContext) {
  const app = new Hono();

  app.get("/", (c) => {
    const dsh = ctx.get("dsh") as { version?: string } | undefined;
    return c.json({
      devices: [
        {
          id: "local",
          name: "DSH Host",
          status: { online: true },
          version: dsh?.version ?? "unknown",
        },
      ],
    });
  });

  return app;
}
