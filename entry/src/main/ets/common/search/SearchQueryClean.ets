// 联网搜索·query 加工纯函数层（2026-09-10 多引擎一期，决明拍板带进一期）：模型给出的
// 搜索关键词在进引擎前做两道归一——①口语前缀清洗（「帮我搜索一下 X」→「X」，Cube
// 快照 utils/SearchQueryUtils.ets:50-85 裁剪移植，chatcube MIT）；②相对时间词归一
//（「今天的 AI 新闻」→「2026年9月10日 今天的 AI 新闻」，仅新闻意图，Cube :3-122 同源
// 裁剪——非新闻意图不改写，避免过度加工吞掉用户原话语义）。★ 零 import 契约（同
// WebSearchParse——node 直跑断言依赖，scripts/sse-assert.mjs ㊿ 组消费；本文件禁加任何
// import）。

// 关键词长度截断（search_web description 已要求聚焦关键词——超长串多为模型传参脏，
// 截断保引擎 URL 不爆；控制字符清掉后按字符位截）
const QUERY_MAX_CHARS: number = 100;

// 口语前缀清洗 + 控制字符剥离 + 空白压缩 + 长度截断。清洗后为空回退原文（防御——
// 纯前缀输入如「搜一下」不因清洗变空串）
export function cleanSearchQuery(raw: string): string {
  let cleaned: string = raw
    .replace(/[\x00-\x1F\x7F]/g, ' ')
    .trim();
  // Cube 双保险：正则一遍（组合前缀）+ 前缀表一遍（遗漏组合），MIT 原样移植
  cleaned = cleaned.replace(
    /^(?:帮我|麻烦|请|请帮我|帮忙)?(?:查询|搜索|查找|查|搜)(?:一下|下)?[\s，,。:：-]*/i, '');
  const prefixes: string[] = [
    '帮我搜索', '搜索一下', '搜索下', '查一下', '查下', '搜一下', '搜下',
    '帮我查', '帮我查一下', '帮我查下', '请搜索', '请查', '请查一下', '请查下',
    '帮我找', '帮我找一下', '帮我找下', '找一下', '找下'
  ];
  for (const prefix of prefixes) {
    if (cleaned.startsWith(prefix)) {
      cleaned = cleaned.substring(prefix.length).trim();
      break;
    }
  }
  cleaned = cleaned.replace(/\s+/g, ' ').trim();
  if (cleaned === '') {
    return raw.trim();
  }
  return cleaned.length > QUERY_MAX_CHARS ? cleaned.substring(0, QUERY_MAX_CHARS) : cleaned;
}

// 显式日期已在 query 里（2026年9月10日 / 2026-09-10 / 2026.9.10）——不再做相对词归一
//（Cube hasExplicitDateInQuery:3-5 同构）
function hasExplicitDate(text: string): boolean {
  return /(\d{4})[年\/\-.](\d{1,2})[月\/\-.]?(\d{1,2})日?/.test(text);
}

// 相对日词 → 天偏移（99 = 无相对词；Cube getRelativeDayOffset:7-18 同构）
function relativeDayOffset(text: string): number {
  if (text.includes('昨天') || text.includes('昨日')) {
    return -1;
  }
  if (text.includes('明天')) {
    return 1;
  }
  if (text.includes('今天') || text.includes('今日') || text.includes('现在') ||
    text.includes('当前')) {
    return 0;
  }
  return 99;
}

// 新闻意图判定（仅该意图才把相对日词展开为具体日期——Cube :36-47 同构口径：避免对
// 「现在的天气怎么样」这类非检索词过度改写）
function isNewsIntent(text: string): boolean {
  const t: string = text.replace(/\s+/g, '').toLowerCase();
  const keywords: string[] = ['新闻', '快讯', '资讯', '头条', '热点', '动态', '发布会', '通报', 'news'];
  for (const keyword of keywords) {
    if (t.includes(keyword.toLowerCase())) {
      return true;
    }
  }
  return false;
}

// 相对时间归一：今天/今天这类词对引擎是「无时间锚的噪音」，新闻意图时在词前补具体日期
//（保留原词——模型引文对照不受影响）。显式日期/非新闻意图/无相对词 = 原样返回。
// ★ 「最近/本周」类不定长词不做数字归一（Cube 亦未做——起止语义猜错比不改更糟，留档）
export function normalizeRelativeTime(query: string, now: Date): string {
  if (query === '' || hasExplicitDate(query)) {
    return query;
  }
  const offset: number = relativeDayOffset(query);
  if (offset === 99 || !isNewsIntent(query)) {
    return query;
  }
  const date: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
  const dateText: string =
    `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  return `${dateText} ${query}`.trim();
}
