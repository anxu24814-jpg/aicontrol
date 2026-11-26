// 页面背景统一入口（一级/二级页面共用）：自定义背景图写入 AppStorage['pageBg'] 后，所有
// 已接入本组件的页面自动跟随切换（@StorageProp 响应式 + @Watch 触发缓存拉取）；值为空
// 字符串 = 默认官方页面底色（page_bg 资源，深浅色自动）。
// · 缓存（坑36）：共享位图缓存 common/BgCache.ets 全局唯一 PixelMap（一级页显示时即解码，
//   二级页挂载同步命中零延迟——防 push 转场滑入期闪白），本组件只负责「取缓存 + 显示」。
// · ★ solid 例外（决明要求）：仅「编辑图片」两页（裁剪/调整）传 solid=true 强制纯色——
//   背景编辑预览框叠壁纸看不清；solid 时跳过缓存拉取（不消费 BgCache），恒走纯色分支。
// · 接入方式：页面根内容区最底层放 <PageBackground />（Stack 首个子组件）；页面根
//   NavDestination backgroundColor 须透明（坑38——转场圆角处实体浅色背景会露白边），
//   页面不透明度由 PageBackground 铺满保证。标题栏模糊蒙层与悬浮页签光感会采样背景图，
//   观感需真机验证。
// · 「背景仅用于会话页」开关（PREF_BG_SESSION_ONLY_KEY，sessionPage 标记本实例）：开启时
//   非会话页实例显示纯色兜底——**显示抑制但缓存维护**（BgCache 恒与当前 pageBg 对齐，
//   坑36 承诺在任何开关态成立）。
// · ★ O1 修复（坑25 实证——@StorageProp 在 NavDestination 栈下层内容组件上订阅不可靠，
//   pop 回旧实例不刷新）：①开关判定与 uri 取值一律**现读** AppStorage（@StorageProp 仅作
//   变化信号，值冻结不污染判定——换图写点在栈顶编辑链，栈下层读字段会拿旧 uri 跑全链：
//   误清刚预热的新图缓存 / 解码已删文件失败回纯色）；②页面壳（PageShell /
//   PageMapBuilder 原生壳分支）在官方 onShown 里 bumpBgShownEpoch()（含 pop 返回的可靠
//   姿势），本组件订阅纪元键 @Watch → load 重判；一级页（Navigation 根组件）无需。
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ensureBgPixelMap, getBgPixelMap, getFallbackBgPixelMap, bgCachePathFor } from './BgCache';
import { registerBgRefreshListener, unregisterBgRefreshListener } from './BgRefreshBus';
import { PREF_BG_SESSION_ONLY_KEY } from './AppPreferences';

// 页面显示纪元键（页面壳 onShown 自 bump，本组件 @Watch → load。非跨页广播 tick：触发者
// = 页面自己显示时，此刻页面在渲染树、订阅可靠；栈下层实例不触发无妨——不可见）。导出供
// BackgroundPanel 背景预览同源订阅（pop 返回时 @StorageProp 在栈下层可能冻结，预览须靠本
// 纪元重读 AppStorage）
export const BG_SHOWN_EPOCH_KEY: string = 'bgShownEpoch';

// 页面显示时自刷入口（PageShell 与 PageMapBuilder 原生壳 onShown 调用；一级页无需）
export function bumpBgShownEpoch(): void {
  AppStorage.setOrCreate<number>(BG_SHOWN_EPOCH_KEY, (AppStorage.get<number>(BG_SHOWN_EPOCH_KEY) ?? 0) + 1);
}

