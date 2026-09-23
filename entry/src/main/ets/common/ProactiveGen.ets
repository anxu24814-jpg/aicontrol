// 主动消息服务（2026-09-12 主动消息第一笔「触发链底层」，任务书-主动消息-20260912；
// 方案档 docs/方案-主动消息-20260912.md——RikkaHub「场景描述一次请求」骨架 + astrbot
// 「空闲检测 + 随机抖动」时机策略）：进程级独立域，顶层函数模块，不持页面/组件引用、
// 不触 UI，全吞错误 hilog 留痕；呈现 = 落库后 bump SESSION_LIST_RELOAD_KEY + 写呈现层
// 两键（笔 2：未读红点 PROACTIVE_UNREAD_CONV_KEY + 横幅驱动 PROACTIVE_BANNER_KEY——红点
// 随列表刷新与键订阅自然上屏，横幅由 Index 根 Stack 常驻 ProactiveBanner 消费；系统通知
// 归后台方案档，会话页实时上屏不做〔§1.2〕）。
// · 触发链：EntryAbility.onForeground 写 APP_FOREGROUND_KEY 后调 onAppForeground()
//   （fire-and-forget）→ 冷启动闸（PREF_LOADED_KEY 未放行 = 首拍早于 loadContent 回调
//   persistProp 注册区，直读开关必得缺省会把开着的开关误判关闭吞掉首拍——2026-09-13
//   冷启动排期笔，决明拍板「冷启动也应加入排期，用户不会专门试挂后台」：挂起待
//   notifyProactiveKeysRegistered 放行补排，ProviderPresetSeed 门闩同形态）→ 按冷却期
//   排一次 setTimeout 检查（单发，非 setInterval——性能红线；冷却未过排到冷却期满的
//   时刻，已过排随机静默期——1 分钟至用户档上限，上限滑轨可调默认 5 分钟）→ 到点
//   runProactiveCheck() 走守卫序 → 解析归属
//   助手（当前助手）→ 组装请求 → requestTitleText → 建新会话落库（标题 + 横幅 + 红点）
//   → 广播 → logTaskUsage → 写 PROACTIVE_SENT_AT_KEY。
// · 守卫序六条（全过才发，任一不过 hilog 留痕即返，无静默落库路径）：①总开关开
//   ②应用在前台（运行态键）③当日已发 < 每日最多档（PROACTIVE_SENT_AT_KEY 滚动数组按
//   toLocalDayKey 计当日条数，上限读 PROACTIVE_DAILY_LIMIT_KEY 用户可调）④距最近
//   一次发送 ≥ 冷却间隔档（now - max(数组)）⑤归属助手合格（当前助手 ACTIVE_ASSISTANT_KEY
//   解析，空/行删回退内置默认助手——发送链「全局默认」兜底同口径；memoryInject 关 =
//   不发话，控制台助手经此守卫自然排除，无显式特判）⑥防打扰（最近活跃会话 updatedAt
//   距 now 不足 2 分钟 = 用户正在和任何助手聊天，本轮跳过——原「目标会话活跃窗口」
//   在新会话形态下的语义延续，改判全局最近活跃）。★ 原④免打扰时段（23:00~8:00）已撤——2026-09-12
//   决明拍板「取消 23~8 点不触发的限制」：触发源只有回前台一条，夜间触发必是用户夜间
//   在用应用，夜间消息可接受。
// · ★ 建新会话形态（2026-09-13 决明拍板，替代原「最近活跃已有会话」形态——真机首条
//   成功后决明指令「我希望是建新会话」；三项拍板 = AskUserQuestion 一道收敛）：归属 =
//   当前选择的助手；内容 = 只靠长期记忆（旧会话上下文方向待「助手跨会话读取记忆」
//   机制落地后再接，届时回本域扩 buildProactivePrompt 历史段）；标题 = 首句内容自动
//   截断（20 字符惯例，titleSource='' 占位态——用户后续在会话里发言时标题链可再升级）。
//   会话行 = 懒建语义消费（nextMessageId('conv') 本地生成 id → insertMessage 带
//   assistantId 建 ChatDb.ensureConversation 行，零新增建行函数）。
// · 时机语义（任务书 §二.2 拍板）：静默期到点时应用已后台/冻结则本轮自然流失（下次
//   onForeground 重排）；守卫不过同样流失，不追赶不积攒；开启开关本身不触发任何立即
//   发送；进程被杀后不触发，下次打开按冷却期补判。
// · 关停与触发源（2026-09-12 决明拍板「不做点击让 agent 发消息」）：★只有定时自动链
//   一个触发源——无 sendProactiveNow 类手动触发导出、页内无触发键；开关行关闭时调
//   cancelProactiveSchedule() 清已排句柄即时生效（切后台不必清句柄——守卫②兜住误
//   触发，清句柄只用于用户关开关）；已落消息不回收。
// · 请求形态（★ 一次请求成形，不两段式）：system 段 = 系统提示词（ChatPromptState 同
//   链解析）+ 记忆块（composeMemoryBlock 30 条/2000 字双封顶，与发送链同值常量本域
//   自持——ChatSendCtrl 侧为组件私有禁跨向 import）+ 场景段（当前本地时间/「以助手身份
//   主动开启一段新对话」约束）；★ 新会话零历史：上下文 = 空（不读任何旧会话消息——
//   决明拍板「只靠长期记忆」，旧会话方向见「建新会话形态」注）。★ 实查勘误（任务书
//   §1.2 补）：requestTitleText 传输层吃单串 prompt（TitleApi.buildTitleBody 固定单条
//   user 消息），消息列表不可直传——本域先用 RequestInject 三件套在消息列表语义上完成
//   组装（注入位置与顺序红线与发送链同构，断言可钉），末尾 toProactivePrompt 序列化为
//   「system 前导段」结构化文本单串再入通道（TitleApi 零改动）。
// · 组装顺序红线（sse-assert/断言族同源）：appendSystemMemory 必须在
//   composeSendMessages **之后**调用——后者 system 分支遇「历史已含 system」整体跳过，
//   提前调用会把会话/助手/系统提示词吞掉；场景段（appendSystemScene）在
//   appendSystemMemory 之后并入 system 尾部。
// · 模型与计费：端点复用记忆两键（resolveMemoryModel——未配置 = 功能未启用，与记忆
//   整理同口径不回退标题模型）；用量 purpose='proactive' 自动进费用统计页分组；
//   输出上限不设（PROACTIVE_MAX_OUTPUT = 0 对齐记忆链拍板——2026-09-12 真机三轮实锤
//   200 硬帽掐死思考模型思考段致正文恒空，见常量注）；失败退避重试照 MemoryGen
//   （2/4/8s ×3，仅 isRetryable 状态码），请求失败不落任何消息（P0-1，禁静默半截入库）。
// · ★ common → components 跨向 import 两处（ChatPromptState / SESSION_LIST_RELOAD_KEY）
//   为任务书 §1.1/§三.1 钦点：前者是「load 纯 DB 解析链非组件态，模块级自持单实例
//   串行复用」的既定设计（ChatSendCtrl 每实例一持是组件域口径，本域进程级一持），
//   后者是广播键单一来源禁裸字符串——均只取符号不触 UI，登记在案。
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ConversationRow, insertMessage, isReady, nextMessageId, nextRowCreatedAt,
  queryConversations, setConversationTitle
} from './store/ChatDb';
import { nextRowSeq } from './store/MessageSeqDb';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  queryAssistants
} from './store/AssistantDb';
import { requestTitleText, TitleRequestResult } from './providers/TitleApi';
import { TitleEndpoint, resolveTitleEndpoint, isRetryable } from './TitleGen';
import { loadPoolKey } from './store/KeyStore';
import { logTaskUsage } from './store/UsageStatsDb';
import { toLocalDayKey } from './store/UsageStatsCalc';
import { queryAssistantMemories, queryMemories, MEMORY_SCOPE_ASSISTANT } from './store/MemoryDb';
import { composeMemoryBlock, MemoryEntryItem } from './MemoryText';
import { isMemoryEnabled, MemoryModelPick, resolveMemoryModel } from './MemoryGen';
import {
  appendSystemMemory, composeSendMessages, PromptInjectConfig
} from './providers/RequestInject';
import { ChatPromptState } from '../components/chat/ChatPromptState';
import { SESSION_LIST_RELOAD_KEY } from '../components/chat/ChatSessionList';
import { PREF_LOADED_KEY } from './AppPreferences';

