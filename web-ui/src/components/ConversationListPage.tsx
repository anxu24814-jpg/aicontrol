import { useMemo, useState } from 'react';
import type { ClientState } from '../web/client';
import { webClient } from '../web/client';
import { navigate } from '../router';
import { Icon } from '../ui/icons';
import { formatRelative, groupByTime, identityIndex, identityInitial } from '../ui/format';
import { themeLabel } from '../ui/theme';
import type { ThemeMode } from '../ui/theme';

interface ListPageProps {
  state: ClientState;
  themeMode: ThemeMode;
  onCycleTheme: () => void;
}

// 会话列表面：手机端 = 卡片分组列表（参照手机视觉稿的 iCloud 式卡片）；
// 桌面端 = 主区欢迎面（会话已在左侧栏常驻，主区再列一遍是重复信息）。
export function ConversationListPage({ state, themeMode, onCycleTheme }: ListPageProps) {
  return (
    <>
      <div className="desktop-only welcome-wrap">
        <WelcomePane state={state} />
      </div>
      <div className="list-page mobile-only">
        <MobileList state={state} themeMode={themeMode} onCycleTheme={onCycleTheme} />
      </div>
    </>
  );
}

function MobileList({ state, themeMode, onCycleTheme }: ListPageProps) {
  const [query, setQuery] = useState('');
  const groups = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    const list = keyword === ''
      ? state.conversations
      : state.conversations.filter((item) => (item.title || '').toLowerCase().includes(keyword));
    return groupByTime(list);
  }, [state.conversations, query]);

  const retry = (): void => {
    if (state.phase === 'ready') {
      webClient.refreshConversations();
    } else {
      webClient.retryNow();
    }
  };

  const ready = state.phase === 'ready';
  const paused = state.phase === 'paused';
  const title = ready
    ? (paused ? '服务已暂停' : '手机已连接')
    : state.phase === 'reconnecting'
      ? '连接已断开'
      : '正在连接手机';
  const sub = ready
    ? '会话与生成进度实时同步，网页端只读历史、可继续对话。'
    : paused
      ? '手机 App 退到后台时服务会暂停，回到前台后自动恢复。'
      : '请确认手机端 Web 服务已开启，且与这台设备在同一局域网。';

  return (
    <div className="list-inner">
      <header className="page-head">
        <div className="page-head-row">
          <h1>会话</h1>
          <div className="head-actions">
            <button
              type="button"
              className="icon-btn"
              onClick={onCycleTheme}
              aria-label={`主题：${themeLabel(themeMode)}`}
              title={`主题：${themeLabel(themeMode)}`}
            >
              <Icon name={themeMode === 'auto' ? 'auto' : themeMode === 'light' ? 'sun' : 'moon'} />
            </button>
            <button
              type="button"
              className="icon-btn"
              onClick={retry}
              aria-label="刷新会话"
              title="刷新会话"
            >
              <Icon name="refresh" />
            </button>
          </div>
        </div>
        <p className="page-sub">{state.conversations.length} 个会话 · 与手机实时同步</p>
      </header>

      <section className="status-card" aria-label="连接状态">
        <span className={`status-icon${ready ? '' : paused ? ' warn' : ' off'}`}>
          <Icon name={ready ? 'monitor' : paused ? 'phone' : 'sync'} />
        </span>
        <span className={`status-pill${ready ? ' ok' : ''}`}>
          <span className={`status-dot ${ready ? 'ready' : paused ? 'paused' : 'busy'}`} />
          {ready ? '已连接' : paused ? '已暂停' : '连接中'}
        </span>
        <h2 className="status-title">{title}</h2>
        <p className="status-sub">{sub}</p>
        <div className="status-actions">
          <button type="button" className="ghost-btn" onClick={retry}>
            <Icon name="refresh" />
            {ready ? '刷新会话' : '立即重试'}
          </button>
        </div>
      </section>

      <label className="list-search">
        <Icon name="search" />
        <input
          value={query}
          placeholder="搜索会话标题"
          aria-label="搜索会话标题"
          onChange={(event) => setQuery(event.target.value)}
        />
        {query !== '' ? (
          <button type="button" className="side-icon-btn" onClick={() => setQuery('')} aria-label="清除搜索">
            <Icon name="close" />
          </button>
        ) : null}
      </label>

      {state.conversationsLoading && state.conversations.length === 0 ? (
        <div className="ios-card" aria-label="载入中">
          {[0, 1, 2, 3].map((index) => (
            <div className="sk-row" key={index}>
              <div className="sk sk-avatar" />
              <div className="sk-lines">
                <div className="sk sk-line" />
                <div className="sk sk-line short" />
              </div>
            </div>
          ))}
        </div>
      ) : null}

      {state.conversationsError !== '' ? (
        <div className="banner warn" style={{ marginTop: 12 }}>
          <span className="banner-text">{state.conversationsError}</span>
          <button type="button" className="link-btn" onClick={() => webClient.refreshConversations()}>
            重试
          </button>
        </div>
      ) : null}

      {groups.map((group) => (
        <section key={group.key} aria-label={group.label}>
          <div className="section-label">
            {group.label}
            <span className="label-tail">{group.items.length}</span>
          </div>
          <div className="ios-card">
            {group.items.map((item) => {
              const running = state.activeRuns.includes(item.id);
              return (
                <button
                  key={item.id}
                  type="button"
                  className="conv-item"
                  onClick={() => navigate(`/c/${encodeURIComponent(item.id)}`)}
                >
                  <span className={`avatar lg identity-${identityIndex(item.id)}`} aria-hidden="true">
                    {identityInitial(item.title)}
                  </span>
                  <span className="conv-body">
                    <span className="conv-title">{item.title || '未命名会话'}</span>
                    <span className="conv-meta">
                      {running ? <span className="run-tag"><span className="spinner" />生成中</span> : null}
                      {item.favorite ? <Icon name="star" filled className="star-mark" /> : null}
                      <span>{formatRelative(item.updatedAt)}</span>
                      {running && item.favorite ? <span className="dot-sep" /> : null}
                    </span>
                  </span>
                  <span className="conv-side">
                    <Icon name="chevronRight" />
                  </span>
                </button>
              );
            })}
          </div>
        </section>
      ))}

      {!state.conversationsLoading && state.conversations.length === 0
        && state.conversationsError === '' ? (
        <div className="ios-card" style={{ marginTop: 14 }}>
          <div className="list-empty">
            <strong>还没有会话</strong>
            在手机的助手页新建一个会话，发送第一条消息后，它会自动出现在这里。
          </div>
        </div>
      ) : null}

      {!state.conversationsLoading && state.conversations.length > 0 && groups.length === 0 ? (
        <div className="ios-card" style={{ marginTop: 14 }}>
          <div className="list-empty">没有标题匹配「{query}」的会话。</div>
        </div>
      ) : null}

      <p className="list-foot">
        网页端只做遥控：可以查看历史与继续对话，新建会话、改设置、编辑记忆请在手机端操作。
      </p>
    </div>
  );
}

