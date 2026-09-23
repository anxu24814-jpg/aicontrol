// 向用户提问交互卡（2026-09-02 工具调用底层一期；CubeAgent AskUserCard 形态裁剪）：
// ask_user 工具执行轮由模型发起问题，用户逐题作答（点选项与/或自己写）后整卡提交 →
// ChatPage.onAskSubmit → ToolRuntime.resolveAsk 续跑模型；「跳过」= 一键整轮跳过并立即提交。
// 渲染位 = ChatToolCard 卡体的提问卡分支（toolState='running' 且 toolName=ask_user 时）；
// 提交后卡片随 toolState 转 done 交回容器渲染回执行（见 ChatToolCard.AskReceiptBody）。
// 入参解析自 msg.toolInputJson（ask_user schema：questions[] 上限 5、每题 options 上限 4 与
// selection_type 三值——ToolTypes.ASK_USER_SCHEMA 同源）；坏 JSON/空问题 = 渲染
// 「问题解析失败」占位（不炸渲染链）。
// ★ 2026-09-20 审批卡视觉迁移笔 A：键行改右对齐单枚「提交」键（主键 primary 态走
// fallbackButton* 四件套第三参，内容区双态、光感适配）+ 无任何答案即禁用 + 作答进度经
// onProgress 上行（容器头行进度徽章的 n）。
// ★ 2026-09-20 笔 B（审批卡协议扩展）：题干下新增小题卡底色块（chips 行 + 恒留自由文本框）；
// 跳过键落键行左位副档（终态动作非开关）；进度判据含 chips 选中；回传 payload 扩
// selected_options / custom_answer / answer 组合串 / skipped / answered_ids / skipped_ids /
// summary（组装见 buildPayload）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { badgeBg, cardBorderColor, cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { ChatMessage } from './ChatMessageCompose';

// ask_user schema 的题数上限（ToolTypes.ASK_USER_SCHEMA maxItems:5 同源——解析侧截断依据；
// 改 schema 时两处同步。★ 2026-09-22 八百七十三节 3 → 5）
const ASK_QUESTIONS_MAX: number = 5;
// 选项数上限（ToolTypes.ASK_USER_SCHEMA 的 options.maxItems:4 同源——解析侧截断依据；
// 改 schema 时两处同步）
const ASK_OPTIONS_MAX: number = 4;
// 选项形态（与 schema enum 三值逐字同源）
export const ASK_SELECT_SINGLE: string = 'single';
export const ASK_SELECT_MULTI: string = 'multi';
export const ASK_SELECT_TEXT: string = 'text';

// 单题渲染载荷（笔 B 补两字段：options = 模型给的选项（可能为空）；selectionType = 'single' | 'multi' | 'text'）
export interface AskQuestion {
  id: string;
  question: string;
  options: string[];
  selectionType: string;
}

// 单题答案载荷（提交 JSON 逐项；JSON 键名直接作字段名——协议侧读法，免二次映射）
interface AskAnswerItem {
  id: string;
  question: string;
  selection_type: string;
  selected_options: string[];
  custom_answer: string;
  answer: string;
  skipped: boolean;
}

// 提交载荷（答案数组 ＋ 实答/跳过两组 id ＋ 打头人话 summary——细节字段殿后，模型读法稳）
interface AskPayload {
  answers: AskAnswerItem[];
  answered_ids: string[];
  skipped_ids: string[];
  summary: string;
}

@Component
export struct ChatAskUserCard {
  @ObjectLink msg: ChatMessage;
  // 提交上行（ChatToolCard 透传 ChatPage → ToolRuntime.resolveAsk）
  onSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  // 作答进度上行（笔 A §5.1；answered = 有答案的题数，total = 题数）——作答变化时上行，
  // 容器以 @State 承接并渲染进度徽章；默认空实现防漏接
  onProgress: (answered: number, total: number) => void = (answered: number,
    total: number): void => {};
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 逐题作答草稿（自由文本，与 questions 一一对应；TextInput onChange 直写）
  @State private drafts: string[] = [];
  // 逐题选中项（chips；★ 改动必须整体替换外层数组——嵌套数组的下标直写在 ArkUI 里不触发
  // 刷新，见 toggleOption）
  @State private selections: string[][] = [];
  private questions: AskQuestion[] = [];
  // 上次上报的已答数（-1 = 尚未上报）——只在**题数计数变化**时上行，逐字输入不重复触发
  // 容器重渲（徽章只看计数，行为等价而渲染更省）
  private lastReported: number = -1;

  aboutToAppear(): void {
    this.questions = parseQuestions(this.msg.toolInputJson ?? '');
    const drafts: string[] = [];
    const selections: string[][] = [];
    for (let i = 0; i < this.questions.length; i++) {
      drafts.push('');
      selections.push([]);
    }
    this.drafts = drafts;
    this.selections = selections;
  }

  // 某题是否已作答（chips 有选中 或 自由文本非空——提交键可用态与进度徽章 n 同源，
  // 容器与子件禁各写一遍）
  private isAnswered(index: number): boolean {
    const picked: string[] = this.selections[index] ?? [];
    return picked.length > 0 || (this.drafts[index] ?? '').trim() !== '';
  }

