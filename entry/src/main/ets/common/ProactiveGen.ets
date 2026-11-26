// 主动消息服务：进程级独立域顶层函数模块，不持页面/组件引用、不触 UI，全吞错误
// hilog 留痕；呈现 = 落库后 bump SESSION_LIST_RELOAD_KEY + 写呈现层两键（未读红点
// PROACTIVE_UNREAD_CONV_KEY + 横幅 PROACTIVE_BANNER_KEY——红点随列表刷新与键订阅上屏，
// 横幅由 Index 根 Stack 常驻 ProactiveBanner 消费；系统通知与会话页实时上屏不做）。
// · 触发链：EntryAbility.onForeground 写 APP_FOREGROUND_KEY 后调 onAppForeground()
//   （fire-and-forget）→ 冷启动闸（坑17：首拍早于 persistProp 注册区，见
//   pendingForegroundSchedule 注；决明拍板「冷启动也应加入排期」）→ 按冷却期排一次
//   setTimeout 检查（单发非 setInterval——性能红线；冷却未过排到期满时刻，已过排随机
//   静默期 1 分钟至用户档上限）→ 到点 runProactiveCheck() 守卫序 → 解析归属助手 →
//   组装请求 → requestTitleText → 建新会话落库 → 广播 → logTaskUsage → 写
//   PROACTIVE_SENT_AT_KEY。
// · 守卫序六条（全过才发，任一不过留痕即返，无静默落库路径）：①总开关开 ②应用在前台
//   （运行态键）③当日已发 < 每日最多档（PROACTIVE_SENT_AT_KEY 滚动数组按 toLocalDayKey
//   计当日条数，上限用户可调）④距最近一次发送 ≥ 冷却间隔档（now - max(数组)）
//   ⑤归属助手合格（当前助手 ACTIVE_ASSISTANT_KEY 解析，空/行删回退内置默认助手——
//   发送链「全局默认」兜底同口径；memoryInject 关 = 不发话）⑥防打扰（最近活跃会话
//   updatedAt 距 now 不足 2 分钟 = 用户正在和任何助手聊天，本轮跳过——全局最近活跃
//   语义）。★ 原免打扰时段（23:00~8:00）已撤——决明拍板「夜间触发必是用户夜间在用
//   应用，夜间消息可接受」。
// · ★ 建新会话形态（决明拍板，替代原「最近活跃已有会话」形态）：归属 = 当前选择的
//   助手；内容 = 只靠长期记忆（旧会话上下文待跨会话记忆机制落地后再接）；标题 = 首句
//   20 字符截断（titleSource='' 占位态——用户后续发言时标题链可再升级）；会话行 =
//   懒建语义（nextMessageId('conv') 本地生成 id，请求成功才落库建行）。
// · 时机语义：静默期到点已后台/冻结或守卫不过则本轮流失（下次 onForeground 重排），
//   不追赶不积攒；开启开关本身不触发立即发送；进程被杀后不触发。
// · 关停与触发源（决明拍板「不做点击让 agent 发消息」）：★只有定时自动链一个触发源
//   ——无手动触发导出、页内无触发键；开关关闭即时生效（cancelProactiveSchedule，切
//   后台不必清句柄——守卫②兜住）；已落消息不回收。
// · 请求形态（★一次请求成形，不两段式）：system 段 = 系统提示词（ChatPromptState 同链
//   解析）+ 记忆块（composeMemoryBlock 双封顶，与发送链同值常量本域自持——ChatSendCtrl
//   侧组件私有禁跨向 import）+ 场景段；★ 新会话零历史（决明拍板「只靠长期记忆」）。
//   ★ 勘误：requestTitleText 传输层吃单串 prompt（TitleApi.buildTitleBody 固定单条
//   user 消息），消息列表不可直传——先用 RequestInject 三件套在消息列表语义上组装
//   （注入位置与顺序红线与发送链同构，断言可钉），末尾 toProactivePrompt 序列化为
//   单串再入通道（TitleApi 零改动）。
// · 组装顺序红线（单源细则见 buildProactivePrompt 注）：appendSystemMemory 必须在
//   composeSendMessages 之后，提前调用会把系统提示词吞掉；场景段在其后并入 system 尾。
// · 模型与计费：端点复用记忆两键（resolveMemoryModel——未配置 = 功能未启用，不回退
//   标题模型）；用量 purpose='proactive' 进费用统计分组；输出上限不设（对齐记忆链
//   拍板，见常量注）；失败退避重试照 MemoryGen（2/4/8s ×3，仅可重试状态码），请求
//   失败不落任何消息（P0-1 禁静默半截入库）。
// · common → components 跨向 import 已清零（ChatPromptState 迁 common/chat/、广播键
//   迁 AppBroadcastKeys）——本域对 components 层零 import；单实例语义与进程级一持
//   不变（ChatSendCtrl 每实例一持是组件域口径）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ConversationRow, isReady, nextMessageId, nextRowCreatedAt,
  queryConversations, setConversationTitle
} from './store/ChatDb';
import { bornGraphConversation } from './chat/ChatContextSource';
import { ORIGIN_SEND, prepareRun, commitRunUnit, finishRun,
  RUN_STATUS_FINISHED, RUN_STATUS_RUNNING } from './store/MessageBranchDb';
