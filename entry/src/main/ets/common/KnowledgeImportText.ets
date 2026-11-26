// 知识库导入导出纯函数域（自 KnowledgeText.ets 尾部整域外迁，方法体逐字零语义变化）。
// 域职责一句话：知识库书级交换格式的纯函数面——自家信封的序列化 / 解析 / 逐条分派 / 审阅弹窗
// 文案 + 通用格式（RikkaHub / Kelivo / SillyTavern 世界书）的出件与收件三形态。
// · 为何单开新件（反碎片下限②申报）：本域横跨两套格式的全部纯逻辑，回并入 KnowledgeText
//   即回复越线原状；并入 KnowledgePack（盘面 I/O 域）会把纯函数域拉进 kit 依赖（选择器 /
//   fileIo / 分享），复制直跑的可测性根基破坏。本件与 KnowledgeText 单向依赖，缝正交。
// · 依赖纪律：唯一 import 源 = KnowledgeText（KnowledgeEntryItem 类型 + 三上限常量 +
//   knowledgeTitleTaken 判定，全局单源不设第二份抄写）；禁引技能域 / 存储域 / 工具域；
//   KnowledgeText 保持零 import，依赖方向恒本件 → KnowledgeText，禁反向。
// · 断言直跑 = assert-knowledge-domain 复制本件为 .tmp/KnowledgeImportText.ts（interface
//   导入行剥除 + 值导入改指 .tmp 副本）；依赖白名单钉 = import 恰两行。
// · 消费方：KnowledgePack（盘面 I/O 链）、KnowledgeLibraryPage（导入导出页链）、
//   ChatSnapshotCtrl（splitKnowledgeKeywords 与会话注入链共用）。

import { KnowledgeEntryItem } from './KnowledgeText';
import { clampKnowledgePriority, clampKnowledgeScan, KNOWLEDGE_TITLE_MAX,
  KNOWLEDGE_KEYWORDS_MAX, KNOWLEDGE_CONTENT_MAX,
  knowledgeTitleTaken } from './KnowledgeText';

// ══ 文件导入导出纯函数 ══
// 自家书级交换格式：三层信封 version / type / data 与竞品同形（RikkaHub ExportData 同构）
// ——通用格式兼容时信封解析可直接复用，只多一个 type 分派分支。盘面 I/O（选择器 / fd 拷贝 /
// 沙箱件 / 分享）仍在 KnowledgePack，本域只有格式构造 / 解析 / 逐条分派 / 预览拼装。

// ── 文件格式常量 ──
// 信封 type（解析按 type 分派格式；本串只认自家，负向钉守全仓零第二处字面量）
export const KNOWLEDGE_FILE_TYPE: string = 'aicontrol_knowledge_book';
// 信封 version（留升级位）。★ 写侧恒写本值；**解析侧三态**（决明拍板）：①缺失或非数值 →
// 宽容照读；②数值且 ≤ 本常量 → 宽容（旧件与新件同读）；③数值且 > 本常量 → **整份拒绝**
// + 中文提示，**不静默归一**（未来版本可能改了字段语义，照读会静默丢数据）。闸位 =
// parseOwnKnowledgeBook 首部；格式语义变化时才递增本值。现值 2 = 条目层含触发精度四字段
//（matchCase / matchWhole / priority / scanDepth）——旧包读 v2 件被版本闸整份拒（预期）；
// 新包读 v1 件缺字段走默认值照读（= 旧行为）
export const KNOWLEDGE_FILE_VERSION: number = 2;
// 自家格式的扩展名（小写归一；页面扩展名分派用）
export const KNOWLEDGE_FILE_EXT: string = 'json';

// ── 通用格式常量 ──
// 竞品信封 type：RikkaHub 与 Kelivo 的世界书格式（两家同形同字段——Kelivo 的导出函数名即
// _toRikkaHubExportJson，故对外只需写**一种**格式）。写侧恒用此值；读侧按「有无 entries」
// 分派（见 parseWorldBookFile）。**字面量单源**：消费一律走常量，全仓禁第二处手写
export const KNOWLEDGE_COMPAT_TYPE: string = 'lorebook';
// 通用格式里关键词的切分符：**只按顿号与逗号**——条目编辑页明写的分隔约定，不猜空格
//（空格可能是关键词本身的一部分，如 machine learning，切了就破坏原意）。★ 与
// splitKnowledgeQuery 的宽分隔符族是两回事：那个切**检索输入**（宁宽），这个切**已保存的
// 关键词字段**（宁准），勿互抄
const KNOWLEDGE_KEYWORD_SEP = /[、,，]+/;

// 文件里的单条条目：v2 起八字段（v1 四字段 + 触发精度四字段）。id 与 createdAt / updatedAt
// **不进文件**——导入恒生成新 id 与新时间戳（与两家竞品「导入必重生 ID」同口径，也避免与
// 库内既有 id 相撞）；条目序 = 数组序。keywords 存**原串**不拆数组（本域检索语义是整串子串
// 匹配，拆开拼回会漂——自家往返保真是本格式存在的第一理由）；source 白名单两值（解析侧
// 归一，非 'assistant' 一律落 'user'，防手改文件造非法值）。触发精度四字段：matchCase /
// matchWhole（0/1）/ priority（0~9999）/ scanDepth（1~20）——写侧值已归一直接写；读侧缺
// 字段走默认（v1 件照读）
export interface KnowledgeFileEntry {
  title: string;
  keywords: string;
  content: string;
  source: string;
  matchCase: number;
  matchWhole: number;
  priority: number;
  scanDepth: number;
}

