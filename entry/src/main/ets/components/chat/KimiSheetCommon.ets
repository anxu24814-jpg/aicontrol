// Kimi 半模态面板共享样式（「添加文件 / 选择模型 / 选择工作区」三面板同款提取）。定稿口径：
// · 面板底 = 半模态专用材质（sheetMaterial，基准 ULTRA_THICK 随沉浸光感总档——2026-10-18
//   决明「全部半模态底改厚，光感弱一档」）；总档「无」= Material.empty 回落 page_bg 实底
//  （原实底语句保留为「无」档专用回退，勿删；坑66 导航条分割带若在材质态复现，按真机复核处置）；
// · 标题栏 GRADIENT_BLUR + enableScrollEffect=false（静止直接生效渐变模糊，官方表实锤）+
//   标题栏 HDS 材质随总档（resolveEffectiveLevel + hdsMaterialParams 映射）；「无」档彻底
//   不设 systemMaterialEffect（NONE 也属「已配置」，会触发 comp_background_gray 默认规则）+
//   关闭键换官方无光感纯色圆底；
//   ★ 2026-10-29 背板恒透明（决明拍板「删蒙层、不删模糊」）：原「材质档吃官方默认
//   backgroundColor = comp_background_gray（不透明浅灰白）」口径已推翻——那层灰白实底就是
//   白蒙层本体；现两档统一显式 Transparent，回退阶梯见下方 originalStyle 处注释；
// · ★ blurStrategy 同页面级单源（2026-11-05 契约固化笔）：显式 ADAPTIVE = SDK 官方默认
//   （hdsBaseComponent.d.ets @default，@since 6.0.0(20)），零行为变化。快速滚动时系统可临时
//   关模糊保帧率、停止后恢复，属官方默认策略，**不作缺陷立项**；半模态恒
//   enableComponentSafeArea: true（内容避让标题栏、不穿透），模糊背后是面板底，降级几乎无感。
//   禁改 ENABLE（代价 = 滚动帧率/功耗上升，先拍板）。语义与分档判据 =
//   ImmersiveLevel.hdsTitleBarOptions 头注释 + docs/规范-搜索交互.md §6。
// · divider AUTO（官方 picker 跟手分割线；真机若 AUTO 在 false 下不显示，回退 ON）。
// 坑69 不适用于声明式 bindSheet（内容属页面树、深浅色随动）；编程式（ComponentContent）面板
// 不复用本样式（坑66 同源）。
// ★ 本件同时是「关闭前确认弹窗」的形制单源（SheetCloseConfirm + confirmSheetClose，文件尾）
//——半模态关闭意图三路（标题栏自绘关闭键 / 宿主 onWillDismiss〔下拉·侧滑·back·ESC·点蒙层〕
// / 面板内容件关闭键上行）需要二次确认的站点都调该函数，键序与键色只在本处一份。
import { UIContext } from '@kit.ArkUI';
import {
  BlurStrategy, BottomBuilderParams, DividerShowType, HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions, HdsTitleBarContentStyle, ScrollEffectType, TitleBarContentOptions,
  TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { SHEET_MASK_COLOR } from '../../common/Theme';
import {
  hdsMaterialParams, overlayMaterial, resolveEffectiveLevel, sheetMaterial
} from '../../common/ImmersiveLevel';

// 面板标题栏（MODAL 标题栏 + xmark 官方关闭键〔menu 数组〕+ AUTO 分割线 + 静止渐变模糊 +
// 标题栏 HDS 材质随总档：>=0 档 hdsMaterialParams 映射，<0「无」档彻底不设材质 + 背板透明 +
// 关闭键官方无光感纯色圆底〔透明圆底在实色背景上看不出按钮背景，二级页「无」档同因定稿〕）。
// 文字/图标色显式 font_primary 系——官方默认此时 on_primary 白字，灰蒙层下不可读，两态
// 同色防白字白图标浅色底不可读。参数化回退教训（决明指引「参考选择模型半模态的顶部模糊」）：
// dividerShow/componentSafeArea 两参数已删、恢复 5 参原样（AUTO + enableComponentSafeArea
// true = 真机验收过的好观感；OFF/内容延伸实测反而分割线下移——半模态顶部跟随既有面板规格，
// 不自创）。
// 第 5 参 confirmAction（可选，向后兼容）：右上角「保存勾」键——菜单键数组 = [保存勾,
// xmark 关闭]（HDS 菜单键自右缘排布，保存靠右）。
// 第 6 参 menuOverride（可选）：完整菜单内容覆盖——排队面板标题栏双键（左启动/暂停、右
// 清空）无 xmark，关闭 = 下拉手势经宿主 onWillDismiss。传本参时 onClose / confirmAction
// 均不参与菜单构造（标题栏其余结构仍由本函数单源）；不传 = 行为与既有逐字一致。
// 第 7 参 bottomBuilder（可选）：标题栏下方自定义区（官方 BottomBuilderParams，@since 20）——
// 现用途 = **面板内搜索框吸顶**（2026-10-31「两处半模态搜索框合入标题自定义区」笔；官方
// 《设置自定义区域》导语明示用途即「标题下方区域增加搜索框、页签」）。带宽算式单源 =
// ImmersiveLevel.segmentBandParams（带内下移 8 + 内容高 40 = 48），消费方勿另算。★ 本壳恒
// enableComponentSafeArea: true（内容区本就避让标题栏），加带后带高自动并入组件安全区 ⇒
// 面板内容零手算让位（页面级 PageShell 才要 searchBandContentTop）；动态收起 = 调用点传
// undefined（同 PageShell titleBarBottomHidden 机理——标题栏逐帧按新选项重建，带随之收放）。
export function sheetTitleBarOptions(mainTitle: string, subTitle: string,
  onClose: () => void, level: number, confirmAction?: () => void,
  menuOverride?: HdsNavigationMenuContentOptions,
  bottomBuilder?: BottomBuilderParams): HdsNavigationTitleBarOptions {
  const resolvedLevel: number = resolveEffectiveLevel(level);
  const titleBarContent: TitleBarContentOptions = {
    title: { mainTitle: mainTitle, subTitle: subTitle },
    divider: { showType: DividerShowType.AUTO },
    menu: menuOverride !== undefined ? menuOverride : {
      value: confirmAction === undefined ? [{
        content: {
          // 关闭键图标（官方 xmark 系统符号；icon 尺寸走 HDS 菜单键官方默认）
          icon: $r('sys.symbol.xmark'),
          action: onClose
        }
      }] : [{
        content: {
          icon: $r('sys.symbol.checkmark'),
          action: confirmAction
        }
      }, {
        content: {
          icon: $r('sys.symbol.xmark'),
          action: onClose
        }
      }]
    }
  };
  const textStyle: HdsTitleBarContentStyle = {
    titleStyle: {
      mainTitleColor: $r('sys.color.font_primary'),
      subTitleColor: $r('sys.color.font_secondary')
    },
    menuStyle: { iconColor: $r('sys.color.icon_primary') }
  };
  // 「无」档：关闭键官方无光感纯色圆底（comp_background_tertiary + icon_primary，
  // 同 hdsTitleBarOptions「无」档返回键/菜单键规则）
  if (resolvedLevel < 0) {
    textStyle.menuStyle = {
      backgroundColor: $r('sys.color.comp_background_tertiary'),
      iconColor: $r('sys.color.icon_primary')
    };
  }
  const style: TitleBarStyleOptions = {
    scrollEffectOpts: {
      // false = GRADIENT_BLUR 静止直接生效渐变模糊（官方表「直接生效模糊」语义，无需滚动）
      enableScrollEffect: false,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR
    },
    // 官方默认档显式固化，与页面级 hdsTitleBarOptions 同值同链（零行为变化，见文件头条）
    blurStrategy: BlurStrategy.ADAPTIVE,
    // 标题栏材质随总档（hdsMaterialParams(resolvedLevel) 映射：0=ADAPTIVE / 2=SMOOTH /
    // 3=GENTLE / 4=EXQUISITE）。
    // ★ 2026-10-29 背板恒透明（决明拍板「删蒙层、不删模糊」）：原高档分支不设 backgroundColor，
    // 命中官方默认规则「GRADIENT_BLUR + 已配置材质 + enableScrollEffect:false ⇒ 背板
    // comp_background_gray（不透明浅灰白）」——那层灰白实底就是白蒙层本体；现两档统一显式
    // 透明（与 hdsTitleBarOptions 同形），顶部只剩「面板底 + 标题栏材质 + 模糊」三层。
    // 回退阶梯（真机嫌太透按序单点调，禁整段回滚）：①blurRadius 调 8~10（d.ts @since 23，
    // 取值 [0,128]）；②材质收一档 GENTLE；③才考虑极淡半透明背板（手写 alpha 色深浅两套）。
    // maskExtraHeight 恒 0（官方默认 32vp 蒙层下探盖住首卡上沿，真机教训）；透明后如需软化
    // 下沿边界只可试 8~16，禁回 32。
    originalStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 0 },
      contentStyle: textStyle
    }
  };
  if (resolvedLevel >= 0) {
    style.systemMaterialEffect = hdsMaterialParams(resolvedLevel);
  }
  // 标题栏下方自定义区（用途/算式/收起口径见函数头第 7 参注释）——不传 = 标题栏结构与既有逐字一致
  if (bottomBuilder) {
    titleBarContent.bottomBuilder = bottomBuilder;
  }
  // enableComponentSafeArea: true = 内容区避让标题栏（官方指南示例同款）；maskExtraHeight 缘由见上方
  return { enableComponentSafeArea: true, content: titleBarContent, style: style };
}

