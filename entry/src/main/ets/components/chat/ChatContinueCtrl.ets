// 继续生成编排域（DS 全家桶二期 S4 / #10）。
// 一句话职责 =「判定某条已收尾答案能否续写 → 起同一分支的新 run → 用例打回流式态 →
// 以已展示正文为前缀发一次 beta 续写请求（追加进原消息、usage 累加、账本两条）」。
// · 禁第二条请求链：起流咽喉点仍是 ChatKeyRoundCtrl.startRound（经 ChatRoundLauncher.
//   launchContinueRound 复用「记忆块 → 技能上下文 → 知识注入 → 复位 → 起流」同一条链），
//   本件只做判据、连接改写与历史末条前缀改写。
// · 追加不新建：节点提交目标由 ChatStreamFlowCtrl.beginContinueRound 登记的承载节点 id
//   指定（continueNodeId），收尾 UPDATE 同一 messageId；新 run 行保证账本 requestId 去重
//   不吞本轮消耗（费用两条）。
// · 只给 DS 官方 CC：官方 chat_prefix_completion 只承诺 OpenAI 兼容 + /beta；Responses
//   明确不支持 → canContinueOnConnection 判据挡死（不出键）。
// · 一次失败即隐藏：404/405/端点不存在 → markContinueUnsupported()（叶子件进程内标记），
//   键隐藏并提示；不做长期探测（任务书 §1-7②）。
import { AiChatMessage, AiConnection } from '../../common/providers/AiTypes';
import { isDsFlashConnection } from '../../common/providers/DsServerTools';
import {
  canContinueOnConnection, CONTINUE_UNSUPPORTED_TEXT, CONTINUE_UNREACHABLE_TEXT,
  dsContinueBaseUrlOf, isContinueUnsupported, isContinueUnsupportedError,
  markContinueUnsupported
} from '../../common/chat/ChatContinueSupport';
import { ChatMessage } from './ChatMessageCompose';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { ChatSendRefs } from './ChatSendCtrl';

// 宿主能力面（ChatSendCtrl 实现；全部薄直通/抽段方法，禁新造传输与组包）
export interface ChatContinueHost {
  isDisposed(): boolean;
  currentRunToken(): string;
  acquireRun(): boolean;
  releaseRunWithGuard(): void;
  routeState(): string;
  ensureGraphRoute(): Promise<void>;
  effectiveAssistantId(): string;
  // 起续写 run（不 fork：同一分支 + 目标节点作输入锚；false = 非末条/坏库）
  beginContinueRun(nodeId: string): Promise<boolean>;
  // 承载行回流式态（绑既有 messageId + 前缀正文 + 承载节点 id）
  beginContinueStreaming(msgId: string, prefixText: string, nodeId: string): void;
  // 同一请求链起流（ChatRoundLauncher.launchContinueRound）
  launchContinueRound(conn: AiConnection, roundToken: string, history: AiChatMessage[]): void;
}

// 续写历史末条改写（纯函数，断言直跑面）：去掉历史里的目标答案（末条 assistant），再以
// 「同正文 + prefix:true」的 assistant 作末条——官方硬要求最后一条消息是待续写的 assistant。
// 末尾不是 assistant 时（异常态）直接从原历史追加，不猜、不删用户消息
export function buildContinueHistory(history: AiChatMessage[], existingText: string): AiChatMessage[] {
  const next: AiChatMessage[] = history.slice();
  if (next.length > 0 && next[next.length - 1].role === 'assistant') {
    next.pop();
  }
  const prefixMessage: AiChatMessage = { role: 'assistant', content: existingText, prefix: true };
  next.push(prefixMessage);
  return next;
}

// 续写连接改写（纯函数）：baseUrl 换 beta 端点，其余字段原样（model/headers/keyPickMode
// 全不动——官方只要求 base_url 加 /beta）
export function dsContinueConnOf(conn: AiConnection): AiConnection {
  const next: AiConnection = {
    baseUrl: dsContinueBaseUrlOf(conn.baseUrl),
    model: conn.model,
    protocol: conn.protocol,
    endpoint: conn.endpoint,
    headers: conn.headers,
    providerId: conn.providerId
  };
  if (conn.promptCacheEnabled !== undefined) {
    next.promptCacheEnabled = conn.promptCacheEnabled;
  }
  if (conn.promptCacheTtl !== undefined) {
    next.promptCacheTtl = conn.promptCacheTtl;
  }
  if (conn.keyPickMode !== undefined) {
    next.keyPickMode = conn.keyPickMode;
  }
  if (conn.bodyOverrides !== undefined) {
    next.bodyOverrides = conn.bodyOverrides;
  }
  return next;
}

