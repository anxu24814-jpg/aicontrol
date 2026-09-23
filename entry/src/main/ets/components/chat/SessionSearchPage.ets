// 会话搜索二级页（2026-09-08 会话搜索改版，决明指令「会话搜索要同设置搜索一样点击 push
// 二级页，之前全都放一级页了，改」）：搜索 UI 自 ChatSessionList 一级页内嵌态整体迁出——
// 对话页签标题栏搜索键 → push 本页（HomeNavigation.newSessionSearch）。形态逐段对照设置
// 搜索 SearchPage（自包壳 + 提交式 + 记录区/结果区/空态三态 + 防循环），差异点 = 数据源
// 会话行（DB 实时行非静态注册表）：
//   · 范围：当前助手名下全部会话（列表页「全部/收藏」分段不随迁——拍板 = 搜索跨全量；
//     ACTIVE_ASSISTANT_KEY + historyFilterIds 过滤口径同 ChatSessionList.reload 平移）；
//   · 提交式（拍板「同设置搜索」）：Search 组件 onSubmit/searchButton/历史词条点击三入口
//     走 applySearch（keyword 回显 + filterRows 派生 + submitted 置位 + 记历史）；onChange
//     清空回未提交态（记录区）。与旧一级页「输入即实时过滤」差异点 = 提交才出结果；
//   · 数据刷新：订阅 SESSION_LIST_RELOAD_KEY（ChatSessionList 同键同消费形态）——打开
//     会话后 ChatPage pop/replace 广播（ChatPage aboutToDisappear 非隐私分支自增），返回
//     本页自动重拉；submitted 态下 reload 落定后用当前 keyword 重算 results（提交式快照
//     不是静态死数据——会话被改名/删除后结果跟随真实数据，旧实时派生语义的等价保障）；
//   · 打开会话必走 onOpenSession 上行（PageMapBuilder 注入 HomeNavigation.openSession
//     闭包）：ChatPage 的 isPrivate 取宿主 activePrivate 快照，该值只在 openSession/
//     newConversation 复位 false——隐私会话 pop 后残留 true，本页若自接
//     pushPathByName(ROUTE_CHAT_PAGE, id) 会把普通会话误开隐私模式；且 ChatPage 页内
//     「新建会话」replacePath 同带 string param，分支无法区分（详注见 PageMapBuilder 头）；
//   · 记录区（搜索历史/最近进入）复用 SessionSearchPanels 两板块组件零改动（历史 = 自读
//     自清 + onSearch 上抛直通 applySearch；最近进入 = id 源 AppStorage、标题/时间由本页
//     rows 反查——recentConvItems 自 ChatSessionList 平移，反查不到 = 已删/非当前助手，
//     跳过不清键，脏 id 防残留）。
// 数据层 = common/SessionSearch.ets（历史 5 条/10 字、最近进入 3 条上限，读写双侧收敛）；
// 记录时机：历史 = 提交式（applySearch 内）；最近进入 = 打开会话实际放行才记（加密认证
// 通过才算——openConv 平移 ChatSessionList.handleOpenCard 放行点语义，两消费方先例）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { HdsListItemCard, HdsNavDestination, PrefixIcon, TitleSize } from '@kit.UIDesignKit';
import { ConversationRow, queryConversations, whenReady } from '../../common/store/ChatDb';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, historyFilterIds } from '../../common/store/AssistantDb';
import { SESSION_LIST_RELOAD_KEY } from './ChatSessionList';
import { biometricGate, BiometricGateOutcome, BiometricGateResult, gateOutcomeMessage } from '../../common/BiometricGate';
import {
  MAX_SESSION_RECENT_CONV,
  recordSessionRecentConv,
  recordSessionSearchHistory,
  SESSION_RECENT_CONV_KEY,
  SESSION_SEARCH_HISTORY_KEY
} from '../../common/SessionSearch';
import { SessionHistorySection, SessionRecentItem, SessionRecentSection, formatConvTime } from './SessionSearchPanels';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, hdsTitleBarOptions, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor } from '../../common/Theme';

