import { useSyncExternalStore } from 'react';
import { webClient } from './client';
import type { ClientState } from './client';

// React 读取连接快照的唯一入口（外部 store：client 内部 set 时统一通知）
export function useWebClient(): ClientState {
  return useSyncExternalStore(webClient.subscribe, webClient.getSnapshot, webClient.getSnapshot);
}
