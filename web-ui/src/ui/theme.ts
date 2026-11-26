// 主题档位（2026-10-22 视觉重做新增）：auto / light / dark 三档，cookie 记忆 + 系统偏好兜底。
// 为什么不用 localStorage：门禁钉 7 明令源码零 localStorage（口令只走 sessionStorage 同源纪律），
// 主题作为非敏感偏好走 cookie（一年期，SameSite=Lax），首帧前由 index.html 内联脚本落地，
// 避免深色用户开局白闪。
export type ThemeMode = 'auto' | 'light' | 'dark';

export type ResolvedTheme = 'light' | 'dark';

const COOKIE_NAME = 'aicontrol_theme';
const COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

function readCookie(name: string): string {
  const raw = document.cookie;
  if (raw === '') {
    return '';
  }
  for (const part of raw.split(';')) {
    const trimmed = part.trim();
    const eq = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    if (trimmed.slice(0, eq) === name) {
      return decodeURIComponent(trimmed.slice(eq + 1));
    }
  }
  return '';
}

function writeCookie(name: string, value: string): void {
  document.cookie = `${name}=${encodeURIComponent(value)}; path=/; max-age=${COOKIE_MAX_AGE}; SameSite=Lax`;
}

export function readThemeMode(): ThemeMode {
  const stored = readCookie(COOKIE_NAME);
  if (stored === 'light' || stored === 'dark' || stored === 'auto') {
    return stored;
  }
  return 'auto';
}

export function systemTheme(): ResolvedTheme {
  if (typeof window.matchMedia !== 'function') {
    return 'light';
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function resolveTheme(mode: ThemeMode): ResolvedTheme {
  return mode === 'auto' ? systemTheme() : mode;
}

// 应用到 <html data-theme>；同时更新 theme-color（移动端状态栏跟色）
export function applyTheme(mode: ThemeMode): void {
  const resolved = resolveTheme(mode);
  const root = document.documentElement;
  root.dataset.theme = resolved;
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta !== null) {
    meta.setAttribute('content', resolved === 'dark' ? '#141416' : '#F7F7F9');
  }
  writeCookie(COOKIE_NAME, mode);
}

export function nextThemeMode(mode: ThemeMode): ThemeMode {
  if (mode === 'auto') {
    return 'light';
  }
  if (mode === 'light') {
    return 'dark';
  }
  return 'auto';
}

export function themeLabel(mode: ThemeMode): string {
  if (mode === 'light') {
    return '浅色';
  }
  if (mode === 'dark') {
    return '深色';
  }
  return '跟随系统';
}
