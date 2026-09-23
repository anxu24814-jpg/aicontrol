// 上下文压缩域（2026-09-23 任务书-上下文压缩-20260923 执行）：一个文件承载整个压缩域
//（反碎片下限：同一功能域优先单件，勿拆两件）。形制照 MemoryImport.ets——进程级独立域：
// 顶层函数模块，不持页面/组件引用、不触 UI，结果对象回传预览面板，由面板出提示。
// · 干什么：把「可压段」（保留最近 N 轮之前的消息）交给模型写成一份交接摘要，用户预览
//   （可编辑、可填补充要求）确认后**采用**才落库（CompressDb.adoptCompressSummary 唯一
//   落库写点）；放弃 = 零副作用（fail-open）。
// · 中断（2026-09-23 修复笔）：生成在途时可被用户中断——cancelCompressDraft 销毁在途
//   http 请求（官方语义「Stops an HTTP request task」）并立即释放在途位；被判过期的结果
//   一律丢弃（零副作用，同 fail-open）。查询口 isCompressInflight 供关闭确认选文案。
// · 依赖方向（单向、无环——坑50 红线）：本域 → AiTypes / TokenEstimate / TitleGen /
//   TitleApi / KeyStore / ProviderDb / UsageStatsDb / CompressDb / ChatDb(isReady) /
//   ChatMessageCompose（类型；common → components 反向先例 = ProactiveGen）。**反向零依赖**。
// · 模型归属（任务书拍板 8）：compressProviderId/compressModelId 两键非空则用它们，
//   **未配置时回退当前会话的模型**（与标题/记忆链「未配置即停」语义不同——本槽有回退）。
// · 提示词归属：独立第七槽 TOOL_PROMPT_SLOT_COMPRESS（UI 编辑面在功能模型页压缩卡）。
// · 纯函数区（buildCompressRows / pickCompressWindow / renderCompressTranscript /
//   buildCompressPrompt / parseCompressOutput）**零外部绑定**——断言脚本剥 import 后直跑
//   （143 ③ 同款形制）；IO 函数（generateCompressDraft）不在直跑面。
// · 记账：logTaskUsage('compress', conversationId, ...)——purpose 'compress' 已入
//   CostStatsCalc.COST_PURPOSES；★ 压缩请求自身的 usage 绝不回填上下文读数（锚点五条
//   红线——压缩是一次性辅助开销，不是会话上下文规模的度量）。
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiChatMessage, AiConnection } from './providers/AiTypes';
import { estimateTokens } from './TokenEstimate';
import { ChatMessage } from '../components/chat/ChatMessageCompose';
import { buildRequestHistory } from '../components/chat/ChatHistoryBuilder';
import { clipHistoryKeepingSummary, clipHistoryTail } from './providers/RequestInject';
import { isReady } from './store/ChatDb';
import { loadPoolKey } from './store/KeyStore';
import { requestTitleText, TitleRequestResult } from './providers/TitleApi';
import { resolveTitleEndpoint, TitleEndpoint } from './TitleGen';
import { logTaskUsage } from './store/UsageStatsDb';
import { contextWindowForConnection } from './store/ProviderDb';

const DOMAIN: number = 0x71C5;
const TAG: string = 'CompressGen';

// ── 模型两键（任务书 §3.4；照 MemoryGen.MEMORY_PROVIDER_KEY/MEMORY_MODEL_KEY 先例，
// 未配置 = 回退当前会话模型——不是「未启用」，与记忆两键语义不同）──
export const COMPRESS_PROVIDER_KEY: string = 'compressProviderId';
export const COMPRESS_MODEL_KEY: string = 'compressModelId';