@Component
export struct SessionSearchPage {
  // 顶部留白（vp，导航壳下发）：HDS 路径滚动内容顶部留白，首项静止时落在渐变模糊蒙层
  // 下方（同其它二级页）；回退路径壳传 0
  @Prop topPad: number = 0;
  // 页面底部留白（vp，导航壳下发——底部避让区让位）
  @Prop bottomPad: number = 0;
  // 打开会话编排回调（HomeNavigation.openSession 闭包：复位隐私标记 + push ChatPage）。
  // ★ 本页所有「进入会话」动作（结果卡/最近进入卡）必须经它，禁自接 push ROUTE_CHAT_PAGE
  onOpenSession: (conversationId: string) => void = (conversationId: string) => {
  };
  // 系统颜色模式（深浅色切换自动刷新卡片/词条配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（搜索框材质随沉浸光感总档，
  // 先例 = SearchPage 搜索框，见 common/ImmersiveLevel.ets）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：仅回退路径消费——HDS 路径搜索框嵌标题栏（stackBuilder，属材质生效
  // 区）恒光感不受本开关影响；回退路径搜索框在内容区顶部（受影响区），true = 官方灰实
  // 底 / false = REGULAR 材质（SearchPage 同参）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 会话列表重拉广播（ChatPage pop/replace 后自增——重拉标题/删会话等；ChatSessionList
  // 同键同消费形态，见该文件头键注释）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onReloadTick') reloadTick: number = 0;
  // 搜索历史/最近进入 id（@StorageLink 仅用于「未提交态」空态判定与最近进入反查——板块
  // 组件各自 @StorageLink 自读自清，记录/清空走 SessionSearch 函数写 AppStorage 本处自动
  // 刷新，SearchPage 同构姿势）
  @StorageLink(SESSION_SEARCH_HISTORY_KEY) searchHistory: string[] = [];
  @StorageLink(SESSION_RECENT_CONV_KEY) recentConvIds: string[] = [];
  // 当前助手名下全部会话行（aboutToAppear/广播两入口全量查询；搜索过滤 = 本数组内存
  // 派生，本地库毫秒级无分页——ChatSessionList 同款全量拍板）
  @State private rows: ConversationRow[] = [];
  // 首拉完成闸（同 ChatSessionList：false = 首次查询在途，防初值空态闪现）
  @State private loaded: boolean = false;
  // 查询失败提示（DB 未就绪/读库失败——P0-1 不静默）
  @State private hintText: string = '';
  // 输入中的关键词（Search 组件 $$ 双向绑定；历史词条点击回填也走它）
  @State private keyword: string = '';
  // 是否已提交搜索（提交式设计：false = 记录区；true = 结果区——SearchPage 同款）
  @State private submitted: boolean = false;
  // 本次提交的结果（filterRows 派生产物整体替换，有界——上限 = rows 条数）
  @State private results: ConversationRow[] = [];
  // 官方 HDS 导航可用性（与 HomeNavigation 根容器同一能力位）：决定搜索框位置——HDS
  // 嵌标题栏（stackBuilder 覆盖层）/ 回退在内容区顶部
  private hdsAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
  // 官方 HDS 列表项卡片可用性（要求 HDSComponent.Full，比 Core 更严格）：决定结果/最近
  // 卡用官方 HdsListItemCard / 回退自制卡
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  aboutToAppear(): void {
    this.reload();
  }

  onReloadTick(): void {
    this.reload();
  }

  // 全量查询当前助手名下会话（同 ChatSessionList.reload 口径：whenReady 守卫冷启动竞态，
  // active 键入口同步读；失败 hintText 提示不静默）；成功落定后 submitted 态下重算
  // results——返回本页时结果随真实数据刷新（设计说明见文件头「数据刷新」条）
  private reload(): void {
    whenReady().then((ok: boolean): void => {
      if (!ok) {
        this.hintText = '数据库初始化失败，请重启应用重试';
        return;
      }
      const activeId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
      queryConversations(historyFilterIds(activeId))
        .then((rows: ConversationRow[]): void => {
          this.rows = rows;
          this.loaded = true;
          if (this.submitted) {
            this.results = this.filterRows(this.keyword);
          }
        })
        .catch((e: Object): void => {
          this.hintText = '会话列表读取失败：' + (e as Error).message;
        });
    });
  }

