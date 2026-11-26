// 提问等待与跨重启续答域（★ U11 解耦笔6·域⑤ 2026-10-16 自 ChatToolRoundCtrl 域级最小拆分
// ——宪法「新增功能域 / 跨域改动不论行数一律先拆」：域⑤ 为 ask 等待链引入「等待行落库 +
// 跨重启续答 + 放弃口」三件新职能，先拆「ask 等待族」到独立件再动手。
// 域定义一句话：ask_user 提问的**等待与续答**——同进程挂起接通（ToolRuntime 交互桥），
// 跨进程（杀应用或运行时空闲回收后重进）等待卡可作答续跑（库侧回填 + 重建请求续跑）或
// 放弃收口；等待行（图态进行中 tool 行）的落库发起同属本域。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话 = 提问等待与续答；②无既有
//   同域可并——ChatToolRoundCtrl 是通用工具轮编排（ask 分支只是其分流一角），且域⑤ 新职能
//   会把等待族显著增重（等待行落库 / 续答编排 / 放弃口），并入会让工具轮件越线；
//   ③实逻辑非转接壳：本件承载续答全链（库侧回填 CAS / 保真载荷构造 / 重建起轮 / 放弃收口）。
// · 依赖方向（零环红线，坑50）：本件 → ChatToolRoundCtrl 仅**单向**类型与纯函数引用
//   （ToolEventRecord / serializeToolRecord / compactPreview）；ChatToolRoundCtrl 不 import
//   本件——挂起点经 ChatToolRoundHost 一格薄直通（beginAskWait）到达本件，防两件成环。
//   模块顶层零求值（坑50 纪律）。
// · 拍板口径（2026-10-15 决明 + 总案 U11）：toolCallId **保真原编号**——等待行落库时点
//   持久化模型原始 id（serializeToolRecord 五键白名单，零迁移零加列），续答回填原样沿用；
//   「新铸自洽」为后备（原编号不可得时回填侧现场编新 id，重建链两侧同取一行载荷天然配对）；
//   不做自动续跑（拍板）；同轮 ask 后未执行调用不回放（对齐 kel 设计原则）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection } from '../../common/providers/AiTypes';
import { toolRuntime } from '../../common/providers/ToolRuntime';
import { nextMessageId, nextRowCreatedAt } from '../../common/store/ChatDb';
import { ORIGIN_SEND, RUN_STATUS_INTERRUPTED } from '../../common/store/MessageBranchDb';
import { AwaitingAskCandidate, GraphNodeRef, GraphRunHandle, graphAwaitingAskCandidates,
  graphCommitNode, graphFinishRun, graphToolFactAdvance }
  from '../../common/chat/ChatGraphCommandSource';
// 重启恢复待答集清标（★ 2026-10-16 重启续答冻结修复笔）：run 离开 awaiting_input 的落库
// 提交回调点（runResume/runAbandon 两处）经运行时单例清标——本件 → common/chat 单向引用
import { chatSessionRuntime } from '../../common/chat/ChatSessionRuntime';
import { ROUTE_BLOCKED } from '../../common/chat/ChatContextSource';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { browseActDeniedResult } from '../../common/providers/ToolBrowseAct';
import { ChatDataSource } from './ChatDataSource';
import { ASK_ABANDON_MARK, ChatMessage, newChatMessage } from './ChatMessageCompose';
import { ChatSendRefs } from './ChatSendCtrl';
import { ChatGraphWriteCtrl } from './ChatGraphWriteCtrl';
import { ToolEventRecord, compactPreview, serializeToolRecord } from './ChatToolRoundCtrl';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatAskResume';

