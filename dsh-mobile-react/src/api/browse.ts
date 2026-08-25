// 目录浏览路由：host.listDirectory / host.createDirectory
import { z } from "zod";
import { createRouter, publicQuery } from "./trpc";
import { getConnection } from "@/lib/dsh/connections";
import { normalizePath, pathBasename, type DirectoryListing } from "@/lib/dsh/protocol";

function requireConnection(deviceId: number) {
  const conn = getConnection(deviceId);
  if (!conn) throw new Error("设备不存在");
  return conn;
}

export const browseRouter = createRouter({
  // host.listDirectory；showHidden=false 时客户端过滤点开头目录（协议不带此参数）
  list: publicQuery
    .input(z.object({ deviceId: z.number(), path: z.string(), showHidden: z.boolean().default(false) }))
    .query(async ({ input }) => {
      const conn = requireConnection(input.deviceId);
      const listing = await conn.client.rpc<DirectoryListing>("host.listDirectory", {
        path: input.path || undefined,
      });
      return {
        ...listing,
        entries: input.showHidden
          ? listing.entries
          : listing.entries.filter((e) => !e.hidden),
      };
    }),

  // host.createDirectory：入参为新目录完整路径，拆成 父路径 + 名称
  createDir: publicQuery
    .input(z.object({ deviceId: z.number(), path: z.string().min(1) }))
    .mutation(async ({ input }) => {
      const conn = requireConnection(input.deviceId);
      const p = normalizePath(input.path);
      const name = pathBasename(p);
      const parent = p.slice(0, p.length - name.length).replace(/\/+$/, "") || "/";
      const value = await conn.client.rpc<{ path: string }>("host.createDirectory", {
        path: parent,
        name,
      });
      return { path: value?.path ?? p };
    }),
});
