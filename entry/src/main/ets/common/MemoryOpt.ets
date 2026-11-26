// 记忆优化服务（形制照 MemoryGen——进程级独立域：顶层函数模块，不持页面/组件引用、不触
// UI，全吞错误 hilog 留痕；本域自身零 toast——prepare 的结果对象回传记忆页，由页面出提示
// 与确认弹窗）。目标 = 把已攒下的存量收拾干净（跨次近义重复合并 + 压短表述——注入窗口只
// 取前 30 条 / 2000 字，压短 = 更多不同事实挤进窗口）。★ 治不了「缺漏」：手里只有条目没有
// 对话原文，凭条目猜「漏了什么」只会产幻觉；补漏只能靠喂原文或提高提取提示词质量。
// · 两段式（人工确认）：prepareMemoryOpt = 请求 + 解析 + 校验 + 改动量闸门，产出可执行计划
//   交页面出确认弹窗；applyMemoryOpt = 用户确认后一个事务落库——用户点头前一个字不落库。
// · 只做手动触发（记忆页「优化记忆」键，无定时无后台静默）；与提取链的差别 = 不查自动整理
//   开关、不查会话，但总开关关仍不可用（记忆停用则整体停用）。
// · 模型两键：未配置 = 功能未启用，**不回退提取模型**（拍板口径——「我没配它，它却在替我
//   花钱」不可接受）；手动链由记忆页前置 toast 引导。
// · 提示词定制键：'' = 未定制 = 生效内置，清删式回退（内置模板升级自动跟随）；生效模板
//   单源 = resolveMemoryOptPromptTemplate()，优化链与编辑面板共用。
// · 请求走 TitleApi.requestTitleText + TitleGen.resolveTitleEndpoint；失败分类照 TitleGen：
//   网络/5xx/429 退避 2/4/8 秒最多 3 次，401/403/配置类不重试。
// · 费用记账复用 purpose='memory'（优化费与整理费混在一类，分不出来——观察项）；输出不设
//   max_tokens，长度靠 prompt 软约束 + 纯函数层硬闸门（单条 ≤ MEMORY_CONTENT_MAX）兜底。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isReady } from './store/ChatDb';
import { loadPoolKey } from './store/KeyStore';
import { READ_TIMEOUT_MS, requestTitleText, resolveFunctionalThinking,
  TitleRequestResult } from './providers/TitleApi';
import { isRetryable, resolveTitleEndpoint, TitleEndpoint } from './TitleGen';
import { logTaskUsage } from './store/UsageStatsDb';
import { applyAssistantMemoryOptChanges, applyMemoryOptChanges, broadcastAssistantMemoryList,
  broadcastMemoryList, MemoryRow, queryAssistantMemories, queryMemories,
  MEMORY_SCOPE_GLOBAL } from './store/MemoryDb';
import { MemoryModelPick, isMemoryEnabled } from './MemoryGen';
import {
  buildMemoryOptPlan, composeMemoryOptList, selectMemoryOptItems, MemoryOptInputItem,
  MemoryOptOutcome, MemoryOptPlan, MEMORY_OPT_STATUS_APPLIED, MEMORY_OPT_STATUS_CONFIG,
  MEMORY_OPT_STATUS_FAILED, MEMORY_OPT_STATUS_NONE, MEMORY_OPT_STATUS_READY,
  MEMORY_OPT_STATUS_SKIPPED, MEMORY_OPT_STATUS_TOO_LARGE
} from './MemoryText';

const DOMAIN: number = 0x71C3;
const TAG: string = 'MemoryOpt';

// 记忆优化模型两键（与记忆提取两键同构：未配置 = 未启用，不回退提取模型，见文件头）
export const MEMORY_OPT_PROVIDER_KEY: string = 'memoryOptProvider';
export const MEMORY_OPT_MODEL_KEY: string = 'memoryOptModel';
// 提示词定制键（'' = 生效内置模板，清删式回退——内置升级自动跟随）
export const MEMORY_OPT_PROMPT_KEY: string = 'memoryOptPrompt';

