// 记忆导入服务（2026-09-22 记忆导入，任务书-记忆导入-20260922 §3.5；形制照 MemoryOpt——
// 进程级独立域：顶层函数模块，不持页面/组件引用、不触 UI，全吞错误 hilog 留痕，广播刷新
// 复用两库既有 tick 键；本域自身零 toast——结果对象回传导入页，由页面出提示）。
// · 干什么：把用户在别的 AI 平台（ChatGPT / Claude 等）跑出来的「关于用户的总结」粘贴回来，
//   经「记忆提取」卡所选模型整理成规范条目，用户预览确认后**整批**写进指定记忆库，写入前
//   自动留一份可整库回退的快照。
// · 为什么独立成域（宪法「新增功能域一律先拆」）：输入域与自动整理不同（外部平台文本 vs
//   本库会话记录），故提示词独立成第六槽；两段式（prepare 出条目 → 用户确认 → apply 落库）
//   与优化链同形，但多一道「事务内二次容量校验」。
// · 依赖方向（单向、无环——坑50 红线）：本域 → MemoryGen（renderMemoryPrompt / 去重段三常量
//   与标记 / resolveMemoryModel / isMemoryEnabled）、MemoryDb（两库读写 + archiveBeforeOptInTx
//   + 快照 kind + MEMORY_MAX_TOTAL / MEMORY_SCOPE_GLOBAL）、MemoryText（parseMemoryLines /
//   normalizeMemoryKey / composeMemoryList）、TitleGen（resolveTitleEndpoint / isRetryable）、
//   TitleApi（requestTitleText）、ChatDb（sharedRdbStore / isReady）、UsageStatsDb
//   （logTaskUsage）。**反向零依赖**——MemoryGen / MemoryDb / MemoryText 不得引本域，成环即
//   启动求值崩（坑50）。
// · 模型归属（决明 2026-09-22 拍板）：复用「记忆提取」两键（MEMORY_PROVIDER_KEY /
//   MEMORY_MODEL_KEY）——不新增功能模型卡、不新增第二对模型键；两键未配置 = 不可导入。
// · 提示词归属（决明 2026-09-22 拍板）：独立第六槽（输入域不同，不能与提取槽共用模板）；
//   槽四件套形制与 MemoryGen / MemoryOpt 逐处同构。
// · 记账（沿用优化链口径）：purpose='memory' 复用记忆类，conversationId 传 ''。
// · 输出上限不设（MEMORY_IMPORT_MAX_OUTPUT = 0 = 不发 max_tokens 字段）：与四链同口径，
//   正文长度由提示词 + parseMemoryLines 截断兜底。
// · 三重加固（缺一即可能落重复条目或超上限，见 applyMemoryImport 与 in-flight 闸）：
//   ①apply 侧容量在**事务内**二次校验（prepare 的容量结论不得信任）；②进程级 in-flight 单
//   布尔闸防**模型请求**并发重复触发（★ 只盖 prepare，不盖 apply——单句柄全局事务的落库在途
//   闸落在页面侧：MemoryImportPage.importing 置真即禁用落库/删除/返回三键并显「正在导入」，
//   2026-09-22 自检轮补。此处勿写成「防并发落库」——那是页面侧那道闸的职责，写在这里会让
//   后来者以为 apply 已被本闸保护）；③页面 alive 守卫（页面侧，防离开页面后静默落库——本域
//   只保证「调用即执行」，放弃语义由页面不发第二次调用承接）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { isReady, sharedRdbStore } from './store/ChatDb';
import { loadPoolKey } from './store/KeyStore';
import { requestTitleText, TitleRequestResult } from './providers/TitleApi';
import { isRetryable, resolveTitleEndpoint, TitleEndpoint } from './TitleGen';
import { logTaskUsage } from './store/UsageStatsDb';
import {
  archiveBeforeOptInTx, broadcastAssistantMemoryList, broadcastMemoryList, insertAssistantMemory,
  insertMemory, MEMORY_MAX_TOTAL, MEMORY_SCOPE_GLOBAL, MEMORY_SNAPSHOT_KIND_IMPORT,
  MemoryRow, queryAssistantMemories, queryMemories
} from './store/MemoryDb';
import {
  isMemoryEnabled, MemoryModelPick, MEMORY_DEDUP_LIST_MARK, MEMORY_DEDUP_MAX_CHARS,
  MEMORY_DEDUP_MAX_COUNT, MEMORY_DEDUP_SECTION, renderMemoryPrompt, resolveMemoryModel
} from './MemoryGen';
import {
  composeMemoryList, MemoryEntryItem, normalizeMemoryKey, parseMemoryLines
} from './MemoryText';

