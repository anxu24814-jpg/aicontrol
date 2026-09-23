// 沉浸光感中枢（自 dshinhm common/ImmersiveLevel.ets 精简随迁——悬浮页签/标题栏光感依赖它）。
// 精简口径：页签/回退胶囊/标题栏/外观显示页消费的函数与键——hdsMaterialParams /
// resolveEffectiveLevel / resolvedHdsMaterialParams / resolvedUiMaterial / leveledUiMaterial /
// hdsTitleBarOptions（含 menu/stackBuilder/keepStackTitle 三参，2026-08-29 M2c 补齐）+ 总档
// 刻度名常量（外观页 LevelSlider 消费）；按钮簇 resolvedButton*（2026-08-29 M3 随迁，
// 行内操作键消费）与内容区回退族 fallbackButton*（2026-09-03，光感新规范开关消费）亦在本文件；
// 弹层族 overlayMaterial（2026-09-22，气泡/半模态/弹窗三族消费）同文件。
// ★ 分项退役（2026-09-12 决明拍板）：原「悬浮底栏」（IMMERSIVE_TAB_BAR_KEY）与「其他控件」
//（IMMERSIVE_OTHER_KEY）两个分项档位键整体退役——用户不再单独控制这两处，二者档位恒跟随
// 沉浸光感总档（等价于分项恒为 0「跟随」），光感功能本体不受影响；原 resolveComponentLevel
// 双参（分项, 总档）随之收敛为单参 resolveEffectiveLevel（总档 → 生效档位），对外函数族
// 的分项参数一并删除。分项刻度名常量 COMPONENT_LEVEL_SHORT_NAMES 与两键的持久化注册、
// 外观页滑轨卡、搜索注册、助手工具白名单同步退役（残留持久化值随键弃用自然失效，无迁移
// 必要——默认「跟随」即总档行为）。
// 档位对齐官方 hdsMaterial.MaterialLevel 语义（本地 SDK
// sdk/default/hms/ets/api/@hms.hds.hdsMaterial.d.ets，@kit.UIDesignKit 导出，@since 6.1.0(23)）：
//   0 系统自适应 ADAPTIVE / 1 无（关闭全部材质）/ 2 弱 SMOOTH / 3 均衡 GENTLE / 4 强 EXQUISITE
// （「无」档 2026-08-20 dshinhm 应决明要求加入总档位——一键关闭全部材质；总档 1 在
//   resolveEffectiveLevel 归一为 -1。档位持久化见 EntryAbility，调节入口 = 「外观显示」页）
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
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
import { TITLE_BAR_MASK_EXTRA_HEIGHT } from './Theme';

// AppStorage 键（dshinhm 同名；持久化注册在 EntryAbility loadContent 成功回调——坑17 时机）
export const IMMERSIVE_LEVEL_KEY: string = 'immersiveLevel';
// 内容区光感新规范开关（2026-09-03 决明拍板，2026-09-07 更名「光感新规范」）：true =
// 内容区受影响组件按华为新光感规范走官方标准形态（新规范下内容区非弹窗组件材质不生效——
// 分段胶囊 = 官方默认 A 档零参数、按钮 fallbackButton* 官方实底）；false = 保持原材质光感
//（对照验收/回滚）。持久化注册在 EntryAbility loadContent 回调（坑17 时机），默认 true
// （验收默认即新效果）；消费侧双态 = 新增 fallbackButton* 函数族（本文件，勿与既有
// resolvedButton* 混用——resolvedButton* 供标题栏/弹窗等豁免区，fallbackButton* 只供
// 内容区受影响组件；分段胶囊消费见 components/SegmentBar.ets）
export const CONTENT_FALLBACK_KEY: string = 'contentFallback';
// 滑动条下方刻度名（2026-08-29 M2c 自 dshinhm 随迁，外观显示页 LevelSlider 消费）：
// 首项缩写为「适应」2 字宽（dshinhm 定稿沉淀，勿改回「自适应」3 字）
export const IMMERSIVE_LEVEL_SHORT_NAMES: string[] = ['适应', '无', '弱', '均衡', '强'];

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
// 0/2/3/4 原样（2026-09-12 分项退役前本函数为双参 resolveComponentLevel(分项, 总档)，
// 分项 0 = 跟随总档——分项退役后分项恒为 0，收敛为单参）
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

