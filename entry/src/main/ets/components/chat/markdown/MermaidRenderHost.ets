/**
 * Mermaid 内联渲染服务（模块级单例）+ 隐藏 Web 宿主组件。
 * 分工：服务 = 队列、票据、缓存、失败语义；宿主 = Web 生命周期与事件转发。服务不持有组件
 * 引用（寿命匹配：App 级服务不得持页面级组件），只经 AppStorage 两个运行时信号键通话
 * （hostActive 驱动挂/拆 Web，jobSignal 驱动取任务），事件回流走服务方法。
 * 安全边界逐项对齐 MarkdownPreviewCover 的 mermaid 面：固定离屏壳、禁网络/文件/存储、无桥、
 * 权限恒 deny、资源精确白名单；唯一通道 = runJavaScript 启动 + title 协议 + runJavaScriptExt
 * 拉取已校验产物。消息列表内零 Web——整页至多一个 1×1 隐藏宿主，空闲 60 秒自动拆，页面离场必拆。
 */
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MERMAID_INLINE_CACHE_CAPACITY, mermaidInlineKey, mermaidInlineLruEvict }
  from '../../../common/markdown/MermaidInlinePolicy';
import { MARKDOWN_PREVIEW_RUNNER_FILE, MARKDOWN_PREVIEW_RUNNER_URL, MARKDOWN_PREVIEW_SCRIPT_FILE,
  MARKDOWN_PREVIEW_SCRIPT_URL, MarkdownPreviewTitle, markdownPreviewReadTitle }
  from '../../../common/markdown/MarkdownPreviewPolicy';

// 运行时信号键（非持久偏好，不进 AppPreferences/persistProp）：宿主组件 @StorageProp 订阅。
export const MERMAID_HOST_ACTIVE_KEY: string = 'mermaidRenderHostActive';
export const MERMAID_HOST_SIGNAL_KEY: string = 'mermaidRenderHostSignal';

// 空闲销毁：任务清空后保留 Web 一段时间复用（连续多图不反复冷启动），到期拆释放资源；
// ArkWeb 每实例内核级固定开销，60 秒是复用收益与常驻成本的折中。
const MERMAID_HOST_IDLE_MS: number = 60000;
// 单任务失败出口（同预览的 15 秒截止）：Web 未响应/异常时退码，不无限悬挂。
const MERMAID_JOB_DEADLINE_MS: number = 15000;
// 排队等待上限：宿主页面迟迟不就绪（装载失败/隐藏宿主不执行 JS）时任务必须有出口，否则
// 代码态静默永久停留；比运行期截止宽，容多图串行排队。
const MERMAID_WAIT_DEADLINE_MS: number = 30000;
// 构建期诊断探针（MARKDOWN_PREVIEW_DEBUG 同族）：true 时逐阶段打一行，排障用。
const MERMAID_RENDER_DEBUG: boolean = false;
const MERMAID_PNG_PREFIX: string = 'data:image/png;base64,';
const MERMAID_PNG_LIMIT: number = 8 * 1024 * 1024;
const MERMAID_IMAGE_BYTES_LIMIT: number = 6 * 1024 * 1024;

export interface MermaidRenderJob {
  job: string;
  key: string;
  source: string;
  darkMode: boolean;
  scale: number;
  watermark: boolean;
  startScript: string;
  completed: boolean;
}

/** bytes 非空 = 成功；null + message = 失败（调用方维持代码态，不占版面报错）。 */
export type MermaidRenderListener = (bytes: Uint8Array | null, message: string) => void;
export type MermaidUnsubscribe = () => void;

