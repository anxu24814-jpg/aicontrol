// 工具调用轮编排域（2026-09-08 自 ChatSendCtrl 域级最小拆分——A1 前置，依据优化建议档
// docs/优化建议-Cube吸收层-20260903.md C2：ChatSendCtrl 入 800~1200 软引导区后，下次实质
// 改动先拆其中边界最清晰的工具轮域）。域定义 = 轮开启（beginToolRound：本轮 assistant
// 收尾落库 + 历史追加）/ 调用执行（executeToolCalls → runRegistered）/ 续轮
//（startNextAssistantRound）+ 轮次态（roundTools / toolAccumulator / toolStep /
// roundReasoningItems）与展示辅助（prettyJson / compactPreview / detectErrorResult）。
// ★ 阶段一零行为变化：方法体自 ChatSendCtrl 逐字搬迁（唯一改写 = 宿主内部状态/引擎域
// 直引收敛为 ChatToolRoundHost 接口方法），宿主经接口回接；★ 阶段二 A1 并行化已落地
//（2026-09-08）：executeToolCalls 分流——ask_user 参与的轮整轮串行（防交互卡并发），其余
// 非交互工具一轮内 Promise.all 并发、按调用原序上屏与收集回传（详见 runToolCallsParallel
// 头注释与 docs/任务书-A1-工具调用并行-20260907.md）。
// 宿主接口由 ChatSendCtrl implements——本文件禁 import ChatSendCtrl（防循环依赖），
// 宿主内部状态全部经接口薄直通访问。
import { AiChatMessage, AiReasoningItem, AiToolCall, AiToolDef } from '../../common/providers/AiTypes';
import { TOOL_STEP_LIMIT_DEFAULT } from '../../common/providers/ToolLimits';
import { ToolCallAccumulator, ToolEntry, TOOL_ASK_USER, clipToolResult,
  executeToolCall, toolRegistry, toolRuntime } from '../../common/providers/ToolTypes';
import { browseActDeniedResult } from '../../common/providers/ToolBrowseAct';
import { CONFIRM_LEVEL_IRREVERSIBLE, ConfirmPrompt } from '../../common/providers/ToolContracts';
import { SseToolDelta } from '../../common/providers/SseParser';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { finalizeMessage, insertMessage, MessageRow,
  nextMessageId, nextRowCreatedAt } from '../../common/store/ChatDb';
import { nextRowSeq } from '../../common/store/MessageSeqDb';
import { finalizeMessageVariant } from '../../common/store/MessageVariantDb';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';

// 触顶让位轮的回传结果（A2，2026-09-09；优化建议档 A2「到顶让模型知情」）：到顶时被丢弃
// 的调用不再静默吞——每个调用以此 JSON 作为 role='tool' 结果回传模型（error 键与工具错误
// 回传同形制），让模型知情并基于已有信息收尾，治「直接收尾 → 最后一轮正文空串 → 空气泡」。
// 文案带上限值（2026-09-09 上限可设置：值随助手配置变化，故由常量改为函数生成）
function limitReachedResult(limit: number): string {
  return JSON.stringify({
    error: '工具调用已达 ' + limit + ' 轮上限，本次调用未执行。请基于已有信息直接回答，不要再调用工具'
  });
}

// 工具卡落库行 content JSON 载荷（role='tool' 行单一真源——回放/历史重建双消费）
export interface ToolEventRecord {
  toolCallId: string;
  name: string;
  argsJson: string;
  result: string;
  isError: boolean;
}

// 宿主接口：工具轮域引用的宿主内部状态/引擎域收敛于此（ChatSendCtrl implements，
// 实现位集中一节——全部薄直通，语义零变化）
export interface ChatToolRoundHost {
  // 通用闸与页面桥（全部薄直通 refs/成员）
  isDisposed(): boolean;            // this.disposed
  isSending(): boolean;             // this.refs.sending()
  isPrivateMode(): boolean;         // this.refs.privateMode()
  isDbReady(): boolean;             // this.refs.dbReady()
  conversationId(): string;         // this.refs.conversationId()
  toast(message: string): void;     // this.refs.toast
  dataSource(): ChatDataSource;     // this.refs.dataSource
  maybeFollow(): void;              // this.refs.follow.maybeFollow()
  // 流式累积态（宿主持有；getter 取 get/set 前缀——与宿主私有成员同名冲突规避）
  getLiveAssistantId(): string;  setLiveAssistantId(id: string): void;
  getLiveThinkingId(): string;   setLiveThinkingId(id: string): void;
  getAssistantFull(): string;    setAssistantFull(value: string): void;
  getThinkingFull(): string;     setThinkingFull(value: string): void;
  roundHistoryRef(): AiChatMessage[];   // 本轮请求历史（返回活引用，push 即生效）
  // 引擎域与节流
  dropThrottle(frameId: string): void;       // 薄包装 this.throttle().drop(frameId)
  settleCubeFlushers(flush: boolean): void;  // 宿主既有方法放宽可见性，签名不变
  // 薄包装 = 三频道重建 + 揭示指针清零（startNextAssistantRound 轮开三行动作整体收敛——
  // 揭示指针属宿主动效态，不为两个纯数值指针单开接口方法）
  rebuildCubeFlushers(): void;
  // Key 池域续发
  attemptCurrent(): void;                    // 宿主既有方法放宽可见性，签名不变
  // ── 多版本（DB v36，2026-09-20 消息重新生成）──
  // 工具轮中间收尾的版本载荷取用：msgId = 重试目标行且重试轮版本态在堂 → 半截版并入
  // 数组并返回组装好的 {variants, active}（settleRoundAssistant 据此走 finalizeMessageVariant
  // 五列落库——旧答案保在 variants[0] 不被中间收尾覆盖丢失，撤链待决①的工具轮实锤路径）；
  // null = 该行不带版本（普通发送轮 / 工具轮续行），settle 侧走原 finalizeMessage 三列落库
  takeVariantPayloadFor(msgId: string, content: string,
    reasoning: string): MessageVariantPayload | null;
}