const DOMAIN: number = 0x71C4;
const TAG: string = 'ProactiveGen';

// ── 行为常量（除三个频次档外全部写死不进 UI；任务书 §三.1；静默期上限滑轨化见下）──
// 间隔档（小时，ProactivePage 滑轨八档——2026-09-12 决明指令弹窗改卡内滑轨，数组序 =
// 滑轨档序，滑轨走索引映射 0~7；同日频次扩域笔加密短档 1/2/3/6/12，决明「按你的来」）
export const PROACTIVE_INTERVAL_OPTIONS: number[] = [1, 2, 3, 4, 6, 8, 12, 24];
export const PROACTIVE_INTERVAL_DEFAULT: number = 24;
// 每日最多档（条，2026-09-12 决明追加「可用户设置发消息频次」——守卫③读键非写死；
// 同日频次扩域笔扩连续域 1~10 条：滑轨直映 + 编辑键精确输入，档位域数组承载白名单
// 校验域，resolveDailyLimit 与页面守卫同口径）
export const PROACTIVE_DAILY_LIMIT_OPTIONS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
export const PROACTIVE_DAILY_LIMIT_DEFAULT: number = 1;
// 回前台静默期上限档（分钟，2026-09-13 决明「主动消息页增加滑轨，支持用户自行控制，
// 类似已有的两个」——第三滑轨：原写死 1~5 分钟随机窗口的上限开放为八档非等距（数组序
// = 滑轨档序，索引映射同间隔档），下限 1 分钟保持写死；默认 5 = 与原行为逐字节一致
// 零回归。档位域数组同承载白名单校验域，resolveQuietMaxMinutes 与页面守卫同口径）
export const PROACTIVE_QUIET_MAX_OPTIONS: number[] = [1, 2, 3, 5, 10, 15, 20, 30];
export const PROACTIVE_QUIET_MAX_DEFAULT: number = 5;
// 回前台随机静默期下限（写死不进 UI——静默期到点要求仍在前台（守卫②），下限防回前台
// 即刻被搭话；上限档可调见上，span = 上限 − 下限恒 ≥ 0〔档位域最小 1 = 下限〕。
// 2026-09-12 频次扩域笔曾把原 10~30 分钟窗口缩为 1~5：长窗口是实际触发率第一瓶颈——
// 该调优随上限滑轨化移交用户自担，原「真机观察观感过急时回调本档」回改条件作废）
const PROACTIVE_FOREGROUND_QUIET_MIN_MS: number = 1 * 60_000;
// 防打扰窗口（最近活跃会话最新消息距 now 不足本窗口 = 用户正在和任何助手聊天，本轮
// 跳过——原「目标会话活跃窗口」守卫在建新会话形态下的语义延续，改判全局最近活跃）
const PROACTIVE_ACTIVE_WINDOW_MS: number = 2 * 60_000;
// 输出上限（0 = 不发 max_tokens 字段 = 模型按自身上限输出——2026-09-12 决明拍板对齐
// 记忆链「不设思考预算上限，正文靠提示词约束」：真机三轮实锤 deepseek-flash 思考模型
// completion 恰 200 全烧思考段、content 恒空 →「标题响应缺少正文」终败且 200 不可重试；
// 正文长度由场景段「一两句」约束 + 横幅截断与空文本拦截兜底，不靠 max_tokens 卡。
// anthropic 方言 0 = 必填兜底 131072（RequestCompose 三态；上限较小的老模型可能 400
// 属既有留档行为，与记忆链同形）
const PROACTIVE_MAX_OUTPUT: number = 0;
// 记忆注入双封顶（与 ChatSendCtrl.MEMORY_INJECT_MAX_COUNT/MAX_CHARS 同值——组件私有
// 常量禁跨向 import，本域自持同值；两处同改）
const PROACTIVE_MEMORY_MAX_COUNT: number = 30;
const PROACTIVE_MEMORY_MAX_CHARS: number = 2000;
// 退避重试（MemoryGen 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次，仅可重试状态码
const MAX_PROACTIVE_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;
const MS_PER_HOUR: number = 3_600_000;

