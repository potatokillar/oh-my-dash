// WebSocket 下行流：<base>/api/events.mux（对齐 dsh_mobile/lib/event_mux.dart）
// 只收不发；断线指数退避自动重连，直到 close()
// 传输层按平台选择：App 内走原生 DshWsPlugin（dsh /api 信任栅栏拒绝浏览器跨源 WS），
// vite dev 浏览器调试走浏览器 WebSocket。

import { Capacitor } from "@capacitor/core";
import type { MuxFrame } from "./protocol";
import { openBrowserWs, openNativeWs, type WsConnection } from "./nativeWs";

export interface MuxMessage {
  /** 信封 rpcId：应答可应答帧（如 approval/requested）时原样回显 */
  rpcId: string;
  payload: MuxFrame;
}

type FrameListener = (msg: MuxMessage) => void;
type StatusListener = (connected: boolean) => void;

export class EventMux {
  private baseUrl: string;
  private conn: WsConnection | null = null;
  private open = false;
  private closed = true;
  private retry = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private frameListeners = new Set<FrameListener>();
  private statusListeners = new Set<StatusListener>();

  get connected(): boolean {
    return this.open;
  }

  onFrame(fn: FrameListener): () => void {
    this.frameListeners.add(fn);
    return () => this.frameListeners.delete(fn);
  }

  onStatus(fn: StatusListener): () => void {
    this.statusListeners.add(fn);
    return () => this.statusListeners.delete(fn);
  }

  private emitStatus(connected: boolean) {
    for (const fn of this.statusListeners) fn(connected);
  }

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  connect(): void {
    this.closed = false;
    this.retry = 0;
    if (this.timer) clearTimeout(this.timer);
    this.teardown();
    void this.openSocket();
  }

  close(): void {
    this.closed = true;
    if (this.timer) clearTimeout(this.timer);
    this.teardown();
  }

  private teardown() {
    const conn = this.conn;
    this.conn = null;
    const wasOpen = this.open;
    this.open = false;
    if (conn) conn.close();
    if (wasOpen) this.emitStatus(false);
  }

  private async openSocket() {
    if (this.closed) return;
    const wsUrl = `${this.baseUrl.replace(/^http/, "ws")}/api/events.mux`;
    const handlers = {
      onOpen: () => {
        if (this.closed) return;
        this.open = true;
        this.retry = 0;
        this.emitStatus(true);
      },
      onMessage: (data: string) => {
        try {
          const msg = JSON.parse(data);
          if (msg && msg.type === "server-request" && msg.payload && typeof msg.payload === "object") {
            const frame: MuxMessage = { rpcId: String(msg.rpcId ?? ""), payload: msg.payload };
            for (const fn of this.frameListeners) fn(frame);
          }
        } catch {
          // 畸形帧：忽略
        }
      },
      onError: () => {
        // onClose 随后触发，统一在那里重连
      },
      onClose: () => {
        if (this.open) {
          this.open = false;
          this.emitStatus(false);
        }
        this.conn = null;
        this.scheduleReconnect();
      },
    };
    const conn = Capacitor.isNativePlatform()
      ? await openNativeWs(wsUrl, handlers).catch(() => null)
      : openBrowserWs(wsUrl, handlers);
    if (this.closed) {
      conn?.close();
      return;
    }
    if (!conn) {
      this.scheduleReconnect();
      return;
    }
    this.conn = conn;
  }

  private scheduleReconnect() {
    if (this.closed) return;
    if (this.timer) clearTimeout(this.timer);
    // 指数退避：1, 2, 4, 8, 16s，封顶 30s（对齐 Flutter）
    const delay = this.retry < 5 ? (1 << this.retry) * 1000 : 30000;
    this.retry++;
    this.timer = setTimeout(() => void this.openSocket(), delay);
  }
}
