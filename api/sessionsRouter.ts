import { z } from "zod";
import { eq, and, desc, lt, sql } from "drizzle-orm";
import { createRouter, publicQuery } from "./middleware";
import { getDb } from "./queries/connection";
import { messages, projects, sessions } from "@db/schema";
import { DEFAULT_MODEL } from "@contracts/models";
import { startTurn, requestStop, respondApproval, getPendingApprovals, emit } from "./agent";

const UNKNOWN_GROUP = "__unknown__"; // 工作目录缺失的会话单独归组

export const sessionsRouter = createRouter({
  // 全量会话列表（已归档自动隐藏）
  list: publicQuery
    .input(z.object({ deviceId: z.number() }))
    .query(async ({ input }) => {
      return getDb()
        .select()
        .from(sessions)
        .where(and(eq(sessions.deviceId, input.deviceId), eq(sessions.archived, false)))
        .orderBy(desc(sessions.updatedAt));
    }),

  // 项目视图：会话按 cwd 聚合 + 注册的空项目
  projects: publicQuery
    .input(z.object({ deviceId: z.number() }))
    .query(async ({ input }) => {
      const db = getDb();
      const sess = await db
        .select()
        .from(sessions)
        .where(and(eq(sessions.deviceId, input.deviceId), eq(sessions.archived, false)));
      const registered = await db
        .select()
        .from(projects)
        .where(eq(projects.deviceId, input.deviceId));

      const groups = new Map<string, { count: number; latest: Date }>();
      for (const s of sess) {
        const key = s.cwd || UNKNOWN_GROUP;
        const g = groups.get(key) ?? { count: 0, latest: s.updatedAt };
        g.count++;
        if (s.updatedAt > g.latest) g.latest = s.updatedAt;
        groups.set(key, g);
      }
      const result = new Map<
        string,
        { path: string | null; title: string | null; count: number; latest: Date; registered: boolean }
      >();
      for (const [key, g] of groups) {
        result.set(key, {
          path: key === UNKNOWN_GROUP ? null : key,
          title: null,
          count: g.count,
          latest: g.latest,
          registered: false,
        });
      }
      for (const p of registered) {
        const existing = result.get(p.path);
        if (existing) {
          existing.title = p.title;
          existing.registered = true;
        } else {
          result.set(p.path, {
            path: p.path,
            title: p.title,
            count: 0,
            latest: p.createdAt,
            registered: true,
          });
        }
      }
      return [...result.values()].sort((a, b) => b.latest.getTime() - a.latest.getTime());
    }),

  // 添加项目（幂等，重复添加有提示）
  addProject: publicQuery
    .input(z.object({ deviceId: z.number(), path: z.string().min(1) }))
    .mutation(async ({ input }) => {
      const db = getDb();
      const [existing] = await db
        .select()
        .from(projects)
        .where(and(eq(projects.deviceId, input.deviceId), eq(projects.path, input.path)));
      if (existing) return { duplicated: true as const };
      const title = input.path.split("/").filter(Boolean).pop() ?? input.path;
      await db.insert(projects).values({ deviceId: input.deviceId, path: input.path, title });
      return { duplicated: false as const };
    }),

  byId: publicQuery
    .input(z.object({ id: z.number() }))
    .query(async ({ input }) => {
      const [row] = await getDb().select().from(sessions).where(eq(sessions.id, input.id));
      if (!row) throw new Error("会话不存在");
      return { ...row, pendingApprovals: getPendingApprovals(row.id) };
    }),

  create: publicQuery
    .input(
      z.object({
        deviceId: z.number(),
        cwd: z.string().nullable(),
        title: z.string().optional(),
      }),
    )
    .mutation(async ({ input }) => {
      const db = getDb();
      const [{ id }] = await db
        .insert(sessions)
        .values({
          deviceId: input.deviceId,
          cwd: input.cwd,
          title: input.title || "新会话",
          provider: DEFAULT_MODEL.provider,
          model: DEFAULT_MODEL.model,
          effort: DEFAULT_MODEL.effort,
        })
        .$returningId();
      const [row] = await db.select().from(sessions).where(eq(sessions.id, id));
      return row;
    }),

  rename: publicQuery
    .input(z.object({ id: z.number(), title: z.string().min(1).max(80) }))
    .mutation(async ({ input }) => {
      await getDb()
        .update(sessions)
        .set({ title: input.title })
        .where(eq(sessions.id, input.id));
    }),

  archive: publicQuery
    .input(z.object({ id: z.number() }))
    .mutation(async ({ input }) => {
      await getDb()
        .update(sessions)
        .set({ archived: true, running: false })
        .where(eq(sessions.id, input.id));
    }),

  setModel: publicQuery
    .input(
      z.object({
        id: z.number(),
        provider: z.string(),
        model: z.string(),
        effort: z.string(),
      }),
    )
    .mutation(async ({ input }) => {
      await getDb()
        .update(sessions)
        .set({ provider: input.provider, model: input.model, effort: input.effort })
        .where(eq(sessions.id, input.id));
    }),

  // 历史消息：游标分页（滚动到顶部向上加载更早）
  messages: publicQuery
    .input(
      z.object({
        sessionId: z.number(),
        beforeSeq: z.number().nullish(),
        limit: z.number().min(1).max(100).default(30),
      }),
    )
    .query(async ({ input }) => {
      const db = getDb();
      const where = input.beforeSeq
        ? and(eq(messages.sessionId, input.sessionId), lt(messages.seq, input.beforeSeq))
        : eq(messages.sessionId, input.sessionId);
      const rows = await db
        .select()
        .from(messages)
        .where(where)
        .orderBy(desc(messages.seq))
        .limit(input.limit);
      return rows.reverse();
    }),

  send: publicQuery
    .input(
      z.object({
        sessionId: z.number(),
        text: z.string().min(1),
        images: z.array(z.string()).max(9).default([]),
      }),
    )
    .mutation(async ({ input }) => {
      const db = getDb();
      const [session] = await db.select().from(sessions).where(eq(sessions.id, input.sessionId));
      if (!session) throw new Error("会话不存在");
      if (session.running) throw new Error("当前会话正在生成中");
      const [maxRow] = await db
        .select({ max: sql<number | null>`max(seq)` })
        .from(messages)
        .where(eq(messages.sessionId, input.sessionId));
      const seq = (maxRow?.max ?? 0) + 1;
      const [{ id: userMsgId }] = await db
        .insert(messages)
        .values({
          sessionId: input.sessionId,
          role: "user",
          content: input.text,
          images: input.images.length ? JSON.stringify(input.images) : null,
          seq,
        })
        .$returningId();
      const [userMsg] = await db.select().from(messages).where(eq(messages.id, userMsgId));
      // 多端同步：用户消息也走事件流，其他端实时可见
      emit(input.sessionId, { type: "user_message", message: userMsg });
      // 首条消息自动生成标题
      if (session.title === "新会话") {
        const auto = input.text.replace(/\s+/g, " ").slice(0, 20);
        await db.update(sessions).set({ title: auto }).where(eq(sessions.id, input.sessionId));
      }
      await db
        .update(sessions)
        .set({ updatedAt: new Date() })
        .where(eq(sessions.id, input.sessionId));
      void startTurn(input.sessionId); // 异步执行 turn
      return { ok: true as const };
    }),

  stop: publicQuery
    .input(z.object({ sessionId: z.number() }))
    .mutation(({ input }) => ({ stopped: requestStop(input.sessionId) })),

  // 远程审批应答：原样回显 rpcId
  respond: publicQuery
    .input(z.object({ rpcId: z.string(), allow: z.boolean() }))
    .mutation(({ input }) => ({ ok: respondApproval(input.rpcId, input.allow) })),
});
