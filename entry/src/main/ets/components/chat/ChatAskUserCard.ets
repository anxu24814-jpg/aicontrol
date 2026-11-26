// 向用户提问交互卡（CubeAgent AskUserCard 形态裁剪）：ask_user 工具执行轮由模型发起问题，
// 用户逐题作答（点选项与/或自己写）后整卡提交 → ChatPage.onAskSubmit → ToolRuntime.resolveAsk
// 续跑模型；「跳过」= 一键整轮跳过并立即提交；无任何答案即禁用提交；作答进度经 onProgress
// 上行（容器头行进度徽章的 n）。
// 渲染位 = ChatToolCard 卡体的提问卡分支（toolState='running' 且 toolName=ask_user 时）；
// 提交后卡片随 toolState 转 done 交回容器渲染回执行（见 ChatToolCard.AskReceiptBody）。
// 入参解析自 msg.toolInputJson（ask_user schema：questions[] 上限 5、每题 options 上限 4 与
// selection_type 三值——ToolTypes.ASK_USER_SCHEMA 同源）；坏 JSON/空问题 = 渲染
// 「问题解析失败」占位（不炸渲染链）。
// ★ 单题分页（2026-11-08 两千一百二十八，决明拍板「主行导航＋次级放弃跳过」）：题干区只
// 渲染当前题，分页头行左侧题型小字、右侧 ‹ n/N › 步进器（ChatAskPager，单题零渲染）；页码
// 随 msg.askDraft.currentIndex 持久化，列表回收重建后停在原题。切题整块重建（ForEach 键
// 含页码）——TextInput 的 text 只在新建时取初值，同键复用会把上一题文本留在框里。
// ★ 键区形制（2128 改判）：①主决策行 = 「上一题」（灰底次钮，首题禁用压暗）+「下一题」
//（Tinted 淡彩推进键）或末题「提交」（primary 强调蓝）；②次级区 = 说明小字 + 「放弃」
//「跳过」两枚无底 TEXTUAL 平级键（卡内底部操作行键档，等分高 40）；③实底键统一高 40 +
// `layoutWeight(1)`，**8vp 小圆角仍是两卡专属例外**（登记见 docs/规范-行内按钮与光感.md §1，
// 2128 起本卡收为两枚实底）；④四件套 / Tinted 三件全走 ImmersiveLevel 单源，零手写色值。
// ★ chips 取色走 Theme.selectChipBg / selectChipTextColor / selectChipBorderColor（未选 =
// 淡彩蓝底 + 强调档字色，选中 = 强调蓝实底 + 白字），圆角 14、边框恒 1vp 透明占位；输入框
// 圆角 10、wellBg 井底 + 0.5vp cardBorderColor 细线自行成形（badgeBg 灰底块退役——8% 黑在
// 白卡上几乎不可见），题间距 14 承接分组。自由文本框恒留，不折叠。
// 回传 payload = answers ＋ answered_ids / skipped_ids ＋ 打头 summary（组装见 buildPayload）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardBorderColor, cardDescColor, cardTitleColor, wellBg,
  selectChipBg, selectChipBorderColor, selectChipTextColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  fallbackButtonBgTinted, fallbackButtonFontTinted, fallbackButtonMaterialTinted }
  from '../../common/ImmersiveLevel';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';
import { ChatAskPager, clampAskPage } from './ChatAskPager';
import { ASK_ABANDON_MARK, AskDraftState, ChatMessage } from './ChatMessageCompose';
// 减弱动态效果门控（与过程段/正文/托管面板同源）
import { markdownMotionEnabled } from './ChatMarkdownBody';

// ask_user schema 的题数上限（ToolTypes.ASK_USER_SCHEMA maxItems:5 同源——解析侧截断依据；
// 改 schema 时两处同步）
const ASK_QUESTIONS_MAX: number = 5;
// 选项数上限（ToolTypes.ASK_USER_SCHEMA 的 options.maxItems:4 同源——解析侧截断依据；
// 改 schema 时两处同步）
const ASK_OPTIONS_MAX: number = 4;
// 选项形态（与 schema enum 三值逐字同源）
export const ASK_SELECT_SINGLE: string = 'single';
export const ASK_SELECT_MULTI: string = 'multi';
export const ASK_SELECT_TEXT: string = 'text';
// 切题进场时长（2129）：只驱动 opacity / translate，滚动区高度由 minHeight/maxHeight 约束
const ASK_PAGE_ENTER_ANIM_MS: number = 120;

