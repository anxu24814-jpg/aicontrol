// 联网搜索设置二级页：条数卡 + 超时卡 + 网页抓取卡 + 引擎卡×N（SEARCH_ENGINES 表驱动，新增引擎加一行即出现；名称 + 徽章行〔搜索与抓取 /
// 免配置·需 API Key / 已·未配置密钥〕+ 行尾启用开关），点卡片 push 引擎配置三级页（SearchEngineDetailPage）。
// ★ 抓取卡 = 功能模型页行式——FunctionalCardHeader 卡头 + SettingValueRow 值行整行可点 = 唯一入口（无箭头
// 无按钮），说明小字收进卡头 ⓘ；显示行经 resolveFetchEngineId 与消费链同源解析（引擎停用/缺钥如实显示本地）；
// 半模态选项 = 本地恒在 + canScrape ∩ 已启用 ∩ 已配置密钥（与消费链同判据，未就绪不进面板）。
// ★ 总开关已退役：全局恒开（联网能力全量可用），是否联网由助手工具页「联网搜索」卡决定、会话内「联网」开关
// 只管当前会话；页内卡片无条件渲染，PREF_SEARCH_SERVICE_ENABLED_KEY 与消费守卫全链同笔退役。
// 语义（决明拍板解耦，废除「选中未启用引擎顺手启用」旧补丁）：开关 = 是否参与（含作为回退候选——付费引擎的
// 费用闸），唯一控制面 = 本页行尾开关；全局当前引擎唯一设置面 = 对话页「更多」菜单「联网」项选引擎
//（ChatSessionOverrideCtrl.pickWebEngine，本页不展示）。当前引擎停用或未配置密钥时，对话自动改用已启用引擎
// 中第一个配置完整的，都没有时回 Bing 免密钥兜底（resolveEngineId 链不变）。
// 刷新链与服务商管理不同：偏好键走 AppStorage（@StorageLink 双向），列表/详情两页订阅同键即时互刷，无 DB 自拉
// → 无需 cardEpoch/onPop 重拉链；卡片仍走状态入键的 ForEach 重建（坑16/坑57 家族）。
// 容器形态 = Scroll + Column（原 Stack + List + 悬浮胶囊三层已退役；条数卡共用件 SliderValueCard 三个既有
// 消费方一律 Scroll + Column 无侧距，卡体自带 CARD_PANEL_WIDTH）；顶/底留白在 Scroll 内 padding（坑9 只管 List）。
// 明文红线：API Key 明文只在详情页输入，保存即清空、界面只显示已·未配置徽标；明文不进日志/toast。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  CARD_SPACING, CARD_PANEL_WIDTH, LIST_CARD_TITLE_FONTSIZE, badgeBg,
  cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { FunctionalCardHeader, SettingValueRow } from './FunctionalSettingRows';
import { SliderValueCard } from '../SliderValueCard';
import { InputDialog } from '../chat/InputDialog';
import { PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY,
  PREF_SEARCH_FETCH_ENGINE_KEY, PREF_SEARCH_RESULT_COUNT_KEY,
  PREF_SEARCH_TIMEOUT_SEC_KEY } from '../../common/AppPreferences';
import { SEARCH_RESULT_COUNT_DEFAULT, SEARCH_RESULT_COUNT_MAX, SEARCH_RESULT_COUNT_MIN,
  SEARCH_TIMEOUT_SECONDS_DEFAULT, SEARCH_TIMEOUT_SECONDS_MAX, SEARCH_TIMEOUT_SECONDS_MIN,
  resolveSearchResultCount, resolveSearchTimeoutSeconds } from '../../common/search/SearchLimits';
import { SETTING_TITLE_SEARCH_COUNT, SETTING_TITLE_SEARCH_ENGINE,
  SETTING_TITLE_SEARCH_TIMEOUT } from '../../common/SettingSearch';
import { EngineCfgEntry, SEARCH_ENGINES, SearchEngineDescriptor,
  parseEngineCfg, resolveFetchEngineId } from '../../common/search/SearchEngineRegistry';
import { ROUTE_SEARCH_ENGINE_DETAIL_PAGE } from '../../common/RouteNames';