// 多版本落库载荷（同上笔）：variants = 全量 JSON 串（已含刚并入的本轮半截版）、active =
// 选中下标（= 新并入版——content 投影与选中版恒同步的投影设计）、count = 版本总数
//（内存投影 variantCount 直接取用，免 settle 侧再解析一遍 JSON）
export interface MessageVariantPayload {
  variants: string;
  active: number;
  count: number;
}

export class ChatToolRoundCtrl {
  private host: ChatToolRoundHost;
  private roundTools: AiToolDef[] = []; // 本轮工具声明（[] = 不带 tools 字段零回归）
  private toolAccumulator: ToolCallAccumulator = new ToolCallAccumulator(); // 流式聚合器
  private toolStep: number = 0; // 已执行的调用轮数（本轮 stepLimit 闸）
  // 本轮工具调用轮数上限（生效值；发送轮首由 resetForNewSend 第二参写入——来源 = 归属
  // 助手 toolStepLimit 列的换算结果，0 = 不限制已换算为内置硬顶 256；'' 无助手 = 默认 32）
  private stepLimit: number = TOOL_STEP_LIMIT_DEFAULT;
  // 本流 reasoning item 捕获（2026-09-06 Responses 修复）：OpenAI 官方端点 include 开启时
  // 流中 output_item.added/done(type='reasoning') 携带 encrypted_content——同 id 后到覆盖
  // 先到（done 终值）；beginToolRound 随 assistant 行挂 roundHistory 回传（官方 stateless
  // 工具轮保真要求），startNextAssistantRound/finishStream 清。非官方端点恒空数组零参与
  private roundReasoningItems: AiReasoningItem[] = [];
  // 触顶让位轮标记（A2，2026-09-09）：每次发送只给一次——让位轮后模型若仍发调用，走原
  // 触顶路径（直接收尾），防「让位」变成无限续轮扣费
  private limitGraceUsed: boolean = false;
  // 轮次纪元（★ 2026-09-09 工具层自检修复）：每次 resetForNewSend（发送轮首 + finishStream
  // 收尾）自增。工具执行是长时异步（联网工具 5~20s），期间用户「停止 → 立刻发新消息」时
  // 旧 lane 回调里的 isSending() 守卫会误判为「本轮仍在发送」（新轮已把 sending 翻真）——
  // 旧结果被写进新轮历史、落孤儿 role='tool' 行、并多起一个流。lane 捕获发起时纪元，
  // 回调与总守卫比对：纪元不符 = 过期轮次，一律作废（卡片补已中止，不落库不续轮）
  private roundGen: number = 0;

  constructor(host: ChatToolRoundHost) {
    this.host = host;
  }

  // ── 接线公共面（ChatSendCtrl 消费；阶段一只此最小集）──

  // 发送重置（dispatchSend 轮首传本轮声明与上限 / finishStream 收尾传 []）——原宿主四行
  // 重置收拢；limit 省略 = 默认 32（收尾路径无工具轮，值不参与判定）
  resetForNewSend(tools: AiToolDef[], limit: number = TOOL_STEP_LIMIT_DEFAULT): void {
    this.roundTools = tools;
    this.stepLimit = limit;
    this.roundGen++; // 轮次纪元推进（在途 lane 全部作废，见 roundGen 注释）
    this.toolAccumulator = new ToolCallAccumulator();
    this.toolStep = 0;
    this.roundReasoningItems = [];
    this.limitGraceUsed = false;
  }

  // 工具调用增量喂聚合器（onStreamDelta；无工具帧宿主侧已短路零开销）——流式增量形
  // SseToolDelta（快照后才归一为 AiToolCall，同 accumulator.feed 契约）
  feedToolCalls(calls: SseToolDelta[]): void {
    this.toolAccumulator.feed(calls);
  }

  // reasoning item 捕获（onStreamDelta）：同 id 后到覆盖（done 终值盖 added）
  captureReasoningItems(items: AiReasoningItem[]): void {
    for (const ri of items) {
      const existed: number = this.roundReasoningItems.findIndex(
        (r: AiReasoningItem): boolean => r.id === ri.id);
      if (existed >= 0) {
        this.roundReasoningItems[existed] = ri;
      } else {
        this.roundReasoningItems.push(ri);
      }
    }
  }

  // 聚合器快照（onStreamDone 判定）
  pendingCalls(): AiToolCall[] {
    return this.toolAccumulator.snapshot();
  }

