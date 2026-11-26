// Web 读 API 处理器——WS 读 API 三面（会话列表 / 历史消息 / 活跃 run）的消息路由与投影。
// 输入已鉴权连接的 api 请求信封，输出发回同连接的 api_result 响应信封，读数全部经工程既有
// 读口；纯函数面集中在文件上半（零依赖标记段，断言脚本剥 import 直跑）。
// 信封契约（协议常量冻结面）：请求 {type:'api', reqId, method, params}；响应 {type:
// 'api_result', reqId, ok, data | error:{code,message}}——reqId 从请求透传，客户端据其配对
// 请求与响应；未知 method 回错误信封不静默。方法名 = list_conversations / read_messages /
// active_runs（任务书口径，U7 前端按此对齐）。
// 读口纪律（红线）：本件零 SQL 字符串、零 sharedRdbStore 句柄——会话列表 = queryConversations
//（2026-11-17 整体退役加密会话笔：原 locked 会话投影层滤出随功能退役删除，全量会话同权）；
// 历史消息 = conversationLoadRoute + readPathPageRows（图会话沿 activeBranch 父链路径，分支
// 真值不直查；cursor 外部输入先证归属——queryNodeRow 会话核验 + isNodeOnActivePath 活动分支
// 链判据，防任意消息 id 沿 parent 链越权读出跨会话/非活动分支内容）；存在性核验 =
// queryConversationRowByIdForRead（ForRead 族——不存在即 404 语义）；活跃 run =
// chatSessionRuntime.activeSessions()（只读枚举面，只消费不修改）。
// DB 未就绪判据 = ChatDb.isReady()（whenReady 先例同源）。
// 载体无关：本件零 import 本域载体件（WsGateway/TransportCarrier 均不在依赖面），回信经注入
// 的 WebApiSender 回调发出——SSE 备胎换载体时本件零改。
// 显示语义不漂移：消息投影复用 chatMessagesFromRows（行→视图消息单源，思考块合成 + 工具卡
// 摘要 60 字预览 + 坏工具行容错跳过——与手机历史回放同一映射，本件不发明第二份工具摘要逻辑）。
// 依赖纪律（零环）：只引读域叶子（ChatDb 读面 / ChatDbReadSearch / ChatContextSource /
// AssistantDb）+ ChatSessionRuntime + ChatMessageProjection（纯投影域）；禁 import UI 件
//（ChatPage/ChatPageLifecycle 族）与本域载体件。内存防线：无状态——路由表常驻（三条目），
// 零缓存零簿记，页预算常量约束单条响应体积（全中文 3 字节折算 300000 字符 ≈ 900KB，对
// 5242864B 协议上限 5 倍边际）。
import { ConversationRow, isReady, MessageRow, queryConversations } from '../store/ChatDb';
import { ChatReadConvRow, queryConversationRowByIdForRead } from '../store/ChatDbReadSearch';
import { ConversationLoadRoute, conversationLoadRoute, isNodeOnActivePath, queryNodeRow,
  readPathPageRows, ROUTE_BLOCKED } from '../chat/ChatContextSource';
import { chatSessionRuntime } from '../chat/ChatSessionRuntime';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, historyFilterIds } from '../store/AssistantDb';
import { chatMessagesFromRows } from '../../components/chat/ChatMessageProjection';
import { ChatMessage } from '../../components/chat/ChatMessageCompose';

// ── 信封与错误码（type 值与 WsGateway 传输层控制族 ping/pong/auth 错开；与中枢业务
// 信封 round_begin 族亦错开——三方互不抢占）──

export const WEB_API_REQUEST_TYPE: string = 'api';
export const WEB_API_RESULT_TYPE: string = 'api_result';

