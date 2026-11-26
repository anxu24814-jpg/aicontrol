// Key 池轮次域（2026-09-20 自 ChatSendCtrl.ets 域级最小拆分迁出——技术债务清单登记在案
// 候选缝兑现：ChatSendCtrl 剔头越 1200 硬线，重试域外迁后仍贴线，把边界最清晰的 Key 池
// 轮次域整体外迁〔方法体自 ChatSendCtrl 逐字搬迁，宿主直引收敛为 ChatKeyRoundHost 接口，
// 照 ChatToolRoundCtrl〔2026-09-08〕先例；同日 CubeEngineCtrl〔2026-09-18〕先例件已随
// 2026-10-10 阶段6第二段退役笔删除〕）。
// 域定义一句话：一轮（= 一次用户发送/重试的全部尝试）的 Key 池轮次态机——取启用 key 序
// → 起始位分派（rotate 轮转 / random 随机，单一来源 nextPickStart）→ 逐支尝试（Asset 取
// 明文；401/403/429 = key 级失败顺位切换重发同消息，一轮内不重用；网络错误与 5xx 不切）→ 全失败
// 才 failRound。★ 语义红线（随域搬迁不动）：key 明文不进日志/toast；失败切换重发同消息
// 不动占位气泡与库行；每次起流前 refreshEstimate 对齐本流（k 校准分母侧）；流终态引用
// 即刻置 null（防工具执行期停止键失效——activeStream 赋值经宿主 setActiveStream）。
// 消费方：ChatSendCtrl（dispatchSend 发起；★ 2026-09-27 拆分笔随形——onStreamError 切换 /
// finishStream 快照与清空两消费点已随流回调域迁 ChatStreamFlowCtrl；ctxCalc 闭包
// currentConn·currentHistory / ChatToolRoundHost.roundHistoryRef 薄委托 /
// attemptCurrent 接口实现薄委托〔工具轮续轮〕）
import { AiChatMessage, AiConnection, AiToolDef, ChatStream, SamplingParams } from '../../common/providers/AiTypes';
// 二期 S2：DS 扩展字段两布尔（标题三态 / 安全开关）在本咽喉点算好，随 start 第 8 参下传
// ——判据单源 = DsServerTools.isDsFlashConnection（非 DS 连接恒 null = 请求体零变化）
import { DsStreamExtras } from '../../common/providers/ChatStreamBase';
import { isDsFlashConnection } from '../../common/providers/DsServerTools';
import {
  DS_TITLE_MODE_EVERY, DS_TITLE_MODE_OFF, dsTitleMode, isDsSafetyCheckEnabled
} from '../../common/AppPreferences';
import { loadPoolKey } from '../../common/store/KeyStore';
import { KEY_PICK_ROTATE, nextPickStart, queryEnabledKeyIds } from '../../common/store/ProviderKeyDb';

// 宿主接口：Key 池域引用的宿主编排能力（ChatSendCtrl implements；★ 2026-09-27 订正
// L-E-2：实现位自 2026-09-25 拆分起在 ChatHostDelegates，宿主仅构造接线）
export interface ChatKeyRoundHost {
  isDisposed(): boolean;             // this.disposed（销毁闸）
  isSending(): boolean;              // this.refs.sending()
  // ── 运行隔离面（2026-09-26 笔1 S2，I6/V2）──
  // 当前轮身份令牌：取钥回调凭**发起时的局部快照**比对（★ 2026-09-26 自检修复 D-1：原快照
  // 存共享字段、新一轮覆写后旧回调与新轮恒等放行，守卫失效）——A 轮取钥中停止、B 发送后
  // A 迟到回调在此被拦，不借 B 的 sending 通过（V2 实锤面）
  runToken(): string;
  // attempt 换代（密钥轮换 = 新 attempt，I5）——tryNextKey 顺位切换时调用
  nextAttempt(): void;
  refreshEstimateFor(history: AiChatMessage[]): void;  // ctxCalc.refreshEstimate（估算对齐）
  createStreamFor(conn: AiConnection): ChatStream;     // 原生协议流工厂（2026-10-10 退役笔后直连）
  setActiveStream(stream: ChatStream | null): void;     // 资源交接（宿主闭包转调 flow.attachStream，2026-09-30 B 收拢——abort 面；null = 流终态清引用）
  toolDeclarations(): AiToolDef[];   // toolRound.declarations()（本轮声明）
  failRound(message: string, status: number): void;  // 最终失败收尾（notice + finishStream('error')；status 供跳转动作分类——2026-09-25 笔）
}

