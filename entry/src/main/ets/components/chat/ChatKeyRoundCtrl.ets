// Key 池轮次域（2026-09-20 自 ChatSendCtrl.ets 域级最小拆分迁出——技术债务清单登记在案
// 候选缝兑现：ChatSendCtrl 剔头越 1200 硬线，重试域外迁后仍贴线，把边界最清晰的 Key 池
// 轮次域整体外迁〔方法体自 ChatSendCtrl 逐字搬迁，宿主直引收敛为 ChatKeyRoundHost 接口，
// 照 ChatToolRoundCtrl〔2026-09-08〕与 CubeEngineCtrl〔2026-09-18〕两先例〕）。
// 域定义一句话：一轮（= 一次用户发送/重试的全部尝试）的 Key 池轮次态机——取启用 key 序
// → 起始位分派（rotate 轮转 / random 随机，单一来源 nextPickStart）→ 逐支尝试（Asset 取
// 明文；401/403/429 = key 级失败顺位切换重发同消息，一轮内不重用；网络错误不切）→ 全失败
// 才 failRound。★ 语义红线（随域搬迁不动）：key 明文不进日志/toast；失败切换重发同消息
// 不动占位气泡与库行；每次起流前 refreshEstimate 对齐本流（k 校准分母侧）；流终态引用
// 即刻置 null（防工具执行期停止键失效——activeStream 赋值经宿主 setActiveStream）。
// 消费方：ChatSendCtrl（dispatchSend 发起 / onStreamError 切换 / finishStream 快照与清空 /
// ctxCalc 闭包 currentConn·currentHistory / ChatToolRoundHost.roundHistoryRef 薄委托 /
// attemptCurrent 接口实现薄委托〔工具轮续轮〕）
import { AiChatMessage, AiConnection, AiToolDef, ChatStream, SamplingParams } from '../../common/providers/AiTypes';
import { loadPoolKey } from '../../common/store/KeyStore';
import { KEY_PICK_ROTATE, nextPickStart, queryEnabledKeyIds } from '../../common/store/ProviderKeyDb';

// 宿主接口：Key 池域引用的宿主编排能力（ChatSendCtrl implements，全部薄直通）
export interface ChatKeyRoundHost {
  isDisposed(): boolean;             // this.disposed（销毁闸）
  isSending(): boolean;              // this.refs.sending()
  refreshEstimateFor(history: AiChatMessage[]): void;  // ctxCalc.refreshEstimate（估算对齐）
  createStreamFor(conn: AiConnection): ChatStream;     // cube.createStream（双引擎分流点）
  setActiveStream(stream: ChatStream | null): void;     // this.activeStream = stream（abort 面；null = 流终态清引用）
  toolDeclarations(): AiToolDef[];   // toolRound.declarations()（本轮声明）
  failRound(message: string): void;  // 最终失败收尾（notice + finishStream('error')）
}

export class ChatKeyRoundCtrl {
  private host: ChatKeyRoundHost;
  // ── 轮次态（一轮 = 一次用户发送/重试的全部尝试；重发同消息不动占位气泡与库行）──
  private roundConn: AiConnection | null = null; // 本轮连接（端点/协议/自定义头）
  private roundHistory: AiChatMessage[] = []; // 本轮请求历史（失败切换重发同消息）
  private roundKeyIds: string[] = []; // 本轮启用 key 序（起始位已归位到首位——模式无关）
  private roundPos: number = -1; // 当前尝试下标（-1 = 无进行中轮次）
  private roundLastError: string = ''; // 最近一次失败原因（全部失败时呈报）
  private roundThinking: string = ''; // 本轮思考档位（失败切换重发同参数；'' = 不带）
  private roundSampling: SamplingParams | null = null; // 本轮采样（同上；null = 未配置不带）

  constructor(host: ChatKeyRoundHost) {
    this.host = host;
  }

  // 本轮连接只读（宿主 onStreamDone 锚点记录 / finishStream 用量归属快照 / ctxCalc 闭包）
  currentConn(): AiConnection | null {
    return this.roundConn;
  }

  // 本轮请求历史活引用（宿主工具轮 roundHistoryRef / ctxCalc 闭包——push 即生效）
  currentHistory(): AiChatMessage[] {
    return this.roundHistory;
  }

