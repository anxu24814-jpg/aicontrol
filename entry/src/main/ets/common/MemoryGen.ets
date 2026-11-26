// 记忆提取服务（照 TitleGen 形制）：进程级独立域——顶层函数模块，不持页面/组件引用、不触
// UI，全吞错误 hilog 留痕，广播刷新（MEMORY_LIST_TICK_KEY）；本域自身零 toast——手动链把
// 结果对象（MemorySinkResult）回传记忆页，由页面出提示（原手动链返回 void，「一条没整理出」
// 与「请求失败」在界面上无从区分——决明驱动修正）。
// · 触发两链：自动 = ChatPage.aboutToDisappear 退出会话 fire-and-forget 一行
//   sinkMemoryForConversation（返回值丢弃 = 后台整理不打扰）；手动 = 记忆页「立即整理」
//   sinkMemoryNow（用户显式动作，守卫放宽——不查自动整理开关与助手沉淀开关，总开关关仍
//   不可用；返回整理结果六态，页面据此 toast）。
// · 守卫序（任一不满足即返回，本域不 toast）：dbReady → 总开关 →（自动链）自动整理开关 →
//  （自动链）归属助手 memorySink → 提取模型（★ 记忆两键未配置 = 功能未启用不整理，与标题
//   生成同口径，**不回退标题模型**——决明指令）→ 消息不足 2 条 → in-flight 集（防同会话并发
//   重复）。★ 2026-11-17 整体退役加密会话笔：原「会话 locked 不沉淀」守卫随功能退役删除
//  （加密会话与普通会话同权，v66 迁移已清零存量标记）。
// · 输入：readRecentRows（路径尾部窗口路由读）过滤 user/assistant 且内容非空，每条截 500，
//   总字符上限 6000 超出头尾都保（头 2000 + 省略标记 + 尾补足），tool 行剔除（纯函数在
//   MemoryText）。
// · 请求带去重清单（P1-1）：库内现有记忆 ≤120 条 / 6000 字附在渲染产物之后，让模型跳过
//   语义等价条目（敏感命中条目不外发）。
// · 输出上限不设（MEMORY_MAX_OUTPUT = 0 = 不发 max_tokens）：决明拍板「不设思考预算上限，
//   让模型先多思考，正文靠提示词约束」；正文长度由提示词 + parseMemoryLines 截断兜底
//  （两链曾全灭的真实根因是非流式请求残留 stream_options 被 400 拒〔已修〕，非本预算）。
// · 请求：复用 TitleApi.requestTitleText（非流式小任务通道——函数名含 Title 但语义通用，
//   不改名：改名牵动 TitleGen 与断言收益为零）；端点验证复用 resolveTitleEndpoint 导出。
// · 失败分类照 TitleGen：网络/5xx/429 退避 2/4/8 秒最多 3 次；401/403/配置类不重试。
// · 写库：parseMemoryLines（编号剥离/敏感过滤/去重/截断）→ insertSinkedMemories（★ 单事务
//  「先存整库快照〔before_sink〕→ 再逐条 insert source='auto'」，失败整批回滚不留半截）；
//   库内达 MEMORY_MAX_TOTAL 跳过新增 + hilog。
// ★ 记忆按需读取笔新增「读取方式」键族（MEMORY_READ_MODE_*——'inject' 自动注入默认 /
//   'tool' 按需读取）与 search_memory 工具执行器（SearchMemoryExecutor——读全库 →
//   MemoryText 检索纯函数 → 结果文本，注册归口 ToolTypes）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isReady,
  } from './store/ChatDb';
import { readRecentRows } from './chat/ChatContextSource';
import { ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  queryConversationAssistantId } from './store/AssistantDb';
import { queryEnabledKeyIds } from './store/ProviderKeyDb';
import { loadPoolKey } from './store/KeyStore';
import { READ_TIMEOUT_MS, requestTitleText, resolveFunctionalThinking,
  TitleRequestResult } from './providers/TitleApi';
import { TitleEndpoint, resolveTitleEndpoint, isRetryable } from './TitleGen';
import { logTaskUsage } from './store/UsageStatsDb';
// ★ 落库收口为 insertSinkedMemories（单事务，见文件头）——本域不再直接调 insertMemory 族
import { broadcastMemoryList, broadcastAssistantMemoryList, insertSinkedMemories,
  MEMORY_FULL_TIP, MEMORY_MAX_TOTAL, MEMORY_SCOPE_ASSISTANT, MEMORY_SCOPE_GLOBAL, MemoryRow,
  queryAssistantMemories, queryMemories } from './store/MemoryDb';
