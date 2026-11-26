// 沉浸光感中枢（自 dshinhm common/ImmersiveLevel.ets 精简随迁——悬浮页签/标题栏光感依赖它）。
// 本文件承载：hdsMaterialParams / resolveEffectiveLevel / resolvedHdsMaterialParams /
// resolvedUiMaterial / leveledUiMaterial / hdsTitleBarOptions（含 menu/stackBuilder/
// keepStackTitle/bottomBuilder 参）；按钮簇 resolvedButton*（行内操作键消费）与内容区回退族
// fallbackButton*（由能力位 CONTENT_FALLBACK_KEY 恒真驱动、无用户入口）；弹层族
// overlayMaterial（气泡/弹窗两族）与半模态面板底 sheetMaterial（见本文件下半）。
// ★ 分项退役（决明拍板）：原「悬浮底栏」（IMMERSIVE_TAB_BAR_KEY）与「其他控件」
//（IMMERSIVE_OTHER_KEY）两分项档位键整体退役——二者恒跟随总档（等价分项恒 0「跟随」）；
// 原 resolveComponentLevel 双参（分项, 总档）收敛为单参 resolveEffectiveLevel（总档 → 生效
// 档位），对外函数族的分项参数一并删除；残留持久化值随键弃用自然失效，无迁移必要。
// 档位对齐官方 hdsMaterial.MaterialLevel（本地 SDK @hms.hds.hdsMaterial.d.ets，
// @kit.UIDesignKit 导出，@since 6.1.0(23)）：
//   0 系统自适应 ADAPTIVE / 1 无（关闭全部材质）/ 2 弱 SMOOTH / 3 均衡 GENTLE / 4 强 EXQUISITE
//（总档 1 在 resolveEffectiveLevel 归一为 -1；档位持久化见 EntryAbility）
// ★ 决明拍板「外观显示页光感段整体退役，不提供光感调整，全部光感维持在强档」：
// 外观页光感段（分段标签 / 滑轨卡 / LevelSlider / 刻度名常量）整体删除，档位改由
// IMMERSIVE_LEVEL_FIXED 固定为 4（强），EntryAbility 负责 persistProp 缺省与存量归正——
// 键**保留为能力位**（与 CONTENT_FALLBACK_KEY 同手法：全站消费方只认键值，日后若要恢复
// 调节，只需把固定值撤掉并复原外观页滑轨卡，无需改任何消费点）。档位函数族按原语义保留
// （含 0~3 分支与「无」档关闭分支）——固定值 4 下它们走强档路径，分支存活即复活路径。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  BlurStrategy,
  BottomBuilderParams,
  BottomBuilderShowType,
  DividerShowType,
  hdsMaterial,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  HdsTitleBarContentStyle,
  ScrollEffectType,
  SystemMaterialParams,
  TitleBarContentOptions,
  TitleBarStyleOptions,
  TitleSize
} from '@kit.UIDesignKit';
import { SEGMENT_BAR_BAND_TOP_INSET, SEGMENT_BAR_HEIGHT, TITLE_BAR_MASK_EXTRA_HEIGHT,
  fallbackGrayBg, fallbackOffCardBg, fallbackBlueBg } from './Theme';

// AppStorage 键（dshinhm 同名；持久化注册在 EntryAbility loadContent 成功回调——坑17 时机）。
// ★ **固定档能力位**：值恒 IMMERSIVE_LEVEL_FIXED（强），无用户调整入口；旧安装存量值由
// EntryAbility 启动时归正，备份导入面同时排除（旧备份低档值不得复活）
export const IMMERSIVE_LEVEL_KEY: string = 'immersiveLevel';
// 沉浸光感固定档 = 4「强」（决明拍板，档位语义见文件头）。
// ★ 唯一写点 = EntryAbility loadContent 回调（persistProp 缺省 + 存量归正）；任何组件/工具
// 禁再写本键（外观页滑轨卡已退役，工具面亦无本键读写位）
export const IMMERSIVE_LEVEL_FIXED: number = 4;
// 内容区「光感新规范」能力位（撤用户开关卡后转为**能力位**）：true = 内容区受影响组件按华为
// 新光感规范走官方标准形态（新规范下内容区非弹窗组件材质不生效——分段胶囊 = 官方默认 A 档
// 零参数、按钮 fallbackButton* 官方实底）；false = 保持原材质光感。
// ★★ 保留理由与复活路径（**勿当死代码清理**）：已无用户入口，EntryAbility persistProp 后做
// 存量归正（已存 false 归 true）⇒ 常态恒 true。华为若放开「内容区材质不生效」限制，改这一
// 处即可全项目切回光感态（消费侧 fallbackButton* 调用与 @StorageProp 订阅零改动即切换）；
// 若要退役本能力位，须连同 fallbackButton* 族与各消费点订阅一并改（勿只删本键）。
// 持久化注册时机 = EntryAbility loadContent 回调（坑17）。★ 全仓按键（**含弹窗 / BindSheet
// 面板内件**）一律走 fallbackButton* 函数族——0 处组件直接调 resolvedButton*，它只作能力位
// false 时的内部透传分支；规范 §2.3「豁免区」指**组件自身材质**保留（标题栏三系 / Menu /
// Toast / 面板壳），不指其内件键换族（真机实锤：内容区键用 resolvedButton* 族会因材质不
// 生效致主钮白字空白）。分段胶囊消费见 components/SegmentBar.ets
export const CONTENT_FALLBACK_KEY: string = 'contentFallback';
// ★ 原总档刻度名常量 IMMERSIVE_LEVEL_SHORT_NAMES（外观页滑轨消费）已随滑轨卡删除——档位恒强
// 无刻度名需求；复活时连同外观页滑轨卡恢复

