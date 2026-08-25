// DshWsPlugin 的 JS 薄封装：原生 WebSocket 下行通道（仅 App 内可用）。
// mux.ts 按 Capacitor.isNativePlatform() 在本实现与浏览器 WebSocket 之间选择。

import { registerPlugin } from "@capacitor/core";

export interface DshWsEvent {
  id: string;
  data?: string;
}

interface DshWsPluginApi {
  connect(opts: { url: string }): Promise<{ id: string }>;
  close(opts: { id: string }): Promise<void>;
  addListener(
    event: "open" | "message" | "error" | "closed",
    fn: (e: DshWsEvent) => void,
  ): Promise<{ remove(): Promise<void> }>;
}

const DshWs = registerPlugin<DshWsPluginApi>("DshWs");

export interface WsHandlers {
  onOpen(): void;
  onMessage(data: string): void;
  onError(): void;
  onClose(): void;
}

/** 统一的最小下行 WS 形态：mux 只关心这几个回调与 close() */
export interface WsConnection {
  close(): void;
}

/** 原生实现：OkHttp WebSocket，事件经插件 notifyListeners 下行 */
export async function openNativeWs(url: string, handlers: WsHandlers): Promise<WsConnection> {
  const subs = await Promise.all([
    DshWs.addListener("open", (e) => {
      if (e.id === id) handlers.onOpen();
    }),
    DshWs.addListener("message", (e) => {
      if (e.id === id && e.data != null) handlers.onMessage(e.data);
    }),
    DshWs.addListener("error", (e) => {
      if (e.id === id) handlers.onError();
    }),
    DshWs.addListener("closed", (e) => {
      if (e.id === id) handlers.onClose();
    }),
  ]);
  const { id } = await DshWs.connect({ url });
  let closed = false;
  return {
    close() {
      if (closed) return;
      closed = true;
      void DshWs.close({ id });
      for (const s of subs) void s.remove();
    },
  };
}

/** 浏览器实现：vite dev 浏览器调试用（直连 dsh 同源/信任主机时可用） */
export function openBrowserWs(url: string, handlers: WsHandlers): WsConnection | null {
  let ws: WebSocket;
  try {
    ws = new WebSocket(url);
  } catch {
    return null;
  }
  ws.onopen = () => handlers.onOpen();
  ws.onmessage = (e) => handlers.onMessage(String(e.data));
  ws.onerror = () => handlers.onError();
  ws.onclose = () => handlers.onClose();
  return {
    close() {
      ws.onopen = ws.onmessage = ws.onerror = ws.onclose = null;
      try {
        ws.close();
      } catch {
        // 忽略关闭异常
      }
    },
  };
}
