// workspace_edit 工具卡「变更」红绿 diff 块。零 diff 算法——old_string/new_string 本就是
// 替换对，行级展开即得红绿体（先全部 - 行后全部 + 行）；不复用 MarkdownCodeText（@Require
// 文档身份两枚，工具卡无此对象），只与其同源消费 Theme.DIFF_* 固定色（防两处漂移，单源见
// Theme 注释）。数据源 = toolInputJson 的 old_string/new_string（落库回放同源，历史卡天然
// 可用）；展示截断走本件自己的上限（数据有界红线），不撞 markdown 链 32K 高亮预算——本件
// 不调用 markdown 词法。★ 字体口径（2026-11-04 字体补接笔）：行区与行号列呈代码原文，随
// **代码字体**（原写死 monospace 常量，改代码字体时不跟）；+N/-M 统计行与「还有 N 行未显示」
// 提示行是人话说明，随**正文字体**。派生纯函数区（本注释至组件声明前）零 ArkUI 依赖，供 Node
// 断言源内提取直跑（assert-tool-domain 348 组）；路由内工具名一律字符串字面量判——本区零跨件
// import 为红线（348 组提取副本直跑，引外部常量即 ReferenceError）。
// 回执 diff 三族（键组由各执行器经 ToolContracts 单源组装/截断）：①set/update 写向回执带
// oldValue/newValue 键；②纯文本回执走附加式「原句逐字保留 + 尾行单行紧凑 JSON」；③
// workspace_write / mount_write 覆盖回执写前读旧文产尾行摘录对（oldExcerpt/newExcerpt；
// 旧文超门槛走 diffSkipped + 行数对）。路由清单见 toolDiffForCard 注释。
import { isCodeLineNumbersEnabled } from '../../common/AppPreferences';
import { cardDescColor, DIFF_ADDITION_COLOR, DIFF_ADDITION_LINE_BG,
  DIFF_DELETION_COLOR, DIFF_DELETION_LINE_BG } from '../../common/Theme';
import { FONT_BODY_DEFAULT, FONT_CODE_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY,
  PREF_FONT_LIB_KEY, bodyFontFamily, codeFontFamily } from '../../common/ChatFont';

// 展示截断上限（每侧行数与单行字符数；统计行恒反映全文总行数，截断只作用于展示行）
export const TOOL_DIFF_MAX_ROWS_PER_SIDE: number = 100;
export const TOOL_DIFF_MAX_ROW_CHARS: number = 1000;

// diff 展示行（kind = deletion/addition；text = 行原文，不含 +/− 前缀——前缀由渲染层拼）
export interface ToolDiffRow {
  kind: string;
  text: string;
}

// diff 视图：统计行（+N -M）+ 展示行列表 + 截断未展示行数（提示行）
export interface ToolDiffView {
  deletions: number;
  additions: number;
  rows: ToolDiffRow[];
  hiddenRows: number;
}

// 行切分：CRLF 归一到 LF 后按 LF 切；空串 = 零行（无行可显）
export function splitDiffLines(source: string): string[] {
  if (source === '') {
    return [];
  }
  return source.replace(/\r\n/g, '\n').split('\n');
}

// 单行字符截断：超限裁到上限并缀省略号（全文原文仍可从原始面板复制）
export function clipDiffLine(line: string, maxChars: number): string {
  if (line.length <= maxChars) {
    return line;
  }
  return line.substring(0, maxChars) + '…';
}

// 派生纯函数：old/new 行级展开 → 红绿视图。行序 = 先全部旧串行（-）后全部新串行（+），
// 各按原序；每侧展示行数独立截断（旧串巨长时不吞掉全部 + 行）；统计恒为全文总行数。
export function deriveToolDiffRows(oldString: string, newString: string,
  maxRowsPerSide: number, maxRowChars: number): ToolDiffView {
  const oldLines: string[] = splitDiffLines(oldString);
  const newLines: string[] = splitDiffLines(newString);
  const oldShown: number = Math.min(oldLines.length, maxRowsPerSide);
  const newShown: number = Math.min(newLines.length, maxRowsPerSide);
  const rows: ToolDiffRow[] = [];
  for (const line of oldLines.slice(0, oldShown)) {
    rows.push({ kind: 'deletion', text: clipDiffLine(line, maxRowChars) });
  }
  for (const line of newLines.slice(0, newShown)) {
    rows.push({ kind: 'addition', text: clipDiffLine(line, maxRowChars) });
  }
  return {
    deletions: oldLines.length,
    additions: newLines.length,
    rows: rows,
    hiddenRows: (oldLines.length - oldShown) + (newLines.length - newShown)
  };
}

