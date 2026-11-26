// 工具卡收起态结果摘要行（偏好开关「工具卡显示结果摘要」已退役、行为固化为恒显示）。普通工具卡收起态
// 在标题行下方显示一行 12fp 单行摘要——完成态 = 次要色一句提炼（按工具族从结果 JSON 提关键
// 信息），出错态 = 警告色错误首句；展开后摘要行退场（详情区已含全部信息，不与展开区
//「已存入工作区」行等重复并置）；运行中/中止/确认卡/提问卡不显示（右槽状态位已表达）。
// 照 ChatToolDiffBlock 先例：派生纯函数区（本注释至组件声明前）零 ArkUI 依赖、工具名字面量
// 判（零跨件 import 红线——钉提取副本直跑引外部常量即 ReferenceError；字面量 ⊆ ToolIds
// 常量值由 assert-chat-display 484 组关系判据守），组件区只做薄渲染与可见判据。
// 提炼口径：不假设 toolOutputJson 单行（实时美化串与回放原串两形态）；JSON.parse 失败 =
// 纯文本回执（workspace/mount/memory/skill/calendar/exec 族）取首个非空行截断；结构化族
// 逐工具提一句；未知 JSON 对象走 note/summary 键兜底，仍无则回空串零渲染（不露 JSON 原文）。
// 入参不带 inputJson——已核全部结果信封，摘要所需信息（文件名/标题/数量）输出串均已自带。
import { cardDescColor, SEGMENT_BODY_PAD_L, SEGMENT_ROW_PAD_R } from '../../common/Theme';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';
import { ChatMessage, isAskCard, isConfirmAwaiting, isConfirmDone } from './ChatMessageCompose';

// 摘要单行截断上限（字符）：单行信息量上限，超长截断缀省略号（全文原文仍可从展开详情查看）
export const TOOL_SUMMARY_MAX_CHARS: number = 48;

// 单行截断（纯函数）：首尾空白先去，超上限裁断缀省略号
export function clipSummaryText(text: string): string {
  const trimmed: string = text.trim();
  if (trimmed.length <= TOOL_SUMMARY_MAX_CHARS) {
    return trimmed;
  }
  return trimmed.substring(0, TOOL_SUMMARY_MAX_CHARS) + '…';
}

// 首个非空行提取（错误文案与纯文本回执的摘要源）：CRLF 归一后按 LF 切，跳过空行
export function firstSummaryLine(text: string): string {
  const lines: string[] = text.replace(/\r\n/g, '\n').split('\n');
  for (const line of lines) {
    const trimmed: string = line.trim();
    if (trimmed !== '') {
      return trimmed;
    }
  }
  return '';
}

// 记录取串（缺键/非串回空串）
export function readSummaryString(rec: Record<string, Object>, key: string): string {
  const raw: Object | undefined = rec[key];
  return typeof raw === 'string' ? raw : '';
}

// 记录取数（缺键/非数回 NaN——经纬度等负值合法，不用负数哨兵；判定走 Number.isFinite）
export function readSummaryNumber(rec: Record<string, Object>, key: string): number {
  const raw: Object | undefined = rec[key];
  return typeof raw === 'number' ? raw : Number.NaN;
}

// 数组成员计数（非数组回 -1，与 0 个成员区分）
export function summaryArrayCount(raw: Object | undefined): number {
  return Array.isArray(raw) ? (raw as Object[]).length : -1;
}

