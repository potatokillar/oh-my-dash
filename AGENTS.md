# AGENTS.md

本仓库是围绕自托管 dsh（DeepSeek Harness）的远程访问工具链，包含：

- `dsh-mobile/` — React + Capacitor Android 客户端（主产物，UI 为 React 重写版）
- `dsh-remote-access/` — dsh profile 插件 bundle（含 `scripts/` 协议验证脚本，零依赖 Node）

## dsh-mobile 架构要点

- UI：`src/pages/` + `src/components/`（React 19 + Vite + Tailwind + shadcn/ui），页面不直接碰网络
- 数据层：页面全部走 `trpc.*` hooks（@trpc/react-query），但**没有服务器**——`src/providers/trpc.tsx` 用自定义 link 直调 `src/api/` 下的本地路由（`createCallerFactory`，零 HTTP，无 transformer，Date 原生透传）
- 本地路由（`src/api/`）的数据源 = 真实 dsh 协议客户端（`src/lib/dsh/`：一元 RPC `POST /api/<method>` + WebSocket `/api/events.mux`，协议类型以 dsh 包内 `dsh-host-apiproxy/lib/types/api/*.d.ts` 为准，`dsh-remote-access/scripts/` 可验证链路）+ localStorage（设备列表、本地数值 sessionId ↔ 远端 sessionId 映射、已注册项目）
- 路由用 HashRouter（Capacitor 本地静态服务不支持 history 回退）
- 设备均为 tailnet 内网 http:// 明文，AndroidManifest 已开 `usesCleartextTraffic`，勿关
- **App 内网络必须全走原生层**：dsh `/api` 信任栅栏要求浏览器请求 `Origin == Host` 且拒绝 `Sec-Fetch-Site: cross-site`（HTTP 与 WS upgrade 同规则），跨源浏览器请求一律 403。因此一元 RPC 靠 `CapacitorHttp` 原生桥（capacitor.config.ts 已启用），`/api/events.mux` 下行靠自研 Kotlin 插件 `DshWsPlugin`（OkHttp，见 `android/app/.../DshWsPlugin.kt` + `src/lib/dsh/nativeWs.ts`）；浏览器 dev 环境用 vite 代理绕行（见下调试回路）

## 发布 APK 流程（每次出包必须执行）

1. **改版本号**：同步改两处
   - `dsh-mobile/package.json` 的 `version`（功能迭代 minor +1，纯修复/样式 patch +1）
   - `dsh-mobile/android/app/build.gradle` 的 `versionName`（同 package.json）与 `versionCode`（+1，单调递增，永不复用，Android 用它判断升级）
2. 验证：`npm run check`（tsc）零错误、`npm run lint` 无新增错误（存量错误见 FEATURES.md §9）、`npm run build` 成功
3. 构建：`cd dsh-mobile && npx cap sync android && cd android && JAVA_HOME=$PWD/../.jdk/jdk-21.0.12.1+1 ./gradlew assembleDebug`
   - **Capacitor 8 要求 JDK 21**（系统 JDK 17 不够）；便携版 Temurin 21 在 `dsh-mobile/.jdk/`（已 gitignore，重新获取：`curl -L https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse | tar -xz`）
   - 产物：`dsh-mobile/android/app/build/outputs/apk/debug/app-debug.apk`
   - applicationId `com.example.dshmobile.dsh_mobile` 沿用自旧版客户端，同机 debug 签名一致可直接覆盖安装
4. 分发（按手机连接状态二选一）：
   - USB 在线：`adb install -r dsh-mobile/android/app/build/outputs/apk/debug/app-debug.apk`
   - USB 掉线：`cp dsh-mobile/android/app/build/outputs/apk/debug/app-debug.apk /tmp/dsh-apk-share/dsh.apk`（tailnet 下载通道 `http://100.103.29.13:8080/dsh.apk`，需确认 python http.server 与 `tailscale serve --tcp=8080` 仍在运行）
5. 通知用户安装方式与版本号变化

## 调试回路

- 浏览器预览：`cd dsh-mobile && npm run dev`（:3000）；dev server 内置 `/dsh-proxy` 代理到本机真实 dsh（剥 Origin、支持 WS），App 里添加设备地址填 `localhost:3000/dsh-proxy` 即可在桌面浏览器里连真实 dsh 调试。改代码后 `npx cap sync android` 才会进 APK
- Android 模拟器（可选）：`DISPLAY=:1 ~/Android/Sdk/emulator/emulator -avd dsh_dev -gpu swiftshader_indirect -no-snapshot-save`；模拟器内设备地址填 `10.0.2.2:3080`（已加入 dsh 信任主机）
- WebView 远程调试：模拟器/手机装上 app 后，桌面 Chrome 开 `chrome://inspect`
- 真实 dsh 服务：`http://127.0.0.1:3080`（不要对它做破坏性操作）

## 约束

- dsh-mobile 不改 `src/pages/` 与 `src/components/` 的 UI 代码（用户的手写成果）；网络/状态逻辑只出现在 `src/api/`、`src/lib/`、`src/providers/`、`src/hooks/`
- 不新增运行时依赖需先确认必要性；浏览器环境禁止 node 专属 API
- dsh 的 `!!js` patch 表达式只支持标量形态（用 `a.concat(b)`，不用 `[...a, ...b]`）
- 不要 git commit，除非用户明确要求
