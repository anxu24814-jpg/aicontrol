// 知识库工具域（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 §4.4；★ 同日
// 知识库第二笔下本加 manage_knowledge——任务书-知识库写入口与上限放宽-20260921；用户可见名
// 「知识库」，世界书 / World Book / Lorebook 只活在文档与代码注释里）：两件——search_knowledge
// 按关键词检索知识库条目（action = search / list 两动作，**只读**，作用域 = 本助手启用集）+
// manage_knowledge 管理知识库与条目（action = list / get / create_book / create / update /
// delete / read_file 七动作，作用域 = **全部书**；其中 create/update/delete 三写 + create_book
// 建库是全工程**唯一写口**，get 为读回单条正文的读动作——2026-09-22 补，read_file 为读回某
// 条目下一份附件件原文的读动作——2026-09-23 知识库文件笔补，附件写口全在 UI）。
// 同文件两工具先例 = ToolSkill.ets（use_skill + manage_skills 同居）。
//
// · 域职责：工具 desc 与 schema 单源 + 执行器（参数解析 → 助手上下文 → 取库取条目 → 纯函数
//   拼装）。检索/判定/回执纯函数在 KnowledgeText.ets（零 import 域，断言脚本复制直跑），行读
//   写在 KnowledgeDb.ets，本件只做编排；注册在 ToolTypes（聚合根，本文件不反向引它——模块环
//   红线，见 ToolContracts.ets 头注释）。
// · ★ 读写分界（2026-09-21 第二笔下本修订，原「只读语义」条已被本笔改写；2026-09-22 补 get
//   动作后，管理件从此**含一个读动作**，本段两处措辞随之修订；2026-09-23 文件笔再补第二个读
//   动作 read_file，本段所列动作名与数量随之更新）：
//   **检索件仍只读**（动作白名单恰 search / list；2026-09-22 O1 笔只给它加了 list 分页两参，
//   读写语义未变），**管理件是唯一写口**
//   （create/update/delete 三写 + create_book 建库；书级不开放改名与删库），另含两个读动作
//   **get**（读回单条正文）与 **read_file**（读回某条目下的一份附件件原文，按件名定位）——
//   作用域同写口 = **全部书**、不受启用集限制（库没被启用时检索件
//   看不见它，但「指名读那一条」没有理由被启用集挡住；这也正是「助手写完自己读不回」的出口）。
//   「用户手写」不再是
//   本功能的定义边界，边界改按两条并写（决明 2026-09-21 拍板，原「用户手写」口径随之作废）：
//   ①**按来源**——知识库 = 用户授权的写入（人写，或助手按用户指令代言整理）；记忆 = 模型自主
//     沉淀。
//   ②**按内容**——知识库 = 与用户本人无关的领域知识；记忆 = 关于用户本人的、随时间变化的事实。
//   两条同时落进两件 desc 的划界句（内容这条是主句）。「工具操作面 ⊆ UI 操作面」红线仍成立：
//   工具七个动作在 UI 都有对应入口（建库 / 新增 / 编辑 / 删除 / 列表 / 读回正文 / 读回附件），
//   且工具侧**更窄**（UI 有书级改名与删库、附件的新建与修改与删除，工具没有；文件写口全在 UI）。
// · ★ 附件（2026-09-23 知识库文件笔）：附件件挂在**条目**下（knowledge_files，件名条目内唯一），
//   检索面**完全不涉文件**（不进索引——检索件回执与打分函数零改动，是笔内的边界而非遗漏）；
//   取用路径 = get 回执列件名 → 模型按名发 read_file。零附件时 get 回执逐字节同升级前
//  （composeKnowledgeManageGetReply 的 fileNames 恒空 ⇒ 零输出）。
// · ★ 回执条数恒取**写后重取**（三处：create / delete / create_book；2026-09-22 修并发竞态）：
//   一轮内多个非交互工具走 Promise.all 并发（ChatToolRoundCtrl.runToolCallsParallel），而原先
//   三处都拿**写前**计数加一（count + 1 / entries.length - 1 / books.length + 1）⇒ 两条回执
//   读到的是同一份先前态、双双少报（决明实测：并行写两条，两条都报「现共 1 条」）。重取到的
//   数 = 本条写入完成那一刻的库态，恒如实；回归条 = assert-knowledge-domain 162 组。
// · ★ 执行器无上下文（读不到当前助手行）= 进程级 AppStorage 中转键机制：键 = 下方
//   KNOWLEDGE_EXEC_ASSISTANT_KEY，写点 = ChatSendCtrl 发送链（初发与重试轮两处，与
//   MEMORY_EXEC_ASSISTANT_KEY 同位同形），读点 = 本件两执行器。值 = 该轮执行者助手 id；'' =
//   无助手上下文（异常路径，按 P0-1 明确回错不静默）。运行时态不持久化（同
//   CHAT_ACTIVE_CONV_KEY 先例：发送点解析，同一会话天然对位）。
// · ★ 隐私边界（判定见任务书 §2 决策 9，此处落成注释防后人「顺手」改）：知识库是**用户
//   授权的知识**，不是会话内容——与 search_chats / get_chats 的隐私语义不同族。故两件工具
//   **都不进 ToolChatSearch.isCrossSessionTool 名单**，隐私会话照常声明，与 search_memory 同判
//   （记忆工具在隐私会话同样声明）。★ 反向也成立：**禁**把本域工具名加进 isCrossSessionTool
//   ——那会让用户在隐私会话里查不了自己写的词条本，属无依据的功能收窄。
// · ★ 声明层（ChatContextUsage.collectTools）零改动：本域两件都是**常规工具**（走
//   assistants.tools 通道 / 助手工具页「知识库」卡开关），不入 MODE_DRIVEN_TOOLS（模式驱动件
//   不走 assistants.tools 也不进工具页），不入 CONSOLE_EXCLUSIVE_TOOLS（普通助手可开）。
//   助手未启用任何知识库时两件**仍可被声明**（声明层不做知识库态判定——那要动注入链，
//   属首笔红线），由执行器回引导串把「没启用」这件事讲清楚。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToolExecutor } from './ToolContracts';
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
  composeKnowledgeSearchResult, composeKnowledgeTitleTakenReply, KNOWLEDGE_CONTENT_MAX,
  KNOWLEDGE_KEYWORDS_MAX, KNOWLEDGE_LIST_DEFAULT_COUNT, KNOWLEDGE_LIST_MAX_COUNT,
  KNOWLEDGE_TITLE_MAX, knowledgeBookNameTaken, knowledgeTitleTaken, KnowledgeEntryItem,
  KnowledgeFileLocateOutcome, locateKnowledgeFileByName, parseEnabledKnowledgeIds,
  selectKnowledgeHits } from '../KnowledgeText';

