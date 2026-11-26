// 二级页公共骨架：官方 HDS NavDestination 唯一路径 + PageBackground 背景层 + 页面根透明
// 背景（坑38：系统转场圆角处透出下层共享背景，不露实色白边）+ 官方标题栏（含菜单可选）。
// 新增二级页 = PageShell({ title, content }) 一行接入（内容经 @BuilderParam 传入），
// 背景/透明背景/标题栏规格结构性保证，无需逐页复制。
// 参数契约：
// - title 主标题（@Prop，见成员注释）；titleSize 标题字号档（二级页统一 TITLE_S）；
// - menuHds HDS 菜单（hdsTitleBarOptions 第 5 参原样传，null = 无）；
// - titleBarStack 标题栏覆盖层（可选）+ keepStackTitle 覆盖层下是否保留主标题
//   （可选，默认 false）——细则见各自成员注释；
// - onShown / onWillDisappear / onBackPressed 生命周期与返回拦截回调（均透传）；
// - titleBarBottom 标题栏下方带（可选）+ titleBarBottomInset 带内下移量（默认 8）
//   + titleBarBottomHeight 带内容高（默认 40 单行档）；
// - content 页面内容（topPad/滚动自行处理，纯展示 + 回调；页面差异集中在此）；
// - 沉浸光感档位本组件 @StorageProp 自订阅，免逐页透传。
import { BottomBuilderParams, DynamicHideParams, HdsNavigationMenuContentOptions,
  HdsNavDestination, HideMode, TitleSize } from '@kit.UIDesignKit';
import {
  hdsTitleBarOptions,
  IMMERSIVE_LEVEL_KEY,
  segmentBandParams
} from './ImmersiveLevel';
import { PageBackground, bumpBgShownEpoch } from './PageBackground';
import { notifyBgChanged } from './BgRefreshBus';
import { SEGMENT_BAR_BAND_TOP_INSET, SEGMENT_BAR_HEIGHT } from './Theme';

