// WebDAV 传输层（蓝本 = cubeagent-stream-test〔chatcube MIT 快照〕services/WebDAVService.ets
// 裁剪——Basic 认证 + PUT/GET 传输 + MKCOL 建目录；整库 zip 备份/恢复语义，非增量）。
// 滚动备份语义：
// · 命名 = aicontrol_backup_YYYYMMDD.zip，本地设备时区；同日重传 PUT 覆盖当日档（当日档 =
//   当日最后一次成功上传），「保留最近 5 份」= 最近 5 个上传日各一份，日粒度轮转。
// · 远端索引档：上传成功后 PUT aicontrol_backup_manifest.json（最近 8 次已知上传，超出裁
//   最旧）。它是**登记不是事实源**——写失败只留痕不阻断「上传完成」；多设备后写覆盖、不加
//   锁不协商；恢复发现 manifest 优先、读不到（404/坏档/空）按缺席回退日期猜名；不参与清理
//   窗口计算，清理跳过它引用的档（防「索引还指着、档已被清」失配）。
// · 清理 = 上传成功后串行 DELETE today-6…today-60 共 55 候选 + legacy 迁移清理，manifest
//   引用集内跳过。全程尽力而为——一切异常静默吞（404/5xx/网络错）：备份本体已成功，清理
//   失败只影响远端多占空间，不判整链失败。
// · 恢复链 = ①manifest 档（uploadedAt 倒序——可命中窗口外的被索引档）→ ②lastName（本机
//   最近一次成功上传的远端名，页面层 preferences 读出传参——传输层不读 preferences）→
//   ③逐个探测 today-0…today-4（换设备/清数据/档被清/无索引）→ ④旧固定名 LEGACY_BACKUP_NAME
//   兜底 → ⑤全 404 才报错。链内同名去重收在纯函数 composeRestoreCandidates；链中 404
//   静默继续属规格语义。
// · 不做目录列表（http kit 枚举无 PROPFIND）：发现能力唯一来源 = manifest 单档 + 日期猜名，
//   无任何前缀枚举/HEAD 扫描；PUT 中断原子化（临时名 + MOVE）不引入——最坏损失 = 当日档，
//   前几日档仍在。
// http 一建一销成对释放 + 每处 options 显式 usingCache: false（坑33——http kit 默认 true，
// 不显式关即静默走响应缓存）；凭据不进**明文**日志/错误信息（错误只透状态码与阶段，不回显
// URL 账号；日志侧由 ReqLog 两层脱敏承接——按名掩码 + 值级清单，见 davRequest 注释）。
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { applyDefaultUserAgent, applyEffectiveProxy } from './providers/RequestIdentity';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from './ReqLog';

const DOMAIN: number = 0x71C7;
const TAG: string = 'WebDavApi';

const TIMEOUT_MS: number = 60000; // 备份 zip 可达数 MB——超时放宽
// 日期档名前缀（export 供 S3Api 同名约定复用单源——两通道档名语义与清理策略一致）
export const BACKUP_NAME_PREFIX: string = 'aicontrol_backup_';
// 旧版固定名（滚动备份改造前线上存量）——用途 = 恢复链兜底 + 清理迁移，不再写入
export const LEGACY_BACKUP_NAME: string = 'aicontrol_backup.zip';

// ── 远端索引档（拍板「恢复发现走 manifest」；常量与结构名为契约名）──
// 索引档名（与日期档同目录；包内 ExportImport 的 manifest.json 是 zip 内格式清单——另一物，互不复用）
export const REMOTE_MANIFEST_NAME: string = 'aicontrol_backup_manifest.json';
const MANIFEST_VERSION: number = 1;
// 数据有界：记录最近 8 次已知上传，超出裁最旧（只进不出的索引 = 无界增长）
const MANIFEST_MAX_ENTRIES: number = 8;

