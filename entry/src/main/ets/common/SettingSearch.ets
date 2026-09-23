// 设置项搜索注册表（2026-08-29 M2c 自 dshinhm 同名文件精简随迁；设置页签标题栏搜索键 →
// 搜索页 SearchPage）：全应用可搜索设置项的单一数据源 + 标题常量单一来源 + 搜索历史持久化
// + 最近使用记录。
//
// ★ 可维护性约定（防误删/防漂移，新增或改名设置项时必须三处同步）：
//   ① 页面 UI 文字：一律引用本文件的 SETTING_TITLE_* 常量（禁止再写字面量）——
//      搜索结果文字与实际 UI 永远一致，改名只改常量一处；
//   ② 路由：nav/HomeNavigation.ets PageMap 链尾加 else if 分支（if/else if 链，坑51）；
//   ③ 注册表：SETTING_SEARCH_ITEMS 加条目（title 用常量、path 用常量拼接）。
//   ④ 帮助条目（2026-09-05 接入）：不经手写——buildHelpSearchItems 程序化生成自
//      common/HelpContent.ets（增删帮助条目只动 HelpContent，注册表自动同步零双源）。
// 可搜范围定稿（口径随 dshinhm 规范「能操作和不能操作的项都算设置项，但不是全可搜」）：
//   可搜 = 一级行卡入口 + 二级页内设置项；不搜 = 搜索页自身（防循环：注册表不含
//   SearchPage，跳转永远离开搜索页）。判定口诀：用户会不会想通过搜索找到并打开它——
//   会，就搜；它只是某个流程里的一步，就不搜。完整判定规程/增改删流程/校验防线见
//   dshinhm docs/设置项搜索规范.md（本项目无地址/图片编辑类目，规则裁剪）。
// 匹配规则：关键字精确搜索（子串包含，不模糊），大小写不敏感（英文词命中）。
// 无高亮（dshinhm 决明定稿随迁）：结果项标题/路径纯文本展示，不做关键词高亮切分。

import {
  ROUTE_ABOUT_PAGE,
  ROUTE_AI_ASSIST_PAGE,
  ROUTE_COST_STATS_PAGE,
  ROUTE_FEEDBACK_PAGE,
  ROUTE_OPEN_SOURCE_PAGE,
  ROUTE_PRIVACY_POLICY_PAGE,
  ROUTE_HELP_CENTER_PAGE,
  ROUTE_HELP_TOPIC_PAGE,
  ROUTE_APPEARANCE_PAGE,
  ROUTE_INFO_PAGE,
  ROUTE_LOG_PAGE,
  ROUTE_REQ_LOG_PAGE,
  ROUTE_PERMISSION_PAGE,
  ROUTE_PREFERENCES_PAGE,
  ROUTE_PROMPT_LIBRARY_PAGE,
  ROUTE_PROVIDER_PAGE,
  ROUTE_DATA_SYNC_PAGE,
  ROUTE_FUNCTIONAL_MODEL_PAGE,
  ROUTE_SYSTEM_PROMPT_PAGE,
  ROUTE_USAGE_STATS_PAGE,
  ROUTE_MEMORY_PAGE,
  ROUTE_PROACTIVE_PAGE,
  ROUTE_STORAGE_PAGE,
  ROUTE_SEARCH_ENGINE_PAGE,
  ROUTE_TOOLS_PAGE,
  ROUTE_SKILL_LIBRARY_PAGE,
  ROUTE_KNOWLEDGE_LIBRARY_PAGE
} from './RouteNames';
import { HELP_GROUPS } from './HelpContent';