// 外部件触发字段读取结果：任一字段在场即 hasTrigger；scanClamped = scanDepth 原值越界被钳
//（附注计数用——「不静默」口径）
interface WorldTriggerRead {
  matchCase: number;
  matchWhole: number;
  priority: number;
  scanDepth: number;
  hasTrigger: boolean;
  scanClamped: boolean;
}

// v1 件与缺失字段的默认触发值（= 列默认 = 旧行为）
function defaultFileTrigger(): WorldTriggerRead {
  return { matchCase: 0, matchWhole: 0, priority: 100, scanDepth: 8,
    hasTrigger: false, scanClamped: false };
}

// 解析结果（ok = false 时 error 为整份级中文原因；entries 为原始条目，逐条分派在
// screenKnowledgeEntries——「整份拒」与「逐条说明」两级校验的分界）。
// notice = 外部世界书导入时的附注（已停用条数 / 注入设置未导入），自家格式恒 ''；
// 由 parseKnowledgeBook 组装、审阅弹窗原样呈现（**不在这里做取舍判断**——本域只描述事实）
export interface KnowledgeFileRead {
  ok: boolean;
  name: string;
  entries: KnowledgeFileEntry[];
  error: string;
  notice: string;
}

// 逐条分派结果：importable = 可导入条目（关键词已截到上限）；skipped = 未导入逐条中文原因；
// clippedKeywords = 因超长被截断关键词的条数（不拒收——关键词只是辅助索引，正文不丢）
export interface KnowledgeScreenResult {
  importable: KnowledgeFileEntry[];
  skipped: string[];
  clippedKeywords: number;
}

// 信封与数据层形态（序列化构造用；解析侧同一形态做非受检视图 + 逐字段 typeof 守卫）
interface KnowledgeFileEnvelope {
  version: number;
  type: string;
  data: KnowledgeFileBookData;
}

interface KnowledgeFileBookData {
  name: string;
  entries: KnowledgeFileEntry[];
}

function rejectKnowledgeFile(error: string): KnowledgeFileRead {
  return { ok: false, name: '', entries: [], error: error, notice: '' };
}

// 书名字长收口。★ 为什么必须有这道闸：书名 50 字上限原本由各建书面把关（库页命名对话框
// maxLength、工具 create_book 显式校验），**导入是第四个建书面**且外部件的 data.name 与文件名
// 兜底都不受我方 UI 约束 ⇒ 唯一无闸的入口（实测 3000 字书名原样落库，预览弹窗首行被撑爆、
// 两键顶出屏）。截断而不拒收：书名只是容器标签，审阅弹窗展示的就是最终落库名（用户可见即
// 非静默），拒收会让文件名偏长的世界书整本导不进来，库里本有重命名兜底
function capBookName(name: string): string {
  if (name.length <= KNOWLEDGE_TITLE_MAX) {
    return name;
  }
  return name.substring(0, safeKnowledgeCut(name, KNOWLEDGE_TITLE_MAX)).trim();
}

// 导出序列化：name + 条目八字段。source 如实导出（DB 侧只产 'user' / 'assistant' 两值，
// 白名单外归 'user' 是防御——导出件不携带非法值，与导入侧同款两端口径）；触发精度四值来自
// 行层（写入侧已归一），直接写不重复钳
export function serializeKnowledgeBook(name: string, entries: KnowledgeEntryItem[],
  sources: string[]): string {
  // sources 与 entries 同序（源标签不走 KnowledgeEntryItem——该形态刻意不带 source，
  // 见 KnowledgeDb 的 KnowledgeEntryRow.source 注释）
  const list: KnowledgeFileEntry[] = [];
  for (let i: number = 0; i < entries.length; i++) {
    list.push({
      title: entries[i].title,
      keywords: entries[i].keywords,
      content: entries[i].content,
      source: sources[i] === 'assistant' ? 'assistant' : 'user',
      matchCase: entries[i].matchCase,
      matchWhole: entries[i].matchWhole,
      priority: entries[i].priority,
      scanDepth: entries[i].scanDepth
    });
  }
  const file: KnowledgeFileEnvelope = {
    version: KNOWLEDGE_FILE_VERSION,
    type: KNOWLEDGE_FILE_TYPE,
    data: { name: name, entries: list }
  };
  return JSON.stringify(file);
}

// ── 通用格式导出 ──
// 写 **RikkaHub 信封 + 最小写入**：RikkaHub 读它是自家格式（LorebookSerializer.tryImportNative）；
// Kelivo 读它走「只认 data 键、连 type 都不校验」的宽容解析。只写有对应物的字段（条目名 /
// 正文 / 关键词），其余（id / position / role / useRegex / constantActive / enabled 等）**一律
// 省略**——两家模型每个字段都带默认值，省略即由对方补**它自己的**默认：零编造、零语义债，
// 且顺带绕开两家在 position 枚举大小写上的人为不一致（那是竞品互读的坑，省略字段即不经
// 那条路）。条目层不写 `type`：对方 entries 的声明类型是具体子类，不需要判别符
interface KnowledgeCompatEntry {
  name: string;
  content: string;
  keywords: string[];
  // 三家共识触发字段（priority / scanDepth / caseSensitive——两家模型「priority 数值大的先
  // 注入」语义一致，直接写不产生歧义）；**不写整词**（matchWhole）：两家模型均无此字段
  //（源码核对结论），写了要么被忽略要么触发未知字段风险，属语义编造
  priority?: number;
  scanDepth?: number;
  caseSensitive?: boolean;
}

