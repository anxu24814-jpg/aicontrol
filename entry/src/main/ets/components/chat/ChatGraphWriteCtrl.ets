// 图会话写侧编排域：graph 运行的**状态句柄与写命令编排**——路由装载（含无行出生）、发送
// 起轮（prepareRun + 附件 refs）、轮内节点提交（commitRunUnit CAS + 步序单调）、工具事实
// 推进、重试替代分支起轮（fork + prepareRetryRun + 分支切换回调）。运行句柄/revision/步序
// 本域私有；宿主（ChatSendCtrl）只留薄委托与轮次收尾组装（账本/标题/建议仍属宿主收尾域）。
// · 为何独立件（反碎片三问）：ChatContextSource 是 common 层无状态命令编排（本域持跨调用
//   运行态且要回调组件层数据源锚，上浮破分层）；ChatHostDelegates 是薄直通集中地；本域即
//   ChatSendCtrl 越硬线后本次改动所属功能域，按宪法「新增功能域不论行数一律先拆」拆出。
import { ConversationOverride, touchConversationUpdatedAt, nextRowCreatedAt,
  sharedRdbStore } from '../../common/store/ChatDb';
import { MessageAttachmentRow } from '../../common/store/AttachmentDb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrepareRunInput, ORIGIN_SEND, RUN_STATUS_FINISHED, RUN_STATUS_RUNNING,
  MSG_STATUS_STREAMING, RUN_STATUS_AWAITING_INPUT, writeNodeServerTools }
  from '../../common/store/MessageBranchDb';
// 图写命令族自 ChatGraphCommandSource 取；路由三符号（含出生原语）留 ChatContextSource
import { GraphRunHandle, GraphNodeRef, GraphSendStart,
  graphBeginContinue, graphReopenNode, graphBeginRetry,
  graphBeginSend, graphCommitNode, graphCheckpointNode,
  graphFinishRun, graphRecordUsage, graphToolFactAdvance, graphToolFactDispatchIntent,
  walkRetryAnchor, walkLatestUserAnchor } from '../../common/chat/ChatGraphCommandSource';
import { ROUTE_BLOCKED, ROUTE_GRAPH,
  bornGraphConversation, conversationGraphBranch,
  conversationWritableRoute } from '../../common/chat/ChatContextSource';
import { ChatMessage } from './ChatMessageCompose';
import { ToolEventRecord, serializeToolRecord } from './ChatToolRoundCtrl';
// 二期 #7：计次类型与账本列串序列化（零依赖叶子，断言直跑面同源）
import { AiServerToolUse, serverToolUseJsonOf } from '../../common/providers/SseParser';

// 图轮收尾输入（宿主收尾域组装——用量五值与归属快照在宿主局部变量）：runFinalStatus = run
// 层三态终态串（RUN_STATUS_FINISHED / FAILED / STOPPED——MessageBranchDb 常量值；done 收敛
// 判据〔标题/建议触发〕由宿主局部 okFinal 布尔继续承载）；placeholderNodeId = 本轮流中占位
// 行节点 id（ChatStreamCheckpoint 域 settle 交接；'' = 本轮无占位行——收口走既有插行老路）。
// 非空 = 终答收口走「更新既有占位行」路径（终值覆写 + 升级 done，防迟到复活守卫在命令层
// 谓词），与 run 终态（紧随的 graphFinishRun）、账本按既有次序收口
export interface GraphFinishInput {
  content: string;
  reasoning: string;
  runFinalStatus: string;
  diagnostic: string;
  placeholderNodeId: string;
  // DeepSeek 服务端工具原样串（DS 全家桶接入批 S2⑥ 可选位——2026-11-14）：非空 = 终答节点
  // 提交成功后按节点 id 补列 server_tools（writeNodeServerTools 条件写键）；''/缺省 = 不写键
  //（列落 NULL = 非官方档轮/无服务端步骤，既有调用逐字零变化）
  serverTools?: string;
  // 服务端工具计次（二期 #7 可选位）：非空 = 随账本行写 serverToolsUsage 列（v65）。缺省 =
  // 非 DS 轮/未用官方工具（列落空串 = 无计次，展示面不出现）
  serverToolUse?: AiServerToolUse;
  conversationId: string;
  providerId: string;
  modelId: string;
  attemptId: string;
  promptTokens: number;
  completionTokens: number;
  durationMs: number;
  firstTokenMs: number;
  cachedTokens: number;
}