// 错误码（明确错误码红线：每分支一个码，客户端可编程判别）
export const WEB_API_ERR_BAD_ENVELOPE: string = 'bad_envelope';   // 非 api 信封 / 脏 JSON
export const WEB_API_ERR_UNKNOWN_METHOD: string = 'unknown_method';
export const WEB_API_ERR_BAD_PARAMS: string = 'bad_params';       // 参数缺失/类型不符
export const WEB_API_ERR_DB_NOT_READY: string = 'db_not_ready';   // EntryAbility 异步初始化未完
export const WEB_API_ERR_NOT_FOUND: string = 'not_found';         // 会话 id 不存在（404 语义）
export const WEB_API_ERR_NOT_READABLE: string = 'not_readable';   // 旧格式墓碑（blocked 路由）
export const WEB_API_ERR_INTERNAL: string = 'internal';           // 读口异常等未分类失败

// 请求信封（严格解析产物）
export interface WebApiRequest {
  readonly type: string;
  readonly reqId: string;
  readonly method: string;
  readonly params: Record<string, Object>;
}

// 响应信封负载形态（error 二员结构）
export interface WebApiErrorBody {
  code: string;
  message: string;
}

export interface WebApiEnvelope {
  type: string;
  reqId: string;
  ok: boolean;
  data?: Object;
  error?: WebApiErrorBody;
}

// ── 纯函数面（零依赖标记段，断言脚本剥 import 直跑）──