// 工具卡入口解析：toolInputJson → diff 视图。坏 JSON / 缺 old_string 或 new_string /
// 字段非串 / 两串全空（无变更可显）一律回 null，卡面零渲染。
export function workspaceEditDiffFromInput(inputJson: string, maxRowsPerSide: number,
  maxRowChars: number): ToolDiffView | null {
  if (inputJson === '') {
    return null;
  }
  let oldString: string = '';
  let newString: string = '';
  try {
    const parsed = JSON.parse(inputJson) as Record<string, Object>;
    const oldRaw: Object | undefined = parsed['old_string'];
    const newRaw: Object | undefined = parsed['new_string'];
    if (typeof oldRaw !== 'string' || typeof newRaw !== 'string') {
      return null;
    }
    oldString = oldRaw;
    newString = newRaw;
  } catch (e) {
    return null;
  }
  if (oldString === '' && newString === '') {
    return null;
  }
  return deriveToolDiffRows(oldString, newString, maxRowsPerSide, maxRowChars);
}

// ── 泛化回执解析 ──
// 回执尾行 envelope：原句式回执 + '\n' + 单行紧凑 JSON；键组三选一——oldValue/newValue、
// oldExcerpt/newExcerpt、diffSkipped/oldLines/newLines。解析双路：整体即 JSON 对象则直接取
// 键组；整体解析失败则自末行向前逐行试 JSON.parse，首个成对象且含任一键组的行取用（散文行
// 含花括号时 JSON.parse 必败，不误取）。历史回执无键组 → null → 无块零迁移。

// 三元门字符串化（oldValue/newValue 键组；执行器落库值可 string/number/boolean 三型）：
// string 原样 / number 与 boolean 归一 String / 其余（缺键、null、对象、数组）回 null
export function scalarToDiffText(raw: Object | undefined): string | null {
  if (typeof raw === 'string') {
    return raw;
  }
  if (typeof raw === 'number') {
    return String(raw);
  }
  if (typeof raw === 'boolean') {
    return raw ? 'true' : 'false';
  }
  return null;
}

// 键组在场判（任一键在场即认——缺一/坏型交键组提取回 null；坏 envelope 不静默跳过继续
// 向更早的行找，防取错行）
export function hasReceiptDiffKey(rec: Record<string, Object>): boolean {
  return rec['oldValue'] !== undefined || rec['newValue'] !== undefined ||
    rec['oldExcerpt'] !== undefined || rec['newExcerpt'] !== undefined ||
    rec['diffSkipped'] !== undefined || rec['oldLines'] !== undefined ||
    rec['newLines'] !== undefined;
}

// JSON 文本 → 对象（整体解析与逐行试共用的单源）：坏 JSON / 非对象（数组、标量、null）回 null
export function parseJsonRecord(text: string): Record<string, Object> | null {
  try {
    const parsed: Object | undefined = JSON.parse(text) as Object | undefined;
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return null;
    }
    return parsed as Record<string, Object>;
  } catch (e) {
    return null;
  }
}

// 键组提取（按上表组序三选一）：组一 oldValue/newValue 走三元门归一；组二 oldExcerpt/
// newExcerpt 走 string 门（正文摘录本就是文本）；组三 diffSkipped/oldLines/newLines 出
//「行数对」视图（超阈跳过无正文可显——统计行按全文行数如实，行列表与隐藏计数归零）。
// 键组缺一/坏型/双空 → null（零渲染；错误回执 {error:…} 无键组自然落底）
export function receiptKeyGroupDiff(rec: Record<string, Object>, maxRowsPerSide: number,
  maxRowChars: number): ToolDiffView | null {
  const oldRaw: Object | undefined = rec['oldValue'];
  const newRaw: Object | undefined = rec['newValue'];
  if (oldRaw !== undefined || newRaw !== undefined) {
    const oldText: string | null = scalarToDiffText(oldRaw);
    const newText: string | null = scalarToDiffText(newRaw);
    if (oldText === null || newText === null || (oldText === '' && newText === '')) {
      return null;
    }
    return deriveToolDiffRows(oldText, newText, maxRowsPerSide, maxRowChars);
  }
  const oldExcerpt: Object | undefined = rec['oldExcerpt'];
  const newExcerpt: Object | undefined = rec['newExcerpt'];
  if (oldExcerpt !== undefined || newExcerpt !== undefined) {
    if (typeof oldExcerpt !== 'string' || typeof newExcerpt !== 'string') {
      return null;
    }
    if (oldExcerpt === '' && newExcerpt === '') {
      return null;
    }
    return deriveToolDiffRows(oldExcerpt, newExcerpt, maxRowsPerSide, maxRowChars);
  }
  const skipRaw: Object | undefined = rec['diffSkipped'];
  const oldLinesRaw: Object | undefined = rec['oldLines'];
  const newLinesRaw: Object | undefined = rec['newLines'];
  if (skipRaw !== undefined || oldLinesRaw !== undefined || newLinesRaw !== undefined) {
    if (typeof skipRaw !== 'string' || typeof oldLinesRaw !== 'number' ||
      typeof newLinesRaw !== 'number') {
      return null;
    }
    return { deletions: oldLinesRaw, additions: newLinesRaw, rows: [], hiddenRows: 0 };
  }
  return null;
}