export class ChatGraphWriteCtrl {
  // 路由镜像（两来源：send/retry 轮首 loadRoute 装载 + 页面加载链 publishRouteProbe 探针）。
  // 两态：'graph' / 'blocked'——'blocked' 语义 = **旧格式墓碑**（含历史 migrating 残值与
  // graph 空分支坏库态），loadRoute 的一切异常/降级态 fail-closed 落 blocked。
  // ★ 未装载态单列 ''（宿主发送入口的闸是同步读——初值若为 blocked，页面刚打开时把
  //「还不知道」当「已确认不可写」拒发，且拒发支的自愈装载会凭空建出空会话行）。未装载
  // 不参与拒绝：裁决恒在装载之后（发送链 ensureGraphRoute → dispatchSend 二道闸），装载后
  // 的异常仍 fail-closed 落 blocked，写面安全不变。
  private route: string = '';
  private branchId: string = '';
  // 当前会话 id（beginSend / beginRetry 轮首刷新）——提交链成功后推进会话列表时间的
  // 取值源（GraphRunHandle 不携会话 id，本域自存；页内控制器恒单会话）
  private activeConversationId: string = '';
  // 排队条目 id（beginSend 第三可选参落此）——prepareRun 同事务删除 send_queue_items 行时
  // 消费（'' = 手动/重试路径，无删行面）。零判据、零落库：只为出队删除口预留贯通链，
  // 不与 IN_FLIGHT 内存闩叠加。
  private pendingQueueItemId: string = '';
  // 运行句柄（prepareRun/prepareRetryRun 成功才置位——先提交输入事实再开流）；步序随本
  // run 提交单调推进，起轮即清零
  private handle: GraphRunHandle | null = null;
  private stepSeq: number = 0;
  // 提交串行链（CAS expectedRevision 取号时序——见 commitOutputNode 注释；链只承载顺序，
  // 结果与异常由各调用方自己的承诺消费）
  private commitChain: Promise<void> = Promise.resolve();
  // ── 提问等待行登记表：toolCallId → 等待行 node id 承诺 ──
  // 挂起点（beginAskWaitRow）登记、结算点（commitToolNode）消费——ask 等待行落库后，其
  // 结算（答案到达）与中止（漏斗补写）**两条既有路径零特判**自动改走「更新既有等待行」
  //（不插第二行）；登记值 = 承诺（插入是异步的，结算可能早于其 resolve——commitToolNode
  // 先 then 等待行 id 再提交，与 commitChain 串行序共同保证「先插后更」）。消费即删
  //（callId 全局唯一）；表生命周期 = 本控制器实例（数据有界 = 每轮至多一条 ask）
  private askWaitRows: Map<string, Promise<string>> = new Map();

  // 内存行库身份回填（live 链原缺 rowSeq/nodeId——两者是压缩选段边界、请求裁剪与摘要采用
  // 核验锚的判据，缺则图会话**未离页**时压缩恒不可用、采用必报「路径已变化」、重试锚定位
  // 失败）。回填值来自本域提交回读的节点引用（节点引用唯一来源在此）。消费方三处：起轮
  // user 行（ChatSendCtrl）+ 终答行（ChatStreamFlowCtrl）+ 中间轮行（commitRoundAssistant）
  static stampNodeRef(msg: ChatMessage | null, ref: GraphNodeRef | null): void {
    if (msg === null || ref === null) {
      return;
    }
    if (ref.seq >= 0) {
      msg.rowSeq = ref.seq;
    }
    msg.nodeId = ref.nodeId;
  }

  // 路由镜像只读（宿主分流判据：graph 才走图写路径——'blocked' 与未装载 '' 皆 false）
  isMode(): boolean {
    return this.route === ROUTE_GRAPH;
  }

  // 路由只读口（graph/blocked/未装载 ''；'blocked' = 旧格式墓碑/不可用——宿主早退判据，
  // 须在占位气泡 push 前拒发，见 ChatSendCtrl.dispatchSend。名带 State 后缀避开与字段
  // route 同名——ArkTS 禁成员同名）
  routeState(): string {
    return this.route;
  }

