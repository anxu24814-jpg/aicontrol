// DeepSeek Files 通道域（DS 全家桶接入批 S4；任务书 = docs/任务书-DS全家桶接入-20261114.md
// 〔自检修订版〕§0「Files」条 / §6-S4①）。职责单句：附件的 DeepSeek 服务端上传客户端——
// multipart 上传取 file_id、上传目标解析（会话级连接同链收敛 + 启用序首支 key）与三枚纯
// 函数面（purpose 分档 / 上限预检 / multipart 组装，供断言直跑）。
// · 官方协议事实（任务书 §0 单源，禁消费方散写）：POST {baseUrl}/files（Bearer 对话密钥）；
//   purpose 字段必须在 file 之前（-F 顺序即 multipart 顺序）；purpose 分档 = .pdf/.docx/
//   .pptx 一律 rich_layout_recognition（代决 6，text_recognition 档不做入口）；expires_after
//   3600s（代决 5——附件仅随当前轮，不占账号配额不留存）；PDF/Word/PPT 上限 100MiB 且须
//   120s 内传完（读超时取 130s = 官方上限 × 1.08 余量）；文件名 ≤512 字节；解析同步返回
//   即可用（无轮询）；CC 引用 = {"type":"file","file_id":"file-api-…"}（compose 层消费）。
// · multiFormDataList 签名查证（2026-11-14 双证）：官方 API 参考 js-apis-http + 本地 SDK
//   d.ts（sdk/default/openharmony/ets/api/@ohos.net.http.d.ts:1119 MultiFormData，@since 11）
//   ——字段 = { name, contentType, data?, filePath?, remoteFileName? }；data 未设时 filePath
//   必设，filePath 形态由引擎直读文件、不整读进内存（100MiB 上限下唯一合法形态）；设
//   remoteFileName 即向请求写 filename 头（服务端收到的文件名），缺省取 filePath 物理名
//   （本工程物理名 = fileId 铸名非用户名，**必须显式设为附件显示名**）；multiFormDataList
//   仅在 Content-Type: multipart/form-data 时生效，boundary 系统生成禁自拼（HttpBinary
//   buildMultiFormData 同款纪律）。仓库内在仓先例 = HttpBinary.buildMultiFormData（已编译
//   验证同签名）；http 请求壳形制（代理/UA/日志/成对销毁）照 ApiSearchEngines.httpPostJson。
// · expires_after 表单字段名按 §0 记法落 `expires_after[anchor]` 与 `expires_after[seconds]`
//   两个文本字段（S0⑥ 未含该参——真机实测前为唯一不确定面；字段名错 = 服务端忽略未知
//   字段退「永久有效」档，非失败形态；改法单点在本函数 buildDsFilesUploadForm）。
// · 上传目标解析（2026-11-14 自检报告 §4.1 修：refs 增 conn() 活连接通道）：调用方从
//   activeConversationId 广播传 convId（写点 = ChatPage enterConversation 既有调用），并把
//   ChatPage.conn（本会话内存覆盖的同链真值）作为 liveConn 传入——新建会话尚无 conversations
//   行时 DB 查不到覆盖，只读 DB 会落到默认助手连接；**活连接优先**（dsUploadConnOf，非官方
//   仍回落 DB 链）后，无行会话也能落到当前官方连接。DB 链仍照旧（queryConversationOverride
//   + queryConversationAssistantId + resolveActiveConnection 四级兜底）——链确定性收敛到页面
//   同一连接；key 取启用序首支（loadPoolKey，MemoryImport/TitleGen 小任务同口径，不轮询池）。
//   解析落空（活连接与 DB 链都判不出官方连接、key 明文缺失）恒 null = 调用方 fail-closed
//   置 failed 态，绝不误传到非官方端点。
//   已知边界（登记制）：多 key 池轮转面，上传支固定首支而发送支按 keyPickMode 轮转——
//   跨账号混池时 file_id 与发送 key 异账号，发送侧可见报错（非静默污染），单 key 池（常态）
//   无此面。
// · 失败语义：失败句叶子复用 httpKitErrorText + httpStatusFailureText（ApiSearchEngines
//   同源，禁自建码表）；错误一律中文上抛/回填，非零退（P0-1 禁静默失败）。
import { http } from '@kit.NetworkKit';
import { applyDefaultUserAgent, applyEffectiveProxy } from './RequestIdentity';
import { httpKitErrorText, httpStatusFailureText } from './WebSearchParse';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';
import { dsUploadConnOf } from './DsServerTools';
import { AiConnection } from './AiTypes';
import { resolveActiveConnection, ActiveConnectionInfo } from '../store/ProviderDb';
import { resolveTitleEndpoint, TitleEndpoint } from '../TitleGen';
import { loadPoolKey } from '../store/KeyStore';
import { queryConversationOverride, ConversationOverride } from '../store/ChatDb';
import { queryConversationAssistantId, ASSISTANT_DEFAULT_ID } from '../store/AssistantDb';