  // 本轮带工具声明（onStreamDone 判定——无声明不进工具轮）
  hasDeclarations(): boolean {
    return this.roundTools.length > 0;
  }

  // 本轮工具声明只读出口（attemptCurrent 发请求带 tools 字段——失败切换/续轮每轮同声明）
  declarations(): AiToolDef[] {
    return this.roundTools;
  }

  // 轮次预算未到顶（onStreamDone 判定——本轮 stepLimit 闸，值 = 助手级上限）
  hasBudget(): boolean {
    return this.toolStep < this.stepLimit;
  }

  // 本轮生效上限（ChatSendCtrl 触顶 notice 文案用——提示里的数字与实际闸门同源，
  // 防「改了助手上限但提示仍写 32」的漂移）
  roundLimit(): number {
    return this.stepLimit;
  }

  // 触顶让位轮可用（A2，2026-09-09）：每次发送只给一次——让位轮后模型仍发调用则走原
  // 触顶路径（直接收尾），防「让位」变成无限续轮
  canGrantLimitGrace(): boolean {
    return !this.limitGraceUsed;
  }

  // ── 工具调用轮（2026-09-02 建域；2026-09-08 自 ChatSendCtrl 逐字迁入）──

  // 轮开启：本轮 assistant 正文/思考收尾（settleRoundAssistant——UI 全量覆盖 + 落库 done
  // + 历史追加 assistant 带 toolCalls 与 reasoning 快照）→ 逐个执行工具。
  // 语义：一次用户发送 = N 轮 assistant 行（每轮一行）+ 工具卡行（role='tool' 落库），
  // 与既有 finishStream 单轮收尾互不复用
  beginToolRound(calls: AiToolCall[]): void {
    // 轮次预算扣减（★ 2026-09-03 自检修复：原实现只比对不自增，toolStep 恒 0 =
    // 轮数闸门形同虚设——模型工具死循环将无限续轮扣费直到手动停止）
    this.toolStep++;
    this.settleRoundAssistant(calls);
    this.executeToolCalls(calls);
  }

  // 触顶让位轮（A2，2026-09-09）：到顶后的收尾轮不静默丢弃调用——本轮 assistant 正常收尾
  // 入历史（带 toolCalls），每个被丢弃的调用补一条合成的 error 工具结果
  //（limitReachedResult，文案带上限值）再开新一轮，让模型自己组织收尾话术（治空气泡）。
  // toolStep 不自增（未执行任何调用，「已执行的调用轮数」语义不变）；让位只给一次
  //（canGrantLimitGrace——让位轮后模型仍发调用则走原触顶路径直接收尾，防无限续轮扣费）
  grantLimitGrace(calls: AiToolCall[]): void {
    this.limitGraceUsed = true;
    this.settleRoundAssistant(calls);
    for (const call of calls) {
      const resultMsg: AiChatMessage = { role: 'tool', content: limitReachedResult(this.stepLimit),
        toolCallId: call.id, toolName: call.name };
      this.host.roundHistoryRef().push(resultMsg);
    }
    this.startNextAssistantRound();
  }

