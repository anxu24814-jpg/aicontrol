// 跨会话读取域：三工具划界——
// · search_chats——按关键词检索**其他会话**的历史消息片段（找具体内容，大层检索面）；
// · get_chats——会话清单与指定会话通读（list 最近会话元数据 / read 按标题或 id 定位读
//   消息原文）；
// · 记忆域 search_memory——记忆蒸馏小层，另域（MemoryText/MemoryGen），desc 已划界。
// 本文件 = 检索与读取纯函数（LIKE 转义 / 关键词打分 / 相关度排序 / 片段开窗 / 结果拼装 /
// 清单渲染 / 定位三态 / 升序窗口与 offset 归一）+ 跨会话工具判据 + 两执行器；SQL 预筛与
// 读取查询在 ChatDb（store 层归口），注册在 ToolTypes（本文件只供 executor 与常量）。
// · 只读工具：端内执行零请求零费用，不记 logTaskUsage；工具轮消耗走全局轮数上限
//（prefToolStepLimit，设置页工具调用页控制）。
// · 隐私三闸：敏感命中消息整条跳过（与 composeMemoryList
//   外发面同口径）/ 隐私会话不声明（声明层过滤在 ChatContextUsage.collectTools，
//   isCrossSessionTool 双件同闸——执行器无上下文，未声明即不可达）/ 当前会话经上下文排除
//   （「其他会话」语义——当前会话内容本就在上下文，返回只是噪声）。
//   ★ 2026-11-17 整体退役加密会话笔：原第一闸「locked 会话 SQL 层整体排除」随功能退役删除
// · 检索选型：SQL LIKE 预筛（保最近 300 条命中）+ 端内关键词打分重排——本地 RDB 千行级
//   LIKE 全扫毫秒级，FTS 留二期（规模真涨再立项）。
// · get_chats 选型（竞品对照）：只读工具而非历史原文自动注入——十家竞品 + MCP 协议源码级
//   调研均不把历史原文自动喂模型；移动端两家均做成只读工具（工具化不破坏 prompt 缓存）。
// ★ 模块环已消：两工具名常量（TOOL_SEARCH_CHATS / TOOL_GET_CHATS）自**零 import 叶子
//   ToolIds.ets** 引——本文件对聚合根 ToolTypes 零 import，环消失。沿革与 B/C 优化笔
//   细节见 docs/变更记录.md。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { TOOL_GET_CHATS, TOOL_SEARCH_CHATS } from './ToolIds';
import { ChatMessageHitRow, ChatReadConvRow, ChatReadWindowRow, queryConversationIdByTitle,
  queryConversationRowByIdForRead, queryConversationRowsForRead, queryConversationTitles,
  queryRecentConversationsForRead, searchMessagesAcross } from '../store/ChatDbReadSearch';
// 图会话可达节点链序表（读面过滤的路径真源——读口在 ChatContextSource，本件只消费；
// 本 import 只在执行器函数体内求值，ChatContextSource 不反向依赖 providers 层）
import { readReachableNodeIds } from '../chat/ChatContextSource';
// 墓碑句单源（本面与各写入口同句，收编自原自写「暂不可读」句）
import { TOMBSTONE_TOAST_TEXT } from '../chat/ChatBranchPolicy';
import { hitSensitiveContent, splitMemoryQuery } from '../MemoryText';

const DOMAIN: number = 0x71C3;
const TAG: string = 'ToolChatSearch';

// 当前会话中转键——★ **已退役**：现行通道 = ToolExecutionContext.conversationId 随链显式
// 携带，原读点（本件两执行器）已删。键位保留仅作兼容，**全仓零读写**——勿按现役口径新增读写
export const CHAT_ACTIVE_CONV_KEY: string = 'chatActiveConv';

// 工具名常量归口在零 import 叶子 ToolIds.ets（TOOL_SEARCH_CHATS / TOOL_GET_CHATS）；本域不重复定义

