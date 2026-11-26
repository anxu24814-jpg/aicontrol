// 会话多选批量条（自 dshinhm 迁入，域级最小拆分先例）：本件承载五宿主共用判据纯函数
// （isAllSelectedIn / hasHiddenSelection / nextSelectAllIds）+ 唯一挂载形态
// SessionMultiselectActionBar（HdsActionBar 图标三键，决明拍板「采用无主按钮路线」；
// HDS 组件系统内置，无 HDS 回退文字条已退役）：
// · 容器 HitTestMode.Transparent（官方 d.ts：自身与子组件响应命中、不拦兄弟节点）——按钮
//   可点、空白区触摸穿透到下层列表；Blank 把操作条压到容器底部；
//   ★ 坑96（真机报障「点胶囊本体仍穿透到后面的勾选卡片」）：Transparent 只放行空白区——
//   本体区（键间隙与左右留白）无消费方时点击落到下层卡片 onClick（多选态 = 误勾选）；本体
//   容器挂空 onClick 消费本区域（子键照常深层优先响应），空白穿透与滚动契约不变；
// · 全选键位理由 = 多选模式契约「原键位一律让位、动作集中在这条操作条上」（标题栏各键
//   多选态 no-op、卡片菜单键不渲染、底部页签收起），全选属模式内批量动作故同区。
import { LengthMetrics } from '@kit.ArkUI';
import { ActionBarButton, ActionBarStyle, HdsActionBar } from '@kit.UIDesignKit';

// 侧栏形态全选指令键（一次性计数器，2026-11-16 首页布局双形态笔——坑3 口径多层宿主链
// 零透传）：发布方 = HomeNavigation 批量条「全选」键（选集与批量条在 drawer 域、行集在侧栏列表，
// 跨抽屉两域经命令键直达），消费方 = SideSessionList @StorageProp @Watch——经
// nextSelectAllIds 按可见行集算好整组上行 onSetSelected
export const SIDE_SELECT_ALL_CMD_KEY: string = 'sideSelectAllCmd';

// 全选两态判据（纯函数，断言脚本剥 import 后直跑）：可见行逐行都在已选集内 = 全选态（键面
// 落「全不选」）。★ 按可见行逐行判而非「已选数 == 可见数」——边缘窗口下计数相等不蕴含集合
// 相等。空可见集恒 false：0 行键面落「全选」、点击由调用方守卫拦成 no-op（不加禁用态口径）。
export function isAllSelectedIn(visibleIds: string[], selectedIds: string[]): boolean {
  if (visibleIds.length === 0) {
    return false;
  }
  for (const id of visibleIds) {
    if (selectedIds.indexOf(id) < 0) {
      return false;
    }
  }
  return true;
}

// 已选是否含不可见行（纯函数）：用于「列表来源变了」的清空兜底——切分段之外同类源 = 换
// 助手（HDS 路径本组件活在 TabContent 跨页签不销毁，选择会残留成「删掉看不见的会话」）/
// 备份恢复 / 他处删行，三者都让可见集整体换掉而段值不变。单纯增长（主动消息落库 / 标题
// 写回重拉）不触发：已选仍在可见集内。空已选集恒 false。
export function hasHiddenSelection(visibleIds: string[], selectedIds: string[]): boolean {
  for (const id of selectedIds) {
    if (visibleIds.indexOf(id) < 0) {
      return true;
    }
  }
  return false;
}

// 全选/全不选切换（纯函数）：全选态 → 清空；否则选中可见集本体（顺带丢弃不可见残留——切分
// 段清空是主阀门，本函数是第二道自愈）。★ 返回 slice 普通数组（坑6：@State 观察代理数组
// 直传 napi 抛 401，切片脱代理）
export function nextSelectAllIds(visibleIds: string[], selectedIds: string[]): string[] {
  return isAllSelectedIn(visibleIds, selectedIds) ? [] : visibleIds.slice();
}

