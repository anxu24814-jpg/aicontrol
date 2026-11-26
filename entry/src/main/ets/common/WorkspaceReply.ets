// 工作区工具回执组装域（自 WorkspaceUtil.ets 拆出）：list / read / write / write_xlsx /
// import 五路回执与目录四工具回执 + 覆盖注记族的纯函数单源——把执行器结构化结果组装成模型
// 面回执文本（预算收口 ≤8192、行级续读指针与覆盖注记措辞全部在此收口）。消费方 =
// ToolWorkspace.ets 与 ToolCodeExec.ets（复用 composeWorkspaceReadReply）。为何不并入主件
// 或既有拆分件：回执措辞与预算证明链的单源地位（主件为零 import 断言直跑叶子，拆分依据
// 见变更记录拆分笔）。

import { WorkspaceDirBrief, WorkspaceListBrief } from './WorkspaceUtil';
import { clipWorkspaceReply, formatWorkspaceSize, formatWorkspaceTime, joinDirName, sourceLabel,
  WORKSPACE_DOC_WARNING_MAX_CHARS, WORKSPACE_READ_MAX_CHARS,
  WORKSPACE_REPLY_BUDGET } from './WorkspaceUtil';

// ── 工具回执组装（工具卡通用文本渲染，零改动 ChatToolCard）──
// list 回执（★ 语义冻结：**按 dir 一层列举**而非全量平铺——1000 件平铺必爆 8192 预算；进
// 子目录由模型把段名填 dir 再调）：首行报位置与规模；子目录条目在前、文件在后（名称 · 大小
// · 时间 · 来源）；空目录给明确语义；超预算按行收口（截断行数 + 尾注明，不用
// clipWorkspaceReply 硬切——按行保可读性）。预算余量按省略尾注**自身长度**预留（余量小于
// 尾注实际长度时合成结果可超 8192）
export function composeWorkspaceListReply(dir: string, dirs: WorkspaceDirBrief[],
  briefs: WorkspaceListBrief[]): string {
  const head: string = dir === '' ?
    '工作区根目录下共 ' + dirs.length + ' 个子文件夹、' + briefs.length + ' 个文件。' :
    '工作区「' + dir + '」目录下共 ' + dirs.length + ' 个子文件夹、' + briefs.length + ' 个文件。';
  if (dirs.length === 0 && briefs.length === 0) {
    return dir === '' ? '工作区还没有文件与子文件夹。' : '该目录还没有文件与子文件夹。';
  }
  const lines: string[] = [head];
  for (const d of dirs) {
    lines.push(d.name + '/ · 目录 · ' + d.fileCount + ' 个文件');
  }
  for (const b of briefs) {
    lines.push(b.name + ' · ' + formatWorkspaceSize(b.size) + ' · ' +
      formatWorkspaceTime(b.createdAt) + ' · ' + sourceLabel(b.source));
  }
  let text: string = lines.join('\n');
  if (text.length > WORKSPACE_REPLY_BUDGET) {
    const kept: string[] = [head];
    const allLines: string[] = lines.slice(1);
    for (let i = 0; i < allLines.length; i++) {
      const line: string = allLines[i];
      const omittedTail: string = '……其余 ' + (allLines.length - i) +
        ' 项已省略。可用更具体的需求让用户在应用的文件工作区中查看。';
      if (kept.join('\n').length + line.length + 1 >
        WORKSPACE_REPLY_BUDGET - omittedTail.length - 1) {
        kept.push(omittedTail);
        break;
      }
      kept.push(line);
    }
    text = kept.join('\n');
  }
  return text;
}

// read 回执（分段读契约：text/doc 两路并行级语义，超长单行改行内截断 + offset/col 行内续读
// 指针——任何内容恒可达）。归一全部在本函数内收口，执行器传模型原值不预处理。判定次序固定：
// 空内容 → 恰读尽与行越界 → 行内位置越界 → 装帧（空内容先判才不对空文件回「已超出末尾」）。
// meta = doc 路的解析来源行（text 路恒空串）。参数：offset = 起始行（1-based）、limit = 本次
// 最多行数（≤0/非有限 = 不限，装到帧体预算即停）、col = 行内起始字符位置（1-based，作用于
// 本段起始行）——缺省/非正/非有限一律按 1（宽松归一防模型习惯性传 0；行语义下 0 无意义）。
// 防回游要点：恰读尽回「已全部读完」（防按越界指引回读开头浪费一轮）；单行截断点与行内续读
// 起点不劈代理对（孤儿代理上屏 = 残缺字符）；触尾给「已全部读完」，截断给行内续读指针。
export function composeWorkspaceReadReply(name: string, content: string,
  offset: number = 0, limit: number = WORKSPACE_READ_MAX_CHARS, meta: string = '',
  col: number = 0): string {
  if (content.length === 0) {
    return '文件「' + name + '」内容为空。';
  }
  return composeReadReplyLines(name, content, offset, limit, meta, col);
}

