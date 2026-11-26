// 发送前异步组装域（排队插队施工总案 P1 域级最小拆分自 ChatSendCtrl.ets 迁出——宪法
// 1200 硬线，方法体与沿革注释自 send() 逐字搬迁，零行为变化）。
// 域定义一句话：**发送前 payload 组装**——send() 守卫全过（占用已接纳）之后的异步组装链：
// 附件载荷（失败降级纯文本）→ 图链转图并行下载编码 → 记忆块快照 → 技能上下文快照 →
// 知识注入计划快照 → 图路由装载 → 路径摘要库直查 → 交宿主派发（dispatchSend）。
// · 为何不能并入既有件（反碎片下限②申报）：ChatRoundAssembly 是「协议请求组装」
//  （assembleRound——历史/注入材料已成后的请求体铸造，消费点两处含重试链）；本件是
//  「发送前材料收集」（附件下载/记忆技能知识快照/路由装载——只在 send 链消费）。职责缝
//   不同：并回 ChatRoundAssembly = 让重试链连带持附件下载与图路由装载（重试轮不需要，
//   其对应段在 launchRetryRound 自持）；亦无其它同域既有件可并。
// · 依赖方向（防循环依赖，照 ChatSendLifecycleCtrl 同款纪律）：本件禁 import ChatSendCtrl
//   的任何符号（含类型——chat 域既有环不增员，照 ChatRoundAssembly 头注释口径）；宿主态
//  （销毁闸/占用释放/会话 id/toast/消息全量/派发口）一律经 ChatSendAssemblyHost 闭包现读
//   到达，禁在本件缓存任何宿主态；snapshot（三快照读取域）无环依赖，直注引用。
// · 派发口形参集（dispatchAssembled）= 宿主 dispatchSend 私有方法签名的原样镜像（Q2 增
//   queueItemId 供 Q3 事务删行 / autoDispatch 供拽底判读——两值自 send 入口随链下传）。
import { AiConnection, AiImagePart, PendingAttachment } from '../../common/providers/AiTypes';
import { ChatSnapshotCtrl, SkillSendContext } from './ChatSnapshotCtrl';
import { KnowledgeInjectPlan } from '../../common/providers/RequestInject';
import { AttachmentPayload, buildAttachmentPayload } from '../../common/AttachmentUtil';
import { fetchTextImages } from '../../common/TextImageFetch';
import { cleanupAttachments } from './AttachmentPickCtrl';
import { ChatMessage } from './ChatMessageCompose';
import { RequestSummaryInput, readPathSummaryInput } from '../../common/chat/ChatContextSource';

// 宿主面（ChatSendCtrl 构造序末位直注——照 ChatSendLifecycleRefs 形制：属性式函数类型，
// ArkTS 对象字面量须对应属性式接口；闭包持宿主态现读，值语义与拆分前同源）
export interface ChatSendAssemblyHost {
  // 销毁闸（this.disposed 现读——两处 disposed 早退的判据源）
  isDisposed: () => boolean;
  // 运行占用释放（组装链失败/离页丢弃早退的归还点）
  releaseRun: () => void;
  // 图路由装载（ensureGraphRoute 薄委托实参同款——写入口路由判据）
  ensureGraphRoute: () => Promise<void>;
  // 会话 id（路径摘要库直查实参源）
  conversationId: () => string;
  // 消息全量（知识注入计划快照的窗口源——原 this.refs.dataSource.allMessages()）
  allMessages: () => ChatMessage[];
  // 错误呈报（附件降级与链尾兜底两句 toast 的出口）
  toast: (message: string) => void;
  // 受理后组装失败通知（总案 Q1 T4c 回滚链——send 已返回 true 但本链无 setSending 写的
  // 失败出口：宿主按 queueItemId 转发队列域回滚在飞项；非队列派发〔queueItemId = ''〕时
  // 宿主实现空转零动作）
  onDispatchAbandoned: (queueItemId: string) => void;
  // 派发口（dispatchSend 私有方法签名原样镜像；queueItemId 供 Q3 事务删行，autoDispatch
  // 供拽底判读）
  dispatchAssembled: (conn: AiConnection, text: string, attachments: PendingAttachment[],
    payload: AttachmentPayload, memoryBlock: string, skillCtx: SkillSendContext,
    knowledge: KnowledgeInjectPlan, pathSummary: RequestSummaryInput | null,
    queueItemId: string, autoDispatch: boolean) => void;
}

export class ChatSendAssembly {
  private host: ChatSendAssemblyHost;
  // 三快照读取域（记忆/技能/知识——2026-09-20 拆分件）：无环依赖直注；方法体搬迁面
  // 保持 this.snapshot.X 原字面
  private snapshot: ChatSnapshotCtrl;

  constructor(host: ChatSendAssemblyHost, snapshot: ChatSnapshotCtrl) {
    this.host = host;
    this.snapshot = snapshot;
  }

