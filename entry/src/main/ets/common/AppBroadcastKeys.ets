// 跨域 AppStorage 广播键中性定义位：common 侧与 components 侧**共享**的 tick / 状态键
// 集中于此，切断 `common → components` 反向 import。
// · 为什么单独成文件：两键消费方两侧都跨（刷新键写点含 common 侧 ProactiveGen、未读键
//   消费方含 components 侧 ChatSessionList）——任一侧持有定义，另一侧就得跨层反引，
//   构成 common→components 反向边。
// · 为什么不能并入 AppPreferences：该件是**偏好键家**（用户可配置、进偏好两表）；而本件
//   两键都不是偏好——`SESSION_LIST_RELOAD_KEY` 是一次性计数器（勿持久化），
//   `PROACTIVE_UNREAD_CONV_KEY` 虽是持久键（`EntryAbility` persistProp）但被
//   `AppPreferences.BACKUP_EXCLUDED_PREF_KEYS` 按设计排除出备份（本机未读痕迹）。
//   并入偏好表 = 语义污染（会被当作设置项读取、登记、导出）。
// · 谁消费：刷新键 —— ProactiveGen（落库尾段自增）、ChatSessionList（自增 + 订阅）、
//   AssistantPage / ChatBranchCtrl / ChatPage / SessionSearchPage / HomeNavigation /
//   DataSyncPage / QuickCleanPage（订阅或自增）；未读键 —— ProactiveGen（落库写入）、
//   ChatSessionList（@StorageProp 红点）、ChatPage（进页清空）、EntryAbility（persistProp）。
// · 禁什么：①本件**零 import**（叶子纪律——引一次就把可求值依赖带回叶子，坑50 求值序风险
//   一起回来）；②**键名字符串值一字不可改**（存量持久态与既有订阅面零迁移——改值等于把
//   未读红点与列表刷新链一并打断）；③**禁在别处再定义同义常量**（同值≠同源；断言按本件
//   源文对表）；④两键语义不动（一次性计数器 vs 持久键，见上）。

// 会话列表刷新广播键（一次性计数器，勿持久化）：写点 = 对话页离页（ChatPage.aboutToDisappear
// ——新建/改行后广播）、本组件两条删除链成功支（deleteOne / deleteSelected——删行发生在
// 对话页签列表内、不经对话页，此侧原零写点）、助手页切/删助手、备份恢复（DataSyncPage）、
// 主动消息落库（ProactiveGen）；消费方 = 本组件 + 助手页卡面「会话 N」chip + 会话搜索页，
// 各自 @Watch 重拉。走 AppStorage 广播而非 @Prop 透传——真机实测 @Prop 计数器经
// HdsTabs/TabContent 多层未传导（返回后时间序不刷新，冷启动数据正确），AppStorage 姿势
// 与组件树层级无关
export const SESSION_LIST_RELOAD_KEY: string = 'sessionListReloadTick';

// 未读会话持久键（string，默认 ''）：落库时写目标会话 id，用户进入该会话页
// onPageShown 清空（ChatPage）——本机未读痕迹与 proactiveSentAt 同族，进 AppPreferences
// 排除表不随备份走；消费方 = ChatSessionList 红点（@StorageProp 只读订阅）
export const PROACTIVE_UNREAD_CONV_KEY: string = 'proactiveUnreadConv';

// ── 系统分享接收桥 ──
// 待发分享件（string，JSON 数组 PendingSharedItem[]，默认未写）：EntryAbility 解析
// sendData（系统分享面板）/ viewData（文件管理器「打开方式」）两入口的拉起 want 后
// 一次性**覆写**（桥恒只留最新一批——消费按 tick 匹配批次，旧批被新批顶替即弃）；消费方 =
// 会话页 onShown（AttachmentPickCtrl.consumePendingShareInto，消费后清回 '[]'）。
// 运行态键不持久（禁入 persistProp——拉起批次是瞬时面，持久化无语义）
export const PENDING_SHARES_KEY: string = 'pendingSharesJson';

// 待发分享批次号（number 一次性计数器，勿持久化）：每写一次桥自增 1——路由方 =
// HomeNavigation（@Watch 订阅，路由恒新建会话页并把 tick 作 push 参数下发）；消费方 =
// 会话页按 shareTick 匹配桥批次。键名字符串值一经定稿不可再改（本件纪律②③）
export const PENDING_SHARES_TICK_KEY: string = 'pendingSharesTick';

// 分享拉起在途标记（boolean，运行态不持久）：EntryAbility onCreate 同步探 want.action
// 置位——getSharedData 异步返回晚于导航壳「启动进新对话」冷启动判定，壳据此让位防双推
//（消费方 = HomeNavigation.tryEnterLaunchConversation 一次性判定；解析失败无 tick 时
// 本次冷启动落回主页列表，hilog 留痕）
export const PENDING_SHARE_INCOMING_KEY: string = 'pendingShareIncoming';

// 启动落点衔接标记（boolean，运行态不持久）：HomeNavigation 在「本次启动的落点 = 会话页」
// 的判定分支置 true（drawer 主区三分支 / tabs 启动进入新对话分支）；消费方 =
// ChatPageLifecycle.enter 一次性读取后清位 → 空态层首帧即画与系统启动页同图同尺寸同中心
// 的图标（DB 十步初始化与读库窗口不再纯背景）。运行期点会话卡进页该键恒 false——转场中
// 不闪图标；与 freshEntry 的分工 = 彼认「本地新造」，本键只认「启动落点」。
export const CHAT_LAUNCH_HANDOFF_KEY: string = 'chatLaunchHandoffPending';

// 待发分享件条目（纯接口零 import——本件叶子纪律）：uri 非空 = 文件件（title = 文件名，
// 可空→消费侧从 uri 尾段兜底提取）；uri 空 = 文本/链接件（content 必非空，进输入框）；
// utd 仅供取证日志，类型判定以文件名扩展名单源（classifyByName，与选择器入口同判据）
export interface PendingSharedItem {
  uri: string;
  title: string;
  utd: string;
  content: string;
}