import { sharedRdbStore } from './store/ChatDb';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, AssistantRow,
  queryAssistant, queryAssistants
} from './store/AssistantDb';
import { READ_TIMEOUT_MS, requestTitleText, resolveFunctionalThinking,
  TitleRequestResult } from './providers/TitleApi';
import { TitleEndpoint, resolveTitleEndpoint, isRetryable } from './TitleGen';
import { loadPoolKey } from './store/KeyStore';
import { logTaskUsage } from './store/UsageStatsDb';
import { toLocalDayKey } from './store/UsageStatsCalc';
import { queryAssistantMemories, queryMemories, MEMORY_SCOPE_ASSISTANT } from './store/MemoryDb';
import { composeMemoryBlock, MemoryEntryItem } from './MemoryText';
import { isMemoryEnabled, MemoryModelPick, resolveMemoryModel } from './MemoryGen';
import {
  appendSystemBlock, composeSendMessages, PromptInjectConfig
} from './providers/RequestInject';
import { ChatPromptState } from './chat/ChatPromptState';
import { PROACTIVE_UNREAD_CONV_KEY, SESSION_LIST_RELOAD_KEY } from './AppBroadcastKeys';
import { PREF_LOADED_KEY } from './AppPreferences';

import {
  PROACTIVE_DAILY_LIMIT_DEFAULT, PROACTIVE_DAILY_LIMIT_KEY, PROACTIVE_DAILY_LIMIT_OPTIONS,
  PROACTIVE_ENABLED_KEY, PROACTIVE_INTERVAL_DEFAULT, PROACTIVE_INTERVAL_HOURS_KEY,
  PROACTIVE_INTERVAL_OPTIONS, PROACTIVE_QUIET_MAX_DEFAULT, PROACTIVE_QUIET_MAX_KEY,
  PROACTIVE_QUIET_MAX_OPTIONS } from './ProactiveConfig';
const DOMAIN: number = 0x71C4;
const TAG: string = 'ProactiveGen';

// ── 行为常量（除三个频次档外全部写死不进 UI；三条档位域数组与默认值外迁
//    ./ProactiveConfig 叶子——与设置白名单 ToolPref 共享以切断反向依赖；KEEP 由档位
//    末元派生，求值序天然安全）──
// 回前台随机静默期下限（写死不进 UI——静默期到点要求仍在前台（守卫②），下限防回前台
// 即刻被搭话；span = 上限 − 下限恒 ≥ 0，档位域最小 1 = 下限）
const PROACTIVE_FOREGROUND_QUIET_MIN_MS: number = 1 * 60_000;
// 防打扰窗口（最近活跃会话最新消息距 now 不足本窗口 = 用户正在聊天，本轮跳过——
// 全局最近活跃语义）
const PROACTIVE_ACTIVE_WINDOW_MS: number = 2 * 60_000;
// 输出上限（0 = 不发 max_tokens 字段——决明拍板对齐记忆链「不设思考预算上限，正文靠
// 提示词约束」：真机实锤思考模型 200 硬帽全烧思考段致正文恒空；正文长度由场景段 +
// 截断与空文本拦截兜底；anthropic 方言 0 = 必填兜底 131072，与记忆链同形）
const PROACTIVE_MAX_OUTPUT: number = 0;
// 记忆注入双封顶（与 MemoryText.MEMORY_INJECT_MAX_COUNT/MAX_CHARS 同值——本域自持同值，
// 两处同改）
const PROACTIVE_MEMORY_MAX_COUNT: number = 30;
const PROACTIVE_MEMORY_MAX_CHARS: number = 2000;
// 退避重试（MemoryGen 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次，仅可重试状态码
const MAX_PROACTIVE_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;
const MS_PER_HOUR: number = 3_600_000;

