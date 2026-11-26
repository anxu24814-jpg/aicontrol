// 工作区数据总览半模态内容件：管理页标题栏「更多」→「数据总览」入口的面板——两卡 = 总览卡
//（总大小大字 + 件数与附加计数 + 上限行）+ 文件类型卡（五类固定序明细行）。样式照「上下文用量」
// 面板（HdsNavigation MODAL 壳 + sheetTitleBarOptions 同源标题 + CARD_PANEL_WIDTH + 底部安全区让位）。
// · 不含 bindSheet（坑64 姿势）：宿主 WorkspaceManagePage 页面根唯一挂载点，sheetKind 多形态
//   分支（'move' / 'overview'）挂载；本件零 IO 零查询纯渲染。
// · 数据面：载荷由宿主打开时现派生，本件按快照渲染——面板每次打开重建，创建期取值恒为本次快照。
// · 数据源两态（tmp）：副标题、次行单位（文件夹数 / 会话数）与上限行文案随之；临时区配额两闸
//   已生效（native fs 闸、data 落件与 staging 三方同吃），tmp 态上限行显示总量与单件两闸。
// · 文案走「面向用户文案写作规约」；符号名经 SDK 三表实查在场，构建绿为终证（坑72 两道门）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { WORKSPACE_MAX_COUNT, WORKSPACE_MAX_TOTAL_BYTES,
  formatWorkspaceSize } from '../../common/WorkspaceUtil';
import { WS_STAT_DOC, WS_STAT_IMAGE, WS_STAT_OTHER, WS_STAT_SHEET, WS_STAT_TEXT,
  WorkspaceTypeStat, workspaceStatCategoryLabel } from '../../common/WorkspaceStatsUtil';
import { WORKSPACE_TMP_MAX_FILE_BYTES, WORKSPACE_TMP_MAX_TOTAL_BYTES } from '../../common/WorkspaceTmpUtil';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';

@Component
export struct WorkspaceOverviewSheet {
  // 总件数（文件行计数——目录行不计，与 queryWorkspaceTotal 口径同源）
  fileCount: number = 0;
  // 总大小（字节；= 五类明细相加，不自设第二口径）
  bytes: number = 0;
  // 附加计数（工作区侧 = 文件夹数；临时侧 = 会话数——UI 单位随 tmp 切换）
  subCount: number = 0;
  // 数据源标记（true = 临时区：副标题、次行单位与上限行显隐随之）
  tmp: boolean = false;
  // 五类明细（固定序 + 零值行补齐，聚合在 WorkspaceStatsUtil 单源）
  types: WorkspaceTypeStat[] = [];
  // 底部系统导航条高（vp，宿主 bottomPad 注入——尾部占位，坑66 方案 B）
  bottomInset: number = 0;
  onClose: () => void = (): void => {
  };
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  private scroller: Scroller = new Scroller();

  private subLineText(): string {
    return '共 ' + this.fileCount + ' 个文件 · ' + this.subCount + (this.tmp ? ' 个会话' : ' 个文件夹');
  }

  // 明细行数值（零行只报件数不赘「0 B」——零噪声口径）
  private typeValueText(item: WorkspaceTypeStat): string {
    return item.count === 0 ? '0 个' : item.count + ' 个 · ' + formatWorkspaceSize(item.bytes);
  }

  // 类别行符号（picture / doc_text / ellipsis_circle 工程在用；doc_plaintext 与 square_grid_2x2 三表核对在场）
  private categorySymbol(category: string): Resource {
    if (category === WS_STAT_TEXT) {
      return $r('sys.symbol.doc_plaintext');
    }
    if (category === WS_STAT_SHEET) {
      return $r('sys.symbol.square_grid_2x2');
    }
    if (category === WS_STAT_IMAGE) {
      return $r('sys.symbol.picture');
    }
    if (category === WS_STAT_DOC) {
      return $r('sys.symbol.doc_text');
    }
    return $r('sys.symbol.ellipsis_circle');
  }

  // 总览卡：总大小大字 + 件数与附加计数 + 上限行（工作区容量与件数两闸 / 临时区总量与单件两闸）
  @Builder
  OverviewCard() {
    Column({ space: 10 }) {
      Text(formatWorkspaceSize(this.bytes))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
      Text(this.subLineText())
        .fontSize(13)
        .fontColor(cardDescColor())
      if (!this.tmp) {
        // 上限行（工作区容量与件数两闸的常量引用——改值即此处随形）
        Text('上限 ' + WORKSPACE_MAX_COUNT + ' 个文件 · ' +
          formatWorkspaceSize(WORKSPACE_MAX_TOTAL_BYTES))
          .fontSize(13)
          .fontColor(cardDescColor())
      } else {
        // 上限行（临时区总量与单件两闸的常量引用——与工作区侧同位同形制）
        Text('总量上限 ' + formatWorkspaceSize(WORKSPACE_TMP_MAX_TOTAL_BYTES) + ' · 单件上限 ' +
          formatWorkspaceSize(WORKSPACE_TMP_MAX_FILE_BYTES))
          .fontSize(13)
          .fontColor(cardDescColor())
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 文件类型卡：五类固定序明细行（分项符号 + 标签左、数值右加粗——上下文用量明细行同形制）
  @Builder
  CategoryRow(item: WorkspaceTypeStat) {
    Row({ space: 6 }) {
      SymbolGlyph(this.categorySymbol(item.category))
        .fontSize(14)
        .fontColor([cardDescColor()])
      Text(workspaceStatCategoryLabel(item.category))
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(this.typeValueText(item))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
  }

  @Builder
  TypeCard() {
    Column({ space: 10 }) {
      Text('文件类型')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      Column({ space: 12 }) {
        // 键含行全部可变展示成分（类别 + 件数 + 大小）——键变重建是行刷新的唯一通道（规范 §3 主通道）
        ForEach(this.types, (item: WorkspaceTypeStat): void => {
          this.CategoryRow(item)
        }, (item: WorkspaceTypeStat): string => item.category + '|' + item.count + '|' + item.bytes)
      }
      .width('100%')
      // 分类口径说明（卡尾小字；先说明后无操作行——本卡无动作面）
      Text('按文件扩展名分类统计。')
        .fontSize(13)
        .fontColor(cardDescColor())
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          this.OverviewCard()
          this.TypeCard()
          // 尾部安全区让位（Row 空占位——Blank 在部分容器下编译 10905201，规范-半模态 §2 先例用 Row）
          Row()
            .height(this.bottomInset)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('数据总览', this.tmp ? '临时文件' : '工作区文件',
      (): void => {
        this.onClose();
      }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
