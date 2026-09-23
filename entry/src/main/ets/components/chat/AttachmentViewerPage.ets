// 附件查看器二级页页面壳（2026-09-15 附件查看器二级页化笔，任务书-附件查看器二级页化-20260915）：
// 查看器承载由「全屏模态 bindContentCover」改导航栈内二级页——本页做四件事（读路由参数 /
// 组 PageShell 官方标题栏 + 页码覆盖层 + 右上角分享键 / 分享取件与调用 / 挂内容主体）。
// 为何不能并入 AttachmentViewer（反碎片下限②书面理由）：并入会让内容件同时承担「路由取参 +
// 页面壳（标题栏接线 / 返回链 / 共享键收口 / 标题栏键取件）」职责，职责缝消失且该件将越 800
// 软引导线；「据路由参数摆页面与标题栏」与「画内容」是可一句话说清的两个职责，故拆为壳/内容两件。
//
// 与模态时代的行为差（决明「二级页化」指令的正面影响面）：
// · 顶部：自绘顶部行（返回键 + 标题 20 Bold + 页码）退役，改官方 HDS 标题栏——渐变模糊蒙层
//   + 沉浸光感材质（即决明要的「顶部光感」）；返回键官方自持（栈非空自动显示、点击自动 pop），
//   页码走标题栏覆盖层（官方标题栏无右侧文本位）。
// · 内容：**两模式均不让内容从标题栏蒙层下经过**（★ 2026-09-15 图片留白笔：图片模式原全出血
//   已改——决明「图片同文字默认不进入标题栏蒙层，放大后可进入，避免展示不全」）。文本 = 内容
//   内层 padding（topPad，上滑时文字滑入蒙层）；图片 = topPad 下发页件、1x 落在标题栏下方、
//   放大后可越出该区进入蒙层。两形态并列记入 docs/规范-行内按钮与光感.md §5，防后人误改。
// · 关闭：官方返回链（标题栏返回键 / 系统返回 / 侧滑）→ pop；模态专属的「单击关闭 / 下滑
//   关闭」退役（页面形态下与官方返回重复，且下滑与 Swiper 侧滑冲突）。
// · 底部（★ 顶栏分享笔）：原「底部工具栏 + 分割线」整体退役（决明「取消底部工具栏 分割线，
//   底部无组件，可展示内容」）——内容铺到屏底；「分享」改标题栏右上角官方菜单数组单键
//   （决明「分享移至标题栏右上角，接光感，同二级页规范」；形制依据 = 规范 §4「二级页同规」：
//   单键一律官方数组、禁自绘，标题栏是沉浸光感生效区，材质/按压/圆底官方按总档接管）。分享链
//   本体迁 common/AttachmentUtil.shareAttachment（与 openSystemPreview 同域同形，行为零变化）。
//
// 标题随页更新通道（本页唯一非平凡点）：PageShell.title 原为普通成员、全仓无运行时改官方标题
// 的先例（SearchEngineDetailPage / ModelEditPage 的标题都是初始化期一次定值），故本笔把
// PageShell.title 改 @Prop——单向同步：本页 @State currentIndex 变 → 传值更新 → PageShell
// 重渲染 → hdsTitleBarOptions 重算。currentIndex 由内容主体经 onPageChange 上行；共享元素
// 广播键的**写点仍单源在内容主体**（Swiper.onChange），本页只在 aboutToDisappear 收口清空
// （同一键两写点 = 随页语义与清键时机双份真相，禁）。
// 真机判据 = 滑到第二张官方标题栏文字跟着变（任务书 §8.1 V4）；不成立则改备选「覆盖层自绘
// 标题 + keepStackTitle=false」——偏离官方标题形制，动前先报告。
// ★ 顶栏分享笔真机追加判据：①右上角分享键与页码**同屏并存不重叠**（官方菜单键 + 覆盖层文本
// 同现是首次组合：官方 d.ts 的 TitleBarContentOptions 把 menu 与 stackBuilder 列为两个独立可选
// 字段、未见互斥说明，但全仓无并存先例——不成立即改覆盖层自绘键，报告后动）；②分享面板可用。
//
// ★ 2026-09-16 标题截断笔（任务书-附件查看器标题截断-20260916）：官方标题栏的 mainTitle 只吃
// 裸 ResourceStr 且不暴露任何截断控制项（本地 SDK 全文 grep maxLines/ellipsis/TextOverflow
// 零命中），超长时官方固定走「先缩字号 → 折两行 → 尾省略」。本笔要的是「单行、尾省略、不缩
// 字号」→ 只能在**喂串前**把显示名按单行预算截好（viewerTitleName：普通尾省略、不保扩展名，
// 决明拍板）：官方拿到的恒是短串，不会再进超长分支，标题的光感材质 / 字号 / 位置全部仍由官方
// 绘制。★ 禁为截断去自绘标题（覆盖层 stackBuilder + keepStackTitle=false）：那会偏离官方标题
// 形制（规范《行内按钮与光感》§4「二级页同规」①要求覆盖层保留主标题）。
// 预算两段：屏宽（display 同步读一次，px ÷ densityPixels = vp，取不到兜底 360vp）− 两侧让位
//（TITLE_SIDE_RESERVE：左让官方返回键、右让右上角分享键与页码覆盖层）→ 单位预算
//（titleBudgetUnits；TITLE_FONT_VP 单源在 AttachmentUtil）。已知边界（本笔不解决）：①预算按
// **屏幕**宽算——平板分屏 / 自由窗口下窗口比屏窄 ⇒ 预算偏大 ⇒ 官方标题栏自行缩字号兜底（不破
// 形、不丢内容）；②本工程 module.json5 未声明 orientation（跟随系统）⇒ 页面打开期间旋屏沿用
// 旧预算（竖屏值用在横屏 = 截早一点，反之偏大）。两态都是观感级退化；真机若发现旋屏后截断点
// 离谱，再按窗口尺寸变化回调重算，不在本笔范围。
// 真机校准项：截断点与右缘的距离观感——偏早调小 TITLE_FONT_VP（预算变大）、偏晚调大，校准后
// 写死并同步注释与断言（书 §4 真机项 4）。
//
// 参数异常守卫（取不到参 / 空集 / 下标越界）：不崩且可返回——items 留空集、标题回空串、分享键
// 点击回 null 直接返回（不加提示面）；返回键归官方标题栏，恒可用。
import { display, SymbolGlyphModifier } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigationMenuContentOptions, TitleSize } from '@kit.UIDesignKit';
import { AttachmentBrief, AttachmentViewerParam, ATTACH_SHARED_ID_KEY, shareAttachment,
  titleBudgetUnits, viewerTitleName
} from '../../common/AttachmentUtil';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ATTACHMENT_VIEWER_PAGE } from '../../common/RouteNames';
import { TITLE_BAR_EDGE_INSET, TITLE_KEY_GAP, TITLE_ROUND_KEY_SIZE } from '../TitleBarKeys';
import { AttachmentViewer } from './AttachmentViewer';

