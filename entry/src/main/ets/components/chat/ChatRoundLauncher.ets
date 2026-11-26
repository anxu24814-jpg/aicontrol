// 轮次组装与起流域（DS 全家桶二期 S4 / §1-8 结构性前置，自 ChatSendCtrl 域级最小拆分迁出）。
// 一句话职责 =「记忆块 → 技能上下文 → 知识注入 → 路径摘要 → 请求历史读库/双闸 → 复位 →
// Key 池起流」的轮次发起链；**不新造传输与组包**（禁第二条请求链：起流咽喉点仍是
// ChatKeyRoundCtrl.startRound，与发送/重试两链同一个）。
// · 拆出理由（宪法 1200 硬线）：ChatSendCtrl 剔头 1236 已超线，只许「行数只减不加」；S4 的
//   #10 继续生成要复用轮次组装与起流，故先把本域整段外迁，拆完宿主降到 1200 以下再回接。
// · 依赖注入面 = ChatRoundLaunchDeps（全闭包，零反向 import ChatSendCtrl 运行时符号——
//   零环红线）；宿主在构造期把私有域件的到达口一次性注入，运行期只调闭包。
// · 行为逐字节零变化：两段方法体自宿主原样迁入，只把 this.xxx 换成 d.xxx。
import { AiChatMessage, AiConnection, SamplingParams } from '../../common/providers/AiTypes';
import { SkillSendContext } from './ChatSnapshotCtrl';
import { RoundRequest } from './ChatRoundAssembly';
import { KnowledgeInjectPlan } from '../../common/providers/RequestInject';
import { RequestHistoryResult } from './ChatRequestHistoryCtrl';
import { RequestSummaryInput, readPathSummaryInput } from '../../common/chat/ChatContextSource';
import { ChatMessage } from './ChatMessageCompose';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { contextWindowForConnection } from '../../common/store/ProviderDb';
import { resolveTokenBudget } from '../../common/chat/RequestHistoryBudget';
import { REQUEST_HISTORY_DECOUPLE_ENABLED } from '../../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RunIdentity } from '../../common/chat/MessageContracts';

// 宿主能力面（ChatSendCtrl 构造期注入；每条 = 一行闭包，宿主不新增公开字段）
export interface ChatRoundLaunchDeps {
  buildMemoryBlock: () => Promise<string>;
  buildSkillContext: (designate: string) => Promise<SkillSendContext>;
  buildKnowledgeBlock: (draftText: string,
    window: ChatMessage[]) => Promise<KnowledgeInjectPlan>;
  allMessages: () => ChatMessage[];
  conversationId: () => string;
  isDisposed: () => boolean;
  isSending: () => boolean;
  runToken: () => string;
  // 活跃 run 身份核验（异步读库窗口内停止/换轮作废；发送轮后段守卫）
  isRunActive: (run: RunIdentity) => boolean;
  toast: (message: string) => void;
  releaseRun: () => void;
  failRound: (message: string, status: number) => void;
  branch: () => string;
  contextCount: () => number;
  // 组装 + 复位组（宿主私有 assembleFittedRound；双闸/工具轮复位/用量清零都在其内部）
  assembleFittedRound: (conn: AiConnection, history: AiChatMessage[], memoryBlock: string,
    skillCtx: SkillSendContext, knowledge: KnowledgeInjectPlan, tokenBudget: number,
    windowTokens: number) => RoundRequest;
  // 请求历史读口（全额预算；userReq/excludeNodeId 传 null = 重试/续写形态）
  loadHistory: (conversationId: string, branchId: string, contextCount: number,
    pathSummary: RequestSummaryInput | null, windowSnapshot: ChatMessage[],
    userReq: AiChatMessage | null, excludeNodeId: string | null) => Promise<RequestHistoryResult>;
  // 起流咽喉点（唯一）
  startRound: (conn: AiConnection, history: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null) => void;
}

export class ChatRoundLauncher {
  private d: ChatRoundLaunchDeps;

