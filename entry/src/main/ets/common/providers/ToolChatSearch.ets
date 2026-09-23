// 跨会话读取域（2026-09-13 跨会话检索笔建域；2026-09-19 跨会话记忆深化笔扩为三工具划界）：
// · search_chats——按关键词检索**其他会话**的历史消息片段（找具体内容，大层检索面）；
// · get_chats——会话清单与指定会话通读（list 最近会话元数据 / read 按标题定位读消息
//   原文，2026-09-19 新增，BLOCKED #10 落地）；
// · 记忆域 search_memory——记忆蒸馏小层，另域（MemoryText/MemoryGen），desc 已划界。
// 本文件 = 检索与读取纯函数（LIKE 转义 / 关键词打分 / 相关度排序 / 片段开窗 / 结果拼装 /
// 清单渲染 / 定位三态 / 升序窗口与 offset 归一）+ 当前会话中转键 + 跨会话工具判据 + 两
// 执行器；SQL 预筛与读取查询在 ChatDb（store 层归口），注册在 ToolTypes（本文件只供
// executor 与常量）。
// · 只读工具：端内执行零请求零费用，不记 logTaskUsage（无可记项）；工具轮消耗走助手级
//   toolStepLimit。
// · 隐私四闸（方案 §0.2 + 深化笔八闸）：locked 会话 SQL 层整体排除 / 敏感命中消息整条跳过
//   （与 composeMemoryList 外发面同口径）/ 隐私会话不声明（声明层过滤在 ChatContextUsage
//   .collectTools，isCrossSessionTool 双件同闸——执行器无上下文，未声明即不可达）/ 当前
//   会话经中转键排除（「其他会话」语义，当前会话内容本就在上下文，返回只是噪声）。
// · 检索选型（方案 §0.2-6）：SQL LIKE 预筛（保最近 300 条命中）+ 端内关键词打分重排
//   ——本地 RDB 千行级 LIKE 全扫毫秒级，FTS 留二期（规模真涨再立项）。
// · get_chats 选型（深化书 §0 竞品对照）：只读工具而非历史原文自动注入——十家竞品 +
//   MCP 协议源码级调研均不把历史原文自动喂模型；移动端两家（RikkaHub/Kelivo）均做成
//   只读工具，RikkaHub 源码注释明说工具化而非静态注入是为不破坏 prompt 缓存。
// ★ 模块环说明（坑50 红线自证）：本文件 import ToolTypes 两工具名常量（TOOL_SEARCH_CHATS
//   / TOOL_GET_CHATS，isCrossSessionTool 判据用）——与 ToolTypes 的 executor import 构成
//   环；两常量引用全部在**函数体内**（运行时求值，模块图此时已稳定），本文件与 ToolTypes
//   的顶层求值面零跨模块绑定读取，86 组扫描器在册可验。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToolExecutor } from './ToolContracts';
import { TOOL_GET_CHATS, TOOL_SEARCH_CHATS } from './ToolTypes';
import { ChatMessageHitRow, ChatReadConvRow, ChatReadWindowRow, queryConversationIdByTitle,
  queryConversationTitles, queryConversationWindowForRead, queryRecentConversationsForRead,
  countConversationMessagesForRead, searchMessagesAcross } from '../store/ChatDb';
import { hitSensitiveContent, splitMemoryQuery } from '../MemoryText';

const DOMAIN: number = 0x71C3;
const TAG: string = 'ToolChatSearch';

// 当前会话中转键（执行器无上下文读不到会话态——值由 ChatSendCtrl 发送时现写，同
// CHAT_SEARCH_COUNT_KEY 先例：发送点解析、同一会话天然对位，读侧恒取当下值；运行时态
// 不持久化）。'' = 无当前会话（不应发生——声明即随发送；脏态零排除兜底）
export const CHAT_ACTIVE_CONV_KEY: string = 'chatActiveConv';

