/** 阅读操作的挂载/绑定/修订票据。只持当前标量与一个在途操作，不持历史 AST 或订阅。 */
import { MarkdownDocumentToken, nextMarkdownBindingId } from './MarkdownDocumentModel';
import { MarkdownNodeKind } from './MarkdownSemanticModel';

export interface MarkdownReadingInput {
  token: MarkdownDocumentToken;
  nodeId: number;
  kind: MarkdownNodeKind;
  source: string;
}

export interface MarkdownReadingTicket extends MarkdownReadingInput {
  mountId: string;
  operationId: number;
}

export function markdownReadingIdentity(input: MarkdownReadingInput): string {
  return input.token.documentId.length.toString() + ':' + input.token.documentId + ':' +
    input.token.generation.toString() + ':' + input.nodeId.toString() + ':' + input.kind;
}

export class MarkdownReadingState {
  private mountId: string = nextMarkdownBindingId();
  private identity: string = '';
  private operationId: number = 0;
  private active: MarkdownReadingTicket | null = null;
  private activeInvalidated: boolean = false;
  private disposed: boolean = false;

  /** true 表示局部页/折叠应清空。普通 revision 或 source 增长不换资源身份。 */
  bind(input: MarkdownReadingInput): boolean {
    if (this.disposed) {
      return false;
    }
    const identity: string = markdownReadingIdentity(input);
    if (this.identity === identity) {
      return false;
    }
    this.identity = identity;
    if (this.active !== null) { this.activeInvalidated = true; }
    // 换绑不放开在途锁。旧 Picker/写盘完成前不再捕获第二份长正文。
    return true;
  }

  isBusy(): boolean {
    return this.active !== null;
  }

  begin(input: MarkdownReadingInput): MarkdownReadingTicket | null {
    if (this.disposed || this.active !== null || input.token.documentId === '') {
      return null;
    }
    this.bind(input);
    const ticket: MarkdownReadingTicket = {
      token: { documentId: input.token.documentId, generation: input.token.generation,
        revision: input.token.revision },
      nodeId: input.nodeId, kind: input.kind, source: input.source,
      mountId: this.mountId, operationId: ++this.operationId
    };
    this.active = ticket;
    this.activeInvalidated = false;
    return ticket;
  }

  sameBinding(ticket: MarkdownReadingTicket, current: MarkdownReadingInput): boolean {
    return !this.disposed && !this.activeInvalidated && this.active === ticket && ticket.mountId === this.mountId &&
      ticket.operationId === this.operationId &&
      markdownReadingIdentity(ticket) === markdownReadingIdentity(current) &&
      this.identity === markdownReadingIdentity(current);
  }

  accepts(ticket: MarkdownReadingTicket, current: MarkdownReadingInput): boolean {
    // 当前 Param 必须由调用方现读。Monitor 尚未运行时，不能只相信 bind 缓存。
    return this.sameBinding(ticket, current) && ticket.token.revision === current.token.revision &&
      ticket.source === current.source;
  }

  finish(ticket: MarkdownReadingTicket): void {
    if (this.active === ticket) {
      this.active = null;
    }
  }

  dispose(): void {
    this.disposed = true;
    this.identity = '';
    this.active = null;
    // disposed 永不可复活；组件重挂须 new 一个实例，mountId 不复用。
  }
}
