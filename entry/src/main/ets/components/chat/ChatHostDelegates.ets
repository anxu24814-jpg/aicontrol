// 发送域宿主接口实现位域（自 ChatSendCtrl 域级拆出，宪法 1200 硬线债档兑现）。域定义：
// 工具轮 / Key 池 / 自动重试三接口的**薄直通与薄包装集中地**——方法体自 ChatSendCtrl 原样
// 搬迁（访问经 access 闭包集回接宿主态与组件引用），宿主只留 access 构造接线与重试域编排。
// 四域件构造实参由 ChatSendCtrl 换本件（构造参数类型本就是接口类型，域件文件零改动）。
// 为何不并入既有同域件：三接口实现位是「宿主态的访问器集合」，与任何单一域件职责都不同——
// 并入谁都会让谁既当域又当别人的宿主；access 闭包集是 ChatSendRefs「页面侧读写集」同款
// 姿势的自然延伸（箭头闭包持宿主延迟求值，构造序无碍）。
// 依赖方向（防循环）：本件**禁 import ChatSendCtrl**（宿主态一律经 access 到达）。
// 消费方：ChatToolRoundCtrl / ChatKeyRoundCtrl / ChatAutoRetryCtrl（本件 implements 回接；
// 原第四件 CubeEngineCtrl 已退役）。
// 流式面 = 「四只读 getter 闭包 + settlement 快照 + clearRoundAccumulation / bindLiveAssistant
// 两意图闭包」——写权限单源在 ChatStreamFlowCtrl（原四 setter 闭包随消费者清零退役）。
import { AiChatMessage, AiConnection, AiToolDef, ChatStream } from '../../common/providers/AiTypes';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage } from './ChatMessageCompose';
import { ChatToolRoundCtrl, ChatToolRoundHost,
  ToolEventRecord } from './ChatToolRoundCtrl';
import { ChatKeyRoundCtrl, ChatKeyRoundHost } from './ChatKeyRoundCtrl';
import { ChatAutoRetryHost } from './ChatAutoRetryCtrl';
import { StreamSettlement } from './ChatStreamFlowCtrl';
import { ChatUsageRoundCtrl } from './ChatUsageRoundCtrl';
import { ChatRetryCtrl } from './ChatRetryCtrl';
import { isAutoRetryEnabled as isAutoRetryPrefEnabled } from '../../common/AppPreferences';
import { AutoRetryCfg, resolveAutoRetryCfg } from '../../common/AppPreferencesRetry';
import { ToolExecutionContext } from '../../common/chat/MessageContracts';

