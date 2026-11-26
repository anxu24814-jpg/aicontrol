// 聊天页加载与刷新编排域（域级最小拆分自 ChatPage，方法体原样搬迁行为不变；@State 写经
// refs 回调）。
// · reloadConn：连接 = resolveActiveConnection 四级兜底链解析（会话页所选 > 会话所属助手
//   绑定 > 全局默认 > 首个启用模型，中途不停——本域先查会话行归属助手〔口径与注入链
//   ChatPromptState 一致〕再传入）；全链落空写 errorText 覆盖层（不静默）。
// · loadHistory：会话消息只读拉取 → 数据源一次性重建 + 进页直达底部末条（jumpToBottomAt，
//   原 scrollEdge 回底见 ChatFollowController 注释）；失败写 errorText。rebuild 不等全会话
//   用量账本——安装先行上屏，账本异步到位经 @Observed 原地补挂（attachUsageMeta 头注释）；
//   历史页触摸预载已全件退役，进页一律走本全量读库链（单一路径）；★ U1 装载链退出取消闸
//   （省算不防写，闸语义与检查点清单见类头取消闸注释；kill 开关 =
//   Theme.HISTORY_LOAD_CANCEL_GATE_ENABLED 默认关 = 现行为零变化）。重建后链式装配附件简报
//  （attachBriefsFor——按 id 归并赋值，气泡渲染面），loadOlder 前插批同链装配。本链兼受限态
//   会话呈报单点——态读结果落 dataSource.blockedNotice（'' = 非受限态），该态只有一义 =
//   旧格式墓碑（覆盖层无重试键）。
// · refreshPage：错误覆盖层「重试」动作（唯一消费方——「更多·刷新」项已退役）——清错误态 +
//   DB 就绪守卫 + 重读连接 + 重拉历史；未就绪跳过读库，保持「初始化失败」提示原样。
// · loadOlder（触顶翻页）：路径锚沿 parent 链前查一页更早消息 → dataSource.prependMessages
//   头部前插；到底（空页/短页）置 olderExhausted 终止翻页（有界）；失败 toast + 上抛
//   （ChatOlderCtrl 据此跳过锚点恢复）。触发/锚点/防抖在 ChatOlderCtrl，提示行 UI 在
//   ChatPageContent。前插批随批补一次账本读（轮级模型名补缺——首载窗外旧轮头行不回落
//   会话当前模型名）。
import { AiConnection } from '../../common/providers/AiTypes';
import {
  ConversationOverride, MessageRow, QUERY_TAIL_LIMIT, queryAttachmentsForMessages,
  queryConversationOverride
} from '../../common/store/ChatDb';
// ★ A1 读库合并笔：三旧口符号（conversationGraphBranch / conversationHasRow /
//   conversationWritableRoute）随级①~③收并从本文件退役，换融合口
import { conversationLoadRoute, ConversationLoadRoute, readPathPageRows,
  ROUTE_BLOCKED, ROUTE_GRAPH } from '../../common/chat/ChatContextSource';
import { TOMBSTONE_NOTICE_TEXT } from '../../common/chat/ChatBranchPolicy';
import { chatMessagesFromRows, PathAnchorCursor } from './ChatMessageProjection';
// 诊断通知行合成（读路径合成轻路线的安装面）
import { newChatMessage } from './ChatMessageCompose';
import { ChatDisplayHistory, DisplayRoundBatch } from './ChatDisplayHistory';
import { applyRoundModelLabels, DisplayRoundFacts } from './ChatDisplayProjection';
import { MessageAttachmentRow } from '../../common/store/AttachmentDb';
import { briefsFromRows } from '../../common/AttachmentUtil';
import { queryUsageByConversation, UsageEventRow } from '../../common/store/UsageStatsDb';
// 进页转场窗信号（掉帧修复刀④：用量账本补挂发起错峰出转场窗）
import { chatTransitionDefer } from './ChatTransitionHold';
// 二期 #7：计次列串解析（零依赖叶子，与写侧 serverToolUseJsonOf 对称）
import { addServerToolUseJson, parseServerToolUseJson } from '../../common/providers/SseParser';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ASSISTANT_DEFAULT_ID, queryConversationAssistantId } from '../../common/store/AssistantDb';
import { ActiveConnectionInfo, resolveActiveConnection } from '../../common/store/ProviderDb';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage } from './ChatMessageCompose';
import { ChatFollowController } from './ChatFollowController';
import { ChatListAnchorJudge } from '../../common/chat/ChatListAnchorJudge';
// ★ 改二：进页定位单步的现读谓词（与 List .stackFromEnd 同式同源——单一来源 = common/Theme 常量）
import { CHAT_STACK_FROM_END_ENABLED } from '../../common/Theme';
// U1 装载链退出取消闸 kill 开关（false = 检查点全部直通 = 现行行为）
import { HISTORY_LOAD_CANCEL_GATE_ENABLED } from '../../common/Theme';
import { markEnterProbe } from './ChatEnterProbe';
import { loadConversationSuggestions } from '../../common/SuggestGen';

// 蒙层首屏就绪兜底（★ 2026-10-18 一次出现笔）：读库入口置假起算，到点无条件置真——
// 防「首个内容帧信号永不到」（帧注册异常/安装被取消）把蒙层卡死。一次性短定时器自清
const ENTRY_FIRST_SCREEN_FALLBACK_MS: number = 1000;

