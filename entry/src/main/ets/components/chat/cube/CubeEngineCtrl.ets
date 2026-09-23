// Cube 实验引擎控制件（2026-09-18 自 ChatSendCtrl 域级最小拆分——该件剔头 1202 行贴 1200
// 硬线，照 ChatToolRoundCtrl〔2026-09-08〕与 ChatContextUsageCalc〔2026-09-17〕先例：方法体
// 逐字搬迁，唯一改写 = 宿主内部状态直引收敛为 CubeEngineHost 接口方法，宿主经接口回接）。
//
// 域定义 = 双引擎分流（偏好页「流式引擎（试验）」开关 AppPreferences.isCubeEngineEnabled 分
// 两态）+ 三频道打字机动效态（CubeStreamFlushers 快照 / 揭示指针 / 流末收口）+ 开关门控。
// 分流落点两处：createStream = 传输+解析（★ 阶段 3 落点，空壳期两分支同走宿主原生协议流工厂
// ——阶段 3 动工时实验分支换 Cube streamPost 双条件收口传输 + 字节级行累积解析，回调出口不
// 变，桥接收口在阶段 4 补齐）；feed = 节流/动效（阶段 2 已接：实验态走 cube/ 三频道打字机——
// displaySync 30fps 逐字 + 首块独立通道 + 揭示指针语义；原生走宿主 ChatAppendThrottle 分档
// 节流不变）。实验态快照由宿主 dispatchSend 轮首经 rebuild 锁定（开关现读一次，轮内行为不随
// 开关中途切换；工具轮每轮重建——宿主 rebuildCubeFlushers 委托本件同法）。
//
// ★ 本文件禁 import ChatSendCtrl（防循环依赖）——宿主内部状态全部经 CubeEngineHost 薄直通
// 访问；实现位集中在 ChatSendCtrl「工具轮域宿主接口实现位」节之后，全部薄直通、语义零变化。
//
// 断言面：本件专钉在 assert-chat-runtime 93 组补充段（2026-09-18 自检轮补五枚——rebuild 守卫与
// 指针同轮清零 / feed 双支 / settle 收口次序 / 禁回引宿主负向 / 拆分禁止回流负向；该件此前零专钉）；
// CubeStreamFlushers 三频道硬约束与 assert-ctx-usage 121 组造流咽喉点次序另在两件。两处锚随形
// 改写见 2026-09-18 变更记录对应节（七百三十四笔与其自检轮）。
import { UIContext } from '@kit.ArkUI';
import { AiConnection, ChatStream } from '../../../common/providers/AiTypes';
import { isCubeEngineEnabled } from '../../../common/AppPreferences';
import { ChatDataSource } from '../ChatDataSource';
import { ChatMessage } from '../ChatMessageCompose';
import { CubeStreamFlushers } from './CubeStreamFlushers';

// 宿主接口：本域引用的宿主内部状态收敛于此（ChatSendCtrl implements，实现位集中一节——全部
// 薄直通，语义零变化）。get* 前缀名与宿主私有成员同名冲突规避，照 ChatToolRoundHost 先例；
// 其中 getLiveAssistantId / getLiveThinkingId / getAssistantFull / getThinkingFull /
// dataSource / maybeFollow 六件与 ChatToolRoundHost 同名同实现——两接口共用宿主同一批委托，
// 不新增第二套
export interface CubeEngineHost {
  uiContext(): UIContext | null;                 // this.refs.cubeUiContext()
  dataSource(): ChatDataSource;                  // this.refs.dataSource
  maybeFollow(): void;                           // this.refs.follow.maybeFollow()
  // 流式累积态（揭示回调按**当下值**取频道 id 与权威全量串——emit 在累积之后）
  getLiveAssistantId(): string;
  getLiveThinkingId(): string;
  getAssistantFull(): string;
  getThinkingFull(): string;
  // 宿主既有方法放宽可见性，签名不变（原生协议流工厂——三协议工厂分发，回调统一回宿主出口）
  createNativeStream(conn: AiConnection): ChatStream;
  enqueueThrottle(frameId: string, delta: string): void;  // 薄包装 this.throttle().enqueue
}

