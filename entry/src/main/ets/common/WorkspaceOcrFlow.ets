// 工作区识别文字执行编排域：管理页/识别文字页「识别文字」动作的唯一编排点——行态注册表 +
// 图片路 / PDF 路识别链 + 标注组装 + 落库。
// · 分层红线（照 OcrEngine 先例）：本件禁 import UI 组件层——toast 通道（notify）与完成回调
//   （onComplete）/导航全部由调用方注入；本件只做入口、链路与落库。
// · 识别链复用既有引擎域零新增：三态引擎 / 回退编排 / 串行队列 / 时限 / 提示词全在 OcrEngine；
//   PDF 页渲染在 DocumentParse.parseAttachment 全路径（thin 命中渲页图——与附件链同一
//   promise 单元、共用解析串行队列）。本件是 OCR 引擎的第三个消费方。
// · 进行中态（running）= 进程内内存注册表（Set<fileId> 单源在此），不落库：页面重建可恢复
//   展示（现查本注册表），杀应用即消失、无滞留态、无常驻对账需求。
// · 退出语义：任务与页面解耦——完成即落库、退页零损失（不接 BusyOverlay、不拦返回）；
//   杀应用 = 完成前不落库、无半截数据、重进重跑。
// · 幽灵写：落库返回 false（识别中该行被删）→ 静默丢弃（识别中允许删除文件，
//   saveWorkspaceOcr 按 id UPDATE changes===0 即行亡）。
// · 共享队列申报：预识别占用全应用 OCR 串行队列与文档解析队列（此间附件识别排队、解析排队）
//   ——用户主动场景可接受，UI 侧以「识别中」态呈现。
import { fileIo as fs } from '@kit.CoreFileKit';
import { PendingAttachment } from './providers/AiTypes';
import { docParser, DocumentParseResult, MAX_EXTRACTED_CHARS, pdfTextThin } from './DocumentParse';
import { OcrImageSource, OcrOutcome, runOcr } from './OcrEngine';
import { queryWorkspaceOcr, saveWorkspaceOcr } from './store/ChatDb';
import { workspaceFilesDir } from './store/WorkspaceDb';
import { WorkspaceFileRow, extOfWorkspaceName } from './WorkspaceUtil';
import { WorkspaceOcrRecord } from './store/WorkspaceDbOcr';

// 识别完成标注（全仓单源，回执/落库文本尾附）
export const WS_OCR_MARK_PARTIAL: string = '\n[部分页面未识别]';
export const WS_OCR_MARK_PAGE_LIMIT_PREFIX: string = '\n[仅识别前 ';
export const WS_OCR_MARK_PAGE_LIMIT_MID: string = ' 页，共 ';
export const WS_OCR_MARK_TRUNCATED: string = '\n[识别文字过长，已截断]';

// 识别进行中注册表（进程内单源；页面重建经 isWorkspaceOcrRunning 现查恢复「识别中」态展示）
const runningIds: Set<string> = new Set<string>();

// 任务落定监听（单槽位——只有管理页订阅，aboutToAppear 挂 aboutToDisappear 摘）：任一识别
// 任务落定（成功/失败/幽灵写）即回调，管理页重派生行态位——治「识别文字页发起的重识别、
// 用户先退回管理页」场景：该任务的 onComplete 归识别文字页，管理页 onPop 刷新时任务仍在跑、
// 标签停「识别中」，落定回调是唯一补刷时机
let settleListener: ((fileId: string) => void) | null = null;

export function setWorkspaceOcrSettleListener(listener: ((fileId: string) => void) | null): void {
  settleListener = listener;
}

// 识别中判定（管理页菜单标签与点击守卫、识别文字页重识别守卫共用单源）
export function isWorkspaceOcrRunning(fileId: string): boolean {
  return runningIds.has(fileId);
}

// 识别对象判定（只 image 档或 doc 档 pdf；文件夹行、临时区、其他档不出入口）
export function isWorkspaceOcrCandidate(row: WorkspaceFileRow): boolean {
  return row.kind === 'image' ||
    (row.kind === 'doc' && extOfWorkspaceName(row.name) === 'pdf');
}

// 完成回调载荷：saved = 是否已落库（false = 失败 / 空文本 / 行已删幽灵写——调用方据此决定
// 自动进页（仅 true 且自身在前台）或刷新列表态）
export interface WorkspaceOcrHooks {
  // toast 通道（用户主动场景——引擎回退告知照附件链口径经此透传）
  notify: (msg: string) => void;
  onComplete: (fileId: string, saved: boolean) => void;
}

// 识别入口（幂等：同 fileId 识别中重复触发 = 无操作——重入守卫第一道在注册表，第二道在
// 调用方菜单点击守卫）。本函数立即返回，任务后台跑；完成经 hooks.onComplete 回调。
export function startWorkspaceOcr(row: WorkspaceFileRow, hooks: WorkspaceOcrHooks): void {
  if (runningIds.has(row.id)) {
    return;
  }
  runningIds.add(row.id);
  startWorkspaceOcrAsync(row, hooks);
}

async function startWorkspaceOcrAsync(row: WorkspaceFileRow,
  hooks: WorkspaceOcrHooks): Promise<void> {
  let saved: boolean = false;
  try {
    saved = await runOcrFlow(row, hooks);
  } catch (e) {
    // 防御面（runOcr 永不 reject、parseAttachment 会 reject——解析 throw 在 runOcrFlow 内已
    // 捕获，能漏到这里的只有意外异常）：中文 toast 不静默（P0-1）
    hooks.notify('识别失败，请稍后重试（' + (e as Error).message + '）');
  } finally {
    runningIds.delete(row.id);
  }
  if (settleListener !== null) {
    settleListener(row.id);
  }
  hooks.onComplete(row.id, saved);
}

