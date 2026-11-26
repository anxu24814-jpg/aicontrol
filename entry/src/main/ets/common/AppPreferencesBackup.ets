// 备份分域：偏好键两分类表 + 备份凭据登记块 + preferences.json 编解码纯函数（自
// AppPreferences.ets 域级最小拆分迁出，方法体原样搬迁零行为变化）。
// 职责单句：本件是「哪些偏好随备份走」的唯一来源与 preferences.json 的编解码纯函数层，
// 消费方 = 导出/导入链（common/store/ExportImport.ets）与 assert-feature-domain 54 组门禁。
// 为何不能并入：备份清单与编解码是备份链专有的独立功能域，与主件「UI 偏好键叶子」职责
// 不同缝；common/ 下无其他备份域件可并入（反碎片：本件能一句话说清独立职责），故新开本件。
// 依赖方向（硬契约）：本件单向 import AppPreferences（引用键常量，那些常量保持 export 于主件
// 不动）——主件零 import 叶子契约必须保持，严禁 AppPreferences 反向 import 本件。
// 表内键名字面量（immersiveLevel 等）与字面量登记（prefHttpCredentialsCfg 等）的漂移由
// assert-feature-domain 54 组「全覆盖钉」兜住（其读源指本件）。
import { PREF_AUTO_RETRY_KEY, PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY,
  PREF_BG_REPLY_NOTIFY_KEY,
  PREF_BG_SESSION_ONLY_KEY, PREF_BODY_CARD_COLLAPSED_KEY,
  PREF_BROWSE_APPROVE_MODE_KEY, PREF_BROWSE_AUTO_APPROVE_KEY,
  PREF_CARD_ALPHA_LEVEL_KEY,
  PREF_CHAT_LOADING_OVERLAY_KEY, PREF_LONG_MSG_COLLAPSE_KEY, PREF_ASSISTANT_BUBBLE_KEY, PREF_CODE_AUTO_COLLAPSE_KEY,
  PREF_THINKING_SLIDER_KEY,
  PREF_CODE_LINE_NUMBERS_KEY,
  PREF_CODE_WORKBENCH_MODE_KEY, PREF_CODE_WORKBENCH_ENGINE_KEY, PREF_CTX_FACTOR_KEY, PREF_DATA_APPROVE_MODE_KEY,
  PREF_DS_DOC_SERVER_KEY, PREF_DS_OFFICIAL_WEB_KEY, PREF_DS_TITLE_MODE_KEY,
  PREF_DS_SAFETY_CHECK_KEY, PREF_DEFAULT_PERMISSION_MODE_KEY,
  PREF_HEADERS_CARD_COLLAPSED_KEY, PREF_HTML_BLOCK_RENDER_KEY, PREF_HTTP_APPROVE_MODE_KEY,
  PREF_HTTP_HOST_INTERVAL_MS_KEY, PREF_HTTP_TIMEOUT_CEILING_MS_KEY,
  PREF_HTTP_WRITE_AUTO_APPROVE_KEY, PREF_INPUT_EXPANDED_KEY, PREF_KEEP_SCREEN_ON_KEY,
  PREF_KEYBOARD_SEND_KEY, PREF_LAUNCH_NEW_CHAT_KEY, PREF_MERMAID_INLINE_KEY,
  PREF_NET_PROXY_ADDR_KEY,
  PREF_NET_PROXY_BYPASS_KEY, PREF_NET_PROXY_MODE_KEY, PREF_NET_PROXY_TYPE_KEY,
  PREF_NET_PROXY_USER_KEY, PREF_NET_READ_TIMEOUT_MIN_KEY, PREF_PASTE_AS_FILE_KEY,
  PREF_PASTE_AS_FILE_THRESHOLD_KEY, PREF_PHOTO_SAVE_GALLERY_KEY, PREF_PHOTO_EDIT_KEY, PREF_PREVIEW_JS_KEY, PREF_PRICE_CARD_COLLAPSED_KEY,
  PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY, PREF_SEARCH_ENGINE_KEY,
  PREF_SEARCH_FETCH_ENGINE_KEY,
  PREF_SEARCH_RESULT_COUNT_KEY, PREF_SEARCH_TIMEOUT_SEC_KEY,
  PREF_HOLDING_FOLLOW_KEY, PREF_NEW_SESSION_ENTRY_KEY, PREF_SESSION_CARD_GRID_KEY,
  PREF_STREAM_FOLLOW_KEY, PREF_SVG_PREVIEW_KEY, PREF_TAB_SWITCH_ANIM_KEY,
  PREF_TEXT_IMAGE_FETCH_KEY, PREF_THINK_EXPAND_KEY, PREF_TIME_REMINDER_KEY,
  PREF_TIME_REMINDER_MINUTES_KEY, PREF_TOOL_STEP_LIMIT_KEY, PREF_USER_AGENT_KEY,
  PREF_WORKSPACE_SORT_KEY, PREF_HOME_LAYOUT_KEY, PREF_LAST_CONV_ID_KEY } from './AppPreferences';
