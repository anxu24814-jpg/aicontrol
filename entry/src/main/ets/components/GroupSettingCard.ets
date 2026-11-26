// 「组卡」规范单源（设置页组卡化：参照 dshinhm「我的」页组卡形态，样式按官方系统设置
//「星闪和蓝牙 → 已配对设备」卡真机实测规格复刻）。
// · 选型理由（「实现选型三级优先」第 3 级登记）：HDS **无组卡组件**——@kit.UIDesignKit
//   全导出清单核实只有 HdsListItemCard 单行卡；华为系统设置的组卡 = 设计规范形态非组件。
//   本组件 = **官方基础组件拼装**（Column 卡底 + 官方 Divider + Button 行原生按压 +
//   SymbolGlyph 图标 + 官方语义色），零第三方零自绘样式。
// · ★ 官方实测基准（2026-09-07 真机 uitest dumpLayout 量测，density 3.5）：
//   · 卡宽 = 屏宽 −32vp（左右 16vp，与 CARD_PANEL_WIDTH 同构 ✓）；卡上下 padding **4vp**；
//     圆角 = 项目统一 **CARD_RADIUS（20vp，2026-10-26 决明拍板统一并单源化）**
//   · **行高固定分档**：带副标题 **64vp** / 无副标题 **56vp**（两行标题仍 56——内容垂直
//     居中，非内容自适应）
//   · 行内缩进：行相对卡左右各 **4vp**（按压蒙层比卡略短）；行内左 padding **8vp** →
//     图标左缘 = 卡内 12vp
//   · 图标 = SymbolGlyph **24vp** 无底；图标-标题间距 **16vp** → 标题左缘 = 卡内 52vp ✓
//   · 标题 16fp Medium；副标题 **14fp**（官方实测行盒拟合，dshinhm 版 13fp 偏小）；标题-
//     副标题间距 2vp
//   · Divider：**0.5vp** 视觉细线（3.5x 下 1vp=3.5px 过粗）；色用 cardBorderColor（深浅
//     分治）；**左缩进 = 图标右缘 + 8vp**；右端到行右缘；末行不显
// · dshinhm 版差异（按官方实测全面对齐）：图标改 SymbolGlyph 24vp 无底（零图片资源）；
//   行高改固定分档 56/64；间距 8→16；副标题 13→14fp；卡补上下 4vp padding；Divider
//   1vp→0.5vp、左缩进 56→44、右缩进 16→4。
//   · 行文本一律**单行省略**（标题与副标题均 maxLines 1 + Ellipsis，2026-09-13 真机报障
//     实锤）：行高是固定分档模型，多行文本物理上放不下——长文本不设省略会溢出卡外
// · 点按：全行圆角（与卡体同值 CARD_RADIUS）+ 蒙层比卡略短 + 官方原生按压。★ 蒙层缩进
//   4vp 用行外包 Column padding 实现——原 Button margin 4 + width 100% 组合真机实测蒙层
//   与卡左右等宽未缩进，且卡上下 padding 4 使蒙层顶下移后与卡圆角错位出楔形白边 = 决明
//   实锤，勿改回 margin 写法。
// · ★ 彩色图标（2026-10-19 决明指令「设置页图标改彩色，颜色参照系统设置，其他页不改」；
//   2026-11 偏好退役后外观固化为 **彩色 + 圆角矩形**，不再有单色/圆形变体）：
//   行可传 iconBg（色板常量 SETTING_ICON_* 由本件导出）→ 图标位恒渲染 **38vp 圆角矩形彩底 +
//   23vp 同色符号**（底形半径 SETTING_ICON_SQUARE_RADIUS；深浅两套按 appColorMode 切换）。
//   几何定稿（2026-10-27 放大左移笔）：彩底行行高统一 **60**（判据取数据 iconBg + icon，
//   彩色形态已固化、行高不随开关跳变）、底形视觉右移 3（translate 渲染期变换
//   不参与测量）→ 视觉左距 = 上留白 = 15、中心 (34,34) 落卡圆角 45° 对角线（2026-10-26
//   同心笔定「**到边等距**」判据，此前「左右等距」判据退役）；Row space 16 → 标题左缘与
//   分割线左缩进 **66**（DIVIDER_LEFT_ICON_LARGE）。
//   ★ 未传 iconBg 的行仍走 **24vp 裸符号**（title 色，行高 56/64）——该形态不受颜色/形状
//   偏好管辖（那项只切彩底行），偏好退役后照留；助手头像选择面板三行即此形态，
//   删分支 = 图标消失 + 文字左移 40vp（2026-11-12 自检轮实锤）。
//   ★ 彩底图形本体抽为全局 @Builder `SettingRowIcon`（本件导出），全仓三处消费（本件组卡行 /
//   WebServiceSettingsPage 两卡 / AssistantEditPage 两卡）一律调它，禁再内联复写。
//   ★ 铺设判据（2026-10-19 决明两轮拍板）：**所有有图标的入口页与设置项页都上彩**——
//   现役彩色页 = 设置主页 / 偏好设置 / 工具调用 / 更多信息 / 助手编辑页三行 / 偏好三级
//   三页 / 存储管理分类行；弹层与无图标行不涉及。
//   ★ 2026-10-20 组卡同色笔（决明「类似 RIK，同板块/组卡内图标同色」）：同一张组卡内
//   所有行的 iconBg 取同色（卡内主色，并列取首行），跨卡保留五色分布。
// · 接口：icon 缺省 = 无图标行（dividerLeft 传 8 对齐标题左缘）；行形态——
//   ①跳转行 = onClick；②开关行 = toggleValue + onToggle 两字段齐全，行尾渲染官方 Toggle：
//   **Toggle 可点自切换（onChange 上行）= 唯一控制面**，行本身不可点且无按压反馈
//  （2026-09-08 决明拍板「只能通过点击开关控制开闭」，全应用统一；原「纯视觉 Toggle +
//   整行点击」形制已废，组件行为单一来源）；③只读行 = 两类回调全缺（无开关无跳转、去按压
//   反馈防「按得下去、什么也没发生」误导；工程内暂无消费方——保留待复用，勿当在用形态读）；
//   ④选中行 = onClick + selectedMark（行尾官方勾选符号标当前项，无 Toggle）；⑤入口行 =
//   跳转行 + chevron: true（行尾灰箭头示意「可进下一页」，形态照 AboutPageCards 回退分支
//   先例）；⑥数值行 = 行尾数值文本 valueText（15fp 次要色 + 单行省略）。
//   ★ 行尾次序（2026-10-07 决明「箭头和数据交换位置」）：数值恒为行尾末位——右缘贴行右
//   内缘，同卡带数值各行数值右缘自然成一条竖线；入口箭头在数值左侧。行尾次序 = 本组件
//   单源，页面装配零改动。
//   ⑦行标题字体（首用 = 外观显示页字体段选择组卡——选项行标题以对应字体渲染「自证」）：
//   传 labelFontFamily = 自证支显式挂族名；缺省支不设 fontFamily、吃 Text 官方缺省 →
//   全局态随应用级字体槽位跟随正文字体（显式族名会钉死系统字体），实现见 RowContent 双分支。
//   ★ 开关显示刷新责任在调用方（2026-09-08 真机报障实锤）：items 是普通成员入参，父组件
//   重渲不更新普通成员，本组件自身又无状态变化 → build 不重跑 → Toggle 定格首帧（症状 =
//   数据已变、开关不动、退出重进才正确）。调用方须把组卡放进「键含开关态/纪元」的 ForEach
//  （键变重建 = 规范 §3 主通道——先例 AssistantToolsPage.toggleEpoch / Pref 三页组键）。
//   组件内 ForEach 键含开关值只在组件确实重渲时才起作用，不能替代调用方键。
//   ★ 同族依据与取舍：坑16 家族判据「状态驱动的列表 ForEach 键须含该状态」+ dshinhm 坑57
//  「普通成员入参不重渲染」（本组件 items 同源）；子组件 @Prop 承载 = 坑16 家族禁区
//  （@BuilderParam/PageShell.content 内 @Prop 不随父状态更新，UI 冻结首帧）。取舍 = 键变
//   重建切换无过渡动画。
// · 未来消费约定：新增组卡 = items 传 GroupEntryItem[]（label 引 SETTING_TITLE_* 常量，
//   单一来源；行点击回调内 recordRecentUse + 上抛导航壳 push；开关行 onToggle 直接写
//   @StorageLink 键，AppStorage 响应式即刷）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../common/AppPreferences';
import { CARD_PANEL_WIDTH, cardBg, cardBorderColor, cardDescColor, cardTitleColor, CARD_RADIUS } from '../common/Theme';