// 工具名常量归口在 ToolTypes（TOOL_SEARCH_CHATS / TOOL_GET_CHATS）；本域不重复定义

// ── 跨会话读取纯函数（get_chats 两动作，2026-09-19 深化笔；断言面：剥 import 后与
// MemoryText 源拼接直跑，㉜ 剥桩先例——同 75 组检索纯函数同约定）──

// list 条数封顶（对齐 RikkaHub recent_chats 上限；任务书 §2.3）
export const CHAT_LIST_MAX: number = 30;
// read 单次条数封顶（拍板 2 宽档）
export const CHAT_READ_TAIL_MAX: number = 30;
// read 单条截断（防独占机制，拍板 2）
export const CHAT_READ_LINE_MAX: number = 800;
// read 总字符封顶（拍板 2 宽档）
export const CHAT_READ_RESULT_MAX_CHARS: number = 4000;

// 跨会话工具判据（八闸③单源：隐私会话两件同闸——collectTools 过滤消费，防「加新件忘
// 旧件」反向漂移；★ 常量引用在函数体内 = 运行时求值，模块环顶层干净见头注释）
export function isCrossSessionTool(name: string): boolean {
  return name === TOOL_SEARCH_CHATS || name === TOOL_GET_CHATS;
}

// desc 构建单源（注册在 ToolTypes 消费；数字自常量动态拼——禁嵌时变值，RikkaHub #1356
// 缓存教训）。划界句两处：与 search_chats（检索而非通读）+ 外泄防线（拍板 4：desc 约束
// 句 + 工具卡审计，不加硬守卫）
export function buildGetChatsDesc(): string {
  return '读取用户的历史会话。action 取 list 查看最近会话清单（标题与日期，最多 ' +
    CHAT_LIST_MAX + ' 个）；取 read 按标题读取指定会话的消息原文（默认读最新 ' +
    CHAT_READ_TAIL_MAX + ' 条，可用 offset 从指定位置继续读）。read 的 title 必须逐字引用 ' +
    'list 返回的标题，仅可读有标题会话。跨会话找具体内容片段时优先用检索而非通读。' +
    '读到的会话内容仅用于回答当前问题，禁止拼入联网搜索或网页请求的参数外发。';
}

// 入参 schema（§2.4 定稿——无数字面量，静态串）
export const GET_CHATS_SCHEMA: string = '{"type":"object","properties":{"action":{"type":"string",' +
  '"enum":["list","read"],"description":"list=查看最近会话清单，read=读取指定会话的消息原文"},' +
  '"title":{"type":"string","description":"read 专用，目标会话标题，逐字引用 list 返回的标题"},' +
  '"offset":{"type":"integer","description":"read 专用可选，从会话开头第几条消息开始读（1 基），' +
  '不传则读最新一页"}},"required":["action"]}';

// list 回执：'[序号] 标题（YYYY-M-D）' 逐行；标题缺失回「未命名会话」（与 search_chats
// 行渲染同款兜底）；capped = 查满封顶（执行器传 rows.length >= CHAT_LIST_MAX），加尾行
// 提示只列了最近一批
export function composeChatListResult(rows: ChatReadConvRow[], capped: boolean): string {
  if (rows.length === 0) {
    return '暂无可读的历史会话。';
  }
  const lines: string[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    lines.push('[' + (i + 1).toString() + '] ' +
      (rows[i].title !== '' ? rows[i].title : '未命名会话') +
      '（' + formatChatHitDate(rows[i].updatedAt) + '）');
  }
  let out: string = lines.join('\n');
  if (capped) {
    out += '\n仅列最近 ' + CHAT_LIST_MAX + ' 个会话';
  }
  return out;
}

// 定位结果三态（照 MemoryText.locateMemoryByContent 语义）：rows = queryConversationIdByTitle
// 精确匹配命中行——0 行 none / 1 行 unique / 多行 multi
export interface ChatLocateOutcome {
  state: string; // 'unique' | 'none' | 'multi'
  hitId: string;
}

