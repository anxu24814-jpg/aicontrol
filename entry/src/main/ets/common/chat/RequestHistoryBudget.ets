// 请求历史预算域：「助手上下文条数 + 模型窗口 token」双闸的**零 I/O 纯函数集**——条数预算
// 解析、token 预算解析、按整轮回退的 token 裁剪、整请求输入侧估算。消费方五处同源（发送/
// 重试/离屏 web 发送/上下文用量面板/压缩选段，全部经 ChatRequestHistoryCtrl 或直接调用），
// 禁第二份实现。
// 零 I/O 且零平台依赖：唯一允许的 import = '../TokenEstimate'（估算原语单源，禁在本件重写
// 字符加权；断言脚本复制本件为 .ts 直跑时 TokenEstimate 同批复制到上一级保持相对层级成立）。
// 禁 import AiTypes（复制直跑断链）——消息形态用本地同构接口 BudgetRow 自持。
// 本件必须可被断言复制直跑且零 DB 依赖，不能混进有 DB / hilog 依赖的读口件或编排件。
// 摘要条识别契约：前缀判据沿用 RequestInject.COMPRESS_SUMMARY_OPEN，常量单源在彼件、经
// clipRoundsToTokenBudget 的 summaryPrefix 入参注入——本件不复制字面量、不自创第二种识别法。
// maxOutput 恒 0 契约：请求链估算恒传 0——输出空间由 0.7 系数的 30% 余量承担；再传真实
// maxOutput 会与余量双重扣减。
import { estimateTokens, IMAGE_TOKEN_ESTIMATE, MSG_FRAMING_TOKENS, toolCallsTokens }
  from '../TokenEstimate';

// 条数硬上限（内部常量；界面与帮助文案不出现该数——「0 为不限制」的语义外壳）
export const REQUEST_HISTORY_MAX_ROWS: number = 1024;

// token 预算系数：tokenBudget = floor(contextWindow × 0.7)；30% 余量承担输出与估算偏差
export const REQUEST_HISTORY_WINDOW_RATIO: number = 0.7;

// 裁剪水位系数（迟滞水位）：触发线仍 = token 预算（floor(窗×0.7)）不变，超线后不再「丢到
// 刚入预算即止」，而是一次裁到 floor(预算×本系数) 水位（≈59.5% 窗）。治「紧贴预算每发送丢
// 约 1 轮 → 历史前缀起点持续右移 → 隐式缓存历史段≈零命中」：头丢间隙内前缀逐字节稳定，
// OpenAI 族历史段命中率回到 ≈(N-1)/N。0.9 太保守（3~7 发一丢）、0.75 单次丢轮过深不采，
// 0.85 与钳制后的实际上限裁点同带自洽。
export const REQUEST_HISTORY_DROP_WATERMARK_RATIO: number = 0.85;

// k 校准闸门钳制界：g = clamp(k, 下限, 上限=1) **只放大不收紧** token 预算——k<下限（估算
// 偏大，中文典型 0.6）预算放大至多 1/0.7 ≈ 1.43×（治「中文实际裁点仅 ~42% 窗」；有效预算
// 单位仍是原始估算口径）；k>1 零收紧（g=1）。★ 为何上限收敛为 1（取消原收紧档）：收紧后的
// 预算进 clipRoundsToTokenBudget，单轮自身超收紧预算即触发既有 fail-open 整序原样发送——
// 预算越小「丢到只剩末轮仍超」越易成立（实测 k=1.5 → 2.58×窗整史 400），且 400 响应无
// usage、recordAnchor 不更新 k（不自愈）；收紧收益小于该风险。下限取 0.7 非 0.5/0.6 档
//（更低下限联合最坏 ≈1.68×窗口、400 几乎必然；0.7 档 stale-k 最坏 ≈1.2×窗口）。存储侧
// calibrateFactor 钳制 [0.2,5] 不变（存真值供显示面，闸门口径在本函数收窄）。消费恰两处
//（ChatRequestHistoryCtrl.fitTokens + ChatContextUsage.computeLive）同一 applyGateCalibration
// 单源——「面板与实发一致」纪律，只校准一侧即两口径分叉
export const REQUEST_HISTORY_GATE_FACTOR_MIN: number = 0.7;
export const REQUEST_HISTORY_GATE_FACTOR_MAX: number = 1;

// 工具调用载荷（与 AiTypes.AiToolCall 同构；零 import 自持——本域只判在场，不消费内容）
export interface BudgetToolCall {
  id: string;
  name: string;
  argsJson: string;
}

// 图片部件 / reasoning 输出项（与 AiTypes.AiImagePart / AiReasoningItem 同构；零 import 自持）
export interface BudgetImagePart { mimeType: string; data: string }
export interface BudgetReasoningItem { id: string; encryptedContent: string }

