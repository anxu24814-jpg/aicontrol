// 标题生成服务（2026-09-05 AI 会话标题自动生成任务 5）——进程级独立域：顶层函数模块，
// 不持页面/组件引用、不触 UI（刷新纯靠广播键），按会话 id 写库——切会话/退页/销毁不
// 中断不丢结果（ChatSendCtrl 已 836 行软引导区禁再添，独立成件）。
// 全链（数据流见任务书方案总览）：发送首条消息 → 占位升级（首条内容截断 ≤20 字符加…，
// 纯本地零请求）→ AI 回复 finishStream('done') 后 fire-and-forget 触发 → 守卫序 →
// 读最近 4 条 user/assistant 消息（每条截 500 字符）拼提示词 → 非流式小请求
//（TitleApi，温度 0.3；输出不设上限——2026-09-20 随思考模型实锤改 0）→ cleanTitle 清洗 +
// isValidTitle 校验 → 写回前
// 重查 titleSource（manual = 放弃——用户改名终胜出的唯一防覆盖闸）→ setConversationTitle
// ('ai') → 广播刷列表标题行（2026-09-09 取消会话内标题显示后，广播消费方只剩会话列表）。
// 守卫序（任务书定稿）：dbReady → 会话行 titleSource==''（成功即止 + manual 永不再生成，
// 失败留 '' 下次对话完成补试）→ privateMode 旁路（**由调用侧保证传入前过滤**——本层
// 无从判隐私态）→ ★标题两键解析（决明 2026-09-05 二次拍板：两键未配置 = 功能未启用，
// 静默放弃不重试不补试，**无会话连接兜底**——标题模型是显式开关，用户不配就不发任何
// 请求；已配置 = 按 tryCandidate 同级标准独立验证〔服务商存在且启用 + 模型为该服务商
// 启用对话模型 + key 池非空〕，验证不通过 = 配置类失败放弃；**禁走 resolveActiveConnection
// 四级链**——链容忍降级（未配置的槽位会被别的模型顶上），而「标题模型未配置 = 标题功能
// 未启用」必须硬区分）。
// 重试（Cube 参数）：网络/5xx/429 类失败按 2^(n+1) 秒退避最多 3 次（setTimeout 链，
// 失败恢复型等待非 P1-3 冗余等待；总窗 ≤14s 进程级有界）；配置/鉴权类（401/403、key
// 缺失、两键未配置或验证不通过）与清洗校验失败（模型输出质量问题，重试同 prompt 大
// 概率同样输出）不重试直接放弃留 ''。全程 hilog 留痕（错误码入日志），不 toast 不出
// notice 气泡——不打扰对话主链路（任务书禁区）。
// 并发防护：模块级 in-flight 会话 id 集——同会话生成在途时新触发直接跳过（防退避窗口
// 内下次对话完成并发重复请求刷屏扣费）；跨会话天然并行无害（按 id 写库互不干扰）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MessageRow, isReady, queryConversationTitleSource, queryRecentMessages,
  setConversationTitle, upgradePlaceholderTitle } from './store/ChatDb';
import { TITLE_MODEL_KEY, TITLE_PROVIDER_KEY, ModelRow, ProviderRow, queryModels,
  queryProviders } from './store/ProviderDb';
import { queryEnabledKeyIds } from './store/ProviderKeyDb';
import { loadPoolKey } from './store/KeyStore';
import { requestTitleText, TitleRequestResult } from './providers/TitleApi';
import { logTaskUsage } from './store/UsageStatsDb';

const DOMAIN: number = 0x71C1;
const TAG: string = 'TitleGen';

