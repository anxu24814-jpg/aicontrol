// 应用偏好持久键单一来源：偏好设置页写、跨域消费——键常量 + 缺省值 + 读值封装集中本文件，
// 防键名/缺省值散落漂移；消费方一律引用本文件常量，禁裸字符串。命名口径：AppStorage 持久键
// = 业务语义驼峰字符串（activeProvider 同族）。本文件零 import（叶子模块）；HTTP 凭据等三段
// 在 common/AppPreferencesHttp.ets（2026-10-01 迁出），备份分域表 + 凭据登记 +
// preferences.json 编解码在 common/AppPreferencesBackup.ets（2026-10-06 迁出）。
// 注册时机 = EntryAbility loadContent 成功回调 persistProp 区（坑17：必须在该回调注册，
// 早注册/晚注册都会导致写入不落盘或与组件初始化抢序）。各读值封装的回退同此口径：persistProp
// 注册先于任何页面组件实例化，正常路径不会走到回退，仅防御（一次性读的时序风险另见
// PREF_LOADED_KEY 注释）。

// ── 2026-11-12 偏好开关批整键退役（2152 节）──
// 十组显示/行为开关键与读值封装整体删除，行为固化为用户不可关闭：推荐语点击恒填入输入框、
// 工具卡收起态恒显结果摘要、本轮改动卡与消息时间与行内高亮与会话图标与会话时间恒显示、
// 会话列表恒按 updatedAt 倒序（最新在上）、行卡图标恒彩色圆角矩形；「图标」三级页整页撤除。
// 旧落盘值不继承、不做行为迁移——墓碑键名清单与一次性清理在 EntryAbility 启动注册区
//（全仓唯一落点）。勿再建同名键：无读点、无写点、无用户入口。

// 默认展开思考（偏好设置首项）：true = 思考步骤内容件（ChatThinkingStep）初始展开 /
// false = 默认收起（3 行截断）。仅决定新渲染块初始态，不做运行时广播（已上屏块不回翻，
// 手动展开/收起不被覆盖）——重进会话/新消息生效
export const PREF_THINK_EXPAND_KEY: string = 'prefThinkExpand';

// 读值封装（消费方组件创建期调用一次）：未写入回退 false（仅防御，见文件头）
export function getThinkExpandDefault(): boolean {
  return AppStorage.get<boolean>(PREF_THINK_EXPAND_KEY) === true;
}

// 已退役（2026-10-10）：原「流式引擎（试验）」键 PREF_STREAM_ENGINE_KEY 与 isCubeEngineEnabled
// 随 Cube 域退役删除——不再有引擎分流点。勿再建同名键：存量落盘值无人读，无害。

// 流式输出自动跟随：true = AI 输出时消息列表自动滚动跟随到底部（默认）/ false = 停在当前
// 位置不自动滚。仅约束流式增量的自动滚底（maybeFollow），手动发送强制滚底（forceToBottom）
// 不受影响。ChatFollowController.maybeFollow 滚底前现读 = 切换即时生效
export const PREF_STREAM_FOLLOW_KEY: string = 'prefStreamFollow';

// 读值封装（maybeFollow 滚底前现读）：未写入回退 true = 跟随（仅防御，见文件头）
export function isStreamAutoFollow(): boolean {
  return AppStorage.get<boolean>(PREF_STREAM_FOLLOW_KEY) !== false;
}

// HTML 预览运行脚本：true = 受限预览（htmlBlock/htmlInline 点开的独立 Web）开 JavaScript——
// 执行面仍无 javaScriptProxy 桥、无网络、无文件权限（开态壳 CSP 仅放宽 script-src，其余恒
// 'none'，blockNetwork(true) 双保险）；false = 照默认剥脚本（默认 = 安全优先，官方 ArkWeb
// 最佳实践）。MarkdownPreviewCover 点开时刻读一次（预览点开才建新实例，天然即时）
export const PREF_PREVIEW_JS_KEY: string = 'prefPreviewJs';

// 读值封装（预览点开时读）：未写入回退 false = 不执行脚本（仅防御，见文件头）
export function isPreviewJsEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_PREVIEW_JS_KEY) === true;
}

// 长代码块自动收起：true = 生成结束的超阈值长代码块自动收起为前若干行 + 底部展开条 /
// false = 保持展开（默认）。MarkdownScrollableBlock 终态评估现读（评估一次不再重评）——
// 重进会话后生效；只影响显示，复制/导出与完整阅读不受影响
export const PREF_CODE_AUTO_COLLAPSE_KEY: string = 'prefCodeAutoCollapse';

// 读值封装（代码块终态评估时读）：未写入回退 false = 不自动收起（仅防御，见文件头）
export function isCodeAutoCollapseEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_CODE_AUTO_COLLAPSE_KEY) === true;
}

// 代码块行号：true = Markdown 代码块、HTML <pre> 代码块与工具卡 diff 块逐行显示行号（默认）
// / false = 不显示。MarkdownCodeText / MarkdownHtmlBlockView / ChatToolDiffBlock 渲染期现读
//（已挂载块不即时增删行号——重进会话后生效）；只影响显示，复制/导出/完整阅读恒取原文
export const PREF_CODE_LINE_NUMBERS_KEY: string = 'prefCodeLineNumbers';

// 读值封装（三处消费点渲染期现读）：未写入回退 true = 显示行号（仅防御，见文件头）
export function isCodeLineNumbersEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_CODE_LINE_NUMBERS_KEY) !== false;
}

// 消息内 HTML 直接渲染：true = 消息中的 htmlBlock 走白名单结构投影 + 原生组件渲染（默认；
// 投影非空才渲染——未闭合/超限/畸形/无可见内容整块退源码）/ false = 一律按源码文本显示。
// MarkdownScrollableBlock 内容分支现读（已挂载块不即时换渲染——重进会话后生效）；只影响
// 显示，复制/导出与完整阅读恒取源文
export const PREF_HTML_BLOCK_RENDER_KEY: string = 'prefHtmlBlockRender';

// 读值封装（内容分支现读）：未写入回退 true = 直接渲染（仅防御，见文件头）
export function isHtmlBlockRenderEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_HTML_BLOCK_RENDER_KEY) !== false;
}

// 会话加载动画：true = 进入会话历史加载期间消息区显示淡蒙层与加载动画（默认——治进会话
// 消息区空白的感知空窗，默认关则该需求落空）/ false = 加载期纯背景。蒙层带最短延迟出现与
// 最短显示时间（防快加载与转场期闪现，两常量单源 ChatLoadingOverlay）。ChatLoadingOverlay
// @StorageProp 订阅——下次进入会话生效（已进会话内加载态不受拨动影响）
export const PREF_CHAT_LOADING_OVERLAY_KEY: string = 'prefChatLoadingOverlay';

// 读值封装：未写入回退 true = 显示加载动画（仅防御，见文件头）
export function isChatLoadingOverlayEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_CHAT_LOADING_OVERLAY_KEY) !== false;
}

// 长消息进页收起（★ 2026-10-18 双态设计改义，键名沿用保存量用户值）：true = 进会话时超阈值
// 超长消息（助手与用户同判）收起为一行提示（默认——重会话进页 0.2 秒量级）/ false = 进页
// 全部展开，由加载动画与分帧渐进揭示承担等待（主线程不被单帧整树构建卡死）。只影响显示，
// 复制/导出恒取原文。ChatMessageItem 折叠判据现读——重进会话后生效；阈值单源 =
// MarkdownScrollableBlock.LONG_MSG_COLLAPSE_CHARS
export const PREF_LONG_MSG_COLLAPSE_KEY: string = 'prefLongMsgCollapse';

// 读值封装（折叠判据现读）：未写入回退 true = 进页收起（仅防御，见文件头）
export function isLongMsgCollapseEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_LONG_MSG_COLLAPSE_KEY) !== false;
}

// 助手消息气泡：true = 助手回复带卡片色气泡底、圆角与内距（默认 = 引入前形态零回归）/
// false = 底色与圆角撤除、内距归零，正文贴行沿排列（过程段与工具卡不受影响仍带卡底，用户
// 泡不跟）。ChatPageContent 进页读一次、经普通成员下发 ChatMessageItem——重进会话后生效，
// 流式期间不做运行时换档
export const PREF_ASSISTANT_BUBBLE_KEY: string = 'prefAssistantBubble';

// 读值封装（进页读一次）：未写入回退 true = 带气泡底。`!== false` 姿势 = 缺省即开——默认
// 开的键禁写 `=== true`（与 isLongMsgCollapseEnabled 同族）
export function isAssistantBubbleVisible(): boolean {
  return AppStorage.get<boolean>(PREF_ASSISTANT_BUBBLE_KEY) !== false;
}

// 思考档位滑轨（★ 2026-11-25 思考档位滑轨笔）：true = 标题栏「思考」热区点开滑轨面板（默认，
// 新形态）/ false = 旧菜单（零回归路径）。消费方 = ChatTitleBarOverlay 的 @StorageProp @Watch
// 订阅——拨动开关即刻切换形态，不用重进会话。缺省开 = `!== false` 姿势（禁写 `=== true`）
export const PREF_THINKING_SLIDER_KEY: string = 'prefThinkingSlider';