  // 路由探针：页面加载链读到的路由与本域**同判据**（ChatContextSource.
  // conversationWritableRoute），随手同步进镜像——宿主发送闸的同步读在页面打开即拿到真值。
  // 只接受两个已知路由值，其余（含未装载 ''）一律丢弃 = 镜像宁缺勿错；不写 branchId
  //（分支恒由 loadRoute 装载，本口只服务「是否可写」的同步判据）
  publishRouteProbe(route: string): void {
    if (route === ROUTE_GRAPH || route === ROUTE_BLOCKED) {
      this.route = route;
    }
  }

  // 当前分支只读（重试 fork 的源分支；'' = 非图态）
  branch(): string {
    return this.branchId;
  }

  // 运行句柄快照（宿主收尾域在 releaseRun 前取值——账本归属与终态收口用）
  handleSnapshot(): GraphRunHandle | null {
    return this.handle;
  }

  // 图路由装载（消费**纯读路由口** conversationWritableRoute，自持「无行即出生」一步；
  // sessionOverride = 无行会话的内存覆盖——出生建行时随 ensureConversation 落覆盖三列，
  // 有行会话调用方恒传 null）。序：路由读（纯判定）→ blocked 早退 → 分支读 → 无分支 =
  // 未出生 → 出生即 graph → 落镜像。异常一律 fail-closed 落 'blocked' 拒写（态读失败 =
  // 判据不可靠，禁当可写放行）；分支读仅在 'graph' 下进行，失败同样置 'blocked'。
  // branchId 只在 'graph' 下非空。
  loadRoute(conversationId: string, assistantId: string,
    promptId: string, sessionOverride: ConversationOverride | null = null): Promise<void> {
    return conversationWritableRoute(conversationId)
      .catch((_e: Object): string => ROUTE_BLOCKED)
      .then((route: string): Promise<string> => {
        this.route = route;
        if (route !== ROUTE_GRAPH) {
          // blocked：无可写图分支——不读分支口（blocked 态读到的分支不可信）
          this.branchId = '';
          return Promise.resolve('');
        }
        return conversationGraphBranch(conversationId)
          .catch((_e: Object): string => {
            this.route = ROUTE_BLOCKED;
            return '';
          });
      })
      .then((branchId: string): Promise<string> => {
        if (this.route !== ROUTE_GRAPH) {
          this.branchId = '';
          return Promise.resolve('');
        }
        if (branchId !== '') {
          this.branchId = branchId;
          return Promise.resolve(branchId);
        }
        // 路由 graph 而分支为空 = 库里无该会话行（未出生）——出生即 graph（写入触发；出生
        // 失败/并发他口已出生让位 → fail-closed 归 blocked，下次装载自愈重试）
        return bornGraphConversation(conversationId, assistantId, promptId, sessionOverride)
          .then((born: string): string => {
            if (born === '') {
              this.route = ROUTE_BLOCKED;
              return '';
            }
            this.branchId = born;
            return born;
          })
          .catch((_e: Object): string => {
            this.route = ROUTE_BLOCKED;
            return '';
          });
      })
      .then((branchId: string): void => {
        // 分支为空的「graph 态」不可写图（无活跃路径）——二值化：该态归 blocked 拒写
        //（F3 的「图态空分支 fail-closed」同口径）
        this.branchId = branchId;
        if (this.route === ROUTE_GRAPH && branchId === '') {
          this.route = ROUTE_BLOCKED;
        }
      })
      .catch((_e: Object): void => {
        // 兜底（理论不达：三段 catch 已就地分流）——异常一律 fail-closed
        this.route = ROUTE_BLOCKED;
        this.branchId = '';
      });
  }

  // 发送起轮（prepareRun 原子提交 user 事实 + 附件 refs 建链）——成功置句柄清步序并回
  // user 节点引用（宿主据此回填 user 内存行 rowSeq/nodeId）；失败上抛由宿主呈报（不具开流
  // 资格）。★ 换 handle 前先排空提交链（契约见 drainCommitChain——上一轮终答提交与
  // setSending(false) 同拍入队，用户立刻开新轮时若先换 handle，在队旧笔执行时被判「已换轮」
  // 误作废，回答重进消失）。queueItemId = 排队派发载荷贯通（prepareRun 单事务内 DELETE
  // send_queue_items WHERE id = ?——出队删行与 user 事实同一事务，库中永无 inFlight 歧义行；
  // 缺省 '' = 手动/重试路径逐字零变化）
  beginSend(input: PrepareRunInput, attachRows: MessageAttachmentRow[],
    queueItemId: string = ''): Promise<GraphSendStart> {
    this.activeConversationId = input.conversationId;
    // Q3 消费位：事务删行入参（随 input 下传 prepareRun——非空 = 本轮由队列出队派发）
    this.pendingQueueItemId = queueItemId;
    input.queueItemId = queueItemId;
    return this.drainCommitChain()
      .then((): Promise<GraphSendStart> => graphBeginSend(input, attachRows))
      .then((start: GraphSendStart): GraphSendStart => {
        this.handle = start.handle;
        this.stepSeq = 0;
        return start;
      });
  }

