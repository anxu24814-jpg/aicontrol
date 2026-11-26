// 工作区层级面包屑（2026-10-03 决明拍板「像系统文件管理器那样在标题栏底下放一条可点可横滑的
// 路径」；内容区「当前位置」卡已由面包屑接管删除）——本件两族：
// ① WorkspaceBreadcrumbBar = 条体（与三库页搜索框 SearchTopBand 同构：高 40、半圆角、REGULAR
//   恒光感；横向滚动 + 可点段 + 「>」分隔 + 尾段 = 当前层加粗；内容变更滚到尾端）。两形态共用：
//   HDS 路径挂 WorkspaceTopBand 带内 / 回退路径内容区悬浮层直挂——二选一互斥禁双份。
//   `panelSurface` = 面板内容区形态：去白卡壳直坐列表，材质照 ModelPickerSheet.SearchRow 两态
//   （API 26 内容区不出沉浸材质）；缺省带内形态逐字不变。
// ② WorkspaceTopBand = HDS 标题栏下带两行承载（面包屑第一行紧贴标题栏 + 分段胶囊第二行）；
//   形态沿 PageTopSegmentBand 三件：水平居中 / 带内下移 inset / 整带命中透传；带高 = inset +
//   WORKSPACE_BAND_CONTENT_HEIGHT（88 = 40 + 8 + 40）。
// · 数据面：@Link currentDir（页面 @State 单源）现派生段数组；点段经 onJump 上抛页面执行（纯内存
//   零库访问；上一级 = 点父段，页面 goUp 退役）。段键含全部可变展示成分（文本 + 跳转目标 + 尾段
//   标记）——键漏项 = 卡面静默定格。
// · @Link tmpSegs = 消费方自备段数组覆盖源：非空即整体替换段数组（临时段下探显示「工作区 > 临时 >
//   会话标题」/ 挂载浏览页段数组下行），空 = 走文件夹派生（原行为逐字不变）。该槽已由临时段专用
//   泛化为通用覆盖源，key/text/isLast 三成分契约不变。
// · 几何常量导出（消费方 = 页面让位算式 searchBandContentTop 与 PageShell.titleBarBottomHeight
//   单源，勿在消费侧另写数值）。
// · 材质：REGULAR（输入族同档同参 interactive false）；「无」档经 resolvedUiMaterial 归一
//   Material.empty + 透明底。条体座位在标题栏下带（生效区内）故恒光感呈现。
// · 段数组恒含根段「工作区」（至少一段）——无空态分支。
import { fallbackOffCardBg } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, cardDescColor, cardTitleColor, SEGMENT_BAR_BAND_TOP_INSET,
  SEGMENT_BAR_HEIGHT } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { workspaceDirJumpTarget, workspaceDirSegments,
  WORKSPACE_ASSISTANT_DIR_ROOT } from '../../common/WorkspaceUtil';
import { SegmentBar } from '../SegmentBar';

// 条体几何（导出常量单源——页面让位算式与壳带高参数共用，勿在消费侧另写数值）
export const WORKSPACE_BREADCRUMB_HEIGHT: number = 40;
export const WORKSPACE_BAND_ROW_GAP: number = 8;
// 带内容底 → 列表内容起 的间距（vp；两消费页同吃：工作区页两行带 / 挂载浏览页单行带）。
// 决明两轮真机反馈后定 24：两行带视觉体量更大，统一口径单管全部间距，内容区首项不再额外 padding top
export const WORKSPACE_BAND_CONTENT_GAP: number = 24;
// 带内两行内容总高（面包屑 40 + 行间距 8 + 分段胶囊背板 40——PageShell 带高 = inset + 本值）
export const WORKSPACE_BAND_CONTENT_HEIGHT: number =
  WORKSPACE_BREADCRUMB_HEIGHT + WORKSPACE_BAND_ROW_GAP + SEGMENT_BAR_HEIGHT;
// 条体圆角（半圆 = 高/2，与搜索框同观感；官方无面包屑组件，自绘是官方 FAQ 同款做法）
const BREADCRUMB_RADIUS: number = WORKSPACE_BREADCRUMB_HEIGHT / 2;

// 段行载荷（键含全部可变展示成分：文本 + 跳转目标 + 尾段标记——漏项 = 卡面静默定格）。
// target 语义由消费方定：文件夹分支 = 目录路径；临时段分支恒 ''（跳转由页面按段位分派）；
// 挂载浏览页 = 段深度字符串（'0' 根 / 'n' 第 n 层，跳转按深度分派）
export interface WorkspaceCrumbSeg {
  key: string;
  text: string;
  target: string;
  isLast: boolean;
}

