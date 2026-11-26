// 消息架构整合·跨笔身份契约：本文件 = 冻结词表与纯类型叶子——run/attempt 身份（六项）
// + 工具执行上下文（ToolExecutionContext，显式执行上下文穿工具链的载体类型）。
// ★ 纪律：本文件零 import、不反向引任何域件——ToolContracts（叶子）与 common/providers
//   各执行器只从本文件引类型，方向恒为「域 → 本文件」，禁止反向。
// ★ 跨笔契约：run/attempt 词表已冻结，runId 升级持久后即同一身份（runId 作持久主键），
//   不重编号、不另开状态机；冻结后修改语义或扩字段 = 须决明立项（三级止损）。
// 身份铸造与终态规则：
// · 铸造：一次接纳（用户发送/重试被占用闸接纳）= 一个 run（runId）；一次网络尝试 =
//   一个 attempt（attemptId = runId + '#a' + attemptEpoch）；工具续轮属同 run 同 attempt，
//   Key 池失败切换与自动重试重发换 attempt（attemptEpoch 自增）。
// · 终态：轮收尾（finishStream done/error）或页面销毁（disposeSilent）= run 终结，
//   占用释放（先失效后释放——释放后旧身份回调一律作废）；runId 一经铸造不复用不重编号。

// run/attempt 身份词表（冻结契约字段；本接口为「一次运行」的只读快照形态）
export interface RunIdentity {
  // 运行身份（用户这次生成）：进程内唯一，格式 run_<epoch 毫秒>_<序号>；持久化后作主键
  runId: string;
  // 所属会话（发起页会话 id；无行会话 = 页面临时 id，与消息行同源）
  conversationId: string;
  // 归属助手实体 id（执行者助手——记忆/知识库选库与账本归属同源；'' = 无绑定）
  assistantId: string;
  // attempt 序号（1 起；Key 池失败切换 / 自动重试重发自增，工具续轮不自增）
  attemptEpoch: number;
  // attempt 身份（runId + '#a' + attemptEpoch——由 attemptEpoch 派生，不独立铸造）
  attemptId: string;
  // 图身份：旧线性阶段**尚未启用**——恒 undefined，禁止伪造已存在的分支行（红线；
  // 消费方读到 undefined 属预期）
  branchId?: string;
  inputHeadId?: string;
}

// 工具执行上下文作用域：会话内调用（聊天链发起，conversationId/runId 必填）
export const TOOL_SCOPE_CHAT: string = 'chat';
// 工具执行上下文作用域：系统级调用（确无会话的合法非聊天调用；conversationId/runId = ''，
// 会话相关工具按各自语义降级）
export const TOOL_SCOPE_SYSTEM: string = 'system';