@Component
export struct PageShell {
  // 主标题（官方标题栏；hdsTitleBarOptions 参数为 string）。
  // ★ @Prop（原普通成员，坑16 家族）：查看器标题须随页更新（滑到第二张图标题跟着变），而
  // 普通成员构造期定值、父页 @State 变化不传导。@Prop 单向同步：父页状态变 → 传值更新 →
  // 本壳重渲染；其余消费方传值参不变即零行为影响
  @Prop title: string = '';
  // 标题字号档：二级页统一 TITLE_S（介于一级页主标题与内容文字之间）
  titleSize: TitleSize = TitleSize.TITLE_S;
  // 标题栏 HDS 菜单（可选；hdsTitleBarOptions 第 5 参原样传，null = 无菜单）
  menuHds: HdsNavigationMenuContentOptions | null = null;
  // 页面显示生命周期回调（可选，透传 onShown——@StorageProp 在栈下层不刷新的替代姿势）
  onShown: () => void = () => {
  };
  // 页面即将消失/转场回调（可选，透传 onWillDisappear——官方钩子语义「即将卸载或转场
  // 动画即将开始时」触发；ChatPage 转场前静默接线用；解冻不走本钩子——回显/取消路径由
  // onShown 承接）
  onWillDisappear: () => void = () => {
  };
  // 返回键拦截回调（可选，坑17：「完成返回即刷新」的页面——排序页等无保存动作场景——用
  // onBackPressed 拦截官方返回链后 pop({ saved: true }) 触发父页 onPop；缺省 false 官方
  // 行为不变）
  onBackPressed: () => boolean = (): boolean => false;
  // 隐藏官方返回键（可选；默认 false 官方行为不变）。★ 侧栏会话二级页 2237 专用：返回动作
  // 自绘进标题栏覆盖层最右热区（TitleBarQuadCapsule），官方返回键不再占位——隐藏后覆盖层
  // 整栏接管、左避让收归 16。透传 HdsNavDestination.hideBackButton（官方 API 18+）；参数名
  // 刻意不叫 hideBackButton——组 3 负向钉扫侧栏页源码里该字面串（防 2235-b 自造壳回潮），
  // 本参落在 PageShell 壳内、消费方只传布尔，两下不相撞。
  backKeyHidden: boolean = false;
  // 背景强制纯色例外（「编辑图片」两页与待发图片裁剪页 true——预览框叠壁纸看不清，
  // 见 PageBackground.ets；默认 false 跟随自定义壁纸）
  bgSolid: boolean = false;
  // 会话页背景标记（「背景仅用于会话页」开关配套）：true = 开关开启时仍显示自定义背景
  //（仅 ChatPage 传 true；二级页均非会话页，默认 false）
  bgSessionPage: boolean = false;
  // 标题栏自定义覆盖层（可选）：整栏覆盖标题栏上方，搜索页用它把搜索框嵌入标题栏与返回键
  // 并排（须自行避让返回键；传入后主标题自动置空，见 ImmersiveLevel hdsTitleBarOptions）。
  // 类型用 CustomBuilder 普通
  // 参数而非 @BuilderParam：该函数原样交给官方 titleBar 选项（官方示例同款），不在本组件
  // build 里当 UI 插槽调用
  titleBarStack: CustomBuilder | null = null;
  // 覆盖层下保留主标题（可选，透传 hdsTitleBarOptions 的 keepStackTitle；默认 false =
  // 覆盖层存在即置空主标题）。现役消费方三处 = 记忆页 / 技能库页 / 附件查看器页（三页覆盖层
  // 都只占标题栏右侧，主标题须照常显示——附件查看器页主标题「当前页文件名」随页更新）
  keepStackTitle: boolean = false;
  // 标题栏下方自定义区（可选，官方 bottomBuilder 整带）：本项目用途 = 承载页顶吸顶分段胶囊
  // 与三库页搜索框（SearchTopBand；内容区件在 API 26 不出材质，迁入即恢复沉浸光感）。
  // builder 必须是组件内 @Builder（坑30：全局 @Builder 被官方 napi 直接调用无视图上下文）；
  // 内容须自行做水平居中与带内下移——**带顶 = 标题栏下沿，不是 topPad**（topPad 含蒙层下延
  // 16vp，见 Theme SEGMENT_BAR_BAND_TOP_INSET 注释）
  titleBarBottom: CustomBuilder | null = null;
  // 带内胶囊下移量（vp；默认 8 = 页顶胶囊现状位置：带顶 + 8 ≡ 各页原 `topPad − 8`）。带高按
  // 本值 + 内容高自动算（用量/费用统计两页传 SEGMENT_BAR_BAND_TOP_INSET_STATS = 16 保现状）
  titleBarBottomInset: number = SEGMENT_BAR_BAND_TOP_INSET;
  // 带内容高（vp；默认 40 = 单行分段胶囊背板高）。两行档（面包屑 + 分段胶囊）传
  // WORKSPACE_BAND_CONTENT_HEIGHT（88 = 40 + 8 + 40），带高 = titleBarBottomInset + 本值；
  // 静态构造期定值，既有消费方不传即原算式零变化
  titleBarBottomHeight: number = SEGMENT_BAR_HEIGHT;
  // 带隐藏开关（true = 本帧不挂带，标题栏重建后带收起）。★ 必须 @Prop——运行期状态驱动的
  // 收起，titleBarBottom 是普通成员、父页重渲染不回写（@Prop title 同款结论）；默认 false
  // 常显（首用 = 提示词库多选态）
  @Prop titleBarBottomHidden: boolean = false;
  // 标题栏下方带滚动联动（可选，A 档接收带——规范-搜索交互 §6）：传入本页滚动控制器即开
  // 官方 dynamicHideTitleBar 收带 + bindToScrollable 感知；收带阈值 = 带高（inset + 内容高，
  // 与带参数同源现读）。null = 不收带（B 档常显，二级页默认）；静态构造期定值，无需状态通道
  titleBarBottomScroller: Scroller | null = null;
  // 页面内容（Slot）：纯展示 + 回调上行；topPad/滚动由内容自行处理
  @BuilderParam content: () => void;
  // 沉浸光感档位（AppStorage 自订阅：标题栏材质/返回键圆底/菜单按钮圆底统一驱动，
  // 免逐页透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // 标题栏下方带参数（未传 builder 或置隐藏开关 ⇒ undefined = 不写该区）；带高算式与
  // showType 单源 = ImmersiveLevel.segmentBandParams（下移 8 ⇒ 48、16 ⇒ 56；两行档
  // contentHeight 88 ⇒ 96——见 titleBarBottomHeight 成员注释）
  private bandParams(): BottomBuilderParams | undefined {
    if (this.titleBarBottomHidden || this.titleBarBottom === null) {
      return undefined;
    }
    return segmentBandParams(this.titleBarBottom, this.titleBarBottomInset,
      this.titleBarBottomHeight);
  }

