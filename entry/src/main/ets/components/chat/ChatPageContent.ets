// 聊天页内容区组件（2026-08-29 对话页 UI 对齐任务 3 自 dshinhm ChatPageContent **去 kap 改造**；
// 拆分形态先例 LogPage/LogPageContent——主文件留 @State/生命周期/网络调度，本组件管 UI 布局
// 与展示，数据经 @Prop/@ObjectLink 入、事件经回调出）。
// 布局（dshinhm 定稿）——Stack 底对齐多层叠加：
// ① 消息流层（全高 List + LazyForEach，ChatDataSource 单一事实源）：
//    · ★ List 常驻挂载（坑63）：空态/错误态改覆盖层而非互斥分支——Scroller 全程绑定，
//      空态下 scrollToEnd 不再抛 BusinessError 闪退；
//    · 顶部留白用官方 contentStartOffset（内容起始静止位置下移 topPad、滚动时可滚入
//      标题栏蒙层透出——与「padding 固定视口内缩」语义不同，勿改回 padding）；底部
//      contentEndOffset = 浮层实测高（末条消息静止在输入栏上方）；两偏移之和超内容区
//      长度时官方双双归零（极短内容边缘场景，可接受）；
//    · 边缘回弹 alwaysEnabled（坑76：内容不足一屏同样可拖拽回弹）；
// ①b 空态/错误态覆盖层（messageCount 驱动）+ 底部渐变蒙层（90vp 下实上透，pageBgFade
//    配对 page_bg——消息滑入输入区渐隐；2026-09-03 三日实验后恢复，见该层注释）；
// ② 「更多」菜单隐形锚点层（openMenu TargetInfo 定位目标；HitTestMode.None 穿透触摸）；
// ③ 底部浮层（输入栏 ChatInputBar）：悬浮消息流之上，容器全透明（材质在输入栏内部）；
//    实测高度 onAreaChange 回写（输入框多行增高实时同步 contentEndOffset）。★ 容器只含
//    输入栏——展开增量高度经 onToolRowInset 从底衬里扣除，故 floatBandHeight 仍只测
//    输入栏本体；
// ④ 附件查看器（2026-09-15 预览第三轮覆盖层 → 同日预览升级笔改全屏模态 → ★ 同日二级页化笔
//    改**导航栈内二级页**）：查看器承载整体移出本组件——pushPathByName 入栈（页面 =
//    components/chat/AttachmentViewerPage.ets，官方 HDS 标题栏 + 内容默认不进蒙层——同日
//    顶栏分享笔口径）。本组件只留
//    「分派 + 开页」两件事：分派单点按件型分三路（文档直走系统预览窗 / 图片 / 文本），开页
//    经共享件 AttachmentUtil.openAttachmentViewer（内含连点防重入与 animated=false）。共享元素
//    广播键 ATTACH_SHARED_ID_KEY 在开页前写（值 = 命中件 id；文本写空串清残留），随后由查看器
//    随页更新、由查看器页销毁时清空（写点清单见 AttachmentUtil 常量注释）。本组件不再持有
//    查看器状态（原 viewerItems/viewerIndex/viewerOpen 三 @State 随模态退役删净），故也无
//    「值参跨 PageShell.content 冻结」的坑16 面。两入口（消息流附件泡 / 输入栏附件条）都在
//    本组件内接线分派（onPreviewAttach / onPreviewAttachment）。
// 去 kap 裁剪项：待办交互卡（PendingInteractionCard 支路 + approvals/questions/
// onApproval/onAnswer）、媒体预览（onPreviewMedia + sessionId 透传）、权限模式/目标输入态
// 透传。★ 触顶翻页链已复原（2026-08-31 任务 D，待接入清单第 5 件销账）：头部提示行
//（加载更早/已到顶）+ onReachStart 触发 + 锚点恢复——编排域拆 ChatOlderCtrl（超线
// 前置拆分），查询/前插在 ChatPageLoadCtrl.loadOlder，状态乘 ChatDataSource @Track。
// 流式跟随（dshinhm 二三四改方案 A + 二三六改方向修正）：手势方向检测（手指下移 = 翻
// 历史停跟随；上移 = 清翻历史意图）+ onReachEnd 门控恢复。
// ★ 2026-09-01 反碎片并回：ChatRetryRow.ets（失败轮重试动作行，本组件单消费方、同域
// 「消息流行渲染」）并入——原拆分动因 = ChatMessageItem 当年 390 行逼近 400 旧红线，
// 宪法修订（600 软引导 / 1000 硬线 + 反碎片下限）后复归。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cardDescColor, CARD_SPACING, MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET,
  pageBgFade, TITLE_BAR_MASK_EXTRA_HEIGHT } from '../../common/Theme';
import { AttachmentBrief, briefsFromPending, isSystemPreviewKind, openAttachmentViewer,
  openSystemPreview, ATTACH_SHARED_ID_KEY } from '../../common/AttachmentUtil';
import { PendingAttachment } from '../../common/providers/AiTypes';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage } from './ChatMessageCompose';
import { ChatMessageItem } from './ChatMessageItem';
import { ChatFollowController } from './ChatFollowController';
import { ChatOlderCtrl, ChatOlderRow } from './ChatOlderCtrl';
import { ChatInputBar } from './ChatInputBar';
import { CHAT_MORE_MENU_ANCHOR_ID } from './ChatMoreMenu';
import { MessageCopySheet } from './MessageCopySheet';
import { sheetPanelOptions } from './KimiSheetCommon';
import { parseSuggestPayload, SUGGEST_PAYLOAD_KEY, SuggestPayload } from '../../common/SuggestGen';

// 输入带高初值（vp）：chip 行 ≈26 + 间距 8 + 输入胶囊 50 + 间距 8 + 输入栏底 padding 8 +
// 少量余量——仅作首帧兜底；运行时底部浮层（③层 Column）实际高度经 onAreaChange 实测
// 回写（输入框多行自增高后固定估值必然失真，末条消息静止位置始终清出浮层）。
// ★ 2026-09-09 自检：原 export + 「ChatPage toast 定位消费」注释与实况不符（全仓无外部
// 消费方），去 export 降为模块内常量
const INPUT_BAND_HEIGHT: number = 101;