// 页面侧读写集（@State 写必须回页面经回调；普通引用直持有——ChatSendRefs 同款）
export interface ChatPageLoadRefs {
  // 数据源现读闭包（闭包化——重进重挂时页面 @State 换源到运行态实例，本域一律现读、
  // 不持旧实例）
  dataSource: () => ChatDataSource;
  follow: ChatFollowController;
  // U4 双态判定器：重建链复位面——reset 挂 jumpToBottomAt 同源时机（attachUsageMeta 内），
  // 条数闸同步出锚初值
  anchorJudge: ChatListAnchorJudge;
  dbReady: () => boolean;
  conversationId: () => string;
  // 连接解析结果回写（conn 普通成员）
  setConnInfo: (info: ActiveConnectionInfo | null) => void;
  setError: (text: string) => void;
  // 动作时错误提示（loadOlder 查询失败——消息流在场，errorText 覆盖层不适用，走 toast）
  toast: (message: string) => void;
  // 会话有效归属助手（四级兜底链②级输入；页面转发 = 面板覆盖 ?? 当前助手 ?? 默认助手——
  // 仅无行会话〔懒创建/隐私〕在归属行查询为 null 时消费；有行会话行走 DB 值不经此）
  effectiveAssistantId: () => string;
  // 无行会话的会话级覆盖：会话还没落行时用户在会话内改的模型选择只存页面内存，本处作
  // DB 回读不到的兜底；行存在 = DB 为准，本值不参与
  memoryOverride: () => ConversationOverride | null;
  // 流式追加缓冲复位（全量重建前清节流缓冲——实现 = ChatSendCtrl.resetAppendBuffer；
  // 本域不反向依赖发送域，经 refs 回调上行）
  resetAppendBuffer: () => void;
  // 写侧路由镜像探针（修复：发送入口的同步闸读写侧镜像，而镜像原本只由发送链自己装载
  //——页面刚打开时首次发送被按未装载值拒发）。本链读到的路由与写侧**同判据**
  //（routeFromFacts 单源），故随手报出：有行会话 = 读到的路由原样；无行（未出生）= 可写
  //（出生由写法入口触发的 born 原语）。实现由页面注入转发（本域与写侧各自零逻辑）
  publishRouteProbe: (route: string) => void;
  // 历史加载收尾通知：loadHistory 全链完成（成败两路都到，挂在 catch 之后）触发——会话页
  // 上下文圆环的确定性补算点（进页初算与 setConnInfo 重算都不等历史重建完成，reloadConn
  // 先完成时圆环停在仅固定开销的小值且再无刷新点；本点保证「历史就绪后必有一次重算」）。
  // 无消费方时零开销（同 onRoundSettled 形制）
  onHistorySettled?: () => void;
  // 前插翻页收尾通知：loadOlder 本批安装完成后触发——版本步进字段是按行运行时字段，前插
  // 批的新行对象须补一次全表重算，否则滚动翻出的旧回答/旧提问没有 ◀x/y▶ 入口（旧「其他
  // 回答」菜单项已退役，无第二入口可兜）。无消费方时零开销
  onOlderLoaded?: () => void;
  // 沙箱 filesDir（附件简报装配拼绝对路径用——相对路径红线只对入库生效，运行时渲染消费
  // 绝对路径；页面闭包现读 host context）
  filesDir: () => string;
  // 首屏就绪帧注册：装载安装提交后用页面 UIContext 排一帧，把 dataSource.entryFirstScreenReady
  // 置真（蒙层盖到首屏块就绪的退场判据）。页面注入 UIContext.postFrameCallback 薄包装；
  // 本域不直接持 UIContext
  postEntryFrame: (callback: () => void) => void;
}

export class ChatPageLoadCtrl {
  private refs: ChatPageLoadRefs;
  // 历史展示轮事实装配域：页面寿命读缓存 + 装载代次（防回填见 ChatDisplayHistory 头注释）；
  // 与数据源同页面寿命——数据源销毁释放链经注册的释放回调清本件索引/代次
  private history: ChatDisplayHistory = new ChatDisplayHistory();
  // ── ★ U1 页面寿命取消闸（kill 开关 = Theme.HISTORY_LOAD_CANCEL_GATE_ENABLED，默认
  //    false = 本闸整体不生效）──置位 = 本页已退出，装载残余链各检查点静默早退。
  // · 闸语义写死 = **省算不防写**：只让退出后仍在跑的白做段（装配/投影/重建/补挂）早退；
  //   防写职责仍在既有「代次 / 会话未变 / 未销毁」三问守卫——二者职责分离禁合并。
  // · 本 ctrl 每页新建（页面寿命件）：勿把闸提为模块级/静态（防误杀重进同会话的新页）。
  // · 取消对象 = loadHistory 历史装载残余链与补挂链（用量账本/附件简报/推荐问题）；
  //   **流式链 / 续流 reveal 三 Map / 发送链零接触**（U9 退页不断流红线）。已发出的 RDB
  //   查询无法中止（官方无取消语义）——省的是级间后续段。
  // · 双置闸点（幂等）：A = ChatPage.onBackPressed（主路径）；B = ChatPageLifecycle.leave
  //   （程序化 pop/replace 兜底）。不挂 onWillDisappear——该钩子被子页 push 覆盖也触发，
  //   会误杀「进会话→立即开子页」的装载链。
  // · 复位点 = onReShown 首部（转场取消回显）——复位 + 被截断的 fresh 装载重发。
  // · 显式 trade-off：置闸截断后 historyLoaded 停 false，打断后 5s 内重进同会话从 remount
  //   快路径变回退 fresh 全量链；kill 开关默认关即无此面
  private historyLoadCancelled: boolean = false;
  // 蒙层首屏就绪兜底定时器（-1 = 未起）。一次性，到点自清；页面销毁后至多白跑一次「置真」
  // 写入（数据源已无消费方，无害）
  private entryReadyFallbackTimer: number = -1;

  constructor(refs: ChatPageLoadRefs) {
    this.refs = refs;
  }

  // 展示态释放回调登记（公开方法：闭包化后构造期 refs.dataSource() 尚是页面占位实例、
  // 重进重挂换源在 enter 期发生，登记必须晚于换源；调用点 = ChatPageLifecycle.enter 紧随
  // ensureRuntimeState 之后。数据源 setDisplayDisposeHandler 保存单一回调；重进重挂时后页
  // 覆盖前页登记〔旧页 history 随页面对象回收〕）
  attachDisplayState(): void {
    this.refs.dataSource().setDisplayDisposeHandler((): void => {
      this.history.dispose();
    });
  }

  // ★ U1 置闸单源（双置闸点共用；幂等）。kill 开关关 = 不置位，全链检查点恒直通 = 现行行为
  cancelHistoryLoad(): void {
    if (HISTORY_LOAD_CANCEL_GATE_ENABLED) {
      this.historyLoadCancelled = true;
    }
  }

  // 蒙层首屏兜底定时器取消（★ 2026-11-18 D3 修复：成对释放——与 beginEntryFirstScreenWindow
  // 的 setTimeout 对称，释放点挂 leave）。防「进会话读库起挂 1s 兜底定时器 → 1s（5s 窗）内
  // 退页重进同会话 → 旧页定时器到点把 entryFirstScreenReady=true 写进仍被新页蒙层消费的
  // 运行态数据源」的迟到写（恰落安装后首个内容帧前 = 新页蒙层提前收起）。幂等（-1 = 无挂起
  // 恒短路）；调用点 = 本方法内（起新窗前清旧窗）与 ChatPageLifecycle.leave（退页收口）。
  // ★ 禁并入 cancelHistoryLoad——彼方法有 HISTORY_LOAD_CANCEL_GATE_ENABLED 开关门控（默认
  // 关），并入则清定时器被门控吞掉、成对释放落空（方案档 §8-12 门控吞并陷阱）
  cancelEntryReadyFallbackTimer(): void {
    if (this.entryReadyFallbackTimer !== -1) {
      clearTimeout(this.entryReadyFallbackTimer);
      this.entryReadyFallbackTimer = -1;
    }
  }

