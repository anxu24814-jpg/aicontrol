// 模型卡（一卡一模型）：modelId 主文本 + 能力标签徽章行 + 右侧启停 Toggle。
// 交互形制：编辑 = 卡片本体点击直进编辑页（现行形制；原四点菜单键整键退役），删除唯一走行左滑
//（RowSwipeDelete 确认链在宿主面板）；启停开关在同排右缘（Toggle 自吞点击，点开关不触发卡片
// onClick——ProviderCardItem 同构先例）；无按压蒙层。
// 启停 = 草稿态（统一保存语义）：onChange 乐观上行 onToggle，由宿主 ProviderToggleDraft 记草稿、
// 点详情页标题栏「保存」统一落库；直接退出 = 草稿随页面丢弃。数组整组替换 + ForEach 键含
// enabled（键变重建卡）驱动 Toggle 与数据态一致。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { capLabels, effectiveCaps, ModelRow } from '../../common/store/ProviderDb';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';

@Component
export struct ModelCardItem {
  row: ModelRow = {
    id: '', providerId: '', modelId: '', name: '', kind: 'chat', caps: '', createdAt: 0, enabled: true,
    capsUserModified: false, favorite: false, priceConfig: '', contextWindow: 0
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  onToggle: (row: ModelRow, isOn: boolean) => void = () => {
  };
  // 卡片点击进编辑页回调（编排在宿主面板；空 id 行不跳——获取同步入库前不存在编辑对象）
  onOpen: (row: ModelRow) => void = () => {
  };

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
        // 能力徽章行（生效能力 = effectiveCaps——未手改行走模型名派生，规则升级自动跟随；
        // 生效空 = 不渲染——获取模型拉回的裸 id 行不摆空徽章）
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

      // 启停开关（草稿态见头注释；不弹确认——开关语义即时可逆且未保存可退回；
      // Toggle 自吞点击不冒泡卡片 onClick）
      Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })
        .onChange((isOn: boolean): void => {
          this.onToggle(this.row, isOn);
        })
    }
    // 卡样式照详情页面板卡（CARD_PANEL_WIDTH + cardBg + CARD_RADIUS + padding16）
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    // 卡片热区点击进编辑页（空 id 行守卫不跳）
    .onClick((): void => {
      if (this.row.id !== '') {
        this.onOpen(this.row);
      }
    })
  }
}
