// 工作区移动半模态面板（决明「参考系统文件空间『移动到…』形制」）：入口 = 工作区管理页文件夹/会话
// 两视图行菜单「移动」——逐层进入式选目标，底部「移动到此处」把条目移到当前所在层。
// · 交互：首层并列工作区根的一级文件夹；点文件夹行进下一层（含空文件夹，进后按底部键即可落点）；
//   路径条承担层级跳转（可横滑 + 点段直达，条体 = WorkspaceBreadcrumbBar 同源）；关闭 = 直接关面板。
// · 滚顶时序：进层/跳层后回顶 = 「待滚标记 + 新层行挂载消费」（goTo 只置位不直调滚动 API；消费点 =
//   ListItem onAppear，换层键全换全量重建即内容就位信号）——赋值同帧直调只对旧层内容求值。
// · 差异于参考图（决明拍板）：无新建文件夹图标；首卡 = 路径条（非「当前要移动的文件」卡），搜索框
//   样观感（panelSurface 两态材质，白卡壳退役）。
// · 数据面：宿主打开时现派生三件 @Prop——targets（可落点集，排除当前目录 / 文件夹自身与整棵子树）、
//   allDirs（全部目录完整路径，逐层列表与箭头判据输入）、hiddenPrefix（移动中的文件夹自身路径，
//   从树里隐藏；文件移动传 ''）。面板零库访问，只做展示与选择。
// · 可见性：隐藏分支不出现；当前所在目录 fromDir 可进入但不可落点（底部键置灰 + 说明行，不静默）；
//   行尾「＞」= 有子文件夹才显（workspaceDirHasDrillChild 单源；空文件夹不显、仍可进入）；空层显说明行。
// · 形态两件：①路径条随内容滚动不吸顶——滚动内容需到达标题栏背后供 GRADIENT_BLUR 采样（规范 §2
//   模糊生效前提；固定首卡 + clip(false) 会让滚动行画到卡上）；②底部键带 = 规范 §2 吸底键条形制
//   （Stack 叠三层：List 全高 clip(false) + 底部渐变蒙层 hitTest None + 透明键带 hitTest Transparent；
//   List 尾占位 = 蒙层高〔含底部安全区〕，两处同源 bottomFadeHeight）。
// · 关闭路径：xmark 与手势两路都由宿主 requestCloseMove 收口（本件只发 onClose 意图——半模态规范
//   「每个宿主一个关闭入口」）。壳与列表形制照 SessionMovePanel（HdsNavigation MODAL +
//   sheetTitleBarOptions 单源 + List clip(false) + ignoreLayoutSafeArea BOTTOM 后键带自垫底线高）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor,
  pageBgFade, CARD_RADIUS
} from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { deriveWorkspaceDrillChildren, workspaceDirHasDrillChild } from '../../common/WorkspaceUtil';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import { WorkspaceBreadcrumbBar, WorkspaceCrumbSeg } from './WorkspaceBreadcrumb';

// 底部渐变蒙层高（KimiFullInputSheet / MessageCopySheet 定稿 90vp 沉淀；尾占位与蒙层同源同一算式）
const WS_MOVE_BOTTOM_FADE_HEIGHT: number = 90;

@Component
export struct WorkspaceMovePanel {
  // 可落点集（宿主现派生；底部键可用性判据——含根 ''）
  @Prop targets: string[] = [];
  // 全部目录完整路径（逐层列表 + 行尾箭头判据的输入）
  @Prop allDirs: string[] = [];
  // 隐藏分支前缀（移动中的文件夹自身路径；文件移动传 ''——不隐藏）
  @Prop hiddenPrefix: string = '';
  // 底部系统导航条高（vp，宿主注入——蒙层/键带/尾占位共用 bottomFadeHeight）
  @Prop bottomInset: number = 0;
  // 落点上抛（宿主执行移动；成功关面板，失败保留面板可重试——P0-1）
  onPickTarget: (target: string) => void = (target: string): void => {
  };
  // 关闭上行（标题栏 xmark；宿主与 onWillDismiss 同调一个 requestCloseMove）
  onClose: () => void = (): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区实底能力位（全仓统一双态族 fallbackButton* 消费前提——恒 true，订阅式避坑16）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 当前浏览层（'' = 工作区根；进层 / 面包屑点段跳层改写——纯内存零库访问）
  @State private panelDir: string = '';
  // 条体临时段覆盖源（条体契约必填槽）：移动面板只服务文件夹语义，本地恒空填充；页面 tmpCrumbSegs
  // 不经本面板透传，语义独立不共享
  @State private tmpCrumbSegs: WorkspaceCrumbSeg[] = [];
  // 滚回顶部待执行标记（@State 赋值先于本帧重渲，同帧直调只对旧层内容求值；置位方 = goTo，消费方 =
  // 新层行 / 空层说明 ListItem onAppear〔换层键全换、行全量重建，挂载后内容已就位〕）
  private pendingTopReset: boolean = false;
  // 滚动控制器（宿主壳 bindToScrollable 绑标题栏渐变模糊——传引用共用同一实例）
  scroller: Scroller = new Scroller();

  // 当前层子目录（段序；隐藏分支已滤除——WorkspaceUtil 单源）
  private childrenOf(): string[] {
    return deriveWorkspaceDrillChildren(this.allDirs, this.panelDir, this.hiddenPrefix);
  }

  // 行尾「＞」显隐（有子文件夹才显；空文件夹仍可进入——同单源过滤）
  private hasChild(dir: string): boolean {
    return workspaceDirHasDrillChild(this.allDirs, dir, this.hiddenPrefix);
  }

  // 当前层可否落点（当前所在目录不在候选——底部键置灰 + 说明行，不静默）
  private canMoveHere(): boolean {
    return this.targets.indexOf(this.panelDir) >= 0;
  }