  // 提交链排空（换轮点〔beginSend/beginRetry 换 handle 前〕调用）：resolve 时链上既有提交
  // 全部结算完毕，使 commitOutputNode 的「换轮作废」判据（this.handle !== captured）只对
  // 真跨轮笔生效。链自身吞结果吞异常，本口恒不抛。契约（禁死锁）：链内执行体只有
  // graphCommitNode 等命令调用，不回调本域、不再入队，故排空恒有界
  drainCommitChain(): Promise<void> {
    return this.commitChain;
  }

  // 输出节点提交（节点 id 返回——账本挂靠；revision 推进在句柄内）。★ 提交串行化：CAS 的
  // expectedRevision 取自句柄，而 revision 自增在提交 resolve 之后——同一同步窗口内连发多笔
  // 提交（并行工具轮收尾 for 循环按调用序连发、串行 lane 与助手收尾同刻）会全部读到同一个
  // 旧 revision，第二笔起被 CAS 拒（affected≠1 回滚）→ 节点永久不入库（重进会话工具卡消失、
  // 只在当场内存可见）。此处以承诺链串行化：下一笔的 revision 读取必然发生在前一笔 resolve
  // 之后，落库序 = 提交序。四个可选参（默认值 = 既有调用逐字零变化）：
  // · nodeStatus（默认 'done'）——'streaming'（MSG_STATUS_STREAMING）= 流中占位行落库；
  // · updateNodeId（默认 ''）——非空 = 收口走「更新既有占位行」路径（终值覆写升级 done）；
  // · runStatusOnCommit（默认 RUN_STATUS_RUNNING）——等待行落库传 RUN_STATUS_AWAITING_INPUT
  //  （插行与 run 停留态同事务原子落定）；
  // · updateNodeIdPromise——等待行**更新**的节点 id 以承诺形态**同步入链**：承诺于链内兑现
  //  （插入提交是链上更早之节恒先完成，无环），节点序位在入链当刻定格恒排在轮收口提交与
  //   finishRun 之前，CAS 不再失配（旧实现经 waiting.then 推迟一个微任务——停止/放弃/超时
  //   漏斗下轮收口提交恒抢先，finishRun 推进 revision 后更新 CAS 失配整笔回滚、等待行滞留
  //   streaming 跨重启复活为不可作答等待卡）
  private commitOutputNode(role: string, content: string, reasoning: string,
    stepIndex: number, nodeStatus: string = 'done',
    updateNodeId: string = '',
    runStatusOnCommit: string = RUN_STATUS_RUNNING,
    updateNodeIdPromise: Promise<string> | null = null): Promise<GraphNodeRef | null> {
    const captured: GraphRunHandle | null = this.handle;
    if (captured === null) {
      return Promise.reject(new Error('图运行句柄未建立，无法提交节点'));
    }
    // 会话 id 快照（B10：提交链执行体异步运行，会话取值随 captured 同款入队时定格）
    const convIdAtCommit: string = this.activeConversationId;
    const run: Promise<GraphNodeRef | null> = this.commitChain.then(async (): Promise<GraphNodeRef | null> => {
      // R1：承诺形态节点 id 在链内兑现（'' = 等待行未落成——退化为插行老路，同域⑤ 前语义）
      const updateId: string = updateNodeIdPromise !== null
        ? await updateNodeIdPromise : updateNodeId;
      if (this.handle !== captured) {
        // 排队期间已换轮（新 run 建句柄）——旧轮提交作废，不写进新 run 的 revision 序列
        return Promise.reject(new Error('图运行已更换，本轮节点提交作废'));
      }
      // 步序单调（run 内 1 起递增——同轮双提交〔assistant 收尾 + 工具节点〕不重号）；取号
      // 随链序执行，与落库序同序
      const step: number = Math.max(this.stepSeq, stepIndex) + 1;
      this.stepSeq = step;
      // ★ 节点 createdAt 走单调分配器 nextRowCreatedAt——裸 Date.now() 在系统时间回拨时产出
      // 逆因果序时间戳，图域导出快照按 createdAt ASC 排序、导入按序增量校验父存在性，
      // 子先父后 = 整会话被判悬边拒收（数据导不回）
      const committedAt: number = nextRowCreatedAt();
      return graphCommitNode(captured, role, content, reasoning, step, committedAt,
        ORIGIN_SEND, nodeStatus, updateId, runStatusOnCommit)
        .then((ref: GraphNodeRef | null): GraphNodeRef | null => {
              // ★ 图写链提交即推进列表时间契约（写侧唯一路径）；ref === null（CAS 冲突未
              // 落库）不推；失败 hilog 留痕不打扰（列表时间为展示面，提交本体已成功）
          if (ref !== null) {
            touchConversationUpdatedAt(convIdAtCommit, committedAt)
              .catch((e: Object): void => {
                hilog.warn(0x0001, 'ChatGraphWrite', '会话列表时间推进失败：%{public}s',
                  (e as Error).message);
              });
          }
          return ref;
        });
    });
    this.commitChain = run.then((): void => undefined, (): void => undefined);
    return run;
  }

