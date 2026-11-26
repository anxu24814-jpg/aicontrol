// 聊天消息数据源：LazyForEach 的 IDataSource 单一事实源 + @Observed/@Track messageCount
// 空态驱动（@Track 字段经 @ObjectLink 订阅驱动空态/错误态分支；键恒定 + 原地改字段 +
// @Observed→@ObjectLink 对象级观察刷新——稳定键拍板语义）。dshinhm 的 kap 支路（transcript
// 回放重建 / frameId 寻址增量 / retry 三方法等）全部不迁——aicontrol 数据流 = ChatDb 尾部查询
// 回放 + 页面侧 OpenAI 流式编排（appendThrottle/权威全量串在页面），本类只做容器 + 通知，
// 不生成 id（DB 消息 id 与视图 id 同源 nextMessageId，由页面统一生成）。
// 触顶翻页：prepend 前插支路 + 翻页态（olderLoading/olderExhausted
// @Track——头部提示行两态驱动）+ 路径翻页锚（seq 游标已退役，理由见 pathAnchor 注释；
// 消费方 ChatOlderCtrl / ChatPageLoadCtrl.loadOlder）。
// 通知语义（★ 过程段折叠笔改判）：结构变更（尾部追加 / 定位插入 / 头部前插 /
// 移除 / 换源重建）一律经展示项重建入口 refreshDisplay → **notifyReload 整体重载**（追加可能
// 合入末段，增量通知无法正确表达——原 notifyAdd 已退役）；原地改字段不通知（@Observed set
// 自驱动，键恒定 LazyForEach 无需重建——稳定键结论）。
// ★ 空态分层：「加载中」≠「空会话」——@Track historyLoaded 标记历史加载已
// 完成（rebuildFromHistory 置 true / clear 复位），空态引导层判定 = messageCount===0 且
// historyLoaded（ChatPageContent）；加载中显示纯背景，进页转场动画中不再闪现引导页。
// 数据有界：消息窗口受 QUERY_TAIL_LIMIT（50）+ 进行中回合上限约束；实例归运行态
// （生成寿命：退页不断流期间随运行态存活；引用归零且非生成经 5 秒空闲回收释放，见
// ChatSessionRuntime.reclaim）——无全局无界持有。
import { MessageRow, QUERY_TAIL_LIMIT } from '../../common/store/ChatDb';
import { chatMessagesFromRows, PathAnchorCursor } from './ChatMessageProjection';
import { ChatMessage, isAskAwaiting, isStepAwaitingUser } from './ChatMessageCompose';
import { renewMarkdownBindings, settleMarkdownBodies } from './ChatMarkdownState';
import { alignRoundStartTimes, buildDisplayItems, ChatDisplayItem, DISPLAY_KIND_SEGMENT,
  DisplayRoundFacts, installDisplayRoundFacts, registerDisplayRound, settleDisplayRoundFacts }
  from './ChatDisplayProjection';

// ★ cleanRoundResidue（末轮重试的内存整轮清扫）与
// RoundResidue 接口已随重试链收敛整段退役——现役唯一重试链 retryAt 走
// 「替代分支 + 路径换源重载」，旧答案与其派生行由整表重建移出，无需内存清扫原语。

