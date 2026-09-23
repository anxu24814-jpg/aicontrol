// 聊天消息视图模型（2026-08-29 任务书 M1 自 dshinhm 同名文件随迁改造）：
// · ChatMessage = 渲染层唯一消费的消息模型（ChatMessageItem/ChatPage 引用）；
// · 剥离 KimiToolTypes 依赖（agentRefsSummary 随之删除）与未随迁消费方的死代码
//   （userDisplayText=附件后缀提示 / toolPayloadText=kap 工具卡载荷——本项目附件后置
//   M4、无 kap 工具卡数据源，删除；tool 分支渲染字段保留备 M4 工具调用展示）；
// ★ ChatMessage = **@Observed 类**（dshinhm 二三四改拍板语义保留）：键恢复稳定
// （keyGenerator 恒 = msg.id），增量帧原地改字段，视图刷新由 @Observed→@ObjectLink
// 对象级观察保证，列表项不每帧销毁重建（stable key + 内容字段精准更新 = 业界流式
// 渲染共识）。
// 约束：@Observed 类必须经 new 构造（对象字面量无效）——统一走 newChatMessage 工厂。
// attachBriefs 类型自 common/AttachmentUtil 引（简报类型单源；common → components 单向）

import { AttachmentBrief } from '../../common/AttachmentUtil';

