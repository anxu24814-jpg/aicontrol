// DeepSeek 服务端工具域（DS 全家桶接入批 S1；任务书 = docs/任务书-DS全家桶接入-20261114.md
// 〔自检修订版〕§0 / §6-S1）。职责单句：DS 会话判定与官方服务端工具的路由判据单源——镜像
// 键写点（ChatPage.setConnInfo）、菜单项（ChatPromptSheet）、发送侧声明（S2 collectTools）、
// 附件分叉（S4）四方共用本件常量与判定，禁在消费方散写 baseUrl 子串或自建服务商枚举。
// · 模型限定（§0 明示）：官方 web_tools / files 指南均写「请使用 deepseek-flash 模型」——
//   判据四合一 = baseUrl 含 api.deepseek.com 且 protocol='openai' 且 endpoint='chat' 且模型
//   id 恰为 'deepseek-flash'。★ 禁用 ModelRegistry.supportsDeepSeekProfile 作本判据：历史名
//   命中域 = DeepSeek/GLM/Kimi 三家共享开关方言（该函数注释明示），作 DS 判据会误放行。
//   其余模型可用性列 S0④ 实测，实测放行再扩判据（只改本件）。
// · 路由存储（任务书 §5 首条）：官方档偏好 = 独立布尔键 PREF_DS_OFFICIAL_WEB_KEY（默认
//   true，代决 1），哨兵 id DS_OFFICIAL_WEB_ID 只在菜单回调链流转——禁落任何持久层（全局
//   引擎键 PREF_SEARCH_ENGINE_KEY 的消费方〔resolveEngineId / webEngineLabel / 菜单勾选 /
//   备份面〕全按「值域 = 引擎注册表 id」建模，伪值会静默丢手选引擎 + 裸显内部标识）。
// · kill switch（DS_SERVER_TOOLS_ENABLED 置 false = 整批一键回现状，任务书 §4.6 / §10）：
//   菜单项隐藏（镜像键恒 false）+ 发送侧不声明（dsOfficialWebActive 恒 false）+ 附件走本地
//   解析 + 回传省略。
import { AiConnection, AiToolDef, ENDPOINT_CHAT, ENDPOINT_RESPONSES, PROTOCOL_OPENAI,
  PendingAttachment } from './AiTypes';
import { normalizeModelRegistryBaseUrl } from './ModelRegistry';
import { isDsOfficialWebPreferred } from '../AppPreferences';

// DS 官方档菜单哨兵 id（仅回调链流转：WebSearchMenu 官方项 onClick → onPickEngine 上行 →
// ChatSessionOverrideCtrl.pickWebEngine 分流——禁写进任何持久层 / 偏好键 / 引擎注册表，
// 负向钉守 = scripts/assert-ds-integration.mjs 甲路由组）
export const DS_OFFICIAL_WEB_ID: string = 'ds_official';

// ── 服务端工具声明常量（S2①，2026-11-14；§0「声明」条官方字面量）──两工具恒同时声明
//（demo store.ts 形制；同一工具声明两次报错、web_search_options 400——本应用不产这两形态）。
// 字面量单源本件：collectTools concat（S2①）与 compose serverType 裸项产出（S2②）共用，
// 禁消费方散写字面量
export const DS_SERVER_TOOL_WEB_SEARCH: string = 'deepseek_web_search';
export const DS_SERVER_TOOL_READ_URL: string = 'deepseek_read_url';

// 官方档轮的服务端工具声明对（collectTools 末尾 concat 消费）：AiToolDef 以 serverType
// 标记（compose 产 {type} 裸项），name = 工具 type 串（声明面唯一标识，token 估算
// toolDefsJson 与「未声明不执行」四面同源不变量照常覆盖；description/parametersJson 空——
// 服务端工具无 schema 无参数，官方形态非 function 包裹）
export function dsServerToolDefs(): AiToolDef[] {
  return [
    { name: DS_SERVER_TOOL_WEB_SEARCH, description: '', parametersJson: '',
      serverType: DS_SERVER_TOOL_WEB_SEARCH },
    { name: DS_SERVER_TOOL_READ_URL, description: '', parametersJson: '',
      serverType: DS_SERVER_TOOL_READ_URL }
  ];
}

// 「DeepSeek 官方可用」镜像键（bool 广播键——ChatPage.setConnInfo 按 kill switch × 连接
// 判据写入，照 CHAT_OFF_SUPPORTED_KEY 同点同链先例；ChatPromptSheet 联网菜单官方项显隐、
// 文档解析行卡守卫与卡面官方态 @StorageProp 自订阅〔坑16 正解〕。只写不删：残留 bool 无害，
// 坑15 只发生在清空场景）
export const CHAT_DS_OFFICIAL_AVAILABLE_KEY: string = 'chatDsOfficialAvailable';

