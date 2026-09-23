// 记忆文本纯函数域（2026-09-08 记忆域，任务书-记忆域-20260908 §2.3/§2.4/§2.7）：
// 提取结果的解析/清洗/敏感过滤/去重 + 注入块拼装/双封顶 + 蒸馏输入拼接 + 提取带去重
// 清单——零 import 纯函数约束（scripts/sse-assert.mjs 复制本文件为 .ts 直跑，
// RequestInject 同款范式；IO 编排〔DB 读写/网络请求〕在 MemoryDb/MemoryGen，不在本域）。
// ★ 2026-09-11 增「记忆优化」节（方案-记忆整理优化-20260911 §6.4/§6.5 二期）：优化模型
// 建议 → 可执行改动计划的全部纯逻辑（解析 / 白名单校验 / 内容校验 / 改动量闸门 + 确认
// 摘要与结果文案单源）；写库编排在 MemoryDb（事务批量原语）与 MemoryOpt（请求链）。
// 输入输出口径：
// · parseMemoryLines：模型原始输出 → 干净条目数组（编号前缀剥离/空行与「无」丢弃/
//   单条截断/敏感命中丢弃/归一化去重/条数上限）
// · selectMemoryEntries：条数/字符双封顶选取（注入块与去重清单同源）
// · composeMemoryBlock：库内条目（卡片序）→ 注入用记忆块文本（对象入参；
//   选取与渲染均按入参序 = 卡片序（用户排定的优先级），直出不再重排；超出加省略尾注；
//   '' = 不注入）
// · composeMemoryList：库内条目 → 提取请求的去重清单文本（先丢敏感命中条目，选取与
//   注入块同源，无头无尾注；'' = 调用方不拼段）
// · buildMemoryContent：会话消息 → 蒸馏输入（过滤/单条截断/压空白；超总量上限头尾
//   都保——头部常含长期声明，尾部信息密度高）
// ★ 2026-09-13 增「记忆检索」节（方案-记忆按需读取-20260913 §2.4）：search_memory 工具的
// 全部纯逻辑（query 切词 / 关键词打分 / 相关度排序 / 双封顶选取 / 结果文本拼装）——零
// 时钟依赖（新近度 = updatedAt 字段排序，非相对当前时间的衰减），断言脚本复制直跑复算；
// 执行器与读库编排在 MemoryGen（IO 归口）。
// ★ 2026-09-13 增「记忆管理」节（任务书-记忆管理工具-20260913）：manage_memory 工具
// （第 15 件，控制台助手管理长期记忆库）的全部纯逻辑（参数校验 / 原文定位 / 分页收窄 /
// 回执拼装）——同零 import 约束供断言复制直跑；执行器与 DB 编排在 ToolMemoryManage /
// MemoryDb（IO 归口）。

// 单条记忆字数上限（建表注释同值；解析侧超长截断、记忆编辑页 maxLength 同源）
export const MEMORY_CONTENT_MAX: number = 500;

// 敏感内容关键词表（2026-09-08 记忆域 §2.6：自动提取条目命中即丢弃 + hilog 留痕；
// 手动添加不拦截——用户自己的输入自己负责，记忆页说明行提示）。匹配 = 小写化子串
//（中文 toLowerCase 无变化，英文关键词大小写通吃）；regex 段拦裸数字形态（手机号/
// 身份证/长卡号——关键词拦不住纯数字输出）
const SENSITIVE_WORDS: string[] = ['密码', '口令', '密钥', 'apikey', 'api key', 'api_key',
  'secret', 'password', '身份证', '银行卡', '卡号', '住址', '手机号', '电话号码'];
const SENSITIVE_REGEXPS: RegExp[] = [/1[3-9]\d{9}/, /\d{17}[\dxX]/, /\d{16,19}/];

// 命中敏感模式返回命中描述（hilog 留痕用），'' = 干净
export function hitSensitiveContent(text: string): string {
  const lower: string = text.toLowerCase();
  for (const word of SENSITIVE_WORDS) {
    if (lower.includes(word)) {
      return word;
    }
  }
  for (const re of SENSITIVE_REGEXPS) {
    if (re.test(text)) {
      return '数字串(' + re.source + ')';
    }
  }
  return '';
}

// 去重归一键（拍板「克制」口径：只做压空白 + trim——不做全角半角归一；首尾标点差异
// 视为不同条目，代价 = 偶发近似重复条，200 条上限兜底）
export function normalizeMemoryKey(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

// 来源标注 → 副行文案（三态单源；★ 2026-09-22 记忆导入笔）：值域 = memories.source 列
// （建表默认 'auto'，无 CHECK 约束，故本函数是唯一映射点——未知值（旧版/脏值）回
// 「自动整理」= 建表默认语义，与三态前行为逐字一致）。
// ★ **全部**消费点必须同走本函数（库管理页行卡 / 助手记忆页只读行卡 / 快照详情页只读行卡
// ——2026-09-22 记忆导入笔自检轮补第三处：原注释只数了两处、第三处漏改，导入条目在快照页被
// 标成「自动整理」= 假话，正是本函数要消灭的形态；故枚举只作提示，真正的守法是断言侧的单源
// 唯一性钉 + 逐处接线钉——新增任何读 source 上屏的行卡，先 grep 本函数名）。单一来源后
// 加值只改这里
export function memorySourceLabel(source: string): string {
  if (source === 'manual') {
    return '手动添加';
  }
  if (source === 'import') {
    return '从外部导入';
  }
  return '自动整理';
}

// 单行清洗：去编号前缀（「1.」「2、」「3)」「-」「•」「·」「*」类——模型逐条输出常见
// 形态）→ 压空白 → trim；'' = 空行
function cleanMemoryLine(line: string): string {
  return line.replace(/^\s*(?:\d+\s*[.、)）]|[•·\-—*]\s*)+/, '')
    .replace(/\s+/g, ' ').trim();
}