  // 发送前异步组装 + 派发（自 ChatSendCtrl.send() 中段原样搬迁——不改判据与链序；宿主态
  // 经 this.host 闭包现读，snapshot 直持引用，语义与拆分前逐字等价）。入参全部为 send()
  // 入口的快照——组装期间宿主改态不污染本链；queueItemId / autoDispatch 同为入口快照，
  // 链体只透传不判读。
  assembleAndDispatch(conn: AiConnection, text: string, attachments: PendingAttachment[],
    hasVision: boolean, designateId: string, queueItemId: string,
    autoDispatch: boolean): void {
    // 附件载荷组装（异步）→ 完成后派发；失败降级空载荷（toast 呈报，文本不陪葬）。组装期间
    // 输入条已被清空（canSend 当场为 false）、销毁闸拦住派发并清删副本。
    // ★ 自检轮订正：sending 闸在 dispatchSend 才置位，「组装窗口内用户重新打字再点发送」并非
    // 物理不可达（窗口 = 载荷组装耗时，纯文本几十毫秒、大图重采样可达秒级）；入参全为入口
    // 快照故并发第二笔不污染第一笔，残余面 = 两条消息同时在飞（各写各的），属**存量**行为
    // 另行登记观察项。
    // 记忆块快照在派发前现读（DB 单一真源不缓存——组装期间用户可能在记忆页增删条目，
    // 发送一刻取当下值）。
    // 图链转图并行组装：附件路保留既有 .catch 降级；图链路 fetchTextImages 恒 resolve
    //（内部全捕获，拍板全静默，无需降级分支），两路齐后在链首并入 payload.images——此后
    // 链体零感知：经既有 userReq.images 挂载随本轮请求发出，displayText / 落库 / 气泡零改动。
    Promise.all([
      buildAttachmentPayload(attachments, hasVision)
        .catch((e: Object): AttachmentPayload => {
          this.host.toast('附件处理失败：' + (e as Error).message + '（已按纯文本发送）');
          return { annotate: '', protocolAppend: '', images: [] };
        }),
      fetchTextImages(text, hasVision)
    ])
      .then((both: [AttachmentPayload, AiImagePart[]]): AttachmentPayload => {
        const payload: AttachmentPayload = both[0];
        if (both[1].length > 0) {
          payload.images = payload.images.concat(both[1]);
        }
        return payload;
      })
      .then((payload: AttachmentPayload): Promise<void> => this.snapshot.buildMemoryBlock()
        .then((memoryBlock: string): Promise<void> => this.snapshot.buildSkillContext(designateId)
          // 知识注入计划快照：与记忆/技能块同链同拍现读（DB 单一真源不缓存）；
          // draftText = 本轮文本（恒在窗口末位）
          .then((skillCtx: SkillSendContext): Promise<void> => {
            return this.snapshot.buildKnowledgeBlock(text, this.host.allMessages())
              .then((knowledge: KnowledgeInjectPlan): void => {
                if (this.host.isDisposed()) {
                  cleanupAttachments(attachments);
                  this.host.releaseRun(); // 离页丢弃派发——归还占用（S2：失败准备也归还）
                  // 受理后组装失败（无 setSending 写）——队列回滚
                  this.host.onDispatchAbandoned(queueItemId);
                  return;
                }
                // 图路由装载（写入口路由判据——migrateState 单点读；纯读路由 + 无行即出生
                // 即 graph，装载异常 fail-closed 落 blocked 由下方二道闸呈报墓碑句）。
                // 路由装载后追加路径摘要库直查——图摘要节点滑出读窗时内存窗口无 summary
                // 行，请求组装需注入值补位（fail-open，读失败 = null 无注入）
                this.host.ensureGraphRoute()
                  .then((): Promise<RequestSummaryInput | null> =>
                    readPathSummaryInput(this.host.conversationId()))
                  .then((pathSummary: RequestSummaryInput | null): void => {
                    if (this.host.isDisposed()) {
                      cleanupAttachments(attachments);
                      this.host.releaseRun();
                      // 同上——受理后组装失败队列回滚
                      this.host.onDispatchAbandoned(queueItemId);
                      return;
                    }
                    this.host.dispatchAssembled(conn, text, attachments, payload, memoryBlock, skillCtx,
                      knowledge, pathSummary, queueItemId, autoDispatch);
                  })
                  .catch((e: Object): void => {
                    // 链尾兜底（自检位B 修复 D-4/B3）：dispatchSend 内同步抛错（如历史组装
                    // 异常）原会链悬空——run 占用永久悬挂、发送态与占位气泡无收尾。归还占用 +
                    // 呈报（无活跃流时停止键走 failRound 兜底，不静默）
                    this.host.releaseRun();
                    this.host.toast('发送准备失败：' + (e as Error).message);
                    // 受理后组装失败（无 setSending 写）——队列回滚（按 queueItemId 回队头 +
                    // 清闩 + PAUSED('delivery')，永不静默丢消息）
                    this.host.onDispatchAbandoned(queueItemId);
                  });
              });
          })));
  }
}
