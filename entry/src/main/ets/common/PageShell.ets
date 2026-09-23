// 二级页公共骨架（2026-08-21 提取，防屎山 P2-4——6 个二级页根组件结构完全重复）：
// HDS/回退双分支 + PageBackground 背景层 + 页面根透明背景（坑38：系统转场圆角处透出
// 下层共享背景，不露实色白边）+ 官方标题栏（hdsTitleBarOptions，含菜单可选）+ 回退
// expandSafeArea。
// 新增二级页 = PageShell({ title, content }) 一行接入（内容经 @BuilderParam 传入），
// 背景一致性/透明背景/标题栏规格/深浅色适配结构性保证，无需逐页复制。
// 参数契约：
// - title 主标题；titleSize 标题字号档（二级页统一 TITLE_S，2026-08-20 定稿）；
// - menuHds 标题栏 HDS 菜单（hdsTitleBarOptions 第 5 参原样传，null = 无；两体系菜单
//   类型不同，menuNav 与之分开）；
// - menuNav 回退路径菜单（NavDestination.menus 原样传，空数组 = 无）；
// - titleBarStack 标题栏自定义覆盖层（可选，仅 HDS 路径生效）+ keepStackTitle 覆盖层下
//   是否保留主标题（可选，默认 false）——消费方见各自成员注释（覆盖层四页；keepStackTitle
//   三页）；
// - onShown 页面显示生命周期回调（可选透传 HdsNavDestination.onShown / NavDestination.onShown，
//   两条路径均支持（回退路径 2026-08-22 补接，见下方回退分支注释）；PermissionPage/
//   ChatPage/MemoryPage/StoragePage 四页同步配置用）；
// - content 页面内容（topPad/滚动/内容组件，纯展示 + 回调；页面差异集中在此）；
// - 档位材质（沉浸光感档位；2026-09-12 分项退役前含「其他控件」分项）本组件 @StorageProp
//   自订阅（LogPageContent 先例），免逐页透传。
import { uiMaterial } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions, HdsNavDestination, TitleSize } from '@kit.UIDesignKit';
import {
  hdsTitleBarOptions,
  IMMERSIVE_LEVEL_KEY,
  leveledUiMaterial,
  resolveEffectiveLevel
} from './ImmersiveLevel';
import { PageBackground, bumpBgShownEpoch } from './PageBackground';

@Component
export struct PageShell {
  // 主标题（官方标题栏；hdsTitleBarOptions 参数为 string）。
  // ★ 2026-09-15 附件查看器二级页化笔改 @Prop（原普通成员）：查看器标题须**随页**更新（滑到
  // 第二张图标题栏文字跟着变——600 段全面自检笔已把「标题随页」列为修复项），而普通成员构造
  // 期定值、父页 @State 变化不会传导（全仓无运行时改官方标题的先例：SearchEngineDetailPage /
  // ModelEditPage 的标题都是初始化期一次定值）。@Prop 单向同步：父页状态变 → 传值更新 →
  // 本壳重渲染 → hdsTitleBarOptions 重算。对其余消费方零行为影响（调用点本就传值参，值不变
  // 不触发重渲染）
  @Prop title: string = '';
  // 标题字号档：二级页统一 TITLE_S（2026-08-20 定稿：二级页标题小一号，介于一级页主标题
  // 与内容文字之间）
  titleSize: TitleSize = TitleSize.TITLE_S;
  // 标题栏 HDS 菜单（可选，如运行日志「更多」、服务地址「刷新」；hdsTitleBarOptions 第 5
  // 参原样传；null = 无菜单）
  menuHds: HdsNavigationMenuContentOptions | null = null;
  // 回退路径菜单（NavDestination.menus 原样传；空数组 = 无菜单）
  menuNav: Array<NavigationMenuItem> = [];
  // 页面显示生命周期回调（可选，透传 HdsNavDestination.onShown / NavDestination.onShown——
  // @StorageProp 在栈下层不刷新的替代姿势；两条路径均支持，消费方见头注释）
  onShown: () => void = () => {
  };
  // 返回键拦截回调（可选，2026-08-30 坑17：需要「完成返回即刷新」的页面——排序页等
  // 无保存动作的场景——用 onBackPressed 拦截官方返回链后 pop({ saved: true }) 触发父页
  // onPop；缺省返回 false = 官方返回行为不变；两路径均支持）
  onBackPressed: () => boolean = (): boolean => false;
  // 背景强制纯色例外（2026-08-21：仅「编辑图片」两页 true——预览框叠壁纸看不清，
  // 见 common/PageBackground.ets 头注释；默认 false 全部页面跟随自定义壁纸）
  bgSolid: boolean = false;
  // 会话页背景标记（2026-09-05「背景仅用于会话页」开关配套）：true = 本页是会话页，
  // 开关开启时仍显示自定义背景（仅 ChatPage 传 true；二级页均非会话页，默认 false）
  bgSessionPage: boolean = false;
  // 标题栏自定义覆盖层（可选，2026-08-22 搜索页引入；官方 stackBuilder @since 6.0.0(20)，
  // 仅 HDS 路径生效，回退路径无此机制——回退页自行在内容区布局）：
  // 整栏覆盖在标题栏上方，搜索页用它把搜索框嵌入标题栏与返回键并排（覆盖层须自行避让
  // 返回键位置；传入后 HDS 路径主标题自动置空，见 ImmersiveLevel hdsTitleBarOptions）。
  // 类型用 CustomBuilder 普通参数而非 @BuilderParam：该函数最终原样交给官方 titleBar
  // 选项（官方示例同款 CustomBuilder 字段），不在本组件 build 里当 UI 插槽调用
  titleBarStack: CustomBuilder | null = null;
  // 覆盖层下保留主标题（可选，透传 hdsTitleBarOptions 的 keepStackTitle；默认 false =
  // 覆盖层存在即置空主标题）。现役消费方三处 = 记忆页 / 技能库页 / 附件查看器页（三页覆盖层
  // 都只占标题栏右侧，主标题须照常显示——附件查看器页主标题「当前页文件名」随页更新）。
  // 记忆页一脉的沿革：2026-09-11 首立（记忆页三键覆盖层）→ 2026-09-13 随覆盖层退役（死参
  // 不留）→ 2026-09-15 随覆盖层回归重启；技能库页同日并入（五百八十五），附件查看器页同日
  // 二级页化并入（六百二十八）——「唯一消费方 = 记忆页」的旧表述沿自五百八十四，六百二十八
  // 起失实（2026-09-16 批次三自检轮按全仓实扫改写）
  keepStackTitle: boolean = false;
  // 页面内容（Slot）：纯展示 + 回调上行；topPad/滚动由内容自行处理
  @BuilderParam content: () => void;
  // 沉浸光感档位（AppStorage 自订阅：标题栏材质/返回键圆底/菜单按钮圆底统一驱动，
  // 免逐页透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 官方 HDS 导航可用性（与 HomeNavigation 根容器同一能力位，两条路径必然一致）
  private hdsAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Core');