// ── 标题常量（单一来源：页面 UI 与本注册表共用，改名只改这里）──
// 设置页签行卡（服务商管理行卡标题 + PageMap 标题栏共用）
export const SETTING_TITLE_PROVIDER: string = '服务商管理';
// 提示词库管理行卡标题（2026-08-30 提示词注入；设置页第 2 卡 + 管理页标题共用；
// 2026-08-30 领导指令改五字「会话提示词」）
export const SETTING_TITLE_PROMPT: string = '会话提示词';
// 系统提示词行卡标题（2026-08-30 系统提示词卡——放会话提示词上方；2026-08-31 独立页化：
// 独立页管理 = SystemPromptPage（库页不显示、内置默认可更改可重置）；注入语义（★2026-09-04
// 归属与注入解耦）= 会话提示词 > 助手提示词 > 系统提示词三级回退——系统提示词行 = 注入
// 基座兜底，存储 = prompt_templates.isGlobal 行参见 PromptTemplateDb 头注释）
export const SETTING_TITLE_SYSTEM_PROMPT: string = '系统提示词';
// 偏好设置行卡标题（2026-09-01 偏好设置页新建：设置页「会话提示词」卡后第 4 卡 + 页标题）
export const SETTING_TITLE_PREFERENCES: string = '偏好设置';
export const SETTING_TITLE_DATA_SYNC: string = '数据与同步';
// 功能模型行卡标题（2026-09-05 功能模型页新建：设置页偏好设置后新卡 + 页标题共用——
// 功能级模型配置集中页；「默认模型」= 发送链四级兜底第③级来源）
export const SETTING_TITLE_FUNCTIONAL_MODEL: string = '功能模型';
// 「功能模型」页行卡标题（首项：默认对话——消费方 resolveActiveConnection 兜底链③级；
// 2026-09-05 决明指令由「默认模型」改名，2026-09-06 再去「模型」二字定名「默认对话」，
// keywords 保留两轮旧名兼容搜索）
export const SETTING_TITLE_DEFAULT_MODEL: string = '默认对话';
// 「功能模型」页第二卡标题（2026-09-05 AI 会话标题生成：标题两键显式开关——未配置 =
// 功能未启用静默不生成；生成链在 common/TitleGen.ets；2026-09-06 去「模型」二字定名
// 「标题生成」，keywords 保留旧名兼容搜索）
export const SETTING_TITLE_TITLE_MODEL: string = '标题生成';
// 「功能模型」页第三卡标题（★ 2026-09-08 先行笔：记忆提取模型——记忆整理独立可配，
// 未配置则不整理（决明指令取消回退标题模型）；生成链在 common/MemoryGen.ets；
// ★ 2026-09-16 决明指令卡名去「模型」二字定名「记忆提取」——与 2026-09-06 前两卡同款
// 去法，keywords 保留旧名兼容搜索）
export const SETTING_TITLE_MEMORY_MODEL: string = '记忆提取';
// 「功能模型」页第四卡标题（★ 2026-09-11「记忆优化模型」二期：对库内已有记忆做去重与
// 改写，未配置则不优化（不回退提取模型）；执行链在 common/MemoryOpt.ets。
// ★ 同笔补记：本常量与上一条「记忆提取」同笔补入搜索注册表——原「同页卡片不进注册表」
// 的说法与同页另两卡（默认对话/标题生成）早已在表内的事实不一致，且搜索「记忆提取模型」
// 此前无任何结果（帮助条目的检索只认标题与少量 keywords，正文里的同款字样不参与匹配）＝
// 用户可见缺口，故按同页同族一并登记。★ 2026-09-16 决明指令卡名去「模型」二字定名
// 「记忆优化」，keywords 保留旧名兼容搜索）
export const SETTING_TITLE_MEMORY_OPT_MODEL: string = '记忆优化';
// 「功能模型」页第五卡标题（2026-09-15 附件 OCR 二期：附件文字识别——总开关默认开 +
// ★ 2026-09-16 内置引擎落地后：卡内三分段胶囊「系统识别 / 内置识别 / 视觉模型」，引擎三态
// 互斥单值落键；链路在 common/OcrEngine.ets + providers/OcrPaddle.ets〔内置〕+
// providers/OcrVisionApi.ets〔视觉〕）
export const SETTING_TITLE_OCR: string = '文字识别';
// 「功能模型」页第六卡标题（2026-09-19 推荐问题功能：AI 回复后的追问推荐生成开关与模型
// 配置——总开关默认关（BYOK 显式授权），未选模型 = 零请求；生成链在 common/SuggestGen.ets。
// ★ 同日晚笔：开场推荐链已退役，本条目只覆盖消息后追问推荐）
export const SETTING_TITLE_SUGGEST: string = '推荐问题';
// 「功能模型」页第七卡标题（2026-09-23 上下文压缩：会话上下文的手动压缩——用量面板发起，
// 模型未配置回退当前会话模型；生成链在 common/CompressGen.ets）
export const SETTING_TITLE_COMPRESS: string = '上下文压缩';
// 「偏好设置」页行卡标题（首项：默认展开思考——消费方 ChatThinkingBlock 初始态）
export const SETTING_TITLE_THINK_EXPAND: string = '默认展开思考';
// 「偏好设置」页行卡标题（第 2 项：流式引擎——2026-09-02 Cube 移植试验副本双引擎开关，
// 消费方 ChatSendCtrl 分流点；2026-09-07 语义定稿「关闭 = 自研引擎，开启 = 试验引擎」，
// UI 文案去 Cube 字样，注释保留来源事实）
export const SETTING_TITLE_STREAM_ENGINE: string = '流式引擎（试验）';
// 「偏好设置」页行卡标题（第 3 项：流式输出自动跟随——2026-09-02 新增，消费方
// ChatFollowController.maybeFollow 单点拦截）
export const SETTING_TITLE_STREAM_FOLLOW: string = '流式输出自动跟随';
// 「偏好设置」页行卡标题（第 4 项：键盘发送——2026-09-03 新增，消费方 ChatInputBar
// enterKeyType 订阅；默认关 = 换行键）
export const SETTING_TITLE_KEYBOARD_SEND: string = '键盘发送';
// 「偏好设置」页行卡标题（第 5 项：会话页屏幕常亮——2026-09-04 新增，消费方 ChatPage
// aboutToAppear/aboutToDisappear 窗口常亮开关；默认关 = 系统息屏）
export const SETTING_TITLE_KEEP_SCREEN_ON: string = '屏幕常亮';
// 「偏好设置」页行卡标题（第 6 项：会话时间显示——2026-09-04 新增，消费方 ChatSessionList
// SessionCardItem 卡片时间显隐；默认开 = 现状）
export const SETTING_TITLE_SESSION_TIME: string = '会话时间显示';
// 「偏好设置」页行卡标题（第 11 项：会话图标显示——2026-09-19 新增，消费方 ChatSessionList
// SessionCardItem 卡片前缀消息图标显隐；默认开 = 现状）
export const SETTING_TITLE_SESSION_ICON: string = '会话图标显示';
// 「偏好设置」页行卡标题（第 12 项：网络自动重试——2026-09-22 新增，消费方 = ChatAutoRetryCtrl
// 判据经 ChatAutoRetryHost 回接 ChatSendCtrl 现读，轮首读一次轮内锁定；默认开 = 有意选择
// 非疏忽〔只在零产出的网络失败触发，风险面极低〕，理由见 AppPreferences 键注释）
export const SETTING_TITLE_AUTO_RETRY: string = '自动重试';
// 「偏好设置」页聊天交互板块内「粘贴长文本转文件」卡标题（2026-09-23 新增，消费方 ChatInputBar
// 判定前订阅本开关与阈值；默认开 = 粘贴文本达到阈值即转成 .txt 附件）。★ 决明同日拍板「开关与
// 滑块合一卡」——本卡含开关与阈值滑轨两个控件（原计划为组卡第 6 行，已废）。帮助条目同名同裁
//〔HELP_SKIP_TITLES〕——该卡已可搜直达，避免同名冗余
export const SETTING_TITLE_PASTE_AS_FILE: string = '粘贴长文本转文件';
// 「偏好设置」页粘贴设置卡内的阈值行标题（2026-09-23 新增；卡内参数名行与编辑弹窗标题共用）
//——按主动消息页三张滑轨卡口径不另立搜索注册项（页面级条目已在，内卡不逐张注册）
export const SETTING_TITLE_PASTE_AS_FILE_THRESHOLD: string = '粘贴长度阈值';
// 「偏好设置」页行卡标题（第 8 项：生物识别方式——2026-09-05 新增，消费方 BiometricGate
// 认证发起单类型；默认开 = 人脸）
export const SETTING_TITLE_BIOMETRIC_FACE: string = '生物识别方式';
// 「偏好设置」页行卡标题（第 9 项：页签切换动画——2026-09-08 新增，消费方 HomeNavigation
// 底部页签切换动画时长；默认开 = 横向滑切，关 = 点按直达）
export const SETTING_TITLE_TAB_SWITCH_ANIM: string = '页签切换动画';
// 「偏好设置」页行卡标题（第 10 项：启动进入页面——2026-09-08 新增，消费方 HomeNavigation
// 冷启动首帧 aboutToAppear 现读；默认关 = 进入对话一级页会话列表，与现状一致）
export const SETTING_TITLE_LAUNCH_ENTRY: string = '启动进入页面';
// 二级页标题
export const SETTING_TITLE_APPEARANCE: string = '外观显示';
export const SETTING_TITLE_MORE_INFO: string = '更多信息';
// 「外观显示」页光感面板（AppearancePage LevelSlider 标题；★ 2026-09-12 分项退役——
// 原「悬浮底栏」「其他控件」两常量（SETTING_TITLE_TAB_BAR / SETTING_TITLE_OTHER_CONTROLS）
// 与对应搜索条目删除，两处档位恒跟随「沉浸光感档位」总卡，见 ImmersiveLevel.ets 头注释）
export const SETTING_TITLE_TAB_LIGHT: string = '光感';
export const SETTING_TITLE_IMMERSIVE_LEVEL: string = '沉浸光感档位';
// 「外观显示」页光感面板第四项（2026-09-03 内容区回退开关卡，2026-09-07 更名「光感新规范」
// ——开关语义不变，开启 = 内容区组件按华为新光感规范走官方标准形态）
export const SETTING_TITLE_CONTENT_FALLBACK: string = '光感新规范';
// 「外观显示」页背景面板（M3 起迁入；分段标签 + 三卡片标题）
export const SETTING_TITLE_TAB_BACKGROUND: string = '背景';
export const SETTING_TITLE_PICK_IMAGE: string = '选择图片';
export const SETTING_TITLE_EDIT_IMAGE: string = '编辑图片';
export const SETTING_TITLE_RESTORE_DEFAULT: string = '恢复默认';
// 「外观显示」页背景面板第四卡（2026-09-05 新增开关卡：恢复默认卡上方——自定义背景只在
// 会话页显示，其余页面用默认底色；消费方 PageBackground 组合判定）
export const SETTING_TITLE_BG_SESSION_ONLY: string = '背景仅用于会话页';
// 关于页域（M3 起迁入；更多信息的子页；★ 获取安装包标题常量 2026-09-08 随功能移除删除——
// 查阅历史见 git 历史 / 变更记录九十六~九十八节）
export const SETTING_TITLE_ABOUT: string = '关于';
export const SETTING_TITLE_PERMISSION: string = '权限信息';
export const SETTING_TITLE_PRIVACY_POLICY: string = '隐私政策';
export const SETTING_TITLE_VERSION_INFO: string = '版本信息';
export const SETTING_TITLE_AI_ASSIST: string = 'AI 辅助开发声明';
export const SETTING_TITLE_OPEN_SOURCE: string = '开源项目鸣谢';
// 反馈与建议（2026-09-07 MeoW 反馈通道：更多信息页行卡标题 + 反馈页标题共用；
// 同日入口自关于页卡片移入更多信息页，插帮助中心行卡下方）
export const SETTING_TITLE_FEEDBACK: string = '反馈与建议';
// 运行日志页（M3 起迁入；更多信息的子页）
export const SETTING_TITLE_RUN_LOG: string = '运行日志';
// 请求日志页（2026-09-23 请求日志笔；更多信息的子页——HTTP 请求现场记录，排障用）
export const SETTING_TITLE_REQ_LOG: string = '请求日志';
// 帮助中心页（2026-09-05 新增：更多信息页首张行卡 + 页标题共用——分板块卡片说明功能与用法）
export const SETTING_TITLE_HELP_CENTER: string = '帮助中心';
// 「用量统计」行卡标题（2026-09-06 token 用量统计：设置页偏好设置卡后新卡 + 页标题共用
// ——概览六数字/按模型/近30天逐日纯列表页）
export const SETTING_TITLE_USAGE_STATS: string = '用量统计';
// 「费用估计」行卡标题（2026-09-10 费用估计：设置页「用量统计+费用估计」组卡第二行 +
// 页标题共用——模型价格 × token 用量折算的估算页〔总览四格/模型排行/用途分布〕；
// 帮助条目同名同裁〔HELP_SKIP_TITLES〕——页面本身可搜直达，避免同名冗余）
export const SETTING_TITLE_COST_STATS: string = '费用估计';
// 「记忆」行卡标题（2026-09-08 记忆域：设置页提示词卡后新卡〔同日决明卡序调整〕+ 页标题
// 共用——跨会话长期记忆管理页：查看/编辑/删除/手动添加/立即整理 + 总开关与自动整理两开关）
export const SETTING_TITLE_MEMORY: string = '记忆';
// 「主动消息」行卡标题（2026-09-12 主动消息第一笔「触发链底层」：设置页记忆卡后单行卡
// 〔同日决明指令与记忆合卡——现为「记忆 + 主动消息」双行组卡第二行〕+ 页标题共用——
// 开关卡 + 两滑轨卡 + 说明小字；帮助条目同名同裁〔HELP_SKIP_TITLES
// 〕——页面本身可搜直达，避免同名冗余）
export const SETTING_TITLE_PROACTIVE: string = '主动消息';
// 「主动消息」页内四卡标题（2026-09-12 决明指令两档弹窗改卡内滑轨后：总开关单开关卡 +
// 触发间隔/每日最多两张 SliderValueCard 滑轨卡；2026-09-13 静默期滑轨笔补第三张）
export const SETTING_TITLE_PROACTIVE_ENABLED: string = '启用主动消息';
export const SETTING_TITLE_PROACTIVE_INTERVAL: string = '触发间隔';
export const SETTING_TITLE_PROACTIVE_DAILY_LIMIT: string = '每日最多';
export const SETTING_TITLE_PROACTIVE_QUIET_MAX: string = '静默期上限';
// 「记忆」页开关组卡两行标题（2026-09-10 控制台助手设置读写扩面：两开关进 set/get_app_preference
// 白名单——白名单条目 setting 字段必须 = 界面真实标题，本常量即该界面的单一来源，MemoryPage
// 行 label 与白名单同引；行序 = 总开关在前）
export const SETTING_TITLE_MEMORY_ENABLED: string = '记忆功能';
export const SETTING_TITLE_MEMORY_AUTO: string = '退出会话后自动整理';
// 「记忆」页读取方式分段卡标题（2026-09-13 记忆按需读取：自动注入 / 按需读取两段——
// 卡内标题行与搜索注册表共用，改名只改这里）
export const SETTING_TITLE_MEMORY_READ_MODE: string = '读取方式';
// 「存储管理」行卡标题（2026-09-09 附件全量落盘第二轮：设置页数据与同步卡内第二行——同日
// 决明指令两卡合并为一张双行组卡；页标题共用——六分类占用展示与可安全清理页；官方《存储空间使用与文件生命周期管理》
// 【应当】条「提供应用内清理入口」的落点）
export const SETTING_TITLE_STORAGE: string = '存储管理';
// 「联网搜索」行卡标题（2026-09-10 多引擎一期：设置页服务商管理卡内第三行——引擎选择/
// 启用/密钥与 baseUrl 配置/测试搜索页；同日 UI 重构对齐服务商管理页并迁卡——记忆卡下与
// 工具调用组成两行主卡，本页为引擎列表〔分段已启用/已停用 + 引擎卡进详情页配置〕；
// 页标题共用；帮助条目同名同裁〔HELP_SKIP_TITLES〕——页面本身可搜直达，避免同名冗余）
export const SETTING_TITLE_SEARCH_ENGINE: string = '联网搜索';
// 「联网搜索」页首卡标题（★ 2026-09-10 控制台助手设置读写扩面：该总开关进白名单——原界面
// 标题只写「总开关」，在工具 desc 的白名单清单里与「记忆功能」等开关并列时指代不明（模型
// 映射与回执转述都会歧义），故补全为「联网搜索总开关」；被拒 toast 早已用此全称
// 〔原 ChatParamChipBar，2026-09-19 联网开关迁标题栏更多菜单后落 ChatPage：「联网搜索总开关
// 已关闭，可在设置的联网搜索页打开」〕，本次让界面与它对齐。
// 搜索注册表不新增条目——引擎/密钥等同页配置项按既有口径只由页级条目承载）
export const SETTING_TITLE_SEARCH_SERVICE: string = '联网搜索总开关';
// 「工具调用」行卡标题（2026-09-10 决明指令：设置页记忆卡下与联网搜索组成两行主卡——
// 二级页现承载「网页高危操作确认」全局工具卡〔2026-09-18 七百五十五节；建卡时曾为空占位
// 〔ToolsSettingsPage〕〕；帮助中心既有两条同名
// 「工具调用」条目均为助手编辑页语义，不入 HELP_SKIP（页面不同），注册表同题经消歧后缀
// 区分）
export const SETTING_TITLE_TOOLS: string = '工具调用';
// 「网页高危操作确认」卡标题（2026-09-18 浏览高危确认降压阀笔：工具调用页首张全局工具卡
// ——卡内标题行与搜索注册表共用，改名只改这里；分段标签「每次确认/自动通过」单源在
// ToolsSettingsPage.approveItems）
export const SETTING_TITLE_BROWSE_CONFIRM: string = '网页高危操作确认';
// 「HTTP 写操作确认」卡标题（2026-09-20 HTTP 请求独立域笔：工具调用页第二张全局工具卡
// ——http_request 写方法的确认档控制面，卡内标题行与搜索注册表共用，改名只改这里；
// 分段标签「每次确认/自动通过」单源在 ToolsSettingsPage.httpApproveItems）
export const SETTING_TITLE_HTTP_CONFIRM: string = 'HTTP 写操作确认';
// 「技能库」行卡标题（2026-09-13 技能层笔 1：设置页系统提示词/提示词卡下新卡 + 页标题 +
// 助手技能页「管理技能库」入口行共用——技能清单管理页：新建/编辑/删除技能，技能 = 助手的
// 「怎么做某件事」说明书，按触发描述被模型自主加载；帮助条目同名语义不同〔帮助条目讲概念
// 与用法，页面是清单管理〕，不入 HELP_SKIP）
export const SETTING_TITLE_SKILL_LIBRARY: string = '技能库';
// 「知识库」行卡标题（2026-09-21 世界书知识库首版：设置页「指令面」组卡第四行 + 页标题 +
// 助手知识库页入口共用——知识库 = 用户手写的词条本，助手觉得需要某领域知识时经
// search_knowledge 自己去查；★ 用户可见名一律「知识库」，世界书/World Book/Lorebook 只
// 出现在文档与代码注释里，不上屏；帮助条目同名语义不同〔帮助条目讲概念与用法，页面是
// 清单管理〕——本条与本项目「技能库」那条处置刻意不同，见 HELP_SKIP_TITLES 内该条注释）
export const SETTING_TITLE_KNOWLEDGE_LIBRARY: string = '知识库';

