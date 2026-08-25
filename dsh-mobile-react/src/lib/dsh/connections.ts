// 每台设备的活连接注册表：DshClient + EventMux 单例，以及待审批登记表。
// 待审批必须在连接层登记（而非页面层）：trpc sessions.respond 只有 rpcId 入参，
// 应答时靠这里反查 sessionId/approvalId 与目标设备。

import { DshClient } from "./client";
import { EventMux } from "./mux";
import { getDevice } from "../store";

export interface PendingApproval {
  rpcId: string;
  deviceId: number;
  sessionId: string; // 远端 sessionId
  approvalId: string;
  toolName: string;
  reason?: string;
}

export interface DeviceConnection {
  deviceId: number;
  client: DshClient;
  mux: EventMux;
  /** rpcId → 审批上下文（approval/resolved 时移除） */
  pendingApprovals: Map<string, PendingApproval>;
}

const connections = new Map<number, DeviceConnection>();

/** 取（或建）设备的活连接；设备不存在返回 null */
export function getConnection(deviceId: number): DeviceConnection | null {
  const hit = connections.get(deviceId);
  if (hit) return hit;
  const device = getDevice(deviceId);
  if (!device) return null;
  const conn: DeviceConnection = {
    deviceId,
    client: new DshClient(device.address),
    mux: new EventMux(device.address),
    pendingApprovals: new Map(),
  };
  conn.mux.onFrame((msg) => {
    const f = msg.payload;
    if (f.type === "approval/requested" && f.sessionId && f.approvalId) {
      conn.pendingApprovals.set(msg.rpcId, {
        rpcId: msg.rpcId,
        deviceId,
        sessionId: f.sessionId,
        approvalId: f.approvalId,
        toolName: f.toolName ?? "(未知工具)",
        reason: f.reason,
      });
    } else if (f.type === "approval/resolved") {
      for (const [rpcId, a] of conn.pendingApprovals) {
        if (a.approvalId === f.approvalId && a.sessionId === f.sessionId) {
          conn.pendingApprovals.delete(rpcId);
        }
      }
    }
  });
  conn.mux.connect();
  connections.set(deviceId, conn);
  return conn;
}

/** 拆除设备连接（编辑/删除设备后调用，下次使用时按新地址重建） */
export function dropConnection(deviceId: number): void {
  const conn = connections.get(deviceId);
  if (!conn) return;
  conn.mux.close();
  connections.delete(deviceId);
}

/** 全表反查待审批（respond 只有 rpcId，不知道设备） */
export function findPendingApproval(rpcId: string): PendingApproval | undefined {
  for (const conn of connections.values()) {
    const hit = conn.pendingApprovals.get(rpcId);
    if (hit) return hit;
  }
  return undefined;
}