// ── 持久与运行态键（persistProp 注册在 EntryAbility.onWindowStageCreate 回调内
//    坑17 区，插入位置 = 全部既有 persistProp 之后、PREF_LOADED_KEY 置 1 之前——该键是
//    「持久键注册完毕」闸信号；AppPreferences 两表登记见该文件—— SENT_AT 进排除表
//    〔本机发送时间戳与使用痕迹四键同族〕；APP_FOREGROUND_KEY 非持久）──
// 主动消息总开关（默认 false——用户显式开启才产生后台请求）
export const PROACTIVE_ENABLED_KEY: string = 'proactiveEnabled';
// 冷却间隔档（小时；值恒在 PROACTIVE_INTERVAL_OPTIONS 内，脏持久值回默认——
// resolveIntervalHours 兜底）
export const PROACTIVE_INTERVAL_HOURS_KEY: string = 'proactiveIntervalHours';
// 每日最多档（条；值恒在 PROACTIVE_DAILY_LIMIT_OPTIONS 内，脏持久值回默认——
// resolveDailyLimit 兜底）
export const PROACTIVE_DAILY_LIMIT_KEY: string = 'proactiveDailyLimit';
// 回前台静默期上限档（分钟；值恒在 PROACTIVE_QUIET_MAX_OPTIONS 内，脏持久值回默认——
// resolveQuietMaxMinutes 兜底，2026-09-13 静默期滑轨笔）
export const PROACTIVE_QUIET_MAX_KEY: string = 'proactiveQuietMaxMinutes';
// 发送时刻滚动数组（毫秒时间戳升序；★为什么是数组：每日上限可调（1~10）后单时间戳
// 无法算当日已发数——一键兼两用：冷却判据 = now - max(list) ≥ 间隔档；当日计数 =
// list 内 toLocalDayKey === 今天 的条数。写入后滚动裁到最近 PROACTIVE_SENT_AT_KEEP 条
// 〔= 每日上限最大值，有界红线〕；数组型持久键先例 EDIT_CROP_STATE_KEY/SEARCH_HISTORY_KEY）
export const PROACTIVE_SENT_AT_KEY: string = 'proactiveSentAt';
// 滚动保留条数（数据有界：裁剪上界 = 每日档最大值——上限调小后旧时间戳仍在窗口内
// 的边界自然正确，上限调大也有历史可数）
const PROACTIVE_SENT_AT_KEEP: number =
  PROACTIVE_DAILY_LIMIT_OPTIONS[PROACTIVE_DAILY_LIMIT_OPTIONS.length - 1];
// 应用前台运行态键（非持久，勿 persistProp——assert-proactive 钉在案）
export const APP_FOREGROUND_KEY: string = 'appForeground';
// ── 呈现层三键（2026-09-12 主动消息第二笔「应用内呈现层」）──
// 未读会话持久键（string，默认 ''）：落库时写目标会话 id，用户进入该会话页
// onPageShown 清空（ChatPage）——本机未读痕迹与 proactiveSentAt 同族，进 AppPreferences
// 排除表不随备份走；消费方 = ChatSessionList 红点（@StorageProp 只读订阅）
export const PROACTIVE_UNREAD_CONV_KEY: string = 'proactiveUnreadConv';
// 横幅驱动键（运行态非持久，勿 persistProp）：值 = 三元组 JSON 串（toBannerPayload），
// '' = 无横幅；消费方 = ProactiveBanner @StorageProp @Watch——键变即重挂（后到覆盖前条，
// 不排队不堆叠）；切后台期间残留属已知限制（回前台重挂重新计时，任务书 §四）
export const PROACTIVE_BANNER_KEY: string = 'proactiveBanner';
// 横幅点击直达命令键（运行态非持久）：值 = convId + '#' + 自增序号（序号保证同会话重复
// 命令也触发 @Watch——其只在值变化时回调）；发布方 = ProactiveBanner 点击，消费方 =
// HomeNavigation @Watch → openSession（CONSOLE_ASK_CMD_KEY 命令键同族范式）
export const PROACTIVE_OPEN_CMD_KEY: string = 'proactiveOpenCmd';

