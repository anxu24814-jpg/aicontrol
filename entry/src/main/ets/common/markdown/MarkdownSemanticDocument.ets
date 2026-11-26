/**
 * 按需解释当前源文。临时打断可撤销，容器可跨空行，恢复仅信有已封闭前驱的完整LF空行。
 * 全局定义/标题索引每次语义消费重建，引用失效不借结构稳定之名冻结旧语义。
 * 这是同步语义缓存，不负责输入节奏，也不持有旧修订或UI状态。
 */
import { MarkdownDocumentToken, MarkdownEndReason } from './MarkdownDocumentModel';
import {
  MarkdownNode, MarkdownReference, MarkdownInlineContext, MarkdownSemanticSnapshot,
  MarkdownSemanticWork, MarkdownHeadingEntry, MarkdownCopyMemo, normalizeMarkdownLabel, copyMarkdownNode
} from './MarkdownSemanticModel';
import { parseMarkdownBlocks } from './MarkdownBlockParser';
import { parseMarkdownInline } from './MarkdownInlineParser';

interface MarkdownRetainedIdentity {
  key: string;
  id: number;
  start: number;
}

export class MarkdownSemanticDocument {
  private nodes: MarkdownNode[] = [];
  private outline: MarkdownHeadingEntry[] = [];
  private identities: MarkdownRetainedIdentity[] = [];
  private parsedRevision: number = -1;
  private dirtyFrom: number = 0;
  private parsedLength: number = 0;
  private nextId: number = 1;
  private dependencySignature: string = '';
  private work: MarkdownSemanticWork = new MarkdownSemanticWork();
  // 快照前缀结构共享：refresh 只重解析 restart 之后的 suffix，[0, restart) 的顶层块对象引用
  // 与值跨帧不变（定义失效帧除外——全树重装饰时共享归零）。复用上次快照对应引用后，块级
  // 浅比较不再触发未变块重渲染，快照复制从全树收缩到长尾链；outline 数量级小维持全量复制。
  private snapshotTopShared: MarkdownNode[] = [];
  private sharedTopCount: number = 0;
  // 表格降窗登记面（U6）：上一拍已装饰的表格节点，键 = 种类 + 源起点（「同 generation」由
  // clear() 清空保证——换代/尾修订/重建都不跨拍复用）。只登记在场表格，随文档有界；单元格
  // 行内解析结果经登记面跨拍搬运，免重跑 parseMarkdownInline。
  private stableTables: Map<string, MarkdownNode> = new Map<string, MarkdownNode>();
  // 快照拷贝 memo（表格键 B2）：上一拍「源节点 → 快照拷贝」表。snapshot 复制尾块子树时命中
  //（源对象与上拍同对象 ⇒ 同值 ⇒ 拷贝仍有效）即推入上拍拷贝对象，不深拷贝不递归；每拍以新建
  // nextCopyOf 整表替换（未命中条目随表脱落，持有量有界 = 本代存活节点数）。清表两处（漏清
  // 任一 = 命中陈值 = 静默错渲染）：定义失效帧（与 sharedTopCount = 0 同分支）与 clear()。
  private prevCopyOf: Map<MarkdownNode, MarkdownNode> = new Map<MarkdownNode, MarkdownNode>();

  changed(from: number): void {
    this.dirtyFrom = Math.min(this.dirtyFrom, from);
  }

  revise(from: number): void {
    const kept: MarkdownRetainedIdentity[] = [];
    for (let index: number = 0; index < this.identities.length; index++) {
      this.work.nodeVisits++;
      if (this.identities[index].start < from) kept.push(this.identities[index]);
    }
    this.rememberIds(this.nodes, from, kept);
    const previousLength: number = Math.min(this.parsedLength, from);
    if (this.work.retainedDefinitions > 0) this.work.dependencyInvalidations++;
    this.clear();
    this.parsedLength = previousLength;
    this.identities = kept;
    this.work.retainedIdentities = kept.length;
  }