const DOMAIN: number = 0x71C4;
const TAG: string = 'MemoryImport';

// ── 导出侧提示词（给外部平台用）──
// ★ 这段文字**不进任何模型请求**，只在导入页被「复制」给用户，用户拿去外部平台运行。故不做
// 提示词槽、不做编辑入口、不属于功能模型页——它是给别的 AI 的指令文本，改它要重新教用户操作。
// 与参考形态（2026-09-22 决明提供的第三方 App 形态）有三处**有意的偏差，勿改回**：
// ①第 4 类由「标注日期的事件、项目和计划：近期重要活动的记录」收窄为「长期项目与计划，已
//   结束的不写」——本库条目要长期注入做背景，带日期的一次性事件会随时间变噪音；
// ②原「用户的名字是<name>。 - 证据：… 日期：…」的多行富结构改为一行一条、证据与日期折进
//   句内——本库入库契约是「一行一条第三人称陈述句」（parseMemoryLines 逐行清洗），富结构
//   直接粘回来会让类别标题行与证据行各自变成垃圾条目；
// ③删去原提示词的「希望摘要能帮到……」式收尾与星号加粗（外部平台输出直连粘贴框，装饰性
//   符号徒增解析噪音）。
export const MEMORY_IMPORT_EXTERNAL_PROMPT: string =
  '帮我把一个 AI 助理中的上下文导入到另一个 AI 助理。你的任务是回顾我们过去的对话，总结你对我的了解。\n' +
  '\n' +
  '在输出中，请避免使用第一人称代词（我、我的）和第二人称代词（你、你的）。请改用「用户」或使用中性词语来指代你了解到的个人。\n' +
  '\n' +
  '尽可能保留用户的原话，尤其是指令和偏好方面的内容。\n' +
  '\n' +
  '类别（按此顺序输出）：\n' +
  '1. 人口统计信息：常用名字、职业、教育程度和常住地。\n' +
  '2. 兴趣和偏好：持续积极的投入（不只是拥有某个物品或单次购买）。\n' +
  '3. 关系：已确认的长期关系。\n' +
  '4. 长期项目与计划：仍在进行的项目、计划与目标，已经结束的不写。\n' +
  '5. 指令：用户明确要求你今后遵循的规则，包括必须做到的事项、绝对禁止的事项以及行为纠正。仅包含已存储记忆中的规则，不包含本次对话中的规则。\n' +
  '\n' +
  '格式：\n' +
  '按上述类别分为带标签的区块，区块标题单独占一行，写成【类别名】。\n' +
  '每个区块内每条事实占一行，不要编号，不要列表符号。\n' +
  '书写规则：\n' +
  '- 用「用户」指代被总结的人，禁止出现第一人称与第二人称代词。\n' +
  '- 每条用完整的第三人称陈述句，不超过 60 字。\n' +
  '- 证据折进句内：用户的原话用引号写在句中，例如 用户要求回答先给结论（原话「先给结论再展开」）。\n' +
  '- 时间信息写进句内，例如 用户在 2026 年 9 月开始做鸿蒙开发。不要写独立的日期行。\n' +
  '- 一条只写一件事，不同的长期事实分开写。\n' +
  '- 某个类别没有内容时，该区块写「无」。\n' +
  '\n' +
  '输出：\n' +
  '- 最终摘要整体放在一个文本块内。';