  // ★ U1 复位点（接线 = ChatPageLifecycle.onReShown 首部）：闸未置零动作直通；闸已置 =
  // 转场取消回显——复位闸，且本页 fresh 装载未完成时重发 loadHistory。未完成判据 = 运行态
  // 数据源 historyLoaded=false（被闸截断的链不会再推进）；重发经 beginLoad 代次重开，旧链
  // 完成面按代次作废（重入安全）。dbReady 守卫：库未就绪 = 进页 whenReady 链仍在途，
  // 由它落载，不重复发
  resumeHistoryLoadIfCancelled(): void {
    if (!this.historyLoadCancelled) {
      return;
    }
    this.historyLoadCancelled = false;
    if (!this.refs.dataSource().historyLoaded && this.refs.dbReady()) {
      this.loadHistory();
    }
  }

  // ★ U1 取消闸检查口（各检查点共用单行读法）：true = 本页已退出，检查点静默早退。
  // kill 开关关 = 恒 false（短路求值零开销）= 现行「防写不防算」逐字同
  private historyLoadAbandoned(): boolean {
    return HISTORY_LOAD_CANCEL_GATE_ENABLED && this.historyLoadCancelled;
  }

  // ★ U9 重进重挂装载入口（域③b）：运行时存在本会话运行态（含生成中与空闲存活两窗）时，
  // 页面**不重建历史**——运行态数据源即屏上真源（live 行对象仍在数组内：flushFrame 以
  // findMessage(liveAssistantId) 定位恒命中，reveal 三 Map 保留值即续流初值——重进不跳变
  // 不重播）。本路只做三事：①历史索引代次重开（loadOlder 沿当前代次复用）；②进页锚底定位
  //（锚**初值**已前移换源同拍；本路只剩 jump 定位半边，跟随态由新页 follow 实例重新初始化）；
  // ③历史收尾通知（上下文圆环确定性补算点）。守卫：运行态数据源尚无装载事实
  //（historyLoaded=false——建态即离页的极端窗口）→ 回退全量链（不装空气泡）
  remountLive(): void {
    const ds: ChatDataSource = this.refs.dataSource();
    if (!ds.historyLoaded) {
      this.loadHistory();
      return;
    }
    this.history.beginLoad(this.refs.conversationId());
    // ★ S1：本处既有 anchorJudge.reset(displayCount()) 已退役——换源同拍已按**全量口径**做
    //   同值 reset，anchored 在内容区首建前即结构性成立；此处再 reset 属重复（恒锚开态
    //   ALWAYS_ENABLED 下 reset 恒真、无降格面；关态 kill-switch 仍有 COUNT_GATE 条数闸。
    //   裁定「remountLive 旧行退役防重复 reset」）
    // ★ 改二：底锚开态进页定位单步直达 END（消「5 秒内重进」两段跳闪动）——谓词**调用点
    //   现读**（与 List .stackFromEnd 同式），禁读 follow.stackAnchored 字段（喂入随帧驱动，
    //   重进窗口可读过期值致修复静默落空）；anchored 初值已在换源同拍出锚（恒锚开态
    //   ALWAYS 恒真、关态回 COUNT_GATE 条数闸，见上 S1），换源到本点（whenReady 微任务）
    //   之间无复位写者、evaluate 只升格不降格
    // ★ S3：落点改喂 lastContentIndex() 单源口（含头部提示行挂载感知）——修 H3：重进保留
    //   翻页残值时头部行挂载、displayCount()-1 落点差 1（近底非末条）的精度损失；两口径
    //   并到同一读口
    this.refs.follow.jumpToBottomAt(ds.lastContentIndex(),
      CHAT_STACK_FROM_END_ENABLED && this.refs.anchorJudge.anchored);
    // 蒙层首屏就绪复位：生成中重进不读库、屏上内容原样在场——信号恒真（swap 复用数据源上
    // 可能残留上轮读库的假值，此处显式归真）
    ds.entryFirstScreenReady = true;
    if (this.refs.onHistorySettled !== undefined) {
      this.refs.onHistorySettled();
    }
  }

  // 连接配置自加载（push 即新实例）：先查会话行归属助手（三态——非 '' = 显式绑定；
  // '' = 内置默认助手；null〔懒创建新会话/隐私会话无行〕= 有效归属 =
  // refs.effectiveAssistantId，口径与注入链 ChatPromptState.load 完全一致），再查会话级
  // 覆盖（DB 值 ?? 无行时页面内存覆盖），最后交 resolveActiveConnection 四级兜底链解析；
  // 行查询失败降级 null = 走有效归属/内存覆盖（可用性优先——异常路径不阻断连接）；
  // 全链落空提示不静默
  reloadConn(): void {
    const cid: string = this.refs.conversationId();
    let rowOverride: ConversationOverride | null = null;
    queryConversationOverride(cid)
      .catch((): ConversationOverride | null => null)
      .then((ov: ConversationOverride | null): Promise<string | null> => {
        rowOverride = ov; // null = 无行（或读失败）→ 下面用页面内存覆盖兜底
        return queryConversationAssistantId(cid).catch((): string | null => null);
      })
      .then((rowId: string | null): Promise<ActiveConnectionInfo | null> => {
        const ownerId: string = rowId !== null && rowId !== '' ? rowId :
          (rowId === null ? this.refs.effectiveAssistantId() : ASSISTANT_DEFAULT_ID);
        const ov: ConversationOverride | null = rowOverride !== null ? rowOverride :
          this.refs.memoryOverride();
        return resolveActiveConnection(ownerId,
          ov !== null ? ov.modelProviderId : '', ov !== null ? ov.modelId : '');
      })
      .then((info: ActiveConnectionInfo | null): void => {
        this.refs.setConnInfo(info);
      })
      .catch((e: Object): void => {
        this.refs.setError('连接配置读取失败：' + (e as Error).message);
      });
  }

  loadHistory(): void {
    // 首屏加载面不消费成败（失败由 errorText 覆盖层呈报；runHistoryLoad 的成败布尔供
    // 换源面判定，本入口语义不变——恒吞、返回值丢弃）
    // 读库入口开启蒙层首屏就绪窗（蒙层盖到首屏块就绪）
    this.beginEntryFirstScreenWindow();
    this.runHistoryLoad();
  }

  // 蒙层首屏就绪窗开启（信号写点之一）：读库开始 → 置假（蒙层据此盖到首个内容帧）；
  // 1000ms 兜底无条件置真（帧信号丢失/安装被取消时不卡死蒙层）。另一写点 =
  // attachUsageMeta.rebuildAndMount 成功后的首个内容帧。reloadBranchPath 不经本入口
  //（切分支/重试换源不是进页，不牵动蒙层时序）
  // ★ 2026-11-17 加载相锚点后移笔：起手批次号先自增——蒙层相位门读它（> 0），起拍由它的
  // 数值翻转驱动（原时间轴自组件挂载起算，冷启动等 DB 就绪的整段空窗被误算成「加载中」，
  // 侧栏形态首页主区常驻 ChatPage 时启动必现假动画）
  private beginEntryFirstScreenWindow(): void {
    const ds: ChatDataSource = this.refs.dataSource();
    ds.entryLoadEpoch = ds.entryLoadEpoch + 1;
    ds.entryFirstScreenReady = false;
    // 在途旧窗先清（幂等单源——D3 修复笔把三行自清段提取为成对释放方法，行为等价）
    this.cancelEntryReadyFallbackTimer();
    this.entryReadyFallbackTimer = setTimeout((): void => {
      this.entryReadyFallbackTimer = -1;
      this.refs.dataSource().entryFirstScreenReady = true;
    }, ENTRY_FIRST_SCREEN_FALLBACK_MS);
  }

