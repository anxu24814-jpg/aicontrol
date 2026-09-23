// 记忆提取服务（2026-09-08 记忆域，任务书-记忆域-20260908 §2.3——照 TitleGen 形制）：
// 进程级独立域：顶层函数模块，不持页面/组件引用、不触 UI，全吞错误 hilog 留痕，广播刷新
// （MEMORY_LIST_TICK_KEY）；本域自身零 toast——手动链把结果对象（MemorySinkResult）回传给
// 记忆页，由页面出提示（2026-09-11 决明「整理出没整理出都没有提示」：原手动链返回 void，
// 「一条没整理出」与「请求失败」在界面上无从区分，用户点完只见到「正在整理」一闪）。
// · 触发两链：自动 = ChatPage.aboutToDisappear 退出会话 fire-and-forget 一行
//   sinkMemoryForConversation（隐私会话由调用侧过滤，与标题生成同口径；返回值丢弃 =
//   后台整理不打扰）；手动 = 记忆页「立即整理」选会话后 sinkMemoryNow（用户显式动作，
//   守卫放宽——不查自动整理开关与助手沉淀开关，总开关关仍不可用；返回整理结果六态，
//   页面据此 toast 新增条数 / 未整理出 / 库满 / 模型失效 / 整理失败）。
// · 守卫序（任一不满足即返回，本域不 toast——手动链的结果对象回传页面出提示，见下）：dbReady → 总开关 →（自动链）自动整理
//   开关 → 会话 locked（加密会话不沉淀——内容蒸馏成记忆会在普通会话被注入 = 越权泄漏，
//   任务书 §2.6）→（自动链）归属助手 memorySink → 提取模型（★ 2026-09-08：记忆两键
//   MEMORY_PROVIDER_KEY/MEMORY_MODEL_KEY 未配置 = 功能未启用，debug 留痕返回——同日决明
//   指令**取消回退标题模型**，与标题生成同口径；手动链由记忆页「立即整理」前置 toast 引导）
//   → 消息不足 2 条 → in-flight 集（防同会话并发重复请求）。
// · 输入：queryRecentMessages 过滤 user/assistant 且内容非空，每条截 500 加 …，总字符
//   上限 6000 超出头尾都保（头 2000 + 省略标记 + 尾补足——头部常含长期声明，尾部信息
//   密度高），tool 行剔除（buildMemoryContent 在 MemoryText 纯函数域）。
// · 请求带去重清单（P1-1）：库内现有记忆 ≤120 条 / 6000 字附在渲染产物之后，让模型跳过
//   语义等价条目（敏感命中条目不外发——composeMemoryList 内过滤；2026-09-11 记忆优化笔
//   自 50/3000 扩面，见 MEMORY_DEDUP_MAX_COUNT 处注）。
// · 输出上限不设（MEMORY_MAX_OUTPUT = 0 = 不发 max_tokens 字段）：2026-09-08 决明拍板
//   「不设思考预算上限，让模型先多思考，正文靠提示词约束」——记忆提示词要求「最多 5 条 ×
//   60 字」≈300+ 字，固定 100 本就不够；正文长度由提示词 + parseMemoryLines 截断兜底，
//   不靠 max_tokens 卡。★ 同日一百六十三节实锤：两链曾全灭的真实根因是非流式请求残留
//   stream_options 被服务端 400 拒（TitleApi.toNonStream 已修），非本预算；「思考与正文
//   共享 max_tokens」只对把思考计入上限的服务商成立，属残留观察项（标题链 100 未动，
//   当前服务商实测无碍——设备库 21 条 titleSource='ai'，2026-09-08 自检轮取证）。
// · 请求：复用 TitleApi.requestTitleText（非流式小任务请求通道，入参 = 任意 prompt——
//   函数名含 Title 但语义通用，不改名：改名牵动 TitleGen 与断言收益为零）；端点验证复用
//   TitleGen.resolveTitleEndpoint 导出（同一模型键同一标准单一来源）。
// · 失败分类照 TitleGen：网络/5xx/429 退避 2/4/8 秒最多 3 次；401/403/配置类不重试。
// · 写库：parseMemoryLines（编号剥离/敏感过滤/去重/截断，MemoryText 纯函数域）→
//   insertMemory(source='auto')；库内达 MEMORY_MAX_TOTAL 跳过新增 + hilog（不打扰）。
// ★ 2026-09-13 记忆按需读取笔（方案-记忆按需读取-20260913）：本域新增「读取方式」键族
//   （MEMORY_READ_MODE_*——'inject' 自动注入默认 / 'tool' 按需读取；MemoryPage 分段卡写、
//   ChatSendCtrl 注入判定与工具声明消费）与 search_memory 工具执行器（SearchMemoryExecutor
//   ——读全库 → MemoryText 检索纯函数 → 结果文本，注册归口 ToolTypes）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isReady, queryConversationLocked,
  queryRecentMessages } from './store/ChatDb';
import { ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  queryConversationAssistantId } from './store/AssistantDb';
import { queryEnabledKeyIds } from './store/ProviderKeyDb';
import { loadPoolKey } from './store/KeyStore';
import { requestTitleText, TitleRequestResult } from './providers/TitleApi';
import { TitleEndpoint, resolveTitleEndpoint, isRetryable } from './TitleGen';
import { logTaskUsage } from './store/UsageStatsDb';
import { broadcastMemoryList, broadcastAssistantMemoryList, insertAssistantMemory,
  insertMemory, MEMORY_MAX_TOTAL, MEMORY_SCOPE_ASSISTANT, MEMORY_SCOPE_GLOBAL, MemoryRow,
  queryAssistantMemories, queryMemories } from './store/MemoryDb';
import { buildMemoryContent, composeMemoryList, MemoryEntryItem, parseMemoryLines,
  normalizeMemoryKey, composeMemorySearchResult, MemorySearchItem } from './MemoryText';
import { ToolExecutor } from './providers/ToolContracts';

const DOMAIN: number = 0x71C2;
const TAG: string = 'MemoryGen';

// 提取提示词（内置常量 = 默认值 + 恢复默认目标，唯一真源；★ 2026-09-08 先行笔开放编辑：
// MEMORY_PROMPT_KEY 定制非空覆盖，'' = 生效内置；两占位符——{content} 渲染为对话内容
// 拼接串，{maxItems} 由 MEMORY_EXTRACT_MAX_COUNT 注入〔条数解耦，治提示词与解析侧双源〕；
// 保存校验只强制 {content}，缺 {maxItems} = 用户显式去掉条数约束，解析侧上限仍兜底）
// ★ 2026-09-11 决明「对记忆整理模型的提示词做适当优化」：八条规则中两条被改写、一条新增
//（改动全部对着下游解析与消费链的真实缺口，不是文风调整）——
// · 新第 8 条（重要性降序）：解析侧 parseMemoryLines 满 maxCount 即 break（㉛ 组「上限保前 5」
//   钉），故模型输出的顺序就是淘汰顺序——原模板没有排序纪律，模型若给出 8 条候选，被丢掉的
//   是随机尾部而非低价值项。要求降序后，「丢尾」= 丢最不重要，与解析侧行为配成一对。
//   附带收益：入库时间戳近同时，注入块按 createdAt 升序渲染 → 最重要的天然落在块首。
// · 新第 6 条（一件事只写一条）：客户端跨条目去重只有 normalizeMemoryKey（压空白 + trim，
//   字面量相等才算重，见 MemoryText 头注），近义重复条会真的落库并各占一条注入名额；模板
//   此前只管「与库内已有记忆不重复」（去重清单段），不管批内自重复。两条互补不重复。
// · 第 3 条补「不要写推测或补充」：原条只排除助手的话，没排除模型对用户的推断（由上下文
//   猜出「用户可能是程序员」这类无依据结论），推断落库后会被当作用户自述长期注入。
// · 「缺漏」不在此治：提取模型漏掉的内容只能靠再读一遍对话补（优化 pass 手里没有对话，
//   见 docs/方案-记忆整理优化-20260911.md §2）。
export const MEMORY_PROMPT_TEMPLATE: string =
  '我将给你一段对话内容，放在 <content> 标签块中。\n' +
  '请从中提取值得跨会话长期记住的用户稳定事实。\n' +
  '1. 值得提取的例如用户透露的身份信息、长期偏好、做事习惯、表达风格、长期目标，以及对助手明确提出的要求\n' +
  '2. 忽略纯技术问答、项目细节、一次性操作指令等临时信息\n' +
  '3. 只从用户说的话里提取，只写他明确表达过的信息，不要写推测或补充；助手的角色设定与助手的回复不算用户信息\n' +
  '4. 每条用完整的第三人称陈述句描述用户，不使用「这个」「刚才」等指回本次对话的词\n' +
  '5. 忽略口令、密钥、证件号、银行卡号、住址等敏感信息，不要输出\n' +
  '6. 一件事只写一条：同一事实的不同说法合并成一条，不同的长期事实分开写，不要把一句话拆成多条\n' +
  '7. 每行一条，每条不超过 60 字，最多 {maxItems} 条\n' +
  '8. 按重要性从高到低排列，最重要的放在最前面；条数超过上限时优先保留靠前的\n' +
  '9. 没有值得记住的内容时只回复「无」\n' +
  '10. 只输出条目本身，不要编号，不要解释，也不要输出你的分析或思考过程\n' +
  '\n' +
  '<content>\n' +
  '{content}\n' +
  '</content>';
export const MEMORY_PROMPT_CONTENT: string = '{content}';
// 条数占位符（§2.3 条数解耦：模板条数由 MEMORY_EXTRACT_MAX_COUNT 渲染注入，与解析侧
// maxCount 同源——用户改提示词不再产生双源谎言）
export const MEMORY_PROMPT_MAX_ITEMS: string = '{maxItems}';

