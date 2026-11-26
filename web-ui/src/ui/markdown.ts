// Markdown 渲染单源（markdown-it + highlight.js 语言子集）。
// 安全：html:false——正文里的原始 HTML 一律按文本转义；markdown-it 内置 link 协议校验
// （javascript: 等被拦）。外链统一 target=_blank + rel=noopener noreferrer。
// 代码块：自绘外壳（语言标签 + 复制键），复制键的点击由消息容器委托处理——不进 innerHTML
// 的任何脚本，正文仍按纯文本转义。
import MarkdownIt from 'markdown-it';
import hljs from 'highlight.js/lib/common';

const LANG_LABEL: Record<string, string> = {
  js: 'JavaScript',
  jsx: 'JavaScript',
  ts: 'TypeScript',
  tsx: 'TypeScript',
  py: 'Python',
  python: 'Python',
  sh: 'Shell',
  bash: 'Shell',
  zsh: 'Shell',
  shell: 'Shell',
  json: 'JSON',
  jsonc: 'JSON',
  html: 'HTML',
  xml: 'XML',
  css: 'CSS',
  scss: 'SCSS',
  less: 'Less',
  go: 'Go',
  rust: 'Rust',
  java: 'Java',
  kotlin: 'Kotlin',
  swift: 'Swift',
  c: 'C',
  cpp: 'C++',
  cs: 'C#',
  sql: 'SQL',
  yaml: 'YAML',
  yml: 'YAML',
  toml: 'TOML',
  ini: 'INI',
  md: 'Markdown',
  markdown: 'Markdown',
  diff: 'Diff',
  dockerfile: 'Dockerfile',
  makefile: 'Makefile',
  ets: 'ArkTS',
  dart: 'Dart',
  php: 'PHP',
  ruby: 'Ruby',
  lua: 'Lua',
  r: 'R',
  scala: 'Scala',
  graphql: 'GraphQL',
  proto: 'Proto',
  text: '文本',
  txt: '文本',
};

const COPY_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"'
  + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
  + '<rect x="9" y="9" width="12" height="12" rx="2.5"/>'
  + '<path d="M5 15H4.5A2.5 2.5 0 0 1 2 12.5v-8A2.5 2.5 0 0 1 4.5 2h8A2.5 2.5 0 0 1 15 4.5V5"/>'
  + '</svg>';

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: true,
});

// 代码块外壳：语言条 + 复制键 + 高亮正文。复制内容由点击时读 <code>.textContent
// 取得（不把源码塞进 data 属性——转义/换行都不可靠）。
md.renderer.rules.fence = (tokens, idx): string => {
  const token = tokens[idx];
  const info = token.info.trim();
  const lang = (info.split(/\s+/)[0] ?? '').toLowerCase();
  const raw = token.content;
  let body = '';
  if (lang !== '' && hljs.getLanguage(lang)) {
    try {
      body = hljs.highlight(raw, { language: lang, ignoreIllegals: true }).value;
    } catch {
      body = md.utils.escapeHtml(raw);
    }
  } else {
    body = md.utils.escapeHtml(raw);
  }
  const label = LANG_LABEL[lang] ?? (lang === '' ? '文本' : lang);
  const langClass = lang === '' ? 'hljs' : `hljs language-${md.utils.escapeHtml(lang)}`;
  return `<div class="codeblock"><div class="codeblock-head">`
    + `<span class="codeblock-lang">${md.utils.escapeHtml(label)}</span>`
    + `<button type="button" class="codeblock-copy" aria-label="复制代码">${COPY_ICON}<span>复制</span></button>`
    + `</div><pre><code class="${langClass}">${body}</code></pre></div>`;
};

const defaultLinkOpen = md.renderer.rules.link_open
  ?? ((tokens, idx, options, _env, self) => self.renderToken(tokens, idx, options));

md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  tokens[idx].attrSet('target', '_blank');
  tokens[idx].attrSet('rel', 'noopener noreferrer');
  return defaultLinkOpen(tokens, idx, options, env, self);
};

export function renderMarkdown(text: string): string {
  return md.render(text);
}
