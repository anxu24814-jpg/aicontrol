// 内置浏览器宿主域（2026-09-16 内置浏览器 P1，任务书-内置浏览器P1-20260916）：
// 一个常驻的隐形 Web 宿主 + 它的控制器/服务/就绪态机/串行队列——把「打开一个网址并等它
// 加载完」做成可被工具域调用的异步服务。骨架照 DocumentParse 四件套（隐式宿主 /
// 服务+控制器双单例 / onControllerAttached 复位-onPageEnd 置位 / queueTail 串行），三处
// 刻意偏离（任务书 §2.1）：
// · 满视口（非 1×1）——isInViewport 筛选、懒加载触发、元素可见性全部依赖视口尺寸，
//   1×1 会让「视口内元素」集合恒空；
// · src = about:blank 起手按需 loadUrl（非本地桥页）——浏览目标是任意远程站点；
// · 命令走 executeAIPageCommand（ArkWeb AI 页面命令，API 26 起官方 Agent 读页接口），
//   非自研 JS 桥。协议纯函数与三件工具执行器在 providers/ToolBrowse.ets（读域）与
//   providers/ToolBrowseAct.ets（动作域）。
// ★ 环纪律：本文件不 import ToolTypes / ToolBrowse / ToolBrowseAct（下游 → 宿主单向；
//   ChatToolRoundCtrl 宿主接口同款防环姿势）——onLoadIntercept 的协议白名单在本文件内
//   自持一份与 ToolBrowse.isHttpUrl 同口径的判定（双写两处，注释互指 + app 域 107 组
//   同口径钉防漂移）。
// ★ 2026-09-18 修复笔（深挖卷开工单 #0/#2④/#9，docs/调研-内置浏览器深挖卷-隐形宿主与
//   诊断探针-20260918.md）：事件面 11 → 20 枚（FCP/FMP 绘制信号、主/子资源分流 + 错误码
//（onHttpErrorReceive / onSslErrorEvent 两口自 2026-09-21 笔 B 起补主/子分流；onErrorReceive
//  自 2026-09-18 #2④ 起已分流——三口口径至此一致）、
//   SSL、渲染进程退出、blankScreen 调试期、导航起止、进度、宿主可见比）+ 命令历史环形
//   缓冲（失败诊断与探针用）+ runJavaScript 兜底正文通道 + 构建期 DevTools 调试开关。
// ★ 2026-09-18 三轮修复（#11，真机二轮回证：getLiteDom 对本宿主恒不返 text 字段——
//   wants 含 text 五连查全缺、id/tag/xpath/visible/rect/attributes 全返）：通用页面 JS
//   通道 runPageJs（元素标签旁路的地基，与兜底正文同通道）+ normalizeJsValue 归一提取
//   双通道共用（runFallbackText 行为不变）+ 命令历史连续同令合并（settle 采样轮逐轮推同
//   一条 getLiteDom 会把交互命令的 441 现场挤出环形——合并 = 刷新 raw/at 不占新槽）。
// 隐私分轨（决明拍板「分轨：普通落盘、隐私不留痕」）：incognitoMode 随挂载点 isPrivate
// 取值（ChatPage 透传，页面生命周期内恒定）——普通会话 Cookie/缓存按平台默认落盘
//（应用私有沙箱），隐私会话不写盘、宿主销毁即清。禁在服务层另设「隐私开关」造成两套
// 真相（红线 7）。
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { CHAT_ACTIVE_CONV_KEY } from './providers/ToolChatSearch';

// 导航等待（任务书 §6.4）：事件置位 + 有界轮询（P1-3 红线——禁裸 sleep，80ms 步长照
// DocumentParse 的 POLL_STEP_MS 先例量级，20s 上限按慢站点实测波动的 ~2 倍设）
export const BROWSE_NAV_TIMEOUT_MS: number = 20000;
export const BROWSE_POLL_STEP_MS: number = 80;
// ── 修复笔常量（深挖卷 §五/§六）──
// 构建期诊断总开关（#0）：true 时 blankScreen 检测生效（引擎每页 1/3/5s 各检一次有开销，
// 深挖卷 §五·5）+ onVisibleAreaChange 记录宿主可见比 + DevTools 远程调试端口开放
//（setWebDebuggingAccess 官方明示「正式发布版本建议不开启」）。默认 false 不进产物常态；
// 真机诊断轮临时翻 true 重构建，诊断完复位（宪法「应用内自检已全量退役」下的正路 =
// 构建期开关，探针不进产物常态）
export const BROWSE_DEBUG: boolean = false;
// DevTools 远程调试端口（BROWSE_DEBUG=true 时生效；电脑 Chrome chrome://inspect →
// Configure 填「设备 IP:8888」直连隐形宿主看 Elements/Console/Network/Performance——
// 深挖卷 §1.3「页面到底是什么」从推断变直读；端口禁 0~1024，官方 since 20 形态）
export const BROWSE_DEVTOOLS_PORT: number = 8888;
// 命令历史环形缓冲容量（#2③/#0：失败回传原始件与探针 JSON 的数据源；只存内存随页覆写，
// 无落盘）。#11 起 5 → 8：连续同令合并落地后 settle 采样轮只占一槽，容量余量留给
//「preflight 取语义 → 交互命令 → settle 采样 → 回执元素重取」的完整现场链
export const BROWSE_CMD_HISTORY_MAX: number = 8;
// 命令历史条目（cmd/raw 均预截断——环形缓冲有界，内存防线「数据有界」）
export interface BrowseCmdRecord {
  cmd: string;
  raw: string;
  at: number;
}
// 导航周期诊断信号（#0 探针原语；每页导航复位，见 openPage）
export interface BrowseNavSignals {
  fcpMs: number;           // 首次内容绘制耗时（-1 = 未触发——本身就是信息：没绘制过）
  fmpMs: number;           // 首次有意义绘制耗时（-1 = 未触发）
  lastProgress: number;    // 最近加载进度（0~100；「卡在 60%」类半加载判据）
  pageHeight: number;      // 控制器 getPageHeight()（-1 = 控制器不可用；≈视口高 ⇒ 布局未发生）
  renderExited: boolean;   // 渲染进程是否异常退出（页面突然空了的第一嫌疑）
  hostVisibleRatio: number; // 宿主可见面积比（-1 = 未记录；调试期 onVisibleAreaChange 回填）
  blankScreenNote: string; // 引擎白屏判定（'' = 未判定/未开启；调试期）
}

