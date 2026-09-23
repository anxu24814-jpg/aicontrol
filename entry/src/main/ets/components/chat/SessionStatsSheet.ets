// 会话统计半模态面板（2026-09-19，决明指令「会话统计半模态，入口放消息页标题栏更多菜单，
// 把原输入框上下文面板的上轮实际与本会累计移入会话统计；不做模型分布与生图统计；不要
// 完全照搬竞品排版，按我们惯例可按语义分类重组」）：面板内容件（不含 bindSheet——宿主
// ChatPage 页面根唯一挂载点，坑64 姿势；规范-半模态 §8「面板内容件」先例）。形制 =
// ContextUsageSheet 同款三件套（HdsNavigation MODAL 壳 + sheetTitleBarOptions + 
// bindToScrollable 滚动感知 + 底部安全区延伸），滚动容器 clip(false)（规范 §2）。
// 内容四卡（竞品为「基本信息」单卡平铺九行，本面板按语义分四组——计数 / 时间 / 用量 /
// 末轮实测，行形制沿用本仓 StatRow「标签左·数值右」族）：
// · 会话概况卡——消息总数（user+assistant 对话行）/ 用户消息 / AI 回复 / 工具调用
//   （role='tool' 卡行）/ 附件数（message_attachments 计数）；
// · 时间卡——首条消息 / 最后活跃 / 时间跨度（三值同源 messages.createdAt 的 MIN/MAX，
//   只取 user/assistant 行与消息总数同基；无消息行整卡不显——0 与未知区分）；
// · Token 用量卡——账本 token_usage_events 按会话聚合（**计费口径**，含工具轮每轮重发的
//   全量上下文；与上下文面板「已用」的窗口规模口径不同基，禁互相换算——同
//   ContextUsageSheet.SessionTotalsCard 退役注记）：总 Token / 输入 / 缓存命中（>0 才显）
//   / 输出 / 轮均 Token（÷ 对话轮数 = 账本行数）/ 生成总耗时 / 平均速度（输出 ÷ 耗时）。
//   本卡 = 原上下文面板「本会话累计」卡移入并扩形（原三行 + 新四行），数据源
//   sessionTotals 经 $ctxUsage @Link 同链（sessionUsageTotals 扩三值同笔）；无账本记录
//   整卡不显；
// · 上轮实际卡——原上下文面板同名卡**原样迁入**（末轮真实用量：输入/缓存/输出/用时/
//   生成速度；数据源 usage.lastUsage = 末条带用量 assistant 行——meta 由回放链按账本
//   回填〔ChatPageLoad.attachUsageMeta 按 messageId 命中即挂，无 status 过滤〕，故重启
//   重进会话后照常显示；隐私会话零落库不挂 meta，同此不显）。
// 入口与可见性：标题栏「更多」菜单「会话统计」项（ChatMoreMenu）；**隐私会话隐藏入口**——
// 隐私会话零落库（会话行/消息行/账本全旁路），库侧统计恒全零，显示全零面板是误导。
// 空态：概况/时间卡数据查询失败降级不显（catch 保留 null，不翻转为 0 静默谎报）；四卡
// 全不显时显「暂无可统计的数据」兜底行（面板不为白屏）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  CARD_PANEL_WIDTH, CARD_SPACING } from '../../common/Theme';
import { tokenShort } from '../../common/TokenEstimate';
import { fmtFirstTokenMs } from '../../common/store/UsageStatsCalc';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { ContextUsage } from './ChatContextUsage';
import { ConversationMsgStats, conversationMsgStats, queryAttachmentCount }
  from '../../common/store/ChatDb';

