// 底部输入位托管组件（2026-11-08 输入位接管笔）：职责一句话 = 等待用户拍板的提问卡/确认卡
// 在等待期接管底部输入位，默认压成细条（S1），点开成面板（S2），作答或终态即把输入位还回。
// 三态归本件自持（@State expanded），页面只管挂不挂；卡体仍由原卡件的 docked 档渲染，
// 本件不复制题干、选项、键区任何一行，也不碰 ask_user / browse_act 协议与续答链。
// 底带：根容器 onAreaChange 自报上沿，喂宿主同一口 readingViewport.input（与输入栏同口径）；
// 输入栏隐藏期间其自身上报由宿主加 dockVisible 守卫，防 0/旧值把底带塌到 0。
// 键盘：挂载期切官方 KeyboardAvoidMode.RESIZE（贴底面板 + 自由文本框的处方，照
// ChatInputBar 焦点期做法），卸载与收起复原 RESIZE_WITH_CARET；keyboardHeightChange 的
// on/off 成对，键盘态底部留白归 0。生命周期成对释放见 aboutToDisappear。
// ★ 动效（2129）：只做渲染层（挂载后淡入 / 面板自底边轻缩入），**不做高度动画**——细条⇄
// 面板的布局仍是同帧落定（方案档 §5.2 与坑26 口径不变）；收起方向照全项目「直写」纪律。
import { display, KeyboardAvoidMode, window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AI_CONTENT_LABEL } from '../../common/AiDisclosure';
import { BUBBLE_RADIUS, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  fallbackGrayBg } from '../../common/Theme';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../../common/AppPreferences';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';
import { ChatMessage, isAskCard, isStepAwaitingUser, toolStepIcon } from './ChatMessageCompose';
import { AskQuestion, ChatAskUserCard, parseQuestions } from './ChatAskUserCard';
import { ChatBrowseConfirmCard } from './ChatBrowseConfirmCard';
import { DOCK_STRIP_INSET, DOCK_STRIP_HEIGHT, DOCK_STRIP_RADIUS,
  DOCK_COMPLIANCE_HEIGHT } from './ChatInputBar';
import { DOCK_CONFIRM_TITLE, askAnsweredOfDraft, askDockTitle } from './ChatDockTitles';
// 减弱动态效果门控（与过程段/正文同源）：读系统「动画程序时长缩放 / 移除动画」开关
import { markdownMotionEnabled } from './ChatMarkdownBody';

// 面板上限 = 屏高 vp × 0.55（决明拍板「展开高度 ≤ 55% 屏高 + 内部滚动」）
const PANEL_MAX_RATIO: number = 0.55;
// 面板固定部位预算（头行 / 上下内距 / 键区两档）：滚动区 maxHeight 由本件算好后下发卡件，
// 卡件只做 constraintSize，不做屏幕算术（面板高度只有 maxHeight 约束，layoutWeight 语义不定）
const DOCK_HEAD_HEIGHT: number = 48;
const DOCK_PADDING_V: number = 24;
const DOCK_ASK_KEYS_BUDGET: number = 112;
const DOCK_CONFIRM_KEYS_BUDGET: number = 168;
const DOCK_BODY_MIN: number = 80;
// 单题分页题干区最小高（2128 笔）：分页后切题不再让面板高度随题跳——下限取「题型行 +
// 三四行题干 + 一行选项 + 输入框」的常见高度；只作 constraintSize.minHeight，仍以
// dockBodyMax 封顶（面板不设死高，坑26 红线）
const DOCK_ASK_BODY_MIN: number = 180;
// 进场动效时长（2129）：挂载后淡入与面板轻缩入共用一档；只动 opacity / translate / scale
const DOCK_ENTER_ANIM_MS: number = 140;
// 挂载首帧的上移距离（vp）：终点 = 0，入场由下往上 6vp 之内
const DOCK_ENTER_OFFSET: number = 6;

@Component
export struct ChatAskDock {
  // @ObjectLink 观察同一 msg 的全部字段：草稿 / toolState / dockOwned 改一处，细条、面板与
  // 流内头行同时刷新，零新通道。@Watch 只兜「外部停止 / 换源」之类终态释放（比 @Link 晚
  // 一拍，作答路径走同帧 onDismiss，确定性不受影响）
  @ObjectLink @Watch('onMsgChanged') msg: ChatMessage;
  // 新卡身份：@Prop + @Watch 保证「新卡恒落 S1」——组件被复用、@ObjectLink 换了对象时
  // 也能把展开态复位，不同卡不继承展开态
  @Prop @Watch('onDockKeyChanged') dockKey: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  @State private expanded: boolean = false;
  @State private keyboardOn: boolean = false;
  // 渲染层进场位（2129）：enterIn = 整卡首次挂载后的淡入；panelIn = 细条→面板的轻缩入。
  // 两者都不参与布局测量（高度仍由内容驱动）；panelIn 随收起/换卡复位、enterIn 无复位点
  //——整卡重播靠「释放帧 dockMsg 置空 → 条件卸载重建」达成（换卡必经释放帧，同帧换卡形态
  // 不存在），enterIn 保持 true 时组件从未卸载、无需重播
  @State private enterIn: boolean = false;
  @State private panelIn: boolean = false;
  // 常态底部留白（页面注入，与输入栏同源）；键盘弹起置 0
  bottomPad: number = 0;
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  // 释放单入口（宿主清 dockVisible / dockMsg / msg.dockOwned）
  onDismiss: () => void = (): void => {};
  onReadingTop: (top: number) => void = (top: number): void => {};
  private panelMax: number = 0;
  private windowRef: window.Window | null = null;
  private departed: boolean = false;
  // 题数解析记忆化（构建期禁高耗：细条与面板头行都读题数，同 inputJson 只解析一次）
  private questionsCacheJson: string = '';
  private questionsCache: AskQuestion[] = [];

