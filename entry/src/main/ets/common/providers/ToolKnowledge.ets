// 知识库工具域（用户可见名「知识库」，世界书 / World Book / Lorebook 只活在文档与注释里）：
// 两件——search_knowledge 检索知识库条目（search / list 两动作，**只读**，作用域 = 本助手启用
// 集）+ manage_knowledge 管理知识库与条目（list / get / read_file / create_book / create /
// update / delete 七动作，作用域 = **全部书**；create/update/delete 三写 + create_book 建库是
// 全工程**唯一写口**，get 与 read_file 是读动作，附件写口全在 UI）。
// 同文件两工具先例 = ToolSkill.ets（use_skill + manage_skills 同居）。
//
// · 域职责：desc 与 schema 单源 + 执行器编排。纯函数在 KnowledgeText.ets（零 import 域，断言
//   脚本复制直跑），行读写在 KnowledgeDb.ets；注册在 ToolTypes（聚合根，本文件不反向引它——
//   模块环红线，见 ToolContracts.ets 头注释）。
// · ★ 读写分界：**检索件仍只读**（白名单恰 search/list）；**管理件是唯一写口**（三写 + 建库，
//   书级不开放改名与删库），另含 get（读回单条正文）与 read_file（读回附件原文）两读动作——
//   作用域同写口 = 全部书、不受启用集限制（「指名读那一条」没有理由被启用集挡住，这正是
//   「助手写完自己读不回」的出口）。知识库与记忆的边界两条并立（决明拍板）：①按来源——知识库
//   = 用户授权的写入（人写或助手按用户指令代言整理），记忆 = 模型自主沉淀；②按内容——知识库
//   = 与用户本人无关的领域知识，记忆 = 关于用户本人的、随时间变化的事实（主句，两件 desc 的
//   划界句同此）。「工具操作面 ⊆ UI 操作面」红线仍成立且工具侧**更窄**（UI 有书级改名删库与
//   附件增改删，工具没有）。
// · ★ 附件：附件挂在**条目**下（knowledge_files，件名条目内唯一），检索面**完全不涉文件**
//   （不进索引，是刻意边界而非遗漏）；取用路径 = get 回执列件名 → read_file。零附件时 get
//   回执逐字节同无附件版（fileNames 恒空 ⇒ 零输出，不变量）。
// · ★ 回执条数恒**写后重取**（create / delete / create_book 三处，修并发竞态）：一轮内多个非
//   交互工具走 Promise.all 并发，拿写前计数加一会双双少报；重取 = 本条写入完成那一刻的库态
//  （回归 = assert-knowledge-domain 162 组）。
// · ★ 执行者助手 id 经执行上下文携带（ToolExecutionContext.knowledgeAssistantId，恒取
//   ownerAssistantId()，接纳时一次快照随链下传）——原 AppStorage 中转键（下方
//   KNOWLEDGE_EXEC_ASSISTANT_KEY）**已退役**；'' = 无上下文（异常路径，P0-1 明确回错不静默）。
// · ★ 隐私边界：知识库是**用户授权的知识**，不是会话内容——两件**都不进 ToolChatSearch.isCrossSessionTool 名单**，
//   隐私会话照常声明（与 search_memory 同判）。反向
//   也成立：**禁**把本域工具名加进该名单——那会让用户在隐私会话查不了自己写的词条本，属无依据
//   的功能收窄。
// · ★ 声明层（ChatContextUsage.collectTools）：两件都是**常规工具**（走 assistants.tools 通道 /
//   助手工具页「知识库」卡开关），不入 MODE_DRIVEN_TOOLS、不入 CONSOLE_EXCLUSIVE_TOOLS。助手
//   未启用知识库时两件**仍可被声明**（声明层不做知识库态判定），由执行器回引导串讲清「没启用」。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { appendReceiptDiffTail, ConfirmPrompt, CONFIRM_LEVEL_IRREVERSIBLE, ToolExecutor,
  toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { dataApproveMode } from '../AppPreferences';
import { AssistantRow, queryAssistant } from '../store/AssistantDb';
import { broadcastKnowledgeList, countBooks, countEntries, countEntriesOfBooks, deleteEntry,
  insertBook, insertEntry, KNOWLEDGE_BOOK_MAX, KNOWLEDGE_ENTRY_MAX, KnowledgeBookRow,
  KnowledgeEntryInput, KnowledgeEntryRow, KnowledgeFileRow, queryBooks, queryEntries,
  queryEntriesByBookIds, queryEntryFiles, toBookItems, toEntryItems, updateEntry } from '../store/KnowledgeDb';
import { composeKnowledgeListResult, composeKnowledgeManageCreateEntryReply,
  composeKnowledgeManageCreateReply, composeKnowledgeManageDeleteReply,
  composeKnowledgeManageGetReply,
  composeKnowledgeManageListReply, composeKnowledgeManageReadFileReply,
  composeKnowledgeManageUpdateReply,
  composeKnowledgeSearchResult, composeKnowledgeTitleTakenReply, clampKnowledgePriority,
  clampKnowledgeScan, KNOWLEDGE_CONTENT_MAX,
  KNOWLEDGE_KEYWORDS_MAX, KNOWLEDGE_LIST_DEFAULT_COUNT, KNOWLEDGE_LIST_MAX_COUNT,
  KNOWLEDGE_TITLE_MAX, knowledgeBookNameTaken, knowledgeTitleTaken, KnowledgeEntryItem,
  KnowledgeFileLocateOutcome, locateKnowledgeFileByName, parseEnabledKnowledgeIds,
  selectKnowledgeHits } from '../KnowledgeText';

