// SessionTraceModel.ets — 会话轨迹组装纯函数
// 职责：把「消息尾窗行 + run 编年 + 工具事实 + 轮级用量 + 诊断补行」确定性地组装成
// 「轮 → 记录行 → 简化条段」只读模型（零 UI、零 DB import 的纯函数叶子——断言可剥 TS 直跑；
// 取数在 store 侧 SessionTraceDb，本件不碰 IO）。
// 语义要点：
//   · 轮 = generation_runs 一行；轮号 = 会话内 run 按 createdAt 升序序号（窗口外旧轮仍占号，
//     无行不建组）；runId 空/悬空的遗留行归末尾「未分组」段（turnNo = 0，fail-safe 可见不吞）。
//   · 记录行排序 = stepIndex 升序（null 殿后——诊断/边界行天然落尾），同键按 createdAt、id 升序。
//   · 工具卡与事实无外键：数量相等才按序一一配对 + 逐对校验 payload 与卡行 argsJson 同文，
//     对不齐不猜（时长/事实态不显示、「—」由 UI 呈现）。
//   · 中止判定读 abortedToolResult() 现形产物特征（结果 JSON 的 cancelled 键，禁抄文案字面量）。
//   · 诊断节点不在 head 读路径上，由调用方按 run.diagnosticMessageId 反查补行传入，本件按
//     runId 并入对应轮组。

// ── 值域常量（本域单源）──
export const TRACE_KIND_USER: string = 'user';
export const TRACE_KIND_ASSISTANT: string = 'assistant';
export const TRACE_KIND_TOOL: string = 'tool';
export const TRACE_KIND_NOTICE: string = 'notice';
export const TRACE_KIND_SUMMARY: string = 'summary';
export const TRACE_KIND_CLEAR: string = 'clear';

export const TRACE_STATUS_DONE: string = 'done';
export const TRACE_STATUS_FAILED: string = 'failed';
export const TRACE_STATUS_RUNNING: string = 'running';
export const TRACE_STATUS_ABORTED: string = 'aborted';

export const TRACE_SEG_USER: string = 'user';
export const TRACE_SEG_ASSISTANT: string = 'assistant';
export const TRACE_SEG_TOOL: string = 'tool';
export const TRACE_SEG_FAILED: string = 'failed';

// 记录行标题（内置角色名与边界行文案——UI 展示与帮助/断言核对共用单源）
export const TRACE_TITLE_USER: string = '用户';
export const TRACE_TITLE_ASSISTANT: string = '助手';
export const TRACE_TITLE_TOOL_FALLBACK: string = '工具';
export const TRACE_TITLE_NOTICE: string = '诊断';
export const TRACE_TITLE_SUMMARY: string = '上下文已压缩';
export const TRACE_TITLE_CLEAR: string = '上下文已清空';

// 摘要截断上限（user 80 / assistant 80 / tool 参数 60 + 结果首行 60）
export const TRACE_TEXT_USER_MAX: number = 80;
export const TRACE_TEXT_ASSISTANT_MAX: number = 80;
export const TRACE_TOOL_ARGS_MAX: number = 60;
export const TRACE_TOOL_RESULT_MAX: number = 60;

// 中止标记键（abortedToolResult() 产物的现形特征键；模型与产品侧同一契约键，禁抄文案字面量）
export const TRACE_ABORT_MARK_KEY: string = 'cancelled';

// ── 输入契约（结构性接口；store 行类型字段为其超集，直接传入）──
export interface TraceRowIn {
  id: string;
  role: string; // user / assistant / tool / summary / clear / notice
  content: string;
  createdAt: number;
  runId: string;
  stepIndex: number | null;
}

export interface TraceRunIn {
  id: string;
  status: string; // prepared / running / finished / failed
  diagnosticMessageId: string;
  createdAt: number;
  updatedAt: number;
}

export interface TraceFactIn {
  id: string;
  runId: string;
  state: string; // prepared / dispatch_intent / result_confirmed / failed
  payload: string;
  result: string;
  createdAt: number;
  finishedAt: number; // v54；0 = 无终态时刻
}

