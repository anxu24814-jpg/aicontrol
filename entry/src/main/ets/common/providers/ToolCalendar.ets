// 日程工具域（决明拍板「查/建/改/删 4 件全做」）：get_calendar_events 查询（默认今天全天，
// 可传起止毫秒，上限 100 条）/ create / update（先读回原日程再合并，只覆盖传了的字段）/
// delete（不可逆档恒问人）。
// ★ 权限：READ_CALENDAR + WRITE_CALENDAR 两枚开放权限（normal + user_grant）——运行期
// 首次调用一次弹窗申请（照 ToolLocation 先例：双权一次申请、以申请后复查为准；拒绝统一
// 文案引导系统设置，不二次拉起）。
// ★ 读取范围 = 只读「本应用创建的日程」（决明拍板硬边界）：不用 READ_WHOLE_CALENDAR
// 受限权限（system_basic，开发期声明即安装失败 9568289）；用户系统日历里其他来源的日程
// 看不到也改不了。
// ★ 账户 = 自建账户（拍板）：name = AiControlCalendar、type = LOCAL、displayName = AiControl
//（用户可见——系统日历「日程来源」里显示的名字）；getCalendar 失败（账户被用户删）即
// createCalendar 重建并 setConfig({ enableReminder: true, color })——提醒双开关之一，
// 漏配则日程不提醒；setConfig 失败不阻断本工具。
// ★ 确认链（拍板）：create / update = 写档（三键卡）、delete = 不可逆档（恒问人）；三预检
// 一律走 routeConfirmPrompt(prompt, dataApproveMode())。fail-closed 照 HttpPreflight H3-5：
// 写意图成立（三必填齐 / 有 id）之后的异常返保守人工卡——预检挂而执行成 = 写操作无卡直发；
// 写意图未成立（参数坏 / 缺 id / 无可改字段）返 null 交执行器报参数错。
// ★ 范围边界与不做项（拍板）：不做循环日程（recurrenceRule）、参会人写入、自定义时区（恒用
// 设备时区）、一键服务、多次提醒、跳系统日历页、全量读取（WHOLE 权限）；提醒不默认设——仅
// reminderMinutes 在场且为正数时转 reminderTime: [n]。字段清空不支持（空串 = 未传 = 保持原值）。
// context 注入：执行器无组件环境——EntryAbility onCreate 经 initCalendarAccess 注入（未注入
// 时返错误不炸轮）。域纪律：本文件只 import './ToolContracts' / './ConfirmRouting' /
// '../AppPreferences' / '../chat/MessageContracts' 与系统 Kit（防环红线，ToolContracts 头
// 注释）；注册在 ToolTypes.ets 聚合根（本文件不引它）。
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { appendReceiptDiffTail, ConfirmPrompt, CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_LEVEL_WRITE,
  CONFIRM_ROUTE_HUMAN, ToolExecutor, toolArgsParseErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { dataApproveMode } from '../AppPreferences';
import { ToolExecutionContext } from '../chat/MessageContracts';

// 双权限（module.json5 同名单源；任一工具执行首步确保——先查后申，两权均已授零弹窗）
const CALENDAR_PERMS: Permissions[] = ['ohos.permission.READ_CALENDAR',
  'ohos.permission.WRITE_CALENDAR'];
// 自建账户三字段（拍板；name = 开发者侧标识、displayName = 用户可见名）
const CALENDAR_ACCOUNT_NAME: string = 'AiControlCalendar';
const CALENDAR_ACCOUNT_DISPLAY: string = 'AiControl';
// 自建日历的颜色（不设默认黑；#1A73E8 = 官方示例同款蓝）
const CALENDAR_COLOR: string = '#1A73E8';
// 查询结果上限（拍板 100 条；另有整串字符预算兜底——100 条长文本会超 8192 截断线硬切出
// 坏 JSON，故到线即止并置 truncated）
const CALENDAR_EVENTS_MAX: number = 100;
const CALENDAR_RESULT_BUDGET: number = 6000;
// 回执/卡面单字段裁剪（防单条超长文本撑爆卡面与结果）
const CALENDAR_TITLE_CLIP: number = 80;
const CALENDAR_DESC_CLIP: number = 200;
const CALENDAR_LOCATION_CLIP: number = 80;
// 确认卡面标题裁剪（照 manageKnowledgeNeedsConfirm 的 30 字先例）
const CALENDAR_CARD_TITLE_CLIP: number = 30;

// 模块级 context 单例（EntryAbility onCreate 注入，进程级不变——状态最小化，不挂装饰器）
let calendarContext: common.UIAbilityContext | null = null;

export function initCalendarAccess(ctx: common.UIAbilityContext): void {
  calendarContext = ctx;
}

// 双权限确保（照 ToolLocation 同款形态，四件执行器共用）：先查后申——两权均已授零弹窗；
// 否则一次申请 READ 与 WRITE，以申请后复查为准（拒绝/失败统一 false 由调用方给文案，
// 不做二次拉起）
async function ensureCalendarPermissions(ctx: common.UIAbilityContext): Promise<boolean> {
  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  if (allCalendarGranted(atManager)) {
    return true;
  }
  try {
    await atManager.requestPermissionsFromUser(ctx, CALENDAR_PERMS);
  } catch (e) {
    return false;
  }
  return allCalendarGranted(atManager);
}

// 逐权查态（getSelfPermissionStatus @since 20 同步 API）；单权查询异常按未授处理（fail-safe）
function allCalendarGranted(atManager: abilityAccessCtrl.AtManager): boolean {
  for (const p of CALENDAR_PERMS) {
    try {
      if (atManager.getSelfPermissionStatus(p) !== abilityAccessCtrl.PermissionStatus.GRANTED) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  return true;
}

// 前置守卫（四件执行器首步共用）：ctx 未注入 / 权限未授返错误 JSON 串；'' = 放行
async function calendarGuard(): Promise<string> {
  const ctx: common.UIAbilityContext | null = calendarContext;
  if (ctx === null) {
    return JSON.stringify({ error: '日程功能未初始化，请重启应用后重试' });
  }
  const granted: boolean = await ensureCalendarPermissions(ctx);
  if (!granted) {
    return JSON.stringify({
      error: '未获得日历权限，无法读写日程。可让用户在系统设置的应用权限管理中为本应用开启日历权限后重试'
    });
  }
  return '';
}

// 取自建日历账户：存在即返回；读取失败（账户被用户删除等异常）即 createCalendar 重建并
// setConfig 设色开提醒；createCalendar 亦失败时抛出由调用方转错误文案。context 未注入
//（理论不可达，守卫已拦）时抛出防静默。
// ★ restoreIfMissing：重建是**写系统日历**的副作用，只许发生在用户已确认的执行链——
// 确认卡预检的读回传 false（账户不存在即抛出，由预检 catch 走保守卡），防「用户看到删除
// 卡还没点、AiControl 日历已被静默重建」（点取消也回不去）
async function obtainCalendar(restoreIfMissing: boolean = true): Promise<calendarManager.Calendar> {
  const ctx: common.UIAbilityContext | null = calendarContext;
  if (ctx === null) {
    throw new Error('日程功能未初始化');
  }
  const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(ctx);
  const account: calendarManager.CalendarAccount = {
    name: CALENDAR_ACCOUNT_NAME,
    type: calendarManager.CalendarType.LOCAL,
    displayName: CALENDAR_ACCOUNT_DISPLAY
  };
  try {
    return await mgr.getCalendar(account);
  } catch (e) {
    // 账户不存在（用户把 AiControl 日历删了）——走重建，不静默；只读语境（预检）直接上抛
    if (!restoreIfMissing) {
      throw e as Error;
    }
  }
  const created: calendarManager.Calendar = await mgr.createCalendar(account);
  try {
    await created.setConfig({ enableReminder: true, color: CALENDAR_COLOR });
  } catch (e) {
    // 设色/开提醒失败不阻断本工具（提醒 = 双开关之一，缺提醒只影响提醒不响，日程本体照常）
  }
  return created;
}

// 设备时区标记（拍板：不做自定义时区）——读不到省略字段，系统按设备时区处理
function deviceTimeZone(): string {
  try {
    return i18n.getTimeZone().getID();
  } catch (e) {
    return '';
  }
}

// 取字符串参数（非字符串/缺省一律归 '' 并 trim——'' = 未传，字段保持原值/不入库）
function readStrArg(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw.trim() : '';
}

// 取数值参数（缺省/非有限数 → NaN 由调用方判缺失；13 位毫秒时间戳取整）
function readNumArg(parsed: Record<string, Object>, key: string): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' && Number.isFinite(raw) ? Math.floor(raw) : NaN;
}

// 取布尔参数（缺省/非布尔 → undefined = 未传；false 是合法传值故不能用缺省形参）
function readBoolArg(parsed: Record<string, Object>, key: string): boolean | undefined {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'boolean' ? raw : undefined;
}

// 文本裁剪（回执与卡面单字段有界）
function clipText(text: string, max: number): string {
  return text.length > max ? text.substring(0, max) + '…' : text;
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

// 本地时间文本（YYYY-MM-DD HH:mm，回执与确认卡共用；设备本地时区）
function formatLocalTime(ms: number): string {
  const d: Date = new Date(ms);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' +
    pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

// 时间段文本（全天日程报日期加「全天」，不报具体时刻）
function formatPeriod(start: number, end: number, isAllDay: boolean): string {
  if (isAllDay) {
    return formatLocalTime(start).substring(0, 10) + ' 全天';
  }
  return formatLocalTime(start) + ' 至 ' + formatLocalTime(end);
}

// 提醒语义文本（reminderTime 单值：正 = 提前、负 = 延后；空数组/0 = 无提醒）
function reminderTextOf(reminderTime: number[] | undefined): string {
  if (reminderTime === undefined || reminderTime.length === 0) {
    return '';
  }
  const first: number = reminderTime[0];
  if (first > 0) {
    return '提前 ' + first + ' 分钟提醒';
  }
  if (first < 0) {
    return '延后 ' + (-first) + ' 分钟提醒';
  }
  return '';
}

// 按 id 读回单条日程（修改合并与删除预检读回共用；需 READ 权限，未授时抛出由调用方分流）。
// 键面固定：id 取编号、type/timeZone 供修改回填、location/description/reminderTime 供合并、
// attendee 供修改防御性回填（官方默认查询字段集成员，读回确定可得；键面设计理由见
// UpdateCalendarEventExecutor 头注释）。★ 不含 recurrenceRule：官方默认查询字段集不含它，
// 显式指定查询行为未定义——若致 getEvents 报错会砸掉修改与删除预检主功能，风险不对称，
// 不做（保留性挂真机观察，BLOCKED 日程节）。restoreIfMissing 透传 obtainCalendar——确认
// 卡预检传 false，决策前零副作用
async function readEventsById(id: number, restoreIfMissing: boolean = true):
  Promise<calendarManager.Event[]> {
  const cal: calendarManager.Calendar = await obtainCalendar(restoreIfMissing);
  return await cal.getEvents(calendarManager.EventFilter.filterById([id]),
    ['id', 'type', 'title', 'startTime', 'endTime', 'isAllDay', 'location', 'description',
      'reminderTime', 'timeZone', 'attendee']);
}

// API 错误文案（前缀 + 错误码；非 BusinessError 时只留前缀，禁 undefined 上回执）
function calendarErrorText(prefix: string, err: Object): string {
  const code: number | undefined = (err as BusinessError).code;
  return typeof code === 'number' ? prefix + '。错误码 ' + code : prefix;
}

// 查询结果条目载荷（ArkTS 对象字面量挂显式接口——坑59①；可选字段缺省省略）
interface CalendarEventPayload {
  id: number;
  title: string;
  startTime: number;
  endTime: number;
  isAllDay: boolean;
  location?: string;
  description?: string;
  reminderMinutes?: number;
}

// 查询结果整串载荷（total = 匹配总数；count = 本次返回条数；truncated = 是否被上限或预算
// 截断——模型据此决定缩窗或分页）
interface CalendarQueryPayload {
  start: number;
  end: number;
  total: number;
  count: number;
  truncated: boolean;
  events: CalendarEventPayload[];
}

// SDK Event → 载荷（无 id 行返 null 跳过——理论不可达，防御式）
function toEventPayload(ev: calendarManager.Event): CalendarEventPayload | null {
  if (typeof ev.id !== 'number') {
    return null;
  }
  const payload: CalendarEventPayload = {
    id: ev.id,
    title: clipText(ev.title ?? '', CALENDAR_TITLE_CLIP),
    startTime: ev.startTime,
    endTime: ev.endTime,
    isAllDay: ev.isAllDay === true
  };
  const loc: calendarManager.Location | undefined = ev.location;
  if (loc !== undefined && loc.location !== undefined && loc.location !== '') {
    payload.location = clipText(loc.location, CALENDAR_LOCATION_CLIP);
  }
  if (ev.description !== undefined && ev.description !== '') {
    payload.description = clipText(ev.description, CALENDAR_DESC_CLIP);
  }
  const reminder: number[] | undefined = ev.reminderTime;
  if (reminder !== undefined && reminder.length > 0 && reminder[0] > 0) {
    payload.reminderMinutes = reminder[0];
  }
  return payload;
}

// 查询入参 schema（时间窗两参成对；零必填——不填查今天全天；★ 时间参数必带毫秒示例
//「例如 1730102400000」——模型高频错 = 传 10 位秒级时间戳或 ISO 字符串，P0 类型钉拦不住
//「秒」语义错，description 是唯一防线）
export const GET_CALENDAR_EVENTS_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"start":{"type":"integer","description":"查询起始时间，13 位毫秒时间戳，例如 1730102400000。' +
  '与 end 成对提供，不填则查今天全天。"},' +
  '"end":{"type":"integer","description":"查询结束时间，13 位毫秒时间戳，例如 1730102400000，' +
  '须晚于 start。"}}}';

// 创建入参 schema（三必填；reminderMinutes 缺省不提醒；起止时间补「（毫秒不是秒）」与
// 示例，理由见 GET schema 注释）
export const CREATE_CALENDAR_EVENT_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"title":{"type":"string","description":"日程标题，必填。"},' +
  '"startTime":{"type":"integer","description":"开始时间，13 位毫秒时间戳（毫秒不是秒），' +
  '例如 1730102400000，必填。"},' +
  '"endTime":{"type":"integer","description":"结束时间，13 位毫秒时间戳（毫秒不是秒），' +
  '例如 1730102400000，必填，须晚于开始时间。"},' +
  '"isAllDay":{"type":"boolean","description":"是否全天日程，缺省 false。"},' +
  '"location":{"type":"string","description":"地点，可选。"},' +
  '"description":{"type":"string","description":"备注，可选。"},' +
  '"reminderMinutes":{"type":"integer","description":"提前多少分钟提醒，可选正数。不填则不提醒。"}},' +
  '"required":["title","startTime","endTime"]}';

// 修改入参 schema（id 必填；其余字段缺省保持原值；起止时间补「（毫秒不是秒）」与示例，
// 理由见 GET schema 注释）
export const UPDATE_CALENDAR_EVENT_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"id":{"type":"integer","description":"日程编号，必填，从查询结果获得。"},' +
  '"title":{"type":"string","description":"新标题。不填则保持原样。"},' +
  '"startTime":{"type":"integer","description":"新开始时间，13 位毫秒时间戳（毫秒不是秒），' +
  '例如 1730102400000。不填则保持原样。"},' +
  '"endTime":{"type":"integer","description":"新结束时间，13 位毫秒时间戳（毫秒不是秒），' +
  '例如 1730102400000。不填则保持原样。"},' +
  '"isAllDay":{"type":"boolean","description":"是否全天日程。不填则保持原样。"},' +
  '"location":{"type":"string","description":"新地点。不填则保持原样。"},' +
  '"description":{"type":"string","description":"新备注。不填则保持原样。"},' +
  '"reminderMinutes":{"type":"integer","description":"提前多少分钟提醒，正数。不填则保持原样。"}},' +
  '"required":["id"]}';

// 删除入参 schema（id 必填；删除不可恢复，每次弹确认卡）
export const DELETE_CALENDAR_EVENT_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"id":{"type":"integer","description":"日程编号，必填，从查询结果获得。"}},' +
  '"required":["id"]}';

// 模型面描述（desc = 何时调用本工具的唯一引导，能力单源红线——零 system prompt 改动）
export function buildGetCalendarEventsDesc(): string {
  return '查询日程。仅能查询本应用创建的日程，即助手写入系统日历的本应用日历，' +
    '用户系统日历里其他来源的日程不在范围内。默认查询今天全天，可传 start 与 end' +
    '（13 位毫秒时间戳）指定时间范围。返回日程的编号、标题、起止时间、全天标记、' +
    '地点与备注，最多返回 ' + CALENDAR_EVENTS_MAX + ' 条。修改或删除日程前先用本工具查到编号。';
}

export function buildCreateCalendarEventDesc(): string {
  return '创建日程。用户明确要求安排日程时调用，日程写入系统日历的本应用日历' +
    '（来源显示 AiControl，用户在系统日历中可见）。必填 title、startTime 与 endTime，' +
    '时间用 13 位毫秒时间戳；可选 isAllDay、location、description、reminderMinutes（提前' +
    '多少分钟提醒，正数，不填则不提醒）。创建会先弹出确认卡片征求用户同意，' +
    '创建成功后向用户复述标题与时间。';
}

export function buildUpdateCalendarEventDesc(): string {
  return '修改日程。先用查询工具拿到日程编号 id。只覆盖传入的字段，' +
    '未传的字段保持原样，可改 title、startTime、endTime、isAllDay、location、' +
    'description 与 reminderMinutes。只能修改本应用创建的日程。' +
    '修改会先弹出确认卡片征求用户同意，成功后向用户复述改了什么。';
}

export function buildDeleteCalendarEventDesc(): string {
  return '删除日程。先用查询工具拿到日程编号 id。只能删除本应用创建的日程。' +
    '删除不可恢复，每次都会先弹出确认卡片征求用户同意；用户未明确要求删除时不要调用。';
}

// 获取日程执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject，错误走 JSON 错误信息）
export class GetCalendarEventsExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let start: number = NaN;
    let end: number = NaN;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      start = readNumArg(parsed, 'start');
      end = readNumArg(parsed, 'end');
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const hasStart: boolean = Number.isFinite(start);
    const hasEnd: boolean = Number.isFinite(end);
    if (hasStart !== hasEnd) {
      return JSON.stringify({ error: 'start 与 end 需要成对提供，均为 13 位毫秒时间戳' });
    }
    if (hasStart && end <= start) {
      return JSON.stringify({ error: 'end 必须晚于 start，请检查时间范围' });
    }
    const guard: string = await calendarGuard();
    if (guard !== '') {
      return guard;
    }
    // 缺省窗口 = 今天全天（本地 0 点至次日 0 点，取本地 Date 构造——夏令时安全）
    let windowStart: number = start;
    let windowEnd: number = end;
    if (!hasStart) {
      const now: Date = new Date();
      windowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
      windowEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime();
    }
    try {
      const cal: calendarManager.Calendar = await obtainCalendar();
      const events: calendarManager.Event[] = await cal.getEvents(
        calendarManager.EventFilter.filterByTime(windowStart, windowEnd),
        ['id', 'title', 'startTime', 'endTime', 'isAllDay', 'location', 'description',
          'reminderTime']);
      events.sort((a: calendarManager.Event, b: calendarManager.Event): number =>
        a.startTime - b.startTime);
      // 双有界：条数上限 100 + 整串字符预算（100 条长文本会超 8192 硬切坏 JSON，到线即止
      // 并置 truncated，total 恒报匹配总数）
      const total: number = events.length;
      const limit: number = total > CALENDAR_EVENTS_MAX ? CALENDAR_EVENTS_MAX : total;
      const payloadEvents: CalendarEventPayload[] = [];
      let used: number = 0;
      let truncated: boolean = total > limit;
      for (let i: number = 0; i < limit; i++) {
        const item: CalendarEventPayload | null = toEventPayload(events[i]);
        if (item === null) {
          continue;
        }
        const itemJson: string = JSON.stringify(item);
        if (used + itemJson.length > CALENDAR_RESULT_BUDGET) {
          truncated = true;
          break;
        }
        payloadEvents.push(item);
        used += itemJson.length;
      }
      const payload: CalendarQueryPayload = {
        start: windowStart,
        end: windowEnd,
        total: total,
        count: payloadEvents.length,
        truncated: truncated,
        events: payloadEvents
      };
      return JSON.stringify(payload);
    } catch (err) {
      return JSON.stringify({ error: calendarErrorText('查询日程失败，请稍后重试', err as Object) });
    }
  }
}

// 创建日程执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject）
export class CreateCalendarEventExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let title: string = '';
    let start: number = NaN;
    let end: number = NaN;
    let isAllDay: boolean | undefined = undefined;
    let location: string = '';
    let description: string = '';
    let reminderMinutes: number = NaN;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      title = readStrArg(parsed, 'title');
      start = readNumArg(parsed, 'startTime');
      end = readNumArg(parsed, 'endTime');
      isAllDay = readBoolArg(parsed, 'isAllDay');
      location = readStrArg(parsed, 'location');
      description = readStrArg(parsed, 'description');
      reminderMinutes = readNumArg(parsed, 'reminderMinutes');
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    if (title === '') {
      return JSON.stringify({ error: '请提供 title 参数（日程标题）' });
    }
    if (!Number.isFinite(start) || !Number.isFinite(end)) {
      return JSON.stringify({ error: '请提供 startTime 与 endTime 参数（13 位毫秒时间戳）' });
    }
    if (end <= start) {
      return JSON.stringify({ error: 'endTime 必须晚于 startTime，请检查时间范围' });
    }
    if (Number.isFinite(reminderMinutes) && reminderMinutes <= 0) {
      return JSON.stringify({ error: 'reminderMinutes 需要是正数（提前分钟数）' });
    }
    const guard: string = await calendarGuard();
    if (guard !== '') {
      return guard;
    }
    // 事件组装（不填 id/instanceStartTime/instanceEndTime——官方口径；type 恒 NORMAL，
    // IMPORTANT 官方不建议三方用）
    const event: calendarManager.Event = {
      title: title,
      type: calendarManager.EventType.NORMAL,
      startTime: start,
      endTime: end,
      isAllDay: isAllDay === true
    };
    if (location !== '') {
      const loc: calendarManager.Location = { location: location };
      event.location = loc;
    }
    if (description !== '') {
      event.description = description;
    }
    // 提醒不默认设：仅显式传正数时转 reminderTime 单值（正 = 提前分钟）
    if (Number.isFinite(reminderMinutes)) {
      event.reminderTime = [reminderMinutes];
    }
    const tz: string = deviceTimeZone();
    if (tz !== '') {
      event.timeZone = tz;
    }
    try {
      const cal: calendarManager.Calendar = await obtainCalendar();
      const eventId: number = await cal.addEvent(event);
      // 回执标题裁剪（与查询回执/卡面同口径——SDK 允许 title 至 5000 字，未裁会让超长标题
      // 整串发给模型）
      return '已创建日程「' + clipText(title, CALENDAR_TITLE_CLIP) + '」，时间 ' +
        formatPeriod(start, end, isAllDay === true) +
        '，编号 ' + eventId + '。可在系统日历的 AiControl 日历中查看。';
    } catch (err) {
      return JSON.stringify({ error: calendarErrorText('创建日程失败，请稍后重试', err as Object) });
    }
  }
}

