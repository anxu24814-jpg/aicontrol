// 模型能力注册表 + 思考策略画像表（2026-09-03 Cube 兼容画像与模型匹配引擎吸收，任务书
// docs/任务书-Cube兼容画像与模型匹配引擎吸收-20260903.md；01 卷 = docs/cube调研/
// 01-协议转换适配层.md §二③/§四 A1+A2 吸收规格）。
// 来源：Cube registry 六件（MIT，上游 services/registry/ 目录的 types/matcher/
// ModelAbilityRegistry/ProviderProfileRegistry/ModelProfileRegistry/CompatibilityResolver）
// 翻译 + ArkTS 化。抄机制不抄形态——Cube
// 单例可变流状态与 5005 行巨石组织不搬（01 卷 C1 明令），本文件为纯静态表 + 纯函数。
//
// ★ 零 import 契约：scripts/sse-assert.mjs 复制本文件直跑（同 SseParser/RequestCompose
// 范式）——禁加任何 import。协议/端点串常量与 AiTypes.PROTOCOL_*/ENDPOINT_* 同值同义，
// 零 import 约束下本地承载（MR_ 前缀防混），改动须两侧 grep 同步。
//
// A1 模型能力注册表：modelId 分词 + 顺序子序列评分匹配（lookupModelAbilities）替代手工
// caps 勾选——未手改的模型能力由模型名自动派生、规则升级自动跟随，用户手改即固定覆盖
//（覆盖事实存 DB caps_user_modified 列，派生值不落库读时派生；effectiveCapsOf 为派生/
// 覆盖语义单一实现，ProviderDb.effectiveCaps 薄壳消费）。
//
// ★ 上下文窗口参考值（2026-09-17 随 DB v33 模型上下文窗口配置新增）：DEFS 的 def 行可带
// contextWindow（窗口总容量 token 数），查询入口 lookupContextBaseline——与能力链同构的
// 「参考值不落库读时派生 / 用户覆盖落 DB provider_models.context_window」范式。
// 数据纪律（改值前必读）：①**两级值来源**——**一级 = 厂商官方文档**（值旁注释注明出处与
// 核对日期，对齐日 2026-09-17；与二级冲突时一级胜），**二级 = models.dev**（opencode 团队
// 维护的开源聚合库，`https://models.dev/api.json` 免鉴权 JSON，快照核对日 2026-09-17；
// 第三方口径，只在该行无一级值时采用，注释标 [md]）；②核实不到、或同族多型号窗口不同而
// 本行都会命中的，一律留 0（UI 走「暂无参考值」）——宁可缺不可错；③**取值规则（2026-09-17
// 决明拍板统一，改值前先读）**：**厂商给了明确数就照抄**——官方精确数（1,048,576 / 1,050,000）
// 与二级快照的明确值（claude / qwen / deepseek 系 1,000,000、doubao 256,000、glm-5.1 200,000、
// glm-4.6 / 4.7 与 MiniMax 系 204,800）同属此类；**只有「厂商只给单位表述、且二级也没给数」
// 时**才按本项目 k=1024、m=1024² 换算兜底。故本表二进制与十进制并存（gemini 1,048,576、
// kimi 262,144 与 1,048,576 是厂商真实口径）——**数字不同不是笔误**，是各厂商各自的申报数；
// **二级值原样照抄、不做换算**（不替第三方改写数字）；④只填「上下文窗口
// 总容量」，不是最大输出、不是单次输入上限；⑤**非对话行留 0**——图像/视频生成模型的
// models.dev limit.context 非对话窗口口径（如 grok-imagine-video 给 1024），填了误导，
// 本表生成类行一律不填；⑥**族内型号窗口不同 → 加「精化行」，不给泛行填值**：精化行须与
// 既有命中行的 abilities/input/output **逐字相同**（只换窗口值）——否则会改动派生 caps；
// 取胜靠更长的 tokens 序列（得分 = specTokens.length，泛行仍是未列型号的兜底）；单枚变体
// 差异（如 gpt-5.4-mini 400K vs gpt-5.4 1.05M、各家 -tts / -chat-latest 变体）不为每枚
// 变体加行，只在族注释记「差异族」；⑦**未列型号不加行**：命中不到任一 def 行的 id（如
// claude-sonnet-5 / doubao-seed-2-x / MiniMax-M3 / gemini-flash-lite-latest / grok-build-0.1）
// 不加行——新行会把它从「无能力派生」变成「按新行派生」，属能力面改动，超出「只落窗口值」
// 范围（各家族注释已列明本笔跳过哪些 id，留待专门笔查证能力后再加）。
// ★ 两处口径各管一边（2026-09-17 拍板同批）：**用户输入的 k / m 简写与快捷档 chips 恒按
// k=1024**（卡片小字对用户明写「k 等于 1024」，见 ModelContextCard），**参考值只反映厂商
// 申报数**——两者不必相等（如 grok-4.5 参考值 500,000 而 chips「500K」= 512,000）。

// ★ 单位表述的口径差异（2026-09-17 拍板统一后定稿）：各厂商申报口径本就二进制 / 十进制
// 混用——gemini / kimi 系 = 1,048,576 与 262,144（厂商真实口径），claude / qwen / deepseek /
// doubao / glm-5.1 系 = 1,000,000 / 256,000 / 200,000（十进制申报数），故同样写「1M」的行
// 在本表并存两种落值，**这不是笔误**；判据 = 头注释纪律③「厂商给了明确数就照抄」。

//
// A2 思考策略画像表：provider × 模型二维画像（first-match-wins + 表尾按协议兜底）取代
// 原 THINKING_OFF_DOMAINS 散落域名表——「关闭思考」判定（AiTypes.supportsThinkingOff
// 内部改查本表）、思考策略解析（resolveReasoningStrategy）与思考菜单选项集派生
//（thinkingOptionsFor）归一。★ 2026-09-06 模型级精化：match 加模型 id 维（可选，
// 不写 = 不约束）——Kimi K3/k2.7-code 参数体系模型级分裂实锤（官方文档 + 决明真机），
// 详见表注释。
//
// 裁剪口径（01 卷 A1/A2 + 任务书 1.b，均有消费面才落）：
// - DEFS 只留预置 12 家相关模型族（openai/gemini/claude/deepseek/qwen/doubao/grok/kimi/
//   glm/minimax）；Cube 的 step/internlm/mimo 三族裁除（本项目预置与模板均无）。
// - IMAGE_GEN_TOOL 能力与相关 def 不移植（Responses hosted tool 非本项目能力——01 卷 C7
//   同族），gpt-5 系 def 相应剥该能力。
// - ModelProfileRegistry 模型级精化簇整体不移植（startsWith 匹配形态等同族机制不搬）；
//   ★ 2026-09-06 起 A2 表自带模型维精化（match 可选模型字段）——原「本期 provider 级
//   拍板」口径被 Kimi 模型级分裂证伪作废（见表注释），DeepSeek V4 high/max 收敛类
//   精化同走加行。
// - 画像表 = DeepSeek 官方行（openai/anthropic 两协议形态）+ 三协议兜底行；★ 2026-09-06
//   增智谱 GLM / 月之暗面 Kimi 官方 openai 形态行（两家官方文档实锤同形开关方言，消费面 =
//   关闭思考菜单显隐与发送链）；其余长尾（MiniMax/OpenRouter/DashScope/硅基/MiMo 等）
//   未查证不预支。
// ★ 加行即接扩展点：新厂商方言 = REASONING_PROFILES 加一行（match 维度内 OR、维度间
//   AND，first-match-wins，更具体的行放前面）；新模型族能力 = DEFS 加一条 def——零业务层改动。
//
// 匹配引擎（自 Cube matcher.ets 翻译）：tokenize 分词（小写字母段/数字段/其余单字符）+
// sequenceMatch 顺序子序列（允许 token 间间隔，得分 = specTokens.length）+ 正则 token
//（^ 开头 / $ 结尾形态）。正则取舍：匹配内即时 new RegExp（Cube 同款）——DEFS 含正则
// token 的 def 仅 1 条（^o$ ^\d+$），调用点为模型入库与编辑页展示（非请求热路径），预编译
// 缓存需额外 spec→RegExp 映射结构，收益趋零不做。

