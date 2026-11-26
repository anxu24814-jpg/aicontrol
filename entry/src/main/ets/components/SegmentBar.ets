// 官方分段胶囊按钮（CapsuleSegmentButtonV2，@since 18）公共封装：
// 全项目消费点数 = **30 处 / 21 文件**（处数沿革见下；文件数 = 2026-11-18 侧栏优化③笔随形——
// 剥注释实测，2026-11-12 偏好开关批自检轮曾记 21 文件、原头注释「22 文件」为 11-09 笔遗留
// 失实值）：五处直调消费收编进本文件新立的
// SettingSegmentRowCard 单源件〔智感握姿 / 启动进入两卡（2026-11-17 整体退役加密会话笔
// 撤生物识别卡）；★ 2026-11-12 偏好开关批：
// 外观图标形状 / 会话排序两卡随功能退役撤除〕，本文件
// +1 处；背景生效范围 / 字体生效范围两卡经该件换装不增直调位 → 35−5+1；含本文件内 2 处 =
// PageTopSegmentBand 承载件 + SettingSegmentRowCard 单源件；★ 2026-11-07 分段明细口径胶囊笔
// +1 → 32 处 / 22 文件（ContextUsageSheet 卡头「占已用/占窗口」，既有文件首消费，紧凑档第二
// 处消费点）。2026-11-12 本笔退役三卡全走单源件间接消费、不减 `SegmentBar({` 直调数，处数
// 仍 30；图标页整页删除亦不含直调位。★ 2026-11-16 挂载卡二次改版笔：MountManageCard 卡内
// 只读/读写分段胶囊随卡面改版退役（模式切换改卡「更多」菜单项），真删除非位移 −1 →
// 29 处 / 20 文件（该件退列）。★ 2026-11-18 侧栏优化③笔：DrawerSidePanel「全部/收藏」
// 自绘 chip 换装分段胶囊 +1 → **30 处 / 21 文件**（新文件首消费，B 轨 bottomBuilder 带承载
// ——materialPinned + emphasizeSelected 双档名；assert-ui-shape 68 组期望值同笔随形）。
// 由 assert-ui-shape 68 组全仓扫描对账，本行随形。
// 范围边界 = 两处自绘 chip 行（ReqLogPage 筛选 / MountManagePage 半模态模式 chips）+ 一处
// 官方 Chip 行（ModelPickerSheet 筛选）非 SegmentBar 形制未跟。★ 2026-11-11 域名确认档退役笔：
// 原第三处自绘 chip 行（HttpRequestSettingsPage 域名确认）随卡整卡删除。
// ★ 任何消费点改动先读本头注释与下方「双档参数速查表」；消费点差异参数 = 仅
// items/selectedIndex + 两处 compact 档名（图表卡卡头「图表/表格」/ 上下文用量分段明细卡
// 卡头「占已用/占窗口」）+ 对话页一处 emphasizeSelected 档名（档位是封装内命名变体，取值全在
// 本文件，**消费侧零数值覆盖**纪律），尺寸/配色/材质全部在本封装。定稿参数从此单一来源
//（勿单独乱调）；定稿过程与官方查证见 docs/变更记录.md 2026-08-20/21 相关条目。
// ★ 页顶承载（materialPinned 恒光感）：页顶分段由 HDS 标题栏下方带（bottomBuilder）承载
// 并传 `materialPinned: true`，恒以光感态呈现（内容区件在 API 26 不出材质，迁入标题栏
// 生效区即恢复；名单以 assert-ui-shape 68 组为单源）；**其余消费点不传，行为一字不变**。
// 承载几何单源 = common/Theme.ets `SEGMENT_BAR_BAND_TOP_INSET(_STATS)`；承载件 = 本文件
// 末尾 PageTopSegmentBand；重启先决与真机判据见 docs/规范-行内按钮与光感.md §7。
//
// ── 双档参数速查表（A 档 × 光感态 = 2 组；应用内唯一真值 = 下方各函数实现，本表为对照速查）──
// | 档位 | 背板 | 背板材质（backgroundSystemMaterial） | 选中项底色 | 选中项字色 | 尺寸 |
// | A 档（能力位恒真；内容区常态；★ 全白底笔后 = 灰轨道白药丸） | 官方灰阶实色（Theme.fallbackGrayBg，深浅分治，随卡底透明度档叠 alpha） | 不设（undefined） | 白底（浅 #FFFFFF 实底 / 深 #26FFFFFF 白 15% 亮胶囊——原官方默认蓝底已弃） | font_primary（浅色黑字 / 深色白字） | 32vp 胶囊 / 40vp 背板 / 四周 4vp（与光感态同参） |
// | 光感态·浅 | 不设（undefined） | resolvedUiMaterial(REGULAR+偏移+interactive+colorInvert) | #A6FFFFFF（白 65%） | font_emphasize（#007DFF 强调蓝） | 两态共用（同 A 档） |
// | 光感态·深 | 不设 | 同上 | #33FFFFFF（白 20%） | #7CB4FF（提亮蓝，可读性档） | 同上 |
// | 对话页变体（emphasizeSelected，2026-11-05 笔排除改白） | 不设 | 同上 | 浅 #1A000000 / 深 #4D006CDE | 浅 ohos_id_color_emphasize / 深 font_on_primary | 同上 |
// ★ 光感态基准档 = REGULAR（2026-10-25 决明调厚笔自官方示例同款 ULTRA_THIN 上调一档，强档
//   −1 偏移下生效 THIN）。
// ★ 尺寸档（正交于「材质/配色」两档）：**标准档**（默认 `compact: false`——除两处紧凑档
// 消费点外全部消费点）= 胶囊 32vp / 四周 4vp / 背板 40vp / 官方 14fp；**紧凑档**
//（`compact: true`——两处卡头视图切换：图表卡「图表/表格」与上下文用量分段明细卡
//「占已用/占窗口」）= 胶囊 22vp / 四周 3vp / 背板 28vp（= SEGMENT_BAR_COMPACT_HEIGHT，
// 恒等式 3+22+3=28 保四周对称）/ 选项字号 10fp；**标题带档**（`bandTier: true`——2026-11-18
// 侧栏会话二级页分段行首立，与同排 36vp 三键紧凑胶囊等高）= 胶囊 28vp / 四周 4vp / 背板
// 36vp（= SEGMENT_BAR_BAND_HEIGHT，恒等式 4+28+4=36）/ 选项字号 12fp。全白底笔后尺寸档为
// **纯尺寸档**——选中配色两档统一（非材质态白底 + font_primary，弃原官方默认蓝底白字
//——决明「蓝底有点突兀」；灰轨道白药丸 = 经典分段控件形态、零彩色不抢内容系列色），档间
// 只差几何；与 materialPinned 旁路正交。
// ★ 2026-10-29 对话页标题栏内嵌分段：本封装**零改动**（原拟增第三档「标题栏档」，实测推翻
// ——32vp 背板在 56vp 标题栏里比两侧 40vp 自绘键矮一截、热区不到官方最小 40vp，改用**标准档**
// 几何，缩短只靠消费侧定宽容器）。
// ★ 选中态强调蓝变体（2026-11-01 决明点名笔，对话页分段专用；**取代 2026-10-30「选中字
// 图标蓝」口径**——彼笔浅 #1B4ACB / 深 #D9E4FF 字色变体随本笔退役）：emphasizeSelected: true
// 时选中项统一到 HDS 蓝（浅 #007DFF / 深 #006CDE，SDK resources.txt 两档值核实）——浅色
// 白/灰胶囊原样、选中字改 $r('sys.color.ohos_id_color_emphasize')（#007DFF，与 HdsTabs 选中
// 蓝、收藏侧滑键同源）；深色选中底自白 15% 亮胶囊改**强调蓝 30% 淡染**（#4D006CDE——全饱和
// 实底 #006CDE 决明真机反馈太显眼二轮压淡，叠材质呈雾蓝明度贴近深轨道）、字改
// $r('sys.color.font_on_primary')（官方「蓝底配 font_on_primary」默认配对，恒 #ffffff，
// resources.txt 核实其两档均解析 font_on #ffffff）。可读性账：浅 #007DFF 字对白底 3.9:1
//（达大字 3:1 线、未达 4.5:1——官方 SegmentButton 默认即此配对，决明拍板接受）、深白字对
// 淡染雾蓝底 >8:1（过正文线）。消费点两处 = 对话页「全部/收藏」分段（TabMoreMenu.
// ChatTabTitleBar 标题栏覆盖层承载）+ 侧栏面板「全部/收藏」分段（DrawerSidePanel.
// BandBottomBuilder bottomBuilder 带承载，2026-11-18 侧栏优化③笔入列），其余消费点不传 =
// 原态（白胶囊 + font_primary）。
// ★ 2026-11-05 顶部白蒙层笔（决明拍板「浅色 50、深色 25、不算对话页」）：**恒光感默认支**的
// 选中项底色自「浅黑 10% / 深白 15%」改为「浅白 65%（#A6FFFFFF）/ 深白 20%（#33FFFFFF）」——
// 透明灰改透明白，绝大范围 = 顶部承载件（PageTopSegmentBand 九页 + 工作区两行带）；对话页变体
// 由上一★条形制原样持有、整支排除本笔（浅 #1A000000 / 深 #4D006CDE 不动）。A 档白底不受影响
// （非材质态分支在材质态之后，两档互不串味）。取色依据与真机判据 = 变更记录对应节。
// ★ 2026-11-05 顶部蓝字笔（决明「除对话页外，顶部分段胶囊选中时字改成蓝色，深色仍用蓝色，
// 可考虑可读性调整，但不要和对话页一样深色转白」）：**恒光感默认支**的选中字色自 font_primary
// （浅黑/深白）改为强调字蓝——浅 `$r('sys.color.font_emphasize')`（#007DFF，与对话页浅色
// 选中字同值）、深 `#7CB4FF`（提亮档：系统 font_emphasize 深色档 #5291FF 对白 20% 胶囊仅
// ≈3:1 不达正文线，提亮档 ≈4.3:1）。**选中底色零变化**（仍浅白 65% / 深白 20%）；A 档白底
// （!materialOn）保持 font_primary；对话页 emphasizeSelected 变体原样（浅蓝/深白）不随本笔。
// 可读性账（白蒙层合成后）：浅 #007DFF 对浅色胶囊 ≈3.6:1（反而优于对话页现状半透明灰底的
// ≈2.5:1）；深 #7CB4FF 对白 20% 胶囊 ≈4.3:1（背板 #1A 估，背板越亮略降、最坏 ≈3.5:1）。
// ★ A 档沿革（决明拍板）：A 档立时为纯官方零参数；后因官方默认背板（系统资源
// segment_button_v2_tab_button_background 半透明灰、几乎全透出背后内容、吸顶+内容滚过场景
// 可读性差）单项覆盖为官方灰阶实色（app.color.comp_fallback_gray 三处真机同色先例；
// 2026-10-25 键/胶囊跟随笔起迁 Theme.fallbackGrayBg 函数族并随卡底透明度档叠 alpha，app
// 资源条目退役）；尺寸 2026-09-11 起两态共用项目值（32vp 胶囊/四周 4vp）；选中底/字色
// 2026-10-16 全白底笔起项目自定义——「A 档 = 官方默认」现仅指材质不设与官方色板基。
// 早期实底态取色批次（华为运动健康截图取色）已随 A 档改造整体退役（史实见变更记录）。
// ★ 2026-09-20 应用内自检全量退役：SelfCheckPage「基础自检/高级自检」消费点随页面删除
//（24 处/20 文件 → 23 处/19 文件，位移非删除）。
// 两态切换驱动：@StorageProp(CONTENT_FALLBACK_KEY)（**能力位**、常态恒 true、用户面无入口，
// 见 common/ImmersiveLevel.ets 头注释同键条）——true = A 档（常态）；false = 光感态（华为若
// 放开内容区材质的复验/切换位）。官方行为差异：无材质（A 档）不支持选中项跟手拖拽，有材质
//（光感态）支持（真机实证）。
// ★ A 与项目「无」档的语义区别（官方开启文档原文分界）：A = backgroundSystemMaterial
// undefined = **恢复组件默认效果**（非材质；背板色已被官方灰阶实色覆盖）；项目「无」档 =
// 显式传 uiMaterial.Material.empty = **关闭沉浸光感效果** + 项目自定义其余参数——两者
// 外观与语义都不同，勿混用。
//
// 官方/自定义边界（本地 SDK d.ts 核实）：
// ① 材质自动反色 = 官方：backgroundSystemMaterial 第 6 参 colorInvert=true（官方文档示例 6
//    同款）——材质背景自动明暗反色适配前景内容；
// ② 选中项字色 = 项目自定义（官方默认 font_on_primary 白字配蓝底，底色改后白字不协调、
//    决明真机反馈后改显式指定；2026-11-05 顶部蓝字笔起按态分三支）：非材质态 font_primary
//    （浅色黑/深色白）；光感态强调字蓝（浅 #007DFF / 深 #7CB4FF 提亮档）；对话页变体浅
//    ohos_id_color_emphasize / 深 font_on_primary 白；
// ③ 选中项底色 = 项目自定义 + 手写深浅色分治：官方无「选中项材质」参数（d.ts 全字段核对）
//    且无对应半透明系统资源——光感态传透明白（浅白 65% / 深白 20%，2026-11-05 白蒙层笔；
//    改前浅黑 10% / 深白 15%），深浅色由本组件手写三元切换（非材质态白底同理由）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, CARD_RADIUS, SEGMENT_BAR_BAND_HEIGHT, SEGMENT_BAR_BAND_TOP_INSET,
  SEGMENT_BAR_COMPACT_HEIGHT, SEGMENT_BAR_HEIGHT, SEGMENT_BAR_ROW_WIDTH, cardBg, cardDescColor,
  cardTitleColor, fallbackGrayBg, selectedAccentBlue } from '../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../common/AppPreferences';

