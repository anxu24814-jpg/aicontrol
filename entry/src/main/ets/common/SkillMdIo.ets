// SKILL.md 文档的解析与序列化（parse / serialize / 打包目录名派生），自 SkillText.ets 域级
// 拆出（parseSkillMd / skillPackDirName / serializeSkillMd 三函数连同各自专属辅助），函数体
// 逐字搬迁零改动；包内条目映射（classifySkillPackEntry / pickSkillRoots）与 use_skill 回执
// 族不属本缝，留主件。
// 单向依赖：本件只 import 主件 SkillText 的两符号——safeCutIndex（skillPackDirName 的代理
// 对安全切点）与 SkillDocItem（serializeSkillMd 入参类型，清单/回执族共用）；SkillText 不
// 反向 import 本件，主件零 import 纯函数约束（复制直跑）不破，依赖图单向无环。
// 断言通道：本件带 import 不能直接复制直跑——assert-skill-domain.mjs 照 SkillManageText
// 先例「剥 import + 前置 SkillText 源拼接」直跑（线上同一实现）。

import { safeCutIndex, SkillDocItem } from './SkillText';

// ── SKILL.md frontmatter 解析（导入侧）──
// 导入包里的 SKILL.md 未必出自本应用（可能手写或来自其他客户端），解析**容错且严格报因**：
// frontmatter 缺失/不可解析/name 缺失/description 键缺失 → ok=false + 中文 error（调用方
// 跳过该条并如实报告，不静默丢件）。允许 description 值为空串，但键必须在——「键缺失」
// 与「作者显式写了空描述」是两件事，前者多为格式错，后者是刻意留空。
export interface SkillMdParse {
  ok: boolean;
  name: string;
  description: string;
  content: string;
  error: string;
}

function rejectSkillMd(error: string): SkillMdParse {
  return { ok: false, name: '', description: '', content: '', error: error };
}

// 首尾围栏剔除：允许 BOM 与围栏前后的空白行（跨客户端产物常见形态）
const MD_FENCE: string = '---';

// YAML 块标量指示符判据（'|' / '>'，可带 chomping 与显式缩进指示：|-, >+, |2 等）。整值
// 匹配才算——「> 3 条时…」等以这两字符开头但另有内容的普通标量不误伤
function isBlockScalarIndicator(value: string): boolean {
  return /^[|>][-+]?\d*$/.test(value);
}

export function parseSkillMd(text: string): SkillMdParse {
  let body: string = text;
  if (body.charCodeAt(0) === 0xFEFF) {
    body = body.substring(1); // BOM（Windows 记事本另存常见）
  }
  const lines: string[] = body.split('\n');
  let head: number = 0;
  while (head < lines.length && lines[head].trim() === '') {
    head++;
  }
  if (head >= lines.length || lines[head].replace(/\r$/, '').trim() !== MD_FENCE) {
    return rejectSkillMd('缺少 frontmatter（文件需要以 --- 开头）');
  }
  let end: number = -1;
  for (let i: number = head + 1; i < lines.length; i++) {
    if (lines[i].replace(/\r$/, '').trim() === MD_FENCE) {
      end = i;
      break;
    }
  }
  if (end < 0) {
    return rejectSkillMd('frontmatter 无法解析（缺少结束的 ---）');
  }
  let name: string | null = null;
  let description: string | null = null;
  for (let i: number = head + 1; i < end; i++) {
    const line: string = lines[i].replace(/\r$/, '');
    const colon: number = line.indexOf(':');
    if (colon < 0) {
      continue;
    }
    const key: string = line.substring(0, colon).trim();
    const rawValue: string = line.substring(colon + 1).trim();
    // **只消费 name / description 两键，其余键原样忽略**（官方 Agent Skills 规范还有
    // license / allowed-tools / metadata / version 等键，别家包带它们是常态，不因此拒收整包）
    if (key !== 'name' && key !== 'description') {
      continue;
    }
    // YAML 多行块标量（`description: |` / `>` 及变体）拒收并说清「暂不支持多行」——
    // description 是模型判断是否加载的主字段，当普通标量收下会变成字面量 '|' 静默落库；
    // 判据收窄到「整值就是块指示符」。本判据只对这两键生效（无关键的块标量忽略即可——
    // 读不懂 ≠ 该拒）
    if (isBlockScalarIndicator(rawValue)) {
      return rejectSkillMd('frontmatter 的 ' + key + ' 用了多行写法（' + rawValue.charAt(0) +
        '），暂不支持，请改写成一行');
    }
    if (key === 'name') {
      name = unquoteYamlScalar(rawValue);
    } else {
      description = unquoteYamlScalar(rawValue);
    }
  }
  if (name === null) {
    return rejectSkillMd('frontmatter 里缺少 name');
  }
  if (name.trim() === '') {
    return rejectSkillMd('frontmatter 里的 name 为空');
  }
  if (description === null) {
    return rejectSkillMd('frontmatter 里缺少 description');
  }
  const tail: string[] = [];
  for (let i: number = end + 1; i < lines.length; i++) {
    tail.push(lines[i].replace(/\r$/, ''));
  }
  // 围栏后的首部空行剔除（serializeSkillMd 恒写一个空行）
  let start: number = 0;
  while (start < tail.length && tail[start].trim() === '') {
    start++;
  }
  // ★ 首尾空白**有意归一**：写入侧 yamlScalar 为带首尾空白的值加引号（保住它），读取侧
  // 统一 trim——净语义 = 「导入的库内值恒无首尾空白」。理由：库内名是模型 use_skill 的
  // 逐字定位键，隐形空白会让照清单重打的名字匹配不上；description 同理。写入侧引号包裹
  // 依然必要——不留它 YAML 会把前导空格吃掉，跨客户端连原文都读不回
  return { ok: true, name: name.trim(), description: description.trim(),
    content: tail.slice(start).join('\n').trim(), error: '' };
}