// 读值封装：未写入回退 true = 滑轨形态（缺省即开）
export function isThinkingSliderEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_THINKING_SLIDER_KEY) !== false;
}

// SVG 预览（★ 2026-10-21 决明拍板：开关面退役、功能恒开）：代码块形式的 SVG（```svg 直认、
// ```xml 验根元素为 svg）在代码块标题条给受限预览入口——点开走受限 Web 壳静态渲染（无脚本、
// 无网络、无文件权限），渲染前过 MarkdownPreviewPolicy 准入校验，失败落回普通代码块；三处
// 消费点读同一封装（恒 true，消费方零改动）。键与 persistProp 注册保留——只为存量备份/偏好
// 读取不报错、备份键计数不因退役而变；旧值（曾手动关闭的用户）自此被忽略
export const PREF_SVG_PREVIEW_KEY: string = 'prefSvgPreview';

// 读值封装：★ 2026-10-21 起恒 true——开关行已退役，不再读旧键（旧 false 值同样视为开启）
export function isSvgPreviewEnabled(): boolean {
  return true;
}

// Mermaid 消息内联渲染：true = 已闭合的合法 mermaid 代码块在消息内直接显示渲染图（离屏
// 受限壳渲成 PNG，原生 Image 显示，点击进现有全屏受限预览；默认）/ false = 一律按代码块
// 显示。渲染失败或通道不可用自动退码——开态最坏情况与关态观感一致。MarkdownScrollableBlock
// 内容分支现读——重进会话后生效；只影响显示，复制/导出恒取源文
export const PREF_MERMAID_INLINE_KEY: string = 'prefMermaidInline';

// 读值封装（内容分支现读）：未写入回退 true = 内联渲染（仅防御，见文件头）
export function isMermaidInlineEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_MERMAID_INLINE_KEY) !== false;
}

// 键盘发送：true = 会话页输入框键盘右下角换行键替换为发送键（点击 onSubmit 直接发送）/
// false = 换行键（默认，与 TextArea.enterKeyType 官方默认一致）。★ 长短按区分 = 系统键盘
// 行为，官方 API 只控制回车键形态，无法保证「长按换行」。ChatInputBar @StorageProp 订阅即刷
export const PREF_KEYBOARD_SEND_KEY: string = 'prefKeyboardSend';

// 输入框常驻展开：true = 会话页输入框恒为展开态（两排卡全宽；点击其他位置、收起键盘均不
// 收起）/ false = 收起态胶囊（默认——点击展开、失焦延时收起）。★ 键盘避让与形态解耦：避让
// 模式切换挂焦点回调、底部留白挂键盘高度事件，均不读本键。ChatInputBar @StorageProp @Watch
// 订阅（进页置初态 + 中途切换即对齐；收起守卫见 startCollapseTimer）
export const PREF_INPUT_EXPANDED_KEY: string = 'prefInputExpanded';

// 图片链接作为图片发送：true = 发送的消息文本含 Markdown 图片链接（![alt](url)，仅
// http/https）时，发送前自动下载其中图片作为图片附件随本轮请求发给模型（单图超时 15 秒 /
// 单张上限 20MB / 一条消息最多 8 张 / 整条总预算 30 秒）/ false = 关（默认），按普通文本
// 发送。★ 全静默：无视觉模型自动旁路、下载失败与超限链接静默留作文本，无确认框无报错无
// 重试；原文全程保留——只给请求合并 images，气泡/DB/协议文本不动。TextImageFetch 发送链
// 三闸早退现读（发送时刻读一次，拨动自下一条消息生效）
export const PREF_TEXT_IMAGE_FETCH_KEY: string = 'prefTextImageFetch';

// 读值封装（TextImageFetch 早退现读）：未写入回退 false = 功能旁路（仅防御，见文件头）
export function isTextImageFetchEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_TEXT_IMAGE_FETCH_KEY) === true;
}

// 拍照保存到相册：true = 会话内「拍照」添加的照片在拍摄时同时存进系统相册——不传 saveUri，
// 系统相机自动落入媒体库并返回 URI（临时授权可读），随后 fd 级拷入沙箱供发送 / false = 只落
// 应用沙箱（默认），相册零痕迹。★ 保存时机 = 拍照时刻（系统相机落盘行为，与是否发送成功
// 无关）；只影响「拍照」入口，零新增权限。AttachmentPickCtrl 相机分支现读——拨动即生效
export const PREF_PHOTO_SAVE_GALLERY_KEY: string = 'prefPhotoSaveGallery';

// 读值封装（相机分支现读）：未写入回退 false = 不保存到相册（仅防御，见文件头）
export function isPhotoSaveGalleryEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_PHOTO_SAVE_GALLERY_KEY) === true;
}

// 添加图片时编辑：true = 会话页「拍照」与「照片」两入口拿到的图片先落沙箱、进待发图片
// 裁剪页编辑，完成后裁剪产物照旧进输入框 / false = 拍完选完直接进输入框（默认，零回归）。
// ★ 范围口径：只管这两个入口；「系统文件」入口、重发、系统分享与粘贴件一律不进编辑页。
// 编辑页返回键 = 放弃这张照片（不入列，原图副本删除）；加载或裁剪失败 = 中文提示后按原图
// 入列，零静默丢失。消费方 = AttachmentPickCtrl.pick 两分支现读——拨动即生效，下一次添加生效
export const PREF_PHOTO_EDIT_KEY: string = 'prefPhotoEdit';

// 读值封装（选择器分支现读）：未写入回退 false = 不编辑（仅防御，见文件头）
export function isPhotoEditEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_PHOTO_EDIT_KEY) === true;
}

// 已退役（2026-10-06 控制面层级化笔）：原总开关 PREF_CODE_WORKBENCH_KEY 与
// isCodeWorkbenchEnabled 删除——三件脚本工具（exec_code / exec_output_read /
// workspace_stage）迁 TOOL_GROUP_CODE 独立卡，可用性全随助手级「脚本工作台」卡开关
//（assistants.tools 清单进出）。存量已写 true 的键不再被读（新装机不注册 persistProp，
// 旧备份导入经 BACKUP_PREF_KEYS 白名单剔除该键）。

// 代码工作台执行档位：'standard' = 标准档（默认，限时与内存上限取全额）/ 'strict' = 严格档
//（时限与内存上限减半——对冲失控脚本）。数值映射单源 = common/codeexec/ScriptLimits.ets
//（本文件只管档位值域与缺省，数值禁散落字面量）。ScriptLimits 映射 + 设置页档位段控
// @StorageLink 消费；随偏好备份走；不进 ToolPref 白名单（放宽执行能力同属权限提升路径）
export const PREF_CODE_WORKBENCH_MODE_KEY: string = 'prefCodeWorkbenchMode';
// 档位两值（值域单源；UI 段控下标映射与 ScriptLimits 映射消费本常量）
export const CODE_WORKBENCH_MODE_STANDARD: string = 'standard';
export const CODE_WORKBENCH_MODE_STRICT: string = 'strict';

// 档位读取封装：脏值/未写入回退 'standard'（缺省真源在 persistProp 注册侧，本函数兜
// 备份导入等第二写键方带来的任意值）
export function resolveCodeWorkbenchMode(raw: string): string {
  return raw === CODE_WORKBENCH_MODE_STRICT ? CODE_WORKBENCH_MODE_STRICT :
    CODE_WORKBENCH_MODE_STANDARD;
}

export function codeWorkbenchMode(): string {
  return resolveCodeWorkbenchMode(AppStorage.get<string>(PREF_CODE_WORKBENCH_MODE_KEY) ?? '');
}

// 脚本执行引擎（★ 2026-10-07 决明拍板「引擎可单独开关」，翻案原「UI 永不暴露引擎选项」
// 红线）：'auto' = 严格档试验引擎 / 标准档系统引擎（默认）；'quickjs' = 两档都试验引擎；
// 'jsvm' = 两档都系统引擎。ScriptEnginePick 每次运行提交时刻现读；随偏好备份走；不进
// ToolPref 白名单（与档位键同口径）
export const PREF_CODE_WORKBENCH_ENGINE_KEY: string = 'prefCodeWorkbenchEngine';
// 引擎三值（值域单源；UI 段控下标映射与二维判定消费本常量）
export const CODE_WORKBENCH_ENGINE_AUTO: string = 'auto';
export const CODE_WORKBENCH_ENGINE_QUICKJS: string = 'quickjs';
export const CODE_WORKBENCH_ENGINE_JSVM: string = 'jsvm';

// 引擎值域归一：脏值/未写回 'auto'（兜备份导入等第二写键方带来的任意值）
export function resolveCodeWorkbenchEngine(raw: string): string {
  if (raw === CODE_WORKBENCH_ENGINE_QUICKJS || raw === CODE_WORKBENCH_ENGINE_JSVM) {
    return raw;
  }
  return CODE_WORKBENCH_ENGINE_AUTO;
}