// ── 紧凑档几何（尺寸档第二档的档内取值单源）：胶囊 22vp / 背板内边距 3vp / 选项字号 10fp；
// 背板最小高取 Theme 的 SEGMENT_BAR_COMPACT_HEIGHT（28 = 3+22+3，恒等式保四周各 3vp 对称，
// 消费侧定宽容器高同引该常量）。标准档（32vp/4vp/官方 14fp）仍散在下方各函数默认支——
// 两档口径与由来见文件头「尺寸档」注 ──
const COMPACT_ITEM_MIN_HEIGHT: number = 22;
const COMPACT_BUTTON_PAD: number = 3;
const COMPACT_FONT_SIZE: number = 10;

// ── 标题带档几何（尺寸档第三档的档内取值单源，2026-11-18 侧栏会话二级页笔）：胶囊 28vp /
// 背板内边距 4vp / 选项字号 12fp；背板最小高取 Theme 的 SEGMENT_BAR_BAND_HEIGHT（36 =
// 4+28+4，恒等式保四周各 4vp 对称）。档义 = 「与 36vp 紧凑标题栏键同排的页顶带」，与卡头
// 紧凑档（22/3/28/10fp）并立——两档都由消费侧传档名、档内取值全在本文件 ──
const BAND_ITEM_MIN_HEIGHT: number = 28;
const BAND_BUTTON_PAD: number = 4;
const BAND_FONT_SIZE: number = 12;