const DOMAIN: number = 0x71C4;
const TAG: string = 'ToolKnowledge';

// 执行者助手中转键（机制与写点见头注释；'' = 未取到上下文）
export const KNOWLEDGE_EXEC_ASSISTANT_KEY: string = 'knowledgeExecAssistantId';

// 入参 schema（静态串；两动作语义写在 description 里，模型据此选路）。★ 2026-09-22 O1 笔加
// list 分页两参（值随常量拼接，禁写死——与下方管理件同口径）
export const SEARCH_KNOWLEDGE_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["search","list"],' +
  '"description":"search=按关键词检索知识条目，list=查看知识库条目清单"},' +
  '"query":{"type":"string","description":"search 专用，检索关键词，多个用空格分隔"},' +
  '"offset":{"type":"integer","description":"list 专用，从第几条开始（默认 1）"},' +
  '"limit":{"type":"integer","description":"list 专用，本页条数（默认 ' +
  KNOWLEDGE_LIST_DEFAULT_COUNT + '，最大 ' + KNOWLEDGE_LIST_MAX_COUNT + '）"}},' +
  '"required":["action"]}';

// 引导串（执行器的三条「问法不对/前置未备」路径——都是让模型下一步能走对，不是错误报告）
const KNOWLEDGE_NO_BOOK_TIP: string =
  '当前助手未启用任何知识库。请在助手编辑页的知识库里启用后再试。';
const KNOWLEDGE_NEED_QUERY_TIP: string =
  '请提供要检索的关键词，或改用 action 为 list 查看条目清单。';
const KNOWLEDGE_BAD_ACTION_TIP: string = 'action 必须是 search 或 list。';