  clear(): void {
    this.work.nodeVisits += this.work.retainedNodes + this.identities.length + this.outline.length;
    this.nodes = [];
    this.outline = [];
    this.identities = [];
    this.parsedRevision = -1;
    this.parsedLength = 0;
    this.dirtyFrom = 0;
    this.dependencySignature = '';
    this.snapshotTopShared = [];
    this.sharedTopCount = 0;
    this.stableTables.clear();
    this.prevCopyOf.clear();
    this.work.retainedNodes = 0;
    this.work.retainedDefinitions = 0;
    this.work.retainedOutlineEntries = 0;
    this.work.retainedIdentities = 0;
  }

  snapshot(token: MarkdownDocumentToken, sourceLength: number, endReason: MarkdownEndReason | undefined,
    readSource: (start: number, end: number) => string): MarkdownSemanticSnapshot {
    const refreshRan: boolean = this.parsedRevision !== token.revision;
    if (refreshRan) {
      this.refresh(sourceLength, readSource);
      this.parsedRevision = token.revision;
      this.parsedLength = sourceLength;
      this.dirtyFrom = sourceLength;
    }
    const shared: number = Math.min(this.sharedTopCount, this.snapshotTopShared.length);
    const copied: MarkdownNode[] = [];
    // B2 memo 载体：prev = 上拍拷贝表（定义失效帧已在 refresh 内清空），next = 本拍新建表，
    // 结束时整表替换 prevCopyOf。命中前提 = 源对象跨拍同对象（重解析出的行对象每拍全新，天然
    // 不命中，安全走深拷贝）。memo 只在发生过 refresh 的拍生效：同一修订的重复快照走逐字深
    // 拷贝——「每次返回新对象」是既有终态隔离契约（assert 337：调用方原地写旧快照不得污染
    // 后续快照），memo 命中会把同一对象再次交出即破坏该契约。
    const nextCopyOf: Map<MarkdownNode, MarkdownNode> = new Map<MarkdownNode, MarkdownNode>();
    const memo: MarkdownCopyMemo | undefined = refreshRan ?
      { prev: this.prevCopyOf, next: nextCopyOf } : undefined;
    for (let index: number = 0; index < this.nodes.length; index++) {
      if (index < shared) {
        // 前缀块自上次快照后值与引用都未变（refresh 只动 restart 之后；定义失效帧
        // sharedTopCount 已归零不进来），复用上次快照引用即当前语义的等价快照。
        copied.push(this.snapshotTopShared[index]);
      } else {
        copied.push(copyMarkdownNode(this.nodes[index], this.work, memo));
      }
    }
    if (memo !== undefined) this.prevCopyOf = nextCopyOf;
    this.snapshotTopShared = copied;
    const outline: MarkdownHeadingEntry[] = [];
    for (let index: number = 0; index < this.outline.length; index++) {
      const entry: MarkdownHeadingEntry = this.outline[index];
      this.work.nodeVisits++;
      this.work.nodeCopies++;
      outline.push({ nodeId: entry.nodeId, headingId: entry.headingId, level: entry.level, text: entry.text });
    }
    return { token: token, nodes: copied, outline: outline, sourceLength: sourceLength, endReason: endReason };
  }

  metrics(): MarkdownSemanticWork {
    const value: MarkdownSemanticWork = new MarkdownSemanticWork();
    value.parsedUnits = this.work.parsedUnits;
    value.inlineUnits = this.work.inlineUnits;
    value.reparsedUnits = this.work.reparsedUnits;
    value.materializedUnits = this.work.materializedUnits;
    value.nodeVisits = this.work.nodeVisits;
    value.nodeCopies = this.work.nodeCopies;
    value.fullParses = this.work.fullParses;
    value.suffixParses = this.work.suffixParses;
    value.dependencyInvalidations = this.work.dependencyInvalidations;
    value.retainedNodes = this.work.retainedNodes;
    value.retainedDefinitions = this.work.retainedDefinitions;
    value.retainedOutlineEntries = this.work.retainedOutlineEntries;
    value.retainedIdentities = this.work.retainedIdentities;
    return value;
  }

