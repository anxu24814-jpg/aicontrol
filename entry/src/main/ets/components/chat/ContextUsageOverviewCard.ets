// 上下文用量面板首卡（自 ContextUsageSheet.OverviewCard 域级最小拆出，计算口径零改动）。
// ★ 形制（2026-11-09 决明「进度环改进度条取代分割线，百分比字体放大，优化排版」）：
// 主行 = 左占比大字 **40fp**（未知态 28fp 破折号）+ 右两排（已用/上限、缓存命中率，右对齐
// 且右侧留 8vp 呼吸位，2026-11-09 反馈笔「小数字有点拥挤，略微左移」），信息气泡贴整卡
// 右上、与主行同行且顶部对齐（122 组气泡形制钉逐条不变）；
// 原 64/7 进度环退役——环共用件仍供输入条圆环键使用，本卡不再消费。
// · 进度条 = 官方 ProgressType.Linear，**取代原构成区 Divider** 恒显示于主行与构成区之间，
//   既是分界也是占比可视化；色档经 contextUsageToneColor 与环共用三档单源，窗口未知
//   value 钳 0 仅底槽。环退役后主行不再被 64vp 环径撑高，整卡排版更松。
// · 构成区 = 口径行（单行「本会话累计 · 含每轮重发」）+ 三列（缓存输入 / 未缓存
//   输入 / 输出，千分位数值在上、小圆点 + 标签在下；2026-11-09 反馈笔换上下，与用量 /
//   费用两页首卡「数值在上、标签在下」同形制）。
// ★ 三列是**计费口径绝对数**（账本按会话聚合，含工具轮每轮重发），与上方「已用/上限」的
// 窗口口径不同基——口径行是隔离带：禁把三列与上方两值相加或相比（「不同基禁并列」拍板：
// 11.4k × 99.1% ≠ 21,480、21,480 + 5,320 ≠ 11.4k，都会让人以为面板算错）。
// · 三列圆点色 = Theme.rampColor 主蓝半透明阶梯（复用既有色族，不新增色档）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  cardBg, cardDescColor, cardTitleColor, rampColor,
  CARD_PANEL_WIDTH, CARD_RADIUS
} from '../../common/Theme';
import { formatContextTokens, tokenShort } from '../../common/TokenEstimate';
import { ContextUsage, contextPct } from './ChatContextUsage';
import { contextUsageToneColor } from './ContextUsageRing';
import { InfoHintButton } from '../InfoHintButton';

// 三列槽位数（rampColor 的 count 参数单源——阶梯档数随列数，改列数时此处同步）
const SPLIT_SLOT_COUNT: number = 3;

@Component
export struct ContextUsageOverviewCard {
  // 活算产物（宿主 @Link 直传，页面活算落地自动刷新；null = 首开计算中占位）
  @Link usage: ContextUsage | null;
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

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

  // 占比文案：窗口已知 = 占比；未知 = 破折号（P4 拍板——未知不显占比；禁把已用绝对数塞进
  // 这一块：它的语义是占比，塞绝对数即误读）
  private ringLabel(): string {
    return this.pct() >= 0 ? this.pct() + '%' : '—';
  }

  // 会话级缓存命中率（-1 = 不显行）：无账本或零命中均不显（零噪声口径——无缓存协议常驻
  // 0% 是噪声）；0.1 精度（×1000 取整再 ÷10 避尾差），钳 100。★ 这是比率不吃基数，与窗口
  // 占比并列不构成两笔账（决明澄清：缓存命中与上下文占用不是一个东西）
  private cacheHitPct(): number {
    if (this.usage === null || this.usage.sessionTotals === null ||
      this.usage.sessionTotals.cachedTokens <= 0) {
      return -1;
    }
    return Math.min(100, Math.round(this.usage.sessionTotals.cachedTokens * 1000 /
      this.usage.sessionTotals.promptTokens) / 10);
  }

  // ── 构成三列（计费口径绝对数；promptTokens 全量输入已含命中部分）──
  // 整块显示条件：有账本且输入非零（sessionTotals null ⇒ 整块不渲染，零噪声）
  private hasSessionSplit(): boolean {
    return this.usage !== null && this.usage.sessionTotals !== null &&
      this.usage.sessionTotals.promptTokens > 0;
  }

  private cachedInputTokens(): number {
    return this.usage !== null && this.usage.sessionTotals !== null
      ? this.usage.sessionTotals.cachedTokens : 0;
  }

  // 未缓存输入 = 全量输入 − 缓存命中（负值防御归零——防上游脏数据）
  private uncachedInputTokens(): number {
    if (this.usage === null || this.usage.sessionTotals === null) {
      return 0;
    }
    const rest: number = this.usage.sessionTotals.promptTokens -
      this.usage.sessionTotals.cachedTokens;
    return rest > 0 ? rest : 0;
  }

  private outputTokens(): number {
    return this.usage !== null && this.usage.sessionTotals !== null
      ? this.usage.sessionTotals.completionTokens : 0;
  }

  // 预警文案（≥80% 出现；「为什么 + 怎么办」可读文案，过文案规约）
  private warnText(): string {
    return '上下文接近上限，可在助手设置里限制发送条数，或新建会话。';
  }

