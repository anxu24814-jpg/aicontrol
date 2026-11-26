// 发送控制器生命周期收尾域（★ U8 解耦笔3·域③a 2026-10-16 自 ChatSendCtrl.ets 域级最小拆分
// 迁出——宪法 1200 硬线：ChatSendCtrl 剔头实测 1200 顶格，本笔「一族到达面」增行即越线
// （任务书 U8 节「净减形态走例外，否则拆出」条件命中），「生命周期收尾域」随运行时迁移
// 一并拆出；两法方法体与全部沿革注释自 ChatSendCtrl 逐字搬迁，行为零变化）。
// 域定义一句话：**发送控制器的生命周期收尾**——停止（abort）与销毁（disposeSilent）两条
// 终止路径的跨域编排单点（把终止事件按域分发：自动重试标记/退避取消、后台任务与本 run
// HTTP 定向掐断、重发域请停、流侧支三段、工具轮挂起取消、运行占用归还）；★ U10 域④
//（2026-10-16）增**第三条终止路径 timeoutInterrupt**（后台超时中断——终态 interrupted
// 的跨域分发裁剪，见下方方法注释）。
// · 为何不能并入既有件（反碎片下限②申报）：ChatStreamFlowCtrl 承接的是**流侧支**（两法的
//   tail 段早已迁彼件）；本件承接的是**编排侧**（四域件分发 + 宿主态读写），职责缝不同。
//   并回 ChatStreamFlowCtrl = 让流域反向持 autoRetry/resend/toolRound 三域引用与 disposed
//   写权（现为宿主专有），倒挂既有域边界。亦无其它同域既有件可并。
// · 与既有拆分史的衔接：2026-09-27 拆分笔已把「停止与销毁两路径的流侧支」迁 ChatStreamFlowCtrl；
//   本笔把两路径的编排残段（宿主内剩余部分）同样迁出，ChatSendCtrl 只余两行薄委托。
// · 宿主面（ChatSendLifecycleRefs，ChatSendCtrl 构造序末位直注——域名沿用宿主字段名，方法体
//   搬迁面最小化）：conversationId / activeRun / markDisposed（disposed 字段写权）/ releaseRun
//   四闭包 + autoRetry / resend / toolRound / flow 四域件引用。
// · 语义红线（随搬迁不动）：停止键先置轮内停止标记再动手（漏置则退避到点重发已停请求）；
//   后台任务连带取消按会话维度 + 本 run 豁免（页面销毁不连带——任务按设计活过页面）；
//   disposeSilent 不触发任何 finishStream（静默销毁链）；离页排空窗口先兑付再归还占用。
// ★ U9 解耦笔4·域③b（2026-10-16）调用面变更：**退页不再调 disposeSilent**（「退页静默
//   掐流」语义退役——退页改只解绑不掐流，见 ChatSessionRuntime.release/detachUi）；本方法
//   保留为**运行时空闲回收点的销毁链**（唯一调用方 = ChatSessionRuntime.reclaim，此刻恒
//   无在途生成——回收门 = 引用归零且非生成）。离页在途排空窗口不再需要本链兑付：运行时
//   跨页存活、排空沿节流时钟自然跑完（finishStream 照常收口落 done/diagnostic 空），
//   finishPendingDrain 保留为回收点兜底（此刻无排空态，恒零动作）。
// · disposeDisplayState 不再随本域（★ U8 起挂页面侧；★ U9 再迁）：数据源展示态释放改挂
//   运行时回收点（ChatSessionRuntime.reclaim 内紧随本销毁链之后）——退页不断流期间展示态
//   必须存活（重进重挂的前提），见 ChatDataSource.disposeDisplayState 注释。
import { httpAbortRun, httpAbortConversationBackground } from '../../common/providers/ToolHttp';
import { toolRuntime } from '../../common/providers/ToolRuntime';
import { RunIdentity } from '../../common/chat/MessageContracts';
import { ChatAutoRetryCtrl } from './ChatAutoRetryCtrl';
import { ChatToolResendCtrl } from './ChatToolResendCtrl';
import { ChatToolRoundCtrl } from './ChatToolRoundCtrl';
import { ChatStreamFlowCtrl } from './ChatStreamFlowCtrl';
import { clearContinueHandler } from '../../common/chat/ChatContinueSupport';

