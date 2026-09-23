// 会话上下文用量·估算纯函数域，含上下文窗口值解析/格式化（2026-09-17 方案-会话上下文
// 用量 执行笔 1；窗口值两函数 2026-09-21 自 ModelContextCard.ets 迁入，B-11④）：
// 「已用」= 预估的本次请求输入 token 量 = estimateTokens(当前发送序列) × k，k = 锚点真值 ÷
// 锚点时刻估算（每模型一份，发送链落偏好键）。精度不重要——k 会吸收系统性偏差（方案 §3.2）；
// ★ 竞品实证红线（方案附录 A，实施时写进注释防后人改回）：
//   ① 锚点只进 k 的计算，绝不直接当「已用」显示（Cline #7383：直接显示上一轮已完成请求的
//     token 数会漏掉本轮新增内容，UI 50% 实发 100%+）——本域只提供估算与比例尺；
//   ② 只认 input 侧字段（promptTokens），不认 totalTokens（Cherry 源码注释直呼 total 是
//     "bogus anchor"）——锚点取值在 ChatSendCtrl，本域不碰流；
//   ③ k 的分子分母同口径：估算序列必须是「全量文本」（含 reasoning 回传与图片折算），
//     混比会凭空造出假倍数（Cherry #18351 报告人自我更正的假 4×）；
//   ④ 异常值挡在 k 之外：calibrateFactor 钳制 [0.2, 5]，哨兵/NaN/≤0 回退 1.0（LibreChat
//     #14661：哨兵 MAX_SAFE_INTEGER 被当真实计数，账单算出 495 亿美元）；
//   ⑤ 遍历完整性：分段遍历必须覆盖全部消息形态——user 文本 / assistant 文本 / assistant
//     回传 reasoning / role='tool' 结果行 / images 按张折算，漏任一种即「估算漏算 → 实际
//     爆窗」（Cherry #17079：内嵌图片计 0，显示 339.8K 实发 1.16M；sse-assert 120 组逐形态钉）。
// 图片按张固定值 IMAGE_TOKEN_ESTIMATE：端侧无可靠公式（分辨率/tile 各家不同），锚点校准会
// 吸收其偏差（图片数固定的会话，k 自然把每张图的真实开销折算进去）。
// 零 import 纯函数约束（照 RequestInject/RequestCompose——scripts/sse-assert.mjs 复制本文件
// 为 .ts 直跑，120 组断言的线上同一实现）。本件于 2026-09-21 收纳上下文窗口值解析/格式化
// 两纯函数（B-11④，自 ModelContextCard.ets 迁入），同守零 import 约束。

// token 数缩略（≥1000 缩 k 一位小数）——2026-09-17 自 ChatMessageItem.tokenShort 提取共用
//（上下文面板与用量气泡同口径；122 组钉同值）
export function tokenShort(n: number): string {
  return n >= 1000 ? (Math.round(n / 100) / 10) + 'k' : String(n);
}

// ── 上下文窗口值解析/格式化（2026-09-21 自 ModelContextCard.ets 迁入，B-11④——迁零
// import 叶子即获得 sse-assert 复制直跑的执行级断言面）──

// 手动输入上限（防呆：千万 token；越界与非法输入一律回 -1 由调用方拦——P0-1 不静默）
export const MAX_CONTEXT_INPUT: number = 10000000;

// 输入解析（纯函数，模块级 export 照 AssistantContextPage.formatTokenText 先例）：
// '1048576' / '1m' / '500k' / '0' / '1,048,576' → 数值；非法或越界（含空串、小数、带非数字
// 前缀）→ -1。★ 禁 parseInt 吃前缀的宽松式（'12abc' 会被吃成 12）——纯数字段逐字符验数字；
// 后缀 k ×1024 / m ×1024²（与快捷档同口径）；0 合法（= 清用户值回未配置）
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
  // 规范千分位（2026-09-21 B-11②）：本应用 formatContextTokens 输出的 '1,048,576' 须能粘回
  // 输入框——首组 1~3 位、其后每段恰 3 位，段间单逗号；余下仍走逐字符数字校验（'1,2a4' 照拒）
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

// 千分位格式化（纯函数）：1048576 → '1,048,576'；0 → '0'。★ 自实现——ArkTS 环境不依赖
// toLocaleString（数值本地化不可控）；负数不出现（调用方只在 > 0 时展示）
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

// ── 逐字符分类加权（方案 §4.1 系数基准：保守口径，偏差交给 k）──
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

// 文本 token 估算（UTF-16 码元遍历；空串 = 0；四舍五入取整）
export function estimateTokens(text: string): number {
  if (text === '') {
    return 0;
  }
  let units: number = 0;
  for (let i = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if (c <= 0x7F) {
      units += WEIGHT_ASCII;
    } else if (isCjkCodeUnit(c)) {
      units += 1.0;
    } else {
      units += WEIGHT_OTHER;
    }
  }
  return Math.round(units);
}

