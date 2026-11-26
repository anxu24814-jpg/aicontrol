// 设置项搜索注册表（设置页搜索键 → 搜索页 SearchPage）：全应用可搜索设置项的单一数据源
// + 标题常量单一来源 + 搜索历史持久化 + 最近使用记录（自 dshinhm 同名文件随迁）。
//
// ★ 可维护性约定（防误删/防漂移，新增或改名设置项时必须三处同步）：
//   ① 页面 UI 文字：一律引用本文件的 SETTING_TITLE_* 常量（禁止再写字面量）——
//      搜索结果文字与实际 UI 永远一致，改名只改常量一处；
//   ② 路由：nav/HomeNavigation.ets PageMap 链尾加 else if 分支（if/else if 链，坑51）；
//   ③ 注册表：SETTING_SEARCH_ITEMS 加条目（title 用常量、path 用常量拼接）。
//   ④ 帮助条目：不经手写——buildHelpSearchItems 程序化生成自 common/HelpContent.ets
//     （增删帮助条目只动 HelpContent，注册表自动同步零双源）。
// 可搜范围定稿（口径随 dshinhm 规范「能操作和不能操作的项都算设置项，但不是全可搜」）：
//   可搜 = 一级行卡入口 + 二级页内设置项；不搜 = 搜索页自身（防循环：注册表不含
//   SearchPage，跳转永远离开搜索页）。判定口诀：用户会不会想通过搜索找到并打开它——
//   会，就搜；它只是某个流程里的一步，就不搜。完整判定规程/增改删流程/校验防线见
//   dshinhm docs/设置项搜索规范.md（本项目无地址/图片编辑类目，规则裁剪）。
// 无高亮（决明定稿随迁）：结果项标题/路径纯文本展示，不做关键词高亮切分。

import {
  ROUTE_ABOUT_PAGE,
  ROUTE_AI_ASSIST_PAGE,
  ROUTE_COST_STATS_PAGE,
  ROUTE_FEEDBACK_PAGE,
  ROUTE_OPEN_SOURCE_PAGE,
  ROUTE_PRIVACY_POLICY_PAGE,
  ROUTE_HELP_CENTER_PAGE,
  ROUTE_HELP_TOPIC_PAGE,
  ROUTE_PREF_BACKGROUND_PAGE,
  ROUTE_PREF_FONT_PAGE,
  ROUTE_INFO_PAGE,
  ROUTE_LOG_PAGE,
  ROUTE_REQ_LOG_PAGE,
  ROUTE_PERMISSION_PAGE,
  ROUTE_PREFERENCES_PAGE,
  ROUTE_PREF_INPUT_SEND_PAGE,
  ROUTE_PREF_AUTO_RETRY_PAGE,
  ROUTE_PREF_REPLY_DISPLAY_PAGE,
  ROUTE_PREF_SESSION_READ_PAGE,
  ROUTE_PREF_APP_LAUNCH_PAGE,
  ROUTE_PROMPT_LIBRARY_PAGE,
  ROUTE_PROVIDER_PAGE,
  ROUTE_DATA_SYNC_PAGE,
  ROUTE_DS_HISTORY_IMPORT_PAGE,
  ROUTE_FUNCTIONAL_MODEL_PAGE,
  ROUTE_SYSTEM_PROMPT_PAGE,
  ROUTE_USAGE_STATS_PAGE,
  ROUTE_MEMORY_PAGE,
  ROUTE_PROACTIVE_PAGE,
  ROUTE_STORAGE_PAGE,
  ROUTE_WORKSPACE_MANAGE_PAGE,
  ROUTE_MOUNT_MANAGE_PAGE,
  ROUTE_SEARCH_ENGINE_PAGE,
  ROUTE_TOOLS_PAGE,
  ROUTE_MCP_PAGE,
  ROUTE_CODE_WORKBENCH_PAGE,
  ROUTE_NODE_RUNTIME_PAGE,
  ROUTE_PY_RUNTIME_PAGE,
  ROUTE_CODE_HTTP_HOSTS_PAGE,
  ROUTE_NETWORK_PAGE,
  ROUTE_WEB_SERVICE_PAGE,
  ROUTE_HTTP_REQUEST_PAGE,
  ROUTE_HTTP_CREDENTIALS_PAGE,
  ROUTE_HTTP_TEMPLATE_PAGE,
  ROUTE_SKILL_LIBRARY_PAGE,
  ROUTE_KNOWLEDGE_LIBRARY_PAGE
} from './RouteNames';
import { HELP_GROUPS } from './HelpContent';

