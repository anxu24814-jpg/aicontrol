// 上下文用量半模态面板（2026-09-17 方案-会话上下文用量 执行笔 4，拍板 P3/P5~P8）：
// 面板内容件（不含 bindSheet——宿主 ChatPage 页面根唯一挂载点，坑64 姿势；规范-半模态
// §8「面板内容件」先例）。形制 = KimiFullInputSheet/ModelPickerSheet 同款三件套
//（HdsNavigation MODAL 壳 + sheetTitleBarOptions 5 参规格 + bindToScrollable 滚动感知 +
// 底部安全区延伸），滚动容器 clip(false)（规范 §2——渐变模糊要有内容可透）。
// 内容两卡（2026-09-19 会话统计笔：原四卡收两卡——「上轮实际」「本会话累计」两卡按
// 决明指令移入新会话统计面板 SessionStatsSheet，本件回归「窗口占用」单一职责；原底部
// 说明行 2026-09-18 移入首卡右上角信息气泡——决明指令「消息用量半模态，底部提示收入
// 首卡右上角气泡，同先例」；先例 = 外观页光感新规范开关卡「长说明移入气泡、卡面留关键
// 句」；方案 §4.4；2026-09-18 增量笔两增——总览卡进度环 + 缓存命中行、明细卡分项符号；
// 同日晚「本会话累计」卡笔——首卡缓存行退掉绝对数只留命中率 + 新增累计卡；同日观感笔
// 〔决明指令「取消进度条，环大/粗一点，缓存率与百分比上下交换，首卡排版舒展些」〕——
// 分段堆叠条退役、环放大加粗至 56/6、缓存率与百分比大字上下交换、首卡三档间距放宽）：
// · 总览卡——进度环（共用件，输入条圆环同形制同色档，面板档 56/6）+ 百分比大字在上、
//   缓存命中率行在下（账本会话聚合；★ 只显百分比不显 token 数——「35.6k 对 8.1k」不同基
//   并列曾被读成一本账，绝对数在会话统计面板 Token 用量卡）+「已用/上限」行（≥80% 附一句
//   行动提示，拍板 P7）；★ 分段堆叠条已退役（2026-09-18 决明指令——占比看环、分项看明细
//   卡，条与环信息重复）；
// · 明细卡——逐段行（分项符号 + 标签左·数值右，UsageRow 形制）+「其他」兜底段（差值 >1%
//   才出，P8）+ 空闲行；窗口未知（windowTokens 0）整卡不显（P4：只显已用数）；
// · 首卡右上角信息气泡（原底部说明行，2026-09-18 决明指令移入）——口径一句（估算随请求校准）
//   + 缓存误解消解（缓存只影响计费不改变窗口占用，方案 §4.4-4）；窗口未知时替换为引导去
//   模型编辑页配置。形制 = InfoHintButton（卡右上角 info 图标 + 官方 bindPopup 气泡，
//   先例外观页光感新规范开关卡），两态文本与原说明行逐字一致。
// ★ 0 与未知区分（§5，Cherry #19965）：hasData false 或 usage null 显「暂无/正在统计」，
// 禁渲染 0%。数据经 @Link 下发（页面活算落地自动刷新；重算进行中保留旧值不清空，
// Cline #3861 反面）。可加总红线（§3.4）：明细各行 + 其他 = 已用，加空闲 = 上限。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { InfoHintButton } from '../InfoHintButton';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY, overlayMaterial
} from '../../common/ImmersiveLevel';
import { cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  CARD_PANEL_WIDTH, CARD_SPACING } from '../../common/Theme';
import { ContextSegment, tokenShort } from '../../common/TokenEstimate';
import { compressibleReady, estimateCompressSaving } from '../../common/CompressGen';
import { queryBoundaryCreatedAt, queryLatestSummary,
  deleteSummaryRows } from '../../common/store/CompressDb';
import { MessageRow } from '../../common/store/ChatDb';
import { ContextUsage, contextPct } from './ChatContextUsage';
import { ContextUsageRing } from './ContextUsageRing';
import { ChatMessage } from './ChatMessageCompose';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 「其他」兜底段出列门槛（P8：差值占上限 >1% 才列——可见噪声与可加总的折中）
const OTHER_SEGMENT_MIN_PCT: number = 0.01;