// 消息类别：user 用户气泡 / assistant 助手气泡 / thinking 思考灰字 / tool 工具行 / notice 提示条
@Observed
export class ChatMessage {
  id: string = '';
  kind: string = '';
  text: string = '';
  toolName: string = ''; // kind=tool：工具名（函数名原串——展示名经 ToolTypes.toolTitle 转换）
  toolState: string = ''; // kind=tool：running / done / error
  level: string = ''; // kind=notice：info / warning / error
  // ── 工具卡字段（kind=tool 专用；2026-09-02 工具调用底层起 tool 分支为活跃渲染路径）──
  toolCallId?: string; // 模型侧调用 id（ask_user 答案上行回传键——ToolRuntime.resolveAsk）
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
  // toolConfirmResult：'approved' | 'rejected' | 'session'（★ 2026-09-20 笔 C 增第三值），
  // 写点 = 用户在确认卡作答那一刻（等待态转回执/拒）。判据 = 回执行分支渲染（见
  // ChatToolCard.confirmDone）；「已允许」在既有字段上无痕（批准戳内存态用完即销），故此
  // 回执必须由本字段承载——只在当场可见，重进会话退回普通工具卡（信息零丢失，申报口径见
  // 任务书 §5.4）
  toolConfirmResult?: string;
  // toolConfirmSessionAllow：用户在确认卡上按的是「本会话内允许」——卡在作答那一刻写 true
  //（只有 true 会写；消费点 = ChatToolRoundCtrl.awaitBrowseConfirm：映射 result = 'session'
  // 并授予会话级免询问）。与上两枚同族：不入库、不参与回放构造
  toolConfirmSessionAllow?: boolean;
  // 思考块关联的正文消息 id（2026-09-01「回传历史思考」：kind='thinking' 专用——思考块
  // 与它上方的 assistant 正文消息的关联键；发送组装历史时经此把思考内容并回 assistant
  // 消息的 reasoning（仅 OpenAI 系回传，见 ChatSendCtrl）。回放 = 'think'-+行 id（行 id
  // 即正文行 id）；流式 = liveAssistantId（懒创建时绑定）。普通消息不设（undefined）
  linkId?: string;
  // ── 同泡化标记（2026-09-16 思考块收入气泡；kind='assistant' 专用，见 ChatMessageItem
  // 思考分支注释）──
  // true = 本条正文泡上方紧贴一行思考半泡（linkId 指本条的那个 thinking 行），气泡上缘
  // 圆角随之切直角、与思考半泡下缘直角无缝拼成一体。**写点 = 思考行三条创建链**（回放
  // rebuildFromHistory / 翻页 prepend / 流式懒创建 onStreamDelta）——建思考行处同时置位；
  // 数据源整体重建即随新对象归零（本仓无删除单条消息路径，故无复位写点）
  thinkAbove?: boolean;
  // ── 用量 meta（2026-09-06 token 用量统计；仅末轮 assistant 行携带——失败/停止/存量/
  // 工具轮中间行天然 undefined 不渲染）。任务书两字段外增 usageCompletionTokens 一项：
  // 口径③ tok/s = completion ÷ duration，仅 total+duration 推不出分子（偏差登记变更记录）
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
  // 常开测量，与「用时」同族；重进会话/切版由账本与变体快照回挂（ChatPageLoad / ChatRetryCtrl）
  usageFirstTokenMs?: number;
  // ── 运行时字段（2026-09-14 消息气泡底栏；不入库、不参与回放构造——rebuildFromHistory
  // 重建的对象两字段 undefined = 底栏按「已结束」显示、重试键按回放尾行判定）──
  // 本条正在流式输出——**两 kind 共用**：①kind='assistant'（2026-09-14 底栏）——占位气泡
  // 创建处置 true，finishStream 收口与工具轮中间行收尾 settleRoundAssistant 置 false
  // （done/error 两路都经收口，失败与手动停止轮自动获得底栏）；②kind='thinking'
  // （2026-09-16 三态收口）——思考行懒创建处置 true（生成中：折叠态显尾部三行预览），
  // finishStream 与 settleRoundAssistant 两处收口置 false（已结束：折叠态内容区收拢为 0、
  // 只留标题行——见 ChatMessageItem.ChatThinkingBlock 头注释）。回放/翻页重建的行两 kind
  // 该字段皆 undefined ⇒ 判「已结束」
  streaming?: boolean;
  // 本条是否为「其后无任何消息」的末条助手消息（重试键显隐判据）。维护 = ChatDataSource
  // push（任何新消息入列即清旧 tail，assistant 行自置）+ rebuildFromHistory（末条
  // assistant 行置 true）+ finishStream 收口置回（failRound 的 notice 先 push 清过 tail）
  tail?: boolean;
  // ── 多版本（DB v36，2026-09-20 消息重新生成；kind='assistant' 专用）──
  // variantCount = 版本总数（含当前选中版；>1 才渲染底栏切换键 ‹ i/N ›）、variantActive =
  // 选中下标。真源 = messages.variants 列（DB），本对字段是渲染投影。写点三链：回放装配
  //（rebuildFromHistory / prepend，从行 variants 解析）/ 重试收尾（finishStream，原地改
  // ——切换键随新答案出现）/ 切换（★ 2026-09-20 注释核正：真写点 = ChatRetryCtrl.switchVariant，
  // 旧注把归属记成 ChatPage 侧的同名方法——ChatPage 全仓无此定义，只有 onVariantSwitch 上行；
  // 链路 = ChatPage.onVariantSwitch → ChatSendCtrl.switchMessageVariant → ChatRetryCtrl。
  // 本写点只换 variantActive，content 投影随 active 同条 UPDATE 换）。undefined / 1 =
  // 单版消息无切换键。与 usage 四字段联动：切换时用量快照随版本换
  variantCount?: number;
  variantActive?: number;
  // ── 正文渲染纪元（2026-09-20 重试真机修复笔；kind='assistant' 专用）──
  // 非前缀替换（重试清空重答 / 切换版本换整段内容）时由写点自增。正文渲染器以
  // 「id#纪元」作 ForEach 键——键变 = 整组件重建 = 渲染器全量重解析（真机实测：两个
  // 渲染器（CJMarkdown 增量解析 / @lidary）对「内容被整体替换」不重解析，重试与切换后
  // 正文停在上一次已解析内容，退出消息页重进才正确；重建与「退出重进」同效）。
  // 流式追加（前缀单调）不动本键——打字机增量路径与 K1 零闪屏口径零影响。
  // 与 streaming/tail 同族「运行时字段」：不入库、不参与回放构造（undefined 即 0）
  renderEpoch?: number;
  // ── 附件简报（2026-09-15 预览第三轮；kind='user' 专用——带附件的消息装配）──
  // 与 streaming/tail 同族「运行时字段」，但口径差异：**回放由装配链写入**（不是「不参与
  // 回放构造」——ChatPageLoad 加载后按 id 归并赋值，翻页前插同链）；不入库、不参与
  // insertMessage（元数据真源 = message_attachments 表）。发送链写点 =
  // ChatSendCtrl.dispatchSend（briefsFromPending，隐私会话同样装配——内存态齐备是隐私
  // 预览成立的前提）；装配后经 @Observed/@ObjectLink 对象级观察驱动气泡渲染
  attachBriefs?: AttachmentBrief[];
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
  // coversToSeq = 摘要行的覆盖边界（仅 kind='summary' 行挂值——本条摘要覆盖到的最大 seq
  // 含）；真源 = messages.coversToSeq 列（DB v42），写入唯一点 CompressDb。
  // 这两个字段**不入库**（rowSeq/coversToSeq 的持久真源就是库列本身，回放时从投影回填）
  coversToSeq?: number;
  // ── 自动重试状态行（2026-09-22 聊天自动重试笔；kind='assistant' 专用）──
  // 非空 = 该助手气泡内正在显示这一行小字（「网络异常，正在重试 1/3」，数字随次数原地更新）。
  // 与 toolConfirmText 同款「运行时字段」口径：**不入库、不参与回放构造**——undefined 即
  // 「无重试」，重进会话回放出来的历史消息天然为 undefined（状态行不跨会话存活）。
  // 写点唯一 = ChatSendCtrl.setRetryHint（自动重试域经 ChatAutoRetryHost 调用：接管时写、
  // 有内容上屏首帧与轮次收尾两处清），只改 Message 对象的本字段一个值、不新增消息行、不动
  // 库行与 variants；刷新靠 @Observed 对象级观察（原地改即重渲），**不走 renderEpoch**
  //（纪元只服务「内容整体替换」的渲染器重建，状态行不换正文）
  retryHint?: string;
  // ── 截断尾注（2026-09-23 输出上限与超时治理笔 2；kind='assistant' 专用）──
  // true = 本条回答被输出上限截断（思考 token 与正文共享同一预算打满即真，四协议标记见
  // SseParser.SseDelta.truncated），气泡正文下方出一行提示。与 retryHint 同款「运行时字段」
  // 口径：**不入库、不参与回放构造**——**推论：重进会话后该提示不再出现**（回放不恢复）。
  // 这是有意选择：加 DB 列要新迁移而收益仅是历史可查，超出本笔范围，故不做。
  // 写点唯一 = ChatSendCtrl.finishStream（挂轮级累积快照的 truncated，与 streaming/tail 同段；
  // 隐私会话同样挂——判据差异见彼处注释）；刷新靠 @Observed 对象级观察（原地改即重渲），
  // **不走 renderEpoch**（纪元只服务「内容整体替换」的渲染器重建，尾注只追加一行不动正文）
  truncated?: boolean;
}

// 消息构造工厂（@Observed 类禁止对象字面量构造——统一入口保证 new 语义；
// 六必填字段外的可选字段由调用方在返回实例上按需赋值）
export function newChatMessage(id: string, kind: string, text: string, toolName: string = '',
  toolState: string = '', level: string = ''): ChatMessage {
  const msg: ChatMessage = new ChatMessage();
  msg.id = id;
  msg.kind = kind;
  msg.text = text;
  msg.toolName = toolName;
  msg.toolState = toolState;
  msg.level = level;
  return msg;
}