// ═══ HDS 形态批量条（决明拍板「采用无主按钮路线」）═══
// 形态 = HdsActionBar 无主按钮（syscap = HDSPattern.Standard）：startButtons 左〔全选态
// 切换｜取消〕、endButtons 右〔删除〕（分组 = 拍板所见即所得）。键面只有圆形图标——「删除
// N 项」计数文字随形态退役（拍板），计数反馈保留在确认弹窗。图标语义：全选 =
// checkmark_circle ↔ checkmark_circle_fill 两态（状态式图标，避开与取消键 xmark 形近碰撞）；
// 取消 = xmark；删除 = trash。
// · ★ 键序稳定化（真机实锤修复）：首版 build 内每帧重建按钮数组，重渲染后 start/end 两组
//   整体换序镜像（V2 @Param 数组整组替换的内部重排）——修复 = 三枚 ActionBarButton 与样式
//   提为成员构造一次，两态经 @Prop @Watch 只突变 @Trace 属性，数组引用恒定零重排机会
//  （官方按钮设计成 @ObservedV2/@Trace 的意图用法）。
// · 高度对齐（真机反馈）：ActionBarStyle.height 显式 56vp = HdsTabs 悬浮页签胶囊高，替换
//   官方默认背板高（观感过高）；isExpand 显式 true（无主按钮不支持切换展开收缩）。
// · 删除键 enabled 随 deleting 翻转（删除在途的禁用反馈，防重复点击可见；语义守卫仍在
//   宿主首行）。
// · 定位与穿透契约：全高容器 + Blank 压底 + Transparent 空白穿透 + barBottom 让位（与页签
//   常态几何重合，多选中页签已收起）；本体容器挂空 onClick 消费（坑96）。
// · 材质口径偏离声明（P2-5）：本形态背板与圆键材质 = HdsActionBar 官方内建（与 HdsTabs /
//   HdsNavigation 同属 HDS 族口径），不接内容区回退开关与光感档位，两态成员无需透传。
// · HdsActionBar 为批量条唯一挂载形态（无 HDS 回退已退役），宿主多选态直接挂载本组件。
const ACTIONBAR_HEIGHT_MATCHING_TAB: number = 56;

@Component
export struct SessionMultiselectActionBar {
  // 全选两态（宿主按 isAllSelectedIn 判定后传入——@Watch 驱动全选图标 fill/描边突变）
  @Prop @Watch('syncButtonStates') allSelected: boolean = false;
  // 删除请求在途（true = 删除键置禁用态，防重复点击反馈）
  @Prop @Watch('syncButtonStates') deleting: boolean = false;
  // 取消（退出多选）/ 删除（执行批量删除）/ 全选切换——回调上行宿主页
  onCancel: () => void = () => {
  };
  onPrimary: () => void = () => {
  };
  onToggleAll: () => void = () => {
  };
  // 批量条距屏底（vp，宿主传 navBarHeight——与页签常态几何重合，见头注释）
  barBottom: number = 80;

  // 三枚键持实例构造一次（成员声明序 = 数组初始化依赖序；onClick 闭包调用期才解引用 this）。
  // 初始图标 = 全选描边态（aboutToAppear 再对齐）
  private selectAllBtn: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.checkmark_circle'),
    accessibilityText: '全选',
    onClick: (): void => {
      this.onToggleAll();
    }
  });
  private cancelBtn: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.xmark'),
    accessibilityText: '取消',
    onClick: (): void => {
      this.onCancel();
    }
  });
  private deleteBtn: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.trash'),
    accessibilityText: '删除',
    enabled: true,
    onClick: (): void => {
      this.onPrimary();
    }
  });
  private startBtns: Array<ActionBarButton> = [this.selectAllBtn, this.cancelBtn];
  private endBtns: Array<ActionBarButton> = [this.deleteBtn];
  // 背板样式持实例（高度 = 页签胶囊 56vp，见头注释；@Trace 属性可后续突变）
  private barStyle: ActionBarStyle = new ActionBarStyle({
    height: LengthMetrics.vp(ACTIONBAR_HEIGHT_MATCHING_TAB)
  });

  aboutToAppear(): void {
    // @Prop 初始化期不触发 @Watch——挂载首帧把两态显式刷上键面（防御性对齐）
    this.syncButtonStates();
  }

  // 两态 → 键面突变（@Trace 属性赋值即驱动 HdsActionBar 内部刷新，零数组替换）
  private syncButtonStates(): void {
    this.selectAllBtn.baseIcon = this.allSelected ? $r('sys.symbol.checkmark_circle_fill')
      : $r('sys.symbol.checkmark_circle');
    this.selectAllBtn.accessibilityText = this.allSelected ? '全不选' : '全选';
    this.deleteBtn.enabled = !this.deleting;
  }

  build() {
    Column() {
      Blank()
      Column() {
        HdsActionBar({
          startButtons: this.startBtns,
          endButtons: this.endBtns,
          actionBarStyle: this.barStyle,
          isExpand: true
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      // 本体点击消费（坑96，口径见文件头）：空 onClick 消费本区域点击防穿透
      //——HDS 三圆键深层优先响应；不挂 focusable(false)（连带子键不可获焦）；
      // accessibilityLevel('no') 只隐本容器自身
      .onClick(() => {
        // 空实现：只消费点击防穿透
      })
      .accessibilityLevel('no')
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .padding({ bottom: this.barBottom })
  }
}
