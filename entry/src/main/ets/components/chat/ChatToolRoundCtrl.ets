// 工具调用轮编排域（自 ChatSendCtrl 域级拆分而出）。域 = 轮开启（beginToolRound：本轮
// assistant 收尾落库 + 历史追加）/ 调用执行（executeToolCalls 分流——ask_user 参与的轮
// 整轮串行防交互卡并发，其余一轮内 Promise.all 并发、按调用原序上屏与回传）/ 续轮
//（startNextAssistantRound）+ 轮次态与展示辅助（prettyJson 等）。
// 宿主接口由 ChatSendCtrl implements（实现位在 ChatHostDelegates）；本文件禁 import
// ChatSendCtrl（防循环依赖），宿主内部状态全部经 ChatToolRoundHost 接口薄直通访问。
// 中止卡三笔口径：B 落库 = 漏斗补写（未结算写 abortedToolResult、已结算原样补、幂等跳过）；
// C 幻觉调用兜底 = 零声明落 notice 不续轮（零协议暴露）；D 会话维度隔离 =
// waitAsk/waitBrowseConfirm 挂会话 id 分桶。
import { AiChatMessage, AiImagePart, AiReasoningItem, AiToolCall, AiToolDef } from '../../common/providers/AiTypes';
import { TOOL_ARGS_MAX_CHARS, TOOL_ARGS_ROUND_MAX_CHARS, TOOL_CALLS_PER_ROUND_MAX,
  TOOL_STEP_LIMIT_DEFAULT } from '../../common/providers/ToolLimits';
import { INTERACTION_ASK, ToolEntry, toolInteractionKind, toolRegistry }
  from '../../common/providers/ToolTypes';
// ★ U11 解耦笔6·域⑤（2026-10-16）：「ask 等待族」拆入 ChatAskResumeCtrl（等待行落库
//〔挂起时插 streaming tool 行 + run→awaiting_input〕/ 跨重启续答 / 放弃口）；本件经构造
// 注入持彼件引用，ask 分支走 beginAskWait 四参（会话/调用 id/等待行载荷 JSON/步序）。
// **等待行结算零特判**：结算（答案到达）与中止（漏斗补写）两路 graphCommitToolNode 调用
// 在写侧登记表命中后自动改走「更新既有等待行」（见 ChatGraphWriteCtrl）。
// ★ 2026-10-06 拆分笔：聚合器与结果截断自 ToolTypes 整域外迁（ToolStream / ToolClip），
// 注册面符号（ToolEntry / toolRegistry）仍自 ToolTypes
import { ToolCallAccumulator } from '../../common/providers/ToolStream';
// ★ 2026-10-19 P6 自检修复：MCP 回执经分流口（mcp__ 前缀放行 32K/4K 自截与错误原文，非 MCP 仍走 8K）
import { clipToolResultForToolSpilled } from '../../common/providers/ToolResultSpill';
// toolRuntime / executeToolCall（域级拆分迁 ToolRuntime.ets）与 deriveCallContext
//（逐调用上下文派生——工具结果附件缝）
import { deriveCallContext, executeToolCall, toolRuntime } from '../../common/providers/ToolRuntime';
import { ToolExecutionContext } from '../../common/chat/MessageContracts';
import { browseActDeniedResult } from '../../common/providers/ToolBrowseAct';
import { CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_RESULT_AI_ALLOWED, CONFIRM_RESULT_AI_DENIED,
  CONFIRM_ROUTE_HUMAN, ConfirmPrompt, toolErrorText } from '../../common/providers/ToolContracts';
// 审批模型闸：确认链命中且白名单未命中时先送审——写操作档 allow 直执行 / deny 即拒 /
// escalate、失败与不可逆档 allow 回人工卡（分流详见 runApprovalOrConfirm；approvalCardNote
// 供卡面说明行，isIrreversibleLevel 供档位闸）
import { APPROVAL_VERDICT_ALLOW, APPROVAL_VERDICT_DENY, ApprovalContextTexts, ApprovalVerdict,
  approvalCardNote, isIrreversibleLevel, judgeToolCall, pickApprovalContextTexts } from '../../common/providers/ApprovalGate';
import { SseToolDelta } from '../../common/providers/SseParser';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nextMessageId, nextRowCreatedAt } from '../../common/store/ChatDb';
import { ChatDataSource } from './ChatDataSource';
import { ChatAskResumeCtrl } from './ChatAskResumeCtrl';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { buildConfirmWaitPayload } from './ChatConfirmWait';
// StreamSettlement 为 type-only import（编译期擦除无运行时环，坑50 纪律同款例外）
import { StreamSettlement } from './ChatStreamFlowCtrl';

// 触顶让位轮回传结果（A2「到顶让模型知情」）：到顶被丢弃的调用以此 JSON 作为 role='tool'
// 结果回传模型（error 键与工具错误回传同形制），让模型知情收尾，治「末轮正文空串 → 空气泡」。
// 文案带上限值（值随助手配置可变，故为函数生成）
function limitReachedResult(limit: number): string {
  return JSON.stringify({
    error: '工具调用已达 ' + limit + ' 轮上限，本次调用未执行。请基于已有信息直接回答，不要再调用工具'
  });
}

// 中止载荷：cancelled 键 + error 文案（含「不要自动重试」语义，三源同形制）——中止漏斗与
// 重发被用户停止共用单源（2026-10-02 重发件导出）。detectErrorResult 对 cancelled 键即判
// 失败态；回放侧 toolCardFromRow（ChatDataSource）据同键映射「已中止」文案
export function abortedToolResult(): string {
  return JSON.stringify({
    cancelled: true,
    error: '用户中止了本次工具执行。不要自动重试或猜测原因，等待用户的下一步指示。'
  });
}

// 审批模型拒绝回传：error 键终态语义（detectErrorResult 即判失败态，模型不得原样重试），
// 理由取审批模型产出（空理由走缺省句）。只回模型不上 UI（卡面理由走 toolConfirmReason 展示）
function approvalDeniedResult(reason: string): string {
  return JSON.stringify({
    error: '审批模型拒绝了本次调用' + (reason !== '' ? '：' + reason : '') +
      '。不要原样重试或绕过审批，调整方案或等待用户指示。'
  });
}

// 工具卡落库行 content JSON 载荷（role='tool' 行单一真源——回放/历史重建双消费）
export interface ToolEventRecord {
  toolCallId: string;
  name: string;
  argsJson: string;
  result: string;
  isError: boolean;
  // 本次调用产出的工具结果附件（图片 / PDF 原件——卡面缩略图与请求组装共同源）。
  // **内存态，不入库**——落库恒走 serializeToolRecord 五键白名单（base64 挡在库外的
  // 唯一闸）；随 roundCards 清空释放（record 轮级生命周期）
  mediaParts?: AiImagePart[];
}

// 落库序列化白名单（「base64 不落库」的唯一闸）：恒输出五键（toolCallId / name / argsJson /
// result / isError）。两个落库调用点（ChatGraphWriteCtrl.commitToolNode 与
// ChatToolResendCtrl.persistAndFinish）一律走本函数，禁回退裸 stringify
export function serializeToolRecord(record: ToolEventRecord): string {
  return JSON.stringify({
    toolCallId: record.toolCallId,
    name: record.name,
    argsJson: record.argsJson,
    result: record.result,
    isError: record.isError
  });
}

// 中止漏斗轮级卡集条目：推卡点 append、resetForNewSend 清空、persistAbortedCards 消费。
// settled = lane 已过守卫并写入 record（显式标记——result !== '' 判据会被「执行器回空串」
// 边缘干扰）；persisted = role='tool' 行已 queued（串行/并行/漏斗三写点共用的幂等判据，
// 漏斗不重复补已落行）
interface RoundToolCardEntry {
  cardId: string;
  record: ToolEventRecord;
  settled: boolean;
  persisted: boolean;
  // graph 事实链 id（派发前意图事实——结果确认段消费；'' = 未落成）
  factId: string;
}