// 标题生成提示词（2026-09-05 决明定稿——Cube/RikkaHub 同构模板中文化，去 {locale}
// 变量：规则 1 已保语言随内容一致；★ 2026-09-05 开放编辑（决明指令）：TITLE_PROMPT_TEMPLATE
// = 内置默认（唯一真源），TITLE_PROMPT_KEY（'titlePrompt' AppStorage 持久键，EntryAbility
// persistProp 注册，同标题两键先例）存用户定制覆盖——'' = 未定制 = 生效内置（恢复默认 =
// 清键回退，内置模板后续升级自动跟随）；生效模板单源 = resolveTitlePromptTemplate()
// 生成链与功能模型页编辑面板共用；TITLE_PROMPT_CONTENT = {content} 占位符（编辑保存校验
// 必须含——缺占位符 = 请求无对话内容可插，模板失效），渲染时替换为对话内容拼接串）
// ★ 2026-09-09 规则 4 上限 10 → 9 字（决明指令「计算…可以显示的最长长度，并同步更改标题
// 生成模型的默认提示词长度要求」；同日两行试验回退后按单行重定）：出处 = 对话页标题栏的
// 单行容量定标——可用文本宽 = 屏宽 − 左避让 64vp − 右避让 152vp，Pura 80 Pro+ 1276px @3.5
// 实测 = 148.57vp；16fp 汉字 1em = 16vp → 9 字（旧值 10 字本就会截掉末字）。★ 同日晚决明
// 指令「取消会话内显示标题」后标题栏不再显示标题（该容量约束的落点消失），9 字上限按
// 「历史页标题显示/生成链路不变」原样保留——历史列表卡宽于标题栏，9 字可全显；放宽另案。
// 已定制用户保留自己的模板（定制优先，不受本次内置升级影响）。
export const TITLE_PROMPT_TEMPLATE: string =
  '我将给你一段对话内容，放在 <content> 标签块中。\n' +
  '请把这段用户与 AI 助手的对话总结成一个简短标题。\n' +
  '1. 标题使用与对话内容一致的语言\n' +
  '2. 不要使用标点符号或其他特殊符号\n' +
  '3. 直接回复标题本身，不要任何解释\n' +
  '4. 标题不超过 9 个字\n' +
  '\n' +
  '<content>\n' +
  '{content}\n' +
  '</content>';
export const TITLE_PROMPT_CONTENT: string = '{content}';
// 标题提示词定制键（AppStorage 持久化；'' = 未定制 = 生效内置模板——清删式语义）
export const TITLE_PROMPT_KEY: string = 'titlePrompt';

// 生效模板纯选择（custom 非空取 custom，空回退内置——AppStorage 读取在 IO 面，
// 本纯函数可节点直跑断言：内核回退与定制两路）
export function pickTitlePrompt(custom: string): string {
  return custom !== '' ? custom : TITLE_PROMPT_TEMPLATE;
}

// 生效模板单源（生成链 + 功能模型页编辑面板共用）：定制非空取定制，空回退内置
export function resolveTitlePromptTemplate(): string {
  return pickTitlePrompt(AppStorage.get<string>(TITLE_PROMPT_KEY) ?? '');
}

// 对话内容输入参数（RikkaHub 单条截断 + Cube 条数双控）：最近 4 条 user/assistant 消息，
// 每条截 500 字符超长加 …（token 双控——Cube 只控条数、RikkaHub 只控单条长，取两者并集）
const TITLE_INPUT_MESSAGES: number = 4;
const TITLE_INPUT_CHAR_LIMIT: number = 500;
// 占位标题上限（Cube buildDraftTitle 同参数）：压空白后 ≤20 字符、超长加 …
const TITLE_PLACEHOLDER_MAX_CHARS: number = 20;
// 退避重试（Cube MAX_TITLE_RETRY 同参数）：2^(n+1) 秒 = 2/4/8 共 3 次，总窗 ≤14s
const MAX_TITLE_RETRY: number = 3;
const RETRY_BASE_SECONDS: number = 2;

// 标题刷新广播键（AppStorage tick 递增；写点 = 本模块写回/占位升级成功，读点 = ChatSessionList
// @StorageProp @Watch → 重拉列表刷标题行——CONN_RESOLVE_TICK_KEY 同款先例，09-05 真机验收
// 通过形态；★ 2026-09-09 取消会话内标题显示后对话页订阅点退役，本键只剩列表一个消费方）
export const CONV_TITLE_TICK_KEY: string = 'convTitleTick';

// in-flight 会话 id 集（退避窗口内防同会话并发重复请求；跨会话并行无害）
const inflightIds: Set<string> = new Set();