@Component
export struct ChatPageContent {
  // 消息数据源（ChatPage @State 持有的 @Observed 实例；@ObjectLink 订阅其 @Track
  // messageCount 驱动空态/错误态分支，LazyForEach 经同一引用订阅 IDataSource 增量通知）
  @ObjectLink dataSource: ChatDataSource;
  // 列表滚动控制器（父组件持有同一引用，新消息 scrollToEnd 用；普通成员不驱动 UI）
  listScroller: Scroller = new Scroller();
  // 流式滚动跟随控制器（父组件构造传入——状态与滚动逻辑见该类；本组件只喂手势/到达事件）
  followCtrl: ChatFollowController = new ChatFollowController(this.listScroller);
  // 触顶翻页编排域（2026-08-31 任务 D——超线拆分迁出后的本页挂点：触顶触发/锚点定格与
  // 恢复；箭头闭包延迟求值，声明序在 listScroller/onLoadOlder 之后即安全；★ 2026-09-15
  // 流式禁用：第四参 busy 现读闭包——busy 为 @Prop（跨 PageShell.content 断点的通道；
  // 实测可用：与停止键同源通道，09-09 停止键工具期真机销账 + 09-04 附件条结案「@Prop
  // 两级链传播正常」背书）；闭包持成员读取，通道未来若升 @Link/广播键本处零改）
  private olderCtrl: ChatOlderCtrl = new ChatOlderCtrl(
    (): ChatDataSource => this.dataSource,
    (): Scroller => this.listScroller,
    (): Promise<void> => this.onLoadOlder(),
    (): boolean => this.busy);
  // 顶部留白（标题栏蒙层下沿 = 状态栏 + TITLE_BAR_MINI_HEIGHT + TITLE_BAR_MASK_EXTRA_HEIGHT）
  // / 底部留白（系统导航条高）：构造传入后不变，普通成员
  topPad: number = 0;
  bottomPad: number = 0;
  // 会话运行中（透传输入栏：true = 发送键变停止键）
  @Prop busy: boolean;
  // DB 就绪（透传输入栏：占位符切换 + 发送键禁点——M1 行为）
  @Prop dbReady: boolean = true;
  // 初始加载失败提示（'' = 无；与 messageCount 联合判定错误态——覆盖层含「重试」）
  @Prop errorText: string = '';
  // 待发附件（透传输入栏；父组件 @State 持有——附件链 2026-09-03 起已接线，选择入列后
  // 非空即渲染附件条；点开预览经 onPreviewAttachment 在本组件分派。★ @Prop 传数组仅靠
  // 父整组赋值刷新——现状消费面〔渲染 + 删除上行〕与该语义一致，坑16 家族若现冻结症状
  // 再按规范 §3 换 @Link 通道）
  @Prop attachments: PendingAttachment[] = [];
  // 思考强度（透传输入栏 chip；2026-08-31 起随请求下发，'' = 默认不传；★ 08-31 归正
  // @Link——本组件居 PageShell.content（@BuilderParam）内，@Prop 不随父 @State 刷新
  //（坑16），选档后 chip 回显冻结；@Link 为订阅式正常通道）。菜单选项集不透传——
  // 2026-09-06 模型级精化起 chip 行 @StorageProp 自订阅广播键（坑16 同款正解）
  @Link thinkingValue: string;
  // 单条消息指定技能（2026-09-16 单条消息指定技能）：两值 @Link 直链（ChatPage @State →
  // 本层 → ChatInputBar 待发条渲染）+ 清除回调（待发条 × 键上行）。@Link 通道理由同
  // thinkingValue——本组件居 PageShell.content（@BuilderParam）内，@Prop 不随父刷新（坑16）
  @Link designatedSkillId: string;
  @Link designatedSkillName: string;
  // 待发条 × 键上行（父组件清两态——本地清，发送漏斗下次恒写）
  onClearDesignate: () => void = () => {
  };
  // 档位选择回调上行（父组件落值回显；二百二十九起消费方 = 回退路径输入栏 chip——
  // HDS 路径思考入口已迁标题栏「思考」热区，其菜单在 ChatPage 内直写 thinkingValue）
  onPickThinking: (option: string) => void = () => {
  };
  // 标题栏思考键交互期（二百二十九：按压或菜单开着——输入栏收起守卫第三源；HDS 路径
  // 思考 chip 退役后由标题栏键上报，@Link 归正通道同 thinkingValue〔坑16：本组件居
  // PageShell.content（@BuilderParam）内，@Prop 不随父刷新〕）
  @Link thinkingHold: boolean;
  // 当前模型名（2026-09-09 透传输入栏工具行显示；只显示不可点）。★ @Link 归正通道（坑16
  // ——本组件居 PageShell.content（@BuilderParam）内，@Prop 不随父刷新会冻结在首帧，同
  // thinkingValue）；'' = 未解析到连接 → 输入栏显示「未选择」灰字
  @Link modelLabel: string;
  // 上下文用量圆环值（2026-09-17 会话上下文用量）：-1 = 未知/无数据（仅底环）；0~100 占
  // 比。@Link 三级链第二跳（ChatPage @State → 本层 → ChatInputBar，坑16 正解通道同
  // modelLabel）；点击回调上行开面板（带草稿文本）
  @Link ctxRingPct: number;
  onOpenContext: (text: string) => void = () => {
  };
  // 全屏输入（透传输入栏）：回写命令（父 @State → @Prop——cmd tick 驱动覆盖）
  @Prop fullInputDraft: string = '';
  @Prop fullInputCmd: number = 0;
  // 点工具行内的全屏输入键上行（当前输入框文本 → 父暂存为面板初值）
  onFullscreen: (text: string) => void = () => {
  };
  // 系统颜色模式（底部渐变蒙层深浅分治；EntryAbility 写入 AppStorage）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 推荐问题广播载荷（2026-09-19 推荐问题功能）：SuggestGen 写回/清空时 tick 递增 + 本键
  // 覆写 JSON 串 {msgId, items}——@Watch 命中后按 msgId 在自身 dataSource 找消息原地挂
  // suggestions 字段（@Observed 对象级观察驱动渲染）。★ 会话 id 不经 ChatPage 传入本组件
  //（ChatPage 硬线零改动），故订阅「载荷键」而非「tick 后读会话行」——msgId 全局唯一，
  // 他会话广播在本页 dataSource 查不到 = 天然 no-op，跨会话无串扰（执行偏差已在变更记录
  // 点名；tick 键 SUGGEST_TICK_KEY 同步递增供时序观察，本组件不订阅）
  @StorageProp(SUGGEST_PAYLOAD_KEY) @Watch('onSuggestPayload') suggestPayload: string = '';
  // ═══ 事件回调（纯展示组件不触网，全部上行 ChatPage） ═══
  // 发送上行（★ 2026-09-15 发送链收口笔：返回值 = 「已投递或已进入确认流程」——输入栏按它
  // 决定清不清草稿；契约全解见 ChatPage.sendWithAttachments 头注释）
  onSend: (text: string, attachments: PendingAttachment[]) => boolean = (): boolean => false;
  onAbort: () => void = () => {
  };
  // 「+」点击（附件与提示词面板入口——上行父组件开 ChatPromptSheet 半模态）
  onAddFile: () => void = () => {
  };
  // 附件行删除（index 上行）
  onRemoveAttachment: (index: number) => void = () => {
  };
  // 长文本粘贴转附件（2026-09-23 粘贴长文本转文件笔）：粘贴文本上行转附件；settle =
  // 转换结果回报（必调恰一次，收口判据由 ChatInputBar 侧单源执行）——本组件只透传，形制同 onAddFile。
  // ★ 默认实现 = settle(false) 而非空体（2026-09-24 自检轮，同 ChatInputBar 同段理由）：输入栏
  // 已拦下原生插入，空体 = 长文本静默消失；settle(false) 退化为「不转附件、原文照常落框」
  onPasteLongText: (text: string, settle: (converted: boolean) => void) => void =
    (_text: string, settle: (converted: boolean) => void): void => {
      settle(false);
    };
  // 错误态「重试」（重拉历史 + 重读连接——aicontrol 语义，接 ChatPage 既有方法）
  onRetry: () => void = () => {
  };
  // 失败轮重试（占位：上行 toast——将来接重发原文；与 onRetry 整页重拉语义不同勿混用）
  onRetryTurn: (turnId: string) => void = () => {
  };
  // ── 消息气泡底栏透传（2026-09-14 任务书；普通成员通道——isPrivate 页级恒定无坑16 风险）──
  // 底栏重试键上行（msgId；ChatPage 委托 ChatSendCtrl.retryLast 就地重答——2026-09-20
  // 重试真链复活并升级多版本保留）
  onRetryMsg: (msgId: string) => void = () => {
  };
  // 底栏版本切换键上行（2026-09-20 消息重新生成·多版本；msgId + 目标版下标 → ChatPage
  // 校验与落库换版；照 onRetryMsg 同契约，本组件透传零业务）
  onVariantSwitch: (msgId: string, target: number) => void = () => {
  };
  // 底栏「更多」键上行（msgId；ChatPage 经 ChatMessageMenuHost 按锚点弹出消息菜单）
  onMoreMenu: (msgId: string) => void = () => {
  };
  // 摘要提示行整行点击上行（2026-09-23 上下文压缩；ChatMessageItem kind='summary' 分支 →
  // ChatPage.openContextSheet 开用量面板；照 onRetryMsg 同契约，本组件透传零业务）
  onOpenUsage: () => void = () => {
  };
  // 隐私会话（构造注入后不变）：true = 气泡底栏整栏不显示（零留痕口径）
  privateSession: boolean = false;
  // ask_user 答案上行（2026-09-02 工具调用底层；ChatPage 构造处注入 → ToolRuntime.resolveAsk）
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {
  };
  // browse_act 高危确认上行（2026-09-18 P2·B 单元；ChatPage 构造处注入 →
  // ChatSendCtrl.resolveBrowseConfirm → ToolRuntime.resolveBrowseConfirm；同 onAskSubmit 形制）
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {
  };
  // 触顶翻页上行（2026-08-31 任务 D：ChatOlderCtrl 触发后回页面 → ChatPageLoadCtrl.loadOlder
  // 游标前查 + 头部前插；Promise——resolve/reject 决定锚点恢复，见 ChatOlderCtrl）
  onLoadOlder: () => Promise<void> = () => Promise.resolve();
  // 底部浮层（③层）实测高度（vp，onAreaChange 回写；初值 INPUT_BAND_HEIGHT 仅首帧兜底）。
  // 注意浮层已含 bottomPad 底 padding，contentEndOffset 直接用不再加
  @State private floatBandHeight: number = INPUT_BAND_HEIGHT;
  // ── 消息全文面板（2026-09-18 消息复制优化笔：长按气泡 → 面板内自由选择复制）──
  // 宿主 = 本组件根 Stack（规范-半模态 §1 三级挂点「分支根」——本组件非 ForEach 行内、
  // 存活期不因数据销毁、isShow 与触发键〔消息行〕就近同位）；不挂 ChatPage 页面根是
  // 行数预算决策：ChatPage 剔头贴 1200 硬线，本面板全链在本组件闭环零上翻
  @State private copySheetShow: boolean = false;
  // 面板文本快照（长按一刻的 msg.text 拷入——流式增量不跟进，面板职责是复制定稿文字）
  @State private copySheetText: string = '';
  // 助手消息（true = 面板显示 AI 标识行）
  @State private copySheetFromAssistant: boolean = false;
  // 展开增量扣减（2026-09-09 决明「展开输入时不管会话多少页面都不动」；同日二修/三改）：
  // 展开让浮层长高的只有工具行（44），其高度从列表底部衬距里扣除——展开/收起时消息列表
  // 零位移；代价 = 展开态卡片顶边覆盖末条下缘（决明拍板取舍）。值由 ChatInputBar 实测上报
  //（工具行 onAreaChange，与浮层高度实测同源 → 动画期间同步不抖动；硬编码常量 + 在
  // animateTo 闭包内一次性设终值会与动画中的实测高度错拍，列表先沉后弹）
  @State private toolRowInset: number = 0;
  // ── 流式跟随（二三四改方案 A）──
  // 手势方向检测基准（onTouch Move 相邻 y 比较；-1 = 无活动手势）
  private lastTouchY: number = -1;
  // 用户正在翻历史（二三六改方向修正：手指下移 = 往回翻历史（停跟随）、上移 = 朝最新
  // 内容；用途 = onReachEnd 恢复跟随的门控：翻历史手势激活期到达底沿不恢复（防贴底
  // 长高触发的误恢复）；朝底方向手势后到达底沿则恢复）
  private historyScrolling: boolean = false;
  // ── 附件查看器（2026-09-15 预览第三轮；★ 同日预览升级笔改全屏模态；★ 同日二级页化笔改
  //    导航栈内二级页）：查看器状态已不在本组件（数据随路由参数生命周期，见 PageMapBuilder
  //    分支），本层只持路由栈引用与两入口分派；打开经共享件 openAttachmentViewer ──
  // 路由栈（普通成员——页面装配处注入；开查看器二级页用）
  pathStack: NavPathStack = new NavPathStack();