@Component
export struct WorkspaceBreadcrumbBar {
  // 当前目录（页面 @State 单源；段数组现派生——@Watch 只管滚尾）。挂载浏览页无文件夹派生源，
  // 本槽以恒定值占位（其覆盖源恒非空，本值从不参与渲染）
  @Link @Watch('onCrumbSourceChanged') currentDir: string;
  // 消费方自备段数组覆盖源：非空 = 条体整体渲染本数组（页面保证临时段期间恒非空——根态两段
  // 常量 / 下探三段；挂载浏览页恒非空——根段恒在）；空 = 走 currentDir 文件夹派生。变更与
  // currentDir 共用回调——进/出下探两向都要滚到尾段
  @Link @Watch('onCrumbSourceChanged') tmpSegs: WorkspaceCrumbSeg[];
  // 禁用态（会话段置灰：会话视图不消费 currentDir，可点会「点了无反馈 + 悄悄改掉文件夹段位置」；
  // 判据 = segIndex !== enabledSegIndex && tmpSegs.length === 0——临时段覆盖源恒非空后自动收窄为
  // 仅会话段。@Prop 单向同步，两构造点：WorkspaceTopBand 自 @Link segIndex 派生 / 页面回退分支直算）
  @Prop disabled: boolean = false;
  // 助手段显示名（当前路径为 assistants/<id>〔或其下〕时 id 段显示助手名——页面反查后传入；
  // '' = 无替换。跳转目标恒按真实 dir 派生，显示名只换文字不换 target）
  @Prop assistantSegName: string = '';
  // 深浅模式（条体悬浮实底 Theme.fallbackOffCardBg 需 mode 实参；档位缺省读键随重进取新档）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 面板内容区形态：true = 条体坐在半模态面板内容区（非标题栏生效区）——材质/底走
  // `ModelPickerSheet.SearchRow` 同款两态；false（缺省）= 标题栏下带形态，恒 REGULAR 光感
  @Prop panelSurface: boolean = false;
  // 内容区实底能力位（面板形态消费；全仓统一两态族前提，恒 true——ImmersiveLevel.ets 头注释）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 段点击跳转上抛（页面执行 currentDir 赋值 + 重派生；尾段不可点故不会上抛当前层；
  // 禁用态整体短路）
  onJump: (dir: string) => void = (dir: string): void => {
  };
  // 沉浸光感档位（AppStorage 自订阅——「无」档归一 Material.empty，免逐页透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  private scroller: Scroller = new Scroller();
  // 滚尾待执行标记（@Watch 同步于状态赋值、先于本帧重渲与布局——直调 scrollEdge 只对旧内容
  // 求值；置位方 = onCrumbSourceChanged，消费方 = 内容 Row onAreaChange〔内容宽就绪后才滚得到
  // 新尾端〕。先例 = 三图表 pendingEdge 机制 + ChatFollowController「未布局完成只滚到已布局底」）
  private pendingEdgeTail: boolean = false;

  // 面包屑源变更（两 @Watch 共用）：置滚尾待执行标记——尾段恒为当前层，滚尾端即当前层可见；
  // 内容不足一屏时 scrollEdge 无实际滚动，天然等价左对齐起点
  private onCrumbSourceChanged(): void {
    this.pendingEdgeTail = true;
  }

  // 段行派生（每次渲染现算；键拼三成分见接口注释）：覆盖源非空即整体返回（尾段 = 上行时点已
  // 解析的会话标题）；否则走文件夹 currentDir 派生。助手段文本替换只作用文件夹分支（临时段
  // 层级无助手目录语义）：第 3 段（下标 2）且第 2 段为 assistants 根段时显示 assistantSegName
  //（显示名单源在页面反查，本条只消费）
  private segments(): WorkspaceCrumbSeg[] {
    if (this.tmpSegs.length > 0) {
      return this.tmpSegs;
    }
    const parts: string[] = workspaceDirSegments(this.currentDir);
    const out: WorkspaceCrumbSeg[] = [];
    for (let i = 0; i < parts.length; i++) {
      const isLast: boolean = i === parts.length - 1;
      const target: string = workspaceDirJumpTarget(this.currentDir, i);
      let text: string = parts[i];
      if (i === 2 && parts.length > 2 && parts[1] === WORKSPACE_ASSISTANT_DIR_ROOT &&
        this.assistantSegName !== '') {
        text = this.assistantSegName;
      }
      out.push({ key: text + '|' + target + '|' + isLast, text: text,
        target: target, isLast: isLast });
    }
    return out;
  }