// 行高两档（官方实测分档模型——有副标题 64 / 无 56，固定行高 + 内容垂直居中）
const ROW_HEIGHT_WITH_SUB: number = 64;
const ROW_HEIGHT_SINGLE: number = 56;
// 彩底图标行统一 60：图标 38 在 60 行内居中 → 卡 pad 4 + (60−38)/2 = 视觉左距 15（translate 3），
// 中心 (34,34) 落 45° 线，有无副标题同档。判据取数据 iconBg + icon；彩色与圆角矩形已固化
// 为不可关闭（偏好退役），不再有形态开关、行高不跳
const ROW_HEIGHT_ICON: number = 60;
// 分割线左缩进默认值 = 卡内 44vp（有图标行口径：4 行缩进 + 8 行 pad + 24 图标 + 8 间距）；
// 无图标行传 8（对齐标题卡内 12 − 4 行缩进对称）
const DIVIDER_LEFT_ICON: number = 44;
const DIVIDER_LEFT_NO_ICON: number = 8;

// 设置图标色板（单源 = 本件；规范条文 = docs/规范-视觉色板与徽标.md §11）：
//   ★ 2026-10-26 决明拍板「完全参照 Rik 的颜色」——**色值整体直抄 RikkaHub minimal 预设
//   主题**（MinimalTheme.kt）。蓝/黄/灰 = primary/tertiary/secondaryContainer 原值；绿紫
//   minimal 无对应，按其 M3 container 规律派生（浅底淡色 + 浅符同族深色，深档深底 + 亮符）。
//   此前「压暗笔」取值与「浅底对白卡 ≥1.35 可见线」随本笔一并退役——minimal 卡底本就纯白，
//   Rik 原生观感即淡圆压白卡（决明拍板接受）。
//   ★ 取值判据（规范层，改色前先读）：浅底 CIE L* 89~95 淡色 / 浅符同色相 L* 26~37 深色；
//   深档 = 深底 L* 26~30 + 亮符 L* 85~92。派生新色按此包络取值并复算验收线，禁凭感觉加减。
//   身份色（Theme.ets IDENTITY_PALETTE）蓝紫黄灰与本表同值——两套语义、一套色源。
//   蓝 #E7F0FE / #1B4ACB（RIK 直抄）；绿 #D9EFDC / #37603F（派生）；黄 #FCEFCE / #6A5008
//   （RIK 直抄）；紫 #E2DEF5 / #4B4886（派生）；灰 #EFF0F2 / #3B3E44（RIK 直抄——
//   「更多信息 → 日志类」专色，收尾不抢色）
// 深色档 = 直抄 minimal 深色主题（蓝/黄/灰）+ 同规律派生（绿/紫），底对卡底 #1C1C1E ≥1.35：
//   蓝 #1D3E7F/#D9E4FF、绿 #244A37/#BCDFC6、黄 #5B4400/#FFE6AA、紫 #413A73/#D6CEF7、
//   灰 #3A3D43/#E2E4E8
// 验收线 = 符号 vs 底 ≥3:1（WCAG 图形元素线，非文本 4.5）；深底 vs #1C1C1E ≥1.35。调值
// 必按此复算并同步改规范 §11，禁凭感觉加减。
interface SettingIconTone {
  lightBg: string;
  lightFg: string;
  darkBg: string;
  darkFg: string;
}