// 修改日程执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject）：先读回原日程 → 按传入
// 字段合并 → 整体 updateEvent。★ 官方未明示 updateEvent 为「整体替换」还是「部分更新」
// ——读回-合并按**保守侧**保留：若整体替换，不回填字段会被清空；若部分更新，读回冗余而
// 无害，两语义下均不劣于直接传差量。
// ★ 工具不写入、但用户经系统日历可补充的字段：
// ① attendee = 读回-合并，回填带**非空判据**（数组缺省或空不回填该键）——防接口对不支持
//   字段返回空值冒充真值，把部分更新语义下本可保留的字段清掉。
// ② recurrenceRule = 不读不填：官方默认查询字段集不含它，显式指定查询行为未定义，风险
//   不对称不做；其保留性依赖 updateEvent 为部分更新语义，真机观察（BLOCKED 日程节第 9 项）。
// ③ isLunar = 不碰：boolean 无空值形态，判据区分不了「真 false」与「接口不支持故缺省
//   false」；敞口仅限用户手动在 AiControl 日历建农历日程的边缘场景。
export class UpdateCalendarEventExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let id: number = NaN;
    let title: string = '';
    let start: number = NaN;
    let end: number = NaN;
    let isAllDay: boolean | undefined = undefined;
    let location: string = '';
    let description: string = '';
    let reminderMinutes: number = NaN;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      id = readNumArg(parsed, 'id');
      title = readStrArg(parsed, 'title');
      start = readNumArg(parsed, 'startTime');
      end = readNumArg(parsed, 'endTime');
      isAllDay = readBoolArg(parsed, 'isAllDay');
      location = readStrArg(parsed, 'location');
      description = readStrArg(parsed, 'description');
      reminderMinutes = readNumArg(parsed, 'reminderMinutes');
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    if (!Number.isFinite(id) || id <= 0) {
      return JSON.stringify({ error: '请提供日程编号 id（从查询结果获得）' });
    }
    if (title === '' && !Number.isFinite(start) && !Number.isFinite(end) &&
      isAllDay === undefined && location === '' && description === '' &&
      !Number.isFinite(reminderMinutes)) {
      return JSON.stringify({
        error: '请提供要修改的内容（title、startTime、endTime、isAllDay、location、description、reminderMinutes 至少一项）'
      });
    }
    if (Number.isFinite(reminderMinutes) && reminderMinutes <= 0) {
      return JSON.stringify({ error: 'reminderMinutes 需要是正数（提前分钟数）' });
    }
    const guard: string = await calendarGuard();
    if (guard !== '') {
      return guard;
    }
    try {
      const cal: calendarManager.Calendar = await obtainCalendar();
      let original: calendarManager.Event | null = null;
      try {
        const list: calendarManager.Event[] = await readEventsById(id);
        original = list.length > 0 ? list[0] : null;
      } catch (err) {
        return JSON.stringify({ error: calendarErrorText('读取原日程失败，本次未修改', err as Object) });
      }
      if (original === null) {
        return JSON.stringify({ error: '未找到编号为 ' + id + ' 的日程，本次未修改' });
      }
      const finalTitle: string = title !== '' ? title : (original.title ?? '');
      const finalStart: number = Number.isFinite(start) ? start : original.startTime;
      const finalEnd: number = Number.isFinite(end) ? end : original.endTime;
      if (finalEnd <= finalStart) {
        return JSON.stringify({ error: '修改后结束时间必须晚于开始时间，请检查时间参数' });
      }
      const finalAllDay: boolean = isAllDay !== undefined ? isAllDay : (original.isAllDay === true);
      // type 为 Event 必填字段（本 SDK d.ts 实查）——读回值在场则沿用，缺省按本应用约定的
      // NORMAL（IMPORTANT 官方不建议三方使用）
      const updated: calendarManager.Event = {
        id: id,
        type: original.type !== undefined ? original.type : calendarManager.EventType.NORMAL,
        title: finalTitle,
        startTime: finalStart,
        endTime: finalEnd,
        isAllDay: finalAllDay
      };
      const originalLocation: calendarManager.Location | undefined = original.location;
      if (location !== '') {
        const loc: calendarManager.Location = { location: location };
        updated.location = loc;
      } else if (originalLocation !== undefined && originalLocation.location !== undefined &&
        originalLocation.location !== '') {
        updated.location = originalLocation;
      }
      const finalDescription: string = description !== '' ? description :
        (original.description ?? '');
      if (finalDescription !== '') {
        updated.description = finalDescription;
      }
      const finalReminder: number[] | undefined = Number.isFinite(reminderMinutes) ?
        [reminderMinutes] : original.reminderTime;
      if (finalReminder !== undefined && finalReminder.length > 0) {
        updated.reminderTime = finalReminder;
      }
      // 参会人防御性回填（判据理由见本类头注释①）：工具不写 attendee，用户经系统日历补充
      // 过的参会人防「整体替换语义下被清空」——缺省或空数组一律不回填该键
      const originalAttendee: calendarManager.Attendee[] | undefined = original.attendee;
      if (originalAttendee !== undefined && originalAttendee.length > 0) {
        updated.attendee = originalAttendee;
      }
      const finalTimeZone: string = original.timeZone !== undefined && original.timeZone !== '' ?
        original.timeZone : deviceTimeZone();
      if (finalTimeZone !== '') {
        updated.timeZone = finalTimeZone;
      }
      await cal.updateEvent(updated);
      // ★ 改动字段与旧新值一趟收集——changed 喂原句「改动了 …」逐字不变；oldParts/newParts
      // 喂回执尾行（appendReceiptDiffTail 组装，值经 clipReceiptDiffValue 单源截断）。旧值
      // 取写前读回的 original；旧值空该行只留字段名，时间复用 formatPeriod 与回执同口径
      const changed: string[] = [];
      const oldParts: string[] = [];
      const newParts: string[] = [];
      const pushDiff = (label: string, oldText: string, newText: string): void => {
        changed.push(label);
        oldParts.push(oldText === '' ? label : label + ' ' + oldText);
        newParts.push(newText === '' ? label : label + ' ' + newText);
      };
      if (title !== '') {
        pushDiff('标题', original.title ?? '', finalTitle);
      }
      if (Number.isFinite(start) || Number.isFinite(end)) {
        pushDiff('时间', formatPeriod(original.startTime, original.endTime, original.isAllDay === true),
          formatPeriod(finalStart, finalEnd, finalAllDay));
      }
      if (isAllDay !== undefined) {
        pushDiff('全天标记', original.isAllDay === true ? '是' : '否', finalAllDay ? '是' : '否');
      }
      if (location !== '') {
        pushDiff('地点', originalLocation !== undefined && originalLocation.location !== undefined ?
          originalLocation.location : '', location);
      }
      if (description !== '') {
        pushDiff('备注', original.description ?? '', finalDescription);
      }
      if (Number.isFinite(reminderMinutes)) {
        pushDiff('提醒', reminderTextOf(original.reminderTime), reminderTextOf([reminderMinutes]));
      }
      const baseReply: string = '已修改日程「' + clipText(finalTitle, CALENDAR_TITLE_CLIP) +
        '」，改动了 ' + changed.join('、') + '，现时间 ' +
        formatPeriod(finalStart, finalEnd, finalAllDay) + '。';
      return appendReceiptDiffTail(baseReply, oldParts.join('\n'), newParts.join('\n'));
    } catch (err) {
      return JSON.stringify({ error: calendarErrorText('修改日程失败，请稍后重试', err as Object) });
    }
  }
}

