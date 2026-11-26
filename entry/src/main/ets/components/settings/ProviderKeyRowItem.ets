// Key 池条目行域件（自 ProviderKeysPanel 拆出）：label（自动编号「Key N」，可重命名）+「明文缺失」
// 胶囊（缺失行）+ 掩码 + 行内「重填」键（仅缺明文行）+「更多」键 + 启停 Toggle。
// ★ 「更多」键形态 = 会话卡四点键同款：dot_grid_2x2 18fp + font_secondary + TEXTUAL 无底（领导
//   指令「不用加圆底」；坑24：ButtonStyleMode 全局裸用不可 import）。
// ★ 「更多」菜单 = 测试连接 / 复制 / 重命名 / 删除（重命名/删除自原行内键移入；复制 = 读明文写系统剪贴板，
//   明文不显示不进 toast，编排在 ProviderKeysPanel.copyKey；项序 = 无害常用在前、危险垫底）：官方
//   Menu/MenuItem builder + symbolStartIcon（SessionCardMenuBuilder 同款，坑72 符号口径）+ menuItemDivider
//   EMBEDDED_IN_MENU（默认不显示须显式设置、FLOATING 被菜单项盖住）；bindMenu 材质 REGULAR 随总档。
//   菜单动作经回调上行主面板——重命名/删除弹窗的 CustomDialogController 构造位留在主面板组件成员（坑7）。
// ★ 启停 = 草稿态（统一保存语义，ProviderKeysPanel 头注释）——Toggle 乐观上行，点详情页「保存」统一
//   落库；重命名/删除/重填 = 资源动作即时落库。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { resolvedUiMaterial, IMMERSIVE_LEVEL_KEY, CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { badgeBg, cardDescColor, cardTitleColor, menuDividerColor } from '../../common/Theme';
import { BadgeTone, StatusBadge } from '../StatusBadge';

// 展示行（掩码预计算——明文读取算掩码后即弃，不驻留状态；missingPlain = Asset 明文缺失「行在明文无」，
// reload 顺带检测——检测面零扩大）
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
  // 内容区回退开关：true = 本键官方实底（新规范下内容区材质不生效）；false = 原材质光感；订阅式切换即刷（坑16）
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
  // 复制（2026-10-05 密钥复制笔）：读明文与写剪贴板全在主面板 copyKey——本件只上行
  onCopy: (row: KeyDisplayRow) => void = () => {
  };

  // 「更多」菜单：测试连接（只读探针零消耗）/ 复制 / 重命名 / 删除，项序 = 无害常用在前、危险垫底；四符号
  // 见下表（wifi / doc_filled_on_doc / square_and_pencil / trash——坑72 口径）；builder 内 this.row 即本行
  @Builder
  RowMenu() {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.wifi')), content: '测试连接' })
        .onClick((): void => {
          this.onTest(this.row);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_filled_on_doc')), content: '复制' })
        .onClick((): void => {
          this.onCopy(this.row);
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
          // 明文缺失标注（非功能键 = 状态徽标：掩码 '••••' 与短 key 同观感，靠本标注区分）。★ 危险档
          // 淡红——「明文缺失」是阻断性状态，与密钥池「可复制/可测试」正向能力形成对比；徽标全站单源
          if (this.row.missingPlain) {
            StatusBadge({ text: '明文缺失', tone: BadgeTone.DANGER })
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
      // 重填键（仅缺明文行）：光感态 = resolvedButton* 原材质（随沉浸光感总档、无光感档回退官方灰底）；
      // 实底态 = fallbackButton* 官方实底（内容区材质不生效时兜底）；不覆盖官方默认形状/字号
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
      // 启停开关（草稿态见头注释；缺明文行照常可切——停用缺失支 = 发送轮询避开它）。
      // ★ 换序：开关在前、更多在后，与服务商列表卡 / MCP 行卡同序
      Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })
        .onChange((isOn: boolean): void => {
          this.onToggle(this.row, isOn);
        })
      // 「更多」键（**无圆底** = TEXTUAL 无底图标键；菜单 = 测试连接 / 复制 / 重命名 / 删除，材质随沉浸光感总档）
      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .bindMenu(this.RowMenu, {
        placement: Placement.BottomRight,
        // ★ 第三参 true = 交互形变 + 触点流光（菜单光感笔；官方最佳实践口径，勿回改 false）
        systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
          this.immersiveLevel, true)
      })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(badgeBg(this.appColorMode))
    .alignItems(VerticalAlign.Center)
  }
}