const SETTING_ICON_TONES: SettingIconTone[] = [
  { lightBg: '#E7F0FE', lightFg: '#1B4ACB', darkBg: '#1D3E7F', darkFg: '#D9E4FF' },
  { lightBg: '#D9EFDC', lightFg: '#37603F', darkBg: '#244A37', darkFg: '#BCDFC6' },
  { lightBg: '#FCEFCE', lightFg: '#6A5008', darkBg: '#5B4400', darkFg: '#FFE6AA' },
  { lightBg: '#E2DEF5', lightFg: '#4B4886', darkBg: '#413A73', darkFg: '#D6CEF7' },
  { lightBg: '#EFF0F2', lightFg: '#3B3E44', darkBg: '#3A3D43', darkFg: '#E2E4E8' }
];

function findSettingIconTone(bg: string): SettingIconTone | undefined {
  for (const tone of SETTING_ICON_TONES) {
    if (tone.lightBg === bg) {
      return tone;
    }
  }
  return undefined;
}

export function settingIconBgOf(bg: string, dark: boolean): string {
  const tone: SettingIconTone | undefined = findSettingIconTone(bg);
  if (tone === undefined) {
    return bg;
  }
  return dark ? tone.darkBg : tone.lightBg;
}

export function settingIconFgOf(bg: string, dark: boolean): ResourceColor {
  const tone: SettingIconTone | undefined = findSettingIconTone(bg);
  if (tone === undefined) {
    return cardTitleColor();
  }
  return dark ? tone.darkFg : tone.lightFg;
}

