import type { IncomingMessage, ServerResponse } from "node:http";
import type { Hono } from "hono";
import { getRequestListener } from "@hono/node-server";

/** 把 Hono app 包成 node http 的请求监听器 */
export function serve(app: Hono) {
  return getRequestListener(app.fetch);
}

export type { IncomingMessage, ServerResponse };