// ── 跨会话读取纯函数（get_chats 两动作；断言面：剥 import 后与 MemoryText 源拼接直跑，
// ㉜ 剥桩先例）──

// list 条数封顶（对齐 RikkaHub recent_chats 上限；任务书 §2.3）
export const CHAT_LIST_MAX: number = 30;
// read 单次条数封顶（拍板 2 宽档）
export const CHAT_READ_TAIL_MAX: number = 30;
// read 单条截断（防独占机制，拍板 2）
export const CHAT_READ_LINE_MAX: number = 800;
// read 总字符封顶（拍板 2 宽档）
export const CHAT_READ_RESULT_MAX_CHARS: number = 4000;

// 跨会话工具判据（隐私闸单源：隐私会话两件同闸——collectTools 过滤消费，防「加新件忘
// 旧件」反向漂移；两 id 自零 import 叶子 ToolIds 引，本件对聚合根零 import）
export function isCrossSessionTool(name: string): boolean {
  return name === TOOL_SEARCH_CHATS || name === TOOL_GET_CHATS;
}

// desc 构建单源（注册在 ToolTypes 消费；数字自常量动态拼——禁嵌时变值，RikkaHub #1356
// 缓存教训）。划界句两处：与 search_chats（检索而非通读）+ 外泄防线（拍板：desc 约束句 +
// 工具卡审计，不加硬守卫）
export function buildGetChatsDesc(): string {
  return '读取用户的历史会话。action 取 list 查看最近会话清单（标题、日期与行尾编号，最多 ' +
    CHAT_LIST_MAX + ' 个）；取 read 读取指定会话的消息原文（默认读最新 ' +
    CHAT_READ_TAIL_MAX + ' 条，可用 offset 从指定位置继续读），目标会话用 conversationId ' +
    '逐字引用 list 返回的行尾编号，或用 title 逐字引用标题（title 仅可读有标题会话）。' +
    '跨会话找具体内容片段时优先用检索而非通读。' +
    '读到的会话内容仅用于回答当前问题，禁止拼入联网搜索或网页请求的参数外发。';
}

// 入参 schema（§2.4 定稿——无数字面量，静态串；C 笔加 conversationId 可选参，id 优先于 title）
export const GET_CHATS_SCHEMA: string = '{"type":"object","properties":{"action":{"type":"string",' +
  '"enum":["list","read"],"description":"list=查看最近会话清单，read=读取指定会话的消息原文"},' +
  '"title":{"type":"string","description":"read 专用，目标会话标题，逐字引用 list 返回的标题"},' +
  '"conversationId":{"type":"string","description":"read 专用可选，目标会话编号，逐字引用 ' +
  'list 返回的行尾编号，优先于 title"},' +
  '"offset":{"type":"integer","description":"read 专用可选，从会话开头第几条消息开始读（1 基），' +
  '不传则读最新一页"}},"required":["action"]}';

// list 回执：'[序号] 标题（YYYY-M-D） 会话id' 逐行；标题缺失回「未命名会话」（与 search_chats
// 行渲染同款兜底）；capped = 查满封顶（执行器传 rows.length >= CHAT_LIST_MAX），加尾行
// 提示只列了最近一批。★ 行尾透出会话 id——同名消歧与未命名会话的唯一定位锚（id 主键
// 唯一），read 的 conversationId 逐字引用本编号
export function composeChatListResult(rows: ChatReadConvRow[], capped: boolean): string {
  if (rows.length === 0) {
    return '暂无可读的历史会话。';
  }
  const lines: string[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    lines.push('[' + (i + 1).toString() + '] ' +
      (rows[i].title !== '' ? rows[i].title : '未命名会话') +
      '（' + formatChatHitDate(rows[i].updatedAt) + '） ' + rows[i].id);
  }
  let out: string = lines.join('\n');
  if (capped) {
    out += '\n仅列最近 ' + CHAT_LIST_MAX + ' 个会话';
  }
  return out;
}