// 档位 → HdsTabs 悬浮页签材质参数：0 自适应交给系统策略；2 弱 / 3 均衡 / 4 强用 IMMERSIVE
// 类型 + 对应官方级别（总档 1 无在 resolveEffectiveLevel 已归一为 -1，不会进本函数）
export function hdsMaterialParams(level: number): SystemMaterialParams {
  if (level === 2) {
    return { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.SMOOTH };
  }
  if (level === 3) {
    return { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.GENTLE };
  }
  if (level === 4) {
    return { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.EXQUISITE };
  }
  return { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE };
}

// 总档 → 生效档位：总档 1「无」→ -1（显式关闭材质，消费方不设材质/走实底回退）；
// 0/2/3/4 原样（原为双参 resolveComponentLevel(分项, 总档)，分项退役后收敛单参，见文件头）
export function resolveEffectiveLevel(globalLevel: number): number {
  return globalLevel === 1 ? -1 : globalLevel;
}

// HDS 组件材质参数（悬浮页签 HdsTabs）：「无」或总档「无」→ materialType NONE（官方
// 关闭方式，总档无已在 resolveEffectiveLevel 归一为 -1）；其余按生效档位走 hdsMaterialParams
export function resolvedHdsMaterialParams(globalLevel: number): SystemMaterialParams {
  const level: number = resolveEffectiveLevel(globalLevel);
  if (level < 0) {
    return { materialType: hdsMaterial.MaterialType.NONE };
  }
  return hdsMaterialParams(level);
}

// 非 HDS 组件材质（SegmentBar 分段胶囊、输入与搜索框族等现存消费方）：总档「无」→ uiMaterial.Material.empty
//（显式关闭）；其余按生效档位在场景基准档上偏移。偏移方向：uiMaterial ImmersiveStyle 是
//「厚薄」轴（ULTRA_THIN 最透 → ULTRA_THICK 最不透），HDS MaterialLevel 视觉方向相反——
// 统一为「强 = 更透、光感更强」（dshinhm 真机实测沉淀）。interactive = 官方按压弹性形变 +
// 触点光晕；applyShadow = 材质自带阴影（全仓无显式传参消费方，走官方默认 true）；colorInvert = 自动反色
//（SegmentBar 分段胶囊背板消费）。
// ★ 菜单材质第三参口径（决明真机实测定稿）：openMenu 宿主与 bindMenu options 的
// systemMaterial，第三参 interactive 恒传 true——官方最佳实践《沉浸光感》「菜单栏适配沉浸
// 光感」即给菜单材质传 interactive: true。真机结论：菜单材质 + 按压弹性形变成立（lightEffect
// 只作点光源照亮邻近可受光件，属官方行为）。旧口径「弹窗类组件传 false」已作废，勿回改；
// 防回退钉 = assert-feature-domain 66b 组。
// ★ 菜单档位口径（决明拍板「所有菜单的光感调低一档，或者说调厚一档」）：全项目菜单弹出点
// 基准档一律 **REGULAR** 单档，消费点禁自造档位（随总档偏移 = 弱 +1→THICK、均衡/自适应 =
// REGULAR、强 −1→THIN、「无」= 关闭）。未跟改面 = 标题栏自绘键/壳体（TitleBarKeys/
// ChatTitleBarOverlay 胶囊壳）仍 THIN、输入族余面（输入胶囊/面包屑条/排队入口条）仍 REGULAR、
// Toast 恒 THICK、弹层族（overlayMaterial）基准
// ULTRA_THICK（弹窗厚一档拍板后）、半模态面板底（sheetMaterial）基准 ULTRA_THICK、
// SegmentBar 基准 REGULAR（决明调厚笔自 ULTRA_THIN 上调，强档下生效
// THIN——原「恒 ULTRA_THIN」口径已退役）。★ 搜索框族 2026-11-05 调薄笔（决明「统一调薄/透
// 一档」）：全族基准一律 THICK（强档生效 REGULAR）——两二级页 SearchPage/SessionSearchPage +
// SearchTopBand 真框 + openOnly 假框四处同基准同生效档。沿革 = 11-03 调厚两笔曾把全族自
// THIN 收敛到 ULTRA_THICK（强档生效 THICK），决明点名反向调薄一档；仍禁单件私调。
// 防回退钉 = assert-feature-domain 66/66b 组 + 59/96/115 组就近钉。
export function resolvedUiMaterial(base: uiMaterial.ImmersiveStyle, globalLevel: number,
  interactive: boolean, applyShadow: boolean = true, colorInvert: boolean = false): uiMaterial.Material {
  const level: number = resolveEffectiveLevel(globalLevel);
  if (level < 0) {
    return uiMaterial.Material.empty;
  }
  return leveledUiMaterial(base, level, interactive, applyShadow, colorInvert);
}