interface KnowledgeCompatBookData {
  name: string;
  entries: KnowledgeCompatEntry[];
}

interface KnowledgeCompatEnvelope {
  version: number;
  type: string;
  data: KnowledgeCompatBookData;
}

export interface KnowledgeCompatExport {
  json: string;
  exported: number; // 写进文件的条数
  dropped: number;  // 无关键词被排除的条数
}

// 关键词整串 → 数组（**只按顿号与逗号**切——见 KNOWLEDGE_KEYWORD_SEP 注释；去空段与首尾
// 空白）。与导入侧 joinKeywordField 是同一份 UI 约定的两个方向（那边按顿号合、这边按顿号
// 逗号切）
export function splitKnowledgeKeywords(keywords: string): string[] {
  const parts: string[] = [];
  for (const raw of keywords.split(KNOWLEDGE_KEYWORD_SEP)) {
    const part: string = raw.trim();
    if (part !== '') {
      parts.push(part);
    }
  }
  return parts;
}

// 通用格式序列化。★ **无关键词的条目不出**：对方的生效机制是关键词命中（`constantActive`
// 默认 false），无关键词的条目在那边**永不生效**——与其产出一个死条目，不如不写并在结果里
// 明示原因（「不静默丢件」口径）。本应用里关键词留空是**合法常态**（条目编辑页明写「留空
// 则只按名称与正文检索」），故这条不是边角情形，必须在 UI 面讲清不可静默略过
export function serializeKnowledgeBookCompat(name: string,
  entries: KnowledgeEntryItem[]): KnowledgeCompatExport {
  const list: KnowledgeCompatEntry[] = [];
  let dropped: number = 0;
  for (const entry of entries) {
    const keywords: string[] = splitKnowledgeKeywords(entry.keywords);
    if (keywords.length === 0) {
      dropped++;
      continue;
    }
    // 三项共识字段随行写出（值为默认时也写——两家的默认值同为 100/8/false，写不写行为
    // 等价，但显式写让「这份文件带着触发配置」可被人工检视；整词不写，见接口注释）
    list.push({ name: entry.title, content: entry.content, keywords: keywords,
      priority: entry.priority, scanDepth: entry.scanDepth,
      caseSensitive: entry.matchCase === 1 });
  }
  const file: KnowledgeCompatEnvelope = {
    version: KNOWLEDGE_FILE_VERSION,
    type: KNOWLEDGE_COMPAT_TYPE,
    data: { name: name, entries: list }
  };
  return { json: JSON.stringify(file), exported: list.length, dropped: dropped };
}

// 导出结果提示（**仅在有条目被排除时非空**——没有要交代的事就不打扰，页面据此决定 toast
// 与否）。入参取两个计数而非整个 KnowledgeCompatExport：盘面域带回的正是这两个数
export function composeKnowledgeCompatExportTip(exported: number, dropped: number): string {
  if (dropped === 0) {
    return '';
  }
  return '已导出 ' + exported + ' 条，' + dropped +
    ' 条没有关键词的条目未导出。通用格式按关键词触发，没有关键词的条目在别的应用里不会生效。';
}

// 导入整份级校验（结构拒，文案逐字定死——页面 toast 与断言的契约面）；逐条内容校验在
// screenKnowledgeEntries。解析侧对未知字段**容忍**（只读白名单字段，多余字段不拒收）；条目
// 数超 KNOWLEDGE_ENTRY_MAX 的闸在页面链（常量单源在 KnowledgeDb，本域依赖纪律拿不到，不为
// 它破纪律）。
// ★ 本函数只做**分派**：自家 type → 原链（parseOwnKnowledgeBook）；其余一律交
// parseWorldBookFile（RikkaHub/Kelivo 信封 / SillyTavern World Info / Kelivo 裸形态）。
// fallbackName = 选择器取到的**文件名**（去扩展名）——外部世界书常无书名字段（ST 格式压根
// 没有 name 概念），照 RikkaHub「导入时用文件名当书名」先例兜底；自家格式恒不看它（自家
// 书名必填、缺失即拒——自家往返保真的契约面，不外溢到外部件）
export function parseKnowledgeBook(text: string, fallbackName: string = ''): KnowledgeFileRead {
  let parsed: object | null = null;
  try {
    parsed = JSON.parse(text) as object | null;
  } catch (e) {
    return rejectKnowledgeFile('文件不是有效 JSON，未导入。');
  }
  // ★ 顶层 null 必须先过闸：`null` 是合法 JSON 值（JSON.parse('null') 返 null），而
  // `env.type` 读 null 属性会抛 TypeError——抛出去会被盘面域兜成「文件读取失败：Cannot read
  // properties of null…」英文原文，与「整份拒给中文原因」的契约不符。其余原始值（数字 /
  // 字符串 / 布尔 / 数组）不在此拦：它们走世界书链后同落「不是知识库文件」
  const env: KnowledgeFileEnvelope | null = parsed as KnowledgeFileEnvelope | null;
  if (env === null) {
    return rejectKnowledgeFile('这个文件不是知识库文件，未导入。');
  }
  if (env.type === KNOWLEDGE_FILE_TYPE) {
    return parseOwnKnowledgeBook(env);
  }
  return parseWorldBookFile(env, fallbackName);
}