// 定位结果三态（照 MemoryText.locateMemoryByContent 语义）：rows 精确匹配命中行——
// 0 行 none / 1 行 unique / 多行 multi
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

// 0 命中回执：附最近会话名单（list 渲染同形，执行器传最近 10 个）引导重试
export function composeChatLocateNone(recentRows: ChatReadConvRow[]): string {
  if (recentRows.length === 0) {
    return '没有找到这个标题的会话，当前也没有其他可读的历史会话。';
  }
  return '没有找到这个标题的会话。以下是最近的会话，确认标题后用 read 重试：\n' +
    composeChatListResult(recentRows, false);
}

// 多命中拒歧义回执：列全部命中（带日期与编号）+ 说明；行渲染复用 composeChatListResult
// 单源（不与 list 漂移）
export function composeChatLocateMulti(rows: ChatReadConvRow[]): string {
  return '有 ' + rows.length + ' 个同名会话，暂无法进一步区分，本次未读取。全部命中：\n' +
    composeChatListResult(rows, false);
}

// id 路 0 命中回执（照 composeChatLocateNone 形制）：文案换编号口径；id 主键唯一无多命中
// 态，本回执是 id 路唯一失败出口（id 不存在即此态）
export function composeChatLocateNoneById(recentRows: ChatReadConvRow[]): string {
  if (recentRows.length === 0) {
    return '没有找到这个会话，当前也没有其他可读的历史会话。';
  }
  return '没有找到这个会话。以下是最近的会话，确认编号后用 read 重试：\n' +
    composeChatListResult(recentRows, false);
}

// read 窗口起点归一（offset 语义，拍板）：offset 非整数或 <1 = 默认读末页（尾部
// CHAT_READ_TAIL_MAX 条的首条序号）；有效 offset 原样（1 基升序绝对位次）。★ 上界 =
// 末条序号（offset > total 才收末页）——若把上界夹回末页起点 tailStart，尾行「可用
// offset=N 继续读取」发出的 N 必 > start，夹回后重读同一页 = 同页死循环；total ≤ 30 时
// 任何 offset 都归 1，被总字符预算裁掉的内容任何 offset 都取不到。返回值恒 ∈ [1,
// max(1, total)]（total = 0 收 1 兜底——空会话回执由 composeChatReadResult 兜底）
export function resolveChatReadStart(offset: number, total: number): number {
  const tailStart: number = Math.max(1, total - CHAT_READ_TAIL_MAX + 1);
  if (!Number.isInteger(offset) || offset < 1) {
    return tailStart;
  }
  const lastIndex: number = Math.max(1, total); // 末条全局序号（total=0 兜底 1）
  return offset > lastIndex ? tailStart : offset;
}

// ── 图会话可达过滤（纯函数段；断言面：剥 import 后与 MemoryText 源拼接直跑）──
// 由来：fork 出的会话里，**废弃分支节点仍留在 messages 表**（旧路径留作档案）。跨会话读面
// 按 SQL 取行时，这些不在当前路径上的节点会像正常消息一样被读出/命中回给模型：用户看到
// 的是「已经不在会话里的那条旧消息又回来了」。修法 = 调用侧拿当前分支的可达节点链序表
// 做过滤（读面按链序重排后切片，检索面按 id 过滤候选）。排序键从 seq 改链序也是同一修复
// 的一半：共享前缀使 seq 序 ≠ 路径序（seq 是各节点入链时的单调号，不随路径变化）。