// 「无」判等（模型无内容时按提示词输出「无」——尾部可能带标点变体；stripped 已是
// cleanMemoryLine 产物，只剥首尾标点比对）
function isNoneAnswer(stripped: string): boolean {
  const bare: string = stripped.replace(/^[，。、,.！!？?\s]+/, '').replace(/[，。、,.！!？?\s]+$/, '');
  return bare === '无' || bare === '';
}

// 提取结果解析：raw = 模型原始输出全文；maxCount = 条数上限（生成链传 5）；existingKeys =
// 库内既有条目的 normalizeMemoryKey 集（跨次去重）。流程 = 逐行清洗 → 丢空行与「无」→
// 单条截 500 加 … → 敏感命中丢弃 → 归一化去重（本次内 + 库内）→ 截 maxCount
export function parseMemoryLines(raw: string, maxCount: number, existingKeys: string[]): string[] {
  const seen: Set<string> = new Set<string>();
  for (const key of existingKeys) {
    if (key !== '') {
      seen.add(key);
    }
  }
  const lines: string[] = raw.split('\n');
  const out: string[] = [];
  for (const line of lines) {
    if (out.length >= maxCount) {
      break;
    }
    const cleaned: string = cleanMemoryLine(line);
    if (isNoneAnswer(cleaned)) {
      continue;
    }
    const content: string = cleaned.length > MEMORY_CONTENT_MAX ?
      cleaned.substring(0, MEMORY_CONTENT_MAX) + '…' : cleaned;
    // 敏感命中整条丢弃（调用方无法在此 hilog——零 import 域，留痕在 MemoryGen 侧对
    // 返回值差集记录）
    if (hitSensitiveContent(content) !== '') {
      continue;
    }
    const key: string = normalizeMemoryKey(content);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(content);
  }
  return out;
}

// 注入块头（供参考语义 + 过时声明——记忆是蒸馏快照非实时真相，让模型以用户当前说法
// 为准，防旧记忆压过新指令）
export const MEMORY_BLOCK_HEADER: string =
  '以下是从过往对话沉淀的长期记忆，供参考。可能过时，以用户当前说法为准。';
// 双封顶截断尾注
const MEMORY_BLOCK_OMIT_NOTE: string = '（更多记忆已省略）';

// 记忆条目（注入块与去重清单共用；入参序 = 调用方 queryMemories 的卡片序〔sortOrder/
// createdAt/content 三键〕）
export interface MemoryEntryItem {
  content: string;
  createdAt: number;
}

// 双封顶选取（注入块与去重清单同源——同一贪心，仅 reservedChars 不同）：条数 maxCount
// 与字符 maxChars 双封顶，超出的整条不进；至少保 1 条（字符预算极小时防 0 条死块）；
// reservedChars = 调用方预留开销（注入块传头行长度，去重清单传 0）。
// ★ 卡序口径（2026-09-12 记忆自定义注入顺序笔）：入参序 = 卡片序（用户排定的优先级），
// 超限时保卡序前 N 条（顶部 30 条 = 注入窗口）。
// ★ 泛型化（2026-09-11 记忆优化笔）：优化输入侧需要带 id 的条目（序号 → 行的映射要能落库），
// 而本函数只读 content——加类型参数 T 让调用方拿回自己的元素类型，避免为此复制一份贪心
// （P2-4：同一贪心第二份拷贝 = 两处漂移面）。T 约束 MemoryEntryItem 即保证 content/createdAt
// 两字段在场，既有三处调用（注入块 / 去重清单）类型推断后行为逐字不变。
export function selectMemoryEntries<T extends MemoryEntryItem>(items: T[], maxCount: number,
  maxChars: number, reservedChars: number): T[] {
  const selected: T[] = [];
  let used: number = reservedChars;
  for (const item of items) {
    if (selected.length >= maxCount) {
      break;
    }
    const line: string = '- ' + item.content;
    if (used + 1 + line.length > maxChars && selected.length > 0) {
      break;
    }
    selected.push(item);
    used += 1 + line.length;
  }
  return selected;
}

// 注入块拼装：items = 库内条目（卡片序——调用方 queryMemories 三键保证）；选取与渲染均按
// 入参序直出（★ 2026-09-12 记忆自定义注入顺序笔：删原 compareMemoryOrder 的 createdAt
// 升序重排——卡序即注入序，用户排定什么顺序就注入什么顺序；「同 DB 状态恒同块字符串」
// 目标由 queryMemories 三键确定性 + 渲染直出等价承接，前缀缓存契约不破）；条数/字符双封顶，
// 超出的整条不进 + 尾注；items 空 → ''（= 不注入）
export function composeMemoryBlock(items: MemoryEntryItem[], maxCount: number,
  maxChars: number): string {
  if (items.length === 0) {
    return '';
  }
  const selected: MemoryEntryItem[] =
    selectMemoryEntries(items, maxCount, maxChars, MEMORY_BLOCK_HEADER.length);
  if (selected.length === 0) {
    return '';
  }
  const lines: string[] = [];
  for (const item of selected) {
    lines.push('- ' + item.content);
  }
  let block: string = MEMORY_BLOCK_HEADER + '\n' + lines.join('\n');
  if (selected.length < items.length) {
    block += '\n' + MEMORY_BLOCK_OMIT_NOTE;
  }
  return block;
}

// 去重清单文本（提取请求用，P1-1）：先丢敏感命中条目（清单随提取请求发到记忆提取模型
// 服务商，可能与聊天服务商不同家——手动条目不过敏感过滤的既定口径下，此处守卫消除新增
// 外发面）→ 与注入块同源选取（reservedChars = 0，无头行开销）→ '- 内容' 逐行，无头无
// 尾注；空入/全丢空/全截空 = ''（调用方不拼段）
export function composeMemoryList(items: MemoryEntryItem[], maxCount: number,
  maxChars: number): string {
  if (items.length === 0) {
    return '';
  }
  const safe: MemoryEntryItem[] = [];
  for (const item of items) {
    if (hitSensitiveContent(item.content) === '') {
      safe.push(item);
    }
  }
  const selected: MemoryEntryItem[] = selectMemoryEntries(safe, maxCount, maxChars, 0);
  if (selected.length === 0) {
    return '';
  }
  const lines: string[] = [];
  for (const item of selected) {
    lines.push('- ' + item.content);
  }
  return lines.join('\n');
}