// 当前页状态（单槽——只保留最近一次打开页、每次导航覆写、不累积；浏览历史不落库）
export interface BrowsePageState {
  url: string;
  title: string;
  text: string;
  // 归属会话（打开时的 CHAT_ACTIVE_CONV_KEY 值）——browse_read 据此校验跨会话不串页
  convId: string;
  at: number;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

// 命令/响应片段截断（历史条目预截断——探针输出与环形缓冲双有界）
function clipForHistory(text: string, maxChars: number): string {
  return text.length > maxChars ? text.substring(0, maxChars) + '…' : text;
}

// runJavaScript 返回值归一（#11 提取，runFallbackText/runPageJs 双通道共用——行为与提取
// 前一致）：引擎差异可能给结果多裹一层 JSON 引号（DocumentParse normalizeRunJavaScriptResult
// 同款两层剥法）；undefined/null → ''；剥到的内容非字符串（如裹的是数组 JSON）保持原样返回
function normalizeJsValue(value: string | undefined | null): string {
  if (value === undefined || value === null) {
    return '';
  }
  let normalized: string = value.toString().trim();
  for (let i: number = 0; i < 2; i++) {
    if (!((normalized.startsWith('"') && normalized.endsWith('"')) ||
      (normalized.startsWith("'") && normalized.endsWith("'")))) {
      return normalized;
    }
    try {
      const parsed: Object = JSON.parse(normalized);
      if (typeof parsed !== 'string') {
        return normalized;
      }
      normalized = (parsed as string).trim();
    } catch (e) {
      return normalized;
    }
  }
  return normalized;
}

// ── 失败归因文案（纯函数；2026-09-21 任务书-浏览器失败归因-20260921 笔 B）──
// 本域此前把主资源加载失败一律压成同一句猜测式归因（把「站点限制」与「需要登录」硬套在网络层
// 失败上）——原因不可指认：域名解析失败与站点反爬落在同句，模型据此把网络故障当成站点行为。
// 三件纯函数的唯一消费者 = 本文件 BrowseService 的旁注方法与 openPage 超时句；码源 =
// 官方 WebNetErrorList（本地 SDK api/@ohos.web.netErrorList.d.ts，Chromium 网络栈语义）。
// ★ 与 providers/WebSearchParse 的 httpKitErrorMessage 是两张表（http kit 码为 23xxxxx 正数，
//   本表为 Chromium 负数码），禁互相搬运或合并。

// 浏览器网络层错误码 → 中文原因（纯函数；未列码返 ''，由 browseLoadFailureNote 走中性兜底句）。
// 覆盖真机常见族：连接与解析（-2/-7/-101/-102/-104/-105/-106/-109/-118/-137/-138）、
// 证书（-107/-201/-202/-207）、地址与响应（-300/-301/-302/-310/-379）；其余码不臆断。
// ★ -301/-302 分列（2026-09-21 自检轮修）：官方 ERR_DISALLOWED_URL_SCHEME（协议被禁止）
// 与 ERR_UNKNOWN_URL_SCHEME（协议未知）是两条语义——原表把 -301 释作「不支持」且漏 -302
export function browseNetErrorMessage(code: number): string {
  if (code === -2) {
    return '网页加载失败，未得到具体原因';
  }
  if (code === -7) {
    return '加载超时，服务器响应太慢';
  }
  if (code === -101) {
    return '连接被重置，可能是网络不稳定';
  }
  if (code === -102) {
    return '服务器拒绝连接，可能是该地址未开放服务';
  }
  if (code === -104) {
    return '连接服务器失败';
  }
  if (code === -105) {
    return '域名解析失败，可能是网址拼写有误或当前网络不可用';
  }
  if (code === -106) {
    return '设备当前没有网络连接';
  }
  if (code === -109) {
    return '无法访问该地址，网络不可达';
  }
  if (code === -118) {
    return '连接超时，服务器没有在预期时间内响应';
  }
  if (code === -137) {
    return '域名解析失败，可能是当前网络不可用';
  }
  if (code === -138) {
    return '网络访问被拒绝，可能是防火墙或系统限制';
  }
  if (code === -107) {
    return '安全连接建立失败，可能是 SSL 协议不兼容';
  }
  if (code === -201) {
    return '安全证书已过期或未生效';
  }
  if (code === -202) {
    return '安全证书不受信任，可能网络被代理或站点使用自签证书';
  }
  if (code === -207) {
    return '安全证书无效';
  }
  if (code === -300) {
    return '网址格式无效';
  }
  if (code === -301) {
    return '该网址的协议已被禁止访问';
  }
  if (code === -302) {
    return '不支持该网址的协议';
  }
  if (code === -310) {
    return '重定向次数过多，已停止跳转';
  }
  if (code === -379) {
    return '站点返回了错误状态码';
  }
  return '';
}

// 主资源加载失败旁注句（纯函数）：中文原因在前，原始码与引擎信息作括注保留（模型可回证、
// 诊断可对码）。未列码走中性句——不得再用猜测式归因把网络故障说成站点行为
export function browseLoadFailureNote(code: number, info: string): string {
  const reason: string = browseNetErrorMessage(code);
  const head: string = reason !== '' ? '网页打不开，' + reason : '网页打不开，可能是网络问题或站点无法访问';
  const detail: string = info !== '' ? '（错误码 ' + code + '：' + info + '）' : '（错误码 ' + code + '）';
  return head + detail;
}

// 主资源 HTTP 错误响应旁注句（纯函数）：状态码 + 中文释义（未列码只报码，不臆断）+ 服务器原因
export function browseHttpStatusText(code: number, reason: string): string {
  const gloss: string = browseHttpStatusGloss(code);
  const detail: string = reason !== '' ? '（服务器返回 ' + reason + '）' : '';
  return '网页返回 HTTP ' + code + (gloss !== '' ? '，' + gloss : '') + detail;
}

// HTTP 状态码中文释义（私有；未列码返 ''）：只列真机常见族——拒绝 / 未找到 / 需要登录 /
// 限流 / 服务端错误。禁把未列码猜成某类原因（错归因比不归因更糟）
function browseHttpStatusGloss(code: number): string {
  if (code === 400) {
    return '请求无效';
  }
  if (code === 401) {
    return '需要登录';
  }
  if (code === 403) {
    return '服务器拒绝访问';
  }
  if (code === 404) {
    return '页面未找到';
  }
  if (code === 405) {
    return '该请求方法不被允许';
  }
  if (code === 408) {
    return '服务器等待请求超时';
  }
  if (code === 429) {
    return '请求过于频繁，被站点限流';
  }
  if (code === 500) {
    return '服务器内部错误';
  }
  if (code === 502) {
    return '网关错误';
  }
  if (code === 503) {
    return '服务暂不可用';
  }
  if (code === 504) {
    return '网关超时';
  }
  return '';
}

// ── 浏览服务单例（控制器由宿主组件 onControllerAttached 注入）──

class BrowseService {
  private controller: webview.WebviewController | null = null;
  // 就绪语义 = 「当前页已载完」，非「曾经载完」（DocumentParse 2026-09-11 笔 4 同款教训：
  // onControllerAttached 复位 / onPageEnd 置位成对，不复位会让首次命令撞未载完页）
  private isReady: boolean = false;
  // 串行队列：单 Web 实例是有状态资源（工具轮默认并发，ChatToolRoundCtrl Promise.all），
  // 所有浏览操作经此排队（红线 4；形制照 DocumentParse.queueTail，前序失败不断链）
  private queueTail: Promise<void> = Promise.resolve();
  private page: BrowsePageState | null = null;
  // 当前页加载期事件面的旁注（拦截/下载/弹窗/错误——进结果 JSON 的 note 呈现给模型；
  // 每次导航前清空，防上一页的错误串页）
  private pendingError: string = '';
  // 子资源失败标记（#2④ D6：图/字体 404 不再顶替主资源旁注误导方向——仅主旁注空时呈现）
  private subResourceError: string = '';
  // 命令历史环形缓冲（#2③/#0——失败诊断「原始命令+原始响应」的唯一来源，此前一个都没留）
  private cmdHistory: BrowseCmdRecord[] = [];
  // 导航周期诊断信号位（#0；openPage 复位、事件回调回填）
  private fcpMs: number = -1;
  private fmpMs: number = -1;
  private lastProgress: number = 0;
  private renderExited: boolean = false;
  private hostVisibleRatio: number = -1;
  private blankScreenNote: string = '';

  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
  }

