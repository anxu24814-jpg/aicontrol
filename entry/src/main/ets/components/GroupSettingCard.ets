// 「组卡」（2026-09-07 新建——设置页组卡化：参照旧项目 dshinhm「我的」页组卡形态，样式
// 按官方系统设置「星闪和蓝牙 → 已配对设备」卡真机实测规格复刻；本文件为该规范单源）。
// · 选型理由（「实现选型三级优先」第 3 级登记，与 dshinhm 组卡同源结论）：HDS **无组卡
//   组件**——@kit.UIDesignKit 全导出清单核实只有 HdsListItemCard 单行卡；华为系统设置的
//   组卡 = 设计规范形态非组件。本组件 = **官方基础组件拼装**（Column 卡底 + 官方 Divider +
//   Button 行原生按压 + SymbolGlyph 图标 + 官方语义色），零第三方零自绘样式。
// · ★ 官方实测基准（2026-09-07 真机 uitest dumpLayout 量测，density 3.5，设备 1276×2848
//   ——与 dshinhm 量测同机口径；页面 = 系统设置 → 星闪和蓝牙 → 已配对设备卡）：
//   · 卡宽 = 屏宽 −32vp（左右 16vp，与 CARD_PANEL_WIDTH 同构 ✓）；卡上下 padding **4vp**；
//     圆角按项目统一卡片体系 **16vp**（官方实测 20vp，2026-09-07 决明拍板不引入）
//   · **行高固定分档**：带副标题 **64vp**（224px）/ 无副标题 **56vp**（196px）——两行标题
//     仍 56vp（内容垂直居中，非内容自适应），即 Official 行高模型 = 有无 secondary 两档
//   · 行内缩进：行相对卡左右各 **4vp**（ListItem 缩进 4vp = 按压蒙层比卡略短，与 dshinhm
//     Button margin 4 先例同构）；行内左 padding **8vp** → 图标左缘 = 卡内 12vp
//   · 图标 = SymbolGlyph **24vp**（85px，无底）；图标-标题间距 **16vp**（56px）
//     → 标题左缘 = 卡内 52vp（12+24+16，实测 52.3vp ✓）
//   · 标题 16fp Medium；副标题 **14fp**（dshinhm 版 13fp 偏小，官方实测行盒 57px 拟合 14fp）；
//     标题-副标题间距 2vp（官方实测 7px）
//   · Divider：官方实测 2px 物理线 ≈ **0.5vp**（视觉细线，非 1vp——3.5x 下 1vp=3.5px 过
//     粗）；色用项目 cardBorderColor（深浅分治；官方实测 #D5D5D5 ≈ 黑16%，项目 12% 相近—
//     —项目统一口径）；**左缩进 = 卡内 44vp**（= 4 行缩进 + 8 行 pad + 24 图标 + 8 间距 =
//     图标右缘 + 8vp，实测 44vp ✓）；右端到行右缘（margin right 4 与行缩进对称）；末行不显
// · dshinhm 版差异（旧项目组卡 32vp 灰圆底 SVG 图标 / 48vp 行高 / 8vp 间距 / 13fp 副标题 /
//   16vp 圆角——本次按官方实测全面对齐，仅圆角保留项目 16vp）：
//   图标改 SymbolGlyph 24vp 无底（新项目设置页符号 sys.symbol 即官方「无底符号」姿势，
//   零图片资源）；行高改固定分档 56/64；间距 8→16；副标题 13→14fp；卡补上下 4vp padding；
//   Divider 1vp→0.5vp、左缩进 56→44、右缩进 16→4。
//   · 行文本一律**单行省略**（标题与副标题均 maxLines 1 + Ellipsis，2026-09-13 真机报障
//     实锤）：行高是固定分档模型（内容垂直居中，非自适应），多行文本物理上放不下——长文本
//     （如内置元技能 90 字触发描述）不设省略会溢出卡外
// · 点按：全行圆角（与卡体同值 16）+ 蒙层比卡略短 + 官方原生按压（Button stateEffect
//   默认 true——官方 ListItem 同款按压反馈）。★ 蒙层缩进 4vp 用行外包 Column padding
//   实现——原 Button margin 4 + width 100% 组合真机实测蒙层与卡左右等宽未缩进（2026-09-07
//   截图像素实测：蒙层缘 x56/x1220 与卡缘精确重合），卡上下 padding 4 使蒙层顶下移后
//   与卡圆角错位出楔形白边 = 决明「点按蒙层与卡片不一致」实锤，勿改回 margin 写法。
// · 接口：icon 缺省 = 无图标行（dividerLeft 传 8 对齐标题左缘）；行形态——
//   ①跳转行 = onClick（SettingsPage/InfoPage 组卡先例）；②开关行 = toggleValue + onToggle
//   两字段齐全，行尾渲染官方 Toggle：**Toggle 可点自切换（onChange 上行）= 唯一控制面**，
//   行本身不可点且无按压反馈（2026-09-08 决明拍板「只能通过点击开关控制开闭」，同日先
//   工具页后全应用统一——偏好设置页两卡同形态；原「纯视觉 Toggle + 整行点击」形制已废，
//   统一后无形态开关，组件行为单一来源）；③只读行 = 两类回调全缺（2026-09-13 工具页成员
//   行只读化——开关收敛到组级语义开关，成员行仅展示图标/标题/副标题，无开关无跳转，
//   去按压反馈防「按得下去、什么也没发生」误导；★ 2026-09-18 工具页分类卡重组后成员行
//   整面退役，本形态在工程内暂无消费方——保留待复用，勿当在用形态读）；④选中行 =
//   onClick + selectedMark
//  （2026-09-16 单条消息指定技能页首用）——行尾官方勾选符号标当前项，无 Toggle（与跳转行
//   同为可按压行）。
//   ★ 开关显示刷新责任在调用方（2026-09-08 真机报障实锤）：items 是普通成员入参，父组件
//   重渲不更新普通成员，本组件自身又无状态变化 → build 不重跑 → Toggle 定格首帧（症状 =
//   数据已变、开关不动、退出重进才正确）。调用方须把组卡放进「键含开关态/纪元」的 ForEach
//   （键变重建 = 规范 §3 主通道）——先例 AssistantToolsPage.toggleEpoch / PreferencesPage
//   两组 key。组件内 ForEach 键含开关值只在组件确实重渲时才起作用，不能替代调用方键。
//   ★ 同族依据与取舍：坑16 家族·2026-09-04 判据「状态驱动的列表 ForEach 键须含该状态」
//   （5b418ff 模型卡/附件条两连实锤）+ dshinhm 坑57「普通成员入参不重渲染」（本组件 items
//   同源）；子组件 @Prop 承载 = 坑16 家族禁区（@BuilderParam/PageShell.content 内 @Prop 不
//   随父状态更新，UI 冻结首帧——2026-08-31 重蹈实锤）。取舍 = 键变重建切换无过渡动画。
// · 未来消费约定：新增组卡 = items 传 GroupEntryItem[]（label 引 SETTING_TITLE_* 常量，
//   单一来源；行点击回调内 recordRecentUse + 上抛导航壳 push——SettingsPage openCard 先例；
//   开关行 onToggle 直接写 @StorageLink 键，AppStorage 响应式即刷）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CARD_PANEL_WIDTH, cardBg, cardBorderColor, cardDescColor, cardTitleColor } from '../common/Theme';