// 自动重试配置 JSON 键：重试判据参数用户可配，定义与解析单源在 AppPreferencesRetry.ets
import { PREF_AUTO_RETRY_CFG_KEY } from './AppPreferencesRetry';
// 消息字体键（当前三键 + 迁移过渡只读四键〔见排除表〕）：定义在 common/ChatFont.ets
//（零 import 叶子件，与本件依赖方向同向——两者都不反向引任何 store 域）
import { PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY, PREF_FONT_LIB_KEY,
  PREF_FONT_SESSION_ONLY_KEY, PREF_FONT_BODY_PATH_KEY, PREF_FONT_BODY_NAME_KEY,
  PREF_FONT_CODE_PATH_KEY, PREF_FONT_CODE_NAME_KEY } from './ChatFont';

// ── 备份分域：偏好键两分类表 ──
// ★ 两张表是「哪些偏好随备份走」的**唯一来源**：导出侧按 BACKUP_PREF_KEYS 收集，
// 导入侧按同名清单回写（两处都读本表，禁散落判断）；assert-feature-domain 54 组「全覆盖钉」
// 扫 EntryAbility 全部 persistProp 键名，要求每个键恰好落在两表之一（数量与并集逐个比对）
// ——新增偏好漏登记即断言 FAIL，靠门禁不靠记性。
// 键名口径：主件（AppPreferences.ets）定义的键直接引用常量；定义在别处（沉浸/图片编辑/
// 设置搜索/会话搜索/服务商/助手/记忆/标题/seed 标记域）的用字符串字面量并在行尾注明单一
// 来源文件——零 import 叶子契约在主件（它是被 UI 页面与 node 断言广泛消费的叶子模块，
// 引 store 域会把 rdb 与 SDK 依赖拖进每个消费者），字面量漂移由上述全覆盖钉兜住（改名 → 钉红）。
// 入表判据 = 用户偏好（显示/行为/交互/安全/配置五类）随备份走，换机恢复后偏好保留；
// 缺省值真源一律在 persistProp 注册侧。逐键入表理由见各键行尾注释；计数沿革入
// docs/变更记录.md，不入本文件。

