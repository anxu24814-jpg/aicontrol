// 附件文字识别引擎域（2026-09-15 附件 OCR 二期，任务书-附件OCR链路-20260915 §3.1/§3.2）：
// 把「一批图 → 一段文字」做成一个可换引擎、**串行**、带回退的通道。消费方 = 附件入列侧
// AttachmentPickCtrl（图片附件路 + 扫描件 PDF 页图路，排程见 §3.5）；toast 通道由调用方
// 经 notify 注入（本件 common 层禁直接引 UI API——分层红线）。
// 引擎形态（★ 2026-09-16 决明拍板「系统识别开关化」→ 同日内置引擎落地，三态；方案 =
// 方案-内置PaddleOCR-20260916 §3.1。首选引擎由功能模型页「文字识别」卡的**卡内三分段
// 胶囊**决定，三态互斥、单值落键 OCR_ENGINE_KEY，解析单源 = ProviderDb.resolveOcrEngine）：
// · system = 系统识别（@kit.CoreVisionKit textRecognition，零配置零权限，默认值）；
// · builtin = 内置识别（providers/OcrPaddle，PP-OCRv6 三模型随包 + 系统内置 MindSpore Lite
//   推理——完全离线、图不出设备、覆盖中英日与拉丁语系；无网可用，不依赖系统服务；
//   真机不支持（canIUse false）或模型加载失败时自动回落系统识别）；
// · model = 视觉引擎（providers/OcrVisionApi，设置 → 功能模型 选一个已配模型，选完即改用）。
// 官方红线（Kit 简介与 d.ts，查证录任务书 §1.1）：
// · **不支持同进程并发调用同一特性**（"系统繁忙"）——本件内建串行队列（queueTail，
//   DocumentParse.ets 同款形态），一切识别经此排队，禁 Promise.all；
// · VisionInfo 只吃 **RGBA_8888** PixelMap——解码唯一入口 = ImageEditUtil.decodeScaled
//   （内部显式锁该格式，禁绕开自建 ImageSource）；
// · TextRecognitionConfiguration 仅 isDirectionDetectionSupported 一参——本件恒 false
//   （页图由桥页正向渲染、图片附件按 EXIF 正向解码，官方"正向图设 false 提性能"）；
// · init/release 成对（懒 init 首次调用前；release 由消费页 ChatPage.aboutToDisappear
//   经 ocrRelease() 调用——建立与释放在「消费方页面生命周期」一对事件上）；
// · 错误码：200 超时 / 1001400001 运行失败 → 立即重试一次（禁人为 sleep 退避，P1-3）；
//   401 入参错 / 1001400002 服务异常（官方建议重启设备）→ 不重试直接失败。
// ★ runOcr 契约：**永不 reject**——内部全捕获，异常/禁用/无源一律转 {ok:false}（调用方
// 据此把附件 ocrState 定到 failed；一旦 reject 漏出，doc 路附件将永停 'parsing' 无法
// 发送——终态兜底红线，任务书 §3.5 末条）。
// ★ 回退编排（§3.4，乙笔落地；★ 2026-09-16 内置引擎落地后收成**唯一规则**，方案 §3.1 表）：
// **首选非系统（builtin / model）→ 回退系统识别；首选系统 → 回退视觉模型（已配时）**。
// 仍只回退一次（禁来回循环——三态下不再有「builtin 失败退 model」这一向：多跳会让失败链路
// 与耗时都不可预期）；换引擎必 notify toast 告知（拍板 #8「不静默改走另一个引擎而不告知」）；
// 两引擎都失败不再 toast（hilog 留痕），发送侧走一期行为（识别失败 ≠ 发送失败）。
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { decodeScaled } from './ImageEditUtil';
import { encodeImageBase64, IMAGE_MAX_EDGE_PX } from './AttachmentUtil';
import { PAGE_IMAGE_LONG_EDGE_PX, PAGE_IMAGE_MIME } from './DocumentParse';
import { AiImagePart } from './providers/AiTypes';
import { ensurePaddleReady, paddleAttachContext, paddleAvailable,
  runPaddlePage } from './providers/OcrPaddle';
import { OCR_ENABLED_KEY, OCR_ENGINE_BUILTIN, OCR_ENGINE_KEY, OCR_ENGINE_MODEL,
  OCR_ENGINE_SYSTEM, OCR_MODEL_KEY, OCR_PREFER_SYSTEM_KEY, OCR_PROVIDER_KEY,
  resolveOcrEngine } from './store/ProviderDb';
import { OcrVisionResult, requestOcrText } from './providers/OcrVisionApi';

