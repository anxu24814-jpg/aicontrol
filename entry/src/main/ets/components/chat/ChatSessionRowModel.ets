// 会话列表行模型（自 ChatSessionRows.ets 域级拆出，2026-11-16 P0 笔）：职责一句话 =
// 「会话列表行的类型与派生——SessionListRow 定义 + 重拉行合成/比对/逐行复用纯函数」。
// 与渲染件 ChatSessionRows.ets 分家：本件零 UI/零 ArkUI 组件依赖（只碰 DB 行、草稿仓、
// 摘要清洗、运行时 loading 判据），渲染件只消费 SessionListRow 并画卡。拆出理由 = 渲染件
// 已越 1200 硬线（P0 前 1173，直接加复用函数会破线）；职责缝清晰（纯数据半边），方法体原样
// 搬迁非重写。依赖方向单向：ChatSessionList / ChatSessionRows / SessionGridRows → 本件。
// 断言装载读点：assert-chat-runtime 351/403/2185 组读本件；351/403 原读 ChatSessionRows
// 已随迁改读本件（403 判据串零改动；351 增 sessionRowEquals 切片与 conversationRowsEqual 同跑
// ——11 字段单一契约的直跑面，2026-11-16 自检轮改口：原「判据串零改动」对 351 已不成立）。
import { ConversationRow } from '../../common/store/ChatDb';
import { NEW_DRAFT_KEY, DraftEntry, getDraft, hasDraft } from './ChatDraftStore';
import { historyFilterIds } from '../../common/store/AssistantDb';
import { cleanSnippet, SNIPPET_MAX_LEN } from '../../common/chat/SessionSnippet';
import { chatSessionRuntime } from '../../common/chat/ChatSessionRuntime';

// 会话列表行（DB 行 + 运行时生成中标记合成形态）。归属 = 行模型域（壳侧 reload 合成、
// 渲染件卡片消费）；loading/draft/snippet 随行对象整体替换流动（visibleRows 换新 → Repeat item
// 比对 → 卡内 ri.item 现读），键纪律两问：行组件消费的可变成分全在行对象内（title/时间/星标/
// loading——整对象替换刷新），Repeat 键仍只写会话 id 身份（机制③：键变不重建，刷新走数据/
// 参数传播）——两问皆过，不漏键
export interface SessionListRow extends ConversationRow {
  // 生成中标记（true = 该会话有活跃生成——壳侧 reload 经 ChatSessionRuntime.isGenerating 合成；
  // 收尾经 SESSION_LIST_RELOAD_KEY 广播重拉清退，见彼两件注释）
  loading: boolean;
  // 草稿标记（true = 该会话有未发出草稿——壳侧 reload 经 reconcileSessionRows/fillSessionRow
  // 合成打标；随行对象整体替换流动〔照 loading 形制，不进 Repeat 键〕；'__new__' 合成行恒 true）
  draft: boolean;
  // 摘要（已清洗的一句，空串 = 无消息）。取数单源 =
  // common/chat/SessionSnippet.queryConversationSnippets（单条按会话索引子查询 SQL），
  // 壳侧 reload 合成时填入；随行对象整体替换流动，不进 Repeat 键（照 loading/draft 形制）
  snippet: string;
}

// ═══ 会话行派生纯函数族（类型属主即函数属主：围绕 SessionListRow 行对象合成/比对；
//     直跑断言装载读点 = assert-chat-runtime 351/403/2185 组；消费方 = 壳 ChatSessionList
//     reload/applySessionSnapshot/syncVisibleRows）═══

// ★ R2-a 结果未变不赋值 / P0 逐行复用：单行 10 字段全等是唯一比对契约（字段清单与
// ChatDb.queryConversations 的 7 列 + loading/draft/snippet 三合成列同源）。漏一项 = 该字段
// 变更被静默吞掉、列表停旧态（坑44/80 家族静默冻结高发面）——conversationRowsEqual 与
// reconcileSessionRows 共用本函数，禁在他处复写。
function sessionRowEquals(a: SessionListRow, b: SessionListRow): boolean {
  return a.id === b.id && a.title === b.title && a.providerId === b.providerId
    && a.createdAt === b.createdAt && a.updatedAt === b.updatedAt
    && a.titleSource === b.titleSource
    && a.favorite === b.favorite && a.loading === b.loading
    && a.draft === b.draft && a.snippet === b.snippet;
}

