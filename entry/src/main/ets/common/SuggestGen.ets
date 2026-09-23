// 推荐问题生成服务（2026-09-19 推荐问题功能，任务书-推荐问题-20260919 执行）——进程级
// 独立域，TitleGen 同构：顶层函数模块、不持页面/组件引用、不触 UI（刷新纯靠广播键）、
// 全链吞错永不 reject（hilog 留痕，不 toast 不出气泡不打扰对话主链路）。
// 单场景（§一，★ 2026-09-19 当晚决明拍板退役开场推荐链——原 A 场景 assistants.openers
// 已随退役全仓零消费，列留库为死列）：消息后推荐 = AI 回复 done 后
// fire-and-forget 独立非流式小请求（全链复用标题生成基建：TitleApi.requestTitleText 四
// 协议非流式通道 + TitleGen 验证/退避/记账范式），末条覆盖写 conversations.suggestions
// 并广播，末条助手消息气泡下 chips 显示，点击经 onSend 直接发送（决策 2/3/4）。
// 守卫序（任务书 §5.1 定稿，逐级早退全静默）：dbReady → 总开关 suggestEnabled（默认关，
// 决策 1）→ 两键齐（未配置 = 零请求无兜底——照标题生成 2026-09-05 拍板，不回退标题模型
// 禁走四级链）→ resolveTitleEndpoint 单级验证 → loadPoolKey 启用序首支 → 隐私会话由调用
// 侧过滤（本层无从判隐私态，TitleGen 同口径）→ 会话行已有非空 suggestions 跳过。
// 输入 = 最后 1 轮（最后 user + 最后 assistant 各 1 条，各截 800 字符加 …）——推荐只依赖
// 最后一问一答，比竞品 6~8 条省 token（任务书 §4.3）。重试 = isRetryable 类退避 2/4/8 秒
// 最多 3 次（setTimeout 链，失败恢复型等待非 P1-3 冗余等待）；解析为空不重试（同 prompt
// 重试大概率同样输出，TitleGen 同款）。
// 清空与代纪元：发送瞬间清空（写 '' + 广播）是中断场景关键兜底（第二轮失败/停止时旧建议
// 已随发送清掉，不会错挂）——同时 bumps 本会话代纪元，在途旧轮生成完成时核对纪元不符
// 即作废（防「发送清空后旧轮建议又写回」竞态：清空 ≠ 取消通道，唯一廉价作废点）。
// 记账：HTTP 200 即 logTaskUsage('suggest', ...) 入账（含 ok=false 的 200 形态，TitleGen
// 2026-09-10 口径）；网络错误/非 200 不记。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MessageRow, isReady, queryConversationSuggestions, queryRecentMessages,
  setConversationSuggestions } from './store/ChatDb';
import { SUGGEST_ENABLED_KEY, SUGGEST_MODEL_KEY, SUGGEST_PROVIDER_KEY } from './store/ProviderDb';
import { TitleEndpoint, isRetryable, resolveTitleEndpoint } from './TitleGen';
import { loadPoolKey } from './store/KeyStore';
import { requestTitleText, TitleRequestResult } from './providers/TitleApi';
import { logTaskUsage } from './store/UsageStatsDb';

const DOMAIN: number = 0x71C2;
const TAG: string = 'SuggestGen';

// 推荐问题提示词（任务书 §5.1 内置默认——语义定稿文案可润色：以用户口吻生成 3 条接下来
// 可能提出的问题，与对话内容语言一致，每条 ≤10 字〔★ 2026-09-19 决明改版：20 → 10 字，
// chips 短句化；解析截断 SUGGEST_ITEM_MAX_CHARS 同值联动〕，不重复已问内容，直接输出 JSON
// 数组不加解释与 markdown）。★ 机制照 TITLE_PROMPT_TEMPLATE：SUGGEST_PROMPT_TEMPLATE = 内置
// 默认（唯一真源），SUGGEST_PROMPT_KEY 存用户定制覆盖——'' = 未定制 = 生效内置（恢复默认
// = 清键回退，内置模板后续升级自动跟随）；生效模板单源 = resolveSuggestPromptTemplate()
// 生成链与功能模型页编辑面板共用；SUGGEST_PROMPT_CONTENT = {content} 占位符（编辑保存
// 校验必须含——缺占位符 = 请求无对话内容可插，模板失效），渲染时替换为对话内容拼接串
export const SUGGEST_PROMPT_TEMPLATE: string =
  '我将给你一段对话内容，放在 <content> 标签块中。\n' +
  '请以用户的口吻，生成 3 条接下来最可能提出的问题。\n' +
  '1. 问题使用与对话内容一致的语言\n' +
  '2. 每条不超过 10 个字，不重复对话中已经问过的内容\n' +
  '3. 直接输出 JSON 字符串数组，例如 ["问题一","问题二","问题三"]，' +
  '不要任何解释，不要 markdown 代码块\n' +
  '\n' +
  '<content>\n' +
  '{content}\n' +
  '</content>';
