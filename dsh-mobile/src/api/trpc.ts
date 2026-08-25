// tRPC 初始化：纯浏览器内直接调用（无 HTTP）。
// transformer 只是类型级标记：不配置时客户端类型会把输出按 JSON 序列化推断
// （Date → string），与直调不传序列化的实际行为不符；恒等 transformer 让
// 输出类型保持原样（运行时不经链路，恒等函数实际不会被调用）。
import { initTRPC } from "@trpc/server";

const identity = { serialize: (v: unknown) => v, deserialize: (v: unknown) => v };

const t = initTRPC.create({
  // 路由跑在浏览器 WebView 里（本地路由直调，无 HTTP），显式声明允许非服务端环境
  allowOutsideOfServer: true,
  transformer: { input: identity, output: identity },
});

export const createRouter = t.router;
export const publicQuery = t.procedure;