  // 打开查看器（分派单点收敛）：共享广播键在 push 前写入（图片 = 命中件 id——气泡/输入栏
  // 缩略图先行绑定为共享元素 out 侧；文本 = 空串清除残留绑定）；push 与连点防重入在共享件
  // AttachmentUtil.openAttachmentViewer 内（两宿主共用，禁裸字符串路由）
  private openViewer(items: AttachmentBrief[], startIndex: number, sharedId: string): void {
    AppStorage.setOrCreate<string>(ATTACH_SHARED_ID_KEY, sharedId);
    openAttachmentViewer(this.pathStack, items, startIndex);
  }

  // ── 入口一：消息流附件泡（ChatMessageItem 上行；与 ChatMessageItem 同名契约）──
  onPreviewAttach(msgId: string, briefId: string): void {
    const msg: ChatMessage | null = this.dataSource.findMessage(msgId);
    if (msg === null) {
      // 未命中守卫（P0-1 禁静默吞）：消息在点开前被重载冲掉——理论不可达
      hilog.warn(0xD5A0, 'ChatPageContent', '附件泡点击未命中消息：%{public}s', msgId);
      return;
    }
    const briefs: AttachmentBrief[] = msg.attachBriefs ?? [];
    const hit: AttachmentBrief | undefined =
      briefs.find((b: AttachmentBrief): boolean => b.id === briefId);
    if (hit === undefined) {
      hilog.warn(0xD5A0, 'ChatPageContent', '附件泡点击未命中简报：%{public}s', briefId);
      return;
    }
    if (hit.kind === 'image') {
      // 图片滑切范围 = 当前已加载消息窗口内全部图片简报（按消息时序展开——书 §6-1；
      // 更早未加载的不参与，翻页后可滑到）
      const scope: AttachmentBrief[] = [];
      const all: ChatMessage[] = this.dataSource.allMessages();
      for (const m of all) {
        if (m.kind === 'user' && m.attachBriefs !== undefined) {
          for (const b of m.attachBriefs) {
            if (b.kind === 'image') {
              scope.push(b);
            }
          }
        }
      }
      this.dispatchPreview(hit, scope);
    } else {
      this.dispatchPreview(hit, []);
    }
  }