export class CubeEngineCtrl {
  private host: CubeEngineHost;
  // 三频道编排（非空 = 本轮实验态——宿主 dispatchSend 快照锁定〔开关现读一次，轮内行为不随
  // 开关中途切换〕；null = 原生态或 UIContext 不可达的防御退化，走原生 ChatAppendThrottle）
  private flushers: CubeStreamFlushers | null = null;
  // 打字机揭示指针：正文/思考各自已揭示字符数（msg.text = full.substring(0, revealed)——
  // 揭示节奏落后于网络累积节奏即打字机效果；原生路径不维护〔全量覆盖语义〕）
  private assistantRevealed: number = 0;
  private thinkingRevealed: number = 0;

  constructor(host: CubeEngineHost) {
    this.host = host;
  }

  // 三频道构造唯一落点（宿主 dispatchSend 轮首 + 工具轮每轮两处共用收敛为单一入口）：实验态
  // 且 UIContext 可达才建——null = 原生路径零变化。reveal 回调闭包持 this 延迟取 live 频道
  // id（emit 永不跨轮——settle/reset 同步收口在先）
  rebuild(): void {
    const uiCtx: UIContext | null = this.host.uiContext();
    if (uiCtx === null || !isCubeEngineEnabled()) {
      this.flushers = null;
    } else {
      this.flushers = new CubeStreamFlushers(uiCtx,
        (chunk: string): void => this.revealChunk(this.host.getLiveAssistantId(), chunk),
        (chunk: string): void => this.revealChunk(this.host.getLiveThinkingId(), chunk));
    }
    // 揭示指针清零（与快照同轮——上一轮残留揭示位不得带进新轮）
    this.assistantRevealed = 0;
    this.thinkingRevealed = 0;
  }

  // 分流点·传输+解析（阶段 3 落点）：空壳期两分支同走原生协议流工厂——阶段 3 动工时实验
  // 分支换 Cube streamPost 双条件收口传输 + 字节级行累积解析（回调出口不变）
  createStream(conn: AiConnection): ChatStream {
    if (isCubeEngineEnabled()) {
      return this.host.createNativeStream(conn);
    }
    return this.host.createNativeStream(conn);
  }

  // 分流点·节流/动效（阶段 2 已接）：实验态（flushers 非空）走三频道打字机——frameId 判
  // 频道（liveAssistantId = 正文，其余 = 思考）；原生走宿主 ChatAppendThrottle 分档节流
  feed(frameId: string, delta: string): void {
    const cube: CubeStreamFlushers | null = this.flushers;
    if (cube !== null) {
      if (frameId === this.host.getLiveAssistantId()) {
        cube.feedContent(delta);
      } else {
        cube.feedReasoning(delta);
      }
      return;
    }
    this.host.enqueueThrottle(frameId, delta);
  }

  // 打字机揭示（frame 回调内——TypewriterFlusher 五条硬约束之 5：只做 substring + 赋值）：
  // revealed 指针推进 + msg.text = full 截取到揭示位（揭示式覆盖——与原生 flushFrame 的
  // 全量覆盖并存，互不干扰：原生路径不经此方法）
  private revealChunk(frameId: string, chunk: string): void {
    if (frameId === '') {
      return; // 防御：思考块尚未懒创建的竞态空档（enqueue 在创建后才调，理论不可达）
    }
    if (frameId === this.host.getLiveAssistantId()) {
      this.assistantRevealed += chunk.length;
      const msg: ChatMessage | null = this.host.dataSource().findMessage(frameId);
      if (msg !== null) {
        msg.text = this.host.getAssistantFull().substring(0, this.assistantRevealed);
      }
    } else {
      this.thinkingRevealed += chunk.length;
      const msg: ChatMessage | null = this.host.dataSource().findMessage(frameId);
      if (msg !== null) {
        msg.text = this.host.getThinkingFull().substring(0, this.thinkingRevealed);
      }
    }
    this.host.maybeFollow();
  }

  // 实验态流末打字机收口（硬约束 3/4：同步吐完再释放；吐完后 revealed = full，msg.text
  // 已是全量——后续既有全量覆盖与落库零改动衔接）
  settle(flush: boolean): void {
    if (this.flushers === null) {
      return;
    }
    if (flush) {
      this.flushers.finish();
      this.assistantRevealed = this.host.getAssistantFull().length;
      this.thinkingRevealed = this.host.getThinkingFull().length;
    } else {
      this.flushers.reset(); // 销毁/静默路径：不吐剩余（页面将亡，DB 权威在 assistantFull）
    }
    this.flushers = null;
  }
}