// 桌面主区欢迎面（参照稿的居中 Hero 结构）：品牌 + 一句主张 + 三张能力卡 + 正在生成的会话。
function WelcomePane({ state }: { state: ClientState }) {
  const running = state.conversations.filter((item) => state.activeRuns.includes(item.id));
  return (
    <div className="welcome">
      <span className="welcome-mark">
        <Icon name="logo" />
      </span>
      <h1 className="welcome-title">
        从手机，继续对话
        <span className="badge accent welcome-badge">局域网</span>
      </h1>
      <p className="welcome-sub">
        左侧是手机上的会话。选一个即可查看历史、接着发消息，回答会实时同步到两端。
      </p>

      <div className="welcome-grid">
        <div className="welcome-card">
          <h3><Icon name="phone" />同一局域网</h3>
          <p>手机与浏览器连同一个 Wi-Fi 即可，数据只在这两台设备之间传输。</p>
        </div>
        <div className="welcome-card">
          <h3><Icon name="sync" />双向同步</h3>
          <p>手机发起的回答可在这边看，网页发送的消息也会落到手机的同一条会话。</p>
        </div>
        <div className="welcome-card">
          <h3><Icon name="lock" />口令进标签页</h3>
          <p>访问口令只存在当前标签页，关闭页面即清除；手机退后台服务自动暂停。</p>
        </div>
      </div>

      {running.length > 0 ? (
        <div className="welcome-running">
          <div className="section-label" style={{ paddingTop: 0 }}>
            正在生成
            <span className="label-tail">{running.length}</span>
          </div>
          {running.map((item) => (
            <button
              key={item.id}
              type="button"
              className="run-row"
              onClick={() => navigate(`/c/${encodeURIComponent(item.id)}`)}
            >
              <span className="run-tag"><span className="spinner" />生成中</span>
              <span className="side-conv-name" style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {item.title || '未命名会话'}
              </span>
              <span style={{ color: 'var(--text-3)', fontSize: 12 }}>{formatRelative(item.updatedAt)}</span>
            </button>
          ))}
        </div>
      ) : null}

      {state.conversations.length === 0 && !state.conversationsLoading ? (
        <p className="welcome-sub" style={{ marginTop: 22, color: 'var(--text-3)' }}>
          左侧还没有会话。请在手机端新建后回到这里。
        </p>
      ) : null}
    </div>
  );
}
