import { useEffect, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import { webClient } from '../web/client';
import { Icon } from '../ui/icons';
import { toast } from '../ui/toast';

interface ComposerProps {
  disabled: boolean;
  liveActive: boolean;
}

// 输入坞（参照稿的圆角卡形制：上方能力条、中部多行输入、下方工具行与发送圆钮）。
// 发送 = send 信封（无头宿主经同一条 ChatSendCtrl 编排链投递/入队）；停止 = stop 信封。
// 能力条里的「手机端助手 / 实时同步」是事实陈述，不是可切换项——本应用没有模型选择面。
export function Composer({ disabled, liveActive }: ComposerProps) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const areaRef = useRef<HTMLTextAreaElement | null>(null);

  useEffect(() => {
    if (text === '' && areaRef.current !== null) {
      areaRef.current.style.height = 'auto';
    }
  }, [text]);

  const submit = async (): Promise<void> => {
    const body = text;
    if (body.trim() === '' || busy || disabled) {
      return;
    }
    setBusy(true);
    setError('');
    try {
      await webClient.sendMessage(body);
      setText('');
    } catch (e) {
      setError(e instanceof Error ? e.message : '发送失败');
      // 保留原文，方便重试（webClient 已回滚乐观消息）
      setText(body);
    } finally {
      setBusy(false);
      areaRef.current?.focus();
    }
  };

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>): void => {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      void submit();
    }
  };

  const onStop = (): void => {
    webClient.stopGeneration();
    toast('已请求停止生成');
  };

  return (
    <div className="composer">
      <div className="composer-chips">
        <span className="chip accent">
          <Icon name="monitor" />
          手机端助手
        </span>
        <span className="chip">
          <Icon name="sync" />
          实时同步
        </span>
        {liveActive ? (
          <span className="chip">
            <span className="spinner" />
            生成中
          </span>
        ) : null}
      </div>

      <textarea
        ref={areaRef}
        className="composer-input"
        value={text}
        rows={1}
        placeholder={disabled ? '连接恢复后可继续发送' : '给手机上的助手发消息，Enter 发送…'}
        disabled={disabled}
        onChange={(event) => {
          setText(event.target.value);
          const el = event.currentTarget;
          el.style.height = 'auto';
          el.style.height = `${Math.min(el.scrollHeight, 168)}px`;
        }}
        onKeyDown={onKeyDown}
        aria-label="消息输入"
      />

      <div className="composer-bar">
        <div className="left">
          <button
            type="button"
            className="round-btn"
            onClick={() => toast('附件请在手机上发送')}
            aria-label="添加附件（需在手机端）"
            title="附件请在手机上发送"
          >
            <Icon name="plus" />
          </button>
        </div>
        <div className="right">
          <span className="model-chip">
            <b>手机端模型</b>
          </span>
          {liveActive && !disabled ? (
            <button
              type="button"
              className="stop-btn"
              onClick={onStop}
              aria-label="停止生成"
              title="停止生成"
            >
              <Icon name="stop" />
            </button>
          ) : (
            <button
              type="button"
              className="send-btn"
              onClick={() => void submit()}
              disabled={disabled || busy || text.trim() === ''}
              aria-label="发送消息"
              title="发送消息"
            >
              <Icon name="arrowUp" />
            </button>
          )}
        </div>
      </div>
      {error !== '' ? <div className="composer-error">{error}</div> : null}
    </div>
  );
}
