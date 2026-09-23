// 内置识别引擎纯函数层（2026-09-16，方案-内置PaddleOCR-20260916 §3.3/§六 阶段 1，ZCode 侧）。
// 与 providers/OcrPaddle.ets（推理编排：解码 / 三模型 predict / 出页文本）分开的理由 =
// 本件**零 import**——断言脚本可复制直跑（scripts/assert-attach-domain.mjs 105 组：
// entry/.../common/OcrPaddleText.ets → scripts/.tmp/OcrPaddleText.ts，Node 原生剥类型），
// 先例 = SseParser / SkillText / MemoryText（同「纯函数层 + 零 import」口径）。
// 覆盖五件：det 几何（letterbox）/ DB 后处理（二值化→连通域→框过滤→unclip→行合并→排序）/
// CTC 解码 / rec 分块与缩放几何 / 字典解析与类别数校验。
//
// ★ 超参真值源 = 模型仓 inference.yml（2026-09-16 阶段 0 实读，**不是**官方文档表格值——
//   文档该列写 None）：det thresh 0.2 / box_thresh 0.4 / unclip_ratio 1.4 /
//   max_candidates 3000（方案 §2.1 原引 0.3/0.6/1.5/1000 为旧版口径，阶段 0 已按实读改正）。
// ★ 类别数关系（阶段 0 设备实测）：C = 字典行数 + 2 —— 字符表 = ['blank'] + 字典 + [' ']
//   （PaddleOCR CTCLabelDecode：blank 置首、空格字符追加在**末尾**）。实测 C=6906 vs 字典 6904。
//   方案原写「类别数 − 1 === 字典行数」按实测作废，判据改 dictClassCountOk（唯一放行式），
//   **不匹配 = 该引擎失败，绝不带错字典硬跑**（方案 §3.2 末条）。
// ★ 长行分块（阶段 0 新增发现，方案未预见的硬需求）：rec 固定输入 48×320，单段可容纳的长宽比
//   上限 = 320/48 ≈ 6.67；整行超此比例时被横向挤压——阶段 0 对照实验（同一张德语行图）：
//   整行挤压解码 =「Viamine.un B2.en asevene mhrn ie」（全糊），按 6.4 比例切 6 段各自解码
//   再拼接 =「Vitamine C. D und B12. Eine ausgewogenee Ernährunq mit viel」（基本逐字正确）；
//   中文行同法由 2 处错降为 1 处错。故 rec 路**一律先分块**（recChunkSpans 单源），
//   切点优先落在低墨迹列（减少切字）。
// 纯函数（断言直跑面）：parseOcrDict / dictClassCountOk / detLetterboxGeom / dbExtractLines /
// ctcDecode / ocrClassChar / recChunkSpans / recResizeGeom / joinChunkText。

// det 输入边长（转换期固定 shape：--inputShape=x:1,3,960,960）
export const OCRP_DET_SIDE: number = 960;
// rec 输入高 / 宽（转换期固定 shape：--inputShape=x:1,3,48,320）
export const OCRP_REC_H: number = 48;
export const OCRP_REC_W: number = 320;
// cls 输入宽 / 高（转换期固定 shape：--inputShape=x:1,3,80,160）
export const OCRP_CLS_W: number = 160;
export const OCRP_CLS_H: number = 80;
// 两轴对齐步长（PaddleOCR DetResizeForTest resize_type0）
export const OCRP_ALIGN: number = 32;
// det 后处理超参（inference.yml 实读）
export const OCRP_DET_THRESH: number = 0.2;
export const OCRP_DET_BOX_THRESH: number = 0.4;
export const OCRP_DET_UNCLIP: number = 1.4;
export const OCRP_DET_MAX_CAND: number = 3000;
// 单块连通域最小像素数（噪点滤除）与框分数下限（= box_thresh，独立常量便于分档）
export const OCRP_MIN_COMPONENT_PX: number = 4;
// det letterbox 几何：长边收到 limit 且两轴对齐 32（原图长边未超 limit 则不放大——照
// PaddleOCR resize_type0 的 `max(h,w) > limit_side_len` 分支；小图原样，靠黑边补满）
export interface OcrDetGeom {
  ratio: number;
  newW: number;
  newH: number;
}

// 文本行框（det 后处理产出；坐标 = letterbox 图内像素，闭区间）
export interface OcrCropBox {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  score: number;
}