// 会话消息（蒸馏输入；MemoryGen 从 ChatDb.MessageRow 取用——零 import 域不引 DB 类型）
export interface MemoryMessageRow {
  role: string;
  content: string;
}

// 蒸馏输入总量上限（迁自 MemoryGen，同值 6000）
export const MEMORY_INPUT_TOTAL_LIMIT: number = 6000;
// 超限时的头部保留量（头部常含身份/长期声明，尾部信息密度高——两头都保）
const MEMORY_INPUT_HEAD_LIMIT: number = 2000;
// 超限省略标记
const MEMORY_INPUT_ELISION: string = '\n…\n';

// 蒸馏输入拼接（MemoryGen 原 buildMemoryContent 迁入 + 截断改头尾都保）：user/assistant
// 非空消息，每条截 500 加 …，'role: 内容' 逐行；总字符超 6000 = 头 2000 + 省略标记 + 尾
// 补足（总长恒 ≤ 6000）；消息不足 2 条 → ''（单条无法构成「对话沉淀」语义）
export function buildMemoryContent(messages: MemoryMessageRow[]): string {
  const picked: MemoryMessageRow[] = [];
  let count: number = 0;
  for (const m of messages) {
    if ((m.role === 'user' || m.role === 'assistant') && m.content !== '') {
      picked.push(m);
      count++;
    }
  }
  if (count < 2) {
    return '';
  }
  const lines: string[] = [];
  for (const m of picked) {
    const text: string = m.content.length > MEMORY_CONTENT_MAX ?
      m.content.substring(0, MEMORY_CONTENT_MAX) + '…' : m.content;
    lines.push(m.role + ': ' + text.replace(/\s+/g, ' ').trim());
  }
  const joined: string = lines.join('\n');
  if (joined.length <= MEMORY_INPUT_TOTAL_LIMIT) {
    return joined;
  }
  const tail: number = MEMORY_INPUT_TOTAL_LIMIT - MEMORY_INPUT_HEAD_LIMIT -
    MEMORY_INPUT_ELISION.length;
  return joined.substring(0, MEMORY_INPUT_HEAD_LIMIT) + MEMORY_INPUT_ELISION +
    joined.substring(joined.length - tail);
}

// ══════════════════════════════════════════════════════════════════════════════
// 记忆优化（「记忆优化模型」pass，2026-09-11 方案-记忆整理优化-20260911 §6.4/§6.5 二期）
// ══════════════════════════════════════════════════════════════════════════════
// 定位（方案 §1）：提取 pass 管「新增侧不再变坏」，本 pass 管「把已经攒下的收拾干净」——
// 存量重复合并 + 粒度统一 + 压短表述（注入窗口按 updatedAt 取前 30 条 / 2000 字，库内可存
// 200 条；压短 = 更多不同事实挤进窗口）。★ 治不了「缺漏」：本 pass 手里只有条目、没有对话
// 原文，让它凭条目猜「应该还有什么」只会产生幻觉条目（方案 §2）。
// 协议（方案 §6.4）：输入按序号 1..N 编号送模型（**不送行 id**——id 是 mem_ 长串，模型抄错
// 一位就是改错行）；输出每行一条 JSON，只认 rewrite / merge 两种 op：
//   {"op":"rewrite","targets":[5],"text":"..."}
//   {"op":"merge","targets":[3,7,9],"text":"..."}
// 未提及的条目一律不动（白名单式——防「模型少说几条就静默删库」）。
// 本域负责「建议 → 可执行改动计划」的全部纯逻辑；网络与写库编排在 MemoryOpt / MemoryDb。

export const MEMORY_OPT_OP_REWRITE: string = 'rewrite';
export const MEMORY_OPT_OP_MERGE: string = 'merge';

// 优化结果态（页面出提示的唯一依据，文案映射单源 = memoryOptToastText；形制照 MemoryGen
// 的 MemorySinkResult 六态）：
// · applied——已应用（changed/merged/ignored 有意义）
// · none——没有可优化的内容（库空 / 模型给的建议全被丢弃 / 模型答「无」）
// · config——优化模型不可用（两键未配置 / 服务商或模型停用 / Key 池空 / 明文缺失）
// · tooLarge——模型给出的改动量超过闸门，整批放弃（方案 §6.5 兜底）
// · failed——本次优化没能完成（请求重试耗尽、异常终止）
// · skipped——守卫未放行且用户无事可做（在途重复触发、库态未就绪），页面保持沉默
// · ready——模型给出了可应用的改动（仅 prepare 阶段出现：页面据此出确认弹窗；toast 映射
//   恒 ''——还没应用，不出提示）
export const MEMORY_OPT_STATUS_APPLIED: string = 'applied';
export const MEMORY_OPT_STATUS_NONE: string = 'none';
export const MEMORY_OPT_STATUS_CONFIG: string = 'config';
export const MEMORY_OPT_STATUS_TOO_LARGE: string = 'tooLarge';
export const MEMORY_OPT_STATUS_FAILED: string = 'failed';
export const MEMORY_OPT_STATUS_SKIPPED: string = 'skipped';
export const MEMORY_OPT_STATUS_READY: string = 'ready';

export interface MemoryOptOutcome {
  status: string;
  changed: number; // 受影响条目数 = 改写数 + 合并组内行数（仅 applied 非零）
  merged: number; // 合并组数（仅 applied 非零）
  ignored: number; // 被丢弃的建议条数（解析失败/越界/敏感/超长/无变化/撞车，仅 applied 有意义）
  covered: number; // 实际送模型的行数（双封顶后）
  total: number; // 库内行数（covered < total = 只覆盖了最近一部分）
}

// 优化输入条目（带 id：选取结果同时喂「序号渲染」与「建议解析」，序号 = 本数组下标 + 1）
export interface MemoryOptInputItem extends MemoryEntryItem {
  id: string;
}