// 随备份携带的偏好（123 键；分类依据 = 方案 §2.1 三分法；★ 2026-11-25 思考档位滑轨笔加 prefThinkingSlider 一键自 122 加 1（滑轨/菜单形态是用户显示偏好，换机恢复后形态保留；缺省 true 真源在 persistProp 注册侧）；★ 2026-11-17 整体退役加密会话笔 prefBiometricFace 出表自 123 减 1；★ 首页布局双形态笔加 prefHomeLayout 与 prefLastConvId 两键自 121 加 2；★ DS 全家桶二期 S2 加 prefDsTitleMode 与 prefDsSafetyCheck 两键自 119 加 2（官方标题三态是用户行为偏好、内容安全审核开关是合规选择，换机恢复后选择态保留）；★ DS 全家桶接入批 S1 加 prefDsOfficialWeb 与 prefDsDocServer 两键自 117 加 2；★ 2026-11-12 偏好开关批十键出表自 127 减 10；★ 2026-11-11 域名确认档退役笔自 129 减 2）
export const BACKUP_PREF_KEYS: string[] = [
  // 沉浸与外观（3）——ImageEditUtil.ets 三键（★ contentFallback / immersiveLevel 已出表
  // 进排除表——能力位/固定档，无用户可调偏好，见排除表同键条）
  'editBlurPct', 'editMaskPct', 'editCropState',
  // 功能模型绑定（17）——ProviderDb.ets 十键 + TitleGen.ets 一键 + AssistantDb.ets 一键
  // + OcrVisionApi.ets 一键（ocr 五键 + suggest 四键 = 字面量，单一来源见行尾）。
  // ★ ocrEngine 现为只读兜底但**仍随备份走**：旧备份恢复后 resolveOcrEngine 还要用它推导，
  // 删了会让老用户升级态丢失
  'defaultProviderId', 'defaultModelId', 'titleProviderId', 'titleModelId', 'titlePrompt',
  // +titleEnabled——标题生成总开关是用户行为偏好（关 = 不再自动起名），随备份走
  'titleEnabled',
  // ocrPrompt 单一来源 OcrVisionApi.ets；suggestPrompt 单一来源 SuggestGen.ets——与
  // titlePrompt 同语义同随备份；suggest 三模型键单一来源 ProviderDb.ets
  'activeAssistantId', 'ocrEnabled', 'ocrEngine', 'ocrPreferSystem', 'ocrProviderId', 'ocrModelId',
  'ocrPrompt',
  'suggestEnabled', 'suggestProviderId', 'suggestModelId', 'suggestPrompt',
  // 命令审批（4）——ProviderDb.ets 两键 + ApprovalGate.ets 一键（approvalPrompt 第八槽定制键，
  // '' = 未定制 = 闸回退内置；approvalEnabled 总开关缺省 true）。前两键行史墓碑：曾加
  // approvalThinking 思考档位键，随功能整体退役出表——键已无任何读写点，不出现在任何一处
  'approvalProviderId', 'approvalModelId', 'approvalPrompt', 'approvalEnabled',
  // 功能任务思考档位（1）——八条功能模型小任务链共用的全局思考档位，缺省 '' = 不干预；
  // 键名字面量单一来源 ProviderDb.ets
  'functionalThinking',
  // 上下文压缩（3）——CompressGen.ets 三键：模型两键与提示词定制键都是用户配置，随备份走
  //（未配置 = 回退当前会话模型，恢复后语义不变）
  'compressProviderId', 'compressModelId', 'compressPrompt',
  // 通用偏好（64）——本文件键。逐键入表理由见各键行尾注释（显示/行为/安全偏好随备份走，
  // 换机恢复后偏好保留；缺省值真源一律在 persistProp 注册侧）。★ 退役出表墓碑：
  // prefStreamEngine（随流式引擎开关整体退役）、PREF_CHAT_PRELOAD_KEY（会话触摸预载整件
  // 退役）——键已不再注册，旧备份携带由导入侧白名单自然忽略
  PREF_THINK_EXPAND_KEY, PREF_KEYBOARD_SEND_KEY,
  // 消息内 HTML 块是否直接渲染——用户显示偏好随备份走（缺省 true 真源在 persistProp 注册侧）
  PREF_HTML_BLOCK_RENDER_KEY,
  // 生成结束的长代码块是否自动收起为前若干行——用户显示偏好随备份走（缺省 false）
  PREF_CODE_AUTO_COLLAPSE_KEY,
  // 代码块（Markdown / HTML <pre> / 工具卡 diff）是否逐行显示行号——用户显示偏好随备份走
  //（缺省 true）
  PREF_CODE_LINE_NUMBERS_KEY,
  // 受限预览是否可执行输入 HTML 的脚本（无桥、无网络、无文件权限）——用户安全偏好，
  // 显式知情开启，随备份走（缺省 false）
  PREF_PREVIEW_JS_KEY,
  // 会话加载期是否显示加载蒙层——用户显示偏好随备份走（缺省 true）；
  // 进页是否收起超长消息——用户显示偏好随备份走（缺省 true）
  PREF_CHAT_LOADING_OVERLAY_KEY, PREF_LONG_MSG_COLLAPSE_KEY,
  // 助手回复是否带气泡底色与内距——用户显示偏好随备份走（缺省 true）
  PREF_ASSISTANT_BUBBLE_KEY,
  // 思考档位选择用滑轨面板还是菜单——用户显示偏好随备份走（缺省 true = 滑轨；
  // ★ 注意不是能力位：两形态功能等价，仅交互形态不同，故随备份而非进排除表）
  PREF_THINKING_SLIDER_KEY,
  // ```svg / 验根为 svg 的 ```xml 代码块是否给受限预览入口——用户显示偏好随备份走（缺省 true）
  PREF_SVG_PREVIEW_KEY,
  PREF_STREAM_FOLLOW_KEY, PREF_MERMAID_INLINE_KEY, PREF_KEEP_SCREEN_ON_KEY,
  PREF_SESSION_CARD_GRID_KEY,
  // 会话列表右下悬浮新建键是否随左右手握持换边——用户交互偏好随备份走（缺省 true）
  PREF_HOLDING_FOLLOW_KEY,
  // 快捷新建键两档选择（★ 2026-10-30 两档化：页签栏旁圆键 / 列表右下悬浮键，原 'off' 关闭档
  // 退役）——用户交互偏好随备份走（缺省 'tabBar'；备份里的存量 'off' 值读侧经
  // resolveNewSessionEntry 归一收编为默认档）
  PREF_NEW_SESSION_ENTRY_KEY,
  // 首页布局形态（'tabs' 底栏页签默认 / 'drawer' 侧栏对话）——用户外观偏好随备份走
  //（方案-首页布局双形态；缺省 'tabs'）
  PREF_HOME_LAYOUT_KEY,
  // 上次打开的会话 id——侧栏形态冷启动落点承接，恢复后落上次会话（缺省 ''）
  PREF_LAST_CONV_ID_KEY,
  // 切后台时是否保活生成并发送回复通知——用户行为偏好随备份走（缺省 false）
  PREF_BG_REPLY_NOTIFY_KEY,
  // 输入框常态形态开关——用户显示偏好随备份走
  PREF_INPUT_EXPANDED_KEY,
  // 消息图链是否转图发送——用户行为偏好随备份走（缺省按文本发送）
  PREF_TEXT_IMAGE_FETCH_KEY,
  // 会话内拍照时照片是否同时存进系统相册——用户行为偏好随备份走（缺省 false）
  PREF_PHOTO_SAVE_GALLERY_KEY,
  // 拍照与相册选图后是否先进裁剪页——用户行为偏好随备份走（缺省 false = 直接入列）
  PREF_PHOTO_EDIT_KEY,
  // 文件工作区列表排序方式——用户显示偏好随备份走（缺省 'custom'）
  PREF_WORKSPACE_SORT_KEY,
  // 端侧代码工作台档位——用户安全偏好随备份走（缺省标准档）。★ 同族墓碑：原总开关
  // PREF_CODE_WORKBENCH_KEY 已退役出表——可用性全权随助手级「脚本工作台」卡〔assistants.tools
  // 清单随助手备份走，不走本表〕；旧备份若带该键，导入按白名单口径自然忽略
  PREF_CODE_WORKBENCH_MODE_KEY,
  // 脚本引擎三态键——用户安全偏好随备份走（缺省 'auto'；定义在 AppPreferences.ets）
  PREF_CODE_WORKBENCH_ENGINE_KEY,
  // 网络异常时是否自动退避重发——用户行为偏好随备份走（非本机残留）
  PREF_AUTO_RETRY_KEY,
  // 自动重试判据参数（状态码集合 / 重试与停止词表 / 退避四参数）用户可配，配置随备份走
  //（总开关仍走上面的旧布尔键）
  PREF_AUTO_RETRY_CFG_KEY,
  PREF_BG_SESSION_ONLY_KEY, PREF_TAB_SWITCH_ANIM_KEY,
  // 卡底透明度档位（0~4，L4 不透明默认）——用户显示偏好随备份走（阶梯表单源 =
  // Theme.ets CARD_ALPHA_* 双表）
  PREF_CARD_ALPHA_LEVEL_KEY,
  PREF_LAUNCH_NEW_CHAT_KEY, PREF_PRICE_CARD_COLLAPSED_KEY, PREF_CTX_FACTOR_KEY,
  // 服务商编辑页两卡与余额请求头卡收放——纯界面展示偏好，随备份走（同一族键，缺省 false）
  PREF_HEADERS_CARD_COLLAPSED_KEY, PREF_BODY_CARD_COLLAPSED_KEY,
  PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY,
  // ★ 确认档位三态（每次确认 / 先问审批模型 / 一律放行）——用户安全偏好随备份走；
  // 旧布尔键 PREF_BROWSE_AUTO_APPROVE_KEY / PREF_HTTP_WRITE_AUTO_APPROVE_KEY **仍留在表内**
  //（退为只读兜底：新键未写的备份恢复后靠它推导，删了老用户档位态即丢失）
  PREF_BROWSE_APPROVE_MODE_KEY, PREF_HTTP_APPROVE_MODE_KEY,
  // 数据管理操作（记忆 / 知识库 / 提示词 / 功能模型五工具）确认档——用户安全偏好随备份走
  //（本域无旧布尔键，缺省恒中间档）
  PREF_DATA_APPROVE_MODE_KEY,
  PREF_BROWSE_AUTO_APPROVE_KEY,
  // HTTP 写操作确认档——用户安全偏好随备份走（与上一行 browse 确认档同款口径）
  PREF_HTTP_WRITE_AUTO_APPROVE_KEY,
  // 会话权限模式应用默认档（2026-11-09 真完全权限笔）：用户安全偏好随备份走。
  // 会话覆盖键 chatPermissionMode 只存内存，刻意不入表（不跨会话、不跨设备继承）。
  PREF_DEFAULT_PERMISSION_MODE_KEY,
  // 粘贴转附件开关与长度阈值——用户行为偏好随备份走
  PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY,
  // 时间间隔提醒的开关与阈值——用户行为偏好随备份走
  PREF_TIME_REMINDER_KEY, PREF_TIME_REMINDER_MINUTES_KEY,
  // 请求身份设置（全局 UA）——用户偏好随备份走（换设备恢复后身份设置保留）
  PREF_USER_AGENT_KEY,
  // 读超时档位与代理三档设置——用户偏好随备份走（换设备恢复后网络设置保留，与 UA 同口径）
  PREF_NET_READ_TIMEOUT_MIN_KEY, PREF_NET_PROXY_MODE_KEY, PREF_NET_PROXY_ADDR_KEY,
  // 协议类型、认证账号与绕过列表——用户偏好随备份走。★ 代理密码刻意不在表内——只进
  // Asset 见凭据登记块 #5，备份明文不含密码，恢复后重填
  PREF_NET_PROXY_TYPE_KEY, PREF_NET_PROXY_USER_KEY, PREF_NET_PROXY_BYPASS_KEY,
  // 轮数上限与搜索条数（自 assistants 两列迁为全局偏好键）——用户行为偏好随备份走
  PREF_TOOL_STEP_LIMIT_KEY, PREF_SEARCH_RESULT_COUNT_KEY,
  // 联网请求超时（同属联网域运行参数，与上方两键同批）——用户行为偏好随备份走
  PREF_SEARCH_TIMEOUT_SEC_KEY,
  // HTTP 工具超时上限档——用户行为偏好随备份走（缺省 1 分钟）
  PREF_HTTP_TIMEOUT_CEILING_MS_KEY,
  // HTTP 工具同域请求间隔档——用户行为偏好随备份走（缺省 1 秒）
  PREF_HTTP_HOST_INTERVAL_MS_KEY,
  // 消息字体三键（定义在 common/ChatFont.ets）：正文与代码的选择值是用户显示偏好，字体库
  // JSON 是导入资产的登记。★ 边界：字体文件本身不随备份——恢复后文件不在本机，启动库
  // 校验剔除缺失项、选中值经 resolve 自动回默认档（ChatFontLoader 口径）
  PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY, PREF_FONT_LIB_KEY,
  // 字体范围偏好（true = 仅会话页默认 / false = 正文档全局），随备份走——全局态换机后由
  // 启动链 applyAppFontOnLaunch 重发应用级槽位，与选择键恢复同一时机
  PREF_FONT_SESSION_ONLY_KEY,
  // 记忆（10）——MemoryGen.ets 六键 + MemoryOpt.ets 三键 + MemoryImport.ets 一键
  //（memoryReadMode 键名字面量单一来源 MemoryGen.ets；memoryImportPrompt 单一来源
  // MemoryImport.ets——导出侧提示词是常量不进键表，它不给用户编辑；各提示词定制键与
  // titlePrompt 同语义同随备份）
  'memoryEnabled', 'memoryAutoSink', 'memoryProvider', 'memoryModel', 'memoryPrompt',
  'memoryReadMode',
  'memoryOptProvider', 'memoryOptModel', 'memoryOptPrompt',
  'memoryImportPrompt',
  // 主动消息（4）——ProactiveConfig.ets 四键（四键常量与缺省值单源该叶子），设置随备份走。
  // ★ 发送时刻数组 proactiveSentAt 不在此表——本机时间线痕迹进下方排除表
  'proactiveEnabled', 'proactiveIntervalHours', 'proactiveDailyLimit', 'proactiveQuietMaxMinutes',
  // 联网搜索（4）——本文件四键（★ 总开关键已随控制面撤除退役出表——无值可迁；
  // 引擎明文不随之走，见下方凭据登记 #2）
  PREF_SEARCH_ENGINE_KEY,
  PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY,
  // 抓取方式选择（本地 / 引擎）——用户行为偏好随备份走（缺省 'local'）
  PREF_SEARCH_FETCH_ENGINE_KEY,
  // DeepSeek 服务商（4）——官方联网档偏好〔代决 1 默认走官方搜索，改选自带引擎的会话级
  // 状态随备份〕与文档服务端解析开关〔拍板 8 带开关不默认自动〕两键，DS 全家桶接入批 S1
  // 新域。用户行为偏好随备份走（换机恢复后选择态保留；缺省 true / false 真源在 persistProp
  // 注册侧）
  PREF_DS_OFFICIAL_WEB_KEY, PREF_DS_DOC_SERVER_KEY,
  // 二期两键（2026-11-14）：标题三态是用户行为偏好、内容安全审核是合规选择，换机恢复后
  // 选择态保留；缺省 'first' / false 真源在 persistProp 注册侧
  PREF_DS_TITLE_MODE_KEY, PREF_DS_SAFETY_CHECK_KEY,
  // HTTP 凭据与域名准入（6）——凭据名称清单（owner → [{id,name,hasValue}]）随备份
  // 走（用户配置非本机痕迹）；值明文恒不在偏好（只进 Asset，凭据登记 #6——含密钥档连值
  // 一起导出、普通备份只带名称清单）。域名准入白名单是用户安全偏好，
  // 随备份走（域名本身非秘密——同域请求在请求日志里本就可见）。★ 2026-11-11 域名确认档
  // 退役笔：prefHttpDomainPolicies 与 prefHttpDomainCardCollapsed 出表（键不再读写，登记
  // 留着即幽灵项，照联网搜索总开关退役笔口径）。★ 以下 HTTP 域键已迁
  // common/AppPreferencesHttp.ets，本文件零 import 叶子契约不动，故以字面量登记
  //（同本表别处字面量键同族先例；改名即 54 组钉红）
  'prefHttpCredentialsCfg',
  'prefHttpAllowedHosts',
  // HTTP 请求页准入卡收放——纯界面展示偏好随备份走（同 prefPriceCardCollapsed 口径，
  // 缺省 false；定义同迁 AppPreferencesHttp.ets，字面量登记理由同上）
  'prefHttpAllowlistCardCollapsed',
  // 脚本联网预授权域名（助手级清单）——用户安全偏好随备份走（域名非秘密，理由同上；
  // 缺省 ''；定义在 AppPreferencesHttp.ets，字面量登记理由同上）
  'prefCodeHttpHosts',
  // 脚本写请求授权（★ 执行中决明改向 = 全局单开关布尔，不按助手区分）——用户安全偏好，
  // 随备份走（缺省 false = 只放行 GET；定义在 AppPreferencesHttp.ets，字面量登记理由同上）
  'prefCodeHttpWrite',
  // 脚本联网域名请求模式（allowlist 缺省 / any）——用户安全偏好随备份走（缺省 'allowlist'；
  // 定义在 AppPreferencesHttp.ets，字面量登记理由同上）
  'prefCodeHttpHostMode',
  // Web 服务（3）——AppPreferencesWeb.ets 三键：服务开关与端口是用户配置随备份走（开关
  // 缺省 false = kill-switch）；仅本机档是调试/进阶偏好随备份走。★ 口令键
  // prefWebServicePasscode 刻意不在本段——口令类敏感值不随备份走，见排除表同键条；
  // 三键定义在 AppPreferencesHttp 同族域拆分件，字面量登记理由同上
  'prefWebServiceEnable', 'prefWebServicePort', 'prefWebServiceLoopbackOnly'
];

