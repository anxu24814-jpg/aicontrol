// 过程段与统一步骤壳（★ 折叠可见集合与三模式由展示投影派生单源〔item.mode / visibleIndices /
// hiddenCount〕，本件只消费——组件内不重复扫描）。
// 职责一句话：**一个过程段（连续思考/工具/收束后中间正文步骤）的卡片、段级控制行与统一步骤
// 骨架**——段外层背景/圆角、摘要条/展开更多/收起控制行、段内每个步骤的「图标列 + 竖线 +
// 内容列」骨架与内容高测量，思考、工具与中间正文三行种共用同一骨架。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话成立（过程段 = 新的展示单元，
//   此前不存在任何承载件）；②不能并入 ChatToolCard（那是单个工具步骤的内容件，且过程段要
//   容纳三行种）也不能并入 ChatMessageItem（本件表达「段」而非「条消息」）；③实逻辑
//   非转接壳（控制行、骨架几何、测量回写全在此）。
// · 中间正文步骤（2026-11-04）内容件在独立件 ChatIntermediateBodyStep：本件只分派步骤壳与
//   两条正文交互上行，不持 Markdown 树；运行中的正文与每轮最终正文仍走独立气泡展示项。
// · 段级展示状态（三层关系）：运行中默认展示最近两步（preview）、整轮正常完成
//   且未手动展开则收成摘要（summary）、用户主动展开后任何收尾事件都不得擅自收起（expanded）。
//   模式/可见集合的唯一推导入口 = ChatDisplayProjection.updateSegmentPresentation——本件点击
//   只写 item.manualExpanded（意愿）后调用它重算，不自行扫业务活跃态。
// · ★ 开合收口改判（真机报障「收起键与详情两层错位」）：段级意愿与步骤级详情意愿
//   职责分离——①段「收起」一并清掉段内全部详情意愿（收起 = 全收，键名副其实）；②关详情
//   只收自身、不撤段意愿（决明修正：多步链内点单条思考只该收自己，段展开态与「收起」键
//   保持，要整段收回请点键）；③关→开仍提升段意愿（收尾事件不藏走正在阅读的详情，settle
//   从不主动收）。
// · 段级隐藏的副作用边界：被隐藏的步骤是**不渲染**（条件分支，非零高占位），
//   故不参与的只是展示；工具执行/审批状态/作答草稿都在消息字段与常显步骤里（等待用户处理的
//   步骤恒在可见集合内，其交互件不因折叠卸载）；等待步骤始终在同一个 ForEach 内以源 id 为键，
//   模式改变只改变该 ForEach 的输入，摘要条在它之前。
// · 依赖方向：本件 → ChatDisplayProjection（展示项与派生规则）/ ChatMessageCompose（消息模型）/
//   ChatToolCard（工具步骤内容件）/ ChatIntermediateBodyStep（中间正文步骤内容件）/
//   ChatStepTitleRow（步骤标题行）/ common/Theme 单向。
// · 只给用户动作加自然尺寸动画，门控复用 ChatMarkdownBody.markdownMotionEnabled；
//   自动 done/error/stopped 的收束仍由原投影立即更新，不给业务态增加动画寿命或高度缓存。
//   ★ 2026-11-05 方向分流：只有**展开**起画（内容先到终点位、clip 卡缘下探揭示）；收起直写
//   （内容同帧卸载，插值只会留空盒并顶住下方正文），四处折叠点同一口径。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
// 二期 S4 #8 图搜宫格：剪贴板与外链（UIContext 形态取宿主 context）
import { pasteboard } from '@kit.BasicServicesKit';
import { launchExternalLink } from '../../common/ExternalLink';
import { cardBg, cardBgTransparent, cardBorderColor, cardDescColor, CARD_SPACING, BUBBLE_PAD_NEAR,
  BUBBLE_RADIUS, CHAIN_GUTTER_WIDTH, CHAIN_LINE_WIDTH, CHAIN_STEP_ICON_SIZE, CHAIN_ICON_MASK_PAD,
  CHAIN_STEP_ICON_CENTER, CHAIN_STEP_ICON_TOP, CHAIN_STEP_PRESS_RADIUS, CHAIN_STEP_TEXT_PAD_L,
  SEGMENT_PAD_V, SEGMENT_PRESS_INSET, SEGMENT_ROW_CONTENT_PAD, SEGMENT_ROW_GAP,
  SEGMENT_ROW_PAD_R, SEGMENT_BODY_PAD_L } from '../../common/Theme';
import { getThinkExpandDefault, PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT }
  from '../../common/AppPreferences';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY,
  bodyFontFamily } from '../../common/ChatFont';
import { roundDurationSuffix } from '../../common/chat/ChatAnswerChoice';
import { ChatMessage, dsStepDetailOf, dsStepIconOf, dsStepTitleOf,
  dsServerSegmentSummary, dsImageGridOf, DsImageItem } from './ChatMessageCompose';
import { ChatDisplayItem, SEGMENT_MODE_EXPANDED, SEGMENT_MODE_PREVIEW,
  updateSegmentPresentation } from './ChatDisplayProjection';
import { ChatStepTitleRow } from './ChatStepTitleRow';
import { ChatToolCard } from './ChatToolCard';
import { ChatIntermediateBodyStep } from './ChatIntermediateBodyStep';
import { ChatRoundHeader } from './ChatMessageHeader';
import { markdownMotionEnabled } from './ChatMarkdownBody';

// 用户展示变更共用同步入口：闭包状态当场落定，快速反向直接采用当前意愿；不等完成后回写。
// 自然 Column/条件内容由官方布局插值，不测全文高、不冻结内容盒；精确中间帧仍须设备验证。
// 关闭试验、release 或减弱动态效果时不启动画，直接执行同一份状态写入。
// ★ 2026-11-05 收起方向直写（真机报障「收起未完成就把正文推下去、中间留白」）：条件渲染式
// 折叠的内容在状态写入的同一帧就卸载，而高度由 animateTo 插值 ⇒ 收起这 200ms 里卡片是个
// 「只剩控制行的空盒」，卡缘从旧高扫到新高，卡内留白且下方正文被旧高顶着。收起方向的内容
// 早已不在、插值不携带任何信息，故 animated 传 false 直写（内容与高度同帧落，零留白）；
// 展开方向仍是内容先到终点位、由 clip 卡缘下探逐步揭示。自动收束照旧不经本入口。
// 导出供段内中间正文内容件同源复用（该件不能 `height(0)` 假装收起，也要同一套门控与参数）。
export function applyProcessPresentation(uiContext: UIContext, change: () => void,
  animated: boolean = true): void {
  if (!animated || !markdownMotionEnabled()) {
    change();
    return;
  }
  uiContext.animateTo({ duration: 200, curve: Curve.EaseOut }, change);
}