// 续答宿主接口（ChatSendCtrl implements，照 ChatRetryHost / ChatResendHost 形制——薄直通与
// 复用重试域两法；实现位集中一节）
export interface ChatAskResumeHost {
  isDisposed(): boolean;
  isSending(): boolean;
  isDbReady(): boolean;
  conversationId(): string;
  toast(message: string): void;
  dataSource(): ChatDataSource;
  setSending(sending: boolean): void;
  // 续答占用接纳（★ 域⑤：接管**既有 run 身份**——RunScope.adopt 非新铸造；false =
  // 同会话已有活跃 run，提示拒单语义与重试域 acquireRun 同款）
  acquireResumeRun(runId: string, attemptEpoch: number): boolean;
  currentRunToken(): string;
  releaseRunWithGuard(): void;
  ensureGraphRoute(): Promise<void>;
  routeState(): string;
  // 起流复位段与组装段（复用重试域两法——组装的 assembleRound 消费点仍恰两处，「禁第二条
  // 请求链」锚不破；续答轮与重试轮同为「无 userReq 注入」的重建起轮）
  beginResumeStreaming(msgId: string): void;
  launchResumeRound(conn: AiConnection, roundToken: string): void;
  // 等待行落库（挂起道——graphWrite.beginAskWaitRow 薄直通：插 streaming tool 行 +
  // run→awaiting_input 同事务；呼叫登记表在彼件，结算/中止两路经 commitToolNode 自动改走
  // 更新既有等待行）
  beginAskWaitRow(toolCallId: string, recordJson: string, stepIndex: number): Promise<string>;
  // 续答句柄接管（graphWrite.adoptRun 薄直通——回填 CAS 后的 revision 与步序续号）
  adoptResumeRun(runId: string, branchId: string, revision: number, stepSeq: number): void;
  // 同进程放弃口（有内存桥在途时走既有停止链——abort 的跨域分发；无桥走库侧收口）
  abortRound(): void;
}

// 等待行载荷读侧投影（serializeToolRecord 五键的子集——保真口径只消费三键）
export interface AskWaitPayload {
  toolCallId: string;
  name: string;
  argsJson: string;
}

// 等待行载荷解析（纯函数——直跑断言面）：合法 JSON 且有非空 toolCallId 与 name 才成立；
// 坏 JSON / 非对象 / 缺键 / 空串回 null（fail-safe：调用方回退新铸自洽或静默跳过）
export function parseAskWaitPayload(recordJson: string): AskWaitPayload | null {
  if (recordJson === '') {
    return null;
  }
  let parsed: object;
  try {
    parsed = JSON.parse(recordJson) as object;
  } catch (e) {
    return null;
  }
  if (parsed === null || Array.isArray(parsed)) {
    return null;
  }
  const rec = parsed as Record<string, Object>;
  const toolCallId: Object | undefined = rec['toolCallId'];
  const name: Object | undefined = rec['name'];
  if (typeof toolCallId !== 'string' || toolCallId === '' ||
    typeof name !== 'string' || name === '') {
    return null;
  }
  const argsRaw: Object | undefined = rec['argsJson'];
  return {
    toolCallId: toolCallId as string,
    name: name as string,
    argsJson: typeof argsRaw === 'string' ? argsRaw as string : '{}'
  };
}

// 终态回填载荷构造（纯函数——直跑断言面；**toolCallId 保真口径的落点**）：以等待行载荷为
// 源构造结算后的五键 record JSON——原 toolCallId 保真沿用（parseAskWaitPayload 命中时），
// 不可得（坏 JSON / 空 id）回退新铸自洽（fallbackCallId 由调用方经 nextMessageId('call')
// 现场铸造，两侧同取一行载荷天然配对——E1 §2.3）；result = 答案载荷，isError=false
//（AskPayload 无 error/cancelled 键——detectErrorResult 恒判成功态）。恒走
// serializeToolRecord（五键白名单与键序单源——禁第二份字面量）
export function buildAskSettledRecordJson(waitRecordJson: string, answerJson: string,
  fallbackCallId: string): string {
  const parsed: AskWaitPayload | null = parseAskWaitPayload(waitRecordJson);
  const record: ToolEventRecord = {
    toolCallId: parsed !== null ? parsed.toolCallId : fallbackCallId,
    name: parsed !== null ? parsed.name : '',
    argsJson: parsed !== null ? parsed.argsJson : '{}',
    result: answerJson,
    isError: false
  };
  return serializeToolRecord(record);
}

