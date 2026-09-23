// 工具调用卡（2026-09-20 审批卡视觉迁移笔 A 第一步域级拆分——自 ChatMessageItem.ets 的
// kind === 'tool' 分支纯搬迁：方法体与标记原样搬，零行为变更、零样式变更）。
// 拆分动因 = 宪法「> 1200 行硬线须先把本次改动所属的功能域拆到独立文件再动手」：本笔要给
// 工具卡加专属头行与回执行，ChatMessageItem 拆分前 1192 行（剔除文件头注释块后约 1178 行），
// 改动必越线；搬迁 = 守「普通工具卡渲染与行为零变化」红线的最强保障（不是重写，是搬家）。
// 职责 = 单条工具调用消息的完整卡面：行头（符号 + 工具名 + 状态位）、分割线、卡体三选一
//（ask_user 交互区 / 高危确认区 / 摘要行与展开详情），点击整卡展开收起。
// 渲染位 = ChatMessageItem.build() 的 tool 分支（一行实例化）。
// ★ 搬迁红线：渲染语句、文案、判据、几何一字未改——只换文件位置与 this 归属（原文件
// tool 分支内的注释一并随迁，保持可追溯）。
import { ConfigurationConstant, common, Want } from '@kit.AbilityKit';
import { BUBBLE_RADIUS, badgeBg, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  BUBBLE_PAD_NEAR } from '../../common/Theme';
import { SearchResultItemPayload, TOOL_ASK_USER, TOOL_BROWSE_ACT, TOOL_SEARCH_WEB,
  TOOL_SCRAPE_WEB, toolTitle } from '../../common/providers/ToolTypes';
import { CONFIRM_LEVEL_IRREVERSIBLE } from '../../common/providers/ToolContracts';
import { ChatMessage } from './ChatMessageCompose';
import { AskQuestion, ChatAskUserCard, parseQuestions } from './ChatAskUserCard';
import { ChatBrowseConfirmCard } from './ChatBrowseConfirmCard';

// 提问卡回执行载荷（msg.toolOutputJson 的 answers[] 逐项；★ 笔 B 补两字段——selectedOptions
// 解析备用（渲染面按组合答案整串上屏、不单独消费）、skipped 决定答案行文案；旧 payload 缺键
// 按缺省降级：空数组与 false）
interface AskAnswerRow {
  id: string;
  question: string;
  answer: string;
  selectedOptions: string[];
  skipped: boolean;
}

// 工具卡折叠态摘要行截断长度：inputText 超过此长度才有展开价值（input/output JSON 存在
// 即可展开）；数值为观感参数，真机可单点调
const TOOL_SUMMARY_MAX_LEN: number = 40;
// 工具卡展开区最大高度（vp）：有界红线——超长 output 不撑爆消息流，区内滚动
const TOOL_DETAIL_MAX_HEIGHT: number = 240;
// 工具卡展开/收起动画时长（ms；2026-09-17 折叠动画笔——官方 FAQ faqs-arkui-769 折叠示例
// 同值 300ms，与思考块 260ms 同族观感；工具卡是条件渲染式折叠（无内容盒解耦），动画只
// 插值高度与箭头旋转）
const TOOL_FOLD_ANIM_MS: number = 300;

