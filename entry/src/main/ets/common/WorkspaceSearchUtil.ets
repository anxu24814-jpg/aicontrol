// 文件工作区检索纯函数域（自 WorkspaceUtil.ets 外迁独立成件——母件越 1200 硬线；并入工具
// 域会把纯函数拉进 DB/kit 依赖）。域职责：workspace_glob / workspace_grep 的模式编译与
// 匹配、行集扫描、回执组装（执行器与注册面在 ToolWorkspace / ToolTypes）。
// 依赖纪律：唯一 import = WorkspaceUtil（全局单源不设第二份抄写）；零 kit、零 store、零
// 工具域（依赖白名单钉同守）；断言直跑 = assert-workspace-domain 复制本件为 .tmp 副本。
import { WorkspaceFileRow } from './WorkspaceUtil';
import { isWorkspaceDirRow, joinDirName, WORKSPACE_REPLY_BUDGET } from './WorkspaceUtil';

// ── 检索两工具常量（单源纪律——消费方禁散写字面量）──
// glob 命中上限（超限即截断置尾注）
export const WORKSPACE_GLOB_MAX_MATCHES: number = 500;
// grep 单件扫描上限（字节；按落库 size 预判，超限跳过计数）
export const WORKSPACE_GREP_FILE_MAX_BYTES: number = 2 * 1024 * 1024;
// grep 累计扫描字节预算（读前预判 + 读后累计——超即停并回执收窄建议）
export const WORKSPACE_GREP_SCAN_BUDGET_BYTES: number = 4 * 1024 * 1024;
// grep 匹配数缺省上限（limit 非有限正数落本值）
export const WORKSPACE_GREP_DEFAULT_LIMIT: number = 100;
// grep 匹配数硬上限（limit 超本值收到本值——防「命中即停」退化为「扫完为止」的第二道）
export const WORKSPACE_GREP_MAX_LIMIT: number = 500;
// grep 单行内容截断（字符）
export const WORKSPACE_GREP_LINE_MAX_CHARS: number = 500;
// pattern 回显上限（字符）：pattern 是模型可任填输入，回执头部句内嵌原串——不截断则长
// pattern 使回执越过 WORKSPACE_REPLY_BUDGET（外层硬切吞掉命中列表）。截断只改回显，匹配仍用原串
export const WORKSPACE_SEARCH_PATTERN_ECHO_MAX: number = 200;

// pattern 回显取值（超上限截断 + '…'；截点不劈代理对——clipGrepLine 同族）
function echoPattern(pattern: string): string {
  if (pattern.length <= WORKSPACE_SEARCH_PATTERN_ECHO_MAX) {
    return pattern;
  }
  let cut: number = WORKSPACE_SEARCH_PATTERN_ECHO_MAX;
  const prev: number = pattern.charCodeAt(cut - 1);
  if (prev >= 0xD800 && prev <= 0xDBFF) {
    cut -= 1;
  }
  return pattern.substring(0, cut) + '…';
}

// ── glob 与 grep 检索（蓝本 = ZCode 自研 glob→RegExp 五规则与 JS grep 回退引擎；遍历源 =
//    DB 行集内存匹配、零文件 IO——鸿蒙无 ripgrep，与 workspace_list 同源）──

// 正则元字符集（glob 编译与 grep 字面量回退共用的单字符转义表）
const REGEX_META_CHARS: string = '\\^$.*+?()[]{}|';

// 单字符正则转义（元字符加反斜杠；空串原样——charAt 越界防御）
function escapeRegexChar(ch: string): string {
  if (ch === '' || REGEX_META_CHARS.indexOf(ch) < 0) {
    return ch;
  }
  return '\\' + ch;
}

