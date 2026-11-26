// 会话搜索数据层：①搜索历史 + 最近进入会话两组记录的持久化，机制逐环对齐
// common/SettingSearch.ets 同名函数族（读写两侧截断收敛 / 去重移头 / 有界）。为何独立
// 建档不入 SettingSearch：域不同（设置项搜索是注册表单一数据源，会话无注册表——记录 =
// 历史 + 最近进入两族键），并入即两域耦合。
// ★ 五环清单（与设置搜索逐环同构，决明点名核对过）：注册 = EntryAbility loadContent
//   成功回调内 PersistentStorage.persistProp 两键（坑17 时机——早于该时机注册写入不落盘）；
//   路由 = 最近进入点击走 onOpen 既有链（handleOpenCard 加密守卫 + push，不另开路由）；
//   缓存 = AppStorage + PersistentStorage（string[] 一维数组可持久化，对象数组禁止）；
//   清删 = 直接写空数组 + 展示侧反查失败跳过（防持久化残留脏 id——已删会话不显示不清键）；
//   上限 = 历史 5 条 / 词条 10 字 / 最近进入 3 条（读写两侧双收敛）。
//
// 正文段检索编排半场：复用面全走既有单一实现，禁各写一份——SQL 预筛 ChatDb.
// searchMessagesAcross（助手范围在场才拼）；切词 MemoryText.splitMemoryQuery；LIKE 转义
// ToolChatSearch.escapeChatLikeToken；图会话可达过滤 collectReachableByConv +
// filterHitsByReachablePaths；相关度打分 rankChatHits（skipSensitiveFilter = true——该
// 过滤判据是外发面，UI 只在本机渲染，不关会变成「搜自己写过的密码搜不到」）；片段
// clipChatSnippet。检索面 = user/assistant 行的 content 一列，思考（reasoning）不入检索面
//（取证见 ChatDb.searchMessagesAcross 注释）。
import { ChatMessageHitRow, searchMessagesAcross } from './store/ChatDbReadSearch';
import { splitMemoryQuery } from './MemoryText';
import {
  clipChatSnippet,
  collectReachableByConv,
  escapeChatLikeToken,
  filterHitsByReachablePaths,
  rankChatHits
} from './providers/ToolChatSearch';

// 搜索历史键（AppStorage + PersistentStorage；EntryAbility persistProp 注册）
export const SESSION_SEARCH_HISTORY_KEY: string = 'sessionSearchHistory';
// 搜索历史上限 5 条（对齐 SettingSearch.MAX_SEARCH_HISTORY 决明定稿值）
export const MAX_SESSION_SEARCH_HISTORY: number = 5;
// 搜索词条长度上限（存储只留前 10 字——超长粘贴属误操作；展示侧另有 maxWidth + 单行
// 省略号双保险，见 SessionSearchPanels）
export const MAX_SESSION_SEARCH_TERM_LENGTH: number = 10;

// 最近进入会话键：存会话 id 一维数组（非 title——title 会改名/可重名，id 稳定唯一；
// 展示侧由列表页按 rows 反查标题，反查不到 = 已删或非当前助手名下，跳过）
export const SESSION_RECENT_CONV_KEY: string = 'sessionRecentConv';
// 最近进入上限 3 条（对齐 SettingSearch.MAX_RECENT_USE）
export const MAX_SESSION_RECENT_CONV: number = 3;

// ── 搜索历史（对齐 SettingSearch 同名族：去重移头、截断上限，有界防内存/存储膨胀）──

export function getSessionSearchHistory(): string[] {
  const history: string[] | undefined = AppStorage.get<string[]>(SESSION_SEARCH_HISTORY_KEY);
  // 读取侧同样截断：上限调整后持久化里可能残留超限旧数据，读取即收敛
  return history === undefined ? [] : history.slice(0, MAX_SESSION_SEARCH_HISTORY);
}

// 记录一次搜索词（Search.onSubmit + 历史词条点击回填移头）：截断长度 → 去重（已存在移到
// 头部）→ 插头部 → 截断上限条数
export function recordSessionSearchHistory(term: string): void {
  const trimmed: string = term.trim();
  if (trimmed === '') {
    return;
  }
  const limited: string = trimmed.slice(0, MAX_SESSION_SEARCH_TERM_LENGTH);
  const history: string[] = getSessionSearchHistory()
    .filter((item: string): boolean => item !== limited);
  history.unshift(limited);
  AppStorage.set(SESSION_SEARCH_HISTORY_KEY, history.slice(0, MAX_SESSION_SEARCH_HISTORY));
}

export function clearSessionSearchHistory(): void {
  AppStorage.set(SESSION_SEARCH_HISTORY_KEY, []);
}

