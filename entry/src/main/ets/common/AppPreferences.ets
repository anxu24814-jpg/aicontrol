// 应用偏好持久键单一来源（2026-09-01 偏好设置页新建）：偏好设置页写、跨域消费（聊天
// 思考块等）——键常量 + 缺省值 + 读值封装集中本文件，防键名/缺省值散落漂移。
// 注册时机 = EntryAbility loadContent 成功回调 persistProp 区（坑17：必须在该回调注册，
// 早注册/晚注册都会导致写入不落盘或与组件初始化抢序）；消费方一律引用本文件常量，
// 禁裸字符串。命名口径：AppStorage 持久键 = 业务语义驼峰字符串（activeProvider 同族）。
// 2026-09-10 备份域并入（方案-偏好与密钥接入备份 §4.1/§4.2）：文件尾段新增「备份分域」
// ——偏好键两分类表（进备份 / 不进备份）+ 备份凭据登记块 + preferences.json 编解码纯
// 函数；本文件仍保持零 import（叶子模块，见尾段注释）。

// 默认展开思考（2026-09-01 偏好设置页首项）：true = 思考折叠块（ChatThinkingBlock）
// 初始展开；false = 默认收起（3 行截断，2026-08-27 拍板形态不变）。仅决定新渲染块的
// 初始态——不做运行时广播（已上屏块不回翻，手动展开/收起不被覆盖），重进会话/新消息生效
export const PREF_THINK_EXPAND_KEY: string = 'prefThinkExpand';

// 读值封装（消费方组件创建期调用一次）：键未写入时回退 false——persistProp 注册先于
// 任何页面组件实例化（loadContent 回调内），正常路径不会走到回退，仅防御
export function getThinkExpandDefault(): boolean {
  return AppStorage.get<boolean>(PREF_THINK_EXPAND_KEY) === true;
}

// 流式引擎选择（2026-09-02 Cube 动效渲染层移植主工程）：false = 自研引擎；true = 试验
// 引擎（Cube 移植，打字机动效 + 增量渲染，长文更流畅）。默认 true（同日真机六场景验收
// 后决明拍板切换）。偏好页开关写入，双引擎分流点现读（★ 2026-09-18 起分流点在
// chat/cube/CubeEngineCtrl：节流/动效 = cube.feed 分流；传输/解析 = cube.createStream，
// 两分支现同走原生协议流工厂）
export const PREF_STREAM_ENGINE_KEY: string = 'prefStreamEngine';

// 读值封装（分流点发送链现读）：未写入回退 true = 实验引擎（与 persistProp
// 注册默认同源；正常路径注册先于任何读取，回退仅防御）
export function isCubeEngineEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_STREAM_ENGINE_KEY) !== false;
}

// 流式输出自动跟随（2026-09-02 偏好设置页第 3 项）：true = AI 输出时消息列表自动滚动
// 跟随到底部（现状）；false = 停在当前位置不自动滚，需重新开启开关才恢复跟随。仅约束流式
// 增量的自动滚底（maybeFollow），手动动作（发送强制滚底 forceToBottom）不受
// 开关影响。默认 true = 现状行为，存量零回归。偏好页开关写入，ChatFollowController
// maybeFollow 现读（AppStorage 每次现读 = 切换即时生效，无需广播）
export const PREF_STREAM_FOLLOW_KEY: string = 'prefStreamFollow';

// 读值封装（ChatFollowController.maybeFollow 滚底前现读）：未写入回退 true = 跟随
//（与 persistProp 注册默认同源；正常路径注册先于任何页面实例化，回退仅防御）
export function isStreamAutoFollow(): boolean {
  return AppStorage.get<boolean>(PREF_STREAM_FOLLOW_KEY) !== false;
}

// 键盘发送（2026-09-03 偏好设置页第 4 项，决明指令「华为官方键盘发送」）：true = 会话页
// 输入框键盘右下角换行键替换为发送键（点击 onSubmit 直接发送，与胶囊发送键同语义）；
// false = 换行键（默认，TextArea.enterKeyType 官方默认值一致）。★ 长短按区分 = 系统键盘
// 行为，官方 API 只控制回车键形态（text_area.d.ts enterKeyType 实锤），无法保证「长按换行」
// 消费方 = ChatInputBar @StorageProp 订阅（开关切换即刷）。默认 false = 现状行为零回归
export const PREF_KEYBOARD_SEND_KEY: string = 'prefKeyboardSend';

// 会话页屏幕常亮（2026-09-04 偏好设置页第 5 项，决明指令「会话页保持屏幕常亮」）：true =
// 进入会话页设窗口常亮（window.setWindowKeepScreenOn(true)，窗口级属性无需权限）/ false =
// 系统息屏（默认，现状零回归）。消费方 = ChatPage aboutToAppear 现读、aboutToDisappear
// 无条件复位 false（成对：退出会话页必恢复系统息屏，@ohos.window d.ts 官方限制条目
// 「退出场景后须设回 false」）。默认关 = 存量行为零回归
export const PREF_KEEP_SCREEN_ON_KEY: string = 'prefKeepScreenOn';

// 读值封装（ChatPage.aboutToAppear 调用一次）：未写入回退 false——persistProp 注册先于
// 任何页面组件实例化（loadContent 回调内），正常路径不会走到回退，仅防御
export function isKeepScreenOnEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_KEEP_SCREEN_ON_KEY) === true;
}