// 占位标题升级（任务 7：dispatchSend 入库链调用——首条 user 消息入库后）：首条内容压
// 白色 ≤20 字符加 …，纯附件消息（文本为空）跳过；条件 UPDATE 原子闸在 ChatDb
// upgradePlaceholderTitle（仅「新对话 + 占位态''」的行才写，已升级/已改名/已生成的不中）
// ——fire-and-forget，失败 hilog 不打扰发送主链路
export function upgradeTitlePlaceholder(conversationId: string, firstUserText: string): void {
  const squeezed: string = firstUserText.replace(/\s+/g, ' ').trim();
  if (squeezed === '') {
    return; // 纯附件消息（无文本）跳过
  }
  const title: string = squeezed.length > TITLE_PLACEHOLDER_MAX_CHARS ?
    squeezed.substring(0, TITLE_PLACEHOLDER_MAX_CHARS) + '…' : squeezed;
  upgradePlaceholderTitle(conversationId, title)
    .then((upgraded: boolean): void => {
      if (upgraded) {
        hilog.info(DOMAIN, TAG, '占位标题已升级 conv=%{public}s', conversationId);
        broadcastTitleRefresh();
      }
    })
    .catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '占位标题升级失败 conv=%{public}s：%{public}s',
        conversationId, (e as Error).message);
    });
}

// 标题生成入口（任务 6：finishStream('done') 内一行 fire-and-forget 调用；privateMode
// 由调用侧守卫过滤后才到这）：内部全吞错误（hilog 留痕），永不 reject
export function generateTitleForConversation(conversationId: string): void {
  if (conversationId === '') {
    return;
  }
  if (inflightIds.has(conversationId)) {
    hilog.info(DOMAIN, TAG, '生成在途跳过本次触发 conv=%{public}s', conversationId);
    return;
  }
  inflightIds.add(conversationId);
  runTitleGeneration(conversationId, 0)
    .catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '标题生成异常终止 conv=%{public}s：%{public}s',
        conversationId, (e as Error).message);
    })
    .finally((): void => {
      inflightIds.delete(conversationId);
    });
}

// 主流程（attempt 从 0 起；retryable 失败经 setTimeout 退避后递归重入）
async function runTitleGeneration(conversationId: string, attempt: number): Promise<void> {
  if (!isReady()) {
    return; // dbReady 守卫（调用侧已判，双保险——竞态窗口内库态不假定）
  }
  // 生成前守卫：'' 才生成（成功即止 + manual 永不再生成；失败留 '' 下次对话完成补试）
  const source: string = await queryConversationTitleSource(conversationId);
  if (source !== '') {
    return;
  }
  // ★ 标题两键解析（唯一来源，禁走四级链/active/default 四键——见文件头守卫序注释）
  const providerId: string = AppStorage.get<string>(TITLE_PROVIDER_KEY) ?? '';
  const modelId: string = AppStorage.get<string>(TITLE_MODEL_KEY) ?? '';
  if (providerId === '' || modelId === '') {
    // 功能未启用（决明拍板：静默不生成，无会话连接兜底）——debug 级留痕，不刷错误日志
    hilog.debug(DOMAIN, TAG, '标题模型未配置，功能未启用');
    return;
  }
  const resolved: TitleEndpoint | null = await resolveTitleEndpoint(providerId, modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '标题模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return;
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——克制定版）
  const apiKey: string = await loadPoolKey(providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '标题 Key 明文缺失（资产迁移中断/手工清资产），放弃');
    return;
  }
  const content: string = buildTitleContent(await queryRecentMessages(conversationId));
  if (content === '') {
    return; // 无可总结内容（空会话竞态——行已删等），无请求必要
  }
  // split/join 替换——String.replace 的替换串含 $&/$`/$' 等特殊序列时会被解释注入模板
  // 片段（消息内容来自用户输入不可信；PromptVariables.replaceToken 同款 split/join 先例）
  // 模板 = resolveTitlePromptTemplate() 现读（用户改提示词下次生成立即生效，无缓存）
  const prompt: string = resolveTitlePromptTemplate().split(TITLE_PROMPT_CONTENT).join(content);
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey, prompt);
  // 用途记账（2026-09-10 费用估计；2026-09-11 自检轮 P1-3 决明拍板放宽）：HTTP 200 即已
  // 消耗 token——正文缺失（ok=false 的 200 形态，TitleApi 已如实带回 usage）也入账；
  // 网络错误/HTTP 非 200 无 usage 不记（技术不可得）。放在清洗校验之前，标题无效放弃
  // 不影响账本如实入账（purpose='title'，conversationId = 目标会话随删会话级联删；
  // 全零不落 = 响应无 usage 字段的零污染守卫）
  if (result.status === 200) {
    logTaskUsage('title', conversationId, resolved.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  if (result.ok) {
    const title: string = cleanTitle(result.text);
    if (!isValidTitle(title)) {
      // 清洗后无效（空/全标点——模型输出质量问题）：不重试直接放弃留 ''（同 prompt 重试
      // 大概率同样输出，成本不值——见文件头注释）
      hilog.warn(DOMAIN, TAG, '标题清洗后无效放弃 conv=%{public}s raw=%{public}s',
        conversationId, result.text.slice(0, 50));
      return;
    }
    // 写回前重查（唯一防覆盖闸后半道：生成期间用户改名 → manual → 放弃）
    const beforeWrite: string = await queryConversationTitleSource(conversationId);
    if (beforeWrite !== '') {
      hilog.info(DOMAIN, TAG, '写回前发现 titleSource=%{public}s，放弃覆盖', beforeWrite);
      return;
    }
    await setConversationTitle(conversationId, title, 'ai');
    hilog.info(DOMAIN, TAG, 'AI 标题已写回 conv=%{public}s title=%{public}s',
      conversationId, title);
    broadcastTitleRefresh();
    return;
  }
  // 失败分类：网络(-1)/5xx/429 = 可退避重试；401/403/400 等 = 配置鉴权类不重试放弃
  if (isRetryable(result.status) && attempt < MAX_TITLE_RETRY) {
    const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, attempt + 1); // 2/4/8
    hilog.warn(DOMAIN, TAG, '标题请求失败(%{public}d) conv=%{public}s，%{public}d 秒后第 %{public}d 次重试',
      result.status, conversationId, delaySeconds, attempt + 1);
    await sleep(delaySeconds * 1000);
    // 重入走完整主流程（守卫全重查——退避窗口内用户改名/行删除由两道守卫兜住）
    await runTitleGeneration(conversationId, attempt + 1);
    return;
  }
  hilog.warn(DOMAIN, TAG, '标题请求最终失败放弃 conv=%{public}s status=%{public}d：%{public}s',
    conversationId, result.status, result.errorMessage);
}

