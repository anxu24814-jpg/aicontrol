// 极简 history 路由（/ 与 /c/:id 两面）。
// 为什么不用 react-router：依赖极简（总案 §6 裁定），两面路由用 pushState + popstate 足够。
// 为什么是 history 而非 hash：亲读 TcpHttpStaticCarrier.ets——静态面对未命中路径统一
// fallback 到 rawfile/webui/index.html，深链 /c/:id 可直接打开；index.html 的
// <base href="/"> 保证嵌套路径下 ./assets 引用仍锚回站点根。
import { useEffect, useState } from 'react';

export type Route =
  | { kind: 'list' }
  | { kind: 'chat'; id: string };

export function parseRoute(pathname: string): Route {
  const match = /^\/c\/([^/]+)\/?$/.exec(pathname);
  if (match !== null) {
    try {
      return { kind: 'chat', id: decodeURIComponent(match[1]) };
    } catch {
      return { kind: 'list' };
    }
  }
  return { kind: 'list' };
}

export function useRoute(): Route {
  const [route, setRoute] = useState<Route>(() => parseRoute(window.location.pathname));
  useEffect(() => {
    const onPop = (): void => {
      setRoute(parseRoute(window.location.pathname));
    };
    window.addEventListener('popstate', onPop);
    return (): void => {
      window.removeEventListener('popstate', onPop);
    };
  }, []);
  return route;
}

export function navigate(path: string): void {
  if (window.location.pathname === path) {
    return;
  }
  window.history.pushState({}, '', path);
  // 手动派发，让 useRoute 在同一渲染循环内更新（pushState 自身不触发 popstate）
  window.dispatchEvent(new PopStateEvent('popstate'));
}
