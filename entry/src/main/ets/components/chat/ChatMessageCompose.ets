// 聊天消息视图模型：ChatMessage = 渲染层唯一消费的消息模型（ChatMessageItem/ChatPage 引用）。
// ★ ChatMessage = **@Observed 类**（dshinhm 二三四改拍板语义保留）：同绑定键稳定，
// 用户/助手渲染键额外含 bodyBindingId；增量帧原地改字段，由 @Observed→@ObjectLink
// 对象级观察保证刷新，列表项不每帧销毁重建（stable key + 内容字段精准更新 = 业界流式
// 渲染共识）。
// 约束：@Observed 类必须经 new 构造（对象字面量无效）——统一走 newChatMessage 工厂。
// attachBriefs 类型自 common/AttachmentUtil 引（简报类型单源；common → components 单向）

import { AttachmentBrief } from '../../common/AttachmentUtil';
import { MarkdownEndReason, nextMarkdownBindingId } from '../../common/markdown/MarkdownDocumentModel';
import { ChatDisplayBudget } from '../../common/chat/ChatDisplayBudget';
// ★ 2026-10-06 代码工作台笔D：工具结果附件类型（components → common 方向，既有先例充分）
import { AiImagePart } from '../../common/providers/AiTypes';
// ★ 2026-10-08 过程段折叠笔：工具步骤状态判据族消费（提问卡判据 + 确认档位常量——自
// ChatToolCard 上收为单源；common/providers 叶子常量模块，零环）
import { TOOL_ASK_USER } from '../../common/providers/ToolIds';
import { CONFIRM_LEVEL_IRREVERSIBLE } from '../../common/providers/ToolContracts';
// ★ DS 全家桶接入批 S3：服务端步骤视图模型域消费两协议字面量（type 兜底分流——字面量单源
// 在 DsServerTools，禁散写）；DsServerTools 零反向依赖本件，无环
import { DS_SERVER_TOOL_WEB_SEARCH, DS_SERVER_TOOL_READ_URL } from '../../common/providers/DsServerTools';
// 二期 #7：计次视图字段类型（只读展示料）
import { AiServerToolUse } from '../../common/providers/SseParser';

// ── 过程步骤行种集（2026-10-08 过程段折叠笔；展示投影与渲染两侧共引单源，禁第二份字面量）──
// 步骤行种 = 构成过程段成员的消息种类（thinking 思考 / tool 工具 / serverstep 服务端步骤——
// DS 官方联网的搜索/读链接等步骤行，S2⑤ 流内合成、S3 官方步骤行渲染接手）。
// 判据消费 = 展示投影的段分组（连续步骤行合成一个过程段；非步骤行断段——空正文 assistant
// 已被投影跳过故不断段）。
export const STEP_KINDS: string[] = ['thinking', 'tool', 'serverstep'];

// 步骤行种判据（展示投影分组共引）
export function isStepKind(kind: string): boolean {
  return STEP_KINDS.indexOf(kind) >= 0;
}

// ── 展示轮状态（2026-10-08 过程段状态收敛与摘要折叠优化笔）──
// 轮 = conversationId + '|' + runId（整轮稳定身份）。running 只由本页已登记的实时轮持有；
// 历史读取的 generation_runs.status 映射 finished→done、failed→error，其它一切值（含历史
// 遗留 running、缺行、坏值）→ unknown（不伪报成功）。stopped 仅实时收尾可达（历史无法区分
// 失败与手动停止，只能统一异常——任务书 §3.2）。
export type DisplayRoundStatus = 'running' | 'done' | 'error' | 'stopped' | 'unknown';

// 提问卡作答草稿镜像（2026-10-08 过程段状态收敛与摘要折叠优化笔；源消息持有的页面寿命状态
// ——虚拟列表组件被回收重建后按 inputJson 精确比较恢复，不另起全局/Map 缓存）。
// inputJson = 题目版本精确比较值（题 id 单键不可靠）；drafts / selections 与题目一一对应。
// currentIndex（2128 分页笔）：当前题下标——单题分页后列表回收重建必须停在原题，否则答到
// 第 3 题被回收再回来会跳回第 1 题（页码是可变展示状态，与草稿同源持久化）。可选字段：
// 老草稿对象缺省 undefined 按 0 读，不设迁移。
export interface AskDraftState {
  inputJson: string;
  drafts: string[];
  selections: string[][];
  currentIndex?: number;
}