// 工具执行上下文（显式携带契约——替代四中转键 CHAT_SEARCH_COUNT_KEY /
// CHAT_ACTIVE_CONV_KEY / MEMORY_EXEC_ASSISTANT_KEY / KNOWLEDGE_EXEC_ASSISTANT_KEY 的进程级
// AppStorage 中转：值在接纳时一次快照随链下传，执行器只读本上下文，禁回读全局键）。
// 已迁调用方缺上下文 = 明确失败（executeToolCall 对 null/undefined 抛错，禁默认回退）。
export interface ToolExecutionContext {
  // 作用域（TOOL_SCOPE_CHAT / TOOL_SCOPE_SYSTEM）
  scope: string;
  // 发起会话 id（chat 必填；system = ''）
  conversationId: string;
  // 所属运行 id（chat 必填；system = ''）——HTTP 在途按 run 定向取消（I11）同源
  runId: string;
  // 所属尝试 id（chat 必填；system = ''）
  attemptId: string;
  // 归属助手实体 id（chat 必填 = RunIdentity.assistantId 同源快照，system = ''）——HTTP
  // 凭据按助手命名空间解析的 owner。冻结词表登记：值源 = ChatSendCtrl
  // buildExecutionContext 的 effectiveAssistantId，与 memoryScopeAssistantId /
  // knowledgeAssistantId 的特化语义不同，恒为会话绑定助手本体
  assistantId: string;
  // 记忆作用域助手 id（原 MEMORY_EXEC_ASSISTANT_KEY 值：助手记忆时 = 助手 id，全局 = ''）
  memoryScopeAssistantId: string;
  // 知识库执行者助手 id（原 KNOWLEDGE_EXEC_ASSISTANT_KEY 值：恒 ownerAssistantId）
  knowledgeAssistantId: string;
  // 搜索条数上限（原 CHAT_SEARCH_COUNT_KEY 值；0 = 未解析，读侧回默认）
  searchResultCount: number;
  // run 活跃探测（S4 浏览队列出队后与副作用前核验取消状态用——闭包由组件层构造时绑定
  // ChatRunScope，common 层执行器只消费本函数类型，不反向引组件；返回 false = 该 run 已
  // 停止/销毁，排队任务必须放弃副作用）
  isRunActive: (runId: string) => boolean;
  // 主模型有无视觉理解快照（I12 扩字段已立项登记）——发送链视觉门控同判据
  //（hasVisionCap(effectiveCaps)），值源 = 当前连接随行 caps（ChatSendCtrl 读
  // refs.conn()?.caps ?? ''，与页面视觉门控同源同值）。消费方 = 工作区 read 图片分支
  //（有视觉 → 图挂续传请求；无视觉 → OCR 文本回执）
  hasVision: boolean;
  // 工具图收集回调（组件层构造时绑定闭包，common 层执行器只消费本函数类型，禁反向引
  // 组件）。签名用 (mimeType, data) 两参原语：本文件零 import 纪律禁引 AiTypes.AiImagePart，
  // 且 ArkTS 禁结构化类型（同构双接口互传即编译错）。语义 = 把工具产出的图片挂进本轮请求
  // 历史 user 消息的 images 数组（续传轮即带图；跨发送随历史重建消失，与附件本体同生命
  // 周期）；返回 false = 挂载失败（本轮 user 消息不可达如重发链 / 超单发送图数上限），
  // 执行器据此中文回执说明。上限单源 = ToolLimits.TOOL_IMAGE_ATTACH_MAX。值域含
  // application/pdf（工具结果位的文档原件，PDF 直传经同一缝交付）；落点分派由挂载侧按
  // 协议能力判据（ToolMediaSupport 单源）决定，执行器无感
  collectImage: (mimeType: string, data: string) => boolean;
  // 扫描件 PDF 页图挂载缝（扩字段登记）——与 collectImage 同挂载逻辑但**不吃
  // TOOL_IMAGE_ATTACH_MAX 计数**：页图预算 = 单册 ≤ RENDER_MAX_PAGES（30）页页图全量可达
  //（8 张上限只约束执行器散图路，页图是单册渲染产物）。消费方 = 工作区 read 的 PDF 视觉路
  // 单点；返回 false = 挂载失败——页图路挂载失败整批放弃页图、回执走纯文本
  collectPageImage: (mimeType: string, data: string) => boolean;
  // 单调用预检便签（决明拍板：预检结论走执行上下文契约，本注释登记）——本调用 preflight
  // 留给**本调用执行器**的一次性结论串（载荷 = 工具自定义约定，'' = 未留）。信道纪律 =
  // 逐调用一个上下文对象贯穿预检与执行（轮内 = executeToolCalls 预检循环逐调用
  // deriveCallContext 派生存入 callContexts、按 callId 取用同对象；重发链 = 单对象贯穿
  // 全程）——同一对象即信道隔离：跨调用不共享、不落盘、不出进程，故载荷无需身份段。
  // 基础上下文恒写 ''（deriveCallContext 全字段透传）——禁在基础上下文写本字段（那会
  // 跨调用串写）。首消费 = mount_copy_in（写点 mountCopyInNeedsConfirm 探测后、读点
  // MountCopyInExecutor 目标打开前失败关闭臂；语义见 ToolMount 两处注释）
  preflightMemo: string;
}