// ── 标题常量（单一来源：页面 UI 与本注册表共用，改名只改这里）──
// 设置页签行卡（服务商管理行卡标题 + PageMap 标题栏共用）
export const SETTING_TITLE_PROVIDER: string = '服务商管理';
// 提示词库管理行卡标题（设置页第 2 卡 + 管理页标题共用）
export const SETTING_TITLE_PROMPT: string = '会话提示词';
// 系统提示词行卡标题（独立页管理：库页不显示、内置默认可更改可重置）；注入语义 =
// 会话提示词 > 助手提示词 > 系统提示词三级回退——系统提示词 = 注入基座兜底；存储 =
// prompt_templates.isGlobal 行（见 PromptTemplateDb 头注释）
export const SETTING_TITLE_SYSTEM_PROMPT: string = '系统提示词';
// 「偏好与外观」行卡标题（设置页卡6 + 页标题共用；重梳笔原「偏好设置」扩容承载外观域——
// 「外观显示」独立入口随三段拆行退役，搜索 keywords 保留旧名「偏好设置」兼容检索）
export const SETTING_TITLE_PREFERENCES: string = '偏好与外观';
// ★ 偏好页两级化：偏好页为入口导航页，四个入口行名（一级页行标题 + 各二级页页标题共用
// 单一来源；二级页内设置项的 SETTING_TITLE_* 常量不动）
export const SETTING_TITLE_PREF_INPUT_SEND: string = '输入与发送';
export const SETTING_TITLE_PREF_REPLY_DISPLAY: string = '回复显示';
export const SETTING_TITLE_PREF_SESSION_READ: string = '会话与阅读';
export const SETTING_TITLE_PREF_APP_LAUNCH: string = '应用与启动';
export const SETTING_TITLE_DATA_SYNC: string = '数据与同步';
// 「导入 DeepSeek 对话」三级页标题（数据与同步页入口卡 + 页标题 + 帮助条目共用——DS 导出包
// 解析为图态新会话落库）
export const SETTING_TITLE_DS_IMPORT: string = '导入 DeepSeek 对话';
// 功能模型行卡标题（设置页新卡 + 页标题共用——功能级模型配置集中页）
export const SETTING_TITLE_FUNCTIONAL_MODEL: string = '功能模型';
// 「功能模型」页首项行卡标题（默认对话——消费方 resolveActiveConnection 兜底链③级；
// keywords 保留旧名「默认模型」兼容搜索）
export const SETTING_TITLE_DEFAULT_MODEL: string = '默认对话';
// 「功能模型」页第二卡标题（标题生成——未配置 = 功能未启用静默不生成，生成链在
// common/TitleGen.ets；卡内「启用标题生成」总开关缺省开，关闭 = 生成链守卫序最前早退
// 零请求、两键配置保留；keywords 保留旧名兼容搜索）
export const SETTING_TITLE_TITLE_MODEL: string = '标题生成';
// 「功能模型」页第三卡标题（记忆提取——记忆整理独立可配，未配置则不整理、不回退标题模型；
// 生成链在 common/MemoryGen.ets；keywords 保留旧名「记忆提取模型」兼容搜索）
export const SETTING_TITLE_MEMORY_MODEL: string = '记忆提取';
// 「功能模型」页第四卡标题（记忆优化——对库内已有记忆做去重与改写，未配置则不优化、
// 不回退提取模型；生成链在 common/MemoryOpt.ets；keywords 保留旧名兼容搜索）
export const SETTING_TITLE_MEMORY_OPT_MODEL: string = '记忆优化';
// 「功能模型」页第五卡标题（文字识别——总开关默认开；卡内三分段「系统识别 / 内置识别 /
// 视觉模型」引擎三态互斥单值；链路在 common/OcrEngine.ets + providers/OcrPaddle.ets
//〔内置〕+ providers/OcrVisionApi.ets〔视觉〕）
export const SETTING_TITLE_OCR: string = '文字识别';
// 「功能模型」页第六卡标题（推荐问题——消息后追问推荐，总开关默认关〔BYOK 显式授权〕，
// 未选模型 = 零请求；生成链在 common/SuggestGen.ets）
export const SETTING_TITLE_SUGGEST: string = '推荐问题';
// 「功能模型」页审批卡标题（命令审批——配置后写操作先由审批模型自动审核，普通写操作通过
// 即执行、删除类放行仍问人；未配置 = 功能未启用照旧弹卡。卡内「启用命令审批」总开关
//〔关闭 = 与未配置同语义〕与「提示词」键；审批链在 common/providers/ApprovalGate.ets）
export const SETTING_TITLE_APPROVAL: string = '命令审批';
// 「功能模型」页功能思考档位卡标题（八条功能模型小任务链共用的全局思考档位，''=默认不干预
// 随服务商出厂设置——聊天对话不受影响；消费链组装口在 common/providers/TitleApi.ets）
export const SETTING_TITLE_FUNCTIONAL_THINKING: string = '功能思考档位';
// 「功能模型」页第七卡标题（上下文压缩——会话上下文的手动压缩，模型未配置回退当前会话
// 模型；生成链在 common/CompressGen.ets）
export const SETTING_TITLE_COMPRESS: string = '上下文压缩';
// 「偏好设置」页行卡标题（默认展开思考——消费方 ChatThinkingStep 初始态）
export const SETTING_TITLE_THINK_EXPAND: string = '默认展开思考';
// （原「流式引擎（试验）」标题常量已随开关行与注册条目删除——实验链整域退役，无引擎分流）
// 「偏好设置」页行卡标题（流式输出自动跟随——消费方 ChatFollowController.maybeFollow
// 单点拦截）
export const SETTING_TITLE_STREAM_FOLLOW: string = '流式输出自动跟随';
// 「偏好设置」页行卡标题（会话加载动画——消费方 ChatPageContent 加载分支 @StorageProp
// 订阅，切换后下次进入会话生效；默认开 = 进会话加载期间消息区显示淡蒙层与加载动画）
export const SETTING_TITLE_CHAT_LOADING_OVERLAY: string = '会话加载动画';
// 「偏好设置」页行卡标题（HTML 预览运行脚本——消费方 MarkdownPreviewCover.aboutToAppear
// 点开时刻读取一次，预览为点开才建的新实例天然即时；默认关 = 受限预览照剥脚本，安全优先）
export const SETTING_TITLE_PREVIEW_JS: string = 'HTML 预览运行脚本';
// 「偏好设置」页行卡标题（长代码块自动收起——消费方 MarkdownScrollableBlock 终态评估处
// 现读，已终态块不再重评、重进会话后生效；默认关）
export const SETTING_TITLE_CODE_AUTO_COLLAPSE: string = '长代码块自动收起';
// 「偏好设置」页行卡标题（代码块行号——消费方 MarkdownCodeText / MarkdownHtmlBlockView /
// ChatToolDiffBlock 渲染期现读，已挂载块不即时增删行号、重进会话后生效；默认开 = Markdown
// 代码块、HTML <pre> 与工具卡 diff 块逐行显示行号）
export const SETTING_TITLE_CODE_LINE_NUMBERS: string = '代码块行号';
// 「偏好设置」页行卡标题（长消息进页收起——关 = 进页全部展开、由加载动画承担等待；
// 消费方 ChatMessageItem 折叠判据渲染期现读，已挂载消息不即时换形态、重进会话后生效；
// 默认开 = 进页收起超长消息）
export const SETTING_TITLE_LONG_MSG_COLLAPSE: string = '长消息进页收起';
// 「偏好设置」页行卡标题（显示助手消息气泡——消费方 ChatPageContent 进页读一次后下发
// ChatMessageItem，已挂载消息不即时换形态、重进会话后生效；默认开 = 助手回复带气泡底色）
export const SETTING_TITLE_ASSISTANT_BUBBLE: string = '显示助手消息气泡';
// 「偏好设置」页行卡标题（思考档位滑轨——消费方 ChatTitleBarOverlay @StorageProp @Watch 订阅，
// 拨动即生效；默认开 = 点标题栏「思考」用滑轨面板选档，关闭后回到原菜单）
export const SETTING_TITLE_THINKING_SLIDER: string = '思考档位滑轨';
// 「偏好设置」页行卡标题（消息内 HTML 直接渲染——消费方 MarkdownScrollableBlock 内容分支
// 现读，已挂载块不即时换渲染、重进会话后生效；默认开 = 投影非空才渲染、超限畸形整块退源码）
export const SETTING_TITLE_HTML_BLOCK_RENDER: string = '消息内 HTML 直接渲染';
// （原「SVG 图形预览」标题常量与注册表条目已随开关退役删除——恒开，搜索到一个没有开关的
//   设置项即死链）
// 「偏好设置」页行卡标题（键盘发送——消费方 ChatInputBar enterKeyType 订阅；默认关 = 换行键）
export const SETTING_TITLE_KEYBOARD_SEND: string = '键盘发送';
// 「偏好设置」页行卡标题（输入框常驻展开——消费方 ChatInputBar 恒展开订阅与收起守卫；
// 默认关 = 收起态胶囊）
export const SETTING_TITLE_INPUT_EXPANDED: string = '输入框常驻展开';
// 「偏好设置」页行卡标题（图片链接作为图片发送——消费方 TextImageFetch 发送链早退现读
//〔isTextImageFetchEnabled〕；默认关 = Markdown 图链按普通文本发送，开启后发送时自动
// 下载图链作为图片附件随本轮请求发给模型）
export const SETTING_TITLE_TEXT_IMAGE: string = '图片链接作为图片发送';
// 「偏好设置」页行卡标题（拍照保存到相册——消费方 AttachmentPickCtrl.pick 相机分支现读
//〔isPhotoSaveGalleryEnabled〕拨动即生效；默认关 = 相册零痕迹〔保存时机 = 拍照时刻，与是否
// 发送无关，只影响「拍照」入口〕）
export const SETTING_TITLE_PHOTO_SAVE_GALLERY: string = '拍照保存到相册';
// 「输入与发送」页行卡标题（添加图片时编辑——消费方 AttachmentPickCtrl.pick 相机与相册分支
// 现读〔isPhotoEditEnabled〕拨动即生效；默认关 = 拍完选完直接进输入框，只影响这两个入口）
export const SETTING_TITLE_PHOTO_EDIT: string = '添加图片时编辑';
// 「偏好设置」页行卡标题（屏幕常亮——消费方 ChatPage aboutToAppear/aboutToDisappear 窗口
// 常亮开关；默认关 = 系统息屏）
export const SETTING_TITLE_KEEP_SCREEN_ON: string = '屏幕常亮';
// 「偏好设置」页行卡标题（智感握姿跟随——「会话与阅读」板块两值分段卡，仅「列表右下」
// 档可开；消费方 components/chat/SessionNewFab @StorageProp @Watch 自订阅（'float' 档悬浮
// 键，关闭时恒右、拨关瞬间归右）；语义见 AppPreferences 同键注释）
export const SETTING_TITLE_HOLDING_FOLLOW: string = '智感握姿跟随';
// 「偏好设置」页「会话与阅读」板块「快捷新建键」分段卡标题（★ 2026-10-30 两档化，决明
// 「关闭这一项去掉——关掉就没有落点了」：两档 = 页签栏旁〔HdsTabs 官方迷你栏圆键，默认〕/
// 列表右下〔会话列表悬浮键〕，原 'off' 关闭档退役——两入口互斥由单键值域结构性保证；
// 消费方 = HomeNavigation〔miniBar 门控〕+ ChatSessionList〔悬浮键挂载门控〕，两处
// @StorageProp 订阅即刷。无帮助条目，不进裁名单）
export const SETTING_TITLE_NEW_SESSION_ENTRY: string = '快捷新建键';
// 「偏好设置」页行卡标题（后台回复提醒——「会话与阅读」组卡开关行；消费方 ChatBgReply
// 申请/发布两闸现读 + PrefSessionReadPage 开关行〔打开时顺带请求通知授权，被拒回落关〕；
// 默认关 = 不申请短时任务也不发通知；零新增权限，帮助说明见「权限信息」页说明卡）
export const SETTING_TITLE_BG_REPLY_NOTIFY: string = '后台回复提醒';
// 「会话与阅读」组卡开关行标题（会话宫格视图——两列宫格 / 单列列表显示形态开关，默认关；
// 消费方 PrefSessionReadPage 组卡开关行）
export const SETTING_TITLE_SESSION_CARD_GRID: string = '会话宫格视图';
// 「自动重试」标题（输入与发送页入口行 + 独立设置页标题；总开关承接旧布尔键语义，判据
// 参数经 ChatAutoRetryHost.autoRetryCfg 读 prefAutoRetryCfg 配置、轮内锁定；默认开 = 有意
// 选择〔只在零产出的失败触发〕，理由见 AppPreferences 键注释）
export const SETTING_TITLE_AUTO_RETRY: string = '自动重试';
// 「偏好设置」页「粘贴长文本转文件」卡标题（消费方 ChatInputBar 判定前订阅本开关与阈值；
// 默认开 = 粘贴文本达到阈值即转 .txt 附件；含开关与阈值滑轨合一卡〔决明拍板〕；帮助条目
// 同名同裁〔HELP_SKIP_TITLES〕——该卡已可搜直达）
export const SETTING_TITLE_PASTE_AS_FILE: string = '粘贴长文本转文件';
// 「粘贴长文本转文件」卡内阈值行标题（卡内参数名行与编辑弹窗标题共用）——按滑轨卡口径
// 不另立搜索注册项（页面级条目已在，内卡不逐张注册）
export const SETTING_TITLE_PASTE_AS_FILE_THRESHOLD: string = '粘贴长度阈值';
// 「偏好设置」页「时间间隔提醒」卡标题（消费方 ChatSendCtrl.assembleRound 每轮现读
// isTimeReminderEnabled / timeReminderMinutes；默认关 = 有意选择〔本功能改变发出去的请求
// 内容，静默生效会让用户困惑〕，理由见 AppPreferences 键注释；卡形制照粘贴卡开关滑块合一，
// 阈值行不另立注册项；帮助条目同名同裁〔HELP_SKIP_TITLES〕）
export const SETTING_TITLE_TIME_REMINDER: string = '时间间隔提醒';
// 「偏好设置」页行卡标题（页签切换动画——消费方 HomeNavigation 底部页签切换动画时长；
// 默认开 = 横向滑切，关 = 点按直达）
export const SETTING_TITLE_TAB_SWITCH_ANIM: string = '页签切换动画';
// 「偏好设置」页行卡标题（启动进入页面——消费方 HomeNavigation 冷启动首帧 aboutToAppear
// 现读；默认关 = 进入对话一级页会话列表）
export const SETTING_TITLE_LAUNCH_ENTRY: string = '启动进入页面';
// 二级页标题
export const SETTING_TITLE_MORE_INFO: string = '更多信息';
// （原「外观显示」页标题常量已随重梳笔退役——外观三段拆为「偏好与外观」页三入口行 +
//   三张三级页，页标题由 SETTING_TITLE_TAB_* 三常量分别承接；沿革见变更记录）
// （原「光感」分段标签与「沉浸光感档位」标题常量已随外观页光感段删除——档位固定强档、
//   无调整面〔键与档位函数族保留为能力位，见 ImmersiveLevel.ets 头注释〕）
// （原「光感新规范」常量已随该卡撤除——内容区件的官方标准外观改为常态、无用户入口
//  〔键 CONTENT_FALLBACK_KEY 保留为能力位〕）
// 「背景」三级页页标题（= 偏好与外观页「外观」板块入口行标题共用单一来源）
export const SETTING_TITLE_TAB_BACKGROUND: string = '背景';
// 「侧栏对话形态」开关行（2026-11-16 首页布局双形态笔，2026-11-18 迁址）：偏好与外观 →
// 应用与启动页开关行——首页布局两形态热切换（开 = 侧栏对话形态 / 关 = 底栏页签）
export const SETTING_TITLE_HOME_LAYOUT: string = '侧栏对话形态';
export const SETTING_TITLE_PICK_IMAGE: string = '选择图片';
export const SETTING_TITLE_EDIT_IMAGE: string = '编辑图片';
export const SETTING_TITLE_RESTORE_DEFAULT: string = '恢复默认';
// 「背景」页背景生效范围分段行卡（段项 仅会话页 = 自定义背景只在会话页显示 / 全应用；
// 键仍布尔、消费方 PageBackground 组合判定）
export const SETTING_TITLE_BG_SESSION_ONLY: string = '背景生效范围';
// 「字体」三级页页标题（= 偏好与外观页入口行标题共用；节标题常量：正文字体 / 代码字体兼作
// 选择卡节标题与搜索条目标题；消费方 ChatFontSection 与搜索注册表）
export const SETTING_TITLE_TAB_FONT: string = '字体';
export const SETTING_TITLE_FONT_BODY: string = '正文字体';
export const SETTING_TITLE_FONT_CODE: string = '代码字体';
export const SETTING_TITLE_FONT_CUSTOM: string = '自定义字体';
// 「外观显示」页字体范围分段行卡（段内自定义字体卡下方——段项 仅会话页 = 字体只在会话页生效
//〔默认〕/ 全应用 = 正文档全局；键仍布尔、消费方 ChatFontSection）
export const SETTING_TITLE_FONT_SESSION_ONLY: string = '字体生效范围';
// 关于页域（更多信息的子页）
export const SETTING_TITLE_ABOUT: string = '关于';
export const SETTING_TITLE_PERMISSION: string = '权限信息';
export const SETTING_TITLE_PRIVACY_POLICY: string = '隐私政策';
export const SETTING_TITLE_VERSION_INFO: string = '版本信息';
export const SETTING_TITLE_AI_ASSIST: string = 'AI 辅助开发声明';
export const SETTING_TITLE_OPEN_SOURCE: string = '开源项目鸣谢';
// 反馈与建议（更多信息页行卡标题 + 反馈页标题共用）
export const SETTING_TITLE_FEEDBACK: string = '反馈与建议';
// 运行日志页（更多信息的子页）
export const SETTING_TITLE_RUN_LOG: string = '运行日志';
// 请求日志页（更多信息的子页——HTTP 请求现场记录，排障用）
export const SETTING_TITLE_REQ_LOG: string = '请求日志';
// 帮助中心页（更多信息页首张行卡 + 页标题共用——分板块卡片说明功能与用法）
export const SETTING_TITLE_HELP_CENTER: string = '帮助中心';
// 「用量统计」行卡标题（设置页组卡行 + 页标题共用——概览/按模型/逐日纯列表页）
export const SETTING_TITLE_USAGE_STATS: string = '用量统计';
// 「费用估计」行卡标题（「用量统计+费用估计」组卡第二行 + 页标题共用；帮助条目同名同裁
//〔HELP_SKIP_TITLES〕——页面本身可搜直达）
export const SETTING_TITLE_COST_STATS: string = '费用估计';
// 「记忆」行卡标题（「记忆 + 主动消息」双行组卡 + 页标题共用——跨会话长期记忆管理页
//〔查看/编辑/删除/手动添加/立即整理 + 总开关与自动整理〕）
export const SETTING_TITLE_MEMORY: string = '记忆';
// 「主动消息」行卡标题（「记忆 + 主动消息」组卡第二行 + 页标题共用——开关卡 + 三张滑轨卡；
// 帮助条目同名同裁〔HELP_SKIP_TITLES〕——页面本身可搜直达）
export const SETTING_TITLE_PROACTIVE: string = '主动消息';
// 「主动消息」页内四卡标题（总开关单开关卡 + 触发间隔/每日最多/静默期三张滑轨卡）
export const SETTING_TITLE_PROACTIVE_ENABLED: string = '启用主动消息';
export const SETTING_TITLE_PROACTIVE_INTERVAL: string = '触发间隔';
export const SETTING_TITLE_PROACTIVE_DAILY_LIMIT: string = '每日最多';
export const SETTING_TITLE_PROACTIVE_QUIET_MAX: string = '静默期上限';
// 「记忆」页开关组卡两行标题（两开关进 set/get_app_preference 白名单——白名单条目 setting
// 字段必须 = 界面真实标题，本常量即该界面的单一来源，MemoryPage 行 label 与白名单同引）
export const SETTING_TITLE_MEMORY_ENABLED: string = '记忆功能';
export const SETTING_TITLE_MEMORY_AUTO: string = '退出会话后自动整理';
// 「记忆」页读取方式分段卡标题（自动注入 / 按需读取——卡内标题行与搜索注册表共用）
export const SETTING_TITLE_MEMORY_READ_MODE: string = '读取方式';
// 「存储管理」行卡标题（「数据与同步」组卡第二行 + 页标题共用——六分类占用展示与可安全
// 清理页；官方存储管理最佳实践「提供应用内清理入口」的落点）
export const SETTING_TITLE_STORAGE: string = '存储管理';
// 「联网搜索」行卡标题（「设置 → 工具调用」页首组卡首行 + 页标题共用——引擎列表页
//〔分段已启用/已停用 + 引擎卡进详情页配置〕；帮助条目同名同裁〔HELP_SKIP_TITLES〕——
// 页面本身可搜直达）
export const SETTING_TITLE_SEARCH_ENGINE: string = '联网搜索';
// （原「联网搜索总开关」常量已随总开关卡与控制台白名单条目退役删除——全局恒开后该
//   设置项不存在）
// 「工具调用」行卡标题（设置页主卡行 + 二级页——页现承载各全局工具确认卡；帮助中心两条
// 同名「工具调用」条目均为助手编辑页语义〔页面不同〕不入 HELP_SKIP，注册表同题经消歧
// 后缀区分）
export const SETTING_TITLE_TOOLS: string = '工具调用';
// 「脚本工作台」行卡与页标题（工具调用页首组卡跳转行 + 脚本工作台设置页标题 + 搜索注册
// 条目共用；搜索 keywords 避用「工作区」防与文件工作区条目双命中）。
// ★ 2026-11-16 改题（决明拍板）：原「代码工作台」——「代码」语义过宽（Python 也是代码却不在
// 本页管辖），用户点进来只见 JavaScript 与模拟 Shell 两模式，故收窄为「脚本」。符号名与路由
// 名不变（单源在值，改题只改本行）；连带面 = ToolTypes.TOOL_GROUP_CODE / HelpContent 条目名
// 与指路句 / HttpPolicy 与 ToolClip 回执 / ToolCodeExec 与 ToolPyExec 两 desc / 页内文案 /
// 两条断言锚（assert-feature-domain 6689 段锚、assert-ui-shape 信封句）
export const SETTING_TITLE_CODE_WORKBENCH: string = '脚本工作台';
// 「脚本联网域名」卡与页标题（脚本工作台页域名入口卡、助手级域名管理卡与全局总览/管理页
// 标题共用；已登记直达总览页条目，改名只改这里）
export const SETTING_TITLE_CODE_HTTP_HOSTS: string = '脚本联网域名';
// 「允许脚本发写请求」开关卡标题（写授权 = 全局单开关，落脚本工作台页；不进搜索注册表
// ——不是独立入口，「写请求」检索意图由「脚本工作台」条目 keywords 承接）
export const SETTING_TITLE_CODE_SCRIPT_WRITE: string = '允许脚本发写请求';
// 「脚本引擎」卡标题（引擎三态：跟随档位 / 试验引擎 / 系统引擎；卡标题与搜索注册表共用）
export const SETTING_TITLE_CODE_ENGINE: string = '脚本引擎';
// 「文件工作区」行卡标题（工具域卡内行 + 管理页标题栏 + 搜索注册条目三处共用；帮助条目
// 同名照裁〔HELP_SKIP_TITLES〕——搜索「文件工作区」直达管理页为最合用户意图的落点）
export const SETTING_TITLE_WORKSPACE: string = '文件工作区';
// 「文件夹挂载」行卡标题（工具域卡第四行 + 管理页标题栏 + 搜索注册条目三处共用；帮助条目
// 同名照裁〔HELP_SKIP_TITLES〕——搜索「文件夹挂载」直达管理页为最合用户意图的落点）
export const SETTING_TITLE_MOUNT: string = '文件夹挂载';
// 网页高危操作确认（★ 2026-11-09 三档归一笔记：该卡与浏览器控制页整页退役，检索词并入
//「新会话默认权限」条目——老用户按「每次确认」「一律放行」「自动通过」仍搜得到）
// 原 SETTING_TITLE_BROWSE_CONFIRM 常量随条目删除，勿回游。
// 「浏览器控制」页标题与「HTTP 写操作确认」卡标题两常量已删（2026-11-18 待拍板 9 收口，
// 决明拍板「废弃常量删除」——2138/2150 退役笔残留墓碑零消费方，整段清退勿回游）
// 「HTTP 请求」设置页标题 + 「请求超时上限」卡标题（工具调用页跳转行落点页——http_request
// 工具专属设置；★ 与「HTTP 写操作确认」是两件事——那是确认档卡，这是工具专属设置页）
export const SETTING_TITLE_HTTP_REQUEST: string = 'HTTP 请求';
export const SETTING_TITLE_HTTP_TIMEOUT: string = '请求超时上限';
// 「MCP」行卡标题（工具调用页入口行 + MCP 服务器管理页标题 + 搜索注册条目三处共用。
// MCP = Model Context Protocol，让助手使用外部工具的开放协议）
export const SETTING_TITLE_MCP: string = 'MCP';
// 「Python 运行环境」行卡与页标题（工具调用页首组卡跳转行 + 运行环境管理页标题 + 搜索注册
// 条目三处共用；2026-11-14 闲3门4批立——解释器状态与预置包查看，首用落位经页内「检查环境」键；
// 帮助条目同批已入 HelpContent「Python 运行」组，本页标题与该件各管一面）
export const SETTING_TITLE_PY_RUNTIME: string = 'Python 运行环境';
// 「Node 运行环境」行卡与页标题（工具调用页首组卡跳转行 + 运行环境管理页标题 + 搜索注册条目三处
// 共用；2026-11-24 鸿蒙 Node 运行时门 4 立——运行环境状态与占用、已装包清单、清空安装包与重建
// 运行区；帮助说明挂在 HelpContent「Node 运行」条目内，条目名与本页标题不同题、不进裁剪名单）
export const SETTING_TITLE_NODE_RUNTIME: string = 'Node 运行环境';
// 「同一域名请求间隔」卡标题（HTTP 请求设置页第二卡——同域出站最小间隔档 关/0.5 秒/
// 1 秒/2 秒；与注册表共用）
export const SETTING_TITLE_HTTP_INTERVAL: string = '同一域名请求间隔';
// 「HTTP 凭据」总览页/管理页标题（HTTP 请求页入口卡 → 凭据总览页〔全局卡 + 每助手卡〕→
// 管理页；全局卡与管理页复用本常量，助手组管理页标题动态拼助手名不在注册表）
export const SETTING_TITLE_HTTP_CREDENTIALS: string = 'HTTP 凭据';
// 「域名准入」卡标题（HTTP 请求设置页内容卡——域名白名单收紧面；2026-11-11 域名确认档退役后
// 本页域名类卡只剩这一张）
export const SETTING_TITLE_HTTP_ALLOWLIST: string = '域名准入';
// （原「出站记录」标题常量与注册表条目已退役——与「请求日志」并为同一跳转入口；检索词
//   〔出站/审计/发过什么〕并入请求日志条目，审计用法由其「只看 HTTP 请求」筛选档承接）
// 「请求模板」入口卡标题（跳模板列表页的管理入口，与注册表共用）
export const SETTING_TITLE_HTTP_TEMPLATES: string = '请求模板';
// 「新会话默认权限」卡标题（★ 2026-11-09 会话权限模式笔：原「数据管理操作确认」三档卡
// 退役，原位换会话级默认档卡；同日三档归一笔记开放三档——谨慎 / 标准 / 高效，分段标签
// 单源在 ToolsSettingsPage.defaultModeItems）
export const SETTING_TITLE_DEFAULT_PERMISSION_MODE: string = '新会话默认权限';
// 「工具调用轮数上限」卡标题（全局参数卡，全助手一份；值域与语义单源 =
// common/providers/ToolLimits.ets）
export const SETTING_TITLE_TOOL_STEP_LIMIT: string = '工具调用轮数上限';
// 「搜索结果条数」卡标题（联网搜索页全局参数卡；值域与换算单源 =
// common/search/SearchLimits.ets）
export const SETTING_TITLE_SEARCH_COUNT: string = '搜索结果条数';
// 「联网请求超时」卡标题（联网搜索页超时滑轨卡；值域单源 = common/search/SearchLimits.ets。
// ★ 与网络设置页「请求读超时」〔管等模型回复、分钟级〕刻意分名分链，读数混淆见该键注释）
export const SETTING_TITLE_SEARCH_TIMEOUT: string = '联网请求超时';
// 「网络设置」二级页标题（设置页「网络」组卡跳转行 + 页标题栏 + 搜索注册三处共用；
// 页内 UA 设置项见 SETTING_TITLE_USER_AGENT）
export const SETTING_TITLE_NETWORK: string = '网络设置';
// 「Web 服务」二级页标题（「网络」组卡第二行入口 + 页标题栏 + 搜索注册三处共用——浏览器
// 远程访问设置页〔启动卡 + 端口与仅本机设置〕）
export const SETTING_TITLE_WEB_SERVICE: string = 'Web 服务';
// 「User-Agent」内容卡标题（网络设置页内容卡——控件非行形态不进组卡；与注册表共用）
export const SETTING_TITLE_USER_AGENT: string = 'User-Agent';
// 「请求读超时」卡标题（网络设置页第二卡——聊天流式读超时档位；分段标签「5/10/20 分钟」
// 单源在 NetworkSettingsPage.readTimeoutItems）
export const SETTING_TITLE_READ_TIMEOUT: string = '请求读超时';
// 「代理」卡标题（网络设置页第三卡——出站代理三档控制面；分段标签单源在
// NetworkSettingsPage.proxyItems）
export const SETTING_TITLE_PROXY: string = '代理';
// 「技能库」行卡标题（设置页行卡 + 页标题共用——技能清单管理页〔管理入口只在设置页〕；
// 技能 = 助手的「怎么做某件事」说明书，按触发描述被模型自主加载。帮助条目同名语义不同
//〔条目讲概念与用法，页面是清单管理〕，不入 HELP_SKIP）
export const SETTING_TITLE_SKILL_LIBRARY: string = '技能库';
// 「知识库」行卡标题（设置页行卡 + 页标题共用——词条本管理页〔管理入口只在设置页〕；
// ★ 用户可见名一律「知识库」，世界书/World Book/Lorebook 只出现在文档与代码注释里不上屏；
// 帮助条目同名语义不同——处置与「技能库」刻意不同，见 HELP_SKIP_TITLES 内该条注释）
export const SETTING_TITLE_KNOWLEDGE_LIBRARY: string = '知识库';