// 放弃口中止载荷（唯一写点；形制照 ToolRuntime.cancelAllPending 对 ask 挂起的取消载荷——
// 同进程停止与跨重启放弃两条路写出**同一语义**的载荷，回放侧 cancelled 键走域① 渲染分支
// 显「已中止」；文案逐字与 ToolRuntime 同位句一致）
export function abandonedAskResult(): string {
  return JSON.stringify({ cancelled: true, error: '用户中止了本次提问' });
}

// 确认卡跨重启「允许」回填载荷（2128 笔；纯函数——直跑断言面）：让模型明确知道「用户
// 允许了，但执行环境已中断、操作没发生」——不得假装成功，也不得当作拒绝。模型据此决定
// 是否重新发起同一调用（预检会再问一次，用户再允许即真正执行）。
export function confirmApprovedAfterRestartResult(): string {
  return JSON.stringify({
    approved: true,
    note: '用户允许了本次操作，但应用已重启、执行环境中断，操作没有发生。如需继续，请重新发起同一个工具调用。'
  });
}

// 等待单元匹配（纯函数）：按行载荷 toolCallId 匹配目标 callId——命中回候选（含 run/行/
// 事实全套库材料），miss 回 null（不在场 = 该卡已答/已中止，调用方静默吞——与
// ToolRuntime.resolveAsk 对不在挂起集 callId 静默吞同口径）
export function pickAwaitingAsk(candidates: AwaitingAskCandidate[],
  callId: string): AwaitingAskCandidate | null {
  for (const candidate of candidates) {
    const parsed: AskWaitPayload | null = parseAskWaitPayload(candidate.waitContent);
    if (parsed !== null && parsed.toolCallId === callId) {
      return candidate;
    }
  }
  return null;
}

export class ChatAskResumeCtrl {
  private refs: ChatSendRefs;
  private host: ChatAskResumeHost;

  constructor(refs: ChatSendRefs, host: ChatAskResumeHost) {
    this.refs = refs;
    this.host = host;
  }

  // ── ⓪答案上行统一入口（ChatSendCtrl.resolveAsk 单点转接——三路分流）──

  // 分流：①放弃标记（等待卡放弃键经统一通道提交，单源 ChatMessageCompose.ASK_ABANDON_MARK）
  // → 放弃路（同进程停止链 / 跨进程库侧收口）；②同进程有内存桥 → 原内存续跑通道逐字零改动；
  // ③无桥（重进后等待卡）→ 库侧续答编排。①判先于②——放弃标记不得落进内存桥被当答案续跑
  resolveAsk(callId: string, answerJson: string): void {
    if (answerJson === ASK_ABANDON_MARK) {
      this.abandonAsk(callId);
      return;
    }
    if (toolRuntime.hasPendingAsk(callId)) {
      toolRuntime.resolveAsk(callId, answerJson);
      return;
    }
    this.resumeAsk(callId, answerJson);
  }

  // ── ①挂起（ask 等待族；ChatToolRoundCtrl.ask 分支经宿主薄直通消费）──

