# aicontrol WebUI

手机 Web 服务（设置 → Web 服务）的浏览器端。React 18 + Vite + TypeScript，依赖只保留
react / react-dom / markdown-it / highlight.js，观感自绘 CSS；所有数据经手机端的
WebSocket 协议（`entry/src/main/ets/common/web/` 为协议唯一真相），前端不含后端逻辑。

> ★ 冻结标注（2026-10-23）：本工程随 Web 伴生面冻结——不做专门同步与增强、禁重跑 ../scripts/build-web-ui.mjs 刷新产物（产物与 manifest 重打自洽，断言不拦，纯纪律）；冻结口径 = 项目 AGENTS.md「开发要求」节「Web 服务与 WebUI 伴生面冻结」条。

## 开发迭代

```bash
cd web-ui
npm install
# 手机 IP（HTTP 8800；WS 默认 +1）：
WEBUI_DEV_PHONE=192.168.1.23:8800 npm run dev
# 若 WS 端口单独改过：再加 WEBUI_DEV_WS_PORT=8801
```

Vite dev 代理把 `/__cfg` 转发到手机 `http://<ip>:8800`、`/ws` 转发到
`ws://<ip>:8801`——浏览器视角同源，免 CORS，改前端热更不重打包。

## 构建与产物

```bash
node ../scripts/build-web-ui.mjs
```

脚本 = `npm install`（node_modules 已在则跳过）→ `npm run build`（tsc 类型检查 + vite
build）→ 清空并拷贝到 `entry/src/main/resources/rawfile/webui/` → 写 `manifest.json`
（builtAt / 逐文件 sha256 / 总字节 / 源码指纹）→ 体积门禁（总产物 > 2MB 报错退出非零）。
产物随仓库提交（手机静态面直接托管 rawfile/webui）；`web-ui/dist` 与 `node_modules`
不入库。

## 协议要点

- 端口发现：`GET /__cfg` → `{"wsPort":8801}`。
- 鉴权：WS 首消息 `{"type":"auth","code":"六位口令"}`；成功无回执，失败收
  `auth_failed` / `auth_required` 后断连。口令只存 `sessionStorage`，不进 localStorage。
- 读：`api` / `api_result`，method = `list_conversations` / `read_messages` / `active_runs`。
- 写：`send` / `stop`，回执 `send_result`（ok = 已投递或已入队，不是模型终态）。
- 直播：`live` 信封（`round_begin` / `round_delta` / `round_end` / `conv_invalidate` /
  `snapshot`）；`round_delta.payload.text` 是当前轮全文，前端整段替换；`server_paused`
  为独立控制信封（手机退后台）。
- 心跳：回服务端 `{"type":"ping"}` 以 `{"type":"pong"}`。

## 路由与托管

`/` = 会话列表，`/c/:id` = 聊天面（history 模式）。手机静态面（TcpHttpStaticCarrier）
对未命中路径回落 `index.html`；`index.html` 的 `<base href="/">` 让 `./assets` 引用在
深链下仍锚回站点根。