// ── 持久与运行态键（persistProp 注册在 EntryAbility.onWindowStageCreate 回调坑17 区，
//    插入位置 = 全部既有 persistProp 之后、PREF_LOADED_KEY 置 1 之前——该键是「持久键
//    注册完毕」闸信号；四枚持久键已外迁 ./ProactiveConfig，ToolPref / ProactivePage /
//    EntryAbility 三处消费方直引叶子；SENT_AT 进 AppPreferences 排除表〔与使用痕迹
//    四键同族〕；APP_FOREGROUND_KEY 非持久）──
// 发送时刻滚动数组（毫秒时间戳升序；★为什么是数组：每日上限可调后单时间戳无法算当日
// 已发数——一键兼两用：冷却判据 = now - max(list) ≥ 间隔档；当日计数 = list 内
// toLocalDayKey === 今天 的条数。写入后滚动裁到最近 KEEP 条〔有界红线〕）
export const PROACTIVE_SENT_AT_KEY: string = 'proactiveSentAt';
// 滚动保留条数（= 每日档最大值：上限调小旧时间戳边界自然正确，调大有历史可数）
const PROACTIVE_SENT_AT_KEEP: number =
  PROACTIVE_DAILY_LIMIT_OPTIONS[PROACTIVE_DAILY_LIMIT_OPTIONS.length - 1];
// 应用前台运行态键（非持久，勿 persistProp——assert-proactive 钉在案）
export const APP_FOREGROUND_KEY: string = 'appForeground';
// ── 呈现层三键 ──
// 未读键已迁零 import 叶子 ./AppBroadcastKeys（消费方 ChatSessionList 在 components 侧，
// 定义位中性化消除反向依赖）；键名与语义逐字不变。
// 横幅驱动键（运行态非持久，勿 persistProp）：值 = 载荷 JSON 串（convId/name/text +
// 自增 seq——序号保证同内容重复横幅也触发 @Watch），'' = 无横幅；消费方 = ProactiveBanner
// @StorageProp @Watch——键变即重挂（后到覆盖前条不排队）；切后台期间残留属已知限制
//（回前台重挂重新计时）
export const PROACTIVE_BANNER_KEY: string = 'proactiveBanner';
// 横幅点击直达命令键（运行态非持久）：值 = convId + '#' + 自增序号（序号保证同会话重复
// 命令也触发 @Watch）；发布方 = ProactiveBanner 点击，消费方 = HomeNavigation @Watch →
// openSession（命令键同族范式）
export const PROACTIVE_OPEN_CMD_KEY: string = 'proactiveOpenCmd';

// 待排检查的 setTimeout 句柄（重排前必清旧——成对释放红线；到点自清 null）
let checkTimer: number | null = null;
// 检查在途标记（防 onForeground 高频重入双跑全链）
let checkRunning: boolean = false;
// 冷启动首拍挂起标记：onForeground 首拍通常早于 loadContent 回调（persistProp 注册区
// ——坑17 落位），总开关键尚未注册，直读会把开着的开关误判为关吞掉首拍；闸未放行时
// 置位挂起，notifyProactiveKeysRegistered 放行后补排，放行前再次回前台幂等置位。
// loadContent 失败路径（err.code 早退）永不放行 = 标志随进程悬置：页面未加载应用不可
// 用、排程语义无损——无残留定时器无泄漏面
let pendingForegroundSchedule: boolean = false;
// 提示词解析域：单实例全程串行复用（load 是纯 DB 解析链，组件无关；禁 new 多实例）。
// ★ 惰性构建（勿搬回模块顶层 const）：顶层构造要求「本模块体求值完」——本域顶层另有
// 派生表达式，模块级构造会把求值序变成前置条件，易重演顶层读未初始化绑定的坑50 家族
//（进页/启动 JsError 闪退）；原 import 环已解散，惰性构建仍保留防回游
let promptStateCache: ChatPromptState | null = null;
function promptState(): ChatPromptState {
  if (promptStateCache === null) {
    promptStateCache = new ChatPromptState();
  }
  return promptStateCache;
}