  // 提问挂起（ask 轮专用 lane 段）：①挂交互桥等用户作答（resolve 经 ToolRuntime.resolveAsk
  // 上行，答案 JSON 串）——**先于落库登记**，防「插卡 → 等待行落库」窗口内的作答被
  // resolveAsk 静默吞；②等待行落库（异步 fire-and-forget——插 streaming tool 行 +
  // run→awaiting_input 同 CAS 事务，登记表在写侧，结算/中止两路经 commitToolNode 自动改走
  // 「更新既有等待行」）。落库失败不阻断等答（退化 = 域⑤ 前语义：进程死亡无等待卡，收口
  // 走插行老路；hilog 留痕在写侧）
  beginAskWait(conversationId: string, callId: string, recordJson: string,
    stepIndex: number): Promise<string> {
    const lane: Promise<string> = toolRuntime.waitAsk(conversationId, callId);
    this.host.beginAskWaitRow(callId, recordJson, stepIndex).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, '提问等待行落库异常：%{public}s', (e as Error).message);
    });
    return lane;
  }

  // 确认等待行落库（2128 笔）：与 ask 共用同一等待行机制（插 streaming 行 + run→
  // awaiting_input），差别只在载荷（确认卡暂停态编进 result 位，见 ChatConfirmWait）与
  // 无 lane——确认的 Promise 由工具轮自己持有，这里只负责落行。
  // 落库失败不阻断等答（退化 = 旧语义：进程死亡后确认卡退回普通工具卡，收口走插行老路）
  beginConfirmWait(conversationId: string, callId: string, recordJson: string,
    stepIndex: number): void {
    if (conversationId === '') {
      return;
    }
    this.host.beginAskWaitRow(callId, recordJson, stepIndex).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, '确认等待行落库异常：%{public}s', (e as Error).message);
    });
  }

  // ── ②跨重启续答（ChatSendCtrl.resolveAsk 无内存挂起时路由到此）──

  // 续答入口（重进后的提问卡提交答案）：守卫 → 库材料读（awaiting_input run 的等待行）→
  // 按 callId 匹配 → 回填链。守卫语义与重试域同位（sending 拒单 / 连接未配置提示）；
  // 匹配不到静默吞（已答/已中止的卡重复提交属误触）
  resumeAsk(callId: string, answerJson: string): void {
    this.resumeWaiting(callId, answerJson);
  }

  // 确认卡跨重启作答（2128 笔；ChatSendCtrl.resolveBrowseConfirm 无内存桥时路由到此）：
  // 用户决定作为工具结果回填并重建起轮——允许文案明说「执行环境已中断、操作没发生」，
  // 拒绝沿用 browse_act 的拒绝文案（模型不得原样重试）。等待行匹配不到静默吞（已答/已中止）
  resumeConfirm(callId: string, approved: boolean): void {
    this.resumeWaiting(callId, approved ? confirmApprovedAfterRestartResult() :
      browseActDeniedResult());
  }

  // 续答共用体（ask 答案 / 确认决定同一条库侧回填链；两入口只是载荷不同）
  private resumeWaiting(callId: string, answerJson: string): void {
    if (this.host.isDisposed() || !this.host.isDbReady()) {
      return;
    }
    if (this.host.isSending()) {
      this.host.toast('当前会话已有进行中的回复，请等待完成或先停止');
      return;
    }
    const conn: AiConnection | null = this.refs.conn();
    if (conn === null) {
      this.host.toast('请先在「设置 > 服务商管理」完善服务商（接口地址、密钥与模型）');
      return;
    }
    const convId: string = this.host.conversationId();
    graphAwaitingAskCandidates(convId)
      .then((candidates: AwaitingAskCandidate[]): void => {
        if (this.host.isDisposed()) {
          return;
        }
        const unit: AwaitingAskCandidate | null = pickAwaitingAsk(candidates, callId);
        if (unit === null) {
          return; // 不在场（已答/已中止）——静默吞
        }
        this.runResume(conn, unit, answerJson);
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '等待提问读取失败：%{public}s', (e as Error).message);
        this.host.toast('读取这条提问失败，请稍后重试');
      });
  }

  // 续答主体（编排序 = 重试域 retryGraph 同款骨架）：接管 run → 置发送态 → 路由装载 →
  //（blocked 早退）→ ①等待行回填终态（CAS 更新 + run 转 running，同一提交）→ ②事实
  // result_confirmed → ③屏上等待卡升级终态（笔1 渲染分支同构三写）→ ④承载行 + 起流复位 +
  // 组装起轮（复用重试组装段——以回放视图重建请求，ask 结果行已在重建链内自然配对）。
  // 任一步失败呈报并归还占用（不静默、不留半成品）；窗口守卫（disposed/token）与重试域同位
  private runResume(conn: AiConnection, unit: AwaitingAskCandidate, answerJson: string): void {
    const runId: string = unit.runId;
    if (!this.host.acquireResumeRun(runId, unit.attemptEpoch)) {
      this.host.toast('当前会话已有进行中的回复，请等待完成或先停止');
      return;
    }
    const roundToken: string = this.host.currentRunToken();
    this.host.setSending(true);
    this.host.ensureGraphRoute()
      .catch((): void => undefined)
      .then((): void => {
        if (this.host.isDisposed() || roundToken === '' ||
          roundToken !== this.host.currentRunToken()) {
          return; // 路由装载窗口内被停止/销毁——占用随收尾释放
        }
        // 旧格式墓碑会话拒写（与发送/重试入口同源同判据同文案）
        if (this.host.routeState() === ROUTE_BLOCKED) {
          this.host.toast(TOMBSTONE_TOAST_TEXT);
          this.host.setSending(false);
          this.host.releaseRunWithGuard();
          return;
        }
        // ①等待行回填终态：CAS 更新既有等待行（谓词 status='streaming'——行已变化即拒）+
        // run 写回 running（同一事务）。载荷 = 答案 + 原 toolCallId 保真沿用（见
        // buildAskSettledRecordJson）；graphCommitNode 就地推进句柄 revision（接管用）
        const fallbackCallId: string = nextMessageId('call');
        const settledJson: string = buildAskSettledRecordJson(unit.waitContent, answerJson,
          fallbackCallId);
        const handle: GraphRunHandle = {
          runId: runId, branchId: unit.branchId, revision: unit.runRevision
        };
        graphCommitNode(handle, 'tool', settledJson, '', unit.maxStepIndex + 1,
          nextRowCreatedAt(), ORIGIN_SEND, 'done', unit.waitNodeId)
          .then((ref: GraphNodeRef | null): void => {
            // ★ 2026-10-16 重启续答冻结修复笔：等待行提交已落定（CAS 命中或行已变）——run
            // 离开 awaiting_input，清启动恢复集标记（两结局同清；置于守卫之前，被停止/销毁
            // 窗口也照清）
            chatSessionRuntime.clearRestoredAwaiting(this.host.conversationId());
            if (this.host.isDisposed() || roundToken !== this.host.currentRunToken()) {
              return;
            }
            if (ref === null) {
              this.host.toast('这条提问的状态已变化，请刷新会话后重试');
              this.host.setSending(false);
              this.host.releaseRunWithGuard();
              return;
            }
            // ②句柄接管（此后本轮提交沿该 run 的 revision/步序续号）
            this.host.adoptResumeRun(runId, unit.branchId, handle.revision,
              unit.maxStepIndex + 1);
            // ③事实确认（factId 空 = 意图未落成，静默跳过——与既有口径同；fire-and-forget，
            // 失败不阻断续跑）
            if (unit.factId !== '') {
              graphToolFactAdvance(unit.factId, runId, '', '', 'result_confirmed', '',
                answerJson).catch((e: Object): void => {
                hilog.warn(DOMAIN, TAG, '续答事实确认失败：%{public}s', (e as Error).message);
              });
            }
            // ④屏上等待卡升级终态（与串行 lane 结算同构：state/输出/摘要三写；toolOutputJson
            // 写**原始载荷**——回放卡同源口径，且 buildRequestHistory 直接读它进协议）
            const card: ChatMessage | null = this.host.dataSource().findMessage(unit.waitNodeId);
            if (card !== null && card.toolState === 'running') {
              card.toolState = 'done';
              card.toolOutputJson = answerJson;
              card.toolDisplayText = compactPreview(answerJson, 60);
              this.host.dataSource().refreshDisplay();
            }
            // ⑤承载行 + 起流 + 组装起轮（anchor = run 输入锚——已证明身份；beginDisplayRound
            // 对已登记轮只补归属，未登记（异常窗口）才注册 running）
            const holder: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
            holder.createdAt = nextRowCreatedAt();
            holder.streaming = true;
            holder.live = true; // 实时行标记（A3）：id 为内存 id，图身份只认收尾 stampNodeRef 回填
            holder.modelLabel = conn.model;
            this.host.dataSource().beginDisplayRound(roundToken, unit.inputAnchorMessageId,
              holder);
            this.host.dataSource().push(holder);
            this.host.beginResumeStreaming(holder.id);
            this.host.launchResumeRound(conn, roundToken);
          })
          .catch((e: Object): void => {
            hilog.error(DOMAIN, TAG, '续答回填失败：%{public}s', (e as Error).message);
            this.host.toast('这次回答没有保存上，请重进会话再试');
            this.host.setSending(false);
            this.host.releaseRunWithGuard();
          });
      });
  }

  // ── ③放弃口（等待卡「放弃」键上行；ChatSendCtrl.abandonAsk 薄委托到此）──

  // 放弃等待（两路分流）：①同进程有内存桥在途 → 走既有停止链（abort 的跨域分发：挂起取消 +
  // 中止卡落库 + run 收口 stopped——用户在场，语义即「停止本轮」）；②无桥（重进后的等待卡，
  // 桥随进程死亡已丢）→ 库侧收口（等待行置中止态 + run interrupted——豁免清算后必须有显式
  // 收口口防永挂，见 ChatDbSweep ④ 段）。匹配不到静默吞（已答/已中止）
  abandonAsk(callId: string): void {
    if (this.host.isDisposed()) {
      return;
    }
    if (toolRuntime.hasPendingAsk(callId)) {
      this.host.abortRound();
      return;
    }
    if (!this.host.isDbReady()) {
      return;
    }
    const convId: string = this.host.conversationId();
    graphAwaitingAskCandidates(convId)
      .then((candidates: AwaitingAskCandidate[]): void => {
        if (this.host.isDisposed()) {
          return;
        }
        const unit: AwaitingAskCandidate | null = pickAwaitingAsk(candidates, callId);
        if (unit === null) {
          return;
        }
        this.runAbandon(unit);
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '放弃读取失败：%{public}s', (e as Error).message);
        this.host.toast('放弃这条提问失败，请稍后重试');
      });
  }

  // 放弃主体（库侧收口，不占运行占用——不开流不组装）：等待行 CAS 置中止态（cancelled
  // 载荷 → 回放走域① 渲染分支显「已中止」）→ run 收口 interrupted（域① 值域；finishRun
  // 终态谓词只排终态四值，对 awaiting_input 停留态行天然放行）→ 事实 failed → 屏上三写 +
  // 轮事实 settle stopped
  private runAbandon(unit: AwaitingAskCandidate): void {
    const payload: string = abandonedAskResult();
    const handle: GraphRunHandle = {
      runId: unit.runId, branchId: unit.branchId, revision: unit.runRevision
    };
    graphCommitNode(handle, 'tool', payload, '', unit.maxStepIndex + 1, nextRowCreatedAt(),
      ORIGIN_SEND, 'done', unit.waitNodeId)
      .then((ref: GraphNodeRef | null): void => {
        // ★ 2026-10-16 重启续答冻结修复笔：放弃提交已落定——同清启动恢复集标记（两结局同清）
        chatSessionRuntime.clearRestoredAwaiting(this.host.conversationId());
        if (this.host.isDisposed()) {
          return;
        }
        if (ref === null) {
          this.host.toast('这条提问的状态已变化，请刷新会话后重试');
          return;
        }
        // run 收口 interrupted（fire-and-forget 链内不吞错：hilog 留痕，屏上状态照常落）
        graphFinishRun(handle, false, '', RUN_STATUS_INTERRUPTED)
          .catch((e: Object): void => {
            hilog.warn(DOMAIN, TAG, '放弃收口失败：%{public}s', (e as Error).message);
          });
        if (unit.factId !== '') {
          graphToolFactAdvance(unit.factId, unit.runId, '', '', 'failed', '', payload)
            .catch((e: Object): void => {
              hilog.warn(DOMAIN, TAG, '放弃事实收口失败：%{public}s', (e as Error).message);
            });
        }
        const card: ChatMessage | null = this.host.dataSource().findMessage(unit.waitNodeId);
        if (card !== null && card.toolState === 'running') {
          card.toolState = 'cancelled';
          card.toolOutputJson = payload;
          card.toolDisplayText = '已中止';
        }
        // 轮事实收口（interrupted 经 display 词表 → stopped；仅已登记 running 轮可结算）
        this.host.dataSource().settleDisplayRound(
          this.host.conversationId() + '|' + unit.runId, 'stopped');
        this.host.dataSource().refreshDisplay();
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '放弃写入失败：%{public}s', (e as Error).message);
        this.host.toast('放弃这条提问失败，请稍后重试');
      });
  }
}

