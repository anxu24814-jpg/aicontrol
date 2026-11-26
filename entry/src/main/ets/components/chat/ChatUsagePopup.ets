// 消息用量气泡（自 ChatMessageItem 整域迁出——该件越 1200 硬线，按宪法先把本次功能域
//〔缓存命中率行〕拆出再动手，方法体与判据原样搬迁零行为变化）：
// 职责单句：渲染消息底栏用量键弹出的「Token 用量」列（标题 + 分割线 + 标签左·数值右若干行，
// 含缓存命中率派生行）。拆在职责缝上：用量气泡是消息底栏的独立展示件，与气泡正文/过程段/
// 菜单无耦合（单消费方 = ChatMessageItem 的 bindPopup）。依赖方向：只读 ChatMessage
//（同域）与 Theme / TokenEstimate 叶子件；零业务、零上行回调——宿主控制弹层开合与锚点，
// 本件只出内容。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardBorderColor, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE } from '../../common/Theme';
import { tokenShort } from '../../common/TokenEstimate';
import { ChatMessage } from './ChatMessageCompose';

@Component
export struct ChatUsagePopup {
  // 单轮用量源（@ObjectLink 对象级观察：弹出时字段已收口，本件只读；与宿主同对象引用）
  @ObjectLink msg: ChatMessage;
  // 深浅色（分割线取色；宿主同款存储键自订阅——弹层重开即现读）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // ── 用量气泡数据。计算口径拍板：输入 = 当轮请求计费输入〔prompt 含全部历史上下文，连续
  // 对话中后轮大于前轮是正常计费口径〕；输出 = 本条回复自身 token；总计 = 输入 + 输出〔= 协议
  // total 原值〕；缓存 = 输入里的命中部分〔真子集，故列在输入之后，总计不重复计它〕；token
  // 数 ≥1000 缩 k 一位小数〔tokenShort 单点〕；tok/s = 输出 token ÷ 纯流式秒〔口径③〕；
  // 用时 <60s 一位小数否则整数秒。术语与设置页「用量统计」同名同义（速度与用时是统计页
  // 没有的维度，措辞写全不裸缩写）；首字耗时行 >0 才挂（老账本行/无产出轮无），常开测量
  // 不随请求日志开关——两枚指标的分野见 ChatUsageRoundCtrl 域头注释 ──
  private usagePromptCount(): number {
    const total: number = this.msg.usageTokens ?? 0;
    const completion: number = this.msg.usageCompletionTokens ?? 0;
    // 输入 = 整轮总量 − 输出；负值防御归零（仅防脏数据）
    return total - completion > 0 ? total - completion : 0;
  }

  // 用时数值串（标签在行首，本函数只出数值与单位）
  private usageDurationValue(): string {
    const seconds: number = (this.msg.usageDurationMs ?? 0) / 1000;
    return seconds < 60 ? (Math.round(seconds * 10) / 10) + 's' : Math.round(seconds) + 's';
  }

  // 生成速度数值串（tok/s；单位跟数字不裸缩写——任务书 §2.7-1）
  private usageSpeedValue(): string {
    const completion: number = this.msg.usageCompletionTokens ?? 0;
    const durationMs: number = this.msg.usageDurationMs ?? 0;
    return Math.round(completion / (durationMs / 1000)) + ' tok/s';
  }

  // 首字耗时数值串：口径 = 本轮首个正文或思考增量到达的墙钟耗时（跨流取首个非 0；常开
  // 测量、不随请求日志开关——与请求日志那枚「首字节」是两个指标，详见 ChatUsageRoundCtrl）。
  // 分档与「用时」同规则（<60 秒一位小数，否则整数秒）
  private usageFirstTokenValue(): string {
    const seconds: number = (this.msg.usageFirstTokenMs ?? 0) / 1000;
    return seconds < 60 ? (Math.round(seconds * 10) / 10) + 's' : Math.round(seconds) + 's';
  }

  // 缓存命中率数值串：命中读 token ÷ 本轮输入 token——输入口径与「输入」行同源
  //（usagePromptCount = 总计 − 输出），与协议「prompt 已含命中部分」的定义一致。命中 ≤0
  // 或输入 ≤0 回 ''（不显行——零命中常驻 0% 是噪声，且防除零/脏数据）；精度 0.1（先 ×1000
  // 取整再 ÷10，避免二进制浮点出现 99.899999 尾巴），钳 100 防上游越界，**与
  // ContextUsageSheet.cacheHitPct 同一算法同一精度**（气泡与面板同一指标禁两种精度）
  private usageCacheHitValue(): string {
    const cached: number = this.msg.usageCachedTokens ?? 0;
    const prompt: number = this.usagePromptCount();
    if (cached <= 0 || prompt <= 0) {
      return '';
    }
    const pct: number = Math.min(100, Math.round(cached * 1000 / prompt) / 10);
    return pct.toFixed(1) + '%';
  }