// 待排检查的 setTimeout 句柄（重排前必清旧——成对释放红线；到点自清 null）
let checkTimer: number | null = null;
// 检查在途标记（防 onForeground 高频重入双跑全链）
let checkRunning: boolean = false;
// 冷启动首拍挂起标记（2026-09-13 冷启动排期笔）：onForeground 首拍通常早于 loadContent
// 回调（persistProp 注册区——坑 17 落位），总开关键尚未注册，直读会把开着的开关误判为
// 关吞掉首拍排程；闸未放行时置位挂起，notifyProactiveKeysRegistered 放行后补排，放行前
// 再次回前台幂等置位。loadContent 失败路径（err.code 早退）永不放行 = 标志随进程悬置：
// 页面未加载应用不可用、排程语义无损，下次启动重判——无残留定时器无泄漏面
let pendingForegroundSchedule: boolean = false;
// 提示词解析域（任务书 §1.1：模块级自持单实例全程串行复用——load 是纯 DB 解析链，
// 组件无关；禁 new 多实例）
// ★ 2026-09-13 自检轮：改**惰性构建**（原为模块级 `const promptState = new ChatPromptState()`）。
// 顶层构造要求「本模块体求值那一刻 ChatPromptState 模块体已求值完」——而 ChatPromptState 正在
// 本域的 import 环内（本域 → ChatPromptState → ToolTypes → ToolPref → 回本域），该前提现今只由
// 「谁先访问」维持：实查全仓 importer 仅本文件与 ChatSendCtrl 两处，后者先 import ToolTypes
// 才迂回走通本域；任一新模块先于本域引 ChatPromptState，即重演顶层读未初始化绑定（坑50 家族
// ——进页/启动 JsError 闪退）。改首次取用时构造 + 缓存复用：单实例语义不变（禁 new 多实例照旧），
// 求值序与本域彻底解耦（ToolPref.setPrefWhitelist 同法）
let promptStateCache: ChatPromptState | null = null;
function promptState(): ChatPromptState {
  if (promptStateCache === null) {
    promptStateCache = new ChatPromptState();
  }
  return promptStateCache;
}

// 组装中间形态（与 RequestInject.InjectChatMessage 同构：role/content 两必填字段，
// 结构兼容直穿 composeSendMessages/appendSystemMemory——后者未导出，
// 调用方同构类型直穿是 ChatSendCtrl 既有先例；序列化只消费 role/content）
interface ProactiveHistoryMsg {
  role: string;
  content: string;
}

// 归属助手载体（resolveProactiveOwner 产出——建新会话形态下无目标会话，横幅显示名 =
// 归属助手名 owner.name）；memoryScope（v35，2026-09-20 助手级记忆）随行携带——记忆块
// 选库判据（'assistant' = 该助手自己的库，'global' = 全局库），与注入/沉淀三链同口径
interface ProactiveOwner {
  assistantId: string;
  assistantName: string;
  memoryScope: string;
}

export function isProactiveEnabled(): boolean {
  return AppStorage.get<boolean>(PROACTIVE_ENABLED_KEY) ?? false;
}

// 生效间隔档（UI 滑轨限定八档；持久键脏值〔版本回滚/异常写〕回默认 24）
export function resolveIntervalHours(): number {
  const stored: number = AppStorage.get<number>(PROACTIVE_INTERVAL_HOURS_KEY) ??
    PROACTIVE_INTERVAL_DEFAULT;
  for (const option of PROACTIVE_INTERVAL_OPTIONS) {
    if (option === stored) {
      return stored;
    }
  }
  return PROACTIVE_INTERVAL_DEFAULT;
}

// 生效每日最多档（UI 滑轨限定 1~10 连续域；脏持久值回默认 1——守卫③读键非写死，
// 2026-09-12 决明「可用户设置发消息频次」，同日频次扩域笔自 1/2/3 三档扩宽）
export function resolveDailyLimit(): number {
  const stored: number = AppStorage.get<number>(PROACTIVE_DAILY_LIMIT_KEY) ??
    PROACTIVE_DAILY_LIMIT_DEFAULT;
  for (const option of PROACTIVE_DAILY_LIMIT_OPTIONS) {
    if (option === stored) {
      return stored;
    }
  }
  return PROACTIVE_DAILY_LIMIT_DEFAULT;
}

// 生效静默期上限档（分钟；UI 滑轨限定八档非等距，脏持久值回默认 5——排程读键非写死，
// 2026-09-13 静默期滑轨笔；与 resolveIntervalHours 同构白名单兜底）
export function resolveQuietMaxMinutes(): number {
  const stored: number = AppStorage.get<number>(PROACTIVE_QUIET_MAX_KEY) ??
    PROACTIVE_QUIET_MAX_DEFAULT;
  for (const option of PROACTIVE_QUIET_MAX_OPTIONS) {
    if (option === stored) {
      return stored;
    }
  }
  return PROACTIVE_QUIET_MAX_DEFAULT;
}

// 发送时刻数组现读（持久层 number[] 一维数组；缺省回 []——从未发过）
function sentAtList(): number[] {
  return AppStorage.get<number[]>(PROACTIVE_SENT_AT_KEY) ?? [];
}

// 数组最大值（ArkTS 展开 Math.max(...arr) 不保证可用，循环直求；空数组回 0）
function maxSentAt(list: number[]): number {
  let max: number = 0;
  for (const ts of list) {
    if (ts > max) {
      max = ts;
    }
  }
  return max;
}

// 压入发送时刻并滚动裁剪（升序保留最近 PROACTIVE_SENT_AT_KEEP 条——数据有界红线；
// 裁剪上界 = 每日档最大值，与档位联动见常量注释）
function pushSentAt(at: number): void {
  const list: number[] = sentAtList();
  list.push(at);
  while (list.length > PROACTIVE_SENT_AT_KEEP) {
    list.shift();
  }
  AppStorage.setOrCreate<number[]>(PROACTIVE_SENT_AT_KEY, list);
}

// ── 呈现层载荷与命令键工具（笔 2；写侧 = 本域落库尾段与 ProactiveBanner 点击，读侧 =
//    ProactiveBanner / HomeNavigation——分隔符与 JSON 结构单源在本域）──

// 横幅载荷三元组（单键 JSON 串原子更新，防三键竞态半态；解析侧容错回 null = 不显示）
export interface ProactiveBannerPayload {
  convId: string;
  name: string;
  text: string;
}

