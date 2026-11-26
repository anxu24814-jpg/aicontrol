// 历史展示轮事实装配。域定义一句话：**按当前页消息装配展示轮事实（run 终态索引 + 本批
// id→轮 id 映射）的页面寿命读缓存**——历史消息的轮状态来自 generation_runs（MessageRow.
// status 不能判断历史生成成功：commitRunUnit 写出的节点 status 固定 done，失败终答也如此；
// 真正轮终态 = run.status，由 graphFinishRun 写 finished/failed）。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话成立（历史侧轮事实唯一读装配）；
//   ②不并入 ChatDisplayProjection——那是零 I/O 的纯投影件，本件持读缓存与装载代次；不并入
//   ChatPageLoad——该件已肩加载编排（连接解析/历史拉取/翻页），读缓存与代次防回填语义独立
//   成域；③实逻辑非转接壳（索引装载 / 代次防回填 / 失败降级全在此）。
// · 读纪律：queryRunRowsByConversation 是**全会话 run 查询**（初载一次，O(会话 run 数)——
//   非固定 50 条；禁止每 token、每 refreshDisplay 或每段查询），失败不作为成功缓存（下次
//   显式加载再试，不自动重试循环）；queryTraceMessagesByIds 每批仅传本页原始 MessageRow.id
//  （不传合成 think-id），构建 id→runId 映射后立即丢弃返回正文等多余字段。缓存只留
//   Map<runId, HistoryRoundInfo> 必要索引（状态 + **可信耗时**〔时间值经可信度纯函数
//   trustedRoundDurationMs 判定后才留〕+ startMs = run.createdAt〔回放侧轮起始时刻的权威
//   事实〕），不保留 content/diagnostic 全文与时间原始列（updatedAt 仅耗时判定瞬用不留）。
// · 代次（generation）：每次「首载 / 手动刷新 / 分支换源」开启新代次并清旧索引（旧批异步
//   结果按代次作废，不把旧批写进新分支）；loadOlder 沿当前代次复用。调用方（ChatPageLoadCtrl）
//   在异步完成面复核 isCurrent(gen) 与数据源 isDisplayDisposed()。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MessageRow } from '../../common/store/ChatDb';
import { queryRunRowsByConversation, queryTraceMessagesByIds } from '../../common/store/SessionTraceDb';
import { TraceRowIn, TraceRunIn } from '../../common/chat/SessionTraceModel';
import { trustedRoundDurationMs } from '../../common/chat/ChatAnswerChoice';
import { DisplayRoundStatus } from './ChatMessageCompose';
import { DisplayRoundFacts } from './ChatDisplayProjection';

// 一批消息的装配结果：facts = 本批涉及 run 的展示轮事实（装进数据源轮事实表）；
// roundIdByMsgId = 本批行 id → 展示轮 id（投影映射入参）；degraded = 任一增强读取失败
//（调用方据此给一次中性 toast，本批缺失事实降级 unknown、正文照常加载）。
// ★ diagNotices = 本批涉及轮的诊断通知合成料（读路径合成轻路线——诊断节点在 DB 挂输入
//   锚、不在 head 读路径上，此处按 run.diagnosticMessageId 反查节点正文交安装层在轮末
//   合成 notice 行，不进 DB 链）
export interface DisplayRoundBatch {
  facts: DisplayRoundFacts[];
  roundIdByMsgId: Map<string, string>;
  degraded: boolean;
  diagNotices: DiagNoticeItem[];
}

// 诊断通知合成料：roundId = 该轮展示 id（安装层定位轮末条）；noticeId = 诊断节点 id
//（合成消息 id——稳定，重装幂等去重的键）；content = 节点正文
export interface DiagNoticeItem {
  roundId: string;
  noticeId: string;
  content: string;
}

// 全会话 run 索引项（一次全会话读同时算出并缓存；缓存只保这几字段，不保诊断全文/正文/
// 时间原始列）：status = run.status 映射；durationMs = 可信耗时（经 trustedRoundDurationMs
// 判定）；startMs = run.createdAt（回放侧轮起始时刻的权威事实——普通轮 = 派发时刻、重试轮
// = 重试时刻、主动消息轮 = 生成派发时刻；>0 才留，消费方 = 展示投影 alignRoundStartTimes
// 经轮事实 startMs 中转）；diagnosticId = run.diagnosticMessageId（非空才留——诊断行读路径
// 合成的索引键；节点正文按 id 现查不留缓存）
export interface HistoryRoundInfo {
  status: DisplayRoundStatus;
  durationMs?: number;
  startMs?: number;
  diagnosticId?: string;
}