// ── 段级控制行高（vp；比步骤标题行低一档：段级控制非步骤身份，取官方触控最小高度线以上）──
const SEGMENT_CONTROL_ROW_HEIGHT: number = 40;

// 段内是否含非思考步骤（工具、DS 服务端步骤或收束后中间正文）：done 段含任一即「处理完成」，
// 只有纯思考段才是「思考完成」。纯函数置组件外顶层，摘要分流判据可直跑（不再由控制行图标
// 判据兼任）。
export function segmentHasNonThinkingStep(steps: ChatMessage[]): boolean {
  for (const step of steps) {
    if (step.kind === 'tool' || step.kind === 'assistant' || step.kind === 'serverstep') {
      return true;
    }
  }
  return false;
}

// 段摘要文案（纯函数，组件外顶层——断言可直跑）：
// done 纯思考「思考完成」/ done 含工具或中间正文「处理完成」/ error「处理未完成」/
// stopped「已停止」/ unknown「查看处理过程」；**异常不写成功**（error/stopped 绝不出现「完成」字样，unknown 用中性
// 文案）；有隐藏才附真实隐藏步数（隐藏 0 不出摘要条——调用方判据）。文案遵守项目「面向用户
// 文案写作规约」：逗号分句、用顿号隔并列、不叠括号。
// ★ 第四可选参 = 本轮**可信耗时**（毫秒）——合法时追加「 · 本轮耗时 X 秒」（格式单源 =
// ChatAnswerChoice.roundDurationSuffix）；原成功/失败/停止/unknown 文案不被覆盖，缺省/空值零
// 变化。★ 真机报障修复：耗时属轮不属段——本函数只负责有值即拼；**同一轮只在本轮最后一个
// 过程段拿到值**（其余段恒 undefined，回填单源 = ChatDisplayProjection 装配末段），故
// 「本轮耗时」一轮出现一次，不会在思考段/工具段上重复同一个数字
export function segmentSummaryText(roundStatus: string, hasNonThinkingStep: boolean,
  hiddenCount: number, durationMs?: number): string {
  let text: string;
  if (roundStatus === 'done') {
    text = hasNonThinkingStep ? '处理完成' : '思考完成';
  } else if (roundStatus === 'error') {
    text = '处理未完成';
  } else if (roundStatus === 'stopped') {
    text = '已停止';
  } else {
    text = '查看处理过程';
  }
  const body: string = hiddenCount > 0 ? text + '，' + hiddenCount + ' 步已收起' : text;
  return body + roundDurationSuffix(durationMs);
}

// ── 思考步骤内容三态常量（结构化三态：展开态全文自然高 / 生成中定高窗装尾部切片 /
// 收束折叠零视窗节点）──
// 折叠态预览行数（观感参数可单点调）
const THINKING_COLLAPSED_LINES: number = 3;
// 思考文字字号（fp）与行高（vp）——切片估算与 Text 样式同源
const THINK_FONT_SIZE: number = 12;
const THINK_LINE_HEIGHT: number = 18;
// 生成中折叠态内容区高度（vp）= 恰 3 行：固定高，切片文本换多少写多少都不改高度
const THINK_BODY_COLLAPSED_H: number = THINKING_COLLAPSED_LINES * THINK_LINE_HEIGHT;
// 生成中折叠窗上端渐隐层高度（vp）= 恰 1 行：只隐最旧的可见行，最新内容贴下沿恒清晰。
// 只加上端（红线）；RIK 上下双端 64px 渐隐不照抄，高度刻意收窄到 1 行内
const THINK_FADE_HEIGHT: number = THINK_LINE_HEIGHT;
// 单行字数估算的宽度未测得兜底（切片取段用；偏小 = 少取历史，不裁最新）
const THINK_TAIL_FALLBACK_CHARS: number = 20;

// ── 折叠态尾部切片（纯函数，组件外顶层；assert-feature-domain 109 组直跑）──
// 返回「交给 Text 从头部渲染」的那一段 = 思考全文的末尾片段，四环：
//  ① 末尾取段——字符量上界 = 折叠行数 × 单行字数估算；
//  ② 代理对保护——切点落在 UTF-16 代理对中间则前移一位（emoji 不被劈开）；
//  ③ 行首对齐——切点后半行宽内有换行则改从换行后开始，不显示半行；
//  ④ 行数收口——短行密集文本按字符量取会远超折叠行数，Text 的 maxLines 只渲染前几行 ⇒
//     窗口里落的反而是旧内容；故把切点沿换行边界后推，直到剩余部分渲染行数 ≤ 折叠行数
//     ——末尾（最新段）始终保留在窗口内
export function thinkTailSlice(text: string, perLine: number): string {
  const limit: number = perLine * THINKING_COLLAPSED_LINES;
  if (text.length <= limit) {
    return text;
  }
  let start: number = text.length - limit;
  const code: number = text.charCodeAt(start);
  if (code >= 0xDC00 && code <= 0xDFFF) {
    start--;
  }
  const nl: number = text.indexOf('\n', start);
  if (nl >= 0 && nl < start + Math.ceil(perLine / 2)) {
    start = nl + 1;
  }
  // 收口循环有界：每轮至少前进 1 个字符，窗内换行数 ≤ 字符量上界；窗内无换行（单行长段）
  // = 字符量切法即正解，直接退出
  while (thinkPreviewLines(text, start, perLine) > THINKING_COLLAPSED_LINES) {
    const next: number = text.indexOf('\n', start);
    if (next < 0) {
      break;
    }
    start = next + 1;
  }
  return text.substring(start);
}

// 切片渲染行数估算（与折叠态 Text 的 maxLines 同口径）：段内按单行字数折行 + 段数；
// 空段记 1 行（空行同样占一行高，不记会低估行数）
function thinkPreviewLines(text: string, start: number, perLine: number): number {
  let lines: number = 0;
  const segs: string[] = text.substring(start).split('\n');
  for (const seg of segs) {
    lines += Math.max(1, Math.ceil(seg.length / perLine));
  }
  return lines;
}