// ── 闸常量（任务书 §0 官方限制单源；纯函数与断言同引，禁消费方散写数字）──
// PDF/Word/PPT 单件上限（100MiB；超限在入列闸拒收——AttachmentPickCtrl cap 分流）
export const DS_FILES_UPLOAD_MAX_BYTES: number = 100 * 1024 * 1024;
// 文件名字节上限（UTF-8；官方「文件名 ≤512 字节」）
export const DS_FILES_NAME_MAX_BYTES: number = 512;
// expires_after 秒数（代决 5：附件仅随当前轮，1 小时足够且不占账号配额）
export const DS_FILES_EXPIRES_AFTER_SECONDS: number = 3600;
// 读超时（官方「120s 内传完」上限 × 1.08 余量取整 = 130s；低于官方上限内传不完 = 服务端
// 侧失败形态，本端不无限等）
export const DS_FILES_READ_TIMEOUT_MS: number = 130000;

// purpose 两档字面量（§0 三值中本应用只落两档；text_recognition 档不做入口——代决 6）
export const DS_FILES_PURPOSE_RICH: string = 'rich_layout_recognition';
export const DS_FILES_PURPOSE_USER_DATA: string = 'user_data';

// ── 纯函数面（断言直跑——零平台依赖，http 只出现在类型位随剥除消失）──