// 单级验证结果（TitleApi 入参直取；keyIds = 启用序——发送取首支；★ 2026-09-08 记忆域起
// 导出——MemoryGen 复用同款验证〔同一模型键，标准单一来源〕，导出零行为变化不牵断言；
// ★ 2026-09-10 费用估计起带 providerId——标题/记忆两链落用途账本要归属服务商快照）
export interface TitleEndpoint {
  providerId: string;
  baseUrl: string;
  protocol: string;
  endpoint: string;
  modelId: string;
  keyIds: string[];
}

// 标题模型单级验证（tryCandidate 同级标准独立实现——该函数为 ProviderDb 模块私有，
// 本层用现成 export 自行组合；标准 = 服务商存在且启用 + 模型为该服务商启用对话模型 +
// key 池非空；null = 验证不通过 = 配置类失败放弃。★ 2026-09-08 记忆域起导出供 MemoryGen
// 复用——同一标题生成模型键的同款验证，抽公共域件收益为零〔一处调用方〕，导出即单一来源）
export async function resolveTitleEndpoint(providerId: string,
  modelId: string): Promise<TitleEndpoint | null> {
  const providers = await queryProviders();
  const provider: ProviderRow | undefined =
    providers.find((row: ProviderRow): boolean => row.id === providerId && row.enabled);
  if (provider === undefined) {
    return null;
  }
  const chatModels: ModelRow[] = (await queryModels(provider.id, 'chat'))
    .filter((row: ModelRow): boolean => row.enabled); // 停用模型不参与（tryCandidate 同口径）
  const model: ModelRow | undefined =
    chatModels.find((row: ModelRow): boolean => row.modelId === modelId);
  if (model === undefined) {
    return null;
  }
  const keyIds: string[] = await queryEnabledKeyIds(provider.id);
  if (keyIds.length === 0) {
    return null;
  }
  return {
    providerId: provider.id,
    baseUrl: provider.baseUrl,
    protocol: provider.protocol,
    endpoint: provider.endpoint,
    modelId: model.modelId,
    keyIds: keyIds
  };
}

