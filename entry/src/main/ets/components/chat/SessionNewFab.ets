// 会话列表右下悬浮新建键（决明指令「一级页右下悬浮新建键（智感握姿跟随）」，真机反馈四改定稿）。
// 沿革：2026-08-31 曾上移标题栏本键退役，2026-10-25 决明主动复活（ChatSessionList 与
// TabMoreMenu 退役注释同笔改写为复活登记）——勿据旧退役结论再移除。
//
// 职责一句话：**会话列表中那一枚悬浮新建键的全部——位置、握姿跟随、显隐契约、点击上行**。
//
// 为何独立成件（反碎片下限②的「为何不能并入」）：motion 握姿订阅要求自有
// aboutToAppear/aboutToDisappear 成对生命周期（成对释放红线）；并入 ChatSessionList 会把
// 传感器订阅的寿命绑到整页壳。本件只做悬浮键，宿主只留一行挂载 + 内容区宽度下行。
//
// · 形态：**局部容器 + 绝对定位，零满高覆盖**。
//   - 根节点只占 56×56（键矩形），`position({ right, bottom })`（官方 Edges 形式，API 12+）
//     绝对定位——键以外区域**完全不覆盖**，列表触摸不会与悬浮层相遇，滚动零死区。
//   - ★ 改判根因（真机实锤「点键时背后会话卡仍暗一下」）：旧满高容器 +
//     `HitTestMode.Transparent` 官方语义是「不阻塞兄弟节点」——同位会话卡会一起进触摸测试，
//     收到 DOWN 就亮蒙层。局部容器用默认命中（Default 自身响应并阻塞兄弟）从机制上消除。
//   - 容器自身挂空 onClick 消费键区内点击（坑96 同款）；键本体 Button 深层识别器优先响应。
// · 形制：
//   - 圆形键 56×56 `ButtonType.Circle`（官方圆钮类型，零自绘 borderRadius——规范《行内按钮
//     与光感》§1 禁自绘红线；56 = HdsTabs 悬浮页签胶囊高，不自造第二套）。
//   - 淡彩次级键配色（决明「键颜色用项目规范的淡蓝色」）：tinted 族四件（fallbackButton*
//     Tinted——规范 §1 四档阶梯「推进型动作」档，新建会话非卡内收口故不入 primary 强调蓝）。
//     ★ 恒传 `true` 走实底、**不订阅** IMMERSIVE_LEVEL_KEY / CONTENT_FALLBACK_KEY：实底分支
//     不消费档位与能力位，订阅即死订阅；能力位若被写成 false 会走进「内容区材质生效性未
//     真机验证」的试验路径。
// · 位置（布局属性驱动，命中跟随）：`position.right` 数值——右位 = 16；左位 = 内容区实宽 −
//   键宽 − 16，由 `animateTo` 驱动插值（布局属性可动画；`offset`/`translate` 只改绘制、会让
//   视觉与命中错位，禁用）。内容区实宽由宿主 onAreaChange 实测下行（`contentWidth`）；
//   未测得（首帧）或容器过窄 → 回右位基值，不出现负边距。
// · 握姿跟随（官方 @ohos.multimodalAwareness.motion，d.ts since 20 ≤ 基线 26）：
//   - `canIUse('SystemCapability.MultimodalAwareness.Motion')` 通过才订阅（手机专属；
//     平板/无传感器设备恒右）。
//   - `motion.on('holdingHandChanged', cb)` → LEFT_HAND_HELD 靠左 / RIGHT_HAND_HELD 靠右 /
//     BOTH_HANDS_HELD·NOT_HELD·UNKNOWN_STATUS 保持当前位（默认右，禁跳变）；事件名与枚举
//     成员逐字按 d.ts，禁抽常量（断言按字面量 grep）。
//   - 偏好开关 `prefHoldingFollow` 默认开；关闭 = 恒右且不响应握姿事件（回调首行早退），
//     拨关瞬间若在左位则动画归右。订阅不随开关挂摘（免第二条寿命轴与重复 off）。
//   - 订阅寿命 = 组件生命周期（拍板 A 案）：本页活在 TabContent 里跨页签不销毁，切页签时
//     订阅仍在——真机耗电观察项入 BLOCKED，有可测差异再改；不提前加第二条寿命轴
//    （性能不许愿红线）。
//   - 异常：201 权限拒绝 / 801 设备不支持 / 3150000x 服务异常一律 try/catch 恒右兜底；
//     `off` 传与 `on` 同一具名引用（d.ts：不传 callback 会摘掉该事件全部监听）。
// · 几何（vp）：bottom = barBottom + FAB_ABOVE_BAR_GAP = （navBarHeight + 16）+ 56 =
//   navBarHeight + 72 = 页签胶囊顶边之上 16 呼吸；真机微调位，单点改动须同步断言。
// · 显隐：多选态由宿主传 hide（Visibility.None 隐藏但组件常驻）——不用条件渲染，因为条件
//   渲染会销毁组件、丢左右位并重新订阅，退出多选会跳回右侧。
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  fallbackButtonBgTinted,
  fallbackButtonFontTinted,
  fallbackButtonMaterialTinted,
  fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { PREF_HOLDING_FOLLOW_KEY } from '../../common/AppPreferences';