// 会话时间显示（2026-09-04 偏好设置页第 6 项，决明指令「对话历史时间显示开关」）：true =
// 会话列表卡片显示最后消息时间（现状）/ false = 只隐藏时间文本——记录不删、updatedAt
// 照常维护，重开开关即恢复显示（纯显示层开关，零数据链路影响）。消费方 = ChatSessionList
// SessionCardItem @StorageProp 自订阅（切换即刷，坑16 正解）。默认 true = 现状零回归
export const PREF_SESSION_TIME_KEY: string = 'prefSessionTime';

// 读值封装（语义参照 isCubeEngineEnabled 的 `!== false` 姿势——本键默认开；persistProp
// 注册先于任何页面组件实例化，正常路径不会走到回退，仅防御）
export function isSessionTimeVisible(): boolean {
  return AppStorage.get<boolean>(PREF_SESSION_TIME_KEY) !== false;
}

// 会话图标显示（2026-09-19 偏好设置页·阅读与会话组第 3 行，决明指令「对话历史卡新增消息
// 图标显隐开关」）：true = 会话列表卡片左侧显示消息图标（默认，现状）/ false = 图标不显示
// ——标题内容随之左移，纯显示层开关，数据链路零影响。消费方 = ChatSessionList
// SessionCardItem @StorageProp 自订阅（官方 HdsListItemCard prefixItem 传 undefined〔d.ts
// 可空实锤〕+ 回退自制卡条件渲染，切换即刷，与 PREF_SESSION_TIME_KEY 同款契约）。默认
// true = 现状零回归
export const PREF_SESSION_ICON_KEY: string = 'prefSessionIcon';

// 读值封装（`!== false` 姿势——本键默认开；persistProp 注册先于任何页面组件实例化，
// 正常路径不会走到回退，仅防御）
export function isSessionIconVisible(): boolean {
  return AppStorage.get<boolean>(PREF_SESSION_ICON_KEY) !== false;
}

// 生物识别方式（2026-09-05 偏好设置页第 8 项，决明指令「偏好设置中选择人脸或指纹，选定
// 后只用一种，取消自动回退」）：true = 人脸识别（默认——真机实测人脸链路已通）/ false =
// 指纹识别。消费方 = BiometricGate 认证发起时现读（AppStorage 每次现读 = 切换即时生效，
// 下次认证即新方式）；系统弹窗内失败重试恒为选定类型（官方弹窗行为——authType 单类型
// 只呈现该类型重试，换方式在偏好设置切换）
export const PREF_BIOMETRIC_FACE_KEY: string = 'prefBiometricFace';

// 读值封装（BiometricGate 发起前现读）：未写入回退 true = 人脸（与 persistProp 注册默认
// 同源；正常路径注册先于任何读取，回退仅防御）
export function isBiometricFacePreferred(): boolean {
  return AppStorage.get<boolean>(PREF_BIOMETRIC_FACE_KEY) !== false;
}

// 背景仅用于会话页（2026-09-05 外观显示页背景面板新增开关卡，决明指令「背景页恢复默认
// 卡上新增一卡」）：true = 自定义背景只在会话页（对话页）显示，其余页面（一级页/二级页/
// 平板分栏铺底）用默认官方底色；false = 全应用生效（默认，现状零回归）。消费方 =
// PageBackground @StorageProp 订阅 + sessionPage 参数（ChatPage 经 PageShell 传入 true）
// 组合判定——开关切换即刷（@Watch 重拉），无运行时广播。抑制实例显示纯色但维持
// BgCache 与当前 pageBg 对齐（预热 + 恢复默认清空，见 PageBackground.ets 头注释），
// 背景图文件与换图/恢复默认链路零改动
export const PREF_BG_SESSION_ONLY_KEY: string = 'prefBgSessionOnly';

// 页签切换动画（2026-09-08 偏好设置页第 9 项，决明指令「偏好设置加切换开关」）：true =
// 一级页底部页签点击切换带横向滑动动画（animationDuration 300 = 官方通用默认时长）；
// false = 点按直达、无过渡动画（animationDuration 0）。默认 true = 2026-09-08 决明
// 拍板开回的现状零回归。消费方 = HomeNavigation @StorageProp 订阅（状态驱动重渲染即刷，
// 无广播需求，与流式引擎开关同款契约）
export const PREF_TAB_SWITCH_ANIM_KEY: string = 'prefTabSwitchAnim';

// 启动进入页面（2026-09-08 偏好设置页第 10 项，决明指令「启动时默认进入新对话或对话一级
// 页，样式参考生物识别方式的分段胶囊」）：true = 冷启动直接进入一个新对话（懒创建不落库，
// 首条消息才建行——同标题栏「＋」语义；会话所属助手 = 当前助手 ACTIVE_ASSISTANT_KEY，即
// 上次选定的那个，无行新会话归属兜底见 ChatPromptState.effectiveAssistantId）/ false =
// 进入对话一级页（会话列表，默认 = 现状零回归）。消费方 = HomeNavigation.aboutToAppear
// 现读一次（仅冷启动首帧生效，后台回前台不重进——组件不重建；切换开关下次启动生效，
// 无广播需求）
export const PREF_LAUNCH_NEW_CHAT_KEY: string = 'prefLaunchNewChat';