  // 本轮 assistant 收尾（beginToolRound 与 grantLimitGrace 共用；方法体自 beginToolRound
  // 原样提取，语义零变化）：UI 全量覆盖 + 落库 done + 历史追加（带 toolCalls 与 reasoning 快照）
  private settleRoundAssistant(calls: AiToolCall[]): void {
    // 局部快照命名 assistantMsgId（2026-09-04 观察项改名）：这是流式 assistant 气泡的
    // 消息 id，非助手归属 id——宿主文件 assistantId 一名只留给助手归属语义（setBoundOverride
    // 参数 / 落库绑定列），防误读（自检曾把落库守卫误读成归属列守卫）
    const assistantMsgId: string = this.host.getLiveAssistantId();
    const thinkingId: string = this.host.getLiveThinkingId();
    const content: string = this.host.getAssistantFull();
    const reasoning: string = this.host.getThinkingFull();
    // 实验态本轮收尾：吐完剩余揭示再全量覆盖（与 finishStream 同序；随后新一轮重建三频道）
    this.host.settleCubeFlushers(true);
    this.host.dropThrottle(assistantMsgId);
    if (thinkingId !== '') {
      this.host.dropThrottle(thinkingId);
      const thinkingMsg: ChatMessage | null = this.host.dataSource().findMessage(thinkingId);
      if (thinkingMsg !== null) {
        thinkingMsg.text = reasoning;
        // 思考行收口（2026-09-16 三态收口）：本轮流已收尾落库 = 该思考块已完成——折叠态
        // 收拢为 0（下一轮若再产 reasoning 由懒创建另建新行，见 ChatSendCtrl.onStreamDelta）
        thinkingMsg.streaming = false;
      }
    }
    const assistantMsg: ChatMessage | null = this.host.dataSource().findMessage(assistantMsgId);
    if (assistantMsg !== null) {
      assistantMsg.text = content;
      // 中间行底栏收口（2026-09-14 消息气泡底栏）：本轮正文已收尾落库 = 「已结束的助手
      // 消息」，置假出底栏（拍板 2a 按消息判——该行自身流式已毕；整轮仍在续行中，但重试
      // 键不现：随后的工具卡 push 与下一轮占位 push 都会清 tail）。任务书 §2.1-⑤ 预期
      // 「中间行保持 streaming=true 直到整轮收尾」实查不成立——中间行不经 finishStream，
      // 不置假则永远无底栏，违背拍板 2a；落点选本收口法（与落库 done 同点，状态同源）
      assistantMsg.streaming = false;
    }
    // 工具轮 assistant 收尾行落库——隐私会话旁路（2026-09-04）。★ 2026-09-20 多版本
    //（DB v36）：重试轮**承载行**的中间收尾带版本落库（半截版并入推进列、content 投影 =
    // 半截、旧答案保在 variants[0]——不带版本会把旧答案覆盖丢失；★ 同日真机修复笔：承载行
    // 无工具轮形态 = 重试目标行、工具轮形态 = 新建承载行，终态收尾以 baseVariants + 终版
    // 覆盖本行的保底，半截版不入最终版本列表）；普通轮/后续中间轮回 null 走原三列落库
    //（该路径行非承载行，无切换键在身）
    if (!this.host.isPrivateMode() && assistantMsgId !== '' && this.host.isDbReady()) {
      const variantPayload: MessageVariantPayload | null =
        this.host.takeVariantPayloadFor(assistantMsgId, content, reasoning);
      if (variantPayload !== null) {
        finalizeMessageVariant(assistantMsgId, content, reasoning, 'done',
          variantPayload.variants, variantPayload.active)
          .catch((e: Object): void => {
            this.host.toast('消息落库失败：' + (e as Error).message);
          });
        if (assistantMsg !== null) {
          assistantMsg.variantCount = variantPayload.count;
          assistantMsg.variantActive = variantPayload.active;
        }
      } else {
        finalizeMessage(assistantMsgId, content, reasoning, 'done')
          .catch((e: Object): void => {
            this.host.toast('消息落库失败：' + (e as Error).message);
          });
      }
    }
    const assistantReq: AiChatMessage = { role: 'assistant', content: content };
    if (reasoning !== '') {
      assistantReq.reasoning = reasoning;
    }
    // reasoning item 回传料挂载（2026-09-06 Responses 修复）：本流捕获的官方端点保真项
    // 随工具轮 assistant 行入历史（compose 在 function_call 前回传 type:'reasoning' item）
    if (this.roundReasoningItems.length > 0) {
      assistantReq.reasoningItems = this.roundReasoningItems.slice();
    }
    assistantReq.toolCalls = calls;
    this.host.roundHistoryRef().push(assistantReq);
  }

  // 分流入口（2026-09-08 A1 并行化）：ask_user 参与的轮整轮串行，其余并发执行。
  // ★ ask 轮整轮串行的设计定案（防交互卡并发）：ask 卡渲染条件 = toolState === 'running'
  // && toolName === TOOL_ASK_USER（ChatMessageItem）——卡上屏即渲染可作答交互区，不存在
  // 「先占位后激活」形态；而 toolRuntime.resolveAsk 对不在挂起集的 callId 静默吞（防误触
  // 语义）——提前上屏的第二张 ask 卡用户可作答但答案必丢。且 ask 等待主体是人类作答
  //（秒级~分钟级），混轮并发的人体感知增益 ≈ 0。「ask 串行 + 其余并发」终极形态须给渲染
  // 域加新状态位（跨域改动），另立任务书不做
  // ★ 2026-09-18 P2 B 单元（确认卡）：高危 browse_act 同走串行——等待主体同为人类，卡上屏
  // 即渲染「允许一次/拒绝」双键，提前上屏无益（同 ask 理由）；★ 2026-09-19 HTTP 请求工具笔
  // 确认链注册表化泛化：预检不再硬编码 browse_act——逐调用查注册表 preflight（browse_act
  // 异步精判 / http_request 写方法判定，统一走 await），返回非 null（说明串＋档位二元组）
  // 即收集入串行路（★ 2026-09-20 审批卡视觉迁移笔 A：形态自「串（'' = 直通）」改 ConfirmPrompt
  // | null，档位随行供卡面徽章用）
  private async executeToolCalls(calls: AiToolCall[]): Promise<void> {
    const hasAsk: boolean = calls.some((c: AiToolCall): boolean => c.name === TOOL_ASK_USER);
    const confirmPrompts: Map<string, ConfirmPrompt> = new Map<string, ConfirmPrompt>();
    const gen: number = this.roundGen; // 预检前采样（循环后复核，见下方纪元守卫）
    for (const call of calls) {
      const pf: ((argsJson: string) => Promise<ConfirmPrompt | null>) | undefined =
        toolRegistry.get(call.name)?.preflight;
      if (pf === undefined) {
        continue;
      }
      const prompt: ConfirmPrompt | null = await pf(call.argsJson);
      if (prompt !== null) {
        confirmPrompts.set(call.id, prompt);
      }
    }
    // 纪元复核加固（2026-09-19 HTTP 请求工具笔）：预检 await 窗口内经历「停止 → 立即发新
    // 消息」时，旧轮 calls 不得入新轮执行（roundGen 已推进 / sending 已翻真）；此刻卡尚未
    // 推上屏，直接 return 无残留（roundGen 判据见字段注释）。★ 2026-09-19 自检 P2-2 修复：
    // 补 isDisposed 判据与 lane/总守卫对齐——离页 disposeSilent 只置 disposed、不翻 sending
    // 不动 roundGen，预检窗口内退页旧轮工具会在已销毁页面上启动执行（browse_act 经排队与
    // 语义抓取构成真实宏任务窗口，暴露面真实存在；纯 http_request 轮预检为微任务级插不进，
    // 由 httpAbortAll 与 lane 守卫兜底）
    if (this.host.isDisposed() || gen !== this.roundGen || !this.host.isSending()) {
      return;
    }
    if (hasAsk || confirmPrompts.size > 0) {
      this.runToolCallsSerial(calls, confirmPrompts);
    } else {
      this.runToolCallsParallel(calls);
    }
  }

