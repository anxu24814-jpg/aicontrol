// 页面背景统一入口（2026-08-20 建立，一级/二级页面共用；2026-08-21 改共享位图缓存——
// 见坑36：原各页面 Image 直接加载 file:// URI，二级页/三级页首次挂载时异步加载，官方
// push 转场滑入期间露出浅色兜底 → 闪白；现改为 common/BgCache.ets 的全局唯一 PixelMap
// 缓存（一级页显示时即解码，二级页挂载同步命中零延迟），本组件仅负责「取缓存 + 显示」）：
// 自定义背景图把图片资源/URI 写入 AppStorage['pageBg'] 后，所有已接入本组件的页面
// 自动跟随切换（@StorageProp 响应式 + @Watch 触发缓存拉取）；值为空字符串 = 默认官方
// 页面底色（page_bg 资源，深浅色自动切换）。
// ★ solid 例外（2026-08-21 决明要求）：仅「编辑图片」两页（裁剪 ImageEditPage / 调整
// ImageAdjustPage）传 solid=true 强制纯色——背景编辑预览框（裁剪框/模糊预览）叠在
// 壁纸上看不清，这两页不显示自定义背景；其余页面保持壁纸。solid 时跳过缓存拉取
// （不消费 BgCache，也无谓解码），恒走纯色分支（深浅色自动）。
// 接入方式：页面根内容区最底层放 <PageBackground />（Stack 首个子组件），卡片/标题栏/
// 悬浮页签均在其上层，层级天然正确；页面根组件（NavDestination）backgroundColor 为透明
// （2026-08-21 坑38：系统转场圆角处若设 page_bg 浅色实体背景会露白边，透明后透出下层
// 共享背景深色）——页面不透明度由 PageBackground 自身保证（铺满 + 纯色分支与页面兜底
// 一致），转场滑入时页面实体不透明。
// 注：自定义背景图生效后，标题栏 GRADIENT_BLUR 模糊蒙层与悬浮页签光感材质会采样到背景图，
// 观感需真机验证（见 docs/变更记录.md 2026-08-20 勘误条）。
// ★ 背景仅用于会话页（2026-09-05 开关新功能）：sessionPage 参数标记本实例是否为会话页
// 背景（ChatPage 经 PageShell 传 true，其余挂载点默认 false）。开关 PREF_BG_SESSION_ONLY_KEY
// 开启时，非会话页实例显示纯色兜底——**显示抑制但缓存维护**（第二轮自检 N1/N2 修复后
// 语义）：抑制实例仍 ensure 当前 pageBg 解码进共享缓存（冷启动/换图后进会话页同步命中
// 零跳变，坑36 承诺在任何开关态成立）并在恢复默认时清空缓存（防滞留）——BgCache 恒与
// 当前 pageBg 对齐，换图/恢复默认链路与开关无关。
// ★ O1 修复（2026-09-05 第三轮，坑25 实证——@StorageProp 在 NavDestination 栈下层内容
//   组件上订阅不可靠，pop 回旧实例不刷新）：①开关判定一律**现读** AppStorage
//   （@StorageProp bgSessionOnly 仅作变化信号，值冻结也不影响判定正确性）；②页面显示
//   时自刷——页面壳（PageShell / PageMapBuilder 原生壳分支）在官方 onShown 里调用
//   bumpBgShownEpoch()（每次页面显示触发，含 pop 返回，坑25 定稿可靠姿势），本组件
//   订阅纪元键 @Watch → load 重判。一级页（Navigation 根组件）无需——根组件订阅正常
//   （坑25 实证差异 = 根组件 vs NavDestination 内容组件）。
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { bgFileNameFromUri } from './ImageEditUtil';
import { ensureBgPixelMap, getBgPixelMap, getFallbackBgPixelMap } from './BgCache';
import { PREF_BG_SESSION_ONLY_KEY } from './AppPreferences';

// 页面显示纪元键（O1 修复：页面显示时自 bump——页面壳 onShown 调用 bumpBgShownEpoch，
// 本组件 @Watch → load。不是跨页广播 tick（规范黑名单实证不触发）：触发者 = 页面自己
// 显示时，此刻页面在渲染树，订阅可靠；栈下层实例的 @Watch 不触发无妨——不可见）
const BG_SHOWN_EPOCH_KEY: string = 'bgShownEpoch';