// ── 续答域宿主桥接（★ U11 域⑤ 2026-10-16）──
// ChatSendCtrl 构造本域件时以本桥替代 this 直传（照 ChatFlowHostBridge 先例形态：宿主类
// 声明不挂本接口，运行隔离态/发送编排经公共方法回接，refs 面直持）。**为何与域件同文件**：
// ChatSendCtrl 贴 1200 硬线期接入面须最小化（单 import + 单构造行），桥与域件职责同源
// （宿主面的翻译层）——并入既有同域件优先于新开文件。依赖方向：本桥 → ChatSendCtrl 仅
// **type-only**（编译期擦除无运行时环——ChatSendRefs 先例同款）；→ ChatGraphWriteCtrl
//（图写侧两口）单向。
// 宿主编排面（结构接口——桥接件对 ChatSendCtrl 的运行面引用收敛于此：ChatSendCtrl 对本件
// 是运行时 import，本件再 import 它即成环；接口结构与彼件公共方法逐一同形，传 this 即满足）
export interface SendCtrlOrchestration {
  isDisposed(): boolean;
  beginRunAcquire(adoptRunId: string, attemptEpoch: number): boolean;
  currentRunToken(): string;
  releaseRunWithGuard(): void;
  ensureGraphRoute(): Promise<void>;
  routeState(): string;
  beginRetryStreaming(msgId: string): void;
  launchRetryRound(conn: AiConnection, roundToken: string): void;
  abort(): void;
}