  // 流中占位行落库（ChatStreamCheckpoint 域经宿主委托消费）：插 assistant 占位行
  // status='streaming'（content/reasoning = 落行时刻最新快照，首拍即带量——少一次写），走
  // commitChain 串行（与工具节点提交共链保序）。成功返回节点 id（域件记住供后续 checkpoint
  // 与收口）；失败/换轮作废上抛由调用方吞（占位行未落 = 收口自然走插行老路，不破坏收口）。
  beginStreamPlaceholder(content: string, reasoning: string): Promise<string> {
    return this.commitOutputNode('assistant', content, reasoning, 0, MSG_STATUS_STREAMING)
      .then((ref: GraphNodeRef | null): string => ref !== null ? ref.nodeId : '');
  }

  // 流中占位行 checkpoint：单行覆写 + 防迟到复活守卫（false = 行已终态，调用方丢弃快照）。
  // 不走 commitChain（无 CAS 无 revision，守卫谓词自保护，串行排水在 ChatStreamCheckpoint 域件）
  checkpointStreamPlaceholder(nodeId: string, content: string,
    reasoning: string): Promise<boolean> {
    return graphCheckpointNode(nodeId, content, reasoning);
  }

  // 图轮收尾（宿主 finishStream 消费）：终答节点提交 → run 终态（幂等）→ 账本
  // recordUsageEvent（requestId = runId 去重，重复回调幂等跳过）。返回落库节点 id（供宿主
  // 触发标题/建议），null = 提交冲突/无句柄；异常不吞（上抛由宿主呈报）。
  // input.placeholderNodeId 非空时终答提交走「更新既有占位行」（不另插新行）；'' 走插行老路
  finishRound(input: GraphFinishInput): Promise<GraphNodeRef | null> {
    const handle: GraphRunHandle | null = this.handle;
    if (handle === null) {
      return Promise.resolve(null);
    }
    return this.commitOutputNode('assistant', input.content, input.reasoning, 0,
      'done', input.placeholderNodeId)
      .then((ref: GraphNodeRef | null): Promise<GraphNodeRef | null> => {
        // v64 服务端工具补列（S2⑥）：提交成功才有 ref（CAS 冲突/失败天然不写）；伴随写
        // 失败 hilog 留痕不阻断轮收尾（touchConversationUpdatedAt 同款「提交后伴随写」先例
        // ——insert 与「更新既有占位行」两路径统一按 ref.nodeId 补列）。
        // ★ 2026-11-14 自检报告 §4.3 修：原 fire-and-forget 不 await——「收尾 → 用户立刻
        // 退出重进」的读窗可能早于 UPDATE 落库（这一次步骤行/来源卡不显示，再进即好）。
        // 现等补列落库再放行 finishRun（多一次 UPDATE 的毫秒级代价，换读窗确定性）
        if (ref === null || input.serverTools === undefined || input.serverTools === '') {
          return Promise.resolve(ref);
        }
        return writeNodeServerTools(sharedRdbStore(), { nodeId: ref.nodeId,
          serverToolsJson: input.serverTools })
          .then((): GraphNodeRef | null => ref)
          .catch((e: Object): GraphNodeRef | null => {
            hilog.warn(0x0001, 'ChatGraphWrite', '服务端工具列补写失败：%{public}s',
              (e as Error).message);
            return ref;
          });
      })
      .then((ref: GraphNodeRef | null): Promise<GraphNodeRef | null> =>
        graphFinishRun(handle, input.runFinalStatus === RUN_STATUS_FINISHED,
          input.diagnostic, input.runFinalStatus)
          .then((): GraphNodeRef | null => ref))
      .then((ref: GraphNodeRef | null): GraphNodeRef | null => {
        if (input.promptTokens > 0 || input.completionTokens > 0) {
          graphRecordUsage({
            conversationId: input.conversationId,
            messageId: ref !== null ? ref.nodeId : '',
            providerId: input.providerId,
            modelId: input.modelId,
            promptTokens: input.promptTokens,
            completionTokens: input.completionTokens,
            totalTokens: input.promptTokens + input.completionTokens,
            durationMs: input.durationMs,
            firstTokenMs: input.firstTokenMs,
            cachedTokens: input.cachedTokens,
            // 二期 #7：计次随账本行落库（'' = 无计次）——漏这处 = 值永远进不了账本
            serverToolsUsage: serverToolUseJsonOf(input.serverToolUse),
            purpose: 'chat',
            runId: handle.runId,
            attemptId: input.attemptId,
            branchId: handle.branchId,
            requestId: handle.runId,
            createdAt: Date.now()
          }).catch((e: Object): void => {
            // 账本写失败 hilog 留痕不打扰对话链（对照 legacy 路 insertUsageEvent 同位口径）
            hilog.warn(0x0001, 'ChatGraphWrite', '图轮账本落库失败：%{public}s',
              (e as Error).message);
          });
        }
        return ref;
      });
  }