// ── 弹层族材质（气泡 bindPopup / 弹窗 CustomDialog·showDialog；半模态面板另走下方
//    sheetMaterial）──
// 基准 = ULTRA_THICK（决明指令「应用内所有弹窗比原来厚一档」自 THICK 上调；官方场景表最强
// 模糊背景，气泡/弹窗下方都是正文内容，厚档下可读性最高）。随总档：弱 +1 已在轴顶钳位 /
// 强 −1 更薄 /「无」= Material.empty 显式关闭——关闭后各弹层回落原有形态（对话框官方底板、
// 气泡官方默认毛玻璃），「无」档零观感回归。
// ★ 无参形态由来：两族消费点都是「弹出瞬间求值」的一次性配置（各 options 构造位），面板
// 打开期间档位不会变，故内部 AppStorage 现读——有意与 resolvedButton* 的「组件内
// @StorageProp 传参」形态分流，勿改回传参（消费方含纯函数 sheetPanelOptions，无组件上下文）。
// ★ 官方依据：气泡（Popup）应用级 ENABLE 下不会默认开启沉浸光感，须显式挂；弹窗
//（CustomDialogController / promptAction.showDialog）官方 ENABLE 下默认开启 ULTRA_THICK，本
// 函数显式覆盖（组件级优先级高于应用级）。官方约束：材质生效后弹窗类主动设置的背景色/
// 背景模糊不生效——弹层各处的底色语句是「无」档专用回退，勿删。依据 = 官方《组件适配
// 沉浸光感》「气泡提示/弹出框」两节。
export function overlayMaterial(): uiMaterial.Material {
  const level: number | undefined = AppStorage.get<number>(IMMERSIVE_LEVEL_KEY);
  return resolvedUiMaterial(uiMaterial.ImmersiveStyle.ULTRA_THICK,
    level === undefined ? 0 : level, false);
}

// ── 半模态面板底材质（决明指令「全部半模态底改厚」）──
// 基准 = ULTRA_THICK（官方《组件适配沉浸光感》半模态默认值，本函数显式化）；其余口径与
// overlayMaterial 逐条相同：随总档偏移（弱 +1 轴顶钳位；均衡/自适应 = 基准；强 −1 → THICK）、
//「无」= Material.empty 显式关闭并回落 page_bg 实底。★ 单源 = KimiSheetCommon.
// sheetPanelOptions（全工程唯一 SheetOptions 构造点，全部 bindSheet 挂载点消费）——半模态
// 面板底改档只改本函数一处；菜单 / 输入族 / Toast / 气泡 / 弹窗各自档位不动（禁顺手统一）。
export function sheetMaterial(): uiMaterial.Material {
  const level: number | undefined = AppStorage.get<number>(IMMERSIVE_LEVEL_KEY);
  return resolvedUiMaterial(uiMaterial.ImmersiveStyle.ULTRA_THICK,
    level === undefined ? 0 : level, false);
}

// 非 HDS 组件材质生成：按档位在组件官方场景基准档上偏移（弱 +1 档更厚、强 -1 档更薄、
// 自适应/均衡 = 基准档、无（1）/-1 = Material.empty 显式关闭——两分支缺一不可：
// -1 是 resolveEffectiveLevel 归一后的「无」，1 是档位值直传场景的防御分支（固定档 4 下
// 作为能力位复活路径保留）。
// colorInvert = 自动反色（官方沉浸光感特性，@since 26.0.0，默认 false——SegmentBar 分段
// 胶囊消费）；materialColor = 材质自定义底色（@since 26，编辑图片链「下一步/保存」按钮
// 消费；★ 材质铁律：设了必须带透明度）。两参不传 = 原四参行为
export function leveledUiMaterial(base: uiMaterial.ImmersiveStyle, level: number,
  interactive: boolean, applyShadow: boolean = true, colorInvert: boolean = false,
  materialColor?: ResourceColor): uiMaterial.Material {
  if (level === 1 || level < 0) {
    return uiMaterial.Material.empty;
  }
  const delta: number = level === 2 ? 1 : (level === 4 ? -1 : 0);
  const style: number = Math.max(uiMaterial.ImmersiveStyle.ULTRA_THIN,
    Math.min(uiMaterial.ImmersiveStyle.ULTRA_THICK, base + delta));
  if (interactive) {
    return new uiMaterial.ImmersiveMaterial({
      style: style as uiMaterial.ImmersiveStyle,
      colorInvert: colorInvert,
      interactive: true,
      lightEffect: { color: undefined }, // 传对象即启用触点光晕，color 缺省用系统默认白色
      applyShadow: applyShadow,
      materialColor: materialColor
    });
  }
  return new uiMaterial.ImmersiveMaterial({
    style: style as uiMaterial.ImmersiveStyle,
    colorInvert: colorInvert,
    applyShadow: applyShadow,
    materialColor: materialColor
  });
}