// 优化提示词（内置常量 = 默认值 + 「恢复默认」回显目标，唯一真源；开放编辑时保存校验强制
// {memories} 占位符）。三条纪律各对下游一处真实约束：序号制 + 只输出要改的条目 ↔
// parseMemoryOptLine 的白名单式应用（未提及的条目一律不动——防模型少说几条就静默删库）；
// 「合并只用于同一事实」「不得丢失或新增信息」↔ 幻觉合并风险的提示词侧缓解（纯函数层验
// 不了语义，靠提示词 + 确认弹窗）；「装不下就不要合并」↔ 字数与信息覆盖冲突时让模型让路。
export const MEMORY_OPT_PROMPT_TEMPLATE: string =
  '我将给你一份已有的长期记忆条目清单，每行以「序号. 内容」格式给出，放在 <memories> 标签块中。\n' +
  '请检查这些条目，只做两类整理：\n' +
  '一是重复的条目、同一件事被拆开写的条目，合并成一条\n' +
  '二是表述啰嗦、冗余的条目，改写得更短更清楚\n' +
  '规则：\n' +
  '1. 只处理确实需要改的条目，不需要改的条目不要出现在结果里\n' +
  '2. 合并只用于同一事实的不同说法，不同的事实不要合并\n' +
  '3. 合并后的内容必须覆盖被合并条目的全部信息，不得丢失，也不得添加原文没有的信息\n' +
  '4. 改写只能精简表述，不得改变原意，也不得增减信息\n' +
  '5. 改写后的条目不超过 60 字，合并后的条目不超过 120 字；信息装不下就不要合并这几条\n' +
  '6. 保持第三人称陈述句，不使用「这个」「刚才」等指回对话的词\n' +
  '7. 每行一条 JSON，不要编号，不要解释，也不要输出你的分析或思考过程\n' +
  '8. 没有需要整理的内容时只回复「无」\n' +
  '输出格式，targets 写要处理的条目序号，合并时写全部被合并的序号，第一个序号对应' +
  '的内容会被替换，其余条目删除：\n' +
  '{"op":"rewrite","targets":[5],"text":"改写后的内容"}\n' +
  '{"op":"merge","targets":[3,7,9],"text":"合并后的内容"}\n' +
  '\n<memories>\n' +
  '{memories}\n' +
  '</memories>';
// 输入占位符（定制模板下用 split/join 单次替换——见 renderMemoryOptPrompt）
export const MEMORY_OPT_PROMPT_MEMORIES: string = '{memories}';

// 优化输入双封顶（120 条 / 6000 字——覆盖大多数真实库且 token 可控；超出按卡片序截断，
// 提示如实告知「仅覆盖前 N 条」）
const MEMORY_OPT_MAX_COUNT: number = 120;
const MEMORY_OPT_MAX_CHARS: number = 6000;
// 输出上限（0 = 不发 max_tokens——与提取链同口径，见文件头）
const MEMORY_OPT_MAX_OUTPUT: number = 0;
// 退避重试（TitleGen/MemoryGen 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次
const MAX_MEMORY_OPT_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;

// 优化进行中计数（AppStorage 键，进程内态不持久化）：写点 = prepare 起止成对（finally
// 兜底），读点 = 记忆页「正在优化」提示行（确认弹窗期间计数已归零——那段时间等的是用户）
export const MEMORY_OPT_RUNNING_KEY: string = 'memoryOptRunningCount';

// prepare 结果（页面出确认弹窗与提示的唯一依据）：plan 非空 = status ready，页面出确认弹
// 窗；plan 空 = none/config/failed/skipped，页面按 memoryOptToastText 出提示（skipped 沉默）
export interface MemoryOptPrepare {
  outcome: MemoryOptOutcome;
  plan: MemoryOptPlan | null;
}

