// 会话搜索二级页（决明拍板「同设置搜索」自一级页内嵌态整体迁出——对话页签标题栏搜索键
// push 本页）。形态逐段对照设置搜索 SearchPage（自包壳 + 提交式 + 记录区/结果区/空态三态
// + 防循环），差异点 = 数据源会话行（DB 实时行非静态注册表）：
//   · 范围：当前助手名下全部会话（「全部/收藏」分段不随迁——拍板 = 搜索跨全量；
//     ACTIVE_ASSISTANT_KEY + historyFilterIds 口径同 ChatSessionList.reload 平移）；
//   · 提交式（拍板）：onSubmit/searchButton/历史词条点击三入口走 applySearch；onChange
//     清空回未提交态（记录区）。★ 与实时过滤框两族勿互抄：与旧一级页「输入即实时过滤」
//     差异 = 提交才出结果，空词口径两族有意相反（实时族空词 = 全量，提交族空词 = 记录区）；
//   · 数据刷新：订阅 SESSION_LIST_RELOAD_KEY（打开会话后 ChatPage pop/replace 广播），返回
//     本页自动重拉；submitted 态下 reload 落定后用当前 keyword 重算（提交式快照不是静态
//     死数据——会话被改名/删除后结果跟随真实数据）；
//   · 打开会话必走 onOpenSession 上行（PageMapBuilder 注入闭包）：ChatPage 参数单源
//     newConversation 复位 false——本页若自接 pushPathByName(ROUTE_CHAT_PAGE, id) 会把
//     普通会话误开隐私模式；且 ChatPage 页内「新建会话」replacePath 同带 string param，
//     分支无法区分（详注见 PageMapBuilder 头）；
//   · 记录区复用 SessionSearchPanels 两板块组件零改动（历史自读自清 + onSearch 上抛直通
//     applySearch；最近进入 = id 源 AppStorage、标题/时间由本页 rows 反查，反查不到 = 已删/
//     非当前助手，跳过不清键，脏 id 防残留）。
// 数据层 = common/SessionSearch.ets（历史 5 条/10 字、最近进入 3 条上限）；记录时机：历史 =
// 提交式（applySearch 内）；最近进入 = 打开会话时记（2026-11-17 整体退役加密会话后无认证前置）。
//
// ★ 搜索增强笔（决明拍板四条——分段两项、历史一份共用、命中卡内高亮、思考内容不纳入）：
// 搜索框下方加「标题 / 正文」分段（默认标题段；分段索引不持久化，进页回默认）。
//   · 标题段 = 内存过滤会话标题，同步出结果；正文段 = 内容检索（数据层
//     searchSessionMessages，异步）——命中消息每行一条，同会话最多 3 条、总上限 60 条
//    （数据层常量）；点行开会话，不做「跳到那条消息」（定位闭环另立项）；
//   · 2026-11-17 整体退役加密会话笔：原「加密会话只出标题不出内容」的 SQL 硬排除与 openConv
//     认证前置随功能退役删除，标题段与正文段对全部会话同权；
//   · 切段若已有提交词 → 用同一个词在新段重搜；无提交词 → 停留记录区；
//   · 异步纪律：请求序号丢弃（后发先至防串台）+ 加载态 + 失败提示不静默；
//   · 承载：分段走标题栏下方带（PageTopSegmentBand，与搜索框所在标题栏同屏并存）。
//   · 尾行判据（O2 修复）：「只显示最相关的一部分结果」提示由数据层 truncated 精确标志驱动
//    ——真丢了行才提示；旧判据「hitItems.length ≥ 60」在恰 60 行且零丢弃时白说。
//   历史/最近进入两板块不分段（一份共用，与决明拍板一致）——切段后记录区仍是同一份。
import { CARD_RADIUS } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items, uiMaterial, UIUtils } from '@kit.ArkUI';
import {
  BottomBuilderParams,
  HdsNavDestination,
  TitleSize
} from '@kit.UIDesignKit';
import { ConversationRow, queryConversations, whenReady } from '../../common/store/ChatDb';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, historyFilterIds } from '../../common/store/AssistantDb';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import {
  composeSessionHitItems,
  HighlightSegment,
  MAX_SESSION_RECENT_CONV,
  recordSessionRecentConv,
  recordSessionSearchHistory,
  searchSessionMessages,
  SessionHitItem,
  SessionMessageSearchResult,
  SESSION_RECENT_CONV_KEY,
  SESSION_SEARCH_HISTORY_KEY
} from '../../common/SessionSearch';
import { SessionHistorySection, SessionRecentItem, SessionRecentSection, formatConvTime } from './SessionSearchPanels';
import {
  hdsTitleBarOptions,
  IMMERSIVE_LEVEL_KEY,
  resolvedUiMaterial,
  segmentBandParams
} from '../../common/ImmersiveLevel';
import { PageTopSegmentBand } from '../SegmentBar';
import { searchBandContentTop } from '../SearchTopBand';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, usageHeatColor } from '../../common/Theme';

