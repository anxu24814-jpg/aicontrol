// 二级页路由注册表 builder（PageMap 域自 HomeNavigation 拆出为全局 @Builder 函数，官方
// 支持全局 @Builder 复用）。
// 挂载契约（坑51 死规矩）：navDestination 必须挂「组件内 @Builder 方法」（HomeNavigation.
// PageMap，由它调用本函数注入 pathStack/topPad 等）——禁止把 navDestination 直接挂成
// 「箭头 lambda 内调本全局函数」，该姿势运行时框架拿不到 UI 节点，全部二级页白屏。
//
// 路由注册硬性约定（违反即生产事故，勿改）：
//   · 分支必须 if/else if 链——独立 if 多分支时「最后一个分支」页面组件被实例化但
//     NavDestination 不挂载（navdestinationId:-1：页面空白 + 返回键直接退出应用）；
//   · 分支顺序与设置页（SettingsPage）显示顺序保持一致，新增页面时两处同步追加；
//   · 新增页面 = 本文件链尾加 else if + 设置页/入口页加条目 + SettingSearch 注册表加条目
//     （若含可搜索设置项，三处同步；★ 非设置项页面不进搜索注册表，只两处同步
//     〔本文件 + RouteNames〕——下文各分支不再重复此条）；
//   · 分支名一律引用 common/RouteNames.ets 的 ROUTE_* 常量（禁止裸字符串——拼错编译期即报）；
//   · 可搜项 pageName 与注册表由 scripts/setting-search-check.mjs 机械校验（交付前跑）。
//   · 子页保存/删除成功 pop 带 result 触发父页 onPop 重拉（坑17 口径：无保存动作 → 返回
//     无参 pop 不挂 onPop）——下文各分支不再重复「（坑17）」。
// 页内铺底：各分支 PageBackground 壁纸组件铺底（自定义背景图写 AppStorage['pageBg'] 后
// 页面自动跟随；根保持透明 = 坑38 转场圆角语义不变）。图片编辑两页与待发图片裁剪页例外：
// PageShell 传 bgSolid=true 强制纯色（预览框叠壁纸看不清）。各二级页普遍自包 PageShell 壳（标题栏菜单/
// 动态标题/半模态须页面自持，壳无法回传——先例 LogPage；标题栏档位材质由各页 PageShell
// 内部 @StorageProp 自订阅）。
import { ChatPage } from '../chat/ChatPage';
import { SessionSearchPage } from '../chat/SessionSearchPage';
import { SettingsPage } from '../settings/SettingsPage';
import { ProviderPage } from '../settings/ProviderPage';
import { ProviderDetailPage } from '../settings/ProviderDetailPage';
import { ModelEditPage } from '../settings/ModelEditPage';
import { PrefBackgroundPage } from '../settings/PrefBackgroundPage';
import { PrefFontPage } from '../settings/PrefFontPage';
import { InfoPage } from '../settings/InfoPage';
import { SearchPage } from '../settings/SearchPage';
import { PromptLibraryPage } from '../settings/PromptLibraryPage';
import { PromptEditPage } from '../settings/PromptEditPage';
import { SystemPromptPage } from '../settings/SystemPromptPage';
import { DataSyncPage } from '../settings/DataSyncPage';
import { DsHistoryImportPage } from '../settings/DsHistoryImportPage';
import { FunctionalModelPage } from '../settings/FunctionalModelPage';
import { PreferencesPage } from '../settings/PreferencesPage';
import { PrefInputSendPage } from '../settings/PrefInputSendPage';
import { AutoRetrySettingsPage } from '../settings/AutoRetrySettingsPage';
import { PrefReplyDisplayPage } from '../settings/PrefReplyDisplayPage';
import { PrefSessionReadPage } from '../settings/PrefSessionReadPage';
import { PrefAppLaunchPage } from '../settings/PrefAppLaunchPage';
import { AssistantEditPage } from '../assistants/AssistantEditPage';
import { AssistantPageHost } from '../assistants/AssistantPageHost';
import { SettingsPageHost } from '../settings/SettingsPageHost';
import { AssistantPromptPage } from '../assistants/AssistantPromptPage';
import { AssistantKnowledgePage } from '../assistants/AssistantKnowledgePage';
import { KnowledgeLibraryPage } from '../settings/KnowledgeLibraryPage';
import { KnowledgeBookPage } from '../settings/KnowledgeBookPage';
import { KnowledgeEditPage } from '../settings/KnowledgeEditPage';
import { KnowledgeFileEditPage } from '../settings/KnowledgeFileEditPage';
import { AssistantAdvancedPage } from '../assistants/AssistantAdvancedPage';
import { AssistantSamplingPage } from '../assistants/AssistantSamplingPage';
import { AssistantContextPage } from '../assistants/AssistantContextPage';
import { AssistantToolsPage } from '../assistants/AssistantToolsPage';
import { AssistantMcpPage } from '../assistants/AssistantMcpPage';
import { ImageEditPage } from '../ImageEditPage';
import { ImageAdjustPage } from '../ImageAdjustPage';
import { PhotoEditPage } from '../PhotoEditPage';
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
import { MemoryLibraryPage } from '../settings/MemoryLibraryPage';
import { MemoryHistoryPage } from '../settings/MemoryHistoryPage';
import { MemorySnapshotPage } from '../settings/MemorySnapshotPage';
import { MemoryImportPage } from '../settings/MemoryImportPage';
import { AssistantMemoryPage } from '../assistants/AssistantMemoryPage';
import { StoragePage } from '../settings/StoragePage';
import { AttachmentManagePage } from '../settings/AttachmentManagePage';
import { QuickCleanPage } from '../settings/QuickCleanPage';
import { WorkspaceManagePage } from '../settings/WorkspaceManagePage';
import { DrawerSidePanel } from './DrawerSidePanel';
import { WorkspaceOcrPage } from '../settings/WorkspaceOcrPage';
import { MountManagePage } from '../settings/MountManagePage';
import { MountBrowsePage } from '../settings/MountBrowsePage';
import { SearchEnginePage } from '../settings/SearchEnginePage';
import { SearchEngineDetailPage } from '../settings/SearchEngineDetailPage';
import { ToolsSettingsPage } from '../settings/ToolsSettingsPage';
import { NetworkSettingsPage } from '../settings/NetworkSettingsPage';
import { WebServiceSettingsPage } from '../settings/WebServiceSettingsPage';
import { HttpRequestSettingsPage } from '../settings/HttpRequestSettingsPage';
import { McpPage } from '../settings/McpPage';
import { McpServerEditPage } from '../settings/McpServerEditPage';
import { HttpCredentialLibraryPage,
  HttpCredentialManagePage } from '../settings/HttpCredentialsPage';
