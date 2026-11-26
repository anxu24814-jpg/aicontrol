// 「设置」二级页壳（2026-11-16 首页布局双形态笔，方案档 §3.8）：侧栏对话形态下侧栏底部
//「设置」入口的落点——内容组件 = SettingsPage 原件零改动（九组卡 + settingGroups 单源），
// 本壳补二级页形。★ 搜索入口（2207 真机回归修，决明要求恢复原机制）：与页签形态同一套
// 「带内假框 ⇄ 收带后右上角键」互斥——页面顶部 = 标题栏下方带内假框（SearchTopBand
// openOnly 档），下滑滚过一带高（48vp）官方动效收带（PageShell A 档滚动联动）+ 右上搜索
// 键出现，回顶恢复；两入口点击都直达既有设置项搜索页。首版「常显搜索圆键重映射」随本笔
// 退役（带位空白且首板块离标题过远的观感即其残留）。
// · 行回调链 = HomeNavActions 同源（无状态编排类——push 目标与页签形态逐项一致）。★ 必在
//   aboutToAppear 重建绑定：自定义组件字段初始化先于父组件参数注入，字段位直接
//   `new HomeNavActions(this.pathStack)` 会捕获 pathStack 的默认空栈且永不更新——2207 真机
//   回归「设置页卡片点了进不了下一页」的根因；aboutToAppear 时参数已注入，重建后全回调
//   push 同一真实路由栈。
// · 收带状态机单源 = SearchTopBand.nextSettingsBandHidden（阈值 48 / 复位 24 滞后带与页签
//   形态同判据）；scroller 自建并交 PageShell 官方滚动感知。
import { PageShell } from '../../common/PageShell';
import { SettingsPage } from './SettingsPage';
import { HomeNavActions } from '../nav/HomeNavActions';
import { TitleBarRoundKey } from '../TitleBarKeys';
import { SearchTopBand, nextSettingsBandHidden } from '../SearchTopBand';

@Component
export struct SettingsPageHost {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入——行回调 push 与搜索页共用）
  pathStack: NavPathStack = new NavPathStack();
  // 设置域导航动作（无状态编排类——构造式与页签形态 HomeNavigation 同源；aboutToAppear
  // 重建绑定真实栈，见文件头「行回调链」注释）
  private actions: HomeNavActions = new HomeNavActions(this.pathStack);
  // 设置页滚动控制器（本形态自建：收带联动交 PageShell.bindToScrollable + SettingsPage
  // 内部 Scroll 挂载，两处同一实例）
  private scroller: Scroller = new Scroller();
  // 收带态（false = 带在、页面顶部、无右上键 / true = 带收起、右上搜索键出现）；唯一写点 =
  // onSettingsScrollOffset 状态机（与页签形态同款，只在变化时写 @State）
  @State private settingsBandHidden: boolean = false;
  // 带内假框哑位词（openOnly 档不可输入不绑词，传 $settingsBandKeyword 仅满足 SearchTopBand
  // @Link 必传契约，恒空不消费）
  @State private settingsBandKeyword: string = '';

  aboutToAppear(): void {
    // 路由栈参数注入后重建动作绑定（根因见文件头；初建实例仅占字段位，未消费即弃）
    this.actions = new HomeNavActions(this.pathStack);
  }

  // 滚动偏移状态机（SettingsPage.onDidScroll 上抛直通；判据单源在 SearchTopBand）
  private onSettingsScrollOffset(offsetY: number): void {
    const next: boolean = nextSettingsBandHidden(offsetY, this.settingsBandHidden);
    if (next !== this.settingsBandHidden) {
      this.settingsBandHidden = next;
    }
  }

  // 标题栏覆盖层：带在 = 空透传层（顶部搜索入口由带内假框承担）；带收起 = 右上搜索圆键
  //（TitleBarRoundKey，ChatTitleBarOverlay 右端「更多」键同形制），点击直达设置项搜索页
  @Builder
  TitleBarOverlay() {
    Row() {
      if (this.settingsBandHidden) {
        TitleBarRoundKey({
          icon: $r('sys.symbol.magnifyingglass'),
          label: '搜索',
          onTap: (): void => {
            this.actions.pushSearch();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .padding({ right: 16 })
    // 覆盖层空白区透传触摸（规范 §4——整栏铺在标题区上方）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 标题栏下方带内假框（openOnly 档——整框点击直达搜索二级页，与页签形态同件同参）
  @Builder
  SettingsSearchBand() {
    SearchTopBand({
      keyword: $settingsBandKeyword,
      openOnly: true,
      placeholder: '搜索设置项',
      onOpen: (): void => {
        this.actions.pushSearch();
      }
    })
  }

  // 内容（坑39：组件内 @Builder 承载，SettingsPage 原件直挂零改动——回调簇走 actions 同源）
  @Builder
  Content() {
    SettingsPage({
      topPad: this.topPad,
      bottomPad: this.bottomPad,
      scroller: this.scroller,
      onScrollOffset: (yOffset: number): void => {
        this.onSettingsScrollOffset(yOffset);
      },
      onOpenProvider: (): void => {
        this.actions.pushProvider();
      },
      onOpenInfo: (): void => {
        this.actions.pushInfo();
      },
      onOpenPrompts: (): void => {
        this.actions.pushPrompts();
      },
      onOpenSkillLibrary: (): void => {
        this.actions.pushSkillLibrary();
      },
      onOpenKnowledgeLibrary: (): void => {
        this.actions.pushKnowledgeLibrary();
      },
      onOpenPreferences: (): void => {
        this.actions.pushPreferences();
      },
      onOpenDataSync: (): void => {
        this.actions.pushDataSync();
      },
      onOpenFunctionalModel: (): void => {
        this.actions.pushFunctionalModel();
      },
      onOpenUsageStats: (): void => {
        this.actions.pushUsageStats();
      },
      onOpenCostStats: (): void => {
        this.actions.pushCostStats();
      },
      onOpenMemory: (): void => {
        this.actions.pushMemory();
      },
      onOpenProactive: (): void => {
        this.actions.pushProactive();
      },
      onOpenStorage: (): void => {
        this.actions.pushStorage();
      },
      onOpenTools: (): void => {
        this.actions.pushTools();
      },
      onOpenWorkspace: (): void => {
        this.actions.pushWorkspace();
      },
      onOpenMount: (): void => {
        this.actions.pushMount();
      },
      onOpenNetwork: (): void => {
        this.actions.pushNetwork();
      },
      onOpenWebService: (): void => {
        this.actions.pushWebService();
      }
    })
  }

  build() {
    PageShell({
      title: '设置',
      titleBarStack: (): void => {
        this.TitleBarOverlay();
      },
      keepStackTitle: true,
      // 带内假框 + 官方收带联动（A 档）：hidden 与官方动效同点切换——带收起时 bandParams
      // 置 undefined、覆盖层键出现；回顶带恢复、键消失
      titleBarBottom: (): void => {
        this.SettingsSearchBand();
      },
      titleBarBottomHidden: this.settingsBandHidden,
      titleBarBottomScroller: this.scroller,
      content: (): void => {
        this.Content();
      }
    })
  }
}