// 非 HDS 组件材质（回退胶囊 BottomTabBar 等）：总档「无」→ uiMaterial.Material.empty
//（显式关闭）；其余按生效档位在场景基准档上偏移。
// 偏移方向：uiMaterial ImmersiveStyle 是「厚薄」轴（ULTRA_THIN 最透 → ULTRA_THICK 最不透），
// HDS MaterialLevel 视觉方向相反——统一为「强 = 更透、光感更强」，与 HDS 侧对齐
//（dshinhm 真机实测沉淀，详见 dshinhm common/ImmersiveLevel.ets 头注释）。
// interactive = 官方按压弹性形变 + 触点光晕；applyShadow = 材质自带阴影（官方默认 true，
// 悬浮胶囊保持默认，与 dshinhm 回退胶囊一致）；colorInvert = 自动反色（M3 补——SegmentBar
// 分段胶囊背板消费，dshinhm 原函数同参；不传 = 原行为，既有调用点零变化）
// ★ 菜单材质第三参口径（2026-09-18 菜单光感笔，决明真机实测定稿）：openMenu 宿主与 bindMenu
// options 的 systemMaterial，第三参 interactive 恒传 true——官方最佳实践《沉浸光感》
// 「菜单栏适配沉浸光感」节即给菜单材质传 interactive: true + lightEffect。本项目真机结论：
// 菜单材质在 + 按压弹性形变成立（lightEffect 不在菜单本体画流光，只作点光源照亮邻近可受光件
// ——如菜单上方标题栏键，属官方行为）。旧口径「弹窗类组件无此参数，传 false」（随 dshinhm
// 迁入的注释）已作废，勿回改；防回退钉 = assert-feature-domain 66b 组。
// 依据 = docs/调研-菜单按压形变与触摸光效-20260918.md。
export function resolvedUiMaterial(base: uiMaterial.ImmersiveStyle, globalLevel: number,
  interactive: boolean, applyShadow: boolean = true, colorInvert: boolean = false): uiMaterial.Material {
  const level: number = resolveEffectiveLevel(globalLevel);
  if (level < 0) {
    return uiMaterial.Material.empty;
  }
  return leveledUiMaterial(base, level, interactive, applyShadow, colorInvert);
}

// ── 弹层族材质（气泡 bindPopup / 半模态 bindSheet / 弹窗 CustomDialog·showDialog；
// 2026-09-22 决明指令「气泡全 thick，半模态/弹窗也改 thick」）──
// 基准 = THICK（官方场景表：较强模糊背景，与菜单同级；气泡/面板/对话框下方都是正文内容，
// 小字与列表需要较强模糊才有可读性）。随沉浸光感总档：弱 +1 更厚 / 强 −1 更薄 /「无」=
// Material.empty 显式关闭——关闭后各弹层回落各自原有形态（半模态恢复 page_bg 实底、
// 对话框恢复官方底板、气泡恢复官方默认毛玻璃），即「无」档零观感回归。
// ★ 无参形态的由来：三族消费点都是「弹出瞬间求值」的一次性配置（各 options 构造位），
// 面板打开期间档位不会变，无需订阅刷新，故内部 AppStorage 现读；这是有意与
// resolvedButton* 的「组件内 @StorageProp 传参」形态分流，勿改回传参（消费方含纯函数
// sheetPanelOptions，无组件上下文）。「无」档关闭语义与 fallbackButton* 的 Material.empty
// 口径一致。
// ★ 覆盖面与官方依据：气泡（Popup）官方「应用级 ENABLE 下不会默认开启沉浸光感」，须显式
// 挂；半模态（bindSheet）与弹窗（CustomDialogController / promptAction.showDialog）官方
// ENABLE 下默认开启 ULTRA_THICK，本函数把基准显式覆盖为 THICK（组件级优先级高于应用级）。
// 官方约束：材质生效后弹窗类主动设置的背景色/背景模糊不生效（弹层各处的底色语句随之成为
// 「无」档专用回退，勿删）。依据 = 官方《组件适配沉浸光感》「气泡提示/弹出框」两节 +
// docs/变更记录.md 本笔条目。
export function overlayMaterial(): uiMaterial.Material {
  const level: number | undefined = AppStorage.get<number>(IMMERSIVE_LEVEL_KEY);
  return resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
    level === undefined ? 0 : level, false);
}