// ── 常数（任务书 §6；阈值属实测调参项——首版照书落，真机实测后再调，改值不需重写结构）──
// 保留段保底轮次（chatbox 双约束口径）：压缩后「我刚才说的」还指得动
export const COMPRESS_KEEP_ROUNDS: number = 2;
// 可压段条数下限：少于 6 条不值得花一次模型调用（键置灰「历史还短」）
export const COMPRESS_MIN_COMPRESSIBLE: number = 6;
// 压缩请求输入占窗口比例上限：超出则从可压段尾部往回收（等于扩大保留段）
export const COMPRESS_INPUT_RATIO_MAX: number = 0.8;
// 摘要输出上限（2026-09-23 输出上限治理笔定稿：固定常量，不挂会话助手 maxOutput——那是
// 用户给聊天回复设的旋钮〔可设 200/512〕，把它当摘要预算 = 主动消息链 2026-09-20 实锤的
// 「思考烧满小上限致正文恒空」在唯一一条链上复活；照 ZCode MAX_OUTPUT_TOKENS_FOR_SUMMARY
// = 20_000。★ 必须含思考预算——cherry-studio 实测一次压缩烧 2233 输出 token 含 thinking；
// ★ 若将来接入模型输出上限数据源，必须 max(4096, min(模型上限, 20000))——4096 下限照
// cherry COMPRESS_MIN_OUTPUT_TOKENS，防老模型小上限掐摘要）
export const COMPRESS_MAX_OUTPUT: number = 20000;
// 压缩请求读超时（2026-09-23 输出上限治理笔 60s → 5 分钟：非流式是等整包不是等增量，
// 思考常开 + 输入接近 0.8×窗口时生成 2~4k token 摘要可能远超 60s；参照 cherry 30 分钟
// idle 档取更保守的 5 分钟；用户的「停止」键〔cancelCompressDraft〕仍是兜底。
// ★ 超时 = 整笔失败〔无半截摘要落库，fail-open〕，非截断——截断走 result.truncated 判）
export const COMPRESS_READ_MS: number = 300000;
// 用途标签（失败文案前缀——传共享通道 taskLabel 形参；压缩面板原样上屏 errorMessage，
// 不参数化则压缩失败会错报「标题响应缺少正文」指错排查方向）
export const COMPRESS_TASK_LABEL: string = '压缩';

// ── 提示词四件套（任务书 §4.1/§4.2；槽名 TOOL_PROMPT_SLOT_COMPRESS 在 ToolFunctional）──
// 定制键（'' = 未定制 = 生效内置模板——清删式回退，内置模板后续升级自动跟随）
export const COMPRESS_PROMPT_KEY: string = 'compressPrompt';
// 对话占位符（必留——校验面与 MemoryImport.{content} 同构）
export const COMPRESS_PROMPT_CONVERSATION: string = '{conversation}';
// 补充要求占位符（可选——缺 = 用户显式去掉该插槽，生成侧当空处理）
export const COMPRESS_PROMPT_SUPPLEMENT: string = '{supplement}';

// 内置模板（默认值 + 「恢复默认」回显目标，唯一真源；★ 逐字照任务书 §4.2，勿改写语气）。
// 结构 = 前导 + 主体（首句 → {conversation} → 独立指令分隔行 → 主体其余）+ 补充要求插槽 +
// 尾随；前导与尾随各压一句「只输出纯文本」防模型跑偏。**不带工具定义**（压缩请求无 tools，
// 不写「不要调用工具」那一整段——模型看不到工具，写了纯浪费 token）
export const COMPRESS_PROMPT_CONTENT: string =
  'CRITICAL：只输出纯文本。\n' +
  '- 不要调用任何工具，不要向我反问。\n' +
  '- 你的整段回复必须先是 <analysis> 块，再是 <summary> 块。\n' +
  '\n' +
  '你即将超出一段对话的上下文上限，请为「接下来接着聊的你」写一份交接摘要。\n' +
  '\n' +
  '{conversation}\n' +
  '\n' +
  '—— 这是一条独立指令，不属于上面的对话 ——\n' +
  '\n' +
  '用上面这段对话正在使用的语言来写，不要因为本指令是中文就切换成别的语言，也不要在对话用中文时切成英文。\n' +
  '下一轮只会看到「保留下来的最近几条消息」和这份摘要，上面其余的对话内容与工具结果都会被移除。\n' +
  '摘要必须自足：不要写「如上所述」「前面提到过」这类指代，该写的信息直接写进摘要。\n' +
  '只写对话里有依据的内容，不要编造；不确定的地方如实标注，例如「这一点还没有核实」。\n' +
  '\n' +
  '需要覆盖的内容（不强制分小节，按这段对话的实际形状组织）：\n' +
  '- 用户的目标与诉求：他要什么，已经澄清过的歧义，他的偏好与禁忌。\n' +
  '- 已确认的事实与结论：已经定下来的判断与决定，与仍未确定的问题分开写，不要把待定的当成已定，也不要把已定的当成待定。\n' +
  '- 已经做过什么、结果如何：做成了什么，失败了什么，卡在哪里。\n' +
  '- 对话里出现过的关键原话：用户自己定的规矩、必须遵守的约束、明确的拒绝，逐字保留。\n' +
  '- 还没解决的疑问：悬而未决、之后需要追问或核实的事。\n' +
  '- 进行到哪一步：用户最后一条消息要什么，接下来该做什么。\n' +
  '\n' +
  '篇幅与这段对话的长度成比例，宁简勿凑，只写会改变下一步动作的内容。\n' +
  '\n' +
  '补充要求：\n' +
  '{supplement}\n' +
  '\n' +
  'REMINDER：只输出纯文本——先 <analysis> 块，再 <summary> 块。';