export class ChatAskResumeBridge implements ChatAskResumeHost {
  private refs: ChatSendRefs;
  private send: SendCtrlOrchestration;
  private graphWrite: ChatGraphWriteCtrl;

  constructor(refs: ChatSendRefs, send: SendCtrlOrchestration, graphWrite: ChatGraphWriteCtrl) {
    this.refs = refs;
    this.send = send;
    this.graphWrite = graphWrite;
  }

  isDisposed(): boolean {
    return this.send.isDisposed();
  }

  isSending(): boolean {
    return this.refs.sending();
  }

  isDbReady(): boolean {
    return this.refs.dbReady();
  }

  conversationId(): string {
    return this.refs.conversationId();
  }

  toast(message: string): void {
    this.refs.toast(message);
  }

  dataSource(): ChatDataSource {
    return this.refs.dataSource;
  }

  setSending(sending: boolean): void {
    this.refs.setSending(sending);
  }

  // 续答接管接纳（走宿主既有接纳闸的接管形态——RunScope.adopt 非新铸造，同会话第二活跃
  // run 拒单语义不变）
  acquireResumeRun(runId: string, attemptEpoch: number): boolean {
    return this.send.beginRunAcquire(runId, attemptEpoch);
  }

  currentRunToken(): string {
    return this.send.currentRunToken();
  }