  // 行主文本：末段名（行仅为目录行，不会传根 ''）
  private nameOf(dir: string): string {
    const segs: string[] = dir.split('/');
    return segs[segs.length - 1];
  }

  // 蒙层高（含底部安全区；尾占位与蒙层两处同源——规范 §2 吸底键条口径）
  private bottomFadeHeight(): number {
    return WS_MOVE_BOTTOM_FADE_HEIGHT + this.bottomInset;
  }

  // 进层 / 面包屑跳层收口（层级切换后回顶——旧层偏移对新层无意义；只置待滚标记，见 pendingTopReset）
  private goTo(dir: string): void {
    if (dir === this.panelDir) {
      return;
    }
    this.panelDir = dir;
    this.pendingTopReset = true;
  }

  // 待滚标记消费（幂等；换层后首个挂载的行 / 空层说明调用；坑63 家族 try/catch 容错）
  private consumeTopReset(): void {
    if (!this.pendingTopReset) {
      return;
    }
    this.pendingTopReset = false;
    try {
      this.scroller.scrollEdge(Edge.Top);
    } catch (e) {
      // 静默：Scroller 未绑定/竞态时滚动 API 可能抛 BusinessError（面包屑条体先例同口径）
    }
  }

  build() {
    HdsNavigation() {
      // 吸底键带层（规范 §2 第三条形制）：Stack 底对齐叠〔List 全高 + 底部渐变蒙层 + 透明键带〕
      Stack({ alignContent: Alignment.Bottom }) {
        List({ space: CARD_SPACING, scroller: this.scroller }) {
          // 首卡 = 路径条（白卡壳退役，条体直坐列表，材质走 panelSurface 两态；功能不变：可横滑 +
          // 点段直达；随内容滚动不吸顶——保标题栏模糊采样）
          ListItem() {
            WorkspaceBreadcrumbBar({
              currentDir: $panelDir,
              tmpSegs: $tmpCrumbSegs,
              panelSurface: true,
              onJump: (dir: string): void => {
                this.goTo(dir);
              }
            })
          }

          // 当前层文件夹列表（点行进入下一层；新层行挂载即消费滚顶标记——首个挂载行即内容就位信号）
          ForEach(this.childrenOf(), (child: string): void => {
            ListItem() {
              // 卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding 16/13 → 12/9 回添，几何零位移
              Column() {
                Button() {
                  Row({ space: 10 }) {
                    SymbolGlyph($r('sys.symbol.folder'))
                      .fontSize(20)
                      .fontColor([cardDescColor()])
                    Text(this.nameOf(child))
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(cardTitleColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (this.hasChild(child)) {
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(16)
                        .fontColor([cardDescColor()])
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
                .type(ButtonType.Normal)
                .width('100%')
                .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                .backgroundColor(Color.Transparent)
                .borderRadius(CARD_RADIUS)
                .onClick((): void => {
                  this.goTo(child);
                })
              }
              .width('100%')
              .padding(4)
              .backgroundColor(cardBg(this.appColorMode))
              .borderRadius(CARD_RADIUS)
            }
            .onAppear((): void => {
              this.consumeTopReset();
            })
          }, (child: string): string => child)

          // 空层说明（无可进入的子文件夹；可否落点由底部键与说明行表达；本行挂载亦消费滚顶标记）
          if (this.childrenOf().length === 0) {
            ListItem() {
              Text(this.canMoveHere() ?
                '这个文件夹里没有子文件夹。点下方按钮可把条目移到这里。' :
                '这个文件夹里没有子文件夹。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
                .padding({ left: 4, right: 4, top: 8 })
            }
            .onAppear((): void => {
              this.consumeTopReset();
            })
          }

          // 尾部占位 = 蒙层高（与蒙层同源 bottomFadeHeight）：滚到底末行停在蒙层上方完整可见；
          // Row 空占位——Blank 在 ListItem 下编译 10905201（规范 §2 先例用 Row）
          ListItem() {
            Row()
              .height(this.bottomFadeHeight())
          }
        }
        .width('100%')
        .height('100%')
        // 滚动内容穿透标题栏背后（clip(false) 缺省裁剪 = 渐变模糊无内容可透——规范 §2）
        .clip(false)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .padding({ top: 20, left: 16, right: 16 })

        // 底部渐变蒙层（pageBgFade → page_bg，深浅分治；hitTest None = 不拦滚动与行卡触摸）
        Column()
          .width('100%')
          .height(this.bottomFadeHeight())
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 底部透明键带（hitTest Transparent = 条面不阻断下层滚动，键本体响应不衰减）——说明行与
        // 置灰键配对解释（不静默）+ 落点主键（全仓统一双态族 fallbackButton*，primary 强调蓝 + 恒白字）
        Column({ space: 8 }) {
          if (!this.canMoveHere()) {
            Text('条目已在当前文件夹里')
              .fontSize(12)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
              .hitTestBehavior(HitTestMode.None)
          }
          Row() {
            Button('移动到此处')
              .enabled(this.canMoveHere())
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .width('100%')
              .onClick((): void => {
                this.onPickTarget(this.panelDir);
              })
          }
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        // 单一 padding（ArkUI 同属性后设覆盖——KimiFullInputSheet 二一五改教训）
        .padding({ top: 12, bottom: this.bottomInset + 12 })
      }
      .width('100%')
      .height('100%')
    }
    // 标题栏（KimiSheetCommon 单源：主副标题 + xmark + AUTO 分割线 + 静止渐变模糊 + 材质随档——勿自绘标题）
    .titleBar(sheetTitleBarOptions('移动到', '选择要移动到的文件夹', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
