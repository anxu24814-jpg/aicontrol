// 会话轨迹页：会话页「更多」菜单「会话轨迹」项 push 的只读整页——按「轮 → 记录行」组织的
// 轨迹账表 + 每轮一条简化时间条 + 点记录行开详情半模态。取数 = SessionTraceDb（store 读口），
// 组装 = SessionTraceModel（纯函数叶子，轮 = generation_runs 一行、run 编号按 createdAt 升序
// 序号），本件只做编排与呈现。
// · 数据装载：进页读一次（不做刷新键）；先判有行（conversationHasRow——无行会话直接空态，
//   禁按路由口代判）→ 图态判据（ROUTE_BLOCKED = 旧格式墓碑，单源引用 TOMBSTONE_NOTICE_TEXT
//   呈报）→ 消息尾窗（TRACE_TAIL_LIMIT 有界）+ run 编年 + 事实/用量/诊断三查 → 组装。
// · 键纪律（坑44/80 家族）：Repeat 键只写轮键（runId / 未分组常量），折叠态是页面级 @State
//  （collapsedKeys）不进键——折叠刷新走 @Param 数组整体替换承接。
// · 详情面板 = SessionTraceDetailSheet（面板内容件不含 bindSheet，宿主 = 本页页面根唯一挂载；
//   纯信息展示不加关闭确认）。★ 关闭-再开协调（真机报障修复）：离场动效不支持打断（官方
//   《半模态转场》「需等动效完全结束后才可再次拉起」），在途期写可见性会被吞——只记开意图，
//   onDisappear 补开 + @Watch 兜底，细则见 openRecord 注释。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIUtils } from '@kit.ArkUI';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import {
 badgeBg, cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING,
  usageAccentColor, CARD_RADIUS
} from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { ROUTE_SESSION_TRACE_PAGE } from '../../common/RouteNames';
import { conversationHasRow, conversationWritableRoute, ROUTE_BLOCKED }
  from '../../common/chat/ChatContextSource';
import { TOMBSTONE_NOTICE_TEXT } from '../../common/chat/ChatBranchPolicy';
import {
  queryChatUsageByRunIds,
  queryRunRowsByConversation,
  queryToolFactsByRunIds,
  queryTraceMessagesByIds,
  readTraceMessageWindow,
  TRACE_TAIL_LIMIT,
  TraceMessageWindow
} from '../../common/store/SessionTraceDb';
import {
  assembleSessionTrace,
  TRACE_KIND_ASSISTANT,
  TRACE_KIND_CLEAR,
  TRACE_KIND_NOTICE,
  TRACE_KIND_SUMMARY,
  TRACE_KIND_TOOL,
  TRACE_KIND_USER,
  TRACE_SEG_ASSISTANT,
  TRACE_SEG_FAILED,
  TRACE_SEG_TOOL,
  TRACE_STATUS_ABORTED,
  TRACE_STATUS_FAILED,
  TRACE_STATUS_RUNNING,
  traceClockText,
  traceDurationText,
  traceSecondsText,
  traceStatusTextOf,
  TraceFactIn,
  TraceRecord,
  TraceSegment,
  TraceTurn,
  TraceUsage
} from '../../common/chat/SessionTraceModel';
import { sheetPanelOptions } from './KimiSheetCommon';
import { SessionTraceDetailSheet } from './SessionTraceDetailSheet';

// 未分组段轮键（runId 空行归组；Repeat 键与折叠键共用单源）
const TRACE_UNGROUPED_KEY: string = '__traceUngrouped__';

// 轮键（Repeat 键只写它；折叠态不进键）
function traceTurnKey(turn: TraceTurn): string {
  return turn.runId !== '' ? turn.runId : TRACE_UNGROUPED_KEY;
}

// 轮标题（轮号 1 起；未分组 = 其他记录）
function traceTurnTitle(turn: TraceTurn): string {
  return turn.turnNo > 0 ? '第 ' + turn.turnNo + ' 轮' : '其他记录';
}

