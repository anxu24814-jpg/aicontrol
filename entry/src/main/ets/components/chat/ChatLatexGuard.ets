// 流式 LaTeX 公式守卫（2026-08-26 夜间任务新增，P0-2）：guardStreamingLatex(text)——
// Markdown 内容喂给 @lidary/markdown 前，把**未闭合**的数学定界符尾部 `$` 转义为 `\$`
//（库按普通文本显示原文），闭合后自然恢复渲染（守卫每次渲染对当前全量文本重跑，
// 配对成立即零改动——幂等，见注释尾「幂等性」）。
// 扫描规则（代码区跳过）：
// · 围栏代码块：```/~~~ 开头行（行首 ≤3 空格）切换围栏态，围栏内整行跳过——**半截
//   围栏**（流式中）同样保护：开栏后所有行视为代码，$ 不转义；
// · 行内代码 span：反引号 run 开闭配对（同长度闭合，CommonMark 语义简化版），
//   span 内 $ 跳过；未闭合 span（流式中）后续视为代码同样跳过；span 态跨行延续；
// · 反斜杠转义：`\$` 为字面 $ 非定界符（扫描跳过——同时保证幂等：守卫产物 `\$`
//   重跑不会被再次转义）；
// · 定界符识别：`$$` 优先于两个 `$`（贪心双字符）；配对按 token 序偶交换
//   （t0-t1、t2-t3…），**跨行配对**（`$$\n…\n$$` 有效——token 收集全文统一进行）。
// 未闭合处置：token 总数为奇 → 自最后一个 token（即未闭合 opener）起，尾部所有 `$`
// 逐字符转义（`$$` → `\$\$`）。
// 取舍（真机项记录）：偶数 token 的假阳性配对（如货币 "$5 和 $6"）不改——那是库既有
// 行为，守卫只管未闭合；行内 $ 跨行闭合依赖全文 token 统一计数（保守但幂等安全）。
// ★ 本文件与 md-spec-test/src/latex-guard-test.ts 为同一算法双实现（ArkTS 无法进
//   node）——改此处必同步改测试侧（两文件头注释互指；全文版 + 增量版两节同规）。
import { ChatMessage } from './ChatMessageCompose';