export const SUGGEST_PROMPT_CONTENT: string = '{content}';
// 推荐提示词定制键（AppStorage 持久化；'' = 未定制 = 生效内置模板——清删式语义；EntryAbility
// persistProp 注册，备份白名单在 AppPreferences.BACKUP_PREF_KEYS 功能模型绑定段）
export const SUGGEST_PROMPT_KEY: string = 'suggestPrompt';

// 生效模板纯选择（custom 非空取 custom，空回退内置——AppStorage 读取在 IO 面，
// 本纯函数可 node 直跑断言：内核回退与定制两路，pickTitlePrompt 同款）
export function pickSuggestPrompt(custom: string): string {
  return custom !== '' ? custom : SUGGEST_PROMPT_TEMPLATE;
}

// 生效模板单源（生成链 + 功能模型页编辑面板共用）：定制非空取定制，空回退内置
export function resolveSuggestPromptTemplate(): string {
  return pickSuggestPrompt(AppStorage.get<string>(SUGGEST_PROMPT_KEY) ?? '');
}

// ── 数值常量（导出 = 断言资产消费）──
// 生成请求温度 0.3 与 maxOutput 在 TitleApi 侧由调用参给定（此处只传 maxOutput）；
// ★ 2026-09-20 上限 300 → 0（决明拍板照标题/记忆链同口径——真机账本实锤 42 笔 34 笔
// 打满 300、思考段烧满正文恒空 = 推荐不出主因；0 = 不发 max_tokens 字段）
export const SUGGEST_MAX_OUTPUT: number = 0;
export const SUGGEST_INPUT_CHAR_LIMIT: number = 800; // 单条输入截断（超长加 …）
export const SUGGEST_COUNT: number = 3; // 推荐条数固定 3（决策 4）
export const SUGGEST_ITEM_MAX_CHARS: number = 10; // 单条建议上限（解析时截断；★ 2026-09-19 决明改版 50 → 10 与提示词同值联动）
const SUGGEST_STORE_MAX: number = 4; // 存储解析条数收口（推荐 ≤3 恒不受影响）
// 退避重试（TitleGen MAX_TITLE_RETRY 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次，总窗 ≤14s
const MAX_SUGGEST_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;

// 推荐刷新广播键（AppStorage tick 递增；CONV_TITLE_TICK_KEY 同款先例）。★ 2026-09-19 执行
// 偏差点名（任务书原写「ChatPageContent 订阅 tick → 调 SuggestGen 读会话行函数」）：会话
// id 不经 ChatPage 传入 ChatPageContent（ChatPage 硬线零改动，其现有 props 无会话 id），
// 订阅侧无从知道该读哪个会话行——改为广播**载荷键**（SUGGEST_PAYLOAD_KEY = JSON 串
// {msgId, items}，msgId 全局唯一），订阅侧按 msgId 在自身 dataSource 命中后原地挂字段，
// 跨会话天然无串扰（他页 dataSource 无此 id = no-op）。tick 键保留作时序信号（语义与
// CONN_RESOLVE_TICK_KEY 同族：@Watch 对同值不触发，payload 键可能连写同串，tick 递增
// 保证每次广播都被感知）。回放路径不走广播——ChatPageLoad.loadHistory 持会话 id 直读库列
export const SUGGEST_TICK_KEY: string = 'suggestTick';
export const SUGGEST_PAYLOAD_KEY: string = 'suggestPayload';

// 广播载荷（msgId = 建议挂载目标助手消息 id；'' = 清空广播——订阅侧按 msgId 命中，空 id
// 天然无命中 = 纯时序信号）
export interface SuggestPayload {
  msgId: string;
  items: string[];
}

