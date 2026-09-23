// 消息复制面板文本准备域（2026-09-18 消息复制优化笔）：把气泡内 Markdown 原文准备成
// 半模态面板可展示/可复制的文本。两个口径——「纯文本」= 去除 md 标记的易读版；
// 「Markdown」= 原文。两口径都先整块剔除表格（决明 2026-09-18 口径「表格等先不显示在
// 半模态中」——表格在面板里是竖线符号串，无阅读与复制价值；放开时只改 removeTableBlocks
// 的调用面）。
// ★ 零 import 纯函数约束（照 TokenEstimate/MemoryText 先例——scripts/assert-msg-copy.mjs
// 复制本文件为 .ts 直跑，断言的就是线上同一实现，禁双实现漂移）。
// ★ 剥标记是保守集（只剥无歧义的标记，宁可残留不可误伤）：
//   · 剥——代码围栏标记行（围栏内代码原样保留）、行内代码反引号（内容原样）、**加粗**、
//     ~~删除线~~、ATX 标题 #、引用 >、链接 [文字](url)（取文字）、图片 ![alt](url)
//     （整段丢弃）、水平分隔线、转义反斜杠、无序列表标记归一为「- 」；
//   · 不剥——单星 *斜体* 与单下划线（误伤乘式 2*3*4 与 snake_case 的风险大于收益，
//     中文回复几乎不用星号斜体）、有序列表编号（1. 是内容的一部分）、HTML 标签、
//     尖括号自动链接（linkify 场景裸 URL 原样可读）。

// 表格块剔除（两口径共用第一步）：GFM 表格 = 连续的「以 | 开头」的行；块内行整块剔除。
// 判据取窄（行首 |）防误伤——正文里行中含竖线的引用句不受影响。
// ★ 围栏感知（2026-09-18 自检轮补）：代码围栏（``` / ~~~）内的行不判表格——围栏里展示
//   md 表格语法或 ASCII 表格（AI 回复常见）时整块被当正文表格删掉是内容丢失，Markdown
//   原文口径更会留下空围栏，与「表格剔除」目的相悖。
export function removeTableBlocks(md: string): string {
  const lines: string[] = md.split('\n');
  const out: string[] = [];
  let inTable: boolean = false;
  let inFence: boolean = false;
  for (const line of lines) {
    if (/^\s{0,3}(```|~~~)/.test(line)) {
      inFence = !inFence; // 围栏标记行自身不是表格行；随下方块结束逻辑照常落原行
    }
    const isRow: boolean = !inFence && line.trimStart().startsWith('|');
    if (isRow) {
      inTable = true;
      continue;
    }
    // 块结束补一个空行（前后段隔开——表格整块消失后段落直接相邻会挤在一起）
    if (inTable && line.trim() !== '') {
      out.push('');
      inTable = false;
    } else if (inTable) {
      inTable = false;
    }
    out.push(line);
  }
  return out.join('\n');
}

// 去除 md 标记（输入 = 已剔除表格的原文；逐行 + 行内两级）：
// ① 逐行——围栏状态机（开栏行丢弃〔含语言标签〕、栏内行原样、闭栏行丢弃）、标题剥 #、
//    引用剥 >、分隔线整行删、无序列表标记归一「- 」；
// ② 行内——行内代码先抽出占位（内容不被后续剥除波及，收尾还原）→ 图片丢弃 → 链接取
//    文字 → 加粗/删除线/转义 → 还原行内代码；尾随空格修剪。
export function stripMarkdownText(md: string): string {
  const lines: string[] = removeTableBlocks(md).split('\n');
  const out: string[] = [];
  const codeSlots: string[] = [];
  let inFence: boolean = false;
  for (const line of lines) {
    if (/^\s{0,3}(```|~~~)/.test(line)) {
      inFence = !inFence;
      continue; // 围栏标记行（含语言标签）整行丢弃
    }
    if (inFence) {
      out.push(line); // 围栏内代码原样保留——禁行内剥除
      continue;
    }
    let t: string = line;
    if (/^\s{0,3}(?:-[ \t]*-[ \t]*-[- \t]*|\*[ \t]*\*[ \t]*\*[\* \t]*|_[ \t]*_[ \t]*_[_ \t]*)$/.test(t)) {
      continue; // 水平分隔线整行删
    }
    const heading: RegExpMatchArray | null = t.match(/^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/);
    if (heading !== null) {
      t = heading[1];
    }
    // 引用前缀剥净（嵌套 > > 连环一并吃掉）
    while (/^\s{0,3}>/.test(t)) {
      t = t.replace(/^\s{0,3}>\s?/, '');
    }
    const listItem: RegExpMatchArray | null = t.match(/^(\s*)[-*+](\s+)(.*)$/);
    if (listItem !== null) {
      t = listItem[1] + '- ' + listItem[3]; // 无序标记归一「- 」（* + 与 - 同义，观感统一）
    }
    out.push(inlineStrip(t, codeSlots).trimEnd());
  }
  // 还原行内代码（单次扫描回填——占位符 \x000N\x000 只出现在正文、回填内容不再被扫，
  // 与逐槽 split/join 等价；逐槽法是 O(槽数×文本长)，长消息多代码段时平方级，
  // 2026-09-18 自检轮 node 基准实测后改单次）
  return out.join('\n').replace(/\x000(\d+)\x000/g, (_m: string, idx: string): string =>
    codeSlots[Number(idx)]);
}

// 行内剥除（单行；codeSlots 收集行内代码原文，正文留占位符）
function inlineStrip(line: string, codeSlots: string[]): string {
  let t: string = line.replace(/`([^`]+)`/g, (_m: string, code: string): string => {
    codeSlots.push(code);
    return '\x000' + (codeSlots.length - 1) + '\x000';
  });
  t = t.replace(/!\[[^\]]*\]\([^)]*\)/g, ''); // 图片整段丢弃（alt 多为文件名，无可读价值）
  t = t.replace(/\[([^\]]+)\]\(([^)]*)\)/g, '$1'); // 链接取文字（url 在 Markdown 原文模式可取）
  t = t.replace(/\*\*([^*]+)\*\*/g, '$1'); // 加粗
  t = t.replace(/~~([^~]+)~~/g, '$1'); // 删除线
  t = t.replace(/\\([\\`*_{}[\]()#+\-.!~|])/g, '$1'); // 转义还原
  return t;
}

// 面板文本准备单点（MessageCopySheet 唯一消费方）：plainMode = 纯文本口径（去表格 + 剥
// 标记）；false = Markdown 原文口径（只去表格——决明「表格等先不显示在半模态中」，
// 放开表格 = 本函数内移除 removeTableBlocks 调用一处）。
export function buildCopySheetText(md: string, plainMode: boolean): string {
  const noTables: string = removeTableBlocks(md);
  return plainMode ? stripMarkdownText(noTables) : noTables;
}
