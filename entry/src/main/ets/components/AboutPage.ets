// 「关于」三级页（2026-08-22 新增；「更多信息」页 InfoPage 行卡入口进入，展示应用版本信息 +
// 「AI 辅助开发声明 / 开源项目鸣谢」卡片入口；★ 2026-09-07 权限信息与隐私政策两卡自本页
// 移出至更多信息页行卡——决明指令）：顶部应用图标 + 应用名 + 版本信息
// 卡片（参考华为系统「关于/应用详情」页样式——用户参考图，去掉备案信息与客服电话；
// 「检测版本更新」无云服务器做不了 = 点击 toast 占位提示；卡片入口 push 对应二级页——
// 见 AboutPageCards 拆分注释）。
// 官方实现依据（2026-08-22 查证）：
// · 图标 = 官方 bpta《应用图标配置与开发》明示场景「应用详情页展示应用图标，例如：应用版本
//   信息页面」→ hdsDrawable 模块处理（@kit.UIDesignKit，@since 5.0.0(12)）；完整例程见官方
//   指南《（推荐）分层图标处理》ui-design-layered-process：getDrawableDescriptor($r(...).id)
//   → 断言 LayeredDrawableDescriptor → hdsDrawable.getHdsLayeredIcon(bundleName, desc, size,
//   hasBorder=false) → PixelMap → Image（不描边，参考图图标无描边）。
// · 版本号 = 运行期读 bundleManager.getBundleInfoForSelfSync（官方 API，不写死字符串——
//   单一来源 app.json5 打包写入包内 pack.info，详见 AGENTS.md「构建与部署」版本规则）。
// · 卡片 = 官方 HdsListItemCard + SuffixTextAndArrow（@since 6.0.0(20)，「已是最新版本 >」
//   官方组合，d.ts 核实）；无 HDS Full 设备回退自制白底卡片（同 InfoPage 惯例）。
// 页面骨架：PageShell（官方 Navigation 标题栏 TITLE_S + 背景 + HDS/回退双分支）。
import { bundleManager, common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial, LayeredDrawableDescriptor } from '@kit.ArkUI';
import { hdsDrawable } from '@kit.UIDesignKit';
import { SETTING_TITLE_ABOUT } from '../common/SettingSearch';
import { ROUTE_AI_ASSIST_PAGE, ROUTE_OPEN_SOURCE_PAGE } from '../common/RouteNames';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';
import { AboutPageCards } from './AboutPageCards';
import { PageShell } from '../common/PageShell';

// 图标输出边长（vp）：参考图示意尺寸，方形圆角（borderRadius 用官方设备圆角档）
const APP_ICON_SIZE: number = 88;