// ═══ 过程段（展示项 kind='segment' 的渲染件）═══
@Component
export struct ChatProcessSegment {
  // 展示项（@ObjectLink：段内成员与展示派生字段原地更新驱动重渲）
  @ObjectLink item: ChatDisplayItem;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（即时面）：消费表达式显式传参建依赖，
  // 档位变化属性级刷新段卡底色；档位键不进 Repeat/LazyForEach 键（列表键纪律）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 正文字体两键 @StorageProp 自订阅：段级控制行（收起 / 展开更多 /
  // 摘要）属会话页消息显示面，随正文字体即时变化；家族串推导单源 = ChatFont.bodyFontFamily
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  // 工具步骤交互上行（ChatPageContent 构造处注入，经段容器原样转发给 ChatToolCard）
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  onResendTool: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {};
  onEditResendTool: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {};
  // 输入位托管认领上行（ChatToolCard → 本件 → ChatPageContent；只透传不改判）
  onAwaitingStep: (msg: ChatMessage) => void = (msg: ChatMessage): void => {};
  // 展示意愿变更前置回调：用户手动展开/收起或开
  // 步骤详情**之前**调用——宿主（ChatPageContent）据此取消进页旧校正（follow.cancelAlign）
  // 并起「展开局部钉顶」，随后由本件改展示字段；不 forceToBottom
  // （收缩仍由原状态更新链驱动）
  // ★ 携带参数 = 被点展示项的锚点消息 id（段级控制行 = 段首步、步骤详情 = 该步）
  // ——宿主按它反查 List 项位，把这一行钉在屏上（上沿不动、增量向下长）；空串 = 无锚可用
  //（段无步骤的防御路径），宿主按「不接管」处理
  onPresentationChange: (msgId: string) => void = (_msgId: string): void => {
  };
  // 中间正文步骤的两条正文交互上行（宿主既有链：Markdown 锚点滚动 / 消息全文面板）。
  // 不接工具回调与轮级操作栏——段内步骤不获轮尾权限；运行中不迁移的中间正文仍走独立气泡。
  // ★ 2026-11-05 菜单笔：原第三条 onMoreMenu（省略号「更多」菜单）随键整条删除，两项功能
  // 由长按全文面板覆盖。
  onMarkdownAnchor: (id: string) => void = (_id: string): void => {};
  onCopyText: (msgId: string) => void = (_msgId: string): void => {};

  // 段内是否含工具步骤：**只服务控制行 gutter 图标**（工具段 / DS 服务端步骤段 gearshape /
  // 纯思考段 lightbulb），不再承担摘要文案分流（该判据已上收 segmentHasNonThinkingStep）；
  // 段类型恒定，逐 build 现算零成本
  private hasToolStep(): boolean {
    for (const step of this.item.steps) {
      if (step.kind === 'tool' || step.kind === 'serverstep') {
        return true;
      }
    }
    return false;
  }

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // 段级控制文案（三模式单源；耗时只在摘要档传
  // ——expanded 仍「收起」、preview 仍「展开更多 N 步」，均不附耗时）。
  // ★ DS 服务端步骤段（S3①）：摘要档优先出「已搜索 N 次」级聚合一句（N 与动词按 call 类型
  // 聚合，单源 = dsServerSegmentSummary）——异常轮回落既有文案（「处理未完成 / 已停止」
  // 不被计数句覆盖，异常不写成功口径不破）
  private controlText(): string {
    if (this.item.mode === SEGMENT_MODE_EXPANDED) {
      return '收起';
    }
    if (this.item.mode === SEGMENT_MODE_PREVIEW) {
      return '展开更多 ' + this.item.hiddenCount + ' 步';
    }
    const dsSummary: string =
      this.item.roundStatus === 'error' || this.item.roundStatus === 'stopped' ? '' :
        dsServerSegmentSummary(this.item.steps);
    if (dsSummary !== '') {
      return dsSummary + roundDurationSuffix(this.item.roundDurationMs);
    }
    return segmentSummaryText(this.item.roundStatus, segmentHasNonThinkingStep(this.item.steps),
      this.item.hiddenCount, this.item.roundDurationMs);
  }

  // 段卡行缝（控制行 → 下方首个步骤标题行）：有可见步骤才补——
  // 空段展开态补了，卡底会多出一段没有对象承接的留白（四缘露白随之不等）
  private controlGap(): number {
    return this.item.visibleIndices.length > 0 ? SEGMENT_ROW_GAP : 0;
  }

  // 控制行显隐：展开态恒显（收起入口）；preview 仅隐藏数 > 0 出「展开更多」（无隐藏不出
  // 「展开更多 0 步」）；summary 仅隐藏数 > 0 出摘要条（「隐藏 0 不出空摘要」——全等待或
  // 空折叠自己说明问题）
  private controlVisible(): boolean {
    if (this.item.mode === SEGMENT_MODE_EXPANDED) {
      return true;
    }
    return this.item.hiddenCount > 0;
  }

  // 段级控制行的锚点消息 id（段首步——展示项 → List 项位反查用；段必有步骤才渲染控制行，
  // 空段防御回空串 = 宿主不接管钉顶）
  private headMsgId(): string {
    return this.item.steps.length > 0 ? this.item.steps[0].id : '';
  }

  // 控制行点击（单入口，先意愿后派生）：manualExpanded 取反（expanded → 收起回自动模式，
  // 其余 → 展开）；★ 开合收口改判：收起分支一并清掉段内全部步骤详情意愿
  //（「收起」名副其实——内容与整排一起收；原「段收起不清详情」契约由真机报障改判）。
  // 随后 updateSegmentPresentation 重算模式与可见集合。不影响另一段、不切分支。
  // ★ 动效按方向分流（真机报障「收起未完成就把正文推下去」）：展开走 200ms 卡缘下探揭示，
  // 收起直写（步骤同帧卸载 + 高度同帧落，不留空盒）
  private toggleSegment(): void {
    this.onPresentationChange(this.headMsgId()); // 用户手动意图：先取消进页旧校正并起钉顶，再改展示字段
    const next: boolean = !this.item.manualExpanded;
    applyProcessPresentation(this.getUIContext(), (): void => {
      this.item.manualExpanded = next;
      if (!next) {
        this.collapseDetails();
      }
      updateSegmentPresentation(this.item);
    }, next);
  }