// ── 几何常量（消费方渲染与断言同源；vp）──
export const FAB_SIZE: number = 56;
export const FAB_ICON_SIZE: number = 24;
export const FAB_EDGE_GAP: number = 16;
export const FAB_ABOVE_BAR_GAP: number = 56;
export const FAB_SIDE_ANIM_MS: number = 300;

@Component
export struct SessionNewFab {
  // 多选态隐藏（宿主传 selectMode）：走 Visibility 而非条件渲染，保留左右位与订阅
  @Prop hide: boolean = false;
  // 批量条距屏底（vp，宿主下发 navBarHeight + 16）；bottom = 本值 + FAB_ABOVE_BAR_GAP
  @Prop barBottom: number = 96;
  // 内容区实宽（vp，宿主根容器 onAreaChange 下行）——左位 position.right 的分母；
  // 0 = 未测得 → 维持右侧基位
  @Prop contentWidth: number = 0;
  // 智感握姿跟随开关（偏好设置 · 会话与阅读组）：默认开；关 = 恒右不跟随。
  // @StorageProp 自订阅（切换即刷）+ @Watch 处理「拨关瞬间归右」
  @StorageProp(PREF_HOLDING_FOLLOW_KEY) @Watch('onFollowSwitchChanged') holdingFollow: boolean = true;
  // 点击上行（与标题栏「＋」同一 newConversation 链，禁在本件或宿主复制 push 逻辑）
  onTap: () => void = (): void => {
  };

  // 握姿侧（true = 左手位）。@State 驱动 position；事件值不变时不动，防握姿抖动反复动画
  @State private holdingLeft: boolean = false;
  // 订阅在场（状态最小化）——off 幂等守卫
  private subscribed: boolean = false;
  // 销毁守卫：卸载后迟到的传感器回调不碰 UI
  private departed: boolean = false;

  // 具名回调引用（on/off 必须同一引用——d.ts off 不传 callback 会摘全部监听）
  private readonly holdingHandler: (status: motion.HoldingHandStatus) => void =
    (status: motion.HoldingHandStatus): void => {
      this.applyHoldingStatus(status);
    };

  aboutToAppear(): void {
    this.departed = false;
    this.subscribeHolding();
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.unsubscribeHolding();
  }