// 生效模型纯选择（两键齐 = 启用，否则未启用——纯函数可直跑断言）
export function pickMemoryOptModel(optProvider: string, optModel: string): MemoryModelPick {
  if (optProvider !== '' && optModel !== '') {
    return { providerId: optProvider, modelId: optModel };
  }
  return { providerId: '', modelId: '' };
}

// 生效模型单源（优化链 + 记忆页「优化记忆」前置检查共用）
export function resolveMemoryOptModel(): MemoryModelPick {
  return pickMemoryOptModel(AppStorage.get<string>(MEMORY_OPT_PROVIDER_KEY) ?? '',
    AppStorage.get<string>(MEMORY_OPT_MODEL_KEY) ?? '');
}

// 生效模板纯选择（定制非空取定制，空回内置）
export function pickMemoryOptPrompt(custom: string): string {
  return custom !== '' ? custom : MEMORY_OPT_PROMPT_TEMPLATE;
}

// 生效模板单源（优化链 + 编辑面板 + 助手工具共用；现读无缓存，改完下次优化即生效）
export function resolveMemoryOptPromptTemplate(): string {
  return pickMemoryOptPrompt(AppStorage.get<string>(MEMORY_OPT_PROMPT_KEY) ?? '');
}

// 提示词渲染（单占位符）：split/join 对可定制模板也安全——单占位符下 join 不重扫替换产物，
// 清单文本含同款字面量也不会被二次替换；两占位符并存的提取链才需单遍扫描
// （见 MemoryGen.renderMemoryPrompt）
export function renderMemoryOptPrompt(template: string, list: string): string {
  return template.split(MEMORY_OPT_PROMPT_MEMORIES).join(list);
}

// 结果构造（多处复用——字面量零散写易漏字段）
function buildOptOutcome(status: string, changed: number, merged: number, ignored: number,
  covered: number, total: number): MemoryOptOutcome {
  return { status: status, changed: changed, merged: merged, ignored: ignored,
    covered: covered, total: total };
}

// prepare 结果构造（无计划形态——守卫未放行与请求失败同形，只差 status）
function prepared(status: string): MemoryOptPrepare {
  return { outcome: buildOptOutcome(status, 0, 0, 0, 0, 0), plan: null };
}

// in-flight 闸（退避窗口内防重复触发；优化不吃会话 id，全局单闸）
let optInFlight: boolean = false;

// 计数增减（Math.max 防负——起止成对，异常路径 finally 兜底）
function bumpOptRunning(delta: number): void {
  const current: number = AppStorage.get<number>(MEMORY_OPT_RUNNING_KEY) ?? 0;
  AppStorage.setOrCreate<number>(MEMORY_OPT_RUNNING_KEY, Math.max(0, current + delta));
}

// 手动链入口（库管理页「优化记忆」键；失败不 reject，落 failed 态）：两段式第一段——只到
// 「产出计划」为止，一个字不落库。libraryId = 优化目标库（MEMORY_SCOPE_GLOBAL 或助手 id），
// 条目读取与计划落库同库；in-flight 保持全局单闸（两库并发优化无收益）
export function prepareMemoryOpt(libraryId: string): Promise<MemoryOptPrepare> {
  if (optInFlight) {
    hilog.info(DOMAIN, TAG, '优化在途，跳过本次触发');
    return Promise.resolve(prepared(MEMORY_OPT_STATUS_SKIPPED));
  }
  optInFlight = true;
  bumpOptRunning(1);
  return runPrepareMemoryOpt(0, libraryId)
    .catch((e: Object): MemoryOptPrepare => {
      hilog.error(DOMAIN, TAG, '记忆优化异常终止：%{public}s', (e as Error).message);
      return prepared(MEMORY_OPT_STATUS_FAILED);
    })
    .finally((): void => {
      optInFlight = false;
      bumpOptRunning(-1);
    });
}