  markReady(): void {
    this.isReady = true;
  }

  markUnready(): void {
    this.isReady = false;
  }

  // ── 事件面旁注（宿主回调进；文案 = 任务书 §2.6 表 + 修复笔 #2④，模型阅读面）──
  // 主资源加载失败（#2④ 起带 getErrorCode；2026-09-21 笔 B 起经 browseLoadFailureNote 出中文
  // 原因——句首即原因，未列码走中性句，不再用猜测式归因。码表见该函数）
  noteLoadError(code: number, info: string): void {
    this.pendingError = browseLoadFailureNote(code, info);
  }

  // HTTP 错误响应（4xx/5xx）：★ 2026-09-21 笔 B 加 isMainFrame 分流——此前子资源（图片、
  // 字体、favicon）的 404 也写进主旁注，既冒充页面故障、又会顶掉已写入的主资源错误（真机
  // 实证 = 变更记录八百一十五节第 ⑧ 项：探针服务的 favicon 404 被写成页面故障）。子资源
  // 走轻量通道（主旁注空时才呈现），与 #2④ D6 对 onErrorReceive 的分流口径对齐
  noteHttpError(code: number, reason: string, isMainFrame: boolean): void {
    if (!isMainFrame) {
      this.noteSubResourceError(code);
      return;
    }
    this.pendingError = browseHttpStatusText(code, reason);
  }