// 可续写判据（纯函数，UI 出键与点击双用）：官方 CC + 未用服务端工具 + 末条有正文 +
// 服务未被判定不支持。usedServerTools 由调用方从消息的 serverToolsJson 判
export function canContinueAnswer(conn: AiConnection | null, msg: ChatMessage,
  isTail: boolean): boolean {
  if (conn === null || !isDsFlashConnection(conn)) {
    return false;
  }
  if (!canContinueOnConnection(conn.protocol, conn.endpoint, conn.baseUrl)) {
    return false;
  }
  const usedTools: boolean = msg.serverToolsJson !== undefined && msg.serverToolsJson !== '';
  return isTail && !msg.streaming && msg.text.trim() !== '' && !usedTools &&
    !isContinueUnsupported();
}

export class ChatContinueCtrl {
  private refs: ChatSendRefs;
  private host: ChatContinueHost;

  constructor(refs: ChatSendRefs, host: ChatContinueHost) {
    this.refs = refs;
    this.host = host;
  }

  // 点击入口（行内图标键 → ChatPage → ChatSendCtrl.continueAt）：先过闸再起轮。
  // 闸序 = 发送态 → 连接能力 → 占用 → 路由 → 起 run → 回流式态 → 组装历史 → 起流
  continueAt(msgId: string): void {
    if (isContinueUnsupported()) {
      this.refs.toast(CONTINUE_UNSUPPORTED_TEXT);
      return;
    }
    if (this.refs.sending()) {
      this.refs.toast('请等待当前回复结束再继续生成');
      return;
    }
    const msg: ChatMessage | null = this.refs.dataSource.findMessage(msgId);
    if (msg === null || msg.kind !== 'assistant' || msg.text.trim() === '') {
      this.refs.toast(CONTINUE_UNSUPPORTED_TEXT);
      return;
    }
    const conn: AiConnection | null = this.refs.conn();
    if (conn === null || !canContinueOnConnection(conn.protocol, conn.endpoint, conn.baseUrl) ||
      !isDsFlashConnection(conn)) {
      this.refs.toast(CONTINUE_UNSUPPORTED_TEXT);
      return;
    }
    const usedTools: boolean = msg.serverToolsJson !== undefined && msg.serverToolsJson !== '';
    if (usedTools) {
      // 官方明示：用过联网工具的回复一律 400——提前拦，不发必错请求
      this.refs.toast('这条回答用过联网，不支持继续生成');
      return;
    }
    const nodeId: string = msg.nodeId !== undefined && msg.nodeId !== '' ? msg.nodeId : msg.id;
    if (!this.host.acquireRun()) {
      this.refs.toast('当前会话已有进行中的回复，请等待完成或先停止');
      return;
    }
    const roundToken: string = this.host.currentRunToken();
    this.refs.setSending(true);
    this.host.ensureGraphRoute()
      .catch((): void => undefined)
      .then((): void => {
        if (this.host.isDisposed() || roundToken === '' ||
          roundToken !== this.host.currentRunToken()) {
          return;
        }
        this.host.beginContinueRun(nodeId)
          .then((ok: boolean): void => {
            if (!ok) {
              this.refs.setSending(false);
              this.host.releaseRunWithGuard();
              this.refs.toast('这条回答不是最后一轮，暂不支持继续生成');
              return;
            }
            if (this.host.isDisposed() || roundToken !== this.host.currentRunToken()) {
              return;
            }
            this.startRound(conn, roundToken, msg, nodeId);
          })
          .catch((): void => {
            this.refs.setSending(false);
            this.host.releaseRunWithGuard();
            this.refs.toast(CONTINUE_UNSUPPORTED_TEXT);
          });
      });
  }

  private startRound(conn: AiConnection, roundToken: string, msg: ChatMessage,
    nodeId: string): void {
    // 承载行回流式态（同一 messageId；已展示正文作前缀初值）
    this.host.beginContinueStreaming(msg.id, msg.text, nodeId);
    this.refs.follow.forceToBottom();
    // 历史 = 当前视图（含本条答案）→ 末条改写为 prefix 版；连接换 beta 端点
    const baseHistory: AiChatMessage[] =
      buildRequestHistory(this.refs.dataSource.allMessages());
    const continueHistory: AiChatMessage[] = buildContinueHistory(baseHistory, msg.text);
    this.host.launchContinueRound(dsContinueConnOf(conn), roundToken, continueHistory);
  }
}
