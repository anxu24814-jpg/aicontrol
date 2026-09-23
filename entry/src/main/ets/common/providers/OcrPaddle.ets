// 内置识别引擎推理编排（2026-09-16，方案-内置PaddleOCR-20260916 §3.3，ZCode 侧）：
// PP-OCRv6 tiny 三模型（det / rec / cls）经 converter_lite 转 .ms 随包，由**鸿蒙系统内置**
// MindSpore Lite 推理——完全离线，图不出设备。纯函数层在 common/OcrPaddleText.ets
//（零 import、断言直跑）；本件只管 IO 与编排：rawfile 取模 / 解码 / 张量填充 / 出页文本。
//
// ★ 阶段 0 设备实测结论（2026-09-16，独立探针工程装机跑通，判据三条全过）——以下四点按
//   实测落地，与方案
//   字面有偏差处即本头注释为准：
//   ① **输入张量布局 = NHWC**（不是方案预设的 NCHW）：三模型实测 shape = det [1,960,960,3]、
//      rec [1,48,320,3]、cls [1,80,160,3]（converter_lite 的 --inputDataFormat 默认 NHWC 且
//      四维输入生效）。故本件**直接按 HWC 顺序写缓冲**（构建期即按 HWC 落位，运行期零重排
//      ——方案 §3.2「取运行时最简的一路」的答案）。
//   ② **cls 必须转换期固定 shape**：不加 --inputShape 转出的 cls.ms 在推理时 CheckInputs
//      failed（宿主 Windows benchmark 与图一致），补 --inputShape=x:1,3,80,160 后通过。
//      三模型转换命令见 docs 阶段 0 验证记录；.ms 体积 det 1.69MB / rec 4.24MB / cls 0.94MB。
//   ③ **rec 长行必须分块**（纯函数层 recChunkSpans 单源，理由见 OcrPaddleText 头注释）。
//   ④ 类别数 = 字典行数 + 2（blank + 字典 + 末尾空格），dictClassCountOk 唯一放行。
// ★ 模型**进程级常驻、永不释放**：官方 ArkTS API 未提供 close / dispose / release，且
//   MindSpore Lite 模型对象无释放接口——**禁**在此补伪释放机制（如置 null 再懒加载，看着像
//   省内存实则只是让下次多付一次加载耗时；真机内存压力有证据再议）。系统识别引擎那套
//   init/release 成对契约**不适用**于本件（那是 CoreVisionKit 的接口要求，勿照搬）。
// ★ 加载路径 = 官方示例口径：resourceManager.getRawFileContent() → loadModelFromBuffer
//   （官方 FAQ 明文：rawfile 的 fd 不是文件系统 fd，**禁**走 loadModelFromFd）。
// ★ 懒加载 + 单飞：ensurePaddleReady 用模块级 promise 保证并发首调只加载一次（三模型加载
//   实测约 35ms 量级，但重复加载会白耗内存）。
// ★ 无模型释放 **不等于** 无失败重试：加载失败（缺文件/加载异常）不复位 promise——一次失败
//   即引擎本次会话不可用（走回退编排换引擎），防「每次识别都重付加载失败的开销」。
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { decodeScaled } from '../ImageEditUtil';
import { IMAGE_MAX_EDGE_PX } from '../AttachmentUtil';
import { PAGE_IMAGE_LONG_EDGE_PX } from '../DocumentParse';
import {
  OCRP_DET_SIDE, OCRP_REC_H, OCRP_REC_W, OCRP_CLS_W, OCRP_CLS_H,
  OCRP_DET_THRESH, OCRP_DET_BOX_THRESH, OCRP_DET_UNCLIP, OCRP_DET_MAX_CAND,
  OcrCropBox, OcrChunkSpan, OcrDetGeom, OcrRecGeom, dbExtractLines, detLetterboxGeom,
  recChunkSpans, recResizeGeom, parseOcrDict, dictClassCountOk, ctcDecode, joinChunkText
} from '../OcrPaddleText';