// run.status → 展示轮状态：finished→done、failed→error、stopped/interrupted→stopped，
// 其它一切值（缺行、坏值）→ unknown（不伪报成功）。
// ★ stopped/interrupted 映射——新写停止轮重进显「已停止」不再误报「处理未完成」；
// **存量 failed 不回刷**（历史停止与失败都混存于 failed，无法区分，维持 error 语义——
// 红线：display 层新值只影响新写入）。
// ★ 同进程重进兜底：running/prepared → stopped——回放视角遇非终态 run 恒为中断轮
//（U9 解耦笔起退页不断流〔release 只解绑不掐流〕，同进程退页重进恒走重挂路不落本函数；
// 本映射只剩运行态被回收后重进与跨进程启动前残留两窗——跨进程启动即被 sweepStaleGraphRuns
// 收口 interrupted），配合同轮 streaming 占位行的半截正文按「已中断 + 半截内容」呈现。
// ★ awaiting_input → running：等待用户输入的轮是**活跃轮**——等待卡可作答、答后续跑同一
// run（续答件回填后本映射随 run 转 running 而恒真），不是中断轮；映射 running 同时给段投影
// preview 模式（等待项恒显）并在续答收口时放行 settleDisplayRound 的「已登记且 running」
// 结算谓词（映射 stopped/unknown 都会让续答完成后的轮事实 settle 不上）
export function mapTraceRunStatus(status: string): DisplayRoundStatus {
  if (status === 'finished') {
    return 'done';
  }
  if (status === 'failed') {
    return 'error';
  }
  if (status === 'stopped' || status === 'interrupted' ||
    status === 'running' || status === 'prepared') {
    return 'stopped';
  }
  if (status === 'awaiting_input') {
    return 'running'; // ★ 等待输入非中断（见上注）
  }
  return 'unknown';
}

export class ChatDisplayHistory {
  // 装载代次（beginLoad 前进；异步完成面复核）
  private generation: number = 0;
  private disposed: boolean = false;
  private conversationId: string = '';
  // 全会话 run 索引（初载一次；失败不缓存——见 ensureRunIndex）：值 = 状态 + 可信耗时 +
  // startMs + diagnosticId（同一次全会话读算出）
  private runStatus: Map<string, HistoryRoundInfo> | null = null;
  // 索引 Promise 复用（防并行两批各发一次全量读）
  private runIndexPromise: Promise<Map<string, HistoryRoundInfo> | null> | null = null;

  // 开启新装载代次（首载 / 手动刷新 / 分支换源）：代次前进 + 清旧索引（旧批异步结果按代次
  // 作废）。返回本代次号随链下传。
  beginLoad(conversationId: string): number {
    this.generation++;
    this.runStatus = null;
    this.runIndexPromise = null;
    this.conversationId = conversationId;
    return this.generation;
  }

  // 当前代次（loadOlder 沿当前代次复用；0 = 从未装载——调用方跳过装配，事实降级 unknown）
  currentGen(): number {
    return this.generation;
  }

  // 是否当前有效代次（异步完成面复核：代次 + 销毁两问）
  isCurrent(gen: number): boolean {
    return !this.disposed && gen > 0 && gen === this.generation;
  }

  // 页面寿命释放（数据源 disposeDisplayState 经释放回调调用——先停写者后清索引/代次）
  dispose(): void {
    this.disposed = true;
    this.generation++;
    this.runStatus = null;
    this.runIndexPromise = null;
  }