  // ── 入口二：输入栏附件条（ChatInputBar 上行；待发附件点开预览，拍板 4）──
  private onPreviewAttachment(fileId: string): void {
    const briefs: AttachmentBrief[] = briefsFromPending(this.attachments);
    const hit: AttachmentBrief | undefined =
      briefs.find((b: AttachmentBrief): boolean => b.id === fileId);
    if (hit === undefined) {
      hilog.warn(0xD5A0, 'ChatPageContent', '输入栏附件点击未命中：%{public}s', fileId);
      return;
    }
    // 图片可滑切（待发附件内同 kind 集合）；文本单件；文档走系统预览
    const scope: AttachmentBrief[] = hit.kind === 'image' ?
      briefs.filter((b: AttachmentBrief): boolean => b.kind === 'image') : [];
    this.dispatchPreview(hit, scope);
  }

  // 预览分派单点（两入口共用）：点击前统一文件存在性检查（单次 syscall，非轮询——天然
  // 避 TOCTOU）→ 文档类走系统预览窗（无查看器）→ 图片按 scope 定位进查看器（按 briefId
  // 匹配定下标，禁下标算术）→ 文本单件进查看器
  private dispatchPreview(hit: AttachmentBrief, imageScope: AttachmentBrief[]): void {
    // 键盘态先收键盘（查看器全屏盖住输入区，键盘悬着观感割裂；clearFocus 官方姿势 =
    // TextArea 失焦 → 系统收起输入法——UIContext.d.ts FocusController）
    this.getUIContext().getFocusController().clearFocus();
    if (!fs.accessSync(hit.absPath)) {
      // 「行在文件不在」（拍板语义）：点击时现检 + 中文提示，不做灰态
      this.getUIContext().getPromptAction().showToast({ message: '文件已不在本机' });
      return;
    }
    if (isSystemPreviewKind(hit.name)) {
      // 文档类系统预览：分派共享件（AttachmentUtil.openSystemPreview——uri 必转 / mimeType
      // 空串 / 1 秒防重入闸 / ctx 判空 / 失败中文 toast 全在件内；2026-09-15 附件管理列表笔
      // 自本组件抽出，两消费方共用，本处行为零变化）
      openSystemPreview(this.getUIContext(), hit.name, hit.absPath);
      return;
    }
    if (hit.kind === 'image') {
      const idx: number =
        imageScope.findIndex((b: AttachmentBrief): boolean => b.id === hit.id);
      if (idx < 0) {
        hilog.warn(0xD5A0, 'ChatPageContent', '图片滑切集合未命中点击件：%{public}s', hit.id);
        return;
      }
      this.openViewer(imageScope, idx, hit.id);
    } else {
      // 文本模式键写空串（统一「每次打开必写键」不变量：清掉上一轮图片预览遗留的绑定，
      // 空串 = 官方「清除绑定」语义。★ 2026-09-15 全面自检笔改注释：原文案「管理页预览
      // 无模态 onDisappear 清理面，其残留键在此自愈」在承载升级笔后失实——管理页承载已
      // 同为全屏模态、清理面与本站对称；本行作为防御性不变量保留，不再承担跨页自愈职责）
      this.openViewer([hit], 0, '');
    }
  }

