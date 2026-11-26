/**
 * 显示帧全文到文档增量的适配，不参与网络、打字机、数据库或消息控制。
 * 绑定由消息创建/换源方显式铸造；相同文本不能证明是同一回答。
 */
import { MarkdownDocumentToken, MarkdownEndReason, MarkdownWorkMetrics,
  nextMarkdownBindingId } from './MarkdownDocumentModel';
import { MarkdownSemanticSnapshot, MarkdownSemanticWork } from './MarkdownSemanticModel';
import { StreamingDocument } from './StreamingDocument';

export interface MarkdownDisplayMetrics {
  frames: number;
  unchangedFrames: number;
  prefixComparedUnits: number;
  appendedUnits: number;
  replacements: number;
  source: MarkdownWorkMetrics;
  semantic: MarkdownSemanticWork;
}

export class MarkdownDisplayBinding {
  // 每次挂载另有命名空间，旧组件的 token 不会在同一消息重新挂载后复活。
  private mountId: string = nextMarkdownBindingId();
  private bindingId: string = '';
  private previousText: string = '';
  private endReason: MarkdownEndReason | undefined = undefined;
  private document: StreamingDocument | null = null;
  private current: MarkdownSemanticSnapshot | null = null;
  private disposed: boolean = false;
  private frames: number = 0;
  private unchangedFrames: number = 0;
  private prefixComparedUnits: number = 0;
  private appendedUnits: number = 0;
  private replacements: number = 0;

  consume(bindingId: string, text: string,
    endReason: MarkdownEndReason | undefined): MarkdownSemanticSnapshot {
    if (this.disposed || bindingId === '') {
      throw new Error('Markdown 正文绑定已释放或身份缺失');
    }
    this.frames++;
    let document: StreamingDocument | null = this.document;
    if (document === null) {
      document = new StreamingDocument(this.documentId(bindingId));
      this.document = document;
      document.append(text);
      this.appendedUnits += text.length;
    } else if (bindingId !== this.bindingId) {
      document.reset(this.documentId(bindingId), text);
      this.replacements++;
    } else if (text === this.previousText && endReason === this.endReason && this.current !== null) {
      this.unchangedFrames++;
      return this.current;
    } else if (this.endReason !== undefined || !this.isPrefixGrowth(text)) {
      // 同绑定的权威修正仍须换代；不能用尾修假冒一般追加，也不能给已结束文档 append。
      document.replace(text);
      this.replacements++;
    } else {
      const delta: string = text.substring(this.previousText.length);
      document.append(delta);
      this.appendedUnits += delta.length;
    }
    this.bindingId = bindingId;
    this.previousText = text;
    this.endReason = endReason;
    if (endReason !== undefined) {
      document.finish(endReason);
    }
    this.current = document.semanticSnapshot();
    return this.current;
  }

  accepts(token: MarkdownDocumentToken): boolean {
    return !this.disposed && this.document !== null && this.document.accepts(token);
  }

  metrics(): MarkdownDisplayMetrics | null {
    if (this.document === null) {
      return null;
    }
    return {
      frames: this.frames, unchangedFrames: this.unchangedFrames,
      prefixComparedUnits: this.prefixComparedUnits, appendedUnits: this.appendedUnits,
      replacements: this.replacements, source: this.document.metrics(),
      semantic: this.document.semanticMetrics()
    };
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    if (this.document !== null) {
      this.document.dispose();
    }
    this.current = null;
    this.previousText = '';
    this.bindingId = '';
    this.endReason = undefined;
  }

  private documentId(bindingId: string): string {
    return bindingId + '/' + this.mountId;
  }

  // 采样验证：上游唯一写者是权威全文的纯追加（终态经 upsert 全量权威覆盖），逐单元全量
  // 比较每帧 O(全文) 是长文显示帧的固定成本。此处只校验头段与接缝尾段——头段防整体漂移，
  // 尾段守住 append 接缝；任一不符退全量精确验证（权威修正仍走 replace，防御不丢）。
  private static PREFIX_SAMPLE_HEAD: number = 32;
  private static PREFIX_SAMPLE_TAIL: number = 64;

  private isPrefixGrowth(text: string): boolean {
    const previous: string = this.previousText;
    if (text.length < previous.length) {
      return false;
    }
    const headLimit: number = Math.min(previous.length, MarkdownDisplayBinding.PREFIX_SAMPLE_HEAD);
    for (let index: number = 0; index < headLimit; index++) {
      this.prefixComparedUnits++;
      if (text.charCodeAt(index) !== previous.charCodeAt(index)) {
        return this.verifyFullPrefix(text);
      }
    }
    const tailStart: number = Math.max(headLimit, previous.length - MarkdownDisplayBinding.PREFIX_SAMPLE_TAIL);
    for (let index: number = tailStart; index < previous.length; index++) {
      this.prefixComparedUnits++;
      if (text.charCodeAt(index) !== previous.charCodeAt(index)) {
        return this.verifyFullPrefix(text);
      }
    }
    return true;
  }

  private verifyFullPrefix(text: string): boolean {
    const previous: string = this.previousText;
    for (let index: number = 0; index < previous.length; index++) {
      this.prefixComparedUnits++;
      if (text.charCodeAt(index) !== previous.charCodeAt(index)) {
        return false;
      }
    }
    return true;
  }
}