const TAG: string = 'OcrPaddle';
// 模型与字典 rawfile 路径（entry/src/main/resources/rawfile/ocr/）
const DET_MODEL_RAW: string = 'ocr/det.ms';
const REC_MODEL_RAW: string = 'ocr/rec.ms';
const CLS_MODEL_RAW: string = 'ocr/cls.ms';
const DICT_RAW: string = 'ocr/rec_dict.txt';
// 行内墨迹判定阈值（灰度低于此值算墨迹——用于分块切点找低墨迹列）
const INK_GRAY_THRESH: number = 128;
// cls 判 180° 的置信下限（低于此值按正向处理——避免低置信误转把好行转坏）
const CLS_FLIP_CONF: number = 0.5;

// 单页识别源（与 OcrEngine.OcrImageSource 同形——本件不反向 import OcrEngine，避免环形依赖）
export interface OcrPaddleSource {
  kind: string;
  data: string;
}

// 引擎态（模块级单例）
let resourceManagerRef: common.Context | null = null;
let readyPromise: Promise<boolean> | null = null;
let detModel: mindSporeLite.Model | null = null;
let recModel: mindSporeLite.Model | null = null;
let clsModel: mindSporeLite.Model | null = null;
let ocrDict: string[] = [];

// 资源管理器注入（调用点 = EntryAbility.onCreate——common 层拿不到 UIContext，能力上下文是
// 应用级单一真源；与 persistProp 注册同处，属组合根职责）
export function paddleAttachContext(ctx: common.Context): void {
  resourceManagerRef = ctx;
}

// 能力探测（系统部件是否内置 MindSpore Lite；假 = 本引擎不可用，回退编排换引擎）
export function paddleAvailable(): boolean {
  return canIUse('SystemCapability.AI.MindSporeLite');
}

// 就绪保证（幂等单飞；false = 本次会话本引擎不可用）。失败不复位——见头注释 ★
export async function ensurePaddleReady(): Promise<boolean> {
  if (readyPromise !== null) {
    return readyPromise;
  }
  readyPromise = loadAll();
  return readyPromise;
}

async function loadAll(): Promise<boolean> {
  const ctx: common.Context | null = resourceManagerRef;
  if (ctx === null) {
    hilog.warn(0xD5A0, TAG, '内置引擎未注入上下文（paddleAttachContext 未调用）');
    return false;
  }
  if (!paddleAvailable()) {
    hilog.warn(0xD5A0, TAG, '设备不支持 MindSpore Lite（canIUse false）');
    return false;
  }
  try {
    const dictBytes: Uint8Array = await ctx.resourceManager.getRawFileContent(DICT_RAW);
    ocrDict = parseOcrDict(util.TextDecoder.create('utf-8').decodeToString(dictBytes));
    if (ocrDict.length === 0) {
      hilog.warn(0xD5A0, TAG, '字典为空——内置引擎不可用');
      return false;
    }
    detModel = await loadOne(ctx, DET_MODEL_RAW, 'det');
    recModel = await loadOne(ctx, REC_MODEL_RAW, 'rec');
    clsModel = await loadOne(ctx, CLS_MODEL_RAW, 'cls');
    // 类别数校验（dictClassCountOk 唯一放行式）：模型输出末维与字典不配套 → 判失败，
    // 绝不带错字典硬跑（方案 §3.2；校验用 rec 模型 48×320 的一次空跑探形状，代价 ~3ms）
    const probe: Float32Array = new Float32Array(3 * OCRP_REC_H * OCRP_REC_W);
    const outs: mindSporeLite.MSTensor[] = await runModel(recModel, probe, OCRP_REC_H, OCRP_REC_W);
    const dims: number[] = outs[0].shape;
    const classCount: number = dims[dims.length - 1];
    if (!dictClassCountOk(classCount, ocrDict.length)) {
      hilog.warn(0xD5A0, TAG, '类别数 %{public}d 与字典行数 %{public}d 不配套——内置引擎不可用',
        classCount, ocrDict.length);
      return false;
    }
    hilog.info(0xD5A0, TAG, '内置引擎就绪（字典 %{public}d 行，类别数 %{public}d）',
      ocrDict.length, classCount);
    return true;
  } catch (e) {
    hilog.warn(0xD5A0, TAG, '内置引擎加载异常：%{public}s', (e as Error).message);
    return false;
  }
}