// 行高两档（官方实测分档模型——有副标题 64 / 无 56，固定行高 + 内容垂直居中）
const ROW_HEIGHT_WITH_SUB: number = 64;
const ROW_HEIGHT_SINGLE: number = 56;
// 分割线左缩进默认值 = 卡内 44vp（有图标行口径：4 行缩进 + 8 行 pad + 24 图标 + 8 间距）；
// 无图标行传 8（对齐标题卡内 12 − 4 行缩进对称）
const DIVIDER_LEFT_ICON: number = 44;
const DIVIDER_LEFT_NO_ICON: number = 8;

export interface GroupEntryItem {
  // 左侧图标（系统符号资源 sys.symbol.*，SymbolGlyph 24vp 无底渲染——官方已配对设备
  // 列图标同款姿势；缺省 = 无图标行，dividerLeft 传 DIVIDER_LEFT_NO_ICON）
  icon?: Resource;
  // 行标题（调用方引用 SETTING_TITLE_* 常量，保持单一来源）
  label: string;
  // 副标题（14fp 次要色；缺省 = 单行——行高自动走 56vp 档）
  secondary?: string;
  // 行点击回调（跳转行必备；开关行可省——用下方 toggleValue/onToggle 两字段）
  onClick?: () => void;
  // 开关行取值（2026-09-08 扩展：本字段与 onToggle 齐全 = 开关行——行尾渲染官方 Toggle，
  // 可点自切换）。调用方闭包读状态（@StorageLink/@State——响应式，键求值时现读）
  toggleValue?: () => boolean;
  // 开关行写值（调用方写状态：@StorageLink 写即持久化 / @State 写后落库；特殊逻辑
  // ——失败回滚 + toast——在回调内做）
  onToggle?: (isOn: boolean) => void;
  // 非开关行的尾部状态位（2026-09-16 单条消息指定技能页首用）：true = 行尾渲染官方勾选
  // 符号（当前选中项标记）。与 toggleValue/onToggle 互斥消费——开关行不渲染本件（渲染分支
  // 为 else if），跳转行/只读行不带本字段（undefined = 不渲染，既有消费方零影响）
  selectedMark?: () => boolean;
}