// 消息类别：user 用户气泡 / assistant 助手气泡 / thinking 思考灰字 / tool 工具行 / notice 提示条
@Observed
export class ChatMessage {
  id: string = '';
  kind: string = '';
  text: string = '';
  // 用户/助手正文绑定独立于业务ID；创建及路径安装显式铸造，帧增长/回填nodeId不改变它。不落库。
  bodyBindingId: string = '';
  bodyEndReason: MarkdownEndReason | undefined = undefined;
  // 只在实时正文上按需创建，不落库；内部普通标量不驱动UI、不持组件回调。
  displayBudget?: ChatDisplayBudget;
  toolName: string = ''; // kind=tool：工具名（函数名原串——展示名经 ToolTypes.toolTitle 转换）
  toolState: string = ''; // kind=tool：running / done / error / cancelled（域① 中止态——判据 = 载荷 cancelled 键）
  level: string = ''; // kind=notice：info / warning / error
  // ── 工具卡字段（kind=tool 专用；2026-09-02 工具调用底层起 tool 分支为活跃渲染路径）──
  toolCallId?: string; // 模型侧调用 id（ask_user 答案上行回传键——ToolRuntime.resolveAsk）
  // ── 工具结果附件（★ 2026-10-06 代码工作台笔D；kind='tool' 专用）──
  // 值 = 本次调用随请求发送的附件（通常 1 张；类型复用 AiImagePart——图片与 PDF 同通道）。
  // 与 toolConfirm* 族同口径「运行时字段」：**不入库、不参与回放构造**——写点 = 工具轮结算
  //（串行 / 并行两处）；重进会话回放出来的历史工具卡本字段恒 undefined（无缩略图，回执
  // 文本仍在）
  toolMediaParts?: AiImagePart[];
  toolInputText?: string; // 入参展示文本（inputText）
  toolInputJson?: string; // input 原始值 JSON 串（展开区全文）
  toolOutputJson?: string; // output 原始值 JSON 串（展开区全文）
  toolDisplayText?: string; // display 文本（字符串原样 / 其他 JSON 串）
  toolProgressPercent?: number; // progress.percent（0~100）
  toolProgressText?: string; // progress.text（无 percent 时的进度文案）
  toolTaskId?: string; // 关联任务 id
  toolTodoId?: string; // 关联待办 id
  toolAgentSummary?: string; // agentRefs 摘要（预组合串）
  // ── 高危动作确认等待（2026-09-18 内置浏览器 P2·B 单元；kind=tool 且 toolName=browse_act
  // 专用）──
  // 非空 = 该调用正等待用户在确认卡上作答（值 = 卡面主因句，如「在「百度一下」上点击
  // 「提交订单」」）。写点 = 工具轮域推卡时（仅命中高危的调用置位）；★ 2026-09-20 审批卡
  // 视觉迁移笔 A 起**用户作答后不再清空**（confirmAwaiting 判据同时看 result 未写；
  // 回执行的体首主因句仍读本字段）；中止分支（停止/销毁）照旧清空。确认卡渲染判据 =
  // running && 本字段非空 && toolConfirmResult undefined（不加后件则读向点击/滚动也会渲染
  // 出无用按钮）；不入库、不参与回放构造（undefined 即「无等待」——重进会话的历史工具卡
  // 天然不等待）
  toolConfirmText?: string;
  // ── 确认档位与作答结果（2026-09-20 审批卡视觉迁移笔 A；三枚与 toolConfirmText 同族的
  // 运行时字段——不入库、不参与回放构造，写法照上方 toolConfirmText 口径）──
  // toolConfirmLevel：'write' | 'irreversible'（ToolContracts 两常量），写点 = 推卡时置
  //（预检二元组的 level）；卡面档位徽章与风险块的判据。undefined = 按写操作档渲染
  toolConfirmLevel?: string;
  // toolConfirmResult：'approved' | 'rejected' | 'session'（★ 2026-09-20 笔 C 增第三值）
  // | 'aiAllowed' | 'aiDenied'（★ 2026-09-28 命令审批功能笔增两值——审批模型闸结论，无人工
  // 参与：aiAllowed = 模型允许后直执行、aiDenied = 模型拒绝即终态），写点 = 用户在确认卡
  // 作答那一刻（等待态转回执/拒）或审批闸结算那一刻（ChatToolRoundCtrl.runOne 审批分支）。
  // 判据 = 回执行分支渲染（见 ChatToolCard.confirmDone）；「已允许」在既有字段上无痕（批准戳
  // 内存态用完即销），故此回执必须由本字段承载——只在当场可见，重进会话退回普通工具卡（信息
  // 零丢失，申报口径见任务书 §5.4）
  toolConfirmResult?: string;
  // toolConfirmReason：审批模型的结论理由（★ 2026-09-28 命令审批功能笔）——仅审批闸结论
  // （aiAllowed/aiDenied）伴随写入，卡面回执区展示；人工卡路径不写（用户自己的决定无需
  // 理由行）。与上族同口径：不入库、不参与回放构造
  toolConfirmReason?: string;
  // toolConfirmAiNote：审批闸「跑了但没结论」的短因（★ 2026-09-28 真机反馈笔）——写点 =
  // ChatToolRoundCtrl 转人工分支（仅槽位已配置却未给出结论时写，未配置 = 功能未启用不写，
  // 免得没配的人每张确认卡都多一行）；渲染 = ChatBrowseConfirmCard 说明行包成整句。
  // 与上族同口径：不入库、不参与回放构造
  toolConfirmAiNote?: string;
  // toolConfirmSessionAllow：用户在确认卡上按的是「本会话内允许」——卡在作答那一刻写 true
  //（只有 true 会写；消费点 = ChatToolRoundCtrl.awaitBrowseConfirm：映射 result = 'session'
  // 并授予会话级免询问）。与上两枚同族：不入库、不参与回放构造
  toolConfirmSessionAllow?: boolean;
  // ── 确认卡结构化预览与域名快捷键（2026-10-01 方案-HTTP工具完善 批 2 笔 2；三枚与上面
  // 同族运行时字段——不入库、不参与回放构造）──
  // toolConfirmDetail：可展开的「要发什么」明细串（预检 buildHttpConfirmPreview 产，写点 =
  // ChatToolRoundCtrl.runHumanConfirm；空串 = 无预览——browse_act 等既有确认零变化）
  toolConfirmDetail?: string;
  // toolConfirmDomain：本次写请求目标 host（预检自 URL 取）——只留作等待态回放载荷，
  // 卡面已无「始终允许该域名」快捷键（2026-11-09 三档归一笔记退役）。写点 = runHumanConfirm
  // 与回放投影；不入库、不参与回放构造
  toolConfirmDomain?: string;
  // toolConfirmDomainAllow：原「始终允许该域名」作答意图位。★ 2026-11-09 三档归一笔记起
  // 已无任何读写点（卡面键与两处落档写点同笔删除），字段仅作旧数据形态占位，勿回游
  toolConfirmDomainAllow?: boolean;
  // 思考块关联的正文消息 id（2026-09-01「回传历史思考」：kind='thinking' 专用——思考块
  // 与它上方的 assistant 正文消息的关联键；发送组装历史时经此把思考内容并回 assistant
  // 消息的 reasoning（仅 OpenAI 系回传，见 ChatSendCtrl）。回放 = 'think'-+行 id（行 id
  // 即正文行 id）；流式 = liveAssistantId（懒创建时绑定）。普通消息不设（undefined）
  linkId?: string;
  // ── 展示轮归属与详情意愿（2026-10-08 过程段状态收敛与摘要折叠优化笔）──
  // displayRoundId：本条所属回复轮的展示身份（conversationId|runId）。写点两路——①实时
  // （beginDisplayRound 写新 holder + bindDisplayMember 由精确 owner 继承；找不到 owner
  // 留空，不扫最近 assistant/user 补猜）；②历史装配（chatMessagesFromRows 按 id→runId 映射
  // 回填 body/toolCard，合成 thinking 继承其 body）。轮终态由数据源轮事实表按本 id 查得。
  // detailExpanded：单步骤详情意愿（思考/工具/收束后中间正文三 kind 共用；中间正文缺省
  // false = 只挂标题、展开才挂 Markdown 树，与思考行的偏好缺省不同；★ 2026-10-13 开合收口笔契约——
  // 用户关→开时经 onDetailOpened 提升段意愿「视为正在阅读」；关详情只收自身、不发上行（多步
  // 链内点单条思考只收自己，段展开态与「收起」键保持）；段级「收起」一并清掉段内全部详情
  // 意愿。收尾事件从不主动改本字段——settle 不藏走正在阅读的详情）。与既有运行时字段
  // 同口径：**不入库、不参与回放构造**；换源重建/页面结束随对象归零。
  // askDraft：提问卡作答草稿（kind='tool' 且等待作答时持有；业务把 toolState 改为
  // done/error 或停止后由数据源 refreshDisplay 清扫）。同族运行时字段，不入库、不参与回放。
  displayRoundId: string = '';
  detailExpanded?: boolean;
  // 原文面板的手选意愿，未手选时按当前内容默认输出优先。仅随消息对象存活，不落库。
  toolRawTab?: string;
  askDraft?: AskDraftState;
  // ── 输入位接管标记（2026-11-08 提问卡与确认卡底部托管笔；与 askDraft / toolConfirm*
  // 同族运行时字段：不入库、不参与回放构造，换源重建/页面结束随对象归零）──
  // true = 本条等待卡已被底部托管位接管，流内只渲染步骤头行、不再挂可作答卡体（避免两处
  // 可答）。写点唯一 = ChatPageContent.claimAskDock；清位三路 = dismissAskDock 单入口、
  // ChatDataSource.clearStaleDockMarkers 重投影清扫、@Watch 见终态兜底。
  dockOwned?: boolean;
  // ── 本轮操作栏宿主标记（2026-10-08 过程段折叠与回复操作归一；展示投影写入、渲染与菜单
  // 守卫共读）──
  // true = 本条是**所属回复轮的最终正文**且该轮已收束（轮内无流式行、无未完成的过程步骤
  // ——等待用户处理或工具执行中）——消息级操作栏（用量键 / 重试键 / 「更多」菜单）只在本条
  // 渲染。轮归属语义与判据
  // 单源 = ChatDisplayProjection 的分组与标记链（**禁第二处判据写法**）；菜单侧同源守卫 =
  // ChatMessageMenuCtrl 读本字段（入口判断与执行守卫同源，防「图标藏了、长按/菜单路径仍可
  // 误操作中途节点」）。
  // 中途正文（轮内其后仍有过程步骤/流式行）与候选未收束正文恒 false——「生成中不把暂时最后
  // 一行认作最终回答」由轮收束判据承载（不是逐帧判据）。
  // 口径照既有运行时字段：**不入库、不参与回放构造**，数据源整体重建即随新对象归零
  // （undefined 按非真消费，`=== true` 判据）；写点唯一 = 展示投影每轮重建时全表刷新。
  opsHost?: boolean;
  // ── 用量 meta（仅末轮 assistant 行携带——失败/停止/存量/工具轮中间行天然 undefined 不
  // 渲染）。usageCompletionTokens 为补增项：口径③ tok/s = completion ÷ duration——仅
  // total+duration 推不出分子
  usageTokens?: number; // 整轮总 token（prompt+completion 跨流求和）
  usageCompletionTokens?: number; // 整轮输出 token（tok/s 分子）
  usageDurationMs?: number; // 整轮纯流式时长（tok/s 分母）
  // 缓存命中输入（2026-09-10 缓存命中显示）：整轮命中缓存读的输入 token（跨流求和）。
  // >0 才挂（输入数已含命中部分，meta 行以括号内缀标注「输入 1.2k（缓存 800）」）；
  // 无缓存协议/短对话恒 undefined 零噪声
  usageCachedTokens?: number;
  // 首字耗时毫秒（2026-09-23 首字耗时笔）：本轮首个正文/思考增量到达时刻 − 流起点，跨流
  // 取**首个非 0**（用户第一次看到字的那一刻，见 ChatUsageRoundCtrl）。>0 才挂
  //（undefined 即不渲染——空响应/纯工具调用轮/无 usage 帧的流天然无此行，与缓存段同款）。
  // 常开测量，与「用时」同族；重进会话回挂走账本（ChatPageLoad；★ 订正 A-22：切版/变体
  // 快照回挂随多版本域退役）
  usageFirstTokenMs?: number;
  // ── 运行时字段（2026-09-14 消息气泡底栏；不入库、不参与回放构造——rebuildFromHistory
  // 重建的对象两字段 undefined = 底栏按「已结束」显示、重试键按回放尾行判定）──
  // 本条正在流式输出——**两 kind 共用**：①kind='assistant'（2026-09-14 底栏）——占位气泡
  // 创建处置 true，finishStream 收口与工具轮中间行收尾 settleRoundAssistant 置 false
  // （done/error 两路都经收口，失败与手动停止轮自动获得底栏）；②kind='thinking'
  // （2026-09-16 三态收口）——思考行懒创建处置 true（生成中：折叠态显尾部三行预览），
  // finishStream 与 settleRoundAssistant 两处收口置 false（已结束：折叠态内容区收拢为 0、
  // 只留标题行——见 ChatProcessSegment.ChatThinkingStep 头注释）。回放/翻页重建的行两 kind
  // 该字段皆 undefined ⇒ 判「已结束」
  streaming?: boolean;
  // 本条是否为「其后无任何消息」的末条助手消息（重试键显隐判据）。维护 = ChatDataSource
  // push（任何新消息入列即清旧 tail，assistant 行自置）+ rebuildFromHistory（末条
  // assistant 行置 true）+ finishStream 收口置回（failRound 的 notice 先 push 清过 tail）
  tail?: boolean;
  // ★ 2026-10-10 阶段6第二段退役笔：原 renderEpoch 字段与「id#纪元」渲染键已随旧渲染器
  // （CJMarkdown/@lidary）整组件重建机制删除——非前缀整段替换现由新引擎绑定世代承接
  // （同绑定 generation 推进即 replace，不换组件、不误作追加，见 MarkdownDisplayBinding）。
  // ── 图节点身份（2026-09-26 自检位B 修复；kind=user/assistant 图会话专用）──
  // graph 会话的库身份 = messages.id（节点 id），由命令层铸造，与内存 id（nextMessageId('msg')）
  // 不同源；图提交回读后由 ChatGraphWriteCtrl.stampNodeRef 回填（★ 2026-09-30 图身份回填笔起
  // 跨三处：起轮回填 user 行在 ChatSendCtrl、收尾回填终答行随 2026-09-27 拆分在
  // ChatStreamFlowCtrl、工具中间轮行经提交链第四参回填在 ChatGraphWriteCtrl.commitRoundAssistant）。
  // 消费点 = 压缩选段边界锚（CompressGen.rowId 取本字段优先——摘要
  // 采用核验 isNodeOnActivePath 按节点 id 上溯）。undefined = legacy 行 / 隐私会话 / 本会话尚未
  // 提交（回放重建的 graph 行 id 即节点 id，无需本字段）
  nodeId?: string;
  // ── 实时行标记（2026-09-27 自检余项收口 A3；kind=user/assistant 专用）──
  // true = 本行诞生于页面实时链（发送/续轮/重试承载行），id 为内存 id；其图身份只认显式
  // 回填 nodeId，禁 id 回退（判据单源 = ChatBranchPolicy.resolveNodeIdOf）。不入库、不参与
  // 回放构造。★ 非 user/assistant 的实时行（工具卡/notice/thinking 等）一律不标——它们不是
  // 「更多」菜单目标行，nodeIdOf 对其取值无消费方；将来若给这些行开菜单或新增吃 nodeIdOf
  // 的入口，须同步补标
  live?: boolean;
  // ── 附件简报（2026-09-15 预览第三轮；kind='user' 专用——带附件的消息装配）──
  // 与 streaming/tail 同族「运行时字段」，但口径差异：**回放由装配链写入**（不是「不参与
  // 回放构造」——ChatPageLoad 加载后按 id 归并赋值，翻页前插同链）；不入库、不参与
  // insertMessage（元数据真源 = message_attachments 表）。发送链写点 =
  // ChatSendCtrl.dispatchSend（briefsFromPending，隐私会话同样装配——内存态齐备是隐私
  // 预览成立的前提）；装配后经 @Observed/@ObjectLink 对象级观察驱动气泡渲染
  attachBriefs?: AttachmentBrief[];
  // ── 引用全文快照（2026-10-21 方案-引用功能全链路 U-C；kind='user' 专用——被引用内容的
  // 已发事实）── 与 attachBriefs 差异：**本字段有库列真源**（messages.quote_text，DB v61）
  // ——入库经 prepareRun bucket 条件写键、回放由 chatMessagesFromRows 从行投影挂值、
  // 实时由 dispatchSend 挂值（回放/实时同址纪律，rowSeq 同族口径）；text 恒存用户原文，
  // 引用块前缀只在组装层拼装。undefined = 无引用不渲染
  quoteText?: string;
  // ── DeepSeek 服务端工具原样 JSON 串（DS 全家桶接入批 S2⑥；kind='assistant' 专用——
  // 本轮服务端搜索/读链接的完整事实，{"server_tool_calls":…,"annotations":…} 原样串）──
  // 与 quoteText 同族「库列真源」字段（messages.server_tools，DB v64）：回放由
  // chatMessagesFromRows 从行投影挂值；实时由流域写——中间轮 settleRoundAssistant 读
  // settlement 快照挂、终轮 finishStream 挂（回放/实时同址纪律）。消费方 = 请求回传
  //（buildRequestHistory → composeOpenAiBody 仅官方档轮输出 server_tool_calls，原样透传
  // 禁截断）与 S3 渲染（步骤行合成 / M1 来源卡）。undefined = 非官方档轮/无服务端步骤
  serverToolsJson?: string;
  // 官方服务端工具计次（二期 #7；v65 账本回放或当轮收尾挂载）：undefined = 无计次（用量
  // 气泡不出现三行）。只读展示料，不参与协议回传
  serverToolUse?: AiServerToolUse;
  // ── M1 来源卡展开意愿（来源卡折叠笔；kind='assistant' 专用）── 与 attachBriefs 同族
  //「运行时字段」：**不入库、不参与回放构造**（undefined 即收起——回放行天然收起，展开是
  // 用户当次阅读动作不该跨会话记忆）。写点 = 来源卡头点击切换与正文角标点击联动展开（均经
  // @Observed 属性赋值驱动刷新，照 ChatDisplayItem.changesExpanded 先例）；刷新承接 =
  // ChatMessageItem @ObjectLink。不进 ForEach 键（键纪律——卡级意愿非行身份）
  dsSourcesExpanded?: boolean;
  // ── 消息后推荐问题（2026-09-19 推荐问题功能；kind='assistant' 专用——末条已完成助手
  // 消息的追问推荐 chips）──
  // 与 attachBriefs 同族「运行时字段」：**回放由装配链写入**（ChatPageLoad.loadHistory
  // 读会话行 suggestions 列挂末条助手消息；loadOlder 前插批不挂）+ **实时由广播写入**
  //（ChatPageContent 订阅 SUGGEST_PAYLOAD_KEY 按 msgId 命中后原地赋值；发送清空广播
  // items 空 = 复位 undefined）；不入库（真源 = conversations.suggestions 列）、不参与
  // insertMessage。undefined 即不渲染——发送链 push 的占位/回放中间行天然无
  suggestions?: string[];
  // ── 压缩边界数据（2026-09-23 上下文压缩；写入侧与回放链挂值、发送组装消费）──
  // rowSeq = 该行在库的 seq。**两处挂值**：① 回放链（rebuildFromHistory / prepend 从行投影
  // 赋值）；② **落库同址**——四类写入点在构造 MessageRow 的同一同步块里，把铸造好的号回填
  // 内存行（ChatSendCtrl 的 user/assistant 两行、ChatToolRoundCtrl 续轮占位行、ChatRetryCtrl
  // 重试承载行）。★ ② 是 2026-09-23 自检轮补的 P1：此前只挂 ①，本会话新发的消息恒无号 ⇒
  // CompressGen 选段在全 live 会话里恒回 null（压缩键永久置灰且文案误报「历史还短」），组装
  // 侧也只裁得动回放段。仍 undefined 的两类 = 不落库的流内行（工具卡/notice/thinking）与隐私
  // 会话行（零落库无号）——组装侧 fail-open 一律不裁。消费方 = ChatHistoryBuilder 的被压段
  // 判据（rowSeq ≤ boundary 不进请求）与 CompressGen 选段
  rowSeq?: number;
  // coversToSeq = **边界行**的覆盖边界（kind='summary' 摘要行 / 'clear' 清空行都挂——本条
  // 边界覆盖到的最大 seq 含；清空行不带正文、boundary 是唯一载荷）；真源 = summary_bindings
  // 绑定行（图侧；messages.coversToSeq 列只承载导入导出保真，图行恒 NULL）。
  // 这两个字段**不入库**（rowSeq/coversToSeq 的持久真源就是库列与绑定行，回放时从投影回填）
  coversToSeq?: number;
  // ── 自动重试状态行（2026-09-22 聊天自动重试笔；kind='assistant' 专用）──
  // 非空 = 该助手气泡内正在显示这一行小字（「请求失败，正在重试 1/3」，数字随次数原地更新；
  // 前缀已中性化——2026-09-24 HTTP 优化笔2 起 5xx 也在重试面，不再单指网络异常）。
  // 与 toolConfirmText 同款「运行时字段」口径：**不入库、不参与回放构造**——undefined 即
  // 「无重试」，重进会话回放出来的历史消息天然为 undefined（状态行不跨会话存活）。
  // 写点唯一 = ChatHostDelegates.setRetryHint（2026-09-25 拆分前在 ChatSendCtrl；自动重试域
  // 经 ChatAutoRetryHost 调用：接管时写、有内容上屏首帧与轮次收尾两处清），只改 Message
  // 对象的本字段一个值、不新增消息行、不动库行与 variants；刷新靠 @Observed 对象级观察
  //（原地改即重渲），不换正文渲染身份（不推绑定/世代——状态行只增显示小字）
  retryHint?: string;
  // ── 错误 notice 跳转动作（2026-09-25 错误 notice 跳转入口笔；kind='notice' 专用）──
  // 'provider' = 密钥失效类（HTTP 401/403）→ 服务商管理页、'network' = 传输层失败类
  //（status = -1）→ 网络设置页；undefined = 无动作（429/5xx/普通提示 notice 纯文本不可点）。
  // 照 retryHint 同款「运行时字段」口径：**不入库、不参与回放构造**——**推论：重进会话后
  // 跳转入口不再出现**。这是有意选择：历史错误无法追溯归类（回放链无 HTTP status 上下文），
  // 运行时字段即语义正确的承载。写点唯一 = ChatStreamFlowCtrl.failRound（宿主薄委托转接；
  // 2026-09-27 拆分笔随形。分类判据单源
  // noticeActionOf 在本文件）；刷新 = 行构造前赋值首帧即带，「›」与 onClick 判据在
  // ChatMessageItem notice 分支
  noticeAction?: string;
  // ── 截断尾注（2026-09-23 输出上限与超时治理笔 2；kind='assistant' 专用）──
  // true = 本条回答被输出上限截断（思考 token 与正文共享同一预算打满即真，四协议标记见
  // SseParser.SseDelta.truncated），气泡正文下方出一行提示。与 retryHint 同款「运行时字段」
  // 口径：**不入库、不参与回放构造**——**推论：重进会话后该提示不再出现**（回放不恢复）。
  // 这是有意选择：加 DB 列要新迁移而收益仅是历史可查，超出本笔范围，故不做。
  // 写点唯一 = ChatStreamFlowCtrl.finishStream（宿主薄委托转接；2026-09-27 拆分笔随形。
  // 挂轮级累积快照的 truncated，与 streaming/tail 同段；
  // 隐私会话同样挂——判据差异见彼处注释）；刷新靠 @Observed 对象级观察（原地改即重渲），
  // 不换正文渲染身份（尾注只追加一行不动正文）
  truncated?: boolean;
  // ── 消息创建时刻（2026-09-24 时间感知治理·时间间隔提醒；★ 2026-10-12 消息时间头笔起
  // **进渲染**——用户时间行与助手轮头行的时间显示源）──
  // 消息创建时刻（毫秒），来源 = messages.createdAt 列（库列早已存在，**不入库新列**），
  // 供发送组装的时间间隔判定（RequestInject.injectTimeReminders）。挂值三路 = 回放链
  // （行投影）+ 落库同址（构造 MessageRow 的同步块回填内存行，与 rowSeq 同族口径）+
  // ★ 2026-10-12 S-1 修复：回放侧助手侧三类（assistant/thinking/tool）在数据源安装口
  // **按轮起始时刻归一**（轮事实 startMs = generation_runs.createdAt——普通轮 = 派发时刻
  //〔与 user 行同值〕、重试轮 = 重试时刻、主动消息轮 = 生成派发时刻；见投影件
  // alignRoundStartTimes），与实时链同语义（派发即轮起始）；user 行保留库行时刻（即其
  // 发送时刻——用户时间行显示源）。不参与序列化（请求组装仅取作判定素材，不带出协议字段）。
  // undefined / 0 = 无值可判（fail-open 不插提醒不炸；时间行按 >0 才挂）。
  // kind 局限 = user/assistant 行（间隔语义只需对话消息；thinking/tool 行回放同值挂上
  // 仅为一致性——轮首项为过程段时头行取 steps[0] 本值，见 ChatProcessSegment）
  createdAt?: number;
  // ── 轮头与轮级模型名（2026-10-12 消息时间头笔）──
  // headHost：true = 本条是所属回复轮**首个上屏项**且载体为正文/状态行——轮头行（头像 +
  // 模型名 + 时间）只在本条渲染，轮内其余项不重复（「同一轮只出一个头行」）。写点唯一 =
  // 展示投影 buildDisplayItems 的全表刷新（值同不写，照 opsHost 同款口径）；段载轮头不在
  // 本字段（轮首项为过程段时标记落 ChatDisplayItem.head，两载体互斥）。
  // 与既有运行时字段同口径：不入库、不参与回放构造，数据源整体重建即随新对象归零
  //（undefined 按非真消费，`=== true` 判据）。
  headHost?: boolean;
  // ── 空轮性质标记（2026-10-23 空消息语义分离笔；展示投影写入、轻量状态行文案共读）──
  // '' / undefined = 非「空正文状态行」行（不参与判定）；'no-text' = 本轮正常收束且轮内有
  // 过程步骤（工具/思考在动），只是没有正文——中性陈述；'no-reply' = 异常轮（error/stopped）
  // 或整轮零产出——沿用无产出口径。判据看**承接物**不看空不空（有过程产出 ≠ 没回复）；
  // 判据单源 = ChatDisplayProjection.buildDisplayItems 全表刷新（禁第二处判据写法）。
  // 与 opsHost/headHost 同口径：不入库、不参与回放构造，数据源整体重建随新对象归零
  //（`=== 'no-text'` 消费，undefined 按非真）。
  emptyRoundKind?: string;
  // ── 回答版本步进（2026-10-25 rik 形态统一笔；ChatAnswerCtrl.recomputeRowVersions 写入、
  // 操作栏步进器共读）──
  // ansVersionCount：本轮「其他回答」候选总数（<2 即无步进器；空正文失败轮不参与——
  // 归组纯函数只收非空末正文，与面板口径同源）；ansVersionIndex：当前屏幕勾在候选中的
  // 序位（0 起）；ansPrevBranch / ansNextBranch：相邻候选的代表分支 id（'' = 已在边界，
  // 对应箭头不可点）。写点唯一 = ChatAnswerCtrl 重算（图快照 + buildAnswerChoices 逐轮
  // 求；值同不写）。与 opsHost/headHost 同口径：不入库、不参与回放构造，数据源整体重建
  // 随新对象归零（重算触发 = 装载/换源收尾 + 轮落库回填后广播 + 面板删除后）。
  ansVersionCount?: number;
  ansVersionIndex?: number;
  ansPrevBranch?: string;
  ansNextBranch?: string;
  // ── 提问版本步进（★ 2026-10-25 rik 形态统一笔二：user 行 ◀x/y▶）──
  // 语义与上组同构，但分组维度 = 「同一 parent 下的 user 兄弟节点」（编辑产出提问变体）；
  // 写点同样唯一 = ChatAnswerCtrl.recomputeRowVersions（buildQuestionChoices 逐行求）。
  // 仅 user 行消费；assistant 行恒 undefined（两套字段互不干扰）
  qsVersionCount?: number;
  qsVersionIndex?: number;
  qsPrevBranch?: string;
  qsNextBranch?: string;
  // modelLabel：本轮模型名（显示用短名，如 'deepseek-flash'）——轮头行模型名行的轮级真值。
  // 挂值三路 = ①实时：dispatchSend 占位行创建同址写 conn.model；②回放首载：ChatPageLoad
  // 按账本 token_usage_events.modelId → 轮 id → 本轮助手侧消息（thinking/tool/assistant）
  // 批量回填（头行载荷在轮首，两载体都可能取用故写全）；★ 2026-10-12 S-2 修复补 ③回放
  // 翻页批：loadOlder 后补一次同源账本读**只补缺**（首载窗外旧轮此前恒空、头行回落会话
  // 当前模型名——切过模型的会话上滑旧页即见错标）。'' / undefined = 无值可显
  //（头行回退会话当前模型名广播键）。不入库（真源 = 账本列）、不参与回放构造
  modelLabel?: string;
  // ── 长消息自动折叠展开意愿（2026-10-15 渲染性能与五项功能优化批 U4d）──
  // true = 用户已点「展开全文」——折叠判据让位（展开即最终意图，列表项组件被回收重建后
  // 不回折——意愿随消息对象存活）；undefined = 未手选（按偏好开关与阈值默认收起）。
  // 判据单源 = MarkdownScrollableBlock.shouldCollapseLongMessage（消费点 ChatMessageItem
  // 助手正文分支）。与 truncated 同款「运行时字段」口径：**不入库、不参与回放构造**，
  // 数据源整体重建随新对象归零；刷新靠 @Observed 对象级观察（原地改即重渲）
  longMsgExpanded?: boolean;
  // ── 进页折叠时点标记（★ 2026-10-18 全折叠笔，与 longMsgExpanded 同为运行时字段、
  // 不入库不参与回放）──：true = 本次进入会话那一刻该消息已终态（非流式）且超阈值——
  // 首建即按收起态渲染，覆盖 live=true 的运行态复用消息（重进 5 秒窗内）；进页后新完成
  // 的流式回复不会被标记，保持展开。每次进页由 ChatDataSource.resetLongMessageExpansion
  // 全量重算，展开意愿同时复位。重生成/续答路径均新建承载行或换源重载（2026-10-18 探查），
  // armed 不随旧对象复用；消费点另有 streaming 守卫。
  longMsgCollapseArmed?: boolean;
  // ── 占位揭示标记（★ 2026-10-18 一次出现笔，替代原 longMsgRevealing，运行时字段、
  // 不入库不参与回放）──
  // true = 该行长正文处于「占位构建」期：正文层以 opacity 0 在行内分帧建块（布局成本逐帧
  // 分摊、绘制不产生），行内只显示静态骨架；揭示完成一次性显现（不做逐块可见生长）。
  // 写点两路——①用户点「展开全文」当帧由本行直接置位（骨架先实际绘制一帧，动画不得盖住
  // 被阻塞主线程）；②滚动中挂载的行由正文链上行置位（调度器滚动暂停期不建可见块）。
  // 清位 = 揭示完成或组件回收的 onRevealDone 上行；每次进页由
  // resetLongMessageExpansion 一并复位。消费点 = 骨架/不透明度判据（ChatMessageItem）、
  // 尾先判据（占位不可见，恒头先）、揭示期行高静默（ChatPageContent onAreaChange）。
  bodyPlaceholder?: boolean;
}

