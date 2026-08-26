import { z } from "zod";
import { eq } from "drizzle-orm";
import { createRouter, publicQuery } from "./middleware";
import { getDb } from "./queries/connection";
import { devices } from "@db/schema";
import { listDirectory, createDirectory, pathExists, normalizePath } from "./demoFs";

async function assertBuiltin(deviceId: number) {
  const [d] = await getDb().select().from(devices).where(eq(devices.id, deviceId));
  if (!d) throw new Error("设备不存在");
  if (d.kind !== "builtin") throw new Error("主机不在线，无法浏览目录");
  return d;
}

export const browseRouter = createRouter({
  // host.listDirectory
  list: publicQuery
    .input(z.object({ deviceId: z.number(), path: z.string(), showHidden: z.boolean().default(false) }))
    .query(async ({ input }) => {
      await assertBuiltin(input.deviceId);
      return listDirectory(input.path, input.showHidden);
    }),

  // host.createDirectory
  createDir: publicQuery
    .input(z.object({ deviceId: z.number(), path: z.string().min(1) }))
    .mutation(async ({ input }) => {
      await assertBuiltin(input.deviceId);
      const p = normalizePath(input.path);
      if (await pathExists(p)) throw new Error("目录已存在");
      await createDirectory(p);
      return { path: p };
    }),
});