// 分段索引（0 标题 / 1 正文）与选项表：模块级单源（ChatSessionList.CHAT_FAV_SEG_ITEMS
// 同款姿势）。★ 两项而非「全部 + 标题 + 正文」= 决明拍板：分段只决定搜哪一面，不做混合
// 视图（混合视图会让两类结果行在半屏里互相挤占；要跨面看就切段）
const SESSION_SEG_TITLE: number = 0;
const SESSION_SEG_CONTENT: number = 1;
const SESSION_SEG_ITEMS: SegmentButtonV2Items = new SegmentButtonV2Items([
  { text: '标题' },
  { text: '正文' }
]);
// 内容让位算式间距（带底 + 28 = 分段承载先例间距，AppearancePage / 三库页同值）
const SEG_BAND_GAP: number = 28;

@Component
export struct SessionSearchPage {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部留白（vp，导航壳下发）：滚动内容顶部留白，首项静止时落在渐变模糊蒙层下方
  //（同其它二级页）
  @Prop topPad: number = 0;
  // 页面底部留白（vp，导航壳下发——底部避让区让位）
  @Prop bottomPad: number = 0;
  // 打开会话编排回调（HomeNavigation.openSession 闭包：复位隐私标记 + push ChatPage）。
  // ★ 本页所有「进入会话」动作（结果卡/最近进入卡）必须经它，禁自接 push ROUTE_CHAT_PAGE；
  // presetTitle = 本行标题上抛供首帧预置（2026-11-15 反馈二笔，见 ChatTitleMenuFactory）
  onOpenSession: (conversationId: string, presetTitle?: string) => void = (conversationId: string) => {
  };
  // 系统颜色模式（深浅色切换自动刷新卡片/词条配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（搜索框材质随沉浸光感总档，
  // 先例 = SearchPage 搜索框，见 common/ImmersiveLevel.ets）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 会话列表重拉广播（ChatPage pop/replace 后自增；ChatSessionList 同键同消费形态）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onReloadTick') reloadTick: number = 0;
  // 搜索历史/最近进入 id（@StorageLink 仅用于「未提交态」空态判定与最近进入反查——板块组件
  // 各自 @StorageLink 自读自清，写 AppStorage 本处自动刷新，SearchPage 同构姿势）
  @StorageLink(SESSION_SEARCH_HISTORY_KEY) searchHistory: string[] = [];
  @StorageLink(SESSION_RECENT_CONV_KEY) recentConvIds: string[] = [];
  // 当前助手名下全部会话行（aboutToAppear/广播两入口全量查询；搜索过滤 = 本数组内存派生，
  // 本地库毫秒级无分页——ChatSessionList 同款全量拍板）
  @State private rows: ConversationRow[] = [];
  // 查询失败提示（DB 未就绪/读库失败——P0-1 不静默）
  @State private hintText: string = '';
  // 输入中的关键词（Search 组件 $$ 双向绑定；历史词条点击回填也走它）
  @State private keyword: string = '';
  // 是否已提交搜索（提交式设计：false = 记录区；true = 结果区——SearchPage 同款）
  @State private submitted: boolean = false;
  // 本次提交的结果（filterRows 派生产物整体替换，有界——上限 = rows 条数）
  @State private results: ConversationRow[] = [];
  // 分段索引（0 标题 / 1 正文；@Watch 收尾切段副作用 = 已有提交词时用同一个词在新段重搜）。
  // 不持久化（本页无该键、EntryAbility 零注册）——每次进页回标题段
  @State @Watch('onSegmentChange') private segIndex: number = SESSION_SEG_TITLE;
  // 正文段结果（composeSessionHitItems 产物整体替换；上限 = 数据层 SESSION_HIT_TOTAL_LIMIT）
  @State private hitItems: SessionHitItem[] = [];
  // 本次结果是否被裁剪（数据层 truncated 原样接住——真丢了行才为 true；驱动结果区尾行提示；
  // O2 修复：旧判据「hitItems.length ≥ 60」在恰 60 行且零丢弃时误报，改精确标志）
  @State private hitTruncated: boolean = false;
  // 正文段检索在途（加载态；标题段是内存同步过滤，无此态）
  @State private hitLoading: boolean = false;
  // 正文段检索失败提示（RDB 异常——P0-1 不静默：提示与空结果分文案）
  @State private hitError: string = '';
  // 正文段检索请求序号（自增唯一；响应回来与当前值不符即丢弃——后发先至防串台）
  private hitSeq: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  onReloadTick(): void {
    this.reload();
  }