// 消息构造工厂（@Observed 类禁止对象字面量构造——统一入口保证 new 语义；
// 六必填字段外的可选字段由调用方在返回实例上按需赋值）
export function newChatMessage(id: string, kind: string, text: string, toolName: string = '',
  toolState: string = '', level: string = ''): ChatMessage {
  const msg: ChatMessage = new ChatMessage();
  msg.id = id;
  msg.kind = kind;
  msg.text = text;
  if (kind === 'assistant' || kind === 'user') {
    msg.bodyBindingId = nextMarkdownBindingId();
  }
  msg.toolName = toolName;
  msg.toolState = toolState;
  msg.level = level;
  return msg;
}

// ═══ 过程步骤状态判据与图标分流（自 ChatToolCard 私有方法收编为视图模型级单源函数族——
// 过程壳 ChatProcessSegment 需在卡外渲染统一步骤图标列；「过程段折叠（等待用户处理的步骤
// 常显）」与「工具步骤标题/图标分流」两侧共读，禁第二份判据写法）═══

// 提问卡判据（工具名）
export function isAskCard(msg: ChatMessage): boolean {
  return msg.toolName === TOOL_ASK_USER;
}

// 提问卡（等待作答）：running 即等作答（问题列表在场与否交卡体兜底提示）
export function isAskAwaiting(msg: ChatMessage): boolean {
  return isAskCard(msg) && msg.toolState === 'running';
}