// 载荷解析（坏 JSON / 缺字段 / 类型不符回 null——订阅侧丢弃该次广播，坑59① 显式接口）
export function parseSuggestPayload(json: string): SuggestPayload | null {
  if (json === '') {
    return null;
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(json) as Object;
  } catch (e) {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return null;
  }
  const rec: Record<string, Object> = parsed as Record<string, Object>;
  const msgId: Object | undefined = rec['msgId'];
  const items: Object | undefined = rec['items'];
  if (typeof msgId !== 'string' || !Array.isArray(items)) {
    return null;
  }
  const list: string[] = [];
  for (const item of items as Object[]) {
    if (typeof item === 'string') {
      list.push(item);
    }
  }
  const payload: SuggestPayload = { msgId: msgId, items: list };
  return payload;
}

// ── 存储解析/序列化（conversations.suggestions 单一落点
// 「本域只存取原串、解析单落点」先例 = tools→ToolTypes / skills→SkillText；openers 列
// 已随开场链退役成死列，无调用方）──

// 库列 JSON 串 → 条目清单（'' / 坏 JSON / 非数组 / 非字符串项逐条丢弃不抛错；trim + 滤空；
// 条数收口 SUGGEST_STORE_MAX = 4）。不压空白不截长——存储值由写入侧（生成解析/编辑页
// 保存校验）保证形态，解析侧只防御坏数据
export function parseSuggestions(json: string): string[] {
  if (json === '') {
    return [];
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(json) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const items: string[] = [];
  for (const item of parsed as Object[]) {
    if (typeof item === 'string' && item.trim() !== '') {
      items.push(item.trim());
    }
  }
  return items.slice(0, SUGGEST_STORE_MAX);
}

// 条目清单 → 库列 JSON 串（JSON.stringify 原样——round-trip 稳定，断言可钉）
export function serializeSuggestions(items: string[]): string {
  return JSON.stringify(items);
}

// 模型输出清洗解析（任务书 §5.1 七环）：去 <think> 标签（TitleGen.cleanTitle 同款正则）→
// 剥首尾 markdown code fence（```json 围栏，模型偶发包裹的防御）→ JSON.parse → 接受两种
// 形态：字符串数组，或对象含 follow_ups 数组（Open WebUI 式包裹防御）→ 逐条 trim / 压
// 空白 / 截 10 字符（按码点，见 clipByCodePoint）/ 滤空串 → 取前 3。任何一步不符或结果为空 = 回 []
export function parseSuggestList(raw: string): string[] {
  let text: string = raw.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  text = stripCodeFence(text);
  let parsed: Object;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    return [];
  }
  let list: Object[] | null = null;
  if (Array.isArray(parsed)) {
    list = parsed as Object[];
  } else if (parsed !== null && typeof parsed === 'object') {
    const rec: Record<string, Object> = parsed as Record<string, Object>;
    const followUps: Object | undefined = rec['follow_ups'];
    if (Array.isArray(followUps)) {
      list = followUps as Object[];
    }
  }
  if (list === null) {
    return [];
  }
  const items: string[] = [];
  for (const item of list) {
    if (typeof item !== 'string') {
      continue;
    }
    const squeezed: string = item.replace(/\s+/g, ' ').trim();
    if (squeezed === '') {
      continue;
    }
    items.push(clipByCodePoint(squeezed, SUGGEST_ITEM_MAX_CHARS));
  }
  return items.slice(0, SUGGEST_COUNT);
}

// 按码点截断（2026-09-20 D2-3 修复）：substring 按 UTF-16 码元切，截点落在代理对中间会切出
// 孤立高位代理（半个 emoji）——残串照写库 / 广播 / 上屏，点击即把残串当消息发出。改按码点
// 计数剪切（代理对算一个字符，与「≤ N 字符」语义一致）；孤立代理脏数据不入对（+1 收尾不死循环）。
// 溢出不加省略号的既有形态（parseSuggestList 面）保持不变
function clipByCodePoint(text: string, max: number): string {
  if (text.length <= max) {
    return text; // 码元数 ≤ max 时码点数必 ≤ max——零拷贝快路径
  }
  let end: number = 0;
  let count: number = 0;
  while (end < text.length && count < max) {
    const code: number = text.charCodeAt(end);
    end += (code >= 0xD800 && code <= 0xDBFF && end + 1 < text.length) ? 2 : 1;
    count++;
  }
  return text.substring(0, end);
}