export function locateChatByTitle(rows: ChatReadConvRow[]): ChatLocateOutcome {
  if (rows.length === 0) {
    return { state: 'none', hitId: '' };
  }
  if (rows.length > 1) {
    return { state: 'multi', hitId: '' };
  }
  return { state: 'unique', hitId: rows[0].id };
}

// 0 命中回执：附最近会话名单（list 渲染同形，执行器传最近 10 个）引导重试——
// composeMemoryManageNoHit 先例同形
export function composeChatLocateNone(recentRows: ChatReadConvRow[]): string {
  if (recentRows.length === 0) {
    return '没有找到这个标题的会话，当前也没有其他可读的历史会话。';
  }
  return '没有找到这个标题的会话。以下是最近的会话，确认标题后用 read 重试：\n' +
    composeChatListResult(recentRows, false);
}

// 多命中拒歧义回执：列全部命中（带日期）+ 说明——composeMemoryManageMultiHit 先例同形
export function composeChatLocateMulti(rows: ChatReadConvRow[]): string {
  const lines: string[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    lines.push('[' + (i + 1).toString() + '] ' +
      (rows[i].title !== '' ? rows[i].title : '未命名会话') +
      '（' + formatChatHitDate(rows[i].updatedAt) + '）');
  }
  return '有 ' + rows.length + ' 个同名会话，暂无法进一步区分，本次未读取。全部命中：\n' +
    lines.join('\n');
}

// read 窗口起点归一（offset 语义，拍板 3）：offset 非整数或 <1 = 默认读末页（尾部
// CHAT_READ_TAIL_MAX 条的首条序号）；有效 offset 原样（1 基升序绝对位次）。★ 2026-09-20
// 修复（D1-2）：原口径 `Math.min(offset, tailStart)` 把上界当成末页起点 tailStart——尾行
// 「可用 offset=N 继续读取」发出的 N 必 > start，夹回后重读同一页 = 同页死循环；total ≤ 30
// 时会话内任何 offset 都归 1，被总字符预算裁掉的内容任何 offset 都取不到。现上界 = 末条
// 序号（offset > total 才收末页；越下界/非整数仍回末页起点 tailStart，与前句同口径），
// 返回值恒 ∈ [1, max(1, total)]
//（total = 0 收 1 兜底——空会话回执由 composeChatReadResult 兜底）
export function resolveChatReadStart(offset: number, total: number): number {
  const tailStart: number = Math.max(1, total - CHAT_READ_TAIL_MAX + 1);
  if (!Number.isInteger(offset) || offset < 1) {
    return tailStart;
  }
  const lastIndex: number = Math.max(1, total); // 末条全局序号（total=0 兜底 1）
  return offset > lastIndex ? tailStart : offset;
}