@Component
export struct SegmentBar {
  // 选项（纯展示，普通成员——父组件构造传入，不触发子组件重渲染；变化场景无）
  items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  // 选中项索引：@Link 与父组件 @State 双向同步（父传 $selectedIndex 语法）
  @Link selectedIndex: number;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色分治选中项底色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位：A 档背板灰随档叠 alpha（页顶分段胶囊常驻面订阅即刷）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 沉浸光感整体档位（AppStorage 共享，驱动背板材质；总档「无」时显式关闭）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区能力位（**能力位**、常态恒 true、无用户入口——见 ImmersiveLevel.ets 头注释同键条）：
  // true = A 档（常态——华为新规范下内容区材质不生效，即官方标准形态）；false = 原
  // backgroundSystemMaterial 光感材质（华为放开内容区材质限制时的复验位）。AppStorage
  // 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 承载位在光感生效区内：true = 本实例由 HDS 标题栏下方带（bottomBuilder）承载——材质在
  // 生效区内有效，故**无视内容区能力位**，恒以光感态呈现；false（默认）= 内容区件，随能力位
  // 走 A 档/光感态。★ 能力位默认值不翻转（翻转会让全项目内容区按钮族从实底变「关档」），
  // 本条只给承载件一条旁路
  materialPinned: boolean = false;
  // 尺寸档（全白底笔后为**纯尺寸档**）：true = 紧凑档（胶囊 22vp / 四周 3vp / 背板 28vp /
  // 选项字号 10fp——两处卡头视图切换消费：图表卡「图表/表格」与上下文用量分段明细卡
  //「占已用/占窗口」，取值全在本文件上方三常量与 Theme 的 SEGMENT_BAR_COMPACT_HEIGHT；
  // 第二消费点按各自容器定宽容纳三字，档内字号不变）；false（默认）= 标准档（全项目定稿几何 32/4/40
  // 与官方 14fp）。消费侧只传档名不传数值；选中配色两档统一（见 selectedItemBg 注释）。
  // 与 materialPinned 旁路正交（内容区/承载位两态都可取紧凑档）
  compact: boolean = false;
  // 标题带档（36vp 背板；2026-11-18 侧栏会话二级页笔首立）：true = 胶囊 28vp / 四周 4vp /
  // 字号 12fp，与同排 36vp 三键紧凑胶囊（TitleBarKeys.TITLE_CAPSULE_COMPACT_*）等高。
  // 与 compact 互斥——两档同时传 true 时按 compact 渲染（卡头小档优先，防误传双档偷换
  // 几何）；消费侧只传档名不传数值（同 compact 纪律）
  bandTier: boolean = false;
  // 选中态强调蓝变体档（2026-11-01 决明点名笔；前身为 2026-10-30 iconBlueSelectedFont 字色
  // 变体，随本笔退役更名）：false（默认）= 白胶囊 + font_primary 原态；true = HDS 强调蓝
  // 形制（浅色只动字色、深色换淡染蓝底白字，取值与依据见头注释「选中态强调蓝变体」★条）。第三
  // 独立维（正交于材质态与尺寸档），判据写进 selectedItemBg/selectedFontColor 自身分支——
  // 不进 materialOn() 汇聚（68 白底钉禁该函数内 materialOn/compact 分叉，本档也不入该禁的
  // 语义域：那是「态不分叉」，本档是「消费点档位」分叉）
  emphasizeSelected: boolean = false;

