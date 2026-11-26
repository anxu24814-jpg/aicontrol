// 知识库关键词触发·匹配域：发送前对最近对话文本做关键词匹配与注入块拼装的全部纯逻辑。
// **零 import 纯函数约束**（照 SkillText / MemoryText / KnowledgeText 先例——断言脚本复制
// 本文件为 .ts 直跑，是本域可测性的根基；IO 编排〔DB 读写、开关判定、条目映射〕在
// ChatSnapshotCtrl.buildKnowledgeBlock，不在本域）。
// ★ 匹配域与字段校验域分件：值域常量与归一函数在 KnowledgeText（clampKnowledgePriority /
// clampKnowledgeScan / KNOWLEDGE_* 常量），本件不持任何默认值常量——入参已由调用方归一，
// 域内只做下界防御（Math.max(1, n)）；禁把匹配代码并回。
// 与工具化检索（search_knowledge）的关系（拍板）：**并存**——工具化 = 模型主动按需查，
// 本域 = 命中必进（客户端本地匹配，不经模型）；两路互不感知互不替代。
// 拍板不做：Sticky / Cooldown / Delay / 递归 / 概率命中；跨块去重（知识与记忆不去重）；
// 向量化。多语言失效如实告知（帮助条目）：大小写归一只对拉丁字母有意义，全角/半角、简繁
// 等差异不归一；整词匹配只对纯 ASCII 单词关键词生效，中文键回落子串（中文无词边界，套 \b
// 恒不命中是静默失联，回落子串可感知）。

// ── 常量定稿（注入预算 8 条 / 2000 字——2000 与记忆注入分账同额；真机实测不当可回登记
//    改值）──
// 注入条数上限（两通道共用：系统块按排序键截停，深度组按应用次序截停——见
// selectKnowledgeDepthHits）
export const KNOWLEDGE_INJECT_MAX_COUNT: number = 8;
// 注入字符预算（两通道共用：系统块含头句与「- 标题」行与正文；深度组只按各条 content
// 长度计——深度注入不带标题行）
export const KNOWLEDGE_INJECT_MAX_CHARS: number = 2000;
// 系统块头句（供参考语义——知识条目是用户手写资产非蒸馏快照，与记忆块头句语义刻意不同）
export const KNOWLEDGE_BLOCK_HEADER: string = '以下是从知识库命中的条目，供参考。';

// 匹配器本地条目形状（自持最小声明以保零 import 直跑；keywords 由调用方用
// KnowledgeImportText.splitKnowledgeKeywords 拆好传入；bookIndex = 调用方按启用书序赋的下标
// ——排序第二键，禁依赖 SQL 返回序做书序）。四字段：matchCase / matchWhole（0/1 行层布尔，
// === 1 视为真）；priority（0~9999，排序第一键降序、全局跨书，同值回落后四键 = 存量顺序零
// 变化）；scanDepth（1~20，已由调用方 clampKnowledgeScan 归一）
export interface KnowledgeMatchEntry {
  id: string;
  title: string;
  keywords: string[];
  content: string;
  bookIndex: number;
  sortOrder: number;
  createdAt: number;
  injectRole: string;
  injectPosition: string;
  injectDepth: number;
  matchCase: number;
  matchWhole: number;
  priority: number;
  scanDepth: number;
}

// 扫描窗口分桶缓存：同一 depth 的窗口文本与 lowercase 版本每轮只算一次——raw/lower 两份
// 同产（**禁在逐条循环里调 toLowerCase**——窗口文本是大头，转换次数必须钉在桶级）
interface KnowledgeScanContext {
  raw: string;
  lower: string;
}

// 纯 ASCII 单词判据：词边界只对 [A-Za-z0-9_]+ 成立；含任何非 ASCII 字符（中文/全角标点/
// 带空格短语）的关键词**回落子串**——中文没有词边界，套 \b 恒不命中
function isAsciiWordChar(code: number): boolean {
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
    code === 95;
}

function isPureAsciiWord(word: string): boolean {
  if (word.length === 0) {
    return false;
  }
  for (let i: number = 0; i < word.length; i++) {
    if (!isAsciiWordChar(word.charCodeAt(i))) {
      return false;
    }
  }
  return true;
}