// 不随备份携带的偏好（20 键；排除理由逐键见下方分组注释，计数沿革入 docs/变更记录.md）
export const BACKUP_EXCLUDED_PREF_KEYS: string[] = [
  // seed 代数标记与待并入登记三键（AssistantDb.ets / ProviderPresetSeed.ets /
  // SkillBuiltinDefs.ets）：本机安装态标记而非用户设置——带进备份会让换机/覆盖导入后
  //「自以为已 seed 而库里没有对应数据」，预置卡与内置技能代数的判断错乱（复活循环坑同族）；
  // skill_builtin_pending 为「待并入登记」，带进备份会把别的机器上没并完的内置件当本机待办
  // 带过来（★ console_tools_seeded 已随控制台合并退役出表——键不再读写，登记留着即幽灵项）
  'provider_presets_seeded', 'skill_builtin_seeded',
  'skill_builtin_pending',
  // 使用痕迹四键（SettingSearch.ets / SessionSearch.ets）：搜过什么、点过什么是本机操作
  // 残留，换机带过去只会让人困惑
  'settingSearchHistory', 'settingRecentUse', 'sessionSearchHistory', 'sessionRecentConv',
  // 壁纸路径（EntryAbility 字面量键）：路径指向本机沙箱文件，而壁纸文件本身不随包——
  // 带路径不带文件 = 恢复后一排加载不出的背景（附件边界同源口径）。决明拍板排除；
  // 将来要连壁纸一起迁，须另立「壁纸文件随包」子任务
  'pageBg',
  // 主动消息发送时刻滚动数组（ProactiveGen.ets）：本机发送时间线痕迹，与使用痕迹四键
  // 同族——跨机时间线无意义。恢复旧备份后冷却归零可能当轮多发一条，由每日上限守卫兜住，
  // 可接受
  'proactiveSentAt',
  // 主动消息未读会话：本机未读痕迹，与 proactiveSentAt 同族——换机带着「别的机器上未读」
  // 的红点无意义；键名字面量，单一来源 AppBroadcastKeys.ets
  'proactiveUnreadConv',
  // 请求日志开关（'prefReqLog'）：诊断开关而非用户设置。开着时会记录含对话内容与请求头
  // 的请求快照——随备份携带会让换机恢复后**静默开启**一个记录敏感内容的开关（恢复流程
  // 不提醒用户复核），故刻意排除；代价仅换机后手动重开一次。键名字面量，单一来源
  // ReqLog.ets（该件刻意零 import，见其头注释）
  'prefReqLog',
  // 内容区能力位（ImmersiveLevel.ets）：该键无用户入口、值恒 true（EntryAbility 在
  // loadContent 回调内做存量归正），**无常量值可携带**；★ 排除的实质理由是它会绕开归正
  // ——导入回写在启动之后跑，旧备份里存着 false，恢复即把恒真不变量打破：恢复后到下次
  // 冷启动之间内容区件退回旧光感材质态（该态在 API 26 内容区不生效 ⇒ 形态退化），而用户
  // 已无入口改回。键名字面量，单一来源 ImmersiveLevel.ets
  'contentFallback',
  // 沉浸光感固定档能力位（ImmersiveLevel.ets）：档位固定强档（IMMERSIVE_LEVEL_FIXED = 4）、
  // 无用户调整入口，**无常量偏好可携带**；排除的实质理由同上一键——旧备份里存着 0/2/3，
  // 恢复即把固定不变量打破，而用户已无入口改回强档。键名字面量，单一来源 ImmersiveLevel.ets
  'immersiveLevel',
  // HTTP 长任务句柄持久化镜像（'prefHttpTaskMirror'）：进程瞬时态——只登记运行中后台任务
  // 的最小身份字段（终态即清），换机/恢复后这些任务的真实下场就是「连接已死」，携带过去
  // 只会让恢复侧把死任务当在途（lost 语义靠重启恢复侧判定，不靠备份迁移）。键名字面量，
  // 单一来源 AppPreferencesHttp.ets
  'prefHttpTaskMirror',
  // 消息字体 v1 退役四键（common/ChatFont.ets）：迁移过渡期只读素材（启动迁移把旧单槽数据
  // 并入共享字体库后随即清空，本机一次性消费）——不随备份走：导入侧只认 BACKUP_PREF_KEYS
  // 白名单，旧备份里的这四键不会被写入本机；旧版自定义字体文件本就不随备份，恢复后无自
  // 定义字体可用属预期。下版本随迁移代码一并删除
  PREF_FONT_BODY_PATH_KEY, PREF_FONT_BODY_NAME_KEY,
  PREF_FONT_CODE_PATH_KEY, PREF_FONT_CODE_NAME_KEY,
  // Web 服务访问口令（'prefWebServicePasscode'）：口令类敏感值不随备份走——换机/恢复后
  // 键落缺省 ''，设置侧首开启自动重新生成 6 位数字码，新口令即新 token 族（token 由口令
  // 派生），不携带旧口令跨机；代价仅换机后重新输一次配对码。键名字面量，单一来源
  // AppPreferencesWeb.ets
  'prefWebServicePasscode',
  // 首启隐私政策同意态（'prefPrivacyAgreed'）：同意是设备侧法律状态而非用户偏好——换机/
  // 恢复后必须重新征得同意（官方口径「用户同意隐私政策前不应有任何调用权限 API 的行为」；
  // 带进备份会让新设备跳过首启弹窗，等于替用户预设同意）。键名字面量，单一来源
  // PrivacyConsent.ets（该件零 import 叶子）
  'prefPrivacyAgreed',
  // 会话权限模式按会话表（'prefChatPermissionModes'）：值 = 会话 id → 谨慎/标准/完全权限
  // 的 JSON 表，重启后按会话恢复。刻意不随备份走：①键是本地会话 id，换机后会话 id 不同
  // 即成死条目；②完全权限是高危档，跨设备静默复现等于替新设备放宽确认策略。代价 = 换机后
  // 各会话回默认档。键名字面量，单一来源 AppPreferences.ets
  'prefChatPermissionModes'
];

