import { describe, expect, it } from '@ohos/hypium';
import { StreamingDocument } from '../main/ets/common/markdown/StreamingDocument';
import { MarkdownDocumentSnapshot, MarkdownDocumentToken,
  MarkdownEndReason } from '../main/ets/common/markdown/MarkdownDocumentModel';
import { MarkdownNode, MarkdownSemanticSnapshot, markdownNode } from '../main/ets/common/markdown/MarkdownSemanticModel';
import { MarkdownPresentationTracker, MarkdownPresentationFrame, MarkdownPresentationMetrics,
  markdownBlockGap, markdownHeadingSize,
  markdownHeadingLineHeight } from '../main/ets/common/markdown/MarkdownPresentation';
import { MarkdownDisplayBinding } from '../main/ets/common/markdown/MarkdownDisplayBinding';
import { markdownInlineRuns, markdownSafeRemoteUrl } from '../main/ets/common/markdown/MarkdownRenderProjection';
import { AI_CONTENT_LABEL } from '../main/ets/common/AiDisclosure';
import { markdownHighlight, MarkdownHighlightResult, MarkdownHighlightRun,
  MARKDOWN_HIGHLIGHT_MAX_UNITS } from '../main/ets/common/markdown/MarkdownHighlight';
import { markdownAnchorEntries, markdownAnchorTarget, markdownAnchorId, markdownFootnoteNumber,
  MarkdownAnchorEntry } from '../main/ets/common/markdown/MarkdownNavigation';
import { markdownPreviewHtml, markdownPreviewMermaidError, markdownPreviewReadTitle,
  markdownPreviewSourcePage, MARKDOWN_PREVIEW_SOURCE_PAGE,
  MarkdownPreviewDocument } from '../main/ets/common/markdown/MarkdownPreviewPolicy';
import { MarkdownReadingInput, MarkdownReadingTicket,
  MarkdownReadingState } from '../main/ets/common/markdown/MarkdownReadingState';
import { MARKDOWN_READING_ROWS, MARKDOWN_READING_COLUMNS, MARKDOWN_READING_UNITS,
  MarkdownReadingCellWindow, MarkdownReadingTablePage, markdownReadingRaw, markdownReadingSemanticText,
  markdownReadingCsv, markdownReadingTablePage,
  markdownReadingCellWindow } from '../main/ets/common/markdown/MarkdownReadingFormat';

function readingTestTable(fields: string[][]): MarkdownNode {
  const table: MarkdownNode = markdownNode('table', 0, 0);
  for (const values of fields) {
    const row: MarkdownNode = markdownNode('tableRow', 0, 0);
    for (const value of values) {
      const cell: MarkdownNode = markdownNode('tableCell', 0, 0);
      const leaf: MarkdownNode = markdownNode('text', 0, value.length);
      leaf.text = value;
      cell.children = [leaf];
      row.children.push(cell);
    }
    table.children.push(row);
  }
  return table;
}