@Observed
export class ChatDataSource implements IDataSource {
  // 消息总数（@Track 响应式字段，与 messages.length 恒等；空态/错误态分支判定经
  // @ObjectLink 订阅本字段——仅本类变更方法内写，外部只读）
  @Track messageCount: number = 0;
  // 历史加载完成标记（2026-09-06 空态分层）：false = 加载中（空态引导层不显示——进页
  // 首帧 messageCount===0 只代表「尚未加载」非「空会话」）；true = loadHistory 已成功
  // 回放（含空表——确认空会话后才显示引导层）。写点 = rebuildFromHistory 置 true（★ 订正
  // A-6：clear() 全仓无调用者，注释原记的「clear() 复位」写点不存在——换会话零残留由
  // 页面每会话重建承担）；loadHistory 失败路径不经（保持 false，与错误态分支互斥
  // 推演见 ChatPageContent 空态分支注释）
  @Track historyLoaded: boolean = false;
  // 进页装载起手批次号（2026-11-17 加载相锚点后移笔）：0 = 本实例尚无进页读库链起手——
  // **含冷启动等 DB 就绪的空窗，此窗不是「加载中」**，ChatLoadingOverlay 不得据此亮起；
  // 每次 loadHistory 起手 +1（beginEntryFirstScreenWindow 同拍自增）。写点唯一 =
  // ChatPageLoadCtrl.beginEntryFirstScreenWindow；消费 = 蒙层相位门（> 0）与起拍 Watch
  //（@Prop 数值翻转通道——用递增计数而非布尔：重试/取消恢复重发 loadHistory 时也必有变化，
  // 起拍不丢）；clear() 复位 0（★ 订正 A-6：clear 全仓无调用者，换会话复位由页面每会话
  // 重建承担）。★ @Track：本字段进 UI 判据（蒙层 build 读 + 内容区传参读），裸字段 UI 读
  // = 140110 雷（坑A1）
  @Track entryLoadEpoch: number = 0;
  // 蒙层首屏就绪信号：false = 本轮读库装载已提交但首屏内容
  // 尚未出帧——ChatLoadingOverlay 据此把蒙层盖到首屏块就绪（OFF 态渐进揭示不再「数据装好
  // 即退蒙层、随后干转圈逐块填」）。写点唯一两处（ChatPageLoadCtrl）：读库入口置假 +
  // 1000ms 兜底置真；安装提交后的首个内容帧置真。非进页态恒真（缺省 true——运行态复用
  // 的生成中重进不读库，remountLive 显式置真）。clear() 一并复位真。
  @Track entryFirstScreenReady: boolean = true;
  // 本地新造会话标记（2026-11-18 乐观空态笔）：true = 本页会话 id 由本地 nextMessageId
  // 生成（无行、必然空）——空态引导层可越过 historyLoaded 读库回执立即成立。为什么：
  // historyLoaded 唯一写点是读库链 rebuildFromMessages，「新会话是空的」在 id 生成那一刻
  // 已确定，却要等 DB 十步初始化 + 一次无行查询 + 一帧回调才被承认——这段空白即「一打开
  // 不是新会话」的观感来源。写点唯一 = ChatPageLifecycle.enter（每次进页按宿主 freshSession
  // 入参覆盖，重进已有会话自动归 false、零残留）；消费 = ChatPageEmptyLayer 空态分支 +
  // ChatLoadingOverlay 相位门（fresh 下空态已是终态，蒙层不得再盖）。★ @Track：进 UI 判据
  //（裸字段被 UI 读 = 140110 雷，坑A1 同族）
  @Track freshEntry: boolean = false;
  // 启动衔接标记（2026-11-24）：true = 本页是本次进程启动落点直接进入的会话页（标记由
  // HomeNavigation 在启动落点判定分支置位、ChatPageLifecycle.enter 一次性消费并读后清）
  //——空态层首帧即画与系统启动页同图同尺寸同中心的图标，DB 十步初始化与读库窗口不再是
  // 纯背景；内容结论（historyLoaded / 消息）到达后与消息区渐显同拍 300ms 淡出。运行期
  // 点会话卡进页恒 false（转场中不闪图标）。★ @Track：进 UI 判据（裸字段被 UI 读 =
  // 140110 雷，坑A1 同族）
  @Track launchHandoff: boolean = false;
  // 页面显示到达标：消息区渐显与壁纸错峰同事件源——
  // 唯一写点 = ChatPageLifecycle.onReShown（页面壳 onShown 链，与 PageBackground 的
  // bumpBgShownEpoch 同回调栈 = 同帧起播〔就绪早于显示时；就绪晚于显示则就绪即播、后于
  // 壁纸——★ 自检轮注释订正：原写「同帧起播」是乐观表述，三条件判据下装载
  // 慢场景为壁纸先行内容后到，非缺陷是数据到达顺序使然〕）；消费点唯一 = ChatPageContent
  // 消息区 opacity 判据（与 entryFirstScreenReady 同链 @ObjectLink 纯响应式，零新订阅面）。
  // pop 返回实例存活保持 true = 直显不重播；重挂复用运行态数据源同理（重进不跳变语义）。
  // ★ 坑A1 红线：本字段进 UI 判据（build 读取），必须 @Track——裸字段被 UI 读 = 140110
  @Track shellArrived: boolean = false;
  // 墓碑会话呈报文案（'' = 非墓碑态不呈报）：非 graph 会话
  // （旧格式 / 历史迁移残值 / graph 空分支坏库态）无可读路径——原
  // 静默落通用空态「开始新的对话」，观感如数据丢失。写点 = ChatPageLoadCtrl 加载链收尾
  //（置文案 / 其余路径清空；★ 订正 A-6：clear() 无调用者，复位实际只由加载链收尾写点
  // 承担）。文案单源 =
  // ChatBranchPolicy.TOMBSTONE_NOTICE_TEXT。通道 = @ObjectLink 订阅 @Track（与 historyLoaded 同
  // 链路驱动覆盖层分支；禁 @Prop——坑16 家族）
  @Track blockedNotice: string = '';
  // ── 触顶翻页态（@Track——头部提示行「加载更早…/已到顶」两态经
  // @ObjectLink 订阅驱动；写点 = ChatOlderCtrl（loading/attempted）与 rebuild 预判 +
  // ChatPageLoadCtrl.loadOlder（exhausted），rebuild/clear 复位——换会话/刷新重开翻页）──
  @Track olderLoading: boolean = false;
  // 到底标记：初始窗不足一页（< QUERY_TAIL_LIMIT）时 rebuild 预判（免触顶空查询、免
  // 加载行闪现——消息不足一屏触顶即无更多）；翻页查到空页/短页置位；到底后触顶不再查
  @Track olderExhausted: boolean = false;
  // 触达标记：用户至少触顶一次才显示「已到顶」行（防短会话进页即常驻提示行——预判
  // 已知到底但行等首次触达再亮，dshinhm 无此行的差异点）
  @Track olderAttempted: boolean = false;
  // ★ 进页暴露窗口整域已退役：一条消息 = 一个 ListItem，
  // 行级窗口拆不开单条长消息内部的块树；超长行已由「进页收起」处置，窗口的推迟对象消失。
  // 本类不再承载窗口态，totalCount/displayCount/getData 恒回全量口径。
  // 路径翻页锚（2026-09-26 笔3 K8：seq 游标在图会话不可用——fork 共享前缀使 seq 序 ≠
  // 路径序，翻页必须沿 parent 链。锚空 = 空历史/坏库态不翻页〔legacy seq 翻页支随 legacy
  // 退役笔3 线性读路径退役删除〕）
  private pathAnchor: PathAnchorCursor | null = null;
  // ── 屏幕已加载分支身份与换源代次 ──
  // 屏幕事实 ≠ 库默认事实：库 isActive 只代表下次加载的默认选择，本字段才是**当前屏上窗口
  // 所沿的真实分支**（回答面板当前勾、屏库分叉恢复消费它）。写点三处：①rebuildFromMessages
  // 安装完成同拍取 anchor.branchId（legacy 窗口/无锚 = ''）；②reanchorBranch（实时重试确已
  // 换数据源路径的时刻）；③markLoadedBranch（回答入口按真实目标节点验证后补建——限定规则
  // 见其注释，本类不验证不猜）。普通 refreshDisplay / token 原地写 / 前插翻页均不写。
  private loadedBranchId: string = '';
  // 路径视图代次（换源事实计数器）：一次 rebuild 安装推进一次（clear 与 reanchorBranch 也
  // 推进）——回答读链用它判「读图期间屏幕换过源」；与 run 装载代次（ChatDisplayHistory
  // generation）分工不同，禁混用。★ @Track（2026-10-24 闪退修复笔）：经 pathEpoch() 只读口
  // 会被 UI 上下文读到（follow 布局供应者闭包，List 属性链重算可拉起），@Observed 优化态下
  // 非 @Track 字段 UI 读 = 140110 硬错（真机 jscrash「Illegal usage of not @Track'ed
  // property 'pathViewEpoch'」）；写点均为低频重建路径，@Track 化零新增通知面
  @Track pathViewEpoch: number = 0;
  private listeners: DataChangeListener[] = [];
  private messages: ChatMessage[] = [];
  // ── 展示项层 ──
  // 「消息 → 展示项」投影结果：连续过程步骤合成一个过程段（独立展示项），其余消息各自一项。
  // **列表渲染消费本层**（IDataSource 契约 = 展示项；totalCount/getData 见下），源消息层
  // （messages / allMessages / messageCount）继续服务请求历史、空态判据与全部域写点——两层的
  // 数量恒不等（段折叠了多条步骤），禁互相替代。重建入口 = refreshDisplay（结构变更后调用，
  // 复用旧展示项对象 ⇒ 段键与手动展开态跨增量/翻页延续）；token 级文本更新不经本层
  //（@Observed 原地写自驱动，列表不重建）。★ @Track（闪退修复）：displayCount()/
  // lastContentIndex() 会在 UI 上下文被读（同 follow 供应者闭包），非 @Track 数组字段 UI 读
  // 同款 140110 雷；重建路径整体重赋值时通知与 messageCount/historyLoaded 同拍，零新增可见
  // 行为（数组元素级变更仍走 IDataSource 通知，本装饰不涉）
  @Track displayItems: ChatDisplayItem[] = [];
  // ── 轮事实表 ──
  // 展示轮（conversationId|runId）→ 事实。写点三路：实时 beginDisplayRound（登记 running）/
  // settleDisplayRound（转终态）/ 历史装配 installDisplayRounds（读缓存映射）。历史缓存与实时
  // 事实同表（同 id 时实时优先——installDisplayRounds 不覆盖已有项）；裁剪只挂删除入口
  // （removeMessageIds 完成后按成员引用剔除），不挂 push/insertBefore/
  // 普通 refreshDisplay（首发 begin 后先 push(user) 时新轮尚无在列成员，不能在该拍误删）。
  private displayRounds: Map<string, DisplayRoundFacts> = new Map();
  // 页面销毁闸（disposeDisplayState 置位后一切展示事实写入被拒——先停写者后释放）
  private displayDisposed: boolean = false;
  // 页面寿命释放回调（ChatPageLoadCtrl 构造时注册 history.dispose；disposeDisplayState 调完
  // 立即清引用，幂等）
  private displayDisposeHandler: (() => void) | null = null;