// 行内续读尾注预留（字符）：帧体预算 = REPLY_BUDGET − 头部上界 − 本预留；64 = 最长尾注句
//（行内指针句约 54 字符）+ 前导换行 + 数字位宽余量的上界
const READ_TAIL_RESERVE: number = 64;
// 行内截断标记（装帧首帧超帧体预算时行尾注明；长度计入截断预留）
const CLIP_MARKER: string = '[本行过长已截断]';

// 行级装帧（text 与 doc 两路同形）。停机两闸：①累计帧长到帧体预算即停；②首行独占超预算 →
// 截断该行并注明、尾注给行内续读指针（行内剩余可达）。全量首帧不出尾注，其余尾注三分
//（截断行内指针 / 已读完 / 下一行指针）。col>1 = 行内续读入口（首帧为该行自第 col 字符起的
// 残段，头行出「第 X 行第 C 个字符起」形态）。
// 帧体预算 = WORKSPACE_REPLY_BUDGET − 本调用头部上界（meta 行 + 头行按末行号代入——行号
// 位数只减不增，故为上界）− READ_TAIL_RESERVE，且不超 WORKSPACE_READ_MAX_CHARS（原静态
// 上界在「长名 + 长 meta + 多短行」组合实测 8206 > 8192 越线改现算）；上界成立下合计恒
// ≤ 8191。★ 上界依赖调用方 meta 有界（doc 路 warning 收口于 WORKSPACE_DOC_WARNING_MAX_CHARS）；
// 截断路径 cut 钳位 ≥1 为纯函数防御面（头部超量也不产出不前移的指针）
function composeReadReplyLines(name: string, content: string, offset: number,
  limit: number, meta: string, col: number): string {
  const lines: string[] = content.split('\n');
  const lineCount: number = lines.length;
  const startLine: number = Number.isFinite(offset) && offset >= 1 ? Math.floor(offset) : 1;
  const maxLines: number = Number.isFinite(limit) && limit > 0 ?
    Math.max(1, Math.floor(limit)) : Number.POSITIVE_INFINITY;
  const head: string = meta === '' ? '' : meta + '\n';
  if (startLine === lineCount + 1) {
    return head + '文件「' + name + '」共 ' + lineCount + ' 行，已全部读完，没有更多内容。';
  }
  if (startLine > lineCount + 1) {
    return head + '文件「' + name + '」共 ' + lineCount + ' 行，请求的起始行号 ' + startLine +
      ' 已超出末尾。可用 offset=1 从第 1 行读取。';
  }
  const firstRaw: string = lines[startLine - 1];
  let col0: number = Number.isFinite(col) && col >= 1 ? Math.floor(col) - 1 : 0;
  if (col0 > 0 && col0 >= firstRaw.length) {
    return head + '文件「' + name + '」共 ' + lineCount + ' 行，第 ' + startLine + ' 行共 ' +
      firstRaw.length + ' 个字符，请求的行内位置 ' + (col0 + 1) +
      ' 超出该行长度。可用 offset=' + startLine + ' 从该行行首读取，或 offset=' +
      (startLine + 1) + ' 读取后续行。';
  }
  if (col0 > 0) {
    // 行内续读起点不得落代理对中间（高代理+低代理 → 回退一位并入成对——F5 同族防线）
    const curCode: number = firstRaw.charCodeAt(col0);
    const prevCode: number = firstRaw.charCodeAt(col0 - 1);
    if (curCode >= 0xDC00 && curCode <= 0xDFFF && prevCode >= 0xD800 && prevCode <= 0xDBFF) {
      col0 -= 1;
    }
  }
  const startCol: number = col0 + 1;
  const headBound: string = head +
    readHeadLine(name, lineCount, startLine, startCol, lineCount) + '\n';
  let frameBudget: number = WORKSPACE_REPLY_BUDGET - headBound.length - READ_TAIL_RESERVE;
  if (frameBudget > WORKSPACE_READ_MAX_CHARS) {
    frameBudget = WORKSPACE_READ_MAX_CHARS;
  }
  const clipOverhead: number = CLIP_MARKER.length + 7;
  const frames: string[] = [];
  let used: number = 0;
  let endLine: number = startLine - 1;
  let clipLine: number = 0;
  let clipNextCol: number = 0;
  for (let idx = startLine - 1; idx < lineCount &&
    (idx - startLine + 1) < maxLines; idx++) {
    const raw: string = lines[idx];
    const prefix: string = (idx + 1) + '\t';
    const seg: string = (idx === startLine - 1 && col0 > 0) ? raw.substring(col0) : raw;
    if (frames.length > 0 && used + prefix.length + seg.length + 1 > frameBudget) {
      break;
    }
    if (frames.length === 0 && prefix.length + seg.length > frameBudget - clipOverhead) {
      // 极压头部防御面：纯函数直调喂超量头部时，本钳位保证至少展示 1 码元、续读指针严格
      // 前移（cut ≤ 0 得空串且指针可能原地踏步 = 模型循环）
      let cut: number = frameBudget - prefix.length - clipOverhead;
      if (cut < 1) {
        cut = 1;
      }
      const lastCode: number = seg.charCodeAt(cut - 1);
      if (lastCode >= 0xD800 && lastCode <= 0xDBFF) {
        cut -= 1;
        if (cut < 1) {
          cut = 1; // 代理对回退不得吞掉前移性（极压面接受孤代理上屏；常态面 cut 远大于 1 不触发）
        }
      }
      frames.push(prefix + seg.substring(0, cut) + CLIP_MARKER);
      endLine = idx + 1;
      clipLine = idx + 1;
      // 续读起点 = 未展示的第一个字符（1-based）；cut 已避代理对中点且恒 ≥1，指针恒前进
      clipNextCol = col0 + cut + 1;
      break;
    }
    frames.push(prefix + seg);
    used += prefix.length + seg.length + 1;
    endLine = idx + 1;
  }
  const atEnd: boolean = endLine >= lineCount;
  // 尾注三分：截断 → 行内续读指针（指针指向未展示的第一个字符，行必未读尽）；触尾未截断 →
  // 已读完；未完 → 下一行指针
  const tail: string = clipLine > 0 ?
    '\n[本行内容过长，已截断显示，该行剩余内容可用 offset=' + clipLine + ' col=' +
      clipNextCol + ' 继续读取]' :
    (atEnd ? '\n[已全部读完，没有更多内容]' :
      '\n[未完部分可用 offset=' + (endLine + 1) + ' 继续读取]');
  if (startLine === 1 && startCol === 1 && atEnd && clipLine === 0) {
    return head + '文件「' + name + '」共 ' + lineCount + ' 行，内容如下：\n' + frames.join('\n');
  }
  return head + readHeadLine(name, lineCount, startLine, startCol, endLine) + '\n' +
    frames.join('\n') + tail;
}