@Component
export struct SessionStatsSheet {
  // 最近一次活算产物（页面 @State 经 $ 绑定——轮次收尾自动刷新；打开时页面侧另刷一次，
  // 见 ChatPage.openStatsSheet）：上轮实际卡与 Token 用量卡共读
  @Link usage: ContextUsage | null;
  // 目标会话 id（宿主注入；懒会话同 id——首条消息触发建行，统计查询对空表返真零）
  conversationId: string = '';
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主 bottomPad 注入——尾部占位，坑66 方案 B）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 消息统计（null = 未加载或查询失败——概况/时间卡不显，不静默显 0）
  @State msgStats: ConversationMsgStats | null = null;
  // 附件计数（-1 = 未加载或查询失败——「附件数」行不显；≥0 = 真值含 0）
  @State attachCount: number = -1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadStats();
  }

  // 统计装载（开面板一次，只读快照不做订阅——P2-4 克制；两查询失败各自降级互不连坐）
  private async loadStats(): Promise<void> {
    try {
      const stats: ConversationMsgStats = await conversationMsgStats(this.conversationId);
      this.msgStats = stats;
    } catch (e) {
      // 查询失败按「未知」隐藏概况/时间卡（0 与未知区分同面板既有口径）
    }
    try {
      const count: number = await queryAttachmentCount(this.conversationId);
      this.attachCount = count;
    } catch (e) {
      // 同上，仅隐藏「附件数」行
    }
  }

  // ── 空安全读取口（@Link 可空对象，闭包/插值处禁裸取——统一经本组方法）──
  private sessionTotals() {
    return this.usage !== null ? this.usage.sessionTotals : null;
  }

  private lastUsage() {
    return this.usage !== null ? this.usage.lastUsage : null;
  }

  // 大数值 token 缩写（Token 用量卡专用）：k 档复用 tokenShort 口径，扩 M 档——长会话累计
  // 可达百万级（竞品同场景 3.7M），「3644.9k」不可读；上轮实际卡维持 tokenShort 原样（单轮
  // 值域小，迁卡不改形）
  private statToken(n: number): string {
    if (n >= 1000000) {
      return (Math.round(n / 100000) / 10) + 'M';
    }
    return tokenShort(n);
  }

  // 全量时间串（时间卡专用）：YYYY-MM-DD HH:mm——统计面板跨天跨度大，带年月（会话列表
  // formatConvTime 的「MM-DD HH:mm」省年形态不适用）
  private formatFullTime(ts: number): string {
    const d: Date = new Date(ts);
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
      pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  // 时间跨度（首末差人性化）：向下取整粗粒度——「跨度」读的是量级非精度
  private spanText(ms: number): string {
    const minutes: number = Math.floor(ms / 60000);
    if (minutes < 1) {
      return '1 分钟内';
    }
    if (minutes < 60) {
      return minutes + ' 分钟';
    }
    if (minutes < 1440) {
      return Math.floor(minutes / 60) + ' 小时';
    }
    return Math.floor(minutes / 1440) + ' 天';
  }

  // 生成总耗时（累计精确值）：<60s 一位小数秒（上轮实际卡 durationValue 同口径），
  // ≥60s「M 分 S 秒」（S 为 0 只留分——文案规约无多余括号）
  private durationText(ms: number): string {
    const seconds: number = ms / 1000;
    if (seconds < 60) {
      return (Math.round(seconds * 10) / 10) + 's';
    }
    const minutes: number = Math.floor(seconds / 60);
    const rest: number = Math.round(seconds - minutes * 60);
    return rest > 0 ? minutes + ' 分 ' + rest + ' 秒' : minutes + ' 分';
  }

  // 用时数值串（<60s 一位小数否则整数秒——ContextUsageSheet 同口径，随卡迁入）
  private durationValue(ms: number): string {
    const seconds: number = ms / 1000;
    return seconds < 60 ? (Math.round(seconds * 10) / 10) + 's' : Math.round(seconds) + 's';
  }

  // 标签左·数值右的统计行（ContextUsageSheet.StatRow 同形制随两卡迁入——原面板两卡
  // 退役后该件已无此行消费方，行 builder 归位本面板单源）
  @Builder
  StatRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
  }

  // 卡骨架（三卡行列表同族：标题 15 加粗 + 分割线 + 行距 12 行列，卡距/内边距与
  // ContextUsageSheet 全同源）
  @Builder
  StatCard(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(cardTitleColor())
    Divider()
      .strokeWidth(1)
      .color(cardBorderColor(this.appColorMode))
  }

  @Builder
  OverviewCard() {
    Column({ space: 10 }) {
      this.StatCard('会话概况')
      Column({ space: 12 }) {
        this.StatRow('消息总数', String(this.msgStats!.userCount + this.msgStats!.assistantCount))
        this.StatRow('用户消息', String(this.msgStats!.userCount))
        this.StatRow('AI 回复', String(this.msgStats!.assistantCount))
        this.StatRow('工具调用', String(this.msgStats!.toolCount))
        if (this.attachCount >= 0) {
          this.StatRow('附件数', String(this.attachCount))
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

  @Builder
  TimeCard() {
    Column({ space: 10 }) {
      this.StatCard('时间')
      Column({ space: 12 }) {
        this.StatRow('首条消息', this.formatFullTime(this.msgStats!.firstAt))
        this.StatRow('最后活跃', this.formatFullTime(this.msgStats!.lastAt))
        this.StatRow('时间跨度', this.spanText(this.msgStats!.lastAt - this.msgStats!.firstAt))
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // Token 用量卡（原「本会话累计」卡移入扩形；行序 = 总 → 输入 → 缓存命中 → 输出 → 轮均
  // → 耗时 → 速度 → 首字——缓存是输入子集相邻才读出「其中」关系，派生值〔轮均/耗时/速度/
  // 首字〕殿后；★ 2026-09-23 首字耗时笔同日改判落点 = 本卡末行「平均首字耗时」）
  @Builder
  TokenCard() {
    Column({ space: 10 }) {
      this.StatCard('Token 用量')
      Column({ space: 12 }) {
        this.StatRow('总 Token', this.statToken(this.sessionTotals()!.totalTokens))
        this.StatRow('输入', this.statToken(this.sessionTotals()!.promptTokens))
        if (this.sessionTotals()!.cachedTokens > 0) {
          this.StatRow('缓存命中', this.statToken(this.sessionTotals()!.cachedTokens))
        }
        this.StatRow('输出', this.statToken(this.sessionTotals()!.completionTokens))
        if (this.sessionTotals()!.rounds > 0) {
          this.StatRow('轮均 Token',
            this.statToken(Math.round(this.sessionTotals()!.totalTokens /
              this.sessionTotals()!.rounds)))
        }
        if (this.sessionTotals()!.durationMs > 0) {
          this.StatRow('生成总耗时', this.durationText(this.sessionTotals()!.durationMs))
        }
        if (this.sessionTotals()!.durationMs > 0 && this.sessionTotals()!.completionTokens > 0) {
          this.StatRow('平均速度', Math.round(this.sessionTotals()!.completionTokens /
            (this.sessionTotals()!.durationMs / 1000)) + ' tok/s')
        }
        // 平均首字耗时（2026-09-23 首字耗时笔；同日两度改判落点：设置页总览格 → 上下文用量
        // 面板 → 本卡）：会话级聚合的 fs ÷ fn，**分母只认有首字记录的轮**（存量轮与无产出
        // 正文的轮恒 0 不进分母）；无记录不显（0 与未知区分同本面板口径）；数值形制随本卡
        // 时间面行（秒一位小数带 s，同生成总耗时 <60s 档）；公式单源 = CALC 层 fmtFirstTokenMs
        if (this.sessionTotals()!.firstTokenRecords > 0) {
          this.StatRow('平均首字耗时',
            fmtFirstTokenMs(this.sessionTotals()!.firstTokenSumMs,
              this.sessionTotals()!.firstTokenRecords) + 's')
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

  // 上轮实际卡（原上下文面板同名卡原样迁入——行集与条件零改动）
  @Builder
  LastRoundCard() {
    Column({ space: 10 }) {
      this.StatCard('上轮实际')
      Column({ space: 12 }) {
        this.StatRow('输入', tokenShort(this.lastUsage()!.promptTokens))
        if (this.lastUsage()!.cachedTokens > 0) {
          this.StatRow('缓存', tokenShort(this.lastUsage()!.cachedTokens))
        }
        this.StatRow('输出', tokenShort(this.lastUsage()!.completionTokens))
        if (this.lastUsage()!.durationMs > 0) {
          this.StatRow('用时', this.durationValue(this.lastUsage()!.durationMs))
          this.StatRow('生成速度', Math.round(this.lastUsage()!.completionTokens /
            (this.lastUsage()!.durationMs / 1000)) + ' tok/s')
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

  // 四卡全不显（消息统计查询失败 + 账本/末轮皆无）的兜底行——面板不为白屏
  private allHidden(): boolean {
    return this.msgStats === null && this.sessionTotals() === null && this.lastUsage() === null;
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          if (this.msgStats !== null) {
            this.OverviewCard()
            // 时间卡：无消息行（firstAt 0）不显——0 与未知区分
            if (this.msgStats.firstAt > 0) {
              this.TimeCard()
            }
          }
          if (this.sessionTotals() !== null) {
            this.TokenCard()
          }
          if (this.lastUsage() !== null) {
            this.LastRoundCard()
          }
          if (this.allHidden()) {
            Text('暂无可统计的数据')
              .fontSize(15)
              .fontColor(cardDescColor())
          }
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
    .titleBar(sheetTitleBarOptions('会话统计', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
