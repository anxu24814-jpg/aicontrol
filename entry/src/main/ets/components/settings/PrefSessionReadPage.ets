// 偏好设置二级页「会话与阅读」：一级偏好页第 3 行入口的承载页——开关组卡（3 开关：屏幕常亮 /
// 后台回复提醒 / 会话宫格视图〔2026-11-11 新增，落在组卡末位——
// 显示类偏好夹在行为偏好之后是当前序，若需并进前三项显示类须另拍板再动序〕）+ 快捷新建键三档分段卡 +
// 智感握姿跟随右置分段行卡（只对「列表右下」档有效，切离自动关闭、拨开 toast 拦截）。
// 一张行卡形制单源 = SegmentBar.SettingSegmentRowCard；快捷新建键卡非「行」形态（三档文案长），
// 按组卡规范 §1.1 独立成卡，不并入开关组卡。
// 页面骨架由 PageShell 提供；开关即时持久化（AppStorage persistProp 键）无保存动作 →
// 返回走无参 pop、push 不挂 onPop。开关行显示刷新 = 恒单例纪元键 ForEach 键变重建（键含本组
// 开关值，见 sessionGroupKey 注释；坑57 正解）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { SegmentBar, SettingSegmentRowCard } from '../SegmentBar';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_ORANGE } from '../GroupSettingCard';
import { PREF_BG_REPLY_NOTIFY_KEY, PREF_HOLDING_FOLLOW_KEY, PREF_KEEP_SCREEN_ON_KEY, PREF_NEW_SESSION_ENTRY_KEY, PREF_SESSION_CARD_GRID_KEY, NEW_SESSION_ENTRY_TAB_BAR, NEW_SESSION_ENTRY_TAB_ITEM, NEW_SESSION_ENTRY_FLOAT, resolveNewSessionEntry, PREF_HOME_LAYOUT_KEY, HOME_LAYOUT_DRAWER, HOME_LAYOUT_TABS } from '../../common/AppPreferences';
import { chatBgReply } from '../../common/chat/ChatBgReply';
import { SETTING_TITLE_BG_REPLY_NOTIFY, SETTING_TITLE_HOLDING_FOLLOW, SETTING_TITLE_KEEP_SCREEN_ON, SETTING_TITLE_NEW_SESSION_ENTRY, SETTING_TITLE_PREF_SESSION_READ, SETTING_TITLE_SESSION_CARD_GRID } from '../../common/SettingSearch';
import { PageShell } from '../../common/PageShell';