async function loadOne(ctx: common.Context, raw: string, name: string): Promise<mindSporeLite.Model> {
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(raw);
  const cpu: mindSporeLite.CpuDevice = {};
  cpu.threadNum = 2;
  cpu.threadAffinityMode = mindSporeLite.ThreadAffinityMode.BIG_CORES_FIRST;
  cpu.precisionMode = 'enforce_fp32';
  const mctx: mindSporeLite.Context = {};
  mctx.target = ['cpu'];
  mctx.cpu = cpu;
  const model: mindSporeLite.Model =
    await mindSporeLite.loadModelFromBuffer(bytes.buffer as ArrayBuffer, mctx);
  hilog.info(0xD5A0, TAG, '模型已加载 %{public}s（%{public}d B）', name, bytes.byteLength);
  return model;
}

// 单页识别（空串 = 本页无文字或识别失败——页级失败由 OcrEngine 的整件编排计失败并跳过）
export async function runPaddlePage(src: OcrPaddleSource): Promise<string> {
  let pm: image.PixelMap | null = null;
  try {
    if (src.kind === 'base64') {
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(src.data);
      pm = await decodeScaled(bytes.buffer as ArrayBuffer, PAGE_IMAGE_LONG_EDGE_PX, true);
    } else {
      pm = await decodeScaled(src.data, IMAGE_MAX_EDGE_PX, true);
    }
    const info: image.ImageInfo = await pm.getImageInfo();
    const w: number = info.size.width;
    const h: number = info.size.height;
    const stride: number = pm.getBytesNumberPerRow();
    const total: number = pm.getPixelBytesNumber();
    const buf: ArrayBuffer = new ArrayBuffer(total);
    await pm.readPixelsToBuffer(buf);
    const text: string = await recognizeRgba(new Uint8Array(buf), w, h, stride);
    return text;
  } finally {
    // 成对释放（与 decodeScaled 建的对——d.ts 要求释放晚于关联异步操作结束）
    if (pm !== null) {
      pm.release();
    }
  }
}

// 页像素 → 文本（RP 阶段 0 探针同链路的线上版）：letterbox → det → 行框 → 逐行 cls/分块 rec
async function recognizeRgba(rgba: Uint8Array, w: number, h: number, stride: number): Promise<string> {
  if (detModel === null || recModel === null || clsModel === null) {
    return '';
  }
  const geom: OcrDetGeom = detLetterboxGeom(w, h, OCRP_DET_SIDE);
  const bgr: Uint8Array = buildLetterboxBgr(rgba, w, h, stride, geom);
  const detInput: Float32Array = bgrToImagenetHwc(bgr, OCRP_DET_SIDE, OCRP_DET_SIDE);
  const detOut: mindSporeLite.MSTensor[] =
    await runModel(detModel, detInput, OCRP_DET_SIDE, OCRP_DET_SIDE);
  const probs: Float32Array = new Float32Array(detOut[0].getData());
  const boxes: OcrCropBox[] = dbExtractLines(probs, OCRP_DET_SIDE, OCRP_DET_SIDE,
    OCRP_DET_THRESH, OCRP_DET_BOX_THRESH, OCRP_DET_UNCLIP, OCRP_DET_MAX_CAND);
  const lines: string[] = [];
  for (let i = 0; i < boxes.length; i++) {
    const lineText: string = await recognizeLine(bgr, boxes[i]);
    if (lineText !== '') {
      lines.push(lineText);
    }
  }
  return lines.join('\n');
}