// 删除日程执行器（注册在 ToolTypes；契约 = 恒 resolve 不 reject）：先尽力读回标题（回执
// 可读性），读回三态——命中用标题、读回成功但无此条 = 如实报未找到不执行、读回异常
//（权限/账户面）按 unknown 继续删除（确认卡已过，删除意图成立）
export class DeleteCalendarEventExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let id: number = NaN;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      id = readNumArg(parsed, 'id');
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    if (!Number.isFinite(id) || id <= 0) {
      return JSON.stringify({ error: '请提供日程编号 id（从查询结果获得）' });
    }
    const guard: string = await calendarGuard();
    if (guard !== '') {
      return guard;
    }
    try {
      const cal: calendarManager.Calendar = await obtainCalendar();
      let titleText: string = '';
      try {
        const list: calendarManager.Event[] = await readEventsById(id);
        if (list.length === 0) {
          return JSON.stringify({ error: '未找到编号为 ' + id + ' 的日程，本次未删除' });
        }
        titleText = list[0].title ?? '';
      } catch (err) {
        // 读回异常（权限/账户面）——按 unknown 处理继续删除（确认卡已过，删除意图成立）
      }
      await cal.deleteEvent(id);
      return titleText !== '' ? '已删除日程「' + clipText(titleText, CALENDAR_TITLE_CLIP) + '」。' :
        '已删除编号为 ' + id + ' 的日程。';
    } catch (err) {
      return JSON.stringify({ error: calendarErrorText('删除日程失败，请稍后重试', err as Object) });
    }
  }
}