// 主流程（attempt 从 0 起；retryable 失败经 setTimeout 退避后递归重入——守卫全重查）
async function runPrepareMemoryOpt(attempt: number, libraryId: string): Promise<MemoryOptPrepare> {
  if (!isReady()) {
    return prepared(MEMORY_OPT_STATUS_SKIPPED); // dbReady 守卫（竞态窗口内库态不假定）
  }
  // 总开关兜底（记忆停用 = 整体停用；记忆页键已同步禁用）
  if (!isMemoryEnabled()) {
    hilog.info(DOMAIN, TAG, '记忆功能已停用，优化跳过');
    return prepared(MEMORY_OPT_STATUS_SKIPPED);
  }
  // 优化模型两键（未配置 = 未启用；面板打开后被清空的竞态同落此处）
  const picked: MemoryModelPick = resolveMemoryOptModel();
  if (picked.providerId === '' || picked.modelId === '') {
    hilog.debug(DOMAIN, TAG, '记忆优化模型未配置，功能未启用');
    return prepared(MEMORY_OPT_STATUS_CONFIG);
  }
  const resolved: TitleEndpoint | null =
    await resolveTitleEndpoint(picked.providerId, picked.modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '记忆优化模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return prepared(MEMORY_OPT_STATUS_CONFIG);
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——TitleGen 同口径）
  const apiKey: string = await loadPoolKey(picked.providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '记忆优化 Key 明文缺失，放弃');
    return prepared(MEMORY_OPT_STATUS_CONFIG);
  }
  // 库内条目（卡片序 = 用户排定的优先级；上限 200 条自然有界）+ 双封顶选取
  // （见 selectMemoryOptItems），按目标库读
  const rows: MemoryRow[] = libraryId === MEMORY_SCOPE_GLOBAL ?
    await queryMemories() : await queryAssistantMemories(libraryId);
  if (rows.length === 0) {
    hilog.info(DOMAIN, TAG, '记忆库为空，无可优化内容');
    return prepared(MEMORY_OPT_STATUS_NONE);
  }
  const items: MemoryOptInputItem[] = [];
  for (const row of rows) {
    items.push({ id: row.id, content: row.content, createdAt: row.createdAt });
  }
  const covered: MemoryOptInputItem[] =
    selectMemoryOptItems(items, MEMORY_OPT_MAX_COUNT, MEMORY_OPT_MAX_CHARS);
  if (covered.length === 0) {
    // selectMemoryOptItems 至少保 1 条，走到这 = 全部条目命中敏感词，请求无意义
    hilog.info(DOMAIN, TAG, '可送优化的条目为空（敏感过滤后无剩余），跳过请求');
    return prepared(MEMORY_OPT_STATUS_NONE);
  }
  // 提示词渲染（生效模板现读；条目清单替换单占位符）
  const prompt: string =
    renderMemoryOptPrompt(resolveMemoryOptPromptTemplate(), composeMemoryOptList(covered));
  // taskLabel = 请求日志来源标签（不传会错报「标题」）；思考档位组装单源 TitleApi.resolveFunctionalThinking
  const ft = resolveFunctionalThinking(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, READ_TIMEOUT_MS);
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey, prompt, MEMORY_OPT_MAX_OUTPUT,
    ft.readTimeoutMs, undefined, '记忆优化', ft.thinking, ft.offEnabled);
  // 用途记账（purpose='memory'；HTTP 200 即已消耗 token——正文缺失的 200 形态也入账；
  // conversationId '' = 无归属会话，费用页按用途统计不受影响）
  if (result.status === 200) {
    logTaskUsage('memory', '', picked.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (result.ok) {
    const plan: MemoryOptPlan = buildMemoryOptPlan(result.text, covered, rows.length);
    if (plan.oversized) {
      hilog.warn(DOMAIN, TAG, '模型给出的改动超闸门（删 %{public}d 行 / 合并 %{public}d 组），整批放弃',
        plan.removed, plan.mergeGroups);
      return { outcome: buildOptOutcome(MEMORY_OPT_STATUS_TOO_LARGE, 0, 0, plan.ignored,
        plan.covered, plan.total), plan: null };
    }
    if (plan.changes.length === 0) {
      // 模型答「无」/ 建议全被丢弃 / 无变化回声 同归 none（不是失败，只是没东西可改）
      hilog.info(DOMAIN, TAG, '本次无可优化的改动（丢弃建议 %{public}d 条）', plan.ignored);
      return { outcome: buildOptOutcome(MEMORY_OPT_STATUS_NONE, 0, 0, plan.ignored,
        plan.covered, plan.total), plan: null };
    }
    hilog.info(DOMAIN, TAG, '优化建议待确认：改写 %{public}d 条 / 合并 %{public}d 组（删 %{public}d 行）',
      plan.rewrite, plan.mergeGroups, plan.removed);
    return { outcome: buildOptOutcome(MEMORY_OPT_STATUS_READY, 0, 0, plan.ignored,
      plan.covered, plan.total), plan: plan };
  }
  if (isRetryable(result.status) && attempt < MAX_MEMORY_OPT_RETRY) {
    const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, attempt + 1); // 2/4/8
    hilog.warn(DOMAIN, TAG, '优化请求失败(%{public}d)，%{public}d 秒后第 %{public}d 次重试',
      result.status, delaySeconds, attempt + 1);
    await sleep(delaySeconds * 1000);
    // 重试结果即本次结果（递归返回值原样上抛，勿吞成 void）
    return runPrepareMemoryOpt(attempt + 1, libraryId);
  }
  hilog.warn(DOMAIN, TAG, '优化请求最终失败放弃 status=%{public}d：%{public}s',
    result.status, result.errorMessage);
  return prepared(MEMORY_OPT_STATUS_FAILED);
}

