// WebDAV 传输层（2026-09-03 Cube 吸收第三批③；蓝本 = cubeagent-stream-test〔chatcube
// MIT 快照〕services/WebDAVService.ets 裁剪——Basic 认证 + PUT/GET 传输 + MKCOL 建目录。
// ★ 2026-09-08 B1 滚动备份改造：固定名覆盖写 → 日期档轮转。整库 zip 备份/恢复语义
//（非增量——Cube sync_version 四列未驱动增量不移植，调研卷04 §二⑪）。
// 滚动备份语义（2026-09-07 任务书拍板）：
// · 命名约定 = aicontrol_backup_YYYYMMDD.zip，日期取本地设备时区（跨时区不处理——
//   个人设备场景）；同日重传 = PUT 覆盖当日档（当日档 = 当日最后一次成功上传），
//   「保留最近 5 份」= 最近 5 个上传日各一份，日粒度轮转。
// · 清理 = 上传成功后串行 DELETE today-6…today-60 共 55 候选 + 旧固定名 legacy 迁移
//   清理。DELETE 全程尽力而为——一切异常静默吞（404/5xx/网络错）：备份本体已成功，
//   清理失败只影响远端多占空间，不判整链失败；60 天窗口覆盖一个月以上未传场景，
//   窗口外残留档不参与恢复链、无安全风险。
// · 恢复链 = ①lastName（本机最近一次成功上传的远端名，页面层 preferences 读出传参
//   ——传输层不读 preferences）→ ②逐个探测 today-0…today-4（换设备/清数据/档被清）
//   → ③旧固定名 LEGACY_BACKUP_NAME 兜底（老版本存量备份）→ ④全 404 才报错。
//   链内同名不重复探测；链中 404 静默继续属规格语义。
// · 「不做目录列表」（http kit 枚举无 PROPFIND，2026-09-03 既有拍板）在新语义下闭环：
//   日粒度命名令最近 5 份可由文件名确定性枚举（候选日名直取），无需 PROPFIND；
//   PUT 中断原子化（临时名 + MOVE）不引入——最坏损失 = 当日档，前几日档仍在，
//   「误传毁掉唯一好备份」的威胁已消除。
// http 一建一销成对释放 + 每处 options 显式 usingCache: false（WebSearch 同款；同源说明
// 见坑33——http kit 默认 true，不显式关即静默走响应缓存）；凭据不进日志/错误信息（安全
// 红线——错误只透状态码与阶段，不回显 URL 账号）。★ 2026-09-24 请求日志扩面笔后口径精确化：
// 凭据仍不进**明文**，日志侧由 ReqLog 两层脱敏承接（按名掩码 + 值级替换；Authorization 的
// Basic base64 串属值级清单，见 davRequest 注释）。
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from './ReqLog';

const TIMEOUT_MS: number = 60000; // 备份 zip 可达数 MB——超时放宽（兜底上限，P1-3 口径）
const BACKUP_NAME_PREFIX: string = 'aicontrol_backup_'; // 日期档名前缀
// 旧版固定名（滚动备份改造前线上存量）——用途 = 恢复链③兜底 + 清理迁移，不再写入
export const LEGACY_BACKUP_NAME: string = 'aicontrol_backup.zip';

// 日期戳（8 位 yyyyMMdd，pad 手法同 ExportImport.exportStamp——本地时区）
function backupDateStamp(d: Date): string {
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate());
}