function mermaidScriptLiteral(text: string): string {
  // U+2028/U+2029 在 JS 源码字面量里会断行，JSON.stringify 不转义它们——照预览启动脚本同款。
  return JSON.stringify(text).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

/** 导出模式启动脚本：实参全走 JSON 序列化，不拼用户函数/script 标签/eval。 */
export function mermaidExportStartScript(job: string, source: string, darkMode: boolean, scale: number,
  watermark: boolean): string {
  return 'window.MarkdownPreviewRunner.startExport(' + JSON.stringify(job) + ',' +
    mermaidScriptLiteral(source) + ',' + (darkMode ? 'true' : 'false') + ',' + String(scale) + ',' +
    (watermark ? 'true' : 'false') + ')';
}

/** 产物拉取脚本：只读固定命名空间下的字符串，表达式结果走 runJavaScriptExt 返回值。 */
export function mermaidExportPullScript(job: string): string {
  return '(window.__mermaidExports[' + JSON.stringify(job) + '] || {}).data || \'\'';
}

/** 渲染服务：串行队列（同 preview runner 单任务语义）+ 缓存 + 订阅表 + 空闲销毁。 */
export class MermaidRenderService {
  private entries: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  private order: string[] = [];
  private waiting: Map<string, MermaidRenderListener[]> = new Map<string, MermaidRenderListener[]>();
  private jobs: MermaidRenderJob[] = [];
  private current: MermaidRenderJob | null = null;
  private jobSeq: number = 0;
  private signal: number = 0;
  private hostActive: boolean = false;
  private hostAttached: boolean = false;
  private webReady: boolean = false;
  private idleTimer: number = -1;
  private deadline: number = -1;

  /** 订阅渲染结果：缓存命中即异步回填；未命中入队并唤醒宿主。返回取消函数（组件离场必调）。 */
  subscribe(source: string, darkMode: boolean, scale: number, watermark: boolean,
    listener: MermaidRenderListener): MermaidUnsubscribe {
    if (!this.hostAttached) {
      // 无宿主场景（技能预览等复用正文渲染但未挂本宿主）：直接失败退码，不悬挂 15 秒。
      if (MERMAID_RENDER_DEBUG) {
        hilog.info(0xD5A0, 'MermaidRender', 'subscribe 无宿主，直接退码');
      }
      setTimeout((): void => { listener(null, '图表内联渲染不可用'); }, 0);
      return (): void => {};
    }
    // 导出（带 AI 标识条）与显示产物不同，故 watermark 进缓存键后缀；主题与倍率已在策略键内。
    const key: string = mermaidInlineKey(source, darkMode, scale) + (watermark ? ':w' : '');
    const cached: Uint8Array | undefined = this.entries.get(key);
    if (cached !== undefined) {
      if (MERMAID_RENDER_DEBUG) {
        hilog.info(0xD5A0, 'MermaidRender', 'subscribe 缓存命中 key=%{public}s bytes=%{public}d', key,
          cached.byteLength);
      }
      // 异步回填：订阅点可能处于组件构建期，同步改状态会与本帧构建重入。
      setTimeout((): void => { listener(cached, ''); }, 0);
      return (): void => {};
    }
    const bucket: MermaidRenderListener[] | undefined = this.waiting.get(key);
    if (bucket === undefined) {
      this.waiting.set(key, [listener]);
    } else {
      bucket.push(listener);
    }
    const queued: boolean = (this.current !== null && this.current.key === key) ||
      this.jobs.some((job: MermaidRenderJob): boolean => job.key === key);
    if (!queued) {
      this.jobSeq++;
      const jobId: string = 'markdown-body-' + this.jobSeq.toString();
      const job: MermaidRenderJob = {
        job: jobId, key: key, source: source, darkMode: darkMode, scale: scale, watermark: watermark,
        startScript: mermaidExportStartScript(jobId, source, darkMode, scale, watermark), completed: false
      };
      this.jobs.push(job);
      this.armWaitDeadline(job);
      this.clearIdle();
      this.setHostActive(true);
      if (MERMAID_RENDER_DEBUG) {
        hilog.info(0xD5A0, 'MermaidRender', 'subscribe 入队 job=%{public}s hostActive=%{public}d webReady=%{public}d',
          jobId, this.hostActive ? 1 : 0, this.webReady ? 1 : 0);
      }
    }
    this.bumpSignal();
    return (): void => {
      const list: MermaidRenderListener[] | undefined = this.waiting.get(key);
      if (list === undefined) {
        return;
      }
      const index: number = list.indexOf(listener);
      if (index >= 0) {
        list.splice(index, 1);
      }
      if (list.length === 0) {
        this.waiting.delete(key);
      }
    };
  }

  attachHost(): void {
    this.hostAttached = true;
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', '接入宿主 排队=%{public}d 在途=%{public}d', this.jobs.length,
        this.current === null ? 0 : 1);
    }
    if (this.jobs.length > 0 && this.current === null) {
      this.setHostActive(true);
      this.bumpSignal();
    }
  }

  /** 页面离场：在途与排队任务一并作废（订阅方随页面销毁已取消），Web 立即拆；缓存保留供
   *  重进会话复出（纯字节有界）。 */
  detachHost(): void {
    this.hostAttached = false;
    this.clearDeadline();
    this.clearIdle();
    this.jobs.length = 0;
    this.current = null;
    this.waiting.clear();
    this.webReady = false;
    this.setHostActive(false);
  }

  /** 宿主取任务：Web 就绪后串行推进；返回 null 表示当前无可启动任务。 */
  nextJob(): MermaidRenderJob | null {
    if (!this.webReady || this.current !== null) {
      return null;
    }
    const job: MermaidRenderJob | undefined = this.jobs.shift();
    if (job === undefined) {
      return null;
    }
    this.current = job;
    this.armDeadline(job);
    return job;
  }

  /** title 协议分流：ok 返回待拉取任务；error 结束失败；其他（含非本会话标题）忽略。 */
  runnerTitle(title: string): MermaidRenderJob | null {
    const job: MermaidRenderJob | null = this.current;
    if (job === null) {
      return null;
    }
    const parsed: MarkdownPreviewTitle = markdownPreviewReadTitle(title, job.job);
    if (parsed.status === 'ok') {
      this.clearDeadline();
      return job;
    }
    if (parsed.status === 'error') {
      this.finishFailure(job, parsed.message);
    }
    return null;
  }

  /** 产物回填：只接受 data:image/png;base64 前缀 + 有界长度，解码失败退码不静默。 */
  pulled(job: MermaidRenderJob, dataUrl: string): void {
    if (this.current !== job) {
      return;
    }
    this.clearDeadline();
    // runJavaScriptExt 回传字符串时带 JSON 外层引号（真机实测长度恒多 2），先剥壳再校验。
    const data: string = dataUrl.length >= 2 && dataUrl.charAt(0) === '"' &&
      dataUrl.charAt(dataUrl.length - 1) === '"' ? dataUrl.substring(1, dataUrl.length - 1) : dataUrl;
    if (!data.startsWith(MERMAID_PNG_PREFIX) || data.length > MERMAID_PNG_LIMIT) {
      this.finishFailure(job, '图表图片无效');
      return;
    }
    let bytes: Uint8Array;
    try {
      bytes = new util.Base64Helper().decodeSync(data.substring(MERMAID_PNG_PREFIX.length));
    } catch (failure) {
      this.finishFailure(job, '图表图片解码失败');
      return;
    }
    if (bytes.byteLength === 0 || bytes.byteLength > MERMAID_IMAGE_BYTES_LIMIT) {
      this.finishFailure(job, '图表图片超出限制');
      return;
    }
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', 'pulled job=%{public}s bytes=%{public}d', job.job,
        bytes.byteLength);
    }
    this.remember(job.key, bytes);
    job.completed = true;
    this.current = null;
    this.publish(job.key, bytes, '');
    this.kick();
  }

  startFailed(job: MermaidRenderJob, message: string): void {
    if (this.current !== job) {
      return;
    }
    this.finishFailure(job, message);
  }

  /** 宿主 Web 就绪/失效：就绪补一次信号推进队列；失效等待重挂。 */
  setWebReady(ready: boolean): void {
    this.webReady = ready;
    if (ready) {
      this.bumpSignal();
    }
  }

  /** Web 进程异常/加载失败：在途与排队全部退码并拆 Web，等下次订阅重挂。 */
  failAll(message: string): void {
    this.clearDeadline();
    const failed: MermaidRenderJob[] = [];
    if (this.current !== null) {
      failed.push(this.current);
      this.current = null;
    }
    while (this.jobs.length > 0) {
      const next: MermaidRenderJob | undefined = this.jobs.shift();
      if (next !== undefined) {
        failed.push(next);
      }
    }
    for (const job of failed) {
      job.completed = true;
      this.publish(job.key, null, message);
    }
    this.setHostActive(false);
  }

  private finishFailure(job: MermaidRenderJob, message: string): void {
    this.clearDeadline();
    job.completed = true;
    if (this.current === job) {
      this.current = null;
    }
    if (MERMAID_RENDER_DEBUG) {
      hilog.warn(0xD5A0, 'MermaidRender', '任务失败 job=%{public}s 原因=%{public}s', job.job, message);
    }
    this.publish(job.key, null, message);
    this.kick();
  }

  private publish(key: string, bytes: Uint8Array | null, message: string): void {
    const list: MermaidRenderListener[] | undefined = this.waiting.get(key);
    if (list === undefined) {
      return;
    }
    this.waiting.delete(key);
    const snapshot: MermaidRenderListener[] = list.slice();
    // 异步回填：调用方可能正处 Web 事件回调栈，同步改图组件状态与本次渲染批次冲突。
    setTimeout((): void => {
      for (const listener of snapshot) {
        listener(bytes, message);
      }
    }, 0);
  }

  private kick(): void {
    if (this.current !== null) {
      return;
    }
    if (this.jobs.length === 0) {
      this.armIdle();
      return;
    }
    this.clearIdle();
    this.setHostActive(true);
    this.bumpSignal();
  }

  private remember(key: string, bytes: Uint8Array): void {
    this.entries.set(key, bytes);
    const existing: number = this.order.indexOf(key);
    if (existing >= 0) {
      this.order.splice(existing, 1);
    }
    this.order.push(key);
    // 活跃键 = 有等待者的键：淘汰跳过它们，宁可短暂超容也不释放正在等的产物。
    const active: string[] = [];
    this.waiting.forEach((_list: MermaidRenderListener[], activeKey: string): void => { active.push(activeKey); });
    const evicted: string[] = mermaidInlineLruEvict(this.order, MERMAID_INLINE_CACHE_CAPACITY, active);
    for (const key of evicted) {
      this.entries.delete(key);
      const position: number = this.order.indexOf(key);
      if (position >= 0) {
        this.order.splice(position, 1);
      }
    }
  }

  private armDeadline(job: MermaidRenderJob): void {
    this.clearDeadline();
    this.deadline = setTimeout((): void => {
      this.deadline = -1;
      if (this.current === job && !job.completed) {
        this.finishFailure(job, '图表渲染超时');
      }
    }, MERMAID_JOB_DEADLINE_MS);
  }

  // 排队期兜底（理由见 MERMAID_WAIT_DEADLINE_MS 注释）：命中即出队退码，不阻塞后续任务。
  private armWaitDeadline(job: MermaidRenderJob): void {
    setTimeout((): void => {
      if (job.completed) {
        return;
      }
      if (MERMAID_RENDER_DEBUG) {
        hilog.warn(0xD5A0, 'MermaidRender',
          '排队超时 job=%{public}s current=%{public}d webReady=%{public}d hostActive=%{public}d',
          job.job, this.current === job ? 1 : 0, this.webReady ? 1 : 0, this.hostActive ? 1 : 0);
      }
      if (this.current === job) {
        this.finishFailure(job, '图表渲染超时');
        return;
      }
      const index: number = this.jobs.indexOf(job);
      if (index >= 0) {
        this.jobs.splice(index, 1);
      }
      job.completed = true;
      this.publish(job.key, null, '图表渲染未就绪');
    }, MERMAID_WAIT_DEADLINE_MS);
  }

  private clearDeadline(): void {
    if (this.deadline !== -1) {
      clearTimeout(this.deadline);
      this.deadline = -1;
    }
  }

  private armIdle(): void {
    this.clearIdle();
    this.idleTimer = setTimeout((): void => {
      this.idleTimer = -1;
      if (this.current === null && this.jobs.length === 0) {
        this.setHostActive(false);
      }
    }, MERMAID_HOST_IDLE_MS);
  }

  private clearIdle(): void {
    if (this.idleTimer !== -1) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
  }

  private setHostActive(active: boolean): void {
    if (this.hostActive === active) {
      return;
    }
    this.hostActive = active;
    AppStorage.setOrCreate<boolean>(MERMAID_HOST_ACTIVE_KEY, active);
  }

  private bumpSignal(): void {
    this.signal++;
    AppStorage.setOrCreate<number>(MERMAID_HOST_SIGNAL_KEY, this.signal);
  }
}