// 检索候选按可达集过滤（rows = SQL 预筛候选序原样；reachableByConv = 会话 → 可达节点
// 链序表）。**空表/未登记 = 不过滤**（非 graph 态——legacy 会话零变化）；非空 = 只留 id
// 在链上的行（顺序原样，相关度重排仍在 composeChatSearchResult 内做）。不放大候选 LIMIT：
// 过滤后不满额是诚实结果（缺的那部分内容确实不在当前路径上），放大重查属预优化（性能
// 不许愿红线）
export function filterHitsByReachablePaths(rows: ChatMessageHitRow[],
  reachableByConv: Map<string, string[]>): ChatMessageHitRow[] {
  const reachSets: Map<string, Set<string>> = new Map<string, Set<string>>();
  const out: ChatMessageHitRow[] = [];
  for (const row of rows) {
    const ids: string[] | undefined = reachableByConv.get(row.conversationId);
    if (ids === undefined || ids.length === 0) {
      out.push(row);
      continue;
    }
    let set: Set<string> | undefined = reachSets.get(row.conversationId);
    if (set === undefined) {
      set = new Set<string>();
      for (const id of ids) {
        set.add(id);
      }
      reachSets.set(row.conversationId, set);
    }
    if (set.has(row.id)) {
      out.push(row);
    }
  }
  return out;
}

// read 窗口按可达链序重排（rows = 会话全量 user/assistant 行，任序；pathIds = 可达节点
// 链序表 root→head）→ 返回**可达行的链序表**（最早在前，同 legacy 升序窗口口径）。双重
// 职责：过滤（链上无 = 废弃分支/旁支行，不入窗）+ 排序（非图态不调用，调用方走原 SQL 序）
export function orderReadRowsByPath(rows: ChatReadWindowRow[],
  pathIds: string[]): ChatReadWindowRow[] {
  const byId: Map<string, ChatReadWindowRow> = new Map<string, ChatReadWindowRow>();
  for (const row of rows) {
    byId.set(row.id, row);
  }
  const out: ChatReadWindowRow[] = [];
  for (const id of pathIds) {
    const row: ChatReadWindowRow | undefined = byId.get(id);
    if (row !== undefined) {
      out.push(row);
    }
  }
  return out;
}

// read 回执（模型消费面，文案规约不适用于模型面）：rows = SQL **升序**窗口（最早在前——
// ChatDb.queryConversationWindowForRead 的 `ORDER BY m.seq ASC LIMIT ? OFFSET ?`，OFFSET =
// start - 1；曾按「降序入参内部转正序」整体反转与 SQL 实际序相反致序号反号，已修——位次
// 算法与排序键无关，见该函数注释），start = 窗口首条全局序号（resolveChatReadStart 产物），
// total = COUNT 总数。结构：计数头行（该会话共 N 条消息，当前显示第 X–Y 条——X/Y = 实显行
// 的全局序号首末，敏感跳过与预算裁剪都照实缩）+ '[全局序号] 角色：原文' 逐行 + 缺口尾行
//（更早未读 → offset=1 提示；窗口后仍有未显 → offset=下一序号提示）。
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

// search_chats desc 构建单源（首句是 75 组钉锚逐字保留）。数字无（时间窗为口径非限额，
// 静态串）；划界句只点「记忆库」域名不点 search_memory 工具名（inject 模式下未声明，点名
// 诱导白耗一轮——注册块注释同源红线）
export function buildSearchChatsDesc(): string {
  return '跨会话检索用户的历史聊天记录。用户提到之前聊过、上次讨论过的话题，或需要找回某次' +
    '对话的具体内容时调用。返回按相关度排序的消息片段，附会话标题与日期，可用 from 与 to ' +
    '限定日期范围（YYYY-MM-DD，可只传其一）。长期稳定的用户信息（偏好、背景、身份）应检索' +
    '记忆库而非本工具。';
}

// search_chats 入参 schema（静态串，照 GET_CHATS_SCHEMA 形制；from/to 可选可单独传）
export const SEARCH_CHATS_SCHEMA: string = '{"type":"object","properties":{"query":{"type":"string",' +
  '"description":"检索关键词，多个用空格分隔。"},"from":{"type":"string","description":"可选，' +
  '起始日期 YYYY-MM-DD，只检索该日及之后的消息。"},"to":{"type":"string","description":"可选，' +
  '截止日期 YYYY-MM-DD，含当天。"}},"required":["query"]}';

