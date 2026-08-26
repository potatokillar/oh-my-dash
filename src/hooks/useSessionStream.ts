import { useEffect, useMemo, useRef, useState } from "react";
import type { Message, Session } from "@db/schema";

export interface PendingApprovalInfo {
  rpcId: string;
  tool: string;
  description: string;
}

interface StreamState {
  session: Session | null;
  messages: Message[];
  pendingApprovals: PendingApprovalInfo[];
  connected: boolean;
}

// WebSocket 事件流的 SSE 实现：快照 + 增量事件，断线指数退避自动重连
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
    let es: EventSource | null = null;
    let closed = false;
    let attempt = 0;
    let timer: ReturnType<typeof setTimeout>;

    const connect = () => {
      if (closed) return;
      es = new EventSource(`/api/stream/session/${sessionId}`);

      es.onopen = () => {
        attempt = 0;
        setState((s) => ({ ...s, connected: true }));
      };

      es.onmessage = (e) => {
        let ev: { type: string; [k: string]: unknown };
        try {
          ev = JSON.parse(e.data);
        } catch {
          return;
        }
        setState((s) => applyEvent(s, ev, seenApprovals.current));
      };

      es.onerror = () => {
        es?.close();
        setState((s) => ({ ...s, connected: false }));
        if (closed) return;
        // 指数退避自动重连
        const delay = Math.min(2 ** attempt * 500, 15000);
        attempt++;
        timer = setTimeout(connect, delay);
      };
    };

    connect();
    return () => {
      closed = true;
      clearTimeout(timer);
      es?.close();
    };
  }, [sessionId]);

  return state;
}

function applyEvent(
  s: StreamState,
  ev: { type: string; [k: string]: unknown },
  seenApprovals: Set<string>,
): StreamState {
  switch (ev.type) {
    case "snapshot": {
      const msgs = (ev.messages as Message[]).map(normalizeMessage);
      const approvals = (ev.pendingApprovals as PendingApprovalInfo[]).filter((a) => {
        // 重放去重：重连后重复的待审批帧不重复弹窗
        if (seenApprovals.has(a.rpcId)) return false;
        seenApprovals.add(a.rpcId);
        return true;
      });
      return {
        ...s,
        session: normalizeSession(ev.session as Session),
        messages: msgs,
        pendingApprovals: approvals,
      };
    }
    case "user_message": {
      const msg = normalizeMessage(ev.message as Message);
      if (s.messages.some((m) => m.id === msg.id)) return s;
      return { ...s, messages: [...s.messages, msg] };
    }
    case "message_start": {
      const seq = ev.seq as number;
      const messageId = ev.messageId as number;
      if (s.messages.some((m) => m.id === messageId)) return s;
      const msg: Message = {
        id: messageId,
        sessionId: s.session?.id ?? 0,
        role: "assistant",
        content: "",
        reasoning: null,
        images: null,
        status: "streaming",
        seq,
        createdAt: new Date(),
      };
      return { ...s, messages: [...s.messages, msg] };
    }
    case "reasoning_delta":
    case "content_delta": {
      const messageId = ev.messageId as number;
      const delta = ev.delta as string;
      return {
        ...s,
        messages: s.messages.map((m) =>
          m.id === messageId
            ? ev.type === "reasoning_delta"
              ? { ...m, reasoning: (m.reasoning ?? "") + delta }
              : { ...m, content: m.content + delta }
            : m,
        ),
      };
    }
    case "message_final": {
      const messageId = ev.messageId as number;
      return {
        ...s,
        messages: s.messages.map((m) =>
          m.id === messageId ? { ...m, status: ev.status as Message["status"] } : m,
        ),
      };
    }
    case "session_updated":
      return s.session
        ? { ...s, session: { ...s.session, running: !s.messages.some((m) => m.status === "streaming") } }
        : s;
    case "approval_request": {
      const rpcId = ev.rpcId as string;
      if (seenApprovals.has(rpcId)) return s; // 重放去重
      seenApprovals.add(rpcId);
      return {
        ...s,
        pendingApprovals: [
          ...s.pendingApprovals,
          { rpcId, tool: ev.tool as string, description: ev.description as string },
        ],
      };
    }
    case "approval_resolved":
      return {
        ...s,
        pendingApprovals: s.pendingApprovals.filter((a) => a.rpcId !== ev.rpcId),
      };
    default:
      return s;
  }
}

// tRPC superjson 会给 Date，SSE JSON 只有 string —— 统一归一化
function normalizeMessage(m: Message): Message {
  return { ...m, createdAt: new Date(m.createdAt) };
}
function normalizeSession(x: Session): Session {
  return { ...x, createdAt: new Date(x.createdAt), updatedAt: new Date(x.updatedAt) };
}

export function useNormalizedSession(sessionId: number | null) {
  const q = sessionId;
  return useMemo(() => q, [q]);
}