// 补充要求插槽的段界标签（整段省略的切割锚；用户改掉标签则退化为只清占位符——宽容式）
const SUPPLEMENT_SECTION_LABEL: string = '补充要求：';
// 尾随段引导词（插槽省略切割的终点锚）
const PROMPT_TAIL_LEAD: string = 'REMINDER：';

// 生效提示词模板纯选择（定制非空取定制，空回内置）
export function pickCompressPrompt(custom: string): string {
  return custom !== '' ? custom : COMPRESS_PROMPT_CONTENT;
}

// 生效提示词模板单源（生成链 + 功能模型页编辑面板 + 控制台助手工具共用——现读，用户改完
// 下次压缩即生效，无缓存无广播）
export function resolveCompressPromptTemplate(): string {
  return pickCompressPrompt(AppStorage.get<string>(COMPRESS_PROMPT_KEY) ?? '');
}

// ── 纯函数区（断言直跑面：零 import 依赖、确定性输入产出确定输出）──

// 选段行（请求序列形态 + 行库序号）：role ∈ user/assistant/tool——与 buildRequestHistory 的
// 过滤口径镜像（notice/thinking/summary 不入；空 user 无图跳过；空 assistant 无工具跳过）
export interface CompressHistoryRow {
  role: string;
  content: string;
  hasToolCalls: boolean; // assistant 行是否带工具调用（后随 kind='tool' 连续段）
  rowSeq?: number;       // 库行 seq（实时流内行无值）
  imageCount: number;    // user 行图片张数（转写 [图片] 占位用；其余行 0）
  toolName?: string;     // role='tool' 行的工具名（转写标注用）
}

// 消息流 → 选段行（纯映射）。图片张数取 attachBriefs 的 image 类简报（回放装配链写入——
// 历史轮图片不重发，请求里只有本条 user 带图；压缩转写只标占位）
export function buildCompressRows(source: ChatMessage[]): CompressHistoryRow[] {
  const rows: CompressHistoryRow[] = [];
  for (let i = 0; i < source.length; i++) {
    const m: ChatMessage = source[i];
    if (m.kind === 'user') {
      let images: number = 0;
      const briefs = m.attachBriefs;
      if (briefs !== undefined) {
        for (const b of briefs) {
          if (b.kind === 'image') {
            images++;
          }
        }
      }
      if (m.text === '' && images === 0) {
        continue; // 空占位行不入序列（与 buildRequestHistory 同判据）
      }
      const row: CompressHistoryRow = { role: 'user', content: m.text, hasToolCalls: false,
        imageCount: images };
      if (m.rowSeq !== undefined) {
        row.rowSeq = m.rowSeq;
      }
      rows.push(row);
      continue;
    }
    if (m.kind === 'assistant') {
      // 工具轮判定 = 紧随的 kind='tool' 连续段（与 buildRequestHistory 的前看口径同构）
      const hasCalls: boolean = i + 1 < source.length && source[i + 1].kind === 'tool';
      if (m.text === '' && !hasCalls) {
        continue; // 空内容且无工具调用（占位/异常）——不入序列
      }
      const row: CompressHistoryRow = { role: 'assistant', content: m.text,
        hasToolCalls: hasCalls, imageCount: 0 };
      if (m.rowSeq !== undefined) {
        row.rowSeq = m.rowSeq;
      }
      rows.push(row);
      continue;
    }
    if (m.kind === 'tool') {
      const row: CompressHistoryRow = { role: 'tool', content: m.toolOutputJson ?? '',
        hasToolCalls: false, imageCount: 0, toolName: m.toolName };
      if (m.rowSeq !== undefined) {
        row.rowSeq = m.rowSeq;
      }
      rows.push(row);
    }
  }
  return rows;
}

// 选段产物：compressible = 可压段（序列头部）、keep = 保留段（最近 keepRounds 轮）、
// coversToSeq = 可压段最后一条带 seq 的行号（覆盖边界，落库用）
export interface CompressWindowPlan {
  compressible: CompressHistoryRow[];
  keep: CompressHistoryRow[];
  coversToSeq: number;
}