// ── 串常量表（enum 不用——同 AiTypes.PROTOCOL_* 串常量姿态）──
// 导出面：仅查询函数族 + STRATEGY_DEEPSEEK_THINKING（任务 3 判定消费）+ 断言直跑所需
//（tokenize/子序列/规范化——sse-assert 复制直跑消费，同 SseParser 导出先例）；
// 其余常量为表数据内部承载。

// 模型能力（A1 派生源；CAP 码映射见 deriveCapsFromAbilities）
const ABILITY_TOOL: string = 'tool';
const ABILITY_REASONING: string = 'reasoning';
// 模型本身输出图（dall-e/imagen/gemini image 系等，派生「图片生成」码）
const ABILITY_IMAGE_GENERATION: string = 'image_generation';
// IMAGE_GEN_TOOL（Responses hosted tool）不移植——见头注释裁剪口径

// 模态
const MODALITY_TEXT: string = 'text';
const MODALITY_IMAGE: string = 'image';

// 思考策略值域（AiConnection.reasoningStrategy 载荷；resolveReasoningStrategy 产出）：
// 'none' | 'openai_effort' | 'deepseek_thinking' | 'anthropic_effort' | 'google_thinking'
// （值域文档；仅 deepseek_thinking 有外部判定消费——工厂/发送守卫经 AiTypes 门面引）
export const STRATEGY_DEEPSEEK_THINKING: string = 'deepseek_thinking';
const STRATEGY_NONE: string = 'none';
const STRATEGY_OPENAI_EFFORT: string = 'openai_effort';
const STRATEGY_ANTHROPIC_EFFORT: string = 'anthropic_effort';
const STRATEGY_GOOGLE_THINKING: string = 'google_thinking';

// 协议/端点（与 AiTypes.PROTOCOL_*/ENDPOINT_* 同值——零 import 本地承载，见头注释）
const MR_PROTOCOL_OPENAI: string = 'openai';
const MR_PROTOCOL_ANTHROPIC: string = 'anthropic';
const MR_PROTOCOL_GEMINI: string = 'gemini';
const MR_ENDPOINT_CHAT: string = 'chat';
const MR_ENDPOINT_RESPONSES: string = 'responses';

// caps 码（与 ProviderDb.MODEL_CAP_CODES 对齐：'web' 无注册表来源永不派生——01 卷 A1 明令）
const CAP_CODE_TOOL: string = 'tool';
const CAP_CODE_REASON: string = 'reason';
const CAP_CODE_VISION: string = 'vision';
const CAP_CODE_IMAGE: string = 'image';

// ── 匹配 DSL（自 Cube types.ets 裁剪：只留两表实际消费的字段集）──

// Model 命中条件：同一 def 内多个 spec AND（全部命中才整 def 命中）。
// startsWith 匹配形态不移植（Cube 侧属 ModelProfileRegistry 模型精化域概念），能力表
// DEFS 零消费（Cube ModelAbilityRegistry.scoreSpec 同样无此分支）；★ A2 画像表模型维
// 用前缀/精确匹配（ReasoningProfileMatchSpec 自承载，2026-09-06），与本 DSL 无涉
interface ModelMatchSpec {
  tokens?: string[]; // tokenize 后顺序子序列命中（允许 token 间间隔）；支持 ^/$ 正则 token
  notTokens?: string[]; // 顺序子序列 *不* 命中（排除族，如 gpt-5 排除 gpt-5-chat）
  exactId?: string; // modelId 与本字段（不区分大小写）完全相等
}

interface ModelAbilityDef {
  match: ModelMatchSpec[];
  abilities: string[];
  input: string[];
  output: string[];
  // 上下文窗口参考值（2026-09-17 DB v33 模型上下文窗口配置新增）：该行命中模型的
  // 上下文窗口总容量（token 数，输入+输出合计口径——不是最大输出、不是单次输入上限）。
  // 0/缺省 = 无参考值（UI 显示「暂无参考值」，不猜口径）。★ 来源约束：只填已联网核实
  // 厂商官方文档现值的行、值旁注释注明出处与核对日期；核不到的行留 0（宁可缺不可错）
  contextWindow?: number;
}

// Provider 命中条件：维度内 OR、维度间 AND（2026-09-06 模型级精化前为「三维 OR 任一命中
// 即整 spec 命中」——既有行均只写 baseUrlIncludesAny 单字段，新语义下逐字节等价）：
// 服务商维 = providerIds/baseUrlIncludesAny/baseUrlEqualsAny 任一命中；模型维 =
// modelIdPrefixesAny/modelIdEqualsAny 任一命中；某维字段全未写 = 该维不约束（恒真）。
// providerIds 为加行即接预留（本期调用方无 provider 身份，恒传 ''——见 matchReasoningSpec）
interface ReasoningProfileMatchSpec {
  providerIds?: string[];
  baseUrlIncludesAny?: string[]; // 规范化 baseUrl 子串（任一）
  baseUrlEqualsAny?: string[]; // 规范化 baseUrl 严格相等（任一）
  modelIdPrefixesAny?: string[]; // 规范化模型 id 前缀（任一；表值须小写——匹配前模型 id 已小写化）
  modelIdEqualsAny?: string[]; // 规范化模型 id 精确相等（任一）
}