  // 本实例是否按光感态呈现：内容区件看能力位，标题栏承载件恒光感态（唯一读点，四函数共用）
  private materialOn(): boolean {
    return this.materialPinned || !this.contentFallback;
  }

  // 双态参数簇：态判定统一走 materialOn()（承载件恒光感、内容区件随能力位）——下文
  //「contentFallback=true/false」为**内容区件**的两态口径，承载件（materialPinned）不走它。
  // contentFallback=true（默认）= A 档（背板官方灰阶实色 + 选中底/字色 = 白底 +
  // font_primary）；false = 光感态（背板材质 + 定稿选中色）。尺寸三参两态共用项目值
  //（32vp 胶囊/四周 4vp/文字边距四向 4），开关只切材质与配色。光感态背板材质（参数对齐
  // 官方 SegmentButtonV2 文档示例 6）：
  // · 基准档 REGULAR（2026-10-25 决明调厚笔自官方示例同款 ULTRA_THIN 上调一档，强档 −1
  //   偏移下生效 THIN）+ 档位偏移（弱 +1 更厚、强 -1 更薄）
  // · interactive=true：按压弹性形变 + 触点光晕；colorInvert=true：材质背板自动明暗反色
  //   （字色已按态显式指定、不依赖反色适配——2026-11-05 顶部蓝字笔起）
  // · applyShadow 默认 true（材质自带阴影）；lightEffect 用系统默认白色。
  // 分离构造（同对象双背板属性有二义性）：非本态属性传 undefined = 未设置，互不干扰。
  // 注：expanded 写法仅作注释载体——实际在 build 内局部变量展开，不写 spread（ArkTS 字面
  // 量 spread 受限，勿改回 `...this.xxx()` 形式）。