// 提问卡「放弃」标记（★ U11 域⑤ 2026-10-16；单源：卡片放弃键经统一答案上行通道提交本标记，
// 续答件按标记分流——同进程有内存桥 = 既有停止链（abort 跨域分发），重进后无桥 = 库侧收口
//（等待行置中止态 + run interrupted）防永挂。标记值与 AskPayload 真实载荷形态不重叠
//（用户答案恒为 buildPayload 产出的 answers 结构），不会误命中）
export const ASK_ABANDON_MARK: string = '{"ask_abandon":true}';

// 确认等待中（判据安全性：ask 分支在同链前位先行拦截；toolConfirmText 全工程仅确认链写入、
// 作答后仍保留 ⇒ 非要「running 且无 result」不足以表达等待态）
export function isConfirmAwaiting(msg: ChatMessage): boolean {
  return msg.toolState === 'running' && (msg.toolConfirmText ?? '') !== '' &&
    msg.toolConfirmResult === undefined;
}

// 确认回执（作答已落位即回执行；运行时字段，重进会话退回普通工具卡）
export function isConfirmDone(msg: ChatMessage): boolean {
  return msg.toolConfirmResult !== undefined;
}

// 确认档位是否不可逆（图标与档位徽章判据；undefined = 写操作档兜底）
export function isConfirmIrreversible(msg: ChatMessage): boolean {
  return msg.toolConfirmLevel === CONFIRM_LEVEL_IRREVERSIBLE;
}