// 面包屑根（一级页名 = 设置页签标题）
const PATH_ROOT: string = '设置';

// ── 帮助条目搜索注册（2026-09-05 接入：程序化生成，单一数据源 common/HelpContent.ets，
// 增删帮助条目只动 HelpContent，注册表自动同步零双源）──
// 帮助条目面包屑前缀 = 帮助中心入口条目 path 延伸
const HELP_PATH_ROOT: string = PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_HELP_CENTER;
// 裁剪名单（2026-09-05 决明拍板）：与既有注册表条目完全重名的 7 条不生成——对应功能页
// 本身可被搜索直达，重复注册会造成 title 冲突与结果冗余。名单用 SETTING_TITLE_* 常量
// 比对（改名自动跟随）；名单与消歧规则变更须同步 scripts/setting-search-check.mjs 第 8 查。
// 2026-09-06 +用量统计（帮助条目 = 该页说明，页面本身静态注册直达——同语义冗余照裁）；
// 2026-09-07 +权限信息/隐私政策（入口自关于页迁至更多信息页行卡，帮助条目同步新增——
// 页面本身仍静态注册直达，照裁）；2026-09-08 +记忆（记忆域：页面静态注册直达，同裁）；
// 2026-09-09 +存储管理（附件落盘第二轮：设置页数据与同步卡内第二行，帮助条目同步新增
// ——页面静态注册直达，同裁）；2026-09-10 +联网搜索（多引擎一期：设置页同名行卡，页面
// 静态注册直达，同裁）；
// 2026-09-10 +工具调用（设置页新增同名行卡〔先空占位〕——★ 与前十三条不同：帮助中心两条
// 「工具调用」条目讲的是助手编辑页的工具区块，页面不同语义不同，照裁是守「同题不冗余」
// 规则的代价，搜索工具调用先达设置页占位页、其文案再指路助手编辑页；条目本身在帮助
// 中心仍可浏览。注意本条对应两条帮助条目〔不同组同题〕，裁剪按题名生效两条同裁）；
// 2026-09-10 +费用估计（费用估计笔：设置页「用量统计+费用估计」组卡第二行，页面静态
// 注册直达，帮助条目同语义照裁）；
// 2026-09-12 +自检（应用内一键自检笔：设置页「自检」单独卡——同日决明指令自更多信息页
// 应用信息板块迁出，页面静态注册直达，帮助条目同语义照裁）；★ 2026-09-20 应用内自检
// 全量退役——本名单条目与帮助「自检」条目、注册表条目、行卡与页面一并删除（名字与页面
// 都不在了，留档只为沿革可检索）；
// 2026-09-12 +主动消息（主动消息第一笔：设置页「主动消息」单行卡〔记忆卡后，同日与记忆
// 合卡为双行组卡第二行〕，页面静态注册直达，帮助条目同语义照裁）
const HELP_SKIP_TITLES: string[] = [
  SETTING_TITLE_SYSTEM_PROMPT,
  SETTING_TITLE_DEFAULT_MODEL,
  SETTING_TITLE_ABOUT,
  SETTING_TITLE_PREFERENCES,
  SETTING_TITLE_RUN_LOG,
  // 请求日志（2026-09-23 请求日志笔：页面静态注册直达，帮助条目同语义照裁——照运行日志口径）
  SETTING_TITLE_REQ_LOG,
  SETTING_TITLE_USAGE_STATS,
  SETTING_TITLE_COST_STATS,
  SETTING_TITLE_FEEDBACK,
  SETTING_TITLE_PERMISSION,
  SETTING_TITLE_PRIVACY_POLICY,
  SETTING_TITLE_MEMORY,
  SETTING_TITLE_STORAGE,
  SETTING_TITLE_SEARCH_ENGINE,
  SETTING_TITLE_TOOLS,
  // 主动消息（2026-09-12：页面静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_PROACTIVE,
  // 文字识别（2026-09-15 附件 OCR 二期：功能模型页「文字识别」卡静态注册直达，
  // 帮助条目同语义照裁）
  SETTING_TITLE_OCR,
  // 网页高危操作确认（2026-09-18 浏览高危确认降压阀笔：工具调用页内卡静态注册直达，
  // 帮助条目同语义照裁）
  SETTING_TITLE_BROWSE_CONFIRM,
  // HTTP 写操作确认（2026-09-20 HTTP 请求独立域笔：工具调用页内第二张卡静态注册直达，
  // 帮助条目同语义照裁）
  SETTING_TITLE_HTTP_CONFIRM,
  // 推荐问题（2026-09-19 推荐问题功能笔：功能模型页「推荐问题」卡静态注册直达，
  // 帮助条目同语义照裁）
  SETTING_TITLE_SUGGEST,
  // 上下文压缩（2026-09-23 上下文压缩笔：功能模型页「上下文压缩」卡静态注册直达，
  // 帮助条目同语义照裁）
  SETTING_TITLE_COMPRESS,
  // 知识库（2026-09-21 世界书知识库首版：设置页「指令面」组卡第四行，页面静态注册直达；
  // ★ 本条的处置与「技能库」那条刻意不同——技能域把帮助条目改名为「技能」避开了重名，
  // 而「知识库」是用户的通用叫法（帮助里另起名字反而难找），故帮助条目照用「知识库」、
  // 由本名单裁掉搜索注册（帮助中心内仍可浏览；搜索「知识库」直达库页 = 用户最可能的
  // 意图）。判据 = setting-search-check 断言 A：帮助条目与静态注册表的重名集合须恰在本
  // 名单内）
  SETTING_TITLE_KNOWLEDGE_LIBRARY,
  // 粘贴长文本转文件（2026-09-23 粘贴长文本转文件笔：偏好设置页聊天交互组第 6 行开关，
  // 页面静态注册直达，帮助条目同语义照裁——裁掉的只是搜索注册，帮助中心内条目照常显示）
  SETTING_TITLE_PASTE_AS_FILE
];