// 整体识别时限（ms，§7.12）：超时停止后续页（已成功页照常采用）——防「识别卡住 → 附件
// 永停识别中 → 用户发不出去」；单页 in-flight 识别无法中断，由下一次循环判定截停
const OCR_TIMEOUT_MS: number = 120000;

// 内置引擎单设时限（★ 2026-09-16 阶段 0 实测依据，方案 §七「内置引擎时延」风险行的处置：
// **不改全局常量**，本引擎单独放宽）。真机实测单页成本 = det ~0.6s + 每文本行「cls 9ms +
// 分块 rec ~40ms×段数」；稀疏页（7 行）≈2.3s/页，密排页（20 行、行宽 700px 折 6 段）≈5.4s/页。
// 文档类附件上限 30 页（DocumentParse 口径）→ 最坏 ≈162s 超出全局 120s，故本引擎取 180s
//（仍有限；超时只截停剩余页，已识别页照常采用——与全局同语义）
const OCR_BUILTIN_TIMEOUT_MS: number = 180000;

// 识别输入源（甲笔定死契约，乙笔不得改签名）：kind='base64' → data 为页图裸 base64
// （DocumentParse.PAGE_IMAGE_MIME 产物）；kind='path' → data 为沙箱绝对路径（图片附件）
export interface OcrImageSource {
  kind: string;
  data: string;
}

// 识别产出（甲笔定死契约）：ok = 至少一页成功；text = 页序拼接全文（'\n\n' 连接，ok=false
// 时空串）；engine = 实际产出方 'system' | 'builtin' | 'model' | ''（未跑任何引擎；
// ★ 2026-09-16 三态扩 builtin）；partial = 有页失败但整体成功（仅日志用，不上屏）
export interface OcrOutcome {
  ok: boolean;
  text: string;
  engine: string;
  partial: boolean;
}

// 串行队列尾（官方禁并发——见头注释；前序失败不断链，DocumentParse.queueTail 同款）
let queueTail: Promise<void> = Promise.resolve();

// 系统引擎懒初始化态：init 成功置位；release 复位。init 返回 false / 抛错不置位（下件
// 重试——瞬时失败不该永久封禁引擎）
let sysInitDone: boolean = false;

// OCR 总开关（拍板 #7：默认开、可关；缺省/未写 = 开）：false = 零识别零耗时回一期行为
export function ocrEnabled(): boolean {
  return (AppStorage.get<string>(OCR_ENABLED_KEY) ?? 'true') !== 'false';
}

// 首选引擎选择（§3.1 三态；★ 2026-09-16 内置引擎落地 = 读 OCR_ENGINE_KEY，未写/脏写按旧
// 口径推导）。**解析单源 = ProviderDb.resolveOcrEngine**（禁在本件重写三目链——功能模型页
// 分段胶囊镜像同源）；「偏好模型但两键空」在该函数内已回落 system（防空 modelId 进链）
function preferredEngine(): string {
  return resolveOcrEngine(AppStorage.get<string>(OCR_ENGINE_KEY) ?? '',
    AppStorage.get<string>(OCR_PREFER_SYSTEM_KEY) ?? '',
    AppStorage.get<string>(OCR_PROVIDER_KEY) ?? '',
    AppStorage.get<string>(OCR_MODEL_KEY) ?? '');
}

// 引擎回退 toast 用的显示名（内置引擎无配置项，故只有它需要常量名；model 走模型名——
// 两处文案与开关化之前逐字一致，回归红线。★ 2026-09-16 自检轮修正：原式 model 支回落
// **引擎内部值**（'model'），toast 实际播「model未成功，已改用本机识别」——注释承诺与
// 实现相反，且断言把该形态钉住（断言与缺陷同侧）；本支只此一处调用者，engine 取
// builtin / model 两态，故非 builtin 即视觉模型）
function engineShortName(engine: string): string {
  return engine === OCR_ENGINE_BUILTIN ? '内置识别' : modelEngineId();
}

// 内置引擎上下文注入（调用点 = EntryAbility.onCreate，与 persistProp 注册同处——组合根职责；
// common 层拿不到 UIContext，能力上下文是应用级单一真源。转发到 OcrPaddle，使 EntryAbility
// 对 OCR 域的接触面保持单文件）
export function ocrAttachContext(ctx: common.Context): void {
  paddleAttachContext(ctx);
}