// 面包屑根（一级页名 = 设置页签标题）
const PATH_ROOT: string = '设置';

// ── 帮助条目搜索注册（程序化生成，单一数据源 common/HelpContent.ets，增删只动该件）──
// 帮助条目面包屑前缀 = 帮助中心入口条目 path 延伸
const HELP_PATH_ROOT: string = PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_HELP_CENTER;
// 裁剪名单（决明拍板）：与既有注册表条目完全重名的帮助条目不生成——对应功能页本身可被
// 搜索直达，重复注册会造成 title 冲突与结果冗余。名单用 SETTING_TITLE_* 常量比对（改名
// 自动跟随）；名单与消歧规则变更须同步 scripts/setting-search-check.mjs 第 8 查。
// ★「工具调用」条目特殊：对应两条帮助条目〔不同组同题〕，裁剪按题名生效两条同裁——帮助
// 条目讲的是助手编辑页工具区块〔页面不同语义不同〕，照裁是守「同题不冗余」规则的代价，
// 搜索先达设置页、其文案再指路助手编辑页；条目本身在帮助中心仍可浏览。
// （原「自检」条目随应用内自检全量退役一并删除）
const HELP_SKIP_TITLES: string[] = [
  SETTING_TITLE_SYSTEM_PROMPT,
  SETTING_TITLE_DEFAULT_MODEL,
  SETTING_TITLE_ABOUT,
  SETTING_TITLE_PREFERENCES,
  SETTING_TITLE_RUN_LOG,
  // 请求日志（页面静态注册直达，帮助条目同语义照裁——照运行日志口径）
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
  // 脚本工作台（工具调用页首组卡行直达脚本工作台设置页，帮助条目同语义照裁——口径同文件工作区）
  SETTING_TITLE_CODE_WORKBENCH,
  // 主动消息（页面静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_PROACTIVE,
  // 导入 DeepSeek 对话（数据与同步页三级页静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_DS_IMPORT,
  // 文字识别（功能模型页卡静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_OCR,
  // ★ 2026-11-09 三档归一笔记：原「网页高危操作确认」「HTTP 写操作确认」两条帮助条目
  // 整条删除（各自设置卡已退役），本名单对应两项同步撤除；检索词并入「新会话默认权限」
  // HTTP 请求（工具调用页跳转行落点页静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_HTTP_REQUEST,
  // HTTP 凭据（凭据总览页静态注册直达〔HTTP 请求页内入口卡〕，帮助条目照裁——搜索「凭据/
  // 密钥」先达可操作的设置页；双入口的另一处〔助手编辑页卡〕不另立搜索项，工具域内设置
  // 以设置页为准）
  SETTING_TITLE_HTTP_CREDENTIALS,
  // 新会话默认权限（工具调用页内卡静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_DEFAULT_PERMISSION_MODE,
  // 侧栏对话形态（偏好与外观 → 应用与启动页开关静态注册直达，帮助条目同语义照裁——
  // ★ 2026-11-16 双形态笔：设置搜索直达开关行，帮助中心另有详解条目；2026-11-18 开关行迁址）
  SETTING_TITLE_HOME_LAYOUT,
  // 推荐问题（功能模型页卡静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_SUGGEST,
  // 上下文压缩（功能模型页卡静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_COMPRESS,
  // 命令审批（功能模型页卡静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_APPROVAL,
  // 功能思考档位（功能模型页卡静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_FUNCTIONAL_THINKING,
  // 知识库（页面静态注册直达；★ 处置与「技能库」刻意不同——技能域把帮助条目改名「技能」
  // 避开重名，而「知识库」是用户的通用叫法（帮助里另起名字反而难找），故帮助条目照用原名、
  // 由本名单裁掉搜索注册（帮助中心内仍可浏览；搜索「知识库」直达库页 = 用户最可能的意图）。
  // 判据 = setting-search-check 断言 A：帮助条目与静态注册表的重名集合须恰在本名单内）
  SETTING_TITLE_KNOWLEDGE_LIBRARY,
  // 粘贴长文本转文件（偏好页卡静态注册直达，帮助条目同语义照裁——裁掉的只是搜索注册，
  // 帮助中心内条目照常显示）
  SETTING_TITLE_PASTE_AS_FILE,
  // 时间间隔提醒（偏好页卡静态注册直达，帮助条目同语义照裁——裁掉的只是搜索注册）
  SETTING_TITLE_TIME_REMINDER,
  // 图片链接作为图片发送（偏好页「输入与发送」组卡行静态注册直达，帮助条目同语义照裁）
  SETTING_TITLE_TEXT_IMAGE,
  // User-Agent（网络设置页内容卡静态注册直达，帮助条目同题照裁）
  SETTING_TITLE_USER_AGENT,
  // 请求读超时（网络设置页内容卡静态注册直达，帮助条目同题照裁）
  SETTING_TITLE_READ_TIMEOUT,
  // 代理（网络设置页内容卡静态注册直达，帮助条目同题照裁）
  SETTING_TITLE_PROXY,
  // 会话宫格视图（偏好页「会话与阅读」组卡开关静态注册直达，帮助条目同题照裁——裁掉的
  // 只是搜索注册，帮助中心内条目照常显示）
  SETTING_TITLE_SESSION_CARD_GRID,
  // 文件工作区（设置页一级行卡静态注册直达管理页，帮助条目同名照裁——裁掉的只是搜索注册）
  SETTING_TITLE_WORKSPACE,
  // 文件夹挂载（工具域卡内行静态注册直达管理页，帮助条目同名照裁——口径同工作区条目）
  SETTING_TITLE_MOUNT,
  // MCP（工具调用页行静态注册直达管理页，帮助条目照用「MCP」通用叫法，由本名单裁掉搜索
  // 注册——口径同知识库条目）
  SETTING_TITLE_MCP,
  // Web 服务（设置页「网络」第二行静态注册直达设置页，帮助条目同题照裁——口径同 MCP 条目）
  SETTING_TITLE_WEB_SERVICE
];