// 抓取方式选项（半模态行卡与显示行的数据源）：'local' 恒在首位（免费默认、终态兜底），其后 = canScrape ∩
// 已启用 ∩ 已配置密钥的引擎（与消费链 resolveFetchEngineId 同判据）；descText = 半模态行卡副行说明
interface FetchOption {
  id: string;
  label: string;
  descText: string;
}

@Component
export struct SearchEnginePage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（引擎卡 push 引擎配置三级页）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 偏好两键（与详情页订阅同键，写这里详情页即时回流）；当前引擎 @StorageLink 已随「当前使用」徽章退役
  // ——该键唯一 UI 写点 = ChatSessionOverrideCtrl.pickWebEngine。默认值取降级安全值（['bing_local'] 免 key 可用）
  @StorageLink(PREF_SEARCH_ENABLED_ENGINES_KEY) enabledEngines: string[] = ['bing_local'];
  @StorageLink(PREF_SEARCH_ENGINE_CFG_KEY) cfgJson: string = '';
  // 抓取方式键（'local' | 引擎 id，默认本地——@StorageLink 写即持久化，EntryAbility persistProp 注册；
  // 消费方 = 注册表 dispatchScrape）
  @StorageLink(PREF_SEARCH_FETCH_ENGINE_KEY) fetchEngineId: string = 'local';
  // 抓取方式半模态（坑64 姿势 bindSheet 挂页面根——ModelSettingsPage 同款）。关闭-再开协调机制与官方依据
  // 单源 = KimiSheetCommon.sheetPanelOptions 第四参
  @State @Watch('onFetchSheetVisibleChanged') private fetchSheetShow: boolean = false;
  private fetchSheetClosing: boolean = false;
  private fetchSheetPendingOpen: boolean = false;
  // 搜索结果条数键（@StorageLink 写即持久化，EntryAbility persistProp 注册）；全局一份、对所有助手生效，本页唯一控制面
  @StorageLink(PREF_SEARCH_RESULT_COUNT_KEY) @Watch('onSearchResultCountPrefChanged')
  searchResultCountPref: number = SEARCH_RESULT_COUNT_DEFAULT;
  // 条数滑轨域状态（@State + $ 传 @Link——坑16 契约；@Watch 写回持久键；aboutToAppear 从持久键取真值并归一）
  @State @Watch('onSearchResultCountSliderChange') sliderSearchResultCount: number =
    SEARCH_RESULT_COUNT_DEFAULT;
  // 条数卡编辑键弹窗控制器（坑7：须组件成员位构造，弹一次 new 一次）
  private searchResultCountEditCtrl: CustomDialogController | null = null;
  // 联网请求超时键（同条数卡形态——@StorageLink 写即持久化，全局一份、本页唯一控制面。★ 与网络设置页
  //「请求读超时」是两条链两把值，见 AppPreferences 该键注释）
  @StorageLink(PREF_SEARCH_TIMEOUT_SEC_KEY) @Watch('onSearchTimeoutPrefChanged')
  searchTimeoutSecPref: number = SEARCH_TIMEOUT_SECONDS_DEFAULT;
  @State @Watch('onSearchTimeoutSliderChange') sliderSearchTimeout: number =
    SEARCH_TIMEOUT_SECONDS_DEFAULT;
  private searchTimeoutEditCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 条数滑轨从持久键取真值并归一（脏值收口或回默认，赋值即触发 @Watch 归正落盘；归一同源 = 消费侧换算函数）
    this.sliderSearchResultCount = resolveSearchResultCount(this.searchResultCountPref);
    this.sliderSearchTimeout = resolveSearchTimeoutSeconds(this.searchTimeoutSecPref);
  }

  private isEnabled(engineId: string): boolean {
    return this.enabledEngines.includes(engineId);
  }

  private hasKeyMarked(engineId: string): boolean {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(engineId);
    return entry !== undefined && entry.hasKey;
  }

  // 抓取方式选项清单（半模态与显示行数据源）：本地恒首位，引擎行 = canScrape ∩ 已启用 ∩ 已配置密钥——与
  // 消费链 resolveFetchEngineId 同判据，未就绪不进面板（选了也会被解析链回落本地）；新增抓取引擎表加一行即自动出现
  private fetchOptions(): FetchOption[] {
    const list: FetchOption[] = [{
      id: 'local', label: '本地抓取', descText: '免费，直接解析网页正文'
    }];
    for (const engine of SEARCH_ENGINES) {
      if (engine.canScrape && this.isEnabled(engine.id) && this.hasKeyMarked(engine.id)) {
        list.push({ id: engine.id, label: engine.label + ' 抓取', descText: '已配置密钥' });
      }
    }
    return list;
  }

  // 当前生效抓取方式 id（显示行与「当前」尾标共用——经 resolveFetchEngineId 与消费链同源，防界面显示与实际不符）
  private resolvedFetchId(): string {
    return resolveFetchEngineId(this.fetchEngineId, this.enabledEngines,
      parseEngineCfg(this.cfgJson));
  }

  // 显示行文本（生效 id 映射选项 label；找不到回「本地抓取」——与解析链兜底同向）
  private selectedFetchLabel(): string {
    const resolved: string = this.resolvedFetchId();
    for (const opt of this.fetchOptions()) {
      if (opt.id === resolved) {
        return opt.label;
      }
    }
    return '本地抓取';
  }

  // 半模态行卡数据（fetchOptions 单源映射——副行 = 选项说明，尾标 = 生效项「当前」，空串不渲染）。★ 生效项
  // 尾标是状态词，置 suffixEmphasis true 走实底胶囊（其余三处宿主不传，普通尾标形制不变）
  private pickRows(): TemplatePickRow[] {
    const resolved: string = this.resolvedFetchId();
    return this.fetchOptions().map((opt: FetchOption): TemplatePickRow => {
      const row: TemplatePickRow = {
        title: opt.label,
        subtitle: opt.descText,
        suffix: opt.id === resolved ? '当前' : '',
        suffixEmphasis: true
      };
      return row;
    });
  }

  // 面板点选：写偏好（写即落盘）后关面板——先落盘后关（钉 B4 序）；不弹 toast（主卡显示行即时刷新即反馈）
  private onPickFetchOption(index: number): void {
    const options: FetchOption[] = this.fetchOptions();
    if (index < 0 || index >= options.length) {
      return;
    }
    this.fetchEngineId = options[index].id;
    this.requestFetchSheetClose();
  }

  // 抓取方式半模态关闭-再开协调（机制与官方依据单源 = KimiSheetCommon.sheetPanelOptions 第四参）；
  // 开意图落定 → 动效在途挂起 / 否则即开（applyFetchSheetOpen 单入口，补开两路共用）
  private requestFetchSheetOpen(): void {
    this.fetchSheetPendingOpen = true;
    if (this.fetchSheetClosing) {
      return; // 离场动效在途：待补开
    }
    this.applyFetchSheetOpen();
  }

  private applyFetchSheetOpen(): void {
    if (!this.fetchSheetPendingOpen) {
      return;
    }
    this.fetchSheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参）：清在途位 + 按开意图补开
  private onFetchSheetGone(): void {
    this.fetchSheetClosing = false;
    if (!this.fetchSheetShow) {
      this.applyFetchSheetOpen();
    }
  }

  // 可见性兜底（@Watch）：框架 $$ 收尾回写压回 false 时按开意图补开；用户关闭必经 requestFetchSheetClose，不会误触
  private onFetchSheetVisibleChanged(): void {
    if (!this.fetchSheetShow) {
      this.applyFetchSheetOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 点选三路同调）：先清开意图（撤销在途期待开）+ 置离场动效在途位，再写可见性
  private requestFetchSheetClose(): void {
    this.fetchSheetPendingOpen = false;
    this.fetchSheetClosing = true;
    this.fetchSheetShow = false;
  }

  // 启用开关（父页唯一写入口；替换整数组保证 @StorageLink 响应）
  private toggleEngine(engineId: string, isOn: boolean): void {
    if (isOn) {
      if (!this.isEnabled(engineId)) {
        this.enabledEngines = this.enabledEngines.concat([engineId]);
      }
    } else {
      this.enabledEngines = this.enabledEngines.filter((id: string): boolean => id !== engineId);
    }
  }

  // 详情页跳转（param = 引擎 id；★ 勿传 null——param 契约 = string，坑12）。不挂 onPop：偏好走 AppStorage
  // 响应式，本页 @StorageLink 订阅自动刷新
  private openDetail(engineId: string): void {
    this.pathStack.pushPathByName(ROUTE_SEARCH_ENGINE_DETAIL_PAGE, engineId);
  }

  // 条数滑轨 → 持久键（写即落盘；同值不回写防递归）
  private onSearchResultCountSliderChange(): void {
    if (this.searchResultCountPref !== this.sliderSearchResultCount) {
      this.searchResultCountPref = this.sliderSearchResultCount;
    }
  }

  // 第二写键方（备份导入恢复）→ 补正条数滑轨值（@StorageLink 自动响应；归一同 resolve）
  private onSearchResultCountPrefChanged(): void {
    const v: number = resolveSearchResultCount(this.searchResultCountPref);
    if (v !== this.sliderSearchResultCount) {
      this.sliderSearchResultCount = v;
    }
  }

  // 条数手动输入解析（整数 + 范围校验；非法 toast 不静默）；合法则更新 @State（@Watch 落盘）
  private applySearchResultCountInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() ||
      v < SEARCH_RESULT_COUNT_MIN || v > SEARCH_RESULT_COUNT_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 ' + SEARCH_RESULT_COUNT_MIN + '~' + SEARCH_RESULT_COUNT_MAX + ' 的整数'
      });
      return;
    }
    this.sliderSearchResultCount = v;
  }

  // 条数编辑键弹窗（InputDialog 数字型——初值预填当前值，成员位 Ctrl 弹一次 new 一次）
  private openSearchResultCountEdit(): void {
    this.searchResultCountEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: SETTING_TITLE_SEARCH_COUNT,
        initialText: String(this.sliderSearchResultCount),
        placeholder: SEARCH_RESULT_COUNT_MIN + '~' + SEARCH_RESULT_COUNT_MAX + ' 的整数',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applySearchResultCountInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.searchResultCountEditCtrl.open();
  }

  // 超时滑轨 → 持久键（写即落盘；同值不回写防递归）
  private onSearchTimeoutSliderChange(): void {
    if (this.searchTimeoutSecPref !== this.sliderSearchTimeout) {
      this.searchTimeoutSecPref = this.sliderSearchTimeout;
    }
  }

  // 第二写键方（备份导入恢复）→ 补正超时滑轨值（@StorageLink 自动响应；归一同 resolve）
  private onSearchTimeoutPrefChanged(): void {
    const v: number = resolveSearchTimeoutSeconds(this.searchTimeoutSecPref);
    if (v !== this.sliderSearchTimeout) {
      this.sliderSearchTimeout = v;
    }
  }

  // 超时手动输入解析（整数 + 范围校验；非法 toast 不静默）；合法则更新 @State（@Watch 落盘）；形制同条数卡
  private applySearchTimeoutInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() ||
      v < SEARCH_TIMEOUT_SECONDS_MIN || v > SEARCH_TIMEOUT_SECONDS_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 ' + SEARCH_TIMEOUT_SECONDS_MIN + '~' + SEARCH_TIMEOUT_SECONDS_MAX + ' 的整数'
      });
      return;
    }
    this.sliderSearchTimeout = v;
  }

  // 超时编辑键弹窗（InputDialog 数字型——初值预填当前值，成员位 Ctrl 弹一次 new 一次）
  private openSearchTimeoutEdit(): void {
    this.searchTimeoutEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: SETTING_TITLE_SEARCH_TIMEOUT,
        initialText: String(this.sliderSearchTimeout),
        placeholder: SEARCH_TIMEOUT_SECONDS_MIN + '~' + SEARCH_TIMEOUT_SECONDS_MAX + ' 的整数',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applySearchTimeoutInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.searchTimeoutEditCtrl.open();
  }

  // 卡片重建键（启用态/密钥态任一变 → 整卡重建——坑16/坑57 家族；当前引擎成分已随「当前使用」徽章退役）
  private cardKey(engine: SearchEngineDescriptor): string {
    return [engine.id, String(this.isEnabled(engine.id)),
      String(this.hasKeyMarked(engine.id))].join('|');
  }

  // 搜索结果条数卡（本页即该值唯一控制面；值域 1~25、默认 5；说明小字由共用卡内建在滑轨上方——宪法「功能
  // 设置卡布局次序」条）。行式布局 = 说明 + 分割线 + 左侧标签 + 右侧短滑轨；与详情页「测试搜索恒用默认条数」
  // 不冲突：那条是调试入口口径（不吃本设置），本条讲对话链
  @Builder
  SearchCountCard() {
    SliderValueCard({
      title: SETTING_TITLE_SEARCH_COUNT, value: $sliderSearchResultCount,
      min: SEARCH_RESULT_COUNT_MIN, max: SEARCH_RESULT_COUNT_MAX, step: 1,
      format: (v: number): string => v + ' 条',
      desc: '联网搜索单次返回的结果条数，对所有助手生效。返回的条目会作为引文进入对话上下文，条数越多消耗越多。免配置的 Bing 由结果页决定条数，通常十条上下',
      rowLabel: '条数',
      onEdit: (): void => {
        this.openSearchResultCountEdit();
      }
    })
  }

  // 联网请求超时卡（形制与条数卡同源、紧邻其下——联网域两枚运行参数同群）。值域 5~60 秒、默认 20；说明
  // 小字由共用卡内建在滑轨上方（宪法「功能设置卡布局次序」条）；行式布局同条数卡
  @Builder
  SearchTimeoutCard() {
    SliderValueCard({
      title: SETTING_TITLE_SEARCH_TIMEOUT, value: $sliderSearchTimeout,
      min: SEARCH_TIMEOUT_SECONDS_MIN, max: SEARCH_TIMEOUT_SECONDS_MAX, step: 5,
      format: (v: number): string => v + ' 秒',
      desc: '联网搜索与读取网页每次请求的等待上限，对所有助手生效。网络较慢或使用中转服务时可调大',
      rowLabel: '超时',
      onEdit: (): void => {
        this.openSearchTimeoutEdit();
      }
    })
  }

  // 网页抓取卡（主卡只显示当前生效方式；卡头 + 值行整行可点 = 唯一入口，说明小字收进卡头 ⓘ 气泡；半模态与值解析链不动）
  @Builder
  FetchEngineCard() {
    Column({ space: 12 }) {
      FunctionalCardHeader({
        title: '网页抓取',
        hint: '读取网页正文时使用的方式。未配置密钥或抓取失败时自动改用本地抓取。'
      })
      Column() {
        SettingValueRow({
          label: '抓取方式',
          subtitle: '',
          value: this.selectedFetchLabel(),
          valueMuted: false,
          dividerTop: false,
          onTap: (): void => {
            this.requestFetchSheetOpen();
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding({ top: 16, bottom: 4 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 抓取方式半模态内容（TemplatePickSheet 第四处消费——assert-ui-shape 64 组收口钉随形 3→4；副行 = 选项说明、
  // 尾标 = 生效项「当前」；不含 bindSheet——宿主挂）
  @Builder
  FetchPickSheet() {
    TemplatePickSheet({
      mainTitle: '网页抓取方式',
      subTitle: '点选即切换',
      rows: this.pickRows(),
      onPick: (index: number): void => {
        this.onPickFetchOption(index);
      },
      onClose: (): void => {
        this.requestFetchSheetClose();
      }
    })
  }

  // 页面内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）；无标题栏菜单（引擎清单固定，无新建/排序/导入需求）。
  // 原首卡与关闭态隐藏分支已随总开关退役撤除——页内卡片无条件渲染
  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 条数卡（页首——总开关卡退役后递补；同属「页面级参数」）
        this.SearchCountCard()
        // 超时卡紧跟条数卡（同属联网域运行参数；两卡同群=竞品对照的「通用选项」组）
        this.SearchTimeoutCard()
        // 网页抓取卡（2026-10-17 二期；抓取方式同属联网域运行参数，引擎卡之前）
        this.FetchEngineCard()
        ForEach(SEARCH_ENGINES, (engine: SearchEngineDescriptor) => {
          SearchEngineCardItem({
            engineId: engine.id,
            label: engine.label,
            requiresApiKey: engine.requiresApiKey,
            canScrape: engine.canScrape,
            engineEnabled: this.isEnabled(engine.id),
            hasKey: this.hasKeyMarked(engine.id),
            onOpen: (engineId: string): void => {
              this.openDetail(engineId);
            },
            onToggle: (engineId: string, isOn: boolean): void => {
              this.toggleEngine(engineId, isOn);
            }
          })
          // 键含状态（启用/密钥）——状态变整卡重建，徽章与开关不定格首帧
        }, (engine: SearchEngineDescriptor): string => this.cardKey(engine))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    // 短内容也上下可拖（alwaysEnabled，工具调用页同款）
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_SEARCH_ENGINE,
      content: (): void => {
        this.Content()
      }
    })
    // 抓取方式半模态（坑64 姿势：bindSheet 挂页面根——ModelSettingsPage 同款；档位 = [MEDIUM, LARGE]）。关闭链
    // = 可见性 $$ 双向 + onWillDismiss 内 action.dismiss() 放行（官方契约）+ requestFetchSheetClose 单入口 +
    // onDisappear 补开（关闭-再开协调，见字段注释）
    .bindSheet($$this.fetchSheetShow, this.FetchPickSheet(), sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        this.requestFetchSheetClose();
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents, undefined,
      (): void => {
        this.onFetchSheetGone();
      }))
  }
}

// 引擎卡片段（对齐 ProviderCardItem：名称 + 徽章行 + 行尾启用开关，无菜单键——引擎由注册表提供，无删除/分享）。
// 纯展示 + 回调上行；展示字段由父页 ForEach 键含状态整卡重建下发（偏好为 AppStorage 响应式，无卡内自拉库链）
@Component
struct SearchEngineCardItem {
  engineId: string = '';
  label: string = '';
  requiresApiKey: boolean = false;
  // 抓取能力（2026-10-17 二期）：true = 该引擎同时可用于「网页抓取」卡（能力徽标显示）
  canScrape: boolean = false;
  // ★ 成员名禁用 enabled——与组件通用属性方法 .enabled() 撞名 = 10505001 编译错（ProviderConfigPanel 同款
  // 教训，2026-09-10 再实锤；该成员已随该页「启用开关卡」退役，教训仍适用）
  engineEnabled: boolean = true;
  hasKey: boolean = false;
  onOpen: (engineId: string) => void = () => {
  };
  onToggle: (engineId: string, isOn: boolean) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 徽章文本清单（坑16：@Builder 值参直调 = 按值快照，徽章行走 ForEach 键变重建）；「当前使用」徽章已退役——
  // 当前引擎唯一设置面 = 对话页「联网」菜单。顺序 = 搜索与抓取〔如有〕/ 免配置·需 API Key / 已·未配置密钥
  private badges(): string[] {
    const list: string[] = [];
    if (this.canScrape) {
      list.push('搜索与抓取');
    }
    list.push(this.requiresApiKey ? '需 API Key' : '免配置');
    if (this.requiresApiKey) {
      list.push(this.hasKey ? '已配置密钥' : '未配置密钥');
    }
    return list;
  }

  // 小徽章（文字胶囊——ProviderCardItem.Badge 同款）
  @Builder
  Badge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  build() {
    // Button(Normal) 包裹 = 官方原生按压蒙层（ProviderCardItem 同款；行内 Toggle 子组件先命中，嵌套点击关系
    // 不变）。★ 蒙层边距统一：卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding 16→12 回添，几何零位移
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(this.label)
              .fontSize(LIST_CARD_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Row({ space: 6 }) {
              ForEach(this.badges(), (text: string) => {
                this.Badge(text)
              }, (text: string): string => text)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // 启用开关（官方 Toggle 可点自切换 = 唯一控制面；停用 = 不参与对话搜索与自动回退）
          Toggle({ type: ToggleType.Switch, isOn: this.engineEnabled })
            .onChange((isOn: boolean): void => {
              this.onToggle(this.engineId, isOn);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .padding(12)
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.onOpen(this.engineId);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(4)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }
}