// 整词命中（手写双指针扫描，**禁 \b 与 RegExp**——ArkTS \b 只认 ASCII word char 且每次匹配
// 现造正则有开销）：命中位置的左右相邻字符都不是 [A-Za-z0-9_] 即整词命中；串首、串尾视为
// 边界
function containsWholeWord(haystack: string, needle: string): boolean {
  let from: number = 0;
  while (from <= haystack.length - needle.length) {
    const at: number = haystack.indexOf(needle, from);
    if (at < 0) {
      return false;
    }
    const leftOk: boolean = at === 0 || !isAsciiWordChar(haystack.charCodeAt(at - 1));
    const rightEnd: number = at + needle.length;
    const rightOk: boolean = rightEnd === haystack.length ||
      !isAsciiWordChar(haystack.charCodeAt(rightEnd));
    if (leftOk && rightOk) {
      return true;
    }
    from = at + 1;
  }
  return false;
}

// 单词命中（matchWhole 消费面）：纯 ASCII 单词 → 词边界判定；否则回落子串
function wordHits(haystack: string, needle: string, whole: boolean): boolean {
  if (needle === '') {
    return false;
  }
  if (whole && isPureAsciiWord(needle)) {
    return containsWholeWord(haystack, needle);
  }
  return haystack.indexOf(needle) >= 0;
}

// 关键词命中 + 五键排序（纯函数不改入参）：
// · 签名 = 「历史 + 草稿」原始序列，窗口截取域内完成（条目各自按 scanDepth 取不同窗口，
//   故域内分桶，排序仍是单次全局五键）。窗口口径：draftText 非空恒为窗口最新一条（占 1
//   名额），historyTexts 取尾部 n-1 条；draft 为空（重试轮/纯附件发送）时窗口 = 历史尾部
//   n-1 条；historyTexts 时间升序（调用方按消息序传入且已滤空串），条数有界（≤20）。
// · 大小写：matchCase=0 两边 lower，=1 原串比较不归一。整词见 wordHits。
// · 排序五键：priority 降序 → bookIndex 升 → sortOrder 升 → createdAt 升 → id 升
//  （同值回落后四键 = 与升级前完全一致；**禁依赖 Map/Set 遍历序与 SQL 返回序**——确定性
//   由显式五键保证）。
// · 空词表 = 不命中（空关键词条目不自动注入，仍可检索）；空窗口（历史与草稿全空）= 不命中。
export function matchKnowledgeEntries(candidates: KnowledgeMatchEntry[],
  historyTexts: string[], draftText: string): KnowledgeMatchEntry[] {
  if (candidates.length === 0 || (historyTexts.length === 0 && draftText === '')) {
    return [];
  }
  // 分桶缓存：键 = scanDepth；条目窗口 = 历史尾部 n-1 条 + draft（非空时）。n 入参下界
  // 再钳一次（Math.max(1, n)——值域归一在调用方，域内不重复定义上限）
  const buckets: Map<number, KnowledgeScanContext> = new Map<number, KnowledgeScanContext>();
  const contextFor = (n: number): KnowledgeScanContext => {
    const depth: number = Math.max(1, n);
    const cached: KnowledgeScanContext | undefined = buckets.get(depth);
    if (cached !== undefined) {
      return cached;
    }
    const window: string[] = [];
    const quota: number = depth - 1;
    for (let i: number = historyTexts.length - 1; i >= 0 && window.length < quota; i--) {
      window.push(historyTexts[i]);
    }
    // 尾部收集是倒序 push，翻回老→新；draft 非空恒居末
    window.reverse();
    if (draftText !== '') {
      window.push(draftText);
    }
    const raw: string = window.join('\n');
    const ctx: KnowledgeScanContext = { raw: raw, lower: raw.toLowerCase() };
    buckets.set(depth, ctx);
    return ctx;
  };
  const hits: KnowledgeMatchEntry[] = [];
  for (const entry of candidates) {
    if (entry.keywords.length === 0) {
      continue; // 空词表 = 不命中
    }
    const ctx: KnowledgeScanContext = contextFor(entry.scanDepth);
    const haystack: string = entry.matchCase === 1 ? ctx.raw : ctx.lower;
    let matched: boolean = false;
    for (const word of entry.keywords) {
      // 关键词侧转换次数 = 条目关键词数（不可避免，量级可忽略——方案 §4.1）
      const needle: string = entry.matchCase === 1 ? word : word.toLowerCase();
      if (wordHits(haystack, needle, entry.matchWhole === 1)) {
        matched = true;
        break;
      }
    }
    if (matched) {
      hits.push(entry);
    }
  }
  hits.sort(compareMatchEntries);
  return hits;
}

