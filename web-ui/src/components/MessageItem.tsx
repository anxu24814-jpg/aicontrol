import { useMemo, useState } from 'react';
import type { LiveRound } from '../web/client';
import { roundStatusText } from '../web/protocol';
import type { WebMessageDto } from '../web/protocol';
import { renderMarkdown } from '../ui/markdown';
import { copyText } from '../ui/clipboard';
import { toast } from '../ui/toast';
import { Icon } from '../ui/icons';
import { formatClock, toolStateClass, toolStateText } from '../ui/format';

// Markdown 正文（html:false 已转义；dangerouslySetInnerHTML 只接收 markdown-it 产物）
export function MarkdownText({ text, cursor = false }: { text: string; cursor?: boolean }) {
  const html = useMemo(() => renderMarkdown(text), [text]);
  return (
    <div className="md-wrap">
      <div className="md" dangerouslySetInnerHTML={{ __html: html }} />
      {cursor ? <span className="stream-cursor" aria-hidden="true" /> : null}
    </div>
  );
}

function TruncatedHint({ truncated }: { truncated: boolean }) {
  return truncated ? <div className="truncated">内容过长，已截断。</div> : null;
}

// 复制键 + 时刻（悬停显形；触屏常显由 CSS 控制）
function MessageActions({ text, createdAt }: { text: string; createdAt: number }) {
  const [copied, setCopied] = useState(false);

  const onCopy = (): void => {
    void copyText(text).then((ok: boolean): void => {
      if (!ok) {
        toast('复制失败，请长按选择文本');
        return;
      }
      setCopied(true);
      toast('已复制');
      window.setTimeout((): void => setCopied(false), 1500);
    });
  };

  return (
    <div className="msg-actions">
      <button
        type="button"
        className={`action-btn${copied ? ' done' : ''}`}
        onClick={onCopy}
        aria-label="复制这条消息"
      >
        <Icon name={copied ? 'check' : 'copy'} />
        {copied ? '已复制' : '复制'}
      </button>
      {createdAt > 0 ? <span className="msg-time">{formatClock(createdAt)}</span> : null}
    </div>
  );
}

function ThinkingBlock({ text, open = false }: { text: string; open?: boolean }) {
  return (
    <details className="thinking" open={open}>
      <summary>
        <Icon name="chevronRight" />
        <span>思考过程</span>
        <span className="thinking-len">{text.length} 字</span>
      </summary>
      <div className="thinking-body">
        <MarkdownText text={text} />
      </div>
    </details>
  );
}

// 历史消息卡（role 由 WebReadApi 直接映 ChatMessage.kind）
export function MessageItem({ message }: { message: WebMessageDto }) {
  if (message.role === 'user') {
    return (
      <div className="msg user">
        <div className="msg-body">
          <div className="user-bubble">{message.text}</div>
          <TruncatedHint truncated={message.truncated} />
          <MessageActions text={message.text} createdAt={message.createdAt} />
        </div>
      </div>
    );
  }
  if (message.role === 'thinking') {
    return <ThinkingBlock text={message.text} />;
  }
  if (message.role === 'tool') {
    const stateText = toolStateText(message.toolState);
    return (
      <div className={`tool-card ${toolStateClass(message.toolState)}`}>
        <div className="tool-head">
          <Icon name="terminal" />
          <span className="tool-name">{message.toolName || '工具调用'}</span>
          {stateText !== '' ? (
            <span className={`tool-state ${toolStateClass(message.toolState)}`}>{stateText}</span>
          ) : null}
        </div>
        {message.text !== '' ? <div className="tool-preview">{message.text}</div> : null}
        <TruncatedHint truncated={message.truncated} />
      </div>
    );
  }
  if (message.role === 'summary' || message.role === 'clear' || message.role === 'notice') {
    if (message.text === '') {
      return <div className="sys-rule" role="separator" />;
    }
    return <div className="sys-line">{message.text}</div>;
  }
  // assistant（默认）
  return (
    <div className="msg assistant">
      <span className="msg-avatar" aria-hidden="true">
        <Icon name="logo" />
      </span>
      <div className="msg-body">
        <MarkdownText text={message.text} />
        <TruncatedHint truncated={message.truncated} />
        <MessageActions text={message.text} createdAt={message.createdAt} />
      </div>
    </div>
  );
}

// 直播中的当前轮（整段替换：text 是服务端给的全文字段，前端直接渲染）
export function LiveMessage({ live }: { live: LiveRound }) {
  const settledText = live.active ? '' : roundStatusText(live.status);
  return (
    <div className="msg assistant live">
      <span className="msg-avatar" aria-hidden="true">
        <Icon name="logo" />
      </span>
      <div className="msg-body">
        <div className="live-head">
          {live.active ? <span className="live-pulse">生成中</span> : null}
          {settledText !== '' ? (
            <span className={`badge ${live.status === 'done' ? '' : 'danger'}`}>{settledText}</span>
          ) : null}
          <span className="origin-tag">{live.origin === 'web' ? '本页发起' : '手机发起'}</span>
        </div>
        {live.reasoning !== '' ? (
          <ThinkingBlock text={live.reasoning} open={live.active} />
        ) : null}
        {live.text !== '' ? (
          <MarkdownText text={live.text} cursor={live.active} />
        ) : live.active ? (
          <div className="live-placeholder">
            <span className="stream-cursor" aria-hidden="true" />
            <span>正在等待首段内容…</span>
          </div>
        ) : (
          <div className="live-placeholder">
            {live.status === 'done' ? '生成完成，没有可显示的内容。' : '本轮没有生成内容。'}
          </div>
        )}
        {!live.active && live.text !== '' ? (
          <MessageActions text={live.text} createdAt={live.updatedAt} />
        ) : null}
      </div>
    </div>
  );
}