// ── 胶囊按钮光感簇（自 dshinhm 随迁——编辑图片链 CropStageView「下一步」/ AdjustStageView
// 「上一步·保存」按钮消费；完整定稿注释见 dshinhm 同名函数）──
// 材质 = REGULAR 通用基准 + 按压形变/触点光效 + 官方蓝灰配色（主 #E60A59F7 强调蓝 / 次深
// #E63A3A3C 浅 #E6E6E8EA 普通灰，AARRGGBB alpha 前置 + 90% 透明度——材质铁律）。★ 全应用
// 固定强调蓝单源 = 0A59F7，图表侧经 Theme.usageAccentColor 同值消费（两族不分叉）；
// colorOverride 可选覆盖配色（暂无消费方，保持原函数形态同构）
export function resolvedButtonMaterial(immersiveLevel: number,
  primary: boolean, colorOverride?: ResourceColor): uiMaterial.Material {
  const level: number = resolveEffectiveLevel(immersiveLevel);
  if (level < 0) {
    return uiMaterial.Material.empty;
  }
  const isDark: boolean = AppStorage.get<number>('appColorMode') ===
    ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  const color: ResourceColor = colorOverride !== undefined ? colorOverride :
    (primary ? '#E60A59F7' : (isDark ? '#E63A3A3C' : '#E6E6E8EA'));
  return leveledUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, level, true, true, true, color);
}

// Button 原生按压反馈开关：材质生效时 false（按压交给材质形变/光效，原生按压色混合会致
// 整块变色）；无光感档 true 保留原生（否则无按压反馈）
export function resolvedButtonStateEffect(immersiveLevel: number): boolean {
  return resolveEffectiveLevel(immersiveLevel) < 0;
}

// 无光感档按钮回退底色（与 resolvedButtonMaterial 配对）：有档 = Transparent（材质铁律）；
// 无档 = 主 comp_background_emphasized 官方蓝实底 / 次 comp_background_tertiary 官方灰
export function resolvedButtonBg(immersiveLevel: number,
  primary: boolean): ResourceColor {
  if (resolveEffectiveLevel(immersiveLevel) < 0) {
    return primary ? $r('sys.color.comp_background_emphasize') :
      $r('sys.color.comp_background_tertiary');
  }
  return Color.Transparent;
}

// 按钮文字色（与 resolvedButtonBg 配对）：主 = font_on_primary 恒白；次 = font_primary 反色
//（档位不参与——官方语义色深浅自动反色）
export function resolvedButtonFont(primary: boolean): ResourceColor {
  if (primary) {
    return $r('sys.color.font_on_primary');
  }
  return $r('sys.color.font_primary');
}

// ── 内容区回退函数族（四件套与 resolvedButton* 同构 + fallback 参；能力位语义见文件头
//    CONTENT_FALLBACK_KEY 条）──
// fallback true = 官方标准形态兜底（按钮官方实色、分段胶囊官方默认 A 档），false = 原材质
// 光感；实底取值与 resolvedButton* 的「无光感档」分支同值（comp_background_tertiary/
// emphasize + font_primary/on_primary + stateEffect(true)）——官方语义色自动深浅反色，零
// 手写色值。触发方式：调用方 @StorageProp(CONTENT_FALLBACK_KEY)（订阅式切换即刷，
// AppStorage.get 现读非响应式——坑16 正解；键值存量归正恒 true，但勿因「恒真」删订阅
//——能力位的可切换性靠这条链路）。
// ★ bg 件两个取值函数（按「面」概念命名）：fallbackButtonBg（**白卡面**——卡体）与
// fallbackButtonBgOffCard（**非白卡面**——页底 / 半模态面板面；决明「背景上的灰底键改白，
// 卡片内不动」后扩到非按钮件）。判据 = 件所坐的面（不是件在哪一页），细则与深色口径见
// 后者注释；非按钮件（变量插入胶囊 / 面板搜索框）按同判据**直取** `Theme.fallbackOffCardBg`
//（绕开四件套——那两族「显式实色 + 无材质」单层组合是各自拍板形态）。
// ★ 等价关系：「分项/总档 = 无」档下 resolvedButtonBg/StateEffect 内建回退官方实色，与本
// 开关默认态（fallback=true）效果一致——两入口殊途同归无害；本开关语义 = 内容区专用
//「实底/光感」模式选择，标题栏与弹窗类的档位恒跟随总档。
export function fallbackButtonMaterial(fallback: boolean, immersiveLevel: number,
  primary: boolean): uiMaterial.Material {
  // 实底态返回 Material.empty（即「不设材质」——代码路径上由调用方 systemMaterial 属性
  // 仍挂空材质，官方语义 = 无材质，配合底色生效；与「无光感档」分支口径一致）
  return fallback ? uiMaterial.Material.empty :
    resolvedButtonMaterial(immersiveLevel, primary);
}