// ── 最近进入（用户最近点开过的会话）：记录时机 = handleOpenCard 进入时（搜索页 openConv
// 同链）；展示 = 列表页按 rows 反查（id → 标题/时间）──

export function getSessionRecentConvs(): string[] {
  const recent: string[] | undefined = AppStorage.get<string[]>(SESSION_RECENT_CONV_KEY);
  return recent === undefined ? [] : recent.slice(0, MAX_SESSION_RECENT_CONV);
}

// 记录一次进入：去重（已存在移到头部）→ 插头部 → 截断上限（同历史有界姿势）
export function recordSessionRecentConv(conversationId: string): void {
  const trimmed: string = conversationId.trim();
  if (trimmed === '') {
    return;
  }
  const recent: string[] = getSessionRecentConvs()
    .filter((item: string): boolean => item !== trimmed);
  recent.unshift(trimmed);
  AppStorage.set(SESSION_RECENT_CONV_KEY, recent.slice(0, MAX_SESSION_RECENT_CONV));
}

export function clearSessionRecentConvs(): void {
  AppStorage.set(SESSION_RECENT_CONV_KEY, []);
}

// ── 正文段检索（消费方 = 会话搜索页 SessionSearchPage 正文分段）──

// SQL 预筛候选上限。跨会话混排 + LIMIT 截断时**排序键即候选集成员判据**（createdAt DESC
// 保最近命中，禁切 seq——见 ChatDb.searchMessagesAcross 注释），相关度重排只在候选集内做，
// 超出的旧命中由「收窄关键词」兜底。UI 侧取 200：展示上限 60 留 3 倍余量即可（工具面 300
// 是给模型的多轮余量）
export const SESSION_HIT_CANDIDATE_LIMIT: number = 200;
// 同一会话最多展示的命中条数：防一个会话命中几十条占满结果区、把其余会话的命中挤出可见面
//（相关度序仍在，被截的是该会话的次要命中——收窄关键词即可见）
export const SESSION_HIT_PER_CONVERSATION: number = 3;
// 正文段展示行上限（数据有界红线：列表只留前 N 行，超出由页面尾行提示引导收窄关键词）
export const SESSION_HIT_TOTAL_LIMIT: number = 60;

// 高亮切段中间态（区间合并用）
interface HighlightRange {
  start: number;
  end: number;
}

// 高亮片段段：hit = 该段是命中词（渲染侧加底色），false = 普通文脉段
export interface HighlightSegment {
  text: string;
  hit: boolean;
}

// 正文段展示行：片段与切段在本层一次算好，渲染侧零文本处理（页面只做时间格式化与上屏）
export interface SessionHitItem {
  // 消息 id（列表键的身份位；本笔不用于跳转，笔 2 定位闭环才消费）
  id: string;
  // 所属会话 id（点击上行打开会话用）
  conversationId: string;
  // 会话标题（空标题兜底「新对话」，与列表卡同款）
  title: string;
  // 命中片段（clipChatSnippet 开窗产物）按命中词切段后的段表——各段顺序拼接 === 片段原文
  segments: HighlightSegment[];
  // 命中消息时间戳（展示侧 formatConvTime 格式化）
  createdAt: number;
}

// 正文段检索产物：hits 已排序 + 封顶；tokens 供展示行组装切段（同一份切词结果两处消费，
// 避免页面与检索侧口径分叉）
export interface SessionMessageSearchResult {
  hits: ChatMessageHitRow[];
  tokens: string[];
  // 展示面是否被裁剪（有行在两层封顶中未上屏）：判据 = 真丢了行才为 true（★ 勿改判
  // 「展示行数 ≥ SESSION_HIT_TOTAL_LIMIT」——恰 60 行且零丢弃时会白说「只显示最相关的
  // 一部分结果」）。结果区尾行提示由它驱动
  truncated: boolean;
}