// 记忆提取模型两键（★ 2026-09-08 先行笔 §2.1 + 同日决明指令取消回退：独立可配，两键齐 =
// 用记忆模型；未配置 = 功能未启用不整理——与标题生成同口径，不再回退标题模型）
export const MEMORY_PROVIDER_KEY: string = 'memoryProvider';
export const MEMORY_MODEL_KEY: string = 'memoryModel';
// 记忆提取提示词定制键（'' = 未定制 = 生效内置 MEMORY_PROMPT_TEMPLATE——清删式回退，
// 内置模板后续升级自动跟随）
export const MEMORY_PROMPT_KEY: string = 'memoryPrompt';

// 生效模型纯选择（两键齐 = 取记忆模型，否则 = 空串对 = 未启用——AppStorage 读取在
// resolveMemoryModel，本纯函数可节点直跑断言）
export interface MemoryModelPick {
  providerId: string;
  modelId: string;
}

export function pickMemoryModel(memProvider: string, memModel: string): MemoryModelPick {
  if (memProvider !== '' && memModel !== '') {
    return { providerId: memProvider, modelId: memModel };
  }
  return { providerId: '', modelId: '' };
}

// 生效模型单源（生成链 + 记忆页「立即整理」前置检查共用）
export function resolveMemoryModel(): MemoryModelPick {
  return pickMemoryModel(AppStorage.get<string>(MEMORY_PROVIDER_KEY) ?? '',
    AppStorage.get<string>(MEMORY_MODEL_KEY) ?? '');
}

// 生效提示词模板纯选择（定制非空取定制，空回内置——照 TitleGen.pickTitlePrompt 形制）
export function pickMemoryPrompt(custom: string): string {
  return custom !== '' ? custom : MEMORY_PROMPT_TEMPLATE;
}

// 生效提示词模板单源（生成链 + 功能模型页编辑面板共用——现读，用户改完下次整理即生效）
export function resolveMemoryPromptTemplate(): string {
  return pickMemoryPrompt(AppStorage.get<string>(MEMORY_PROMPT_KEY) ?? '');
}

// 模板渲染（单遍扫描替换 {maxItems} 与 {content}）：★ 禁两次 split/join 连续替换——先
// 替换的值若含后一占位符字面量会被二次替换，而对话内容来自用户输入不可信（可含
// 「{maxItems}」字面量）；单遍扫描对占位符顺序与内容字面量均安全。{maxItems} 缺失 = 用户
// 显式去掉条数约束，原样输出
export function renderMemoryPrompt(template: string, content: string,
  maxItems: number): string {
  const pieces: string[] = [];
  let rest: string = template;
  while (rest !== '') {
    const contentAt: number = rest.indexOf(MEMORY_PROMPT_CONTENT);
    const maxItemsAt: number = rest.indexOf(MEMORY_PROMPT_MAX_ITEMS);
    let at: number = -1;
    let isContent: boolean = false;
    if (contentAt >= 0 && (maxItemsAt < 0 || contentAt < maxItemsAt)) {
      at = contentAt;
      isContent = true;
    } else if (maxItemsAt >= 0) {
      at = maxItemsAt;
    }
    if (at < 0) {
      pieces.push(rest);
      break;
    }
    pieces.push(rest.substring(0, at));
    pieces.push(isContent ? content : maxItems.toString());
    rest = rest.substring(at + (isContent ? MEMORY_PROMPT_CONTENT.length :
      MEMORY_PROMPT_MAX_ITEMS.length));
  }
  return pieces.join('');
}

// 记忆总开关（AppStorage 持久键，EntryAbility persistProp 注册默认 true——照 PREF_BG_
// SESSION_ONLY_KEY 先例）：false = 不注入不沉淀，自动整理与手动整理均不可用（记忆页
// 显示停用说明行；列表仍可查看/编辑/删除——数据管理不依赖开关）。注入侧消费点 =
// ChatSendCtrl.buildMemoryBlock
export const MEMORY_ENABLED_KEY: string = 'memoryEnabled';
// 退出会话后自动整理开关（默认 false——用户显式开启才产生后台请求；开 = 退出会话自动
// 沉淀一次，每次一个模型请求）
export const MEMORY_AUTO_KEY: string = 'memoryAutoSink';
// 整理进行中计数（AppStorage 键，进程内态不持久化）：写点 = startSinking 起止成对
// （finally 兜底），读点 = MemoryPage @StorageProp——「正在整理」提示，结果未出期间可见
// （含自动链触发的后台整理）
export const MEMORY_SINKING_KEY: string = 'memorySinkingCount';

