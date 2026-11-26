/**
 * 公式位图的进程级 LRU 缓存服务（模块级单例）+ native 渲染管线唯一入口。
 *
 * 为什么单开一件：治「进会先源码后渲染」——列表重挂载后每条公式从零走 native 排版
 * 与解码链；本件把成品 PixelMap 按资源四元键（MathRenderPolicy.mathResourceKey）跨挂载
 * 复用，热缓存下块级 aboutToAppear 同步出图、行内经父预填当帧出图。
 *
 * 寿命契约：本件不持有任何组件、回调或闭包引用（App 级单例不得持页面级短寿命对象）；
 * 调用方只借不拥——acquire/release 成对记账，PixelMap 的 release 只在本件内三处发生
 *（淘汰计划产出 / 同键收养替换 / invalidate 借用归零），组件侧禁直接 pixelMap.release()
 *（SDK 无引用计数，release 后再触报 7600105——「缓存持有 + 借用计数 + 唯一 release 点」
 * 是唯一安全形态）。拒收面（单条超上限）所有权留组件自释放。
 *
 * 在途去重：同键并发 resolve 共享同一 Promise（含失败结果）；Promise 由本件持有，故 native
 * 排版 + 解码链整体驻本件（自 MarkdownMath.drain 原样搬迁，fail 文案与判据逐字不动）——
 * 若链留组件而 Service 持组件闭包即违寿命匹配红线。
 */
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LatexMathColorFormat, latexStringToImageWithError, TeXParseResult, TeXResultCode }
  from '@cangjie-tpc/formula_hybrid';
import { MATH_RENDER_CACHE_BYTE_BUDGET, MATH_RENDER_CACHE_CAPACITY, MATH_RENDER_CACHE_ENTRY_MAX_BYTES,
  mathEntryBytes, mathLruEvictPlan } from '../../../common/markdown/MathRenderPolicy';

/** width/height 均为 vp；PixelMap 所有权归 MathRenderService（缓存持有 + 借用计数），消费方只借。 */
export interface MarkdownMathImage {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

/** resolve 结果：surface=null 时 failText 为渲染链 fail 点文案（逐字自 MarkdownMath.drain 搬迁）；
 *  cached=false = 拒收私有面（单条超上限或同键死条目占用——所有权留组件自释放）。 */
export interface MathRenderResult {
  surface: MarkdownMathImage | null;
  failText: string;
  cached: boolean;
}

// 资源安全上界，不宣称性能阈值。超界仍显示完整源码，不截断/更改 AST（判据与 MarkdownMath
// 源上界同族）；releaseMathResource 驻本件单源导出——组件私有面释放也走这里。
const MAX_MATH_IMAGE_BYTES: number = 16 * 1024 * 1024;
const MAX_MATH_IMAGE_PIXELS: number = 4 * 1024 * 1024;
const MAX_MATH_IMAGE_EDGE: number = 16384;

function validMathSize(width: number, height: number): boolean {
  return Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0 &&
    width <= MAX_MATH_IMAGE_EDGE && height <= MAX_MATH_IMAGE_EDGE &&
    width * height <= MAX_MATH_IMAGE_PIXELS;
}

export async function releaseMathResource(resource: image.ImageSource | image.PixelMap | undefined): Promise<void> {
  if (resource === undefined) {
    return;
  }
  try {
    await resource.release();
  } catch (error) {
    // 清理失败不得吞掉，但不把公式文本或原生错误详情打入公共日志。
    hilog.error(0xD5A1, 'MathRender', '公式图片资源释放失败');
  }
}

interface MathCacheEntry {
  surface: MarkdownMathImage;
  bytes: number;
  borrows: number;
  // invalidate 标死：立即移出可服集（lookup 不再命中）；PixelMap 延迟到借用归零再释放
  //（在场图不被抽走）——治「损坏条目反复命中」。标死条目不进 order（不参与新淘汰位序）。
  dead: boolean;
}

class MathRenderService {
  private entries: Map<string, MathCacheEntry> = new Map<string, MathCacheEntry>();
  // LRU 位序，旧→新；lookup 读时推进（真 LRU——修正 Mermaid 只 remember 触序的 FIFO 缺陷）。
  private order: string[] = [];
  // 在途去重：同键并发共享同一 Promise（含失败结果）。
  private inFlight: Map<string, Promise<MathRenderResult>> = new Map<string, Promise<MathRenderResult>>();