// 单条上传登记（档名 + 上传时刻毫秒值；倒序排列后写回远端）
export interface RemoteBackupEntry {
  name: string;
  uploadedAt: number;
}

// 索引档 JSON 顶层（version 供将来升版识别——当前只写不读，读到非 1 也宽容当缺席）
interface RemoteManifestPayload {
  version: number;
  backups: RemoteBackupEntry[];
}

// 日期戳（8 位 yyyyMMdd，本地时区）
function backupDateStamp(d: Date): string {
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate());
}

// 远端日期档名（今日 − offsetDays 天，offset 0 = 今天；跨月/跨年自动进位；export 供 S3Api
// 复用，本地时区口径两通道一致）
export function remoteBackupName(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() - offsetDays);
  return BACKUP_NAME_PREFIX + backupDateStamp(d) + '.zip';
}

// WebDAV 连接配置（页面层持久化；password = 应用专用密码——不落日志）
export interface WebDavConfig {
  baseUrl: string; // 例 https://dav.jianguoyun.com/dav/
  username: string;
  password: string;
  dirName: string; // 远端子目录名（默认 aicontrol；可含多段 a/b）
}

// Basic 认证头（base64(user:pass)——RFC 7617）
function authHeader(user: string, password: string): string {
  const raw: Uint8Array = new util.TextEncoder().encodeInto(user + ':' + password);
  return 'Basic ' + new util.Base64Helper().encodeToStringSync(raw);
}