// UTF-8 字节长（文件名字节闸的分母——官方限「512 字节」非字符数，CJK 每字 3 字节须按字节
// 计；代理对 4 字节、增补平面逐对计）
function utf8ByteLength(value: string): number {
  let bytes: number = 0;
  for (let i = 0; i < value.length; i++) {
    const code: number = value.charCodeAt(i);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF) {
      bytes += 4;
      i++; // 低位代理随首码元同轮消费
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

// purpose 分档（代决 6 单源）：.pdf/.docx/.pptx 一律 rich_layout_recognition（图文混排都给
// 模型）；其余（图片/纯文本/表格等，仅当将来扩接入面时可达）按 user_data。扩展名大小写
// 不敏感；无扩展名/未知扩展名兜 user_data（该函数非路由闸——路由闸见 AttachmentPickCtrl
// 的 dsServerCandidate 组合判据，只放行 RICH 档）
export function dsFilesPurposeFor(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  const ext: string = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  if (ext === 'pdf' || ext === 'docx' || ext === 'pptx') {
    return DS_FILES_PURPOSE_RICH;
  }
  return DS_FILES_PURPOSE_USER_DATA;
}

// 上传前预检（纯函数，中文报错非空即拒收）：单件 100MiB + 文件名 ≤512 字节（UTF-8）两闸。
// 100MiB 闸在入列 cap 分流已同值把守（AttachmentPickCtrl），此处复检 = 单源同值双写防线
//（两处同引本函数与常量，不各自写数字）；报错句式与入列域既有中文报错同族
export function dsFilesRejectReason(fileName: string, size: number): string {
  if (size > DS_FILES_UPLOAD_MAX_BYTES) {
    return fileName + ' 超过 100MB 上限';
  }
  if (utf8ByteLength(fileName) > DS_FILES_NAME_MAX_BYTES) {
    return '文件名超过 512 字节上限，请重命名后重试';
  }
  return '';
}

// multipart 表单组装（纯函数，断言直跑；断言钉三件事：purpose 项在前〔官方 -F 顺序即
// multipart 顺序，错位 = 400〕、expires_after 两文本字段〔§0 记法〕、file 项 filePath 形态
// 〔引擎直读文件禁整读内存〕+ remoteFileName = 显示名）。mime 由调用方传（docMime 单源在
// AttachmentUtil——本件不反向 import，纯函数面保持零产品依赖）。
// ★ expires_after 3600s 由调用方传 DS_FILES_EXPIRES_AFTER_SECONDS（代决 5 单值），不在此
// 写死——断言以常量现读判（改值不红）
export interface DsFilesFormBuild {
  ok: boolean;
  errorText: string;
  data: http.MultiFormData[];
}

export function buildDsFilesUploadForm(fileName: string, mime: string, filePath: string,
  expiresAfterSeconds: number): DsFilesFormBuild {
  if (filePath === '') {
    return { ok: false, errorText: '上传文件路径缺失', data: [] };
  }
  const data: http.MultiFormData[] = [
    // ① purpose（必须在 file 之前——官方「-F 顺序即 multipart 顺序」）
    { name: 'purpose', contentType: 'text/plain', data: dsFilesPurposeFor(fileName) },
    // ② expires_after（§0 记法两字段；S0⑥ 真机待验——见文件头「唯一不确定面」）
    { name: 'expires_after[anchor]', contentType: 'text/plain', data: 'created_at' },
    { name: 'expires_after[seconds]', contentType: 'text/plain',
      data: String(expiresAfterSeconds) },
    // ③ file（filePath 形态 = 引擎直读文件；remoteFileName = 显示名——物理名是 fileId
    // 铸名，缺省会把内部名暴露为服务端文件名）
    { name: 'file', contentType: mime !== '' ? mime : 'application/octet-stream',
      filePath: filePath, remoteFileName: fileName }
  ];
  return { ok: true, errorText: '', data: data };
}

// 上传端点合成（纯函数）：连接 baseUrl 归一（trim + 去尾斜杠 + 剥 /v1 尾段）+ '/files'——
// 官方模板 E 端点为 https://api.deepseek.com/files（域名根、无 /v1），而对话连接 baseUrl
// 两态（带 /v1 与不带）都可达，剥 /v1 统一到域名根形制
export function dsFilesUploadUrl(baseUrl: string): string {
  const trimmed: string = baseUrl.trim().replace(/\/+$/, '');
  const stripped: string = trimmed.endsWith('/v1') ?
    trimmed.substring(0, trimmed.length - 3) : trimmed;
  return stripped + '/files';
}

// ── 上传目标解析（IO 域——不进断言直跑面；失败恒 null 由调用方 fail-closed 处置）──

// 上传目标（对话密钥 = 当前 DS 连接的池钥明文；明文仅在本域内存流转，禁进日志/toast——
// 安全红线同 KeyStore 口径）
export interface DsFilesUploadTarget {
  baseUrl: string;
  apiKey: string;
}

// 会话级上传目标解析：liveConn（页面 conn 活连接，本会话内存覆盖真值）优先 → DB 链
// （convId → 会话覆盖 + 助手归属 → resolveActiveConnection 四级链）回落 → dsUploadConnOf
// 两源同判 isDsFlashConnection（fail-closed：判不出官方连接就不上传）→ 启用序首支 pool key
// 明文。任一环落空 = null。★ 2026-11-14 自检报告 §4.1 修：首版只读 DB，新建会话（无
// conversations 行）的内存模型覆盖查不到 ⇒ 落到默认助手连接，多服务商下选 PDF 必失败；
// 活连接通道补上后无行会话同样命中当前官方连接（convId 为空也可用活连接）。
export async function resolveDsUploadTarget(convId: string,
  liveConn: AiConnection | null = null): Promise<DsFilesUploadTarget | null> {
  let dbConn: AiConnection | null = null;
  if (convId !== '') {
    // 会话覆盖（行不存在 = 无行会话窗口，'' 走兜底链——reloadConn 降级同口径）
    let overrideProviderId: string = '';
    let overrideModelId: string = '';
    try {
      const override: ConversationOverride | null = await queryConversationOverride(convId);
      if (override !== null) {
        overrideProviderId = override.modelProviderId;
        overrideModelId = override.modelId;
      }
    } catch (e) {
      // 覆盖读失败降兜底链（不停链——resolveActiveConnection 容忍空覆盖）
    }
    // 会话归属助手（行缺失/查询失败 = 默认助手——resolveSessionActive 同口径）
    let ownerId: string = ASSISTANT_DEFAULT_ID;
    try {
      const rowId: string | null = await queryConversationAssistantId(convId);
      if (rowId !== null && rowId !== '') {
        ownerId = rowId;
      }
    } catch (e) {
      // 归属读失败降默认助手
    }
    try {
      const info: ActiveConnectionInfo | null =
        await resolveActiveConnection(ownerId, overrideProviderId, overrideModelId);
      dbConn = info !== null ? info.conn : null;
    } catch (e) {
      dbConn = null;
    }
  }
  const conn: AiConnection | null = dsUploadConnOf(liveConn, dbConn);
  if (conn === null) {
    return null; // fail-closed：两源都判不出官方连接不上传（防误传非官方端点）
  }
  // 启用序首支 key（resolveTitleEndpoint = 服务商启用 × 模型启用 × 池非空的同级验证复用，
  // MemoryImport 先例；小任务不轮询池）
  let resolved: TitleEndpoint | null = null;
  try {
    resolved = await resolveTitleEndpoint(conn.providerId, conn.model);
  } catch (e) {
    resolved = null;
  }
  if (resolved === null || resolved.keyIds.length === 0) {
    return null;
  }
  let apiKey: string = '';
  try {
    apiKey = await loadPoolKey(resolved.providerId, resolved.keyIds[0]);
  } catch (e) {
    apiKey = '';
  }
  if (apiKey === '') {
    return null; // 明文缺失（资产缺失态——发送链同款「跳过该支」语义在此收口为失败）
  }
  return { baseUrl: conn.baseUrl, apiKey: apiKey };
}

// ── 上传壳（照 ApiSearchEngines.httpPostJson 形制：一建一销 + finally 成对 destroy +
// 代理/UA 全局约定 + 请求日志单点；multipart 走 multiFormDataList filePath 形态）──

// 上传回执：ok = 服务端解析同步完成（返回即可用——无轮询）；fileId = 官方 file-api-… 形
// id（PendingAttachment.remoteFileId 消费面）；失败 errorText 中文（parseError 呈报面）
export interface DsFilesUploadOutcome {
  ok: boolean;
  errorText: string;
  fileId: string;
}

// 单件上传：target（resolveDsUploadTarget 产物）+ 沙箱副本绝对路径 + 显示名 + mime
//（docMime 派生值）+ size（入列入闸过的现值）。内部预检双闸（dsFilesRejectReason，与入列
// cap 同源同值）先行——越限中文报错拒收，不发请求
export async function uploadDsFile(target: DsFilesUploadTarget, filePath: string,
  displayName: string, mime: string, size: number): Promise<DsFilesUploadOutcome> {
  const rejected: string = dsFilesRejectReason(displayName, size);
  if (rejected !== '') {
    return { ok: false, errorText: rejected, fileId: '' };
  }
  const form: DsFilesFormBuild = buildDsFilesUploadForm(displayName, mime, filePath,
    DS_FILES_EXPIRES_AFTER_SECONDS);
  if (!form.ok) {
    return { ok: false, errorText: form.errorText, fileId: '' };
  }
  const url: string = dsFilesUploadUrl(target.baseUrl);
  const headers: Record<string, string> = {
    // Content-Type 必须显式 multipart/form-data（multiFormDataList 仅该形态生效；
    // boundary 系统生成禁自拼——HttpBinary 同款纪律）
    'Content-Type': 'multipart/form-data',
    'Authorization': `Bearer ${target.apiKey}`
  };
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 全局 UA 兜底（先于日志埋点——日志记到实际发送的头；代理兜底写 options，同 httpPostJson）
  applyDefaultUserAgent(headers);
  const logId: string = reqLogBegin({
    source: 'DS 文档上传', model: '', method: 'POST', url: url, headers: headers,
    body: '[multipart ' + displayName + ']'
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      multiFormDataList: form.data,
      connectTimeout: DS_FILES_READ_TIMEOUT_MS,
      readTimeout: DS_FILES_READ_TIMEOUT_MS,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    };
    applyEffectiveProxy(options);
    const resp: http.HttpResponse = await req.request(url, options);
    reqLogSetResponseHeaders(logId, resp.header);
    const body: string = typeof resp.result === 'string' ? resp.result : String(resp.result);
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      const failText: string = httpStatusFailureText(resp.responseCode, body);
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, failText, body);
      logged = true;
      return { ok: false, errorText: '上传失败：' + failText, fileId: '' };
    }
    // 同步解析：2xx 响应体即文件对象（OpenAI files 形态 {id: "file-api-…", ...}）——id
    // 缺失/坏 JSON = 防御报错（P0-1 不静默）
    let fileId: string = '';
    try {
      const rec = JSON.parse(body) as Record<string, Object>;
      const id: Object | undefined = rec['id'];
      if (typeof id === 'string' && id !== '') {
        fileId = id;
      }
    } catch (e) {
      fileId = '';
    }
    if (fileId === '') {
      const failText: string = '上传响应未含文件标识';
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, failText, body);
      logged = true;
      return { ok: false, errorText: failText, fileId: '' };
    }
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '', '');
    logged = true;
    return { ok: true, errorText: '', fileId: fileId };
  } catch (e) {
    const failText: string = '上传失败：' + httpKitErrorText(e, DS_FILES_READ_TIMEOUT_MS / 1000);
    if (!logged) {
      reqLogEnd(logId, -1, Date.now() - startedAt, failText, '');
    }
    return { ok: false, errorText: failText, fileId: '' };
  } finally {
    // destroy 包 try（裸 destroy 抛错会从 finally 穿出——httpPostJson 同款）
    try {
      req.destroy();
    } catch (e) {
    }
  }
}