@Component
export struct PrefSessionReadPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  // 会话页屏幕常亮（true = 进会话页设窗口常亮 / false = 系统息屏）。消费方 = ChatPage
  // aboutToAppear 现读 + aboutToDisappear 复位（窗口属性无广播需求）
  @StorageLink(PREF_KEEP_SCREEN_ON_KEY) keepScreenOn: boolean = false;
  // 会话宫格视图（false = 单列列表默认 / true = 两列宫格）。消费方 = ChatSessionList 壳
  // @StorageProp 订阅（切换即重算）与会话卡片渲染分支
  @StorageLink(PREF_SESSION_CARD_GRID_KEY) sessionCardGrid: boolean = false;
  // 后台回复提醒：true = 切后台保活生成并发通知（打开时申请通知授权，被拒回落为关）；
  // 消费方 = ChatBgReply 两闸现读。关闭即时取消在途短时任务与通知；开启时若已有生成在跑补申请
  @StorageLink(PREF_BG_REPLY_NOTIFY_KEY) bgReplyNotify: boolean = false;
  // 智感握姿跟随（只对「列表右下」档的悬浮键有效，切离自动关闭、拨开 toast 拦截）：
  // true = 随左右手握持换边 / false = 恒右。消费方 = SessionNewFab @StorageProp @Watch 自订阅
  @StorageLink(PREF_HOLDING_FOLLOW_KEY) @Watch('onHoldingFollowChanged')
  holdingFollow: boolean = true;
  // 智感握姿段控下标镜像（顺序契约：0 = 关闭 / 1 = 开启；与 onHoldingSegChanged 同序）
  @State @Watch('onHoldingSegChanged') holdingSegIndex: number = 0;
  // 智感握姿分段选项（两值；两值分段不是「行」形态，故独立成卡）
  private holdingItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '关闭' },
    { text: '开启' }
  ]);
  // 快捷新建键（★ 2026-10-30 两档化，决明「关闭这一项去掉——关掉就没有落点了」：'off' 档
  // 退役，存量旧值经 resolveNewSessionEntry 归一为 'tabBar'；★ 2026-10-31 三档化新增
  // 'tabItem'）/ 'tabBar' 页签栏旁圆键（默认）/ 'tabItem' 页签第四项动作位 / 'float' 列表
  // 右下悬浮键——各入口互斥由单键值域结构性保证。消费方 = HomeNavigation +
  // ChatSessionList @StorageProp 订阅
  @StorageLink(PREF_NEW_SESSION_ENTRY_KEY) @Watch('onEntryModeChanged')
  newSessionEntry: string = NEW_SESSION_ENTRY_TAB_BAR;
  // 段控下标镜像（@State + @Watch 双向：用户点段 → 写键；键侧改写 → 补正下标）
  @State @Watch('onEntrySegChanged') entrySegIndex: number = 0;
  // 分段选项（顺序契约见下；与 entryIndexOf / entryValueOf 三处同序——★ 2026-10-30 两档化：
  // 原「关闭」段随档退役、三段收两段；★ 2026-10-31 三档化回三段：0 = 页签栏旁 /
  // 1 = 页签第四项 / 2 = 列表右下）
  private entryItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '页签栏旁' },
    { text: '页签第四项' },
    { text: '列表右下' }
  ]);
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 系统颜色模式（卡片底色；EntryAbility 已接线写键，深浅色切换自动刷新）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // ★ 首页布局（双形态笔灰化判据）：宫格视图与快捷新建键两卡仅底栏形态生效——侧栏形态下
  // 两卡交互拦截 + 注明「仅底栏形态可用」（方案档 §3.10 拍板；@StorageProp = 热切即时跟随）
  @StorageProp(PREF_HOME_LAYOUT_KEY) homeLayout: string = HOME_LAYOUT_TABS;

  // 灰化判据（当前是否侧栏形态——两卡拦截共用）
  private isDrawerLayout(): boolean {
    return this.homeLayout === HOME_LAYOUT_DRAWER;
  }

  aboutToAppear(): void {
    // 快捷新建键分段对齐（脏值/退役旧值 'off' 经 resolveNewSessionEntry 落 'tabBar' = 下标 0）
    this.entrySegIndex = this.entryIndexOf(this.newSessionEntry);
    // 智感握姿依赖归正：旧备份/外部写入可能留下「非列表右下档 + 智感开」非法组合——进页即关
    if (this.newSessionEntry !== NEW_SESSION_ENTRY_FLOAT && this.holdingFollow) {
      this.holdingFollow = false;
    }
    this.holdingSegIndex = this.holdingFollow ? 1 : 0;
  }

  // 快捷新建键值 ↔ 分段下标（三处同序：entryItems / entryIndexOf / entryValueOf；脏值与退役
  // 旧值 'off' 经归一收编为 'tabBar' = 下标 0——★ 2026-10-31 三档化顺序契约）
  private entryIndexOf(value: string): number {
    const entry: string = resolveNewSessionEntry(value);
    return entry === NEW_SESSION_ENTRY_FLOAT ? 2 : entry === NEW_SESSION_ENTRY_TAB_ITEM ? 1 : 0;
  }

  private entryValueOf(index: number): string {
    return index === 1 ? NEW_SESSION_ENTRY_TAB_ITEM : index === 2 ? NEW_SESSION_ENTRY_FLOAT
      : NEW_SESSION_ENTRY_TAB_BAR;
  }

  // 用户点分段 → 写快捷新建键（同值不回写防递归）；★ 双形态笔：侧栏形态下快捷新建键无效
  //（新建入口固定 = 侧栏底部大键 + 聊天页「更多」菜单首项，方案档 §4.1-10）——拦截写值、
  // toast 提示并回弹分段（entrySegIndex 拉回键当前真值下标，变更即通知驱动重渲）
  private onEntrySegChanged(): void {
    if (this.isDrawerLayout()) {
      this.entrySegIndex = this.entryIndexOf(this.newSessionEntry);
      this.getUIContext().getPromptAction().showToast({ message: '仅底栏形态可用' });
      return;
    }
    const value: string = this.entryValueOf(this.entrySegIndex);
    if (value !== this.newSessionEntry) {
      this.newSessionEntry = value;
    }
  }

  // 键第二写方（备份导入恢复 / 脏值）→ 补正分段下标（不回写键）；切离「列表右下」即自动关智感
  private onEntryModeChanged(): void {
    const idx: number = this.entryIndexOf(this.newSessionEntry);
    if (idx !== this.entrySegIndex) {
      this.entrySegIndex = idx;
    }
    if (this.newSessionEntry !== NEW_SESSION_ENTRY_FLOAT && this.holdingFollow) {
      this.holdingFollow = false;
    }
  }

  // 智感握姿分段：只有快捷新建键 = 列表右下时才允许开启——不可选弹 toast 拦截并回弹
  //（拨了不算数，界面拉回真值）
  private onHoldingSegChanged(): void {
    if (this.holdingSegIndex === 1) {
      if (this.newSessionEntry !== NEW_SESSION_ENTRY_FLOAT) {
        this.getUIContext().getPromptAction().showToast({
          message: '把快捷新建键设为列表右下后才能开启'
        });
        this.holdingSegIndex = 0;
        return;
      }
      if (!this.holdingFollow) {
        this.holdingFollow = true;
      }
      return;
    }
    if (this.holdingFollow) {
      this.holdingFollow = false;
    }
  }

  // 智感键第二写方（备份导入 / 自动关闭回落）→ 补正分段下标（不回写键）
  private onHoldingFollowChanged(): void {
    const idx: number = this.holdingFollow ? 1 : 0;
    if (idx !== this.holdingSegIndex) {
      this.holdingSegIndex = idx;
    }
  }

  // ── 本页开关组卡（3 开关；行副标题照旧）。智感握姿已移出组卡改两值分段卡（组卡规范 §1.1）；
  // 卡内各行统一橙（卡内主色并列取首行）──
  private sessionGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.sun_max'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_KEEP_SCREEN_ON,
        secondary: '会话页保持常亮',
        toggleValue: (): boolean => this.keepScreenOn,
        onToggle: (isOn: boolean): void => {
          this.keepScreenOn = isOn;
        }
      },
      {
        icon: $r('sys.symbol.bell'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_BG_REPLY_NOTIFY,
        secondary: '切后台继续生成并发通知',
        toggleValue: (): boolean => this.bgReplyNotify,
        onToggle: (isOn: boolean): void => {
          this.applyBgReplyToggle(isOn);
        }
      },
      {
        icon: $r('sys.symbol.square_grid_2x2'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_SESSION_CARD_GRID,
        // ★ 双形态笔：侧栏形态下宫格无效（侧栏列表固定精简单行档，方案档 §2.4）——副标题
        // 换注明文案、开关拦截回弹
        secondary: this.isDrawerLayout() ? '仅底栏形态可用' : '开启后改两列宫格',
        toggleValue: (): boolean => this.sessionCardGrid,
        onToggle: (isOn: boolean): void => {
          if (this.isDrawerLayout()) {
            this.getUIContext().getPromptAction().showToast({ message: '仅底栏形态可用' });
            return;
          }
          this.sessionCardGrid = isOn;
        }
      }
    ];
  }

  // 后台回复提醒拨动：开 = 先申请通知授权（打开才弹窗）——授予才开启并通知账本补申请在途
  // 保活；拒绝回落为关并提示（避免「开关开着却什么都不会发生」）。关 = 立即取消在途短时任务
  // 与通知。授权弹窗失败/无上下文一律按未获处理。开启意向先乐观写 @StorageLink——被拒回落的
  // false 复位靠组卡重建键拉回 Toggle 真值（否则 Toggle 停在假 ON 态）
  private applyBgReplyToggle(isOn: boolean): void {
    if (!isOn) {
      this.bgReplyNotify = false;
      chatBgReply.onSwitchChanged(false);
      return;
    }
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    this.bgReplyNotify = true;
    chatBgReply.requestEnableNotify(context).then((granted: boolean): void => {
      if (this.departed) {
        return;
      }
      if (granted) {
        chatBgReply.onSwitchChanged(true);
      } else {
        this.bgReplyNotify = false;
        this.getUIContext().getPromptAction().showToast({
          message: '未获得通知授权，后台回复提醒保持关闭'
        });
      }
    });
  }

  // 组卡重建键（键含本组开关值：任一开关变动即键变 → 组卡重建 → Toggle 拉新值；组卡 items
  // 普通成员不随父重渲更新——坑57 正解。bgReplyNotify 进键，被拒回落也靠它刷 Toggle 真值；
  // ★ 双形态笔：布局值进键——热切/灰化切换即重建刷宫格行注明文案与拦截回弹态）
  private sessionGroupKey(): string {
    return [String(this.keepScreenOn), String(this.sessionCardGrid),
      String(this.bgReplyNotify), String(this.isDrawerLayout())].join('|');
  }

  build() {
    // 页面骨架统一由 PageShell 提供；标题 = 行名常量（与一级页入口行单源）
    PageShell({
      title: SETTING_TITLE_PREF_SESSION_READ,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 开关组卡（恒单例纪元键 ForEach：键变重建刷开关，见 sessionGroupKey 注释）
        ForEach([this.sessionGroupKey()], (_key: string) => {
          GroupSettingCard({ items: this.sessionGroup(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
        }, (key: string): string => key)
        // 快捷新建键卡（三档分段 = 选择/内容卡形态；说明小字在按钮行上方——
        // 功能设置卡布局次序条。各处快捷入口互斥由单键值域保证。★ 2026-10-30 两档化：说明句
        // 去关闭语义，原文案「关闭后两处都不显示」随档退役；★ 2026-10-31 三档化新增页签
        // 第四项段，说明句「选择新建会话键显示的位置」语义不变沿用）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_NEW_SESSION_ENTRY)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text(this.isDrawerLayout() ? '仅底栏形态可用' : '选择新建会话键显示的位置')
              .fontSize(12)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Column() {
            SegmentBar({
              items: this.entryItems,
              selectedIndex: $entrySegIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 智感握姿跟随卡（右置分段行卡，SettingSegmentRowCard 单源件；只对「列表右下」档有效，
        // 切离自动关闭 + 拨开 toast 拦截——门控见 onHoldingSegChanged 注释）
        SettingSegmentRowCard({
          title: SETTING_TITLE_HOLDING_FOLLOW,
          subtitle: '把快捷新建键设为列表右下后才能开启',
          items: this.holdingItems,
          selectedIndex: $holdingSegIndex
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

  aboutToDisappear(): void {
    this.departed = true;
  }
}
