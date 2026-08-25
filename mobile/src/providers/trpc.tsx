import { createTRPCReact } from "@trpc/react-query";
import { TRPCClientError, type TRPCLink } from "@trpc/client";
import { observable } from "@trpc/server/observable";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { appRouter, type AppRouter } from "@/api/router";
import type { ReactNode } from "react";

export const trpc = createTRPCReact<AppRouter>();

// 纯浏览器端：自定义 link 直接调用本地 caller，零 HTTP、无序列化
const localCallerLink: TRPCLink<AppRouter> = () => {
  return ({ op }) =>
    observable((observer) => {
      const caller = appRouter.createCaller({});
      // path 形如 "sessions.list"，逐级取到 procedure 函数
      const procedure = op.path
        .split(".")
        .reduce<unknown>((acc, key) => (acc as Record<string, unknown>)?.[key], caller);
      if (typeof procedure !== "function") {
        observer.error(TRPCClientError.from(new Error(`未知 procedure: ${op.path}`)));
        return () => {};
      }
      Promise.resolve()
        .then(() => (procedure as (input: unknown) => unknown)(op.input))
        .then((data) => {
          observer.next({ result: { data } });
          observer.complete();
        })
        .catch((cause) => observer.error(TRPCClientError.from(cause)));
      return () => {};
    });
};

const queryClient = new QueryClient();
const trpcClient = trpc.createClient({
  links: [localCallerLink],
});

export function TRPCProvider({ children }: { children: ReactNode }) {
  return (
    <trpc.Provider client={trpcClient} queryClient={queryClient}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </trpc.Provider>
  );
}