// 识别链本体（返回 = 是否落库成功）
async function runOcrFlow(row: WorkspaceFileRow, hooks: WorkspaceOcrHooks): Promise<boolean> {
  const filesDir: string = workspaceFilesDir();
  if (filesDir === '') {
    hooks.notify('工作区目录未就绪，请稍后再试');
    return false;
  }
  // 入队前现检（行在 + 文件在，缺失中文提示照「文件已不在本机」先例）——行在判据 = 六列
  // 记录可读（行删 ⇒ 查询 null）
  const alive: WorkspaceOcrRecord | null = await queryWorkspaceOcr(row.id);
  if (alive === null) {
    hooks.notify('文件已不在本机');
    return false;
  }
  const absPath: string = filesDir + '/' + row.localPath;
  if (!fs.accessSync(absPath)) {
    hooks.notify('文件已不在本机');
    return false;
  }
  // 起始指纹（★ 识别**起始**时刻的 stat 快照——识别期间文件被换 ⇒ 完成后立即判过期；
  // mtime 秒 ×1000 转 ms 入库，fs.Stat.mtime 为秒，WorkspaceDb 对账同款换算）
  const stat: fs.Stat = fs.statSync(absPath);
  const mtimeMs: number = stat.mtime * 1000;
  const size: number = stat.size;

  let text: string = '';
  let engine: string = '';
  let partial: boolean = false;
  let renderedPages: number = 0;
  let totalPdfPages: number = 0;

  if (row.kind === 'image') {
    // 图片路：沙箱绝对路径直入引擎（解码/编码链在 OcrEngine 内自管）
    const sources: OcrImageSource[] = [{ kind: 'path', data: absPath }];
    const outcome: OcrOutcome = await runOcr(sources, hooks.notify);
    if (!outcome.ok) {
      hooks.notify('文字识别未成功，请稍后重试');
      return false;
    }
    text = outcome.text;
    engine = outcome.engine;
    partial = outcome.partial;
  } else {
    // PDF 路：parseAttachment 全路径（thin 命中续渲页图——解析与渲染同一 promise 单元，
    // 共用解析串行队列；渲染 45s 上限 + OCR 时限照引擎常量，用户等待场景接受）
    const att: PendingAttachment = {
      fileId: row.id, name: row.name, mediaType: row.mime, size: row.size,
      kind: 'doc', localPath: absPath
    };
    let parsed: DocumentParseResult;
    try {
      parsed = await docParser.parseAttachment(att);
    } catch (e) {
      // 解析 throw（超时 / 解析器未就绪 / 读副本失败）= 失败路：原因透传，不落库、
      // 不出「未识别到文字」（防把失败谎报为无文字）
      hooks.notify('「' + row.name + '」解析失败，请稍后重试');
      return false;
    }
    if (parsed.success !== true) {
      hooks.notify('「' + row.name + '」解析失败，请稍后重试');
      return false;
    }
    const thin: boolean = pdfTextThin(row.name, parsed.textChars, parsed.textPages);
    if (parsed.pageImages.length > 0) {
      // thin 命中已渲：逐页组 base64 源进 OCR（页图 mime 恒 image/jpeg——PAGE_IMAGE_MIME 产物）
      const sources: OcrImageSource[] = [];
      for (const page of parsed.pageImages) {
        sources.push({ kind: 'base64', data: page.data });
      }
      renderedPages = parsed.pageImages.length;
      totalPdfPages = parsed.pageCount;
      const outcome: OcrOutcome = await runOcr(sources, hooks.notify);
      if (!outcome.ok) {
        hooks.notify('文字识别未成功，请稍后重试');
        return false;
      }
      text = outcome.text;
      engine = outcome.engine;
      partial = outcome.partial;
    } else if (!thin) {
      // 非 thin（文字层）：解析文本直接作识别文本（零 OCR 耗时——秒级提取）
      text = parsed.text;
      engine = parsed.engine;
    } else {
      // thin 命中但页图空 = 渲染整批降级：失败路，不出「未识别到文字」
      hooks.notify('「' + row.name + '」页面渲染失败，请稍后重试');
      return false;
    }
  }

  if (text === '') {
    hooks.notify('未识别到文字');
    return false;
  }
  // 标注组装：部分页失败 / 超时截停照落 + 尾注；渲染受页数限时再附页数标注；
  // 超抽取上限截断 + 尾注
  if (partial) {
    text += WS_OCR_MARK_PARTIAL;
  }
  if (renderedPages > 0 && totalPdfPages > renderedPages) {
    text += WS_OCR_MARK_PAGE_LIMIT_PREFIX + renderedPages + WS_OCR_MARK_PAGE_LIMIT_MID +
      totalPdfPages + ' 页]';
  }
  if (text.length > MAX_EXTRACTED_CHARS) {
    text = text.substring(0, MAX_EXTRACTED_CHARS) + WS_OCR_MARK_TRUNCATED;
  }
  // 落库（条件 = ok && text !== ''，上方两失败路已拦）；幽灵写静默（行已删）
  return saveWorkspaceOcr(row.id, text, engine, mtimeMs, size);
}