// code fence 剥除（```json\n...\``` 首行围栏 + 尾围栏；单行无换行形态剥头 ``` 后找尾围栏）
function stripCodeFence(text: string): string {
  let t: string = text.trim();
  if (!t.startsWith('```')) {
    return t;
  }
  const firstNl: number = t.indexOf('\n');
  t = firstNl >= 0 ? t.substring(firstNl + 1) : t.substring(3);
  const close: number = t.lastIndexOf('```');
  if (close >= 0) {
    t = t.substring(0, close);
  }
  return t.trim();
}

// 对话内容拼接：最后 1 轮 = 最后 user + 最后 assistant 各 1 条（过滤空内容；tool 行不入），
// 各截 800 字符加 …，`user: 内容` / `assistant: 内容` 逐行（buildTitleContent 同款拼接，
// 含压空白）。两条皆空 = ''（无请求必要）
export function buildSuggestContent(messages: MessageRow[]): string {
  let lastUser: string = '';
  let lastAssistant: string = '';
  for (const m of messages) {
    if (m.role === 'user' && m.content !== '') {
      lastUser = m.content;
    }
    if (m.role === 'assistant' && m.content !== '') {
      lastAssistant = m.content;
    }
  }
  const lines: string[] = [];
  // 压空白后再判空（纯空白内容跳过——拼出「user: 」空值行会让提示词缺对话内容）
  const userText: string = lastUser !== '' ? squeezeInput(lastUser) : '';
  const assistantText: string = lastAssistant !== '' ? squeezeInput(lastAssistant) : '';
  if (userText !== '') {
    lines.push('user: ' + userText);
  }
  if (assistantText !== '') {
    lines.push('assistant: ' + assistantText);
  }
  return lines.join('\n');
}

// 单条输入截断：压空白 ≤800 字符、超长加 …（TITLE_INPUT_CHAR_LIMIT 同款姿势；截断按码点
// 走 clipByCodePoint——同族收口，D2-3 的孤立代理残串本处虽只进提示词不上屏，仍一并根治）
function squeezeInput(content: string): string {
  const squeezed: string = content.replace(/\s+/g, ' ').trim();
  return squeezed.length > SUGGEST_INPUT_CHAR_LIMIT ?
    clipByCodePoint(squeezed, SUGGEST_INPUT_CHAR_LIMIT) + '…' : squeezed;
}

// in-flight 会话 id 集（退避窗口内防同会话并发重复请求；跨会话并行无害——TitleGen 同款）
const inflightIds: Set<string> = new Set();
// 在途期被吞掉的触发暂存（会话 id → 最近一次被跳过的目标消息 id）——收口后补跑一次。
// ★ 2026-09-20 修复（D2-1）：原实现命中在途直接 return 丢弃——上一轮生成仍在途时（退避
// 重试窗 2+4+8 = 14s 加请求时长）用户发下一条，该轮 done 的触发被整条吞掉，净效果是该轮
// 建议永不生成且用户侧完全静默（只有 hilog）。恒只保最新一条、收口即删（数据有界）
const pendingMsgIds: Map<string, string> = new Map();
// 代纪元（会话级）：clearConversationSuggestions bumps——在途生成写库前核对，不符即作废
//（防「发送清空后旧轮建议又写回」竞态；只在 in-flight 期记账，生成收口即删，Map 恒小）
const clearEpochs: Map<string, number> = new Map();