  // 子资源失败单独成句且不喧宾夺主（D6 修法②：仅主旁注空时经 takePendingNote 呈现；
  // 2026-09-21 笔 B：首写者优先逻辑抽为此方法，供子资源 HTTP 失败复用；SSL 子资源句走覆盖通道（B-13））
  noteSubResourceError(code: number): void {
    this.noteSubResourceOnce('页面部分资源加载失败（错误码 ' + code + '），内容可能不完整');
  }

  // 子资源通道首写者优先（多起子资源失败只报首起——呈现面只给一句，报一堆无益；
  // HTTP 子资源；证书句见 noteSsl）
  private noteSubResourceOnce(text: string): void {
    if (this.subResourceError === '') {
      this.subResourceError = text;
    }
  }

  // SSL 证书校验失败（#2④ 起已接；★ 2026-09-21 笔 B 加 isMainFrame 分流——官方明示本事件
  // 覆盖主 frame 与子 frame「To handle SSL errors for requests for the main frame, use the
  // isMainFrame field to distinguish」（component/web.d.ts onSslErrorEvent 文档），子 frame
  // 证书失败（页面内第三方图片/字体）此前会冒充整页失败并把「已停止加载」写进主旁注。
  // 主 frame 句逐字不变（该情形确为整页停载）；子 frame 走轻量通道
  noteSsl(isMainFrame: boolean): void {
    if (!isMainFrame) {
      // 子资源通道优先级（2026-09-21 B-13）：证书校验失败属安全事件，可覆盖低危句
      //（图片 favicon 404 先到不得吞掉它）；反向不覆盖——HTTP 句仍走首写者通道
      //（noteSubResourceOnce），证书句先到则 HTTP 句按「只报首起」丢弃。
      this.subResourceError = '页面部分资源的安全证书校验失败，已取消加载';
      return;
    }
    this.pendingError = '网页安全证书校验失败，已停止加载，可能网络被代理或证书异常';
  }

  // 渲染进程异常退出（#0 事件面：页面突然空了的第一嫌疑，必复位就绪态防后续命令假死）
  noteRenderExited(): void {
    this.renderExited = true;
    this.isReady = false;
    this.pendingError = '页面渲染进程异常退出，请重新打开网页';
  }

  noteIntercept(url: string): void {
    this.pendingError = '页面尝试跳转到不支持的地址，已拦截：' + url;
  }

  noteDownload(url: string): void {
    this.pendingError = '页面触发了文件下载，已忽略';
  }

  noteDialog(kind: string): void {
    this.pendingError = '页面弹出了' + (kind === 'alert' ? '提示框' : kind === 'confirm' ? '确认框' : '输入框') +
      '，已自动取消';
  }

  noteNewWindow(url: string): void {
    this.pendingError = '页面尝试打开新窗口，已忽略：' + url;
  }

  // 引擎白屏判定（调试期 BROWSE_DEBUG 才可能触发；「从未回调」本身也是信息）
  noteBlankScreen(reason: string): void {
    this.blankScreenNote = reason;
  }

  takePendingNote(): string {
    if (this.pendingError !== '') {
      return this.pendingError;
    }
    return this.subResourceError;
  }

  // ── 诊断信号位（#0；事件回调回填——各 mark 仅导航周期内首次有效）──
  markFcp(ms: number): void {
    if (this.fcpMs < 0) {
      this.fcpMs = ms;
    }
  }

  markFmp(ms: number): void {
    if (this.fmpMs < 0) {
      this.fmpMs = ms;
    }
  }

  markProgress(progress: number): void {
    this.lastProgress = progress; // 压制噪声：只记最新值不进旁注，探针读取
  }