// 宿主态访问集（宿主构造本件时以闭包集注入——箭头持宿主 this 延迟求值，域件引用在
// 宿主构造序中后于本件创建也不悬空：调用时刻恒已就位）
export interface ChatHostAccess {
  isDisposed: () => boolean;            // 宿主 disposed（销毁闸）
  isSending: () => boolean;             // refs.sending()（轮次在场闸）
  isDbReady: () => boolean;             // refs.dbReady()
  conversationId: () => string;         // refs.conversationId()
  toast: (message: string) => void;     // refs.toast
  dataSource: () => ChatDataSource;     // refs.dataSource
  maybeFollow: () => void;              // refs.follow.maybeFollow()
  // 流式累积态只读闭包（写面收敛为下方三个意图闭包，域外无字段形状可达）
  liveAssistantId: () => string;
  liveThinkingId: () => string;
  assistantFull: () => string;
  thinkingFull: () => string;
  // 流域意图面：结算快照一次取齐四值（工具轮 settleRoundAssistant 消费）+ 续轮两受控动作
  //——流域公开写面全集，各闭包语义单一
  settlement: () => StreamSettlement;
  clearRoundAccumulation: () => void;
  bindLiveAssistant: (id: string) => void;
  // 域件与节流引用（延迟求值）
  keyRound: () => ChatKeyRoundCtrl;
  toolRound: () => ChatToolRoundCtrl;
  retry: () => ChatRetryCtrl;
  usageRound: () => ChatUsageRoundCtrl;
  // 运行隔离面
  runToken: () => string;                     // 当前轮身份令牌（'' = 无活跃轮）
  nextAttempt: () => void;                    // attempt 换代（密钥轮换 / 自动重试）
  executionContext: () => ToolExecutionContext; // 本轮工具执行上下文快照
  // 工具结果附件缝（回接宿主附件缝域 ChatToolMediaCtrl 的通道）
  collectToolImage: (callId: string, mimeType: string, data: string) => boolean;
  toolResultMedia: () => boolean;
  // 图会话写侧（运行句柄与 revision 在宿主，域件经此单点发意图）
  isGraphMode: () => boolean;                 // 本轮 graph 形态（非 graph 含未装载 '' 恒 false）
  // 中间轮 assistant 节点提交（placeholderNodeId 非空走「更新既有占位行」收口路径）
  graphCommitRoundAssistant: (content: string, reasoning: string,
    stepIndex: number, stampTarget: ChatMessage | null,
    placeholderNodeId: string) => Promise<boolean>;
  graphCommitToolNode: (record: ToolEventRecord,
    stepIndex: number) => Promise<boolean>;   // 工具结果节点提交
  graphToolFactDispatch: (name: string, argsJson: string) => Promise<string>; // 意图事实
  graphToolFactConfirm: (factId: string, result: string, failed: boolean) => Promise<void>;
  // 其余宿主动作面
  refreshEstimate: (history: AiChatMessage[]) => void; // ctxCalc.refreshEstimate
  setActiveStream: (stream: ChatStream | null) => void; // 资源交接（宿主转调 flow.attachStream，不再字段写）
  throttleDrop: (frameId: string) => void;              // flow.throttle().drop（节流器域在 ChatStreamFlowCtrl）
  // 两个留宿主的接口方法回接口（实现体在 ChatStreamFlowCtrl，宿主薄委托转接，access 契约
  // 面零变化）
  failRound: (message: string, status: number) => void;       // 宿主失败呈报（紧邻分流段）
  createNativeStream: (conn: AiConnection) => ChatStream;     // 宿主原生流构造（回调直连流回调域）
}

