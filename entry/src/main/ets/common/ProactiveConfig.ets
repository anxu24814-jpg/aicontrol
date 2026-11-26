// 主动消息配置叶子（自 `common/ProactiveGen.ets` 整段外迁）：主动消息域的**档位域数组 +
// 默认值 + 持久键**共 10 件——被域实现（ProactiveGen 的排程与守卫）与设置白名单
//（ToolPref.setPrefWhitelist 的 levelValues 映射、刻度名生成与读写校验）两方共享，落中性
// 叶子以切断 `ToolPref → ProactiveGen` 反向依赖。
// · 为什么单独成文件：这 10 件「谁定义、谁消费」跨了设置域与主动消息域——留在 ProactiveGen
//   则设置白名单必须反向引主动消息域实现（模块环 + 域边界倒置）。落叶子后两域**单向**引本件。
// · 谁消费：ProactiveGen（排程/守卫/滑轨默认与兜底）、ToolPref（白名单归档 + desc 刻度名 +
//   读写校验）、ProactivePage（三滑轨 @StorageLink）、EntryAbility（persistProp 注册）、
//   ModelUsageCheck（总开关键读取）。
// · 禁什么：①本件**零 import**（叶子纪律——引一次就把可求值依赖带回叶子，坑50 求值序风险
//   一起回来；本件被设置域与主动消息域两方共享，环的风险面最宽）；②**禁在别处再定义同义
//   常量**（同值≠同源——断言与白名单按本件源文对表）；③ProactiveGen **不得对外转出**本件
//   符号（禁 `export { … } from './ProactiveConfig'`），消费方一律直引叶子。

// 间隔档（小时，ProactivePage 滑轨八档——数组序 = 滑轨档序，滑轨走索引映射 0~7）
export const PROACTIVE_INTERVAL_OPTIONS: number[] = [1, 2, 3, 4, 6, 8, 12, 24];
export const PROACTIVE_INTERVAL_DEFAULT: number = 24;
// 每日最多档（条，连续域 1~10：滑轨直映 + 编辑键精确输入，档位域数组承载白名单校验域，
// resolveDailyLimit 与页面守卫同口径）
export const PROACTIVE_DAILY_LIMIT_OPTIONS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
export const PROACTIVE_DAILY_LIMIT_DEFAULT: number = 1;
// 回前台静默期上限档（分钟，第三滑轨：原写死 1~5 分钟随机窗口的上限开放为八档非等距
//（数组序 = 滑轨档序，索引映射同间隔档），下限 1 分钟保持写死；默认 5 = 与原行为逐字节
// 一致零回归。档位域数组同承载白名单校验域，resolveQuietMaxMinutes 与页面守卫同口径）
export const PROACTIVE_QUIET_MAX_OPTIONS: number[] = [1, 2, 3, 5, 10, 15, 20, 30];
export const PROACTIVE_QUIET_MAX_DEFAULT: number = 5;
// ── 持久键（persistProp 注册在 EntryAbility.onWindowStageCreate 回调内坑17 区，插入位置 =
//    全部既有 persistProp 之后、PREF_LOADED_KEY 置 1 之前——该键是「持久键注册完毕」闸信号；
//    AppPreferences 两表登记见该文件。★ 本域其余键（proactiveSentAt / appForeground /
//    proactiveBanner / proactiveOpenCmd）仍归 ProactiveGen、proactiveUnreadConv 归
//    AppBroadcastKeys（广播键中性定义位），均不进本件）──
// 主动消息总开关（默认 false——用户显式开启才产生后台请求）
export const PROACTIVE_ENABLED_KEY: string = 'proactiveEnabled';
// 冷却间隔档（小时；值恒在 PROACTIVE_INTERVAL_OPTIONS 内，脏持久值回默认——
// resolveIntervalHours 兜底）
export const PROACTIVE_INTERVAL_HOURS_KEY: string = 'proactiveIntervalHours';
// 每日最多档（条；值恒在 PROACTIVE_DAILY_LIMIT_OPTIONS 内，脏持久值回默认——
// resolveDailyLimit 兜底）
export const PROACTIVE_DAILY_LIMIT_KEY: string = 'proactiveDailyLimit';
// 回前台静默期上限档（分钟；值恒在 PROACTIVE_QUIET_MAX_OPTIONS 内，脏持久值回默认——
// resolveQuietMaxMinutes 兜底）
export const PROACTIVE_QUIET_MAX_KEY: string = 'proactiveQuietMaxMinutes';