const DOMAIN: number = 0x71C4;
const TAG: string = 'ToolKnowledge';

// 执行者助手中转键（**已退役**：值改经 ToolExecutionContext.knowledgeAssistantId 携带）。键位
// 保留仅作兼容，**全仓零读写**——勿按现役口径新增 AppStorage 读写
export const KNOWLEDGE_EXEC_ASSISTANT_KEY: string = 'knowledgeExecAssistantId';

// 入参 schema（静态串；两动作语义写在 description 里，模型据此选路；分页两参随常量拼接、
// 禁写死——与下方管理件同口径）
export const SEARCH_KNOWLEDGE_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["search","list"],' +
  '"description":"search=按关键词检索知识条目，list=查看知识库条目清单"},' +
  '"query":{"type":"string","description":"search 专用，检索关键词，多个用空格分隔"},' +
  '"offset":{"type":"integer","description":"list 专用，从第几条开始（默认 1）"},' +
  '"limit":{"type":"integer","description":"list 专用，本页条数（默认 ' +
  KNOWLEDGE_LIST_DEFAULT_COUNT + '，最大 ' + KNOWLEDGE_LIST_MAX_COUNT + '）"}},' +
  '"required":["action"]}';

// 引导串（三条「问法不对/前置未备」路径——都是让模型下一步能走对，不是错误报告）：前两条属
// **请求不合法族**（非法 action / 缺必填词）→ error 形态、卡面「出错」态；第三条属**业务/配置
// 结论**（该助手没启用知识库）→ 照旧中文文本、卡面完成态（与「空库」「未命中」同族）
const KNOWLEDGE_NO_BOOK_TIP: string =
  '当前助手未启用任何知识库。请在助手编辑页的知识库里启用后再试。';
const KNOWLEDGE_NEED_QUERY_TIP: string =
  '请提供要检索的关键词，或改用 action 为 list 查看条目清单。';
const KNOWLEDGE_BAD_ACTION_TIP: string = 'action 必须是 search 或 list。';

// desc 单源（注册在 ToolTypes 消费；三段式 = 调用时机 / 返回形态 / 划界）。★ 划界句**不点未
// 声明工具的具名**（点名会诱导模型调用未声明工具白耗一轮——既有红线，见 ToolTypes 的
// search_chats 注册块注释）。★ 全文零数字字面量（RikkaHub #1356 缓存教训：不嵌时变值）
export function buildSearchKnowledgeDesc(): string {
  return '检索用户手写的知识库条目。用户的问题涉及某个领域的专门知识，' +
    '例如术语、设定、规范、人物或事物背景，而对话上下文里没有这些信息时调用。' +
    '返回命中的条目原文，附所属知识库名。action 取 list 可先查看有哪些条目，' +
    '该清单分页，每页默认 ' + KNOWLEDGE_LIST_DEFAULT_COUNT + ' 条，更多用 offset 继续看。' +
    '动作 search 需要 query。长期稳定的用户信息，例如偏好、背景、身份，' +
    '应检索记忆库，技能是模型加载的做法说明，两者与本工具不同族。';
}

// 知识库检索执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject，错误走 JSON 错误信息
// ——SearchChatsExecutor / GetChatsExecutor 同款）
export class SearchKnowledgeExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let action: string = '';
    let query: string = '';
    let offset: number = 1;
    let limit: number = KNOWLEDGE_LIST_DEFAULT_COUNT;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const rawAction = parsed['action'];
      if (typeof rawAction === 'string') {
        action = rawAction.trim();
      }
      const rawQuery = parsed['query'];
      if (typeof rawQuery === 'string') {
        query = rawQuery.trim();
      }
      // list 分页两参（search 动作不消费；区间夹取在回执层）
      offset = readIntArg(parsed, 'offset', 1);
      limit = readIntArg(parsed, 'limit', KNOWLEDGE_LIST_DEFAULT_COUNT);
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    // 纯参数错先判（不读库；两动作白名单）——请求不合法族 = error 形态
    if (action !== 'search' && action !== 'list') {
      return Promise.resolve(rejectInvalidArgs(KNOWLEDGE_BAD_ACTION_TIP));
    }
    // 执行者助手 id 经执行上下文携带（中转键已退役）
    const assistantId: string = ctx.knowledgeAssistantId;
    if (assistantId === '') {
      return Promise.resolve(JSON.stringify({ error: '未取到当前助手上下文，无法读取知识库' }));
    }
    const fail = (e: Object): string => {
      hilog.warn(DOMAIN, TAG, '知识库读取失败：%{public}s', toolErrorText(e));
      return JSON.stringify({ error: '知识库读取失败：' + toolErrorText(e) });
    };
    return queryAssistant(assistantId)
      .then((row: AssistantRow | null): Promise<string> => {
        // 助手行查不到（已删/坏 id）按空集处理：与「未启用」同引导串——区分两者没有可执行的下一步
        const enabledIds: string[] = parseEnabledKnowledgeIds(row !== null ? row.knowledge : '');
        if (enabledIds.length === 0) {
          return Promise.resolve(KNOWLEDGE_NO_BOOK_TIP);
        }
        // 一次取全部已启用库的条目（**禁逐库查**——轻量检测纪律）
        return queryEntriesByBookIds(enabledIds)
          .then((rows: KnowledgeEntryRow[]): Promise<string> => {
            // 条目级停用过滤：enabled=0 整条停用——检索与浏览不返回；管理面清单不过滤
            //（要看得见停用条目）
            const pool: KnowledgeEntryRow[] = rows.filter((row: KnowledgeEntryRow): boolean =>
              row.enabled !== 0);
            return queryBooks().then((books: KnowledgeBookRow[]): string => {
              // 只留已启用的库行（表头计数与所见条目同源；传全库会让「已启用 N 个」虚高）
              const enabledBooks: KnowledgeBookRow[] =
                books.filter((book: KnowledgeBookRow): boolean => enabledIds.includes(book.id));
              // 纯函数域形态适配（ArkTS 禁结构类型——见 KnowledgeDb 适配组注释）
              const entryItems: KnowledgeEntryItem[] = toEntryItems(pool);
              if (action === 'list') {
                return composeKnowledgeListResult(toBookItems(enabledBooks), entryItems,
                  offset, limit);
              }
              if (query === '') {
                // 缺必填检索词同族 = error 形态（search_chats / search_memory 同判据）
                return rejectInvalidArgs(KNOWLEDGE_NEED_QUERY_TIP);
              }
              const names: Map<string, string> = new Map<string, string>();
              for (const book of enabledBooks) {
                names.set(book.id, book.name);
              }
              // limit 传 0 = 把全部候选交给拼装层，由它按双封顶截断并据实加尾行
              return composeKnowledgeSearchResult(selectKnowledgeHits(entryItems, query, 0), names);
            });
          })
          .catch(fail);
      })
      .catch(fail);
  }
}