  // 中间轮 assistant 节点提交（ChatToolRoundCtrl.settleRoundAssistant 快照；null = 无行可
  // 回填）：提交成功（ref 非空）经 stampNodeRef 单点回填该行库身份；ref 为 null（CAS 拒）
  // 或链拒绝时不回填、不伪造 seq/nodeId，行对象零触碰。placeholderNodeId 非空 = 中间轮
  // 占位行收口走「更新既有占位行」（快照取自 StreamSettlement.checkpointNodeId）。
  // ★ v64 服务端工具补列（S2⑥）：提交口从 stampTarget.serverToolsJson 读（快照先挂内存行
  // 再提交——提交与内存行同源），ref 非 null 且值非空才写（伴随写失败 hilog 留痕不阻断）
  commitRoundAssistant(content: string, reasoning: string,
    stepIndex: number, stampTarget: ChatMessage | null,
    placeholderNodeId: string = ''): Promise<boolean> {
    return this.commitOutputNode('assistant', content, reasoning, stepIndex,
      'done', placeholderNodeId)
      .then((ref: GraphNodeRef | null): Promise<boolean> => {
        ChatGraphWriteCtrl.stampNodeRef(stampTarget, ref); // ref 为 null 时 no-op（stampNodeRef 守卫）
        const serverToolsJson: string = stampTarget !== null &&
          stampTarget.serverToolsJson !== undefined ? stampTarget.serverToolsJson : '';
        if (ref === null || serverToolsJson === '') {
          return Promise.resolve(ref !== null);
        }
        // ★ 2026-11-14 自检报告 §4.3 修：补列 await 后才放行本轮（同 finishRound 口径——
        // 中间轮收尾后紧邻退出重进的读窗不再可能早于 UPDATE）
        return writeNodeServerTools(sharedRdbStore(), { nodeId: ref.nodeId,
          serverToolsJson: serverToolsJson })
          .then((): boolean => true)
          .catch((e: Object): boolean => {
            hilog.warn(0x0001, 'ChatGraphWrite', '中间轮服务端工具列补写失败：%{public}s',
              (e as Error).message);
            return true; // 补列失败不阻断提交成功的本轮（原语义保留）
          });
      });
  }