// 自家格式链：四拒逐字（坏 JSON 一拒在分派层）+ 版本闸一拒 + 字段白名单 + source 两值归一
function parseOwnKnowledgeBook(env: KnowledgeFileEnvelope): KnowledgeFileRead {
  // ── 版本闸（第五拒，决明拍板三态，见 KNOWLEDGE_FILE_VERSION 注）──
  // 判据是**关系式**（与 KNOWLEDGE_FILE_VERSION 现比）而不是写死数值——升版本时本处零改动。
  // 竞品链 parseWorldBookFile **不受本闸约束**（外部件的版本号与本应用无关，见该函数头注释）
  if (typeof env.version === 'number' && env.version > KNOWLEDGE_FILE_VERSION) {
    return rejectKnowledgeFile('这个文件来自更高版本的知识库格式，当前版本读不了。请升级应用后再导入。');
  }
  const data: KnowledgeFileBookData | null = env.data ?? null;
  if (data === null || typeof data !== 'object') {
    // data 缺失或非对象 ⇒ 名称必缺，落名称拒
    return rejectKnowledgeFile('文件里没有知识库名称，未导入。');
  }
  const ownName: string = (typeof data.name === 'string' ? data.name : '').trim();
  if (ownName === '') {
    return rejectKnowledgeFile('文件里没有知识库名称，未导入。');
  }
  const name: string = capBookName(ownName);
  if (!Array.isArray(data.entries)) {
    return rejectKnowledgeFile('文件里没有条目清单，未导入。');
  }
  const entries: KnowledgeFileEntry[] = [];
  const rawItems: object[] = data.entries as object[];
  for (let i: number = 0; i < rawItems.length; i++) {
    const rec: KnowledgeFileEntry | null = rawItems[i] as KnowledgeFileEntry | null;
    // 数组里塞了 null（手改件）⇒ 落空条目交逐条分派按「无标题」说明；★ 禁在解析层抛
    //（`null.title` 会抛 TypeError，被盘面域兜成英文原文——与「条目级问题逐条说明、不升级
    // 成整份拒」的口径相反）
    if (rec === null) {
      const d: WorldTriggerRead = defaultFileTrigger();
      entries.push({ title: '', keywords: '', content: '', source: 'user',
        matchCase: d.matchCase, matchWhole: d.matchWhole, priority: d.priority,
        scanDepth: d.scanDepth });
      continue;
    }
    // 逐字段 typeof 守卫：非对象项 / 缺字段的条目落默认值，交逐条分派按「无标题」说明
    //（条目级问题逐条说明，不在解析层升级成整份拒）。触发精度四字段同守卫（v1 件缺字段
    // → 默认值照读；脏值钳位——KnowledgeText 的 clamp 单源）
    entries.push({
      title: typeof rec.title === 'string' ? rec.title : '',
      keywords: typeof rec.keywords === 'string' ? rec.keywords : '',
      content: typeof rec.content === 'string' ? rec.content : '',
      source: rec.source === 'assistant' ? 'assistant' : 'user',
      matchCase: typeof rec.matchCase === 'number' ? (rec.matchCase === 1 ? 1 : 0) : 0,
      matchWhole: typeof rec.matchWhole === 'number' ? (rec.matchWhole === 1 ? 1 : 0) : 0,
      priority: typeof rec.priority === 'number' ? clampKnowledgePriority(rec.priority) : 100,
      scanDepth: typeof rec.scanDepth === 'number' ? clampKnowledgeScan(rec.scanDepth) : 8
    });
  }
  return { ok: true, name: name, entries: entries, error: '', notice: '' };
}

// ── 外部世界书链 ──
// 收件面 = 三种：① RikkaHub / Kelivo 信封（`{version, type:'lorebook', data:{name, entries[]}}`）
// ② SillyTavern World Info v2（无信封，顶层 entries 是**以 uid 字符串为键的 Map**）
// ③ Kelivo 裸形态（无信封，顶层 entries 为数组——Kelivo 的解析只看 data 键或 entries 键、
//    连 type 都不校验，故它写出的边角形态也要吃）。**不读的字段一律不读**：注入位置与注入
//    角色在本应用无对应物，条目顺序 order 有意不映射（方向相反），原样忽略并在弹窗附注里
//    明说。触发精度四字段（priority / scanDepth / caseSensitive / matchWholeWords）自 v63 起
//    有对应字段并读取（见 KnowledgeWorldEntry 与 readWorldTrigger），自动注入机制自 v51 起存在
interface KnowledgeWorldHolder {
  name?: string;
  entries?: object;
}

