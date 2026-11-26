// 图标集（2026-10-22 视觉重做新增）：全部内联 SVG，24×24 视框、currentColor 描边。
// 为什么不用图标库：依赖极简是门禁硬约束（scripts/assert-web-ui.mjs 钉 8 只认四项 deps），
// 十几个图标自绘即可，且能保证与项目色板/线宽一致。
import type { ReactNode } from 'react';

export type IconName =
  | 'logo'
  | 'plus'
  | 'refresh'
  | 'search'
  | 'chevronRight'
  | 'chevronDown'
  | 'copy'
  | 'check'
  | 'arrowUp'
  | 'arrowDown'
  | 'stop'
  | 'menu'
  | 'back'
  | 'terminal'
  | 'star'
  | 'spark'
  | 'monitor'
  | 'phone'
  | 'lock'
  | 'sun'
  | 'moon'
  | 'auto'
  | 'close'
  | 'sliders'
  | 'sync';

const PATHS: Record<IconName, ReactNode> = {
  logo: (
    <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5Z" />
  ),
  plus: <path d="M12 5v14M5 12h14" />,
  refresh: <path d="M21 12a9 9 0 1 1-2.64-6.36M21 3v6h-6" />,
  search: (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m20.5 20.5-4.2-4.2" />
    </>
  ),
  chevronRight: <path d="m9 18 6-6-6-6" />,
  chevronDown: <path d="m6 9 6 6 6-6" />,
  copy: (
    <>
      <rect x="9" y="9" width="12" height="12" rx="2.5" />
      <path d="M5 15H4.5A2.5 2.5 0 0 1 2 12.5v-8A2.5 2.5 0 0 1 4.5 2h8A2.5 2.5 0 0 1 15 4.5V5" />
    </>
  ),
  check: <path d="M20 6 9 17l-5-5" />,
  arrowUp: <path d="M12 19V5M5 12l7-7 7 7" />,
  arrowDown: <path d="M12 5v14M19 12l-7 7-7-7" />,
  stop: <rect x="6" y="6" width="12" height="12" rx="2.5" fill="currentColor" stroke="none" />,
  menu: <path d="M3 6h18M3 12h18M3 18h18" />,
  back: <path d="M19 12H5M12 19l-7-7 7-7" />,
  terminal: <path d="M4 17l6-6-6-6M12 19h8" />,
  star: (
    <path d="M12 3.2l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17.2l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 3.2Z" />
  ),
  spark: <path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z" />,
  monitor: (
    <>
      <rect x="2.5" y="3.5" width="19" height="13" rx="2.5" />
      <path d="M8.5 21h7M12 16.5V21" />
    </>
  ),
  phone: (
    <>
      <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
      <path d="M11 18.5h2" />
    </>
  ),
  lock: (
    <>
      <rect x="4" y="10.5" width="16" height="11" rx="2.5" />
      <path d="M8 10.5V7a4 4 0 0 1 8 0v3.5" />
    </>
  ),
  sun: (
    <>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </>
  ),
  moon: <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />,
  auto: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 3a9 9 0 0 1 0 18Z" fill="currentColor" stroke="none" />
    </>
  ),
  close: <path d="M18 6 6 18M6 6l12 12" />,
  sliders: <path d="M4 21v-6M4 11V3M12 21v-9M12 8V3M20 21v-4M20 13V3M1.5 15h5M9.5 8h5M17.5 17h5" />,
  sync: <path d="M4 12a8 8 0 0 1 13.66-5.66M20 12a8 8 0 0 1-13.66 5.66M17.5 2.5v4h-4M6.5 21.5v-4h4" />,
};

interface IconProps {
  name: IconName;
  className?: string;
  filled?: boolean;
  size?: number;
}

export function Icon({ name, className, filled = false, size }: IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size ?? 16}
      height={size ?? 16}
      fill={filled ? 'currentColor' : 'none'}
      stroke="currentColor"
      strokeWidth={1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
      focusable="false"
      style={size !== undefined ? { width: size, height: size } : undefined}
    >
      {PATHS[name]}
    </svg>
  );
}