  // 工具结果节点提交（串行 lane / 并行收尾 / 中止漏斗消费，经宿主薄委托）：落库走
  // serializeToolRecord 五键白名单——record 的内存字段（mediaParts 的 base64）挡在库外。
  // ★ 本调用是 ask 等待行**两终结路**的汇聚点——登记表命中（本 toolCallId 的等待行在场）
  // 时改走「更新既有等待行」：答案到达（串行 lane 结算）与轮中止（persistAbortedCards 补写）
  // 自动升级既有等待行为终态，**不插第二行**；不命中走既有插行路径逐字零变化。更新路径同
  // 经 commitOutputNode/commitChain（与等待行插入同链保序）且 CAS 推进 revision——run 同拍
  // 写回 running（续跑语义：等待已结束、轮继续；边界 = 仅当更新先于轮收口提交与 finishRun
  // 落库时成立，链序恒保证）。等待行未落成（落库失败/CAS 拒 → 承诺兑现 ''）→ 退化为插行
  // 老路（中途死亡无等待卡，收口不断链）
  commitToolNode(record: ToolEventRecord, stepIndex: number): Promise<boolean> {
    const waiting: Promise<string> | undefined = this.askWaitRows.get(record.toolCallId);
    if (waiting !== undefined) {
      this.askWaitRows.delete(record.toolCallId); // 消费即删（一调用一等待行）
      return this.commitOutputNode('tool', serializeToolRecord(record), '', stepIndex,
        'done', '', RUN_STATUS_RUNNING, waiting)
        .then((ref: GraphNodeRef | null): boolean => ref !== null);
    }
    return this.commitOutputNode('tool', serializeToolRecord(record), '', stepIndex)
      .then((ref: GraphNodeRef | null): boolean => ref !== null);
  }

  // 提问等待行落库（★ 解耦笔6 域⑤ 2026-10-16 新增公开口——ChatToolRoundHost 一格薄直通
  // 消费）：ask 挂起时插 tool 行 status='streaming'（与域② 占位行同构——「图态进行中行」
  // 两族之一）并把 run 置 awaiting_input（同一 CAS 事务原子：插行 + revision 推进 + 停留态，
  // 见 CommitUnitOutput.runStatus）；载荷 = serializeToolRecord 五键 JSON、toolCallId 为
  // **模型原始编号**（保真口径持久化点——跨重启续答回填时原样沿用，见 ChatAskResumeCtrl）。
  // 成功登记 callId → node id 承诺（结算/中止两路经 commitToolNode 消费改走更新路）；
  // 失败吞并回 ''（等答不阻断——退化语义见 commitToolNode 注释）。parent = 提交时 head、
  // head 前移全套复用既有插行路径（等待行即链上末节点）
  beginAskWaitRow(toolCallId: string, recordJson: string,
    stepIndex: number): Promise<string> {
    const p: Promise<string> = this.commitOutputNode('tool', recordJson, '', stepIndex,
      MSG_STATUS_STREAMING, '', RUN_STATUS_AWAITING_INPUT)
      .then((ref: GraphNodeRef | null): string => ref !== null ? ref.nodeId : '')
      .catch((e: Object): string => {
        hilog.warn(0x0001, 'ChatGraphWrite', '提问等待行落库失败：%{public}s',
          (e as Error).message);
        return '';
      });
    this.askWaitRows.set(toolCallId, p);
    return p;
  }

  // 续答 run 接管（★ 解耦笔6 域⑤ 2026-10-16 新增）：把库内既有 run（awaiting_input 经
  // 续答回填转 running）接进本域句柄位——此后本轮的节点提交（占位行插入/终答收口/工具
  // 结果）沿该 run 的 revision 序列与步序续号推进，finishRound/finishRun 零特判（续答
  // 即「同一 run 的下一段流」）。revision 由调用方传**回填 CAS 之后**的现值（回填提交
  // 经 graphCommitNode 已就地推进句柄自身 revision）；stepSeq 取库内本 run 最大 stepIndex
  // （防同 run 内步序重号——trace 排序与 stepIndex 列语义）。activeConversationId 供
  // 提交链的列表时间推进（B10 契约，与 beginSend 同源）
  adoptRun(runId: string, branchId: string, revision: number, stepSeq: number,
    conversationId: string): void {
    this.activeConversationId = conversationId;
    this.handle = { runId: runId, branchId: branchId, revision: revision };
    this.stepSeq = stepSeq > 0 ? stepSeq : 0;
  }