// ── 管理知识库工具（内置第 26 件；对标 manage_memory / manage_skills 形制）──
// 七动作 = list / get / read_file / create_book / create / update / delete——**书级只开放建库**
//（改名与删库留给设置页：删除不可逆且 UI 有确认链，desc 里给指路）；get / read_file 均只读。
// · 定位范围 = **全部书**（不取启用集）——★ 与检索件的「启用集」作用域**刻意不同**（新建书默认
//   不被启用，写动作卡启用集则助手刚建的书写不进去）。**「闸」与「建议」之别**（防顺手收紧成
//   与检索同域）：①闸 = 写动作**不受**启用集限制，用户指明书名就用该书；②建议 = book 缺席时
//   回执把该助手**已启用**的库列为建议落点（空则建议先 create_book）。assistantId 仍取
//  （P0-1 存在性守卫），但**不拿它做写权限判定**。
// · update **只改传入的字段**（未传/空串保持原值，照 manage_skills 明文）——updateEntry 原语是
//   整体替换语义，**必须回填未传字段**否则会把正文清空。
// · 重名拦截：**条目**单源 = knowledgeTitleTaken、**书名**单源 = knowledgeBookNameTaken（编辑页
//   同用）；**不加 DB 唯一索引**（存量重名会让迁移失败，应用层已覆盖全部写入口）。
// · 写入恒 source='assistant'（编辑页恒 'user'）；update 不改 source。
// · 恒 resolve 不 reject：**回执两形态**（定界 = 请求不合法 → 出错态 / 请求合法但业务做不到 →
//   完成态，防后人再猜）——error 形态（JSON 壳，卡面「出错」态、事实链 failed，与
//   detectErrorResult 判据对齐）覆盖：①请求不合法族（一律经 rejectInvalidArgs 包壳：解析失败 /
//   非法 action / 缺 book·title·file / 三位超限〔create 与 update 两链〕/ 容量上限〔决明拍板：
//   容量类一律出错态〕/ update 三选一守卫）；②catch 异常；③执行上下文缺失。中文文本形态
//  （完成态）覆盖业务拒绝（未命中 / 重名歧义 / 零附件 / 未启用）——执行器正常返回的拒绝结论。
//   兜底由 executeToolCall 包装 error JSON 不炸轮次；三写点后 broadcastKnowledgeList。
// · ★ 存量重名两条歧义路径（库内条目重名 / 跨库书名重名，旧数据可能有）：工具侧一律**拒歧义
//   并如实回执**（不猜、不静默取第一条——P0-1），指引用户到设置页处理。

// 入参 schema（静态串；上限数字随常量单源动态拼、禁写死——照 MANAGE_MEMORY_SCHEMA 先例）。
// 确认链预检：**只拦 delete**（删除不可恢复，读向与其余写向照旧直通），档位恒
// CONFIRM_LEVEL_IRREVERSIBLE（恒问人；三档豁免与去向归一在 routeConfirmPrompt 单点）。
// book/title 缺一 = 执行器报参数引导、不弹卡；主因句带库名与条目名各截 30 字。全包 try/catch 恒 null
export async function manageKnowledgeNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const actionRaw: Object | undefined = parsed['action'];
    if (typeof actionRaw !== 'string' || actionRaw.trim() !== 'delete') {
      return null;
    }
    const clip30 = (raw: Object | undefined): string => {
      const v: string = typeof raw === 'string' ? raw.trim() : '';
      return v.length > 30 ? v.substring(0, 30) + '…' : v;
    };
    const book: string = clip30(parsed['book']);
    const title: string = clip30(parsed['title']);
    if (book === '' || title === '') {
      return null;
    }
    return routeConfirmPrompt({ text: '删除知识库「' + book + '」的条目「' + title + '」',
      level: CONFIRM_LEVEL_IRREVERSIBLE }, dataApproveMode());
  } catch (e) {
    return null;
  }
}

