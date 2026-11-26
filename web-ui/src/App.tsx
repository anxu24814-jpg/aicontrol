import { useEffect, useState } from 'react';
import { webClient } from './web/client';
import { useWebClient } from './web/useWebClient';
import { useRoute } from './router';
import { AuthScreen } from './components/AuthScreen';
import { ChatPage } from './components/ChatPage';
import { ConversationListPage } from './components/ConversationListPage';
import { Modal } from './components/Modal';
import { Sidebar } from './components/Sidebar';
import { ToastHost } from './ui/toast';
import { applyTheme, nextThemeMode, readThemeMode } from './ui/theme';
import type { ThemeMode } from './ui/theme';

export default function App() {
  const state = useWebClient();
  const route = useRoute();
  const [themeMode, setThemeMode] = useState<ThemeMode>(() => readThemeMode());
  const [drawer, setDrawer] = useState(false);
  const [newChatOpen, setNewChatOpen] = useState(false);

  // 有已存口令（sessionStorage）才自动连接；无口令停在口令页
  useEffect(() => {
    webClient.start();
  }, []);

  // 主题：显式应用一次（index.html 内联脚本已做首帧防闪），auto 档跟随系统变化
  useEffect(() => {
    applyTheme(themeMode);
  }, [themeMode]);

  useEffect(() => {
    if (typeof window.matchMedia !== 'function') {
      return undefined;
    }
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (): void => {
      if (themeMode === 'auto') {
        applyTheme('auto');
      }
    };
    media.addEventListener('change', onChange);
    return (): void => media.removeEventListener('change', onChange);
  }, [themeMode]);

  // 路由 → 会话通道：进入 /c/:id 即向服务端登记（read_messages 首开触发 snapshot）
  const routeKind = route.kind;
  const routeId = route.kind === 'chat' ? route.id : '';
  useEffect(() => {
    if (routeKind === 'chat') {
      webClient.openConversation(routeId);
    } else {
      webClient.closeConversation();
    }
    setDrawer(false);
  }, [routeKind, routeId]);

  useEffect(() => {
    if (route.kind === 'chat') {
      const conversation = state.conversations.find((item) => item.id === route.id);
      document.title = conversation?.title
        ? `${conversation.title} · AI Control`
        : 'AI Control 网页遥控';
    } else {
      document.title = 'AI Control 网页遥控';
    }
  }, [route, state.conversations]);

  if (!state.hasCode || state.phase === 'disconnected') {
    return (
      <div className="app">
        <main className="main">
          <AuthScreen state={state} />
        </main>
        <ToastHost />
      </div>
    );
  }

  const cycleTheme = (): void => setThemeMode((current) => nextThemeMode(current));

  const sidebarProps = {
    state,
    activeId: routeId,
    themeMode,
    onCycleTheme: cycleTheme,
    onNewChat: () => setNewChatOpen(true),
    onRefresh: () => webClient.refreshConversations(),
    onClose: () => setDrawer(false),
  };

  return (
    <div className="app">
      <Sidebar {...sidebarProps} drawer={false} />

      {drawer ? (
        <>
          <div className="drawer-scrim" onClick={() => setDrawer(false)} role="presentation" />
          <Sidebar {...sidebarProps} drawer />
        </>
      ) : null}

      <main className="main">
        {route.kind === 'chat' ? (
          <ChatPage
            key={route.id}
            conversationId={route.id}
            state={state}
            onOpenSidebar={() => setDrawer(true)}
          />
        ) : (
          <ConversationListPage state={state} themeMode={themeMode} onCycleTheme={cycleTheme} />
        )}
      </main>

      <ToastHost />

      {newChatOpen ? (
        <Modal
          title="新建会话在手机端完成"
          onClose={() => setNewChatOpen(false)}
          actions={(
            <button type="button" className="primary-btn" onClick={() => setNewChatOpen(false)}>
              知道了
            </button>
          )}
        >
          <p style={{ margin: 0 }}>网页端只做遥控，不持有会话创建权。新建后会自动出现在这里：</p>
          <ol>
            <li>打开手机上的本应用；</li>
            <li>在对话页签点右下角「＋」（或在会话内「⋯」菜单选「新建会话」）；</li>
            <li>回到这里点右上角刷新，或等下一次同步。</li>
          </ol>
        </Modal>
      ) : null}


    </div>
  );
}