// 面板 SheetOptions（官方标准双停靠位 + 显式遮罩色 + 面板底材质 sheetMaterial〔基准
// ULTRA_THICK 随总档，「无」档 Material.empty = 材质关闭、backgroundColor 恢复生效即实底
// 回退〕；maskColor 与页面其余弹层同源 Theme.SHEET_MASK_COLOR）。
// ★ onWillDismiss（可选）：手势关闭（遮罩/下滑/返回键）在**关闭动画开始前**同步回调
//（d.ts 实锤；onDisappear 是动画结束后才回调——其迟到回调把 sheetShow 回写 false 会误杀
// 快速打开的下一个面板）。在此回写显示状态 = 手势路径全部动画前同步置 false，「关 A 立即
// 开 B」无竞态。代码置 false（xmark/选中）不触发本回调。回调须幂等。
// ★ 关闭链统一件（全仓挂载点一体收口）：①可见性一律 `$$` 布尔双向（程序化关闭 = 赋
// false，官方示例唯一形态）；②onWillDismiss 回调内调 action.dismiss() 放行（官方《绑定
// 半模态页面（bindSheet）》「二次确认能力」节：注册后所有关闭操作都需经 dismiss()，漏调
// 则关不掉）；放行两变体——零暂存站点恒放行，确认站点确认通过才放行；③关闭恒不复位内容
// 形态（关闭写点只置可见性，禁写内容形态串）；④下拉回弹口径——缺省直落不回弹，含二次
// 确认的形态传 pullSpringBack=true 保留官方回弹。
// detents 元组类型（SheetOptions.detents = [第一档, 第二档?, 第三档?]，d.ts 实锤非数组）
export type SheetDetents = [string | number | Resource, (string | number | Resource)?,
  (string | number | Resource)?];