// 序列化（落库尾段调用：助手名 + 首行截断文本）
export function toBannerPayload(convId: string, name: string, text: string): string {
  const payload: ProactiveBannerPayload = { convId: convId, name: name, text: text };
  return JSON.stringify(payload);
}

// 解析（ProactiveBanner 消费；容错：空串/坏 JSON/字段缺失或类型不符回 null）
export function parseBannerPayload(raw: string): ProactiveBannerPayload | null {
  if (raw === '') {
    return null;
  }
  try {
    const parsed: ProactiveBannerPayload = JSON.parse(raw) as ProactiveBannerPayload;
    if (typeof parsed.convId !== 'string' || typeof parsed.name !== 'string' ||
      typeof parsed.text !== 'string') {
      return null;
    }
    return parsed;
  } catch (e) {
    return null;
  }
}

// 横幅首行截断（任务书 §二：首行 + 按字符截断 + 省略号；渲染侧 Text maxLines(1) 再兜底）
const PROACTIVE_BANNER_PREVIEW_MAX: number = 50;
function toBannerPreview(text: string): string {
  const firstLine: string = text.split('\n')[0];
  return firstLine.length > PROACTIVE_BANNER_PREVIEW_MAX ?
    firstLine.substring(0, PROACTIVE_BANNER_PREVIEW_MAX) + '…' : firstLine;
}

// 横幅点击命令派发（'#' 分隔 convId 与自增序号——序号让同会话重复点击也触发 @Watch；
// 脏值序号容错回 0 重计）
export function bumpProactiveOpenCmd(convId: string): void {
  const prev: string = AppStorage.get<string>(PROACTIVE_OPEN_CMD_KEY) ?? '';
  const tail: string = prev.split('#')[1] ?? '';
  const prevSeq: number = tail !== '' && !Number.isNaN(Number(tail)) ? Number(tail) : 0;
  AppStorage.setOrCreate<string>(PROACTIVE_OPEN_CMD_KEY, convId + '#' + (prevSeq + 1));
}

// 命令解析（'#' 前段 = 会话 id；'' = 空命令不导航，消费方判空）
export function parseProactiveOpenCmd(raw: string): string {
  return raw.split('#')[0];
}

// 回前排程入口（EntryAbility.onForeground 一行 fire-and-forget）：先过冷启动闸——
// PREF_LOADED_KEY 未放行（首拍早于 persistProp 注册区，此时读开关必得缺省）置挂起标记
// 即返，已放行清标记走总开关早退后排程；开关关闭即时生效由 cancelProactiveSchedule
// 承接（ProactivePage 开关行调用）
export function onAppForeground(): void {
  if ((AppStorage.get<number>(PREF_LOADED_KEY) ?? 0) !== 1) {
    pendingForegroundSchedule = true;
    hilog.info(DOMAIN, TAG, '偏好键未注册完毕（冷启动首拍），主动消息排程挂起待闸放行');
    return;
  }
  pendingForegroundSchedule = false;
  scheduleProactiveIfEnabled();
}

// 冷启动闸放行通知（EntryAbility loadContent 回调主动消息六键 persistProp 注册完毕后
// 调用——ProviderPresetSeed.notifyPresetSeedKeyRegistered 同款门闩形态）：有挂起的首拍
// 才补排，无挂起（热启动 / 回调先于 onForeground 的极端序）幂等即返
export function notifyProactiveKeysRegistered(): void {
  if (!pendingForegroundSchedule) {
    return;
  }
  pendingForegroundSchedule = false;
  hilog.info(DOMAIN, TAG, '偏好键注册完毕，冷启动首拍挂起的主动消息排程放行');
  scheduleProactiveIfEnabled();
}

// 总开关早退后排程（回前台入口与闸放行补排共用入口动作——关 = 零排程零定时器）
function scheduleProactiveIfEnabled(): void {
  if (!isProactiveEnabled()) {
    return;
  }
  scheduleProactiveCheck();
}

// 清已排检查（开关行关闭时调——定时器不残留；在途请求不中断：已扣费的在途请求完成仍
// 落库（首次成功路径落库前无开关复查，属「已发起请求收尾」语义）；重试路径守卫全重查
// ——开关已关则①拦下不再重试）
export function cancelProactiveSchedule(): void {
  if (checkTimer !== null) {
    clearTimeout(checkTimer);
    checkTimer = null;
    hilog.info(DOMAIN, TAG, '主动消息排程已取消');
  }
}

// 排一次检查（任务书 §二.2 顺延口径）：冷却未过 → 排到冷却期满的时刻；已过 → 排
// 随机静默期 1~5 分钟。到点应用已后台则守卫②拦下（本轮流失，下次回前台重排）
function scheduleProactiveCheck(): void {
  if (checkTimer !== null) {
    clearTimeout(checkTimer);
    checkTimer = null;
  }
  const last: number = maxSentAt(sentAtList()); // 0 = 从未发过 → 冷却视为已过
  const cooldownEnd: number = last + resolveIntervalHours() * MS_PER_HOUR;
  const now: number = Date.now();
  let delayMs: number;
  if (cooldownEnd > now) {
    delayMs = cooldownEnd - now;
    hilog.info(DOMAIN, TAG, '主动消息排程至冷却期满（%{public}d 毫秒后）', delayMs);
  } else {
    // 随机静默期窗口 = 1 分钟（写死下限）至用户档上限（resolveQuietMaxMinutes——上限
    // 滑轨可调，2026-09-13 静默期滑轨笔）；span 恒 ≥ 0（档位域最小 1 = 下限，取 1 即
    // 固定 1 分钟无随机）。随机化时机全由本档承担，冷却判据用整档不另抖——§1.2 勘误 5
    const quietMaxMinutes: number = resolveQuietMaxMinutes();
    const span: number = quietMaxMinutes * 60_000 - PROACTIVE_FOREGROUND_QUIET_MIN_MS;
    delayMs = PROACTIVE_FOREGROUND_QUIET_MIN_MS + Math.floor(Math.random() * span);
    hilog.info(DOMAIN, TAG, '主动消息排随机静默期（%{public}d 毫秒后，上限 %{public}d 分钟）',
      delayMs, quietMaxMinutes);
  }
  checkTimer = setTimeout((): void => {
    checkTimer = null;
    runProactiveCheck().catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '主动消息检查异常终止：%{public}s', (e as Error).message);
    });
  }, delayMs);
}