// ── 备份凭据登记块（★ 新增凭据必须在此登记——导出侧两档逻辑与本块同源）──
// 本项目凭据只有七处，档位归属如下（改任何一处都要同步本节）：
// 1. 服务商 API 密钥池（Asset 别名 aic.p.<providerId>/<keyId>，KeyStore.ets）
//    → 含密钥档随加密件进包；不含密钥档明文不进包（provider_keys 行照常进包，
//      同设备恢复靠 Asset 明文天然可用，换设备恢复后重填）
// 2. 搜索引擎 API 密钥（Asset 别名 aic.se.<engineId>，KeyStore.ets）
//    → 同 #1（两域必须对称）
// 3. 余额密钥 / 余额请求头 / 自定义请求头（providers 三个明文列 balance_key /
//    balance_headers / headers，建表 SQL 在 ChatDbMigrate.ets）
//    → ★ 两个档位的 providers.json **都**置空（明文只进加密件）；含密钥档由加密件回填，
//      不含密钥档导入后这三列为空（余额查询失效 = 验收项）
// 4. WebDAV 应用专用密码（Asset 别名 aic.dav.password，KeyStore.ets）
//    → ★ 恒不进包（任何档皆否）：通道凭据自指死锁——它随包传到 WebDAV 后，恢复要先从
//      WebDAV 下载该包，而下载正需要它，故必然只能留在本机、换机重填一次
// 5. 代理账号密码（Asset 别名 aic.proxy.password，KeyStore.ets；决明拍板「Asset 加密存储」）
//    → ★ 恒不进包（任何档皆否，同 #4 口径）：随备份走的只有代理地址与认证账号
//     （PREF_NET_PROXY_USER_KEY 明文偏好——账号无密码不成凭据，单独泄露无认证面，故
//      不设加密件档），密码换机重填一次
// 6. HTTP 请求凭据（Asset 别名 aic.h.<owner>/<credId>，KeyStore.ets；决明拍板「同搜索
//    引擎 key 全档」）
//    → 同 #1/#2 对称：含密钥档随加密件连值进包（换机无缝恢复）；不含密钥档明文不进包
//     （PREF_HTTP_CREDENTIALS_CFG_KEY 名称清单照常随包——恢复后清单在、值重填）
// 7. S3 对象存储 SecretAccessKey（Asset 别名 aic.s3.secret，KeyStore.ets）
//    → ★ 恒不进包（任何档皆否，同 #4 口径）：备份通道凭据自指死锁——它随包传到 S3 后，
//      恢复要先从 S3 下载该包，而下载正需要它，故只能留在本机、换机重填一次；
//      Access Key ID 无独立认证面（无 Secret 不成凭据，同 #5 代理账号口径）随 s3_config
//      非敏感偏好——s3_config 与 webdav_config 同为页面自持独立偏好文件，不进本表