// 写确认预检（create）：写意图成立 = title 与起止时间齐备且 end > start（参数坏返 null 交
// 执行器报参数错，无直发面）；卡面 detail = 时间段 +（有提醒时）提前 N 分钟提醒。
// ★ fail-closed（HttpPreflight H3-5 口径）：写意图成立之后的异常返保守人工卡——预检挂而
// 执行成 = 写操作无卡直发，恒 CONFIRM_ROUTE_HUMAN 不走档位豁免
export async function createCalendarEventNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const title: string = readStrArg(parsed, 'title');
    const start: number = readNumArg(parsed, 'startTime');
    const end: number = readNumArg(parsed, 'endTime');
    if (title === '' || !Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
      return null;
    }
    const isAllDay: boolean = readBoolArg(parsed, 'isAllDay') === true;
    const reminderMinutes: number = readNumArg(parsed, 'reminderMinutes');
    // ★ 参数坏档：reminderMinutes 负数/零 = 执行器必拒的参数错（「需要是正数」回执）——本
    // 预检返 null 交执行器报错，不弹卡（弹了用户白点一次允许再收参数错）
    if (Number.isFinite(reminderMinutes) && reminderMinutes <= 0) {
      return null;
    }
    try {
      const detailParts: string[] = [formatPeriod(start, end, isAllDay)];
      if (Number.isFinite(reminderMinutes) && reminderMinutes > 0) {
        detailParts.push('提前 ' + reminderMinutes + ' 分钟提醒');
      }
      return routeConfirmPrompt({
        text: '创建日程「' + clipText(title, CALENDAR_CARD_TITLE_CLIP) + '」',
        level: CONFIRM_LEVEL_WRITE,
        detail: detailParts.join('，')
      }, dataApproveMode());
    } catch (e) {
      return { text: '创建日程前的确认检查出现异常，本次创建需要你确认。',
        level: CONFIRM_LEVEL_WRITE, route: CONFIRM_ROUTE_HUMAN };
    }
  } catch (e) {
    // 坏形态阶段（JSON 解析失败）——执行器必然以参数错误回执拦下，无直发面
    return null;
  }
}