import { buildMemoryContent, composeMemoryList, MemoryEntryItem, parseMemoryLines,
  normalizeMemoryKey, composeMemorySearchResult, splitMemoryQuery,
  MEMORY_SEARCH_NEED_QUERY_TIP, MemorySearchItem } from './MemoryText';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './providers/ToolContracts';
import { ToolExecutionContext } from './chat/MessageContracts';
import { substitutePromptVariables } from './providers/PromptVariables';

const DOMAIN: number = 0x71C2;
const TAG: string = 'MemoryGen';

// 提取提示词（内置常量 = 默认值 + 恢复默认目标，唯一真源；MEMORY_PROMPT_KEY 定制非空覆盖，
// '' = 生效内置；两占位符——{content} 渲染为对话内容，{maxItems} 由 MEMORY_EXTRACT_MAX_COUNT
// 注入〔条数解耦，治提示词与解析侧双源〕；保存校验只强制 {content}，缺 {maxItems} = 用户
// 显式去掉条数约束，解析侧上限仍兜底）。
// ★ 规则要点（各有下游依据，改前先看对应消费链）：第 8 条重要性降序 = 解析侧满 maxCount 即
// break，模型输出顺序就是淘汰顺序，降序才让「丢尾」= 丢最不重要（附带：注入块按 createdAt
// 升序渲染，最重要的天然在块首）；第 6 条一件事一条 = 客户端去重只有 normalizeMemoryKey
// 字面量相等，批内近义重复靠模板管（与库内去重清单段互补）；第 3 条不写推测 = 推断落库会
// 被当用户自述长期注入；第 1 条含长期计划与重要日期；第 2 条反事实判据「换新会话不知道
// 会不会让回答变差」；第 4 条绝对时间纪律——提取输入是消息窗口、窗口内无日期，相对时间
//（昨天/下周）落库即永久失真（配套请求头「当前日期」行，见 MEMORY_DATE_LINE_TEMPLATE；
// 第 5 条敏感清单按决明拍板保持现状不动）。
export const MEMORY_PROMPT_TEMPLATE: string =
  '我将给你一段对话内容，放在 <content> 标签块中。\n' +
  '请从中提取值得跨会话长期记住的用户稳定事实。\n' +
  '1. 值得提取的例如用户透露的身份信息、长期偏好、做事习惯、表达风格、长期目标、正在进行的长期计划与重要日期，以及对助手明确提出的要求\n' +
  '2. 忽略纯技术问答、项目细节、一次性操作指令等临时信息；判断标准是换一个新会话重新开始时，不知道这条信息会不会让回答变差，不会就不要提取\n' +
  '3. 只从用户说的话里提取，只写他明确表达过的信息，不要写推测或补充；助手的角色设定与助手的回复不算用户信息\n' +
  '4. 每条用完整的第三人称陈述句描述用户，不使用「这个」「刚才」等指回本次对话的词；时间一律写成绝对日期（如 2026 年 10 月），不使用「昨天」「下周」这类相对说法\n' +
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
// 条数占位符（条数由 MEMORY_EXTRACT_MAX_COUNT 注入，与解析侧 maxCount 同源）
export const MEMORY_PROMPT_MAX_ITEMS: string = '{maxItems}';

// 「当前日期」行：外挂式注入请求头——不占用户模板（请求期上下文不得塞回模板再渲染），
// 自定义提示词用户同样获得日期基准；渲染走 substitutePromptVariables（日期/星期格式与聊天侧
// {{date}}/{{weekday}} 同源，改格式单点改 PromptVariables）
const MEMORY_DATE_LINE_TEMPLATE: string =
  '当前日期：{{date}}（{{weekday}}）。涉及时间时请据此换算成绝对日期。';

// 记忆提取模型两键（未配置 = 功能未启用不整理，不回退标题模型——见文件头）
export const MEMORY_PROVIDER_KEY: string = 'memoryProvider';
export const MEMORY_MODEL_KEY: string = 'memoryModel';
// 提示词定制键（'' = 生效内置模板——清删式回退，内置升级自动跟随）
export const MEMORY_PROMPT_KEY: string = 'memoryPrompt';

// 生效模型纯选择（两键齐 = 取记忆模型，否则空串对 = 未启用；AppStorage 读取在 resolveMemoryModel）
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

export function pickMemoryPrompt(custom: string): string {
  return custom !== '' ? custom : MEMORY_PROMPT_TEMPLATE;
}

// 生效提示词模板单源（生成链 + 功能模型页编辑面板共用——现读，用户改完下次整理即生效）
export function resolveMemoryPromptTemplate(): string {
  return pickMemoryPrompt(AppStorage.get<string>(MEMORY_PROMPT_KEY) ?? '');
}