// ── preferences.json 编解码纯函数（导出写 / 导入读；node 断言直跑本文件）──
// 条目形态 {key, type, value}：type 显式携带是防 JSON 弱类型把 0 与 false 混淆（照 Cube
// collectPreferences 先例）。★ 类型四值 = string|number|boolean 三值 + array——本项目的
// 编辑参数记忆（editCropState）与启用引擎清单（prefSearchEnabledEngines）都是持久化数组，
// 三值形态装不下（数组只认一维纯 string / 纯 number：对象数组禁持久化）。
export interface PrefBackupItem {
  key: string;
  type: string; // 'string' | 'number' | 'boolean' | 'array'
  value: Object;
}

// 值类型判定（'' = 不支持的类型 = 导出跳过、导入拒收）
export function classifyPrefValue(v: Object | undefined): string {
  if (typeof v === 'string') {
    return 'string';
  }
  if (typeof v === 'number') {
    return 'number';
  }
  if (typeof v === 'boolean') {
    return 'boolean';
  }
  if (Array.isArray(v)) {
    const arr: Object[] = v as Object[];
    const allString: boolean = arr.every((x: Object): boolean => typeof x === 'string');
    const allNumber: boolean = arr.every((x: Object): boolean => typeof x === 'number');
    return allString || allNumber ? 'array' : '';
  }
  return '';
}

