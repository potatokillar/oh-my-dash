// 会话事件 → 本地 Message 的共享转换（sessions.messages 与 useSessionStream 共用）
// 图片块按引用携带，经 session.attachment 解引用为 dataURL 供 <img> 直接渲染

import type { DshClient } from "./client";
import { messageFromEvent, splitContent, type SessionEvent } from "./protocol";
import type { Message } from "@db/schema";

export async function eventToMessage(
  client: DshClient,
  localSessionId: number,
  remoteId: string,
  ev: SessionEvent,
  status: Message["status"] = "done",
): Promise<Message | null> {
  const m = messageFromEvent(ev);
  if (!m) return null;
  const parts = splitContent(m.content);
  const images: string[] = [];
  for (const img of parts.images) {
    if (img.data && img.mediaType) {
      // 防御：上行 prompt 回显形态直接带 base64
      images.push(`data:${img.mediaType};base64,${img.data}`);
    } else if (img.attachmentId) {
      try {
        const value = await client.rpc<{ data: string; attachment: { mediaType: string } }>(
          "session.attachment",
          { sessionId: remoteId, attachmentId: img.attachmentId },
        );
        images.push(`data:${value.attachment.mediaType};base64,${value.data}`);
      } catch {
        // 附件读取失败：跳过该图，不影响消息本体
      }
    }
  }
  return {
    id: ev.seq,
    sessionId: localSessionId,
    role: m.isUser ? "user" : "assistant",
    content: parts.text,
    reasoning: parts.reasoning || null,
    images: images.length ? JSON.stringify(images) : null,
    status,
    seq: ev.seq,
    createdAt: new Date(m.time || Date.now()),
  };
}