  constructor(deps: ChatRoundLaunchDeps) {
    this.d = deps;
  }

  // 发送轮后段（解耦链：读库 → 组装 → 双闸 → 复位 → 开流；原 ChatSendCtrl.
  // dispatchRoundAfterPersist 整段迁入，守卫与日志口径逐字保真）
  async launchSendRound(conn: AiConnection, run: RunIdentity, excludeNodeId: string,
    windowSnapshot: ChatMessage[], userReq: AiChatMessage, memoryBlock: string,
    skillCtx: SkillSendContext, knowledge: KnowledgeInjectPlan,
    pathSummary: RequestSummaryInput | null): Promise<void> {
    const d: ChatRoundLaunchDeps = this.d;
    const contextCount: number = d.contextCount();
    const loadTask: Promise<RequestHistoryResult> = d.loadHistory(
      d.conversationId(), d.branch(), contextCount, pathSummary,
      windowSnapshot, userReq, excludeNodeId);
    const windowTask: Promise<number> = contextWindowForConnection(conn);
    const result: RequestHistoryResult = await loadTask;
    const windowTokens: number = await windowTask.catch((): number => 0);
    if (d.isDisposed() || !d.isRunActive(run)) {
      return; // 读库窗口内被停止 / 换轮——本轮身份作废
    }
    hilog.info(0x0001, 'ChatSend',
      '请求历史 rowCount %{public}d %{public}s / tokenBudget %{public}d',
      result.rowCount, result.degraded ? '（读库降级·窗口快照）' : '', resolveTokenBudget(windowTokens));
    this.startWithHistory(conn, d.runToken(), result.history, windowTokens,
      memoryBlock, skillCtx, knowledge, false);
  }

  // 重试组装段（ChatRetryHost.launchRetryRound）：记忆块 → 技能上下文（'' = 重试不重指定
  // ——指定随首答 user 消息已注入历史文本）→ 知识注入 → 路径摘要 → assembleRound →
  // 工具轮重置 → 执行上下文构造 → 轮次用量清零 → Key 池发起。**与 dispatchSend 尾段同序列**。
  // roundToken = 重试轮身份快照；异步组装窗口内会话被停止/换轮时旧轮按 token 失配作废。
  launchRetryRound(conn: AiConnection, roundToken: string): void {
    const d: ChatRoundLaunchDeps = this.d;
    d.buildMemoryBlock()
      .then((memoryBlock: string): Promise<void> => d.buildSkillContext('')
        // 内链 return 回外链 + 链尾补 catch（原内链 detached 无 catch 会悬挂 run 占用）
        .then((skillCtx: SkillSendContext): Promise<void> => {
          return d.buildKnowledgeBlock('', d.allMessages())
            .then((knowledge: KnowledgeInjectPlan): Promise<void> => {
              return readPathSummaryInput(d.conversationId())
                .then((pathSummary: RequestSummaryInput | null): void => {
                  if (d.isDisposed() || !d.isSending() || roundToken === '' ||
                    roundToken !== d.runToken()) {
                    return;
                  }
                  if (REQUEST_HISTORY_DECOUPLE_ENABLED) {
                    this.retryRoundFromDb(conn, roundToken, pathSummary,
                      memoryBlock, skillCtx, knowledge);
                    return;
                  }
                  const legacyHistory: AiChatMessage[] =
                    buildRequestHistory(d.allMessages(), pathSummary);
                  const legacyReq: RoundRequest =
                    d.assembleFittedRound(conn, legacyHistory, memoryBlock, skillCtx, knowledge, 0, 0);
                  d.startRound(conn, legacyReq.history, legacyReq.thinking, legacyReq.sampling);
                });
            });
        }))
      .catch((e: Object): void => {
        d.releaseRun();
        d.toast('发送准备失败：' + (e as Error).message);
      });
  }

