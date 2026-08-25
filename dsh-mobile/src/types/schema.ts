// 数据模型（原演示后端为 drizzle/MySQL 表结构；App 化后为纯 TS 类型，
// 由 src/api 下的本地路由基于真实 dsh 协议 + localStorage 填充）

// 设备 = 一台运行 dsh web 的主机（名称 + 地址）
export interface Device {
  id: number;
  name: string;
  address: string;
  kind: "builtin" | "remote";
  createdAt: Date;
}

// 项目 = 注册的目录（可为空项目）；会话也按 cwd 自动聚合
export interface Project {
  id: number;
  deviceId: number;
  path: string;
  title: string | null;
  createdAt: Date;
}

export interface Session {
  id: number;
  deviceId: number;
  title: string;
  cwd: string | null;
  provider: string;
  model: string;
  effort: string;
  archived: boolean;
  running: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface Message {
  id: number;
  sessionId: number;
  role: "user" | "assistant";
  content: string;
  reasoning: string | null;
  images: string | null; // JSON string[]（dataURL）
  status: "streaming" | "done" | "interrupted";
  seq: number;
  createdAt: Date;
}