// URL 规整（去尾斜杠——拼接统一由本层补）
function trimSlash(url: string): string {
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

// 远端路径（baseUrl/dirName/name，逐段 encodeURIComponent——空格等字符安全，非法字符按编码语义处理）
function remoteUrl(cfg: WebDavConfig, name: string): string {
  const segs: string[] = cfg.dirName.split('/').filter((s: string): boolean => s !== '');
  segs.push(name);
  return trimSlash(cfg.baseUrl) + '/' + segs.map((s: string): string => encodeURIComponent(s))
    .join('/');
}

// WebDAV 状态错误（davRequest 收非 2xx 时抛出；调用方按需消化）
class DavStatusError extends Error {
  status: number;
  constructor(status: number) {
    super('HTTP ' + status);
    this.status = status;
  }
}

// 401 → 统一中文（凭据错误——与 probe 同文案；其余状态码回 null 由调用方按阶段消化）
function authError(e: Object): Error | null {
  if (e instanceof DavStatusError && (e as DavStatusError).status === 401) {
    return new Error('账号或密码（应用密码）不正确');
  }
  return null;
}

async function davRequest(method: http.RequestMethod, methodName: string, url: string,
  cfg: WebDavConfig, extraHeaders: Record<string, string>,
  body?: ArrayBuffer): Promise<http.HttpResponse> {
  // 头先于句柄构造（成对释放：authHeader 抛错时尚未 createHttp，无句柄可泄——顺序不可换）；
  // 全局 UA 兜底先于日志埋点（日志记实际发送的头）；extraHeaders 恒不带 UA，兜底恒生效
  const headers: Record<string, string> = {};
  headers['Authorization'] = authHeader(cfg.username, cfg.password);
  for (const key of Object.keys(extraHeaders)) {
    headers[key] = extraHeaders[key];
  }
  applyDefaultUserAgent(headers);
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 请求日志：本层是备份链唯一传输出口（PUT/GET/DELETE/OPTIONS 四方法共用）；methodName =
  // 方法名字符串（不做枚举反查，防与调用点漂移）。Authorization 的 Basic base64 由 ReqLog
  // 两层脱敏承接（安全红线见文件头）
  const logId: string = reqLogBegin({
    source: '网盘备份', model: '', method: methodName, url: url, headers: headers, body: ''
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      // 显式关响应缓存（坑33，http kit 默认 true）——GET 恢复链可能命中「同日重传覆盖」前的旧档
      usingCache: false,
      expectDataType: method === http.RequestMethod.GET ?
        http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
    };
    // 代理兜底：system 档零介入，direct/custom 写 usingProxy——一处接线四方法全生效；读超时
    // 保持本链 60s 不吃全局档
    applyEffectiveProxy(options);
    if (body !== undefined) {
      options.extraData = body;
    }
    const resp: http.HttpResponse = await req.request(url, options);
    reqLogSetResponseHeaders(logId, resp.header);
    // 非 2xx 的错误体只在 STRING 型可取（GET 是 ARRAY_BUFFER——zip 二进制无文本语义，据型判空即可）
    const failTail: string = typeof resp.result === 'string' ? resp.result : '';
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt,
      resp.responseCode < 200 || resp.responseCode >= 300 ? 'HTTP ' + resp.responseCode : '',
      resp.responseCode < 200 || resp.responseCode >= 300 ? failTail : '');
    logged = true;
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new DavStatusError(resp.responseCode);
    }
    return resp;
  } catch (e) {
    if (!logged) {
      // 未走到响应（网络层/超时）：状态码记 -1，文案取错误码便于对码表（BusinessError 是
      // 接口非类，按 code 字段判）
      const biz = e as BusinessError;
      const netMsg: string = typeof biz.code === 'number' ?
        '无法连接服务器(code ' + biz.code + ')' : '网络错误';
      reqLogEnd(logId, -1, Date.now() - startedAt, netMsg, '');
    }
    // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
    throw e as Error;
  } finally {
    // destroy 包 try：裸 destroy 抛错会从 finally 穿出，把已成功的上传/下载改写成失败
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// 逐段建目录（MKCOL 深链——405 = 已存在跳过，其余非 2xx 呈报。http.RequestMethod 枚举无
// MKCOL〔d.ts 实查〕——method 字段以字符串字面量传入、运行时原样透传到头行）
export async function ensureDir(cfg: WebDavConfig): Promise<void> {
  const base: string = trimSlash(cfg.baseUrl);
  const segments: string[] = cfg.dirName.split('/').filter((s: string): boolean => s !== '');
  let current: string = base;
  for (const seg of segments) {
    current = current + '/' + encodeURIComponent(seg);
    // 头先于句柄构造（成对释放，同 davRequest）；全局 UA 兜底同 davRequest（先于日志埋点）
    const headers: Record<string, string> = {};
    headers['Authorization'] = authHeader(cfg.username, cfg.password);
    applyDefaultUserAgent(headers);
    const req: http.HttpRequest = http.createHttp();
    const startedAt: number = Date.now();
    // 请求日志：每段目录一条——排障要看「第几段挂了」（401 常在建目录这一步暴露）
    const logId: string = reqLogBegin({
      source: '网盘备份', model: '', method: 'MKCOL', url: current, headers: headers, body: ''
    });
    let logged: boolean = false;
    try {
      const options: http.HttpRequestOptions = {
        method: 'MKCOL' as ESObject as http.RequestMethod,
        header: headers,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS,
        // 显式关缓存（坑33；MKCOL 本无缓存语义，仍按全仓惯例每处 options 都写）
        usingCache: false
      };
      // 代理兜底（同 davRequest 口径）
      applyEffectiveProxy(options);
      const resp: http.HttpResponse = await req.request(current, options);
      reqLogSetResponseHeaders(logId, resp.header);
      const ok: boolean = resp.responseCode >= 200 && resp.responseCode < 300;
      const exists: boolean = resp.responseCode === 405; // 405 = 目录已存在，正常
      const failTail: string = typeof resp.result === 'string' ? resp.result : '';
      // 405 如实记 405（列表按非 2xx 着色会标红，而它实为正常）——记实际发生的传输层事实
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt,
        ok || exists ? '' : 'HTTP ' + resp.responseCode, ok ? '' : failTail);
      logged = true;
      if (ok) {
        continue;
      }
      if (!exists) {
        // 401 翻译（上传前凭据错误在此暴露——与 probe 同文案）
        throw resp.responseCode === 401 ? new Error('账号或密码（应用密码）不正确') :
          new Error(`创建远端目录失败（HTTP ${resp.responseCode}）`);
      }
    } catch (e) {
      if (!logged) {
        const biz = e as BusinessError;
        const netMsg: string = typeof biz.code === 'number' ?
          '无法连接服务器(code ' + biz.code + ')' : '网络错误';
        reqLogEnd(logId, -1, Date.now() - startedAt, netMsg, '');
      }
      // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
      throw e as Error;
    } finally {
      try {
        req.destroy();
      } catch (e) {
      }
    }
  }
}