// 识别主入口（永不 reject——见头注释；!ocrEnabled 或零源 = {ok:false, engine:''}，调用方
// 据此不置 running 态不阻断发送）。notify = 调用方注入的 toast 通道（回退提示用，乙笔消费）
export async function runOcr(sources: OcrImageSource[],
  notify: (msg: string) => void): Promise<OcrOutcome> {
  if (!ocrEnabled() || sources.length === 0) {
    return { ok: false, text: '', engine: '', partial: false };
  }
  const task: Promise<OcrOutcome> = queueTail.then(
    (): Promise<OcrOutcome> => runOcrQueued(sources, notify));
  queueTail = task.then((): void => {}, (): void => {});
  return task;
}

// 队内执行（引擎选择 + 回退编排 §3.4；全捕获兜底——异常一律转 {ok:false}，保 runOcr 永不
// reject 契约）。回退只发生一次（禁来回循环）；两引擎都失败不再 toast（hilog 留痕）。
// ★ 三态唯一回退规则：首选非系统（builtin / model）→ 系统识别；首选系统 → 视觉模型（已配时）
async function runOcrQueued(sources: OcrImageSource[],
  notify: (msg: string) => void): Promise<OcrOutcome> {
  const preferred: string = preferredEngine();
  let first: OcrOutcome;
  if (preferred === OCR_ENGINE_MODEL) {
    first = await runModelOcr(sources);
  } else if (preferred === OCR_ENGINE_BUILTIN) {
    first = await runBuiltinOcr(sources);
  } else {
    first = await runSystemOcrSafe(sources);
  }
  if (first.ok) {
    return first;
  }
  if (preferred !== OCR_ENGINE_SYSTEM && systemOcrAvailable()) {
    notify(engineShortName(preferred) + '未成功，已改用本机识别');
    const second: OcrOutcome = await runSystemOcrSafe(sources);
    if (!second.ok) {
      hilog.warn(0xD5A0, 'OcrEngine', '首选 %{public}s 失败后系统识别回退仍失败', preferred);
    }
    return second;
  }
  if (preferred === OCR_ENGINE_SYSTEM && modelEngineConfigured()) {
    notify('本机文字识别未成功，已改用 ' + modelEngineId());
    const second: OcrOutcome = await runModelOcr(sources);
    if (!second.ok) {
      hilog.warn(0xD5A0, 'OcrEngine', '本机识别失败后视觉引擎回退仍失败：%{public}s',
        modelEngineId());
    }
    return second;
  }
  return first;
}

// 系统引擎可用性（canIUse 单源——runSystemOcr 门与回退前置判定共用）
function systemOcrAvailable(): boolean {
  return canIUse('SystemCapability.AI.OCR.TextRecognition');
}

// 视觉引擎配置判定与模型 id（引擎两键都非空才算已配置）
function modelEngineId(): string {
  return AppStorage.get<string>(OCR_MODEL_KEY) ?? '';
}

function modelEngineConfigured(): boolean {
  return modelEngineId() !== '' && (AppStorage.get<string>(OCR_PROVIDER_KEY) ?? '') !== '';
}

// 系统引擎释放（成对释放：与懒 init 一对；调用点 = ChatPage.aboutToDisappear——当前唯一
// 消费页，将来第二消费方出现时改集中释放点，§7.11）。★ 释放经串行队列排队（2026-09-16
// 自检轮修正）：离页时识别可能仍在跑（大扫描件识别数十秒级），队列外直呼 release 会打进
// in-flight recognizeText——官方约束同进程禁并发访问该特性；排队后释放与一切识别严格
// 定序，离页后再入队的识别排在释放之后、经 ensureSysInit 复位自然重 init
export async function ocrRelease(): Promise<void> {
  const task: Promise<void> = queueTail.then((): Promise<void> => releaseSysEngine());
  queueTail = task.then((): void => {}, (): void => {});
  return task;
}

// 释放本体（仅经队列执行——release 不打 in-flight 识别；未 init 过 = 无需释放，复位放在
// try 前与原形一致：release 抛错也不留「已释放但标记在位」的假态）
async function releaseSysEngine(): Promise<void> {
  if (!sysInitDone) {
    return;
  }
  sysInitDone = false;
  try {
    await textRecognition.release();
  } catch (e) {
    hilog.warn(0xD5A0, 'OcrEngine', '系统引擎释放失败：%{public}s', (e as Error).message);
  }
}

// 系统引擎懒初始化（官方要求 init/release 成对加载释放模型；false/异常 = 本次不可用）
async function ensureSysInit(): Promise<boolean> {
  if (sysInitDone) {
    return true;
  }
  try {
    const ok: boolean = await textRecognition.init();
    if (ok) {
      sysInitDone = true;
    } else {
      hilog.warn(0xD5A0, 'OcrEngine', '系统识别引擎初始化返回 false（本件按不可用处理）');
    }
    return ok;
  } catch (e) {
    hilog.warn(0xD5A0, 'OcrEngine', '系统识别引擎初始化异常：%{public}s', (e as Error).message);
    return false;
  }
}