// 宿主接口：工具轮域引用的宿主内部状态/引擎域收敛于此（ChatSendCtrl implements，全部薄直通）
export interface ChatToolRoundHost {
  // 通用闸与页面桥（全部薄直通 refs/成员）
  isDisposed(): boolean;            // this.disposed
  isSending(): boolean;             // this.refs.sending()
  isDbReady(): boolean;             // this.refs.dbReady()
  conversationId(): string;         // this.refs.conversationId()
  toast(message: string): void;     // this.refs.toast
  dataSource(): ChatDataSource;     // this.refs.dataSource
  maybeFollow(): void;              // this.refs.follow.maybeFollow()
  // 流式态消费：读面 = 结算快照 settlement() 一次取齐，写面 = 两个受控动作（五字段写权限
  // 单源在 ChatStreamFlowCtrl 意图方法）
  settlement(): StreamSettlement;          // 只读结算快照（settleRoundAssistant 开头一次取齐）
  clearRoundAccumulation(): void;          // 续轮清三值（两累积串 + 思考行 id）
  bindLiveAssistant(id: string): void;     // 续轮绑占位行 id（占位行 push 之后调用）
  roundHistoryRef(): AiChatMessage[];   // 本轮请求历史（返回活引用，push 即生效）
  // 节流（Cube 引擎域已整域退役，此为残留消费面）
  dropThrottle(frameId: string): void;       // 薄包装 this.throttle().drop(frameId)
  // Key 池域续发
  attemptCurrent(): void;                    // 宿主既有方法放宽可见性，签名不变
  // 本轮工具执行上下文（显式携带替代四中转键——接纳时快照随链下传）
  executionContext(): ToolExecutionContext;
  // ── 工具结果附件缝 ──
  // 执行器经派生上下文（deriveCallContext）的 collectImage 交付附件；实现位 =
  // ChatToolMediaCtrl.collectToolImage（预算闸 + 恒记本调用 record〔卡面源〕+ 非能力协议
  // 回落 user 消息位）。false = 超预算或条目不在场，执行器据此中文回执
  collectToolImage(callId: string, mimeType: string, data: string): boolean;
  // 本连接工具结果附件位判据（结果回传带图与否依据——逐请求现读，连接切换即时生效）
  toolResultMedia(): boolean;
  // ── 图会话写侧（graph 轮内持久化经宿主单点编排——运行句柄与 revision 在宿主，本域只发
  // 意图；legacy 落库支已随线性写路径退役删除，图提交即唯一落库路径）──
  // 本轮是否 graph 形态（宿主轮首定格；blocked 早退后轮内恒 graph——防御性判据）
  isGraphMode(): boolean;
  // 中间轮 assistant 收尾提交（settleRoundAssistant 消费）：false = revision 冲突等被拒
  //（宿主呈报不静默）。stampTarget = 发起提交当刻的内存行对象（提交成功由写侧经
  // stampNodeRef 回填库身份；禁 resolve 后现读 liveAssistantId——会错 association）。
  // placeholderNodeId = 流中占位行节点 id（settlement 快照带出；'' = 无占位行，走既有插行路）
  graphCommitRoundAssistant(content: string, reasoning: string, stepIndex: number,
    stampTarget: ChatMessage | null, placeholderNodeId: string): Promise<boolean>;
  // 工具结果节点提交（串行 lane / 并行收尾 / 中止漏斗消费）
  graphCommitToolNode(record: ToolEventRecord, stepIndex: number): Promise<boolean>;
  // 工具事实：派发前意图（返回 factId 供确认段消费；落库失败回 ''，hilog 留痕不阻断执行）
  graphToolFactDispatch(name: string, argsJson: string): Promise<string>;
  // 工具事实：结果确认 / 失败终态（factId 空 = 意图未落成，静默跳过）
  graphToolFactConfirm(factId: string, result: string, failed: boolean): Promise<void>;
}

export class ChatToolRoundCtrl {
  private host: ChatToolRoundHost;
  private roundTools: AiToolDef[] = []; // 本轮工具声明（[] = 不带 tools 字段零回归）
  private toolAccumulator: ToolCallAccumulator = new ToolCallAccumulator(); // 流式聚合器
  private toolStep: number = 0; // 已执行的调用轮数（本轮 stepLimit 闸）
  // 本轮调用轮数上限（resetForNewSend 第二参写入 = 助手 toolStepLimit 换算结果；
  // 0 = 不限制已换算为内置硬顶 256；无助手缺省 32）
  private stepLimit: number = TOOL_STEP_LIMIT_DEFAULT;
  // 本流 reasoning item 捕获（OpenAI 官方端点 stateless 工具轮保真要求）：同 id 后到覆盖
  //（done 终值）；beginToolRound 随 assistant 行挂 roundHistory 回传，续轮/收尾清；
  // 非官方端点恒空数组零参与
  private roundReasoningItems: AiReasoningItem[] = [];
  // 触顶让位标记：每次发送只给一次——让位后模型仍发调用走原触顶路径（直接收尾），
  // 防「让位」变成无限续轮扣费
  private limitGraceUsed: boolean = false;
  // 轮次纪元：每次 resetForNewSend（发送轮首 + finishStream 收尾）自增。工具执行是长时异步
  //（联网工具 5~20s），「停止 → 立刻发新消息」时旧 lane 回调的 isSending() 守卫会误判为本轮
  // 仍在发送——旧结果会写进新轮历史、落孤儿 role='tool' 行、多起一个流。lane 捕获发起时纪元，
  // 回调与总守卫比对：不符 = 过期轮次一律作废（卡片补已中止，不落库不续轮）
  private roundGen: number = 0;
  // 本轮已上屏工具卡集：串行/并行两处推卡点 append，resetForNewSend 清空（与纪元推进同拍
  //——在途条目随旧轮作废）；条目持卡 id 与 record **引用**（lane 结算原位写 result/isError
  //——只存卡 id 无法还原已完成调用的载荷）。消费方 = persistAbortedCards（宿主经
  // abortRoundPending 调用）
  private roundCards: RoundToolCardEntry[] = [];
  // 工具窗占位行 id（'' = 无）：工具批启动时提前 push 的下一轮 assistant 占位行——治「空
  // 正文行被投影过滤后整轮执行期（慢工具/ask 确认，可达分钟级）无任何气泡」。生命周期
  // **三收口**（全路径无孤儿枚举，缺一即空行泄漏）：①续轮复用（startNextAssistantRound
  // 命中在场行，跳过 push 直接续写）；②停止/失败弹出（finishStream → retractPending
  // Placeholder，走 removeMessageIds 整行移除——禁「置假保留」形态：无正文轮命中投影双
  // 例外会渲染双状态行）；③resetForNewSend 兜底弹出（跨发送残留防御）。工具报错**不**
  // 收轮（error JSON 回执照常续轮），不触达收口。命名避开 assistantMsg——assert-app-domain
  // 95 组有限定名计数钉按该变量名对账（placeholderMsg 是新写点唯一合法名）
  private pendingPlaceholderId: string = '';
  // 本轮逐调用执行上下文表（preflightMemo 便签信道）：executeToolCalls 预检循环逐调用
  // deriveCallContext 派生按 callId 存表，runRegistered 按 callId 取用**同对象**（预检与执行
  // 共享一个上下文；语义与写入纪律见 MessageContracts 字段注释）；每次 executeToolCalls
  // 入口清旧（数据有界 = 只留本轮调用数条）。清点时机安全：下一轮必在本轮全部调用结算
  //（runOne 链）之后才到达
  private callContexts: Map<string, ToolExecutionContext> = new Map();
  // 提问等待与续答域（waitAsk/挂起/回填全在彼件；挂起点经 beginAskWait 调用）
  private askCtrl: ChatAskResumeCtrl;

  constructor(host: ChatToolRoundHost, askCtrl: ChatAskResumeCtrl) {
    this.host = host;
    this.askCtrl = askCtrl;
  }

  // ── 接线公共面（ChatSendCtrl 消费）──

