// 「外观显示」二级页（2026-08-29 M2c 自 dshinhm 同名页精简迁移；**M3 任务 2 补齐「背景」
// 分段**——dshinhm 定稿形态整体替换光感直排版）：
// 顶部官方分段按钮（CapsuleSegmentButtonV2 单选胶囊型，「光感 / 背景」两标签，参数定稿在
// 公共组件 components/SegmentBar.ets——官方/自定义边界注释见该文件头）+ 两个面板：
// ①光感面板：沉浸光感调节中心（整体档位（适应/无/弱/均衡/强）——语义见
// common/ImmersiveLevel.ets）——一滑轨卡 + 光感新规范开关卡（★ 2026-09-12 决明拍板分项
// 退役：原「悬浮底栏」「其他控件」两张分项滑轨卡删除，两处档位恒跟随总档，细节见
// ImmersiveLevel.ets 头注释「分项退役」节）；
// ②背景面板：更换背景（选择图片/编辑图片/恢复默认三卡，见 components/BackgroundPanel.ets
// ——选图→拷沙箱→push 编辑页，保存成功才生效；恢复默认 = 清 pageBg 回官方灰底）。
// 布局：滑轨卡（2026-09-03 决明「放卡片，参考助手采样参数滑轨」——cardBg + borderRadius
// 16 + padding 16 + CARD_PANEL_WIDTH，SamplingToggleCard 同款卡规范）+ 节标题（粗体）+
// 灰色说明 + 长滑块 + 刻度名在卡内；滑块 = 官方 Slider（InSet 胶囊滑轨，形态注释同 dshinhm）。
// 原「平铺不进卡片」dshinhm 定稿口径随本次卡片化废弃（页面节间距 28 与卡间距 CARD_SPACING
// 的同源关系见 LightPanel 注释）。
// Stack 吸顶结构（dshinhm 定稿）：内容滚动层 + 分段胶囊悬浮固定层——胶囊不随内容滚动，
// 内容向上滚时从胶囊背后穿过，经胶囊背板沉浸光感材质（backgroundSystemMaterial）模糊透出。
// 页面骨架：壳在 nav/PageMapBuilder.ets（HdsNavDestination/NavDestination 双分支 + 根透明 +
// PageBackground 铺底 + TITLE_S 标题栏），本组件只提供内容（dshinhm 版经 PageShell 自包壳，
// aicontrol 统一壳在 PageMap——差异仅 build 外壳层，内容结构原样）。
// 入口：设置页行卡 + 搜索（tab 分段参数：0 光感 / 1 背景，坑44——@State 初始化器先于父组件
// 传参执行，aboutToAppear 里赋值）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, SEGMENT_BAR_HEIGHT, sliderTrackColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY,
  IMMERSIVE_LEVEL_KEY,
  IMMERSIVE_LEVEL_SHORT_NAMES,
  leveledUiMaterial
} from '../../common/ImmersiveLevel';
import {
  SETTING_TITLE_APPEARANCE,
  SETTING_TITLE_CONTENT_FALLBACK,
  SETTING_TITLE_IMMERSIVE_LEVEL,
  SETTING_TITLE_TAB_BACKGROUND,
  SETTING_TITLE_TAB_LIGHT
} from '../../common/SettingSearch';
import { BackgroundPanel } from '../BackgroundPanel';
import { InfoHintButton } from '../InfoHintButton';
import { SegmentBar } from '../SegmentBar';
import { PageShell } from '../../common/PageShell';

// 单节调节控件：节标题 + 说明 + 官方步进滑块（带沉浸光感滑轨）+ 刻度名
//（dshinhm AppearancePage.LevelSlider 实测定稿形态照搬：官方默认尺寸 20vp 滑轨 + 12×12
// 滑块，2026-08-20 dshinhm 真机微调定稿；间距 6/3/3vp 逐项 margin 不用 Column space）
@Component
struct LevelSlider {
  // 节标题/说明/刻度名：纯展示入参，创建后不变，用普通成员
  title: string = '';
  desc: string = '';
  names: string[] = [];
  // 当前档位（父组件 @StorageLink 驱动重建）与生效档位（-1 或 1（总档「无」）= 无材质，
  // 滑轨实时预览；1 由 leveledUiMaterial 内部转 Material.empty）
  @Prop value: number = 0;  @Prop resolvedLevel: number = 0;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  onChange: (value: number) => void = () => {
  };