// 结构化族逐工具提炼（只接「已是合法 JSON 对象且非失败信封」的记录；认不出或字段不齐回
// 空串交上层 note/summary 兜底。信封字段位与各执行器输出已逐处核对在案：搜索族
// ToolWebSearch / 浏览族 ToolBrowse / browse_act ToolBrowseAct / http HttpFlow / 图表
// ToolChart / 其余各件同笔探查表）
export function summaryForKnownTool(toolName: string, rec: Record<string, Object>): string {
  if (toolName === 'search_web' || toolName === 'scrape_web') {
    const results: Object | undefined = rec['results'];
    const count: number = summaryArrayCount(results);
    if (count <= 0) {
      return toolName === 'search_web' ? '未搜到结果' : '';
    }
    const first: Object | undefined = (results as Object[])[0];
    const title: string = typeof first === 'object' && first !== null ?
      readSummaryString(first as Record<string, Object>, 'title') : '';
    if (toolName === 'scrape_web') {
      return clipSummaryText(title !== '' ? '已读取「' + title + '」' : '已读取网页');
    }
    return clipSummaryText(title !== '' ?
      count + ' 条结果 · 首条「' + title + '」' : count + ' 条结果');
  }
  if (toolName === 'browse_open' || toolName === 'browse_read') {
    const title: string = readSummaryString(rec, 'title');
    const head: string = title !== '' ? '「' + title + '」' : readSummaryString(rec, 'url');
    if (Array.isArray(rec['nodes'])) {
      const collected: number = readSummaryNumber(rec, 'collected');
      const total: number = readSummaryNumber(rec, 'count');
      const n: number = Number.isFinite(collected) ? collected : total;
      return clipSummaryText((head !== '' ? head + ' · ' : '') +
        (Number.isFinite(n) ? n + ' 个元素' : '已读取页面'));
    }
    const totalChars: number = readSummaryNumber(rec, 'totalChars');
    return clipSummaryText((head !== '' ? head + ' · ' : '') +
      (Number.isFinite(totalChars) ? '共 ' + totalChars + ' 字符' : '已读取页面'));
  }
  if (toolName === 'browse_act') {
    const action: string = readSummaryString(rec, 'action');
    const changed: boolean = rec['changed'] === true;
    return clipSummaryText((action !== '' ? action : '操作') + ' · ' +
      (changed ? '页面已变化' : '页面无变化'));
  }
  if (toolName === 'http_request') {
    const savedRaw: Object | undefined = rec['saved'];
    if (typeof savedRaw === 'object' && savedRaw !== null) {
      const name: string = readSummaryString(savedRaw as Record<string, Object>, 'name');
      if (name !== '') {
        return clipSummaryText('已存入工作区 ' + name);
      }
    }
    const status: number = readSummaryNumber(rec, 'status');
    if (!Number.isFinite(status)) {
      return '';
    }
    const totalLength: number = readSummaryNumber(rec, 'totalLength');
    if (Number.isFinite(totalLength)) {
      return 'HTTP ' + status + ' · 正文 ' + totalLength + ' 字符';
    }
    const contentLength: number = readSummaryNumber(rec, 'contentLength');
    if (Number.isFinite(contentLength)) {
      return 'HTTP ' + status + ' · ' + contentLength + ' 字节';
    }
    return 'HTTP ' + status;
  }
  if (toolName === 'chart_display' && rec['success'] === true) {
    const style: string = readSummaryString(rec, 'style');
    const series: number = readSummaryNumber(rec, 'series_count');
    const points: number = readSummaryNumber(rec, 'point_count');
    if (Number.isFinite(series) && Number.isFinite(points)) {
      return clipSummaryText((style !== '' ? style : '图表') + ' · ' + series + ' 系列 ' + points + ' 点');
    }
    return '图表已生成';
  }
  if (toolName === 'get_time_info') {
    const parts: string[] = [];
    const date: string = readSummaryString(rec, 'date');
    const time: string = readSummaryString(rec, 'time');
    const weekday: string = readSummaryString(rec, 'weekday');
    if (date !== '') {
      parts.push(date);
    }
    if (time !== '') {
      parts.push(time);
    }
    if (weekday !== '') {
      parts.push(weekday);
    }
    return parts.length > 0 ? clipSummaryText(parts.join(' ')) : '';
  }
  if (toolName === 'get_location') {
    const address: string = readSummaryString(rec, 'address');
    if (address !== '') {
      return clipSummaryText(address);
    }
    const lat: number = readSummaryNumber(rec, 'latitude');
    const lon: number = readSummaryNumber(rec, 'longitude');
    if (Number.isFinite(lat) && Number.isFinite(lon)) {
      return clipSummaryText('纬度 ' + lat + ' · 经度 ' + lon);
    }
    return '';
  }
  if (toolName === 'get_calendar_events') {
    const count: number = readSummaryNumber(rec, 'count');
    const total: number = readSummaryNumber(rec, 'total');
    const n: number = Number.isFinite(count) ? count : total;
    return Number.isFinite(n) ? n + ' 个日程' : '';
  }
  if (toolName === 'env_list') {
    const credsRaw: Object | undefined = rec['credentials'];
    if (typeof credsRaw === 'object' && credsRaw !== null) {
      const creds: Record<string, Object> = credsRaw as Record<string, Object>;
      const n: number = Math.max(0, summaryArrayCount(creds['global'])) +
        Math.max(0, summaryArrayCount(creds['assistant']));
      if (n > 0) {
        return '凭据 ' + n + ' 条';
      }
    }
    return '';
  }
  if (toolName === 'search_help') {
    const count: number = summaryArrayCount(rec['results']);
    if (count > 0) {
      return '帮助条目 ' + count + ' 条';
    }
    return count === 0 ? '未找到相关帮助' : '';
  }
  if (toolName === 'get_app_preference') {
    const count: number = summaryArrayCount(rec['settings']);
    return count > 0 ? count + ' 项设置' : '';
  }
  if (toolName === 'get_provider_config') {
    const count: number = summaryArrayCount(rec['providers']);
    return count >= 0 ? count + ' 家服务商' : '';
  }
  if (toolName === 'test_provider' && rec['ok'] === true) {
    const count: number = summaryArrayCount(rec['models']);
    return count >= 0 ? '连接成功 · ' + count + ' 个模型' : '连接成功';
  }
  if (toolName === 'manage_balance' && rec['ok'] === true) {
    const balance: string = readSummaryString(rec, 'balance');
    return balance !== '' ? clipSummaryText('余额 ' + balance) : '';
  }
  if (toolName === 'clipboard_write' && rec['success'] === true) {
    const chars: number = readSummaryNumber(rec, 'textChars');
    return Number.isFinite(chars) ? '已写入 ' + chars + ' 字' : '已写入剪贴板';
  }
  return '';
}

