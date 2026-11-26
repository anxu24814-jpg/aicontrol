// 快速清理页：设置 → 存储管理 →「快速清理」入口卡 push——把本机各域数据分项列出（按
// 决明指令「仅限已有功能」：六项有删除能力的域 + 一项聚合「清除全部」）。
// 形态（2026-11-15 决明指令，**推翻 2026-09-27「每项一张单独行卡 + 逐项确认」旧指令**）：
// ①除聚合项外六项合为一张组卡，行右侧官方 Checkbox 多选（可多选/取消多选），卡底统一
//「清除」键批量执行——说明小字在键上方（宪法「功能设置卡布局次序」）；②「清除全部数据」
// 保留原独立单卡形态零改动（标题 + 说明 + 全宽键 + 逐项确认弹窗原链不动）。
// 批量确认：点底部清除键一次确认（列出所选项），沿坑7 成员位重建模式；级联提示句单源
// QuickClean.TMP_CASCADE_HINT（勾中会话项且临时区非空才提示）。键形制（决明拍板灰底红字）：
// 官方四件套 + 危险色字——底色/材质/按压走 fallbackButton*（卡内档 comp_fallback_gray），
// 字色覆盖 app.color.dialog_confirm_red；禁自绘 borderRadius/fontSize。多选框 = 官方
// Checkbox 纯视觉 + hitTestBehavior(None)（坑5 自带点击会消费事件），行点击唯一控制通路
//（MemoryLibraryRows 多选先例）；勾选态进 ForEach 键（键纪律）。
// 刷新链（规范-数据存储获取刷新方案 §3 白名单）：aboutToAppear 首载 + 执行完成后重载，
// 重载后按 quickCleanAvailable 过滤勾选集（清空项自动掉勾）；无子页保存动作故不挂 onShown
//（每次 push 新实例，进页现读），无手动刷新键。
// 加载态：读数未回不渲卡片（官方「加载完成前不显 0」——否则行显 0 并全灰，是错误空态）；
// 失败态：整页失败卡 + 重试，不用读数判灰（读数不可信时置灰 = 用户永远够不着）。
// 执行态：busy 期间行与键全禁（enabled 拦截 + opacity 0.4 显式压暗——防连点叠清，链间
// 事务不可并行）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageShell } from '../../common/PageShell';
import { bumpBusyOverlay, confirmLeaveBusyPage, releaseBusyOverlay } from '../BusyOverlay';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { QUICK_CLEAN_ALL, QUICK_CLEAN_CONV, QuickCleanItem, QuickCleanOutcome,
  QuickCleanOverview, TMP_CASCADE_HINT, executeQuickClean, quickCleanAvailable,
  quickCleanConfirmMessage, quickCleanItems, quickCleanSummaryText,
  readQuickCleanOverview } from '../../common/QuickClean';
import { isReady, listWorkspaceTmpGroups } from '../../common/store/ChatDb';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InfoCard } from '../InfoCard';
// 草稿整仓级联清（清空会话成功回调挂点，见 afterClean 注释）
import { purgeAllDrafts } from '../chat/ChatDraftStore';

const DOMAIN: number = 0xDACD;
const TAG: string = 'QuickCleanPage';

// 页名单源（StoragePage 入口卡与 SearchPage 结果侧同引——两处显示名必然一致）
export const QUICK_CLEAN_TITLE: string = '快速清理';