@Component
export struct GroupSettingCard {
  // 行数据（普通成员：创建后不再更新——行列表不重渲染，同 SettingEntry 参数姿势；开关行
  // 的显示刷新由调用方键变重建承担，见头注释「开关显示刷新责任在调用方」）
  items: GroupEntryItem[] = [];
  // 分割线左缩进（卡内 vp）：有图标行默认 44（图标右缘 + 8vp，官方实测）；无图标行传 8
  dividerLeft: number = DIVIDER_LEFT_ICON;
  // 系统颜色模式（深浅色卡底/分割线/文字，EntryAbility 写入 AppStorage——同
  // GroupCardPlaceholder 消费姿势）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 开关行判定（toggleValue + onToggle 两字段齐全）——@Builder 内禁局部变量，收敛为方法
  private isSwitchRow(item: GroupEntryItem): boolean {
    return item.toggleValue !== undefined && item.onToggle !== undefined;
  }

  // 可按压判定（跳转行专属）：开关行与只读行都去按压反馈——开关行「行点击空转」（2026-09-08
  // 统一形态），只读行无任何交互（2026-09-13 工具页成员行只读化随形）
  private isClickableRow(item: GroupEntryItem): boolean {
    return !this.isSwitchRow(item) && item.onClick !== undefined;
  }

  // Toggle 上行（开关行唯一控制面；行点击不切换——2026-09-08 统一形态）
  private onToggleUp(item: GroupEntryItem, isOn: boolean): void {
    if (this.isSwitchRow(item) && item.onToggle !== undefined) {
      item.onToggle(isOn);
    }
  }