  build() {
    // ★ 卡片壳（2026-09-03 决明「三个滑轨放卡片，参考助手采样参数滑轨」）：卡 = 标题 +
    // 说明 + 滑块 + 刻度名，外层 cardBg + borderRadius 16 + padding 16 + CARD_PANEL_WIDTH
    //（SamplingToggleCard 同款卡规范——底色/圆角/宽度三线对齐，见该组件头注释）；
    // 间距 6/3/3vp 逐项 margin 保持（采样卡 Column space 12 系弹展开区间隙，本卡无展开区）
    Column() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
        .margin({ bottom: 6 })
      Text(this.desc)
        .fontSize(13)
        .fontColor(cardDescColor())
        .margin({ bottom: 3 })
      // 官方 InSet 长滑动条（官方默认尺寸：trackThickness 20vp + blockSize 12×12——
      // dshinhm 本地 SDK slider.d.ts 核实过的定稿尺寸）
      Slider({ value: this.value, min: 0, max: this.names.length - 1, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(20)
        .blockSize({ width: 12, height: 12 })
        .trackBorderRadius(10)
        // 半透明滑轨色：让底层沉浸光感材质透出（不透明会完全盖住材质滤镜，官方属性冲突约束）
        .trackColor(sliderTrackColor(this.appColorMode))
        // 按住滑块/滑轨即移动并拖动（官方默认 SLIDE_AND_CLICK，显式声明防默认变化）
        .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
        // 材质按布局区域 + borderRadius 渲染（官方指南 Column 示例同款），圆角与胶囊滑轨一致
        .borderRadius(10)
        // 滑轨沉浸光感材质：REGULAR 通用场景基准档，随生效档位偏移；「无」档显式关闭
        .systemMaterial(this.resolvedLevel < 0 ? uiMaterial.Material.empty :
          leveledUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.resolvedLevel, false))
        .onChange((value: number) => {
          this.onChange(value);
        })
        .margin({ bottom: 3 })
      // 刻度名：SpaceBetween 两端对齐（dshinhm 定稿——首项「适应」2 字宽；短名常量口径
      // 见 common/ImmersiveLevel.ets）
      Row() {
        ForEach(this.names, (name: string) => {
          Text(name)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    // 组件整体宽度统一 CARD_PANEL_WIDTH（与卡片页同宽对齐，调用方 Column 居中）
    .width(CARD_PANEL_WIDTH)
    .alignItems(HorizontalAlign.Start)
    // 卡片壳（采样卡同款规范：cardBg + borderRadius 16 + padding 16）
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
  }
}

@Component
export struct AppearancePage {
  // 沉浸光感总档（@StorageLink 双向绑定 AppStorage，拖动滑条即全应用生效——标题栏/页签材质
  // 由消费方 @StorageProp 自动跟随；持久化由 EntryAbility 的 persistProp 负责，重启保留）
  @StorageLink(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 光感新规范开关（2026-09-03 第四项，2026-09-07 更名「光感新规范」）：默认 true = 内容区
  // 受影响组件按华为新光感规范走官方标准形态（分段胶囊 = 官方默认 A 档、按钮 = fallbackButton*
  // 官方实底——新规范下内容区材质不生效）；false = 保留原材质光感（对照验收/回滚）。@StorageLink
  // 即改即生效（消费侧 @StorageProp 订阅式随刷，无广播需求——坑16 正解契约同流式引擎开关）
  @StorageLink(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 顶部留白（vp，导航壳下发：首节落在标题栏渐变模糊蒙层下方）；底部留白 = 避让区高
  //（二级页全屏覆盖页签；dshinhm 版固定 bottom 24，aicontrol 全屏窗口加 navBarHeight 让位）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 系统颜色模式（开关卡底色；EntryAbility 已接线写键，深浅色切换自动刷新——同
  // PreferencesPage 开关行契约）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：背景面板「选择图片/编辑图片」卡片
  // push 编辑二级页（官方系统级转场）
  pathStack: NavPathStack = new NavPathStack();
  // 顶部分段标签选中项：0 光感面板 / 1 背景面板。
  // 初始分段 initialTab（搜索结果跳转指定分段用；普通进入 0）：坑44——@State 初始化器先于
  // 父组件传参执行，必须在 aboutToAppear 里把入参赋给 @State（dshinhm 先例）
  @State sectionTab: number = 0;
  initialTab: number = 0;
  // 官方分段按钮选项（单选胶囊型 CapsuleSegmentButtonV2，@since 18）：纯展示入参，普通成员
  private sectionItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: SETTING_TITLE_TAB_LIGHT },
    { text: SETTING_TITLE_TAB_BACKGROUND }
  ]);

  aboutToAppear(): void {
    // 坑44：@State 初始化器先于父组件传参执行——入参 initialTab 在此赋给 @State
    this.sectionTab = this.initialTab;
  }

  // 光感新规范开关卡（2026-09-03 第四项，2026-09-07 更名；同日卡面说明改短 + 标题行挂
  // InfoHintButton 气泡——补「不再跟随上方光感滑轨」关键关系（帮助中心条目已有该句，
  // UI 卡面此前缺失），完整边界说明进气泡；2026-09-08 气泡位置修正——气泡从「左列标题
  // 行右端」上移至整卡右上角（原结构标题行在左侧文本列内、右侧为开关列，气泡落在开关
  // 左上角——决明真机反馈「要求整卡右上角」）：两行结构 = 顶行 标题 + 气泡（标题行撑满
  // 卡内宽，气泡即落整卡右上角，与开关不重叠不遮挡）/ 次行 说明 + 官方开关（PreferencesPage
  // 开关行同款：说明左、Toggle 右同行，先说明后操作口径不变）。卡体 = 自绘卡 cardBg +
  // borderRadius 16 + CARD_PANEL_WIDTH（开关行非单条目导航卡，不走 HdsListItemCard 形态
  // ——与禁用/单选卡同族口径）
  @Builder
  FallbackSwitchCard() {
    Column({ space: 2 }) {
      // 顶行 = 标题 + info 气泡（InfoHintButton 先例：长说明移入气泡、卡面留关键句；
      // 行宽撑满卡内宽度 → 气泡在整卡右上角）
      Row() {
        Text(SETTING_TITLE_CONTENT_FALLBACK)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '开启后，内容区组件例如按钮、分段胶囊，采用华为新光感规范的官方标准外观，不再随上方光感滑轨变化。标题栏、弹窗与悬浮页签仍跟随沉浸光感档位。关闭后恢复旧版光感效果'
        })
      }
      .width('100%')
      // 次行 = 说明 + 官方开关（PreferencesPage 开关行先例：说明左、Toggle 右同行）
      Row({ space: 12 }) {
        Text('开启后，内容区组件不再跟随上方光感滑轨。关闭后恢复旧版光感效果')
          .fontSize(13)
          .fontColor(cardDescColor())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.contentFallback })
          .onChange((isOn: boolean): void => {
            this.contentFallback = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .width(CARD_PANEL_WIDTH)
  }

  // 光感面板：总档滑轨卡 + 光感新规范开关卡（2026-09-03 卡片化：卡间距 CARD_SPACING=10，
  // 与背景面板/偏好页卡片间距统一；原无卡时节间距 28vp 口径随卡片化废弃。分项两滑轨卡
  // 2026-09-12 退役——两处档位恒跟随总档，见 ImmersiveLevel.ets 头注释）
  @Builder
  LightPanel() {
    Column({ space: CARD_SPACING }) {
      LevelSlider({
        title: SETTING_TITLE_IMMERSIVE_LEVEL,
        desc: '全应用的材质光感基准',
        names: IMMERSIVE_LEVEL_SHORT_NAMES,
        value: this.immersiveLevel,
        resolvedLevel: this.immersiveLevel,
        onChange: (value: number) => {
          this.immersiveLevel = value;
        }
      })
      this.FallbackSwitchCard()
    }
  }

  build() {
    // 页面骨架统一由 PageShell 提供（2026-09-07 迁——原 PageMapBuilder 直壳 titleBar 为
    // 入栈快照，本页调档位后返回键材质不实时刷新，须返回重进才生效（决明真机反馈）；
    // PageShell 内部 @StorageProp 自订阅标题栏档位材质，实时跟随）；PageShell 已含
    // HDS/回退双分支 + PageBackground + onShown(bumpBgShownEpoch) 内置
    PageShell({
      title: SETTING_TITLE_APPEARANCE,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    // Stack 叠加（dshinhm 定稿吸顶结构）：内容滚动层 + 分段胶囊悬浮固定层——胶囊不随内容
    // 滚动；内容向上滚时从胶囊背后穿过，经胶囊背板沉浸光感材质模糊透出
    Stack({ alignContent: Alignment.Top }) {
      // ── 内容滚动层：从屏幕顶开始（HDS 路径内容区延伸到标题栏背后），顶部留白 =
      // 胶囊悬浮位置（topPad - 8）+ 胶囊总高 SEGMENT_BAR_HEIGHT + 面板间距 28——
      // 内容初始静止在胶囊下方，滚动时滑入胶囊背后；底部 24vp 留白 + 避让区让位
      Scroll() {
        Column() {
          if (this.sectionTab === 0) {
            this.LightPanel()
          } else {
            BackgroundPanel({ pathStack: this.pathStack })
          }
        }
        .width('100%')
        // 控件统一 CARD_PANEL_WIDTH 居中：内容区不设左右边距，留白由控件自身宽度产生
        .alignItems(HorizontalAlign.Center)
        // 从上往下依次排列（列表卡片页通用法则）
        .justifyContent(FlexAlign.Start)
        .padding({ top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28, bottom: this.bottomPad + 24 })
      }
      .width('100%')
      .height('100%')
      // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)

      // ── 分段胶囊悬浮固定层：Stack 顶层（后声明在上），顶部对齐，位置 = 原静止位置
      //（topPad - 8：标题栏下沿 + 蒙层渐隐边缘 8vp；回退路径 topPad=0 钳位 0）。
      // 官方单选胶囊型分段按钮参数定稿在公共组件 components/SegmentBar.ets（单一来源勿
      // 单独乱调）；本层仅负责悬浮定位与宽度约束（官方无宽度参数且 width 通用属性无效）
      Column() {
        SegmentBar({
          items: this.sectionItems,
          selectedIndex: $sectionTab
        })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: Math.max(this.topPad - 8, 0) })
    }
    .width('100%')
    .height('100%')
  }
}
