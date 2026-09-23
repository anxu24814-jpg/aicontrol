// Kimi 半模态面板共享样式（2026-08-23 三十六改提取：P2-4——「添加文件 / 选择模型 /
// 选择工作区」三面板同款；自 FileSheet.ets 迁出）。官方文件选择器样式定稿：
// · 面板底 = 弹层族材质（ImmersiveLevel.overlayMaterial，基准 THICK，随沉浸光感总档）——
//   ★ 2026-09-22 决明指令「半模态/弹窗也改 thick」：原「面板固定实底 app.color.page_bg、
//   永久退出 uiMaterial 光感档位体系」（坑66 定论：实底全高一致无导航条分割带）就此推翻
//   为：有档 = 材质、总档「无」= Material.empty 回落 page_bg 实底（原实底语句保留为
//   「无」档专用回退，勿删）；坑66 的导航条分割带现象若在材质态复现，按真机复核处置
//   （回退路径 = 总档调「无」或报告后单点调整）；
// · 标题栏 GRADIENT_BLUR + enableScrollEffect=false = 静止直接生效渐变模糊（官方表实锤，
//   「直接生效模糊」语义）+ **标题栏 HDS 材质**（systemMaterialEffect @since 23；材质档下
//   官方配套默认：GRADIENT_BLUR + 材质 + false 时 backgroundColor 默认 sys.color.
//   comp_background_gray、blurRadius 默认 12 = 浅灰蒙层 + 材质光感 + 模糊透出，外观近
//   官方 picker 顶部；原 35 改的纯透明 + blur16 由官方默认接替——统一三面板）；
//   ★ 四十二改（决明真机确认定稿）：标题栏材质随沉浸光感总档（原写死
//   IMMERSIVE+ADAPTIVE 系统自适应、不随档；2026-09-12 分项退役前随沉浸光感总档）
//   ——同 hdsTitleBarOptions 姿势：
//   resolveEffectiveLevel + hdsMaterialParams 映射；「无」档彻底不设 systemMaterialEffect
//   （NONE 也属「已配置」，会触发 comp_background_gray 默认规则——hdsTitleBarOptions 第五轮
//   结论）+ 背板显式透明 + 关闭键换官方无光感纯色圆底。★ 面板底于 2026-09-22 决明指令起
//   改用弹层族材质（见首节），原「面板实底仍退出档位体系（坑66 病根，不动）」随该指令解除。
// · divider AUTO（官方 picker 跟手分割线；真机若 AUTO 在 false 下不显示，回退 ON）。
// 坑69 不适用于声明式 bindSheet（内容属页面树、深浅色随动）；编程式（ComponentContent）
// 面板在本文件外不复用本样式（坑66 同源）。
// ★ 2026-09-23 半模态关闭确认笔：本件同时是「关闭前确认弹窗」的形制单源（SheetCloseConfirm +
// confirmSheetClose，文件尾）——半模态的关闭意图分三路（标题栏自绘关闭键 / 宿主 onWillDismiss
// 〔下拉·侧滑·三键 back·ESC·点蒙层，框架转交〕/ 面板内容件关闭键上行），需要二次确认的站点
// 三路都调该函数，键序与键色只在本处一份。
import { UIContext } from '@kit.ArkUI';
import {
  DividerShowType, HdsNavigationTitleBarOptions,
  HdsTitleBarContentStyle, ScrollEffectType, TitleBarContentOptions, TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { SHEET_MASK_COLOR } from '../../common/Theme';
import { hdsMaterialParams, overlayMaterial, resolveEffectiveLevel } from '../../common/ImmersiveLevel';

// 面板标题栏（MODAL 标题栏 + xmark 官方关闭键（menu 数组）+ AUTO 分割线 + 静止渐变模糊 +
// 标题栏 HDS 材质随沉浸光感总档（★ 四十二改：原写死 IMMERSIVE+ADAPTIVE 系统自适应
// 不随档；现同 hdsTitleBarOptions：>=0 档 hdsMaterialParams 映射，<0「无」档彻底不设材质 +
// 背板透明 + 关闭键官方无光感纯色圆底——2026-08-20 二级页「无」档同因定稿：透明圆底+提亮
// 压暗在实色背景上看不出按钮背景）；文字/图标色显式 font_primary 系——官方默认此时为
// on_primary 白字，灰蒙层+透出下不可读，显式覆盖必要；两态同色防十五改白字白图标浅色底不可读）
// ★ 二一七改（回退二一五改的参数化——决明指引「参考列表类半模态（选择模型）的顶部
// 模糊，它就是可以的」）：dividerShow/componentSafeArea 两参数删除，函数恢复 5 参原样
// （AUTO 分割线 + enableComponentSafeArea true = 模型选择面板同款、真机验收过的好观感；
// 二一五改的 OFF/内容延伸在半模态标题栏上实测反而出现分割线且下移——过度自定义，
// 教训：半模态顶部跟随既有面板规格，不自创）
// ★ 2026-08-31 演进（可选第 6 参 confirmAction，向后兼容——现有 5 参调用零改动）：
// 右上角「保存勾」键（checkmark，获取模型同步面板用）——菜单键数组 = [保存勾, xmark 关闭]
//（HDS 标题栏菜单键自右缘排布，保存为主操作靠右；真机若顺序观感不佳调换数组序即可）
export function sheetTitleBarOptions(mainTitle: string, subTitle: string,
  onClose: () => void, level: number,   confirmAction?: () => void): HdsNavigationTitleBarOptions {
  const resolvedLevel: number = resolveEffectiveLevel(level);
  const titleBarContent: TitleBarContentOptions = {
    title: { mainTitle: mainTitle, subTitle: subTitle },
    divider: { showType: DividerShowType.AUTO },
    menu: {
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
    // ★ 四十二改：标题栏 HDS 材质随沉浸光感总档驱动（原写死 IMMERSIVE+
    // ADAPTIVE 系统自适应——hdsMaterial 与 uiMaterial 两体系无关、不随应用档位；现按
    // hdsMaterialParams(resolvedLevel) 映射：0=ADAPTIVE 系统策略 / 2=SMOOTH / 3=GENTLE /
    // 4=EXQUISITE。2026-09-12 分项退役前随沉浸光感总档）。材质档下官方配套默认（无需显式设 backgroundStyle）：false 模式
    // backgroundColor = comp_background_gray（深浅分治）、blurRadius 12。
    // 「无」档（resolvedLevel<0）：不设 systemMaterialEffect（NONE 属「已配置」，触发
    // comp_background_gray 默认规则嫌疑——hdsTitleBarOptions 第五轮结论）+ 背板显式透明，
    // 只留 GRADIENT_BLUR 常显蒙层（「不设 = 透明」无官方依据，显式设防默认规则兜底）
    originalStyle: {
      backgroundStyle: resolvedLevel < 0
        ? { backgroundColor: Color.Transparent, maskExtraHeight: 0 }
        : { maskExtraHeight: 0 },
      contentStyle: textStyle
    }
  };
  if (resolvedLevel >= 0) {
    style.systemMaterialEffect = hdsMaterialParams(resolvedLevel);
  }
  // 三十九改：maskExtraHeight: 0——官方默认 32vp 蒙层下探会盖住首卡上沿（决明真机反馈
  //「首卡进入渐变模糊区」）；标题栏区模糊/材质采样不受影响（滚动内容滚入标题栏区仍被模糊）
  return { enableComponentSafeArea: true, content: titleBarContent, style: style };
}

// 面板 SheetOptions（官方标准双停靠位 + 显式遮罩色 + 弹层族材质（overlayMaterial，基准
// THICK 随沉浸光感总档；★ 2026-09-22 决明指令；「无」档 Material.empty → 官方语义下材质
// 关闭、backgroundColor 恢复生效，即实底回退路径）；maskColor 与页面其余弹层同源
//（Theme.SHEET_MASK_COLOR）。
// ★ onWillDismiss（可选，37 改 onDisappear → 43 改换用）：手势关闭（遮罩点击/下滑/系统
// 返回键）在**关闭动画开始前**同步回调（d.ts 实锤：onWillDismiss @since 12；
// onDisappear 是「动画结束后才回调」——43 改竞态根因：A 关闭动画结束时的迟到回调把
// sheetShow 回写 false，快速打开的 B 被误杀自动收起）。在此回写显示状态 = 手势关闭路径
// 全部动画前同步置 false，无迟到回调窗口：「关闭再开不弹」（37 改真机复现：sheetShow 残留
// true 值不变不触发刷新）继续解决，且「关 A 立即开 B」不再竞态。代码置 false（xmark/
// 选中）不触发本回调（且这两路径已在代码侧同步置 false）。回调须幂等（关闭后置 false，
// 面板已 false 时赋值无副作用）
// detents 元组类型（SheetOptions.detents = [第一档, 第二档?, 第三档?]，d.ts 实锤非数组）
export type SheetDetents = [string | number | Resource, (string | number | Resource)?,
  (string | number | Resource)?];

// ★ 2026-09-15（决明指令「选择模型半模态默认展开全屏、取消半屏态、全屏下拉直接收起」）：
// **全屏单挡位** = 唯一挡位 LARGE——开局即全屏（API 参考原文「底部弹窗竖屏生效，元组中第一
// 个高度为初始高度」；本场景即底部弹窗竖屏）+ 下拉无中间停靠直达关闭（无第二挡位可停；官方
// FAQ 场景三原文「即使已经停靠在最小挡位高度，也能通过滑动弹窗继续下拉，松手后系统会依据
// 下拉速度和距离，关闭半模态弹窗或者是回弹到最小挡位高度」）。单一来源：选择模型面板三站点
// （对话页 / 助手模型设置 / 功能模型）共用本常量，改此一行三处同效——档位是 bindSheet 宿主
// 参数，不在面板件（ModelPickerSheet）内部。
export const DETENTS_FULL: SheetDetents = [SheetSize.LARGE];

export function sheetPanelOptions(onWillDismiss?: (action: DismissSheetAction) => void,
  detents?: SheetDetents): SheetOptions {
  const options: SheetOptions = {
    maskColor: SHEET_MASK_COLOR,
    showClose: false,
    enableFloatingDragBar: true,
    // 「无」档专用实底回退（材质生效时官方忽略 backgroundColor、Material.empty 时恢复；
    // 官方《组件适配沉浸光感》「弹出框」节）
    backgroundColor: $r('app.color.page_bg'),
    systemMaterial: overlayMaterial()
  };
  // 四十改：detents 参数化——默认官方双停靠位 MEDIUM/LARGE（★ 2026-09-15 自检轮订正：唯一
  // 吃本默认者 = FunctionalModelPage 提示词编辑面板〔传 undefined 分支〕，不是「列表类面板」
  // ——列表类面板今已全部显式传参）。★ 同日：提示词/附件面板（ChatPage 'prompt' 分支）改传
  // 同值 [MEDIUM, LARGE]——决明指令「默认半屏、仍支持拉全屏」，原 [FIT_CONTENT, LARGE] 档位
  // 自此零在役消费者；选择模型面板改传 DETENTS_FULL 全屏单挡位，不再吃本默认
  if (detents !== undefined) {
    options.detents = detents;
  } else {
    options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
  }
  if (onWillDismiss !== undefined) {
    options.onWillDismiss = onWillDismiss;
  }
  return options;
}

// ── 关闭前确认弹窗（形制单源；2026-09-23 半模态关闭确认笔）──
// 站点只供文案（SheetCloseConfirm 四字段），键序 / 键色 / 取消语义三件固定在本函数：
// · 键序 = [取消, 确认]（确认在右）：取消键 sys.color.font_secondary、确认键 font_primary
//  （压缩面板 2026-09-23 修复笔现役口径，统一到它保三站点同形）；
// · 返回值 = 用户是否选「确认」（放弃改动 / 停止生成）：true 才放行关闭；
// · 取消语义——三种「非确认出口」全部落「不关面板」：①点蒙层关掉确认弹窗 ②弹窗期间按系统
//   返回（autoCancel 官方默认只关弹窗——**勿改 false**，那会把出口①变成无出口死结）
//   ③弹窗自身异常（catch 返回 false）。★ 2026-09-23 自检轮订正：出口③**不弹提示**（只是不关
//   面板，用户看到面板还在会再点一次），故这里**不是**「P0-1 不静默」的适用面——它的取舍是
//   「宁可多问一次，不可误弃」，本件全程零静默数据丢弃；原注释自称「P0-1 不静默」与此不符，
//   已按自检轮实测（异常路径无 toast）改为现述。
// 判据来源：官方《绑定半模态页面（bindSheet）》「二次确认能力」节原文——「声明 onWillDismiss
// 接口后，半模态页面的所有关闭操作，包括侧滑、点击关闭按钮、点击蒙层和下拉关闭，都需通过调用
// dismiss 方法来实现。若未实现此逻辑，半模态页面将无法响应上述关闭操作。」（本仓自绘关闭键
// 不进该漏斗，故站点须把标题栏关闭键一路也指到同一收口方法）
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