// 上传备份（PUT 当日日期档——同日重传覆盖；成功返回远端名，页面层持久化为 lastName 供恢复
// 链②环）。建目录先行；401 翻译与 probe 同文案
export async function uploadBackup(cfg: WebDavConfig, localPath: string): Promise<string> {
  await ensureDir(cfg);
  const data: ArrayBuffer = await readLocalFile(localPath);
  const name: string = remoteBackupName(0);
  try {
    await davRequest(http.RequestMethod.PUT, 'PUT', remoteUrl(cfg, name), cfg,
      { 'Content-Type': 'application/zip' }, data);
    return name;
  } catch (e) {
    const auth: Error | null = authError(e);
    if (auth !== null) {
      throw auth;
    }
    throw e as Error;
  }
}

// 删除远端单档（清理轮专用；DELETE 与 MKCOL 同机制——method 字符串字面量透传）。尽力而为：
// 一切异常静默吞（含 404/5xx/网络错）——调用时机在备份本体已成功后，清理失败只影响远端多占
// 空间；404 = 档不存在 = 目标状态已达
async function deleteRemoteFile(cfg: WebDavConfig, name: string): Promise<void> {
  try {
    await davRequest('DELETE' as ESObject as http.RequestMethod, 'DELETE',
      remoteUrl(cfg, name), cfg, {});
  } catch (e) {
    // 尽力而为：吞（理由见函数头）
  }
}

// 读远端索引档（恢复发现与上传登记共用）。宽容语义：404 / 非 2xx / 网络错 / 解析失败 /
// 结构不符（backups 非数组、条目缺字段或空名）/ 空 = 返回 []（按缺席处理，不是错误——恢复
// 发现还有日期猜名兜底；结构不符整体视作缺席，不半信半疑用坏档——回退日期猜名的可靠性高于
// 残缺索引）；唯 401 上抛（凭据错误要让恢复链立刻以中文文案失败，不落候选探测逐环 401）。
// GET 收 ARRAY_BUFFER → TextDecoder 解码
async function readRemoteManifest(cfg: WebDavConfig): Promise<RemoteBackupEntry[]> {
  try {
    const resp: http.HttpResponse = await davRequest(http.RequestMethod.GET, 'GET',
      remoteUrl(cfg, REMOTE_MANIFEST_NAME), cfg, {});
    const text: string = util.TextDecoder.create('utf-8')
      .decodeToString(new Uint8Array(resp.result as ArrayBuffer));
    const parsed: Object = JSON.parse(text) as Object;
    const backups: Object | undefined = (parsed as Record<string, Object>)['backups'];
    if (!Array.isArray(backups)) {
      return [];
    }
    const entries: RemoteBackupEntry[] = [];
    for (const item of backups as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        return [];
      }
      const rec: Record<string, Object> = item as Record<string, Object>;
      const name: Object | undefined = rec['name'];
      const uploadedAt: Object | undefined = rec['uploadedAt'];
      if (typeof name !== 'string' || name === '' || typeof uploadedAt !== 'number') {
        return [];
      }
      entries.push({ name: name, uploadedAt: uploadedAt });
    }
    return entries;
  } catch (e) {
    const auth: Error | null = authError(e);
    if (auth !== null) {
      throw auth;
    }
    return [];
  }
}