export function codeWorkbenchEngine(): string {
  return resolveCodeWorkbenchEngine(AppStorage.get<string>(PREF_CODE_WORKBENCH_ENGINE_KEY) ?? '');
}

// 二维判定：本次运行是否走试验引擎（QuickJS）——「引擎开关 × 档位」的唯一判据单源（禁在
// 别处重写三目链；照 resolveOcrEngine「解析单源」先例）。纯函数零依赖，供断言直跑；
// 真值表：auto（含脏值/空）→ 严格档试验、其余系统；quickjs → 两档恒试验；jsvm → 两档恒系统
export function codeWorkbenchUsesQuickJsEngine(mode: string, engine: string): boolean {
  const e: string = resolveCodeWorkbenchEngine(engine);
  if (e === CODE_WORKBENCH_ENGINE_JSVM) {
    return false;
  }
  if (e === CODE_WORKBENCH_ENGINE_QUICKJS) {
    return true;
  }
  return mode === CODE_WORKBENCH_MODE_STRICT;
}

// 会话页屏幕常亮：true = 进入会话页设窗口常亮（window.setWindowKeepScreenOn，窗口级属性
// 无需权限）/ false = 系统息屏（默认）。ChatPage aboutToAppear 现读、aboutToDisappear 无条件
// 复位 false（成对——官方限制条目「退出场景后须设回 false」）
export const PREF_KEEP_SCREEN_ON_KEY: string = 'prefKeepScreenOn';

// 读值封装（ChatPage.aboutToAppear 调用一次）：未写入回退 false（仅防御，见文件头）
export function isKeepScreenOnEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_KEEP_SCREEN_ON_KEY) === true;
}

// 会话宫格视图（用户面名称；内部代号方块卡）：true = 对话页会话卡按摘要长短错落排成两列宫格 / false = 单列列表。默认 false =
// 引入前形态零回归，故读值用 `=== true` 回退（同 isKeepScreenOnEnabled 口径）。消费方 =
// ChatSessionList 壳 @StorageProp 订阅（切换即重算）与会话卡片渲染分支
export const PREF_SESSION_CARD_GRID_KEY: string = 'prefSessionCardGrid';

// 读值封装：未写入回退 false = 单列列表（仅防御，见文件头）
export function isSessionCardGridVisible(): boolean {
  return AppStorage.get<boolean>(PREF_SESSION_CARD_GRID_KEY) === true;
}

// 智感握姿跟随（2026-10-27 订正：页签栏入口随 adaptToHandedness 撤销退役，消费方只剩悬浮键）：
// true = 悬浮新建键随左右手握持移到同侧 / false = 恒右不跟随（握姿事件照常到达但早退）。
// SessionNewFab @StorageProp @Watch 自订阅（拨关瞬间若在左位则动画归右）。★ 本键只在
//「列表右下」档有生效面（PREF_NEW_SESSION_ENTRY_KEY 门控，PrefSessionReadPage 检测到非该档
// 即自动归正 false）——「默认 true」实际只在悬浮档且未进过偏好页的组合可达，正常链路智感
// 从关闭起步，属 opt-in
export const PREF_HOLDING_FOLLOW_KEY: string = 'prefHoldingFollow';

// 读值封装：未写入回退 true（`!== false` 默认开姿势，仅防御）
export function isHoldingFollowEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_HOLDING_FOLLOW_KEY) !== false;
}

// 快捷新建键（★ 2026-10-29 二改，默认值由 'off' 改 'tabBar'；★ 2026-10-30 三改两档化，
// 决明「关闭这一项去掉——关掉就没有落点了，默认仍然是页签栏旁」——'off' 档退役，两处
// 入口至少其一恒在场；★ 2026-10-31 三档化，新增 'tabItem' 页签第四项档）：单键三值——
// 'tabBar' 页签栏旁圆键（HdsTabs 官方迷你栏插槽，**默认**）/ 'tabItem' 页签第四项动作位
//（HdsTabs 第四个 TabContent，点击不切页直接新建）/ 'float' 会话列表右下悬浮键。各入口的
// 互斥由单键值域**结构性**保证——不存在「两个都开」的取值，故不做开关互相锁定的写回逻辑
//（拨开一个自动关另一个会让开关自己跳）。
// 消费方 = HomeNavigation（miniBar 门控 + 第四项条件挂载）+ ChatSessionList（悬浮键挂载
// 门控）@StorageProp 订阅即刷；写点唯一 = PrefSessionReadPage 分段卡（下标 ↔ 值映射见该页
// 成员注释）；随偏好备份走。默认值只在**首次注册**（新装/从无本键旧版升级）时生效——已存
// 'off' 旧值经 resolveNewSessionEntry 归一为 'tabBar'（退役档并入默认档），不强制迁移
export const PREF_NEW_SESSION_ENTRY_KEY: string = 'prefNewSessionEntry';
// 值域三量（上键单源；写入点 = 偏好页三段，消费方比较常量，禁裸字符串。★ 2026-10-30
// 两档化：原 'off' 关闭档随决明拍板退役、常量删除——存量 'off' 由归一函数收编；
// ★ 2026-10-31 三档化新增 'tabItem'）
export const NEW_SESSION_ENTRY_TAB_BAR: string = 'tabBar';
export const NEW_SESSION_ENTRY_TAB_ITEM: string = 'tabItem';
export const NEW_SESSION_ENTRY_FLOAT: string = 'float';

// 值域归一：未写入/脏值/退役旧值 'off' 一律回退 'tabBar'（保留档 = 'float' 与 'tabItem'；
// 兜备份导入等第二写键方任意值）。消费方与偏好页同吃本归一 ⇒ 「显示段」与
// 「实际生效面」不分叉；纯函数供断言直跑
export function resolveNewSessionEntry(raw: string): string {
  if (raw === NEW_SESSION_ENTRY_FLOAT || raw === NEW_SESSION_ENTRY_TAB_ITEM) {
    return raw;
  }
  return NEW_SESSION_ENTRY_TAB_BAR;
}

// 后台回复提醒：true = 切后台时申请短时任务保活当前生成并发送回复通知（开关打开时顺带请求
// 通知授权，被拒即回落为关）/ false = 不申请短时任务也不发通知（默认——「关 = 不承诺做不到
// 的事」，语义细则见 ChatBgReply 头注释）。ChatBgReply 申请/发布两闸现读（关 =
// requestKeepAlive 与 publishOngoing 直接早退）+ 设置页开关行
export const PREF_BG_REPLY_NOTIFY_KEY: string = 'prefBgReplyNotify';

// 读值封装（两闸现读——开关关即零动作）：未写入回退 false（`=== true` 姿势，仅防御）
export function isBgReplyNotifyEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_BG_REPLY_NOTIFY_KEY) === true;
}

// 文件工作区列表排序：六档 = 'custom' 自定义（默认——文件夹按拖拽序、文件按最近更新在前）/
// 'name' 两段名称字典序 / 'timeDesc' | 'timeAsc' 文件夹按创建时间、文件按最近更新时间降/升 /
// 'sizeDesc' | 'sizeAsc' 文件夹按子树合计、文件按自身大小降/升——纯显示层换序，DB 查询与
// 成员集不动。消费方 = 管理页现读单源（写点唯一、写入即显式重派生，不赌订阅时序；排序只在
// 文件夹分段生效）+ workspace_list 工具回执（AI 与用户同序不变量）。写入点唯一 = 管理页
//「更多」菜单「排序」子菜单；值域常量与脏值兜底单源 = WorkspaceUtil.resolveWorkspaceSortMode
export const PREF_WORKSPACE_SORT_KEY: string = 'prefWorkspaceSort';

// 背景仅用于会话页：true = 自定义背景只在会话页显示，其余页面（一级/二级/平板分栏铺底）用
// 默认官方底色 / false = 全应用生效（默认）。PageBackground @StorageProp 订阅 + sessionPage
// 参数（ChatPage 经 PageShell 传 true）组合判定，@Watch 重拉即刷；背景图文件与换图/恢复默认
// 链路零改动
export const PREF_BG_SESSION_ONLY_KEY: string = 'prefBgSessionOnly';

// ── 卡底透明度档位 ──
// 键 = 持久档位（0~4 五档，L4 不透明 = 默认）。消费链 = Theme.ets cardBg / chatBubbleUserBg
// 缺省读键（重建层）+ 即时面 13~15 件 @StorageProp 只读订阅（档位变化属性级刷新）；写点唯一
// = 「背景」三级页滑轨卡 @StorageLink。阶梯表单源 = Theme.ets CARD_ALPHA_LIGHT/DARK 双表
export const PREF_CARD_ALPHA_LEVEL_KEY: string = 'prefCardAlphaLevel';
// 档位值域四量（滑轨 min/max/step 与钳位共引——改域只改这里，禁两处各写一份）
export const CARD_ALPHA_MIN: number = 0;
export const CARD_ALPHA_MAX: number = 4;
export const CARD_ALPHA_STEP: number = 1;
export const CARD_ALPHA_DEFAULT: number = 4;

