/**
 * 预览只接受白名单重建的 HTML / 受限 Mermaid 数据 / 专用准入重建的 SVG（U5 起），不把原文
 * 拼进可执行壳。唯一例外（U8a）：用户显式开启「HTML 预览运行脚本」时，输入 HTML 的脚本元素
 * 正文原样入壳（属性照剥 + `</script` 转义，见 markdownPreviewHtml 的 allowScripts 参数），
 * 壳 CSP 仅放宽 script-src，其余指令、导航拦截、权限拒绝与无桥不变量全不变。
 * 限制超界明确退回源码，不截半份内容冒充完整预览。
 */
import { MarkdownDocumentToken } from './MarkdownDocumentModel';
import { MarkdownNode } from './MarkdownSemanticModel';
import { decodeMarkdownEntities } from './MarkdownEntities';

export const MARKDOWN_PREVIEW_ORIGIN: string = 'https://markdown-preview.invalid';
export const MARKDOWN_PREVIEW_RUNNER_URL: string = MARKDOWN_PREVIEW_ORIGIN + '/mermaid.html';
export const MARKDOWN_PREVIEW_SCRIPT_URL: string = MARKDOWN_PREVIEW_ORIGIN + '/mermaid.min.js';
export const MARKDOWN_PREVIEW_RUNNER_FILE: string = 'markdown-preview/mermaid.html';
export const MARKDOWN_PREVIEW_SCRIPT_FILE: string = 'markdown-preview/mermaid.min.js';
export const MARKDOWN_PREVIEW_SOURCE_PAGE: number = 4096;
export const MARKDOWN_PREVIEW_INPUT_LIMIT: number = 65536;
export const MARKDOWN_PREVIEW_MERMAID_LIMIT: number = 16384;
export const MARKDOWN_PREVIEW_HTML_CSP: string = "default-src 'none'; script-src 'none'; " +
  "style-src 'unsafe-inline'; img-src 'none'; font-src 'none'; connect-src 'none'; " +
  "media-src 'none'; object-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; " +
  "base-uri 'none'; form-action 'none'";
// 开态 CSP（仅偏好开关开启时使用）：相对关态只放宽 script-src 为 'unsafe-inline'（放行内联
// 脚本，外链仍被剥属性 + 拦截），其余指令恒 'none'——脚本即便执行也取不到网络与本地资源，
// 与组件侧 blockNetwork(true) 构成双保险。由关态常量派生，防两串指令集漂移。
export const MARKDOWN_PREVIEW_HTML_CSP_SCRIPTS: string =
  MARKDOWN_PREVIEW_HTML_CSP.replace("script-src 'none'", "script-src 'unsafe-inline'");

// details/summary（U8b）：标签与内容都保留，折叠交互由 WebView 原生承担（零原生码）；
// open 属性照「属性不透传」口径不重建，详情一律从收起态起。
const SAFE_TAGS: string[] = ['p', 'div', 'span', 'br', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'strong', 'b', 'em', 'i', 'u', 's', 'del', 'small', 'mark', 'sub', 'sup', 'pre', 'code',
  'blockquote', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'thead', 'tbody', 'tfoot', 'tr',
  'th', 'td', 'caption', 'section', 'article', 'header', 'footer', 'main', 'figure', 'figcaption',
  'details', 'summary', 'a'];
const VOID_TAGS: string[] = ['br', 'hr'];
const OMIT_CONTENT_TAGS: string[] = ['script', 'style', 'title', 'iframe', 'object', 'embed',
  'svg', 'math', 'template', 'noscript', 'textarea', 'xmp', 'plaintext', 'audio', 'video'];
const PREVIEW_DEPTH_LIMIT: number = 64;
const PREVIEW_TAG_LIMIT: number = 4096;

export interface MarkdownPreviewDocument {
  html: string;
  error: string;
  removed: boolean;
}

export interface MarkdownPreviewTitle {
  status: string;
  message: string;
}

interface PreviewTag {
  name: string;
  closing: boolean;
  attributes: string;
}

/** 矢量预览语言判定（U5）：codeBlock 且语言标记为 svg/xml——```svg 直认、```xml 走验根元素
 *  为 svg。偏好开关与装配分支共用本判定，语言集合单源；本件不引 AppPreferences，保持 Node
 *  直跑面零 AppStorage 依赖。 */
export function markdownPreviewSvgLanguage(node: MarkdownNode): boolean {
  if (node.kind !== 'codeBlock') { return false; }
  const language: string = node.language.trim().toLowerCase();
  return language === 'svg' || language === 'xml';
}

export function markdownPreviewSupported(node: MarkdownNode): boolean {
  if (node.kind === 'htmlBlock' || node.kind === 'htmlInline') { return true; }
  if (node.kind !== 'codeBlock') { return false; }
  const language: string = node.language.trim().toLowerCase();
  if (language === 'mermaid') { return true; }
  // ```svg / ```xml（U5）：未闭合不判支持（流式在途无预览入口，闭合后一次评估免每拍重扫）；
  // 闭合后过准入校验，失败判不支持 → 无预览入口，块照常按代码块显示（零静默错渲染）。
  if (markdownPreviewSvgLanguage(node)) {
    return node.closed === true && markdownPreviewSvgError(node.text, true) === '';
  }
  return false;
}

/** 受限预览键在场判定（U5-R3b 拒因可见化）：准入失败的闭合 svg/xml 围栏也在场——旧口径下
 *  整份静默无键，用户以为功能没做。键点击时先问 markdownPreviewSvgError，非空弹具体拒因
 *  提示（UIContext toast），空才挂预览宿主；未闭合仍无键。其余语言面复用 markdownPreviewSupported。 */
export function markdownPreviewVisible(node: MarkdownNode): boolean {
  if (markdownPreviewSvgLanguage(node)) { return node.closed === true; }
  return markdownPreviewSupported(node);
}

export function markdownPreviewIdentity(token: MarkdownDocumentToken, node: MarkdownNode): string {
  return token.documentId.length.toString() + ':' + token.documentId + ':' + token.generation.toString() +
    ':' + token.revision.toString() + ':' + node.id.toString() + ':' + node.kind;
}