export const SETTING_ICON_BLUE: string = '#E7F0FE';
export const SETTING_ICON_GREEN: string = '#D9EFDC';
export const SETTING_ICON_ORANGE: string = '#FCEFCE';
export const SETTING_ICON_PURPLE: string = '#E2DEF5';
export const SETTING_ICON_GRAY: string = '#EFF0F2';

// 彩底图标几何（SettingRowIcon 单源定稿）：38vp 底 + 23vp 符号（底形恒圆角矩形、半径
// SETTING_ICON_SQUARE_RADIUS——形状偏好已退役）；行高 60 内居中 → 视觉左距 = 上留白 = 15
export const SETTING_ICON_SIZE: number = 38;
export const SETTING_ICON_SYMBOL_SIZE: number = 23;
// 圆角方块档圆角 = 14（2026-10-31 决明拍板：初定 12〔会话徽章 36 档同尺寸级先例〕后
// 「圆角大一点点」上调定档，与助手列表卡 56 档头像圆角同值，仍在卡片圆角 CARD_RADIUS(20)
// 节奏内）；「消费侧禁另写半径」的规范口径由本常量单源承接，条文见
// docs/规范-视觉色板与徽标.md §4/§11
export const SETTING_ICON_SQUARE_RADIUS: number = 14;

// ★ 彩底行图标的**唯一实现**（2026-10-26 收口笔）：38vp 底（恒圆角矩形）+ 23vp 同色符号
// + 深浅解析 + 视觉偏移，全仓三处消费一律调本件，禁再内联复写：
//   ★ 底形固定（2026-11「图标颜色/形状」偏好退役）：底圆角恒取 SETTING_ICON_SQUARE_RADIUS(14)，
//   不再有圆形分支；@Builder 不能自持状态：重建触发由深浅模式订阅 + 组卡 ForEach 键含
//   深浅模式承担（见 build 内键注释）；签名不变，全仓调用点零改动
//   ① GroupSettingCard.RowContent（组卡行）——offsetX = **3**（行高 60 / 图标 38 → 上留白
//      15，视觉左缘 12 + 3 = 15，中心 (34,34) 落卡圆角 45° 对角线，判据见
//      docs/规范-列表卡片与组卡.md §3.1）
//   ② WebServiceSettingsPage 基础网络 / 安全保护两卡——offsetX = **3**（行口径同 ①）
//   ③ AssistantEditPage.ToolsCard / AdvancedCard（整行一张卡）——offsetX = **0**（其对齐
//      靠卡自身 padding 16，上内距 = 左内距即同心，不需额外视觉偏移）
// offsetX 是**参数**不是散落值：两种同心基准（组卡行 15 / 单行卡 16）都在本注释里说清。
@Builder
export function SettingRowIcon(icon: Resource, bg: string, dark: boolean, offsetX: number) {
  Column() {
    SymbolGlyph(icon)
      .fontSize(SETTING_ICON_SYMBOL_SIZE)
      .fontColor([settingIconFgOf(bg, dark)])
  }
  .width(SETTING_ICON_SIZE)
  .height(SETTING_ICON_SIZE)
  // 底形恒圆角矩形——形状偏好已退役、行为固化为不可关闭，不再有圆形半径分支
  .borderRadius(SETTING_ICON_SQUARE_RADIUS)
  .backgroundColor(settingIconBgOf(bg, dark))
  .justifyContent(FlexAlign.Center)
  .translate({ x: offsetX })
}

