// 选项宫格（表单重构 UI 提案 S1 项新建，决明拍板采纳）：职责一句话 =
// 「四选一的选项容器单源」——2×2 瓦片，选中后原地展开对应输入，不再把四种表单全堆在页上。
// 判据唯一来源 = docs/规范-列表卡片与组卡.md §4.13（改形制先读该节）。
// · 分工判据（硬，先过这条再选控件）：≤3 项且纯文字 = 官方分段胶囊（SegmentBar /
//   SegmentButtonV2）；**恰 4 项、或选项需要副行小字/价格 = 宫格**。2 项恒用分段胶囊，
//   禁为凑 2×2 强行四选。一卡最多一组，同卡出现两组 = 选型错了应拆卡。
// · 性质是「选项」不是「按钮」：照 ModelCapsCard 范式——无 stateEffect 按压光感、不接
//   resolvedButton* 四件套（宪法「选项类 chips」排除项，宫格同属选项族）。
// · 形态：2×2、间距 8；瓦片 minH 46 / 圆角 12 / 浅灰底（fallbackGrayBg 同族）/ 常态无描边；
//   选中 = 淡彩底（fallbackBlueBg）+ 强调色边 + 右下角 18vp 圆勾（勾底主蓝实底、勾符号白）。
//   未选中瓦片保留 1vp **透明**边（不描边但占位），选中换强调色——避免选中时整块瓦片因边框
//   从无到有而跳动 1vp。
// · 配色两档（tone，2026-11-11 MCP 认证四档笔）：'gray' 缺省 = 上述灰底形态（搜索引擎页
//   在用，逐字不变）；'chip' = 与协议版本 chip 同族——未选淡彩蓝底 + 强调档字色、选中强调蓝
//   实底 + 白字、边恒透明、**撤圆勾**（实底已足够区分，勾在实底上无对比）。chip 档只改取色
//   与勾的存废，布局、字号、行高、onPick 契约与 gray 档完全一致。
// · 单源：本件是唯一实现；首批消费 = McpServerEditPage 认证四档（无需认证 / Bearer /
//   API Key / 自定义请求头，2026-11-11 起走 chip 档），第二批 = SearchEngineDetailPage 引擎
//   四版本（带价格副行，走缺省 gray 档）。
// · 刷新责任在调用方（同 StatusBadge 契约）：入参走 @Prop，父侧整组替换 labels/selectedValue
//   即刷；点击只上行 onPick，不自行改选中态（选中态归父页，防两处真值）。
import { LengthMetrics } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../common/AppPreferences';
import {
  cardTitleColor, fallbackBlueBg, fallbackGrayBg, selectChipBg, selectChipBorderColor,
  selectChipTextColor
} from '../common/Theme';

// 瓦片最小高度（vp；规范 §4.13「minH 46」——两行文字 + 上下留白的下限）
const TILE_MIN_HEIGHT: number = 46;
// 瓦片圆角（规范定值；本件是自绘容器但圆角走规范单值，不开放给调用方）
const TILE_RADIUS: number = 12;
// 选中勾直径（规范「18vp 圆勾」）
const TICK_SIZE: number = 18;

@Component
export struct OptionTileGrid {
  // 主行文字（4 项；不足 4 项按左到右、上到下顺排，末位留空）
  @Prop labels: string[] = [];
  // 副行文字（可选；缺项 / 空串 = 该瓦片无副行）——带价格、协议名一类「需要副行」的信息
  @Prop subLabels: string[] = [];
  // 选项值（与 labels 同序；onPick 回传它，不是下标——下标在增删档位时会失配）
  @Prop values: string[] = [];
  // 当前选中值（父页真值）
  @Prop selectedValue: string = '';
  // 配色变体：'gray' 缺省 = 浅灰瓦片；'chip' = 协议版本 chip 同族蓝底（见头注释「配色两档」）
  @Prop tone: string = 'gray';
  // 点选上行（不自行改选中态，见头注释）
  onPick: (value: string) => void = (value: string): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（瓦片灰底随档——与全站灰面同口径，档位变化即刷）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  private subOf(index: number): string {
    return index < this.subLabels.length ? this.subLabels[index] : '';
  }

  private isPicked(index: number): boolean {
    return index < this.values.length && this.values[index] === this.selectedValue;
  }

  private isChipTone(): boolean {
    return this.tone === 'chip';
  }

  // 主行字色（gray = 选中强调蓝 / 未选标题色；chip = 与协议版本 chip 同源两态）
  private tileTextColor(index: number): ResourceColor {
    if (this.isChipTone()) {
      return selectChipTextColor(this.isPicked(index), this.appColorMode);
    }
    return this.isPicked(index) ? $r('sys.color.ohos_id_color_emphasize') : cardTitleColor();
  }

  // 瓦片底色（chip = 未选淡彩蓝 / 选中强调蓝实底；gray = 既有淡彩选中 / 浅灰常态）
  private tileBg(index: number): ResourceColor {
    if (this.isChipTone()) {
      return selectChipBg(this.isPicked(index), this.appColorMode, this.cardAlphaLevel);
    }
    return this.isPicked(index) ? fallbackBlueBg(this.appColorMode, this.cardAlphaLevel) :
      fallbackGrayBg(this.appColorMode, this.cardAlphaLevel);
  }

  // 瓦片描边（chip = 恒透明占位；gray = 选中强调边）
  private tileBorderColor(index: number): ResourceColor {
    if (this.isChipTone()) {
      return selectChipBorderColor(this.isPicked(index));
    }
    return this.isPicked(index) ? $r('sys.color.ohos_id_color_emphasize') : Color.Transparent;
  }

  // 单块瓦片（宽 = 半栏减半间距；calc 由框架算，不在 build 里做算术）
  @Builder
  Tile(index: number) {
    Column({ space: 2 }) {
      Row() {
        Text(this.labels[index])
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tileTextColor(index))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // chip 档撤勾：强调蓝实底上勾无对比，实底本身已足够表达选中
        if (this.isPicked(index) && !this.isChipTone()) {
          Stack() {
            Column()
              .width(TICK_SIZE)
              .height(TICK_SIZE)
              .borderRadius(TICK_SIZE / 2)
              .backgroundColor($r('sys.color.ohos_id_color_emphasize'))
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(11)
              .fontColor([Color.White])
          }
          .width(TICK_SIZE)
          .height(TICK_SIZE)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.subOf(index) !== '') {
        Text(this.subOf(index))
          .fontSize(10)
          .fontColor(this.isChipTone() ?
            selectChipTextColor(this.isPicked(index), this.appColorMode) :
            $r('sys.color.font_secondary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('calc(50% - 4vp)')
    .constraintSize({ minHeight: TILE_MIN_HEIGHT })
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(TILE_RADIUS)
    .backgroundColor(this.tileBg(index))
    .border({
      width: 1,
      color: this.tileBorderColor(index)
    })
    .alignItems(HorizontalAlign.Start)
    // ★ minHeight 46 下内容默认顶对齐，单行文字视觉偏上；纵向居中后瓦片文字才落在几何中心
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (index < this.values.length) {
        this.onPick(this.values[index]);
      }
    })
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(this.labels, (label: string, index: number) => {
        this.Tile(index)
      }, (label: string, index: number): string => 'ot' + index + '-' + label + '-' +
        (this.isPicked(index) ? '1' : '0'))
    }
    .width('100%')
  }
}