// 写确认预检（update）：写意图成立 = id 合法且有至少一个可改字段在场（缺 id / 无可改字段返
// null 交执行器报错）；卡面不复读原日程（标题在场用标题起头，否则报编号）。fail-closed 同上
export async function updateCalendarEventNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const id: number = readNumArg(parsed, 'id');
    if (!Number.isFinite(id) || id <= 0) {
      return null;
    }
    const title: string = readStrArg(parsed, 'title');
    const start: number = readNumArg(parsed, 'startTime');
    const end: number = readNumArg(parsed, 'endTime');
    const isAllDay: boolean | undefined = readBoolArg(parsed, 'isAllDay');
    const location: string = readStrArg(parsed, 'location');
    const description: string = readStrArg(parsed, 'description');
    const reminderMinutes: number = readNumArg(parsed, 'reminderMinutes');
    // ★ 参数坏档：负数/零 reminderMinutes = 执行器必拒的参数错——返 null 交执行器报错
    // 不弹卡（与 create 预检同口径）
    if (Number.isFinite(reminderMinutes) && reminderMinutes <= 0) {
      return null;
    }
    const fields: string[] = [];
    if (title !== '') {
      fields.push('标题');
    }
    if (Number.isFinite(start) || Number.isFinite(end)) {
      fields.push('时间');
    }
    if (isAllDay !== undefined) {
      fields.push('全天标记');
    }
    if (location !== '') {
      fields.push('地点');
    }
    if (description !== '') {
      fields.push('备注');
    }
    if (Number.isFinite(reminderMinutes) && reminderMinutes > 0) {
      fields.push('提醒');
    }
    if (fields.length === 0) {
      return null;
    }
    try {
      const headline: string = title !== '' ?
        '修改日程「' + clipText(title, CALENDAR_CARD_TITLE_CLIP) + '」' :
        '修改编号为 ' + id + ' 的日程';
      return routeConfirmPrompt({
        text: headline,
        level: CONFIRM_LEVEL_WRITE,
        detail: '将修改 ' + fields.join('、')
      }, dataApproveMode());
    } catch (e) {
      return { text: '修改日程前的确认检查出现异常，本次修改需要你确认。',
        level: CONFIRM_LEVEL_WRITE, route: CONFIRM_ROUTE_HUMAN };
    }
  } catch (e) {
    return null;
  }
}

