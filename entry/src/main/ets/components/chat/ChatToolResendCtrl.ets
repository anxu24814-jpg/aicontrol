// 工具卡重发编排域：模板工具卡「重发 / 改参数重发」的**轮外执行编排**——自持 mini-run 起轮
// → 确认链（写方法三档不豁免）→ 执行 → assistant 宿主行 + tool 结果节点两节点落库 → run
// 终态收口；新工具卡消息入会话流（历史可见、重进不丢、模型下一轮可见）。
// · 独立 run 不复用上一轮句柄：commitRunUnit 的 CAS UPDATE 恒把 run status 写回 running——
//   往已终结 run 提交破坏 run 生命周期；复用旧 runId 会把旧 run 的取消状态误伤重发（坑75）。
//   mini-run 走 prepareRun 空输入形态（userContent='' 不建 user 节点），命令层零改动；origin
//   经 commitRunUnit 入参落 ORIGIN_RESEND（prepareRun 入参只写 user 节点，空输入无处落）。
// · 落 assistant('') + tool 两节点：buildRequestHistory 对工具行是「assistant 前看配对」——
//   孤立 tool 行不入协议（模型不可见）。
// · 确认链不豁免：model 档**落人工卡**（重发无本轮请求历史，审批模型缺判断素材不送审——
//   从严 = 多弹一次卡，不放过写操作）。确认卡 / 挂起桥 / 域名快捷键 / 作答痕迹全复用既有
//   ToolRuntime 机制与 ChatToolCard 渲染，零新 UI。
// · 与发送轮互斥：同一占用闸（chatRunScope）+ sending 置真；停止键经宿主 abort 重发分支定向
//   httpAbortRun + 本域 requestStop（挂起由 cancelAllPending 以 false 续跑，按 stopRequested
//   归类中止，不误报拒绝）。
// · 宿主接口由 ChatSendCtrl implements（照 ChatRetryHost 先例）；对 ChatSendCtrl 仅类型引用
//  （编译期擦除无运行时环）；模块顶层零求值（坑50 纪律）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
// mini-run 耗时读回（读口 + 可信度纯函数 + 轮事实形状——与普通回复链同源）
import { queryRunRowById } from '../../common/store/SessionTraceDb';
import { TraceRunIn } from '../../common/chat/SessionTraceModel';
import { trustedRoundDurationMs } from '../../common/chat/ChatAnswerChoice';
import { DisplayRoundFacts } from './ChatDisplayProjection';
import { ChatGraphWriteCtrl } from './ChatGraphWriteCtrl';
import { isCancelledResult } from './ChatMessageProjection';
import { nextMessageId, nextRowCreatedAt, touchConversationUpdatedAt } from '../../common/store/ChatDb';
import { RunIdentity, ToolExecutionContext } from '../../common/chat/MessageContracts';
import { GraphNodeRef, GraphRunHandle, GraphSendStart, graphBeginSend, graphCommitNode,
  graphFinishRun, graphToolFactAdvance, graphToolFactDispatchIntent }
  from '../../common/chat/ChatGraphCommandSource';
import { ORIGIN_RESEND, PrepareRunInput } from '../../common/store/MessageBranchDb';
import { toolRegistry } from '../../common/providers/ToolTypes';
// 结果裁剪走落盘增强口（超 8K 非 MCP 结果落临时区 + 信封回执；mcp__ 前缀放行 32K/4K 自截
// 与错误原文——三消费方同源单点 = ToolResultSpill）
import { clipToolResultForToolSpilled } from '../../common/providers/ToolResultSpill';
import { CONFIRM_LEVEL_IRREVERSIBLE, ConfirmPrompt, ToolEntry, toolErrorText }
  from '../../common/providers/ToolContracts';
import { executeToolCall, toolRuntime } from '../../common/providers/ToolRuntime';
import { browseActDeniedResult } from '../../common/providers/ToolBrowseAct';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { ToolEventRecord, abortedToolResult, compactPreview, detectErrorResult, prettyJson,
  serializeToolRecord }
  from './ChatToolRoundCtrl';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatToolResend';