// 五键比较器（priority 降序在前 = 全局跨书注入优先级；后四键 = 旧四键原序，同 priority 时
// 行为与升级前完全一致；id 字典序为确定性兜底）
function compareMatchEntries(a: KnowledgeMatchEntry, b: KnowledgeMatchEntry): number {
  if (a.priority !== b.priority) {
    return b.priority - a.priority;
  }
  if (a.bookIndex !== b.bookIndex) {
    return a.bookIndex - b.bookIndex;
  }
  if (a.sortOrder !== b.sortOrder) {
    return a.sortOrder - b.sortOrder;
  }
  if (a.createdAt !== b.createdAt) {
    return a.createdAt - b.createdAt;
  }
  if (a.id < b.id) {
    return -1;
  }
  if (a.id > b.id) {
    return 1;
  }
  return 0;
}

// 系统位注入块拼装（照 MemoryText.composeMemoryBlock 同款：头句预留 + 贪心双封顶），
// 逐条 = 「- 条目标题」行 + 正文（正文原样不截断——拍板「不截断单条」）；条数满或加入将
// 超字符预算即止；★ 至少保 1 条（字符预算极小时防 0 条死块，不截断不丢弃）；零命中返回
// ''（= 不注入）。确定性：同一命中序列 + 同一预算 → 输出逐字节一致（贪心按入参序直出，
// 入参序 = matchKnowledgeEntries 产出的五键序）。
// ★ 超限省略补尾注「（另有 N 条相关知识未展开）」。两条边界：①**只报数、不承诺可检索**
// ——search_knowledge 是 defaultEnabled: false，点名或暗示「可检索」会诱导未启用该工具的
// 助手空转一轮；②**尾注不计入 maxChars**——「未超限逐字节不变」判据要求贪心逻辑零变化
//（预留尾注位会让恰压线装下的存量形态提前截停 = 行为回归），越线量 = 尾注一行有界常数，
// 系统块下游无 8192 类二次截断器，无截断风险
export function composeKnowledgeSystemBlock(hits: KnowledgeMatchEntry[], maxCount: number,
  maxChars: number): string {
  if (hits.length === 0) {
    return '';
  }
  const selected: KnowledgeMatchEntry[] = [];
  let used: number = KNOWLEDGE_BLOCK_HEADER.length;
  for (const entry of hits) {
    if (selected.length >= maxCount) {
      break;
    }
    const cost: number = 2 + entry.title.length + 1 + entry.content.length; // '- '+title+'\n'+content
    if (used + 1 + cost > maxChars && selected.length > 0) {
      break; // 加入将超预算即止（首条豁免——保 1 条，见上注）
    }
    selected.push(entry);
    used += 1 + cost;
  }
  if (selected.length === 0) {
    return '';
  }
  const lines: string[] = [];
  for (const entry of selected) {
    lines.push('- ' + entry.title);
    lines.push(entry.content);
  }
  let block: string = KNOWLEDGE_BLOCK_HEADER + '\n' + lines.join('\n');
  const omitted: number = hits.length - selected.length;
  if (omitted > 0) {
    block += '\n（另有 ' + omitted + ' 条相关知识未展开）';
  }
  return block;
}

// 深度组预算装载（第二条注入通道同样封顶——非 system 身份命中逐条进目标消息，不封顶则
// 单轮注入量随命中数无上界且用户无法预知）：按入参序贪心装入（入参序 = 应用次序，深度降
// 序、同深度按命中序——ChatSnapshotCtrl 排好后传入，截停次序即应用次序），条数满或加入将
// 超字符预算即止，不截断单条；★ 至少保 1 条。字符口径 = 各条 content 长度之和（深度注入
// 只带正文不带标题行，与系统块「- 标题 + 正文」记账不同源）；合并分隔符（'\n\n'）量级可
// 忽略不计。零命中返回空数组；纯函数不改入参
export function selectKnowledgeDepthHits(hits: KnowledgeMatchEntry[], maxCount: number,
  maxChars: number): KnowledgeMatchEntry[] {
  if (hits.length === 0) {
    return [];
  }
  const selected: KnowledgeMatchEntry[] = [];
  let used: number = 0;
  for (const entry of hits) {
    if (selected.length >= maxCount) {
      break;
    }
    const cost: number = entry.content.length;
    if (used + cost > maxChars && selected.length > 0) {
      break; // 加入将超预算即止（首条豁免——保 1 条，见上注）
    }
    selected.push(entry);
    used += cost;
  }
  return selected;
}
