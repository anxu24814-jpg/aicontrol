/** Text/Span/ImageSpan 原生混排。资源事件携不可变身份，外链与文内跳转分别准入。 */
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { MarkdownDocumentToken, nextMarkdownBindingId } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode, markdownNode } from '../../../common/markdown/MarkdownSemanticModel';
// DS 来源角标（S3③）：区间表类型自视图模型单源引入
import { DsCitationSpan } from '../ChatMessageCompose';
import { MarkdownInlineRun, markdownInlineRuns, markdownSafeRemoteUrl, markdownLaunchTarget }
  from '../../../common/markdown/MarkdownRenderProjection';
import { launchExternalLink } from '../../../common/ExternalLink';
import { MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT } from '../../../common/markdown/MarkdownPresentation';
import { FONT_FAMILY_MONO, FONT_FAMILY_SYSTEM } from '../../../common/ChatFont';
import { badgeBg, cardTitleColor, usageAccentColor } from '../../../common/Theme';
import { MarkdownMath, MarkdownMathImage } from './MarkdownMath';
import { MATH_INLINE_FONT_SCALE, mathResourceKey } from '../../../common/markdown/MathRenderPolicy';
import { mathRenderService } from './MathRenderService';
import { MarkdownPreview } from './MarkdownPreview';
import { MarkdownImageCover } from './MarkdownImageCover';

interface MarkdownInlineImageState {
  key: string;
  state: string;
  height: number;
}
// cacheKey = 父侧预填借用的缓存键（null = 无借用；mathStates 身份键仍是 resource.key，
// 两套键正交）——过滤丢弃与组件离场时据此成对归还借用（成对释放红线）。
interface MarkdownInlineMathState {
  key: string;
  value: MarkdownMathImage | null;
  error: string;
  cacheKey: string | null;
}
interface MarkdownInlineCover {
  session: string;
  resource: MarkdownInlineResource;
}
interface MarkdownInlineResource {
  key: string;
  node: MarkdownNode;
  token: MarkdownDocumentToken;
  requestId: string;
}

// ——行内图片盒形制单源（占位盒与成图盒同尺寸预留）：盒宽恒定、占位高恒 90——落图只按
// 宽高比在 20~160 内填充高度、不改写盒宽，防二次跳变；改任一值须同步三处状态写点
//（imageState 默认 / imageComplete 无效支 / imageError）。
const INLINE_IMAGE_WIDTH: number = 120;
const INLINE_IMAGE_PLACEHOLDER_HEIGHT: number = 90;
// 图片圆角 8vp。borderRadius 对 ImageSpan 走 CommonMethod 扩展面（查证门已过）；真机验收
// 须实测其裁内容与否——若不裁则在下述挂点位补 .clip(true) 同测（BLOCKED 真机验收登记项）。
// 公式 ImageSpan 不挂圆角（会裁字形）。
const INLINE_IMAGE_RADIUS: number = 8;

// ── 行内超宽公式提升独立行内块容器 ──
// 官方能力面：Text 子组件封闭白名单、Span/ImageSpan 无滚动族——行内公式无法自带滚动容器，
// 唯一正解 = 超宽时提升为独立一行横向 Scroll（块级公式容器即形态先例）。判宽 = 位图宽超
// 容器内容宽 − 本余量（2~4vp 防临界抖动）；**流式在途不做提升切换**（「文字不抽搐」红线），
// 终态一次性评估定格。
const INLINE_MATH_HOIST_MARGIN_VP: number = 4;

// 段落渲染段（切分口径）：连续非提升 run 归并为一个文本段，每个提升公式单独成行。
// key 覆盖段内全部可变展示成分（键纪律：文本段 = 段起点 run 键 + 段长；公式段 = 资源键）——
// 键变即行重建，行内文本随流式增长经段内 Repeat 既有逐拍通道刷新。
interface MarkdownInlineSegment {
  key: string;
  start: number;
  end: number;
  math: MarkdownNode | null;
}

