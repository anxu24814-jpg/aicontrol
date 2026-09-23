// 二级页路由注册表 builder（2026-08-29 M3 拆分，HomeNavigation 398 行触 400 红线——按
// dshinhm PageMapBuilder.ets 先例迁 PageMap 域；拍板 = 任务书 M3 第 2 条）：PageMap 分支链
// 自 HomeNavigation 迁出为全局 @Builder 函数 buildPageMap（官方支持全局 @Builder 复用；
// 组件构造不依赖 build 上下文，无 DSL 手势工厂风险）。
// 挂载契约（坑51 死规矩，dshinhm 真机事故沉淀）：navDestination 必须挂「组件内 @Builder
// 方法」（HomeNavigation.PageMap，由它调用本函数注入 pathStack/topPad 等）——禁止把
// navDestination 直接挂成「箭头 lambda 内调本全局函数」，该姿势运行时框架拿不到 UI 节点：
// 「Builder function is empty / can't find name in config file」、全部二级页白屏。
//
// 路由注册硬性约定（违反即生产事故，勿改）：
//   · 分支必须 if/else if 链——独立 if 多分支时「最后一个分支」页面组件被实例化但
//     NavDestination 不挂载（navdestinationId:-1：页面空白 + 返回键直接退出应用）；
//   · 分支顺序与设置页（SettingsPage）显示顺序保持一致，新增页面时两处同步追加；
//   · 新增页面 = 本文件链尾加 else if + 设置页/入口页加条目 + SettingSearch 注册表加条目
//     （若含可搜索设置项，三处同步，见 dshinhm docs/设置项搜索规范.md；★ 会话搜索二级页
//     ROUTE_SESSION_SEARCH_PAGE 是例外 = 非设置项，只两处同步〔本文件 + RouteNames〕）；
//   · 分支名一律引用 common/RouteNames.ets 的 ROUTE_* 常量（禁止裸字符串——拼错编译期即报）；
//   · 可搜项 pageName 与注册表由 scripts/setting-search-check.mjs 机械校验（交付前跑）。
// 页内铺底层（2026-08-29 M3 换装）：各分支原「Column 挂 page_bg 实色」（M2a 轮 6 定稿——
// 根透明 + 页内铺底提供不透明性）换装 PageBackground 壁纸组件（轮 6 注释预留位兑现）：
// 自定义背景图写入 AppStorage['pageBg'] 后全部页面自动跟随；默认态 = page_bg 纯色（深浅
// 色自动），与原实色行为一致；根保持透明 = 坑38 转场圆角语义不变。
// 编辑图片两页（ImageEditPage/ImageAdjustPage，M3 任务 2 迁入）例外：PageShell 传
// bgSolid=true 强制纯色（预览框叠壁纸看不清，PageBackground 头注释）。
import { ChatPage } from '../chat/ChatPage';
import { SessionSearchPage } from '../chat/SessionSearchPage';
import { SettingsPage } from '../settings/SettingsPage';
import { ProviderPage } from '../settings/ProviderPage';
import { ProviderSortPage } from '../settings/ProviderSortPage';
import { ProviderDetailPage } from '../settings/ProviderDetailPage';
import { ModelEditPage } from '../settings/ModelEditPage';
import { AppearancePage } from '../settings/AppearancePage';
import { InfoPage } from '../settings/InfoPage';
import { SearchPage } from '../settings/SearchPage';
import { PromptLibraryPage } from '../settings/PromptLibraryPage';
import { PromptEditPage } from '../settings/PromptEditPage';
import { SystemPromptPage } from '../settings/SystemPromptPage';
import { DataSyncPage } from '../settings/DataSyncPage';
import { FunctionalModelPage } from '../settings/FunctionalModelPage';
import { PreferencesPage } from '../settings/PreferencesPage';
import { AssistantEditPage } from '../assistants/AssistantEditPage';
import { AssistantSortPage } from '../assistants/AssistantSortPage';
import { AssistantPromptPage } from '../assistants/AssistantPromptPage';
import { ModelSettingsPage } from '../assistants/ModelSettingsPage';
import { AssistantKnowledgePage } from '../assistants/AssistantKnowledgePage';
import { KnowledgeLibraryPage } from '../settings/KnowledgeLibraryPage';
import { KnowledgeBookPage } from '../settings/KnowledgeBookPage';
import { KnowledgeEditPage } from '../settings/KnowledgeEditPage';
import { KnowledgeFileEditPage } from '../settings/KnowledgeFileEditPage';
import { AssistantAdvancedPage } from '../assistants/AssistantAdvancedPage';
import { AssistantSamplingPage } from '../assistants/AssistantSamplingPage';
import { AssistantContextPage } from '../assistants/AssistantContextPage';
import { AssistantToolsPage } from '../assistants/AssistantToolsPage';
import { ImageEditPage } from '../ImageEditPage';
import { ImageAdjustPage } from '../ImageAdjustPage';
import { AboutPage } from '../AboutPage';
import { PermissionPage } from '../PermissionPage';
import { AiAssistPage } from '../AiAssistPage';
import { OpenSourcePage } from '../OpenSourcePage';
import { PrivacyPolicyPage } from '../PrivacyPolicyPage';
import { FeedbackPage } from '../FeedbackPage';
import { HelpCenterPage } from '../settings/HelpCenterPage';
import { HelpTopicPage } from '../settings/HelpTopicPage';
import { UsageStatsPage } from '../settings/UsageStatsPage';
import { CostStatsPage } from '../settings/CostStatsPage';
import { MemoryPage } from '../settings/MemoryPage';
import { MemoryEditPage } from '../settings/MemoryEditPage';
import { MemorySortPage } from '../settings/MemorySortPage';
import { MemoryLibraryPage } from '../settings/MemoryLibraryPage';
import { MemoryHistoryPage } from '../settings/MemoryHistoryPage';
import { MemorySnapshotPage } from '../settings/MemorySnapshotPage';
import { MemoryImportPage } from '../settings/MemoryImportPage';
import { AssistantMemoryPage } from '../assistants/AssistantMemoryPage';
import { StoragePage } from '../settings/StoragePage';
import { AttachmentManagePage } from '../settings/AttachmentManagePage';
import { SearchEnginePage } from '../settings/SearchEnginePage';
import { SearchEngineDetailPage } from '../settings/SearchEngineDetailPage';
import { ToolsSettingsPage } from '../settings/ToolsSettingsPage';
import { ProactivePage } from '../settings/ProactivePage';
import { PriceTemplatePage } from '../settings/PriceTemplatePage';
import { PriceTemplateEditPage } from '../settings/PriceTemplateEditPage';
import { BalanceConfigPage } from '../settings/BalanceConfigPage';
import { SkillLibraryPage } from '../settings/SkillLibraryPage';
import { SkillEditPage } from '../settings/SkillEditPage';
import { SkillFileEditPage } from '../settings/SkillFileEditPage';
import { AttachmentViewerPage } from '../chat/AttachmentViewerPage';
import { AssistantSkillPage } from '../assistants/AssistantSkillPage';
import { LogPage } from '../LogPage';
import { ReqLogPage } from '../ReqLogPage';
import {
  ROUTE_CHAT_PAGE,
  ROUTE_PROVIDER_PAGE,
  ROUTE_PROVIDER_SORT_PAGE,
  ROUTE_PROVIDER_DETAIL_PAGE,
  ROUTE_MODEL_EDIT_PAGE,
  ROUTE_APPEARANCE_PAGE,
  ROUTE_IMAGE_EDIT_PAGE,
  ROUTE_IMAGE_ADJUST_PAGE,
  ROUTE_INFO_PAGE,
  ROUTE_ABOUT_PAGE,
  ROUTE_PERMISSION_PAGE,
  ROUTE_AI_ASSIST_PAGE,
  ROUTE_OPEN_SOURCE_PAGE,
  ROUTE_PRIVACY_POLICY_PAGE,
  ROUTE_HELP_CENTER_PAGE,
  ROUTE_HELP_TOPIC_PAGE,
  ROUTE_LOG_PAGE,
  ROUTE_REQ_LOG_PAGE,
  ROUTE_SEARCH_PAGE,
  ROUTE_PROMPT_LIBRARY_PAGE,
  ROUTE_PROMPT_EDIT_PAGE,
  ROUTE_DATA_SYNC_PAGE,
  ROUTE_FUNCTIONAL_MODEL_PAGE,
  ROUTE_SYSTEM_PROMPT_PAGE,
  ROUTE_ASSISTANT_EDIT_PAGE,
  ROUTE_ASSISTANT_SORT_PAGE,
  ROUTE_ASSISTANT_PROMPT_PAGE,
  ROUTE_MODEL_SETTINGS_PAGE,
  ROUTE_PREFERENCES_PAGE,
  ROUTE_ASSISTANT_ADVANCED_PAGE,
  ROUTE_ASSISTANT_SAMPLING_PAGE,
  ROUTE_ASSISTANT_CONTEXT_PAGE,
  ROUTE_ASSISTANT_TOOLS_PAGE,
  ROUTE_USAGE_STATS_PAGE,
  ROUTE_COST_STATS_PAGE,
  ROUTE_FEEDBACK_PAGE,
  ROUTE_SESSION_SEARCH_PAGE,
  ROUTE_MEMORY_PAGE,
  ROUTE_MEMORY_EDIT_PAGE,
  ROUTE_MEMORY_SORT_PAGE,
  ROUTE_MEMORY_LIBRARY_PAGE,
  ROUTE_MEMORY_HISTORY_PAGE,
  ROUTE_MEMORY_SNAPSHOT_PAGE,
  ROUTE_MEMORY_IMPORT_PAGE,
  ROUTE_ASSISTANT_MEMORY_PAGE,
  ROUTE_STORAGE_PAGE,
  ROUTE_ATTACHMENT_MANAGE_PAGE,
  ROUTE_SEARCH_ENGINE_PAGE,
  ROUTE_SEARCH_ENGINE_DETAIL_PAGE,
  ROUTE_TOOLS_PAGE,
  ROUTE_PROACTIVE_PAGE,
  ROUTE_PRICE_TEMPLATE_PAGE,
  ROUTE_PRICE_TEMPLATE_EDIT_PAGE,
  ROUTE_BALANCE_CONFIG_PAGE,
  ROUTE_SKILL_LIBRARY_PAGE,
  ROUTE_KNOWLEDGE_LIBRARY_PAGE,
  ROUTE_KNOWLEDGE_BOOK_PAGE,
  ROUTE_KNOWLEDGE_EDIT_PAGE,
  ROUTE_KNOWLEDGE_FILE_EDIT_PAGE,
  ROUTE_ASSISTANT_KNOWLEDGE_PAGE,
  ROUTE_SKILL_EDIT_PAGE,
  ROUTE_ASSISTANT_SKILL_PAGE,
  ROUTE_SKILL_DESIGNATE_PAGE,
  ROUTE_SKILL_FILE_EDIT_PAGE,
  ROUTE_ATTACHMENT_VIEWER_PAGE
} from '../../common/RouteNames';