interface ReasoningProfileDef {
  protocol: string; // MR_PROTOCOL_* 之一（强制匹配）
  match: ReasoningProfileMatchSpec;
  strategy: string; // STRATEGY_* 之一
  // 缺省 true；false = 本行模型恒思考/关不掉（K3 不收 thinking 参数、k2.7-code 传
  // disabled 必 400、GLM 强制系）——菜单摘「关闭」档 + 存量 off 值非法化回默认
  supportOff?: boolean;
  // 档位菜单判据（2026-09-11 立，三类摘法；逐模型/族查官方参数页后落行）：
  //   ①官方无此档位（如 GLM-4.5/4.6 无 reasoning_effort 字段）→ 摘该档；
  //   ②官方明示等价冗余（如 GLM-5.2 官方「low/medium 映射为 high」，low 无独立强度语义）
  //     → 摘冗余档——菜单不展示「选了等于别档」的诱饵项；
  //   ③官方禁关闭 → 走 supportOff: false（见上行字段），不占本字段。
  // 总纲 = 菜单只出现「在本模型上有独立语义的官方合法档位」；官方未明写的档位保留原样（不猜
  // 口径）——能保证的只是「不出现官方明确说不合法或明确说等价的档位」，不是「菜单档位与
  // 实际强度永远一致」。★ 只摘不补：官方档位多于我方值域时（如 GLM-5.2 的 xhigh/minimal）
  // 不扩充本常量值域——扩值域要动 THINKING_OPTIONS + 发送链 + 存量字段，属跨域改动。
  // 缺省 undefined = 思考菜单全量选项集（AiTypes.THINKING_OPTIONS 同值常量本地承载）；
  // 显式 = 选项集收窄（如 K2.x 不支持 reasoning_effort → 摘 low/high/max；GLM-5.2 摘 low）
  menuOptions?: string[];
}

interface ReasoningProfileFallback {
  protocol: string;
  strategy: string;
}

// ── 匹配引擎（自 Cube matcher.ets + ModelAbilityRegistry.ets 合一翻译；spec 分支序与
// Cube 能力表 scoreSpec 逐行对齐：exactId → notTokens → tokens）──

const EXACT_BONUS: number = 1000;

// 规范化 baseUrl：trim + 小写 + 去尾斜杠（Cube 同款，仅去一个；断言直跑消费）
export function normalizeModelRegistryBaseUrl(baseUrl: string): string {
  let normalized: string = baseUrl.trim().toLowerCase();
  if (normalized.endsWith('/')) {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}

function isLowerLetter(code: number): boolean {
  return code >= 97 && code <= 122; // a-z
}

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57; // 0-9
}

// modelId 分词：小写字母段 / 数字段 / 其余单字符（'-' '.' '/' 等各成单 token）
export function tokenizeModelId(modelId: string): string[] {
  const tokens: string[] = [];
  const input: string = modelId.toLowerCase();
  let i: number = 0;
  while (i < input.length) {
    const code: number = input.charCodeAt(i);
    if (isLowerLetter(code)) {
      const start: number = i;
      i++;
      while (i < input.length && isLowerLetter(input.charCodeAt(i))) {
        i++;
      }
      tokens.push(input.substring(start, i));
    } else if (isDigit(code)) {
      const start: number = i;
      i++;
      while (i < input.length && isDigit(input.charCodeAt(i))) {
        i++;
      }
      tokens.push(input.substring(start, i));
    } else {
      tokens.push(input.charAt(i));
      i++;
    }
  }
  return tokens;
}

// 顺序子序列：modelTokens 按序包含 specTokens 即命中（允许间隔），得分 = specTokens.length
// 正则 token（^ 开头或 $ 结尾）按 RegExp 整 token 测试（大小写不敏感——取舍见头注释）
export function sequenceMatchLength(modelTokens: string[], specTokens: string[]): number | null {
  if (specTokens.length === 0) {
    return null;
  }
  let si: number = 0;
  for (let i = 0; i < modelTokens.length; i++) {
    const spec: string = specTokens[si];
    let matched: boolean = false;
    if (spec.startsWith('^') || spec.endsWith('$')) {
      matched = new RegExp(spec, 'i').test(modelTokens[i]);
    } else {
      matched = modelTokens[i] === spec;
    }
    if (matched) {
      si++;
      if (si === specTokens.length) {
        return specTokens.length;
      }
    }
  }
  return null;
}

function lowerAll(spec: string[]): string[] {
  const lowered: string[] = [];
  for (let i = 0; i < spec.length; i++) {
    lowered.push(spec[i].toLowerCase());
  }
  return lowered;
}

// 单 spec 评分（null = 不命中）；notTokens 命中其排除族 = null、未命中 = 0 分
function scoreModelSpec(modelId: string, modelTokens: string[], spec: ModelMatchSpec): number | null {
  if (spec.exactId !== undefined) {
    return modelId.toLowerCase() === spec.exactId.toLowerCase() ? EXACT_BONUS + modelTokens.length : null;
  }
  if (spec.notTokens !== undefined && spec.notTokens.length > 0) {
    return sequenceMatchLength(modelTokens, lowerAll(spec.notTokens)) === null ? 0 : null;
  }
  if (spec.tokens !== undefined && spec.tokens.length > 0) {
    return sequenceMatchLength(modelTokens, lowerAll(spec.tokens));
  }
  return null;
}

// def 内多 spec AND 累加总分（任一 spec 不中即整 def 不中）
function scoreModelDef(modelId: string, modelTokens: string[], def: ModelAbilityDef): number | null {
  if (def.match.length === 0) {
    return null;
  }
  let total: number = 0;
  for (let i = 0; i < def.match.length; i++) {
    const score: number | null = scoreModelSpec(modelId, modelTokens, def.match[i]);
    if (score === null) {
      return null;
    }
    total += score;
  }
  return total;
}

// 最高分命中、并列取首（遍历序即声明序）；无命中返回 null
function lookupBestDef(modelId: string, defs: ModelAbilityDef[]): ModelAbilityDef | null {
  const modelTokens: string[] = tokenizeModelId(modelId);
  let bestScore: number | null = null;
  let bestDef: ModelAbilityDef | null = null;
  for (let i = 0; i < defs.length; i++) {
    const score: number | null = scoreModelDef(modelId, modelTokens, defs[i]);
    if (score === null) {
      continue;
    }
    if (bestScore === null || score > bestScore) {
      bestScore = score;
      bestDef = defs[i];
    }
  }
  return bestDef;
}

// ── A1 能力声明表 DEFS（自 Cube ModelAbilityRegistry.ets 裁剪翻译，剥 IMG_TOOL——
// 头注释裁剪口径；族序与 def 序照 Cube，并列取首语义下顺序即优先级）──

const MR_T: string = MODALITY_TEXT;
const MR_I: string = MODALITY_IMAGE;

// ★ 2026-09-17 第五参 contextWindow（上下文窗口参考值）：**给值时须写满前四参**
//（def(match, abilities, [MR_T, MR_I], [MR_T], 128000)）——既有行有只传两参的形态
//（input/output 取缺省），直接 def(match, abilities, 128000) 会把数组位传成数字 = 类型错
function def(match: ModelMatchSpec[], abilities: string[], input: string[] = [MR_T],
  output: string[] = [MR_T], contextWindow: number = 0): ModelAbilityDef {
  const d: ModelAbilityDef = {
    match: match, abilities: abilities, input: input, output: output, contextWindow: contextWindow
  };
  return d;
}