// 推荐生成入口（finishStream('done') 内 finalizeMessage.then 的 done 分支一行
// fire-and-forget 调用，generateTitleForConversation 同位；隐私会话由调用侧守卫过滤后才到
// 这；内部全吞错误 hilog 留痕，永不 reject）
export function generateSuggestForMessage(conversationId: string, assistantMsgId: string): void {
  if (conversationId === '' || assistantMsgId === '') {
    return;
  }
  if (inflightIds.has(conversationId)) {
    // 在途期不并发、但也不丢弃：暂存最新触发，收口后补跑（见 pendingMsgIds 注释）
    pendingMsgIds.set(conversationId, assistantMsgId);
    hilog.info(DOMAIN, TAG, '生成在途，本次触发暂存待补跑 conv=%{public}s', conversationId);
    return;
  }
  inflightIds.add(conversationId);
  const epoch: number = clearEpochs.get(conversationId) ?? 0;
  runSuggestGeneration(conversationId, assistantMsgId, 0, epoch)
    .catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '推荐生成异常终止 conv=%{public}s：%{public}s',
        conversationId, (e as Error).message);
    })
    .finally((): void => {
      inflightIds.delete(conversationId);
      clearEpochs.delete(conversationId); // 收口即删——纪元只在 in-flight 期有意义（有界）
      // 在途期被吞掉的触发在此补跑（★ 2026-09-20 修复 D2-1）：先清在途登记再重入，
      // 否则补跑又被自身去重拦下；重入走完整守卫序，纪元按收口后现值现读
      const pending: string | undefined = pendingMsgIds.get(conversationId);
      if (pending !== undefined) {
        pendingMsgIds.delete(conversationId);
        generateSuggestForMessage(conversationId, pending);
      }
    });
}

// 主流程（attempt 从 0 起；retryable 失败经 setTimeout 退避后重入走完整守卫序）
async function runSuggestGeneration(conversationId: string, assistantMsgId: string,
  attempt: number, epoch: number): Promise<void> {
  if (!isReady()) {
    return; // dbReady 守卫（调用侧已判，双保险——竞态窗口内库态不假定）
  }
  if ((clearEpochs.get(conversationId) ?? 0) !== epoch) {
    return; // 期间发生发送清空——本轮作废（重入各层含写库前共三道核对）
  }
  const enabled: boolean = AppStorage.get<boolean>(SUGGEST_ENABLED_KEY) === true;
  if (!enabled) {
    hilog.debug(DOMAIN, TAG, '推荐问题总开关未开启');
    return;
  }
  // 两键解析（唯一来源，禁走四级链/active/default——见文件头守卫序注释）
  const providerId: string = AppStorage.get<string>(SUGGEST_PROVIDER_KEY) ?? '';
  const modelId: string = AppStorage.get<string>(SUGGEST_MODEL_KEY) ?? '';
  if (providerId === '' || modelId === '') {
    // 功能未启用（决明拍板同标题生成：静默不生成，无会话连接兜底）——debug 级留痕
    hilog.debug(DOMAIN, TAG, '推荐问题模型未配置，功能未启用');
    return;
  }
  const resolved: TitleEndpoint | null = await resolveTitleEndpoint(providerId, modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '推荐问题模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return;
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——TitleGen 同口径）
  const existing: string = await queryConversationSuggestions(conversationId);
  if (existing !== '') {
    return; // 会话行已有非空建议——防异常路径重复生成
  }
  const apiKey: string = await loadPoolKey(resolved.providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '推荐问题 Key 明文缺失（资产迁移中断/手工清资产），放弃');
    return;
  }
  const content: string = buildSuggestContent(await queryRecentMessages(conversationId));
  if (content === '') {
    return; // 无可推荐内容（两条皆空），无请求必要
  }
  // split/join 替换——String.replace 的替换串含 $&/$`/$' 等特殊序列时会被解释注入模板
  //（消息内容来自用户输入不可信；TitleGen 同款 split/join 先例）
  // 模板 = resolveSuggestPromptTemplate() 现读（用户改提示词下次生成立即生效，无缓存）
  const prompt: string =
    resolveSuggestPromptTemplate().split(SUGGEST_PROMPT_CONTENT).join(content);
  // 末三形参：读超时与句柄回传走默认，第三位 taskLabel = 请求日志来源标签 + 失败文案用途
  // 前缀（2026-09-23 请求日志笔；此前不传即错报「标题」）
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey, prompt, SUGGEST_MAX_OUTPUT,
    undefined, undefined, '推荐问题');
  // 用途记账（TitleGen 2026-09-10 口径）：HTTP 200 即已消耗 token——ok=false 的 200 形态也
  // 入账；网络错误/HTTP 非 200 无 usage 不记。放清洗之前，建议无效放弃不影响账本如实
  //（purpose='suggest'，conversationId = 目标会话随删会话级联删；全零不落 = 零污染守卫）
  if (result.status === 200) {
    logTaskUsage('suggest', conversationId, resolved.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (result.ok) {
    const items: string[] = parseSuggestList(result.text);
    if (items.length === 0) {
      // 清洗后为空（模型输出质量问题）：不重试直接放弃（同 prompt 重试大概率同样输出）
      hilog.warn(DOMAIN, TAG, '推荐清洗后为空放弃 conv=%{public}s raw=%{public}s',
        conversationId, result.text.slice(0, 50));
      return;
    }
    if ((clearEpochs.get(conversationId) ?? 0) !== epoch) {
      hilog.info(DOMAIN, TAG, '写库前发现会话已发送清空，旧轮建议作废 conv=%{public}s',
        conversationId);
      return;
    }
    try {
      await setConversationSuggestions(conversationId, serializeSuggestions(items));
    } catch (e) {
      // 写库失败 hilog 不广播（UI 保持无建议态，不假装成功）
      hilog.error(DOMAIN, TAG, '推荐写库失败 conv=%{public}s：%{public}s',
        conversationId, (e as Error).message);
      return;
    }
    hilog.info(DOMAIN, TAG, '推荐已写回 conv=%{public}s count=%{public}d',
      conversationId, items.length);
    broadcastSuggestRefresh(assistantMsgId, items);
    return;
  }
  // 失败分类：网络(-1)/5xx/429 = 可退避重试；401/403/400 等 = 配置鉴权类不重试放弃
  if (isRetryable(result.status) && attempt < MAX_SUGGEST_RETRY) {
    const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, attempt + 1); // 2/4/8
    hilog.warn(DOMAIN, TAG, '推荐请求失败(%{public}d) conv=%{public}s，%{public}d 秒后第 %{public}d 次重试',
      result.status, conversationId, delaySeconds, attempt + 1);
    await sleep(delaySeconds * 1000);
    // 重入走完整守卫序（守卫全重查——退避窗口内发送清空/行删除由纪元与守卫兜住）
    await runSuggestGeneration(conversationId, assistantMsgId, attempt + 1, epoch);
    return;
  }
  hilog.warn(DOMAIN, TAG, '推荐请求最终失败放弃 conv=%{public}s status=%{public}d：%{public}s',
    conversationId, result.status, result.errorMessage);
}