// rec 分块段（x0 含 / x1 不含——便于 slice 语义）
export interface OcrChunkSpan {
  x0: number;
  x1: number;
}

// rec 单段缩放几何（等比缩到高 targetH，宽不超 maxW）
export interface OcrRecGeom {
  resizeW: number;
  resizeH: number;
}

// 对齐 32（PaddleOCR：int(round(v/32)*32)，下限 32）
export function alignOcr32(v: number): number {
  return Math.max(Math.round(Math.round(v / OCRP_ALIGN) * OCRP_ALIGN), OCRP_ALIGN);
}

export function detLetterboxGeom(w: number, h: number, limit: number): OcrDetGeom {
  const longSide: number = Math.max(w, h);
  if (longSide <= limit || longSide <= 0 || w <= 0 || h <= 0) {
    const same: OcrDetGeom = { ratio: 1, newW: Math.min(w, limit), newH: Math.min(h, limit) };
    return same;
  }
  const ratio: number = limit / longSide;
  let newW: number = alignOcr32(w * ratio);
  let newH: number = alignOcr32(h * ratio);
  // 对齐可能把长边顶出 limit 一格（例：limit=960，比值后 959.6 → 960 恰好；但短边低位
  // 进位可能连带长边超界）——钳回 limit，防越界写缓冲
  if (newW > limit) {
    newW = limit;
  }
  if (newH > limit) {
    newH = limit;
  }
  const geom: OcrDetGeom = { ratio: ratio, newW: newW, newH: newH };
  return geom;
}

// DB 后处理：概率图 → 行框列表（字母序 = 阅读序：先上后下、同带先左后右）。
// 步骤 = 二值化（> thresh）→ 8 邻域连通域 → 面积/分数过滤 → unclip 外扩 → 行合并。
// unclip 用 DB 距离公式的轴对齐近似：d = 面积 × ratio ÷ 周长（PaddleOCR 走 pyclipper 多边形
// 偏移，本件只处理轴对齐框，故用同一距离公式的矩形外扩解）。
export function dbExtractLines(probs: Float32Array, w: number, h: number, thresh: number,
  boxThresh: number, unclipRatio: number, maxCandidates: number): OcrCropBox[] {
  const boxes: OcrCropBox[] = [];
  if (w <= 0 || h <= 0 || probs.length < w * h) {
    return boxes;
  }
  const mask: Uint8Array = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) {
    mask[i] = probs[i] > thresh ? 1 : 0;
  }
  const visited: Uint8Array = new Uint8Array(w * h);
  const stack: Int32Array = new Int32Array(w * h);
  for (let start = 0; start < w * h; start++) {
    if (mask[start] === 0 || visited[start] === 1) {
      continue;
    }
    let sp: number = 0;
    stack[sp] = start;
    sp++;
    visited[start] = 1;
    let minX: number = w;
    let maxX: number = -1;
    let minY: number = h;
    let maxY: number = -1;
    let count: number = 0;
    let sum: number = 0;
    while (sp > 0) {
      sp--;
      const idx: number = stack[sp];
      const y: number = Math.floor(idx / w);
      const x: number = idx - y * w;
      count++;
      sum += probs[idx];
      if (x < minX) {
        minX = x;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (y > maxY) {
        maxY = y;
      }
      for (let dy = -1; dy <= 1; dy++) {
        const ny: number = y + dy;
        if (ny < 0 || ny >= h) {
          continue;
        }
        for (let dx = -1; dx <= 1; dx++) {
          const nx: number = x + dx;
          if (nx < 0 || nx >= w) {
            continue;
          }
          const nIdx: number = ny * w + nx;
          if (mask[nIdx] === 1 && visited[nIdx] === 0) {
            visited[nIdx] = 1;
            stack[sp] = nIdx;
            sp++;
          }
        }
      }
    }
    if (count < OCRP_MIN_COMPONENT_PX) {
      continue;
    }
    const score: number = sum / count;
    if (score < boxThresh) {
      continue;
    }
    const bw: number = maxX - minX + 1;
    const bh: number = maxY - minY + 1;
    const perimeter: number = 2 * (bw + bh);
    const pad: number = perimeter > 0 ? Math.round(count * unclipRatio / perimeter) : 0;
    const box: OcrCropBox = {
      x0: Math.max(minX - pad, 0),
      y0: Math.max(minY - pad, 0),
      x1: Math.min(maxX + pad, w - 1),
      y1: Math.min(maxY + pad, h - 1),
      score: score
    };
    boxes.push(box);
    if (boxes.length >= maxCandidates) {
      break;
    }
  }
  return mergeOcrLines(boxes);
}