@Component
export struct PageBackground {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图
  // 照常完成
  private departed: boolean = false;
  // 直达刷新回调：**成员初始化式箭头函数**——身份恒定，注销可对位（★ 禁改 .bind(this)
  // 注册：每次 bind 产生新函数身份 = 注销失位泄漏，见 BgRefreshBus.ets 头注释）；departed
  // 双保险（销毁后迟到通知不写状态）
  private onBgDirectRefresh: () => void = () => {
    if (!this.departed) {
      this.load();
    }
  };
  // 自定义背景图；空 = 默认纯色背景。仅作变化信号（值变化时重新拉取缓存——相同字符串
  // 不触发，坑34 已由唯一名 URI 规避），取值一律现读 AppStorage（栈下层值冻结不污染判定）
  @StorageProp('pageBg') @Watch('onAnySignalChanged') pageBg: string = '';
  // 「背景仅用于会话页」开关：仅作变化信号（@Watch 触发 load 重判），判定一律现读
  // AppStorage（栈下层值冻结不影响正确性）
  @StorageProp(PREF_BG_SESSION_ONLY_KEY) @Watch('onAnySignalChanged') bgSessionOnly: boolean = false;
  // 页面显示纪元（onShown 自 bump，本实例 @Watch → load 重判——pop 回旧实例时开关态现读纠正）
  @StorageProp(BG_SHOWN_EPOCH_KEY) @Watch('onShownEpoch') shownEpoch: number = 0;
  // 本实例已收到显示纪元事件的私标（★ 勿改判 shownEpoch > 0——那是全局纪元值，会话页挂载
  // 时来源页早已 bump 过、恒 > 0，兜底分支恒真 = 错峰失效；私标只由本实例 @Watch 置位，
  // 才能表达「纪元事件已到达本实例」）
  private shellArrived: boolean = false;
  // 当前显示位图（引 BgCache 共享缓存，不持有释放权——释放由缓存管理）；null = 解码中/
  // 无背景，显示纯色兜底
  @State bgPm: image.PixelMap | null = null;
  // 壁纸首帧淡入完成位（决明拍板：会话页 + 一级页签〔homeTab〕实例播渐显，二级页维持
  // 直显——每进一个二级页都渐显一遍会很烦）：false = 壁纸未首显（opacity 0 露底色）。
  // 会话页实例经 onShownEpoch 置位错峰（决明拍板「错峰+300ms」，见 onShownEpoch 注释），
  // onAppear 兜底 + 非会话页实例挂载即置，双写点保「置位必达」（bgRevealed 恒 false =
  // 壁纸恒隐卡死）；时长 300ms 与消息区渐显同档。同实例内换图/恢复默认不重置 = 直切
  @State bgRevealed: boolean = false;
  // 强制纯色例外（仅编辑图片两页传 true，见头注释）；创建时固定，普通成员（不驱动 UI）
  solid: boolean = false;
  // 会话页背景标记：true = 本实例是会话页背景，不受「仅会话页」开关抑制；创建时固定，
  // 普通成员（不驱动 UI）
  sessionPage: boolean = false;
  // 一级页签背景标记（HomeNavigation 挂载的导航壳常驻背景）：冷启动「纯色→壁纸」跳变走
  // 渐显（见 bgRevealed 注释）；创建时固定普通成员，单实例常驻 = 渐显只冷启动播一次，
  // 切页签不重挂不重播
  homeTab: boolean = false;
  // 拉取序号：防乱序（连续换图时只采纳最新一次解码结果，先例 ImageEditPage blurSeq）
  private loadSeq: number = 0;

  aboutToAppear(): void {
    // 直达通道注册：实例入列，写点 notifyBgChanged() 点名 load 现读重判——送达不经任何
    // 框架订阅原语（与坑16/坑25 失效面正交）；三条 @Watch 链保留为次通道；销毁时与
    // departed 置位同点注销（成对释放）
    registerBgRefreshListener(this.onBgDirectRefresh);
    this.load();
  }

  // 任一信号变化（换图/恢复默认/开关切换）→ load 重判
  onAnySignalChanged(): void {
    this.load();
  }

  onShownEpoch(): void {
    // 私标置位先于一切（含 load）：冷缓存时序B（纪元先到、解码完成后 Image 才挂载）下
    // onAppear 兜底判此私标
    this.shellArrived = true;
    this.load();
    // ★ 错峰置位（决明拍板「错峰+300ms」）：会话页实例渐显触发推迟到页面壳 onShown——
    // push 转场窗口内不再叠全屏 alpha 大面动画（透明档掉帧削峰主收益）；到达软化让位
    // 可见性（动画不承担可见性职责，onAppear 兜底见 build 内注释）
    if (this.sessionPage) {
      this.bgRevealed = true;
    }
  }

  // 开关键现读（@StorageProp 值在栈下层冻结不可靠，判定一律读 AppStorage）
  private bgOnlyNow(): boolean {
    return AppStorage.get<boolean>(PREF_BG_SESSION_ONLY_KEY) === true;
  }

  // 是否抑制自定义背景显示：solid 例外（编辑图片两页）或「仅会话页」开关开启且本页非
  // 会话页。抑制 = 不显示背景图——但仍维护 BgCache（预热 + 恢复默认清空，见 load），
  // 缓存恒与当前 pageBg 对齐
  private suppressCustomBg(): boolean {
    return this.solid || (this.bgOnlyNow() && !this.sessionPage);
  }

