// 会话路由：真实 dsh RPC（session.* / workspace.*）+ 本地注册表
import { z } from "zod";
import { createRouter, publicQuery } from "./trpc";
import { getConnection, findPendingApproval } from "@/lib/dsh/connections";
import {
  bindSession,
  resolveSession,
  getCachedModel,
  setCachedModel,
} from "@/lib/store";
import {
  normalizePath,
  sessionDisplayName,
  buildPromptContent,
  dataUrlToImage,
  type SessionSummary,
  type WorkspaceView,
  type HostDescription,
  type HistoryPage,
  type SessionModels,
} from "@/lib/dsh/protocol";
import { eventToMessage } from "@/lib/dsh/messages";
import type { Message, Session } from "@db/schema";

const UNKNOWN_GROUP = "__unknown__"; // 工作目录缺失的会话单独归组

function requireConnection(deviceId: number) {
  const conn = getConnection(deviceId);
  if (!conn) throw new Error("设备不存在");
  return conn;
}

function requireBinding(id: number) {
  const binding = resolveSession(id);
  if (!binding) throw new Error("会话不存在");
  return binding;
}

interface WorkspaceSnapshot {
  workspaces: WorkspaceView[];
  archivedSessionIds: Set<string>;
}

// workspace.list 不支持的老主机：降级为无项目、无归档（对齐 Flutter）
async function listWorkspaces(conn: ReturnType<typeof requireConnection>): Promise<WorkspaceSnapshot> {
  try {
    const value = await conn.client.rpc<{ items?: WorkspaceView[]; archivedSessionIds?: string[] }>(
      "workspace.list",
    );
    return {
      workspaces: Array.isArray(value?.items) ? value.items : [],
      archivedSessionIds: new Set(
        Array.isArray(value?.archivedSessionIds) ? value.archivedSessionIds : [],
      ),
    };
  } catch {
    return { workspaces: [], archivedSessionIds: new Set() };
  }
}

// 主机默认模型（session.list 不带模型信息，未缓存的会话用主机默认填充展示）
async function hostDefaultModel(
  conn: ReturnType<typeof requireConnection>,
): Promise<{ provider: string; model: string }> {
  try {
    const desc = await conn.client.rpc<HostDescription>("host.describe");
    return { provider: desc.provider ?? "", model: desc.model ?? "" };
  } catch {
    return { provider: "", model: "" };
  }
}

/** SessionSummary → 本地 Session 行（登记本地数值 id，填模型缓存/主机默认） */
function toLocalSession(
  deviceId: number,
  s: SessionSummary,
  hostDefault: { provider: string; model: string },
): Session {
  const binding = bindSession(deviceId, s.sessionId);
  const cached = getCachedModel(deviceId, s.sessionId);
  return {
    id: binding.id,
    deviceId,
    title: sessionDisplayName(s),
    cwd: s.cwd ?? null,
    provider: cached?.provider ?? hostDefault.provider,
    model: cached?.model ?? hostDefault.model,
    effort: cached?.effort ?? "off",
    archived: false,
    running: s.running,
    createdAt: new Date(binding.createdAt),
    updatedAt: new Date(s.updatedAt || Date.now()),
  };
}

// 设备离线时 RPC 抛错，页面按错误态展示
async function listRemoteSessions(conn: ReturnType<typeof requireConnection>) {
  const value = await conn.client.rpc<{ items?: SessionSummary[] }>("session.list");
  return Array.isArray(value?.items) ? value.items : [];
}

