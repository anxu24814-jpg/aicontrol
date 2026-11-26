// 消息重试编排域（2026-09-20 消息重新生成立域，域级最小拆分自 ChatSendCtrl.ets 迁出
// ——ChatSendCtrl 本笔越 1200 硬线，新增的重试域整域外迁〔宪法「新增功能域不论行数一律
// 先拆」〕）。★ 2026-09-26 legacy 退役笔3 随形收窄：legacy 就地替换＋多版本链（retryLegacy /
// takeVariantPayloadFor / applyFinalVariant / switchVariant 与存储域件 MessageVariantDb）
// 随线性写路径整域退役删除。★ 2026-10-25 rik 形态统一笔：**单链收敛**——原末轮专用链
// retryLast/retryGraph（内存整轮清扫 + 就地承载行）整段退役，唯一入口 = 中途整轮重试
// retryAt（任意已收尾助手轮，含末轮；末轮与历史轮等价走「替代分支 + 路径换源重载」，
// 视图回从头由重建链 reset 天然承接——原 retryGraph 内的锚态复位〔2026-10-13 U4R〕即
// 因重建链天然复位而无需迁移）。发送编排（复位段/组装段/轮次发起）经 ChatRetryHost 回接
// 宿主 ChatSendCtrl——**禁第二条请求链**（组装与发送共用宿主 assembleRound/startRound）。
// 沿革：重试真链 2026-09-14 落地（44e89bc）→ 2026-09-15 撤链（594 节）→ 2026-09-20 复活
// 取回并升级多版本（决明「执行方案，拍板按推荐来」——方案档 docs/方案-消息重新生成-
// 20260920.md）→ 2026-09-26 消息架构整合笔3 S1 图形制（替代分支）→ 2026-09-26 legacy
// 退役笔3（多版本域退役，本域收窄为图重试）→ 2026-10-25 rik 形态统一笔（单链收敛）。
// 账本口径拍板：重试消耗照常落账（账本与消息生命周期解耦，统计页全量求和）；帮助中心
// 「消息格式」条有说明句。
// ★★ 2026-09-26 自检修复（blocked 在重试入口漏接；笔3 二值化后为唯一拒写判据）：
// retryAt 分流前 blocked 早退——非 graph 态（旧格式墓碑）/ graph 空分支坏库态 /
// 态读异常下一律拒写，早退点在一切破坏性动作（删行/占位落库）之前（占用与窗口闸
// 一并归还），呈报文案单源 = ChatBranchPolicy.TOMBSTONE_TOAST_TEXT（与发送入口逐字同源）。
import { AiConnection } from '../../common/providers/AiTypes';
import { nextMessageId, nextRowCreatedAt } from '../../common/store/ChatDb';
import { clearConversationSuggestions } from '../../common/SuggestGen';
import { BranchAnchorRow, resolveRunInputAnchor, TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { readBranchAnchors, ROUTE_BLOCKED } from '../../common/chat/ChatContextSource';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { ChatSendRefs } from './ChatSendCtrl';

// 宿主接口：重试域引用的宿主编排能力（ChatSendCtrl implements，全部薄直通或抽段方法）
export interface ChatRetryHost {
  isDisposed(): boolean;              // this.disposed（销毁闸）
  // 重试流式复位段（宿主私有态集中地——流域意图方法 beginStreamRound 绑 id 并同拍清
  // 三值〔2026-09-30 B 收拢〕+ setSending(true)/forceToBottom，方法体见宿主）
  beginRetryStreaming(msgId: string): void;
  // 重试组装段（宿主私有链：记忆块 → 技能上下文 → assembleRound → 工具轮重置 → 执行上下文
  // 构造 → 轮次用量清零 → startRound；守卫 disposed/sending/身份快照在段首——方法体见宿主）
  // ★ roundToken 形参（2026-09-26 笔1 S2）：重试轮身份快照随段传递
  launchRetryRound(conn: AiConnection, roundToken: string): void;
  // ── 运行隔离面（2026-09-26 笔1 S2）：重试轮与发送轮同走占用闸与身份核验 ──
  acquireRun(): boolean;              // 接纳（同会话已有活跃 run = false，V9）
  currentRunToken(): string;          // 当前轮身份令牌（'' = 无活跃轮）
  releaseRunWithGuard(): void;        // 守卫失败归还占用（blocked 早退/各失败支）
  // ── 图会话重试面（2026-09-26 笔3 S1/K5；legacy 退役笔3 起唯一形态）──
  // 路由二值读取（★ 2026-09-27 订正：原「待强迁/锁定/黑名单」三机制已随迁移机制退役——
  // 'blocked' = 旧格式墓碑 / graph 空分支坏库态 / 态读异常，retryAt 拒写判据；
  // 与发送入口同源同判据）
  routeState(): string;
  ensureGraphRoute(): Promise<void>;  // 路由装载（重试轮首；异常 fail-closed 落 blocked）
  // 重试替代分支起轮（K5：找锚 → forkBranch → prepareRetryRun → 切分支 → 数据源锚切换；
  // false = 锚点缺失/起轮失败）
  beginGraphRetry(targetMsgId: string): Promise<boolean>;
}

export class ChatRetryCtrl {
  private refs: ChatSendRefs;
  private host: ChatRetryHost;

  constructor(refs: ChatSendRefs, host: ChatRetryHost) {
    this.refs = refs;
    this.host = host;
  }

  // 重试唯一入口（2026-10-25 rik 形态统一笔：retryLast 退役后原「中途整轮重试」即全场景
  // 唯一链——目标 = 任意已收尾 assistant 轮（含末轮；可用性判据在 ChatBranchPolicy.
  // canRetryAt，调用侧〔ChatMessageMenuCtrl.retryFromBubble / retryRound〕先行过闸呈报）；
  // 锚点对目标**精确解**——目标所属 run 的完整输入锚点由父链纯函数定位
  //（ChatBranchPolicy.resolveRunInputAnchor，输入面 = ChatContextSource.readBranchAnchors 一次
  // 取全），锚点交给既有 beginGraphRetry（仓储侧 walkRetryAnchor 对 user 锚自证通过；
  // **不回退末轮锚**——中途目标用末轮锚会张冠李戴，末轮目标用本级锚恰为精确解）。
  // 视图处理 = **路径换源重载**（refs.reloadBranchPath：切到新分支后视图 = 共享前缀 +
  // 锚点 user，L9 分页锚/估算/建议随重载失效；锚态复位由重建链 reset 天然承接）；
  // 重载完成再推承载行起轮。
  retryAt(nodeId: string): void {
    if (this.refs.sending()) {
      this.refs.toast('请等待当前回复结束再重试');
      return;
    }
    if (nodeId === '') {
      this.refs.toast('这条消息的位置信息还没就绪，暂不可用');
      return;
    }
    const conn: AiConnection | null = this.refs.conn();
    if (conn === null) {
      this.refs.toast('请先在「设置 > 服务商管理」完善服务商（接口地址、密钥与模型）');
      return;
    }
    if (!this.host.acquireRun()) {
      this.refs.toast('当前会话已有进行中的回复，请等待完成或先停止');
      return;
    }
    // 异步窗口闸（★ 2026-09-26 自检位B 修复 B4/D5，原形制照已退役的 retryLast 同位注释）：接纳即
    // 置 sending——acquire 到 beginRetryStreaming 之间还有路由装载/建分支/换源三段异步，
    // 原只在 beginRetryStreaming 置位 ⇒ 该窗口内编辑/创建分支/复制/切分支全不被
    //「请先停止当前回复」拦（与在途轮并行改同一会话）。失败支已有 setSending(false) 归还
    const roundToken: string = this.host.currentRunToken();
    this.refs.setSending(true);
    this.host.ensureGraphRoute()
      .catch((): void => undefined)
      .then((): void => {
        if (this.host.isDisposed() || roundToken === '' ||
          roundToken !== this.host.currentRunToken()) {
          return;
        }
        // ★ legacy 退役笔3 判据面统一（★ 旧会话墓碑笔随形）：原走 isGraphMode() 落「尚未
        // 完成迁移」文案（blocked 分流判据曾与已退役的 retryLast 不一致）；收编后与
        // 发送入口同源——routeState() blocked 早退 + **同一句墓碑短句**
        if (this.host.routeState() === ROUTE_BLOCKED) {
          this.refs.toast(TOMBSTONE_TOAST_TEXT);
          this.refs.setSending(false);
          this.host.releaseRunWithGuard();
          return;
        }
        this.retryAtGraph(nodeId, conn, roundToken);
      });
  }

  // 中途整轮重试主体：锚点定位（纯函数预校验）→ 既有 beginGraphRetry 起替代分支 → 路径换源
  // 重载 → 推承载行 + 组装段起轮。任一步失败均呈报并归还占用（不静默、不留半成品气泡）
  private retryAtGraph(nodeId: string, conn: AiConnection, roundToken: string): void {
    const convId: string = this.refs.conversationId();
    // 已解析输入锚跨后续 Promise 链保留（任务书 §6.A.5：换源后不得从「最后 user」重新猜）
    let roundAnchor: string = '';
    readBranchAnchors(convId)
      .catch((): Map<string, BranchAnchorRow> => new Map<string, BranchAnchorRow>())
      .then((nodes: Map<string, BranchAnchorRow>): Promise<boolean> => {
        if (this.host.isDisposed() || roundToken === '' ||
          roundToken !== this.host.currentRunToken()) {
          return Promise.resolve(false);
        }
        const anchor: string | null = resolveRunInputAnchor(nodeId, nodes);
        if (anchor === null) {
          this.refs.toast('未找到这条消息所属轮的输入锚点，本次重试未执行');
          return Promise.resolve(false);
        }
        roundAnchor = anchor;
        return this.host.beginGraphRetry(anchor);
      })
      .then((ok: boolean): Promise<void> => {
        if (this.host.isDisposed() || roundToken === '' ||
          roundToken !== this.host.currentRunToken()) {
          return Promise.resolve();
        }
        if (!ok) {
          this.refs.toast('未找到重试锚点，本次重试未执行');
          this.refs.setSending(false);
          this.host.releaseRunWithGuard();
          return Promise.resolve();
        }
        // 路径换源重载（新分支 = 共享前缀 + 锚点 user；旧后续留在原分支不再上屏）
        return this.refs.reloadBranchPath()
          .catch((): boolean => false) // ★ D6：异常按失败收（换源面 fail-closed）
          .then((refreshed: boolean): void => {
            if (this.host.isDisposed() || roundToken === '' ||
              roundToken !== this.host.currentRunToken()) {
              return;
            }
            if (!refreshed) {
              // ★ 2026-09-26 全链复检余项（D6）：换源失败**不起轮**——替代分支已建而屏上仍是
              // 旧路径，起轮即屏库分叉；呈报并归还占用（形制照本函数其余失败支）
              this.refs.toast('视图刷新失败，请重进会话');
              this.refs.setSending(false);
              this.host.releaseRunWithGuard();
              return;
            }
            const holder: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
            holder.streaming = true;
            holder.live = true; // 实时行标记（A3）：id 为内存 id，图身份只认回填（live 注释）
            // 承载行时间与轮级模型名（2026-10-12 消息时间头笔；★ 同日自检轮补）：与
            // dispatchSend 占位行同口径（同 retryGraph 承载行）
            holder.createdAt = nextRowCreatedAt();
            holder.modelLabel = conn.model;
            // 新轮登记（2026-10-08 状态收敛笔：路径换源完成、holder push 前登记；输入锚 =
            // 上文已解析并用于 beginGraphRetry 的同一锚——精确重试的已证明身份，不从换源后的
            //「最后 user」重猜）
            this.refs.dataSource.beginDisplayRound(roundToken, roundAnchor, holder);
            this.refs.dataSource.push(holder);
            clearConversationSuggestions(this.refs.conversationId());
            this.host.beginRetryStreaming(holder.id);
            this.host.launchRetryRound(conn, roundToken);
          });
      })
      .catch((e: Object): void => {
        this.refs.toast('重试失败：' + (e as Error).message);
        this.refs.setSending(false);
        this.host.releaseRunWithGuard();
      });
  }
}