  // 当前分支路径重载（切分支与中途整轮重试切到替代分支后换源）：与 loadHistory 同一链
  //（Promise 面——重建完成后 settle，调用方按「先换源后起轮」次序消费，见
  // ChatRetryCtrl.retryAtGraph/ChatBranchCtrl.submitEdit）。返回值 = **成败可判**的
  // Promise<boolean>（false = 态读异常或历史读取失败，视图未换源）——调用方据此中止
  // 后续动作，屏上路径与库态静默分叉
  reloadBranchPath(): Promise<boolean> {
    return this.runHistoryLoad();
  }

  // 历史加载链（loadHistory 与 reloadBranchPath 共用单源；全链吞异常——失败写 errorText，
  // 不向调用方抛，故 Promise 不因异常 reject；返回成败：态读异常或历史读取失败 = false，
  // 调用方据此中止后续动作）。本链兼 blocked 会话呈报**唯一采样点**——态读结果落
  // dataSource.blockedNotice（'' = 非受限态），受限态覆盖层据此呈报（ChatPageContent）
  private runHistoryLoad(): Promise<boolean> {
    // 全量重建前复位追加缓冲（旧窗口增量作废 + 档位回快档）
    this.refs.resetAppendBuffer();
    const cid: string = this.refs.conversationId();
    // 展示轮事实装载代次开启（首载/手动刷新/分支换源同开新代次——清旧 run 索引，旧批异步
    // 结果按代次作废；loadOlder 沿本代次复用）
    const loadGen: number = this.history.beginLoad(cid);
    return this.loadFromDatabase(cid, loadGen);
  }

  // 全量读库链（进页唯一路径；预载退役后无「命中旁路」双形态）
  private loadFromDatabase(cid: string, loadGen: number): Promise<boolean> {
    let loadFailed: boolean = false;
    // 本批确已安装标记：assemble 回 null（代次失效/已销毁）、安装前置校验不过、主历史读取
    // 出错，任一发生即保持 false——链尾「重载成功」必须 = 无错 + 确已安装 + 代次仍有效
    //（假成功出口不得被回答切换链吃到）
    let installed: boolean = false;
    // 有行判据（呈报前置条件：无行 = 未出生新会话，正常空态不呈报）
    let hasRowHere: boolean = false;
    // 本链 blocked 呈报文案（'' = 不呈报；链尾统一写，见下）
    let blockedText: string = '';
    // 路由读：graph 会话沿当前分支 parent 链读尾部窗口（线性读路径已退役，无分支 = 无可读
    // 路径——空历史渲染，态读失败同路 fail-closed 置 loadFailed）；首开路由读 = **纯读
    // 路由口**（无副作用，旧格式会话不再迁移，读回 blocked 即呈墓碑）；无行 = 未出生——
    // 不调路由口直接渲染空历史。★ A1 读库合并笔：级①~③（存在查 + 路由口 + 分支查）收并
    // 为融合口 conversationLoadRoute 单查一次——无行/墓碑/正常各形态行为与探针/采样判据
    // 逐字同旧（A1 等价表五形态）
    let loadedBranchId: string = '';
    let loadedRows: MessageRow[] = [];
    return conversationLoadRoute(cid)
      .catch((e: Object): ConversationLoadRoute => {
        // A1 失败路径（禁静默）：态读异常呈报 errorText + loadFailed（换源面判败中止），返回
        // 兜底 plan 续链。兜底 plan 的 hasRow 位**必须取 true**——非库事实，是镜像旧②失败时刻
        // 有效态的路由工件（若写 false，下游探针原式 hasRowHere ? route : ROUTE_GRAPH 会错报
        // GRAPH，违「探针必发 BLOCKED」）；由此失败三要件（墓碑采样跳过 / 探针报 BLOCKED /
        // loadFailed 守卫跳级④落空 rows）全经下游原式自然达成——与旧②失败形态逐字同
        this.refs.setError('会话状态读取失败：' + (e as Error).message);
        loadFailed = true;
        const fallback: ConversationLoadRoute = { hasRow: true, route: ROUTE_BLOCKED, branchId: '' };
        return fallback;
      })
      .then((plan: ConversationLoadRoute): Promise<MessageRow[]> => {
        // ★ U1 取消闸检查点（采样与探针写前、分支读查询前）——页面已退出不采样不写路由
        // 探针不查分支，空 rows 直落级④（级④检查点再拦装配；原四级检查点收为两级，拦截
        // 边界等价——原三段串行查询已收并为单一不可中断查询段）
        if (this.historyLoadAbandoned()) {
          return Promise.resolve<MessageRow[]>([]);
        }
        hasRowHere = plan.hasRow;
        const route: string = plan.route;
        // 墓碑覆盖层采样（判据两件：**有行** + 路由 blocked；文案单源 = TOMBSTONE_NOTICE_TEXT
        //——重试不会改变结果）。读失败（loadFailed）不呈报——错误覆盖层优先，两分支不同时命中
        if (hasRowHere && route === ROUTE_BLOCKED && !loadFailed) {
          blockedText = TOMBSTONE_NOTICE_TEXT;
        }
        // 写侧路由镜像探针（见 refs 注释）：无行 = 未出生按可写报出（出生由写入触发），
        // 其余原样报出——发送入口的同步闸据此拿到与页面同步的真值
        this.refs.publishRouteProbe(hasRowHere ? route : ROUTE_GRAPH);
        // 主路由读已失败——不再读分支、不重建，旧屏幕原样保留（errorText 覆盖层在场）；
        // 空历史绝不装上覆盖旧屏（合法无行/旧格式墓碑不走本支，照常装空态）
        if (loadFailed) {
          return Promise.resolve<MessageRow[]>([]);
        }
        if (plan.branchId !== '') {
          loadedBranchId = plan.branchId;
          return readPathPageRows(cid, plan.branchId, null, QUERY_TAIL_LIMIT);
        }
        // 无分支 = 未出生 / 旧格式墓碑 / 坏库（fail-closed 空历史）
        return Promise.resolve<MessageRow[]>([]);
      })
      .then((rows: MessageRow[]): Promise<void> => {
        // ★ U1 取消闸检查点（装配与安装前）——白做段主段（轮事实装配/投影映射/重建绑定）
        // 在此砍断：已退出不装配不安装，静默直落链尾
        if (this.historyLoadAbandoned()) {
          return Promise.resolve();
        }
        // ★ 读败不装空史（「loadFailed 时不得安装空历史覆盖旧屏幕」）：失败链不装配、不重建
        //——旧屏原样保留。原实现失败链仍会拿空 rows 走装配重建，空历史装上覆盖旧屏（本守卫
        // 即该缺口收口；合法无行/旧格式墓碑 loadFailed 恒假，照旧装空态）
        if (loadFailed) {
          return Promise.resolve();
        }
        loadedRows = rows;
        // 本批轮事实装配（run 终态索引初载一次 + 本批 id→runId）；投影映射与安装收尾走
        // installLoadedBatch 单源；代次失效/已销毁回 null = 丢弃本批（不把旧批写进新分支）
        return this.history.assemble(rows, loadGen)
          .then((batch: DisplayRoundBatch | null): Promise<void> => {
            if (batch === null) {
              return Promise.resolve();
            }
            return this.installLoadedBatch(rows, batch,
              loadedBranchId !== '' ? { branchId: loadedBranchId,
                oldestNodeId: rows.length > 0 ? rows[0].id : '' } : null, loadGen)
              .then((ok: boolean): void => {
                installed = ok;
              });
          });
      })
      .catch((e: Object): void => {
        // ★ U1 取消闸检查点（错误通道）：页面已退出——不写 errorText（无消费者），静默吞
        //（链契约不向调用方抛不变）
        if (this.historyLoadAbandoned()) {
          return;
        }
        this.refs.setError('历史消息读取失败：' + (e as Error).message);
        loadFailed = true; // 换源面据本标记中止——本轮视图未重建完成
      })
      .then((): boolean => {
        // ★ U1 取消闸检查点（链尾·收尾写前）：不写 blockedNotice、不触发 onHistorySettled
        //（页面已走，圆环补算无消费者）；false = 本链未装载完成
        if (this.historyLoadAbandoned()) {
          return false;
        }
        // blocked 呈报单点写（置文案 / 其余路径清空——状态已收口或换会话时旧文案不留）。
        // 位次在 rebuild 之后：本链的 rebuild 分量（空历史）不改本字段，写在前会被截断
        this.refs.dataSource().blockedNotice = loadFailed ? '' : blockedText;
        // 收尾通知挂在 catch 之后 = 成败两路都到（见 refs.onHistorySettled 注释）
        if (this.refs.onHistorySettled !== undefined) {
          this.refs.onHistorySettled();
        }
        // 成败出口（loadHistory 丢弃本值，reloadBranchPath 的消费方据此中止后续动作）：
        // truth 三问——无主读取错误 + 本批确已安装 + 代次仍有效。assemble 回 null / 安装
        // 被拒 / 主历史读错任一路径恒 false（旧屏幕保留）
        return !loadFailed && installed && this.history.isCurrent(loadGen);
      });
  }