  // 订阅握姿（能力不支持/权限拒绝/服务异常一律静默恒右——功能降级不阻断新建入口）
  private subscribeHolding(): void {
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      return;
    }
    try {
      motion.on('holdingHandChanged', this.holdingHandler);
      this.subscribed = true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(0xD5A1, 'SessionNewFab',
        'subscribe holdingHandChanged failed: %{public}d %{public}s', error.code, error.message);
    }
  }

  // 退订（与 subscribeHolding 成对；失败也置 false，避免卸载路径重复 off）
  private unsubscribeHolding(): void {
    if (!this.subscribed) {
      return;
    }
    try {
      motion.off('holdingHandChanged', this.holdingHandler);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(0xD5A1, 'SessionNewFab',
        'unsubscribe holdingHandChanged failed: %{public}d %{public}s', error.code, error.message);
    }
    this.subscribed = false;
  }

  // 握姿 → 侧位（三种「不指向某一侧」的状态保持当前位：双手/未握持/未知，禁跳变；
  // 开关关闭时首行早退 = 恒右）
  private applyHoldingStatus(status: motion.HoldingHandStatus): void {
    if (this.departed || !this.holdingFollow) {
      return;
    }
    let nextLeft: boolean = this.holdingLeft;
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      nextLeft = true;
    } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      nextLeft = false;
    } else {
      return;
    }
    if (nextLeft === this.holdingLeft) {
      return;
    }
    // UIContext 版 animateTo（禁全局 animateTo）：只包状态赋值，position 值由 build 重算
    this.getUIContext().animateTo({ duration: FAB_SIDE_ANIM_MS, curve: Curve.EaseOut },
      (): void => {
        this.holdingLeft = nextLeft;
      });
  }

  // 开关拨关 → 当前在左位则动画归右（拨开不回位：保持用户当前所见，等下一次握姿事件）
  private onFollowSwitchChanged(): void {
    if (this.holdingFollow || !this.holdingLeft || this.departed) {
      return;
    }
    this.getUIContext().animateTo({ duration: FAB_SIDE_ANIM_MS, curve: Curve.EaseOut },
      (): void => {
        this.holdingLeft = false;
      });
  }

  // 右缘距离（vp）：右位 = 16；左位 = 内容区实宽 − 键宽 − 16；宽度未测得或过窄 → 回右位基值
  private fabRightInset(): number {
    if (!this.holdingLeft || this.contentWidth <= 0) {
      return FAB_EDGE_GAP;
    }
    const travel: number = this.contentWidth - FAB_SIZE - FAB_EDGE_GAP;
    return travel > FAB_EDGE_GAP ? travel : FAB_EDGE_GAP;
  }

  build() {
    // 局部容器：只占键矩形 + 绝对定位——键外零覆盖、滚动零死区（口径见文件头「形态」）
    Stack() {
      Button() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(FAB_ICON_SIZE)
          .fontColor([fallbackButtonFontTinted(true)])
      }
      .type(ButtonType.Circle)
      .width(FAB_SIZE)
      .height(FAB_SIZE)
      .padding(0)
      // 淡彩次级键四件（规范 §1 四档「推进型动作」档；恒实底口径见文件头「形制」）
      .backgroundColor(fallbackButtonBgTinted(true, 0))
      .systemMaterial(fallbackButtonMaterialTinted(true, 0))
      .stateEffect(fallbackButtonStateEffect(true, 0))
      .accessibilityText('新建会话')
      .onClick((): void => {
        this.onTap();
      })
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    // 绝对定位（Edges 形式，API 12+）：底边 = 批量条距底 + 56（页签胶囊顶边之上 16 呼吸）
    .position({ right: this.fabRightInset(), bottom: this.barBottom + FAB_ABOVE_BAR_GAP })
    // 空 onClick：消费键矩形内点击并阻断下层卡片命中（坑96 同款；子键深层优先响应）
    .onClick((): void => {
      // 空实现
    })
    .accessibilityLevel('no')
    // 多选态隐藏（组件常驻：保留左右位与订阅，见文件头「显隐」）
    .visibility(this.hide ? Visibility.None : Visibility.Visible)
  }
}