export function fallbackButtonStateEffect(fallback: boolean,
  immersiveLevel: number): boolean {
  // 实底态恒 true（原生按压反馈由按钮自带）；光感态回归原判定
  return fallback ? true : resolvedButtonStateEffect(immersiveLevel);
}

export function fallbackButtonBg(fallback: boolean,
  immersiveLevel: number, primary: boolean, level?: number): ResourceColor {
  // 实底态强制官方实色（绕过「有档 = Transparent」）；光感态回归原判定。
  // ★ 次钮灰底随卡底透明度档位叠 alpha（可读性担忧由 alpha 双表下限浅 50% / 深 40% 兜底；
  // 基色经 Theme.fallbackGrayBg——官方按钮普通灰阶实色，浅 #E6E8EA / 深 #3A3A3C 已真机
  // 验证）；主钮强调蓝实底**不随档**（收口动作强调锚点 + 恒白字对比不受透明度稀释）。
  // mode 体内现读 AppStorage；level 缺省 = 重建层读键，拖动现场与常驻面消费点显式传
  // this.cardAlphaLevel 建立即时刷新依赖
  if (!fallback) {
    return resolvedButtonBg(immersiveLevel, primary);
  }
  if (primary) {
    return $r('sys.color.comp_background_emphasize');
  }
  return fallbackGrayBg(AppStorage.get<number>('appColorMode') ??
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT, level);
}

// ★ 卡外实心件底色（决明拍板「背景上的灰底键改白，卡片内不动」，后扩到变量 chip 与半模态
// 搜索框；本函数 = 按钮侧实现单源——**次钮**消费点只许调本函数，禁在调用侧自写色值）。
// 四件套之 bg 件的**第二取值函数**：与 fallbackButtonBg 只差「实底态 + 次钮」这一格，主钮
//（强调蓝）/ 光感态（透传 resolvedButtonBg）/ 材质·按压·字色三件套全部一字不动，故消费点
// 只替换 backgroundColor 一处。
// 判据 = 键所坐的**面**（不是键在哪一页）：**非白卡面**（页底 page_bg / 半模态面板面 / 组卡
// 之间的卡外区 / **淡染卡面**——2026-11-09 服务商编辑页余额入口卡补判：绿染面非白卡面，
// 「卡片内不动」指基色分叉判据不动，不是按「是否落在某个 Column 里」判）取卡外白基（浅 #FFFFFF——比浅面亮一档才显形，与「白卡坐灰底」同构；经
// `Theme.fallbackOffCardBg`）、**白卡面**（卡体 cardBg）仍取灰基（对白面才有对比；经
// `Theme.fallbackGrayBg`；两基色均随卡底透明度档叠 alpha，「卡片内不动」指基色分叉判据
// 不变）。深色两值同灰（#3A3A3C）= **深色零感知**。★ 适用边界：本条只管**浅色面**；深色底
//（如全屏编辑页 #121212 舞台）上的灰件不在判据内——那种面用通用灰本就清楚，勿按本条改白
//（先例 = AdjustStageView 上一步键）。
export function fallbackButtonBgOffCard(fallback: boolean, immersiveLevel: number,
  primary: boolean, level?: number): ResourceColor {
  if (!fallback) {
    // 光感态回归原判定（与 fallbackButtonBg 同句——两函数只在实底态的次钮分叉）
    return resolvedButtonBg(immersiveLevel, primary);
  }
  if (primary) {
    return $r('sys.color.comp_background_emphasize');
  }
  // 实底态次钮随卡底透明度档叠 alpha（基色 Theme.fallbackOffCardBg，口径同头注释「面」判据）
  return fallbackOffCardBg(AppStorage.get<number>('appColorMode') ??
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT, level);
}

// ── 淡彩次级键（决明拍板「卡内键四档阶梯」；判据与消费面清单 = 规范-行内按钮与光感 §1 表
//    「淡彩次级键」行）──
// 档位语义：主钮（强调蓝实底恒白字）与次钮（普通灰实底）之间的**推进型动作档**——
// 「添加 XX / 测试连接 / 选择模板 / 重新授权 / 上传备份」一类推进流程但非本卡收口的动作。
// 分档判据（写键时先过三问）：本卡另有收口主钮吗（有 → 本键不入主档）？动作是推进型还是
// 中性可逆（可逆 → 走次钮灰档）？语义强度够不上无底轻动作吗（够不上才坐实底）。
// 实底态 = 淡蓝底 + 深蓝字（app 资源深浅分治：浅 #DCE8FF/#1D4ED8、深 #1B2A4A/#A8C7FF——
// 与状态徽标强调档/用户气泡同值共用，见规范-视觉色板与徽标 §10；对比度已按该档实测，靠
// 形状与场景区分、不另开近似 token）。光感态 = 透传次钮分支（resolvedButton* 灰）——
// CONTENT_FALLBACK_KEY 恒 true 下该分支现役不可达；若复活光感态需补淡蓝材质配色
//（colorOverride）再议。stateEffect 不设独立函数：复用 fallbackButtonStateEffect。
export function fallbackButtonBgTinted(fallback: boolean,
  immersiveLevel: number, level?: number): ResourceColor {
  // 实底态淡蓝底随卡底透明度档叠 alpha（基色 Theme.fallbackBlueBg，字色
  // comp_fallback_blue_fg 资源保留配对不动）
  return fallback ? fallbackBlueBg(AppStorage.get<number>('appColorMode') ??
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT, level) :
    resolvedButtonBg(immersiveLevel, false);
}

