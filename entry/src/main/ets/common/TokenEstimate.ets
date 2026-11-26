// 会话上下文用量·估算纯函数域，含上下文窗口值解析/格式化。「已用」= 预估的本次请求输入
// token 量 = estimateTokens(当前发送序列) × k，k = 锚点真值 ÷ 锚点时刻估算（每模型一份，
// 发送链落偏好键）。精度不重要——k 会吸收系统性偏差。
// ★ 竞品实证红线（防后人改回）：
//   ① 锚点只进 k 的计算，绝不直接当「已用」显示（直接显示上一轮已完成请求的 token 数会漏
//     掉本轮新增内容，UI 50% 实发 100%+）——本域只提供估算与比例尺；
//   ② 只认 input 侧字段（promptTokens），不认 totalTokens（Cherry 源码注释直呼 total 是
//     "bogus anchor"）——锚点取值在 ChatSendCtrl，本域不碰流；
//   ③ k 的分子分母同口径：估算序列必须是「全量文本」（含 reasoning 回传、图片折算与工具
//     调用 argsJson），混比会凭空造出假倍数；
//   ④ 异常值挡在 k 之外：calibrateFactor 钳制 [0.2, 5]，哨兵/NaN/≤0 回退 1.0（LibreChat：
//     哨兵 MAX_SAFE_INTEGER 被当真实计数，账单算出 495 亿美元）；
//   ⑤ 遍历完整性：分段遍历必须覆盖全部消息形态——user 文本 / assistant 文本 / assistant
//     回传 reasoning / assistant 工具调用参数（argsJson）/ role='tool' 结果行 / images 按张
//     折算，漏任一种即「估算漏算 → 实际爆窗」（sse-assert 120 组逐形态钉）。
// 图片按张固定值 IMAGE_TOKEN_ESTIMATE：端侧无可靠公式（分辨率/tile 各家不同），锚点校准会
// 吸收其偏差（图片数固定的会话，k 自然把每张图的真实开销折算进去）。
// 零 import 纯函数约束（scripts/sse-assert.mjs 复制本文件为 .ts 直跑，120 组断言的线上同一
// 实现；窗口值两函数自 ModelContextCard.ets 迁入，同守该约束）。

// token 数缩略（≥1000 缩 k 一位小数）——上下文面板与用量气泡同口径
export function tokenShort(n: number): string {
  return n >= 1000 ? (Math.round(n / 100) / 10) + 'k' : String(n);
}

// ── 上下文窗口值解析/格式化（自 ModelContextCard.ets 迁入，同守零 import）──

// 手动输入上限（防呆：千万 token；越界与非法输入一律回 -1 由调用方拦——P0-1 不静默）
export const MAX_CONTEXT_INPUT: number = 10000000;

// 输入解析：'1048576' / '1m' / '500k' / '0' / '1,048,576' → 数值；非法或越界（空串、小数、
// 带非数字前缀）→ -1 由调用方拦（P0-1 不静默）。★ 禁 parseInt 吃前缀的宽松式（'12abc' 会被
// 吃成 12）——纯数字段逐字符验数字；后缀 k ×1024 / m ×1024²（与快捷档同口径）；0 合法
//（= 清用户值回未配置）
export function parseContextTokenInput(text: string): number {
  const raw: string = text.trim().toLowerCase();
  if (raw === '') {
    return -1;
  }
  let digits: string = raw;
  let multiplier: number = 1;
  const last: string = raw.charAt(raw.length - 1);
  if (last === 'k') {
    digits = raw.slice(0, raw.length - 1);
    multiplier = 1024;
  } else if (last === 'm') {
    digits = raw.slice(0, raw.length - 1);
    multiplier = 1024 * 1024;
  }
  // 规范千分位（formatContextTokens 输出的 '1,048,576' 须能粘回输入框）：首组 1~3 位、其后
  // 每段恰 3 位，段间单逗号；余下仍逐字符数字校验（'1,2a4' 照拒）
  if (digits.includes(',')) {
    const groups: string[] = digits.split(',');
    let valid: boolean = true;
    for (let i = 0; i < groups.length; i++) {
      const g: string = groups[i];
      const bad: boolean = i === 0 ? (g.length < 1 || g.length > 3) : g.length !== 3;
      if (bad) {
        valid = false;
        break;
      }
    }
    if (!valid) {
      return -1;
    }
    digits = groups.join('');
  }
  if (digits.length === 0) {
    return -1;
  }
  for (let i = 0; i < digits.length; i++) {
    const code: number = digits.charCodeAt(i);
    if (code < 48 || code > 57) {
      return -1;
    }
  }
  const n: number = Number(digits) * multiplier;
  if (!Number.isFinite(n) || n < 0 || n > MAX_CONTEXT_INPUT) {
    return -1;
  }
  return n;
}