// 三接口实现位集中地（自 ChatSendCtrl「宿主实现位」三段 + Key 池段整段迁入，方法体搬迁
// 零语义变化，唯一差异 = this.X 态访问改经 this.access.X 回接）
export class ChatHostDelegates implements ChatToolRoundHost, ChatKeyRoundHost,
  ChatAutoRetryHost {
  private access: ChatHostAccess;

  constructor(access: ChatHostAccess) {
    this.access = access;
  }

  // ── ChatToolRoundHost 实现位（isDisposed / isSending 与另两接口同名同义——单实现多满足）──

  isDisposed(): boolean {
    return this.access.isDisposed();
  }

  isSending(): boolean {
    return this.access.isSending();
  }

  isDbReady(): boolean {
    return this.access.isDbReady();
  }

  conversationId(): string {
    return this.access.conversationId();
  }

  toast(message: string): void {
    this.access.toast(message);
  }

  dataSource(): ChatDataSource {
    return this.access.dataSource();
  }

  maybeFollow(): void {
    this.access.maybeFollow();
  }

  getLiveAssistantId(): string {
    return this.access.liveAssistantId();
  }

  getLiveThinkingId(): string {
    return this.access.liveThinkingId();
  }

  getAssistantFull(): string {
    return this.access.assistantFull();
  }

  getThinkingFull(): string {
    return this.access.thinkingFull();
  }

  // 结算快照与续轮两受控动作（ChatToolRoundHost 消费——工具轮写面经这三个语义单一方法
  // 到达流域）
  settlement(): StreamSettlement {
    return this.access.settlement();
  }

  clearRoundAccumulation(): void {
    this.access.clearRoundAccumulation();
  }

  bindLiveAssistant(id: string): void {
    this.access.bindLiveAssistant(id);
  }

  roundHistoryRef(): AiChatMessage[] {
    return this.access.keyRound().currentHistory();
  }

  dropThrottle(frameId: string): void {
    this.access.throttleDrop(frameId);
  }

  // Key 池域续发咽喉点（双接口共用——工具轮续轮与自动重试到点同走此薄委托）
  attemptCurrent(): void {
    this.access.keyRound().attemptCurrent();
  }

  // ── ChatKeyRoundHost 实现位 ──

  // 起流前估算刷新（ctxCalc.refreshEstimate——k 校准分母侧与实际请求对齐）
  refreshEstimateFor(history: AiChatMessage[]): void {
    this.access.refreshEstimate(history);
  }

  // ── 运行隔离面实现位（三接口共用）──

  // 当前轮身份令牌（Key 池取钥回调核验面——V2）
  runToken(): string {
    return this.access.runToken();
  }

  // attempt 换代转发（tryNextKey 密钥轮换 / 自动重试到点两消费方）
  nextAttempt(): void {
    this.access.nextAttempt();
  }

  // 本轮工具执行上下文（工具轮 executeToolCall 与预检消费——四中转键退役后的值通道）
  executionContext(): ToolExecutionContext {
    return this.access.executionContext();
  }

  // ── 工具结果附件缝实现位（实现体在宿主附件缝域 ChatToolMediaCtrl）──

  collectToolImage(callId: string, mimeType: string, data: string): boolean {
    return this.access.collectToolImage(callId, mimeType, data);
  }

  toolResultMedia(): boolean {
    return this.access.toolResultMedia();
  }

  // ── 图会话写侧实现位（ChatToolRoundHost 消费）──

  isGraphMode(): boolean {
    return this.access.isGraphMode();
  }

  graphCommitRoundAssistant(content: string, reasoning: string,
    stepIndex: number, stampTarget: ChatMessage | null,
    placeholderNodeId: string): Promise<boolean> {
    return this.access.graphCommitRoundAssistant(content, reasoning, stepIndex, stampTarget,
      placeholderNodeId);
  }

  graphCommitToolNode(record: ToolEventRecord, stepIndex: number): Promise<boolean> {
    return this.access.graphCommitToolNode(record, stepIndex);
  }

  graphToolFactDispatch(name: string, argsJson: string): Promise<string> {
    return this.access.graphToolFactDispatch(name, argsJson);
  }

  graphToolFactConfirm(factId: string, result: string, failed: boolean): Promise<void> {
    return this.access.graphToolFactConfirm(factId, result, failed);
  }

  // 传输流构造（直连原生协议流工厂——cube 分流点已随退役笔删除）
  createStreamFor(conn: AiConnection): ChatStream {
    return this.access.createNativeStream(conn);
  }

  // 活跃流引用登记（Key 池起流/切换清引用，abort 停止键消费面在流回调域）。形参 =
  // ChatStream | null 与接口声明同形——Key 池传 null 清引用是正当调用，窄签名会让类型系统静音
  setActiveStream(stream: ChatStream | null): void {
    this.access.setActiveStream(stream);
  }

  // 本轮工具声明（Key 池起流随请求下发——toolRound.declarations 单源）
  toolDeclarations(): AiToolDef[] {
    return this.access.toolRound().declarations();
  }

  // 最终失败收尾——接口转接位（反碎片③豁免：接口归属 Key 池域、实现体在
  // ChatStreamFlowCtrl.failRound，宿主薄委托转接，链路零变化）
  failRound(message: string, status: number): void {
    this.access.failRound(message, status);
  }

  // ── ChatAutoRetryHost 实现位——共用实现不重落，本段只落三件 ──

  // 自动重试开关现读（单一来源 AppPreferences.isAutoRetryEnabled，别名导入防同名遮蔽；开关
  // 轮首现读一次、轮内锁定。总开关恒为旧布尔键单一真源——配置键只判参数不判开关）
  isAutoRetryEnabled(): boolean {
    return isAutoRetryPrefEnabled();
  }

  // 重试判据配置读口（域件首次接管经此取一次轮内锁定的快照——状态码集合 / 重试与停止
  // 词表 / 退避四参数；键未写 = 解析默认，写入自下一轮生效）
  autoRetryCfg(): AutoRetryCfg {
    return resolveAutoRetryCfg();
  }

  // 状态行写入（域件在「接管」与「让位」两点调用）：改当前占位气泡运行时字段，@Observed
  // 原地改即刷；消息不在（理论不可达）静默跳过，勿新建消息行（D7 红线）
  setRetryHint(text: string): void {
    const msg: ChatMessage | null = this.access.dataSource().findMessage(this.access.liveAssistantId());
    if (msg === null) {
      return;
    }
    msg.retryHint = text === '' ? undefined : text;
  }
}