// 顺序敏感：查询 orderByDesc(updatedAt) 决定行序，序变即数据变——保守方向（拿不准就赋值，
// 宁可多刷不可漏刷）。★ 产品路径零调用（2026-11-16 P0 起 reconcileSessionRows 自持「按 id 复用
// + 引用/顺序比对」），保留为 assert-chat-runtime 351 组直跑面与字段契约对照，禁在产品侧接线。
export function conversationRowsEqual(current: SessionListRow[], next: SessionListRow[]): boolean {
  if (current.length !== next.length) {
    return false;
  }
  for (let i = 0; i < current.length; i++) {
    if (!sessionRowEquals(current[i], next[i])) {
      return false;
    }
  }
  return true;
}

// 空白行对象：SessionListRow 字段清单的唯一字面量落点（新增字段时此处编译必红；fill 系列
// 只赋值不增删字段）
function emptySessionRow(): SessionListRow {
  return {
    id: '', title: '', providerId: '', createdAt: 0, updatedAt: 0,
    titleSource: '', favorite: false,
    loading: false, draft: false, snippet: ''
  };
}

// 单行摘要取值单源（applyDraftRows 旧合成路径与 reconcileSessionRows P0 路径共用）：
// 草稿正文优先于最后一条消息
function snippetForRow(row: ConversationRow, snippets: Map<string, string>): string {
  const entry: DraftEntry | undefined = getDraft(row.id);
  let snippet: string = snippets.get(row.id) ?? '';
  if (entry !== undefined && entry.text.trim() !== '') {
    snippet = cleanSnippet(entry.text, SNIPPET_MAX_LEN);
  }
  return snippet;
}

// 单行派生值落 target（不 new）：reconcileSessionRows 的比对 scratch 与 composeSessionRow
// 共用同一套赋值——先把候选值写进 scratch，再与旧行逐字段比；未变行直接复用旧对象。
function fillSessionRow(target: SessionListRow, row: ConversationRow, loading: boolean,
  snippets: Map<string, string>): void {
  target.id = row.id;
  target.title = row.title;
  target.providerId = row.providerId;
  target.createdAt = row.createdAt;
  target.updatedAt = row.updatedAt;
  target.titleSource = row.titleSource;
  target.favorite = row.favorite;
  target.loading = loading;
  target.draft = hasDraft(row.id);
  target.snippet = snippetForRow(row, snippets);
}

// 单行合成（变了才调；未变行走 reconcile 的旧对象复用，不经过本函数）
function composeSessionRow(row: ConversationRow, loading: boolean,
  snippets: Map<string, string>): SessionListRow {
  const out: SessionListRow = emptySessionRow();
  fillSessionRow(out, row, loading, snippets);
  return out;
}

// '__new__' 合成行字段（头部插入 = 恒置顶；不落库，建行会被启动 sweep 当垃圾级联删）
function fillSyntheticRow(target: SessionListRow, draft: DraftEntry): void {
  target.id = NEW_DRAFT_KEY;
  target.title = '新会话';
  target.providerId = '';
  target.createdAt = draft.updatedAt;
  target.updatedAt = draft.updatedAt;
  target.titleSource = '';
  target.favorite = false;
  target.loading = false;
  target.draft = true;
  target.snippet = cleanSnippet(draft.text, SNIPPET_MAX_LEN);
}

function composeSyntheticRow(draft: DraftEntry): SessionListRow {
  const out: SessionListRow = emptySessionRow();
  fillSyntheticRow(out, draft);
  return out;
}

// 行合成（旧路径，保留为 403 断言直跑面/合成语义对照；产品路径自 2026-11-16 P0 起改走
// reconcileSessionRows——本函数每次调用仍整批 new，禁在产品侧重新接线）：
// DB 行 + 运行态生成中标记（loading 随行对象整体替换流动）。显式字段构造（ArkTS 对象字面量
// 禁 spread 收窄——勿改回 {...row}）；draft/snippet 取值与 P0 路径共用 snippetForRow/hasDraft。
export function applyDraftRows(rows: SessionListRow[], activeAssistantId: string,
  snippets: Map<string, string> = new Map<string, string>()): SessionListRow[] {
  const marked: SessionListRow[] = rows.map((row: SessionListRow): SessionListRow =>
    composeSessionRow(row, row.loading, snippets));
  const newDraft: DraftEntry | undefined = getDraft(NEW_DRAFT_KEY);
  if (newDraft !== undefined
    && historyFilterIds(activeAssistantId).includes(newDraft.assistantId)) {
    return [composeSyntheticRow(newDraft)].concat(marked);
  }
  return marked;
}