  // 标题栏下方带官方滚动联动参数（A 档）：未传滚动控制器 = 全默认不收带；传入 = 只收带区
  //（标题与返回键不动），阈值 = 本带高（inset + 内容高，与 bandParams 同两源现读）
  private bandHideParams(): DynamicHideParams {
    if (this.titleBarBottomScroller === null) {
      return { hideBottomBuilder: false };
    }
    return {
      hideBottomBuilder: true,
      mode: HideMode.SCROLL_UP_TO,
      hideOffset: this.titleBarBottomInset + this.titleBarBottomHeight
    };
  }

  build() {
    HdsNavDestination() {
      // Stack 背景层垫底（统一页面背景，见 PageBackground.ets；自定义背景写入
      // AppStorage['pageBg'] 后全二级页自动跟随，位图缓存见 BgCache.ets）
      Stack() {
        PageBackground({ solid: this.bgSolid, sessionPage: this.bgSessionPage })
        this.content()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // 页面根背景透明（坑38）：系统转场圆角处透出下层共享背景，不露实色白边；
    // 不透明度由 PageBackground 铺满 + 纯色分支兜底保证
    .backgroundColor(Color.Transparent)
    // 官方 HDS 标题栏：返回按钮（栈非空自动显示）+ 渐变模糊 + 光感材质（参数含义与定稿见
    // ImmersiveLevel.ets hdsTitleBarOptions；覆盖层下保留主标题经同名参透传，未传 = 默认置空）
    .titleBar(hdsTitleBarOptions(this.title, this.immersiveLevel, this.titleSize,
      this.menuHds !== null ? this.menuHds : undefined,
      this.titleBarStack !== null ? this.titleBarStack : undefined, this.keepStackTitle,
      this.bandParams()))
    // 官方滚动联动（A 档接收带页才生效；未传控制器 = dynamicHide 全默认 + 绑定空数组空转，
    // 与 HomeNavigation「壳上恒挂、非设置页签无感知源」同口径——拆条件链会复制整段壳，不做）
    .dynamicHideTitleBar(this.bandHideParams())
    .bindToScrollable(this.titleBarBottomScroller !== null ? [this.titleBarBottomScroller] : [])
    // 页面显示生命周期（透传）+ 背景显示自刷：每次页面显示 bump 纪元键（坑25 定稿「onShown
    // 是可靠姿势，每次页面显示触发，含 pop 返回」）；直达补刷——显示时刻的补刷不走
    // epoch @Watch（该实例可能已冻结，坑16/坑25 族，不赌本实例订阅面存活），bump 保留
    //（次通道 + BackgroundPanel 预览既有 epoch 订阅面仍消费）
    .onShown(() => {
      bumpBgShownEpoch();
      notifyBgChanged();
      this.onShown();
    })
    // 转场前静默（透传）
    .onWillDisappear(() => {
      this.onWillDisappear();
    })
    // 返回键拦截（透传；坑17——完成返回即刷新的页面用，缺省 false 官方行为不变）
    .onBackPressed(() => {
      return this.onBackPressed();
    })
    // 官方返回键隐藏（侧栏二级页自绘四键胶囊场景；默认 false 零行为变化）
    .hideBackButton(this.backKeyHidden)
  }
}