  // 清掉段内全部步骤的详情意愿（含当前不可见的隐藏步骤——重开段 = 全新收起态）；只写
  // true→false 的有值位，不对已收起步骤发多余 @Observed 通知
  private collapseDetails(): void {
    for (const step of this.item.steps) {
      if (step.detailExpanded === true) {
        step.detailExpanded = false;
      }
    }
  }

  // 步骤详情开启上行（ChatProcessStep 转发，携该步消息 id = 钉顶锚点行）：用户正在阅读该
  // 步骤 ⇒ 同时提升本段展开意愿（不能整轮结束时突然藏起正在看的详情）。
  // 关详情只收自身、不撤段意愿（决明修正：段级收回只走「收起」键，
  // 行点击管自己）
  private onStepDetailOpened(msgId: string): void {
    this.onPresentationChange(msgId);
    if (!this.item.manualExpanded) {
      this.item.manualExpanded = true;
      updateSegmentPresentation(this.item);
    }
  }

  // 段级控制行（摘要条 / 展开更多 N 步 / 收起）：与步骤标题行同一套按压与圆角；零自身定位
  // 常量——行距 / 右内距 / 左沿全取 Theme 单源，符号列中心 ≡ 步骤图标中心、控制文案左沿 ≡
  // 步骤文本左沿（蒙层随卡体 padding 收至贴缘 4，行内容以 SEGMENT_ROW_CONTENT_PAD 回添复位，
  // 轴线关系见 Theme 注释）。gutter 符号 = **过程图标**（工具段 gearshape / 纯思考段
  // lightbulb——与步骤图标同族），行尾出箭头（chevron_down，展开态 180°）；三段模式共用同一
  // 行结构，只有文案与箭头方向变化。行缝 SEGMENT_ROW_GAP：无可见步骤（空段展开态）不补
  // （见 controlGap）。缝挂 margin 而非行高：规范「行缩进禁 margin」管的是**水平缩进**（真机
  // 实测宽度方向的蒙层不缩进），主轴方向行距用 margin 是既有形制（先例 = ChatPageContent
  // 「新行型落 ListItem 必须自带上距」）。
  @Builder
  ControlRow() {
    Button() {
      Row({ space: CHAIN_STEP_TEXT_PAD_L }) {
        Column() {
          SymbolGlyph(this.hasToolStep() ? $r('sys.symbol.gearshape') :
            $r('sys.symbol.lightbulb'))
            .fontSize(CHAIN_STEP_ICON_SIZE)
            .fontColor([cardDescColor()])
        }
        .width(CHAIN_GUTTER_WIDTH)
        .alignItems(HorizontalAlign.Center)
        Text(this.controlText())
          .fontSize(13)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(this.item.roundStatus === 'error' || this.item.roundStatus === 'stopped' ?
            $r('sys.color.ohos_id_color_warning') : cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([cardDescColor()])
          .rotate({ angle: this.item.mode === SEGMENT_MODE_EXPANDED ? 180 : 0 })
      }
      .width('100%')
      .height(SEGMENT_CONTROL_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .padding({ left: SEGMENT_ROW_CONTENT_PAD, right: SEGMENT_ROW_PAD_R })
    }
    .type(ButtonType.Normal)
    .width('100%')
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(CHAIN_STEP_PRESS_RADIUS)
    .margin({ bottom: this.controlGap() })
    // 条件控制行消失时立即卸载，覆盖 animateTo 上下树的默认淡出。
    .transition(TransitionEffect.IDENTITY)
    .onClick((): void => {
      this.toggleSegment();
    })
  }

  build() {
    // 轮头行（决明拍板；时间行已退役——时间迁入回答卡右上角常驻卡头行，本载体只出模型名）：
    // 本段为轮内首个上屏项时头行挂段顶（卡外上方）。与正文载体 ChatMessageItem.headHost 互斥，
    // 一轮只出一处（判据单源 = 展示投影 buildDisplayItems）。
    // ★ 间距只认本 Column 的 space（决明拍板：与思考卡和正文的间距一致）：ArkUI 的 Column
    // space 是容器统一插入的相邻间距，会压过子组件主轴方向的 `.margin()`（实测）——勿改由段体
    // margin 承担首段间距。段体 `.margin({ top: CARD_SPACING })` 保留：无头行时本 Column 只有
    // 段体一个子项、space 不参与，margin 才生效（纪律见 ChatPageContent「新行型落 ListItem
    // 必须自带上距」）。
    // 轮级模型名取段首步——步骤行由发送链继承本轮正文行（见
    // ChatToolRoundCtrl.stampRoundMeta 与 ChatStreamFlowCtrl 思考行同款继承）
    Column({ space: 12 }) {
      if (this.item.head && this.item.steps.length > 0) {
        ChatRoundHeader({
          modelLabel: this.item.steps[0].modelLabel ?? ''
        })
      }
      Column() {
        if (this.controlVisible()) {
          this.ControlRow()
        }
        ForEach(this.item.visibleIndices, (stepIndex: number): void => {
          ChatProcessStep({
            msg: this.item.steps[stepIndex],
            // 段内连线范围 = 可见步骤集合内相邻两步骤之间（首可见无上段线、末可见无下段线）；
            // 隐藏步骤不参与（任务书 §7.1 竖线穿图标列中心）
            first: stepIndex === this.item.visibleIndices[0],
            last: stepIndex === this.item.visibleIndices[this.item.visibleIndices.length - 1],
            onDetailOpened: (msgId: string): void => {
              this.onStepDetailOpened(msgId);
            },
            onAskSubmit: (callId: string, answerJson: string): void => {
              this.onAskSubmit(callId, answerJson);
            },
            onBrowseConfirm: (callId: string, approved: boolean): void => {
              this.onBrowseConfirm(callId, approved);
            },
            onResendTool: (msgId: string, toolName: string, argsJson: string): void => {
              this.onResendTool(msgId, toolName, argsJson);
            },
            onEditResendTool: (msgId: string, toolName: string, argsJson: string): void => {
              this.onEditResendTool(msgId, toolName, argsJson);
            },
            onAwaitingStep: (msg: ChatMessage): void => {
              this.onAwaitingStep(msg);
            },
            onMarkdownAnchor: (id: string): void => {
              this.onMarkdownAnchor(id);
            },
            onCopyText: (msgId: string): void => {
              this.onCopyText(msgId);
            }
          })
        }, (stepIndex: number): string => this.item.steps[stepIndex].id)
      }
      // 段体 = 一层外背景 + 一处外圆角：段内步骤不再各画完整卡背景，与正文气泡独立、不做
      // 切角拼接——故恒四角圆角 + 行上距 CARD_SPACING 由外层承担。宽度与既有消息行同源 =
      // 行宽 − 左右近距（外层 padding 承担左右近距、卡体 width 100%），卡左缘 ≡ 正文气泡左缘
      //（两处同取 BUBBLE_PAD_NEAR）。卡体 padding 用 SEGMENT_PRESS_INSET（按压蒙层贴缘 4，
      // 组卡同款）、行内容以 SEGMENT_ROW_CONTENT_PAD 回添复位——两条轴线关系（「竖线中心 ≡
      // 正文首字中心」与「竖线居中于卡左缘与标题左沿之间」，后者为方向关系保留）由常量共同
      // 决定，实算口径见 Theme 两常量注释
      .width('100%')
      .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
      .borderRadius(BUBBLE_RADIUS)
      // ★ 出卡中间帧修复：段内展示切换（applyProcessPresentation 200ms）与工具卡折叠
      //（TOOL_FOLD_ANIM_MS 300ms）都是布局类高度动画——按官方 FAQ faqs-arkui-1400，此类动画
      // 内容直接到终点态，卡高在途时终位步骤行与竖线会画在卡外灰底上（真机实锤：展开时工具
      // 步骤行浮在卡外）。clip(true) 令子组件超出卡圆角轮廓的区域不可见——只裁绘制不参与测量
      // 与布局，稳态卡高恒等于内容高零影响；两处动画的揭示形态从「内容先现、卡边追赶」改为
      // 「卡缘下探逐步揭示」。
      .clip(true)
      .padding({ left: SEGMENT_PRESS_INSET, right: SEGMENT_PRESS_INSET, top: SEGMENT_PAD_V, bottom: SEGMENT_PAD_V })
    }
    .width('100%')
    .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
    .margin({ top: CARD_SPACING })
  }
}

// ═══ 统一步骤壳（段内单个步骤的骨架）═══
// 「图标列 + 竖线 + 内容列」三件是思考、工具与中间正文**同一套**实现：图标列宽/中心、标题行高
//（在 ChatStepTitleRow）、内容列左沿与段内间距全由本件与 Theme 常量单源给出，三个行种不再各调
// 一组近似常数。
// 竖线分上下两段，范围随可见集合内相邻关系（first/last 判据由段容器给出）：
// 上段线止于图标上缘留隙，下段线从图标下缘留隙起画至内容底，替代白底遮罩。
// 线高恒不超过内容高；测量点仍挂独立内容列，禁止测含线的 Stack 后回填。
@Component
struct ChatProcessStep {
  @ObjectLink msg: ChatMessage;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 段内首个/末个可见步骤（连线上段/下段的取色判据；@Prop——展开/收起使可见集合变化时随父更新）
  @Prop first: boolean = false;
  @Prop last: boolean = false;
  // 步骤详情开启上行（仅用户关→开时被调用；透传给工具卡/思考步骤）——携本步消息 id
  //（宿主据此把该步所在段卡钉在屏上，开详情时上沿不动）
  onDetailOpened: (msgId: string) => void = (_msgId: string): void => {
  };
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  onResendTool: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {};
  onEditResendTool: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {};
  // 输入位托管认领上行（工具卡双钩子 → 本件 → 段容器 → 宿主）
  onAwaitingStep: (msg: ChatMessage) => void = (msg: ChatMessage): void => {};
  // 中间正文步骤两条交互上行（经段容器转发到 ChatPageContent 既有宿主）
  onMarkdownAnchor: (id: string) => void = (_id: string): void => {};
  onCopyText: (msgId: string) => void = (_msgId: string): void => {};
  // 内容列实测高度（vp；下段线的显式数值高数据源；初值 0 = 首帧未测得，线高 0 不渲染）
  @State private contentHeight: number = 0;

  // 内容列实测高度回写（唯一测量点；只收有限非负值，差值 <0.5vp 不更新防同值抖动，
  // 允许由非零回落为零——内容缩短即收敛）
  private onContentArea(hVp: number): void {
    if (!Number.isFinite(hVp) || hVp < 0) {
      return;
    }
    if (Math.abs(hVp - this.contentHeight) < 0.5) {
      return;
    }
    this.contentHeight = hVp;
  }

  @Builder
  LineLayers() {
    // x 偏移加 SEGMENT_ROW_CONTENT_PAD 前缀——线随内容列同挪（卡体 padding 收 4 后行内容盒
    // 起点右移 4，线相对 Stack 起点同加 4 才对回原屏位：轨心 ≡ 卡缘 4+4+gutter÷2 = 22，与
    // 标题图标列/正文首字中心同轴不变）
    Column() {
    }
    .width(CHAIN_LINE_WIDTH)
    .height(Math.max(0, this.contentHeight -
      (CHAIN_STEP_ICON_CENTER + CHAIN_STEP_ICON_SIZE / 2 + CHAIN_ICON_MASK_PAD)))
    .backgroundColor(this.last ? Color.Transparent : cardBorderColor(this.appColorMode))
    .offset({ x: SEGMENT_ROW_CONTENT_PAD + (CHAIN_GUTTER_WIDTH - CHAIN_LINE_WIDTH) / 2,
      y: CHAIN_STEP_ICON_CENTER + CHAIN_STEP_ICON_SIZE / 2 + CHAIN_ICON_MASK_PAD })
    .hitTestBehavior(HitTestMode.None)
    Column() {
    }
    .width(CHAIN_LINE_WIDTH)
    .height(CHAIN_STEP_ICON_TOP)
    .backgroundColor(this.first ? Color.Transparent : cardBorderColor(this.appColorMode))
    .offset({ x: SEGMENT_ROW_CONTENT_PAD + (CHAIN_GUTTER_WIDTH - CHAIN_LINE_WIDTH) / 2 })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.LineLayers()
      Row() {
        Column() {
          if (this.msg.kind === 'tool') {
            ChatToolCard({
              msg: this.msg,
              onDetailOpened: (): void => {
                this.onDetailOpened(this.msg.id);
              },
              onAskSubmit: (callId: string, answerJson: string): void => {
                this.onAskSubmit(callId, answerJson);
              },
              onBrowseConfirm: (callId: string, approved: boolean): void => {
                this.onBrowseConfirm(callId, approved);
              },
              onResend: (msgId: string, toolName: string, argsJson: string): void => {
                this.onResendTool(msgId, toolName, argsJson);
              },
              onEditResend: (msgId: string, toolName: string, argsJson: string): void => {
                this.onEditResendTool(msgId, toolName, argsJson);
              },
              onAwaitingStep: (msg: ChatMessage): void => {
                this.onAwaitingStep(msg);
              }
            })
          } else if (this.msg.kind === 'assistant') {
            // 收束后中间正文：内容件自持 Markdown 挂载时机与三条交互，壳只给竖线与内容列。
            ChatIntermediateBodyStep({
              msg: this.msg,
              onDetailOpened: (): void => {
                this.onDetailOpened(this.msg.id);
              },
              onMarkdownAnchor: (id: string): void => {
                this.onMarkdownAnchor(id);
              },
              onCopyText: (msgId: string): void => {
                this.onCopyText(msgId);
              }
            })
          } else if (this.msg.kind === 'serverstep') {
            // DS 服务端步骤行（S2⑤ 行种，S3① 接手渲染）：标题行 + 明细行内容件；数据载荷
            // toolOutputJson = call 原样串（实时链与回放合成同承载字段）
            ChatServerStep({ msg: this.msg })
          } else {
            // 既有 thinking 分支；未知 kind 不落中间正文（防把新行种默认当正文渲染）。
            ChatThinkingStep({
              msg: this.msg,
              onDetailOpened: (): void => {
                this.onDetailOpened(this.msg.id);
              }
            })
          }
        }
        .layoutWeight(1)
        // 步与步之间的行缝（三处行缝同取 SEGMENT_ROW_GAP 单源；padding 在 Stack 内，竖线随
        // 内容列延伸穿过行缝，相邻步骤线段仍相接成连通长线）
        .padding({ bottom: SEGMENT_ROW_GAP })
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.onContentArea(newArea.height as number);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    // 线层下段随内容列实测高、恒 ≤ 内容高；本裁剪作余量兜底——线不越段体
    .clip(true)
    // ForEach 剔出的步骤立即离场，不以默认淡出保留旧热区与行高；等待项仍由投影恒显。
    .transition(TransitionEffect.IDENTITY)
  }
}

// ═══ DS 服务端步骤内容件（S3①；头行 = 共享标题行）═══
// 标题 = action 短句（映射单源 = dsStepTitleOf——search→「搜索」+queries、open_page→
// 「打开网页」、find_in_page→「页内查找」、read_link→「读链接」），图标按 action 分流
// （单源 = dsStepIconOf，符号全取全仓在场证据）；右槽 = 状态位（running 转圈 / error 警告 /
// done 完成勾——形制照 ChatToolCard.GenericHeadSlot 状态位族）。明细行 = URL/查找词单行
// 省略（外部数据防御——dsStepDetailOf 空串不渲染）。无展开详情：sources/annotations 由
// M1 来源卡承载（消息级一处，步骤行不重复面板）。图搜步骤（kind=image 系）同走本件通用
// 形态 + 来源计数（代决 2 首轮不做图片宫格）。
@Component
struct ChatServerStep {
  @ObjectLink msg: ChatMessage;
  // 正文字体两键 @StorageProp 自订阅：明细行小字随正文字体（思考步骤明细同款口径）
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // ── 图搜宫格（二期 S4 #8）──
  // 取数记忆化（照来源卡解析记忆化先例）：toolOutputJson 是纯函数入参，串不变即复用；
  // build 判据链一次渲染会问两次（expandable 与展开区），缓存后第二次零成本
  private gridCacheJson: string = '';
  private gridCacheList: DsImageItem[] = [];

  private imageGrid(): DsImageItem[] {
    const json: string = this.msg.toolOutputJson ?? '';
    if (json !== this.gridCacheJson) {
      this.gridCacheJson = json;
      this.gridCacheList = dsImageGridOf(json);
    }
    return this.gridCacheList;
  }

  private gridExpanded(): boolean {
    return this.msg.detailExpanded === true;
  }

  // 展开意愿读写复用 msg.detailExpanded（与思考段同字段不同行——每条消息的步骤行各自持值，
  // 互不影响；回放行 undefined 天然收起）。展开 200ms / 收起直写，与思考段同节奏
  private toggleGrid(): void {
    const next: boolean = !this.gridExpanded();
    applyProcessPresentation(this.getUIContext(), (): void => {
      this.msg.detailExpanded = next;
    }, next);
  }

  private toastText(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // 静默（无 UI 上下文边缘态）
    }
  }

  private openUrl(url: string): void {
    if (url === '') {
      return;
    }
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, url);
    } catch (e) {
      this.toastText('无法打开链接');
    }
  }