@ComponentV2
export struct MarkdownInlineView {
  @Param nodes: MarkdownNode[] = [];
  @Param source: string = '';
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  // 默认参即正文排印单源（16/24）；标题经 BlockView 显式传参覆盖，表格单元格吃默认参。
  @Param fontSize: number = MARKDOWN_BODY_FONT_SIZE;
  @Param lineHeight: number = MARKDOWN_BODY_LINE_HEIGHT;
  @Param bold: boolean = false;
  @Param quoted: boolean = false;
  // taskDone = 处于已勾选任务项的内容树内（BlockView 下行旗标）：勾选态增强——
  // run 级删除线 + 整段 0.75 不透明度
  @Param taskDone: boolean = false;
  @Param compact: boolean = false;
  @Param textAlign: TextAlign = TextAlign.Start;
  // 消息字体家族串：正文/行内代码分水岭 = StyledSpan 的 run.code 二元选择——普通 run 取
  // 正文字体、code run 取代码字体；未设 family 的附属 Span 与容器 Text 统一挂正文字体
  //（Span 继承父 Text 八属性，官方语义）
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  // 流式态标量：live 真 = 本正文仍在流式输出——超宽行内公式不做行内↔独立行
  // 提升切换（「文字不抽搐」红线），终态一次性定格；缺省 false = 非流式旁路消费点零改动
  // 即定格。单源 = ChatMarkdownBody。
  @Param live: boolean = false;
  // DS 来源角标（S3③，可选——缺省空数组零渲染零行为变化）：UTF-16 码元区间 + 来源卡序号
  //（换算单源 = ChatMessageCompose.dsCitationSpansOf）。锚定 = 覆盖引用区间的叶 run（源
  // 区间相交取文档序最后命中——区间终点侧）；角标渲染为上标序号 Span，点击上行序号，
  // 宿主换算 M1 来源卡行锚点走既有滚动链
  @Param citations: DsCitationSpan[] = [];
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  @Event onCitationTap: (entry: number) => void = (_entry: number): void => {};
  @Local private mountKey: string = '';
  @Local private imageStates: MarkdownInlineImageState[] = [];
  @Local private imageRequests: MarkdownInlineResource[] = [];
  @Local private mathRequests: MarkdownInlineResource[] = [];
  @Local private mathStates: MarkdownInlineMathState[] = [];
  @Local private imageCovers: MarkdownInlineCover[] = [];
  // 容器内容宽实测（判宽基准）：根 Column onAreaChange 回写（等值守卫——流式增长
  // 期布局回调不产状态写）。消费面 = @Computed segments 的判宽读（宽变即段表与行键整体
  // 刷新，宽本身不复进任何行键）。
  @Local private containerWidth: number = 0;
  private alive: boolean = false;
  private lifecycle: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.lifecycle++;
    this.mountKey = nextMarkdownBindingId();
    this.imageStates = [];
    this.mathStates = [];
    this.imageCovers = [];
    this.imageRequests = [];
    this.mathRequests = [];
    this.syncResources();
  }
  aboutToDisappear(): void {
    this.alive = false;
    this.lifecycle++;
    // 父侧借用归还（预填登记的 cacheKey；owner 侧借用由其自身 aboutToDisappear 归还，
    // 两计数独立累加独立归还）——成对释放红线。
    for (const state of this.mathStates) {
      if (state.cacheKey !== null) {
        mathRenderService.release(state.cacheKey);
      }
    }
  }

  @Computed
  get runs(): MarkdownInlineRun[] { return markdownInlineRuns(this.nodes); }

  private resourceKey(node: MarkdownNode): string {
    return this.mountKey + '/' + this.token.documentId.length.toString() + ':' + this.token.documentId + '/' +
      this.token.generation.toString() + '/' + node.id.toString() + '/' +
      (node.kind === 'image' ? node.destination : node.kind + '/' + node.closed.toString() + '/' + node.text + '/' + this.darkMode.toString() + '/' + this.fontSize.toString());
  }

  private resource(node: MarkdownNode): MarkdownInlineResource {
    return { key: this.resourceKey(node), node: node, requestId: nextMarkdownBindingId(), token: {
      documentId: this.token.documentId, generation: this.token.generation, revision: this.token.revision } };
  }

  // ── 行内超宽公式提升 ──
  // 容器内容宽回写：API 26 重载显式传 expectedUpdateInterval（1000ms 档，防隐式依赖；流式
  // 期高度增长的回调被节流）；等值守卫（<0.5vp 视为同宽）防状态写噪声。
  private measureContainer(area: Area): void {
    const width: number = area.width as number;
    if (!Number.isFinite(width) || width <= 0) { return; }
    if (Math.abs(width - this.containerWidth) < 0.5) { return; }
    this.containerWidth = width;
  }

  // 提升判据（无副作用）：终态（live 假——流式在途恒不提升，防重排抽搐）+ 公式位图已定稿
  // 在场 + 位图宽超容器内容宽 − 余量。失败/未闭合/加载中（value 为 null）恒不提升（照常
  // 走源码与状态文案兜底）。
  private hoistedMath(node: MarkdownNode): boolean {
    if (this.live || this.containerWidth <= 0) { return false; }
    const surface: MarkdownMathImage | null = this.mathState(node).value;
    return surface !== null && surface.width > this.containerWidth - INLINE_MATH_HOIST_MARGIN_VP;
  }

  private textSegment(runs: MarkdownInlineRun[], start: number, end: number): MarkdownInlineSegment {
    // 键 = 段起点 run 身份（runKey = id:绝对下标）+ 段长：段边界任一变化即换键重建行，
    // 行内值参（start/end）与键同源——键不变则参数不变，值参冻结面无害。
    return { key: this.runKey(runs[start], start) + '/' + (end - start).toString(),
      start: start, end: end, math: null };
  }

  // ── DS 来源角标（S3③）──
  // 段内叶节点收集（与 appendInlineRuns 同构判据：有子节点且非 image 的容器递归，其余为叶
  //——run.id 即叶节点 id）
  private collectLeafNodes(nodes: MarkdownNode[], out: MarkdownNode[]): void {
    for (const node of nodes) {
      if (node.children.length > 0 && node.kind !== 'image') {
        this.collectLeafNodes(node.children, out);
      } else {
        out.push(node);
      }
    }
  }

  // run 叶 id → 角标序号表（@Computed 缓存——citations/nodes 不变即不重算；citations 空 =
  // 空表零成本）。锚定 = 与引用源区间相交的叶 run 取文档序最后命中（区间终点侧），区间落
  // 在纯标记符内回落段内最后一个叶 run，无叶跳过。
  // ★ 2026-11-14 自检轮修：citations 全量下传给**每个**行内视图（段落/标题/表格单元），
  // 「无相交即回落末叶」会让每个不在本文块内的引用都挂到本块尾部 ⇒ 全文到处冒出角标。
  // 归属判据 = 引用区间**起点**落在本视图区间内（同一注跨段时只在起笔块出一次，不重复）；
  // 只有「起点在本块但落在纯标记符之间」才回落末叶（原意图）。
  @Computed
  get citationByRun(): Map<number, number[]> {
    const byRun: Map<number, number[]> = new Map<number, number[]>();
    if (this.citations.length === 0 || this.nodes.length === 0) {
      return byRun;
    }
    const leaves: MarkdownNode[] = [];
    this.collectLeafNodes(this.nodes, leaves);
    if (leaves.length === 0) {
      return byRun;
    }
    // 本视图总区间（节点 range 为文档绝对坐标）——判定注区间是否属于本块的最小依据
    let viewStart: number = leaves[0].range.start;
    let viewEnd: number = leaves[0].range.end;
    for (const leaf of leaves) {
      if (leaf.range.start < viewStart) {
        viewStart = leaf.range.start;
      }
      if (leaf.range.end > viewEnd) {
        viewEnd = leaf.range.end;
      }
    }
    for (const span of this.citations) {
      if (span.start < viewStart || span.start >= viewEnd) {
        continue; // 起笔不在本块（防每块尾部误挂 + 跨段重复——见函数头修订注释）
      }
      let anchor: MarkdownNode | null = null;
      for (const leaf of leaves) {
        if (leaf.range.start < span.end && leaf.range.end > span.start) {
          anchor = leaf;
        }
      }
      if (anchor === null) {
        anchor = leaves[leaves.length - 1];
      }
      const list: number[] | undefined = byRun.get(anchor.id);
      if (list === undefined) {
        byRun.set(anchor.id, [span.entry]);
      } else if (list.indexOf(span.entry) < 0) {
        // 同一 run 同一来源重复引用只出一个号（ForEach 键 = 序号串，重复键会被引擎丢弃并告警）
        list.push(span.entry);
      }
    }
    return byRun;
  }

  // 入参必须是 run 叶节点 id、禁数组下标：本函数在 CitationMarkers 的 ForEach 数据表达式
  // 里求值，该更新闭包跨帧持久，流式重解析使 runs 合并/平移的瞬间旧下标即越界
  //（2026-11-15 闪退栈 = this.runs[runIndex].id 读 undefined）；叶节点 id 是稳定身份且与
  // citationByRun 的键同源，重解析后查空即零角标、行重建后自愈。
  private citationNumbersForRun(runId: number): number[] {
    const list: number[] | undefined = this.citationByRun.get(runId);
    return list !== undefined ? list : [];
  }

  // 角标标记（上标序号 Span，形制照 script run：字号 ×0.72 + 基线抬升 0.25×字号；色 =
  // usageAccentColor 与文内链接同源）。样式不驱布局变化只增可见符号，流式期 citations 恒
  // 空零行渲染；入参传 run 叶 id 而非下标的原因见 citationNumbersForRun 头注释
  @Builder
  CitationMarkers(runId: number) {
    ForEach(this.citationNumbersForRun(runId), (entry: number) => {
      Span(entry.toString())
        .fontSize(this.fontSize * 0.72)
        .fontColor(usageAccentColor(this.colorMode()))
        .baselineOffset(LengthMetrics.fp(this.fontSize * 0.25))
        .onClick((): void => {
          this.onCitationTap(entry);
        })
    }, (entry: number): string => entry.toString())
  }

  // 段落渲染段序列：连续非提升 run 归并文本段、每个提升公式单独成段。无提升时恒为单文本段
  //（Repeat 行直挂外层 Column，节点树与现状一致）；有提升时公式段独占一行横向 Scroll。
  @Computed
  get segments(): MarkdownInlineSegment[] {
    const runs: MarkdownInlineRun[] = this.runs;
    const result: MarkdownInlineSegment[] = [];
    let start: number = 0;
    for (let index: number = 0; index < runs.length; index++) {
      const node: MarkdownNode | null = runs[index].math;
      if (node === null || !this.hoistedMath(node)) { continue; }
      if (index > start) { result.push(this.textSegment(runs, start, index)); }
      result.push({ key: this.resourceKey(node), start: index, end: index + 1, math: node });
      start = index + 1;
    }
    if (start < runs.length) { result.push(this.textSegment(runs, start, runs.length)); }
    return result;
  }

  @Computed
  get mathResources(): MarkdownInlineResource[] {
    return this.mathRequests.filter((resource: MarkdownInlineResource): boolean =>
      this.runs.some((run: MarkdownInlineRun): boolean => run.math !== null && this.resourceKey(run.math) === resource.key));
  }

  @Computed
  get htmlNodes(): MarkdownNode[] {
    if (!this.runs.some((run: MarkdownInlineRun): boolean => run.html !== null) || this.nodes.length === 0) { return []; }
    const start: number = this.nodes[0].range.start;
    const end: number = this.nodes[this.nodes.length - 1].range.end;
    const node: MarkdownNode = markdownNode('htmlInline', start, end);
    node.id = this.nodes[0].id;
    // 开闭HTML标签是不同语义叶子，整段源片才能保留其中的文本与结构，不给每个空标签单开预览。
    node.text = start >= 0 && end <= this.source.length ? this.source.substring(start, end) :
      this.runs.map((run: MarkdownInlineRun): string => run.text).join('');
    return [node];
  }

  @Monitor('nodes', 'token', 'darkMode', 'fontSize')
  private syncResources(): void {
    if (!this.alive) { return; }
    const nextImages: MarkdownInlineResource[] = [];
    const nextMath: MarkdownInlineResource[] = [];
    for (const run of this.runs) {
      const node: MarkdownNode | null = run.image !== null ? run.image : run.math;
      if (node === null) { continue; }
      const previous: MarkdownInlineResource[] = run.image !== null ? this.imageRequests : this.mathRequests;
      const key: string = this.resourceKey(node);
      const resource: MarkdownInlineResource = previous.find((item: MarkdownInlineResource): boolean => item.key === key) ??
        this.resource(node);
      if (run.image !== null) { nextImages.push(resource); } else { nextMath.push(resource); }
    }
    this.imageRequests = nextImages;
    this.mathRequests = nextMath;
    const imageKeys: string[] = nextImages.map((resource: MarkdownInlineResource): string => resource.key);
    const mathKeys: string[] = nextMath.map((resource: MarkdownInlineResource): string => resource.key);
    this.imageStates = this.imageStates.filter((state: MarkdownInlineImageState): boolean => imageKeys.indexOf(state.key) >= 0);
    // 被过滤丢弃的 math 状态若挂父侧借用（预填登记），先归还再丢弃——成对释放红线。
    for (const state of this.mathStates) {
      if (state.cacheKey !== null && mathKeys.indexOf(state.key) < 0) {
        mathRenderService.release(state.cacheKey);
      }
    }
    this.mathStates = this.mathStates.filter((state: MarkdownInlineMathState): boolean => mathKeys.indexOf(state.key) >= 0);
    this.imageCovers = this.imageCovers.filter((cover: MarkdownInlineCover): boolean => nextImages.indexOf(cover.resource) >= 0);
    // 公式缓存预填（进会同步命中）：对 value 为空且无错误的 math 资源预查缓存，命中即当帧
    // 出图（owner 挂载后的回调重写同值，冗余无害）。@Local 初始化器里查缓存不可行（先于
    // @Param 注入）；循环先算后一次性赋值——状态最小化红线。
    const primed: MarkdownInlineMathState[] = [];
    const fontPixels: number = this.getUIContext().fp2px(this.fontSize * MATH_INLINE_FONT_SCALE);
    const pixelToVp: number = this.getUIContext().px2vp(1);
    for (const resource of this.mathRequests) {
      const state: MarkdownInlineMathState = this.mathState(resource.node);
      if (state.value !== null || state.error !== '') {
        continue;
      }
      const key: string = mathResourceKey(resource.node.text, fontPixels, this.darkMode, pixelToVp);
      const hit: MarkdownMathImage | null = mathRenderService.lookup(key);
      if (hit === null) {
        continue;
      }
      mathRenderService.acquire(key);
      primed.push({ key: resource.key, value: hit, error: '', cacheKey: key });
    }
    if (primed.length > 0) {
      const primedKeys: Set<string> = new Set<string>(
        primed.map((state: MarkdownInlineMathState): string => state.key));
      this.mathStates = this.mathStates.filter((state: MarkdownInlineMathState): boolean =>
        !primedKeys.has(state.key)).concat(primed);
    }
  }

  private accepts(resource: MarkdownInlineResource, kind: string): boolean {
    return this.alive && (kind === 'image' ? this.imageRequests : this.mathRequests).indexOf(resource) >= 0 &&
      this.token.documentId === resource.token.documentId &&
      this.token.generation === resource.token.generation && this.token.revision >= resource.token.revision &&
      this.runs.some((run: MarkdownInlineRun): boolean => {
        const node: MarkdownNode | null = kind === 'image' ? run.image : run.math;
        return node !== null && this.resourceKey(node) === resource.key;
      });
  }

  private imageResources(node: MarkdownNode): MarkdownInlineResource[] {
    const key: string = this.resourceKey(node);
    return this.imageRequests.filter((resource: MarkdownInlineResource): boolean => resource.key === key);
  }

  private mathResourcesFor(node: MarkdownNode): MarkdownInlineResource[] {
    const key: string = this.resourceKey(node);
    return this.mathRequests.filter((resource: MarkdownInlineResource): boolean => resource.key === key);
  }

  private imageState(node: MarkdownNode): MarkdownInlineImageState {
    const key: string = this.resourceKey(node);
    return this.imageStates.find((state: MarkdownInlineImageState): boolean => state.key === key) ??
      { key: key, state: 'loading', height: INLINE_IMAGE_PLACEHOLDER_HEIGHT };
  }

  private imageComplete(resource: MarkdownInlineResource, event: ImageLoadResult): void {
    if (!this.accepts(resource, 'image') || event.loadingStatus !== 1) { return; }
    const valid: boolean = Number.isFinite(event.width) && Number.isFinite(event.height) && event.width > 0 && event.height > 0;
    this.imageStates = this.imageStates.filter((state: MarkdownInlineImageState): boolean => state.key !== resource.key)
      .concat([{ key: resource.key, state: valid ? 'loaded' : 'failed',
        height: valid ? Math.max(20, Math.min(160, INLINE_IMAGE_WIDTH * event.height / event.width)) :
          INLINE_IMAGE_PLACEHOLDER_HEIGHT }]);
  }

  private imageError(resource: MarkdownInlineResource): void {
    if (!this.accepts(resource, 'image')) { return; }
    this.imageStates = this.imageStates.filter((state: MarkdownInlineImageState): boolean => state.key !== resource.key)
      .concat([{ key: resource.key, state: 'failed', height: INLINE_IMAGE_PLACEHOLDER_HEIGHT }]);
  }

  private mathState(node: MarkdownNode): MarkdownInlineMathState {
    const key: string = this.resourceKey(node);
    return this.mathStates.find((state: MarkdownInlineMathState): boolean => state.key === key) ??
      { key: key, value: null, error: '', cacheKey: null };
  }

  private acceptMath(resource: MarkdownInlineResource, value: MarkdownMathImage | null, error: string): void {
    if (!this.accepts(resource, 'math')) { return; }
    // 重写状态继承既有父侧借用登记（预填 cacheKey 不随 owner 回调重写丢失——过滤与离场
    // 的归还据此成对）。
    const previous: MarkdownInlineMathState = this.mathState(resource.node);
    this.mathStates = this.mathStates.filter((state: MarkdownInlineMathState): boolean => state.key !== resource.key)
      .concat([{ key: resource.key, value: value, error: error, cacheKey: previous.cacheKey }]);
  }

  private mathDisplayFailed(resource: MarkdownInlineResource, surface: MarkdownMathImage): void {
    if (this.accepts(resource, 'math') && this.mathState(resource.node).value === surface) {
      this.acceptMath(resource, null, '公式图片显示失败。已保留源码');
    }
  }

  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  private spanSize(run: MarkdownInlineRun): number {
    return run.script !== 0 ? this.fontSize * 0.72 : run.code ? this.fontSize - 1 : this.fontSize;
  }
  private runKey(run: MarkdownInlineRun, index: number): string { return run.id.toString() + ':' + index.toString(); }
  private clickable(destination: string): boolean {
    return destination.startsWith('#') || destination.startsWith('reference:') ||
      markdownLaunchTarget(destination) !== '';
  }
  private sameToken(token: MarkdownDocumentToken): boolean {
    return this.token.documentId === token.documentId && this.token.generation === token.generation &&
      this.token.revision === token.revision;
  }
  private linkFailure(token: MarkdownDocumentToken, lifecycle: number): void {
    if (!this.alive || this.lifecycle !== lifecycle || !this.sameToken(token)) { return; }
    this.getUIContext().getPromptAction().showToast({
      message: '无法打开链接。可能未安装对应应用，可以从消息全文复制地址' });
  }
  private openLink(raw: string): void {
    if (!this.alive) { return; }
    if (raw.startsWith('#') || raw.startsWith('reference:')) { this.onNavigate(raw); return; }
    const url: string = markdownLaunchTarget(raw);
    if (url === '') { return; }
    const token: MarkdownDocumentToken = {
      documentId: this.token.documentId, generation: this.token.generation, revision: this.token.revision };
    const lifecycle: number = this.lifecycle;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, url, (): void => { this.linkFailure(token, lifecycle); });
    } catch (error) { this.linkFailure(token, lifecycle); }
  }

  @Builder
  StyledSpan(row: RepeatItem<string>) {
    Span(this.runs[row.index].text)
      .fontSize(this.spanSize(this.runs[row.index]))
      .fontColor(this.clickable(this.runs[row.index].destination) ? usageAccentColor(this.colorMode()) : cardTitleColor())
      .fontWeight(this.bold || this.runs[row.index].bold ? FontWeight.Bold : FontWeight.Normal)
      .fontStyle(this.runs[row.index].italic || this.quoted ? FontStyle.Italic : FontStyle.Normal)
      .fontFamily(this.runs[row.index].code ? this.codeFontFamily : this.bodyFontFamily)
      // 删除线：run 自身 strikethrough 或已勾选任务项内容（taskDone 旗标）均着删除线
      .decoration({ type: this.runs[row.index].strike || this.taskDone ? TextDecorationType.LineThrough : TextDecorationType.None })
      // ==高亮== mark 底：官方文本高亮背景系统色（ohos_id_color_text_highlight_bg，
      // 官方选中文本同款伴随色；口径 = 官方强调色系正色取官方 token）；code 灰底优先。
      .textBackgroundStyle({ color: this.runs[row.index].code ? badgeBg(this.colorMode()) :
        this.runs[row.index].mark ? $r('sys.color.ohos_id_color_text_highlight_bg') : Color.Transparent })
      .baselineOffset(LengthMetrics.fp(this.runs[row.index].script * this.fontSize * 0.25))
      .onClick(this.clickable(this.runs[row.index].destination) ? (): void => {
        this.openLink(this.runs[row.index].destination);
      } : undefined)
  }

  // 文本段渲染：现状单 Text 体逐字迁移，run 读取按下标偏移（start + row.index）。
  // 值参（start/end）与段键同源（段起点 run 键 + 段长在键中），键变即行重建、参数随新行刷新。
  @Builder
  TextRuns(start: number, end: number) {
    Text() {
      Repeat<string>(this.runs.slice(start, end).map((run: MarkdownInlineRun, index: number): string =>
        this.runKey(run, start + index)))
        .each((row: RepeatItem<string>) => {
          if (this.runs[start + row.index].image !== null) {
            if (markdownSafeRemoteUrl(this.runs[start + row.index].image!.destination) !== '' &&
              this.imageState(this.runs[start + row.index].image!).state !== 'failed') {
              ForEach(this.imageResources(this.runs[start + row.index].image!), (resource: MarkdownInlineResource) => {
                ImageSpan(resource.node.destination)
                  .width(INLINE_IMAGE_WIDTH).height(this.imageState(resource.node).height)
                  .objectFit(ImageFit.Contain).verticalAlign(ImageSpanAlignment.CENTER)
                  // 图片圆角（真机若不裁内容则此位补 .clip(true) 同测，见常量区注释）
                  .borderRadius(INLINE_IMAGE_RADIUS)
                  .onComplete((event: ImageLoadResult): void => { this.imageComplete(resource, event); })
                  .onError((): void => { this.imageError(resource); })
                  .onClick((): void => {
                    // 重入守卫独立成行（与完整阅读/受限预览宿主开守卫同形；离场动效在途期
                    // imageCovers 未清，本行与 onClosed 上行清空联合构成结构式关闭-再开协调，
                    // 见 assert-ui-shape ephemeral 判据）。
                    if (this.imageCovers.length > 0) { return; }
                    if (this.accepts(resource, 'image')) {
                      this.imageCovers = [{ session: nextMarkdownBindingId(), resource: resource }];
                    }
                  })
              }, (resource: MarkdownInlineResource): string => resource.requestId)
            }
            if (markdownSafeRemoteUrl(this.runs[start + row.index].image!.destination) === '' ||
              this.imageState(this.runs[start + row.index].image!).state !== 'loaded') {
              Span(' [' + (this.runs[start + row.index].image!.text || '图片') + '] ' + this.runs[start + row.index].image!.destination + ' ')
                .fontSize(this.fontSize).fontColor(cardTitleColor())
            }
            if (this.runs[start + row.index].destination !== '') {
              Span(' 打开图片链接 ')
                .fontSize(13).fontColor(usageAccentColor(this.colorMode()))
                .onClick((): void => { this.openLink(this.runs[start + row.index].destination); })
            }
          } else if (this.runs[start + row.index].math !== null &&
            this.mathState(this.runs[start + row.index].math!).value !== null) {
            ForEach(this.mathResourcesFor(this.runs[start + row.index].math!), (resource: MarkdownInlineResource) => {
              ForEach([this.mathState(resource.node).value!], (surface: MarkdownMathImage) => {
                ImageSpan(surface.pixelMap)
                  .width(surface.width).height(surface.height)
                  .objectFit(ImageFit.Contain)
                  // 基线校准：公式底部坐文字基线（CENTER 在式高接近行高时视觉下沉）；含公式
                  // 段行高恒定、不随公式在场切换（切换 = 落图行高跳变）。
                  .verticalAlign(ImageSpanAlignment.BASELINE)
                  .onError((): void => { this.mathDisplayFailed(resource, surface); })
              }, (_surface: MarkdownMathImage): string => resource.key)
            }, (resource: MarkdownInlineResource): string => resource.requestId)
          } else {
            // StyledSpan 按行下标读当前 runs：本路径行号为段内相对，构造绝对下标行对象
            //（item 值不被消费，仅承载下标——与快路径 RepeatItem 同形同读点）。
            this.StyledSpan({ item: this.runKey(this.runs[start + row.index], start + row.index),
              index: start + row.index })
            this.CitationMarkers(this.runs[start + row.index].id)
            if (this.runs[start + row.index].math !== null &&
              this.mathState(this.runs[start + row.index].math!).error !== '') {
              Span(' ' + this.mathState(this.runs[start + row.index].math!).error + ' ')
                .fontSize(12).fontColor($r('sys.color.font_secondary'))
            }
          }
        })
        .key((key: string): string => key)
    }
    .fontSize(this.fontSize).lineHeight(this.lineHeight).fontColor(cardTitleColor())
    .fontFamily(this.bodyFontFamily)
    .fontWeight(this.bold ? FontWeight.Bold : FontWeight.Normal).textAlign(this.textAlign)
    // 已勾选任务项内容整体降不透明度至 0.75（勾选态增强；渲染域属性不触布局）
    .opacity(this.taskDone ? 0.75 : 1)
    .copyOption(CopyOptions.None).width(this.compact ? undefined : '100%')
  }

  // 提升行：超宽行内公式的独立一行横向 Scroll——容器参数照块级公式横滚先例
  //（Spring 回弹 + scrollBar Off + alwaysEnabled）；位图所有权仍归 MarkdownMath 资源
  // owner，本行只借用 PixelMap（onImage(null) 时随 mathState 退场）。
  @Builder
  MathHoistRow(node: MarkdownNode) {
    Scroll() {
      Row() {
        ForEach(this.mathResourcesFor(node), (resource: MarkdownInlineResource) => {
          ForEach([this.mathState(resource.node).value!], (surface: MarkdownMathImage) => {
            Image(surface.pixelMap)
              .width(surface.width).height(surface.height)
              .objectFit(ImageFit.Contain)
              .copyOption(CopyOptions.None)
              .accessibilityText(resource.node.text)
              .onError((): void => { this.mathDisplayFailed(resource, surface); })
          }, (_surface: MarkdownMathImage): string => resource.key)
        }, (resource: MarkdownInlineResource): string => resource.requestId)
      }
    }
    .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  // 提升激活判据：段表非单文本段即命中（单段且为公式 = 全段一超宽公式）。
  private hoistActive(): boolean {
    const segments: MarkdownInlineSegment[] = this.segments;
    return segments.length > 1 || (segments.length === 1 && segments[0].math !== null);
  }

  build() {
    Column({ space: 4 }) {
      if (this.hoistActive()) {
        // 提升路径（仅终态定格后进入）：超宽公式独占一行横向 Scroll、文本按段归并；
        // 段行直挂本 Column，段间沿用 4vp 节奏。段键含全部可变展示成分，边界变化逐行重建。
        Repeat<string>(this.segments.map((segment: MarkdownInlineSegment): string => segment.key))
          .each((row: RepeatItem<string>) => {
            if (this.segments[row.index].math !== null) {
              this.MathHoistRow(this.segments[row.index].math!)
            } else {
              this.TextRuns(this.segments[row.index].start, this.segments[row.index].end)
            }
          })
          .key((key: string): string => key)
      } else {
        // 常规路径（流式全程与无超宽公式的终态）：单 Text 全 run 原生混排，结构零变化。
        Text() {
          Repeat<string>(this.runs.map((run: MarkdownInlineRun, index: number): string => this.runKey(run, index)))
            .each((row: RepeatItem<string>) => {
              if (this.runs[row.index].image !== null) {
                if (markdownSafeRemoteUrl(this.runs[row.index].image!.destination) !== '' &&
                  this.imageState(this.runs[row.index].image!).state !== 'failed') {
                  ForEach(this.imageResources(this.runs[row.index].image!), (resource: MarkdownInlineResource) => {
                    ImageSpan(resource.node.destination)
                      .width(INLINE_IMAGE_WIDTH).height(this.imageState(resource.node).height)
                      .objectFit(ImageFit.Contain).verticalAlign(ImageSpanAlignment.CENTER)
                      // 图片圆角（真机若不裁内容则此位补 .clip(true) 同测，见常量区注释）
                      .borderRadius(INLINE_IMAGE_RADIUS)
                      .onComplete((event: ImageLoadResult): void => { this.imageComplete(resource, event); })
                      .onError((): void => { this.imageError(resource); })
                      .onClick((): void => {
                        // 重入守卫独立成行（同上：结构式关闭-再开协调守卫件）。
                        if (this.imageCovers.length > 0) { return; }
                        if (this.accepts(resource, 'image')) {
                          this.imageCovers = [{ session: nextMarkdownBindingId(), resource: resource }];
                        }
                      })
                  }, (resource: MarkdownInlineResource): string => resource.requestId)
                }
                if (markdownSafeRemoteUrl(this.runs[row.index].image!.destination) === '' ||
                  this.imageState(this.runs[row.index].image!).state !== 'loaded') {
                  Span(' [' + (this.runs[row.index].image!.text || '图片') + '] ' + this.runs[row.index].image!.destination + ' ')
                    .fontSize(this.fontSize).fontColor(cardTitleColor())
                }
                if (this.runs[row.index].destination !== '') {
                  Span(' 打开图片链接 ')
                    .fontSize(13).fontColor(usageAccentColor(this.colorMode()))
                    .onClick((): void => { this.openLink(this.runs[row.index].destination); })
                }
              } else if (this.runs[row.index].math !== null && this.mathState(this.runs[row.index].math!).value !== null) {
                ForEach(this.mathResourcesFor(this.runs[row.index].math!), (resource: MarkdownInlineResource) => {
                  ForEach([this.mathState(resource.node).value!], (surface: MarkdownMathImage) => {
                    ImageSpan(surface.pixelMap)
                      .width(surface.width).height(surface.height)
                      .objectFit(ImageFit.Contain)
                      // 基线校准（见 TextRuns 同款注释）：公式底部坐文字基线，行高不随公式在场切换。
                      .verticalAlign(ImageSpanAlignment.BASELINE)
                      .onError((): void => { this.mathDisplayFailed(resource, surface); })
                  }, (_surface: MarkdownMathImage): string => resource.key)
                }, (resource: MarkdownInlineResource): string => resource.requestId)
              } else {
                this.StyledSpan(row)
                this.CitationMarkers(this.runs[row.index].id)
                if (this.runs[row.index].math !== null && this.mathState(this.runs[row.index].math!).error !== '') {
                  Span(' ' + this.mathState(this.runs[row.index].math!).error + ' ')
                    .fontSize(12).fontColor($r('sys.color.font_secondary'))
                }
              }
            })
            .key((key: string): string => key)
        }
        .fontSize(this.fontSize).lineHeight(this.lineHeight).fontColor(cardTitleColor())
        .fontFamily(this.bodyFontFamily)
        .fontWeight(this.bold ? FontWeight.Bold : FontWeight.Normal).textAlign(this.textAlign)
        // 已勾选任务项内容整体降不透明度至 0.75（勾选态增强；渲染域属性不触布局）
        .opacity(this.taskDone ? 0.75 : 1)
        .copyOption(CopyOptions.None).width(this.compact ? undefined : '100%')
      }
      ForEach(this.mathResources, (resource: MarkdownInlineResource) => {
        MarkdownMath({ node: resource.node, token: this.token, darkMode: this.darkMode,
          fontSize: this.fontSize, inlineOutput: true,
          onImage: (value: MarkdownMathImage | null): void => { this.acceptMath(resource, value, ''); },
          onFailure: (message: string): void => {
            this.acceptMath(resource, message === '' ? this.mathState(resource.node).value : null, message);
          } })
      }, (resource: MarkdownInlineResource): string => resource.requestId)
      Repeat<number>(this.htmlNodes.map((node: MarkdownNode): number => node.id))
        .each((row: RepeatItem<number>) => {
          MarkdownPreview({ node: this.htmlNodes[row.index], token: this.token, darkMode: this.darkMode,
            codeFontFamily: this.codeFontFamily })
        })
        .key((id: number): string => id.toString())
      ForEach(this.imageCovers, (cover: MarkdownInlineCover) => {
        MarkdownImageCover({ node: cover.resource.node, token: cover.resource.token, darkMode: this.darkMode,
          onClosed: (): void => {
            if (this.alive && this.imageCovers.length > 0 && this.imageCovers[0] === cover) { this.imageCovers = []; }
          } })
      }, (cover: MarkdownInlineCover): string => cover.session)
    }
    .width(this.compact ? undefined : '100%').alignItems(HorizontalAlign.Start)
    // 容器内容宽实测（判宽基准与 API 26 节流重载见 measureContainer 注释）
    .onAreaChange((_oldArea: Area, newArea: Area): void => { this.measureContainer(newArea); },
      { expectedUpdateInterval: 1000 })
  }
}