// 读值封装（HomeNavigation.aboutToAppear 调用一次）：未写入回退 false——persistProp 注册
// 先于任何页面组件实例化（loadContent 回调内），正常路径不会走到回退，仅防御
export function isLaunchNewChatEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_LAUNCH_NEW_CHAT_KEY) === true;
}

// 价格卡收起态（2026-09-17 价格卡折叠记忆笔，决明报障「收起状态保存后无法记忆」）：true =
// 模型编辑页价格卡默认收起为「主副标题两行短卡」/ false = 默认展开（存量行为零回归）。
// ★ 与其他偏好不同，本键**不在偏好设置页暴露**——由用户在卡片标题行点收起/展开时经
// @StorageLink 双向绑定隐式写入（一写即落盘，无需点保存、无需退出页面），故无设置页行、
// 无搜索注册、无帮助条目（界面行为不入帮助）。换机随备份走（纯界面展示偏好，与
// PREF_THINK_EXPAND_KEY 同类）。★ 消费方 = ModelPriceCard @StorageLink collapsed——
// 价格模板编辑页复用同一张卡但 collapsible=false，判定带能力守卫：读到的全局值不影响其
// 渲染（恒展开），它也不会写入
export const PREF_PRICE_CARD_COLLAPSED_KEY: string = 'prefPriceCardCollapsed';

// 浏览高危操作自动通过（2026-09-18 浏览高危确认降压阀笔，决明拍板「拍板按你」——04 专题档
// §五·2 预留的第二道全局降压阀落地）：false = 每次确认（默认，存量零回归——browse_act 高危
// 动作弹确认卡征求同意）/ true = 自动通过（预检直接判无需确认，高危动作与读向动作同路并行
// 执行）。消费方 = ToolBrowseAct 预检早退 + 执行器高危分支两闸现读（AppStorage 每次现读 =
// 切换即时生效，下一个动作按新值；已弹出的确认卡仍需作答）。刻意不进 set_app_preference
// 白名单——防提示注入翻转安全设置（ToolPref 头注原则）
export const PREF_BROWSE_AUTO_APPROVE_KEY: string = 'prefBrowseAutoApprove';

// 读值封装（ToolBrowseAct 两闸现读）：未写入回退 false = 每次确认——persistProp 注册先于
// 任何页面组件实例化，正常路径不会走到回退，仅防御
export function isBrowseAutoApproveEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_BROWSE_AUTO_APPROVE_KEY) === true;
}

// HTTP 写操作自动通过（2026-09-20 HTTP 请求独立域笔，决明拍板「设置页可控制权限授予之类 →
// 写方法确认档」）：false = 每次确认（默认，存量零回归——http_request 写方法
// POST/PUT/DELETE/PATCH 弹确认卡征求同意）/ true = 自动通过（预检首行早退回空串，写请求与
// 读方法同路直发）。消费方 = ToolHttp.httpRequestNeedsConfirm 预检现读（AppStorage 每次现读
// = 切换即时生效，下一个请求按新值；已弹出的确认卡仍需作答；执行器侧无第二道判据——本件
// 不带批准戳）。刻意不进 set_app_preference 白名单——防提示注入翻转安全设置（PREF_BROWSE_
// AUTO_APPROVE_KEY 同款纪律）
export const PREF_HTTP_WRITE_AUTO_APPROVE_KEY: string = 'prefHttpWriteAutoApprove';

// 读值封装（ToolHttp 预检现读）：未写入回退 false = 每次确认——persistProp 注册先于任何页面
// 组件实例化，正常路径不会走到回退，仅防御
export function isHttpWriteAutoApproveEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_HTTP_WRITE_AUTO_APPROVE_KEY) === true;
}

// 网络自动重试（2026-09-22 聊天自动重试笔）：true = 请求因网络原因失败且**本轮尚无任何内容
// 产出**时自动退避重发同一请求，最多 3 次（2/4/8 秒），期间助手气泡内显示次数状态行、用户
// 可随时停止；false = 不自动重试，维持手动点底栏重试键的现状。★ 只覆盖网络层失败与零产出
// 两种条件同时成立的情形——中途断流（屏上已有内容）与 401/403/429（归 Key 池换钥）都不自动
// 重试，判据单源见 ChatAutoRetryCtrl。
// ★ 默认 true = **有意选择非疏忽**（越出「默认 = 现状零回归」惯例）：本键只在「零产出的网络
// 失败」触发，重试耗尽仍走原失败路径，风险面极低；默认关则绝大多数用户永不会打开，功能等于
// 白做（与 RikkaHub enableAutoRetry 默认开的取向一致）。消费方 = ChatAutoRetryCtrl 判据经
// ChatAutoRetryHost.isAutoRetryEnabled 回接宿主现读；开关值在轮首现读一次、轮内锁定（照
// CubeEngineCtrl「开关现读一次，轮内行为不随开关中途切换」同口径），故切换下一条消息生效
export const PREF_AUTO_RETRY_KEY: string = 'prefAutoRetry';

// 读值封装（自动重试域判据现读）：未写入回退 true = 自动重试（与 persistProp 注册默认同源；
// 正常路径注册先于任何页面组件实例化，回退仅防御）
export function isAutoRetryEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_AUTO_RETRY_KEY) !== false;
}

