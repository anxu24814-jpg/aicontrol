// 流式 DB checkpoint 节流域（kelivo 范式 LatestWinsCheckpointWriter 的本工程形态）：流式
// 权威累积的 250ms latest-wins 落库调度——占位行落库触发、增量快照串行排水、收口交接
//（占位行节点 id 交 finishStream / settleRoundAssistant 走「更新既有占位行」收口）。
// · 与 UI 域 appendThrottle 互不合并（硬约束）：彼件是显示揭示节流（有界前缀上屏，
//   67ms~300ms 档位），本件是 DB 持久化节流（全量快照落库，250ms 固定档）——两域节奏、
//   内容、目的地皆不同，合并会让「显示滞后」与「落库滞后」互相牵制，各自独立。
// · 同步栈红线（R4-b）：onStreamDelta 同步链只置脏标 + 起定时器（markDirty 恒同步零 DB）；
//   一切 DB 写都在定时器异步回调里发起。
// · latest-wins 串行排水：任一时刻至多一笔写在途（inFlight 闸）；排队期间新快照只更新
//   「脏」标，下一定时拍现读权威串最新值（中间值不保序不重试）；写失败丢弃不毒化队列。
// · 防迟到复活守卫（域核心）：守卫谓词在命令层（updateStreamingNodeCheckpoint 的
//   status='streaming' WHERE）——收口/清扫先到后，迟到快照 affected=0 落空丢弃；本域另以
//   轮代次（epoch）挡「换轮后回写旧轮」的跨轮污染。
// · 止损位：构建期常数开关 CHAT_STREAM_DB_CHECKPOINT_ENABLED——卡顿即关不退码：关闭后
//   markDirty 短路、占位行永不落库、收口走既有插行老路（半截丢失回到「最多丢整轮」口径）、
//   启动清算对存量残留照常收口（自洽无新残留）。
// · 依赖方向（零环红线，坑50）：仅 import @kit 系统包；宿主面（CheckpointHost）由
//   ChatStreamFlowCtrl 实现（snapshot 现读权威串 / beginPlaceholder·writeCheckpoint 经
//   ChatFlowHost 薄委托到 ChatGraphWriteCtrl）——本件不 import 任何工程件。
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'ChatStreamCheckpoint';

// 止损开关（构建期常数——卡顿即改 false 重出包，不退码；关闭行为见头注释「止损位」条）
export const CHAT_STREAM_DB_CHECKPOINT_ENABLED: boolean = true;

// checkpoint 节流间隔（250ms——半截丢失上限；写放大实测后才调参）
const CHECKPOINT_INTERVAL_MS: number = 250;

// 排水快照（宿主现读权威串的最新值——latest-wins 的 latest 来源）
export interface CheckpointSnapshot {
  content: string;
  reasoning: string;
}

// 宿主面回调三口（ChatStreamFlowCtrl 构造注入——函数参数形制避开对象字面量
// arkts-no-untyped-obj-literals 限制）：snapshot 现读权威串 / beginPlaceholder 占位行
// 落库（返回节点 id，'' = 失败或无句柄，下拍重试）/ writeCheckpoint 增量单行写
//（false = 行已终态〔防迟到复活守卫拒〕，本域丢弃）
export type CheckpointSnapshotFn = () => CheckpointSnapshot;
export type CheckpointBeginFn = (content: string, reasoning: string) => Promise<string>;
export type CheckpointWriteFn = (nodeId: string, content: string,
  reasoning: string) => Promise<boolean>;

export class ChatStreamCheckpoint {
  private snapshotFn: CheckpointSnapshotFn;
  private beginFn: CheckpointBeginFn;
  private writeFn: CheckpointWriteFn;
  private placeholderNodeId: string = '';
  private timerId: number = -1;
  private dirty: boolean = false;
  private inFlight: boolean = false;
  // 轮代次（beginRound 推进）：迟到排水/回填按代次丢弃，防换轮后写旧轮
  private epoch: number = 0;

  constructor(snapshotFn: CheckpointSnapshotFn, beginFn: CheckpointBeginFn,
    writeFn: CheckpointWriteFn) {
    this.snapshotFn = snapshotFn;
    this.beginFn = beginFn;
    this.writeFn = writeFn;
  }

  // 轮复位（beginStreamRound / bindLiveAssistant 续轮 / disposeActiveStream 离页三口共用）：
  // 停定时 + 清占位行登记 + 代次推进（在途写由命令层守卫与代次双重兜底——离页/换轮后其
  // 尾部动作全部作废，不再重排）
  beginRound(): void {
    this.epoch++;
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.placeholderNodeId = '';
    this.dirty = false;
  }

  // 增量到达登记（onStreamDelta 同步栈调用——恒同步零 DB，只置脏 + 起定时；开关关闭短路）
  markDirty(): void {
    if (!CHAT_STREAM_DB_CHECKPOINT_ENABLED) {
      return;
    }
    this.dirty = true;
    if (this.timerId < 0) {
      this.timerId = setTimeout((): void => { this.drain(); }, CHECKPOINT_INTERVAL_MS);
    }
  }

  // 收口交接（finishStream 消费）：停定时并交出占位行节点 id（'' = 本轮无占位行——零增量
  // 轮或开关关闭，收口走插行老路）；交出即复位（在途写落空由守卫丢弃）
  settle(): string {
    const nodeId: string = this.placeholderNodeId;
    this.beginRound();
    return nodeId;
  }

  // 当前占位行节点 id 只读（StreamSettlement.checkpointNodeId 取值面——工具轮中间行收口用）
  currentNodeId(): string {
    return this.placeholderNodeId;
  }

  // 排水（定时器异步回调——一切 DB 写只在此发起）：latest-wins 现读快照；占位行未落则先
  // 落行（快照即首版内容），已落则单行覆写。串行：inFlight 期间本拍让位，写完成尾部按脏
  // 标重排（丢拍不丢轮——只要还有增量，下一拍必补 latest）
  private drain(): void {
    this.timerId = -1;
    if (this.inFlight || !this.dirty) {
      return;
    }
    this.dirty = false;
    this.inFlight = true;
    const myEpoch: number = this.epoch;
    const snap: CheckpointSnapshot = this.snapshotFn();
    const nodeAtDrain: string = this.placeholderNodeId;
    const write: Promise<void> = nodeAtDrain === ''
      ? this.beginFn(snap.content, snap.reasoning)
        .then((nodeId: string): void => {
          // 回填登记过代次校验：换轮/离页后落成也不认领（行已属旧轮，由收口/清扫接管）
          if (myEpoch === this.epoch && nodeId !== '') {
            this.placeholderNodeId = nodeId;
          }
        })
      : this.writeFn(nodeAtDrain, snap.content, snap.reasoning)
        .then((_ok: boolean): void => undefined); // false = 行已终态，迟到快照丢弃（守卫语义）
    write
      .catch((e: Object): void => {
        // 写失败丢弃不毒化队列（kelivo 同款）——占位行未落则下拍重试，已落则下拍覆写
        hilog.warn(DOMAIN, TAG, 'checkpoint 落库失败（丢弃本拍）：%{public}s',
          (e as Error).message);
      })
      .then((): void => {
        this.inFlight = false;
        if (myEpoch === this.epoch && this.dirty) {
          this.timerId = setTimeout((): void => { this.drain(); }, CHECKPOINT_INTERVAL_MS);
        }
      });
  }
}