// 应用计划（两段式第二段，用户确认后调用）：一个事务落库（见 MemoryDb.applyMemoryOptChanges
// / applyAssistantMemoryOptChanges），成功广播对应库列表刷新（libraryId 与 prepare 同值同库，
// 事务限库内）；落库失败 = failed（事务已回滚，零改动不产生半成品库）
export async function applyMemoryOpt(plan: MemoryOptPlan,
  libraryId: string): Promise<MemoryOptOutcome> {
  if (plan.changes.length === 0) {
    return buildOptOutcome(MEMORY_OPT_STATUS_NONE, 0, 0, plan.ignored, plan.covered, plan.total);
  }
  // 存档摘要：随快照落库，供历史页副行显示「这一版改了什么」（「·」分隔符为项目惯例）
  const snapshotNote: string = '改写 ' + plan.rewrite + ' 条 · 合并 ' + plan.mergeGroups + ' 组';
  try {
    if (libraryId === MEMORY_SCOPE_GLOBAL) {
      await applyMemoryOptChanges(plan.changes, snapshotNote);
    } else {
      await applyAssistantMemoryOptChanges(libraryId, plan.changes, snapshotNote);
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, '优化落库失败已回滚：%{public}s', (e as Error).message);
    return buildOptOutcome(MEMORY_OPT_STATUS_FAILED, 0, 0, plan.ignored, plan.covered,
      plan.total);
  }
  if (libraryId === MEMORY_SCOPE_GLOBAL) {
    broadcastMemoryList();
  } else {
    broadcastAssistantMemoryList();
  }
  // changed = 改写数 + 合并组内行数（一组 merge 动整组行，只报组数会口径失真）
  const changed: number = plan.rewrite + plan.mergeRows;
  hilog.info(DOMAIN, TAG, '记忆优化已应用：%{public}d 条受影响 / 合并 %{public}d 组',
    changed, plan.mergeGroups);
  return buildOptOutcome(MEMORY_OPT_STATUS_APPLIED, changed, plan.mergeGroups, plan.ignored,
    plan.covered, plan.total);
}

// 失败恢复型退避等待（TitleGen/MemoryGen 同款）
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}