// ★ P0（2026-11-16）：重拉结果按 id 逐行复用——未变行直接沿用旧对象引用，只有变行才
// composeSessionRow 新建；返回 null = 新旧行集逐项同引用同序（壳侧跳过赋值，R2-a 语义不变）。
// 为什么：旧路径每次重拉先造 2N 个对象（loading 合成一遍 + 草稿摘要合成一遍）再全量比对，
// 即使一行没变也整批变成垃圾；在退页/生成收尾等异步重拉落在滑动窗口时，这批垃圾会推高
// Young GC 触发概率（官方 GC 文档：Young 阈值 2~16MB；Old 单次约 5~10ms），表现为滑一两下
// 偶发卡一下。本函数稳态重拉零行对象 new（仅一个 Map + 一个 scratch），变一行只 new 一行。
// 字段契约 = sessionRowEquals 的 10 项（漏一项 = 该字段静默冻结，坑44/80 家族）。
export function reconcileSessionRows(current: SessionListRow[], queried: ConversationRow[],
  activeAssistantId: string, snippets: Map<string, string>): SessionListRow[] | null {
  const previousById: Map<string, SessionListRow> = new Map<string, SessionListRow>();
  for (const row of current) {
    previousById.set(row.id, row);
  }
  // 单 scratch 复用（每行只赋值不 new）；变行才 composeSessionRow
  const scratch: SessionListRow = emptySessionRow();
  const next: SessionListRow[] = [];

  const newDraft: DraftEntry | undefined = getDraft(NEW_DRAFT_KEY);
  if (newDraft !== undefined
    && historyFilterIds(activeAssistantId).includes(newDraft.assistantId)) {
    fillSyntheticRow(scratch, newDraft);
    const previous: SessionListRow | undefined = previousById.get(NEW_DRAFT_KEY);
    next.push(previous !== undefined && sessionRowEquals(previous, scratch) ? previous :
      composeSyntheticRow(newDraft));
  }

  for (const row of queried) {
    const loading: boolean = chatSessionRuntime.isGenerating(row.id);
    fillSessionRow(scratch, row, loading, snippets);
    const previous: SessionListRow | undefined = previousById.get(row.id);
    next.push(previous !== undefined && sessionRowEquals(previous, scratch) ? previous :
      composeSessionRow(row, loading, snippets));
  }

  // 同长且逐项同引用同序 = 无变化（null 让壳侧跳过 assignment；顺序变化仍返回 next，
  // 保证 updatedAt 重排落地）
  if (next.length === current.length) {
    let unchanged: boolean = true;
    for (let i = 0; i < next.length; i++) {
      if (next[i] !== current[i]) {
        unchanged = false;
        break;
      }
    }
    if (unchanged) {
      return null;
    }
  }
  return next;
}

// oldest 档反转后重钉顶（恒置顶落法②，方案 §6.1-2）：整体反转会把头部合成行翻到尾——把
// id === NEW_DRAFT_KEY 的行移回首。★ 排序档已随 2026-11-12 偏好开关批退役（列表恒最新在上），
// 本函数无产品调用点，仅 assert-chat-runtime 403 组直跑面；勿因「没人用」删除（钉面在场）。
// 纯函数（入参先浅拷贝再动，不动 rows 原数组防 @State 被
// 原地改动；入参已是反转新拷贝，防御性拷贝保函数自纯）
export function repinDraftTop(rows: SessionListRow[]): SessionListRow[] {
  if (rows.length === 0 || rows[0].id === NEW_DRAFT_KEY) {
    return rows;
  }
  const at: number = rows.findIndex((row: SessionListRow): boolean => row.id === NEW_DRAFT_KEY);
  if (at < 0) {
    return rows;
  }
  const moved: SessionListRow[] = rows.slice();
  const draftRow: SessionListRow = moved.splice(at, 1)[0];
  moved.unshift(draftRow);
  return moved;
}
