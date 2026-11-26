// WebUI 协议常量与 DTO（★ 2026-10-22 Web 服务与 WebUI 施工总案 U7 新建）。
// 单一真相 = 已提交的 ArkTS 件（entry/src/main/ets/common/web/），本文件每个常量都能在
// 服务端源码找到对应定义；改协议先改 ArkTS 再改这里，禁止前端自创字段。
// 对齐清单：
// · 鉴权   —— WebAuthValidator.parseWebAuthMessage / WsGateway.handleAuthMessage（auth / auth_failed / auth_required）
// · 心跳   —— WsGateway（服务端发 {"type":"ping"}，客户端必须回 {"type":"pong"}）
// · 读 API —— WebReadApi（api / api_result 与三个 method 名、错误码）
// · 写路由 —— WebHeadlessHost（send / stop / send_result；send_result 的 ok 语义 =
//              已投递或已入队，不是模型终态）
// · 直播   —— WebLivePump（live 信封五类 liveType + server_paused 独立控制信封）
// · 静态面 —— TcpHttpStaticCarrier（GET /__cfg → {"wsPort":8801}，SPA fallback index.html）

// ── 传输控制（WsGateway.ets）──
export const AUTH_TYPE = 'auth';
export const AUTH_FAILED_TYPE = 'auth_failed';
export const AUTH_REQUIRED_TYPE = 'auth_required';
export const PING_TYPE = 'ping';
export const PONG_TYPE = 'pong';
export const CLOSE_NOTICE_TYPE = 'close_notice';

// ── 读 API（WebReadApi.ets）──
export const API_TYPE = 'api';
export const API_RESULT_TYPE = 'api_result';
export const API_LIST_CONVERSATIONS = 'list_conversations';
export const API_READ_MESSAGES = 'read_messages';
export const API_ACTIVE_RUNS = 'active_runs';

// ── 写路由（WebHeadlessHost.ets）──
export const SEND_TYPE = 'send';
export const STOP_TYPE = 'stop';
export const SEND_RESULT_TYPE = 'send_result';

// ── 直播下行（WebLivePump.ets）──
export const LIVE_TYPE = 'live';
export const SERVER_PAUSED_TYPE = 'server_paused';
export const LIVE_SNAPSHOT = 'snapshot';
export const LIVE_ROUND_BEGIN = 'round_begin';
export const LIVE_ROUND_DELTA = 'round_delta';
export const LIVE_ROUND_END = 'round_end';
export const LIVE_CONV_INVALIDATE = 'conv_invalidate';

// ── 静态面（TcpHttpStaticCarrier.ets）──
// GET /__cfg → {"transport":"sse","wsPort":8801}（transport 是版本探针，wsPort 仅诊断）
export const CFG_PATH = '/__cfg';
// 传输面（transport.ts 单源，此处只留文档指针：下行 /events?cid=、上行 POST /api/msg?cid=）

// 会话列表单页（服务端上限 WEB_LIST_LIMIT_MAX = 500；V1 一次取足，列表分页不做）
export const LIST_LIMIT = 200;
// 历史消息单页（服务端 clampWebMsgLimit 缺省 50 / 上限 200）
export const MESSAGE_LIMIT = 50;

// DTO（字段与 WebReadApi.ets 的 WebConversationDto / WebMessageDto 逐字对齐）
export interface WebConversationDto {
  id: string;
  title: string;
  updatedAt: number;
  favorite: boolean;
}

export interface WebMessageDto {
  id: string;
  role: string; // user / assistant / thinking / tool / summary / clear / notice
  text: string;
  createdAt: number;
  truncated: boolean;
  toolName?: string;
  toolState?: string;
}

export interface WebListData {
  conversations: WebConversationDto[];
  total: number;
  offset: number;
  limit: number;
}

export interface WebHistoryData {
  conversationId: string;
  messages: WebMessageDto[];
  nextCursor: string;
}

export interface WebActiveRunsData {
  runs: string[];
}

export interface WebApiError {
  code: string;
  message: string;
}

export interface WebApiResult {
  type: string;
  reqId: string;
  ok: boolean;
  data?: unknown;
  error?: WebApiError;
}

export interface WebSendResult {
  type: string;
  reqId?: string;
  ok: boolean;
  error?: WebApiError;
}

// WebLivePump.WebLivePayload 逐字对齐（未用字段在服务端省略）
export interface LivePayload {
  text: string;
  reasoning: string;
  status: string;
  roundActive: boolean;
  messages?: WebMessageDto[];
  nextCursor?: string;
  historyOk?: boolean;
  activeRuns?: string[];
}

export interface LiveFrame {
  type: string;
  seq: number;
  conversationId: string;
  origin: string;
  liveType: string;
  payload: LivePayload;
}

// 服务端错误码 → 用户可读文案（代码分支可编程判别；文案只做展示）
export function apiErrorText(code: string, fallback: string): string {
  switch (code) {
    case 'bad_envelope':
      return '请求格式不正确，请刷新页面重试。';
    case 'unknown_method':
      return '手机服务不支持该请求，请升级手机应用。';
    case 'bad_params':
      return '请求参数不正确，请返回列表后重试。';
    case 'db_not_ready':
      return '手机数据库尚未就绪，请稍后重试。';
    case 'not_found':
      return '会话不存在或已被删除。';
    case 'not_readable':
      return '该会话为旧格式，网页端不可读取。';
    case 'empty_text':
      return '消息内容为空。';
    case 'no_connection':
      return '手机端没有可用的服务商配置。';
    case 'history_failed':
      return '手机端读取历史消息失败。';
    case 'send_rejected':
      return '发送被拒绝，请检查手机端的会话状态。';
    case 'too_many_sessions':
      return '网页端打开的会话过多，请返回列表后重试。';
    case 'internal':
      return '手机服务内部错误，请稍后重试。';
    default:
      return fallback;
  }
}

// round_end 四态（finishStream 入口语义）→ 展示文案
export function roundStatusText(status: string): string {
  switch (status) {
    case 'done':
      return '已完成';
    case 'error':
      return '生成失败';
    case 'stopped':
      return '已停止';
    case 'interrupted':
      return '已中断';
    default:
      return '';
  }
}