  // 一批消息的轮事实装配（初载与翻页两路共用）：run 索引（初载一次）+ 本批 id→runId（每批
  // 一次）。两口可并行；任一路失败降级（degraded = true，缺失事实 unknown），按 id 读取成功
  // 而 run 读取失败时保留已证明的轮 id 用于断段（状态 unknown）。代次失效/已销毁回 null
  //（调用方丢弃本批，不写回）。
  // ★ 第三路：诊断通知合成料——本批涉及轮里「终态非 done 且带诊断节点」的 run（error/
  // stopped 映射态），按 diagnosticId 批查节点正文（queryTraceMessagesByIds 一次 IN 查询；
  // 只认 role='notice' 行），正文非空才入 diagNotices。诊断内容读取失败 fail-open（hilog
  // 留痕、无该行——通知是增强信息，缺席不阻断正文，不计 degraded）
  assemble(rows: MessageRow[], gen: number): Promise<DisplayRoundBatch | null> {
    if (!this.isCurrent(gen)) {
      return Promise.resolve(null);
    }
    const ids: string[] = [];
    for (const row of rows) {
      ids.push(row.id);
    }
    const statusPromise: Promise<Map<string, HistoryRoundInfo> | null> =
      this.ensureRunIndex(gen);
    const idsPromise: Promise<Map<string, string> | null> = ids.length === 0 ?
      Promise.resolve(new Map<string, string>()) : queryTraceMessagesByIds(ids)
        .then((traceRows: TraceRowIn[]): Map<string, string> => {
          // 只取 id→runId 映射，返回正文、时间等多余字段立即丢弃（读纪律）
          const byId: Map<string, string> = new Map();
          for (const row of traceRows) {
            if (row.runId !== undefined && row.runId !== '') {
              byId.set(row.id, row.runId);
            }
          }
          return byId;
        })
        .catch((e: Object): Map<string, string> | null => {
          hilog.warn(0xD5A0, 'ChatDisplayHistory', '本批轮 id 读取失败（本批状态降级 unknown）：%{public}s',
            (e as Error).message);
          return null;
        });
    // 诊断通知合成料的收集表——轮命中态在下方 Promise.all 的 then 内基于两表构建
    const diagIds: string[] = [];
    const diagRoundOf: Map<string, string> = new Map();
    return Promise.all([statusPromise, idsPromise])
      .then((both: [Map<string, HistoryRoundInfo> | null, Map<string, string> | null]):
        Promise<DisplayRoundBatch | null> => {
        if (!this.isCurrent(gen)) {
          return Promise.resolve(null);
        }
        const statusIndex: Map<string, HistoryRoundInfo> | null = both[0];
        const runOfMsg: Map<string, string> | null = both[1];
        const cid: string = this.conversationId;
        const roundIdByMsgId: Map<string, string> = new Map();
        const facts: DisplayRoundFacts[] = [];
        const seen: Set<string> = new Set();
        if (runOfMsg !== null) {
          runOfMsg.forEach((runId: string, msgId: string): void => {
            const roundId: string = cid + '|' + runId;
            roundIdByMsgId.set(msgId, roundId);
            if (seen.has(roundId)) {
              return;
            }
            seen.add(roundId);
            const indexed: HistoryRoundInfo | undefined =
              statusIndex !== null ? statusIndex.get(runId) : undefined;
            const status: DisplayRoundStatus = indexed !== undefined ? indexed.status : 'unknown';
            // 历史 inputAnchorId 默认空（不额外遍历父链；恢复操作点击时复用既有精确解析）
            const fact: DisplayRoundFacts = { id: roundId, status: status, inputAnchorId: '' };
            // 可信耗时随索引一并装入（undefined = 无可信结束事实——显示面完全隐藏）
            if (indexed !== undefined && indexed.durationMs !== undefined) {
              fact.durationMs = indexed.durationMs;
            }
            // 轮起始时刻随索引一并装入（undefined = 无 run 事实，回放侧保持库行时刻——
            // 消费链见 DisplayRoundFacts.startMs 注释）
            if (indexed !== undefined && indexed.startMs !== undefined) {
              fact.startMs = indexed.startMs;
            }
            facts.push(fact);
            // 诊断通知合成料收集：终态非 done（error/stopped）且索引带诊断 id 的轮
            if (indexed !== undefined && (status === 'error' || status === 'stopped') &&
              indexed.diagnosticId !== undefined && indexed.diagnosticId !== '') {
              if (!diagRoundOf.has(indexed.diagnosticId)) {
                diagIds.push(indexed.diagnosticId);
                diagRoundOf.set(indexed.diagnosticId, roundId);
              }
            }
          });
        }
        if (diagIds.length === 0) {
          const emptyBatch: DisplayRoundBatch = { facts: facts, roundIdByMsgId: roundIdByMsgId,
            degraded: statusIndex === null || runOfMsg === null, diagNotices: [] };
          return Promise.resolve(emptyBatch);
        }
        return queryTraceMessagesByIds(diagIds)
          .then((diagRows: TraceRowIn[]): DisplayRoundBatch => {
            const diagNotices: DiagNoticeItem[] = [];
            for (const row of diagRows) {
              if (row.role !== 'notice' || row.content === '') {
                continue;
              }
              const roundId: string | undefined = diagRoundOf.get(row.id);
              if (roundId === undefined) {
                continue;
              }
              diagNotices.push({ roundId: roundId, noticeId: row.id, content: row.content });
            }
            const batch: DisplayRoundBatch = { facts: facts, roundIdByMsgId: roundIdByMsgId,
              degraded: statusIndex === null || runOfMsg === null, diagNotices: diagNotices };
            return batch;
          })
          .catch((e: Object): DisplayRoundBatch => {
            // fail-open：诊断行缺席不阻断正文（增强信息，宁缺不阻断）
            hilog.warn(0xD5A0, 'ChatDisplayHistory', '诊断通知内容读取失败（本批跳过诊断行）：%{public}s',
              (e as Error).message);
            const batch: DisplayRoundBatch = { facts: facts, roundIdByMsgId: roundIdByMsgId,
              degraded: statusIndex === null || runOfMsg === null, diagNotices: [] };
            return batch;
          });
      });
  }