// ── 导入解析提示词（第六槽）──
// 定制键（'' = 未定制 = 生效内置 MEMORY_IMPORT_PROMPT_TEMPLATE——清删式回退，内置模板后续
// 升级自动跟随；语义照 MemoryGen.MEMORY_PROMPT_KEY / MemoryOpt.MEMORY_OPT_PROMPT_KEY）
export const MEMORY_IMPORT_PROMPT_KEY: string = 'memoryImportPrompt';
// 占位符（两枚：{content} 插待整理文本、{maxItems} 由 MEMORY_IMPORT_MAX_COUNT 渲染注入——
// 条数解耦，治提示词与解析侧双源；保存校验只强制 {content}，缺 {maxItems} = 用户显式去掉
// 条数约束，解析侧上限仍兜底）
export const MEMORY_IMPORT_PROMPT_CONTENT: string = '{content}';
export const MEMORY_IMPORT_PROMPT_MAX_ITEMS: string = '{maxItems}';

// 内置模板（默认值 + 「恢复默认」回显目标，唯一真源）：11 条规则全对着下游一处真实约束——
// 第 1 条结构信息丢弃 ↔ parseMemoryLines 逐行清洗（外部输出的类别标题/编号/证据标签/日期
// 标记不作预处理，直接在提示词侧消化，见任务书 §1.4 红线 4）；第 5 条批内合并 ↔ 客户端
// 跨条目去重只有字面量归一（近义重复条会真的落库并各占一条注入名额）；第 8 条条数上限 ↔
// {maxItems} 与解析侧 maxCount 同源；第 9 条重要性降序 ↔ 解析侧满 maxCount 即 break（丢尾 =
// 丢最不重要）；第 10 条「无」↔ parseMemoryLines 的 isNoneAnswer（三路同归 none 态）
export const MEMORY_IMPORT_PROMPT_TEMPLATE: string =
  '我将给你一段文本，放在 <content> 标签块中。它可能来自另一个 AI 平台对用户的记忆总结，格式不固定，可能含类别标题、编号、证据说明、日期标记或第一人称表述。\n' +
  '请把它整理成可以长期保存的记忆条目。\n' +
  '1. 丢掉类别标题、编号、证据标签、日期标记等结构信息，只保留事实本身\n' +
  '2. 每条用完整的第三人称陈述句描述用户，不使用「这个」「刚才」等指代\n' +
  '3. 用户的原话可以保留在引号内\n' +
  '4. 时间信息能自然写进句内就写进去，写不进去就丢掉\n' +
  '5. 同一件事的重复说法合并成一条，不同的长期事实分开写\n' +
  '6. 忽略纯技术问答、项目细节、一次性操作等临时信息\n' +
  '7. 忽略口令、密钥、证件号、银行卡号、住址等敏感信息，不要输出\n' +
  '8. 每行一条，每条不超过 60 字，最多 {maxItems} 条\n' +
  '9. 按重要性从高到低排列，最重要的放在最前面\n' +
  '10. 没有可整理的内容时只回复「无」\n' +
  '11. 只输出条目本身，不要编号，不要解释，也不要输出你的分析或思考过程\n' +
  '\n' +
  '<content>\n' +
  '{content}\n' +
  '</content>';

// 生效提示词模板纯选择（定制非空取定制，空回内置——照 MemoryGen.pickMemoryPrompt 形制）
export function pickMemoryImportPrompt(custom: string): string {
  return custom !== '' ? custom : MEMORY_IMPORT_PROMPT_TEMPLATE;
}

// 生效提示词模板单源（导入链 + 功能模型页编辑面板 + 控制台助手工具共用——现读，用户改完
// 下次导入即生效，无缓存无广播）
export function resolveMemoryImportPromptTemplate(): string {
  return pickMemoryImportPrompt(AppStorage.get<string>(MEMORY_IMPORT_PROMPT_KEY) ?? '');
}