// ── 记忆读取方式（2026-09-13 记忆按需读取，方案-记忆按需读取-20260913 §2.2）──
// 全局偏好：'inject' = 自动注入（默认——发送链把记忆块拼进 system prompt 尾部，现状零回归）/
// 'tool' = 按需读取（聊天链不注入，改为声明 search_memory 工具由模型按需检索；主动消息链
// 维持注入不受本键影响——四百八十一节拍板「主动消息内容只靠记忆」）。参与闸仍四源相与：
// 本键只换「注入还是检索」的形态，不豁免总开关/助手「注入」开关/非私密三闸。
// 消费方 = MemoryPage 分段卡（@StorageLink）+ ChatSendCtrl（buildMemoryBlock 守卫与工具
// 声明追加）；persistProp 注册在 EntryAbility 记忆域键区
export const MEMORY_READ_MODE_KEY: string = 'memoryReadMode';
export const MEMORY_READ_MODE_INJECT: string = 'inject';
export const MEMORY_READ_MODE_TOOL: string = 'tool';
export const MEMORY_READ_MODE_DEFAULT: string = MEMORY_READ_MODE_INJECT;

// 生效读取方式纯选择（仅 'tool' 视为按需读取——脏值/空值一律回 inject，存量零漂移；
// 照 pickMemoryModel 形制，本纯函数可节点直跑断言）
export function pickMemoryReadMode(value: string): string {
  return value === MEMORY_READ_MODE_TOOL ? MEMORY_READ_MODE_TOOL : MEMORY_READ_MODE_INJECT;
}

// 生效读取方式单源（发送链注入判定与工具声明、记忆页分段卡共用）
export function resolveMemoryReadMode(): string {
  return pickMemoryReadMode(AppStorage.get<string>(MEMORY_READ_MODE_KEY) ?? '');
}

export function isMemoryToolReadMode(): boolean {
  return resolveMemoryReadMode() === MEMORY_READ_MODE_TOOL;
}

// ── 记忆工具作用域中转键（v35，2026-09-20 助手级记忆）──
// search_memory / manage_memory 执行器无上下文（读不到助手行/会话态），执行者的记忆作用域
// 经进程级键中转——值 = 目标助手 id（'assistant' 作用域时非空；'global' 时空串 = 全局库），
// 两执行器按「键非空 = 查该助手库 / 空 = 全局库」同一判据选库与定位，跨库操作天然隔离
//（定位集/查询集锁本库是唯一机制；两库行 id 前缀为连字符形态 'asmem-'/'mem-'，仅供人读，
// 全仓无按前缀判库的代码）。写点 = ChatSendCtrl.dispatchSend（发送时
// 现写，与 CHAT_SEARCH_COUNT_KEY / CHAT_ACTIVE_CONV_KEY 同位同理由）；读点 = SearchMemoryExecutor
// 与 ToolMemoryManage 执行时
export const MEMORY_EXEC_ASSISTANT_KEY: string = 'memoryExecAssistantId';

// ── 手动链整理结果（2026-09-11 决明「整理完要有提示」；同日追加「库满 / 模型与 Key 失效 /
// 重试耗尽也给出对应提示」）──
// 六态 = 记忆页出提示的唯一依据（文案映射单源 = memorySinkToastText；本域只报事实不出 UI）：
// · inserted——本次新增 N 条（count 有意义，页面报条数）
// · none——本次没整理出任何条目（模型按提示词答「无」/ 条目全被敏感过滤与去重丢掉 / 会话
//   不足 2 条无从提取），★ 三路同归此态：对用户而言都是「没有记忆产生」，页面提示同一句
// · limit——库内已达 MEMORY_MAX_TOTAL（有界红线，跳过新增；与「＋」新建键共用一句提示）
// · config——提取模型不可用（两键未配置 / 服务商停用 / 模型停用 / Key 池空 / Key 明文缺失）
// · failed——本次整理没能完成（请求重试耗尽、异常终止）
// · skipped——守卫未放行且用户无事可做（在途重复触发、库态未就绪、加密会话、自动链的助手
//   沉淀开关），页面保持沉默（弹了是噪音）
// ★ 六态全走返回值而不借 reject：调用方只需一次 then 拿结果，无需 catch 分支
export const MEMORY_SINK_STATUS_INSERTED: string = 'inserted';
export const MEMORY_SINK_STATUS_NONE: string = 'none';
export const MEMORY_SINK_STATUS_LIMIT: string = 'limit';
export const MEMORY_SINK_STATUS_CONFIG: string = 'config';
export const MEMORY_SINK_STATUS_FAILED: string = 'failed';
export const MEMORY_SINK_STATUS_SKIPPED: string = 'skipped';

export interface MemorySinkResult {
  status: string;
  count: number; // 仅 inserted 非零（其余恒 0）
}

// 结果构造（多处复用——字面量零散写易漏 count 字段）
function buildSinkResult(status: string, count: number): MemorySinkResult {
  return { status: status, count: count };
}

// 库满提示（单源：记忆页「＋」新建键上限拦截与「立即整理」两处消费同一句——同一状况同一说法）
export const MEMORY_FULL_TIP: string =
  '记忆已达上限 ' + MEMORY_MAX_TOTAL + ' 条，请先删除部分条目';