function normalizeGlobPattern(pattern: string): string {
  return pattern.replace(/\\/g, '/').replace(/^\.\//, '');
}

// glob→RegExp 编译（单遍逐字符扫描，锚定 ^…$）：**/ → (?:.*/)?〔跨目录前缀可选〕/ ** →
// .*〔跨目录〕/ * → [^/]*〔不跨 /〕/ ? → [^/] / {a,b} → 备选项逐字符转义不递归编译（{} 内
// * ? 是字面、嵌套按首个 } 截断——蓝本原行为）/ 其余转义。全覆盖 ⇒ 产物恒合法正则；
// new RegExp 再炸由执行器 catch 兜底
export function compileWorkspaceGlob(pattern: string): RegExp {
  const normalized: string = normalizeGlobPattern(pattern);
  let regex: string = '^';
  let index: number = 0;
  while (index < normalized.length) {
    const ch: string = normalized.charAt(index);
    if (ch === '*') {
      const next: string = normalized.charAt(index + 1);
      if (next === '*') {
        if (normalized.charAt(index + 2) === '/') {
          regex += '(?:.*/)?';
          index += 3;
        } else {
          regex += '.*';
          index += 2;
        }
        continue;
      }
      regex += '[^/]*';
      index += 1;
      continue;
    }
    if (ch === '?') {
      regex += '[^/]';
      index += 1;
      continue;
    }
    if (ch === '{') {
      const end: number = normalized.indexOf('}', index + 1);
      if (end > index) {
        const parts: string[] = normalized.substring(index + 1, end).split(',');
        let alternatives: string = '';
        for (let i = 0; i < parts.length; i++) {
          let escaped: string = '';
          for (const c of parts[i]) {
            escaped += escapeRegexChar(c);
          }
          alternatives += (i > 0 ? '|' : '') + escaped;
        }
        regex += '(?:' + alternatives + ')';
        index = end + 1;
        continue;
      }
    }
    regex += escapeRegexChar(ch);
    index += 1;
  }
  regex += '$';
  return new RegExp(regex);
}

// glob 匹配器（模式不含 / 时启用 basename 兜底——相对路径整串或尾段任一命中即真；含 / 只按整串）
export interface WorkspaceGlobMatcher {
  regex: RegExp;
  basenameRegex: RegExp | undefined;
}

export function buildWorkspaceGlobMatcher(pattern: string): WorkspaceGlobMatcher {
  const normalized: string = normalizeGlobPattern(pattern);
  const matcher: WorkspaceGlobMatcher = {
    regex: compileWorkspaceGlob(normalized),
    basenameRegex: normalized.indexOf('/') >= 0 ? undefined : compileWorkspaceGlob(normalized)
  };
  return matcher;
}

// 单候选匹配（relativePath = 相对匹配根的路径；fileName = 尾段——无 / 模式的兜底对象）
export function workspaceGlobMatches(matcher: WorkspaceGlobMatcher, relativePath: string,
  fileName: string): boolean {
  if (matcher.regex.test(relativePath)) {
    return true;
  }
  return matcher.basenameRegex !== undefined && matcher.basenameRegex.test(fileName);
}

// glob 匹配结果（path = 相对工作区根完整路径；目录行的尾 / 由回执层加——排序键不带尾斜杠）
export interface WorkspaceGlobMatch {
  path: string;
  isDir: boolean;
}

export interface WorkspaceGlobResult {
  matches: WorkspaceGlobMatch[]; // 路径字典序，≤ WORKSPACE_GLOB_MAX_MATCHES
  truncated: boolean; // 命中超上限即截断
}

// 行集 glob 匹配（纯 DB 行集零文件 IO）：候选 = dir 段为界的前缀过滤（dir=资料 命中 资料 与
// 资料/2026，不误吞 资料2）；文件行目录行都参与、目录命中输出带尾 /；输出 = 相对工作区根完整
// 路径（模型可直接 read）；路径字典序；超上限截断。目录行缺失由启动对账兜底、不派生前缀目录
export function matchWorkspaceGlob(rows: WorkspaceFileRow[], pattern: string,
  dir: string): WorkspaceGlobResult {
  const matcher: WorkspaceGlobMatcher = buildWorkspaceGlobMatcher(pattern);
  const prefix: string = dir === '' ? '' : dir + '/';
  const pathOrder: string[] = [];
  const dirByPath: Map<string, boolean> = new Map<string, boolean>();
  for (const row of rows) {
    if (dir !== '' && row.dir !== dir && !row.dir.startsWith(prefix)) {
      continue;
    }
    const fullPath: string = joinDirName(row.dir, row.name);
    const relative: string = dir === '' ? fullPath : fullPath.substring(prefix.length);
    if (!workspaceGlobMatches(matcher, relative, row.name)) {
      continue;
    }
    pathOrder.push(fullPath);
    dirByPath.set(fullPath, isWorkspaceDirRow(row));
  }
  pathOrder.sort();
  const truncated: boolean = pathOrder.length > WORKSPACE_GLOB_MAX_MATCHES;
  if (truncated) {
    pathOrder.splice(WORKSPACE_GLOB_MAX_MATCHES);
  }
  const matches: WorkspaceGlobMatch[] = [];
  for (const p of pathOrder) {
    const hit: WorkspaceGlobMatch = { path: p, isDir: dirByPath.get(p) === true };
    matches.push(hit);
  }
  return { matches: matches, truncated: truncated };
}

// 逐行回执收口（glob 与 grep 回执共用：超预算按行截断 + 省略尾注；余量按尾注自身长度预留
//——composeWorkspaceListReply 同族口径，不回改 list）
function clipLinesReply(head: string, lines: string[], tailLines: string[]): string {
  const whole: string[] = [head];
  for (const line of lines) {
    whole.push(line);
  }
  for (const t of tailLines) {
    whole.push(t);
  }
  const text: string = whole.join('\n');
  if (text.length <= WORKSPACE_REPLY_BUDGET) {
    return text;
  }
  const body: string[] = [];
  for (const line of lines) {
    body.push(line);
  }
  for (const t of tailLines) {
    body.push(t);
  }
  const omittedTail: string = '……内容过长已省略，可用更具体的 pattern 或 dir 收窄。';
  const kept: string[] = [head];
  for (let i = 0; i < body.length; i++) {
    if (kept.join('\n').length + body[i].length + 1 >
      WORKSPACE_REPLY_BUDGET - omittedTail.length - 1) {
      kept.push(omittedTail);
      break;
    }
    kept.push(body[i]);
  }
  return kept.join('\n');
}

// glob 回执：命中路径逐行（目录带尾 /）+ 统计与截断尾注；零命中给 workspace_list 指引。
// rowsAtCap = 行集贴读取上限（结果可能不全的如实申报）；pattern 一律经 echoPattern 回显（有界）
export function composeWorkspaceGlobReply(pattern: string, dir: string,
  matches: WorkspaceGlobMatch[], truncated: boolean, rowsAtCap: boolean): string {
  const shown: string = echoPattern(pattern);
  if (matches.length === 0) {
    return '没有匹配「' + shown + '」的文件或文件夹。' +
      '可先用 workspace_list 查看工作区里有哪些文件，再写更准确的模式。';
  }
  const where: string = dir === '' ? '工作区' : '「' + dir + '」目录';
  const head: string = truncated ?
    '在' + where + '按「' + shown + '」匹配较多，以下为前 ' + matches.length +
      ' 项（可用更具体的模式或 dir 收窄）：' :
    '在' + where + '按「' + shown + '」找到 ' + matches.length + ' 项：';
  const lines: string[] = [];
  for (const m of matches) {
    lines.push(m.isDir ? m.path + '/' : m.path);
  }
  const tailLines: string[] = [];
  if (rowsAtCap) {
    tailLines.push('工作区条目较多，以上结果可能不全，可用 dir 收窄后再查。');
  }
  return clipLinesReply(head, lines, tailLines);
}

// grep 正则构造（非法正则回退字面量并置 literal；**不带 g 标志**做逐行 test——规避 lastIndex 状态残留）
export interface WorkspaceGrepRegex {
  regex: RegExp;
  literal: boolean; // true = 原模式未按正则语义匹配，已按字面文本匹配（回执注明）
  // true = 检出嵌套量词等高危形态，主动降级字面量（W2-3 拍板；回执注明降级原因与重试指引）
  risky: boolean;
}

// {n}/{n,}/{n,m} 量词段识别：命中返回闭合 } 的下标（主扫描跳整段）；非法形态返 -1（{ 按字面计——Annex B 同判）
function braceQuantifierEnd(pattern: string, index: number): number {
  let i: number = index + 1;
  while (i < pattern.length && pattern.charAt(i) >= '0' && pattern.charAt(i) <= '9') {
    i += 1;
  }
  if (i === index + 1) {
    return -1; // { 后无数字 = 字面 {
  }
  if (i < pattern.length && pattern.charAt(i) === ',') {
    i += 1;
    while (i < pattern.length && pattern.charAt(i) >= '0' && pattern.charAt(i) <= '9') {
      i += 1;
    }
  }
  return i < pattern.length && pattern.charAt(i) === '}' ? i : -1;
}

// 指定位是否量词起点（hasNestedQuantifier 辅助：判「组闭合后是否紧跟量词」）
function isQuantifierStart(pattern: string, index: number): boolean {
  if (index >= pattern.length) {
    return false;
  }
  const ch: string = pattern.charAt(index);
  return ch === '*' || ch === '+' || ch === '?' ||
    (ch === '{' && braceQuantifierEnd(pattern, index) >= 0);
}

// 嵌套量词高危形态检测（W2-3 拍板）：量词作用于「以量词收尾的分组」（(a+)+ 家族，含组闭合
// 传播的 ((a+))+）对长重复行是指数回溯，主线程逐行 test 可冻结 UI——三重闸只限 IO 量、对
// 单行 CPU 回溯无界，故编译前静态检出即降级字面量（扫描时转义对/字符类整体跳过、非法量词
// 段按字面 { 计）。★ 保守非穷尽：交替重叠（(a|aa)+）不在判据内；误判恒 = 过度降级（安全侧）
function hasNestedQuantifier(pattern: string): boolean {
  // 上一原子的「尾部量词化」状态：字面原子 = 是否跟量词；组闭合 = 组尾传播值
  let lastQuantified: boolean = false;
  let index: number = 0;
  while (index < pattern.length) {
    const ch: string = pattern.charAt(index);
    if (ch === '\\') {
      index += 2; // 转义对整体跳过（末尾孤立 \ 越出由循环条件收）
      continue;
    }
    if (ch === '[') {
      index += 1;
      while (index < pattern.length && pattern.charAt(index) !== ']') {
        if (pattern.charAt(index) === '\\') {
          index += 1;
        }
        index += 1;
      }
      index += 1; // 字符类整体跳过
      lastQuantified = false;
      continue;
    }
    if (ch === '(') {
      lastQuantified = false; // 进组：组内尚未有原子
      index += 1;
      continue;
    }
    if (ch === ')') {
      const innerTail: boolean = lastQuantified;
      if (innerTail && isQuantifierStart(pattern, index + 1)) {
        return true; // 主判据：组尾量词收尾 + 组后紧跟量词
      }
      lastQuantified = innerTail; // 组作为外层新原子，传播组尾状态（覆盖 ((a+))+）
      index += 1;
      continue;
    }
    if (ch === '*' || ch === '+' || ch === '?') {
      lastQuantified = true;
      index += 1;
      continue;
    }
    if (ch === '{') {
      const end: number = braceQuantifierEnd(pattern, index);
      if (end >= 0) {
        lastQuantified = true;
        index = end + 1;
      } else {
        lastQuantified = false; // 字面 {
        index += 1;
      }
      continue;
    }
    lastQuantified = false; // 普通字符 = 新原子起点
    index += 1;
  }
  return false;
}

// 字面量正则构建（非法回退与高危降级两出口共用——原样逐字符转义）
function literalWorkspaceRegex(pattern: string, flags: string): RegExp {
  let escaped: string = '';
  for (const ch of pattern) {
    escaped += escapeRegexChar(ch);
  }
  return new RegExp(escaped, flags);
}

export function buildWorkspaceGrepRegex(pattern: string, ignoreCase: boolean): WorkspaceGrepRegex {
  const flags: string = ignoreCase ? 'i' : '';
  // ★ W2-3 拍板：高危形态先于编译检出即降级字面量；不引 TaskPool、不动三重闸（拍板范围）
  if (hasNestedQuantifier(pattern)) {
    const risky: WorkspaceGrepRegex =
      { regex: literalWorkspaceRegex(pattern, flags), literal: true, risky: true };
    return risky;
  }
  try {
    const built: WorkspaceGrepRegex = { regex: new RegExp(pattern, flags), literal: false, risky: false };
    return built;
  } catch {
    const fallback: WorkspaceGrepRegex =
      { regex: literalWorkspaceRegex(pattern, flags), literal: true, risky: false };
    return fallback;
  }
}

// grep limit 归一（非有限正数落缺省；超硬上限收到硬上限——两道防退化，方案 §4.4）
export function normalizeWorkspaceGrepLimit(limit: number): number {
  if (!Number.isFinite(limit) || limit <= 0) {
    return WORKSPACE_GREP_DEFAULT_LIMIT;
  }
  return Math.min(Math.floor(limit), WORKSPACE_GREP_MAX_LIMIT);
}

// grep 单行内容截断（截点不劈代理对）
function clipGrepLine(line: string): string {
  if (line.length <= WORKSPACE_GREP_LINE_MAX_CHARS) {
    return line;
  }
  let cut: number = WORKSPACE_GREP_LINE_MAX_CHARS;
  const prev: number = line.charCodeAt(cut - 1);
  if (prev >= 0xD800 && prev <= 0xDBFF) {
    cut -= 1;
  }
  return line.substring(0, cut);
}

// grep 单件命中（line 1-based；text 已截 500）
export interface WorkspaceGrepHit {
  path: string;
  line: number;
  text: string;
}

// grep 扫描统计与结果（三重闸的判定产物——回执分母 = candidateCount 闸前口径）
export interface WorkspaceGrepScanResult {
  hits: WorkspaceGrepHit[];
  truncated: boolean; // 命中达 limit 即停（可能还有更多）
  stoppedByBudget: boolean; // 累计扫描预算即停
  scannedCount: number; // 实际读入扫描件数
  candidateCount: number; // 候选件数（dir 过滤后的 text 档）
  skippedOversize: number; // 单件超 2MB 跳过
  skippedBinary: number; // 含 NUL 判二进制跳过
  skippedUnreadable: number; // 读失败跳过
}

// 行集 grep 扫描（只读纯函数——文件读入经 reader 注入，全部闸与统计在此判定；reader 抛错 =
// 单件读失败跳过不中断）。候选 = kind='text' 文件行 + dir 段为界前缀过滤。三重闸：单件 2MB /
// 累计扫描 4MB / 匹配数 limit〔命中即停〕。路径输出 = dir/name 相对形态（与 workspace_list 同词汇）
export function scanWorkspaceGrep(rows: WorkspaceFileRow[], dir: string, regex: RegExp,
  limit: number, reader: (localPath: string) => string): WorkspaceGrepScanResult {
  const result: WorkspaceGrepScanResult = { hits: [], truncated: false, stoppedByBudget: false,
    scannedCount: 0, candidateCount: 0, skippedOversize: 0, skippedBinary: 0,
    skippedUnreadable: 0 };
  const prefix: string = dir === '' ? '' : dir + '/';
  // 候选集先整表过滤、分母一次赋值——原实现循环内 ++，命中即停时其后候选未计数、回执分母
  // 缩水（真机实锤）；分母 = 闸前候选全量，跳过/已扫描计数保持「停前实际触达」口径
  const candidates: WorkspaceFileRow[] = [];
  for (const row of rows) {
    if (isWorkspaceDirRow(row) || row.kind !== 'text') {
      continue;
    }
    if (dir !== '' && row.dir !== dir && !row.dir.startsWith(prefix)) {
      continue;
    }
    candidates.push(row);
  }
  result.candidateCount = candidates.length;
  let budget: number = 0;
  for (const row of candidates) {
    if (row.size > WORKSPACE_GREP_FILE_MAX_BYTES) {
      result.skippedOversize++;
      continue;
    }
    if (budget + row.size > WORKSPACE_GREP_SCAN_BUDGET_BYTES) {
      result.stoppedByBudget = true;
      break;
    }
    let content: string;
    try {
      content = reader(row.localPath);
    } catch {
      result.skippedUnreadable++;
      continue;
    }
    budget += row.size;
    result.scannedCount++;
    if (content.indexOf('\u0000') >= 0) {
      result.skippedBinary++;
      continue;
    }
    const lines: string[] = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (regex.test(lines[i])) {
        const hit: WorkspaceGrepHit = { path: joinDirName(row.dir, row.name), line: i + 1,
          text: clipGrepLine(lines[i]) };
        result.hits.push(hit);
        if (result.hits.length >= limit) {
          result.truncated = true;
          break;
        }
      }
    }
    if (result.truncated) {
      break;
    }
  }
  return result;
}