  // 发送重置（dispatchSend 轮首传声明与上限 / finishStream 收尾传 []）；limit 省略 = 默认 32
  //（收尾路径无工具轮，值不参与判定）
  resetForNewSend(tools: AiToolDef[], limit: number = TOOL_STEP_LIMIT_DEFAULT): void {
    // 占位行兜底弹出（孤儿防线第三口）：上一发送若在工具窗内被打断且未经 finishStream
    // 收口（理论不达——error/interrupted 两路终态都经收口），残留空占位行在此整行移除，
    // 防泄漏进新一轮
    this.retractPendingPlaceholder();
    this.roundTools = tools;
    this.stepLimit = limit;
    this.roundGen++; // 纪元推进（在途 lane 全部作废）
    this.toolAccumulator = new ToolCallAccumulator();
    this.toolStep = 0;
    this.roundReasoningItems = [];
    this.limitGraceUsed = false;
    this.roundCards = []; // 漏斗卡集清空（与纪元同拍，时机红线见 persistAbortedCards）
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

  // 本轮生效上限（触顶 notice 文案用——与实际闸门同源，防「改了助手上限但提示仍写 32」漂移）
  roundLimit(): number {
    return this.stepLimit;
  }

  // 触顶让位轮可用：每次发送只给一次（防「让位」变无限续轮，见 limitGraceUsed）
  canGrantLimitGrace(): boolean {
    return !this.limitGraceUsed;
  }

  // 幻觉调用兜底（宿主 onStreamDone 收尾前接线）：本轮**零工具声明**而模型仍发调用——落
  // 一行 notice 后照常收尾；不补工具行、不续轮、不回传（「无 tools + 工具历史」协议组合
  // 四方言未证实，零协议暴露）。与 lane 的「未声明即不执行」守卫同族互补（彼处理「有声明
  // 但该调用未声明」，此处处理「整轮零声明」，两态覆盖声明面全集）。notice 不落库（回放同口径）
  noticeForUndeclaredCalls(calls: AiToolCall[]): void {
    if (calls.length > 0 && !this.hasDeclarations()) {
      this.host.dataSource().push(newChatMessage(nextMessageId('notice'), 'notice',
        '模型尝试调用工具，但本轮未启用任何工具，本次调用已忽略'));
    }
  }

  // 中止收尾漏斗（宿主 failRound 手动停止 / disposeSilent 页面销毁两处消费，序列收成单点）：
  // ①cancelAllPending 只清本会话挂起（会话维度隔离——分栏态他会话在途的提问/确认卡不被
  // 连带取消）；②persistAbortedCards 补写中止行（时机红线：须在轮次态清空
  //〔failRound → finishStream → resetForNewSend〕之前）
  abortRoundPending(conversationId: string): void {
    toolRuntime.cancelAllPending(conversationId);
    this.persistAbortedCards();
  }

  // 中止卡落库：遍历推卡集补写未落行条目——未结算（ask/确认/执行器在途）写 abortedToolResult，
  // 已结算未落行按 record 原样补写，已落行幂等跳过。★ 时机红线：须与轮次态失效**同同步栈**
  //（failRound 先于 finishStream 的 setSending/resetForNewSend；disposeSilent 已有 disposed=true）
  // ——同步返回后排队 lane 回调才走 stale 分支不重写，异步插入会与 lane 落行竞态双写。隐私
  // 会话全程零行（红线）。未结算条目同步补内存卡面终态（续聊请求历史经
  // ChatHistoryBuilder.toolCallFromMessage 读屏上卡不读库，卡无 output 则历史残缺）；
  // 补行取号走单调分配器恒晚于本轮既有行；落库失败 toast 不静默
  persistAbortedCards(): void {
    if (this.roundCards.length === 0 || !this.host.isDbReady()) {
      return;
    }
    // graph 分支：把中止卡提交为工具结果节点（载荷同 abortedToolResult）+ 事实终态——中止
    // 痕迹进路径（重进可见），事实终态 = 明确不重放。中止卡不置 isError：中止是状态不是失败
    //——result 载荷内 cancelled 键即判据（detectErrorResult / 回放 isCancelledResult 同源），
    // isError=false 使回放侧映射中性「已中止」徽标而非「出错」。事实标签按实况分流：未结算
    // 推 failed、已结算成功推 result_confirmed（已被正常路径确认过的理论窗口，二次确认被态表
    // 机械拒绝落 catch 留痕）。fire-and-forget 提交（宿主运行句柄收尾时仍有效）
    for (const entry of this.roundCards) {
      if (entry.persisted) {
        continue;
      }
      const unsettled: boolean = !entry.settled;
      if (unsettled) {
        entry.record.result = abortedToolResult();
        // isError 不置真：初始 false 保持——cancelled 键载荷即中止判据
      }
      entry.persisted = true;
      const card: ChatMessage | null = this.host.dataSource().findMessage(entry.cardId);
      if (unsettled && card !== null) {
        card.toolState = 'cancelled';
        card.toolOutputJson = prettyJson(entry.record.result);
        card.toolDisplayText = '已中止';
        // 等待态变化（等待用户处理 → 中止）后刷新展示投影（可见集合与轮操作栏判据吃等待态）
        this.host.dataSource().refreshDisplay();
        // 确认等待中中止的卡：确认标记与作答回执一并清——cancelAllPending 以 false 续跑后
        // awaitBrowseConfirm 内层会写 result='rejected'，不清则中止卡被渲染成「已拒绝」回执态
        //（confirmDone 判 result 非 undefined），违背该卡回退普通工具卡的既定不变量
        //（与串行 stale 分支同口径）
        card.toolConfirmText = '';
        card.toolConfirmResult = undefined;
      }
      this.host.graphCommitToolNode(entry.record, this.toolStep)
        .then((ok: boolean): Promise<void> => {
          if (!ok) {
            return Promise.resolve();
          }
          return this.host.graphToolFactConfirm(entry.factId, entry.record.result, unsettled);
        })
        .catch((e: Object): void => {
          hilog.warn(0x0001, 'ChatToolRound', '中止卡图侧提交失败：%{public}s',
            (e as Error).message);
        });
    }
  }

  // ── 工具调用轮 ──

  // 工具调用输入预算闸（数值决明拍板）：判据单源（空串 = 放行），串行与并行两路同点消费。
  // 判据对象 = 聚合完毕的 argsJson（聚合器与解析器不动）；超限 = 该调用不执行、error JSON
  // 回传（与「未在本轮启用」同形制——保 tool_calls ↔ tool 结果配对完整，防下一轮请求 400），
  // 文案数字取常量现读。三判据：①序位超单轮调用数上限；②单调用参数超上限；③按调用序前缀
  // 累计参数超单轮合计（超限位起不执行——前缀和只增，后续调用同判）
  private toolCallGateReason(call: AiToolCall, index: number, calls: AiToolCall[]): string {
    if (index >= TOOL_CALLS_PER_ROUND_MAX) {
      return '本轮工具调用数超出上限 ' + TOOL_CALLS_PER_ROUND_MAX + '，本次调用未执行';
    }
    if (call.argsJson.length > TOOL_ARGS_MAX_CHARS) {
      return '工具参数过长，本次调用未执行。请减少单次调用的参数内容';
    }
    let roundTotal: number = 0;
    for (let i = 0; i <= index; i++) {
      roundTotal += calls[i].argsJson.length;
    }
    if (roundTotal > TOOL_ARGS_ROUND_MAX_CHARS) {
      return '工具参数过长，本次调用未执行。请减少单次调用的参数内容';
    }
    return '';
  }

  // 轮开启：本轮 assistant 正文/思考收尾（settleRoundAssistant——UI 全量覆盖 + 落库 done
  // + 历史追加带 toolCalls 与 reasoning 快照）→ 逐个执行工具。语义：一次用户发送 = N 轮
  // assistant 行（每轮一行）+ 工具卡行（role='tool' 落库），与 finishStream 单轮收尾互不复用
  beginToolRound(calls: AiToolCall[]): void {
    // 轮次预算扣减（自检修复：原只比对不自增，toolStep 恒 0 = 闸门形同虚设，工具死循环
    // 无限续轮扣费直到手动停止）
    this.toolStep++;
    this.settleRoundAssistant(calls);
    this.executeToolCalls(calls);
  }

  // 触顶让位轮：到顶的收尾轮不静默丢弃调用——本轮 assistant 正常收尾入历史（带 toolCalls），
  // 每个被丢弃的调用补一条合成 error 工具结果（limitReachedResult，文案带上限值）再开新一轮，
  // 让模型自己组织收尾话术（治空气泡）。toolStep 不自增（未执行任何调用，「已执行的调用轮数」
  // 语义不变）；让位只给一次（canGrantLimitGrace，防无限续轮扣费）
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

  // 本轮 assistant 收尾（beginToolRound 与 grantLimitGrace 共用）：UI 全量覆盖 + 落库 done
  // + 历史追加（带 toolCalls 与 reasoning 快照）
  private settleRoundAssistant(calls: AiToolCall[]): void {
    // 结算快照：方法开头一次取齐四值（本方法内无中途写点，时机不引入语义差）。
    // assistantMsgId = 流式 assistant 气泡的消息 id，非助手归属 id——宿主文件 assistantId
    // 一名只留给助手归属语义（setBoundOverride 参数 / 落库绑定列），防误读
    const settle: StreamSettlement = this.host.settlement();
    const assistantMsgId: string = settle.liveAssistantId;
    const thinkingId: string = settle.liveThinkingId;
    const content: string = settle.assistantFull;
    const reasoning: string = settle.thinkingFull;
    // DeepSeek 服务端工具快照（S2⑥，2026-11-14）：非空 = 本 assistant 轮有服务端步骤——
    // 先挂内存行再提交（提交口 commitRoundAssistant 从 stampTarget 读，屏显与库同源）；
    // '' = 本轮无服务端步骤，行字段保持 undefined（零噪声）
    const serverToolsJson: string = settle.serverToolsJson;
    this.host.dropThrottle(assistantMsgId);
    if (thinkingId !== '') {
      this.host.dropThrottle(thinkingId);
      const thinkingMsg: ChatMessage | null = this.host.dataSource().findMessage(thinkingId);
      if (thinkingMsg !== null) {
        thinkingMsg.text = reasoning;
        // 思考行收口：本轮流已收尾落库 = 该思考块已完成（下一轮若再产 reasoning 由懒创建
        // 另建新行，见 ChatStreamFlowCtrl.onStreamDelta）
        thinkingMsg.streaming = false;
      }
    }
    const assistantMsg: ChatMessage | null = this.host.dataSource().findMessage(assistantMsgId);
    if (assistantMsg !== null) {
      assistantMsg.text = content;
      // 服务端工具原样串挂载（S2⑥——提交口从本行 stampTarget 读补列；非空才挂）
      if (serverToolsJson !== '') {
        assistantMsg.serverToolsJson = serverToolsJson;
      }
      // 中间行底栏收口（拍板 2a 按消息判）：本行自身流式已毕即置假出底栏；重试键不现
      //（随后的工具卡 push 与下一轮占位 push 都会清 tail）。中间行不经 finishStream，
      // 不置假则永远无底栏；落点选本收口法（与落库 done 同点，状态同源）
      assistantMsg.streaming = false;
      // tail 就地让出（真机修复）：本行之后必有工具卡与续轮行，此刻已非「其后无任何消息」
      //——原等工具卡 push 才清，长预检 await 期间空正文行渲染空泡肉眼可见；就地清后空行
      // 立即塌隐。中止轮不受影响：abort 路径 finishStream 会把 tail 置回本行，语义两链一致
      if (assistantMsg.tail === true) {
        assistantMsg.tail = false;
      }
    }
    // 中间轮收尾（streaming 置假 + tail 让出）后刷新展示投影——收束候选判定与空正文
    // 占位行的去留都按写后状态重算
    this.host.dataSource().refreshDisplay();
    // 工具轮 assistant 收尾行落库。graph 路径 = 提交本轮路径节点（content/reasoning/
    // stepIndex，commitRunUnit CAS），无占位行无版本链（图态无版本链——重试承载行走替代
    // 分支）；提交失败 toast 不静默。占位行在库时（settle.checkpointNodeId 非空）收口走
    // 「更新既有占位行」——占位行即中间行（终值覆写升级 done，不另插新行；流中半截已随
    // 250ms checkpoint 在库，收口即全量对齐）；'' 走既有插行路
    if (assistantMsgId !== '' && this.host.isDbReady()) {
      this.host.graphCommitRoundAssistant(content, reasoning, this.toolStep, assistantMsg,
        settle.checkpointNodeId)
        .then((ok: boolean): void => {
          if (!ok) {
            this.host.toast('消息提交冲突，本轮内容未保存');
          }
        })
        .catch((e: Object): void => {
          this.host.toast('消息提交失败：' + (e as Error).message);
        });
    }
    const assistantReq: AiChatMessage = { role: 'assistant', content: content };
    if (reasoning !== '') {
      assistantReq.reasoning = reasoning;
    }
    // reasoning item 回传料挂载：官方端点保真项随工具轮 assistant 行入历史
    //（compose 在 function_call 前回传 type:'reasoning' item）
    if (this.roundReasoningItems.length > 0) {
      assistantReq.reasoningItems = this.roundReasoningItems.slice();
    }
    // DeepSeek 服务端工具回传串挂载（S2⑥⑦——续轮请求历史随行，混用轮〔服务端搜索 + 客户端
    // 工具同流〕两个收口都要带服务端数据；compose 仅官方档轮输出 server_tool_calls）
    if (serverToolsJson !== '') {
      assistantReq.serverToolCallsJson = serverToolsJson;
    }
    assistantReq.toolCalls = calls;
    this.host.roundHistoryRef().push(assistantReq);
  }

  // 分流入口：交互类工具参与的轮整轮串行，其余并发执行。交互类判据 = 注册项派生
  //（toolInteractionKind(c.name) === INTERACTION_ASK——加新交互工具只需标注册块，本层零改动）。
  // ask 轮整轮串行定案（防交互卡并发）：ask 卡上屏即渲染可作答交互区（无「先占位后激活」
  // 形态），而 toolRuntime.resolveAsk 对不在挂起集的 callId 静默吞——提前上屏的第二张 ask 卡
  // 用户可作答但答案必丢；且 ask 等待主体是人类作答（秒~分钟级），混轮并发人体感知增益 ≈ 0。
  // 高危 browse_act 等确认卡同走串行（等待主体同为人类，卡上屏即渲染双键，提前上屏无益）。
  // 确认链注册表化泛化：逐调用查注册表 preflight（browse_act 异步精判 / http_request 写方法
  // 判定，统一 await），返回 ConfirmPrompt | null 非 null 即收集入串行路（档位随行供卡面徽章）
  private async executeToolCalls(calls: AiToolCall[]): Promise<void> {
    const hasAsk: boolean = calls.some((c: AiToolCall): boolean =>
      toolInteractionKind(c.name) === INTERACTION_ASK);
    const confirmPrompts: Map<string, ConfirmPrompt> = new Map<string, ConfirmPrompt>();
    const gen: number = this.roundGen; // 预检前采样（循环后复核，见下方纪元守卫）
    // 预检便签信道：执行上下文自「轮首单件共用」改「逐调用派生一次成型」——预检与执行
    // 同对象（preflightMemo 便签随对象从预检流到执行器，信道与纪律见 MessageContracts 字段
    // 注释；差异仅对象身份逐调用唯一，collectImage 缝本就逐调用绑 callId）；表按 callId 存、
    // 轮首清旧（数据有界，清点时机安全见字段注释）
    const baseExecCtx: ToolExecutionContext = this.host.executionContext();
    this.callContexts.clear();
    for (const call of calls) {
      const execCtx: ToolExecutionContext = deriveCallContext(baseExecCtx,
        (m: string, d: string): boolean => this.host.collectToolImage(call.id, m, d));
      this.callContexts.set(call.id, execCtx);
      const pf: ((argsJson: string, ctx: ToolExecutionContext) => Promise<ConfirmPrompt | null>) | undefined =
        toolRegistry.get(call.name)?.preflight;
      if (pf === undefined) {
        continue;
      }
      const prompt: ConfirmPrompt | null = await pf(call.argsJson, execCtx);
      if (prompt !== null) {
        confirmPrompts.set(call.id, prompt);
      }
    }
    // 纪元复核：预检 await 窗口内经历「停止 → 立即发新消息」时，旧轮 calls 不得入新轮执行
    //（roundGen 已推进 / sending 已翻真）；此刻卡尚未推上屏，直接 return 无残留。补
    // isDisposed 判据与 lane/总守卫对齐——销毁链只置 disposed、不翻 sending；不动 roundGen，
    // 预检窗口内退页旧轮工具会在已销毁页面上启动执行（browse_act 经排队与语义抓取构成真实
    // 宏任务窗口；纯 http_request 轮预检为微任务级插不进，由 httpAbortAll 与 lane 守卫兜底）
    if (this.host.isDisposed() || gen !== this.roundGen || !this.host.isSending()) {
      return;
    }
    // 工具窗占位行插桩（纪元复核通过后、执行分流前——此刻起至续轮/终态，屏面恒有
    // streaming 气泡）：本轮流末空正文行已随 settleRoundAssistant 收束被投影过滤，若不在
    // 此提前 push 下一轮占位行，慢工具/ask 确认的整个执行期（分钟级可达）屏面无任何气泡。
    // 复用与弹出语义见 pendingPlaceholderId 字段注释
    this.pushPlaceholderForNextRound();
    if (hasAsk || confirmPrompts.size > 0) {
      this.runToolCallsSerial(calls, confirmPrompts);
    } else {
      this.runToolCallsParallel(calls);
    }
  }

  // 串行执行本轮工具调用（ask 轮 / 高危确认轮专用路径）→ 全部完成后开新一轮
  private runToolCallsSerial(calls: AiToolCall[],
    confirmPrompts: Map<string, ConfirmPrompt>): void {
    const gen: number = this.roundGen; // 本轮纪元（过期轮次作废）
    // 展示轮 owner 快照：批进入时一次性取（异步预检之后不得再读易变的当前 owner）——本批
    // 全部工具卡与思考行都继承本轮正文行的轮归属
    const ownerId: string = this.host.settlement().liveAssistantId;
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
      // 高危确认等待标记：置位后 ChatToolCard 渲染确认卡（双键作答）——text 入主因句、
      // level 入档位徽章与风险块判据。会话级白名单命中（仅写操作档）时不置标记——
      // confirmPrompt 就地置 undefined（下游 run 分发据此直走注册表执行器，不再挂确认桥
      //——不置判据而只跳过标记会让分发仍去挂桥等一个永不到来的作答），并当场补批准戳
      //（见 sessionAllowHit）。确认链命中且白名单未命中时走审批闸（approvalPrompt 非 null
      //= 闸接管）——卡确认字段**此处不再置**（审批期间卡处 running 普通态，人工卡渲染判据
      // toolConfirmText 非空天然不成立；escalate 转人工时才在 runApprovalOrConfirm 内置，
      // 零新状态位无「卡已渲染而模型未裁」竞态；level 徽标随 ai 回执 deny/allow 两分支同写）。
      // 白名单命中路径照旧直通（用户显式意愿优先于模型意见，也不为审批烧请求）
      const promptRaw: ConfirmPrompt | undefined = confirmPrompts.get(call.id);
      const bypassBySession: boolean = promptRaw !== undefined &&
        this.sessionAllowHit(promptRaw, call.name);
      const approvalPrompt: ConfirmPrompt | undefined =
        (promptRaw !== undefined && !bypassBySession) ? promptRaw : undefined;
      // 结论去向：预检可直指人工卡（「每次确认」档——不过审批模型）或交审批闸（缺省口径）。
      // 域知识留工具侧，本层只按字段分派（不认工具名）
      const humanOnly: boolean =
        approvalPrompt !== undefined && approvalPrompt.route === CONFIRM_ROUTE_HUMAN;
      if (bypassBySession) {
        this.grantApproval(call);
      }
      // 工具卡轮归属继承：精确 owner = 本轮正文行——push 前落值
      this.host.dataSource().bindDisplayMember(card, ownerId);
      // 轮级载荷继承：工具卡为轮内首个上屏项时轮头行取本行载荷
      this.stampRoundMeta(card, ownerId);
      this.pushToolCardOrdered(card);
      this.host.maybeFollow();
      // 中止漏斗登记：推卡点 append——条目持 record 引用，lane 结算原位写 result/isError，
      // 漏斗按 settled/persisted 分流补行（见 RoundToolCardEntry 注释）
      const funnelEntry: RoundToolCardEntry = { cardId: cardId, record: record,
        settled: false, persisted: false, factId: '' };
      this.roundCards.push(funnelEntry);
      // graph 意图先行：派发前 prepared 落行 + dispatch_intent 推进——factId 随 promise
      // 回填条目供结果确认段消费；落库失败回 ''（确认静默跳过 + hilog 留痕），执行不阻断
      if (this.host.isGraphMode() && this.host.isDbReady()) {
        this.host.graphToolFactDispatch(call.name, call.argsJson)
          .then((factId: string): void => {
            funnelEntry.factId = factId;
          })
          .catch((e: Object): void => {
            hilog.warn(0x0001, 'ChatToolRound', '工具意图事实落库失败：%{public}s',
              (e as Error).message);
          });
      }
      // 执行：ask_user 挂交互桥（等用户作答），高危 browse_act 挂确认桥（等用户放行），
      // 其余走注册表执行器。未声明守卫（防模型幻觉调用——如会话联网开关剔除 search_web 后
      // 模型仍调用）：不执行、error JSON 回传模型自纠——「未声明即不执行」与请求体声明面
      // 一致，注册表认识不算数
      const declared: boolean =
        this.roundTools.some((t: AiToolDef): boolean => t.name === call.name);
      // 创建经 safeRun 收口（实参求值同步抛错与执行器违约 rejection 一并转 error JSON，
      // 轮次不悬挂）；预算闸先于声明闸（超限调用含交互类一律不执行）
      const gateReason: string = this.toolCallGateReason(call, index, calls);
      const run: Promise<string> = this.safeRun((): Promise<string> => gateReason !== '' ?
        Promise.resolve(JSON.stringify({ error: gateReason })) :
        (!declared ?
        Promise.resolve(JSON.stringify({ error: `工具 ${call.name} 未在本轮启用` })) :
        (toolInteractionKind(call.name) === INTERACTION_ASK ?
          this.askCtrl.beginAskWait(this.host.conversationId(), call.id,
            serializeToolRecord(record), this.toolStep) :
          (approvalPrompt === undefined ?
            this.runRegistered(call.name, call.argsJson, call.id) :
            (humanOnly ?
              this.runHumanConfirm(call, cardId, approvalPrompt, '') :
              this.runApprovalOrConfirm(call, cardId, approvalPrompt, gen))))));
      run.then((raw: string): void => {
        if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
          // 等答/执行间隙停止或销毁——不再落卡不再续轮（ask 已被 cancelAll 续跑过，此处吞）；
          // 卡片补终态防 running 幽灵（原实现直接 return，停止后工具卡永久停在 running 且
          // 不落库——UI 有卡 DB 无行，重进会话凭空消失）。纪元守卫：停止后立刻发新消息时
          // isSending() 已翻真，旧 lane 不得把过期结果写进新轮（详见 roundGen 注释）
          const stale: ChatMessage | null = this.host.dataSource().findMessage(cardId);
          if (stale !== null) {
            stale.toolState = 'cancelled';
            stale.toolDisplayText = '已中止';
            // 等待态变化后刷新展示投影（同中止漏斗口径）
            this.host.dataSource().refreshDisplay();
            // 确认等待中途停止/销毁：确认标记与作答回执一并清——cancelAllPending 已以
            // false 续跑本链，awaitBrowseConfirm 内层会先写 result='rejected'（本外层守卫
            // 是其承诺链下游），不清则中止卡被渲染成「已拒绝」回执态（confirmDone 判
            // result 非 undefined），违背「该卡自然回退普通工具卡」不变量
            stale.toolConfirmText = '';
            stale.toolConfirmResult = undefined;
          }
          return;
        }
        // ★ 2026-10-26 注入链治理 P0-c：超 8K 非 MCP 结果改落临时区 + 信封回执（串行路）
        record.result = clipToolResultForToolSpilled(call.name, raw,
          this.host.conversationId());
        record.isError = detectErrorResult(record.result);
        funnelEntry.settled = true; // 漏斗条目结算标记
        // 卡片态更新（@Observed 原地改字段——流式渲染同机制）
        const doneCard: ChatMessage | null = this.host.dataSource().findMessage(cardId);
        if (doneCard !== null) {
          doneCard.toolState = record.isError ? 'error' : 'done';
          doneCard.toolOutputJson = prettyJson(record.result);
          doneCard.toolDisplayText = compactPreview(record.result, 60);
          // 等待态变化（等答 → 完成）后刷新展示投影
          this.host.dataSource().refreshDisplay();
          if (record.isError) {
            doneCard.text = compactPreview(record.result, 60);
          }
          // 工具结果附件缩略图源（非空才赋保持 undefined 不渲染；两条落点路都写防卡面
          // 渲染随协议退化）
          if (record.mediaParts !== undefined && record.mediaParts.length > 0) {
            doneCard.toolMediaParts = record.mediaParts;
          }
        }
        // role='tool' 行落库（回放单一真源）：graph 会话提交工具结果节点（commitRunUnit
        // CAS）+ 事实推进 result_confirmed/failed。库未就绪跳过——不标 persisted，
        // 中止漏斗后续可补
        if (this.host.isDbReady()) {
          funnelEntry.persisted = true;
          this.host.graphCommitToolNode(record, this.toolStep)
            .then((ok: boolean): Promise<void> => {
              if (!ok) {
                this.host.toast('工具记录提交冲突');
                return Promise.resolve();
              }
              return this.host.graphToolFactConfirm(funnelEntry.factId, record.result,
                record.isError);
            })
            .catch((e: Object): void => {
              this.host.toast('工具记录提交失败：' + (e as Error).message);
            });
        }
        // 结果回传历史（四协议方言翻译在 compose 层）。能力协议（toolResultMedia 现读）且
        // 本调用有附件 → 随 role='tool' 行带 images（工具结果附件位——compose 层按 mime 分派）
        const resultMsg: AiChatMessage = { role: 'tool', content: record.result,
          toolCallId: call.id, toolName: call.name };
        if (this.host.toolResultMedia() && record.mediaParts !== undefined &&
          record.mediaParts.length > 0) {
          resultMsg.images = record.mediaParts.slice();
        }
        this.host.roundHistoryRef().push(resultMsg);
        runOne(index + 1);
      });
    };
    runOne(0);
  }

  // 并行执行本轮非交互工具调用（OpenAI parallel_tool_calls 默认语义：并发执行后按原序回传；
  // 双 search_web 2×20s 超时预算 → ≈1×20s）。三段式：
  // ① 同步 for 按调用序建漏斗条目 + push 工具卡 running + 起执行 Promise——同一同步循环内
  //    完成 = 卡序恒等于调用序（上屏序红线，渲染序零风险）；
  // ② lane 完成回调：停止/销毁守卫（命中补「已中止」终态防幽灵卡，同串行防线）→ 条目写
  //    result/isError 与 settled → 该卡终态原地更新（并发下进度可感知）。lane 拒绝面由
  //    safeRun 收口（「执行器契约恒 resolve」已被打破：缺上下文明确抛错致旧轮整链悬挂）
  //    ——都转 error JSON，Promise.all 不被击穿；总链另有兜底 catch（理论不达，防整轮悬挂）
  // ③ Promise.all 统一收尾：一次性总守卫 → 按调用序落库 role='tool' 行 + 历史按序 push →
  //    startNextAssistantRound。
  // 语义不变项：轮数上限按轮计（beginToolRound 每轮 ++ 一次，上限 = 本轮 stepLimit）/ 未声明
  // 守卫 / clipToolResult 截断 / detectErrorResult 探测 / 隐私会话旁路 / key 失败切换
  //（attemptCurrent 续发）/ 停止与销毁守卫（逐 lane + 总守卫）/ 单调用轮本质同构（不特判回串行）
  private runToolCallsParallel(calls: AiToolCall[]): void {
    const startedAt: number = Date.now();
    const gen: number = this.roundGen; // 本轮纪元（过期作废）
    // 展示轮 owner 快照：批进入时一次性取（并行 lane 各自异步——不得在 lane 内重读易变的
    // 当前 owner）；本批全部工具卡继承本轮正文行归属
    const ownerId: string = this.host.settlement().liveAssistantId;
    // 漏斗条目集（本方法局部）：lane 结算需原位写 settled 标记、收尾循环按序取 record 与
    // 卡 id 写行并标 persisted
    const entries: RoundToolCardEntry[] = [];
    const lanes: Promise<void>[] = [];
    // 索引循环（非 for-of）：预算闸（toolCallGateReason）需调用序位与全表（前缀累计），
    // 卡序 = 调用序的同步循环语义不变
    for (let i = 0; i < calls.length; i++) {
      const call: AiToolCall = calls[i];
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
      // 工具卡轮归属继承：同串行点（同步循环内 push 前落值）
      this.host.dataSource().bindDisplayMember(card, ownerId);
      // 轮级载荷继承：同串行点
      this.stampRoundMeta(card, ownerId);
      this.pushToolCardOrdered(card);
      this.host.maybeFollow();
      // 漏斗登记：推卡点 append——条目同时进轮级卡集（漏斗遍历补行）与本方法局部序列
      //（lane 结算与收尾按序取用）
      const funnelEntry: RoundToolCardEntry = { cardId: cardId, record: record,
        settled: false, persisted: false, factId: '' };
      this.roundCards.push(funnelEntry);
      entries.push(funnelEntry);
      // graph 意图先行（同串行点）：派发前意图事实，factId 随 promise 回填条目——并行收尾
      // 循环按调用序确认
      if (this.host.isGraphMode() && this.host.isDbReady()) {
        this.host.graphToolFactDispatch(call.name, call.argsJson)
          .then((factId: string): void => {
            funnelEntry.factId = factId;
          })
          .catch((e: Object): void => {
            hilog.warn(0x0001, 'ChatToolRound', '工具意图事实落库失败：%{public}s',
              (e as Error).message);
          });
      }
      // 未声明守卫（模型幻觉调用——「未声明即不执行」，error JSON 回传模型自纠；语义同串行）
      const declared: boolean =
        this.roundTools.some((t: AiToolDef): boolean => t.name === call.name);
      // 同串行点：safeRun 收口（同步抛错与违约 rejection 一并转 error JSON，lane 不悬挂、
      // 不击穿下方 Promise.all）；预算闸先于声明闸（同判据 toolCallGateReason——两路同点；
      // 超限调用不执行、error JSON 回传保配对）
      const gateReason: string = this.toolCallGateReason(call, i, calls);
      const run: Promise<string> = this.safeRun((): Promise<string> => gateReason !== '' ?
        Promise.resolve(JSON.stringify({ error: gateReason })) :
        (!declared ?
        Promise.resolve(JSON.stringify({ error: `工具 ${call.name} 未在本轮启用` })) :
        this.runRegistered(call.name, call.argsJson, call.id)));
      lanes.push(run.then((raw: string): void => {
        if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
          // 停止/销毁——该卡补终态防 running 幽灵（同串行防线），落库与续轮交由下方
          // Promise.all 收尾总守卫拦；纪元守卫（停止后立刻发新消息时 isSending() 已翻真
          //——旧 lane 不得写新轮）
          const stale: ChatMessage | null = this.host.dataSource().findMessage(cardId);
          if (stale !== null) {
            stale.toolState = 'cancelled';
            stale.toolDisplayText = '已中止';
            // 等待态变化后刷新展示投影（同中止漏斗口径）
            this.host.dataSource().refreshDisplay();
          }
          return;
        }
        // ★ 2026-10-26 注入链治理 P0-c：超 8K 非 MCP 结果改落临时区 + 信封回执（并行路）
        record.result = clipToolResultForToolSpilled(call.name, raw,
          this.host.conversationId());
        record.isError = detectErrorResult(record.result);
        funnelEntry.settled = true; // 漏斗条目结算标记
        // 卡片终态各自完成即更（@Observed 原地改字段——并发下进度可感知）
        const doneCard: ChatMessage | null = this.host.dataSource().findMessage(cardId);
        if (doneCard !== null) {
          doneCard.toolState = record.isError ? 'error' : 'done';
          doneCard.toolOutputJson = prettyJson(record.result);
          doneCard.toolDisplayText = compactPreview(record.result, 60);
          // 等待态变化（等答 → 完成）后刷新展示投影
          this.host.dataSource().refreshDisplay();
          if (record.isError) {
            doneCard.text = compactPreview(record.result, 60);
          }
          // 工具结果附件缩略图源（同串行点——两条落点路都写）
          if (record.mediaParts !== undefined && record.mediaParts.length > 0) {
            doneCard.toolMediaParts = record.mediaParts;
          }
        }
      }));
    }
    Promise.all(lanes).then((): void => {
      // 总守卫：全部完成后停止/销毁/轮次已换纪元——不落库不续轮（各卡幽灵防线已在 lane 内补过）
      if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
        return;
      }
      // 按调用序统一收尾：工具结果提交（回放单一真源）。graph 会话在本循环按调用序串行提交
      // 工具节点（并行 lane 只结算卡面——节点链序 = 调用序，commitRunUnit 串行 CAS 保证
      // 父链成链不兄弟分叉）+ 事实确认；提交失败 toast 不静默
      for (let i = 0; i < calls.length; i++) {
        const entry: RoundToolCardEntry = entries[i];
        const record: ToolEventRecord = entry.record;
        if (this.host.isDbReady()) {
          entry.persisted = true;
          this.host.graphCommitToolNode(record, this.toolStep)
            .then((ok: boolean): Promise<void> => {
              if (!ok) {
                this.host.toast('工具记录提交冲突');
                return Promise.resolve();
              }
              return this.host.graphToolFactConfirm(entry.factId, record.result,
                record.isError);
            })
            .catch((e: Object): void => {
              this.host.toast('工具记录提交失败：' + (e as Error).message);
            });
        }
        // 结果回传历史（四协议方言翻译在 compose 层）；能力协议（toolResultMedia 现读）且
        // 本调用有附件 → 随 role='tool' 行带 images（同串行点——工具结果附件位）
        const resultMsg: AiChatMessage = { role: 'tool', content: record.result,
          toolCallId: calls[i].id, toolName: calls[i].name };
        if (this.host.toolResultMedia() && record.mediaParts !== undefined &&
          record.mediaParts.length > 0) {
          resultMsg.images = record.mediaParts.slice();
        }
        this.host.roundHistoryRef().push(resultMsg);
      }
      // 真机验收证据面（BLOCKED 半托并发项引用；串行路径零新增打点）
      hilog.info(0x0001, 'ChatSend', '工具并行：%{public}d 个调用并发完成，耗时 %{public}d ms',
        calls.length, Date.now() - startedAt);
      this.startNextAssistantRound();
    }).catch((e: Object): void => {
      // 总链兜底（理论不达——lane 已由 safeRun 各自转 error JSON）：lane 回调整体抛错时
      // Promise.all 拒绝会令整轮悬挂（无落库无续轮），此处按「工具失败不炸轮次」语义继续
      // 续轮；守卫同收尾总闸
      hilog.warn(0x0001, 'ChatToolRound', '工具并行收尾异常：%{public}s', (e as Error).message);
      if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
        return;
      }
      this.startNextAssistantRound();
    });
  }

  // 执行承诺收口：把「执行承诺创建 + 结算」两步收成一处——①创建段同步抛错（runRegistered
  // 实参求值取 executionContext，缺上下文明确抛）转拒绝；②执行器违约 rejection 转 error
  // JSON。与「工具失败不炸轮次」既有形态同形（error 键 JSON 回填模型自纠），lane 与总链
  // 都不断，轮次不悬挂
  private safeRun(create: () => Promise<string>): Promise<string> {
    // 取串经 toolErrorText：非 Error rejection（BusinessError 等接口对象）时
    // (e as Error).message 可为 undefined——回执面禁出现 undefined 字样
    try {
      return create().catch((e: Object): string =>
        JSON.stringify({ error: '工具执行异常：' + toolErrorText(e) }));
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '工具执行异常：' + toolErrorText(e) }));
    }
  }

  // 注册表执行入口（未知函数名 = 注册表与声明脱节——error JSON 回传模型自纠不炸轮）。
  // callId 参定位本调用附件缝（上下文逐调用派生，collectImage 覆写为「本调用的附件缝」
  //——host.collectToolImage 按 callId 记到本调用的 record，并行 lane 各自一份互不串写）。
  // ask / 确认两挂起路径与未声明 / 预算闸早退不经本函数（零附件面）；**四处调用点**
  //（串行 runOne / 并行 lane / 审批放行 / 确认放行）缺一即该路调用拿不到附件缝
  private runRegistered(name: string, argsJson: string, callId: string): Promise<string> {
    const entry: ToolEntry | undefined = toolRegistry.get(name);
    if (entry === undefined) {
      return Promise.resolve(JSON.stringify({ error: '未知工具：' + name }));
    }
    // ctx 随链下传：执行器经执行上下文读会话/助手/运行身份，不再读 AppStorage 中转键；
    // 缺上下文由 executeToolCall 明确抛错。优先取预检循环存下的本调用上下文（同对象 =
    // preflightMemo 便签信道——确认桥等待分钟级后仍取同对象）；表未命中（无预检工具等）
    // 才现派生兜底——兜底为通路健壮位，便签消费方恒经预检路径
    const stored: ToolExecutionContext | undefined = this.callContexts.get(callId);
    return executeToolCall(entry, argsJson,
      stored !== undefined ? stored :
      deriveCallContext(this.host.executionContext(), (m: string, d: string): boolean =>
        this.host.collectToolImage(callId, m, d)));
  }

  // 本调用附件登记：roundCards 里按 toolCallId 查条目 → 命中则 mediaParts push（懒建数组）；
  // 未命中（条目不在场——中止漏斗已清 / 轮次作废）回 false。消费方 =
  // ChatToolMediaCtrl.collectToolImage（宿主经 access 闭包到达）
  attachCallMedia(callId: string, mimeType: string, data: string): boolean {
    for (const entry of this.roundCards) {
      if (entry.record.toolCallId === callId) {
        if (entry.record.mediaParts === undefined) {
          entry.record.mediaParts = [];
        }
        const part: AiImagePart = { mimeType: mimeType, data: data };
        entry.record.mediaParts.push(part);
        return true;
      }
    }
    return false;
  }

  // ── 审批模型闸 ──
  // 确认链命中且白名单未命中的调用先送审批模型，按**档位 × 结论**分流（四路）：
  // · 写操作档 allow = 直执行（卡留 aiAllowed 痕迹）；
  // · 写操作档 deny = 即拒（卡留 aiDenied + 理由，回传终态 JSON——模型不得原样重试）；
  // · escalate 与一切失败 = 回人工卡（此时才置卡确认字段 + 说明行 toolConfirmAiNote，走既有
  //   awaitBrowseConfirm 零改动；说明行只在审批模型已配置时非空——见分支注）；
  // · **不可逆档 allow 也回人工卡**（档位闸；决明拍板「明确拒绝才自动拒，允许/不确定转
  //   人工卡」——从严语义只在提示词 level 句承载，闸侧不因档位改送审形态，只改结论去向；
  //   不可逆档 deny 照旧自动拒，挡幻觉删除）。
  // 纪元守卫：审批是秒级长窗口（读超时 60s）——结论 settle 后先复核 disposed/sending/gen，
  // 过期轮回中止载荷（外层 run.then 总守卫吞并补卡终态），审批结论绝不写进新轮。
  // allow 授予走 grantApproval 单源（onApproved 分发——browse_act 批准戳 / 无戳工具空操作，
  // 与人工允许、会话白名单两条既有路径同一条规则一处实现）
  private runApprovalOrConfirm(call: AiToolCall, cardId: string, prompt: ConfirmPrompt,
    gen: number): Promise<string> {
    // 审批上下文可信面（纯函数收编在闸域）：尾部 user / assistant 正文各一段，本轮助手
    // 正文为空时回退用户所回应的那条；tool 行不取
    const texts: ApprovalContextTexts =
      pickApprovalContextTexts(this.host.roundHistoryRef());
    return judgeToolCall(prompt.level, prompt.text, call.name, call.argsJson,
      texts.userText, texts.assistantText)
      .then((verdict: ApprovalVerdict): Promise<string> => {
        if (this.host.isDisposed() || !this.host.isSending() || gen !== this.roundGen) {
          return Promise.resolve(abortedToolResult()); // 过期轮——外层守卫吞，卡补终态
        }
        const card: ChatMessage | null = this.host.dataSource().findMessage(cardId);
        if (verdict.verdict === APPROVAL_VERDICT_DENY) {
          if (card !== null) {
            card.toolConfirmResult = CONFIRM_RESULT_AI_DENIED;
            // 等待态变化后刷新展示投影（可见集合/轮操作栏判据吃等待态）
            this.host.dataSource().refreshDisplay();
            card.toolConfirmReason = verdict.reason;
            // 徽标失真修正：ai 回执路径统一写档位，徽标与预检档位恒一致（运行时字段不入库）
            card.toolConfirmLevel = prompt.level;
          }
          return Promise.resolve(approvalDeniedResult(verdict.reason));
        }
        // 写操作档放行 = 直执行（卡留 aiAllowed 痕迹）。档位闸：**不可逆档即使放行也落到
        // 下面的人工卡**（决明拍板「极危档也先过审批模型，明确拒绝才自动拒，允许/不确定转
        // 人工卡」；原实现漏了这道闸，模型判允许即执行 = 删除类动作无人确认）。不可逆档
        // 不得写 aiAllowed：写了卡就转回执态、确认区不渲染，用户将看不到按钮
        //（形状钉负向面守）
        if (verdict.verdict === APPROVAL_VERDICT_ALLOW && !isIrreversibleLevel(prompt.level)) {
          if (card !== null) {
            card.toolConfirmResult = CONFIRM_RESULT_AI_ALLOWED;
            card.toolConfirmReason = verdict.reason;
            card.toolConfirmLevel = prompt.level; // 档位徽标：ai 回执路径统一写准
            // 等待态变化后刷新展示投影（同 deny 分支口径）
            this.host.dataSource().refreshDisplay();
          }
          this.grantApproval(call);
          return this.runRegistered(call.name, call.argsJson, call.id);
        }
        // 人工卡两来源：①escalate（含未配置 / 失败 / 解析不出）②不可逆档模型放行。
        // 说明行随结论一并上卡（approvalCardNote 单源）——「闸跑了但没结论」与「本来就要
        // 问卷」在卡面必须分得开；未配置 = 空串不上卡（不给没配审批模型的用户添常驻说明行）
        return this.runHumanConfirm(call, cardId, prompt,
          approvalCardNote(verdict.verdict, prompt.level, verdict.failReason));
      });
  }

  // 人工确认（两条入路）：①预检直指人工卡（「每次确认」档不走闸：aiNote 恒 ''）②审批闸落
  // 人工卡（escalate / 不可逆档放行：aiNote = approvalCardNote 单源给）。卡 text/aiNote
  // 两字段写点仍只此一处（level 另有 ai 回执 deny/allow 两分支写点）。预览串与目标域名
  // 同点随行（空串 = 无预览/不出快捷键，browse_act 既有确认零变化）
  private runHumanConfirm(call: AiToolCall, cardId: string, prompt: ConfirmPrompt,
    aiNote: string): Promise<string> {
    const card: ChatMessage | null = this.host.dataSource().findMessage(cardId);
    if (card !== null) {
      card.toolConfirmLevel = prompt.level;
      card.toolConfirmText = prompt.text;
      card.toolConfirmAiNote = aiNote;
      card.toolConfirmDetail = prompt.detail ?? '';
      card.toolConfirmDomain = prompt.domain ?? '';
      // 等待态成立（说明串写入）后刷新展示投影——不刷新则「卡已推、说明串未写」窗口里
      // 轮被判为收束，中途正文会短暂出现操作栏；写后重算即收回「等待工具/用户操作」态
      this.host.dataSource().refreshDisplay();
    }
    // 确认等待行落库（2128 笔）：此前确认卡只有内存桥、DB 无行，杀进程/回收重进后卡面
    // 状态全失（toolConfirm* 是运行时字段）；现在把暂停态编进等待行 result 位（五键白名单
    // 不动、零迁移），回放侧 ChatConfirmWait 解码即恢复可作答入口。
    // ★ 顺序红线同 ask：先挂桥再落行——反序会让「落行完成前点确认」的作答走库侧续答，
    // 而库行尚未插入即匹配不到（静默吞）
    const lane: Promise<string> = this.awaitBrowseConfirm(call, cardId);
    if (this.host.isDbReady()) {
      const waitPayload: string = buildConfirmWaitPayload({
        text: prompt.text, level: prompt.level, detail: prompt.detail ?? '',
        domain: prompt.domain ?? '', aiNote: aiNote
      });
      if (waitPayload !== '') {
        this.askCtrl.beginConfirmWait(this.host.conversationId(), call.id,
          serializeToolRecord({
            toolCallId: call.id, name: call.name, argsJson: call.argsJson,
            result: waitPayload, isError: false
          }), this.toolStep);
      }
    }
    return lane;
  }

  // 确认链等待：挂确认桥等用户作答 → 允许则经注册表 onApproved 授予（browse_act 写单次
  // 批准戳；convId 在**用户作答那一刻**经宿主取当前会话快照，桥内不自读 AppStorage——负向
  // 钉守）后执行；拒绝则回拒绝文案（终态，模型不得重试）。作答后**不再清空
  // toolConfirmText**（回执行的体首主因句仍读它），改写 toolConfirmResult（'approved' /
  // 'rejected'）——确认区随之转执行中态或回执态（等待态判据 = text 非空且 result 未写，
  // 见 ChatToolCard.confirmAwaiting）。授予按 call.name 查注册表分发——无 onApproved 工具
  // 允许即直执行（批准戳是 browse_act 专属凭据，不跨工具）。作答痕迹三值：'session' =
  // 「本会话内允许」，本链据此授予会话级免询问（仅写操作档、仅本会话、仅本工具；不可逆档
  // 不出第三键）。★ 2026-11-09 三档归一笔记：原「始终允许该域名」快捷落档写点退役（★
  // 2026-11-11 域名确认档整卡退役——该档已无设置页维护面，写确认只随会话三档），本链只认
  // 「允许一次 / 本会话内允许」两值。
  private awaitBrowseConfirm(call: AiToolCall, cardId: string): Promise<string> {
    return toolRuntime.waitBrowseConfirm(this.host.conversationId(), call.id).then((approved: boolean): Promise<string> => {
      const card: ChatMessage | null = this.host.dataSource().findMessage(cardId);
      const sessionPicked: boolean = card !== null && card.toolConfirmSessionAllow === true;
      if (card !== null) {
        // 作答痕迹三值：'session' = 用户按的「本会话内允许」
        card.toolConfirmResult = approved ?
          (sessionPicked ? 'session' : 'approved') : 'rejected';
        // 等待态变化（用户作答）后刷新展示投影——写点在上一行，投影按写后状态重算
        //（可见集合与轮操作栏判据都吃等待态，见 ChatDisplayProjection）
        this.host.dataSource().refreshDisplay();
      }
      if (approved && sessionPicked) {
        // 会话级授予（唯一写点）：键 = 本会话快照 id + 工具名
        toolRuntime.grantSessionAllow(this.host.conversationId(), call.name);
      }
      if (!approved) {
        return Promise.resolve(browseActDeniedResult());
      }
      this.grantApproval(call);
      return this.runRegistered(call.name, call.argsJson, call.id);
    });
  }

  // 会话级免询问判据：**仅写操作档** + 白名单命中才免询问——不可逆档恒照旧弹卡（「本会话
  // 内允许」只授权用户当时看见的那类动作，删除类动作永远单独问，与「不可逆档不出第三键」
  // 同一条立意）。会话 id 经宿主快照取（负向钉守：链内零全局中转键字样）
  private sessionAllowHit(prompt: ConfirmPrompt, toolName: string): boolean {
    return prompt.level !== CONFIRM_LEVEL_IRREVERSIBLE &&
      toolRuntime.isSessionAllowed(this.host.conversationId(), toolName);
  }

  // 批准授予单源（onApproved 分发；两处共调 = 用户在卡上允许 + 会话级免询问——「获准 ⇒
  // 经注册表授予」收成一处，禁各写一份）。browse_act 凭戳执行（单次消费 + 60s TTL +
  // 会话一致）；http_request 等无 onApproved 工具此调用为空操作
  private grantApproval(call: AiToolCall): void {
    toolRegistry.get(call.name)?.onApproved?.(this.host.conversationId());
  }

  // 轮级载荷继承：步骤行借本轮正文行的创建时刻与轮级模型名——轮头行「轮开始时刻 + 模型名」
  // 口径单源（步骤行自身不产时刻/不持模型名；漏 modelLabel 即轮头行落到会话级兜底，切换模型
  // 后旧轮头漂成新模型）。owner 缺失/无值防御 = 两列各自按 undefined 不写（回落会话级兜底，
  // 不改既有行为）
  private stampRoundMeta(msg: ChatMessage, ownerId: string): void {
    if (msg.createdAt !== undefined && msg.modelLabel !== undefined) {
      return;
    }
    const owner: ChatMessage | null = this.host.dataSource().findMessage(ownerId);
    if (owner === null) {
      return;
    }
    if (msg.createdAt === undefined && owner.createdAt !== undefined) {
      msg.createdAt = owner.createdAt;
    }
    if (msg.modelLabel === undefined && owner.modelLabel !== undefined) {
      msg.modelLabel = owner.modelLabel;
    }
  }

  // 工具窗占位行提前 push（executeToolCalls 纪元复核后插桩点调用，一轮恰一次）：构造形态
  // 与 startNextAssistantRound 现役占位 push 完全一致（streaming 置真、正文空、live 标记、
  // 轮归属继承），仅两处有意差——①createdAt 不在此取号：提前在场时本工具轮工具卡尚未
  // push，此刻取号会早于工具行，续轮复用补写才与现役「恒晚于全部工具行」逐拍等价；②不
  // 绑流式域（bindLiveAssistant 留到复用拍，提前期间流域仍属上一轮正文行）。占位行提前
  // 期间零增量零 checkpoint（无 markDirty 不落库），DB 面与现状等价
  private pushPlaceholderForNextRound(): void {
    const ownerId: string = this.host.settlement().liveAssistantId;
    const placeholderMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
    placeholderMsg.streaming = true;
    placeholderMsg.live = true;
    this.host.dataSource().bindDisplayMember(placeholderMsg, ownerId);
    this.host.dataSource().push(placeholderMsg);
    this.host.maybeFollow();
    this.pendingPlaceholderId = placeholderMsg.id;
  }

  // 工具卡上屏保序（串行/并行两推卡点共用单源）：占位行在场时卡插在其**前**（屏序恒
  // [卡1, 卡2, …, 占位]——占位行是下一轮正文气泡，视觉在工具卡下方；多卡逐张 insertBefore
  // 同一锚位即保调用序）；不在场（纪元复核前已回退 / 复用后字段清空的异常窗）走现役
  // push 兜底。insertBefore 无 tail 清扫：占位行 push 口已置 tail，卡插其前不破坏
  // 「其后无消息」语义
  private pushToolCardOrdered(card: ChatMessage): void {
    const placeholderId: string = this.pendingPlaceholderId;
    if (placeholderId !== '' &&
      this.host.dataSource().findMessage(placeholderId) !== null) {
      this.host.dataSource().insertBefore(placeholderId, card);
      return;
    }
    this.host.dataSource().push(card);
  }

  // 占位行收口弹出（离开工具窗的「停止/失败」路专用，finishStream 在工具轮间隙终态时
  // 调用）：整行移除走 removeMessageIds 现役 API（自带轮事实裁剪与展示投影重算）+ 清
  // 字段，幂等（字段空即零动作）。禁「streaming 置假保留」形态：无正文轮停止时该行命中
  // statusTailIds 例外、旧正文行命中 tail 例外 → 工具卡上下双状态行。崩溃/杀进程 = 内存
  // 行不落库即消失，与现状一致
  retractPendingPlaceholder(): void {
    const pendingId: string = this.pendingPlaceholderId;
    if (pendingId === '') {
      return;
    }
    this.pendingPlaceholderId = '';
    if (this.host.dataSource().findMessage(pendingId) !== null) {
      this.host.dataSource().removeMessageIds([pendingId]);
    }
  }

  // 新一轮 assistant 占位（历史已含全部调用与结果）：重置累积态 → 新占位行上屏+落库 →
  // 同 key 位续发（不重轮转——失败切换语义只在 key 级失败时推进）
  private startNextAssistantRound(): void {
    if (this.host.isDisposed() || !this.host.isSending()) {
      return;
    }
    // 展示轮继承：清累积前保存旧 owner（清三值之后旧 liveAssistantId 即失），新占位行
    // push 前继承其轮 id——续轮不 begin 新轮（同一 run 内工具循环）
    const prevOwnerId: string = this.host.settlement().liveAssistantId;
    this.toolAccumulator = new ToolCallAccumulator();
    this.roundReasoningItems = [];
    // 续轮清三值（受控动作单点）：正文行 id 不在此时清，占位行 push 后才经
    // bindLiveAssistant 绑定
    this.host.clearRoundAccumulation();
    // 工具窗占位行复用分叉：提前 push 的占位行在场（工具窗正常续轮）→ 跳过构造与 push，
    // 补写 createdAt 后按现役尾段（绑定流式域 + 续发）收口——用户面 = 执行期的气泡即
    // 续轮正文气泡本体，续轮首增量零结构变更（行对象同一，比 pop+push 少一次投影变更）。
    // 字段初始化对账：bodyBindingId 由 newChatMessage 工厂对 assistant 恒铸（插桩时已有）、
    // displayBudget 由首帧 flush 懒创建（提前期间零增量不创建，与现役 push 同拍）、轮归属
    // 已在插桩时按同源 owner 绑定（幂等）——复用行与全新 push 行无字段差。不在场（让位轮
    // / 异常回退）走下方现役 push 全段兜底
    const reusedPlaceholder: ChatMessage | null = this.pendingPlaceholderId !== '' ?
      this.host.dataSource().findMessage(this.pendingPlaceholderId) : null;
    if (reusedPlaceholder !== null) {
      this.pendingPlaceholderId = '';
      // createdAt 补写走单调分配器：此刻取号恒严格晚于本工具轮全部工具行（分配器契约），
      // 补齐提前 push 时有意留空的轮开始时刻——现役 push 形态同源同拍
      reusedPlaceholder.createdAt = nextRowCreatedAt();
      this.host.bindLiveAssistant(reusedPlaceholder.id);
      this.host.attemptCurrent();
      return;
    }
    // createdAt 走单调分配器：恒严格晚于本工具轮全部工具行——原同拍 Date.now() 同毫秒并列
    // 是「工具卡回放到最新消息后」根因
    const rowCreatedAt: number = nextRowCreatedAt();
    const assistantMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
    // 创建时刻同源回填：与下方落库行同值共用；隐私会话同样有值（assistant 行推进间隔判定
    // 游标，缺失 = 下一条 user 的 gap 从更早消息起算偏大）
    assistantMsg.createdAt = rowCreatedAt;
    // 流式运行时标记（照 dispatchSend 占位同款）：新一轮开始 = 本行底栏不现，收口由本类
    // settleRoundAssistant（中间轮）或宿主 finishStream（最终轮）置假
    assistantMsg.streaming = true;
    // 实时行标记：id 为内存 id，图身份由 settleRoundAssistant 以发起当刻行对象经提交链
    // 第四参交写侧 stampNodeRef 回填
    assistantMsg.live = true;
    // 轮归属继承：续轮占位行继承旧 owner 的轮 id（push 前落值——首帧即属本轮；owner 已换/
    // 无轮 id 时留空，投影按 unknown 保守处理）
    this.host.dataSource().bindDisplayMember(assistantMsg, prevOwnerId);
    this.host.dataSource().push(assistantMsg);
    this.host.bindLiveAssistant(assistantMsg.id);
    // 图态无占位行——续轮 assistant 节点在其收尾时经 graphCommitRoundAssistant 提交，
    // 中断恢复走 run 终态清扫
    this.host.attemptCurrent();
  }
}

// JSON 串美化（工具卡展开区展示用；坏 JSON 原样返回——展示兜底不炸）。重发编排域
//（ChatToolResendCtrl）产物卡构造消费同一单源，禁第二份实现
export function prettyJson(json: string): string {
  try {
    return JSON.stringify(JSON.parse(json), null, 2);
  } catch (e) {
    return json;
  }
}

// 单行紧凑预览（工具卡摘要行；空白压一空格 + 超长截断）——重发件导出，同上单源口径
export function compactPreview(json: string, maxChars: number): string {
  const line: string = json.replace(/\s+/g, ' ').trim();
  return line.length > maxChars ? line.substring(0, maxChars) + '…' : line;
}

// 结果错误探测：合法 JSON 且带 error/cancelled 键 = 失败态；重发回执结算消费同一单源
export function detectErrorResult(result: string): boolean {
  try {
    const parsed: object = JSON.parse(result);
    const rec = parsed as Record<string, Object>;
    return rec['error'] !== undefined || rec['cancelled'] !== undefined;
  } catch (e) {
    return false; // 非 JSON 结果（纯文本）恒成功态
  }
}