// 建议解析产物（模型一条 JSON 的合法形态；越界/未知 op 等在解析期就被拒，不出现在此）
export interface MemoryOptSuggestion {
  op: string;
  targets: number[]; // 1 起序号，升序不保证（保留行 = 首个序号，故原序保留）
  text: string;
}

// 单条改动：keepId 保留行（rewrite = 该行自身；merge = targets 首序号对应行，其余进
// deleteIds 删除）；text 为新内容
export interface MemoryOptChange {
  op: string;
  keepId: string;
  text: string;
  deleteIds: string[];
}

// 改动计划（确认摘要与执行共同依据；oversized 时 changes 恒空 = 整批放弃）
export interface MemoryOptPlan {
  changes: MemoryOptChange[];
  rewrite: number; // 改写条数
  mergeGroups: number; // 合并组数
  mergeRows: number; // 被合并进组的行数（含保留行）
  removed: number; // 将删除的行数（= mergeRows - mergeGroups）
  ignored: number; // 被丢弃的建议条数
  oversized: boolean; // 改动量超闸门（true = 整批放弃）
  covered: number;
  total: number;
}

// 优化输入选取：先丢敏感命中条目（与 composeMemoryList 同口径——优化请求发往的服务商未必
// 与聊天同家，手动条目的敏感内容不外发）→ 与注入块/去重清单同一贪心（条数 + 字符双封顶，
// 卡序口径：入参序 = queryMemories 的卡片序，超限保卡序前 N 条）。返回数组即序号基准。
export function selectMemoryOptItems(items: MemoryOptInputItem[], maxCount: number,
  maxChars: number): MemoryOptInputItem[] {
  const safe: MemoryOptInputItem[] = [];
  for (const item of items) {
    if (hitSensitiveContent(item.content) === '') {
      safe.push(item);
    }
  }
  return selectMemoryEntries(safe, maxCount, maxChars, 0);
}

// 序号渲染（'1. 内容' 逐行）——模型据序号引用行，不送 id（方案 §6.4）
export function composeMemoryOptList(items: MemoryEntryItem[]): string {
  const lines: string[] = [];
  for (let i = 0; i < items.length; i++) {
    lines.push((i + 1).toString() + '. ' + items[i].content);
  }
  return lines.join('\n');
}

// 单行建议解析：'' / 「无」类空答由调用方先滤掉；本函数对任何形态问题（坏 JSON / 未知 op /
// 序号越界或非整数 / 序号重复 / rewrite 序号数非 1 / merge 序号数不足 2 / 文本空或超长或
// 命中敏感）一律返回 null，由调用方计入 ignored。行首编号由 cleanMemoryLine 先剥（模型可能
// 把 JSON 也逐条编号）
// ★ 序号重复必须拒（2026-09-11 自检轮补，脏输入实测出的数据丢失路径）：merge 的保留行 =
// 首个序号行、其余序号行进 deleteIds——`targets:[3,3]` 会产出 keepId == deleteIds[0]，落库
// 时先按新文本更新该行、紧接着把它删掉，**合并结果与原文一起消失**（用户看到「合并 2 条为
// 1 条」，实际 0 条留存）。重复序号本身就说明模型对这几行的关系判断不可信，故整条丢（记
// ignored），不做「去重后照用」——那等于替模型猜它的意思
function parseMemoryOptLine(line: string, count: number): MemoryOptSuggestion | null {
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(line) as Record<string, Object>;
  } catch (e) {
    return null;
  }
  const rawOp: Object | undefined = parsed['op'];
  const rawTargets: Object | undefined = parsed['targets'];
  const rawText: Object | undefined = parsed['text'];
  if (typeof rawOp !== 'string' || typeof rawText !== 'string' || !Array.isArray(rawTargets)) {
    return null;
  }
  const op: string = rawOp.trim();
  if (op !== MEMORY_OPT_OP_REWRITE && op !== MEMORY_OPT_OP_MERGE) {
    return null;
  }
  const entries: Object[] = rawTargets as Object[];
  if (op === MEMORY_OPT_OP_REWRITE ? entries.length !== 1 : entries.length < 2) {
    return null;
  }
  const targets: number[] = [];
  const seenIndex: Set<number> = new Set<number>();
  for (const entry of entries) {
    if (typeof entry !== 'number') {
      return null;
    }
    const index: number = entry as number;
    if (!Number.isInteger(index) || index < 1 || index > count) {
      return null;
    }
    if (seenIndex.has(index)) {
      return null;
    }
    seenIndex.add(index);
    targets.push(index);
  }
  const text: string = rawText.trim();
  if (text === '' || text.length > MEMORY_CONTENT_MAX) {
    return null;
  }
  if (hitSensitiveContent(text) !== '') {
    return null;
  }
  return { op: op, targets: targets, text: text };
}