  // 全量查询当前助手名下会话（同 ChatSessionList.reload 口径：whenReady 守卫冷启动竞态；
  // 失败 hintText 提示不静默）；成功落定后 submitted 态下按当前分段重算结果——返回本页时
  // 结果随真实数据刷新（正文段 = 重查一次内容检索，标题段 = 内存重筛）
  private reload(): void {
    whenReady().then((ok: boolean): void => {
      if (this.departed) {
        return;
      }
      if (!ok) {
        this.hintText = '数据库初始化失败，请重启应用重试';
        return;
      }
      const activeId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
      queryConversations(historyFilterIds(activeId))
        .then((rows: ConversationRow[]): void => {
          if (this.departed) {
            return;
          }
          this.rows = rows;
          if (this.submitted) {
            this.runSearch();
          }
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.hintText = '会话列表读取失败：' + (e as Error).message;
        });
    });
  }

  // 标题子串过滤（rows 内存派生，不动时间序；大小写不敏感双侧 toLowerCase；空词返回空
  //——applySearch 首行已防空，此为防御）：ChatSessionList.visibleRows 搜索段口径平移
  private filterRows(kw: string): ConversationRow[] {
    const keyword: string = kw.trim().toLowerCase();
    if (keyword === '') {
      return [];
    }
    return this.rows.filter((row: ConversationRow): boolean =>
      row.title.toLowerCase().includes(keyword));
  }

  // 提交搜索（onSubmit / searchButton / 历史词条点击统一入口——SearchPage.doSearch 同构）：
  // keyword 回显（$$ 双向绑定）+ 按当前分段出结果 + 切结果区 + 记历史（记录时机 = 提交式，
  // 去重移头在 SessionSearch 内收敛；历史一份共用——两段记同一份，切段不重记）
  private applySearch(term: string): void {
    const kw: string = term.trim();
    if (kw === '') {
      return;
    }
    this.keyword = kw;
    this.submitted = true;
    recordSessionSearchHistory(kw);
    this.runSearch();
  }

  // 按当前分段出结果：标题段 = 内存同步过滤（立即出结果，无加载态）；正文段 = 异步内容检索。
  // 两段各自持有结果（results / hitItems），切段只换展示面不互清——runSearch 天然重算目标段
  private runSearch(): void {
    if (this.segIndex === SESSION_SEG_TITLE) {
      this.results = this.filterRows(this.keyword);
      return;
    }
    this.runContentSearch(this.keyword);
  }

  // 正文段检索（唯一调用点 = runSearch）：先清旧结果再查——避免新词在途时旧词结果继续留在
  // 屏上；序号丢弃 = 同一时刻只有最新一次的响应能落屏（用户改词/切段的旧响应到达即弃）。
  // 助手范围与会话列表/标题段同一口径（historyFilterIds 单源）；失败提示不静默
  private runContentSearch(kw: string): void {
    this.hitItems = [];
    this.hitTruncated = false;
    this.hitError = '';
    this.hitLoading = true;
    this.hitSeq++;
    const seq: number = this.hitSeq;
    const activeId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
    searchSessionMessages(kw, historyFilterIds(activeId))
      .then((res: SessionMessageSearchResult): void => {
        if (this.departed) {
          return;
        }
        if (seq !== this.hitSeq) {
          return; // 在途旧响应（改词/切段/重查已发起新一次）——丢弃不落屏
        }
        this.hitItems = composeSessionHitItems(res.hits, res.tokens, this.titleMap());
        this.hitTruncated = res.truncated;
        this.hitLoading = false;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        if (seq !== this.hitSeq) {
          return;
        }
        this.hitError = '消息检索失败：' + (e as Error).message;
        this.hitLoading = false;
      });
  }

