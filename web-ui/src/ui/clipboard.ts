// 复制到剪贴板（2026-10-22 视觉重做新增）。
// 局域网是 http（非安全上下文），navigator.clipboard 在多数浏览器不可用，故必须带
// execCommand 兜底——否则手机上「复制代码」会静默失败。
export async function copyText(text: string): Promise<boolean> {
  if (text === '') {
    return false;
  }
  try {
    if (typeof navigator !== 'undefined' && navigator.clipboard !== undefined
      && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // 落到 execCommand 兜底
  }
  try {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', 'readonly');
    area.style.position = 'fixed';
    area.style.top = '-1000px';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    area.setSelectionRange(0, text.length);
    const ok = document.execCommand('copy');
    document.body.removeChild(area);
    return ok;
  } catch {
    return false;
  }
}