// 工具步骤是否正等待用户处理（投影的两个消费点：①常显判据——等待步骤不计入「最后两步」
// 名额且即便在早段也保持可见；②轮收束判据——等待中的轮不算收束，不给最终正文挂操作栏）
export function isStepAwaitingUser(msg: ChatMessage): boolean {
  return isAskAwaiting(msg) || isConfirmAwaiting(msg);
}

// 工具步骤图标分流（过程壳 gutter 图标列单源；与卡面头行三分支同源——确认卡按档位
// lock / 警告三角、提问卡 message、通用 gearshape。提问卡两态同取 message（回执行亦为
// 提问语义），不依赖回执解析结果，故与卡面头行的 askDone 解析边角无关）
export function toolStepIcon(msg: ChatMessage): Resource {
  if (isConfirmAwaiting(msg) || isConfirmDone(msg)) {
    return isConfirmIrreversible(msg) ? $r('sys.symbol.exclamationmark_triangle') :
      $r('sys.symbol.lock');
  }
  if (isAskCard(msg)) {
    return $r('sys.symbol.message');
  }
  return $r('sys.symbol.gearshape');
}

// 错误 notice 跳转动作分类单源（2026-09-25 错误 notice 跳转入口笔；failRound 写入侧与本
// 文件 noticeAction 字段注释、断言真值表三方共用——改分类先改这里）。拍板依据 = 上位档
// 「HTTP 网络层优化」笔⑤：密钥问题归服务商页、网络问题归网络页；429/5xx/协议错误帧(-2)/
// 无码哨值(0) 无明确去向，一律不设动作（notice 保持纯文本不可点——任务书 §3）。
// 返回 '' = 无动作。
export function noticeActionOf(status: number): string {
  if (status === 401 || status === 403) {
    return 'provider';
  }
  if (status === -1) {
    return 'network';
  }
  return '';
}

// ═══ DS 服务端步骤视图模型域（DS 全家桶接入批 S3；S3① 步骤行 / M1 来源卡 / M2 角标 /
// 回放合成四方共用的纯函数族——坏 JSON / 缺键防御回缺省，渲染与回放容错不炸）═══
// call 结构（任务书 §0）：type（两工具名）/ kind（search 系或 image 系）/ action
//（search{queries} / open_page{url} / find_in_page{url,pattern} / read_link{url}）/ status /
// sources（url/title/snippet…）；外层 serverToolsJson = {"server_tool_calls":…,"annotations":…}。

// call 对象的渲染面视图（dsCallViewOf 私有解析产物；字段缺席回缺省）
interface DsCallView {
  toolType: string;
  actionType: string;
  image: boolean;
  queries: string[];
  url: string;
  pattern: string;
}