// 「当前连接是 Responses 形态」镜像键（bool 广播键，ChatPage.setConnInfo 与上键同点同链写）：
// 文档解析行卡在 Responses 连接上仍可开、上传也成功，但 Responses 的 file item 形态官方未给
//（任务书 §1-7③），发送前必须拦下并给可执行提示——静默丢附件比阻断更糟。消费方唯一 =
// AttachmentUtil.attachBlockingReason（经 dsServerDocBlockReason 判定）
export const CHAT_DS_RESPONSES_ENDPOINT_KEY: string = 'chatDsResponsesEndpoint';

// 整批 kill switch（默认 true = 功能在）。false 语义见文件头；只改这一处即整批回现状。
export const DS_SERVER_TOOLS_ENABLED: boolean = true;

// DS 官方连接判据（§0 四合一，纯函数）：baseUrl 归一化后含 api.deepseek.com 且协议 = OpenAI
// 且接口形态 = chat 且模型 id 恰为 'deepseek-flash'。conn = null（连接解析落空）恒 false
//（fail-closed：判不出官方连接就不给官方入口）。归一化复用 ModelRegistry 同款（trim + 小写
// + 去尾斜杠——baseUrl 末尾斜杠容忍与协议层同口径）。
export function isDsFlashConnection(conn: AiConnection | null): boolean {
  if (conn === null) {
    return false;
  }
  // 二期 S3：endpoint 由 'chat' 扩为 'chat' | 'responses'（官方两份文档都承诺同一模型与
  // 官方能力面；Anthropic/Gemini 形态仍不吃本判据——它们不出官方项）
  const endpointOk: boolean = conn.endpoint === ENDPOINT_CHAT ||
    conn.endpoint === ENDPOINT_RESPONSES;
  return normalizeModelRegistryBaseUrl(conn.baseUrl).includes('api.deepseek.com') &&
    conn.protocol === PROTOCOL_OPENAI && endpointOk && conn.model === 'deepseek-flash';
}

// 工具共存冲突文案判据（二期 S3 / 任务书 §1-7，纯函数）：官方无明文「服务端工具与客户端
// function 工具可否同声明」——按可共存实现，400 且错误体提到工具冲突时运行时剔除客户端
// function 工具重发一次。判据 = 提到工具（tool/工具）且提到冲突/互斥（conflict/exclusive/
// 冲突/不能同时）；命中与否只影响一次重发，不改请求形态单源
// 输入侧内容安全拦截判据（二期 #6 / 任务书 §6-S2 验收⑤）：官方 400 文案
// `Content Exists Risk`；中转向可能本地化为「输入内容…」。命中即走「归还输入 + 提示可改
// 可重发」分支，不当网络失败、不切 key、不自动重试（输入不改重试必然同错）
export function isDsInputRiskMessage(message: string): boolean {
  const lower: string = message.toLowerCase();
  return lower.includes('content exists risk') || lower.includes('content_risk') ||
    message.includes('输入内容未通过') || message.includes('输入内容存在风险');
}

export function isDsToolConflictMessage(message: string): boolean {
  const lower: string = message.toLowerCase();
  const mentionsTool: boolean = lower.includes('tool') || message.includes('工具');
  const mentionsConflict: boolean = lower.includes('conflict') ||
    lower.includes('exclusive') || message.includes('冲突') || message.includes('不能同时');
  return mentionsTool && mentionsConflict;
}

// 上传目标连接选取（S4 附件上传链，2026-11-14 自检报告 §4.1 修）：活连接优先、DB 链回落。
// 活连接 = ChatPage.conn（本会话内存覆盖的同链真值）——新建会话尚无 conversations 行时，
// 模型覆盖只存在页面内存，DB 链查不到；只读 DB 会落到默认助手连接，多服务商下误判失败。
// 两源都按 isDsFlashConnection 复核（fail-closed：判不出官方连接 = null，防误传非官方端点）。
// 纯函数（无 IO）供断言直跑；消费方单源 = DsFilesClient.resolveDsUploadTarget。
export function dsUploadConnOf(live: AiConnection | null,
  fromDb: AiConnection | null): AiConnection | null {
  if (isDsFlashConnection(live)) {
    return live;
  }
  if (isDsFlashConnection(fromDb)) {
    return fromDb;
  }
  return null;
}

// 官方档成立总判（发送侧声明 / 历史回传 / 附件分叉共用的唯一路由判据；三参为纯直跑面，
// kill switch 与官方档偏好两因子经常量 / 读值封装内读——非全纯函数，断言直跑经 AppStorage
// 桩图翻转偏好因子）：kill
// switch × 官方档偏好 × 连接四合一 × 联网域允许 × 无服务端解析件。末位因子 = 文档 × 官方
// 联网互斥回退（任务书 §4.3——文档在场自动回退自带引擎；S0② 实测放行则删该因子，S4⑤）。
// 消费方禁另写组合判据（改判据只动本件）。
export function dsOfficialWebActive(conn: AiConnection | null, webDomainAllowed: boolean,
  hasServerDoc: boolean): boolean {
  return DS_SERVER_TOOLS_ENABLED && isDsOfficialWebPreferred() &&
    isDsFlashConnection(conn) && webDomainAllowed && !hasServerDoc;
}