// 粘贴长文本转文件（2026-09-23 任务书-长文本粘贴转文件-20260923）：true = 会话页输入栏粘贴
// 的文本长度达到阈值时**不插进输入框**，而是落盘成一个 .txt 附件挂进待发附件条（显示名
// 粘贴_<时间戳>.txt，发送方式与其他附件相同）；false = 功能整体失效，任何粘贴照常插入。
// ★ 默认 true = 有意选择非疏忽：粘贴件只是换个位置出现（内容一字不丢；附件满或失败时文本
// 回退到输入框），默认关则绝大多数用户永不会打开（与 RikkaHub enablePasteAsFile 同取向）。
// 消费方 = ChatInputBar @StorageProp 自订阅（偏好页切换即刷，坑16 正解）
export const PREF_PASTE_AS_FILE_KEY: string = 'prefPasteAsFile';

// 粘贴转文件的长度阈值（字符数）：粘贴文本长度 **≥ 本值** 才转成附件，短文本照常插入。
// 默认 2000 = 「一段话」与「一整篇」的常见分界（手机上 2000 字已明显占满输入框，插入后
// 难读难改）。取值域 1000~20000、步进 500，读取侧一律经 clampPasteThreshold 钳位——老备份
// 或手工改值可能越界，越界值会让滑块停在异常位置且判定静默失效。消费方同上一键
export const PREF_PASTE_AS_FILE_THRESHOLD_KEY: string = 'prefPasteAsFileThreshold';

// 阈值域三量与默认值（滑块 min/max/step 与钳位共引——改域只改这里，禁两处各写一份）
export const PASTE_THRESHOLD_MIN: number = 1000;
export const PASTE_THRESHOLD_MAX: number = 20000;
export const PASTE_THRESHOLD_STEP: number = 500;
export const PASTE_THRESHOLD_DEFAULT: number = 2000;

// 阈值钳位（非有限数或越界 → 回默认；域内值取整原样回）。读取侧取值一律经本函数
export function clampPasteThreshold(value: number): number {
  if (!Number.isFinite(value)) {
    return PASTE_THRESHOLD_DEFAULT;
  }
  return Math.min(Math.max(Math.round(value), PASTE_THRESHOLD_MIN), PASTE_THRESHOLD_MAX);
}

// ── 会话上下文用量·校准系数（2026-09-17 方案-会话上下文用量执行笔）──
// k = 真实输入 token ÷ 发送时本地估算（calibrateFactor 钳制 [0.2, 5]，异常回 1），按模型名
// 分键——k 是模型分词口径的属性不是会话属性，跨会话共享（方案 §4.2）。持久层 = string 键
// 承载 JSON 数组 [{modelId, factor}]（最近使用在前；「JSON 串结构化键」模式，见联网搜索域
// 立规——对象键名动态增删在 ArkTS 禁 delete，数组序即 LRU 序）。条数上限
// CTX_FACTOR_MAX_ENTRIES 防无界增长（宪法数据有界；超出丢最旧）。解析/序列化/查找/前插均
// 纯函数（零 import 保持——scripts/sse-assert.mjs 120 组复制直跑）；AppStorage 读写封装照
// 本文件既有姿态（写侧唯一 = ChatSendCtrl 锚点校准点，读侧 = 会话页活算）
export const PREF_CTX_FACTOR_KEY: string = 'prefCtxFactor';
export const CTX_FACTOR_MAX_ENTRIES: number = 20;

// 单条系数记录（modelId = provider_models.modelId 原串）
export interface CtxFactorEntry {
  modelId: string;
  factor: number;
}

// 解析（容错：坏 JSON / 非数组 / 元素缺字段 / factor 非有限正数——逐条丢弃不抛错，
// parsePrefBackup 范式）
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
    const modelId: Object | undefined = rec['modelId'];
    const factor: Object | undefined = rec['factor'];
    if (typeof modelId === 'string' && modelId !== '' && typeof factor === 'number' &&
      Number.isFinite(factor) && factor > 0) {
      entries.push({ modelId: modelId, factor: factor });
    }
  }
  return entries;
}

// 查模型系数（无记录 / 记录不合法回 1.0 = 纯估算态）
export function lookupCtxFactor(entries: CtxFactorEntry[], modelId: string): number {
  for (const e of entries) {
    if (e.modelId === modelId) {
      return e.factor;
    }
  }
  return 1;
}

export function serializeCtxFactors(entries: CtxFactorEntry[]): string {
  return JSON.stringify(entries);
}

// 前插更新（同模型旧条剔除、新条置顶 = 最近使用；超上限丢尾）。factor 不合法原样返回
//（带毒锚点不落盘——calibrateFactor 成品恒合法，此为第二道闸）
export function upsertCtxFactor(entries: CtxFactorEntry[], modelId: string,
  factor: number): CtxFactorEntry[] {
  if (modelId === '' || !Number.isFinite(factor) || factor <= 0) {
    return entries;
  }
  const next: CtxFactorEntry[] = [{ modelId: modelId, factor: factor }];
  for (const e of entries) {
    if (e.modelId !== modelId) {
      next.push(e);
    }
  }
  return next.slice(0, CTX_FACTOR_MAX_ENTRIES);
}