// 区间头行（单源两消费：帧体预算的头部上界〔末行号传 lineCount〕与最终回执头行〔传实际
// endLine〕——同函数保证上界与实际同形，改措辞不改预算证明）。startCol=1 出「第 X~Y 行」；
// 行内续读（startCol>1）出「第 X 行第 C 个字符起」形态（单行续读省「至第 Y 行」）
function readHeadLine(name: string, lineCount: number, startLine: number,
  startCol: number, endLine: number): string {
  if (startCol === 1) {
    return '文件「' + name + '」共 ' + lineCount + ' 行，以下为第 ' + startLine + '~' +
      endLine + ' 行：';
  }
  if (startLine === endLine) {
    return '文件「' + name + '」共 ' + lineCount + ' 行，以下为第 ' + startLine + ' 行第 ' +
      startCol + ' 个字符起的内容：';
  }
  return '文件「' + name + '」共 ' + lineCount + ' 行，以下为第 ' + startLine + ' 行第 ' +
    startCol + ' 个字符起至第 ' + endLine + ' 行：';
}

// doc 读回执的解析来源行（meta；engine 空〔非 PDF 引擎无引擎名〕不出 meta 行）。页段仅
// pageCount>0 时给；thin 命中〔判据复用 pdfTextThin〕附加扫描件提示——防模型对稀薄文本误判
//「文件为空」。warning = 桥页部分解析提示（PDF>200 页 / xlsx>20 表 / pptx>500 页时桥页只把
// 提示放 warning 字段、正文无截断标记——附加到 meta 行随预算自控收口，模型才知晓）
export function workspaceDocMetaLine(engine: string, pageCount: number, thin: boolean,
  warning: string = ''): string {
  if (engine === '') {
    return '';
  }
  let line: string = '已解析为文字内容（引擎 ' + engine +
    (pageCount > 0 ? '，共 ' + pageCount + ' 页' : '') + '）。';
  if (warning !== '') {
    // ★ warning 回显收口（上限 + '…'）——长度无上限的外部串（docx 路 mammoth messages
    // join）不经收口会顶穿回执预算证明
    line += (warning.length > WORKSPACE_DOC_WARNING_MAX_CHARS ?
      warning.substring(0, WORKSPACE_DOC_WARNING_MAX_CHARS) + '…' : warning) + '。';
  }
  if (thin) {
    line += '文字内容较少，可能是扫描件，建议让用户在应用内打开查看。';
  }
  return line;
}