export interface TraceUsageIn {
  runId: string;
  promptTokens: number;
  cachedTokens: number;
  completionTokens: number;
  totalTokens: number;
  durationMs: number;
  firstTokenMs: number;
}

// ── 输出契约（任务书 §4.2）──
export interface TraceUsage {
  promptTokens: number;
  cachedTokens: number;
  completionTokens: number;
  totalTokens: number;
  durationMs: number;
  firstTokenMs: number;
}

export interface TraceRecord {
  id: string; // 行键（Repeat 键只用它）
  kind: string;
  title: string;
  summary: string;
  timeMs: number;
  durationMs: number; // 本行可归因时长（0 = 无——UI 依 status 呈现「执行中」或「—」）
  status: string;
  factRef: string; // 关联工具事实 id（'' = 无/对不齐）
}

export interface TraceSegment {
  kind: string;
  t0: number;
  t1: number;
  failed: boolean;
}

export interface TraceTurn {
  runId: string; // '' = 未分组段
  turnNo: number; // 1 起；未分组 = 0
  startMs: number;
  endMs: number;
  status: string;
  usage: TraceUsage | null; // null = 未落账
  segments: TraceSegment[];
  records: TraceRecord[];
}

export interface TraceModel {
  turns: TraceTurn[];
  truncated: boolean;
}

// ── 工具卡解析（content = serializeToolRecord 五键 JSON）──
export interface TraceToolCard {
  ok: boolean;
  name: string;
  argsJson: string;
  result: string;
  isError: boolean;
  cancelled: boolean;
}

// 结果 JSON 中止特征判读（abortedToolResult() 产物 = cancelled 键在场）
export function traceResultCancelled(resultText: string): boolean {
  if (resultText === '') {
    return false;
  }
  try {
    const parsed: object = JSON.parse(resultText);
    const rec = parsed as Record<string, Object>;
    return rec[TRACE_ABORT_MARK_KEY] === true;
  } catch (e) {
    return false; // 非 JSON 结果（纯文本）无中止特征
  }
}

export function traceParseToolCard(content: string): TraceToolCard {
  if (content === '') {
    return { ok: false, name: '', argsJson: '', result: '', isError: false, cancelled: false };
  }
  try {
    const parsed: object = JSON.parse(content);
    const rec = parsed as Record<string, Object>;
    const name: string = typeof rec['name'] === 'string' ? rec['name'] as string : '';
    const argsJson: string = typeof rec['argsJson'] === 'string' ? rec['argsJson'] as string : '';
    const result: string = typeof rec['result'] === 'string' ? rec['result'] as string : '';
    const isError: boolean = rec['isError'] === true;
    return { ok: true, name: name, argsJson: argsJson, result: result, isError: isError,
      cancelled: traceResultCancelled(result) };
  } catch (e) {
    return { ok: false, name: '', argsJson: '', result: '', isError: false, cancelled: false };
  }
}