// 帮助条目 → 搜索注册条目（点击直达条目详情页：pageName = 帮助详情路由，param = 条目 id
//「分组::标题」，HelpTopicPage 经 findHelpTopic 还原）。
// title 全表唯一守卫：与静态注册表查重，同名片目追加「 · 分组名」后缀消歧（通用规则，当前
// 无命中——两处「工具调用」已整题进裁剪名单，机制留作后续同题条目兜底；主词仍在前部，
// 子串搜索不受影响）。
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
        keywords = ['模板', '全选'];
      } else if (topic.title === '批量删除') {
        // UI 菜单项实际叫「多选」——搜菜单名也能找到本条目；「全选」= 批量条上的一键选中键
        keywords = ['多选', '全选'];
      } else if (topic.title === '脚本工作台') {
        // ★ 2026-11-16 改题：旧名「代码工作台」进 keywords 兼容检索——匹配为子串包含，
        // title 换名后不补旧名则老用户搜旧名直接失联（与设置条目同一条旧名口径）
        keywords = ['代码工作台'];
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
  // 面包屑路径（结果项副标题，如「设置 > 外观显示 > 背景」）
  path: string;
  // 额外匹配词（同义词/英文/口语词；title 本身的文字无需重复）
  keywords: string[];
  // 目标页路由名（HomeNavigation PageMap 分支名；★ 必须引用 common/RouteNames.ets 的
  // ROUTE_* 常量，禁止裸字符串——与 PageMap 分支天然同源，拼错编译期即报）
  pageName: string;
  // 目标页内分段标签（历史字段——重梳笔后无分段消费页，全表恒 -1；字段与 SearchPage.openItem
  // 的 tab >= 0 传参分支保留为未来分段页预留）
  tab: number;
  // 跳转 params（可选；未定义 = 现行为不变（tab >= 0 时传 tab，否则 null），SearchPage.
  // openItem 读取；帮助条目传条目 id「分组::标题」）
  param?: Object | null;
}