@Component
export struct ContextUsageSheet {
  // 最近一次活算产物（页面 @State 经 $ 绑定——活算落地自动刷新；null = 首开计算中占位）
  @Link usage: ContextUsage | null;
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主 bottomPad 注入——尾部占位，坑66 方案 B）
  bottomInset: number = 0;
  // ── 上下文压缩卡供给（2026-09-23 上下文压缩，任务书 §3.1）：面板此前无任何动作按钮，
  // 本卡是唯一动作面。refs 闭包由宿主 ChatPage 注入（子件不反向 import 宿主）──
  // conversationId = 本次会话的持久标识；**空串 = 无持久会话**（隐私会话零落痕模式由宿主
  // 传 ''）⇒ 压缩卡整卡不渲染 + 状态装载整块跳过——摘要必须落库才成立，本模式无行可落、
  // 写库又破零留痕红线。★ 2026-09-23 自检轮补：原实现宿主无条件带 id、卡照渲染且键可点，
  // 落库路径可达（当时仅靠「本会话消息无库序号」误打误撞挡住）
  conversationId: string = '';
  allMessages: () => ChatMessage[] = () => [];
  clipLimit: () => number = () => 0;
  // 流式态快照（置灰三条件之一；回调现读 = 弹出后每次重算）
  sending: () => boolean = () => false;
  // 打开压缩预览面板（宿主切 sheetKind='compress'——本面板随之收起，同宿主单面板多形态）
  onCompress: () => void = () => {
  };
  // 摘要删除完成上行（宿主移除流内提示行 + 刷新用量）
  onSummaryDeleted: (summaryId: string) => void = () => {
  };
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 压缩卡自持状态（开面板时装载；采用/删除后宿主重开面板自然重载）
  @State private summaryRow: MessageRow | null = null;
  @State private boundaryAt: number = 0;
  @State private savedTokens: number = 0;
  @State private readyToCompress: boolean = false;
  @State private summaryExpanded: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 无持久会话（隐私会话/空引用）⇒ 压缩卡不渲染，状态装载整块跳过（零查询零估算）
    if (this.conversationId === '') {
      return;
    }
    this.reloadCompressState();
  }

  // 压缩卡状态装载（面板打开时一次）：摘要行 + 边界时间 + 节省量 + 可压判定。查询失败降级
  // 「未压缩」态不炸面板（P0-1 的留痕在域件 hilog）
  private reloadCompressState(): void {
    this.savedTokens = estimateCompressSaving(this.allMessages(), this.clipLimit());
    this.readyToCompress = compressibleReady(this.allMessages());
    const convId: string = this.conversationId;
    if (convId === '') {
      this.summaryRow = null;
      this.boundaryAt = 0;
      return;
    }
    queryLatestSummary(convId)
      .then((row: MessageRow | null): void => {
        this.summaryRow = row;
        this.boundaryAt = 0;
        if (row !== null && row.coversToSeq !== undefined) {
          queryBoundaryCreatedAt(convId, row.coversToSeq)
            .then((at: number): void => {
              this.boundaryAt = at;
            })
            .catch((): void => {
              this.boundaryAt = 0;
            });
        }
      })
      .catch((): void => {
        this.summaryRow = null;
      });
  }

  // 压缩键置灰三条件（任务书 §3.1）：①流式进行中 ②窗口未知 ③可压段不足——任一命中置灰
  private compressDisabled(): boolean {
    return this.sending() || this.winTokens() <= 0 || !this.readyToCompress;
  }

  // 置灰原因一行（文案规约：分句句号、无冒号分号连环）
  private compressDisabledReason(): string {
    if (this.sending()) {
      return '回复进行中，结束后可压缩';
    }
    if (this.winTokens() <= 0) {
      return '该模型未配置上下文窗口，暂不能压缩';
    }
    return '历史还短，暂时不用压缩';
  }

  // 状态行文案：已压缩 · 节省约 N tokens · 覆盖 … 之前的内容（边界行已被删回 0 = 不带时间
  // 部分——别为凑时间造第二个时钟源，任务书 §3.1）
  private compressStateText(): string {
    if (this.summaryRow === null) {
      return '未压缩';
    }
    let text: string = '已压缩 · 节省约 ' + tokenShort(this.savedTokens) + ' tokens';
    if (this.boundaryAt > 0) {
      text += ' · 覆盖 ' + this.formatBoundaryTime() + ' 之前的内容';
    }
    return text;
  }

  // 边界时间（SessionStatsSheet 同款本地格式化：YYYY-MM-DD HH:mm）
  private formatBoundaryTime(): string {
    const d: Date = new Date(this.boundaryAt);
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
      pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  // 删除摘要（破坏性动作 → 官方对话框二次确认；确认 → 删行（事务 + 附件级联）→ 上行宿主
  // 移除流内提示行并刷新用量——下一次请求回到全文）
  private async confirmDeleteSummary(): Promise<void> {
    const row: MessageRow | null = this.summaryRow;
    if (row === null) {
      return;
    }
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: '删除摘要？',
        message: '删除后下一次请求回到全文，上下文占用会回升',
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '删除', color: $r('sys.color.font_primary') }
        ]
      });
      if (choice.index !== 1) {
        return;
      }
    } catch (e) {
      return; // 弹窗异常不删（宁可不删不可误删）
    }
    try {
      await deleteSummaryRows([row.id]);
      this.summaryRow = null;
      this.boundaryAt = 0;
      this.savedTokens = 0;
      this.onSummaryDeleted(row.id);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: '删除失败：' + (e as Error).message });
    }
  }

  // ── 空安全读取口（@Link 可空对象，闭包/插值处禁裸取——统一经本组方法）──
  private pct(): number {
    return this.usage !== null ? contextPct(this.usage) : -1;
  }

  private winTokens(): number {
    return this.usage !== null ? this.usage.windowTokens : 0;
  }

  private usedTokens(): number {
    return this.usage !== null ? this.usage.usedTokens : 0;
  }

  private segList(): ContextSegment[] {
    return this.usage !== null ? this.usage.segments : [];
  }

  private otherTokens(): number {
    return this.usage !== null ? this.usage.otherTokens : 0;
  }

  // 待发附件未处理完（2026-09-23 活算纳入待发附件笔）：解析中/识别中的件文本侧尚未计入
  //——true 才显明细卡提示行（false = 零噪声不显）
  private attachPending(): boolean {
    return this.usage !== null && this.usage.attachPending;
  }

  // ★ 首字均值（平均首字耗时）本件不承载：2026-09-23 曾短暂落本面板总览卡（941 节），同日
  // 二次改判迁「会话统计」面板 Token 用量卡末行（942 节，决明「移入会话统计吧」）——本件
  // 与首字面的唯一关系回到既有的「气泡弹层按条显示」
  // 会话级缓存命中率（2026-09-18 增量笔；-1 = 不显行）：无账本记录或零命中均不显——
  // 「缓存行 >0 才显」同款零噪声口径（无缓存协议常驻 0% 是噪声非信息）；有命中钳 100 防
  // 上游异常越界。★ 只显比率：绝对数与「已用」不同基（计费口径 vs 窗口规模口径），同行
  // 并列会被读成同一本账——token 数落「本会话累计」卡（真机账本实证 + 决明指令）
  private cacheHitPct(): number {
    if (this.usage === null || this.usage.sessionTotals === null ||
      this.usage.sessionTotals.cachedTokens <= 0) {
      return -1;
    }
    return Math.min(100, Math.round(this.usage.sessionTotals.cachedTokens * 100 /
      this.usage.sessionTotals.promptTokens));
  }

  // 分段符号映射（2026-09-18 增量笔：分项行前小图标，语义对应——名称经 SDK sysResource
  // 符号表实名核对；集中一函数 = 键集演进单点，未知键兜底问号圆）
  private segSymbol(key: string): Resource {
    if (key === 'prompt') {
      return $r('sys.symbol.gearshape');
    }
    if (key === 'skills') {
      return $r('sys.symbol.wand_and_stars');
    }
    if (key === 'memory') {
      return $r('sys.symbol.book_pages');
    }
    if (key === 'tools') {
      return $r('sys.symbol.wrench_and_screwdriver');
    }
    if (key === 'user') {
      return $r('sys.symbol.person');
    }
    if (key === 'assistant') {
      return $r('sys.symbol.text_bubble_left_2');
    }
    if (key === 'toolResults') {
      return $r('sys.symbol.list_checkmark');
    }
    if (key === 'draft') {
      return $r('sys.symbol.square_and_pencil');
    }
    if (key === 'reserved') {
      return $r('sys.symbol.hourglass');
    }
    // 「其他」= 命名段和与总量的差值兜底段（与合并段「其余 N 段」同取省略号圆）
    if (key === 'other') {
      return $r('sys.symbol.ellipsis_circle');
    }
    if (key === 'othersSmall') {
      return $r('sys.symbol.ellipsis_circle');
    }
    if (key === 'free') {
      return $r('sys.symbol.minus_circle');
    }
    return $r('sys.symbol.questionmark_circle');
  }

  // 预警文案（≥80% 出现，P7 + 附录 A #31：给「为什么 + 怎么办」的可读文案；过文案规约
  //——分句句号、无冒号分号连环）
  private warnText(): string {
    return '上下文接近上限，可在助手设置里限制发送条数，或新建会话。';
  }

  // 口径说明全文（原底部说明行，2026-09-18 移入首卡右上角气泡；两态文本与原行逐字一致
  // ——窗口已知 = 估算口径 + 缓存误解消解，未知 = 引导去模型编辑页配置）
  private hintText(): string {
    return this.winTokens() > 0 ?
      '用量为估算，随实际请求校准。缓存只影响计费，不改变窗口占用。' :
      '该模型未配置上下文窗口，可在模型编辑页填写。';
  }

  @Builder
  OverviewCard() {
    // 首卡间距 14（2026-09-18 决明「首卡排版舒展些」——余下三卡行列表仍 10/12 档）
    Column({ space: 14 }) {
      // 右上角信息气泡（2026-09-18 决明「底部提示收入首卡右上角气泡，同先例」——原面板底部
      // 说明行移此）：★ **与主行同行**，不另起一行——InfoHintButton 是 Button 形态（默认高
      // ≈40vp，比 18fp 图标高得多），单起一行会在卡顶留一条空行、把环与大字整体压下去
      //（2026-09-18 决明真机报障「怎么把环与百分比顶到下面了，组件大小还是避让没设好吗」）。
      // 落位 = 主行末位（主行 `space:16` + 大字列 layoutWeight(1) ⇒ 气泡贴主行右缘 = 整卡
      // 右上角）；无数据（暂无）分支该行只有一行字，故按规范-列表卡片 §4.3 形制「文字
      // layoutWeight(1) + 行尾 InfoHintButton」同行承载；「正在统计」态与退役前一致不挂气泡。
      if (this.usage === null) {
        Text('正在统计用量')
          .fontSize(15)
          .fontColor(cardDescColor())
      } else if (!this.usage.hasData) {
        // §5 无任何可用数据：显「暂无」，禁渲染 0%（0 与未知区分）
        Row() {
          Text('暂无可统计的用量')
            .fontSize(15)
            .fontColor(cardDescColor())
            .layoutWeight(1)
          InfoHintButton({ text: this.hintText() })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        // 主行 = 进度环 + 右列（百分比大字在上、缓存命中率在下——2026-09-18 决明指令上下
        // 交换，原缓存行在占比前）。环 = 共用件 56vp/6vp（输入条 20/3 同形制同色档，
        // ContextUsageRing 单源；56/6 为面板观感档，2026-09-18「环大/粗一点」）；窗口未知
        // pct -1 仅底环，大字显已用数（P4）
        Row({ space: 16 }) {
          ContextUsageRing({ pct: this.pct(), ringSize: 56, ringStroke: 6 })
          Column({ space: 6 }) {
            // 大字：窗口已知 = 占比（P2 圆环不显数字的对照——面板是「看明细」处）；未知 = 已用数（P4）
            Text(this.pct() >= 0 ? this.pct() + '%' : '已用 ' + tokenShort(this.usedTokens()))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
            if (this.cacheHitPct() >= 0) {
              Text('缓存命中 ' + this.cacheHitPct() + '%')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
          }
          .alignItems(HorizontalAlign.Start)
          // 大字列吃满剩余宽 ⇒ 紧随其后的气泡贴主行右缘（整卡右上角），与主行同行零额外行高
          .layoutWeight(1)
          InfoHintButton({ text: this.hintText() })
        }
        // ★ 顶部对齐（2026-09-18 决明二轮真机「但是偏低啊，没跟环顶齐平」）：原 Center 对齐
        // 下气泡被行高居中（大字列 ≈62vp > 环 56vp ⇒ 气泡顶比环顶低出近一个身位）；改 Top 后
        // 环顶 / 大字列顶 / 气泡顶同起于行顶 ⇒ 气泡与环顶齐平（行高仍由最高件决定，不变）
        .alignItems(VerticalAlign.Top)
        if (this.pct() >= 0) {
          Text('已用 ' + tokenShort(this.usedTokens()) + ' / 上限 ' +
            tokenShort(this.winTokens()))
            .fontSize(13)
            .fontColor(cardDescColor())
          if (this.pct() >= 80) {
            Text(this.warnText())
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_warning'))
          }
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 明细行（分项符号 + 标签左·数值右，ChatMessageItem.UsageRow 形制：标签次要色、数值主色
  // 加粗；符号 = segSymbol 映射 14vp 同色，2026-09-18 增量笔）
  @Builder
  DetailRow(label: string, tokens: number, key: string) {
    Row({ space: 6 }) {
      SymbolGlyph(this.segSymbol(key))
        .fontSize(14)
        .fontColor([cardDescColor()])
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(tokenShort(tokens) + ' · ' + Math.round(tokens * 100 / this.winTokens()) + '%')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
  }

  @Builder
  DetailCard() {
    Column({ space: 10 }) {
      Text('分段明细')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      Column({ space: 12 }) {
        ForEach(this.segList(), (seg: ContextSegment) => {
          this.DetailRow(seg.label, seg.tokens, seg.key)
        }, (seg: ContextSegment): string => seg.key + '|' + seg.tokens)
        // 「其他」兜底段（P8：差值 >1% 才出——协议包装/图片折算误差的可归因落点，可加总
        // 红线：各行相加能对上总数，Claude Code #18241 同屏矛盾的反面）
        if (this.otherTokens() * 1.0 / this.winTokens() > OTHER_SEGMENT_MIN_PCT) {
          this.DetailRow('其他', this.otherTokens(), 'other')
        }
        // 空闲行（已用超窗时钳 0 不显负）
        if (this.winTokens() - this.usedTokens() > 0) {
          this.DetailRow('空闲', this.winTokens() - this.usedTokens(), 'free')
        }
        // 待发附件提示行（2026-09-23 活算纳入待发附件笔）：有件尚未处理完（解析中/识别中）
        // 时该部分文本侧未计入——不说破会被读成面板漏算（Cherry #17079「估算漏算而不说明」
        // 同族）；长句随状态条件渲染留在板块内（规范-列表卡片与组卡「状态提示」条：优于藏进
        // 气泡），13fp 次要色 = 本面板说明小字既有形制
        if (this.attachPending()) {
          Text('有附件尚未处理完，未计入用量。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // ── 上下文压缩卡（2026-09-23 上下文压缩，任务书 §3.1；卡内三段次序照宪法「功能设置卡
  //    布局次序」条：状态行 → 说明小字 → 操作行）──
  @Builder
  CompressCard() {
    Column({ space: 10 }) {
      Text('上下文压缩')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      // ① 状态行：无摘要 =「未压缩」；有摘要 = 节省量 + 覆盖范围 + 摘要正文折叠区（只读）
      Text(this.compressStateText())
        .fontSize(13)
        .fontColor(cardDescColor())
      if (this.summaryRow !== null) {
        Row() {
          Text(this.summaryExpanded ? '收起摘要' : '展开摘要')
            .fontSize(13)
            .fontColor(cardTitleColor())
          Blank()
          SymbolGlyph(this.summaryExpanded ? $r('sys.symbol.chevron_up') :
            $r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([cardDescColor()])
        }
        .width('100%')
        .onClick((): void => {
          this.summaryExpanded = !this.summaryExpanded;
        })
        if (this.summaryExpanded) {
          Text(this.summaryRow.content)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
      }
      // ② 说明小字（操作行上方——布局次序条）
      Text('压缩只影响之后发送的内容，原消息仍保存在本机会话里')
        .fontSize(13)
        .fontColor(cardDescColor())
      // ③ 操作行：主键「压缩上下文 / 重新压缩」（面板唯一入口）；有摘要时并列「删除摘要」
      //（破坏性 → ConfirmDialog 二次确认）。键形制照规范-行内按钮与光感：行内文字键
      // resolvedButton 四件套，破坏性项不做红色自绘
      Row({ space: 10 }) {
        Button(this.summaryRow === null ? '压缩上下文' : '重新压缩')
          .enabled(!this.compressDisabled())
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.onCompress();
          })
        if (this.summaryRow !== null) {
          Button('删除摘要')
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.confirmDeleteSummary();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.compressDisabled()) {
        Text(this.compressDisabledReason())
          .fontSize(12)
          .fontColor(cardDescColor())
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          this.OverviewCard()
          // 明细卡仅窗口已知（P4：未知时不显占比与分段条，引导去配置）
          if (this.usage !== null && this.usage.hasData && this.usage.windowTokens > 0) {
            this.DetailCard()
          }
          // 压缩卡（2026-09-23：DetailCard 之后——动作面殿后）。★ 无持久会话（隐私会话零落痕
          // 模式由宿主传 ''）整卡不渲染：摘要必须落库，本模式无行可落（2026-09-23 自检轮补）
          if (this.conversationId !== '') {
            this.CompressCard()
          }
          // 「上轮实际」「本会话累计」两卡已于 2026-09-19 移入会话统计面板 SessionStatsSheet
          //（决明指令）——此处退役，负向钉见 assert-ui-shape 会话统计组
          // 口径说明行已于 2026-09-18 移入首卡右上角信息气泡（hintText + InfoHintButton），
          // 此处退役——负向钉见 assert-ui-shape 122 组（旧 Text 三元形态零回流）
          // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条；Row 空占位——
          // Blank 在部分容器下编译 10905201，规范-半模态 §2 先例用 Row）
          Row()
            .height(this.bottomInset)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('上下文用量', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
