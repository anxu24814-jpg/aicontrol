// 工具结果附件的协议×模型能力判据叶子（★ 2026-10-06 代码工作台笔D 段一/段二新建）。
// 域定义一句话：回答「这份连接的协议与模型能不能在工具结果位收图片 / 收 PDF 原件」，
// 外加 PDF 直传的尺寸窗常量与已知坑洞黑名单表。零 import、零 IO、纯函数——断言脚本按
// 既有副本机制复制直跑同源（照 EndpointPolicy / ModelRegistry 的「复制直跑」先例）。
// · 为何不能并入既有件（反碎片下限②申报）：AiTypes.ets 是协议常量与能力表的聚合（含
//   import），本件要能被断言脚本复制直跑（零 import 硬约束）；EndpointPolicy.ets 职责 =
//   端点加密分级（不同域）；AttachmentUtil.ets（>800 行、含 kit import）不宜再挂协议判据。
// · 协议形状依据（三方官方文档，2026-10-06 开工复核）：anthropic tool_result.content 块
//   数组支持 image / document 块；OpenAI Responses function_call_output.output 支持内容项
//   数组（input_image / input_file）；Gemini functionResponse 的 parts 兄弟键仅 Gemini 3.x
//   支持（2.x 传之被拒）；OpenAI Chat Completions 官方无工具结果媒体通道（恒 false）。
//
// ── 已知坑洞黑名单登记法（写进本表前必读）──
// · 登记触发 = 真机/报障实锤「该 host 或该模型前缀在工具结果位收不住附件」——两类形态：
//   ①拒收（服务端 400）；②收下但模型读不出（首例 = 2026-10-08 DeepSeek 读挂载 PDF：
//   协议形状兼容 ≠ 模型能消费 PDF 原件，回执承诺「原件已随请求发送」与实收不符）。
// · 形态：host 行填域名（如 example.com，子串匹配）；模型前缀行填 id 前缀（如
//   gemini-3-vision-x）。
// · 登记 → 变更记录一句（现象 + 日期）+ 真机复验一条（回落路可达）；**禁凭猜登记**。
// · 表注：2026-10-06 笔D 定稿为空表；2026-10-08 首次登记（DeepSeek 前缀行，见下方表注）。

// 与 AiTypes.ENDPOINT_RESPONSES 同值（'responses'——零 import 纪律下本地承载，改动须两侧
// grep 同步；同值由 assert-tool-domain 判据组钉守）。TMS_ 前缀防混（照 ModelRegistry 的
// MR_ 先例）
export const TMS_ENDPOINT_RESPONSES: string = 'responses';
// 与 AiTypes.PROTOCOL_ANTHROPIC / PROTOCOL_GEMINI 同值（零 import 本地承载；判据内与
// 调用方传参两侧 grep 同步）
const TMS_PROTOCOL_ANTHROPIC: string = 'anthropic';
const TMS_PROTOCOL_GEMINI: string = 'gemini';

// PDF 原件直传尺寸窗（源文件字节；段二）：> 上限 = 回落解析文本；< 下限 = 原件无收益
//（解析文本更省 token），同样回落。上限取向 = 源件 base64 膨胀（约 ×4/3）后仍离服务端
// 请求体上限有余量（Anthropic 请求体上限约 32MB / Gemini 整请求上限与单 inline_data 上限
// 约 20MB 级，2026-10-06 开工复核联网口径）；8MB 取保守量级，复核结果不改变本档取值
export const DOC_NATIVE_MAX_BYTES: number = 8 * 1024 * 1024;
export const DOC_NATIVE_MIN_BYTES: number = 4 * 1024;

// 已知坑洞黑名单（登记法见文件头「黑名单登记法」节；禁提前收录未复现条目）：
// host 行 = baseUrl 子串匹配；模型前缀行 = model id 前缀匹配。黑名单优先于真值表（命中即双 false）
// ★ 2026-10-08 报障登记（变更记录一千五百一十八节）：模型前缀行 deepseek——读挂载 / 工作区 PDF
// 走原件直传窗后模型读不出（协议形状兼容〔anthropic 块数组 / responses 端点〕≠ 模型能消费
// 原件；回执「原件已随请求发送」失实）。命中后回落解析路（文本 / 页图 OCR），与「非能力
// 协议回落」同语义。只登记前缀行：实锤对象 = DeepSeek 系模型（官方域与 relay 同名转发均
// deepseek 系 id，前缀行全覆盖；host 行收敛为不登记——避免对 host 作未复现的越权断言）。
// 复验 = BLOCKED 同名节。
export const TOOL_MEDIA_BLOCK_HOSTS: string[] = [];
export const TOOL_MEDIA_BLOCK_MODEL_PREFIXES: string[] = ['deepseek'];

// 能力二元组（image = 工具结果位可收图片 image/*；pdf = 工具结果位可收 PDF 原件）
export interface ToolMediaSupport {
  image: boolean;
  pdf: boolean;
}

// 判据真值表（值与常量比较，禁裸字面量散写）：
// · anthropic → 双真（tool_result.content 块数组支持 image / document 块）；
// · gemini 且模型 id 前缀 gemini-3 → 双真（functionResponse 的 parts 兄弟键仅 Gemini 3.x，
//   2.x 传之被拒——硬编码于本判据；前缀匹配而非点号匹配，防漏判 preview 类 id）；
// · openai 族 endpoint === 'responses' → 双真（function_call_output.output 内容项数组）；
// · 其余（openai chat 及未知值）→ 双假（官方无通道——恒回落 user 消息位）；
// · 黑名单命中 → 双假（优先于上表）。
// baseUrl 只消费黑名单（indexOf 子串包含，不做前缀伪装判定的重复实现；空串不命中）；
// model 空串 = gemini 判据落 false（fail-safe）。
export function resolveToolMediaSupport(protocol: string, endpoint: string, model: string,
  baseUrl: string): ToolMediaSupport {
  const fail: ToolMediaSupport = { image: false, pdf: false };
  const host: string = baseUrl.trim().toLowerCase();
  for (const blocked of TOOL_MEDIA_BLOCK_HOSTS) {
    if (blocked !== '' && host.indexOf(blocked.trim().toLowerCase()) >= 0) {
      return fail;
    }
  }
  const modelLower: string = model.trim().toLowerCase();
  for (const prefix of TOOL_MEDIA_BLOCK_MODEL_PREFIXES) {
    if (prefix !== '' && modelLower.startsWith(prefix.trim().toLowerCase())) {
      return fail;
    }
  }
  if (protocol === TMS_PROTOCOL_ANTHROPIC) {
    return { image: true, pdf: true };
  }
  if (protocol === TMS_PROTOCOL_GEMINI) {
    return modelLower.startsWith('gemini-3') ? { image: true, pdf: true } : fail;
  }
  if (endpoint === TMS_ENDPOINT_RESPONSES) {
    return { image: true, pdf: true };
  }
  return fail;
}
