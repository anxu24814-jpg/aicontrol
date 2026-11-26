/** 正文展示绑定的换源与终态投影；不改变消息、轮次或数据库的业务状态。 */
import { MarkdownEndReason, nextMarkdownBindingId } from '../../common/markdown/MarkdownDocumentModel';
import { ChatMessage } from './ChatMessageCompose';
import { ChatDisplayItem, DisplayRoundFacts } from './ChatDisplayProjection';

export function renewMarkdownBindings(messages: ChatMessage[]): void {
  for (const message of messages) {
    // 用户编辑/分支重载也可能复用同ID同文；展示身份必须随安装重铸，不能靠内容判换版。
    if (message.kind === 'assistant' || message.kind === 'user') {
      message.bodyBindingId = nextMarkdownBindingId();
      message.bodyEndReason = undefined;
    }
  }
}

export function settleMarkdownBodies(messages: ChatMessage[], rounds: Map<string, DisplayRoundFacts>): void {
  const lastBodies: Map<string, ChatMessage> = new Map();
  for (const message of messages) {
    if (message.kind === 'assistant' && message.displayRoundId !== '') {
      lastBodies.set(message.displayRoundId, message);
    }
  }
  for (const message of messages) {
    if (message.kind !== 'assistant' || message.live !== true || message.streaming === true ||
      message.bodyEndReason !== undefined) {
      continue;
    }
    const facts: DisplayRoundFacts | undefined = rounds.get(message.displayRoundId);
    let reason: MarkdownEndReason | undefined = undefined;
    if (message.displayRoundId !== '' && lastBodies.get(message.displayRoundId) !== message) {
      reason = 'done';
    } else if (facts !== undefined) {
      if (facts.status === 'stopped') {
        reason = 'stopped';
      } else if (facts.status === 'error') {
        reason = 'failed';
      } else if (facts.status === 'done') {
        reason = message.truncated === true ? 'truncated' : 'done';
      }
    }
    // 工具等待期间末段虽streaming=false仍可能被停止再次收尾；等后继正文或轮终态证明。
    // 历史unknown不伪报done，保留原文可读，不为显示新增持久化事实。
    if (reason !== undefined) {
      message.bodyEndReason = reason;
    }
  }
}

export function markdownDisplayItemKey(item: ChatDisplayItem): string {
  const message: ChatMessage | null = item.msg;
  // 只扩渲染键；业务item.key、菜单目标及滚动锚保持原值，同绑定文本变化不换键。
  return message !== null && (message.kind === 'assistant' || message.kind === 'user') ?
    item.key + '/' + message.bodyBindingId : item.key;
}