// 可搜索设置项注册表静态部分（顺序 = 结果列表顺序，按页面层级排列）。
// ★ 总表 SETTING_SEARCH_ITEMS 在下方 = 本静态表 + 帮助条目程序化生成（buildHelpSearchItems）
const BASE_SEARCH_ITEMS: SettingSearchItem[] = [
  // ── 一级入口 ──
  { title: SETTING_TITLE_PROVIDER, path: PATH_ROOT, keywords: ['服务商', '连接', '配置', 'API', '接口', '模型', 'baseUrl', 'apiKey', 'DeepSeek', '供应商'], pageName: ROUTE_PROVIDER_PAGE, tab: -1 },
  // 功能模型（一级入口——功能级模型配置集中页）
  { title: SETTING_TITLE_FUNCTIONAL_MODEL, path: PATH_ROOT, keywords: ['功能模型', '默认模型', '兜底', '缺省', '模型', 'default'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 系统提示词（独立页直达 SystemPromptPage；keywords 保留「全局默认」兼容旧叫法）
  { title: SETTING_TITLE_SYSTEM_PROMPT, path: PATH_ROOT, keywords: ['系统提示词', '人设', '角色', '指令', '注入', 'system', 'Prompt', '全局默认'], pageName: ROUTE_SYSTEM_PROMPT_PAGE, tab: -1 },
  // 提示词库（独立库页；keywords 含库页搜索框词「搜索提示词」——同记忆条目口径）
  { title: SETTING_TITLE_PROMPT, path: PATH_ROOT, keywords: ['提示词', '人设', '角色', '指令', '全局默认', 'system', 'Prompt', '注入', '搜索提示词'], pageName: ROUTE_PROMPT_LIBRARY_PAGE, tab: -1 },
  // 技能库（技能清单管理页；keywords 含「搜索技能」〔库页搜索框〕与「多选」〔库页「更多」
  // 菜单批量删除入口，三级页不进本表——命中本条再进库页〕）
  { title: SETTING_TITLE_SKILL_LIBRARY, path: PATH_ROOT, keywords: ['技能', '说明书', '流程', 'skill', '加载', 'use_skill', '搜索技能', '多选'], pageName: ROUTE_SKILL_LIBRARY_PAGE, tab: -1 },
  // 知识库（词条本管理页；keywords 含「搜索知识库」与「注入」「触发」「自动注入」——条目级
  // 注入配置与助手知识库页「关键词自动注入」开关不另立搜索项，命中本条目再进页）
  { title: SETTING_TITLE_KNOWLEDGE_LIBRARY, path: PATH_ROOT, keywords: ['知识库', '词条', '术语', '设定', 'world book', 'lorebook', '搜索知识库', '注入', '触发', '自动注入'], pageName: ROUTE_KNOWLEDGE_LIBRARY_PAGE, tab: -1 },
  // 记忆（导入/窗口外/撤销整理/搜索记忆/多选等入口都在库管理页「更多」菜单或库页〔三级页
  // 不进本表〕——搜索时命中本条目再进库页，为唯一可达路径）
  { title: SETTING_TITLE_MEMORY, path: PATH_ROOT, keywords: ['记忆', '长期记忆', '自动整理', '跨会话', '沉淀', '注入', '助手记忆', '全局记忆', '记忆库', '导入', '迁移', '其他平台', '窗口外', '撤销整理', '搜索记忆', '多选'], pageName: ROUTE_MEMORY_PAGE, tab: -1 },
  // 主动消息（「记忆 + 主动消息」组卡第二行，卡序与 SettingsPage.settingGroups 同步）
  { title: SETTING_TITLE_PROACTIVE, path: PATH_ROOT, keywords: ['主动消息', '主动发消息', '主动', '问候', '打招呼', '静默期', 'proactive'], pageName: ROUTE_PROACTIVE_PAGE, tab: -1 },
  // 工具调用（二级页承载各全局工具确认卡；帮助中心两条同名条目为助手编辑页工具区块语义，
  // 整题裁掉〔两条跨组同裁，见 HELP_SKIP_TITLES〕——搜索命中本条目，文案再指路助手编辑页）
  { title: SETTING_TITLE_TOOLS, path: PATH_ROOT, keywords: ['工具', '调用', '内置工具', 'tool'], pageName: ROUTE_TOOLS_PAGE, tab: -1 },
  // 联网搜索（入口落「设置 → 工具调用」页首组卡首行，面包屑随页面层级改二级；条目按本表
  //「按页面层级排列」置于父条目工具调用之后；pageName = 原页直达）
  { title: SETTING_TITLE_SEARCH_ENGINE, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['联网', '搜索', '引擎', '抓取', '博查', '秘塔', 'serper', 'bing', 'deepseek', '智谱', 'web', '多引擎'], pageName: ROUTE_SEARCH_ENGINE_PAGE, tab: -1 },
  // 脚本工作台（落点 = 脚本工作台设置页〔运行档位 + 脚本引擎 + 域名入口 + 写请求开关〕；
  // keywords 避用「工作区」〔已被文件工作区条目占用，双命中伤指路精确性〕；含「写请求」
  //「发请求」——写授权全局开关落本页。★ 含旧名「代码工作台」——2026-11-16 改题后旧名进
  // keywords 兼容检索〔匹配为子串包含，title 换成「脚本工作台」后不补旧名则老用户搜旧名
  // 直接失联；惯例同「偏好设置」「默认模型」等条目〕）
  { title: SETTING_TITLE_CODE_WORKBENCH, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['代码', '脚本', '沙箱', '执行', 'code', '档位', '写请求', '发请求', '代码工作台'], pageName: ROUTE_CODE_WORKBENCH_PAGE, tab: -1 },
  // Python 运行环境（落点 = 运行环境管理页〔解释器状态 + 预置包只读清单 + 检查环境键〕；
  // 行序与工具调用页首组卡一致 = 脚本工作台之后；keywords 含「数据分析」——预置 numpy/
  // pandas/matplotlib 等包，从用途入手也能命中；「自装包/安装包」接白名单安装检索意图，
  //「word/excel/ppt/pdf/文档」接自装包文档处理能力检索意图）
  { title: SETTING_TITLE_PY_RUNTIME, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['Python', '解释器', '运行环境', '数据分析', '自装包', '安装包', 'word', 'excel', 'ppt', 'pdf', '文档'], pageName: ROUTE_PY_RUNTIME_PAGE, tab: -1 },
  // Node 运行环境（落点 = 运行环境管理页〔状态与占用 + 已装包清单 + 清空安装包 / 重建运行区〕；
  // 行序与工具调用页首组卡一致 = Python 运行环境之后。keywords「运行环境」「安装包」「清理」与
  // Python / 存储管理两条共用是门 4 任务书代决——这三词是用户找本页的实际说法，搜它们多条并列、
  // 各自面包屑可辨；其余词零双挂）
  { title: SETTING_TITLE_NODE_RUNTIME, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['Node', 'npm', '运行环境', '安装包', '命令行', '清理'], pageName: ROUTE_NODE_RUNTIME_PAGE, tab: -1 },
  // 脚本联网域名（落点 = 总览页〔全局卡 + 每助手卡〕；keywords 避用「白名单」〔已被 HTTP
  // 域名准入条目占用〕；含「任何域名」「请求模式」——模式切换分段卡落总览页）
  { title: SETTING_TITLE_CODE_HTTP_HOSTS, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_CODE_WORKBENCH, keywords: ['脚本联网', '域名', '授权', 'httpGet', '联网域名', '任何域名', '请求模式'], pageName: ROUTE_CODE_HTTP_HOSTS_PAGE, tab: -1 },
  // 脚本引擎（引擎三态卡；pageName 复用脚本工作台设置页路由）
  { title: SETTING_TITLE_CODE_ENGINE, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_CODE_WORKBENCH, keywords: ['脚本', '引擎', '执行', '运行'], pageName: ROUTE_CODE_WORKBENCH_PAGE, tab: -1 },
  // 文件工作区（一级条目直达管理页——搜索「文件工作区」直达管理页为最合用户意图的落点；
  // keywords 覆盖「文件夹」「移动」「会话文件」「临时文件」等入口词；「改名」「删除」
  //「附件」已挂其他条目，零双挂规则不带）
  { title: SETTING_TITLE_WORKSPACE, path: PATH_ROOT, keywords: ['文件', '工作区', '上传文件', '保存文件', '助手文件', '文件夹', '新建文件夹', '移动', '会话文件', '临时文件'], pageName: ROUTE_WORKSPACE_MANAGE_PAGE, tab: -1 },
  // 文件夹挂载（直达管理页——授权 AI 访问本机文件夹〔系统目录选择器 + 持久授权〕；
  //「文件夹」被工作区条目占用，零双挂不带）
  { title: SETTING_TITLE_MOUNT, path: PATH_ROOT, keywords: ['挂载', '授权', 'AI 访问文件夹', '外部文件夹', '授权目录', '本机文件夹'], pageName: ROUTE_MOUNT_MANAGE_PAGE, tab: -1 },
  // ★ 2026-11-09 三档归一笔记：原「网页高危操作确认」「浏览器控制」「HTTP 写操作确认」
  // 三条注册整批删除（前两者随浏览器控制页退役，后者随 HTTP 页写操作确认卡退役）。三域
  // 审批设置的检索词全部并入下方「新会话默认权限」条目，老用户按旧词仍搜得到。
  // MCP（工具调用页入口行落点 = MCP 服务器管理页；keywords 含协议全称 Model Context Protocol）
  { title: SETTING_TITLE_MCP, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['MCP', 'mcp', '服务器', '工具', '插件', '扩展', 'Model Context Protocol'], pageName: ROUTE_MCP_PAGE, tab: -1 },
  // 新会话默认权限（keywords 带三档名与旧分域名词，覆盖「删记忆怎么老问我」「默认谨慎」
  //「网页确认」「HTTP 写操作确认」类说法——三域审批卡已并入本卡统管；★ 2026-11-11 自检轮：
  // 补「例外 / 始终允许 / 不再问 / 免确认」四词，域名确认档退役后这些当年挂在卡片与例外档上
  // 的说法无别处可落，统一由本卡解释「还问不问」）
  { title: SETTING_TITLE_DEFAULT_PERMISSION_MODE, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['权限', '权限模式', '默认权限', '新会话', '谨慎', '标准', '高效', '完全权限', '每次确认', '先问审批模型', '一律放行', '自动通过', '网页确认', 'HTTP 写操作确认', '确认', '例外', '始终允许', '不再问', '免确认', '审批模型', '删除', '记忆', '知识库', '提示词', '功能模型'], pageName: ROUTE_TOOLS_PAGE, tab: -1 },
  // 工具调用轮数上限（全局参数卡；keywords 覆盖用户原在助手编辑页找它的说法）
  { title: SETTING_TITLE_TOOL_STEP_LIMIT, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['工具', '调用', '轮数', '上限', '轮次', '次数', 'steps', 'rounds'], pageName: ROUTE_TOOLS_PAGE, tab: -1 },
  // HTTP 请求（工具调用页跳转行落点页——http_request 工具专属设置）
  { title: SETTING_TITLE_HTTP_REQUEST, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS, keywords: ['HTTP', 'http', '接口', '请求', 'api', 'API', '重定向', '跳转', '返回'], pageName: ROUTE_HTTP_REQUEST_PAGE, tab: -1 },
  // 请求超时上限（★ 与「请求读超时」「联网请求超时」三条的区分——本条偏「HTTP 工具」
  //「接口」语境，用户按「超时」搜则三条并列，各自面包屑可辨）
  { title: SETTING_TITLE_HTTP_TIMEOUT, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_HTTP_REQUEST, keywords: ['HTTP 超时', '接口超时', '请求超时', '超时上限', '等待', '超时', 'timeout'], pageName: ROUTE_HTTP_REQUEST_PAGE, tab: -1 },
  // 同一域名请求间隔（keywords 覆盖「限速」「频率」「打挂」——从「为什么连着调被挡住」入手也能命中）
  { title: SETTING_TITLE_HTTP_INTERVAL, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_HTTP_REQUEST, keywords: ['HTTP', '接口', '限速', '频率', '间隔', '同域', '域名', '太快', '打挂'], pageName: ROUTE_HTTP_REQUEST_PAGE, tab: -1 },
  // HTTP 凭据（凭据总览页；keywords 另带「令牌」「token」以接国外 API 语境）
  { title: SETTING_TITLE_HTTP_CREDENTIALS, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_HTTP_REQUEST, keywords: ['HTTP', '凭据', '密钥', '环境变量', '全局', '令牌', 'token', 'key', 'api'], pageName: ROUTE_HTTP_CREDENTIALS_PAGE, tab: -1 },
  // 请求模板（模板列表页；keywords 含「curl」「openapi」两导入源）
  { title: SETTING_TITLE_HTTP_TEMPLATES, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_HTTP_REQUEST, keywords: ['HTTP', '模板', '接口', '请求', 'curl', 'openapi', 'api', '复用'], pageName: ROUTE_HTTP_TEMPLATE_PAGE, tab: -1 },
  // 域名准入（keywords 覆盖「白名单」「只能访问哪些网站」类说法；2026-11-11 域名确认档退役后
  // 原「例外 / 始终允许 / 不再问」类检索词并归下方「新会话默认权限」条目——那三个词问的是
  // 「还要不要问我」，属于确认口径而非访问范围，落权限模式卡才是可解释面；本条目只答「能访问
  // 哪些域名」）
  { title: SETTING_TITLE_HTTP_ALLOWLIST, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_HTTP_REQUEST, keywords: ['域名', '白名单', '准入', '允许', '限制', '放行', '只能访问', 'HTTP'], pageName: ROUTE_HTTP_REQUEST_PAGE, tab: -1 },
  // 搜索结果条数（联网搜索页全局参数卡；keywords 加「联网」帮从联网域入手的用户命中）
  { title: SETTING_TITLE_SEARCH_COUNT, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_SEARCH_ENGINE, keywords: ['搜索', '联网', '条数', '结果', '条数上限', '返回', '数量', 'count', 'search'], pageName: ROUTE_SEARCH_ENGINE_PAGE, tab: -1 },
  // 联网请求超时（★ 与网络设置页「请求读超时」分语境：那条偏「读取」「模型」，本条偏
  //「联网」「搜索」；keywords 覆盖「太慢」等——从「为什么老失败/等太久」入手也能命中）
  { title: SETTING_TITLE_SEARCH_TIMEOUT, path: PATH_ROOT + ' > ' + SETTING_TITLE_TOOLS + ' > ' + SETTING_TITLE_SEARCH_ENGINE, keywords: ['超时', '联网', '搜索', '等待', '时间', '太慢', '超时时间', 'timeout'], pageName: ROUTE_SEARCH_ENGINE_PAGE, tab: -1 },
  // 网络设置（设置页「网络」组卡——全局网络请求设置页；条目顺序与 SettingsPage.settingGroups 同步）
  { title: SETTING_TITLE_NETWORK, path: PATH_ROOT, keywords: ['网络', '请求', '身份', '标识', 'User-Agent', 'UA', '伪装'], pageName: ROUTE_NETWORK_PAGE, tab: -1 },
  // Web 服务（「网络」组卡第二行——浏览器远程访问设置页；帮助条目同题经 HELP_SKIP 裁剪
  // 不重复注册）
  { title: SETTING_TITLE_WEB_SERVICE, path: PATH_ROOT, keywords: ['Web', 'web', '网页', '远程', '遥控', '浏览器', '局域网', '口令', '端口', '服务', '电脑'], pageName: ROUTE_WEB_SERVICE_PAGE, tab: -1 },
  // User-Agent 卡（网络设置页内容卡；帮助条目同题经 HELP_SKIP 裁剪不重复注册）
  { title: SETTING_TITLE_USER_AGENT, path: PATH_ROOT + ' > ' + SETTING_TITLE_NETWORK, keywords: ['用户代理', 'useragent', 'user agent', 'UA', '标识', '身份'], pageName: ROUTE_NETWORK_PAGE, tab: -1 },
  // 请求读超时卡（网络设置页第二卡；帮助条目同题经 HELP_SKIP 裁剪不重复注册）
  { title: SETTING_TITLE_READ_TIMEOUT, path: PATH_ROOT + ' > ' + SETTING_TITLE_NETWORK, keywords: ['读超时', '超时', '断开', '卡住', '等待', 'timeout'], pageName: ROUTE_NETWORK_PAGE, tab: -1 },
  // 代理卡（网络设置页第三卡；keywords 含「测试连接」〔卡内测试键〕与「SOCKS5」「绕过」
  //「账号密码」〔协议分段/绕过列表/认证〕入口词）
  { title: SETTING_TITLE_PROXY, path: PATH_ROOT + ' > ' + SETTING_TITLE_NETWORK, keywords: ['网络代理', '代理服务器', '直连', '端口', 'host', 'port', '测试连接', 'SOCKS5', 'socks5', 'socks', 'HTTP 代理', '绕过', '不走代理', '账号密码', '代理账号', '代理密码', '代理认证'], pageName: ROUTE_NETWORK_PAGE, tab: -1 },
  // 「偏好与外观」一级入口（重梳笔：keywords 收编原「外观显示」条目外观域词 + 旧名「偏好设置」
  // 兼容检索——外观三段拆三张三级页，页级条目在下方外观板块组）
  { title: SETTING_TITLE_PREFERENCES, path: PATH_ROOT, keywords: ['偏好', '设置', '偏好设置', '外观', '显示', '思考', '展开', '开关'], pageName: ROUTE_PREFERENCES_PAGE, tab: -1 },
  // ── 偏好与外观 · 外观板块（页级条目 = 背景 / 字体 两张三级页直达；原「外观显示」页级
  //    条目随页退役，外观域词收编进上方「偏好与外观」入口）──
  { title: SETTING_TITLE_TAB_BACKGROUND, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['背景', '壁纸', '墙纸', '主题', '外观'], pageName: ROUTE_PREF_BACKGROUND_PAGE, tab: -1 },
  // 侧栏对话形态开关行（首页布局双形态笔：开 = 首页直接对话、历史收左侧栏；词收「首页/
  // 布局/侧栏/抽屉/底栏/页签/切换」直达族 + 竞品俗称拼音。★ 2026-11-18 决明拍板开关行从
  // 「外观」卡迁入「应用与启动」页——路径末段与 pageName 随迁）
  { title: SETTING_TITLE_HOME_LAYOUT, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_APP_LAUNCH, keywords: ['侧栏', '侧边栏', '抽屉', '首页', '布局', '底栏', '页签', '切换', '形态', '对话', 'rikkahub', 'rik'], pageName: ROUTE_PREF_APP_LAUNCH_PAGE, tab: -1 },
  { title: SETTING_TITLE_TAB_FONT, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES, keywords: ['字体', '换字体', '外观', 'font'], pageName: ROUTE_PREF_FONT_PAGE, tab: -1 },
  // 正文字体（「字体」页选择组卡）
  { title: SETTING_TITLE_FONT_BODY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_FONT, keywords: ['字体', '正文字体', '衬线', '仿宋', '等宽', '宋体', '自定义字体', '字体导入', 'font'], pageName: ROUTE_PREF_FONT_PAGE, tab: -1 },
  { title: SETTING_TITLE_FONT_CODE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_FONT, keywords: ['字体', '代码字体', '代码块', '等宽', 'mono', 'JetBrains', '自定义字体', '字体导入', 'font'], pageName: ROUTE_PREF_FONT_PAGE, tab: -1 },
  // 字体生效范围分段行卡（「字体」页管理卡下方）
  { title: SETTING_TITLE_FONT_SESSION_ONLY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_FONT, keywords: ['字体', '范围', '会话页', '对话页', '全局', '应用级', '仅'], pageName: ROUTE_PREF_FONT_PAGE, tab: -1 },
  { title: SETTING_TITLE_USAGE_STATS, path: PATH_ROOT, keywords: ['用量', '统计', 'token', '消耗', 'tokens', '速度', 'tok', '生成速度'], pageName: ROUTE_USAGE_STATS_PAGE, tab: -1 },
  // 费用估计（价格配置入口在模型编辑页，关键词带「价格」直达本页后经空态引导指路）
  { title: SETTING_TITLE_COST_STATS, path: PATH_ROOT, keywords: ['费用', '成本', '价格', '花费', '多少钱', '消费', '金额', '花销', 'cost'], pageName: ROUTE_COST_STATS_PAGE, tab: -1 },
  // 数据与同步（keywords 含 'S3'——页内第三分段卡面名，匹配逻辑为关键词 includes）
  { title: SETTING_TITLE_DATA_SYNC, path: PATH_ROOT, keywords: ['数据', '同步', '备份', '导出', '导入', 'WebDAV', 'S3', '恢复'], pageName: ROUTE_DATA_SYNC_PAGE, tab: -1 },
  // 导入 DeepSeek 对话（数据与同步页入口卡三级页——DS 官方导出包解析为新会话，不覆盖现有）
  { title: SETTING_TITLE_DS_IMPORT, path: PATH_ROOT + ' > ' + SETTING_TITLE_DATA_SYNC, keywords: ['DeepSeek', 'deepseek', '导入', '对话', '迁移', '备份包', '导出包'], pageName: ROUTE_DS_HISTORY_IMPORT_PAGE, tab: -1 },
  // 存储管理（页内下级页与「更多」菜单的入口词都补在本条——匹配逻辑是关键词 includes，
  // 卡面名/菜单名不补词则按名搜索必落空：「会话附件/对话附件」「浏览器数据」「运行日志」
  //「快速清理/清空数据/清除数据/清空记忆」「清理附件/清理聊天附件」〔「更多」菜单〕。
  // ★ 工作区四组词已撤——文件工作区已成一级行卡自有条目，词留此处会双命中且旧落点失实）
  { title: SETTING_TITLE_STORAGE, path: PATH_ROOT, keywords: ['存储', '空间', '清理', '清理附件', '清理聊天附件', '缓存', '占用', '容量', '附件', '对话附件', '会话附件', '垃圾', '浏览器', '浏览器数据', '网页数据', '运行日志', '日志', 'cookie', 'storage', '快速清理', '清空数据', '清除数据', '清空记忆'], pageName: ROUTE_STORAGE_PAGE, tab: -1 },
  { title: SETTING_TITLE_MORE_INFO, path: PATH_ROOT, keywords: ['信息', '关于', '版本'], pageName: ROUTE_INFO_PAGE, tab: -1 },
  // ── 偏好与外观 · 背景页内容卡 ──
  { title: SETTING_TITLE_PICK_IMAGE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['背景', '壁纸', '图片', '相册', '裁剪', '模糊', '遮罩'], pageName: ROUTE_PREF_BACKGROUND_PAGE, tab: -1 },
  { title: SETTING_TITLE_EDIT_IMAGE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['裁剪', '模糊', '遮罩', '背景', '壁纸'], pageName: ROUTE_PREF_BACKGROUND_PAGE, tab: -1 },
  { title: SETTING_TITLE_RESTORE_DEFAULT, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['恢复', '默认', '背景', '壁纸'], pageName: ROUTE_PREF_BACKGROUND_PAGE, tab: -1 },
  // 背景生效范围分段行卡（「背景」页）
  { title: SETTING_TITLE_BG_SESSION_ONLY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_TAB_BACKGROUND, keywords: ['背景', '壁纸', '会话页', '对话页', '范围', '仅'], pageName: ROUTE_PREF_BACKGROUND_PAGE, tab: -1 },
  // ── 更多信息 · 关于域 ──
  { title: SETTING_TITLE_ABOUT, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['关于', '版本', '应用', '图标'], pageName: ROUTE_ABOUT_PAGE, tab: -1 },
  { title: SETTING_TITLE_VERSION_INFO, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_ABOUT, keywords: ['版本', '更新', '检测'], pageName: ROUTE_ABOUT_PAGE, tab: -1 },
  // （原「获取安装包」条目已随功能移除删除——公开签名 HAP 经该卡外传任何设备可直接侧载）
  // 权限信息/隐私政策（path 随入口迁移挂更多信息页一级，同反馈与建议条目口径）
  { title: SETTING_TITLE_PERMISSION, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['权限', '隐私', '网络', '访问'], pageName: ROUTE_PERMISSION_PAGE, tab: -1 },
  { title: SETTING_TITLE_PRIVACY_POLICY, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['隐私', '个人信息', '数据', '政策', '收集', '授权'], pageName: ROUTE_PRIVACY_POLICY_PAGE, tab: -1 },
  { title: SETTING_TITLE_AI_ASSIST, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_ABOUT, keywords: ['AI', '人工智能', '辅助', '开发', '声明', '名单', '工具', 'Agent'], pageName: ROUTE_AI_ASSIST_PAGE, tab: -1 },
  { title: SETTING_TITLE_OPEN_SOURCE, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO + ' > ' + SETTING_TITLE_ABOUT, keywords: ['开源', '鸣谢', '致谢', '第三方', '许可', '协议', 'Cube', 'MIT', '引用'], pageName: ROUTE_OPEN_SOURCE_PAGE, tab: -1 },
  // 反馈与建议（更多信息页行卡——反馈直达开发者）
  { title: SETTING_TITLE_FEEDBACK, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['反馈', '建议', '意见', '问题', '联系开发者', '提意见', 'MeoW'], pageName: ROUTE_FEEDBACK_PAGE, tab: -1 },
  // ── 更多信息 · 运行日志（keywords 含「卡顿」「无响应」「被杀」「终止」——用户描述这几类
  //    系统事件的实际用词，与页面区块名〔主线程卡顿/应用终止〕并不同词，不加则搜不到）──
  { title: SETTING_TITLE_RUN_LOG, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['日志', '运行', '错误', '记录', '崩溃', '异常', '排查', '卡顿', '无响应', '被杀', '终止', '性能'], pageName: ROUTE_LOG_PAGE, tab: -1 },
  // ── 更多信息 · 请求日志（HTTP 请求现场——请求头/请求体/响应码，排障「连不上 / 发不出 /
  // 用不了」；原「出站记录」条目退役，其关键词〔出站/审计/发过什么〕并入本行——按旧语境
  // 检索仍直达本页，检索入口不丢）──
  { title: SETTING_TITLE_REQ_LOG, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['日志', '请求', '记录', '接口', 'HTTP', '响应', '排查', '调试', '出站', '审计', '发过什么'], pageName: ROUTE_REQ_LOG_PAGE, tab: -1 },
  // ── 更多信息 · 帮助中心（更多信息页首张行卡——分板块功能与用法说明）──
  { title: SETTING_TITLE_HELP_CENTER, path: PATH_ROOT + ' > ' + SETTING_TITLE_MORE_INFO, keywords: ['帮助', '使用说明', '指南', '教程', '上手', '怎么用', '用法', 'FAQ', '说明'], pageName: ROUTE_HELP_CENTER_PAGE, tab: -1 },
  // ── 偏好与外观页（tab=-1，入口条目在上方一级入口组；两级化 + 重梳笔后各项 pageName 指各自
  //    下级页、面包屑〔设置 > 偏好与外观 > 页名〕——搜索命中直达对应页）──
  { title: SETTING_TITLE_THINK_EXPAND, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['思考', '思维链', '思考链', '展开', '收起', '折叠', '默认'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // 流式输出自动跟随开关
  { title: SETTING_TITLE_STREAM_FOLLOW, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['跟随', '流式', '自动', '滚动', '随动', '输出', 'follow', 'scroll'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // 会话加载动画开关（进会话加载期间消息区显示加载动画，默认开）
  { title: SETTING_TITLE_CHAT_LOADING_OVERLAY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['加载', '动画', '进度', '转圈', '空白', '等待', '进入会话', '会话页', 'loading'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // HTML 预览运行脚本开关（受限预览可执行 HTML 中的脚本，仅本地运行且无法联网，默认关）
  { title: SETTING_TITLE_PREVIEW_JS, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['脚本', '运行', '执行', '预览', '网页', 'javascript', 'js', 'html', '受限', '本地'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // 长代码块自动收起开关（生成结束的长代码块自动收起为前若干行，可点展开条查看全部，默认关）
  { title: SETTING_TITLE_CODE_AUTO_COLLAPSE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['代码', '代码块', '收起', '折叠', '展开', '长代码', '自动收起', '收起代码', 'collapse', 'code'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // 代码块行号开关（Markdown 代码块、HTML <pre> 与工具卡 diff 块逐行行号，重进会话后生效，默认开）
  { title: SETTING_TITLE_CODE_LINE_NUMBERS, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['代码', '代码块', '行号', '编号', '数字', 'line', 'number', 'linenumber', 'diff', 'html'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // 长消息进页收起开关（开 = 进会话时超长消息收起，关 = 全部展开并由加载动画承担等待）
  { title: SETTING_TITLE_LONG_MSG_COLLAPSE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['长消息', '长回复', '收起', '折叠', '展开', '展开全文', '占位', '进入会话', '进页', '加载', 'collapse', '长文'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  { title: SETTING_TITLE_ASSISTANT_BUBBLE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['气泡', '助手气泡', '气泡背景', '气泡底', '消息气泡', '贴边', '内距', '间距', 'bubble', 'assistant'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  { title: SETTING_TITLE_THINKING_SLIDER, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['思考', '档位', '滑轨', '滑块', '强度', '菜单', '模型'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // 消息内 HTML 直接渲染开关（HTML 块直接显示渲染结果，关闭显示源码，重进会话后生效，默认开）
  { title: SETTING_TITLE_HTML_BLOCK_RENDER, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_REPLY_DISPLAY, keywords: ['html', '渲染', '消息', '网页', '标签', '直接显示', '源码', 'render', 'web'], pageName: ROUTE_PREF_REPLY_DISPLAY_PAGE, tab: -1 },
  // （SVG 图形预览开关注册条目随开关退役删除——恒开，搜索项不再存在）
  // 自动重试（升级为独立设置页——总开关 + 重试参数四数字行 + 状态码与重试/停止关键字清单；
  // 面包屑与 pageName 随改挂新页）
  { title: SETTING_TITLE_AUTO_RETRY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND + ' > ' + SETTING_TITLE_AUTO_RETRY, keywords: ['重试', '自动重试', '网络', '断网', '异常', '失败', '重发', 'retry', '自动', '服务器', '退避', '倍率', '延迟', '等待', '状态码', '关键字', '次数'], pageName: ROUTE_PREF_AUTO_RETRY_PAGE, tab: -1 },
  // 粘贴长文本转文件开关（粘贴的文本达到阈值时转成文本附件）
  { title: SETTING_TITLE_PASTE_AS_FILE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['粘贴', '长文本', '附件', '剪贴板', '阈值', '文本'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 时间间隔提醒开关（对话间隔超阈值时发送组装插一条时间提醒）
  { title: SETTING_TITLE_TIME_REMINDER, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['时间', '间隔', '提醒', '时刻', '缓存'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 键盘发送开关
  { title: SETTING_TITLE_KEYBOARD_SEND, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['键盘', '发送', '换行', '回车', '键盘发送'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 输入框常驻展开开关
  { title: SETTING_TITLE_INPUT_EXPANDED, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['输入框', '展开', '收起', '工具栏', '常驻', '胶囊', '输入'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 图片链接作为图片发送开关（消息里的 Markdown 图链发送时自动下载转图随请求发给模型）
  { title: SETTING_TITLE_TEXT_IMAGE, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['图片链接', '图链', 'markdown', '图片', '链接', '发送'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 拍照保存到相册开关（拍照时照片是否同时存进系统相册，默认不保存；保存时机 = 拍照时刻，
  // 只影响「拍照」入口）
  { title: SETTING_TITLE_PHOTO_SAVE_GALLERY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['拍照', '照片', '相册', '图库', '保存', '相机', '存入', 'camera', 'photo', 'gallery', 'album'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 添加图片时编辑开关（拍照与相册选图后先进裁剪页，默认关；「系统文件」入口不受影响）
  { title: SETTING_TITLE_PHOTO_EDIT, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_INPUT_SEND, keywords: ['编辑', '裁剪', '拍照', '照片', '图片', '相机', '放大', '输入框', 'crop', 'photo', 'edit'], pageName: ROUTE_PREF_INPUT_SEND_PAGE, tab: -1 },
  // 会话页屏幕常亮开关
  { title: SETTING_TITLE_KEEP_SCREEN_ON, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_SESSION_READ, keywords: ['常亮', '亮屏', '亮着', '息屏', '熄屏', '锁屏', '不熄屏', 'keepScreenOn', '屏幕'], pageName: ROUTE_PREF_SESSION_READ_PAGE, tab: -1 },
  // 会话宫格视图开关（两列宫格 / 单列列表显示形态；keywords 覆盖用户对宫格排列的各类叫法）
  { title: SETTING_TITLE_SESSION_CARD_GRID, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_SESSION_READ, keywords: ['宫格', '视图', '宫格视图', '方块', '两列', '瀑布', '会话卡', '排列', '列表', '方块卡', '网格'], pageName: ROUTE_PREF_SESSION_READ_PAGE, tab: -1 },
  // 智感握姿跟随开关（会话列表悬浮新建键随左右手握持换边）
  { title: SETTING_TITLE_HOLDING_FOLLOW, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_SESSION_READ, keywords: ['智感握姿', '握姿', '握持', '左手', '右手', '换手', '悬浮键', '新建键', 'holdingFollow'], pageName: ROUTE_PREF_SESSION_READ_PAGE, tab: -1 },
  // 快捷新建键分段卡（★ 2026-10-30 两档化：页签栏旁 / 列表右下两档，两处快捷键互斥；
  // ★ 2026-10-31 三档化新增页签第四项档）
  { title: SETTING_TITLE_NEW_SESSION_ENTRY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_SESSION_READ, keywords: ['新建会话', '新建', '快捷', '加号', '圆键', '悬浮键', '页签栏', '页签第四项', '第四项', '右下角', 'newSession'], pageName: ROUTE_PREF_SESSION_READ_PAGE, tab: -1 },
  // 后台回复提醒开关（切后台是否保活生成并发回复通知）
  { title: SETTING_TITLE_BG_REPLY_NOTIFY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_SESSION_READ, keywords: ['后台', '后台回复', '回复', '通知', '提醒', '保活', '切后台', '后台运行', '通知栏', 'bgReplyNotify'], pageName: ROUTE_PREF_SESSION_READ_PAGE, tab: -1 },
  // 页签切换动画开关
  { title: SETTING_TITLE_TAB_SWITCH_ANIM, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_APP_LAUNCH, keywords: ['页签', '切换', '动画', '转场', '滑动', '横向', 'tab', '直达'], pageName: ROUTE_PREF_APP_LAUNCH_PAGE, tab: -1 },
  // 启动进入页面卡（冷启动默认进入新对话或会话列表）
  { title: SETTING_TITLE_LAUNCH_ENTRY, path: PATH_ROOT + ' > ' + SETTING_TITLE_PREFERENCES + ' > ' + SETTING_TITLE_PREF_APP_LAUNCH, keywords: ['启动', '打开', '进入', '默认', '新对话', '会话列表', '首页', '开机', 'launch'], pageName: ROUTE_PREF_APP_LAUNCH_PAGE, tab: -1 },
  // ── 功能模型页（入口条目在上方一级入口组）──
  { title: SETTING_TITLE_DEFAULT_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['默认模型', '默认对话模型', '兜底', '缺省', '回退', '指定', '模型'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 标题生成卡
  { title: SETTING_TITLE_TITLE_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['标题', '标题生成模型', '会话名', '自动命名', '命名', '摘要', '改名', '提示词', 'title'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 记忆提取卡（keywords 补旧名「记忆提取模型」兼容搜索）
  { title: SETTING_TITLE_MEMORY_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['记忆', '提取', '整理', '记忆模型', '记忆提取模型', '记忆整理', '沉淀', 'memory'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 记忆优化卡（keywords 补旧名「记忆优化模型」兼容搜索）
  { title: SETTING_TITLE_MEMORY_OPT_MODEL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['记忆', '优化', '去重', '合并', '改写', '润色', '整理', '记忆优化模型', 'memory'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 文字识别卡（三档段位名全在列，搜任一段名均可达；含「提示词」——识别要求可自定义）
  { title: SETTING_TITLE_OCR, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['文字识别', '识别', '系统识别', '内置识别', '模型识别', '离线', 'OCR', '扫描', '扫描件', '图片', '附件', '视觉', '引擎', '提示词'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 推荐问题卡（回复后追问推荐生成开关与模型）
  { title: SETTING_TITLE_SUGGEST, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['推荐', '推荐问题', '追问', '建议', 'followup', 'suggest'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 命令审批卡（工具调用确认链的审批模型配置）
  { title: SETTING_TITLE_APPROVAL, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['审批', '命令审批', '审批模型', '允许', '拒绝', '自动确认', '确认卡', 'approval'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  { title: SETTING_TITLE_FUNCTIONAL_THINKING, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['思考', '思考档位', '思维链', '推理', '深度思考', '档位', '功能模型', 'thinking'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 上下文压缩卡（会话上下文手动压缩的模型与提示词）
  { title: SETTING_TITLE_COMPRESS, path: PATH_ROOT + ' > ' + SETTING_TITLE_FUNCTIONAL_MODEL, keywords: ['压缩', '上下文压缩', '摘要', '总结', '压缩上下文', 'compress'], pageName: ROUTE_FUNCTIONAL_MODEL_PAGE, tab: -1 },
  // 记忆读取方式卡（自动注入默认 / 按需读取切换；页级「记忆」入口条目 keywords 不动）
  { title: SETTING_TITLE_MEMORY_READ_MODE, path: PATH_ROOT + ' > ' + SETTING_TITLE_MEMORY, keywords: ['按需', '检索', '工具', '自动注入'], pageName: ROUTE_MEMORY_PAGE, tab: -1 }
];

// 注册表总表 = 静态条目 + 帮助条目（帮助条目程序化生成排在尾部——搜索结果里帮助内容在
// 功能页之后）
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
//    注册 persistProp——坑17 时机；去重移头、截断上限，有界防内存/存储膨胀）──
export const SEARCH_HISTORY_KEY: string = 'settingSearchHistory';
// 上限 5 条（只留近 5 个）
export const MAX_SEARCH_HISTORY: number = 5;
// 搜索词长度上限（存储只留前 10 字——超长粘贴属误操作，截断后点击回填的也是短词，搜索
// 语义不受损；展示侧另有 maxWidth + 单行省略号双保险，见 SearchSections）
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

// ── 最近使用：用户最近打开过的设置项（搜索跳转记录），存 title 一维字符串数组（对象数组
//    禁止持久化）；展示时按 title 在注册表反查完整条目（title 全注册表唯一——注册表新建
//    条目时同样遵守）──
export const RECENT_USE_KEY: string = 'settingRecentUse';
// 上限 3 条（避免列表过长）
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
