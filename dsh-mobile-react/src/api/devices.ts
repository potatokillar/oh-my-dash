// 设备路由：localStorage 持久化 + host.describe 在线探测
import { z } from "zod";
import { createRouter, publicQuery } from "./trpc";
import { DshClient } from "@/lib/dsh/client";
import type { HostDescription } from "@/lib/dsh/protocol";
import {
  loadDevices,
  saveDevices,
  addDevice as storeAddDevice,
  dropDeviceState,
  type StoredDevice,
} from "@/lib/store";
import { dropConnection } from "@/lib/dsh/connections";
import type { Device } from "@db/schema";

const ADDRESS_RE = /^(https?:\/\/)?[\w.-]+(:\d+)?(\/\S*)?$/;

export interface HostStatus {
  online: boolean;
  model?: string;
  cwd?: string;
  reason?: string;
}

function toDevice(d: StoredDevice): Device {
  return { ...d, createdAt: new Date(d.createdAt) };
}

function normalizeAddress(address: string): string {
  return /^https?:\/\//.test(address) ? address : `http://${address}`;
}

// 握手（host.describe）：进入设备列表时对每个设备执行，4s 超时
async function probeHost(address: string): Promise<HostStatus> {
  try {
    const desc = await Promise.race([
      new DshClient(address).rpc<HostDescription>("host.describe"),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("连接超时")), 4000)),
    ]);
    return {
      online: true,
      model: desc.provider && desc.model ? `${desc.provider}/${desc.model}` : desc.model,
      cwd: desc.cwd,
    };
  } catch (e) {
    return { online: false, reason: e instanceof Error ? e.message : "无法连接到主机" };
  }
}

export const devicesRouter = createRouter({
  // 设备列表 + 在线状态探测
  list: publicQuery.query(async () => {
    const rows = loadDevices().map(toDevice).sort((a, b) => b.id - a.id);
    return Promise.all(rows.map(async (d) => ({ ...d, status: await probeHost(d.address) })));
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
      const row = toDevice(storeAddDevice(input.name, normalizeAddress(input.address)));
      return { ...row, status: await probeHost(row.address) };
    }),

  update: publicQuery
    .input(
      z.object({
        id: z.number(),
        name: z.string().min(1).max(60),
        address: z.string().min(1).regex(ADDRESS_RE, "地址格式不正确"),
      }),
    )
    .mutation(({ input }) => {
      const devices = loadDevices().map((d) =>
        d.id === input.id
          ? { ...d, name: input.name, address: normalizeAddress(input.address) }
          : d,
      );
      saveDevices(devices);
      dropConnection(input.id); // 下次使用时按新地址重建连接
    }),

  remove: publicQuery
    .input(z.object({ id: z.number() }))
    .mutation(({ input }) => {
      saveDevices(loadDevices().filter((d) => d.id !== input.id));
      dropConnection(input.id);
      dropDeviceState(input.id);
    }),
});
