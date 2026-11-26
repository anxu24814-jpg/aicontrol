// 「文件夹挂载」管理页卡面域（自 MountManagePage 域级最小拆分，依据 = 宪法「防屎山」结构防腐条）：
// 职责 = 挂载卡渲染 + 卡内下排三键；系统选择器、授权编排与库读写仍留在页面壳（MountManagePage），
// 本件只消费页面下发的回调。
// 卡面形态（2026-11-16 决明参照服务商编辑页模型卡重绘，同日二改「模式徽标改蓝放右上角同助手页 /
// 路径降副标题」）：卡头 = 名称行（16 Medium 引 CARD_SECTION_TITLE_FONTSIZE + 行尾 StatusBadge
// 强调档蓝徽标显示只读·读写，同助手页「当前」徽标姿势）+ 路径副标题（13 引 CARD_NOTE_FONTSIZE，
// 单行省略）；原 folder 前导图标、铅笔改名键与自绘灰底 10fp 徽章行随本笔退役（三档字号/字重
// 全部收进 Theme 单源常量，不再自绘）；
// · **卡内分段胶囊退役**：只在卡上「看模式」不满足需求、且切换本就是重选文件夹的重动作，模式切换
//   收进「更多」菜单（切换至读写 / 切换至只读，域件 MountCardMenu），卡面只留模式徽章表达现状；
// · 底部 = 下排三键：左侧「打开 / 移除」等宽次钮（移除仅字色覆盖危险红），右侧 40vp 圆底「更多」
//   图标键（dot_grid_2x2，形制照 ProviderModelsPanel 工具卡；锚点 id 挂键自身，openMenu 按 id 定位）；
//   分割线在卡头与键行之间；仅「打开」键进入浏览页，卡体空白无热区；
// · 失效态（needReauth）= 警示行 + 全宽「重新授权」键（切换项在菜单内置灰，见域件注释）；底部
//   三键照常，失效态点打开键由页面侧 toast 指引。
// ★ 权限切换在途闸已随胶囊退役：原「按住胶囊拖拽跨档叠出多层系统选择器」风险面（消息字体页事故
//   同族）随分段形态一并消失——菜单项单击即收起，不存在连续回调；页面侧 picking 闸仍保留，
//   形成唯一一道防重入。
// 列表键纪律：卡实例由页面 ForEach 键控重建（键含 id/名/URI/模式/警示文案），普通成员不承担刷新；
// 模式切换成功后页面 reload → 键变重建，徽章与菜单文案随新数据。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  MOUNT_MODE_READ_ONLY,
  mountModeLabel,
  mountPathDisplay
} from '../../common/MountUtil';
import {
  CARD_NOTE_FONTSIZE,
  CARD_PANEL_WIDTH,
  CARD_SECTION_TITLE_FONTSIZE,
  cardBg,
  cardBorderColor,
  cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY,
  IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg, fallbackButtonBgTinted,
  fallbackButtonFont, fallbackButtonFontTinted,
  fallbackButtonMaterial, fallbackButtonMaterialTinted,
  fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { StatusBadge } from '../StatusBadge';

// 卡视图载荷（自 MountManagePage 原样迁入；键含全部可变展示成分 = MountUtil.mountCardKey）
export interface MountCardView {
  id: number;
  name: string;
  dirUri: string;
  mode: number;
  warningText: string;
  needReauth: boolean;
}

@Component
export struct MountManageCard {
  // 卡数据（普通成员：页面 ForEach 键控重建 = 唯一更新路径，与 WorkspaceListRows 行卡同契约）
  card: MountCardView = {
    id: 0,
    name: '',
    dirUri: '',
    mode: MOUNT_MODE_READ_ONLY,
    warningText: '',
    needReauth: false
  };
  // 页面动作回调（系统选择器与库读写编排在页面壳；本件只上行意图）
  onOpen: () => void = (): void => {};
  // 无 onRename：改名入口已收进卡「更多」菜单（域件 MountCardMenu 的 callbacks 直连页面），
  // 卡面既无改名键就不留同名回调（2026-11-16 自检轮剔死参数）
  onReauth: () => void = (): void => {};
  onSwitchMode: () => void = (): void => {};
  onRemove: () => void = (): void => {};
  // 「更多」键上行（菜单内容与宿主在页面侧：卡只上抛意图，菜单按点击当刻卡数据现建）
  onMore: () => void = (): void => {};
  // 卡内「更多」键锚点 id（openMenu TargetInfo 定位目标 = 该键——勿锚整卡）
  menuAnchorId: string = '';

  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  // 卡头（名称行 + 模式徽标右置 + 路径副标题；形制照助手页列表卡）
  @Builder
  CardHead() {
    Column({ space: 4 }) {
      // 名称行 = 单行 Row（勿改 Flex wrap：长名 + 徽标同排超宽时徽标会被挤到第二行，行高翻倍——
      // 助手页同名行判据，徽标恒占定宽、名称 layoutWeight 让位并省略）
      Row({ space: 6 }) {
        Text(this.card.name)
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // 模式徽标（强调档蓝——StatusBadge 单源件，同助手页「当前」徽标；徽标非按钮非选项 chip，
        // 走四档色身份不属「行内操作按钮官方形制」约束）
        StatusBadge({ text: mountModeLabel(this.card.mode) })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 路径 = 副标题（13fp 灰，单行省略——列行卡副行归一档 CARD_NOTE_FONTSIZE）
      Text(mountPathDisplay(this.card.dirUri))
        .fontSize(CARD_NOTE_FONTSIZE)
        .fontColor(cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 失效态区（警示行 + 重新授权键；正常态整区不渲染）
  @Builder
  ReauthSection() {
    Column({ space: 8 }) {
      Text(this.card.warningText)
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_warning'))
        .width('100%')
        .textAlign(TextAlign.Start)
      Button('重新授权')
        .width('100%')
        .fontColor(fallbackButtonFontTinted(this.contentFallback))
        .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
        .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.onReauth();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 下排三键（左：打开 / 移除 等宽次钮；右：更多圆底图标键——照 ProviderModelsPanel 工具卡）
  @Builder
  ActionRow() {
    Row({ space: 8 }) {
      Button('打开')
        .layoutWeight(1)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.onOpen();
        })
      Button('移除')
        .layoutWeight(1)
        .fontColor($r('app.color.dialog_confirm_red'))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.onRemove();
        })
      // 更多键：直挂 Row 不占伸缩槽——打开/移除 layoutWeight 等分剩余宽度；锚点 id 挂键自身
      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(18)
          .fontColor([fallbackButtonFont(this.contentFallback, false)])
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .accessibilityText('更多操作')
      .id(this.menuAnchorId)
      .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
      .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
      .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
      .onClick((): void => {
        this.onMore();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 10 }) {
      this.CardHead()
      if (this.card.needReauth) {
        this.ReauthSection()
      }
      Divider()
        .strokeWidth(0.5)
        .color(cardBorderColor(this.appColorMode))
      this.ActionRow()
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    // 仅「打开」键进入浏览页，卡体空白无热区（整卡 onClick 已于 2026-10-19 拆除）
  }
}