// 千分位格式化：1048576 → '1,048,576'；0 → '0'。★ 自实现——ArkTS 环境不依赖 toLocaleString
//（数值本地化不可控）；负数不出现（调用方只在 > 0 时展示）
export function formatContextTokens(n: number): string {
  const s: string = String(Math.trunc(n));
  let out: string = '';
  let count: number = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    out = s.charAt(i) + out;
    count++;
    if (count % 3 === 0 && i > 0) {
      out = ',' + out;
    }
  }
  return out;
}

// ── 逐字符分类加权（系数基准：保守口径，偏差交给 k）──
// CJK 及全角标点 1.0/码（中文 1 字 ≈ 1 token：Claude 系约 1.0、GPT 系约 0.6，取上界）
const WEIGHT_ASCII: number = 0.25;  // ASCII 0.25/字符（英文约 4 字符/token）
const WEIGHT_OTHER: number = 0.6;   // 其他（拉丁扩展/代理对/emoji）0.6/码元

// CJK 判定（BMP 码元级；代理对〔含 CJK 扩展 B+〕按「其他」0.6/码元计——两端各半，整体 ≈1.2/字）
function isCjkCodeUnit(c: number): boolean {
  return (c >= 0x3000 && c <= 0x303F) ||   // CJK 符号和标点（。「」等）
    (c >= 0x3400 && c <= 0x4DBF) ||        // CJK 统一表意文字扩展 A
    (c >= 0x4E00 && c <= 0x9FFF) ||        // CJK 统一表意文字
    (c >= 0xF900 && c <= 0xFAFF) ||        // CJK 兼容表意文字
    (c >= 0xFF00 && c <= 0xFFEF);          // 全角形式（，！？Ａ等）
}

// 未取整 token 权重（工具定义分组拆段的分配比例用——分组各自 round 会漂 ±(组数-1)，须以
// 未取整权重定「残差归谁」；estimateTokens = round(本值)）
function rawTokenUnits(text: string): number {
  if (text === '') {
    return 0;
  }
  let units: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if (c <= 0x7F) {
      units += WEIGHT_ASCII;
    } else if (isCjkCodeUnit(c)) {
      units += 1.0;
    } else {
      units += WEIGHT_OTHER;
    }
  }
  return units;
}

// 文本 token 估算（UTF-16 码元遍历；空串 = 0；四舍五入取整）
export function estimateTokens(text: string): number {
  return Math.round(rawTokenUnits(text));
}

// 图片按张固定估算（张；理由见头注释）
export const IMAGE_TOKEN_ESTIMATE: number = 900;

// 每条消息的协议包装开销（JSON 帧/角色键等）：计入总量但不入命名段——正是「其他」兜底段的
// 来源（★ 可加总红线：分段之和 ≤ 总量，差额并入「其他」，Claude Code 同屏矛盾的反面）
export const MSG_FRAMING_TOKENS: number = 4;

// 工具调用计数形态（最小计数面 = 工具名 + 参数 JSON 原串——AiToolCall 与 BudgetToolCall 均
// 为本形态超集）；零 import 域内新增符号，同守纯函数约束
export interface ToolCallArgLike {
  name: string;
  argsJson: string;
}