// 粘贴文本上限（超限拦截：页面侧 maxLength 拦输入 + 本域再拦一道——maxLength 只约束输入框
// 键入/粘贴，程序化写入与旧版本留存的超长草稿仍会到达本域）
export const MEMORY_IMPORT_INPUT_MAX: number = 8000;
// 单次整理条数上限（{maxItems} 渲染注入值 + parseMemoryLines 解析上限，同源一处）
const MEMORY_IMPORT_MAX_COUNT: number = 40;
// 输出上限（0 = 不发 max_tokens 字段——与标题/提取/优化/识别四链同口径）
const MEMORY_IMPORT_MAX_OUTPUT: number = 0;
// 退避重试（TitleGen / MemoryGen / MemoryOpt 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次
const MAX_IMPORT_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;

// 存档摘要（历史页副行给人看的那句；「·」分隔符是本项目既有惯例）——导入没有改写/合并，
// 摘要如实说这次存的是导入前的库
const IMPORT_SNAPSHOT_NOTE: string = '导入前';

// ── 结果态（八态，照 MemorySinkResult 形制：全走返回值不借 reject）──
// · ready——整理成功且有条目（携带清单，预览态用）
// · none——没整理出条目（模型答「无」/ 条目全被敏感过滤与去重丢掉 / 粘贴文本为空）
// · limit——库满（prepare 或 apply 侧读到满，两处同态——页面同一句提示）
// · config——模型不可用（两键未配置 / 服务商或模型停用 / Key 池空 / 明文缺失）
// · failed——请求重试耗尽或异常终止
// · tooLarge——粘贴文本超 MEMORY_IMPORT_INPUT_MAX
// · skipped——守卫未放行（库态未就绪 / 总开关关 / 在途重复触发），页面保持沉默
// · inserted——apply 成功（count = 实际落库条数）
export const MEMORY_IMPORT_STATUS_READY: string = 'ready';
export const MEMORY_IMPORT_STATUS_NONE: string = 'none';
export const MEMORY_IMPORT_STATUS_LIMIT: string = 'limit';
export const MEMORY_IMPORT_STATUS_CONFIG: string = 'config';
export const MEMORY_IMPORT_STATUS_FAILED: string = 'failed';
export const MEMORY_IMPORT_STATUS_TOO_LARGE: string = 'tooLarge';
export const MEMORY_IMPORT_STATUS_SKIPPED: string = 'skipped';
export const MEMORY_IMPORT_STATUS_INSERTED: string = 'inserted';

// 整理计划（prepare 产物；页面预览态的唯一依据）：
// · items——待导入条目（已过解析侧清洗/敏感过滤/去重/条数上限，且已按剩余容量截断）
// · truncated——因库剩余容量不足而丢掉的条数（0 = 没丢；预览态据此出说明行）
export interface MemoryImportPlan {
  status: string;
  items: string[];
  truncated: number;
}

// 落库结果（apply 产物）
export interface MemoryImportResult {
  status: string;
  count: number;
}

function buildPlan(status: string, items: string[], truncated: number): MemoryImportPlan {
  return { status: status, items: items, truncated: truncated };
}

function buildResult(status: string, count: number): MemoryImportResult {
  return { status: status, count: count };
}

// in-flight 闸（单布尔，防模型请求并发重复触发；★ **不盖 apply**——落库在途闸在页面侧，
// 见头注释三重加固 ②）：导入不吃会话 id（导入不由会话触发），故用单布尔而非集合
// （照 MemoryOpt.optInFlight 形制；MemoryGen 的集合是因为它按会话去重）
let importInFlight: boolean = false;

