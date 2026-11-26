/**
 * Mermaid 消息内联渲染的纯策略：准入、缓存键、显示尺寸与 LRU 淘汰。
 *
 * 为什么单开一件：消息内联与点开预览共用同一条安全边界（输入准入 = MarkdownPreviewPolicy
 * 的 markdownPreviewMermaidError，渲染仍走固定离线壳与输出双侧校验），本件只回答四个纯问题
 * ——该不该渲、缓存键是什么、显示多大、缓存留几张。零 Kit 依赖（只 import 纯语义/策略件），
 * 可进断言脚本（assert-markdown-display）的 Node 直跑面；真正的 Web 编排在 UI 域件
 * MermaidRenderHost。
 */
import { MarkdownNode } from './MarkdownSemanticModel';
import { markdownPreviewMermaidError } from './MarkdownPreviewPolicy';

/** 内联产物缓存条数上限（宪法数据有界：典型图每张百 KB 级，32 张 = 十 MB 级封顶）。 */
export const MERMAID_INLINE_CACHE_CAPACITY: number = 32;
/** 渲染倍率：2x 覆盖常见屏幕密度下 360vp 内容宽的清晰度；导出按同倍率独立重渲。 */
export const MERMAID_INLINE_SCALE: number = 2;
/** canvas 单边像素硬限（对齐 runner 边界与内存红线；超限拒绝内联，退码显示）。 */
export const MERMAID_INLINE_MAX_EDGE: number = 4096;
/** 内联图最大显示高度（vp）：超高图等比缩到限高，点击进全屏看完整图。 */
export const MERMAID_INLINE_MAX_HEIGHT: number = 480;

export interface MermaidInlineSize {
  width: number;
  height: number;
}

/** 准入判定：仅已闭合、非空、合法 mermaid 围栏可内联；开关与流式判据都收在这一处，
 *  与点开预览的 markdownPreviewSupported/previewEnabled 同源复用，禁第二套语言判定。 */
export function mermaidInlineEligible(node: MarkdownNode, enabled: boolean): boolean {
  if (!enabled || node.kind !== 'codeBlock' || node.closed !== true) {
    return false;
  }
  if (node.language.trim().toLowerCase() !== 'mermaid') {
    return false;
  }
  return markdownPreviewMermaidError(node.text, true) === '';
}

/** FNV-1a 32 位（长度前缀防拼接碰撞；源码 ≤16384 单元，全串扫描代价可接受）。 */
function mermaidInlineHash(source: string): number {
  let hash: number = 0x811C9DC5;
  for (let index: number = 0; index < source.length; index++) {
    hash = hash ^ source.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** 缓存键 = 源长 + 源哈希 + 主题 + 倍率：主题切换自然换键重渲，切回旧主题命中旧键不重渲。 */
export function mermaidInlineKey(source: string, darkMode: boolean, scale: number): string {
  const hex: string = ('00000000' + mermaidInlineHash(source).toString(16)).slice(-8);
  return source.length.toString() + ':' + hex + ':' + (darkMode ? 'd' : 'l') + ':' +
    Math.round(scale).toString();
}

/** 等比 contain：源像素按倍率折回 vp，宽不超容器、高不超限高。小图不放大（避免拉满变糊）。
 *  非法输入回 height 0——调用方据此退码显示，不猜尺寸。 */
export function mermaidInlineDisplaySize(sourceWidth: number, sourceHeight: number, containerWidth: number,
  scale: number): MermaidInlineSize {
  if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight) || sourceWidth <= 0 || sourceHeight <= 0 ||
    !Number.isFinite(containerWidth) || containerWidth <= 0 || !Number.isFinite(scale) || scale <= 0) {
    return { width: 0, height: 0 };
  }
  const naturalWidth: number = sourceWidth / scale;
  const naturalHeight: number = sourceHeight / scale;
  let width: number = Math.min(naturalWidth, containerWidth);
  let height: number = naturalHeight * width / naturalWidth;
  if (height > MERMAID_INLINE_MAX_HEIGHT) {
    height = MERMAID_INLINE_MAX_HEIGHT;
    width = naturalWidth * height / naturalHeight;
  }
  return { width: Math.max(1, width), height: Math.max(1, height) };
}

/** LRU 淘汰计划（无副作用，单独导出供断言直跑）：order 为旧→新，返回应删除的键。
 *  活跃订阅键（正在显示/在场）一律跳过——释放活跃资源会让在场 Image 显示异常，
 *  故宁可让缓存短暂超过容量也不伤在场图。 */
export function mermaidInlineLruEvict(order: string[], capacity: number, activeKeys: string[]): string[] {
  const evicted: string[] = [];
  if (order.length === 0 || capacity <= 0) {
    return evicted;
  }
  const active: Set<string> = new Set<string>(activeKeys);
  let remaining: number = order.length;
  for (const key of order) {
    if (remaining <= capacity) {
      break;
    }
    if (active.has(key)) {
      continue;
    }
    evicted.push(key);
    remaining--;
  }
  return evicted;
}