// 计划构建（解析 + 校验 + 改动量闸门——方案 §6.5 三道防线全在本函数）：
// ① 动作白名单：只认 rewrite / merge，**不提供 drop**（「这条不值得留」是主观判断，交给
//    用户自己删；merge 的副产物删除是允许的——合并本就要删被并入的行）
// ② 内容校验：≤ MEMORY_CONTENT_MAX 字（与库内单条上限同源）、命中敏感词表即丢、归一化
//    去重键不得与保留中的条目撞车（否则等于制造重复条）；另拒「无变化」——改写结果与被
//    改写行逐字同键（模型回声）或合并结果等于被合并行之一（必然丢信息）都丢该建议；
//    序号重复同样拒（见 parseMemoryOptLine——保留行会被自己删掉 = 内容净丢失）
// ③ 改动量闸门：将被删除的行数 ≤ 库内条数的 1/3 且 合并组数 ≤ 库内条数的 1/2，超限
//    oversized 置位、changes 清空 = 整批放弃（模型跑飞的兜底）；小库按下限 1 保底
//    （2 条重复的库若按 1/3 取整为 0，任何合并都被闸门拒 = 最该合并的场景反而不可用）
// 入参 total = 库内总行数（**只用于截断告知**：items 是双封顶后的子集，total > items.length
// 即「只覆盖了最近一部分」，页面据此如实说明；纯函数不吃 DB，故由调用方传入）
export function buildMemoryOptPlan(raw: string, items: MemoryOptInputItem[],
  total: number): MemoryOptPlan {
  const count: number = items.length;
  const changes: MemoryOptChange[] = [];
  let ignored: number = 0;
  let rewrite: number = 0;
  let mergeGroups: number = 0;
  let mergeRows: number = 0;
  let removed: number = 0;
  // 保留集去重键：尚未被任何已接受改动触及的行（新文本撞上它 = 制造重复条 → 丢该建议）。
  // 接受一条改动时把其涉及行的键暂扣、把新文本的键记入，故两条建议产出同文本也会互斥
  const survivorKeys: Set<string> = new Set<string>();
  for (const item of items) {
    survivorKeys.add(normalizeMemoryKey(item.content));
  }
  const usedIndex: Set<number> = new Set<number>();
  if (count > 0) {
    const lines: string[] = raw.split('\n');
    for (const line of lines) {
      const bare: string = cleanMemoryLine(line);
      if (bare === '' || isNoneAnswer(bare)) {
        continue; // 空行与模型答「无」不当作「一条建议」
      }
      const suggestion: MemoryOptSuggestion | null = parseMemoryOptLine(bare, count);
      if (suggestion === null) {
        ignored++;
        continue;
      }
      // 同一行不许被两条建议同时改（否则后一条会覆盖前一条的落点）
      let conflict: boolean = false;
      for (const target of suggestion.targets) {
        if (usedIndex.has(target)) {
          conflict = true;
        }
      }
      if (conflict) {
        ignored++;
        continue;
      }
      const key: string = normalizeMemoryKey(suggestion.text);
      let noChange: boolean = false;
      const hold: string[] = [];
      for (const target of suggestion.targets) {
        const oldKey: string = normalizeMemoryKey(items[target - 1].content);
        if (oldKey === key) {
          noChange = true;
        }
        if (survivorKeys.has(oldKey)) {
          survivorKeys.delete(oldKey);
          hold.push(oldKey);
        }
      }
      if (noChange || survivorKeys.has(key)) {
        for (const held of hold) {
          survivorKeys.add(held); // 丢弃即还原暂扣
        }
        ignored++;
        continue;
      }
      survivorKeys.add(key);
      const deleteIds: string[] = [];
      for (let i = 1; i < suggestion.targets.length; i++) {
        deleteIds.push(items[suggestion.targets[i] - 1].id);
      }
      for (const target of suggestion.targets) {
        usedIndex.add(target);
      }
      changes.push({
        op: suggestion.op,
        keepId: items[suggestion.targets[0] - 1].id,
        text: suggestion.text,
        deleteIds: deleteIds
      });
      if (suggestion.op === MEMORY_OPT_OP_MERGE) {
        mergeGroups++;
        mergeRows += suggestion.targets.length;
        removed += deleteIds.length;
      } else {
        rewrite++;
      }
    }
  }
  const maxRemoved: number = count >= 2 ? Math.max(1, Math.floor(count / 3)) : 0;
  const maxGroups: number = count >= 2 ? Math.max(1, Math.floor(count / 2)) : 0;
  const oversized: boolean = removed > maxRemoved || mergeGroups > maxGroups;
  return {
    changes: oversized ? [] : changes,
    rewrite: rewrite,
    mergeGroups: mergeGroups,
    mergeRows: mergeRows,
    removed: removed,
    ignored: ignored,
    oversized: oversized,
    covered: count,
    total: total
  };
}

// 确认弹窗正文（单源；plan 空改动时返回 ''——调用方据此不出弹窗）：先摘要再后果警示
//（方案 R1 缓解 = 确认弹窗 + 改动量上限 + 不许 drop + 帮助建议先导出备份）。★ 后果句按
// plan 形态分岔——只改写时不说「被合并掉的条目会删除」（没合并却说删除 = 假话，P0-1）
export function memoryOptConfirmText(plan: MemoryOptPlan): string {
  const parts: string[] = [];
  if (plan.mergeGroups > 0) {
    parts.push('合并 ' + plan.mergeGroups + ' 组共 ' + plan.mergeRows + ' 条为 ' +
      plan.mergeGroups + ' 条');
  }
  if (plan.rewrite > 0) {
    parts.push('改写 ' + plan.rewrite + ' 条');
  }
  if (parts.length === 0) {
    return '';
  }
  return '将' + parts.join('，') + '。' + (plan.mergeGroups > 0 ?
    '被合并掉的条目会删除，' : '') + '改动不可撤销。';
}

// 结果 → 用户提示文案（纯函数单源；'' = 不出提示）。除 skipped 外每态都有回声；applied 带
// 改动量、合并组数、截断告知与被丢弃建议数——「只覆盖了靠前一部分」「模型给的建议有几条
// 没被采用」都是用户该知道的事实（P0-1：不许假装整理过全库）；ignored 用「无法采用」而非
// 「无法识别」——该桶同时装解析失败与「解析成功但不可采用」（越界序号 / 无变化 / 撞车 /
// 敏感 / 超长），说「无法识别」在后者是假话
export function memoryOptToastText(outcome: MemoryOptOutcome): string {
  if (outcome.status === MEMORY_OPT_STATUS_APPLIED) {
    let text: string = '已优化 ' + outcome.changed + ' 条记忆';
    if (outcome.merged > 0) {
      text += '，合并 ' + outcome.merged + ' 组';
    }
    if (outcome.covered < outcome.total) {
      text += '，仅覆盖前 ' + outcome.covered + ' 条';
    }
    if (outcome.ignored > 0) {
      text += '，忽略 ' + outcome.ignored + ' 条无法采用的建议';
    }
    return text;
  }
  if (outcome.status === MEMORY_OPT_STATUS_NONE) {
    return '没有可优化的内容';
  }
  if (outcome.status === MEMORY_OPT_STATUS_CONFIG) {
    return '记忆优化模型当前不可用，请检查模型与密钥设置';
  }
  if (outcome.status === MEMORY_OPT_STATUS_TOO_LARGE) {
    return '模型给出的改动过大，已放弃';
  }
  if (outcome.status === MEMORY_OPT_STATUS_FAILED) {
    return '优化失败，请稍后重试';
  }
  return '';
}

