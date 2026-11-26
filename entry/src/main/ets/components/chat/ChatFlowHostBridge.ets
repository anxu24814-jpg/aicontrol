// 流回调域宿主面桥接件（自 ChatSendCtrl 域级拆出，方法体原样搬迁）：**ChatFlowHost 接口的
// 桥接实现**——运行隔离态四口（isDisposed / currentRunToken / currentAttemptId /
// releaseRun）经构造闭包回接宿主私有态，图写侧四口（句柄快照 / 图轮收尾 / 占位行落库 /
// 占位行增量写）直达 ChatGraphWriteCtrl。
// · 为何不并入既有件（反碎片下限三问）：无既有同域可并——ChatHostDelegates 是
//   ChatToolRoundHost 薄直通集中地（access 面无图写句柄口，扩面 = 为并入而扩接口）；
//   ChatGraphWriteCtrl 是编排体（宿主面是它的消费侧，并回即自指）；ChatStreamFlowCtrl 是
//   接口定义方（实现并回 = 接口自实现，且运行隔离态须回接宿主）；非转接壳——持跨调用图写
//   引用与宿主闭包的完整实现位（ChatSendCtrl 直传 this 的替代形态）。
// · 依赖方向（零环红线，坑50）：本件 → ChatStreamFlowCtrl（ChatFlowHost /
//   GraphFinishInput type-only）+ ChatGraphWriteCtrl 单向；ChatSendCtrl → 本件单向——运行
//   环不存在（ChatStreamFlowCtrl 对 ChatSendCtrl 仅 type-only 引用，编译期擦除）。
import { GraphRunHandle, GraphNodeRef } from '../../common/chat/ChatGraphCommandSource';
import { ChatGraphWriteCtrl, GraphFinishInput } from './ChatGraphWriteCtrl';
import { ChatFlowHost } from './ChatStreamFlowCtrl';

// 流回调域宿主面桥接实现（ChatSendCtrl 构造 flow 时以本件实例替代 this 直传——
// implements 关系自宿主迁本件，宿主类声明不再挂 ChatFlowHost）
export class ChatFlowHostBridge implements ChatFlowHost {
  private graphWrite: ChatGraphWriteCtrl;
  private disposedFn: () => boolean;
  private runTokenFn: () => string;
  private attemptIdFn: () => string;
  private releaseRunFn: () => void;

  constructor(graphWrite: ChatGraphWriteCtrl, disposedFn: () => boolean,
    runTokenFn: () => string, attemptIdFn: () => string, releaseRunFn: () => void) {
    this.graphWrite = graphWrite;
    this.disposedFn = disposedFn;
    this.runTokenFn = runTokenFn;
    this.attemptIdFn = attemptIdFn;
    this.releaseRunFn = releaseRunFn;
  }

  // 宿主销毁闸（isRoundAlive 消费——与 ChatRetryHost.isDisposed 同源同值）
  isDisposed(): boolean {
    return this.disposedFn();
  }

  // 当前 run 身份令牌（createNativeStream 发起一刻快照——V2/V3 迟到回调拦截）
  currentRunToken(): string {
    return this.runTokenFn();
  }

  // 当前 attemptId（createNativeStream 快照 + finishStream 账本归属快照）
  currentAttemptId(): string {
    return this.attemptIdFn();
  }

  // 释放运行占用（finishStream 轮收尾——先失效后释放的「释放」点）
  releaseRun(): void {
    this.releaseRunFn();
  }

  // 图写侧句柄快照（finishStream 收尾身份取值口——graphWrite 私有经此到达）
  graphHandleSnapshot(): GraphRunHandle | null {
    return this.graphWrite.handleSnapshot();
  }

  // 图轮收尾委托（终答提交 + run 终态 + 账本一体——编排体在 ChatGraphWriteCtrl；
  // GraphFinishInput 带 placeholderNodeId 走「更新既有占位行」收口）
  graphFinishRound(input: GraphFinishInput): Promise<GraphNodeRef | null> {
    return this.graphWrite.finishRound(input);
  }

  // 流中占位行落库（ChatStreamCheckpoint 域经此到达编排层）
  commitStreamPlaceholder(content: string, reasoning: string): Promise<string> {
    return this.graphWrite.beginStreamPlaceholder(content, reasoning);
  }

  // 流中占位行增量写（防迟到复活守卫在命令层谓词）
  checkpointStreamPlaceholder(nodeId: string, content: string,
    reasoning: string): Promise<boolean> {
    return this.graphWrite.checkpointStreamPlaceholder(nodeId, content, reasoning);
  }
}