// 行合并：竖直投影重叠 ≥ 短边一半 且 水平间隙 ≤ max(短边×0.8, 8px) 的两框归同一行
//（DB 二值图里同一文本行常被字间空隙切成多段连通域，不合并 = rec 只读到半个句子）
export function mergeOcrLines(boxes: OcrCropBox[]): OcrCropBox[] {
  const sorted: OcrCropBox[] = boxes.slice().sort((a: OcrCropBox, b: OcrCropBox): number => {
    const dy: number = a.y0 - b.y0;
    return dy !== 0 ? dy : a.x0 - b.x0;
  });
  const lines: OcrCropBox[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const b: OcrCropBox = sorted[i];
    let merged: boolean = false;
    for (let j = 0; j < lines.length; j++) {
      const l: OcrCropBox = lines[j];
      const overlap: number = Math.min(l.y1, b.y1) - Math.max(l.y0, b.y0);
      const minH: number = Math.min(l.y1 - l.y0, b.y1 - b.y0) + 1;
      if (overlap * 2 < minH) {
        continue;
      }
      let gapX: number = 0;
      if (b.x0 > l.x1) {
        gapX = b.x0 - l.x1;
      } else if (l.x0 > b.x1) {
        gapX = l.x0 - b.x1;
      }
      if (gapX > Math.max(minH * 0.8, 8)) {
        continue;
      }
      const mergedBox: OcrCropBox = {
        x0: Math.min(l.x0, b.x0),
        y0: Math.min(l.y0, b.y0),
        x1: Math.max(l.x1, b.x1),
        y1: Math.max(l.y1, b.y1),
        score: (l.score + b.score) / 2
      };
      lines[j] = mergedBox;
      merged = true;
      break;
    }
    if (!merged) {
      const copy: OcrCropBox = { x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1, score: b.score };
      lines.push(copy);
    }
  }
  lines.sort((a: OcrCropBox, b: OcrCropBox): number => {
    const dy: number = a.y0 - b.y0;
    return dy !== 0 ? dy : a.x0 - b.x0;
  });
  return lines;
}

// rec 分块：整行宽 cw、高 ch，单块宽上限 = floor(ch × maxW/targetH)，切点优先落在低墨迹列
//（ink = 逐列墨迹量，长度应 ≥ cw；传 null / 长度不足则按等距切——低墨迹搜索窗 = 理想切点
// 前后各 15% 块宽，取其内 ink 最小列）。返回段按序，x0 含 x1 不含。
export function recChunkSpans(cw: number, ch: number, targetH: number, maxW: number,
  ink: Float32Array | null): OcrChunkSpan[] {
  const spans: OcrChunkSpan[] = [];
  if (cw <= 0 || ch <= 0) {
    return spans;
  }
  const maxAspect: number = maxW / targetH;
  const chunkW: number = Math.max(Math.floor(ch * maxAspect), 1);
  if (cw <= chunkW) {
    const whole: OcrChunkSpan = { x0: 0, x1: cw };
    spans.push(whole);
    return spans;
  }
  let x: number = 0;
  while (x < cw) {
    let end: number = Math.min(x + chunkW, cw);
    if (end < cw) {
      end = pickLowInkCut(x, end, cw, chunkW, ink);
    }
    const span: OcrChunkSpan = { x0: x, x1: end };
    spans.push(span);
    x = end;
  }
  return spans;
}

// 低墨迹切点：在 [ideal−window, ideal+window] 内挑 ink 最小列（并列取最靠左）；无 ink 数据
// 直接用 ideal。窗宽 = 块宽的 15%（至少 2px）
function pickLowInkCut(start: number, ideal: number, cw: number, chunkW: number,
  ink: Float32Array | null): number {
  if (ink === null || ink.length < cw) {
    return ideal;
  }
  const window: number = Math.max(Math.round(chunkW * 0.15), 2);
  const lo: number = Math.max(start + 1, ideal - window);
  const hi: number = Math.min(cw - 1, ideal + window);
  let best: number = ideal;
  let bestInk: number = -1;
  for (let i = lo; i <= hi; i++) {
    const cur: number = ink[i];
    if (bestInk < 0 || cur < bestInk) {
      bestInk = cur;
      best = i;
    }
  }
  return best;
}