// ══════════════════════════════════════════════════════════════════════════════
// 记忆检索（search_memory 工具纯函数面，2026-09-13 方案-记忆按需读取-20260913 §2.4）
// ══════════════════════════════════════════════════════════════════════════════
// 定位（方案 §1.2/§2.4）：读取方式切「按需读取」后，模型经工具调用自主决定何时查记忆
// ——本节只管「query → 相关条目 → 结果文本」的纯逻辑；检索在端内完成（零请求零费用），
// 库 ≤200 条全量内存打分（不做 SQL 端检索，避免 FTS 依赖与 SQL/内存双实现分叉）。

// 工具返回双封顶（宪法数据有界；比注入窗口 30/2000 小一档——检索结果按相关度已聚焦，
// 8 条/1500 字覆盖典型问询，超出由尾行提示模型收窄关键词）
export const MEMORY_TOOL_RESULT_MAX_COUNT: number = 8;
export const MEMORY_TOOL_RESULT_MAX_CHARS: number = 1500;
// 触上限尾行（selected < ranked = 双封顶截断了命中集）
const MEMORY_SEARCH_CAP_NOTE: string = '已达返回上限，可用更具体的关键词再检索';

// 检索条目（打分需要 updatedAt 新近度；extends MemoryEntryItem 保 selectMemoryEntries
// 泛型直接复用——同一贪心不复制。入参序 = 调用方 queryMemories 的卡片序，同库三键保证）
export interface MemorySearchItem extends MemoryEntryItem {
  updatedAt: number;
}

// 打分中间态（score/order 只在排序期存在；order = 入参下标，tiebreak 保卡序确定性）
interface MemorySearchScoredItem {
  item: MemorySearchItem;
  score: number;
  order: number;
}