  // 背板色：A 档 = 官方灰阶实色基（Theme.fallbackGrayBg 深浅分治 + 卡底透明度档叠 alpha——
  // 按钮族/恢复键/变量插入卡三处真机同色先例）；光感态 = 不设（材质优先）
  private backButtonBg(): ColorMetrics | undefined {
    if (!this.materialOn()) {
      return ColorMetrics.resourceColor(
        fallbackGrayBg(this.appColorMode, this.cardAlphaLevel));
    }
    return undefined;
  }

  // 选中项底色：非材质态（内容区常态——标准档与紧凑档同款）= **白底**（浅色 #FFFFFF 实底 /
  // 深色 #26FFFFFF 白 15% 亮胶囊；灰轨道白药丸 = 经典分段控件形态、零彩色不抢内容系列色，
  // 弃原官方默认蓝底）；材质态（页顶承载恒光感）= 透明白（浅白 65% / 深白 20%，2026-11-05
  // 决明白蒙层笔，见函数体注释）。对话页变体（emphasizeSelected）整支排除本笔——深色 HDS
  // 强调蓝底、浅色半透明灰原样（口径见头注释★条）
  private selectedItemBg(): ColorMetrics {
    const dark: boolean = this.appColorMode ===
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    if (this.emphasizeSelected) {
      // 对话页变体整支排除 2026-11-05 白蒙层笔（决明「不算对话页」）：深色淡染蓝原样
      //（2026-11-01 二轮压淡，依据见头注释★条）；浅色半透明灰原样——该页恒 materialPinned，
      // 改前浅色即落本值 #1A000000。对话页选中观感由 11-01 拍板独立持有，不随顶部白蒙层改色
      return ColorMetrics.resourceColor(dark ? '#4D006CDE' : '#1A000000');
    }
    if (!this.materialOn()) {
      return ColorMetrics.resourceColor(dark ? '#26FFFFFF' : '#FFFFFF');
    }
    // 光感态（恒光感顶部承载件，2026-11-05 决明白蒙层笔）：浅色黑 10% 透明灰 → 白 65%
    //（#A6FFFFFF）、深色白 15% → 白 20%（#33FFFFFF）。定值与二轮拍板 = 决明（初版 50/25 落码
    // 后改值）；物理账 = 白蒙层在浅背板上靠提亮立选中，alpha 越低越轻灵、选中感越弱（65% 对
    // 浅背板约 1.17:1，仍弱于原黑 10% 的 1.26:1）；深色 20% 对深背板约 2.0:1，比原白 15% 的
    // 1.6:1 更立得住
    return ColorMetrics.resourceColor(dark ? '#33FFFFFF' : '#A6FFFFFF');
  }