  // ┌──── IDataSource 实现（LazyForEach 契约 = 展示项层）────┐
  // ★ 索引语义变更点：本契约的下标是**展示项下标**（段占一位），凡 scrollToIndex / 锚点 /
  // 可见下标（ChatOlderCtrl、ChatFollowController、ChatPageLoad 进页定位）一律走本空间；
  // 源消息下标（messages 数组）只服务请求组装与域内逻辑，两者禁混用（任务书 §9.A.4）。
  totalCount(): number {
    return this.displayItems.length;
  }

  getData(index: number): ChatDisplayItem {
    return this.displayItems[index];
  }

  // 消息流只读全量（2026-09-01「回传历史思考」：ChatHistoryBuilder.buildRequestHistory
  // 输入源——纯函数组装请求历史（含 thinking→assistant reasoning 配对）；只读数组引用，
  // 消息对象本身 @Observed（流式原地改字段），读取不通知不改状态）。
  // ★ 2026-10-08：**恒回源消息全员**（含被折叠段隐藏的步骤、不上屏的空正文行）——请求历史、
  // 压缩选段、上下文用量都按真实历史算；折叠只是展示层，禁把本方法改成折叠后可见列表。
  allMessages(): ChatMessage[] {
    return this.messages;
  }

  // 展示项只读全量（渲染层诊断与断言直读用；语义同 displayItems 注释）
  allDisplayItems(): ChatDisplayItem[] {
    return this.displayItems;
  }

