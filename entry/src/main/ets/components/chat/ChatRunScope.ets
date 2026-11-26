// 会话运行占用协调者（进程内单例）：一次「接纳」的进程内账本——按会话登记唯一活跃 run，
// 铸造 run/attempt 身份，提供身份核验与定向释放。三条职责：
// · 接纳即占用：acquire 同步建立占用并铸造 run 身份——组装窗口内第二笔发送被同步拒绝
//  （消灭「sending 置位前双发」窗口）；同会话第二控制器/页面实例同样被拒（单活跃 run，
//   不新增多窗口产品功能）。
// · 身份核验：迟到回调凭「发起时快照的身份」核验——旧 run 的取钥回调/流回调在释放或换代
//   后一律作废，不借新一轮的 sending 通过。
// · 失效先于释放：release 按身份匹配删除——旧 run 的兜底清理（旧 finally）带旧 runId，
//   删不到新登记的 run（V10「旧 finally 不删新登记」）；停止时先 release（失效：探测面全
//   false）再取消资源（HTTP/流）。
// 消费方：ChatSendCtrl（接纳/释放/换代/探测闭包源）；common 层（ToolBrowse/ToolHttp）经
// ToolExecutionContext.isRunActive 闭包消费，不直接 import 本件（分层：common 不引 components）。
import { RunIdentity } from '../../common/chat/MessageContracts';

// 活跃运行条目（进程内存态，不落库——隐私会话同语义零持久）
interface ActiveRun {
  identity: RunIdentity;
}

export class ChatRunScope {
  // 会话 id → 活跃 run（数据有界：条目数 = 进行中会话数，收尾/销毁即删，无界增长不存在）
  private runs: Map<string, ActiveRun> = new Map<string, ActiveRun>();
  // runId 铸造序号（配合时间戳保进程内唯一）
  private runSeq: number = 0;

  // 接纳：会话无活跃 run → 建占用并落身份；已有活跃 run → 拒绝（返回 null，调用方
  // 以中文提示拒单）。同步方法——双发窗口在调用方守卫段内同步闭合。
  // ★ 身份两来源：adoptRunId 缺省 '' = 铸造新身份（既有语义逐字不变）；非空 = **接管库内
  // 既有 run**（ask 等待跨重启续跑——attemptId 按既有编码规则由 runId + attemptEpoch 派生，
  // 写点/探测/释放三面与铸造条目完全同构）
  acquire(conversationId: string, adoptRunId: string = '',
    attemptEpoch: number = 1): RunIdentity | null {
    if (conversationId === '') {
      // 空键不建占用（fail-safe——与 httpAbortRun / grantSessionAllow 同族口径：无会话 id
      // 的调用序缺陷不得在进程账本留下一条永不被定向释放的占用）
      return null;
    }
    if (this.runs.has(conversationId)) {
      return null;
    }
    if (adoptRunId !== '') {
      const epoch: number = attemptEpoch > 0 ? attemptEpoch : 1;
      const adopted: RunIdentity = {
        runId: adoptRunId,
        conversationId: conversationId,
        assistantId: '',
        attemptEpoch: epoch,
        attemptId: ''
      };
      adopted.attemptId = adopted.runId + '#a' + adopted.attemptEpoch;
      this.runs.set(conversationId, { identity: adopted });
      return adopted;
    }
    this.runSeq++;
    const identity: RunIdentity = {
      runId: 'run_' + Date.now() + '_' + this.runSeq,
      conversationId: conversationId,
      assistantId: '',
      attemptEpoch: 1,
      attemptId: ''
    };
    identity.attemptId = identity.runId + '#a' + identity.attemptEpoch;
    this.runs.set(conversationId, { identity: identity });
    return identity;
  }

  // 身份补录（assistantId 接纳时未知——promptState 解析在宿主侧完成后回填；仅首个非空值
  // 生效，防后到空值抹写）
  bindAssistant(conversationId: string, runId: string, assistantId: string): void {
    const run: ActiveRun | undefined = this.runs.get(conversationId);
    if (run !== undefined && run.identity.runId === runId && assistantId !== '' &&
      run.identity.assistantId === '') {
      run.identity.assistantId = assistantId;
    }
  }

  // attempt 换代（密钥轮换 / 自动重试重发；工具续轮不调）：attemptEpoch 自增并派生新
  // attemptId；run 不在场或 runId 不匹配 = ''（调用方零消费即可，不抛错——换代失败随旧
  // 身份一并作废）
  nextAttempt(conversationId: string, runId: string): string {
    const run: ActiveRun | undefined = this.runs.get(conversationId);
    if (run === undefined || run.identity.runId !== runId) {
      return '';
    }
    run.identity.attemptEpoch++;
    run.identity.attemptId = run.identity.runId + '#a' + run.identity.attemptEpoch;
    return run.identity.attemptId;
  }

  // run 活跃探测（队列取消权核验面；探测闭包经 ToolExecutionContext 下发 common 层）。
  // 只读不写——任何持有旧身份的路径在 release 后恒 false
  isActive(conversationId: string, runId: string): boolean {
    const run: ActiveRun | undefined = this.runs.get(conversationId);
    return run !== undefined && run.identity.runId === runId;
  }

  // 释放（按身份匹配——双保险：会话 id 与 runId 都对上才删；旧 run 的兜底清理带旧 runId
  // 删不到新登记，V10）。幂等：已释放再释放零效果
  release(conversationId: string, runId: string): void {
    const run: ActiveRun | undefined = this.runs.get(conversationId);
    if (run !== undefined && run.identity.runId === runId) {
      this.runs.delete(conversationId);
    }
  }
}

// 进程级单例（跨页面实例共享——双控制器/分栏态同会话占用由此互见，I2/V9）
export const chatRunScope: ChatRunScope = new ChatRunScope();
