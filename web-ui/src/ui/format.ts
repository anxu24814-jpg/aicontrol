// 展示辅助（身份色取色 / 时间 / 分组 / 角色文案）。
// 身份色语义与 docs/规范-视觉色板与徽标.md 一致：会话 id 全串散列取六色之一，
// 不取标题（标题会变）——CSS 变量单源在 styles/tokens.css，组件只写 identity-N 类名。

export function identityIndex(seed: string): number {
  let hash = 0;
  for (const ch of seed) {
    hash = (hash * 31 + (ch.codePointAt(0) ?? 0)) >>> 0;
  }
  return hash % 6;
}

export function identityInitial(title: string): string {
  const trimmed = title.trim();
  if (trimmed === '') {
    return '会';
  }
  return Array.from(trimmed)[0] ?? '会';
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

export function dayKey(ts: number): string {
  // ★ 2026-10-22 自检修：ts <= 0 归 ''——服务端 DTO 的 createdAt 可能为 0（未回填行），
  // 而 formatDayLabel(0) 已回 ''，两处不一致会让时间线插入一个**没有标签的空日期分隔条**
  if (!Number.isFinite(ts) || ts <= 0) {
    return '';
  }
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

// 侧栏/列表的相对时间（对齐参照稿的「6天」短形态）
export function formatRelative(ts: number): string {
  if (!Number.isFinite(ts) || ts <= 0) {
    return '';
  }
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const diff = Date.now() - ts;
  if (diff < 60_000) {
    return '刚刚';
  }
  if (diff < 3_600_000) {
    return `${Math.floor(diff / 60_000)}分钟`;
  }
  if (diff < 86_400_000 && dayKey(ts) === dayKey(Date.now())) {
    return `${Math.floor(diff / 3_600_000)}小时`;
  }
  const days = Math.round((startOfDay(new Date()) - startOfDay(date)) / 86_400_000);
  if (days <= 1) {
    return '昨天';
  }
  if (days < 30) {
    return `${days}天`;
  }
  if (days < 365) {
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }
  return `${date.getFullYear()}年${date.getMonth() + 1}月`;
}

export function formatClock(ts: number): string {
  if (!Number.isFinite(ts) || ts <= 0) {
    return '';
  }
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

// 消息日期分隔（今天 / 昨天 / 10月20日 / 2025年10月20日）
export function formatDayLabel(ts: number): string {
  if (!Number.isFinite(ts) || ts <= 0) {
    return '';
  }
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const days = Math.round((startOfDay(new Date()) - startOfDay(date)) / 86_400_000);
  if (days === 0) {
    return '今天';
  }
  if (days === 1) {
    return '昨天';
  }
  if (date.getFullYear() === new Date().getFullYear()) {
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

// 兼容旧调用点（聊天页副标题）：同日给时刻，跨日给日期
export function formatTimestamp(ts: number): string {
  if (!Number.isFinite(ts) || ts <= 0) {
    return '';
  }
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const sameDay = dayKey(ts) === dayKey(Date.now());
  return sameDay ? formatClock(ts) : formatDayLabel(ts);
}

export interface ConversationLike {
  id: string;
  title: string;
  updatedAt: number;
  favorite: boolean;
}

export interface ConversationGroup {
  key: string;
  label: string;
  items: ConversationLike[];
}

// 时间分组（今天 / 昨天 / 最近 7 天 / 最近 30 天 / 更早）。
// 为什么不是「工作区」分组：会话 DTO 只有 id/title/updatedAt/favorite 四个字段
//（WebReadApi.ets WebConversationDto），拿不到工作区归属——不虚构层级，改为时间分桶。
export function groupByTime(items: ConversationLike[]): ConversationGroup[] {
  const buckets: { key: string; label: string; limit: number }[] = [
    { key: 'today', label: '今天', limit: 0 },
    { key: 'yesterday', label: '昨天', limit: 1 },
    { key: 'week', label: '最近 7 天', limit: 7 },
    { key: 'month', label: '最近 30 天', limit: 30 },
    { key: 'older', label: '更早', limit: Number.POSITIVE_INFINITY },
  ];
  const groups: ConversationGroup[] = buckets.map((bucket) => ({
    key: bucket.key,
    label: bucket.label,
    items: [],
  }));
  const today = startOfDay(new Date());
  for (const item of items) {
    const valid = Number.isFinite(item.updatedAt) && item.updatedAt > 0;
    const days = valid
      ? Math.round((today - startOfDay(new Date(item.updatedAt))) / 86_400_000)
      : Number.POSITIVE_INFINITY;
    let index = buckets.length - 1;
    for (let i = 0; i < buckets.length; i++) {
      if (days <= buckets[i].limit) {
        index = i;
        break;
      }
    }
    groups[index].items.push(item);
  }
  return groups.filter((group) => group.items.length > 0);
}

export function toolStateText(state: string | undefined): string {
  switch (state) {
    case 'running':
      return '执行中';
    case 'done':
      return '已完成';
    case 'error':
      return '失败';
    case 'cancelled':
      return '已取消';
    default:
      return '';
  }
}

export function toolStateClass(state: string | undefined): string {
  if (state === 'running' || state === 'done' || state === 'error' || state === 'cancelled') {
    return state;
  }
  return '';
}