  markHostVisibleRatio(ratio: number): void {
    this.hostVisibleRatio = ratio;
  }

  getNavSignals(): BrowseNavSignals {
    let pageHeight: number = -1;
    if (this.controller !== null) {
      try {
        pageHeight = this.controller.getPageHeight();
      } catch (e) {
        pageHeight = -1; // 控制器未关联页面等异常态——探针如实回 -1
      }
    }
    return { fcpMs: this.fcpMs, fmpMs: this.fmpMs, lastProgress: this.lastProgress,
      pageHeight: pageHeight, renderExited: this.renderExited,
      hostVisibleRatio: this.hostVisibleRatio, blankScreenNote: this.blankScreenNote };
  }

  getCommandHistory(): BrowseCmdRecord[] {
    return this.cmdHistory.slice(); // 拷贝出栈（调用方改不动内部缓冲）
  }

  private recordCommand(cmd: string, raw: string): void {
    // 连续同令合并（#11）：settle 采样轮与就绪等待轮逐轮推入的是同一条 getLiteDom——
    // 旧逐轮推入会把交互命令（type/click 的 441 现场）挤出环形，debug 永远看不到它；
    // 合并语义 = 刷新最新 raw/at 不占新槽位（「最近一条同命令的最新结果」）
    const clippedCmd: string = clipForHistory(cmd, 200);
    const last: BrowseCmdRecord | undefined = this.cmdHistory.length > 0 ?
      this.cmdHistory[this.cmdHistory.length - 1] : undefined;
    if (last !== undefined && last.cmd === clippedCmd) {
      last.raw = clipForHistory(raw, 300);
      last.at = Date.now();
      return;
    }
    this.cmdHistory.push({ cmd: clippedCmd, raw: clipForHistory(raw, 300), at: Date.now() });
    if (this.cmdHistory.length > BROWSE_CMD_HISTORY_MAX) {
      this.cmdHistory.shift(); // 环形语义：只留最近 N 条（内存防线「数据有界」）
    }
  }

  // 串行入口（所有浏览操作经此排队）：task 在队尾执行，返回值原样透传
  queued<T>(task: () => Promise<T>): Promise<T> {
    const run: Promise<T> = this.queueTail.then(task, task);
    this.queueTail = run.then((): void => {}, (): void => {});
    return run;
  }

  // 导航（排队内执行）：清旧页与旧旁注 → 复位就绪与诊断信号 → loadUrl → 等 onPageEnd
  // 置位。失败面（中文、终态、不静默）：宿主未挂载 / 超时；onErrorReceive 类错误走
  // pendingError 旁注进结果不阻断（子资源失败 onPageEnd 照发）
  async openPage(url: string): Promise<void> {
    if (this.controller === null) {
      throw new Error('浏览器尚未就绪，请稍后重试');
    }
    this.page = null; // 导航即弃旧页：失败后旧页不可再读（防读到「模型以为是新页」的旧内容）
    this.pendingError = '';
    this.subResourceError = '';
    this.isReady = false;
    this.fcpMs = -1;
    this.fmpMs = -1;
    this.lastProgress = 0;
    this.renderExited = false;
    this.blankScreenNote = '';
    this.controller.loadUrl(url);
    const start: number = Date.now();
    while (!this.isReady) {
      if (Date.now() - start > BROWSE_NAV_TIMEOUT_MS) {
        // 超时句可指认（2026-09-21 笔 B）：报出实际等待秒数；若事件面已写入具体原因
        //（如 onErrorReceive 的 -118），以其为线索收尾（非成因：弹窗/新窗口/下载三类也
        // 写该字段，故标签与因果表述解耦——2026-09-21 B-12）
        const waited: number = Math.max(1, Math.round(BROWSE_NAV_TIMEOUT_MS / 1000));
        const tail: string = this.pendingError !== '' ?
          '，页面期间另有动作：' + this.pendingError : '，可能是网络较慢或站点无响应';
        throw new Error('网页加载超时，等待 ' + waited + ' 秒仍未完成加载' + tail);
      }
      await sleep(BROWSE_POLL_STEP_MS);
    }
  }

  // AI 页面命令薄封装：空串 = 网页不可用/命令无法执行（官方明示）；17100001 控制器未关联 /
  // 17100024 命令格式错（自检面）按 d.ts 错误码映射。命令与响应进环形历史（#2③）
  async runCommand(command: string): Promise<string> {
    return this.executeCommand(command, true);
  }

  // 交互命令通道（P2，2026-09-18）：与查询命令的唯一差异 = 空串语义——操作类命令
  //（click/type/send_keys）成功时官方明示返回空串，runCommand 的「空串即抛」会把成功
  // 当失败（04 篇 A1 空串三义合一）；此处空串原样返回交上层按码表与采样判定，
  // {code,error} 失败形态与异常的错误映射两通道一致
  async runInteractionCommand(command: string): Promise<string> {
    return this.executeCommand(command, false);
  }

