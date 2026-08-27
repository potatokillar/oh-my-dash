import { createServer } from "node:http";
import { createApp } from "./server.js";

// Cordis 上下文的最小类型(避免依赖 preview 版不稳定的全量类型)
export interface DshContext {
  on(event: string, listener: (...args: any[]) => void): () => void;
  effect(fn: () => void | (() => void)): () => void;
  get(key: string): unknown;
  logger(name: string): { info(msg: string, ...a: unknown[]): void; warn(msg: string, ...a: unknown[]): void; error(msg: string, ...a: unknown[]): void };
  [key: string]: unknown;
}

export interface PluginConfig {
  port?: number;
  clientDir?: string;
}

export const name = "dsh-oh-my-dash";

/**
 * 插件入口:DSH(Cordis)加载 bundle 时调用。
 * 所有注册都包在 ctx.effect 里,卸载插件时自动回收。
 */
export function apply(ctx: DshContext, config: PluginConfig = {}) {
  const log = typeof ctx.logger === "function" ? ctx.logger(name) : console;
  const app = createApp(ctx);

  const server = createServer((req, res) => {
    app.fetch(req, res);
  });

  ctx.effect(() => {
    const port = config.port ?? 0;
    server.listen(port, () => {
      const addr = server.address();
      const actual = typeof addr === "object" && addr ? addr.port : port;
      log.info(`oh-my-dash mobile client ready: http://0.0.0.0:${actual}/`);
    });
    return () => {
      server.close();
      log.info("oh-my-dash plugin disposed");
    };
  });
}

export default apply;