export class ChatKeyRoundCtrl {
  private host: ChatKeyRoundHost;
  // ── 轮次态（一轮 = 一次用户发送/重试的全部尝试；重发同消息不动占位气泡与库行）──
  private roundConn: AiConnection | null = null; // 本轮连接（端点/协议/自定义头）
  private roundHistory: AiChatMessage[] = []; // 本轮请求历史（失败切换重发同消息）
  private roundKeyIds: string[] = []; // 本轮启用 key 序（起始位已归位到首位——模式无关）
  private roundPos: number = -1; // 当前尝试下标（-1 = 无进行中轮次）
  private roundLastError: string = ''; // 最近一次失败原因（全部失败时呈报）
  private roundLastStatus: number = 0; // 最近一次失败的 HTTP 状态码（2026-09-25 笔：Key 池打尽后随 failRound 落跳转动作分类——0 = 无码哨值不设动作；与 roundLastError 同拍写入）
  private roundThinking: string = ''; // 本轮思考档位（失败切换重发同参数；'' = 不带）
  private roundSampling: SamplingParams | null = null; // 本轮采样（同上；null = 未配置不带）
  // 客户端 function 工具已剔除标记（二期 S3 / §1-7 工具共存自适应）：400 冲突命中后置真，
  // 本枝后续重发只声明官方服务端工具；轮次收尾复位（resetForSettle）
  private clientToolsDropped: boolean = false;

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
    this.clientToolsDropped = false;
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
    this.roundLastStatus = 0;
    // 身份快照（★ 2026-09-26 自检修复 D-1）：**局部常量**——本轮取钥链各闭包各自固化，
    // 跨轮互不干扰（原存共享字段 roundToken：新一轮 startRound 覆写后，旧回调与新轮比的是
    // 同一个新值 ⇒ 恒等放行，V2 守卫失效）
    const token: string = this.host.runToken();
    queryEnabledKeyIds(conn.providerId)
      .then((enabled: string[]): void => {
        if (this.host.isDisposed() || !this.host.isSending() || this.host.runToken() !== token) {
          return; // 取钥间隙页面销毁/已收尾（停止、库失败等）——轮次作废
        }
        if (enabled.length === 0) {
          // 第二参传 0（无码哨值 = 不设跳转动作——「未配密钥直达服务商页」属增强不做，任务书 §2.2）
          this.host.failRound('密钥未配置：请在「服务商管理」为该服务商添加 API Key', 0);
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
        if (this.host.isDisposed() || !this.host.isSending() || this.host.runToken() !== token) {
          return;
        }
        this.host.failRound('密钥池读取失败：' + (e as Error).message, 0);
      });
  }

  // DS 扩展字段两布尔（二期 S2；非 DS 连接 / 两档全关恒 null ⇒ 请求体逐字节零变化）。
  // title 的 'first' 语义 = **本会话首个请求**（请求历史里还没有 assistant 轮）——不做
  // 「无标题就每轮重试」，拿不到交 TitleGen 兜底；'every' 恒带（每轮最多多等 5 秒）。
  // 两值都是纯读：偏好键 + 连接判据 + 本轮历史，无 IO
  private dsExtrasOf(conn: AiConnection): DsStreamExtras | null {
    if (!isDsFlashConnection(conn)) {
      return null;
    }
    let safety: boolean = isDsSafetyCheckEnabled();
    let title: boolean = false;
    const mode: string = dsTitleMode();
    if (mode === DS_TITLE_MODE_EVERY) {
      title = true;
    } else if (mode !== DS_TITLE_MODE_OFF) {
      let hasAssistant: boolean = false;
      for (const m of this.roundHistory) {
        if (m.role === 'assistant') {
          hasAssistant = true;
          break;
        }
      }
      title = !hasAssistant;
    }
    if (!safety && !title) {
      return null;
    }
    const extras: DsStreamExtras = { title: title, safety: safety };
    return extras;
  }