// 检索词切分：按空白与中英文标点切，去空去重（保首现顺序）。中文整句无空格时整句成一个
// 词——工具 desc 已指引模型传关键词（「多个用空格分隔」），此处不做滑窗泛化（帮助检索
// searchHelpTerms 面向用户原话须泛化；本工具面向模型，输入自律性更高，克制不加）
export function splitMemoryQuery(query: string): string[] {
  const tokens: string[] = [];
  const seen: Set<string> = new Set<string>();
  const parts: string[] = query.split(/[\s,.;:!?，。、；：？！…—·\-~～()\[\]{}「」『』“”‘’"\/'\\|]+/)
    .map((p: string): string => p.trim());
  for (const part of parts) {
    if (part !== '' && !seen.has(part)) {
      seen.add(part);
      tokens.push(part);
    }
  }
  return tokens;
}

// 相关度打分：逐词命中 +1 + 整串 trimmed query 命中再 +2（整串是意图最强信号——分词把
// 「食品科学」拆成「食品」「科学」会命中零散条目，整串命中优先站上去）。
// ★ 大小写：两侧 toLowerCase——英文关键词大小写变体不丢分（用户问「openai」须命中
// 「OpenAI」的记忆，与 search_chats 用户可见行为一致，2026-09-13 O-1 拍板对齐；中文
// toLowerCase 无变化）。本域无 SQL 预筛，不存在「预筛/打分口径分叉」，小写化纯为
// 跨工具行为一致
function scoreMemoryItem(content: string, tokens: string[], whole: string): number {
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

// 排序比较（score 降序 → updatedAt 降序〔新者优先〕→ 入参序升序〔卡序〕；order tiebreak
// 显式写出——不赌引擎 sort 稳定性，断言可复算）
function compareMemorySearch(a: MemorySearchScoredItem, b: MemorySearchScoredItem): number {
  if (a.score !== b.score) {
    return b.score - a.score;
  }
  if (a.item.updatedAt !== b.item.updatedAt) {
    return b.item.updatedAt - a.item.updatedAt;
  }
  return a.order - b.order;
}

// 打分排序（零分条目不入选）：items 卡片序入 → 相关度序出
export function rankMemorySearchResults(items: MemorySearchItem[], tokens: string[],
  whole: string): MemorySearchItem[] {
  const scored: MemorySearchScoredItem[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const score: number = scoreMemoryItem(items[i].content, tokens, whole);
    if (score > 0) {
      scored.push({ item: items[i], score: score, order: i });
    }
  }
  scored.sort(compareMemorySearch);
  const ranked: MemorySearchItem[] = [];
  for (const entry of scored) {
    ranked.push(entry.item);
  }
  return ranked;
}

// 检索结果文本（模型消费面，简洁中文——文案规约不适用于模型面）：
// · 空库 → 「记忆库为空。」；query 切分后为空（纯标点/空白）→ 索要关键词
// · 无命中 → 未检索到 + 库内条数 + 换词提示
// · 命中 → 计数头行 + '[序号] 内容' 逐行；双封顶截断加尾行提示收窄关键词
// 选取复用 selectMemoryEntries 双封顶贪心（字符预算按既有 '- ' 行计——渲染前缀 '[3] ' 比它
// 长数字符，1500 字预算下偏差 ≤ 数十字，语义为软预算，不为对齐渲染前缀复制第二份贪心）
export function composeMemorySearchResult(items: MemorySearchItem[], query: string): string {
  if (items.length === 0) {
    return '记忆库为空。';
  }
  const tokens: string[] = splitMemoryQuery(query);
  if (tokens.length === 0) {
    return '请提供要检索的关键词。';
  }
  const ranked: MemorySearchItem[] = rankMemorySearchResults(items, tokens, query.trim());
  if (ranked.length === 0) {
    return '未检索到相关记忆。记忆库现有 ' + items.length + ' 条，可换关键词再试。';
  }
  const selected: MemorySearchItem[] = selectMemoryEntries(ranked, MEMORY_TOOL_RESULT_MAX_COUNT,
    MEMORY_TOOL_RESULT_MAX_CHARS, 0);
  const lines: string[] = ['检索到 ' + selected.length + ' 条相关记忆，按相关度排序'];
  for (let i: number = 0; i < selected.length; i++) {
    lines.push('[' + (i + 1).toString() + '] ' + selected[i].content);
  }
  if (selected.length < ranked.length) {
    lines.push(MEMORY_SEARCH_CAP_NOTE);
  }
  return lines.join('\n');
}

// ══════════════════════════════════════════════════════════════════════════════
// 记忆管理（manage_memory 工具纯函数面，2026-09-13 任务书-记忆管理工具-20260913）
// ══════════════════════════════════════════════════════════════════════════════
// 定位：控制台助手对长期记忆库的管理面——list 完整查看条数/内容/顺序 + create/update/delete
// 三写（含 delete，拍板 1：记忆删除无「N 会话引用」级联链，UI 记忆页有完整管理兜底）。本节
// 只管纯逻辑；DB 读写与广播编排在 ToolMemoryManage（执行器）。回执恒纯文本（manage_prompts
// 的 JSON 载荷形态不沿用——记忆条目本身是自然语言文本，纯文本对模型最直接），文案规约不
// 适用于模型面。
// ★ 定位方式 = 记忆原文精确匹配（拍板 2）：update/delete 的 content 与库内条目 trim 后逐字
//   相等才命中——0 命中回名单、≥2 命中拒歧义（manage_prompts 的 name 定位同形迁移）。弃
//   index 序号（连续删除下漂移删错条）与行 id（mem-<时间戳>-<序号> 模型不可抄，RikkaHub
//   #1830 实证 id 空洞被误读）——回执里的原文即下次操作的定位键。

// list 分页口径（拍板 6）：默认 30 对齐注入窗口语义（ChatSendCtrl 的 MEMORY_INJECT_MAX_COUNT
// 同值 30——两处 30 同值不同源，改注入窗口时须同查本常量，74 组回归钉在 ChatSendCtrl 侧）；
// 上限 50
export const MEMORY_MANAGE_LIST_DEFAULT_COUNT: number = 30;
export const MEMORY_MANAGE_LIST_MAX_COUNT: number = 50;
// 页内总字数软顶：超则自动收窄本页条数（至少 1 条）——防 clipToolResult 8192 硬顶截尾丢翻页
// 提示（最坏 50 条 × 500 字 = 25000 字；典型 60 字/条时 50 条约 3000 字不受影响）
export const MEMORY_MANAGE_PAGE_SOFT_CHARS: number = 6000;

// 校验结果（纯函数可断言）：ok = true 时 action 与对应参数就绪；offset/limit 为归一后值
export interface ManageMemoryValidation {
  ok: boolean;
  action: string;
  content: string;
  newContent: string;
  offset: number;
  limit: number;
  error: string;
}

function rejectManageMemory(error: string): ManageMemoryValidation {
  return { ok: false, action: '', content: '', newContent: '', offset: 1,
    limit: MEMORY_MANAGE_LIST_DEFAULT_COUNT, error: error };
}

// 参数校验纯函数：坏 JSON / 非法 action / create 缺 content / update 缺 content 或
// new_content / content 与 new_content 空、超 MEMORY_CONTENT_MAX 全拒；list 的 offset/limit
// 脏值归默认不报错（offset <1 或非整数 → 1；limit <1、>上限或非整数 → 30——模型少一轮纠错）
export function validateManageMemoryArgs(argsJson: string): ManageMemoryValidation {
  let action: string = '';
  let content: string = '';
  let newContent: string = '';
  let offset: number = 1;
  let limit: number = MEMORY_MANAGE_LIST_DEFAULT_COUNT;
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawContent: Object | undefined = parsed['content'];
    const rawNewContent: Object | undefined = parsed['new_content'];
    const rawOffset: Object | undefined = parsed['offset'];
    const rawLimit: Object | undefined = parsed['limit'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawContent === 'string') {
      content = rawContent.trim();
    }
    if (typeof rawNewContent === 'string') {
      newContent = rawNewContent.trim();
    }
    if (typeof rawOffset === 'number' && Number.isInteger(rawOffset)) {
      offset = rawOffset;
    }
    if (typeof rawLimit === 'number' && Number.isInteger(rawLimit)) {
      limit = rawLimit;
    }
  } catch (e) {
    return rejectManageMemory('参数解析失败，需要 action 参数');
  }
  if (action !== 'list' && action !== 'create' && action !== 'update' && action !== 'delete') {
    return rejectManageMemory('action 必须是 list、create、update 或 delete');
  }
  // offset/limit 归一（脏值归默认——拍板 6）
  if (offset < 1) {
    offset = 1;
  }
  if (limit < 1) {
    limit = MEMORY_MANAGE_LIST_DEFAULT_COUNT;
  }
  if (limit > MEMORY_MANAGE_LIST_MAX_COUNT) {
    limit = MEMORY_MANAGE_LIST_MAX_COUNT;
  }
  if (action === 'create' || action === 'update' || action === 'delete') {
    if (content === '') {
      return rejectManageMemory('action 为 ' + action +
        ' 时需要 content 参数，值为目标记忆全文（update/delete 为要操作的原文）');
    }
    if (content.length > MEMORY_CONTENT_MAX) {
      return rejectManageMemory('content 超过 ' + MEMORY_CONTENT_MAX + ' 字上限，当前 ' +
        content.length + ' 字，请精简');
    }
  }
  if (action === 'update') {
    if (newContent === '') {
      return rejectManageMemory('action 为 update 时需要 new_content 参数，值为修改后的记忆全文');
    }
    if (newContent.length > MEMORY_CONTENT_MAX) {
      return rejectManageMemory('new_content 超过 ' + MEMORY_CONTENT_MAX + ' 字上限，当前 ' +
        newContent.length + ' 字，请精简');
    }
  }
  return { ok: true, action: action, content: content, newContent: newContent,
    offset: offset, limit: limit, error: '' };
}

// 管理条目（定位与回执需要的最小行形态——零 import 域不引 DB 类型，执行器以 MemoryRow 适配）
export interface MemoryManageItem {
  id: string;
  content: string;
}

// 定位结果三态：unique = 唯一命中（hitId/hitContent 就绪）；none = 零命中；multi = 多命中
//（hits = 全部命中条渲染行 '[全库序号] 原文'，供回执列出区分）
export interface MemoryLocateOutcome {
  state: string; // 'unique' | 'none' | 'multi'
  hitId: string;
  hitContent: string;
  hits: string[];
}

// 原文精确匹配定位（拍板 2）：两侧 trim 后逐字相等才命中；items = 库序（queryMemories 三键）
export function locateMemoryByContent(items: MemoryManageItem[],
  content: string): MemoryLocateOutcome {
  const needle: string = content.trim();
  const hits: string[] = [];
  let hitId: string = '';
  let hitContent: string = '';
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].content.trim() === needle) {
      if (hitId === '') {
        hitId = items[i].id;
        hitContent = items[i].content;
      }
      hits.push('[' + (i + 1).toString() + '] ' + items[i].content);
    }
  }
  if (hits.length === 0) {
    return { state: 'none', hitId: '', hitContent: '', hits: [] };
  }
  if (hits.length > 1) {
    return { state: 'multi', hitId: '', hitContent: '', hits: hits };
  }
  return { state: 'unique', hitId: hitId, hitContent: hitContent, hits: [] };
}

