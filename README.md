# oh-my-dash

围绕自托管 [dsh](https://www.npmjs.com/package/@deepseek-ai/dsh)（DeepSeek Harness）的远程访问工具链：手机 App、服务器插件、协议验证脚本。

## 组成

- **`dsh_mobile/`** — Flutter Android 客户端：多设备管理（设备 → 项目/会话 → 对话）、项目（workspace）列表、服务器端目录浏览、远程审批（允许一次/拒绝）、实时事件流同步（手机发的消息 PC 浏览器可见，反之亦然）。
- **`dsh-remote-access/`** — dsh profile 插件 bundle：为远程客户端挂载应用内目录选择器（browse 后端），并以声明式配置向 `/api` 信任栅栏追加主机。安装：`dsh plugin --profile web add file:./dsh-remote-access`。
- **`dsh-client-probe/`** — 零依赖 Node 协议验证脚本（`probe.mjs` 全链路、`sync-test.mjs` 双端同步），也是第三方客户端的参考实现。

## 部署要点

dsh web 默认只绑 `127.0.0.1` 且无认证层，远程访问请走安全通道（推荐 Tailscale：`tailscale serve --bg --tcp=3080 tcp://127.0.0.1:3080`），详见 `dsh-remote-access/README.md`。

## 协议

客户端与 dsh host 的通信是 JSON-RPC over HTTP（`POST /api/<method>`）加两条 WebSocket 下行流（`/api/events.mux`、`/api/events.host`），无鉴权、Host 头信任栅栏。方法全表见 dsh 包内 `dsh-host-apiproxy/lib/types/api/rpc-map.d.ts`。