// 选段纯函数（一轮 = 从一条 user 行到下一条 user 行之前）：
// · 保留段 = 最近 keepRounds 轮 ⇒ 边界恒落在一条 user 行之前——**工具对（assistant 工具轮
//   与其后 role='tool' 结果行）永不被撕开**（工具行只会出现在轮内 assistant 之后，不临界）；
// · 可压段条数 < minCompressible → null（键置灰「历史还短」）；
// · 边界行无 rowSeq（理论不发生：实时流内行恒在保留段/尾部）→ 向前退到最近带值行；退到底
//   仍无 → null（**禁**用 0 或猜测值兜底——错边界 = 误删保留段）；
// · user 轮次不足 keepRounds（连保留段都凑不齐）→ null。
// 返回 null 的两种成因（不足 / 无号）都归「本次不可压」，调用方按置灰处理
export function pickCompressWindow(rows: CompressHistoryRow[], keepRounds: number,
  minCompressible: number): CompressWindowPlan | null {
  const userStarts: number[] = [];
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].role === 'user') {
      userStarts.push(i);
    }
  }
  if (userStarts.length <= keepRounds) {
    return null;
  }
  const keepStart: number = userStarts[userStarts.length - keepRounds];
  const compressible: CompressHistoryRow[] = rows.slice(0, keepStart);
  if (compressible.length < minCompressible) {
    return null;
  }
  // 覆盖边界：可压段尾部最近一条带 seq 的行（边界行恰为 tool 行也成立——seq ≤ 边界一并被
  // 压掉，其配对 assistant 恒在更前）
  let boundary: number = -1;
  for (let i = compressible.length - 1; i >= 0; i--) {
    if (compressible[i].rowSeq !== undefined) {
      boundary = compressible[i].rowSeq ?? -1;
      break;
    }
  }
  if (boundary < 0) {
    return null;
  }
  return { compressible: compressible, keep: rows.slice(keepStart), coversToSeq: boundary };
}

// 可压段 → 转写文本（给模型看的对话记录）。图片不进压缩请求（任务书拍板 9）——位置留
// [图片] 占位；工具调用与结果以标注行呈现（摘要要覆盖「已经做过什么、结果如何」）
export function renderCompressTranscript(rows: CompressHistoryRow[]): string {
  const lines: string[] = [];
  for (const r of rows) {
    if (r.role === 'user') {
      let body: string = r.content;
      for (let i = 0; i < r.imageCount; i++) {
        body += (body !== '' ? '\n' : '') + '[图片]';
      }
      lines.push('用户：' + body);
      continue;
    }
    if (r.role === 'assistant') {
      lines.push('助手：' + (r.content !== '' ? r.content : '（调用工具）'));
      continue;
    }
    const name: string = r.toolName !== undefined && r.toolName !== '' ? '（' + r.toolName + '）' : '';
    lines.push('工具结果' + name + '：' + r.content);
  }
  return lines.join('\n\n');
}

// 提示词拼装（前导 + 主体 + 插槽 + 尾随，照 ZCode buildCompactPrompt 的拼装序）：
// {conversation} 注入转写文本；补充要求非空注入 {supplement}，为空则**整段省略**插槽
//（从「补充要求：」标签行起删到尾随 REMINDER 前；用户改掉标签则退化为只清占位符——宽容式）。
// ★ 2026-09-23 自检轮修复（次序）：先在**模板**上处理补充要求插槽，再把转写注入——原实现反
// 序（先注入转写、后按 indexOf 找段界），转写正文里一旦出现「补充要求：」字样（用户聊到压缩
// 功能就会），标签锚点落在转写内部、切割会整段吃掉转写尾部与模板正文，摘要静默丢掉最近对话
export function buildCompressPrompt(template: string, transcript: string,
  supplement: string): string {
  const extra: string = supplement.trim();
  let filled: string = template;
  if (extra !== '') {
    filled = template.split(COMPRESS_PROMPT_SUPPLEMENT).join(extra);
  } else if (template.includes(COMPRESS_PROMPT_SUPPLEMENT)) {
    const labelIdx: number = template.indexOf(SUPPLEMENT_SECTION_LABEL);
    const tailIdx: number = template.indexOf(PROMPT_TAIL_LEAD);
    filled = (labelIdx >= 0 && tailIdx > labelIdx) ?
      template.slice(0, labelIdx) + template.slice(tailIdx) :
      template.split(COMPRESS_PROMPT_SUPPLEMENT).join('');
  }
  return filled.split(COMPRESS_PROMPT_CONVERSATION).join(transcript);
}

// 输出解析（宽容式）：丢掉 <analysis>…</analysis> 段；命中 <summary>…</summary> 只取其中
// 正文；都没有则取去掉 analysis 后的全文。返回 ''（trim 后）= 失败——不落库、报错提示。
// ★ 截断防御（2026-09-23 输出上限治理笔，两种未闭合都拦）：剥离闭合 analysis 后，余文仍含
// <analysis> 开标签（思考段没写完 = 输出在中途被掐），或含 <summary> 开标签而无完整闭合块
//（截断发生在输出尾部时最常见的形态——半截正文会被当摘要呈现、可被「采用」落库）→ 一律 ''
// 走失败分支；宁可失败给明确文案，不落半截摘要
export function parseCompressOutput(raw: string): string {
  let text: string = raw.replace(/<analysis>[\s\S]*?<\/analysis>/g, '');
  if (text.includes('<analysis>')) {
    return '';
  }
  const match: RegExpMatchArray | null = text.match(/<summary>([\s\S]*?)<\/summary>/);
  if (match !== null) {
    text = match[1];
  } else if (text.includes('<summary>')) {
    return '';
  }
  return text.trim();
}