// 回执解析入口：output 整体即 JSON 对象 → 直接取键组（取不到即 null，不回退逐行——整体已是
// 合法 JSON 时不存在尾行语义）；否则自末行向前逐行试，首个成对象且含任一键组的行取用；
// 全失败 → null（零渲染）
export function receiptPairDiffFromOutput(output: string, maxRowsPerSide: number,
  maxRowChars: number): ToolDiffView | null {
  if (output === '') {
    return null;
  }
  const whole: Record<string, Object> | null = parseJsonRecord(output);
  if (whole !== null) {
    return receiptKeyGroupDiff(whole, maxRowsPerSide, maxRowChars);
  }
  const lines: string[] = output.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    const line: string = lines[i].trim();
    if (line === '') {
      continue;
    }
    const rec: Record<string, Object> | null = parseJsonRecord(line);
    if (rec !== null && hasReceiptDiffKey(rec)) {
      return receiptKeyGroupDiff(rec, maxRowsPerSide, maxRowChars);
    }
  }
  return null;
}

// 功能模型显示名对拼行（set_functional_model 回执四键 oldProvider/oldModel/provider/model
// 均为执行器写前读的显示名，未配置或行已删 = 空串）：两侧都在场 → 「商 · 模」；缺一侧取
// 在场者；双缺空串（旧侧空 = 未设置，diff 呈全新增，语义如实）
export function joinFunctionalModelPair(providerRaw: Object | undefined,
  modelRaw: Object | undefined): string {
  const provider: string = typeof providerRaw === 'string' ? providerRaw : '';
  const model: string = typeof modelRaw === 'string' ? modelRaw : '';
  if (provider === '') {
    return model;
  }
  if (model === '') {
    return provider;
  }
  return provider + ' · ' + model;
}

// set_functional_model 专用小提取器（回执恒为整体 JSON，无尾行形态）：读四键拼行成对；
// 旧空 = 未设置 → diff 呈全新增；新侧也空（非 set 回执 / 坏回执）→ null
export function functionalModelDiffFromOutput(outputJson: string, maxRowsPerSide: number,
  maxRowChars: number): ToolDiffView | null {
  if (outputJson === '') {
    return null;
  }
  const parsed: Record<string, Object> | null = parseJsonRecord(outputJson);
  if (parsed === null) {
    return null;
  }
  const oldText: string = joinFunctionalModelPair(parsed['oldProvider'], parsed['oldModel']);
  const newText: string = joinFunctionalModelPair(parsed['provider'], parsed['model']);
  if (oldText === '' && newText === '') {
    return null;
  }
  return deriveToolDiffRows(oldText, newText, maxRowsPerSide, maxRowChars);
}

// 工具卡 diff 路由收口（工具名字面量判——零跨件 import 红线，见文件头）：workspace_edit
// 走入参替换对；D2a 六件（edit_system_prompt / edit_title_prompt / manage_prompts /
// manage_providers / manage_models / manage_balance）、D2b 四件（update_calendar_event /
// manage_knowledge / manage_skills / manage_memory）与 D3 两件（workspace_write /
// mount_write 覆盖路尾行摘录键组）走回执通用键组（后两族回执为「原句 + 尾行」附加式，
// 解析侧逐行试 JSON 自然承接）；set_functional_model 走专用四键提取器；其余工具（含纯
// 查询 / 产物族）恒 null——卡面无块零渲染（set_app_preference 一档随写件退役出路由）
export function toolDiffForCard(toolName: string, inputJson: string, outputJson: string,
  maxRowsPerSide: number, maxRowChars: number): ToolDiffView | null {
  if (toolName === 'workspace_edit') {
    return workspaceEditDiffFromInput(inputJson, maxRowsPerSide, maxRowChars);
  }
  if (toolName === 'edit_system_prompt' ||
    toolName === 'edit_title_prompt' || toolName === 'manage_prompts' ||
    toolName === 'manage_providers' || toolName === 'manage_models' ||
    toolName === 'manage_balance' || toolName === 'update_calendar_event' ||
    toolName === 'manage_knowledge' || toolName === 'manage_skills' ||
    toolName === 'manage_memory' || toolName === 'workspace_write' ||
    toolName === 'mount_write') {
    return receiptPairDiffFromOutput(outputJson, maxRowsPerSide, maxRowChars);
  }
  if (toolName === 'set_functional_model') {
    return functionalModelDiffFromOutput(outputJson, maxRowsPerSide, maxRowChars);
  }
  return null;
}