// 单行识别：裁行 → cls 判向（180° 则转正）→ 分块 rec → 拼接
async function recognizeLine(bgr: Uint8Array, box: OcrCropBox): Promise<string> {
  if (recModel === null || clsModel === null) {
    return '';
  }
  let crop: OcrRgbaCrop = cropBgrToRgba(bgr, box);
  if (crop.w <= 0 || crop.h <= 0) {
    return '';
  }
  const clsInput: Float32Array = rgbaToImagenetHwc(crop.rgba, crop.w, crop.h, OCRP_CLS_W, OCRP_CLS_H);
  const clsOut: mindSporeLite.MSTensor[] =
    await runModel(clsModel, clsInput, OCRP_CLS_H, OCRP_CLS_W);
  const clsLogits: Float32Array = new Float32Array(clsOut[0].getData());
  if (clsLogits.length >= 2 && clsLogits[1] > clsLogits[0] &&
    clsLogits[1] >= CLS_FLIP_CONF) {
    crop = rotateRgba180(crop);
  }
  const ink: Float32Array = inkProfile(crop);
  const spans: OcrChunkSpan[] = recChunkSpans(crop.w, crop.h, OCRP_REC_H, OCRP_REC_W, ink);
  const pieces: string[] = [];
  for (let i = 0; i < spans.length; i++) {
    const recInput: Float32Array = chunkToRecInput(crop, spans[i]);
    const recOut: mindSporeLite.MSTensor[] =
      await runModel(recModel, recInput, OCRP_REC_H, OCRP_REC_W);
    const dims: number[] = recOut[0].shape;
    const flat: Float32Array = new Float32Array(recOut[0].getData());
    pieces.push(ctcDecode(flat, dims[dims.length - 2], dims[dims.length - 1], ocrDict));
  }
  return joinChunkText(pieces);
}

// 模型推理（张量按 HWC 落位——NHWC 实测口径见头注释①；输入张量由 getInputs 取，setData 填充）
async function runModel(model: mindSporeLite.Model, hwc: Float32Array, h: number,
  w: number): Promise<mindSporeLite.MSTensor[]> {
  const inputs: mindSporeLite.MSTensor[] = model.getInputs();
  inputs[0].setData(hwc.buffer as ArrayBuffer);
  return await model.predict(inputs);
}

// ── 页面图预处理（纯计算，与纯函数层分家的理由 = 这些是像素搬运，不做语义决策）──

interface OcrRgbaCrop {
  w: number;
  h: number;
  rgba: Uint8Array;
}

// RGBA 页图 → letterbox 后的 BGR 全画布（黑边填充；未超限的图原样左上角放置）
function buildLetterboxBgr(rgba: Uint8Array, w: number, h: number, stride: number,
  geom: OcrDetGeom): Uint8Array {
  const out: Uint8Array = new Uint8Array(OCRP_DET_SIDE * OCRP_DET_SIDE * 3);
  const dstW: number = geom.newW;
  const dstH: number = geom.newH;
  for (let dy = 0; dy < dstH; dy++) {
    const fy: number = (dy + 0.5) * h / dstH - 0.5;
    let y0: number = Math.floor(fy);
    const wy: number = fy - y0;
    let y1: number = y0 + 1;
    if (y0 < 0) {
      y0 = 0;
    }
    if (y0 > h - 1) {
      y0 = h - 1;
    }
    if (y1 > h - 1) {
      y1 = h - 1;
    }
    for (let dx = 0; dx < dstW; dx++) {
      const fx: number = (dx + 0.5) * w / dstW - 0.5;
      let x0: number = Math.floor(fx);
      const wx: number = fx - x0;
      let x1: number = x0 + 1;
      if (x0 < 0) {
        x0 = 0;
      }
      if (x0 > w - 1) {
        x0 = w - 1;
      }
      if (x1 > w - 1) {
        x1 = w - 1;
      }
      const i00: number = y0 * stride + x0 * 4;
      const i01: number = y0 * stride + x1 * 4;
      const i10: number = y1 * stride + x0 * 4;
      const i11: number = y1 * stride + x1 * 4;
      const o: number = (dy * OCRP_DET_SIDE + dx) * 3;
      // 通道序 BGR（模型按 BGR 训练；RGBA 源通道 0=R 1=G 2=B）
      for (let c = 0; c < 3; c++) {
        const sc: number = 2 - c;
        const v00: number = rgba[i00 + sc];
        const v01: number = rgba[i01 + sc];
        const v10: number = rgba[i10 + sc];
        const v11: number = rgba[i11 + sc];
        const top: number = v00 + (v01 - v00) * wx;
        const bot: number = v10 + (v11 - v10) * wx;
        out[o + c] = Math.round(top + (bot - top) * wy);
      }
    }
  }
  return out;
}