// 主检查入口（in-flight 闸 + 全吞错误包装）
async function runProactiveCheck(): Promise<void> {
  if (checkRunning) {
    hilog.info(DOMAIN, TAG, '主动消息检查在途，本次触发跳过');
    return;
  }
  checkRunning = true;
  try {
    await runProactiveCheckInner(0);
  } catch (e) {
    hilog.error(DOMAIN, TAG, '主动消息链路异常终止：%{public}s', (e as Error).message);
  } finally {
    checkRunning = false;
  }
}

// 守卫序 + 组装 + 发送（attempt 从 0 起；retryable 失败经 sleep 退避后递归重入——
// 守卫全重查，与 MemoryGen 递归形态一致）。每个返回点均 hilog 留痕（验收：七守卫任一
// 置假路径无静默落库）
async function runProactiveCheckInner(attempt: number): Promise<void> {
  const now: number = Date.now();
  // ① 总开关（排程后到点前用户关掉的竞态兜底——关闭链另有 cancelProactiveSchedule）
  if (!isProactiveEnabled()) {
    hilog.debug(DOMAIN, TAG, '主动消息总开关已关，本轮跳过');
    return;
  }
  // ② 应用在前台（后台/冻结窗口期到点的守卫；到点即拦）
  if (!(AppStorage.get<boolean>(APP_FOREGROUND_KEY) ?? false)) {
    hilog.info(DOMAIN, TAG, '应用不在前台，本轮流失（下次回前台重排）');
    return;
  }
  const sentList: number[] = sentAtList();
  // ③ 每日上限（本地自然日按 toLocalDayKey 计数当日条数，上限读 PROACTIVE_DAILY_LIMIT_KEY
  // 用户可调档——2026-09-12 决明「可用户设置发消息频次」；数组空 = 从未发过）
  const todayKey: string = toLocalDayKey(now);
  let todayCount: number = 0;
  for (const ts of sentList) {
    if (toLocalDayKey(ts) === todayKey) {
      todayCount++;
    }
  }
  const dailyLimit: number = resolveDailyLimit();
  if (todayCount >= dailyLimit) {
    hilog.info(DOMAIN, TAG, '主动消息今日已发 %{public}d 条达每日上限 %{public}d，本轮跳过',
      todayCount, dailyLimit);
    return;
  }
  // ④ 冷却间隔（距最近一次发送 ≥ 间隔档——守卫③已拦「今天发满」，此处再拦「跨天但
  // 未满档」，如 4 小时档上午发过下午到点的回前台重排场景；max 0 = 从未发过视为已过）
  const intervalMs: number = resolveIntervalHours() * MS_PER_HOUR;
  const lastSent: number = maxSentAt(sentList);
  if (now - lastSent < intervalMs) {
    hilog.info(DOMAIN, TAG, '冷却期未满（距上条 %{public}d 毫秒 < %{public}d），本轮跳过',
      now - lastSent, intervalMs);
    return;
  }
  if (!isReady()) {
    hilog.warn(DOMAIN, TAG, '数据库未就绪，本轮跳过');
    return;
  }
  // ⑤ 归属助手（当前助手解析 + memoryInject 判定——resolveProactiveOwner 内）
  const owner: ProactiveOwner | null = await resolveProactiveOwner();
  if (owner === null) {
    hilog.info(DOMAIN, TAG, '归属助手不合格（未开记忆注入），本轮跳过');
    return;
  }
  // ⑥ 防打扰（最近活跃会话 2 分钟内更新 = 用户正在聊天，任何助手都不打扰——建新
  // 会话形态下原活跃窗口守卫的全局语义延续）
  const newestAt: number = await latestConversationActivity();
  if (newestAt > 0 && now - newestAt < PROACTIVE_ACTIVE_WINDOW_MS) {
    hilog.info(DOMAIN, TAG, '最近会话 %{public}d 毫秒内有新消息（用户在聊天），本轮跳过',
      now - newestAt);
    return;
  }
  // 提取模型（记忆两键复用——未配置 = 功能未启用，与记忆整理同口径不回退标题模型）
  const picked: MemoryModelPick = resolveMemoryModel();
  if (picked.providerId === '' || picked.modelId === '') {
    hilog.debug(DOMAIN, TAG, '记忆提取模型未配置，主动消息功能未启用');
    return;
  }
  const resolved: TitleEndpoint | null =
    await resolveTitleEndpoint(picked.providerId, picked.modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '主动消息模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return;
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——TitleGen 同口径）
  const apiKey: string = await loadPoolKey(picked.providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '主动消息 Key 明文缺失，放弃');
    return;
  }
  // 新会话 id 先行本地生成（懒建语义——请求成功才落库建行，失败则 id 弃用零残留）
  const convId: string = nextMessageId('conv');
  // 组装（顺序红线：composeSendMessages → appendSystemMemory → appendSystemScene）
  const prompt: string = await buildProactivePrompt(owner, convId, resolved.modelId);
  // 末三形参：读超时与句柄回传走默认，第三位 taskLabel = 请求日志来源标签 + 失败文案用途
  // 前缀（2026-09-23 请求日志笔；此前不传即错报「标题」）
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl,
    resolved.modelId, resolved.protocol, resolved.endpoint, apiKey, prompt,
    PROACTIVE_MAX_OUTPUT, undefined, undefined, '主动消息');
  // 用量记账（HTTP 200 即已消耗 token，正文缺失也入账——MemoryGen 同口径；放在落库
  // 之前，「请求成功但落库失败」不影响账本如实入账）
  if (result.status === 200) {
    logTaskUsage('proactive', convId, picked.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (!result.ok) {
    // 失败分类照 MemoryGen：网络/5xx/429 退避重试（守卫全重查），401/403/配置类不重试；
    // 终败只留痕，不落任何消息（P0-1 禁静默半截入库）
    if (isRetryable(result.status) && attempt < MAX_PROACTIVE_RETRY) {
      const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, attempt + 1); // 2/4/8
      hilog.warn(DOMAIN, TAG, '主动消息请求失败(%{public}d)，%{public}d 秒后第 %{public}d 次重试',
        result.status, delaySeconds, attempt + 1);
      await sleepProactive(delaySeconds * 1000);
      return runProactiveCheckInner(attempt + 1);
    }
    hilog.warn(DOMAIN, TAG, '主动消息最终失败放弃 status=%{public}d：%{public}s',
      result.status, result.errorMessage);
    return;
  }
  // 空返回拦截（★自检轮补）：返回文本 trim 后为空亦视为失败不落库——防空 assistant
  // 消息上屏与空横幅（ok=true 只保证非空串，纯空白仍可能）
  if (result.text.trim() === '') {
    hilog.warn(DOMAIN, TAG, '主动消息返回空文本，不落库');
    return;
  }
  // 建新会话落库（懒建语义消费：insertMessage 带 assistantId 首条建行
  // ChatDb.ensureConversation——零新增建行函数；一次性 status 'done' 完整 assistant
  // 消息——非流式无需 finalizeMessage）
  // 行时间走单调分配器（★ 2026-09-21 消息存储机制改造笔 2 债务②收口：原写裸 Date.now()）；
  // 本会话恒为新 id（上方 nextMessageId('conv')）⇒ 分配器无记账 ⇒ 本行 seq 恒 0（会话首行）。
  // sentAt 兼作下方 pushSentAt 的冷却基准——分配器值 ≈ now 且单调，冷却判据（now − lastSent
  // 与日键计数）语义不变
  const sentAt: number = nextRowCreatedAt();
  await insertMessage({
    id: nextMessageId('msg'),
    conversationId: convId,
    role: 'assistant',
    content: result.text,
    reasoning: '',
    status: 'done',
    createdAt: sentAt,
    seq: nextRowSeq(convId)
  }, owner.assistantId);
  // 会话标题 = 首句截断（titleSource='' 占位态——用户后续在该会话发言时标题链可再
  // 升级；20 字符省略号惯例与 TitleGen.TITLE_PLACEHOLDER_MAX_CHARS 同形，本域自持）
  await setConversationTitle(convId, toProactiveTitle(result.text), '');
  // 会话列表刷新广播（呈现面=列表；会话页恰好开着不当场自动上屏属预期——§1.2 勘误 3）
  bumpSessionListReload();
  // 压入发送时刻（滚动裁到最近 PROACTIVE_SENT_AT_KEEP 条 = 每日档最大值，数据有界）
  pushSentAt(sentAt);
  // 呈现层两键（笔 2）：未读红点（进会话页 onPageShown 清）+ 横幅（助手名 + 首行截断；
  // 前台守卫②保证落库恒在前台——切后台竞态下键残留属已知限制，回前台重挂重新计时）
  AppStorage.setOrCreate<string>(PROACTIVE_UNREAD_CONV_KEY, convId);
  AppStorage.setOrCreate<string>(PROACTIVE_BANNER_KEY, toBannerPayload(
    convId, owner.assistantName, toBannerPreview(result.text)));
  hilog.info(DOMAIN, TAG, '主动消息已落库新会话 conv=%{public}s', convId);
}

