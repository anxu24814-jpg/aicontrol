// 连接能力三项测试判据叶子件（2026-09-21 服务商连接能力三项测试笔）：把三探针的原始观测量
// 归一为四态字里的「通过 / 失败」两枚，外加工具名两型聚合——文案与四态渲染在探针层与面板层
//（本件只管判据，不管展示）。
// ★ 硬约束：本文件零 import、顶层零副作用、只用 erasable TS 语法（无 enum/namespace/装饰器）
// ——scripts/assert-ui-shape.mjs 132 组把本文件复制为 .tmp/ConnectTestJudge.ts 由 node 直跑
//（断言的就是线上同一实现，禁双实现漂移），机制要求零 import（SseParser / RequestCompose /
// TokenEstimate / ModelRegistry 同为此约束的既有先例）。故入参出参一律标量——禁引 SseDelta /
// KeyDisplayRow 等外部类型；缺省量为 '' / 0（调用方按 undefined 判断后归一传入）。
// 四态（idle / running / ok / fail）是本件与面板共用的值域：判据只产 ok / fail 两枚，
// idle / running 是面板展示态（未测试 / 测试中）。

// 面板展示四态字（值域单源；判据函数只用 OK / FAIL 两枚）
export const PROBE_IDLE: string = 'idle';
export const PROBE_RUNNING: string = 'running';
export const PROBE_OK: string = 'ok';
export const PROBE_FAIL: string = 'fail';

// T1 非流式判据：HTTP 200 且响应体解出非空正文 = 通过（唯一条件；非 200 与空正文皆失败——
// 空正文说明端点通但拿不到模型回复，与「能不能聊天」的测试目的不符，不放过）
export function judgeTextProbe(httpCode: number, hasText: boolean): string {
  const passed: boolean = httpCode === 200 && hasText;
  return passed ? PROBE_OK : PROBE_FAIL;
}

// T2 流式判据：HTTP 200 且见过 ≥1 个非空正文增量且无终态错误 = 通过。
// · 只认 content（reasoningContent / 思考帧不算——思考帧能到而正文帧到不了是真实的坏形态，
//   放它过等于假绿灯）；
// · 收尾异常不放过：流中途断掉（未收终止标记）时调用方带 hasError = true，即便已收过半截
//   正文也判失败——「流没走完」本身就是问题，如实报出（错误原文经 detail 呈现）。
export function judgeStreamProbe(httpCode: number, sawContentFrame: boolean,
  hasError: boolean): string {
  const passed: boolean = httpCode === 200 && sawContentFrame && !hasError;
  return passed ? PROBE_OK : PROBE_FAIL;
}

// T3 工具调用判据（三档归一）：HTTP 非 200 = 失败；HTTP 200 起两档**同归通过**——见到工具
// 调用增量 = 调用链通，零调用 = 连通但模型没调工具。零调用档是**通过**不是红灯：本项测的是
// 「连接与协议层能不能接受 tools 字段」，模型是否真的发起调用取决于模型自身倾向，不代表连接
// 有问题（竞品 RikkaHub 同判），「没调工具」这层语义由调用方以文案传达。
// toolCallCount < 0 = 采集异常（计数不可能为负），归失败防假通过。
export function judgeToolProbe(httpCode: number, toolCallCount: number): string {
  if (httpCode !== 200 || toolCallCount < 0) {
    return PROBE_FAIL;
  }
  return PROBE_OK;
}

// 工具名两型聚合（值域与语义见 SseParser.SseToolDelta 的 name / nameFull 两字段注释；
// 口径取自既有聚合先例 ToolTypes.ToolCallAccumulator.feed 的同名分支）：
// · nameFull 非空 = 全量替换式（Responses 的 added/done 两事件各携带完整名）——直接覆盖；
// · 否则 name 为分片拼接式（OpenAI chat 事实形态，首帧片段 + 续片）——累加。
// ★ 漏判一型的后果（2026-09-06 真机实锤 bug 家族）：拼接式误当替换式 = 名字残缺；替换式误
// 当拼接式 = 拼出「search_helpsearch_help」重名——本条聚合只有这两条分支，禁再加第三义。
// 入参标量：collected = 已聚合名，name = 本片文本（无分片传 ''），nameFull = 全量文本（无传 ''）
export function mergeToolCallName(collected: string, name: string, nameFull: string): string {
  if (nameFull !== '') {
    return nameFull;
  }
  return collected + name;
}