// 宿主面（ChatSendCtrl implements 位 = 构造序末位直注；四闭包持宿主态现读——sending/
// disposed/activeRun 等值语义与拆分前同源，禁在本件缓存任何宿主态）。
// ★ 成员形态 = 属性式函数类型（照 ChatHostAccess 先例——ArkTS 对象字面量须对应属性式接口）
export interface ChatSendLifecycleRefs {
  // 会话 id（后台任务定向取消与工具轮挂起取消的实参源）
  conversationId: () => string;
  // 本控制器活跃 run 身份现读（null = 无活跃轮）——两终止路径的定向实参源
  activeRun: () => RunIdentity | null;
  // 销毁闸置位（disposeSilent 首行；字段本体与全部读取方仍在 ChatSendCtrl）
  markDisposed: () => void;
  // 运行占用释放（先失效后释放的「释放」点；abort 不在此释放——停止收尾仍要经流 onError
  // 回来走 failRound，释放点提前会把停止主路径的收尾拦死，见原注释）
  releaseRun: () => void;
  // ── 四域件引用（跨域分发面——直注，构造期纯赋值 + 本件只可能在其后被调取）──
  // 自动重试域（轮内停止标记 / 在途退避取消）
  autoRetry: ChatAutoRetryCtrl;
  // 工具卡重发域（重发进行中 = 停止键属重发域）
  resend: ChatToolResendCtrl;
  // 工具轮域（挂起兜底取消 + 中止卡落库）
  toolRound: ChatToolRoundCtrl;
  // 流回调域（流侧支三段：abort 侧支 / 离页排空兑付 / 离页静默掐链）
  flow: ChatStreamFlowCtrl;
}

export class ChatSendLifecycleCtrl {
  private refs: ChatSendLifecycleRefs;

  constructor(refs: ChatSendLifecycleRefs) {
    this.refs = refs;
  }

  // 中止（M1 onStop 语义）：取钥间隙/工具轮执行期无活跃流时直接收尾（防间隙续传——用户已
  // 明确停止）。★ 2026-09-09 工具层自检修复：工具轮执行期 activeStream 曾指向已收尾的流
  // 对象，abort() 走 `activeStream.abort()` → ChatStreamBase.fail 的 finished 首行守卫
  // 静默空转 = 停止键在工具执行期间失效（联网工具 5~20s 窗口内点停止无任何反应，模型继续
  // 续轮扣费）。修法 = onStreamDone 收尾即置 null（流已终态，引用不再有用）——停止键落
  // 下方 failRound 分支，工具轮 lane 的停止守卫接住（卡片补已中止、不落库不续轮）。
  abort(): void {
    // ★ 2026-09-22 自动重试笔：置轮内停止标记 + 取消在途退避（域件 markUserStop，两句一体），
    // **必须早于下方任何收尾**——「已手动停止」与网络错误同为 -1，判据只靠该标记区分；漏置
    // 则退避到点会把用户已停止的请求又发出去
    this.refs.autoRetry.markUserStop();
    // ★ 2026-10-02 调研修复笔 #2（决明拍板 A）：停止键连带取消本会话仍在跑的后台长任务
    // ——后台任务挂发起轮 runId，发起轮结束后下方按本 run 定向掐断匹配不到它（原缺口
    // = 只能等任务超时），无其他取消入口；连带取消让「停止键即取消」承诺闭合。任务仍按
    // 各自发起轮 runId 精确掐断，分栏他会话不在查询面内不受连带；页面销毁（disposeSilent）
    // 不连带——后台任务按设计活过页面，重进会话可查结果
    //（宿主面读改写：活跃 run 一次快照——原 `this.activeRun` 字段两次连续读，本件经闭包
    // 现读快照同值，同步体无第二写者，语义逐字等价）
    const activeRunAtAbort: RunIdentity | null = this.refs.activeRun();
    httpAbortConversationBackground(this.refs.conversationId(),
      activeRunAtAbort !== null ? activeRunAtAbort.runId : '');
    // ★ 2026-10-01 重发件：重发进行中 = 停止键属于重发域——定向掐 HTTP（activeRun 即重发
    // run）+ 请停标记（执行回调按它归类中止载荷，不误报网络失败）+ 清本会话挂起确认（确认
    // 等待中无在途请求可掐——cancelAllPending 以 false 续跑人工卡链，回调按请停标记归类；
    // sending 闸保证本会话此刻唯一挂起 = 重发确认，分栏他会话不受影响）。重发不走流式，
    // failRound / abortActiveStream 的流式收尾不适用，提前返回
    if (this.refs.resend.isBusy()) {
      const runAtStop: RunIdentity | null = this.refs.activeRun();
      httpAbortRun(runAtStop !== null ? runAtStop.runId : '');
      this.refs.resend.requestStop();
      toolRuntime.cancelAllPending(this.refs.conversationId());
      return;
    }
    // 在途 http_request 立即掐断（2026-09-19 HTTP 请求工具笔）：destroy 在途 request →
    // promise 以错误结算 → 工具轮 lane 收尾守卫把卡转「已中止」（30s 读超时兜底口径见
    // ToolHttp 注释）。★ 2026-09-26 笔1 S4：改按本 run 定向取消（httpAbortRun，I11/V5）——
    // 分栏态他会话与本会话新 run 的在途不受连带；全量入口 httpAbortAll 保留给全进程退出
    const run: RunIdentity | null = this.refs.activeRun();
    httpAbortRun(run !== null ? run.runId : '');
    // 退避期的 activeStream 已被自动重试分支置空（见流回调域 onStreamError），停止键落
    // abortActiveStream 的 else 分支即时收尾（notice 行 + 输入栏回可发送态）——流侧支
    // 2026-09-27 随流回调域迁 ChatStreamFlowCtrl（原 if/else 判段与哨值注释随迁）
    this.refs.flow.abortActiveStream();
  }