// read 回执（模型消费面，文案规约不适用于模型面）：rows = SQL **升序**窗口（最早在前——
// ChatDb.queryConversationWindowForRead 的 `ORDER BY m.seq ASC LIMIT ? OFFSET ?`
//（2026-09-21 消息存储机制改造笔 3 切序：原 `m.createdAt ASC, m.rowid ASC` 双键退役——
// 排序权威 = 会话内 seq 单键；位次算法与排序键无关，见该函数注释），
// OFFSET = start - 1；★ 2026-09-20 修复（D1-1）：原先按「降序入参内部转正序」整体反转，
// 与 SQL 实际序相反，[start] 挂成窗口最新一条、序号与 offset 口径整体反号），
// start = 窗口首条全局序号（resolveChatReadStart 产物），total = COUNT 总数。
// 结构：计数头行（该会话共 N 条消息，当前显示第 X–Y 条——X/Y = 实显行的全局序号首末，
// 敏感跳过与预算裁剪都照实缩）+ '[全局序号] 角色：原文' 逐行
// + 缺口尾行（更早未读 → offset=1 提示；窗口后仍有未显 → offset=下一序号提示；该提示的
// offset 现可跟随——resolveChatReadStart 上界已放开到末条序号）。
// · 全局序号 = 升序绝对位次（含敏感跳过行——offset 翻页与序号恒对齐，跳号即敏感行不计）；
// · 敏感命中整条静默跳过（照 search_chats 先例，不回补不注明——rankChatHits 同口径）；
// · 单条保留换行仅 trim 首尾（通读场景代码与结构有价值），超 CHAT_READ_LINE_MAX 尾部
//   截断加 …；
// · 选取 = 贪心装入总字符封顶（selectMemoryEntries 同语义：超限整行不进，保已选行完整）。
export function composeChatReadResult(rows: ChatReadWindowRow[], total: number,
  start: number): string {
  if (total === 0 || rows.length === 0) {
    return '该会话暂无可读的消息。';
  }
  const lines: string[] = [];
  let used: number = 0;
  // consumed = 窗口内已定去向的原始行数（含敏感跳过；字符截断 break 时停在第一条未进行）
  let consumed: number = 0;
  // 实显首末全局序号（头行照实报——窗口长度 ≠ 实显行数：敏感跳过与预算裁剪都会缩）
  let firstShown: number = 0;
  let lastShown: number = 0;
  for (let i: number = 0; i < rows.length; i++) {
    const row: ChatReadWindowRow = rows[i];
    if (hitSensitiveContent(row.content) !== '') {
      consumed = i + 1;
      continue;
    }
    const role: string = row.role === 'user' ? '用户' :
      (row.role === 'assistant' ? '助手' : row.role);
    let text: string = row.content.trim();
    if (text.length > CHAT_READ_LINE_MAX) {
      text = text.substring(0, CHAT_READ_LINE_MAX) + '…';
    }
    const line: string = '[' + (start + i).toString() + '] ' + role + '：' + text;
    if (used + line.length > CHAT_READ_RESULT_MAX_CHARS && lines.length > 0) {
      break;
    }
    lines.push(line);
    used += line.length;
    consumed = i + 1;
    if (lines.length === 1) {
      firstShown = start + i; // 首条实显行（前导敏感行不计——头行首号照实）
    }
    lastShown = start + i;
  }
  if (lines.length === 0) {
    // 窗口内无一条可读（全敏感或防御分支）——不注明跳过原因（敏感过滤口径）
    return '该会话暂无可读的消息。';
  }
  const parts: string[] = ['该会话共 ' + total + ' 条消息，当前显示第 ' + firstShown + '–' +
    lastShown + ' 条：'];
  parts.push(lines.join('\n'));
  if (start > 1) {
    parts.push('可用 offset=1 读取更早的 ' + (start - 1) + ' 条');
  }
  const nextOffset: number = start + consumed;
  if (nextOffset <= total) {
    parts.push('可用 offset=' + nextOffset + ' 继续读取');
  }
  return parts.join('\n');
}

// ── 检索纯函数（断言面：剥 import 后与 MemoryText 源拼接直跑，㉜ 剥桩先例）──

// SQL 预筛候选上限（方案 §2.3：保最近的 300 条命中——createdAt DESC 截断；打分层做
// 相关度重排，超旧命中让位由尾行提示收窄关键词；数据有界红线）。
// ★ 2026-09-21 自检 P1：预筛的排序键**恒为 createdAt**（跨会话混排 + LIMIT 截断 ⇒ 排序键即
// 候选集成员判据；改成会话内 seq 会让短会话的命中被系统性挤出候选集）——动
// ChatDb.searchMessagesAcross 的 ORDER BY 前先读该函数注释的禁切判据
export const CHAT_SEARCH_CANDIDATE_LIMIT: number = 300;
// 工具返回双封顶（宪法数据有界；行含标题/日期/角色/片段 ≈150 字，10 条/2000 字覆盖
// 典型问询，超出由尾行引导收窄）
export const CHAT_TOOL_RESULT_MAX_COUNT: number = 10;
export const CHAT_TOOL_RESULT_MAX_CHARS: number = 2000;
// 触上限尾行
const CHAT_SEARCH_CAP_NOTE: string = '已达返回上限，可用更具体的关键词再检索';
// 单条消息片段上限（开窗截取的目标长度）
const CHAT_SNIPPET_MAX: number = 120;
// 开窗时首个命中词前的留白（命中词居窗口前部——其后文脉通常更长）
const CHAT_SNIPPET_HEADROOM: number = 30;

