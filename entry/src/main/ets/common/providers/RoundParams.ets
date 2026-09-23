// 轮次请求参数解析域（2026-09-23 输出上限与超时治理笔 2 域级最小拆分）：一句话职责 =
// 「本轮请求参数解析——思考档位归一 + 采样字段组装 + 思考与输出上限联动」。方法体自
// components/chat/ChatSendCtrl.assembleRound 的思考档位段与采样段整体搬迁（判据逐句等价，
// 沿革注释随迁），本笔新增的上限联动一并落此；宿主只留一行调用（禁第二条请求链的锚点
// 仍在宿主 assembleRound 头注释）。
// ★ 拆出动因（宪法「单文件规模上限」判据）：ChatSendCtrl.ets 剔头 1198 行贴 1200 硬线，
// 本笔截断接线与上限联动净增必越线。为何不能并入既有件见 docs/变更记录.md 本笔条目
//（RequestCompose.ets 是零 import 契约件/复制直跑件，反向合并会破直跑）。
//
// 上限联动取向（只抬不降；2026-09-23 三仓对照后的取向声明——★ 竞品无一家抬上限，后人勿
// 照抄「压」的形态）：Cherry 扣减（maxOutputTokens - budget，把用户值当总预算）、Kelivo
// Vertex 压预算（budget = maxTokens - 1024，保正文至少 1024）、RikkaHub 完全不联动（原样
// 发）。本仓取「抬」的三条判据：
// ① 架构判据：本仓的思考预算**不是用户旋钮**——由档位映射定死（geminiThinkingBudget =
//   1024/8192/24576），用户旋钮只有「最大输出长度」一个。压预算 = 把档位语义悄悄降级
//   （用户选 max 的思考强度被上限设置改写成 low 档），静默改语义比抬上限更贵。
// ② 取向判据：保持思考追求效果（母书拍板）；抬上限与之一致，压预算正好相反。
// ③ 风险闭合：抬升有上界——floor 最大 = 24576 + 4096 = 28672，且只在「用户显式配置正数
//   上限 + 思考真的开启」时介入（未配置、显式 0、脏负值、显式关闭〔off〕四态零介入——活性
//   判据见 thinkingConsumesBudget）。28672 低于 Gemini 2.5 全系的
//   maxOutputTokens 量级，不会把请求顶到「超模型上限」的 400 面；将来若出现更大的档位
//   预算或余量，须重估此上界。

import { AiConnection, AssistantAdvancedParams, SamplingParams, supportsThinking,
  connectionOffEnabled, legalThinkingTier, THINKING_OPTIONS, PROTOCOL_GEMINI } from './AiTypes';
import { geminiThinkingBudget } from './RequestCompose';

// 思考开启时的正文余量（上限联动下限的加法项）：量级出处 = Cherry
// COMPRESSION_MIN_OUTPUT_TOKENS 4096（packages/aiCore/src/core/context/middleware.ts:48）
// ——该值由一条实测定出（压缩调用实测需 2233 输出 token〔5.8k 字符思考 + 1.7k 字符摘要〕，
// 旧固定值 2048 正卡在边界上、预算烧在思考中途致正文空返）⇒ 4096 ≈ 实测需求 1.8 倍。
// ★ 本常量是本仓自定值，不照抄任何竞品的「联动」逻辑（取向三条见文件头）。
export const COMPOSE_OUTPUT_HEADROOM: number = 4096;

// 本轮参数解析产物（宿主 ChatSendCtrl.RoundRequest 取 thinking/sampling 两字段消费）
export interface RoundParams {
  thinking: string;
  sampling: SamplingParams | null;
}

// 档位是否真的消耗输出预算（上限联动的活性判据；2026-09-23 自检轮补——原判据只写
// `thinking !== ''`，把「显式关闭思考」也算成了开启，用户配小上限 + 选 off 档时上限被
// 静默抬高，与下方判据 ③「只在……思考开启时介入」自相矛盾）：
// · '' = 不带档位字段（未选）⇒ 无思考；
// · 'off' = 显式关闭 ⇒ compose 侧落 thinking{type:'disabled'}（OpenAI 系）/ reasoning
//   {effort:'none'}（Anthropic 系）/ 不发 thinkingConfig（Gemini 系，本仓 off 恒降级 ''，
//   见下方归一），**无思考 token 消耗** ⇒ 不存在「思考吃预算」问题，不介入；
// · 其余（low/high/max）= 真思考档 ⇒ 消耗。
// ★ 语义与 RequestCompose 的既有分支判据同义（`if (thinking === 'off' && offEnabled)` /
// `else if (thinking !== '' && thinking !== 'off')`——那里判发什么字段、这里判留不留余量）。
// 不能反向引用（本件 import RequestCompose 的 geminiThinkingBudget，反向即 import 环，
// P-9 家族），故在此单源化并配行为直跑真值表。
export function thinkingConsumesBudget(thinking: string): boolean {
  return thinking !== '' && thinking !== 'off';
}