// 读值封装（会话页活算消费）：未写入回 1.0（与「无该模型系数」同语义）
export function currentCtxFactor(modelId: string): number {
  return lookupCtxFactor(parseCtxFactors(AppStorage.get<string>(PREF_CTX_FACTOR_KEY) ?? ''), modelId);
}

// 写值封装（ChatSendCtrl 锚点校准点消费）：整键覆盖写（禁局部拼串——「JSON 串结构化键」立规）
export function saveCtxFactor(modelId: string, factor: number): void {
  const next: CtxFactorEntry[] =
    upsertCtxFactor(parseCtxFactors(AppStorage.get<string>(PREF_CTX_FACTOR_KEY) ?? ''),
      modelId, factor);
  AppStorage.setOrCreate<string>(PREF_CTX_FACTOR_KEY, serializeCtxFactors(next));
}

// 偏好键注册完成标记（AppStorage 进程内一次性信号，**非持久键**——不 persistProp、不进白名单）：
// EntryAbility loadContent 回调 persistProp 区末尾置 1。★ 2026-09-08 自检轮立：需要「一次性读
// 持久值」的消费方（当前唯一 = 启动进入页面的冷启动首帧判定）不应赌「persistProp 注册早于
// 页面组件实例化」——该时序是项目注释里的推断（dshinhm 坑17 原文只引官方「UI 实例初始化
// 成功后（即 loadContent 传入的回调被调用时）」），而 loadContent 的 d.ts 反注「回调内当前 UI
// 的执行上下文可能不明确」，一旦推断为假，一次性现读会拿到缺省值 = 设置静默失效。消费姿势 =
// `@StorageProp(PREF_LOADED_KEY) @Watch(...)`：键变 = 磁盘值已落 AppStorage，此时现读任何偏好键
// 都拿到持久值（HomeNavigation 先例：@StorageProp(CONSOLE_ASK_CMD_KEY) @Watch 同款订阅形制）
export const PREF_LOADED_KEY: string = 'prefLoaded';

// ── 联网搜索域四键（2026-09-10 多引擎一期）──
// ★ 立规「JSON 串结构化键」新模式（本文件首例；后续结构化偏好照此办理）：持久层仍是
// string 键，但值承载 JSON 串（{engineId:{baseUrl,hasKey}}）；读值一律经 parse 封装
// （坏 JSON 容错回空态，禁裸 JSON.parse 散落消费方）；写值一律经 serialize 封装（整键
// 覆盖写，禁局部拼串）。明文红线：本键只存 hasKey 布尔标记，API Key 明文只进 Asset
//（KeyStore saveSearchEngineKey 族）——禁把密钥写进本键。数组型偏好另有原生 string[]
// 形态（PREF_SEARCH_ENABLED_ENGINES_KEY，照 SettingSearch 先例——对象数组禁止持久化，
// 一维 string[] 可）。引擎 id 与结构常量单一来源 = common/search/SearchEngineRegistry.ets。

// 联网搜索总开关：false = 发送链不声明 search_web（ChatSendCtrl 过滤）+ 执行器兜底拒执；
// true = 照助手/会话两级既有语义（默认 true = 现状零回归——不配置任何引擎时行为逐字节
// 不变，默认引擎 bing_local 免 key）
export const PREF_SEARCH_SERVICE_ENABLED_KEY: string = 'prefSearchServiceEnabled';

// 读值封装（ChatSendCtrl 声明过滤现读）：未写入回退 true——与 persistProp 注册默认同源，
// 正常路径注册先于任何页面组件实例化，回退仅防御
export function isSearchServiceEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_SEARCH_SERVICE_ENABLED_KEY) !== false;
}

// 当前搜索引擎 id（默认 'bing_local'；实际生效值经注册表 fallback 链解析——本键存的是
// 用户手选，失效态由 resolveEngineId 兜底）
export const PREF_SEARCH_ENGINE_KEY: string = 'prefSearchEngine';

export function getSearchEngineId(): string {
  return AppStorage.get<string>(PREF_SEARCH_ENGINE_KEY) ?? 'bing_local';
}

// 启用引擎清单（原生 string[] 持久——SettingSearch 先例；注册默认 = 注册表全量 id
// 〔EntryAbility 经 ALL_SEARCH_ENGINE_IDS 引入，单一来源在 common/search/SearchEngineRegistry.ets〕；
// 空数组 = 用户显式全关，注册表 fallback 链兜 bing_local——读值不做默认展开，语义判读在域内）
export const PREF_SEARCH_ENABLED_ENGINES_KEY: string = 'prefSearchEnabledEngines';

export function getSearchEnabledEngineIds(): string[] {
  const raw: string[] | undefined = AppStorage.get<string[]>(PREF_SEARCH_ENABLED_ENGINES_KEY);
  return raw === undefined ? [] : raw;
}

// 引擎配置 JSON 串（{engineId:{baseUrl,hasKey}}；'' = 全默认无配置。hasKey 只是 UI 标记，
// 明文只在 Asset）。解析/序列化/生效 baseUrl 计算的纯函数与 AppStorage 读封装在
// common/search/SearchEngineRegistry.ets（域内聚——本文件只持键常量与兜底读值）
export const PREF_SEARCH_ENGINE_CFG_KEY: string = 'prefSearchEngineCfg';