// desc 单源（注册在 ToolTypes 消费；三段式 = 调用时机 / 返回形态 / 划界）。
// ★ 划界句**不点未声明工具的具名**：inject 模式下 search_memory 可能未声明，点名会诱导模型
// 调用未声明工具白耗一轮（既有红线，见 ToolTypes 的 search_chats 注册块注释）。
// ★ 全文零数字字面量（无嵌时变值——RikkaHub #1356 缓存教训）
export function buildSearchKnowledgeDesc(): string {
  return '检索用户手写的知识库条目。用户的问题涉及某个领域的专门知识，' +
    '例如术语、设定、规范、人物或事物背景，而对话上下文里没有这些信息时调用。' +
    '返回命中的条目原文，附所属知识库名。action 取 list 可先查看有哪些条目，' +
    '该清单分页，每页默认 ' + KNOWLEDGE_LIST_DEFAULT_COUNT + ' 条，更多用 offset 继续看。' +
    '动作 search 需要 query。长期稳定的用户信息，例如偏好、背景、身份，' +
    '应检索记忆库，技能是模型加载的做法说明，两者与本工具不同族。';
}

// 知识库检索执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject，错误走 JSON 错误信息
// ——SearchChatsExecutor / GetChatsExecutor 同款）。流程见 execute 内注释
export class SearchKnowledgeExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
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
      // 2026-09-22 O1 笔：list 分页两参（search 动作不消费；区间夹取在回执层）
      offset = readIntArg(parsed, 'offset', 1);
      limit = readIntArg(parsed, 'limit', KNOWLEDGE_LIST_DEFAULT_COUNT);
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    // 纯参数错先判（不读库；两动作白名单）
    if (action !== 'search' && action !== 'list') {
      return Promise.resolve(KNOWLEDGE_BAD_ACTION_TIP);
    }
    const assistantId: string = AppStorage.get<string>(KNOWLEDGE_EXEC_ASSISTANT_KEY) ?? '';
    if (assistantId === '') {
      return Promise.resolve(JSON.stringify({ error: '未取到当前助手上下文，无法读取知识库' }));
    }
    const fail = (e: Object): string => {
      hilog.warn(DOMAIN, TAG, '知识库读取失败：%{public}s', (e as Error).message);
      return JSON.stringify({ error: '知识库读取失败：' + (e as Error).message });
    };
    return queryAssistant(assistantId)
      .then((row: AssistantRow | null): Promise<string> => {
        // 助手行查不到（已删/坏 id）按空集处理：与「未启用」同一条引导串——对模型而言
        // 两者都是「现在读不到知识库」，区分它们没有可执行的下一步
        const enabledIds: string[] = parseEnabledKnowledgeIds(row !== null ? row.knowledge : '');
        if (enabledIds.length === 0) {
          return Promise.resolve(KNOWLEDGE_NO_BOOK_TIP);
        }
        // 一次取全部已启用库的条目（**禁逐库查**——P1-2 轻量检测纪律）
        return queryEntriesByBookIds(enabledIds)
          .then((pool: KnowledgeEntryRow[]): Promise<string> =>
            queryBooks().then((books: KnowledgeBookRow[]): string => {
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
                return KNOWLEDGE_NEED_QUERY_TIP;
              }
              const names: Map<string, string> = new Map<string, string>();
              for (const book of enabledBooks) {
                names.set(book.id, book.name);
              }
              // limit 传 0 = 把全部候选交给拼装层，由它按双封顶截断并据实加尾行
              return composeKnowledgeSearchResult(selectKnowledgeHits(entryItems, query, 0), names);
            }))
          .catch(fail);
      })
      .catch(fail);
  }
}

