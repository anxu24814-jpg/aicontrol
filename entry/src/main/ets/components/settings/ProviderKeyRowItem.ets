// Key 池条目行域件（2026-08-31 自 ProviderKeysPanel 拆出——行内加「更多」菜单前按防屎山
// 规则腾 400 红线；行形态原样搬迁 + 当日新增更多键）：label（自动编号「Key N」，可重命名）
// + 「明文缺失」胶囊（缺失行）+ 掩码 + 行内「重填」键（仅缺明文行）+ **「更多」键（启停
// 开关左侧，领导指令）** + 启停 Toggle。
// ★ 「更多」键形态（2026-08-31 领导指令「不用加圆底」）= 会话卡四点键同款：dot_grid_2x2
// 18fp + font_secondary + ButtonStyleMode.TEXTUAL 无底（坑24：ButtonStyleMode 全局裸用
// 不可 import）。
// ★ 「更多」菜单 = 测试连接 / 重命名 / 删除（重命名/删除自原行内键移入——领导指令；
// 测试连接同日增；项序 = 无害常用在前、危险垫底）：
// 官方 Menu/MenuItem builder 形态 + symbolStartIcon（SessionCardMenuBuilder 同款——trashed/
// square_and_pencil 符号坑72 口径）+ menuItemDivider EMBEDDED_IN_MENU（官方菜单分割线
// 默认不显示须显式设置、FLOATING 被菜单项盖住不可见——SessionCardMenu 定稿注释）；bindMenu
// 材质 REGULAR 随沉浸光感总档。菜单动作经回调上行主面板——重命名/删除弹窗的
// CustomDialogController 构造位留在主面板组件成员（坑7 硬约束：弹窗控制器须组件成员位
// 构造，域级拆分不能拆出其构造位）。
// ★ 启停 = 草稿态（2026-08-31 统一保存语义，ProviderKeysPanel 头注释）——Toggle 乐观上行，
// 点详情页「保存」统一落库；重命名/删除/重填 = 资源动作即时落库。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { resolvedUiMaterial, IMMERSIVE_LEVEL_KEY, CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { badgeBg, cardDescColor, cardTitleColor, menuDividerColor } from '../../common/Theme';

// 展示行（掩码预计算——明文读取算掩码后即弃，不驻留状态；missingPlain = Asset 明文缺失
// 「行在明文无」，reload 顺带检测——检测面零扩大）
export interface KeyDisplayRow {
  id: string;
  label: string;
  mask: string;
  enabled: boolean;
  missingPlain: boolean;
}

// key 掩码（前3后4，任务书拍板形态；过短键不全露——防泄露整钥）
export function maskKey(plain: string): string {
  if (plain.length <= 8) {
    return '••••';
  }
  return plain.substring(0, 3) + '••••' + plain.substring(plain.length - 4);
}

@Component
export struct ProviderKeyRowItem {
  row: KeyDisplayRow = {
    id: '', label: '', mask: '', enabled: true, missingPlain: false
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 「更多」菜单材质随档（BatchMenu 同款口径）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 事件上行（弹窗编排、启停草稿与连接测试全在主面板——本件纯展示 + 菜单壳）
  onToggle: (row: KeyDisplayRow, isOn: boolean) => void = () => {
  };
  onRename: (row: KeyDisplayRow) => void = () => {
  };
  onDelete: (row: KeyDisplayRow) => void = () => {
  };
  onRefill: (row: KeyDisplayRow) => void = () => {
  };
  onTest: (row: KeyDisplayRow) => void = () => {
  };

  // 「更多」菜单（2026-08-31 加「测试连接」〔wifi 符号表实锤〕= 测本支 key 连接，只读
  // 探针零消耗）：项序 = 无害常用在前、危险垫底（测试连接/重命名/删除）——前两项语义
  // 与会话卡菜单同源；官方 Menu/MenuItem builder 形态 + symbolStartIcon + 显式分割线
  // EMBEDDED_IN_MENU（SessionCardMenuBuilder 同款）；本组件每行一实例，builder 内
  // this.row 即本行——无需带参 builder
  @Builder
  RowMenu() {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.wifi')), content: '测试连接' })
        .onClick((): void => {
          this.onTest(this.row);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '重命名' })
        .onClick((): void => {
          this.onRename(this.row);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
        .onClick((): void => {
          this.onDelete(this.row);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(this.row.label)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 明文缺失标注（非功能键 = 选项类胶囊：Text + badgeBg 灰底无按压光感，
          // 照 ModelCapsCard 范式；掩码 '••••' 与短 key 同观感，靠本标注区分）
          if (this.row.missingPlain) {
            Text('明文缺失')
              .fontSize(10)
              .fontColor(cardDescColor())
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(badgeBg(this.appColorMode))
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(this.row.mask)
          .fontSize(13)
          .fontColor(cardDescColor())
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(6)
          .backgroundColor(badgeBg(this.appColorMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 重填键（仅缺明文行：2026-09-02 沉浸光感化 + 2026-09-03 内容区回退双态——光感态 =
      // resolvedButton* 原材质光感，材质随沉浸光感总档、无光感档回退官方灰底；实底态 =
      // fallbackButton* 官方实底（内容区材质不生效时兜底）；不覆盖官方默认形状/字号）
      if (this.row.missingPlain) {
        Button('重填')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.onRefill(this.row);
          })
      }
      // 「更多」键（启停开关左侧——领导指令；**无圆底** = 会话卡四点键同款 TEXTUAL 无底
      // 图标键；菜单 = 删除/重命名，材质随沉浸光感总档）
      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .bindMenu(this.RowMenu, {
        placement: Placement.BottomRight,
        // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
        systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
          this.immersiveLevel, true)
      })
      // 启停开关（草稿态见头注释；缺明文行照常可切——停用缺失支 = 发送轮询避开它）
      Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })
        .onChange((isOn: boolean): void => {
          this.onToggle(this.row, isOn);
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(badgeBg(this.appColorMode))
    .alignItems(VerticalAlign.Center)
  }
}