  private restartIndex(readSource: (start: number, end: number) => string): number {
    if (this.nodes.length === 0 || this.dirtyFrom === 0) return 0;
    // 临时标题/围栏可能被尾字符否定，连带撤销前段的打断事实；不能仅退最后一块。
    // 只信完整LF空行，且其前驱不能是会跨空行延续的容器/缩进代码/HTML。
    for (let index: number = this.nodes.length - 1; index > 0; index--) {
      const node: MarkdownNode = this.nodes[index];
      this.work.nodeVisits++;
      if (node.kind !== 'blank' || node.range.end > this.dirtyFrom) continue;
      this.work.materializedUnits++;
      if (readSource(node.range.end - 1, node.range.end) !== '\n') continue;
      let previous: number = index - 1;
      while (previous > 0 && this.nodes[previous].kind === 'blank') {
        previous--;
        this.work.nodeVisits++;
      }
      const kind: string = this.nodes[previous].kind;
      if (kind === 'paragraph' || kind === 'heading' || kind === 'thematicBreak' ||
        kind === 'referenceDefinition' || kind === 'toc' || kind === 'blank') return previous + 1;
    }
    return 0;
  }

  private refresh(sourceLength: number, readSource: (start: number, end: number) => string): void {
    const restart: number = this.restartIndex(readSource);
    const offset: number = restart < this.nodes.length ? this.nodes[restart].range.start : 0;
    const previousIds: Map<string, number[]> = new Map<string, number[]>();
    for (let index: number = 0; index < this.identities.length; index++) {
      const entry: MarkdownRetainedIdentity = this.identities[index];
      let values: number[] | undefined = previousIds.get(entry.key);
      if (values === undefined) { values = []; previousIds.set(entry.key, values); }
      values.push(entry.id);
      this.work.nodeVisits++;
    }
    this.identities = [];
    this.work.retainedIdentities = 0;
    const removedNodes: number = this.indexIds(this.nodes, previousIds, restart);
    const source: string = readSource(offset, sourceLength);
    this.work.materializedUnits += source.length;
    if (offset === 0) this.work.fullParses++;
    else this.work.suffixParses++;
    this.work.reparsedUnits += Math.max(0, Math.min(this.parsedLength, sourceLength) - offset);
    const suffix: MarkdownNode[] = parseMarkdownBlocks(source, offset, this.work);
    this.ownStrings(suffix);
    this.nodes.length = restart;
    for (let index: number = 0; index < suffix.length; index++) this.nodes.push(suffix[index]);

    const references: Map<string, MarkdownReference> = new Map<string, MarkdownReference>();
    const footnotes: Map<string, number> = new Map<string, number>();
    const signature: string[] = [];
    this.collectDefinitions(this.nodes, references, footnotes, signature);
    const currentSignature: string = JSON.stringify(signature);
    this.work.materializedUnits += currentSignature.length;
    const invalidated: boolean = currentSignature !== this.dependencySignature;
    if (invalidated && this.parsedRevision >= 0) this.work.dependencyInvalidations++;
    this.dependencySignature = currentSignature;
    this.work.retainedDefinitions = references.size + footnotes.size;
    const context: MarkdownInlineContext = { references: references, footnotes: footnotes, work: this.work };
    // 前缀未失效时ID已在节点上；只有定义变化重装饰前缀时才为它们补身份索引。
    if (invalidated) { this.indexIds(this.nodes, previousIds, 0, restart); }
    // 表格登记面（U6）：前缀表本拍不重装饰，节点对象原位继承故登记随搬；重装饰的树在本拍
    // 覆盖登记。定义失效帧禁复用（null）——契约「签名变更使全部行内宿主重解」不破。
    const stableTables: Map<string, MarkdownNode> = new Map<string, MarkdownNode>();
    this.stableTables.forEach((value: MarkdownNode, key: string): void => { stableTables.set(key, value); });
    const tableReuse: Map<string, MarkdownNode> | null = invalidated ? null : this.stableTables;
    // 标题自动ID与目录全局相关；普通行内只有定义变更时才重解稳定前缀。
    for (let index: number = 0; index < this.nodes.length; index++) {
      if (invalidated || index >= restart) this.decorate(this.nodes[index], context, readSource, tableReuse, stableTables);
    }
    this.stableTables = stableTables;
    const headings: MarkdownNode[] = [];
    const ids: Map<string, number> = new Map<string, number>();
    this.collectHeadings(this.nodes, headings, ids, new Set<string>());
    this.work.retainedNodes = invalidated ? 0 : this.work.retainedNodes - removedNodes;
    this.assignIds(this.nodes, previousIds, invalidated ? 0 : restart);
    this.outline = [];
    for (let index: number = 0; index < headings.length; index++) {
      const heading: MarkdownNode = headings[index];
      this.outline.push({ nodeId: heading.id, headingId: heading.headingId,
        level: heading.level, text: this.textOf(heading) });
    }
    this.work.retainedOutlineEntries = this.outline.length;
    // 定义失效帧全树重装饰（前缀块 inline children 被替换），结构共享归零；正常帧共享
    // 到 restart——[0, restart) 的块ID原位保留，headingId只被幂等写同值，引用未变。
    this.sharedTopCount = invalidated ? 0 : restart;
    // 定义失效帧：前缀节点已被原地重装饰（inline children 换新对象），上拍快照拷贝过期——
    // memo 不清即命中陈值（B2 唯一陈值风险位，与 sharedTopCount = 0 同分支清）。
    if (invalidated) this.prevCopyOf.clear();
  }