  // 行内容（可点行专属）：行高固定分档 + 内容垂直居中（官方行高模型，勿改回自适应 padding
  // ——48vp 自适应版 = dshinhm 旧规格，2026-09-07 决明「纵向宽度偏窄」实锤）
  @Builder
  RowContent(item: GroupEntryItem) {
    Row({ space: 16 }) {
      if (item.icon !== undefined) {
        // 图标 24vp 无底符号；色 = 官方图标色 = 标题色同源（实测图标 #1A1A1A ≈ 标题 #1B1B1B）
        SymbolGlyph(item.icon)
          .fontSize(24)
          .fontColor([cardTitleColor()])
      }
      Column({ space: 2 }) {
        // ★ 单行省略（2026-09-13 真机报障实锤：内置元技能 90 字触发描述在助手技能页副标题位
        // 溢出卡外）——行高是固定分档模型（64/56vp + 垂直居中），多行文本物理上放不下，长
        // 文本一律单行省略；标题同款一并收口（长技能名/长模板名同族隐患）
        Text(item.label)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.secondary !== undefined) {
          Text(item.secondary)
            .fontSize(14)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (item.toggleValue !== undefined && item.onToggle !== undefined) {
        // 开关行：官方 Toggle 可点自切换 = 唯一控制面（2026-09-08 统一形态——不再有纯视觉
        // 形态；行点击不切换，故无双触发面）
        Toggle({ type: ToggleType.Switch, isOn: item.toggleValue() })
          .onChange((isOn: boolean): void => {
            this.onToggleUp(item, isOn);
          })
      } else if (item.selectedMark !== undefined && item.selectedMark()) {
        // 选中标记（2026-09-16 单条消息指定技能页首用）：非开关行的尾部状态位——当前选中项
        // 行尾打勾（官方强调色符号；20vp 与 Toggle 视觉重量相当）。与 Toggle 互斥（else 链）
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([$r('sys.color.comp_background_emphasize')])
      }
    }
    .width('100%')
    .height(item.secondary !== undefined ? ROW_HEIGHT_WITH_SUB : ROW_HEIGHT_SINGLE)
    // 行内左右 padding 8（内容左缘 = 行 4 缩进 + 8 = 卡内 12vp，官方实测）；上下由固定
    // 行高 + VerticalAlign.Center 居中（官方模型）
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  EntryRow(item: GroupEntryItem) {
    // 行缩进 4vp 由外包容器 padding 承担（margin + width 100% 组合失效原因见头注释
    // 「点按」节）——蒙层 = 卡宽 −8vp 的悬浮圆角条，四周均匀露白，官方已配对设备卡同款
    Column() {
      Button() {
        this.RowContent(item)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      // 蒙层圆角与卡体同值 16（卡片圆角变更时两处同改——dshinhm 一七八改铁律）
      .borderRadius(16)
      // 可按压 = 跳转行专属（开关行/只读行去反馈——按下去没反应是误导）
      .stateEffect(this.isClickableRow(item))
      .onClick(() => {
        // 行点击：跳转行 = 回调上抛（SettingsPage/InfoPage 先例）；开关行 = 空转（唯一控制面
        // 是 Toggle 自身，2026-09-08 统一形态）；只读行 = 无回调天然空转
        if (this.isClickableRow(item) && item.onClick !== undefined) {
          item.onClick();
        }
      })
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  build() {
    Column() {
      ForEach(this.items, (item: GroupEntryItem, index: number) => {
        this.EntryRow(item)
        // 行间分割线（末行不显——华为系统设置组卡同款；左缩进 = dividerLeft 与标题列
        // 对齐，右缩进 4 = 行缩进（右端到行右缘，官方实测）；0.5vp 官方实测细线）
        if (index < this.items.length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .margin({ left: this.dividerLeft, right: 4 })
        }
      }, (item: GroupEntryItem): string =>
        // 键含状态（2026-09-08 开关系）：label + 开关值——组件确实重渲时（如 appColorMode
        // 变化）值变键变行重建拉新 Toggle 值；跨父组件状态变化的刷新仍靠调用方键变重建
        //（跳转行无 toggleValue，键 = label 纯静态——SettingsPage 行为零变化）
        item.label + (item.toggleValue !== undefined ? String(item.toggleValue()) : ''))
    }
    // 宽度 = CARD_PANEL_WIDTH（100%−32vp，卡左缘与标题栏主标题左缘对齐——全应用卡宽基准，
    // 官方系统设置卡同值）；圆角 16（2026-09-07 决明拍板项目统一——官方实测 20 不引入）；
    // 卡顶/底 padding 4（官方实测，行缩进 4 与分割线右端 4 同体系）
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding({ top: 4, bottom: 4 })
  }
}