// 彩底行的分割线左缩进：按**视觉**底形右缘 53（38 布局右缘 50 + 视觉右移 3）+ 间距 13 =
// 66vp（无底页仍用组件缺省 44）——彩色页调用方显式传入，几何算式与
// rowSpace 同源；左端**跟标题左缘**，右端收至卡内 12（= 内容右缘，见 build 内 Divider
// margin right）。底形恒圆角矩形、尺寸与偏移固定，本值恒定
export const DIVIDER_LEFT_ICON_LARGE: number = 66;

export interface GroupEntryItem {
  // 左侧图标（sys.symbol.*；缺省 = 无图标行，dividerLeft 传 DIVIDER_LEFT_NO_ICON）
  icon?: Resource;
  // 图标底色（取 SETTING_ICON_* 常量）：传了 = 图标位渲染 38vp 浅色圆角矩形彩底 + 23vp
  // 同色符号（深浅两套，按 appColorMode 切换）——彩色与形状偏好已退役、外观固化为不可关闭；
  // 缺省 = 24vp 灰黑裸符号（该形态不受颜色/形状偏好管辖，偏好退役后照留）。有底页
  // dividerLeft 须传 DIVIDER_LEFT_ICON_LARGE（66）。类型为 string（全仓传值均为
  // SETTING_ICON_* 常量，收窄后可直接喂 SettingRowIcon）
  iconBg?: string;
  // 行标题（调用方引用 SETTING_TITLE_* 常量，保持单一来源）
  label: string;
  // 副标题（14fp 次要色；缺省 = 单行——行高自动走 56vp 档）
  secondary?: string;
  // 行标题字体族（首用 = 外观显示页字体段选择组卡「自证」）：缺省不设 fontFamily、吃真
  // 缺省跟随全局态（显式族名会钉死系统字体）
  labelFontFamily?: string;
  // 行尾数值文本：非空 = 渲染（★ 恒为行尾末位——右缘贴行右内缘，15fp 次要色 + 单行省略；
  // 入口箭头在数值左侧）；缺省不渲染。用途 = 数据行组卡（行尾报该行当前数值）
  valueText?: string;
  // 行点击回调（跳转行必备；开关行可省——用下方 toggleValue/onToggle 两字段）
  onClick?: () => void;
  // 开关行取值（与 onToggle 齐全 = 开关行——行尾渲染官方 Toggle，可点自切换）。调用方
  // 闭包读状态（@StorageLink/@State——响应式，键求值时现读）
  toggleValue?: () => boolean;
  // 开关行写值（调用方写状态：@StorageLink 写即持久化 / @State 写后落库；特殊逻辑——
  // 失败回滚 + toast——在回调内做）
  onToggle?: (isOn: boolean) => void;
  // 非开关行的尾部状态位：true = 行尾渲染官方勾选符号（当前选中项标记）。与
  // toggleValue/onToggle 互斥消费（渲染分支为 else if）。★ 指定技能页退役后本字段现役零
  // 消费——保留为共用件能力位（将来同类选中行可直接复用），104 组打勾位钉照旧守本件形态
  selectedMark?: () => boolean;
  // 入口行右箭头：true = 行尾渲染 chevron_right 灰箭头（「可进下一页」视觉指引，形态照
  // AboutPageCards 回退分支先例；渲染分支在 selectedMark 之后，与 Toggle/勾选互斥）；缺省
  // 不渲染
  chevron?: boolean;
  // 行可用态（首用 = 存储管理页清理面板行卡）：false = 整行置灰不可点（官方 .enabled——
  // 置灰后点击由系统拦截，配合去按压反馈不误导）；缺省 = 恒可用。置灰态视觉由系统 enabled
  // 态接管，本件不另画灰样式
  enabled?: boolean;
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
  // 卡底透明度档位只读订阅（设置页签整页组卡宿主，pop 回落地的第一眼面；档位键不进
  // ForEach 键，属性级更新不触发行重建）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 图标外观恒彩色 + 圆角矩形——颜色/形状偏好已退役、行为固化为不可关闭，不再订阅任何开关，
  // 也不再有单色/圆形回退态（useColorIcon 恒 true）
  private useColorIcon(item: GroupEntryItem): boolean {
    return true;
  }