interface KnowledgeWorldEntry {
  name?: string;
  comment?: string;
  key?: string[] | string;
  keywords?: string[] | string;
  content?: string;
  enabled?: boolean;
  disable?: boolean;
  // 触发字段：两套键名都声明——ST 导出常见驼峰、手改件常见蛇形，读侧都试（取值一律先
  // typeof 再采信，脏类型视为缺失）。priority = RikkaHub / Kelivo 模型字段（数值大的先注入，
  // 与我方语义同向）；scanDepth 两家同名；caseSensitive 同名（true = 区分大小写）；
  // matchWholeWords 仅 ST（语义与我方一致，可直接映射）。★ **ST 的 order 有意不声明不读**
  //（R13：语义方向相反——ST「大 order 后插入」vs 我方「大 priority 先注入」，且是书内相对
  // 序非跨书全局序，映射会全员钳 0 或打乱用户手写顺序，不映射、附注明说）；★ **ST 的 depth
  // 是注入深度不是扫描深度**（只在 position=AT_DEPTH 生效），不读
  priority?: number;
  scanDepth?: number;
  caseSensitive?: boolean;
  matchWholeWords?: boolean;
  scan_depth?: number;
  case_sensitive?: boolean;
  match_whole_words?: boolean;
}

// 外部件触发字段读取（两形态共用）：驼峰优先、蛇形兜底；数字钳位（priority 0~9999 /
// scanDepth 1~20——clamp 单源 KnowledgeText）；任一字段在场即 hasTrigger（附注「已保留」
// 计数用）；scanDepth 原值越界即 scanClamped（附注「钳位」计数用，不静默）
function readWorldTrigger(rec: KnowledgeWorldEntry): WorldTriggerRead {
  const out: WorldTriggerRead = defaultFileTrigger();
  const caseRaw: boolean | undefined =
    rec.caseSensitive !== undefined ? rec.caseSensitive : rec.case_sensitive;
  if (caseRaw !== undefined && typeof caseRaw === 'boolean') {
    out.matchCase = caseRaw ? 1 : 0;
    out.hasTrigger = true;
  }
  const wholeRaw: boolean | undefined =
    rec.matchWholeWords !== undefined ? rec.matchWholeWords : rec.match_whole_words;
  if (wholeRaw !== undefined && typeof wholeRaw === 'boolean') {
    out.matchWhole = wholeRaw ? 1 : 0;
    out.hasTrigger = true;
  }
  if (typeof rec.priority === 'number') {
    out.priority = clampKnowledgePriority(rec.priority);
    out.hasTrigger = true;
  }
  const scanRaw: number | undefined = rec.scanDepth !== undefined ? rec.scanDepth : rec.scan_depth;
  if (scanRaw !== undefined && typeof scanRaw === 'number') {
    const clamped: number = clampKnowledgeScan(scanRaw);
    out.scanDepth = clamped;
    out.scanClamped = clamped !== scanRaw;
    out.hasTrigger = true;
  }
  return out;
}

// 关键词字段归一（三形态容错）：数组 → 逐项 trim 去空后 join('、')（**方向与我们导出侧相反**：
// 那边按顿号逗号切、这边按顿号合，两边同一份 UI 约定）；字符串 → 原样（ST 的 key 单串形态与
// 手写件容错）；缺字段 → ''。★ 数组元素仍逐项过 typeof（手改件里塞数字/布尔不罕见）；入参
// 声明为联合类型而非 object——按 object 收窄在 ArkTS 会编译报 `trim does not exist on never`
function joinKeywordField(value: string[] | string | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (value === undefined) {
    return '';
  }
  // 运行期兜底：字段塞了对象等不可迭代值（手改件）⇒ 视为缺失返空串。类型面本支恒假（联合
  // 类型已收窄到 string[]），留着是因为 JSON 不守类型——真喂进来时 `for…of` 会抛 TypeError，
  // 抛出去被盘面域兜成英文原文，与「逐条说明」口径不符
  if (!Array.isArray(value)) {
    return '';
  }
  const parts: string[] = [];
  for (const item of value) {
    if (typeof item === 'string' && item.trim() !== '') {
      parts.push(item.trim());
    }
  }
  return parts.join('、');
}

// 首个关键词（ST 条目标题在 comment 为空时取它——RikkaHub ST 导入同口径）
function firstWorldKeyword(value: string[] | string | undefined): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (value === undefined) {
    return '';
  }
  // 运行期兜底（同 joinKeywordField）：不可迭代值视为缺失（ST 件里 key 塞对象时不留英文抛错面）
  if (!Array.isArray(value)) {
    return '';
  }
  for (const item of value) {
    if (typeof item === 'string' && item.trim() !== '') {
      return item.trim();
    }
  }
  return '';
}

// ST Map 键的排序位次（键是条目 uid 的数字串；非数字键排在所有数字键之后，同段按原序保持稳定
// ——确定性优先，禁依赖对象键的枚举序，同一文件在不同引擎上序会漂）
function worldEntryRank(key: string): number {
  const n: number = Number.parseInt(key, 10);
  return Number.isNaN(n) ? 2147483647 : n;
}

