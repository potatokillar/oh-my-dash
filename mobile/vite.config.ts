import path from "path"
const __dirname = import.meta.dirname
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      // 桌面浏览器调试回路：/dsh-proxy → 本机真实 dsh。
      // dsh /api 信任栅栏要求 Origin authority == Host，跨源一律 403；
      // 代理剥掉 Origin（栅栏对无 Origin 的 loopback 请求放行），changeOrigin 把
      // Host 改写为目标。仅 dev server 生效，不进生产包。
      // 设备地址填 localhost:3000/dsh-proxy 即可走代理。
      "/dsh-proxy": {
        target: "http://127.0.0.1:3080",
        changeOrigin: true,
        ws: true,
        rewrite: (p) => p.replace(/^\/dsh-proxy/, ""),
        configure: (proxy) => {
          const stripOrigin = (proxyReq: { removeHeader(name: string): void }) => {
            proxyReq.removeHeader("origin");
          };
          proxy.on("proxyReq", stripOrigin);
          proxy.on("proxyReqWs", stripOrigin);
        },
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@contracts": path.resolve(__dirname, "./contracts"),
      "@db": path.resolve(__dirname, "./src/types"),
    },
  },
  build: {
    outDir: path.resolve(__dirname, "dist"),
    emptyOutDir: true,
  },
});