// 系统引擎整件识别（外层安全壳：异常兜底转 {ok:false}，保 runOcrQueued 编排不中断）
async function runSystemOcrSafe(sources: OcrImageSource[]): Promise<OcrOutcome> {
  try {
    return await runSystemOcr(sources);
  } catch (e) {
    hilog.warn(0xD5A0, 'OcrEngine', '系统引擎整件异常：%{public}s', (e as Error).message);
    return { ok: false, text: '', engine: 'system', partial: false };
  }
}

// 视觉引擎整件识别（自捕获——配置缺失/编码失败/请求失败一律 {ok:false}，回退编排据此换引擎）
async function runModelOcr(sources: OcrImageSource[]): Promise<OcrOutcome> {
  const providerId: string = AppStorage.get<string>(OCR_PROVIDER_KEY) ?? '';
  const modelId: string = modelEngineId();
  if (providerId === '' || modelId === '') {
    return { ok: false, text: '', engine: 'model', partial: false };
  }
  try {
    const images: AiImagePart[] = await sourcesToParts(sources);
    if (images.length === 0) {
      return { ok: false, text: '', engine: 'model', partial: false };
    }
    const result: OcrVisionResult = await requestOcrText(providerId, modelId, images);
    if (!result.ok) {
      hilog.warn(0xD5A0, 'OcrEngine', '视觉引擎识别失败（status %{public}d）：%{public}s',
        result.status, result.errorMessage);
      return { ok: false, text: '', engine: 'model', partial: false };
    }
    return { ok: true, text: result.text, engine: 'model', partial: false };
  } catch (e) {
    hilog.warn(0xD5A0, 'OcrEngine', '视觉引擎整件异常：%{public}s', (e as Error).message);
    return { ok: false, text: '', engine: 'model', partial: false };
  }
}

// 识别源 → 视觉引擎图片部件：页图（base64）原样配 PAGE_IMAGE_MIME；图片附件（沙箱路径）
// 经 encodeImageBase64 限长边重采样编码（与发送链同一编码入口——复用最小附件壳，该函数
// 只消费 name〔定输出 mime〕与 localPath 两字段）
async function sourcesToParts(sources: OcrImageSource[]): Promise<AiImagePart[]> {
  const parts: AiImagePart[] = [];
  for (const src of sources) {
    if (src.kind === 'base64') {
      parts.push({ mimeType: PAGE_IMAGE_MIME, data: src.data });
    } else {
      const name: string = src.data.substring(src.data.lastIndexOf('/') + 1);
      parts.push(await encodeImageBase64({ fileId: '', name: name, mediaType: '', size: 0,
        kind: 'image', localPath: src.data }));
    }
  }
  return parts;
}

// 系统引擎整件识别：能力探测 → 懒 init → 逐页串行（禁并发）。页级失败跳过（日志留痕），
// ≥1 页成功即整件成功（partial=true）；零成功 = 整件失败（回退编排接管）。整体时限内未跑
// 完的页按失败计并截停
async function runSystemOcr(sources: OcrImageSource[]): Promise<OcrOutcome> {
  if (!systemOcrAvailable()) {
    hilog.warn(0xD5A0, 'OcrEngine', '系统识别能力不可用（canIUse false）');
    return { ok: false, text: '', engine: 'system', partial: false };
  }
  if (!await ensureSysInit()) {
    return { ok: false, text: '', engine: 'system', partial: false };
  }
  const parts: string[] = [];
  let failed: number = 0;
  const start: number = Date.now();
  for (let i = 0; i < sources.length; i++) {
    if (Date.now() - start > OCR_TIMEOUT_MS) {
      const remaining: number = sources.length - i;
      failed += remaining;
      hilog.warn(0xD5A0, 'OcrEngine', '识别整体超时（%{public}d ms），剩余 %{public}d 页截停',
        OCR_TIMEOUT_MS, remaining);
      break;
    }
    try {
      const pageText: string = await recognizeSource(sources[i]);
      if (pageText !== '') {
        parts.push(pageText);
      }
    } catch (e) {
      failed++;
      hilog.warn(0xD5A0, 'OcrEngine', '第 %{public}d 页识别失败：%{public}s',
        i + 1, (e as Error).message);
    }
  }
  const ok: boolean = failed < sources.length;
  const partial: boolean = ok && failed > 0;
  return { ok: ok, text: ok ? parts.join('\n\n') : '', engine: 'system', partial: partial };
}

