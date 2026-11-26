// 附件查看器二级页页面壳：查看器承载由「全屏模态 bindContentCover」改导航栈内二级页——
// 本页做四件事（读路由参数 / 组 PageShell 官方标题栏 + 页码覆盖层 + 右上角分享键 / 分享取件
// 与调用 / 挂内容主体）。不并入 AttachmentViewer 的理由（反碎片②）：并入会让内容件同时承担
// 「路由取参 + 页面壳」职责且越 800 软线——「据路由参数摆页面与标题栏」与「画内容」是两个
// 可一句话说清的职责，拆壳/内容两件。
// 与模态时代的行为差：顶部改官方 HDS 标题栏（渐变模糊蒙层 + 沉浸光感材质，返回键官方自持），
// 页码走标题栏覆盖层；**两模式均不让内容从标题栏蒙层下经过**（图片默认不进蒙层、放大后可进
//——两形态并列记入规范-行内按钮与光感 §5，防误改）；关闭走官方返回链（模态专属单击/下滑
// 关闭随承载退役，下滑与 Swiper 侧滑冲突）；底部工具栏整体退役（决明「取消底部工具栏 分割
// 线」），「分享」改标题栏右上角官方菜单数组单键（二级页同规：单键一律官方数组、禁自绘），
// 分享链本体在 common/AttachmentUtil.shareAttachment。
// 标题随页更新通道（本页唯一非平凡点）：PageShell.title 已改 @Prop 单向同步——本页 @State
// currentIndex 变 → 传值更新 → PageShell 重渲染 → hdsTitleBarOptions 重算；currentIndex 由
// 内容主体 onPageChange 上行。共享元素广播键写点单源在内容主体（Swiper.onChange），本页只在
// aboutToDisappear 收口清空（同一键两写点 = 双份真相，禁）。
// ★ 标题截断：官方 mainTitle 只吃裸 ResourceStr、不暴露截断控制项（超长固定走「缩字号 →
// 折两行 → 尾省略」），本页要「单行、尾省略、不缩字号」→ 只能在喂串前按单行预算截好
//（viewerTitleName：普通尾省略、不保扩展名，决明拍板）——官方拿到的恒是短串，不会再进超长
// 分支。禁为截断自绘标题（偏离官方标题形制，规范 §4）。
// 预算两段：屏宽（display 同步读一次，取不到兜底 360vp）− 两侧让位（TITLE_SIDE_RESERVE：左
// 让返回键、右让分享键与页码覆盖层）→ 单位预算（TITLE_FONT_VP 单源在 AttachmentUtil）。
// 已知边界（观感级退化，本页不解决）：预算按屏幕宽算——分屏/自由窗口下窗口比屏窄 ⇒ 预算
// 偏大由官方缩字号兜底；未声明 orientation（跟随系统）⇒ 打开期间旋屏沿用旧预算。
// 参数异常守卫（取不到参 / 空集 / 下标越界）：不崩且可返回——items 留空集、标题回空串、
// 分享键点击回 null 直接返回（不加提示面）；返回键归官方标题栏，恒可用。
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigationMenuContentOptions, TitleSize } from '@kit.UIDesignKit';
import { AttachmentBrief, AttachmentViewerParam, ATTACH_SHARED_ID_KEY, shareAttachment,
  titleBudgetUnits, viewerTitleName
} from '../../common/AttachmentUtil';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ATTACHMENT_VIEWER_PAGE } from '../../common/RouteNames';
import { TITLE_BAR_EDGE_INSET, TITLE_KEY_GAP, TITLE_ROUND_KEY_SIZE } from '../TitleBarKeys';
import { AttachmentViewer } from './AttachmentViewer';

// 页码覆盖层右内距：让出标题栏右上角分享键位（官方菜单数组跨度 = 右缘内距 16 + 圆键 40 × N
// + 键间距 8 × (N−1)，页码视作第二项 N = 2）。取共用件常量，禁写死数值
const PAGE_NO_RIGHT_INSET: number =
  TITLE_BAR_EDGE_INSET + TITLE_ROUND_KEY_SIZE + TITLE_KEY_GAP;

// 标题区两侧让位总宽（vp）：左让返回键、右让分享键与页码覆盖层——按共用件三常量之和式写
//（禁写死；右单侧与上行 PAGE_NO_RIGHT_INSET 同值）
const TITLE_SIDE_RESERVE: number =
  2 * (TITLE_BAR_EDGE_INSET + TITLE_ROUND_KEY_SIZE + TITLE_KEY_GAP);

// 屏宽兜底（vp）：display 取不到时（理论不可达）——标题照常截断，占位不引异常
const SCREEN_WIDTH_FALLBACK_VP: number = 360;