  private collectDefinitions(nodes: MarkdownNode[], references: Map<string, MarkdownReference>,
    footnotes: Map<string, number>, signature: string[]): void {
    for (let index: number = 0; index < nodes.length; index++) {
      const node: MarkdownNode = nodes[index];
      this.work.nodeVisits++;
      const label: string = normalizeMarkdownLabel(node.label);
      if (node.kind === 'referenceDefinition' && !references.has(label)) {
        references.set(label, { label: label, destination: node.destination, title: node.title });
        signature.push('r', label, node.destination, node.title);
      } else if (node.kind === 'footnoteDefinition' && !footnotes.has(label)) {
        const number: number = footnotes.size + 1;
        footnotes.set(label, number);
        signature.push('f', label, number.toString());
      }
      // 行内旧children不含块定义，不必重复遍历。
      if (!this.isInlineHost(node) && node.kind !== 'toc') {
        this.collectDefinitions(node.children, references, footnotes, signature);
      }
    }
  }

  private isInlineHost(node: MarkdownNode): boolean {
    return node.kind === 'paragraph' || node.kind === 'heading' || node.kind === 'tableCell';
  }

  private decorate(node: MarkdownNode, context: MarkdownInlineContext,
    readSource: (start: number, end: number) => string, reuse: Map<string, MarkdownNode> | null,
    registry: Map<string, MarkdownNode>): void {
    this.work.nodeVisits++;
    if (this.isInlineHost(node)) {
      node.children = parseMarkdownInline(node.parts, context);
      this.ownStrings(node.children);
      return;
    }
    if (node.kind === 'toc') return;
    if (node.kind === 'table') {
      this.decorateTable(node, context, readSource, reuse, registry);
      return;
    }
    for (let index: number = 0; index < node.children.length; index++) {
      this.decorate(node.children[index], context, readSource, reuse, registry);
    }
  }

