/**
 * 语义快照的纯展示元数据，不驱动揭示、不持有快照/节点/正文，也不调度动画。
 * 只比较当前命名空间的顶层可见 ID 与上帧标量；原生 transition 仅消费当帧进入 ID。
 * 计数是逻辑观察量，retainedIds 是当前持有量，不代表 CPU、设备内存或动画验收结论。
 */
import { MarkdownDocumentToken, MarkdownEndReason } from './MarkdownDocumentModel';
import { MarkdownNode, MarkdownSemanticSnapshot } from './MarkdownSemanticModel';

export type MarkdownPresentationKind = 'initial' | 'replace' | 'growth' | 'unchanged' | 'done' | 'interrupted';

export interface MarkdownPresentationFrame {
  kind: MarkdownPresentationKind;
  enteringIds: number[];
}

export interface MarkdownPresentationMetrics {
  frames: number;
  nodeVisits: number;
  enteredBlocks: number;
  retainedIds: number;
}

export class MarkdownPresentationTracker {
  private previousToken: MarkdownDocumentToken | null = null;
  private previousLength: number = 0;
  private previousLive: boolean = false;
  private previousEndReason: MarkdownEndReason | undefined = undefined;
  private visibleIds: Set<number> = new Set<number>();
  private disposed: boolean = false;
  private frames: number = 0;
  private nodeVisits: number = 0;
  private enteredBlocks: number = 0;

  consume(snapshot: MarkdownSemanticSnapshot, live: boolean): MarkdownPresentationFrame {
    if (this.disposed) {
      throw new Error('Markdown 展示跟踪已释放');
    }
    this.frames++;
    const previous: MarkdownDocumentToken | null = this.previousToken;
    const sameNamespace: boolean = previous !== null &&
      previous.documentId === snapshot.token.documentId && previous.generation === snapshot.token.generation;
    const sameRevision: boolean = sameNamespace && previous !== null &&
      previous.revision === snapshot.token.revision;
    const sameSnapshot: boolean = sameRevision && this.previousLength === snapshot.sourceLength &&
      this.previousEndReason === snapshot.endReason;
    // live 来自消息的 live && streaming，不能从 endReason 未定推断历史内容还在生成。
    const growth: boolean = sameNamespace && this.previousLive && live &&
      this.previousEndReason === undefined && snapshot.endReason === undefined &&
      snapshot.sourceLength > this.previousLength;
    let kind: MarkdownPresentationKind = 'unchanged';
    if (previous === null) {
      kind = 'initial';
    } else if (!sameNamespace) {
      kind = 'replace';
    } else if (snapshot.endReason !== undefined && !sameSnapshot) {
      kind = snapshot.endReason === 'done' ? 'done' : 'interrupted';
    } else if (growth) {
      kind = 'growth';
    }

    const enteringIds: number[] = [];
    if (!sameSnapshot) {
      const currentIds: Set<number> = new Set<number>();
      for (let index: number = 0; index < snapshot.nodes.length; index++) {
        const node: MarkdownNode = snapshot.nodes[index];
        this.nodeVisits++;
        if (node.kind === 'blank' || node.kind === 'referenceDefinition') {
          continue;
        }
        // range 起点防旧尾重分类/引用后补冒充新块：曾消失的旧块即使改 ID 回来，起点仍早于
        // 已读原文——故无需累积历帧 ID，更不保存整个语义树。
        if (growth && !this.visibleIds.has(node.id) && node.range.start >= this.previousLength) {
          enteringIds.push(node.id);
        }
        currentIds.add(node.id);
      }
      this.visibleIds = currentIds;
    }
    this.enteredBlocks += enteringIds.length;
    // 拷贝标量 token，调用方之后修改 snapshot 或 token 不会改写跟踪器记忆。
    this.previousToken = { documentId: snapshot.token.documentId,
      generation: snapshot.token.generation, revision: snapshot.token.revision };
    this.previousLength = snapshot.sourceLength;
    this.previousLive = live;
    this.previousEndReason = snapshot.endReason;
    return { kind: kind, enteringIds: enteringIds };
  }

  metrics(): MarkdownPresentationMetrics {
    return { frames: this.frames, nodeVisits: this.nodeVisits,
      enteredBlocks: this.enteredBlocks, retainedIds: this.visibleIds.size };
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.visibleIds.clear();
    this.previousToken = null;
    this.previousLength = 0;
    this.previousLive = false;
    this.previousEndReason = undefined;
  }
}

/**
 * 正文排印单源：16fp/行高 24 对齐 RIK 16sp/1.5 倍。视图层字号/行高散点一律引此常量，
 * 行内代码「正文−1」规则由消费方在常量上推导。
 */
export const MARKDOWN_BODY_FONT_SIZE: number = 16;
export const MARKDOWN_BODY_LINE_HEIGHT: number = 24;

/**
 * 引用块视觉嵌套上限：第 1~3 层照常画左条/底色/内距；第 4 层起不再新增视觉层，内容并入
 * 第 3 层框（防「越深越灰 + 每层左右吃 19vp」把正文挤没）。语义靠引用框与斜体继续承担；
 * 解析树的真实层数不变（解析器另有 64 层防爆栈阀）。
 */
export const MARKDOWN_QUOTE_MAX_VISUAL_DEPTH: number = 3;
// 第 4 层首行前置省略标记的固定列宽（vp）：只占一行内左侧一小格，不另起一行、不推动已有块。
export const MARKDOWN_QUOTE_MERGED_MARK_WIDTH: number = 14;

/**
 * 块间距梯度：标题前 20 > 容器相邻 18 > 默认段距 6 = 标题后 6 > tight 列表 4（默认段距曾
 * 放宽到 16，实测「段落散开、一文变多卡」，经 8 回落至 6）。
 * ★ 段距 6 与标题后 6 同档——「标题后紧贴」的语义由 6 = 全梯度最小非紧档承担，梯度判据
 * 相应为非严格（assert-markdown-display 3698 同笔改判）。
 * 分割线两侧让位为 0——其自带上下 margin 即总间距，防与块距叠加翻倍。视觉初值，须由
 * 最终设备验收。
 */
export function markdownBlockGap(node: MarkdownNode, previous: MarkdownNode | null,
  tight: boolean = false): number {
  if (previous === null) return 0;
  if (node.kind === 'thematicBreak' || previous.kind === 'thematicBreak') return 0;
  if (node.kind === 'heading') return 20;
  if (previous.kind === 'heading') return 6;
  if (node.kind === 'codeBlock' || node.kind === 'table' || node.kind === 'blockquote' ||
    previous.kind === 'codeBlock' || previous.kind === 'table' || previous.kind === 'blockquote') return 18;
  if (tight && (node.kind === 'listItem' || node.kind === 'paragraph') &&
    (previous.kind === 'listItem' || previous.kind === 'paragraph')) return 4;
  return 6;
}

/** 标题梯度对齐 RIK（H1~H6 = 24/22/20/18/16/14 Bold）；本工程五级族，H5+ 与正文同号、靠加粗区分。 */
export function markdownHeadingSize(level: number): number {
  return level === 1 ? 24 : level === 2 ? 22 : level === 3 ? 20 : level === 4 ? 18 : 16;
}

/** 行高按 RIK「字号×1.25」就近取偶数：30/28/26/24/20。 */
export function markdownHeadingLineHeight(level: number): number {
  return level === 1 ? 30 : level === 2 ? 28 : level === 3 ? 26 : level === 4 ? 24 : 20;
}
