// 官方路由名单一来源（随迁 dshinhm 同名规范）：PageMap 分支（nav/HomeNavigation.ets）、各页
// pushPathByName、设置项搜索注册表 pageName 三处同源引用——拼错任一 = NavDestination 分支
// 不匹配、页面空白（坑51 同族）。新增路由 = 本文件加常量 + PageMap 链尾 else if 分支 + 注册表
// 条目（三处同步，scripts/setting-search-check.mjs 机械把关）。常量名 = 路由名 + _PAGE 后缀；
// 值 = PageMap 注册名；Tab 内容页不经 PageMap 无常量。
// 通用口径（下文不逐条重复）：各页自包 PageShell 壳；写即持久化/无保存动作的页返回无参 pop
// 不挂 onPop〔坑17 口径〕，保存类页 pop 带 result 触发上级 onPop 重拉。「★ 非设置项」= 不进
// SettingSearch 注册表——两处同步即可 = 本文件 + PageMap 分支（设置项才三处同步）。

// 对话页（会话列表卡片 push，param = null）
export const ROUTE_CHAT_PAGE: string = 'chatPage';
// 服务商管理二级页（设置页行卡 push）
export const ROUTE_PROVIDER_PAGE: string = 'providerPage';
//（服务商排序三级页已退役：排序回管理页列表原位长按拖拽〔onMove〕，坑10 由 List 挂
// `.clip(false)` 消解——见 ProviderPage 头注释）
// 服务商详情三级页：列表页卡片 push 携 providerId；标题栏「+」键无参 push = 新建；壳含「保存」键
export const ROUTE_PROVIDER_DETAIL_PAGE: string = 'ProviderDetailPage';
// 编辑模型四级页：详情页模型页签 push，param = ModelEditParam（providerId + modelRowId，后者空 = 新建）
export const ROUTE_MODEL_EDIT_PAGE: string = 'ModelEditPage';
//（原「外观显示」二级页路由常量已随偏好与外观重梳笔退役，不留悬空常量——外观三段拆为
//「偏好与外观」页三张入口行 + 三张三级页〔背景 / 字体 / 图标〕，沿革见变更记录）
// 更多信息二级页：骨架 + 关于
export const ROUTE_INFO_PAGE: string = 'InfoPage';
// 设置项搜索页：设置页签标题栏搜索键 push；注册表禁止包含本页（防循环）
export const ROUTE_SEARCH_PAGE: string = 'SearchPage';
// 图片编辑裁剪二级页：背景面板「选择图片/编辑图片」push，param = EditImageParam
export const ROUTE_IMAGE_EDIT_PAGE: string = 'ImageEditPage';
// 图片编辑调整二级页：裁剪页「下一步」push，param = AdjustPageParam；保存后 popToName 一次弹两级回背景页
export const ROUTE_IMAGE_ADJUST_PAGE: string = 'ImageAdjustPage';
// 待发图片裁剪二级页（★ 非设置项，不进搜索注册表）：会话页拍照/相册选图后由
// AttachmentPickCtrl 经 ChatPage 注入的路由能力 push，param = PhotoEditParam{srcPath}；
// pop 恒带 PhotoEditOutcome{path, thumb}（定义在 AttachmentUtil），'' = 放弃这张、原图路径
// = 编辑失败、成品路径 = 裁剪成功；thumb = 保存后预解的缩略图（非空则入列侧免二次解码）
export const ROUTE_PHOTO_EDIT_PAGE: string = 'PhotoEditPage';
// 关于三级页：更多信息页行卡；pathStack 供 AI 声明/开源鸣谢卡 push 下级页
export const ROUTE_ABOUT_PAGE: string = 'AboutPage';
// 权限信息页：更多信息页行卡（上架合规展示面）；纯展示无下级跳转
export const ROUTE_PERMISSION_PAGE: string = 'PermissionPage';
// AI 辅助开发声明页：关于页卡片 push；纯展示
export const ROUTE_AI_ASSIST_PAGE: string = 'AiAssistPage';
// 开源项目鸣谢页：关于页卡片 push；纯展示
export const ROUTE_OPEN_SOURCE_PAGE: string = 'OpenSourcePage';
// 隐私政策页：更多信息页行卡（上架合规入口）；纯展示
export const ROUTE_PRIVACY_POLICY_PAGE: string = 'PrivacyPolicyPage';
// 运行日志三级页：更多信息页条目 push；壳含「更多」菜单
export const ROUTE_LOG_PAGE: string = 'LogPage';
// 请求日志三级页：更多信息页条目 push；壳含「更多」菜单与半模态详情面板宿主。HTTP 工具审计
// 用法由本页「只看 HTTP 请求」筛选档承接（原「出站记录」入口已退役）
export const ROUTE_REQ_LOG_PAGE: string = 'ReqLogPage';
// 提示词库管理二级页：设置页行卡 push——管理系统提示词与会话模板
export const ROUTE_PROMPT_LIBRARY_PAGE: string = 'PromptLibraryPage';
// 提示词编辑三级页：管理页 push，param = 模板 id（空 = 新增）；壳含「保存」键（系统提示词
// 由 ROUTE_SYSTEM_PROMPT_PAGE 承载）
export const ROUTE_PROMPT_EDIT_PAGE: string = 'PromptEditPage';
// 系统提示词独立页（决明拍板与会话提示词「分开」：内置默认可更改可重置）：入口 = 「会话
// 提示词」页列表首卡 + 搜索条目 push 无参；壳无菜单键、底部「恢复/保存」两键
export const ROUTE_SYSTEM_PROMPT_PAGE: string = 'SystemPromptPage';
// 助手编辑二级页：助手页签列表卡点击 push（恒编辑态——新建走列表页「＋」对话框不经本页）；
// 纯分区导航枢纽（名称行卡 + 提示词/记忆/工具调用/技能/知识库/高级设定六卡，底部无按钮）
export const ROUTE_ASSISTANT_EDIT_PAGE: string = 'AssistantEditPage';
//（助手排序三级页已退役：排序改助手页列表原位长按拖拽，原「Scroll+Column〔坑9〕须独立成页」
// 判据随容器改造失效——见 AssistantPage 头注释）
// 助手提示词三级页：编辑页「提示词」分区卡 push，param = 助手 id；用户手建 = SystemPromptPage
// 同款表单（变量插入 + 内容 + 底部保存），内置默认助手 = 只读展示
export const ROUTE_ASSISTANT_PROMPT_PAGE: string = 'AssistantPromptPage';
// ★ 原「助手分区占位三级页」「助手模型设置三级页」路由常量已随功能退役删除（占位清空 /
// 决明「去掉模型设置二级页」，页面件与 PageMap 分支同笔删）——此处不留名以免与全仓零该
// 符号的死代码复核打架，沿革见变更记录
// 「偏好与外观」二级页（决明拍板重梳：原「偏好设置」页扩容承载外观域——七入口行〔使用习惯
// 三行：输入与发送 / 回复显示 / 会话与阅读；外观三行：背景 / 字体 / 图标；应用一行：应用与
// 启动〕；persistProp 即时生效无保存键。路由名沿用 preferencesPage 不变，仅标题改「偏好与外观」）
export const ROUTE_PREFERENCES_PAGE: string = 'preferencesPage';
// 偏好「输入与发送」页：偏好一级页第 1 入口行 push——键盘发送 / 粘贴长文本转文件 / 时间
// 间隔提醒 / 网络自动重试；传 pathStack（「自动重试」push 下级页）
export const ROUTE_PREF_INPUT_SEND_PAGE: string = 'prefInputSendPage';
// 「自动重试」三级页：输入与发送页入口行 push——原组内开关行升级为独立页（总开关〔承接旧
// 布尔语义〕+ 重试参数四数字行 + 状态码与重试/停止关键字三清单 chips）；无标题栏菜单键
export const ROUTE_PREF_AUTO_RETRY_PAGE: string = 'prefAutoRetryPage';
// 偏好「回复显示」页：第 2 入口行——默认展开思考 / 流式引擎 / 流式输出自动跟随
export const ROUTE_PREF_REPLY_DISPLAY_PAGE: string = 'prefReplyDisplayPage';
// 偏好「会话与阅读」页：第 3 入口行——屏幕常亮
export const ROUTE_PREF_SESSION_READ_PAGE: string = 'prefSessionReadPage';
// 偏好「应用与启动」页：第 4 入口行——页签切换动画 / 启动默认页面
export const ROUTE_PREF_APP_LAUNCH_PAGE: string = 'prefAppLaunchPage';
// 「背景」三级页（原外观显示页「背景」段独立成页）：偏好与外观页「背景」入口行 push——
// BackgroundPanel 整页承载（选图 → 编辑页链回跳本页）；传 pathStack（面板 push 图片编辑页）
export const ROUTE_PREF_BACKGROUND_PAGE: string = 'prefBackgroundPage';
// 「字体」三级页（原外观显示页「字体」段独立成页）：偏好与外观页「字体」入口行 push——
// ChatFontSection 整页承载（字体展示 / 正文与代码字体 / 自定义字体管理）；无下级跳转
export const ROUTE_PREF_FONT_PAGE: string = 'prefFontPage';
// 「数据与同步」二级页：全量导入导出 + WebDAV
export const ROUTE_DATA_SYNC_PAGE: string = 'DataSyncPage';
// 「导入 DeepSeek 对话」三级页：数据与同步页入口卡 push 无参——三态单页（选包 → 校验预览 →
// 确认应用），DS 导出 zip 解析为图态新会话落库（不覆盖现有会话）。★ 设置项（三处同步）；
// 帮助中心另立同名条目
export const ROUTE_DS_HISTORY_IMPORT_PAGE: string = 'dsHistoryImportPage';
// 功能模型二级页：设置页「功能模型」卡 push——功能级模型配置集中页，首项「默认模型」=
// 发送链四级兜底第③级来源；含模型选择半模态
export const ROUTE_FUNCTIONAL_MODEL_PAGE: string = 'functionalModelPage';
// 助手高级设定二级页：编辑页「高级设定」卡 push，param = 助手 id——两行卡（采样参数/
// 上下文与输出，副行摘要随三级页 onPop 重拉）
export const ROUTE_ASSISTANT_ADVANCED_PAGE: string = 'assistantAdvancedPage';
// 助手采样参数三级页：「采样参数」行卡 push，param = 助手 id——四开关卡（开 → 卡内展开
// 官方 InSet 滑块）；返回时 onBackPressed 拦截统一落库
export const ROUTE_ASSISTANT_SAMPLING_PAGE: string = 'assistantSamplingPage';
// 助手上下文与输出三级页：「上下文与输出」行卡 push，param = 助手 id——上下文消息数/
// 最大输出长度两滑块卡（编辑键弹数字输入对话框）；返回时统一落库
export const ROUTE_ASSISTANT_CONTEXT_PAGE: string = 'assistantContextPage';
export const ROUTE_ASSISTANT_TOOLS_PAGE: string = 'assistantToolsPage';
// 助手 MCP 服务器开关三级页：编辑页组卡「MCP」行 push，param = 助手 id——按助手勾选
// 服务器开关（写 assistants.mcpServers 列）；服务器的增删改仍在设置侧 MCP 管理页
export const ROUTE_ASSISTANT_MCP_PAGE: string = 'assistantMcpPage';
// 帮助中心页：更多信息页行卡 push——分板块卡片说明应用功能与用法；条目卡可点进详情页
//（pathStack 传入）
export const ROUTE_HELP_CENTER_PAGE: string = 'helpCenterPage';
// 帮助条目详情页：帮助中心页条目卡 push，param = 条目 id「分组标题::条目标题」，经
// HelpContent.findHelpTopic 还原内容；纯展示，pathStack 仅读参
export const ROUTE_HELP_TOPIC_PAGE: string = 'helpTopicPage';
// 「用量统计」二级页：设置页卡 push——概览六数字 / 按模型 / 近30天逐日列表
export const ROUTE_USAGE_STATS_PAGE: string = 'UsageStatsPage';
// 「费用估计」二级页：设置页「用量统计+费用估计」组卡第二行 push——模型价格 × token 用量
// 折算估算，总览四格/模型排行/用途分布三卡，时段胶囊与用量统计页同源
export const ROUTE_COST_STATS_PAGE: string = 'costStatsPage';
// 「反馈与建议」页：更多信息页行卡 push（帮助中心行卡下方）——反馈文本经第三方推送服务
// api.chuckfang.com 直达开发者手机，零自有服务器；纯表单
export const ROUTE_FEEDBACK_PAGE: string = 'FeedbackPage';
// 会话搜索二级页：对话页签标题栏搜索键 push——搜索范围 = 当前助手名下全部会话标题；
// 打开会话经 HomeNavigation.openSession 既有链（不自接 push ChatPage）。★ 非设置项
export const ROUTE_SESSION_SEARCH_PAGE: string = 'SessionSearchPage';
// 「记忆」二级页：设置页「记忆」卡 push——跨会话长期记忆管理：总开关/自动整理 + 条目列表
// 查看/编辑/删除/手动添加；标题栏「＋」与「⋯」（排序/立即整理/优化记忆收进「更多」菜单）
export const ROUTE_MEMORY_PAGE: string = 'memoryPage';
// 记忆编辑三级页（决明指令：添加/编辑一律进二级页，形制对齐 PromptEditPage）：记忆页「＋」
// push 空参 = 新增、点条目卡 push 记忆 id = 编辑；壳含「保存」键
export const ROUTE_MEMORY_EDIT_PAGE: string = 'MemoryEditPage';
//（记忆排序三级页已退役：排序改库管理页列表原位长按拖拽——与服务商/助手三处统一，见
// MemoryLibraryPage 头注释）
// 记忆库管理三级页：设置记忆页点库卡 push，param = { libraryId }（'global' = 全局库 /
// 助手 id = 助手库）；条目管理面（列表/增删改/排序/立即整理/优化）操作面跟库走；标题栏
//〔＋|⋯〕胶囊。★ 非设置项
export const ROUTE_MEMORY_LIBRARY_PAGE: string = 'MemoryLibraryPage';
// 记忆历史三级页：库管理页「更多」菜单 push，param = { libraryId }（MemoryLibraryParam 复用，
// 声明单源在 MemoryPage.ets）——列出该库最近改动前快照（优化前/导入前共用配额）+ 恢复前
// 兜底，行卡恢复键整库回退；无标题栏菜单键。★ 非设置项
export const ROUTE_MEMORY_HISTORY_PAGE: string = 'MemoryHistoryPage';
// 记忆快照详情三级页：历史页点行卡 push，param = MemorySnapshotParam{snapshotId}（声明单源
// 在发起方 MemoryHistoryPage.ets），只读列条目；★ 不设恢复键（恢复入口唯一在列表行卡，
// 多入口 = 误触与歧义）。★ 非设置项
export const ROUTE_MEMORY_SNAPSHOT_PAGE: string = 'MemorySnapshotPage';
// 记忆导入三级页：库管理页「更多」菜单「从其他平台导入」push，param = { libraryId }
//（MemoryImportParam，声明单源在发起方 MemoryLibraryPage.ets）——三态单页（粘贴 → 整理中
// → 预览），确认后事务化批量落库 + 导入前快照；保存/导入动作在页内主键。★ 非设置项
export const ROUTE_MEMORY_IMPORT_PAGE: string = 'MemoryImportPage';
// 助手记忆三级页：编辑页「记忆」分区卡 push，param = 助手 id——注入/沉淀两开关行
//（assistants.memoryInject/memorySink 即时落库，编辑页摘要经其 onPop 重拉）
export const ROUTE_ASSISTANT_MEMORY_PAGE: string = 'assistantMemoryPage';
// 「存储管理」二级页：设置页组卡内第二行 push——六分类占用展示 + 可安全清理；无标题栏菜单键
export const ROUTE_STORAGE_PAGE: string = 'storagePage';
// 「附件管理」三级页：存储管理页「对话附件」行 push——按会话分组列出已发送附件，可展开
// 预览与单件删；无标题栏菜单键。★ 非设置项（「会话附件」「对话附件」搜索词挂在「存储
// 管理」条目 keywords 上）
export const ROUTE_ATTACHMENT_MANAGE_PAGE: string = 'attachmentManagePage';
// 「快速清理」三级页：存储管理页「快速清理」入口卡 push——各域数据分项列出（每项一张行卡），
// 逐项确认后清除，执行后页内重载读数；无标题栏菜单键。★ 非设置项（「快速清理」搜索词挂在
//「存储管理」条目 keywords 上）；帮助中心另立同名条目
export const ROUTE_QUICK_CLEAN_PAGE: string = 'quickCleanPage';
// 「文件工作区」二级页：设置页「联网搜索 + 工具调用」卡内第三行 push——列出助手保存与用户
// 上传的工作区文件，可预览/分享/上传/单件删除与清空；标题栏「更多」菜单三项（新建文件夹/
// 上传文件/清空工作区）；传 pathStack（预览 push 查看器）。★ 设置项（三处同步，搜索「文件
// 工作区」直达本页）；帮助中心另立同名条目
export const ROUTE_WORKSPACE_MANAGE_PAGE: string = 'workspaceManagePage';
// 「文件夹挂载」二级页：设置页卡 4 第四行 push——授权 AI 访问本机文件夹（系统 FOLDER
// 选择器 + 持久授权），管理挂载清单：添加/改名/切换模式/访问开关/重新授权/移除；授权与行
// 读写即时落定；无标题栏菜单键。★ 设置项（三处同步，搜索「文件夹挂载」直达本页）；帮助
// 中心另立同名条目
export const ROUTE_MOUNT_MANAGE_PAGE: string = 'mountManagePage';
// 「文件夹挂载」浏览页：管理页点挂载卡 push，param = MountBrowseParam{mountId}——只读浏览：
// 面包屑 + 条目列表 + 预览三路 + 复制到工作区；传 pathStack（预览 push 附件查看器）。
// ★ 非设置项；帮助说明挂在「文件夹挂载」条目 detail 内（不另立条目）
export const ROUTE_MOUNT_BROWSE_PAGE: string = 'mountBrowsePage';
// 「识别文字」三级页：工作区管理页文件行菜单或识别完成自动进入，param =
// WorkspaceOcrPageParam{fileId, name}（声明单源在发起方 WorkspaceOcrPage.ets）——预识别文本
// 查看与校对，保存链 = 返回统一落库且 pop 恒带 result（管理页 onPop 刷新菜单标签）。★ 非设置项
export const ROUTE_WORKSPACE_OCR_PAGE: string = 'workspaceOcrPage';
// 「联网搜索」二级页：条数卡 + 超时卡 + 引擎卡列表同屏，点卡片 push 详情页配置
export const ROUTE_SEARCH_ENGINE_PAGE: string = 'searchEnginePage';
// 「引擎配置」三级页：列表页点引擎卡 push，param = 引擎 id——密钥/baseUrl/测试搜索/设为
// 当前/启停；写偏好即时生效，列表页经 @StorageLink 订阅自动刷新无需 onPop
export const ROUTE_SEARCH_ENGINE_DETAIL_PAGE: string = 'searchEngineDetailPage';
// 「工具调用」二级页：设置页记忆卡下主卡第二行 push——内置工具全局设置
export const ROUTE_TOOLS_PAGE: string = 'toolsPage';
// 「MCP」三级页：工具调用页首组卡第五行 push 无参——MCP 服务器管理页：清单增删改查、测连
// 与工具同步；无标题栏菜单键
export const ROUTE_MCP_PAGE: string = 'mcpPage';
// 「MCP 服务器编辑」四级页：MCP 管理页行卡与「添加服务器」键 push，param =
// McpEditParam{ serverId }（'' = 新建）——新建/编辑表单 + 保存后自动测连 + 删除级联；
// 保存/删除 pop 带 result 触发管理页 onPop 重拉。★ 非设置项
export const ROUTE_MCP_SERVER_EDIT_PAGE: string = 'mcpServerEditPage';
// 「网络设置」二级页：设置页「网络」组卡单行跳转——页内 User-Agent 内容卡（默认值 + 输入 +
// 重置，写即持久化）；全局 UA 兜底写入单源在 common/providers/RequestIdentity.ets
export const ROUTE_NETWORK_PAGE: string = 'networkPage';
// 「Web 服务」二级页：设置页卡 5「网络」第二行 push——浏览器远程访问设置页：启动卡（开关/
// 地址/口令）+ 服务设置（端口/仅本机）+ 安全提示卡；无标题栏菜单键
export const ROUTE_WEB_SERVICE_PAGE: string = 'webServicePage';
// 「HTTP 请求」三级页：工具调用页内跳转行落点——http_request 工具专属设置（超时上限/凭据/
// 域名准入/请求模板；审计用法见 ROUTE_REQ_LOG_PAGE 注释）；无标题栏菜单键
export const ROUTE_HTTP_REQUEST_PAGE: string = 'httpRequestPage';
// 原「浏览器控制」三级页常量已随三档归一笔记退役（2026-11-09）：该页只有「网页高危操作
// 确认」一张卡，审批并入「新会话默认权限」三档统管，整页删除，勿回游。
// 「HTTP 凭据」总览页 + 管理页（决明拍板双入口）：总览页 = HTTP 请求设置页第三张卡 push
// 无参（全局卡 + 每助手卡）；管理页 param = owner（'global' 或助手 id），入口两处 = 总览页
// 卡与助手编辑页「HTTP 凭据」分区卡（编辑页 push 直达本助手组）
export const ROUTE_HTTP_CREDENTIALS_PAGE: string = 'httpCredentialsPage';
export const ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE: string = 'httpCredentialManagePage';
// 「HTTP 凭据」三级页·凭据编辑：管理页「添加凭据」push credId = '' 新建 / 行菜单「编辑」
// push credId，param = HttpCredEditParam{owner, credId}——名称 + 值 + 用途说明三字段一处填，
// 标题栏「保存」键；保存 pop 带 result 触发管理页 onPop 重拉。★ 非设置项
export const ROUTE_HTTP_CREDENTIAL_EDIT_PAGE: string = 'httpCredentialEditPage';
// 「脚本工作台」设置页 + 「脚本联网域名」总览页 + 管理页（照 HTTP 凭据三件套形制）：设置页
// = 工具调用页首组卡「脚本工作台」行 push 无参（档位段控 + 域名入口卡）；总览页 = 域名入口
// 卡 push 无参（全局卡 + 每助手卡）；管理页 param = owner（'global' 或助手 id），入口两处 =
// 总览页卡与助手编辑页「脚本联网域名」分区卡
export const ROUTE_CODE_WORKBENCH_PAGE: string = 'codeWorkbenchPage';
export const ROUTE_CODE_HTTP_HOSTS_PAGE: string = 'codeHttpHostsPage';
export const ROUTE_CODE_HTTP_HOST_MANAGE_PAGE: string = 'codeHttpHostManagePage';
// 「HTTP 请求模板」列表页 + 编辑页：列表页 = HTTP 请求设置页入口卡 push 无参；编辑页 push
// param = 'new' | 模板 id。编辑页保存 → pop({ saved: true })（坑17：子页 pop 必带 result
// 才触发列表页 onPop 重拉）；无保存动作的直接返回不带 result、列表页不重拉（数据未变，
// 不刷即期望行为）
export const ROUTE_HTTP_TEMPLATE_PAGE: string = 'httpTemplatePage';
export const ROUTE_HTTP_TEMPLATE_EDIT_PAGE: string = 'httpTemplateEditPage';
// 「主动消息」二级页：设置页卡 push——总开关 + 触发间隔两行组卡 + 说明小字；无标题栏菜单键
export const ROUTE_PROACTIVE_PAGE: string = 'proactivePage';
// 「价格模板」二级页·服务商选择：服务商管理页标题栏「更多」菜单「价格模板」项 push——行卡
// 列表 = 服务商名（全集含停用与内置），点行 push 模板列表页携 providerId；本页无写动作。
// ★ 非设置项
export const ROUTE_PRICE_TEMPLATE_PROVIDERS_PAGE: string = 'priceTemplateProvidersPage';
// 「价格模板」二级页·模板列表：服务商选择页点行 push，param = providerId——行卡列表（主行
// 模板名 + 副行 priceSummary 摘要）+ 标题栏「添加」键 + onPop 重拉。★ 非设置项
export const ROUTE_PRICE_TEMPLATE_PAGE: string = 'priceTemplatePage';
// 「价格模板」三级页·模板编辑：列表页点行 push 携 templateId / 「添加」键 push templateId =
// '' 新建，param = PriceTemplateEditParam{providerId, templateId}——名称卡 + 复用
// ModelPriceCard + 标题栏保存键 + 编辑态底部删除键；保存/删除 pop 带 result 触发列表页重拉
export const ROUTE_PRICE_TEMPLATE_EDIT_PAGE: string = 'priceTemplateEditPage';
//（原「自检」二级页路由常量 2026-09-20 随应用内自检全量退役撤除，不留悬空常量）
// 「余额查询」二级页·配置：服务商编辑页高级页签「余额查询」入口卡 push，param =
// BalanceConfigParam{providerId}——启用开关 + 六字段 + 套用模板卡 + 请求头卡；滚动骨架 =
// Scroll+Column（避 List 坑9）；页内自保存 + 保存 pop 带 result → 入口页 onPop 刷余额徽章。
// ★ 查询键不在本页（在入口卡与「配置余额」成双键，查询链宿主页自持、吃保存后库态）。
// ★ 非设置项
export const ROUTE_BALANCE_CONFIG_PAGE: string = 'balanceConfigPage';
// 「技能库」二级页：设置页行卡 push 无参——★ **唯一入口**（决明指令：管理只在设置页）；
// 技能清单 + 「＋新建」+ 行卡四点键菜单，删除确认含「已启用的助手将同步移除该技能」；
// 刷新 = SKILL_LIST_TICK_KEY 广播。★ 设置项（三处同步）
export const ROUTE_SKILL_LIBRARY_PAGE: string = 'skillLibraryPage';
// 「技能编辑」三级页：库页「＋新建」push 空参 / 点行卡 push 技能 id（'' = 新建）——四段卡：
// 身份（名称/触发描述/图标）→ 正文（编辑 ⇄ markdown 预览）→ 操作（导出 SKILL.md）→ 危险
// 操作（删除，仅编辑态）；标题栏「保存」键
export const ROUTE_SKILL_EDIT_PAGE: string = 'skillEditPage';
// 助手技能三级页：编辑页「技能」分区卡 push，param = 助手 id——技能开关组卡（Toggle 即时落
// assistants.skills 列，第 11 个开关面直接拒）；★ 管理入口只在设置页（本页无管理入口，
// 形态对齐助手记忆页「条目只读、管理去设置页」）；控制台助手不渲染入口（编辑页隐藏）。
// ★ 原「技能选择页」路由已退役——技能选择改「会话设置」半模态第四子态（SkillPickPanel；
// ★ 2026-10-30 面板自「附件与提示词」更名）
export const ROUTE_ASSISTANT_SKILL_PAGE: string = 'assistantSkillPage';
// 技能附件编辑四级页：技能编辑页文件组卡「新建/上传文件」与行内编辑键 push，param =
// SkillFileEditParam{skillId,fileId,draftName,draftContent}（fileId '' = 新建，draft 初值供
// 上传链把选择器内容带进来过目）；标题栏「保存」+ 编辑态底部删除键。★ 非设置项
export const ROUTE_SKILL_FILE_EDIT_PAGE: string = 'skillFileEditPage';
// 「知识库」二级页：设置页「指令面」组卡行卡 push——★ **唯一入口**（决明指令：助手知识库
// 页的管理入口已撤，管理只在设置页）；书名清单 + 标题栏「＋」+ 行卡四点键菜单（重命名/
// 删除），删除确认含「该库的全部条目一并删除，已启用它的助手将同步移除」；刷新 =
// KNOWLEDGE_LIST_TICK_KEY 广播。用户可见名「知识库」，世界书/World Book 只在文档与注释里
// 不上屏。★ 设置项（三处同步）
export const ROUTE_KNOWLEDGE_LIBRARY_PAGE: string = 'knowledgeLibraryPage';
// 「知识库条目清单」三级页：库页点行卡 push，param = 书名 id；页标题 = 书名（查询回填），
// 查不到 = 已删 → 返回；条目行卡 + 四点键菜单（删除）；标题栏「＋」新建（达上限拦截）。
// ★ 非设置项
export const ROUTE_KNOWLEDGE_BOOK_PAGE: string = 'knowledgeBookPage';
// 「知识库条目编辑」四级页：清单页「＋」/点条目行 push，param = KnowledgeEditParam{bookId,
// entryId}（'' = 新建）——**三段分段胶囊**（条目〔名称+关键词〕/ 正文 / 文件，骨架照
// SkillEditPage；编辑态三段、新建态两段）+ 标题栏「保存」键（校验失败 toast 不静默、加载
// 未完成不许保存）。★ 非设置项
export const ROUTE_KNOWLEDGE_EDIT_PAGE: string = 'knowledgeEditPage';
// 知识库条目附件编辑页：条目编辑页文件卡「新建/上传文件」与行内编辑键 push，param =
// KnowledgeFileEditParam{entryId,fileId,draftName,draftContent}（fileId '' = 新建，draft
// 初值同技能附件页语义）；标题栏「保存」+ 编辑态底部删除键。★ 非设置项
export const ROUTE_KNOWLEDGE_FILE_EDIT_PAGE: string = 'knowledgeFileEditPage';
// 助手知识库三级页：编辑页「知识库」分区卡 push，param = 助手 id——知识库开关组卡（Toggle
// 即时落 assistants.knowledge 列，第 11 个开关面直接拒）；★ 管理入口只在设置页（形态对齐
// 助手记忆页「条目只读、管理去设置页」）；控制台助手不渲染本页入口（编辑页知识库卡对它
// 整段不渲染，与技能同口径）
export const ROUTE_ASSISTANT_KNOWLEDGE_PAGE: string = 'assistantKnowledgePage';
// 附件查看器二级页（由全屏模态改导航栈二级页）：两宿主 push（会话页附件泡/输入栏附件条 +
// 附件管理页行点击），param = AttachmentViewerParam{items,index}——顶部归官方 HDS 标题栏
//〔渐变模糊 + 沉浸光感〕，两模式默认不让内容进蒙层（放大后可进）；标题栏右上角「分享」键。
// ★ 非设置项
export const ROUTE_ATTACHMENT_VIEWER_PAGE: string = 'attachmentViewerPage';
// 「会话轨迹」二级页：会话页「更多」菜单「会话轨迹」项 push，param = 会话 id——轮/记录行
// 只读账表 + 简化时间条 + 记录详情半模态。★ 非设置项
export const ROUTE_SESSION_TRACE_PAGE: string = 'sessionTracePage';
// 「会话工作区」二级页：会话页「更多」菜单「会话工作区」项 push，param = 会话 id——只显示
// 本会话的工作区文件（conversationId 追溯列命中件；上传/挂载复制件恒空串不进本页），可预览/
// 分享/改名/移动与删除；面包屑单段置灰承载位置感。★ 非设置项
export const ROUTE_SESSION_WORKSPACE_PAGE: string = 'sessionWorkspacePage';
// 「Python 运行验证」页（2026-11-06 鸿蒙Python运行时门1笔）：门 1 临时验证面——初始化内嵌
// 解释器 + 固定诊断脚本回显。入口 = 构建 PY_PROBE_ENABLED 开关门控（默认 false 零渲染，
// true 时工具调用页列表尾出临时行——门 4 前不接正式功能链、不进设置搜索注册表）。
// ★ 非设置项（临时验证面）
export const ROUTE_PY_RUNTIME_PROBE_PAGE: string = 'pyRuntimeProbePage';
// 「Node 运行验证」页（2026-11-23 鸿蒙Node运行时门1笔）：门 1 临时验证面——准备引导脚本 +
// 启动宿主壳 + 固定诊断脚本回显。入口 = 构建 NODE_PROBE_ENABLED 开关门控（默认 false 零渲染，
// true 时工具调用页列表尾出临时行——门 2 前不接正式功能链、不进设置搜索注册表）。
// ★ 非设置项（临时验证面）
export const ROUTE_NODE_RUNTIME_PROBE_PAGE: string = 'nodeRuntimeProbePage';
// 「Python 运行环境」设置页（2026-11-14 闲3门4批，母方案 §2.6）：正式管理页——解释器状态
// 与预置包只读清单，「检查环境」键触发首用落位与初始化（幂等）。入口 = 工具调用页首组卡
// 「Python 运行环境」行 push 无参，紧邻「脚本工作台」行。★ 设置项（三处同步）；帮助条目
// 同批已入 HelpContent（「Python 运行」组）。与探针页分工——管理页是正式面，探针页仍是构建期
// 开关门控的临时验证面
export const ROUTE_PY_RUNTIME_PAGE: string = 'pyRuntimePage';
// 「Node 运行环境」设置页（2026-11-24 鸿蒙 Node 运行时门 4，任务书-鸿蒙Node运行时门4产品面与发布
// -20261124）：正式管理页——运行环境状态与两项占用回显，「检查环境」键幂等拉起运行区（落位 +
// 启动），已装包只读清单，维护卡清空安装包 / 重建运行区 / 重启应用。入口 = 工具调用页首组卡
//「Node 运行环境」行 push 无参，紧跟「Python 运行环境」行。★ 设置项（三处同步）；帮助说明挂在
// HelpContent「Node 运行」条目内（不另立条目）。与探针页分工——管理页是正式面，探针页仍是构建期
// 开关门控的临时验证面
export const ROUTE_NODE_RUNTIME_PAGE: string = 'nodeRuntimePage';
// 「助手」二级页（2026-11-16 首页布局双形态笔，方案档 §3.8）：侧栏对话形态下侧栏底部
//「助手」入口与助手切换面板「管理助手」push——页签形态照旧走 TabContent 不经本路由。
// 内容组件 = AssistantPage 原件，壳层 = AssistantPageHost（PageShell + 标题栏覆盖层「＋」
// 新建键）。★ 非设置项（页签同名页已是设置可搜入口，本路由不进搜索注册表——两处同步）
export const ROUTE_ASSISTANT_PAGE: string = 'assistantPage';
// 「设置」二级页（同笔）：侧栏底部「设置」入口 push——内容组件 = SettingsPage 原件，壳层 =
// SettingsPageHost（PageShell + 标题栏覆盖层常显搜索键——「带内假框 ⇄ 右上角键」互斥是
// 页签形态专属，二级页化后重映射为常显入口，方案档 §3.8）。★ 非设置项（同上不进注册表）
export const ROUTE_SETTINGS_PAGE: string = 'settingsPage';
// 「侧栏会话」伪侧栏二级页（2026-11-18 侧栏二级页化笔，决明拍板）：drawer 形态首页汉堡键
// push——全宽页承载原侧栏内容（助手行标题栏 + 分段带 + 会话列表 + 多选域页内自持）。转场 =
// 官方默认（首版自绘反向转场已随二次校正退役——官方页壳下自绘位移会破坏标题栏避让；关闭 =
// 返回键 / 系统返回手势）。★ 非设置项（两处同步即可）
export const ROUTE_SIDE_PANEL_PAGE: string = 'sidePanelPage';