// BGR 全画布 → ImageNet 归一化 HWC（det 输入；黑边像素 0 归一化后为负值，与 PaddleOCR
// 「先补零再归一化」同序）
function bgrToImagenetHwc(bgr: Uint8Array, w: number, h: number): Float32Array {
  const out: Float32Array = new Float32Array(w * h * 3);
  for (let i = 0; i < w * h; i++) {
    const s: number = i * 3;
    out[s] = (bgr[s] / 255 - 0.485) / 0.229;
    out[s + 1] = (bgr[s + 1] / 255 - 0.456) / 0.224;
    out[s + 2] = (bgr[s + 2] / 255 - 0.406) / 0.225;
  }
  return out;
}

// BGR 全画布 → 行框裁片（RGBA，供 cls 与 rec 共用；越界钳位）
function cropBgrToRgba(bgr: Uint8Array, box: OcrCropBox): OcrRgbaCrop {
  const x0: number = Math.max(box.x0, 0);
  const y0: number = Math.max(box.y0, 0);
  const x1: number = Math.min(box.x1, OCRP_DET_SIDE - 1);
  const y1: number = Math.min(box.y1, OCRP_DET_SIDE - 1);
  const cw: number = Math.max(x1 - x0 + 1, 0);
  const ch: number = Math.max(y1 - y0 + 1, 0);
  const rgba: Uint8Array = new Uint8Array(cw * ch * 4);
  for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
      const s: number = ((y0 + y) * OCRP_DET_SIDE + (x0 + x)) * 3;
      const d: number = (y * cw + x) * 4;
      rgba[d] = bgr[s + 2];
      rgba[d + 1] = bgr[s + 1];
      rgba[d + 2] = bgr[s];
      rgba[d + 3] = 255;
    }
  }
  const crop: OcrRgbaCrop = { w: cw, h: ch, rgba: rgba };
  return crop;
}

// 180° 旋转（cls 判倒置时转正后再识别）
function rotateRgba180(crop: OcrRgbaCrop): OcrRgbaCrop {
  const w: number = crop.w;
  const h: number = crop.h;
  const rgba: Uint8Array = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const s: number = (y * w + x) * 4;
      const d: number = ((h - 1 - y) * w + (w - 1 - x)) * 4;
      rgba[d] = crop.rgba[s];
      rgba[d + 1] = crop.rgba[s + 1];
      rgba[d + 2] = crop.rgba[s + 2];
      rgba[d + 3] = 255;
    }
  }
  const out: OcrRgbaCrop = { w: w, h: h, rgba: rgba };
  return out;
}

// 逐列墨迹量（灰度 < INK_GRAY_THRESH 的像素计数——分块切点找低墨迹列用）
function inkProfile(crop: OcrRgbaCrop): Float32Array {
  const ink: Float32Array = new Float32Array(crop.w);
  for (let x = 0; x < crop.w; x++) {
    let cnt: number = 0;
    for (let y = 0; y < crop.h; y++) {
      const i: number = (y * crop.w + x) * 4;
      const gray: number = (crop.rgba[i] + crop.rgba[i + 1] + crop.rgba[i + 2]) / 3;
      if (gray < INK_GRAY_THRESH) {
        cnt++;
      }
    }
    ink[x] = cnt;
  }
  return ink;
}