// 链一入口（导入页「AI 整理」键）：只发请求 + 解析，**一个字都不落库**。全程结果对象
// （含退避重试；失败不 reject，落在 failed 态）——调用页据此进预览态或出提示
export function prepareMemoryImport(rawText: string,
  libraryId: string): Promise<MemoryImportPlan> {
  if (importInFlight) {
    hilog.info(DOMAIN, TAG, '导入整理在途，跳过本次触发');
    return Promise.resolve(buildPlan(MEMORY_IMPORT_STATUS_SKIPPED, [], 0));
  }
  importInFlight = true;
  return runPrepareMemoryImport(0, rawText, libraryId)
    .catch((e: Object): MemoryImportPlan => {
      hilog.error(DOMAIN, TAG, '导入整理异常终止：%{public}s', (e as Error).message);
      return buildPlan(MEMORY_IMPORT_STATUS_FAILED, [], 0);
    })
    .finally((): void => {
      importInFlight = false;
    });
}

// 整理主流程（attempt 从 0 起；retryable 失败经 setTimeout 退避后递归重入——守卫全重查）。
// 守卫序照 runMemorySinking 同序同口径：dbReady → 总开关 → 文本空/超限 → 模型两键 → 端点
// 与 Key → 库内上限 → 渲染与请求 → 记账 → 解析 → 容量截断
async function runPrepareMemoryImport(attempt: number, rawText: string,
  libraryId: string): Promise<MemoryImportPlan> {
  if (!isReady()) {
    return buildPlan(MEMORY_IMPORT_STATUS_SKIPPED, [], 0); // dbReady 守卫（竞态窗口内库态不假定）
  }
  if (!isMemoryEnabled()) {
    // 总开关（记忆功能停用 = 导入停用；页面入口已前置拦截，此处兜底——与「立即整理」同口径）
    hilog.info(DOMAIN, TAG, '记忆功能已停用，导入整理跳过');
    return buildPlan(MEMORY_IMPORT_STATUS_SKIPPED, [], 0);
  }
  const text: string = rawText.trim();
  if (text === '') {
    return buildPlan(MEMORY_IMPORT_STATUS_NONE, [], 0); // 空文本（页面已有前置 toast，此处兜底）
  }
  if (text.length > MEMORY_IMPORT_INPUT_MAX) {
    hilog.info(DOMAIN, TAG, '导入文本 %{public}d 字超上限 %{public}d，拒绝整理',
      text.length, MEMORY_IMPORT_INPUT_MAX);
    return buildPlan(MEMORY_IMPORT_STATUS_TOO_LARGE, [], 0);
  }
  // 记忆提取模型两键（★ 与「立即整理」共用同一对键，未配置 = 不可导入——决明 2026-09-22
  // 拍板「复用卡、执行不同任务与不同提示词」；不回退任何其他模型）
  const picked: MemoryModelPick = resolveMemoryModel();
  if (picked.providerId === '' || picked.modelId === '') {
    hilog.debug(DOMAIN, TAG, '记忆提取模型未配置，导入不可用');
    return buildPlan(MEMORY_IMPORT_STATUS_CONFIG, [], 0);
  }
  const resolved: TitleEndpoint | null =
    await resolveTitleEndpoint(picked.providerId, picked.modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '导入整理模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return buildPlan(MEMORY_IMPORT_STATUS_CONFIG, [], 0);
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——TitleGen 同口径）
  const apiKey: string = await loadPoolKey(picked.providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '导入整理 Key 明文缺失，放弃');
    return buildPlan(MEMORY_IMPORT_STATUS_CONFIG, [], 0);
  }
  // 目标库现有条目（同一遍现读三用：库满守卫 / 跨次去重键集 / 去重清单——与提取链同源口径；
  // ★ v35 起两库分派，库判据 = libraryId）
  const rows: MemoryRow[] = libraryId === MEMORY_SCOPE_GLOBAL ?
    await queryMemories() : await queryAssistantMemories(libraryId);
  if (rows.length >= MEMORY_MAX_TOTAL) {
    hilog.info(DOMAIN, TAG, '记忆已达上限 %{public}d 条，导入不可用', MEMORY_MAX_TOTAL);
    return buildPlan(MEMORY_IMPORT_STATUS_LIMIT, [], 0);
  }
  const existingKeys: string[] = [];
  const dedupItems: MemoryEntryItem[] = [];
  for (const row of rows) {
    existingKeys.push(normalizeMemoryKey(row.content));
    dedupItems.push({ content: row.content, createdAt: row.createdAt });
  }
  // 提示词渲染（单遍扫描两占位符：{maxItems} 注入条数上限 + {content} 注入粘贴文本——生效
  // 模板现读，用户改提示词下次导入即生效）
  let prompt: string = renderMemoryPrompt(resolveMemoryImportPromptTemplate(), text,
    MEMORY_IMPORT_MAX_COUNT);
  // 去重清单追加：★ 必须在渲染产物之后拼——清单含用户记忆文本，塞回模板再渲染等于给不可信
  // 内容开二次替换面（照 MemoryGen 同款防线）；空清单不拼段（零回归）
  const list: string = composeMemoryList(dedupItems, MEMORY_DEDUP_MAX_COUNT, MEMORY_DEDUP_MAX_CHARS);
  if (list !== '') {
    prompt += MEMORY_DEDUP_SECTION.split(MEMORY_DEDUP_LIST_MARK).join(list);
  }
  // 末三形参：读超时与句柄回传走默认，第三位 taskLabel = 请求日志来源标签 + 失败文案用途
  // 前缀（2026-09-23 请求日志笔；此前不传即错报「标题」）
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey, prompt, MEMORY_IMPORT_MAX_OUTPUT,
    undefined, undefined, '记忆导入');
  // 用途记账（HTTP 200 即已消耗 token——正文缺失的 200 形态也入账，照提取/优化两链口径）。
  // ★ 会话 id 传**空串**：本链无会话归属（导入不由会话触发），账目计入总费用与费用估计，
  //   但不归属任何会话、也不参与会话删除级联——这是有意为之，勿当 bug 改成传参（本链根本没
  //   有会话 id 可传：调用方是导入页，不是会话页）
  if (result.status === 200) {
    logTaskUsage('memory', '', picked.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (result.ok) {
    const items: string[] = parseMemoryLines(result.text, MEMORY_IMPORT_MAX_COUNT, existingKeys);
    if (items.length === 0) {
      // 模型答「无」与「条目全被敏感过滤/去重丢掉」同归 none（页面提示未整理出内容）
      hilog.info(DOMAIN, TAG, '本次导入未整理出条目');
      return buildPlan(MEMORY_IMPORT_STATUS_NONE, [], 0);
    }
    // 容量截断（prepare 侧预截断——让用户在预览态就看到「只保留前 N 条」，而不是确认后才发现
    // 少了几条；apply 侧另有事务内二次校验兜窗口期变化）。保留**前** N 条 = 淘汰尾部，与解析侧
    // 「满 maxCount 即 break」同向（提示词第 9 条已要求重要性降序，故尾部 = 最不重要）
    const room: number = MEMORY_MAX_TOTAL - rows.length;
    const kept: string[] = items.length > room ? items.slice(0, room) : items;
    const truncated: number = items.length - kept.length;
    if (truncated > 0) {
      hilog.info(DOMAIN, TAG, '库剩余容量 %{public}d 条，本次导入丢弃尾部 %{public}d 条', room, truncated);
    }
    hilog.info(DOMAIN, TAG, '导入整理完成：%{public}d 条待确认（丢弃 %{public}d 条）',
      kept.length, truncated);
    return buildPlan(MEMORY_IMPORT_STATUS_READY, kept, truncated);
  }
  // 失败分类（TitleGen 同款）：网络/5xx/429 退避重试；401/403/配置类不重试
  if (isRetryable(result.status) && attempt < MAX_IMPORT_RETRY) {
    const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, attempt + 1); // 2/4/8
    hilog.warn(DOMAIN, TAG, '导入整理请求失败(%{public}d)，%{public}d 秒后第 %{public}d 次重试',
      result.status, delaySeconds, attempt + 1);
    await sleep(delaySeconds * 1000);
    // 重试结果即本次结果（递归返回值原样上抛，勿吞成 void）
    return runPrepareMemoryImport(attempt + 1, rawText, libraryId);
  }
  hilog.warn(DOMAIN, TAG, '导入整理最终失败放弃 status=%{public}d：%{public}s',
    result.status, result.errorMessage);
  return buildPlan(MEMORY_IMPORT_STATUS_FAILED, [], 0);
}