// 模板渲染（单遍扫描替换两占位符）：★ 禁两次 split/join 连续替换——对话内容来自用户输入
//（可含「{maxItems}」字面量），先替换的值若含后一占位符字面量会被二次替换；单遍扫描对
// 占位符顺序与内容字面量均安全。{maxItems} 缺失 = 用户显式去掉条数约束，原样输出
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

// 记忆总开关（AppStorage 持久键，默认 true）：false = 不注入不沉淀，自动整理与手动整理均
// 不可用（记忆页显示停用说明行；列表仍可查看/编辑/删除——数据管理不依赖开关）。注入侧
// 消费点 = ChatSendCtrl.buildMemoryBlock
export const MEMORY_ENABLED_KEY: string = 'memoryEnabled';
// 退出会话后自动整理开关（默认 false——用户显式开启才产生后台请求；开 = 退出会话自动
// 沉淀一次，每次一个模型请求）
export const MEMORY_AUTO_KEY: string = 'memoryAutoSink';
// 整理进行中计数（进程内态不持久化）：写点 = startSinking 起止成对（finally 兜底），读点 =
// MemoryPage「正在整理」提示（含自动链触发的后台整理）
export const MEMORY_SINKING_KEY: string = 'memorySinkingCount';

// ── 记忆读取方式 ──
// 'inject' = 自动注入（默认——发送链把记忆块拼进 system prompt 尾部）/ 'tool' = 按需读取
//（聊天链不注入，改为声明 search_memory 工具由模型按需检索；主动消息链维持注入不受本键
// 影响——拍板「主动消息内容只靠记忆」）。本键只换「注入还是检索」形态，不豁免总开关/
// 助手「注入」开关/非私密三闸。消费方 = MemoryPage 分段卡 + ChatSendCtrl；persistProp
// 注册在 EntryAbility 记忆域键区
export const MEMORY_READ_MODE_KEY: string = 'memoryReadMode';
export const MEMORY_READ_MODE_INJECT: string = 'inject';
export const MEMORY_READ_MODE_TOOL: string = 'tool';
export const MEMORY_READ_MODE_DEFAULT: string = MEMORY_READ_MODE_INJECT;

// 生效读取方式纯选择（仅 'tool' 视为按需读取，脏值/空值一律回 inject——存量零漂移）
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

// ── 记忆工具作用域中转键——★ **已退役**（现行通道 = ToolExecutionContext.memoryScopeAssistantId
//    随链显式携带，接纳时一次快照、执行器只读上下文）──
// 键位保留仅作兼容，**全仓零读写**——勿按现役口径新增 AppStorage 读写
export const MEMORY_EXEC_ASSISTANT_KEY: string = 'memoryExecAssistantId';

// ── 手动链整理结果 ──
// 六态 = 记忆页出提示的唯一依据（文案映射单源 = memorySinkToastText；本域只报事实不出 UI）：
// · inserted——本次新增 N 条（count 有意义）
// · none——没整理出条目（模型答「无」/ 全被敏感过滤与去重丢掉 / 会话不足 2 条，三路同归
//   此态——对用户都是「没有记忆产生」，同一句提示）
// · limit——库内已达 MEMORY_MAX_TOTAL（有界红线；与「＋」新建键共用一句提示）
// · config——提取模型不可用（两键未配置 / 服务商停用 / 模型停用 / Key 池空 / 明文缺失）
// · failed——本次整理没能完成（请求重试耗尽、异常终止）
// · skipped——守卫未放行且用户无事可做（在途重复、库态未就绪、自动链助手沉淀
//   开关），页面保持沉默（弹了是噪音）
// ★ 六态全走返回值不借 reject：调用方一次 then 拿结果
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

// 库满提示（单源：「＋」新建键上限拦截与「立即整理」两处同一句）。★ 定义在 MemoryDb
//（存储域满额写入闸同需此句，而 MemoryDb 不得反向引本件——坑50 零环），此处 import 后
// 再出口，本域与既有消费面的 import 路径零变化
export { MEMORY_FULL_TIP };

// 结果 → 用户提示文案（纯函数单源；'' = 不出提示）。除 skipped 外每态都有回声——整理出
// 东西报条数、没整理出也说一声（原静默让用户以为没反应）、库满与模型失效给可操作下一步、
// 失败如实报。skipped 沉默 = 用户无事可做，弹了是噪音。★ failed 文案不写「请求失败」——
// 该态同时承载重试耗尽与异常终止（含写库抛错），且写库在单事务内失败即整批回滚不留半截
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