export function fallbackButtonFontTinted(fallback: boolean): ResourceColor {
  return fallback ? $r('app.color.comp_fallback_blue_fg') :
    resolvedButtonFont(false);
}

export function fallbackButtonMaterialTinted(fallback: boolean,
  immersiveLevel: number): uiMaterial.Material {
  return fallback ? uiMaterial.Material.empty :
    resolvedButtonMaterial(immersiveLevel, false);
}

// ── 三态分发（复用渲染器专用：DataSyncPage/S3SyncCard ActionBtn、SearchEngineDetailPage
// InlineBtn 的参数化键——primary 主档蓝 / tinted 淡彩档 / 两者皆否 = 次档灰；直写键走
// fallbackButtonBg(Tinted) 独立函数族，勿混用两入口，值同源无分叉）──
export function tierButtonFont(fallback: boolean, primary: boolean,
  tinted: boolean): ResourceColor {
  if (primary) {
    return fallbackButtonFont(fallback, true);
  }
  if (tinted) {
    return fallbackButtonFontTinted(fallback);
  }
  return fallbackButtonFont(fallback, false);
}

export function tierButtonBg(fallback: boolean, immersiveLevel: number,
  primary: boolean, tinted: boolean): ResourceColor {
  if (primary) {
    return fallbackButtonBg(fallback, immersiveLevel, true);
  }
  if (tinted) {
    return fallbackButtonBgTinted(fallback, immersiveLevel);
  }
  return fallbackButtonBg(fallback, immersiveLevel, false);
}

export function tierButtonMaterial(fallback: boolean, immersiveLevel: number,
  primary: boolean, tinted: boolean): uiMaterial.Material {
  if (primary) {
    return fallbackButtonMaterial(fallback, immersiveLevel, true);
  }
  if (tinted) {
    return fallbackButtonMaterialTinted(fallback, immersiveLevel);
  }
  return fallbackButtonMaterial(fallback, immersiveLevel, false);
}

export function fallbackButtonFont(fallback: boolean, primary: boolean): ResourceColor {
  // 字色恒官方语义色反色（实底态与光感态一致，档位不参与）——fallback 仅保四件套
  // 形制同构
  return resolvedButtonFont(primary);
}