  private async executeCommand(command: string, emptyIsError: boolean): Promise<string> {
    if (this.controller === null) {
      throw new Error('浏览器尚未就绪，请稍后重试');
    }
    let raw: string = '';
    try {
      raw = await this.controller.executeAIPageCommand(command);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === 17100001) {
        throw new Error('浏览器尚未就绪，请稍后重试');
      }
      if (err.code === 17100024) {
        throw new Error('内部命令格式错误');
      }
      throw new Error('页面命令执行失败：' + err.message);
    }
    this.recordCommand(command, raw);
    if (raw === '' && emptyIsError) {
      throw new Error('页面未就绪或命令无法执行，请重新打开网页');
    }
    return raw;
  }

  // 兜底正文通道（#9 深挖卷 §6：官方 getLiteDom 抽取面真空时退 runJavaScript 直读
  // body.innerText——同 Web 实例同串行队列，调用方保证排队内调用）。失败回空串不抛
  //（兜底失败交主流程统一收口）
  async runFallbackText(): Promise<string> {
    if (this.controller === null) {
      return '';
    }
    try {
      return normalizeJsValue(await this.controller.runJavaScript(
        'document.body ? document.body.innerText : ""') as string | undefined);
    } catch (e) {
      return '';
    }
  }

  // 通用页面 JS 通道（#11：getLiteDom 对本宿主恒不返 text 字段——两轮真机铁证〔wants
  // 含 text 五连查全缺，id/tag/xpath/visible/rect/attributes 全返〕——元素标签旁路 = 域件
  // 组装脚本经此执行）。失败/控制器缺位回空串不抛（旁路退化 = 无文本，不阻断主流程）；
  // 调用方保证排队内调用（与 runFallbackText 同纪律）
  async runPageJs(script: string): Promise<string> {
    if (this.controller === null) {
      return '';
    }
    try {
      return normalizeJsValue(await this.controller.runJavaScript(script) as
        string | undefined);
    } catch (e) {
      return '';
    }
  }

  // 就绪态只读查询（P2 settle 采样循环用——域件 settleAfterAction 每步先看是否导航中）
  isPageReady(): boolean {
    return this.isReady;
  }

  // 旁注排空（P2：动作可能触发导航，动作前清旧旁注防上一页错误串页——openPage 内
  // 同款语义的公开面；导航中产生的新旁注照常进结果 note）
  clearPendingNote(): void {
    this.pendingError = '';
    this.subResourceError = '';
  }

  // 会话归属校验（任务书 §1.6-2 新增）：浏览页是全局单实例内存态，跨会话读页 = 静默给错
  // 结果（A 为隐私会话时构成内容泄漏）——browse_read 每次先过此校验。不符与无页同句
  //（不暴露「别的会话有页面」这一信息）；'' = 通过
  assertOwnership(): string {
    if (this.page === null) {
      return '当前会话没有已打开的页面，请先调用「打开网页」';
    }
    const active: string = AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? '';
    if (active === '' || active !== this.page.convId) {
      return '当前会话没有已打开的页面，请先调用「打开网页」';
    }
    return '';
  }

  // 当前页提交（抽取完成后由执行器调用）：convId 由执行器在工具边界快照传入，禁在此自读
  // 中转键——openPage 加重试可达 20 秒级，任务期间用户切会话再发送会改写键值，晚读即把
  // A 会话打开的页归属到 B（A 续读被挡、B 反而能读，正破 assertOwnership 所防的串页；
  // 坑58/P-19 口径——值在消息边界取）。读侧 assertOwnership 仍现读现判（读时按当前会话判）
  commitPage(url: string, title: string, text: string, convId: string): void {
    this.page = { url: url, title: title, text: text, convId: convId, at: Date.now() };
  }

  currentPage(): BrowsePageState | null {
    return this.page;
  }
}

export const browseService: BrowseService = new BrowseService();
export const browseController: webview.WebviewController = new webview.WebviewController();

// 失败回执诊断信号（2026-09-20 任务书-浏览器失败回执附诊断信号执行笔）：三侧执行器 catch
// 调用——open 路径页面未提交（openPage 已清 page，无页可判）传执行器在工具边界快照的
// convId；read/act 路径传 '' 走页面归属校验。归属不成立返回 null（调用方不写 signals 键）
// ——防排队期间切会话把 A 会话的导航信号串给 B（坑58/P-19 口径：值在消息边界取；本函数
// 在 catch 内同步执行，不跨等待）。字段与 browse_read mode=debug 探针逐字同源（模型零学习
// 成本）；恒全字段写入——「全 -1」本身就是「导航未发生/未绘制」的信息（探针判据表第一
// 分叉），不做「有无内容」二次判据（形态恒定优于条件省略）
export function browseFailureSignals(originConvId: string): Record<string, Object> | null {
  const active: string = AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? '';
  if (originConvId !== '') {
    if (active === '' || active !== originConvId) {
      return null; // open 路径：排队期间切会话——不附
    }
  } else if (browseService.assertOwnership() !== '') {
    return null; // read/act 路径：无页或跨会话——不附
  }
  const signals: BrowseNavSignals = browseService.getNavSignals();
  const rec: Record<string, Object> = {};
  rec['pageHeight'] = signals.pageHeight;
  rec['firstContentfulPaintMs'] = signals.fcpMs;
  rec['firstMeaningfulPaintMs'] = signals.fmpMs;
  rec['lastProgress'] = signals.lastProgress;
  rec['renderExited'] = signals.renderExited;
  rec['hostVisibleRatio'] = signals.hostVisibleRatio;
  rec['blankScreen'] = signals.blankScreenNote;
  return rec;
}