// ── 管理知识库工具（2026-09-21 知识库第二笔下本，任务书-知识库写入口与上限放宽-20260921
//    §4.4——内置第 26 件 manage_knowledge 的实现；第 25 件 search_knowledge 在上）──
// 用户说「把这段整理成知识条目 / 读一下那条 / 改一下那条 / 删掉那条」时，模型经本件读写知识库
// （对标 manage_memory / manage_skills 同一形制）。七动作 = list / get / read_file / create_book /
// create / update / delete——**书级只开放建库**（改名与删库留给设置页：删除不可逆且 UI 有确认链，
// desc 里给指路）；get 是 2026-09-22 补的读回动作，read_file 是 2026-09-23 知识库文件笔补的读回
// 附件动作（两者均只读，作用域同写口）。
// · 定位范围 = **全部书**（不取启用集）——★ 与 search_knowledge 的「启用集」作用域**刻意不同**：
//   create_book 新建的书默认不被任何助手启用（决策 3 的必然后果），若写动作也卡启用集，助手
//   刚建的书就写不进去。**「闸」与「建议」之别**（防后人「顺手」收紧成与检索同域，逐条照此）：
//   ①「闸」= 写动作**不受**启用集限制——用户指明了书名就用该书，不论本助手是否启用；
//   ②「建议」= 书名缺席时（book 参数没给），回执把该助手**已启用**的库列为建议落点
//      （parseEnabledKnowledgeIds 读 assistants.knowledge），启用集为空则建议先 create_book。
//   assistantId 仍取（P0-1 上下文守卫），但**不拿它做写权限判定**。
// · 条目字段语义（照 manage_skills 明文）：update **只改传入的字段**，未传或传空串的字段保持
//   原值——实现 = 先取现行为底、把非空字段覆盖上去、合成完整 KnowledgeEntryInput 再交
//   updateEntry（该原语是整体替换语义，字段全写，**必须回填未传字段**否则会把正文清空）。
// · 重名拦截（决策 8）：**条目**判定单源 = KnowledgeText.knowledgeTitleTaken（编辑页保存前
//   同用），create 与 update 改名两路都拦，命中回执点名该书现有标题；**书名**判定单源 =
//   KnowledgeText.knowledgeBookNameTaken（2026-09-22 八百七十一节起库页新建/重命名两路同用，
//   本件 create_book 亦改指它）；**不加 DB 唯一索引**（存量重名会让迁移失败，应用层两路已覆盖
//   全部写入口）。
// · 源标记（决策 7）：本件写入恒 source='assistant'（编辑页恒 'user'）；update 不改 source。
// · 恒 resolve 不 reject（ToolMemoryManage / ManageSkillsExecutor 同口径）：全部错误态走中文
//   文本回执，兜底由 executeToolCall 包装 error JSON 不炸轮次；三写点后 broadcastKnowledgeList
//   （前台库页/书页即时刷新）。
// · ★ 存量重名的两条歧义路径（2026-09-21 本笔加，决策 8 只禁新写入的重名、不清洗存量）：
//   库内条目重名与跨库书名重名在 UI 侧都可能存在（旧数据），工具侧一律**拒歧义并如实回执**
//   （不猜、不静默取第一条——P0-1 不静默），指引用户到设置页逐行处理。

// 入参 schema（静态串；七动作语义写在 description 里，模型据此选路；上限数字随常量单源动态拼，
// 照 MANAGE_MEMORY_SCHEMA / MANAGE_SKILLS_SCHEMA 先例——改常量 schema 自随）
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
  '"offset":{"type":"integer","description":"list 专用，从第几条开始（默认 1）"},' +
  '"limit":{"type":"integer","description":"list 专用，本页条数（默认 ' +
  KNOWLEDGE_LIST_DEFAULT_COUNT + '，最大 ' + KNOWLEDGE_LIST_MAX_COUNT + '）"}},' +
  '"required":["action"]}';

// desc 单源（注册在 ToolTypes 消费；三段式 = 调用时机 / 逐动作用法 / 划界与限额）。
// ★ 划界句**只点域名不点工具名**：inject 模式或助手未启用知识库时 search_memory 可能未声明，
// 点名会诱导模型调用未声明工具白耗一轮（既有红线，见 ToolTypes 的 search_chats 注册块注释）。
// ★ 上限数字随常量拼接、禁写死（RikkaHub #1356 缓存教训：不嵌时变值，常量上限无碍）
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
    '知识库本身的改名与删除不在本工具范围，需要时到 设置 → 知识库 操作。' +
    '仅在用户明确要求时调用，执行后向用户复述改了什么。';
}

// 取字符串参数（非字符串/缺省一律归 '' 并 trim）。★ 两件各留一份取值块是刻意的（域内自持，
// 不做跨件合并——KnowledgeText 头注释同条纪律）。★ 2026-09-22 O1 笔起**检索件取值块不再
// 冻结**：该笔为 list 分页给 search_knowledge 也加了 offset/limit 两参（原「本笔红线 = 不动
// search_knowledge 行为面」是 2026-09-21 下本的自限范围，随该笔交付结束自然失效）
function readStrArg(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw.trim() : '';
}