// 结果 → 用户提示文案（纯函数，单源；'' = 不出提示）。除 skipped 外每态都有回声：整理出东西
// 要报条数（列表已刷新，条数是最直接的证据）、没整理出也要说一声（原行为静默，用户以为功能
// 没反应）、库满与模型失效给可操作的下一步、整理失败如实报失败。skipped 沉默 = 那几种情况下
// 用户无事可做，弹了反而是噪音
// ★ failed 文案不写「请求失败」：该态同时承载请求重试耗尽与异常终止（含逐条写库中途抛错——
//   前几条已落库），说「请求失败」在写库异常场景是假话（2026-09-11 自检轮 P2-A 修正）
export function memorySinkToastText(result: MemorySinkResult): string {
  if (result.status === MEMORY_SINK_STATUS_INSERTED) {
    return '已新增 ' + result.count + ' 条记忆';
  }
  if (result.status === MEMORY_SINK_STATUS_NONE) {
    return '未整理出值得记忆的信息';
  }
  if (result.status === MEMORY_SINK_STATUS_LIMIT) {
    return MEMORY_FULL_TIP;
  }
  if (result.status === MEMORY_SINK_STATUS_CONFIG) {
    return '记忆提取模型当前不可用，请检查模型与密钥设置';
  }
  if (result.status === MEMORY_SINK_STATUS_FAILED) {
    return '整理失败，请稍后重试';
  }
  return '';
}

// 去重清单（P1-1）：库内现有记忆随提取请求带给模型，让其跳过语义等价条目；条数/字符
// 双封顶（库上限 200 条全量太重；queryMemories 已按卡片序 = 用户排定优先级的最可能
// 重复集，可按需调）
// ★ 2026-09-11 扩面（方案-记忆整理优化-20260911 §六 Q2）：50/3000 → 120/6000——零新请求
// 就能治「新增侧跨次近义重复」的一次参数改动（清单原只带最近 50 条，更早的重复条目模型
// 看不见，于是照提照落库；存量重复由「记忆优化模型」pass 收拾）。代价 = 每次整理提示词的
// token 上升（清单从属于提取请求，不额外发请求）
// ★ 2026-09-22 记忆导入笔：三常量 export（原模块私有）供 MemoryImport 域复用——导入整理与
// 自动整理面对的是同一件事（让模型跳过库内已有条目），两处各写一份清单口径必然漂移；本域
// 只外借常量，**导入链不并入本域**（独立功能域，见 MemoryImport 头注释）
export const MEMORY_DEDUP_MAX_COUNT: number = 120;
export const MEMORY_DEDUP_MAX_CHARS: number = 6000;
// 清单段内标记（★ 只在段常量内使用，不进用户模板——MEMORY_PROMPT_* 前缀属模板占位符家族）
// ★ 2026-09-22 记忆导入笔：同 export——导入链也要把清单插进本段，标记不外借就得在导入域
// 复写 '{memories}' 字面量（第二份来源，改标记时静默漂移）；本域非模板面，外借代价为零
export const MEMORY_DEDUP_LIST_MARK: string = '{memories}';
// 清单段（★ 追加在 renderMemoryPrompt 产物之后——不得塞回模板再渲染，模板来自用户输入）
export const MEMORY_DEDUP_SECTION: string =
  '\n\n已有记忆（下列内容已经记住，语义等价的信息不要重复提取；无则忽略本节）：\n' +
  '<memories>\n' + MEMORY_DEDUP_LIST_MARK + '\n</memories>';
// 提取条数上限（模板 {maxItems} 渲染注入 + 解析侧 maxCount 同源——条数解耦后唯一来源）
const MEMORY_EXTRACT_MAX_COUNT: number = 5;
// 输出上限（0 = 不发 max_tokens 字段 = 模型按自身上限输出——见文件头「输出上限不设」注）
const MEMORY_MAX_OUTPUT: number = 0;
// 退避重试（TitleGen 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次
const MAX_MEMORY_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;

// in-flight 会话 id 集（退避窗口内防同会话并发重复请求——自动链退出触发与手动链同时
// 到达时去重；跨会话并行无害）
const inflightIds: Set<string> = new Set();

// 自动链入口（ChatPage.aboutToDisappear 一行 fire-and-forget；内部全吞错误不 reject）
// ★ 返回值有意丢弃：后台整理不打扰用户，结果提示只服务手动链
export function sinkMemoryForConversation(conversationId: string): void {
  if (conversationId === '') {
    return;
  }
  // 总开关 + 自动整理开关（AppStorage 持久键现读——开关关闭 = 零请求零写库）
  if (!isMemoryEnabled() || !isAutoSinkEnabled()) {
    return;
  }
  // 自动链目标库 = ''（由 runMemorySinking 按会话归属 scope 分派；手动链才传入口库）
  startSinking(conversationId, false, '');
}