// 链二入口（导入页「导入 N 条」键，用户确认后调用）：**一个事务**内完成——事务内读库
// （容量二次校验）→ 存档 → 逐条插入 → 提交，提交后才广播。失败即 rollBack 整体回滚，
// 中止即零改动（要么全进要么全不进——预览已确认，用户期待的就是全量落库）。
// ★ 读取与存档同处事务内，读到的是同一快照；★ 广播必须在 commit 之后。
export async function applyMemoryImport(items: string[],
  libraryId: string): Promise<MemoryImportResult> {
  if (items.length === 0) {
    return buildResult(MEMORY_IMPORT_STATUS_NONE, 0);
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  let written: number = 0;
  db.beginTransaction();
  try {
    // ① 事务内读库——★ 容量结论**不得信任 prepare**：prepare 算过的剩余容量到 apply 时可能
    // 已变（窗口期内退出会话的自动整理落库、或另一库页发起的导入先落库）
    const rows: MemoryRow[] = libraryId === MEMORY_SCOPE_GLOBAL ?
      await queryMemories() : await queryAssistantMemories(libraryId);
    const room: number = MEMORY_MAX_TOTAL - rows.length;
    if (room <= 0) {
      // ★ 提前返回必先 rollBack，否则事务悬挂（后续任何 beginTransaction 抛「嵌套」）
      db.rollBack();
      hilog.info(DOMAIN, TAG, '导入落库时库已满，未写入任何条目');
      return buildResult(MEMORY_IMPORT_STATUS_LIMIT, 0);
    }
    const pending: string[] = items.length > room ? items.slice(0, room) : items;
    // ② 先存档（同事务——拍快照与落库同生同死；事务外先拍 = 导入失败会留下一份「什么都没变」
    // 的幽灵快照，白占一个配额位）
    await archiveBeforeOptInTx(db, libraryId, IMPORT_SNAPSHOT_NOTE, MEMORY_SNAPSHOT_KIND_IMPORT);
    // ③ 逐条插入：insertMemory / insertAssistantMemory 自身**不开事务**（查 sortOrder 后即写），
    // 故在外层事务内逐条调用是安全的（先例 = applyMemoryOptChanges 同法）；source='import'
    // 是新增值，无存量行需要迁移（建表无 CHECK 约束）
    for (const item of pending) {
      if (libraryId === MEMORY_SCOPE_GLOBAL) {
        await insertMemory({ content: item, source: 'import', assistantId: '', conversationId: '' });
      } else {
        await insertAssistantMemory(libraryId, item, 'import', '');
      }
    }
    written = pending.length;
    db.commit();
  } catch (e) {
    // 禁静默：回滚后原样抛出，调用侧转 failed 并出提示（事务已 rollBack，库内零改动）
    db.rollBack();
    hilog.error(DOMAIN, TAG, '导入落库失败已回滚：%{public}s', (e as Error).message);
    throw e as Error;
  }
  // ④ 广播（必须在本行之前完成 commit——列表刷新读的是已提交态）
  if (libraryId === MEMORY_SCOPE_GLOBAL) {
    broadcastMemoryList();
  } else {
    broadcastAssistantMemoryList();
  }
  hilog.info(DOMAIN, TAG, '导入落库完成 %{public}d 条（库 %{public}s）', written, libraryId);
  return buildResult(MEMORY_IMPORT_STATUS_INSERTED, written);
}

// 失败恢复型退避等待（TitleGen / MemoryGen / MemoryOpt 同款）
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}
