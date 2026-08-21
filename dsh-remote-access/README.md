# dsh-remote-access

让 [dsh](https://www.npmjs.com/package/@deepseek-ai/dsh)（DeepSeek Harness）的 web profile 更好地服务远程客户端（手机 App、其他设备浏览器）的插件 bundle。

## 功能

- **应用内目录选择器**：把 `directory-picker` 从桌面原生的 `-native` 后端换成应用内浏览的 `-browse` 后端。原生后端只能在主机桌面上弹对话框，远程客户端用不了；browse 后端让 `host.listDirectory` / `host.createDirectory` 对远程客户端可用（新建会话时选择工作目录的前提）。
- **额外信任主机**：提供 `remote-access` 配置行，声明式的向 `/api` 浏览器信任栅栏追加 authority（等效于启动时加 `--trusted-host`，但固化在配置里）。

## 安装

```sh
dsh plugin --profile web add dsh-remote-access        # npm（发布后）
dsh plugin --profile web add file:/path/to/dsh-remote-access  # 本地目录
dsh plugin --profile web remove dsh-remote-access     # 移除
```

安装命令会把本包追加进 profile 的 `dsh.profile.bundles`（要求包声明了 `dsh.bundle.patch`，本包已声明）。用 `dsh --profile web --dump-config` 可以确认组合结果。

## 配置

在 profile 的用户 patch 层（`~/.dsh/profiles/web/cordis.patch.yml`）声明远程访问用到的主机名/IP：

```yaml
- id: remote-access
  config:
    hosts: ['100.103.29.13']        # 或 'phone.example.com'、'nas.lan:3080'
```

每条必须是规范的 `host[:port]` 字面量（栅栏会做 WHATWG 规范化校验，写错会启动报错）。该文件被热重载，保存即生效。

## 网络打通（本插件范围之外）

dsh 的 webserver 只绑 `127.0.0.1`（`--host 0.0.0.0` 被官方有意禁用：web 端**没有认证层**，暴露到网络等于开放远程代码执行）。远程访问需要你自己选一种安全通道：

- **Tailscale（推荐）**：`tailscale serve --bg --tcp=3080 tcp://127.0.0.1:3080`，把服务只暴露给你的 tailnet；`hosts` 里填本机的 Tailscale IP。
- **认证反向代理**：caddy/nginx 在前面做 basic auth + TLS，并把 `Host` 改写为 `127.0.0.1:3080`（可同时通过信任栅栏和特权方法的 loopback 钉死）。
- **可信局域网**：profile patch 里把 webserver 行改为 `host: '0.0.0.0'`（栅栏会自动信任本机 LAN IP 字面量）。风险自负——同网段任何人可完全控制你的 agent。

## 注意

- 本插件**不提供认证**。信任栅栏是可达性策略，不是身份认证。需要认证请用上面的反代方案。
- 组合顺序：本 bundle 在 `dsh-base`/`dsh-web-app` 之后、profile 用户 patch 之前应用；用户层可以覆盖本插件的一切。
- 仅测试于 `@deepseek-ai/dsh` 0.1.0-rc.6；dsh 处于 rc 阶段，行 id 和 config 形态可能随版本变化，升级后请用 `--dump-config` 复核。