// 图片按张固定估算（张；理由见头注释）
export const IMAGE_TOKEN_ESTIMATE: number = 900;

// 每条消息的协议包装开销（JSON 帧/角色键等）：计入总量但不入命名段——正是「其他」兜底段
// 的来源（可加总红线：分段之和 ≤ 总量，差额并入「其他」，Claude Code #18241 同屏矛盾的反面）
export const MSG_FRAMING_TOKENS: number = 4;

// 发送序列条目（role 事实值 'system'|'user'|'assistant'|'tool'；system 行不入段——其内容
// 已由提示词/技能清单/记忆三段单列覆盖，计入即双重计数）。★ 遍历完整性：text 覆盖
// user/assistant/tool 三种正文，reasoning 覆盖 assistant 回传思考（OpenAI 路径进输入），
// imageCount 覆盖图片按张折算——五种消息形态全走本结构，断言逐形态钉
export interface SendSnapshotItem {
  role: string;
  text: string;
  reasoning: string;   // 仅 assistant 携带；无则 ''
  imageCount: number;  // 仅 user 携带（附件仅随当前轮）；无则 0
}

// 组装快照（纯数据，方案 §4.1）：systemText = 三级解析+变量替换后的注入内容；
// skillManifest/memoryBlock = 技能清单/记忆块（空串 = 不列段）；toolDefsJson = 工具声明
// name+description+parametersJson 逐条拼串；history = 截尾后的历史（含本轮 user——
// ★ 只能是 clipHistoryTail 之后的序列，截尾前的不是真发送序列，方案 §六-2）；
// draftText/imageCount/pendingAttachText = 待发输入三件（草稿文本 / 视觉通道张数 / 附件
// 协议文本侧内容——面板打开时取一次，不随打字刷）；maxOutput = 助手高级设定预留输出
//（0 = 不列段）。★ pendingAttachText 只在**面板活算**传值：发送链定格（beginRound /
// refreshEstimate）恒传 ''——实发序列里本轮 user 已含附件正文（ChatSendCtrl.dispatchSend
// 的 protocolText），此处再计即双算（P2-5 言行一致的反面：估算面必须与实际发送面同口径）
export interface SendSnapshot {
  systemText: string;
  skillManifest: string;
  memoryBlock: string;
  toolDefsJson: string;
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
// 消费方），保证「分段之和 ≤ 总量、差额可归因」的可加总结构
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
  if (snapshot.toolDefsJson !== '') {
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
      // reasoning 计入助手段（回传思考占输入，OpenAI/Responses 路径——漏算即低估）
      assistantTokens += estimateTokens(m.text) + estimateTokens(m.reasoning);
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
  // AttachmentUtil.pendingAttachFootprint）。`?? ''` 是对未标注的直跑字面量的防御（sse-assert
  // 的 .mjs 字面量无类型检查——缺字段即 undefined，`!== ''` 判不出去）
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

// 总量估算 = 命名段之和 + 每条消息协议包装（帧开销）；恒 ≥ 分段之和（差额 = 包装，
// 即「其他」兜底段的来源）。发送链用它当 pendingEstimate（k 的分母侧——与服务商回传的
// promptTokens 同口径的全量输入）
export function estimateSnapshotTotal(snapshot: SendSnapshot): number {
  let total: number = 0;
  const segments: ContextSegment[] = estimateSegments(snapshot);
  for (const s of segments) {
    total += s.tokens;
  }
  total += snapshot.history.length * MSG_FRAMING_TOKENS;
  return total;
}

// ── 小值段合并（方案 §3.4；Claude Code #92881：大量 0 token 条目淹没重要分类）──
// 占比 < 1% 且绝对值 < 200 token 的段并成「其余 N 段」汇总行；windowTokens ≤ 0（未知，
// 不显分段条的场景）原样返回。合并只动展示面，不改命名段口径
export const SMALL_SEGMENT_MAX_TOKENS: number = 200;

export function mergeSmallSegments(segments: ContextSegment[], windowTokens: number): ContextSegment[] {
  if (windowTokens <= 0) {
    return segments;
  }
  const kept: ContextSegment[] = [];
  const small: ContextSegment[] = [];
  for (const s of segments) {
    if (s.tokens < SMALL_SEGMENT_MAX_TOKENS && s.tokens / windowTokens < 0.01) {
      small.push(s);
    } else {
      kept.push(s);
    }
  }
  if (small.length > 0) {
    let sum: number = 0;
    for (const s of small) {
      sum += s.tokens;
    }
    kept.push({ key: 'othersSmall', label: '其余 ' + small.length + ' 段', tokens: sum });
  }
  return kept;
}

// ── 校准系数（方案 §3.2；红线④⑤的代码面）──
// k = 真实输入 ÷ 发送时估算；pendingEstimate ≤ 0 / 真值 ≤ 0 / NaN / Infinity 回 1.0（纯估
// 算态），成品钳制 [0.2, 5]（异常锚点不得进显示链——超界即「锚点本身可疑」，
// 回 1 比带毒校准安全）
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
