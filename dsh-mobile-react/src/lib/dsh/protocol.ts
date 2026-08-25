// dsh 协议的纯数据类型与报文解析助手（无 I/O，对齐 dsh_mobile/lib/models.dart）
// 权威来源：@deepseek-ai/dsh-host-apiproxy 的 api/*.d.ts 契约

// ---- 信封 ----

/** 一元调用回包：POST /api/<method> 的响应体 */
export interface ServerResponse {
  type: "server-response";
  rpcId: string;
  result: { ok: true; value: unknown } | { ok: false; error: unknown };
}

/** events.mux 下行帧信封：payload 为 MuxFrame，应答审批时原样回显 rpcId */
export interface MuxEnvelope {
  type: "server-request";
  rpcId: string;
  payload: MuxFrame;
}

// ---- host ----

export interface HostDescription {
  version: string;
  cwd: string;
  provider?: string;
  model?: string;
  attachedSessions: number;
  canOpenPath: boolean;
}

export interface DirectoryEntry {
  name: string;
  path: string;
  hidden: boolean;
}

export interface DirectoryListing {
  path: string;
  home: string;
  crumbs: DirectoryEntry[];
  entries: DirectoryEntry[];
  truncated: boolean;
}

// ---- session ----

/** 投影块：{asOfSeq, values: {<key>: <value>}}，title 等提示信息从这里挖 */
export interface ProjectionsBlock {
  asOfSeq: number;
  values: Record<string, unknown>;
}

/** session.list 的一行 */
export interface SessionSummary {
  sessionId: string;
  updatedAt: number; // epoch ms
  running: boolean;
  blank: boolean;
  cwd?: string;
  agentPreset?: string;
  projections?: ProjectionsBlock;
}

/** 会话事件（历史条目与 mux 帧共用）：seq 会话内单调递增 */
export interface SessionEvent {
  type: string;
  seq: number;
  time: number; // epoch ms
  data?: Record<string, unknown>;
}

export interface HistoryEntry {
  event: SessionEvent;
  view?: unknown;
}

export interface HistoryPage {
  events: HistoryEntry[];
  hasMore: boolean;
  projections?: ProjectionsBlock;
}

/** 消息 content 块（只关心渲染所需的最小字段） */
export interface ContentBlock {
  type: string;
  text?: string;
  name?: string;
  mediaType?: string;
  data?: string; // base64（仅 prompt 上行；历史里图片按引用携带）
  attachment?: { attachmentId: string; mediaType: string; name?: string };
}

// ---- 模型目录（session.models） ----

export interface ModelSelection {
  provider: string;
  model: string;
  reasoningEffort?: string;
}

export interface ModelCatalogModel {
  id: string;
  name: string;
  reasoning?: { efforts: { id: string; name: string }[]; defaultEffort?: string };
}

export interface ModelProviderGroup {
  id: string;
  name: string;
  models: ModelCatalogModel[];
}

export interface SessionModels {
  current: ModelSelection;
  routable: boolean;
  groups: ModelProviderGroup[];
  failures: { id: string; name: string; message: string }[];
}

// ---- workspace ----

export interface WorkspaceView {
  workspaceId: string;
  path: string;
  title: string;
  sessionIds: string[];
  createdAt: string; // ISO-8601
  updatedAt: string;
}

// ---- mux 帧 ----

/**
 * events.mux 下行帧（server-request 的 payload）。协议是演进式词汇表，
 * 这里用宽松结构：已知字段定型，其余经索引签名透传。
 * 已知 type：session/event、session/subscribed、approval/requested、
 * approval/resolved、question/*、session/queue、session/jobs、session/projection、stream/error
 */
export interface MuxFrame {
  type: string;
  sessionId?: string;
  /** session/event：原始会话事件 */
  event?: SessionEvent;
  /** session/subscribed：订阅基线 */
  lastSeq?: number;
  /** approval/requested、approval/resolved */
  approvalId?: string;
  toolName?: string;
  callId?: string;
  reason?: string;
  outcome?: string;
  [k: string]: unknown;
}

// ---- 解析助手 ----

/** 从 projections 块里防御式挖会话标题（对齐 Flutter extractTitle） */
export function extractTitle(projections: unknown): string | null {
  if (!projections || typeof projections !== "object") return null;
  const values = (projections as ProjectionsBlock).values;
  if (!values || typeof values !== "object") return null;
  for (const v of Object.values(values)) {
    if (typeof v === "string" && v) return v;
    if (v && typeof v === "object") {
      const t = (v as { title?: unknown }).title;
      if (typeof t === "string" && t) return t;
    }
  }
  return null;
}

/** 显示名：标题 > "新会话"（空会话）> cwd 基名 + 短 id */
export function sessionDisplayName(s: SessionSummary): string {
  const t = extractTitle(s.projections);
  if (t) return t;
  if (s.blank) return "新会话";
  const base = s.cwd ? pathBasename(s.cwd) : "";
  const short = s.sessionId.slice(0, 8);
  return base ? `${base} · ${short}` : short;
}

