// 轮级用量与诊断标记域（2026-09-23 首字耗时笔自 ChatSendCtrl.ets 域级最小拆分迁出——
// 技术债务清单登记在案候选缝兑现：ChatSendCtrl 剔头 1198 行贴 1200 硬线，本次功能增量
// （首字耗时）正落在这条累积链上，按宪法「越线须先拆域」把边界最清晰的一条缝整体外迁
// 〔成员与读写法自 ChatSendCtrl 逐字搬迁、语义零变化，照 ChatKeyRoundCtrl〔2026-09-20〕
// 与 ChatToolRoundCtrl〔2026-09-08〕两先例〕）。
// 域定义一句话：一轮（= 一次用户发送及其全部流——含工具轮 N 流与 Key 失败切换）的用量与
// 诊断标记累积器，三处消费全经本件：轮首清零 → 每条流收尾累积 → 收尾快照。
// ★ 三条合并口径**刻意不同，勿「统一」**（各有其据，逐条见下）：
//   · 用量四值（prompt/completion/cached/durationMs）跨流**求和**——工具轮 N 流与失败切换的
//     成功流同为真实消耗，一次用户发送 = 一行账本（决明口径②，2026-09-06）。流内多帧合并
//     （take-max）已在流层 ChatStreamBase 完成，本件只做跨流求和；error/停止轮残留值由下次
//     轮首清零兜底（finishStream done-only 闸天然不落库）；
//   · 截断标记**末流胜出**（直接赋值而非 `||=`）——工具轮多流时以最终呈现给用户的那条流
//     为准（2026-09-23 输出上限治理笔 2；照 ctxCalc.recordAnchor 同款判据）；
//   · 首字耗时**首个非 0 胜出**——「用户等多久看到第一个字」那一刻早在首条产出正文/思考的
//     流上定格，后续流更小的值不得回改（2026-09-23 首字耗时笔；时点量不是量累加，与上一条
//     的末流胜出刻意相反）。
// ★ 首字耗时与请求日志的「首字节」是两个指标（体感口径 vs 诊断口径；后者随日志开关、本条
// 不随任何开关），字段级口径见 ChatStreamBase.firstTokenMs 与 AiTypes.AiStreamHandlers 第四参。
import { AiUsageDelta } from '../../common/providers/SseParser';

// 轮级快照（收尾消费面两处：宿主 finishStream 的挂载与落库、takeVariantPayloadFor 的版本
// 载荷）。前五值字段名与 ChatRetryCtrl.VariantUsageSnapshot 同名同义——★ 但版本载荷处**必须
// 逐字段显式列举**，禁整对象直传：ArkTS 是 TypeScript 严格子集，**禁结构类型**
//（arkts-no-structural-typing）——本快照比 VariantUsageSnapshot 多一个 truncated，整对象直传
// 不是「多余字段自动忽略」而是**编译不过**（2026-09-23 首字耗时笔首跑构建实锤，坑78）；
// 同理反向少一个字段也编译不过（同笔 applyFinalVariant 载荷漏补 firstTokenMs 即栽在这条）。
// 多一值少一值都在调用点的字面量里显式决定，别指望语言替我们忽略
export interface RoundUsageValues {
  prompt: number;
  completion: number;
  durationMs: number;
  cached: number;
  firstTokenMs: number;
  truncated: boolean;
}

export class ChatUsageRoundCtrl {
  private promptTokens: number = 0;
  private completionTokens: number = 0;
  private durationMs: number = 0;
  private cachedTokens: number = 0;
  private firstTokenMs: number = 0;
  private truncated: boolean = false;

  // 轮首清零（宿主 dispatchSend 与 launchRetryRound 两处调——轮首唯一清零点；工具轮间不清，
  // 见域头注释的跨流求和口径）
  reset(): void {
    this.promptTokens = 0;
    this.completionTokens = 0;
    this.durationMs = 0;
    this.cachedTokens = 0;
    this.firstTokenMs = 0;
    this.truncated = false;
  }

  // 单流收尾累积（宿主 onStreamDone 委托；四参 = onDone 透出值）。失败流无 onDone 天然不计；
  // usage null（流无 usage 帧）只累时长与首字、不累 token——首字与 usage 无关（无用量协议的
  // 服务商照样有首个字），故首字打戳**不经** usage 判据
  accumulateStream(usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
    firstTokenMs: number): void {
    this.durationMs += durationMs;
    this.truncated = truncated;
    if (firstTokenMs > 0 && this.firstTokenMs === 0) {
      this.firstTokenMs = firstTokenMs;
    }
    if (usage !== null) {
      this.promptTokens += usage.promptTokens;
      this.completionTokens += usage.completionTokens;
      this.cachedTokens += usage.cachedTokens ?? 0;
    }
  }

  // 收尾快照（宿主 finishStream 挂载/落库与 takeVariantPayloadFor 版本载荷两处调）——**局部
  // 快照防连发错位**：finalizeMessage 异步完成后才落账本，彼时用户可能已开新一轮发送（累积器
  // 被清零重计），故消费侧必须先取快照再异步
  values(): RoundUsageValues {
    return {
      prompt: this.promptTokens,
      completion: this.completionTokens,
      durationMs: this.durationMs,
      cached: this.cachedTokens,
      firstTokenMs: this.firstTokenMs,
      truncated: this.truncated
    };
  }
}