  // 装配批安装与补挂单源（全量读库链与翻页链共用）：degraded 中性 toast → 投影映射（含
  // displayRoundId 回填，attachUsageMeta 不再二次无参映射）→ attachUsageMeta（安装先行
  // 上屏 + 用量异步补挂）→ 附件/建议补挂。返回 installed（安装前置校验三问任一不过 =
  // false，旧批不写新屏）
  private installLoadedBatch(rows: MessageRow[], batch: DisplayRoundBatch,
    pathAnchor: PathAnchorCursor | null, loadGen: number): Promise<boolean> {
    // ★ U1 取消闸检查点（装配入口·两链共用单源）：投影映射与降级 toast 都在退出后属白做/
    // 无消费者——已退出整段不进，直接回 false（下游补挂随 installed=false 天然跳过）
    if (this.historyLoadAbandoned()) {
      return Promise.resolve(false);
    }
    let installed: boolean = false;
    if (batch.degraded) {
      // 失败中性呈报（每次加载最多一次；正文加载不受影响，不设 errorText）
      this.refs.toast('部分处理状态读取失败，可刷新重试');
    }
    const msgs: ChatMessage[] = chatMessagesFromRows(rows, batch.roundIdByMsgId);
    this.appendDiagNotices(msgs, batch, false);
    return this.attachUsageMeta(rows, msgs, batch.facts, pathAnchor, loadGen)
      .then((ok: boolean): void => {
        installed = ok;
        // 附件简报装配（链在 attachUsageMeta 之后 = 重建必然已完成，findMessage 按 id 命中
        // 新消息，竞态零面）；装配失败在方法内 hilog 留痕不阻断（附件泡缺席即标注回退显示）
        // 附件/建议补挂仅在「确已安装 + 同代次有效」时执行——旧批的补挂不得落到新分支/
        // 新会话的新屏上
        if (installed && this.history.isCurrent(loadGen)) {
          this.attachBriefsFor(rows);
          // 回放链推荐问题装配（attachBriefs 先例同位——读会话行 suggestions 列挂末条助手
          // 消息；重建已完成，按 kind 倒序定位无竞态）；loadOlder 前插批不挂（显示面只有末条）
          this.attachSuggestionsFor();
        }
      })
      .then((): boolean => installed);
  }