  // 进页折叠态复位：每次进入
  // 会话（swap 复用运行态并换源写回）把**助手与用户**两侧的手动展开意愿清回默认收起——
  // 运行态 5 秒回收窗内同一批 ChatMessage 对象会跨页复用，不清则上次展开的长行在重进时
  // 仍整棵物化，进页优化失效。同时按**进页时点**重算折叠标记：已终态（非流式）的行标记
  // 为 armed（覆盖 live=true 的运行态复用消息）；仍在流式或进页后新完成的行不标记，保持
  // 展开。展开中标记一并复位（防组件回收后残留静默位）。@Observed 原地写，在
  // replaceDataSource / 首建之前调用，无额外重渲。
  resetLongMessageExpansion(): void {
    for (const message of this.messages) {
      message.longMsgExpanded = false;
      message.bodyPlaceholder = false;
      // ★ 2128：输入位托管标记一并复位（进页/换源复位语义）。等待卡期间 busy 恒真，重进
      // 走 remountLive 复用同一批消息对象——上一页留下的 dockOwned=true 会让卡件认领守卫
      // 短路，而新页托管位初值 false，结果托管位与流内卡体双灭（「离页再进看不到卡」根因）。
      // 方案 §4.4「离页不回写标记」不变：复位在装载侧，不在离页侧
      message.dockOwned = false;
      if (message.kind === 'assistant') {
        message.longMsgCollapseArmed = message.streaming !== true;
      }
    }
  }

  // 展示项条数（进页直达底部末条定位、空态判据以外的下标运算用；源消息数用 messageCount）
  displayCount(): number {
    return this.displayItems.length;
  }

  // 全量口径只读口（窗口退役后与
  // displayCount() 同值，保留本口免动既有调用点）
  totalItemCount(): number {
    return this.displayItems.length;
  }

  // 头部提示行是否挂载（唯一判据，2026-10-22 展开钉顶笔自三处内联式收编）：本页 List 头部
  // if 条件、展示末条下标、展示项下标 → List 项位换算三处同源——头部行在场时展示项在 List
  // 项位整体 +1（新增第四处消费前先读本条）
  headerMounted(): boolean {
    return this.olderLoading || (this.olderExhausted && this.olderAttempted && this.messageCount > 0);
  }

  // 展示项下标 → List 项位（头部行感知；< 0 原样回 -1 = 未命中）
  listIndexForDisplay(displayIndex: number): number {
    if (displayIndex < 0) {
      return -1;
    }
    return displayIndex + (this.headerMounted() ? 1 : 0);
  }

  // 源消息 id → List 项位（展开钉顶的锚点行读取用：段级取段首步 id、步骤级取该步 id，
  // 两者都经 displayIndexOfMessage 落到所在段；未命中回 -1）
  listIndexForMessage(msgId: string): number {
    return this.listIndexForDisplay(this.displayIndexOfMessage(msgId));
  }

  // 展示末条下标（下标补偿单源）：含头部提示行感知——头部行
  // 挂载（olderLoading，或 olderExhausted×olderAttempted×非空）时展示项在 List 项位整体
  // +1，末条下标随之 +1；判据与本页头部行渲染条件（ChatPageContent List 头部 if）同源。
  // 空表回 -1（调用方按 < 0 自守——jumpToBottomAt 空表复位语义原样）
  lastContentIndex(): number {
    const count: number = this.displayCount();
    if (count <= 0) {
      return -1;
    }
    return count - 1 + (this.headerMounted() ? 1 : 0);
  }

  // 展示项下标 → 项内首条消息 id（触顶翻页锚点定格用；段取首步、消息项取自身——锚点按
  // **源消息 id** 记录，恢复时按 id 反查下标，段在翻页补全后可能改头/合并也不失锚）
  anchorMessageIdAt(index: number): string {
    if (index < 0 || index >= this.displayItems.length) {
      return '';
    }
    const item: ChatDisplayItem = this.displayItems[index];
    if (item.kind === DISPLAY_KIND_SEGMENT) {
      return item.steps.length > 0 ? item.steps[0].id : '';
    }
    return item.msg !== null ? item.msg.id : '';
  }

  // 源消息 id → 展示项下标（锚点恢复、菜单锚点定位用；不在展示流 = -1——被折叠步骤仍能命中
  // 其所在段，故菜单/重试目标行恒可定位）
  displayIndexOfMessage(msgId: string): number {
    for (let i = 0; i < this.displayItems.length; i++) {
      const item: ChatDisplayItem = this.displayItems[i];
      if (item.kind === DISPLAY_KIND_SEGMENT) {
        for (const step of item.steps) {
          if (step.id === msgId) {
            return i;
          }
        }
      } else if (item.msg !== null && item.msg.id === msgId) {
        return i;
      }
    }
    return -1;
  }