// 裁片 → 单段 rec 输入（等比缩到高 48、宽 ≤320，归一化 (x/255−0.5)/0.5，右侧补 0 到 320；
// HWC 落位——见头注释①）
function chunkToRecInput(crop: OcrRgbaCrop, span: OcrChunkSpan): Float32Array {
  const out: Float32Array = new Float32Array(OCRP_REC_H * OCRP_REC_W * 3);
  const cw: number = Math.max(span.x1 - span.x0, 1);
  const geom: OcrRecGeom = recResizeGeom(cw, crop.h, OCRP_REC_H, OCRP_REC_W);
  for (let dy = 0; dy < OCRP_REC_H; dy++) {
    const fy: number = (dy + 0.5) * crop.h / OCRP_REC_H - 0.5;
    let y0: number = Math.floor(fy);
    const wy: number = fy - y0;
    let y1: number = y0 + 1;
    if (y0 < 0) {
      y0 = 0;
    }
    if (y0 > crop.h - 1) {
      y0 = crop.h - 1;
    }
    if (y1 > crop.h - 1) {
      y1 = crop.h - 1;
    }
    for (let dx = 0; dx < geom.resizeW; dx++) {
      const fx: number = (dx + 0.5) * cw / geom.resizeW - 0.5;
      let x0: number = Math.floor(fx);
      const wx: number = fx - x0;
      let x1: number = x0 + 1;
      if (x0 < 0) {
        x0 = 0;
      }
      if (x0 > cw - 1) {
        x0 = cw - 1;
      }
      if (x1 > cw - 1) {
        x1 = cw - 1;
      }
      const px0: number = span.x0 + x0;
      const px1: number = span.x0 + x1;
      const i00: number = (y0 * crop.w + px0) * 4;
      const i01: number = (y0 * crop.w + px1) * 4;
      const i10: number = (y1 * crop.w + px0) * 4;
      const i11: number = (y1 * crop.w + px1) * 4;
      const o: number = (dy * OCRP_REC_W + dx) * 3;
      for (let c = 0; c < 3; c++) {
        const sc: number = 2 - c;
        const v00: number = crop.rgba[i00 + sc];
        const v01: number = crop.rgba[i01 + sc];
        const v10: number = crop.rgba[i10 + sc];
        const v11: number = crop.rgba[i11 + sc];
        const top: number = v00 + (v01 - v00) * wx;
        const bot: number = v10 + (v11 - v10) * wx;
        const v: number = Math.round(top + (bot - top) * wy);
        out[o + c] = (v / 255 - 0.5) / 0.5;
      }
    }
    // 右侧补 0（归一化空间的 0 = 灰 127.5，与 PaddleOCR resize_norm_img 同序）
    for (let dx = geom.resizeW; dx < OCRP_REC_W; dx++) {
      const o: number = (dy * OCRP_REC_W + dx) * 3;
      out[o] = 0;
      out[o + 1] = 0;
      out[o + 2] = 0;
    }
  }
  return out;
}

// cls 输入：裁片等比缩到 160×80（不保比例——官方 PreProcess 就是直接 resize 到 160×80），
// ImageNet 归一化，HWC
function rgbaToImagenetHwc(rgba: Uint8Array, cw: number, ch: number, w: number,
  h: number): Float32Array {
  const out: Float32Array = new Float32Array(w * h * 3);
  for (let dy = 0; dy < h; dy++) {
    const fy: number = (dy + 0.5) * ch / h - 0.5;
    let y0: number = Math.floor(fy);
    const wy: number = fy - y0;
    let y1: number = y0 + 1;
    if (y0 < 0) {
      y0 = 0;
    }
    if (y0 > ch - 1) {
      y0 = ch - 1;
    }
    if (y1 > ch - 1) {
      y1 = ch - 1;
    }
    for (let dx = 0; dx < w; dx++) {
      const fx: number = (dx + 0.5) * cw / w - 0.5;
      let x0: number = Math.floor(fx);
      const wx: number = fx - x0;
      let x1: number = x0 + 1;
      if (x0 < 0) {
        x0 = 0;
      }
      if (x0 > cw - 1) {
        x0 = cw - 1;
      }
      if (x1 > cw - 1) {
        x1 = cw - 1;
      }
      const i00: number = (y0 * cw + x0) * 4;
      const i01: number = (y0 * cw + x1) * 4;
      const i10: number = (y1 * cw + x0) * 4;
      const i11: number = (y1 * cw + x1) * 4;
      const o: number = (dy * w + dx) * 3;
      const mean: number[] = [0.485, 0.456, 0.406];
      const std: number[] = [0.229, 0.224, 0.225];
      for (let c = 0; c < 3; c++) {
        const sc: number = 2 - c;
        const v00: number = rgba[i00 + sc];
        const v01: number = rgba[i01 + sc];
        const v10: number = rgba[i10 + sc];
        const v11: number = rgba[i11 + sc];
        const top: number = v00 + (v01 - v00) * wx;
        const bot: number = v10 + (v11 - v10) * wx;
        const v: number = Math.round(top + (bot - top) * wy);
        out[o + c] = (v / 255 - mean[c]) / std[c];
      }
    }
  }
  return out;
}
