/**
 * 点开才创建的独立受限 Web。HTML 默认禁脚本（用户显式开启「HTML 预览运行脚本」偏好后，
 * 输入脚本可在无桥、无网络、无文件权限的壳内执行，偏好默认关零回归）；Mermaid 恒走
 * 固定离线壳与 bundle；SVG 走静态壳文档，恒无 JS、无桥、无网络——准入重建在
 * MarkdownPreviewPolicy 内完成，本件只负责生命周期与拦截。每次打开新 controller/session，
 * 旧文档修订与页面离场立即撤 Web；不注册原生桥。承载 = bindSheet 半模态 + HdsNavigation
 * MODAL 壳 + 官方标题栏与 xmark 圆钮（照 MarkdownReadingCover 同构，规范-半模态 §1）；
 * Web 拦截/装载/关闭链安全语义逐条不变。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { MarkdownDocumentToken, nextMarkdownBindingId } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { MARKDOWN_PREVIEW_ORIGIN, MARKDOWN_PREVIEW_RUNNER_URL, MARKDOWN_PREVIEW_SCRIPT_URL,
  MARKDOWN_PREVIEW_RUNNER_FILE, MARKDOWN_PREVIEW_SCRIPT_FILE, MARKDOWN_PREVIEW_SOURCE_PAGE,
  MarkdownPreviewDocument, MarkdownPreviewTitle, markdownPreviewSupported, markdownPreviewIdentity,
  markdownPreviewHtml, markdownPreviewMermaidError, markdownPreviewStartScript, markdownPreviewReadTitle,
  markdownPreviewSourcePage, markdownPreviewSvg, markdownPreviewSvgLanguage }
  from '../../../common/markdown/MarkdownPreviewPolicy';
import { cardBorderColor, cardDescColor, cardTitleColor, wellBg } from '../../../common/Theme';
import { FONT_FAMILY_MONO } from '../../../common/ChatFont';
import { isPreviewJsEnabled, isSvgPreviewEnabled } from '../../../common/AppPreferences';
import { IMMERSIVE_LEVEL_KEY } from '../../../common/ImmersiveLevel';
import { DETENTS_FULL, sheetPanelOptions, sheetTitleBarOptions } from '../KimiSheetCommon';
import { MarkdownReadingButton } from './MarkdownReadingButton';

// 仅作为失败出口，不是预热或轮询；成功事件到达即清除，不据此许诺设备性能。
const PREVIEW_FAILURE_DEADLINE_MS: number = 15000;
// 整页滚动（三改）：页面进 Scroll 后子件拿不到剩余空间，Web 区改定高 = 面板内容视口 ×
// 本比例（下限 280vp；视口高度经 Page 的 onAreaChange 实测回写）。
const PREVIEW_WEB_VIEWPORT_RATIO: number = 0.55;
const PREVIEW_WEB_MIN_HEIGHT: number = 280;
// 构建期诊断开关（BROWSE_DEBUG 同族，默认 false）：true 时装载链打最小 hilog 探针，供
// 真机「加载不出来」归因；诊断轮临时翻 true 重构建，完事复位。
const MARKDOWN_PREVIEW_DEBUG: boolean = false;

@ComponentV2
export struct MarkdownPreview {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  // 代码字体家族串：透传给封面源码视图（技术原文走等宽）
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Local private covers: string[] = [];
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.covers = []; }
  aboutToDisappear(): void { this.alive = false; }

  private open(): void {
    // 重入守卫独立成行（与完整阅读宿主 openCover 同形；离场动效在途期 covers 未清，本行
    // 与预览键置灰联合构成结构式关闭-再开协调，见 assert-ui-shape ephemeral 判据）。
    if (this.covers.length > 0) { return; }
    if (!this.alive || !markdownPreviewSupported(this.node) ||
      (this.node.kind === 'codeBlock' && !this.node.closed)) { return; }
    this.covers = [nextMarkdownBindingId()];
  }

  private closed(session: string): void {
    if (this.alive && this.covers.length === 1 && this.covers[0] === session) { this.covers = []; }
  }

  // 入口提示行：脚本开关开且内容为 html 类时承诺句改口为「脚本仅本地运行」——开态
  // 下输入脚本确会执行，「不执行输入中的脚本」不再为真（言行一致）；关态与 mermaid 不变。
  private entryHint(): string {
    if (this.node.kind === 'codeBlock') {
      return this.node.closed ? '独立预览仅显示安全内容。不联网，不执行输入中的脚本' :
        '图表围栏尚未闭合，请先阅读源码';
    }
    return isPreviewJsEnabled() ? '独立预览仅显示安全内容。不联网，脚本仅本地运行' :
      '独立预览仅显示安全内容。不联网，不执行输入中的脚本';
  }

  build() {
    Column({ space: 6 }) {
      if (markdownPreviewSupported(this.node)) {
        // 行内入口（唯一挂载点 MarkdownInlineView 恒传 htmlInline 合成节点）：说明小字居左、
        // 受限预览裸图标键居右（SymbolGlyph eye + TEXTUAL，与块级标题条右槽键同形制）；
        // kind/closed 判定与 open() 守卫同源保留，防御未来挂载面变化。
        Row({ space: 8 }) {
          Text(this.entryHint())
            .fontSize(12).lineHeight(18).fontColor(cardDescColor()).layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.eye')).fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('受限预览')
          .enabled(this.covers.length === 0 && (this.node.kind !== 'codeBlock' || this.node.closed))
          .onClick((): void => { this.open(); })
        }
        .width('100%')
      }
      ForEach(this.covers, (session: string) => {
        MarkdownPreviewCover({ node: this.node, token: this.token, darkMode: this.darkMode, session: session,
          codeFontFamily: this.codeFontFamily,
          onClosed: (closedSession: string): void => { this.closed(closedSession); } })
      }, (session: string): string => session)
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
export struct MarkdownPreviewCover {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Require @Param session: string;
  @Param darkMode: boolean = false;
  // 代码字体家族串：源码视图走代码字体（默认 = 通用等宽）
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Event onClosed: (session: string) => void = (_session: string): void => {};
  // 半模态可见性（关闭链①：$$ 双向目标；唯一写 true 落 aboutToAppear，宿主挂载即拉起）
  @Local private isPresent: boolean = false;
  @Local private webMounted: boolean = false;
  @Local private feedback: string = '正在加载受限预览';
  @Local private sourcePage: number = 0;
  // Web 区定高（整页滚动三改：Scroll 主轴无界子件拿不到剩余空间——初值 380 首帧兜底，
  // Page 的 onAreaChange 按视口比例回写）
  @Local private webHeight: number = 380;
  private controller: webview.WebviewController = new webview.WebviewController();
  // 页面滚动控制器：bindToScrollable 的滚动感知对象——标题栏 GRADIENT_BLUR 与 AUTO
  // 分割线按它的滚动位状态工作（先例 = ContextUsageSheet.scroller）
  private scroller: Scroller = new Scroller();
  private alive: boolean = false;
  private attached: boolean = false;
  private lifecycle: number = 0;
  private identity: string = '';
  private capturedSource: string = '';
  private capturedDark: boolean = false;
  private mermaid: boolean = false;
  // SVG 载体标记：```svg / ```xml（验根）代码块走静态 SVG 文档分支——与 mermaid 分离
  //（mermaid 走固定 runner + JS 恒开；SVG 恒无 JS、静态壳文档）。
  private svg: boolean = false;
  // 脚本开关快照：html 类预览点开时刻读偏好一次，同时驱动 Web 的 javaScriptAccess
  // 与壳 CSP/脚本豁免——两处同源防读写不一致；mermaid 恒走固定可信壳不受本开关影响。
  private htmlScripts: boolean = false;
  private html: string = '';
  private pageUrl: string = '';
  private bootstrapPending: boolean = false;
  private loadNavigationSeen: boolean = false;
  private overrideNavigationSeen: boolean = false;
  private documentServed: boolean = false;
  private pageEnded: boolean = false;
  private htmlTitleSeen: boolean = false;
  private started: boolean = false;
  private deadline: number = -1;
  // 占位空选项（aboutToAppear 必先于 build 执行，真实选项在那里按本会话代际装配——
  // MarkdownReadingCover.panelOptions 同形）
  private panelOptions: SheetOptions = {};

  aboutToAppear(): void {
    this.alive = true;
    const lifecycle: number = ++this.lifecycle;
    const session: string = this.session;
    this.controller = new webview.WebviewController();
    this.attached = false;
    this.bootstrapPending = false;
    this.loadNavigationSeen = false;
    this.overrideNavigationSeen = false;
    this.documentServed = false;
    this.pageEnded = false;
    this.htmlTitleSeen = false;
    this.started = false;
    this.html = '';
    this.webMounted = false;
    this.feedback = '正在加载受限预览';
    this.identity = markdownPreviewIdentity(this.token, this.node);
    this.capturedSource = this.node.text;
    this.capturedDark = this.darkMode;
    // 载体三分：mermaid codeBlock / svg·xml codeBlock / 其余（html 类）。脚本开关快照只对
    // html 类落位——SVG 恒无 JS（静态文档 + 壳 CSP script-src 'none'），不受开关影响。
    this.svg = markdownPreviewSvgLanguage(this.node);
    this.mermaid = this.node.kind === 'codeBlock' && !this.svg;
    this.htmlScripts = !this.mermaid && !this.svg && isPreviewJsEnabled();
    this.sourcePage = 0;
    // 半模态面板选项（全工程唯一 SheetOptions 构造点；全屏单挡位 DETENTS_FULL 与原全屏
    // ContentCover 行为等价）。关闭链②：手势路经官方漏斗 onWillDismiss 放行后路由关闭单
    // 入口 close()（与标题栏 xmark 两路同调）；第四参 onDisappear = 离场动效结束信号 →
    // onSheetGone 上行 onClosed（父件清 covers 卸载本宿主）。
    this.panelOptions = sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        if (this.alive && lifecycle === this.lifecycle) { this.close(); }
      },
      DETENTS_FULL,
      undefined,
      (): void => {
        if (this.alive && lifecycle === this.lifecycle) { this.onSheetGone(); }
      });
    // 宿主挂载即拉起：父件置 covers 即开意图，本会话是新鲜宿主，无离场动效在途
    this.isPresent = true;
    // SVG 面另读偏好开关（prefSvgPreview 默认开，点开时刻一次）：入口键侧已按开关隐藏
    //（MarkdownScrollableBlock），此处为纵深防御——关态不可能正常走到本壳
    if (!markdownPreviewSupported(this.node) || (this.svg && !isSvgPreviewEnabled())) {
      this.feedback = '此内容不支持受限预览';
      return;
    }
    if (this.mermaid) {
      const error: string = markdownPreviewMermaidError(this.capturedSource, this.node.closed);
      if (error !== '') { this.feedback = error; return; }
      this.pageUrl = MARKDOWN_PREVIEW_RUNNER_URL;
    } else if (this.svg) {
      const document: MarkdownPreviewDocument = markdownPreviewSvg(this.capturedSource, this.darkMode, session);
      if (document.error !== '') { this.feedback = document.error; return; }
      this.html = document.html;
      this.pageUrl = MARKDOWN_PREVIEW_ORIGIN + '/svg/' + session;
    } else {
      const document: MarkdownPreviewDocument = markdownPreviewHtml(this.capturedSource, this.darkMode, session,
        this.htmlScripts);
      if (document.error !== '') { this.feedback = document.error; return; }
      this.html = document.html;
      this.pageUrl = MARKDOWN_PREVIEW_ORIGIN + '/html/' + session;
    }
    this.webMounted = true;
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.lifecycle++;
    this.stopWeb();
    this.html = '';
    this.capturedSource = '';
  }

  @Monitor('node', 'token', 'darkMode')
  private inputChanged(): void {
    if (this.alive && !this.current()) {
      this.stopWeb();
      this.webMounted = false;
      this.html = '';
      this.capturedSource = '';
      this.sourcePage = 0;
      this.feedback = '内容或主题已更新，旧预览已关闭。请关闭此页后重新打开';
    }
  }

  private current(): boolean {
    return this.alive && this.isPresent && this.identity === markdownPreviewIdentity(this.token, this.node) &&
      this.capturedSource === this.node.text && this.capturedDark === this.darkMode;
  }

  private clearDeadline(): void {
    if (this.deadline !== -1) { clearTimeout(this.deadline); this.deadline = -1; }
  }

  private stopWeb(): void {
    this.clearDeadline();
    this.bootstrapPending = false;
    if (this.attached) {
      try { this.controller.stop(); }
      catch (failure) {
        // 解绑与关闭可以相邻到达；记录即可，不能因停止失败重新创建或放宽预览。
        hilog.warn(0xD5A0, 'MarkdownPreview', '预览停止失败：%{public}s', (failure as Error).message);
      }
    }
    this.attached = false;
  }

  // 关闭单入口（规范-半模态 §1：标题栏 xmark 与 onWillDismiss 两路同调；零暂存恒直关）。
  // 关闭即同步撤 Web 是本件安全不变量（动画开始前 Web 已停——「页面离场立即撤 Web」照旧），
  // 只写可见性触发离场动效，内容树随动画走完。
  private close(): void {
    this.stopWeb();
    this.webMounted = false;
    this.isPresent = false;
  }

  // 关闭-再开协调的动效结束执行点（sheetPanelOptions 第四参 onDisappear——d.ts「动画结束
  // 后回调」）：安全收尾再兜一遍（幂等）+ 上行 onClosed，父件清 covers（卸载本宿主并放开
  // 预览键）——下一次开只可能在此之后。
  private onSheetGone(): void {
    this.stopWeb();
    this.webMounted = false;
    this.onClosed(this.session);
  }

  // 井底取色模式（V2 组件无 @StorageProp：darkMode 派生数值模式；卡底透明度档位由 wellBg
  // 缺省参数现读——本面板是短命新建实例，开面板期间档位不会变）
  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  // 标题栏材质档（V2 组件无 @StorageProp——弹出瞬间现读，MarkdownReadingCover.titleLevel
  // 同口径：面板打开期间档位不会变，无需订阅刷新）
  private titleLevel(): number {
    const level: number | undefined = AppStorage.get<number>(IMMERSIVE_LEVEL_KEY);
    return level === undefined ? 0 : level;
  }

  private fail(message: string): void {
    if (!this.current()) { return; }
    this.stopWeb();
    this.webMounted = false;
    this.feedback = message;
  }

  private armDeadline(lifecycle: number, session: string): void {
    this.deadline = setTimeout((): void => {
      if (this.current() && lifecycle === this.lifecycle && session === this.session) {
        this.fail('预览未能完成加载，请阅读源码后关闭重试');
      }
    }, PREVIEW_FAILURE_DEADLINE_MS);
  }

  private controllerAttached(): void {
    const lifecycle: number = this.lifecycle;
    const session: string = this.session;
    // 早退路径同样武装 15s 兜底：attach 与状态失效竞态时不许停在「正在加载」无出口。
    if (!this.current() || !this.webMounted) { this.armDeadline(lifecycle, session); return; }
    this.attached = true;
    this.bootstrapPending = true;
    this.armDeadline(lifecycle, session);
    try {
      // 装载单机制：HTML 与 Mermaid 同路，均 loadUrl 触发主导航、由资源拦截供给内容。
      // 原 loadData 直传原始 HTML 属规格外组合（官方要求 data 为 Base64/URL 编码），壳内
      // 样式色值的首个 # 会被解释为 URL fragment 截断文档，已弃用。
      this.controller.loadUrl(this.pageUrl);
    } catch (failure) {
      hilog.warn(0xD5A0, 'MarkdownPreview', '预览加载失败：%{public}s', (failure as Error).message);
      this.fail('预览加载失败，请阅读源码');
    }
  }

  private interceptNavigation(request: WebResourceRequest, override: boolean): boolean {
    const seen: boolean = override ? this.overrideNavigationSeen : this.loadNavigationSeen;
    if (this.current() && this.webMounted && this.bootstrapPending && !seen && request.isMainFrame() && !request.isRedirect() &&
      request.getRequestMethod() === 'GET' && request.getRequestUrl() === this.pageUrl) {
      // 两道回调各只放行同一个宿主URL一次，互不消费对方许可。
      // pageBegin与两回调的次序未获官方保证，不在pageBegin提前封门；pageEnd终止引导。
      if (override) { this.overrideNavigationSeen = true; }
      else { this.loadNavigationSeen = true; }
      return false;
    }
    // 链接、表单、iframe、重定向与重复主导航一律拒绝，不从此处唤起其他应用。
    return true;
  }

  private resourceResponse(request: WebResourceRequest): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    let served: string = 'deny';
    response.setResponseData('');
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType('text/plain');
    response.setResponseCode(403);
    response.setReasonMessage('Forbidden');
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' }]);
    if (this.current() && this.webMounted && request.getRequestMethod() === 'GET' && !request.isRedirect()) {
      const url: string = request.getRequestUrl();
      if (url === this.pageUrl && request.isMainFrame() && !this.documentServed) {
        this.documentServed = true;
        served = this.mermaid ? 'runner' : 'html';
        response.setResponseData(this.mermaid ? $rawfile(MARKDOWN_PREVIEW_RUNNER_FILE) : this.html);
        response.setResponseMimeType('text/html');
        response.setResponseCode(200);
        response.setReasonMessage('OK');
      } else if (this.mermaid && !request.isMainFrame() && url === MARKDOWN_PREVIEW_SCRIPT_URL) {
        served = 'script';
        response.setResponseData($rawfile(MARKDOWN_PREVIEW_SCRIPT_FILE));
        response.setResponseMimeType('text/javascript');
        response.setResponseCode(200);
        response.setReasonMessage('OK');
      }
    }
    response.setResponseIsReady(true);
    if (MARKDOWN_PREVIEW_DEBUG) {
      hilog.info(0xD5A0, 'MarkdownPreview', 'intercept url=%{public}s main=%{public}d served=%{public}s',
        request.getRequestUrl(), request.isMainFrame() ? 1 : 0, served);
    }
    // 绝不返回 null/undefined，否则官方语义为继续加载原资源。
    return response;
  }

  private pageComplete(url: string): void {
    if (MARKDOWN_PREVIEW_DEBUG) {
      hilog.info(0xD5A0, 'MarkdownPreview', 'pageEnd url=%{public}s ended=%{public}d', url, this.pageEnded ? 1 : 0);
    }
    if (!this.current() || !this.webMounted || url !== this.pageUrl || this.pageEnded) { return; }
    this.pageEnded = true;
    this.bootstrapPending = false;
    if (!this.mermaid) {
      if (this.htmlTitleSeen) { this.clearDeadline(); this.feedback = this.staticFeedback(); }
      return;
    }
    if (this.started) { return; }
    this.started = true;
    const lifecycle: number = this.lifecycle;
    const session: string = this.session;
    this.feedback = '正在离线渲染图表';
    try {
      // runJavaScript 的 Promise 不等待网页 Promise。这里仅验同步启动确认，完成走 title 事件。
      this.controller.runJavaScript(markdownPreviewStartScript(this.capturedSource, session, this.capturedDark))
        .then((result: string): void => {
          if (!this.current() || lifecycle !== this.lifecycle || session !== this.session || !this.webMounted) { return; }
          if (result !== 'accepted' && result !== '"accepted"') { this.fail('图表渲染器未就绪，请阅读源码'); }
        }).catch((failure: Error): void => {
          if (!this.current() || lifecycle !== this.lifecycle || session !== this.session) { return; }
          hilog.warn(0xD5A0, 'MarkdownPreview', '图表启动失败：%{public}s', failure.message);
          this.fail('图表渲染器加载失败，请阅读源码');
        });
    } catch (failure) {
      hilog.warn(0xD5A0, 'MarkdownPreview', '图表启动失败：%{public}s', (failure as Error).message);
      this.fail('图表渲染器加载失败，请阅读源码');
    }
  }

  // 静态文档（html 类 / svg）成功承诺句单源：svg 走静态渲染语义（SMIL 已剥离），不冒称
  // 结构重建口径；两处完成出口（pageEnd 与 title）共用，防两处文案漂移。
  private staticFeedback(): string {
    return this.svg ? 'SVG 已静态渲染。动画与外部内容均未启用' :
      '已显示安全结构。原有样式、链接及有源内容不会执行';
  }

  private titleReceived(event: OnTitleReceiveEvent): void {
    if (MARKDOWN_PREVIEW_DEBUG) {
      hilog.info(0xD5A0, 'MarkdownPreview', 'title=%{public}s real=%{public}d',
        event.title, event.isRealTitle === false ? 0 : 1);
    }
    if (!this.current() || !this.webMounted || event.isRealTitle === false) { return; }
    if (!this.mermaid) {
      // 静态文档标题协议：html 与 svg 两键并列——各自壳的 <title> 与页址后缀同源
      if (event.title === 'md-preview:' + this.session + (this.svg ? ':svg' : ':html')) {
        this.htmlTitleSeen = true;
        if (this.pageEnded) { this.clearDeadline(); this.feedback = this.staticFeedback(); }
      }
      return;
    }
    if (!this.started) { return; }
    const title: MarkdownPreviewTitle = markdownPreviewReadTitle(event.title, this.session);
    if (title.status === 'ok') { this.clearDeadline(); this.feedback = '图表已离线渲染。交互与外部内容均未启用'; }
    else if (title.status === 'error') { this.fail(title.message); }
  }

  @Builder
  PreviewWeb() {
    Web({ src: '', controller: this.controller, incognitoMode: true })
      // 唯一组件级 JS 控制面：mermaid 恒开（固定可信壳 + 固定 bundle）；html 类按
      // 点开时刻的偏好快照开关（默认关零回归）。无桥、导航双拦截与 onPermissionRequest
      // 恒 deny 不变量不随本开关变化。
      .javaScriptAccess(this.mermaid || this.htmlScripts)
      .blockNetwork(true)
      .fileAccess(false)
      .onlineImageAccess(false)
      .imageAccess(false)
      .domStorageAccess(false)
      .databaseAccess(false)
      .geolocationAccess(false)
      .mixedMode(MixedMode.None)
      .cacheMode(CacheMode.None)
      .copyOptions(CopyOptions.None)
      .multiWindowAccess(false)
      .allowWindowOpenMethod(false)
      .enableAutoFill(false)
      // 滚动链：Web 内滚由 Web 自己响应，到上下边后余量交给**本页 Scroll**（SELF_FIRST）——
      // 三改前没有页面 Scroll，余量直递面板拖拽致误拖误关（故当时 SELF_ONLY 截断）；现页面
      // 自身到边由 Spring alwaysEnabled 消费。overScrollMode NEVER = d.ts nestedScroll 节
      // 官方建议（嵌套场景 Web 到边先触发 overscroll 回弹影响体验）。
      .overScrollMode(OverScrollMode.NEVER)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST })
      .onControllerAttached((): void => { this.controllerAttached(); })
      .onLoadIntercept((event: OnLoadInterceptEvent): boolean => this.interceptNavigation(event.data, false))
      .onOverrideUrlLoading((request: WebResourceRequest): boolean => this.interceptNavigation(request, true))
      .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse => this.resourceResponse(event.request))
      .onPageEnd((event: OnPageEndEvent): void => { this.pageComplete(event.url); })
      .onTitleReceive((event: OnTitleReceiveEvent): void => { this.titleReceived(event); })
      .onErrorReceive((event: OnErrorReceiveEvent): void => {
        if (MARKDOWN_PREVIEW_DEBUG) {
          hilog.info(0xD5A0, 'MarkdownPreview', 'error url=%{public}s info=%{public}s code=%{public}d',
            event.request.getRequestUrl(), event.error.getErrorInfo(), event.error.getErrorCode());
        }
        if (event.request.isMainFrame() && event.request.getRequestUrl() === this.pageUrl) {
          this.fail('页面加载失败，请阅读源码');
        }
      })
      .onRenderExited((_event: OnRenderExitedEvent): void => { this.fail('预览渲染进程已退出，请阅读源码'); })
      .onRenderProcessNotResponding((): void => { this.fail('预览渲染进程未响应，请阅读源码'); })
      .onPermissionRequest((event: OnPermissionRequestEvent): void => { event.request.deny(); })
      // 预览框 20vp 圆角（决明拍板）：Web 属复杂渲染组件，官方 FAQ「圆角边框问题」
      //（faqs-arkui-1083）——此类组件 borderRadius 须配 clip 才裁剪生效（仓内先例
      // ProactiveBanner 同款 20+clip）。
      .borderRadius(20)
      .clip(true)
      .width('100%').height(this.webHeight)
      .onDisAppear((): void => { this.attached = false; this.clearDeadline(); })
  }

  @Computed
  get sourcePages(): number { return Math.max(1, Math.ceil(this.node.text.length / MARKDOWN_PREVIEW_SOURCE_PAGE)); }

  @Builder
  Page() {
    HdsNavigation() {
      // 整页滚动（三改）：内容整体进 Scroll——源码井自适应整段高度、井内滚退役，读源码变
      //「整页顺读」。Web 区改定高 = 视口 × 55%（下限 280，onAreaChange 回写），保留自身内
      // 滚，到边余量交本页 Scroll；本页 Spring alwaysEnabled 消费余量不把面板拖起来。
      // 滚动条统一隐藏。
      Scroll(this.scroller) {
        Column({ space: 8 }) {
          // 静态安全承诺句随脚本开关快照取值（言行一致改口口径见 entryHint）
          Text(this.htmlScripts ? '独立预览仅显示安全内容。不联网，脚本仅本地运行' :
            '独立预览仅显示安全内容。不联网，不执行输入中的脚本')
            .fontSize(12).lineHeight(18).fontColor(cardDescColor()).width('100%')
          Text(this.feedback).fontSize(12).lineHeight(18).fontColor(cardDescColor()).width('100%')
          if (this.webMounted && this.current()) { this.PreviewWeb() }
          Text('当前源码。第 ' + (this.sourcePage + 1).toString() + ' 页，共 ' + this.sourcePages.toString() + ' 页')
            .fontSize(12).lineHeight(18).fontColor(cardDescColor()).width('100%')
          if (this.sourcePages > 1) {
            Row({ space: 8 }) {
              MarkdownReadingButton({ label: '上一页', isEnabled: this.sourcePage > 0,
                onAction: (): void => { this.sourcePage = Math.max(0, this.sourcePage - 1); } })
              MarkdownReadingButton({ label: '下一页', isEnabled: this.sourcePage + 1 < this.sourcePages,
                onAction: (): void => { this.sourcePage = Math.min(this.sourcePages - 1, this.sourcePage + 1); } })
            }
            .width('100%')
          }
          // 源码井：井底 wellBg + 0.5vp cardBorderColor 发丝边 + 圆角 12 + 内距 12（规范-
          // 列表卡片与组卡 §4.17 形制，先例 ContextUsageSheet.SummaryWell）；**不套井会读出
          // 一条假分割线**——本页内容区不设底色而裸文本无底无边，读作「页面被切开」。
          // ★ 井的内距/描边/裁剪恒挂外层容器，禁挂滚动容器自身（真机教训 = Scroll 自带
          // 内距后整页滚不动）；本井不内滚，随源码整段高度展开。
          Column() {
            Text(markdownPreviewSourcePage(this.node.text, this.sourcePage) || '空源码')
              .fontSize(14).lineHeight(21).fontFamily(this.codeFontFamily).fontColor(cardTitleColor())
              .copyOption(CopyOptions.None).width('100%')
          }
          .width('100%').padding(12)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(wellBg(this.colorMode()))
          .border({ width: 0.5, color: cardBorderColor(this.colorMode()) })
          .borderRadius(12)
          .clip(true)
        }
        .width('100%').padding(12).alignItems(HorizontalAlign.Start)
        // 不设背景色：面板底由 sheetPanelOptions 承担（材质态实底会盖掉材质，「无」档回落
        // page_bg）——MarkdownReadingCover 内容区同口径
      }
      .width('100%').height('100%')
      // 短内容顶对齐（坑18：Scroll 默认 Center 会把不足一屏的页面垂直居中）
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 滚动内容穿透标题栏背后供 GRADIENT_BLUR 采样（规范-半模态 §2：缺省裁剪 = 模糊空转，
      // 真机症状 = 标题栏无沉浸光感 + AUTO 分割线露出硬边）
      .clip(false)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const h: number = newArea.height as number;
        if (h > 0) {
          const next: number = Math.max(PREVIEW_WEB_MIN_HEIGHT, Math.round(h * PREVIEW_WEB_VIEWPORT_RATIO));
          if (next !== this.webHeight) { this.webHeight = next; }
        }
      })
    }
    // 官方半模态标题形制（规范-半模态 §1：HdsNavigation MODAL 壳 + sheetTitleBarOptions
    // 同源，勿自绘标题）；关闭键 = 标题栏官方 xmark 圆钮（决明拍板），与 onWillDismiss 两路
    // 同调 close()。滚动绑定按规范 §2 三件齐做：Scroller + bindToScrollable + 页面 Scroll
    // clip(false)（内容穿透标题栏供 GRADIENT_BLUR 采样）——缺任一件退回「顶部无光感 +
    // AUTO 分割线」；无吸底键带，底部安全区不延伸。
    .titleBar(sheetTitleBarOptions('受限预览', '', (): void => { this.close(); }, this.titleLevel()))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
  }

  build() {
    Blank().width(0).height(0).bindSheet($$this.isPresent, this.Page(), this.panelOptions)
  }
}