function dsCallViewOf(callJson: string): DsCallView | null {
  if (callJson === '') {
    return null;
  }
  try {
    const rec: Record<string, Object> = JSON.parse(callJson) as Record<string, Object>;
    const toolType: string = typeof rec['type'] === 'string' ? rec['type'] as string : '';
    const kind: string = typeof rec['kind'] === 'string' ? rec['kind'] as string : '';
    let actionType: string = '';
    let queries: string[] = [];
    let url: string = '';
    let pattern: string = '';
    const action: Object | undefined = rec['action'];
    if (typeof action === 'object' && action !== null) {
      const arec: Record<string, Object> = action as Record<string, Object>;
      actionType = typeof arec['type'] === 'string' ? arec['type'] as string : '';
      const rawQueries: Object | undefined = arec['queries'];
      if (Array.isArray(rawQueries)) {
        for (const q of rawQueries as object[]) {
          if (typeof q === 'string' && q !== '') {
            queries.push(q);
          }
        }
      }
      url = typeof arec['url'] === 'string' ? arec['url'] as string : '';
      pattern = typeof arec['pattern'] === 'string' ? arec['pattern'] as string : '';
    }
    return { toolType: toolType, actionType: actionType,
      image: kind === 'image_search' || kind === 'deep_image_search',
      queries: queries, url: url, pattern: pattern };
  } catch (e) {
    return null;
  }
}

// ── Responses 列载荷归一（二期 S3）──
// 列载荷 {"protocol":"responses","items":[…]}
// → 显示面三纯函数吃的 CC 信封 {"server_tool_calls":[{"index":n,"calls":[call]}],"annotations":[…]}
// items 内 web_search_call 按官方字段直搬（type/kind/action/status/sources/page，signature
// 不读）；message item 的 content[].annotations（url_citation）汇总为 annotations。无 protocol
// 键 / 坏串 = 原样返回（CC 旧行零变化，负向零回归）。★ 与 SseResponsesParse 的流内归一分职：
// 那边归一「流事件 → 步骤行」（实时建行），本处归一「落库信封 → 回放显示」
//（合成 / 来源卡 / 角标）——同一官方形态的两个消费时机，各自零依赖实现
//（两边都要求剥 import 可直跑）
export function dsNormalizeServerTools(serverToolsJson: string): string {
  if (serverToolsJson === '') {
    return '';
  }
  let root: Record<string, Object>;
  try {
    root = JSON.parse(serverToolsJson) as Record<string, Object>;
  } catch (e) {
    return serverToolsJson;
  }
  if (root === null || typeof root !== 'object' || root['protocol'] !== 'responses') {
    return serverToolsJson;
  }
  const items: Object | undefined = root['items'];
  if (items === undefined || items === null || !Array.isArray(items)) {
    return serverToolsJson;
  }
  const steps: Record<string, Object>[] = [];
  const annotations: Object[] = [];
  let stepIndex: number = 0;
  for (const item of items as Object[]) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      continue;
    }
    const rec: Record<string, Object> = item as Record<string, Object>;
    const itemType: string = typeof rec['type'] === 'string' ? rec['type'] as string : '';
    if (itemType === 'web_search_call') {
      const kind: string = typeof rec['kind'] === 'string' ? rec['kind'] as string : '';
      const call: Record<string, Object> = {};
      call['type'] = kind === 'read_link' ? DS_SERVER_TOOL_READ_URL : DS_SERVER_TOOL_WEB_SEARCH;
      if (kind !== '') {
        call['kind'] = kind;
      }
      if (rec['action'] !== undefined && rec['action'] !== null) {
        call['action'] = rec['action'];
      }
      if (typeof rec['status'] === 'string' && rec['status'] !== '') {
        call['status'] = rec['status'] === 'failed' ? 'failed' : 'completed';
      }
      if (Array.isArray(rec['sources'])) {
        call['sources'] = rec['sources'];
      }
      if (rec['page'] !== undefined && rec['page'] !== null) {
        call['page'] = rec['page'];
      }
      if (typeof rec['id'] === 'string' && rec['id'] !== '') {
        call['id'] = rec['id'];
      }
      const calls: Record<string, Object>[] = [call];
      const step: Record<string, Object> = {};
      step['index'] = stepIndex;
      step['calls'] = calls;
      steps.push(step);
      stepIndex++;
      continue;
    }
    // 引用标注：message item 的 content 数组里 output_text 段携带 annotations（官方嵌套
    // url_citation 形态，与 CC annotations 同形——来源卡与角标解析函数直接吃）
    if (itemType === 'message' && Array.isArray(rec['content'])) {
      for (const part of rec['content'] as Object[]) {
        if (part === null || typeof part !== 'object' || Array.isArray(part)) {
          continue;
        }
        const p: Record<string, Object> = part as Record<string, Object>;
        if (Array.isArray(p['annotations'])) {
          for (const a of p['annotations'] as Object[]) {
            annotations.push(a);
          }
        }
      }
    }
  }
  if (steps.length === 0 && annotations.length === 0) {
    return serverToolsJson;
  }
  const envelope: Record<string, Object> = {};
  envelope['server_tool_calls'] = steps;
  if (annotations.length > 0) {
    envelope['annotations'] = annotations;
  }
  return JSON.stringify(envelope);
}

// serverToolsJson → call 原样串数组（server_tool_calls 按步组织的 calls 展开；串值保真
//——parse 后逐 call 原样 stringify，与实时链 callJson 同口径）。消费方 = 回放合成
//（ChatMessageProjection）与来源卡/角标（本文件下游）。坏 JSON / 非 step 数组回空数组
export function dsServerCallJsonsOf(serverToolsJson: string): string[] {
  const json: string = dsNormalizeServerTools(serverToolsJson);
  if (json === '') {
    return [];
  }
  try {
    const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    const raw: Object | undefined = parsed['server_tool_calls'];
    if (!Array.isArray(raw)) {
      return [];
    }
    const calls: string[] = [];
    for (const step of raw as object[]) {
      const rec: Record<string, Object> = step as Record<string, Object>;
      const stepCalls: Object | undefined = rec['calls'];
      if (!Array.isArray(stepCalls)) {
        continue;
      }
      for (const call of stepCalls as object[]) {
        calls.push(JSON.stringify(call));
      }
    }
    return calls;
  } catch (e) {
    return [];
  }
}

// 步骤行标题 = action 短句（面向用户文案：并列顿号、无冒号分号连环）。映射 =
// search→「搜索」+queries（image 系→「图片搜索」）、open_page→「打开网页」、
// find_in_page→「页内查找」、read_link→「读链接」；action 缺席按 call.type 兜底；
// 双缺省「联网操作」
export function dsStepTitleOf(callJson: string): string {
  const view: DsCallView | null = dsCallViewOf(callJson);
  if (view === null) {
    return '联网操作';
  }
  if (view.actionType === 'search') {
    const prefix: string = view.image ? '图片搜索' : '搜索';
    return view.queries.length > 0 ? prefix + ' ' + view.queries.join('、') : prefix;
  }
  if (view.actionType === 'open_page') {
    return '打开网页';
  }
  if (view.actionType === 'find_in_page') {
    return '页内查找';
  }
  if (view.actionType === 'read_link') {
    return '读链接';
  }
  if (view.toolType === DS_SERVER_TOOL_WEB_SEARCH) {
    return '联网搜索';
  }
  if (view.toolType === DS_SERVER_TOOL_READ_URL) {
    return '读链接';
  }
  return '联网操作';
}

// 步骤行明细行（第二行小字）：打开网页/读链接 = URL、页内查找 = 查找词（空回退 URL）；
// 搜索类无明细行（queries 已在标题，来源上来源卡）。空串 = 不渲染
export function dsStepDetailOf(callJson: string): string {
  const view: DsCallView | null = dsCallViewOf(callJson);
  if (view === null) {
    return '';
  }
  if (view.actionType === 'open_page' || view.actionType === 'read_link') {
    return view.url;
  }
  if (view.actionType === 'find_in_page') {
    return view.pattern !== '' ? view.pattern : view.url;
  }
  return '';
}

// 步骤行图标（符号全部取全仓在场证据——坑72：magnifyingglass/picture/link/doc_text/
// doc_plaintext/gearshape 五面既有消费点）；action 判据优先、type 兜底
export function dsStepIconOf(callJson: string): Resource {
  const view: DsCallView | null = dsCallViewOf(callJson);
  if (view !== null) {
    if (view.actionType === 'search') {
      return view.image ? $r('sys.symbol.picture') : $r('sys.symbol.magnifyingglass');
    }
    if (view.actionType === 'open_page') {
      return $r('sys.symbol.link');
    }
    if (view.actionType === 'find_in_page') {
      return $r('sys.symbol.doc_text');
    }
    if (view.actionType === 'read_link') {
      return $r('sys.symbol.doc_plaintext');
    }
    if (view.toolType === DS_SERVER_TOOL_WEB_SEARCH) {
      return $r('sys.symbol.magnifyingglass');
    }
    if (view.toolType === DS_SERVER_TOOL_READ_URL) {
      return $r('sys.symbol.doc_plaintext');
    }
  }
  return $r('sys.symbol.gearshape');
}