// 取整数参数（非整数/缺省 → fallback；脏值不报错，由回执层夹到合法范围——照 manage_skills /
// manage_memory 两先例的「list 的 offset/limit 脏值归默认不报错」口径，模型少一轮纠错）
function readIntArg(parsed: Record<string, Object>, key: string, fallback: number): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' && Number.isInteger(raw) ? raw : fallback;
}

// 书名精确匹配命中集（trim 后逐字——模型按 list 回执里的书名引用）；0 命中 / 多命中的回执
// 由调用方按 P0-1 各自如实给出（多命中 = 存量重名书，工具侧无法区分，禁猜）
function matchBooks(books: KnowledgeBookRow[], name: string): KnowledgeBookRow[] {
  return books.filter((row: KnowledgeBookRow): boolean => row.name.trim() === name);
}

// 书清单逐行（回执里的可选书名列表——「没有这本书」与「book 缺席」两条路径共用）
function bookNameLines(books: KnowledgeBookRow[]): string {
  return books.map((row: KnowledgeBookRow): string => '【' + row.name + '】').join('\n');
}

// 条目名 → 三位上限校验（超限回中文回执，未超回 ''）。与编辑页 maxLength 同源常量——工具面
// 不设的话会造出 UI 造不出的超限数据（P0-1：宁可拒绝，不可静默入库）
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