// 外部世界书附注（弹窗原文呈现）：①已停用条数（按计数）②已保留的触发设置（按计数——触发
// 精度四字段随文件导入）③未导入项（注入位置、注入角色与条目顺序——order 不映射 R13、
// position/role 无对应物不写）④扫描条数钳位结果（按计数，不静默）。③恒含（它解释的是
//「为什么导入后行为与源应用不同」）。★ 措辞守「面向用户文案写作规约」：分句用句号、无
// 冒号分号连环
function composeWorldNotice(disabled: number, triggerKept: number, scanClamped: number): string {
  const parts: string[] = [];
  if (disabled > 0) {
    parts.push('源文件里已停用的 ' + disabled + ' 条未导入');
  }
  if (triggerKept > 0) {
    parts.push('已保留 ' + triggerKept + ' 条的触发设置，含区分大小写、整词匹配、优先级与检查最近消息条数');
  }
  parts.push('注入位置、注入角色与条目顺序不随文件携带');
  if (scanClamped > 0) {
    parts.push(scanClamped + ' 条的检查最近消息条数超出支持范围，已调整到 1 到 20 条之间');
  }
  return parts.join('。') + '。';
}

function parseWorldBookFile(env: KnowledgeFileEnvelope, fallbackName: string): KnowledgeFileRead {
  const raw: object | null = env.data ?? null;
  const holder: KnowledgeWorldHolder =
    (raw !== null && typeof raw === 'object' ? raw : env as object) as KnowledgeWorldHolder;
  const entries: object | null = holder.entries ?? null;
  if (entries === null || typeof entries !== 'object') {
    // 拿不出条目清单 ⇒ 不是世界书件。★ 本拒**取代**早期的「错 type 拒」：判据由「type 是否
    // 为我方」推广为「能否拿出条目清单」——同信封不同实体的件（RikkaHub 的 mode_injection
    // 导出等）在此照拒，「不是知识库文件」的语义不弱化，只是不再拿 type 当唯一凭据
    return rejectKnowledgeFile('这个文件不是知识库文件，未导入。');
  }
  const own: string = (typeof holder.name === 'string' ? holder.name : '').trim();
  const picked: string = own !== '' ? own : fallbackName.trim();
  if (picked === '') {
    return rejectKnowledgeFile('文件里没有知识库名称，未导入。');
  }
  // 书名字长收口（见 capBookName）：外部件的 name 字段与文件名兜底都可能超长，两者同过一闸
  const name: string = capBookName(picked);
  if (Array.isArray(entries)) {
    return readWorldArray(name, entries as object[]);
  }
  return readWorldMap(name, entries as object);
}

// 数组形态（RikkaHub / Kelivo）：条目序 = 数组序；`enabled === false` 的条目不导入（如实计数
//——源应用里它本就不生效，搬过来反而会让用户以为它一直可用）。触发字段两套键名读取
//（驼峰 + 蛇形兜底手改件）
function readWorldArray(name: string, items: object[]): KnowledgeFileRead {
  const entries: KnowledgeFileEntry[] = [];
  let disabled: number = 0;
  let triggerKept: number = 0;
  let scanClamped: number = 0;
  for (const item of items) {
    const rec: KnowledgeWorldEntry | null = item as KnowledgeWorldEntry | null;
    // 数组里塞了 null（手改件）⇒ 落空条目交逐条分派按「无标题」说明；★ 禁在解析层抛
    //（`null.enabled` 会抛 TypeError，被盘面域兜成「文件读取失败：…」英文原文）
    if (rec === null) {
      const d: WorldTriggerRead = defaultFileTrigger();
      entries.push({ title: '', keywords: '', content: '', source: 'user',
        matchCase: d.matchCase, matchWhole: d.matchWhole, priority: d.priority,
        scanDepth: d.scanDepth });
      continue;
    }
    if (rec.enabled === false) {
      disabled++;
      continue;
    }
    const trigger: WorldTriggerRead = readWorldTrigger(rec);
    if (trigger.hasTrigger) {
      triggerKept++;
    }
    if (trigger.scanClamped) {
      scanClamped++;
    }
    entries.push({
      title: typeof rec.name === 'string' ? rec.name : '',
      keywords: joinKeywordField(rec.keywords),
      content: typeof rec.content === 'string' ? rec.content : '',
      source: 'user',
      matchCase: trigger.matchCase, matchWhole: trigger.matchWhole,
      priority: trigger.priority, scanDepth: trigger.scanDepth
    });
  }
  return { ok: true, name: name, entries: entries, error: '',
    notice: composeWorldNotice(disabled, triggerKept, scanClamped) };
}

