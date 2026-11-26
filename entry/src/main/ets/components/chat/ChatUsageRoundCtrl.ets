// 轮级用量与诊断标记域（自 ChatSendCtrl 域级拆出，成员与读写法逐字搬迁）：一轮（= 一次
// 用户发送及其全部流——含工具轮 N 流与 Key 失败切换）的用量与诊断标记累积器，三处消费全
// 经本件：轮首清零 → 每条流收尾累积 → 收尾快照。
// ★ 三条合并口径**刻意不同，勿「统一」**（各有其据，逐条见下）：
//   · 用量四值（prompt/completion/cached/durationMs）跨流**求和**——工具轮 N 流与失败切换的
//     成功流同为真实消耗，一次用户发送 = 一行账本（决明口径②）。流内多帧合并（take-max）
//     已在流层 ChatStreamBase 完成，本件只做跨流求和；error/停止轮残留值由下次轮首清零兜底
//    （finishStream done-only 闸天然不落库）；
//   · 截断标记**末流胜出**（直接赋值而非 `||=`）——工具轮多流时以最终呈现给用户的那条流
//     为准（照 ctxCalc.recordAnchor 同款判据）；
//   · 首字耗时**首个非 0 胜出**——「用户等多久看到第一个字」那一刻早在首条产出正文/思考的
//     流上定格，后续流更小的值不得回改（时点量不是量累加，与上一条的末流胜出刻意相反）。
// ★ 首字耗时与请求日志的「首字节」是两个指标（体感口径 vs 诊断口径；后者随日志开关、本条
// 不随任何开关），字段级口径见 ChatStreamBase.firstTokenMs 与 AiTypes.AiStreamHandlers 第四参。
import { AiServerToolUse, AiUsageDelta } from '../../common/providers/SseParser';

// 轮级快照（收尾消费面两处：宿主 finishStream 的挂载与落库、takeVariantPayloadFor 的版本
// 载荷）。前五值字段名与 ChatRetryCtrl.VariantUsageSnapshot 同名同义——★ 但版本载荷处**必须
// 逐字段显式列举**，禁整对象直传：ArkTS 是 TypeScript 严格子集，**禁结构类型**
//（arkts-no-structural-typing）——本快照比 VariantUsageSnapshot 多一个 truncated，整对象直传
// 不是「多余字段自动忽略」而是**编译不过**（坑78，构建实锤）；同理反向少一个字段也编译不过
//（applyFinalVariant 载荷漏补 firstTokenMs 即栽过这条）。多一值少一值都在调用点的字面量里
// 显式决定，别指望语言替我们忽略
export interface RoundUsageValues {
  prompt: number;
  completion: number;
  durationMs: number;
  cached: number;
  firstTokenMs: number;
  truncated: boolean;
  // 二期 #7：官方服务端工具计次（undefined = 本轮无计次）。跨流**求和**（同 token 口径——
  // 工具轮 N 流各是一次真实请求，计次相加才是这一轮的真实调用次数）；审核 token 只采集
  // 不单列（随账本留存，展示面不出现），故不入本快照
  serverToolUse: AiServerToolUse | undefined;
}

export class ChatUsageRoundCtrl {
  private promptTokens: number = 0;
  private completionTokens: number = 0;
  private durationMs: number = 0;
  private cachedTokens: number = 0;
  private firstTokenMs: number = 0;
  private truncated: boolean = false;
  private serverToolUse: AiServerToolUse | undefined = undefined;

  // 轮首清零（宿主 dispatchSend 与 launchRetryRound 两处调——轮首唯一清零点；工具轮间不清，
  // 见域头注释的跨流求和口径）
  reset(): void {
    this.promptTokens = 0;
    this.completionTokens = 0;
    this.durationMs = 0;
    this.cachedTokens = 0;
    this.firstTokenMs = 0;
    this.truncated = false;
    this.serverToolUse = undefined;
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
      if (usage.serverToolUse !== undefined) {
        const prev: AiServerToolUse = this.serverToolUse ?? { search: 0, fetch: 0, image: 0 };
        this.serverToolUse = {
          search: prev.search + usage.serverToolUse.search,
          fetch: prev.fetch + usage.serverToolUse.fetch,
          image: prev.image + usage.serverToolUse.image
        };
      }
    }
  }

  // 收尾快照（宿主 finishStream 挂载/落库消费）——**局部
  // 快照防连发错位**：finalizeMessage 异步完成后才落账本，彼时用户可能已开新一轮发送（累积器
  // 被清零重计），故消费侧必须先取快照再异步
  values(): RoundUsageValues {
    return {
      prompt: this.promptTokens,
      completion: this.completionTokens,
      durationMs: this.durationMs,
      cached: this.cachedTokens,
      firstTokenMs: this.firstTokenMs,
      truncated: this.truncated,
      serverToolUse: this.serverToolUse === undefined ? undefined : {
        search: this.serverToolUse.search,
        fetch: this.serverToolUse.fetch,
        image: this.serverToolUse.image
      }
    };
  }
}
