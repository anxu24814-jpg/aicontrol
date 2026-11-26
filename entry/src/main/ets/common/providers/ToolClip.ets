// 工具结果截断纯域（2026-10-06 拆分笔自立：自 common/providers/ToolTypes.ets 尾部整域外迁——
// 该件越 1200 硬线，按宪法「越线件实质改动前先拆本次改动所属功能域」先拆截断域再动；建档与
// 偿还落账 = docs/变更记录.md 本笔条目）。
// 域职责一句话：工具结果文本的定长截断——搜索类载荷结构化截断（先裁 summary 保 results
// 整串，装不下再逐条裁 snippet 的两级保底，引文卡数据源恒在场）与纯文本硬截兜底两态。
// · 为何单开新件（反碎片下限②申报）：本域零依赖（纯 JSON 字符串处理），并入任何既有件都只是
//   换一个越线或错域的落点；消费者跨层（编排层两件直调，其余工具域只按 8192 线做预算计算、
//   import 面最小化），独立成件后 import 面=零。★ 2026-09-26 笔1 S3a 拆分时原判「clipToolResult
//   不随迁（消费方 15 件中 7 件在工具域外，迁出会强制白名单外文件改 import）」——本笔推翻该
//   结论：白名单外消费方实际只两件（ChatToolRoundCtrl / ChatToolResendCtrl）随拆改接线，其余
//   件并不 import 本函数；越线条款下整域迁出本件。
// · 依赖纪律：零 import（纯 JSON 字符串处理）——断言复制直跑即自足。
// · 沿革：本件内容 = 2026-09-02 工具调用底层笔在 ToolTypes 落码 + 2026-09-03 自检 P1-3 修复
//   （结构化截断）的截断块（B14）整域搬迁，方法体逐字、零语义变化；原段前「工具执行域已外迁
//   ToolRuntime」的迁移记事随域归位（ToolRuntime 侧头注释自持，2026-10-06 已随形）。
// 工具结果文本截断（数据有界红线——超长结果只留头部；RikkaHub 32K 同思路，aicontrol 取 8K
// 手机端保守值）。截断尾标提示模型结果被裁。
// ★ 2026-09-03 自检 P1-3 修复：搜索类结果 JSON（scrape_web summary 复述全文，转义后常超
// 8192）超限时不再硬截 JSON 中间——先结构化只裁 summary 键再序列化（results 保整 =
// 引文卡回放数据源不丢），模型恒收合法 JSON；非搜索载荷形态仍走旧硬截兜底
export function clipToolResult(result: string, maxChars: number = 8192): string {
  if (result.length <= maxChars) {
    return result;
  }
  const structured: string = clipSearchPayload(result, maxChars);
  if (structured !== '') {
    return structured;
  }
  return result.substring(0, maxChars) + '…[结果过长已截断]';
}

// 工具回执截断分流（2026-10-19 P6 自检修复——MCP 32K/4K 契约被全局 8K 二次覆盖）：
// MCP 成功回执已由 McpTools executor 调 McpText.truncateToolResult 按 32K/4K 契约自截，
// 错误回执按「错误文案原样透传」拍板不截——本件 8K 全局线只服务非 MCP 工具。带工具名的
// 单点分流口，两个消费方（ChatToolRoundCtrl 串行/并行两路 + ChatToolResendCtrl 重发路）
// 统一经此调用，防二次缩水把 8K~32K 结果截短、把超长错误文本截成非原文。
// 前缀字面量与 McpText.MCP_TOOL_NAME_PREFIX 同值（本件「零 import、断言整件复制直跑」纪律
// 不允许反向引 McpText；前缀判据单源仍在彼件，396 组断言钉住拼装形态，改前缀时两处同改）。
export function clipToolResultForTool(toolName: string, result: string): string {
  if (shouldBypassToolClip(toolName)) {
    return result;
  }
  return clipToolResult(result);
}

// 搜索类载荷结构化截断（P1-3）：只裁 summary（模型阅读面）保 results 整串——引文卡唯一
// 数据源（ChatMessageItem.toolSearchRefs 解析 results 数组，坏 JSON 回空 = 引文卡静默消失）。
// 非搜索形态（无 summary/results 键）或 results 单串即超限 → '' 由调用方走旧硬截兜底。
// 预算算法：summary 按溢出量递减裁剪 + 尾标重试序列化（JSON 转义膨胀——\n→\\n 等使预算
// 失真，每轮按 5% 回退收敛；至多十余轮 stringify，单次执行路径开销可忽略）
// ★ 2026-10-26 P6 自检修复（1）：导出供溢出落盘分流口在落盘判据**之前**先试结构化截断——
// 搜索载荷（scrape_web 整页正文转义后常超 8K）能装进阈值就回合法 JSON、不落盘，引文卡
// 数据源不丢（落盘信封是纯文本，parseSearchRefs 必败 = 引文卡静默消失）；返回 '' = 非搜索
// 形态或两级裁剪都装不下，由调用方继续走落盘/硬截。
// ★ 2026-11-01 分页续读笔：第二级保底（clipResultSnippets）——summary 裁到近空仍超限 =
// results 整串超限（条数调大或引擎摘要偏长时高发，真机「搜索卡存文件」即此），summary 与
// 全部 snippet 联合按比例裁剪保载荷恒在场（rik search_web 白名单豁免同思路：引文卡与模型
// 阅读都依赖完整 results，而读回工具 exec_output_read 默认关，落盘对搜索场景等于死路）。
const CLIP_TAIL: string = '…[内容过长已截断]';