// 上传登记（上传成功后由页面层调用，I8：**登记不许反悔上传成功**）——读旧索引（best-effort）
// → 合并（本次置顶、同名取本次较晚时刻）→ 按 uploadedAt 倒序 → 裁到封顶 → PUT 回远端。
// 任何失败只 hilog.warn 并吞、不上抛；返回合并后的档名集供清理做保护集（写失败时只保护本次
// 档——已知限度：该轮清理可能删掉索引还引用的更老档，如实申报不补偿）。多设备竞争 =
// 读-合并-写、后写覆盖（不加锁、不做版本协商）
export async function recordRemoteBackup(cfg: WebDavConfig, name: string): Promise<string[]> {
  const merged: RemoteBackupEntry[] = [];
  try {
    const existing: RemoteBackupEntry[] = await readRemoteManifest(cfg);
    for (const entry of existing) {
      if (entry.name !== name) {
        merged.push(entry);
      }
    }
  } catch (e) {
    // 读失败（含 401——上传刚成功后的索引读不该把整链翻成失败）按缺席重建，只写本次档
    hilog.warn(DOMAIN, TAG, '远端索引档读取失败，按缺席重建：%{public}s', (e as Error).message);
  }
  merged.unshift({ name: name, uploadedAt: Date.now() });
  merged.sort((a: RemoteBackupEntry, b: RemoteBackupEntry): number =>
    b.uploadedAt - a.uploadedAt);
  const kept: RemoteBackupEntry[] = merged.slice(0, MANIFEST_MAX_ENTRIES);
  try {
    const payload: RemoteManifestPayload = { version: MANIFEST_VERSION, backups: kept };
    const encoded: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(payload));
    const body: ArrayBuffer = encoded.buffer.slice(encoded.byteOffset,
      encoded.byteOffset + encoded.byteLength) as ArrayBuffer;
    await davRequest(http.RequestMethod.PUT, 'PUT', remoteUrl(cfg, REMOTE_MANIFEST_NAME), cfg,
      { 'Content-Type': 'application/json' }, body);
    const names: string[] = [];
    for (const entry of kept) {
      names.push(entry.name);
    }
    return names;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '远端索引档写入失败（备份本体已上传成功）：%{public}s',
      (e as Error).message);
    return [name];
  }
}

// 恢复候选序（**纯函数**，node 断言直跑）：manifest 档名（已倒序）→ lastName（非空时）→
// todayNames → legacy 兜底；逐段去重、保留首个出现位置
export function composeRestoreCandidates(manifestNames: string[], lastName: string,
  todayNames: string[]): string[] {
  const candidates: string[] = [];
  for (const name of manifestNames) {
    candidates.push(name);
  }
  if (lastName !== '') {
    candidates.push(lastName);
  }
  for (const name of todayNames) {
    candidates.push(name);
  }
  candidates.push(LEGACY_BACKUP_NAME);
  const seen: string[] = [];
  const result: string[] = [];
  for (const name of candidates) {
    if (seen.indexOf(name) !== -1) {
      continue;
    }
    seen.push(name);
    result.push(name);
  }
  return result;
}

// 清理删除集（**纯函数**，node 断言直跑）：窗口 today-6…today-60 升序 + legacy（末尾，
// 保序）减去保护集（manifest 引用档不删——索引还指着的档被清 = 恢复发现失配）。
export function pruneDeleteNames(protectedNames: string[]): string[] {
  const names: string[] = [];
  for (let i = 6; i <= 60; i++) {
    names.push(remoteBackupName(i));
  }
  names.push(LEGACY_BACKUP_NAME);
  const result: string[] = [];
  for (const name of names) {
    if (protectedNames.indexOf(name) !== -1) {
      continue;
    }
    result.push(name);
  }
  return result;
}

