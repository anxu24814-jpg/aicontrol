// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// assert-chat-search-domain.mjs — 跨会话读取域断言（2026-09-19 跨会话记忆深化笔立；
// 75 组 + 131 组自 assert-app-domain.mjs 整块迁出——本笔 get_chats 把 app-domain 推过
// 6000 拆分触发线，宪法「脚本例外与拆分触发线」条：按域切 assert-<域>.mjs + 共享帮助
// 模块 assert-lib.mjs，门禁逐件登记，并以「断言总数 = 各件求和」+「搬迁前后 PASS 名全集
// 逐字比对」为行为等价证明。跨会话读取域职责缝一句话：search_chats 检索其他会话消息片段
// 与 get_chats 清单/通读两工具的全部断言面〔纯函数直跑 + 源码形态〕）。
// 域内容 = 75 组（跨会话检索 search_chats，2026-09-13；★ 2026-09-19 深化笔随形改判一处
// ——隐私闸判据换 isCrossSessionTool，细形态负向钉归 131 组）+ 131 组（跨会话记忆深化
// get_chats，2026-09-19 任务书-跨会话记忆深化-20260919：A 清单与定位纯函数直跑 / B offset
// 归一与窗口渲染直跑 / C 源码形态〔四常量 / 三查询 locked 排除与升序窗口 / 注册 / 划界
// 与外泄 / isCrossSessionTool 双件同闸 / 帮助 / seed 零扩〕）。
// ★ 2026-09-20 修复随形（D1-1 / D1-2）：131 组 B 段两处钉改判 + 补三条——①B2 首钉原喂
// DESC 序并期望「内部转正序」，前提与生产输入（SQL 升序）相反：钉全绿而线上序号整体反号
// （[start] 挂窗口最新条），现喂真运行序断言 [1]=最早条；②B1 补「前向分页可达」（offset ∈
// (末页起点, 末条序号] 原样生效）——旧口径夹回 tailStart 使尾行「继续读取」不可跟随（同页
// 死循环）；③B2 补「尾行 offset 可跟随」「头行报实显序号（缩尾/缩首）」两条。
// 剥桩形制（同 assert-app-domain 75 组配套原样）：ToolChatSearch 带 ToolTypes/ChatDb/
// MemoryText import——复制后剥 import 行，再前置零 import 的 MemoryText 源拼接为单文件
// 直跑；MemoryText.ts 各域件独立生成同一 .tmp 文件（幂等，模块缓存同实例）。执行器体内
// AppStorage/ChatDb/hilog 引用与 isCrossSessionTool（函数体引 ToolTypes 常量）不在直跑面。

import { copyFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { check, report } from './assert-lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const tmpDir = path.join(here, '.tmp');
// ★ 2026-09-24 公开仓可验证性笔：本件此前不自建 .tmp，靠同目录其它件先跑出目录——干净检出
// 单独跑即 copyFileSync ENOENT（公开面首跑实测）；与同族件（sse-assert / assert-msg-copy /
// assert-price-template）对齐，自建目录。
mkdirSync(tmpDir, { recursive: true });

// 75 组配套前置：MemoryText 零 import 纯函数层（复制直跑——splitMemoryQuery/
// hitSensitiveContent 被本域纯函数消费）
copyFileSync(path.join(here, '..', '..', 'entry', 'src', 'main', 'ets', 'common', 'MemoryText.ets'),
  path.join(tmpDir, 'MemoryText.ts'));

// 75 组配套：跨会话检索纯函数层 2026-09-13（ToolChatSearch 带 ToolTypes/ChatDb/MemoryText
// import——复制后剥 import 行，再前置零 import 的 MemoryText 源拼接为单文件直跑：其
// splitMemoryQuery/hitSensitiveContent 被本域纯函数消费；ChatMessageHitRow 为纯类型位，
// 类型擦除后无运行时引用；执行器体内 AppStorage/ChatDb/hilog 引用不在断言调用面。IO 编排
// 〔SQL 预筛/标题反查〕不在断言面，剥法同 ㉜ MemoryGen 先例）
{
  const { readFileSync, writeFileSync } = await import('node:fs');
  const chatSearchRaw = readFileSync(path.join(here, '..', '..', 'entry', 'src', 'main', 'ets',
    'common', 'providers', 'ToolChatSearch.ets'), 'utf-8');
  const memTextSrc = readFileSync(path.join(tmpDir, 'MemoryText.ts'), 'utf-8');
  writeFileSync(path.join(tmpDir, 'ToolChatSearch.ts'),
    memTextSrc + '\n' + chatSearchRaw.replace(/import[\s\S]*?from\s+'[^']+';/g, ''));
}

// 75 组配套：跨会话检索纯函数（ToolChatSearch 剥 import + MemoryText 前置拼接直跑）
const {
  escapeChatLikeToken, rankChatHits, clipChatSnippet, formatChatHitDate,
  composeChatSearchResult, CHAT_SEARCH_CANDIDATE_LIMIT, CHAT_TOOL_RESULT_MAX_COUNT,
  CHAT_TOOL_RESULT_MAX_CHARS,
  // 131 组配套：会话读取纯函数（2026-09-19 跨会话记忆深化笔 get_chats——同文件同剥桩；
  // isCrossSessionTool 不进直跑面：函数体引 ToolTypes 常量，剥 import 后未定义，断言走
  // 源码形态钉）
  composeChatListResult, locateChatByTitle, composeChatLocateNone, composeChatLocateMulti,
  resolveChatReadStart, composeChatReadResult,
  CHAT_LIST_MAX, CHAT_READ_TAIL_MAX, CHAT_READ_LINE_MAX, CHAT_READ_RESULT_MAX_CHARS
} = await import('./.tmp/ToolChatSearch.ts');

// ═══ 75 组：跨会话检索（2026-09-13 跨会话检索笔，方案-跨会话检索-20260913——检索纯函数
// 直跑 + 隐私面/注册/声明/接线源码形态。判据一律先剥注释（73 组 strip73 同法）═══
{
  const { readFileSync: rfs75 } = await import('node:fs');
  const rd75 = (rel) => rfs75(path.join(here, '..', '..', 'entry', 'src', 'main', 'ets', rel), 'utf-8');
  const strip75 = (src) => src.split('\n')
    .map((l) => l.replace(/\r$/, '').replace(/\/\/.*$/, '')).join('\n');
  const mk75 = (conversationId, role, content, createdAt) =>
    ({ conversationId: conversationId, role: role, content: content, createdAt: createdAt });
  const day75 = new Date(2026, 8, 13, 12, 0, 0).getTime();

  // A. 检索纯函数（ToolChatSearch 剥桩直跑面）
  // A1 LIKE 转义：通配符三字符加前缀 / 普通词原样
  check('75 转义-通配符三字符各加前缀',
    escapeChatLikeToken('a%b_c\\d'), 'a\\%b\\_c\\\\d');
  check('75 转义-普通词原样', escapeChatLikeToken('猫粮 brand'), '猫粮 brand');
  // A2 打分排序：score 降序 → createdAt 降序 → SQL 返回序；敏感整条跳过；ASCII 大小写不敏感
  check('75 排序-同分新者在前（createdAt 次键）',
    rankChatHits([mk75('c1', 'user', '聊了猫A', day75), mk75('c1', 'user', '聊了猫B', day75 + 1)],
      ['猫'], '猫').map((r) => r.content), ['聊了猫B', '聊了猫A']);
  check('75 排序-多词计分压过新近度',
    rankChatHits([mk75('c1', 'user', '只提到猫', day75 + 9999),
      mk75('c1', 'user', '聊过猫也聊过狗', day75)], ['猫', '狗'], '猫 狗')
      .map((r) => r.content), ['聊过猫也聊过狗', '只提到猫']);
  check('75 排序-敏感命中整条跳过（外发面口径）',
    rankChatHits([mk75('c1', 'user', '猫的密码忘记了', day75 + 1),
      mk75('c1', 'user', '正常聊猫', day75)], ['猫'], '猫')
      .map((r) => r.content), ['正常聊猫']);
  check('75 排序-ASCII 大小写不敏感（与 LIKE 预筛口径对齐）',
    rankChatHits([mk75('c1', 'user', 'I love Python', day75)], ['python'], 'python').length, 1);
  // A3 片段开窗：短文原样压空白 / 长文以命中词为中心 / 无命中回头部
  check('75 片段-短文原样含压空白', clipChatSnippet('多行\n\n猫\t猫  聊天', ['猫']),
    '多行 猫 猫 聊天');
  check('75 片段-长文开窗含命中词',
    clipChatSnippet('A'.repeat(100) + '猫'.repeat(10) + 'B'.repeat(100), ['猫']),
    '…' + 'A'.repeat(30) + '猫'.repeat(10) + 'B'.repeat(80) + '…');
  check('75 片段-无命中回头部截取',
    clipChatSnippet('X'.repeat(200), ['猫']), 'X'.repeat(120) + '…');
  check('75 日期-本地年月日格式', formatChatHitDate(day75), '2026-9-13');
  // A4 结果文本四形态
  check('75 结果-空 query 索要关键词',
    composeChatSearchResult([mk75('c1', 'user', '猫', day75)], new Map(), '，。'),
    '请提供要检索的关键词。');
  check('75 结果-无命中换词提示',
    composeChatSearchResult([mk75('c1', 'user', '完全无关内容', day75)], new Map(), '猫'),
    '未检索到相关消息。可更换更具体的关键词再试。');
  check('75 结果-行渲染与标题缺失回退（含角色与日期）',
    composeChatSearchResult([mk75('c1', 'user', '我家猫叫小花', day75)], new Map(), '猫'),
    '检索到 1 条相关消息，来自 1 个会话，按相关度排序\n' +
    '[1] 会话「未命名会话」（2026-9-13）用户：我家猫叫小花');
  const twoConv75 = new Map([['c1', '饮食记录'], ['c2', '运动计划']]);
  check('75 结果-多会话计数与标题渲染',
    composeChatSearchResult([mk75('c1', 'user', '聊了猫一', day75),
      mk75('c2', 'assistant', '聊了猫二', day75)], twoConv75, '猫').split('\n')[0],
    '检索到 2 条相关消息，来自 2 个会话，按相关度排序');
  const many75 = [];
  for (let i = 1; i <= 12; i++) {
    many75.push(mk75('c1', 'user', '猫条目' + i, day75 + i));
  }
  const capped75 = composeChatSearchResult(many75, new Map([['c1', '会话一']]), '猫');
  check('75 结果-条数封顶带尾行',
    [capped75.split('\n')[0], capped75.split('\n').filter((l) => l.startsWith('[')).length,
      capped75.split('\n')[capped75.split('\n').length - 1]],
    ['检索到 10 条相关消息，来自 1 个会话，按相关度排序', 10,
      '已达返回上限，可用更具体的关键词再检索']);
  check('75 结果-未截断无尾行',
    composeChatSearchResult(many75.slice(0, 3), new Map(), '猫').includes('已达返回上限'), false);
  check('75 封顶-候选与返回三常量',
    [CHAT_SEARCH_CANDIDATE_LIMIT, CHAT_TOOL_RESULT_MAX_COUNT, CHAT_TOOL_RESULT_MAX_CHARS],
    [300, 10, 2000]);

  // B. 源码形态（隐私四闸 / SQL 预筛 / 注册 / 声明 / 接线 / 同步 / 回归）
  const db75 = strip75(rd75('common/store/ChatDb.ets'));
  // ★ 2026-09-21 消息存储机制改造笔 3 改判：排序键切 seq 单键；★ 同日自检 P1 修复笔**翻回**：
  // 本窗是跨会话混排 + LIMIT 截断，排序键即**候选集成员判据**——seq 是会话内 0 基序号（换会话
  // 重置），在该扫描域不可比 ⇒ 禁切，排序权威维持 `m.createdAt DESC, m.rowid DESC`（作用域判据
  // 与执行级真值表在 assert-store-consistency 145 组 ①②⑩）；LIKE 匹配面与三条件零改动
  check('75 SQL-locked 会话 join 排除 + 角色过滤 + ESCAPE + LIMIT 有界 + createdAt 序（本窗禁切 seq）',
    db75.includes('WHERE c.locked = 0 AND m.conversationId <> ? AND m.role IN') &&
    db75.includes("ESCAPE '\\\\'") &&
    db75.includes('ORDER BY m.createdAt DESC, m.rowid DESC LIMIT ?'),
    true);
  const chatSrc75 = strip75(rd75('common/providers/ToolChatSearch.ets'));
  check('75 执行器-中转键取当前会话 + 恒 resolve（错误走 JSON 错误信息）',
    chatSrc75.includes("AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? ''") &&
    chatSrc75.includes("error: '会话记录读取失败：'"), true);
  check('75 执行器-标题批量反查（两查询有界，禁逐行）',
    chatSrc75.includes('queryConversationTitles(rows)'), true);
  const toolSrc75 = strip75(rd75('common/providers/ToolTypes.ets'));
  check('75 注册-常量与 desc 划界（与记忆分层——不点 search_memory 工具名防未声明调用）',
    toolSrc75.includes("export const TOOL_SEARCH_CHATS: string = 'search_chats';") &&
    toolSrc75.includes('跨会话检索用户的历史聊天记录。') &&
    !toolSrc75.slice(toolSrc75.indexOf('name: TOOL_SEARCH_CHATS'),
      toolSrc75.indexOf('name: TOOL_SEARCH_CHATS') + 900).includes('search_memory'), true);
  // ★ 2026-09-13 技能层笔 1：模式驱动名单由单件扩为双件——本条原钉「名单仍只
  // search_memory」（防跨会话检索被塞进模式驱动），改钉「名单恰为两件且本件不在其中」
  // 同效且随形（恰等而非 includes——名单被塞第三件时本条照红）
  check('75 注册-defaultEnabled=false 且非模式驱动（名单恰两件，本件不在其中）',
    /name: TOOL_SEARCH_CHATS,[\s\S]*?defaultEnabled: false,/.test(toolSrc75) &&
    toolSrc75.includes(
      'const MODE_DRIVEN_TOOLS: string[] = [TOOL_SEARCH_MEMORY, TOOL_USE_SKILL];') &&
    !/MODE_DRIVEN_TOOLS: string\[\] = \[[^\]]*TOOL_SEARCH_CHATS/.test(toolSrc75), true);
  // ★ 2026-09-17 会话上下文用量笔：声明链迁 calc，隐私闸钉随址改读 calc（语义不变）；
  // send75 仍 = ChatSendCtrl（下方中转键钉继续用）
  // ★ 2026-09-19 跨会话记忆深化笔随形改判：单件过滤退役（t.name !== TOOL_SEARCH_CHATS），
  // 判据换 isCrossSessionTool 域级单源——细形态与旧单件零残留负向钉在 131 组隐私闸条，
  // 此处钉 privateMode 闸在位与判据消费
  const send75 = strip75(rd75('components/chat/ChatSendCtrl.ets'));
  const calc75 = strip75(rd75('components/chat/ChatContextUsage.ets'));
  check('75 声明-隐私会话不声明（跨会话域判据单源；深化笔随形）',
    calc75.includes('if (this.refs.privateMode()) {') &&
    calc75.includes('isCrossSessionTool(t.name)'), true);
  check('75 中转键-发送时现写（与搜索条数键同位）',
    send75.includes("AppStorage.setOrCreate<string>(CHAT_ACTIVE_CONV_KEY, this.refs.conversationId())"),
    true);
  const toolsPage75 = strip75(rd75('components/assistants/AssistantToolsPage.ets'));
  // ★ 2026-09-18 分类卡重组随形：成员行图标映射退役，改钉卡片承载——跨会话检索归本地
  // 检索卡（页面消费卡常量渲染，ToolTypes group 标注为归属单源）
  check('75 页面-工具在卡承载（跨会话检索入本地检索卡）',
    toolsPage75.includes('TOOL_GROUP_LOCAL') &&
    /name: TOOL_SEARCH_CHATS,\s*group: TOOL_GROUP_LOCAL,/.test(strip75(rd75('common/providers/ToolTypes.ets'))), true);
  const help75 = strip75(rd75('common/HelpContent.ets'));
  // ★ 2026-09-17 界面耦合清理笔：原两锚为工具名枚举片段（每加一件工具都要随形）——按
  // HelpContent 头注释「界面耦合红线」节退役，改钉本笔的语义契约（跨会话检索覆盖面 +
  // 加密会话零检索，用户可见行为）；枚举片段的零回流由 set-pref-tool-check 负向钉承担。
  check('75 同步-帮助讲明检索历史会话的覆盖面（其他会话可见 + 加密会话不参与；★ 2026-09-17 锚改语义句）',
    help75.includes('检索历史会话查找的是其他会话的聊天记录，加密会话的内容不会被检索到'), true);
  const assistDb75 = strip75(rd75('common/store/AssistantDb.ets'));
  check('75 回归-控制台 seed 未扩（非立身能力，手动开——零代际迁移）',
    assistDb75.includes('"get_usage_stats"]') &&
    !assistDb75.includes('search_chats'), true);
}

// ══ 131 组：跨会话记忆深化 get_chats（2026-09-19 深化笔，任务书-跨会话记忆深化-20260919
// ——清单与定位纯函数直跑 + offset 归一与窗口渲染直跑 + 注册/三查询/隐私闸/划界源码形态。
// 判据一律先剥注释（75 组 strip75 同法）；isCrossSessionTool 不进直跑面（函数体引 ToolTypes
// 常量，剥 import 后未定义——形态钉承担）═══
{
  const { readFileSync: rfs131 } = await import('node:fs');
  const rd131 = (rel) => rfs131(path.join(here, '..', '..', 'entry', 'src', 'main', 'ets', rel), 'utf-8');
  const strip131 = (src) => src.split('\n')
    .map((l) => l.replace(/\r$/, '').replace(/\/\/.*$/, '')).join('\n');
  const mkConv131 = (id, title, updatedAt) => ({ id: id, title: title, updatedAt: updatedAt });
  const mkRead131 = (role, content) => ({ role: role, content: content, createdAt: 0 });
  const day131 = new Date(2026, 8, 19, 12, 0, 0).getTime();

  // A. 清单与定位纯函数直跑
  // A1 list 渲染：空态 / 行形态 / 标题缺失回退 / 封顶尾行 / 未封顶无尾行
  check('131 清单-空清单回执', composeChatListResult([], false), '暂无可读的历史会话。');
  check('131 清单-行渲染与标题缺失回退（含日期）',
    composeChatListResult([mkConv131('c1', '猫粮调研', day131), mkConv131('c2', '', day131 + 1)], false),
    '[1] 猫粮调研（2026-9-19）\n[2] 未命名会话（2026-9-19）');
  const capList131 = [];
  for (let i = 0; i < CHAT_LIST_MAX; i++) {
    capList131.push(mkConv131('c' + i, '会话' + i, day131 + i));
  }
  check('131 清单-封顶尾行动态拼',
    composeChatListResult(capList131, true).split('\n').pop(), '仅列最近 30 个会话');
  check('131 清单-未封顶无尾行',
    composeChatListResult(capList131.slice(0, 3), false).includes('仅列最近'), false);

  // A2 定位三态（locateChatByTitle 真值表 + 两回执文案）
  check('131 定位-三态真值表',
    [locateChatByTitle([]).state,
      locateChatByTitle([mkConv131('c9', 'T', day131)]).state + ':' +
        locateChatByTitle([mkConv131('c9', 'T', day131)]).hitId,
      locateChatByTitle([mkConv131('c1', 'T', day131), mkConv131('c2', 'T', day131)]).state],
    ['none', 'unique:c9', 'multi']);
  check('131 定位-none 回执附最近名单引导重试（list 渲染同形）',
    composeChatLocateNone([mkConv131('c1', '饮食记录', day131)]),
    '没有找到这个标题的会话。以下是最近的会话，确认标题后用 read 重试：\n' +
    '[1] 饮食记录（2026-9-19）');
  check('131 定位-none 空名单兜底', composeChatLocateNone([]),
    '没有找到这个标题的会话，当前也没有其他可读的历史会话。');
  check('131 定位-multi 拒歧义列全部命中带日期',
    composeChatLocateMulti([mkConv131('c1', '同名会话', day131), mkConv131('c2', '同名会话', day131 + 1)]),
    '有 2 个同名会话，暂无法进一步区分，本次未读取。全部命中：\n' +
    '[1] 同名会话（2026-9-19）\n[2] 同名会话（2026-9-19）');

  // B. offset 归一与窗口渲染直跑
  // B1 resolveChatReadStart 真值表：默认末页（NaN/脏值/<1）/ 有效 offset / 越上界收末页 /
  // total=0 与小额 total
  check('131 归一-默认末页（未传 NaN 与脏值同归）',
    [resolveChatReadStart(Number.NaN, 100), resolveChatReadStart(0, 100),
      resolveChatReadStart(-5, 100), resolveChatReadStart(2.5, 100)],
    [71, 71, 71, 71]);
  check('131 归一-有效 offset 原样（1 基升序）',
    [resolveChatReadStart(1, 100), resolveChatReadStart(50, 100)], [1, 50]);
  // ★ 2026-09-20 修复（D1-2）禁止形态钉：前向分页上界 = 末条序号。旧口径
  // Math.min(offset, tailStart) 把末页起点当上界——尾行「可用 offset=N 继续读取」发出的
  // N 恒 > start，夹回后重读同一页（同页死循环）；total ≤ 30 时任何 offset 都归 1。
  // 判据：offset ∈ (末页起点, 末条序号] 原样生效（9→9 而非旧口径 1），超末条序号才收末页
  check('131 归一-前向分页可达（offset 落在末页起点之后仍原样；仅超末条序号收末页）',
    [resolveChatReadStart(9, 12), resolveChatReadStart(30, 100),
      resolveChatReadStart(100, 100), resolveChatReadStart(101, 100)],
    [9, 30, 100, 71]);
  check('131 归一-越上界收末页', resolveChatReadStart(9999, 100), 71);
  // 钉名核正（2026-09-20 收尾复核备注）：此态回 1 的来源是 tailStart 下界（total ≤ 末页长
  // 时 tailStart = 1），不是「越下界归 1」——越下界与脏值同走 tailStart 分支（见上一条真值表）
  check('131 归一-total=0 与小额 total 收末页起点 1（小额时 tailStart 恒 1）',
    [resolveChatReadStart(Number.NaN, 0), resolveChatReadStart(Number.NaN, 20),
      resolveChatReadStart(9999, 20)], [1, 1, 1]);
  check('131 归一-边界恰等不截（offset 恰为末页起点）', resolveChatReadStart(71, 100), 71);

  // B2 窗口渲染：正序全局序号与角色 / 单条截断 / 敏感跳号 / 字符贪心 / 三缺口尾行 / 空窗兜底
  // ★ 2026-09-20 修复（D1-1）：入参 = SQL 真实序（queryConversationWindowForRead 的
  // ORDER BY createdAt ASC），渲染直排——[start] 恒为窗口最早条。旧钉喂 DESC 序并期望
  // 「内部转正序」，前提与生产输入相反：钉全绿而线上序号整体反号（[start] 挂窗口最新条）
  check('131 窗口-升序窗口原样直排 + 全局序号与角色映射（入参最早在前）',
    composeChatReadResult([mkRead131('user', '提问甲'), mkRead131('assistant', '回答乙')],
      2, 1),
    '该会话共 2 条消息，当前显示第 1–2 条：\n[1] 用户：提问甲\n[2] 助手：回答乙');
  check('131 窗口-单条超 800 尾截加省略号（保留换行 trim 首尾）',
    composeChatReadResult([mkRead131('user', 'a'.repeat(801))], 1, 1)
      .includes('[' + '1' + '] 用户：' + 'a'.repeat(800) + '…'), true);
  check('131 窗口-换行保留（内容中间换行原样）',
    composeChatReadResult([mkRead131('user', '第一行\n第二行')], 1, 1)
      .includes('用户：第一行\n第二行'), true);
  const sensRows131 = [mkRead131('user', '正常第一'), mkRead131('user', '我的密码是123456'),
    mkRead131('user', '正常第二')]; // SQL 升序入参序（最早在前）——[1] 正常第一 / [2] 敏感跳过 / [3] 正常第二
  check('131 窗口-敏感命中整条静默跳过（序号跳号、不回补不注明）',
    composeChatReadResult(sensRows131, 3, 1),
    '该会话共 3 条消息，当前显示第 1–3 条：\n[1] 用户：正常第一\n[3] 用户：正常第二');
  const longRows131 = [];
  for (let i = 0; i < 12; i++) {
    longRows131.push(mkRead131('user', '内容' + i + 'x'.repeat(480)));
  }
  const cappedRead131 = composeChatReadResult(longRows131, 12, 1);
  check('131 窗口-总字符 4000 贪心装入（超限整行不进，保已选行完整）',
    [cappedRead131.split('\n').filter((l) => /^\[\d+\] /.test(l)).length,
      cappedRead131.split('\n').pop()], [8, '可用 offset=9 继续读取']);
  // ★ 2026-09-20 修复（D1-2）：尾行 offset 必须可跟随——照尾行提示重读要取到剩余内容
  //（旧口径 start 被夹回末页起点，第二页与首屏逐字相同 = 同页死循环，被 4000 字预算裁掉
  //  的内容任何 offset 都取不到）
  const nextStart131 = resolveChatReadStart(9, 12);
  const page2Read131 = composeChatReadResult(longRows131.slice(nextStart131 - 1), 12, nextStart131);
  check('131 窗口-尾行 offset 可跟随（第二页取到剩余内容、序号续接、与首屏不同）',
    [nextStart131, page2Read131.split('\n')[0], page2Read131.includes('[9] 用户：内容8'),
      page2Read131.split('\n').filter((l) => /^\[\d+\] /.test(l))
        .map((l) => l.slice(0, l.indexOf(']') + 1)).join(''),
      page2Read131 === cappedRead131],
    [9, '该会话共 12 条消息，当前显示第 9–12 条：', true, '[9][10][11][12]', false]);
  // ★ 2026-09-20 修复（D1-2）：头行报实显序号（窗口长度 ≠ 实显行数——预算裁剪缩尾、
  // 前导敏感行缩首，旧口径写 start + rows.length - 1 = 窗口长度，与「只显示 k 行」不符）
  check('131 窗口-头行报实显序号（预算裁剪缩尾 + 前导敏感行缩首）',
    [cappedRead131.split('\n')[0],
      composeChatReadResult([mkRead131('user', '卡号6222020200112233445'),
        mkRead131('user', '正常内容')], 2, 1).split('\n')[0]],
    ['该会话共 12 条消息，当前显示第 1–8 条：', '该会话共 2 条消息，当前显示第 2–2 条：']);
  check('131 窗口-更早未读给 offset=1 提示（带 M 条数）',
    composeChatReadResult(longRows131.slice(6), 12, 7)
      .split('\n').filter((l) => l.startsWith('可用 offset=1')),
    ['可用 offset=1 读取更早的 6 条']);
  const midRead131 = composeChatReadResult(longRows131.slice(2, 8), 12, 3);
  check('131 窗口-双缺口并存（更早与继续两尾行同出）',
    [midRead131.split('\n').filter((l) => l.startsWith('可用')).join('|'),
      midRead131.split('\n')[0]],
    ['可用 offset=1 读取更早的 2 条|可用 offset=9 继续读取',
      '该会话共 12 条消息，当前显示第 3–8 条：']);
  check('131 窗口-窗口尽无继续提示、total 恰尽无任何尾行',
    composeChatReadResult(longRows131.slice(0, 3), 3, 1).includes('可用 offset'), false);
  check('131 窗口-空窗兜底（total=0 与 rows 空）',
    [composeChatReadResult([], 0, 1), composeChatReadResult([], 5, 1)],
    ['该会话暂无可读的消息。', '该会话暂无可读的消息。']);
  check('131 窗口-全敏感窗口兜底（不注明原因）',
    composeChatReadResult([mkRead131('user', '卡号6222020200112233445')], 1, 1),
    '该会话暂无可读的消息。');

  // C. 源码形态（四常量 / 三查询 / 注册 / 隐私闸 / 划界与外泄 / 帮助 / seed）
  check('131 常量-四封顶值钉（拍板 2 与 §2.3）',
    [CHAT_LIST_MAX, CHAT_READ_TAIL_MAX, CHAT_READ_LINE_MAX, CHAT_READ_RESULT_MAX_CHARS],
    [30, 30, 800, 4000]);
  const db131 = strip131(rd131('common/store/ChatDb.ets'));
  check('131 查询-三查询全部 SQL 层 locked = 0（八闸①加密会话不可达）',
    [/queryRecentConversationsForRead[\s\S]{0,400}?WHERE locked = 0/.test(db131),
      /queryConversationIdByTitle[\s\S]{0,300}?WHERE locked = 0 AND title = \?/.test(db131),
      /countConversationMessagesForRead[\s\S]{0,400}?c\.locked = 0/.test(db131),
      /queryConversationWindowForRead[\s\S]{0,400}?c\.locked = 0/.test(db131)],
    [true, true, true, true]);
  // ★ 2026-09-21 消息存储机制改造笔 3 改判：升序窗口排序键切 **seq 单键**（笔 1 的
  // `m.createdAt ASC, m.rowid ASC` 双键退役）；OFFSET 语义本身不变（位次算法只依赖行集与
  // 排序键——COUNT 与窗口两查询筛选面完全一致，见 ChatDb 该函数注释）
  check('131 查询-升序窗口 OFFSET = start - 1 + seq 单键序（offset=1 读更早的自洽序；任务书 SQL 串 DESC 笔误已按语义落）',
    db131.includes('ORDER BY m.seq ASC LIMIT ? OFFSET ?'), true);
  // ── 旧序口径零残留（2026-09-21 自检轮补，P-21 明文负向钉）──
  // 由来：本笔把两处窗口序补上 rowid 决胜键（ChatDb 侧原地改判见上一钉），而**消费方**
  // ToolChatSearch 的 read 回执注释引用了旧 SQL 字面，本笔漏收（复核轮已核正该处 :156）。
  // 判据跑**原文**（含注释）——保护对象是注释口径，剥注释即失明（P-21 ④：与坑40/48 的
  // 「负向钉剥注释防假红」方向相反，按被保护对象选源）。单键窗口序字面（createdAt 后直接
  // 接 LIMIT，无 rowid 决胜）在任何 .ets 中出现即红：代码侧回退由上一钉捕，本钉捕
  // 「代码改了、引用它的注释没改」这一形态。遍历跳过产物目录（assert-net-parse 同款走法）
  const { readFileSync: rfWalk131, readdirSync: rdWalk131 } = await import('node:fs');
  const walk131 = (dir, out) => {
    for (const e of rdWalk131(dir, { withFileTypes: true })) {
      if (['.tmp', 'build', 'oh_modules', 'node_modules', '.git', '.cxx'].includes(e.name)) {
        continue;
      }
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        walk131(p, out);
      } else if (e.name.endsWith('.ets')) {
        out.push(p);
      }
    }
    return out;
  };
  const staleSeq131 = [];
  for (const f of walk131(path.join(here, '..', '..', 'entry', 'src', 'main', 'ets'), [])) {
    const src131 = rfWalk131(f, 'utf-8');
    if (src131.includes('createdAt ASC LIMIT') || src131.includes('createdAt DESC LIMIT')) {
      staleSeq131.push(path.basename(f));
    }
  }
  check('131 查询-旧序口径零残留（全仓 .ets 原文扫「单键窗口序」字面：代码与引用注释同收）',
    staleSeq131, []);
  check('131 查询-当前会话排除（list 条件拼段 + 窗口角色过滤）',
    db131.includes("sql += ' AND id <> ?';") &&
    db131.includes("m.role IN (\\'user\\', \\'assistant\\')"), true);
  const chat131 = strip131(rd131('common/providers/ToolChatSearch.ets'));
  check('131 执行器-中转键取当前会话 + 恒 resolve（错误走文本回执 JSON）',
    chat131.includes("AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? ''") &&
    chat131.includes("error: '会话记录读取失败：'"), true);
  check('131 执行器-定位三态分流与 none 回名单 10 条（COUNT 先行归一后窗口两查）',
    chat131.includes("located.state === 'multi'") &&
    chat131.includes("located.state === 'none'") &&
    chat131.includes('queryRecentConversationsForRead(10, activeConv)') &&
    chat131.includes('countConversationMessagesForRead(located.hitId)'), true);
  const tool131 = strip131(rd131('common/providers/ToolTypes.ets'));
  check('131 注册-形态钉（第 23 件：本地检索卡 / defaultEnabled=false / desc 动态拼 / schema 域单源）',
    /name: TOOL_GET_CHATS,\s*group: TOOL_GROUP_LOCAL,\s*title: '读取历史会话',\s*desc: buildGetChatsDesc\(\),\s*parametersJson: GET_CHATS_SCHEMA,\s*defaultEnabled: false,/.test(tool131), true);
  check('131 desc-划界句与外泄约束句在位（拍板 4：desc 约束句 + 工具卡审计，不加硬守卫）',
    chat131.includes('跨会话找具体内容片段时优先用检索而非通读') &&
    chat131.includes('禁止拼入联网搜索或网页请求的参数外发') &&
    !chat131.slice(chat131.indexOf('buildGetChatsDesc')).slice(0, 600).includes('search_memory'), true);
  check('131 desc-数字自常量动态拼（禁嵌时变值——desc 构建段零 30/800 字面）',
    /return '读取用户的历史会话。action 取 list 查看最近会话清单（标题与日期，最多 ' \+\s*CHAT_LIST_MAX/.test(chat131) &&
    /默认读最新 ' \+\s*CHAT_READ_TAIL_MAX/.test(chat131), true);
  check('131 判据-isCrossSessionTool 双件形态（函数体内引 ToolTypes 两常量——模块环顶层干净）',
    chat131.includes('import { TOOL_GET_CHATS, TOOL_SEARCH_CHATS } from \'./ToolTypes\';') &&
    /return name === TOOL_SEARCH_CHATS \|\| name === TOOL_GET_CHATS;/.test(chat131), true);
  const calc131 = strip131(rd131('components/chat/ChatContextUsage.ets'));
  check('131 隐私闸-双件同闸单源判据（privateMode 条件 + isCrossSessionTool 消费；旧单件过滤零残留）',
    calc131.includes('if (this.refs.privateMode()) {') &&
    calc131.includes('!isCrossSessionTool(t.name)') &&
    !calc131.includes('TOOL_SEARCH_CHATS'), true);
  const help131 = strip131(rd131('common/HelpContent.ets'));
  check('131 帮助-读取历史会话入帮助两处（工具卡枚举 + 本地检索卡语义，加密句保留）',
    help131.includes('检索历史会话、读取历史会话。调用过程以工具卡片显示') &&
    help131.includes('检索历史会话与读取历史会话在本地检索卡') &&
    help131.includes('读取历史会话让助手列出最近的会话，或按标题通读某个会话的完整聊天内容，加密会话同样读不到'), true);
  const assistDb131 = strip131(rd131('common/store/AssistantDb.ets'));
  check('131 回归-控制台 seed 零扩（非立身能力——零代际迁移）',
    !assistDb131.includes('get_chats'), true);
}

report();