// 档位钳位（非有限数或越界回默认，域内取整原样回）。读写两侧一律经本函数——老备份/手改
// 越界防档位表下标越界
export function clampCardAlphaLevel(value: number): number {
  if (!Number.isFinite(value)) {
    return CARD_ALPHA_DEFAULT;
  }
  return Math.min(Math.max(Math.round(value), CARD_ALPHA_MIN), CARD_ALPHA_MAX);
}

// 页签切换动画：true = 一级页底部页签点击切换带横向滑动动画（300ms = 官方通用默认时长）/
// false = 点按直达、无过渡（默认 true）。HomeNavigation @StorageProp 订阅（状态驱动重渲染
// 即刷）
export const PREF_TAB_SWITCH_ANIM_KEY: string = 'prefTabSwitchAnim';

// 启动进入页面：true = 冷启动直接进入一个新对话（懒创建不落库，首条消息才建行——同标题栏
//「＋」语义；所属助手 = 当前助手 ACTIVE_ASSISTANT_KEY，无行新会话兜底见
// ChatPromptState.effectiveAssistantId）/ false = 进入对话一级页（默认）。HomeNavigation.
// aboutToAppear 现读一次——仅冷启动首帧生效（后台回前台不重进），切换下次启动生效
export const PREF_LAUNCH_NEW_CHAT_KEY: string = 'prefLaunchNewChat';

// 读值封装（HomeNavigation.aboutToAppear 调用一次）：未写入回退 false（仅防御，见文件头）
export function isLaunchNewChatEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_LAUNCH_NEW_CHAT_KEY) === true;
}

// ── 首页布局双形态（方案-首页布局双形态-20261116，2026-11-16 立项一笔施工）──
// 首页布局：'tabs' 底栏页签形态（现状，默认）/ 'drawer' 侧栏对话形态（首页直接是对话，
// 历史会话与助手/设置入口收左侧抽屉，类 RikkaHub）。写点唯一 = 「偏好与外观」页「外观」卡
// 开关行；消费方 = HomeNavigation（形态分发器 @StorageProp @Watch——热切换回根重建壳）。
// 切换立即生效不重启（三页数据真源全在 RDB + AppStorage，壳重建 aboutToAppear 重查即恢复）；
// 切换丢临时态（主区滚动位/侧栏开合/导航栈清空回根）——极低频操作可接受，论证见方案档 §2.1
export const PREF_HOME_LAYOUT_KEY: string = 'prefHomeLayout';
// 值域两量（单键值域结构性互斥，同 PREF_NEW_SESSION_ENTRY_KEY 口径）
export const HOME_LAYOUT_TABS: string = 'tabs';
export const HOME_LAYOUT_DRAWER: string = 'drawer';

// 值域归一：未写入/脏值一律回退 'tabs'（引入前形态零回归）；消费方与偏好页同吃本归一，
// 「显示段」与「实际生效面」不分叉；纯函数供断言直跑
export function resolveHomeLayout(raw: string): string {
  return raw === HOME_LAYOUT_DRAWER ? HOME_LAYOUT_DRAWER : HOME_LAYOUT_TABS;
}

// 读值封装：当前是否侧栏对话形态（分发器与灰化判定共用）
export function isHomeLayoutDrawer(): boolean {
  return resolveHomeLayout(AppStorage.get<string>(PREF_HOME_LAYOUT_KEY) ?? '') === HOME_LAYOUT_DRAWER;
}

// 上次打开的会话 id（侧栏形态启动落点承接键，方案档 §4.1-8）：会话打开时更新（openSession
// 与主区换会话两写点）；侧栏形态冷启动且「启动进入新对话」关 = 打开本键会话，空/会话已删
// 兜底新会话态。随备份走（换机后落上次会话）
export const PREF_LAST_CONV_ID_KEY: string = 'prefLastConvId';

// 价格卡收起态：true = 模型编辑页价格卡默认收起为「主副标题两行短卡」/ false = 默认展开。
// ★ 与其他偏好不同，本键**不在偏好设置页暴露**——用户点卡片标题行经 @StorageLink 双向绑定
// 隐式写入（一写即落盘，无需保存），故无设置页行、无搜索注册、无帮助条目；换机随备份走。
// 消费方 = ModelPriceCard @StorageLink collapsed——价格模板编辑页复用同卡但 collapsible=false，
// 判定带能力守卫（读到的全局值不影响其渲染——恒展开，也不写入）
export const PREF_PRICE_CARD_COLLAPSED_KEY: string = 'prefPriceCardCollapsed';

// 服务商编辑页高级页签两卡收放态（与价格卡同款口径：不在偏好页暴露，点标题行 @StorageLink
// 隐式写入一写即落盘，随备份走）。消费方 = ProviderHeadersPanel / ProviderBodyPanel 各持一
// 键（两卡独立不串）
export const PREF_HEADERS_CARD_COLLAPSED_KEY: string = 'prefHeadersCardCollapsed';
export const PREF_BODY_CARD_COLLAPSED_KEY: string = 'prefBodyCardCollapsed';

// 余额请求头卡收放态（同上口径）。消费方 = BalanceHeadersCard（宿主 = BalanceConfigPage）
export const PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY: string = 'prefBalanceHeadersCardCollapsed';

// 浏览高危操作自动通过（旧布尔键，已退为确认档的只读兜底，见下「确认档三态」）：false =
// 每次确认（默认——高危动作弹确认卡征求同意）/ true = 自动通过（预检直接判无需确认，高危
// 动作与读向动作同路并行执行）。ToolBrowseAct 两闸现读 = 切换即时生效，下一个动作按新值
//（已弹出的确认卡仍需作答）。★ 刻意不进工具查询白名单（get_app_preference）——防提示注入翻转安全设置
export const PREF_BROWSE_AUTO_APPROVE_KEY: string = 'prefBrowseAutoApprove';

// 读值封装（两闸现读）：未写入回退 false = 每次确认（仅防御，见文件头）
export function isBrowseAutoApproveEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_BROWSE_AUTO_APPROVE_KEY) === true;
}

// HTTP 写操作自动通过（旧布尔键，已退为确认档的只读兜底，见下「确认档三态」）：false =
// 每次确认（默认——http_request 写方法 POST/PUT/DELETE/PATCH 弹确认卡征求同意）/ true =
// 自动通过（预检首行早退回空串，写请求与读方法同路直发）。ToolHttp 预检现读（下一个请求按
// 新值，已弹出的确认卡仍需作答；执行器侧无第二道判据——本件不带批准戳）。★ 刻意不进
// 工具查询白名单（get_app_preference）——防提示注入翻转安全设置（同浏览键纪律）
export const PREF_HTTP_WRITE_AUTO_APPROVE_KEY: string = 'prefHttpWriteAutoApprove';

// 读值封装（ToolHttp 预检现读）：未写入回退 false = 每次确认（仅防御，见文件头）
export function isHttpWriteAutoApproveEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_HTTP_WRITE_AUTO_APPROVE_KEY) === true;
}

// ── 确认档三态（2026-09-28 三档归并——治「自动通过」与审批模型两根控件在同一根轴上竞争、
//    自动通过会静默盖掉审批模型）──
// 每域一根旋钮，互斥：ask = 每次确认（直落人工卡，**不过审批模型**）；model = 先问审批模型
//（缺省档：放行即执行、拒绝与拿不准落人工卡；**未配置审批槽时经闸 escalate 落同一张人工卡
// ⇒ 与旧「每次确认」同效**——迁移零行为变化的支点）；auto = 一律放行（预检早退，连模型也
// 不看 = 旧「自动通过」）。
// ★ 存储形态：**新字符串键为写侧，旧布尔键退为只读兜底但仍随备份走**——旧备份恢复后还要按
// 旧键推导，删了会丢老用户升级态。写入面只剩设置页分段（@StorageLink 一写即落盘）
export const APPROVE_MODE_ASK: string = 'ask';
export const APPROVE_MODE_MODEL: string = 'model';
export const APPROVE_MODE_AUTO: string = 'auto';

// 网页高危操作确认档（键名同族：prefBrowseApproveMode）
export const PREF_BROWSE_APPROVE_MODE_KEY: string = 'prefBrowseApproveMode';
// HTTP 写操作确认档（键名同族：prefHttpApproveMode）
export const PREF_HTTP_APPROVE_MODE_KEY: string = 'prefHttpApproveMode';
// 数据管理操作确认档（第三域：记忆/知识库/提示词/功能模型五工具 + 日程三写件）。★ 本域无
// 旧布尔键——未写键按 resolveApproveMode 第二参 false 推导 = 缺省中间档（未配置审批槽时经闸
// escalate 落人工卡 = 与「每次确认」同效，缺省从严不扰民）
export const PREF_DATA_APPROVE_MODE_KEY: string = 'prefDataApproveMode';