export const MANAGE_KNOWLEDGE_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["list","get","read_file","create_book","create","update","delete"],' +
  '"description":"list=查看知识库清单或某库的条目标题，get=读取某条目的全文，' +
  'read_file=读取某条目下的一份文件，create_book=新建一个知识库，create=新增条目，' +
  'update=修改条目，delete=删除条目"},' +
  '"book":{"type":"string","description":"知识库名称（' + KNOWLEDGE_TITLE_MAX +
  ' 字内），逐字取自 list 回执。list 可选，填了就列该库的条目；其余动作必填"},' +
  '"title":{"type":"string","description":"条目名称。create 必填；get、read_file、update 与 ' +
  'delete 用它定位，须与 list 返回的标题逐字一致"},' +
  '"file":{"type":"string","description":"read_file 必填，文件名逐字取自 get 回执的文件行"},' +
  '"keywords":{"type":"string","description":"create 与 update 可选，多个用逗号分隔（' +
  KNOWLEDGE_KEYWORDS_MAX + ' 字内）"},' +
  '"content":{"type":"string","description":"create 必填，update 可选，条目正文（' +
  KNOWLEDGE_CONTENT_MAX + ' 字内）；update 为整体替换而不是追加"},' +
  '"new_title":{"type":"string","description":"update 专用可选，改名后的新名称"},' +
  '"matchCase":{"type":"boolean","description":"create 与 update 可选，区分大小写，默认 false"},' +
  '"matchWhole":{"type":"boolean","description":"create 与 update 可选，整词匹配，只对英文单词生效"},' +
  '"priority":{"type":"integer","description":"create 与 update 可选，0 到 9999，默认 100，' +
  '数值大的先注入"},' +
  '"scanDepth":{"type":"integer","description":"create 与 update 可选，1 到 20，默认 8"},' +
  '"offset":{"type":"integer","description":"list 专用，从第几条开始（默认 1）"},' +
  '"limit":{"type":"integer","description":"list 专用，本页条数（默认 ' +
  KNOWLEDGE_LIST_DEFAULT_COUNT + '，最大 ' + KNOWLEDGE_LIST_MAX_COUNT + '）"}},' +
  '"required":["action"]}';

// desc 单源（注册在 ToolTypes 消费）。★ 划界句**只点域名不点工具名**（点名会诱导模型调用未
// 声明工具白耗一轮——既有红线，见 ToolTypes 的 search_chats 注册块注释）；★ 上限数字随常量
// 拼接、禁写死（RikkaHub #1356 缓存教训：不嵌时变值）
export function buildManageKnowledgeDesc(): string {
  return '管理知识库。知识库是用户授权的领域知识条目，人写或由助手按用户要求整理，' +
    '内容与用户本人无关。关于用户自己的偏好、背景、身份与交代过的事，属于记忆库，' +
    '不在本工具范围，请用记忆那一族。' +
    'action 取 list 查看知识库清单，带 book 参数时列出该库的条目标题，' +
    '清单分页，每页默认 ' + KNOWLEDGE_LIST_DEFAULT_COUNT + ' 条，更多用 offset 继续看；' +
    'create_book 新建一个知识库；create 新增条目，需 book 与 title，keywords 可选；' +
    'get 读取某条目的全文，需 book 与 title，改正文前先用它拿到当前全文，' +
    '条目有附件文件时回执里会多一行文件清单；' +
    'read_file 读取其中一份文件的全文，需 book、title 与 file，file 逐字取自该行文件清单；' +
    'update 与 delete 先 list 拿到条目标题，再用 book 与 title 逐字定位。' +
    'update 只改传入的字段，未传或传空串的字段保持原值。' +
    '同一知识库内条目不允许重名，重名会被拒绝并返回该书现有标题。' +
    '单条正文上限 ' + KNOWLEDGE_CONTENT_MAX + ' 字，一个知识库上限 ' + KNOWLEDGE_ENTRY_MAX +
    ' 条，知识库总数上限 ' + KNOWLEDGE_BOOK_MAX + ' 个。' +
    '可选设置触发精度：区分大小写、整词匹配、优先级、检查最近消息条数。' +
    '知识库本身的改名与删除不在本工具范围，需要时到 设置 → 知识库 操作。' +
    '仅在用户明确要求时调用，执行后向用户复述改了什么。';
}

// 取字符串参数（非字符串/缺省归 '' 并 trim）。★ 两件各留一份取值块是刻意的（域内自持，不跨件
// 合并——KnowledgeText 头注释同条纪律）
function readStrArg(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw.trim() : '';
}

// 取整数参数（非整数/缺省 → fallback；脏值不报错、由回执层夹取——照 manage_skills /
// manage_memory 的「脏值归默认不报错」口径，模型少一轮纠错）
function readIntArg(parsed: Record<string, Object>, key: string, fallback: number): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' && Number.isInteger(raw) ? raw : fallback;
}