// 去重清单（P1-1）：库内现有记忆随提取请求带给模型，让其跳过语义等价条目；条数/字符双封顶
//（库上限 200 条全量太重；120/6000 自 50/3000 扩面——清单只带最近 50 条时更早的近义重复
// 模型看不见、照提照落库）。★ 三常量 export 供 MemoryImport 域复用（导入整理与自动整理
// 面对同一件事，各写一份口径必然漂移）；本域只外借常量，**导入链不并入本域**
export const MEMORY_DEDUP_MAX_COUNT: number = 120;
export const MEMORY_DEDUP_MAX_CHARS: number = 6000;
// 清单段内标记（★ 不进用户模板——MEMORY_PROMPT_* 前缀属模板占位符家族；同 export 供导入链
// 拼清单段，避免其在导入域复写 '{memories}' 字面量造成第二份来源）
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

// 自动链入口（ChatPage.aboutToDisappear 一行 fire-and-forget；全吞错误不 reject，返回值
// 有意丢弃——后台整理不打扰，结果提示只服务手动链）
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
// 动作终胜），总开关关仍不可用。返回 Promise = 全链结果对象（失败不 reject 落 failed 态）
//——调用页据此重拉列表 + 出提示。第二参 targetLibraryId = 落库目标入口库（全局库页传
// MEMORY_SCOPE_GLOBAL 或助手库页传助手 id；产物库恒等于入口库，不走自动链的归属分派——
// 入口在哪个库整理就进哪个库）
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

// 统一起跑（in-flight 闸 + 全吞错误包装；返回全链结果）；manualTarget 仅手动链消费
//（自动链恒 ''，目标库由会话归属 scope 分派）
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