// 档位归一（纯函数，断言直跑）：合法三值原样；未写（''）与脏值一律**按旧布尔键推导**——
// 旧 true（自动通过）→ auto、旧 false（每次确认）→ model。四处共用同一函数，禁各自散判
export function resolveApproveMode(rawMode: string, legacyAutoApprove: boolean): string {
  if (rawMode === APPROVE_MODE_ASK || rawMode === APPROVE_MODE_MODEL ||
    rawMode === APPROVE_MODE_AUTO) {
    return rawMode;
  }
  return legacyAutoApprove ? APPROVE_MODE_AUTO : APPROVE_MODE_MODEL;
}

// 现读封装（两闸现读——切换即时生效，下一个动作按新值，已弹出的确认卡仍需作答）
export function browseApproveMode(): string {
  return resolveApproveMode(AppStorage.get<string>(PREF_BROWSE_APPROVE_MODE_KEY) ?? '',
    AppStorage.get<boolean>(PREF_BROWSE_AUTO_APPROVE_KEY) === true);
}

// 现读封装（ToolHttp 预检现读）
export function httpApproveMode(): string {
  return resolveApproveMode(AppStorage.get<string>(PREF_HTTP_APPROVE_MODE_KEY) ?? '',
    AppStorage.get<boolean>(PREF_HTTP_WRITE_AUTO_APPROVE_KEY) === true);
}

// 现读封装（数据管理族预检现读；legacy 恒 false——本域无旧布尔键，见键注释）
export function dataApproveMode(): string {
  return resolveApproveMode(AppStorage.get<string>(PREF_DATA_APPROVE_MODE_KEY) ?? '', false);
}

// ── 会话权限模式四键（2026-11-09 真完全权限笔；同日三档归一笔记收敛为谨慎/标准/高效）：
//    一根旋钮统管三域确认档 ──
// 应用默认档：落盘随备份，三档全开放；缺省 '' = 迁移态，由启动迁移
//（PermissionMode.migrateLegacyApproveModes）按旧三域档最严值一次性折算写定。写点 =
// 设置-工具页默认档卡。
export const PREF_DEFAULT_PERMISSION_MODE_KEY: string = 'prefDefaultPermissionMode';
// 当前会话覆盖：只存 AppStorage 内存（由按会话持久表回填，见下一键），不注册 persistProp、
// 不进备份表。'' = 当前会话未手动切档。
export const CHAT_PERMISSION_MODE_KEY: string = 'chatPermissionMode';
// 当前会话 id（只存 AppStorage 内存，与上一键配对——判断「进的是不是同一个会话」；
// 不持久化，进程死亡即失效）
export const CHAT_PERMISSION_MODE_CONV_KEY: string = 'chatPermissionModeConv';
// 按会话持久表（JSON：会话 id → 谨慎/标准/完全权限）：重启后按会话恢复，落 persistProp、
// 刻意不进备份表（键是本地会话 id，换机无意义；完全权限跨设备静默复现等于替新设备放宽）。
export const PREF_CHAT_PERMISSION_MODES_KEY: string = 'prefChatPermissionModes';

// 默认档现读（'' = 迁移态）。三档全开放（高效档自三档归一笔记起可由用户设为默认），
// 脏值一律回退 ''。会话覆盖与档位映射在 common/chat/PermissionMode.ets（本件零 import
// 叶子契约不破）。
export function defaultPermissionMode(): string {
  const raw: string = AppStorage.get<string>(PREF_DEFAULT_PERMISSION_MODE_KEY) ?? '';
  return (raw === 'cautious' || raw === 'standard' || raw === 'full') ? raw : '';
}

// 工具调用轮数上限：存储值域 0~32——0 = 不限制（经 ToolLimits.resolveToolStepLimit 换算为
// 内置硬顶 256 兜底）/ 1~上限 = 一次发送内工具调用轮数上限；默认 32 = 旧全局常量同值。★ 旧
// 载体 = assistants.toolStepLimit 列（DB v22）2026-09-27 起退役为墓碑（库内保留、代码面零
// 读写），本键接管全局唯一来源。ChatPromptState 两 getter 轮首现读（改值下一条消息生效）
// + 设置页滑轨卡。默认值与值域单源在 ToolLimits 叶子模块；随备份走
export const PREF_TOOL_STEP_LIMIT_KEY: string = 'prefToolStepLimit';

// 搜索结果条数：值域 1~25，默认 5；换算与钳位单源 = common/search/SearchLimits.ets。旧载体
// assistants.searchResultCount 列（DB v25）同笔退役为墓碑。ChatPromptState 轮首现读（值随
// 执行上下文快照传搜索执行器）+ 设置页「联网搜索」页条数卡；随备份走
export const PREF_SEARCH_RESULT_COUNT_KEY: string = 'prefSearchResultCount';

// 联网请求超时：存储值 = 秒数，值域 5~60、默认 20（= 旧写死 SEARCH_TIMEOUT_MS 20000 同值，
// 零回归）；值域与换算单源 = common/search/SearchLimits.ets。作用链 = 联网搜索四通路（Bing
// local / 博查 / 秘塔 / Serper）与 scrape_web 抓取的请求计时（改值下一个请求生效，在途请求
// 用入口快照）。消费方 = 联网请求入口（经 searchTimeoutSeconds 取一次后形参下传）+ 设置页
//「联网搜索」页超时卡。★ 与 PREF_NET_READ_TIMEOUT_MIN_KEY **刻意分链**（那条管等模型回复、
// 分钟级；本条管等网页与接口响应、秒级）——两键互不读写，勿合并。随备份走
export const PREF_SEARCH_TIMEOUT_SEC_KEY: string = 'prefSearchTimeoutSec';

// 网络自动重试：true = 请求失败且**本轮尚无任何内容产出**时自动退避重发同一请求，最多 3 次
//（2/4/8 秒），期间助手气泡内显示次数状态行、用户可随时停止 / false = 不自动重试，维持手动
// 点重试。重试面 = 传输层 -1 ∪ 服务端 5xx（500/502/503/504/529）∪ 瞬态文案（过载限流类词表
// 命中），与零产出、非用户停止同时成立——中途断流（屏上已有内容）、401/403/429（归 Key 池
// 换钥）与余额不足类停词不自动重试（判据单源见 ChatAutoRetryCtrl）。★ 默认 true = **有意
// 选择非疏忽**（越出「默认 = 现状零回归」惯例）：只在零产出的网络失败触发，重试耗尽仍走原
// 失败路径，风险面极低；默认关则绝大多数用户永不会打开，功能等于白做。轮首现读一次、轮内
// 锁定——切换下一条消息生效
export const PREF_AUTO_RETRY_KEY: string = 'prefAutoRetry';

// 读值封装（自动重试域判据现读）：未写入回退 true = 自动重试（仅防御，见文件头）
export function isAutoRetryEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_AUTO_RETRY_KEY) !== false;
}

// 粘贴长文本转文件：true = 会话页输入栏粘贴的文本长度达到阈值时**不插进输入框**，落盘成
// .txt 附件挂进待发附件条（附件满或失败时文本回退输入框，内容一字不丢）/ false = 任何粘贴
// 照常插入。★ 默认 true = 有意选择非疏忽（粘贴件只是换个位置出现；默认关则功能等于白做）。
// ChatInputBar @StorageProp 自订阅即刷（坑16 正解）
export const PREF_PASTE_AS_FILE_KEY: string = 'prefPasteAsFile';

// 粘贴转文件的长度阈值（字符数）：粘贴文本长度 **≥ 本值** 才转附件，短文本照常插入。
// 默认 2000；取值域 1000~20000、步进 500，读取侧一律经 clampPasteThreshold 钳位（老备份/
// 手改越界会让滑块停在异常位置且判定静默失效）。消费方同上一键
export const PREF_PASTE_AS_FILE_THRESHOLD_KEY: string = 'prefPasteAsFileThreshold';

// 阈值域三量与默认值（滑块 min/max/step 与钳位共引——改域只改这里，禁两处各写一份）
export const PASTE_THRESHOLD_MIN: number = 1000;
export const PASTE_THRESHOLD_MAX: number = 20000;
export const PASTE_THRESHOLD_STEP: number = 500;
export const PASTE_THRESHOLD_DEFAULT: number = 2000;

// 阈值钳位（非有限数或越界回默认；域内取整原样回）。读取侧取值一律经本函数
export function clampPasteThreshold(value: number): number {
  if (!Number.isFinite(value)) {
    return PASTE_THRESHOLD_DEFAULT;
  }
  return Math.min(Math.max(Math.round(value), PASTE_THRESHOLD_MIN), PASTE_THRESHOLD_MAX);
}

// 时间间隔提醒：true = 对话间隔超过阈值时，发送组装在该条 user 消息前插入一条合成提醒（含
// 当时时刻与距上一条消息的时长，帮助模型理解时间跨度）/ false = 完全不插。★ 默认 false =
// 有意选择（与粘贴键相反）：本功能改变发出去的请求内容，静默生效会让用户困惑。提醒不落库
// 不上屏，只在请求日志可见；ChatSendCtrl 每轮现读（轮首一次、轮内锁定，照自动重试同口径）
export const PREF_TIME_REMINDER_KEY: string = 'prefTimeReminder';