  // 选中项字色三支（底色一律不动，2026-11-05 顶部蓝字笔只动字）：
  // · 非材质态（A 档白底胶囊）= font_primary（浅色黑 / 深色白）——官方默认 font_on_primary
  //   白字配白底不可读，故显式覆盖；
  // · 光感态（顶部承载件，materialOn）= **强调字蓝单源** Theme.selectedAccentBlue——浅
  //   $r('sys.color.font_emphasize')（#007DFF，与对话页浅色选中字同值）、深 #7CB4FF 提亮档
  //   （系统 font_emphasize 深色档 #5291FF 对白 20% 胶囊仅 ≈3:1，提亮到 ≈4.3:1 保可读）；
  //   菜单项尾选中勾同函数消费，故「顶部分段选中」与「菜单选中勾」恒同色。决明「深色仍蓝、
  //   不学对话页转白」
  // · 变体支（emphasizeSelected，两消费点 = 对话页分段 + 侧栏面板分段〔2026-11-18 优化③笔〕）
  //   = 浅 HDS 强调蓝 / 深 font_on_primary
  //   白（深色胶囊已换蓝底，白字为官方蓝底配对；对比账见头注释★条）——本笔不碰
  private selectedFontColor(): ColorMetrics {
    const dark: boolean = this.appColorMode ===
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    if (this.emphasizeSelected) {
      if (dark) {
        return ColorMetrics.resourceColor($r('sys.color.font_on_primary'));
      }
      return ColorMetrics.resourceColor($r('sys.color.ohos_id_color_emphasize'));
    }
    if (this.materialOn()) {
      // 顶部光感态选中字色 = 选中态强调蓝单源；菜单项尾选中勾同函数消费，改色只动
      // Theme.selectedAccentBlue，本函数体不再散抄浅深字面量（2026-11-15 勾色笔）
      return ColorMetrics.resourceColor(selectedAccentBlue(this.appColorMode));
    }
    return ColorMetrics.resourceColor($r('sys.color.font_primary'));
  }

  // 选中胶囊高度：两态共用 32vp——官方默认 36vp 与本项目 32vp 并存时开关会在两套几何间跳变；
  // 统一后开关只切材质与配色（定稿史见 build 注释）。紧凑档分支：22vp；标题带档分支：28vp
  private itemMinH(): LengthMetrics {
    if (this.bandTier) {
      return LengthMetrics.vp(BAND_ITEM_MIN_HEIGHT);
    }
    return this.compact ? LengthMetrics.vp(COMPACT_ITEM_MIN_HEIGHT) : LengthMetrics.vp(32);
  }

  // 背板内边距：两态共用 4vp——与 32vp 胶囊配合实现四周各 4vp 对称（须与 itemMinHeight
  // 联动修改，见 build 注释）。紧凑档分支：3vp（与 22vp 胶囊配合四周各 3vp——恒等式
  // 3+22+3=28）；标题带档分支：4vp（与 28vp 胶囊配合四周各 4vp——恒等式 4+28+4=36）
  private buttonPad(): LengthMetrics {
    if (this.bandTier) {
      return LengthMetrics.vp(BAND_BUTTON_PAD);
    }
    return this.compact ? LengthMetrics.vp(COMPACT_BUTTON_PAD) : LengthMetrics.vp(4);
  }

  // 胶囊内部文字边距：两态共用四向 4vp（start/end 由官方默认 8vp 收窄——控制胶囊内文字
  // 边距，不影响胶囊相对背板位置）
  private itemPad(): LocalizedPadding {
    return {
      top: LengthMetrics.vp(4),
      bottom: LengthMetrics.vp(4),
      start: LengthMetrics.vp(4),
      end: LengthMetrics.vp(4)
    };
  }

  // 背板最小高：标准档不传（undefined = 官方默认，
  // sys.float.segment_button_v2_singleline_background_height = 40vp——与 4+32+4=40 恒等，
  // 官方默认即所求，勿多传）；紧凑档必须显式传 28vp——官方默认 40vp 兜底会把背板撑住
  //（官方布局 = 背板高 max(按钮最小高, 边距×2 + 项高)，3+22+3=28 < 40 时不传就缩不下来）；
  // 标题带档同理由显式传 36vp（4+28+4=36 < 40）
  private buttonMinH(): LengthMetrics | undefined {
    if (this.bandTier) {
      return LengthMetrics.vp(SEGMENT_BAR_BAND_HEIGHT);
    }
    return this.compact ? LengthMetrics.vp(SEGMENT_BAR_COMPACT_HEIGHT) : undefined;
  }

