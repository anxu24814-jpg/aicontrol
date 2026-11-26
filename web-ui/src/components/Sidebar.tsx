import { useEffect, useMemo, useRef, useState } from 'react';
import type { ClientState } from '../web/client';
import { webClient } from '../web/client';
import { navigate } from '../router';
import { Icon } from '../ui/icons';
import { formatRelative, groupByTime, identityIndex, identityInitial } from '../ui/format';
import { themeLabel } from '../ui/theme';
import type { ThemeMode } from '../ui/theme';

interface SidebarProps {
  state: ClientState;
  activeId: string;
  drawer: boolean;
  themeMode: ThemeMode;
  onCycleTheme: () => void;
  onNewChat: () => void;
  onRefresh: () => void;
  onClose: () => void;
}

const PHASE_TEXT: Record<string, string> = {
  connecting: '正在连接',
  authing: '正在验证',
  ready: '已连接',
  paused: '服务已暂停',
  reconnecting: '重连中',
  disconnected: '未连接',
};

// 侧栏（桌面常驻 / 手机抽屉）：品牌行 + 新会话入口 + 会话时间分组 + 连接状态与主题。
// 数据全部来自 ClientState（会话列表由 webClient 在 snapshot 与 conv_invalidate 时刷新），
// 本组件不发起读请求——除刷新键显式调 refreshConversations。
export function Sidebar({
  state,
  activeId,
  drawer,
  themeMode,
  onCycleTheme,
  onNewChat,
  onRefresh,
  onClose,
}: SidebarProps) {
  const [query, setQuery] = useState('');
  const [onlyRunning, setOnlyRunning] = useState(false);
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});
  const searchRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!drawer) {
      setQuery('');
      setOnlyRunning(false);
    }
  }, [drawer]);

  const groups = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    let list = state.conversations;
    if (onlyRunning) {
      list = list.filter((item) => state.activeRuns.includes(item.id));
    }
    if (keyword !== '') {
      list = list.filter((item) => (item.title || '').toLowerCase().includes(keyword));
    }
    return groupByTime(list);
  }, [state.conversations, state.activeRuns, query, onlyRunning]);

  const runningCount = state.conversations.filter(
    (item) => state.activeRuns.includes(item.id),
  ).length;

  const open = (id: string): void => {
    navigate(`/c/${encodeURIComponent(id)}`);
    if (drawer) {
      onClose();
    }
  };

  const toggleGroup = (key: string): void => {
    setCollapsed((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  return (
    <aside className={`sidebar${drawer ? ' drawer' : ''}`} aria-label="会话导航">
      <div className="side-head">
        <div className="brand">
          <span className="brand-mark">
            <Icon name="logo" />
          </span>
          <span className="brand-name">AI Control</span>
          <span className="brand-tag">WEB</span>
        </div>
        {drawer ? (
          <button type="button" className="icon-btn" onClick={onClose} aria-label="关闭导航">
            <Icon name="close" />
          </button>
        ) : null}
      </div>

      <button type="button" className="new-chat" onClick={onNewChat}>
        <Icon name="plus" />
        新会话
      </button>
      <p className="new-chat-note">在手机端点「＋」新建，这里自动出现</p>

      <div className="side-nav">
        <button
          type="button"
          className="nav-row"
          onClick={() => { setOnlyRunning(false); searchRef.current?.focus(); }}
        >
          <Icon name="search" />
          搜索会话
          <span className="nav-tail">{state.conversations.length}</span>
        </button>
        {runningCount > 0 ? (
          <button
            type="button"
            className="nav-row"
            onClick={() => setOnlyRunning((prev) => !prev)}
            aria-pressed={onlyRunning}
          >
            <Icon name="spark" />
            {onlyRunning ? '显示全部会话' : '只看生成中'}
            <span className="nav-tail">{runningCount}</span>
          </button>
        ) : null}
      </div>

      <div className="side-body">
        <div className="side-section">
          <div className="side-section-head">
            <span>会话</span>
            <span className="tools">
              <button
                type="button"
                className="side-icon-btn"
                onClick={onRefresh}
                aria-label="刷新会话列表"
                title="刷新会话列表"
              >
                <Icon name="refresh" />
              </button>
            </span>
          </div>

          <label className="side-search">
            <Icon name="search" />
            <input
              ref={searchRef}
              value={query}
              placeholder="按标题筛选"
              aria-label="按标题筛选会话"
              onChange={(event) => setQuery(event.target.value)}
            />
            {query !== '' ? (
              <button
                type="button"
                className="side-icon-btn"
                onClick={() => setQuery('')}
                aria-label="清除筛选"
              >
                <Icon name="close" />
              </button>
            ) : null}
          </label>

          {state.conversationsLoading && state.conversations.length === 0 ? (
            <div className="side-group-empty">正在读取会话…</div>
          ) : null}

          {groups.map((group) => {
            const closed = collapsed[group.key] === true;
            return (
              <div className="side-group" key={group.key}>
                <button
                  type="button"
                  className={`side-group-head${closed ? ' closed' : ''}`}
                  onClick={() => toggleGroup(group.key)}
                  aria-expanded={!closed}
                >
                  <Icon name="chevronDown" className="caret" />
                  {group.label}
                  <span className="count">{group.items.length}</span>
                </button>
                {closed ? null : group.items.map((item) => {
                  const running = state.activeRuns.includes(item.id);
                  return (
                    <button
                      key={item.id}
                      type="button"
                      className={`side-conv${item.id === activeId ? ' active' : ''}`}
                      onClick={() => open(item.id)}
                      title={item.title || '未命名会话'}
                    >
                      {item.favorite ? <Icon name="star" filled className="star" /> : null}
                      <span className="name">{item.title || '未命名会话'}</span>
                      {running ? <span className="live-dot" aria-label="生成中" /> : null}
                      <span className="when">{formatRelative(item.updatedAt)}</span>
                    </button>
                  );
                })}
              </div>
            );
          })}

          {!state.conversationsLoading && groups.length === 0 ? (
            <div className="side-group-empty">
              {query !== '' || onlyRunning
                ? '没有匹配的会话。'
                : '还没有会话。在手机端新建后会自动出现在这里。'}
            </div>
          ) : null}
        </div>
      </div>

      <div className="side-foot">
        <button
          type="button"
          className="side-user"
          onClick={() => webClient.refreshConversations()}
          title="刷新会话列表"
        >
          <span className={`avatar identity-${identityIndex(state.conversationId || 'phone')}`}>
            {identityInitial('手机')}
          </span>
          <span className="side-user-main">
            <span className="side-user-name">手机端助手</span>
            <span className="side-user-sub">
              <span className={`status-dot ${state.phase === 'ready' ? 'ready' : 'paused'}`} />
              {PHASE_TEXT[state.phase] ?? ''}
            </span>
          </span>
        </button>
        <button
          type="button"
          className="icon-btn"
          onClick={onCycleTheme}
          aria-label={`主题：${themeLabel(themeMode)}`}
          title={`主题：${themeLabel(themeMode)}`}
        >
          <Icon name={themeMode === 'auto' ? 'auto' : themeMode === 'light' ? 'sun' : 'moon'} />
        </button>
      </div>
    </aside>
  );
}
