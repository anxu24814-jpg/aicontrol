/** 语义树到可读行内片段的纯投影，及外链与跳转准入。无 UI、网络或原文修改。 */
import { MarkdownNode } from './MarkdownSemanticModel';

export interface MarkdownInlineRun {
  id: number;
  text: string;
  bold: boolean;
  italic: boolean;
  strike: boolean;
  mark: boolean;
  code: boolean;
  script: number;
  destination: string;
  image: MarkdownNode | null;
  math: MarkdownNode | null;
  html: MarkdownNode | null;
}

// 危险字符前置检查（空串/控制字符与空格/反斜线/百分号编码的控制符或反斜线）——
// markdownSafeRemoteUrl 与 markdownLaunchTarget 共用，禁止复制两份正则。
function markdownUnsafeUrlChars(raw: string): boolean {
  return raw === '' || /[\u0000-\u0020\u007f-\u009f\\]/.test(raw) ||
    /%(?:0[0-9a-f]|1[0-9a-f]|7f|5c)/i.test(raw);
}

export function markdownSafeRemoteUrl(raw: string): string {
  if (markdownUnsafeUrlChars(raw)) {
    return '';
  }
  const match: RegExpMatchArray | null = raw.match(/^https?:\/\/([^/?#]+)(?:[/?#]|$)/i);
  if (match === null) {
    return '';
  }
  const authority: string = match[1];
  if (/[\s@%<>"'`]/.test(authority)) {
    return '';
  }
  const host: RegExpMatchArray | null = authority.startsWith('[') ?
    authority.match(/^\[([0-9a-fA-F:]+)\](?::([0-9]+))?$/) :
    authority.match(/^([^:\[\]]+)(?::([0-9]+))?$/);
  if (host === null || host[1] === '' || host[1] === '.') {
    return '';
  }
  if (host[2] !== undefined) {
    const port: number = Number(host[2]);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      return '';
    }
  }
  return raw;
}

// 消息链接跳转禁止的协议名单（决明拍板宽放行·黑名单制）：格式合法的自定义 scheme 一律
// 放行交系统匹配（装了目标应用就打开、没装由调用方提示），仅本表（本应用与系统内部能力面）
// 与 ohos* 前缀拒发；http/https 不在此表——必须先过 markdownSafeRemoteUrl 的严格判据，
// 不得经松弛分支绕过（凭据/端口/编码等检查不放松）。
const MARKDOWN_BLOCKED_SCHEMES: string[] = ['file', 'content', 'datashare', 'javascript',
  'data', 'blob', 'about'];

// 链接跳转准入（与 markdownSafeRemoteUrl 分工：后者只认 http/https，是图片加载与远程资源
// 判据；本函数额外放行黑名单外的自定义 scheme，如 bilibili:// mailto: tel:）。返回原样
// URL = 可点（调用方走 launchExternalLink→openLink），'' = 不可点、文字保留。
export function markdownLaunchTarget(raw: string): string {
  if (markdownSafeRemoteUrl(raw) !== '') {
    return raw;
  }
  if (markdownUnsafeUrlChars(raw)) {
    return '';
  }
  const match: RegExpMatchArray | null = raw.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*):(.+)$/);
  if (match === null) {
    return '';
  }
  const scheme: string = match[1].toLowerCase();
  if (scheme === 'http' || scheme === 'https') {
    return '';
  }
  if (scheme.startsWith('ohos') || MARKDOWN_BLOCKED_SCHEMES.indexOf(scheme) >= 0) {
    return '';
  }
  return raw;
}

export function markdownNodeText(node: MarkdownNode): string {
  if (node.kind === 'softBreak') {
    return ' ';
  }
  if (node.kind === 'hardBreak') {
    return '\n';
  }
  if (node.kind === 'footnoteReference') {
    return '[^' + node.label + ']';
  }
  if (node.kind === 'math' || node.kind === 'mathBlock') {
    // 语义模型不保存原定界种类，标明源码展示而不伪造另一种定界或闭合。
    return (node.closed ? '公式 ' : '未闭合公式 ') + node.text;
  }
  if (node.text !== '') {
    return node.text;
  }
  const parts: string[] = [];
  for (const child of node.children) {
    parts.push(markdownNodeText(child));
  }
  if (parts.length > 0) {
    return parts.join('');
  }
  for (const part of node.parts) {
    parts.push(part.text);
  }
  if (parts.length > 0) {
    return parts.join('');
  }
  const emptyKinds: string[] = ['text', 'code', 'image', 'paragraph', 'heading', 'tableCell',
    'listItem', 'blockquote', 'blank', 'referenceDefinition', 'codeBlock', 'htmlBlock', 'htmlInline'];
  return emptyKinds.indexOf(node.kind) >= 0 ? '' : '未能显示此内容 ' + node.kind;
}

export function markdownInlineRuns(nodes: MarkdownNode[]): MarkdownInlineRun[] {
  const result: MarkdownInlineRun[] = [];
  appendInlineRuns(nodes, false, false, false, false, false, 0, '', result);
  return result;
}

function appendInlineRuns(nodes: MarkdownNode[], bold: boolean, italic: boolean, strike: boolean,
  mark: boolean, code: boolean, script: number, destination: string, result: MarkdownInlineRun[]): void {
  for (const node of nodes) {
    const nextBold: boolean = bold || node.kind === 'strong';
    const nextItalic: boolean = italic || node.kind === 'emphasis';
    const nextStrike: boolean = strike || node.kind === 'strikethrough';
    const nextMark: boolean = mark || node.kind === 'highlight';
    const nextCode: boolean = code || node.kind === 'code' || node.kind === 'math' || node.kind === 'htmlInline';
    const nextScript: number = node.kind === 'subscript' ? -1 : (node.kind === 'superscript' ? 1 : script);
    const nextDestination: string = node.kind === 'link' ? node.destination : destination;
    if (node.children.length > 0 && node.kind !== 'image') {
      appendInlineRuns(node.children, nextBold, nextItalic, nextStrike, nextMark, nextCode, nextScript,
        nextDestination, result);
    } else {
      result.push({ id: node.id, text: node.kind === 'footnoteReference' ? '[' + node.startNumber.toString() + ']' :
        markdownNodeText(node), bold: nextBold,
        italic: nextItalic, strike: nextStrike, mark: nextMark, code: nextCode,
        script: node.kind === 'footnoteReference' ? 1 : nextScript,
        destination: node.kind === 'footnoteReference' ? 'reference:' + node.id.toString() : nextDestination,
        image: node.kind === 'image' ? node : null,
        math: node.kind === 'math' ? node : null,
        html: node.kind === 'htmlInline' ? node : null });
    }
  }
}