  // 拉取当前背景位图：同步命中缓存直接显示；未命中触发缓存解码，完成后按序号采纳。换图
  // 瞬间 bgPm 保持旧图（先旧后新，无纯色闪变）；恢复默认先同步置空（安全窗口见 BgCache.ets）
  private load(): void {
    // solid 例外页：恒纯色、不消费也不预热 BgCache（前序页已预热缓存，跳过解码无谓消耗）；
    // loadSeq 递增作废在途回填
    if (this.solid) {
      this.loadSeq++;
      this.bgPm = null;
      return;
    }
    const seq: number = ++this.loadSeq;
    // uri 现读（O1：栈下层 @StorageProp 值冻结在压栈前旧值——读字段会拿旧 uri 跑全链：
    // '' 误清刚预热的新图缓存、旧图解码已删文件失败回纯色，见文件头）
    const uri: string = AppStorage.get<string>('pageBg') ?? '';
    if (uri.length === 0) {
      // 无背景：清空缓存（旧图移入延迟释放，见 BgCache.ets）。所有非 solid 实例通用含
      // 开关抑制实例——抑制态恢复默认若不在此清缓存，缓存会滞留旧图到下次换图
      this.bgPm = null;
      ensureBgPixelMap(''); // 清空缓存
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      // 禁止静默失败（P0-1）：极端场景回纯色但必须留日志
      hilog.error(0xD5A0, 'PageBackground', 'page background load failed: host context unavailable');
      this.bgPm = null;
      return;
    }
    // 沙箱纯路径单源 BgCache.bgCachePathFor（坑31 口径；与冷启动预热共用）
    const path: string = bgCachePathFor(context.filesDir, uri);
    if (this.bgOnlyNow() && !this.sessionPage) {
      // 开关抑制实例：不显示背景（恒走 build 纯色分支），但仍 ensure 维护缓存——冷启动/
      // 换图后进会话页同步命中零跳变（坑36 承诺在任何开关态成立）；在途回填已被上方 seq
      // 递增作废，不持有显示
      ensureBgPixelMap(path);
      this.bgPm = null;
      return;
    }
    const hit: image.PixelMap | null = getBgPixelMap(path);
    if (hit !== null) {
      this.bgPm = hit;
      return;
    }
    // 新图解码中（换壁纸后立即进页/页面重建）：先显示换图窗口的旧图兜底（prevPm）——首帧/
    // 转场不露纯色闪白，解码完成后经 ensure 切新图；无旧图（首次冷启动）保持纯色兜底。
    // ★ 守卫：仅 bgPm === null（当前无图可显，新页面首帧）才用 prevPm 兜底——无条件覆盖
    // 会把正在显示的正确图回退成两代之前的旧图（调整页保存未预热缓存路径必现：换图瞬间
    // 显示上上一张、解码完成才跳新图；换图解码失败路径则永久停在旧图）
    const fallback: image.PixelMap | null = getFallbackBgPixelMap();
    if (fallback !== null && this.bgPm === null) {
      this.bgPm = fallback;
    }
    ensureBgPixelMap(path).then((pm: image.PixelMap | null) => {
      if (this.departed) {
        return;
      }
      if (seq === this.loadSeq) {
        this.bgPm = pm;
      }
    });
  }

  build() {
    // 实底底色恒在（挂 Stack 背景色承载，原独立 Column 垫层并入——同色同层等价，每实例省
    // 一个全屏渲染节点）：BgCache 命中只保证「源就绪」不保证首帧栅格化/纹理上传完成，页面
    // 根透明（坑38）下该窗口 = 整页透出下层页面——底色恒铺后最差形态收窄为「同色一闪」；
    // 壁纸 Cover 满铺不透明，稳态观感零变化
    Stack() {
      if (!this.suppressCustomBg() && this.bgPm !== null) {
        // 自定义背景图：等比覆盖铺满（裁切多余），深浅色同一张；src 为共享缓存 PixelMap
        //（非 URI——零加载延迟，转场不闪，坑36）
        Image(this.bgPm)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          // 壁纸渐显（会话页 + 一级页签〔homeTab〕实例播，二级页直显）：置位驱动 opacity
          //——渐显实例首挂必经置位 → 渐显（新进会话播、pop 返回原实例不重播）；动画只
          // 软化到达、不承担可见性职责。★ 错峰（决明拍板）：会话页实例置位走 onShownEpoch
          //（转场后播）；本回调只兜底——非会话页实例挂载即置，会话页实例在私标已置
          //（shellArrived，时序B 冷缓存）时置位保「置位必达」（bgRevealed 恒 false = 壁纸
          // 恒隐卡死，430 组判据守护对象）；★ 兜底判据用实例私标而非全局纪元值（全局值在
          // 会话页挂载时恒 > 0，读值 = 兜底恒真错峰失效）。时长 300ms（错峰后不与转场抢帧，
          // 与消息区渐显同档）；animation 辖域只辖 opacity，声明位紧随其后
          .opacity((!this.sessionPage && !this.homeTab) || this.bgRevealed ? 1 : 0)
          .animation({ duration: 300, curve: Curve.EaseOut })
          .onAppear(() => {
            if (!this.sessionPage || this.shellArrived) {
              this.bgRevealed = true;
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    // 默认页面底色：page_bg 资源（base #F1F3F5 / dark #121212），深浅色自动。★ 勿再改
    // sys.color（官方化查证结论）：sys.color.background 不存在；官方 background_primary 纯
    // 白/深黑会回归「白底白卡无区分」（决明否决过）；官方 sub_background 浅色值虽同为
    // #F1F3F5 但简名不在 sysResource 清单、深色为纯黑（与定稿 #121212 不一致）——页面背景
    // 保持 app 资源，输入框/卡片等元素底色才走官方 comp_background_* 叠色体系。
    // 底色挂本 Stack 背景色（见 build 头注释）；非页面根 NavDestination 背景，不涉坑38
    .backgroundColor($r('app.color.page_bg'))
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 直达通道注销（与 departed 置位同点，注册成对释放）
    unregisterBgRefreshListener(this.onBgDirectRefresh);
  }
}