  // ── 官方服务端工具计次三行（二期 #7）：只列非零项（零噪声口径与缓存行同源）、只给次数
  // 不折算金额（官方只给次数，项目费用体系是 token×单价，无按次计价位置）。'' = 不渲染。
  // 口径：tool_search 官方注明「计费的搜索次数，不含图片搜索」，故搜索与图搜两行不重叠
  private searchCountText(): string {
    const n: number = this.msg.serverToolUse !== undefined ? this.msg.serverToolUse.search : 0;
    return n > 0 ? n + ' 次' : '';
  }

  private fetchCountText(): string {
    const n: number = this.msg.serverToolUse !== undefined ? this.msg.serverToolUse.fetch : 0;
    return n > 0 ? n + ' 页' : '';
  }

  private imageCountText(): string {
    const n: number = this.msg.serverToolUse !== undefined ? this.msg.serverToolUse.image : 0;
    return n > 0 ? n + ' 张' : '';
  }

  // 用量行（标签左·数值右对齐——2026-09-15 决明「同图竖向排列」；标签次要色、数值
  // 主色加粗，两处色位对位即行形态判据）。@Builder 按值传参只读展示（内容为预组合串、
  // 弹窗内容重开即重算，无刷新需求——照 ToolSummaryRow 先例）
  @Builder
  UsageRow(label: string, value: string) {
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

  // 用量键气泡内容（bindPopup builder——首层容器禁 position；内距 12，横宽 220——收窄因
  // 用量数字不长，多一行最长「缓存命中率 + 100%」标签对后略增宽，「生成速度 + 9999 tok/s」
  // 仍留足余量）。组件内直读 this.msg 规避坑57 按值传参；字段在流末收口后不变，弹出时现读
  // 即可无需订阅。
  // ★ 决明改版定稿（照其供图形态）：①标题 = 纯文字「Token 用量」（**气泡内不显示任何符号**
  //——AI 徽标与模型名都不取，用量符号只落在底栏用量键上）；②标题下分割线 + 竖排（基础
  // 六行 + 命中率条件行 = 最多七行）；③速度行殿后且恒主色无强调蓝（决明「速度不用蓝体」
  //「速度放最后」）；④缓存行命中 >0 才列，其下再挂「缓存命中率」行（输入缺失或零命中
  // 整行不挂）；⑤用时与速度同行门 = 时长在场（时长缺省的协议两行同缺）；⑥底部口径声明
  // 已撤（决明「底部提示删除」——标题行语义自明）──
  @Builder
  UsagePopup() {
    Column({ space: 10 }) {
      // 标题行（14fp 常规字重官方强调蓝——2026-11-01 决明拍板随板块标题改档；纯文字无符号——见上注①）
      Text('Token 用量')
        .fontSize(SECTION_TITLE_FONTSIZE)
        .fontColor($r('sys.color.ohos_id_color_emphasize'))
        .width('100%')
      // 标题与用量行的分组分割线（照工具卡分割线形制）
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      Column({ space: 8 }) {
        this.UsageRow('输入', tokenShort(this.usagePromptCount()))
        if ((this.msg.usageCachedTokens ?? 0) > 0) {
          this.UsageRow('缓存', tokenShort(this.msg.usageCachedTokens ?? 0))
            // 缓存命中率：紧随缓存行——命中是输入的真子集，比率就地说明「这一轮输入省了多少」；
          // 空串 = 命中或输入缺失，整行不挂（零噪声口径与缓存行 >0 门同源）
          if (this.usageCacheHitValue() !== '') {
            this.UsageRow('缓存命中率', this.usageCacheHitValue())
          }
        }
        this.UsageRow('输出', tokenShort(this.msg.usageCompletionTokens ?? 0))
        this.UsageRow('总计', tokenShort(this.msg.usageTokens ?? 0))
        if ((this.msg.usageDurationMs ?? 0) > 0) {
            // 首字耗时殿于用时之前：时间三行按发生序排——首字 → 用时 → 生成速度。＞0 才显
          //（升级前老账本行与无产出轮次无此行）；口径见 usageFirstTokenValue 注释
          if ((this.msg.usageFirstTokenMs ?? 0) > 0) {
            this.UsageRow('首字耗时', this.usageFirstTokenValue());
          }
          this.UsageRow('用时', this.usageDurationValue());
          this.UsageRow('生成速度', this.usageSpeedValue());
        }
        // 官方工具计次（二期 #7）：非零才列；三项全零整组不挂（serverToolUse undefined）
        if (this.searchCountText() !== '') {
          this.UsageRow('搜索次数', this.searchCountText());
        }
        if (this.fetchCountText() !== '') {
          this.UsageRow('抓取页数', this.fetchCountText());
        }
        if (this.imageCountText() !== '') {
          this.UsageRow('图搜张数', this.imageCountText());
        }
      }
      .width('100%')
    }
    .width(220)
    .padding(12)
    .alignItems(HorizontalAlign.Start)
  }

  // 组件体 = 气泡内容本身（保留 UsagePopup builder 形态：弹层宿主的 bindPopup 直接挂本组件，
  // 内容判断据与行序断言面按 builder 切片不随拆域漂移）
  build() {
    this.UsagePopup();
  }
}