// HDS 标题栏配置（一级页 HdsNavigation / 二级页 HdsNavDestination 共用；自 dshinhm 随迁，
// 样式定稿全量故事〔六轮真机迭代〕见 dshinhm 同名头注释，此处只留结论）：
// · 主标题 + 官方字号档（一级页缺省 TITLE_ML / 二级页传 TITLE_S）+ 分割线关闭 +
//   GRADIENT_BLUR 常显模糊（enableScrollEffect: false——true 在 HdsNavigation 嵌 HdsTabs
//   下绑定链路不可靠，真机定稿勿改回；「常显」相对滚动渐进而言，模糊本身仍受下条
//   blurStrategy 的系统策略约束）+ 背板显式透明（防「GRADIENT_BLUR + 配置过材质 +
//   false」默认规则渲染灰白实底）+ 蒙层下延 maskExtraHeight = TITLE_BAR_MASK_EXTRA_HEIGHT
//  （与页面 topPad 同名常量必须同值，Theme.ets 注释）+ 标题色显式 font_primary。
// · ★ blurStrategy 显式 ADAPTIVE（2026-11-05 契约固化笔，**零行为变化**）：SDK
//   hdsBaseComponent.d.ets 该字段 @default BlurStrategy.ADAPTIVE（@since 6.0.0(20)，枚举注释
//   "Adaptive blur effect based on system policies"）——本仓两处标题栏单源此前均未写，隐式
//   吃同一默认。快速滚动时系统按负载临时关掉标题栏模糊、停止后恢复，是官方默认策略；官方
//   设置类应用快速滑动同样掉模糊，故**不作缺陷立项**，静止/慢滚/停止后模糊与穿透均恒在。
//   官方 FAQ faqs-arkui-1095 备有兜底 = 改 BlurStrategy.ENABLE 强制开启，代价是滚动帧率与
//   功耗上升，未经拍板禁改。本字段只作用标题栏 style，不动滚动容器、不绑 Scroller、不改
//   dynamicHideTitleBar ⇒ 助手页 List.onMove 长按拖拽排序与对话页 SessionSwipeItem 侧滑手势
//   零影响。分档判据 = docs/规范-搜索交互.md §6。
// · 材质由总档驱动（「无」档归一 -1 = 不设 systemMaterialEffect——不设而非 NONE：NONE 也
//   属「已配置」，会触发默认背景色规则）。
// · avoidLayoutSafeArea: true = 标题栏主动避让状态栏（全屏窗口下唯一官方开关，普通
//   Navigation 无此能力——坑2）。
// · menu = 右上角菜单按钮（HdsNavigationMenuContentOptions：value 数组 + 每项
//   content.icon/action，@since 5.1.0(18)；icon 直接传 $r('sys.symbol.xxx') 系统符号）——
//   设置页签标题栏搜索键（magnifyingglass）消费。
//   stackBuilder = 标题栏自定义覆盖层（TitleBarContentOptions.stackBuilder，@since 6.0.0(20)；
//   官方指南《设置自定义区域》）——消费方两类：①经 PageShell.titleBarStack 转交的十三页 =
//   ChatPage（模型胶囊 + 右上角胶囊）、MemoryLibraryPage / SkillLibraryPage（菜单域件
//   SkillTitleMenu）/ ProviderPage /
//   PromptLibraryPage（右上角合并胶囊〔＋|⋯〕）、AttachmentViewerPage（页码 n/N）、
//   KnowledgeLibraryPage（〔＋新建|⋯更多〕双热区胶囊）/ KnowledgeBookPage /
//   MountManagePage（〔＋〕单圆键）/
//   WorkspaceManagePage（2026-11-18 文件工作区双键胶囊〔新建文件夹|⋯更多〕，原官方菜单数组单键退役）、
//   AssistantPageHost（助手二级页〔＋〕新建键）/ SettingsPageHost（设置二级页
//   magnifyingglass 搜索键——常显搜索入口重映射，双形态笔）/ DrawerSidePanel（侧栏会话
//   二级页——2026-11-18「助手行替换标题」笔：助手行本体〔徽章 + 名 + 三热区胶囊〕整栏接管
//   标题位，多选态换「已选 N 项」）——单圆键/页码形态主标题经 keepStackTitle 保留，
//   DrawerSidePanel 为整栏接管（keepStackTitle 缺省 false = 官方主标题置空）；②直调本函数
//   传第 5 参的三处 = HomeNavigation 一级页
//   两页签（「助手」= 合并胶囊、「对话」= 搜索键 + 胶囊，两页签互斥出键同用一个调用点）、
//   SearchPage / SessionSearchPage（搜索框嵌入标题栏）。★ 2026-11-18 侧栏 B 轨初版曾把
//   DrawerSidePanel 助手行放 stackBuilder（直调第四处），同日 2235-b 两行带校正后助手行与
//   分段行一起收进 bottomBuilder（工作区同款），本清单回三处；同日「助手行替换标题」笔再
//   接入——改经 PageShell.titleBarStack 壳转交（不再直调），故壳转交名单十一页 → 十二页。
//   自绘键件统一来自
//   components/TitleBarKeys.ets（几何 + 双态单源）。传入即主标题置空（覆盖层压在标题上方，
//   官方示例同款），keepStackTitle = true 时保留主标题（覆盖层只占标题栏右侧，官方标题
//   照常绘制）。★ 覆盖层内容必须是组件或组件内 @Builder（全局 @Builder 被官方 napi 直接
//   调用时无视图上下文，运行期闪退——坑30）；二级页覆盖层还须挂 hitTestBehavior
//  (Transparent)（整栏铺在返回键上方，默认档挡返回键——MemoryPage 自检轮实测，规范 §4）。
//   清单与全仓调用点自动对账 = feature-domain 60 组钉。
// · 「无」档返回键圆底分支（resolvedLevel < 0 时 backIconStyle/menuStyle 纯色圆底，官方
//   无光感样式 = comp_background_tertiary + icon_primary）——总档调「无」后二级页返回键/
//   菜单键保持可见可点（dshinhm 真机定稿）。
// · bottomBuilder = 官方标题栏下方自定义区（TitleBarContentOptions.bottomBuilder，
//   @since 6.0.0(20)；官方指南明文用途 =「标题下方区域加搜索框、页签」）。本项目用法 =
//   承载页顶吸顶分段胶囊——内容区件在 API 26 不出材质，迁入本区即恢复沉浸光感（真机实测
//   两自定义区都在生效区内）；另承载三库页搜索框 SearchTopBand（REGULAR 恒光感，消费方经
//   PageShell.titleBarBottom 同路转交——形锚 = assert-ui-shape 68 组「搜索带接线」钉）。
//   规格构造单源 = 下方 segmentBandParams（带高算式，勿在消费侧另算）；★ 带顶 = 标题栏下沿
//  （**不是 topPad**——topPad 含蒙层下延 16vp），带内下移量单源 = Theme
//   SEGMENT_BAR_BAND_TOP_INSET(_STATS)。消费方 = 经 PageShell.titleBarBottom 转交的各二级页
//  （持续扩面，计数以 grep 为准）+ DrawerSidePanel 直调（2026-11-18 2235-b：助手行 + 分段行
//   两行带，带内容高 WORKSPACE_BAND_CONTENT_HEIGHT 88，与工作区页同源）；HomeNavigation
//  「对话」页签原直调处已随标题栏内嵌分段笔退役（该页分段迁入标题栏覆盖层，带整条取消）
export function hdsTitleBarOptions(mainTitle: string, level: number,
  mainTitleSize: TitleSize = TitleSize.TITLE_ML,
  menu?: HdsNavigationMenuContentOptions, stackBuilder?: CustomBuilder,
  keepStackTitle: boolean = false, bottomBuilder?: BottomBuilderParams): HdsNavigationTitleBarOptions {
  const resolvedLevel: number = resolveEffectiveLevel(level);
  const contentStyle: HdsTitleBarContentStyle = {
    titleStyle: { mainTitleColor: $r('sys.color.font_primary') }
  };
  if (resolvedLevel < 0) {
    contentStyle.backIconStyle = {
      backgroundColor: $r('sys.color.comp_background_tertiary'),
      iconColor: $r('sys.color.icon_primary')
    };
    // 右上角菜单按钮「无」档同返回键：纯色圆底 + 深色图标（官方无光感样式，同规则）
    contentStyle.menuStyle = {
      backgroundColor: $r('sys.color.comp_background_tertiary'),
      iconColor: $r('sys.color.icon_primary')
    };
  }
  const style: TitleBarStyleOptions = {
    scrollEffectOpts: {
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      enableScrollEffect: false // 常显模糊（dshinhm 第六轮定稿，勿改 true）
    },
    // 官方默认档显式固化（零行为变化；语义、禁改口径与手势无耦合实证见函数头 blurStrategy 条）
    blurStrategy: BlurStrategy.ADAPTIVE,
    originalStyle: {
      backgroundStyle: {
        backgroundColor: Color.Transparent,
        maskExtraHeight: TITLE_BAR_MASK_EXTRA_HEIGHT
      },
      contentStyle: contentStyle
    }
  };
  if (resolvedLevel >= 0) {
    style.systemMaterialEffect = hdsMaterialParams(resolvedLevel);
  }
  const titleBarContent: TitleBarContentOptions = {
    title: {
      // 覆盖层默认置空主标题（搜索框占位场景）；keepStackTitle=true 时保留
      mainTitle: stackBuilder && !keepStackTitle ? '' : mainTitle,
      mainTitleSize: mainTitleSize
    },
    divider: { showType: DividerShowType.OFF },
    // 右上角菜单按钮（设置页签搜索键等；不传 = 无菜单）
    menu: menu
  };
  if (stackBuilder) {
    // 标题栏自定义覆盖层（消费方与硬约束见头注释 stackBuilder 段；feature-domain 60 组钉对账）
    titleBarContent.stackBuilder = stackBuilder;
  }
  if (bottomBuilder) {
    // 标题栏下方自定义区（用途与消费方见头注释 bottomBuilder 段）。带顶由 HDS 保证为标题栏
    // 下沿，带宽/下移量由消费方按 Theme 常量算好传入（算式单源 = 下方 segmentBandParams）
    titleBarContent.bottomBuilder = bottomBuilder;
  }
  return {
    avoidLayoutSafeArea: true,
    content: titleBarContent,
    style: style
  };
}