/** 从 content 块数组拆出正文 / reasoning / 图片引用（渲染用） */
export function splitContent(content: unknown): {
  text: string;
  reasoning: string;
  images: { attachmentId?: string; mediaType?: string; name: string; data?: string }[];
} {
  const out = { text: "", reasoning: "", images: [] as { attachmentId?: string; mediaType?: string; name: string; data?: string }[] };
  if (!Array.isArray(content)) return out;
  for (const b of content as ContentBlock[]) {
    if (!b || typeof b !== "object") continue;
    if (b.type === "image") {
      out.images.push({
        attachmentId: b.attachment?.attachmentId,
        mediaType: b.attachment?.mediaType ?? b.mediaType,
        name: b.attachment?.name ?? b.name ?? "图片",
        data: b.data,
      });
    } else if (b.type === "text" && b.text) {
      out.text += b.text;
    } else if (b.type === "reasoning" && b.text) {
      out.reasoning += b.text;
    }
  }
  return out;
}

/**
 * 会话事件 → 可渲染消息，不可见返回 null（对齐 Flutter messageFromEvent）：
 * - user/message 仅渲染 source.kind === 'user'（其余为运行时上下文快照）
 * - assistant/message 取 data.message.content
 */
export function messageFromEvent(event: SessionEvent): {
  isUser: boolean;
  content: ContentBlock[] | unknown;
  time: number;
} | null {
  const data = event.data;
  if (!data) return null;
  if (event.type === "user/message") {
    const source = data.source as { kind?: string } | undefined;
    if (source?.kind !== "user") return null;
    const content = data.content;
    if (!Array.isArray(content) || content.length === 0) return null;
    return { isUser: true, content, time: event.time };
  }
  if (event.type === "assistant/message") {
    const message = data.message as { content?: unknown } | undefined;
    if (!message || !Array.isArray(message.content) || message.content.length === 0) return null;
    return { isUser: false, content: message.content, time: event.time };
  }
  return null;
}

/**
 * assistant/chunk 增量：chunk 为 StreamChunk 鉴别联合
 * （text-delta / reasoning-delta 携带 text；其余形态无增量文本）
 */
export function chunkDelta(event: SessionEvent): { kind: "text" | "reasoning"; text: string } | null {
  if (event.type !== "assistant/chunk") return null;
  const chunk = event.data?.chunk as { type?: string; text?: string; delta?: { text?: string } } | undefined;
  if (!chunk) return null;
  if (chunk.type === "text-delta" && chunk.text) return { kind: "text", text: chunk.text };
  if (chunk.type === "reasoning-delta" && chunk.text) return { kind: "reasoning", text: chunk.text };
  // 防御旧形态：data.chunk.text / data.chunk.delta.text
  const legacy = chunk.text ?? chunk.delta?.text;
  if (legacy) return { kind: "text", text: legacy };
  return null;
}

/** turn/end 原因：aborted（用户停止）映射为 interrupted，其余为 done */
export function turnEndInterrupted(event: SessionEvent): boolean {
  const reason = event.data?.reason as { kind?: string } | undefined;
  return reason?.kind === "aborted";
}

// ---- prompt content 组装（对齐 Flutter buildPromptContent） ----

export interface PromptImage {
  mediaType: string;
  data: string; // base64
  name: string;
}

export function buildPromptContent(
  text: string,
  images: PromptImage[],
): { type: string; text?: string; mediaType?: string; data?: string; name?: string }[] {
  const content: { type: string; text?: string; mediaType?: string; data?: string; name?: string }[] = [];
  const t = text.trim();
  if (t) content.push({ type: "text", text: t });
  for (const img of images) {
    content.push({ type: "image", mediaType: img.mediaType, data: img.data, name: img.name });
  }
  return content;
}

/** dataURL → PromptImage；无法解析返回 null */
export function dataUrlToImage(dataUrl: string, index: number): PromptImage | null {
  const m = /^data:([\w/+.-]+);base64,(.*)$/s.exec(dataUrl);
  if (!m) return null;
  const ext = m[1].split("/")[1]?.replace("jpeg", "jpg") ?? "png";
  return { mediaType: m[1], data: m[2], name: `image-${index + 1}.${ext}` };
}

// ---- 路径 ----

/** 规范化主机路径：去尾部斜杠（保留根 "/ "） */
export function normalizePath(path: string): string {
  if (path.length > 1) return path.replace(/\/+$/, "") || "/";
  return path;
}

/** 路径最后一个非空段（"/" 本身返回 "/"） */
export function pathBasename(path: string): string {
  const p = normalizePath(path);
  if (p === "/") return "/";
  const i = p.lastIndexOf("/");
  return i < 0 ? p : p.slice(i + 1);
}