// 主流程（attempt 从 0 起；retryable 失败经 setTimeout 退避后递归重入——守卫全重查）。
// 每个返回点都显式给态（六态见 memorySinkToastText 区）；manualTarget = 手动链目标库
async function runMemorySinking(conversationId: string, attempt: number,
  manual: boolean, manualTarget: string): Promise<MemorySinkResult> {
  if (!isReady()) {
    return buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0); // dbReady 守卫（调用侧已判——竞态窗口内库态不假定）
  }
  // 归属助手解析（自动链守卫 + 目标库分派两用，统一查一次；行 ''〔存量未绑定〕= 默认助手）
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
      // 助手已删（归属恒有默认兜底，null = 查询异常放弃）或显式关沉淀
      return buildSinkResult(MEMORY_SINK_STATUS_SKIPPED, 0);
    }
    // （原「控制台归属不自动沉淀」分支已随控制台合并笔退役——控制台助手整体退役后归属判据失去对象）
  }
  // 目标库分派：手动链 = 入口库（见 sinkMemoryNow 注）；自动链 = 会话归属助手作用域分派
  //（'assistant' = 该助手库；'global' 或助手行不在 = 全局库）
  const targetAssistantId: string = manual ?
    (manualTarget === MEMORY_SCOPE_GLOBAL ? '' : manualTarget) :
    (owner !== null && owner.memoryScope === MEMORY_SCOPE_ASSISTANT ? owner.id : '');
  // 提取模型（两键未配置 = 未启用，见文件头；此处 config 态兜「面板打开后模型被清空」的
  // 竞态，页面同一句提示）
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
// 三态路由读：记忆沉淀读当前路径窗口（graph 会话按路径读）
  const content: string = buildMemoryContent(await readRecentRows(conversationId));
  if (content === '') {
    // 无可整理内容（空会话竞态 / 不足 2 条），零请求必要；★ 归 none 态——对用户就是
    //「没有记忆产生」
    hilog.info(DOMAIN, TAG, '会话可整理内容不足，跳过请求 conv=%{public}s', conversationId);
    return buildSinkResult(MEMORY_SINK_STATUS_NONE, 0);
  }
  // 库内上限守卫（有界红线——达上限跳过新增；按目标库读，助手库独立计数同口径）
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
  // 提示词渲染（单遍扫描两占位符；生效模板现读，改完下次整理即生效）+「当前日期」行前置
  //（外挂不占模板，见 MEMORY_DATE_LINE_TEMPLATE）
  let prompt: string = substitutePromptVariables(MEMORY_DATE_LINE_TEMPLATE, '', '', '',
    new Date()) + '\n\n' + renderMemoryPrompt(resolveMemoryPromptTemplate(), content,
    MEMORY_EXTRACT_MAX_COUNT);
  // 去重清单追加（P1-1）：★ 必须在渲染产物之后拼——清单含用户记忆文本，塞回模板再渲染
  // 等于给不可信内容开二次替换面；空清单不拼段（零回归）
  const list: string = composeMemoryList(items, MEMORY_DEDUP_MAX_COUNT, MEMORY_DEDUP_MAX_CHARS);
  if (list !== '') {
    prompt += MEMORY_DEDUP_SECTION.split(MEMORY_DEDUP_LIST_MARK).join(list);
  }
  // taskLabel '记忆' = 请求日志来源标签 + 失败文案前缀（不传即错报「标题」）；思考档位与读
  // 超时走 resolveFunctionalThinking 组装单源（''/off 档与原值恒等零回归）
  const ft = resolveFunctionalThinking(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, READ_TIMEOUT_MS);
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey, prompt, MEMORY_MAX_OUTPUT,
    ft.readTimeoutMs, undefined, '记忆', ft.thinking, ft.offEnabled);
  // 用途记账：HTTP 200 即已消耗 token——正文缺失的 200 形态也入账（决明拍板放宽）；网络
  // 错误/非 200 无 usage 不记（技术不可得）。放在解析/写库之前，「本次无值得沉淀」放弃不
  // 影响账本如实入账（purpose='memory'，conversationId = 触发会话随删会话级联删）
  if (result.status === 200) {
    logTaskUsage('memory', conversationId, picked.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (result.ok) {
    const lines: string[] = parseMemoryLines(result.text, MEMORY_EXTRACT_MAX_COUNT, existing);
    if (lines.length === 0) {
      // 模型答「无」与全被敏感过滤/去重丢掉同归 none（不是失败，只是这次没东西可沉淀）
      hilog.info(DOMAIN, TAG, '本次无值得沉淀的记忆 conv=%{public}s', conversationId);
      return buildSinkResult(MEMORY_SINK_STATUS_NONE, 0);
    }
    // 落库（单事务原语 insertSinkedMemories，见文件头）。归属标注 '' = 无归属（手动链无行 /
    // 助手已删形态）
    const assistantIdValue: string = ownerId !== null && ownerId !== '' ? ownerId : '';
    await insertSinkedMemories(
      targetAssistantId !== '' ? targetAssistantId : MEMORY_SCOPE_GLOBAL,
      lines, assistantIdValue, conversationId);
    // hilog 与两库广播原位保留（写库成功后——禁因事务化提前或后移）
    if (targetAssistantId !== '') {
      hilog.info(DOMAIN, TAG, '记忆已沉淀 %{public}d 条（助手库 %{public}s） conv=%{public}s',
        lines.length, targetAssistantId, conversationId);
      broadcastAssistantMemoryList();
    } else {
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

// ── search_memory 执行器（注册在 ToolTypes）──
// 读库（≤200 条小数据集全量内存打分）→ MemoryText 检索纯函数（切词/打分/双封顶选取）→
// 结果文本。★ 契约 = 恒 resolve 不 reject（错误走 JSON 错误信息）；端内执行零模型请求零
// 费用，不记 logTaskUsage；工具轮消耗走全局轮数上限（prefToolStepLimit）。目标库由执行
// 上下文携带（ctx.memoryScopeAssistantId 非空 = 该助手库、空 = 全局库）；四闸（总开关/
// 读取方式/助手开关/非私密）在声明层 ChatSendCtrl 把关，未声明即不可达
export class SearchMemoryExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let query: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    // 目标库分派：与 manage_memory 执行器同一判据（执行上下文显式携带）
    const targetAssistantId: string = ctx.memoryScopeAssistantId;
    const libRead: Promise<MemoryRow[]> = targetAssistantId !== '' ?
      queryAssistantMemories(targetAssistantId) : queryMemories();
    return libRead
      .then((rows: MemoryRow[]): string => {
        const items: MemorySearchItem[] = [];
        for (const row of rows) {
          items.push({ content: row.content, createdAt: row.createdAt,
            updatedAt: row.updatedAt });
        }
        // 空关键词（切分后无词）= 缺必填检索词 → error 形态（与 search_chats / search_knowledge
        // 同判据，句同源一常量禁第二份字面）。空库让位——纯函数内「记忆库为空。」在前，此处
        // 同步取其位次
        if (items.length > 0 && splitMemoryQuery(query).length === 0) {
          return JSON.stringify({ error: MEMORY_SEARCH_NEED_QUERY_TIP });
        }
        return composeMemorySearchResult(items, query);
      })
      .catch((e: Object): string => {
        hilog.warn(DOMAIN, TAG, '记忆检索读取失败：%{public}s', toolErrorText(e));
        return JSON.stringify({ error: '记忆读取失败：' + toolErrorText(e) });
      });
  }
}