// 请求信封严格解析：JSON 根对象 + type 恰为 'api' + reqId/method 均 string（method 非空）+
// params 可缺省（缺省空表）但必须在场时为对象——其余（脏 JSON / 非对象根 / type 不符 / 缺员 /
// params 非对象）一律 null（fail-closed，宁可拒不可炸）
export function parseWebApiRequest(text: string): WebApiRequest | null {
  let raw: Object;
  try {
    raw = JSON.parse(text) as Object;
  } catch (e) {
    return null;
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const rec: Record<string, Object> = raw as Record<string, Object>;
  const t: Object | undefined = rec['type'];
  const rid: Object | undefined = rec['reqId'];
  const m: Object | undefined = rec['method'];
  if (typeof t !== 'string' || t !== WEB_API_REQUEST_TYPE) {
    return null;
  }
  if (typeof rid !== 'string' || typeof m !== 'string' || m === '') {
    return null;
  }
  let params: Record<string, Object> = {};
  const p: Object | undefined = rec['params'];
  if (p !== undefined) {
    if (p === null || typeof p !== 'object' || Array.isArray(p)) {
      return null;
    }
    params = p as Record<string, Object>;
  }
  const req: WebApiRequest = { type: t, reqId: rid, method: m, params: params };
  return req;
}

// 成功响应信封（reqId 透传——客户端配对键）
export function buildWebApiOkResult(reqId: string, data: Object): string {
  const env: WebApiEnvelope = { type: WEB_API_RESULT_TYPE, reqId: reqId, ok: true, data: data };
  return JSON.stringify(env);
}

// 失败响应信封（ok 恒 false + error 二员；未知 method / 坏信封 / 业务错误共用）
export function buildWebApiErrResult(reqId: string, code: string, message: string): string {
  const err: WebApiErrorBody = { code: code, message: message };
  const env: WebApiEnvelope = { type: WEB_API_RESULT_TYPE, reqId: reqId, ok: false, error: err };
  return JSON.stringify(env);
}

// 参数取值（容错抽取：类型不符回缺省，不炸解析——畸形参数落钳位/缺省路径）
export function webParamString(params: Record<string, Object>, key: string): string {
  const v: Object | undefined = params[key];
  return typeof v === 'string' ? v : '';
}

export function webParamNumber(params: Record<string, Object>, key: string, fallback: number): number {
  const v: Object | undefined = params[key];
  if (typeof v === 'number' && Number.isFinite(v)) {
    return v;
  }
  return fallback;
}

// ── 分页钳位（AppPreferencesWeb.clampWebPort 同风格：整数 + 值域内原样，否则回缺省）──

// 会话列表页容量（列表查询本体走 phone 全量口径，web 侧 limit/offset 在全量结果上切片控载荷，
// 缺省 50 = QUERY_TAIL_LIMIT 同量级）
export const WEB_LIST_LIMIT_DEFAULT: number = 50;
export const WEB_LIST_LIMIT_MAX: number = 500;

// 历史消息页容量（与 readPathPageRows 的 limit 同轴——QUERY_TAIL_LIMIT 同量级）
export const WEB_MSG_LIMIT_DEFAULT: number = 50;
export const WEB_MSG_LIMIT_MAX: number = 200;

export function clampWebListLimit(raw: number): number {
  if (!Number.isInteger(raw) || raw < 1 || raw > WEB_LIST_LIMIT_MAX) {
    return WEB_LIST_LIMIT_DEFAULT;
  }
  return raw;
}

export function clampWebMsgLimit(raw: number): number {
  if (!Number.isInteger(raw) || raw < 1 || raw > WEB_MSG_LIMIT_MAX) {
    return WEB_MSG_LIMIT_DEFAULT;
  }
  return raw;
}

// 偏移钳位（负值/非整数归 0——offset 无「回缺省」语义，下界即安全值）
export function clampWebListOffset(raw: number): number {
  if (!Number.isInteger(raw) || raw < 0) {
    return 0;
  }
  return raw;
}

// ── 消息页字符预算（「超长会话一律分页，不做单条大包」的确定性装填计划）──

// 单条响应字符预算（全中文 3 字节折算 ≈900KB < 1MB 预算线；纯 ASCII 300KB）
export const WEB_MSG_PAGE_BUDGET_CHARS: number = 300000;

// 装填计划：输入页内各行体积（序 = 最早在前），从最新侧往回装填——
// · 整行装得下 → 全装（truncatedIndex 恒 -1）；
// · 装不下但页内已有完整行 → 该行**整行让位**（不入本页）并停止——更早行一并让位；页游标
//   = 最早已装完整行 id（readPathPage 翻页不含自身），下一页带全预算重取，超预算行整行补齐
//   （★ 让位行若截断装填且以自身当游标，翻页不含自身 → 被截掉的尾部永久不可达）；
// · 装不下且页内尚无完整行（唯一候选行本身 > 预算）→ 截断装填（cutAllowance = 可用字符数）；
//   单条超预算消息无行内续读端点，尾部限制登记 V2；
// · 预算耗尽 → 停止（更早行让位同上）；
// · 预算 ≤ 0 或空页 → includeFrom = -1（空页）。
// includeFrom = 最早已装行下标；truncatedIndex = 截断行下标（恒 = includeFrom，-1 = 无截断）
export interface WebRowBudgetPlan {
  includeFrom: number;
  truncatedIndex: number;
  cutAllowance: number;
}

export function planWebRowBudget(rowLens: number[], budgetChars: number): WebRowBudgetPlan {
  const n: number = rowLens.length;
  let used: number = 0;
  let includeFrom: number = -1;
  let truncatedIndex: number = -1;
  let cutAllowance: number = 0;
  if (budgetChars > 0) {
    for (let i = n - 1; i >= 0; i--) {
      const remaining: number = budgetChars - used;
      if (remaining <= 0) {
        break;
      }
      if (rowLens[i] <= remaining) {
        used += rowLens[i];
        includeFrom = i;
        continue;
      }
      // 已有完整行 → 超预算行整行让位（下一页带全预算重取，避免截断尾部不可达）
      if (includeFrom >= 0) {
        break;
      }
      // 唯一候选行本身超预算 → 截断装填（无行内续读端点，见函数头注释）
      truncatedIndex = i;
      includeFrom = i;
      cutAllowance = remaining;
      break;
    }
  }
  const plan: WebRowBudgetPlan = { includeFrom: includeFrom, truncatedIndex: truncatedIndex,
    cutAllowance: cutAllowance };
  return plan;
}

// ── DTO 形态（web 渲染字段面：V1 = id/role/text/createdAt/truncated + 工具卡摘要二员）──

export interface WebConversationDto {
  id: string;
  title: string;
  updatedAt: number;
  favorite: boolean;
}

export interface WebMessageDto {
  id: string;
  role: string;        // user / assistant / thinking / tool / summary / clear / notice（kind 直映）
  text: string;        // 正文；tool 行 = 60 字预览摘要（chatMessagesFromRows 单源）
  createdAt: number;
  truncated: boolean;  // 预算截断标记（web 端据此提示「内容过长已截断」）
  toolName?: string;   // 仅 tool 行
  toolState?: string;  // 仅 tool 行（running / done / error / cancelled）
}

export interface WebListData {
  conversations: WebConversationDto[];
  total: number;
  offset: number;
  limit: number;
}

export interface WebHistoryData {
  conversationId: string;
  messages: WebMessageDto[];
  nextCursor: string;  // '' = 到顶；否则 = 下一页游标（本页最早已装行 id——readPathPage 翻页语义不含自身）
}

export interface WebActiveRunsData {
  runs: string[];
}

// ── 处理器面（读口消费——本段以下引用工程读口，直跑副本惰性求值不触达）──

// 业务错误（带错误码；dispatch 统一收口为错误信封）
class WebApiError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

// DB 就绪闸（whenReady 先例同源判据——isReady 粘滞真值；不排队等待：读请求即时失败回明确
// 错误码优于压 5s 队列，客户端见码重试）
function ensureWebDbReady(): void {
  if (!isReady()) {
    throw new WebApiError(WEB_API_ERR_DB_NOT_READY, '数据库未就绪，请稍后重试');
  }
}

// 消息 DTO 投影（text/truncated 由调用侧按预算计划给出；工具摘要单源在 chatMessagesFromRows）
// ★ serverstep 最小机械适配（DS 全家桶接入批 S2⑧，2026-11-14；web 冻结面——任务书 S2⑧）：
// serverstep 行按 tool 行同款降级（正文空 + 状态字段），只保协议面形状不新增字段不增强；
// S2 期回放投影尚不合成 serverstep 行（行合成随 S3），本支为防御位——合成落地后 web 消费方
// 天然不炸
function webMessageDtoOf(m: ChatMessage, text: string, truncated: boolean): WebMessageDto {
  const dto: WebMessageDto = {
    id: m.id,
    role: m.kind,
    text: text,
    createdAt: m.createdAt ?? 0,
    truncated: truncated
  };
  if (m.kind === 'tool' || m.kind === 'serverstep') {
    dto.toolName = m.toolName;
    dto.toolState = m.toolState;
  }
  return dto;
}

// 消息行显示文本（tool 行取摘要预览，其余取正文——与手机卡面同源）。serverstep 同款降级
//（摘要位取 toolDisplayText——S2⑧ 最小机械适配，与 webMessageDtoOf 同理由）
function webMessageTextOf(m: ChatMessage): string {
  if (m.kind === 'tool' || m.kind === 'serverstep') {
    return m.toolDisplayText ?? '';
  }
  return m.text;
}

// 会话列表：phone 会话列表 Dao 面全量（当前助手口径 historyFilterIds——与手机历史页同一过滤
// 先例）→ limit/offset 切片控载荷
async function listConversationsHandler(params: Record<string, Object>): Promise<Object> {
  ensureWebDbReady();
  const limit: number = clampWebListLimit(webParamNumber(params, 'limit', WEB_LIST_LIMIT_DEFAULT));
  const offset: number = clampWebListOffset(webParamNumber(params, 'offset', 0));
  const activeId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  const rows: ConversationRow[] = await queryConversations(historyFilterIds(activeId));
  const visible: WebConversationDto[] = [];
  for (const row of rows) {
    const dto: WebConversationDto = { id: row.id, title: row.title, updatedAt: row.updatedAt,
      favorite: row.favorite };
    visible.push(dto);
  }
  const pageRows: WebConversationDto[] = visible.slice(offset, offset + limit);
  const data: WebListData = { conversations: pageRows, total: visible.length,
    offset: offset, limit: limit };
  return data;
}

// 历史消息：存在性核验（ForRead——不存在回 null）→ 读路由（blocked =
// 旧格式墓碑不可读）→ readPathPageRows 沿 activeBranch 父链取页 → 预算装填投影
async function readMessagesHandler(params: Record<string, Object>): Promise<Object> {
  ensureWebDbReady();
  const cid: string = webParamString(params, 'conversationId');
  if (cid === '') {
    throw new WebApiError(WEB_API_ERR_BAD_PARAMS, 'conversationId 缺失');
  }
  const cursor: string = webParamString(params, 'cursor'); // '' = 首页（尾部窗口）
  const limit: number = clampWebMsgLimit(webParamNumber(params, 'limit', WEB_MSG_LIMIT_DEFAULT));
  const convRow: ChatReadConvRow | null = await queryConversationRowByIdForRead(cid);
  if (convRow === null) {
    throw new WebApiError(WEB_API_ERR_NOT_FOUND, '会话不存在');
  }
  const route: ConversationLoadRoute = await conversationLoadRoute(cid);
  if (route.route === ROUTE_BLOCKED) {
    throw new WebApiError(WEB_API_ERR_NOT_READABLE, '会话为旧格式，不可读取');
  }
  // ★ cursor 为外部输入，必须先证归属再交给读路由——readPathPage 以 WHERE id = ? 从游标节点
  // 沿 parent 链读，不校验节点会话，任意消息 id 可越权读出跨会话或非活动分支内容。读行走既有
  // queryNodeRow（本件零新增 SQL；游标行须与 cid 同会话），路径判据走既有 isNodeOnActivePath
  //（沿 activeBranch 父链可达）。不存在/跨会话 → not_found（不泄露存在性）；同会话非活动
  // 分支 → bad_params（切分支后的旧游标，客户端从首页重取）。首页无 cursor 不进入本段，路径
  // 零改动。
  if (cursor !== '') {
    const cursorRow: MessageRow | null = await queryNodeRow(cursor);
    if (cursorRow === null || cursorRow.conversationId !== cid) {
      throw new WebApiError(WEB_API_ERR_NOT_FOUND, '会话不存在');
    }
    const onActivePath: boolean = await isNodeOnActivePath(cid, route.branchId, cursor);
    if (!onActivePath) {
      throw new WebApiError(WEB_API_ERR_BAD_PARAMS, '游标不在当前分支，请从首页重取');
    }
  }
  const rows: MessageRow[] = await readPathPageRows(cid, route.branchId,
    cursor === '' ? null : cursor, limit);
  // 预算计划（行体积 = 正文 + 思考；tool 行 content 即载荷串同计）
  const rowLens: number[] = [];
  for (const row of rows) {
    rowLens.push(row.content.length + row.reasoning.length);
  }
  const budget: WebRowBudgetPlan = planWebRowBudget(rowLens, WEB_MSG_PAGE_BUDGET_CHARS);
  const messages: WebMessageDto[] = [];
  if (budget.includeFrom >= 0) {
    const included: MessageRow[] = rows.slice(budget.includeFrom);
    const cutRowId: string = budget.truncatedIndex >= 0 ? rows[budget.truncatedIndex].id : '';
    let cutLeft: number = budget.cutAllowance;
    const msgs: ChatMessage[] = chatMessagesFromRows(included);
    for (const m of msgs) {
      const isCutRow: boolean = cutRowId !== '' &&
        (m.id === cutRowId || m.id === 'think-' + cutRowId);
      const text: string = webMessageTextOf(m);
      if (!isCutRow) {
        messages.push(webMessageDtoOf(m, text, false));
        continue;
      }
      // 截断行：思考→正文序装填 cutAllowance，超出的成员清空并标截断（页序不变）
      let outText: string = text;
      let truncated: boolean = false;
      if (cutLeft <= 0) {
        outText = '';
        truncated = text !== '';
      } else if (text.length > cutLeft) {
        outText = text.substring(0, cutLeft);
        truncated = true;
        cutLeft = 0;
      } else {
        cutLeft -= text.length;
      }
      messages.push(webMessageDtoOf(m, outText, truncated));
    }
  }
  // 到顶判定：窗口满页（上方可能还有祖先）或预算让位（本页有更早行未装）→ 给游标；
  // 短页且全装 = 路径到顶。游标 = 最早已装行 id（readPathPage 翻页不含自身，让位行是其
  // 祖先、下一页自然补齐）
  const moreAbove: boolean = rows.length >= limit || budget.includeFrom > 0;
  const nextCursor: string = moreAbove && budget.includeFrom >= 0 ?
    rows[budget.includeFrom].id : '';
  const data: WebHistoryData = { conversationId: cid, messages: messages, nextCursor: nextCursor };
  return data;
}

// 活跃 run：activeSessions 只读枚举（纯进程内存态，无 DB 依赖——不设就绪闸）
async function activeRunsHandler(_params: Record<string, Object>): Promise<Object> {
  const data: WebActiveRunsData = { runs: chatSessionRuntime.activeSessions() };
  return data;
}

// ── 路由表（method→handler 单源；新方法只在此登记）──

export const WEB_API_METHOD_LIST: string = 'list_conversations';
export const WEB_API_METHOD_READ: string = 'read_messages';
export const WEB_API_METHOD_ACTIVE: string = 'active_runs';

export type WebApiHandler = (params: Record<string, Object>) => Promise<Object>;

const WEB_API_ROUTES: Map<string, WebApiHandler> = new Map<string, WebApiHandler>();
WEB_API_ROUTES.set(WEB_API_METHOD_LIST, listConversationsHandler);
WEB_API_ROUTES.set(WEB_API_METHOD_READ, readMessagesHandler);
WEB_API_ROUTES.set(WEB_API_METHOD_ACTIVE, activeRunsHandler);

export function webApiMethodKnown(method: string): boolean {
  return WEB_API_ROUTES.has(method);
}

// ── 分发入口（manager 的 CarrierEvents.onMessage 接入——WsGateway fail-closed ② 保证只有
//    已鉴权连接的消息到达此处，本件不重复鉴权）──

// 回信通道（载体无关：manager 注入动态面载体的 sendTo；SSE 备胎换载体时本件零改）
export interface WebApiSender {
  send(connId: string, text: string): Promise<boolean>;
}

// 分发：坏信封/未知 method/业务错/读口异常四路全落错误信封（不静默）；发送失败由 sender
// 侧处置（载体件发送失败即断连的快照语义兜底），此处不等待不记账
export function dispatchWebApi(connId: string, text: string, sender: WebApiSender): void {
  const fire = (reply: string): void => {
    sender.send(connId, reply).catch((): void => {
    });
  };
  const req: WebApiRequest | null = parseWebApiRequest(text);
  if (req === null) {
    fire(buildWebApiErrResult('', WEB_API_ERR_BAD_ENVELOPE, '消息不是有效的请求信封'));
    return;
  }
  const handler: WebApiHandler | undefined = WEB_API_ROUTES.get(req.method);
  if (handler === undefined) {
    fire(buildWebApiErrResult(req.reqId, WEB_API_ERR_UNKNOWN_METHOD, '未知方法 ' + req.method));
    return;
  }
  handler(req.params).then((data: Object): void => {
    fire(buildWebApiOkResult(req.reqId, data));
  }).catch((e: Object): void => {
    if (e instanceof WebApiError) {
      fire(buildWebApiErrResult(req.reqId, e.code, e.message));
      return;
    }
    fire(buildWebApiErrResult(req.reqId, WEB_API_ERR_INTERNAL, (e as Error).message));
  });
}