  private onKeyboardHeight = (height: number): void => {
    const on: boolean = height > 0;
    if (on !== this.keyboardOn) {
      this.keyboardOn = on;
    }
  };

  aboutToAppear(): void {
    this.departed = false;
    this.panelMax = Math.round(this.getUIContext().px2vp(display.getDefaultDisplaySync().height) *
      PANEL_MAX_RATIO);
    // 托管位常驻期用压缩避让：面板贴底，内部自由文本框聚焦时键盘抬起面板而非压住键区。
    // 失焦/退页由 aboutToDisappear 幂等复原（挂载时输入栏已隐藏，二者不抢同一窗口级模式）
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window): void => {
      if (this.departed) {
        return;
      }
      this.windowRef = win;
      win.on('keyboardHeightChange', this.onKeyboardHeight);
      this.keyboardOn = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height > 0;
    }).catch((err: Error): void => {
      hilog.error(0xD5A0, 'ChatAskDock', 'keyboard listen failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    if (this.windowRef !== null) {
      this.windowRef.off('keyboardHeightChange', this.onKeyboardHeight);
      this.windowRef = null;
    }
  }

  private onMsgChanged(): void {
    if (!isStepAwaitingUser(this.msg)) {
      this.onDismiss();
    }
  }

  private onDockKeyChanged(): void {
    this.expanded = false;
    this.panelIn = false;
  }

  // 整卡进场（挂载首帧在 build 取 opacity 0 / 下移 6，onAppear 后再动画到终点）：只改渲染
  // 属性，承载高度与列表让位同帧落定——不走布局动画（faqs-arkui-1400 的中间帧问题），也
  // 不干扰 onAreaChange 的上沿上报；减弱动态效果时直落终点（与过程段同一门控）
  private playEnter(): void {
    if (this.enterIn) {
      return;
    }
    if (!markdownMotionEnabled()) {
      this.enterIn = true;
      return;
    }
    this.getUIContext().animateTo({ duration: DOCK_ENTER_ANIM_MS, curve: Curve.EaseOut },
      (): void => {
        this.enterIn = true;
      });
  }

  // 细条 → 面板（只展开方向）：面板已按终高挂载，内容自底边 0.98 缩放入位并淡入。收起不做
  // 反向——面板同帧卸载，与工具卡/过程段「收起直写」同一判据（插值只会留空盒）
  private playPanelIn(): void {
    if (this.panelIn) {
      return;
    }
    if (!markdownMotionEnabled()) {
      this.panelIn = true;
      return;
    }
    this.getUIContext().animateTo({ duration: DOCK_ENTER_ANIM_MS, curve: Curve.EaseOut },
      (): void => {
        this.panelIn = true;
      });
  }

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  private questions(): AskQuestion[] {
    const inputJson: string = this.msg.toolInputJson ?? '';
    if (inputJson !== this.questionsCacheJson) {
      this.questionsCacheJson = inputJson;
      this.questionsCache = parseQuestions(inputJson);
    }
    return this.questionsCache;
  }

  private isAsk(): boolean {
    return isAskCard(this.msg);
  }

  private title(): string {
    return this.isAsk() ? askDockTitle(this.questions().length) : DOCK_CONFIRM_TITLE;
  }

  // 细条右侧进度（多题才显；与流内头行徽章同一 msg.askDraft 现算，零第二份草稿）
  private progress(): string {
    if (!this.isAsk()) {
      return '';
    }
    const total: number = this.questions().length;
    if (total <= 1) {
      return '';
    }
    return '已答 ' + askAnsweredOfDraft(this.msg.askDraft, total) + ' / ' + total;
  }

  private dockBodyMax(): number {
    const keysBudget: number = this.isAsk() ? DOCK_ASK_KEYS_BUDGET : DOCK_CONFIRM_KEYS_BUDGET;
    return Math.max(DOCK_BODY_MIN, this.panelMax - DOCK_HEAD_HEIGHT - keysBudget -
      DOCK_COMPLIANCE_HEIGHT - DOCK_PADDING_V);
  }

  // 题干区最小高（仅提问卡分页用）：min ≤ max，小屏/分屏时自动退化为 max（不越上限）
  private dockBodyMin(): number {
    return Math.min(this.dockBodyMax(), DOCK_ASK_BODY_MIN);
  }

  // 收起先清焦点再压条：文本框仍聚焦时键盘会留在细条上方，官方 FocusController.clearFocus
  // 是无组件 id 依赖的统一清焦口；键盘避让模式由卸载/复原链兜底，不在此重复切换
  private collapse(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
      hilog.warn(0xD5A0, 'ChatAskDock', 'clearFocus unavailable: %{public}s',
        (e as Error).message);
    }
    this.expanded = false;
    this.panelIn = false;
  }

  private answer(callId: string, answerJson: string): void {
    this.onDismiss();
    this.onAskSubmit(callId, answerJson);
  }

  private confirm(callId: string, approved: boolean): void {
    this.onDismiss();
    this.onBrowseConfirm(callId, approved);
  }

  @Builder
  Strip() {
    Row({ space: 10 }) {
      SymbolGlyph(toolStepIcon(this.msg))
        .fontSize(18)
        .fontColor([cardTitleColor()])
      Column({ space: 2 }) {
        Text(this.title())
          .fontSize(14)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.progress() !== '') {
          Text(this.progress())
            .fontSize(11)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardDescColor())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('展开')
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
      SymbolGlyph($r('sys.symbol.chevron_up'))
        .fontSize(16)
        .fontColor([cardDescColor()])
    }
    .height(DOCK_STRIP_HEIGHT)
    .width('100%')
    .padding({ left: 16, right: 16 })
    .margin({ left: DOCK_STRIP_INSET, right: DOCK_STRIP_INSET })
    .borderRadius(DOCK_STRIP_RADIUS)
    .backgroundColor(fallbackGrayBg(this.appColorMode, this.cardAlphaLevel))
    .onClick((): void => {
      this.expanded = true;
    })
  }

  @Builder
  PanelHead() {
    Row({ space: 8 }) {
      SymbolGlyph(toolStepIcon(this.msg))
        .fontSize(18)
        .fontColor([cardTitleColor()])
      Text(this.title())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .onClick((): void => {
        this.collapse();
      })
    }
    .height(DOCK_HEAD_HEIGHT)
    .width('100%')
    // 头行内距与卡体内容同档（2128 笔）：面板外层已有 16 屏边距，头行/卡体再各自 16
    // ——标题、题干、选项、键区共用一条左沿，治「卡内元素贴边」
    .padding({ left: 16, right: 16 })
  }

  @Builder
  Panel() {
    Column() {
      this.PanelHead()
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      // 卡体复用：docked 档由卡件自己渲染「滚动 Body + 固定键区」，键区一行不复制、档位
      // 与取色单源仍在卡件内。确认卡主因句已由其 Body 渲染，面板头行不重复一遍。
      // ★ 左右内距容器（2128 笔）：流内路径的列位由 ChatToolCard 正文列内距承担，托管面板
      // 没有那一层——此前卡件直接贴 Divider 后沿，题干/选项/键区全部贴边。内距加在本层而
      // 不是卡件根：两卡根 `.padding({ top: 4, bottom: 8 })` 是流内对齐契约（344 组钉守），
      // 卡件自持水平内距会让流内内容再缩一次、与标题行错列
      Column() {
        if (this.isAsk()) {
          ChatAskUserCard({
            msg: this.msg,
            docked: true,
            dockBodyMax: this.dockBodyMax(),
            dockBodyMin: this.dockBodyMin(),
            onSubmit: (callId: string, answerJson: string): void => {
              this.answer(callId, answerJson);
            }
          })
        } else {
          ChatBrowseConfirmCard({
            msg: this.msg,
            docked: true,
            dockBodyMax: this.dockBodyMax(),
            onSubmit: (callId: string, approved: boolean): void => {
              this.confirm(callId, approved);
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .borderRadius(BUBBLE_RADIUS)
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })
    // 圆角裁切只裁绘制，面板高度由内容驱动（不设死高，坑26 红线）；maxHeight 是 55% 上限
    .clip(true)
    .constraintSize({ maxHeight: this.panelMax })
    // 细条 → 面板：面板按终高挂载，自底边 0.98 缩放入位 + 淡入（只展开方向；收起直写）
    .opacity(this.panelIn ? 1 : 0)
    .scale({ x: 1, y: this.panelIn ? 1 : 0.98, centerX: '50%', centerY: '100%' })
    .onAppear((): void => {
      this.playPanelIn();
    })
  }

  build() {
    Column({ space: 8 }) {
      if (this.expanded) {
        this.Panel()
      } else {
        this.Strip()
      }
      // 合规行与输入栏同源同高（AI_CONTENT_LABEL 单源）
      Text(AI_CONTENT_LABEL)
        .fontSize(11)
        .fontColor(cardDescColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(DOCK_COMPLIANCE_HEIGHT)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: this.keyboardOn ? 0 : this.bottomPad })
    // 整卡进场：挂载首帧透明且下移 6vp，onAppear 后 140ms 淡入归位（纯渲染属性）
    .opacity(this.enterIn ? 1 : 0)
    .translate({ y: this.enterIn ? 0 : DOCK_ENTER_OFFSET })
    .onAppear((): void => {
      this.playEnter();
    })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      if (!this.departed) {
        this.onReadingTop(newArea.globalPosition.y as number);
      }
    })
  }
}