// 清理旧档（上传成功后调用）：删除集 = pruneDeleteNames（窗口 + legacy，跳过保护集）。恒正常
// 返回——内部全吞（见文件头「清理」节）；窗口 6..60 与 legacy 两数不动，也不为 manifest
// 新增清理路径
export async function pruneOldBackups(cfg: WebDavConfig,
  protectedNames: string[]): Promise<void> {
  const names: string[] = pruneDeleteNames(protectedNames);
  for (const name of names) {
    await deleteRemoteFile(cfg, name);
  }
}

// 下载最近一份备份到本地（GET，恢复链见文件头）：候选序去重后逐个探测，命中即写 localPath
// 并返回远端名。链中 404 静默继续（规格语义）；任一环 401 上抛（统一中文文案，含 manifest
// 读环）；链尾全 404 抛统一提示
export async function downloadLatestBackup(cfg: WebDavConfig, localPath: string,
  lastName: string): Promise<string> {
  const manifestEntries: RemoteBackupEntry[] = await readRemoteManifest(cfg);
  const manifestNames: string[] = [];
  for (const entry of manifestEntries) {
    manifestNames.push(entry.name);
  }
  const todayNames: string[] = [];
  for (let i = 0; i < 5; i++) {
    todayNames.push(remoteBackupName(i));
  }
  const candidates: string[] = composeRestoreCandidates(manifestNames, lastName, todayNames);
  for (const name of candidates) {
    const hit: string | null = await tryGetBackup(cfg, localPath, name);
    if (hit !== null) {
      return hit;
    }
  }
  throw new Error('远端还没有备份文件，请先在任意设备上传一次');
}

// 恢复链单环探测：GET 命中写 localPath 返回档名；404 返 null（继续下一环）；
// 401 翻译上抛；其余异常原样上抛（网络错/5xx 不吞——与原 downloadFile 同口径）
async function tryGetBackup(cfg: WebDavConfig, localPath: string,
  name: string): Promise<string | null> {
  try {
    const resp: http.HttpResponse = await davRequest(http.RequestMethod.GET, 'GET',
      remoteUrl(cfg, name), cfg, {});
    writeLocalFile(localPath, resp.result as ArrayBuffer);
    return name;
  } catch (e) {
    const auth: Error | null = authError(e);
    if (auth !== null) {
      throw auth;
    }
    if (e instanceof DavStatusError && (e as DavStatusError).status === 404) {
      return null;
    }
    throw e as Error;
  }
}

// 远端可达性探测（OPTIONS 带 Basic 头——401 = 账号或密码错误；2xx/405 = 可达）
export async function probe(cfg: WebDavConfig): Promise<void> {
  try {
    await davRequest(http.RequestMethod.OPTIONS, 'OPTIONS', trimSlash(cfg.baseUrl), cfg, {});
  } catch (e) {
    if (e instanceof DavStatusError) {
      const status: number = (e as DavStatusError).status;
      if (status === 401) {
        throw new Error('账号或密码（应用密码）不正确');
      }
      if (status === 405) {
        return; // 方法不被允许但服务可达 = 探测通过
      }
      throw new Error(`服务器不可达（HTTP ${status}）`);
    }
    throw e as Error;
  }
}

// ── 本地文件读写（fs 直读直写，成对关 fd）──

async function readLocalFile(path: string): Promise<ArrayBuffer> {
  const stat: fs.Stat = fs.statSync(path);
  const ab: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    // 消费 readSync 实际读取长度：短读时零填充尾部不得混入上传的备份 zip（等长读零拷贝直返）
    const len: number = fs.readSync(file.fd, ab);
    return len === ab.byteLength ? ab : ab.slice(0, len);
  } finally {
    fs.closeSync(file);
  }
}

function writeLocalFile(path: string, data: ArrayBuffer): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE |
    fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, data);
  } finally {
    fs.closeSync(file);
  }
}