  /** 表格容器重装饰（U6 表格降窗 + B1 整行搬用）：稳定行复用——上一拍同「种类 + 源起点」表格
   *  节点逐行对齐，行须两拍同起点同终点（同源文本）、行列数同构、且本拍 range 末字符为 LF
   *  （行已封存，不再受尾字符追加影响）才复用。B1：判据不变的前提下把整行对象换回上一拍的
   * （node.children[index] = before）——同代内同起终点源区间字节不变（只有尾部追加），上拍行
   *  对象逐字段等价于本拍重解析结果；整行同对象后快照层 memo（prevCopyOf，对象身份键）得以
   *  命中整行子树免深拷贝。首行不齐即止（其后照常重装饰，含增长中的末行）；表结构非追加变化
   *  在逐行对齐处自然失配而整表退回全量。reuse 为 null（定义失效帧）时不复用。 */
  private decorateTable(node: MarkdownNode, context: MarkdownInlineContext,
    readSource: (start: number, end: number) => string, reuse: Map<string, MarkdownNode> | null,
    registry: Map<string, MarkdownNode>): void {
    const key: string = node.kind + ':' + node.range.start.toString();
    const previous: MarkdownNode | undefined = reuse === null ? undefined : reuse.get(key);
    let stable: number = 0;
    if (previous !== undefined && previous.children.length <= node.children.length) {
      stable = previous.children.length;
      for (let index: number = 0; index < stable; index++) {
        const row: MarkdownNode = node.children[index];
        const before: MarkdownNode = previous.children[index];
        const sealed: boolean = row.range.end > row.range.start &&
          readSource(row.range.end - 1, row.range.end) === '\n';
        if (before.kind !== 'tableRow' || row.kind !== 'tableRow' ||
          before.range.start !== row.range.start || before.range.end !== row.range.end ||
          before.children.length !== row.children.length || !sealed) {
          stable = index;
          break;
        }
        node.children[index] = before;
      }
    }
    for (let index: number = stable; index < node.children.length; index++) {
      this.decorate(node.children[index], context, readSource, reuse, registry);
    }
    registry.set(key, node);
  }

  private textOf(node: MarkdownNode): string {
    this.work.nodeVisits++;
    if (node.kind === 'softBreak' || node.kind === 'hardBreak') return ' ';
    if (node.children.length === 0) return node.text;
    const pieces: string[] = [];
    for (let index: number = 0; index < node.children.length; index++) pieces.push(this.textOf(node.children[index]));
    const text: string = pieces.join('');
    this.work.materializedUnits += text.length;
    return text;
  }