  // ── 消息全文面板（2026-09-18 消息复制优化笔）──
  // 长按解析开面板（ChatMessageItem.onCopyText 上行）：findMessage 解析 + 三守卫（隐私
  // 会话零留痕防御早退 + 流式生成中不弹〔同日流式闸笔，判据同 ChatMessageItem 主守卫〕
  // + 空文本无可复制——判据主守卫在 ChatMessageItem.requestCopySheet，此处兜第二道）。
  // 快照语义：开面板一刻拷 text，流式增量不跟进（MessageCopySheet 头注释）
  private openMsgCopySheet(msgId: string): void {
    if (this.privateSession) {
      return;
    }
    const msg: ChatMessage | null = this.dataSource.findMessage(msgId);
    if (msg === null || msg.streaming === true || msg.text === '') {
      hilog.warn(0xD5A0, 'ChatPageContent', '长按复制未命中消息或无文本：%{public}s', msgId);
      return;
    }
    this.copySheetText = msg.text;
    this.copySheetFromAssistant = msg.kind === 'assistant';
    this.copySheetShow = true;
  }

  // 面板内容（坑51 红线：bindSheet builder 位挂组件内 @Builder 方法；文本/角色普通参数
  // 直挂——快照语义，开面板前同帧赋值，坑75 不适用）
  @Builder
  CopySheetBuilder() {
    MessageCopySheet({
      text: this.copySheetText,
      fromAssistant: this.copySheetFromAssistant,
      onClose: (): void => {
        this.copySheetShow = false;
      },
      bottomInset: this.bottomPad
    })
  }

  // 在底现读（偏移级 Scroller.isAtEnd，@since 10；2026-09-04 滚动修复核心判定）：
  // try/catch 坑63 族（未绑定/竞态抛 BusinessError）——异常按「不在底」处理：跟随闸宁
  // 不恢复（下一事件自愈）
  private isAtEndSafe(): boolean {
    try {
      return this.listScroller.isAtEnd();
    } catch (e) {
      return false;
    }
  }