  /** 同步查缓存；命中即 touch（读时推进 LRU 序）。不 acquire——借用登记是调用方的显式动作。 */
  lookup(key: string): MarkdownMathImage | null {
    const entry: MathCacheEntry | undefined = this.entries.get(key);
    if (entry === undefined || entry.dead) {
      return null;
    }
    const position: number = this.order.indexOf(key);
    if (position >= 0) {
      this.order.splice(position, 1);
    }
    this.order.push(key);
    return entry.surface;
  }

  /** 借用 +1（display 定格时）；块级 owner 与行内父侧各自独立计数（双计数有意冗余——防
   *  「父预填 → owner 未及挂载」窗口内被逐出）。 */
  acquire(key: string): void {
    const entry: MathCacheEntry | undefined = this.entries.get(key);
    if (entry !== undefined && !entry.dead) {
      entry.borrows++;
    }
  }

  /** 借用 −1；不立即逐出（下次 store 统一跑淘汰计划）。死条目借用归零即收尸释放。 */
  release(key: string): void {
    const entry: MathCacheEntry | undefined = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    if (entry.borrows > 0) {
      entry.borrows--;
    }
    if (entry.dead && entry.borrows === 0) {
      this.dropEntry(key, entry);
    }
  }

  /** 失效：立即移出可服集（不再命中），PixelMap 延迟到借用归零再释放——治「已入缓存条目
   *  损坏被反复命中」（Image 渲染失败时由消费方调用）。 */
  invalidate(key: string): void {
    const entry: MathCacheEntry | undefined = this.entries.get(key);
    if (entry === undefined || entry.dead) {
      return;
    }
    entry.dead = true;
    if (entry.borrows === 0) {
      this.dropEntry(key, entry);
      return;
    }
    const position: number = this.order.indexOf(key);
    if (position >= 0) {
      this.order.splice(position, 1);
    }
  }

  /** 渲染管线单入口：查缓存 → 在途去重 → native 排版 + ImageSource→PixelMap 解码链（自
   *  MarkdownMath.drain 方法体原样搬迁）→ store → 返回。失败结果同样去重共享。 */
  async resolve(key: string, tex: string, fontPixels: number, darkMode: boolean,
    pixelToVp: number): Promise<MathRenderResult> {
    const hit: MarkdownMathImage | null = this.lookup(key);
    if (hit !== null) {
      return { surface: hit, failText: '', cached: true };
    }
    const pending: Promise<MathRenderResult> | undefined = this.inFlight.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<MathRenderResult> = this.render(key, tex, fontPixels, darkMode, pixelToVp);
    this.inFlight.set(key, task);
    try {
      return await task;
    } finally {
      this.inFlight.delete(key);
    }
  }

  private async render(key: string, tex: string, fontPixels: number, darkMode: boolean,
    pixelToVp: number): Promise<MathRenderResult> {
    let source: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      // 颜色沿旧公式的官方灰阶双态，不在公式层创建主题或执行 HTML/Web。
      const result: TeXParseResult = await latexStringToImageWithError(tex, fontPixels,
        darkMode ? 0xE6FFFFFF : 0xE6000000, 0x00000000, LatexMathColorFormat.COLOR_FORMAT_BGRA_8888);
      if (result.resultCode !== TeXResultCode.Success || result.imageBytes.byteLength === 0) {
        return { surface: null, failText: '公式排版失败。已保留源码', cached: false };
      }
      if (result.imageBytes.byteLength > MAX_MATH_IMAGE_BYTES) {
        return { surface: null, failText: '公式图片过大。已保留源码', cached: false };
      }
      source = image.createImageSource(result.imageBytes);
      if (source === undefined) {
        throw new Error('公式图片无法解码');
      }
      const sourceInfo: image.ImageInfo = await source.getImageInfo();
      if (!validMathSize(sourceInfo.size.width, sourceInfo.size.height)) {
        return { surface: null, failText: '公式图片尺寸超出范围。已保留源码', cached: false };
      }
      // 每次任务独占一个 ImageSource；不在同一实例上并发解码，也不在解码前释放它。
      pixelMap = await source.createPixelMap();
      if (pixelMap === undefined) {
        throw new Error('公式图片无法解码');
      }
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      if (!validMathSize(info.size.width, info.size.height)) {
        return { surface: null, failText: '公式图片尺寸超出范围。已保留源码', cached: false };
      }
      const surface: MarkdownMathImage = {
        pixelMap: pixelMap, width: info.size.width * pixelToVp,
        height: info.size.height * pixelToVp
      };
      pixelMap = undefined; // 所有权交给 surface/store，finally 只清理未交付结果。
      return this.store(key, surface, info.size.width, info.size.height);
    } catch (error) {
      return { surface: null, failText: '公式排版失败。已保留源码', cached: false };
    } finally {
      await releaseMathResource(source);
      await releaseMathResource(pixelMap);
    }
  }