// 标题栏右上角分享键：官方菜单数组（材质/按压/圆底官方接管），符号槽位用 content.icon
function viewerShareMenuHds(onShare: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.share'),
        action: onShare
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct AttachmentViewerPage {
  // 内容顶部留白（状态栏 + MINI 标题栏 + 蒙层下延，两模式共用）：文本走内层 padding，图片
  // 经内容件下发页件（1x 落标题栏下方、放大后可进蒙层）——见头注释与规范 §5
  @Prop topPad: number = 0;
  // 路由栈（取参 + 返回链 pop；与全仓页面同款普通成员）
  pathStack: NavPathStack = new NavPathStack();
  // 查看集与起始下标（aboutToAppear 自路由参数取；@State 因标题/页码覆盖层据它现算）
  @State private items: AttachmentBrief[] = [];
  @State private startIndex: number = 0;
  // 当前页下标（标题与页码两处同源）：初值 = 起始下标，随滑切经 onPageChange 上行刷新
  @State private currentIndex: number = 0;
  // 标题单行预算（换算单源在 AttachmentUtil.titleBudgetUnits）：aboutToAppear 一次算好，
  // build 内只读（性能红线）
  private titleBudget: number = 0;

  aboutToAppear(): void {
    // 标题预算一次算好（build 内零计算，见 computeTitleBudget）
    this.titleBudget = this.computeTitleBudget();
    // 取 push 参数：同名页面多次入栈取末条（旧条目已随 pop 移除；先例 ImageAdjustPage）
    const params: Array<AttachmentViewerParam> =
      this.pathStack.getParamByName(ROUTE_ATTACHMENT_VIEWER_PAGE) as Array<AttachmentViewerParam>;
    if (params.length === 0) {
      return; // 取不到参：留空集，页面可返回（守卫口径见头注释）
    }
    const param: AttachmentViewerParam = params[params.length - 1];
    this.items = param.items;
    this.startIndex = param.index;
    this.currentIndex = param.index;
  }

  aboutToDisappear(): void {
    // 共享元素广播键收口（成对释放：写点 = 内容主体打开前/随页，清点 = 本页销毁）
    AppStorage.setOrCreate<string>(ATTACH_SHARED_ID_KEY, '');
  }

  // 图片模式判定（与内容件同口径：看首件 kind——文本模式恒单件）
  private isImageMode(): boolean {
    return this.items.length > 0 && this.items[0].kind === 'image';
  }

  // 当前页附件（分享取件单一依据；下标钳合法范围，空集回 null；标题与页码覆盖层同口径）
  private currentBrief(): AttachmentBrief | null {
    if (this.items.length === 0) {
      return null;
    }
    const i: number = this.currentIndex >= 0 && this.currentIndex < this.items.length ?
      this.currentIndex : 0;
    return this.items[i];
  }

  // 分享当前页附件（链路本体 = shareAttachment；空集/越界回 null 即返回，不加提示面）
  private shareCurrent(): void {
    const brief: AttachmentBrief | null = this.currentBrief();
    if (brief === null) {
      return;
    }
    shareAttachment(this.getUIContext(), brief);
  }

  // 标题单行预算（视觉单位）：屏宽 − 两侧让位 → 单位预算（换算与 TITLE_FONT_VP 单源在
  // AttachmentUtil.titleBudgetUnits）
  private computeTitleBudget(): number {
    let screenVp: number = SCREEN_WIDTH_FALLBACK_VP;
    try {
      const d = display.getDefaultDisplaySync();
      const density: number = d.densityPixels > 0 ? d.densityPixels : 1;
      screenVp = Math.ceil(d.width / density);
    } catch (e) {
      // 取不到（理论不可达）——兜底屏宽，标题照常截断（守卫口径：不加提示面，只留日志）
      hilog.warn(0xD5A0, 'AttachViewerPage', '屏宽读取失败，标题预算取兜底值：%{public}s',
        (e as Error).message);
    }
    return titleBudgetUnits(screenVp - TITLE_SIDE_RESERVE);
  }

  // 官方标题栏主标题 = **当前页**文件名（随滑切更新，不得回归「恒显第一件名」；空集回落
  // 空串）。显示名经 viewerTitleName 按单行预算截——官方拿到的恒是短串，不走缩字号/折行分支
  private currentTitle(): string {
    const brief: AttachmentBrief | null = this.currentBrief();
    return brief === null ? '' : viewerTitleName(brief.name, this.titleBudget);
  }

  // 标题栏覆盖层（页码 n/N）。三条硬约束（规范 §4 沉淀）：①组件内 @Builder 挂载（坑30：
  // 全局 @Builder 被官方 titleBar napi 直调无视图上下文，启动闪退）；②根挂 Transparent
  //（整栏铺返回键上方，默认档挡返回键）；③根 Row 全宽全高 + End 对齐。纯文本非键——右内距
  // 取共用件常量（禁写死）且已让开分享键位（覆盖层命中透传）
  @Builder
  TitleBarPageNo() {
    Row() {
      // 页码仅图片模式且多图时渲染（文本模式恒单件、单图无滑切——显 n/N 是噪声）
      if (this.isImageMode() && this.items.length > 1) {
        Text((this.currentIndex + 1) + '/' + this.items.length)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .padding({ right: PAGE_NO_RIGHT_INSET })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  Content() {
    AttachmentViewer({
      items: this.items,
      index: this.startIndex,
      topPad: this.topPad,
      // 关闭上行走官方返回链（模态时代的 onWillDismiss 承接随承载退役）
      onClose: (): void => {
        this.pathStack.pop();
      },
      // 下标上行（标题 + 页码两处同源刷新；广播键写点仍单源在内容主体）
      onPageChange: (i: number): void => {
        this.currentIndex = i;
      }
    })
  }

  build() {
    PageShell({
      title: this.currentTitle(),
      // 官方二级页标题档（全仓统一 TITLE_S，显式传值免回查壳默认）
      titleSize: TitleSize.TITLE_S,
      // 右上角分享键（官方菜单数组，见构造器注释）
      menuHds: viewerShareMenuHds((): void => {
        this.shareCurrent();
      }),
      // 覆盖层 = 页码；keepStackTitle = true 保主标题（覆盖层默认置空主标题，本页主标题不能丢）
      titleBarStack: (): void => {
        this.TitleBarPageNo();
      },
      keepStackTitle: true,
      content: (): void => {
        this.Content();
      }
    })
  }
}