export function getSearchEngineCfgJson(): string {
  return AppStorage.get<string>(PREF_SEARCH_ENGINE_CFG_KEY) ?? '';
}

// ── 备份分域：偏好键两分类表（2026-09-10 方案-偏好与密钥接入备份 §2.1/§4.2）──
// ★ 两张表是「哪些偏好随备份走」的**唯一来源**：导出侧按 BACKUP_PREF_KEYS 收集，
// 导入侧按同名清单回写（两处都读本表，禁散落判断）；assert-feature-domain 54 组「全覆盖钉」扫
// EntryAbility 全部 persistProp 键名，要求每个键恰好落在两表之一（数量与并集逐个比对）
// ——新增偏好漏登记即断言 FAIL，靠门禁不靠记性。
// 键名口径：本文件定义的键直接引用常量；定义在别处（沉浸/图片编辑/设置搜索/会话搜索/
// 服务商/助手/记忆/标题/seed 标记域）的用字符串字面量并在行尾注明单一来源文件——本文件
// 刻意保持零 import（它是被 UI 页面与 node 断言广泛消费的叶子模块，引 store 域会把 rdb
// 与 SDK 依赖拖进每个消费者），字面量漂移由上述全覆盖钉兜住（改名 → 钉红）。

// 随备份携带的偏好（60 键；分类依据 = 方案 §2.1 三分法。★ 2026-09-12 光感分项退役——
// 原 immersiveTabBar/immersiveOther 两键出表，退役键无 AppStorage 键值可收，见
// ImmersiveLevel.ets 头注释；2026-09-13 记忆按需读取笔 +memoryReadMode（读取方式是
// 用户设置，随备份走——顺核正头注计数：proactiveQuietMaxMinutes 入表后原「36 键」
// 头注漏更，实为 37，本笔 38；2026-09-15 附件 OCR 二期 +ocr 三键〔总开关 + 引擎两键
// ——识别引擎选择是用户设置，随备份走〕，本笔 41；2026-09-16 系统识别开关化 +ocrPreferSystem
// 偏好键〔引擎偏好是用户设置，随备份走〕，本笔 42；★ 同日内置引擎落地 +ocrEngine 三态键
// 〔引擎选择是用户设置，随备份走〕，本笔 43；2026-09-17 识别提示词定制笔 +ocrPrompt
// 〔识别提示词是用户设置，随备份走〕，本笔 44；★ 同日价格卡折叠记忆笔
// +prefPriceCardCollapsed〔价格卡收放是用户选择，纯界面展示偏好，随备份走〕，本笔 45；
// 2026-09-18 浏览高危确认降压阀笔 +prefBrowseAutoApprove〔确认档位是用户安全偏好，随备份
// 走——顺核段首计数：会话上下文用量笔入表后段首已更 46，本笔 47〕；2026-09-19 会话图标
// 显示笔 +PREF_SESSION_ICON_KEY〔图标显隐是纯界面展示偏好，随备份走——顺核段首计数：
// 本笔 48〕；★ 同日推荐问题功能笔 +suggest 四键〔总开关/模型两键/提示词定制——推荐问题
// 是显式授权的功能配置，随备份走；顺核段首计数：本笔 52〕；2026-09-20 HTTP 请求独立域笔 +prefHttpWriteAutoApprove〔写操作确认档是用户安全偏好，随备份走〕，本笔 53；
// 2026-09-22 聊天自动重试笔 +PREF_AUTO_RETRY_KEY〔自动重试开关是用户行为偏好，随备份走〕，
// 本笔 54；★ 同日记忆导入笔 +memoryImportPrompt〔导入整理提示词是用户设置，与 memoryPrompt /
// memoryOptPrompt 同语义同随备份〕，本笔 55；2026-09-23 粘贴长文本转文件笔 +prefPasteAsFile /
// prefPasteAsFileThreshold〔开关与阈值都是用户行为偏好，随备份走——★ 顺核逐笔计数：上下文
// 压缩笔 compress 三键入表后段首已更 58、逐笔计数漏跟（停在 55），本笔一并订正〕，本笔 60）
export const BACKUP_PREF_KEYS: string[] = [
  // 沉浸与外观（5）——ImmersiveLevel.ets 两键 + ImageEditUtil.ets 三键
  'immersiveLevel', 'contentFallback',
  'editBlurPct', 'editMaskPct', 'editCropState',
  // 功能模型绑定（16）——ProviderDb.ets 九键 + TitleGen.ets 一键 + AssistantDb.ets 一键
  // + OcrVisionApi.ets 一键（2026-09-15 附件 OCR 二期 +ocrEnabled/ocrProviderId/ocrModelId
  // ——键名字面量，单一来源 ProviderDb.ets，与下两行同族先例；2026-09-16 系统识别开关化
  // +ocrPreferSystem；★ 同日内置引擎落地 +ocrEngine——三态引擎键自此为写侧，偏好键退役为
  // 只读兜底但**仍随备份走**：旧备份恢复后 resolveOcrEngine 还要用它推导，删了会让老用户
  // 升级态丢失；2026-09-17 识别提示词定制笔 +ocrPrompt——单一来源 OcrVisionApi.ets，
  // 与 titlePrompt 同语义同随备份；2026-09-19 推荐问题功能笔 +suggest 四键——suggestEnabled/
  // suggestProviderId/suggestModelId 单一来源 ProviderDb.ets、suggestPrompt 单一来源
  // SuggestGen.ets，与 titlePrompt 同语义同随备份）
  'defaultProviderId', 'defaultModelId', 'titleProviderId', 'titleModelId', 'titlePrompt',
  'activeAssistantId', 'ocrEnabled', 'ocrEngine', 'ocrPreferSystem', 'ocrProviderId', 'ocrModelId',
  'ocrPrompt',
  'suggestEnabled', 'suggestProviderId', 'suggestModelId', 'suggestPrompt',
  // 上下文压缩（3）——CompressGen.ets 三键（2026-09-23 任务书-上下文压缩-20260923）：
  // 模型两键与提示词定制键都是用户配置，随备份走（未配置 = 回退当前会话模型，恢复后语义不变）
  'compressProviderId', 'compressModelId', 'compressPrompt',
  // 通用偏好（18）——本文件十八键（2026-09-17 价格卡折叠记忆笔 +PREF_PRICE_CARD_COLLAPSED_KEY
  // 与会话上下文用量笔 +PREF_CTX_FACTOR_KEY；2026-09-18 浏览高危确认降压阀笔
  // +PREF_BROWSE_AUTO_APPROVE_KEY——确认档位是用户安全偏好随备份走；2026-09-19 会话图标
  // 显示笔 +PREF_SESSION_ICON_KEY——纯界面展示偏好随备份走；2026-09-22 聊天自动重试笔
  // +PREF_AUTO_RETRY_KEY——自动重试开关是用户行为偏好随备份走；2026-09-23 粘贴长文本转
  // 文件笔 +PREF_PASTE_AS_FILE_KEY / PREF_PASTE_AS_FILE_THRESHOLD_KEY——开关与阈值都是
  // 用户行为偏好随备份走）
  PREF_THINK_EXPAND_KEY, PREF_KEYBOARD_SEND_KEY, PREF_STREAM_ENGINE_KEY,
  PREF_STREAM_FOLLOW_KEY, PREF_KEEP_SCREEN_ON_KEY, PREF_SESSION_TIME_KEY,
  PREF_SESSION_ICON_KEY,
  // +PREF_AUTO_RETRY_KEY——2026-09-22 聊天自动重试笔：开关决定网络异常时是否自动退避重发，
  // 属用户行为偏好，随备份走（不是本机残留）
  PREF_AUTO_RETRY_KEY,
  PREF_BIOMETRIC_FACE_KEY, PREF_BG_SESSION_ONLY_KEY, PREF_TAB_SWITCH_ANIM_KEY,
  PREF_LAUNCH_NEW_CHAT_KEY, PREF_PRICE_CARD_COLLAPSED_KEY, PREF_CTX_FACTOR_KEY,
  PREF_BROWSE_AUTO_APPROVE_KEY,
  // +PREF_HTTP_WRITE_AUTO_APPROVE_KEY——2026-09-20 HTTP 请求独立域笔：HTTP 写操作确认档同属
  // 用户安全偏好，随备份走（与上一行 browse 确认档同款口径）
  PREF_HTTP_WRITE_AUTO_APPROVE_KEY,
  // +PREF_PASTE_AS_FILE_KEY / PREF_PASTE_AS_FILE_THRESHOLD_KEY——2026-09-23 粘贴长文本转
  // 文件笔：粘贴转附件开关与长度阈值都是用户行为偏好，随备份走（换机恢复后习惯不变）
  PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY,
  // 记忆（10）——MemoryGen.ets 六键 + MemoryOpt.ets 三键 + MemoryImport.ets 一键
  //（2026-09-11 记忆优化模型二期；同日收尾补提示词定制键，与 memoryPrompt 同语义同随备份；
  // 2026-09-13 记忆按需读取笔补 memoryReadMode 读取方式，键名字面量，单一来源 MemoryGen.ets；
  // ★ 2026-09-22 记忆导入笔补 memoryImportPrompt——导入整理提示词与 memoryOptPrompt 同款
  // 用户设置（导出侧提示词是常量不进键表，它不给用户编辑）；单一来源 MemoryImport.ets）
  'memoryEnabled', 'memoryAutoSink', 'memoryProvider', 'memoryModel', 'memoryPrompt',
  'memoryReadMode',
  'memoryOptProvider', 'memoryOptModel', 'memoryOptPrompt',
  'memoryImportPrompt',
  // 主动消息（4）——ProactiveGen.ets 四键（2026-09-12 主动消息第一笔；2026-09-13 静默期
  // 滑轨笔补 proactiveQuietMaxMinutes。设置随备份走。★发送时刻数组 proactiveSentAt 不在
  // 此表——本机时间线痕迹进下方排除表）
  'proactiveEnabled', 'proactiveIntervalHours', 'proactiveDailyLimit', 'proactiveQuietMaxMinutes',
  // 联网搜索（4）——本文件四键（引擎明文不随之走，见下方凭据登记 #2）
  PREF_SEARCH_SERVICE_ENABLED_KEY, PREF_SEARCH_ENGINE_KEY,
  PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY
];