// ★ 全屏单挡位（决明指令「选择模型半模态默认展开全屏、取消半屏态、全屏下拉直接收起」）：
// 唯一挡位 LARGE = 开局即全屏（元组第一高度即初始高度）+ 下拉无中间停靠直达关闭（官方
// FAQ 场景三：停靠最小挡位后仍可继续下拉关闭或回弹）。选择模型面板三站点（对话页 / 助手
// 模型设置 / 功能模型）共用本常量，改此一行三处同效——档位是 bindSheet 宿主参数，不在
// 面板件（ModelPickerSheet）内部。
export const DETENTS_FULL: SheetDetents = [SheetSize.LARGE];

// pullSpringBack（第三参；缺省 = 项目口径「下拉直落不回弹」）：缺省时注册空
// onWillSpringBackWhenDismiss（官方指南：声明后回弹须自行 springBack() 处理，无此逻辑则
// 不回弹；不注册则官方默认「先回弹再决定是否关闭」= 上下闪动两步，judder 源；d.ts @since 12）。
// ★ 传 true = 保留官方回弹——只给含二次确认（下拉被拦）的形态用：确认弹窗「取消」后面板
// 须靠预回弹复位；零暂存（下拉即关）形态一律缺省直落。保留回弹三形态 = 获取模型 /
// 功能模型页提示词 / 对话页压缩，其余全量直落。
// onDisappear（第四参，可选）：离场动效**结束后**回调——给「列表行连续点开同一面板」形态
// 做「等动效结束再补开」的完成信号（官方：离场动效不支持打断，须完全结束才可再次拉起；
// 消费方 = 会话轨迹页 / 请求日志页）。其余站点不传 = 零行为变化。
export function sheetPanelOptions(onWillDismiss?: (action: DismissSheetAction) => void,
  detents?: SheetDetents, pullSpringBack?: boolean,
  onDisappear?: () => void): SheetOptions {
  const options: SheetOptions = {
    maskColor: SHEET_MASK_COLOR,
    showClose: false,
    enableFloatingDragBar: true,
    // 「无」档专用实底回退（材质生效时官方忽略 backgroundColor、Material.empty 时恢复）
    backgroundColor: $r('app.color.page_bg'),
    systemMaterial: sheetMaterial(),
    // ★ 滚动区跟手刷新（决明真机报障 + 指令）：官方默认 FOLLOW_DETENT = 滑动结束后才更新
    // 内容显示区域——拖拽换档期间内容区不跟手、旧底边以下整片空白；CONTINUOUS = 滑动过程
    // 中持续刷新（出处 = API 参考《半模态转场》scrollSizeMode + d.ts 枚举注释）。全站统一
    // 设于本函数 = 全工程唯一 SheetOptions 构造点；单档位面板无换档拖动，本项空转无副作用。
    scrollSizeMode: ScrollSizeMode.CONTINUOUS
  };
  // 默认官方双停靠位 MEDIUM/LARGE——唯一吃本默认者 = FunctionalModelPage 提示词编辑面板
  //（undefined 分支）；提示词/附件面板与它同值 [MEDIUM, LARGE]（决明指令「默认半屏、仍
  // 支持拉全屏」），选择模型面板传 DETENTS_FULL 全屏单挡位
  if (detents !== undefined) {
    options.detents = detents;
  } else {
    options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
  }
  if (onWillDismiss !== undefined) {
    options.onWillDismiss = onWillDismiss;
  }
  if (pullSpringBack !== true) {
    // 缺省直落口径见函数头：空实现不调 springBack()，无「回弹再关」两步闪动
    options.onWillSpringBackWhenDismiss = (_spring: SpringBackAction): void => {
    };
  }
  if (onDisappear !== undefined) {
    options.onDisappear = onDisappear;
  }
  return options;
}