  // run 终态索引（初载一次；Promise 复用防并行两批各发一次全量读；失败不作为成功缓存——
  // 清 Promise 待下次显式加载再试）：同一次全会话读同时算状态映射与可信耗时
  //（trustedRoundDurationMs——failed 无诊断即不可信，防启动清扫伪长耗时）
  private ensureRunIndex(gen: number): Promise<Map<string, HistoryRoundInfo> | null> {
    if (this.runStatus !== null) {
      return Promise.resolve(this.runStatus);
    }
    if (this.runIndexPromise !== null) {
      return this.runIndexPromise;
    }
    const cid: string = this.conversationId;
    const pending: Promise<Map<string, HistoryRoundInfo> | null> =
      queryRunRowsByConversation(cid)
        .then((runs: TraceRunIn[]): Map<string, HistoryRoundInfo> | null => {
          if (!this.isCurrent(gen)) {
            return null;
          }
          const map: Map<string, HistoryRoundInfo> = new Map();
          for (const run of runs) {
            const info: HistoryRoundInfo = { status: mapTraceRunStatus(run.status) };
            const durationMs: number | undefined = trustedRoundDurationMs({
              status: run.status,
              diagnosticMessageId: run.diagnosticMessageId,
              createdAt: run.createdAt,
              updatedAt: run.updatedAt
            });
            if (durationMs !== undefined) {
              info.durationMs = durationMs;
            }
            // 轮起始时刻：run.createdAt > 0 才留（缺值 fail-open——回放侧保持库行时刻，
            // 见 DisplayRoundFacts.startMs 注释）
            if (run.createdAt > 0) {
              info.startMs = run.createdAt;
            }
            // 诊断节点索引键（读路径合成）：非空才留——正文按 id 现查不缓存（读纪律）
            if (run.diagnosticMessageId !== '') {
              info.diagnosticId = run.diagnosticMessageId;
            }
            map.set(run.id, info);
          }
          this.runStatus = map; // 成功才缓存
          return map;
        })
        .catch((e: Object): Map<string, HistoryRoundInfo> | null => {
          hilog.warn(0xD5A0, 'ChatDisplayHistory', '会话 run 索引读取失败（本批状态降级 unknown）：%{public}s',
            (e as Error).message);
          if (this.isCurrent(gen)) {
            this.runIndexPromise = null; // 失败不作成功缓存（下次显式加载再试，不自动重试）
          }
          return null;
        });
    this.runIndexPromise = pending;
    return pending;
  }
}