// 预算 / 裁剪 / 估算共用的消息行形态：**AiChatMessage 的完整本地同构镜像**（照
// RequestInject.InjectChatMessage 全字段镜像先例——裁剪输出的行要能无损还原回
// AiChatMessage：role/content/reasoning/toolCalls/toolCallId 为裁剪与估算消费面；
// toolName/images/reasoningItems/createdAt 为协议保真透传面〔漏 toolName =
// Gemini functionResponse 配对坏、漏 images = 本条 user 附件丢〕，本域不消费只随行；
// imageCount 为唯一派生位（由 images.length 折算，对齐 SendSnapshotItem 按张口径）。
export interface BudgetRow {
  role: string;          // 'system' | 'user' | 'assistant' | 'tool'
  content: string;
  reasoning: string;     // 仅 assistant 携带；无则 ''
  toolCalls?: BudgetToolCall[];  // 仅 assistant 携带（历史轮工具调用回传）
  toolCallId?: string;   // 仅 role='tool' 结果行携带
  toolName?: string;     // 仅 role='tool' 结果行携带（Gemini 配对必需）
  images?: BudgetImagePart[];    // 仅 user 携带（本条附件——裁剪永不丢末轮，随行保真）
  reasoningItems?: BudgetReasoningItem[]; // 仅 assistant（Responses 官方工具轮保真项）
  createdAt?: number;    // 时间提醒判定素材（序列化层不输出）
  imageCount: number;    // images.length 折算（估算消费面；无图 0）
}

// 整请求输入侧估算入参（systemText / toolDefsJson 由调用方从最终序列抽出；maxOutput 恒 0）
export interface BudgetEstimateInput {
  systemText: string;
  history: BudgetRow[];
  toolDefsJson: string;
  maxOutput: number;
}

// 条数预算：contextCount = 0（不限制）→ 硬上限；正数钳到硬上限；负数防御归 0
//（负值 = 坏数据——读口层恒不达〔高级设定滑块 0~1024〕，防御口径 = 宁可只发本条不放大）
export function resolveRowBudget(contextCount: number): number {
  if (contextCount < 0) {
    return 0;
  }
  if (contextCount === 0) {
    return REQUEST_HISTORY_MAX_ROWS;
  }
  return Math.min(contextCount, REQUEST_HISTORY_MAX_ROWS);
}

// 读口实际读取条数 = 预算 − 1：预算是「含本条 user」口径（与 clipHistoryTail 现状一致），
// 本条 user 由 ChatRequestHistoryCtrl 按 userReq 入参在返回前 push——读口与组装链都不得
// 再做一次口径转换，转换只在本函数。预算 ≤ 1 → 0（只发本条）。
// ★ 重试链例外在 Ctrl.load 一处换算：userReq = null（锚点 user 已在库内、读出的 rows 天然
// 含锚点）时读全额预算——发送与重试两条数一致。
export function resolveReadRows(contextCount: number): number {
  const budget: number = resolveRowBudget(contextCount);
  return budget > 0 ? budget - 1 : 0;
}

// token 预算：windowTokens ≤ 0（无参考值）→ 0 = 不做 token 裁剪（fail-open 维持现状）；
// 否则 floor(window × 0.7)。floor 后为 0（窗口极小）同样视作 0 = 不裁，需调用方显式钉。
export function resolveTokenBudget(windowTokens: number): number {
  if (windowTokens <= 0) {
    return 0;
  }
  return Math.floor(windowTokens * REQUEST_HISTORY_WINDOW_RATIO);
}

// 闸门预算校准：对已解析的 token 预算按钳制值 g = clamp(k, MIN, 1) 整体换算 floor(预算/g)
//——k<0.7 放大预算（最多 ≈1.43×），k≥1 零收紧（规避「收紧预算 → 单轮超预算 → fail-open
// 整史全发」）。k 非法（NaN/≤0/非有限）视 1 → 原值逐字节返回（k 未积累期零漂移）；
// maxTokens ≤ 0 → 0（校准不改变不裁语义）；估算与裁剪全程原始估算单位，只预算侧换算
//（rowTokens / 断言 / 面板分段零改动面）；角色分离：显示缩放继续用原 factor（computeLive
// 显示面恒 ×k），本函数只服务闸门口径，两角色禁混用。
export function applyGateCalibration(maxTokens: number, k: number): number {
  if (maxTokens <= 0) {
    return 0;
  }
  const safeK: number = Number.isFinite(k) && k > 0 ? k : 1;
  const g: number = Math.min(Math.max(safeK, REQUEST_HISTORY_GATE_FACTOR_MIN),
    REQUEST_HISTORY_GATE_FACTOR_MAX);
  return Math.floor(maxTokens / g);
}

// 单行输入侧 token（估算原语单源 TokenEstimate；system 行内容跳过——由 systemText 单列，
// 只计帧开销，与 estimateSegments 的 history 分桶同口径）
function rowTokens(m: BudgetRow): number {
  if (m.role === 'user') {
    return estimateTokens(m.content) + m.imageCount * IMAGE_TOKEN_ESTIMATE + MSG_FRAMING_TOKENS;
  }
  if (m.role === 'assistant') {
    // 工具调用参数计入：BudgetRow 自带 toolCalls（历史轮回传），计数单源 =
    // TokenEstimate.toolCallsTokens——与估算快照/k 分母三面同值，禁第二实现
    return estimateTokens(m.content) + estimateTokens(m.reasoning) +
      toolCallsTokens(m.toolCalls) + MSG_FRAMING_TOKENS;
  }
  if (m.role === 'tool') {
    return estimateTokens(m.content) + MSG_FRAMING_TOKENS;
  }
  return MSG_FRAMING_TOKENS;
}

