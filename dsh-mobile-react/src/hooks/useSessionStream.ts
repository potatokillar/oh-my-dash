// 会话实时流：dsh events.mux（WebSocket）+ session.history 快照
// 返回形状与事件应用语义与原 SSE 版一致：{session, messages, pendingApprovals, connected}
// 快照→增量、流式气泡、审批重放去重（rpcId）、断线重连后重新拉快照对齐
import { useEffect, useRef, useState } from "react";
import type { Message, Session } from "@db/schema";
import { getConnection, type PendingApproval } from "@/lib/dsh/connections";
import type { MuxMessage } from "@/lib/dsh/mux";
import { resolveSession, getCachedModel, setCachedModel } from "@/lib/store";
import {
  chunkDelta,
  sessionDisplayName,
  turnEndInterrupted,
  type HistoryPage,
  type SessionModels,
  type SessionSummary,
} from "@/lib/dsh/protocol";
import { eventToMessage } from "@/lib/dsh/messages";
import { updateModelCatalog } from "@contracts/models";

export interface PendingApprovalInfo {
  rpcId: string;
  tool: string;
  description: string;
  /** 内部使用：approval/resolved 按 approvalId 反查移除 */
  approvalId?: string;
}

interface StreamState {
  session: Session | null;
  messages: Message[];
  pendingApprovals: PendingApprovalInfo[];
  connected: boolean;
}

const PAGE_SIZE = 30;
const BUBBLE_ID = -1; // 流式占位气泡的固定 id（真实消息 id = 事件 seq，不会为负）