  // 解耦重试链：读口全额预算（锚点 user 占预算内名额）；读库失败降级用清扫/换源后的窗口
  // 快照。读库窗口内换轮/停止 = 静默作废。失败上抛由外层 catch 收口。
  private async retryRoundFromDb(conn: AiConnection, roundToken: string,
    pathSummary: RequestSummaryInput | null, memoryBlock: string,
    skillCtx: SkillSendContext, knowledge: KnowledgeInjectPlan): Promise<void> {
    const d: ChatRoundLaunchDeps = this.d;
    const contextCount: number = d.contextCount();
    const windowSnapshot: ChatMessage[] = d.allMessages().slice();
    const loadTask: Promise<RequestHistoryResult> = d.loadHistory(
      d.conversationId(), d.branch(), contextCount, pathSummary, windowSnapshot, null, null);
    const windowTask: Promise<number> = contextWindowForConnection(conn);
    const result: RequestHistoryResult = await loadTask;
    const windowTokens: number = await windowTask.catch((): number => 0);
    if (d.isDisposed() || !d.isSending() || roundToken === '' || roundToken !== d.runToken()) {
      return;
    }
    hilog.info(0x0001, 'ChatSend', '重试历史 rowCount %{public}d %{public}s',
      result.rowCount, result.degraded ? '（读库降级·窗口快照）' : '');
    this.startWithHistory(conn, roundToken, result.history, windowTokens,
      memoryBlock, skillCtx, knowledge, true);
  }

  // 继续生成起流（二期 S4 #10）：外部已组装好「末条 assistant + prefix:true」的历史与
  // beta 端点连接，本方法只走同一条「双闸 → 复位 → 起流」链，不新开请求路径。
  // guardOnSending=false = 续写轮的占用态由 ChatContinueCtrl 自持（不经 refs.sending 闸）
  launchContinueRound(conn: AiConnection, roundToken: string, history: AiChatMessage[]): void {
    const d: ChatRoundLaunchDeps = this.d;
    d.buildMemoryBlock()
      .then((memoryBlock: string): Promise<void> => d.buildSkillContext('')
        .then((skillCtx: SkillSendContext): Promise<void> =>
          d.buildKnowledgeBlock('', d.allMessages())
            .then((knowledge: KnowledgeInjectPlan): void => {
              // 续写不做 token 双闸裁剪（budget 0 = fitTokens 原引用直通）：前缀末条被裁
              // 即失去 prefix 语义，官方硬要求最后一条消息是那条 assistant
              if (d.isDisposed() || roundToken === '' || roundToken !== d.runToken()) {
                return;
              }
              const finalReq: RoundRequest = d.assembleFittedRound(conn, history,
                memoryBlock, skillCtx, knowledge, 0, 0);
              if (finalReq.blockReason !== undefined && finalReq.blockReason !== '') {
                d.failRound(finalReq.blockReason, 0);
                return;
              }
              d.startRound(conn, finalReq.history, finalReq.thinking, finalReq.sampling);
            })))
      .catch((e: Object): void => {
        d.releaseRun();
        d.toast('继续生成准备失败：' + (e as Error).message);
      });
  }

  // 双闸 + 小窗前置拦截 + 起流（三条链共用，行为与宿主原 assembleFittedRound 调用段同序）
  private startWithHistory(conn: AiConnection, roundToken: string, history: AiChatMessage[],
    windowTokens: number, memoryBlock: string, skillCtx: SkillSendContext,
    knowledge: KnowledgeInjectPlan, guardOnSending: boolean): void {
    const d: ChatRoundLaunchDeps = this.d;
    if (d.isDisposed() || roundToken === '' || roundToken !== d.runToken() ||
      (guardOnSending && !d.isSending())) {
      return;
    }
    const finalReq: RoundRequest = d.assembleFittedRound(conn, history,
      memoryBlock, skillCtx, knowledge, resolveTokenBudget(windowTokens), windowTokens);
    if (finalReq.blockReason !== undefined && finalReq.blockReason !== '') {
      d.failRound(finalReq.blockReason, 0);
      return;
    }
    d.startRound(conn, finalReq.history, finalReq.thinking, finalReq.sampling);
  }
}