  // 结构变更后的展示项重建（写点收口：数据源自身全部维护点 + 域外状态写点经本方法上报——
  // 见各调用方注释）。prev 传入 = 增量续用（段对象复用承载键与折叠态）；传空 = 换源全新建
  // （重建/换分支——折叠态回默认，与「重进恢复默认」同口径）。
  // ★ 2026-10-08 状态收敛笔：重投影前先清扫「已不处于等待作答」的提问卡草稿（业务把
  // toolState 改为 done/error 或停止后——任务书 §3.4），轮事实与等待态由投影一并重算。
  refreshDisplay(): void {
    // 先清扫已不等待作答的提问卡草稿，再重投影（投影不读草稿，次序为口径纪律）
    this.clearStaleAskDrafts();
    this.clearStaleDockMarkers();
    settleMarkdownBodies(this.messages, this.displayRounds);
    // 第 4 参 = 窗口含会话起点？（olderExhausted——残缺前缀轮判据的消歧输入，见投影件轮首
    // 目标段注释）
    this.applyDisplayItems(buildDisplayItems(this.messages, this.displayItems, this.displayRounds,
      this.olderExhausted));
  }

  // 换源重建（内部用：rebuildFromMessages 走全新建——折叠态不跨换源延续）
  private refreshDisplayFresh(): void {
    this.clearStaleAskDrafts();
    this.clearStaleDockMarkers();
    settleMarkdownBodies(this.messages, this.displayRounds);
    this.applyDisplayItems(buildDisplayItems(this.messages, [], this.displayRounds,
      this.olderExhausted));
  }

  private applyDisplayItems(next: ChatDisplayItem[]): void {
    this.displayItems = next;
    this.notifyReload();
  }

  // 提问卡草稿清扫（唯一判据 = 已不处于等待作答；草稿写入/恢复全在 ChatAskUserCard）——
  // 写点收口在重投影入口，组件的显示镜像随 msg 观察链自然失活
  private clearStaleAskDrafts(): void {
    for (const m of this.messages) {
      if (m.kind === 'tool' && m.askDraft !== undefined && !isAskAwaiting(m)) {
        m.askDraft = undefined;
      }
    }
  }

  // 输入位接管标记清扫（2026-11-08 笔；与草稿清扫并列、判据扩到两类等待卡）：业务把
  // toolState 改终态或外部停止后，标记若残留会让流内头行永久不挂卡体。只清「已不等待」
  // 的标记，等待中的卡由宿主 dismiss 单入口清；换源重建的对象天然 undefined。
  private clearStaleDockMarkers(): void {
    for (const m of this.messages) {
      if (m.kind === 'tool' && m.dockOwned === true && !isStepAwaitingUser(m)) {
        m.dockOwned = false;
      }
    }
  }

  // ── 展示轮事实（写入面）──

  // 轮登记（只在新 holder 上屏前调用）：非空 id 登记 running 并写 holder.displayRoundId；
  // 同 id 重复调用（工具续轮/异常路径）不把终态重置回 running——已登记项保留原状态，
  // 仅补写 holder 归属。空 id / 页面已销毁 = 不登记（不伪造轮）。规则本体在展示投影件
  //（registerDisplayRound——可直接直跑），本处只管销毁闸与 holder 归属
  beginDisplayRound(roundId: string, inputAnchorId: string, holder: ChatMessage): void {
    if (this.displayDisposed || roundId === '') {
      return;
    }
    registerDisplayRound(this.displayRounds, roundId, inputAnchorId);
    holder.displayRoundId = roundId;
  }

  // 成员轮归属继承（思考懒创建 / 工具卡上屏前调用）：**只查精确 owner**（正常就位行）
  // 继承其非空轮 id；找不到则留空（不扫最近 assistant/user 补猜）。owner 的
  // 轮 id 由 beginDisplayRound（新 holder）或上一轮继承（startNextAssistantRound）给出。
  bindDisplayMember(msg: ChatMessage, ownerAssistantId: string): void {
    if (this.displayDisposed || ownerAssistantId === '') {
      return;
    }
    const owner: ChatMessage | null = this.findMessage(ownerAssistantId);
    if (owner === null || owner.displayRoundId === '') {
      return;
    }
    msg.displayRoundId = owner.displayRoundId;
  }

  // 轮终态结算（唯一合法三值 done/error/stopped）：只允许**已登记且 running** 的轮转终态；
  // 空 id / 未登记 id / 已终态均不改（R1 迟到 settle 不会改写已终态，也不会碰 R2）。自身
  // 不 reload——由收尾调用方写完源字段后统一 refreshDisplay。规则本体在展示投影件
  //（settleDisplayRoundFacts，可直接直跑）
  settleDisplayRound(roundId: string, status: string): void {
    if (this.displayDisposed || roundId === '') {
      return;
    }
    settleDisplayRoundFacts(this.displayRounds, roundId, status);
  }

  // 轮事实批量安装（历史装配批；只安装不通知——由随后的 rebuild/prepend 统一 reload）。
  // 已存在项不覆盖：本页已装配的实时 running/终态优先于历史缓存，不允许旧 running/unknown
  // 覆盖 live 终态；规则本体在展示投影件（installDisplayRoundFacts，可直跑）
  installDisplayRounds(facts: DisplayRoundFacts[]): void {
    if (this.displayDisposed) {
      return;
    }
    installDisplayRoundFacts(this.displayRounds, facts);
  }