const MODEL_ABILITY_DEFS: ModelAbilityDef[] = [
  // --- OpenAI ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实，出处见本段注释；口径 = 窗口总容量）
  // 一级：gpt-5 / 5.1 / 5.2 = 400K、gpt-5.4 / 5.5 = 1,050,000（OpenAI 官方模型页
  // developers.openai.com/api/docs/models/*，2026-09-17 核对；二级 md 对这些 id 同值）。
  // 二级补面 [md]：gpt-4o 系 128,000、gpt-4.1 系 1,047,576、o 系（o1 / o1-pro / o3 /
  // o3-mini / o3-pro / o4-mini）200,000。
  // 差异族（不为变体改值 / 加行）：gpt-5.2-chat-latest 128K、gpt-5.3-codex-spark 128K、
  // gpt-5.4-mini 与 -nano 400K——变体值与主行值不同，主行值仍对多数 id 成立。
  // 生成类行（gpt-image / dall-e）留 0：见头注释纪律⑤（非对话窗口口径）
  // ★ gpt-5.3 有意留 0：两个变体窗口不同——gpt-5.3-chat-latest 128K（官方模型页标注已
  // 弃用；md 同值）/ gpt-5.3-codex 400K（md 同值）——本行两个变体都会命中（判据只到
  // tokens ['gpt','5','3']），任填一个必错其一，故留「暂无参考值」；其一已弃用故不加行
  def([{ tokens: ['gpt', 'image'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_I]),
  def([{ tokens: ['dall', 'e'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_I]),
  def([{ exactId: 'dall-e-3' }], [ABILITY_IMAGE_GENERATION], [MR_T], [MR_I]),
  def([{ exactId: 'dall-e-2' }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_I]),
  def([{ tokens: ['gpt', '4', 'o'] }], [ABILITY_TOOL], [MR_T, MR_I], [MR_T], 128000),
  def([{ tokens: ['gpt', '4', '1'] }], [ABILITY_TOOL], [MR_T, MR_I], [MR_T], 1047576),
  def([{ tokens: ['^o$', '^\\d+$'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 200000),
  def([{ tokens: ['gpt', 'oss'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['gpt', '5'] }, { notTokens: ['gpt', '5', '.'] }, { notTokens: ['gpt', '5', 'chat'] }],
    [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 400000),
  def([{ tokens: ['gpt', '5', '1'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 400000),
  def([{ tokens: ['gpt', '5', '2'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 400000),
  def([{ tokens: ['gpt', '5', '3'] }], [ABILITY_TOOL], [MR_T, MR_I]),
  def([{ tokens: ['gpt', '5', '4'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1050000),
  def([{ tokens: ['gpt', '5', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1050000),

  // --- Gemini ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实）：2.5 Pro / 2.5 Flash / 3 Pro / 3 Flash /
  // 3.1 Pro Preview 均为 1,048,576（一级：Google 官方模型页给 3.1 Pro Preview 输入上限
  // 1,048,576；Vertex AI 对照表同值覆盖 2.5/3.x 族；二级 md 对 2.5/3.x 族同值）。
  // 二级补面 [md]：gemini-flash-latest = 1,048,576。★ 仍留 0 的两处：gemini-pro-latest
  //（md 无此 id）、2.0 Flash（md 无此 id）——两源都核不到现值。生成类行（2.5-flash-image /
  // 3-pro-image / 3.1-flash-image / imagen）留 0：见头注释纪律⑤（md 给 32768/65536/131072，
  // 属图像生成口径非对话窗口）；差异族：各 -tts 变体 8192、3.1-flash-live-preview 131072
  def([{ tokens: ['gemini', '2', '0', 'flash'] }], [ABILITY_TOOL], [MR_T, MR_I]),
  def([{ tokens: ['gemini', '2', '5', 'flash'] }, { notTokens: ['image'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),
  def([{ tokens: ['gemini', '2', '5', 'pro'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),
  def([{ tokens: ['gemini', '2', '0', 'flash', 'preview', 'image'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_T, MR_I]),
  def([{ tokens: ['gemini', '2', '5', 'flash', 'image'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_T, MR_I]),
  def([{ tokens: ['gemini', '3', 'pro', 'image'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_T, MR_I]),
  def([{ tokens: ['gemini', '3', 'pro'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),
  def([{ tokens: ['gemini', '3', 'flash'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),
  def([{ tokens: ['gemini', '3', '1', 'flash', 'image'] }], [ABILITY_REASONING, ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_T, MR_I]),
  def([{ tokens: ['imagen'] }], [ABILITY_IMAGE_GENERATION], [MR_T], [MR_I]),
  def([{ tokens: ['gemini', '3', '1', 'pro', 'preview'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),
  def([{ exactId: 'gemini-flash-latest' }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),
  def([{ exactId: 'gemini-pro-latest' }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),

  // --- Claude ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实）：Sonnet 4.6 / Opus 4.6 / Opus 4.7 = 1M
  //（一级：Anthropic 官方 context-windows 页：1M 自 2026-03-13 GA，无长上下文加价；Sonnet 4.6
  // 另有 200K 标准档口径——本行取官方列示的窗口值）。★ 取值按二级口径落 1,000,000：官方只
  // 写「1M」未给精确数，二级快照对全部 claude id 给十进制 1,000,000（若按本表 k=1024 换算
  // 会得 1,048,576）——厂商十进制/二进制混用的口径差异见头注释「单位表述的口径差异补记」。
  // 二级补面 [md]（4.5 系拆三枚精化行——族内窗口本就不同，泛行只能留 0）：sonnet-4-5 系
  // 1,000,000、opus-4-5 系 200,000、haiku-4-5 系 200,000（-20250929 / -20251101 等日期后缀
  // 变体同子序列命中，同值）；opus-4-8 系 1,000,000（md 2026-05-28 发布，是唯一命中泛行
  // ['claude','4'] 的 id，故为它加行）；泛行 ['claude','4'] 与 ['claude','4','5'] 由此仍留 0
  //（可落型号已各自拆行，泛行只剩未列型号兜底）。★ 未落行 = 命中不到任一 def 行的 id
  //（claude-sonnet-5 / opus-5 / fable-5 系，md 均 1M）——加行会改动派生 caps，超出本笔范围；
  // claude-3.5 / 3.7 sonnet 两行两源均无现值 → 留 0
  def([{ tokens: ['claude', '3', '5', 'sonnet'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),
  def([{ tokens: ['claude', '3', '7', 'sonnet'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),
  def([{ tokens: ['claude', '4'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),
  def([{ tokens: ['claude', '4', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),
  def([{ tokens: ['claude', 'sonnet', '4', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['claude', 'opus', '4', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 200000),
  def([{ tokens: ['claude', 'haiku', '4', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 200000),
  def([{ tokens: ['claude', 'sonnet', '4', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['claude', 'opus', '4', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['claude', 'opus', '4', '7'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['claude', 'opus', '4', '8'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),

  // --- DeepSeek ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实）：deepseek-v4-pro = 1,000,000（一级：官方定价页
  // api-docs.deepseek.com/quick_start/pricing 写 context 1M、未给精确数；二级 md 同 id 给十进制
  // 1,000,000 → 按纪律③「给了明确数就照抄」取值。★ 2026-09-17 口径统一笔：本行原为按 k=1024
  // 换算的 1,048,576，经决明拍板统一到厂商申报数，见变更记录七百零一节）。
  // 二级补面 [md]：v4-flash 系（含 -vision-exp 变体与火山方舟同名转发）= 1,000,000。
  // ★ 仍留 0 的行：deepseek-chat / deepseek-reasoner / v3 / v3.1 / v3.2 / r1——官方定价页
  // 现值已无这些 id（2025-08 的 128K 公告属历史版本口径），md 亦无覆盖 → 宁可缺不可错；
  // md 列出的 deepseek-flash（1,000,000）无同族 def 行可落（判据 ['deepseek','v','4','flash']
  // 命中不了 'deepseek-flash'），不为它加行——加行会改派生 caps，超出「窗口值吸收」范围
  def([{ tokens: ['deepseek', 'v', '3'] }], [ABILITY_TOOL]),
  def([{ tokens: ['deepseek', 'chat'] }], [ABILITY_TOOL]),
  def([{ tokens: ['deepseek', 'r', '1'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['deepseek', 'reasoner'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['deepseek', 'v', '4', 'flash'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 1000000),
  def([{ tokens: ['deepseek', 'v', '4', 'pro'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 1000000),
  def([{ tokens: ['deepseek', 'v', '3', '1'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['deepseek', 'v', '3', '2'] }], [ABILITY_TOOL, ABILITY_REASONING]),

  // --- Qwen ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实）：qwen3.5 / qwen3.6 = 1,000,000（一级：阿里云
  // 百炼官方模型页：qwen3.5-plus 上下文长度 1,000,000、最大输入 991,808；qwen3.6-plus 同。
  // 二级 md 对 qwen3.5-plus / qwen3.6-plus / qwen3.7-max / qwen3.8-max 等 API 型号同值）。
  // 二级补面 [md]：qwq-plus 131,072、qvq-max 131,072。
  // ★ 泛行 ['qwen','3'] 留 0：它同时命中 Qwen3-Max（262,144）与 Qwen3-Coder-Plus（1,048,576）
  // 等窗口不同的同族型号——md 对泛行命中集给出六种值（53248 / 65536 / 131072 / 262144 /
  // 1000000 / 1048576），任填一个必错其一；差异族：qwen3.5-* / qwen3.6-* 开放权重型号
  // 262,144（API 型号 qwen3.5-plus 1,000,000，主行值取 API 侧）
  def([{ tokens: ['qwen', '3'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['qwen', '3', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['qwen', '3', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['qwq'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 131072),
  def([{ tokens: ['qvq'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 131072),

  // --- 豆包 ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实）：doubao 1.8 = 256,000（一级：火山方舟官方模型
  // 文档 doubao-seed-1-8 写「上下文窗口 256K、最大输入 224K」未给精确数；二级 md 同族一律
  // 256,000 → 按纪律③照抄二级明确数。★ 2026-09-17 口径统一笔：本行原为按 k=1024 换算的
  // 262,144，经决明拍板统一到厂商申报数，见变更记录七百零一节）。
  // 二级补面 [md]：doubao 1.6 系（-flash / -vision 等变体同值）= 256,000（与 1.8 同口径）。
  // ★ doubao-seed-2-x 系（md 给 256,000）无同族 def 行可落，不加行（同 DeepSeek 注）
  def([{ tokens: ['doubao', '1', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 256000),
  def([{ tokens: ['doubao', '1', '8'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 256000),

  // --- Grok ---
  // ★ 上下文窗口参考值：xAI 官方 /v1/models 不返回 context_length（无一级来源）——按纪律⑥
  // 拆精化行落二级值 [md]：grok-4.3 系 1,000,000、grok-4.20 系 1,000,000、grok-4.5 与
  // grok-4.6 系 500,000。泛行 ['grok','4'] 仍留 0（族内 500000 / 1000000 两值冲突，留作
  // 未列型号的兜底）；grok-build-0.1（md 256,000）无同族 def 行可落，不加行。
  // 生成类行（grok-imagine-image / -video）留 0：见头注释纪律⑤（md 给 16000 / 64000 与
  // 1024，属图像/视频生成口径非对话窗口）
  def([{ tokens: ['grok', 'imagine', 'image'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_I]),
  def([{ tokens: ['grok', 'imagine'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_I]),
  def([{ tokens: ['grok', 'image'] }], [ABILITY_IMAGE_GENERATION], [MR_T, MR_I], [MR_I]),
  def([{ tokens: ['grok', '4', '3'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['grok', '4', '20'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1000000),
  def([{ tokens: ['grok', '4', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 500000),
  def([{ tokens: ['grok', '4', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 500000),
  def([{ tokens: ['grok', '4'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),

  // --- Kimi ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实）：k2.6 / k2.7 = 256K、k3 = 1M（一级：官方模型
  // 总览页 platform.kimi.com/docs/api/models-overview，2026-09-17 逐条读数；二级 md 对
  // k2.6 / k2.7-code 两 id 给 262144、对 k3 给 1048576——与一级换算值逐字同值）。
  // 泛行 ['kimi','k','2'] 与 k2.5 两源均无覆盖 → 留 0（官方该页现只列 k2.6 / k2.7-code / k3）
  def([{ tokens: ['kimi', 'k', '2'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['kimi', 'k', '2', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I]),
  def([{ tokens: ['kimi', 'k', '2', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 262144),
  // kimi-k2.7-code（含 -highspeed，前缀同覆盖）：工具 ✅ + 恒思考 ✅——官方思考模型页
  // 2026-09-11 查证：「kimi-k2.7-code 和 kimi-k2.6（启用思考能力时）都支持通过深度推理
  // 进行多步工具调用」「始终开启思考，且保留式思考（Preserved Thinking）始终开启」。
  // 视觉不落（不猜口径）：官方模型列表页（platform.kimi.com/docs/models）k2.7-code 条目
  // 无任何模态表述——对照同页 K2.6 明写「支持视觉与文本输入」，定价页「多模态模型」非
  // 明示不采。此前本模型由 k2 基础行 3 分子序列偶然命中（tool+reasoning 纯文本），显式
  // 4 分行落地后同能力取胜，派生结果零变化、仅消除偶然依赖。
  def([{ tokens: ['kimi', 'k', '2', '7'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 262144),
  // kimi-k3：工具 ✅ + 恒思考 ✅ + 视觉 ✅——官方 2026-09-11 查证：模型列表页与 K3
  // quickstart 均「原生支持视觉理解」（quickstart 带 image_url 输入示例；输入另含 video，
  // DEFS 模态体系无 video 不落）；思考模型页「始终进行推理且保留式思考始终开启」+
  // reasoning_effort low/high/max。此前无 def 命中 → 徽标全空（EMPTY_ABILITY_RESULT），
  // 本行落地后 tool/reason/vision 三徽标自动派生。
  def([{ tokens: ['kimi', 'k', '3'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T, MR_I], [MR_T], 1048576),

  // --- GLM ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实，一级：官方总览页 docs.z.ai/guides/overview/
  // overview 逐行读数）：GLM-4.5 = 131,072、GLM-4.6 = 204,800、GLM-4.7 = 204,800（二级 md
  // 对三行同值）；GLM-5.1 = 200,000（一级只写 200K、未给精确数，二级 md 给十进制 200,000 →
  // 按纪律③照抄；★ 2026-09-17 口径统一笔：本行原为按 k=1024 换算的 204,800，见七百零一节）。
  // 二级补面 [md]（泛行 ['glm','5'] 命中集三值冲突 → 按纪律⑥为旗舰拆精化行）：glm-5.2 系
  // 1,000,000、glm-5.3 系 1,000,000（含 -flash 变体与火山方舟同名转发）；泛行 ['glm','5']
  // 仍留 0（GLM-5 / 5v-turbo 200,000~204,800 vs 5.2 / 5.3 1,000,000）；差异族：glm-4.5v
  // 64000、glm-4.6v 128000、glm-4.7-flash 与 -flashx 200000（主行值对各自主型号成立）
  def([{ tokens: ['glm', '4', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 131072),
  def([{ tokens: ['glm', '4', '6'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 204800),
  def([{ tokens: ['glm', '4', '7'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 204800),
  def([{ tokens: ['glm', '5'] }], [ABILITY_TOOL, ABILITY_REASONING]),
  def([{ tokens: ['glm', '5', '1'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 200000),
  def([{ tokens: ['glm', '5', '2'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 1000000),
  def([{ tokens: ['glm', '5', '3'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 1000000),

  // --- MiniMax ---
  // ★ 上下文窗口参考值（2026-09-17 联网核实，一级：MiniMax 开放平台官方模型页
  // platform.minimaxi.com，含 -highspeed 变体同值）：M2.7 = 204,800。二级 md 对 M2 /
  // M2.1 / M2.5 / M2.7 四子族一律 204,800（与一级值逐字同值）→ 二级补面 [md]：泛行
  // ['minimax','m','2'] 204,800、M2.5 204,800。差异族 / 未覆盖：M3（md 1,048,576）无同族
  // def 行可落，不加行（同 DeepSeek 注）
  def([{ tokens: ['minimax', 'm', '2'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 204800),
  def([{ tokens: ['minimax', 'm', '2', '5'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 204800),
  def([{ tokens: ['minimax', 'm', '2', '7'] }], [ABILITY_TOOL, ABILITY_REASONING], [MR_T], [MR_T], 204800),
];

// ── A2 思考策略画像表（first-match-wins，更具体行在前；表尾按协议兜底）──
// DeepSeek 官方行（openai/anthropic 两协议形态——任务书 1.b）+ 三协议兜底行；2026-09-06
// 增智谱 GLM / 月之暗面 Kimi 官方 openai 形态行（两家官方文档实锤 thinking{type} 开关方言
// 与 DeepSeek 线形逐字节相同——策略值复用 deepseek_thinking〔历史命名，语义 = 该开关方言〕，
// compose/判定链零改动）。其余长尾方言（MiniMax/OpenRouter/DashScope/硅基/MiMo 等）
// 未查证不预支，加行即接。
// ★ 2026-09-06 模型级精化（决明真机实测引爆——原「模型级强制思考例外不入画像，off 传
// disabled 端侧报错走错误回显链」拍板作废）：实测 K3 收 thinking{type:disabled} 不报错——
// 官方文档（platform.kimi.com 思考模型页 + chat API 参数页）实锤 K3 不收 thinking 参数
//（「无需（也不应）传入」），其参数体系 = 顶层 reasoning_effort low/high/max（默认 max），
// 服务端对不适用字段宽容忽略 = 「关闭」静默无效（语义欺诈）；同族：k2.7-code 恒思考传
// disabled 必 400、K2.x 不支持 reasoning_effort。故 match 加模型维拆行精化（rikkahub
// issue #1573 同款坑同款修法，2026-07 先行参考）。K3 思维链另注：官方口径「始终推理……
// 并可能返回 reasoning_content」——不保证返回，无思考块 ≠ 解析 bug。
const REASONING_PROFILES: ReasoningProfileDef[] = [
  // DeepSeek 官方 openai 形态：thinking{type} 方言（off 判定与策略解析同源——原
  // THINKING_OFF_DOMAINS 域名表语义并入本行，supportsThinkingOff 改查此处）
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['api.deepseek.com'] },
    strategy: STRATEGY_DEEPSEEK_THINKING
  },
  // 智谱 GLM 官方 openai 形态四行（2026-09-11 档位合法性查证收口，docs.z.ai/guides/
  // capabilities/thinking 逐字实锤）：reasoning_effort「is only supported by GLM-5.2 and
  // above」且 GLM-5.3/5.3-FLASH「only max, high and low are supported. Any other input
  // will result in an error」；强制思考 = 「GLM-5.3, GLM-5.3-FLASH, GLM-4.7 and GLM-4.5V
  // use forced thinking」（5.3 系传 thinking{type:disabled} 报错），可关 = GLM-5.2/5.1/5/
  // 4.6/4.5（enabled 模式下自动判断是否思考）。四行 first-match-wins 依具体度降序：
  // A. GLM-4.7 / 4.5V 强制系：恒思考 + 官方不支持 reasoning_effort → 菜单仅「默认」，
  //    透传三档 = 静默无效故摘
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['open.bigmodel.cn'], modelIdPrefixesAny: ['glm-4.7', 'glm-4.5v'] },
    strategy: STRATEGY_DEEPSEEK_THINKING,
    supportOff: false,
    menuOptions: ['']
  },
  // B. GLM-5.3 系（前缀同覆盖 -FLASH 变体）：恒思考 + 官方合法档位恰为我方三档 → 缺省
  //    全量，「关闭」档由 supportOff 摘
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['open.bigmodel.cn'], modelIdPrefixesAny: ['glm-5.3'] },
    strategy: STRATEGY_DEEPSEEK_THINKING,
    supportOff: false
  },
  // C. GLM-5.2：可关（thinking.type disabled）+ effort 合法集为我方值域超集（max/xhigh/
  //    high/medium/low/minimal/none）；★ 摘 low——官方映射「low/medium 被映射为 high」，
  //    low 在本模型上无独立强度语义（选了等于选 high），按判据②摘等价冗余档（见
  //    menuOptions 字段注释）。余下 high/max 语义独立，菜单 = 默认/关闭/high/max
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['open.bigmodel.cn'], modelIdPrefixesAny: ['glm-5.2'] },
    strategy: STRATEGY_DEEPSEEK_THINKING,
    menuOptions: ['', 'off', 'high', 'max']
  },
  // D. GLM 官方 openai 形态兜底（GLM-4.5/4.6/5/5.1 等：官方仅承诺 thinking{type} 开关、
  //    无 reasoning_effort → 摘 low/high/max 三档防静默透传；强制系 4.7/4.5V/5.3 系见
  //    A/B 行）
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['open.bigmodel.cn'] },
    strategy: STRATEGY_DEEPSEEK_THINKING,
    menuOptions: ['', 'off']
  },
  // kimi-k3（含官方别名精确 'k3'）：恒思考 + 保留式思考恒开；不收 thinking 参数（传之
  // 宽容忽略 = 静默无效），参数体系 = 顶层 reasoning_effort low/high/max（默认 max）——
  // 纯 effort 方言；菜单摘「关闭」，三档枚举与我方档位值域逐字对齐（透传即生效）
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: {
      baseUrlIncludesAny: ['api.moonshot.cn', 'api.moonshot.ai'],
      modelIdPrefixesAny: ['kimi-k3'],
      modelIdEqualsAny: ['k3']
    },
    strategy: STRATEGY_OPENAI_EFFORT,
    supportOff: false,
    menuOptions: ['', 'low', 'high', 'max']
  },
  // kimi-k2.7-code（含 -highspeed 变体）：恒思考 + 保留式思考恒开，thinking 仅接受
  // enabled（传 disabled 必 400），不支持 reasoning_effort——无可调思考参数，菜单仅「默认」
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['api.moonshot.cn', 'api.moonshot.ai'], modelIdPrefixesAny: ['kimi-k2.7'] },
    strategy: STRATEGY_NONE,
    supportOff: false,
    menuOptions: ['']
  },
  // 月之暗面 Kimi 官方 openai 形态兜底（k2.5/k2.6：thinking{type} 开关方言同 DeepSeek）；
  // 官方 K2.x 请求参数表无 reasoning_effort 字段 → 摘 low/high/max 档位（防静默透传）；
  // api.moonshot.ai = 国际站同规格一并收录
  {
    protocol: MR_PROTOCOL_OPENAI,
    match: { baseUrlIncludesAny: ['api.moonshot.cn', 'api.moonshot.ai'] },
    strategy: STRATEGY_DEEPSEEK_THINKING,
    menuOptions: ['', 'off']
  },
  // DeepSeek 官方 anthropic 形态：显式落行（本期策略与兜底同 = anthropic_effort，为将来
  // DeepSeek anthropic 专属精化留位——加行即接点；GLM/Kimi anthropic 兼容端点未查证不落行）
  {
    protocol: MR_PROTOCOL_ANTHROPIC,
    match: { baseUrlIncludesAny: ['api.deepseek.com'] },
    strategy: STRATEGY_ANTHROPIC_EFFORT
  }
];

const REASONING_FALLBACKS: ReasoningProfileFallback[] = [
  // openai 族兜底（含官方与兼容中转）：effort 方言
  { protocol: MR_PROTOCOL_OPENAI, strategy: STRATEGY_OPENAI_EFFORT },
  // anthropic 兜底：effort 方言
  { protocol: MR_PROTOCOL_ANTHROPIC, strategy: STRATEGY_ANTHROPIC_EFFORT },
  // gemini 兜底：thinkingConfig 方言
  { protocol: MR_PROTOCOL_GEMINI, strategy: STRATEGY_GOOGLE_THINKING }
];

// 服务商维命中（三维 OR；字段全未写 = 不约束恒真）
function matchProviderDim(providerId: string, normalizedBaseUrl: string, spec: ReasoningProfileMatchSpec): boolean {
  let wroteAny: boolean = false;
  if (spec.providerIds !== undefined) {
    wroteAny = true;
    for (let i = 0; i < spec.providerIds.length; i++) {
      if (providerId === spec.providerIds[i]) {
        return true;
      }
    }
  }
  if (spec.baseUrlIncludesAny !== undefined) {
    wroteAny = true;
    for (let i = 0; i < spec.baseUrlIncludesAny.length; i++) {
      if (normalizedBaseUrl.includes(spec.baseUrlIncludesAny[i])) {
        return true;
      }
    }
  }
  if (spec.baseUrlEqualsAny !== undefined) {
    wroteAny = true;
    for (let i = 0; i < spec.baseUrlEqualsAny.length; i++) {
      if (normalizedBaseUrl === spec.baseUrlEqualsAny[i]) {
        return true;
      }
    }
  }
  return !wroteAny;
}

// 模型维命中（两维 OR；字段全未写 = 不约束恒真——2026-09-06 模型级精化新增）
function matchModelDim(normalizedModelId: string, spec: ReasoningProfileMatchSpec): boolean {
  let wroteAny: boolean = false;
  if (spec.modelIdPrefixesAny !== undefined) {
    wroteAny = true;
    for (let i = 0; i < spec.modelIdPrefixesAny.length; i++) {
      if (normalizedModelId.startsWith(spec.modelIdPrefixesAny[i])) {
        return true;
      }
    }
  }
  if (spec.modelIdEqualsAny !== undefined) {
    wroteAny = true;
    for (let i = 0; i < spec.modelIdEqualsAny.length; i++) {
      if (normalizedModelId === spec.modelIdEqualsAny[i]) {
        return true;
      }
    }
  }
  return !wroteAny;
}

// 整 spec 命中 = 服务商维 AND 模型维（维度语义见 ReasoningProfileMatchSpec 注释）
function matchReasoningSpec(providerId: string, normalizedBaseUrl: string, normalizedModelId: string,
  spec: ReasoningProfileMatchSpec): boolean {
  return matchProviderDim(providerId, normalizedBaseUrl, spec) && matchModelDim(normalizedModelId, spec);
}

// ── A1 查询结果与公开 API ──

export interface ModelAbilityResult {
  abilities: string[];
  inputModalities: string[];
  outputModalities: string[];
  // 上下文窗口参考值（2026-09-17 DB v33）：命中 def 行已核实的窗口值；0 = 无参考值
  // （未命中 def 或该行未填）。消费 = 编辑模型页「上下文窗口」卡参考值行
  contextWindow: number;
}

// 未命中任何 def = 全空（派生空 = 不误标——未知自定义模型能力维持手工）；input/output
// 兜底纯文本、contextWindow 0 = 无参考值。共享只读实例（调用方只读契约，Cube 同款）
const EMPTY_ABILITY_RESULT: ModelAbilityResult = {
  abilities: [],
  inputModalities: [MR_T],
  outputModalities: [MR_T],
  contextWindow: 0
};

// modelId → 能力三元组 + 窗口参考值（最高分 def；未知模型回 EMPTY_ABILITY_RESULT）
export function lookupModelAbilities(modelId: string): ModelAbilityResult {
  const best: ModelAbilityDef | null = lookupBestDef(modelId, MODEL_ABILITY_DEFS);
  if (best === null) {
    return EMPTY_ABILITY_RESULT;
  }
  const result: ModelAbilityResult = {
    abilities: best.abilities,
    inputModalities: best.input,
    outputModalities: best.output,
    contextWindow: best.contextWindow !== undefined ? best.contextWindow : 0
  };
  return result;
}

// 上下文窗口参考值查询（2026-09-17 DB v33，任务书-模型上下文窗口）：命中模型行 = 该行已
// 核实的窗口值；未命中 def / 命中但该行未填值 = 0（恒 0 = 「暂无参考值」——不猜口径）。
// ★ 参考值不落库：DB 只存用户覆盖值（provider_models.context_window，0 = 未配置），
// 未配置行读时经本函数按模型名派生（与能力 A1 链 caps_user_modified 同构）。
// ★ 运行期取值场景 = 编辑模型页载入/模型 ID 输入回调，禁进 build（宪法性能红线）
export function lookupContextBaseline(modelId: string): number {
  return lookupModelAbilities(modelId).contextWindow;
}

// ── A2 公开 API ──

// 规范化模型 id（画像模型维匹配前处理：trim + 小写；表值侧约束见 ReasoningProfileMatchSpec）
function normalizeModelId(modelId: string): string {
  return modelId.trim().toLowerCase();
}

// 画像行命中解析（2026-09-06 模型级精化唯一入口；first-match-wins 更具体行在前）。
// openai+responses 端点无画像行（官方 Responses 形态，DeepSeek 官方无此端点形态）与
// 未命中均返回 null——消费方按各自缺省语义处理（策略解析走协议兜底、off 判定 false、
// 菜单选项集全量）
export function resolveReasoningProfile(protocol: string, endpoint: string, baseUrl: string,
  modelId: string): ReasoningProfileDef | null {
  if (protocol === MR_PROTOCOL_OPENAI && endpoint === MR_ENDPOINT_RESPONSES) {
    return null;
  }
  const normalizedUrl: string = normalizeModelRegistryBaseUrl(baseUrl);
  const normalizedModel: string = normalizeModelId(modelId);
  for (let i = 0; i < REASONING_PROFILES.length; i++) {
    const row: ReasoningProfileDef = REASONING_PROFILES[i];
    if (row.protocol === protocol && matchReasoningSpec('', normalizedUrl, normalizedModel, row.match)) {
      return row;
    }
  }
  return null;
}

// 思考策略解析（唯一填充点 = ProviderDb.resolveActiveConnection → conn.reasoningStrategy）。
// provider × 模型二维判定（2026-09-06 模型级精化）：responses 端点无条件归 openai_effort；
// 其余 first-match 画像行 → 协议兜底 → none（未知协议串兜底，工厂同款兜底语义）。
// modelId 缺省 '' = 模型级行不命中（前缀/精确均假），退化 provider 级旧行为（安全方向）
export function resolveReasoningStrategy(protocol: string, endpoint: string, baseUrl: string,
  modelId: string = ''): string {
  const profile: ReasoningProfileDef | null = resolveReasoningProfile(protocol, endpoint, baseUrl, modelId);
  if (profile !== null) {
    return profile.strategy;
  }
  if (protocol === MR_PROTOCOL_OPENAI && endpoint === MR_ENDPOINT_RESPONSES) {
    return STRATEGY_OPENAI_EFFORT;
  }
  for (let i = 0; i < REASONING_FALLBACKS.length; i++) {
    if (REASONING_FALLBACKS[i].protocol === protocol) {
      return REASONING_FALLBACKS[i].strategy;
    }
  }
  return STRATEGY_NONE;
}

// 思考菜单全量缺省选项集（与 AiTypes.THINKING_OPTIONS 同值——零 import 契约本地承载，
// 断言 ㉕ 组钉等价；'' = 默认不传 / off = 关闭（显隐另受 offOk 闸）/ low/high/max 档位）
const MR_THINKING_OPTIONS_DEFAULT: string[] = ['', 'off', 'low', 'high', 'max'];

// 思考菜单选项集派生（按连接形态查画像）：命中行显式 menuOptions → 收窄集；否则全量
// 缺省（现状逐字节——responses 端点/未命中画像同）
export function thinkingOptionsFor(protocol: string, endpoint: string, baseUrl: string,
  modelId: string): string[] {
  const profile: ReasoningProfileDef | null = resolveReasoningProfile(protocol, endpoint, baseUrl, modelId);
  if (profile !== null && profile.menuOptions !== undefined) {
    return profile.menuOptions;
  }
  return MR_THINKING_OPTIONS_DEFAULT;
}

// 开关方言画像命中判定（恒查 openai chat 形态画像——「关闭思考」菜单显隐与 off 生效的
// 唯一判定源（AiTypes.supportsThinkingOff/connectionOffEnabled 改查此处）：命中 && 开关方言
// 策略 && 行级 supportOff 未禁）。★ 函数名为历史名——2026-09-06 起命中域 = DeepSeek/GLM/
// Kimi 三家官方域（thinking{type} 开关方言同形共享，见表注释）；同日晚叠加模型维（GLM
// 强制系 / kimi-k3/k2.7-code 关不掉 → false）。「与协议形态无关」语义维持：anthropic 形态
// DeepSeek 的 off（reasoning{effort:none}）经本判定同样为真
export function supportsDeepSeekProfile(baseUrl: string, modelId: string = ''): boolean {
  const profile: ReasoningProfileDef | null =
    resolveReasoningProfile(MR_PROTOCOL_OPENAI, MR_ENDPOINT_CHAT, baseUrl, modelId);
  return profile !== null && profile.strategy === STRATEGY_DEEPSEEK_THINKING && profile.supportOff !== false;
}

// ── A1 派生/覆盖语义（单一实现；ProviderDb.effectiveCaps 薄壳消费，sse-assert 直跑）──

// 能力三元组 → caps 码逗号串（按 MODEL_CAP_CODES 序 tool,reason,vision,image 派生；
// 'web' 无注册表来源永不派生——仅用户手改可设；「图片生成」码 = IMAGE_GENERATION 能力
// 或输出含 IMAGE）
export function deriveCapsFromAbilities(abilities: string[], inputModalities: string[],
  outputModalities: string[]): string {
  const codes: string[] = [];
  if (abilities.indexOf(ABILITY_TOOL) >= 0) {
    codes.push(CAP_CODE_TOOL);
  }
  if (abilities.indexOf(ABILITY_REASONING) >= 0) {
    codes.push(CAP_CODE_REASON);
  }
  if (inputModalities.indexOf(MODALITY_IMAGE) >= 0) {
    codes.push(CAP_CODE_VISION);
  }
  if (abilities.indexOf(ABILITY_IMAGE_GENERATION) >= 0 || outputModalities.indexOf(MODALITY_IMAGE) >= 0) {
    codes.push(CAP_CODE_IMAGE);
  }
  return codes.join(',');
}

// effectiveCaps 语义：capsUserModified = true → 用户 caps 原样（含全不勾的显式清空——
// 编辑即固化拍板）；false → 按模型名派生（规则升级自动跟随）。'web' 只能存在于用户 caps。
export function effectiveCapsOf(capsUserModified: boolean, caps: string, modelId: string): string {
  if (capsUserModified) {
    return caps;
  }
  const result: ModelAbilityResult = lookupModelAbilities(modelId);
  return deriveCapsFromAbilities(result.abilities, result.inputModalities, result.outputModalities);
}