  // 轮次收尾清空（宿主 finishStream 调——五成员复位防陈旧续传）
  resetForSettle(): void {
    this.roundConn = null;
    this.roundHistory = [];
    this.roundThinking = '';
    this.roundSampling = null;
    this.roundKeyIds = [];
    this.roundPos = -1;
  }

  // 轮次启动：取启用 key 序 → 轮询指针定起始位（进程内轮转）→ 首次尝试。池空 =
  // 解析与发送间被清空的竞态（常规空池在 conn 解析已拦）——按失败收尾不静默
  startRound(conn: AiConnection, history: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null): void {
    this.roundConn = conn;
    this.roundHistory = history;
    this.roundThinking = thinking;
    this.roundSampling = sampling;
    this.roundLastError = '';
    queryEnabledKeyIds(conn.providerId)
      .then((enabled: string[]): void => {
        if (this.host.isDisposed() || !this.host.isSending()) {
          return; // 取钥间隙页面销毁/已收尾（停止、库失败等）——轮次作废
        }
        if (enabled.length === 0) {
          this.host.failRound('密钥未配置：请在「服务商管理」为该服务商添加 API Key');
          return;
        }
        // 起始位按服务商配置的取钥方式分派（rotate = 轮转指针原行为 / random = 均匀随机；
        // 脏值与缺字段一律 rotate 兜底——分派单一来源 nextPickStart）
        const start: number = nextPickStart(conn.keyPickMode ?? KEY_PICK_ROTATE,
          conn.providerId, enabled.length);
        // 轮转起始归位：尝试序 = 自 start 起环绕一周（失败切换顺位推进，一轮内不重用）
        this.roundKeyIds = enabled.slice(start).concat(enabled.slice(0, start));
        this.roundPos = 0;
        this.attemptCurrent();
      })
      .catch((e: Object): void => {
        if (this.host.isDisposed() || !this.host.isSending()) {
          return;
        }
        this.host.failRound('密钥池读取失败：' + (e as Error).message);
      });
  }

  // 当前 key 尝试：Asset 取明文（空/失败顺位下一支；明文不进日志/toast——安全红线）；
  // 每次起流前刷新估算（首流/失败切换/工具续轮全经此咽喉点——pendingEstimate 恒对齐
  // 「本流实际请求」，k 的分母侧；失败重发同序为幂等刷新）
  attemptCurrent(): void {
    const conn: AiConnection | null = this.roundConn;
    if (conn === null || this.roundPos < 0 || this.roundPos >= this.roundKeyIds.length) {
      return;
    }
    const keyId: string = this.roundKeyIds[this.roundPos];
    loadPoolKey(conn.providerId, keyId)
      .then((plaintext: string): void => {
        if (this.host.isDisposed() || !this.host.isSending()) {
          return; // 取钥间隙已停止/销毁——不发
        }
        if (plaintext === '') {
          // 资产缺失（条目与行同生命周期，正常不达；迁移中断/手工清资产可达）——跳过该支；
          // 已是最后一支 = 按最近失败原因收尾（防轮次悬挂）
          if (!this.tryNextKey('Key 资产缺失')) {
            this.host.failRound(this.roundLastError);
          }
          return;
        }
        this.host.refreshEstimateFor(this.roundHistory);
        const stream: ChatStream = this.host.createStreamFor(conn);
        this.host.setActiveStream(stream);
        stream.start(conn, plaintext, this.roundHistory, this.roundThinking, this.roundSampling,
          this.host.toolDeclarations());
      })
      .catch((e: Object): void => {
        if (this.host.isDisposed() || !this.host.isSending()) {
          return;
        }
        if (!this.tryNextKey('Key 读取失败：' + (e as Error).message)) {
          this.host.failRound(this.roundLastError);
        }
      });
  }

  // 失败切换（401/403/429 才切，网络错误不切——判据表 RETRY_STATUSES 在宿主流回调域）：
  // 顺位下一支重发；false = 一轮打尽
  tryNextKey(lastMessage: string): boolean {
    this.roundLastError = lastMessage;
    this.host.setActiveStream(null);
    if (this.roundPos + 1 < this.roundKeyIds.length) {
      this.roundPos++;
      this.attemptCurrent();
      return true;
    }
    return false;
  }
}