@Component
export struct AboutPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（首个控件静止时完整落在
  // 渐变模糊蒙层下方；回退路径传 0）。创建后不变，用普通成员（与其余 8 个二级页一致，
  // 状态最小化——2026-08-22 审查修正：原为 @Prop 过度装饰）
  topPad: number = 0;
  // 沉浸光感整体档位（AppStorage 共享，驱动 toast 材质）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 应用版本号（versionName，运行期读 bundleManager；@State 驱动卡片副文本刷新）
  @State appVersion: string = '';
  // 应用图标（hdsDrawable 处理后的 PixelMap；null = 处理失败不渲染——aboutToDisappear 释放）
  @State appIconPm: image.PixelMap | null = null;
  // 应用包名（bundleManager 动态读，hdsDrawable 参数用；普通成员——本页生命周期内不变）
  private bundleName: string = '';
  // 路由栈（HomeNavigation PageMap 传入，与根 Navigation 同一引用）：AI 声明/开源鸣谢
  // 卡片 pushPathByName 入栈下级页（官方系统级转场）；普通成员传引用
  pathStack: NavPathStack = new NavPathStack();
  // 官方 HDS 列表项卡片可用性：syscap 自检（HdsListItemCard 要求 HDSComponent.Full）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // 读取版本信息（bundleManager.getBundleInfoForSelfSync，官方同步 API；失败显示「未知」+
  // console.error 记录——版本读取失败不阻断页面，但日志留痕不静默）
  private readBundleInfo(): void {
    try {
      // ★ 必须用 WITH_APPLICATION 标志：GET_BUNDLE_INFO_DEFAULT 官方枚举注释「does not
      // contain information about the ... application」（2026-08-22 真机「未知」根因——DEFAULT
      // 下 appInfo 为 undefined，info.appInfo.name 抛 TypeError 被 catch 吞掉；顶层
      // versionName/versionCode 属默认基本信息始终可用，仅 appInfo 依赖该标志）
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      // appInfo 判空兜底（防任何 flag 行为差异再 TypeError；包名取不到时图标跳过渲染，版本号不受影响）
      this.bundleName = info.appInfo ? info.appInfo.name : '';
      this.appVersion = info.versionName;
    } catch (err) {
      this.appVersion = '未知';
      console.error('read bundle info failed: ' + JSON.stringify(err));
    }
  }

  // 生成应用图标（官方 hdsDrawable 分层图标处理，UI Design Kit；失败不渲染图标，仅日志）
  private buildAppIcon(): void {
    // 无 HDS Full 能力跳过（与 hdsListCardAvailable 卡片判据同源；非 HDS 设备 hdsDrawable 不支持）
    if (!this.hdsListCardAvailable) {
      return;
    }
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const resManager = hostContext?.resourceManager;
      if (!resManager) {
        console.error('build app icon failed: resourceManager unavailable');
        return;
      }
      // 原始分层图标信息（app.media.layered_image = AppScope 分层图标 json，前景+背景合成）
      const desc: LayeredDrawableDescriptor =
        resManager.getDrawableDescriptor($r('app.media.layered_image').id) as LayeredDrawableDescriptor;
      // 处理成与 HarmonyOS Design System 一致的图标（hasBorder=false：参考图图标无描边）
      this.appIconPm = hdsDrawable.getHdsLayeredIcon(this.bundleName, desc, APP_ICON_SIZE, false);
    } catch (err) {
      console.error('build app icon failed: ' + JSON.stringify(err));
    }
  }

  aboutToAppear(): void {
    this.readBundleInfo();
    this.buildAppIcon();
  }

  aboutToDisappear(): void {
    // 成对释放（内存红线）：本页持有的 PixelMap 销毁时释放（Image 组件只消费不拥有）
    if (this.appIconPm) {
      this.appIconPm.release();
      this.appIconPm = null;
    }
  }

  // 「检测版本更新」占位（无云服务器，2026-08-22 决明定稿：预留 toast 提示，不做假检查）
  private showVersionCheckPlaceholder(): void {
    this.showToast('版本检测功能暂未上线');
  }

  // 本页 toast 统一入口（2026-08-22 提取）：材质随沉浸光感总档
  //（基准 THICK = 官方默认档，同 InfoPage 复制提示）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false)
    });
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——同 InfoPage 坑）
    Column() {
      Scroll() {
        Column() {
          // 顶部：应用图标 + 应用名（参考图：图标居中、名字在下；iconPixelMap 失败时跳过图标）。
          // 图标/Text/卡片共用本 Column 的 alignItems(Center) 居中——卡片实际渲染宽 = 容器 100%−32vp
          if (this.appIconPm) {
            Image(this.appIconPm)
              .width(APP_ICON_SIZE)
              .height(APP_ICON_SIZE)
              // 设备圆角档（官方近似 API，同编辑图片预览框）：与系统图标形状一致而非生硬直角
              .borderRadius($r('sys.float.ohos_id_corner_radius_default_xl'))
              .margin({ bottom: 12 })
          }
          Text($r('app.string.app_name'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          // 图标/名字区与卡片之间距：24vp（视野内分区）
          .margin({ bottom: 24 })

          // 卡片列（2026-08-22 拆分：卡片 UI 已移入 AboutPageCards——本页逼近 400 行
          // 防屎山红线，规则要求先拆再加；点击回调上行本页处理）
          AboutPageCards({
            appVersion: this.appVersion,
            onVersionCheck: (): void => {
              this.showVersionCheckPlaceholder();
            },
            onAiAssist: (): void => {
              this.pathStack.pushPathByName(ROUTE_AI_ASSIST_PAGE, null);
            },
            onOpenSource: (): void => {
              this.pathStack.pushPathByName(ROUTE_OPEN_SOURCE_PAGE, null);
            }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（2026-08-22 修复：原固定 margin top 24 漏避让标题栏，内容顶到标题栏
        // 背后——真机复现；规范姿势同 InfoPage：首元素静止时完整落在渐变
        // 模糊蒙层下方，滚动时滑入蒙层透出）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（2026-08-20 根因修复：Scroll align 默认 Center——同 InfoPage）
      .align(Alignment.TopStart)
      // 官方边缘回弹：滑到边界继续滑一段距离、松手回弹
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支，见
    // common/PageShell.ets 头注释）；本页只提供标题与内容
    PageShell({
      title: SETTING_TITLE_ABOUT,
      content: () => {
        this.Content()
      }
    })
  }
}