// 整请求输入侧估算：systemText + 注入后历史 + 工具声明串 + 逐行帧开销；maxOutput > 0 才
// 计预留输出段（请求链恒传 0——防与 0.7 余量双重扣减）。system 行内容不入（systemText
// 单列，双重计数防线）。
export function estimateRequestTokens(input: BudgetEstimateInput): number {
  let total: number = estimateTokens(input.systemText) + estimateTokens(input.toolDefsJson);
  for (const m of input.history) {
    total += rowTokens(m);
  }
  if (input.maxOutput > 0) {
    total += input.maxOutput;
  }
  return total;
}

// 按整轮裁到 token 预算内：
// · maxTokens ≤ 0 → 不裁（token 闸未启用），原引用返回；
// · 头部保留区 = 到第一条「非摘要 user」之前的全部行（system 注入行、压缩摘要条、首轮前
//   注入消息）——永不丢弃；
// · 轮 = 一条 user 起、到下一 user 之前（含 assistant、tool 结果）为一个原子组，从头部
//   整轮丢弃；摘要条（summaryPrefix 前缀判据）永不丢弃、不作轮首候选；
// · 迟滞水位：触发判据仍「total ≤ 预算 → 原引用返回」不变；越线后一次裁到
//   floor(预算 × REQUEST_HISTORY_DROP_WATERMARK_RATIO) 水位（丢到刚入水位即止；丢不出
//   水位时退求入预算线）；丢到只剩最后一轮仍超**预算线** = 单轮自身超预算 → **整序原样
//   返回**（fail-open 宁多带不可误删，判据对 maxTokens 原值不对水位）；
// · 工具对原子性：按轮裁剪天然不产生孤儿 tool 开头（保留起点恒为轮首 user 或保留区）；
//   末尾防御只挡脏输入（输出首行 role='tool' = 配对 assistant 缺位 → 整序回退不裁）。
// · maxTokens 语义 = history 侧可用预算：调用方（ChatRequestHistoryCtrl.fitTokens）已从
//   总预算扣除 systemText 与 toolDefsJson 的估算量——本件零 I/O，不吃 system / tools 原文。
export function clipRoundsToTokenBudget(rows: BudgetRow[], maxTokens: number,
  summaryPrefix: string): BudgetRow[] {
  if (maxTokens <= 0 || rows.length === 0) {
    return rows;
  }
  let headEnd: number = 0;
  for (let i = 0; i < rows.length; i++) {
    const r: BudgetRow = rows[i];
    if (r.role === 'user' && !r.content.startsWith(summaryPrefix)) {
      break;
    }
    headEnd = i + 1;
  }
  const roundStarts: number[] = [];
  for (let i = headEnd; i < rows.length; i++) {
    const r: BudgetRow = rows[i];
    if (r.role === 'user' && !r.content.startsWith(summaryPrefix)) {
      roundStarts.push(i);
    }
  }
  if (roundStarts.length === 0) {
    return rows;
  }
  let total: number = 0;
  for (const r of rows) {
    total += rowTokens(r);
  }
  if (total <= maxTokens) {
    return rows;
  }
  // 迟滞水位：停机目标自预算线下沉到 floor(预算 × REQUEST_HISTORY_DROP_WATERMARK_RATIO)
  //——触发线不动（上方 total ≤ maxTokens 已原引用返回，预算内会话零行为变化）；此处
  // maxTokens 恒 > 0，水位恒 ≥ 0，不会误入死循环
  const targetTokens: number = Math.floor(maxTokens * REQUEST_HISTORY_DROP_WATERMARK_RATIO);
  let dropRounds: number = 0;
  while (dropRounds < roundStarts.length - 1 && total > targetTokens) {
    const from: number = roundStarts[dropRounds];
    const to: number = dropRounds + 1 < roundStarts.length ?
      roundStarts[dropRounds + 1] : rows.length;
    for (let i = from; i < to; i++) {
      total -= rowTokens(rows[i]);
    }
    dropRounds++;
  }
  // fail-open 判据对 maxTokens 原值（非水位）：丢到只剩末轮时若连预算线都压不进 → 整序
  // 原样保留；已进预算线但停在 (水位, 预算] 区间 = 水位够不着时退求入预算——接受
  if (total > maxTokens) {
    return rows;
  }
  // 保留区（system / 摘要条 / 首轮前注入，[0, headEnd)）整段拼回裁剪后段——slice 单起点会
  // 把保留区一起丢掉（保留区在索引头部、轮起点在其后，两者不相邻）
  const out: BudgetRow[] =
    rows.slice(0, headEnd).concat(rows.slice(roundStarts[dropRounds]));
  if (out.length > 0 && out[0].role === 'tool') {
    return rows;
  }
  return out;
}