@Component
export struct QuickCleanPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 页面栈（执行段返回拦截确认离开后 pop 用）
  pathStack: NavPathStack = new NavPathStack();
  // 统计就绪标记（false = 不渲卡片，只显说明行——见头注释「加载态」）
  @State private loaded: boolean = false;
  @State private loadFailed: boolean = false;
  @State private overview: QuickCleanOverview | null = null;
  // 批量勾选集（2026-11-15 多选笔；只含非聚合项 key——聚合项独立单卡不进勾选集）
  @State private selectedKeys: string[] = [];
  // 执行中（行与底部键全禁 + 文案转「清除中…」——防连点叠清）
  @State private busy: boolean = false;
  // 确认目标项 key（'' = 无；弹窗构造在成员位，动态文案经 openConfirm 重建——坑7）
  private pendingKey: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 读数重入守卫（首显与 aboutToAppear 同帧双触发由它去重）
  private loading: boolean = false;
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: QUICK_CLEAN_TITLE,
      message: '',
      confirmLabel: '清除',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.load();
  }

  // 读数（进页一次；失败三条路径同置 loadFailed——取不到上下文 / 库未就绪 / 查询抛错）
  private load(): void {
    if (this.loading) {
      return;
    }
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.loadFailed = true;
      this.showToast('无法获取应用上下文');
      return;
    }
    if (!isReady()) {
      this.loadFailed = true;
      this.showToast('数据库尚未就绪，请稍后再试');
      return;
    }
    this.loading = true;
    this.loadFailed = false;
    readQuickCleanOverview(ctx)
      .then((ov: QuickCleanOverview): void => {
        if (this.departed) {
          return;
        }
        this.overview = ov;
        this.loaded = true;
        // 重载后按可清判据过滤勾选集——清空项自动掉勾（读数与勾选态同步回落，防「勾着
        // 空项」死键）；聚合项不在勾选集（toggle 不放行），过滤恒安全
        this.selectedKeys = this.selectedKeys.filter((key: string): boolean =>
          quickCleanAvailable(key, ov));
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.loadFailed = true;
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '快速清理读数失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.showToast('读取本机数据失败，请重试（code ' + err.code + '）');
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 确认弹窗（每项执行前必经——决明指令「点击每一个清理项时，都必须要弹出确认弹窗，
  // 说明风险」）：正文由 QuickClean 单源纯函数按项生成，带现状数量或占用
  private openConfirm(item: QuickCleanItem): void {
    const ov: QuickCleanOverview | null = this.overview;
    if (ov === null || this.busy || !quickCleanAvailable(item.key, ov)) {
      return;
    }
    this.pendingKey = item.key;
    // 临时区非空才提示级联删（空时零提示防误导；文案单源在 quickCleanConfirmMessage）
    const tmpPresent: boolean = listWorkspaceTmpGroups().length > 0;
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: item.title,
        message: quickCleanConfirmMessage(item.key, ov, tmpPresent),
        // 聚合项的确认键文案区分单点（「全部清除」而非「清除」——用户按下前一眼看清范围）
        confirmLabel: item.key === QUICK_CLEAN_ALL ? '全部清除' : '清除',
        onConfirm: (): void => {
          this.doClean();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 执行（确认后；逐项结果回报——失败项如实列名，不静默不谎报）
  private async doClean(): Promise<void> {
    const key: string = this.pendingKey;
    this.pendingKey = '';
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined || key === '' || this.busy) {
      return;
    }
    this.busy = true;
    // 执行段遮罩：清除事务期间盖应用级浮层 + 拦返回（executeQuickClean 逐项吞错转失败
    // 结果，finally 兜底归还令牌；清除写入不受离开影响）
    const busyToken: number = bumpBusyOverlay('正在清除数据');
    try {
      const results: QuickCleanOutcome[] = await executeQuickClean(key, ctx)
        .finally((): void => {
          releaseBusyOverlay(busyToken);
        });
      if (this.departed) {
        return;
      }
      this.afterClean(results);
    } catch (e) {
      if (this.departed) {
        return;
      }
      // executeQuickClean 内部已逐项吞错转失败结果，走到这里 = 编排层自身异常（如未知 key）
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, '快速清理编排失败：%{public}s', err.message);
      this.showToast('清理失败：' + err.message);
      this.load();
    } finally {
      this.busy = false;
    }
  }

  // 执行后收口：会话被清 → 推会话列表重拉广播（记忆两库广播在 MemoryDb.clearAllMemories
  // 内推，模型/背景消费方各自进页现读）+ 结果 toast + 重载读数（数字与可点判据同步回落）
  private afterClean(results: QuickCleanOutcome[]): void {
    const touchedConv: boolean = results.some((r: QuickCleanOutcome): boolean =>
      r.key === QUICK_CLEAN_CONV && r.ok);
    if (touchedConv) {
      // 会话已清 → 草稿整仓级联清（QuickClean 在 common 层禁 import components，级联清落本
      // UI 调用点；purgeAllDrafts 内部逐条目 WithFiles 防孤儿文件。聚合项命中同走本处）
      purgeAllDrafts();
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
    }
    // 结果文案单源 = QuickClean.quickCleanSummaryText（页面不自拼，两处各写必漂移）
    this.showToast(quickCleanSummaryText(results));
    this.load();
  }

  // ── 批量清除链（2026-11-15 多选笔）──

  // 批量确认弹窗（点底部清除键一次确认，列出所选项——坑7 成员位重建模式沿用，动态文案经
  // 重建下发）。正文 = 所选项 title 顿号串 + 不可恢复句 + 级联提示（勾中会话项且工作区临时
  // 组非空才加，句单源 TMP_CASCADE_HINT——与单项/聚合确认同一句源，禁第三处硬写）。空选 /
  // 读数未回 / busy 不开（键 enabled 已拦，此处双保险）
  private openBatchConfirm(): void {
    const ov: QuickCleanOverview | null = this.overview;
    if (ov === null || this.busy || this.selectedKeys.length === 0) {
      return;
    }
    const chosen: QuickCleanItem[] = this.cleanItems().filter((item: QuickCleanItem): boolean =>
      this.selectedKeys.indexOf(item.key) >= 0);
    if (chosen.length === 0) {
      return;
    }
    const names: string = chosen.map((item: QuickCleanItem): string => item.title).join('、');
    const tmpPresent: boolean = listWorkspaceTmpGroups().length > 0;
    const touchConv: boolean = chosen.some((item: QuickCleanItem): boolean =>
      item.key === QUICK_CLEAN_CONV);
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: QUICK_CLEAN_TITLE,
        message: '将执行' + names + '。删除后无法恢复。' +
          (touchConv && tmpPresent ? TMP_CASCADE_HINT : ''),
        confirmLabel: '清除',
        onConfirm: (): void => {
          this.doCleanSelected();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 批量执行（确认后）：清单序逐键串行调 QuickClean 单源（sharedRdbStore 单句柄禁并发，
  // 禁 Promise.all；executeQuickClean 逐项吞错转失败结果，循环拼接即可）→ afterClean 收口
  //（级联广播 / toast / 重载全沿用）。busy 遮罩与返回拦截沿用单项链
  private async doCleanSelected(): Promise<void> {
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined || this.busy || this.selectedKeys.length === 0) {
      return;
    }
    const ov: QuickCleanOverview | null = this.overview;
    const keys: string[] = this.cleanItems()
      .filter((item: QuickCleanItem): boolean =>
        ov !== null && this.selectedKeys.indexOf(item.key) >= 0 && quickCleanAvailable(item.key, ov))
      .map((item: QuickCleanItem): string => item.key);
    if (keys.length === 0) {
      return;
    }
    this.busy = true;
    // 执行段遮罩：清除事务期间盖应用级浮层 + 拦返回（executeQuickClean 逐项吞错转失败
    // 结果；清除写入不受离开影响——finally 兜底归还令牌）
    const busyToken: number = bumpBusyOverlay('正在清除数据');
    try {
      const results: QuickCleanOutcome[] = [];
      for (const key of keys) {
        const part: QuickCleanOutcome[] = await executeQuickClean(key, ctx);
        for (const r of part) {
          results.push(r);
        }
      }
      if (this.departed) {
        return;
      }
      this.afterClean(results);
    } catch (e) {
      if (this.departed) {
        return;
      }
      // executeQuickClean 内部已逐项吞错转失败结果，走到这里 = 编排层自身异常（如未知 key）
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, '快速清理批量执行失败：%{public}s', err.message);
      this.showToast('清理失败：' + err.message);
      this.load();
    } finally {
      releaseBusyOverlay(busyToken);
      this.busy = false;
    }
  }

  // 顶部说明行：危险提示由入口卡标题警示符号 + 确认弹窗承载，本行只交代范围与勾选操作。
  // ★ 卡宽口径：宿主 Column 无左右 16vp padding，InfoCard 自挂 CARD_PANEL_WIDTH 恰与下方
  // 卡体左缘同线（规范-列表卡片与组卡 §4.3）
  @Builder
  IntroRow() {
    InfoCard({ text: '以下操作会永久删除本机数据，且无法撤销。勾选要清除的项后点清除键，执行前会再次确认。' })
  }

  // 多选行（组卡内，2026-11-15 决明笔）：标题 16fp Medium + 说明 13fp 次要灰 + 右侧官方
  // Checkbox 纯视觉（hitTestBehavior(None)——坑5 自带点击会消费事件，行点击唯一控制通路，
  // MemoryLibraryRows 多选先例）；不可清项 / busy 整行 enabled(false) + opacity(0.4)（行容器
  // 非官方键不吃自动压暗，显式压暗与 GroupSettingCard 置灰口径同源）；行高 64 = 组卡两行档。
  // 勾选态刷新责任：勾选位进 ForEach 键（BatchCard 键公式），键变重建拉新 Checkbox 值
  @Builder
  CheckRow(item: QuickCleanItem) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.desc)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Checkbox()
        .select(this.selectedKeys.indexOf(item.key) >= 0)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(64)
    .alignItems(VerticalAlign.Center)
    .enabled(this.canRun(item) && !this.busy)
    .opacity(this.canRun(item) && !this.busy ? 1 : 0.4)
    .onClick((): void => {
      this.toggleSelected(item);
    })
  }

  // 组卡（2026-11-15 决明笔）：六项多选行 + 说明小字 + 底部统一清除键（说明在键上方——
  // 宪法「功能设置卡布局次序」）；卡壳四件套与页内各卡同源。底部键灰底红字（决明拍板——
  // 旧页七键同源形制 fallbackButton* 四件套 + dialog_confirm_red 覆字），选中数为 0 置灰。
  // 行间分割线 0.5vp（组卡行规格）
  @Builder
  BatchCard() {
    Column({ space: 10 }) {
      ForEach(this.cleanItems(), (item: QuickCleanItem, idx: number): void => {
        if (idx > 0) {
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .width('100%')
        }
        this.CheckRow(item)
      }, (item: QuickCleanItem): string => item.key + '|' +
        (this.canRun(item) ? '1' : '0') + '|' +
        (this.selectedKeys.indexOf(item.key) >= 0 ? '1' : '0') + '|' +
        (this.busy ? '1' : '0'))
      Text('勾选要清除的项，点下方清除键统一执行。执行前会再次确认。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Button(this.busy ? '清除中…' : '清除')
        .width('100%')
        .fontColor($r('app.color.dialog_confirm_red'))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(this.selectedKeys.length > 0 && !this.busy && !this.loadFailed)
        .onClick((): void => {
          this.openBatchConfirm();
        })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 聚合项卡（「清除全部数据」——2026-11-15 多选笔起独立单卡零改动；标题 + 说明 + 全宽键 +
  // 逐项确认弹窗，说明在按钮行上方——宪法「功能设置卡布局次序」）
  @Builder
  ItemCard(item: QuickCleanItem) {
    Column({ space: 10 }) {
      Text(item.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text(item.desc)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      // 键字色恒危险红（不设 primary 蓝）——本页七键全是破坏性动作，上强调蓝会把「最危险
      // 的一键」渲成「推荐操作」；七键同形同色
      Button(this.busy ? '清除中…' : (item.key === QUICK_CLEAN_ALL ? '全部清除' : '清除'))
        .width('100%')
        .fontColor($r('app.color.dialog_confirm_red'))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(this.canRun(item) && !this.busy && !this.loadFailed)
        .onClick((): void => {
          this.openConfirm(item);
        })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 键可点判据：读数已回 + 该项有内容 + 非执行中（读数未回时 loaded=false，整片不渲）
  private canRun(item: QuickCleanItem): boolean {
    const ov: QuickCleanOverview | null = this.overview;
    return ov !== null && this.loaded && quickCleanAvailable(item.key, ov);
  }

  // 勾选切换（行点击唯一控制通路——Checkbox hitTestBehavior(None) 纯视觉，坑5）：不可清项
  // 与 busy 期拒绝（行 enabled 已拦，此处双保险）；集合整体换引用驱动键变重建
  private toggleSelected(item: QuickCleanItem): void {
    if (this.busy || !this.canRun(item)) {
      return;
    }
    if (this.selectedKeys.indexOf(item.key) >= 0) {
      this.selectedKeys = this.selectedKeys.filter((key: string): boolean => key !== item.key);
    } else {
      this.selectedKeys = this.selectedKeys.concat([item.key]);
    }
  }

  // 六项清单（清单序单源 quickCleanItems 去聚合项——聚合项独立单卡由 ItemCard 承载；
  // 序仍走单源，本页不自写顺序表）
  private cleanItems(): QuickCleanItem[] {
    return quickCleanItems().filter((item: QuickCleanItem): boolean =>
      item.key !== QUICK_CLEAN_ALL);
  }

  // 聚合项（清单末位单源取尾项——ItemCard 原形态承载，逐项确认与执行链零改动）
  private allItem(): QuickCleanItem {
    const items: QuickCleanItem[] = quickCleanItems();
    return items[items.length - 1];
  }

  // 失败态卡（重试走 load 单一路径）
  @Builder
  FailCard() {
    Column({ space: 10 }) {
      Text('读取本机数据失败')
        .fontSize(15)
        .fontColor(cardTitleColor())
      Button('重试')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.load();
        })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        this.IntroRow()
        if (this.loadFailed) {
          this.FailCard()
        } else if (this.loaded) {
          // 六项合组卡（2026-11-15 决明笔）+ 聚合项独立单卡原形态（清单序末位由单源保证）
          this.BatchCard()
          this.ItemCard(this.allItem())
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: QUICK_CLEAN_TITLE,
      // 执行段返回拦截（BusyOverlay 单源——清除进行中弹确认，离开 = 撤遮罩 + pop，
      // 清除链继续后台完成）
      onBackPressed: (): boolean => {
        return confirmLeaveBusyPage(this.getUIContext(), (): void => {
          this.pathStack.pop();
        });
      },
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