// 页面路由表：官方 navDestination 注册（NavPathStack push 的 name 在此映射到组件）。
// param 为路由参数（d.ts 声明 unknown，ArkTS 禁 any/unknown 故用 Object，官方示例同款）。
// pathStack/topPad/bottomPad = HomeNavigation.PageMap 注入（topPad 已按 hdsAvailable 归一——
// HDS = 状态栏+标题栏+蒙层，回退 = 0；2026-09-07 直壳迁 PageShell 后档位参数不再入参，
// 标题栏材质由各页 PageShell 内部 @StorageProp 自订阅）；
// activeConvId = 对话页目标会话（HomeNavigation push 前写定，构建时读值）；
// activePrivate = 对话页隐私模式标记（2026-09-04，HomeNavigation 写定——push/replace 均
// 读同一位，页内「新建会话」replacePath 自然继承隐私态）；
// openSession = 打开会话编排回调（2026-09-08 会话搜索二级页注入，HomeNavigation.PageMap
// 闭包直传本组件方法 openSession——捕获 this 合法，坑51 只禁 lambda 直挂 navDestination）。
// ★ 为何会话搜索页不自接 pushPathByName(ROUTE_CHAT_PAGE, id)：ChatPage 的 isPrivate =
// 本函数构造时读 activePrivate 快照，该值只在 HomeNavigation.openSession/newConversation
// 复位 false——隐私会话 pop 后残留 true，绕过 openSession 直 push 会把普通会话误开隐私
// 模式；且 ChatPage 页内「新建会话」replacePathByName 同样带 string param（隐私态需继承），
// 分支内无法区分两种来源，不能以「param string → isPrivate false」取巧。经 openSession
// 上行 = 复位 + 写 activeConvId + push 一步到位，隐私 bug 从结构上消除。
@Builder
export function buildPageMap(name: string, param: Object, pathStack: NavPathStack, topPad: number,
  bottomPad: number, activeConvId: string, activePrivate: boolean,
  openSession: (conversationId: string) => void) {
  if (name === ROUTE_CHAT_PAGE) {
    // 对话页（2026-08-29 对话页 UI 对齐任务 4 起自包 PageShell 壳——标题覆盖层/双键菜单/
    // 半模态须页面自持，PageMap 壳无法回传，拍板 4；同 LogPage 先例薄构造）：
    // param = 会话 id（新建会话 replacePathByName 传入；null/缺省 = 既有 push 链路的
    // HomeNavigation.activeConvId）；pop/replace 后会话列表重拉广播在页面 aboutToDisappear
    ChatPage({
      conversationId: typeof param === 'string' && param !== '' ? param : activeConvId,
      isPrivate: activePrivate,
      topPad: topPad,
      bottomPad: bottomPad,
      pathStack: pathStack
    })
  } else if (name === ROUTE_PROVIDER_PAGE) {
    // 服务商管理列表页（设置页行卡 push；2026-08-30 反馈轮 2 起自包 PageShell 壳——
    // onShown 刷新键 + 标题栏菜单须页面自持（栈下层 @StorageProp 不刷新，刷新主通道
    // = onShown）；本分支薄构造同 LogPage 先例
    ProviderPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROVIDER_SORT_PAGE) {
    // 服务商排序三级页（2026-08-30 反馈轮 6，领导方案——管理页摘拖拽（坑10 浮起被列表
    // 内容区裁切），排序独立成页：窄卡仅长按排序、无点击编辑与信息展示；pop 后管理页
    // 经 onPop 重拉新序——排序页 onBackPressed → pop 带 result（坑17），管理页手动
    // 「刷新」键仍作兜底）
    ProviderSortPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROVIDER_DETAIL_PAGE) {
    // 服务商详情三级页（2026-08-30 服务商管理域；自包 PageShell 壳——标题动态 + 标题栏
    // 「保存」键须页面自持，ChatPage/LogPage 同款薄构造先例）；push 参数页面内 getParamByName 取
    ProviderDetailPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_MODEL_EDIT_PAGE) {
    // 编辑模型四级页（2026-08-30 服务商管理域；自包 PageShell 壳——标题「添加/编辑模型」
    // 动态 + 标题栏「保存」键）；push 参数 ModelEditParam 页面内取
    ModelEditPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_FUNCTIONAL_MODEL_PAGE) {
    // 功能模型二级页（2026-09-05：设置页「功能模型」卡 push——功能级模型配置集中页，
    // 首项「默认模型」= 发送链四级兜底第③级来源；同日决明调序卡片移到服务商管理下，
    // 分支随「与设置页显示顺序一致」惯例搬至服务商域后）：自包 PageShell 壳（含模型
    // 选择半模态，ModelSettingsPage 同款自包形态）；选择即时写键无保存动作，push 无参
    FunctionalModelPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_APPEARANCE_PAGE) {
    // 外观显示二级页（M3 起含「光感/背景」分段——BackgroundPanel 迁入）：自包 PageShell 壳
    //（2026-09-07 迁——原 PageMapBuilder 直壳 titleBar 为入栈快照，本页调档位后返回键材质
    // 不实时刷新，须返回重进才生效（决明真机反馈）；PageShell 内部 @StorageProp 自订阅标题
    // 栏档位材质，实时跟随，与其余二级页一致）；pathStack 传入：背景面板「选择图片/编辑
    // 图片」push 编辑二级页（同一路由栈）；initialTab = 搜索结果跳转指定分段（0 光感 /
    // 1 背景），普通进入传 null 默认 0（坑44：@State 初始化器先于父组件传参，页面内
    // aboutToAppear 赋值）
    AppearancePage({
      topPad: topPad,
      bottomPad: bottomPad,
      pathStack: pathStack,
      initialTab: typeof param === 'number' ? param : 0
    })
  } else if (name === ROUTE_IMAGE_EDIT_PAGE) {
    // 图片编辑裁剪二级页（M3，从「外观显示」背景面板两入口进入）。编辑对象经 push 参数
    // EditImageParam.srcUri 传入（选择图片 = 新选图临时文件 / 编辑图片 = 当前背景），页面自行
    // getParamByName 取，本分支不消费 param。自包 PageShell 壳（含 bgSolid=true 强制纯色例外
    // ——预览框叠壁纸看不清）；pathStack：「下一步」push 调整页 / 空背景·解码失败时 pop 返回
    ImageEditPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_IMAGE_ADJUST_PAGE) {
    // 图片编辑调整二级页（M3）：裁剪页「下一步」push 入栈，保存后 popToName 一次弹两级
    // 退出编辑（见 ImageAdjustPage.ets 头注释）；自包 PageShell 壳（bgSolid=true）
    ImageAdjustPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_INFO_PAGE) {
    // 更多信息二级页：自包 PageShell 壳（2026-09-07 迁——原 PageMapBuilder 直壳 titleBar 为
    // 入栈快照，档位变化不实时刷新，与外观页同病同修）；pathStack 传入——「关于」「运行
    // 日志」与 2026-09-07 迁入的「权限信息」「隐私政策」行卡 push 下级页（同一路由栈，
    // 官方系统级转场）
    InfoPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ABOUT_PAGE) {
    // 「关于」三级页（M3，从更多信息页进入）；pathStack 传入：「AI 辅助开发声明」卡片
    // push 下级页（同一路由栈）；自包 PageShell 壳
    AboutPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_PERMISSION_PAGE) {
    // 「权限信息」页（M3，2026-09-07 起从更多信息页行卡进入）；纯展示无下级跳转，
    // 不传 pathStack；自包壳
    PermissionPage({ topPad: topPad })
  } else if (name === ROUTE_AI_ASSIST_PAGE) {
    // 「AI 辅助开发声明」页（M3，从关于页进入）；纯展示无下级跳转；自包壳
    AiAssistPage({ topPad: topPad })
  } else if (name === ROUTE_OPEN_SOURCE_PAGE) {
    // 「开源项目鸣谢」页（2026-09-02，从关于页进入）；纯展示无下级跳转；自包壳
    OpenSourcePage({ topPad: topPad })
  } else if (name === ROUTE_LOG_PAGE) {
    // 「运行日志」三级页（M3，从更多信息页进入）：自包 PageShell 壳（含右上角「更多」
    // 菜单——action 绑页面方法，壳在此无法回传，dshinhm PageShell 同款自包形态）；
    // 崩溃订阅在 EntryAbility 进程级（拍板 6），页面刷新经共享 holder 拉取
    LogPage({ topPad: topPad })
  } else if (name === ROUTE_REQ_LOG_PAGE) {
    // 「请求日志」三级页（2026-09-23 请求日志笔，从更多信息页进入）：自包 PageShell 壳
    //（含右上角「更多」菜单与半模态详情面板宿主——action 与 bindSheet 都绑页面方法，壳在此
    // 无法回传，LogPage 同款自包形态）；数据源 = 进程内内存环形缓冲（common/ReqLog.ets）
    ReqLogPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_SEARCH_PAGE) {
    // 搜索页（M2c）：自包壳（HdsNavDestination/NavDestination 双分支在页面内）——标题栏
    // stackBuilder 搜索框依赖页面 keyword 状态，壳在此无法把 builder 传回标题栏（dshinhm
    // PageShell 已验证形态，改道理由见 SearchPage 头注释与 PROGRESS.md M2c 风险①）
    SearchPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SYSTEM_PROMPT_PAGE) {
    // 系统提示词独立页（2026-08-31：与会话提示词分开——库页不显示、独立页管理、内置默认
    // 可更改可重置；设置页行卡/搜索条目 push 无参；自包壳（右上角无菜单键 + 底部恢复/保存）
    SystemPromptPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_DATA_SYNC_PAGE) {
    // 「数据与同步」二级页（2026-09-03 第三批③：全量导入导出 + WebDAV；设置页行卡/搜索
    // 条目 push 无参；自包 PageShell 壳）
    DataSyncPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROMPT_LIBRARY_PAGE) {
    // 「提示词」管理页（2026-08-30 提示词注入；设置页行卡进入）：自包 PageShell 壳
    //（含右上角「新增」菜单——动作绑页面方法，壳无法回传，照 LogPage 同款自包形态）
    PromptLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROMPT_EDIT_PAGE) {
    // 「提示词」编辑页（2026-08-30 提示词注入；管理页 push）：自包壳（param = 模板 id）
    PromptEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_EDIT_PAGE) {
    // 助手编辑二级页（2026-09-01 助手域；助手页签列表卡点击 push）：自包 PageShell 壳
    //（纯分区导航枢纽——名称行卡弹重命名 + 提示词/记忆/工具调用/技能/知识库/高级设定
    // 六分区卡，底部无按钮）；param = 助手 id（恒编辑态——新建走列表页「＋」对话框）页面内
    // getParamByName 取（ModelEditPage 同款取参姿势）
    AssistantEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_SORT_PAGE) {
    // 助手排序三级页（2026-09-22 助手自定义列表序——ProviderSortPage/MemorySortPage
    // 同构：List + ForEach.onMove 拖拽落定即回写 sortOrder；onBackPressed pop 带 result
    // 触发助手页经指令键重拉新卡序，坑17。无 push 参数——本页恒排序全量助手）
    AssistantSortPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_PROMPT_PAGE) {
    // 助手提示词三级页（2026-09-01 分区化；编辑页「提示词」分区卡 push）：自包 PageShell
    // 壳（用户手建 = SystemPromptPage 同款表单 / 内置默认助手 = 只读展示）；param = 助手
    // id 页面内 getParamByName 取
    AssistantPromptPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MODEL_SETTINGS_PAGE) {
    // 助手模型设置三级页（2026-09-01 模型绑定；编辑页「模型设置」首卡 push）：自包
    // PageShell 壳——单卡（上部绑定显示 + 下部双键）；param = 助手 id 页面内取
    ModelSettingsPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_ADVANCED_PAGE) {
    // 助手高级设定二级页（2026-09-01 高级设定；编辑页「高级设定」分区卡 push）：自包
    // PageShell 壳——两行卡（采样参数/上下文与输出，onPop 刷摘要）；param = 助手 id
    AssistantAdvancedPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_SAMPLING_PAGE) {
    // 助手采样参数三级页（2026-09-01 高级设定；二级页「采样参数」行卡 push）：自包
    // PageShell 壳——四开关卡（开 → 卡内展开官方 InSet 滑块）；param = 助手 id
    AssistantSamplingPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_CONTEXT_PAGE) {
    // 助手上下文与输出三级页（2026-09-01 高级设定；二级页「上下文与输出」行卡 push）：
    // 自包 PageShell 壳——两滑块卡（上下文消息数/最大输出长度 + 编辑键数字弹窗）；
    // param = 助手 id
    AssistantContextPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_TOOLS_PAGE) {
    // 助手工具页签三级页（2026-09-02 工具调用底层；编辑页「工具调用」分区卡 push）：
    // 自包 PageShell 壳——注册表全量工具开关卡（Toggle 即时落库 assistants.tools 列）；
    // param = 助手 id 页面内取
    AssistantToolsPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PREFERENCES_PAGE) {
    // 偏好设置二级页（2026-09-01 领导指令：设置页「会话提示词」卡后新增——偏好项集中页，
    // 首项「默认展开思考」）：自包 PageShell 壳（2026-09-07 迁——原直壳 titleBar 为入栈
    // 快照，与外观页同病同修）；开关即改即持久化（AppStorage persistProp），无保存动作 →
    // 返回无参 pop 不挂 onPop（坑17 口径「无数据变化不加 result」），push 无参
    PreferencesPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PRIVACY_POLICY_PAGE) {
    // 「隐私政策」页（2026-09-02 新增；2026-09-07 起从更多信息页行卡进入——上架合规
    // 入口）；纯展示无下级跳转，不传 pathStack；自包壳（PageShell）
    PrivacyPolicyPage({ topPad: topPad })
  } else if (name === ROUTE_HELP_CENTER_PAGE) {
    // 「帮助中心」页（2026-09-05 新增；更多信息页行卡 push——分板块卡片说明功能与用法）：
    // 2026-09-05 二级页化起条目卡可点进详情，pathStack 传入（条目 push 帮助条目详情页）；
    // 自包壳（PageShell）
    HelpCenterPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_HELP_TOPIC_PAGE) {
    // 「帮助条目详情」页（2026-09-05 二级页化新增；帮助中心页条目卡 push——单条功能的
    // 详细用法说明）：param = 条目 id 页面内 getParamByName 取（MemoryLibraryPage 同款
    // 姿势）；纯展示无下级跳转，pathStack 仅用于读参；自包壳（PageShell）
    HelpTopicPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_USAGE_STATS_PAGE) {
    // 「用量统计」页（2026-09-06 token 用量统计；设置页「用量统计」行卡 push——概览六
    // 数字/按模型/近30天逐日纯列表）：无编辑无保存动作 → 返回无参 pop 不挂 onPop
    //（坑17 口径），push 无参；自包壳（PageShell）
    UsageStatsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_COST_STATS_PAGE) {
    // 「费用估计」页（2026-09-10 方案-费用估计；设置页「用量统计+费用估计」组卡第二行
    // push 无参——模型价格 × token 用量折算估算，三卡随时段胶囊联动）：无编辑无保存
    // 动作 → 返回无参 pop 不挂 onPop（坑17 口径），不传 pathStack（无下级跳转）；
    // 自包壳（PageShell）
    CostStatsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_FEEDBACK_PAGE) {
    // 「反馈与建议」页（2026-09-07 MeoW 反馈通道：更多信息页行卡 push〔帮助中心行卡
    // 下方，同日自关于页卡片移入〕——反馈文本经第三方
    // 推送服务 api.chuckfang.com 直达开发者手机，零自有服务器）：纯表单无保存态、无
    // 下级跳转 → 返回无参 pop 不挂 onPop（坑17 口径），push 无参；自包壳（PageShell）
    FeedbackPage({ topPad: topPad })
  } else if (name === ROUTE_SESSION_SEARCH_PAGE) {
    // 会话搜索二级页（2026-09-08 会话搜索改版：搜索 UI 自 ChatSessionList 一级页内嵌态
    // 迁独立页——决明指令「同设置搜索点击 push 二级页」；SearchPage 同构自包壳：HDS 路径
    // 搜索框经 stackBuilder 嵌标题栏〔依赖页面 keyword 状态，壳无法回传——SearchPage 头
    // 注释改道理由同款〕/ 回退路径搜索框在内容区顶部）。范围 = 当前助手名下全部会话标题
    //（列表页分段/收藏域不随迁）；打开会话必走 openSession 回调（隐私复位语义见函数头
    // 注释——★ 禁在本分支改成直 push ROUTE_CHAT_PAGE）
    SessionSearchPage({
      topPad: topPad,
      bottomPad: bottomPad,
      onOpenSession: openSession
    })
  } else if (name === ROUTE_MEMORY_PAGE) {
    // 「记忆」二级页（2026-09-08 记忆域；设置页「记忆」卡 push 无参——跨会话长期记忆
    // 管理：两开关 + 条目列表 + 添加/编辑/删除/立即整理；写操作即时落库无保存动作 →
    // 返回无参 pop 不挂 onPop（坑17 口径）；自包壳（PageShell，标题栏「＋」新建键与
    // 「⋯」更多菜单两键——排序/立即整理/优化记忆三项在「更多」菜单里，2026-09-13）
    MemoryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROACTIVE_PAGE) {
    // 「主动消息」二级页（2026-09-12 主动消息第一笔「触发链底层」；设置页「主动消息」
    // 单行卡 push 无参——总开关 + 触发间隔两行组卡 + 说明小字；写操作即时持久化 →
    // 返回无参 pop 不挂 onPop（坑17 口径）；自包 PageShell 壳，无标题栏菜单键
    ProactivePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_EDIT_PAGE) {
    // 记忆编辑三级页（2026-09-08 决明指令：取消记忆新增弹窗，添加/编辑一律进二级页——
    // 形制对齐会话提示词编辑页 PromptEditPage；记忆页「＋」新建键 push 空参 / 点条目卡 push
    // 记忆 id）：自包 PageShell 壳（标题栏「保存」键）；param 页面内 getParamByName 取，
    // 保存成功 pop({saved:true}) 触发记忆页 onPop 重拉（坑17）
    MemoryEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_SORT_PAGE) {
    // 记忆排序三级页（2026-09-12 记忆自定义注入顺序——ProviderSortPage 同构：List +
    // ForEach.onMove 拖拽落定即回写 sortOrder；onBackPressed pop 带 result 触发记忆页
    // onPop 重拉新卡序，坑17）
    MemorySortPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_LIBRARY_PAGE) {
    // 记忆库管理三级页（2026-09-20 助手级记忆：设置记忆页一级改分库列表后点库卡 push——
    // param = { libraryId }（'global' = 全局库 / 助手 id = 助手库）页面内 getParamByName 取；
    // 条目管理面自 MemoryPage 整体迁入（列表/增删改/排序/立即整理/优化，操作面跟库走），
    // 保存/排序 pop({saved:true}) 触发本页 onPop 重拉（坑17）
    MemoryLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_HISTORY_PAGE) {
    // 记忆历史三级页（2026-09-22 记忆优化历史：库管理页「更多」菜单「记忆历史」项 push——
    // param = { libraryId } 复用 MemoryLibraryParam，页面内 getParamByName 取；列出该库最近的
    // 改动前快照（优化前 / 导入前两类共用一份配额）+ 一份恢复前兜底，行卡右侧恢复键整库回退
    //（确认弹窗后落库）；自包 PageShell 壳，无标题栏菜单键
    MemoryHistoryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_SNAPSHOT_PAGE) {
    // 记忆快照详情三级页（2026-09-22 记忆优化历史：历史页点行卡 push——param =
    // MemorySnapshotParam{snapshotId} 页面内 getParamByName 取；只读列出该版条目，**不设
    // 恢复键**（恢复入口唯一在列表行卡）；自包 PageShell 壳，无标题栏菜单键
    MemorySnapshotPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_IMPORT_PAGE) {
    // 记忆导入三级页（2026-09-22 记忆导入：库管理页「更多」菜单「从其他平台导入」项 push——
    // param = { libraryId }（MemoryImportParam，声明单源在发起方 MemoryLibraryPage.ets），
    // 页面内 getParamByName 取；三态单页 = 粘贴外部平台输出 → AI 整理 → 预览确认后事务化
    // 批量落库（写入前自动存一份「导入前」快照）；自包 PageShell 壳，无标题栏菜单键
    MemoryImportPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_MEMORY_PAGE) {
    // 助手记忆三级页（2026-09-08 记忆域；助手编辑页「记忆」分区卡 push）：自包 PageShell
    // 壳——注入/沉淀两开关行（即时落库）；param = 助手 id 页面内 getParamByName 取；
    // 开关即改即生效，编辑页卡面摘要经编辑页自身 onPop 重拉（本页返回带 result）
    AssistantMemoryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_STORAGE_PAGE) {
    // 「存储管理」二级页（2026-09-09 附件全量落盘第二轮；设置页「数据与同步+存储管理」
    // 组卡内第二行 push
    // 无参——六分类占用展示 + 可安全清理）：无编辑无保存动作 → 返回无参 pop 不挂 onPop
    //（坑17 口径）；★ 2026-09-15 附件管理列表笔起传 pathStack（页内卡3「会话附件」入口卡
    // push 附件管理页——原「无下级跳转」注释随本笔作废）；自包壳（PageShell）
    StoragePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ATTACHMENT_MANAGE_PAGE) {
    // 「附件管理」三级页（2026-09-15 附件管理列表笔；存储管理页「会话附件」卡 push 无参
    //——按会话分组列出已发送附件，展开可预览与单件删）：无编辑无保存动作 → 返回无参 pop
    // 不挂 onPop（坑17 口径）；★ 2026-09-15 查看器二级页化笔起传 pathStack（行点击的查看器
    // 自全屏模态改导航栈内二级页 push——原「页内查看器是覆盖层非下级页」注释随本笔作废）；
    // 自包壳
    AttachmentManagePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SEARCH_ENGINE_PAGE) {
    // 「联网搜索」二级页·引擎列表（2026-09-10 多引擎一期；同日 UI 重构对齐服务商管理：
    // 设置页「联网搜索+工具调用」两行主卡首行 push 无参——总开关 + 分段胶囊已启用/已停用
    // + 引擎卡列表，点卡片 push 引擎配置三级页）：写操作即时持久化无保存动作 → 返回无参
    // pop 不挂 onPop（坑17 口径）；自包壳（PageShell）；传 pathStack（点卡片下探）
    SearchEnginePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SEARCH_ENGINE_DETAIL_PAGE) {
    // 「引擎配置」三级页（2026-09-10 UI 重构对齐服务商管理：列表页点引擎卡 push，param =
    // 引擎 id 页面内 getParamByName 取——启停/设当前/密钥与 baseUrl/测试搜索）：写偏好
    // 即时生效，列表页经 @StorageLink 订阅自动刷新无需 onPop；自包壳（PageShell）
    SearchEngineDetailPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_TOOLS_PAGE) {
    // 「工具调用」二级页（2026-09-10 决明指令：设置页「联网搜索+工具调用」两行主卡第二行
    // push 无参——先空占位，后续承载内置工具全局设置）：无编辑无保存动作 → 返回无参 pop
    // 不挂 onPop（坑17 口径）；自包壳（PageShell）
    ToolsSettingsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PRICE_TEMPLATE_PAGE) {
    // 「价格模板」二级页·模板列表（2026-09-11 价格模板；服务商编辑页高级页签卡 push，param
    // = providerId 页面内 getParamByName 取）：自包 PageShell 壳（标题栏「添加」键）；子页
    // 保存/删除 pop 带 result → 本页 onPop 重拉（坑17）；★ 非设置项不进搜索注册表（两处
    // 同步 = RouteNames + 本文件）
    PriceTemplatePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PRICE_TEMPLATE_EDIT_PAGE) {
    // 「价格模板」三级页·模板编辑（2026-09-11 价格模板；列表页点行卡/「添加」键 push，param
    // = PriceTemplateEditParam{providerId, templateId} 页面内取）：自包 PageShell 壳（标题栏
    // 「保存」键 + 编辑态底部删除键）；复用 ModelPriceCard 同一张价格卡，保存/删除 pop 带
    // result 触发列表页 onPop 重拉（坑17）
    PriceTemplateEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_BALANCE_CONFIG_PAGE) {
    // 「余额查询」二级页·配置（2026-09-11 方案 v3 余额配置二级页化；服务商编辑页高级
    // 页签「余额查询」入口卡 push，param = BalanceConfigParam{providerId} 页面内
    // getParamByName 取）：自包 PageShell 壳（标题栏「保存」键复用 ProviderSaveMenu 工厂）；
    // 页内自保存 + 查询 pop 带 result → 入口页 onPop 自增 headEpoch 刷顶卡余额徽章（坑17）；
    // ★ 非设置项不进搜索注册表（两处同步 = RouteNames + 本文件）
    BalanceConfigPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SKILL_LIBRARY_PAGE) {
    // 「技能库」二级页（2026-09-13 技能层笔 1；设置页「技能库」行卡 push 无参 + 助手技能页
    // 「管理技能库」入口行 push 无参——技能清单 + 标题栏「＋新建」+ 行卡四点键菜单）：
    // 列表刷新 = SKILL_LIST_TICK_KEY 广播（SkillDb 增删改收口处递增）+ 子页 pop 带 result；
    // 传 pathStack（点行卡/「＋」下探技能编辑页）；自包 PageShell 壳
    SkillLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_LIBRARY_PAGE) {
    // 「知识库」二级页（2026-09-21 世界书知识库首版；设置页「指令面」组卡「知识库」行卡
    // push 无参 + 助手知识库页「管理知识库」入口行 push 无参——书名清单 + 标题栏「＋」单键
    // + 行卡四点键菜单（重命名/删除））：列表刷新 = KNOWLEDGE_LIST_TICK_KEY 广播（KnowledgeDb
    // 增删改收口处递增）+ 子页 pop 带 result；传 pathStack（点行卡下探条目清单页）；
    // 自包 PageShell 壳。★ 分支位次 = 紧邻技能库页——与 SettingsPage「指令面」组卡的行序
    //（系统提示词/提示词/技能库/知识库）一致，该件文件头的硬性约定
    KnowledgeLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_BOOK_PAGE) {
    // 「知识库条目清单」三级页（2026-09-21 世界书知识库首版；库页点行卡 push，param =
    // 书名 id（string）页面内 getParamByName 取）：自包 PageShell 壳——页标题 = 书名
    //（查询回填，查不到即返回上一页）+ 计数说明行 + 条目行卡（四点键菜单 = 删除）+ 标题栏
    // 「＋」单键（新建条目，达 KNOWLEDGE_ENTRY_MAX 拦截）；传 pathStack（点条目行/「＋」
    // 下探条目编辑页）；刷新 = 子页 pop 带 result 经 onPop 重拉（坑17）
    KnowledgeBookPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_EDIT_PAGE) {
    // 「知识库条目编辑」四级页（2026-09-21 世界书知识库首版，2026-09-23 文件笔改三段页签；
    // 清单页「＋」/点条目行 push，param = KnowledgeEditParam{bookId,entryId}（entryId '' =
    // 新建）页面内 getParamByName 取）：自包 PageShell 壳（标题栏「保存」键——校验失败 toast
    // 不静默）；保存成功 pop 带 result 触发清单页 onPop 重拉（坑17）；传 pathStack（文件卡
    // 下探条目附件编辑页）
    KnowledgeEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_FILE_EDIT_PAGE) {
    // 「知识库条目附件编辑」五级页（2026-09-23 知识库文件笔；条目编辑页文件卡 push，param =
    // KnowledgeFileEditParam 页面内 getParamByName 取）：自包 PageShell 壳（标题栏「保存」键 +
    // 编辑态底部删除键）；保存/删除成功 pop 带 result 触发文件卡 onPop 重拉（坑17）
    KnowledgeFileEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_KNOWLEDGE_PAGE) {
    // 助手知识库三级页（2026-09-21 世界书知识库首版；助手编辑页「知识库」分区卡 push）：
    // 自包 PageShell 壳——知识库开关组卡（即时落库）+「管理知识库」入口行；param = 助手 id
    // 页面内 getParamByName 取；开关即改即生效，编辑页卡面摘要经编辑页自身 onPop 重拉
    //（本页返回带 result）
    AssistantKnowledgePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SKILL_EDIT_PAGE) {
    // 「技能编辑」三级页（2026-09-13 技能层笔 1；库页「＋新建」push 空参 / 点行卡 push 技能
    // id，param = 技能 id 页面内 getParamByName 取）：自包 PageShell 壳（标题栏「保存」键）；
    // 保存/删除成功 pop 带 result 触发库页刷新（坑17）；四段卡见页面头注释
    SkillEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_SKILL_PAGE) {
    // 助手技能三级页（2026-09-13 技能层笔 1；助手编辑页「技能」分区卡 push）：自包
    // PageShell 壳——技能开关组卡（即时落库）+「管理技能库」入口行；param = 助手 id
    // 页面内 getParamByName 取；开关即改即生效，编辑页卡面摘要经编辑页自身 onPop 重拉
    //（本页返回带 result）
    AssistantSkillPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack,
      hostKind: 'assistant' })
  } else if (name === ROUTE_SKILL_DESIGNATE_PAGE) {
    // 技能选择页（2026-09-16 单条消息指定技能；对话页半模态「技能」卡单入口 push，param =
    // SkillDesignateParam{skillId} 页面内 getParamByName 取）：组件参数化复用
    // AssistantSkillPage（hostKind 'designate'）——全库可点，点一件即指定并返回（点当前行
    // = 取消并返回）+「管理技能库」行；点行即 pop 带 SkillDesignateResult{skillId,skillName}
    // → ChatPage onPop 写两 @State（坑17）；自包 PageShell 壳。★ 非设置项，不进搜索注册表
    //（两处同步 = RouteNames + 本文件）
    AssistantSkillPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack,
      hostKind: 'designate' })
  } else if (name === ROUTE_SKILL_FILE_EDIT_PAGE) {
    // 「技能附件编辑」四级页（2026-09-13 技能层笔 2；技能编辑页文件组卡 push，param =
    // SkillFileEditParam 页面内 getParamByName 取）：自包 PageShell 壳（标题栏「保存」键 +
    // 编辑态底部删除键）；保存/删除成功 pop 带 result 触发组卡 onPop 重拉（坑17）
    SkillFileEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ATTACHMENT_VIEWER_PAGE) {
    // 附件查看器二级页（2026-09-15 附件查看器二级页化；两宿主 push〔会话页附件泡/输入栏
    // 附件条 + 附件管理页行点击〕，param = AttachmentViewerParam{items,index} 页面内
    // getParamByName 取）：原全屏模态 bindContentCover 承载退役——改页面后顶部归官方 HDS
    // 标题栏（渐变模糊蒙层 + 沉浸光感材质）骑在内容之上，两模式默认不让内容进蒙层：图片
    // topPad 下发页件（1x 落标题栏下方、放大后可进蒙层）、文本走内容内层 padding（本参下发
    // 即此用）——均同日顶栏分享笔口径；底部零组件（原底栏随顶栏分享笔退役）。无编辑无保存
    // 动作 → 返回无参 pop 不挂 onPop（坑17 口径）；自包 PageShell 壳，标题栏右上角「分享」键
    // （官方菜单数组，构造在 AttachmentViewerPage）；底部零组件无避让需求，故本页不收
    // bottomPad；
    // ★ 非设置项不进搜索注册表（两处同步 = RouteNames + 本文件）
    AttachmentViewerPage({ topPad: topPad, pathStack: pathStack })
  }
}
