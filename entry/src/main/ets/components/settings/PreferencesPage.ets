// 「偏好与外观」一级页（原「偏好设置」页扩容，随重梳笔并入外观域；决明拍板彻底重梳）：本页
// 承载三个板块头与三张入口组卡——「使用习惯」卡 3 入口行（输入与发送 / 回复显示 / 会话与阅读）、
// 「外观」卡 2 入口行（背景 / 字体——原「外观显示」页三段拆行，段内容各成三级页）、
// 「应用」卡 1 入口行（应用与启动），行尾 chevron 示意可进下一页；点击 push 对应三级页
//（分流与沿革见各 Pref*Page / PrefBackgroundPage / PrefFontPage 文件头注释）。
// ★ 分组定稿（决明拍板）：行副标题 = 组内代表项列举（与设置页入口卡「动词开头一句简介」口径
// 有意不同，本页帮用户定位项落在哪行）。
// 骨架：壳由 PageShell 提供（HDS 单路径 + PageBackground + onShown 内置）；本页无状态 → push
// 无参、返回无参 pop 不挂 onPop（坑17 口径）。行点击经 pathStack 直接 push（SearchPage 先例——
// pathStack 由 PageMapBuilder 分支下发，不经 HomeNavActions）。组卡行形态 = 跳转行 + chevron。
import { SECTION_GAP, SECTION_HEADER_GAP } from '../../common/Theme';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE, SETTING_ICON_GREEN, SETTING_ICON_PURPLE } from '../GroupSettingCard';
import { ROUTE_PREF_APP_LAUNCH_PAGE, ROUTE_PREF_BACKGROUND_PAGE, ROUTE_PREF_FONT_PAGE, ROUTE_PREF_INPUT_SEND_PAGE, ROUTE_PREF_REPLY_DISPLAY_PAGE, ROUTE_PREF_SESSION_READ_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_PREF_APP_LAUNCH, SETTING_TITLE_PREF_INPUT_SEND, SETTING_TITLE_PREF_REPLY_DISPLAY, SETTING_TITLE_PREF_SESSION_READ, SETTING_TITLE_PREFERENCES, SETTING_TITLE_TAB_BACKGROUND, SETTING_TITLE_TAB_FONT } from '../../common/SettingSearch';
import { SectionHeader } from '../SectionHeader';
import { PageShell } from '../../common/PageShell';

// 板块头（只留标题——副标题行 2026-11-01 决明拍板整行退役）
const PREF_SECTION_HABIT: string = '使用习惯';
// 「外观」板块（原「外观显示」页三段拆行——背景 / 字体各成三级页，入口行收拢于此）
const PREF_SECTION_APPEARANCE: string = '外观';
const PREF_SECTION_APP: string = '应用';

// 入口行副标题（二级页内容的代表项列举——参考图入口行范式；只此一处使用，不入搜索注册表）
const SUBTITLE_PREF_INPUT_SEND: string = '回车发送、粘贴转文件、自动重试';
const SUBTITLE_PREF_REPLY_DISPLAY: string = '思考块、自动跟随';
// 会话与阅读页副标题（★ 2026-11-12 偏好开关批随退役改写：原「屏幕常亮、卡片显示、排列方向」
// 的后两项分别指向已退役的会话时间/图标显示开关与整卡撤除的「会话排序」——保留项按页内
// 现役卡列举：屏幕常亮 / 后台回复提醒 / 会话宫格视图 + 快捷新建键 + 智感握姿）
const SUBTITLE_PREF_SESSION_READ: string = '屏幕常亮、宫格视图、快捷新建键';
// 外观两行副标题（对应三级页内容的代表项列举）
const SUBTITLE_PREF_BACKGROUND: string = '选择壁纸、生效范围与恢复默认';
const SUBTITLE_PREF_FONT: string = '正文字体、代码字体与自定义字体';
const SUBTITLE_PREF_APP_LAUNCH: string = '页签动画、解锁方式、启动页面';

@Component
export struct PreferencesPage {
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：行点击 push 对应三级页（SearchPage 同款）
  pathStack: NavPathStack = new NavPathStack();
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;

  // 卡1「使用习惯」行数据（3 入口行；类型化返回——ArkTS 禁 build 内匿名字面量数组 10605038）
  private habitGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.keyboard'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_PREF_INPUT_SEND,
        secondary: SUBTITLE_PREF_INPUT_SEND,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_INPUT_SEND_PAGE, null);
        }
      },
      {
        icon: $r('sys.symbol.text_bubble_left_2'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_PREF_REPLY_DISPLAY,
        secondary: SUBTITLE_PREF_REPLY_DISPLAY,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_REPLY_DISPLAY_PAGE, null);
        }
      },
      {
        icon: $r('sys.symbol.message'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_PREF_SESSION_READ,
        secondary: SUBTITLE_PREF_SESSION_READ,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_SESSION_READ_PAGE, null);
        }
      }
    ];
  }

  // 卡2「外观」行数据（2 入口行——原「外观显示」页三段拆行；行图标 = 工程实证
  // 符号：picture / textformat 在用先例见 SettingsPage 与 PrefInputSendPage，photo 未在用
  // 不取。★ 2026-11-18 决明拍板「侧栏对话形态」开关行随功能域迁入「应用与启动」页
  //（PrefAppLaunchPage），本卡回归纯外观两行——HomeNavigation @Watch 热切回根链随迁入页保留）
  private appearanceGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.picture'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_TAB_BACKGROUND,
        secondary: SUBTITLE_PREF_BACKGROUND,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_BACKGROUND_PAGE, null);
        }
      },
      {
        icon: $r('sys.symbol.textformat'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_TAB_FONT,
        secondary: SUBTITLE_PREF_FONT,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_FONT_PAGE, null);
        }
      }
    ];
  }

  // 卡3「应用」行数据（1 入口行——板块不足 2 行仍成卡：入口行独立形态非开关单卡）
  private appGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.gearshape'),
        iconBg: SETTING_ICON_GREEN,
        label: SETTING_TITLE_PREF_APP_LAUNCH,
        secondary: SUBTITLE_PREF_APP_LAUNCH,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_APP_LAUNCH_PAGE, null);
        }
      }
    ];
  }

  build() {
    // 页面骨架统一由 PageShell 提供（自带档位实时刷新，勿自绘 titleBar）
    PageShell({
      title: SETTING_TITLE_PREFERENCES,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: SECTION_GAP }) {
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: PREF_SECTION_HABIT })
          // 恒单例 ForEach（key = 组首行标题——组为静态数据无增删，key 仅用于稳定标识）
          ForEach([this.habitGroup()], (group: GroupEntryItem[]) => {
            GroupSettingCard({ items: group, dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (group: GroupEntryItem[]): string => group[0].label)
        }
        .width('100%')
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: PREF_SECTION_APPEARANCE })
          // 恒单例 ForEach（组为静态两行无开关——键只作稳定标识；"侧栏对话形态"开关行随
          // 2026-11-18 迁入应用与启动页，本卡不再需要布局值进键）
          ForEach([this.appearanceGroup()], (group: GroupEntryItem[]) => {
            GroupSettingCard({ items: group, dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (group: GroupEntryItem[]): string => group[0].label)
        }
        .width('100%')
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: PREF_SECTION_APP })
          ForEach([this.appGroup()], (group: GroupEntryItem[]) => {
            GroupSettingCard({ items: group, dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (group: GroupEntryItem[]): string => group[0].label)
        }
        .width('100%')
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