// 标题栏下方带（bottomBuilder）参数构造（带高算式单源）：
// builder 必须是**组件内 @Builder**（坑30：全局 @Builder 被官方 napi 直接调用无视图上下文，
// 运行期闪退）；带高 = 带内下移量 + 内容高（缺省内容高 = 胶囊背板 40vp〔Theme
// SEGMENT_BAR_HEIGHT〕——下移 8 ⇒ 48、下移 16 ⇒ 56，胶囊底与带底齐平）；常显档
// DIRECTLY_SHOW（另一档 OVERDRAG_SHOW = 下拉才显，本用途不用）。第三参 contentHeight =
// 两行档（面包屑 + 分段胶囊）用——工作区页传 WORKSPACE_BAND_CONTENT_HEIGHT（88 = 40+8+40）
// ⇒ 带高 = 8 + 88 = 96；缺省 40，既有消费方（下移 8 ⇒ 48 / STATS 16 ⇒ 56）零变化。
// 消费方 = PageShell.bandParams 与 SessionSearchPage 直调（两处共用本算式勿各写一份；
// HomeNavigation「对话」页签原直调处已随标题栏内嵌分段笔退役，带整条取消）
export function segmentBandParams(builder: CustomBuilder,
  inset: number = SEGMENT_BAR_BAND_TOP_INSET,
  contentHeight: number = SEGMENT_BAR_HEIGHT): BottomBuilderParams {
  return {
    builder: builder,
    height: inset + contentHeight,
    showType: BottomBuilderShowType.DIRECTLY_SHOW
  };
}
