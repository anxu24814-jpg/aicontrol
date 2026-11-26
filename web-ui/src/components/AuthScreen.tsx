import { useEffect, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import type { ClientState } from '../web/client';
import { webClient } from '../web/client';
import { Icon } from '../ui/icons';

// 口令配对面（首屏）：6 位数字码 → sessionStorage → 建立 SSE 流并首消息鉴权。
// 服务端语义（WebAuthValidator.ets）：口令空且非本机档 = 拒绝全部；本机档免口令但仍须
// 5s 内发首条消息——本端永远发 auth 信封，两种档位同一条路径。
export function AuthScreen({ state }: { state: ClientState }) {
  const [code, setCode] = useState('');
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // 只有「已提交过口令且在途」才显示连接中——首屏无口令时 phase 仍是初值 connecting，
  // 直接按 phase 判会给出「正在连接…」的假状态
  const connecting = state.hasCode
    && (state.phase === 'connecting' || state.phase === 'authing');

  const submit = (event: FormEvent<HTMLFormElement>): void => {
    event.preventDefault();
    if (code.length !== 6) {
      return;
    }
    webClient.submitCode(code);
  };

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-logo">
          <Icon name="logo" />
        </div>
        <h1 className="auth-title">连接手机</h1>
        <p className="auth-sub">
          输入手机「Web 服务」设置页显示的 6 位访问密码。密码只保存在本标签页，关闭页面即清除。
        </p>
        <form className="auth-form" onSubmit={submit}>
          <input
            ref={inputRef}
            className="pin-input"
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            value={code}
            placeholder="六位数字密码"
            aria-label="六位访问密码"
            onChange={(event) => {
              const digits = event.target.value.replace(/\D/g, '').slice(0, 6);
              setCode(digits);
            }}
          />
          {state.authError !== '' ? <p className="auth-error">{state.authError}</p> : null}
          <button type="submit" className="primary-btn" disabled={code.length !== 6}>
            {connecting ? '正在连接…' : '连接手机'}
          </button>
        </form>
        <p className="auth-hint">
          手机与这台设备需要连接同一个局域网。手机端请保持 App 在前台，退到后台时服务会暂停。
        </p>
      </div>
    </div>
  );
}