  // 剔除客户端 function 工具后同 key 重发一次（二期 S3 / §1-7 工具共存自适应）：调用方
  // （ChatStreamFlowCtrl.onStreamError）仅在 400 + 零产出 + 冲突文案命中时调用；已剔除过
  // 返回 false = 不重复剔（不会无限重发）。只改本轮声明面，不动历史与请求组装单源
  retryWithoutClientTools(): boolean {
    if (this.clientToolsDropped || this.roundConn === null) {
      return false;
    }
    this.clientToolsDropped = true;
    this.attemptCurrent();
    return true;
  }

  // 本轮声明面（工具共存自适应唯一分派点）：剔除态只留官方服务端工具（serverType 非空）
  private roundDeclarations(): AiToolDef[] {
    const decls: AiToolDef[] = this.host.toolDeclarations();
    if (!this.clientToolsDropped) {
      return decls;
    }
    return decls.filter((t: AiToolDef): boolean =>
      t.serverType !== undefined && t.serverType !== '');
  }

  // 当前 key 尝试：Asset 取明文（空/失败顺位下一支；明文不进日志/toast——安全红线）；
  // 每次起流前刷新估算（首流/失败切换/工具续轮全经此咽喉点——pendingEstimate 恒对齐
  // 「本流实际请求」，k 的分母侧；失败重发同序为幂等刷新）
  attemptCurrent(): void {
    const conn: AiConnection | null = this.roundConn;
    if (conn === null || this.roundPos < 0 || this.roundPos >= this.roundKeyIds.length) {
      return;
    }
    // 身份快照同 startRound（★ D-1）：**局部常量**随本链闭包固化——工具续轮/失败切换重入
    // 本方法时重取当下令牌（同轮内值恒等）；跨轮旧链按各自快照失配作废，不借新轮 sending
    const token: string = this.host.runToken();
    const keyId: string = this.roundKeyIds[this.roundPos];
    loadPoolKey(conn.providerId, keyId)
      .then((plaintext: string): void => {
        if (this.host.isDisposed() || !this.host.isSending() || this.host.runToken() !== token) {
          return; // 取钥间隙已停止/销毁——不发
        }
        if (plaintext === '') {
          // 资产缺失（条目与行同生命周期，正常不达；迁移中断/手工清资产可达）——跳过该支；
          // 已是最后一支 = 按最近失败原因收尾（防轮次悬挂）
          if (!this.tryNextKey('Key 资产缺失', 0)) {
            this.host.failRound(this.roundLastError, this.roundLastStatus);
          }
          return;
        }
        this.host.refreshEstimateFor(this.roundHistory);
        const stream: ChatStream = this.host.createStreamFor(conn);
        this.host.setActiveStream(stream);
        stream.start(conn, plaintext, this.roundHistory, this.roundThinking, this.roundSampling,
          this.roundDeclarations(), '聊天', this.dsExtrasOf(conn));
      })
      .catch((e: Object): void => {
        if (this.host.isDisposed() || !this.host.isSending() || this.host.runToken() !== token) {
          return;
        }
        if (!this.tryNextKey('Key 读取失败：' + (e as Error).message, 0)) {
          this.host.failRound(this.roundLastError, this.roundLastStatus);
        }
      });
  }

  // 失败切换（401/403/429 才切，网络错误与 5xx 不切——服务端失败换 key 无益同 key 重发，
  // 判据表 RETRY_STATUSES 在宿主流回调域）：顺位下一支重发；false = 一轮打尽。
  // ★ status 随 lastMessage 同拍快照（2026-09-25 错误 notice 跳转入口笔）：Key 池打尽后
  // failRound 按它落跳转动作分类（401/403 打尽 = notice 可点直达服务商页的主路径）；0 =
  // 无码哨值（密钥未配置/池读取失败/资产缺失等非 HTTP 码路径）
  tryNextKey(lastMessage: string, status: number): boolean {
    this.roundLastError = lastMessage;
    this.roundLastStatus = status;
    this.host.setActiveStream(null);
    this.host.nextAttempt(); // 密钥轮换 = 换 attempt（I5；2026-09-26 笔1 S2）
    if (this.roundPos + 1 < this.roundKeyIds.length) {
      this.roundPos++;
      this.attemptCurrent();
      return true;
    }
    return false;
  }
}