// 提醒间隔阈值（分钟）：user 消息与其前一条非 system 消息的间隔 **≥ 本值** 才插提醒。
// 默认 60；取值域 15~720、步进 15，读取侧一律经 clampTimeReminderMinutes 钳位。消费方同上一键
export const PREF_TIME_REMINDER_MINUTES_KEY: string = 'prefTimeReminderMinutes';

// 阈值域三量与默认值（滑块 min/max/step 与钳位共引——改域只改这里，禁两处各写一份）
export const TIME_REMINDER_MIN: number = 15;
export const TIME_REMINDER_MAX: number = 720;
export const TIME_REMINDER_STEP: number = 15;
export const TIME_REMINDER_DEFAULT: number = 60;

// 阈值钳位（非有限数或越界回默认；域内取整原样回）。读取侧取值一律经本函数
export function clampTimeReminderMinutes(value: number): number {
  if (!Number.isFinite(value)) {
    return TIME_REMINDER_DEFAULT;
  }
  return Math.min(Math.max(Math.round(value), TIME_REMINDER_MIN), TIME_REMINDER_MAX);
}

// 读值封装（发送组装轮首现读）：未写入回退 false = 不提醒（仅防御，见文件头）
export function isTimeReminderEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_TIME_REMINDER_KEY) === true;
}

// 阈值读值封装（同上）：未写入回默认 60，越界/非有限数经钳位收进域内
export function timeReminderMinutes(): number {
  return clampTimeReminderMinutes(
    AppStorage.get<number>(PREF_TIME_REMINDER_MINUTES_KEY) ?? TIME_REMINDER_DEFAULT);
}

// ── 全局请求身份 ──
// 全局 User-Agent 自定义值：'' = 用默认（AiControl/<versionName>——默认值拼接、净化与兜底
// 单源在 common/providers/RequestIdentity.ets，本文件零 import 只持键与读封装）。消费方 =
// RequestIdentity.effectiveUserAgent + 网络设置页 @StorageLink（写即持久化无保存键）。★ 刻意
// 不进工具查询白名单（get_app_preference）——UA 属可被提示注入利用的网络指纹。随备份走
export const PREF_USER_AGENT_KEY: string = 'prefUserAgent';

// 读值封装（RequestIdentity.effectiveUserAgent 取值侧消费）：未写入回退 '' = 用默认
export function getUserAgentPref(): string {
  return AppStorage.get<string>(PREF_USER_AGENT_KEY) ?? '';
}

// ── 网络设置域键 ──
// ★ 刻意不进工具查询白名单（get_app_preference）——与 UA 同属可被提示注入利用的网络指纹面。随备份走
//（★ 代理密码例外不落偏好，见代理段）。地址解析与消费单源在 common/providers/
// RequestIdentity.ets，本文件零 import 只持键与读封装。

// 请求读超时档位（分钟）：只作用于聊天流式链（ChatStreamBase readTimeout = 两次增量间隔上限
// 语义）；档位白名单 {5,10,20}，默认 10 = 现行 600s（存量零回归）。ChatStreamBase 起流前现读；
// 小任务/搜索/WebDAV 链各自分档刻意不吃本键
export const PREF_NET_READ_TIMEOUT_MIN_KEY: string = 'prefNetReadTimeoutMin';

// 档位白名单与默认（UI 分段三档与钳制共引——改档位只改这里，禁两处各写一份）
export const NET_READ_TIMEOUT_MINUTES: number[] = [5, 10, 20];
export const NET_READ_TIMEOUT_MINUTES_DEFAULT: number = 10;

// 档位钳制（非白名单值 → 10；老备份或手工改值防呆）。UI 与取值侧共引
export function clampNetReadTimeoutMinutes(value: number): number {
  return NET_READ_TIMEOUT_MINUTES.includes(value) ? value : NET_READ_TIMEOUT_MINUTES_DEFAULT;
}

// 读值封装（ChatStreamBase 起流前现读）：未写入回默认 10，越界经钳制收进白名单
export function netReadTimeoutMinutes(): number {
  const raw: number | undefined = AppStorage.get<number>(PREF_NET_READ_TIMEOUT_MIN_KEY);
  return raw === undefined ? NET_READ_TIMEOUT_MINUTES_DEFAULT : clampNetReadTimeoutMinutes(raw);
}

// 代理模式三档：'system' = 跟随系统（默认，请求不写 usingProxy 字段）/ 'direct' = 直连
//（usingProxy: false）/ 'custom' = 自定义地址（解析 PREF_NET_PROXY_ADDR_KEY 传 {host, port}）。
// 非三值一律钳 'system'
export const PREF_NET_PROXY_MODE_KEY: string = 'prefNetProxyMode';
export const NET_PROXY_MODE_SYSTEM: string = 'system';
export const NET_PROXY_MODE_DIRECT: string = 'direct';
export const NET_PROXY_MODE_CUSTOM: string = 'custom';

// 模式白名单钳制（direct/custom 原样回，'system' 与一切非法值归 'system'）
export function clampNetProxyMode(value: string): string {
  return value === NET_PROXY_MODE_DIRECT || value === NET_PROXY_MODE_CUSTOM ?
    value : NET_PROXY_MODE_SYSTEM;
}

// 读值封装（RequestIdentity.applyEffectiveProxy 取值侧消费）：未写入回 'system'
export function netProxyMode(): string {
  return clampNetProxyMode(AppStorage.get<string>(PREF_NET_PROXY_MODE_KEY) ?? '');
}

// 自定义代理地址（'host:port' 文本；'' = 未填）。解析判据单源 = RequestIdentity.
// parseNetProxyAddr（UI 输入校验与取值侧同函数，双端口径一致——UA 双端净化同款红线）
export const PREF_NET_PROXY_ADDR_KEY: string = 'prefNetProxyAddr';

// 读值封装（同上）：未写入回 ''
export function getNetProxyAddr(): string {
  return AppStorage.get<string>(PREF_NET_PROXY_ADDR_KEY) ?? '';
}

// 代理协议类型（custom 档内生效）：'http' = HTTP 代理（默认，存量语义，写 usingProxy）/
// 'socks5' = SOCKS5 代理（写 usingSocks5Proxy，API 26 起原生字段）。★ 两字段官方注勿同配
//（SOCKS5 优先）——互斥写侧单源在 RequestIdentity.applyEffectiveProxy
export const PREF_NET_PROXY_TYPE_KEY: string = 'prefNetProxyType';
export const NET_PROXY_TYPE_HTTP: string = 'http';
export const NET_PROXY_TYPE_SOCKS5: string = 'socks5';

// 类型白名单钳制（'socks5' 原样回，'http' 与一切非法值归 'http'；老备份/手改防呆）
export function clampNetProxyType(value: string): string {
  return value === NET_PROXY_TYPE_SOCKS5 ? value : NET_PROXY_TYPE_HTTP;
}

// 读值封装（RequestIdentity.applyEffectiveProxy 取值侧消费）：未写入回 'http'
export function netProxyType(): string {
  return clampNetProxyType(AppStorage.get<string>(PREF_NET_PROXY_TYPE_KEY) ?? '');
}

// 代理认证账号（custom 档账号密码认证的 username；'' = 未填 = 不认证）。★ 密码不落偏好——
// 只进 Asset（别名 aic.proxy.password，KeyStore.loadProxyPassword 族），随备份走的是账号不是密码
export const PREF_NET_PROXY_USER_KEY: string = 'prefNetProxyUser';

// 读值封装（同上）：未写入回 ''
export function getNetProxyUser(): string {
  return AppStorage.get<string>(PREF_NET_PROXY_USER_KEY) ?? '';
}

// 绕过列表：多行文本，每行一个域名或 IP，命中的请求目标不走代理直连——写进 HttpProxy /
// Socks5Proxy 的 exclusionList 平台原生字段（官方匹配规则：域名按标签级部分/精确匹配、IP
// 精确、单个 * 通配且必须独立成表；网段写法不在官方承诺内，UI 文案不承诺）。'' = 无绕过
export const PREF_NET_PROXY_BYPASS_KEY: string = 'prefNetProxyBypass';

// 绕过列表上限（宪法数据有界：行数与单行长度封顶防无界增长；253 = 域名规范长度上限）
export const NET_PROXY_BYPASS_MAX_LINES: number = 64;
export const NET_PROXY_BYPASS_LINE_MAX: number = 253;

// 拆行净化（纯函数，UI 回显与取值侧共引）：剔 \r 防混行 → 按 \n 分割 → 逐行 trim 去空行
// → 单行越界截断 → 整表行数封顶。行内容不校验不删——写侧零准入（非法行平台匹配自不会命中，
// UI 侧校验反而制造合法改动假红）
export function splitNetProxyBypassLines(raw: string): string[] {
  const lines: string[] = [];
  if (raw === '') {
    return lines;
  }
  const parts: string[] = raw.replace(/\r/g, '').split('\n');
  for (const part of parts) {
    const line: string = part.trim();
    if (line === '') {
      continue;
    }
    lines.push(line.length > NET_PROXY_BYPASS_LINE_MAX ?
      line.substring(0, NET_PROXY_BYPASS_LINE_MAX) : line);
    if (lines.length >= NET_PROXY_BYPASS_MAX_LINES) {
      break;
    }
  }
  return lines;
}