// 归属助手解析（★ 建新会话形态拍板「归属 = 当前选择的助手」）：ACTIVE_ASSISTANT_KEY
// 读当前助手 → 行删/键空回退内置默认助手（发送链四级兜底「全局默认」同口径）→
// memoryInject 判定（关 = 不在其名下发话，来历不明防线同前；控制台助手经此守卫自然
// 排除，无显式特判）。不合格回 null。
async function resolveProactiveOwner(): Promise<ProactiveOwner | null> {
  const pickedId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ??
    ASSISTANT_DEFAULT_ID;
  const row: AssistantRow | null = await queryAssistant(
    pickedId !== '' ? pickedId : ASSISTANT_DEFAULT_ID);
  if (row === null) {
    return null;
  }
  if (!row.memoryInject) {
    return null;
  }
  return { assistantId: row.id, assistantName: row.name, memoryScope: row.memoryScope };
}

// 防打扰判据（守卫⑥）：全助手集查最近活跃会话（updatedAt 降序首行——懒建语义下
// updatedAt 随消息 touch 维护 ≈ 最新消息时刻），空表回 0 = 无会话不打扰。原「目标
// 会话活跃窗口」在建新会话形态下的全局语义延续：用户正在和任何助手聊天都不打扰
async function latestConversationActivity(): Promise<number> {
  const assistants: AssistantRow[] = await queryAssistants();
  const assistantIds: string[] = [];
  for (const assistant of assistants) {
    assistantIds.push(assistant.id);
  }
  assistantIds.push('');
  const conversations: ConversationRow[] = await queryConversations(assistantIds);
  return conversations.length > 0 ? conversations[0].updatedAt : 0;
}