// 裁剪切点代理对防护（★ 2026-11-01 自检修复笔：两级裁剪切点原按码元 substring，落在
// emoji 等代理对中间时产出孤立码元——隔离扫描 45 组超限载荷 3 组命中（emoji 密集 summary
// 实测）。同构本件 spillCutIndex 先例：切点前一码元是高位且切点处是低位 = 劈对，退一位
// 整对保留在串外；cut = 0 或串尾时无切点原样返回）
function clipSafeCut(text: string, cut: number): number {
  if (cut > 0 && cut < text.length) {
    const prev: number = text.charCodeAt(cut - 1);
    const at: number = text.charCodeAt(cut);
    if (prev >= 0xD800 && prev <= 0xDBFF && at >= 0xDC00 && at <= 0xDFFF) {
      return cut - 1;
    }
  }
  return cut;
}

export function clipSearchPayload(result: string, maxChars: number): string {
  try {
    const rec = JSON.parse(result) as Record<string, Object>;
    const summaryRaw: Object = rec['summary'];
    const resultsRaw: Object = rec['results'];
    if (typeof summaryRaw !== 'string' || !Array.isArray(resultsRaw)) {
      return '';
    }
    const summary: string = summaryRaw as string;
    let json: string = JSON.stringify(rec);
    if (json.length <= maxChars) {
      return json;
    }
    const overflow: number = json.length - maxChars;
    let cut: number = summary.length - overflow - CLIP_TAIL.length;
    while (cut > 0) {
      rec['summary'] = summary.substring(0, clipSafeCut(summary, cut)) + CLIP_TAIL;
      json = JSON.stringify(rec);
      if (json.length <= maxChars) {
        return json;
      }
      cut = Math.floor(cut * 0.95);
    }
    return clipResultSnippets(rec, maxChars);
  } catch (e) {
    return '';
  }
}

// 第二级保底：summary 与各条 snippet **联合**按比例裁剪（★ 2026-11-01 交付后自检补——初版
// 只裁 snippet，而第一级 cut ≤ 0 时 summary 原样在场未裁：条数大场景 summary（contentForAI）
// 与 results 信息同源重叠、常双双超限，snippet 面收不回全部溢出 → pct 起步为负 → 恒 ''
// 落盘（25 条实测 16775 → 空串）。联合面 = summary + 全部 snippet 同一百分比按各自长度
// 分配削减、95% 收敛、下限 0 = 全裁光；被裁文本尾加 '…' 如实标记；条数不减、键不删、
// title/url 不裁（引文卡可点性优先），非串 snippet 原样不动。全裁光仍超限（title/url 本身
// 超限，理论不可达）→ '' 走调用方兜底。
const CLIP_SNIPPET_ELLIPSIS: string = '…';

// 可裁面单元（ArkTS 字面量须显式类型——apply 写回闭包，箭头属性接口为既有认可形制）
interface ClipCutPart {
  original: string;
  apply: (v: string) => void;
}

function clipResultSnippets(rec: Record<string, Object>, maxChars: number): string {
  const resultsRaw: Object = rec['results'];
  if (!Array.isArray(resultsRaw)) {
    return '';
  }
  const parts: ClipCutPart[] = [];
  const summaryRaw: Object = rec['summary'];
  if (typeof summaryRaw === 'string') {
    const original: string = summaryRaw as string;
    const part: ClipCutPart = { original: original,
      apply: (v: string) => { rec['summary'] = v; } };
    parts.push(part);
  }
  const items: Object[] = resultsRaw as Object[];
  for (const item of items) {
    const it = item as Record<string, Object>;
    const raw: Object = it['snippet'];
    if (typeof raw === 'string') {
      const original: string = raw as string;
      const part: ClipCutPart = { original: original,
        apply: (v: string) => { it['snippet'] = v; } };
      parts.push(part);
    }
  }
  let total: number = 0;
  for (const p of parts) {
    total += p.original.length;
  }
  if (total === 0) {
    return '';
  }
  const overflow: number = JSON.stringify(rec).length - maxChars;
  if (overflow <= 0) {
    return JSON.stringify(rec);
  }
  let pct: number = Math.floor((total - overflow) * 100 / total);
  if (pct > 100) {
    pct = 100;
  }
  while (pct >= 0) {
    for (const p of parts) {
      const target: number = Math.floor(p.original.length * pct / 100);
      if (target >= p.original.length) {
        continue;
      }
      p.apply(target > 0 ?
        p.original.substring(0, clipSafeCut(p.original, target)) + CLIP_SNIPPET_ELLIPSIS : '');
    }
    const json: string = JSON.stringify(rec);
    if (json.length <= maxChars) {
      return json;
    }
    if (pct === 0) {
      break;
    }
    pct = Math.floor(pct * 95 / 100);
  }
  return '';
}

