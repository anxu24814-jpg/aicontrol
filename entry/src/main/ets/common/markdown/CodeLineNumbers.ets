/**
 * 代码行号纯函数：行数口径与行号文本生成。零 UI / 零偏好依赖；消费方 = MarkdownCodeText
 * （Markdown 代码块）、MarkdownHtmlBlockView（HTML <pre> 代码块）；工具卡 diff 的行号标签
 * 在 ChatToolDiffBlock 组件内按同类行计数自算（该件派生纯函数区禁止外引，见其头注释）。
 * ★ 行数口径与 MarkdownScrollableBlock.markdownCodeLineCount 逐字一致（空文本 0 行；尾
 * 终止符不另起一行）——后者保持自包含以满足 assert-markdown-display 的 support 机械编译
 * （函数体内不能引外部绑定），两处语义由 338 组关系钉守，改任一处必须同步另一处。
 * 行号补齐用不换行空格（\u00A0）：monospace 下每位等宽，9→10 不跳列宽；99→100 自然增一位。
 */
export function codeLineCount(text: string): number {
  if (text === '') {
    return 0;
  }
  let count: number = 1;
  for (let index: number = 0; index < text.length; index++) {
    if (text.charCodeAt(index) === 10) {
      count++;
    }
  }
  return text.charCodeAt(text.length - 1) === 10 ? count - 1 : count;
}

/** 单个行号标签：至少补到 minDigits 位（1 起）。number 非正数按 1 处理，仅防御。 */
export function codeLineNumberLabel(number: number, minDigits: number = 2): string {
  const digits: string = Math.max(1, Math.floor(number)).toString();
  const pad: number = Math.max(0, minDigits - digits.length);
  let prefix: string = '';
  for (let index: number = 0; index < pad; index++) {
    prefix += '\u00A0';
  }
  return prefix + digits;
}

/** 整块行号文本：按显示行数生成 1..N 行号，'\n' 连接；空文本返回空串。 */
export function codeLineNumberText(text: string, minDigits: number = 2): string {
  const total: number = codeLineCount(text);
  if (total <= 0) {
    return '';
  }
  const width: number = Math.max(minDigits, total.toString().length);
  const labels: string[] = [];
  for (let number: number = 1; number <= total; number++) {
    labels.push(codeLineNumberLabel(number, width));
  }
  return labels.join('\n');
}