  private collectHeadings(nodes: MarkdownNode[], headings: MarkdownNode[], ids: Map<string, number>,
    usedIds: Set<string>): void {
    for (let index: number = 0; index < nodes.length; index++) {
      const node: MarkdownNode = nodes[index];
      this.work.nodeVisits++;
      if (node.kind === 'heading') {
        // 显式ID由块解析器写label，以免自动ID在后续消费时误当显式ID。
        const explicit: string = node.label;
        let base: string = explicit.length > 0 ? explicit : this.textOf(node).trim().toLowerCase()
          .replace(/[!"#$%&'()*+,./:;<=>?@[\\\]^\x60{|}~，。！？；：、（）【】《》“”‘’]/g, '').replace(/\s+/g, '-');
        if (base.length === 0) base = 'section';
        const count: number = (ids.get(base) ?? 0) + 1;
        ids.set(base, count);
        let candidate: string = count === 1 ? base : base + '-' + count.toString();
        while (usedIds.has(candidate)) candidate += '-2';
        usedIds.add(candidate);
        node.headingId = candidate;
        headings.push(node);
      } else if (!this.isInlineHost(node) && node.kind !== 'toc') {
        this.collectHeadings(node.children, headings, ids, usedIds);
      }
    }
  }

  private rememberIds(nodes: MarkdownNode[], from: number, kept: MarkdownRetainedIdentity[],
    rowStart: number = -1): void {
    for (let index: number = 0; index < nodes.length; index++) {
      const node: MarkdownNode = nodes[index];
      this.work.nodeVisits++;
      if (node.range.start < from) {
        kept.push({ key: this.identityKey(node, rowStart, index), id: node.id, start: node.range.start });
        this.rememberIds(node.children, from, kept, this.cellRowStart(node));
      }
    }
  }

  private owned(text: string): string {
    if (text.length === 0) return '';
    const pages: string[] = [];
    for (let start: number = 0; start < text.length; start += 4096) {
      const characters: string[] = [];
      for (let index: number = start; index < Math.min(start + 4096, text.length); index++) {
        characters.push(text.charAt(index));
      }
      pages.push(characters.join(''));
    }
    this.work.materializedUnits += text.length * 3;
    return pages.join('');
  }

  private ownStrings(nodes: MarkdownNode[]): void {
    for (let index: number = 0; index < nodes.length; index++) {
      const node: MarkdownNode = nodes[index];
      this.work.nodeVisits++;
      node.text = this.owned(node.text);
      node.destination = this.owned(node.destination);
      node.title = this.owned(node.title);
      node.label = this.owned(node.label);
      node.language = this.owned(node.language);
      node.headingId = this.owned(node.headingId);
      for (let partIndex: number = 0; partIndex < node.parts.length; partIndex++) {
        node.parts[partIndex].text = this.owned(node.parts[partIndex].text);
      }
      this.ownStrings(node.children);
    }
  }

  // 单元格身份上下文（表格键 A）：本节点是 tableRow 时给下一层（单元格）传行源起点，其余一律
  // -1。三处递归（rememberIds/indexIds/assignIds）共用本推导，与 identityKey 保持同源——键
  // 三处不同源 = id 错配（唯一高危面）。
  private cellRowStart(node: MarkdownNode): number {
    return node.kind === 'tableRow' ? node.range.start : -1;
  }

  // 表格键 A：缺格单元格的 range.start 钉在「行体末尾」（MarkdownBlockParser 缺格规则），流式
  // 追加时逐拍右移且同行多个缺格同键——身份键每拍变、单元格每拍换 id。单元格键改用「父行
  // 起点 + 列序」：行起点不随行内追加移动，同一逻辑单元格跨拍同键同 id。行键、表级登记键
  //（decorateTable）与其余种类维持原式（link 仍附 label）。
  private identityKey(node: MarkdownNode, rowStart: number = -1, cellIndex: number = 0): string {
    if (node.kind === 'tableCell') {
      return node.kind + ':' + rowStart.toString() + ':' + cellIndex.toString();
    }
    return node.kind + ':' + node.range.start.toString() + (node.kind === 'link' && node.label.length > 0 ?
      ':' + node.label : '');
  }

  private indexIds(nodes: MarkdownNode[], ids: Map<string, number[]>, start: number = 0,
    end: number = nodes.length, rowStart: number = -1): number {
    let count: number = 0;
    for (let index: number = start; index < end; index++) {
      const node: MarkdownNode = nodes[index];
      this.work.nodeVisits++;
      const key: string = this.identityKey(node, rowStart, index);
      let entries: number[] | undefined = ids.get(key);
      if (entries === undefined) { entries = []; ids.set(key, entries); }
      entries.push(node.id);
      count += 1 + this.indexIds(node.children, ids, 0, node.children.length, this.cellRowStart(node));
    }
    return count;
  }

  private assignIds(nodes: MarkdownNode[], previous: Map<string, number[]>, start: number = 0,
    rowStart: number = -1): void {
    for (let index: number = start; index < nodes.length; index++) {
      const node: MarkdownNode = nodes[index];
      this.work.nodeVisits++;
      this.work.retainedNodes++;
      const candidates: number[] | undefined = previous.get(this.identityKey(node, rowStart, index));
      if (candidates !== undefined && candidates.length > 0) {
        node.id = candidates.shift()!;
      } else {
        if (this.nextId >= Number.MAX_SAFE_INTEGER) throw new Error('Markdown 语义节点序号已达安全整数上限');
        node.id = this.nextId++;
      }
      this.assignIds(node.children, previous, 0, this.cellRowStart(node));
    }
  }
}