  // 口径说明全文（首卡右上角气泡；窗口已知 = 估算口径 + 缓存误解消解，未知 = 引导配置）
  private hintText(): string {
    return this.winTokens() > 0 ?
      '用量为估算，随实际请求校准。缓存只影响计费，不改变窗口占用。' :
      '该模型未配置上下文窗口，可在模型编辑页填写。';
  }

  // 构成列（千分位数值在上 / 小圆点 + 标签在下；圆点色 = rampColor 阶梯第 slot 档）
  @Builder
  SplitColumn(label: string, tokens: number, slot: number) {
    Column({ space: 6 }) {
      Text(formatContextTokens(tokens))
        .fontSize(14)
        // 自适应缩字号（14fp 起缩、9fp 下限，缩到下限仍超宽才省略——长串静默截断会误读）
        .maxFontSize(14)
        .minFontSize(9)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
        .maxLines(1)
        // 长串（百万级累计）缩字号不换行——三列文本同基线，换行会把三列撕成两行
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 })
          .fill(rampColor(this.appColorMode, slot, SPLIT_SLOT_COUNT))
          .flexShrink(0)
        Text(label)
          .fontSize(11)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 14 }) {
      if (this.usage === null) {
        Text('正在统计用量')
          .fontSize(15)
          .fontColor(cardDescColor())
      } else if (!this.usage.hasData) {
        // 无任何可用数据：显「暂无」，禁渲染 0%（0 与未知区分）
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
        // 主行（2026-11-09 改版）：占比大字独占左侧 40fp（未知态破折号降 28fp）+ 右两排
        // 右对齐、右缘留 8vp 呼吸位不贴气泡；环退役后主行高度由 64vp 环径回落到文字高，
        // 整卡更松
        Row() {
          Row({ space: 12 }) {
            Text(this.ringLabel())
              .fontSize(this.pct() >= 0 ? 40 : 28)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .maxLines(1)
            // 右两排 = 已用/上限 + 缓存命中率（右对齐；右缘留 8vp 呼吸位不贴气泡，左缘差
            // 是两排内容长度不同所致，不强求左缘齐）
            Column({ space: 4 }) {
              // 已用/上限 = 单 Text 双 Span 右对齐（18 Bold + 12 次要色）；窄屏超宽省略号收尾
              //——不拆两 Text 各占半宽（会把 '/ 128k' 顶到行尾读不成一组）
              Text() {
                Span(tokenShort(this.usedTokens()))
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(cardTitleColor())
                if (this.pct() >= 0) {
                  // 分母同色系降档（12fp 次要色）——' / 128k' 不抢分子
                  Span(' / ' + tokenShort(this.winTokens()))
                    .fontSize(12)
                    .fontColor(cardDescColor())
                }
              }
              .width('100%')
              .maxLines(1)
              .textAlign(TextAlign.End)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.cacheHitPct() >= 0) {
                // 窄屏（320vp）折两行而不是缩字：12fp 两行比 9fp 一行可读
                Text('缓存命中 ' + this.cacheHitPct().toFixed(1) + '%')
                  .fontSize(12)
                  .fontColor(cardDescColor())
                  .width('100%')
                  .maxLines(2)
                  .textAlign(TextAlign.End)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.End)
            // 右两排吃满剩余宽、右缘留 8vp ⇒ 两排数字与右上角气泡不挤（反馈笔「略微左移」）
            .layoutWeight(1)
            .margin({ right: 8 })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          InfoHintButton({ text: this.hintText() })
        }
        .width('100%')
        // 顶部对齐：气泡贴主行右上角，不与放大后的百分比大字争中线
        .alignItems(VerticalAlign.Top)
        if (this.pct() >= 80) {
          Text(this.warnText())
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_warning'))
        }
        // 进度条取代原构成区分割线（2026-11-09）：官方 Linear 8vp，恒显示、不随有无账本
        // 显隐；色档与输入条环共用 contextUsageToneColor，窗口未知 value 钳 0 仅底槽
        Progress({ value: this.pct() > 0 ? this.pct() : 0, total: 100,
          type: ProgressType.Linear })
          .style({ strokeWidth: 8 })
          .color(contextUsageToneColor(this.pct()))
          .backgroundColor($r('sys.color.comp_divider'))
          .width('100%')
          .height(8)
        // 构成区：口径行 + 三列（口径行是「计费口径 vs 窗口口径」的隔离带，
        // 禁删——删了两组绝对数就成同屏两笔账）
        if (this.hasSessionSplit()) {
          Column({ space: 8 }) {
            // 口径行 = 「计费口径绝对数 vs 上方窗口口径」隔离带：禁删、禁收进右上气泡
            //（气泡点开才见，收走后两式误读会回来）
            Text('本会话累计 · 含每轮重发')
              .fontSize(12)
              .fontColor(cardDescColor())
              .width('100%')
            Row({ space: 8 }) {
              this.SplitColumn('缓存输入', this.cachedInputTokens(), 0)
              this.SplitColumn('未缓存输入', this.uncachedInputTokens(), 1)
              this.SplitColumn('输出', this.outputTokens(), 2)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }
}