// ── call 对象字段提取（S2⑤ 步骤行合成用——协议字面量单源本件，消费方禁散写）──
// call 结构（§0 响应结构条）：type（两工具名）/ kind / action / status（completed/failed）/
// sources / page / signature / error。坏 JSON / 缺键防御回缺省（回放容错不炸）。
// serverStepNameOf = 步骤行名（type 工具名原串——S3 渲染映射官方短句）；
// serverStepStateOf = 步骤行态（status completed → done、failed → error、in_progress /
// searching → running（Responses 三态进行中，自检轮补——首版非 failed 一律 done，
// searching 帧会把已在场行提前翻完成）、缺席按 done——官方形态信任口径，与
// isCancelledResult 同族「键判据」风格）
export function serverStepNameOf(callJson: string): string {
  try {
    const rec = JSON.parse(callJson) as Record<string, Object>;
    const t: Object | undefined = rec['type'];
    return typeof t === 'string' ? t : '';
  } catch (e) {
    return '';
  }
}

export function serverStepStateOf(callJson: string): string {
  try {
    const rec = JSON.parse(callJson) as Record<string, Object>;
    const s: Object | undefined = rec['status'];
    if (typeof s === 'string') {
      if (s === 'failed') {
        return 'error';
      }
      if (s === 'in_progress' || s === 'searching') {
        return 'running';
      }
    }
    return 'done';
  } catch (e) {
    return 'error'; // 坏串 = 无法证实完成，防御归 error
  }
}

// 步内调用键（S2⑤ 行键料；★ 2026-11-14 自检轮补）：官方步 = {index, calls:[…]}，**一步可含
// 多个调用**（docs「calls 按发起顺序排列」；事件 call_started/call_completed 带 step + call，
// call 自带 index/id）。首版只按 step 作行键 ⇒ 同一步第二个 call_started 被当成 completed
// 更新既有行（名称停留首个调用、第二个调用无行）；本函数给出行键第二段 = call.id（官方唯一），
// 缺 id 退 index，双缺退 ''（调用方自增兜底）。判据 = 调用内唯一，禁跨步假设全局唯一。
export function serverCallKeyOf(callJson: string): string {
  try {
    const rec = JSON.parse(callJson) as Record<string, Object>;
    const id: Object | undefined = rec['id'];
    if (typeof id === 'string' && id !== '') {
      return id;
    }
    const idx: Object | undefined = rec['index'];
    if (typeof idx === 'number' && Number.isFinite(idx)) {
      return String(idx);
    }
    return '';
  } catch (e) {
    return '';
  }
}

// ── 服务端解析件发送阻断判据（S4③-B 支，纯函数——断言直跑面）──
// 带 remoteFileId 的附件件只有 DS 官方档连接能消费（composeOpenAiBody 产 {type:'file',
// file_id} 部件——§0 CC 引用扁平形态）。发送时镜像键 false = 连接已切走（换模型/换会话/
// kill switch 关），继续发送会把 file_id 落进不认该形态的端点——阻断提示移除重加（重新
// 入列按当下连接分叉路由）。dsOfficialAvailable 由调用方从镜像键（CHAT_DS_OFFICIAL_
// AVAILABLE_KEY，ChatPage.setConnInfo 写）现读传入，本函数保持纯函数直跑面；remoteFileId
// 缺席（本地解析件/图片/文本）恒放行。消费方唯一 = AttachmentUtil.attachBlockingReason
//（attach 域阻断单源），禁第二处散写同判据。
// ★ 自检轮补（S3 判据扩展的副作用）：endpoint='responses' 也是官方档，但 Responses 的 file
// item 形态官方未给，compose 侧只能防御性跳过（= 静默丢附件）。responsesEndpoint 为真时
// 先拦并给可执行提示（任务书 §1-7③「给明确提示」的落点）
export function dsServerDocBlockReason(att: PendingAttachment,
  dsOfficialAvailable: boolean, responsesEndpoint: boolean = false): string {
  if (att.remoteFileId === undefined || att.remoteFileId === '') {
    return '';
  }
  if (responsesEndpoint) {
    return `文档解析当前只支持 Chat Completions 形态，请移除该附件或切换接口形态：${att.name}`;
  }
  if (dsOfficialAvailable) {
    return '';
  }
  return `当前连接不支持服务端解析附件，请移除后重新添加：${att.name}`;
}