// 协议历史的纯文本 token 估算（节省量的口径件——只数 content 与 reasoning，同 estimateTokens
// 单一来源，不另造估算）
function estimateHistoryTokens(history: AiChatMessage[]): number {
  let total: number = 0;
  for (const m of history) {
    total += estimateTokens(m.content);
    if (m.reasoning !== undefined) {
      total += estimateTokens(m.reasoning);
    }
  }
  return total;
}

// 节省量（面板状态行「节省约 N tokens」；任务书 §2.6）：同一链估算相减——无摘要链（摘要行
// 剔除后全量历史 + 同限截尾）减有摘要链（当前请求形态）。面板开时现算（自校正式，无需为
// 跨重启显示另存数值）；负值防御归零（如 contextCount 截尾后两链同形即无差）
export function estimateCompressSaving(source: ChatMessage[], clipLimit: number): number {
  const withSummary: number = estimateHistoryTokens(
    clipHistoryKeepingSummary(buildRequestHistory(source), clipLimit));
  const withoutSummary: ChatMessage[] = [];
  for (const m of source) {
    if (m.kind !== 'summary') {
      withoutSummary.push(m);
    }
  }
  const full: number = estimateHistoryTokens(
    clipHistoryTail(buildRequestHistory(withoutSummary), clipLimit));
  return full - withSummary > 0 ? full - withSummary : 0;
}

// ── IO 区 ──

// 模型两键选择（纯函数）：两键齐 = 用压缩模型；缺任一回退当前会话连接；无连接 = 空对
export interface CompressModelPick {
  providerId: string;
  modelId: string;
}

export function pickCompressModel(compressProvider: string, compressModel: string,
  conn: AiConnection | null): CompressModelPick {
  if (compressProvider !== '' && compressModel !== '') {
    return { providerId: compressProvider, modelId: compressModel };
  }
  if (conn !== null) {
    return { providerId: conn.providerId, modelId: conn.model };
  }
  return { providerId: '', modelId: '' };
}

export function resolveCompressModel(conn: AiConnection | null): CompressModelPick {
  return pickCompressModel(AppStorage.get<string>(COMPRESS_PROVIDER_KEY) ?? '',
    AppStorage.get<string>(COMPRESS_MODEL_KEY) ?? '', conn);
}

// 生成结果态（照 MemoryImport 八态精神收敛；全走返回值不借 reject）：
// ready——生成成功（summaryText = 解析后纯摘要正文，coversToSeq = 覆盖边界）
// config——模型不可用（无连接且两键未配 / 服务商或模型停用 / Key 池空 / 明文缺失）
// insufficient——可压段不足（含无库序号边界；键本应置灰，此处兜底）
// tooLong——输入上限守卫收到底仍超（「历史太长，本次压不动」，fail-open）
// failed——请求异常或解析为空
// skipped——守卫未放行（库未就绪 / 会话 id 空）
// busy——同会话上一次生成仍在途（★ 2026-09-23 自检轮补：原与 skipped 合流，面板会把「在途」
//   报成「会话未就绪」——文案必须分清；★ 同日修复笔后再改口径：面板关闭三路都会中断本次
//   生成并立即释放在途位，故本态现由**非关闭路径**（页面销毁等未经关闭确认的收尾）留下，
//   最长到读超时 5 分钟）
// cancelled——本次结果已被用户中断作废（★ 2026-09-23 修复笔补：面板已关，调用方丢弃即可）
export const COMPRESS_STATUS_CANCELLED: string = 'cancelled';
export const COMPRESS_STATUS_READY: string = 'ready';
export const COMPRESS_STATUS_CONFIG: string = 'config';
export const COMPRESS_STATUS_INSUFFICIENT: string = 'insufficient';
export const COMPRESS_STATUS_TOO_LONG: string = 'tooLong';
export const COMPRESS_STATUS_FAILED: string = 'failed';
export const COMPRESS_STATUS_SKIPPED: string = 'skipped';
export const COMPRESS_STATUS_BUSY: string = 'busy';

export interface CompressDraftResult {
  status: string;
  summaryText: string;
  errorMessage: string;
  coversToSeq: number;
}