// 帮助条目 → 搜索注册条目（点击直达帮助条目详情页：pageName = 帮助详情路由，
// param = 条目 id「分组::标题」，HelpTopicPage 经 findHelpTopic 还原）。
// title 全表唯一守卫：与静态注册表查重，同名片目追加「 · 分组名」后缀消歧
//（通用规则，当前无命中——原先命中的两处「工具调用」自 2026-09-10 起整题进裁剪名单，
// 机制留作后续新增同题条目时的兜底；主词仍在前部，子串搜索不受影响）。
// keywords 默认空（title 子串已覆盖主词），仅个别条目补同义词/缩写。
export function buildHelpSearchItems(): SettingSearchItem[] {
  const items: SettingSearchItem[] = [];
  const used: Set<string> = new Set();
  // 静态注册表先占位（BASE_SEARCH_ITEMS 在本函数首次被调用时已初始化完成——调用点在
  // SETTING_SEARCH_ITEMS 定义处，无 TDZ）
  for (const item of BASE_SEARCH_ITEMS) {
    used.add(item.title);
  }
  for (const group of HELP_GROUPS) {
    for (const topic of group.items) {
      if (HELP_SKIP_TITLES.includes(topic.title)) {
        continue;
      }
      let title: string = topic.title;
      if (used.has(title)) {
        title = topic.title + ' · ' + group.title;
      }
      used.add(title);
      let keywords: string[] = [];
      if (topic.title === '什么是 API 与 API Key') {
        keywords = ['密钥', 'key', 'token', '凭证'];
      } else if (topic.title === '会话提示词库') {
        keywords = ['模板'];
      } else if (topic.title === '批量删除') {
        // UI 菜单项实际叫「多选」——搜菜单名也能找到本条目（2026-09-05 二轮精修发现）
        keywords = ['多选'];
      }
      items.push({
        title: title,
        path: HELP_PATH_ROOT + ' > ' + group.title,
        keywords: keywords,
        pageName: ROUTE_HELP_TOPIC_PAGE,
        tab: -1,
        param: group.title + '::' + topic.title
      });
    }
  }
  return items;
}