// 「变更」块渲染体：+N -M 统计行 + 红绿行区 + 截断提示行。diff 数据为构造期一次传入的
// 派生视图（落库后不变——普通成员即够，状态最小化，不挂装饰器）；行区键覆盖该行全部
// 可变展示成分（kind + 序位 + 文本，坑 44/80 家族）。每行可选行号列——按侧分别从 1
// 计数、只在显示层；派生纯函数区与 ToolDiffRow/ToolDiffView 字段零改动（348 组精确
// JSON 不受影响）
@Component
export struct ChatToolDiffBlock {
  diff: ToolDiffView = { deletions: 0, additions: 0, rows: [], hiddenRows: 0 };
  // 消息字体三键 @StorageProp 自订阅（2026-11-04 字体补接笔）：diff 行区与行号列呈的是代码
  // 原文 → 随**代码字体**；+N/-M 统计行与「还有 N 行未显示」提示行是说明文字 → 随**正文字体**
  //（判据 = 展示对象是代码还是人话，两域各取自己的档，不共用一套族名）
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_CODE_KEY) fontCodeValue: string = FONT_CODE_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';

  // 正文/代码家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  private resolveCodeFamily(): string {
    return codeFontFamily(this.fontCodeValue, this.fontLibJson);
  }

  // 行号：删除侧/增加侧各自从 1 编号（按当前行之前同类行数量计数）；至少补 2 位，
  // 9→10 不跳列宽；不改派生纯函数区（348 组零外引红线）
  private lineNumberLabel(index: number): string {
    const kind: string = this.diff.rows[index].kind;
    let number: number = 0;
    for (let cursor: number = 0; cursor <= index; cursor++) {
      if (this.diff.rows[cursor].kind === kind) {
        number++;
      }
    }
    const digits: string = number.toString();
    const pad: number = Math.max(0, 2 - digits.length);
    let prefix: string = '';
    for (let cursor: number = 0; cursor < pad; cursor++) {
      prefix += '\u00A0';
    }
    return prefix + digits;
  }

  build() {
    Column({ space: 2 }) {
      Row({ space: 10 }) {
        Text('+' + this.diff.additions)
          .fontSize(11)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(DIFF_ADDITION_COLOR)
        Text('-' + this.diff.deletions)
          .fontSize(11)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(DIFF_DELETION_COLOR)
      }
      ForEach(this.diff.rows, (row: ToolDiffRow, index: number): void => {
        Row({ space: 8 }) {
          if (isCodeLineNumbersEnabled()) {
            Text(this.lineNumberLabel(index))
              .fontSize(13).lineHeight(18).fontFamily(this.resolveCodeFamily())
              .fontColor(cardDescColor()).opacity(0.4).copyOption(CopyOptions.None)
          }
          Text() {
            Span((row.kind === 'addition' ? '+' : '-') + row.text)
              .fontColor(row.kind === 'addition' ? DIFF_ADDITION_COLOR : DIFF_DELETION_COLOR)
              .textBackgroundStyle({ color: row.kind === 'addition' ?
                DIFF_ADDITION_LINE_BG : DIFF_DELETION_LINE_BG })
          }
          .fontSize(13)
          .lineHeight(18)
          .fontFamily(this.resolveCodeFamily())
          .layoutWeight(1)
        }
        .width('100%').alignItems(VerticalAlign.Top)
      }, (row: ToolDiffRow, index: number): string =>
        row.kind + '#' + index.toString() + '#' + row.text)
      if (this.diff.hiddenRows > 0) {
        Text('还有 ' + this.diff.hiddenRows + ' 行未显示')
          .fontSize(11)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