function buildDraft(status: string, summaryText: string, errorMessage: string,
  coversToSeq: number): CompressDraftResult {
  return { status: status, summaryText: summaryText, errorMessage: errorMessage,
    coversToSeq: coversToSeq };
}

// 在途闸与中断位（同一会话压缩中重复点键无效；照 MemoryGen 的 Set 范式升级为 Map——
// 2026-09-23 修复笔加「代 + 请求句柄」两栏，支撑「生成中点关闭 = 停止本次压缩」）：
// · token 代——每次发号自增；中断或被新一笔顶替后，旧 promise 回来时凭代不符判过期，
//   结果作废（面板已关、草稿无处可去；落库唯一路径是「采用」，故作废零副作用）
// · request 句柄——请求创建时登记，中断用 destroy 真停（不登记则只能等 60s 读超时）
// · onCanceled——请求侧给的**取消收尾回调**（2026-09-23 自检轮加，独立复核 F1）：destroy
//   后旧 promise 何时 settle 不由本层掌控，若走 reject 分支请求日志会把用户主动中断记成
//   「网络失败」（与聊天链 -3 分家同族）——故中断时显式调它一次：日志落取消终态，悬着的
//   promise 一并落定（代不符的过期分支照旧丢弃结果，两条路不冲突）
interface CompressInflight {
  token: number;
  request: http.HttpRequest | null;
  onCanceled: (() => void) | null;
}
const inflight: Map<string, CompressInflight> = new Map<string, CompressInflight>();
let inflightTokenSeq: number = 0;

// 在途查询（面板关闭确认的判据：在途 = 确认文案走「停止本次压缩」分支）
export function isCompressInflight(conversationId: string): boolean {
  return inflight.has(conversationId);
}

// 中断（用户关掉面板即停止本次压缩）：先释放在途位、再销毁请求句柄、最后落请求日志的取消
// 终态——返回是否确有一笔在途被中断。★ 本地释放先于 destroy：destroy 后旧 promise 何时
// settle 不由本层掌控（官方只承诺停止任务与释放资源），先删在途位才能保证「关掉再开」立刻
// 可重新生成，不必干等读超时；旧 promise 若后到，凭代不符走过期分支丢弃
export function cancelCompressDraft(conversationId: string): boolean {
  const entry: CompressInflight | undefined = inflight.get(conversationId);
  if (entry === undefined) {
    return false;
  }
  inflight.delete(conversationId);
  const request: http.HttpRequest | null = entry.request;
  if (request !== null) {
    try {
      request.destroy();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '中断 destroy 异常（忽略）：%{public}s', (e as Error).message);
    }
  }
  // 取消收尾（2026-09-23 自检轮加）：由请求侧给的闭包落日志的「已取消」终态——不调它则
  // destroy 后的结算会把用户主动中断记成「网络失败」（见 CompressInflight.onCanceled 注释）
  const onCanceled: (() => void) | null = entry.onCanceled;
  if (onCanceled !== null) {
    onCanceled();
  }
  hilog.info(DOMAIN, TAG, '压缩生成被用户中断');
  return true;
}

// 面板置灰判据③（可压段不足）：选段跑得通才亮键（纯计算，无 IO）
export function compressibleReady(source: ChatMessage[]): boolean {
  return pickCompressWindow(buildCompressRows(source), COMPRESS_KEEP_ROUNDS,
    COMPRESS_MIN_COMPRESSIBLE) !== null;
}

// 生成入口（预览面板打开即调）：只发请求 + 解析，**一个字都不落库**（采用走
// CompressDb.adoptCompressSummary）。失败不 reject，落在各结果态
export function generateCompressDraft(conversationId: string, source: ChatMessage[],
  conn: AiConnection | null, supplement: string): Promise<CompressDraftResult> {
  if (conversationId === '') {
    hilog.info(DOMAIN, TAG, '无会话（隐私会话/空引用），跳过本次触发');
    return Promise.resolve(buildDraft(COMPRESS_STATUS_SKIPPED, '', '', -1));
  }
  if (inflight.has(conversationId)) {
    hilog.info(DOMAIN, TAG, '同会话压缩生成在途，本次触发忽略');
    return Promise.resolve(buildDraft(COMPRESS_STATUS_BUSY, '', '', -1));
  }
  inflightTokenSeq++;
  const entry: CompressInflight = { token: inflightTokenSeq, request: null, onCanceled: null };
  inflight.set(conversationId, entry);
  const registerRequest = (req: http.HttpRequest, onCanceled: () => void): void => {
    entry.request = req;
    entry.onCanceled = onCanceled;
  };
  return runGenerateCompressDraft(conversationId, source, conn, supplement,
    registerRequest, entry.token)
    .then((result: CompressDraftResult): CompressDraftResult => {
      const current: CompressInflight | undefined = inflight.get(conversationId);
      if (current === undefined || current.token !== entry.token) {
        hilog.info(DOMAIN, TAG, '本次压缩结果已过期（被中断或被新一笔顶替），丢弃');
        return buildDraft(COMPRESS_STATUS_CANCELLED, '', '', -1);
      }
      return result;
    })
    .catch((e: Object): CompressDraftResult => {
      hilog.error(DOMAIN, TAG, '压缩生成异常终止：%{public}s', (e as Error).message);
      return buildDraft(COMPRESS_STATUS_FAILED, '', (e as Error).message, -1);
    })
    .finally((): void => {
      // 只在自己仍是在途主时释放——中断与被顶替两路已各自处置，代不符不得误删新一笔
      const current: CompressInflight | undefined = inflight.get(conversationId);
      if (current !== undefined && current.token === entry.token) {
        inflight.delete(conversationId);
      }
    });
}