// ── 注册表条目 ──
export interface SettingSearchItem {
  // 显示标题（= 页面 UI 文字常量，搜索结果展示标题）
  title: string;
  // 面包屑路径（结果项副标题，如「设置 > 外观显示 > 光感」）
  path: string;
  // 额外匹配词（同义词/英文/口语词；title 本身的文字无需重复）
  keywords: string[];
  // 目标页路由名（HomeNavigation PageMap 分支名；★ 必须引用 common/RouteNames.ets 的
  // ROUTE_* 常量，禁止裸字符串——与 PageMap 分支天然同源，拼错编译期即报）
  pageName: string;
  // 目标页内分段标签（仅 AppearancePage：0 光感；「背景」面板迁入时启用 1；其余页 -1）
  tab: number;
  // 跳转 params（可选；未定义 = 现行为不变（tab >= 0 时传 tab，否则 null），
  // SearchPage.openItem 读取——2026-08-31 系统提示词条目独立页化后无参条目，字段仅模板页
  // 类条目预留）
  param?: Object | null;
}

// 可搜索设置项注册表静态部分（顺序 = 结果列表顺序，按页面层级排列；条目随页面迁移逐任务
// 增补）。背景面板条目 M3 起登记（tab=1 直达「背景」分段，dshinhm 口径随迁）。
// ★ 总表 SETTING_SEARCH_ITEMS 在下方 = 本静态表 + 帮助条目程序化生成（buildHelpSearchItems）
const BASE_SEARCH_ITEMS: SettingSearchItem[] = [
  // ── 一级入口 ──
  { title: SETTING_TITLE_PROVIDER, path: PATH_ROOT, keywords: ['服务商', '连接', '配置', 'API', '接口', '模型', 'baseUrl', 'apiKey', 'DeepSeek', '供应商'], pageName: ROUTE_PROVIDER_PAGE, tab: -1 },
  // 功能模型（2026-09-05 登记原放数据与同步条目后，同日决明调序与页面卡片同步移到
  // 服务商管理下——功能级模型配置集中页）
  { title: SETTING_TITLE_FUNCTIONAL_MODEL, path: PATH_ROOT, keywords: ['功能模型', '默认模型', '兜底', '缺省', '模型', 'default'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 系统提示词（2026-08-31 独立页化：不再经编辑页全局分支——pageName 改独立路由，无参
  // 直达 SystemPromptPage；keywords 保留「全局默认」兼容旧叫法记忆）
  { title: SETTING_TITLE_SYSTEM_PROMPT, path: PATH_ROOT, keywords: ['系统提示词', '人设', '角色', '指令', '注入', 'system', 'Prompt', '全局默认'], pageName: ROUTE_SYSTEM_PROMPT_PAGE, tab: -1 },
  { title: SETTING_TITLE_PROMPT, path: PATH_ROOT, keywords: ['提示词', '人设', '角色', '指令', '全局默认', 'system', 'Prompt', '注入'], pageName: ROUTE_PROMPT_LIBRARY_PAGE, tab: -1 },
  // 技能库（2026-09-13 技能层登记：设置页「系统提示词+提示词」卡下单独卡——技能清单管理页
  //〔对齐通用组件「技能」的 skill 概念〕；keywords 带「技能」「说明书」「流程」「skill」
  // 三个口语入口词，条目顺序与 SettingsPage.settingGroups 同步）
  { title: SETTING_TITLE_SKILL_LIBRARY, path: PATH_ROOT, keywords: ['技能', '说明书', '流程', 'skill', '加载', 'use_skill'], pageName: ROUTE_SKILL_LIBRARY_PAGE, tab: -1 },
  // 知识库（2026-09-21 世界书知识库首版登记：设置页「指令面」组卡第四行——词条本管理页；
  // keywords 带「知识库」「词条」「术语」「设定」「world book」「lorebook」六个入口词
  //〔后两个是竞品通用叫法，用户可能按它找〕，条目顺序与 SettingsPage.settingGroups 同步）
  { title: SETTING_TITLE_KNOWLEDGE_LIBRARY, path: PATH_ROOT, keywords: ['知识库', '词条', '术语', '设定', 'world book', 'lorebook'], pageName: ROUTE_KNOWLEDGE_LIBRARY_PAGE, tab: -1 },
  // 记忆（2026-09-08 记忆域登记；同日决明卡序调整 = 移至提示词条目后——卡序与 SettingsPage 同步；2026-09-20 助手级记忆补三搜索词；★ 2026-09-22 记忆导入笔补三搜索词——导入入口在库管理页「更多」菜单〔三级页，不进本表〕，搜索该功能时命中记忆条目再经「更多」菜单找到，是唯一可达路径）
  { title: SETTING_TITLE_MEMORY, path: PATH_ROOT, keywords: ['记忆', '长期记忆', '自动整理', '跨会话', '沉淀', '注入', '助手记忆', '全局记忆', '记忆库', '导入', '迁移', '其他平台'], pageName: ROUTE_MEMORY_PAGE, tab: -1 },
  // 主动消息（2026-09-12 主动消息第一笔登记：设置页「主动消息」单行卡〔记忆卡后〕，同日
  // 与记忆合卡为双行组卡第二行——卡序与 SettingsPage.settingGroups 同步）
  { title: SETTING_TITLE_PROACTIVE, path: PATH_ROOT, keywords: ['主动消息', '主动发消息', '主动', '问候', '打招呼', '静默期', 'proactive'], pageName: ROUTE_PROACTIVE_PAGE, tab: -1 },
  // 联网搜索（2026-09-10 多引擎一期登记：设置页「联网搜索+工具调用」两行主卡首行〔同日
  // UI 重构自卡1 第三行迁入记忆卡下〕——条目顺序与 SettingsPage.settingGroups 同步）
  { title: SETTING_TITLE_SEARCH_ENGINE, path: PATH_ROOT, keywords: ['联网', '搜索', '引擎', '博查', '秘塔', 'serper', 'bing', 'web', '多引擎'], pageName: ROUTE_SEARCH_ENGINE_PAGE, tab: -1 },
  // 工具调用（2026-09-10 决明指令登记：两行主卡第二行——二级页现承载「网页高危操作确认」
  // 全局工具卡〔七百五十五节；建卡时曾为空占位〕；帮助中心两条同名
  // 「工具调用」条目讲的是助手编辑页的工具区块〔页面不同语义不同〕，按「帮助条目与静态
  // 注册表同题不冗余」规则整题裁掉〔两条跨组同裁，见 HELP_SKIP_TITLES〕——搜索该题命中
  // 本条目，条目文案再指路助手编辑页，帮助条目本身在帮助中心仍可浏览）
  { title: SETTING_TITLE_TOOLS, path: PATH_ROOT, keywords: ['工具', '调用', '内置工具', 'tool'], pageName: ROUTE_TOOLS_PAGE, tab: -1 },
  // 网页高危操作确认（2026-09-18 浏览高危确认降压阀笔登记：工具调用页内卡——二级条目
  // 面包屑挂工具调用页下，keywords 带「自动通过」「确认」等口语入口词；不进 HELP_SKIP，
  // 帮助条目同名同语义由 buildHelpSearchItems 消歧兜底〔当前同题唯一无冲突〕）
  { title: SETTING_TITLE_BROWSE_CONFIRM, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['自动通过', '每次确认', '高危', '确认', '同意'], pageName: ROUTE_TOOLS_PAGE, tab: -1 },
  // HTTP 写操作确认（2026-09-20 HTTP 请求独立域笔登记：工具调用页内第二张卡——二级条目
  // 面包屑挂工具调用页下，keywords 带「接口」「HTTP」「自动通过」等口语入口词；与上一条
  // 同形制，同题不冲突）
  { title: SETTING_TITLE_HTTP_CONFIRM, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['HTTP', '接口', '网络请求', '自动通过', '每次确认', '确认'], pageName: ROUTE_TOOLS_PAGE, tab: -1 },
  { title: SETTING_TITLE_PREFERENCES, path: PATH_ROOT, keywords: ['偏好', '设置', '思考', '展开', '开关'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  { title: SETTING_TITLE_APPEARANCE, path: PATH_ROOT, keywords: ['外观', '显示', '光感', '材质', '沉浸', '壁纸', '背景'], pageName: ROUTE_APPEARANCE_PAGE, tab: 0 },
  // 用量统计（2026-09-06 token 用量统计登记；2026-09-08 卡序调整后居外观条目下、数据与同步前）
  { title: SETTING_TITLE_USAGE_STATS, path: PATH_ROOT, keywords: ['用量', '统计', 'token', '消耗', 'tokens', '速度', 'tok', '生成速度'], pageName: ROUTE_USAGE_STATS_PAGE, tab: -1 },
  // 费用估计（2026-09-10 费用估计登记：组卡第二行，条目顺序与 SettingsPage.settingGroups
  // 同步；价格配置入口在模型编辑页，关键词带「价格」直达本页后经空态引导指路）
  { title: SETTING_TITLE_COST_STATS, path: PATH_ROOT, keywords: ['费用', '成本', '价格', '花费', '多少钱', '消费', '金额', '花销', 'cost'], pageName: ROUTE_COST_STATS_PAGE, tab: -1 },
  // 数据与同步（2026-09-05 决明调序与页面卡片同步移到更多信息前）
  { title: SETTING_TITLE_DATA_SYNC, path: PATH_ROOT, keywords: ['数据', '同步', '备份', '导出', '导入', 'WebDAV', '恢复'], pageName: ROUTE_DATA_SYNC_PAGE, tab: -1 },
  // 存储管理（2026-09-09 附件全量落盘第二轮登记：数据与同步卡内第二行——六分类占用与
  // 清理；卡序与 SettingsPage.settingGroups 同步）。★ 2026-09-15 附件管理列表笔：keywords
  // 补「会话附件」——该页是存储管理页内的卡3，非独立设置项（不新增注册条目），但匹配逻辑
  // 是「关键词 includes 查询词」，不补词则按卡面名搜索必然落空。★ 2026-09-21 存储清理口径
  // 对齐笔：补「浏览器数据」「运行日志」两组词（页内卡4 与卡2 第三行，同上口径）
  { title: SETTING_TITLE_STORAGE, path: PATH_ROOT, keywords: ['存储', '空间', '清理', '缓存', '占用', '容量', '附件', '会话附件', '垃圾', '浏览器', '浏览器数据', '网页数据', '运行日志', '日志', 'cookie', 'storage'], pageName: ROUTE_STORAGE_PAGE, tab: -1 },
  { title: SETTING_TITLE_MORE_INFO, path: PATH_ROOT, keywords: ['信息', '关于', '版本'], pageName: ROUTE_INFO_PAGE, tab: -1 },
  // ── 外观显示 · 光感面板（path 带「光感」段拼接；★ 2026-09-12 分项退役——原「悬浮底栏」
  // 「其他控件」两搜索条目删除，搜索结果不再导向已退役的分项滑轨）──
  { title: SETTING_TITLE_IMMERSIVE_LEVEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_APPEARANCE + ' > ' + SETTING_TITLE_TAB_LIGHT, keywords: ['光感', '材质', '沉浸', '毛玻璃', '模糊'], pageName: ROUTE_APPEARANCE_PAGE, tab: 0 },
  { title: SETTING_TITLE_CONTENT_FALLBACK, path: PATH_ROOT + ' > ' + SETTING_TITLE_APPEARANCE + ' > ' + SETTING_TITLE_TAB_LIGHT, keywords: ['光感', '新规范', '规范', '官方', '标准', '材质', '内容区', '回退', '兜底'], pageName: ROUTE_APPEARANCE_PAGE, tab: 0 },
  // ── 外观显示 · 背景面板（M3 登记，tab=1；path 带「背景」段，dshinhm 口径随迁）──
  { title: SETTING_TITLE_PICK_IMAGE, path: PATH_ROOT + ' > ' + SETTING_TITLE_APPEARANCE + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['背景', '壁纸', '图片', '相册', '裁剪', '模糊', '遮罩'], pageName: ROUTE_APPEARANCE_PAGE, tab: 1 },
  { title: SETTING_TITLE_EDIT_IMAGE, path: PATH_ROOT + ' > ' + SETTING_TITLE_APPEARANCE + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['裁剪', '模糊', '遮罩', '背景', '壁纸'], pageName: ROUTE_APPEARANCE_PAGE, tab: 1 },
  { title: SETTING_TITLE_RESTORE_DEFAULT, path: PATH_ROOT + ' > ' + SETTING_TITLE_APPEARANCE + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['恢复', '默认', '背景', '壁纸'], pageName: ROUTE_APPEARANCE_PAGE, tab: 1 },
  // 背景仅用于会话页开关（2026-09-05 背景面板第四卡登记；tab=1 直达「背景」分段）
  { title: SETTING_TITLE_BG_SESSION_ONLY, path: PATH_ROOT + ' > ' + SETTING_TITLE_APPEARANCE + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['背景', '壁纸', '会话页', '对话页', '范围', '仅'], pageName: ROUTE_APPEARANCE_PAGE, tab: 1 },
  // ── 更多信息 · 关于域（M3 登记，dshinhm 口径随迁）──
  { title: SETTING_TITLE_ABOUT, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['关于', '版本', '应用', '图标'], pageName: ROUTE_ABOUT_PAGE, tab: -1 },
  { title: SETTING_TITLE_VERSION_INFO, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_ABOUT, keywords: ['版本', '更新', '检测'], pageName: ROUTE_ABOUT_PAGE, tab: -1 },
  // 获取安装包条目 2026-09-08 移除：功能已整体移除（决明「消除全部影响」）——公开签名 HAP
  // 经该卡分享外传任何设备可直接侧载；搜索与帮助不再导向
  // 权限信息/隐私政策（2026-09-07 自关于页卡片迁至更多信息页行卡——path 随入口迁移改挂
  // 更多信息页一级，同反馈与建议条目口径）
  { title: SETTING_TITLE_PERMISSION, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['权限', '隐私', '网络', '访问'], pageName: ROUTE_PERMISSION_PAGE, tab: -1 },
  { title: SETTING_TITLE_PRIVACY_POLICY, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['隐私', '个人信息', '数据', '政策', '收集', '授权'], pageName: ROUTE_PRIVACY_POLICY_PAGE, tab: -1 },
  { title: SETTING_TITLE_AI_ASSIST, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_ABOUT, keywords: ['AI', '人工智能', '辅助', '开发', '声明', '名单', '工具', 'Agent'], pageName: ROUTE_AI_ASSIST_PAGE, tab: -1 },
  { title: SETTING_TITLE_OPEN_SOURCE, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_ABOUT, keywords: ['开源', '鸣谢', '致谢', '第三方', '许可', '协议', 'Cube', 'MIT', '引用'], pageName: ROUTE_OPEN_SOURCE_PAGE, tab: -1 },
  // 反馈与建议（2026-09-07 MeoW 反馈通道登记：更多信息页行卡——反馈直达开发者；
  // 同日自关于页卡片移入，path 随入口迁移改挂更多信息页一级）
  { title: SETTING_TITLE_FEEDBACK, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['反馈', '建议', '意见', '问题', '联系开发者', '提意见', 'MeoW'], pageName: ROUTE_FEEDBACK_PAGE, tab: -1 },
  // ── 更多信息 · 运行日志（M3 登记，dshinhm 口径随迁）──
  { title: SETTING_TITLE_RUN_LOG, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['日志', '运行', '错误', '记录', '崩溃', '异常', '排查'], pageName: ROUTE_LOG_PAGE, tab: -1 },
  // ── 更多信息 · 请求日志（2026-09-23 请求日志笔登记：HTTP 请求现场——请求头/请求体/
  // 响应码，排障「连不上 / 发不出 / 用不了」；关键词含「接口」「http」等口语提法）──
  { title: SETTING_TITLE_REQ_LOG, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['日志', '请求', '记录', '接口', 'HTTP', '响应', '排查', '调试'], pageName: ROUTE_REQ_LOG_PAGE, tab: -1 },
  // ── 更多信息 · 帮助中心（2026-09-05 登记：更多信息页首张行卡——分板块功能与用法说明）──
  { title: SETTING_TITLE_HELP_CENTER, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['帮助', '使用说明', '指南', '教程', '上手', '怎么用', '用法', 'FAQ', '说明'], pageName: ROUTE_HELP_CENTER_PAGE, tab: -1 },
  // ── 偏好设置页（2026-09-01 登记；无分段 tab=-1，入口条目在上方一级入口组）──
  { title: SETTING_TITLE_THINK_EXPAND, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['思考', '思维链', '思考链', '展开', '收起', '折叠', '默认'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 流式引擎开关（2026-09-02 Cube 移植试验副本登记）
  { title: SETTING_TITLE_STREAM_ENGINE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['流式', '引擎', '实验', '试验', '打字机', '动效', '输出', '逐字'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 流式输出自动跟随开关（2026-09-02 登记）
  { title: SETTING_TITLE_STREAM_FOLLOW, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['跟随', '流式', '自动', '滚动', '随动', '输出', 'follow', 'scroll'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 网络自动重试开关（2026-09-22 登记：网络异常且本轮无内容产出时自动退避重发，最多 3 次）
  { title: SETTING_TITLE_AUTO_RETRY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['重试', '自动重试', '网络', '断网', '异常', '失败', '重发', 'retry', '自动'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 粘贴长文本转文件开关（2026-09-23 登记：粘贴的文本达到阈值时不插进输入框，改为转成文本附件）
  { title: SETTING_TITLE_PASTE_AS_FILE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['粘贴', '长文本', '附件', '剪贴板', '阈值', '文本'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 键盘发送开关（2026-09-03 登记）
  { title: SETTING_TITLE_KEYBOARD_SEND, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['键盘', '发送', '换行', '回车', '键盘发送'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 会话页屏幕常亮开关（2026-09-04 登记）
  { title: SETTING_TITLE_KEEP_SCREEN_ON, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['常亮', '亮屏', '亮着', '息屏', '熄屏', '锁屏', '不熄屏', 'keepScreenOn', '屏幕'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 会话时间显示开关（2026-09-04 登记）
  { title: SETTING_TITLE_SESSION_TIME, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['时间', '日期', '会话时间', '会话卡片', '显示', '列表', '卡片'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 会话图标显示开关（2026-09-19 登记：会话卡片左侧消息图标显隐）
  { title: SETTING_TITLE_SESSION_ICON, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['图标', '消息图标', '会话图标', 'icon', 'message', '卡片', '显示', '隐藏', '前缀'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 生物识别方式开关（2026-09-05 登记）
  { title: SETTING_TITLE_BIOMETRIC_FACE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['生物识别', '人脸', '指纹', '加密', '认证', '解锁'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 页签切换动画开关（2026-09-08 登记）
  { title: SETTING_TITLE_TAB_SWITCH_ANIM, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['页签', '切换', '动画', '转场', '滑动', '横向', 'tab', '直达'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // 启动进入页面卡（2026-09-08 登记：冷启动默认进入新对话或会话列表）
  { title: SETTING_TITLE_LAUNCH_ENTRY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['启动', '打开', '进入', '默认', '新对话', '会话列表', '首页', '开机', 'launch'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // ── 功能模型页（2026-09-05 登记；入口条目在上方一级入口组）──
  { title: SETTING_TITLE_DEFAULT_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['默认模型', '默认对话模型', '兜底', '缺省', '回退', '指定', '模型'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 标题生成卡（2026-09-05 AI 会话标题登记）
  { title: SETTING_TITLE_TITLE_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['标题', '标题生成模型', '会话名', '自动命名', '命名', '摘要', '改名', '提示词', 'title'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 记忆提取卡（2026-09-11 记忆优化笔补登记——此前漏登记致搜「记忆提取模型」无结果；
  // ★ 2026-09-16 卡名去「模型」二字，keywords 补旧名兼容搜索）
  { title: SETTING_TITLE_MEMORY_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['记忆', '提取', '整理', '记忆模型', '记忆提取模型', '记忆整理', '沉淀', 'memory'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 记忆优化卡（2026-09-11 记忆优化模型二期登记；★ 2026-09-16 同上补旧名 keywords）
  { title: SETTING_TITLE_MEMORY_OPT_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['记忆', '优化', '去重', '合并', '改写', '润色', '整理', '记忆优化模型', 'memory'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 文字识别卡（2026-09-15 附件 OCR 二期登记：附件图片与扫描件发送前识别成文字；
  // ★ 2026-09-16 开关化补「系统识别」「模型识别」两词；★ 同日内置引擎落地补「内置识别」
  // 「离线」两词——三档段位名全在列，搜任一段名均可达；★ 2026-09-17 识别提示词开放自定义
  // 补「提示词」一词）
  { title: SETTING_TITLE_OCR, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['文字识别', '识别', '系统识别', '内置识别', '模型识别', '离线', 'OCR', '扫描', '扫描件', '图片', '附件', '视觉', '引擎', '提示词'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 推荐问题卡（2026-09-19 推荐问题功能登记：回复后追问推荐生成开关与模型；keywords 带
  // 「追问」「建议」等口语入口词）
  { title: SETTING_TITLE_SUGGEST, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['推荐', '推荐问题', '追问', '建议', 'followup', 'suggest'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 上下文压缩卡（2026-09-23 上下文压缩登记：会话上下文手动压缩的模型与提示词；
  // keywords 带「摘要」「总结」等口语入口词）
  { title: SETTING_TITLE_COMPRESS, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['压缩', '上下文压缩', '摘要', '总结', '压缩上下文', 'compress'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 记忆读取方式卡（2026-09-13 记忆按需读取登记：记忆页「记忆开关」板块分段卡——自动
  // 注入默认 / 按需读取切换；页级「记忆」入口条目 keywords 不动）
  { title: SETTING_TITLE_MEMORY_READ_MODE, path: PATH_ROOT + ' > ' + SETTING_TITLE_MEMORY, keywords: ['按需', '检索', '工具', '自动注入'], pageName: ROUTE_MEMORY_PAGE, tab: -1 }
];

// 可搜索设置项注册表总表 = 静态条目 + 帮助条目（2026-09-05 接入：帮助条目程序化生成
// 排在尾部——搜索结果里帮助内容在功能页之后）
export const SETTING_SEARCH_ITEMS: SettingSearchItem[] = [
  ...BASE_SEARCH_ITEMS,
  ...buildHelpSearchItems()
];

// ── 匹配（关键字精确搜索：子串包含、大小写不敏感；空关键词返回空）──
export function searchSettingItems(keyword: string): SettingSearchItem[] {
  const key: string = keyword.trim().toLowerCase();
  if (key === '') {
    return [];
  }
  return SETTING_SEARCH_ITEMS.filter((item: SettingSearchItem) =>
    item.title.toLowerCase().includes(key) ||
    item.keywords.some((word: string) => word.toLowerCase().includes(key)));
}

// ── 搜索历史（AppStorage + PersistentStorage 持久化，EntryAbility loadContent 成功回调
// 注册 persistProp——坑17 时机；姿势同 dshinhm：去重移头、截断上限，有界防内存/存储膨胀）──
export const SEARCH_HISTORY_KEY: string = 'settingSearchHistory';
// 上限 5 条（dshinhm 决明定稿随迁：只留近 5 个）
export const MAX_SEARCH_HISTORY: number = 5;
// 搜索词长度上限（dshinhm 定稿随迁：存储只留前 10 字——超长粘贴属误操作，截断后点击回填的
// 也是短词，搜索语义不受损；展示侧另有 maxWidth + 单行省略号双保险，见 SearchSections）
export const MAX_SEARCH_TERM_LENGTH: number = 10;

export function getSearchHistory(): string[] {
  const history: string[] | undefined = AppStorage.get<string[]>(SEARCH_HISTORY_KEY);
  // 读取侧同样截断：上限调整后持久化里可能残留超限旧数据，读取即收敛
  //（数组头部最新，slice 取最新数条；同 getRecentUse 姿势）
  return history === undefined ? [] : history.slice(0, MAX_SEARCH_HISTORY);
}

// 记录一次搜索词：截断长度上限 → 去重（已存在移到头部）→ 插头部 → 截断 MAX_SEARCH_HISTORY 条
export function recordSearchHistory(term: string): void {
  const trimmed: string = term.trim();
  if (trimmed === '') {
    return;
  }
  const limited: string = trimmed.slice(0, MAX_SEARCH_TERM_LENGTH);
  const history: string[] = getSearchHistory().filter((item: string) => item !== limited);
  history.unshift(limited);
  AppStorage.set(SEARCH_HISTORY_KEY, history.slice(0, MAX_SEARCH_HISTORY));
}

export function clearSearchHistory(): void {
  AppStorage.set(SEARCH_HISTORY_KEY, []);
}

// ── 最近使用：用户最近打开过的设置项（搜索跳转记录），存 title 一维字符串数组
//（对象数组禁止持久化，dshinhm 先例）；展示时按 title 在注册表反查完整条目
//（title 全注册表唯一——SETTING_TITLE_* 常量各不同，注册表新建条目时同样遵守）──
export const RECENT_USE_KEY: string = 'settingRecentUse';
// 上限 3 条（dshinhm 决明定稿随迁：只留三个避免列表过长）
export const MAX_RECENT_USE: number = 3;

export function getRecentUse(): string[] {
  const recent: string[] | undefined = AppStorage.get<string[]>(RECENT_USE_KEY);
  // 读取侧同样截断（同 getSearchHistory 姿势）
  return recent === undefined ? [] : recent.slice(0, MAX_RECENT_USE);
}

// 记录一次打开：去重（已存在移到头部）→ 插头部 → 截断 MAX_RECENT_USE 条（同历史有界姿势）
export function recordRecentUse(title: string): void {
  const trimmed: string = title.trim();
  if (trimmed === '') {
    return;
  }
  const recent: string[] = getRecentUse().filter((item: string) => item !== trimmed);
  recent.unshift(trimmed);
  AppStorage.set(RECENT_USE_KEY, recent.slice(0, MAX_RECENT_USE));
}

export function clearRecentUse(): void {
  AppStorage.set(RECENT_USE_KEY, []);
}

// 注册表反查（title → 完整条目，供最近使用项展示标题/面包屑/路由参数）
export function findItemByTitle(title: string): SettingSearchItem | undefined {
  return SETTING_SEARCH_ITEMS.find((item: SettingSearchItem) => item.title === title);
}
