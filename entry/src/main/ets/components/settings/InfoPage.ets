// 「更多信息」二级页：7 跳转条目分 3 板块组卡——帮助与支持（帮助中心/反馈与建议）/ 隐私与权限（权限信息/
// 隐私政策）/ 应用信息（运行日志/请求日志/关于），板块标题 = 公共 SectionHeader。组卡与设置页同源
//（GroupSettingCard 跳转行；原 HDS HdsListItemCard 双分支已整体退役）。行点击 = openCard 收口：先
// recordRecentUse（搜索页「最近使用」口径）再 push 同名二级页。页面骨架：壳在 nav/PageMapBuilder.ets，
// 本组件只提供内容；pathStack 由壳传入。
import { SECTION_GAP, SECTION_HEADER_GAP } from '../../common/Theme';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE, SETTING_ICON_GRAY, SETTING_ICON_ORANGE } from '../GroupSettingCard';
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

// 板块数据（标题 + 组卡行；类型化返回——ArkTS 禁 build 内匿名字面量数组，10605038；
// 副标题行 2026-11-01 退役故无 subtitle 字段）
interface InfoSectionData {
  title: string;
  items: GroupEntryItem[];
}

@Component
export struct InfoPage {
  // 顶部/底部留白（vp，导航壳下发：topPad = 首卡落在标题栏渐变模糊蒙层下方；bottomPad = 底部避让区高）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：条目点击 pushPathByName 入栈三级页
  pathStack: NavPathStack = new NavPathStack();

  // 三板块组卡（分组/组序 = 语义：帮助与支持 / 隐私与权限 / 应用信息；图标经 SDK resources.txt 核实；
  // 板块卡内同色——帮助蓝 / 隐私橙 / 应用信息灰；onClick = openCard 收口记「最近使用」+ push）
  private infoSections(): InfoSectionData[] {
    return [
      {
        title: '帮助与支持',
        items: [
          {
            icon: $r('sys.symbol.questionmark_circle'),
            iconBg: SETTING_ICON_BLUE,
            label: SETTING_TITLE_HELP_CENTER,
            secondary: '查看功能与用法说明',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_HELP_CENTER, ROUTE_HELP_CENTER_PAGE)
            }
          },
          {
            icon: $r('sys.symbol.paperplane_fill'),
            iconBg: SETTING_ICON_BLUE,
            label: SETTING_TITLE_FEEDBACK,
            secondary: '把问题或建议发给开发者',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_FEEDBACK, ROUTE_FEEDBACK_PAGE)
            }
          }
        ]
      },
      {
        title: '隐私与权限',
        items: [
          {
            icon: $r('sys.symbol.checkmark_shield'),
            iconBg: SETTING_ICON_ORANGE,
            label: SETTING_TITLE_PERMISSION,
            secondary: '查看各权限的用途与授予状态',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_PERMISSION, ROUTE_PERMISSION_PAGE)
            }
          },
          {
            icon: $r('sys.symbol.lock'),
            iconBg: SETTING_ICON_ORANGE,
            label: SETTING_TITLE_PRIVACY_POLICY,
            secondary: '了解个人信息保护与数据使用',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_PRIVACY_POLICY, ROUTE_PRIVACY_POLICY_PAGE)
            }
          }
        ]
      },
      // 应用信息（行副标题报实际内容与记录面，不复述板块名/行名）
      {
        title: '应用信息',
        items: [
          {
            icon: $r('sys.symbol.list_bullet'),
            iconBg: SETTING_ICON_GRAY,
            label: SETTING_TITLE_RUN_LOG,
            secondary: '查看报错与运行异常记录',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_RUN_LOG, ROUTE_LOG_PAGE)
            }
          },
          {
          // 请求日志：排查「连不上 / 发不出 / 用不了」时的请求现场
          icon: $r('sys.symbol.arrow_left_arrow_right'),
            iconBg: SETTING_ICON_GRAY,
            label: SETTING_TITLE_REQ_LOG,
            secondary: '查看应用发出的网络请求记录',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_REQ_LOG, ROUTE_REQ_LOG_PAGE)
            }
          },
          // 「出站记录」行已退役（与「请求日志」同为跳请求日志页的入口、并排无可见差异；HTTP 审计走
          // 请求日志页「只看 HTTP 请求」筛选档）——防回游
          {
            icon: $r('sys.symbol.info_circle'),
            iconBg: SETTING_ICON_GRAY,
            label: SETTING_TITLE_ABOUT,
            secondary: '版本信息与相关声明',
            chevron: true,
            onClick: (): void => {
              this.openCard(SETTING_TITLE_ABOUT, ROUTE_ABOUT_PAGE)
            }
          }
        ]
      }
    ];
  }

  // 行点击统一收口：先记「最近使用」（搜索跳转 + 卡片点击两处记录，展示经注册表反查）再 push——SettingsPage
  // openCard 同构
  private openCard(recordTitle: string, page: string): void {
    recordRecentUse(recordTitle);
    this.pathStack.pushPathByName(page, null);
  }

  build() {
    // 页面骨架统一由 PageShell 提供（原直壳 titleBar 为入栈快照、档位变化不实时刷新，与外观页同病同修）；
    // PageShell 含 HDS/回退双分支 + PageBackground + onShown 内置
    PageShell({
      title: SETTING_TITLE_MORE_INFO,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight 会塌陷——同款坑）
    Scroll() {
      Column({ space: SECTION_GAP }) {
        // 三板块（每板块 = 公共 SectionHeader + GroupSettingCard；ForEach key = 板块标题〔互不重复〕；
        // 间距三档走 Theme 常量——板块间 SECTION_GAP 20 / 标题下 SECTION_HEADER_GAP 6）
        ForEach(this.infoSections(), (section: InfoSectionData) => {
          Column({ space: SECTION_HEADER_GAP }) {
            SectionHeader({ title: section.title })
            GroupSettingCard({ items: section.items, dividerLeft: DIVIDER_LEFT_ICON_LARGE })
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
    .scrollBar(BarState.Off)
  }
}