export const MERMAID_RENDER_SERVICE: MermaidRenderService = new MermaidRenderService();

/**
 * 隐藏 Web 宿主：整页唯一实例，挂 1×1 透明区域；V1 组件（@StorageProp + @Watch 是项目既有
 * 组合，PageBackground 先例），由 ChatPageContent 常挂，Web 按服务信号条件渲染。
 */
@Component
export struct MermaidRenderHost {
  @StorageProp(MERMAID_HOST_ACTIVE_KEY) @Watch('onHostSignal') private hostActive: boolean = false;
  @StorageProp(MERMAID_HOST_SIGNAL_KEY) @Watch('onHostSignal') private hostSignal: number = 0;
  @State private webMounted: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private attached: boolean = false;
  private webReady: boolean = false;
  private documentServed: boolean = false;
  private navigationSeen: boolean = false;
  private overrideSeen: boolean = false;
  private alive: boolean = false;
  private pageUrl: string = MARKDOWN_PREVIEW_RUNNER_URL;

  aboutToAppear(): void {
    this.alive = true;
    this.webMounted = this.hostActive;
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', '宿主出现 hostActive=%{public}d 立即挂载=%{public}d',
        this.hostActive ? 1 : 0, this.webMounted ? 1 : 0);
    }
    MERMAID_RENDER_SERVICE.attachHost();
  }

  aboutToDisappear(): void {
    this.alive = false;
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', '宿主离场');
    }
    this.stopWeb();
    MERMAID_RENDER_SERVICE.detachHost();
  }

  // 两个信号任一变化都走本口：active 变化管挂/拆，signal 变化管推进队列。
  private onHostSignal(): void {
    if (!this.alive) {
      return;
    }
    if (this.hostActive && !this.webMounted) {
      this.mountWeb();
    } else if (!this.hostActive && this.webMounted) {
      this.unmountWeb();
    }
    this.tryStart();
  }

  private mountWeb(): void {
    this.controller = new webview.WebviewController();
    this.attached = false;
    this.webReady = false;
    this.documentServed = false;
    this.navigationSeen = false;
    this.overrideSeen = false;
    this.webMounted = true;
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', '挂载 Web');
    }
  }

  private unmountWeb(): void {
    this.stopWeb();
    this.webMounted = false;
  }

  private stopWeb(): void {
    this.webReady = false;
    MERMAID_RENDER_SERVICE.setWebReady(false);
    if (this.attached) {
      try {
        this.controller.stop();
      } catch (failure) {
        hilog.warn(0xD5A0, 'MermaidRender', '内联渲染宿主停止失败：%{public}s', (failure as Error).message);
      }
    }
    this.attached = false;
  }

  private controllerAttached(): void {
    if (!this.alive || !this.webMounted) {
      if (MERMAID_RENDER_DEBUG) {
        hilog.warn(0xD5A0, 'MermaidRender', '控制器挂接但宿主已失效 alive=%{public}d mounted=%{public}d',
          this.alive ? 1 : 0, this.webMounted ? 1 : 0);
      }
      return;
    }
    this.attached = true;
    this.navigationSeen = false;
    this.overrideSeen = false;
    this.documentServed = false;
    try {
      // 装载单机制同预览：loadUrl 触发主导航，资源拦截供给固定壳与脚本。
      if (MERMAID_RENDER_DEBUG) {
        hilog.info(0xD5A0, 'MermaidRender', '控制器就绪 开始装载 %{public}s', this.pageUrl);
      }
      this.controller.loadUrl(this.pageUrl);
    } catch (failure) {
      hilog.warn(0xD5A0, 'MermaidRender', '内联渲染宿主加载失败：%{public}s', (failure as Error).message);
      MERMAID_RENDER_SERVICE.failAll('图表渲染不可用');
      this.unmountWeb();
    }
  }

  private interceptNavigation(request: WebResourceRequest, override: boolean): boolean {
    const seen: boolean = override ? this.overrideSeen : this.navigationSeen;
    if (this.alive && this.webMounted && !this.webReady && !seen && request.isMainFrame() &&
      !request.isRedirect() && request.getRequestMethod() === 'GET' &&
      request.getRequestUrl() === this.pageUrl) {
      // 两道回调各只放行同一宿主 URL 一次；就绪后（webReady）不再放行任何导航。
      if (override) {
        this.overrideSeen = true;
      } else {
        this.navigationSeen = true;
      }
      return false;
    }
    return true;
  }

  private resourceResponse(request: WebResourceRequest): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseData('');
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType('text/plain');
    response.setResponseCode(403);
    response.setReasonMessage('Forbidden');
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' }]);
    let served: string = 'deny';
    if (this.alive && this.webMounted && request.getRequestMethod() === 'GET' && !request.isRedirect()) {
      const url: string = request.getRequestUrl();
      if (url === this.pageUrl && request.isMainFrame() && !this.documentServed) {
        this.documentServed = true;
        served = 'runner';
        response.setResponseData($rawfile(MARKDOWN_PREVIEW_RUNNER_FILE));
        response.setResponseMimeType('text/html');
        response.setResponseCode(200);
        response.setReasonMessage('OK');
      } else if (!request.isMainFrame() && url === MARKDOWN_PREVIEW_SCRIPT_URL) {
        served = 'script';
        response.setResponseData($rawfile(MARKDOWN_PREVIEW_SCRIPT_FILE));
        response.setResponseMimeType('text/javascript');
        response.setResponseCode(200);
        response.setReasonMessage('OK');
      }
    }
    response.setResponseIsReady(true);
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', 'intercept url=%{public}s main=%{public}d served=%{public}s',
        request.getRequestUrl(), request.isMainFrame() ? 1 : 0, served);
    }
    // 绝不返回 null/undefined，否则官方语义为继续加载原资源。
    return response;
  }

  private pageComplete(url: string): void {
    if (!this.alive || !this.webMounted || url !== this.pageUrl || this.webReady) {
      return;
    }
    this.webReady = true;
    MERMAID_RENDER_SERVICE.setWebReady(true);
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', 'pageEnd url=%{public}s', url);
    }
    this.tryStart();
  }

  private tryStart(): void {
    if (!this.alive || !this.webMounted || !this.attached || !this.webReady) {
      return;
    }
    const job: MermaidRenderJob | null = MERMAID_RENDER_SERVICE.nextJob();
    if (job === null) {
      return;
    }
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', 'start job=%{public}s', job.job);
    }
    try {
      // runJavaScript 的 Promise 不等待网页 Promise：仅验同步启动确认，完成走 title 协议。
      this.controller.runJavaScript(job.startScript).then((result: string): void => {
        if (result !== 'accepted' && result !== '"accepted"') {
          MERMAID_RENDER_SERVICE.startFailed(job, '图表渲染器未就绪');
          this.tryStart();
        }
      }).catch((failure: Error): void => {
        hilog.warn(0xD5A0, 'MermaidRender', '图表启动失败：%{public}s', failure.message);
        MERMAID_RENDER_SERVICE.startFailed(job, '图表渲染器加载失败');
        this.tryStart();
      });
    } catch (failure) {
      MERMAID_RENDER_SERVICE.startFailed(job, '图表渲染器加载失败');
      this.tryStart();
    }
  }

  private titleReceived(event: OnTitleReceiveEvent): void {
    if (!this.alive || !this.webMounted || event.isRealTitle === false) {
      return;
    }
    if (MERMAID_RENDER_DEBUG) {
      hilog.info(0xD5A0, 'MermaidRender', 'title=%{public}s', event.title);
    }
    const job: MermaidRenderJob | null = MERMAID_RENDER_SERVICE.runnerTitle(event.title);
    if (job === null) {
      return;
    }
    try {
      this.controller.runJavaScriptExt(mermaidExportPullScript(job.job)).then(
        (result: webview.JsMessageExt): void => {
          let data: string = '';
          let type: number = -1;
          try {
            type = result.getType();
            if (result.getType() === webview.JsMessageType.STRING) {
              data = result.getString();
            }
          } catch (failure) {
            data = '';
          }
          if (MERMAID_RENDER_DEBUG) {
            hilog.info(0xD5A0, 'MermaidRender', '拉取结果 job=%{public}s type=%{public}d len=%{public}d',
              job.job, type, data.length);
          }
          MERMAID_RENDER_SERVICE.pulled(job, data);
          this.tryStart();
        }).catch((failure: Error): void => {
        hilog.warn(0xD5A0, 'MermaidRender', '产物拉取失败：%{public}s', failure.message);
        MERMAID_RENDER_SERVICE.startFailed(job, '图表产物拉取失败');
        this.tryStart();
      });
    } catch (failure) {
      MERMAID_RENDER_SERVICE.startFailed(job, '图表产物拉取失败');
      this.tryStart();
    }
  }

  private failWeb(): void {
    MERMAID_RENDER_SERVICE.failAll('图表渲染不可用');
    this.unmountWeb();
  }

  build() {
    Column() {
      if (this.webMounted) {
        Web({ src: '', controller: this.controller, incognitoMode: true })
          // 安全面逐项对齐 MarkdownPreviewCover：固定可信壳恒开 JS；无桥、禁网络/文件/存储、
          // 禁弹窗与新窗、权限恒拒；CSP 见 mermaid.html（img-src 仅 blob: 供 canvas 转码）。
          .javaScriptAccess(true)
          // ★ 与预览宿主的两处差异（转码需要）：① onlineImageAccess/imageAccess 开——真机
          // 实测关着时 <img> 连 data: 位图都不回调（onload/onerror 全无），转码必然挂死；
          // ② 网络边界仍由 blockNetwork(true) + 资源拦截白名单（非白名单一律 403）+ CSP
          // （connect-src/font-src/media-src 全 none，img-src 仅 data:/blob:）三重承担。
          // 其余不变量与预览宿主一致：无桥、禁文件/存储、禁新窗、权限恒拒、incognito。
          .blockNetwork(true)
          .fileAccess(false)
          .onlineImageAccess(true)
          .imageAccess(true)
          .domStorageAccess(false)
          .databaseAccess(false)
          .geolocationAccess(false)
          .mixedMode(MixedMode.None)
          .cacheMode(CacheMode.None)
          .copyOptions(CopyOptions.None)
          .multiWindowAccess(false)
          .allowWindowOpenMethod(false)
          .enableAutoFill(false)
          .onControllerAttached((): void => { this.controllerAttached(); })
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => this.interceptNavigation(event.data, false))
          .onOverrideUrlLoading((request: WebResourceRequest): boolean =>
          this.interceptNavigation(request, true))
          .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse =>
          this.resourceResponse(event.request))
          .onPageEnd((event: OnPageEndEvent): void => { this.pageComplete(event.url); })
          .onTitleReceive((event: OnTitleReceiveEvent): void => { this.titleReceived(event); })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame() && event.request.getRequestUrl() === this.pageUrl) {
              this.failWeb();
            }
          })
          .onRenderExited((_event: OnRenderExitedEvent): void => { this.failWeb(); })
          .onRenderProcessNotResponding((): void => { this.failWeb(); })
          .onPermissionRequest((event: OnPermissionRequestEvent): void => { event.request.deny(); })
          .width('100%').height('100%')
      }
    }
    .width(1).height(1).opacity(0.01)
    // 顶层 1×1 不遮挡阅读，交互一律穿透（宿主只做离屏转码，永不接收触摸）。
    .hitTestBehavior(HitTestMode.None)
  }
}