// 发送瞬间清空（dispatchSend 入库链 upgradeTitlePlaceholder 调用同位——任务书 §5.1 清空
// 接线；此清空是中断场景的关键兜底：第二轮回复失败或手动停止时，上一轮旧建议已在发送
// 瞬间清掉，不会错挂在失败轮下面）。in-flight 期同时 bumps 代纪元作废在途旧轮写回；
// fire-and-forget，写库失败 hilog 不广播。隐私会话由调用侧过滤（不入此函数）
export function clearConversationSuggestions(conversationId: string): void {
  if (conversationId === '') {
    return;
  }
  if (inflightIds.has(conversationId)) {
    clearEpochs.set(conversationId, (clearEpochs.get(conversationId) ?? 0) + 1);
  }
  setConversationSuggestions(conversationId, '')
    .then((): void => {
      broadcastSuggestRefresh('', []); // 清空广播（msgId 空 = 订阅侧纯时序信号无挂载面）
    })
    .catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '推荐清空失败 conv=%{public}s：%{public}s',
        conversationId, (e as Error).message);
    });
}

// 会话行建议读取（ChatPageLoad.loadHistory 回放装配消费——持会话 id 直读库列，不经广播）；
// 解析单落点 = parseSuggestions（'' / 坏数据回 []）
export async function loadConversationSuggestions(conversationId: string): Promise<string[]> {
  return parseSuggestions(await queryConversationSuggestions(conversationId));
}

// 推荐刷新广播：tick 递增 + 载荷键覆写（两键成对——语义见 SUGGEST_TICK_KEY 注释）
function broadcastSuggestRefresh(msgId: string, items: string[]): void {
  AppStorage.setOrCreate<number>(SUGGEST_TICK_KEY,
    (AppStorage.get<number>(SUGGEST_TICK_KEY) ?? 0) + 1);
  const payload: SuggestPayload = { msgId: msgId, items: items };
  AppStorage.setOrCreate<string>(SUGGEST_PAYLOAD_KEY, JSON.stringify(payload));
}

// 失败恢复型退避等待（重试链专用——非 P1-3 禁的冗余等待；TitleGen 同款）
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}