// 读值封装（RequestIdentity.applyEffectiveProxy 取值侧消费）：未写入回 []
export function getNetProxyBypassLines(): string[] {
  return splitNetProxyBypassLines(AppStorage.get<string>(PREF_NET_PROXY_BYPASS_KEY) ?? '');
}

// ── HTTP 请求工具域键 ──
// ★ 与另两处超时**刻意分链**：本键只封 http_request 工具单次请求的等待上限（秒级四档）——
// PREF_NET_READ_TIMEOUT_MIN_KEY 管聊天流式链（分钟档）、PREF_SEARCH_TIMEOUT_SEC_KEY 管搜索
// 与抓取链（秒档），三键互不读写。★ 刻意不进工具查询白名单（get_app_preference）——与 UA / 代理同属
// 网络出口参数。随备份走
export const PREF_HTTP_TIMEOUT_CEILING_MS_KEY: string = 'prefHttpTimeoutCeilingMs';

// 档位白名单与默认（UI 分段与钳制共引，改档位只改这里；默认 60 秒——默认档下模型不传
// timeout_ms 时生效值 min(30s, 60s) = 30 秒，与放开前行为逐字一致，存量零回归）
export const HTTP_TIMEOUT_CEILING_MS: number[] = [30000, 60000, 120000, 180000];
export const HTTP_TIMEOUT_CEILING_MS_DEFAULT: number = 60000;

// 档位钳制（非白名单值 → 60000；老备份或手工改值防呆）。UI 与取值侧共引
export function clampHttpTimeoutCeilingMs(value: number): number {
  return HTTP_TIMEOUT_CEILING_MS.includes(value) ? value : HTTP_TIMEOUT_CEILING_MS_DEFAULT;
}

// 读值封装（ToolHttp 每请求现读——改档下一请求生效）：未写入回默认 1 分钟，越界经钳制
export function httpTimeoutCeilingMs(): number {
  const raw: number | undefined = AppStorage.get<number>(PREF_HTTP_TIMEOUT_CEILING_MS_KEY);
  return raw === undefined ? HTTP_TIMEOUT_CEILING_MS_DEFAULT : clampHttpTimeoutCeilingMs(raw);
}

// 同域请求间隔档：同一域名两次出站请求的最小间隔（毫秒）；0 = 关闭限速。★ 上游
// Retry-After 驱动的域名级熔断不受本键影响（恒生效——对方明示的信号，不是本机节奏偏好）。
// 默认 1 秒 = **有意选择非疏忽**（照 PREF_AUTO_RETRY_KEY 同款论证）：同域并发多发调用会被
// 挡下一次——回执带 retriable 与等待秒数，下一轮立即可重试；默认关则功能等于白做（保护面 =
// 跑飞的工具轮不会把对方服务打挂）。★ 刻意不进工具查询白名单（get_app_preference）（网络出口参数，
// 同纪律）。随备份走
export const PREF_HTTP_HOST_INTERVAL_MS_KEY: string = 'prefHttpHostIntervalMs';

// 档位白名单与默认（UI 分段四档与钳制共引——改档位只改这里，禁两处各写一份）
export const HTTP_HOST_INTERVAL_MS: number[] = [0, 500, 1000, 2000];
export const HTTP_HOST_INTERVAL_MS_DEFAULT: number = 1000;

// 档位钳制（非白名单值 → 1000；老备份或手工改值防呆）。UI 与取值侧共引
export function clampHttpHostIntervalMs(value: number): number {
  return HTTP_HOST_INTERVAL_MS.includes(value) ? value : HTTP_HOST_INTERVAL_MS_DEFAULT;
}

// 读值封装（ToolHttp 每请求现读——改档下一请求生效）：未写入回默认 1 秒，越界经钳制
export function httpHostIntervalMs(): number {
  const raw: number | undefined = AppStorage.get<number>(PREF_HTTP_HOST_INTERVAL_MS_KEY);
  return raw === undefined ? HTTP_HOST_INTERVAL_MS_DEFAULT : clampHttpHostIntervalMs(raw);
}

// ── 会话上下文用量·校准系数（★ 2026-10-24 缓存统计案 U2 起双键）──
// k = 真实输入 token ÷ 发送时本地估算，按 (providerId+modelId) 双键分键——k 是「服务商×模型」
// 分词口径的属性不是会话属性，跨会话共享；同模型名跨服务商分词可能不同，单键 modelId 会串 k。
// ★ 双键精确匹配、'' 不作通配回退——旧格式条目（providerId=''，legacy）解析保留不丢，但读侧
// 对真实服务商 id 永不匹配 → 存量 k 惰性化、由 LRU 自然淘汰；写侧 upsert 顺手清退同模型
// legacy 条。不做 '' 兜底复用（兜底 = 把串 k 缺陷为存量保留）。持久层 = string 键承载 JSON 数组
// [{providerId, modelId, factor}]（最近使用在前——对象键名动态增删在 ArkTS 禁 delete，数组序
// 即 LRU 序）。条数上限 CTX_FACTOR_MAX_ENTRIES 防无界增长（宪法数据有界，超出丢最旧，LRU
// 淘汰兜底）。解析/序列化/查找/前插均纯函数（零 import 保持——scripts/sse-assert.mjs 复制
// 直跑）；写侧唯一 = 流回调锚点校准点 recordAnchor，读侧 = 会话页活算
export const PREF_CTX_FACTOR_KEY: string = 'prefCtxFactor';
export const CTX_FACTOR_MAX_ENTRIES: number = 20;

// 单条系数记录（providerId = 所属服务商 id + modelId = provider_models.modelId 原串；双键精确
// 匹配；providerId='' = 旧格式条目〔legacy，U2 前落键的存量 k〕）
export interface CtxFactorEntry {
  providerId: string;
  modelId: string;
  factor: number;
}

// 解析（容错：坏 JSON / 非数组 / 元素缺 modelId / factor 非有限正数——逐条丢弃不抛错；
// ★ 缺/坏 providerId 的旧格式条目降级为 providerId='' 保留——防线只挡坏值不挡旧值）
export function parseCtxFactors(json: string): CtxFactorEntry[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const entries: CtxFactorEntry[] = [];
  for (const item of raw) {
    const rec = item as Record<string, Object>;
    const providerId: Object | undefined = rec['providerId'];
    const modelId: Object | undefined = rec['modelId'];
    const factor: Object | undefined = rec['factor'];
    if (typeof modelId === 'string' && modelId !== '' && typeof factor === 'number' &&
      Number.isFinite(factor) && factor > 0) {
      const pid: string = typeof providerId === 'string' ? providerId : '';
      entries.push({ providerId: pid, modelId: modelId, factor: factor });
    }
  }
  return entries;
}

// 查 (服务商,模型) 系数（双键精确匹配，'' 不作通配——legacy 条目对真实服务商 id 永不命中；
// 无记录/不合法回 1.0 = 纯估算态）
export function lookupCtxFactor(entries: CtxFactorEntry[], providerId: string,
  modelId: string): number {
  for (const e of entries) {
    if (e.providerId === providerId && e.modelId === modelId) {
      return e.factor;
    }
  }
  return 1;
}

export function serializeCtxFactors(entries: CtxFactorEntry[]): string {
  return JSON.stringify(entries);
}

// 前插更新（同双键旧条剔除、新条置顶 = 最近使用；★ 顺手清退同 modelId 的 legacy 条
//〔providerId===''〕——防占 CTX_FACTOR_MAX_ENTRIES 的 LRU 死名额；超上限丢尾）。factor
// 不合法原样返回（带毒锚点不落盘——第二道闸）
export function upsertCtxFactor(entries: CtxFactorEntry[], providerId: string, modelId: string,
  factor: number): CtxFactorEntry[] {
  if (modelId === '' || !Number.isFinite(factor) || factor <= 0) {
    return entries;
  }
  const next: CtxFactorEntry[] = [{ providerId: providerId, modelId: modelId, factor: factor }];
  for (const e of entries) {
    const sameKey: boolean = e.providerId === providerId && e.modelId === modelId;
    const legacySameModel: boolean = e.providerId === '' && e.modelId === modelId;
    if (!sameKey && !legacySameModel) {
      next.push(e);
    }
  }
  return next.slice(0, CTX_FACTOR_MAX_ENTRIES);
}

// 读值封装（会话页活算消费）：未写入回 1.0（与「无该 (服务商,模型) 系数」同语义）
export function currentCtxFactor(providerId: string, modelId: string): number {
  return lookupCtxFactor(parseCtxFactors(AppStorage.get<string>(PREF_CTX_FACTOR_KEY) ?? ''),
    providerId, modelId);
}

// 写值封装（recordAnchor 锚点校准点消费）：整键覆盖写（禁局部拼串——「JSON 串结构化键」立规）
export function saveCtxFactor(providerId: string, modelId: string, factor: number): void {
  const next: CtxFactorEntry[] =
    upsertCtxFactor(parseCtxFactors(AppStorage.get<string>(PREF_CTX_FACTOR_KEY) ?? ''),
      providerId, modelId, factor);
  AppStorage.setOrCreate<string>(PREF_CTX_FACTOR_KEY, serializeCtxFactors(next));
}

