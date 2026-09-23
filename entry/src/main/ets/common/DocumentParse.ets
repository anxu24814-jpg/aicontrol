// 文档附件解析域（2026-09-03 Cube 吸收第三批②；源自 cubeagent-stream-test〔chatcube
// MIT 快照〕services/DocumentParseService.ets 裁剪移植 + aicontrol 附件链适配）：
// · 隐式 WebView 载荷 rawfile/document-parser/document-parser.html（mammoth〔docx〕/
//   pdfjs〔pdf〕/ SheetJS〔xls·xlsx〕/ jszip〔ofd〕四引擎，MIT 随 rawfile NOTICE）；
// · ArkTS 侧 runJavaScript 调 DocumentParserBridge.start/append/finish/getResult/cancel，
//   base64 256KB 分块注入 + 80ms 轮询取结果（45s 上限）+ ready 等待（5s 上限）；
// · 硬限制分型（DOCX 25M / Excel 20M / PDF·OFD 30M）+ 抽取上限 120K 字符；
// · 解析态机（idle/parsing/done/failed/toolarge）+ 发送阻断判定（未解析完不发——
//   防模型收到空附件，Cube DocumentParsePolicy 同语义）。
// 与 Cube 差异：Cube MessageAttachment 持久驻留 filesDir 且 parsed_text 随消息落库；
// aicontrol = cacheDir 副本发送即删、解析文本仅进内存随本轮请求（规避「文件永驻」坑，
// 调研卷04 §四），重发场景解析文本不落库（登记后置）。
// ★ 2026-09-15 附件 PDF 页渲染一期（任务书-附件PDF页渲染与视觉门控-20260915）：文字层太薄的
// PDF（扫描件）在解析时续做逐页渲染，页图（裸 base64 JPEG）随本轮请求进视觉通道——
// 渲染与解析**同属一个 promise 单元**（桥页是单任务状态机，另起异步会与下一件解析互踩；
// 队列语义由 parseAttachment 的 queueTail 天然守住）；判据 pdfTextThin 吃「纯正文长度 +
// 实际抽取页数」（★ 2026-09-15 收口笔：分母由全量页数改抽取页数，>200 页文字型文档不再被
// 摊薄误判扫描件）；渲染失败整批降级（不留半批）+ hilog 留痕，不抛错给上层（不让渲染问题
// 卡死发送链）。
// 宿主组件 DocParserHost 在本文件导出（ChatPage Content 内挂载；控制器/服务双单例——
// 全应用唯一解析通道，parse 串行由调用方保证：AttachmentPickCtrl 入列即排程）。
// ★ 2026-09-11 笔 4 就绪语义：isReady 含义 = 当前 Web 已载完桥页，不是「曾经载完过」
//（markReady/markUnready 成对——宿主 onPageEnd 置位 / onControllerAttached 复位两回调驱动）。
import { webview } from '@kit.ArkWeb';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { AiImagePart, PendingAttachment } from './providers/AiTypes';

const WEB_PARSER_URL: string = 'resource://rawfile/document-parser/document-parser.html';
const BASE64_CHUNK_SIZE: number = 256 * 1024;
const WEB_READY_TIMEOUT_MS: number = 5000;
const WEB_PARSE_TIMEOUT_MS: number = 45000;
// 轮询步长（Cube :195/:251 同值 80ms——P1-3 口径：解析结果无就绪回调，轮询为兜底，
// 上限 45s 有界）
const POLL_STEP_MS: number = 80;

// ── PDF 页渲染参数（2026-09-15 附件 PDF 页渲染一期）──
// 单件渲染页数上限（拍板①：30 页/件；同轮多件按附件顺序各件各自 30 页，不设轮次合计闸）。
// ★ 本常量是唯一来源，经 renderPages(maxPages) 入参传给桥页——桥页不设第二常量（防两处漂移）
export const RENDER_MAX_PAGES: number = 30;
// 页图长边（px；仅文档口径——桥页侧同名常量作渲染参数，两处各一份、注释互指，判据不看它）
export const PAGE_IMAGE_LONG_EDGE_PX: number = 1600;
// 扫描件判据（拍板②：全文 < 300 字符 或 页均 < 50 字符）
export const SCAN_TEXT_MIN_CHARS: number = 300;
export const SCAN_TEXT_MIN_PER_PAGE: number = 50;
// 页图 MIME（canvas.toDataURL('image/jpeg') 产物；pagemap 元素恒此值）
export const PAGE_IMAGE_MIME: string = 'image/jpeg';
// 页渲染轮询上限（初值照解析口径 45s；页图拉取含逐页 runJavaScript 回传，30 页渲染实测
// 耗时以任务书 §2.8 真机校准）
export const RENDER_TIMEOUT_MS: number = 45000;