// 页面显示时自刷入口（PageShell 与 PageMapBuilder 原生壳 onShown 调用；一级页无需）
export function bumpBgShownEpoch(): void {
  AppStorage.setOrCreate<number>(BG_SHOWN_EPOCH_KEY, (AppStorage.get<number>(BG_SHOWN_EPOCH_KEY) ?? 0) + 1);
}

@Component
export struct PageBackground {
  // 自定义背景图（资源名/路径/URI 字符串）；空 = 默认纯色背景。@Watch：值变化（换图/
  // 恢复默认）时重新拉取缓存——@StorageProp 相同字符串不触发（坑34 已由唯一名 URI 规避）
  @StorageProp('pageBg') @Watch('onAnySignalChanged') pageBg: string = '';
  // 背景仅用于会话页开关（2026-09-05 新增订阅）：**仅作变化信号**（@Watch 触发 load 重判）
  // ——判定一律现读 AppStorage（O1 修复：栈下层值冻结不影响正确性）
  @StorageProp(PREF_BG_SESSION_ONLY_KEY) @Watch('onAnySignalChanged') bgSessionOnly: boolean = false;
  // 页面显示纪元（O1 修复：页面 onShown 时自 bump，本实例 @Watch → load 重判——pop 回
  // 旧实例时开关态现读纠正）
  @StorageProp(BG_SHOWN_EPOCH_KEY) @Watch('onShownEpoch') shownEpoch: number = 0;
  // 当前显示位图（引用 BgCache 共享缓存，不持有释放权——释放由缓存管理，见 BgCache.ets）；
  // null = 解码中/无背景，显示纯色兜底；驱动 UI 用 @State
  @State bgPm: image.PixelMap | null = null;
  // 强制纯色例外开关（2026-08-21：仅编辑图片两页传 true，预览框叠壁纸看不清——见头注释）。
  // 创建时固定、生命周期内不变，用普通成员（不驱动 UI，build 直接读）
  solid: boolean = false;
  // 会话页背景标记（2026-09-05 背景仅用于会话页开关配套）：true = 本实例是会话页背景，
  // 不受开关抑制。创建时固定、生命周期内不变，用普通成员（不驱动 UI，build 直接读）
  sessionPage: boolean = false;
  // 拉取序号：防乱序（连续换图时只采纳最新一次解码结果，先例 ImageEditPage blurSeq）
  private loadSeq: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  // 任一信号变化（pageBg 换图/恢复默认 或 开关切换）→ load 重判（回调名 2026-09-05 第三轮
  // 自检更名：原 onPageBgChanged 仅指换图，现双键共用，语义对齐）
  onAnySignalChanged(): void {
    this.load();
  }

  onShownEpoch(): void {
    this.load();
  }

  // 开关键现读（O1 修复：@StorageProp 值在栈下层冻结不可靠，判定一律读 AppStorage）
  private bgOnlyNow(): boolean {
    return AppStorage.get<boolean>(PREF_BG_SESSION_ONLY_KEY) === true;
  }

  // 本实例是否抑制自定义背景显示：强制纯色例外（编辑图片两页）或「背景仅用于会话页」
  // 开关开启且本页非会话页。抑制 = 不显示背景图——但仍维护 BgCache（预热 + 恢复默认
  // 清空，见 load），保证缓存恒与当前 pageBg 对齐（第二轮自检 N1/N2 修复后语义）
  private suppressCustomBg(): boolean {
    return this.solid || (this.bgOnlyNow() && !this.sessionPage);
  }