// 工具调用 token 估算（U1 计数单源——「该计什么、怎么计」只此一份，估算快照 / token 闸 /
// k 分母三面同源消费，禁第二实现）：逐条 estimateTokens(name) + estimateTokens(argsJson)
// 求和；undefined / 空数组回 0。口径克制：不计 id（客户端自造时间戳串）与协议帧包装（每调用
// 约 8~15 token 量级恒小——真机反馈工具重会话仍偏低再议 TOOL_CALL_FRAMING_TOKENS 常量）。
// `?? ''` 是对未标注直跑字面量的防御（缺字段退化不炸）
export function toolCallsTokens(calls: ToolCallArgLike[] | undefined): number {
  if (calls === undefined || calls.length === 0) {
    return 0;
  }
  let total: number = 0;
  for (const c of calls) {
    total += estimateTokens(c.name ?? '') + estimateTokens(c.argsJson ?? '');
  }
  return total;
}

// 发送序列条目（role 事实值 'system'|'user'|'assistant'|'tool'；system 行不入段——其内容
// 已由提示词/技能清单/记忆三段单列覆盖，计入即双重计数）。★ 遍历完整性：text 覆盖
// user/assistant/tool 三种正文，reasoning 覆盖 assistant 回传思考（OpenAI 路径进输入），
// imageCount 覆盖图片按张折算，toolCalls 覆盖 assistant 工具调用参数——六种消息形态全走本
// 结构，断言逐形态钉
export interface SendSnapshotItem {
  role: string;
  text: string;
  reasoning: string;   // 仅 assistant 携带；无则 ''
  imageCount: number;  // 仅 user 携带（附件仅随当前轮）；无则 0
  // 工具调用参数：仅 assistant 携带（argsJson 进请求体四协议全带，漏计即「估算漏算→实际
  // 爆窗」）。可选字段缺省自然退化不计（直跑字面量缺字段不炸）
  toolCalls?: ToolCallArgLike[];
}

// 工具定义分组（**面板活算口径**）：key ∈ {'tools_builtin'（内置与模式驱动件），
// 'tools_mcp'（MCP 服务器组——同 key 多组共存，面板段符号按 key 映射、行区分靠 label）}；
// label = 组名 UI 文案（该 server 发生超预算整件移除时生产方在 label 尾注「（M 件超预算未
// 带）」）；defsJson = 组内工具声明拼串（与 ChatContextUsage.toolDefsJsonOf 同源——分组段
// token 由本字段估出）
export interface ToolDefGroup {
  key: string;
  label: string;
  defsJson: string;
}

// 组装快照（纯数据）：systemText = 三级解析+变量替换后的注入内容；skillManifest/memoryBlock
// = 技能清单/记忆块（空串 = 不列段）；toolDefsJson = 工具声明 name+description+
// parametersJson 逐条拼串；history = 截尾后的历史（含本轮 user——★ 只能是 clipHistoryTail
// 之后的序列，截尾前的不是真发送序列）；draftText/imageCount/pendingAttachText = 待发输入
// 三件（草稿文本 / 视觉通道张数 / 附件协议文本侧内容——面板打开时取一次，不随打字刷）；
// maxOutput = 助手高级设定预留输出（0 = 不列段）。★ pendingAttachText 只在**面板活算**传值：
// 发送链定格（beginRound / refreshEstimate）恒传 ''——实发序列里本轮 user 已含附件正文
//（ChatSendCtrl.dispatchSend 的 protocolText），此处再计即双算（估算面必须与实际发送面
// 同口径）
export interface SendSnapshot {
  systemText: string;
  skillManifest: string;
  memoryBlock: string;
  // 知识注入估算文本（v51 世界书关键词触发笔）：**面板活算口径**（全量 = 系统位命中块 +
  // 深度条目 content 拼接——ChatContextUsage.computeLive 用，其历史为注入前序列，深度内容只
  // 此一处计）；★ 发送链 beginRound 分母侧只取系统块（分母历史已含深度注入的落行文本，再计
  // 全量即双算——见 ChatSendCtrl.assembleRound「只计不落进历史行的部分」注）；两路同源同一
  // buildKnowledgeBlock plan，禁第二实现；'' = 不列段
  knowledge: string;
  toolDefsJson: string;
  // 工具定义分组：null = 无分组（发送链定格与直跑字面量缺字段的自然退化——估算总量口径
  // 不变）；有分组时 estimateSegments 按组列段替换 'tools' 单段。`?? null` 防御直跑字面量
  toolDefGroups: ToolDefGroup[] | null;
  history: SendSnapshotItem[];
  draftText: string;
  imageCount: number;
  pendingAttachText: string;
  maxOutput: number;
}