// 对话内容拼接：最近 4 条 user/assistant 消息（tool 行剔除；空内容跳过），
// 每条截 500 字符加 …，`user: 内容` / `assistant: 内容` 逐行（RikkaHub summaryAsText 同构）
export function buildTitleContent(messages: MessageRow[]): string {
  const picked: MessageRow[] = [];
  for (const m of messages) {
    if ((m.role === 'user' || m.role === 'assistant') && m.content !== '') {
      picked.push(m);
    }
  }
  const tail: MessageRow[] = picked.slice(-TITLE_INPUT_MESSAGES);
  const lines: string[] = [];
  for (const m of tail) {
    const text: string = m.content.length > TITLE_INPUT_CHAR_LIMIT ?
      m.content.substring(0, TITLE_INPUT_CHAR_LIMIT) + '…' : m.content;
    lines.push(m.role + ': ' + text.replace(/\s+/g, ' ').trim());
  }
  return lines.join('\n');
}

// 标题清洗（Cube cleanTitle 全套）：去 <think> 标签 → 首尾引号 → 取首个非空行 →
// 去「标题：」类前缀 → 压空格。超长不硬截（拍板：模型偶发超长可接受，硬截会产生怪标题）
// 导出 = 断言资产消费（sse-assert ㉘ 组 node 直跑本实现；下三函数同——IO 编排函数不在此列）
export function cleanTitle(raw: string): string {
  let text: string = raw.replace(/<think>[\s\S]*?<\/think>/g, '');
  text = text.trim();
  text = stripWrappingQuotes(text);
  // 取首个非空行（推理模型首行可能为空/多行输出取第一行——Cube 同款）
  const lines: string[] = text.split('\n');
  let firstLine: string = '';
  for (const line of lines) {
    if (line.trim() !== '') {
      firstLine = line.trim();
      break;
    }
  }
  text = firstLine;
  // 去「标题：」「Title:」类前缀（中英冒号两形）
  text = text.replace(/^(?:标题|题目|title|Title)\s*[:：]\s*/, '');
  return text.replace(/\s+/g, ' ').trim();
}

// 首尾配对引号剥离（一层——模型偶发双包裹时循环剥净）
function stripWrappingQuotes(text: string): string {
  const pairs: string[][] = [['"', '"'], ['「', '」'], ['『', '』'], ['“', '”'], ['‘', '’']];
  let out: string = text;
  let stripped: boolean = true;
  while (stripped && out.length >= 2) {
    stripped = false;
    for (const pair of pairs) {
      if (out.startsWith(pair[0]) && out.endsWith(pair[1])) {
        out = out.substring(1, out.length - 1).trim();
        stripped = true;
        break;
      }
    }
  }
  return out;
}

// 标题有效性（Cube isValidTitle 同义）：非空且非全标点/空白——至少一个非标点字符
export function isValidTitle(title: string): boolean {
  if (title === '') {
    return false;
  }
  const punctRe = /[.,!?;:、。，！？；："'`「」『』（）()\[\]【】{}<>《》~@#%^&*_+=\-|\\/…·—\s]/;
  for (let i = 0; i < title.length; i++) {
    if (!punctRe.test(title.charAt(i))) {
      return true;
    }
  }
  return false;
}

// retryable 判定（Cube 同义）：网络错误(-1) / 5xx 服务端错误 / 429 限流 = 可退避重试；
// 401/403 鉴权与 400 等请求类 = 配置问题重试无意义，不重试
export function isRetryable(status: number): boolean {
  return status === -1 || status === 429 || status >= 500;
}

// 失败恢复型退避等待（重试链专用——非 P1-3 禁的冗余等待）
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

// 标题刷新广播：CONV_TITLE_TICK_KEY 单键 tick 递增（订阅侧一处——ChatSessionList 刷新列表
// 行；common 层不反向 import components 常量，列表既有 SESSION_LIST_RELOAD_KEY 的写点不动，
// ChatSessionList 另订阅本键即收口。★ 2026-09-09 对话页标题显示退役，其订阅点一并删除）
function broadcastTitleRefresh(): void {
  AppStorage.setOrCreate<number>(CONV_TITLE_TICK_KEY,
    (AppStorage.get<number>(CONV_TITLE_TICK_KEY) ?? 0) + 1);
}