export const sessionsRouter = createRouter({
  // 全量会话列表（已归档自动隐藏）
  list: publicQuery
    .input(z.object({ deviceId: z.number() }))
    .query(async ({ input }) => {
      const conn = requireConnection(input.deviceId);
      const [items, ws] = await Promise.all([listRemoteSessions(conn), listWorkspaces(conn)]);
      const visible = items.filter((s) => !ws.archivedSessionIds.has(s.sessionId));
      // 有会话缺模型缓存时才取主机默认，避免每次轮询多发一次 RPC
      const needDefault = visible.some((s) => !getCachedModel(input.deviceId, s.sessionId));
      const hostDefault = needDefault
        ? await hostDefaultModel(conn)
        : { provider: "", model: "" };
      return visible
        .map((s) => toLocalSession(input.deviceId, s, hostDefault))
        .sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
    }),

  // 项目视图：会话按 cwd 聚合 + 已注册 workspace（空项目也展示）
  projects: publicQuery
    .input(z.object({ deviceId: z.number() }))
    .query(async ({ input }) => {
      const conn = requireConnection(input.deviceId);
      const [items, ws] = await Promise.all([listRemoteSessions(conn), listWorkspaces(conn)]);
      const visible = items.filter((s) => !ws.archivedSessionIds.has(s.sessionId));

      const result = new Map<
        string,
        { path: string | null; title: string | null; count: number; latest: Date; registered: boolean }
      >();
      for (const s of visible) {
        const key = s.cwd ? normalizePath(s.cwd) : UNKNOWN_GROUP;
        const g = result.get(key) ?? {
          path: key === UNKNOWN_GROUP ? null : key,
          title: null,
          count: 0,
          latest: new Date(0),
          registered: false,
        };
        g.count++;
        const t = new Date(s.updatedAt || 0);
        if (t > g.latest) g.latest = t;
        result.set(key, g);
      }
      for (const w of ws.workspaces) {
        if (!w.path) continue;
        const key = normalizePath(w.path);
        const existing = result.get(key);
        if (existing) {
          existing.title = w.title || null;
          existing.registered = true;
        } else {
          result.set(key, {
            path: key,
            title: w.title || null,
            count: 0,
            latest: new Date(w.createdAt || 0),
            registered: true,
          });
        }
      }
      return [...result.values()].sort((a, b) => b.latest.getTime() - a.latest.getTime());
    }),

  // 添加项目（注册 workspace；幂等，重复添加有提示）
  addProject: publicQuery
    .input(z.object({ deviceId: z.number(), path: z.string().min(1) }))
    .mutation(async ({ input }) => {
      const conn = requireConnection(input.deviceId);
      const value = await conn.client.rpc<{ created?: boolean }>("workspace.create", {
        path: input.path,
      });
      return { duplicated: !value?.created };
    }),

  byId: publicQuery
    .input(z.object({ id: z.number() }))
    .query(async ({ input }) => {
      const binding = requireBinding(input.id);
      const conn = requireConnection(binding.deviceId);
      const items = await listRemoteSessions(conn);
      const summary = items.find((s) => s.sessionId === binding.remoteId);
      const hostDefault = await hostDefaultModel(conn);
      const row = summary
        ? toLocalSession(binding.deviceId, summary, hostDefault)
        : // 列表里找不到（极少见）：用注册表信息兜底
          {
            id: binding.id,
            deviceId: binding.deviceId,
            title: "新会话",
            cwd: null,
            provider: hostDefault.provider,
            model: hostDefault.model,
            effort: "off",
            archived: false,
            running: false,
            createdAt: new Date(binding.createdAt),
            updatedAt: new Date(binding.createdAt),
          };
      const pendingApprovals = [...conn.pendingApprovals.values()]
        .filter((a) => a.sessionId === binding.remoteId)
        .map((a) => ({ rpcId: a.rpcId, tool: a.toolName, description: a.reason ?? "" }));
      return { ...row, pendingApprovals };
    }),

  create: publicQuery
    .input(
      z.object({
        deviceId: z.number(),
        cwd: z.string().nullable(),
        title: z.string().optional(),
      }),
    )
    .mutation(async ({ input }) => {
      const conn = requireConnection(input.deviceId);
      const value = await conn.client.rpc<{ sessionId: string }>("session.create", {
        ...(input.cwd ? { cwd: input.cwd } : {}),
      });
      const remoteId = value.sessionId;
      if (!remoteId) throw new Error("创建会话失败");
      if (input.title) {
        await conn.client.rpc("session.rename", { sessionId: remoteId, title: input.title });
      }
      const binding = bindSession(input.deviceId, remoteId);
      const hostDefault = await hostDefaultModel(conn);
      setCachedModel(input.deviceId, remoteId, { ...hostDefault, effort: "off" });
      const row: Session = {
        id: binding.id,
        deviceId: input.deviceId,
        title: input.title || "新会话",
        cwd: input.cwd,
        provider: hostDefault.provider,
        model: hostDefault.model,
        effort: "off",
        archived: false,
        running: false,
        createdAt: new Date(binding.createdAt),
        updatedAt: new Date(binding.createdAt),
      };
      return row;
    }),

  rename: publicQuery
    .input(z.object({ id: z.number(), title: z.string().min(1).max(80) }))
    .mutation(async ({ input }) => {
      const binding = requireBinding(input.id);
      const conn = requireConnection(binding.deviceId);
      await conn.client.rpc("session.rename", { sessionId: binding.remoteId, title: input.title });
    }),

  // 归档：dsh 的 registry 级归档（workspace.archiveSession），列表自动隐藏
  archive: publicQuery
    .input(z.object({ id: z.number() }))
    .mutation(async ({ input }) => {
      const binding = requireBinding(input.id);
      const conn = requireConnection(binding.deviceId);
      await conn.client.rpc("workspace.archiveSession", { sessionId: binding.remoteId });
    }),

  setModel: publicQuery
    .input(
      z.object({
        id: z.number(),
        provider: z.string(),
        model: z.string(),
        effort: z.string(),
      }),
    )
    .mutation(async ({ input }) => {
      const binding = requireBinding(input.id);
      const conn = requireConnection(binding.deviceId);
      // "off" 是本地目录对「无推理档」的占位，不上行（selectModel 会按目录校验 effort）
      await conn.client.rpc("session.selectModel", {
        sessionId: binding.remoteId,
        provider: input.provider,
        model: input.model,
        ...(input.effort !== "off" ? { reasoningEffort: input.effort } : {}),
      });
      setCachedModel(binding.deviceId, binding.remoteId, {
        provider: input.provider,
        model: input.model,
        effort: input.effort,
      });
    }),

  // 历史消息：beforeSeq 向上翻页（对齐 session.history 的窗口语义）
  messages: publicQuery
    .input(
      z.object({
        sessionId: z.number(),
        beforeSeq: z.number().nullish(),
        limit: z.number().min(1).max(100).default(30),
      }),
    )
    .query(async ({ input }) => {
      const binding = requireBinding(input.sessionId);
      const conn = requireConnection(binding.deviceId);
      const page = await conn.client.rpc<HistoryPage>("session.history", {
        sessionId: binding.remoteId,
        ...(input.beforeSeq != null ? { beforeSeq: input.beforeSeq } : {}),
        maxMessages: input.limit,
      });
      const events = Array.isArray(page?.events) ? page.events : [];
      const out: Message[] = [];
      for (const entry of events) {
        const ev = entry?.event;
        if (!ev) continue;
        const msg = await eventToMessage(conn.client, input.sessionId, binding.remoteId, ev);
        if (msg) out.push(msg);
      }
      return out;
    }),

  send: publicQuery
    .input(
      z.object({
        sessionId: z.number(),
        text: z.string().min(1),
        images: z.array(z.string()).max(9).default([]),
      }),
    )
    .mutation(async ({ input }) => {
      const binding = requireBinding(input.sessionId);
      const conn = requireConnection(binding.deviceId);
      const images = input.images
        .map((d, i) => dataUrlToImage(d, i))
        .filter((x): x is NonNullable<typeof x> => x !== null);
      const content = buildPromptContent(input.text, images);
      if (content.length === 0) throw new Error("消息内容为空");
      await conn.client.rpc("session.prompt", {
        sessionId: binding.remoteId,
        mode: "queue",
        content,
      });
      // 用户消息与助手回复都走 events.mux 实时下发，无需本地乐观插入
      return { ok: true as const };
    }),

  stop: publicQuery
    .input(z.object({ sessionId: z.number() }))
    .mutation(async ({ input }) => {
      const binding = requireBinding(input.sessionId);
      const conn = requireConnection(binding.deviceId);
      await conn.client.rpc("session.cancel", { sessionId: binding.remoteId });
      return { stopped: true };
    }),

  // 远程审批应答：原样回显 rpcId（POST /api/respond）
  respond: publicQuery
    .input(z.object({ rpcId: z.string(), allow: z.boolean() }))
    .mutation(async ({ input }) => {
      const pending = findPendingApproval(input.rpcId);
      if (!pending) return { ok: false };
      const conn = getConnection(pending.deviceId);
      if (!conn) return { ok: false };
      await conn.client.respondApproval({
        rpcId: input.rpcId,
        sessionId: pending.sessionId,
        approvalId: pending.approvalId,
        outcome: input.allow ? "allowed-once" : "rejected",
      });
      conn.pendingApprovals.delete(input.rpcId);
      return { ok: true };
    }),

  // 会话模型目录 + 当前选择（聊天页/useSessionStream 使用）
  models: publicQuery
    .input(z.object({ sessionId: z.number() }))
    .query(async ({ input }) => {
      const binding = requireBinding(input.sessionId);
      const conn = requireConnection(binding.deviceId);
      const value = await conn.client.rpc<SessionModels>("session.models", {
        sessionId: binding.remoteId,
      });
      if (value?.current?.provider) {
        setCachedModel(binding.deviceId, binding.remoteId, {
          provider: value.current.provider,
          model: value.current.model,
          effort: value.current.reasoningEffort ?? "off",
        });
      }
      return value;
    }),
});