// 组装中间形态（与 RequestInject.InjectChatMessage 同构：role/content 两必填字段，结构
// 兼容直穿 composeSendMessages/appendSystemBlock——后者未导出，同构类型直穿是
// ChatSendCtrl 既有先例；序列化只消费 role/content）
interface ProactiveHistoryMsg {
  role: string;
  content: string;
}

// 归属助手载体（resolveProactiveOwner 产出——建新会话形态下无目标会话，横幅显示名 =
// owner.name）；memoryScope 随行携带——记忆块选库判据（'assistant' = 该助手自己的库，
// 'global' = 全局库），与注入/沉淀链同口径
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

// 生效每日最多档（UI 滑轨限定 1~10 连续域；脏持久值回默认 1——守卫③读键非写死）
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

// 生效静默期上限档（分钟；UI 滑轨限定八档非等距，脏持久值回默认 5；白名单兜底同上）
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

// 发送时刻数组现读（缺省回 []——从未发过）
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

// 压入发送时刻并滚动裁剪（升序保留最近 KEEP 条——数据有界红线）
function pushSentAt(at: number): void {
  const list: number[] = sentAtList();
  list.push(at);
  while (list.length > PROACTIVE_SENT_AT_KEEP) {
    list.shift();
  }
  AppStorage.setOrCreate<number[]>(PROACTIVE_SENT_AT_KEY, list);
}

// ── 呈现层载荷与命令键工具（写侧 = 本域落库尾段与 ProactiveBanner 点击，读侧 =
//    ProactiveBanner / HomeNavigation——分隔符与 JSON 结构单源在本域）──

// 横幅载荷（单键 JSON 串原子更新，防多键竞态半态；解析侧容错回 null = 不显示）。
// seq = 进程级自增序号——@Watch 只在值变化时回调，7 秒自动收起后键仍持旧值，同内容
// 重复横幅无序号会写同串静默吞掉
export interface ProactiveBannerPayload {
  convId: string;
  name: string;
  text: string;
  seq: number;
}

// 序列化（助手名 + 首行截断 + 自增 seq：读前值 +1，脏值回 0 重计——键非持久，进程内恒递增）
export function toBannerPayload(convId: string, name: string, text: string): string {
  const prev: ProactiveBannerPayload | null =
    parseBannerPayload(AppStorage.get<string>(PROACTIVE_BANNER_KEY) ?? '');
  const prevSeq: number = prev !== null ? prev.seq : 0;
  const payload: ProactiveBannerPayload =
    { convId: convId, name: name, text: text, seq: prevSeq + 1 };
  return JSON.stringify(payload);
}

// 解析（ProactiveBanner 消费 + 序号自增读前值；容错：空串/坏 JSON/字段缺失或类型不符
// 回 null——缺序号的载荷不显示）
export function parseBannerPayload(raw: string): ProactiveBannerPayload | null {
  if (raw === '') {
    return null;
  }
  try {
    const parsed: ProactiveBannerPayload = JSON.parse(raw) as ProactiveBannerPayload;
    if (typeof parsed.convId !== 'string' || typeof parsed.name !== 'string' ||
      typeof parsed.text !== 'string' || typeof parsed.seq !== 'number') {
      return null;
    }
    return parsed;
  } catch (e) {
    return null;
  }
}