// 定位失败回执（纯文本错误态，执行器原样返回）：
// · none：附库前 10 条清单 + 逐字引用指引（manage_prompts 0 匹配回显名单先例同形）
// · multi：列出全部命中条 + 区分指引（manage_prompts 多匹配拒歧义先例同形）
export function composeMemoryManageNoHit(items: MemoryManageItem[]): string {
  if (items.length === 0) {
    return '记忆库为空，没有可以修改或删除的记忆。';
  }
  const previewCount: number = Math.min(10, items.length);
  const lines: string[] = [];
  for (let i: number = 0; i < previewCount; i++) {
    lines.push('[' + (i + 1).toString() + '] ' + items[i].content);
  }
  const head: string = previewCount === items.length ?
    '当前库全部 ' + items.length + ' 条：' :
    '当前库前 ' + previewCount + ' 条（共 ' + items.length + ' 条）：';
  return '没有找到这条记忆——content 必须与库内某条记忆的原文逐字一致。\n' + head + '\n' +
    lines.join('\n') + '\n请先用 list 查看全部记忆，再逐字引用要操作的那条原文。';
}

export function composeMemoryManageMultiHit(hits: string[]): string {
  return '有 ' + hits.length + ' 条内容完全相同的记忆，无法确定要操作哪一条，本次未执行。全部命中条：\n' +
    hits.join('\n') + '\n请让用户补充更长的原文片段以区分，或指引用户在 设置 → 记忆 手动处理。';
}

// list 回执（纯文本；items = 库序，编号 = 全库序号——翻页连续〔offset=31 起的本页从 [31]
// 编起〕、与注入序同源，禁页内 1..K 重编号；单条全显不截断——「完整查看内容」是需求点）。
// 结构：计数头 + '[序号] 内容' 逐行 + 收窄/翻页/末尾尾注 + 注入口径行。offset/limit 脏值在
// 此二次归一（含 offset ≤ total 收口——越过末页的 offset 收到末条，模型恒见内容不落空页）
export function composeMemoryManageList(items: MemoryManageItem[], offset: number,
  limit: number): string {
  const total: number = items.length;
  if (total === 0) {
    return '记忆库为空。';
  }
  let start: number = offset < 1 ? 1 : offset;
  if (start > total) {
    start = total;
  }
  let count: number = limit < 1 ? MEMORY_MANAGE_LIST_DEFAULT_COUNT : limit;
  if (count > MEMORY_MANAGE_LIST_MAX_COUNT) {
    count = MEMORY_MANAGE_LIST_MAX_COUNT;
  }
  // 页内切片 + 软顶收窄：累计字数超 MEMORY_MANAGE_PAGE_SOFT_CHARS 即止（至少 1 条——首条
  // 恒放行，单条 ≤500 字恒在预算内）
  const lines: string[] = [];
  let shown: number = 0;
  let used: number = 0;
  while (shown < count && start - 1 + shown < total) {
    const item: MemoryManageItem = items[start - 1 + shown];
    const line: string = '[' + (start + shown).toString() + '] ' + item.content;
    if (shown > 0 && used + line.length > MEMORY_MANAGE_PAGE_SOFT_CHARS) {
      break;
    }
    lines.push(line);
    used += line.length;
    shown++;
  }
  const lastShown: number = start - 1 + shown;
  const parts: string[] = ['共 ' + total + ' 条记忆，按注入顺序排列（序号小先注入）。本页第 ' +
    start + '~' + lastShown + ' 条：'];
  parts.push(lines.join('\n'));
  if (shown < count && lastShown < total) {
    parts.push('本页因长度限制只显示前 ' + shown + ' 条');
  }
  if (lastShown < total) {
    parts.push('还有 ' + (total - lastShown) + ' 条，可用 offset=' + (lastShown + 1) + ' 继续');
  } else {
    parts.push('已到末尾');
  }
  parts.push('注：会话自动注入时最多携带前 ' + MEMORY_MANAGE_LIST_DEFAULT_COUNT + ' 条。');
  return parts.join('\n');
}

// 四写回执（纯文本——回执即向用户复述改了什么的载体，控制台提示词「执行后确认」行为约束
// 据此满足；create 回执的原文用调用方传入的 content 归一值——库内行即此串）
export function composeMemoryManageCreateReply(content: string, totalAfter: number): string {
  return '已新增记忆（现共 ' + totalAfter + ' 条）：\n' + content;
}

export function composeMemoryManageUpdateReply(oldContent: string, newContent: string): string {
  return '已修改记忆：\n旧：' + oldContent + '\n新：' + newContent;
}

export function composeMemoryManageDeleteReply(content: string, remaining: number): string {
  return '已删除记忆：\n' + content + '\n现剩余 ' + remaining + ' 条。';
}
