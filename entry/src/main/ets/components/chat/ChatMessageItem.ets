// 聊天气泡渲染（自 dshinhm 同名文件随迁改造）：按 ChatMessage.kind 分发形态——user 右侧
// 气泡 / assistant 左侧卡片色气泡 / notice 居中提示条（summary / clear 同族状态行）。
// ★ 过程段折叠后本件只余非步骤行（user / assistant 正文 / summary / clear / notice）——
// thinking 与 tool 步骤渲染件 = ChatProcessSegment.ChatProcessStep；消息级操作栏唯一化：
// 底栏只在 `msg.opsHost === true` 的最终正文行渲染（轮归属判据单源 =
// ChatDisplayProjection.computeOpsHostIds），中途正文保留阅读/长按复制；失败/中止且本轮无
// 正文 = 空正文行改轻量状态尾部（措辞按 msg.emptyRoundKind 分流，判据单源见投影）；链标记
// 与思考半泡切角拼接已退役——正文气泡恒四角圆角、恒上距 CARD_SPACING。
// 气泡行边距常量 BUBBLE_PAD_*（真机定稿值随迁）：用户侧镜像（右近 4/左远 20）；助手侧两侧
// 同取近侧 4/4；用户泡宽度上限 BUBBLE_USER_MAX_WIDTH 78%（挂点 = 外层定宽壳，见 user 分支）。
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { FrameCallback } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BUBBLE_RADIUS, cardBg, cardBorderColor, cardDescColor, cardTitleColor, ATTACH_BUBBLE_GAP,
  CARD_SPACING, CARD_RADIUS, CHAT_ROUND_SPACING, CHAT_ASK_GAP, BUBBLE_PAD_FAR, BUBBLE_PAD_NEAR,
  BUBBLE_USER_MAX_WIDTH, quoteBarColor, quoteBlockBg, chatBubbleUserBg,
  CHAT_LAYOUT_DEBUG } from '../../common/Theme';
import { hideAttachAnnotate } from '../../common/AttachmentUtil';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { withAiContentLabel } from '../../common/AiDisclosure';
import { buildCopySheetText } from '../../common/MarkdownText';
import { copyTextToClipboard } from '../../common/Clipboard';
import { AttachmentBubble } from './AttachmentBubble';
import { quotePreviewOf } from './ChatQuoteBar';
import { ChatMessage, DsCitationSpan, dsCitationSpansOf,
  dsSourceEntryAnchorId } from './ChatMessageCompose';
// 二期 S4 #13：来源卡域整段迁出（本件只留一行组件调用——徽标与长按在新址）
import { ChatSourceCard } from './ChatSourceCard';
import { launchExternalLink } from '../../common/ExternalLink';
import { ChatSuggestBar } from './ChatSuggestBar';
import { MESSAGE_MENU_ANCHOR_PREFIX } from './ChatMoreMenu';
import { ChatMarkdownBody } from './ChatMarkdownBody';
import { ChatUsagePopup } from './ChatUsagePopup';
import { LONG_MSG_COLLAPSE_CHARS } from './markdown/MarkdownScrollableBlock';
import { isLongMsgCollapseEnabled, PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT }
  from '../../common/AppPreferences';
import { ChatRoundHeader, formatMsgTime } from './ChatMessageHeader';
import { FONT_BODY_DEFAULT, FONT_CODE_DEFAULT, PREF_FONT_BODY_KEY,
  PREF_FONT_CODE_KEY, PREF_FONT_LIB_KEY, bodyFontFamily, codeFontFamily } from '../../common/ChatFont';

// 消息正文渲染统一走 ChatMarkdownBody（旧 @lidary/Cube 双库与调试双闸已退役；新引擎各块自理横滚）。

// ── 生成中饰件（决明拍板）──
// 蓝光标几何（vp）：绘制在正文块下沿外侧、正文与工具栏之间的既有空档内；offset = 光标高 ⇒
// 顶边贴正文块下沿。零排版装饰（Stack 叠层 + offset 属渲染域位移，不入布局）⇒ 撤下零位移、
// 不压字、不改断行。初值，真机可整组微调一档
const GEN_CURSOR_WIDTH_VP: number = 3.5;
const GEN_CURSOR_HEIGHT_VP: number = 14;
const GEN_CURSOR_RADIUS_VP: number = 1.75;
const GEN_CURSOR_OFFSET_Y_VP: number = 14;

// ── 长正文占位骨架（★ 2026-10-18 一次出现笔）──
// 构建期行内只显静态灰条（不挂逐帧动画——动画不得盖住被阻塞主线程）；正文层 opacity 0 在
// 背后逐帧建块，揭示完成一次性显现。几何初值，真机可调
const LONG_REVEAL_SKELETON_BAR_HEIGHT: number = 14;
const LONG_REVEAL_SKELETON_GAP: number = 10;
const LONG_REVEAL_SKELETON_RADIUS: number = 7;

// 气泡侧引用摘要长度（气泡密度比输入条更高，故短于 QUOTE_BAR_PREVIEW_CHARS；真机微调档）
const BUBBLE_QUOTE_PREVIEW_CHARS: number = 12;

// 展开动作一次性帧（★ 2026-10-18 一次出现笔）：点击收起条当帧只绘骨架，下一帧才挂正文
//（骨架先实际绘制一帧的铁律）。与组件同寿、销毁成对 cancel
class ChatExpandFrame extends FrameCallback {
  private action: (() => void) | null;
  constructor(action: () => void) { super(); this.action = action; }
  cancel(): void { this.action = null; }
  onFrame(_time: number): void {
    const action: (() => void) | null = this.action;
    this.action = null;
    action?.();
  }
}