  releaseRunWithGuard(): void {
    this.send.releaseRunWithGuard();
  }

  ensureGraphRoute(): Promise<void> {
    return this.send.ensureGraphRoute();
  }

  routeState(): string {
    return this.send.routeState();
  }

  // 起流复位段与组装段（复用重试域两法——「禁第二条请求链」组装单源）
  beginResumeStreaming(msgId: string): void {
    this.send.beginRetryStreaming(msgId);
  }

  launchResumeRound(conn: AiConnection, roundToken: string): void {
    this.send.launchRetryRound(conn, roundToken);
  }

  // 等待行落库（图写侧直连——插 streaming tool 行 + run→awaiting_input 同 CAS 事务）
  beginAskWaitRow(toolCallId: string, recordJson: string,
    stepIndex: number): Promise<string> {
    return this.graphWrite.beginAskWaitRow(toolCallId, recordJson, stepIndex);
  }

  // 续答句柄接管（图写侧直连——本轮流提交沿既有 run 的 revision/步序续号）
  adoptResumeRun(runId: string, branchId: string, revision: number, stepSeq: number): void {
    this.graphWrite.adoptRun(runId, branchId, revision, stepSeq, this.refs.conversationId());
  }

  // 同进程放弃口（复用既有停止链——abort 的跨域分发）
  abortRound(): void {
    this.send.abort();
  }
}