// serverstep 段折叠态摘要（「已搜索 N 次」级一句——N 与动词按 call 类型聚合，并列顿号）；
// 段内无 serverstep 步骤或全部坏串回 ''（调用方回落 segmentSummaryText 既有文案）
export function dsServerSegmentSummary(steps: ChatMessage[]): string {
  let search: number = 0;
  let image: number = 0;
  let open: number = 0;
  let find: number = 0;
  let read: number = 0;
  for (const step of steps) {
    if (step.kind !== 'serverstep') {
      continue;
    }
    const view: DsCallView | null = dsCallViewOf(step.toolOutputJson ?? '');
    if (view === null) {
      continue;
    }
    if (view.actionType === 'search') {
      if (view.image) {
        image++;
      } else {
        search++;
      }
    } else if (view.actionType === 'open_page') {
      open++;
    } else if (view.actionType === 'find_in_page') {
      find++;
    } else if (view.actionType === 'read_link') {
      read++;
    }
  }
  const parts: string[] = [];
  if (search > 0) {
    parts.push('已搜索 ' + search.toString() + ' 次');
  }
  if (image > 0) {
    parts.push('已搜图 ' + image.toString() + ' 次');
  }
  if (open > 0) {
    parts.push('已打开 ' + open.toString() + ' 个网页');
  }
  if (find > 0) {
    parts.push('已页内查找 ' + find.toString() + ' 次');
  }
  if (read > 0) {
    parts.push('已读 ' + read.toString() + ' 个链接');
  }
  return parts.join('、');
}

// ── M1 来源卡（消息级来源列表）──去重口径：URL trim 后精确等值，搜索 sources 先（带
// snippet，按 call 顺序）、read_link 的 page 次之（读了未引用的页面也进卡）、annotations
// 最后补位（按注顺序）；空 URL 恒跳过。title 缺省空串由渲染面回退 URL。序号 = 1 起稳定序
//（M2 角标同源——角标号即本表序号）。★ 2026-11-14 自检报告 §4.2 修：首版只收 sources 与
// annotations，官方 read_link 的 page{url,title,published_at} 未收——读了但未被正文引用的
// 页面不进来源卡（用户看不到「已读」的出处）；page 段落在 sources 与 annotations 之间，
// 既有条目的相对次序不变（同一 URL 仍由先到段占号）
export interface DsSourceEntry {
  number: number;
  url: string;
  title: string;
  snippet: string;
}

// read_link 的 page 摘要（仅两字段进来源卡；published_at 不展示）
interface DsPageRef {
  url: string;
  title: string;
}

// annotations 单注解析（官方形态嵌套：{type:'url_citation', url_citation:{url,title,
// start_index,end_index}}——2026-11-14 自检轮实证，api-docs 原文与 CC 多轮章节一致）。
// ★ 扁平形态 {url,title,...} 是 S3 首版误读（同批断言同步以扁平夹具自洽，故长期全绿）：
// 真实响应下 url 恒缺席 ⇒ 来源卡漏 annotations 段、M2 角标恒空。本函数为该形态唯一解析点，
// 来源卡与角标两消费方共用（禁各自再展开）；start/end 缺席回 -1（由调用方按非法跳过）。
interface DsAnnotationView {
  url: string;
  title: string;
  startCp: number;
  endCp: number;
}

function dsAnnotationViewOf(value: Object): DsAnnotationView | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const inner: Object | undefined = rec['url_citation'];
  if (typeof inner !== 'object' || inner === null || Array.isArray(inner)) {
    return null;
  }
  const cite: Record<string, Object> = inner as Record<string, Object>;
  return {
    url: typeof cite['url'] === 'string' ? cite['url'] as string : '',
    title: typeof cite['title'] === 'string' ? cite['title'] as string : '',
    startCp: typeof cite['start_index'] === 'number' ? cite['start_index'] as number : -1,
    endCp: typeof cite['end_index'] === 'number' ? cite['end_index'] as number : -1
  };
}

// ── 图搜结果宫格取数（DS 全家桶二期 S4 #8）──
// 单组渲染上限（任务书 §6-S4 定值 20）：只截渲染不截数据——多出的图不进树，内存与首帧都
// 有界；不提示「还有 N 张」（图搜结果的完整性不是用户需要知道的事，提示反而噪声）
export const DS_IMAGE_GRID_MAX: number = 20;

// 宫格单张（url = 可直载的图片地址；pageUrl = 来源网页，'' = 无）
export interface DsImageItem {
  url: string;
  pageUrl: string;
  title: string;
  index: number; // 组内序号（1 起；ForEach 键与无障碍朗读用）
}

// 图片 URL 候选键（顺序即优先级）。★ 只列**明确的图片语义键**：官方搜索结果里的 `url` /
// `source_page_url` 是**网页地址**，当图片直载必失败（Image 显示占位框），故不列入——宁可
// 宫格不出现，也不把网页当图渲染出一排占位。★ 官方历史导出（demo ImageSearchResult）只有
// title / source_page_url / snippet / site_name / published_at，**无图片 URL 字段**；流式
// Responses 的 web_search_call.sources 官方未公开完整形态。故本取数按候选键探测：任一命中
// 即出宫格，全不命中回空数组（宫格不出现，零噪声）。真机若仍无宫格 = 官方确实不下发图片
// 地址，届时保持「不出现」而不产生占位噪音（本批如实登记该口径）
const DS_IMAGE_URL_KEYS: string[] = ['image_url', 'imageUrl', 'thumbnail_url', 'thumbnailUrl',
  'thumbnail', 'thumb_url', 'thumb', 'cover_url', 'coverUrl', 'cover', 'pic_url', 'picUrl',
  'img_url', 'imgUrl', 'picture_url'];

// 宽松串读（键缺席/非串回 ''）
function dsStrFieldOf(rec: Record<string, Object>, key: string): string {
  const value: Object | undefined = rec[key];
  return typeof value === 'string' ? value as string : '';
}

// 单条 source 的图片地址探测：按候选键序找第一个 http(s) 串；非绝对地址一律跳过（相对路径
// 无法直载，交给不出现）
function dsImageUrlOf(rec: Record<string, Object>): string {
  for (const key of DS_IMAGE_URL_KEYS) {
    const value: string = dsStrFieldOf(rec, key);
    if (value === '') {
      continue;
    }
    const lower: string = value.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return value;
    }
  }
  return '';
}

// 列载荷 → 宫格条目（纯函数，断言直跑）。只认 kind 含 image 的调用（image_search /
// deep_image_search / 官方 image 变体），其余调用的 sources 是网页结果、不进宫格
export function dsImageGridOf(serverToolsJson: string): DsImageItem[] {
  const out: DsImageItem[] = [];
  const callJsons: string[] = dsServerCallJsonsOf(serverToolsJson);
  // 单 call 形态兜底（自检轮修）：serverstep 行的 toolOutputJson 是**单个 call 对象**（实时
  // 事件写点与回放投影同源），而 dsServerCallJsonsOf 只认合体信封——首版直接喂它，宫格恒空、
  // 展开区永不可达。信封版优先，剥不出调用时按单 call 试一次（无 kind 的坏串自然跳过）
  if (callJsons.length === 0 && serverToolsJson.trim().startsWith('{')) {
    callJsons.push(serverToolsJson);
  }
  for (const callJson of callJsons) {
    let call: Record<string, Object>;
    try {
      const parsed: Object = JSON.parse(callJson) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        continue;
      }
      call = parsed as Record<string, Object>;
    } catch (e) {
      continue;
    }
    const kind: string = dsStrFieldOf(call, 'kind');
    if (!kind.includes('image')) {
      continue;
    }
    const sources: Object | undefined = call['sources'];
    if (sources === undefined || sources === null || !Array.isArray(sources)) {
      continue;
    }
    for (const src of sources as Object[]) {
      if (out.length >= DS_IMAGE_GRID_MAX) {
        return out;
      }
      if (src === null || typeof src !== 'object' || Array.isArray(src)) {
        continue;
      }
      const rec: Record<string, Object> = src as Record<string, Object>;
      const url: string = dsImageUrlOf(rec);
      if (url === '') {
        continue;
      }
      const pageUrl: string = dsStrFieldOf(rec, 'source_page_url') !== '' ?
        dsStrFieldOf(rec, 'source_page_url') : dsStrFieldOf(rec, 'url');
      out.push({ url: url, pageUrl: pageUrl, title: dsStrFieldOf(rec, 'title'),
        index: out.length + 1 });
    }
  }
  return out;
}