// YAML 标量还原（与 yamlScalar 对偶）：双引号包裹 → 剥引号 + 反转义；单引号 → 剥引号 +
// '' 还原为 '（YAML 单引号转义规则）；裸值 → 原样。只处理**同款引号成对**的形态，半引号
// （只有一边）按裸值返回——比自作聪明地截断更安全
export function unquoteYamlScalar(value: string): string {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    const inner: string = value.substring(1, value.length - 1);
    let out: string = '';
    for (let i: number = 0; i < inner.length; i++) {
      const ch: string = inner.charAt(i);
      if (ch === '\\' && i + 1 < inner.length) {
        const next: string = inner.charAt(i + 1);
        if (next === 'n') {
          out += '\n';
          i++;
          continue;
        }
        if (next === 'r') {
          out += '\r';
          i++;
          continue;
        }
        if (next === 't') {
          out += '\t';
          i++;
          continue;
        }
        if (next === '"' || next === '\\') {
          out += next;
          i++;
          continue;
        }
      }
      out += ch;
    }
    return out;
  }
  if (value.length >= 2 && value.startsWith('\'') && value.endsWith('\'')) {
    return value.substring(1, value.length - 1).split('\'\'').join('\'');
  }
  return value;
}

// ── 技能包（zip 目录）──
// 包内形态 = <目录名>/SKILL.md + <目录名>/files/<附件名>；目录名取技能名的文件名安全化形态
// （跨端非法字符替换 + 截断；与导出文件名同款清洗）
export function skillPackDirName(skillName: string): string {
  const safe: string = skillName.replace(/[\\/:*?"<>|]/g, '_').trim();
  // 截断走 safeCutIndex（不劈代理对——目录名会落到文件系统路径上，孤立代理字符是非法名）
  const cut: string = safe.substring(0, safeCutIndex(safe, 40));
  // 纯点段（'.' / '..'）与空名同档归位 skill（2026-09-15 全面自检轮 P1）：清洗正则不处理
  // 点，名称恰为 '..' 时原样返回——导出链 root = staging + '/..' 解析回 cacheDir 本身，
  // 正文与 files/ 全部越界写进 cacheDir，且 compressFile(root) 会把整个 cacheDir 打包进
  // 分享件（探针 scripts/.tmp/skill-layer-check-20260915.mjs 实锤）。'...' 等多点串是
  // 合法目录名，不误伤
  return cut === '' || cut === '.' || cut === '..' ? 'skill' : cut;
}

// ── SKILL.md 序列化（导出，方案 §2.6）──
// 形态 = YAML frontmatter（name / description 两键）+ 空行 + 正文原文——与 Agent Skills
// 开放规范同形，导出的文件外部工具可直接读取
export function serializeSkillMd(doc: SkillDocItem): string {
  return '---\nname: ' + yamlScalar(doc.name) + '\ndescription: ' +
    yamlScalar(doc.description) + '\n---\n\n' + doc.content;
}

// YAML 标量包裹（方案 §2.6 的「description 含冒号等特殊字符时双引号包裹」——name 同一
// 函数处理，理由 = 名称里的冒号同样会把 frontmatter 解析带偏，两键同规比单键特判更不易漏）：
// 含 ':' '#' '"' '\'' 反斜杠、换行、首尾空白，或以 YAML 指示符（- ? [ ] { } & * ! | > % @ ` ,）
// 开头时用双引号包裹并转义；其余原样输出（普通中文名不被引号污染，外部工具读起来清爽）
export function yamlScalar(value: string): string {
  if (!needsYamlQuote(value)) {
    return value;
  }
  let escaped: string = '';
  for (let i: number = 0; i < value.length; i++) {
    const ch: string = value.charAt(i);
    if (ch === '"' || ch === '\\') {
      escaped += '\\' + ch;
    } else if (ch === '\n') {
      escaped += '\\n';
    } else if (ch === '\r') {
      escaped += '\\r';
    } else if (ch === '\t') {
      escaped += '\\t';
    } else {
      escaped += ch;
    }
  }
  return '"' + escaped + '"';
}

// YAML 类型化标量（2026-09-13 独立探针补：跨客户端互读时，裸值会被 YAML 隐式类型解析
// 「吃掉」字符串语义——PyYAML 实测 123→int、true→bool、null/~→None、0012→八进制 10、
// .nan→float、2026-09-13→date。本应用自读无害（parseSkillMd 取原始文本），但导出件是给
// 外部 Agent Skills 客户端读的，故这几类一律加引号锁成字符串）。判据按 YAML 1.1/1.2 核心
// schema 的隐式解析规则收窄：布尔/空值词表、数字（十进制含前导零与下划线、十六进制、
// 指数）、无穷与 NaN、ISO 日期时间、文档结束标记
const YAML_TYPED_SCALARS: RegExp[] = [
  /^(?:true|false|yes|no|on|off|null|~)$/i,
  /^[-+]?(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][-+]?\d+)?$/,
  /^[-+]?0[xX][0-9a-fA-F_]+$/,
  /^[-+]?\.(?:inf|nan)$/i,
  /^\d{4}-\d{1,2}-\d{1,2}(?:[Tt ].*)?$/,
  /^\.\.\.$/
];

const YAML_INDICATORS: string = '-?:,[]{}#&*!|>\'\"%@`';
// ★ 全角冒号一并计入触发集：中文写作里「步骤：先做 A」是全角冒号，YAML 规格上它并非指示符
// （不引号也不会解析错），但本工程导出的技能文件主要给中文用户看与被外部工具搬运，统一包裹
// 的代价为零（双引号包裹恒为合法 YAML）而「有的冒号包、有的不包」反而是难解释的形态差异
const YAML_SPECIALS: string = ':#\'"\\\n\r\t：';

function needsYamlQuote(value: string): boolean {
  if (value === '') {
    return true; // 空值裸写会让 frontmatter 该键变成 null 语义——显式 '""' 更明确
  }
  if (value.trim() !== value) {
    return true; // 首尾空白：YAML 折叠规则会吃掉
  }
  for (let i: number = 0; i < value.length; i++) {
    const ch: string = value.charAt(i);
    if (YAML_SPECIALS.indexOf(ch) >= 0) {
      return true;
    }
    if (i === 0 && YAML_INDICATORS.indexOf(ch) >= 0) {
      return true;
    }
  }
  for (const pattern of YAML_TYPED_SCALARS) {
    if (pattern.test(value)) {
      return true; // 会被 YAML 隐式类型解析成非字符串——加引号锁语义
    }
  }
  return false;
}
