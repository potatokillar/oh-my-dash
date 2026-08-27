# dsh-oh-my-dash

Oh-My-Dash 手机客户端的 DeepSeek Harness 插件版：把 DSH 的会话、工具审批、目录浏览能力通过一个移动端 Web App 暴露出来，手机浏览器即可与 DSH Agent 对话。

## 架构

插件跑在 DSH(Cordis)进程内，通过 `ctx` 消费 DSH 服务，不自己造数据：

| 模块 | DSH 服务 |
|---|---|
| 设备/主机探活 | 本机即设备（插件在 DSH 进程内） |
| 会话列表/创建/发消息/停止 | `ctx.sessions` |
| 消息流（SSE） | `ctx.on('session/event')` |
| 远程审批 | `ctx.on('tools/pre-execute')` |
| 目录浏览 | `ctx.fs`（带工作区边界的安全读） |

前端复用 oh-my-dash 的 React App（浅色/深色双主题），build 后由插件静态托管。

## 安装

```bash
# 要求 @deepseek-ai/dsh >= 0.1.0-rc.6
dsh plugin --profile web add github:potatokillar/dsh-oh-my-dash
dsh web --profile web
# 手机访问 http://<主机IP>:<插件端口>/
```

## 开发

```bash
npm install
npm run build          # 编译 Host 端 → dist/
cd client && npm run build   # 构建前端 → client/dist/(待接入)
dsh plugin --profile web add .   # 本地验证
dsh --profile web --dump-config | grep oh-my-dash
```

## 配置（cordis.patch.yml)

- `port`:HTTP 服务端口，`0` 为随机可用端口
- `clientDir`：前端静态资源目录

## 与 Codex 配合

本插件与 `@deepseek-ai/dsh-subagent-codex` 并列，Codex 作为子代理由 DSH 主 Agent 调度，手机端可把「调用 Codex」做成快捷操作。

> 注意：DSH 处于 developer preview,`ctx.*` 服务接口可能有破坏性变更，升级前先 `--dump-config` 验证。