// 卡上入参 JSON → 改参数重发对话框预填表（只取顶层字符串值——模板参数值域恒 string；坏
// JSON / 空串回空表 = 预填尽力而为，不影响参数清单纯查模板行）
export function parseResendPrefill(argsJson: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (argsJson === '') {
    return out;
  }
  let parsed: object;
  try {
    parsed = JSON.parse(argsJson) as object;
  } catch (e) {
    return out;
  }
  if (parsed === null || Array.isArray(parsed)) {
    return out;
  }
  const rec = parsed as Record<string, Object>;
  for (const key of Object.keys(rec)) {
    const v: Object = rec[key];
    if (typeof v === 'string') {
      out[key] = v;
    }
  }
  return out;
}

// 重发轮展示终态映射（纯函数供断言直跑）：中止→stopped / 出错→error / 完成→done；「未保存」
// 路径由调用方按卡面出错直接落 error，不走本映射
export function resendRoundStatusOf(isError: boolean, cancelled: boolean): string {
  return cancelled ? 'stopped' : (isError ? 'error' : 'done');
}

// 重发编排宿主接口（ChatSendCtrl implements——全部薄直通）
export interface ChatResendHost {
  isDisposed(): boolean;
  isSending(): boolean;
  isDbReady(): boolean;
  conversationId(): string;
  toast(message: string): void;
  dataSource(): ChatDataSource;
  setSending(sending: boolean): void;
  followToBottom(): void;
  // 运行占用接纳（chatRunScope 会话互斥；成功返回重发 run 身份，null = 会话已有活跃 run）
  acquireResendRun(): RunIdentity | null;
  releaseResendRun(): void;
  // 执行上下文构造（接纳后调用——activeRun = 重发 run，值随链快照；实现 = buildExecutionContext）
  buildResendContext(): ToolExecutionContext;
  // 归属助手 id（prepareRun 的 assistantId）
  effectiveAssistantId(): string;
  // 图写侧路由（graphWrite 既有面）
  graphBranch(): string;
  ensureGraphRoute(): Promise<void>;
}

export class ChatToolResendCtrl {
  private host: ChatResendHost;
  // 重发进行态（单发互斥位——同一时刻至多一笔重发；sending 闸已挡发送轮，本位挡重发重入）
  private active: boolean = false;
  // 停止请求标记（宿主 abort 重发分支置位——执行回调按它分流中止载荷，区别于执行失败）
  private stopRequested: boolean = false;
  // 自持图句柄（mini-run 的 revision 序列——与 ChatGraphWriteCtrl 的轮级句柄完全独立，
  // 禁共用：共用会把重发节点挂进发送轮的提交链与「换轮作废」判据）
  private handle: GraphRunHandle | null = null;
  // 发起时会话快照（确认授予与事实链的会话键——落库/作答一律用快照，禁执行中途现读）
  private activeConvId: string = '';

  constructor(host: ChatResendHost) {
    this.host = host;
  }

  // 重发进行中（宿主 abort 分支的分流判据——true = 停止键属于本域）
  isBusy(): boolean {
    return this.active;
  }

  // 停止请求（宿主 abort 重发分支调用；HTTP 在途由宿主 httpAbortRun 定向掐断，执行回调按
  // 本标记归类中止）
  requestStop(): void {
    this.stopRequested = true;
  }