import { HttpCredentialEditPage } from '../settings/HttpCredentialEditPage';
import { CodeWorkbenchPage, CodeHttpHostsLibraryPage,
  CodeHttpHostManagePage } from '../settings/CodeWorkbenchPages';
import { PyRuntimePage } from '../settings/PyRuntimePage';
import { NodeRuntimePage } from '../settings/NodeRuntimePage';
import { HttpTemplatePage, HttpTemplateEditPage } from '../settings/HttpTemplatePage';
import { ProactivePage } from '../settings/ProactivePage';
import { PriceTemplatePage } from '../settings/PriceTemplatePage';
import { PriceTemplateEditPage } from '../settings/PriceTemplateEditPage';
import { PriceTemplateProvidersPage } from '../settings/PriceTemplateProvidersPage';
import { BalanceConfigPage } from '../settings/BalanceConfigPage';
import { SkillLibraryPage } from '../settings/SkillLibraryPage';
import { SkillEditPage } from '../settings/SkillEditPage';
import { SkillFileEditPage } from '../settings/SkillFileEditPage';
import { AttachmentViewerPage } from '../chat/AttachmentViewerPage';
import { SessionTracePage } from '../chat/SessionTracePage';
import { SessionWorkspacePage } from '../chat/SessionWorkspacePage';
import { AssistantSkillPage } from '../assistants/AssistantSkillPage';
import { LogPage } from '../LogPage';
import { ReqLogPage } from '../ReqLogPage';
import { PyRuntimeProbePage } from '../../pages/PyRuntimeProbePage';
import { NodeRuntimeProbePage } from '../../pages/NodeRuntimeProbePage';
import {
  ROUTE_CHAT_PAGE,
  ROUTE_PROVIDER_PAGE,
  ROUTE_PROVIDER_DETAIL_PAGE,
  ROUTE_MODEL_EDIT_PAGE,
  ROUTE_PREF_BACKGROUND_PAGE,
  ROUTE_PREF_FONT_PAGE,
  ROUTE_IMAGE_EDIT_PAGE,
  ROUTE_IMAGE_ADJUST_PAGE,
  ROUTE_PHOTO_EDIT_PAGE,
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
  ROUTE_DS_HISTORY_IMPORT_PAGE,
  ROUTE_FUNCTIONAL_MODEL_PAGE,
  ROUTE_SYSTEM_PROMPT_PAGE,
  ROUTE_ASSISTANT_EDIT_PAGE,
  ROUTE_ASSISTANT_PROMPT_PAGE,
  ROUTE_ASSISTANT_PAGE,
  ROUTE_SETTINGS_PAGE,
  ROUTE_PREFERENCES_PAGE,
  ROUTE_PREF_INPUT_SEND_PAGE,
  ROUTE_PREF_AUTO_RETRY_PAGE,
  ROUTE_PREF_REPLY_DISPLAY_PAGE,
  ROUTE_PREF_SESSION_READ_PAGE,
  ROUTE_PREF_APP_LAUNCH_PAGE,
  ROUTE_ASSISTANT_ADVANCED_PAGE,
  ROUTE_ASSISTANT_SAMPLING_PAGE,
  ROUTE_ASSISTANT_CONTEXT_PAGE,
  ROUTE_ASSISTANT_TOOLS_PAGE,
  ROUTE_ASSISTANT_MCP_PAGE,
  ROUTE_USAGE_STATS_PAGE,
  ROUTE_COST_STATS_PAGE,
  ROUTE_FEEDBACK_PAGE,
  ROUTE_SESSION_SEARCH_PAGE,
  ROUTE_MEMORY_PAGE,
  ROUTE_MEMORY_EDIT_PAGE,
  ROUTE_MEMORY_LIBRARY_PAGE,
  ROUTE_MEMORY_HISTORY_PAGE,
  ROUTE_MEMORY_SNAPSHOT_PAGE,
  ROUTE_MEMORY_IMPORT_PAGE,
  ROUTE_ASSISTANT_MEMORY_PAGE,
  ROUTE_STORAGE_PAGE,
  ROUTE_ATTACHMENT_MANAGE_PAGE,
  ROUTE_QUICK_CLEAN_PAGE,
  ROUTE_WORKSPACE_MANAGE_PAGE,
  ROUTE_MOUNT_MANAGE_PAGE,
  ROUTE_MOUNT_BROWSE_PAGE,
  ROUTE_WORKSPACE_OCR_PAGE,
  ROUTE_SEARCH_ENGINE_PAGE,
  ROUTE_SEARCH_ENGINE_DETAIL_PAGE,
  ROUTE_TOOLS_PAGE,
  ROUTE_MCP_PAGE,
  ROUTE_MCP_SERVER_EDIT_PAGE,
  ROUTE_NETWORK_PAGE,
  ROUTE_WEB_SERVICE_PAGE,
  ROUTE_HTTP_REQUEST_PAGE,
  ROUTE_HTTP_CREDENTIALS_PAGE,
  ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE,
  ROUTE_HTTP_CREDENTIAL_EDIT_PAGE,
  ROUTE_CODE_WORKBENCH_PAGE,
  ROUTE_CODE_HTTP_HOSTS_PAGE,
  ROUTE_CODE_HTTP_HOST_MANAGE_PAGE,
  ROUTE_HTTP_TEMPLATE_PAGE,
  ROUTE_HTTP_TEMPLATE_EDIT_PAGE,
  ROUTE_PROACTIVE_PAGE,
  ROUTE_PRICE_TEMPLATE_PROVIDERS_PAGE,
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
  ROUTE_SKILL_FILE_EDIT_PAGE,
  ROUTE_ATTACHMENT_VIEWER_PAGE,
  ROUTE_SESSION_TRACE_PAGE,
  ROUTE_SESSION_WORKSPACE_PAGE,
  ROUTE_PY_RUNTIME_PROBE_PAGE,
  ROUTE_NODE_RUNTIME_PROBE_PAGE,
  ROUTE_PY_RUNTIME_PAGE,
  ROUTE_NODE_RUNTIME_PAGE,
  ROUTE_SIDE_PANEL_PAGE
} from '../../common/RouteNames';

