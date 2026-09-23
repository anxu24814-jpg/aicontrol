// 官方路由名单一来源（2026-08-29 M2c 自 dshinhm 同名文件规范随迁）：
// PageMap 分支判断（nav/HomeNavigation.ets）、各页 pushPathByName、设置项搜索注册表
// pageName（common/SettingSearch.ets）三处此前各写裸字符串/散落常量，靠人工保证一致——
// 拼错任一 = NavDestination 分支不匹配、页面空白/返回键直接退应用（坑51 同族风险）。
// 统一引用本文件常量后：①拼写错误编译期即报（未定义标识符，ArkTS 严格模式）；
// ②注册表 pageName 与 PageMap 分支天然同源，漂移不可能；③新增路由页 = 本文件加常量 +
// PageMap 链尾 else if 分支 + 注册表条目（三处同步，判定规程与校验防线见
// dshinhm docs/设置项搜索规范.md，本项目口径随迁；scripts/setting-search-check.mjs 机械把关）。
// 常量名 = 路由名 + _PAGE 后缀；值 = PageMap 注册名（保持既有字符串不变）。
// Tab 内容页（ChatSessionList/AssistantPage/SettingsPage）不经 PageMap，无常量。

// 对话页（M1 起；从会话列表卡片 push，param = null）
export const ROUTE_CHAT_PAGE: string = 'chatPage';
// 服务商管理二级页（M2a 轮 7 起；2026-08-30 服务商管理域改版为列表页——设置页行卡 push）
export const ROUTE_PROVIDER_PAGE: string = 'providerPage';
// 服务商排序三级页（2026-08-30 反馈轮 6 起；管理页标题栏更多菜单「排序」push。管理页
// 自此摘拖拽——坑10 浮起被列表内容区裁切，排序页窄卡留浮起放大头部空间）
export const ROUTE_PROVIDER_SORT_PAGE: string = 'providerSortPage';
// 服务商详情三级页（2026-08-30 服务商管理域起；列表页卡片 push 携 providerId / 标题栏
// 「+」键 push 无参 = 新建；自包 PageShell 壳——标题动态 + 标题栏「保存」键）
export const ROUTE_PROVIDER_DETAIL_PAGE: string = 'ProviderDetailPage';
// 编辑模型四级页（2026-08-30 服务商管理域起；详情页模型页签 push，param = ModelEditParam
//（providerId + modelRowId，后者空 = 新建）；自包 PageShell 壳）
export const ROUTE_MODEL_EDIT_PAGE: string = 'ModelEditPage';
// 外观显示二级页（M2c 起；本轮仅光感面板，入口 = 搜索直达，设置页暂无行卡）
export const ROUTE_APPEARANCE_PAGE: string = 'AppearancePage';
// 更多信息二级页（M2c 起；骨架 + 关于）
export const ROUTE_INFO_PAGE: string = 'InfoPage';
// 设置项搜索页（M2c 起；设置页签标题栏搜索键 push；注册表禁止包含本页——防循环）
export const ROUTE_SEARCH_PAGE: string = 'SearchPage';
// 图片编辑裁剪二级页（M3 起；背景面板「选择图片/编辑图片」push，param = EditImageParam）
export const ROUTE_IMAGE_EDIT_PAGE: string = 'ImageEditPage';
// 图片编辑调整二级页（M3 起；裁剪页「下一步」push，param = AdjustPageParam；保存后 popToName
// 一次弹两级回外观页）
export const ROUTE_IMAGE_ADJUST_PAGE: string = 'ImageAdjustPage';
// 关于三级页（M3 起；更多信息页行卡；pathStack 供 AI 声明/开源鸣谢卡片 push 下级页）
export const ROUTE_ABOUT_PAGE: string = 'AboutPage';
// 权限信息页（M3 起；2026-09-07 自关于页卡片迁至更多信息页行卡；纯展示无下级跳转）
export const ROUTE_PERMISSION_PAGE: string = 'PermissionPage';
// AI 辅助开发声明页（M3 起；关于页卡片 push；纯展示无下级跳转）
export const ROUTE_AI_ASSIST_PAGE: string = 'AiAssistPage';
// 开源项目鸣谢页（2026-09-02 新增；关于页卡片 push；纯展示无下级跳转）
export const ROUTE_OPEN_SOURCE_PAGE: string = 'OpenSourcePage';
// 隐私政策页（2026-09-02 新增；2026-09-07 自关于页卡片迁至更多信息页行卡——上架合规
// 入口；纯展示无下级跳转）
export const ROUTE_PRIVACY_POLICY_PAGE: string = 'PrivacyPolicyPage';
// 运行日志三级页（M3 起；更多信息页条目 push；自包 PageShell 壳含「更多」菜单）
export const ROUTE_LOG_PAGE: string = 'LogPage';
// 请求日志三级页（2026-09-23 请求日志笔；更多信息页条目 push；自包 PageShell 壳含「更多」
// 菜单与半模态详情面板宿主）
export const ROUTE_REQ_LOG_PAGE: string = 'ReqLogPage';
// 提示词库管理二级页（2026-08-30 提示词注入；设置页行卡 push——管理系统提示词与会话模板）
export const ROUTE_PROMPT_LIBRARY_PAGE: string = 'PromptLibraryPage';
// 提示词编辑三级页（2026-08-30 提示词注入；管理页 push，param = 模板 id（空 = 新增）；
// 自包 PageShell 壳含「保存」键；★ 2026-08-31 起不再承载系统提示词——独立页
// ROUTE_SYSTEM_PROMPT_PAGE 接管）
export const ROUTE_PROMPT_EDIT_PAGE: string = 'PromptEditPage';
// 系统提示词独立页（2026-08-31 领导指令：与会话提示词「分开」——库页不显示、独立页
// 管理、内置默认可更改可重置；设置页行卡与搜索条目 push，无参；自包 PageShell 壳，右上角
// 无菜单键 + 底部「恢复/保存」两按钮）
export const ROUTE_SYSTEM_PROMPT_PAGE: string = 'SystemPromptPage';
// 助手编辑二级页（2026-09-01 助手域起，同日分区化/按钮区退役定稿）：助手页签列表卡点击
// push（恒编辑态——新建走列表页「＋」对话框不经本页）；自包 PageShell 壳——纯分区导航
// 枢纽（名称行卡弹重命名 + 提示词/记忆/工具调用/技能/知识库/高级设定六卡，底部无按钮）
export const ROUTE_ASSISTANT_EDIT_PAGE: string = 'AssistantEditPage';
// 助手排序三级页（2026-09-22 助手自定义列表序：助手页签标题栏「⋯」更多菜单的「排序」项
// push〔该菜单项 2026-09-22 合并胶囊笔先落占位提示，本笔兑现〕——ProviderSortPage /
// MemorySortPage 同构拖拽排序页〔ForEach.onMove 官方限 List，而助手页是 Scroll+Column
// 〔坑9〕，故必须独立成页〕；pop 带 result 触发助手页经指令键重拉新卡序。★ 非设置项（页签
// 标题栏入口），不进 SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支
//〔ROUTE_PROVIDER_SORT_PAGE 同款例外口径〕）
export const ROUTE_ASSISTANT_SORT_PAGE: string = 'assistantSortPage';
// 助手提示词三级页（2026-09-01 分区化起）：编辑页「提示词」分区卡 push，param = 助手 id；
// 自包 PageShell 壳——用户手建 = SystemPromptPage 同款表单（变量插入 + 内容 + 底部保存），
// 内置默认助手 = 只读展示页（反馈轮 3 语义原样迁移）
export const ROUTE_ASSISTANT_PROMPT_PAGE: string = 'AssistantPromptPage';
// ★ 原「助手分区占位三级页」路由常量 2026-09-21 随世界书知识库首版删除（死代码清理）：
// 它是六张分区卡里最后一个占位项（知识库）的承载页，占位清单清空后零消费点——页面件
// （components/assistants 下的 71 行纯展示件）与本常量同笔删除；此处不留名以免负向钉
// （全仓零该符号）与死代码清理的复核互相打架，沿革见 docs/变更记录.md 本笔条目
// 助手模型设置三级页（2026-09-01 模型绑定起）：编辑页「模型设置」首卡 push，param =
// 助手 id；自包 PageShell 壳——单卡（上部绑定显示 + 下部选择模型/思考强度双键，半模态
// 与菜单同会话页机制）；选择/档位即时落库，返回 pop 带 result 刷编辑页卡片摘要
export const ROUTE_MODEL_SETTINGS_PAGE: string = 'assistantModelSettingsPage';
// 偏好设置二级页（2026-09-01 领导指令：设置页「会话提示词」卡后新增——偏好项集中页，
// 首项「默认展开思考」；AppStorage persistProp 即时生效无保存键，返回无需 onPop）
export const ROUTE_PREFERENCES_PAGE: string = 'preferencesPage';
// 「数据与同步」二级页（2026-09-03 Cube 吸收第三批③：全量导入导出 + WebDAV；自包 PageShell 壳）
export const ROUTE_DATA_SYNC_PAGE: string = 'DataSyncPage';
// 功能模型二级页（2026-09-05 决明指令：设置页「功能模型」卡 push——功能级模型配置集中页，
// 首项「默认模型」= 发送链四级兜底第③级来源；自包 PageShell 壳含模型选择半模态）
export const ROUTE_FUNCTIONAL_MODEL_PAGE: string = 'functionalModelPage';
// 助手高级设定二级页（2026-09-01 高级设定起）：编辑页「高级设定」分区卡 push，param =
// 助手 id；自包 PageShell 壳——两行卡（采样参数/上下文与输出，副行摘要随三级页 onPop
// 重拉）
export const ROUTE_ASSISTANT_ADVANCED_PAGE: string = 'assistantAdvancedPage';
// 助手采样参数三级页（2026-09-01 高级设定起）：二级页「采样参数」行卡 push，param =
// 助手 id；自包 PageShell 壳——四开关卡（开 → 卡内展开官方 InSet 滑块）；返回时
// onBackPressed 拦截统一落库
export const ROUTE_ASSISTANT_SAMPLING_PAGE: string = 'assistantSamplingPage';
// 助手上下文与输出三级页（2026-09-01 高级设定起）：二级页「上下文与输出」行卡 push，
// param = 助手 id；自包 PageShell 壳——上下文消息数/最大输出长度两滑块卡（编辑键弹
// 数字输入对话框）；返回时统一落库
export const ROUTE_ASSISTANT_CONTEXT_PAGE: string = 'assistantContextPage';
export const ROUTE_ASSISTANT_TOOLS_PAGE: string = 'assistantToolsPage';
// 帮助中心页（2026-09-05 新增；更多信息页行卡 push——分板块卡片说明应用功能与用法）；
// 2026-09-05 二级页化：条目卡可点进帮助条目详情页（pathStack 自此传入）；自包壳（PageShell）
export const ROUTE_HELP_CENTER_PAGE: string = 'helpCenterPage';
// 帮助条目详情页（2026-09-05 二级页化新增；帮助中心页条目卡点击 push，param = 条目 id
// 「分组标题::条目标题」——页面内 getParamByName 取，经 HelpContent.findHelpTopic 还原
// 内容；纯展示无下级跳转，pathStack 仅用于读参；自包壳（PageShell））
export const ROUTE_HELP_TOPIC_PAGE: string = 'helpTopicPage';
// 「用量统计」二级页（2026-09-06 token 用量统计：设置页「用量统计」卡 push——概览六数字
// /按模型/近30天逐日纯列表；无编辑无保存动作，返回无参 pop 不挂 onPop〔坑17 口径〕；
// 自包 PageShell 壳）
export const ROUTE_USAGE_STATS_PAGE: string = 'UsageStatsPage';
// 「费用估计」二级页（2026-09-10 方案-费用估计：设置页「用量统计+费用估计」组卡第二行
// push——模型价格 × token 用量的折算估算，总览四格/模型排行/用途分布三卡，时段胶囊与
// 用量统计页同源；无编辑无保存动作 → 返回无参 pop 不挂 onPop〔坑17 口径〕；自包
// PageShell 壳）
export const ROUTE_COST_STATS_PAGE: string = 'costStatsPage';
// 「反馈与建议」页（2026-09-07 MeoW 反馈通道新增：更多信息页行卡 push〔帮助中心行卡
// 下方，同日自关于页卡片移入〕——反馈文本经第三方
// 推送服务 api.chuckfang.com 直达开发者手机，零自有服务器；纯表单无下级跳转，返回无参
// pop 不挂 onPop〔坑17 口径〕；自包 PageShell 壳）
export const ROUTE_FEEDBACK_PAGE: string = 'FeedbackPage';
// 会话搜索二级页（2026-09-08 会话搜索改版：对话页签标题栏搜索键 push——搜索 UI 自一级页
// 内嵌态迁独立页，SearchPage 同构自包壳；搜索范围 = 当前助手名下全部会话标题。★ 非设置
// 项，不进 SettingSearch 注册表（三处同步惯例只约束设置项，本页两处同步即可 = 本文件 +
// PageMap 分支）；打开会话不自接 push ChatPage——经 HomeNavigation.openSession 既有链
//（activePrivate 隐私复位语义，见 PageMapBuilder 分支注释））
export const ROUTE_SESSION_SEARCH_PAGE: string = 'SessionSearchPage';
// 「记忆」二级页（2026-09-08 记忆域：设置页「记忆」卡 push——跨会话长期记忆管理：总
// 开关/自动整理两开关 + 条目列表查看/编辑/删除/手动添加/立即整理；自包 PageShell 壳，
// 标题栏两键 =「＋」新建与「⋯」更多——2026-09-13 起排序/立即整理/优化记忆三项收进
// 「更多」菜单）
export const ROUTE_MEMORY_PAGE: string = 'memoryPage';
// 记忆编辑三级页（2026-09-08 决明指令：取消「记忆条目」新增弹窗，添加/编辑一律进二级页
// ——形制对齐会话提示词编辑页 PromptEditPage；记忆页「＋」新建键 push 空参 = 新增、
// 点条目卡 push 记忆 id = 编辑；自包 PageShell 壳含「保存」键）
export const ROUTE_MEMORY_EDIT_PAGE: string = 'MemoryEditPage';
// 记忆排序三级页（2026-09-12 记忆自定义注入顺序：记忆页标题栏「更多」菜单的「排序」项
// push——ProviderSortPage 同构拖拽排序页；pop 带 result 触发记忆页 onPop 重拉新卡序）
export const ROUTE_MEMORY_SORT_PAGE: string = 'MemorySortPage';
// 记忆库管理三级页（2026-09-20 助手级记忆：设置记忆页一级改分库列表后，点库卡 push——
// param = { libraryId }（'global' = 全局库 / 助手 id = 助手库）；条目管理面自 MemoryPage
// 整体迁入（列表/增删改/排序/立即整理/优化），操作面跟库走；自包 PageShell 壳 + 标题栏
// 〔＋|⋯〕胶囊。★ 非设置项（三级页），不进 SettingSearch 注册表——两处同步即可 =
// 本文件 + PageMap 分支（ROUTE_ATTACHMENT_MANAGE_PAGE 同款例外口径）
export const ROUTE_MEMORY_LIBRARY_PAGE: string = 'MemoryLibraryPage';
// 记忆历史三级页（2026-09-22 记忆优化历史：库管理页「更多」菜单「记忆历史」项 push——
// param = { libraryId }（MemoryLibraryParam 复用，声明单源在 MemoryPage.ets），列出该库最近的
// 改动前快照（优化前 / 导入前两类共用一份配额）+ 一份恢复前兜底，行卡右侧恢复键整库回退；
// 自包 PageShell 壳，无标题栏菜单键。
// ★ 非设置项（三级页），不进 SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支
//〔ROUTE_MEMORY_LIBRARY_PAGE 同款例外口径〕）
export const ROUTE_MEMORY_HISTORY_PAGE: string = 'MemoryHistoryPage';
// 记忆快照详情三级页（2026-09-22 记忆优化历史：历史页点行卡 push——param =
// MemorySnapshotParam{snapshotId}（声明单源在发起方 MemoryHistoryPage.ets），只读列出该份
// 快照的条目；★ 不设恢复键（D9：恢复入口唯一在列表行卡，多入口 = 误触与歧义）；自包
// PageShell 壳，无标题栏菜单键。★ 非设置项，不进 SettingSearch 注册表——两处同步即可
//〔同上例外口径〕）
export const ROUTE_MEMORY_SNAPSHOT_PAGE: string = 'MemorySnapshotPage';
// 记忆导入三级页（2026-09-22 记忆导入：库管理页「更多」菜单「从其他平台导入」项 push——
// param = { libraryId }（MemoryImportParam，声明单源在发起方 MemoryLibraryPage.ets），三态
// 单页（粘贴 → 整理中 → 预览），确认后事务化批量落库 + 导入前快照；自包 PageShell 壳，
// 标题栏无菜单键（保存/导入动作在页内主键）。★ 非设置项（三级页），不进 SettingSearch
// 注册表——两处同步即可 = 本文件 + PageMap 分支〔ROUTE_MEMORY_LIBRARY_PAGE 同款例外口径〕）
export const ROUTE_MEMORY_IMPORT_PAGE: string = 'MemoryImportPage';
// 助手记忆三级页（2026-09-08 记忆域：助手编辑页「记忆」分区卡 push，param = 助手 id；
// 自包 PageShell 壳——注入/沉淀两开关行（assistants.memoryInject/memorySink 列即时
// 落库），开关即改即生效返回不挂 onPop〔编辑页摘要刷新经编辑页 onPop 重拉〕）
export const ROUTE_ASSISTANT_MEMORY_PAGE: string = 'assistantMemoryPage';
// 「存储管理」二级页（2026-09-09 附件全量落盘第二轮·存储管理页：设置页「数据与同步+
// 存储管理」组卡内第二行 push——六分类占用展示 + 可安全清理；无编辑无保存动作 → 返回
// 无参 pop 不挂 onPop〔坑17 口径〕；自包 PageShell 壳，无标题栏菜单键）
export const ROUTE_STORAGE_PAGE: string = 'storagePage';
// 「附件管理」三级页（2026-09-15 附件管理列表笔：存储管理页「会话附件」入口卡 push——按
// 会话分组列出已发送附件，可展开预览与单件删）；无编辑无保存动作 → 返回无参 pop 不挂
// onPop〔坑17 口径〕；自包 PageShell 壳，无标题栏菜单键。★ 非设置项（三级页），不进
// SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支（ROUTE_SESSION_SEARCH_PAGE
// 同款例外口径；「会话附件」作为搜索词挂在「存储管理」条目的 keywords 上）
export const ROUTE_ATTACHMENT_MANAGE_PAGE: string = 'attachmentManagePage';
// 「联网搜索」二级页·引擎列表（2026-09-10 多引擎一期；同日 UI 重构对齐服务商管理页：
// 总开关 + 分段胶囊「已启用/已停用」+ 引擎卡列表，点卡片 push 详情页配置；写操作即时
// 持久化无保存动作 → 返回无参 pop 不挂 onPop〔坑17 口径〕；自包 PageShell 壳）
export const ROUTE_SEARCH_ENGINE_PAGE: string = 'searchEnginePage';
// 「引擎配置」三级页（2026-09-10 UI 重构对齐服务商管理：列表页点引擎卡 push，param =
// 引擎 id——密钥/baseUrl/测试搜索/设为当前/启停；写偏好即时生效，列表页经 @StorageLink
// 订阅自动刷新无需 onPop；自包 PageShell 壳）
export const ROUTE_SEARCH_ENGINE_DETAIL_PAGE: string = 'searchEngineDetailPage';
// 「工具调用」二级页（2026-09-10 决明指令：设置页记忆卡下两行主卡第二行 push——先空
// 占位，后续承载内置工具全局设置；无编辑无保存动作 → 返回无参 pop 不挂 onPop〔坑17
// 口径〕；自包 PageShell 壳）
export const ROUTE_TOOLS_PAGE: string = 'toolsPage';
// 「主动消息」二级页（2026-09-12 主动消息第一笔「触发链底层」：设置页「主动消息」卡
// push——总开关 + 触发间隔两行组卡 + 说明小字；写操作即时持久化无保存动作 → 返回无参
// pop 不挂 onPop〔坑17 口径〕；自包 PageShell 壳，无标题栏菜单键）
export const ROUTE_PROACTIVE_PAGE: string = 'proactivePage';
// 「价格模板」二级页·模板列表（2026-09-11 价格模板，任务书-价格模板-20260911；服务商
// 编辑页高级页签「价格模板」卡 push，param = providerId——行卡列表（主行模板名 + 副行
// priceSummary 摘要）+ 标题栏「添加」键 + onPop 重拉；自包 PageShell 壳。★ 非设置项
//（四级页），不进 SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支
//〔ROUTE_SESSION_SEARCH_PAGE 例外口径同款〕）
export const ROUTE_PRICE_TEMPLATE_PAGE: string = 'priceTemplatePage';
// 「价格模板」三级页·模板编辑（2026-09-11 价格模板；列表页点行卡 push 携 templateId /
// 标题栏「添加」键 push templateId = '' 新建，param = PriceTemplateEditParam{providerId,
// templateId}——名称卡 + 复用 ModelPriceCard 同一张价格卡 + 标题栏保存键 + 编辑态底部
// 删除键；保存/删除 pop 带 result 触发列表页 onPop 重拉〔坑17〕；自包 PageShell 壳）
export const ROUTE_PRICE_TEMPLATE_EDIT_PAGE: string = 'priceTemplateEditPage';
//（原「自检」二级页路由常量 2026-09-20 随应用内自检功能全量退役一并撤除——入口卡、页面、
// 检测域六件与断言件同步删除，本文件不留悬空常量）
// 「余额查询」二级页·配置（2026-09-11 方案 v3 余额配置二级页化；服务商编辑页高级页签
// 「余额查询」入口卡 push，param = BalanceConfigParam{providerId}——启用开关 + 六字段 +
// 套用余额模板卡 + 余额请求头卡；滚动骨架 = Scroll+Column（反馈修正笔改，避 List 的坑9）；
// 页内自保存（updateBalanceConfig）+ 保存 pop 带 result → 入口页 onPop 自增 headEpoch 刷
// 顶卡余额徽章〔坑17〕。★ 查询键不在本页——在入口卡与「配置余额」成双键，查询链宿主页
// 自持、吃保存后库态；自包 PageShell 壳。★ 非设置项（同价格模板口径），不进
// SettingSearch 注册表——两处同步 = 本文件 + PageMap 分支）
export const ROUTE_BALANCE_CONFIG_PAGE: string = 'balanceConfigPage';
// 「技能库」二级页（2026-09-13 技能层笔 1：设置页「技能库」行卡 push + 助手技能页「管理
// 技能库」入口行 push——双入口；技能清单 + 标题栏「＋新建」+ 行卡四点键菜单，删除确认含
// 「已启用的助手将同步移除该技能」；列表刷新 = SKILL_LIST_TICK_KEY 广播；自包 PageShell 壳。
// ★ 设置项（一级行卡入口 + 搜索注册条目，三处同步 = 本文件 + PageMap 分支 + SettingSearch））
export const ROUTE_SKILL_LIBRARY_PAGE: string = 'skillLibraryPage';
// 「技能编辑」三级页（2026-09-13 技能层笔 1；技能库页「＋新建」push 空参 / 点行卡 push
// 技能 id，param = 技能 id（'' = 新建）——四段卡：身份（名称/触发描述/图标）→ 正文
//（编辑 ⇄ 静态全量 markdown 预览）→ 操作（导出 SKILL.md）→ 危险操作（删除，仅编辑态）；
// 标题栏「保存」键；保存/删除 pop 带 result → 库页 onPop/tick 重拉〔坑17〕；自包 PageShell 壳）
export const ROUTE_SKILL_EDIT_PAGE: string = 'skillEditPage';
// 助手技能三级页（2026-09-13 技能层笔 1：助手编辑页「技能」分区卡 push，param = 助手 id；
// 自包 PageShell 壳——技能开关组卡（Toggle 即时落 assistants.skills 列，第 11 个开关面
// 直接拒）+「管理技能库」入口行；开关即改即生效返回不挂 onPop〔编辑页摘要刷新经编辑页
// onPop 重拉〕。★ 控制台助手不渲染入口（编辑页隐藏）——方案 §2.8 #4
export const ROUTE_ASSISTANT_SKILL_PAGE: string = 'assistantSkillPage';
// 技能选择页（2026-09-16 单条消息指定技能：对话页「附件与提示词」半模态「技能」卡单入口
// push，param = SkillDesignateParam{skillId} 页面内 getParamByName 取）——组件参数化复用
// AssistantSkillPage（hostKind 'designate'，不新开壳）。点行即 pop 带
// SkillDesignateResult{skillId,skillName}（'' = 取消指定/未选择）→ ChatPage onPop 写两
// @State〔坑17〕；自包 PageShell 壳。★ 非设置项（会话页入口），不进 SettingSearch 注册表
//——两处同步即可 = 本文件 + PageMap 分支〔ROUTE_SESSION_SEARCH_PAGE 同款例外口径〕。
// ★ 常量名与值同改：旧名（会话技能页）属「会话级覆盖」语义，随该功能退役一并撤除
//（该路由值无持久化消费者，改名零兼容负担）
export const ROUTE_SKILL_DESIGNATE_PAGE: string = 'skillDesignatePage';
// 技能附件编辑四级页（2026-09-13 技能层笔 2「独立小编辑页」落地；技能编辑页文件组卡
// 「新建文件/上传文件」与行内编辑键 push，param = SkillFileEditParam{skillId,fileId,draftName,
// draftContent}（fileId '' = 新建，draft 初值供上传链把选择器读到的内容带进来过目）；
// 标题栏「保存」键 + 编辑态底部删除键；保存/删除 pop 带 result → 组卡 onPop 重拉〔坑17〕；
// 自包 PageShell 壳。★ 非设置项（四级页），不进 SettingSearch 注册表——两处同步即可 =
// 本文件 + PageMap 分支〔价格模板/余额配置同款口径〕）
export const ROUTE_SKILL_FILE_EDIT_PAGE: string = 'skillFileEditPage';
// 「知识库」二级页（2026-09-21 世界书知识库首版：设置页「指令面」组卡「知识库」行卡 push +
// 助手知识库页「管理知识库」入口行 push——双入口；书名清单 + 标题栏「＋」单键（新建知识库）
// + 行卡四点键菜单（重命名/删除），删除确认含「该库的全部条目一并删除，已启用它的助手将
// 同步移除」；列表刷新 = KNOWLEDGE_LIST_TICK_KEY 广播；自包 PageShell 壳。用户可见名
// 「知识库」，世界书/World Book/Lorebook 只出现在文档与代码注释里，不上屏。
// ★ 设置项（一级行卡入口 + 搜索注册条目，三处同步 = 本文件 + PageMap 分支 + SettingSearch））
export const ROUTE_KNOWLEDGE_LIBRARY_PAGE: string = 'knowledgeLibraryPage';
// 「知识库条目清单」三级页（2026-09-21 世界书知识库首版；库页点行卡 push，param =
// 书名 id（string）页面内 getParamByName 取；页标题 = 书名（查询回填），查不到 = 已删 → 返回；
// 条目行卡 = 名称 + 副行摘要 + 四点键菜单（删除）；标题栏「＋」单键（新建条目，达上限拦截）；
// 刷新 = 子页 pop 带 result 经 onPop 重拉〔坑17〕+ 本页删除自刷；自包 PageShell 壳。
// ★ 非设置项（二三级页），不进 SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支
//〔技能库域同款口径〕）
export const ROUTE_KNOWLEDGE_BOOK_PAGE: string = 'knowledgeBookPage';
// 「知识库条目编辑」四级页（2026-09-21 世界书知识库首版；条目清单页「＋」/点条目行 push，
// param = KnowledgeEditParam{bookId,entryId}（entryId '' = 新建）页面内 getParamByName 取；
// ★ 2026-09-23 知识库文件笔改**三段分段胶囊**（条目〔名称+关键词〕/ 正文 / 文件——骨架照
// SkillEditPage；编辑态三段、新建态两段〔尚未落行没有可挂附件的对象〕）+ 标题栏「保存」键
//（校验失败 toast 不静默、加载未完成不许保存——SkillEditPage 同款 O-13 闸）；保存 pop 带
// result → 清单页 onPop 重拉〔坑17〕；自包 PageShell 壳。★ 非设置项，不进 SettingSearch
// 注册表——两处同步即可 = 本文件 + PageMap 分支）
export const ROUTE_KNOWLEDGE_EDIT_PAGE: string = 'knowledgeEditPage';
// 知识库条目附件编辑页（2026-09-23 知识库文件笔；条目编辑页文件卡「新建文件/上传文件」与
// 行内编辑键 push，param = KnowledgeFileEditParam{entryId,fileId,draftName,draftContent}
//（fileId '' = 新建，draft 初值供上传链把选择器读到的内容带进来过目）；标题栏「保存」键 +
// 编辑态底部删除键；保存/删除 pop 带 result → 文件卡 onPop 重拉〔坑17〕；自包 PageShell 壳。
// ★ 非设置项（五级页），不进 SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支
//〔技能附件编辑页同款口径〕）
export const ROUTE_KNOWLEDGE_FILE_EDIT_PAGE: string = 'knowledgeFileEditPage';
// 助手知识库三级页（2026-09-21 世界书知识库首版：助手编辑页「知识库」分区卡 push，param =
// 助手 id；自包 PageShell 壳——知识库开关组卡（Toggle 即时落 assistants.knowledge 列，第 11
// 个开关面直接拒）+「管理知识库」入口行；开关即改即生效，返回 pop 带 result 触发编辑页
// onPop 重拉摘要〔坑17〕。★ 控制台助手照常可用（知识库与技能不同——一期对控制台不设封锁）
export const ROUTE_ASSISTANT_KNOWLEDGE_PAGE: string = 'assistantKnowledgePage';
// 附件查看器二级页（2026-09-15 附件查看器二级页化：承载由「全屏模态 bindContentCover」改
// 导航栈内二级页——两宿主 push〔会话页附件泡/输入栏附件条 + 附件管理页行点击〕，param =
// AttachmentViewerParam{items,index} 页面内 getParamByName 取；改页面后顶部归官方 HDS 标题栏
// 〔渐变模糊 + 沉浸光感材质〕，两模式默认不让内容进蒙层（图片 1x 留白下发页件、文本 topPad
// 走内容内层，放大后可进——同日顶栏分享笔口径）。无编辑无保存动作
// → 返回无参 pop 不挂 onPop〔坑17 口径〕；自包 PageShell 壳，标题栏右上角「分享」键（官方
// 菜单数组，构造在 AttachmentViewerPage）。★ 非设置项，
// 不进 SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支
//〔ROUTE_SESSION_SEARCH_PAGE 同款例外口径〕）
export const ROUTE_ATTACHMENT_VIEWER_PAGE: string = 'attachmentViewerPage';