// 思考档位联动下的「实际发出上限」（全态纯数值函数——零外部依赖，断言面复制直跑对象）：
// · configured === undefined ⇒ 原样（未配置 = 不发该字段，模型按自身上限输出——2026-09-08/09-12/
//   09-20 三次拍板的安全默认，本函数不动）；
// · configured <= 0 ⇒ 原样（显式 0 = 不限制；负值属脏数据，同样零介入——静默改写用户值比
//   脏值透传更糟）；
// · thinkingActive === false ⇒ 原样（未开思考不存在「思考吃预算」问题）；
// · 其余（显式正数 + 思考开）⇒ 取「configured」与「档位预算 + 正文余量」的较大者——
//   **只抬不降**（用户填的值已够大时逐字节原样，不产生 +1）。
// ★ 三态与闸门收在本函数内（调用点只算预算、不写条件分支）：闸门若留在调用点，「未配置 /
// 显式 0 不介入」这条行为只能靠源码形状钉守，收进来后三态与抬升同在一张行为直跑真值表。
// ★ Anthropic 的未配置态（maxOutput === undefined）天然在闸门外，compose 侧 8192 兜底
// 逐字节保留（Anthropic 默认上限改按模型自身能力一节整体顺延，见任务书 §1 不做项）。
export function resolveSentMaxOutput(configured: number | undefined, thinkingActive: boolean,
  thinkingBudget: number): number | undefined {
  if (configured === undefined || configured <= 0 || !thinkingActive) {
    return configured;
  }
  const floor: number = thinkingBudget + COMPOSE_OUTPUT_HEADROOM;
  return configured >= floor ? configured : floor;
}

// 本轮思考档位与采样参数的唯一组装点（方法体自 ChatSendCtrl.assembleRound 搬迁，语义
// 逐句等价）。调用方消费：thinking → 请求体档位字段（'' = 不带）、sampling → 采样五字段
//（null = 未配置零字段零回归）。
export function resolveRoundParams(conn: AiConnection, tier: string,
  advanced: AssistantAdvancedParams | null): RoundParams {
  // 思考档位（2026-08-31 任务 B）：页面 thinkingValue 经 refs 入；协议能力门控——
  // PROTOCOL_CAPS 无 thinking 键的协议不传（零回归）；值透传给协议流（'' = 不带字段）。
  // ★ 2026-08-31 关闭档兜底：off 仅开关方言画像域有效（菜单已按域暴露，此处防「off
  // 状态 + 切到非支持域」漏网——非域 off 降级 '' = 不传，静默零字段）；2026-09-03
  // Cube 吸收 A2 起经 connectionOffEnabled(conn) 单一判定源；★ 2026-09-06 模型级
  // 精化：合法性归一 legalThinkingTier——off 看连接 off 支持（conn.reasoningOffSupported
  // 填充），其余档位看画像行收窄后选项集（conn.reasoningMenuOptions）——防「收窄前
  // 选中值 + 切模型漏网」同 off 兜底同构
  let thinking: string = '';
  if (tier !== '' && supportsThinking(conn.protocol, conn.endpoint)) {
    thinking = legalThinkingTier(tier, connectionOffEnabled(conn),
      conn.reasoningMenuOptions ?? THINKING_OPTIONS);
  }
  // 采样参数（2026-09-01 高级设定）：助手高级设定解析缓存取五字段（contextCount 已在
  // 宿主消费——上下文截尾用）；全空 = null（等价未配置，请求体零字段零回归）
  let sampling: SamplingParams | null = null;
  if (advanced !== null) {
    sampling = {
      temperature: advanced.temperature,
      topP: advanced.topP,
      presencePenalty: advanced.presencePenalty,
      frequencyPenalty: advanced.frequencyPenalty,
      maxOutput: advanced.maxOutput
    };
    if (sampling.temperature === undefined && sampling.topP === undefined &&
      sampling.presencePenalty === undefined && sampling.frequencyPenalty === undefined &&
      sampling.maxOutput === undefined) {
      sampling = null;
    }
  }
  // 上限联动（只抬不降）：三态零介入（未配置 undefined / 显式 0 不限制 / 脏负值）在
  // resolveSentMaxOutput 内；「思考真的消耗预算」这一活性闸门在 thinkingConsumesBudget 内
  //——此处只算预算，不写条件分支（闸门单源，见两函数注释）。
  // ★ budget 的取值边界：geminiThinkingBudget 只在真思考档被调（该函数头注释明写「''
  // 不经此」；off 档亦不该进——见活性判据）；非 Gemini 协议 budget = 0 ⇒ floor 恒 =
  // 4096 = **固定的最小正文留量**（不是由预算算出的值）——Anthropic 走 output_config.effort、
  // OpenAI 走 reasoning_effort，两家只送档位名不送 token 预算数，无从计算，故给固定留量。
  if (sampling !== null) {
    const thinkingActive: boolean = thinkingConsumesBudget(thinking);
    const budget: number = conn.protocol === PROTOCOL_GEMINI && thinkingActive
      ? geminiThinkingBudget(thinking) : 0;
    sampling.maxOutput = resolveSentMaxOutput(sampling.maxOutput, thinkingActive, budget);
  }
  return { thinking: thinking, sampling: sampling };
}