// 来源域名（站点徽标用，纯函数）：去协议 → 去路径/查询/锚点 → 去端口 → 去 userinfo →
// 去 www. 前缀 → 小写。非 http(s) / 解析不出 → ''（调用方按空值不渲染徽标，**禁**回退成
// 显示原始 URL——徽标位置显示长链接会把标题行挤爆；完整 URL 在条目第三行本来就有）
export function dsDomainOf(url: string): string {
  const trimmed: string = url.trim();
  const lower: string = trimmed.toLowerCase();
  let rest: string = '';
  if (lower.startsWith('https://')) {
    rest = trimmed.substring(8);
  } else if (lower.startsWith('http://')) {
    rest = trimmed.substring(7);
  } else {
    return '';
  }
  const slash: number = rest.indexOf('/');
  if (slash >= 0) {
    rest = rest.substring(0, slash);
  }
  const query: number = rest.indexOf('?');
  if (query >= 0) {
    rest = rest.substring(0, query);
  }
  const hash: number = rest.indexOf('#');
  if (hash >= 0) {
    rest = rest.substring(0, hash);
  }
  // userinfo 先剥（自检轮修：首版先剥端口——user:pass@host 被截成 "user"，IPv6 字面量被截成
  // "[2001"）；剥完再按形态取主机名
  const at: number = rest.lastIndexOf('@');
  if (at >= 0) {
    rest = rest.substring(at + 1);
  }
  if (rest.startsWith('[')) {
    const close: number = rest.indexOf(']');
    if (close < 0) {
      return ''; // 未闭合的 IPv6 字面量 = 无法解析，整块不渲染
    }
    rest = rest.substring(0, close + 1);
  } else {
    const colon: number = rest.indexOf(':');
    if (colon > 0) {
      rest = rest.substring(0, colon);
    }
  }
  if (rest.toLowerCase().startsWith('www.')) {
    rest = rest.substring(4);
  }
  return rest.toLowerCase();
}

export function dsSourceEntriesOf(serverToolsJson: string): DsSourceEntry[] {
  const normalized: string = dsNormalizeServerTools(serverToolsJson);
  if (normalized === '') {
    return [];
  }
  const out: DsSourceEntry[] = [];
  const seen: Set<string> = new Set<string>();
  const push = (url: string, title: string, snippet: string): void => {
    const trimmed: string = url.trim();
    if (trimmed === '' || seen.has(trimmed)) {
      return;
    }
    seen.add(trimmed);
    out.push({ number: out.length + 1, url: trimmed, title: title, snippet: snippet });
  };
  const pages: DsPageRef[] = [];
  for (const callJson of dsServerCallJsonsOf(normalized)) {
    try {
      const call: Record<string, Object> = JSON.parse(callJson) as Record<string, Object>;
      const sources: Object | undefined = call['sources'];
      if (Array.isArray(sources)) {
        for (const s of sources as object[]) {
          const rec: Record<string, Object> = s as Record<string, Object>;
          push(typeof rec['url'] === 'string' ? rec['url'] as string : '',
            typeof rec['title'] === 'string' ? rec['title'] as string : '',
            typeof rec['snippet'] === 'string' ? rec['snippet'] as string : '');
        }
      }
      // read_link 的 page（读了未引用的页面也进卡——先收集后统一编号，保 sources 段序号）
      const page: Object | undefined = call['page'];
      if (typeof page === 'object' && page !== null && !Array.isArray(page)) {
        const pageRec: Record<string, Object> = page as Record<string, Object>;
        pages.push({
          url: typeof pageRec['url'] === 'string' ? pageRec['url'] as string : '',
          title: typeof pageRec['title'] === 'string' ? pageRec['title'] as string : ''
        });
      }
    } catch (e) {
      continue; // call 坏串跳过（容错不炸）
    }
  }
  for (const page of pages) {
    push(page.url, page.title, '');
  }
  try {
    const parsed: Record<string, Object> = JSON.parse(normalized) as Record<string, Object>;
    const annos: Object | undefined = parsed['annotations'];
    if (Array.isArray(annos)) {
      for (const a of annos as object[]) {
        // 官方嵌套形态单源解析（扁平形态不存在于真实响应——见 dsAnnotationViewOf 注释）
        const view: DsAnnotationView | null = dsAnnotationViewOf(a);
        if (view !== null) {
          push(view.url, view.title, '');
        }
      }
    }
  } catch (e) {
    // 外层坏串但 sources 已尽力收集——按已收集面返回
  }
  return out;
}

// 来源卡行点击锚点 id（M2 角标点击滚动目标——宿主既有 scrollToMarkdownAnchor 按组件
// id 几何滚动，本 id 挂 M1 来源卡行）
export const DS_SOURCE_ENTRY_ANCHOR_PREFIX: string = 'dssrc-';

export function dsSourceEntryAnchorId(msgId: string, entryNumber: number): string {
  return DS_SOURCE_ENTRY_ANCHOR_PREFIX + msgId + '-' + entryNumber.toString();
}

// ── M2 正文角标 ──官方口径 annotations 区间 = Unicode 码点；ArkTS string 切片与本仓
// markdown 节点 range 均为 UTF-16 码元（substring 口径）——换算单源在本函数（非 BMP 字符
// 每码点占 2 码元，逐点扫描换算）
export interface DsCitationSpan {
  start: number; // UTF-16 码元（正文全文坐标）
  end: number;
  entry: number; // 来源卡序号（1 起；未收录 URL 不产角标）
}

export function dsCodePointIndexToUtf16(text: string, codePointIndex: number): number {
  if (codePointIndex <= 0) {
    return 0;
  }
  let u16: number = 0;
  let cp: number = 0;
  while (u16 < text.length && cp < codePointIndex) {
    const code: number = text.charCodeAt(u16);
    if (code >= 0xD800 && code <= 0xDBFF && u16 + 1 < text.length) {
      const next: number = text.charCodeAt(u16 + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        u16 += 2;
        cp++;
        continue;
      }
    }
    u16++;
    cp++;
  }
  return u16;
}

// serverToolsJson + 正文全文 → 角标区间表（UTF-16 码元；按 start 升序）。URL 未进来源卡
// / 区间非法 / 越界全文的注跳过——角标只在「有点可去」时渲染
export function dsCitationSpansOf(serverToolsJson: string, bodyText: string): DsCitationSpan[] {
  const entries: DsSourceEntry[] = dsSourceEntriesOf(serverToolsJson);
  if (entries.length === 0 || bodyText === '') {
    return [];
  }
  try {
    const parsed: Record<string, Object> =
      JSON.parse(dsNormalizeServerTools(serverToolsJson)) as Record<string, Object>;
    const annos: Object | undefined = parsed['annotations'];
    if (!Array.isArray(annos)) {
      return [];
    }
    const spans: DsCitationSpan[] = [];
    for (const a of annos as object[]) {
      // 官方嵌套形态单源解析（与来源卡同一函数——扁平形态不存在于真实响应）
      const view: DsAnnotationView | null = dsAnnotationViewOf(a);
      if (view === null) {
        continue;
      }
      const url: string = view.url;
      const startCp: number = view.startCp;
      const endCp: number = view.endCp;
      if (url === '' || startCp < 0 || endCp <= startCp) {
        continue;
      }
      let entryNumber: number = 0;
      for (const entry of entries) {
        if (entry.url === url.trim()) {
          entryNumber = entry.number;
          break;
        }
      }
      if (entryNumber === 0) {
        continue;
      }
      const start: number = dsCodePointIndexToUtf16(bodyText, startCp);
      const end: number = dsCodePointIndexToUtf16(bodyText, endCp);
      if (start >= bodyText.length || end <= start) {
        continue;
      }
      spans.push({ start: start, end: Math.min(end, bodyText.length), entry: entryNumber });
    }
    spans.sort((a: DsCitationSpan, b: DsCitationSpan): number => a.start - b.start);
    return spans;
  } catch (e) {
    return [];
  }
}
