// 聊天自动重试配置域偏好键与读封装（照 AppPreferencesHttp.ets「JSON 串结构化键」同族）。
// 零 import 叶子（只用 AppStorage，谁都可引、不引任何人）；备份收录以常量引用登记在
// AppPreferencesBackup.ets（键名漂移由 assert-feature-domain 54 组钉兜住——改名即红）。
// 结构（单 JSON 键；字段缺省 / 脏值逐字段回默认不抛错——偏好键宁可回默认不可炸链）：
//   { maxRetries, initialDelayMs, multiplier, maxDelayMs,
//     retryStatusCodes: number[], retryKeywords: string[], stopKeywords: string[] }
// ★ 三清单空表 = 有效配置（用户清空意图，原样生效不弹默认）；原表非空而元素全被清洗掉 =
// 脏数据回默认；键缺失 / 坏 JSON / 非数组脏值回默认。
// ★ 总开关不在本键——沿用旧布尔键 prefAutoRetry（AppPreferences.PREF_AUTO_RETRY_KEY）：
// 设置页总开关与控制台设键路径都写它，单一真源；旧键保留不删 = 回退通道。
// 退避语义：第 n 次重试延迟 = initialDelayMs × multiplier^(n-1)，封顶 maxDelayMs。
// ★ 默认值底版 = 原编译期常量值（408/425 是请求侧超时语义、429 归 Key 池换钥先位，均不入面）。
// 域件侧另有同值兜底常量（宿主未接配置读口时用），两处等值由 assert-retry-domain 172 组
// 关系钉守（单侧漂移即红）。
// ★ Key 池换钥边界：ChatStreamFlowCtrl 换钥面 [401,403,429] 是独立优先链（先于自动重试判），
// 本键不并入不劫持——用户自配加 429 等码只影响池尽后的自动重试面。

// 自动重试配置 JSON 串结构化键（'' = 未写 = 全默认 = 行为与改造前逐字节等价）
export const PREF_AUTO_RETRY_CFG_KEY: string = 'prefAutoRetryCfg';

// 配置结构（消费方 = ChatAutoRetryCtrl 经宿主读口 + 自动重试设置页渲染面）
export interface AutoRetryCfg {
  maxRetries: number;          // 本轮最多自动重试次数（1 起）
  initialDelayMs: number;      // 第 1 次重试前等待（毫秒）
  multiplier: number;          // 退避倍率（第 n 次 = initial × multiplier^(n-1)）
  maxDelayMs: number;          // 单次等待上限（毫秒，封顶）
  retryStatusCodes: number[];  // 可自动重试的服务端状态码集合（不含传输层 -1，-1 恒在面；空表 = 不按状态码重试）
  retryKeywords: string[];     // 瞬态文案词表（命中即越过状态码面接管；英文大小写不敏感；空表 = 不启用）
  stopKeywords: string[];      // 停词表（先于瞬态词与状态码判——确定性失败不重发；空表 = 无停词）
}

// ── 字段域与上限（宪法数据有界；UI 弹窗与解析清洗共引单源）──
export const AUTO_RETRY_MAX_RETRIES_MIN: number = 1;
export const AUTO_RETRY_MAX_RETRIES_MAX: number = 10;
export const AUTO_RETRY_INITIAL_MS_MIN: number = 100;
export const AUTO_RETRY_INITIAL_MS_MAX: number = 60000;
export const AUTO_RETRY_MULTIPLIER_MIN: number = 1;
export const AUTO_RETRY_MULTIPLIER_MAX: number = 10;
export const AUTO_RETRY_DELAY_CAP_MS_MIN: number = 1000;
export const AUTO_RETRY_DELAY_CAP_MS_MAX: number = 600000;
export const AUTO_RETRY_STATUS_MIN: number = 100;
export const AUTO_RETRY_STATUS_MAX: number = 599;
export const AUTO_RETRY_STATUS_MAX_COUNT: number = 32;
export const AUTO_RETRY_WORD_MAX_CHARS: number = 40;
export const AUTO_RETRY_WORDS_MAX_COUNT: number = 24;

// ── 默认值底版（408/425/429 不入面，429 归 Key 池换钥先位）──
export const AUTO_RETRY_DEFAULT_MAX_RETRIES: number = 3;
export const AUTO_RETRY_DEFAULT_INITIAL_MS: number = 2000;
export const AUTO_RETRY_DEFAULT_MULTIPLIER: number = 2;
export const AUTO_RETRY_DEFAULT_DELAY_CAP_MS: number = 8000;
export const AUTO_RETRY_DEFAULT_STATUS_CODES: number[] = [500, 502, 503, 504, 529];
export const AUTO_RETRY_DEFAULT_RETRY_KEYWORDS: string[] = ['并发', '稍后', '重试', '访问量过大',
  '繁忙', '限流', 'rate limit', 'too many requests', 'overloaded', 'try again', 'timeout', '超时'];