// ── 关闭前确认弹窗（形制单源）──
// 站点只供文案（SheetCloseConfirm 四字段），键序 / 键色 / 取消语义三件固定在本函数：
// · 键序 = [取消, 确认]（确认在右）：取消键 sys.color.font_secondary、确认键 font_primary；
// · 返回值 = 用户是否选「确认」（放弃改动 / 停止生成）：true 才放行关闭；
// · 取消语义——三种「非确认出口」全部落「不关面板」：①点蒙层关掉确认弹窗 ②弹窗期间按系统
//   返回（autoCancel 官方默认只关弹窗——**勿改 false**，那会把出口①变成无出口死结）
//   ③弹窗自身异常（catch 返回 false，不弹提示——只是不关面板，用户看到面板还在会再点一次；
//   取舍是「宁可多问一次，不可误弃」，全程零静默数据丢弃）。
// 判据来源：官方《绑定半模态页面（bindSheet）》「二次确认能力」节——「声明 onWillDismiss
// 接口后，半模态页面的所有关闭操作……都需通过调用 dismiss 方法来实现。若未实现此逻辑，
// 半模态页面将无法响应上述关闭操作。」（本仓自绘关闭键不进该漏斗，故站点须把标题栏关闭
// 键一路也指到同一收口方法）
export interface SheetCloseConfirm {
  title: string;
  message: string;
  cancelLabel: string;
  confirmLabel: string;
}

export async function confirmSheetClose(ui: UIContext, spec: SheetCloseConfirm): Promise<boolean> {
  try {
    const choice = await ui.getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: spec.title,
      message: spec.message,
      buttons: [
        { text: spec.cancelLabel, color: $r('sys.color.font_secondary') },
        { text: spec.confirmLabel, color: $r('sys.color.font_primary') }
      ]
    });
    return choice.index === 1;
  } catch (e) {
    return false;
  }
}