// 用户气泡蓝：色值单源 = Theme 函数 chatBubbleUserBg（浅 #DCE8FF / 深 #2E4A73 双档原值，
// 随卡底透明度档位叠 alpha；资源条目已退役）。浅色取状态强调淡底同值（蓝味再淡与白卡分不开）；
// 深色不复用身份深蓝底 #1B2A4A（与卡底几乎同色，泡边界会消失）。消息泡与附件泡共用本函数
@Component
export struct ChatMessageItem {
  // @ObjectLink 对象级观察：流式增量由页面侧原地改 ChatMessage 字段（键恒定不重建列表项）
  @ObjectLink msg: ChatMessage;
  // 助手气泡档位：宿主进页读一次后下发——重进会话生效，本组件不订阅偏好键（流式期间重跑
  // build 不换档）；只作用于助手正文那一层
  bubbleVisible: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位 @StorageProp 只读订阅：档位键不进任何 ForEach/LazyForEach 键——属性级
  // 更新不触发列表项重建（列表键纪律），档位变化属性级刷新助手泡底色
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 消息字体三键 @StorageProp 自订阅（选择值两键 + 共享字体库 JSON）：改选回会话页即重渲拉新
  // 家族串（推导单源 = ChatFont 纯函数，本组件换算一次后经 @Param 下发 V2 正文链）。★ 换字体
  // 不改 content 串、不换键：流式绑定与滚动链零感知，重排只发生在改选当帧
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_CODE_KEY) fontCodeValue: string = FONT_CODE_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';

  // 正文/代码家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  private resolveCodeFamily(): string {
    return codeFontFamily(this.fontCodeValue, this.fontLibJson);
  }

  // 展开动作的下一帧挂载句柄（一次性；销毁成对 cancel）
  private expandFrame: ChatExpandFrame | null = null;

  // ── DS 角标解析记忆化（S3③；来源卡解析已随 #13 迁出本件，缓存只剩角标一份）──
  private citeCacheJson: string = '';
  private citeCacheText: string = '';
  private citeCacheList: DsCitationSpan[] = [];
  // 来源卡角标联动展开的延时句柄（< 0 = 无在途；成对释放——离场清，见 onCitation 注释）
  private dsExpandTimer: number = -1;

  // M2 角标区间（UTF-16 码元；正文与 serverToolsJson 任一变化即失效重算——正文流式增长期
  // serverToolsJson 恒缺席，自然旁路）。来源卡条目已迁出本件，但角标由正文渲染层消费，
  // 仍留父件
  private dsCitations(): DsCitationSpan[] {
    const json: string = this.msg.serverToolsJson ?? '';
    if (json === '') {
      return [];
    }
    if (json !== this.citeCacheJson || this.msg.text !== this.citeCacheText) {
      this.citeCacheJson = json;
      this.citeCacheText = this.msg.text;
      this.citeCacheList = dsCitationSpansOf(json, this.msg.text);
    }
    return this.citeCacheList;
  }

  // 来源行点击 → 系统浏览器（统一出口 launchExternalLink，照 ChatToolCard.openRefUrl 现役
  // 链路——UIContext 形态取宿主 context；失败静默，URL 打开非关键路径不打断阅读）
  private openSourceUrl(url: string): void {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, url);
    } catch (e) {
      // 静默（拿不到宿主 context 的边缘形态）
    }
  }

  // 来源卡角标联动展开的延时句柄清理（幂等——离场与重复点击两条路径都安全）
  private cancelDsExpandTimer(): void {
    if (this.dsExpandTimer >= 0) {
      clearTimeout(this.dsExpandTimer);
      this.dsExpandTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.expandFrame?.cancel();
    this.expandFrame = null;
    this.cancelDsExpandTimer();
  }

  // 标题/脚注锚点点击上行，目标为当前正文实际挂载的组件ID；滚动仍由宿主唯一Scroller执行。
  onMarkdownAnchor: (id: string) => void = () => {
  };
  // 长消息展开上行（带 msgId）：宿主停进页校正/跟随、置阅读期底锚冻结并把该行滚到视口顶部；
  // 正文随后在占位层背后分帧建块、一次性显现（展开只读开头，不强制回底）
  onLongMessageExpand: (msgId: string) => void = (_msgId: string): void => {
  };
  // 来源卡展开收起前置上行（带 msgId；照 ChatProcessSegment.onPresentationChange 同名同义）：
  // 宿主先解进页校正并对本行起「展开局部钉顶」（上沿不动、增量向下长），随后本件改展开意愿
  //——吸底时卡头不被展开内容顶出屏，收起后仍在原处可再点
  onPresentationChange: (msgId: string) => void = (_msgId: string): void => {
  };
  // ── 消息气泡底栏（回调一律上行——本组件零业务）──
  // 重试键点击上行（msgId；ChatPage 委托菜单域 retryFromBubble——判据过闸后走 ChatRetryCtrl.
  // retryAt 单链，末条与历史答案行同形）
  onRetryMsg: (msgId: string) => void = () => {
  };
  // 回答版本步进上行（msgId + 方向〔-1 上一 / +1 下一〕；ChatPage 委托 ChatAnswerCtrl.
  // stepVersion 现读候选切分支——本组件零业务）
  onAnswerStep: (msgId: string, direction: number) => void = () => {
  };
  // 步进器计数位点击上行（msgId；ChatPage 委托 ChatAnswerCtrl.openFor 打开「其他回答」
  // 面板——删除与全文预览在面板内）
  onAnswerPanel: (msgId: string) => void = () => {
  };
  // 提问版本步进上行（user 行 ◀x/y▶ 箭头；msgId + 方向——与回答步进同链 ChatAnswerCtrl.stepVersion）
  onQuestionStep: (msgId: string, direction: number) => void = () => {
  };
  // 「更多」键点击上行（msgId；ChatPage 经 ChatMessageMenuHost 按锚点弹出消息菜单）
  onMoreMenu: (msgId: string) => void = () => {
  };
  // 长按气泡上行（msgId；ChatPageContent 根 Stack 宿主开「消息全文」半模态面板——面板内跨
  // 段落自由选择；★ 底栏复制键已复位，长按与底栏两入口并存，本 prop 保留不动）
  onCopyText: (msgId: string) => void = () => {
  };
  // 附件泡点击派发上行（msgId + briefId → ChatPageContent 分派：图片/文本进应用内查看器、
  // 文档走系统预览——本组件零业务）
  onPreviewAttach: (msgId: string, briefId: string) => void = (msgId: string,
    briefId: string): void => {
  };
  // 推荐问题 chip 点击上行（改名 onSuggestSend → onSuggestTap——点击去向恒为「填入输入框」，
  // 2026-11-12 偏好开关批后不再有「直接发送」分支；本组件零业务）
  onSuggestTap: (text: string) => void = () => {
  };
  // 摘要提示行整行点击上行（kind='summary' 专用——打开「上下文用量」面板看摘要详情与删除键；
  // 本组件零业务，ChatPage 构造处注入）
  onOpenUsage: () => void = () => {
  };
  // 错误 notice 跳转动作上行（action 值域 = 'provider'/'network'——发送域失败路径写
  // msg.noticeAction；跳转在 ChatPageContent 直持 pathStack 实现；无动作 notice 不调本 prop）
  onNoticeAction: (action: string) => void = () => {
  };
  // 用量键气泡开关（bindPopup 受控 show，照 InfoHintButton 复位语义）
  @State private usagePopupShow: boolean = false;

  // 底栏显隐总判据：助手消息且**本条承载本轮消息级操作栏**（opsHost——投影按轮归属写入的
  // 最终正文标记）；中途正文与未收束候选正文不挂栏（「本轮操作栏仅这一处承载」）；streaming
  // 由 opsHost 的轮收束判据覆盖（流式中的轮不可能产出 opsHost），此处不再单判
  private barVisible(): boolean {
    return this.msg.kind === 'assistant' && this.msg.opsHost === true;
  }

  // 轻量状态行判据：失败/中止且本轮无最终正文——恢复入口按本行身份分流（两形态同走单链
  // retryFromBubble → retryAt）：末条（tail 真）带「重试」文字键（onRetryMsg——本行即末轮）；
  // 历史异常轮最后一条空正文行（opsHost 真、tail 假，投影按轮终态授位）不复制文字键，恢复
  // 走本行下方 FinalOpsBar 的重试图标键（同上行链）
  private statusLineVisible(): boolean {
    return this.msg.kind === 'assistant' && this.msg.streaming !== true &&
      this.msg.text.trim() === '' && (this.msg.tail === true || this.msg.opsHost === true);
  }

  // 空轮状态行文案：性质判据单源 = msg.emptyRoundKind（投影写），本处只做文案映射——
  // 'no-text' = 本轮有过程产出、只是没有正文（中性陈述，不当失败）；其余（异常轮/零产出）=
  // 无产出口径。两态共用同一行位与恢复键，只换措辞（防两套恢复入口并存）
  private statusLineText(): string {
    return this.msg.emptyRoundKind === 'no-text' ? '本轮没有文字回复' : '本轮没有产生回复';
  }

  // 推荐问题 chips 显隐总判据（「全与才显示」）：末条（tail）+ 非流式 + 建议非空。
  // ★ 「非 busy」由 tail + streaming 联合承载，不透传页级 busy（状态最小化 + 免 @Prop 级联）：
  // 新轮发送 push 首条消息即清全部 tail，流式占位自身 streaming=true——busy 窗口内本判据恒 false
  private suggestVisible(): boolean {
    return this.msg.tail === true && this.msg.streaming !== true &&
      (this.msg.suggestions ?? []).length > 0;
  }

  // 生成中饰件总判据：流式中的助手行 = 穿戴生成中饰件的窗口（蓝光标 + 提前工具栏与灰态）
  //——收尾（finishStream / settleRoundAssistant 置 streaming 假）经 @ObjectLink 重渲自动
  // 撤下，不新增刷新通路（同 barVisible/statusLineVisible/suggestVisible 判据族）
  private genDressingVisible(): boolean {
    return this.msg.kind === 'assistant' && this.msg.streaming === true;
  }

  // 长消息折叠显示判据：偏好开 + 终态 + 超阈值 + 用户未展开（longMsgExpanded——展开即最终
  // 意图，组件回收重建不回折）。终态口径 = bodyEndReason 在场，**不用 streaming**（工具等待期
  // 假终态陷阱）；流式期 bodyEndReason 恒 undefined 天然不折（流式红线：输出期间不整树换形态）；
  // 偏好渲染期现读 isLongMsgCollapseEnabled（AppStorage 现读，重进会话后生效）；阈值单源 =
  // MarkdownScrollableBlock.LONG_MSG_COLLAPSE_CHARS
  private longCollapseActive(): boolean {
    // 用户已展开 = 最终意图，任何判据不再折（组件回收重建也不回折）
    if (this.msg.longMsgExpanded === true) {
      return false;
    }
    // 流式期永不折（输出期间不整树换形态——流式红线）；重生成/续答另走新承载行或换源
    if (this.msg.streaming === true) {
      return false;
    }
    // 偏好关 = 进页全部展开（双态设计：关态由加载动画与分帧渐进揭示承担等待）
    if (!isLongMsgCollapseEnabled() || this.msg.text.length <= LONG_MSG_COLLAPSE_CHARS) {
      return false;
    }
    // 偏好开：进页收起（历史行 + 进页时点标记覆盖的复用行）。**进页后新完成的回复不折**
    //——用户正在读，生成结束瞬间突然收起会打断阅读；下次进页自然收起
    return this.msg.live !== true || this.msg.longMsgCollapseArmed === true;
  }

  // 尾先揭示判据：非占位形态的底锚进页末条消息先出尾部（首屏直接看到回答末尾）；占位形态
  //（展开/滚动挂载）内容不可见，恒头先无观感差
  private tailFirstReveal(): boolean {
    return this.msg.tail === true && this.msg.bodyPlaceholder !== true;
  }

  // 占位揭示判据：正文在 opacity 0 层背后逐帧建块、行内只显静态骨架；揭示完成由正文链
  // onRevealDone 清位。骨架/不透明度/触摸穿透三处共用本判据
  private placeholderActive(): boolean {
    return this.msg.bodyPlaceholder === true;
  }

  // 卡头行时间显隐：仅每轮回答卡——生成中 = 流式行；收尾后 = 操作栏宿主行（opsHost）。显隐在
  // 同一行内完成（行恒在）⇒ 零几何变化；时间取值 = msg.createdAt（轮起始时刻单源，
  // 见 ChatMessageHeader.formatMsgTime 注释）
  private answerTimeVisible(): boolean {
    return this.msg.kind === 'assistant' &&
      (this.msg.opsHost === true || this.msg.streaming === true);
  }

  // 消息时间总闸：偏好键已退役、时间显示恒开，不再有偏好关闭态；仅保留「时刻在场」数据判据
  // （老数据 createdAt 缺省整行不渲染零占位），两处显示点（用户提问上方时间行 / 助手回答卡头行）
  // 共用本判据，禁各自复制条件
  private messageTimeOn(): boolean {
    return (this.msg.createdAt ?? 0) > 0;
  }

  // 生成中工具栏「更多」键可用性：生成中仅正文非空时可用（空正文窗口无菜单可开——
  // ChatMoreMenu 场景 'none' 拒开口径的置灰态）；收尾/常驻形态恒可用（opsHost 行含历史异常
  // 轮恢复入口）。★ 真机修复（1593 节）：本判据只许在**无参** @Builder 键体属性表达式内经
  // this 直读（消费面 = MoreMenuKey 单处；2026-11-05 菜单笔后省略号变体已退役）——经值参数
  // 下传会被按值捕获冻结首值（收尾后驻留置灰、退出重进才恢复；官方 FAQ faqs-arkui-1078）
  private moreKeyInactive(): boolean {
    return this.genDressingVisible() && this.msg.text.trim() === '';
  }

  // 用户消息显示正文（拍板 5「显示层隐去」）：有附件简报且尾部标注逐字吻合 → 剥掉标注段
  //（附件泡已呈现名单，不重复）；无简报（导入恢复/老数据）→ 原样显示标注作回退。
  // **只改显示层**——复制键与协议文本仍用库内全文（msg.text）
  private displayBodyText(): string {
    const briefs = this.msg.attachBriefs;
    if (briefs === undefined || briefs.length === 0) {
      return this.msg.text;
    }
    const names: string[] = briefs.map((b): string => b.name);
    return hideAttachAnnotate(this.msg.text, names);
  }

  // ★ 用量气泡拆域：用量数据五方法与「Token 用量」气泡整域迁 ChatUsagePopup.ets（本件剔头
  // 越 1200 硬线，按宪法先拆本次功能域再动手，零行为变化）；本件只留 bindPopup 挂载点与用量键

  // 长按守卫（决明拍板「只在停止状态可长按复制」——生成中快照是半截文本，复制即误导；收口
  // 置假后即可复制，手动停止轮同享；user 行 streaming 恒 undefined 不受影响）；空文本无可复制。
  // 守卫内收（手势两泡恒挂、不满足静默不弹）而非手势条件分支——通用属性链上条件手势反而
  // 多写组件分支
  private requestCopySheet(): void {
    if (this.msg.streaming === true || this.msg.text === '') {
      return;
    }
    this.onCopyText(this.msg.id);
  }

  // 复制全文（决明指令「消息工具栏新增复制键，点击复制全文」）：口径与面板「复制全文」键
  // 默认档同源——纯文本（去表格 + 剥 md 标记，单源 buildCopySheetText）+ 助手全文附 AI 显式
  // 标识；剪贴板写入单源 = common/Clipboard。空 payload 守卫 = 消息只含表格被整块剔空——
  // 静默复制空串等于假成功，显式呈报（与面板 copyAll 同句）；长按面板路径保留不动。
  // DOMAIN 0xD5A1 复活原键日志域（0xD5A0 系已归 common/Clipboard 单源）
  private copyFullText(): void {
    const payload: string = buildCopySheetText(this.msg.text, true);
    if (payload === '') {
      this.getUIContext().getPromptAction().showToast({ message: '当前消息没有可复制的文字' });
      return;
    }
    try {
      copyTextToClipboard(this.getUIContext(), withAiContentLabel(payload), '已复制');
    } catch (e) {
      // 同步抛错中文呈报（异步失败已由 copyTextToClipboard 内 hilog + toast 两头承接）
      hilog.error(0xD5A1, 'ChatMessageItem', '复制全文失败：%{public}s', (e as Error).message);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
    }
  }

  // 用户泡正文：无条件新引擎（直吃已剥标注的显示原文）。
  build() {
    if (this.msg.kind === 'user') {
      // 用户消息两泡竖排（拍板 7：附件独立气泡、置于消息气泡之前）：外包裹 Column 先附件泡
      // 后消息泡，间距 ATTACH_BUBBLE_GAP——两泡同属本条消息（同一 ListItem，拆独立消息行即
      // 破坏回放装配归属，红线 §3-9）；用户侧操作不变（底栏「更多」键在位）
      Column({ space: ATTACH_BUBBLE_GAP }) {
        // 消息时间行（决明拍板）：用户侧只出时间、无头像，右对齐挂消息最上（有附件泡时在
        // 附件泡之上——消息级时间，与正文有无无关）；12fp 次要色。createdAt 缺省（老数据）
        // 整行不渲染零占位；时间显示恒开（偏好已退役），仅按时刻在场渲染（见 messageTimeOn）
        if (this.messageTimeOn()) {
          Row() {
            Text(formatMsgTime(this.msg.createdAt ?? 0))
              .fontSize(12)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .padding({ right: BUBBLE_PAD_NEAR })
          .justifyContent(FlexAlign.End)
        }
        // 引用摘要条（U-E）：用户气泡外、附件泡同层——被引用内容的已发标记。★ 本批不可点
        //（登记待拍板「后续补点击看全文」；做时复用 ChatQuoteSheet 弹只读查看）。形态 = 左条
        // 3vp + 近无感底（与 markdown 引用块/输入侧引用条三面一形；色值单源 quoteBlockBg/
        // quoteBarColor）。刷新承接 = @Observed(ChatMessage) + @ObjectLink 属性赋值触发行重渲
        //（attachBriefs 同通道先例），不进 LazyForEach 键（键纪律「别的刷新机制明确承接」）；
        // 回放链经重建天然携带
        if (this.msg.quoteText !== undefined && this.msg.quoteText !== '') {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.quote'))
              .fontSize(14)
              .fontColor([$r('sys.color.font_secondary')])
            Text('引用：' + quotePreviewOf(this.msg.quoteText, BUBBLE_QUOTE_PREVIEW_CHARS))
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width(BUBBLE_USER_MAX_WIDTH)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(12)
          .backgroundColor(quoteBlockBg(this.appColorMode))
          .border({ width: { left: 3 }, color: quoteBarColor(this.appColorMode) })
        }
        // 附件泡（有简报才挂，零占位；点击派发上行 ChatPageContent 分派预览）
        if ((this.msg.attachBriefs ?? []).length > 0) {
          AttachmentBubble({
            msg: this.msg,
            onPreviewAttach: (msgId: string, briefId: string): void => {
              this.onPreviewAttach(msgId, briefId);
            }
          })
        }
        // 消息泡：右对齐、浅蓝底（chatBubbleUserBg 单源，随卡底透明度档位叠 alpha）。★ 空文本
        // 规则（纯附件消息）：标注隐去后正文为空 → 整只不渲染（禁空气泡，只剩上方附件泡）。
        // 正文 = displayBodyText()，身份仍按 bodyBindingId 铸造，不依赖文本增量缓存。★ 宽度
        // 上限 = BUBBLE_USER_MAX_WIDTH 78%（60% → 增宽 30%；行内距不动，右缘贴位与右距不变、
        // 短消息泡仍随内容收缩）。★ 换行修复：上限**挂点**由气泡 constraintSize 改为外层定宽壳
        //——constraintSize 是测量后的钳制，泡内 Markdown 段落仍按父行全宽排版，泡一收窄内容
        // 就顶出右缘（官方尺寸设置取值表 + FAQ faqs-arkui-95 同族现象）；外壳显式 width 后
        // 壳宽即子组件**测量约束**，段落按上限换行、宽内容块（代码/表格自带横滚面）收在泡内横滚
        if (this.displayBodyText() !== '') {
          Row() {
            Blank()
            // 定宽壳：只承担宽度上限，不画底不设内距（气泡形制在下方共享内容列）；
            // alignItems(End) 让短泡贴壳右缘（位置与收窄前一致）
            Column() {
              Column() {
                // 用户消息同享进页收起（长消息不分角色——用户粘贴的超长文本同样付整树物化成本）。
                // ★ 一次出现笔：展开点击当帧正文未挂（longMsgExpanded 下一帧写），折叠门仍真
                //——此帧收起条位置先绘骨架（「骨架先实际绘制一帧再挂正文」铁律），下一帧挂
                // 正文后骨架移入下方叠层继续显示，揭示完成一次性显现
                if (this.longCollapseActive()) {
                  if (this.placeholderActive()) {
                    this.LongRevealSkeleton()
                  } else {
                    this.LongCollapseBar()
                  }
                } else {
                  // ── 正文 + 占位骨架叠层：占位揭示期正文层 opacity 0 在背后逐帧建块（布局
                  // 成本分摊、不绘制）、不响应触摸；骨架层贴顶显示。揭示完成 onRevealDone
                  // 清位 → 正文一次性显现、骨架撤下 ──
                  Stack({ alignContent: Alignment.TopStart }) {
                    ChatMarkdownBody({
                      bindingId: this.msg.bodyBindingId,
                      content: this.displayBodyText(),
                      live: false,
                      tailFirst: this.tailFirstReveal(),
                      placeholder: this.placeholderActive(),
                      aiContent: false,
                      compact: true,
                      darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
                      bodyFontFamily: this.resolveBodyFamily(),
                      codeFontFamily: this.resolveCodeFamily(),
                      onAnchor: (id: string): void => {
                        this.onMarkdownAnchor(id);
                      },
                      onRevealDone: (): void => {
                        this.msg.bodyPlaceholder = false;
                      },
                      onRevealPlaceholder: (placeholder: boolean): void => {
                        if (placeholder) {
                          this.msg.bodyPlaceholder = true;
                        }
                      }
                    })
                      .opacity(this.placeholderActive() ? 0 : 1)
                      .hitTestBehavior(this.placeholderActive() ? HitTestMode.None : HitTestMode.Default)
                    if (this.placeholderActive()) {
                      this.LongRevealSkeleton()
                    }
                  }
                  .width('100%')
                }
              }
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(chatBubbleUserBg(this.appColorMode, this.cardAlphaLevel))
              .borderRadius(BUBBLE_RADIUS)
              // 两路共享气泡长按，全文面板仍取 msg.text；定宽壳空档不响应，不以块级复制替代
              .gesture(LongPressGesture().onAction((_event: GestureEvent): void => {
                this.requestCopySheet();
              }))
            }
            .width(BUBBLE_USER_MAX_WIDTH)
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding({ left: BUBBLE_PAD_FAR, right: BUBBLE_PAD_NEAR })
          .justifyContent(FlexAlign.End)
        }
        // ── 底栏（user 气泡下方、右对齐侧——右缘与气泡行同距 BUBBLE_PAD_NEAR；纯附件消息
        // 同样可开菜单）：左侧提问版本步进器（编辑产出变体 ≥2 才显示；箭头切版本，计数位
        // 不可点——提问变体无面板承接）
        Row({ space: 2 }) {
          if ((this.msg.qsVersionCount ?? 0) >= 2) {
            Button() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .enabled((this.msg.qsPrevBranch ?? '') !== '')
            .opacity((this.msg.qsPrevBranch ?? '') !== '' ? 1.0 : 0.4)
            .onClick((): void => {
              this.onQuestionStep(this.msg.id, -1);
            })
            Text(((this.msg.qsVersionIndex ?? 0) + 1) + '/' + (this.msg.qsVersionCount ?? 1))
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .padding({ left: 4, right: 8 })
            Button() {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .enabled((this.msg.qsNextBranch ?? '') !== '')
            .opacity((this.msg.qsNextBranch ?? '') !== '' ? 1.0 : 0.4)
            .onClick((): void => {
              this.onQuestionStep(this.msg.id, 1);
            })
          }
          this.MoreMenuKey();
        }
        .width('100%')
        .padding({ right: BUBBLE_PAD_NEAR })
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      // 布局诊断描边（构建期开关，交付恒关——Theme.ets CHAT_LAYOUT_DEBUG）
      .borderWidth(CHAT_LAYOUT_DEBUG ? 1 : 0)
      .borderColor(Color.Orange)
      // 用户行为独立泡，上距 30 / 下距补 4（与助手项 CARD_SPACING 合成 14）——见 Theme 两常量注释
      .margin({ top: CHAT_ROUND_SPACING, bottom: CHAT_ASK_GAP - CARD_SPACING })
    } else if (this.msg.kind === 'assistant') {
      // ── 空正文收束轮：本轮尾部渲染轻量状态行——提示恒显，末条行带「重试」键（onRetryMsg
      // 单链上行），历史异常轮行由其 FinalOpsBar 重试图标键承载恢复（同链），不把空正文当
      // 成功终答。措辞按 msg.emptyRoundKind 分流（有过程产出 = 中性陈述「没有文字回复」；
      // 异常轮/零产出 = 「没有产生回复」）——同一行位、同一恢复键，只换文案
      if (this.statusLineVisible()) {
        Column({ space: 4 }) {
          // 轮头行：失败/中止轮同样带头行——头行是轮级身份（哪个模型失败一眼可见；本分支
          // 无回答卡承载时间，该轮不显示时间）
          if (this.msg.headHost === true) {
            ChatRoundHeader({
              modelLabel: this.msg.modelLabel ?? ''
            })
          }
          Row({ space: 8 }) {
            Blank()
            Text(this.statusLineText())
              .fontSize(13)
              .fontColor(cardDescColor())
            if (this.msg.tail === true) {
              Text('重试')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_warning'))
                .onClick((): void => {
                  this.onRetryMsg(this.msg.id);
                })
            }
            Blank()
          }
          .width('100%')
          if (this.msg.opsHost === true) {
            // 历史异常轮（非末条）：操作栏重试图标键即恢复入口（原经「更多」菜单「重新生成」，
            // 菜单项已随单链收敛退役）
            this.FinalOpsBar()
          }
        }
        .width('100%')
        .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
        .margin({ top: CARD_SPACING })
      } else {
        // 助手气泡：左对齐、卡片色底（深浅色自适应）。正文唯一走 ChatMarkdownBody（新引擎，
        // 不吃旧公式转义，流末/换源身份由 bodyBindingId 承接）；底栏唯一在 opsHost 行承载
        //（见 barVisible 与 FinalOpsBar）。★ 首段间距笔：外层 space 4 → 12（头行 → 气泡）
        //——Column 的 space 压过子组件主轴 margin，本值即唯一间距源；chips 与气泡随之
        // 4 → 12（同 space 单源无法分档，观感不适再拆嵌套）。
        Column({ space: 12 }) {
          // 轮头行（决明拍板）：本轮首个上屏项承载头像 + 模型名（判据 = 展示投影标记
          // msg.headHost，值单源在彼处）；段载轮头由 ChatProcessSegment 承载同件，两处互斥不重复
          if (this.msg.headHost === true) {
            ChatRoundHeader({
              modelLabel: this.msg.modelLabel ?? ''
            })
          }
          Row() {
            Column({ space: 8 }) {
              // ── 常驻卡头行（决明拍板）：左「AI 生成内容」恒显（所有助手正文卡同面孔——
              // 生成中/收尾后/历史回放/中途正文行）；右时间仅每轮回答卡显示（生成中 = 流式行；
              // 收尾后 = 操作栏宿主行），中途正文行只有字样——行恒在、时间文字零几何增减 ⇒
              // 收尾无跳变。蓝取官方强调色资源；时间格式/取值单源 = formatMsgTime +
              // msg.createdAt（轮起始时刻：实时链派发写入、回放链 alignRoundStartTimes 归一）──
              Row() {
                Text('AI 生成内容')
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_emphasize'))
                Blank()
                if (this.messageTimeOn() && this.answerTimeVisible()) {
                  Text(formatMsgTime(this.msg.createdAt ?? 0))
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                }
              }
              .width('100%')
              // ── 自动重试状态行：挂气泡内、正文之上——判据 = retryHint 非空（undefined/''
              // = 无重试，结构零变化）；纯文本一行，数字随次数原地更新不新增行。样式取组卡
              // 副标题规格（14fp 小字）+ 官方次要色资源（零自绘色值）──
              if (this.msg.retryHint !== undefined && this.msg.retryHint !== '') {
                Text(this.msg.retryHint)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
              }
              // ── 长消息折叠门：偏好开 + 终态 + 超阈值且用户未展开时，正文整树不上屏（跳过
              // 解析与组件构建），只出收起条；展开后正常渲染全文（ChatMarkdownBody 全量挂载，
              // 身份 = 既有 bodyBindingId）。★ 一次出现笔：展开点击当帧正文未挂——此帧收起条
              // 位置先绘骨架（「骨架先实际绘制一帧再挂正文」铁律），下一帧挂正文后骨架移入
              // 下方叠层继续显示，揭示完成一次性显现
              if (this.longCollapseActive()) {
                if (this.placeholderActive()) {
                  this.LongRevealSkeleton()
                } else {
                  this.LongCollapseBar()
                }
              } else {
                // 助手正文唯一入口：绑定/终态与显示帧分别传递，不吃旧公式转义。
                // ★ 外套 Stack 承蓝光标叠层——正文恒 100% 宽、包装层零 key 不加条件（不触发
                // 重挂；文档渲染/绑定/@Monitor 链/入场动画零适配）
                Stack({ alignContent: Alignment.BottomStart }) {
                  ChatMarkdownBody({
                    bindingId: this.msg.bodyBindingId,
                    content: this.msg.text,
                    endReason: this.msg.bodyEndReason,
                    live: this.msg.live === true && this.msg.streaming === true,
                    tailFirst: this.tailFirstReveal(),
                    placeholder: this.placeholderActive(),
                    displayBudget: this.msg.displayBudget,
                    // DS 来源角标（S3③，可选入参——非官方档轮空数组零渲染零行为变化）
                    citations: this.dsCitations(),
                    darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
                    bodyFontFamily: this.resolveBodyFamily(),
                    codeFontFamily: this.resolveCodeFamily(),
                    onAnchor: (id: string): void => {
                      this.onMarkdownAnchor(id);
                    },
                    // 角标点击 → 来源卡行锚点（宿主既有 scrollToMarkdownAnchor 链几何滚动
                    //——序号换算单源 = dsSourceEntryAnchorId）。★ 来源卡折叠笔：收起态条目
                    // 锚点不在树上，先展开再滚——展开动画 220ms（200ms 动画 + 一帧余量）后
                    // 条目就位转发滚动；已展开照旧即滚。★ 延时句柄落成员位、离场清（1712
                    // 销毁守卫：迟到回调会向已销毁行上行滚动 → 取 UIContext 抛错/滚空，
                    // 且裸 setTimeout 无主可清）
                    onCitation: (entry: number): void => {
                      // 来源在场判据不再解析（#13：解析在 ChatSourceCard 内；此处只需知道
                      // 有没有来源载荷——无载荷则锚点也不存在，直接滚会滚空）
                      if (this.msg.dsSourcesExpanded !== true &&
                        (this.msg.serverToolsJson ?? '') !== '') {
                        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut },
                          (): void => {
                            this.msg.dsSourcesExpanded = true;
                          });
                        this.cancelDsExpandTimer();
                        this.dsExpandTimer = setTimeout((): void => {
                          this.dsExpandTimer = -1;
                          this.onMarkdownAnchor(dsSourceEntryAnchorId(this.msg.id, entry));
                        }, 220);
                        return;
                      }
                      this.onMarkdownAnchor(dsSourceEntryAnchorId(this.msg.id, entry));
                    },
                    // 分帧揭示完成（或正文组件回收）→ 解除本行占位标记，宿主恢复行高回报与
                    // 锚态重评，正文一次性显现、骨架撤下
                    onRevealDone: (): void => {
                      this.msg.bodyPlaceholder = false;
                    },
                    // 滚动暂停期挂载由正文链自行进入占位（骨架先出，停止滚动后背后建块）
                    onRevealPlaceholder: (placeholder: boolean): void => {
                      if (placeholder) {
                        this.msg.bodyPlaceholder = true;
                      }
                    }
                  })
                    .opacity(this.placeholderActive() ? 0 : 1)
                    .hitTestBehavior(this.placeholderActive() ? HitTestMode.None : HitTestMode.Default)
                  // 占位骨架：贴 Stack 顶、盖在 opacity 0 的正文层上方；揭示完成清位一并撤下
                  if (this.placeholderActive()) {
                    this.LongRevealSkeleton()
                  }
                  // 生成中蓝光标（判据 = streaming；收尾经 @ObjectLink 重渲即撤）：零排版装饰
                  //——绘制在正文块下沿外侧空档内，不占水平/垂直布局 ⇒ 撤下零位移、不压字、
                  // 不改断行、文字恒现于光标上一排；HitTestMode.None 不吞气泡长按手势
                  if (this.genDressingVisible()) {
                    Row()
                      .width(GEN_CURSOR_WIDTH_VP)
                      .height(GEN_CURSOR_HEIGHT_VP)
                      .borderRadius(GEN_CURSOR_RADIUS_VP)
                      .backgroundColor($r('sys.color.comp_background_emphasize'))
                      .offset({ y: GEN_CURSOR_OFFSET_Y_VP })
                      .hitTestBehavior(HitTestMode.None)
                  }
                }
                .width('100%')
              }
              // ── 截断尾注：挂气泡内、正文之下——与上方 retryHint 状态行一上一下对称。判据 =
              // truncated 恰 true（undefined/false = 无截断，结构零变化）；样式照 retryHint 行
              // 同款。**只追加一行、不改写正文**（渲染刷新红线：「非前缀整段替换」才须换绑定/
              // 推进世代）；判据只认真截断（responses 侧收窄到 max_output_tokens，内容过滤不
              // 挂键），故「提高上限/降低档位」文案恒与真因一致 ──
              if (this.msg.truncated === true) {
                Text('输出被上限截断，可提高输出上限或降低思考档位')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
              }
              // ── 气泡内底部工具栏：收束后在 opsHost 行唯一承载；生成中提前显示（挂载支 =
              // opsHost 或流式行），原本中途不可用的键置灰不可点（灰态在各键内按生成中判据
              // 收口），收尾逐键回现状守卫 ──
              if (this.barVisible() || this.genDressingVisible()) {
                this.FinalOpsBar()
              }
              // ★ 2026-11-05 菜单笔：原「中间正文单键」分支整条删除（省略号「更多」键 +
              // 气泡内右下角 Row）——复制正文/查看正文由长按全文面板覆盖，中间正文行不再
              // 挂任何气泡内操作键；空正文异常行的恢复入口不变（轻量状态行重试键 / 操作栏「更多」）
            }
            // 气泡形制统一挂内容列（内边距/底色/圆角/宽度上限；过程段与正文各自独立泡）。
            // ★ 档位关 = 内距 0 + 底色透明 + 圆角 0
            .padding({ left: this.bubbleVisible ? 14 : 0, right: this.bubbleVisible ? 14 : 0,
              top: this.bubbleVisible ? 10 : 0, bottom: this.bubbleVisible ? 10 : 0 })
            .backgroundColor(this.bubbleVisible ? cardBg(this.appColorMode, this.cardAlphaLevel) : Color.Transparent)
            .borderRadius(this.bubbleVisible ? BUBBLE_RADIUS : 0)
            .constraintSize({ maxWidth: '100%' })
            // 长按开「消息全文」面板（旧渲染器逐段复制已随件删除，长按在气泡层恒为该手势）
            .gesture(LongPressGesture().onAction((_event: GestureEvent): void => {
              this.requestCopySheet();
            }))
            Blank()
          }
          .width('100%')
          // 布局诊断描边（构建期开关，交付恒关——Theme.ets CHAT_LAYOUT_DEBUG）
          .borderWidth(CHAT_LAYOUT_DEBUG ? 1 : 0)
          .borderColor(Color.Green)
          // ── 来源卡（S3② 折叠卡，二期 S4 #13 迁 ChatSourceCard）：判据只看列载荷在场；
          // 条目集合与渲染全在子件（父件不再为「有没有条目」跑解析）。展开意愿仍走
          // msg.dsSourcesExpanded，卡头点击先上行钉顶再改值——与拆分前同序
          if (this.msg.kind === 'assistant' && (this.msg.serverToolsJson ?? '') !== '') {
            ChatSourceCard({
              serverToolsJson: this.msg.serverToolsJson ?? '',
              msgId: this.msg.id,
              expanded: this.msg.dsSourcesExpanded === true,
              bodyFamily: this.resolveBodyFamily(),
              appColorMode: this.appColorMode,
              cardAlphaLevel: this.cardAlphaLevel,
              onToggle: (): void => {
                this.onPresentationChange(this.msg.id);
                this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
                  this.msg.dsSourcesExpanded = this.msg.dsSourcesExpanded !== true;
                });
              },
              onOpenUrl: (url: string): void => {
                this.openSourceUrl(url);
              }
            })
          }
          // ── 推荐问题 chips：挂外层 Column 内、气泡 Row 之后 = 气泡卡外下方（左右 padding
          // 与气泡同缘对齐——chips 独立于卡片底与圆角，长建议换行不撑泡）；点击去向按偏好
          // 分流在 ChatPageContent ──
          if (this.suggestVisible()) {
            ChatSuggestBar({
              suggestions: this.msg.suggestions ?? [],
              onPick: (text: string): void => {
                this.onSuggestTap(text);
              }
            })
          }
        }
        .width('100%')
        // ★ 决明「助手的右边距缩短与左边距统一」：两侧同取 BUBBLE_PAD_NEAR
        .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
        // 正文气泡与过程段各自独立（不切角拼接），上距恒 CARD_SPACING
        .margin({ top: CARD_SPACING })
      }
    } else if (this.msg.kind === 'summary') {
      // 压缩摘要提示行：一行高的**持久**轻提示——与 notice 同款居中式样，但本行**落库**
      //（notice「不落库」惯例不适用——它标记会话的持久压缩状态，重进会话由回放重建）；文案
      // 固定（msg.text 存摘要正文，展示不用它——正文在用量面板折叠区看）；整行可点 → 打开
      // 上下文用量面板。★ 渲染判据 = **覆盖边界在场**（coversToSeq 由投影层按 summary_bindings
      // 绑定投影；图软删只删 binding 留文本行——无绑定的档案行不得再报「已压缩」，否则提示行
      // 复活而面板报未压缩）。无绑定行整行不渲染：不删数据、不动读侧
      if (this.msg.coversToSeq !== undefined) {
        Row() {
          Blank()
          Text('上下文已压缩，摘要见上下文用量')
            .fontSize(11)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
        }
        .width('100%')
        .margin({ top: CARD_SPACING })
        .onClick((): void => {
          this.onOpenUsage();
        })
      }
    } else if (this.msg.kind === 'clear') {
      // 上下文清空分隔条：左右横线夹一行小字，标出「这条线之前的内容不再进请求」的分界
      //（分界之前的消息仍在本行之上可见可回看，非破坏式）。渲染判据与 summary 行同款——
      //**覆盖边界在场才渲染**（coversToSeq 由投影层按 summary_bindings 绑定投影；撤销清空
      // 只删 binding 留文本行——无绑定的档案行不得再标分界，即 E-3 同族缺陷）。整行可点 →
      // 打开上下文用量面板（复用 onOpenUsage 既有上行链）
      if (this.msg.coversToSeq !== undefined) {
        Row({ space: 8 }) {
          Divider()
            .strokeWidth(1)
            .color(cardBorderColor(this.appColorMode))
            .layoutWeight(1)
          Text('已清空上下文')
            .fontSize(11)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Divider()
            .strokeWidth(1)
            .color(cardBorderColor(this.appColorMode))
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: CARD_SPACING })
        .onClick((): void => {
          this.onOpenUsage();
        })
      }
    } else {
      // notice：居中提示条（连接状态/错误提示等）。★ msg.noticeAction 非空 = 整行可点（行尾
      //「›」提示可点，文字字符非自绘图标、同 11fp 灰阶）——onClick 常挂、回调内判空
      //（ArkUI 链式属性无条件挂法；无动作时点击空转、无按压反馈，可见行为与不可点逐字一致）
      Row() {
        Blank()
        Text(this.msg.text)
          .fontSize(11)
          .fontColor(this.msg.level === 'error' ? $r('sys.color.ohos_id_color_warning') : cardDescColor())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.msg.noticeAction !== undefined) {
          Text(' ›')
            .fontSize(11)
            .fontColor(cardDescColor())
        }
        Blank()
      }
      .width('100%')
      .margin({ top: CARD_SPACING })
      .onClick((): void => {
        if (this.msg.noticeAction !== undefined) {
          this.onNoticeAction(this.msg.noticeAction);
        }
      })
    }
  }

  // 长消息收起条：终态评估命中的长正文折叠态占位——说明行 + 展开键（收起是默认态，展开即
  // 用户最终意图，无反向收起键）。形制照 AutoCollapseBar 范式（行内裸键族：TEXTUAL 无底 +
  // font_secondary 官方次要色，不自绘底色/圆角/按压）；键内状态直读组件 this（可变状态不进
  // @Builder 值参——坑16 家族/1593 实锤）；展开动作 = 原地写 msg.longMsgExpanded（@Observed
  // 对象级观察驱动重渲，同 suggestions/attachBriefs 写点族）
  @Builder
  LongCollapseBar() {
    Row({ space: 8 }) {
      Text(this.msg.kind === 'user' ? '这条消息较长，已收起' : '这条回复较长，已自动收起')
        .fontSize(13)
        .fontColor(cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
          Text('展开全文')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(VerticalAlign.Center)
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .accessibilityText('展开全文')
      .onClick((): void => {
        // 展开是阅读动作（★ 一次出现笔）：宿主停进页校正/跟随、置阅读期底锚冻结并把该行滚
        // 到视口顶部；本行当帧只置占位并绘骨架——骨架先实际绘制一帧，下一帧才挂正文（动画
        // 不得盖住被阻塞主线程）；正文随后在占位层背后逐帧建块，揭示完成一次性显现
        this.onLongMessageExpand(this.msg.id);
        this.msg.bodyPlaceholder = true;
        this.expandFrame?.cancel();
        const frame: ChatExpandFrame = new ChatExpandFrame((): void => {
          this.msg.longMsgExpanded = true;
        });
        this.expandFrame = frame;
        this.getUIContext().postFrameCallback(frame);
      })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  // 占位骨架：长正文占位构建期的静态灰条——不挂逐帧动画（动画不得盖住被阻塞主线程），贴
  // Stack 顶部（.align 覆盖 Stack 的 alignContent）；覆盖在 opacity 0 的正文层上方，揭示
  // 完成由宿主清 bodyPlaceholder 一并撤下。灰条取官方交互灰语义色（comp_background_tertiary，
  // 仓内三处真机同色先例）
  @Builder
  LongRevealSkeleton() {
    Column({ space: LONG_REVEAL_SKELETON_GAP }) {
      Row()
        .width('100%')
        .height(LONG_REVEAL_SKELETON_BAR_HEIGHT)
        .borderRadius(LONG_REVEAL_SKELETON_RADIUS)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
      Row()
        .width('86%')
        .height(LONG_REVEAL_SKELETON_BAR_HEIGHT)
        .borderRadius(LONG_REVEAL_SKELETON_RADIUS)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
      Row()
        .width('58%')
        .height(LONG_REVEAL_SKELETON_BAR_HEIGHT)
        .borderRadius(LONG_REVEAL_SKELETON_RADIUS)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4 })
    .align(Alignment.TopStart)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityText('内容加载中')
  }

  // 用量气泡宿主（★ 闪退修复，真机实锤）：bindPopup 的 builder 是**普通箭头函数**，ets
  // 编译器只在 build() 与 @Builder 体内把自定义组件语法糖 `Foo({...})` 转译为 `new Foo(...)`；
  // 把 `ChatUsagePopup({ msg: this.msg })` 直接写在箭头函数里，运行期按「无 new 调用类构造器」
  // 抛 TypeError、应用当场 JsError 退出。故组件创建落在本 @Builder 体内、箭头函数只转发调用
  //——禁再把组件调用搬回箭头函数
  @Builder
  UsagePopupHost() {
    ChatUsagePopup({ msg: this.msg });
  }

  // 本轮消息级操作栏（正常完成/历史较早轮的最终正文都在该轮末尾唯一承载；生成中提前显示
  //——流式行同渲染本栏，中途不可用的键置灰不可点，收尾逐键回现状守卫）。内容 = 用量键
  //（有账本值才可点；生成中挂灰态占位）+ 复制键（非空文本才可点；生成中即复制已揭示前缀）
  // + 重试键（末条且收束后——历史轮重生成走「更多」菜单）+「更多」键（生成中仅正文非空时
  // 可用）。宽度写法仍 = 写作①（不设百分比宽度、不加 Blank）；对齐 = alignSelf(ItemAlign.End)
  // 挂气泡右缘、从右下角向左排
  @Builder
  FinalOpsBar() {
    Row({ space: 12 }) {
      // 用量键（拍板 6：点击弹气泡；usageTokens 在场才挂——无用量协议天然不弹空气泡）。
      // ★ 注释核正：中断/失败轮同落账本（error 收尾同落同显），轮内已有完整收尾段时照挂值
      // 仍会弹气泡，勿据旧注把挂载守卫当误改删回。符号 = data_proportion（与设置页「用量
      // 统计」行卡同款；键形仍是 TEXTUAL 图标键、字号取底栏统一 16fp）。气泡 builder 直读
      // this.msg（坑57 按值传参规避）；挂载支扩「或生成中」（灰态占位），可点守卫 = 有账本值
      //（生成中无值 ⇒ 置灰不可点——防弹空气泡契约由 enabled 承接）
      if (this.msg.usageTokens !== undefined || this.genDressingVisible()) {
        Button() {
          SymbolGlyph($r('sys.symbol.data_proportion'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .enabled(this.msg.usageTokens !== undefined)
        .opacity(this.msg.usageTokens !== undefined ? 1.0 : 0.4)
        .onClick((): void => {
          this.usagePopupShow = !this.usagePopupShow;
        })
        // 右下锚定后用量键在屏右半区：placement = BottomRight（右缘对齐向左展开；220 宽气泡
        // 窄屏个别键位放不下时由系统「显示不下自动调整位置」避让兜底）
        // 气泡内容 = ChatUsagePopup 独立件（拆域笔整域迁出，本处只留挂载点；组件内
        // @ObjectLink 直读同一 msg 对象——坑57 不适用）。★ 组件创建必须经 @Builder
        //（UsagePopupHost）转发，禁在箭头函数内直接调用——非 UI 上下文不转译 new，运行期
        // TypeError 闪退
        .bindPopup(this.usagePopupShow, {
          builder: (): void => {
            this.UsagePopupHost();
          },
          placement: Placement.BottomRight,
          // 弹层族材质（决明指令「气泡全 thick」；「无」档 = 材质关闭，回落官方默认形态）
          systemMaterial: overlayMaterial(),
          onStateChange: (event: PopupStateChangeParam): void => {
            if (!event.isVisible) {
              this.usagePopupShow = false;
            }
          }
        })
      }
      // 复制键（★ 决明指令复活：消息工具栏一键复制全文——原退役迁长按面板〔面板保留自由
      // 选择〕，恢复后两入口并存；口径 = 面板「复制全文」默认档，见 copyFullText）。空文本
      // 不挂：防复制空气泡；图标沿用原键 checkmark_square_on_square〔SDK sysResource 符号表
      // 实名核过〕。挂载支扩「或生成中」；可点守卫 = 非空文本（生成中即复制已揭示前缀，与
      // 中途单键菜单「复制正文」既有口径一致；空文本恒灰）
      if (this.msg.text !== '' || this.genDressingVisible()) {
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .enabled(this.msg.text !== '')
        .opacity(this.msg.text !== '' ? 1.0 : 0.4)
        .onClick((): void => {
          this.copyFullText();
        })
      }
      // ★ 2026-10-09 消息菜单入口笔：原位「其他回答」文字键随入口迁消息「更多」菜单退役，
      // 菜单项又随行内步进器上线退役。★ 2026-11-15 续写收入菜单笔：行内续写键随入口迁消息
      //「更多」菜单退役（唯一入口在菜单，判据单源 ChatContinueSupport 不变）。本栏键序自此 =
      // 用量 → 复制 → 版本步进 → 重试 → 更多
      // ── 回答版本步进器 ──
      // 显示判据 = ansVersionCount ≥ 2（<2 零渲染——恒显 1/1 只添噪；运行时字段由
      // ChatAnswerCtrl 重算写入，@Observed 驱动）；流式中不渲染（重算挂轮落库后，流式期本值
      // 未定）。形制 = 行内裸键族（TEXTUAL 无底图标键 + 次要色计数文字；chevron 符号已核）；
      // 边界侧箭头置灰不可点（ansPrev/ansNext 空 = 已在边界）。左右箭头 = 切上一/下一版本
      //（onAnswerStep）；计数位可点 = 打开「其他回答」面板（onAnswerPanel——删除此版本与
      // 全文预览在面板内承接）
      if ((this.msg.ansVersionCount ?? 0) >= 2 && !this.genDressingVisible()) {
        Row({ space: 2 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .enabled((this.msg.ansPrevBranch ?? '') !== '')
          .opacity((this.msg.ansPrevBranch ?? '') !== '' ? 1.0 : 0.4)
          .onClick((): void => {
            this.onAnswerStep(this.msg.id, -1);
          })
          Text(((this.msg.ansVersionIndex ?? 0) + 1) + '/' + (this.msg.ansVersionCount ?? 1))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 4, right: 4 })
            .onClick((): void => {
              this.onAnswerPanel(this.msg.id);
            })
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .enabled((this.msg.ansNextBranch ?? '') !== '')
          .opacity((this.msg.ansNextBranch ?? '') !== '' ? 1.0 : 0.4)
          .onClick((): void => {
            this.onAnswerStep(this.msg.id, 1);
          })
        }
      }
      // 重试键：判据 = barVisible（assistant + opsHost，含历史轮与空失败轮收束后）——扩到
      // 全部答案行，重试唯一入口（历史轮重生成不再经「更多」菜单〔菜单项随单链收敛退役〕）；
      // 图会话重试 = 替代分支（旧答案留在旧分支路径可切回查看）。挂载支扩「或生成中」（流式
      // 行 tail 常真，靠生成中判据压灰——「未收束不给用」）；可点守卫 = 答案行且非生成中
      if (this.barVisible() || this.genDressingVisible()) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .enabled(this.barVisible() && !this.genDressingVisible())
        .opacity(this.barVisible() && !this.genDressingVisible() ? 1.0 : 0.4)
        .onClick((): void => {
          this.onRetryMsg(this.msg.id);
        })
      }
      // 「更多」键（锚点 = 前缀 + 消息 id，ChatPage 侧 ChatMessageMenuHost 消费）。★ 复制键
      // 沿革：退役迁长按面板 → 决明指令复位（两入口并存，「退役」表述仅存沿革义，见上方
      // 复制键注释与 copyFullText）。键体收 @Builder MoreMenuKey（与 user 分支共用，形制单源）；
      // 生成中空正文窗口置灰（灰态判据收键体属性表达式内直读——无参 builder 通道，见键段注释）
      this.MoreMenuKey();
    }
    .margin({ top: 6 })
    .alignSelf(ItemAlign.End)
  }

  // 消息底栏「更多」键：**两处**消费面（user 行 / 轮尾操作栏）共用键体形制 = 单源：
  // SymbolGlyph 无底 TEXTUAL 图标键 + font_secondary + 锚点 id（openMenu 的 TargetInfo 定位
  // 目标，ChatMessageMenuHost 按同一前缀拼接）+ onMoreMenu 上行。一条消息只渲染一个分支 ⇒
  // 锚点恒唯一（user 行若无挂点，「编辑/创建分支/复制为新会话」对 user 消息整链不可达——
  // 见 ChatMoreMenu.callbacksFor.showEdit）。
  // ★ 拆域笔后「位置须在 build() 之后」的约束已随用量气泡迁出失效，键体留原位不动（禁顺手
  // 大重构）。★ 2026-11-05 菜单笔：中间正文行的省略号变体（原 MoreMenuKeyEllipsis）随两处
  // 入口退役删除，本件只剩 dot_grid_2x2 四点网格一形；禁自绘椭圆底/边框/实底。
  // ★ 生成中空正文窗口置灰：**无参** builder 通道——有参 builder 的值参数按值捕获、不随状态
  // 刷新（官方 FAQ faqs-arkui-1078 按值传递表；首版即因此收尾驻留置灰，1593 节真机修复），
  // 故灰态判据在键体属性表达式内经 this 直读（moreKeyInactive），随状态即时刷新
  @Builder
  MoreMenuKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .enabled(!this.moreKeyInactive())
    .opacity(this.moreKeyInactive() ? 0.4 : 1.0)
    .id(MESSAGE_MENU_ANCHOR_PREFIX + this.msg.id)
    .onClick((): void => {
      this.onMoreMenu(this.msg.id);
    })
  }

  // ★ 2026-11-05 菜单笔：原 `MoreMenuKeyEllipsis`（中间正文行省略号变体）随两处入口退役
  // 整件删除——本件只剩 dot_grid 主形一枚键体（user 行 / 轮尾操作栏共用）。
  // 灰态判据仍在该键体属性表达式内经 this 直读（无参 builder 通道，见上方键段注释）
}