  // 重发入口（原样与改参数同一入口——argsJson 为卡上原值 / 对话框收集值；UI 层已判键显示，
  // 本层注册表态再判一次防御——模板可能在卡渲染后被删）
  startResend(_msgId: string, slug: string, argsJson: string): void {
    if (this.active) {
      // 重入给提示不静默（重发自身 running 卡上重发键可点、编辑对话框确认后也会走到——
      // 静默吞 = 用户填参点发送零反馈）
      this.host.toast('已有重发进行中，请等待完成或先停止');
      return;
    }
    if (this.host.isDisposed()) {
      return;
    }
    if (this.host.isSending()) {
      this.host.toast('当前会话已有进行中的回复，请等待完成或先停止');
      return;
    }
    const entry: ToolEntry | undefined = toolRegistry.get(slug);
    if (entry === undefined) {
      this.host.toast('该请求模板已删除，无法重发');
      return;
    }
    if (!this.host.isDbReady()) {
      this.host.toast('数据库未就绪，请稍候再试');
      return;
    }
    const run: RunIdentity | null = this.host.acquireResendRun();
    if (run === null) {
      this.host.toast('当前会话已有进行中的回复，请等待完成或先停止');
      return;
    }
    this.active = true;
    this.stopRequested = false;
    this.handle = null;
    const convId: string = this.host.conversationId();
    this.activeConvId = convId;
    this.host.setSending(true);
    // 路由装载（发送轮 ensureGraphRoute 同款——无行即出生，异常 fail-closed 落 blocked）
    this.host.ensureGraphRoute().then((): void => {
      if (this.host.isDisposed()) {
        this.finishOccupy(false);
        return;
      }
      if (this.host.graphBranch() === '') {
        this.host.toast(TOMBSTONE_TOAST_TEXT);
        this.finishOccupy(false);
        return;
      }
      this.beginGraph(entry, slug, argsJson, run, convId);
    }).catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '重发路由装载失败：%{public}s', (e as Error).message);
      this.host.toast('重发准备失败，请稍后再试');
      this.finishOccupy(true);
    });
  }

  // mini-run 起轮 + 屏上两行 push（prepareRun 空输入形态——无 user 节点，run 输入锚 = 提交时
  // 分支 head；起轮失败不具执行资格，fail-closed 呈报）
  private beginGraph(entry: ToolEntry, slug: string, argsJson: string, run: RunIdentity,
    convId: string): void {
    const beginInput: PrepareRunInput = {
      runId: run.runId,
      conversationId: convId,
      branchId: this.host.graphBranch(),
      assistantId: this.host.effectiveAssistantId(),
      userContent: '',
      origin: ORIGIN_RESEND,
      now: nextRowCreatedAt()
    };
    graphBeginSend(beginInput, [])
      .then((start: GraphSendStart): void => {
        this.handle = { runId: start.handle.runId, branchId: start.handle.branchId,
          revision: start.handle.revision };
        // 屏上两行：assistant 空正文宿主行（与工具卡构成前看配对段——模型下一轮可见）+ 工具卡（running）
        const hostMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
        hostMsg.createdAt = nextRowCreatedAt();
        hostMsg.live = true; // 图身份由落库段 stampNodeRef 回填（live 注释先例）
        const callId: string = nextMessageId('call');
        // kind 位恒 'tool'（空串会左移致 kind='' 落 notice 分支渲染为提示行、确认卡与终态写入全空转）
        const card: ChatMessage = newChatMessage(nextMessageId('tool'), 'tool', '', slug, 'running');
        card.toolCallId = callId;
        card.toolInputJson = prettyJson(argsJson);
        card.toolInputText = compactPreview(argsJson, 40);
        card.createdAt = nextRowCreatedAt();
        // 重发 mini-run 是真实 run，展示层如实登记独立轮——不登记则轮无事实、投影判 unknown
        // 收成 summary。轮身份与发送轮 currentRunToken 同式；输入锚空串 = 如实空（「缺失用空，
        // 禁猜」）；只碰本 run、旧轮零动作（不把旧轮改 running）
        this.host.dataSource().beginDisplayRound(convId + '|' + run.runId, '', hostMsg);
        this.host.dataSource().push(hostMsg);
        this.host.dataSource().bindDisplayMember(card, hostMsg.id);
        this.host.dataSource().push(card);
        this.host.followToBottom();
        // 意图事实先行（dispatch_intent 先于执行；落库失败回 ''，结果确认静默跳过，执行不阻断）
        graphToolFactDispatchIntent(run.runId, run.attemptId, slug, argsJson)
          .then((factId: string): void => {
            this.runPipeline(entry, slug, argsJson, card, callId, run, hostMsg, factId);
          })
          .catch((e: Object): void => {
            hilog.warn(DOMAIN, TAG, '重发意图事实落库失败：%{public}s', (e as Error).message);
            this.runPipeline(entry, slug, argsJson, card, callId, run, hostMsg, '');
          });
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '重发起轮失败：%{public}s', (e as Error).message);
        this.host.toast('重发保存失败，未开始执行');
        this.finishOccupy(true);
      });
  }

  // 确认链 + 执行 + 落库收口（preflight 非空 = 写方法或每次确认档——三档确认不豁免）
  private runPipeline(entry: ToolEntry, slug: string, argsJson: string, card: ChatMessage,
    callId: string, run: RunIdentity, hostMsg: ChatMessage, factId: string): void {
    const ctx: ToolExecutionContext = this.host.buildResendContext();
    const preflight = entry.preflight;
    const promptPromise: Promise<ConfirmPrompt | null> = preflight !== undefined ?
      preflight(argsJson, ctx) : Promise.resolve<ConfirmPrompt | null>(null);
    promptPromise.then((prompt: ConfirmPrompt | null): void => {
      if (this.settleIfAbandoned()) {
        return;
      }
      if (prompt === null) {
        // 全读请求 / auto 档 / 无预检工具——直执行（写方法恒带 preflight；白名单豁免须预检命中才谈）
        this.executeAndSettle(entry, argsJson, ctx, card, callId, run, hostMsg, factId);
        return;
      }
      // 会话级免询问（仅写操作档——不可逆档恒照旧弹卡，与轮内 sessionAllowHit 同判据）
      if (prompt.level !== CONFIRM_LEVEL_IRREVERSIBLE &&
        toolRuntime.isSessionAllowed(this.activeConvId, slug)) {
        this.executeAndSettle(entry, argsJson, ctx, card, callId, run, hostMsg, factId);
        return;
      }
      // 人工卡（ask 档 / model 档降级——本域不接审批模型闸，理由见文件头；「每次确认」档
      // 与「先问审批模型」档同落本支）
      this.humanConfirm(entry, argsJson, ctx, card, callId, prompt, run, hostMsg, factId);
    }).catch((e: Object): void => {
      // 预检异常不该发生（契约自防返 null）——防御性按执行失败收口不悬挂；已销毁同走放弃
      // 收口（销毁后仍落库 = 屏库分叉，违反本域「dispose 后屏上卡与节点都不落库」口径）
      if (this.settleIfAbandoned()) {
        return;
      }
      hilog.error(DOMAIN, TAG, '重发预检异常：%{public}s', (e as Error).message);
      this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
        JSON.stringify({ error: '重发预检失败：' + toolErrorText(e) }));
    });
  }

  // 人工确认（照轮内 runHumanConfirm 形制：卡置确认字段即渲染确认卡——复用既有确认卡
  // 判据与双键，零新 UI；作答经既有上行链 → resolveBrowseConfirm 按 callId 续跑）
  private humanConfirm(entry: ToolEntry, argsJson: string, ctx: ToolExecutionContext,
    card: ChatMessage, callId: string, prompt: ConfirmPrompt, run: RunIdentity,
    hostMsg: ChatMessage, factId: string): void {
    card.toolConfirmLevel = prompt.level;
    card.toolConfirmText = prompt.text;
    card.toolConfirmAiNote = '';
    card.toolConfirmDetail = prompt.detail ?? '';
    card.toolConfirmDomain = prompt.domain ?? '';
    // 等待态成立（说明串写入）后刷新展示投影（与轮内同口径——写后重算可见集合与轮操作栏判据）
    this.host.dataSource().refreshDisplay();
    toolRuntime.waitBrowseConfirm(this.activeConvId, callId).then((approved: boolean): void => {
      const answeredCard: ChatMessage | null = this.host.dataSource().findMessage(card.id);
      const sessionPicked: boolean = answeredCard !== null &&
        answeredCard.toolConfirmSessionAllow === true;
      if (answeredCard !== null) {
        // 作答痕迹（三值——'session' = 用户按的「本会话内允许」，轮内同款）
        answeredCard.toolConfirmResult = approved ?
          (sessionPicked ? 'session' : 'approved') : 'rejected';
        this.host.dataSource().refreshDisplay();
      }
      if (approved && sessionPicked) {
        toolRuntime.grantSessionAllow(this.activeConvId, entry.name);
      }
      if (this.settleIfAbandoned()) {
        return;
      }
      if (this.stopRequested) {
        // 停止发生在确认等待中（宿主 cancelAllPending 以 false 续跑）——中止载荷而非拒绝
        this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
          abortedToolResult());
        return;
      }
      if (!approved) {
        this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
          browseActDeniedResult());
        return;
      }
      this.executeAndSettle(entry, argsJson, ctx, card, callId, run, hostMsg, factId);
    });
  }

  // 执行 + 结算（executeToolCall 同步抛错与执行器违约 rejection 都转 error JSON，不悬挂不炸域）
  private executeAndSettle(entry: ToolEntry, argsJson: string, ctx: ToolExecutionContext,
    card: ChatMessage, callId: string, run: RunIdentity, hostMsg: ChatMessage,
    factId: string): void {
    let exec: Promise<string>;
    try {
      exec = executeToolCall(entry, argsJson, ctx);
    } catch (e) {
      this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
        JSON.stringify({ error: '工具执行异常：' + toolErrorText(e) }));
      return;
    }
    exec.then((raw: string): void => {
      if (this.settleIfAbandoned()) {
        return;
      }
      if (this.stopRequested) {
        // 停止发生在执行中（宿主 httpAbortRun 掐断，promise 以传输错误结算）——按中止载荷
        // 归类，不把主动停止误报成网络失败
        this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
          abortedToolResult());
        return;
      }
      this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson, raw);
    }).catch((e: Object): void => {
      if (this.settleIfAbandoned()) {
        return;
      }
      if (this.stopRequested) {
        this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
          abortedToolResult());
        return;
      }
      this.settleWithResult(entry, card, callId, run, hostMsg, factId, argsJson,
        JSON.stringify({ error: '工具执行异常：' + toolErrorText(e) }));
    });
  }

  // 统一结算：卡终态 → 两节点落库（assistant 宿主行 + tool 结果）→ 事实确认 → run 终态
  // → 占用归还。拒绝 / 中止 / 失败 / 成功四路同走（完整动作痕迹落库——回放「已拒绝 /
  // 已中止」可见）
  private settleWithResult(entry: ToolEntry, card: ChatMessage, callId: string,
    run: RunIdentity, hostMsg: ChatMessage, factId: string, argsJson: string,
    raw: string): void {
    const record: ToolEventRecord = {
      toolCallId: callId,
      name: entry.name,
      argsJson: argsJson,
      result: clipToolResultForToolSpilled(entry.name, raw, this.host.conversationId()),
      isError: detectErrorResult(raw)
    };
    // 卡终态延后到落库定局（原实现终态先行于落库——落库失败时屏上卡已定格终态而历史未
    // 落库，重进会话该卡消失 = 屏库分叉。两态落点见 settleCardSaved / settleCardUnsaved）
    this.persistAndFinish(record, card, hostMsg, run, factId);
  }

  // 卡正常终态（落库成功后落；@Observed 原地改字段——轮内 lane 结算同机制）。中止载荷映射
  // 与回放 toolCardFromRow 同口径（cancelled 键 →「已中止」——否则屏库两态分歧）
  private settleCardSaved(card: ChatMessage, record: ToolEventRecord): void {
    const doneCard: ChatMessage | null = this.host.dataSource().findMessage(card.id);
    if (doneCard === null || doneCard.toolState !== 'running') {
      return;
    }
    // cancelled 判据与 isError 解耦、态位增 cancelled——与回放 toolCardFromRow 同口径（中止
    // 是状态不是失败；两态不一致即屏库分歧）
    const cancelled: boolean = isCancelledResult(record.result);
    doneCard.toolState = cancelled ? 'cancelled' : (record.isError ? 'error' : 'done');
    doneCard.toolOutputJson = prettyJson(record.result);
    doneCard.toolDisplayText = cancelled ? '已中止' : compactPreview(record.result, 60);
    if (record.isError && !cancelled) {
      doneCard.text = compactPreview(record.result, 60);
    }
    // 卡终态与轮终态同拍——roundId 取卡面已装配轮身份（与投影消费同源；空 id 由 DataSource
    // 侧零动作兜底）；settle 不 reload，随下行 refreshDisplay 统一重算
    this.host.dataSource().settleDisplayRound(doneCard.displayRoundId,
      resendRoundStatusOf(record.isError, cancelled));
    // 等待态变化后刷新展示投影（同轮内 doneCard 口径）
    this.host.dataSource().refreshDisplay();
  }

  // 卡「未保存」终态（落库失败 / 提交冲突后落）：请求本体已执行完，结果仍在卡上可见，
  // 但重进会话不保留——如实告知不假装已保存
  private settleCardUnsaved(card: ChatMessage, record: ToolEventRecord): void {
    const doneCard: ChatMessage | null = this.host.dataSource().findMessage(card.id);
    if (doneCard === null || doneCard.toolState !== 'running') {
      return;
    }
    doneCard.toolState = 'error';
    doneCard.toolOutputJson = prettyJson(record.result);
    doneCard.toolDisplayText = '重发记录未保存，重进会话将不保留';
    // 未保存终态 = 卡面 error——轮事实同拍落 error（不让重发轮永久挂在 running；中止载荷
    // 在本路径卡面即未保存，不做 stopped 区分）
    this.host.dataSource().settleDisplayRound(doneCard.displayRoundId, 'error');
    this.host.dataSource().refreshDisplay();
  }

  // 已销毁守卫 + 放弃收口：true = 页面已销毁——屏上卡与节点都不落库（页面销毁 dataSource
  // 随弃 = 屏库一致，重进会话无痕）；占用由 disposeSilent 的 releaseRun 归还，此处只复位
  // 本域态（不复位 sending——页面已销毁，闭包写已销毁页面的 @State 无观察者且不必要）
  private settleIfAbandoned(): boolean {
    if (!this.host.isDisposed()) {
      return false;
    }
    this.active = false;
    this.handle = null;
    return true;
  }

  // 落库与收口（finishOccupy 恒执行——任何分支不悬挂占用）
  private persistAndFinish(record: ToolEventRecord, card: ChatMessage, hostMsg: ChatMessage,
    run: RunIdentity, factId: string): void {
    const handle: GraphRunHandle | null = this.handle;
    if (handle === null) {
      // 理论不达（beginGraph 成功才进管道）——防御性归还占用不悬挂
      this.finishOccupy(true);
      return;
    }
    // 两笔输出节点携登记值落列（prepareRun 的 origin 入参只写 user 节点、空输入形态不建
    // user 节点——ORIGIN_RESEND 只能经此处落列）；耗时读回快照在 graphFinishRun 之前取
    //（展示轮 id / 会话 / runId / 数据源引用 / 路径视图代次——delay 读回不认「当前卡」）
    const dsAtFinish: ChatDataSource = this.host.dataSource();
    const roundIdAtFinish: string = card.displayRoundId;
    const convIdAtFinish: string = this.activeConvId;
    const runIdAtFinish: string = run.runId;
    const epochAtFinish: number = dsAtFinish.pathEpoch();
    graphCommitNode(handle, 'assistant', '', '', 1, nextRowCreatedAt(), ORIGIN_RESEND)
      .then((hostRef: GraphNodeRef | null): Promise<GraphNodeRef | null> => {
        ChatGraphWriteCtrl.stampNodeRef(hostMsg, hostRef);
        if (hostRef === null) {
          this.host.toast('重发记录提交冲突');
        }
        // 落库走 serializeToolRecord 五键白名单（重发链无附件，产物与原 JSON.stringify(record)
        // 逐字节相同；口径与 ChatGraphWriteCtrl.commitToolNode 同源，防两链漂移）
        return graphCommitNode(handle, 'tool', serializeToolRecord(record), '', 1,
          nextRowCreatedAt(), ORIGIN_RESEND);
      })
      .then((toolRef: GraphNodeRef | null): Promise<void> => {
        ChatGraphWriteCtrl.stampNodeRef(card, toolRef);
        if (toolRef === null) {
          // 提交冲突 = 卡未落库（按「未保存」终态归位，不再定格终态造成重进会话凭空消失）
          this.host.toast('重发记录提交冲突');
          this.settleCardUnsaved(card, record);
        } else {
          this.settleCardSaved(card, record);
        }
        // 会话列表时间推进（图写链提交即推进列表时间是写侧契约——重发直连命令层绕过了
        // 该域，补同款 fire-and-forget）
        if (toolRef !== null) {
          touchConversationUpdatedAt(this.activeConvId, nextRowCreatedAt())
            .catch((e: Object): void => {
              hilog.warn(DOMAIN, TAG, '会话列表时间推进失败：%{public}s', (e as Error).message);
            });
        }
        // 事实确认（factId 空 = 意图未落成，静默跳过——与轮内同口径）
        if (factId !== '') {
          return graphToolFactAdvance(factId, run.runId, run.attemptId, '',
            record.isError ? 'failed' : 'result_confirmed', '', record.result)
            .then((): void => undefined);
        }
        return Promise.resolve();
      })
      .then((): Promise<void> => graphFinishRun(handle, !record.isError, ''))
      .then((): void => {
        // 持久化成功后的**独立**耗时读回——本调用不 return / 不 await（保存链与下行
        // finishOccupy、sending/占用归还都不等待它）；失败重发轮直接跳过（failed 无诊断
        // 不可信，不为补显示改 graphFinishRun 的 diagnostic 参数）
        if (!record.isError && roundIdAtFinish !== '' && runIdAtFinish !== '') {
          this.readBackRoundDuration(dsAtFinish, convIdAtFinish, epochAtFinish,
            roundIdAtFinish, runIdAtFinish);
        }
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '重发记录落库失败：%{public}s', (e as Error).message);
        // 落库失败 = 卡未保存（按「未保存」终态归位，屏上所见与库内所存恒一致；卡已终态
        // 时本调用幂等空转）
        this.settleCardUnsaved(card, record);
        this.host.toast('重发记录保存失败：' + (e as Error).message);
      })
      .then((): void => {
        this.finishOccupy(true);
      });
  }

  // 本 mini-run 耗时读回（与普通回复链同可信度与存活守卫）：单 run 精确读一次 → 数据源/
  // 会话/代次未变 → 轮事实仍在且终态 → 可信度纯函数判过 → setter 成功才 refreshDisplay 一次。
  // 读失败 hilog 留痕 + 页面仍有效时给一次中文提示（独立 catch——不进保存 catch、不误改工具卡）
  private readBackRoundDuration(ds: ChatDataSource, cid: string, epoch: number,
    roundId: string, runId: string): void {
    queryRunRowById(cid, runId)
      .then((run: TraceRunIn | null): void => {
        if (run === null || run.id !== runId) {
          return; // run 不在 / 身份不符——保持隐藏
        }
        if (ds.isDisplayDisposed() || this.host.dataSource() !== ds ||
          this.activeConvId !== cid || ds.pathEpoch() !== epoch) {
          return; // 离页 / 换源 / 会话变——迟到结果不再回填
        }
        const facts: DisplayRoundFacts | null = ds.displayRoundFactsOf(roundId);
        if (facts === null) {
          return;
        }
        const durationMs: number | undefined = trustedRoundDurationMs({
          status: run.status,
          diagnosticMessageId: run.diagnosticMessageId,
          createdAt: run.createdAt,
          updatedAt: run.updatedAt
        });
        if (durationMs === undefined) {
          return; // 不可信保持隐藏（failed 无诊断——含本链失败重发轮）
        }
        if (ds.setDisplayRoundDuration(roundId, durationMs)) {
          ds.refreshDisplay(); // 成功才刷新一次（已有合法值 / 非终态由 setter 拒绝）
        }
      })
      .catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, '重发轮耗时读取失败：%{public}s', (e as Error).message);
        if (!ds.isDisplayDisposed() && this.host.dataSource() === ds &&
          !this.host.isDisposed()) {
          this.host.toast('本轮耗时读取失败，可刷新重试');
        }
      });
  }

  // 占用归还 + 发送态复位（resetSending = false 仅用于页面已销毁支——闭包写已销毁页面的
  // @State 无观察者且不必要）
  private finishOccupy(resetSending: boolean): void {
    if (resetSending) {
      this.host.setSending(false);
    }
    this.host.releaseResendRun();
    this.active = false;
    this.handle = null;
  }
}