export const AUTO_RETRY_DEFAULT_STOP_KEYWORDS: string[] = ['余额', '不足', '额度', '欠费',
  'balance', 'insufficient', 'quota', 'invalid api key', 'unauthorized', 'permission', '未实名'];

// 默认配置整件（「恢复默认」键与断言直跑用；返回新数组防调用方原地改默认单源）
export function autoRetryDefaultCfg(): AutoRetryCfg {
  return {
    maxRetries: AUTO_RETRY_DEFAULT_MAX_RETRIES,
    initialDelayMs: AUTO_RETRY_DEFAULT_INITIAL_MS,
    multiplier: AUTO_RETRY_DEFAULT_MULTIPLIER,
    maxDelayMs: AUTO_RETRY_DEFAULT_DELAY_CAP_MS,
    retryStatusCodes: AUTO_RETRY_DEFAULT_STATUS_CODES.slice(),
    retryKeywords: AUTO_RETRY_DEFAULT_RETRY_KEYWORDS.slice(),
    stopKeywords: AUTO_RETRY_DEFAULT_STOP_KEYWORDS.slice()
  };
}

// 数值字段清洗（越界 / 非有限数回默认；整数性只约束 maxRetries 与毫秒三值——倍率允许小数）
function cleanNumber(raw: Object, fallback: number, min: number, max: number, int: boolean): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    return fallback;
  }
  if (int && !Number.isInteger(raw)) {
    return fallback;
  }
  if (raw < min || raw > max) {
    return fallback;
  }
  return raw;
}

// 状态码清单清洗（元素逐个验 100~599 整数、去重保序、条数上限丢尾部）★ 空表保留（用户清空
// 意图即配置——「不按状态码重试」原样生效）；键缺失 / 非数组脏值回默认；原表非空而全脏回默认
function cleanStatuses(raw: Object): number[] {
  const out: number[] = [];
  if (!Array.isArray(raw)) {
    return AUTO_RETRY_DEFAULT_STATUS_CODES.slice();
  }
  const list: Object[] = raw as Object[];
  for (const item of list) {
    if (typeof item !== 'number' || !Number.isInteger(item) ||
      item < AUTO_RETRY_STATUS_MIN || item > AUTO_RETRY_STATUS_MAX) {
      continue;
    }
    if (!out.includes(item)) {
      out.push(item);
    }
    if (out.length >= AUTO_RETRY_STATUS_MAX_COUNT) {
      break;
    }
  }
  if (out.length === 0 && list.length > 0) {
    return AUTO_RETRY_DEFAULT_STATUS_CODES.slice(); // 原表非空但元素全脏 = 脏数据，回默认
  }
  return out; // 空表（原表本身为空）= 用户清空意图，原样生效
}

// 词表清洗（元素 trim、空串 / 超长丢弃、去重保序、条数上限丢尾部）★ 空表保留（用户清空意图
// 即配置）；键缺失 / 非数组脏值回默认；原表非空而全脏回默认
function cleanWords(raw: Object, fallback: string[]): string[] {
  const out: string[] = [];
  if (!Array.isArray(raw)) {
    return fallback.slice();
  }
  const seenLower: string[] = [];
  const list: Object[] = raw as Object[];
  for (const item of list) {
    if (typeof item !== 'string') {
      continue;
    }
    const word: string = item.trim();
    if (word === '' || word.length > AUTO_RETRY_WORD_MAX_CHARS) {
      continue;
    }
    const lower: string = word.toLowerCase();
    if (seenLower.includes(lower)) {
      continue;
    }
    seenLower.push(lower);
    out.push(word);
    if (out.length >= AUTO_RETRY_WORDS_MAX_COUNT) {
      break;
    }
  }
  if (out.length === 0 && list.length > 0) {
    return fallback.slice(); // 原表非空但元素全脏 = 脏数据，回默认
  }
  return out; // 空表（原表本身为空）= 用户清空意图，原样生效
}