  // 轮事实只读（重试域取已证明输入锚用；未登记回 null）
  displayRoundFactsOf(roundId: string): DisplayRoundFacts | null {
    const facts: DisplayRoundFacts | undefined =
      roundId !== '' ? this.displayRounds.get(roundId) : undefined;
    return facts !== undefined ? facts : null;
  }

  // 轮可信耗时回填：只填**已存在且终态**
  // 的指定轮——disposed / 空 id / 数值非法 / 轮不存在 / 非终态 / 已有合法时间一律 false
  //（不新建轮、不扫描「当前轮」替代传入轮 id）；成功写值返 true，调用方 true 后 refreshDisplay
  // 一次（本方法自身不通知——与轮事实其余写点同口径）
  setDisplayRoundDuration(roundId: string, durationMs: number): boolean {
    if (this.displayDisposed || roundId === '') {
      return false;
    }
    if (!Number.isFinite(durationMs) || durationMs < 0) {
      return false;
    }
    const facts: DisplayRoundFacts | undefined = this.displayRounds.get(roundId);
    if (facts === undefined) {
      return false;
    }
    if (facts.status !== 'done' && facts.status !== 'error' && facts.status !== 'stopped') {
      return false;
    }
    if (facts.durationMs !== undefined) {
      return false;
    }
    facts.durationMs = durationMs;
    return true;
  }

  // 轮事实裁剪（删除入口专用——removeMessageIds 完成后调用）：只保留仍被
  // 在列消息引用的轮。**禁挂 push/insertBefore/普通 refreshDisplay**：首发 begin 后先 push(user)
  // 再 push(holder)，前一拍新轮尚无在列成员，挂错点即误删。
  private pruneDisplayRounds(): void {
    if (this.displayRounds.size === 0) {
      return;
    }
    const referenced: Set<string> = new Set();
    for (const m of this.messages) {
      if (m.displayRoundId !== '') {
        referenced.add(m.displayRoundId);
      }
    }
    const kept: Map<string, DisplayRoundFacts> = new Map();
    this.displayRounds.forEach((fact: DisplayRoundFacts, id: string): void => {
      if (referenced.has(id)) {
        kept.set(id, fact);
      }
    });
    this.displayRounds = kept;
  }

  // ── 展示态页面寿命释放 ──
  // 调用点 = ChatPageLifecycle.leave 的页面侧回调 + **运行时
  // 闲置回收点**（ChatSessionRuntime.reclaim——退页不断流后展示态必须活过离页〔重进重挂的
  // 前提〕，随运行态回收一并释放；位次不变 = 全部停写者之后）：置销毁闸 → 调释放回调（清
  // 历史读缓存索引/代次〔登记面挂 ChatPageLoadCtrl.attachDisplayState——闭包化后须晚于
  // 换源〕）并立即清回调引用 → 释放轮事实/草稿/详情（不通知列表）。幂等。
  setDisplayDisposeHandler(handler: () => void): void {
    this.displayDisposeHandler = handler;
  }

  isDisplayDisposed(): boolean {
    return this.displayDisposed;
  }

  disposeDisplayState(): void {
    this.displayDisposed = true;
    const handler: (() => void) | null = this.displayDisposeHandler;
    this.displayDisposeHandler = null;
    if (handler !== null) {
      handler();
    }
    this.displayRounds.clear();
    this.releaseMessageDisplayState();
    this.displayItems = [];
  }