  // 推荐问题广播消费（2026-09-19 推荐问题功能；@Watch onSuggestPayload）：载荷解析 →
  // 按 msgId 命中本页消息（全局唯一 id——他会话广播天然无命中）→ 原地挂/清 suggestions
  // 字段。写回广播 items 非空 = 挂载；发送清空广播 msgId='' 无命中即结束（UI 收起由
  // busy 隐藏 + tail 清空两道既有结构承载，内存字段随该消息失去 tail 后不再可见）
  private onSuggestPayload(): void {
    const payload: SuggestPayload | null = parseSuggestPayload(this.suggestPayload);
    if (payload === null || payload.msgId === '') {
      return;
    }
    const msg: ChatMessage | null = this.dataSource.findMessage(payload.msgId);
    if (msg === null || msg.kind !== 'assistant') {
      return;
    }
    msg.suggestions = payload.items.length > 0 ? payload.items : undefined;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ── ① 消息流层（全高 List + LazyForEach，ChatDataSource 单一事实源）──
      // ★ List 常驻挂载（坑63）：空态/错误态是覆盖层而非互斥分支，Scroller 全程绑定
      List({ space: CARD_SPACING, scroller: this.listScroller }) {
        // ── 触顶翻页头部提示行（2026-08-31 任务 D，dshinhm 同款位——LazyForEach 之前 =
        //    列表头部；两态 UI 件 = ChatOlderRow（域文件内），此处只判挂载：加载中 /
        //    已到顶（到底 + 触达过顶部 + 有消息——短会话预判到底但行等首次触达再亮，
        //    不进页常驻）──
        if (this.dataSource.olderLoading ||
          (this.dataSource.olderExhausted && this.dataSource.olderAttempted &&
            this.dataSource.messageCount > 0)) {
          ListItem() {
            ChatOlderRow({
              loading: this.dataSource.olderLoading,
              exhausted: this.dataSource.olderExhausted
            })
          }
        }
        LazyForEach(this.dataSource, (msg: ChatMessage) => {
          ListItem() {
            // retry 动作行独立组件分流（dshinhm 二二六改「新 kind,独立组件」拍板；aicontrol
            // 当前无 kind='retry' 产生方——渲染链占位预埋，其余 kind 走 ChatMessageItem）
            if (msg.kind === 'retry') {
              ChatRetryRow({
                msg: { turnId: msg.text },
                onRetryTurn: (turnId: string): void => { this.onRetryTurn(turnId); }
              })
            } else {
              ChatMessageItem({
                msg: msg,
                onAskSubmit: (callId: string, answerJson: string): void => {
                  this.onAskSubmit(callId, answerJson);
                },
                onBrowseConfirm: (callId: string, approved: boolean): void => {
                  this.onBrowseConfirm(callId, approved);
                },
                onRetryMsg: (msgId: string): void => {
                  this.onRetryMsg(msgId);
                },
                onVariantSwitch: (msgId: string, target: number): void => {
                  this.onVariantSwitch(msgId, target);
                },
                onMoreMenu: (msgId: string): void => {
                  this.onMoreMenu(msgId);
                },
                // 摘要提示行点击开上下文用量面板（2026-09-23 上下文压缩；三级同名链照
                // onRetryMsg 契约：ChatMessageItem prop → 本组件实现 → ChatPage 注入）
                onOpenUsage: (): void => {
                  this.onOpenUsage();
                },
                // 附件泡点击派发（2026-09-15 预览第三轮；三级同名链：ChatMessageItem
                // prop → 本组件实现 → 分派单点 dispatchPreview）
                onPreviewAttach: (msgId: string, briefId: string): void => {
                  this.onPreviewAttach(msgId, briefId);
                },
                // 长按气泡开「消息全文」面板（2026-09-18 复制入口迁移；解析与开面板在
                // 本组件闭环 openMsgCopySheet——不走 ChatPage，行数预算见字段注释）
                onCopyText: (msgId: string): void => {
                  this.openMsgCopySheet(msgId);
                },
                // 推荐问题 chip 点击上行（2026-09-19 推荐问题功能）：复用既有 onSend
                // 直接发送（决策 2——不填充输入框，零新状态通道；发送后建议随发送即
                // 清空收起）
                onSuggestSend: (text: string): void => {
                  this.onSend(text, []);
                },
                privateSession: this.privateSession
              })
            }
          }
          // 项级实测上报（2026-09-06 四稿，Cube ChatMessageListSection 机制移植）：消息项
          // 高度变化喂 followCtrl（0.5vp 去抖在其内部）——「末条在视口内原地长高、可见下标
          // 不变」时 onScrollIndex 无回调，本通道是进页校正链的精确长高触发源
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.followCtrl.onItemAreaChange(msg.id, newArea.height as number);
          })
        // 键 = 消息 id（恒定——增量经 @Observed/@ObjectLink 对象级观察刷新视图，列表项
        // 不每帧重建；「id+version 拼键」是官方点名的闪烁反模式，勿回退）
        }, (msg: ChatMessage) => msg.id)
      }
      .width('100%')
      .height('100%')
      // 列表顶对齐红线（Scroll/List 通用属性 align 默认 Center，短列表会居中——坑18 同族）
      .align(Alignment.TopStart)
      .padding({ left: 12, right: 12 })
      // 顶部/底部留白 = 官方内容起始/结束偏移（随滚动滚走，消息滑入顶部蒙层透出；
      // 语义见头注释①——勿改 padding，padding 是固定视口内缩）
      .contentStartOffset(this.topPad)
      // 底部衬距 = 浮层实测高 − 展开增量（快捷条 + 工具行；展开/收起时列表零位移，见
      // toolRowInset 注释；多行自增高仍实时跟随——那部分不扣）
      .contentEndOffset(this.floatBandHeight - this.toolRowInset)
      // 边缘回弹（坑76）：内容不足一屏同样可拖拽回弹
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 触顶触发翻页（2026-08-31 任务 D；防抖守卫在 ChatOlderCtrl——加载中闸/到底停）
      .onReachStart(() => {
        this.olderCtrl.tryLoadOlder();
      })
      // 第一个可见项下标跟踪（翻页锚点记录用；滚动时轻量更新，非状态驱动）+ 末个可见项
      // 下标喂 followCtrl 进页定位校正链（2026-09-06——rebuild 同帧 scrollToIndex 估算
      // 落点偏上的逼近校正，事件驱动零定时器，详见 ChatFollowController.onScrollIndex）
      // ★ 2026-09-04 撤在此判在底（原 atBottom 缓存）——end 语义是「末项进入可视区」
      // 非真正滚到底，缓存只会记住误判（见字段注释三度修订）；同回调仍喂 olderCtrl 锚点
      .onScrollIndex((first: number, end: number) => {
        this.olderCtrl.onScrollIndex(first);
        this.followCtrl.onScrollIndex(end);
      })
      // 滚动到达底沿 = 恢复跟随，门控 = 非翻历史手势（二三六改）+ 真到底现读（2026-09-04）：
      // 官方语义 onReachEnd 在「末项进入可视区」即触发、且内容/布局变化会再触发——流式中
      // 用户翻历史后往下滑，末条一露头就恢复跟随，增量 maybeFollow 随即拽底与手势互相
      // 打断（决明「上滑停止后不能立刻下滑」主因）。isAtEnd 闸 = 贴底（偏移级）才恢复，
      // 露头路过不再误恢复；未误恢复状态下用户回到真底，边缘回弹过端/回端会再触发本事件
      // 自愈，无需兜底
      .onReachEnd(() => {
        if (!this.historyScrolling && this.isAtEndSafe()) {
          this.followCtrl.onReachEnd();
        }
      })
      // 手势方向检测（触摸滚动语义：手指下移 = 往回翻历史（offset 减小）→ 立即停跟随；
      // 手指上移 = 朝最新内容方向（跟随拽底与之同向无拉锯，不干预）。代码 scrollEdge
      // 不走触摸事件，与跟随拽底天然不冲突（2vp 死区滤手指抖动）。★ 2026-09-04 触摸闸：
      // Down/Up/Cancel 喂 followCtrl——手指在屏期间 maybeFollow 程序滚动链一律熄火（Cube
      // ChatScrollUiFlow onScrollStart 一触摸即释放程序跟随的同思路最小化），不等 >2vp 首帧
      // 位移；松手时仍在跟随态由 onListTouchEnd 补滚尾部增量
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.lastTouchY = event.touches[0].y;
          this.followCtrl.onListTouchStart();
        } else if (event.type === TouchType.Move) {
          const y: number = event.touches[0].y;
          if (this.lastTouchY >= 0 && y > this.lastTouchY + 2) {
            // 手指下移 = 翻历史 → 停跟随
            this.followCtrl.onUserScrollUp();
            this.historyScrolling = true;
          } else if (this.lastTouchY >= 0 && y < this.lastTouchY - 2) {
            // 手指上移 = 朝底部 → 清翻历史意图（到底沿时允许恢复跟随）；顺带取消触顶
            // 翻页的待恢复锚点（2026-09-02 手感修复：用户下滑 = 放弃看旧消息，加载完成
            // 不再 scrollToIndex 拉回——「停止后无法立刻下滑」根因）；★ 2026-09-06 校正链
            // 三稿：进页待校正一并取消（用户自主往底拉时校正链不取消，松手惯性滑行期会被
            // scrollToIndex 打断跳回估算落点 =「拉完松手跳回原地」根因；following 不动——
            // 流式跟随与该向无冲突，见 ChatFollowController.onScrollIndex 三稿注释）
            this.historyScrolling = false;
            this.olderCtrl.cancelAnchor();
            this.followCtrl.cancelAlign();
          }
          this.lastTouchY = y;
        } else {
          // Up/Cancel：开触摸闸——仍在跟随态则补滚尾部增量（闸内三连判，脱底零副作用）
          this.lastTouchY = -1;
          this.followCtrl.onListTouchEnd();
        }
      })

      // ── ①b 空态/错误态覆盖层（仅无消息时显示，盖住空 List）──
      // Scroll 包裹（dshinhm 二十九改）：内容高度加 topPad 滚动余量 + 底部同量 padding
      // 吸收——静止观感不变（全屏居中），可滚动量 = topPad（与「内容可滑入标题栏蒙层」
      // 同语义）；边缘回弹对齐消息层
      if (this.errorText !== '' && this.dataSource.messageCount === 0) {
        // 初始加载失败：中文提示 + 重试（P0-1）
        Scroll() {
          Column({ space: 12 }) {
            Text(this.errorText)
              .fontSize(13)
              .fontColor(cardDescColor())
            Button('重试')
              .fontSize(14)
              .onClick(() => {
                this.onRetry();
              })
          }
          .width('100%')
          .height('calc(100% + ' + this.topPad + 'vp)')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: this.topPad })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
      } else if (this.dataSource.messageCount === 0 && this.dataSource.historyLoaded) {
        // 空态（新对话 / 空历史会话）：应用图标 + 「AI 控制台」引导语（去 Kimi 化——
        // dshinhm 为 kimi_logo + 引导语，aicontrol 用应用图标资源 startIcon）
        // ★ 2026-09-06 空态分层：追加 historyLoaded 判定——进页加载中（历史查询在途）
        // 显示纯背景，确认空会话（loadHistory 成功回放，含空表）才显示引导层，转场动画
        // 中不再闪现「开始新的对话」。两分支互斥推演：错误态命中 = errorText 非 ''
        //（loadHistory 失败 setError，historyLoaded 恒 false 同不进本分支）；本分支命中 =
        // errorText 为 ''（else 链）且 historyLoaded 为 true（rebuild 成功）；加载中 =
        // 两标记皆 false → 两分支均不命中 = 纯背景无覆盖层。判定经 @ObjectLink 订阅
        // @Track 链路与 messageCount 同通道（禁 @Prop——坑16 家族）
        Scroll() {
          Column({ space: 12 }) {
            Image($r('app.media.startIcon'))
              .width(64)
              .height(64)
              .borderRadius(14)
            Text('AI 控制台')
              .fontSize(15)
              .fontColor(cardDescColor())
            Text('开始新的对话')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .height('calc(100% + ' + this.topPad + 'vp)')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: this.topPad })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
      }

      // ── ①b 底部渐变蒙层（dshinhm 十改定稿，2026-09-03 三日实验后恢复）：90vp 高小
      // 范围（盖输入胶囊背后，上沿止于胶囊附近），下实上透渐变（page_bg 深浅自适应配
      // pageBgFade 透明版）——消息滚动滑入输入区渐隐；盖消息层之下、输入栏浮层仍在
      // 上方（不遮输入框本体）；HitTestMode.None 不拦列表滚动/点击。★ 高度 90vp 为
      // 真机调参项，单点可调。实验记录（真机实测）：①backgroundBlurStyle(COMPONENT_THIN)
      // + 蒙层 = 纯白实底（蒙版色不可调 + 蒙层抢先渐隐）；②backgroundEffect 半透模糊
      // （移除蒙层）半透可显但 pop 转场/消息滚动卡（官方 NOTE 逐帧实时渲染实锤）→
      // 三案转正：
      // 恢复蒙层 + 胶囊官方实底（ChatInputBar，零实时渲染）。「半透渐变」备选（未采用）：
      // 蒙层渐变终点由全不透明 page_bg 改半透明（≈50%），消息滑入隐约透出=观感近半透
      // 且静态无性能开销，若后续要半透观感改此端色即可。
      Column()
        .width('100%')
        .height(90)
        .linearGradient({
          angle: 180,
          colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
        })
        .hitTestBehavior(HitTestMode.None)

      // ── ② 「更多」菜单隐形锚点层（openMenu TargetInfo；几何常量与 LogPageContent 同源）──
      // 全高层 + HitTestMode.None：自身与子孙都不参与命中测试，触摸穿透到下层消息列表；
      // 内层 Top 对齐 Stack 复刻 LogPageContent 锚点定位（其外层 Stack 是顶对齐，本层是底对齐）
      Stack({ alignContent: Alignment.Top }) {
        Row() {
          Blank()
          Column()
            .width(1)
            .height(1)
            .id(CHAT_MORE_MENU_ANCHOR_ID)
        }
        .width('100%')
        .padding({ right: MORE_MENU_ANCHOR_RIGHT })
        // 锚点顶 = 「更多」按钮下沿（勿写成标题栏下沿，差 8vp 菜单偏低——LogPageContent
        // 踩坑①）
        .margin({ top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0) })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)

      // ── ③ 底部浮层：输入栏（容器全透明，材质在 ChatInputBar 内部） ──
      // ★ 本容器只挂输入栏：展开增量高度经 onToolRowInset 从底衬里扣除——本容器与
      // floatBandHeight 测量口径均不受影响
      Column() {
        ChatInputBar({
          busy: this.busy,
          dbReady: this.dbReady,
          bottomPad: this.bottomPad,
          attachments: this.attachments,
          thinkingValue: $thinkingValue,
          modelLabel: $modelLabel,
          // 上下文用量圆环（2026-09-17）：值 @Link 下发 + 点击上行（链第 2→3 层）
          ctxRingPct: $ctxRingPct,
          onOpenContext: this.onOpenContext,
          onToolRowInset: (inset: number): void => {
            this.toolRowInset = inset;
          },
          // 展开态上行（2026-09-09 二修之三）：用户开始操作输入栏 → 合闸暂停进页校正链。
          // 展开/收起会让浮层高度变化，链若存活会在每次变化时把列表无动画拽到底（见
          // ChatFollowController.onContentShift）——「有的会话进去后展开输入框页面上移」根因
          onExpandState: (expanded: boolean): void => {
            this.followCtrl.setHold(expanded);
          },
          onPickThinking: this.onPickThinking,
          thinkingHold: $thinkingHold,
          // 单条消息指定技能（2026-09-16）：两值 @Link 透传 + 清除回调上行（链第 2→3 层）
          designatedSkillId: $designatedSkillId,
          designatedSkillName: $designatedSkillName,
          onClearDesignate: this.onClearDesignate,
          onSend: this.onSend,
          onAbort: this.onAbort,
          onAddFile: this.onAddFile,
          onRemoveAttachment: this.onRemoveAttachment,
          // 长文本粘贴转附件（2026-09-23 粘贴长文本转文件笔）：原样透传（收口闭包由
          // ChatInputBar 自持，本组件与页面都不 reinterpret 它）
          onPasteLongText: this.onPasteLongText,
          // 已选未发附件点开预览（2026-09-15 预览第三轮，拍板 4——同域同形入口，
          // 同一查看器/系统预览分派复用）
          onPreviewAttachment: (fileId: string): void => {
            this.onPreviewAttachment(fileId);
          },
          fullInputDraft: this.fullInputDraft,
          fullInputCmd: this.fullInputCmd,
          onFullscreen: this.onFullscreen
        })
      }
      .width('100%')
      // ★ 2026-09-03 决明拍板「改回去，不让渡」：bottomPad−8 的避让让渡已撤销（恢复全量
      // 避让——全屏下输入栏不压手势条的 08-29 定稿口径回正；让渡版经真机确认有贴手势条
      // 风险后弃用）。★ 2026-09-09 底部留白移交 ChatInputBar：键盘态需置 0（决明「抬起过高」，
      // 键盘已盖住底部系统区），而键盘状态只有该组件持有——本层只透传 bottomPad，不再自挂
      // padding（高度口径不变：浮层实测高仍含该留白，contentEndOffset 联动照旧）
      // 实测浮层高度回写（area 宽高单位 vp，官方通用事件）——驱动消息列表 contentEndOffset，
      // 输入框自增高时末条消息不被浮层遮；高度相同则 ArkTS 状态相同不触发重渲染；
      // ★ 2026-09-06 校正链二稿：contentEndOffset 漂移喂 followCtrl.onContentShift——进页
      // 待校正存活期重对齐末条（chips 行晚到变高致末条下沉被遮 = 「进旧会话停在中间偏下」
      // 根因，详见 ChatFollowController）
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.floatBandHeight = newArea.height as number;
        this.followCtrl.onContentShift();
      })

      // ── ④ 附件查看器：★ 二级页化笔改导航栈内二级页 pushPathByName（页面 =
      //    AttachmentViewerPage），本层不再挂任何弹层/模态（原链尾 bindContentCover 已删）
      //    ——文档类不进查看器，分派点直走系统预览窗 ──
    }
    .width('100%')
    .height('100%')
    // ── 消息全文半模态（2026-09-18 消息复制优化笔）：分支根挂点（规范-半模态 §1 判据
    // 三条全过，见 copySheetShow 字段注释）；[MEDIUM, LARGE] 半屏起双停靠 = §4 选型表
    // 「信息查看类」档位（上下文用量面板同款）。onWillDismiss 同步收口（坑73——手势关闭
    // 动画前置回写，勿用 onDisappear 迟到回调）
    .bindSheet(this.copySheetShow, this.CopySheetBuilder(), sheetPanelOptions(
      (_action: DismissSheetAction): void => {
        this.copySheetShow = false;
      },
      [SheetSize.MEDIUM, SheetSize.LARGE]))
  }
}

