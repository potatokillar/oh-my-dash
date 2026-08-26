import {
  mysqlTable,
  mysqlEnum,
  serial,
  bigint,
  varchar,
  mediumtext,
  boolean,
  int,
  timestamp,
  index,
} from "drizzle-orm/mysql-core";

// 设备 = 一台运行 dsh web 的主机（名称 + 地址）
export const devices = mysqlTable("devices", {
  id: serial("id").primaryKey(),
  name: varchar("name", { length: 255 }).notNull(),
  address: varchar("address", { length: 512 }).notNull(),
  // builtin = 内置演示主机（服务端模拟的 dsh web）；remote = 真实远程主机
  kind: mysqlEnum("kind", ["builtin", "remote"]).notNull().default("remote"),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
});

// 项目 = 注册的目录（可为空项目）；会话也按 cwd 自动聚合
export const projects = mysqlTable(
  "projects",
  {
    id: serial("id").primaryKey(),
    deviceId: bigint("deviceId", { mode: "number", unsigned: true }).notNull(),
    path: varchar("path", { length: 512 }).notNull(),
    title: varchar("title", { length: 255 }),
    createdAt: timestamp("createdAt").defaultNow().notNull(),
  },
  (t) => ({ deviceIdx: index("projects_device_idx").on(t.deviceId) }),
);

export const sessions = mysqlTable(
  "sessions",
  {
    id: serial("id").primaryKey(),
    deviceId: bigint("deviceId", { mode: "number", unsigned: true }).notNull(),
    title: varchar("title", { length: 255 }).notNull(),
    cwd: varchar("cwd", { length: 512 }),
    provider: varchar("provider", { length: 64 }).notNull(),
    model: varchar("model", { length: 128 }).notNull(),
    effort: varchar("effort", { length: 32 }).notNull().default("off"),
    archived: boolean("archived").notNull().default(false),
    running: boolean("running").notNull().default(false),
    createdAt: timestamp("createdAt").defaultNow().notNull(),
    updatedAt: timestamp("updatedAt").defaultNow().notNull(),
  },
  (t) => ({ deviceIdx: index("sessions_device_idx").on(t.deviceId) }),
);

export const messages = mysqlTable(
  "messages",
  {
    id: serial("id").primaryKey(),
    sessionId: bigint("sessionId", { mode: "number", unsigned: true }).notNull(),
    role: mysqlEnum("role", ["user", "assistant"]).notNull(),
    content: mediumtext("content").notNull(),
    reasoning: mediumtext("reasoning"),
    images: mediumtext("images"), // JSON string[]（dataURL）
    status: mysqlEnum("status", ["streaming", "done", "interrupted"])
      .notNull()
      .default("done"),
    seq: int("seq").notNull(),
    createdAt: timestamp("createdAt").defaultNow().notNull(),
  },
  (t) => ({ sessionIdx: index("messages_session_idx").on(t.sessionId, t.seq) }),
);

// 通过目录浏览器在演示主机上新建的目录
export const demoDirs = mysqlTable("demo_dirs", {
  id: serial("id").primaryKey(),
  path: varchar("path", { length: 512 }).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
});

export type Device = typeof devices.$inferSelect;
export type Project = typeof projects.$inferSelect;
export type Session = typeof sessions.$inferSelect;
export type Message = typeof messages.$inferSelect;