// 图片读回执：image 档五路（挂载成功 / 挂载失败 / OCR 文字 / OCR 无文字 / OCR 未开启与失败）。
// 执行器分流（ctx.hasVision），本函数只管回执形态；全部过文案规约。ocr_text 路整条经
// clipWorkspaceReply 收口（密图 OCR 可产数千字——预算单源 WORKSPACE_REPLY_BUDGET）；未知
// outcome 兜底 ocr_failed 形态（防御面）。engine 中文名映射在本函数内（OcrOutcome 契约只回
// 引擎类值拿不到模型名，视觉模型统一显示「视觉模型」）
export function composeWorkspaceImageReply(name: string, outcome: string, detail: string = '',
  engine: string = ''): string {
  if (outcome === 'attached') {
    return '图片「' + name + '」已附在本次消息中，可以直接查看。';
  }
  if (outcome === 'attach_failed') {
    return '图片「' + name + '」读取成功，但本次会话无法附加图片。' +
      '请让用户在应用内查看该图片。';
  }
  if (outcome === 'ocr_text') {
    const engineLabel: string = engine === 'system' ? '系统识别' :
      (engine === 'builtin' ? '内置识别' : (engine === 'model' ? '视觉模型' : ''));
    const head: string = '图片「' + name + '」已识别出文字内容' +
      (engineLabel !== '' ? '（引擎 ' + engineLabel + '）' : '') + '，如下。';
    return clipWorkspaceReply(head + '\n' + detail, WORKSPACE_REPLY_BUDGET);
  }
  if (outcome === 'ocr_empty') {
    return '图片「' + name + '」未识别到文字。它可能是纯图形图片，' +
      '请结合文件名与上下文判断内容，或让用户在应用内查看。';
  }
  if (outcome === 'ocr_disabled') {
    return '图片「' + name + '」无法识别文字，因为应用的文字识别功能未开启。' +
      '请让用户在应用的设置中开启文字识别，或在应用内查看该图片。';
  }
  return '图片「' + name + '」文字识别未成功。请让用户在应用内查看该图片，或稍后重试。';
}

// 图片预识别回执：无视觉读图片命中有效预识别文本时的回执——来源标注由调用方经
// workspaceOcrSourceLabel（WorkspaceDbOcr 单源）传入，全文经 clipWorkspaceReply 收口（预识别
// 文本上限 12 万字符，远超回执预算）
export function composeWorkspaceOcrFreshReply(name: string, sourceLabel: string,
  text: string): string {
  const head: string = '图片「' + name + '」使用' + sourceLabel + '，内容如下。';
  return clipWorkspaceReply(head + '\n' + text, WORKSPACE_REPLY_BUDGET);
}

// doc 原件直传回执：read 的 doc 路原生分支挂载成功——PDF 原件已随工具结果位发出，模型可
// 直接阅读（文字/图片/排版全量信息，不附解析文本，省一次桥页解析与 token）。失败形态不新增
// 文案：读失败 / 空字节 / 挂载失败一律回落现状解析路（调用方保证），本函数只有成功一态
export function composeWorkspaceDocNativeReply(name: string): string {
  return '文档「' + name + '」的原件已随本轮请求发送，可以直接阅读其中的文字、图片与排版。';
}

// doc 读错误映射（已知码中文映射 + 指向下一步；未知码原样透传保留诊断面——P0-1）。code 取
// DocumentParseResult.error 码或 throw message（执行器 catch 兜底传入）；limitText =
// formatWorkspaceSize(该分型上限)，执行器现算传入
export function workspaceParseErrorReply(name: string, code: string, limitText: string): string {
  if (code === 'file_too_large') {
    return '「' + name + '」超过文档解析大小上限（' + limitText + '），无法读取内容。' +
      '请让用户改用较小的文件。';
  }
  if (code === 'empty_file_data') {
    return '「' + name + '」内容为空，无法解析。';
  }
  if (code === 'unsupported_file_type') {
    return '「' + name + '」的文件类型暂不支持解析。';
  }
  if (code === '解析超时') {
    return '「' + name + '」解析超时，请稍后重试，或让用户改用较小的文件。';
  }
  return '「' + name + '」解析失败（' + code + '）。请稍后重试。';
}