// Map 形态（SillyTavern World Info v2）：标题 = comment，空则取首个关键词；停用标是 `disable`
//（与竞品 `enabled` 相反极——两家各一极，此处是 ST 侧）；键序按 worldEntryRank。ST 的
// scanDepth 常为 null（继承书级全局值），null 视为缺失落默认 8；order 与 depth 有意不读，
// 见 KnowledgeWorldEntry 注释 R13
function readWorldMap(name: string, map: object): KnowledgeFileRead {
  const rec: Record<string, object> = map as Record<string, object>;
  const keys: string[] = Object.keys(rec);
  const order: number[] = [];
  for (let i: number = 0; i < keys.length; i++) {
    order.push(i);
  }
  order.sort((a: number, b: number): number => {
    const ra: number = worldEntryRank(keys[a]);
    const rb: number = worldEntryRank(keys[b]);
    return ra !== rb ? ra - rb : a - b;
  });
  const entries: KnowledgeFileEntry[] = [];
  let disabled: number = 0;
  let triggerKept: number = 0;
  let scanClamped: number = 0;
  for (const idx of order) {
    // 退化项（Map 里塞了 null / 非对象）不特判字段：落空条目 ⇒ 走逐条分派的「无标题」说明
    //（与自家格式「条目级问题不在解析层升级成整份拒」同一口径，也避开对接口类型做 typeof
    // 收窄——ArkTS 下会落 never）。★ 但 **null 必须先过闸**：「字段读为 undefined」只对非
    // null 的值成立，`null.disable` 会抛 TypeError（被盘面域兜成英文原文）
    const item: KnowledgeWorldEntry | null = rec[keys[idx]] as KnowledgeWorldEntry | null;
    if (item === null) {
      const d: WorldTriggerRead = defaultFileTrigger();
      entries.push({ title: '', keywords: '', content: '', source: 'user',
        matchCase: d.matchCase, matchWhole: d.matchWhole, priority: d.priority,
        scanDepth: d.scanDepth });
      continue;
    }
    if (item.disable === true) {
      disabled++;
      continue;
    }
    const comment: string = typeof item.comment === 'string' ? item.comment.trim() : '';
    const trigger: WorldTriggerRead = readWorldTrigger(item);
    if (trigger.hasTrigger) {
      triggerKept++;
    }
    if (trigger.scanClamped) {
      scanClamped++;
    }
    entries.push({
      title: comment !== '' ? comment : firstWorldKeyword(item.key),
      keywords: joinKeywordField(item.key),
      content: typeof item.content === 'string' ? item.content : '',
      source: 'user',
      matchCase: trigger.matchCase, matchWhole: trigger.matchWhole,
      priority: trigger.priority, scanDepth: trigger.scanDepth
    });
  }
  return { ok: true, name: name, entries: entries, error: '',
    notice: composeWorldNotice(disabled, triggerKept, scanClamped) };
}

// 定长截断的安全切点（代理对防护——emoji 等增补平面字符占两码元，硬切会留孤立代理字符，
// 它进文件名是非法名、进请求体是非法 Unicode；照 SkillText.safeCutIndex 口径本地一份——
// 依赖纪律不引技能域〔唯一 import 源 = KnowledgeText〕，两域同形不同源既有纪律）
function safeKnowledgeCut(text: string, max: number): number {
  if (text.length <= max) {
    return text.length;
  }
  const last: number = text.charCodeAt(max - 1);
  return (last >= 0xD800 && last <= 0xDBFF) ? max - 1 : max;
}

function clipImportText(text: string, max: number): string {
  return text.length > max ? text.substring(0, safeKnowledgeCut(text, max)) : text;
}

// 逐条分派（真值表）：三类「跳过」与一类「截断」的分野——跳过 = 原样保不住的，宁可不导
//（标题是检索权重最高字段、正文是原文，截断即悄悄改命中行为与内容）；截断 = 辅助字段且已
// 明示。重名判定复用 knowledgeTitleTaken（导入目标恒为新库 ⇒ 只需文件内自查：与已收条目
// 撞名即跳过）
export function screenKnowledgeEntries(raw: KnowledgeFileEntry[]): KnowledgeScreenResult {
  const importable: KnowledgeFileEntry[] = [];
  const skipped: string[] = [];
  const accepted: KnowledgeEntryItem[] = []; // 文件内前序已收集（合成 id 防自撞语义误用）
  let clippedKeywords: number = 0;
  for (let i: number = 0; i < raw.length; i++) {
    const title: string = raw[i].title.trim();
    if (title === '') {
      skipped.push('第 ' + (i + 1) + ' 条（无标题）：条目名为空');
      continue;
    }
    if (title.length > KNOWLEDGE_TITLE_MAX) {
      skipped.push('『' + clipImportText(title, KNOWLEDGE_IMPORT_NAME_MAX) +
        '…』：条目名超过 ' + KNOWLEDGE_TITLE_MAX + ' 字');
      continue;
    }
    if (raw[i].content.length > KNOWLEDGE_CONTENT_MAX) {
      skipped.push('『' + title + '』：正文 ' + raw[i].content.length + ' 字，超过 ' +
        KNOWLEDGE_CONTENT_MAX + ' 字上限');
      continue;
    }
    if (knowledgeTitleTaken(accepted, title, '')) {
      skipped.push('『' + title + '』：文件里有重名条目');
      continue;
    }
    let keywords: string = raw[i].keywords;
    if (keywords.length > KNOWLEDGE_KEYWORDS_MAX) {
      keywords = keywords.substring(0, safeKnowledgeCut(keywords, KNOWLEDGE_KEYWORDS_MAX));
      clippedKeywords++;
    }
    importable.push({ title: title, keywords: keywords, content: raw[i].content,
      source: raw[i].source === 'assistant' ? 'assistant' : 'user',
      // 触发精度四字段透传（2026-10-26 触发精度笔）——解析层已归一，这里只搬运
      matchCase: raw[i].matchCase, matchWhole: raw[i].matchWhole,
      priority: raw[i].priority, scanDepth: raw[i].scanDepth });
    // 重名自查的合成条目：注入四字段落建表默认（字面量纯函数域自持，禁引 RequestInject 常量
    //〔依赖纪律〕；importable 侧不带四字段 = 真实落库经 KnowledgeEntryInput 可缺省默认，见
    // KnowledgeDb）；触发精度四字段照搬（重名判定不消费，形态完整防 undefined 进比较路径）
    accepted.push({ id: 'f' + i, bookId: '', title: title, keywords: keywords,
      content: raw[i].content, createdAt: 0, sortOrder: 0,
      injectRole: 'system', injectPosition: 'head', injectDepth: 0, enabled: 1,
      matchCase: raw[i].matchCase, matchWhole: raw[i].matchWhole,
      priority: raw[i].priority, scanDepth: raw[i].scanDepth });
  }
  return { importable: importable, skipped: skipped, clippedKeywords: clippedKeywords };
}