  // 会话 id → 标题（正文段结果行的标题来源）：来源 = 本页已加载的当前助手会话行，与内容检索
  // 同一助手范围（正常必命中）；反查不到时 composeSessionHitItems 兜底「新对话」不丢行
  private titleMap(): Map<string, string> {
    const map: Map<string, string> = new Map<string, string>();
    for (const row of this.rows) {
      map.set(row.id, row.title);
    }
    return map;
  }

  // 切段收尾（PageTopSegmentBand 是 @Link 双向绑定，无回调——用 @Watch 承担副作用）：已提交则用当前
  // 关键词在新段重搜（不要求重新输入）；未提交 = 停留记录区，切段只换下次提交的去向
  private onSegmentChange(): void {
    if (!this.submitted) {
      return;
    }
    this.runSearch();
  }

  // 正文段命中行点击：行里只有会话 id，按 id 反查会话行再走同一条 openConv 链（最近进入记录 +
  // 上行打开）；反查不到 = 搜索后该会话被删（竞态），跳过不清键——与 openRecentConv
  // 同姿势（脏 id 防残留）
  private openHitConv(conversationId: string): void {
    const row: ConversationRow | undefined =
      this.rows.find((r: ConversationRow): boolean => r.id === conversationId);
    if (row !== undefined) {
      this.openConv(row);
    }
  }

  // 内容区顶留白 = 标题栏下带底 + 28，算式单源 = SearchTopBand.searchBandContentTop
  //（带顶 = 标题栏下沿不是 topPad，见该件注释）
  private contentTop(): number {
    return searchBandContentTop(this.topPad, SEG_BAND_GAP);
  }