export function markdownPreviewEscape(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** 脚本正文端点（U8a）：大小写不敏感的 `</script` 后接定界符（空白/斜杠/大于号/文末）才是
 * 闭合候选——与浏览器脚本数据态终止序列同口径（定界符集是规范超集：早切不会漏切）；其余
 * 前缀形态（如 `</scriptx`）仍属正文。返回候选下标，无候选返回 -1。 */
function scriptCloseIndex(source: string, from: number): number {
  const match: RegExpExecArray | null = /<\/script(?=[\s\/>]|$)/i.exec(source.substring(from));
  return match === null ? -1 : from + match.index;
}

/** 脚本正文入壳前转义（U8a）：正文内残留的 `</script` 改写为 `<\/script`（JS 字符串与正则里
 * `\/` 与 `/` 等价，脚本语义不变），截断序列无法提前闭合元素把后段标记排出；大小写不敏感。 */
function escapeScriptContent(content: string): string {
  return content.replace(/<\/(script)/gi, '<\\/$1');
}

function tagEnd(source: string, start: number): number {
  let quote: string = '';
  for (let cursor: number = start + 1; cursor < source.length; cursor++) {
    const character: string = source.charAt(cursor);
    if (quote !== '') {
      if (character === quote) { quote = ''; }
    } else if (character === '"' || character === "'") { quote = character; }
    else if (character === '>') { return cursor; }
  }
  return -1;
}

function parseTag(text: string): PreviewTag | null {
  const match: RegExpExecArray | null = /^\s*(\/?)\s*([a-zA-Z][a-zA-Z0-9]*)([\s\S]*)$/.exec(text);
  if (match === null || (match[3] !== '' && !/^[\s/]/.test(match[3]))) { return null; }
  return { name: match[2].toLowerCase(), closing: match[1] === '/', attributes: match[3] };
}

/** 属性不透传。只重新生成离散对齐/方向和有界的表格跨格、列表起点。 */
function safeAttributes(tag: PreviewTag): string {
  const attributes: string[] = [];
  const seen: Set<string> = new Set<string>();
  const pattern: RegExp = /([^\s=<>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  let match: RegExpExecArray | null = pattern.exec(tag.attributes);
  while (match !== null) {
    const name: string = match[1].toLowerCase();
    const value: string = (match[2] ?? match[3] ?? match[4] ?? '').toLowerCase();
    if (!seen.has(name)) {
      seen.add(name);
      if (name === 'dir' && ['ltr', 'rtl', 'auto'].includes(value)) {
        attributes.push(' dir="' + value + '"');
      } else if (name === 'align' && ['left', 'right', 'center', 'justify'].includes(value)) {
        attributes.push(' align="' + value + '"');
      } else if ((name === 'colspan' || name === 'rowspan') && (tag.name === 'td' || tag.name === 'th') &&
        /^[1-9][0-9]?$/.test(value)) {
        attributes.push(' ' + name + '="' + value + '"');
      } else if (name === 'start' && tag.name === 'ol' && /^-?[0-9]{1,6}$/.test(value)) {
        attributes.push(' start="' + value + '"');
      }
    }
    match = pattern.exec(tag.attributes);
  }
  return attributes.join('');
}

function failedHtml(message: string): MarkdownPreviewDocument {
  return { html: '', error: message, removed: true };
}

export function markdownPreviewHtml(source: string, darkMode: boolean, session: string,
  allowScripts: boolean = false): MarkdownPreviewDocument {
  if (source.length > MARKDOWN_PREVIEW_INPUT_LIMIT) {
    return failedHtml('内容超过受限预览上限，请阅读源码');
  }
  const pieces: string[] = [];
  const opened: string[] = [];
  let skipName: string = '';
  let cursor: number = 0;
  let tags: number = 0;
  let removed: boolean = false;
  while (cursor < source.length) {
    const next: number = source.indexOf('<', cursor);
    if (next < 0) {
      if (skipName === '') { pieces.push(markdownPreviewEscape(decodeMarkdownEntities(source.substring(cursor)))); }
      break;
    }
    if (skipName === '') { pieces.push(markdownPreviewEscape(decodeMarkdownEntities(source.substring(cursor, next)))); }
    if (source.startsWith('<!--', next)) {
      const commentEnd: number = source.indexOf('-->', next + 4);
      cursor = commentEnd < 0 ? source.length : commentEnd + 3;
      removed = true;
      continue;
    }
    const end: number = tagEnd(source, next);
    if (end < 0) {
      if (skipName === '') { pieces.push(markdownPreviewEscape(source.substring(next))); }
      break;
    }
    const rawTag: string = source.substring(next + 1, end);
    const tag: PreviewTag | null = parseTag(rawTag);
    cursor = end + 1;
    if (++tags > PREVIEW_TAG_LIMIT) { return failedHtml('标签数量超过受限预览上限，请阅读源码'); }
    if (tag === null) {
      if (skipName === '') { pieces.push(markdownPreviewEscape('<' + rawTag + '>')); }
      removed = true;
      continue;
    }
    if (skipName !== '') {
      if (tag.closing && tag.name === skipName) { skipName = ''; }
      continue;
    }
    if (OMIT_CONTENT_TAGS.includes(tag.name)) {
      // 脚本开关开（U8a）：只有 script 元素豁免剥离，正文原子入壳；其余省略标签与关态路径逐字不变。
      if (allowScripts && tag.name === 'script' && !tag.closing) {
        if (/\/\s*$/.test(tag.attributes)) {
          // 自闭合形态无正文；src 等属性照剥，等价空脚本元素（外链不可能装载）。
          pieces.push('<script></script>');
        } else {
          const closeAt: number = scriptCloseIndex(source, cursor);
          const bodyEnd: number = closeAt < 0 ? source.length : closeAt;
          const content: string = source.substring(cursor, bodyEnd);
          const escaped: string = escapeScriptContent(content);
          // 未找到闭合候选时正文到文末并补写闭合标签：脚本数据态未收口会吞掉壳尾。
          pieces.push('<script>' + escaped + '</script>');
          if (escaped !== content) { removed = true; }
          if (closeAt < 0) { cursor = source.length; }
          else {
            const closeEnd: number = source.indexOf('>', closeAt);
            cursor = closeEnd < 0 ? source.length : closeEnd + 1;
          }
        }
        if (tag.attributes.trim() !== '') { removed = true; }
        continue;
      }
      if (!tag.closing && !/\/\s*$/.test(tag.attributes)) { skipName = tag.name; }
      removed = true;
      continue;
    }
    if (!SAFE_TAGS.includes(tag.name)) { removed = true; continue; }
    if (tag.closing) {
      const target: number = opened.lastIndexOf(tag.name);
      if (target < 0) { removed = true; continue; }
      while (opened.length > target) { pieces.push('</' + opened.pop()! + '>'); }
    } else {
      const attributes: string = safeAttributes(tag);
      // 任何属性均重新生成，链接标签仅保留文字与结构，不再具有导航能力。
      if (tag.attributes.trim() !== '') { removed = true; }
      pieces.push('<' + tag.name + attributes + '>');
      if (!VOID_TAGS.includes(tag.name)) {
        if (opened.length >= PREVIEW_DEPTH_LIMIT) { return failedHtml('标签嵌套超过受限预览上限，请阅读源码'); }
        opened.push(tag.name);
      }
    }
  }
  while (opened.length > 0) { pieces.push('</' + opened.pop()! + '>'); }
  const body: string = pieces.join('');
  // 无可见文本或分隔线时显示明确空态，不报空白成功。
  const hasContent: boolean = body.includes('<hr>') || body.replace(/<[^>]*>/g, '').trim() !== '';
  const foreground: string = darkMode ? '#f1f1f1' : '#202124';
  const background: string = darkMode ? '#161616' : '#ffffff';
  const shell: string = '<!doctype html><html><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<meta http-equiv="Content-Security-Policy" content="' +
    markdownPreviewEscape(allowScripts ? MARKDOWN_PREVIEW_HTML_CSP_SCRIPTS : MARKDOWN_PREVIEW_HTML_CSP) + '">' +
    '<title>' + markdownPreviewEscape('md-preview:' + session + ':html') + '</title>' +
    '<style>html{color-scheme:' + (darkMode ? 'dark' : 'light') + '}body{margin:16px;color:' + foreground +
    ';background:' + background + ';font:16px/1.5 sans-serif;overflow-wrap:anywhere}' +
    'pre{white-space:pre-wrap}table{border-collapse:collapse;max-width:100%}td,th{border:1px solid #888;padding:6px}' +
    'img,iframe,object,embed,form,input,button{display:none}</style></head><body>' +
    (hasContent ? body : '<p>没有可安全展示的内容，请阅读源码。</p>') + '</body></html>';
  return { html: shell, error: '', removed: removed };
}

// ── SVG 内联预览准入（U5 / 需求 R3）──
// 路线 = 受限 Web 壳复用（安全壳零改动）：```svg 直认、```xml 验根元素为 svg。本段为专用
// XML 事件流轻量扫描器，**刻意不复用 HTML 的 SAFE_TAGS 白名单**（在 OMIT_CONTENT_TAGS 放开
// svg 等于给全体 HTML 预览扩攻击面）。准入 = 根元素 svg + 命名空间（缺 xmlns 补默认）+ 标签/
// 属性白名单 + 拒 DOCTYPE/ENTITY/foreignObject/script/style/外链 + SMIL 剥离 + 字节与边长
// 双上限；失败回退纯代码块，零静默错渲染。双保险 = 本扫描器剥可执行面 + 壳 blockNetwork/
// 零桥/CSP script-src 'none'。输出为归一重建 SVG（前缀抹平、属性重排、值重新转义），非原文透传。
export const MARKDOWN_PREVIEW_SVG_LIMIT: number = 65536;
export const MARKDOWN_PREVIEW_SVG_EDGE_LIMIT: number = 2048;
const SVG_NAMESPACE: string = 'http://www.w3.org/2000/svg';
// 标签白名单（保守静态绘图子集，XML 大小写敏感逐字比对）：违规标签整份拒。script / style /
// foreignObject / image / a / animateMotion 等有源标签刻意不在列——进白名单即开放对应通道。
// use（U5-R3b）只放行内部片段引用，走下方 href 值级门。
const SVG_TAGS: string[] = ['svg', 'g', 'defs', 'symbol', 'switch', 'title', 'desc', 'use',
  'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'path', 'text', 'tspan',
  'linearGradient', 'radialGradient', 'stop', 'pattern', 'clipPath', 'mask', 'marker', 'filter',
  'feGaussianBlur', 'feOffset', 'feBlend', 'feColorMatrix', 'feComposite', 'feFlood',
  'feDropShadow', 'feMerge', 'feMergeNode', 'feMorphology'];
// 子树剥离表（元素与内容整体移除、其余图形照常预览，单点可调）：①SMIL 时序元素（保守假设 =
// 静态预览语义，待拍板项；要动画时移除本表即放行）；②metadata（U5-R3b，无渲染语义的生成面
// 元数据容器）。不在本表的其他动画类标签（set / animateMotion）不在白名单 → 整份拒、回退代码块。
const SVG_STRIP_TAGS: string[] = ['animate', 'animateTransform', 'metadata'];
// 剥离属性表（U5-R3b）：class / data-* 与 role / aria-*（WAI-ARIA 读屏元数据，零渲染零
// 执行语义）等无意义生成面标记，丢弃后放行（不会透传；整份拒会让带标记图形无法预览）。
// style 属性与 style 标签刻意不在放宽面（安全面待拍板）。
function svgStrippedAttribute(name: string): boolean {
  const local: string = svgLocalName(name);
  return local === 'class' || local === 'role' ||
    local.startsWith('data-') || local.startsWith('aria-');
}
// 属性白名单（XML 大小写敏感逐字比对）：id 供内部 url(#id) 片段引用；on* / style 等不在列，
// 属性名不在白名单即整份拒（class 与 data-* 先经剥离表丢弃；use 的 href / xlink:href 走值级门）。
const SVG_ATTRIBUTES: string[] = ['id', 'version', 'baseProfile',
  'x', 'y', 'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'fx', 'fy', 'fr',
  'width', 'height', 'd', 'points', 'dx', 'dy', 'rotate', 'transform', 'viewBox',
  'preserveAspectRatio', 'pathLength', 'textLength', 'lengthAdjust', 'startOffset',
  'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity',
  'stroke-linecap', 'stroke-linejoin', 'stroke-dasharray', 'stroke-dashoffset',
  'stroke-miterlimit', 'opacity', 'color', 'display', 'visibility',
  'font-family', 'font-size', 'font-size-adjust', 'font-weight', 'font-style', 'font-variant',
  'font-stretch', 'letter-spacing', 'word-spacing', 'text-anchor', 'dominant-baseline',
  'alignment-baseline', 'baseline-shift', 'direction', 'unicode-bidi', 'writing-mode',
  'glyph-orientation-horizontal', 'glyph-orientation-vertical', 'paint-order',
  'shape-rendering', 'color-interpolation', 'color-interpolation-filters', 'color-rendering',
  'image-rendering', 'text-rendering', 'vector-effect', 'clip-path', 'clip-rule', 'mask',
  'filter', 'marker-start', 'marker-mid', 'marker-end',
  'stop-color', 'stop-opacity', 'offset', 'gradientUnits', 'gradientTransform', 'spreadMethod',
  'patternUnits', 'patternContentUnits', 'patternTransform', 'clipPathUnits',
  'maskUnits', 'maskContentUnits', 'filterUnits', 'primitiveUnits',
  'markerWidth', 'markerHeight', 'markerUnits', 'refX', 'refY', 'orient',
  'stdDeviation', 'in', 'in2', 'result', 'mode', 'values', 'tableValues', 'slope', 'intercept',
  'amplitude', 'exponent', 'operator', 'k1', 'k2', 'k3', 'k4', 'radius', 'type',
  'flood-color', 'flood-opacity'];

interface SvgAttribute {
  name: string;
  value: string;
}

interface SvgToken {
  raw: string;
  closing: boolean;
  selfClosed: boolean;
  attributes: SvgAttribute[];
  end: number;
}

interface SvgFrame {
  name: string;
  stripped: boolean;
}

interface SvgPreviewContent {
  svg: string;
  stripped: boolean;
  reason: string;
}

/** 拒因通道（U5-R3b）：扫描器在首处失败点写入可读原因，UI 只消费 markdownPreviewSvgError
 *  的返回值、不重判校验。空串 = 未失败。 */
interface SvgReason {
  text: string;
}

function svgLocalName(name: string): string {
  const at: number = name.lastIndexOf(':');
  return at < 0 ? name : name.substring(at + 1);
}

function svgNameEnd(source: string, start: number): number {
  let cursor: number = start;
  while (cursor < source.length) {
    const character: string = source.charAt(cursor);
    const isName: boolean = (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') ||
      character === ':' || character === '_' || character === '-' || character === '.';
    if (!isName) { break; }
    cursor++;
  }
  return cursor;
}

/** 单标签事件流扫描（自写，宽度 = 一个标签）：具名开/闭/自闭合 + 引号感知属性表；
 *  畸形（未收口 / 无引号值 / 非法名字）返回 null → 整份拒。 */
function svgReadTag(source: string, at: number): SvgToken | null {
  let cursor: number = at + 1;
  let closing: boolean = false;
  if (source.charAt(cursor) === '/') { closing = true; cursor++; }
  const nameEnd: number = svgNameEnd(source, cursor);
  if (nameEnd === cursor) { return null; }
  const raw: string = source.substring(cursor, nameEnd);
  cursor = nameEnd;
  const attributes: SvgAttribute[] = [];
  let selfClosed: boolean = false;
  while (cursor < source.length) {
    while (cursor < source.length && /\s/.test(source.charAt(cursor))) { cursor++; }
    const character: string = source.charAt(cursor);
    if (character === '') { return null; }
    if (character === '>') {
      return { raw: raw, closing: closing, selfClosed: selfClosed, attributes: attributes, end: cursor + 1 };
    }
    if (character === '/') {
      let probe: number = cursor + 1;
      while (probe < source.length && /\s/.test(source.charAt(probe))) { probe++; }
      if (source.charAt(probe) !== '>') { return null; }
      selfClosed = true;
      cursor = probe;
      continue;
    }
    if (closing) { return null; }
    const attributeEnd: number = svgNameEnd(source, cursor);
    if (attributeEnd === cursor) { return null; }
    const name: string = source.substring(cursor, attributeEnd);
    cursor = attributeEnd;
    while (cursor < source.length && /\s/.test(source.charAt(cursor))) { cursor++; }
    let value: string = '';
    if (source.charAt(cursor) === '=') {
      cursor++;
      while (cursor < source.length && /\s/.test(source.charAt(cursor))) { cursor++; }
      const quote: string = source.charAt(cursor);
      if (quote !== '"' && quote !== "'") { return null; }
      const close: number = source.indexOf(quote, cursor + 1);
      if (close < 0) { return null; }
      value = source.substring(cursor + 1, close);
      cursor = close + 1;
    }
    attributes.push({ name: name, value: value });
  }
  return null;
}

/** 属性白名单 + 值级防外链：javascript: 与裸 `<` 一律拒；url() 只放行内部片段引用
 *  url(#id)（照 use href="#id" 先例——渐变/图案/遮罩/滤镜据此可达），其余形态一律拒；值
 *  重新转义（`"` → &quot;）后回写。root = 根元素时附尺寸上限（viewBox 四数齐备且边长
 *  ≤2048、显式宽高首数 ≤2048，防超大画布；百分比与非数值照 XML 无效值口径放行）。
 *  tag = 所属元素名（use 的 href 值级门与 xlink: 前缀抹平在此收口）；reason = 拒因通道。 */
function svgAttributeText(attribute: SvgAttribute, root: boolean, tag: string,
  reason: SvgReason): string | null {
  const name: string = svgLocalName(attribute.name);
  const value: string = attribute.value;
  // use 引用面（U5-R3b）：href / xlink:href 只放行内部片段引用（# 开头 id），输出统一抹前缀为
  // href（xmlns:xlink 声明本就被丢弃，保留前缀会造未声明命名空间）；外链、data: 一律拒。
  if (name === 'href') {
    if (tag === 'use' && /^#[A-Za-z_][A-Za-z0-9_.:-]*$/.test(value)) { return 'href="' + value + '"'; }
    reason.text = '受限预览不支持 ' + attribute.name + ' 的引用';
    return null;
  }
  // xml:space（U5-R3b）：生成面常见空白处理声明，无执行面；preserve/default 两态归一保留。
  if (attribute.name === 'xml:space') {
    if (value === 'preserve' || value === 'default') { return 'xml:space="' + value + '"'; }
    reason.text = '受限预览不支持 xml:space 的取值';
    return null;
  }
  if (!SVG_ATTRIBUTES.includes(name)) {
    reason.text = '受限预览不支持属性 ' + attribute.name;
    return null;
  }
  if (/javascript:/i.test(value) || value.indexOf('<') >= 0) {
    reason.text = '受限预览不支持 ' + attribute.name + ' 的取值';
    return null;
  }
  // url() 引用面：只放行内部片段引用 url(#id)（照 use href="#id" 先例，引用目标限同文档
  // 白名单元素，无网络无执行语义）；其余形态（外链、data:、相对路径、带引号/空白写法）一律
  // 拒——剥离全部合法内部引用后残留 url( 即拒。两正则同步容忍空白（R1 修复）：CSS 允许 url
  // 与括号间及括号内空白，旧写法两头不匹配即旁路放行，现两头均认空白。
  if (/url\s*\(/i.test(value.replace(/url\s*\(\s*#[A-Za-z_][A-Za-z0-9_.:-]*\s*\)/ig, ''))) {
    reason.text = '受限预览不支持 ' + attribute.name + ' 里的外部引用';
    return null;
  }
  if (root && name === 'viewBox') {
    const tokens: string[] = value.trim().split(/[\s,]+/);
    if (tokens.length !== 4) { reason.text = 'SVG 画布尺寸不合规'; return null; }
    for (let index: number = 0; index < 4; index++) {
      if (Number.isNaN(Number(tokens[index]))) { reason.text = 'SVG 画布尺寸不合规'; return null; }
    }
    const boxWidth: number = Number(tokens[2]);
    const boxHeight: number = Number(tokens[3]);
    if (boxWidth <= 0 || boxHeight <= 0 ||
      boxWidth > MARKDOWN_PREVIEW_SVG_EDGE_LIMIT || boxHeight > MARKDOWN_PREVIEW_SVG_EDGE_LIMIT) {
      reason.text = 'SVG 画布尺寸超出受限预览上限';
      return null;
    }
  }
  if (root && (name === 'width' || name === 'height')) {
    const match: RegExpExecArray | null = /^\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/.exec(value);
    if (match !== null && Number(match[1]) > MARKDOWN_PREVIEW_SVG_EDGE_LIMIT) {
      reason.text = 'SVG 画布尺寸超出受限预览上限';
      return null;
    }
  }
  return name + '="' + value.replace(/"/g, '&quot;') + '"';
}

/** 根元素属性：前缀根须显式绑定 SVG 命名空间（xmlns:前缀）；缺默认 xmlns 补默认（归一重建，
 * 前缀抹平，输出恒为无前缀 <svg xmlns=...>）。 */
function svgRootAttributes(token: SvgToken, reason: SvgReason): string | null {
  const at: number = token.raw.lastIndexOf(':');
  const prefix: string = at < 0 ? '' : token.raw.substring(0, at);
  let defaultDeclared: boolean = false;
  let prefixDeclared: boolean = false;
  const pieces: string[] = [];
  for (let index: number = 0; index < token.attributes.length; index++) {
    const attribute: SvgAttribute = token.attributes[index];
    if (svgStrippedAttribute(attribute.name)) { continue; }
    if (attribute.name === 'xmlns') {
      if (attribute.value !== SVG_NAMESPACE) {
        reason.text = 'SVG 命名空间不是标准 SVG 命名空间';
        return null;
      }
      defaultDeclared = true;
      continue;
    }
    if (attribute.name.startsWith('xmlns:')) {
      // 其他前缀声明（如 xmlns:xlink）丢弃：href 引用面只放行内部片段引用，无外链残留
      if (attribute.name.substring(6) === prefix) {
        if (attribute.value !== SVG_NAMESPACE) {
          reason.text = 'SVG 命名空间不是标准 SVG 命名空间';
          return null;
        }
        prefixDeclared = true;
      }
      continue;
    }
    const text: string | null = svgAttributeText(attribute, true, 'svg', reason);
    if (text === null) { return null; }
    pieces.push(text);
  }
  if (prefix !== '' && !prefixDeclared) {
    reason.text = 'SVG 前缀元素未声明对应命名空间';
    return null;
  }
  if (!defaultDeclared) { pieces.unshift('xmlns="' + SVG_NAMESPACE + '"'); }
  return pieces.length === 0 ? '' : ' ' + pieces.join(' ');
}

function svgElementAttributes(token: SvgToken, reason: SvgReason): string | null {
  const tag: string = svgLocalName(token.raw);
  const pieces: string[] = [];
  for (let index: number = 0; index < token.attributes.length; index++) {
    const attribute: SvgAttribute = token.attributes[index];
    if (svgStrippedAttribute(attribute.name)) { continue; }
    if (attribute.name === 'xmlns' || attribute.name.startsWith('xmlns:')) { continue; }
    const text: string | null = svgAttributeText(attribute, false, tag, reason);
    if (text === null) { return null; }
    pieces.push(text);
  }
  return pieces.length === 0 ? '' : ' ' + pieces.join(' ');
}

class SvgPreviewScanner {
  private readonly source: string;
  private cursor: number = 0;
  private tags: number = 0;
  private rootSeen: boolean = false;
  private rootClosed: boolean = false;
  private stripDepth: number = 0;
  private stripped: boolean = false;
  private readonly reason: SvgReason = { text: '' };
  private readonly stack: SvgFrame[] = [];
  private readonly pieces: string[] = [];

  constructor(source: string) { this.source = source; }

  /** 拒因收口（U5-R3b）：首处失败点最接近用户要修的问题，后续失败不改写先到原因。 */
  private reject(reason: string): SvgPreviewContent {
    if (this.reason.text === '') { this.reason.text = reason; }
    return { svg: '', stripped: false, reason: this.reason.text };
  }

  /** 单遍扫描重建：返回重建片段（'' = 拒，消费方回退纯代码块）、剥离标记与拒因。 */
  run(): SvgPreviewContent {
    if (this.source.trim() === '') { return this.reject('SVG 源码为空'); }
    if (this.source.length > MARKDOWN_PREVIEW_SVG_LIMIT) { return this.reject('SVG 超出受限预览上限'); }
    while (this.cursor < this.source.length) {
      const next: number = this.source.indexOf('<', this.cursor);
      const text: string = next < 0 ? this.source.substring(this.cursor) :
        this.source.substring(this.cursor, next);
      if (text !== '') {
        if (this.rootSeen && !this.rootClosed) {
          if (this.stripDepth === 0) { this.pieces.push(text); }
        } else if (text.trim() !== '') {
          return this.reject('SVG 根元素外含文本');  // 根元素外非空白文本（XML 不允许）
        }
      }
      if (next < 0) { break; }
      this.cursor = next;
      if (this.source.startsWith('<!--', this.cursor)) {
        const end: number = this.source.indexOf('-->', this.cursor + 4);
        if (end < 0) { return this.reject('SVG 注释未收口'); }
        this.cursor = end + 3;
        continue;
      }
      const marker: string = this.source.charAt(this.cursor + 1);
      // DOCTYPE / ENTITY / CDATA / 条件注释一律拒（实体展开与外部 DTD 面全关）
      if (marker === '!') { return this.reject('SVG 含 DOCTYPE 或实体声明'); }
      if (marker === '?') {
        // 声明与处理指令仅在跳过面（不入输出）：xml 声明、PI 无执行通道
        const end: number = this.source.indexOf('?>', this.cursor + 2);
        if (end < 0) { return this.reject('SVG 处理指令未收口'); }
        this.cursor = end + 2;
        continue;
      }
      const token: SvgToken | null = svgReadTag(this.source, this.cursor);
      if (token === null) { return this.reject('SVG 标签写法不合规'); }
      this.cursor = token.end;
      if (++this.tags > PREVIEW_TAG_LIMIT) { return this.reject('SVG 标签数量超出受限预览上限'); }
      if (!this.step(token)) { return this.reject('SVG 结构不合规'); }
    }
    if (!this.rootSeen) { return this.reject('SVG 根元素不是 svg'); }
    if (!this.rootClosed || this.stack.length !== 0) { return this.reject('SVG 根元素未闭合'); }
    return { svg: this.pieces.join(''), stripped: this.stripped, reason: '' };
  }

  private step(token: SvgToken): boolean {
    const name: string = svgLocalName(token.raw);
    if (token.closing) {
      if (this.stack.length === 0 || this.stack[this.stack.length - 1].name !== name) {
        this.reason.text = 'SVG 标签配对不合规';
        return false;
      }
      const frame: SvgFrame = this.stack.pop()!;
      if (frame.stripped) { this.stripDepth--; }
      else { this.pieces.push('</' + name + '>'); }
      if (this.stack.length === 0) { this.rootClosed = true; }
      return true;
    }
    if (this.stack.length === 0) {
      if (this.rootSeen || name !== 'svg') {
        this.reason.text = 'SVG 根元素不是 svg';
        return false;
      }
      const attributes: string | null = svgRootAttributes(token, this.reason);
      if (attributes === null) { return false; }
      this.rootSeen = true;
      if (token.selfClosed) {
        this.rootClosed = true;
        this.pieces.push('<svg' + attributes + '/>');
        return true;
      }
      this.pieces.push('<svg' + attributes + '>');
      this.stack.push({ name: name, stripped: false });
      return true;
    }
    // 剥离面（SMIL 时序元素、metadata 或其子树）：整段丢弃，不校验、不入输出
    if (this.stripDepth > 0 || SVG_STRIP_TAGS.includes(name)) {
      if (SVG_STRIP_TAGS.includes(name)) { this.stripped = true; }
      if (!token.selfClosed) {
        if (this.stack.length >= PREVIEW_DEPTH_LIMIT) {
          this.reason.text = 'SVG 嵌套超出受限预览上限';
          return false;
        }
        this.stack.push({ name: name, stripped: true });
        this.stripDepth++;
      }
      return true;
    }
    if (!SVG_TAGS.includes(name)) {
      this.reason.text = '受限预览不支持标签 ' + token.raw;
      return false;
    }
    const attributes: string | null = svgElementAttributes(token, this.reason);
    if (attributes === null) { return false; }
    this.pieces.push('<' + name + attributes + (token.selfClosed ? '/>' : '>'));
    if (!token.selfClosed) {
      if (this.stack.length >= PREVIEW_DEPTH_LIMIT) {
        this.reason.text = 'SVG 嵌套超出受限预览上限';
        return false;
      }
      this.stack.push({ name: name, stripped: false });
    }
    return true;
  }
}

function svgPreviewContent(source: string): SvgPreviewContent {
  return new SvgPreviewScanner(source).run();
}

export function markdownPreviewSvgError(source: string, closed: boolean): string {
  if (!closed) { return 'SVG 围栏尚未闭合，请先阅读源码'; }
  if (source.trim() === '') { return 'SVG 源码为空'; }
  if (source.length > MARKDOWN_PREVIEW_SVG_LIMIT) { return 'SVG 超过受限预览上限，请阅读源码'; }
  const content: SvgPreviewContent = svgPreviewContent(source);
  if (content.svg !== '') { return ''; }
  // 拒因可见化（U5-R3b）：带出扫描器首处失败原因，UI 只消费本值。
  return (content.reason !== '' ? content.reason : 'SVG 未通过安全校验') + '，请阅读源码';
}

/** SVG 受限预览文档装配：准入重建片段入固定壳（与 HTML/Mermaid 同壳口径——固定虚拟源、资源
 *  拦截、无脚本、CSP 恒 script-src 'none'）；标题协议 :svg 与 :html 并列为成功信号。图形置于
 *  白底画板（SVG 颜色内嵌不随主题，深色下黑描边需浅底才可见，防「渲染成功但看不见」）。 */
export function markdownPreviewSvg(source: string, darkMode: boolean, session: string): MarkdownPreviewDocument {
  const content: SvgPreviewContent = svgPreviewContent(source);
  if (content.svg === '') {
    return { html: '', error: (content.reason !== '' ? content.reason : 'SVG 未通过安全校验') + '，请阅读源码',
      removed: false };
  }
  const foreground: string = darkMode ? '#f1f1f1' : '#202124';
  const background: string = darkMode ? '#161616' : '#ffffff';
  const shell: string = '<!doctype html><html><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<meta http-equiv="Content-Security-Policy" content="' +
    markdownPreviewEscape(MARKDOWN_PREVIEW_HTML_CSP) + '">' +
    '<title>' + markdownPreviewEscape('md-preview:' + session + ':svg') + '</title>' +
    '<style>html{color-scheme:' + (darkMode ? 'dark' : 'light') + '}body{margin:16px;color:' + foreground +
    ';background:' + background + ';font:16px/1.5 sans-serif}' +
    '.svg-plate{background:#ffffff;border-radius:8px;padding:4px}' +
    'svg{display:block;margin:0 auto;max-width:100%;height:auto}</style></head><body>' +
    '<div class="svg-plate">' + content.svg + '</div></body></html>';
  return { html: shell, error: '', removed: content.stripped };
}

// ── 消息流 HTML 块白名单投影（U10）──
// 与 markdownPreviewHtml 同源：同一份 SAFE_TAGS / parseTag / 实体解码 / 限额，但输出为有界
// 结构列表——只有标签名、样式旗标与解码纯文本，属性/URL/脚本在结构层不存在（a 只留文字旗标）。
// 内联投影恒不豁免 script（U8a 开关只作用于受限预览 Web 壳）。退源码口径（null ⇒ 挂点走原
// MarkdownReadingContent 源码路径）：输入/标签数/嵌套超限、块级或表格结构帧未闭合（流式在途
// 常态——严格退源码让流式期稳定停在源码态、闭合后一次切渲染；块内行内配对项随所属块闭合隐式
// 补闭，仅根级未收口才判）、表格畸形、无可见内容。预览壳对未闭合自动补闭，投影对块级刻意更
// 严：流式稳定优先。
export interface MarkdownHtmlRun {
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  mark: boolean;
  code: boolean;
  link: boolean;
}

export interface MarkdownHtmlBlock {
  id: number;
  tag: string;
  level: number;
  marker: string;
  indent: number;
  header: boolean;
  runs: MarkdownHtmlRun[];
  cells: MarkdownHtmlRun[][];
  children: MarkdownHtmlBlock[];
}

/** 投影节点的标题级别（h1~h6 返回 1~6，其余标签返回 0）——解析定级与组件选字级共用。 */
export function markdownHtmlHeadingLevel(tag: string): number {
  if (tag.length !== 2 || tag.charAt(0) !== 'h') { return 0; }
  const level: number = Number(tag.charAt(1));
  return level >= 1 && level <= 6 ? level : 0;
}

interface HtmlProjectionStyle {
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  mark: boolean;
  code: boolean;
  link: boolean;
}

interface HtmlProjectionInline {
  tag: string;
  style: HtmlProjectionStyle;
}

// 帧角色：block = 内容块（含根帧，runs 即收集槽）/ pass = 透传容器（零呈现）/ table = 表格 /
// row = 行收集 / cell = 单元格（cell 即收集槽）。entryDepth = 入栈时配对项数——帧闭合时把帧内
// 开出的配对项截断到帧内基线（隐式补闭同口径，闭合仅按名外溢不误伤）。
interface HtmlProjectionFrame {
  role: string;
  tag: string;
  node: MarkdownHtmlBlock | null;
  cell: MarkdownHtmlRun[] | null;
  header: boolean;
  entryDepth: number;
}

/** 行内白名单：折叠进文本段不建结构（span 只作配对占位）。 */
const HTML_PROJECTION_INLINE_TAGS: string[] = ['strong', 'b', 'em', 'i', 'u', 's', 'del', 'small',
  'mark', 'sub', 'sup', 'code', 'a', 'span'];

class HtmlProjectionParser {
  private readonly source: string;
  private cursor: number = 0;
  private tags: number = 0;
  private serial: number = 0;
  private visible: boolean = false;
  private frames: HtmlProjectionFrame[] = [];
  // 配对项栈（行内标记 + 单元格/pre 内折叠的块级标签）：闭合按名就近吞并，帧闭合截断到帧内基线。
  private inline: HtmlProjectionInline[] = [];

  constructor(source: string) { this.source = source; }

  private make(tag: string): MarkdownHtmlBlock {
    this.serial++;
    return { id: this.serial, tag: tag, level: 0, marker: '', indent: 0, header: false,
      runs: [], cells: [], children: [] };
  }

  // 最近的容器帧（透传帧跳过）：块级标签的挂载点与表格结构核验同用。
  private contentFrame(): HtmlProjectionFrame {
    for (let index: number = this.frames.length - 1; index >= 0; index--) {
      if (this.frames[index].role !== 'pass') { return this.frames[index]; }
    }
    return this.frames[0];
  }

  // 文本收集槽：单元格帧与块帧直取；表格/行帧内游离文本不渲染（浏览器同口径，直接丢弃）。
  private runSink(): MarkdownHtmlRun[] | null {
    for (let index: number = this.frames.length - 1; index >= 0; index--) {
      const frame: HtmlProjectionFrame = this.frames[index];
      if (frame.role === 'cell') { return frame.cell; }
      if (frame.role === 'block') { return frame.node === null ? null : frame.node.runs; }
      if (frame.role === 'table' || frame.role === 'row') { return null; }
    }
    return null;
  }

  private currentStyle(): HtmlProjectionStyle {
    const style: HtmlProjectionStyle = { bold: false, italic: false, underline: false, strike: false,
      mark: false, code: false, link: false };
    for (let index: number = this.frames.length - 1; index >= 0; index--) {
      const frame: HtmlProjectionFrame = this.frames[index];
      if (frame.role === 'block' && frame.node !== null) {
        // pre 内容恒等宽（组件按 code 旗标选字体，与阅读面同档）。
        style.code = frame.node.tag === 'pre';
        break;
      }
    }
    for (let index: number = 0; index < this.inline.length; index++) {
      const item: HtmlProjectionStyle = this.inline[index].style;
      style.bold = style.bold || item.bold;
      style.italic = style.italic || item.italic;
      style.underline = style.underline || item.underline;
      style.strike = style.strike || item.strike;
      style.mark = style.mark || item.mark;
      style.code = style.code || item.code;
      style.link = style.link || item.link;
    }
    return style;
  }

  private styleOf(name: string): HtmlProjectionStyle {
    return { bold: name === 'strong' || name === 'b', italic: name === 'em' || name === 'i',
      underline: name === 'u', strike: name === 's' || name === 'del', mark: name === 'mark',
      code: name === 'code', link: name === 'a' };
  }

  private pushRun(text: string): void {
    const runs: MarkdownHtmlRun[] | null = this.runSink();
    if (runs === null) { return; }
    const style: HtmlProjectionStyle = this.currentStyle();
    const last: MarkdownHtmlRun | null = runs.length > 0 ? runs[runs.length - 1] : null;
    if (last !== null && last.bold === style.bold && last.italic === style.italic &&
      last.underline === style.underline && last.strike === style.strike && last.mark === style.mark &&
      last.code === style.code && last.link === style.link) {
      last.text += text;
      return;
    }
    runs.push({ text: text, bold: style.bold, italic: style.italic, underline: style.underline,
      strike: style.strike, mark: style.mark, code: style.code, link: style.link });
  }

  // 空白折叠（浏览器语义）：非 pre / 非行内代码的连续空白收成一空格（nbsp 等不可折叠字符
  // 不受影响）；块首尾净白由 trimRuns 修剪；br 走 pushBreak 不折叠，换行语义保留。
  private pushText(text: string): void {
    if (text === '') { return; }
    if (text.trim() !== '') { this.visible = true; }
    this.pushRun(this.currentStyle().code ? text : text.replace(/[ \t\r\n]+/g, ' '));
  }

  private pushBreak(): void {
    this.pushRun('\n');
  }

  private trimRuns(runs: MarkdownHtmlRun[], trimHead: boolean, trimTail: boolean): void {
    if (runs.length === 0) { return; }
    if (trimHead) { runs[0].text = runs[0].text.replace(/^[ \t\r\n]+/, ''); }
    if (trimTail) { runs[runs.length - 1].text = runs[runs.length - 1].text.replace(/[ \t\r\n]+$/, ''); }
    for (let index: number = runs.length - 1; index >= 0; index--) {
      if (runs[index].text === '') { runs.splice(index, 1); }
    }
  }

  // 出栈前修剪：pre 保源码原样，其余块与单元格修剪首尾净白（缩进排版不修剪会上屏）。
  private normalize(node: MarkdownHtmlBlock): void {
    if (node.tag !== 'pre') { this.trimRuns(node.runs, true, true); }
    for (let index: number = 0; index < node.cells.length; index++) {
      this.trimRuns(node.cells[index], true, true);
    }
    for (let index: number = 0; index < node.children.length; index++) {
      this.normalize(node.children[index]);
    }
  }

  // 悬挂文本落成 text 子节点保文档顺序：force = 挂子块前必冲；非 force = 已有子块才冲
  //（尾文本在最后子块后，无子块时 runs 留守原位）。
  private flushRuns(frame: HtmlProjectionFrame, force: boolean): void {
    if (frame.role !== 'block' || frame.node === null) { return; }
    const node: MarkdownHtmlBlock = frame.node;
    if (node.runs.length === 0 || (!force && node.children.length === 0)) { return; }
    const text: MarkdownHtmlBlock = this.make('text');
    text.runs = node.runs;
    node.runs = [];
    node.children.push(text);
  }

  private attachBlock(node: MarkdownHtmlBlock): boolean {
    const parent: HtmlProjectionFrame = this.contentFrame();
    if (parent.role !== 'block' || parent.node === null) { return false; }
    this.flushRuns(parent, true);
    parent.node.children.push(node);
    return true;
  }

  private listItem(node: MarkdownHtmlBlock): boolean {
    let list: MarkdownHtmlBlock | null = null;
    let depth: number = 0;
    for (let index: number = this.frames.length - 1; index >= 0; index--) {
      const frame: HtmlProjectionFrame = this.frames[index];
      if (frame.role === 'block' && frame.node !== null &&
        (frame.node.tag === 'ul' || frame.node.tag === 'ol')) {
        // 自栈顶向下 = 由内向外：首个命中即最近一层列表，marker 计数与符号只认它（循环覆盖
        // 取到的是最外层——内层 ol 从外层续号，P6 自检②缺陷已修）；更外层仅累计 depth。
        if (list === null) { list = frame.node; }
        depth++;
      }
    }
    if (list === null) { return false; }
    node.indent = depth - 1;
    if (list.tag === 'ol') {
      let items: number = 0;
      for (let index: number = 0; index < list.children.length; index++) {
        if (list.children[index].tag === 'li') { items++; }
      }
      node.marker = (items + 1).toString() + '.';
    } else {
      node.marker = '•';
    }
    return true;
  }

  private closeTag(name: string): void {
    for (let index: number = this.inline.length - 1; index >= 0; index--) {
      if (this.inline[index].tag === name) {
        this.inline.splice(index);
        return;
      }
    }
    for (let index: number = this.frames.length - 1; index >= 1; index--) {
      if (this.frames[index].tag === name) {
        while (this.frames.length > index) { this.closeFrame(this.frames.pop()!); }
        return;
      }
    }
  }

  // 帧出栈统一收口：悬挂文本落位后，把帧内开出的配对项截断到帧内基线（隐式补闭）。
  private closeFrame(frame: HtmlProjectionFrame): void {
    this.flushRuns(frame, false);
    if (this.inline.length > frame.entryDepth) { this.inline.splice(frame.entryDepth); }
  }

  private skipOmitted(name: string): boolean {
    while (this.cursor < this.source.length) {
      const next: number = this.source.indexOf('<', this.cursor);
      if (next < 0) { this.cursor = this.source.length; return true; }
      const end: number = tagEnd(this.source, next);
      if (end < 0) { this.cursor = this.source.length; return true; }
      const tag: PreviewTag | null = parseTag(this.source.substring(next + 1, end));
      this.cursor = end + 1;
      this.tags++;
      if (this.tags > PREVIEW_TAG_LIMIT) { return false; }
      if (tag !== null && tag.closing && tag.name === name) { return true; }
    }
    return true;
  }

  private hasText(runs: MarkdownHtmlRun[]): boolean {
    for (let index: number = 0; index < runs.length; index++) {
      if (runs[index].text.trim() !== '') { return true; }
    }
    return false;
  }

  private hasContent(node: MarkdownHtmlBlock): boolean {
    if (node.tag === 'hr') { return true; }
    if (this.hasText(node.runs)) { return true; }
    for (let index: number = 0; index < node.cells.length; index++) {
      if (this.hasText(node.cells[index])) { return true; }
    }
    for (let index: number = 0; index < node.children.length; index++) {
      if (this.hasContent(node.children[index])) { return true; }
    }
    return false;
  }

  private prune(nodes: MarkdownHtmlBlock[]): void {
    for (let index: number = 0; index < nodes.length; index++) {
      this.prune(nodes[index].children);
      if (this.hasContent(nodes[index])) { continue; }
      nodes.splice(index, 1);
      index--;
    }
  }

  project(): MarkdownHtmlBlock[] | null {
    if (this.source.length > MARKDOWN_PREVIEW_INPUT_LIMIT) { return null; }
    const root: MarkdownHtmlBlock = this.make('');
    this.frames.push({ role: 'block', tag: '', node: root, cell: null, header: false,
      entryDepth: this.inline.length });
    while (this.cursor < this.source.length) {
      const next: number = this.source.indexOf('<', this.cursor);
      if (next < 0) { this.pushText(decodeMarkdownEntities(this.source.substring(this.cursor))); break; }
      this.pushText(decodeMarkdownEntities(this.source.substring(this.cursor, next)));
      if (this.source.startsWith('<!--', next)) {
        const commentEnd: number = this.source.indexOf('-->', next + 4);
        this.cursor = commentEnd < 0 ? this.source.length : commentEnd + 3;
        continue;
      }
      const end: number = tagEnd(this.source, next);
      if (end < 0) { this.pushText(this.source.substring(next)); break; }
      const raw: string = this.source.substring(next + 1, end);
      const tag: PreviewTag | null = parseTag(raw);
      this.cursor = end + 1;
      this.tags++;
      if (this.tags > PREVIEW_TAG_LIMIT || this.frames.length + this.inline.length > PREVIEW_DEPTH_LIMIT) {
        return null;
      }
      if (tag === null) { this.pushText('<' + raw + '>'); continue; }
      const name: string = tag.name;
      // 自闭合形态照 markdownPreviewHtml 同款判据（属性以 / 收尾 = 闭合，无正文）。
      if (!tag.closing) {
        if (!this.openTag(name, /\/\s*$/.test(tag.attributes))) { return null; }
      } else {
        this.closeTag(name);
      }
    }
    if (this.frames.length > 1 || this.inline.length > 0) { return null; }
    // 根帧自身无渲染面：悬挂文本强制落成顶层 text 节点，与其余块同级排序。
    this.flushRuns(this.frames[0], true);
    if (!this.visible) { return null; }
    for (let index: number = 0; index < root.children.length; index++) { this.normalize(root.children[index]); }
    this.prune(root.children);
    return root.children.length > 0 ? root.children : null;
  }

  private openTag(name: string, selfClosed: boolean): boolean {
    if (OMIT_CONTENT_TAGS.includes(name)) {
      // 恒剥（内联投影不豁免 script，见上方 U10 说明）：内容整段吞掉。
      return selfClosed || this.skipOmitted(name);
    }
    if (!SAFE_TAGS.includes(name)) { return true; }
    if (name === 'br') { this.pushBreak(); return true; }
    if (HTML_PROJECTION_INLINE_TAGS.includes(name)) {
      if (!selfClosed) { this.inline.push({ tag: name, style: this.styleOf(name) }); }
      return true;
    }
    const context: HtmlProjectionFrame = this.contentFrame();
    if (context.role === 'cell' || (context.role === 'block' && context.node !== null &&
      context.node.tag === 'pre')) {
      // 单元格与 pre 内块级标签折叠为文本（嵌套表到此降级）：只登记成对闭合（闭合先被配对栈
      // 吞，不误关外层结构帧），内容经 runSink 顺序并入。
      if (!selfClosed) { this.inline.push({ tag: name, style: this.styleOf(name) }); }
      return true;
    }
    if (name === 'hr') {
      const line: MarkdownHtmlBlock = this.make('hr');
      if (!this.attachBlock(line)) { return false; }
      this.visible = true;
      return true;
    }
    const level: number = markdownHtmlHeadingLevel(name);
    if (level > 0 || name === 'p' || name === 'blockquote' || name === 'pre' || name === 'ul' ||
      name === 'ol' || name === 'li') {
      const node: MarkdownHtmlBlock = this.make(name);
      node.level = level;
      if (name === 'li' && !this.listItem(node)) { return false; }
      if (!this.attachBlock(node)) { return false; }
      if (!selfClosed) { this.frames.push({ role: 'block', tag: name, node: node, cell: null,
        header: false, entryDepth: this.inline.length }); }
      return true;
    }
    if (name === 'table') {
      const node: MarkdownHtmlBlock = this.make(name);
      if (!this.attachBlock(node)) { return false; }
      if (!selfClosed) { this.frames.push({ role: 'table', tag: name, node: node, cell: null,
        header: false, entryDepth: this.inline.length }); }
      return true;
    }
    if (name === 'thead' || name === 'tbody' || name === 'tfoot') {
      if (context.role !== 'table' || context.node === null) { return false; }
      context.header = name === 'thead';
      if (!selfClosed) { this.frames.push({ role: 'pass', tag: name, node: null, cell: null,
        header: false, entryDepth: this.inline.length }); }
      return true;
    }
    if (name === 'tr') {
      if (context.role !== 'table' || context.node === null) { return false; }
      const row: MarkdownHtmlBlock = this.make(name);
      row.header = context.header;
      context.node.children.push(row);
      if (!selfClosed) { this.frames.push({ role: 'row', tag: name, node: row, cell: null,
        header: row.header, entryDepth: this.inline.length }); }
      return true;
    }
    if (name === 'th' || name === 'td') {
      if (context.role !== 'row' || context.node === null) { return false; }
      const cell: MarkdownHtmlRun[] = [];
      context.node.cells.push(cell);
      if (name === 'th') { context.header = true; context.node.header = true; }
      if (!selfClosed) { this.frames.push({ role: 'cell', tag: name, node: null, cell: cell,
        header: false, entryDepth: this.inline.length }); }
      return true;
    }
    // 其余白名单标签 = 透传容器：标签本身零呈现，内容并入就地上下文（后续新白名单标签自动落此档）。
    if (!selfClosed) { this.frames.push({ role: 'pass', tag: name, node: null, cell: null,
      header: false, entryDepth: this.inline.length }); }
    return true;
  }
}

/** 消息流 HTML 块投影入口（纯函数）：有界结构列表；null = 整块退源码。输入与
 *  markdownPreviewHtml 同一输入面（htmlBlock 语义节点 text）。 */
export function markdownHtmlProjection(source: string): MarkdownHtmlBlock[] | null {
  return new HtmlProjectionParser(source).project();
}

export function markdownPreviewMermaidError(source: string, closed: boolean): string {
  if (!closed) { return '图表围栏尚未闭合，请先阅读源码'; }
  if (source.trim() === '') { return '图表源码为空'; }
  if (source.length > MARKDOWN_PREVIEW_MERMAID_LIMIT) { return '图表超过受限预览上限，请阅读源码'; }
  // 不给输入配置、交互、外部图片或 CSS 注入通道。实体/HTML 即便被库支持也不入受限子集。
  if (/%%\s*\{|(^|\n)\s*---(?:\r?\n|$)|\b(?:click|href|callback|call|config|securityLevel|htmlLabels|linkTarget|image|img|icon|style|classDef|linkStyle)\b|<\s*\/?\s*[a-zA-Z][^>]*>|<!|<\?|&(?:#|[a-zA-Z])/i.test(source)) {
    return '图表包含配置、交互或外部内容，受限预览不执行这些语法';
  }
  return '';
}

/** 只把序列化后的值作为固定函数实参，不生成用户函数、模板或脚本标签。 */
export function markdownPreviewStartScript(source: string, session: string, darkMode: boolean): string {
  const literal: string = JSON.stringify(source).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  return 'window.MarkdownPreviewRunner.start(' + JSON.stringify(session) + ',' + literal + ',' +
    (darkMode ? 'true' : 'false') + ')';
}

export function markdownPreviewReadTitle(title: string, session: string): MarkdownPreviewTitle {
  const prefix: string = 'md-preview:' + session + ':';
  if (!title.startsWith(prefix)) { return { status: '', message: '' }; }
  const value: string = title.substring(prefix.length);
  if (value === 'ok') { return { status: 'ok', message: '' }; }
  if (value.startsWith('error:')) {
    let message: string = '图表渲染失败，请阅读源码';
    try { message = decodeURIComponent(value.substring(6, 1030)).substring(0, 160) || message; }
    catch (_) { /* 标题畸形只回可读错误，不反向执行或放宽权限。 */ }
    return { status: 'error', message: message };
  }
  return { status: '', message: '' };
}

/** 原文只按页展示，不删除数据；相邻页边界同步右移，避免切开代理对。 */
export function markdownPreviewSourcePage(source: string, page: number): string {
  const pages: number = Math.max(1, Math.ceil(source.length / MARKDOWN_PREVIEW_SOURCE_PAGE));
  const index: number = Math.max(0, Math.min(pages - 1, Math.floor(page)));
  let start: number = index * MARKDOWN_PREVIEW_SOURCE_PAGE;
  let end: number = Math.min(source.length, start + MARKDOWN_PREVIEW_SOURCE_PAGE);
  if (start > 0 && source.charCodeAt(start - 1) >= 0xD800 && source.charCodeAt(start - 1) <= 0xDBFF &&
    source.charCodeAt(start) >= 0xDC00 && source.charCodeAt(start) <= 0xDFFF) { start++; }
  if (end < source.length && source.charCodeAt(end - 1) >= 0xD800 && source.charCodeAt(end - 1) <= 0xDBFF &&
    source.charCodeAt(end) >= 0xDC00 && source.charCodeAt(end) <= 0xDFFF) { end++; }
  return source.substring(start, end);
}
