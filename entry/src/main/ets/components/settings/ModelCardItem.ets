// 模型卡（一卡一模型）——2026-08-31 自 ProviderModelsPanel 域拆（统一保存语义改动加
// 启停草稿链前按防屎山规则腾行数红线；组件体原样搬迁）：modelId 主文本 + 能力标签徽章行
// + 右侧启停 Toggle + 四点菜单键。
// ★ 2026-09-17 交互改形（决明指令「开关略左移，右侧放更多；菜单放编辑与删除；原来点卡片
// 进编辑改为只能点菜单才能进」）：①卡点击进编辑退役——卡片本体不再挂 onClick，编辑与删除
// 统一收进右侧四点键菜单（ModelCardMenu 域件）；②四点键与启停开关同排右缘，开关因此左移
// 一个键宽（形制对齐 ProviderCardItem：Toggle + 四点键，服务商卡先例）；③无按压蒙层——
// 卡片本体已无点击语义，不再需要整卡蒙层（原文档同款亦无）。
// ★ 启停 = 草稿态（2026-08-31 统一保存语义）：onChange 乐观上行 onToggle 由宿主
// ProviderToggleDraft 记草稿、点详情页标题栏「保存」统一落库；直接退出 = 草稿随页面丢弃
// 不保存。数组整组替换 + ForEach 键含 enabled（键变重建卡）驱动 Toggle 与数据态一致。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { capLabels, effectiveCaps, ModelRow } from '../../common/store/ProviderDb';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

@Component
export struct ModelCardItem {
  row: ModelRow = {
    id: '', providerId: '', modelId: '', name: '', kind: 'chat', caps: '', createdAt: 0, enabled: true,
    capsUserModified: false, favorite: false, priceConfig: '', contextWindow: 0
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  onToggle: (row: ModelRow, isOn: boolean) => void = () => {
  };
  // 更多键回调（弹 ModelCardMenu；编排在宿主面板）
  onMenu: (row: ModelRow) => void = () => {
  };
  // 菜单锚点 id（openMenu TargetInfo 定位目标 = 本四点键——勿锚整卡，服务商卡先例：
  // 整卡锚点使菜单低于按钮 ≈30vp 观感偏低；空串 = 不定位，宿主恒传）
  menuAnchorId: string = '';

  // 小徽章（文字胶囊；badgeBg 半透明灰底，文字 cardDescColor——ProviderCardItem 同款）
  @Builder
  CapBadge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  build() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(this.row.modelId)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        // 能力标签徽章行（生效能力 = effectiveCaps——未手改行走模型名派生〔v15 Cube 吸收
        // A1，规则升级自动跟随〕；生效空 = 不渲染——获取模型拉回的裸 id 行不摆空徽章）
        if (effectiveCaps(this.row) !== '') {
          Row({ space: 4 }) {
            ForEach(capLabels(effectiveCaps(this.row)), (label: string) => {
              this.CapBadge(label)
            }, (label: string): string => label)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 启停开关（草稿态见头注释；不弹确认——开关语义即时可逆且未保存可退回，
      // ProviderCardItem 同款）
      Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })
        .onChange((isOn: boolean): void => {
          this.onToggle(this.row, isOn);
        })
      // 四点菜单键（dot_grid_2x2——服务商卡/会话卡同符号；TEXTUAL 文字键形制 + 锚点 id
      // 挂键自身，2026-09-12 UI 同形异构归一笔 1 定稿形制：无显式高宽吃官方默认热区）
      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .id(this.menuAnchorId)
      .onClick((): void => {
        this.onMenu(this.row);
      })
    }
    // 卡样式照详情页面板卡（CARD_PANEL_WIDTH + cardBg + 圆角16 + padding16）
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
  }
}