export default function streamingDocumentTest(): void {
  describe('StreamingDocument', () => {
    it('preservesSplitInputAndUnclosedFence', 0, (): void => {
      const document: StreamingDocument = new StreamingDocument('local-stream');
      document.append('序言\r');
      document.append('\n\r\n```ts\nconst icon = "\uD83D');
      document.append('\uDE80";');
      document.finish('stopped');
      const snapshot: MarkdownDocumentSnapshot = document.snapshot();
      expect(document.sourceText()).assertEqual('序言\r\n\r\n```ts\nconst icon = "🚀";');
      expect(snapshot.blocks.length).assertEqual(3);
      expect(snapshot.blocks[2].kind).assertEqual('fence');
      expect(snapshot.blocks[2].closed).assertFalse();
      expect(snapshot.endReason).assertEqual('stopped');
      document.dispose();
    });
    it('parsesSemanticContainersAndLateReference', 0, (): void => {
      const document: StreamingDocument = new StreamingDocument('local-semantic');
      document.append('# 花\n\n- [x] **叶**\n\n[芽][s]\n\n');
      const headingId: number = document.semanticSnapshot().nodes[0].id;
      document.append('[s]: https://example.invalid/seed\n');
      const nodes: MarkdownNode[] = document.semanticSnapshot().nodes;
      expect(nodes[0].kind).assertEqual('heading');
      expect(nodes[0].id).assertEqual(headingId);
      const lists: MarkdownNode[] = nodes.filter((node: MarkdownNode): boolean => node.kind === 'list');
      expect(lists[0].children[0].checked).assertTrue();
      const paragraphs: MarkdownNode[] = nodes.filter((node: MarkdownNode): boolean => node.kind === 'paragraph');
      expect(paragraphs[0].children[0].kind).assertEqual('link');
      expect(paragraphs[0].children[0].destination).assertEqual('https://example.invalid/seed');
      document.dispose();
      expect(document.semanticMetrics().retainedNodes).assertEqual(0);
    });
    it('parsesTableMathAndEntities', 0, (): void => {
      const document: StreamingDocument = new StreamingDocument('local-extensions');
      document.append('| `a|b` | &amp; |\n| --- | ---: |\n| 1 | 2 |\n\n$$\nx');
      document.finish('stopped');
      const nodes: MarkdownNode[] = document.semanticSnapshot().nodes;
      expect(nodes[0].kind).assertEqual('table');
      expect(nodes[0].children[0].children[0].children[0].text).assertEqual('a|b');
      expect(nodes[0].children[0].children[1].children[0].text).assertEqual('&');
      expect(nodes[2].kind).assertEqual('mathBlock');
      expect(nodes[2].closed).assertFalse();
      document.dispose();
    });
    it('consumesDisplayFramesAndExplicitBindings', 0, (): void => {
      const input: MarkdownDisplayBinding = new MarkdownDisplayBinding();
      const first: MarkdownSemanticSnapshot = input.consume('body-a', '**叶', undefined);
      const growing: MarkdownSemanticSnapshot = input.consume('body-a', '**叶子**', undefined);
      expect(growing.token.generation).assertEqual(first.token.generation);
      expect(growing.nodes[0].children[0].kind).assertEqual('strong');
      expect(input.accepts(first.token)).assertFalse();
      const replacement: MarkdownSemanticSnapshot = input.consume('body-b', '**叶子**', 'stopped');
      expect(replacement.endReason).assertEqual('stopped');
      expect(input.accepts(growing.token)).assertFalse();
      expect(markdownInlineRuns(replacement.nodes[0].children)[0].bold).assertTrue();
      input.dispose();
      expect(input.accepts(replacement.token)).assertFalse();
    });
    it('tracksOnlyNewLiveTopLevelBlocks', 0, (): void => {
      const input: MarkdownDisplayBinding = new MarkdownDisplayBinding();
      const tracker: MarkdownPresentationTracker = new MarkdownPresentationTracker();
      const history: MarkdownSemanticSnapshot = input.consume('presentation', 'history\n\n', undefined);
      expect(tracker.consume(history, false).kind).assertEqual('initial');
      expect(tracker.consume(history, true).enteringIds.length).assertEqual(0);
      expect(tracker.consume(history, false).kind).assertEqual('unchanged');
      const resumed: MarkdownSemanticSnapshot = input.consume('presentation', 'history\n\nrestored\n\n', undefined);
      expect(tracker.consume(resumed, true).enteringIds.length).assertEqual(0);
      const growing: MarkdownSemanticSnapshot = input.consume('presentation',
        'history\n\nrestored\n\n### New\n\n', undefined);
      const frame: MarkdownPresentationFrame = tracker.consume(growing, true);
      const heading: MarkdownNode = growing.nodes.filter((node: MarkdownNode): boolean => node.kind === 'heading')[0];
      expect(frame.kind).assertEqual('growth');
      expect(frame.enteringIds.length).assertEqual(1);
      expect(frame.enteringIds[0]).assertEqual(heading.id);
      expect(tracker.consume(growing, true).enteringIds.length).assertEqual(0);
      const remounted: MarkdownPresentationTracker = new MarkdownPresentationTracker();
      expect(remounted.consume(growing, true).kind).assertEqual('initial');
      expect(remounted.metrics().enteredBlocks).assertEqual(0);
      remounted.dispose();
      const replaced: MarkdownSemanticSnapshot = input.consume('presentation', 'title\n', undefined);
      expect(tracker.consume(replaced, true).kind).assertEqual('replace');
      const reclassified: MarkdownSemanticSnapshot = input.consume('presentation', 'title\n---\n', undefined);
      expect(reclassified.nodes[0].kind).assertEqual('heading');
      expect(tracker.consume(reclassified, true).enteringIds.length).assertEqual(0);
      const changedBinding: MarkdownSemanticSnapshot = input.consume('other-presentation', 'title\n---\n', undefined);
      expect(tracker.consume(changedBinding, true).kind).assertEqual('replace');
      expect(tracker.metrics().retainedIds).assertEqual(1);
      tracker.dispose(); input.dispose();
    });
    it('deduplicatesPresentationEndAndReleasesIds', 0, (): void => {
      const reasons: MarkdownEndReason[] = ['done', 'stopped', 'failed', 'truncated'];
      for (let index: number = 0; index < reasons.length; index++) {
        const reason: MarkdownEndReason = reasons[index];
        const input: MarkdownDisplayBinding = new MarkdownDisplayBinding();
        const tracker: MarkdownPresentationTracker = new MarkdownPresentationTracker();
        tracker.consume(input.consume('presentation-end', 'prefix\n\n', undefined), true);
        const ended: MarkdownSemanticSnapshot = input.consume('presentation-end', 'prefix\n\ntail', reason);
        const frame: MarkdownPresentationFrame = tracker.consume(ended, true);
        expect(frame.kind).assertEqual(reason === 'done' ? 'done' : 'interrupted');
        expect(frame.enteringIds.length).assertEqual(0);
        expect(tracker.consume(ended, true).kind).assertEqual('unchanged');
        expect(tracker.consume(ended, false).kind).assertEqual('unchanged');
        const beforeDispose: MarkdownPresentationMetrics = tracker.metrics();
        tracker.dispose(); tracker.dispose();
        expect(tracker.metrics().retainedIds).assertEqual(0);
        expect(tracker.metrics().frames).assertEqual(beforeDispose.frames);
        let rejected: boolean = false;
        try {
          tracker.consume(ended, true);
        } catch (_) {
          rejected = true;
        }
        expect(rejected).assertTrue();
        input.dispose();
      }
    });
    it('replacesPresentationNamespaceWithoutHoldingHistory', 0, (): void => {
      const document: StreamingDocument = new StreamingDocument('presentation-generation');
      const tracker: MarkdownPresentationTracker = new MarkdownPresentationTracker();
      let source: string = '';
      for (let index: number = 0; index < 24; index++) {
        const delta: string = 'block ' + index.toString() + '\n\n';
        source += delta;
        document.append(delta);
        const snapshot: MarkdownSemanticSnapshot = document.semanticSnapshot();
        tracker.consume(snapshot, true);
        const visible: MarkdownNode[] = snapshot.nodes.filter((node: MarkdownNode): boolean =>
          node.kind !== 'blank' && node.kind !== 'referenceDefinition');
        expect(tracker.metrics().retainedIds).assertEqual(visible.length);
      }
      document.replace(source);
      const replaced: MarkdownPresentationFrame = tracker.consume(document.semanticSnapshot(), true);
      expect(replaced.kind).assertEqual('replace');
      expect(replaced.enteringIds.length).assertEqual(0);
      document.replace('short');
      tracker.consume(document.semanticSnapshot(), false);
      expect(tracker.metrics().retainedIds).assertEqual(1);
      const frames: number = tracker.metrics().frames;
      const copy: MarkdownPresentationMetrics = tracker.metrics();
      copy.frames = -1;
      expect(tracker.metrics().frames).assertEqual(frames);
      tracker.dispose(); document.dispose();
    });
    it('preservesPresentationSpacingAndHeadingRelations', 0, (): void => {
      const paragraph: MarkdownNode = markdownNode('paragraph', 0, 1);
      const heading: MarkdownNode = markdownNode('heading', 1, 2);
      const code: MarkdownNode = markdownNode('codeBlock', 2, 3);
      const ordinary: number = markdownBlockGap(paragraph, paragraph);
      const tight: number = markdownBlockGap(paragraph, paragraph, true);
      expect(markdownBlockGap(heading, null, true)).assertEqual(0);
      expect(ordinary > tight && tight > 0).assertTrue();
      expect(markdownBlockGap(heading, paragraph) > ordinary).assertTrue();
      expect(markdownBlockGap(paragraph, heading) < ordinary).assertTrue();
      expect(markdownBlockGap(code, paragraph) > ordinary).assertTrue();
      expect(markdownBlockGap(code, paragraph, true)).assertEqual(markdownBlockGap(code, paragraph));
      expect(markdownBlockGap(heading, code, true)).assertEqual(markdownBlockGap(heading, paragraph));
      for (let level: number = 1; level <= 6; level++) {
        expect(markdownHeadingLineHeight(level) > markdownHeadingSize(level)).assertTrue();
        if (level < 6) {
          expect(markdownHeadingSize(level) >= markdownHeadingSize(level + 1)).assertTrue();
          expect(markdownHeadingLineHeight(level) >= markdownHeadingLineHeight(level + 1)).assertTrue();
        }
      }
      expect(markdownHeadingSize(1) > markdownHeadingSize(6)).assertTrue();
      expect(markdownHeadingLineHeight(1) > markdownHeadingLineHeight(6)).assertTrue();
    });
    it('preservesReadingRawAndCsvSemantics', 0, (): void => {
      const source: string = 'prefix\r\n| a | b |\r\n| --- | --- |\r\n| x | y | extra |\r\n';
      const raw: MarkdownNode = markdownNode('table', 8, source.length);
      expect(markdownReadingRaw(source, raw)).assertEqual(source.slice(8));
      const table: MarkdownNode = readingTestTable([[' a ', 'quote"'], ['line\r\nnext', '']]);
      expect(markdownReadingCsv(table)).assertEqual('" a ","quote"""\r\n"line\r\nnext",""\r\n"' +
        AI_CONTENT_LABEL + '",""');
      const math: MarkdownNode = markdownNode('math', 0, 3);
      math.text = 'x+1'; math.closed = false;
      expect(markdownReadingSemanticText(math)).assertEqual('x+1');
      let rejected: boolean = false;
      try { markdownReadingCsv(readingTestTable([[]])); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('isolatesReadingTicketsAndKeepsSingleFlight', 0, (): void => {
      const state: MarkdownReadingState = new MarkdownReadingState();
      const input: MarkdownReadingInput = { token: { documentId: 'reading-local', generation: 1, revision: 2 },
        nodeId: 7, kind: 'codeBlock', source: 'old' };
      expect(state.bind(input)).assertTrue();
      const ticket: MarkdownReadingTicket | null = state.begin(input);
      expect(ticket !== null).assertTrue();
      if (ticket === null) { return; }
      expect(state.accepts(ticket, input)).assertTrue();
      const growing: MarkdownReadingInput = { token: { documentId: 'reading-local', generation: 1, revision: 3 },
        nodeId: 7, kind: 'codeBlock', source: 'old grows' };
      expect(state.accepts(ticket, growing)).assertFalse();
      expect(state.bind(growing)).assertFalse();
      expect(state.sameBinding(ticket, growing)).assertTrue();
      expect(state.begin(growing) === null).assertTrue();
      const replaced: MarkdownReadingInput = { token: { documentId: 'reading-local', generation: 2, revision: 3 },
        nodeId: 7, kind: 'codeBlock', source: 'other' };
      expect(state.bind(replaced)).assertTrue();
      expect(state.begin(replaced) === null).assertTrue();
      state.finish(ticket);
      const next: MarkdownReadingTicket | null = state.begin(replaced);
      expect(next !== null).assertTrue();
      state.finish(ticket);
      expect(state.isBusy()).assertTrue();
      state.dispose();
      expect(state.accepts(ticket, input)).assertFalse();
      expect(state.begin(input) === null).assertTrue();
    });
    it('boundsReadingTableAndCellWindows', 0, (): void => {
      const rows: string[][] = [];
      for (let row: number = 0; row < MARKDOWN_READING_ROWS + 3; row++) {
        const fields: string[] = [];
        for (let column: number = 0; column < MARKDOWN_READING_COLUMNS + 2; column++) {
          fields.push(row.toString() + ',' + column.toString());
        }
        rows.push(fields);
      }
      const table: MarkdownNode = readingTestTable(rows);
      const first: MarkdownReadingTablePage = markdownReadingTablePage(table, 0, 0);
      const next: MarkdownReadingTablePage = markdownReadingTablePage(table, 1, 1);
      expect(first.rowIndices.length <= MARKDOWN_READING_ROWS + 1).assertTrue();
      expect(first.columnIndices.length <= MARKDOWN_READING_COLUMNS).assertTrue();
      expect(next.rowIndices[0]).assertEqual(0);
      expect(next.rowIndices[1]).assertEqual(MARKDOWN_READING_ROWS + 1);
      expect(next.columnIndices[0]).assertEqual(MARKDOWN_READING_COLUMNS);
      const cell: MarkdownNode = markdownNode('tableCell', 0, 0);
      const strong: MarkdownNode = markdownNode('strong', 0, 0);
      const leaf: MarkdownNode = markdownNode('text', 0, 0);
      leaf.text = 'a'.repeat(MARKDOWN_READING_UNITS - 1) + '🚀tail';
      strong.children = [leaf]; cell.children = [strong];
      const window: MarkdownReadingCellWindow = markdownReadingCellWindow(cell, 0);
      const last: MarkdownReadingCellWindow = markdownReadingCellWindow(cell, 1);
      expect(window.hasNext).assertTrue(); expect(last.hasNext).assertFalse();
      expect(window.utf16Units <= MARKDOWN_READING_UNITS).assertTrue();
      expect(window.nodes.map((part: MarkdownNode): string => markdownReadingSemanticText(part)).join('') +
        last.nodes.map((part: MarkdownNode): string => markdownReadingSemanticText(part)).join('')).assertEqual(leaf.text);
      expect(markdownInlineRuns(last.nodes)[0].bold).assertTrue();
      expect(markdownInlineRuns(last.nodes)[0].text).assertEqual('🚀tail');
    });
    it('blocksUnsafeMarkdownDestinations', 0, (): void => {
      expect(markdownSafeRemoteUrl('https://example.invalid/a?q=1')).assertEqual('https://example.invalid/a?q=1');
      expect(markdownSafeRemoteUrl('javascript:alert(1)')).assertEqual('');
      expect(markdownSafeRemoteUrl('file:///data/private')).assertEqual('');
      expect(markdownSafeRemoteUrl('https://user:secret@example.invalid')).assertEqual('');
      expect(markdownSafeRemoteUrl('https://example.invalid/\u000Aevil')).assertEqual('');
    });
    it('highlightsNativeRunsWithoutChangingSource', 0, (): void => {
      const source: string = '@ComponentV2\r\nstruct Demo { @Param n: number = 42; } // 中文🚀';
      const result: MarkdownHighlightResult = markdownHighlight(source, 'arkts');
      expect(result.status).assertEqual('highlighted');
      expect(result.runs.map((run: MarkdownHighlightRun): string => run.text).join('')).assertEqual(source);
      expect(result.runs.some((run: MarkdownHighlightRun): boolean =>
        run.kind === 'keyword' && run.text === '@ComponentV2')).assertTrue();
      const unknown: MarkdownHighlightResult = markdownHighlight(source, 'unknown-language');
      expect(unknown.status).assertEqual('plain'); expect(unknown.message.length > 0).assertTrue();
      const longSource: string = '/*' + 'x'.repeat(MARKDOWN_HIGHLIGHT_MAX_UNITS);
      const limited: MarkdownHighlightResult = markdownHighlight(longSource, 'js');
      expect(limited.status).assertEqual('limited'); expect(limited.readUnits).assertEqual(0);
      expect(limited.runs.map((run: MarkdownHighlightRun): string => run.text).join('')).assertEqual(longSource);
    });
    it('resolvesDocumentAnchorsWithoutCrossingGeneration', 0, (): void => {
      const heading: MarkdownNode = markdownNode('heading', 0, 3);
      heading.id = 101; heading.headingId = '中文';
      const definition: MarkdownNode = markdownNode('footnoteDefinition', 3, 8);
      definition.id = 102; definition.label = ' Note ';
      const entries: MarkdownAnchorEntry[] = markdownAnchorEntries([heading, definition]);
      expect(markdownAnchorTarget(entries, '#' + encodeURIComponent('中文'))).assertEqual(101);
      expect(markdownAnchorTarget(entries, 'footnote:note')).assertEqual(102);
      expect(markdownAnchorTarget(entries, '#%ZZ')).assertEqual(0);
      expect(markdownFootnoteNumber(entries, 'NOTE')).assertEqual(1);
      const token: MarkdownDocumentToken = { documentId: 'local-anchors', generation: 1, revision: 1 };
      const id: string = markdownAnchorId(token, 101);
      token.revision++;
      expect(markdownAnchorId(token, 101)).assertEqual(id);
      token.generation++;
      expect(markdownAnchorId(token, 101) !== id).assertTrue();
    });
    it('sanitizesPreviewAndRetainsCompleteSourcePages', 0, (): void => {
      const document: MarkdownPreviewDocument = markdownPreviewHtml(
        '<script>attack()</script><p onclick="attack()">safe</p><img src="https://evil.invalid">', false, 'local');
      expect(document.error).assertEqual('');
      expect(document.html.includes('<p>safe</p>')).assertTrue();
      expect(document.html.includes('attack()')).assertFalse();
      expect(document.html.includes('https://evil.invalid')).assertFalse();
      expect(markdownPreviewMermaidError('graph TD; A-->B', true)).assertEqual('');
      expect(markdownPreviewMermaidError('graph TD; A-->B\nclick A "https://evil.invalid"', true) !== '').assertTrue();
      expect(markdownPreviewMermaidError('graph TD; A-->B', false) !== '').assertTrue();
      expect(markdownPreviewReadTitle('md-preview:other:ok', 'local').status).assertEqual('');
      const source: string = 'x'.repeat(MARKDOWN_PREVIEW_SOURCE_PAGE - 1) + '🚀tail';
      expect(markdownPreviewSourcePage(source, 0) + markdownPreviewSourcePage(source, 1)).assertEqual(source);
    });
    it('isolatesReplacedDocument', 0, (): void => {
      const document: StreamingDocument = new StreamingDocument('local-replace');
      document.append('旧答案');
      const previousToken: MarkdownDocumentToken = document.token();
      document.replace('新答案');
      expect(document.accepts(previousToken)).assertFalse();
      expect(document.sourceText()).assertEqual('新答案');
      document.finish('done');
      const revision: number = document.token().revision;
      document.finish('done');
      expect(document.token().revision).assertEqual(revision);
      document.dispose();
      expect(document.accepts(previousToken)).assertFalse();
    });
  });
}