  private store(key: string, surface: MarkdownMathImage, pxWidth: number, pxHeight: number): MathRenderResult {
    const bytes: number = mathEntryBytes(pxWidth, pxHeight);
    if (bytes > MATH_RENDER_CACHE_ENTRY_MAX_BYTES) {
      // 单条拒收：所有权留组件（cached=false），clearImage 走私有面自释放路径。
      return { surface: surface, failText: '', cached: false };
    }
    const existing: MathCacheEntry | undefined = this.entries.get(key);
    if (existing !== undefined) {
      if (existing.dead) {
        // 死条目借用未清（在场图等收尸）：新面不能覆盖（旧 PixelMap 将失去引用永不释放）——
        // 按拒收私有面退回，死条目经 release 归零收尸后下次 store 正常入库。
        return { surface: surface, failText: '', cached: false };
      }
      // 同键竞态：收养已有 surface、释放自产 PixelMap（防孤儿；无条件覆盖会释放正被
      // 借用显示的 PixelMap）。位序随收养推进到最新。
      const position: number = this.order.indexOf(key);
      if (position >= 0) {
        this.order.splice(position, 1);
      }
      this.order.push(key);
      releaseMathResource(surface.pixelMap);
      return { surface: existing.surface, failText: '', cached: true };
    }
    this.entries.set(key, { surface: surface, bytes: bytes, borrows: 0, dead: false });
    this.order.push(key);
    this.evict(key);
    return { surface: surface, failText: '', cached: true };
  }

  /** 双闸淘汰：条数或字节任一越线即自最旧起逐出，借用中条目与刚入库未交付的自键跳过
   *  （在场不逐——宁可短暂超容也不伤在场图；上界 = 预算 + 在场显示面 + 一条未交付单条
   *  〔≤ 单条拒收上限〕，均有界约束）。 */
  private evict(protectKey: string): void {
    if (this.order.length === 0) {
      return;
    }
    const entryBytes: Record<string, number> = {};
    const borrowed: Set<string> = new Set<string>();
    this.entries.forEach((entry: MathCacheEntry, key: string): void => {
      entryBytes[key] = entry.bytes;
      if (entry.borrows > 0) {
        borrowed.add(key);
      }
    });
    // 自键自逐防护：store 刚入库的本键 borrows=0 未经 acquire——若闸越线
    // 且更旧条目全在借用中，淘汰会逐出自键并当场释放 PixelMap，而 store 仍返回 cached=true
    // 的已释放面（消费方定格死图）。故自键与借用键同格跳过，超容顺延到下次 store 淘汰。
    borrowed.add(protectKey);
    const plan: string[] = mathLruEvictPlan(this.order, entryBytes, borrowed,
      MATH_RENDER_CACHE_CAPACITY, MATH_RENDER_CACHE_BYTE_BUDGET);
    for (const key of plan) {
      const entry: MathCacheEntry | undefined = this.entries.get(key);
      if (entry !== undefined) {
        this.dropEntry(key, entry);
      }
    }
  }

  private dropEntry(key: string, entry: MathCacheEntry): void {
    this.entries.delete(key);
    const position: number = this.order.indexOf(key);
    if (position >= 0) {
      this.order.splice(position, 1);
    }
    releaseMathResource(entry.surface.pixelMap);
  }
}

export const mathRenderService: MathRenderService = new MathRenderService();