// 可选布尔（缺省/脏类型 → undefined = 未传）：update「只改传入的字段」要求区分「显式传
// false」与「未传」——readStrArg 的归 '' 姿势在这组不适用
function readOptBoolArg(parsed: Record<string, Object>, key: string): boolean | undefined {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'boolean' ? raw : undefined;
}

// 可选整数（缺省/脏值 → undefined = 未传；越界由 clamp 收口不报错——同宽容口径）
function readOptIntArg(parsed: Record<string, Object>, key: string): number | undefined {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' && Number.isInteger(raw) ? raw : undefined;
}

// 书名精确匹配命中集（trim 逐字）；0/多命中由调用方如实回执（多命中 = 存量重名书，禁猜）
function matchBooks(books: KnowledgeBookRow[], name: string): KnowledgeBookRow[] {
  return books.filter((row: KnowledgeBookRow): boolean => row.name.trim() === name);
}

// 书清单逐行（回执里的可选书名列表——「没有这本书」与「book 缺席」两条路径共用）
function bookNameLines(books: KnowledgeBookRow[]): string {
  return books.map((row: KnowledgeBookRow): string => '【' + row.name + '】').join('\n');
}

// 条目名 → 三位上限校验（与编辑页 maxLength 同源常量——不设会造出 UI 造不出的超限数据）
function checkFieldLengths(title: string, keywords: string, content: string): string {
  if (title !== '' && title.length > KNOWLEDGE_TITLE_MAX) {
    return '条目名称超过 ' + KNOWLEDGE_TITLE_MAX + ' 字，本次未写入。请精简后重试。';
  }
  if (keywords.length > KNOWLEDGE_KEYWORDS_MAX) {
    return '关键词超过 ' + KNOWLEDGE_KEYWORDS_MAX + ' 字，本次未写入。请精简后重试。';
  }
  if (content.length > KNOWLEDGE_CONTENT_MAX) {
    return '条目正文超过 ' + KNOWLEDGE_CONTENT_MAX + ' 字，本次未写入。请精简后重试。';
  }
  return '';
}

// 请求不合法族回执壳：validate / 字段校验 / 缺必填 / 超限 / 容量拦截一律经本函数包 error 形态
//（卡面「出错」态，与 detectErrorResult 判据对齐）；**业务拒绝不走本壳**（未命中 / 歧义 / 重名 /
// 空库 / 零附件——照旧中文文本、完成态）。单点收口 = 防后人漏包一处
function rejectInvalidArgs(text: string): string {
  return JSON.stringify({ error: text });
}