@Component
export struct SessionTracePage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（PageMap 注入；param = 会话 id，getParamByName 取）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private conversationId: string = '';
  // 上屏轮组（组装产物；Repeat 数据源）
  @State turns: TraceTurn[] = [];
  // 装载完成位（读取毫秒级不设加载指示；状态最小化）
  @State loaded: boolean = false;
  // 截断标记（>TRACE_TAIL_LIMIT 条时有值；列表首行呈报）
  @State truncated: boolean = false;
  // 旧格式墓碑态（TOMBSTONE_NOTICE_TEXT 单源呈报；与空态互斥）
  @State tombstone: boolean = false;
  // 折叠轮键集（页面级状态，整体替换触发刷新；不进 Repeat 键——键纪律红线）
  @State collapsedKeys: string[] = [];
  // 详情面板态（关闭恒不复位内容形态——关闭写点只置可见性）
  // ★ @Watch = 关闭-再开协调的兜底网（框架收尾回写压回可见性时按开意图补开一次）
  @State @Watch('onSheetVisibleChanged') sheetOpen: boolean = false;
  @State sheetRecord: TraceRecord | null = null;
  @State sheetUsage: TraceUsage | null = null;
  @State sheetFact: TraceFactIn | null = null;
  // 离场动效在途位（requestCloseDetail 置位 / onDisappear 清位——动效结束后回调）。动效期
  // 点行只记账不写可见性（写了会被吞或被收尾回写压回，症状 = 新面板立即被收起）
  private sheetClosing: boolean = false;
  // 开意图（用户点行想看的记录对）：点行即记、用户关闭清、两处补开据此取件；同时是「可见性
  // 应随意图」的判据（用户关闭必经 requestCloseDetail 先清本对，不误触兜底）
  private intentRecord: TraceRecord | null = null;
  private intentTurn: TraceTurn | null = null;
  // 工具事实原始行（factRef → 详情取参数/结果用；非状态量，不上屏）
  private facts: TraceFactIn[] = [];

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_SESSION_TRACE_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    this.conversationId = typeof last === 'string' ? last : '';
    if (this.conversationId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少会话参数' });
      this.pathStack.pop();
      return;
    }
    this.load();
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 销毁收口：清开意图（防销毁期框架回写可见性触发兜底补开——写已销毁组件）
    this.intentRecord = null;
    this.intentTurn = null;
  }

  // 装载链（进页一次）：先判有行 → 墓碑分流 → 四查一窗 → 组装
  private async load(): Promise<void> {
    try {
      const hasRow: boolean = await conversationHasRow(this.conversationId);
      if (this.departed) {
        return;
      }
      if (!hasRow) {
        this.loaded = true; // 无行会话 = 空态（「暂无轨迹记录」）
        return;
      }
      const route: string = await conversationWritableRoute(this.conversationId);
      if (this.departed) {
        return;
      }
      if (route === ROUTE_BLOCKED) {
        this.tombstone = true;
        this.loaded = true;
        return;
      }
      const window: TraceMessageWindow =
        await readTraceMessageWindow(this.conversationId, TRACE_TAIL_LIMIT);
        if (this.departed) {
          return;
        }
      const runs = await queryRunRowsByConversation(this.conversationId);
      if (this.departed) {
        return;
      }
      // 事实/用量按窗口内出现的 run 收窄（数据有界）；诊断按窗口内 run 的
      // diagnosticMessageId 反查（notice 不在 head 读路径上）
      const runIds: string[] = [];
      for (const row of window.rows) {
        if (row.runId !== '' && !runIds.includes(row.runId)) {
          runIds.push(row.runId);
        }
      }
      const facts = await queryToolFactsByRunIds(runIds);
      if (this.departed) {
        return;
      }
      const usages = await queryChatUsageByRunIds(runIds);
      if (this.departed) {
        return;
      }
      const diagIds: string[] = [];
      for (const run of runs) {
        if (run.diagnosticMessageId !== '' && runIds.includes(run.id)) {
          diagIds.push(run.diagnosticMessageId);
        }
      }
      const diagnostics = await queryTraceMessagesByIds(diagIds);
      if (this.departed) {
        return;
      }
      this.facts = facts;
      const model = assembleSessionTrace(window.rows, runs, facts, usages, diagnostics,
        window.truncated);
      this.truncated = model.truncated;
      this.turns = model.turns;
      this.loaded = true;
    } catch (e) {
      if (this.departed) {
        return;
      }
      // 不静默：读取失败如实呈报（页面保持空态可返回）
      this.getUIContext().getPromptAction().showToast({
        message: '轨迹读取失败，' + (e as Error).message
      });
      this.loaded = true;
    }
  }

  // 折叠/展开轮组（整体替换数组触发刷新；键纪律见文件头）
  private toggleTurn(key: string): void {
    const next: string[] = [];
    let found: boolean = false;
    for (const k of this.collapsedKeys) {
      if (k === key) {
        found = true;
      } else {
        next.push(k);
      }
    }
    if (!found) {
      next.push(key);
    }
    this.collapsedKeys = next;
  }

  private findFact(factRef: string): TraceFactIn | null {
    if (factRef === '') {
      return null;
    }
    for (const fact of this.facts) {
      if (fact.id === factRef) {
        return fact;
      }
    }
    return null;
  }

  // 点记录行开详情。★ 关闭-再开协调（真机报障「关面板后快点另一行，新面板立即被收起」）：
  // 离场动效在途期只记开意图、不写可见性——官方《半模态转场》「离场动效不支持打断，动效
  // 执行期间无法响应其他手势动作……需要等动效完全结束后才可以再次拉起」；在途期写下的
  // true 会被吞或被收尾回写压回。补开两路 = onSheetGone（正路）与 onSheetVisibleChanged
  //（回写压回兜底）
  private openRecord(rec: TraceRecord, turn: TraceTurn): void {
    this.intentRecord = rec;
    this.intentTurn = turn;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  // 按开意图落内容与可见性（openRecord 直开与两处补开共用单入口；无意图即无动作）
  private applyOpen(): void {
    const rec: TraceRecord | null = this.intentRecord;
    const turn: TraceTurn | null = this.intentTurn;
    if (rec === null || turn === null) {
      return;
    }
    this.sheetRecord = rec;
    this.sheetUsage = turn.usage;
    this.sheetFact = this.findFact(rec.factRef);
    this.sheetOpen = true;
  }

  // 离场动效结束（onDisappear——d.ts：动画结束后回调）：清在途位 + 按开意图补开（官方口径
  // 「等动效完全结束后才可再次拉起」的执行点）
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetOpen) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底：非用户关闭路径把可见性写回 false 时按开意图补一次（框架 `$$` 收尾回写
  // 落在动效之后的时序差）。用户关闭必经 requestCloseDetail（先清开意图再写 false），不误触本支
  private onSheetVisibleChanged(): void {
    if (!this.sheetOpen) {
      this.applyOpen();
    }
  }

  // 详情关闭单入口（规范-半模态 §1 新码硬约束：标题栏 xmark 与 onWillDismiss 两路同调；
  // 纯信息展示无暂存 ⇒ 直接关；关闭不复位内容形态 = 只置可见性）。★ 先清开意图（撤销在途期
  // 点下的待开）+ 置离场动效在途位，再写可见性
  private requestCloseDetail(): void {
    this.intentRecord = null;
    this.intentTurn = null;
    this.sheetClosing = true;
    this.sheetOpen = false;
  }

  // 空态与受限态行（墓碑呈报用 TOMBSTONE_NOTICE_TEXT 单源引用，禁抄文案）
  @Builder
  StateHint() {
    Text(this.tombstone ? TOMBSTONE_NOTICE_TEXT : '暂无轨迹记录')
      .fontSize(13)
      .fontColor(cardDescColor())
      .width(CARD_PANEL_WIDTH)
      .textAlign(TextAlign.Start)
  }

  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      if (!this.loaded) {
        // 装载中：空白（读取毫秒级；不设加载指示）
        Row() {
        }
        .width('100%')
        .height('100%')
      } else if (this.tombstone || this.turns.length === 0) {
        Scroll() {
          Column({ space: CARD_SPACING }) {
            this.StateHint()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .clip(false)
      } else {
        TraceTurnRows({
          turns: UIUtils.enableV2Compatibility(this.turns),
          collapsedKeys: UIUtils.enableV2Compatibility(this.collapsedKeys),
          truncated: this.truncated,
          appColorMode: this.appColorMode,
          topPad: this.topPad,
          bottomPad: this.bottomPad,
          onToggle: (key: string): void => {
            this.toggleTurn(key);
          },
          onOpen: (rec: TraceRecord, turn: TraceTurn): void => {
            this.openRecord(rec, turn);
          }
        })
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  // 详情半模态内容（面板内容件在 SessionTraceDetailSheet——本处只组装参数；bindSheet 挂页面
  // 根，规范-半模态 §1 挂点判据：合法树内 / 存活期不因数据销毁 / isShow 与触发键同组件位）
  @Builder
  TraceDetailSheet() {
    SessionTraceDetailSheet({
      record: this.sheetRecord,
      usage: this.sheetUsage,
      fact: this.sheetFact,
      bottomInset: this.bottomPad,
      onClose: (): void => {
        this.requestCloseDetail();
      }
    })
  }

  build() {
    PageShell({
      title: '会话轨迹',
      content: (): void => {
        this.Content()
      }
    })
      // 关闭链三件：可见性 `$$` 双向 + onWillDismiss 内放行后路由到 requestCloseDetail 单入口。
      // ★ 第四参 onDisappear = 关闭-再开协调的动效结束信号（在途期点下的待开在此补开；档位
      // 与回弹两参走缺省）
      .bindSheet($$this.sheetOpen, this.TraceDetailSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestCloseDetail();
        },
        undefined, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }
}

// ═══ 轨迹清单渲染域（V1 壳 + V2 渲染件，Repeat.virtualScroll）═══
// 键只写轮键（traceTurnKey）；折叠态经 collapsedKeys @Param 下发（整体替换承接刷新，不进键）。
@ComponentV2
struct TraceTurnRows {
  @Param turns: TraceTurn[] = [];
  @Param collapsedKeys: string[] = [];
  @Param truncated: boolean = false;
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  @Event onToggle: (key: string) => void = () => {
  };
  @Event onOpen: (rec: TraceRecord, turn: TraceTurn) => void = () => {
  };

  // 段权重（比例按真实时刻；零宽段给最小可见权重——失败段靠颜色可见的最小保底）
  private segWeight(seg: TraceSegment, turn: TraceTurn): number {
    const span: number = turn.endMs - turn.startMs;
    const unit: number = span > 0 ? span * 0.005 : 1;
    return Math.max(seg.t1 - seg.t0, unit);
  }

  // 段颜色（用户段次要灰 / 助手段主强调蓝 / 工具段主蓝 60% / 失败段警示红）
  private segColor(kind: string): ResourceColor {
    if (kind === TRACE_SEG_ASSISTANT) {
      return usageAccentColor(this.appColorMode);
    }
    if (kind === TRACE_SEG_TOOL) {
      return '#99' + usageAccentColor(this.appColorMode).substring(1);
    }
    if (kind === TRACE_SEG_FAILED) {
      return $r('sys.color.ohos_id_color_alert');
    }
    return cardDescColor();
  }

  private isCollapsed(turn: TraceTurn): boolean {
    return this.collapsedKeys.includes(traceTurnKey(turn));
  }

  // 记录行图标（kind 单源；失败/中止与进行中经由 recColor 着色）
  private recIcon(kind: string): Resource {
    if (kind === TRACE_KIND_USER) {
      return $r('sys.symbol.person');
    }
    if (kind === TRACE_KIND_ASSISTANT) {
      return $r('sys.symbol.message');
    }
    if (kind === TRACE_KIND_TOOL) {
      return $r('sys.symbol.wrench_and_screwdriver');
    }
    if (kind === TRACE_KIND_NOTICE) {
      return $r('sys.symbol.exclamationmark_triangle');
    }
    if (kind === TRACE_KIND_SUMMARY) {
      return $r('sys.symbol.archivebox');
    }
    if (kind === TRACE_KIND_CLEAR) {
      return $r('sys.symbol.xmark_circle');
    }
    return $r('sys.symbol.info_circle');
  }

  // 记录行主色（失败/中止 = 警示红；进行中 = 主蓝；其余标题色——图标与标题共用）
  private recColor(rec: TraceRecord): ResourceColor {
    if (rec.status === TRACE_STATUS_FAILED || rec.status === TRACE_STATUS_ABORTED) {
      return $r('sys.color.ohos_id_color_alert');
    }
    if (rec.status === TRACE_STATUS_RUNNING) {
      return usageAccentColor(this.appColorMode);
    }
    return cardTitleColor();
  }

  // 记录行右侧文字：工具行 = 耗时 / 「执行中」/「—」；助手行 = 首字耗时徽标；其余空
  private recRightText(rec: TraceRecord, turn: TraceTurn): string {
    if (rec.kind === TRACE_KIND_TOOL) {
      if (rec.durationMs > 0) {
        return traceDurationText(rec.durationMs);
      }
      return rec.status === TRACE_STATUS_RUNNING ? '执行中' : '—';
    }
    if (rec.kind === TRACE_KIND_ASSISTANT && turn.usage !== null && turn.usage.firstTokenMs > 0) {
      return '首字 ' + traceSecondsText(turn.usage.firstTokenMs);
    }
    return '';
  }

  // 轮头（第 N 轮 / 其他记录 + 状态徽标 + 起始时刻 + 总耗时；点按折叠/展开）
  @Builder
  TurnHead(ri: RepeatItem<TraceTurn>) {
    Row({ space: 8 }) {
      Text(traceTurnTitle(ri.item))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
      // 状态徽标（只显进行中与失败两态——完成不显章，未分组无态）
      if (ri.item.status === TRACE_STATUS_RUNNING || ri.item.status === TRACE_STATUS_FAILED) {
        Text(traceStatusTextOf(ri.item.status))
          .fontSize(12)
          .fontColor(ri.item.status === TRACE_STATUS_FAILED ?
            $r('sys.color.ohos_id_color_alert') : usageAccentColor(this.appColorMode))
      }
      Blank()
      Text(traceClockText(ri.item.startMs) +
        (ri.item.endMs > ri.item.startMs ?
          ' · ' + traceDurationText(ri.item.endMs - ri.item.startMs) : ''))
        .fontSize(13)
        .fontColor(cardDescColor())
      SymbolGlyph(this.isCollapsed(ri.item) ? $r('sys.symbol.chevron_right') :
        $r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([cardDescColor()])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onToggle(traceTurnKey(ri.item));
    })
  }

  // 简化时间条（按真实时刻比例分段；缺段不画；零宽段最小权重保底）
  @Builder
  TraceBar(turn: TraceTurn) {
    Row({ space: 1 }) {
      ForEach(turn.segments, (seg: TraceSegment) => {
        Row()
          .layoutWeight(this.segWeight(seg, turn))
          .height('100%')
          .backgroundColor(this.segColor(seg.kind))
      }, (seg: TraceSegment, idx: number): string => seg.kind + ':' + seg.t0 + ':' + seg.t1 + ':' + idx)
    }
    .width('100%')
    .height(6)
    .borderRadius(3)
    .backgroundColor(badgeBg(this.appColorMode))
    .clip(true)
  }

  // 记录行（图标 + 标题 + 摘要 + 右侧时长/首字；点按开详情）
  @Builder
  RecordRow(rec: TraceRecord, turn: TraceTurn) {
    Row({ space: 10 }) {
      SymbolGlyph(this.recIcon(rec.kind))
        .fontSize(16)
        .fontColor([this.recColor(rec)])
      Column({ space: 2 }) {
        Text(rec.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.recColor(rec))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (rec.summary !== '') {
          Text(rec.summary)
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.recRightText(rec, turn) !== '') {
        Text(this.recRightText(rec, turn))
          .fontSize(13)
          .fontColor(cardDescColor())
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    .onClick((): void => {
      this.onOpen(rec, turn);
    })
  }

  @Builder
  TurnCard(ri: RepeatItem<TraceTurn>) {
    Column({ space: 10 }) {
      this.TurnHead(ri)
      this.TraceBar(ri.item)
      if (!this.isCollapsed(ri.item)) {
        ForEach(ri.item.records, (rec: TraceRecord) => {
          this.RecordRow(rec, ri.item)
        }, (rec: TraceRecord): string => rec.id)
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    List({ space: CARD_SPACING }) {
      Repeat<TraceTurn>(this.turns)
        .each((ri: RepeatItem<TraceTurn>) => {
          ListItem() {
            Column({ space: CARD_SPACING }) {
              if (ri.index === 0 && this.truncated) {
                // 截断呈报（数据有界红线 >TRACE_TAIL_LIMIT 时）
                Text('仅显示最近部分，更早的记录未列出')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width(CARD_PANEL_WIDTH)
                  .textAlign(TextAlign.Start)
              }
              this.TurnCard(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 轮键（runId / 未分组常量；折叠态不进键——键纪律红线）
        .key((turn: TraceTurn): string => traceTurnKey(turn))
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .cachedCount(5)
  }
}