// 非 HDS 组件材质生成：按档位在组件官方场景基准档上偏移（弱 +1 档更厚、强 -1 档更薄、
// 自适应/均衡 = 基准档、无（1）/-1 = Material.empty 显式关闭——两分支缺一不可：
// -1 是 resolveEffectiveLevel 归一后的「无」，1 是总档滑轨直传场景）。
// colorInvert/materialColor 两可选参（2026-08-29 M3 自 dshinhm 原函数补齐——编辑图片链的
// 分段胶囊 SegmentBar（colorInvert）与「下一步/保存」按钮（materialColor）消费；不传 =
// 原四参行为，既有调用点零变化）：
// colorInvert = 自动反色（官方沉浸光感特性，@since 26.0.0，默认 false）；materialColor =
// 材质自定义底色（@since 26；★ 材质铁律：设了必须带透明度）
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

// ── 胶囊按钮光感簇（2026-08-29 M3 自 dshinhm 随迁——编辑图片链 CropStageView「下一步」/
// AdjustStageView「上一步·保存」按钮消费；完整定稿注释见 dshinhm 同名函数）──
// 材质 = REGULAR 通用基准 + 按压形变/触点光效 + 官方蓝灰配色（主 #E60A59F7 强调蓝 /
// 次深 #E63A3A3C 浅 #E6E6E8EA 普通灰，AARRGGBB alpha 前置 + 90% 透明度——材质铁律）；
// ★ 2026-09-12 UI 同形异构归一笔 6：全应用固定强调蓝单源 = 0A59F7，图表侧经
// Theme.usageAccentColor 同值消费（原 0A58F6 已归一，两族不再分叉）；
// colorOverride 可选覆盖配色（本项目暂无消费方，参数随原函数形态保持同构）
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

// ── 内容区回退函数族（2026-09-03 决明拍板，四件套与 resolvedButton* 同构 + fallback 参）──
// 语义：新规范下内容区非弹窗组件材质不生效（Material inactive: out of scope），受影响组件
// 由外观页开关（CONTENT_FALLBACK_KEY，默认 true，2026-09-07 更名「光感新规范」）驱动双态——
// true = 官方标准形态兜底（按钮官方实色、分段胶囊官方默认 A 档），false = 原材质光感。
// 实底取值与 resolvedButton* 的「无光感档」分支同值（comp_background_tertiary/
// emphasize + font_primary/on_primary + stateEffect(true)）——官方语义色自动深浅反色，
// 零手写色值。注意：本族只供内容区受影响组件消费；标题栏/弹窗等豁免区继续用 resolvedButton*
//（勿混用，文件头 CONTENT_FALLBACK_KEY 注释有同一说明）。
// 触发方式：调用方 @StorageProp(CONTENT_FALLBACK_KEY)（订阅式，切换即刷；AppStorage.get
// 现读非响应式——坑16 正解）。
// ★ 等价关系（2026-09-03 方案 A 补记）：「分项/总档 = 无」档下 resolvedButtonBg/StateEffect
// 内建回退官方实色（Theme.ets 无光感档语句链），与本开关默认态（fallback=true）效果一致
// ——两入口殊途同归，无害；本开关语义 = 内容区专用「实底/光感」模式选择，标题栏与弹窗类
// 的档位恒跟随沉浸光感总档（2026-09-12 分项退役口径，外观页文字已明示）。
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
  immersiveLevel: number, primary: boolean): ResourceColor {
  // 实底态强制官方实色（绕过「有档 = Transparent」）；光感态回归原判定。
  // ★ 2026-09-03 决明反馈「灰底透明度很低，可读性不佳」→ 次钮不透明化：官方语义色
  // comp_background_tertiary 真机观察带透明度（底层内容透出、文字可读性差）——改官方
  // 按钮普通灰阶实色（浅 #E6E8EA / 深 #3A3A3C，已真机验证的官方色板值，不透明；app
  // 资源深浅分治 = page_bg 先例）；主钮（comp_background_emphasize 强调蓝）保留官方
  // 语义色——用户未反馈蓝底透明问题
  return fallback ? (primary ? $r('sys.color.comp_background_emphasize') :
    $r('app.color.comp_fallback_gray')) :
    resolvedButtonBg(immersiveLevel, primary);
}