// 远端日期档名（今日 − offsetDays 天；offset 0 = 今天。Date.setDate 跨月/跨年自动进位）
function remoteBackupName(offsetDays: number): string {
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

// 远端路径（baseUrl/dirName/name，逐段 encode——空格等字符安全；逐段 encodeURIComponent
// 编码而非拒绝，非法字符按编码语义处理）
function remoteUrl(cfg: WebDavConfig, name: string): string {
  const segs: string[] = cfg.dirName.split('/').filter((s: string): boolean => s !== '');
  segs.push(name);
  return trimSlash(cfg.baseUrl) + '/' + segs.map((s: string): string => encodeURIComponent(s))
    .join('/');
}

// 单请求执行（非 2xx 抛 DavStatusError，调用方按需消化；body 支持 PUT 载荷）
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
  // 头先于句柄构造（成对释放：authHeader 抛错时尚未 createHttp，无句柄可泄——顺序不可换）
  const headers: Record<string, string> = {};
  headers['Authorization'] = authHeader(cfg.username, cfg.password);
  for (const key of Object.keys(extraHeaders)) {
    headers[key] = extraHeaders[key];
  }
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 请求日志（2026-09-24 扩面笔）：本层是备份链的唯一传输出口（PUT 上传 / GET 恢复 /
  // DELETE 清理 / OPTIONS 探测四方法共用）；methodName 形参 = 方法名字符串（枚举 → 名字的
  // 反查不做，防与调用点漂移）。凭据面：Authorization 是 Basic base64——按名判据命中即掩，
  // 值级脱敏清单再从该值拆段，两层与其余链同规格（安全红线见本件头注释）
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
      // ★ 2026-09-11 笔 4：显式关响应缓存（http kit 默认 true，坑33）——GET 恢复链可能
      // 命中「同日重传覆盖」前的旧档；本层四方法共用此 options，一处收口
      usingCache: false,
      expectDataType: method === http.RequestMethod.GET ?
        http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
    };
    if (body !== undefined) {
      options.extraData = body;
    }
    const resp: http.HttpResponse = await req.request(url, options);
    reqLogSetResponseHeaders(logId, resp.header);
    // 非 2xx 的错误体只在 STRING 型可取（GET 是 ARRAY_BUFFER——zip 二进制无文本语义，
    // 据型判空即可，不必另立「哪些方法能记正文」的清单）
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
      // 未走到响应（网络层/超时）：状态码记 -1；文案取错误码便于对码表（BusinessError 是
      // 接口非类，instanceof Error 不成立——同 ToolHttp 的实锤，故按 code 字段判）
      const biz = e as BusinessError;
      const netMsg: string = typeof biz.code === 'number' ?
        '无法连接服务器(code ' + biz.code + ')' : '网络错误';
      reqLogEnd(logId, -1, Date.now() - startedAt, netMsg, '');
    }
    // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
    throw e as Error;
  } finally {
    // destroy 包 try（同 ModelListApi / TitleApi / KeyConnectTester 先例）：裸 destroy 抛错
    // 会从 finally 穿出，把已成功的上传/下载改写成失败
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// 逐段建目录（MKCOL 深链——405 = 已存在跳过；其余非 2xx 呈报。http.RequestMethod 枚举
// 无 MKCOL〔d.ts 实查〕——method 字段以字符串字面量传入，运行时按原样透传到头行。
// ★ 2026-09-03 自检顺手清：原外层 catch 的 DavStatusError 分支不可达（内层按
// responseCode 判定后抛的是普通 Error），已简化）
export async function ensureDir(cfg: WebDavConfig): Promise<void> {
  const base: string = trimSlash(cfg.baseUrl);
  const segments: string[] = cfg.dirName.split('/').filter((s: string): boolean => s !== '');
  let current: string = base;
  for (const seg of segments) {
    current = current + '/' + encodeURIComponent(seg);
    // 头先于句柄构造（成对释放，同 davRequest）
    const headers: Record<string, string> = {};
    headers['Authorization'] = authHeader(cfg.username, cfg.password);
    const req: http.HttpRequest = http.createHttp();
    const startedAt: number = Date.now();
    // 请求日志（2026-09-24 扩面笔）：每段目录一条——排障要看的是「第几段挂了」（401/403 常
    // 在建目录这一步就暴露，是凭据错误的第一个现场）
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
        // ★ 2026-09-11 笔 4：同款显式声明（坑33；MKCOL 本无缓存语义，独立字面量仍按全仓
        // 惯例每处 options 都写——不留「这处为什么不写」的疑问）
        usingCache: false
      };
      const resp: http.HttpResponse = await req.request(current, options);
      reqLogSetResponseHeaders(logId, resp.header);
      const ok: boolean = resp.responseCode >= 200 && resp.responseCode < 300;
      const exists: boolean = resp.responseCode === 405; // 405 = 目录已存在，正常
      const failTail: string = typeof resp.result === 'string' ? resp.result : '';
      // ★ 405 如实记 405（列表按 HTTP 非 2xx 着色会标红，而它实为正常）：不另立「哪些链的
      // 哪些码算成功」的第二套判据——记的是实际发生的传输层事实，同 Anthropic 探针 404 形态
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt,
        ok || exists ? '' : 'HTTP ' + resp.responseCode, ok ? '' : failTail);
      logged = true;
      if (ok) {
        continue;
      }
      if (!exists) {
        // ★ 2026-09-03 401 翻译（上传前凭据错误即在此暴露——与 probe 同文案）
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

// 上传备份（PUT 当日日期档——同日重传覆盖当日档；成功返回实际上传的远端名，页面层
// 持久化为 lastName 供恢复链①环）。建目录先行。
// ★ 2026-09-03 401 翻译（PUT 阶段凭据错误——与 probe 同文案）
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

// 删除远端单档（清理轮专用，DELETE 与 MKCOL 同机制——method 字段字符串字面量透传）。
// ★ 尽力而为语义：一切异常静默吞（含 404/5xx/网络错）——调用时机在备份本体已成功之后，
// 清理失败只影响远端多占空间，不判整链失败；404 = 档不存在 = 目标状态已达。
async function deleteRemoteFile(cfg: WebDavConfig, name: string): Promise<void> {
  try {
    await davRequest('DELETE' as ESObject as http.RequestMethod, 'DELETE',
      remoteUrl(cfg, name), cfg, {});
  } catch (e) {
    // 尽力而为：吞（理由见函数头注释）
  }
}

// 清理旧档（上传成功后调用）：串行 DELETE today-6…today-60 共 55 候选日名 + 旧固定名
// legacy 迁移清理（防陈旧档永留误导）。恒正常返回——内部全吞（头注释「清理」节）。
export async function pruneOldBackups(cfg: WebDavConfig): Promise<void> {
  for (let i = 6; i <= 60; i++) {
    await deleteRemoteFile(cfg, remoteBackupName(i));
  }
  await deleteRemoteFile(cfg, LEGACY_BACKUP_NAME);
}

// 下载最近一份备份到本地（GET，恢复链见头注释）：候选序 = lastName（非空时）→
// today-0…today-4 → 旧固定名；命中即写入 localPath 并返回远端名。链内 404 静默继续
//（规格语义）；任一环 401 上抛（统一中文文案）；链尾全 404 抛统一提示。
// ★ 2026-09-03 401 翻译沿用（GET 阶段凭据错误）
export async function downloadLatestBackup(cfg: WebDavConfig, localPath: string,
  lastName: string): Promise<string> {
  const candidates: string[] = [];
  if (lastName !== '') {
    candidates.push(lastName);
  }
  for (let i = 0; i < 5; i++) {
    candidates.push(remoteBackupName(i));
  }
  candidates.push(LEGACY_BACKUP_NAME);
  const tried: string[] = []; // 链内同名不重复探测
  for (const name of candidates) {
    if (tried.indexOf(name) !== -1) {
      continue;
    }
    tried.push(name);
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
    // 消费 readSync 的实际读取长度（d.ts 明载返回值）：短读时零填充尾部不得混入上传的
    // 备份 zip——ExportImport.readFileText / ProviderShare.readShareFileText 同款先例
    //（第 2 轮 O5 本域半边，全面自检第 3 轮笔 2 收口；等长读零拷贝直返）
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