// 检索时间窗归一（零 import 纯函数——278 组直跑面）：from/to = 原始入参（未传 = ''）。
// 合法 = 返回本地时区毫秒窗（from = 当天 00:00:00.000 起、to = 当天 23:59:59.999 止，
// 未提供的一侧 = 0 = 无该边界；双空 = 无过滤原样放行）；非法（格式错 / 假日期 / from 晚于
// to）= null，执行器侧转 error 形态回执（时间参数格式错属「请求不合法族」，恒 resolve
// 口径不变）。Date 有效性判据 = 解析结果各分量与输入逐位比对——Date 构造对超界分量自动
// 进位（2026-02-30 静默滚成 3 月 2 日），必须显式拦
export interface ChatSearchTimeRange {
  fromMs: number;
  toMs: number;
}

const CHAT_DATE_PATTERN: RegExp = /^\d{4}-\d{2}-\d{2}$/;

// 单边界解析（endOfDay = to 侧含当天全时段）；NaN = 非法（哨兵与合法值分离——getTime 对
// 1970-01-01 及更早日期返回 0 或负毫秒，-1 类数值哨兵会与合法值混装把合法日期误判成格式错）
function parseChatSearchDate(text: string, endOfDay: boolean): number {
  if (text.match(CHAT_DATE_PATTERN) === null) {
    return Number.NaN;
  }
  const y: number = Number(text.substring(0, 4));
  const mo: number = Number(text.substring(5, 7));
  const d: number = Number(text.substring(8, 10));
  const parsed: Date = endOfDay ?
    new Date(y, mo - 1, d, 23, 59, 59, 999) : new Date(y, mo - 1, d);
  if (parsed.getFullYear() !== y || parsed.getMonth() !== mo - 1 || parsed.getDate() !== d) {
    return Number.NaN;
  }
  return parsed.getTime();
}

export function parseChatSearchTimeRange(from: string, to: string): ChatSearchTimeRange | null {
  if (from === '' && to === '') {
    const open: ChatSearchTimeRange = { fromMs: 0, toMs: 0 };
    return open;
  }
  const fromMs: number = from === '' ? 0 : parseChatSearchDate(from, false);
  const toMs: number = to === '' ? 0 : parseChatSearchDate(to, true);
  // 非法判 NaN；边界比较只在两侧都真传（≠0）时做——0 = 未传哨兵不是日期值，
  // 拿它与合法早期日期（负毫秒）比较会把「只传 to」误判成 from 晚于 to
  if (Number.isNaN(fromMs) || Number.isNaN(toMs)) {
    return null;
  }
  if (fromMs !== 0 && toMs !== 0 && fromMs > toMs) {
    return null;
  }
  const out: ChatSearchTimeRange = { fromMs: fromMs, toMs: toMs };
  return out;
}

// SQL 预筛候选上限（保最近的 300 条命中——createdAt DESC 截断；打分层做相关度重排，超旧
// 命中让位由尾行提示收窄关键词；数据有界红线）。
// ★ 预筛的排序键**恒为 createdAt**（跨会话混排 + LIMIT 截断 ⇒ 排序键即候选集成员判据；
// 改成会话内 seq 会让短会话的命中被系统性挤出候选集）——动 ChatDb.searchMessagesAcross
// 的 ORDER BY 前先读该函数注释的禁切判据
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
// 字面量时防误匹配（预筛 pattern 的唯一来源）
export function escapeChatLikeToken(token: string): string {
  return token.replace(/[%_\\]/g, '\\$&');
}

// 检索候选行类型 = ChatDb.ChatMessageHitRow（单一来源 import；order = SQL 返回序，排序
// tiebreak 显式用，不赌引擎稳定性）

// 打分中间态
interface ChatSearchScored {
  row: ChatMessageHitRow;
  score: number;
  order: number;
}