// 分型硬上限（字节）与抽取上限（Cube DocumentParseLimits 同值）
const DOCX_HARD_BYTES: number = 25 * 1024 * 1024;
const EXCEL_HARD_BYTES: number = 20 * 1024 * 1024;
const PDF_HARD_BYTES: number = 30 * 1024 * 1024;
const OFD_HARD_BYTES: number = 30 * 1024 * 1024;
export const MAX_EXTRACTED_CHARS: number = 120000;

// 解析结果（Cube DocumentParseResult 同构；2026-09-15 一期增三字段）
export class DocumentParseResult {
  success: boolean = false;
  text: string = '';
  engine: string = '';
  error: string = '';
  warning: string = '';
  truncated: boolean = false;
  // PDF 全量页数（桥页 pdf.numPages，非 200 页抽取上限；非 PDF 引擎恒 0）
  pageCount: number = 0;
  // 纯正文长度（剔除 "---\nPage N:\n" 页标记；扫描件判据的输入，非 PDF 恒 0）
  textChars: number = 0;
  // 实际抽取页数（桥页 min(numPages, 200)——★ 扫描件判据的分母，非 PDF 恒 0；
  // 与 pageCount 分列：>200 页文档的正文只来自前 200 页，「页均」的分子分母须同域）
  textPages: number = 0;
  // 页图（元素 = 页序，mime 恒 PAGE_IMAGE_MIME；空 = 无页图——未渲染/整批降级）
  pageImages: AiImagePart[] = [];
}

// 解析态（PendingAttachment.parseState 事实值——'idle' 已入列未解析 / 'parsing' 进行中 /
// 'done' 成功 / 'failed' 失败 / 'toolarge' 超分型上限）
export type DocParseState = 'idle' | 'parsing' | 'done' | 'failed' | 'toolarge';

// WebView 结果 JSON 形态（DocumentParserBridge 产出）
interface WebDocumentParseResultJson {
  success?: boolean;
  text?: string;
  engine?: string;
  error?: string;
  warning?: string;
  truncated?: boolean;
  // 页统计（仅 PDF 引擎产出；docx/xlsx/ofd 不带——读侧 ?? 0 兜底不炸）
  pageCount?: number;
  textChars?: number;
  // 实际抽取页数（min(numPages, MAX_PDF_PAGES)——判据分母，见 pdfTextThin）
  textPages?: number;
}

// 桥页渲染态 JSON（getRenderState 产出）
interface WebRenderStateJson {
  done?: boolean;
  count?: number;
  error?: string;
}

// 桥输入（document-parser.html 约定字段）
interface WebDocumentParseInput {
  taskId: string;
  fileName: string;
  mimeType: string;
  size: number;
  maxChars: number;
}

// 文档候选判定（按扩展名——aicontrol 选择入口已按扩展名分流 kind='doc'，此处同源白名单；
// Cube 同步比对 mime 双通道，aicontrol 附件 mime 由扩展名派生，单一来源按扩展名）
export function isDocCandidate(att: PendingAttachment): boolean {
  if (att.kind !== 'doc') {
    return false;
  }
  const ext: string = docExt(att.name);
  return ext === '.pdf' || ext === '.docx' || ext === '.xlsx' || ext === '.xls' ||
    ext === '.ofd';
}