// 手动链入口（库管理页「立即整理」选会话后）：不查自动整理开关与助手沉淀开关（用户显式
// 动作终胜），总开关关仍不可用（任务书 §2.2 表格语义）。返回 Promise = 全链结束后的结果
// 对象（含退避重试；失败不 reject，落在 failed 态）——调用页据此重拉列表 + 出提示
// （2026-09-08 自检轮：原 fire-and-forget 只能等广播，栈下层收不到时列表不刷新）。
// ★ v35 第二参 targetLibraryId（2026-09-20 助手级记忆）：手动整理的落库目标 = 入口库——
// 传 MEMORY_SCOPE_GLOBAL（全局库页）或助手 id（助手库页）；产物库恒等于入口库（用户显式
// 动作指定目标，不走自动链的会话归属 scope 分派——入口在哪个库整理就进哪个库，语义无歧义）
export function sinkMemoryNow(conversationId: string,
  targetLibraryId: string): Promise<MemorySinkResult> {
  if (conversationId === '') {
    return Promise.resolve(buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0));
  }
  if (!isMemoryEnabled()) {
    hilog.info(DOMAIN, TAG, '记忆功能已停用，手动整理跳过');
    return Promise.resolve(buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0));
  }
  return startSinking(conversationId, true, targetLibraryId);
}

export function isMemoryEnabled(): boolean {
  return AppStorage.get<boolean>(MEMORY_ENABLED_KEY) ?? true;
}

export function isAutoSinkEnabled(): boolean {
  return AppStorage.get<boolean>(MEMORY_AUTO_KEY) ?? false;
}

// 统一起跑（in-flight 闸 + 全吞错误包装；返回全链结果——手动链调用方据此重拉列表 + 出
// 提示，自动链忽略返回值）；manualTarget 仅手动链消费（sinkMemoryNow 传入的目标库，
// 自动链恒 ''——目标库由会话归属 scope 分派）
function startSinking(conversationId: string, manual: boolean,
  manualTarget: string): Promise<MemorySinkResult> {
  if (inflightIds.has(conversationId)) {
    hilog.info(DOMAIN, TAG, '整理在途跳过本次触发 conv=%{public}s', conversationId);
    return Promise.resolve(buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0));
  }
  inflightIds.add(conversationId);
  bumpSinking(1);
  return runMemorySinking(conversationId, 0, manual, manualTarget)
    .catch((e: Object): MemorySinkResult => {
      hilog.error(DOMAIN, TAG, '记忆整理异常终止 conv=%{public}s：%{public}s',
        conversationId, (e as Error).message);
      return buildSinkResult(MEMORY_SINK_STATUS_FAILED, 0);
    })
    .finally((): void => {
      inflightIds.delete(conversationId);
      bumpSinking(-1);
    });
}

// 整理中计数增减（AppStorage 广播；Math.max 防负——起止成对，异常路径 finally 兜底）
function bumpSinking(delta: number): void {
  const current: number = AppStorage.get<number>(MEMORY_SINKING_KEY) ?? 0;
  AppStorage.setOrCreate<number>(MEMORY_SINKING_KEY, Math.max(0, current + delta));
}