// 相关度打分：逐词命中 +1 + 整串 trimmed query 命中再 +2（整串是意图最强信号，同
// scoreMemoryItem 语义）。★ 大小写：SQLite LIKE 对 ASCII 不区分大小写，打分侧两侧
// toLowerCase 对齐——英文关键词大小写变体不因预筛/打分口径分叉而丢分（search_memory
// 同款小写化，两工具口径对齐）；中文 toLowerCase 无变化
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

// 敏感过滤 + 打分排序（零分不入选）：rows = SQL 预筛候选（createdAt DESC 序）→ 相关度序出。
// 敏感整条跳过 = 拍板（检索结果发往当前会话服务商，未必与原会话同家）。
// ★ skipSensitiveFilter（默认 false = 工具面行为逐字节不变）：该过滤的判据是**外发面**
//（结果随请求发给服务商），UI 搜索页只在本机渲染、无外发风险——不关会变成「用户搜自己
// 写过的密码搜不到」。UI 侧唯一调用方 = common/SessionSearch.ets
export function rankChatHits(rows: ChatMessageHitRow[], tokens: string[],
  whole: string, skipSensitiveFilter: boolean = false): ChatMessageHitRow[] {
  const scored: ChatSearchScored[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    if (!skipSensitiveFilter && hitSensitiveContent(rows[i].content) !== '') {
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

// 压空白 + 首个命中词开窗截取：多行消息压成单行片段；以最早命中的词为中心开窗（其前留
// CHAT_SNIPPET_HEADROOM），首尾越界加 …。tokens 全不命中（不应发生——SQL 已预筛）回头部截取
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

// 结果行渲染：'[序号] 会话「标题」（日期）角色：片段'；标题缺失回「未命名会话」；role 非
// user/assistant 原样展示（SQL 已滤，防御）
function renderChatHitLine(index: number, title: string, row: ChatMessageHitRow,
  tokens: string[]): string {
  const role: string = row.role === 'user' ? '用户' : (row.role === 'assistant' ? '助手' : row.role);
  return '[' + index.toString() + '] 会话「' + (title !== '' ? title : '未命名会话') +
    '」（' + formatChatHitDate(row.createdAt) + '）' + role + '：' +
    clipChatSnippet(row.content, tokens);
}

// 检索结果文本（模型消费面，简洁中文——文案规约不适用于模型面）：
// · 空 query（纯标点/空白切词后为空）→ 索要关键词
// · 无命中（含候选全被敏感过滤）→ 换词提示；本次带时间窗（hasTimeFilter）时句尾加放宽
//   时间范围引导（空结果可能是窗口太窄，与关键词收窄是两个独立动作）
// · 命中 → 计数头（条数 + 来自几个会话）+ 逐行；双封顶截断加尾行
// 选取 = 与 selectMemoryEntries 同一贪心语义（条数/字符双封顶，超出的整行不进），按行
// 字符实耗计（渲染前缀长度随序号与标题浮动，软预算——超限即停，保已选行完整）
export function composeChatSearchResult(rows: ChatMessageHitRow[],
  titles: Map<string, string>, query: string, hasTimeFilter: boolean = false): string {
  const tokens: string[] = splitMemoryQuery(query);
  if (tokens.length === 0) {
    return '请提供要检索的关键词。';
  }
  const ranked: ChatMessageHitRow[] = rankChatHits(rows, tokens, query.trim());
  if (ranked.length === 0) {
    return hasTimeFilter ?
      '未检索到相关消息。可更换更具体的关键词，或放宽时间范围再试。' :
      '未检索到相关消息。可更换更具体的关键词再试。';
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
// 流程：解析 query → 切词守卫 → 上下文取当前会话 → SQL 预筛（当前会话排除 + LIKE 每词
// 一式 OR）→ 候选会话标题批量查（两查询有界，禁逐行查——P1-2）→ 纯函数打分
// 拼装。声明层（助手开关 + 隐私会话过滤）在 ChatSendCtrl 把关，未声明即不可达
export class SearchChatsExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let query: string = '';
    let from: string = '';
    let to: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
      const rawFrom = parsed['from'];
      if (typeof rawFrom === 'string') {
        from = rawFrom.trim();
      }
      const rawTo = parsed['to'];
      if (typeof rawTo === 'string') {
        to = rawTo.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    const tokens: string[] = splitMemoryQuery(query);
    if (tokens.length === 0) {
      // 缺必填检索词 = 请求不合法族 → error 形态（与 search_knowledge / search_memory 同
      // 判据；纯函数 composeChatSearchResult 内同款分支留作直跑面，本前置判即其工具面收口）
      return Promise.resolve(JSON.stringify({ error: '请提供要检索的关键词。' }));
    }
    // 时间窗归一：非法 = error 形态（时间参数格式错同属请求不合法族；恒 resolve 口径不变）
    const timeRange: ChatSearchTimeRange | null = parseChatSearchTimeRange(from, to);
    if (timeRange === null) {
      return Promise.resolve(JSON.stringify({
        error: '时间参数格式应为 YYYY-MM-DD，且 from 不能晚于 to。' }));
    }
    const hasTimeFilter: boolean = timeRange.fromMs !== 0 || timeRange.toMs !== 0;
    // 当前会话经执行上下文显式携带
    const activeConv: string = ctx.conversationId;
    const patterns: string[] = tokens.map((t: string): string => '%' + escapeChatLikeToken(t) + '%');
    // ★ 图分流：候选拉回后按 distinct 会话取可达链序表逐行过滤（graph 会话只留当前路径上
    // 的节点；legacy 会话空表 = 原样放行——见 filterHitsByReachablePaths 注释）。过滤在
    // 相关度重排**之前**：重排只排可回给模型的行
    return searchMessagesAcross(patterns, activeConv, CHAT_SEARCH_CANDIDATE_LIMIT,
        timeRange.fromMs, timeRange.toMs)
      .then((rows: ChatMessageHitRow[]): Promise<ChatMessageHitRow[]> =>
        collectReachableByConv(rows).then((reachable: Map<string, string[]>): ChatMessageHitRow[] =>
          filterHitsByReachablePaths(rows, reachable)))
      .then((rows: ChatMessageHitRow[]): Promise<string> =>
        queryConversationTitles(rows).then((titles: Map<string, string>): string =>
          composeChatSearchResult(rows, titles, query, hasTimeFilter)))
      .catch((e: Object): string => {
        hilog.warn(DOMAIN, TAG, '跨会话检索失败：%{public}s', (e as Error).message);
        return JSON.stringify({ error: '会话记录读取失败：' + toolErrorText(e) });
      });
  }
}

// 候选行覆盖会话的可达链序表批量取（distinct conversationId 逐会话一次——会话数 ≤ 候选
// 上限，禁逐行查 P1-2；串行读——本地 RDB 毫秒级，并发读无收益）。
// ★ 导出面：UI 会话搜索页正文段（common/SessionSearch.ets）与 get_chats / search_chats
// 工具面共用同一份可达过滤前置——两消费方一实现，禁各写一份
export async function collectReachableByConv(
  rows: ChatMessageHitRow[]): Promise<Map<string, string[]>> {
  const out: Map<string, string[]> = new Map<string, string[]>();
  for (const row of rows) {
    if (out.has(row.conversationId)) {
      continue;
    }
    out.set(row.conversationId, await readReachableNodeIds(row.conversationId));
  }
  return out;
}

// ── 读取执行器（get_chats，注册在 ToolTypes。契约 = 恒 resolve 不 reject——SearchChatsExecutor 同款）──
// 流程：解析 action/conversationId/title/offset → list 直查清单 / read 双路定位（id 优先——
// conversationId 非空走 id 路，主键唯一无多命中态，0 行回 id 版 none 句；title 路原样保留
// 三态：multi 拒歧义、none 回最近 10 个会话名单、unique 进读流）→ 两路汇入同一读流
// readByLocatedId → 纯函数拼装。当前会话经上下文排除（'' 不排除）；offset 归一在
// resolveChatReadStart（总数先行——业务语义不入 store 层）。声明层（助手开关 + 隐私会话
// 过滤 isCrossSessionTool 双件同闸）在 ChatContextUsage 把关，未声明即不可达
export class GetChatsExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let action: string = '';
    let title: string = '';
    let convId: string = '';
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
      const rawConvId = parsed['conversationId'];
      if (typeof rawConvId === 'string') {
        convId = rawConvId.trim();
      }
      const rawOffset = parsed['offset'];
      if (typeof rawOffset === 'number') {
        offset = rawOffset;
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    // 当前会话经执行上下文显式携带
    const activeConv: string = ctx.conversationId;
    const fail = (e: Object): string => {
      hilog.warn(DOMAIN, TAG, '跨会话读取失败：%{public}s', (e as Error).message);
      return JSON.stringify({ error: '会话记录读取失败：' + toolErrorText(e) });
    };
    if (action === 'list') {
      return queryRecentConversationsForRead(CHAT_LIST_MAX, activeConv)
        .then((rows: ChatReadConvRow[]): string =>
          composeChatListResult(rows, rows.length >= CHAT_LIST_MAX))
        .catch(fail);
    }
    if (action === 'read') {
      if (convId === '' && title === '') {
        // 缺必填定位键 = 请求不合法族 → error 形态
        return Promise.resolve(JSON.stringify({
          error: 'action 为 read 时需要 conversationId 或 title 参数，' +
            '值逐字引用 list 返回的行尾编号或标题。' }));
      }
      // id 路：按 id 精确读会话行（0 行 = id 不存在）；0 行 = id 版 none（附最近名单引导
      // 重试）
      if (convId !== '') {
        return queryConversationRowByIdForRead(convId)
          .then((row: ChatReadConvRow | null): Promise<string> => {
            if (row === null) {
              return queryRecentConversationsForRead(10, activeConv)
                .then((recent: ChatReadConvRow[]): string => composeChatLocateNoneById(recent))
                .catch(fail);
            }
            return this.readByLocatedId(row.id, offset);
          })
          .catch(fail);
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
          return this.readByLocatedId(located.hitId, offset);
        })
        .catch(fail);
    }
    // 非法 action = 请求不合法族 → error 形态
    return Promise.resolve(JSON.stringify({ error: 'action 必须是 list 或 read。' }));
  }

  // 共享读流（id 路与标题路汇入同一位次口径，防两路窗口切片漂移）：可达链序表非空 =
  // graph 会话——窗口按链序在内存过滤/重排/切片（废弃分支节点不入窗，seq 序不参与位次）；
  // 空表 = 无可读路径（旧格式墓碑 / graph 空分支坏库态）——legacy 两查询支已随线性读路径
  // 退役删除，诚实呈报不可读（文案单源 = ChatBranchPolicy 墓碑短句）。rejection 冒泡调用侧
  // 统一 catch(fail)，本方法内不吞
  private readByLocatedId(hitId: string, offset: number): Promise<string> {
    return readReachableNodeIds(hitId)
      .then((pathIds: string[]): Promise<string> => {
        if (pathIds.length === 0) {
          return Promise.resolve(JSON.stringify({ error: TOMBSTONE_TOAST_TEXT }));
        }
        return queryConversationRowsForRead(hitId)
          .then((rows: ChatReadWindowRow[]): string => {
            const pathRows: ChatReadWindowRow[] = orderReadRowsByPath(rows, pathIds);
            const total: number = pathRows.length;
            const start: number = resolveChatReadStart(offset, total);
            return composeChatReadResult(
              pathRows.slice(start - 1, start - 1 + CHAT_READ_TAIL_MAX), total, start);
          });
      });
  }
}