  build() {
    if (this.hdsAvailable) {
      HdsNavDestination() {
        // Stack 背景层垫底（统一页面背景，见 common/PageBackground.ets）：自定义背景图写入
        // AppStorage['pageBg'] 后所有二级页自动跟随（共享位图缓存，见 BgCache.ets）
        Stack() {
          PageBackground({ solid: this.bgSolid, sessionPage: this.bgSessionPage })
          this.content()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      // 页面根背景透明（坑38）：系统转场圆角处透出下层（一级页共享背景），不露实色白边；
      // 页面不透明度由 PageBackground 铺满 + 纯色分支兜底保证
      .backgroundColor(Color.Transparent)
      // 官方 HDS 标题栏：返回按钮（栈非空自动显示）+ 渐变模糊 + 光感材质（参数含义与
      // 定稿见 ImmersiveLevel.ets hdsTitleBarOptions；材质由沉浸光感总档驱动）；
      // 覆盖层下保留主标题（keepStackTitle）经本壳同名参透传——消费方三处（记忆页/技能库页/
      // 附件查看器页）的覆盖层都只占标题栏右侧，其值即消费方实需；未传 = 默认置空（覆盖层压在
      // 标题上方，官方示例同款）
      .titleBar(hdsTitleBarOptions(this.title, this.immersiveLevel, this.titleSize,
        this.menuHds !== null ? this.menuHds : undefined,
        this.titleBarStack !== null ? this.titleBarStack : undefined, this.keepStackTitle))
      // 页面显示生命周期（透传，消费方见头注释）+ 背景显示自刷（O1 修复：
      // 每次页面显示 bump 纪元键——pop 回旧实例时 PageBackground @Watch → load 现读重判，
      // 坑25 定稿「onShown 是可靠姿势，每次页面显示触发，含 pop 返回」）
      .onShown(() => {
        bumpBgShownEpoch();
        this.onShown();
      })
      // 返回键拦截（透传；坑17——完成返回即刷新的页面用，缺省 false 官方行为不变）
      .onBackPressed(() => {
        return this.onBackPressed();
      })
    } else {
      NavDestination() {
        // Stack 背景层垫底（同 HDS 分支，见上）
        Stack() {
          PageBackground({ solid: this.bgSolid, sessionPage: this.bgSessionPage })
          this.content()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      // 官方默认标题栏：title(ResourceStr) + 官方返回箭头（栈非空自动显示、点击自动 pop）+
      // 官方主标题字号/位置/边距；options 挂沉浸光感材质（与一级页回退路径同规格；总档
      //「无」→ resolveEffectiveLevel 归一 -1，leveledUiMaterial 内部转 Material.empty）
      .title(this.title, {
        systemMaterial: leveledUiMaterial(uiMaterial.ImmersiveStyle.THIN,
          resolveEffectiveLevel(this.immersiveLevel), false)
      })
      .menus(this.menuNav)
      // 页面显示生命周期（同 HDS 分支透传）+ 背景显示自刷
      //（O1 修复，同 HDS 分支——NavDestination.onShown 官方支持）
      .onShown(() => {
        bumpBgShownEpoch();
        this.onShown();
      })
      // 返回键拦截（透传；坑17——完成返回即刷新的页面用，缺省 false 官方行为不变）
      .onBackPressed(() => {
        return this.onBackPressed();
      })
      // 覆盖 Navigation 默认 expandSafeArea 去掉 TOP（避让状态栏，见 HomeNavigation.ets
      // 回退分支注释）；BOTTOM 保持展开
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD, SafeAreaType.CUTOUT], [SafeAreaEdge.BOTTOM])
    }
  }
}