// 知识库管理执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject）
export class ManageKnowledgeExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let action: string = '';
    let book: string = '';
    let title: string = '';
    let keywords: string = '';
    let content: string = '';
    let newTitle: string = '';
    let fileName: string = '';
    let offset: number = 1;
    let limit: number = KNOWLEDGE_LIST_DEFAULT_COUNT;
    // 触发精度四参：可选形态（undefined = 未传，update 保留原值）
    let matchCase: boolean | undefined = undefined;
    let matchWhole: boolean | undefined = undefined;
    let priority: number | undefined = undefined;
    let scanDepth: number | undefined = undefined;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      action = readStrArg(parsed, 'action');
      book = readStrArg(parsed, 'book');
      title = readStrArg(parsed, 'title');
      keywords = readStrArg(parsed, 'keywords');
      content = readStrArg(parsed, 'content');
      newTitle = readStrArg(parsed, 'new_title');
      fileName = readStrArg(parsed, 'file');
      // list 分页两参（其余动作不消费；区间夹取在回执层）
      offset = readIntArg(parsed, 'offset', 1);
      limit = readIntArg(parsed, 'limit', KNOWLEDGE_LIST_DEFAULT_COUNT);
      matchCase = readOptBoolArg(parsed, 'matchCase');
      matchWhole = readOptBoolArg(parsed, 'matchWhole');
      priority = readOptIntArg(parsed, 'priority');
      scanDepth = readOptIntArg(parsed, 'scanDepth');
    } catch (e) {
      // 请求不合法族 = error 形态
      return rejectInvalidArgs(
        '参数解析失败，需要 action 参数（list / get / read_file / create_book / create / update / delete）。');
    }
    if (action !== 'list' && action !== 'get' && action !== 'read_file' &&
      action !== 'create_book' &&
      action !== 'create' && action !== 'update' && action !== 'delete') {
      return rejectInvalidArgs(
        'action 必须是 list、get、read_file、create_book、create、update 或 delete。');
    }
    // 助手上下文守卫（P0-1）：只做存在性检查、**不做权限判定**（写动作定位范围 = 全部书，
    // 见头注释「闸与建议之别」）；助手 id 经执行上下文携带
    const assistantId: string = ctx.knowledgeAssistantId;
    if (assistantId === '') {
      return JSON.stringify({ error: '未取到当前助手上下文，无法管理知识库' });
    }
    try {
      return await this.dispatch(action, assistantId, book, title, keywords, content, newTitle,
        fileName, offset, limit, matchCase, matchWhole, priority, scanDepth);
    } catch (e) {
      // catch 异常 = error 形态（原纯文本会被 detectErrorResult 判成成功态——卡面与事实链均失实）
      hilog.warn(DOMAIN, TAG, '知识库管理失败：%{public}s', toolErrorText(e));
      return JSON.stringify({ error: '知识库操作失败：' + toolErrorText(e) });
    }
  }

  // 七动作分派：list（两形态）/ create_book → 其余动作共用「先定位书、再定位条目」两段
  private async dispatch(action: string, assistantId: string, book: string, title: string,
    keywords: string, content: string, newTitle: string, fileName: string, offset: number,
    limit: number, matchCase: boolean | undefined, matchWhole: boolean | undefined,
    priority: number | undefined, scanDepth: number | undefined): Promise<string> {
    const books: KnowledgeBookRow[] = await queryBooks();
    if (action === 'list' && book === '') {
      // 全书清单（定位范围同写动作 = 全部书）
      const counts: Map<string, number> =
        await countEntriesOfBooks(books.map((row: KnowledgeBookRow): string => row.id));
      return composeKnowledgeManageListReply('', toBookItems(books), counts, [], offset, limit);
    }
    if (action === 'create_book') {
      if (book === '') {
        return rejectInvalidArgs('请提供 book 参数（新知识库名称）。');
      }
      // 书名长度与 UI 同档（同用 KNOWLEDGE_TITLE_MAX 单源）。不判会造出 UI 造不出的超限数据，
      // 且超长书名会顶破工具结果管线 8192 预算、破坏「单条正文恒完整送达」不变量
      if (book.length > KNOWLEDGE_TITLE_MAX) {
        return rejectInvalidArgs(
          '知识库名称超过 ' + KNOWLEDGE_TITLE_MAX + ' 字，本次未创建。请精简后重试。');
      }
      // 判定单源 = knowledgeBookNameTaken（库页新建/重命名同用）——免两处各写一套比较逻辑
      if (knowledgeBookNameTaken(toBookItems(books), book, '')) {
        return '已有同名知识库「' + book + '」，本次未创建。现有知识库：\n' + bookNameLines(books) +
          '\n请换一个名称后再试。';
      }
      if (books.length >= KNOWLEDGE_BOOK_MAX) {
        // 容量拦截 = 出错态（决明拍板：库满/上限一族一律出错——写入没落成，卡片该警示；
        // 与记忆/技能库满同态）
        return rejectInvalidArgs('知识库总数已达上限 ' + KNOWLEDGE_BOOK_MAX +
          ' 个，本次未创建。可在设置的知识库页删除不再使用的库后重试。');
      }
      const created: KnowledgeBookRow = await insertBook(book);
      broadcastKnowledgeList();
      // 写后重取（并发建两库时写前计数会双双少报）
      const total: number = await countBooks();
      return composeKnowledgeManageCreateReply(created.name, total);
    }
    if (book === '') {
      // 缺必填 book（create/update/delete/get/read_file 共用引导）——请求不合法族。（list 无
      // book 走上方全书清单合法形态、不经此处——原注释曾把 list 误列入此并误导真机测试，勿回写）
      return rejectInvalidArgs(await this.bookMissingReply(assistantId));
    }
    const hit: KnowledgeBookRow[] = matchBooks(books, book);
    if (hit.length === 0) {
      const tail: string = books.length > 0 ? '现有知识库：\n' + bookNameLines(books) :
        '当前还没有知识库，可用 action 为 create_book 新建一个。';
      return '没有名为「' + book + '」的知识库，本次未执行。' + tail;
    }
    if (hit.length > 1) {
      // 存量重名书（UI 建库不判重名，历史数据可能有）：工具侧只按书名定位，无法区分——如实拒
      return '有 ' + hit.length + ' 个知识库都叫「' + book + '」，无法确定改动哪一个，本次未执行。' +
        '请在设置的知识库页给其中一个改名后重试。';
    }
    const target: KnowledgeBookRow = hit[0];
    if (action === 'list') {
      const rows: KnowledgeEntryRow[] = await queryEntries(target.id);
      return composeKnowledgeManageListReply(target.name, [], new Map<string, number>(),
        toEntryItems(rows), offset, limit);
    }
    if (action === 'create') {
      return this.createEntryFlow(target, title, keywords, content, matchCase, matchWhole,
        priority, scanDepth);
    }
    // update / delete：条目定位（标题 trim 逐字；该书内唯一是常态，存量重名则拒歧义）
    if (title === '') {
      return rejectInvalidArgs('请提供 title 参数（条目名称），须与 list 返回的标题逐字一致。');
    }
    const entries: KnowledgeEntryRow[] = await queryEntries(target.id);
    const matches: KnowledgeEntryRow[] = entries.filter((row: KnowledgeEntryRow): boolean =>
      row.title.trim() === title);
    if (matches.length === 0) {
      const tail: string = entries.length > 0 ?
        '该书现有标题：\n' + entries.map((row: KnowledgeEntryRow): string =>
          '【' + row.title + '】').join('\n') : '该书暂无条目。';
      return '知识库「' + target.name + '」里没有名为「' + title + '」的条目，本次未执行。' + tail;
    }
    if (matches.length > 1) {
      return '知识库「' + target.name + '」里有 ' + matches.length + ' 条都叫「' + title +
        '」，无法确定改动哪一条，本次未执行。请在设置的知识库页给其中一条改名后重试。';
    }
    const entry: KnowledgeEntryRow = matches[0];
    if (action === 'get') {
      // 读回单条正文：作用域同写口 = 全部书（见头注释「读写分界」）；定位段与 update/delete
      // 复用。附件件名清单一并带上（模型据此发 read_file）——零附件则 fileNames 为空、回执逐
      // 字节同无附件版（不变量，断言守）
      const fileRows: KnowledgeFileRow[] = await queryEntryFiles(entry.id);
      return composeKnowledgeManageGetReply(target.name, entry.title, entry.keywords,
        entry.content, fileRows.map((row: KnowledgeFileRow): string => row.name));
    }
    if (action === 'read_file') {
      // 读回附件原文：作用域同 get = 全部书；定位 = 先条目（复用上方拒歧义路径）再件名——件名
      // 四态（零附件 / 缺 file / 同名多件 / 查无此件）都如实回执不猜（P0-1）。★ 同名多件不是
      // 理论情形：备份恢复链按 id 原样插回不查件名唯一（见 ExportImport 导入循环），「删除 →
      // 同名重建 → 恢复」即造出同条目两件同名
      const rows: KnowledgeFileRow[] = await queryEntryFiles(entry.id);
      const names: string[] = rows.map((row: KnowledgeFileRow): string => row.name);
      if (rows.length === 0) {
        return '知识库「' + target.name + '」的条目「' + entry.title +
          '」没有附件文件，本次未执行。';
      }
      const listTail: string = '该条目现有文件：\n' +
        names.map((item: string): string => '【' + item + '】').join('\n');
      if (fileName === '') {
        return rejectInvalidArgs('请提供 file 参数（文件名，逐字取自 get 回执的文件行）。' +
          listTail);
      }
      const located: KnowledgeFileLocateOutcome = locateKnowledgeFileByName(names, fileName);
      if (located.state === 'multi') {
        return '知识库「' + target.name + '」的条目「' + entry.title + '」里有 ' +
          located.hits.length.toString() + ' 份都叫「' + fileName +
          '」，无法确定读哪一份，本次未执行。\n' + located.hits.join('\n');
      }
      if (located.state === 'none') {
        return '知识库「' + target.name + '」的条目「' + entry.title + '」里没有名为「' +
          fileName + '」的文件，本次未执行。' + listTail;
      }
      return composeKnowledgeManageReadFileReply(target.name, entry.title, rows[located.index].name,
        rows[located.index].content);
    }
    if (action === 'delete') {
      await deleteEntry(entry.id);
      broadcastKnowledgeList();
      // 写后重取（并发删两条时写前计数会双双少报）
      const remain: number = await countEntries(target.id);
      return composeKnowledgeManageDeleteReply(target.name, entry.title, remain);
    }
    return this.updateEntryFlow(target, entries, entry, title, keywords, content, newTitle,
      matchCase, matchWhole, priority, scanDepth);
  }

  // 「book 缺席」引导：建议 = 该助手已启用的知识库（只是建议不是闸；空则建议先建库）
  private async bookMissingReply(assistantId: string): Promise<string> {
    const row: AssistantRow | null = await queryAssistant(assistantId);
    const enabledIds: string[] = parseEnabledKnowledgeIds(row !== null ? row.knowledge : '');
    const books: KnowledgeBookRow[] = await queryBooks();
    const names: string[] = [];
    for (const item of books) {
      if (enabledIds.includes(item.id)) {
        names.push('【' + item.name + '】');
      }
    }
    if (names.length === 0) {
      return '请提供 book 参数（知识库名称）。当前助手未启用任何知识库，' +
        '可先用 action 为 create_book 新建一个。';
    }
    return '请提供 book 参数（知识库名称）。当前助手已启用的知识库：' + names.join('、') + '。';
  }

  // create 分支：字段校验 → 条目数上限 → 重名判定 → 落库（恒 source='assistant'）→ 广播 →
  // 回执。★ 方法名带 Flow 后缀——本文件 import 了 KnowledgeDb 的同名原语，**方法与原语同名会被
  // 类作用域遮蔽**（成员优先），调用即自递归；ToolSkill 的 *Flow 命名同款
  private async createEntryFlow(target: KnowledgeBookRow, title: string, keywords: string,
    content: string, matchCase: boolean | undefined, matchWhole: boolean | undefined,
    priority: number | undefined, scanDepth: number | undefined): Promise<string> {
    if (title === '') {
      return rejectInvalidArgs('请提供 title 参数（条目名称）。');
    }
    const lengthError: string = checkFieldLengths(title, keywords, content);
    if (lengthError !== '') {
      return rejectInvalidArgs(lengthError);
    }
    const count: number = await countEntries(target.id);
    if (count >= KNOWLEDGE_ENTRY_MAX) {
      // 容量拦截 = 出错态（同上）
      return rejectInvalidArgs('知识库「' + target.name + '」的条目已达上限 ' +
        KNOWLEDGE_ENTRY_MAX + ' 条，本次未写入。请先删除不再使用的条目。');
    }
    const entries: KnowledgeEntryRow[] = await queryEntries(target.id);
    if (knowledgeTitleTaken(toEntryItems(entries), title, '')) {
      return composeKnowledgeTitleTakenReply(target.name, title,
        entries.map((row: KnowledgeEntryRow): string => row.title));
    }
    // 触发精度四键：未传 = undefined = insertEntry 落列默认；传入经 clamp 归一（宽容不报错）
    const input: KnowledgeEntryInput = { title: title, keywords: keywords, content: content,
      matchCase: matchCase !== undefined ? (matchCase ? 1 : 0) : undefined,
      matchWhole: matchWhole !== undefined ? (matchWhole ? 1 : 0) : undefined,
      priority: priority !== undefined ? clampKnowledgePriority(priority) : undefined,
      scanDepth: scanDepth !== undefined ? clampKnowledgeScan(scanDepth) : undefined };
    await insertEntry(target.id, input, 'assistant');
    broadcastKnowledgeList();
    // 写后重取（禁写前 count + 1——并发下会少报）
    const total: number = await countEntries(target.id);
    return composeKnowledgeManageCreateEntryReply(target.name, title, total);
  }

  // update 分支：字段合流（未传/空串保持原值——照 manage_skills 明文；触发精度四键同）→ 全等
  // 则如实回执不写库 → 改名重名判定（排除自身）→ 上限校验 → 落库（**不碰 source**）→ 广播 → 回执
  private async updateEntryFlow(target: KnowledgeBookRow, entries: KnowledgeEntryRow[],
    entry: KnowledgeEntryRow, title: string, keywords: string, content: string,
    newTitle: string, matchCase: boolean | undefined, matchWhole: boolean | undefined,
    priority: number | undefined, scanDepth: number | undefined): Promise<string> {
    if (newTitle === '' && keywords === '' && content === '' && matchCase === undefined &&
      matchWhole === undefined && priority === undefined && scanDepth === undefined) {
      return rejectInvalidArgs('请提供要修改的内容。new_title、keywords、content 至少给一项，' +
        '未传或传空串的字段保持原值。');
    }
    const finalTitle: string = newTitle !== '' ? newTitle : entry.title;
    const finalKeywords: string = keywords !== '' ? keywords : entry.keywords;
    const finalContent: string = content !== '' ? content : entry.content;
    // 触发精度合流：未传保持原值；传入布尔转 0/1、数字经 clamp（与 create 链同口径）
    const finalMatchCase: number = matchCase !== undefined ? (matchCase ? 1 : 0) : entry.matchCase;
    const finalMatchWhole: number = matchWhole !== undefined ? (matchWhole ? 1 : 0) : entry.matchWhole;
    const finalPriority: number = priority !== undefined ?
      clampKnowledgePriority(priority) : entry.priority;
    const finalScanDepth: number = scanDepth !== undefined ?
      clampKnowledgeScan(scanDepth) : entry.scanDepth;
    // changed 条件处同趟收集旧新值行——喂回执尾行（appendReceiptDiffTail 组装，值经
    // clipReceiptDiffValue 单源截断），changed 仍喂原句；旧值空该行只留字段名
    const changed: string[] = [];
    const oldParts: string[] = [];
    const newParts: string[] = [];
    const pushDiff = (label: string, oldText: string, newText: string): void => {
      changed.push(label);
      oldParts.push(oldText === '' ? label : label + ' ' + oldText);
      newParts.push(newText === '' ? label : label + ' ' + newText);
    };
    const onOffText = (v: number): string => v === 1 ? '开' : '关';
    if (finalTitle !== entry.title) {
      pushDiff('名称', entry.title, finalTitle);
    }
    if (finalKeywords !== entry.keywords) {
      pushDiff('关键词', entry.keywords, finalKeywords);
    }
    if (finalContent !== entry.content) {
      pushDiff('正文', entry.content, finalContent);
    }
    // 触发精度四键：只在值变化时列一行
    if (finalMatchCase !== entry.matchCase) {
      pushDiff('区分大小写', onOffText(entry.matchCase), onOffText(finalMatchCase));
    }
    if (finalMatchWhole !== entry.matchWhole) {
      pushDiff('整词匹配', onOffText(entry.matchWhole), onOffText(finalMatchWhole));
    }
    if (finalPriority !== entry.priority) {
      pushDiff('优先级', String(entry.priority), String(finalPriority));
    }
    if (finalScanDepth !== entry.scanDepth) {
      pushDiff('检查最近消息', String(entry.scanDepth) + ' 条', String(finalScanDepth) + ' 条');
    }
    if (changed.length === 0) {
      // 传了字段但与现值全等——如实回执不写库（防假更新回执，ManageSkillsExecutor 先例）
      return '传入内容与「' + entry.title + '」当前内容相同，未做修改。';
    }
    const lengthError: string = checkFieldLengths(finalTitle, finalKeywords, finalContent);
    if (lengthError !== '') {
      // 请求不合法族 = error 形态（create 链同族已包壳，同一超限两链不得异态）
      return rejectInvalidArgs(lengthError);
    }
    if (finalTitle !== entry.title &&
      knowledgeTitleTaken(toEntryItems(entries), finalTitle, entry.id)) {
      return composeKnowledgeTitleTakenReply(target.name, finalTitle,
        entries.filter((row: KnowledgeEntryRow): boolean => row.id !== entry.id)
          .map((row: KnowledgeEntryRow): string => row.title));
    }
    const input: KnowledgeEntryInput = {
      title: finalTitle, keywords: finalKeywords, content: finalContent,
      matchCase: finalMatchCase, matchWhole: finalMatchWhole,
      priority: finalPriority, scanDepth: finalScanDepth
    };
    await updateEntry(entry.id, input);
    broadcastKnowledgeList();
    return appendReceiptDiffTail(
      composeKnowledgeManageUpdateReply(target.name, entry.title, finalTitle, changed),
      oldParts.join('\n'), newParts.join('\n'));
  }
}