// 不随备份携带的偏好（12 键；四类理由见方案 §2.1 与下方分组注释）
export const BACKUP_EXCLUDED_PREF_KEYS: string[] = [
  // seed 代数标记与待并入登记四键（AssistantDb.ets / ProviderPresetSeed.ets /
  // SkillBuiltinDefs.ets）：本机安装态标记而非用户设置——带进备份会让换机/覆盖导入后
  // 「自以为已 seed 而库里没有对应数据」，控制台助手工具清单、预置卡与内置技能代数的判断
  // 错乱（复活循环坑同族）；skill_builtin_pending 为「待并入登记」（2026-09-20 D5-3），
  // 带进备份会把别的机器上没并完的内置件当本机待办带过来
  'console_tools_seeded', 'provider_presets_seeded', 'skill_builtin_seeded',
  'skill_builtin_pending',
  // 使用痕迹四键（SettingSearch.ets / SessionSearch.ets）：搜过什么、点过什么是本机操作
  // 残留，换机带过去只会让人困惑
  'settingSearchHistory', 'settingRecentUse', 'sessionSearchHistory', 'sessionRecentConv',
  // 壁纸路径（EntryAbility 字面量键）：路径指向本机沙箱文件，而壁纸文件本身不随包——
  // 带路径不带文件 = 恢复后一排加载不出的背景（附件边界同源口径）。决明 2026-09-10 拍板
  // 排除；将来要连壁纸一起迁，须另立「壁纸文件随包」子任务，本笔不做
  'pageBg',
  // 主动消息发送时刻滚动数组（ProactiveGen.ets）：本机发送时间线痕迹，与使用痕迹四键
  // 同族——跨机时间线无意义。恢复旧备份后冷却归零可能当轮多发一条，由每日上限守卫
  // 兜住，可接受（2026-09-12 主动消息第一笔，任务书 §3.2 口径；原并列「与静默期」
  // 随免打扰时段撤除删——四百七十四节）
  'proactiveSentAt',
  // 主动消息未读会话（ProactiveGen.ets，2026-09-12 主动消息第二笔）：本机未读痕迹，与
  // proactiveSentAt 同族——换机带着「别的机器上未读」的红点无意义；键名字面量，单一来源
  // ProactiveGen.ets
  'proactiveUnreadConv',
  // 请求日志开关（'prefReqLog'，2026-09-23 请求日志笔）：诊断开关而非用户设置。开着时会记录
  // 含对话内容与请求头的请求快照——随备份携带会让换机恢复后**静默开启**一个记录敏感内容的
  // 开关（恢复流程不提醒用户复核），故刻意排除；代价仅换机后手动重开一次。键名字面量，
  // 单一来源 ReqLog.ets（该件刻意零 import，见其头注释）
  'prefReqLog'
];