  // 当前深浅模式（图标色对切换判据；appColorMode 变化时 ForEach 键含它，行会重建）
  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // 开关行判定（toggleValue + onToggle 两字段齐全）——@Builder 内禁局部变量，收敛为方法
  private isSwitchRow(item: GroupEntryItem): boolean {
    return item.toggleValue !== undefined && item.onToggle !== undefined;
  }

  // 可按压判定（跳转行专属）：开关行与只读行都去按压反馈——开关行「行点击空转」，
  // 只读行无任何交互
  private isClickableRow(item: GroupEntryItem): boolean {
    return !this.isSwitchRow(item) && item.onClick !== undefined;
  }

  // Toggle 上行（开关行唯一控制面；行点击不切换——2026-09-08 统一形态）
  private onToggleUp(item: GroupEntryItem, isOn: boolean): void {
    if (this.isSwitchRow(item) && item.onToggle !== undefined) {
      item.onToggle(isOn);
    }
  }

  // 行内元素间距：彩底行 16（12 + 38 底形 + 16 = 标题左缘 66vp；视觉底形右缘 53 + 间距 13 =
  // 视觉字形间距 ≈13 与参考对齐）——图标外观已固化，不再有单色普通行形态
  private rowSpace(item: GroupEntryItem): number {
    // 恒 16，保留方法位承接后续几何调整
    return this.useColorIcon(item) ? 16 : 16;
  }

  // 行高：彩底图标行统一 60（有无副标题同档）；无底行仍按官方两档 64/56
  private rowHeight(item: GroupEntryItem): number {
    if (item.iconBg !== undefined && item.icon !== undefined) {
      return ROW_HEIGHT_ICON;
    }
    return item.secondary !== undefined ? ROW_HEIGHT_WITH_SUB : ROW_HEIGHT_SINGLE;
  }

  // 分割线左缩进：图标外观恒彩色（偏好退役），恒取调用方传入值（彩底页 66），不再有
  // 「关闭彩色回退 44」分支
  private dividerIndent(): number {
    return this.dividerLeft;
  }