export function guardStreamingLatex(text: string): string {
  if (text.indexOf('$') < 0) {
    return text;
  }
  const lines: string[] = text.split('\n');
  let offset: number = 0;
  let inFence: boolean = false;
  let codeRun: number = 0; // 未闭合行内代码 span 的反引号长度（跨行延续）
  const tokens: number[] = []; // 代码区外全部数学定界符的全局起始偏移
  for (const line of lines) {
    const lineStart: number = offset;
    offset += line.length + 1;
    if (isFenceLine(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue;
    }
    let j: number = 0;
    while (j < line.length) {
      const ch: string = line.charAt(j);
      if (ch === '\\') {
        j += 2; // 转义下一字符（\$ 字面量；行尾 \ 越界 +2 安全）
        continue;
      }
      if (ch === '`') {
        let run: number = 1;
        while (j + run < line.length && line.charAt(j + run) === '`') {
          run++;
        }
        if (codeRun === 0) {
          codeRun = run;
        } else if (run === codeRun) {
          codeRun = 0;
        }
        j += run;
        continue;
      }
      if (ch === '$') {
        if (codeRun > 0) {
          j++;
          continue;
        }
        tokens.push(lineStart + j);
        j += (j + 1 < line.length && line.charAt(j + 1) === '$') ? 2 : 1;
        continue;
      }
      j++;
    }
  }
  // ★ 二三〇改（任务 F 公式失败回退,确定性失败源第一类）：空公式配对段（`$ $`/
  // `$$ $$`/`$\n$`——定界符间内容 trim 空）转义为原文显示——空公式喂 liblatex 必然
  // 无意义渲染（无字形可产）,应用层预判直接回退;从后往前转义保偏移稳定（尾部处理
  // 复用未闭合同款 replace）。非空假阳性配对（货币 "$5 和 $6"）维持库既有行为不转。
  // ★ 二四〇改语义修正：空段判定与 token 总数奇偶**解耦**（原实现 if/else 互斥——
  // 奇数时跳过全部空段判定,「$ $ 已闭合 + 后开未闭合」流式组合下空段漏转,fuzz 对照
  // 实锤;转义本意只看段本身是否空,与尾部无关。增量版按对即时判定天然解耦,两版同此;
  // 26 断言基线无奇数+空段组合案例,零回归）
  const escapes: number[] = [];
  for (let i = 0; i + 1 < tokens.length; i += 2) {
    const openAt: number = tokens[i];
    const delimLen: number = text.startsWith('$$', openAt) ? 2 : 1;
    const body: string = text.substring(openAt + delimLen, tokens[i + 1]);
    if (body.trim() === '') {
      escapes.push(i); // 空段：opener 与 closer 都转义
      escapes.push(i + 1);
    }
  }
  if (tokens.length % 2 === 1) {
    escapes.push(tokens.length - 1); // 未闭合尾 token 整段转义（原逻辑;与空段点不相交——
                                     // 尾 token 不参与配对,i+1<len 上限保证）
  }
  if (escapes.length === 0) {
    return text; // 全配对非空（含 0）——零改动（幂等：闭合后自然恢复）
  }
  let out: string = text;
  // 降序逐 token 处理：未闭合 = 该 token 起尾部全转义;空段 = 定界符本身转义
  const sorted: number[] = escapes.slice().sort((a: number, b: number): number => b - a);
  for (const ti of sorted) {
    const at: number = tokens[ti];
    if (ti === tokens.length - 1 && tokens.length % 2 === 1) {
      out = out.substring(0, at) + out.substring(at).replace(/\$/g, '\\$');
    } else {
      const len: number = out.startsWith('$$', at) ? 2 : 1;
      // $$ → \$\$(逐 $ 转义,与未闭合路径 replace 同语义——只转首个 \$ 会留裸 $ 再配对)
      const escaped: string = len === 2 ? '\\$\\$' : '\\$';
      out = out.substring(0, at) + escaped + out.substring(at + len);
    }
  }
  return out;
}

// 围栏行判定：行首 ≤3 空格 + ≥3 个 ` 或 ~（CommonMark 简化——开栏字符不校验闭栏
// 同字符，守卫场景宁多保护不多放行；info string 忽略）
function isFenceLine(line: string): boolean {
  let i: number = 0;
  while (i < line.length && i < 3 && line.charAt(i) === ' ') {
    i++;
  }
  const head: string = line.substring(i, i + 3);
  return head === '```' || head === '~~~';
}

// ═══════════ 增量守卫（二四〇改，路线图 §8.2-4a 阶段 1 ②）═══════════
// StreamingLatexGuard.feed(text)——全文入全文出，输出与 guardStreamingLatex **逐字节
// 等价**，但每轮只扫增量（每字符摊还扫描 ≤2 次：先作为上轮「半行」扫一次，行补全后
// 回滚重扫一次），消除主线程每帧 O(全文) 扫描（流式帧频 ~10/s × 全文长的放大项）。
//
// 等价性设计（正确性锚点 = latex-guard-test.ts 增量节「逐帧喂 ≡ 全文版」逐帧断言 +
// fuzz 对照；改本类必同步测试侧同构移植）：
// · 判定态：inFence/codeRun（与全文版同语义）；pendingOpener/pendingDelim = 全文版
//   偶链配对的栈深-1 形式（顺序配对 t0-t1,t2-t3… 等价）；settleAt/outPrefix = 定稿区
//   （[0..settleAt) 的输出已确定不再变化——opener 前文本/非空配对段/轮末余段原样并入，
//   空段定界符转义后并入）；tailOut/tailMark = 未闭合尾段转义输出缓存——尾部全 $ 盲转
//   对字符串拼接封闭 ⇒ tailOut += esc(增量段) 等价于全文版「尾 token 起全文 replace」；
// · 配对闭合即「恢复」：非空段弃 tailOut 取输入原样（= 全文版重新判定 escapes 为空
//   → 零改动）；空段转义 opener+closer 两定界符（body trim 空 = 无 $ 无 codeRun，
//   与全文版降序逐点替换结果逐字节相同——每个转义点只改局部、区间外原样）；
// · 半行对齐：全文版对 split 后最后一段（无换行的文末半行）也扫描，增量版同样把半行
//   当完整行扫——下轮该行补长时**回滚重扫**：判定态与输出（outPrefix/tailOut 截断）
//   恢复到半行扫描前快照，半行+增量整体重扫（每轮回滚量 = 上轮增量，摊还线性）；
//   半行超 HALF_LINE_MAX 走全文重扫防无换行长文 O(n²) 退化；
// · 前缀不单调（回放/reset/终态全量覆盖缩短/组件复用换消息）→ resetState 全文重扫
//   兜底——任何输入下输出与全文版恒等，增量化只影响成本不影响结果。
//
// 状态挂接：guardStreamingLatexLive(msg) 按消息 id 持有实例（模块级 Map FIFO 上限
// LIVE_GUARD_LIMIT——不入 ChatMessageItem（贴线 400 行）不入数据源（守卫属渲染辅助
// 域）；消息释放由上限逐出兜底，outPrefix 与消息文本同量级、条目小有界）。keyGenerator
// 键恒定（msg.id）下同一消息每轮 feed 同一实例命中增量路径。
const LIVE_GUARD_LIMIT: number = 64;
// 半行回滚重扫上限：超过则全文重扫（无换行超长尾段场景的 O(n²) 防线——每帧成本
// 回到 O(n) 全文扫描量级，不劣于增量化前）
const HALF_LINE_MAX: number = 4096;

function escAll(seg: string): string {
  return seg.replace(/\$/g, '\\$');
}

// 定界符转义：$$ → \$\$（逐 $ 转义防残留裸 $ 再配对）、$ → \$（与全文版同语义）
function escToken(text: string, at: number): string {
  return text.startsWith('$$', at) ? '\\$\\$' : '\\$';
}

export class StreamingLatexGuard {
  private prevIn: string = '';        // 上一轮输入全文（前缀单调性判定 + 增量提取锚点）
  private outPrefix: string = '';     // 定稿输出（[0..settleAt) 的输出，含已定转义段）
  private settleAt: number = 0;       // 定稿点（输入坐标；此前的输出不再变化）
  private inFence: boolean = false;
  private codeRun: number = 0;
  private pendingOpener: number = -1; // 未配对 opener 输入偏移（-1 = 无/偶配对态）
  private pendingDelim: number = 1;   // opener 定界长度（1/2）
  private tailOut: string = '';       // 未闭合尾段转义输出（盲转义对拼接封闭）
  private tailMark: number = 0;       // tailOut 已覆盖的输入终点（下次从此续 esc）
  // 半行快照（回滚重扫；半行 = 文末最后一个 \n 之后的未决段）
  private snapValid: boolean = false;
  private snapFence: boolean = false;
  private snapCodeRun: number = 0;
  private snapOpener: number = -1;
  private snapDelim: number = 1;
  private snapSettle: number = 0;
  private snapOutLen: number = 0;
  private snapTailLen: number = 0;
  private snapTailMark: number = 0;
  private snapHalfStart: number = 0;  // 半行绝对起点（回滚后重扫 work 的起点）

  feed(text: string): string {
    if (this.prevIn !== '' && !text.startsWith(this.prevIn)) {
      this.resetState(); // 非前缀单调：清状态，本输入走全文重扫（prevIn 归零后全当增量）
    }
    if (text === this.prevIn) {
      return this.pendingOpener >= 0 ? this.outPrefix + this.tailOut : this.outPrefix;
    }
    let work: string;
    let workStart: number;
    if (this.snapValid) {
      const halfLen: number = this.prevIn.length - this.snapHalfStart;
      if (halfLen > HALF_LINE_MAX) {
        this.resetState();
        work = text;
        workStart = 0;
      } else {
        this.inFence = this.snapFence;
        this.codeRun = this.snapCodeRun;
        this.pendingOpener = this.snapOpener;
        this.pendingDelim = this.snapDelim;
        this.settleAt = this.snapSettle;
        this.outPrefix = this.outPrefix.substring(0, this.snapOutLen);
        this.tailOut = this.tailOut.substring(0, this.snapTailLen);
        this.tailMark = this.snapTailMark;
        work = this.prevIn.substring(this.snapHalfStart) + text.substring(this.prevIn.length);
        workStart = this.snapHalfStart;
      }
    } else {
      work = text.substring(this.prevIn.length);
      workStart = this.prevIn.length;
    }
    this.prevIn = text;
    // 行分段：完整行区（至最后一个 \n 含）+ 文末半行——**半行也扫**（与全文版「split
    // 最后一段参与判定」对齐；快照落完整行区扫完之后、半行扫描之前，供下轮回滚）
    const lastNl: number = work.lastIndexOf('\n');
    if (lastNl >= 0) {
      this.scan(work, 0, lastNl + 1, workStart, text);
      if (lastNl + 1 < work.length) {
        this.takeSnapshot(workStart + lastNl + 1);
        this.scan(work, lastNl + 1, work.length, workStart, text);
      } else {
        this.snapValid = false; // 以 \n 结尾：无半行，下轮无需回滚
      }
    } else {
      this.takeSnapshot(workStart); // work 全为半行：先落快照再扫
      this.scan(work, 0, work.length, workStart, text);
    }
    if (this.pendingOpener >= 0) {
      // 尾态：tailOut 续 esc 至文末（盲转义对拼接封闭——增量段整体 replace 即逐字符
      // replace 的拼接，与全文版「尾 token 起全文 replace」逐字节等价）
      if (this.tailMark < text.length) {
        this.tailOut += escAll(text.substring(this.tailMark, text.length));
        this.tailMark = text.length;
      }
      return this.outPrefix + this.tailOut;
    }
    if (this.settleAt < text.length) {
      // 全配对：余段原样定稿（= 全文版 escapes 为空零改动）
      this.outPrefix += text.substring(this.settleAt, text.length);
      this.settleAt = text.length;
    }
    return this.outPrefix;
  }

  private resetState(): void {
    this.prevIn = '';
    this.outPrefix = '';
    this.settleAt = 0;
    this.inFence = false;
    this.codeRun = 0;
    this.pendingOpener = -1;
    this.pendingDelim = 1;
    this.tailOut = '';
    this.tailMark = 0;
    this.snapValid = false;
  }

  private takeSnapshot(halfStart: number): void {
    this.snapValid = true;
    this.snapFence = this.inFence;
    this.snapCodeRun = this.codeRun;
    this.snapOpener = this.pendingOpener;
    this.snapDelim = this.pendingDelim;
    this.snapSettle = this.settleAt;
    this.snapOutLen = this.outPrefix.length;
    this.snapTailLen = this.tailOut.length;
    this.snapTailMark = this.tailMark;
    this.snapHalfStart = halfStart;
  }

  // 逐行扫描 [from..to)（work 内下标；absBase = work 在全文的**整体**起点——行绝对
  // 坐标 = absBase + work 内下标，两段调用统一传 workStart，勿传段起点防二次累加）
  private scan(work: string, from: number, to: number, absBase: number, fullText: string): void {
    let lineStart: number = from;
    while (lineStart < to) {
      const nl: number = work.indexOf('\n', lineStart);
      const lineEnd: number = (nl >= 0 && nl < to) ? nl : to;
      this.scanLine(work, lineStart, lineEnd, absBase + lineStart, fullText);
      lineStart = lineEnd + 1; // \n 原样通过：输出由区间拼接/tailOut esc 段覆盖
    }
  }

  // 单行字符扫描（与全文版循环逐语义一致：\ → ` → $；token 位置 = absBase + 行内偏移）
  private scanLine(work: string, ls: number, le: number, absLineStart: number,
    fullText: string): void {
    const line: string = work.substring(ls, le);
    if (isFenceLine(line)) {
      this.inFence = !this.inFence;
      return;
    }
    if (this.inFence) {
      return;
    }
    let j: number = 0;
    while (j < line.length) {
      const ch: string = line.charAt(j);
      if (ch === '\\') {
        j += 2; // 行尾 \ 越界 +2 安全（与全文版同）
        continue;
      }
      if (ch === '`') {
        let run: number = 1;
        while (j + run < line.length && line.charAt(j + run) === '`') {
          run++;
        }
        if (this.codeRun === 0) {
          this.codeRun = run;
        } else if (run === this.codeRun) {
          this.codeRun = 0;
        }
        j += run;
        continue;
      }
      if (ch === '$') {
        if (this.codeRun > 0) {
          j++;
          continue;
        }
        const isDouble: boolean = j + 1 < line.length && line.charAt(j + 1) === '$';
        this.onToken(absLineStart + j, isDouble ? 2 : 1, fullText);
        j += isDouble ? 2 : 1;
        continue;
      }
      j++;
    }
  }

  // token 事件：opener 开启（定稿 opener 前未判区 + 开尾段）或 closer 配对（空段转义 /
  // 非空段原样定稿）。配对结构 = 全文版偶链顺序配对（栈深 1）
  private onToken(at: number, delim: number, fullText: string): void {
    if (this.pendingOpener < 0) {
      this.outPrefix += fullText.substring(this.settleAt, at);
      this.settleAt = at;
      this.pendingOpener = at;
      this.pendingDelim = delim;
      this.tailOut = '';
      this.tailMark = at;
      return;
    }
    const body: string = fullText.substring(this.pendingOpener + this.pendingDelim, at);
    if (body.trim() === '') {
      // 空段：两定界符转义（body trim 空 = 无 $ 无 codeRun，原样保留空白）
      this.outPrefix += escToken(fullText, this.pendingOpener) + body + escToken(fullText, at);
    } else {
      // 非空段：整段原样定稿（含 opener..closerEnd——「闭合后自然恢复渲染」）
      this.outPrefix += fullText.substring(this.pendingOpener, at + delim);
    }
    this.settleAt = at + delim;
    this.pendingOpener = -1;
  }
}

// 增量守卫实例仓（按消息 id；FIFO 上限逐出——keyGenerator 键恒定使同一消息每轮命中
// 同一实例；上限兜底消息释放后的残留，条目 ≈ 消息文本同量级、有界）
const liveGuards: Map<string, StreamingLatexGuard> = new Map();

// 渲染入口（ChatMessageItem 消费）：按消息增量化。语义承诺 = 返回值与
// guardStreamingLatex(msg.text) 恒等（增量失败路径自动退全文重扫）
export function guardStreamingLatexLive(msg: ChatMessage): string {
  let guard: StreamingLatexGuard | undefined = liveGuards.get(msg.id);
  if (guard === undefined) {
    guard = new StreamingLatexGuard();
    liveGuards.set(msg.id, guard);
    if (liveGuards.size > LIVE_GUARD_LIMIT) {
      const excess: number = liveGuards.size - LIVE_GUARD_LIMIT;
      const dropKeys: string[] = [];
      let dropped: number = 0;
      for (const k of liveGuards.keys()) {
        if (dropped >= excess) {
          break;
        }
        dropKeys.push(k);
        dropped++;
      }
      for (const k of dropKeys) {
        liveGuards.delete(k);
      }
    }
  }
  return guard.feed(msg.text);
}