// 页面路由表：官方 navDestination 注册（NavPathStack push 的 name 在此映射到组件）。
// param 为路由参数（d.ts 声明 unknown，ArkTS 禁 any/unknown 故用 Object，官方示例同款）。
// pathStack/topPad/bottomPad = HomeNavigation.PageMap 注入（topPad = HDS 口径
//——状态栏+标题栏+蒙层）；activeConvId = 对话页目标会话（push 前写定，
// 构建时读值）；openSession = 打开会话编排回调（HomeNavigation 闭包直传，presetTitle =
// 点卡行标题供 ChatPage 首帧预置——2026-11-15 反馈二笔）。★ 会话搜索页
// 不自接 pushPathByName 而经 openSession 上行 = 写 activeConvId + push 一步到位，参数链单一。
@Builder
export function buildPageMap(name: string, param: Object, pathStack: NavPathStack, topPad: number,
  bottomPad: number, activeConvId: string, freshConvId: string,
  openSession: (conversationId: string, presetTitle?: string) => void,
  newConversation: () => void,
  onActiveSessionDeleted: (freshId: string) => void) {
  if (name === ROUTE_CHAT_PAGE) {
    // 对话页（自包壳）：param = 会话 id（null/缺省 = activeConvId）；★ 分享拉起 push 参数 =
    // 分享桥批次号 shareTick（number，会话页 onShown 按 tick 匹配消费，其他形态传 0）；
    // pop/replace 后会话列表重拉广播在页面 aboutToDisappear
    ChatPage({
      conversationId: typeof param === 'string' && param !== '' ? param : activeConvId,
      // 乐观空态标记（2026-11-18）：目标会话 id 等于本地新造 id = 必然空，空态不等读库回执
      //（freshConvId 空串 = 无候选，恒 false；表达式与 conversationId 同源判据）
      freshSession: freshConvId !== '' &&
        (typeof param === 'string' && param !== '' ? param : activeConvId) === freshConvId,
      shareTick: typeof param === 'number' ? param : 0,
      topPad: topPad,
      bottomPad: bottomPad,
      pathStack: pathStack
    })
  } else if (name === ROUTE_PROVIDER_PAGE) {
    // 服务商管理列表页：onShown 刷新键须页面自持（栈下层 @StorageProp 不刷新）
    ProviderPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
    // （服务商排序三级页分支已退役：排序回管理页列表原位长按拖拽）
  } else if (name === ROUTE_PROVIDER_DETAIL_PAGE) {
    // 服务商详情三级页：标题动态 + 标题栏「保存」键页面自持；push 参数页面内 getParamByName 取
    ProviderDetailPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_MODEL_EDIT_PAGE) {
    // 编辑模型四级页：标题「添加/编辑模型」动态 + 标题栏「保存」键；push 参数 ModelEditParam 页面内取
    ModelEditPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_FUNCTIONAL_MODEL_PAGE) {
    // 功能模型二级页（设置页「功能模型」卡 push）：功能级模型配置集中页，首项「默认模型」=
    // 发送链四级兜底第③级来源；选择即时写键，push 无参
    FunctionalModelPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_IMAGE_EDIT_PAGE) {
    // 图片编辑裁剪二级页（背景页面板两入口进入）：push 参数页面内取本分支不消费；
    // bgSolid=true 例外；「下一步」push 调整页 / 空背景·解码失败 pop 返回
    ImageEditPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_IMAGE_ADJUST_PAGE) {
    // 图片编辑调整二级页：裁剪页「下一步」push 入栈，保存后 popToName 一次弹两级退出编辑；
    // bgSolid=true 例外
    ImageAdjustPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_PHOTO_EDIT_PAGE) {
    // 待发图片裁剪二级页（★ 非设置项）：会话页拍照/相册选图后由 AttachmentPickCtrl 经
    // ChatPage 的 onPop 桥 push，param 页面内取本分支不消费；pop 恒带 result 回传成品路径
    PhotoEditPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_INFO_PAGE) {
    // 更多信息二级页：行卡（关于/运行日志/权限信息/隐私政策）push 下级页传 pathStack（同栈转场）
    InfoPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ABOUT_PAGE) {
    // 「关于」三级页：「AI 辅助开发声明」卡 push 下级页（同栈）；自包壳
    AboutPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_PERMISSION_PAGE) {
    // 「权限信息」页：纯展示无下级跳转，不传 pathStack
    PermissionPage({ topPad: topPad })
  } else if (name === ROUTE_AI_ASSIST_PAGE) {
    // 「AI 辅助开发声明」页：纯展示无下级跳转
    AiAssistPage({ topPad: topPad })
  } else if (name === ROUTE_OPEN_SOURCE_PAGE) {
    // 「开源项目鸣谢」页：纯展示无下级跳转
    OpenSourcePage({ topPad: topPad })
  } else if (name === ROUTE_LOG_PAGE) {
    // 「运行日志」三级页：右上角「更多」菜单须页面自持；崩溃订阅在 EntryAbility 进程级，
    // 页面刷新经共享 holder 拉取
    LogPage({ topPad: topPad })
  } else if (name === ROUTE_REQ_LOG_PAGE) {
    // 「请求日志」三级页：「更多」菜单与半模态详情面板须页面自持；数据源 = 进程内内存
    // 环形缓冲（common/ReqLog.ets）
    ReqLogPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_SEARCH_PAGE) {
    // 搜索页：标题栏 stackBuilder 搜索框依赖页面 keyword 状态须页面自持（改道理由见
    // SearchPage 头注释）
    SearchPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SYSTEM_PROMPT_PAGE) {
    // 系统提示词独立页（与会话提示词分开——独立管理、内置默认可更改可重置）；右上无菜单键
    // + 底部恢复/保存
    SystemPromptPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_DATA_SYNC_PAGE) {
    // 「数据与同步」二级页：全量导入导出 + WebDAV；push 无参
    DataSyncPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_DS_HISTORY_IMPORT_PAGE) {
    // 「导入 DeepSeek 对话」三级页（数据与同步页入口卡 push 无参）：三态单页 = 选包 → 校验
    // 预览 → 确认应用（DS 导出包解析为图态新会话落库，不覆盖现有会话）
    DsHistoryImportPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROMPT_LIBRARY_PAGE) {
    // 「提示词」管理页：右上角「新增」菜单须页面自持
    PromptLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROMPT_EDIT_PAGE) {
    // 「提示词」编辑页（管理页 push）：param = 模板 id
    PromptEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_EDIT_PAGE) {
    // 助手编辑二级页（助手页签列表卡点击 push）：纯分区导航枢纽（构成见 AssistantEditPage
    // 头注释）；param = 助手 id（恒编辑态——新建走列表页「＋」对话框）页面内取
    AssistantEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
    // （助手排序三级页分支已退役：排序改助手页列表原位长按拖拽）
  } else if (name === ROUTE_ASSISTANT_PROMPT_PAGE) {
    // 助手提示词三级页（编辑页「提示词」分区卡 push）：用户手建 = SystemPromptPage 同款
    // 表单 / 内置默认助手 = 只读展示；param = 助手 id 页面内取
    AssistantPromptPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_ADVANCED_PAGE) {
    // 助手高级设定二级页（编辑页「高级设定」分区卡 push）：两行卡（采样参数/上下文与输出）；
    // param = 助手 id
    AssistantAdvancedPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_SAMPLING_PAGE) {
    // 助手采样参数三级页：四开关卡（开 → 卡内展开官方 InSet 滑块）；param = 助手 id
    AssistantSamplingPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_CONTEXT_PAGE) {
    // 助手上下文与输出三级页：两滑块卡（上下文消息数/最大输出长度 + 编辑键数字弹窗）；
    // param = 助手 id
    AssistantContextPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_TOOLS_PAGE) {
    // 助手工具页签三级页（编辑页「工具调用」分区卡 push）：注册表全量工具开关卡（Toggle
    // 即时落库 assistants.tools 列）；param = 助手 id 页面内取
    AssistantToolsPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_MCP_PAGE) {
    // 助手 MCP 服务器开关三级页（编辑页组卡「MCP」行 push）：按助手勾选服务器，开关即时
    // 落库 assistants.mcpServers 列；param = 助手 id 页面内取
    AssistantMcpPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PREFERENCES_PAGE) {
    // 「偏好与外观」一级页：三板块头 + 七入口行（使用习惯三行 / 外观三行 / 应用一行），点击经
    // pathStack 直推七个下级页（SearchPage 同款姿势）；无保存动作，push 无参
    PreferencesPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PREF_INPUT_SEND_PAGE) {
    // 偏好设置二级页「输入与发送」：开关即改即持久化；传 pathStack（「自动重试」行 push
    // 下级页；阈值编辑走页内 CustomDialogController——坑7 形态）
    PrefInputSendPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PREF_AUTO_RETRY_PAGE) {
    // 「自动重试」三级页（输入与发送页入口行 push 无参）：总开关〔承接旧布尔语义〕+
    // 重试参数四数字行 + 状态码与重试/停止关键字三清单 chips，写即持久化；无下级跳转
    AutoRetrySettingsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PREF_REPLY_DISPLAY_PAGE) {
    // 偏好设置二级页「回复显示」（一级页第 2 入口行 push）：不传 pathStack（无下级跳转）
    PrefReplyDisplayPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PREF_SESSION_READ_PAGE) {
    // 偏好设置二级页「会话与阅读」（一级页第 3 入口行 push）：不传 pathStack（无下级跳转）
    PrefSessionReadPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PREF_APP_LAUNCH_PAGE) {
    // 偏好设置二级页「应用与启动」（一级页第 4 入口行 push）：不传 pathStack（无下级跳转）
    PrefAppLaunchPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PREF_BACKGROUND_PAGE) {
    // 「背景」三级页（偏好与外观页「背景」入口行 push 无参）：BackgroundPanel 整页承载；
    // 传 pathStack（面板「选择/编辑图片」push 图片编辑页，编辑保存后 popToName 回本页）
    PrefBackgroundPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PREF_FONT_PAGE) {
    // 「字体」三级页（偏好与外观页「字体」入口行 push 无参）：ChatFontSection 整页承载；
    // 不传 pathStack（无下级跳转）
    PrefFontPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_PRIVACY_POLICY_PAGE) {
    // 「隐私政策」页（上架合规入口）：纯展示无下级跳转，不传 pathStack
    PrivacyPolicyPage({ topPad: topPad })
  } else if (name === ROUTE_HELP_CENTER_PAGE) {
    // 「帮助中心」页：条目卡可点进详情（pathStack 传入 push 帮助条目详情页）
    HelpCenterPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_HELP_TOPIC_PAGE) {
    // 「帮助条目详情」页：param = 条目 id 页面内取；纯展示，pathStack 仅用于读参
    HelpTopicPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_USAGE_STATS_PAGE) {
    // 「用量统计」页：概览六数字/按模型/近30天逐日纯列表，push 无参
    UsageStatsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_COST_STATS_PAGE) {
    // 「费用估计」页：模型价格 × token 用量折算估算，三卡随时段胶囊联动；不传 pathStack
    CostStatsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_FEEDBACK_PAGE) {
    // 「反馈与建议」页：反馈文本经第三方推送服务直达开发者手机，零自有服务器；发送键吸底
    // 需 bottomPad 计算让位；push 无参
    FeedbackPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_SESSION_SEARCH_PAGE) {
    // 会话搜索二级页（SearchPage 同构自包壳）。范围 = 当前助手名下全部会话标题；打开会话
    // 必走 openSession 回调（★ 禁在本分支改成直 push ROUTE_CHAT_PAGE——见函数头注释）
    SessionSearchPage({
      topPad: topPad,
      bottomPad: bottomPad,
      onOpenSession: openSession
    })
  } else if (name === ROUTE_MEMORY_PAGE) {
    // 「记忆」二级页：两开关 + 条目列表 + 添加/编辑/删除/立即整理；标题栏「＋」与「⋯」两键
    //（排序/立即整理/优化记忆在「更多」菜单）
    MemoryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PROACTIVE_PAGE) {
    // 「主动消息」二级页：总开关 + 触发间隔两行组卡 + 说明小字；写操作即时持久化
    ProactivePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_EDIT_PAGE) {
    // 记忆编辑三级页（添加/编辑一律进二级页，形制对齐 PromptEditPage）：记忆页「＋」push
    // 空参 / 点条目卡 push 记忆 id；标题栏「保存」键，保存成功 pop({saved:true}) 触发记忆页重拉
    MemoryEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
    // （记忆排序三级页分支已退役：排序改记忆库管理页列表原位长按拖拽）
  } else if (name === ROUTE_MEMORY_LIBRARY_PAGE) {
    // 记忆库管理三级页（设置记忆页点库卡 push）：param = { libraryId }（'global' = 全局库 /
    // 助手 id = 助手库）页面内取；条目管理面跟库走，保存/排序 pop 带 result 触发本页重拉
    MemoryLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_HISTORY_PAGE) {
    // 记忆历史三级页（库管理页「更多」菜单进入）：param = { libraryId } 复用
    // MemoryLibraryParam 页面内取；列该库最近改动前快照（优化前/导入前共用配额），行卡恢复
    // 键确认弹窗后整库回退
    MemoryHistoryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_SNAPSHOT_PAGE) {
    // 记忆快照详情三级页（历史页点行卡 push）：param = {snapshotId} 页面内取；只读列出该版
    // 条目，不设恢复键（恢复入口唯一在列表行卡）
    MemorySnapshotPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MEMORY_IMPORT_PAGE) {
    // 记忆导入三级页（库管理页「更多」菜单「从其他平台导入」push）：param = { libraryId }
    //（声明单源在 MemoryLibraryPage.ets）页面内取；三态单页 = 粘贴 → AI 整理 → 预览确认
    // 后事务化批量落库（写前自动存「导入前」快照）
    MemoryImportPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_MEMORY_PAGE) {
    // 助手记忆三级页（助手编辑页「记忆」分区卡 push）：注入/沉淀两开关行（即时落库），
    // 无管理入口（管理只在设置页）；param = 助手 id；本页返回带 result 供编辑页重拉
    AssistantMemoryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_STORAGE_PAGE) {
    // 「存储管理」二级页：六分类占用展示 + 可安全清理；传 pathStack（页内卡3「会话附件」
    // 入口卡 push 附件管理页）
    StoragePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ATTACHMENT_MANAGE_PAGE) {
    // 「附件管理」三级页（存储管理页「会话附件」卡 push 无参）：按会话分组列出已发送附件，
    // 展开可预览与单件删；传 pathStack（行点击 push 查看器二级页）
    AttachmentManagePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_QUICK_CLEAN_PAGE) {
    // 「快速清理」三级页（存储管理页「快速清理」入口卡 push 无参）：各域数据分项列出、
    // 逐项确认后清除；传 pathStack（执行段返回拦截确认离开后 pop 用）
    QuickCleanPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_WORKSPACE_MANAGE_PAGE) {
    // 「文件工作区」二级页：列出助手保存与用户上传的工作区文件，可预览、分享、上传、单件
    // 删除；标题栏「⋯更多」挂三项 = 新建文件夹 / 上传文件 / 清空工作区；传 pathStack
    //（行点击预览 push 查看器）
    WorkspaceManagePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MOUNT_MANAGE_PAGE) {
    // 「文件夹挂载」二级页（与文件工作区平级两文件域）：授权 AI 访问本机文件夹 + 挂载清单
    // 管理（添加/改名/切换模式/重新授权/移除）；授权与行读写即时落定；传 pathStack（正常态
    // 挂载卡点入浏览页）
    MountManagePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MOUNT_BROWSE_PAGE) {
    // 「文件夹挂载」浏览三级页（管理页正常态挂载卡 push，param = MountBrowseParam{mountId}
    // 页面内取末条）：只读浏览——面包屑 + 条目列表 + 预览三路 + 复制到工作区；传 pathStack
    //（文件行预览 push 查看器）
    MountBrowsePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_WORKSPACE_OCR_PAGE) {
    // 「识别文字」三级页（管理页文件行菜单或识别完成自动进入，param =
    // WorkspaceOcrPageParam{fileId, name} 页面内取末条）：预识别文本查看与校对；保存链 =
    // 返回统一落库且 pop 恒带 result → 管理页 onPop 刷新菜单标签
    WorkspaceOcrPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SEARCH_ENGINE_PAGE) {
    // 「联网搜索」引擎列表页（工具调用页首组卡首行 push 无参）：条数卡 + 超时卡 + 引擎卡
    // 列表（总开关已退役全局恒开），点卡片 push 引擎配置三级页；传 pathStack（点卡片下探）
    SearchEnginePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SEARCH_ENGINE_DETAIL_PAGE) {
    // 「引擎配置」三级页（列表页点引擎卡 push，param = 引擎 id 页面内取）：启停/设当前/
    // 密钥与 baseUrl/测试搜索；写偏好即时生效，列表页经 @StorageLink 订阅自动刷新无需 onPop
    SearchEngineDetailPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_TOOLS_PAGE) {
    // 「工具调用」二级页：内置工具全局设置
    ToolsSettingsPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_NETWORK_PAGE) {
    // 「网络设置」二级页：User-Agent 内容卡写即持久化。分支位次 = 紧随工具调用页——与
    // SettingsPage 卡序一致
    NetworkSettingsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_WEB_SERVICE_PAGE) {
    // 「Web 服务」二级页（设置页卡5「网络」第二行）：浏览器远程访问设置——启动卡（服务
    // 开关/地址/口令）+ 服务设置（端口/仅本机）+ 安全提示卡；写即持久化。分支位次 = 紧随
    // 网络设置页
    WebServiceSettingsPage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_HTTP_REQUEST_PAGE) {
    // 「HTTP 请求」三级页（工具调用页内跳转行 push 无参）：http_request 工具专属设置，首张
    // 卡请求超时上限。分支位次 = 紧随工具调用页（原浏览器控制页已随三档归一退役，2026-11-09）
    HttpRequestSettingsPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_HTTP_CREDENTIALS_PAGE) {
    // 「HTTP 凭据」总览页（HTTP 请求设置页第三张卡 push 无参）：页内全局卡 + 每助手卡，
    // 点击进管理页经本页 pathStack
    HttpCredentialLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE) {
    // 「HTTP 凭据」管理页（总览页卡/助手编辑页分区卡两路 push，param = owner 页面内取
    // 末条）：管理动作即时落库
    HttpCredentialManagePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_HTTP_CREDENTIAL_EDIT_PAGE) {
    // 「HTTP 凭据」编辑页（管理页「添加凭据」push credId='' 新建 / 行菜单与缺失行「编辑」
    // push credId，param = HttpCredEditParam{owner, credId} 页面内取）：名称 + 值 + 用途说明
    // 三字段，标题栏「保存」键；保存 pop 带 result 触发管理页重拉
    HttpCredentialEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_CODE_WORKBENCH_PAGE) {
    // 「脚本工作台」设置页（工具调用页首组卡「脚本工作台」行 push 无参）：档位段控 +
    // 脚本联网域名入口卡。分支位次 = 紧随浏览器控制页（同为工具调用页子页）
    CodeWorkbenchPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PY_RUNTIME_PAGE) {
    // 「Python 运行环境」设置页（工具调用页首组卡「Python 运行环境」行 push 无参）：
    // 解释器状态与预置包只读清单，「检查环境」键触发首用落位与初始化。分支位次 = 紧随
    // 脚本工作台页（与工具调用页子页行序一致）；无下级跳转，不传 pathStack（PermissionPage
    // 同款）
    PyRuntimePage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_NODE_RUNTIME_PAGE) {
    // 「Node 运行环境」设置页（2026-11-24 鸿蒙 Node 运行时门 4；工具调用页「Node 运行环境」行 push
    // 无参）：运行环境状态与占用、已装包清单、清空安装包 / 重建运行区 / 重启应用。分支位次 = 紧随
    // Python 运行环境页（与工具调用页子页行序一致）；无下级跳转，不传 pathStack
    NodeRuntimePage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_MCP_PAGE) {
    // 「MCP」三级页（工具调用页首组卡「MCP」行 push 无参）：MCP 服务器管理（服务器清单 +
    // 测连 + 工具同步）。分支位次 = 脚本工作台页之后（与工具调用页子页显示序一致，勿机械
    // 挂全文件链尾）
    McpPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_MCP_SERVER_EDIT_PAGE) {
    // 「MCP 服务器编辑」四级页（管理页行卡与「添加服务器」键 push，param =
    // McpEditParam{serverId}（'' = 新建）页面内取末条——表单 + 保存后自动测连 + 删除级联）：
    // 保存/删除成功 pop 带 result 触发管理页重拉。位次 = 紧随 MCP 管理页（MCP 域内簇）
    McpServerEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_CODE_HTTP_HOSTS_PAGE) {
    // 「脚本联网域名」总览页（脚本工作台设置页域名入口卡 push 无参）：页内全局卡 + 每助手卡，
    // 点击进管理页经本页 pathStack
    CodeHttpHostsLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_CODE_HTTP_HOST_MANAGE_PAGE) {
    // 「脚本联网域名」管理页（总览页卡/助手编辑页分区卡两路 push，param = owner 页面内取
    // 末条）：管理动作即时落库
    CodeHttpHostManagePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_HTTP_TEMPLATE_PAGE) {
    // 「HTTP 请求模板」列表页（HTTP 请求设置页入口卡 push 无参）：点行进编辑页，编辑页保存
    // pop 带 result 经 pushPathByName 第三参回调重拉
    HttpTemplatePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_HTTP_TEMPLATE_EDIT_PAGE) {
    // 「HTTP 请求模板」编辑页（列表页 push，param = 'new' | 模板 id 页面内取末条）；保存 →
    // pop({ saved: true })
    HttpTemplateEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PRICE_TEMPLATE_PAGE) {
    // 「价格模板」模板列表页（服务商选择页点行 push，param = providerId 页面内取）：标题栏
    // 「添加」键；子页保存/删除 pop 带 result → 本页 onPop 重拉
    PriceTemplatePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PRICE_TEMPLATE_EDIT_PAGE) {
    // 「价格模板」模板编辑页（列表页点行卡/「添加」键 push，param =
    // PriceTemplateEditParam{providerId, templateId} 页面内取）：标题栏「保存」键 + 编辑态底部
    // 删除键；复用 ModelPriceCard 同一张价格卡，保存/删除 pop 带 result 触发列表页重拉
    PriceTemplateEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_BALANCE_CONFIG_PAGE) {
    // 「余额查询」配置页（服务商编辑页高级页签入口卡 push，param =
    // BalanceConfigParam{providerId} 页面内取）：标题栏「保存」键复用 ProviderSaveMenu 工厂；
    // 页内自保存 + 查询 pop 带 result → 入口页 onPop 自增 headEpoch 刷顶卡余额徽章
    BalanceConfigPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SKILL_LIBRARY_PAGE) {
    // 「技能库」二级页（唯一入口，助手侧入口行均已撤）：技能清单 + 标题栏「＋新建」+ 行卡
    // 四点键菜单；列表刷新 = SKILL_LIST_TICK_KEY 广播 + 子页 pop 带 result；传 pathStack
    //（点行卡/「＋」下探技能编辑页）
    SkillLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_LIBRARY_PAGE) {
    // 「知识库」二级页（唯一入口，助手侧入口行已撤）：书名清单 + 标题栏「＋」+ 行卡四点键
    // 菜单（重命名/删除）；刷新 = KNOWLEDGE_LIST_TICK_KEY 广播 + 子页 pop 带 result；传
    // pathStack（点行卡下探条目清单页）。★ 分支位次 = 紧邻技能库页——与 SettingsPage
    // 「指令面」组卡行序一致
    KnowledgeLibraryPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_BOOK_PAGE) {
    // 「知识库条目清单」三级页（库页点行卡 push，param = 书名 id 页面内取）：页标题 = 书名
    //（查询回填，查不到即返回上一页）+ 条目行卡（四点键菜单 = 删除）+ 标题栏「＋」单键
    //（新建条目，达 KNOWLEDGE_ENTRY_MAX 拦截）；子页 pop 带 result 经 onPop 重拉
    KnowledgeBookPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_EDIT_PAGE) {
    // 「知识库条目编辑」四级页（清单页「＋」/点条目行 push，param =
    // KnowledgeEditParam{bookId,entryId}（entryId '' = 新建）页面内取）：标题栏「保存」键
    //（校验失败 toast 不静默）；保存成功 pop 带 result 触发清单页重拉；传 pathStack（文件卡
    // 下探条目附件编辑页）
    KnowledgeEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_KNOWLEDGE_FILE_EDIT_PAGE) {
    // 「知识库条目附件编辑」五级页（条目编辑页文件卡 push，param = KnowledgeFileEditParam
    // 页面内取）：标题栏「保存」键 + 编辑态底部删除键；保存/删除成功 pop 带 result 触发
    // 文件卡重拉
    KnowledgeFileEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_KNOWLEDGE_PAGE) {
    // 助手知识库三级页（助手编辑页「知识库」分区卡 push）：知识库开关组卡（即时落库），无
    // 管理入口（管理只在设置页）；param = 助手 id 页面内取；本页返回带 result 供编辑页重拉
    AssistantKnowledgePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SKILL_EDIT_PAGE) {
    // 「技能编辑」三级页（库页「＋新建」push 空参 / 点行卡 push 技能 id，param = 技能 id
    // 页面内取）：标题栏「保存」键；保存/删除成功 pop 带 result 触发库页刷新
    SkillEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ASSISTANT_SKILL_PAGE) {
    // 助手技能三级页（助手编辑页「技能」分区卡 push）：技能开关组卡（即时落库），无管理
    // 入口（管理只在设置页）；param = 助手 id 页面内取；本页返回带 result 供编辑页重拉
    //（原双宿主参数化已随「技能选择页」路由退役，本分支只余助手模式）
    AssistantSkillPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SKILL_FILE_EDIT_PAGE) {
    // 「技能附件编辑」四级页（技能编辑页文件组卡 push，param = SkillFileEditParam 页面内取）：
    // 标题栏「保存」键 + 编辑态底部删除键；保存/删除成功 pop 带 result 触发组卡重拉
    SkillFileEditPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_ATTACHMENT_VIEWER_PAGE) {
    // 附件查看器二级页（两宿主 push：会话页附件泡/输入栏附件条 + 附件管理页行点击，param =
    // AttachmentViewerParam{items,index} 页面内取——原全屏模态改页面后顶部归官方 HDS 标题栏
    // 骑内容之上）：图片 topPad 下发（1x 落标题栏下方、放大后可进蒙层）、文本走内容内层
    // padding；标题栏右上角「分享」键；无底部组件不收 bottomPad
    AttachmentViewerPage({ topPad: topPad, pathStack: pathStack })
  } else if (name === ROUTE_PRICE_TEMPLATE_PROVIDERS_PAGE) {
    // 「价格模板」服务商选择页（服务商管理页标题栏「更多」菜单「价格模板」项 push 无参）：
    // 点行 push 模板列表页携 providerId（param 契约与旧入口逐字一致）
    PriceTemplateProvidersPage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SESSION_TRACE_PAGE) {
    // 「会话轨迹」二级页（会话页「更多」菜单 push，param = 会话 id 页面内取）：轮/记录行
    // 只读账表 + 简化时间条 + 详情半模态
    SessionTracePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SESSION_WORKSPACE_PAGE) {
    // 「会话工作区」二级页（会话页「更多」菜单 push，param = 会话 id 页面内取）：只显示本
    // 会话的工作区文件（面包屑单段置灰 + 文件行卡 + 预览/分享/改名/移动/删除）；生成中落库
    // 不自动现（快照语义，重进页刷新）；传 pathStack（预览 push 查看器）
    SessionWorkspacePage({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_PY_RUNTIME_PROBE_PAGE) {
    // 「Python 运行验证」页（2026-11-06 鸿蒙Python运行时门1笔）：门 1 临时验证面——入口由
    // 构建 PY_PROBE_ENABLED 开关门控（工具调用页列表尾），路由分支无条件注册（不 push 不
    // 实例化）。纯验证无下级跳转，不传 pathStack（PermissionPage 同款）。★ 非设置项
    //（临时验证面，不进设置搜索注册表）
    PyRuntimeProbePage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_NODE_RUNTIME_PROBE_PAGE) {
    // 「Node 运行验证」页（2026-11-23 鸿蒙 Node 运行时门 1 笔）：门 1 临时验证面——入口由
    // 构建 NODE_PROBE_ENABLED 开关门控（工具调用页列表尾），路由分支无条件注册（不 push 不
    // 实例化）。纯验证无下级跳转，不传 pathStack（Python 探针页同款）。★ 非设置项
    //（临时验证面，不进设置搜索注册表）
    NodeRuntimeProbePage({ topPad: topPad, bottomPad: bottomPad })
  } else if (name === ROUTE_ASSISTANT_PAGE) {
    // 「助手」二级页（2026-11-16 首页布局双形态笔）：侧栏对话形态下侧栏底部「助手」入口与
    // 助手切换面板「管理助手」push——AssistantPage 原件 + AssistantPageHost 壳（PageShell +
    // 「＋新建助手」覆盖层）；页签形态不经本分支。★ 非设置项
    AssistantPageHost({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SETTINGS_PAGE) {
    // 「设置」二级页（同笔）：侧栏底部「设置」入口 push——SettingsPage 原件 +
    // SettingsPageHost 壳（PageShell + 常显搜索键——页签「假框⇄右上角键」互斥为页签专属，
    // 二级页化重映射，方案档 §3.8）。★ 非设置项
    SettingsPageHost({ topPad: topPad, bottomPad: bottomPad, pathStack: pathStack })
  } else if (name === ROUTE_SIDE_PANEL_PAGE) {
    // 「侧栏会话」伪侧栏二级页（2026-11-18 侧栏二级页化笔）：drawer 形态首页汉堡键 push——
    // 全宽页承载侧栏内容（标题栏覆盖层助手行 + 单行分段带回 + 会话列表 + 多选域页内自持）；
    // 瞬显入场〔push animated=false，系统默认转场无结束信号〕；退场点卡瞬收 / 系统返回与返回键官方动画（2235-b 起自绘转场已退役）。
    // param 无；三回调上行 = openSession（点行回首页换会话）/ newConversation（新建回首页）/
    // onActiveSessionDeleted（删除命中主区会话，主区换新会话态、本页留守）。★ 非设置项
    DrawerSidePanel({
      topPad: topPad,
      bottomPad: bottomPad,
      pathStack: pathStack,
      selectedConvId: activeConvId,
      onOpenSession: openSession,
      onNewConversation: newConversation,
      onActiveSessionDeleted: onActiveSessionDeleted
    })
  }
}
