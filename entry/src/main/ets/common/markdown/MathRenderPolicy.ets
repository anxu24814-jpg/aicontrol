/**
 * 公式渲染缓存的纯策略件：缓存键构造、字节计量、双闸淘汰计划与容量常量。
 *
 * 为什么单开一件：键构造必须与组件 capture 的资源四元（tex/fontPixels/darkMode/pixelToVp）
 * 同用一式、防第二份 1.2 倍补偿——纯函数单源让块级（MarkdownMath）与行内（MarkdownInlineView
 * 预填）双消费方 import 同一常量，而非互引组件件内部常量的隐藏耦合。零 Kit 依赖（只含纯
 * 语义/常量），可进断言脚本 Node 直跑面；真正持 PixelMap 的缓存在 UI 域件 MathRenderService
 * （PixelMap 类型不进 common/markdown 零 Kit 纯语义区）。
 */

// 行内公式排版字号 = 正文 1.2 倍视觉补偿（LaTeX 排版 x-height 偏小，与正文字号同值时
// 行内公式显小）；块级公式独立成行、无行内正文参照，不放大。键构造与组件 capture 同用本常量。
export const MATH_INLINE_FONT_SCALE: number = 1.2;

/** 缓存条数闸。[真机定档]：真机 Profiler + 首帧读数后可调，只动常量不动机制。 */
export const MATH_RENDER_CACHE_CAPACITY: number = 64;
/** 缓存字节闸 16MB。[真机定档]：典型行内式约 200×40px≈32KB、块级式约 800×120px≈384KB，
 *  64 条混合约 5~10MB，16MB 留余量。 */
export const MATH_RENDER_CACHE_BYTE_BUDGET: number = 16 * 1024 * 1024;
/** 单条拒收上限 4MB（约 1000×1000px，超此属异常产物——防超宽矩阵巨型位图吞噬预算）。 */
export const MATH_RENDER_CACHE_ENTRY_MAX_BYTES: number = 4 * 1024 * 1024;

/** 缓存键 = 资源四元（tex/fontPixels/darkMode/pixelToVp），跨挂载复用；不含身份成分。
 *  原文键（总指挥裁定）：tex 长度前缀 + 原文入键（Map 内存键，无碰撞、可调试），长前缀防
 *  拼接歧义；darkMode 决定 native 前景色参数故进键；fontPixels/pixelToVp 各取两位小数归一
 *  （Math.round(x*100)）——防密度换档边界 <1px 错配条目。身份成分（documentId/nodeId/mount）
 *  不进键：缓存要的正是跨挂载复用；行内 1.2 补偿已折进 fontPixels（不另设 kind 成分）。 */
export function mathResourceKey(tex: string, fontPixels: number, darkMode: boolean, pixelToVp: number): string {
  return tex.length.toString() + ':' + tex + ':' + (darkMode ? 'd' : 'l') + ':' +
    Math.round(fontPixels * 100).toString() + ':' + Math.round(pixelToVp * 100).toString();
}

/** 条目字节 = 宽 × 高 × 4（BGRA_8888，image Kit 官方口径每像素 4 字节）。 */
export function mathEntryBytes(pxWidth: number, pxHeight: number): number {
  return pxWidth * pxHeight * 4;
}

/** 纯淘汰计划（无副作用，断言直跑）：order 旧→新；条数或字节任一越线即自最旧起逐出，
 *  借用中键跳过（在场不逐——释放正被借用显示的 PixelMap 会让在场 Image 异常，宁可让缓存
 *  短暂超容也不伤在场图）。entryBytes 只须覆盖 order 中在缓存里的键（被提前移除的键缺项
 *  视为 0 字节、不参与字节闸）。 */
export function mathLruEvictPlan(order: string[], entryBytes: Record<string, number>,
  borrowed: Set<string>, capacity: number, byteBudget: number): string[] {
  // ArkTS 严格子集无 Object.prototype.hasOwnProperty.call——键在场判据走 keys+indexOf
  //（InlineView mathStates 过滤同款先例；缓存面 ≤64 条，线性查代价可忽略）。
  const knownKeys: string[] = Object.keys(entryBytes);
  const hasBytes = (key: string): boolean => knownKeys.indexOf(key) >= 0;
  const evicted: string[] = [];
  if (capacity <= 0 || byteBudget <= 0) {
    return evicted;
  }
  let count: number = 0;
  let bytes: number = 0;
  for (const key of order) {
    if (hasBytes(key)) {
      count++;
      bytes += entryBytes[key];
    }
  }
  for (const key of order) {
    if (count <= capacity && bytes <= byteBudget) {
      break;
    }
    if (borrowed.has(key) || !hasBytes(key)) {
      continue;
    }
    evicted.push(key);
    count--;
    bytes -= entryBytes[key];
  }
  return evicted;
}