  // 诊断通知行合成安装（LB-4③ 读路径合成轻路线）：装配层（ChatDisplayHistory.assemble 的
  // diagNotices）在本批轮末条消息之后插入 kind='notice' 合成行——id = 诊断节点 id（稳定，
  // 重装幂等去重键）、与实时 notice 同形态（不落库、经 buildRequestHistory 的 notice 跳过
  // 不入请求组装面、不进检索/统计面——三面口径天然对齐，零 DB 链改动）。prepend（触顶
  // 翻页前插）两道守卫：①轮已延伸到已安装的新消息（跨页轮——末条在新页，本批不插，由含
  // 末条的批次负责）；②同 id 行已在屏（防御）。tail 是整面重建（替换全集），无跨页问题
  // 恒插（本批含该轮消息才插——roundIdByMsgId 未命中的轮留给含它的批次）
  private appendDiagNotices(msgs: ChatMessage[], batch: DisplayRoundBatch, prepend: boolean): void {
    if (batch.diagNotices.length === 0) {
      return;
    }
    const ds: ChatDataSource = this.refs.dataSource();
    for (const notice of batch.diagNotices) {
      if (prepend && (ds.findMessage(notice.noticeId) !== null ||
        this.roundOnScreen(notice.roundId))) {
        continue;
      }
      let lastIdx: number = -1;
      for (let i: number = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].displayRoundId === notice.roundId) {
          lastIdx = i;
          break;
        }
      }
      if (lastIdx < 0) {
        continue; // 本批无该轮消息——合成料留给含该轮消息的批次
      }
      const row: ChatMessage = newChatMessage(notice.noticeId, 'notice', notice.content);
      if (msgs[lastIdx].createdAt !== undefined) {
        row.createdAt = msgs[lastIdx].createdAt; // 轮末同刻（消息时间头同源口径）
      }
      msgs.splice(lastIdx + 1, 0, row);
    }
  }

  // 轮消息是否已上屏（appendDiagNotices 的 prepend 守卫——跨页轮判定）
  private roundOnScreen(roundId: string): boolean {
    const onScreen: ChatMessage[] = this.refs.dataSource().allMessages();
    for (const m of onScreen) {
      if (m.displayRoundId === roundId) {
        return true;
      }
    }
    return false;
  }

  // 历史回放安装与用量补挂（U4a 拆序：用量查询移出首屏关键路径）。现序 = **先同步安装上屏**
  //（rebuild + 进页定位，不等任何账本查询），账本异步到位后按 id 原地补挂——补挂走既有刷新
  // 通道（@Observed/@ObjectLink 对象级观察驱动渲染，坑16 正解——禁 @Prop、禁自建广播键）。
  // ★ 补挂锚定止损：补挂内容全落**高度恒定槽位**——用量键落消息底栏 FinalOpsBar（常高行）、
  // 轮级模型名落轮头行（头像 32vp 定高、模型名单行省略）——补挂不改任何展示项行高 ⇒
  // 底锚/贴顶锚定不受扰动（「进会话首屏锚定后无可见跳动」为真机验收项）。
  // 显示口径：按 messageId 取最后一条事件（升序遍历覆盖，后写胜出）——重试后显示最新值；
  // 统计页与费用页照旧全量求和（账本语义）。账本查询失败静默降级不挂载（展示增强不阻断，
  // hilog 留痕）。loadGen 入参与 Promise<boolean> 返回值——安装前置校验（代次仍有效 / 会话
  // 未变 / 数据源未销毁）通过且确实调用 rebuild 才回 true；缺用量 ≠ 切换失败（安装照常回 true）
  private attachUsageMeta(rows: MessageRow[], msgs: ChatMessage[],
    facts: DisplayRoundFacts[], pathAnchor: PathAnchorCursor | null,
    loadGen: number): Promise<boolean> {
    const cid: string = this.refs.conversationId();
    const rebuildAndMount = (): boolean => {
      // ★ U1 取消闸检查点（rebuild 前置）：页面已退出——重建属白做段，静默返回 false。
      // **省算不防写**：防写职责在下三行「代次/会话未变/未销毁」三问守卫，闸只让白做链
      // 早退——二者职责分离禁合并（闸失效时三问守卫仍兜底防写）
      if (this.historyLoadAbandoned()) {
        return false;
      }
      // 安装前置校验（同代次三问）：任一不成立即不安装——旧批不得写进新分支/新会话，旧屏
      // 幕原样保留（disposed 后同样不回填，异步批不得写回已释放展示态）
      if (!this.history.isCurrent(loadGen) ||
        this.refs.conversationId() !== cid || this.refs.dataSource().isDisplayDisposed()) {
        return false;
      }
      // 一次性重建（映射已在上层完成；graph 窗口走 rebuildFromMessages 带路径锚与轮事实。
      // 思考块合成在投影件内）
      this.refs.dataSource().rebuildFromMessages(msgs, rows.length < QUERY_TAIL_LIMIT,
        pathAnchor, facts);
      // 进页初始定位直达底部末条（原 forceToBottom 的 scrollEdge 有「布局漂移跳滚」与
      //「竞态停顶」两面，见 ChatFollowController.jumpToBottomAt 注释）；refreshPage 复用本链
      // 同点到达。下标空间 = **展示项**（段占一位；数据源 IDataSource 契约同层，见 ChatDataSource）
      // U4 双态复位（jumpToBottomAt 同源时机、同链同 tick）：条数闸同步出锚初值、不等行高
      // 回报；老会话长历史 rebuild 同帧径直底锚（组B 进页定位红线：禁「先顶对齐再翻底锚」
      // 中间态），短老会话贴顶 + END 对齐钳位无感；★ 2026-11-25 恒锚笔：开态 reset 恒真，
      // 本处不产生翻档
      this.refs.anchorJudge.reset(this.refs.dataSource().displayCount());
      // 同 remountLive 口径——底锚开态单步直达 END（谓词调用点现读，理由见彼处注释）；
      // S3：落点同喂 lastContentIndex() 单源口——本链 rebuild 后 olderAttempted=false 头部行
      // 不挂载，补偿位恒 0 = 与原 displayCount()-1 逐字同值（改喂只为两调用点同口径单源）
      this.refs.follow.jumpToBottomAt(this.refs.dataSource().lastContentIndex(),
        CHAT_STACK_FROM_END_ENABLED && this.refs.anchorJudge.anchored);
      // U0 观测（纯 hilog 零行为）：fresh 安装点入时轴——A 场景主口径 = tap→install
      markEnterProbe('install');
      // 蒙层首屏就绪（信号写点之二）：安装提交后的首个内容帧置真——首屏块已出帧，蒙层据此
      // 退场。代次守卫：帧回调迟到时已换批/换源则不写（数据源现读，旧批不污染新屏）
      this.refs.postEntryFrame((): void => {
        if (this.history.isCurrent(loadGen)) {
          this.refs.dataSource().entryFirstScreenReady = true;
        }
      });
      return true; // 确已安装（回答切换链的「重载成功必须是真的」判据之一）
    };
    // ① 同步先行上屏（首屏关键路径不再等账本）
    const installed: boolean = rebuildAndMount();
    if (installed) {
      // ② 用量 meta 异步补挂：全会话账本查完经原通道落地；失败静默降级（正文已在屏，
      // 缺的只是用量与轮级模型名，下次刷新重试）。★ 掉帧修复刀④：发起错峰出转场窗（补挂
      // 落常高槽不改行高——U4a 契约在案，晚到不可见）；已出窗立即执行，现行为不变
      chatTransitionDefer((): void => {
        // 窗内退出守卫（省发起；落地段三问守卫照旧兜底）
        if (this.historyLoadAbandoned()) {
          return;
        }
        queryUsageByConversation(cid)
          .then((events: UsageEventRow[]): void => {
            // ★ U1 取消闸检查点（补挂链·用量账本入口）：页面已退出——逐消息原地写用量属
            // 白做，静默跳过（三问守卫仍兜底；查询本身无法中止，省的是落地段）
            if (this.historyLoadAbandoned()) {
              return;
            }
            // 补挂前置校验（同代次三问，与安装同口径）：代次已换/会话已变/已销毁 = 旧批不写新屏
            if (!this.history.isCurrent(loadGen) ||
              this.refs.conversationId() !== cid || this.refs.dataSource().isDisplayDisposed()) {
              return;
            }
            this.applyUsageEvents(events, this.refs.dataSource().allMessages());
          })
          .catch((e: Object): void => {
            hilog.warn(0xD5A0, 'ChatPageLoad', '回放用量账本补挂失败（正文不受影响，无用量显示）：%{public}s',
              (e as Error).message);
          });
      });
    }
    return Promise.resolve(installed);
  }

  // 用量事件落地（补挂半边）：批量事件按 messageId **跨轮求和**（升序遍历累加；同一
  // messageId 多行 = 续写每轮一行账本——费用两笔不重复、气泡显示整条答案合计，决明
  // 2026-11-14 拍板「两轮和」；首字耗时是时点量取第一段非零值不累加）
  // → findMessage 按 id 定位原地赋值（@ObjectLink 对象级观察驱动刷新——禁止按下标，思考块
  // 合成使消息序与行序不对应）；轮级模型名经账本 modelId → 轮 id 映射写全（首载写全态
  // onlyMissing = false）。只写 @Observed 字段、不触发任何滚动/定位调用——补挂高度恒定
  // 口径见 attachUsageMeta 头注释
  private applyUsageEvents(events: UsageEventRow[], msgs: ChatMessage[]): void {
    const byId: Map<string, UsageEventRow> = new Map();
    for (const ev of events) {
      const prev: UsageEventRow | undefined = byId.get(ev.messageId);
      if (prev === undefined) {
        byId.set(ev.messageId, ev);
        continue;
      }
      // 同一 messageId 的第二行起累加（续写跨轮）：数值四项求和、首字取第一段非零、
      // 计次串两轮相加（空串/坏串按 0）
      prev.totalTokens += ev.totalTokens;
      prev.completionTokens += ev.completionTokens;
      prev.durationMs += ev.durationMs;
      prev.cachedTokens += ev.cachedTokens;
      if (prev.firstTokenMs <= 0) {
        prev.firstTokenMs = ev.firstTokenMs;
      }
      prev.serverToolsUsage = addServerToolUseJson(prev.serverToolsUsage, ev.serverToolsUsage);
    }
    byId.forEach((ev: UsageEventRow, msgId: string): void => {
      const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
      // 二期 #7：计次行可能 token 全零（只有 service 计次）——挂载判据并上计次串
      if (msg !== null && msg.kind === 'assistant' &&
        (ev.totalTokens > 0 || ev.serverToolsUsage !== '')) {
        msg.usageTokens = ev.totalTokens;
        msg.usageCompletionTokens = ev.completionTokens;
        msg.usageDurationMs = ev.durationMs;
        // 首字耗时：>0 才挂（升级前的存量账本行 DEFAULT 0 = 无该指标天然不显示；零噪声口径）
        if (ev.firstTokenMs > 0) {
          msg.usageFirstTokenMs = ev.firstTokenMs;
        }
        // 缓存命中段：>0 才挂（undefined 即不渲染）；历史行 DB 默认 0 = 升级前的存量轮次
        // 天然无段（表自 v26 起新记缓存）
        if (ev.cachedTokens > 0) {
          msg.usageCachedTokens = ev.cachedTokens;
        }
        // 官方服务端工具计次（二期 #7）：非空串才挂；坏串/全零由解析纯函数回 undefined
        //（不挂键 = 气泡不出三行）
        const use = parseServerToolUseJson(ev.serverToolsUsage);
        if (use !== undefined) {
          msg.serverToolUse = use;
        }
      }
    });
    // 轮级模型名回填（空 modelId 与未归属轮在映射内天然跳过——头行回退会话当前模型名广播键）
    applyRoundModelLabels(msgs, this.roundModelFromEvents(events), false);
  }

  // 账本事件 → 轮级模型名映射（两消费方 = 首载写全 / 翻页补缺）：byId 升序遍历覆盖 = 同消息
  // 取末条（重试产生同消息第二条事件 = 最新消耗与最新模型名，与用量装配同口径）；modelId 空
  // 跳过；事件消息须已加载方能定位轮 id（未加载 = 该轮不该批在列，天然跳过）
  private roundModelFromEvents(events: UsageEventRow[]): Map<string, string> {
    const byId: Map<string, UsageEventRow> = new Map();
    for (const ev of events) {
      byId.set(ev.messageId, ev);
    }
    const roundModel: Map<string, string> = new Map();
    byId.forEach((ev: UsageEventRow, msgId: string): void => {
      if (ev.modelId === '') {
        return;
      }
      const src: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
      if (src !== null && src.displayRoundId !== '') {
        roundModel.set(src.displayRoundId, ev.modelId);
      }
    });
    return roundModel;
  }

  // 翻页批轮级模型名补缺（S-2 修复：前插批装配链不含账本读取 ⇒ 首载 QUERY_TAIL_LIMIT 窗
  // 之外的旧轮 modelLabel 恒空、轮头回落会话当前模型名，切过模型的会话上滑旧页即见错标）。
  // 补一次同源账本读，**只补缺**写 modelLabel（onlyMissing——不覆盖实时链自铸值与前批已写
  // 值；不动用量面 = 旧页无用量属既有口径），不触发滚底/校正（原地 @Observed 写）。扫全量
  // 在列消息：跨界轮（user 行在本批、头行承载在已加载部分）一并补。失败静默降级；异步完成
  // 面复核代次/会话/销毁三问（防旧批写进新源——与 attachUsageMeta 安装前置校验同口径）
  private backfillOlderRoundLabels(loadGen: number): void {
    const cid: string = this.refs.conversationId();
    queryUsageByConversation(cid)
      .then((events: UsageEventRow[]): void => {
        if (!this.history.isCurrent(loadGen) || this.refs.conversationId() !== cid ||
          this.refs.dataSource().isDisplayDisposed()) {
          return;
        }
        applyRoundModelLabels(this.refs.dataSource().allMessages(),
          this.roundModelFromEvents(events), true);
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatPageLoad', '旧页轮级模型名补缺失败（头行回落会话模型名）：%{public}s',
          (e as Error).message);
      });
  }

  // 回放链附件简报装配（loadHistory 与 loadOlder 共用）：收集批内 user 行 id（空集短路零
  // 查询）→ 查附件行 → 按 messageId 归并 → **按 id 定位**（禁按下标——思考块合成使消息序
  // 与行序不对应）原地赋值 attachBriefs（@Observed/@ObjectLink 对象级观察驱动气泡渲染）。
  // 装配只在加载链一次完成，build 内零查询零 I/O（性能红线 + 坑57）；失败 hilog 留痕不阻断
  //（附件泡缺席即标注回退显示）。本方法是回放侧唯一写点（send 链写点在 ChatSendCtrl）
  private attachBriefsFor(rows: MessageRow[]): void {
    // ★ U1 取消闸检查点（补挂链·附件简报入口）：页面已退出——简报查询与装配属白做，
    // 静默早退（缺席即不渲染，展示增强不阻断语义不变）
    if (this.historyLoadAbandoned()) {
      return;
    }
    const ids: string[] = [];
    for (const row of rows) {
      if (row.role === 'user') {
        ids.push(row.id);
      }
    }
    if (ids.length === 0) {
      return;
    }
    queryAttachmentsForMessages(ids)
      .then((attachRows: MessageAttachmentRow[]): void => {
        if (attachRows.length === 0) {
          return;
        }
        const byMsg: Map<string, MessageAttachmentRow[]> = new Map();
        for (const attachRow of attachRows) {
          const list: MessageAttachmentRow[] | undefined = byMsg.get(attachRow.messageId);
          if (list !== undefined) {
            list.push(attachRow);
          } else {
            byMsg.set(attachRow.messageId, [attachRow]);
          }
        }
        const filesDir: string = this.refs.filesDir();
        byMsg.forEach((list: MessageAttachmentRow[], msgId: string): void => {
          const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
          if (msg !== null && msg.kind === 'user') {
            msg.attachBriefs = briefsFromRows(list, filesDir);
          }
        });
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatPageLoad', '附件简报装配失败（气泡退标注回退显示）：%{public}s',
          (e as Error).message);
      });
  }

  // 回放链推荐问题装配（loadHistory 专用——loadOlder 前插批不挂）：读会话行 suggestions 列
  //（解析单落点 SuggestGen.loadConversationSuggestions）挂到末条助手消息（**按 kind 倒序
  // 定位，禁按下标**——思考块合成使消息序与行序不对应，attachBriefsFor 同款纪律）；
  // @Observed 对象级观察驱动渲染。空串/解析空 = 不挂（undefined 即不渲染）；失败 hilog
  // 留痕不阻断。隐私会话无行恒回 ''，零特判；发送清空后 '' 同不挂
  private attachSuggestionsFor(): void {
    // ★ U1 取消闸检查点（补挂链·推荐问题入口）：页面已退出——建议读取与挂载属白做，
    // 静默早退
    if (this.historyLoadAbandoned()) {
      return;
    }
    loadConversationSuggestions(this.refs.conversationId())
      .then((items: string[]): void => {
        if (items.length === 0) {
          return;
        }
        const all: ChatMessage[] = this.refs.dataSource().allMessages();
        for (let i = all.length - 1; i >= 0; i--) {
          if (all[i].kind === 'assistant') {
            all[i].suggestions = items;
            break;
          }
        }
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatPageLoad', '推荐问题装配失败：%{public}s', (e as Error).message);
      });
  }

  // 触顶翻页查询（ChatOlderCtrl.tryLoadOlder 上行）：空页/短页 = 到底置 olderExhausted
  //（此后触顶不再查询——有界）；失败 toast 呈报并上抛（调用方跳过锚点恢复，滚动位置本就
  // 不动）
  loadOlder(): Promise<void> {
    const ds: ChatDataSource = this.refs.dataSource();
    // 路径翻页：游标携分支与锚点节点，沿 parent 链向根取一页；seq 游标在图会话不可用——
    // fork 共享前缀使 seq 序 ≠ 路径序。无路径锚 = 空历史/坏库态，不翻页
    if (ds.oldestAnchor() !== null) {
      const anchor = ds.oldestAnchor() as PathAnchorCursor;
      // 翻页沿当前装载代次复用（只查本批 id，不重查全量 run 索引；代次失效/已销毁时 assemble
      // 回 null ⇒ 本批整批丢弃不前插，防旧批写进新分支。接线前置保证翻页入口以
      // oldestAnchor 非空为门槛〔首载装配完成前不可达〕，正常路径恒有有效代次；防御性代次 0
      // 同走整批丢弃〔安全侧〕）
      const loadGen: number = this.history.currentGen();
      return readPathPageRows(this.refs.conversationId(), anchor.branchId,
        anchor.oldestNodeId, QUERY_TAIL_LIMIT)
        .then((rows: MessageRow[]): Promise<void> => {
          // 到底判定（空页/不足一页；与装配无关的原口径）
          if (rows.length < QUERY_TAIL_LIMIT) {
            ds.olderExhausted = true;
          }
          if (rows.length === 0) {
            return Promise.resolve();
          }
          // 先装配轮事实再前插（仅 reload 一次；附件、用量与 cancelAlign 顺序不变）
          return this.history.assemble(rows, loadGen)
            .then((batch: DisplayRoundBatch | null): void => {
              if (batch === null) {
                return; // 代次失效/已销毁——丢弃本批（不把旧批写进新分支）
              }
              if (batch.degraded) {
                this.refs.toast('部分处理状态读取失败，可刷新重试');
              }
              if (ds.isDisplayDisposed()) {
                return;
              }
              // 诊断通知合成（prepend 形）：跨页轮守卫见方法注释
              const olderMsgs: ChatMessage[] = chatMessagesFromRows(rows, batch.roundIdByMsgId);
              this.appendDiagNotices(olderMsgs, batch, true);
              ds.prependMessages(olderMsgs,
                { branchId: anchor.branchId, oldestNodeId: rows[0].id }, batch.facts);
              // 头部前插使列表项下标平移——进页待校正目标失真即取消（正常路径用户翻历史
              // 手势已先清，本行兜异常路径防校正链与翻页锚点互抢拽底）
              this.refs.follow.cancelAlign();
              // 本批前插消息的附件简报装配：同一查询面、另一批 id；prepend 同步完成，
              // 查询回来时按 id 命中前插消息
              this.attachBriefsFor(rows);
              // 旧页轮级模型名补缺（异步、不阻断翻页链，见方法注释）
              this.backfillOlderRoundLabels(loadGen);
              // 版本步进全表重算：前插批行对象为新构造，步进字段全空——不补算即旧回答/
              // 旧提问翻出来没有 ◀x/y▶
              if (this.refs.onOlderLoaded !== undefined) {
                this.refs.onOlderLoaded();
              }
            });
        })
        .catch((e: Object): void => {
          this.refs.toast('更早消息读取失败：' + (e as Error).message);
          throw e as Error;
        });
    }
    return Promise.resolve();
  }

  // 刷新：清错误态 + 重读连接 + 重拉历史；DB 未就绪时跳过读库动作（防「初始化失败」提示
  // 被「连接配置读取失败」覆盖——竞态修复守卫随迁）。原两条「手动重试口」动作随迁移机制
  // 退役删除——旧格式会话不再迁移，墓碑覆盖层不再提供重试键（重试不会改变结果）；本入口
  // 回归纯刷新语义，唯一调用方 = 错误覆盖层「重试」（「更多·刷新」菜单项已删）
  refreshPage(): void {
    this.refs.setError('');
    if (this.refs.dbReady()) {
      this.reloadConn();
      this.loadHistory();
    }
  }
}
