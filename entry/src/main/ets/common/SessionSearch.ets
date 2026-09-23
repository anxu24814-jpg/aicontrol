// 会话搜索数据层（2026-09-08 会话搜索记录区，决明指令「样式与设置搜索对齐，增加搜索历史，
// 最近使用改名最近进入，其他逻辑一致」）：会话搜索历史 + 最近进入会话两组记录的持久化，
// 机制逐环对齐 common/SettingSearch.ets 同名函数族（读写两侧截断收敛 / 去重移头 / 有界）。
// 为何独立建档不入 SettingSearch：域不同（设置项搜索 vs 会话列表搜索），SettingSearch 是
// 「设置项注册表 + 标题常量」的单一数据源，会话无注册表（记录 = 历史 + 最近进入两族键），
// 并入会把两域耦合；分层范式同 SettingSearch（数据层）/ SearchSections（板块 UI）。
//
// ★ 五环清单（决明点名「注意注册 路由 缓存 清删 上限等」，与设置搜索逐环同构）：
//   注册 = EntryAbility loadContent 成功回调内 PersistentStorage.persistProp 两键（坑17
//     时机——早于该时机注册写入不落盘）；路由 = 最近进入点击走 onOpen 既有链（handleOpenCard
//     加密守卫 + push，不另开路由）；缓存 = AppStorage + PersistentStorage 持久化（string[]
//     一维数组可持久化，对象数组禁止——dshinhm 先例）；清删 = 历史区垃圾桶 / 最近进入区 X
//     直接写空数组 + 展示侧反查失败跳过（防持久化残留脏 id——已删会话不显示不清键，对齐
//     SettingSearch 脏数据姿势）；上限 = 历史 5 条 / 词条 10 字 / 最近进入 3 条（与设置
//     搜索同值，读写两侧双收敛）。

// 搜索历史键（AppStorage + PersistentStorage；EntryAbility persistProp 注册）
export const SESSION_SEARCH_HISTORY_KEY: string = 'sessionSearchHistory';
// 搜索历史上限 5 条（对齐 SettingSearch.MAX_SEARCH_HISTORY 决明定稿值）
export const MAX_SESSION_SEARCH_HISTORY: number = 5;
// 搜索词条长度上限（对齐 SettingSearch.MAX_SEARCH_TERM_LENGTH：存储只留前 10 字——超长
// 粘贴属误操作；展示侧另有 maxWidth + 单行省略号双保险，见 SessionSearchPanels）
export const MAX_SESSION_SEARCH_TERM_LENGTH: number = 10;

// 最近进入会话键：存会话 id 一维数组（非 title——title 会改名/可重名，id 稳定唯一；
// 展示侧由列表页按当前已加载 rows 反查标题，反查不到 = 已删或非当前助手名下，跳过）
export const SESSION_RECENT_CONV_KEY: string = 'sessionRecentConv';
// 最近进入上限 3 条（对齐 SettingSearch.MAX_RECENT_USE）
export const MAX_SESSION_RECENT_CONV: number = 3;

// ── 搜索历史（对齐 SettingSearch 同名族：去重移头、截断上限，有界防内存/存储膨胀）──

export function getSessionSearchHistory(): string[] {
  const history: string[] | undefined = AppStorage.get<string[]>(SESSION_SEARCH_HISTORY_KEY);
  // 读取侧同样截断：上限调整后持久化里可能残留超限旧数据，读取即收敛（SettingSearch 姿势）
  return history === undefined ? [] : history.slice(0, MAX_SESSION_SEARCH_HISTORY);
}

// 记录一次搜索词（Search.onSubmit 唯一调用点 + 历史词条点击回填移头）：截断长度上限 →
// 去重（已存在移到头部）→ 插头部 → 截断上限条数
export function recordSessionSearchHistory(term: string): void {
  const trimmed: string = term.trim();
  if (trimmed === '') {
    return;
  }
  const limited: string = trimmed.slice(0, MAX_SESSION_SEARCH_TERM_LENGTH);
  const history: string[] = getSessionSearchHistory()
    .filter((item: string): boolean => item !== limited);
  history.unshift(limited);
  AppStorage.set(SESSION_SEARCH_HISTORY_KEY, history.slice(0, MAX_SESSION_SEARCH_HISTORY));
}

export function clearSessionSearchHistory(): void {
  AppStorage.set(SESSION_SEARCH_HISTORY_KEY, []);
}

// ── 最近进入（用户最近点开过的会话）：记录时机 = handleOpenCard 实际放行进入（含加密
// 会话认证通过分支——未通过不算进入）；展示 = 列表页按当前 rows 反查（id → 标题/时间）──

export function getSessionRecentConvs(): string[] {
  const recent: string[] | undefined = AppStorage.get<string[]>(SESSION_RECENT_CONV_KEY);
  return recent === undefined ? [] : recent.slice(0, MAX_SESSION_RECENT_CONV);
}

// 记录一次进入：去重（已存在移到头部）→ 插头部 → 截断上限（同历史有界姿势）
export function recordSessionRecentConv(conversationId: string): void {
  const trimmed: string = conversationId.trim();
  if (trimmed === '') {
    return;
  }
  const recent: string[] = getSessionRecentConvs()
    .filter((item: string): boolean => item !== trimmed);
  recent.unshift(trimmed);
  AppStorage.set(SESSION_RECENT_CONV_KEY, recent.slice(0, MAX_SESSION_RECENT_CONV));
}

export function clearSessionRecentConvs(): void {
  AppStorage.set(SESSION_RECENT_CONV_KEY, []);
}