// ── 备份凭据登记块（★ 新增凭据必须在此登记——导出侧两档逻辑与本块同源）──
// 本项目凭据只有四处，档位归属如下（改任何一处都要同步本节）：
// 1. 服务商 API 密钥池（Asset 别名 aic.p.<providerId>/<keyId>，KeyStore.ets）
//    → 含密钥档随加密件进包；不含密钥档明文不进包（provider_keys 行照常进包，
//      同设备恢复靠 Asset 明文天然可用，换设备恢复后重填）
// 2. 搜索引擎 API 密钥（Asset 别名 aic.se.<engineId>，KeyStore.ets）
//    → 同 #1（两域必须对称，见方案 §2.2）
// 3. 余额密钥 / 余额请求头 / 自定义请求头（providers 三个明文列 balance_key /
//    balance_headers / headers，建表 SQL 在 ChatDbMigrate.ets）
//    → ★ 两个档位的 providers.json **都**置空（明文只进加密件）；含密钥档由加密件回填，
//      不含密钥档导入后这三列为空（余额查询失效 = 方案 §九 验收项）
// 4. WebDAV 应用专用密码（Asset 别名 aic.dav.password，KeyStore.ets）
//    → ★ 恒不进包（任何档皆否）：通道凭据自指死锁——它随包传到 WebDAV 后，恢复要先从
//      WebDAV 下载该包，而下载正需要它，故必然只能留在本机、换机重填一次

// ── preferences.json 编解码纯函数（导出写 / 导入读；node 断言直跑本文件）──
// 条目形态 {key, type, value}：type 显式携带是防 JSON 弱类型把 0 与 false 混淆（照 Cube
// collectPreferences 先例）。★ 类型四值 = 方案 §4.1 的 string|number|boolean 三值 + 
// array——本项目的编辑参数记忆（editCropState）与启用引擎清单（prefSearchEnabledEngines）
// 都是持久化数组，三值形态装不下，故扩为四值（数组只认一维纯 string / 纯 number：对象
// 数组禁持久化，见本文件联网搜索域注释）。
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
// 分域文件不存在才由调用方按「老备份缺失容忍」跳过，见方案 §4.1）
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
// ★ 2026-09-10 自检轮补：'array' 单值把 string[] 与 number[] 归成一类，本机 editCropState
// 是数字数组、prefSearchEnabledEngines 是字符串数组——只比 'array' 会放过「字符串数组
// 写进数字数组」的脏包，消费方（图片编辑参数）算术得 NaN。见 applyBackupPrefItems）
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
// 元素类型相符（自检轮补，见 arrayElementKindOf）
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
