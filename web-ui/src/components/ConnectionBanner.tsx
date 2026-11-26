import type { ClientState } from '../web/client';

interface ConnectionBannerProps {
  state: ClientState;
  onRetry: () => void;
}

// 连接状态横幅（非 ready 时常显；ready 时只在列表/消息读失败时出错误条）。
// server_paused = 手机退后台的主动暂停：显示等待态而不是重连风暴（总案 §7.1）。
export function ConnectionBanner({ state, onRetry }: ConnectionBannerProps) {
  if (state.phase === 'ready') {
    if (state.conversationsError !== '') {
      return (
        <div className="banner warn">
          <span className="banner-text">{state.conversationsError}</span>
          <button type="button" className="link-btn" onClick={onRetry}>重试</button>
        </div>
      );
    }
    return null;
  }
  if (state.phase === 'disconnected') {
    return null;
  }
  if (state.phase === 'paused') {
    return (
      <div className="banner">
        <span className="banner-text">
          手机服务已暂停。保持手机 App 在前台，服务恢复后会自动重连。
        </span>
        <button type="button" className="link-btn" onClick={onRetry}>重试连接</button>
      </div>
    );
  }
  if (state.phase === 'reconnecting') {
    return (
      <div className="banner">
        <span className="banner-text">
          连接已断开，正在重连。第 {state.reconnectAttempt} 次尝试，约 {state.reconnectInSec} 秒后再试。
        </span>
        <button type="button" className="link-btn" onClick={onRetry}>立即重试</button>
      </div>
    );
  }
  return (
    <div className="banner">
      <span className="banner-text">
        {state.phase === 'authing' ? '正在验证口令…' : '正在连接手机服务…'}
      </span>
    </div>
  );
}