  // 串行执行本轮工具调用（ask 轮 / 高危确认轮专用路径——原 A1 前的全轮串行体原样更名，
  // 行为逐字节不变，与 2026-09-05 十卡真机验收形态完全一致）→ 全部完成后开新一轮
  private runToolCallsSerial(calls: AiToolCall[],
    confirmPrompts: Map<string, ConfirmPrompt>): void {
    const gen: number = this.roundGen; // 本轮纪元（过期轮次作废，见 roundGen 注释）
    const runOne = (index: number): void => {
      if (index >= calls.length) {
        this.startNextAssistantRound();
        return;
      }
      const call: AiToolCall = calls[index];
      const record: ToolEventRecord = {
        toolCallId: call.id, name: call.name, argsJson: call.argsJson,
        result: '', isError: false
      };
      // 工具卡（running）上屏：插在当前流末（正文之后）
      const cardId: string = nextMessageId('tool');
      const card: ChatMessage = newChatMessage(cardId, 'tool', '', call.name, 'running');
      card.toolCallId = call.id;
      card.toolInputJson = prettyJson(call.argsJson);
      card.toolInputText = compactPreview(call.argsJson, 40);
      // 高危确认等待标记（P2 B 单元；2026-09-20 笔 A 起二元组）：置位后 ChatToolCard 渲染
      // 确认卡（双键作答）——text 入主因句、level 入档位徽章与风险块判据
      // ★ 2026-09-20 笔 C：会话级白名单命中（仅写操作档）时不置标记——confirmPrompt 就地置
      // undefined（下游 run 分发据此直走注册表执行器，不再挂确认桥——不置判据而只跳过标记
      // 会让分发仍去挂桥等一个永不到来的作答），并当场补批准戳（见 sessionAllowHit 注释）
      const promptRaw: ConfirmPrompt | undefined = confirmPrompts.get(call.id);
      const bypassBySession: boolean = promptRaw !== undefined &&
        this.sessionAllowHit(promptRaw, call.name);
      const confirmPrompt: ConfirmPrompt | undefined = bypassBySession ? undefined : promptRaw;
      if (confirmPrompt !== undefined) {
        card.toolConfirmLevel = confirmPrompt.level;
        card.toolConfirmText = confirmPrompt.text;
      } else if (bypassBySession) {
        this.grantApproval(call);
      }
      this.host.dataSource().push(card);
      this.host.maybeFollow();
      // 执行：ask_user 挂交互桥（等用户作答），高危 browse_act 挂确认桥（等用户放行），
      // 其余走注册表执行器。
      // ★ 2026-09-03 自检修复：调用名不在本轮声明集（模型幻觉调用——如会话联网开关剔除
      // search_web 后模型仍调用）不执行，error JSON 回传模型自纠——「未声明即不执行」与
      // 请求体声明面一致，注册表认识不算数
      const declared: boolean =
        this.roundTools.some((t: AiToolDef): boolean => t.name === call.name);
      const run: Promise<string> = !declared ?
        Promise.resolve(JSON.stringify({ error: `工具 ${call.name} 未在本轮启用` })) :
        (call.name === TOOL_ASK_USER ?
          toolRuntime.waitAsk(call.id) :
          (confirmPrompt !== undefined ?
            this.awaitBrowseConfirm(call, cardId) :
            this.runRegistered(call.name, call.argsJson)));
      run.then((raw: string): void => {
        if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
          // 等答/执行间隙停止或销毁——不再落卡不再续轮（ask 已被 cancelAll 续跑过，此处吞）；
          // 卡片补终态防 running 幽灵（★ 2026-09-03 自检修复：原实现直接 return，停止后
          // 工具卡永久停在 running 且不落库——UI 有卡 DB 无行，重进会话凭空消失）。
          // ★ 2026-09-09 工具层自检修复：加纪元守卫——停止后立刻发新消息时 isSending()
          // 已翻真（新轮进行中），旧 lane 会把过期结果写进新轮历史 + 落孤儿行 + 多起一
          // 个流（详见 roundGen 字段注释）
          const stale: ChatMessage | null = this.host.dataSource().findMessage(cardId);
          if (stale !== null) {
            stale.toolState = 'error';
            stale.toolDisplayText = '已中止';
            // 确认等待中途停止/销毁：清确认标记（cancelAllPending 已以 false 续跑本链，
            // 此处只防残留说明串随消息对象留档）。★ 2026-09-20 审批卡视觉迁移笔 A：照旧
            // 只清 text 不写 result——该卡自然回退普通工具卡（中止轮的既定表现，勿改）
            stale.toolConfirmText = '';
          }
          return;
        }
        record.result = clipToolResult(raw);
        record.isError = detectErrorResult(record.result);
        // 卡片态更新（@Observed 原地改字段——流式渲染同机制）
        const doneCard: ChatMessage | null = this.host.dataSource().findMessage(cardId);
        if (doneCard !== null) {
          doneCard.toolState = record.isError ? 'error' : 'done';
          doneCard.toolOutputJson = prettyJson(record.result);
          doneCard.toolDisplayText = compactPreview(record.result, 60);
          if (record.isError) {
            doneCard.text = compactPreview(record.result, 60);
          }
        }
        // role='tool' 行落库（回放单一真源）——隐私会话旁路（2026-09-04）；落库失败
        // toast 不静默（不阻断对话链）
        if (!this.host.isPrivateMode() && this.host.isDbReady()) {
          const convId: string = this.host.conversationId();
          const row: MessageRow = {
            id: cardId, conversationId: convId, role: 'tool',
            content: JSON.stringify(record), reasoning: '', status: 'done',
            createdAt: nextRowCreatedAt(), // 单调分配器（防同毫秒并列——回放乱序修复笔）
            // seq 与 createdAt 同址铸造（★ 2026-09-21 消息存储机制改造笔 2 D1 红线：行对象
            // 构造当场取号，禁 await 后补铸；串行 lane 逐调用依次铸造 = 卡序即号序）
            seq: nextRowSeq(convId)
          };
          insertMessage(row)
            .catch((e: Object): void => {
              this.host.toast('工具记录入库失败：' + (e as Error).message);
            });
        }
        // 结果回传历史（四协议方言翻译在 compose 层）
        const resultMsg: AiChatMessage = { role: 'tool', content: record.result,
          toolCallId: call.id, toolName: call.name };
        this.host.roundHistoryRef().push(resultMsg);
        runOne(index + 1);
      });
    };
    runOne(0);
  }

  // 并行执行本轮非交互工具调用（2026-09-08 A1——OpenAI Function Calling parallel_tool_calls
  // 默认语义：模型可一次发多个调用，调用方并发执行后按原序回传；双 search_web 对比式提问
  // 2×20s 超时预算 → ≈1×20s）。三段式：
  // ① 同步 for 按调用序建 record 槽 + push 工具卡 running + 起执行 Promise——全部 push 在
  //    同一同步循环内完成 = 卡序恒等于调用序（上屏序红线，渲染序零风险）；
  // ② 每条 lane 完成回调：停止/销毁守卫（命中补「已中止」终态防幽灵卡，同串行防线）→
  //    槽写 result/isError → 该卡终态原地更新（各自完成即更，并发下进度可感知）。lane 不
  //    加 catch——执行器契约恒 resolve（ToolTypes.executeToolCall 内部 try/catch 包装错误
  //    JSON，Promise.all 不会被执行器拒绝击穿）；
  // ③ Promise.all 统一收尾：一次性总守卫 → 按调用序落库 role='tool' 行 + 历史按序 push
  //    → startNextAssistantRound。
  // 语义不变项：轮数上限按轮计（beginToolRound 每轮 ++ 一次，上限值 = 本轮 stepLimit）/
  // 未声明守卫 / clipToolResult 截断 / detectErrorResult 探测 / 隐私会话旁路 / key 失败切换
  //（attemptCurrent 续发）/ 停止与销毁守卫（逐 lane + 总守卫）/ 单调用轮走此路径本质同构
  //（不特判回串行）
  private runToolCallsParallel(calls: AiToolCall[]): void {
    const startedAt: number = Date.now();
    const gen: number = this.roundGen; // 本轮纪元（过期轮次作废，见 roundGen 注释）
    const slots: ToolEventRecord[] = [];
    const cardIds: string[] = [];
    const lanes: Promise<void>[] = [];
    for (const call of calls) {
      const record: ToolEventRecord = {
        toolCallId: call.id, name: call.name, argsJson: call.argsJson,
        result: '', isError: false
      };
      // 工具卡（running）上屏：插在当前流末（正文之后）——同步循环保调用序
      const cardId: string = nextMessageId('tool');
      const card: ChatMessage = newChatMessage(cardId, 'tool', '', call.name, 'running');
      card.toolCallId = call.id;
      card.toolInputJson = prettyJson(call.argsJson);
      card.toolInputText = compactPreview(call.argsJson, 40);
      this.host.dataSource().push(card);
      this.host.maybeFollow();
      slots.push(record);
      cardIds.push(cardId);
      // 未声明守卫（模型幻觉调用——「未声明即不执行」，error JSON 回传模型自纠；语义同串行）
      const declared: boolean =
        this.roundTools.some((t: AiToolDef): boolean => t.name === call.name);
      const run: Promise<string> = !declared ?
        Promise.resolve(JSON.stringify({ error: `工具 ${call.name} 未在本轮启用` })) :
        this.runRegistered(call.name, call.argsJson);
      lanes.push(run.then((raw: string): void => {
        if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
          // 等答/执行间隙停止或销毁——该卡补终态防 running 幽灵（同串行防线）；
          // 落库与续轮交由下方 Promise.all 收尾总守卫拦。★ 2026-09-09 工具层自检修复：
          // 加纪元守卫（停止后立刻发新消息时 isSending() 已翻真——旧 lane 不得写新轮）
          const stale: ChatMessage | null = this.host.dataSource().findMessage(cardId);
          if (stale !== null) {
            stale.toolState = 'error';
            stale.toolDisplayText = '已中止';
          }
          return;
        }
        record.result = clipToolResult(raw);
        record.isError = detectErrorResult(record.result);
        // 卡片终态各自完成即更（@Observed 原地改字段——并发下进度可感知）
        const doneCard: ChatMessage | null = this.host.dataSource().findMessage(cardId);
        if (doneCard !== null) {
          doneCard.toolState = record.isError ? 'error' : 'done';
          doneCard.toolOutputJson = prettyJson(record.result);
          doneCard.toolDisplayText = compactPreview(record.result, 60);
          if (record.isError) {
            doneCard.text = compactPreview(record.result, 60);
          }
        }
      }));
    }
    Promise.all(lanes).then((): void => {
      // 总守卫：全部完成后停止/销毁/轮次已换纪元——不落库不续轮（各卡幽灵防线已在 lane 内补过）
      if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
        return;
      }
      // 按调用序统一收尾：role='tool' 行落库（回放单一真源）——隐私会话旁路（2026-09-04）；
      // createdAt 走单调分配器（2026-09-19 乱序修复笔：原「同毫秒多行按调用序落库」只保证
      // 工具行彼此递增，与下一轮占位行同拍取时仍并列——分配器全链严格递增，回放序彻底稳定）
      for (let i = 0; i < calls.length; i++) {
        const record: ToolEventRecord = slots[i];
        if (!this.host.isPrivateMode() && this.host.isDbReady()) {
          const convId: string = this.host.conversationId();
          const row: MessageRow = {
            id: cardIds[i], conversationId: convId, role: 'tool',
            content: JSON.stringify(record), reasoning: '', status: 'done',
            createdAt: nextRowCreatedAt(),
            // seq 与 createdAt 同址铸造（笔 2 D1 红线同串行点）：本同步 for 按调用序连铸，
            // 与卡序同序——物理插入完成序（Promise.all 后逐行 insert）不参与号序
            seq: nextRowSeq(convId)
          };
          insertMessage(row)
            .catch((e: Object): void => {
              this.host.toast('工具记录入库失败：' + (e as Error).message);
            });
        }
        // 结果回传历史（四协议方言翻译在 compose 层）
        const resultMsg: AiChatMessage = { role: 'tool', content: record.result,
          toolCallId: calls[i].id, toolName: calls[i].name };
        this.host.roundHistoryRef().push(resultMsg);
      }
      // 真机验收证据面（BLOCKED 半托并发项引用；串行路径零新增打点）
      hilog.info(0x0001, 'ChatSend', '工具并行：%{public}d 个调用并发完成，耗时 %{public}d ms',
        calls.length, Date.now() - startedAt);
      this.startNextAssistantRound();
    });
  }

  // 注册表执行入口（未知函数名 = 注册表与声明脱节——error JSON 回传模型自纠不炸轮）
  private runRegistered(name: string, argsJson: string): Promise<string> {
    const entry: ToolEntry | undefined = toolRegistry.get(name);
    if (entry === undefined) {
      return Promise.resolve(JSON.stringify({ error: '未知工具：' + name }));
    }
    return executeToolCall(entry, argsJson);
  }

  // 确认链等待（2026-09-18 P2 B 单元立；2026-09-19 HTTP 请求工具笔
  // 泛化）：挂确认桥等用户作答 → 允许则经注册表 onApproved 授予（browse_act 写单次批准戳；
  // convId 在**用户作答那一刻**经宿主取当前会话快照，桥内不自读 AppStorage——负向钉守；时序
  // 近窗口亚秒级）后执行；拒绝则回拒绝文案（终态，模型不得重试）。★ 2026-09-20 审批卡
  // 视觉迁移笔 A：作答后**不再清空 toolConfirmText**（回执行的体首主因句仍读它），改为写
  // toolConfirmResult（'approved' / 'rejected'）——确认区随之转回执行中态或回执态（原地
  // 改字段即刷新；等待态判据 = text 非空且 result 未写，见 ChatToolCard.confirmAwaiting）。
  // ★ 允许分支的授予动作按 call.name 查注册表分发——http_request 等无
  // onApproved 工具允许即直执行（批准戳是 browse_act 专属凭据，不跨工具）
  // ★ 2026-09-20 笔 C（会话级允许）：作答痕迹扩三值——卡上另写 toolConfirmSessionAllow
  // 表示用户按的是「本会话内允许」，本链据此把 result 映射 'session' 并授予会话级免询问
  //（仅写操作档、仅本会话、仅本工具；不可逆档不出第三键，见 sessionAllowHit）
  private awaitBrowseConfirm(call: AiToolCall, cardId: string): Promise<string> {
    return toolRuntime.waitBrowseConfirm(call.id).then((approved: boolean): Promise<string> => {
      const card: ChatMessage | null = this.host.dataSource().findMessage(cardId);
      const sessionPicked: boolean = card !== null && card.toolConfirmSessionAllow === true;
      if (card !== null) {
        // 作答痕迹（笔 A 立、笔 C 扩三值）：'session' = 用户按的「本会话内允许」
        card.toolConfirmResult = approved ?
          (sessionPicked ? 'session' : 'approved') : 'rejected';
      }
      if (approved && sessionPicked) {
        // 会话级授予（唯一写点）：键 = 本会话快照 id + 工具名
        toolRuntime.grantSessionAllow(this.host.conversationId(), call.name);
      }
      if (!approved) {
        return Promise.resolve(browseActDeniedResult());
      }
      this.grantApproval(call);
      return this.runRegistered(call.name, call.argsJson);
    });
  }

  // 会话级免询问判据（笔 C §2.4）：**仅写操作档** + 白名单命中才免询问——不可逆档恒照旧弹卡
  //（用户在写操作卡上点的「本会话内允许」只授权他当时看见的那类动作；删除类动作永远单独问，
  // 与「不可逆档不出第三键」同一条立意）。会话 id 经宿主快照取（负向钉：链内零全局中转键字样，
  // assert-app-domain 125 组同守）
  private sessionAllowHit(prompt: ConfirmPrompt, toolName: string): boolean {
    return prompt.level !== CONFIRM_LEVEL_IRREVERSIBLE &&
      toolRuntime.isSessionAllowed(this.host.conversationId(), toolName);
  }

  // 批准授予单源（onApproved 分发；两处共调 = 用户在卡上允许 + 会话级免询问——本方法把
  // 「获准 ⇒ 经注册表授予」这条规则收成一处，禁各写一份）。browse_act 凭戳执行（单次消费 +
  // 60s TTL + 会话一致）；http_request 等无 onApproved 工具此调用为空操作
  private grantApproval(call: AiToolCall): void {
    toolRegistry.get(call.name)?.onApproved?.(this.host.conversationId());
  }

  // 新一轮 assistant 占位（历史已含全部调用与结果）：重置累积态 → 新占位行上屏+落库 →
  // 同 key 位续发（不重轮转——失败切换语义只在 key 级失败时推进）
  private startNextAssistantRound(): void {
    if (this.host.isDisposed() || !this.host.isSending()) {
      return;
    }
    this.toolAccumulator = new ToolCallAccumulator();
    this.roundReasoningItems = [];
    this.host.setAssistantFull('');
    this.host.setThinkingFull('');
    this.host.setLiveThinkingId('');
    // 实验态新一轮：三频道重建（TypewriterFlusher reset 后不可复用）+ 揭示指针清零
    this.host.rebuildCubeFlushers();
    // 占位行 createdAt 走单调分配器（2026-09-19 乱序修复笔）：恒严格晚于本工具轮全部
    // 工具行——原同拍 Date.now() 同毫秒并列是「工具卡回放到最新消息后」根因
    const rowCreatedAt: number = nextRowCreatedAt();
    const assistantMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
    // 流式运行时标记（2026-09-14 消息底栏，照 dispatchSend 占位同款）：新一轮开始 = 本行
    // 底栏不现，收口由本类 settleRoundAssistant（中间轮）或宿主 finishStream（最终轮）置假
    assistantMsg.streaming = true;
    this.host.dataSource().push(assistantMsg);
    this.host.setLiveAssistantId(assistantMsg.id);
    // 占位行落库——隐私会话旁路（2026-09-04）
    if (!this.host.isPrivateMode()) {
      const convId: string = this.host.conversationId();
      const assistantRow: MessageRow = {
        id: assistantMsg.id, conversationId: convId, role: 'assistant',
        content: '', reasoning: '', status: 'streaming', createdAt: rowCreatedAt,
        // seq 与 createdAt 同址铸造（★ 笔 2 D1 红线）：本行号恒 > 本工具轮全部工具行（上面
        // 的同步 for 连铸在前），续轮占位恒为会话末条号——回放序与号序同向
        seq: nextRowSeq(convId)
      };
      // 内存行同址回填库序号（理由全文 = ChatMessage.rowSeq 字段注释）
      assistantMsg.rowSeq = assistantRow.seq;
      insertMessage(assistantRow)
        .catch((e: Object): void => {
          this.host.toast('消息入库失败：' + (e as Error).message);
        });
    }
    this.host.attemptCurrent();
  }
}

// JSON 串美化（工具卡展开区展示用；坏 JSON 原样返回——展示兜底不炸）
function prettyJson(json: string): string {
  try {
    return JSON.stringify(JSON.parse(json), null, 2);
  } catch (e) {
    return json;
  }
}

// 单行紧凑预览（工具卡摘要行；空白压一空格 + 超长截断）
function compactPreview(json: string, maxChars: number): string {
  const line: string = json.replace(/\s+/g, ' ').trim();
  return line.length > maxChars ? line.substring(0, maxChars) + '…' : line;
}

// 结果错误探测（CubeAgent isError 探测同思路）：合法 JSON 且带 error/cancelled 键 = 失败态
function detectErrorResult(result: string): boolean {
  try {
    const parsed: object = JSON.parse(result);
    const rec = parsed as Record<string, Object>;
    return rec['error'] !== undefined || rec['cancelled'] !== undefined;
  } catch (e) {
    return false; // 非 JSON 结果（纯文本）恒成功态
  }
}