// 导出文件名清洗（非法字符 → _、截 40、去首尾点与空格、空名与纯点段兜底「知识库」；照
// SkillText.skillPackDirName 形制加首尾点剥离）。★ 单源：导出侧文件名与导入侧失败提示共用，
// 禁两处各写一套
export function knowledgeFileName(bookName: string): string {
  const safe: string = bookName.replace(/[\\/:*?"<>|]/g, '_').replace(/^[.\s]+|[.\s]+$/g, '');
  const cut: string = safe.substring(0, safeKnowledgeCut(safe, 40));
  return cut === '' ? '知识库' : cut;
}

// ── 审阅弹窗文案（§3.3）──
// ★ 结构上界是硬要求（照 SkillText.composeBatchImportPreview——弹窗 message 是无上限 Text，
// 长清单会把「导入 / 取消」两键顶出屏，技能笔真机预演实锤过一次）：条目名封顶 8 项（余下
// 「等 N 条」）、未导入封顶 3 条（余下计数）、每项截断。封顶档与技能域同值但**各域自持**
// （依赖纪律不引技能域，同款纪律同款理由——2026-10-06 拆分随形）
const KNOWLEDGE_IMPORT_LIST_MAX: number = 8;
const KNOWLEDGE_IMPORT_SKIP_LIST_MAX: number = 3;
const KNOWLEDGE_IMPORT_NAME_MAX: number = 20;
const KNOWLEDGE_IMPORT_WARN_MAX: number = 40;
const KNOWLEDGE_IMPORT_WARN_NAME_MAX: number = 20;
// 安全提示句（导入弹窗恒末句——条目会进检索结果发给模型，导入前用户该过目）
const KNOWLEDGE_IMPORT_SAFETY_LINE: string =
  '条目内容会在助手检索知识库时发给模型，请确认内容可信后再导入。';

// 导入说明单条裁剪（名段压窄、原因保留——照 SkillText.clipImportWarning 同款两段式）
function clipKnowledgeWarn(warning: string): string {
  const sep: number = warning.indexOf('：');
  if (sep < 0) {
    return clipImportText(warning, KNOWLEDGE_IMPORT_WARN_MAX);
  }
  const name: string = warning.substring(0, sep);
  const reason: string = warning.substring(sep + 1);
  const shown: string = name.length > KNOWLEDGE_IMPORT_WARN_NAME_MAX ?
    clipImportText(name, KNOWLEDGE_IMPORT_WARN_NAME_MAX) : name;
  return clipImportText(shown + '：' + reason, KNOWLEDGE_IMPORT_WARN_MAX);
}

// 审阅弹窗文案：书名 + 条数 / 条目名清单 / 未导入逐条 / 截断计数 / **外部件附注** / 安全行恒末。
// notice 来自 parseKnowledgeBook（外部世界书链恒非空、自家格式恒空），**原样呈现**——本函数不做
// 取舍判断，只负责把它排在「截断计数」之后、安全行之前（安全行恒末是结构契约，钉在断言里）
export function composeKnowledgeImportPreview(name: string,
  screen: KnowledgeScreenResult, notice: string = ''): string {
  const parts: string[] = [];
  const total: number = screen.importable.length;
  const limit: number = Math.min(KNOWLEDGE_IMPORT_LIST_MAX, total);
  const lines: string[] = [];
  for (let i: number = 0; i < limit; i++) {
    lines.push((i + 1).toString() + '. ' + clipImportText(screen.importable[i].title,
      KNOWLEDGE_IMPORT_NAME_MAX));
  }
  if (total > limit) {
    lines[limit - 1] = lines[limit - 1] + ' 等 ' + total + ' 条';
  }
  parts.push('将新建知识库「' + name + '」，导入 ' + total + ' 条条目\n' + lines.join('\n'));
  if (screen.skipped.length > 0) {
    const shown: string[] = [];
    const keep: number = Math.min(KNOWLEDGE_IMPORT_SKIP_LIST_MAX, screen.skipped.length);
    for (let i: number = 0; i < keep; i++) {
      shown.push(clipKnowledgeWarn(screen.skipped[i]));
    }
    const more: string = screen.skipped.length > keep ?
      ' 等 ' + screen.skipped.length + ' 项' : '';
    parts.push(screen.skipped.length + ' 条未导入：\n- ' + shown.join('\n- ') + more);
  }
  if (screen.clippedKeywords > 0) {
    parts.push(screen.clippedKeywords + ' 条的关键词过长已截断');
  }
  if (notice !== '') {
    parts.push(notice);
  }
  parts.push(KNOWLEDGE_IMPORT_SAFETY_LINE);
  return parts.join('\n\n');
}