// 知识库管理执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject）
export class ManageKnowledgeExecutor implements ToolExecutor {
  async execute(argsJson: string): Promise<string> {
    let action: string = '';
    let book: string = '';
    let title: string = '';
    let keywords: string = '';
    let content: string = '';
    let newTitle: string = '';
    let fileName: string = '';
    let offset: number = 1;
    let limit: number = KNOWLEDGE_LIST_DEFAULT_COUNT;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      action = readStrArg(parsed, 'action');
      book = readStrArg(parsed, 'book');
      title = readStrArg(parsed, 'title');
      keywords = readStrArg(parsed, 'keywords');
      content = readStrArg(parsed, 'content');
      newTitle = readStrArg(parsed, 'new_title');
      fileName = readStrArg(parsed, 'file');
      // 2026-09-22 O1 笔：list 分页两参（其余动作不消费；区间夹取在回执层）
      offset = readIntArg(parsed, 'offset', 1);
      limit = readIntArg(parsed, 'limit', KNOWLEDGE_LIST_DEFAULT_COUNT);
    } catch (e) {
      return '参数解析失败，需要 action 参数（list / get / read_file / create_book / create / update / delete）。';
    }
    if (action !== 'list' && action !== 'get' && action !== 'read_file' &&
      action !== 'create_book' &&
      action !== 'create' && action !== 'update' && action !== 'delete') {
      return 'action 必须是 list、get、read_file、create_book、create、update 或 delete。';
    }
    // 助手上下文守卫（P0-1）：只做「这一轮有没有助手」的存在性检查，**不做权限判定**
    //（写动作的定位范围是全部书，与执行者的启用集无关——见文件区头注释「闸与建议之别」）
    const assistantId: string = AppStorage.get<string>(KNOWLEDGE_EXEC_ASSISTANT_KEY) ?? '';
    if (assistantId === '') {
      return JSON.stringify({ error: '未取到当前助手上下文，无法管理知识库' });
    }
    try {
      return await this.dispatch(action, assistantId, book, title, keywords, content, newTitle,
        fileName, offset, limit);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '知识库管理失败：%{public}s', (e as Error).message);
      return '知识库操作失败：' + (e as Error).message;
    }
  }

  // 七动作分派：list（两形态）/ create_book → 其余动作共用「先定位书、再定位条目」两段
  private async dispatch(action: string, assistantId: string, book: string, title: string,
    keywords: string, content: string, newTitle: string, fileName: string, offset: number,
    limit: number): Promise<string> {
    const books: KnowledgeBookRow[] = await queryBooks();
    if (action === 'list' && book === '') {
      // 全书清单（不限启用集——list 的定位范围同写动作，都是全部书）
      const counts: Map<string, number> =
        await countEntriesOfBooks(books.map((row: KnowledgeBookRow): string => row.id));
      return composeKnowledgeManageListReply('', toBookItems(books), counts, [], offset, limit);
    }
    if (action === 'create_book') {
      if (book === '') {
        return '请提供 book 参数（新知识库名称）。';
      }
      // 书名长度与 UI 同档（库页命名对话框 maxLength 同用 KNOWLEDGE_TITLE_MAX——单一来源，
      // 两处随常量同动）。★ 2026-09-22 自检轮补：原缺此判 ⇒ 工具面能造出 UI 造不出的超限
      // 数据（与下方 checkFieldLengths 同一纪律），且书名进检索结果头行与各回执清单，超长会
      // 顶破工具结果管线 8192 预算、连带破坏「单条正文恒完整送达」那条不变量
      if (book.length > KNOWLEDGE_TITLE_MAX) {
        return '知识库名称超过 ' + KNOWLEDGE_TITLE_MAX + ' 字，本次未创建。请精简后重试。';
      }
      // 判定单源 = KnowledgeText.knowledgeBookNameTaken（2026-09-22 八百七十一节起库页新建与
      // 重命名两路同用）——原为本地 matchBooks 判空，改指同一函数免「两处各写一套比较逻辑」
      if (knowledgeBookNameTaken(toBookItems(books), book, '')) {
        return '已有同名知识库「' + book + '」，本次未创建。现有知识库：\n' + bookNameLines(books) +
          '\n请换一个名称后再试。';
      }
      if (books.length >= KNOWLEDGE_BOOK_MAX) {
        return '知识库总数已达上限 ' + KNOWLEDGE_BOOK_MAX +
          ' 个，本次未创建。可在设置的知识库页删除不再使用的库后重试。';
      }
      const created: KnowledgeBookRow = await insertBook(book);
      broadcastKnowledgeList();
      // 写后重取（同上——并发建两库时写前的 books.length + 1 会双双少报）
      const total: number = await countBooks();
      return composeKnowledgeManageCreateReply(created.name, total);
    }
    if (book === '') {
      return this.bookMissingReply(assistantId);
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
      return this.createEntryFlow(target, title, keywords, content);
    }
    // update / delete：条目定位（标题 trim 逐字；该书内唯一是常态，存量重名则拒歧义）
    if (title === '') {
      return '请提供 title 参数（条目名称），须与 list 返回的标题逐字一致。';
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
      // 读回单条正文（2026-09-22 补）：作用域同写口 = 全部书，不受启用集限制（见文件头
      // 「读写分界」条）；定位段与 update/delete 完全复用（0 命中/多命中两条拒歧义路径同上）。
      // ★ 2026-09-23 文件笔：附件的件名清单一并带上（模型据此发 read_file）——**零附件则
      // fileNames 为空数组、回执行逐字节同升级前**（不变量，断言守）
      const fileRows: KnowledgeFileRow[] = await queryEntryFiles(entry.id);
      return composeKnowledgeManageGetReply(target.name, entry.title, entry.keywords,
        entry.content, fileRows.map((row: KnowledgeFileRow): string => row.name));
    }
    if (action === 'read_file') {
      // 读回附件件原文（2026-09-23 知识库文件笔）：作用域同 get = 全部书；定位 = 先条目
      //（复用上方 0 命中/多命中两条拒歧义路径）再件名——件名这一级四态：该条目零附件 / 缺
      // file 参数 / 同名多件 / 查无此件，四条都如实回执不猜（P0-1 不静默）。★ 同名多件这一态
      // 不是理论情形：导出备份的恢复链按 id 原样插回已删的旧行、不查件名唯一（见 ExportImport
      // 的导入循环），故「删除 → 同名重建 → 从备份恢复」就能造出同条目两件同名
      const rows: KnowledgeFileRow[] = await queryEntryFiles(entry.id);
      const names: string[] = rows.map((row: KnowledgeFileRow): string => row.name);
      if (rows.length === 0) {
        return '知识库「' + target.name + '」的条目「' + entry.title +
          '」没有附件文件，本次未执行。';
      }
      const listTail: string = '该条目现有文件：\n' +
        names.map((item: string): string => '【' + item + '】').join('\n');
      if (fileName === '') {
        return '请提供 file 参数（文件名，逐字取自 get 回执的文件行）。' + listTail;
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
      // 写后重取（同上——并发删两条时写前的 entries.length - 1 会双双少报）
      const remain: number = await countEntries(target.id);
      return composeKnowledgeManageDeleteReply(target.name, entry.title, remain);
    }
    return this.updateEntryFlow(target, entries, entry, title, keywords, content, newTitle);
  }

  // list/create/update/delete 的「book 缺席」引导（决策 3 的**建议落点**落法：建议 = 该助手
  // 已启用的知识库——只是建议，不是闸；启用集为空则建议先建库）
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

  // create 分支：三字段校验（名称非空 + 三位上限）→ 条目数上限 → 重名判定 → 落库（恒
  // source='assistant'）→ 广播 → 回执。★ 方法名带 Flow 后缀（不是 updateEntry / createEntry）
  // ——本文件 import 了 KnowledgeDb 的同名原语，**方法名与原语同名会被类作用域遮蔽**（成员优先
  // 于外层作用域），调用即自递归；ToolSkill 的 createSkillFlow / updateSkillFlow 同款命名
  private async createEntryFlow(target: KnowledgeBookRow, title: string, keywords: string,
    content: string): Promise<string> {
    if (title === '') {
      return '请提供 title 参数（条目名称）。';
    }
    const lengthError: string = checkFieldLengths(title, keywords, content);
    if (lengthError !== '') {
      return lengthError;
    }
    const count: number = await countEntries(target.id);
    if (count >= KNOWLEDGE_ENTRY_MAX) {
      return '知识库「' + target.name + '」的条目已达上限 ' + KNOWLEDGE_ENTRY_MAX +
        ' 条，本次未写入。请先删除不再使用的条目。';
    }
    const entries: KnowledgeEntryRow[] = await queryEntries(target.id);
    if (knowledgeTitleTaken(toEntryItems(entries), title, '')) {
      return composeKnowledgeTitleTakenReply(target.name, title,
        entries.map((row: KnowledgeEntryRow): string => row.title));
    }
    const input: KnowledgeEntryInput = { title: title, keywords: keywords, content: content };
    await insertEntry(target.id, input, 'assistant');
    broadcastKnowledgeList();
    // 计数取**写后重取**（禁写前的 count + 1——并发下会少报，见文件头「回执条数」条）
    const total: number = await countEntries(target.id);
    return composeKnowledgeManageCreateEntryReply(target.name, title, total);
  }

  // update 分支：字段合流（未传/空串保持原值——照 manage_skills 明文）→ 全等则如实回执不写库
  // → 改名重名判定（排除自身）→ 上限校验 → 落库（**不碰 source**）→ 广播 → 回执
  private async updateEntryFlow(target: KnowledgeBookRow, entries: KnowledgeEntryRow[],
    entry: KnowledgeEntryRow, title: string, keywords: string, content: string,
    newTitle: string): Promise<string> {
    if (newTitle === '' && keywords === '' && content === '') {
      return '请提供要修改的内容。new_title、keywords、content 至少给一项，' +
        '未传或传空串的字段保持原值。';
    }
    const finalTitle: string = newTitle !== '' ? newTitle : entry.title;
    const finalKeywords: string = keywords !== '' ? keywords : entry.keywords;
    const finalContent: string = content !== '' ? content : entry.content;
    const changed: string[] = [];
    if (finalTitle !== entry.title) {
      changed.push('名称');
    }
    if (finalKeywords !== entry.keywords) {
      changed.push('关键词');
    }
    if (finalContent !== entry.content) {
      changed.push('正文');
    }
    if (changed.length === 0) {
      // 传了字段但与现值全等——如实回执不写库（防假更新回执，ManageSkillsExecutor 先例）
      return '传入内容与「' + entry.title + '」当前内容相同，未做修改。';
    }
    const lengthError: string = checkFieldLengths(finalTitle, finalKeywords, finalContent);
    if (lengthError !== '') {
      return lengthError;
    }
    if (finalTitle !== entry.title &&
      knowledgeTitleTaken(toEntryItems(entries), finalTitle, entry.id)) {
      return composeKnowledgeTitleTakenReply(target.name, finalTitle,
        entries.filter((row: KnowledgeEntryRow): boolean => row.id !== entry.id)
          .map((row: KnowledgeEntryRow): string => row.title));
    }
    const input: KnowledgeEntryInput = {
      title: finalTitle, keywords: finalKeywords, content: finalContent
    };
    await updateEntry(entry.id, input);
    broadcastKnowledgeList();
    return composeKnowledgeManageUpdateReply(target.name, entry.title, finalTitle, changed);
  }
}