// rec 单段缩放几何：等比缩到高 targetH，宽 = min(maxW, ceil(targetH × 宽/高))（PaddleOCR
// resize_norm_img 同式——超宽不裁切，靠 maxW 上限截断）
export function recResizeGeom(cw: number, ch: number, targetH: number, maxW: number): OcrRecGeom {
  if (cw <= 0 || ch <= 0) {
    const zero: OcrRecGeom = { resizeW: 0, resizeH: 0 };
    return zero;
  }
  const ratio: number = cw / ch;
  const w: number = Math.min(maxW, Math.ceil(targetH * ratio));
  const geom: OcrRecGeom = { resizeW: Math.max(w, 1), resizeH: targetH };
  return geom;
}

// 字典解析：按行切、去 \r、丢空行（官方 ppocrv6_tiny_dict.txt 一行一字符，含 `'` 这类
// 容易被误处理的字符——故不做引号剥离，原样收）
export function parseOcrDict(text: string): string[] {
  const raw: string[] = text.split('\n');
  const chars: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    const line: string = raw[i].charAt(raw[i].length - 1) === '\r' ?
      raw[i].substring(0, raw[i].length - 1) : raw[i];
    if (line.length > 0) {
      chars.push(line);
    }
  }
  return chars;
}

// 类别数校验：唯一放行式——C 必须等于「字典行数 + 2」（blank + 字典 + 空格）。不符 =
// 模型与字典不配套，该引擎判失败，绝不带错字典硬跑
export function dictClassCountOk(classCount: number, dictLen: number): boolean {
  return dictLen > 0 && classCount === dictLen + 2;
}

// 类别下标 → 字符（0 = blank 空串；1..dict.length = 字典项；末尾空格位仅当类别数吻合时给 ' '）
export function ocrClassChar(idx: number, dict: string[], classCount: number): string {
  if (idx <= 0) {
    return '';
  }
  if (idx <= dict.length) {
    return dict[idx - 1];
  }
  if (idx === dict.length + 1 && classCount === dict.length + 2) {
    return ' ';
  }
  return '';
}

// CTC 贪心解码：逐帧取 argmax → 跳 blank（0）→ 去连续重复 → 映射字符
export function ctcDecode(flat: Float32Array, t: number, classCount: number,
  dict: string[]): string {
  if (t <= 0 || classCount <= 0 || flat.length < t * classCount) {
    return '';
  }
  let out: string = '';
  let prev: number = -1;
  for (let step = 0; step < t; step++) {
    const base: number = step * classCount;
    let best: number = 0;
    let bestV: number = flat[base];
    for (let c = 1; c < classCount; c++) {
      const v: number = flat[base + c];
      if (v > bestV) {
        bestV = v;
        best = c;
      }
    }
    if (best !== 0 && best !== prev) {
      out += ocrClassChar(best, dict, classCount);
    }
    prev = best;
  }
  return out;
}

// 分块结果拼接：逐段去首尾空白后相接。段间不补空格——★ 2026-09-16 v4 真机实测反证：曾按
// 「切点零墨迹槽宽 ≥ 平均字宽 × 0.25 即补空格」的启发式补词间空格，实测**两边都插错**
//（中文插出「维生 素」「来源是 日晒」，德语插出「lebenswichti ge」「versorg t」），而该补的
// 词间空格（sindlebenswichtige）仍未补上——按证据回退，不补空格（丢空格的代价小于插错空格：
// v3 实测中文 7 行近逐字正确、德语 7 行可读）。真正的解法 = 分块重叠解码 + 重叠文本归并，
// 属后续项（登记在变更记录，未实现）。全空段忽略
export function joinChunkText(pieces: string[]): string {
  let out: string = '';
  for (let i = 0; i < pieces.length; i++) {
    out += trimOcrSpace(pieces[i]);
  }
  return out;
}

function trimOcrSpace(s: string): string {
  let start: number = 0;
  let end: number = s.length;
  while (start < end && (s.charAt(start) === ' ' || s.charAt(start) === '\t')) {
    start++;
  }
  while (end > start && (s.charAt(end - 1) === ' ' || s.charAt(end - 1) === '\t')) {
    end--;
  }
  return s.substring(start, end);
}