// 偏好键注册完成标记（AppStorage 进程内一次性信号，**非持久键**——不 persistProp、不进白名单）：
// EntryAbility loadContent 回调 persistProp 区末尾置 1。★ 需要「一次性读持久值」的消费方不应赌
//「persistProp 注册早于页面组件实例化」——该时序只是项目注释里的推断（坑17 原文只引官方
//「loadContent 回调被调用时」），而 loadContent 的 d.ts 反注「回调内当前 UI 的执行上下文可能
// 不明确」，一旦推断为假，一次性现读会拿到缺省值 = 设置静默失效。消费姿势 =
// `@StorageProp(PREF_LOADED_KEY) @Watch(...)`：键变 = 磁盘值已落 AppStorage，此时现读任何偏好键
// 都拿到持久值。当前消费方 = HomeNavigation（启动进入页面冷启动首帧判定）+ ProactiveGen
//（冷启动闸：未放行则置挂起标记）
export const PREF_LOADED_KEY: string = 'prefLoaded';

// ── 联网搜索域键 ──
// ★ 立规「JSON 串结构化键」（本文件首例，后续结构化偏好照此办理）：持久层仍是 string 键，值
// 承载 JSON 串；读值一律经 parse 封装（坏 JSON 容错回空态，禁裸 JSON.parse 散落消费方）；
// 写值一律经 serialize 封装（整键覆盖写，禁局部拼串）。明文红线：本域只存 hasKey 布尔标记，
// API Key 明文只进 Asset（KeyStore saveSearchEngineKey 族）——禁把密钥写进键。数组型偏好另有
// 原生 string[] 形态（对象数组禁止持久化，一维 string[] 可）。引擎 id 与结构常量单一来源 =
// common/search/SearchEngineRegistry.ets。★ 联网搜索总开关键已退役（2026-10-01，
// PREF_SEARCH_SERVICE_ENABLED_KEY 与 isSearchServiceEnabled 同笔删除）：全局恒开——是否联网
// 由助手工具页「联网搜索」卡开关 ∩ 会话内「联网」开关两源合取决定；旧布尔键不再注册、不入
// 备份键表，存量落盘值成无人读写的孤儿，无害。

// 当前搜索引擎 id（默认 'bing_local'；存用户手选，实际生效值经注册表 fallback 链
// resolveEngineId 兜底）
export const PREF_SEARCH_ENGINE_KEY: string = 'prefSearchEngine';

export function getSearchEngineId(): string {
  return AppStorage.get<string>(PREF_SEARCH_ENGINE_KEY) ?? 'bing_local';
}

// 启用引擎清单（原生 string[] 持久；注册默认 = 注册表全量 id〔EntryAbility 经
// ALL_SEARCH_ENGINE_IDS 引入〕；空数组 = 用户显式全关，fallback 链兜 bing_local——读值不做
// 默认展开，语义判读在域内）
export const PREF_SEARCH_ENABLED_ENGINES_KEY: string = 'prefSearchEnabledEngines';

export function getSearchEnabledEngineIds(): string[] {
  const raw: string[] | undefined = AppStorage.get<string[]>(PREF_SEARCH_ENABLED_ENGINES_KEY);
  return raw === undefined ? [] : raw;
}

// 引擎配置 JSON 串（{engineId:{baseUrl,hasKey}}；'' = 全默认。hasKey 只是 UI 标记，明文只在
// Asset）。解析/序列化与读封装在 SearchEngineRegistry.ets（域内聚——本文件只持键常量与兜底读值）
export const PREF_SEARCH_ENGINE_CFG_KEY: string = 'prefSearchEngineCfg';

export function getSearchEngineCfgJson(): string {
  return AppStorage.get<string>(PREF_SEARCH_ENGINE_CFG_KEY) ?? '';
}

// 抓取引擎（值域 = 'local' | 引擎 id，兜底 'local'）：'local' = 本地 HTTP 抓取（免费默认）；
// 引擎 id = 该引擎的抓取 API（当前仅 deepseek）。未配置密钥/引擎停用/抓取失败由 dispatchScrape
// 回落本地——回落不算错，本地抓取是既有零配置通路。与搜索键解耦：搜索与抓取可各选不同引擎；
// 同一引擎共用一把密钥与同一条配置条目
export const PREF_SEARCH_FETCH_ENGINE_KEY: string = 'prefSearchFetchEngine';

export function getSearchFetchEngineId(): string {
  return AppStorage.get<string>(PREF_SEARCH_FETCH_ENGINE_KEY) ?? 'local';
}

// ── DeepSeek 服务商域键（DS 全家桶接入批；常量+getter 登记面先例 = PREF_MERMAID_INLINE_KEY
// 五处：本件 → EntryAbility persistProp → AppPreferencesBackup 备份表 → assert-feature-domain
// 54 组计数钉 → assert-ds-integration 直跑）──

// 官方联网档偏好（代决 1 = DS 会话默认走官方搜索）：true = DS 会话联网开时由 DeepSeek
// 官方服务端执行（联网菜单「DeepSeek 官方」项选中态、默认）/ false = 用户改选了自带引擎
//（该会话回自带链；全局引擎键 PREF_SEARCH_ENGINE_KEY 原样保留自带引擎值——菜单哨兵 id
// 只在回调链流转、禁落任何持久层，判据单源 = DsServerTools.dsOfficialWebActive）。
// 消费面 = 发送侧声明 / 历史回传 / 附件分叉 / 联网卡右侧值与菜单勾选；唯一 UI 写点 =
// ChatSessionOverrideCtrl.pickWebEngine 分流。随备份走（用户行为偏好）
export const PREF_DS_OFFICIAL_WEB_KEY: string = 'prefDsOfficialWeb';

// 读值封装：未写入回退 true = 官方档默认开（`!== false` 姿势，仅防御，见文件头）
export function isDsOfficialWebPreferred(): boolean {
  return AppStorage.get<boolean>(PREF_DS_OFFICIAL_WEB_KEY) !== false;
}

// 文档服务端解析（拍板 8 = 带开关、不默认自动）：true = DS 会话发 PDF、Word、PPT 附件时
// 跳过本地解析，入列即上传 DeepSeek 服务端取 file_id（发送侧接线 = 任务书 S4）；false =
// 附件照常本地解析（默认 = 现状零回归）。设置面 = 会话设置面板「文档解析」行卡（仅 DS
// 会话渲染）；整批回退另有 DsServerTools.DS_SERVER_TOOLS_ENABLED kill switch（false 时
// 本键不参与判定 = 附件恒本地解析）
export const PREF_DS_DOC_SERVER_KEY: string = 'prefDsDocServer';

// 读值封装（S4 分叉判据现读）：未写入回退 false = 本地解析（`=== true` 姿势，仅防御）
export function isDsDocServerEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_DS_DOC_SERVER_KEY) === true;
}

// ── DS 全家桶二期两键（2026-11-14 决明拍板；登记面五处同 PREF_MERMAID_INLINE_KEY）──

// 官方会话标题三态（二期 #4）：'off' = 不带 title 字段、完全走现有 TitleGen / 'first' =
// 只在**本会话首个请求**带一次（缺省，官方建议档——零 5 秒等待）/ 'every' = 每轮带
//（每轮回复最多多等 5 秒，官方原文）。只对 DS 官方模型会话生效（判据 = isDsFlashConnection）。
// 入口 = 设置页 → 功能模型 → 标题生成卡内三档值行（会话设置面板不加）；随备份走
export const PREF_DS_TITLE_MODE_KEY: string = 'prefDsTitleMode';

export const DS_TITLE_MODE_OFF: string = 'off';
export const DS_TITLE_MODE_FIRST: string = 'first';
export const DS_TITLE_MODE_EVERY: string = 'every';

// 读值封装（起流咽喉点现读）：未写入/脏值一律回退 'first'（缺省真源仍在 persistProp 注册侧）
export function dsTitleMode(): string {
  const value: string | undefined = AppStorage.get<string>(PREF_DS_TITLE_MODE_KEY);
  if (value === DS_TITLE_MODE_OFF || value === DS_TITLE_MODE_EVERY) {
    return value;
  }
  return DS_TITLE_MODE_FIRST;
}

// 内容安全审核开关（二期 #6）：true = DS 官方请求带 safety_check:{"level":"high"} / false =
// 不带字段（缺省，决明拍板——关不等于「关闭审核」，官方未开启时声明联网工具也可能拒答）。
// 入口 = 偏好设置 →「输入与发送」页组卡内开关（会话设置面板不加）；随备份走
export const PREF_DS_SAFETY_CHECK_KEY: string = 'prefDsSafetyCheck';

// 读值封装（起流咽喉点现读）：未写入回退 false（`=== true` 姿势，仅防御）
export function isDsSafetyCheckEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_DS_SAFETY_CHECK_KEY) === true;
}