// 单键 → 备份条目（不支持类型返回 null——跳过该键不写半成品）
export function toPrefBackupItem(key: string, v: Object | undefined): PrefBackupItem | null {
  const type: string = classifyPrefValue(v);
  if (type === '') {
    return null;
  }
  return { key: key, type: type, value: v as Object };
}

// 收集当前偏好为备份条目（导出侧调用；未注册键与不支持类型自动跳过）
export function collectBackupPrefItems(): PrefBackupItem[] {
  const items: PrefBackupItem[] = [];
  for (const key of BACKUP_PREF_KEYS) {
    const item: PrefBackupItem | null = toPrefBackupItem(key, AppStorage.get<Object>(key));
    if (item !== null) {
      items.push(item);
    }
  }
  return items;
}

export function serializePrefBackup(items: PrefBackupItem[]): string {
  return JSON.stringify(items);
}

// 解析（格式容错：坏 JSON / 非数组 / 元素残缺 / type 与 value 对不上——一律丢弃该条不抛错；
// 分域文件不存在才由调用方按「老备份缺失容忍」跳过）
export function parsePrefBackup(json: string): PrefBackupItem[] {
  const items: PrefBackupItem[] = [];
  if (json === '') {
    return items;
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(json) as Object;
  } catch (e) {
    return items;
  }
  if (!Array.isArray(parsed)) {
    return items;
  }
  for (const raw of parsed as Object[]) {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      continue;
    }
    const rec: Record<string, Object> = raw as Record<string, Object>;
    const key: Object | undefined = rec['key'];
    const type: Object | undefined = rec['type'];
    const value: Object | undefined = rec['value'];
    if (typeof key !== 'string' || typeof type !== 'string' || value === undefined) {
      continue;
    }
    if (classifyPrefValue(value) !== type) {
      continue; // type 与 value 不符（手改/跨版本脏值）丢弃
    }
    items.push({ key: key as string, type: type as string, value: value as Object });
  }
  return items;
}

