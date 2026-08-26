import { z } from "zod";
import { eq, desc } from "drizzle-orm";
import { createRouter, publicQuery } from "./middleware";
import { getDb } from "./queries/connection";
import { devices } from "@db/schema";
import { probeHost } from "./hostProbe";

const ADDRESS_RE = /^(https?:\/\/)?[\w.-]+(:\d+)?(\/\S*)?$/;

export const devicesRouter = createRouter({
  // 设备列表 + 在线状态探测（进入列表时对每个设备执行握手）
  list: publicQuery.query(async () => {
    const rows = await getDb().select().from(devices).orderBy(desc(devices.id));
    return Promise.all(
      rows.map(async (d) => ({ ...d, status: await probeHost(d) })),
    );
  }),

  add: publicQuery
    .input(
      z.object({
        name: z.string().min(1, "请输入名称").max(60),
        address: z
          .string()
          .min(1, "请输入地址")
          .regex(ADDRESS_RE, "地址格式不正确，例如 192.168.1.10:3080"),
      }),
    )
    .mutation(async ({ input }) => {
      const address = /^https?:\/\//.test(input.address)
        ? input.address
        : `http://${input.address}`;
      const [{ id }] = await getDb()
        .insert(devices)
        .values({ name: input.name, address, kind: "remote" })
        .$returningId();
      const [row] = await getDb().select().from(devices).where(eq(devices.id, id));
      return { ...row, status: await probeHost(row) };
    }),

  update: publicQuery
    .input(
      z.object({
        id: z.number(),
        name: z.string().min(1).max(60),
        address: z.string().min(1).regex(ADDRESS_RE, "地址格式不正确"),
      }),
    )
    .mutation(async ({ input }) => {
      const address = /^https?:\/\//.test(input.address)
        ? input.address
        : `http://${input.address}`;
      await getDb()
        .update(devices)
        .set({ name: input.name, address })
        .where(eq(devices.id, input.id));
    }),

  remove: publicQuery
    .input(z.object({ id: z.number() }))
    .mutation(async ({ input }) => {
      await getDb().delete(devices).where(eq(devices.id, input.id));
    }),
});