  // 已作答题数
  private answeredCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.questions.length; i++) {
      if (this.isAnswered(i)) {
        n++;
      }
    }
    return n;
  }

  // 作答变化统一入口（全件两个调用点：chips 点选与取消走 toggleOption、自由文本输入与清空
  // 走 TextInput.onChange）：计数变了才上行进度（见 lastReported 注释）
  private notifyProgress(): void {
    const answered: number = this.answeredCount();
    if (answered === this.lastReported) {
      return;
    }
    this.lastReported = answered;
    this.onProgress(answered, this.questions.length);
  }

  // chips 渲染判据（唯一，chips 行与 placeholder 两处共用）：给了形态但没给选项也回纯文本
  // ——不渲染空 chips 行（题干下一条空底色带 = 观感事故）
  private showOptions(q: AskQuestion): boolean {
    return q.selectionType !== ASK_SELECT_TEXT && q.options.length > 0;
  }

  private isSelected(index: number, option: string): boolean {
    return (this.selections[index] ?? []).indexOf(option) >= 0;
  }

  // 胶囊两态取色（选中 = 官方强调蓝实底恒白字、零手写色值；未选 = 灰底主色字 + 1vp 边）
  private chipFill(index: number, option: string): ResourceColor {
    return this.isSelected(index, option) ? $r('sys.color.ohos_id_color_emphasize') :
      badgeBg(this.appColorMode);
  }

  private chipTextColor(index: number, option: string): ResourceColor {
    return this.isSelected(index, option) ? Color.White : cardTitleColor();
  }

  // 选项点选（单选：点未选独占选中，点已选取消；多选：只切换它自己）
  private toggleOption(index: number, option: string): void {
    const current: string[] = this.selections[index] ?? [];
    let picked: string[] = [];
    if (this.questions[index].selectionType === ASK_SELECT_MULTI) {
      let found: boolean = false;
      for (const item of current) {
        if (item === option) {
          found = true;
        } else {
          picked.push(item);
        }
      }
      if (!found) {
        picked.push(option);
      }
    } else {
      picked = (current.length === 1 && current[0] === option) ? [] : [option];
    }
    // 外层数组整替换（禁下标直写——嵌套数组的下标写在 ArkUI 里不触发刷新）
    const next: string[][] = this.selections.slice();
    next[index] = picked;
    this.selections = next;
    this.notifyProgress();
  }

  // 提交载荷组装（skipAll = 整轮跳过：全题按空答案走，等价于全部留空后点提交）
  private buildPayload(skipAll: boolean): AskPayload {
    const answers: AskAnswerItem[] = [];
    const answeredIds: string[] = [];
    const skippedIds: string[] = [];
    for (let i = 0; i < this.questions.length; i++) {
      const q: AskQuestion = this.questions[i];
      const selected: string[] = skipAll ? [] : (this.selections[i] ?? []);
      const custom: string = skipAll ? '' : (this.drafts[i] ?? '').trim();
      // 组合答案 = 选中项与自由文本以「、」相接，两者都不丢——模型只读 answer 即拿全用户意思，
      // 卡面回执也读本字段（丢了自由文本回执即失真）
      const parts: string[] = [];
      for (const item of selected) {
        if (item !== '') {
          parts.push(item);
        }
      }
      if (custom !== '') {
        parts.push(custom);
      }
      const answer: string = parts.join('、');
      const skipped: boolean = answer === '';
      if (skipped) {
        skippedIds.push(q.id);
      } else {
        answeredIds.push(q.id);
      }
      answers.push({ id: q.id, question: q.question, selection_type: q.selectionType,
        selected_options: selected, custom_answer: custom, answer: answer, skipped: skipped });
    }
    // summary 句式恒定（跳过 0 个照写，模型读法稳）；全跳过另起一句
    const summary: string = answeredIds.length > 0
      ? '用户回答了 ' + answeredIds.length + ' 个问题，跳过 ' + skippedIds.length + ' 个问题'
      : '用户跳过了本次询问';
    return { answers: answers, answered_ids: answeredIds, skipped_ids: skippedIds, summary: summary };
  }

  private submit(skipAll: boolean): void {
    if (this.questions.length === 0) {
      return;
    }
    this.onSubmit(this.msg.toolCallId ?? '', JSON.stringify(this.buildPayload(skipAll)));
  }

  build() {
    Column({ space: 10 }) {
      if (this.questions.length === 0) {
        Text('问题解析失败，入参异常。可停止后重试')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      } else {
        ForEach(this.questions, (q: AskQuestion, index: number) => {
          Column({ space: 6 }) {
            Text(q.question)
              .fontSize(14)
              .fontColor(cardTitleColor())
              .width('100%')
            // 小题卡（笔 B 新增）：chips 行（判据命中才渲染）＋ 恒留自由文本框；底色 = A 案灰底
            // badgeBg（零新色；B 案强调蓝淡底已否决）——★ 自绘·本笔申报两处之一（另一处 =
            // 下方 chips 几何），理由与边界见 docs/变更记录.md 八百零九节「自绘例外申报」条
            Column({ space: 8 }) {
              // ★ 自绘·本笔申报两处之二：chips 几何 12fp / 内距 10-6 / 圆角 12 / 边距 6-6 与
              // ModelCapsCard（13fp·12-6·14）有意不同——chips 是卡内二级元素，字号降一档、几何
              // 收一圈；取色全走官方资源（选中强调蓝 + 未选 badgeBg），零手写色值
              if (this.showOptions(q)) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(q.options, (option: string): void => {
                    Text(option)
                      .fontSize(12)
                      .fontColor(this.chipTextColor(index, option))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .backgroundColor(this.chipFill(index, option))
                      .border({
                        width: this.isSelected(index, option) ? 0 : 1,
                        color: cardBorderColor(this.appColorMode)
                      })
                      .onClick((): void => {
                        this.toggleOption(index, option);
                      })
                  }, (option: string): string => option + (this.isSelected(index, option) ? '#on' : '#off'))
                  // ★ 键值带选中态：同键节点不重跑子构建，选中色变化必须靠键变化驱动重建
                  //（试验台真机实锤：同键只换状态的写法会留下不换色的胶囊）
                }
                .width('100%')
              }
              TextInput({
                text: this.drafts[index] ?? '',
                placeholder: this.showOptions(q) ? '也可以自己写…' : '输入你的回答…'
              })
                .fontSize(14)
                .height(36)
                .borderRadius(8)
                .width('100%')
                .onChange((value: string): void => {
                  this.drafts[index] = value;
                  this.notifyProgress();
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor(badgeBg(this.appColorMode))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (q: AskQuestion): string => q.id)
        // 键行：右对齐、两枚自然宽度键（不给 layoutWeight）。跳过 = 左位副档（四件套第三参
        // false）＋ 一键整轮跳过并立即提交（终态动作，非开关——按下即提交，无需再点提交）；
        // 提交 = 右位主档，全部题目皆无答案才禁（任一题有选中或有文本即可提交）
        Row({ space: 10 }) {
          Button('跳过')
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick((): void => {
              this.submit(true);
            })
          Button('提交')
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .enabled(this.answeredCount() > 0)
            .onClick((): void => {
              this.submit(false);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 12, top: 4, bottom: 8 })
  }
}

// 入参 questions 解析（坏形/缺 id/question 的题项跳过；非法 = 空数组由 UI 兜底提示）。
// ★ 笔 A：①按 schema maxItems 截前 ASK_QUESTIONS_MAX 题（旧观察项 O-1 收编——超限题模型
// 越权多给，卡上不渲染也提交不出去）；②**导出**（容器算卡头「单题/多题」与进度 N 要用，
// 禁两处各解析一遍）
// ★ 笔 B：逐题收两新字段——options（非数组 → []；逐项只收 string 并截前 ASK_OPTIONS_MAX）与
// selection_type（'single' / 'multi' 原样，其余一切含缺字段、非法值、空串 → 'text'；
// 坏形一律降级不炸）
export function parseQuestions(inputJson: string): AskQuestion[] {
  if (inputJson === '') {
    return [];
  }
  let questions: object[] | undefined = undefined;
  try {
    const parsed: object = JSON.parse(inputJson) as object;
    const rec = parsed as Record<string, Object>;
    const raw: Object | undefined = rec['questions'];
    if (Array.isArray(raw)) {
      questions = raw as object[];
    }
  } catch (e) {
    return [];
  }
  const result: AskQuestion[] = [];
  if (questions === undefined) {
    return result;
  }
  for (const item of questions) {
    if (result.length >= ASK_QUESTIONS_MAX) {
      break;
    }
    const rec = item as Record<string, Object>;
    if (typeof rec['id'] === 'string' && typeof rec['question'] === 'string') {
      result.push({
        id: rec['id'] as string,
        question: rec['question'] as string,
        options: parseOptions(rec['options']),
        selectionType: parseSelectionType(rec['selection_type'])
      });
    }
  }
  return result;
}

// 选项解析（非数组 → 空数组；逐项只收 string 并截前 ASK_OPTIONS_MAX——照题数截断的既有纪律，
// 收编越权多给）
function parseOptions(raw: Object | undefined): string[] {
  const options: string[] = [];
  if (!Array.isArray(raw)) {
    return options;
  }
  const items: Object[] = raw as Object[];
  for (const item of items) {
    if (options.length >= ASK_OPTIONS_MAX) {
      break;
    }
    if (typeof item === 'string') {
      options.push(item as string);
    }
  }
  return options;
}

// 选项形态解析：'single' / 'multi' 原样，其余一切（缺字段 / 非法值 / 空串）→ 'text'
function parseSelectionType(raw: Object | undefined): string {
  if (raw === ASK_SELECT_SINGLE || raw === ASK_SELECT_MULTI) {
    return raw as string;
  }
  return ASK_SELECT_TEXT;
}
