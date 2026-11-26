// WebUI 客户端状态面（★ 2026-10-22 WebUI U7 新建）：连接状态快照、直播轮形态与
// 消息合并纯函数。与 client.ts 的传输/协议编排分开——本文件零 socket、零 React，
// 只做「服务端帧 → 界面可消费状态」的纯映射，便于独立演算与后续单测。
import { apiErrorText } from './protocol';
import type { WebConversationDto, WebMessageDto } from './protocol';

// 口令存储键（sessionStorage；只在当前标签页存活）
const CODE_STORAGE_KEY = 'aicontrol.webui.code';

export type ClientPhase =
  | 'connecting'  // 正在解析 /__cfg 并建立 socket
  | 'authing'     // socket 已开，首消息 auth 已发，等首个业务响应
  | 'ready'       // 已鉴权且读写通道可用
  | 'paused'      // 手机退后台，服务端广播 server_paused 后断连
  | 'reconnecting' // 非暂停原因断线，指数退避重连中
  | 'disconnected'; // 鉴权失败等终态，等待用户重新输口令

export interface LiveRound {
  text: string;
  reasoning: string;
  active: boolean;
  status: string;
  origin: string;
  updatedAt: number;
}

export interface ClientState {
  phase: ClientPhase;
  hasCode: boolean;
  authError: string;
  connectionError: string;
  reconnectAttempt: number;
  reconnectInSec: number;
  serverPaused: boolean;
  conversations: WebConversationDto[];
  conversationsLoading: boolean;
  conversationsError: string;
  activeRuns: string[];
  conversationId: string;
  messages: WebMessageDto[];
  nextCursor: string;
  messagesLoading: boolean;
  loadingEarlier: boolean;
  messagesError: string;
  historyOk: boolean;
  live: LiveRound | null;
  pendingUsers: WebMessageDto[];
}

export const INITIAL_STATE: ClientState = {
  phase: 'connecting',
  hasCode: false,
  authError: '',
  connectionError: '',
  reconnectAttempt: 0,
  reconnectInSec: 0,
  serverPaused: false,
  conversations: [],
  conversationsLoading: false,
  conversationsError: '',
  activeRuns: [],
  conversationId: '',
  messages: [],
  nextCursor: '',
  messagesLoading: false,
  loadingEarlier: false,
  messagesError: '',
  historyOk: true,
  live: null,
  pendingUsers: [],
};

export interface PendingCall<T> {
  resolve: (value: T) => void;
  reject: (error: Error) => void;
  timer: number;
}

export class ApiError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

// 读消息三种用途：首开 / 终态回读 / 向上翻页
export type RefreshMode = 'initial' | 'refresh' | 'earlier';

export function readStoredCode(): string {
  try {
    return window.sessionStorage.getItem(CODE_STORAGE_KEY) || '';
  } catch {
    return '';
  }
}

export function storeCode(code: string): void {
  try {
    if (code === '') {
      window.sessionStorage.removeItem(CODE_STORAGE_KEY);
    } else {
      window.sessionStorage.setItem(CODE_STORAGE_KEY, code);
    }
  } catch {
    // 私密模式等禁用存储：退化为内存态（本会话仍可用）
  }
}

export function dedupeMessages(messages: WebMessageDto[]): WebMessageDto[] {
  const seen = new Set<string>();
  const out: WebMessageDto[] = [];
  for (const message of messages) {
    if (seen.has(message.id)) {
      continue;
    }
    seen.add(message.id);
    out.push(message);
  }
  return out;
}

// 直播回显去重：250ms 落库 checkpoint 会把半截 assistant / thinking 行带进历史读结果，
// 而同一段正文又在 live 帧里（全文）。整段替换模型下按「历史行是 live 全文的前缀」剥离。
// ★ 2026-10-22 自检修：只剥**最后一条**——checkpoint 回显必然是序列末行，而原实现全表
// filter 会把历史里任何一条「恰为 live 全文前缀」的旧回答一并吞掉（上一轮的「好的」对上
// 当前轮的「好的，我来…」），表现为历史回答凭空消失。取舍：同一次落库若把思考与正文投成
// 两行（think-<id> + <id>），末行是正文，思考行会暂留一帧与 live.reasoning 重复——宁可
// 重复观感，不可删历史内容。
function stripLiveEcho(messages: WebMessageDto[], live: LiveRound): WebMessageDto[] {
  const out = messages.slice();
  const last = out.length - 1;
  if (last < 0) {
    return out;
  }
  const message = out[last];
  const echoAssistant = message.role === 'assistant' && live.text !== ''
    && (message.text === live.text
      || (message.text !== '' && live.text.startsWith(message.text)));
  const echoThinking = message.role === 'thinking' && live.reasoning !== ''
    && (message.text === live.reasoning
      || (message.text !== '' && live.reasoning.startsWith(message.text)));
  if (echoAssistant || echoThinking) {
    out.splice(last, 1);
  }
  return out;
}

export interface ReconcileResult {
  messages: WebMessageDto[];
  live: LiveRound | null;
}

// 历史读结果与当前直播轮合流：
// · 落库态已含终答全文 → 丢弃 live 气泡（否则重复一条）；
// · 否则剥离 checkpoint 回显，保留 live（全文更权威）。
export function reconcileHistory(raw: WebMessageDto[], live: LiveRound | null): ReconcileResult {
  if (live === null) {
    return { messages: raw, live: null };
  }
  if (!live.active && live.text !== '') {
    for (const message of raw) {
      if (message.role === 'assistant' && message.text === live.text) {
        return { messages: raw, live: null };
      }
    }
  }
  return { messages: stripLiveEcho(raw, live), live };
}

export function errorText(error: unknown, fallback: string): string {
  if (error instanceof ApiError) {
    return apiErrorText(error.code, error.message || fallback);
  }
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return fallback;
}