// 解析（读值封装底层；脏 JSON 回全默认，字段脏值逐字段回默认——不抛错）。export 供设置页
// 渲染面直引（自 @StorageLink 键串派生清单建渲染依赖，照 parseHttpAllowedHosts 先例）
export function parseAutoRetryCfg(json: string): AutoRetryCfg {
  const fallback: AutoRetryCfg = autoRetryDefaultCfg();
  if (json === '') {
    return fallback;
  }
  try {
    const raw = JSON.parse(json) as Record<string, Object>;
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      return fallback;
    }
    fallback.maxRetries = cleanNumber(raw['maxRetries'], fallback.maxRetries,
      AUTO_RETRY_MAX_RETRIES_MIN, AUTO_RETRY_MAX_RETRIES_MAX, true);
    fallback.initialDelayMs = cleanNumber(raw['initialDelayMs'], fallback.initialDelayMs,
      AUTO_RETRY_INITIAL_MS_MIN, AUTO_RETRY_INITIAL_MS_MAX, true);
    fallback.multiplier = cleanNumber(raw['multiplier'], fallback.multiplier,
      AUTO_RETRY_MULTIPLIER_MIN, AUTO_RETRY_MULTIPLIER_MAX, false);
    fallback.maxDelayMs = cleanNumber(raw['maxDelayMs'], fallback.maxDelayMs,
      AUTO_RETRY_DELAY_CAP_MS_MIN, AUTO_RETRY_DELAY_CAP_MS_MAX, true);
    fallback.retryStatusCodes = cleanStatuses(raw['retryStatusCodes']);
    fallback.retryKeywords = cleanWords(raw['retryKeywords'], AUTO_RETRY_DEFAULT_RETRY_KEYWORDS);
    fallback.stopKeywords = cleanWords(raw['stopKeywords'], AUTO_RETRY_DEFAULT_STOP_KEYWORDS);
  } catch (e) {
    return autoRetryDefaultCfg();
  }
  return fallback;
}

// 键 JSON 串读口（@StorageLink 直连兜底读）
export function getAutoRetryCfgJson(): string {
  return AppStorage.get<string>(PREF_AUTO_RETRY_CFG_KEY) ?? '';
}

// 读生效配置（宿主 ChatAutoRetryHost.autoRetryCfg 实现位每轮现读——写入下一轮生效）
export function resolveAutoRetryCfg(): AutoRetryCfg {
  return parseAutoRetryCfg(getAutoRetryCfgJson());
}

// 序列化（写侧单源——只写清洗后的值，脏值不落盘）
function serializeAutoRetryCfg(cfg: AutoRetryCfg): string {
  return JSON.stringify(cfg);
}

// 写全量（设置页所有编辑键共用：读现值 → 改单字段 → 归一 → 回写）
function writeCfg(cfg: AutoRetryCfg): void {
  AppStorage.set<string>(PREF_AUTO_RETRY_CFG_KEY, serializeAutoRetryCfg(cfg));
}

// 写退避四参数（设置页「重试参数」四行编辑弹窗确认时各调一次，未改字段传现值）
export function setAutoRetryNumbers(maxRetries: number, initialDelayMs: number,
  multiplier: number, maxDelayMs: number): void {
  const cur: AutoRetryCfg = resolveAutoRetryCfg();
  cur.maxRetries = cleanNumber(maxRetries, cur.maxRetries,
    AUTO_RETRY_MAX_RETRIES_MIN, AUTO_RETRY_MAX_RETRIES_MAX, true);
  cur.initialDelayMs = cleanNumber(initialDelayMs, cur.initialDelayMs,
    AUTO_RETRY_INITIAL_MS_MIN, AUTO_RETRY_INITIAL_MS_MAX, true);
  cur.multiplier = cleanNumber(multiplier, cur.multiplier,
    AUTO_RETRY_MULTIPLIER_MIN, AUTO_RETRY_MULTIPLIER_MAX, false);
  cur.maxDelayMs = cleanNumber(maxDelayMs, cur.maxDelayMs,
    AUTO_RETRY_DELAY_CAP_MS_MIN, AUTO_RETRY_DELAY_CAP_MS_MAX, true);
  writeCfg(cur);
}

// 写状态码集合（设置页 chips 增删后整表回写；清洗同解析侧单源）
export function setAutoRetryStatusCodes(codes: number[]): void {
  const cur: AutoRetryCfg = resolveAutoRetryCfg();
  cur.retryStatusCodes = cleanStatuses(codes as Object[]);
  writeCfg(cur);
}

// 写瞬态词表（设置页「重试关键字」chips 增删与恢复默认共用）
export function setAutoRetryRetryKeywords(words: string[]): void {
  const cur: AutoRetryCfg = resolveAutoRetryCfg();
  cur.retryKeywords = cleanWords(words as Object[], AUTO_RETRY_DEFAULT_RETRY_KEYWORDS);
  writeCfg(cur);
}

// 写停词表（设置页「停止关键字」chips 增删与恢复默认共用）
export function setAutoRetryStopKeywords(words: string[]): void {
  const cur: AutoRetryCfg = resolveAutoRetryCfg();
  cur.stopKeywords = cleanWords(words as Object[], AUTO_RETRY_DEFAULT_STOP_KEYWORDS);
  writeCfg(cur);
}