// 写确认预检（delete，不可逆档——任何数据管理档位都进确认链恒问人）：写意图成立 = id 合法。
// 卡面 detail 尽力读回标题与时间（需 READ 权限，未授/读不到走保守卡）；读回之后的组装异常
// 返保守人工卡（fail-closed，恒不可逆档）
export async function deleteCalendarEventNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const id: number = readNumArg(parsed, 'id');
    if (!Number.isFinite(id) || id <= 0) {
      return null;
    }
    try {
      let headline: string = '删除编号为 ' + id + ' 的日程';
      let detail: string = '删除后无法恢复';
      try {
        // ★ 只读读回（restoreIfMissing=false）：预检在用户决策前不得产生系统日历写入（账户
        // 重建）——账户被删时读回抛出落保守卡；用户确认后的执行链仍走重建自愈
        const list: calendarManager.Event[] = await readEventsById(id, false);
        if (list.length > 0) {
          const ev: calendarManager.Event = list[0];
          headline = '删除日程「' + clipText(ev.title ?? '', CALENDAR_CARD_TITLE_CLIP) + '」';
          detail = '时间 ' + formatPeriod(ev.startTime, ev.endTime, ev.isAllDay === true) +
            '。删除后无法恢复';
        }
      } catch (e) {
        // 读回失败（权限未授 / 账户不可达）——保守卡路径：卡面只有编号与「删除后无法恢复」，
        // 档位与恒问人语义不受影响
      }
      return routeConfirmPrompt({
        text: headline,
        level: CONFIRM_LEVEL_IRREVERSIBLE,
        detail: detail
      }, dataApproveMode());
    } catch (e) {
      return { text: '删除日程前的确认检查出现异常，本次删除需要你确认。',
        level: CONFIRM_LEVEL_IRREVERSIBLE, route: CONFIRM_ROUTE_HUMAN };
    }
  } catch (e) {
    return null;
  }
}
