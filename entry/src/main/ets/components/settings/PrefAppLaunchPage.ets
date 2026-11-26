// 偏好设置二级页「应用与启动」：一级偏好页第 4 行入口的承载页——「界面观感」「启动进入」
// 两个单卡板块合并迁入（页签切换动画开关卡 / 启动进入右置分段行卡——SettingSegmentRowCard
// 单源件）。★ 2026-11-17 整体退役加密会话笔：原「生物识别方式」分段卡随功能退役删除
//（唯一消费方 BiometricGate 已整件撤除）。
// ★ 2026-11-18 决明拍板「侧栏对话形态」开关行从偏好一级页「外观」卡迁入本页——它与
//  「启动进入」同属首页导航形态族（开 = 首页直接对话、历史收左侧栏），拨动仍由 HomeNavigation
//  @Watch 热切回根，链未动；@StorageLink 写即持久化，无保存动作。
// 坑17 口径：壳由 PageShell 提供；开关与分段即时持久化（AppStorage persistProp 键）无保存动作 →
// 返回走无参 pop、push 不挂 onPop。两处分段卡的双向映射（下标 ↔ 布尔键、互设守卫同值不递归）见成员注释。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { SettingSegmentRowCard } from '../SegmentBar';
import { HOME_LAYOUT_DRAWER, HOME_LAYOUT_TABS, PREF_HOME_LAYOUT_KEY, PREF_LAUNCH_NEW_CHAT_KEY, PREF_TAB_SWITCH_ANIM_KEY } from '../../common/AppPreferences';
import { SETTING_TITLE_HOME_LAYOUT, SETTING_TITLE_LAUNCH_ENTRY, SETTING_TITLE_PREF_APP_LAUNCH, SETTING_TITLE_TAB_SWITCH_ANIM } from '../../common/SettingSearch';
import { PageShell } from '../../common/PageShell';

@Component
export struct PrefAppLaunchPage {
  // 页签切换动画：true = 底部页签点击切换带横向滑动动画（默认）/ false = 点按直达无过渡。
  // 消费方 = HomeNavigation @StorageProp 订阅（状态驱动重渲染即时生效，无广播）
  @StorageLink(PREF_TAB_SWITCH_ANIM_KEY) tabSwitchAnim: boolean = true;
  // 首页布局（侧栏对话形态）：true = 侧栏对话形态 / false = 底栏页签（默认，两值域归一见
  // resolveHomeLayout）。2026-11-18 从偏好一级页「外观」卡迁入本页。消费方 = HomeNavigation
  // @StorageProp + @Watch 热切回根（拨动即生效，当前页被清栈回首页可预期）
  @StorageLink(PREF_HOME_LAYOUT_KEY) homeLayout: string = HOME_LAYOUT_TABS;
  // 启动进入页面：true = 冷启动直接进入新对话（懒创建不落库，助手随当前选择）/ false = 进入对话一级页
  //（会话列表，默认）。消费方 = HomeNavigation.aboutToAppear 现读一次（仅冷启动首帧生效，后台回前台不重进；
  // 切换下次启动生效）。双向映射：点分段经 onLaunchIndexChanged 写键，备份导入等
  // 其他写键经 onLaunchPrefChanged 补正下标——互设守卫同值不递归
  @StorageLink(PREF_LAUNCH_NEW_CHAT_KEY) @Watch('onLaunchPrefChanged') launchNewChat: boolean = false;
  @State @Watch('onLaunchIndexChanged') launchIndex: number = 1;
  // 分段选项（顺序契约：下标 0 = 新对话（键 true）/ 1 = 会话列表（键 false），勿单独乱调）
  private launchItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '新对话' },
    { text: '会话列表' }
  ]);
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 系统颜色模式（自绘卡底色；EntryAbility 已接线写键，深浅色切换自动刷新）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // 分段下标与持久键初值对齐（@StorageLink 声明处默认值不代表键实际值）
    this.launchIndex = this.launchNewChat ? 0 : 1;
  }

  // 用户点分段 → 写启动进入持久键（互设守卫同值不递归；下标 0 = 新对话 = 键 true）
  private onLaunchIndexChanged(): void {
    const newChat: boolean = this.launchIndex === 0;
    if (newChat !== this.launchNewChat) {
      this.launchNewChat = newChat;
    }
  }

  // 工具直写键 / 其他写键方 → 补正分段下标（onBiometricChanged 同款契约）
  private onLaunchPrefChanged(): void {
    const idx: number = this.launchNewChat ? 0 : 1;
    if (idx !== this.launchIndex) {
      this.launchIndex = idx;
    }
  }

  build() {
    // 页面骨架统一由 PageShell 提供；标题 = 行名常量（与一级页入口行共用单一来源）
    PageShell({
      title: SETTING_TITLE_PREF_APP_LAUNCH,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 页签切换动画单卡（板块不足 2 行不组卡——组卡规范红线 5）
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_TAB_SWITCH_ANIM)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('开启后页签滑动切换。关闭后直达无过渡')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.tabSwitchAnim })
            .onChange((isOn: boolean): void => {
              this.tabSwitchAnim = isOn;
            })
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 侧栏对话形态开关单卡（2026-11-18 从偏好一级页「外观」卡迁入，形制照上方页签动画卡：
        // 说明小字置于操作行上方，开关拨动即写持久键、HomeNavigation @Watch 热切回根）
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_HOME_LAYOUT)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('开启后首页直接进入对话，历史会话与入口收进左侧栏')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.homeLayout === HOME_LAYOUT_DRAWER })
            .onChange((isOn: boolean): void => {
              this.homeLayout = isOn ? HOME_LAYOUT_DRAWER : HOME_LAYOUT_TABS;
            })
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 启动进入分段行卡（SettingSegmentRowCard 单源件；双向映射见成员注释）
        SettingSegmentRowCard({
          title: SETTING_TITLE_LAUNCH_ENTRY,
          subtitle: '打开应用时默认进入的页面',
          items: this.launchItems,
          selectedIndex: $launchIndex
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }
}