  // 标题子串过滤（rows 内存派生，不动时间序；大小写不敏感双侧 toLowerCase；空词返回空
  // ——applySearch 首行已防空，此为防御）：ChatSessionList.visibleRows 搜索段口径平移
  private filterRows(kw: string): ConversationRow[] {
    const keyword: string = kw.trim().toLowerCase();
    if (keyword === '') {
      return [];
    }
    return this.rows.filter((row: ConversationRow): boolean =>
      row.title.toLowerCase().includes(keyword));
  }

  // 提交搜索（onSubmit / searchButton / 历史词条点击统一入口——SearchPage.doSearch 同构）：
  // keyword 回显（$$ 双向绑定）+ 结果整体替换 + 切结果区 + 记历史（记录时机 = 提交式，
  // 历史去重移头在 SessionSearch 内收敛）
  private applySearch(term: string): void {
    const kw: string = term.trim();
    if (kw === '') {
      return;
    }
    this.keyword = kw;
    this.results = this.filterRows(kw);
    this.submitted = true;
    recordSessionSearchHistory(kw);
  }

  // 打开会话守卫（ChatSessionList.handleOpenCard 平移——两个消费方先例可接受）：加密会话
  // 先过官方生物识别，通过才记最近进入 + 上行打开（每次进入都验证，不维持解锁态）；
  // 未加密直通；取消静默、失败按原因提示不进入（BiometricGate.gateOutcomeMessage 分文案）
  private openConv(row: ConversationRow): void {
    if (!row.locked) {
      recordSessionRecentConv(row.id);
      this.onOpenSession(row.id);
      return;
    }
    biometricGate('验证身份，进入加密会话')
      .then((gate: BiometricGateResult): void => {
        if (gate.outcome === BiometricGateOutcome.PASSED) {
          recordSessionRecentConv(row.id);
          this.onOpenSession(row.id);
          return;
        }
        const message: string = gateOutcomeMessage(gate);
        if (message !== '') {
          this.getUIContext().getPromptAction().showToast({ message: message });
        }
      });
  }

  // 最近进入条目反查（ChatSessionList.recentConvItems 平移）：持久化存 id，展示按本页
  // rows 反查标题/时间；反查不到 = 已删或非当前助手名下，跳过不清键（防持久化残留脏 id，
  // SettingSearch 同款姿势）；标题空兜底「新对话」与列表卡展示一致
  private recentConvItems(): SessionRecentItem[] {
    const items: SessionRecentItem[] = [];
    const limit: number = Math.min(this.recentConvIds.length, MAX_SESSION_RECENT_CONV);
    for (let i = 0; i < limit; i++) {
      const id: string = this.recentConvIds[i];
      const row: ConversationRow | undefined =
        this.rows.find((r: ConversationRow): boolean => r.id === id);
      if (row !== undefined) {
        items.push({
          id: row.id,
          title: row.title !== '' ? row.title : '新对话',
          timeText: formatConvTime(row.updatedAt)
        });
      }
    }
    return items;
  }

  // 最近进入卡片点击（板块上抛 id）：rows 反查命中才进入（已删防御——展示侧本已跳过，
  // 兜底不静默路径之外的安全网）
  private openRecentConv(id: string): void {
    const row: ConversationRow | undefined =
      this.rows.find((r: ConversationRow): boolean => r.id === id);
    if (row !== undefined) {
      this.openConv(row);
    }
  }