// 数组元素类型判定（'string' | 'number' | '' = 空数组或混合——导入回写的类型契约用。
// ★ 只比 'array' 单值会放过「字符串数组写进数字数组」的脏包：本机 editCropState 是数字
// 数组、prefSearchEnabledEngines 是字符串数组，消费方算术会得 NaN。见 applyBackupPrefItems）
function arrayElementKindOf(v: Object): string {
  const arr: Object[] = v as Object[];
  let kind: string = '';
  for (const x of arr) {
    const cur: string = typeof x === 'string' ? 'string' : (typeof x === 'number' ? 'number' : '');
    if (cur === '') {
      return ''; // 有非 string/number 元素 = 混合/异常，判为无信息
    }
    if (kind === '') {
      kind = cur;
    } else if (kind !== cur) {
      return ''; // 混合数组（classifyPrefValue 本已拦，此处双保险）
    }
  }
  return kind; // 空数组返回 ''（无元素信息 → 调用方按放行处理）
}

// 回写偏好（导入侧调用）——返回实际写入条数。三道闸：①只认 BACKUP_PREF_KEYS 内的键
// （被改过的备份不能写任意 AppStorage 键）；②键未注册（现值 undefined）或类型与现值
// 不符（跨版本改过键型）跳过——注册默认值与本机类型为准，防写坏运行中页面；③数组还要
// 元素类型相符（见 arrayElementKindOf）
export function applyBackupPrefItems(items: PrefBackupItem[]): number {
  let written: number = 0;
  for (const item of items) {
    if (!BACKUP_PREF_KEYS.includes(item.key)) {
      continue;
    }
    const current: Object | undefined = AppStorage.get<Object>(item.key);
    if (current === undefined || classifyPrefValue(current) !== item.type) {
      continue;
    }
    if (item.type === 'array') {
      const curKind: string = arrayElementKindOf(current);
      const newKind: string = arrayElementKindOf(item.value);
      if (curKind !== '' && newKind !== '' && curKind !== newKind) {
        continue;
      }
    }
    AppStorage.setOrCreate<Object>(item.key, item.value);
    written++;
  }
  return written;
}