  // 打开会话（ChatSessionList.handleOpenCard 平移——两个消费方先例可接受）：记最近进入 +
  // 上行打开（2026-11-17 整体退役加密会话后无认证前置，全部会话直通）
  private openConv(row: ConversationRow): void {
    recordSessionRecentConv(row.id);
    this.onOpenSession(row.id, row.title);
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

  // 标题栏下方带参数（带高算式与 showType 单源 = ImmersiveLevel.segmentBandParams
  // ——下移 8 + 背板 40 = 48，恰为搜索框所在标题栏的下沿再加 8vp）
  private bandParams(): BottomBuilderParams {
    return segmentBandParams((): void => {
      this.TopSegmentBand();
    });
  }

  // 标题栏下方带承载（几何/材质/命中透传全在公共件 PageTopSegmentBand——与搜索框
  // 所在标题栏同屏并存）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: SESSION_SEG_ITEMS,
      selectedIndex: $segIndex
    })
  }

  // 空态提示（无结果 / 首次进入引导共用）：官方放大镜符号 + 主/副文案垂直居中（SearchPage
  // EmptyHint 同款形态——纯文字+符号组件）
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

  // 搜索框本体（嵌标题栏覆盖层）——SearchPage.SearchBox 逐参数同构：defaultFocus(true)
  // 进页自动获焦 + 拉起输入法（二级页化红利 = 官方 defaultFocus 语义适用，取代旧一级页
  // 内嵌态的 requestFocus hack）；searchButton 框尾「搜索」文字钮（点击同时触发 onSubmit，
  // d.ts 核实）；键盘搜索键 = EnterKeyType.Search（Search 默认值）；高度 40vp 与标题栏
  // 返回键对齐。材质恒光感基准 THICK 随沉浸光感总档（标题栏生效区；2026-11-05 调薄笔自
  // ULTRA_THICK 回落一档，强档生效 REGULAR 与全族一致）。★ 清空输入回记录区
  //（onChange 内 submitted 复位——提交式搜索设计，非空修改不自动重搜）
  @Builder
  SearchBox() {
    Search({ value: $$this.keyword, placeholder: '搜索会话' })
      .searchButton('搜索')
      .defaultFocus(true)
      // 透明底勿删——Search 内容层默认底会遮 systemMaterial 背板（官方 FAQ），2033 撤兜底曾连带删此行致输入变白
      .backgroundColor(Color.Transparent)
      .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false))
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
  // 第 6 参注入）：搜索框与返回键横向并排；左侧留白 64vp = 返回键避让（HDS 标题栏几何真机
  // 量测值）；命中测试 Transparent——覆盖层整栏铺在返回键上方，空白区不拦截触摸
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

  // 内容区（搜索框在标题栏内、分段由标题栏下带承载）：下方按分段 = 标题段结果 / 正文段结果 /
  // 记录区（未提交）+ 三态空态（无结果 / 检索中 / 检索失败）；键盘弹起盖住底部时可滚动查看
  @Builder
  PageContent() {
    Column() {
      if (this.submitted && this.segIndex === SESSION_SEG_TITLE && this.results.length > 0) {
        SessionSearchResults({
          results: UIUtils.enableV2Compatibility(this.results),
          topPad: this.contentTop(),
          bottomPad: this.bottomPad,
          hintText: this.hintText,
          appColorMode: this.appColorMode,
          onOpen: (row: ConversationRow): void => this.openConv(row)
        })
          .layoutWeight(1)
      } else if (this.submitted && this.segIndex === SESSION_SEG_CONTENT && this.hitItems.length > 0) {
        SessionSearchHits({
          items: UIUtils.enableV2Compatibility(this.hitItems),
          topPad: this.contentTop(),
          bottomPad: this.bottomPad,
          capped: this.hitTruncated,
          appColorMode: this.appColorMode,
          onOpen: (item: SessionHitItem): void => this.openHitConv(item.conversationId)
        })
          .layoutWeight(1)
      } else {
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
              // 反查结果可能为空，不能用全局最近进入 id 数量决定是否展示板块。
              if (this.recentConvItems().length > 0) {
                SessionRecentSection({ items: this.recentConvItems(), onOpen: (id: string): void => {
                  this.openRecentConv(id)
                } })
                  .margin({ top: 12 })
              }
              if (this.hintText === '' && this.searchHistory.length === 0 &&
                this.recentConvItems().length === 0) {
                this.EmptyHint('输入关键词搜索会话', '标题匹配会话名，正文匹配消息内容')
              }
            } else if (this.segIndex === SESSION_SEG_CONTENT) {
              // 正文段三态：检索失败 / 检索中 / 无命中（失败与空结果分文案——不静默）
              if (this.hitError !== '') {
                Text(this.hitError)
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_warning'))
                  .width(CARD_PANEL_WIDTH)
              } else if (this.hitLoading) {
                this.EmptyHint('正在搜索消息', '结果稍候呈现')
              } else {
                this.EmptyHint('没找到匹配的消息', '换个关键词试试')
              }
            } else {
              this.EmptyHint('没找到匹配的会话', '切到正文可搜索消息内容')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Start)
          .padding({ top: this.contentTop(), bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // ★ 自包壳（SearchPage 同款改道说明）：会话搜索框依赖本页 keyword 状态（$$ 双向绑定），
    // 壳在 PageMap 内无法把 builder 传回标题栏——本页自包壳：HdsNavDestination 根透明 +
    // 页内铺底层 + 官方标题栏（搜索框经 stackBuilder 嵌入标题栏）
    HdsNavDestination() {
      Column() {
        this.PageContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'))
    }
    .backgroundColor(Color.Transparent)
    // 第 5 参 = 标题栏覆盖层（搜索框整栏），第 7 参 = 标题栏下带（标题/正文分段）——两区
    // 同屏并存先例 = HomeNavigation「对话」页签、三库页搜索带
    .titleBar(hdsTitleBarOptions('搜索会话', this.immersiveLevel,
      TitleSize.TITLE_S, undefined, (): void => this.TitleBarSearch(), false,
      this.bandParams()))
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

@ComponentV2
struct SessionSearchResults {
  @Param results: ConversationRow[] = [];
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  @Param hintText: string = '';
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Event onOpen: (row: ConversationRow) => void = () => {};

  // Repeat 会复用节点，必须保留整个 RepeatItem，显示与点击均读取其当前 item。
  // 2026-11-04 蒙层合规笔：整卡自绘（§4.19 范式——卡底 + padding 4 + 透明 Button 蒙层，
  // 四缘各 4vp；卡高 72 = 4×2 + 64，内容内距 12 + 外层 4 = 原官方卡内距 16）
  @Builder
  ResultCard(ri: RepeatItem<ConversationRow>) {
    Column() {
      Button() {
        Row({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
          Column({ space: 0 }) {
            Text(ri.item.title !== '' ? ri.item.title : '新对话')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(formatConvTime(ri.item.updatedAt))
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([cardDescColor()])
            .flexShrink(0)
        }
        .width('100%')
        .height('100%')
      }
      .type(ButtonType.Normal)
      .width('100%')
      .height(64)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.onOpen(ri.item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    List({ space: CARD_SPACING }) {
      Repeat<ConversationRow>(this.results)
        .each((ri: RepeatItem<ConversationRow>) => {
          ListItem() {
            Column({ space: CARD_SPACING }) {
              if (ri.index === 0 && this.hintText !== '') {
                Text(this.hintText)
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_warning'))
                  .width(CARD_PANEL_WIDTH)
              }
              this.ResultCard(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({
              top: ri.index === 0 ? this.topPad : 0,
              bottom: ri.index === this.results.length - 1 ? this.bottomPad + 24 : 0
            })
          }
        })
        .key((row: ConversationRow): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
    .clip(false)
    .scrollBar(BarState.Off)
  }
}

// 正文段结果列表（V2 + Repeat 虚拟化——机制与红线同 SessionSearchResults：懒加载须配 V2 /
// RepeatItem 须整体传参 / 键只写身份 / 0 行不挂载由页面兜底三态文案）。行形制 = 会话标题
//（次行，1 行省略）+ 时间 + 命中片段（主行，2 行省略、命中词带底色）。卡壳 = 整卡自绘
//（2026-11-04 蒙层合规笔：§4.19 范式，蒙层四缘 4vp；内容列自绘两行，命中底色走 Span）——
// 卡高随内容自适应（内容 + 32 = 外层 4×2 + 内距 12×2），与会话卡等高模型无关
// ★ 真机待验：Span 拼装 × maxLines(2) 尾省略；自绘卡内容列高度随结果行数增长
@ComponentV2
struct SessionSearchHits {
  @Param items: SessionHitItem[] = [];
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 结果被裁剪标志（数据层 truncated 原样透传；页面算好传入作尾行判据，本件只渲染尾行）
  @Param capped: boolean = false;
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Event onOpen: (item: SessionHitItem) => void = () => {};

  // 命中片段：按切段逐段出 Span，命中段加文字背景（textBackgroundStyle 是 Span 属性、Text 无此
  // 属性——官方 FAQ「关键词高亮」同款写法）。底色取主强调蓝半透明阶梯最浅档（Theme.usageHeatColor
  // ——应用内既有 ARGB 半透明手法，透卡底深浅自适应，不新造色值）
  @Builder
  Snippet(segments: HighlightSegment[]) {
    Text() {
      ForEach(segments, (seg: HighlightSegment) => {
        Span(seg.text)
          .textBackgroundStyle({
            color: seg.hit ? usageHeatColor(this.appColorMode, 1) : Color.Transparent,
            radius: 4
          })
      }, (seg: HighlightSegment, index: number): string => index.toString() + '|' + seg.text)
    }
    .fontSize(15)
    .fontColor($r('sys.color.font_primary'))
    .width('100%')
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  // 行内文本块（会话标题 + 时间一行，片段一行）
  @Builder
  HitText(item: SessionHitItem) {
    Column({ space: 4 }) {
      Row() {
        Text(item.title)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(formatConvTime(item.createdAt))
          .fontSize(13)
          .fontColor(cardDescColor())
          .margin({ left: 8 })
      }
      .width('100%')

      this.Snippet(item.segments)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // Repeat 会复用节点，必须保留整个 RepeatItem，显示与点击均读取其当前 item。
  // 2026-11-04 蒙层合规笔：整卡自绘（卡高随内容自适应；蒙层四缘 4vp）
  @Builder
  HitCard(ri: RepeatItem<SessionHitItem>) {
    Column() {
      Button() {
        Row({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
          Column() {
            this.HitText(ri.item)
          }
          .layoutWeight(1)
        }
        .width('100%')
      }
      .type(ButtonType.Normal)
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.onOpen(ri.item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    List({ space: CARD_SPACING }) {
      Repeat<SessionHitItem>(this.items)
        .each((ri: RepeatItem<SessionHitItem>) => {
          ListItem() {
            Column({ space: CARD_SPACING }) {
              this.HitCard(ri)
              if (ri.index === this.items.length - 1 && this.capped) {
                Text('只显示最相关的一部分结果，可用更具体的关键词再搜。')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width(CARD_PANEL_WIDTH)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({
              top: ri.index === 0 ? this.topPad : 0,
              bottom: ri.index === this.items.length - 1 ? this.bottomPad + 24 : 0
            })
          }
        })
        .key((item: SessionHitItem): string => item.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
    .clip(false)
    .scrollBar(BarState.Off)
  }
}