  // 结果项行卡（最近进入卡同形态——SearchPage.ResultCard/SearchSections.RecentCard 各写
  // 各的先例，不跨文件抽卡）：官方 HdsListItemCard 前缀 message 符号 + 标题 primaryText +
  // 时间副行 secondaryText；宽度不设 width（官方示例姿势）= 容器 100% − 内部 16vp×2 =
  // CARD_PANEL_WIDTH 与记录区天然对齐；回退路径（无 HDS Full 能力）自制卡同构。
  // ForEach 键含 title/time 后缀（坑16 族：reload 后键不变则卡片构造快照不刷——键变重建
  // 防重拉后标题/时间陈旧，ChatSessionList 卡片键同款机制）
  @Builder
  ResultCard(row: ConversationRow) {
    if (this.hdsListCardAvailable) {
      HdsListItemCard({
        prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.message') } }),
        textItem: {
          primaryText: { text: row.title !== '' ? row.title : '新对话' },
          secondaryText: { text: formatConvTime(row.updatedAt) }
        },
        cardBorderRadius: 16,
        onClick: () => {
          this.openConv(row);
        }
      })
    } else {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(20)
            .fontColor([cardDescColor()])
          Column({ space: 4 }) {
            Text(row.title !== '' ? row.title : '新对话')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(formatConvTime(row.updatedAt))
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
      }
      .width(CARD_PANEL_WIDTH)
      .borderRadius(16)
      .backgroundColor(cardBg(this.appColorMode))
      .onClick(() => {
        this.openConv(row);
      })
    }
  }

