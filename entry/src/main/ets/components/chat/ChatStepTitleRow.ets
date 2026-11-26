// 图标与文字共用标题热区，背景透明以免在原生按压蒙层上盖出白块。
// ★ 热区（Button）随段卡 padding 收至贴缘 4（蒙层内距 SEGMENT_PRESS_INSET，圆角
// CHAIN_STEP_PRESS_RADIUS = 卡圆角）；行内容以 SEGMENT_ROW_CONTENT_PAD 回添复位——图标列
// 与标题左沿逐字未动（工具三头行与思考行同件同效）。
// 标题（思考过程 / 工具名 / 确认提问卡题）随正文字体；状态位、徽章与按钮文案不在本件，
// 各自消费面处理。
import { cardDescColor, cardTitleColor, CHAIN_STEP_PRESS_RADIUS, CHAIN_STEP_ROW_HEIGHT,
  CHAIN_GUTTER_WIDTH, CHAIN_STEP_ICON_SIZE, CHAIN_STEP_TEXT_PAD_L,
  SEGMENT_ROW_CONTENT_PAD, SEGMENT_ROW_PAD_R } from '../../common/Theme';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';

@Builder
function emptyStepSlot(): void {
}

@Component
export struct ChatStepTitleRow {
  @Prop title: string;
  @Prop icon: Resource = $r('sys.symbol.lightbulb');
  @Prop expandable: boolean = false;
  @Prop expanded: boolean = false;
  onToggle: () => void = () => {};
  @BuilderParam slot: () => void = emptyStepSlot;
  // 正文字体两键 @StorageProp 自订阅：标题属会话页消息显示面，随正文字体选择即时变化；
  // 家族串推导单源 = ChatFont.bodyFontFamily
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  build() {
    Button() {
      Row({ space: CHAIN_STEP_TEXT_PAD_L }) {
        Column() {
          SymbolGlyph(this.icon)
            .fontSize(CHAIN_STEP_ICON_SIZE)
            .fontColor([cardDescColor()])
        }
        .width(CHAIN_GUTTER_WIDTH)
        .alignItems(HorizontalAlign.Center)
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          this.slot()
          if (this.expandable) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([cardDescColor()])
              .rotate({ angle: this.expanded ? 180 : 0 })
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(CHAIN_STEP_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .padding({ left: SEGMENT_ROW_CONTENT_PAD, right: SEGMENT_ROW_PAD_R })
    }
    .type(ButtonType.Normal)
    .width('100%')
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(CHAIN_STEP_PRESS_RADIUS)
    .stateEffect(this.expandable)
    .onClick((): void => {
      if (this.expandable) {
        this.onToggle();
      }
    })
  }
}
