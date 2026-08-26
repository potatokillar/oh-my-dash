import { DEFAULT_MODEL } from "@contracts/models";
import type { Device } from "@db/schema";

export interface HostStatus {
  online: boolean;
  model?: string;
  cwd?: string;
  reason?: string;
}

// 握手（host.describe）：进入设备列表时对每个设备执行
export async function probeHost(device: Device): Promise<HostStatus> {
  if (device.kind === "builtin") {
    return {
      online: true,
      model: `${DEFAULT_MODEL.provider}/${DEFAULT_MODEL.model}`,
      cwd: "/home/dev",
    };
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 4000);
  try {
    const res = await fetch(`${device.address.replace(/\/$/, "")}/api/describe`, {
      signal: controller.signal,
    });
    if (!res.ok) return { online: false, reason: `主机返回 HTTP ${res.status}` };
    const data = (await res.json()) as { model?: string; cwd?: string };
    return { online: true, model: data.model, cwd: data.cwd };
  } catch (e) {
    const msg = e instanceof Error && e.name === "AbortError" ? "连接超时" : "无法连接到主机";
    return { online: false, reason: msg };
  } finally {
    clearTimeout(timer);
  }
}