  // 空态提示（无结果 / 首次进入引导共用）：官方放大镜符号 + 主/副文案垂直居中（SearchPage
  // EmptyHint 同款形态——纯文字+符号组件，两路径天然一致）
  @Builder
  EmptyHint(main: string, sub: string) {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(24)
        .fontColor([cardDescColor()])
      Text(main)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
      Text(sub)
        .fontSize(14)
        .fontColor(cardDescColor())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 32 })
  }

  // 搜索框本体（两路径共用：HDS 内嵌标题栏 / 回退在内容区顶部）——SearchPage.SearchBox
  // 逐参数同构：
  // defaultFocus(true) 进页自动获焦 + 拉起输入法（@since 9，NavDestination 层级页面生效；
  // ★ 二级页化红利 = 官方 defaultFocus 语义适用范围，取代旧一级页内嵌态的 requestFocus
  // hack——ChatSessionList 文件头 2026-09-08 焦点结论对照）；
  // searchButton 框尾「搜索」文字钮（点击同时触发 onSubmit，d.ts 核实）；
  // 键盘搜索键 = EnterKeyType.Search（Search 默认值，无需显式设）；
  // 高度 40vp 与标题栏返回键对齐；宽度 100% 由外层容器约束；
  // 材质双态：HDS 路径（标题栏，生效区）= 恒光感 REGULAR 随沉浸光感总档；回退路径（内容
  // 区，受影响区）= contentFallback 开关实底 comp_fallback_gray / 光感 REGULAR（SearchPage
  // 同款落地）；★ 清空输入回记录区（onChange 内 submitted 复位——提交式搜索设计，非空
  // 修改不自动重搜）
  @Builder
  SearchBox() {
    Search({ value: $$this.keyword, placeholder: '搜索会话' })
      .searchButton('搜索')
      .defaultFocus(true)
      .backgroundColor(!this.hdsAvailable && this.contentFallback ?
        $r('app.color.comp_fallback_gray') : Color.Transparent)
      .systemMaterial(!this.hdsAvailable && this.contentFallback ? uiMaterial.Material.empty :
        resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, false))
      .width('100%')
      .height(40)
      .onChange((value: string) => {
        if (value.trim() === '') {
          this.submitted = false;
          this.results = [];
        }
      })
      .onSubmit((value: string) => {
        this.applySearch(value);
      })
  }

  // 标题栏覆盖层（SearchPage.TitleBarSearch 同构——官方 stackBuilder 经 hdsTitleBarOptions
  // 第 6 参注入）：搜索框与返回键横向并排；左侧留白 64vp = 返回键避让（HDS 标题栏几何
  // 真机量测值）；命中测试 Transparent——覆盖层整栏铺在返回键上方，空白区不拦截触摸
  @Builder
  TitleBarSearch() {
    Row() {
      this.SearchBox()
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 64, right: 16 })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 内容区（两路径共用；HDS 路径搜索框在标题栏内不重复布局，回退路径搜索框固定在内容区
  // 顶部）：下方三态 = 未提交（记录区：历史 + 最近进入 + 首入引导）/ 已提交有结果 /
  // 已提交无结果；键盘弹起盖住底部时可滚动查看
  @Builder
  PageContent() {
    Column() {
      if (!this.hdsAvailable) {
        Column() {
          this.SearchBox()
        }
        .width(CARD_PANEL_WIDTH)
        .margin({ top: this.topPad, bottom: 16 })
      }

      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (this.hintText !== '') {
            Text(this.hintText)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width(CARD_PANEL_WIDTH)
          }
          if (!this.submitted) {
            if (this.searchHistory.length > 0) {
              SessionHistorySection({ onSearch: (term: string): void => {
                this.applySearch(term)
              } })
            }
            // ★ 守卫用反查产物长度而非 recentConvIds 键长度（2026-09-08 自检轮修）：反查
            // 可能全落空——最近进入的会话全属其他助手（记录键全局共享、rows 只含当前助手
            // 名下行）或全被删除，此时键非空而 items 空，按键长度挂载会渲染只剩「最近进入」
            // 标题行的悬空死状态（板块组件无 items 空保护——契约 = 页面侧只传有数据的板块）
            if (this.recentConvItems().length > 0) {
              // 板块间距（SearchPage 同款：margin top 12 拉开层级——结果区卡片间距仍
              // CARD_SPACING 不受影响）；items = 页面方法反查产物（@Builder 内不允许声明
              // 变量——ChatSessionList 旧版同款「条件用方法产物 + 传参走方法」姿势）
              SessionRecentSection({ items: this.recentConvItems(), onOpen: (id: string): void => {
                this.openRecentConv(id)
              } })
                .margin({ top: 12 })
            }
            // 首入引导（无历史、最近进入反查全空、无失败提示）：SearchPage.EmptyHint 同款
            // 形态（hintText 非空时不显示——加载失败态不误导用户可搜索；条件同上用反查
            // 产物长度，反查全落空时引导可见而非空白）
            if (this.hintText === '' && this.searchHistory.length === 0 &&
              this.recentConvItems().length === 0) {
              this.EmptyHint('输入关键词搜索会话', '只匹配当前助手名下会话标题')
            }
          } else if (this.results.length > 0) {
            ForEach(this.results, (row: ConversationRow) => {
              this.ResultCard(row)
              // 键含标题/时间后缀（reload 重算结果后键变即重建——防构造快照陈旧，坑16 族；
              // 会话 id 去重键语义不变）
            }, (row: ConversationRow): string => row.id + '|' + row.title + '|' + row.updatedAt)
          } else {
            this.EmptyHint('未找到匹配的会话', '换个关键词试试')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.hdsAvailable ? this.topPad : 0, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center 坑——同 SearchPage）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // ★ 自包壳（SearchPage 同款改道说明）：会话搜索框依赖本页 keyword 状态（$$ 双向绑定），
    // 壳在 PageMap 内无法把 builder 传回标题栏——本页自包壳：HDS 路径 HdsNavDestination
    // 根透明 + 页内铺底层 + 官方标题栏（搜索框经 stackBuilder 嵌入标题栏、与返回键横向
    // 并排）；回退路径普通 NavDestination + 搜索框在内容区顶部（回退无 stackBuilder 机制）
    if (this.hdsAvailable) {
      HdsNavDestination() {
        Column() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
      }
      .backgroundColor(Color.Transparent)
      .titleBar(hdsTitleBarOptions('搜索会话', this.immersiveLevel,
        TitleSize.TITLE_S, undefined, (): void => this.TitleBarSearch()))
    } else {
      NavDestination() {
        Column() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
      }
      .backgroundColor(Color.Transparent)
      .title('搜索会话')
    }
  }
}
