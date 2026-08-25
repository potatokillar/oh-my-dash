// dsh JSON-RPC over HTTP 客户端（对齐 dsh_mobile/lib/dsh_api.dart）
// 一元调用：POST <base>/api/<method>；审批应答：POST <base>/api/respond

import type { ServerResponse } from "./protocol";

export class DshApiError extends Error {
  method: string;

  constructor(method: string, message: string) {
    super(`${method}: ${message}`);
    this.name = "DshApiError";
    this.method = method;
  }
}

export class DshClient {
  baseUrl: string;
  private seq = 0;

  constructor(baseUrl: string) {
    // 去掉尾部斜杠，避免拼出 //api
    this.baseUrl = baseUrl.replace(/\/+$/, "");
  }

  private async post(path: string, body: unknown): Promise<Record<string, unknown>> {
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}${path}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
    } catch (e) {
      throw new DshApiError(path, `无法连接服务器: ${e instanceof Error ? e.message : e}`);
    }
    const text = await res.text();
    if (res.status !== 200) throw new DshApiError(path, `HTTP ${res.status}: ${text}`);
    let decoded: unknown;
    try {
      decoded = JSON.parse(text);
    } catch {
      throw new DshApiError(path, `意外响应: ${text.slice(0, 200)}`);
    }
    if (!decoded || typeof decoded !== "object") {
      throw new DshApiError(path, `意外响应: ${text.slice(0, 200)}`);
    }
    return decoded as Record<string, unknown>;
  }

  /** 一元调用：POST `<base>/api/<method>`，result.ok=false 时抛错 */
  async rpc<T = unknown>(method: string, payload: Record<string, unknown> = {}): Promise<T> {
    const rpcId = `dsh-web-${++this.seq}-${Date.now()}`;
    const msg = (await this.post(`/api/${method}`, {
      type: "client-request",
      rpcId,
      method,
      payload,
    })) as unknown as ServerResponse;
    if (msg.type !== "server-response" || !msg.result) {
      throw new DshApiError(method, `意外报文: ${JSON.stringify(msg).slice(0, 200)}`);
    }
    if (msg.result.ok === true) return msg.result.value as T;
    const error = msg.result.error as { message?: string; code?: string } | undefined;
    const em = error && typeof error === "object" ? (error.message ?? error.code) : error;
    throw new DshApiError(method, `RPC 错误: ${em ?? "未知"}`);
  }

  /** 应答可应答的 server-request（审批）：POST /api/respond，原样回显 rpcId */
  async respond(rpcId: string, value: Record<string, unknown>): Promise<void> {
    await this.post("/api/respond", {
      type: "client-response",
      rpcId,
      result: { ok: true, value },
    });
  }

  /** 审批应答便捷封装 */
  respondApproval(opts: {
    rpcId: string;
    sessionId: string;
    approvalId: string;
    outcome: "allowed-once" | "rejected";
  }): Promise<void> {
    return this.respond(opts.rpcId, {
      sessionId: opts.sessionId,
      approvalId: opts.approvalId,
      outcome: opts.outcome,
    });
  }
}