  // 行内容（可点行专属）：行高固定分档 + 内容垂直居中（官方行高模型，勿改回自适应 padding
  // ——48vp 自适应版 = dshinhm 旧规格，2026-09-07 决明「纵向宽度偏窄」实锤）
  @Builder
  RowContent(item: GroupEntryItem) {
    Row({ space: this.rowSpace(item) }) {
      // 图标两形态：传了 iconBg = 彩底行（恒彩色 + 圆角矩形，偏移 3 为「到边等距」同心
      // 判据的组卡行定值——视觉左距 = 上留白 = 15，中心 (34,34) 落卡圆角 45° 线，几何沿革
      // 见文件头「彩色图标」节）；未传 iconBg = 无底色行仍 24vp 裸符号（★ 该形态不受
      // 「图标颜色/形状」偏好管辖——那项只切彩底行，故偏好退役后仍须保留；助手编辑页头像
      // 选择面板三行走的正是本分支，删掉即图标消失、文字左移 40vp = 2026-11-12 自检轮实锤）
      if (item.icon !== undefined) {
        if (item.iconBg !== undefined) {
          SettingRowIcon(item.icon, item.iconBg, this.isDarkMode(), 3)
        } else {
          // 图标 24vp 无底符号；色 = 官方图标色 = 标题色同源（实测图标 #1A1A1A ≈ 标题 #1B1B1B）
          SymbolGlyph(item.icon)
            .fontSize(24)
            .fontColor([cardTitleColor()])
        }
      }
      Column({ space: 2 }) {
        // ★ 单行省略（2026-09-13 真机报障实锤：长副标题溢出卡外）——行高是固定分档模型，
        // 多行文本物理上放不下，标题与副标题一律单行省略
        if (item.labelFontFamily !== undefined) {
          // 自证支：显式挂族名（if 分支内 item.labelFontFamily 已窄化为 string，可喂
          // fontFamily 签名 string | Resource）
          Text(item.label)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontFamily(item.labelFontFamily)
        } else {
          // 缺省支：不设 fontFamily，吃 Text 官方缺省 → 全局态随应用级字体槽位跟随正文字体。
          // 禁加回显式系统族名——显式 fontFamily 优先于应用级槽位，会把行标题钉死系统字体
          //（I5 负判据守）
          Text(item.label)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
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
        // 开关行：官方 Toggle 可点自切换 = 唯一控制面（行点击不切换，无双触发面）
        Toggle({ type: ToggleType.Switch, isOn: item.toggleValue() })
          .onChange((isOn: boolean): void => {
            this.onToggleUp(item, isOn);
          })
      } else if (item.selectedMark !== undefined && item.selectedMark()) {
        // 选中标记：非开关行的尾部状态位——当前选中项行尾打勾（官方强调色符号；20vp 与
        // Toggle 视觉重量相当）。与 Toggle 互斥（else 链）
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([$r('sys.color.comp_background_emphasize')])
      } else if (item.chevron === true) {
        // 入口行右箭头：灰箭头示意「可进下一页」（cardDescColor）。20vp 与行尾勾选标记同
        // 重量档；右缘留 4vp 呼吸（原贴行右内缘观感「顶到边」）。全仓带箭头行统一随形
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([cardDescColor()])
          .margin({ right: 4 })
      }
      if (item.valueText !== undefined) {
        // 行尾数值（★ 恒为行尾末位——右缘贴行右内缘，同卡带数值各行右缘成一条竖线；入口
        // 箭头在数值左侧）；单行省略防长文本撑破固定行高
        Text(item.valueText)
          .fontSize(15)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(this.rowHeight(item))
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
      .borderRadius(CARD_RADIUS) // 蒙层圆角与卡体同值 CARD_RADIUS（单源后天然同值）
      // 可按压 = 跳转行专属（开关行/只读行去反馈——按下去没反应是误导）；置灰行
      //（enabled = false）官方拦截点击并去按压
      .stateEffect(this.isClickableRow(item))
      .enabled(item.enabled !== false)
      .onClick(() => {
        // 行点击：跳转行 = 回调上抛；开关行 = 空转（唯一控制面是 Toggle 自身）；只读行 =
        // 无回调天然空转
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
        // 行间分割线（末行不显——华为系统设置组卡同款；左缩进 = dividerLeft 与标题列对齐，
        // 右缩进 = 卡内 12 = 内容右缘；0.5vp 官方实测细线）
        if (index < this.items.length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .margin({ left: this.dividerIndent(), right: 12 })
        }
      }, (item: GroupEntryItem): string =>
        // ★ 键含状态：label + 开关值——组件确实重渲时值变键变行重建拉新 Toggle 值；跨父
        // 组件状态变化的刷新仍靠调用方键变重建（跳转行无 toggleValue，键 = label 纯静态）。
        // 彩底行键再含深浅模式防切深浅时图标定格旧色（Toggle 定格同根因）；图标外观已固化
        // 为彩色 + 圆角矩形（偏好退役），不再含颜色开关态与形状变体后缀
        item.label + (item.toggleValue !== undefined ? String(item.toggleValue()) : '') +
          (item.iconBg !== undefined ? '#color' + this.appColorMode : ''))
    }
    // 宽度 = CARD_PANEL_WIDTH（全应用卡宽基准，官方系统设置卡同值）；圆角 = CARD_RADIUS；
    // 卡顶/底 padding 4（官方实测，行缩进 4 与分割线右端同体系）
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 4 })
  }
}