// 定长截断的安全切点（代理对防护）：emoji 等增补平面字符占两码元，substring 按码元
// 硬切会留下孤立代理字符上屏乱码——照 SkillText.safeCutIndex 口径本地一份（不为小
// 函数扩 import 面）
function safeProactiveCut(text: string, max: number): number {
  if (text.length <= max) {
    return text.length;
  }
  const last: number = text.charCodeAt(max - 1);
  return (last >= 0xD800 && last <= 0xDBFF) ? max - 1 : max;
}

// 横幅首行截断（首行 + 按字符截断 + 省略号；渲染侧 Text maxLines(1) 再兜底）
const PROACTIVE_BANNER_PREVIEW_MAX: number = 50;
function toBannerPreview(text: string): string {
  const firstLine: string = text.split('\n')[0];
  return firstLine.length > PROACTIVE_BANNER_PREVIEW_MAX ?
    firstLine.substring(0, safeProactiveCut(firstLine, PROACTIVE_BANNER_PREVIEW_MAX)) + '…' :
    firstLine;
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
// PREF_LOADED_KEY 未放行（首拍早于 persistProp 注册区）置挂起标记即返，已放行清标记
// 走总开关早退后排程；开关关闭即时生效由 cancelProactiveSchedule 承接
export function onAppForeground(): void {
  if ((AppStorage.get<number>(PREF_LOADED_KEY) ?? 0) !== 1) {
    pendingForegroundSchedule = true;
    hilog.info(DOMAIN, TAG, '偏好键未注册完毕（冷启动首拍），主动消息排程挂起待闸放行');
    return;
  }
  pendingForegroundSchedule = false;
  scheduleProactiveIfEnabled();
}

// 冷启动闸放行通知（loadContent 回调各键 persistProp 注册完毕后调用）：有挂起的首拍
// 才补排，无挂起（热启动/回调先于 onForeground 的极端序）幂等即返
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

// 清已排检查（开关行关闭时调——定时器不残留；在途请求不中断：已扣费请求完成仍落库，
// 重试路径守卫全重查——开关已关则①拦下）
export function cancelProactiveSchedule(): void {
  if (checkTimer !== null) {
    clearTimeout(checkTimer);
    checkTimer = null;
    hilog.info(DOMAIN, TAG, '主动消息排程已取消');
  }
}

// 排一次检查：冷却未过 → 排到冷却期满的时刻；已过 → 排随机静默期 1 分钟至用户档上限。
// 到点应用已后台则守卫②拦下（本轮流失，下次回前台重排）
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
    // 随机静默期窗口 = 写死下限 1 分钟至用户档上限（resolveQuietMaxMinutes）；span 恒
    // ≥ 0（档位域最小 1 = 下限，取 1 即固定 1 分钟）。随机化时机全由本档承担，冷却判据
    // 用整档不另抖
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

// 守卫序 + 组装 + 发送（attempt 从 0 起；retryable 失败经 sleep 退避后递归重入——守卫
// 全重查，与 MemoryGen 递归形态一致；每个返回点均 hilog 留痕，无静默落库）
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
  // ③ 每日上限（toLocalDayKey 计当日条数，上限读档用户可调；数组空 = 从未发过）
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
  // ④ 冷却间隔（距最近一次发送 ≥ 间隔档——③拦「今天发满」，此处拦「跨天未满档」；
  // max 0 = 从未发过视为已过）
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
    hilog.info(DOMAIN, TAG, '归属助手不合格（未开记忆注入或为控制台助手），本轮跳过');
    return;
  }
  // ⑥ 防打扰（最近活跃会话 2 分钟内更新 = 用户正在聊天，任何助手都不打扰——全局语义）
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
  // 组装（顺序红线见 buildProactivePrompt 注）
  const prompt: string = await buildProactivePrompt(owner, convId, resolved.modelId);
  // 末三形参：读超时与句柄回传走默认；taskLabel = 请求日志来源标签 + 失败文案前缀；
  // 思考档位与读超时组装单源 TitleApi.resolveFunctionalThinking
  const ft = resolveFunctionalThinking(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, READ_TIMEOUT_MS);
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl,
    resolved.modelId, resolved.protocol, resolved.endpoint, apiKey, prompt,
    PROACTIVE_MAX_OUTPUT, ft.readTimeoutMs, undefined, '主动消息', ft.thinking, ft.offEnabled);
  // 用量记账（HTTP 200 即已消耗 token，正文缺失也入账——MemoryGen 同口径；放在落库前，
  // 「请求成功但落库失败」不影响账本如实入账）
  if (result.status === 200) {
    logTaskUsage('proactive', convId, picked.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (!result.ok) {
    // 失败分类照 MemoryGen：网络/5xx/429 退避重试（守卫全重查），401/403/配置类不重试；
    // 终败只留痕不落任何消息（P0-1）
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
  // 空返回拦截：ok=true 只保证非空串，trim 后纯空白仍可能——视为失败不落库（防空
  // assistant 消息上屏与空横幅）
  if (result.text.trim() === '') {
    hilog.warn(DOMAIN, TAG, '主动消息返回空文本，不落库');
    return;
  }
  // 落库（bornGraphConversation 出生即 graph：单事务 = 建行含归属助手绑定 + 空分支 +
  // 置 migrateState/activeBranchId）：①出生 ②prepareRun 无用户输入形态（userContent=''
  // ——不建 user 节点，首条即 assistant）③commitRunUnit 落首条 assistant 节点（seq 由
  // 命令内铸造）④finishRun 收终态。任一步失败 = 本轮放弃不落消息（fail-closed，P0-1；
  // 出生失败行已建但零消息，sweepEmptyConversations 会清空行）。行时间走单调分配器
  //（sentAt 兼作冷却基准——分配器值 ≈ now 且单调，冷却判据与日键计数语义不变）
  const sentAt: number = nextRowCreatedAt();
  const branchId: string = await bornGraphConversation(convId, owner.assistantId, '', null);
  if (branchId === '') {
    hilog.warn(DOMAIN, TAG, '主动消息会话出生失败（行已在或事务失败），本轮放弃不落消息');
    return;
  }
  const runId: string = nextMessageId('run');
  await prepareRun(sharedRdbStore(), {
    runId: runId,
    conversationId: convId,
    branchId: branchId,
    assistantId: owner.assistantId,
    userContent: '',
    origin: ORIGIN_SEND,
    now: sentAt
  });
  const committed: boolean = await commitRunUnit(sharedRdbStore(), {
    runId: runId,
    expectedRevision: 0,
    checkpoint: '',
    output: { content: result.text, reasoning: '', role: 'assistant', stepIndex: 1,
      nodeStatus: 'done', updateNodeId: '',
      // runStatus 显式化（缺省即 RUNNING——此处恒 running，语义零变化）
      runStatus: RUN_STATUS_RUNNING }, // CommitUnitOutput 形参（插行 done + 更新路径关）
    now: nextRowCreatedAt(),
    origin: ORIGIN_SEND
  });
  if (!committed) {
    hilog.warn(DOMAIN, TAG, '主动消息节点提交冲突（revision 不符），本轮放弃');
    return;
  }
  await finishRun(sharedRdbStore(), {
    runId: runId,
    finalStatus: RUN_STATUS_FINISHED,
    diagnosticContent: '',
    now: Date.now()
  });
  // 会话标题 = 首句截断（titleSource='' 占位态——用户后续发言时标题链可再升级；20 字符
  // 省略号惯例，本域自持）
  await setConversationTitle(convId, toProactiveTitle(result.text), '');
  // 会话列表刷新广播（呈现面=列表；会话页恰好开着不当场自动上屏属预期——§1.2 勘误 3）
  bumpSessionListReload();
  // 压入发送时刻（滚动裁剪——数据有界）
  pushSentAt(sentAt);
  // 呈现层两键：未读红点（进会话页 onPageShown 清）+ 横幅（助手名 + 首行截断；前台
  // 守卫②保证落库恒在前台——切后台竞态下键残留属已知限制，回前台重挂重新计时）
  AppStorage.setOrCreate<string>(PROACTIVE_UNREAD_CONV_KEY, convId);
  AppStorage.setOrCreate<string>(PROACTIVE_BANNER_KEY, toBannerPayload(
    convId, owner.assistantName, toBannerPreview(result.text)));
  hilog.info(DOMAIN, TAG, '主动消息已落库新会话 conv=%{public}s', convId);
}

// 归属助手解析（★建新会话形态「归属 = 当前选择的助手」）：ACTIVE_ASSISTANT_KEY 读当前
// 助手 → 行删/键空回退内置默认助手（发送链「全局默认」兜底同口径）→ memoryInject
// 判定（关 = 不在其名下发话）。不合格回 null。（原「控制台助手排除」分支已随控制台
// 合并笔退役）
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
  // （原「控制台助手排除」分支已随 2026-10-25 控制台合并笔退役）
  return { assistantId: row.id, assistantName: row.name, memoryScope: row.memoryScope };
}

// 防打扰判据（守卫⑥）：全助手集查最近活跃会话（updatedAt 降序首行——懒建语义下
// updatedAt 随消息 touch 维护 ≈ 最新消息时刻），空表回 0 = 无会话不打扰
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
// 换行在规整时折叠）
const PROACTIVE_TITLE_MAX_CHARS: number = 20;
function toProactiveTitle(text: string): string {
  const squeezed: string = text.replace(/\s+/g, ' ').trim();
  return squeezed.length > PROACTIVE_TITLE_MAX_CHARS ?
    squeezed.substring(0, safeProactiveCut(squeezed, PROACTIVE_TITLE_MAX_CHARS)) + '…' :
    squeezed;
}

// 请求组装（★顺序红线：composeSendMessages → 记忆块 → 场景段——appendSystemMemory
// 必须在 composeSendMessages 之后，提前调用会把系统提示词吞掉〔其 system 分支遇已含
// system 整体跳过〕，RequestInject 注释与断言族互证）：★ 新会话零历史（决明拍板
// 「只靠长期记忆」）——历史恒空数组，composeSendMessages 的 system 注入分支照常产出
// 提示词位；ChatPromptState 同链 load + applyVariables（变量替换取当下时刻；load 新 id
// 无行 → effectiveAssistantId = 当前助手，与落库归属同源）→ 记忆块并 system 位 →
// 场景段并 system 尾 → 序列化单串
async function buildProactivePrompt(owner: ProactiveOwner, convId: string,
  modelId: string): Promise<string> {
  const history: ProactiveHistoryMsg[] = [];
  const state: ChatPromptState = promptState();
  await state.load(convId);
  const config: PromptInjectConfig | null =
    state.applyVariables(state.config(), modelId);
  const composed: ProactiveHistoryMsg[] = composeSendMessages(history, config);
  // appendSystemMemory 薄转出改直调 appendSystemBlock（不带尾段标记——记忆块属稳定段，
  // 形制等价零变化）
  const withMemory: ProactiveHistoryMsg[] =
    appendSystemBlock(composed, await buildProactiveMemoryBlock(owner));
  const withScene: ProactiveHistoryMsg[] =
    appendSystemScene(withMemory, buildSceneSection(Date.now()));
  return toProactivePrompt(withScene);
}

// 记忆块（发送链同口径：记忆总开关关/库空 → ''（appendSystemBlock 对空串原样返回零
// 回归）；30 条/2000 字双封顶同值）。★ 按归属助手作用域选库——'assistant' = 该助手
// 自己的库（queryAssistantMemories），'global' = 全局库（queryMemories）；与发送链/
// 沉淀链/工具链同源同口径（ownerId 空 = 全局兜底）
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

// 场景段（当前本地时间 + 主动开启新对话约束；「不要复述本段场景描述」防模型把时间
// 念出来）
function buildSceneSection(now: number): string {
  return '当前时间是 ' + formatLocalTime(now) +
    '。请以助手身份主动开启一段新对话，说一两句自然的话，不要复述本段场景描述。';
}

// 场景段并入 system 尾部（首条 system 合并 content 尾部，无 system 首位插入——连续
// 两条 system 会撞 Anthropic/Gemini 交替约束，故必合并不另插）
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

// 组装列表 → 单串 prompt（requestTitleText 传输层吃单串——见文件头「请求形态」注）：
// system 消息按序作前导段，user/assistant 以「用户:/助手:」前缀展平为对话记录段
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
