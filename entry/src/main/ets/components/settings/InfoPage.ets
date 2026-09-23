// 「更多信息」二级页（2026-08-29 M2c 迁骨架；M3 改造为 dshinhm 跳转卡形态；★ 2026-09-08
// 组卡化——决明指令「梳理语义换序合卡，样式参考设置页组卡」；2026-09-12 应用信息板块
// 增「自检」行卡成 7 条目、同日决明指令该行卡迁出至设置页单独卡——本页余 6 条目；
// ★ 2026-09-23 请求日志笔「应用信息」板增「请求日志」行卡——本页 7 条目）：
// 7 跳转条目分 3 板块
// 组卡——帮助与支持（帮助中心/反馈与建议）/ 隐私与权限（权限信息/隐私政策）/ 应用信息
//（运行日志/请求日志/关于），板块标题 = 公共 SectionHeader（Theme SECTION_TITLE_FONTSIZE 规范）。
// 组卡与设置页同源（GroupSettingCard 跳转行）；原 HDS HdsListItemCard 双分支
//（HDSComponent.Full 门槛 + 回退自制卡）整体退役——设置页组卡化先例。
// 行点击 = openCard 收口：recordRecentUse（搜索页「最近使用」dshinhm 口径——搜索跳转 +
// 卡片点击两处记录）后 push 同名二级页。注：组卡化前本页跳转不记「最近使用」（设置页
// openCard 先例漏接），2026-09-08 组卡化顺带对齐。
// M2c 版版本/来源两行展示的迁移去向：版本→关于页版本卡、来源→关于页应用名下小字（领导
// 验收过的信息不丢，见变更记录 M3；2026-08-29 决明拍板来源小字已自关于页移除，信息不再
// 保留）。
// 页面骨架：壳在 nav/PageMapBuilder.ets（双分支 + 根透明 + PageBackground 铺底 + TITLE_S
// 标题栏），本组件只提供内容；pathStack 由壳传入（条目 push 用）。
import { CARD_SPACING } from '../../common/Theme';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { PageShell } from '../../common/PageShell';
import {
  SETTING_TITLE_ABOUT,
  SETTING_TITLE_FEEDBACK,
  SETTING_TITLE_HELP_CENTER,
  SETTING_TITLE_MORE_INFO,
  SETTING_TITLE_PERMISSION,
  SETTING_TITLE_PRIVACY_POLICY,
  SETTING_TITLE_REQ_LOG,
  SETTING_TITLE_RUN_LOG
} from '../../common/SettingSearch';
import { recordRecentUse } from '../../common/SettingSearch';
import {
  ROUTE_ABOUT_PAGE,
  ROUTE_FEEDBACK_PAGE,
  ROUTE_HELP_CENTER_PAGE,
  ROUTE_LOG_PAGE,
  ROUTE_PERMISSION_PAGE,
  ROUTE_PRIVACY_POLICY_PAGE,
  ROUTE_REQ_LOG_PAGE
} from '../../common/RouteNames';

// 板块数据（标题 + 副标题 + 组卡行；类型化返回——ArkTS 禁 build 内匿名字面量数组，
// 10605038）
interface InfoSectionData {
  title: string;
  subtitle: string;
  items: GroupEntryItem[];
}

@Component
export struct InfoPage {
  // 顶部/底部留白（vp，导航壳下发：topPad = 首卡落在标题栏渐变模糊蒙层下方；bottomPad =
  // 底部避让区高——二级页全屏覆盖页签）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：条目点击 pushPathByName 入栈三级页
  pathStack: NavPathStack = new NavPathStack();

  // 三板块组卡（2026-09-08 组卡化；分组/组序 = 语义：帮助与支持 / 隐私与权限 / 应用信息；
  // 图标 = SDK 符号表 resources.txt 已核实；onClick = openCard 收口记「最近使用」+ push）
  private infoSections(): InfoSectionData[] {
    return [
      {
        title: '帮助与支持',
        subtitle: '查使用说明或向开发者反馈',
        items: [
          {
            icon: $r('sys.symbol.questionmark_circle'),
            label: SETTING_TITLE_HELP_CENTER,
            secondary: '查看功能与用法说明',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_HELP_CENTER, ROUTE_HELP_CENTER_PAGE)
            }
          },
          {
            icon: $r('sys.symbol.paperplane_fill'),
            label: SETTING_TITLE_FEEDBACK,
            secondary: '向开发者反馈问题与建议',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_FEEDBACK, ROUTE_FEEDBACK_PAGE)
            }
          }
        ]
      },
      {
        title: '隐私与权限',
        subtitle: '查看权限与个人信息保护',
        items: [
          {
            icon: $r('sys.symbol.checkmark_shield'),
            label: SETTING_TITLE_PERMISSION,
            secondary: '查看应用权限与状态',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_PERMISSION, ROUTE_PERMISSION_PAGE)
            }
          },
          {
            icon: $r('sys.symbol.lock'),
            label: SETTING_TITLE_PRIVACY_POLICY,
            secondary: '了解个人信息保护与数据使用',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_PRIVACY_POLICY, ROUTE_PRIVACY_POLICY_PAGE)
            }
          }
        ]
      },
      {
        title: '应用信息',
        subtitle: '查看运行日志、请求记录与应用信息',
        items: [
          {
            icon: $r('sys.symbol.list_bullet'),
            label: SETTING_TITLE_RUN_LOG,
            secondary: '查看应用运行日志',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_RUN_LOG, ROUTE_LOG_PAGE)
            }
          },
          {
            // 请求日志（2026-09-23 请求日志笔）：排查「连不上 / 发不出 / 用不了」时的请求现场
            icon: $r('sys.symbol.arrow_left_arrow_right'),
            label: SETTING_TITLE_REQ_LOG,
            secondary: '查看网络请求记录',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_REQ_LOG, ROUTE_REQ_LOG_PAGE)
            }
          },
          {
            icon: $r('sys.symbol.info_circle'),
            label: SETTING_TITLE_ABOUT,
            secondary: '版本信息与相关声明',
            onClick: (): void => {
              this.openCard(SETTING_TITLE_ABOUT, ROUTE_ABOUT_PAGE)
            }
          }
        ]
      }
    ];
  }

  // 行点击统一收口：先记「最近使用」（dshinhm 口径：搜索跳转 + 卡片点击两处记录，展示经
  // 注册表反查）再 push 目标二级页——SettingsPage openCard 同构
  private openCard(recordTitle: string, page: string): void {
    recordRecentUse(recordTitle);
    this.pathStack.pushPathByName(page, null);
  }

  build() {
    // 页面骨架统一由 PageShell 提供（2026-09-07 迁——原 PageMapBuilder 直壳 titleBar 为
    // 入栈快照，档位变化不实时刷新，与外观页同病同修）；PageShell 已含 HDS/回退双分支 +
    // PageBackground + onShown(bumpBgShownEpoch) 内置
    PageShell({
      title: SETTING_TITLE_MORE_INFO,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——ProviderPage 同款坑）；官方 Scroll + edgeEffect(Spring) 边缘回弹
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 三板块（2026-09-08 组卡化：每板块 = 公共 SectionHeader + GroupSettingCard；
        // ForEach key = 板块标题（三板块标题互不重复）；组卡行 key = 条目标题静态）
        ForEach(this.infoSections(), (section: InfoSectionData) => {
          Column({ space: 6 }) {
            SectionHeader({ title: section.title, subtitle: section.subtitle })
            GroupSettingCard({ items: section.items })
          }
          .width('100%')
        }, (section: InfoSectionData): string => section.title)
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
  }
}