// 页码覆盖层右内距：让出官方标题栏右上角的分享键位——官方菜单数组跨度 = 右缘内距 16 +
// 圆键 40 × N + 键间距 8 × (N−1)（把页码视作数组第二项，N = 2 ⇒ 64）。几何取共用件常量
// （TitleBarKeys），禁写死数值（规范《行内按钮与光感》§4「原数组形态跨度」公式同源）
const PAGE_NO_RIGHT_INSET: number =
  TITLE_BAR_EDGE_INSET + TITLE_ROUND_KEY_SIZE + TITLE_KEY_GAP;

// 标题区两侧让位总宽（vp）：左让官方返回键、右让右上角分享键与页码覆盖层——两处同一组几何，
// 按共用件三常量之和式写（禁写死 64 / 128；右单侧与上行 PAGE_NO_RIGHT_INSET 同值）
const TITLE_SIDE_RESERVE: number =
  2 * (TITLE_BAR_EDGE_INSET + TITLE_ROUND_KEY_SIZE + TITLE_KEY_GAP);

// 屏宽兜底（vp）：display 取不到时（理论不可达）——标题照常截断，占位不引异常
const SCREEN_WIDTH_FALLBACK_VP: number = 360;

// 标题栏右上角分享键：HDS 路径走官方菜单数组（每项一个官方圆钮，材质/按压/圆底官方接管），
// 回退路径走 NavDestination.menus 数组——两体系菜单类型不同，分别构造、动作同源（先例 =
// MemoryEditPage.memorySaveMenuHds / LogPage「更多」）。符号资源槽位：HDS 用 content.icon，
// 回退项须走 symbolIcon（其 icon 是图片槽位，Symbol 不显示）
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

function viewerShareMenuNav(onShare: () => void): NavigationMenuItem[] {
  return [{
    value: '分享',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.share')),
    action: onShare
  } as NavigationMenuItem];
}