// onLoadIntercept 的协议白名单（★ 与 providers/ToolBrowse.isHttpUrl 同口径双写——环纪律
// 本文件不引域件；107 组两侧同口径钉）。主文档导航与子资源全过此回调，只放行 http/https
function isHttpSchemeUrl(url: string): boolean {
  const lower: string = url.trim().toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

// ── 隐形宿主组件（ChatPage Content 内挂载，与 DocParserHost 同域 sibling）──
// 满视口 + opacity(0) + 屏内叠层（Stack 声明序在消息流之前 = 被实体 UI 盖住，官方明说
// 「被遮挡组件系统不会终止其行为」——非屏幕外降级档）+ 命中穿透。★ 形态 B（2026-09-18
// 决明拍板切离屏 A → 屏内被盖 B，#6 落地）：A 形态 position(-9999) 离屏真机实锤内核
// AI 命令面被降级（定位 421 / 键盘空转 / getLiteDom text 恒缺，六轮旁路修法见变更记录
// 七百四十四~七百五十节）；B 形态验证点 = ①用户界面零影响（被盖住 + 透明 + 穿透三保险）
// ②全链行为不回退 ③内核降级面是否恢复（恢复则后续可评估退役部分旁路；不恢复则确证
// 降级与位置无关）。✅ 真机判定（2026-09-18 决明回证「暂没发现问题」）：界面零影响 +
// 全链不回退通过，B 形态转正；内核降级面是否恢复待长观察（全记录档 =
// docs/归档/专题-内置浏览器修复全记录-20260918.md）。
// 事件面十八枚 = 就绪三件（附着复位/onPageBegin 复位/onPageEnd 置位）+ 错误四件
//（onHttpErrorReceive / onSslErrorEvent 两口自 2026-09-21 笔 B 起补主子分流、onErrorReceive 自
//  #2④ 起已分流 + 错误码 / 渲染退出）+
// 绘制两件（FCP/FMP）+ 进度 + 拦截/下载 + 弹窗三件 + 新窗口 + 白屏判定（调试期）+
// 宿主可见比（调试期）。（onLoadStarted/onLoadFinished 在深挖卷补齐清单里，但就绪语义
// 与 onPageEnd 重叠、无独立消费者，按 P2-4 不挂——真机若需 fragment 导航信号再补。）
// 弹窗三件恒 return true（应用自处理
// → 不弹系统默认框）且随即 handleCancel 回结果（只 return 不回调 JsResult 会让页面脚本
// 悬停；false 分支语义是「弹窗处理作废」非「自动取消」，易读岔——统一走 true 分支）。
// 新窗口不创建（multiWindowAccess 保持默认 false 不写），setWebController 按官方形态显式
// 告知「没有新窗口」（d.ts：不调用会阻塞渲染进程；形参非可选不收 null——传未挂载任何
// Web 的占位控制器，即「无新窗口」的等价表达）。
@Component
export struct BrowseHost {
  isPrivate: boolean = false; // ChatPage 以 this.isPrivate 传入（页面生命周期内恒定）
  build() {
    // incognitoMode 是 Web 构造参（WebOptions 字段，component/web.d.ts）非链式属性——
    // 分轨开关在构造期定死（页面生命周期内恒定，与 isPrivate 语义一致）
    Web({ src: 'about:blank', controller: browseController, incognitoMode: this.isPrivate })
      .width('100%')
      .height('100%')
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .backgroundColor(Color.Transparent)
      .javaScriptAccess(true)
      .fileAccess(false)
      .blankScreenDetectionConfig({ enable: BROWSE_DEBUG, detectionTiming: [1.0, 3.0, 5.0] })
      .onControllerAttached(() => {
        browseService.attachController(browseController);
        // 新 Web 附着即复位就绪（DocumentParse 2026-09-11 笔 4 同款双向 fail-safe）
        browseService.markUnready();
        // DevTools 远程调试（#0）：构建期开关，正式产物恒关（官方安全提示「正式发布版本
        // 建议不开启」）；调试包开放 TCP 端口，电脑 Chrome chrome://inspect 直连隐形宿主
        if (BROWSE_DEBUG) {
          try {
            webview.WebviewController.setWebDebuggingAccess(true, BROWSE_DEVTOOLS_PORT);
          } catch (e) {
            // 端口被占等异常不打断宿主生命周期（诊断通道缺失不影响功能面）
          }
        }
      })
      .onProgressChange((e: OnProgressChangeEvent) => {
        browseService.markProgress(e.newProgress);
      })
      .onFirstContentfulPaint((e: OnFirstContentfulPaintEvent) => {
        // 首次内容绘制（#0/#3）：「页面是否真的绘制过一次内容」的官方信号——探针判据
        // 表首行（FCP 未触发 ∧ rect 缺失 ⇒ 渲染/布局未发生 → 宿主形态 A/B）
        browseService.markFcp(e.firstContentfulPaintMs);
      })
      .onFirstMeaningfulPaint((e: FirstMeaningfulPaint) => {
        // 有意义的首绘（比 FCP 更接近「内容就绪」；官方结构 firstMeaningfulPaintTime）
        if (e.firstMeaningfulPaintTime !== undefined) {
          browseService.markFmp(e.firstMeaningfulPaintTime);
        }
      })
      .onPageBegin(() => {
        // P2（2026-09-18）：动作触发的导航（click 跳转、表单提交）不复位 isReady，settle
        // 采样无法感知「正在跳转」；onPageBegin 主文档事件与 onPageEnd 成对后，settle 循环
        // 的 isReady 翻转检测可复用（openPage 自持 markUnready，重复复位无害）
        browseService.markUnready();
      })
      .onPageEnd(() => {
        browseService.markReady();
      })
      .onErrorReceive((e: OnErrorReceiveEvent) => {
        // #2④ D6 修复：主/子资源分流 + 错误码——子资源（图/字体）失败不再顶替主资源
        // 旁注把模型引向「站点拦截」的错误方向；主资源失败带 netErrorList 码义
        if (e.request.isMainFrame()) {
          browseService.noteLoadError(e.error.getErrorCode(), e.error.getErrorInfo());
        } else {
          browseService.noteSubResourceError(e.error.getErrorCode());
        }
      })
      .onHttpErrorReceive((e: OnHttpErrorReceiveEvent) => {
        // 2026-09-21 笔 B：主/子分流——子资源（favicon/图片/字体）的 HTTP 错误不再冒充页面故障
        browseService.noteHttpError(e.response.getResponseCode(), e.response.getReasonMessage(),
          e.request.isMainFrame());
      })
      .onSslErrorEvent((e: SslErrorEvent) => {
        // #2④：SSL 失败（企业代理/自签证书/中间人）——此前完全未接、旁注里无声；
        // 恒取消加载（handleCancel，官方建议；不接受来路不明的证书）。
        // ★ 2026-09-21 笔 B：isMainFrame 分流（官方明示本事件覆盖主/子 frame）
        e.handler.handleCancel();
        browseService.noteSsl(e.isMainFrame);
      })
      .onRenderExited(() => {
        // 渲染进程异常退出（#0 事件面）：页面突然空了的第一嫌疑
        browseService.noteRenderExited();
      })
      .onDetectedBlankScreen((e: BlankScreenDetectionEventInfo) => {
        // 引擎白屏判定（#0，仅 BROWSE_DEBUG 时可能触发）：reason 为官方枚举值，
        // details 含命中内容节点数——判据表「渲染了但没内容」分支
        browseService.noteBlankScreen('码 ' + e.blankScreenReason +
          (e.blankScreenDetails !== undefined ? ' 详情 ' + JSON.stringify(e.blankScreenDetails) : ''));
      })
      .onVisibleAreaChange([0.0, 1.0], (isExpanding: boolean, currentRatio: number) => {
        // 宿主可见面积比（#0 调试期信号：「系统认不认为它不可见」的直接读数——离屏
        // position 下预期恒 0，Stack 满视口形态下预期 1，A/B 判别的基线数据）
        browseService.markHostVisibleRatio(Math.round(currentRatio * 100) / 100);
      })
      .onLoadIntercept((e: OnLoadInterceptEvent): boolean => {
        const url: string = e.data.getRequestUrl();
        if (!isHttpSchemeUrl(url)) {
          browseService.noteIntercept(url);
          return true;
        }
        return false;
      })
      .onDownloadStart((e: OnDownloadStartEvent) => {
        browseService.noteDownload(e.url);
      })
      .onAlert((e: OnAlertEvent): boolean => {
        browseService.noteDialog('alert');
        e.result.handleCancel();
        return true;
      })
      .onConfirm((e: OnConfirmEvent): boolean => {
        browseService.noteDialog('confirm');
        e.result.handleCancel();
        return true;
      })
      .onPrompt((e: OnPromptEvent): boolean => {
        browseService.noteDialog('prompt');
        e.result.handleCancel();
        return true;
      })
      .onWindowNew((e: OnWindowNewEvent) => {
        browseService.noteNewWindow(e.targetUrl);
        e.handler.setWebController(new webview.WebviewController());
      })
  }
}

// 宿主销毁不接显式清理（ChatPage.aboutToDisappear 无对应动作）：页面销毁后控制器引用随
// 新宿主 onControllerAttached 重附着覆盖；期间旧引用上的命令按 17100001 → 「浏览器尚未
// 就绪」可读收口，不崩链——前台约束语义，任务书 §7-6
