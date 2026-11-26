import { useEffect, useRef, useState } from 'react';
import type { MouseEvent as ReactMouseEvent, ReactNode } from 'react';
import type { ClientState } from '../web/client';
import { webClient } from '../web/client';
import { Composer } from './Composer';
import { ConnectionBanner } from './ConnectionBanner';
import { LiveMessage, MessageItem } from './MessageItem';
import { Icon } from '../ui/icons';
import { copyText } from '../ui/clipboard';
import { toast } from '../ui/toast';
import { dayKey, formatDayLabel, formatRelative } from '../ui/format';
import type { WebMessageDto } from '../web/protocol';

interface ChatPageProps {
  conversationId: string;
  state: ClientState;
  onOpenSidebar: () => void;
}

// 聊天面：历史消息 + 乐观用户消息 + 当前直播轮（全文整段替换）+ 输入坞。
// 自动跟底只在用户接近底部时生效；向上翻历史不被流式增量打断。
export function ChatPage({ conversationId, state, onOpenSidebar }: ChatPageProps) {
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const stickRef = useRef(true);
  const prependRef = useRef<{ height: number; top: number; count: number } | null>(null);
  const [atBottom, setAtBottom] = useState(true);

  const conversation = state.conversations.find((item) => item.id === conversationId);
  const title = conversation?.title || '会话';
  const streaming = state.live !== null && state.live.active;

  // 键盘避让：移动端软键盘弹出时布局视口不变、visualViewport 变矮。把真实可视高度写进
  // --app-h，聊天页据此收高，输入坞自然贴在键盘上沿（iOS/Android 同一套路径）。
  useEffect(() => {
    const viewport = window.visualViewport;
    if (viewport === null || viewport === undefined) {
      return undefined;
    }
    const apply = (): void => {
      const height = Math.round(viewport.height);
      if (height > 0) {
        document.documentElement.style.setProperty('--app-h', `${height}px`);
      }
      if (stickRef.current) {
        const el = scrollRef.current;
        if (el !== null) {
          el.scrollTop = el.scrollHeight;
        }
      }
    };
    apply();
    viewport.addEventListener('resize', apply);
    viewport.addEventListener('scroll', apply);
    return (): void => {
      viewport.removeEventListener('resize', apply);
      viewport.removeEventListener('scroll', apply);
      document.documentElement.style.removeProperty('--app-h');
    };
  }, []);

  const subtitle = streaming
    ? `${state.live?.origin === 'web' ? '本页发起' : '手机发起'} · 内容实时同步`
    : conversation?.updatedAt
      ? `最近更新 ${formatRelative(conversation.updatedAt)} · 与手机同步`
      : '消息与手机同步';

  const onScroll = (): void => {
    const el = scrollRef.current;
    if (el === null) {
      return;
    }
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    stickRef.current = nearBottom;
    setAtBottom(nearBottom);
  };

  const scrollToBottom = (): void => {
    const el = scrollRef.current;
    if (el === null) {
      return;
    }
    stickRef.current = true;
    setAtBottom(true);
    el.scrollTop = el.scrollHeight;
  };

  useEffect(() => {
    const el = scrollRef.current;
    if (el === null || state.loadingEarlier) {
      return;
    }
    if (prependRef.current !== null) {
      const anchor = prependRef.current;
      prependRef.current = null;
      if (state.messages.length > anchor.count) {
        el.scrollTop = anchor.top + (el.scrollHeight - anchor.height);
        return;
      }
    }
    if (stickRef.current) {
      // 直接落位（不用 rAF：后台标签页 rAF 会被节流/暂停，流式跟底会失效）
      el.scrollTop = el.scrollHeight;
    }
  }, [state.messages, state.pendingUsers, state.live?.text, state.live?.reasoning,
    state.live?.active, state.loadingEarlier]);

  const onLoadEarlier = (): void => {
    const el = scrollRef.current;
    if (el === null) {
      return;
    }
    prependRef.current = { height: el.scrollHeight, top: el.scrollTop, count: state.messages.length };
    webClient.loadEarlier();
  };

  // 代码块复制（事件委托）：markdown 产物里的复制键不带 React 处理器，
  // 这里按 closest 找块，读 <code>.textContent 作为复制内容
  const onContentClick = (event: ReactMouseEvent<HTMLDivElement>): void => {
    const target = event.target as HTMLElement | null;
    if (target === null) {
      return;
    }
    const button = target.closest('.codeblock-copy');
    if (!(button instanceof HTMLElement)) {
      return;
    }
    const block = button.closest('.codeblock');
    const code = block !== null ? block.querySelector('code') : null;
    if (code === null) {
      return;
    }
    void copyText(code.textContent ?? '').then((ok: boolean): void => {
      if (!ok) {
        toast('复制失败，请长按选择文本');
        return;
      }
      button.classList.add('copied');
      const label = button.querySelector('span');
      if (label !== null) {
        label.textContent = '已复制';
      }
      window.setTimeout((): void => {
        button.classList.remove('copied');
        if (label !== null) {
          label.textContent = '复制';
        }
      }, 1600);
    });
  };

  const empty = !state.messagesLoading
    && state.messages.length === 0
    && state.pendingUsers.length === 0
    && state.live === null;

  return (
    <div className="chat-page">
      <header className="chat-head">
        <button
          type="button"
          className="icon-btn only-mobile"
          onClick={onOpenSidebar}
          aria-label="打开会话列表"
        >
          <Icon name="menu" />
        </button>
        <div className="chat-head-main">
          <div className="chat-title-row">
            <h1 className="chat-title" title={title}>{title}</h1>
            {streaming ? <span className="badge accent">生成中</span> : null}
          </div>
          <div className="chat-sub">{subtitle}</div>
        </div>
        <div className="chat-head-actions">
          <button
            type="button"
            className="icon-btn"
            onClick={() => webClient.retryCurrentConversation()}
            aria-label="重新载入本会话"
            title="重新载入本会话"
          >
            <Icon name="refresh" />
          </button>
        </div>
      </header>

      <div className="chat-banner-wrap">
        <ConnectionBanner
          state={state}
          onRetry={() => {
            if (state.phase === 'ready') {
              webClient.refreshConversations();
            } else {
              webClient.retryNow();
            }
          }}
        />
      </div>

      <div className="chat-scroll" ref={scrollRef} onScroll={onScroll} onClick={onContentClick}>
        <div className="chat-content">
          {state.messagesLoading && state.messages.length === 0 ? (
            <>
              <div className="sk-msg assistant"><div className="sk sk-bubble" /></div>
              <div className="sk-msg user"><div className="sk sk-bubble" /></div>
              <div className="sk-msg assistant"><div className="sk sk-bubble" /></div>
            </>
          ) : null}

          {state.nextCursor !== '' ? (
            <button
              type="button"
              className="load-earlier"
              onClick={onLoadEarlier}
              disabled={state.loadingEarlier}
            >
              {state.loadingEarlier ? '正在载入…' : '加载更早消息'}
            </button>
          ) : null}

          {state.messagesError !== '' ? (
            <div className="error-card">
              <span>{state.messagesError}</span>
              <button
                type="button"
                className="link-btn"
                onClick={() => webClient.retryCurrentConversation()}
              >
                重新载入
              </button>
            </div>
          ) : null}

          {state.historyOk === false ? (
            <div className="error-card">
              <span>历史消息读取超时，当前只显示实时内容。</span>
              <button
                type="button"
                className="link-btn"
                onClick={() => webClient.retryCurrentConversation()}
              >
                重试
              </button>
            </div>
          ) : null}

          {renderTimeline(state.messages, state.pendingUsers)}
          {state.live !== null ? <LiveMessage live={state.live} /> : null}

          {empty ? (
            <div className="empty-chat">
              <span className="msg-avatar" aria-hidden="true"><Icon name="logo" /></span>
              <span className="empty-title">这条会话还没有消息</span>
              <span>在下方输入内容，手机会收到同一条消息并开始回答。</span>
            </div>
          ) : null}
        </div>
      </div>

      <div className="composer-wrap">
        {!atBottom ? (
          <button type="button" className="jump-bottom" onClick={scrollToBottom}>
            <Icon name="arrowDown" />
            回到底部
          </button>
        ) : null}
        <Composer disabled={state.phase !== 'ready'} liveActive={streaming} />
      </div>
    </div>
  );
}

// 时间线：跨天处插日期分隔；乐观用户消息排在有 id 的消息之后
function renderTimeline(messages: WebMessageDto[], pending: WebMessageDto[]): ReactNode[] {
  const nodes: ReactNode[] = [];
  let lastDay = '';
  for (const message of messages) {
    const key = dayKey(message.createdAt);
    if (key !== '' && key !== lastDay) {
      lastDay = key;
      nodes.push(
        <div className="date-sep" key={`sep-${key}-${message.id}`}>
          <span>{formatDayLabel(message.createdAt)}</span>
        </div>,
      );
    }
    nodes.push(<MessageItem key={message.id} message={message} />);
  }
  for (const message of pending) {
    const key = dayKey(message.createdAt);
    if (key !== '' && key !== lastDay) {
      lastDay = key;
      nodes.push(
        <div className="date-sep" key={`sep-${key}-${message.id}`}>
          <span>{formatDayLabel(message.createdAt)}</span>
        </div>,
      );
    }
    nodes.push(<MessageItem key={message.id} message={message} />);
  }
  return nodes;
}