  // 选项字号：标准档不传（undefined = 官方默认 14fp——d.ts 实读，勿照记忆写值）；紧凑档
  // 10fp（与图表卡标题 11fp 差 1fp，在防回归钉 ±1fp 容差内——该同号判据只针对图表卡；
  // 第二消费点分段明细卡标题 15fp 刻意用同档小字，容器按三字选项另定宽）；标题带档 12fp
  //（28vp 胶囊内的比例与紧凑档 10/22 同档）。选中/未选中两参同源（官方两参各自默认 14fp，
  // 须双传，只传一个另一态不生效）
  private compactFontSize(): LengthMetrics | undefined {
    if (this.bandTier) {
      return LengthMetrics.fp(BAND_FONT_SIZE);
    }
    return this.compact ? LengthMetrics.fp(COMPACT_FONT_SIZE) : undefined;
  }

  // 背板材质：A 档 = 不传（无材质，背板即官方默认资源色）；光感态 = 沉浸光感材质（参数解析
  // 见上方双态参数簇注释；基准档 REGULAR——真机仍嫌透则再上一档基准，单行改动）
  private backMaterial(): uiMaterial.Material | undefined {
    return this.materialOn() ?
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
        this.immersiveLevel, true, true, true) : undefined;
  }

  build() {
    // 官方单选胶囊型分段按钮（CapsuleSegmentButtonV2，@since 18）。
    // ★ 宽度：官方无宽度参数且不支持通用属性（width 无效），组件宽度 = 父容器宽度
    //（选项等分撑满）——使用处外层包 CARD_PANEL_WIDTH 容器居中约束（见 common/Theme.ets
    // CARD_PANEL_WIDTH 注释）。
    // ★ 选中胶囊尺寸与四周等距（两轮真机 uitest 实测定稿；两态共用本几何）：
    // 官方布局 = 胶囊（选项区）与背板「内边距对齐」（顶对齐 + buttonPadding 顶部间隙），
    // 不做垂直居中；背板高 = max(buttonMinHeight 官方资源 40vp, buttonPadding×2 + 项高)。
    // ① 首版缩至 32vp 未动 buttonPadding（默认 2vp）：顶距 2vp、底距 40−2−32=6vp → 偏上
    // 4vp（决明反馈根因）；② 恢复 36vp 官方默认：2+36+2=40 上下对称但胶囊偏大；
    // ③ 光感态定稿：32vp + buttonPadding 4vp——4+32+4=40 恰好等于背板最小高、不撑高，
    // 选中胶囊相对背板上下左右各 4vp 完全对称（决明要求「32 且四周各 4」）；
    // ④ 几何统一（决明「把官方的蓝色选中胶囊大小与光感的统一，这样两者就只有材质差异」）：
    // A 档尺寸三参与光感态完全同参，恒等式 4+32+4=40 保证背板恒 40vp（SEGMENT_BAR_HEIGHT
    // 与悬浮层留白计算零扰动）——开关自此只切材质与配色；
    // ⑤ 紧凑档（仅图表卡卡头）：胶囊 22vp / 边距 3vp / 背板最小高 28vp（显式传——官方默认
    // 40vp 兜底会撑住背板）/ 字号 10fp；恒等式 3+22+3=28 同保四周各 3vp 对称。标准档四值
    // 不动（①~④定稿几何即其现态）。
    // itemPadding 四周 4vp（top/bottom 恰为官方默认 padding_level2=4vp，start/end 由官方
    // 默认 padding_level4=8vp 收窄为 4vp）——控制胶囊内部文字边距，不影响胶囊相对背板位置；
    // 文字在胶囊内垂直居中（官方实现）。
    // 官方资源数值（SDK previewer resources.txt 核实）：背板高 40vp
    //（segment_button_v2_singleline_background_height）、选中胶囊默认高 36vp
    //（segment_button_v2_singleline_selected_height）、padding_level1=2vp、padding_level2=4vp
    CapsuleSegmentButtonV2({
      items: this.items,
      selectedIndex: this.selectedIndex,
      $selectedIndex: (index: number) => {
        this.selectedIndex = index;
      },
      // 外观参数（解析见上方双态参数簇注释；ColorMetrics 需 resourceColor 包装，参数类型为
      // ColorMetrics 不接受裸字符串）
      itemSelectedBackgroundColor: this.selectedItemBg(),
      itemSelectedFontColor: this.selectedFontColor(),
      // 选项字号（紧凑档 10fp；标准档 undefined = 官方 14fp——选中/未选中两参同源双传）
      itemFontSize: this.compactFontSize(),
      itemSelectedFontSize: this.compactFontSize(),
      itemMinHeight: this.itemMinH(),
      // 背板最小高（紧凑档 28vp；标准档 undefined 即官方默认 40vp——见 buttonMinH 注释）
      buttonMinHeight: this.buttonMinH(),
      // 背板内边距（四周统一，两态共用 4vp）：与 32vp 胶囊配合实现四周各 4vp 对称，
      // 须与 itemMinHeight 联动修改
      buttonPadding: this.buttonPad(),
      itemPadding: this.itemPad(),
      // 双态材质：A 档 = 背板官方灰阶实色（backButtonBg）+ 不设材质；光感态 =
      // backgroundSystemMaterial 材质 + 不设背板色；非本态传 undefined（可选属性 = 未设置）
      buttonBackgroundColor: this.backButtonBg(),
      backgroundSystemMaterial: this.backMaterial()
    })
  }
}