export function useSessionStream(sessionId: number | null) {
  const [state, setState] = useState<StreamState>({
    session: null,
    messages: [],
    pendingApprovals: [],
    connected: false,
  });
  const seenApprovals = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (sessionId === null) return;
    const binding = resolveSession(sessionId);
    if (!binding) return;
    const conn = getConnection(binding.deviceId);
    if (!conn) return;

    const remoteId = binding.remoteId;
    const deviceId = binding.deviceId;
    let disposed = false;
    let loading = false;
    let prevConnected = false;
    let didInitialLoad = false;
    const buffer: MuxMessage[] = []; // 快照加载期间到达的帧，加载完后回放
    const seenEventSeqs = new Set<number>(); // user/assistant message 去重（快照与增量共用）

    const toApprovalInfo = (a: PendingApproval): PendingApprovalInfo => ({
      rpcId: a.rpcId,
      tool: a.toolName,
      description: a.reason ?? "",
      approvalId: a.approvalId,
    });

    // 快照：会话行 + 最近一页消息 + 待审批 + 模型目录
    const loadSnapshot = async () => {
      if (loading || disposed) return;
      loading = true;
      try {
        const [list, page] = await Promise.all([
          conn.client.rpc<{ items?: SessionSummary[] }>("session.list"),
          conn.client.rpc<HistoryPage>("session.history", {
            sessionId: remoteId,
            maxMessages: PAGE_SIZE,
          }),
        ]);
        // 模型目录：驱动 ModelSheet / 模型 chip；老主机没有 session.models 时用缓存兜底
        let sel = getCachedModel(deviceId, remoteId) ?? { provider: "", model: "", effort: "off" };
        try {
          const models = await conn.client.rpc<SessionModels>("session.models", { sessionId: remoteId });
          if (disposed) return;
          if (models?.current?.provider) {
            sel = {
              provider: models.current.provider,
              model: models.current.model,
              effort: models.current.reasoningEffort ?? "off",
            };
            setCachedModel(deviceId, remoteId, sel);
          }
          updateModelCatalog(models);
        } catch {
          // 目录拉取失败不阻塞会话
        }
        const events = Array.isArray(page?.events) ? page.events : [];
        const messages: Message[] = [];
        for (const entry of events) {
          const ev = entry?.event;
          if (!ev) continue;
          const msg = await eventToMessage(conn.client, sessionId, remoteId, ev);
          if (msg) {
            seenEventSeqs.add(ev.seq);
            messages.push(msg);
          }
        }
        if (disposed) return;
        const summary = list?.items?.find((s) => s.sessionId === remoteId);
        const session: Session = {
          id: sessionId,
          deviceId,
          title: summary ? sessionDisplayName(summary) : "新会话",
          cwd: summary?.cwd ?? null,
          provider: sel.provider,
          model: sel.model,
          effort: sel.effort,
          archived: false,
          running: summary?.running ?? false,
          createdAt: new Date(binding.createdAt),
          updatedAt: new Date(summary?.updatedAt || Date.now()),
        };
        const approvals = [...conn.pendingApprovals.values()]
          .filter((a) => a.sessionId === remoteId)
          .filter((a) => {
            // 重放去重：重连后重复的待审批帧不重复弹窗
            if (seenApprovals.current.has(a.rpcId)) return false;
            seenApprovals.current.add(a.rpcId);
            return true;
          })
          .map(toApprovalInfo);
        setState((s) => ({ ...s, session, messages, pendingApprovals: approvals }));
      } catch {
        // 设备离线等：保持空态，connected 标志由 mux 状态驱动
      } finally {
        loading = false;
        // 回放加载期间缓存的帧
        const pending = buffer.splice(0);
        for (const msg of pending) processFrame(msg);
      }
    };

    const upsertBubble = (s: StreamState, seq: number, kind: "text" | "reasoning", text: string): StreamState => {
      const bubble = s.messages.find((m) => m.id === BUBBLE_ID);
      if (!bubble) {
        const msg: Message = {
          id: BUBBLE_ID,
          sessionId,
          role: "assistant",
          content: kind === "text" ? text : "",
          reasoning: kind === "reasoning" ? text : null,
          images: null,
          status: "streaming",
          seq,
          createdAt: new Date(),
        };
        return { ...s, messages: [...s.messages, msg] };
      }
      return {
        ...s,
        messages: s.messages.map((m) =>
          m.id === BUBBLE_ID
            ? kind === "reasoning"
              ? { ...m, reasoning: (m.reasoning ?? "") + text }
              : { ...m, content: m.content + text }
            : m,
        ),
      };
    };

    // 最终消息（user/message、assistant/message）：图片要解引用，异步构建后落状态
    const appendFinalMessage = (ev: Parameters<typeof eventToMessage>[3]) => {
      seenEventSeqs.add(ev.seq);
      void eventToMessage(conn.client, sessionId, remoteId, ev).then((msg) => {
        if (disposed || !msg) return;
        setState((s) => {
          if (s.messages.some((m) => m.id === msg.id)) return s;
          // 最终 assistant/message 替换流式占位气泡
          const base = msg.role === "assistant" ? s.messages.filter((m) => m.id !== BUBBLE_ID) : s.messages;
          return { ...s, messages: [...base, msg] };
        });
      });
    };

    const processFrame = (msg: MuxMessage) => {
      const f = msg.payload;
      if (f.sessionId !== remoteId) return; //  mux 是全会话聚合流，按会话过滤
      if (f.type === "session/event") {
        const ev = f.event;
        if (!ev) return;
        switch (ev.type) {
          case "turn/start":
            setState((s) => (s.session ? { ...s, session: { ...s.session, running: true } } : s));
            break;
          case "turn/end": {
            const interrupted = turnEndInterrupted(ev);
            setState((s) => ({
              ...s,
              session: s.session ? { ...s.session, running: false } : s.session,
              // turn 结束时仍未被最终消息替换的气泡收尾（中断时 assistant/message 可能不来）
              messages: s.messages.map((m) =>
                m.id === BUBBLE_ID ? { ...m, status: interrupted ? "interrupted" : "done" } : m,
              ),
            }));
            break;
          }
          case "session/title": {
            const title = (ev.data as { title?: unknown } | undefined)?.title;
            if (typeof title === "string" && title) {
              setState((s) => (s.session ? { ...s, session: { ...s.session, title } } : s));
            }
            break;
          }
          case "assistant/chunk": {
            const delta = chunkDelta(ev);
            if (delta) setState((s) => upsertBubble(s, ev.seq, delta.kind, delta.text));
            break;
          }
          case "user/message":
          case "assistant/message":
            if (seenEventSeqs.has(ev.seq)) break; // 快照/增量重疊去重
            appendFinalMessage(ev);
            break;
        }
      } else if (f.type === "approval/requested") {
        if (seenApprovals.current.has(msg.rpcId)) return; // 重放去重
        seenApprovals.current.add(msg.rpcId);
        const info = toApprovalInfo({
          rpcId: msg.rpcId,
          deviceId,
          sessionId: remoteId,
          approvalId: f.approvalId ?? "",
          toolName: f.toolName ?? "(未知工具)",
          reason: f.reason,
        });
        setState((s) => ({ ...s, pendingApprovals: [...s.pendingApprovals, info] }));
      } else if (f.type === "approval/resolved") {
        setState((s) => ({
          ...s,
          pendingApprovals: s.pendingApprovals.filter((a) => a.approvalId !== f.approvalId),
        }));
      }
    };

    const onFrame = (msg: MuxMessage) => {
      if (disposed) return;
      if (loading) {
        buffer.push(msg);
        return;
      }
      processFrame(msg);
    };

    const onStatus = (connected: boolean) => {
      if (disposed) return;
      setState((s) => ({ ...s, connected }));
      // 断线重连：重新拉快照对齐（服务端会自动重放待审批帧，按 rpcId 去重）
      if (connected && !prevConnected && didInitialLoad) void loadSnapshot();
      prevConnected = connected;
    };

    const offFrame = conn.mux.onFrame(onFrame);
    const offStatus = conn.mux.onStatus(onStatus);
    setState((s) => ({ ...s, connected: conn.mux.connected }));
    void loadSnapshot().then(() => {
      didInitialLoad = true;
    });

    return () => {
      disposed = true;
      offFrame();
      offStatus();
    };
  }, [sessionId]);

  return state;
}
