import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  // 沿用 Flutter 版 applicationId：同机 debug 签名一致，可无缝覆盖安装
  appId: "com.example.dshmobile.dsh_mobile",
  appName: "Oh-My-Dash",
  webDir: "dist",
  server: {
    // 页面以 http://localhost 提供，避免 https 页面调 http:// 设备被混合内容拦截
    androidScheme: "http",
  },
  plugins: {
    CapacitorHttp: {
      // dsh 的 /api 信任栅栏要求 Origin == Host（跨源浏览器请求一律 403），
      // 一元 RPC 必须走原生网络层（无 Origin/Sec-Fetch 头）
      enabled: true,
    },
  },
};

export default config;