  private copyImageLink(url: string): void {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data)
        .then((): void => {
          this.toastText('图片链接已复制');
        })
        .catch((): void => {
          this.toastText('复制失败');
        });
    } catch (e) {
      this.toastText('复制失败');
    }
  }

  // 点图动作菜单（UIContext 版 showActionMenu——半模态菜单形态；禁全局 promptAction.*）。
  // 三动作全部可达：打开大图（系统浏览器，长按可存）/ 复制图片链接 / 打开来源网页
  //（pageUrl 为空时第三项说明该条没有来源页，不留死键）。任务书点名的「存工作区 / 追问
  // 这张图 / 图片编辑」需跨层入口（工作区写入管道 / 输入栏回填 / 图片编辑页 push 栈），
  // 步骤行组件都拿不到，按任务书「无现成入口时用打开大图占位且必须可达」的授权处置
  private onImageTap(item: DsImageItem): void {
    const title: string = item.title !== '' ? item.title : '图搜结果';
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: title + '\n' + item.url,
        buttons: [
          { text: '打开大图', color: $r('sys.color.font_primary') },
          { text: '复制图片链接', color: $r('sys.color.font_primary') },
          { text: '打开来源网页', color: $r('sys.color.font_primary') }
        ]
      }).then((result): void => {
        if (result.index === 0) {
          this.openUrl(item.url);
        } else if (result.index === 1) {
          this.copyImageLink(item.url);
        } else if (result.index === 2) {
          if (item.pageUrl !== '') {
            this.openUrl(item.pageUrl);
          } else {
            this.toastText('这条结果没有来源网页');
          }
        }
      }).catch((): void => undefined);
    } catch (e) {
      // 弹层不可用（无 UI 上下文）——静默，不吞点击但也不打断
    }
  }

  // 宫格（3 列 / 单组上限由 dsImageGridOf 截在 20 张）。Grid 高度自适应内容、不设固定高
  // 即不滚动；scrollBar 显式关（任务书滚动容器红线，即便当前形态不滚也照守）
  @Builder
  ImageGrid() {
    Grid() {
      ForEach(this.imageGrid(), (item: DsImageItem): void => {
        GridItem() {
          Image(item.url)
            .width('100%')
            .aspectRatio(1)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .onClick((): void => {
              this.onImageTap(item);
            })
        }
      }, (item: DsImageItem): string => item.url + '#' + item.index.toString())
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(6)
    .rowsGap(6)
    .width('100%')
    .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R, top: 6 })
    .scrollBar(BarState.Off)
  }

  // 状态位右槽（形制单源照 ChatToolCard.GenericHeadSlot——running 转圈 / error 警告三角 /
  // done 完成勾；serverstep 行无 cancelled 态——中止轮由「已停止」段摘要承载）
  @Builder
  ServerStepSlot() {
    Row({ space: 8 }) {
      if (this.msg.toolState === 'running') {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(cardDescColor())
        Text('执行中…')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
      } else if (this.msg.toolState === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(14)
          .fontColor([$r('sys.color.ohos_id_color_warning')])
        Text('出错')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor($r('sys.color.ohos_id_color_warning'))
      } else {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([cardDescColor()])
        Text('完成')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
      }
    }
  }

  build() {
    Column() {
      ChatStepTitleRow({
        icon: dsStepIconOf(this.msg.toolOutputJson ?? ''),
        title: dsStepTitleOf(this.msg.toolOutputJson ?? ''),
        // 有图搜结果图才可展开（普通步骤行仍零展开，点击行为与改前逐字一致）
        expandable: this.imageGrid().length > 0,
        expanded: this.gridExpanded(),
        onToggle: (): void => {
          this.toggleGrid();
        },
        slot: (): void => {
          this.ServerStepSlot();
        }
      })
      if (dsStepDetailOf(this.msg.toolOutputJson ?? '') !== '') {
        Text(dsStepDetailOf(this.msg.toolOutputJson ?? ''))
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R })
      }
      // 图搜宫格（二期 #8）：展开态才渲染（收起零节点——与思考段同纪律）
      if (this.gridExpanded() && this.imageGrid().length > 0) {
        this.ImageGrid()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ═══ 思考步骤内容件（头行 = 共享标题行）═══
// 标题行 = ChatStepTitleRow（与工具步骤同源按压/几何）；展开态 = 全文自然高；生成中折叠态 =
// 定高窗（恰 3 行）装尾部切片贴下沿；收束折叠 = 零视窗节点（只留标题行——高度归零靠「不
// 渲染节点」而非「height(0) 属性生效」，对任何状态机失灵 fail-safe）。
// 详情意愿读写 msg.detailExpanded（页面寿命，组件回收重建不丢）；
// 首次未初始化才取偏好缺省 getThinkExpandDefault()（默认偏好不算用户主动展开——不提升段意愿）。
@Component
struct ChatThinkingStep {
  @ObjectLink msg: ChatMessage;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅：渐隐起点 cardBg 显式传参，
  // 档位变化属性级刷新渐变层（起点随档、终点恒透）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 消息正文字体两键 @StorageProp 自订阅：思考过程段正文属消息内容，全跟随正文字体（字号
  // 不变——反推算式 charsPerLine 不随动，坑103 无涉）
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  // 详情开启上行（仅用户关→开时调用）
  onDetailOpened: () => void = (): void => {};
  // 内容区实测宽度（vp；onAreaChange 回写）——仅服务尾部切片的单行字数估算
  private textW: number = 0;
  // ── 流式计时（域内自足，不跨域拿数据、不动数据层）──
  // 状态最小化：唯一 @State = 已流逝整秒数（1s 粒度有界节流；tick 内临时算好后一次赋值）
  @State private thinkSeconds: number = 0;
  // interval 句柄（-1 = 未运行；setInterval↔clearInterval 成对释放，宪法内存防线）
  private timerId: number = -1;
  // 计时起点兜底：组件首挂时刻（msg.createdAt 缺失时用）
  private mountMs: number = 0;

  aboutToAppear(): void {
    // 详情意愿首次初始化（唯一写点；已明确 true/false 不被组件重建覆盖——msg 由数据源持有）
    if (this.msg.detailExpanded === undefined) {
      this.msg.detailExpanded = getThinkExpandDefault();
    }
    // 计时只在挂载时已流式的思考行启动（思考行创建即 streaming；回放行恒否——零 ticker）
    this.mountMs = Date.now();
    if (this.msg.streaming === true) {
      this.startThinkTimer();
    }
  }

  // 流束/卸载即停：interval 生命周期的两个清除点之一（另一个在 tick 自纠）
  aboutToDisappear(): void {
    this.stopThinkTimer();
  }

  // 计时起点优先消息 createdAt（毫秒，每 tick 重读；拍板「起点取既有 ChatMessage.createdAt」）。
  // 实时思考行由发送链继承轮起始时刻（见 ChatStreamFlowCtrl 建行处），故实际起点 = 轮起始
  //（距本轮发送的秒数；LazyForEach 回收重建不重起数）；createdAt 缺失（防御路径）才回落
  // 组件首挂时刻
  private thinkStartMs(): number {
    if (this.msg.createdAt !== undefined && this.msg.createdAt > 0) {
      return this.msg.createdAt;
    }
    return this.mountMs;
  }

  private elapsedSeconds(): number {
    return Math.max(0, Math.floor((Date.now() - this.thinkStartMs()) / 1000));
  }

  // 状态位文案：措辞与 ChatAnswerChoice.roundDurationSuffix「· X 秒」同风格同分隔符
  private statusText(): string {
    return '思考中 · ' + this.thinkSeconds + ' 秒';
  }

  private startThinkTimer(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.thinkSeconds = this.elapsedSeconds();
    this.timerId = setInterval((): void => {
      // 流束自纠：@ObjectLink 字段原地翻转无独立回调，tick 内自查即停（误差 ≤1s，且流束后
      // 状态位与折叠窗都已随重渲卸下，迟到的一拍不可见）
      if (this.msg.streaming !== true) {
        this.stopThinkTimer();
        return;
      }
      this.thinkSeconds = this.elapsedSeconds();
    }, 1000);
  }

  private stopThinkTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private detailExpanded(): boolean {
    return this.msg.detailExpanded === true;
  }

  // 正文字体家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // 单行字数估算：12fp 中文全角字宽 ≈ 字号；下限 8 防极端窄宽除出荒谬值
  private charsPerLine(): number {
    if (this.textW <= 0) {
      return THINK_TAIL_FALLBACK_CHARS;
    }
    const n: number = Math.floor(this.textW / THINK_FONT_SIZE);
    return n >= 8 ? n : THINK_TAIL_FALLBACK_CHARS;
  }

  private tailPreview(): string {
    return thinkTailSlice(this.msg.text, this.charsPerLine());
  }

  // 详情切换（用户意图单入口）：关→开先上行（宿主取消进页校正、提升段意愿），再写详情；
  // ★ 决明修正：关详情只收自身、不发任何上行——多步链内点单条思考
  // 只收自己，段展开态与「收起」键保持（要整段收回点键，收起 = 键清全部详情 + 段回自动）。
  // 段意愿与详情意愿同一次同步布局提交。★ 方向分流同段级：展开 200ms，收起直写（内容同帧
  // 卸载，插值只会留空盒）
  private toggleDetail(): void {
    const next: boolean = !this.detailExpanded();
    applyProcessPresentation(this.getUIContext(), (): void => {
      if (next) {
        this.onDetailOpened();
      }
      this.msg.detailExpanded = next;
    }, next);
  }

  // 内容区实测宽度回写（宽度只随屏宽/旋转变化，0.5vp 阈值去抖防重入）。
  // 正文列内距 = SEGMENT_BODY_PAD_L / SEGMENT_ROW_PAD_R 组合（卡体 padding 收 4、行内容补 4
  // 回添复位）——本估算式须按组合内距扣减，净文字宽与改前逐字等价；按旧式扣减会把估算宽多
  // 算 8vp（charsPerLine 高估约 1 字 ⇒ 尾部切片多取、最新段被 maxLines 省略号截尾——预览
  // 「末尾恒保留」契约受损）
  private onBodyArea(wVp: number): void {
    if (!Number.isFinite(wVp) || wVp <= 0) {
      return;
    }
    const textWidth: number = Math.max(0, wVp - SEGMENT_BODY_PAD_L - SEGMENT_ROW_PAD_R);
    if (Math.abs(textWidth - this.textW) < 0.5) {
      return;
    }
    this.textW = textWidth;
  }

  @Builder
  StatusSlot() {
    if (this.msg.streaming === true) {
      // 流式计时：实时秒数随 1s tick 走（RIK 阶段 B §4）；12fp 灰风格不变；字体随正文
      Text(this.statusText())
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
    }
  }

  build() {
    Column() {
      ChatStepTitleRow({
        title: '思考过程',
        // 有内容才可展开（空文本思考行理论上不产生——懒创建即带增量；防御性判据）
        expandable: this.msg.text !== '' || this.detailExpanded(),
        expanded: this.detailExpanded(),
        onToggle: (): void => {
          this.toggleDetail();
        },
        slot: (): void => {
          this.StatusSlot();
        }
      })
      // 结构化三态视窗：展开态优先（用户明确表达过要看，流末收口不强制收起）；生成中定高窗
      // 贴下沿；收束折叠零节点
      if (this.detailExpanded()) {
        Column() {
          Text(this.msg.text)
            .fontSize(THINK_FONT_SIZE)
            .fontColor(cardDescColor())
            .fontStyle(FontStyle.Italic)
            .lineHeight(THINK_LINE_HEIGHT)
            .fontFamily(this.resolveBodyFamily())
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R })
        .transition(TransitionEffect.IDENTITY)
      } else if (this.msg.streaming === true) {
        // 上端渐隐：定高窗外包一层 Stack，窗上沿叠「段卡底色→
        // 透明」渐变层——只隐最旧的可见行，最新内容贴下沿恒清晰；渐变层高度有界（恰 1 行）、
        // 不参与测量（窗体定高/clip/贴下沿全留在内容列），HitTestMode.None 不挡触摸。
        // 起点色与段卡实际底色同源（cardBg 单源函数——渐变与卡面同 token 深浅色一致）
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            Text(this.tailPreview())
              .fontSize(THINK_FONT_SIZE)
              .fontColor(cardDescColor())
              .fontStyle(FontStyle.Italic)
              .lineHeight(THINK_LINE_HEIGHT)
              .fontFamily(this.resolveBodyFamily())
              .width('100%')
              .maxLines(THINKING_COLLAPSED_LINES)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(THINK_BODY_COLLAPSED_H)
          .clip(true)
          // 贴下沿：预览态末段（最新思考）贴着窗口下沿出现
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R })
          // 上端渐隐层（Stack 上层）：angle 180 = 自上而下、offset 0 在窗顶——起点随档位
          // 半透明、终点恒透（起点 cardBg 传档位、终点 cardBgTransparent 单源函数——cardBg
          // 返回 8 位色串，禁 substring 私拼）
          Column() {
          }
          .width('100%')
          .height(THINK_FADE_HEIGHT)
          .linearGradient({
            angle: 180,
            colors: [[cardBg(this.appColorMode, this.cardAlphaLevel), 0], [cardBgTransparent(this.appColorMode), 1]]
          })
          .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        // 分支根自 Column 换 Stack，IDENTITY 随根走（折叠根显式退出契约，防默认 fade
        // 延留退出内容）
        .transition(TransitionEffect.IDENTITY)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 宽度回写（仅认宽度变化，高度变化零成本）
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.onBodyArea(newArea.width as number);
    })
  }
}