// 分段（九段口径，方案 §3.4；key 供消费方映射段色，label = UI 文案）
export interface ContextSegment {
  key: string;
  label: string;
  tokens: number;
}

// 分段估算：空段不列（技能清单 ''/记忆 ''/工具 [] 等零开销面零噪声）；history 按 role 分
// 三桶（用户/助手/工具结果）；图片恒并入「本轮输入」段（历史 user 行的 imageCount 同源）。
// 返回的命名段**不含**「其他」与「空闲」——两者由总量减法派生（estimateSnapshotTotal /
// 消费方），保证★「分段之和 ≤ 总量、差额可归因」的可加总结构
export function estimateSegments(snapshot: SendSnapshot): ContextSegment[] {
  const segments: ContextSegment[] = [];
  if (snapshot.systemText !== '') {
    segments.push({ key: 'prompt', label: '提示词', tokens: estimateTokens(snapshot.systemText) });
  }
  if (snapshot.skillManifest !== '') {
    segments.push({ key: 'skills', label: '技能清单', tokens: estimateTokens(snapshot.skillManifest) });
  }
  if (snapshot.memoryBlock !== '') {
    segments.push({ key: 'memory', label: '记忆', tokens: estimateTokens(snapshot.memoryBlock) });
  }
  // 知识注入段（与记忆段同款「空段不列」零噪声口径）。`?? ''` 防御直跑字面量
  const knowledgeText: string = snapshot.knowledge ?? '';
  if (knowledgeText !== '') {
    segments.push({ key: 'knowledge', label: '知识注入', tokens: estimateTokens(knowledgeText) });
  }
  // 工具定义段：有分组按组列段，无分组退旧单段。★ 加总红线 R5：各组段 token 之和 = 无分组
  // 单段 token（同一 toolDefsJson 两口径，「分段之和 ≤ 总量、差额可归因」不因拆段破）——各组
  // 先按本组 defsJson 独立取整，凑整残差归**原始权重最大组**（锚定单段总量 round(全文)；
  // 分组各自独立四舍五入会漂 ±(组数-1)）。空组（defsJson ''）不列段（零 token 不减和）
  const toolGroups: ToolDefGroup[] | null = snapshot.toolDefGroups ?? null;
  if (toolGroups !== null && toolGroups.length > 0) {
    const totalToolsTokens: number = estimateTokens(snapshot.toolDefsJson);
    const groupSegs: ToolDefGroup[] = [];
    const groupRaws: number[] = [];
    const groupTokens: number[] = [];
    for (const g of toolGroups) {
      if (g.defsJson === '') {
        continue;
      }
      groupSegs.push(g);
      groupRaws.push(rawTokenUnits(g.defsJson));
      groupTokens.push(estimateTokens(g.defsJson));
    }
    if (groupSegs.length > 0) {
      let maxIdx: number = 0;
      let othersSum: number = 0;
      for (let i: number = 0; i < groupSegs.length; i++) {
        if (groupRaws[i] > groupRaws[maxIdx]) {
          maxIdx = i;
        }
      }
      for (let i: number = 0; i < groupSegs.length; i++) {
        if (i !== maxIdx) {
          othersSum += groupTokens[i];
        }
      }
      groupTokens[maxIdx] = totalToolsTokens - othersSum;
      for (let i: number = 0; i < groupSegs.length; i++) {
        segments.push({ key: groupSegs[i].key, label: groupSegs[i].label,
          tokens: groupTokens[i] });
      }
    }
  } else if (snapshot.toolDefsJson !== '') {
    segments.push({ key: 'tools', label: '工具定义', tokens: estimateTokens(snapshot.toolDefsJson) });
  }
  let userTokens: number = 0;
  let assistantTokens: number = 0;
  let toolTokens: number = 0;
  let historyImages: number = 0;
  for (const m of snapshot.history) {
    if (m.role === 'user') {
      userTokens += estimateTokens(m.text);
      historyImages += m.imageCount;
    } else if (m.role === 'assistant') {
      // reasoning 与工具调用参数并入助手段（回传思考占输入；argsJson 随请求体重发、随历史
      // 累计放大——并入既有 key='assistant' 段不加新段，缺字段天然退化 0）
      assistantTokens += estimateTokens(m.text) + estimateTokens(m.reasoning) +
        toolCallsTokens(m.toolCalls);
    } else if (m.role === 'tool') {
      toolTokens += estimateTokens(m.text);
    }
    // 'system' 行跳过：内容已由前三段单列覆盖（见 SendSnapshotItem 注释）
  }
  if (userTokens > 0) {
    segments.push({ key: 'user', label: '用户消息', tokens: userTokens });
  }
  if (assistantTokens > 0) {
    segments.push({ key: 'assistant', label: '助手回复', tokens: assistantTokens });
  }
  if (toolTokens > 0) {
    segments.push({ key: 'toolResults', label: '工具结果', tokens: toolTokens });
  }
  // 待发附件协议文本侧内容（doc 解析正文 / OCR 文本 / 文本附件内容——与发送链单源，
  // AttachmentUtil.pendingAttachFootprint）。`?? ''` 防御直跑字面量（缺字段即 undefined，
  // `!== ''` 判不出去）
  const draftTokens: number = estimateTokens(snapshot.draftText) +
    estimateTokens(snapshot.pendingAttachText ?? '') +
    (snapshot.imageCount + historyImages) * IMAGE_TOKEN_ESTIMATE;
  if (draftTokens > 0) {
    segments.push({ key: 'draft', label: '本轮输入', tokens: draftTokens });
  }
  if (snapshot.maxOutput > 0) {
    segments.push({ key: 'reserved', label: '预留输出', tokens: snapshot.maxOutput });
  }
  return segments;
}