// 单题渲染载荷（options = 模型给的选项，可能为空）
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
  // 作答进度上行（answered = 有答案的题数，total = 题数）——作答变化时上行，
  // 容器以 @State 承接并渲染进度徽章；默认空实现防漏接
  onProgress: (answered: number, total: number) => void = (answered: number,
    total: number): void => {};
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 正文字体两键 @StorageProp 自订阅（2026-10-20 字体扩展笔）：提问卡题干、选项 chips 与
  // 键区三键均属会话页消息显示面，随正文字体即时变化（文字键 2026-11-04 补接）；作答输入框
  // 保持系统字体（输入态几何稳定，同聊天输入框口径，决明拍板例外）。两能力位 = 四件套入参
  //（CONTENT_FALLBACK_KEY 恒 true、用户面无入口；光感总档固定强档），与全仓消费点同形
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 逐题作答草稿（自由文本，与 questions 一一对应；TextInput onChange 直写）
  @State private drafts: string[] = [];
  // 逐题选中项（chips；★ 改动必须整体替换外层数组——嵌套数组的下标直写在 ArkUI 里不触发
  // 刷新，见 toggleOption）
  @State private selections: string[][] = [];
  // 输入位托管档（2026-11-08）：docked=true 时题干进有界滚动区、键区固定不滚；滚动区
  // maxHeight 由 ChatAskDock 按屏高算好后下发，本件只做 constraintSize（面板高度只有
  // maxHeight 约束，layoutWeight 组合语义不确定）。流内路径 docked 恒 false，逐字不变。
  @Prop docked: boolean = false;
  @Prop dockBodyMax: number = 200;
  // 托管档题干区最小高（2128 分页笔）：单题分页后不同题内容高不同，切题时面板高度会跳——
  // 由 ChatAskDock 按面板预算下发一个下限（min ≤ max），短题留白、长题内部滚动；面板本身
  // 仍由内容驱动、不设死高（坑26 红线）。流内路径不读本值
  @Prop dockBodyMin: number = 0;
  // 当前题下标（单题分页；随 msg.askDraft 持久化——虚拟列表回收重建后停在原题，见
  // AskDraftState.currentIndex 注释）。所有读写草稿/选中都按本下标对真实数组
  @State private currentIndex: number = 0;
  // 切题进场位（2129）：true = 已到位；切题时先落 false 让新页首帧透明、下移 4vp，onAppear
  // 后再 120ms 淡入归位。只动渲染属性，滚动区高度仍由 minHeight/maxHeight 约束（不做高度动画）
  @State private pageIn: boolean = true;
  private questions: AskQuestion[] = [];
  // 上次上报的已答数（-1 = 尚未上报）——只在**题数计数变化**时上行，逐字输入不重复触发
  // 容器重渲（徽章只看计数，行为等价而渲染更省）
  private lastReported: number = -1;

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  aboutToAppear(): void {
    // 草稿恢复/初始化：输入渲染镜像 = 本地 @State；真源 = 源消息
    // 持有的 msg.askDraft（页面寿命——虚拟列表组件被回收重建后按 inputJson 精确比较恢复；
    // 不另起全局/Map 缓存、不为保活禁止 LazyForEach 回收）
    this.restoreFromMessage();
  }

  // 草稿恢复/初始化：先解析题目，再按 msg.askDraft.inputJson 与当前
  // toolInputJson **逐字一致**且数组长度匹配恢复（二维数组逐层 slice 防共享引用）；否则建
  // 全空并保存。解析空题不创建草稿。恢复后 lastReported 复位 -1 + notifyProgress——
  // 父卡已答数（进度徽章）也随之恢复
  private restoreFromMessage(): void {
    const inputJson: string = this.msg.toolInputJson ?? '';
    this.questions = parseQuestions(inputJson);
    const saved: AskDraftState | undefined = this.msg.askDraft;
    if (saved !== undefined && saved.inputJson === inputJson &&
      saved.drafts.length === this.questions.length &&
      saved.selections.length === this.questions.length) {
      this.drafts = saved.drafts.slice();
      const selections: string[][] = [];
      for (const row of saved.selections) {
        selections.push(row.slice());
      }
      this.selections = selections;
      // 页码恢复（2128）：坏值/超出当前题数一律夹取；老草稿无本字段按 0 读
      this.currentIndex = clampAskPage(saved.currentIndex ?? 0, this.questions.length);
    } else {
      const drafts: string[] = [];
      const selections: string[][] = [];
      for (let i = 0; i < this.questions.length; i++) {
        drafts.push('');
        selections.push([]);
      }
      this.drafts = drafts;
      this.selections = selections;
      this.currentIndex = 0;
      if (this.questions.length > 0) {
        this.persistDraft();
      }
    }
    this.lastReported = -1;
    this.notifyProgress();
  }

  // 草稿落镜像（每次交互即写——防组件被回收时丢草稿）：inputJson 为题目版本精确比较值
  private persistDraft(): void {
    const state: AskDraftState = {
      inputJson: this.msg.toolInputJson ?? '',
      drafts: this.drafts.slice(),
      selections: this.selections.map((row: string[]): string[] => row.slice()),
      currentIndex: this.currentIndex
    };
    this.msg.askDraft = state;
  }

  // 题目版本校验（每次交互与 submit 入口先调）：镜像版本与当前入参不一致（含首见无草稿）=
  // 换题了——本次旧题事件不应用到新题，重新解析/清空并刷新进度；一致则零动作（打字不丢）
  private ensureDraftVersion(): void {
    const inputJson: string = this.msg.toolInputJson ?? '';
    const saved: AskDraftState | undefined = this.msg.askDraft;
    if (saved !== undefined && saved.inputJson === inputJson &&
      saved.drafts.length === this.questions.length &&
      saved.selections.length === this.questions.length) {
      return;
    }
    this.restoreFromMessage();
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

  // 单题分页（2128）：当前题切片 —— 交给 ForEach 渲染，键含 currentIndex 使切题重建整块
  //（TextInput 的 text 只在新建时取初值，同键复用会留下上一题文本；坑44/80 家族键纪律）。
  // 越界回空数组（换题缩短时旧渲染帧的安全网）
  private pageQuestions(): AskQuestion[] {
    const q: AskQuestion | undefined = this.questions[this.currentIndex];
    return q !== undefined ? [q] : [];
  }

  // 题型小字（单选 / 多选 / 填空）——照参考图在题干上方给一句，选项形态之外的题也读得懂
  // 「要不要自己写」。判据与 showOptions 同源。
  private typeLabel(q: AskQuestion): string {
    if (!this.showOptions(q)) {
      return '填空';
    }
    return q.selectionType === ASK_SELECT_MULTI ? '多选' : '单选';
  }

  // 切题（右上步进器与底部上一题/下一题共用）：先校验题目版本，再夹取页码；页码变化即落草稿
  // 镜像（回收重建后停原题）。不触发进度上行——作答计数未变。
  private goToPage(delta: number): void {
    this.ensureDraftVersion();
    const next: number = clampAskPage(this.currentIndex + delta, this.questions.length);
    if (next === this.currentIndex) {
      return;
    }
    // 先落进场位再换页：新页首帧取透明/下移，onAppear 动画归位（只做进场，无退场）
    this.pageIn = false;
    this.currentIndex = next;
    this.persistDraft();
  }

  // 切题进场（只正向）：减弱动态效果时直落终点；只改 opacity/translate，不改滚动区高度
  private playPageIn(): void {
    if (this.pageIn) {
      return;
    }
    if (!markdownMotionEnabled()) {
      this.pageIn = true;
      return;
    }
    this.getUIContext().animateTo({ duration: ASK_PAGE_ENTER_ANIM_MS, curve: Curve.EaseOut },
      (): void => {
        this.pageIn = true;
      });
  }

  private isLastPage(): boolean {
    return this.currentIndex >= this.questions.length - 1;
  }

  // 当前题题型小字（越界回空串——坏草稿/换题帧不渲染脏字）
  private currentTypeLabel(): string {
    const q: AskQuestion | undefined = this.questions[this.currentIndex];
    return q !== undefined ? this.typeLabel(q) : '';
  }

  private isSelected(index: number, option: string): boolean {
    return (this.selections[index] ?? []).indexOf(option) >= 0;
  }

  // chip 两态取色已上收 Theme.selectChipBg / selectChipTextColor（原 chipFill / chipTextColor
  // 私有实现退役）；消费侧禁再写 chip 底色 / 字色（口径见文件头）。

  // 选项点选（单选：点未选独占选中，点已选取消；多选：只切换它自己）
  private toggleOption(index: number, option: string): void {
    this.ensureDraftVersion(); // 题目版本校验（换题 = 旧题事件不落到新题）
    // 换题后旧渲染事件越界防御：ensureDraftVersion 重解析可能把题数缩短，旧题 index 直接
    // 丢弃（旧题事件不应用到新题）——不守卫即读越界抛异常、写越界扩脏数组
    if (index < 0 || index >= this.questions.length) {
      return;
    }
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
    this.persistDraft();
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
    // 提交入口先校验题目版本（显示中题版本变化在下次输入/提交前校验）；
    // 不在点提交时提前删草稿（回调 void，尚无成功回执——业务写 toolState 后由数据源清扫）
    this.ensureDraftVersion();
    this.onSubmit(this.msg.toolCallId ?? '', JSON.stringify(this.buildPayload(skipAll)));
  }

  // 题干区（Body）与键区（Keys）拆成两块 @Builder：流内路径两块仍同处一个 Column，
  // 语义与几何逐字不变；托管路径只把 Body 放进有界滚动区，键区恒定固定可见（贴竞品图
  // ——5 题长卡不用滑到底才交卷）。键区整块原样搬迁，档位与取色单源仍在本件，
  // 禁在托管位复制一份。
  @Builder
  Body() {
    if (this.questions.length === 0) {
      Text('问题解析失败，入参异常。可停止后重试')
        .fontSize(13)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
        .width('100%')
      } else {
        Column({ space: 6 }) {
          // 分页头行（2128）：左题型小字、右 ‹ n/N › 切题。两路径同形（流内卡与托管面板
          // 都在 Divider 下方），单题时步进器自持零渲染、只剩题型小字
          Row({ space: 8 }) {
            Text(this.currentTypeLabel())
              .fontSize(11)
              .fontFamily(this.resolveBodyFamily())
              .fontColor(cardDescColor())
              .layoutWeight(1)
            ChatAskPager({
              index: this.currentIndex,
              count: this.questions.length,
              onStep: (delta: number): void => {
                this.goToPage(delta);
              }
            })
          }
          .width('100%')
          // ★ 单题渲染 + 键含页码（坑44/80 家族）：切题必须整块重建——TextInput 的 text
          // 只在新建时取初值，同键复用会把上一题的文本留在框里；页码不进键 = 静默冻结
          ForEach(this.pageQuestions(), (q: AskQuestion): void => {
            Column({ space: 6 }) {
              Text(q.question)
                .fontSize(14)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardTitleColor())
                .width('100%')
              // 小题卡：chips 行（判据命中才渲染）＋ 恒留自由文本框；元素自行成形（chip 淡彩
              // 蓝底、文本框 wellBg 井底 + 细线，判据见规范-列表卡片与组卡 §4.12），原 badgeBg
              // 灰底块退役
              Column({ space: 8 }) {
                // ★ chips 几何 12fp / 内距 10-6 / 圆角 14（Theme 登记 14~18 档）/ 边距 6-6；
                // 取色全走 Theme.selectChip*，零手写色值
                if (this.showOptions(q)) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(q.options, (option: string): void => {
                      Text(option)
                        .fontSize(12)
                        .fontFamily(this.resolveBodyFamily())
                        .fontColor(selectChipTextColor(this.isSelected(this.currentIndex, option),
                          this.appColorMode))
                        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                        .borderRadius(14)
                        .margin({ right: 6, bottom: 6 })
                        .backgroundColor(selectChipBg(this.isSelected(this.currentIndex, option),
                          this.appColorMode))
                        // 1vp 恒宽透明边只作布局占位：选中态靠实底区分，宽度不随选中变化
                        //（原写法选中时 width 归零，切换瞬间整块窄 2vp，换行会重排）
                        .border({ width: 1,
                          color: selectChipBorderColor(this.isSelected(this.currentIndex, option)) })
                        .onClick((): void => {
                          this.toggleOption(this.currentIndex, option);
                        })
                    }, (option: string): string => this.currentIndex + '|' + option +
                      (this.isSelected(this.currentIndex, option) ? '#on' : '#off'))
                    // ★ 键值带页码与选中态：同键节点不重跑子构建，选中色/切题都必须靠键变化
                    // 驱动重建（试验台真机实锤：同键只换状态的写法会留下不换色的胶囊）
                  }
                  .width('100%')
                }
                TextInput({
                  text: this.drafts[this.currentIndex] ?? '',
                  placeholder: this.showOptions(q) ? '也可以自己写…' : '输入你的回答…'
                })
                  .fontSize(14)
                  .height(36)
                  .borderRadius(10)
                  // 兜底成形：白底输入框落白卡会整块消失——井底 + 0.5vp 卡边细线（判据 = 卡内
                  // 大面积容器，见 Theme wellBg 注释与规范-列表卡片与组卡 §4.12）
                  .backgroundColor(wellBg(this.appColorMode))
                  .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })
                  .width('100%')
                  .onChange((value: string): void => {
                    this.ensureDraftVersion(); // 题目版本校验（换题 = 旧题输入不落到新题）
                    const index: number = this.currentIndex;
                    // 越界防御（同 toggleOption）：越界输入整体丢弃（不扩脏 drafts 数组，防
                    // 后续版本校验被污染长度反复重置）
                    if (index < 0 || index >= this.questions.length) {
                      return;
                    }
                    // 整体替换（新数组）后落镜像——本地 @State 渲染 + msg.askDraft 持草稿
                    const next: string[] = this.drafts.slice();
                    next[index] = value;
                    this.drafts = next;
                    this.persistDraft();
                    this.notifyProgress();
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            // 切题进场：新页首帧透明 + 下移 4vp，onAppear 后 120ms 归位（纯渲染属性）
            .opacity(this.pageIn ? 1 : 0)
            .translate({ y: this.pageIn ? 0 : 4 })
            .onAppear((): void => {
              this.playPageIn();
            })
          }, (q: AskQuestion): string => q.id + '|' + this.currentIndex)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  Keys() {
        // 键区分层（2128 分页笔，决明拍板「主行导航＋次级放弃跳过」）：
        // ①主决策行 = 翻页导航与收口——上一题（灰底次钮，首题禁用）+ 下一题（淡彩推进键）
        //   或末题提交（主操作键）。翻页是推进型非收口，故非末题右键走 Tinted 档，末题才
        //   换成 primary 强调蓝；「提交」只在末题出现（分页表单惯例，参考图同形）。
        // ②次级区 = 说明小字在键行上方，放弃/跳过两枚走「卡内底部操作行键」档（无底
        //   TEXTUAL + 等分 + 高 40 + 次要色）——整轮放弃与整轮跳过是平级出口，不占实底档。
        // 实底操作键由三枚收为两枚（8vp 小圆角例外随形改判，规范 §1 登记；禁扩散）。
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Button('上一题')
              .layoutWeight(1)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.resolveBodyFamily())
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              // 首题禁用：官方 enabled 只断交互不改色，须显式压暗（规范 §1 轻动作/禁用条）
              .enabled(this.currentIndex > 0)
              .opacity(this.currentIndex > 0 ? 1.0 : 0.4)
              .onClick((): void => {
                this.goToPage(-1);
              })
            if (this.isLastPage()) {
              Button('提交')
                .layoutWeight(1)
                .height(40)
                .borderRadius(8)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(fallbackButtonFont(this.contentFallback, true))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                // 禁用态须显式压暗：官方 enabled 只断交互不改色（官方《禁用控制》示例与 Button
                // 示例均另加 opacity(0.4)；先例 = ChatInputBar 发送键）。2111 把本键由无底文字键
                // 改实底主钮后，不加压暗会变成「看着可点却点不动」的强化蓝主钮（2112 自检轮修）
                .enabled(this.answeredCount() > 0)
                .opacity(this.answeredCount() > 0 ? 1.0 : 0.4)
                .onClick((): void => {
                  this.submit(false);
                })
            } else {
              Button('下一题')
                .layoutWeight(1)
                .height(40)
                .borderRadius(8)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(fallbackButtonFontTinted(this.contentFallback))
                .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
                .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .onClick((): void => {
                  this.goToPage(1);
                })
            }
          }
          .width('100%')
          Column({ space: 8 }) {
            Text('跳过会把所有问题留空提交。')
              .fontSize(12)
              .fontFamily(this.resolveBodyFamily())
              .fontColor(cardDescColor())
              .width('100%')
            Row({ space: 12 }) {
              Button('放弃')
                .layoutWeight(1)
                .height(40)
                .fontFamily(this.resolveBodyFamily())
                .fontColor($r('sys.color.font_secondary'))
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  // 放弃 = 经统一答案上行通道提交放弃标记（ASK_ABANDON_MARK 单源在
                  // ChatMessageCompose；续答件按标记分流——同进程停止链 / 跨进程库侧收口）
                  this.onSubmit(this.msg.toolCallId ?? '', ASK_ABANDON_MARK);
                })
              Button('跳过')
                .layoutWeight(1)
                .height(40)
                .fontFamily(this.resolveBodyFamily())
                .fontColor($r('sys.color.font_secondary'))
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  this.submit(true);
                })
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
  }

  build() {
    // 题间距 14（原灰底块包裹撤除后由间距承担分组；10 会让题干与上一题输入框糊成一片）
    Column({ space: 14 }) {
      if (this.docked) {
        Scroll() {
          Column({ space: 14 }) {
            this.Body()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .width('100%')
        // 单题分页的卡高稳定（2128）：只给下限不给死高——不同题内容高不同，切题时面板
        // 高度不再随题跳；短题留白、长题内部滚动，面板本身仍内容驱动（坑26 红线）
        .constraintSize({ minHeight: Math.min(this.dockBodyMin, this.dockBodyMax),
          maxHeight: this.dockBodyMax })
      } else {
        this.Body()
      }
      // 解析失败无题可答时不挂键区（与流内原语义一致）
      if (this.questions.length > 0) {
        this.Keys()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // ★ 对齐笔（决明「问题卡太窄，改为与正文对齐」）：左右自持内距 16/12 退役——与内容列
    //（标题/思考/回执同左沿）对齐，作答前后宽度零跳变；确认卡 ChatBrowseConfirmCard 同款
    //（同缺陷族）
    .padding({ top: 4, bottom: 8 })
  }
}

// 入参 questions 解析（坏形/缺 id/question 的题项跳过；非法 = 空数组由 UI 兜底提示）。
// ★ 按 schema maxItems 截前 ASK_QUESTIONS_MAX 题（超限题模型越权多给，卡上不渲染也提交
// 不出去）；**导出**（容器算卡头「单题/多题」与进度 N 要用，禁两处各解析一遍）。逐题收
// options（非数组 → []；逐项只收 string 并截前 ASK_OPTIONS_MAX）与 selection_type
//（'single' / 'multi' 原样，其余一切 → 'text'；坏形一律降级不炸）
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

// 选项解析（非数组 → 空数组；逐项只收 string 并截前 ASK_OPTIONS_MAX——照题数截断的既有纪律）
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