// 会话标题截断（20 字符省略号——TitleGen 占位标题同形惯例：压空白规整后截断，多行
// 回复的换行在规整时折叠；空白规整同款）
const PROACTIVE_TITLE_MAX_CHARS: number = 20;
function toProactiveTitle(text: string): string {
  const squeezed: string = text.replace(/\s+/g, ' ').trim();
  return squeezed.length > PROACTIVE_TITLE_MAX_CHARS ?
    squeezed.substring(0, PROACTIVE_TITLE_MAX_CHARS) + '…' : squeezed;
}

// 请求组装（★顺序红线：composeSendMessages → appendSystemMemory → appendSystemScene
// ——appendSystemMemory 必须在 composeSendMessages 之后，提前调用会把会话/助手/系统
// 提示词吞掉〔composeSendMessages 的 system 分支遇已含 system 整体跳过〕，RequestInject
// 注释与断言族互证）：★ 新会话零历史（决明拍板「只靠长期记忆」）——历史恒空数组，
// composeSendMessages 的 system 注入分支照常产出提示词位（拼接式分支 target<0 原样
// 返回不伪造，RequestInject 既有容错）；提示词注入（ChatPromptState 同链 load +
// applyVariables，变量替换取当下时刻；load 新 id 无行 → effectiveAssistantId =
// 当前助手，与落库归属同源）→ 记忆块并 system 位 → 场景段并 system 尾 → 序列化单串
async function buildProactivePrompt(owner: ProactiveOwner, convId: string,
  modelId: string): Promise<string> {
  const history: ProactiveHistoryMsg[] = [];
  const state: ChatPromptState = promptState();
  await state.load(convId);
  const config: PromptInjectConfig | null =
    state.applyVariables(state.config(), modelId);
  const composed: ProactiveHistoryMsg[] = composeSendMessages(history, config);
  const withMemory: ProactiveHistoryMsg[] =
    appendSystemMemory(composed, await buildProactiveMemoryBlock(owner));
  const withScene: ProactiveHistoryMsg[] =
    appendSystemScene(withMemory, buildSceneSection(Date.now()));
  return toProactivePrompt(withScene);
}

// 记忆块（发送链 buildMemoryBlock 同口径：记忆总开关关/库空 → ''（appendSystemMemory
// 对空串原样返回零回归）；30 条/2000 字双封顶——与发送链同值）。
// ★ v35（2026-09-20 助手级记忆）：按归属助手作用域选库——'assistant' = 该助手自己的库
//（queryAssistantMemories），'global' = 全局库原路径（存量行为逐字节不变）；与发送链/
// 沉淀链/工具链四路同源同口径（ownerId 空 = 全局兜底，与发送链同判据）
async function buildProactiveMemoryBlock(owner: ProactiveOwner): Promise<string> {
  if (!isMemoryEnabled()) {
    return '';
  }
  const useAssistantLib: boolean =
    owner.memoryScope === MEMORY_SCOPE_ASSISTANT && owner.assistantId !== '';
  const rows = useAssistantLib ?
    await queryAssistantMemories(owner.assistantId) : await queryMemories();
  if (rows.length === 0) {
    return '';
  }
  const items: MemoryEntryItem[] = [];
  for (const row of rows) {
    items.push({ content: row.content, createdAt: row.createdAt });
  }
  return composeMemoryBlock(items, PROACTIVE_MEMORY_MAX_COUNT, PROACTIVE_MEMORY_MAX_CHARS);
}

// 场景段（建新会话形态：当前本地时间 + 主动开启新对话约束——原「距上一条用户消息
// 时长」句随旧会话形态退役，无对话记录段时该句失去指代对象。「不要复述本段场景描述」
// 防模型把时间念出来）
function buildSceneSection(now: number): string {
  return '当前时间是 ' + formatLocalTime(now) +
    '。请以助手身份主动开启一段新对话，说一两句自然的话，不要复述本段场景描述。';
}

// 场景段并入 system 尾部（appendSystemMemory 同形态：首条 system 合并 content 尾部，
// 无 system 首位插入——连续两条 system 会撞 Anthropic/Gemini 交替约束，故必合并不另插）
function appendSystemScene(history: ProactiveHistoryMsg[],
  scene: string): ProactiveHistoryMsg[] {
  if (history.length > 0 && history[0].role === 'system') {
    const merged: ProactiveHistoryMsg[] =
      [{ role: 'system', content: history[0].content + '\n\n' + scene }];
    for (let i = 1; i < history.length; i++) {
      merged.push(history[i]);
    }
    return merged;
  }
  const injected: ProactiveHistoryMsg[] = [{ role: 'system', content: scene }];
  for (const m of history) {
    injected.push(m);
  }
  return injected;
}

// 组装列表 → 单串 prompt（requestTitleText 传输层吃单串——文件头「请求形态」注）：
// system 消息按序作前导段（提示词 → 记忆块 → 场景段），user/assistant 交替以
// 「用户:/助手:」前缀展平为对话记录段
function toProactivePrompt(history: ProactiveHistoryMsg[]): string {
  const sections: string[] = [];
  const turns: string[] = [];
  for (const m of history) {
    if (m.role === 'system') {
      sections.push(m.content);
    } else if (m.role === 'user') {
      turns.push('用户:' + m.content);
    } else {
      turns.push('助手:' + m.content);
    }
  }
  if (turns.length > 0) {
    sections.push('你们最近的对话记录如下。\n' + turns.join('\n'));
  }
  return sections.join('\n\n');
}

// 本地时间 YYYY-MM-DD HH:mm（场景段用；本地时区口径）
function formatLocalTime(ms: number): string {
  const d: Date = new Date(ms);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' +
    pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : n.toString();
}

// 会话列表刷新广播（一次性计数器自增——@Watch 只在值变化时回调，勿写固定值）
function bumpSessionListReload(): void {
  const tick: number = AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0;
  AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY, tick + 1);
}

// 失败恢复型退避等待（MemoryGen 同款）
function sleepProactive(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}