// ═══ 失败轮重试动作行（2026-08-27 二二六改拍板「新 kind，独立组件」；2026-09-01 自
// ChatRetryRow.ets 并回本文件）═══
// kind='retry' 消息的专属渲染——居中一行「本轮执行失败」灰字 + 「重试」文字键（官方警示
// 色）；点击上行 onRetryTurn(turnId)（本组件透传 → ChatPage 出「重试暂未开放」占位 toast
// ——原设计「重发原文，行即删」未实现，真实现另立项〔五百九十四节〕；且该 kind 行当前
// **无产生方**，用户不可达）。
// retry 行消息视图模型（ChatMessage 的 retry 收窄——Content 分流处构造，避免把全量
// ChatMessage 透传本组件；ArkTS 禁 any，显式接口）
interface RetryRowMsg {
  turnId: string;
}

@Component
struct ChatRetryRow {
  // 消息（kind='retry'；text = turnId；@Prop 同 ChatMessageItem 契约——本行无增量更新，
  // 键恒 'rty-<turnId>'（二三四改稳定键），@Prop 保证构建时值传导）
  @Prop msg: RetryRowMsg;
  // 点击上行（turnId 参数）
  onRetryTurn: (turnId: string) => void = () => {
  };

  build() {
    Row({ space: 8 }) {
      Text('本轮执行失败')
        .fontSize(13)
        .fontColor(cardDescColor())
      Text('重试')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_warning'))
        .onClick((): void => {
          this.onRetryTurn(this.msg.turnId);
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }
}