// 生成主流程：守卫序 = dbReady → 选段 → 模型（两键 ?? 会话连接）→ 端点与 Key → 输入上限
// 守卫（尾部回收）→ **中断竞态闸（代仍当前）** → 拼装与请求 → 记账 → 解析
// entryToken = 本笔在途位的代（发起前闸的判据；见闸内注释）
async function runGenerateCompressDraft(conversationId: string, source: ChatMessage[],
  conn: AiConnection | null, supplement: string,
  onRequest: (req: http.HttpRequest, onCanceled: () => void) => void,
  entryToken: number): Promise<CompressDraftResult> {
  if (!isReady()) {
    return buildDraft(COMPRESS_STATUS_SKIPPED, '', '', -1); // 库态守卫（竞态窗口内不假定）
  }
  const rows: CompressHistoryRow[] = buildCompressRows(source);
  let plan: CompressWindowPlan | null =
    pickCompressWindow(rows, COMPRESS_KEEP_ROUNDS, COMPRESS_MIN_COMPRESSIBLE);
  if (plan === null) {
    return buildDraft(COMPRESS_STATUS_INSUFFICIENT, '', '', -1);
  }
  // 模型解析（两键 ?? 会话连接）与端点验证（resolveTitleEndpoint 标准三验：服务商启用 +
  // 模型启用对话 + Key 池非空——与标题/记忆链同源口径）
  const picked: CompressModelPick = resolveCompressModel(conn);
  if (picked.providerId === '' || picked.modelId === '') {
    hilog.debug(DOMAIN, TAG, '无可用模型（两键未配且会话无连接），压缩不可用');
    return buildDraft(COMPRESS_STATUS_CONFIG, '', '', -1);
  }
  const resolved: TitleEndpoint | null =
    await resolveTitleEndpoint(picked.providerId, picked.modelId);
  if (resolved === null) {
    hilog.warn(DOMAIN, TAG, '压缩模型验证不通过（服务商停用/模型停用/Key 池空），放弃');
    return buildDraft(COMPRESS_STATUS_CONFIG, '', '', -1);
  }
  const keyId: string = resolved.keyIds[0]; // 启用序首支（小任务不轮询池——标题链同口径）
  const apiKey: string = await loadPoolKey(picked.providerId, keyId);
  if (apiKey === '') {
    hilog.warn(DOMAIN, TAG, '压缩 Key 明文缺失，放弃');
    return buildDraft(COMPRESS_STATUS_CONFIG, '', '', -1);
  }
  // 输入上限守卫（§4.4）：「可压段 + 提示词」估算 > 窗口 × COMPRESS_INPUT_RATIO_MAX 时从
  // 可压段尾部整轮往回收（等于扩大保留段）；收到底仍超 = tooLong（fail-open，什么都没发生）
  const windowConn: AiConnection = { baseUrl: resolved.baseUrl, model: resolved.modelId,
    protocol: resolved.protocol, endpoint: resolved.endpoint, headers: [],
    providerId: resolved.providerId };
  const windowTokens: number = await contextWindowForConnection(windowConn);
  const promptTemplate: string = resolveCompressPromptTemplate();
  if (windowTokens > 0) {
    const budget: number = Math.floor(windowTokens * COMPRESS_INPUT_RATIO_MAX);
    let shrinkRounds: number = 0;
    while (estimateTokens(
      buildCompressPrompt(promptTemplate, renderCompressTranscript(plan.compressible),
        supplement)) > budget) {
      // 尾部整轮回收（等于扩大保留段一轮）——重算选段；轮次收尽（null）或可压段跌破下限
      //（pick 内建判 null）即「收到底」
      shrinkRounds++;
      plan = pickCompressWindow(rows, COMPRESS_KEEP_ROUNDS + shrinkRounds,
        COMPRESS_MIN_COMPRESSIBLE);
      if (plan === null) {
        break;
      }
    }
    if (plan === null) {
      hilog.info(DOMAIN, TAG, '压缩输入收到底仍超窗口比例上限，本次放弃');
      return buildDraft(COMPRESS_STATUS_TOO_LONG, '', '', -1);
    }
  }
  // ★ 中断竞态闸（2026-09-23 自检轮补）：上面这条守卫链含四处 await（选段后的服务商/模型/
  // Key/窗口读数四次 IO），用户在这期间点关闭并确认「停止」时，在途位已被 cancelCompressDraft
  // 释放而请求句柄尚未登记（registerRequest 还没被回调到）——无本闸则请求照发照计费，用户
  // 眼里的「已停止」落空。闸与下面的 requestTitleText 调用之间**无 await**（prompt 拼装是
  // 同步的，句柄在 requestTitleText 体内同步登记），故「判代 → 登记」零窗口：取消只可能落在
  // 本闸之前（被闸拦下，零请求零消耗）或其之后（那时句柄已登记，destroy 生效）
  const owner: CompressInflight | undefined = inflight.get(conversationId);
  if (owner === undefined || owner.token !== entryToken) {
    hilog.info(DOMAIN, TAG, '发起前在途位已易主（用户中断或新一笔顶替），本次不发请求');
    return buildDraft(COMPRESS_STATUS_CANCELLED, '', '', -1);
  }
  // 请求（复用标题非流式通道；★ 上限传 COMPRESS_MAX_OUTPUT 常量——2026-09-23 输出上限
  // 治理笔脱挂会话助手 maxOutput〔那是给聊天回复设的旋钮，设小即「思考烧满正文恒空」在
  // 压缩链复活〕；★ 读超时 5 分钟——大输入一次性请求不照标题 30s，值与语义见常量注；
  // ★ onRequest 把句柄交给在途位登记，供用户中断时 destroy；taskLabel 压缩——面板上屏
  // 的失败文案不再错报「标题」）
  const prompt: string =
    buildCompressPrompt(promptTemplate, renderCompressTranscript(plan.compressible), supplement);
  const result: TitleRequestResult = await requestTitleText(resolved.baseUrl,
    resolved.modelId, resolved.protocol, resolved.endpoint, apiKey, prompt,
    COMPRESS_MAX_OUTPUT, COMPRESS_READ_MS, onRequest, COMPRESS_TASK_LABEL);
  // 用途记账（HTTP 200 即已消耗 token——正文缺失的 200 形态也入账；★ 本请求 usage 不回填
  // 上下文读数——锚点五条红线）
  if (result.status === 200) {
    logTaskUsage('compress', conversationId, resolved.providerId, resolved.modelId,
      result.promptTokens, result.completionTokens, result.cachedTokens);
  }
  // ★ 截断优先判（2026-09-23 输出上限治理笔）：排在 !ok 之前——截断时正文常为空/半截，
  // 先落「缺正文」类文案会把「输出上限不够」误报成「响应异常」，指错排查方向。取向登记：
  // 截断一律判失败（模型截断前已产出完整 summary 时可用摘要一并作废——先要「不落半截」；
  // 若真机确见「截断 + 完整 summary」形态再按任务书 §8④ 回改）
  if (result.truncated) {
    hilog.warn(DOMAIN, TAG, '压缩输出被上限截断（completion %{public}d token）',
      result.completionTokens);
    return buildDraft(COMPRESS_STATUS_FAILED, '',
      '压缩输出被上限截断，可换用输出上限更大的压缩模型，或缩短历史后重试', plan.coversToSeq);
  }
  if (!result.ok) {
    hilog.warn(DOMAIN, TAG, '压缩请求失败 status=%{public}d：%{public}s',
      result.status, result.errorMessage);
    return buildDraft(COMPRESS_STATUS_FAILED, '', result.errorMessage, plan.coversToSeq);
  }
  const summaryText: string = parseCompressOutput(result.text);
  if (summaryText === '') {
    hilog.warn(DOMAIN, TAG, '压缩输出解析为空（正文 %{public}d 字）', result.text.length);
    return buildDraft(COMPRESS_STATUS_FAILED, '', '压缩结果为空，可重试', plan.coversToSeq);
  }
  hilog.info(DOMAIN, TAG, '压缩摘要生成成功：%{public}d 字（边界 seq %{public}d）',
    summaryText.length, plan.coversToSeq);
  return buildDraft(COMPRESS_STATUS_READY, summaryText, '', plan.coversToSeq);
}
