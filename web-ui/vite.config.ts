import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// 产物托管形态 = 手机 rawfile/webui（TcpHttpStaticCarrier 静态面，根路径 '/'）。
// base './' 让 index.html 的资产引用保持相对；index.html 里的 <base href="/"> 把相对引用
// 锚回站点根——history 路由 /c/:id 由静态面 SPA fallback 回 index.html 时资产仍可解析。
// dev 代理：/__cfg、/events（SSE 长连）、/api（上行 POST）→ 手机 8800——三者同源同端口，
// 浏览器视角零 CORS。★ 2026-10-22 SSE 备胎笔：/ws（8801）代理随 WS 动态面退役一并拆除。
const phone = process.env.WEBUI_DEV_PHONE || '127.0.0.1:8800';
const httpOrigin = phone.startsWith('http') ? phone.replace(/\/$/, '') : `http://${phone}`;

export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    target: 'es2020',
    sourcemap: false,
    chunkSizeWarningLimit: 1600,
  },
  server: {
    host: true,
    proxy: {
      '/__cfg': {
        target: httpOrigin,
        changeOrigin: true,
      },
      // SSE 长连：代理必须关闭缓冲（vite 默认透传，这里显式写出便于排障）
      '/events': {
        target: httpOrigin,
        changeOrigin: true,
      },
      '/api': {
        target: httpOrigin,
        changeOrigin: true,
      },
    },
  },
});