// LIKE 通配符转义（ESCAPE '\' 配对）：token 内 % _ \ 前缀反斜杠——用户关键词含通配符
// 字面量时防误匹配（纯函数，预筛 pattern 的唯一来源）
export function escapeChatLikeToken(token: string): string {
  return token.replace(/[%_\\]/g, '\\$&');
}

// 检索候选行类型 = ChatDb.ChatMessageHitRow（单一来源 import；order = SQL 返回序
// 〔createdAt DESC〕，排序 tiebreak 显式用，不赌引擎稳定性）

// 打分中间态
interface ChatSearchScored {
  row: ChatMessageHitRow;
  score: number;
  order: number;
}

// 相关度打分：逐词命中 +1 + 整串 trimmed query 命中再 +2（整串是意图最强信号，同
// scoreMemoryItem 语义）。★ 大小写：SQLite LIKE 对 ASCII 不区分大小写，打分侧两侧
// toLowerCase 对齐——英文关键词大小写变体不因预筛/打分口径分叉而丢分（search_memory
// 已同款小写化，2026-09-13 自检轮 O-1 拍板两工具口径对齐）；中文 toLowerCase 无变化
function scoreChatRow(content: string, tokens: string[], whole: string): number {
  const lower: string = content.toLowerCase();
  let score: number = 0;
  for (const token of tokens) {
    if (lower.includes(token.toLowerCase())) {
      score++;
    }
  }
  if (whole !== '' && lower.includes(whole.toLowerCase())) {
    score += 2;
  }
  return score;
}

// 敏感过滤 + 打分排序（零分或敏感命中不入选）：rows = SQL 预筛候选（createdAt DESC 序）
// → 相关度序出。敏感整条跳过 = 拍板④（检索结果发往当前会话服务商，未必与原会话同家）
export function rankChatHits(rows: ChatMessageHitRow[], tokens: string[],
  whole: string): ChatMessageHitRow[] {
  const scored: ChatSearchScored[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    if (hitSensitiveContent(rows[i].content) !== '') {
      continue;
    }
    const score: number = scoreChatRow(rows[i].content, tokens, whole);
    if (score > 0) {
      scored.push({ row: rows[i], score: score, order: i });
    }
  }
  scored.sort((a: ChatSearchScored, b: ChatSearchScored): number => {
    if (a.score !== b.score) {
      return b.score - a.score;
    }
    if (a.row.createdAt !== b.row.createdAt) {
      return b.row.createdAt - a.row.createdAt;
    }
    return a.order - b.order;
  });
  const ranked: ChatMessageHitRow[] = [];
  for (const entry of scored) {
    ranked.push(entry.row);
  }
  return ranked;
}

// 压空白 + 首个命中词开窗截取：多行消息压成单行片段；以最早命中的词为中心开窗（其前
// 留 CHAT_SNIPPET_HEADROOM），首尾越界加 …。tokens 全不命中（不应发生——SQL 已预筛）
// 回头部截取
export function clipChatSnippet(content: string, tokens: string[]): string {
  const flat: string = content.replace(/\s+/g, ' ').trim();
  if (flat.length <= CHAT_SNIPPET_MAX) {
    return flat;
  }
  const lower: string = flat.toLowerCase();
  let hitAt: number = -1;
  for (const token of tokens) {
    const at: number = lower.indexOf(token.toLowerCase());
    if (at >= 0 && (hitAt < 0 || at < hitAt)) {
      hitAt = at;
    }
  }
  const start: number = hitAt < 0 ? 0 : Math.max(0, Math.min(hitAt - CHAT_SNIPPET_HEADROOM,
    flat.length - CHAT_SNIPPET_MAX));
  const end: number = Math.min(flat.length, start + CHAT_SNIPPET_MAX);
  return (start > 0 ? '…' : '') + flat.substring(start, end) + (end < flat.length ? '…' : '');
}