// 分型硬上限（0 = 无分型上限）
export function docHardLimitBytes(att: PendingAttachment): number {
  const ext: string = docExt(att.name);
  if (ext === '.docx') {
    return DOCX_HARD_BYTES;
  }
  if (ext === '.xlsx' || ext === '.xls') {
    return EXCEL_HARD_BYTES;
  }
  if (ext === '.pdf') {
    return PDF_HARD_BYTES;
  }
  if (ext === '.ofd') {
    return OFD_HARD_BYTES;
  }
  return 0;
}

// 扫描件判据（纯函数，断言直跑；拍板②口径）：非 .pdf 恒 false（docx/xlsx/ofd 不渲染）、
// 页数非正恒 false（无页数即无「页均」分母），其余 = 全文不足 300 字符 或 页均不足 50 字符。
// ★ 输入必须是纯正文长度（桥页 textChars 已剔页标记——页标记每页约 12 字符会把扫描件顶穿）
// ★ 第三参 = **实际抽取页数**（桥页 textPages = min(numPages, 200)），不是全量页数——
// 2026-09-15 收口笔：正文只累加前 200 页，拿全量页数当分母会把 >200 页文档的计算页均摊薄
// （真实页均落在 [50, 总页数÷4) 的文字型长文档被误判扫描件、白渲 30 页图；总页数 ≤200 时
// 两参同值、行为逐字不变）
export function pdfTextThin(name: string, textChars: number, textPages: number): boolean {
  if (docExt(name) !== '.pdf' || textPages <= 0) {
    return false;
  }
  return textChars < SCAN_TEXT_MIN_CHARS || textChars / textPages < SCAN_TEXT_MIN_PER_PAGE;
}

// 发送阻断判定（Cube DocumentParsePolicy.shouldBlockSend/getBlockingReason 合并裁剪——
// doc 且未 done 一律阻断；返回中文阻断原因，'' = 放行）
export function docBlockingReason(atts: PendingAttachment[]): string {
  for (const att of atts) {
    if (!isDocCandidate(att) || att.parseState === 'done') {
      continue;
    }
    if (att.parseState === 'toolarge') {
      return `附件过大，暂不支持解析：${att.name}`;
    }
    if (att.parseState === 'failed') {
      const suffix: string = (att.parseError ?? '') !== '' ? `：${att.parseError}` : '';
      return `附件解析失败，请移除或更换文件后再发送：${att.name}${suffix}`;
    }
    return `附件仍在解析中：${att.name}`;
  }
  return '';
}

function docExt(fileName: string): string {
  const index: number = fileName.lastIndexOf('.');
  if (index < 0) {
    return '';
  }
  return fileName.substring(index).toLowerCase();
}

// 沙箱副本 → base64（整读整编——Cube readAsBase64 同姿势；峰值内存 ≤ 文件×1.4，
// 分型硬上限内可控）。★ 消费 readSync 的实际读取长度（d.ts 明载返回值）：短读时零填充
// 尾部不得混入 base64（WebDavApi.readLocalFile 同款先例——第 2 轮 O5 本域半边，全面
// 自检第 3 轮笔 3 收口；等长读零拷贝直返）
function readBase64(path: string): string {
  const stat: fs.Stat = fs.statSync(path);
  const buf: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const len: number = fs.readSync(file.fd, buf);
    const data: ArrayBuffer = len === buf.byteLength ? buf : buf.slice(0, len);
    return new util.Base64Helper().encodeToStringSync(new Uint8Array(data));
  } finally {
    fs.closeSync(file);
  }
}

// ── 解析服务单例（控制器由宿主组件 onControllerAttached 注入）──