  // ask_user 答案上行 / browse_act 确认上行留宿主（ChatSendCtrl.resolveAsk / resolveBrowseConfirm）

  // 后台超时中断（★ U10 解耦笔5·域④ 2026-10-16 第三条终止路径；前两条 = abort 停止 /
  // disposeSilent 销毁）：终态语义 = interrupted（非用户停止、非失败——域①四终态值域
  // 已开闸），与 abort 同族的跨域分发裁剪成超时所需三条：①在途 http_request 定向掐断
  //（工具轮立刻结算，不必等 30s 读超时）；②本会话后台长任务连带取消（同 abort 口径——
  // 「超时即取消」承诺闭合；进程即将被系统挂起，任务留着也活不过冻结）；③自动重试在途
  // 退避取消（防退避到点在冻结窗口重发已失控的请求）+ 工具轮挂起兜底取消（中止卡落库，
  // 同 failRound 漏斗）+ 流侧支静默掐断与 interrupted 收口（chatBgReply 超时回调链
  // 落点，见 ChatStreamFlowCtrl.interruptForTimeout）。**不置用户停止标记**（interrupted
  // 非 stopped——置了会把 run 层收口压成 stopped 语义）
  timeoutInterrupt(): void {
    const run: RunIdentity | null = this.refs.activeRun();
    const runIdAtTimeout: string = run !== null ? run.runId : '';
    httpAbortRun(runIdAtTimeout);
    httpAbortConversationBackground(this.refs.conversationId(), runIdAtTimeout);
    this.refs.autoRetry.cancelBackoff();
    this.refs.toolRound.abortRoundPending(this.refs.conversationId());
    this.refs.flow.interruptForTimeout();
  }

  // 页面销毁静默中止（红线：解绑回调防销毁后触 UI）；销毁闸拦住异步取钥续传（DB 残留
  // streaming 态由下次启动 markStreamingAsError 兜底转 error）
  disposeSilent(): void {
    this.refs.markDisposed();
    // 在途 http_request 同步掐断（离页不留悬挂网络请求）——★ 2026-09-26 笔1 S4：按 run
    // 定向（httpAbortRun，I11/V5），须在 releaseRun 前快照身份；全量入口 httpAbortAll 保留
    // 给全进程退出
    const activeRun: RunIdentity | null = this.refs.activeRun();
    const runIdAtDispose: string = activeRun !== null ? activeRun.runId : '';
    httpAbortRun(runIdAtDispose);
    // 收尾排空在途时先落终态（2026-10-12 RIK 第四笔笔三：离页不等 drain——终态收尾含
    // 落库须在 releaseRun 清运行身份之前完成，重进页从库回放全文；无在途排空零动作）
    this.refs.flow.finishPendingDrain();
    // 运行占用释放（2026-09-26 笔1 S2）：先失效（token 清空 + 探测面 false——离页后在途
    // 浏览队列任务出队即放弃）再归还
    this.refs.releaseRun();
    // 自动重试域取消（2026-09-22）：在途退避定时器成对释放（创建点 takeOver）——防销毁后
    // 定时器到点重发（守卫拦得住，但定时器本身不该悬着）
    this.refs.autoRetry.cancelBackoff();
    this.refs.toolRound.abortRoundPending(this.refs.conversationId()); // 挂起兜底取消（★ 09-24 D 只清本会话，分栏态他会话在途不连带）+ 中止卡落库（B 案 A，时机见域件头注释）
    this.refs.flow.disposeActiveStream(); // 流侧支 2026-09-27 随流回调域迁 ChatStreamFlowCtrl
    // 续写事件口注销（自检轮补，成对释放）：登记点在 ChatSendCtrl 构造期，销毁链在此清空
    //——模块级单例不长期持有已销毁控制器的闭包
    clearContinueHandler();
    // 展示态页面寿命释放（disposeDisplayState）★ U8 起不随本域——挂页面侧 leave()（紧随
    // release 之后 host.dataSource 直调；位次 = 全部停写者之后不变；IDataSource/LazyForEach
    // 消费契约与页面寿命释放语义留页面侧）
  }
}