// 总量估算 = 命名段之和 + 每条消息协议包装（帧开销）；恒 ≥ 分段之和（差额 = 包装，即「其他」
// 兜底段的来源）。发送链用它当 pendingEstimate（k 的分母侧——与服务商回传 promptTokens 同
// 口径的全量输入）
export function estimateSnapshotTotal(snapshot: SendSnapshot): number {
  let total: number = 0;
  const segments: ContextSegment[] = estimateSegments(snapshot);
  for (const s of segments) {
    total += s.tokens;
  }
  total += snapshot.history.length * MSG_FRAMING_TOKENS;
  return total;
}

// ── 小值段合并——已退役（决明拍板「全部豁免合并，以免看不出来合并了什么」）──
// 本工程命名段数有界（≤12）不存在「零碎行淹没主要矛盾」问题，合并只制造不可见黑盒；
// **全段恒单独上屏**。原两符号（合并函数与阈值常量）全仓删除，退役净度由 sse-assert
// 120 组防回流钉守。

// ── 校准系数（红线④⑤的代码面）──
// k = 真实输入 ÷ 发送时估算；pendingEstimate ≤ 0 / 真值 ≤ 0 / NaN / Infinity 回 1.0（纯估
// 算态），成品钳制 [0.2, 5]（异常锚点不得进显示链——超界即「锚点本身可疑」，回 1 比带毒
// 校准安全）
export const FACTOR_MIN: number = 0.2;
export const FACTOR_MAX: number = 5;

export function calibrateFactor(realPromptTokens: number, pendingEstimate: number): number {
  if (!Number.isFinite(realPromptTokens) || !Number.isFinite(pendingEstimate)) {
    return 1;
  }
  if (realPromptTokens <= 0 || pendingEstimate <= 0) {
    return 1;
  }
  const k: number = realPromptTokens / pendingEstimate;
  if (!Number.isFinite(k)) {
    return 1;
  }
  if (k < FACTOR_MIN) {
    return FACTOR_MIN;
  }
  if (k > FACTOR_MAX) {
    return FACTOR_MAX;
  }
  return k;
}