class WebDocumentParser {
  private controller: webview.WebviewController | null = null;
  private isReady: boolean = false;
  // 串行队列（★ 2026-09-03 自检修复：bridge 是单任务状态机〔currentTask/chunks 全局单份，
  // document-parser.html〕，多附件并发 start/append 会互相覆盖错乱——Cube 原版在 ChatPage
  // 有 documentParseQueue 页面级队列，移植时适配层丢失；此处补解析域内建队列 = 单一修复点，
  // promise 链逐任务排队，前序失败不断链）
  private queueTail: Promise<void> = Promise.resolve();

  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
  }

  markReady(): void {
    this.isReady = true;
  }

  // 就绪复位（★ 2026-09-11 笔 4）：isReady 的事实含义 = **当前 Web 已载完桥页**，不是「曾经载完过」。
  // 新 Web 附着控制器（宿主 onControllerAttached）即调用——此刻新桥页尚未载完，必须从「未就绪」
  // 重新开始等 markReady（onPageEnd）。修复面 = 反复进出会话页后 isReady 残留 true 导致
  // waitUntilReady 立即放行、首次 runJavaScript 撞未载完桥页（解析超时/脚本执行失败，报告 §3-F）
  markUnready(): void {
    this.isReady = false;
  }

  // 页面销毁兜底取消（进行中解析停止——半成品结果丢弃）
  async cancelCurrentParse(): Promise<void> {
    if (this.controller === null || !this.isReady) {
      return;
    }
    try {
      await this.runScript('window.DocumentParserBridge.cancel()');
    } catch (e) {
      // 取消失败静默（页面将亡，无消费方）
    }
  }

  // 单附件解析入口（排队串行——见 queueTail 注释）：候选/上限前置 → ready 等待 → 读副本
  // base64 → 分块注入 → finish → 轮询取结果。抛错 = 调用方转 failed 态（错误信息进
  // parseError 可见）
  parseAttachment(att: PendingAttachment): Promise<DocumentParseResult> {
    const task: Promise<DocumentParseResult> = this.queueTail.then(
      (): Promise<DocumentParseResult> => this.parseAttachmentNow(att),
      (): Promise<DocumentParseResult> => this.parseAttachmentNow(att));
    this.queueTail = task.then((): void => {}, (): void => {});
    return task;
  }

  private async parseAttachmentNow(att: PendingAttachment): Promise<DocumentParseResult> {
    const result: DocumentParseResult = new DocumentParseResult();
    if (!isDocCandidate(att)) {
      result.error = 'unsupported_file_type';
      return result;
    }
    const hardLimit: number = docHardLimitBytes(att);
    if (hardLimit > 0 && att.size > hardLimit) {
      result.error = 'file_too_large';
      return result;
    }
    await this.waitUntilReady();
    const base64Data: string = readBase64(att.localPath);
    if (base64Data === '') {
      result.error = 'empty_file_data';
      return result;
    }
    const parsed: DocumentParseResult = await this.parseBase64(att, base64Data);
    try {
      return await this.renderThinPdf(att, parsed);
    } finally {
      // 桥页收口（2026-09-15 自检轮 P2 修复）：文档句柄的**建点在 parsePdf 全类型**（凡成功
      // 载入的 PDF 都留存句柄供渲染复用），原释点只在渲染路径内（finally）——非 thin 的文字型
      // PDF 与解析中途失败的 PDF 句柄会一直留存到下一件解析（start）或离页（cancel），
      // 最大 30MB 的 PDF 字节随之常驻（成对释放红线：建点范围 ⊃ 释点范围即漏）。
      // 收口到本函数尾 = 所有出口（早退/降级/成功）都经此 finally；clearPages 幂等，
      // 非 PDF 与无句柄场景为空操作
      await this.clearPagesSilent();
    }
  }

  // 扫描件页图渲染（2026-09-15 一期）：判据命中即渲（**不等 caps**——拍板④：渲染与视觉
  // 门控解耦，发送那刻的 caps 只决定弹不弹确认；代价 = 配非视觉模型时白渲一次，本地 CPU
  // 零 token）。桥页是单任务状态机，故本步**续在同一 promise 单元内**——另起异步会与下一件
  // 附件的解析互踩（start() 会重置桥页态）。失败一律整批降级：
  // 页图清空 + hilog 留痕，result.success 不动（文本照旧），不抛错给上层。
  // 页图与文档句柄的收口**不在此处**——调用方 parseAttachmentNow 的 finally 覆盖全部出口
  // （2026-09-15 自检轮 P2 修复移出，见该处注释）
  private async renderThinPdf(att: PendingAttachment,
    result: DocumentParseResult): Promise<DocumentParseResult> {
    if (!result.success || !pdfTextThin(att.name, result.textChars, result.textPages)) {
      return result;
    }
    try {
      const issued: string =
        await this.runScript(`window.DocumentParserBridge.renderPages(${RENDER_MAX_PAGES})`);
      if (issued === 'error:no_pdf_document') {
        hilog.warn(0xD5A0, 'DocumentParse', 'PDF 页渲染未启动（桥页无文档句柄）：%{public}s',
          att.name);
        return result;
      }
      const pages: AiImagePart[] | null = await this.pullRenderedPages(att, result.pageCount);
      if (pages !== null) {
        result.pageImages = pages;
      }
    } catch (e) {
      // 渲染异常（含轮询结果 JSON 解析失败）= 整批降级，不让渲染问题卡死发送链
      hilog.warn(0xD5A0, 'DocumentParse', 'PDF 页渲染失败（降级纯文本）：%{public}s %{public}s',
        att.name, (e as Error).message);
    }
    return result;
  }

  // 页图拉取（轮询渲染态 → 逐页取裸 base64）。期望页数 = min(全量页数, RENDER_MAX_PAGES)；
  // 页数不符/渲染报错/超时/单页取空 → 返回 null（调用方整批丢弃，不留半批）
  private async pullRenderedPages(att: PendingAttachment,
    pageCount: number): Promise<AiImagePart[] | null> {
    const expected: number = Math.min(pageCount, RENDER_MAX_PAGES);
    const start: number = Date.now();
    let done: boolean = false;
    let count: number = 0;
    let renderError: string = '';
    while (Date.now() - start <= RENDER_TIMEOUT_MS) {
      const raw: string = await this.runScript('window.DocumentParserBridge.getRenderState()');
      const state: WebRenderStateJson = JSON.parse(raw) as WebRenderStateJson;
      done = state.done === true;
      count = state.count ?? 0;
      renderError = state.error ?? '';
      if (done) {
        break;
      }
      await sleep(POLL_STEP_MS);
    }
    if (!done || renderError !== '') {
      hilog.warn(0xD5A0, 'DocumentParse', 'PDF 页渲染未完成（done=%{public}s error=%{public}s）：%{public}s',
        String(done), renderError, att.name);
      return null;
    }
    if (count !== expected) {
      hilog.warn(0xD5A0, 'DocumentParse', 'PDF 页图页数不符（实得 %{public}d / 期望 %{public}d）：%{public}s',
        count, expected, att.name);
      return null;
    }
    const parts: AiImagePart[] = [];
    for (let index = 0; index < count; index++) {
      const data: string =
        await this.runScript(`window.DocumentParserBridge.getPageImage(${index})`);
      if (data === '') {
        hilog.warn(0xD5A0, 'DocumentParse', 'PDF 页图取回为空（第 %{public}d 页）：%{public}s',
          index + 1, att.name);
        return null;
      }
      parts.push({ mimeType: PAGE_IMAGE_MIME, data: data });
    }
    return parts;
  }

  // 桥页页图清理（幂等；失败静默——桥页侧资源随下次 start/页面卸载回收，无消费方需感知）
  private async clearPagesSilent(): Promise<void> {
    try {
      await this.runScript('window.DocumentParserBridge.clearPages()');
    } catch (e) {
      // 清理失败静默：下一次 start() 亦会收口销毁（幂等）
    }
  }

  // ready 等待（宿主 onPageEnd 置位 / onControllerAttached 复位——见 markUnready；80ms 步长
  // 5s 上限——WebView 未就绪 = 竞态兜底）
  private async waitUntilReady(): Promise<void> {
    const start: number = Date.now();
    while (!this.isReady) {
      if (Date.now() - start > WEB_READY_TIMEOUT_MS) {
        throw new Error('解析器未就绪');
      }
      await sleep(POLL_STEP_MS);
    }
  }

  private async parseBase64(att: PendingAttachment, base64Data: string): Promise<DocumentParseResult> {
    const taskId: string = `doc_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    const input: WebDocumentParseInput = {
      taskId: taskId,
      fileName: att.name,
      mimeType: att.mediaType,
      size: att.size,
      maxChars: MAX_EXTRACTED_CHARS
    };
    await this.runScript(`window.DocumentParserBridge.start(${JSON.stringify(input)})`);
    for (let offset = 0; offset < base64Data.length; offset += BASE64_CHUNK_SIZE) {
      const chunk: string =
        base64Data.substring(offset, Math.min(offset + BASE64_CHUNK_SIZE, base64Data.length));
      await this.runScript(`window.DocumentParserBridge.append(${JSON.stringify(chunk)})`);
    }
    const initialResult: string = await this.runScript('window.DocumentParserBridge.finish()');
    const rawResult: string = await this.waitForWebParseResult(initialResult);
    return this.parseWebResult(rawResult);
  }

  // 结果轮询（finish 返回非 JSON = 仍在解析，80ms 步长 45s 上限；Cube 同构）
  private async waitForWebParseResult(initialResult: string): Promise<string> {
    if (this.isWebParseJsonResult(initialResult)) {
      return initialResult;
    }
    const start: number = Date.now();
    while (Date.now() - start <= WEB_PARSE_TIMEOUT_MS) {
      const rawResult: string = await this.runScript('window.DocumentParserBridge.getResult()');
      if (this.isWebParseJsonResult(rawResult)) {
        return rawResult;
      }
      await sleep(POLL_STEP_MS);
    }
    throw new Error('解析超时');
  }

  private isWebParseJsonResult(value: string): boolean {
    const normalized: string = value.trim();
    return normalized.startsWith('{') && normalized.endsWith('}');
  }


  private async runScript(script: string): Promise<string> {
    if (this.controller === null) {
      throw new Error('解析器控制器缺失');
    }
    try {
      const value: string | undefined =
        await this.controller.runJavaScript(script) as string | undefined;
      if (value === undefined || value === null) {
        return '';
      }
      return this.normalizeRunJavaScriptResult(value.toString());
    } catch (e) {
      throw new Error('解析脚本执行失败: ' + (e as Error).message);
    }
  }

  // runJavaScript 返回值可能被 JSON 字符串再包一层（引擎差异容错——Cube 同款剥两层引号）
  private normalizeRunJavaScriptResult(value: string): string {
    let normalized: string = value.trim();
    for (let i = 0; i < 2; i++) {
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

  private parseWebResult(raw: string): DocumentParseResult {
    const result: DocumentParseResult = new DocumentParseResult();
    try {
      const json: WebDocumentParseResultJson = JSON.parse(raw) as WebDocumentParseResultJson;
      result.success = json.success === true;
      result.text = json.text ?? '';
      result.engine = json.engine ?? '';
      result.error = json.error ?? '';
      result.warning = json.warning ?? '';
      result.truncated = json.truncated === true;
      // 页统计兜底（docx/xlsx/ofd 三引擎不产出这三字段——缺省 0 不可炸）
      result.pageCount = json.pageCount ?? 0;
      result.textChars = json.textChars ?? 0;
      result.textPages = json.textPages ?? 0;
      return result;
    } catch (e) {
      result.error = '解析结果无效';
      return result;
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

export const docParser: WebDocumentParser = new WebDocumentParser();
export const docParseController: webview.WebviewController = new webview.WebviewController();


// ── 隐式宿主组件（ChatPage Content 内挂载；1×1 透明 + 离屏定位 + 命中穿透——
// Cube ChatPage:2527-2545 形态逐项照搬）──
@Component
export struct DocParserHost {
  build() {
    Web({ src: WEB_PARSER_URL, controller: docParseController })
      .width(1)
      .height(1)
      .opacity(0)
      .position({ x: -2, y: -2 })
      .hitTestBehavior(HitTestMode.None)
      .onControllerAttached(() => {
        docParser.attachController(docParseController);
        // ★ 2026-09-11 笔 4：新 Web 附着即复位就绪——复位与置位同属「Web 附着 → 桥页载完」
        // 一对事件（onControllerAttached 复位 / onPageEnd 置位）；Web 被复用未重附着 = 未销毁
        // 不复位才对，Web 重建必重附着复位、随后由新桥页 onPageEnd 重新置位（双向 fail-safe）
        docParser.markUnready();
      })
      .onPageEnd(() => {
        docParser.markReady();
      })
      .javaScriptAccess(true)
      .fileAccess(false)
      .backgroundColor(Color.Transparent)
  }
}
