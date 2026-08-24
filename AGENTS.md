# AGENTS.md

本仓库是围绕自托管 dsh（DeepSeek Harness）的远程访问工具链，包含：

- `dsh_mobile/` — Flutter Android 客户端（主产物）
- `dsh-remote-access/` — dsh profile 插件 bundle
- `dsh-client-probe/` — 协议验证脚本（零依赖 Node）

## 发布 APK 流程（每次出包必须执行）

1. **改版本号**：编辑 `dsh_mobile/pubspec.yaml` 的 `version: x.y.z+n`
   - 功能迭代：minor +1（如 1.1.0 → 1.2.0），build 号同步 +1
   - 纯修复/样式：patch +1，build 号 +1
   - build 号（+n）单调递增，永不复用（Android 用它判断升级）
2. 验证：`flutter analyze` 零错误、`flutter test` 全过
3. 构建：`flutter build apk --debug`
4. 分发（按手机连接状态二选一）：
   - USB 在线：`adb install -r dsh_mobile/build/app/outputs/flutter-apk/app-debug.apk`
   - USB 掉线：`cp dsh_mobile/build/app/outputs/flutter-apk/app-debug.apk /tmp/dsh-apk-share/dsh.apk`（tailnet 下载通道 `http://100.103.29.13:8080/dsh.apk`，需确认 python http.server 与 `tailscale serve --tcp=8080` 仍在运行）
5. 通知用户安装方式与版本号变化

## 调试回路

- Linux 桌面版：`flutter build linux --debug` 后 `DISPLAY=:1 build/linux/x64/debug/bundle/dsh_mobile`（CMake 缓存异常时 `rm -rf build/linux`）
- 截图：`DISPLAY=:1 xwd -root -silent | convert xwd:- /tmp/x.png`；模拟点击：`DISPLAY=:1 xdotool mousemove X Y click 1`
- Android 模拟器：`DISPLAY=:1 ~/Android/Sdk/emulator/emulator -avd dsh_dev -gpu auto -no-snapshot-save`（KVM 可用；模拟器内 App 可连真实 dsh）；模拟器截图 `adb exec-out screencap -p > x.png`
- 真实 dsh 服务：`http://127.0.0.1:3080`（不要对它做破坏性操作）

## 约束

- dsh_mobile 只允许 `shared_preferences` 与 `image_picker` 两个三方依赖；HTTP/WebSocket 用 dart:io；状态管理用 ChangeNotifier
- dsh 的 `!!js` patch 表达式只支持标量形态（用 `a.concat(b)`，不用 `[...a, ...b]`）
- 不要 git commit，除非用户明确要求