// 主流程（attempt 从 0 起；retryable 失败经 setTimeout 退避后递归重入——守卫全重查）
// 返回 = 本次整理结果（每个返回点都显式给态：ArkTS 类型已禁裸 return，此处再把「哪种态」
// 写清——inserted/none/limit/config/failed 五态是页面出提示的依据〔skipped 不出提示〕，
// 见 memorySinkToastText）。manualTarget = 手动链目标库（sinkMemoryNow 传入；自动链恒 ''）
async function runMemorySinking(conversationId: string, attempt: number,
  manual: boolean, manualTarget: string): Promise<MemorySinkResult> {
  if (!isReady()) {
    return buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0); // dbReady 守卫（调用侧已判——竞态窗口内库态不假定）
  }
  // 加密会话不沉淀（§2.6：蒸馏越权泄漏防线；手动链同拦——选会话面板已排除加密会话，
  // 此处兜底）
  if (await queryConversationLocked(conversationId)) {
    hilog.info(DOMAIN, TAG, '加密会话不沉淀 conv=%{public}s', conversationId);
    return buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0);
  }
  // 归属助手解析（自动链守卫 + v35 目标库分派两用——提升到函数级统一查一次；manual 链
  // 原不查归属，现多一次读但不拦判，行为等价）：行 ''（存量未绑定）= 默认助手，与守卫
  // 原口径一致
  const ownerId: string | null = await queryConversationAssistantId(conversationId);
  let owner: AssistantRow | null = null;
  if (ownerId !== null && ownerId !== '') {
    owner = await queryAssistant(ownerId);
  } else if (ownerId === '') {
    owner = await queryAssistant(ASSISTANT_DEFAULT_ID);
  }
  // 归属助手沉淀开关（自动链守卫；手动链用户显式动作放行）
  if (!manual) {
    if (ownerId === null) {
      return buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0); // 无行会话（空会话退出）——无沉淀面
    }
    if (owner === null || !owner.memorySink) {
      // 助手已删（弱链回退——无归属不拦沉淀？归属恒有默认兜底，null = 查询异常放弃）或显式关沉淀
      return buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0);
    }
  }
  // 目标库分派（v35，2026-09-20 助手级记忆）：手动链 = 入口库（manualTarget——'global' =
  // 全局库、助手 id = 该助手库，产物库恒等于入口库）；自动链 = 会话归属助手作用域分派
  //（'assistant' = 该助手自己的库；'global' 或助手行不在 = 全局库，存量路径逐字节不变）
  const targetAssistantId: string = manual ?
    (manualTarget === MEMORY_SCOPE_GLOBAL ? '' : manualTarget) :
    (owner !== null && owner.memoryScope === MEMORY_SCOPE_ASSISTANT ? owner.id : '');
  // 提取模型（★ 决明指令取消回退：记忆两键未配置 = 功能未启用，debug 留痕返回——自动链
  // 静默跳过，手动链由记忆页「立即整理」前置 toast 引导；此处 config 态兜「面板打开后模型
  // 被清空」的竞态，页面同一句提示）
  const picked: MemoryModelPick = resolveMemoryModel();
  if (picked.providerId === '' || picked.modelId === '') {
    hilog.debug(DOMAIN, TAG, '记忆提取模型未配置，功能未启用');
    return buildSinkResult(MEMORY_SINK_STATUS_CONFIG, 0);
  }
  const resolved: TitleEndpoint | null =
    await resolveTitleEndpoint(picked.providerId, picked.modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '记忆整理模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return buildSinkResult(MEMORY_SINK_STATUS_CONFIG, 0);
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——TitleGen 同口径）
  const apiKey: string = await loadPoolKey(picked.providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '记忆整理 Key 明文缺失，放弃');
    return buildSinkResult(MEMORY_SINK_STATUS_CONFIG, 0);
  }
  const content: string = buildMemoryContent(await queryRecentMessages(conversationId));
  if (content === '') {
    // 无可整理内容（空会话竞态 / 会话不足 2 条——buildMemoryContent 单条不成对话），零请求
    // 必要；★ 归 none 态：对用户就是「没有记忆产生」，与模型答「无」同一句提示
    hilog.info(DOMAIN, TAG, '会话可整理内容不足，跳过请求 conv=%{public}s', conversationId);
    return buildSinkResult(MEMORY_SINK_STATUS_NONE, 0);
  }
  // 库内上限守卫（有界红线——达 200 条跳过新增；与既有条目去重键、去重清单同一遍现读；
  // ★ v35 按目标库读——助手库独立计数同口径）
  const existing: string[] = [];
  const items: MemoryEntryItem[] = [];
  const libRows: MemoryRow[] = targetAssistantId !== '' ?
    await queryAssistantMemories(targetAssistantId) : await queryMemories();
  for (const row of libRows) {
    existing.push(normalizeMemoryKey(row.content));
    items.push({ content: row.content, createdAt: row.createdAt });
  }
  if (existing.length >= MEMORY_MAX_TOTAL) {
    hilog.info(DOMAIN, TAG, '记忆已达上限 %{public}d 条，跳过新增', MEMORY_MAX_TOTAL);
    return buildSinkResult(MEMORY_SINK_STATUS_LIMIT, 0);
  }
  // 提示词渲染（单遍扫描两占位符：{maxItems} 注入条数上限 + {content} 注入对话内容——
  // 生效模板现读，用户改提示词下次整理即生效；$& 特殊序列防线随单遍扫描天然成立）
  let prompt: string = renderMemoryPrompt(resolveMemoryPromptTemplate(), content,
    MEMORY_EXTRACT_MAX_COUNT);
  // 去重清单追加（P1-1）：★ 必须在渲染产物之后拼——清单含用户记忆文本，塞回模板再渲染
  // 等于给不可信内容开二次替换面；空清单不拼段（零回归）
  const list: string = composeMemoryList(items, MEMORY_DEDUP_MAX_COUNT, MEMORY_DEDUP_MAX_CHARS);
  if (list !== '') {
    prompt += MEMORY_DEDUP_SECTION.split(MEMORY_DEDUP_LIST_MARK).join(list);
  }
  // 末三形参：读超时与句柄回传走默认（undefined = 取形参默认值），第三位 taskLabel =
  // 请求日志来源标签 + 失败文案用途前缀（2026-09-23 请求日志笔；此前不传即错报「标题」）
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey, prompt, MEMORY_MAX_OUTPUT,
    undefined, undefined, '记忆');
  // 用途记账（2026-09-10 费用估计；2026-09-11 自检轮 P1-3 决明拍板放宽）：HTTP 200 即已
  // 消耗 token——正文缺失（ok=false 的 200 形态，TitleApi 已如实带回 usage）也入账；
  // 网络错误/HTTP 非 200 无 usage 不记（技术不可得）。放在解析/写库之前，「本次无值得
  // 沉淀的记忆」放弃不影响账本如实入账（purpose='memory'，conversationId = 触发会话
  // 随删会话级联删；全零不落 = 响应无 usage 字段的零污染守卫）
  if (result.status === 200) {
    logTaskUsage('memory', conversationId, picked.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (result.ok) {
    const lines: string[] = parseMemoryLines(result.text, MEMORY_EXTRACT_MAX_COUNT, existing);
    if (lines.length === 0) {
      // 模型答「无」与「条目全被敏感过滤/去重丢掉」同归 none（页面提示「未整理出值得记忆
      // 的信息」——不是失败，只是这次没东西可沉淀）
      hilog.info(DOMAIN, TAG, '本次无值得沉淀的记忆 conv=%{public}s', conversationId);
      return buildSinkResult(MEMORY_SINK_STATUS_NONE, 0);
    }
    if (targetAssistantId !== '') {
      // 助手库落库（v35）：写入目标跟随作用域——scope='assistant' 的助手沉淀进自己的库
      for (const line of lines) {
        await insertAssistantMemory(targetAssistantId, line, 'auto', conversationId);
      }
      hilog.info(DOMAIN, TAG, '记忆已沉淀 %{public}d 条（助手库 %{public}s） conv=%{public}s',
        lines.length, targetAssistantId, conversationId);
      broadcastAssistantMemoryList();
    } else {
      // 全局库落库（存量路径逐字节不变）：归属标注沿用原口径（'' = 无归属——手动链无行/
      // 助手已删形态）
      const assistantId: string = ownerId !== null && ownerId !== '' ? ownerId : '';
      for (const line of lines) {
        await insertMemory({ content: line, source: 'auto', assistantId: assistantId,
          conversationId: conversationId });
      }
      hilog.info(DOMAIN, TAG, '记忆已沉淀 %{public}d 条 conv=%{public}s', lines.length,
        conversationId);
      broadcastMemoryList();
    }
    return buildSinkResult(MEMORY_SINK_STATUS_INSERTED, lines.length);
  }
  // 失败分类（TitleGen 同款）：网络/5xx/429 退避重试；401/403/配置类不重试
  if (isRetryable(result.status) && attempt < MAX_MEMORY_RETRY) {
    const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, attempt + 1); // 2/4/8
    hilog.warn(DOMAIN, TAG, '记忆整理请求失败(%{public}d) conv=%{public}s，%{public}d 秒后第 %{public}d 次重试',
      result.status, conversationId, delaySeconds, attempt + 1);
    await sleep(delaySeconds * 1000);
    // 重试结果即本次结果（递归返回值原样上抛，勿吞成 void——否则手动链拿到 undefined）
    return runMemorySinking(conversationId, attempt + 1, manual, manualTarget);
  }
  hilog.warn(DOMAIN, TAG, '记忆整理最终失败放弃 conv=%{public}s status=%{public}d：%{public}s',
    conversationId, result.status, result.errorMessage);
  return buildSinkResult(MEMORY_SINK_STATUS_FAILED, 0);
}