  // 换源（clear / rebuild）前的旧消息展示态清扫：草稿与详情意愿随旧对象归零（可能仍被
  // 异步闭包引用的大数组在此显式断开，不只期待 GC）
  private releaseMessageDisplayState(): void {
    for (const m of this.messages) {
      if (m.askDraft !== undefined) {
        m.askDraft = undefined;
      }
      if (m.detailExpanded !== undefined) {
        m.detailExpanded = undefined;
      }
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
  // └────────────────────────────────┘

  isEmpty(): boolean {
    return this.messages.length === 0;
  }

  // 清空消息流（★ 订正 A-6：整容器复位原语，当前全仓无调用者——换会话零残留由「页面
  // 每会话重建 + 加载链收尾写点」承担，勿据本方法推断换会话会清流；键空间 id 不重置——
  // nextMessageId 全局唯一防 key 复用）；翻页态与游标随窗口一并复位
  clear(): void {
    // 换源前清旧消息展示态与轮事实（草稿/详情/轮事实随旧源作废）
    this.releaseMessageDisplayState();
    this.displayRounds.clear();
    this.messages = [];
    this.messageCount = 0;
    this.historyLoaded = false;
    this.entryLoadEpoch = 0;
    this.entryFirstScreenReady = true;
    this.freshEntry = false;
    this.launchHandoff = false;
    this.blockedNotice = '';
    this.olderLoading = false;
    this.olderExhausted = false;
    this.olderAttempted = false;
    this.pathAnchor = null;
    // 屏幕身份随清空回未证态并推进换源代次（旧屏幕事实不得跨清空残留）
    this.loadedBranchId = '';
    this.pathViewEpoch++;
    this.refreshDisplayFresh();
  }

  // 历史回放重建（ChatDb 尾部查询 → 消息流；服务端/本地库为权威，整体重建）。
  // 行→消息映射收编 ChatMessageProjection.chatMessagesFromRows
  // 单源（rebuild/prepend/live 共用映射），本方法只剩容器语义（tail 维护/游标/通知）；
  // graph 会话经 rebuildFromMessages 走同源映射＋路径锚。
  // 有 reasoning 的行先补思考块（回放形态 = 思考在回答上方，与流式实时一致）；
  // ★ 回传历史思考：思考块 linkId = 正文行 id（发送组装时把思考并回
  // assistant 消息——仅 OpenAI 系，见 ChatSendCtrl.dispatchSend）
  rebuildFromHistory(rows: MessageRow[], facts?: DisplayRoundFacts[],
    roundIdOf?: Map<string, string>): void {
    this.rebuildFromMessages(chatMessagesFromRows(rows, roundIdOf),
      rows.length < QUERY_TAIL_LIMIT, null, facts);
  }

  // 视图消息数组直灌重建（graph 会话加载链：行映射已在加载侧经
  // 投影件完成，容器语义与 legacy 同一收口。anchor 非空 = graph 窗口（路径锚随窗口写入，
  // seq 游标不写——两游标互斥，loadOlder 按锚空分流）；anchor 空 = legacy 窗口）
  // 可选 facts = 本批历史装配的轮事实——顺序固定「清旧展示状态
  // →装新 facts→换 messages→投影」
  rebuildFromMessages(msgs: ChatMessage[], exhausted: boolean,
    anchor: PathAnchorCursor | null, facts?: DisplayRoundFacts[]): void {
    // 换源前清旧消息展示态与轮事实（草稿/详情意愿不跨换源延续；旧异步闭包引用的大数组
    // 在此断开）
    this.releaseMessageDisplayState();
    this.displayRounds.clear();
    // 末条 assistant 行置 tail（「其后无任何消息」在回放
    // 形态 = 最后一个 assistant 行——notice 不落库、工具行恒随其 assistant 段落成组）
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].kind === 'assistant') {
        msgs[i].tail = true;
        break;
      }
    }
    renewMarkdownBindings(msgs);
    this.messages = msgs;
    this.messageCount = msgs.length;
    this.historyLoaded = true; // 空态分层：回放成功含空表——确认空才亮引导层
    this.olderLoading = false;
    this.olderAttempted = false;
    // 初始窗不足一页 = 历史已全量在窗——预判到底（免触顶空查询；行显示另需 olderAttempted）
    this.olderExhausted = exhausted;
    this.pathAnchor = anchor;
    // 屏幕已加载分支身份随安装同拍落定：graph 窗口 =
    // anchor.branchId（含空 head 分支——分支存在即屏幕沿它），legacy/无锚 = ''（未证）；
    // 一次 rebuild 只推进一次换源代次
    this.loadedBranchId = anchor !== null ? anchor.branchId : '';
    this.pathViewEpoch++;
    if (facts !== undefined) {
      this.installDisplayRounds(facts);
    }
    // 回放轮起始时刻归一：助手侧消息 createdAt 对齐本轮
    // run.createdAt（口径/预演见投影件 alignRoundStartTimes）——刷新前归一 = 单次渲染；
    // 本口为整窗重建（无旧批在列），扫传入 msgs 即全量
    alignRoundStartTimes(msgs, this.displayRounds);
    // 换源重建展示项（prev 传空——折叠态不跨换源延续，与
    //「重进恢复默认」同口径；同分支增量走 refreshDisplay 续用）
    this.refreshDisplayFresh();
  }

  // View 消息数组头部前插（触顶路径翻页的前插容器语义）：早于当前
  // 首帧的一页按序头部插入 + 整体重建（头部批量插入逐条 onDataAdd 索引全移，reload 一次
  // 成章）；anchor 非空 = graph 翻页批，路径锚前移到新首行节点。不触尾部 flush/append
  // 语义——翻页是只读历史，流式增量逻辑零改（push/insertBefore 原样）。
  // 展示项重建走增量续用（prev 传入——窗口首段被前插补全时
  // 段对象复用，键与手动展开态不丢；分页补全前缀不得重置段状态）
  // 本批（更早窗口）的轮事实**先安装再拼消息**，仅 reload 一次；
  // prepend 绝不清旧状态（草稿/详情/旧轮事实原样保留）
  prependMessages(msgs: ChatMessage[], anchor: PathAnchorCursor | null,
    facts?: DisplayRoundFacts[]): void {
    if (msgs.length === 0 && anchor === null) {
      return;
    }
    if (facts !== undefined) {
      this.installDisplayRounds(facts);
    }
    this.messages = msgs.concat(this.messages);
    this.messageCount = this.messages.length;
    if (anchor !== null) {
      this.pathAnchor = anchor;
    }
    // 回放轮起始时刻归一（同 rebuildFromMessages）：扫
    // **全量在列消息**——跨界轮（user 行在本批、其已加载部分在上批装入时无 startMs）在此
    // 一并归一；已归一值走「值同不写」零通知
    alignRoundStartTimes(this.messages, this.displayRounds);
    this.refreshDisplay();
  }

  // 路径翻页锚只读出口（2026-09-26 笔3 K8；graph 会话翻页判据——非空走路径翻页）
  oldestAnchor(): PathAnchorCursor | null {
    return this.pathAnchor;
  }

  // 屏幕已加载分支身份只读（'' = 未证/legacy 窗口——回答面板禁把它当图身份用，禁拿库默认
  // isActive 冒充）
  loadedBranch(): string {
    return this.loadedBranchId;
  }

  // 路径视图代次只读（回答读链的过期判据：读图期间屏幕换源即作废旧结果）
  pathEpoch(): number {
    return this.pathViewEpoch;
  }

  // 屏幕身份补建（限定规则）：只给「实时发送后仍无
  // loadedBranchId」的页面用——回答入口读图后须先按真实目标节点验证「库默认分支路径确实
  // 包含目标、且该 U 的最后非空正文等于点击的轮尾节点」，通过才可调用；本类不验证、不猜，
  // 禁每次打开无条件以库默认覆盖已加载值。只补记身份（不换源）故不推进换源代次——推进会让
  // 同一打开链自身的读结果被判过期
  markLoadedBranch(branchId: string): void {
    this.loadedBranchId = branchId;
  }

  // 重试建替代分支后的锚切换（前缀节点两分支共享，
  // oldestNodeId 仍有效；branchId 换新分支——后续翻页沿新分支 parent 链走。seq 游标不动，
  // 图会话翻页不读它）
  // ★ 即使 pathAnchor 为 null（实时发送阶段）也更新
  // 屏幕身份并推进换源代次——实时重试确已把数据源切到新分支路径，本写点只由该事实触发，
  // 不把库默认读值冒充屏幕；原「pathAnchor 非空才改分页锚」的逻辑保留
  reanchorBranch(branchId: string): void {
    if (this.pathAnchor !== null) {
      this.pathAnchor = { branchId: branchId, oldestNodeId: this.pathAnchor.oldestNodeId };
    }
    this.loadedBranchId = branchId;
    this.pathViewEpoch++;
  }

  // 尾部追加（用户/助手占位/notice 消息；页面生成 id 后入列）。tail 维护：任何新消息入列
  // = 原末条助手消息不再满足「其后无任何消息」，先清后置
  // （新入列的 assistant 行自己成为 tail；工具轮中间行在后续 tool 卡 push 时自然失 tail，
  // 最终轮收尾由 finishStream 置回）。窗口 ≤ QUERY_TAIL_LIMIT+进行中回合，线性清扫零成本
  push(msg: ChatMessage): void {
    // ★ 自检轮修复：摘要提示行不参与 tail 维护——它是会话级状态行，不是「其后
    // 又有了新消息」。回放链 rebuildFromHistory 同样把 tail 落在末条 assistant 行（提示行在
    // 其后仍带底栏），两链须一致；否则「采用压缩」瞬间末条回答的底栏（重试/用量/版本切换）
    // 整栏消失到下一轮为止，而重进会话又复现——同态两样。
    // ★ 自检轮补：清空分隔条同属会话级状态行（清空瞬间末条回答底栏整栏消失，
    // 同族缺陷）——判据按**边界家族**枚举（summary | clear），后续新增边界类型时此处一并
    // 加名，勿逐类各留一处洞
    if (msg.kind !== 'summary' && msg.kind !== 'clear') {
      for (const m of this.messages) {
        if (m.tail === true) {
          m.tail = false;
        }
      }
      if (msg.kind === 'assistant') {
        msg.tail = true;
      }
    }
    this.messages.push(msg);
    this.messageCount = this.messages.length;
    // 追加后展示项重建（末段吸收新步骤 = 段对象复用、键不变；
    // 新起正文/提示行 = 新展示项）
    this.refreshDisplay();
  }

  // 定位插入（流式思考块懒创建：插在助手占位气泡之前——思考在回答上方；beforeId 须存在）
  insertBefore(beforeId: string, msg: ChatMessage): void {
    const index: number = this.findIndex(beforeId);
    if (index < 0) {
      this.push(msg);
      return;
    }
    this.messages.splice(index, 0, msg);
    this.messageCount = this.messages.length;
    this.refreshDisplay();
  }

  // 按 id 查消息（流式原地改字段的引用入口；找不到 = null 交调用方守卫）
  findMessage(id: string): ChatMessage | null {
    const index: number = this.findIndex(id);
    return index >= 0 ? this.messages[index] : null;
  }

  // 按 id 批量移除消息行（无命中零通知）。现役消费方 = ChatPage 压缩收口（removeMessages
  // 回调——流内摘要提示行随删除摘要下屏）
  removeMessageIds(ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    const kept: ChatMessage[] = [];
    const removedIds: string[] = [];
    for (const m of this.messages) {
      if (ids.indexOf(m.id) >= 0) {
        removedIds.push(m.id);
        if (m.askDraft !== undefined) {
          m.askDraft = undefined; // 被移除对象草稿同步清（不以 GC 期待替代——异步闭包可能仍引用）
        }
        continue;
      }
      kept.push(m);
    }
    if (removedIds.length > 0) {
      this.messages = kept;
      this.messageCount = kept.length;
      this.pruneDisplayRounds();
      // ★ 2026-10-08 过程段折叠笔：移除后展示项重建（段成员收缩或整段消失）
      this.refreshDisplay();
    }
  }

  private findIndex(id: string): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private notifyReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}
