// 轻提示（2026-10-22 视觉重做新增）：单例队列，最长同时一条，1.9s 自动消失。
// 用途 = 复制成功/失败、新建会话指引等一次性反馈；不做全局状态库，避免为一句提示引入依赖。
import { useEffect, useState } from 'react';

type Listener = (message: string) => void;

const listeners = new Set<Listener>();

export function toast(message: string): void {
  const text = message.trim();
  if (text === '') {
    return;
  }
  for (const listener of listeners) {
    listener(text);
  }
}

export function ToastHost() {
  const [message, setMessage] = useState('');
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    let timer = 0;
    const onToast = (next: string): void => {
      setMessage(next);
      setVisible(true);
      window.clearTimeout(timer);
      timer = window.setTimeout((): void => setVisible(false), 1900);
    };
    listeners.add(onToast);
    return (): void => {
      window.clearTimeout(timer);
      listeners.delete(onToast);
    };
  }, []);

  if (!visible || message === '') {
    return null;
  }
  return (
    <div className="toast-host" role="status" aria-live="polite">
      <div className="toast">{message}</div>
    </div>
  );
}