// 消息日期格式化（YYYY-M-D 本地时区——会话标题旁的时间提示，模型可感知新近度）
export function formatChatHitDate(createdAt: number): string {
  const d: Date = new Date(createdAt);
  return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
}

// 结果行渲染：'[序号] 会话「标题」（日期）角色：片段'；标题缺失回「未命名会话」；
// role 非 user/assistant 原样展示（SQL 已滤，防御）
function renderChatHitLine(index: number, title: string, row: ChatMessageHitRow,
  tokens: string[]): string {
  const role: string = row.role === 'user' ? '用户' : (row.role === 'assistant' ? '助手' : row.role);
  return '[' + index.toString() + '] 会话「' + (title !== '' ? title : '未命名会话') +
    '」（' + formatChatHitDate(row.createdAt) + '）' + role + '：' +
    clipChatSnippet(row.content, tokens);
}

// 检索结果文本（模型消费面，简洁中文——文案规约不适用于模型面）：
// · 空 query（纯标点/空白切词后为空）→ 索要关键词
// · 无命中（含候选全被敏感过滤）→ 换词提示
// · 命中 → 计数头（条数 + 来自几个会话）+ 逐行；双封顶截断加尾行
// 选取 = 与 selectMemoryEntries 同一贪心语义（条数/字符双封顶，超出的整行不进），此处
// 按行字符实耗计（渲染前缀长度随序号与标题浮动，软预算——超限即停，保已选行完整）
export function composeChatSearchResult(rows: ChatMessageHitRow[],
  titles: Map<string, string>, query: string): string {
  const tokens: string[] = splitMemoryQuery(query);
  if (tokens.length === 0) {
    return '请提供要检索的关键词。';
  }
  const ranked: ChatMessageHitRow[] = rankChatHits(rows, tokens, query.trim());
  if (ranked.length === 0) {
    return '未检索到相关消息。可更换更具体的关键词再试。';
  }
  const lines: string[] = [];
  const convs: Set<string> = new Set<string>();
  let used: number = 0;
  for (const row of ranked) {
    if (lines.length >= CHAT_TOOL_RESULT_MAX_COUNT) {
      break;
    }
    const title: string = titles.get(row.conversationId) ?? '';
    const line: string = renderChatHitLine(lines.length + 1, title, row, tokens);
    if (used + line.length > CHAT_TOOL_RESULT_MAX_CHARS && lines.length > 0) {
      break;
    }
    lines.push(line);
    used += line.length;
    convs.add(row.conversationId);
  }
  const header: string = '检索到 ' + lines.length + ' 条相关消息，来自 ' + convs.size +
    ' 个会话，按相关度排序';
  let out: string = header + '\n' + lines.join('\n');
  if (lines.length < ranked.length) {
    out += '\n' + CHAT_SEARCH_CAP_NOTE;
  }
  return out;
}