  // 拉取当前背景位图：同步命中缓存直接显示；未命中触发缓存解码，完成后按序号采纳。
  // 换图瞬间 bgPm 保持旧图（先旧后新，无纯色闪变）；恢复默认先同步置空（数据切换后
  // 缓存侧才清空，安全窗口见 BgCache.ets 头注释）
  private load(): void {
    // solid 例外页（编辑图片两页）：恒纯色、不消费也不预热 BgCache（预览框叠壁纸看不清，
    // 且一级页/前序页已预热缓存，此处跳过解码无谓消耗）；loadSeq 递增作废在途回填
    if (this.solid) {
      this.loadSeq++;
      this.bgPm = null;
      return;
    }
    const seq: number = ++this.loadSeq;
    const uri: string = this.pageBg;
    if (uri.length === 0) {
      // 无背景：清空缓存（旧图移入延迟释放，见 BgCache.ets）。所有非 solid 实例通用，
      // 含开关抑制实例——抑制态恢复默认若不在此清缓存，缓存会滞留旧图到下次换图
      //（第二轮自检 N2 修复）
      this.bgPm = null;
      ensureBgPixelMap(''); // 清空缓存（旧图移入延迟释放，见 BgCache.ets）
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      // 禁止静默失败（P0-1）：极端场景回纯色但必须留日志（先例 ImageEditPage）
      console.error('page background load failed: host context unavailable');
      this.bgPm = null;
      return;
    }
    // 沙箱纯路径：file:// URI 剥前缀是非法相对路径（坑31），须提取文件名拼目录
    const path: string = context.filesDir + '/' + bgFileNameFromUri(uri);
    if (this.bgOnlyNow() && !this.sessionPage) {
      // 开关抑制实例：不显示背景（恒走 build 纯色分支），但仍 ensure 维护缓存——
      // 缓存恒与当前 pageBg 对齐：冷启动/换图后进会话页同步命中零跳变（坑36 承诺在
      // 任何开关态成立，第二轮自检 N1 修复）；在途回填已被上方 seq 递增作废，不持有显示。
      // 判定现读（bgOnlyNow，O1 修复）：@StorageProp 值栈下层冻结不影响
      ensureBgPixelMap(path);
      this.bgPm = null;
      return;
    }
    const hit: image.PixelMap | null = getBgPixelMap(path);
    if (hit !== null) {
      this.bgPm = hit;
      return;
    }
    // 新图解码中（换壁纸后立即进页/页面重建）：先显示换图窗口的旧图兜底（prevPm，
    // 2026-08-21 残量修复）——首帧/转场不露纯色闪白，解码完成后经 ensure 切新图；
    // 无旧图（首次冷启动）则保持纯色兜底，由下方 ensure 完成后切换。
    // 守卫（2026-08-22 审查修复）：仅在「当前无图可显」（bgPm === null，新页面首帧）
    // 才用 prevPm 兜底——无条件覆盖会把正在显示的正确图回退成两代之前的旧图
    // （调整页保存未预热缓存路径必现：换图瞬间显示上上一张，解码完成才跳新图；
    // 换图解码失败路径则永久停在旧图）
    const fallback: image.PixelMap | null = getFallbackBgPixelMap();
    if (fallback !== null && this.bgPm === null) {
      this.bgPm = fallback;
    }
    ensureBgPixelMap(path).then((pm: image.PixelMap | null) => {
      if (seq === this.loadSeq) {
        this.bgPm = pm;
      }
    });
  }

  build() {
    if (!this.suppressCustomBg() && this.bgPm !== null) {
      // 自定义背景图：等比覆盖铺满（裁切多余部分），深浅色模式同一张图；
      // src 为共享缓存 PixelMap（非 URI——零加载延迟，转场不闪，坑36 修复）
      Image(this.bgPm)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else {
      // 默认页面底色：page_bg 资源（base #F1F3F5 / dark #121212），深浅色自动。
      // ★ 2026-08-21 官方化查证结论（勿再改 sys.color）：① sys.color.background 不存在
      // （编译 Unknown resource，项目 2026-08-20 旧注释有误）；② 官方 background_primary
      // = 浅白/深黑（resources.txt 125831061 → white/black），纯白底会回归「白底白卡
      // 无区分」（2026-08-20 决明否决过）；③ 官方 sub_background 浅色恰为 #F1F3F5
      // （ohos_id_color_sub_background = #fff1f3f5）但简名不在 sysResource 清单、深色为
      // 纯黑 #000000（与定稿 #121212 不一致）——故页面背景保持 app 资源（浅色值与官方
      // 一致），输入框/卡片等元素底色才走官方 comp_background_* 叠色体系
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
    }
  }
}