// 内置引擎整件识别（providers/OcrPaddle；★ 2026-09-16 方案-内置PaddleOCR §3.1/§3.3）：
// 能力探测 → 模型懒加载（进程级常驻、无释放 API——见 OcrPaddle 头注释）→ 逐页串行。
// 与系统引擎同款错误契约：页级失败跳过（日志留痕），≥1 页成功即整件成功（partial），零成功
// = 整件失败（回退编排接管）；整体时限用本引擎专属常量（OCR_BUILTIN_TIMEOUT_MS，理由见其
// 注释）。整件异常兜底 {ok:false}——runOcr 永不 reject 契约不破
async function runBuiltinOcr(sources: OcrImageSource[]): Promise<OcrOutcome> {
  try {
    if (!paddleAvailable()) {
      hilog.warn(0xD5A0, 'OcrEngine', '内置识别能力不可用（canIUse false）');
      return { ok: false, text: '', engine: 'builtin', partial: false };
    }
    if (!await ensurePaddleReady()) {
      return { ok: false, text: '', engine: 'builtin', partial: false };
    }
    const parts: string[] = [];
    let failed: number = 0;
    const start: number = Date.now();
    for (let i = 0; i < sources.length; i++) {
      if (Date.now() - start > OCR_BUILTIN_TIMEOUT_MS) {
        const remaining: number = sources.length - i;
        failed += remaining;
        hilog.warn(0xD5A0, 'OcrEngine', '内置识别整体超时（%{public}d ms），剩余 %{public}d 页截停',
          OCR_BUILTIN_TIMEOUT_MS, remaining);
        break;
      }
      try {
        const pageText: string = await runPaddlePage({ kind: sources[i].kind, data: sources[i].data });
        if (pageText !== '') {
          parts.push(pageText);
        }
      } catch (e) {
        failed++;
        hilog.warn(0xD5A0, 'OcrEngine', '内置识别第 %{public}d 页失败：%{public}s',
          i + 1, (e as Error).message);
      }
    }
    const ok: boolean = failed < sources.length;
    const partial: boolean = ok && failed > 0;
    return { ok: ok, text: ok ? parts.join('\n\n') : '', engine: 'builtin', partial: partial };
  } catch (e) {
    hilog.warn(0xD5A0, 'OcrEngine', '内置引擎整件异常：%{public}s', (e as Error).message);
    return { ok: false, text: '', engine: 'builtin', partial: false };
  }
}

// 单页识别一次（解码 → 识别）。PixelMap 释放在 finally——d.ts 原文警告「释放前确保关联
// 异步操作已结束」，必须晚于 recognizeText 返回；解码失败 pm 保持 null 无需释放
//（decodeScaled 内部 ImageSource 已成对释放，不绕开它自建）
async function recognizeSourceOnce(src: OcrImageSource): Promise<string> {
  let pm: image.PixelMap | null = null;
  try {
    if (src.kind === 'base64') {
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(src.data);
      pm = await decodeScaled(bytes.buffer as ArrayBuffer, PAGE_IMAGE_LONG_EDGE_PX, true);
    } else {
      pm = await decodeScaled(src.data, IMAGE_MAX_EDGE_PX, true);
    }
    const conf: textRecognition.TextRecognitionConfiguration = { isDirectionDetectionSupported: false };
    const res: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText({ pixelMap: pm }, conf);
    return res.value ?? '';
  } finally {
    if (pm !== null) {
      pm.release();
    }
  }
}

// 单页识别（带一次重试）：200 超时 / 1001400001 运行失败 → 立即重试一次（官方"择时重试"
//；本项目禁人为 sleep，故不设退避）；401 入参错 / 1001400002 服务异常（官方建议重启设备）
// 及其余错误不重试直接上抛（页级失败由 runSystemOcr 跳过）
const OCR_RETRYABLE_CODES: number[] = [200, 1001400001];

function ocrErrorCode(e: Object): number {
  const err = e as BusinessError;
  return typeof err.code === 'number' ? err.code : -1;
}

async function recognizeSource(src: OcrImageSource): Promise<string> {
  try {
    return await recognizeSourceOnce(src);
  } catch (e) {
    const code: number = ocrErrorCode(e);
    if (OCR_RETRYABLE_CODES.includes(code)) {
      hilog.warn(0xD5A0, 'OcrEngine', '识别瞬时错误（code %{public}d），立即重试一次', code);
      return await recognizeSourceOnce(src);
    }
    throw e as Error;
  }
}