// ── 执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject，错误走 JSON 错误信息）──
// 流程：解析 query → 切词守卫 → 中转键取当前会话 → SQL 预筛（locked 排除 + 当前会话
// 排除 + LIKE 每词一式 OR）→ 候选会话标题批量查（两查询有界，禁逐行查——P1-2）→ 纯
// 函数打分拼装。声明层（助手开关 + 隐私会话过滤）在 ChatSendCtrl 把关，未声明即不可达
export class SearchChatsExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    let query: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    const tokens: string[] = splitMemoryQuery(query);
    if (tokens.length === 0) {
      return Promise.resolve('请提供要检索的关键词。');
    }
    const activeConv: string = AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? '';
    const patterns: string[] = tokens.map((t: string): string => '%' + escapeChatLikeToken(t) + '%');
    return searchMessagesAcross(patterns, activeConv, CHAT_SEARCH_CANDIDATE_LIMIT)
      .then((rows: ChatMessageHitRow[]): Promise<string> =>
        queryConversationTitles(rows).then((titles: Map<string, string>): string =>
          composeChatSearchResult(rows, titles, query)))
      .catch((e: Object): string => {
        hilog.warn(DOMAIN, TAG, '跨会话检索失败：%{public}s', (e as Error).message);
        return JSON.stringify({ error: '会话记录读取失败：' + (e as Error).message });
      });
  }
}

// ── 读取执行器（get_chats，2026-09-19 深化笔；注册在 ToolTypes。契约 = 恒 resolve 不
// reject，错误走 JSON 错误信息——SearchChatsExecutor 同款）──
// 流程：解析 action/title/offset → list 直查清单 / read 按标题定位（三态：multi 拒歧义、
// none 回最近 10 个会话名单、unique 先 COUNT 后窗口两查）→ 纯函数拼装。当前会话经中转键
// 排除（'' 不排除）；offset 归一在 resolveChatReadStart（总数先行——业务语义不入 store 层）。
// 声明层（助手开关 + 隐私会话过滤 isCrossSessionTool 双件同闸）在 ChatContextUsage 把关，
// 未声明即不可达
export class GetChatsExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    let action: string = '';
    let title: string = '';
    let offset: number = Number.NaN; // 未传/非数字 = NaN → resolveChatReadStart 归默认末页
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const rawAction = parsed['action'];
      if (typeof rawAction === 'string') {
        action = rawAction.trim();
      }
      const rawTitle = parsed['title'];
      if (typeof rawTitle === 'string') {
        title = rawTitle.trim();
      }
      const rawOffset = parsed['offset'];
      if (typeof rawOffset === 'number') {
        offset = rawOffset;
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    const activeConv: string = AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? '';
    const fail = (e: Object): string => {
      hilog.warn(DOMAIN, TAG, '跨会话读取失败：%{public}s', (e as Error).message);
      return JSON.stringify({ error: '会话记录读取失败：' + (e as Error).message });
    };
    if (action === 'list') {
      return queryRecentConversationsForRead(CHAT_LIST_MAX, activeConv)
        .then((rows: ChatReadConvRow[]): string =>
          composeChatListResult(rows, rows.length >= CHAT_LIST_MAX))
        .catch(fail);
    }
    if (action === 'read') {
      if (title === '') {
        return Promise.resolve('action 为 read 时需要 title 参数，值为目标会话标题，' +
          '逐字引用 list 返回的标题。');
      }
      return queryConversationIdByTitle(title)
        .then((hits: ChatReadConvRow[]): Promise<string> => {
          const located: ChatLocateOutcome = locateChatByTitle(hits);
          if (located.state === 'multi') {
            return Promise.resolve(composeChatLocateMulti(hits));
          }
          if (located.state === 'none') {
            return queryRecentConversationsForRead(10, activeConv)
              .then((recent: ChatReadConvRow[]): string => composeChatLocateNone(recent))
              .catch(fail);
          }
          return countConversationMessagesForRead(located.hitId)
            .then((total: number): Promise<string> => {
              const start: number = resolveChatReadStart(offset, total);
              return queryConversationWindowForRead(located.hitId, start, CHAT_READ_TAIL_MAX)
                .then((rows: ChatReadWindowRow[]): string =>
                  composeChatReadResult(rows, total, start));
            })
            .catch(fail);
        })
        .catch(fail);
    }
    return Promise.resolve('action 必须是 list 或 read。');
  }
}