// 失败恢复型退避等待（TitleGen 同款）
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

// ── search_memory 执行器（2026-09-13 记忆按需读取，方案 §2.3；注册在 ToolTypes）──
// 检索用户的长期记忆库：读库（≤200 条小数据集全量内存打分，P1-2 合规）→ MemoryText
// 检索纯函数（切词/打分/双封顶选取）→ 结果文本。★ 契约 = 恒 resolve 不 reject（错误走
// JSON 错误信息，SearchHelpExecutor 等项目先例）；端内执行零模型请求零费用，不记
// logTaskUsage（无可记项）；工具轮消耗走既有助手级 toolStepLimit。执行器无上下文
// （读不到助手行/会话态）——目标库经 MEMORY_EXEC_ASSISTANT_KEY 中转（v35 起随作用域
// 选库：键非空 = 该助手自己的库，空 = 全局库）；四闸（总开关/读取方式/助手开关/非私密）
// 在声明层 ChatSendCtrl 把关，未声明即不可达
export class SearchMemoryExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    let query: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    // 目标库分派（v35）：与 manage_memory 执行器同一判据同一键——跨库检索天然隔离
    const targetAssistantId: string = AppStorage.get<string>(MEMORY_EXEC_ASSISTANT_KEY) ?? '';
    const libRead: Promise<MemoryRow[]> = targetAssistantId !== '' ?
      queryAssistantMemories(targetAssistantId) : queryMemories();
    return libRead
      .then((rows: MemoryRow[]): string => {
        const items: MemorySearchItem[] = [];
        for (const row of rows) {
          items.push({ content: row.content, createdAt: row.createdAt,
            updatedAt: row.updatedAt });
        }
        return composeMemorySearchResult(items, query);
      })
      .catch((e: Object): string => {
        hilog.warn(DOMAIN, TAG, '记忆检索读取失败：%{public}s', (e as Error).message);
        return JSON.stringify({ error: '记忆读取失败：' + (e as Error).message });
      });
  }
}