  build() {
    Scroll(this.scroller) {
      Row() {
        ForEach(this.segments(), (seg: WorkspaceCrumbSeg): void => {
          if (!seg.isLast) {
            // 可点段：点击跳回该层（无按压反馈——Text 链）；禁用态整段转次要色 + onClick 短路
            Text(seg.text)
              .fontSize(15)
              .fontColor(this.disabled ? cardDescColor() : cardTitleColor())
              .maxLines(1)
              .padding({ left: 6, right: 6 })
              .onClick((): void => {
                if (!this.disabled) {
                  this.onJump(seg.target);
                }
              })
            Text('>')
              .fontSize(15)
              .fontColor(cardDescColor())
              .maxLines(1)
          } else {
            // 尾段 = 当前层（加粗强调、不可点；禁用态转次要色）
            Text(seg.text)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.disabled ? cardDescColor() : cardTitleColor())
              .maxLines(1)
              .padding({ left: 6, right: 6 })
          }
        }, (seg: WorkspaceCrumbSeg): string => seg.key)
      }
      .height(WORKSPACE_BREADCRUMB_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })
      // 内容宽变更后消费滚尾标记（首触即解除）；坑63 家族 try/catch：Scroller 未绑定/竞态时
      // 滚动 API 可能抛 BusinessError，静默降级为停在原位
      .onAreaChange((): void => {
        if (this.pendingEdgeTail) {
          this.pendingEdgeTail = false;
          try {
            this.scroller.scrollEdge(Edge.End);
          } catch (e) {
            // 静默：内容未变无补偿动作（三图表先例同口径）
          }
        }
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    // Scroll 通用 align 默认 Alignment.Center——内容不足一屏宽时必须显式左对齐
    .align(Alignment.Start)
    .width('100%')
    .height(WORKSPACE_BREADCRUMB_HEIGHT)
    .borderRadius(BREADCRUMB_RADIUS)
    .clip(true)
    // 底 + 材质两态分治：带内形态恒光感（透明底 + REGULAR）；面板形态照 SearchRow 逐参对齐——
    // 能力位实底 app.color.comp_fallback_off_card + 空材质，否则透明底 + THIN（「无」档经
    // resolvedUiMaterial 归一）
    .backgroundColor(this.panelSurface && this.contentFallback ?
      fallbackOffCardBg(this.appColorMode) : Color.Transparent)
    .systemMaterial(this.panelSurface ?
      (this.contentFallback ? uiMaterial.Material.empty :
        resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN, this.immersiveLevel, false)) :
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, false))
  }
}

// HDS 标题栏下方带两行承载（面包屑 + 分段胶囊）——官方《设置自定义区域》bottomBuilder 承载；
// 三件形态与 PageTopSegmentBand 逐字同构：① 水平居中；② 带内下移 inset（带顶 = 标题栏下沿，
// 不是 topPad——topPad 含蒙层下延 16vp）；③ 整带命中透传（hitTest Transparent：带体不挡下方
// 列表拖动，条体/胶囊自身仍可点）。使用处 = 工作区页组件内 @Builder 包一层交给
// PageShell.titleBarBottom（坑30：builder 必须是组件内 @Builder）
@Component
export struct WorkspaceTopBand {
  // 当前目录（透传给条体做段派生——两级 @Link 链）
  @Link currentDir: string;
  // 分段索引（页面 @State 双向同步）
  @Link segIndex: number;
  // 胶囊选项（纯展示普通成员——SegmentBar 契约）
  segItems: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  // 段点击跳转上抛（透传给条体；语义随源分派在页面——文件夹段 target = 目录路径，临时段下探态
  // 任意可点段 = 回组列表，页面按段位与覆盖源判）
  onJump: (dir: string) => void = (dir: string): void => {
  };
  // 临时段下探覆盖源（页面 @State tmpCrumbSegs 经两级 @Link 透传条体；页面在临时段期间恒非空——
  // 根态两段常量 / 下探三段，空 = 仅会话段与文件夹段）
  @Link tmpSegs: WorkspaceCrumbSeg[];
  // 面包屑启用段（文件夹段以外皆置灰，改启用段语义；缺省 0 = 首段〔文件夹〕启用，与页面
  // WS_SEG_FOLDER 同值约定。临时段覆盖源恒定非空后，置灰实效 = 仅会话段）
  enabledSegIndex: number = 0;
  // 助手段显示名（透传给条体——页面反查后传入，'' = 无替换）
  assistantSegName: string = '';
  // 带内下移量（vp）：与 PageShell.titleBarBottomInset 同值配对（两半几何同源——默认 8）
  inset: number = SEGMENT_BAR_BAND_TOP_INSET;

  build() {
    Row() {
      Column({ space: WORKSPACE_BAND_ROW_GAP }) {
        WorkspaceBreadcrumbBar({
          currentDir: $currentDir,
          tmpSegs: $tmpSegs,
          disabled: this.segIndex !== this.enabledSegIndex && this.tmpSegs.length === 0,
          assistantSegName: this.assistantSegName,
          onJump: this.onJump
        })
        SegmentBar({
          items: this.segItems,
          selectedIndex: $segIndex,
          materialPinned: true
        })
      }
      .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .padding({ top: this.inset })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