// ── 内部帮助（不导出——判据面走主函数）──
function traceCompact(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

function traceTruncate(text: string, maxChars: number): string {
  return text.length > maxChars ? text.substring(0, maxChars) + '…' : text;
}

function traceFirstLine(text: string): string {
  const idx: number = text.indexOf('\n');
  return idx >= 0 ? text.substring(0, idx) : text;
}

function traceKindOf(role: string): string {
  if (role === 'user') {
    return TRACE_KIND_USER;
  }
  if (role === 'assistant') {
    return TRACE_KIND_ASSISTANT;
  }
  if (role === 'tool') {
    return TRACE_KIND_TOOL;
  }
  if (role === 'notice') {
    return TRACE_KIND_NOTICE;
  }
  if (role === 'summary') {
    return TRACE_KIND_SUMMARY;
  }
  if (role === 'clear') {
    return TRACE_KIND_CLEAR;
  }
  return role; // 词表外原样透传（fail-safe 可见，不静默吞）
}

function traceRunStatusOf(runStatus: string): string {
  if (runStatus === 'finished') {
    return TRACE_STATUS_DONE;
  }
  if (runStatus === 'failed') {
    return TRACE_STATUS_FAILED;
  }
  if (runStatus === 'prepared' || runStatus === 'running') {
    return TRACE_STATUS_RUNNING;
  }
  // awaiting_input（ask 等用户作答的停留态）同族归「进行中」——该轮是活跃轮（可作答续跑，
  // 非中断非失败）；词表外仍不猜（无徽标）
  if (runStatus === 'awaiting_input') {
    return TRACE_STATUS_RUNNING;
  }
  return ''; // 词表外不猜（无徽标）
}

// ── 记录行构造（卡解析结果入参复用，避免双解析）──
function traceBuildRecord(row: TraceRowIn, card: TraceToolCard | null,
  fact: TraceFactIn | null): TraceRecord {
  const kind: string = traceKindOf(row.role);
  if (kind === TRACE_KIND_TOOL) {
    const toolCard: TraceToolCard = card !== null ? card
      : { ok: false, name: '', argsJson: '', result: '', isError: false, cancelled: false };
    const title: string = toolCard.ok && toolCard.name !== '' ? toolCard.name : TRACE_TITLE_TOOL_FALLBACK;
    let summary: string = '';
    if (toolCard.ok) {
      const parts: string[] = [];
      if (toolCard.argsJson !== '') {
        parts.push('参数 ' + traceTruncate(traceCompact(toolCard.argsJson), TRACE_TOOL_ARGS_MAX));
      }
      const resultLine: string = traceCompact(traceFirstLine(toolCard.result));
      if (resultLine !== '') {
        parts.push('结果 ' + traceTruncate(resultLine, TRACE_TOOL_RESULT_MAX));
      }
      summary = parts.join(' · ');
    } else {
      summary = traceTruncate(traceCompact(row.content), TRACE_TEXT_USER_MAX); // 解析失败原样预览
    }
    let durationMs: number = 0;
    let status: string = '';
    if (fact !== null) {
      if (fact.finishedAt > fact.createdAt) {
        durationMs = fact.finishedAt - fact.createdAt;
      }
      const cancelled: boolean = toolCard.cancelled || traceResultCancelled(fact.result);
      if (fact.state === 'result_confirmed') {
        status = cancelled ? TRACE_STATUS_ABORTED : TRACE_STATUS_DONE;
      } else if (fact.state === 'failed') {
        status = cancelled ? TRACE_STATUS_ABORTED : TRACE_STATUS_FAILED;
      } else {
        status = TRACE_STATUS_RUNNING; // prepared / dispatch_intent（在途）
      }
    }
    return { id: row.id, kind: kind, title: title, summary: summary, timeMs: row.createdAt,
      durationMs: durationMs, status: status, factRef: fact !== null ? fact.id : '' };
  }
  if (kind === TRACE_KIND_USER) {
    return { id: row.id, kind: kind, title: TRACE_TITLE_USER,
      summary: traceTruncate(traceCompact(row.content), TRACE_TEXT_USER_MAX),
      timeMs: row.createdAt, durationMs: 0, status: TRACE_STATUS_DONE, factRef: '' };
  }
  if (kind === TRACE_KIND_ASSISTANT) {
    return { id: row.id, kind: kind, title: TRACE_TITLE_ASSISTANT,
      summary: traceTruncate(traceCompact(row.content), TRACE_TEXT_ASSISTANT_MAX),
      timeMs: row.createdAt, durationMs: 0, status: TRACE_STATUS_DONE, factRef: '' };
  }
  if (kind === TRACE_KIND_NOTICE) {
    return { id: row.id, kind: kind, title: TRACE_TITLE_NOTICE,
      summary: traceTruncate(traceCompact(row.content), TRACE_TEXT_USER_MAX),
      timeMs: row.createdAt, durationMs: 0, status: TRACE_STATUS_FAILED, factRef: '' };
  }
  if (kind === TRACE_KIND_SUMMARY) {
    return { id: row.id, kind: kind, title: TRACE_TITLE_SUMMARY,
      summary: traceTruncate(traceCompact(row.content), TRACE_TEXT_USER_MAX),
      timeMs: row.createdAt, durationMs: 0, status: TRACE_STATUS_DONE, factRef: '' };
  }
  // clear 与词表外：clear 用清空文案、正文一般空；词表外原样标题
  return { id: row.id, kind: kind, title: kind === TRACE_KIND_CLEAR ? TRACE_TITLE_CLEAR : row.role,
    summary: kind === TRACE_KIND_CLEAR ? '' : traceTruncate(traceCompact(row.content), TRACE_TEXT_USER_MAX),
    timeMs: row.createdAt, durationMs: 0, status: TRACE_STATUS_DONE, factRef: '' };
}

// ── 轮组构造 ──
function traceBuildTurn(runId: string, turnNo: number, bucket: TraceRowIn[],
  runFacts: TraceFactIn[], usageRow: TraceUsageIn | null, run: TraceRunIn | null): TraceTurn {
  const sorted: TraceRowIn[] = bucket.slice();
  sorted.sort((a: TraceRowIn, b: TraceRowIn): number => {
    const sa: number = a.stepIndex === null ? 2147483647 : a.stepIndex;
    const sb: number = b.stepIndex === null ? 2147483647 : b.stepIndex;
    if (sa !== sb) {
      return sa - sb;
    }
    if (a.createdAt !== b.createdAt) {
      return a.createdAt - b.createdAt;
    }
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
  });
  // 工具卡行与事实配对（§2.4：数量相等才按序配对 + 逐对同文校验；对不齐不猜）
  const cardRows: TraceRowIn[] = [];
  const cardByRowId = new Map<string, TraceToolCard>();
  for (const r of sorted) {
    if (r.role === 'tool') {
      cardRows.push(r);
      cardByRowId.set(r.id, traceParseToolCard(r.content));
    }
  }
  const paired = new Map<string, TraceFactIn>();
  if (runFacts.length === cardRows.length) {
    for (let i = 0; i < cardRows.length; i++) {
      const card: TraceToolCard = cardByRowId.get(cardRows[i].id) as TraceToolCard;
      const fact: TraceFactIn = runFacts[i];
      if (card.ok && fact.payload === card.argsJson) {
        paired.set(cardRows[i].id, fact);
      }
    }
  }
  // 记录行与段
  const records: TraceRecord[] = [];
  const segments: TraceSegment[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const row: TraceRowIn = sorted[i];
    const card: TraceToolCard | null = row.role === 'tool'
      ? cardByRowId.get(row.id) as TraceToolCard : null;
    const fact: TraceFactIn | null = row.role === 'tool'
      ? (paired.get(row.id) !== undefined ? paired.get(row.id) as TraceFactIn : null) : null;
    const record: TraceRecord = traceBuildRecord(row, card, fact);
    records.push(record);
    if (record.kind === TRACE_KIND_USER) {
      // 用户段：用户行 → 首个 assistant/notice 行（取不到不画）
      for (let j = i + 1; j < sorted.length; j++) {
        const nextKind: string = traceKindOf(sorted[j].role);
        if (nextKind === TRACE_KIND_ASSISTANT || nextKind === TRACE_KIND_NOTICE) {
          if (sorted[j].createdAt >= record.timeMs) {
            segments.push({ kind: TRACE_SEG_USER, t0: record.timeMs,
              t1: sorted[j].createdAt, failed: false });
          }
          break;
        }
      }
    } else if (record.kind === TRACE_KIND_ASSISTANT) {
      // 助手段：下一条记录（近似锚）；末条 assistant 取 run 收尾时刻（真墙钟），
      // 兜底 = createdAt + 轮用量时长（账本口径），都取不到不画
      let t1: number = -1;
      if (i + 1 < sorted.length) {
        t1 = sorted[i + 1].createdAt;
      } else if (run !== null && run.updatedAt > record.timeMs) {
        t1 = run.updatedAt;
      } else if (usageRow !== null && usageRow.durationMs > 0) {
        t1 = record.timeMs + usageRow.durationMs;
      }
      if (t1 >= record.timeMs) {
        segments.push({ kind: TRACE_SEG_ASSISTANT, t0: record.timeMs, t1: t1, failed: false });
      }
    } else if (record.kind === TRACE_KIND_TOOL) {
      // 工具段：已配对且终态时刻在场才画（0 → 不画）
      if (fact !== null && fact.finishedAt > fact.createdAt) {
        segments.push({ kind: TRACE_SEG_TOOL, t0: fact.createdAt, t1: fact.finishedAt,
          failed: false });
      }
    }
    // 失败段：失败/中止记录零宽标（含诊断行；靠颜色可见）
    if (record.status === TRACE_STATUS_FAILED || record.status === TRACE_STATUS_ABORTED) {
      segments.push({ kind: TRACE_SEG_FAILED, t0: record.timeMs, t1: record.timeMs, failed: true });
    }
  }
  // 轮起止：段与记录的最大终点（任务书 §4.4）；startMs 再并 run.createdAt 取最早
  let startMs: number = 0;
  let endMs: number = 0;
  let hasBound: boolean = false;
  for (const rec of records) {
    if (!hasBound || rec.timeMs < startMs) {
      startMs = rec.timeMs;
    }
    if (!hasBound || rec.timeMs > endMs) {
      endMs = rec.timeMs;
    }
    hasBound = true;
  }
  for (const seg of segments) {
    if (!hasBound || seg.t0 < startMs) {
      startMs = seg.t0;
    }
    if (!hasBound || seg.t1 > endMs) {
      endMs = seg.t1;
    }
    hasBound = true;
  }
  if (run !== null && (!hasBound || run.createdAt < startMs)) {
    startMs = run.createdAt;
    hasBound = true;
  }
  const usage: TraceUsage | null = usageRow === null ? null : {
    promptTokens: usageRow.promptTokens,
    cachedTokens: usageRow.cachedTokens,
    completionTokens: usageRow.completionTokens,
    totalTokens: usageRow.totalTokens,
    durationMs: usageRow.durationMs,
    firstTokenMs: usageRow.firstTokenMs
  };
  return {
    runId: runId,
    turnNo: turnNo,
    startMs: hasBound ? startMs : 0,
    endMs: hasBound ? endMs : 0,
    status: run !== null ? traceRunStatusOf(run.status) : '',
    usage: usage,
    segments: segments,
    records: records
  };
}

// ── 展示格式纯函数（页与详情面板共用单源；纯字符串，零 UI 依赖）──
// 时钟串 HH:mm:ss（记录行与轮头）；详情面板用全量串
export function traceClockText(ts: number): string {
  const d: Date = new Date(ts);
  const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
}

export function traceFullTimeText(ts: number): string {
  const d: Date = new Date(ts);
  const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
    pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
}

// 时长串（工具耗时 / 轮总耗时）：<60s 一位小数秒，≥60s「M 分 S 秒」（S 为 0 只留分；
// 秒段向下取整防 59.5~60 进位成「1 分 60 秒」——SessionStatsSheet.durationText 同口径）
export function traceDurationText(ms: number): string {
  const seconds: number = ms / 1000;
  if (seconds < 60) {
    return (Math.round(seconds * 10) / 10) + 's';
  }
  const minutes: number = Math.floor(seconds / 60);
  const rest: number = Math.floor(seconds - minutes * 60);
  return rest > 0 ? minutes + ' 分 ' + rest + ' 秒' : minutes + ' 分';
}

// 秒值串（首字耗时徽标）：<60s 一位小数否则整数秒（消息气泡 usageFirstTokenValue 同口径）
export function traceSecondsText(ms: number): string {
  const seconds: number = ms / 1000;
  return seconds < 60 ? (Math.round(seconds * 10) / 10) + 's' : Math.round(seconds) + 's';
}

// 状态文案（详情面板状态行与轮状态徽标共用；'' = 无态显「—」）
export function traceStatusTextOf(status: string): string {
  if (status === TRACE_STATUS_DONE) {
    return '完成';
  }
  if (status === TRACE_STATUS_FAILED) {
    return '失败';
  }
  if (status === TRACE_STATUS_RUNNING) {
    return '进行中';
  }
  if (status === TRACE_STATUS_ABORTED) {
    return '已中止';
  }
  return '—';
}

// ── 主组装（唯一导出入口）──
export function assembleSessionTrace(rows: TraceRowIn[], runs: TraceRunIn[],
  facts: TraceFactIn[], usages: TraceUsageIn[], diagnostics: TraceRowIn[],
  truncated: boolean): TraceModel {
  // ① run 编年与轮号（会话内 createdAt 升序；并列按 id 稳定化）
  const sortedRuns: TraceRunIn[] = runs.slice();
  sortedRuns.sort((a: TraceRunIn, b: TraceRunIn): number => {
    if (a.createdAt !== b.createdAt) {
      return a.createdAt - b.createdAt;
    }
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
  });
  const runNoById = new Map<string, number>();
  const runById = new Map<string, TraceRunIn>();
  for (let i = 0; i < sortedRuns.length; i++) {
    runNoById.set(sortedRuns[i].id, i + 1);
    runById.set(sortedRuns[i].id, sortedRuns[i]);
  }
  // ② 行合集（窗口 + 诊断补行；按 id 去重）
  const merged: TraceRowIn[] = [];
  const seenIds = new Set<string>();
  for (const r of rows) {
    if (!seenIds.has(r.id)) {
      seenIds.add(r.id);
      merged.push(r);
    }
  }
  for (const d of diagnostics) {
    if (!seenIds.has(d.id)) {
      seenIds.add(d.id);
      merged.push(d);
    }
  }
  // ③ 分组：命中 run 编年者进对应轮组；遗留行（runId 空）与悬空 runId 行归末尾未分组段
  const grouped = new Map<string, TraceRowIn[]>();
  const ungrouped: TraceRowIn[] = [];
  for (const r of merged) {
    if (r.runId !== '' && runById.has(r.runId)) {
      const bucket: TraceRowIn[] | undefined = grouped.get(r.runId);
      if (bucket === undefined) {
        grouped.set(r.runId, [r]);
      } else {
        bucket.push(r);
      }
    } else {
      ungrouped.push(r);
    }
  }
  // ④ 事实按 run 预索引（保入参序 = store 侧 createdAt/rowid 升序）；用量一轮恰一行（后到胜出兜防御）
  const factsByRun = new Map<string, TraceFactIn[]>();
  for (const f of facts) {
    const arr: TraceFactIn[] | undefined = factsByRun.get(f.runId);
    if (arr === undefined) {
      factsByRun.set(f.runId, [f]);
    } else {
      arr.push(f);
    }
  }
  const usageByRun = new Map<string, TraceUsageIn>();
  for (const u of usages) {
    usageByRun.set(u.runId, u);
  }
  // ⑤ 轮组（按轮号升序；窗口外旧轮无行不建组但轮号已占）+ ⑥ 末尾未分组段
  const turns: TraceTurn[] = [];
  for (const run of sortedRuns) {
    const bucket: TraceRowIn[] | undefined = grouped.get(run.id);
    if (bucket === undefined) {
      continue;
    }
    const runFacts: TraceFactIn[] | undefined = factsByRun.get(run.id);
    const usageRow: TraceUsageIn | undefined = usageByRun.get(run.id);
    turns.push(traceBuildTurn(run.id, runNoById.get(run.id) as number, bucket,
      runFacts !== undefined ? runFacts : [], usageRow !== undefined ? usageRow : null, run));
  }
  if (ungrouped.length > 0) {
    turns.push(traceBuildTurn('', 0, ungrouped, [], null, null));
  }
  return { turns: turns, truncated: truncated };
}