  // 工具事实：派发前意图（prepared 落行 + dispatch_intent）
  toolFactDispatch(runId: string, attemptId: string, name: string,
    argsJson: string): Promise<string> {
    return graphToolFactDispatchIntent(runId, attemptId, name, argsJson);
  }

  // 工具事实：结果确认 / 失败终态（factId 空 = 意图未落成，静默跳过）
  toolFactConfirm(factId: string, runId: string, attemptId: string, result: string,
    failed: boolean): Promise<void> {
    if (factId === '') {
      return Promise.resolve();
    }
    return graphToolFactAdvance(factId, runId, attemptId, '',
      failed ? 'failed' : 'result_confirmed', '', result).then((): void => undefined);
  }

  // 续写重开节点（状态置回 streaming；见命令层同注释）
  reopenNode(nodeId: string): Promise<boolean> {
    return graphReopenNode(nodeId);
  }

  // 续写起轮（二期 S4 #10）：不 fork（同一分支同一答案节点原地追加），为本轮新建 run 行
  // 以便账本去重不吞续写消耗。branchId 沿用当前分支；head 必须是目标节点（末条答案）——
  // prepareRetryRun 的一致性校验在此天然拦住「非末条续写」。返回 false = 起轮失败/非末条。
  beginContinue(conversationId: string, runId: string, assistantId: string,
    targetNodeId: string): Promise<boolean> {
    if (runId === '' || this.branchId === '' || targetNodeId === '') {
      return Promise.resolve(false);
    }
    const branchAtStart: string = this.branchId;
    this.activeConversationId = conversationId;
    return this.drainCommitChain().then((): Promise<GraphRunHandle> =>
      graphBeginContinue({
        runId: runId,
        conversationId: conversationId,
        branchId: branchAtStart,
        assistantId: assistantId,
        anchorNodeId: targetNodeId,
        now: Date.now()
      })).then((handle: GraphRunHandle): boolean => {
        this.handle = handle;
        this.stepSeq = 0;
        return true;
      }).catch((_e: Object): boolean => false);
  }

  // 重试替代分支起轮（K5/P4 拍板值：找锚 → forkBranch（旧路径不删）→ prepareRetryRun
  //（不新增 user 节点）→ 切 activeBranch → onBranchSwitched 回调（宿主切数据源路径锚与
  // 分支镜像）。返回 false = 锚点缺失/起轮失败（调用方呈报降级）
  // ★ 2026-09-26 自检位B 修复（live 链身份不同源）：live 消息 id（nextMessageId('msg')）与
  // 图节点 id（命令层铸造）不同源，按目标 id 上溯查不到行——原实现直接判失败，图会话未离页
  // 时重试键恒报「未找到重试锚点」（离页重进走回放链 id = 节点 id 才成功）。此处补回退：
  // 目标 id 查不到时按「该轮重试 = 末条答案所在轮的 user 锚」语义从分支 head 上溯（★ 2026-10-25
  // rik 形态统一笔：目标恒为某条已收尾答案、其所属轮 user 锚唯一，两法同解）
  beginRetry(conversationId: string, runId: string, assistantId: string, targetMsgId: string,
    onBranchSwitched: (branchId: string) => void): Promise<boolean> {
    if (runId === '' || this.branchId === '') {
      return Promise.resolve(false);
    }
    const sourceBranch: string = this.branchId;
    this.activeConversationId = conversationId;
    return walkRetryAnchor(targetMsgId)
      .then((anchor: string | null): Promise<string | null> =>
        anchor !== null ? Promise.resolve(anchor)
          : walkLatestUserAnchor(sourceBranch))
      .then((anchor: string | null): Promise<boolean> => {
        if (anchor === null) {
          return Promise.resolve(false);
        }
        // ★ 换 handle 前先排空提交链（2026-09-26 自检位B 修复 B5——契约见 drainCommitChain
        // 注释；与 beginSend 同款）
        return this.drainCommitChain().then((): Promise<GraphRunHandle> => graphBeginRetry({
          runId: runId,
          conversationId: conversationId,
          branchId: sourceBranch,
          assistantId: assistantId,
          anchorNodeId: anchor,
          now: Date.now()
        })).then((handle: GraphRunHandle): boolean => {
          this.handle = handle;
          this.stepSeq = 0;
          this.branchId = handle.branchId;
          onBranchSwitched(handle.branchId);
          return true;
        });
      })
      .catch((_e: Object): boolean => false);
  }
}