// 覆盖注记两档：覆盖前既有行的归属分类——'conversation' = 其他会话保存；'external' = 无会话
// 归属（管理页上传 source='user' 与对账恢复件 source='recovered'，全仓两路逐调用点核实）；
// '' = 同会话/无注记
export const WORKSPACE_OVERWRITE_CONVERSATION: string = 'conversation';
export const WORKSPACE_OVERWRITE_EXTERNAL: string = 'external';

// 覆盖归属分类判据单源（write / write_xlsx / import 三写入路共用）：既有行无会话归属
//（上传/恢复件）= 外源档——与本次写入方有无会话无关（'' 不是会话，不存在「同会话」）；
// 有归属且 ≠ 本次 = 会话档；其余 = ''（无注记）
export function workspaceOverwriteKindOf(prevConversationId: string,
  currentConversationId: string): string {
  if (prevConversationId === '') {
    return WORKSPACE_OVERWRITE_EXTERNAL;
  }
  return prevConversationId === currentConversationId ? '' : WORKSPACE_OVERWRITE_CONVERSATION;
}

// 覆盖注记句（三路回执共用措辞单源；'' 与未知档 = 无注记）：句首自带「注意，」句尾「。」——
// write 路接在基句后直拼；import 路基句尾无句号，由调用方先补「。」再接（见 ToolWorkspace）
export function workspaceOverwriteNote(kind: string): string {
  if (kind === WORKSPACE_OVERWRITE_CONVERSATION) {
    return '注意，本次覆盖了其他会话保存的文件。';
  }
  if (kind === WORKSPACE_OVERWRITE_EXTERNAL) {
    return '注意，本次覆盖了用户上传或恢复的文件。';
  }
  return '';
}

// write 回执：已保存 + 名称 + 大小 + 现有件数。overwriteKind = 覆盖注记档（判据单源
// workspaceOverwriteKindOf；缺省 '' = 既有调用回执逐字不变）；diffTail = 覆盖写旧文摘录或
// 超阈行数对的单行 JSON（缺省 '' 不附加；非空直拼 '\n' + 尾行——envelope 契约 = 施工总案 §四）
export function composeWorkspaceWriteReply(name: string, sizeBytes: number,
  totalCount: number, overwriteKind: string = '', diffTail: string = ''): string {
  const base: string = '已保存「' + name + '」，共 ' + sizeBytes + ' 字节。工作区现有 ' +
    totalCount + ' 个文件。';
  const note: string = workspaceOverwriteNote(overwriteKind);
  const text: string = note === '' ? base : base + note;
  return diffTail === '' ? text : text + '\n' + diffTail;
}

// ── 目录四工具回执（动作结果 + 实际落点/名 + 关键数值，纯函数组装）──
// mkdir 回执：创建成功 / 已存在幂等两态（dirLabel = 逻辑路径串）
export function composeWorkspaceDirCreatedReply(dirLabel: string,
  alreadyExists: boolean): string {
  return alreadyExists ?
    '文件夹「' + dirLabel + '」已存在。' :
    '已创建文件夹「' + dirLabel + '」。';
}

// rename 回执：文件报新旧名、文件夹报段名路径（isDir 分流；dirLabel = 所在目录，'' = 根）
export function composeWorkspaceRenameReply(dirLabel: string, oldName: string,
  newName: string, isDir: boolean): string {
  const where: string = dirLabel === '' ? '' : '（位于 ' + dirLabel + '）';
  return isDir ?
    '已把文件夹「' + joinDirName(dirLabel, oldName) + '」改名为「' +
      joinDirName(dirLabel, newName) + '」。' :
    '已把「' + oldName + '」改名为「' + newName + '」' + where + '。';
}

// move 回执：移到根与移到子目录两态（isDir = true 时 nameLabel = 段名路径）
export function composeWorkspaceMoveReply(toDir: string, nameLabel: string,
  isDir: boolean): string {
  const label: string = isDir ? '文件夹「' + nameLabel + '」' : '「' + nameLabel + '」';
  return toDir === '' ?
    '已把' + label + '移动到根目录。' :
    '已把' + label + '移动到「' + toDir + '」。';
}

// delete 回执：文件报名、文件夹报件数与合计大小（由执行器从删前统计取得）
export function composeWorkspaceDeleteReply(nameLabel: string, isDir: boolean,
  fileCount: number, totalBytes: number): string {
  return isDir ?
    '已删除文件夹「' + nameLabel + '」，共删除 ' + fileCount + ' 个文件，合计 ' +
      formatWorkspaceSize(totalBytes) + '。' :
    '已删除「' + nameLabel + '」。';
}