export function fallbackButtonFont(fallback: boolean, primary: boolean): ResourceColor {
  // 字色恒官方语义色反色（实底态与光感态一致，档位不参与）——fallback 仅保四件套
  // 形制同构
  return resolvedButtonFont(primary);
}

// HDS 标题栏配置（一级页 HdsNavigation / 二级页 HdsNavDestination 共用；2026-08-29 自
// dshinhm 同名函数精简随迁——样式定稿全量故事（六轮真机迭代：白底分割线四轮排查/
// 常显定稿/背景板透明收口）见 dshinhm common/ImmersiveLevel.ets 头注释，此处只留结论）：
// · 主标题 + 官方字号档（一级页缺省 TITLE_ML / 二级页传 TITLE_S——dshinhm 定稿二级页
//   小一号）+ 分割线关闭 + GRADIENT_BLUR 常显模糊（enableScrollEffect: false——true 在
//   HdsNavigation 嵌 HdsTabs 下绑定链路不可靠，dshinhm 真机定稿勿改回）+ 背板显式透明
//   （防 6.1.0(23)「GRADIENT_BLUR + 配置过材质 + false」默认规则渲染 comp_background_gray
//   灰白实底）+ 蒙层下延 maskExtraHeight = TITLE_BAR_MASK_EXTRA_HEIGHT（与页面 topPad
//   的同 名常量必须同值，Theme.ets 注释）+ 标题色显式 font_primary。
// · 材质由沉浸光感总档驱动（resolveEffectiveLevel；「无」档归一 -1 = 不设
//   systemMaterialEffect——不设而非 NONE：NONE 也属「已配置」，会触发默认背景色规则）。
//   ★ 2026-09-12 分项退役前由「其他控件」分项驱动，退役后跟随总档。
// · avoidLayoutSafeArea: true = 标题栏主动避让状态栏（全屏窗口下标题不撞状态栏的唯一
//   官方开关，dshinhm 同款；普通 Navigation 无此能力——坑2）。
// · 第 5/6/7 参（2026-08-29 M2c 自 dshinhm 原函数补齐，已验证形态照搬）：
//   menu = 右上角菜单按钮（HdsNavigationMenuContentOptions：value 数组 + 每项 content.icon/
//   action，本地 SDK d.ts @since 5.1.0(18)；icon 直接传 $r('sys.symbol.xxx') 系统符号）——
//   设置页签标题栏搜索键（magnifyingglass）消费；stackBuilder = 标题栏自定义覆盖层
//   （TitleBarContentOptions.stackBuilder，@since 6.0.0(20)；官方指南《设置自定义区域》）——
//   消费方两类共十处（2026-09-22 服务商页合并胶囊笔后全量重数；本清单与全仓调用点自动
//   对账，钉在 feature-domain 60 组）：①经 PageShell.titleBarStack 转交的七页 = ChatPage
//   （模型胶囊 + 右上角胶囊）、MemoryLibraryPage（右上角合并胶囊 = MemoryTitleBarKeys 组件；记忆管理面 2026-09-20 自 MemoryPage 迁入本页，
//   覆盖层 2026-09-13 曾随「键入更多菜单」退役、2026-09-15 按决明指令以合并胶囊形态回归）、
//   SkillLibraryPage（右上角合并胶囊〔＋|导入〕= TitleBarContent）、AttachmentViewerPage
//   （附件查看器页的页码 n/N 覆盖层，2026-09-15 二级页化笔新增——覆盖层只占标题栏右端、
//   主标题「当前页文件名」经 keepStackTitle 保留）、KnowledgeLibraryPage 与
//   KnowledgeBookPage（知识库库页/条目清单页右上角〔＋〕单圆键 = TitleBarRoundKey，
//   2026-09-21 世界书知识库首版新增——覆盖层只占标题栏右端，主标题经 keepStackTitle 保留）、
//   ProviderPage（服务商管理页右上角合并胶囊〔＋新建服务商|⋯更多〕= ProviderTitleBarKeys
//   组件，2026-09-22 决明「新建键移出与更多形成双键胶囊，参考消息页实现」——新建键自
//   「更多」菜单移出成左热区，主标题「服务商管理」经 keepStackTitle 保留）；
//   ②直调本函数传第 5 参的
//   三处 = HomeNavigation 一级页两页签（「助手」页签 = 合并胶囊〔＋新建助手|⋯更多〕=
//   AssistantTitleBarKeys 组件，2026-09-22 决明「＋/更多双键胶囊，加保持原功能，点击更多弹
//   菜单」——原官方菜单数组单键 ＋ 退役；「对话」页签 = 搜索键 + 胶囊 = ChatTabTitleBar
//   组件，两页签互斥出键、同用这一个调用点）、SearchPage
//   （搜索框嵌入标题栏）、SessionSearchPage（同）。其中自绘键件 2026-09-11 起统一来自
//   `components/TitleBarKeys.ets`（几何 + 双态单源）；传入即
//   主标题置空（覆盖层压在标题上方，官方示例同款），keepStackTitle = true 时保留主标题
//   （HomeNavigation 助手/对话两页签与 MemoryLibraryPage / SkillLibraryPage / AttachmentViewerPage /
//   KnowledgeLibraryPage / KnowledgeBookPage / ProviderPage 消费
//   ——覆盖层只占标题栏右侧，官方标题照常绘制）。★ 覆盖层内容必须是组件或组件内 @Builder
//   （全局 @Builder 被官方 napi 直接调用时无视图上下文，运行期闪退——坑30）；二级页覆盖层
//   还须挂 hitTestBehavior(Transparent)（整栏铺在返回键上方，默认档挡返回键——MemoryPage
//   自检轮实测，规范 §4）。
// · 「无」档返回键圆底分支（resolvedLevel < 0 时 backIconStyle/menuStyle 纯色圆底，官方
//   无光感样式 = comp_background_tertiary + icon_primary）随原函数补齐——总档调「无」后
//   二级页返回键/菜单键保持可见可点（dshinhm 真机定稿）。
export function hdsTitleBarOptions(mainTitle: string, level: number,
  mainTitleSize: TitleSize = TitleSize.TITLE_ML,
  menu?: HdsNavigationMenuContentOptions, stackBuilder?: CustomBuilder,
  keepStackTitle: boolean = false): HdsNavigationTitleBarOptions {
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
    // 标题栏自定义覆盖层（消费方两类七处与硬约束见头注释「第 5/6/7 参」段——本参即
    // stackBuilder；逐名清单在头注释，与全仓调用点自动对账 = feature-domain 60 组钉）
    titleBarContent.stackBuilder = stackBuilder;
  }
  return {
    avoidLayoutSafeArea: true,
    content: titleBarContent,
    style: style
  };
}