// 正文段检索（页面唯一入口）。★ 提交式检索（回车 / 搜索键 / 历史词条 / 切到正文段），
// 无 debounce——页面侧用请求序号丢弃在途旧响应（后发先至防串台）。
// 链路：切词（纯标点 → 空词直接回空，不查库）→ LIKE 各词一式 OR 预筛（助手范围内）→
// 图会话可达过滤（废弃分支节点不得上屏——否则点开会话看不到那条消息）→ 相关度打分排序
// → 两层封顶（truncated = 真丢了行，页面尾行提示判据）。错误不吞：RDB 异常向上抛，
// 由页面提示（P0-1 不静默）
export async function searchSessionMessages(keyword: string,
  assistantIds: string[]): Promise<SessionMessageSearchResult> {
  const tokens: string[] = splitMemoryQuery(keyword);
  if (tokens.length === 0) {
    return { hits: [], tokens: [], truncated: false };
  }
  const patterns: string[] = tokens.map((token: string): string =>
    '%' + escapeChatLikeToken(token) + '%');
  const candidates: ChatMessageHitRow[] = await searchMessagesAcross(patterns, '',
    SESSION_HIT_CANDIDATE_LIMIT, 0, 0, assistantIds);
  const reachable: Map<string, string[]> = await collectReachableByConv(candidates);
  const onPath: ChatMessageHitRow[] = filterHitsByReachablePaths(candidates, reachable);
  const ranked: ChatMessageHitRow[] = rankChatHits(onPath, tokens, keyword.trim(), true);
  const capped: ChatMessageHitRow[] =
    capSessionHits(ranked, SESSION_HIT_PER_CONVERSATION, SESSION_HIT_TOTAL_LIMIT);
  return {
    hits: capped,
    tokens: tokens,
    truncated: ranked.length > capped.length
  };
}

// 命中封顶（纯函数，保序——rows 须为已排序序）：同会话最多 perConversation 条、总数最多
// total 条（先到 total 直接收工，不再扫尾部）
export function capSessionHits(rows: ChatMessageHitRow[], perConversation: number,
  total: number): ChatMessageHitRow[] {
  const used: Map<string, number> = new Map<string, number>();
  const out: ChatMessageHitRow[] = [];
  for (const row of rows) {
    if (out.length >= total) {
      break;
    }
    const count: number = used.get(row.conversationId) ?? 0;
    if (count >= perConversation) {
      continue;
    }
    used.set(row.conversationId, count + 1);
    out.push(row);
  }
  return out;
}

// 展示行组装（纯函数）：会话标题反查（空标题兜底「新对话」；反查不到 = 已删/跨助手，标题
// 位留兜底值——内容命中侧不因此丢行，会话列表广播回来后 reload 自动重算）、片段开窗、
// 命中切段
export function composeSessionHitItems(hits: ChatMessageHitRow[], tokens: string[],
  titles: Map<string, string>): SessionHitItem[] {
  const items: SessionHitItem[] = [];
  for (const hit of hits) {
    const snippet: string = clipChatSnippet(hit.content, tokens);
    const title: string = titles.get(hit.conversationId) ?? '';
    items.push({
      id: hit.id,
      conversationId: hit.conversationId,
      title: title !== '' ? title : '新对话',
      segments: splitHighlightSegments(snippet, tokens),
      createdAt: hit.createdAt
    });
  }
  return items;
}

// 片段高亮切段（纯函数）：把片段按命中词切成 [普通 | 命中] 交替段，渲染侧逐段出 Span（命中
// 段加底色）。大小写不敏感（与 SQL LIKE 的 ASCII 不敏感、打分侧两侧 toLowerCase 三口径对齐）；
// 多词命中区间重叠或相接即合并（相邻命中不产出空段）；无命中 = 单段 hit=false（片段照常
// 显示，不因切不出高亮而丢行）。**永不丢字符**：各段顺序拼接恒等于原串
export function splitHighlightSegments(text: string, tokens: string[]): HighlightSegment[] {
  const lower: string = text.toLowerCase();
  const ranges: HighlightRange[] = [];
  for (const token of tokens) {
    const needle: string = token.toLowerCase();
    if (needle === '') {
      continue;
    }
    let from: number = 0;
    while (from <= lower.length - needle.length) {
      const at: number = lower.indexOf(needle, from);
      if (at < 0) {
        break;
      }
      ranges.push({ start: at, end: at + needle.length });
      from = at + needle.length;
    }
  }
  if (ranges.length === 0) {
    return [{ text: text, hit: false }];
  }
  ranges.sort((a: HighlightRange, b: HighlightRange): number => a.start - b.start);
  const merged: HighlightRange[] = [];
  for (const range of ranges) {
    const last: HighlightRange | undefined =
      merged.length > 0 ? merged[merged.length - 1] : undefined;
    if (last !== undefined && range.start <= last.end) {
      if (range.end > last.end) {
        last.end = range.end;
      }
      continue;
    }
    merged.push({ start: range.start, end: range.end });
  }
  const segments: HighlightSegment[] = [];
  let cursor: number = 0;
  for (const range of merged) {
    if (range.start > cursor) {
      segments.push({ text: text.substring(cursor, range.start), hit: false });
    }
    segments.push({ text: text.substring(range.start, range.end), hit: true });
    cursor = range.end;
  }
  if (cursor < text.length) {
    segments.push({ text: text.substring(cursor), hit: false });
  }
  return segments;
}