// ═══ 工具结果溢出落盘纯函数族（2026-10-26 注入链治理 P0-c，方案-注入链治理施工总案
//     -20261025 §三 P0-c + 20261026 核查修订定案）═══
// 设计：超 8K 的非 MCP 工具结果不再「substring + 尾标」永弃，改「落临时区 + 信封回执
//（头尾预览 + exec_output_read 读回指引）」——「超限即丢且不给回头路」止血。落盘 IO 不进
// 本件（破零 import 直跑纪律）——IO 编排在 common/providers/ToolResultSpill.ets（三消费方
// 共用），本件只持分流判据与信封组装**纯函数**（assert-ui-shape 直跑面随之可钉信封形态）。

// MCP 分流判据（导出：IO 小件复用，前缀字面量单源仍在本件一处——与 McpText.
// MCP_TOOL_NAME_PREFIX 同值双写的既有形态不变，396 组钉拼装形态）
export function shouldBypassToolClip(toolName: string): boolean {
  return toolName.startsWith('mcp__');
}

// 溢出落盘 kill-switch（总案拍板默认开；关 = 三消费点逐字节回现有截断形态）
export const TOOL_RESULT_SPILL_ENABLED: boolean = true;
// 溢出阈值（与 clipToolResult 形参默认线 8192 同值——字面量双写，MCP 前缀同款先例，
// 改线两处同改；sse-assert 既有关系钉读形参默认值，不改形参形态）
export const TOOL_RESULT_SPILL_THRESHOLD: number = 8192;
// 头尾预览长度（照 ScriptReceipt.SCRIPT_PREVIEW_CLIP 同档 ~1KB；信封自预算 = 预览两段
// 2048 + 文案约 150 < 8192，保证通用截断器不二次截断信封）
const SPILL_PREVIEW_CHARS: number = 1024;

// 溢出分流判据（开关开 + 超阈值；MCP 判据在上层先行——见 IO 小件）
export function shouldSpillToolResult(result: string): boolean {
  return TOOL_RESULT_SPILL_ENABLED && result.length > TOOL_RESULT_SPILL_THRESHOLD;
}

// 预览切点（代理对防护——SkillText.safeCutIndex 同构，本件零 import 自持一份）
function spillCutIndex(text: string, max: number): number {
  if (text.length <= max) {
    return text.length;
  }
  const last: number = text.charCodeAt(max - 1);
  return (last >= 0xD800 && last <= 0xDBFF) ? max - 1 : max;
}

export function spillHeadPreview(result: string): string {
  return result.substring(0, spillCutIndex(result, SPILL_PREVIEW_CHARS));
}

export function spillTailPreview(result: string): string {
  const from: number = Math.max(result.length - SPILL_PREVIEW_CHARS, 0);
  let tail: string = result.substring(from);
  if (tail.length === SPILL_PREVIEW_CHARS) {
    // 首码元落在代理对低位 = 劈对，退一位保完整字符
    const headCode: number = tail.charCodeAt(0);
    if (headCode >= 0xDC00 && headCode <= 0xDFFF) {
      tail = tail.substring(1);
    }
  }
  return tail;
}

// 溢出信封组装（入参 = 文件名 / 原字符数 / 头尾预览，零 IO；文案同构 ScriptReceipt.
// composeEnvelope 私有件不可直引〔入参绑 ScriptRunResult〕——同构新写，指引同指
// exec_output_read）。★ R1 如实声明：临时文件用户可手动清理（无启动清扫），清理后不可
// 恢复——不承诺持久；★ 只指路不点名检索工具之外的能力（与 exec_code 信封同一话术）；
// ★ 2026-10-26 P6 自检修复（6）：exec_output_read 默认不声明（defaultEnabled false，
// 仅开启「脚本工作台」卡的助手可用）——信封补一句启用路径，避免把多数助手指向未声明
// 工具而空转一轮
export function composeToolSpillEnvelope(fileName: string, totalChars: number,
  headPreview: string, tailPreview: string): string {
  return '结果超过 ' + TOOL_RESULT_SPILL_THRESHOLD + ' 字符上限，已保存为临时文件 ' +
    fileName + '，共 ' + totalChars + ' 字符。临时文件可能被清理，清理后不可恢复，需要时' +
    '重跑工具。开头：\n' + headPreview + '\n结尾：\n' + tailPreview +
    '\n继续查看用 exec_output_read，name 传文件名，offset 从 1 起分段读。' +
    '该工具需先在助手工具页的脚本工作台卡开启，未开启时无法读回。';
}

// 落盘失败降级句（拼接在现有截断结果之后——R2 失败不阻断，且如实告知「未能保存全文」
// 而非静默截断；ScriptReceipt.SCRIPT_SPILL_FAILED_TEXT 同族）
export function withSpillFailedNote(clipped: string): string {
  return clipped + '\n[超长结果未能保存全文，仅保留截断内容]';
}