// 收起态摘要提炼入口（纯函数）：done/error 终态的输出串 → 一句话；回空串 = 不渲染。
// 层序 = 空结果 → 落盘信封 → 纯文本回执（parse 失败首行截断）→ 失败/中止信封（error 首句 /
// cancelled 空）→ 结构化族提炼 → note/summary 键兜底 → 空串
export function toolCardSummaryText(toolName: string, outputJson: string): string {
  if (outputJson === '') {
    return '';
  }
  // 落盘信封（ToolClip.composeToolSpillEnvelope 动态拼阈值进前缀——判短语不判数字，阈值
  // 调整不红）：超长结果已存临时文件，信封正文本就不可读
  if (outputJson.startsWith('结果超过 ') && outputJson.includes(' 字符上限，已保存为临时文件')) {
    return '结果过长 · 已存临时文件';
  }
  let parsed: Record<string, Object> | null = null;
  let structured: boolean = false;
  try {
    const raw: Object = JSON.parse(outputJson) as Object;
    structured = true;
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      parsed = raw as Record<string, Object>;
    }
  } catch (e) {
    structured = false;
  }
  if (!structured) {
    return clipSummaryText(firstSummaryLine(outputJson));
  }
  // 合法 JSON 但非对象（数组/标量/null）——无一句话可提炼，不露原文
  if (parsed === null) {
    return '';
  }
  // 失败与中止信封（与 ChatToolRoundCtrl.detectErrorResult 同判）。★ cancelled 先判：中止
  // 信封同时带 cancelled 与 error 两键（abortedToolResult 形态）——中止语义优先（「用户
  // 中止」不是错误句，右槽已显「已中止」位），纯失败信封只带 error 键不受影响
  if (parsed['cancelled'] !== undefined) {
    return '';
  }
  if (parsed['error'] !== undefined) {
    return clipSummaryText(firstSummaryLine(readSummaryString(parsed, 'error')));
  }
  const family: string = summaryForKnownTool(toolName, parsed);
  if (family !== '') {
    return family;
  }
  // 通用兜底：note / summary 人话键（MCP 与未单列工具的常见回执键），仍无则空串零渲染
  const note: string = readSummaryString(parsed, 'note');
  if (note !== '') {
    return clipSummaryText(firstSummaryLine(note));
  }
  const summary: string = readSummaryString(parsed, 'summary');
  if (summary !== '') {
    return clipSummaryText(firstSummaryLine(summary));
  }
  return '';
}

// 收起态摘要行渲染体：偏好开关关 / 确认与提问卡 / 非终态 / 已展开 / 摘要空串时零渲染（根
// Column 空挂零高度，无内距防占位空白）。@ObjectLink msg 订阅 toolState / detailExpanded
// 增量——结算与展开切换即刷新；提炼结果记忆化（键 = outputJson 纯函数，照 savedFile 形）
@Component
export struct ChatToolSummaryRow {
  @ObjectLink msg: ChatMessage;
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  private summaryCacheJson: string = '';
  private summaryCacheText: string = '';

  private summaryText(): string {
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (outputJson === this.summaryCacheJson) {
      return this.summaryCacheText;
    }
    const text: string = toolCardSummaryText(this.msg.toolName, outputJson);
    this.summaryCacheJson = outputJson;
    this.summaryCacheText = text;
    return text;
  }

  // 可见判据：摘要行恒显示（偏好键已退役、不再有开关总闸），仅按卡片形态收敛——非提问卡 &&
  // 非确认卡（等待/回执两态都走专属头行）&& 收起态 && done/error 终态 && 摘要非空；展开后退场
  private rowVisible(): boolean {
    return !isAskCard(this.msg) && !isConfirmAwaiting(this.msg) &&
      !isConfirmDone(this.msg) && this.msg.detailExpanded !== true &&
      (this.msg.toolState === 'done' || this.msg.toolState === 'error') &&
      this.summaryText() !== '';
  }

  build() {
    Column() {
      if (this.rowVisible()) {
        Text(this.summaryText())
          .fontSize(12)
          .fontFamily(bodyFontFamily(this.fontBodyValue, this.fontLibJson))
          .fontColor(this.msg.toolState === 'error' ?
            $r('sys.color.ohos_id_color_warning') : cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 左沿与标题文字对齐（= 展开区正文列同沿）；bottom 8 与 DetailBody 底距同档，
          // 防贴到下一行步骤标题
          .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R, bottom: 8 })
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