@Component
export struct AttachmentViewerPage {
  // 内容顶部留白（= 状态栏 + MINI 标题栏 + 蒙层下延，PageMapBuilder 下发；原只给文本模式，
  // 同日顶栏分享笔起**两模式共用**）：文本走内容内层 padding，图片经内容件下发页件（1x 落
  // 标题栏下方、放大后可越出该区进入蒙层）——两形态并列见头注释与规范 §5
  @Prop topPad: number = 0;
  // 路由栈（取参 + 返回链 pop；与全仓页面同款普通成员）
  pathStack: NavPathStack = new NavPathStack();
  // 查看集与起始下标（aboutToAppear 自路由参数取；@State 因标题/页码覆盖层据它现算）
  @State private items: AttachmentBrief[] = [];
  @State private startIndex: number = 0;
  // 当前页下标（标题与页码两处同源）：初值 = 起始下标，随滑切经 onPageChange 上行刷新
  @State private currentIndex: number = 0;
  // 标题单行预算（视觉单位，换算见 common/AttachmentUtil.titleBudgetUnits）：aboutToAppear
  // 一次算好，build 内只读（性能红线——build 不做计算）
  private titleBudget: number = 0;

  aboutToAppear(): void {
    // 标题预算一次算好（屏宽 − 两侧让位 → 单位预算；build 内零计算，见 computeTitleBudget）
    this.titleBudget = this.computeTitleBudget();
    // 取 push 参数：同名页面多次入栈取**末条**（返回后再进时旧条目已随 pop 移除，兜底取末尾；
    // 先例 ImageAdjustPage / AssistantEditPage）
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

  // 当前页附件（分享取件的单一依据；下标钳在合法范围，空集回 null）——★ 顶栏分享笔自内容件
  // 同名方法迁来（分享键已在页面壳，取件判据随键走；标题与页码覆盖层共用同一取件口径）
  private currentBrief(): AttachmentBrief | null {
    if (this.items.length === 0) {
      return null;
    }
    const i: number = this.currentIndex >= 0 && this.currentIndex < this.items.length ?
      this.currentIndex : 0;
    return this.items[i];
  }

  // 分享当前页附件（★ 顶栏分享笔：键自内容件底栏迁到本页标题栏，链路本体 = 共享件
  // shareAttachment——系统分享面板 + UTD 两态 + uri 必转 + 失败中文 toast，与迁移前逐字同）。
  // 空集/越界时 currentBrief 回 null 即返回（参数异常守卫口径，不加提示面）
  private shareCurrent(): void {
    const brief: AttachmentBrief | null = this.currentBrief();
    if (brief === null) {
      return;
    }
    shareAttachment(this.getUIContext(), brief);
  }

  // 标题单行预算（视觉单位）：屏宽（display 同步读一次，px ÷ densityPixels = vp，取不到兜底
  // 360vp）− 两侧让位 → 单位预算（换算与 TITLE_FONT_VP 单源在 AttachmentUtil.titleBudgetUnits）
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

  // 官方标题栏主标题 = **当前页**文件名（随滑切更新——600 段已把「标题随页」列为修复项，
  // 本体不得回归「恒显第一件名」；空集回落空串）。
  // ★ 2026-09-16 标题截断笔：显示名经 viewerTitleName 按单行预算截（规则 = 普通尾省略、不保
  // 扩展名）——官方标题栏拿到的恒是短串，不会再走它那套缩字号 / 折行分支（官方 mainTitle 只吃
  // 裸 ResourceStr、不暴露截断控制项，故只能喂串前截；详见文件头「标题截断笔」节与
  // AttachmentUtil 同域注释）
  private currentTitle(): string {
    const brief: AttachmentBrief | null = this.currentBrief();
    return brief === null ? '' : viewerTitleName(brief.name, this.titleBudget);
  }

  // 标题栏覆盖层（页码 n/N）。三条硬约束随二级页覆盖层而来（规范《行内按钮与光感》§4 沉淀）：
  // ①**组件内 @Builder** 挂载（坑30：全局 @Builder 被官方 titleBar napi 直接调用时无视图
  //   上下文，启动即闪退）；②根挂 hitTestBehavior(Transparent)（整栏铺在返回键上方，默认档
  //   会挡住返回键）；③根 Row 全宽全高 + End 对齐，左侧标题区与返回键区不占位。
  // 键件不引共用件（纯文本非键）——右内距取共用件常量（禁写死数），且已让开右上角分享键位
  // （见 PAGE_NO_RIGHT_INSET；覆盖层命中透传，分享键照常可点）
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
      // 官方二级页标题档（全仓二级页统一 TITLE_S——显式传值为把「标题档」这件事写在页面上，
      // 免读者回查壳默认值）
      titleSize: TitleSize.TITLE_S,
      // 右上角分享键（★ 顶栏分享笔新增；两体系各一枚、动作同源——HDS 官方菜单数组 +
      // 回退 menus 数组，见文件头两构造器注释）
      menuHds: viewerShareMenuHds((): void => {
        this.shareCurrent();
      }),
      menuNav: viewerShareMenuNav((): void => {
        this.shareCurrent();
      }),
      // 标题栏覆盖层 = 页码；keepStackTitle = true 保住主标题（覆盖层默认会把主标题置空，
      // 本页主标题「当前页文件名」是主体的信息，不能丢）
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