@Component
export struct ChatToolCard {
  @ObjectLink msg: ChatMessage;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 工具卡展开态（每消息实例独立，列表项回收即弃）
  @State toolExpanded: boolean = false;
  // 提问卡作答进度（笔 A：ChatAskUserCard 作答变化时上行，头行进度徽章的 n；总数 N 由
  // 本件按 askQuestions().length 现算，不双份存——禁两处各解析一遍的同一口径）
  @State askAnswered: number = 0;
  // ask_user 答案上行（ChatMessageItem 透传 → ChatPage → ToolRuntime.resolveAsk）
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  // browse_act 高危确认上行（ChatMessageItem 透传 → ChatPage → ChatSendCtrl.resolveBrowseConfirm）
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};

  // 工具展示名（函数名 → 中文卡题；未注册函数名原样——自定义/未知工具可读性兜底）
  private toolDisplayName(): string {
    return toolTitle(this.msg.toolName);
  }

  // 工具卡是否有可展开详情（无详情不挂点击——防「可点感」死交互）
  private toolHasDetail(): boolean {
    const inputJson: string = this.msg.toolInputJson ?? '';
    const outputJson: string = this.msg.toolOutputJson ?? '';
    const inputText: string = this.msg.toolInputText ?? '';
    return inputJson !== '' || outputJson !== '' || inputText.length > TOOL_SUMMARY_MAX_LEN ||
      this.toolSearchRefs().length > 0;
  }

  // 搜索类工具结果 → 引文列表（2026-09-03 第三批①；Cube MessageBubble 引文卡裁剪形态
  // ——role='tool' 行 result JSON 的 results[] 解析，坏 JSON/非搜索工具回空数组不渲染；
  // 回放路径 toolOutputJson 同源，历史消息引文卡自动可用）
  private toolSearchRefs(): SearchResultItemPayload[] {
    if (this.msg.toolName !== TOOL_SEARCH_WEB && this.msg.toolName !== TOOL_SCRAPE_WEB) {
      return [];
    }
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (outputJson === '') {
      return [];
    }
    try {
      const parsed = JSON.parse(outputJson) as Record<string, Object>;
      const raw: Object = parsed['results'];
      if (!Array.isArray(raw)) {
        return [];
      }
      const refs: SearchResultItemPayload[] = [];
      const items: object[] = raw as object[];
      for (const item of items) {
        const rec = item as Record<string, Object>;
        refs.push({
          index: typeof rec['index'] === 'number' ? rec['index'] as number : 0,
          id: typeof rec['id'] === 'string' ? rec['id'] as string : '',
          title: typeof rec['title'] === 'string' ? rec['title'] as string : '',
          url: typeof rec['url'] === 'string' ? rec['url'] as string : '',
          snippet: typeof rec['snippet'] === 'string' ? rec['snippet'] as string : ''
        });
      }
      return refs;
    } catch (e) {
      return [];
    }
  }

  // 引文点击 → 系统浏览器打开（want viewData + browsable 实体；失败静默——URL 打开
  // 非关键路径，不打断阅读）
  private openRefUrl(url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
        entities: ['entity.system.browsable']
      };
      (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility(want);
    } catch (e) {
      // 静默（无可处理浏览器的边缘形态）
    }
  }

  // 工具卡是否有卡体（摘要行或内容行任一存在——决定头部分割线显隐）
  // ★ 笔 A 随形：确认说明串判据改用专属头两谓词（confirmAwaiting || confirmDone）——与旧
  // 「toolConfirmText 非空」等价：等待态两式同真；作答后说明串保留 ⇒ 回执态由 confirmDone
  // 接住；中止分支（stale）清空串且不写 result ⇒ 两式同假，与旧式同效
  private toolHasBody(): boolean {
    return this.toolHasDetail() || this.msg.toolProgressPercent !== undefined ||
      this.msg.toolProgressText !== undefined || this.msg.toolTodoId !== undefined ||
      this.msg.toolTaskId !== undefined || this.msg.toolAgentSummary !== undefined ||
      this.confirmAwaiting() || this.confirmDone() || this.msg.text !== '' ||
      (this.msg.toolDisplayText ?? '') !== '';
  }

  // ── 专属卡头判据（笔 A §3.1 两族四态；「确认等待态」全件唯一判据，禁各写一遍）──
  // 确认等待中（2026-09-18 P2·B 起；2026-09-19 确认卡泛化去 browse_act 中间条件；
  // ★ 2026-09-20 笔 A 统一判据）：running ＋ 说明串非空 ＋ 尚未作答（result 未写）——头区
  // 不显「执行中…」（等待主体是人类），确认卡渲染判据同源（与 ask 分支口径一致）。
  // ★ 判据安全性：ask 分支在同链前位先行拦截（toolName === TOOL_ASK_USER 优先命中）；
  // toolConfirmText 全工程仅确认链写入、作答后仍保留（回执行主因句读它）⇒ 非要「running
  // 且无 result」不足以表达等待态；http_request 等后继确认工具自动同形
  private confirmAwaiting(): boolean {
    return this.msg.toolState === 'running' && (this.msg.toolConfirmText ?? '') !== '' &&
      this.msg.toolConfirmResult === undefined;
  }

  // 确认回执（笔 A §3.1）：作答已落位即回执行——判据落在运行时字段（不入库），故只在当场
  // 可见、重进会话退回普通工具卡（信息零丢失，申报口径见任务书 §5.4）
  private confirmDone(): boolean {
    return this.msg.toolConfirmResult !== undefined;
  }

  // 确认档位是否不可逆（卡头符号与档位徽章的判据；undefined = 写操作档兜底——老数据/跳过
  // 预检的历史卡不因缺字段而错显红档）
  private confirmLevelIrreversible(): boolean {
    return this.msg.toolConfirmLevel === CONFIRM_LEVEL_IRREVERSIBLE;
  }

  // 作答是否「已允许」（回执行状态位文案判据）
  private confirmApproved(): boolean {
    return this.msg.toolConfirmResult === 'approved';
  }

  // 本会话内允许（回执行状态位判据；★ 2026-09-20 笔 C——会话级免询问的自动路径不产生回执，
  // 那种调用从未显示确认卡，本谓词只服务「用户按了第三键」这一种作答）
  private confirmSessionApproved(): boolean {
    return this.msg.toolConfirmResult === 'session';
  }

  // 是否提问卡（工具名判据——两种态共用，展开面与专属头分支同源）
  private askCard(): boolean {
    return this.msg.toolName === TOOL_ASK_USER;
  }

  // 提问卡（等待）：running 即等作答（问题列表在场与否交卡体兜底提示）
  private askAwaiting(): boolean {
    return this.askCard() && this.msg.toolState === 'running';
  }

  // 提问卡（回执）：已结束 ＋ 结果能解析出 answers 数组（解析失败 = 回执不成立，退回普通
  // 工具卡——不炸渲染，§5.3）
  private askDone(): boolean {
    return this.askCard() && this.msg.toolState !== 'running' && this.askAnswers().length > 0;
  }

  // 卡头标题·确认卡（2026-09-19 泛化：browse_act 逐字不动；其余 = 网络请求文案；笔 A 起
  // 标题自 ChatBrowseConfirmCard 上移本件——卡体不再重复渲染同一句）
  private confirmTitle(): string {
    return this.msg.toolName === TOOL_BROWSE_ACT ? '助手请求操作网页' : '助手请求发送网络请求';
  }

  // 卡头标题·提问卡（单题 / 多题两态；题数 = 入参 questions 现算，与进度徽章的 N 同源）
  private askTitle(): string {
    return this.askQuestions().length > 1 ? '助手想跟你确认几个问题' : '助手想跟你确认一下';
  }

  // 提问卡题目列表（parseQuestions 单源——ChatAskUserCard 导出，本件算标题与进度 N）
  private askQuestions(): AskQuestion[] {
    return parseQuestions(this.msg.toolInputJson ?? '');
  }

  // 提问卡答案列表（回执行数据源 = 工具结果 JSON 的 answers[]；坏 JSON / 非数组 / 缺键 →
  // 空数组，回执行判据随之不成立）
  private askAnswers(): AskAnswerRow[] {
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (outputJson === '') {
      return [];
    }
    let rows: object[] | undefined = undefined;
    try {
      const parsed = JSON.parse(outputJson) as Record<string, Object>;
      const raw: Object = parsed['answers'];
      if (Array.isArray(raw)) {
        rows = raw as object[];
      }
    } catch (e) {
      return [];
    }
    if (rows === undefined) {
      return [];
    }
    const result: AskAnswerRow[] = [];
    for (const item of rows) {
      const rec = item as Record<string, Object>;
      if (typeof rec['id'] === 'string' && typeof rec['question'] === 'string') {
        const answerRaw: Object = rec['answer'];
        const selectedRaw: Object = rec['selected_options'];
        const selected: string[] = [];
        if (Array.isArray(selectedRaw)) {
          const options: Object[] = selectedRaw as Object[];
          for (const option of options) {
            if (typeof option === 'string') {
              selected.push(option as string);
            }
          }
        }
        result.push({
          id: rec['id'] as string,
          question: rec['question'] as string,
          answer: typeof answerRaw === 'string' ? answerRaw as string : '',
          selectedOptions: selected,
          // 缺省 false 是兼容旧 payload 的判据（旧版无本字段、真值只有 true 一种写法）
          skipped: rec['skipped'] === true
        });
      }
    }
    return result;
  }

  // 进度徽章文案（§3.3）：全答完改「已回答」（投稿前态——用户填齐但未点提交）
  private askProgressText(): string {
    const total: number = this.askQuestions().length;
    return this.askAnswered >= total ? '已回答' : '已答 ' + this.askAnswered + ' / ' + total;
  }

  // 展开可点判据（§3.2：确认卡两态照通用头判据保留可展开；提问卡两态都不提供展开——
  // 其卡体已含全部信息，避免死交互。通用工具卡路径下本判据 == toolHasDetail，行为零变化）
  private headExpandable(): boolean {
    return this.toolHasDetail() && !this.askCard();
  }

  // ── 专属头行（笔 A §3.2/§3.3；几何与通用头同：高 48、padding 左 12 右 12、Row space 8）──
  // 确认卡头（等待与回执两态共用；符号按档位、右槽 = 档位徽章 + 状态位、展开键照通用头判据）
  @Builder
  ConfirmHead() {
    Row({ space: 8 }) {
      if (this.confirmLevelIrreversible()) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(16)
          .fontColor([cardDescColor()])
      } else {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(16)
          .fontColor([cardDescColor()])
      }
      Text(this.confirmTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Row({ space: 6 }) {
        this.ConfirmLevelBadge()
        // 状态位（等待 / 回执三文案；12fp 次要色，不配转圈——转圈语义留给真在跑的执行）
        Text(this.confirmDone() ? (this.confirmSessionApproved() ? '本会话内已允许' :
          (this.confirmApproved() ? '已允许一次' : '已拒绝')) : '等你的确认')
          .fontSize(12)
          .fontColor(cardDescColor())
      }
      if (this.headExpandable()) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([cardDescColor()])
          .rotate({ angle: this.toolExpanded ? 180 : 0 })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
  }

  // 提问卡头（等待与回执两态共用；右槽 = 进度徽章〔仅等待态〕+ 状态位；两态都不提供展开）
  @Builder
  AskHead() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(16)
        .fontColor([cardDescColor()])
      Text(this.askTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Row({ space: 6 }) {
        // 进度徽章只在等待态（回执态由状态位「已回答」承载，§3.3）；题数解析失败（0）不挂
        if (this.askAwaiting() && this.askQuestions().length > 0) {
          this.AskProgressBadge()
        }
        Text(this.askAwaiting() ? '等你回答' : '已回答')
          .fontSize(12)
          .fontColor(cardDescColor())
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
  }

  // 档位徽章（★ 自绘·已拍板两处之一；几何 = 11fp Medium ＋ 内距 10/5 ＋ 圆角 999。
  // 写操作档 = badgeBg 灰底 + 次要色字；不可逆档 = 危险红实底 + 恒白字）
  @Builder
  ConfirmLevelBadge() {
    if (this.confirmLevelIrreversible()) {
      Text('不可撤销')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(999)
        .backgroundColor($r('app.color.dialog_confirm_red'))
    } else {
      Text('写操作')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardDescColor())
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(999)
        .backgroundColor(badgeBg(this.appColorMode))
    }
  }

  // 进度徽章（提问卡等待态；几何同档位徽章，取色零新色——底 badgeBg、字次要色）
  @Builder
  AskProgressBadge() {
    Text(this.askProgressText())
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(cardDescColor())
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(999)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  // 确认回执行体首主因句（§5.2：答题后说明串仍在——体首补一行，摘要行与展开区照旧渲染，
  // 结果内容（HTTP 响应体等）仍需可查；帮助条目已承诺「想核对的完整内容可在工具卡片展开查看」）
  @Builder
  ConfirmReceiptRow() {
    Text(this.msg.toolConfirmText ?? '')
      .fontSize(14)
      .fontColor(cardTitleColor())
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 16, right: 12 })
  }

  // 提问卡回执行卡体（§5.3：逐题 = 题干 14fp 主色 ＋ 答案行 13fp——实答走强调色、跳过与空
  // 答案显「已跳过」次要色；★ 笔 B：上屏的是组合答案（如「方案 A、但要注意 X」），用户点选
  // 了什么与补写了什么同屏可见，无需另渲染 chips；不渲染摘要行与展开区——信息 = 结果 JSON
  // 本身，已由回执完整呈现、零丢失）
  @Builder
  AskReceiptBody() {
    Column({ space: 10 }) {
      ForEach(this.askAnswers(), (row: AskAnswerRow): void => {
        Column({ space: 4 }) {
          Text(row.question)
            .fontSize(14)
            .fontColor(cardTitleColor())
            .width('100%')
          Text(row.skipped || row.answer.trim() === '' ? '已跳过' : row.answer)
            .fontSize(13)
            .fontColor(row.skipped || row.answer.trim() === '' ? cardDescColor() :
              $r('sys.color.ohos_id_color_emphasize'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (row: AskAnswerRow): string => row.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 12, top: 4, bottom: 8 })
  }

  // 摘要行（13fp 次要色单行，@Builder 按值传参只读展示——内容为预组合串无刷新需求）
  @Builder
  ToolSummaryRow(content: string) {
    Row() {
      Text(content)
        .fontSize(12)
        .fontColor(cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 16, right: 12 })
  }

  build() {
    // 完整工具调用卡：卡体对齐组卡规范数值——圆角 16/行高 48/label 16fp Medium/次要文字
    // 12~13fp；左右边距对齐助手气泡（4/4，2026-09-16 随助手气泡统一）；点击展开详情（有详情才可点）
    Column() {
      // 行头三选一（笔 A §3.1）：确认卡 / 提问卡命中即渲染专属头行（替代通用头），
      // 未命中走原通用头行（通用头一字不动）
      if (this.confirmAwaiting() || this.confirmDone()) {
        this.ConfirmHead()
      } else if (this.askAwaiting() || this.askDone()) {
        this.AskHead()
      } else {
        // 行头：符号 + 工具名 + 状态（running 动画 / done·error 图标+语义色）
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(16)
            .fontColor([cardDescColor()])
          Text(this.toolDisplayName())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.msg.toolState === 'running' && this.msg.toolName !== TOOL_ASK_USER &&
            !this.confirmAwaiting()) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(cardDescColor())
            Text('执行中…')
              .fontSize(12)
              .fontColor(cardDescColor())
          } else if (this.msg.toolState === 'error') {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(14)
              .fontColor([$r('sys.color.ohos_id_color_warning')])
            Text('出错')
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
          } else {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(14)
              .fontColor([cardDescColor()])
            Text('完成')
              .fontSize(12)
              .fontColor(cardDescColor())
          }
          if (this.toolHasDetail()) {
            // 展开指示（chevron_down 旋转 180° = 展开；字形表实锤存在）
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([cardDescColor()])
              .rotate({ angle: this.toolExpanded ? 180 : 0 })
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12 })
      }

      if (this.toolHasBody()) {
        // 头部与卡体分割线（1vp cardBorderColor；左 16 对齐卡体内容块）
        Divider()
          .strokeWidth(1)
          .color(cardBorderColor(this.appColorMode))
          .margin({ left: 16, right: 12 })

        // 摘要行区（存在才渲染；13fp 档就近取 12fp 与状态文字同档）
        if (this.msg.toolProgressPercent !== undefined) {
          this.ToolSummaryRow('进度 ' + Math.round(this.msg.toolProgressPercent) + '%')
        } else if (this.msg.toolProgressText !== undefined) {
          this.ToolSummaryRow(this.msg.toolProgressText)
        }
        if (this.msg.toolTodoId !== undefined) {
          this.ToolSummaryRow('todo:' + this.msg.toolTodoId)
        }
        if (this.msg.toolTaskId !== undefined) {
          this.ToolSummaryRow('任务 ' + this.msg.toolTaskId)
        }
        if (this.msg.toolAgentSummary !== undefined) {
          this.ToolSummaryRow('子代理 ' + this.msg.toolAgentSummary)
        }

        // 确认回执行体首主因句（笔 A §5.2）：作答后说明串仍在（写点不再清空），此处补一行；
        // 摘要行与展开区照旧渲染（见下方分支——结果内容仍需可查）。与下方 if 链并列而非
        // 嵌入：展开/收起两种形态下都要出现，且与「非确认卡」分支互斥由 confirmDone 保证
        if (this.confirmDone()) {
          this.ConfirmReceiptRow()
        }

        // ask_user 交互区（2026-09-02；running 态专属——done 后走下方摘要/展开区）：
        // 问题渲染 + 文本作答 + 整卡提交，答案经 onAskSubmit 上行续跑模型
        // ★ 笔 A：判据收成 askAwaiting()（同 askCard && running）；回执走下方 askDone 分支
        if (this.askAwaiting()) {
          ChatAskUserCard({
            msg: this.msg,
            onSubmit: (callId: string, answerJson: string): void => {
              this.onAskSubmit(callId, answerJson);
            },
            // 作答进度上行（笔 A §5.1）：输入与清空都报（answered = 有答案题数），容器渲染进度徽章
            onProgress: (answered: number, total: number): void => {
              this.askAnswered = answered;
            }
          })
        } else if (this.askDone()) {
          // 提问卡回执行（笔 A §5.3）：逐题题干 ＋ 答案行；不渲染摘要行与展开区
          this.AskReceiptBody()
        } else if (this.confirmAwaiting()) {
          // 高危确认区（2026-09-18 P2·B 单元起；2026-09-19 确认卡泛化去 browse_act 中间
          // 条件——running 且带确认说明串才渲染，ask 分支在前位先行拦截；读向动作与已作答
          // 卡不渲染本区，见 ChatBrowseConfirmCard 头注释）：允许一次/拒绝双键，作答经
          // onBrowseConfirm 上行续跑工具轮。★ 笔 A：等待态判据含 result 未写，作答即转回执
          ChatBrowseConfirmCard({
            msg: this.msg,
            onSubmit: (callId: string, approved: boolean): void => {
              this.onBrowseConfirm(callId, approved);
            }
          })
        } else if (!this.toolExpanded) {
          if ((this.msg.toolInputText ?? '') !== '') {
            Text(this.msg.toolInputText ?? '')
              .fontSize(12)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 16, right: 12 })
          }
          if (this.msg.text !== '') {
            Text(this.msg.text)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 16, right: 12 })
          }
          if ((this.msg.toolDisplayText ?? '') !== '') {
            Text(this.msg.toolDisplayText ?? '')
              .fontSize(12)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 16, right: 12 })
          }
        } else {
          Scroll() {
            Column({ space: 6 }) {
              if ((this.msg.toolInputText ?? '') !== '') {
                Text(this.msg.toolInputText ?? '')
                  .fontSize(12)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              if (this.msg.text !== '') {
                Text(this.msg.text)
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_warning'))
                  .width('100%')
              }
              if ((this.msg.toolDisplayText ?? '') !== '') {
                Text(this.msg.toolDisplayText ?? '')
                  .fontSize(12)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              // 引文卡（2026-09-03 第三批①）：搜索类结果编号引文列表——编号圆点 + 标题
              // + 摘要 + URL，点行开浏览器（Cube MessageBubble:2954-3013 裁剪形态）
              if (this.toolSearchRefs().length > 0) {
                Text('来源')
                  .fontSize(11)
                  .fontColor(cardTitleColor())
                  .width('100%')
                ForEach(this.toolSearchRefs(), (ref: SearchResultItemPayload): void => {
                  Column({ space: 2 }) {
                    Row({ space: 6 }) {
                      Text(String(ref.index))
                        .fontSize(11)
                        .fontColor(cardDescColor())
                        .constraintSize({ minWidth: 16 })
                      Text(ref.title !== '' ? ref.title : ref.url)
                        .fontSize(13)
                        .fontColor(cardTitleColor())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')
                    if (ref.snippet !== '') {
                      Text(ref.snippet)
                        .fontSize(11)
                        .fontColor(cardDescColor())
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                    Text(ref.url)
                      .fontSize(10)
                      .fontColor(cardDescColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .onClick((): void => {
                    if (ref.url !== '') {
                      this.openRefUrl(ref.url);
                    }
                  })
                }, (ref: SearchResultItemPayload): string => ref.url + '#' + ref.index)
              }
              if ((this.msg.toolInputJson ?? '') !== '') {
                Text('入参 input')
                  .fontSize(11)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text(this.msg.toolInputJson ?? '')
                  .fontSize(11)
                  .fontColor(cardDescColor())
                  .lineHeight(16)
                  .width('100%')
              }
              if ((this.msg.toolOutputJson ?? '') !== '') {
                Text('输出 output')
                  .fontSize(11)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text(this.msg.toolOutputJson ?? '')
                  .fontSize(11)
                  .fontColor(cardDescColor())
                  .lineHeight(16)
                  .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 12, top: 8, bottom: 8 })
          }
          .scrollBar(BarState.Auto)
          .width('100%')
          .constraintSize({ maxHeight: TOOL_DETAIL_MAX_HEIGHT })
        }
      }
    }
    .width(`calc(100% - ${BUBBLE_PAD_NEAR * 2}vp)`)
    .margin({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(BUBBLE_RADIUS)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 0, bottom: this.toolHasBody() ? 8 : 0 })
    .onClick((): void => {
      // 仅可展开卡响应点击（无详情卡不可点——防死交互）；切换展开态。
      // ★ 2026-09-17 折叠动画笔：切换包进 animateTo（官方 FAQ faqs-arkui-769 折叠示例
      // 做法 + 该示例 300ms 时长；UIContext 形态——宪法禁全局 animateTo）。高度与箭头
      // 旋转随之插值；本卡是条件渲染式折叠，内容不随高度形变（官方 FAQ faqs-arkui-1400
      // 背景知识「布局类改变宽高的动画，内容都是直接到终点状态」）
      // ★ 笔 A：判据自 toolHasDetail 改 headExpandable（= toolHasDetail && 非提问卡）——
      // 提问卡两种态都不提供展开（卡体已含全部信息），非提问卡路径与旧判据逐字同效
      if (this.headExpandable()) {
        this.getUIContext().animateTo({ duration: TOOL_FOLD_ANIM_MS, curve: Curve.EaseInOut },
          (): void => {
            this.toolExpanded = !this.toolExpanded;
          });
      }
    })
  }
}