// 页顶分段胶囊「标题栏下方带」承载形态（HDS 路径专用；与 SegmentBar 同域并入本文件——它
// 只为首者服务，不另起文件）：官方《设置自定义区域》bottomBuilder 承载页顶吸顶胶囊——内容区件
// 在 API 26 不出材质（《沉浸光感简介》生效范围），迁入标题栏生效区即恢复沉浸光感。**胶囊本体
// 几何一字不动**（宽 CARD_PANEL_WIDTH、背板 40vp，参数全在 SegmentBar 内），本组件只担承载位三件：
//   ① 水平居中；
//   ② 带内下移 inset——**带顶 = 标题栏下沿，不是 topPad**（topPad 含蒙层下延 16vp，见 Theme
//      SEGMENT_BAR_BAND_TOP_INSET 注释；默认 8 = 页顶原 `margin top: topPad − 8` 的等价点）；
//   ③ 整带命中透传（hitTest Transparent：带体不挡下方列表拖动，胶囊自身仍可点选/跟手）。
// 使用处 = 消费页组件内 @Builder 包一层交给 hdsTitleBarOptions 第 8 参（坑30：builder 必须是
// 组件内 @Builder）；内容区悬浮层已随 2026-10-31 撤 HDS 回退兜底笔整体退役，本承载为唯一
// 路径（禁双份）。
@Component
export struct PageTopSegmentBand {
  // 胶囊选项（纯展示普通成员——SegmentBar 契约）
  items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  // 选中索引（@Link 与页面 @State 双向同步，同 SegmentBar）
  @Link selectedIndex: number;
  // 带内下移量（vp）：默认 8 = 页顶常规现状位置；用量统计/费用统计两页传 STATS 档 16
  //（该两页现状 `margin top: topPad` 不探入蒙层，各保各自现状——Theme 常量注释）
  inset: number = SEGMENT_BAR_BAND_TOP_INSET;

  build() {
    Row() {
      Column() {
        SegmentBar({
          items: this.items,
          selectedIndex: $selectedIndex,
          materialPinned: true
        })
      }
      .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .padding({ top: this.inset })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

// 「设置分段行卡」承载形态（与上两件同域并入本文件——分段胶囊第三种承载：行卡右置）：
// 形制 = 行卡（cardBg 卡底 + CARD_RADIUS + CARD_PANEL_WIDTH）左侧标题 + 副标题、右侧定宽
// SEGMENT_BAR_ROW_WIDTH 分段胶囊（首例 = 外观页「图标形状」卡，2026-10-31 决明拍板全站统一
// 后八消费点单源 = 本件，禁再内联复写）。行不可点、分段为唯一控制面；下标 ↔ 持久键双向映射
// 在消费页（本件只渲染，坑57 键纪律不涉及——八消费点均为独立卡直连 @State，无 ForEach 键面）。
// 卡底色自订阅 appColorMode + 卡底透明度档（深浅色切换与档位变化即刷，即时面组件同款契约）。
@Component
export struct SettingSegmentRowCard {
  title: string = '';
  subtitle: string = '';
  items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  // 选中索引（@Link 与页面 @State 双向同步，同 SegmentBar）
  @Link selectedIndex: number;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column() {
        SegmentBar({
          items: this.items,
          selectedIndex: $selectedIndex
        })
      }
      .width(SEGMENT_BAR_ROW_WIDTH)
      .height(SEGMENT_BAR_HEIGHT)
    }
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.title)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    .width(CARD_PANEL_WIDTH)
  }
}
