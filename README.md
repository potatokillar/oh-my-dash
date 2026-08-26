# DSH — 手机端 AI 对话客户端（React + Node 全栈架构）

移动端优先的 AI 对话应用：设备管理、按 cwd 分组的项目列表、目录浏览器、多会话管理、
SSE 流式聊天（推理折叠 / 图片附件 / 停止 / 快捷指令）、模型与推理档位切换、远程工具审批，
以及明暗双主题（Claude 风格暖色系设计）。

## 技术栈

- **前端**：React 19 + TypeScript + Vite + Tailwind CSS + shadcn/ui（Radix）+ react-router v7
- **后端**：Hono + tRPC 11（端到端类型安全）
- **数据库**：MySQL + Drizzle ORM
- **实时**：SSE（EventSource）快照 + 增量事件推送，支持多客户端同步与断线重连

## 目录结构

```
api/          Hono + tRPC 服务端（设备、会话、浏览、SSE 流、模拟 Agent 引擎）
contracts/    前后端共享类型与常量（模型、Provider、错误码）
db/           Drizzle schema、relations、seed
src/          React 前端（pages / components / hooks / providers）
```

## 本地开发

```bash
cp .env.example .env   # 填入 DATABASE_URL 等配置
npm install
npm run db:push        # 同步数据库表结构
npx tsx db/seed.ts     # 可选：写入演示数据
npm run dev            # http://localhost:3000
```

## 生产构建

```bash
npm run build
npm start
```

或使用 Docker：

```bash
docker build -t dsh .
docker run -p 3000:3000 --env-file .env dsh
```

## 常用命令

| 命令 | 说明 |
| --- | --- |
| `npm run dev` | 开发服务器（HMR，端口 3000） |
| `npm run check` | TypeScript 类型检查 |
| `npm run test` | Vitest 测试 |
| `npm run db:push` | 开发期同步数据库 schema |
| `npm run db:generate` / `db:migrate` | 生产迁移 |

> 说明：仓库未提交 `package-lock.json`（体积原因），`npm install` 会自动生成；
> `.env` 含敏感凭证，已通过 `.gitignore` 排除，请按 `.env.example` 自行配置。