// grep 回执：每命中一行「路径:行号: 内容」+ 扫描统计与截断尾注；literal 回退注明；零命中分
// 两态；按行收口。pattern 一律经 echoPattern 回显。risky（尾部可选参，缺省 false——存量
// 直跑调用零波及）= 高危降级口，回执分列注明降级原因与重试指引
export function composeWorkspaceGrepReply(pattern: string, literal: boolean, dir: string,
  scan: WorkspaceGrepScanResult, rowsAtCap: boolean, risky: boolean = false): string {
  const scope: string = dir === '' ? '工作区' : '「' + dir + '」目录';
  const shown: string = echoPattern(pattern);
  if (scan.hits.length === 0) {
    let zero: string = scan.candidateCount === 0 ?
      scope + '没有可搜索的文本文件。' :
      '在' + scope + '的 ' + scan.candidateCount + ' 个文本文件里没有找到匹配「' + shown +
        '」的内容。';
    if (risky) {
      zero = '「' + shown + '」的正则写法过于复杂，已按字面文本匹配。' +
        '可换更简单的正则写法后重试。' + zero;
    } else if (literal) {
      zero = '「' + shown + '」不是有效的正则表达式，已按字面文本匹配。' + zero;
    }
    return zero;
  }
  const head: string = scan.truncated ?
    '匹配较多，以下为前 ' + scan.hits.length + ' 处（可用更具体的 pattern 或 dir 收窄）：' :
    '找到 ' + scan.hits.length + ' 处匹配：';
  const lines: string[] = [];
  for (const hit of scan.hits) {
    lines.push(hit.path + ':' + hit.line + ': ' + hit.text);
  }
  const tailLines: string[] = [];
  if (risky) {
    tailLines.push('「' + shown + '」的正则写法过于复杂，已按字面文本匹配。' +
      '可换更简单的正则写法后重试。');
  } else if (literal) {
    tailLines.push('「' + shown + '」不是有效的正则表达式，已按字面文本匹配。');
  }
  const skipped: number = scan.skippedOversize + scan.skippedBinary + scan.skippedUnreadable;
  let statLine: string = '共扫描 ' + scan.scannedCount + '/' + scan.candidateCount + ' 个文本文件';
  if (skipped > 0) {
    statLine += '，跳过 ' + skipped + ' 个（超限 ' + scan.skippedOversize + '、二进制 ' +
      scan.skippedBinary + '、读取失败 ' + scan.skippedUnreadable + '）';
  }
  tailLines.push(statLine + '。');
  if (scan.stoppedByBudget) {
    tailLines.push('已达到扫描量上限停止，可用 dir 收窄范围或用更具体的 pattern。');
  }
  if (rowsAtCap) {
    tailLines.push('工作区条目较多，以上结果可能不全，可用 dir 收窄后再查。');
  }
  return clipLinesReply(head, lines, tailLines);
}

