// S3 兼容对象存储传输层（与 WebDavApi 平行的第二传输通道）。
// 产品语义参照 RikkaHub data/sync/s3（测试连接 = ListObjectsV2 探活、path-style 默认开、
// region 默认 auto），签名算法按 AWS 官方 Signature Version 4 规范自行实现，零第三方 SDK；
// 测试向量 = AWS 官方 aws-sig-v4-test-suite（assert-net-parse S3 组直跑）。
// ★ 零 manifest 设计（与 WebDAV 的关键差异）：S3 有真列举能力（ListObjectsV2），恢复发现 =
// 列举 prefix 单源，不需要 WebDAV「manifest 索引档 + 日期猜名」的发现链——通道能力不同，
// 不强求两通道同构；档名约定与滚动清理「保留最近 5 份」语义与 WebDAV 一致（档名常量与
// remoteBackupName 直接 import 自 WebDavApi 单源，禁在本件复制第二份）。
// 签名纪律：只签 host / x-amz-date / x-amz-content-sha256〔+ content-type（PUT 时）〕四头，
// 其余头不签名不违法——SigV4 只要求 x-amz-* 必签；Host 头由 HTTP 栈按 URL 自填，签名侧只
// 计算不注入。时间戳 = UTC 基本格式（SigV4 规范）；备份档名日期仍取本地时区（WebDAV 同
// 口径，跨时区不处理）。http 一建一销成对释放 + 每处 options 显式 usingCache: false
//（坑33 同源纪律）；凭据不进日志/错误信息（ReqLog 两层脱敏承接）；secretAccessKey 只在
// 签名链内存中出现，恒不落任何盘面/日志（KeyStore aic.s3.secret 单源）。
// 列举翻页（max-keys 1000/页 × continuation-token 续拉，上限 200 页）：prefix 可指向共享
// 目录——单页时字典序更小的前 1000 个对象会把自家备份档挤出列举面（恢复误报空、清理永不
// 触发），故补翻页；页上限防异常实现 IsTruncated 恒真造成无界循环，到顶抛错不静默（P0-1）。
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { applyDefaultUserAgent, applyEffectiveProxy } from './providers/RequestIdentity';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from './ReqLog';
import { BACKUP_NAME_PREFIX, remoteBackupName } from './WebDavApi';

const DOMAIN: number = 0x71C8;
const TAG: string = 'S3Api';

const TIMEOUT_MS: number = 60000; // 备份 zip 可达数 MB——同 WebDavApi 口径（兜底上限，P1-3）
const S3_SERVICE: string = 's3'; // SigV4 credential scope 服务名（S3 兼容存储恒 s3）
const S3_ALGORITHM: string = 'AWS4-HMAC-SHA256';
const DEFAULT_REGION: string = 'auto'; // region 留空时的 scope 值——R2/MinIO 官方推荐填法
const BACKUP_KEEP_COUNT: number = 5; // 滚动清理保留份数（与 WebDAV「最近 5 个上传日」同数）
const MAX_LIST_PAGES: number = 200; // 列举翻页上限（1000 × 200 = 20 万对象——防异常实现无界循环）

// S3 连接配置（页面层持久化；secretAccessKey 不落任何盘面——页面自 Asset 读出直传本层）
export interface S3Config {
  endpoint: string; // 例 https://s3.example.com——只到主机或主机加端口，不带路径与桶名
  bucket: string;
  region: string; // credential scope 区域名；R2/MinIO 用 auto
  accessKeyId: string;
  secretAccessKey: string;
  prefix: string; // 远端目录前缀（默认 aicontrol；可含多段 a/b）
  pathStyle: boolean; // true = https://host/bucket/key；false = https://bucket.host/key
}

// ── 纯函数层（node 断言直跑——assert-net-parse S3 组复制直跑；签名算法的可测核心全在此）──

// UTC 基本格式时间戳（20250830T123600Z——SigV4 规范 x-amz-date 形制）
export function amzDateTime(d: Date): string {
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) +
    'T' + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + 'Z';
}

// credential scope（dateStamp/region/s3/aws4_request）
export function scopeOf(dateStamp: string, region: string): string {
  return dateStamp + '/' + region + '/' + S3_SERVICE + '/aws4_request';
}

// RFC3986 段编码（encodeURIComponent 已保 A-Za-z0-9-._~ 不动，补齐其放行的 5 个保留字；
// 保留 '/' 由调用方分段后逐段编码——canonical URI 与 query 两消费面各自分段）
export function uriEncode(seg: string): string {
  return encodeURIComponent(seg)
    .replace(/!/g, '%21')
    .replace(/'/g, '%27')
    .replace(/\(/g, '%28')
    .replace(/\)/g, '%29')
    .replace(/\*/g, '%2A');
}

// endpoint 取 host 段（含端口；容错剥 scheme 与路径——UI 校验在前，此处防御兜底）
export function endpointHost(endpoint: string): string {
  let e: string = endpoint.trim();
  const scheme: number = e.indexOf('://');
  if (scheme >= 0) {
    e = e.substring(scheme + 3);
  }
  const slash: number = e.indexOf('/');
  if (slash >= 0) {
    e = e.substring(0, slash);
  }
  return e;
}

// Host 签名值（path-style = host；virtual = bucket.host——桶名作子域）
export function hostHeaderOf(cfg: S3Config): string {
  const host: string = endpointHost(cfg.endpoint);
  if (cfg.pathStyle) {
    return host;
  }
  return cfg.bucket + '.' + host;
}

// 对象键（prefix/name——prefix 逐段 trim 去空段〔判据与入列同一 trimmed 值〕；name 为 ''
// 时返回纯 prefix，作列举前缀用）
export function objectKeyOf(cfg: S3Config, name: string): string {
  const segs: string[] = [];
  for (const s of cfg.prefix.split('/')) {
    const seg: string = s.trim();
    if (seg !== '') {
      segs.push(seg);
    }
  }
  if (name !== '') {
    segs.push(name);
  }
  return segs.join('/');
}

// 请求 URL（path-style = endpoint/bucket/key；virtual = scheme://bucket.host/key；
// key 为 '' 时省尾段——列举场景）
export function requestUrlOf(cfg: S3Config, key: string): string {
  const e: string = cfg.endpoint.trim().replace(/\/+$/, '');
  const parts: string[] = key.split('/').filter((s: string): boolean => s !== '')
    .map((s: string): string => uriEncode(s));
  const tail: string = parts.join('/');
  if (cfg.pathStyle) {
    return e + '/' + uriEncode(cfg.bucket) + (tail !== '' ? '/' + tail : '');
  }
  const scheme: number = e.indexOf('://');
  const schemeText: string = scheme >= 0 ? e.substring(0, scheme) : 'https';
  const host: string = scheme >= 0 ? e.substring(scheme + 3) : e;
  return schemeText + '://' + uriEncode(cfg.bucket) + '.' + host + (tail !== '' ? '/' + tail : '');
}

// canonical URI（逐段编码保留 '/'；path-style 首段为桶名，key 为 '' 时列举形制无尾斜杠）
export function canonicalUriOf(cfg: S3Config, key: string): string {
  const segs: string[] = [];
  if (cfg.pathStyle) {
    segs.push(cfg.bucket);
  }
  for (const s of key.split('/')) {
    if (s !== '') {
      segs.push(s);
    }
  }
  return '/' + segs.map((s: string): string => uriEncode(s)).join('/');
}

// 头对排序归一（键小写、值 trim、按键排序——canonical headers 与 signedHeaders 共用）
function sortedHeaderPairs(headerPairs: string[][]): string[][] {
  return headerPairs.map((p: string[]): string[] => [p[0].toLowerCase(), p[1].trim()])
    .sort((a: string[], b: string[]): number => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
}

// signedHeaders 值（排序键名分号连接——Authorization 头的 SignedHeaders 段）
export function signedHeadersOf(headerPairs: string[][]): string {
  return sortedHeaderPairs(headerPairs).map((p: string[]): string => p[0]).join(';');
}

// 规范请求串（SigV4 六段：method \n canonicalURI \n canonicalQuery \n canonicalHeaders
// \n signedHeaders \n payloadHash——官方 get-vanilla 向量逐字节比对见 assert-net-parse）
export function canonicalRequestOf(method: string, canonicalUri: string,
  canonicalQuery: string, headerPairs: string[][], payloadHash: string): string {
  const sorted: string[][] = sortedHeaderPairs(headerPairs);
  const canonicalHeaders: string = sorted.map((p: string[]): string => p[0] + ':' + p[1] + '\n')
    .join('');
  const signedHeaders: string = sorted.map((p: string[]): string => p[0]).join(';');
  return method + '\n' + canonicalUri + '\n' + canonicalQuery + '\n' +
    canonicalHeaders + '\n' + signedHeaders + '\n' + payloadHash;
}

// 规范查询串（键值各自 RFC3986 编码后按键再按值排序——AWS get-vanilla-query-order-key
// 向量实证排序键为「编码后的字节序」，同名参数按值排）
export function canonicalQueryOf(params: string[][]): string {
  return params.map((p: string[]): string[] => [uriEncode(p[0]), uriEncode(p[1])])
    .sort((a: string[], b: string[]): number => {
      if (a[0] !== b[0]) {
        return a[0] < b[0] ? -1 : 1;
      }
      if (a[1] !== b[1]) {
        return a[1] < b[1] ? -1 : 1;
      }
      return 0;
    })
    .map((p: string[]): string => p[0] + '=' + p[1]).join('&');
}

// 待签名串（四段：算法 \n amzDate \n scope \n canonicalRequest 的 SHA-256 十六进制）
export function stringToSignOf(amzDate: string, scope: string, creqHash: string): string {
  return S3_ALGORITHM + '\n' + amzDate + '\n' + scope + '\n' + creqHash;
}

// 字节 → 小写十六进制（SigV4 签名与摘要的输出形制）
export function bytesToHex(bytes: Uint8Array): string {
  const hex: string = '0123456789abcdef';
  let out: string = '';
  for (let i = 0; i < bytes.length; i++) {
    out += hex.charAt(bytes[i] >> 4) + hex.charAt(bytes[i] & 15);
  }
  return out;
}

// 测试连接错误分型（纯函数——返回 null = 无专型，调用方给通用 HTTP 提示；body 供
// NoSuchBucket / 重定向类按正文识别——部分实现状态码不规范，正文关键词是第二判据）
export function probeErrorMessage(status: number, body: string): string | null {
  if (status === 401 || status === 403) {
    return '访问密钥不正确，请核对 Access Key ID 与 Secret Access Key';
  }
  if (status === 404 || body.indexOf('NoSuchBucket') !== -1) {
    return '存储桶不存在，请核对桶名';
  }
  if (status === 301 || status === 307 || body.indexOf('PermanentRedirect') !== -1 ||
    body.indexOf('AuthorizationHeaderMalformed') !== -1) {
    return '区域或寻址风格不匹配，试着修改区域或切换路径风格';
  }
  return null;
}

// 服务地址形态校验（纯函数，'' = 合法）：带路径的 endpoint 会让签名 Host〔endpointHost 剥
// 路径〕与请求 URL〔requestUrlOf 保留路径前缀〕分叉 → SignatureDoesNotMatch，且错误分型
// 误导为区域/寻址问题。尾斜杠容忍；空串判由页面 s3ConfigOk 承担
export function endpointFormatError(endpoint: string): string {
  let e: string = endpoint.trim();
  const scheme: number = e.indexOf('://');
  if (scheme >= 0) {
    e = e.substring(scheme + 3);
  }
  e = e.replace(/\/+$/, '');
  if (e.indexOf('/') >= 0) {
    return '服务地址不能带路径，请只填到主机或主机加端口，例如 https://s3.example.com';
  }
  return '';
}

// 备份档键判定（键尾段 = aicontrol_backup_*.zip——清理与恢复链共用）
export function isBackupKey(key: string): boolean {
  const tail: string = key.substring(key.lastIndexOf('/') + 1);
  return tail.startsWith(BACKUP_NAME_PREFIX) && tail.endsWith('.zip');
}

// 恢复候选序（纯函数——真列举单源）：备份档键按名倒序（名含日期戳，字典倒序 = 时间倒序；
// 同日重传同名覆盖无重复）；lastName 仍在列表内时置顶（本机最近上传优先——换设备后
// 列表首即远端最新，lastName 缺席无害）
export function composeS3RestoreCandidates(keys: string[], lastName: string): string[] {
  const backups: string[] = [];
  for (const k of keys) {
    if (isBackupKey(k)) {
      backups.push(k);
    }
  }
  backups.sort((a: string, b: string): number => a < b ? 1 : a > b ? -1 : 0);
  const result: string[] = [];
  if (lastName !== '' && backups.indexOf(lastName) !== -1) {
    result.push(lastName);
  }
  for (const k of backups) {
    if (k !== lastName) {
      result.push(k);
    }
  }
  return result;
}

// 清理删除集（纯函数）：备份档倒序取序、删除集按最老先列出（逐键独立 DELETE 的执行序 =
// 最老先删，与 WebDAV 清窗同向——中途中断留下的总是较新档）；非备份键不触碰（prefix 可能
// 指向共享目录——只删自己命名约定内的对象）
export function pruneDeleteKeys(keys: string[], keepCount: number): string[] {
  const backups: string[] = [];
  for (const k of keys) {
    if (isBackupKey(k)) {
      backups.push(k);
    }
  }
  backups.sort((a: string, b: string): number => a < b ? 1 : a > b ? -1 : 0);
  const result: string[] = [];
  for (let i = keepCount; i < backups.length; i++) {
    result.push(backups[i]);
  }
  return result.reverse();
}

// ListObjectsV2 响应提键（轻量字符串提取——对象名集自有可控，不引 XML 库；实体按五预
// 定义解码，&amp; 恒最后还原防二次解码）
export function parseListKeys(xml: string): string[] {
  const keys: string[] = [];
  let at: number = xml.indexOf('<Key>');
  while (at >= 0) {
    const end: number = xml.indexOf('</Key>', at);
    if (end < 0) {
      break;
    }
    keys.push(decodeXmlText(xml.substring(at + 5, end)));
    at = xml.indexOf('<Key>', end);
  }
  return keys;
}

export function decodeXmlText(s: string): string {
  return s.replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

// ListObjectsV2 单页解析（键集 + 截断续拉 token）：token 与键同过实体解码（token 为不透明
// 串按 XML 转义下发，不解码会把 &amp; 原样回传导致续拉空页）；IsTruncated 显式判 true 且
// NextContinuationToken 在场才取（双判据——部分实现截断为 false 时 token 字段形态不定）
export interface S3ListPage {
  keys: string[];
  nextToken: string;
}

export function parseListPage(xml: string): S3ListPage {
  const keys: string[] = parseListKeys(xml);
  if (xml.indexOf('<IsTruncated>true</IsTruncated>') < 0) {
    return { keys: keys, nextToken: '' };
  }
  const open: string = '<NextContinuationToken>';
  const at: number = xml.indexOf(open);
  if (at < 0) {
    return { keys: keys, nextToken: '' };
  }
  const end: number = xml.indexOf('</NextContinuationToken>', at);
  if (end < 0) {
    return { keys: keys, nextToken: '' };
  }
  return { keys: keys, nextToken: decodeXmlText(xml.substring(at + open.length, end)) };
}

// ── 加密原语（cryptoFramework——HMAC 链与 Md 摘要；SymKeyGenerator('HMAC') 裸二进制键
// 1~4096 字节合法〔d.ts 实查〕，ProviderShare convertKey 同款先例）──

async function sha256HexOfBytes(data: Uint8Array): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  await md.update({ data: data });
  const digest: cryptoFramework.DataBlob = await md.digest();
  return bytesToHex(digest.data);
}

async function sha256HexOfString(text: string): Promise<string> {
  return sha256HexOfBytes(new util.TextEncoder().encodeInto(text));
}

async function hmacSha256(keyBytes: Uint8Array, dataBytes: Uint8Array): Promise<Uint8Array> {
  const gen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
  const symKey: cryptoFramework.SymKey = await gen.convertKey({ data: keyBytes });
  const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
  await mac.init(symKey);
  await mac.update({ data: dataBytes });
  const out: cryptoFramework.DataBlob = await mac.doFinal();
  return out.data;
}

// 签名密钥派生链（AWS4{secret} → date → region → s3 → aws4_request，逐环 HMAC-SHA256）
async function deriveSigningKey(secret: string, dateStamp: string, region: string): Promise<Uint8Array> {
  const enc = (s: string): Uint8Array => new util.TextEncoder().encodeInto(s);
  let key: Uint8Array = await hmacSha256(enc('AWS4' + secret), enc(dateStamp));
  key = await hmacSha256(key, enc(region));
  key = await hmacSha256(key, enc(S3_SERVICE));
  key = await hmacSha256(key, enc('aws4_request'));
  return key;
}

// ── 请求执行 ──

// 非 2xx 异常（携带状态码与响应正文——probe 错误分型与列举错误翻译的第二判据）
class S3StatusError extends Error {
  status: number;
  body: string;
  constructor(status: number, body: string) {
    super('HTTP ' + status);
    this.status = status;
    this.body = body;
  }
}

// 状态码 → 中文错误（probeErrorMessage 专型优先，无专型给通用提示）
function statusToError(e: S3StatusError): Error {
  const mapped: string | null = probeErrorMessage(e.status, e.body);
  if (mapped !== null) {
    return new Error(mapped);
  }
  return new Error(`服务器不可达（HTTP ${e.status}）`);
}

// 单请求执行（SigV4 签名 + 发送；非 2xx 抛 S3StatusError。body 支持 PUT 载荷——
// payload hash 取真实 SHA-256，无 body 用空串哈希，全程不用 UNSIGNED-PAYLOAD 简化分支）
async function s3Request(method: http.RequestMethod, methodName: string, cfg: S3Config,
  key: string, query: string[][], body?: ArrayBuffer,
  contentType?: string): Promise<http.HttpResponse> {
  const region: string = cfg.region.trim() !== '' ? cfg.region.trim() : DEFAULT_REGION;
  const now: Date = new Date();
  const amzDate: string = amzDateTime(now);
  const dateStamp: string = amzDate.substring(0, 8);
  const payloadHash: string = body === undefined ?
    await sha256HexOfBytes(new Uint8Array(0)) : await sha256HexOfBytes(new Uint8Array(body));
  const headerPairs: string[][] = [
    ['host', hostHeaderOf(cfg)],
    ['x-amz-date', amzDate],
    ['x-amz-content-sha256', payloadHash]
  ];
  if (contentType !== undefined) {
    headerPairs.push(['content-type', contentType]);
  }
  const canonicalQuery: string = canonicalQueryOf(query);
  const creq: string = canonicalRequestOf(methodName, canonicalUriOf(cfg, key),
    canonicalQuery, headerPairs, payloadHash);
  const creqHash: string = await sha256HexOfString(creq);
  const scope: string = scopeOf(dateStamp, region);
  const sts: string = stringToSignOf(amzDate, scope, creqHash);
  const signingKey: Uint8Array = await deriveSigningKey(cfg.secretAccessKey, dateStamp, region);
  const signature: string = bytesToHex(await hmacSha256(signingKey,
    new util.TextEncoder().encodeInto(sts)));
  const authorization: string = S3_ALGORITHM + ' Credential=' + cfg.accessKeyId + '/' + scope +
    ', SignedHeaders=' + signedHeadersOf(headerPairs) + ', Signature=' + signature;

  // 头先于句柄构造（成对释放——签名链抛错时尚未 createHttp，无句柄可泄，顺序不可换）
  const headers: Record<string, string> = {};
  headers['Authorization'] = authorization;
  headers['x-amz-date'] = amzDate;
  headers['x-amz-content-sha256'] = payloadHash;
  if (contentType !== undefined) {
    headers['Content-Type'] = contentType;
  }
  applyDefaultUserAgent(headers);
  const url: string = requestUrlOf(cfg, key) + (canonicalQuery !== '' ? '?' + canonicalQuery : '');
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 请求日志（WebDavApi 同款纪律）：本层是 S3 链唯一传输出口；Authorization 值级脱敏由
  // ReqLog 清单承接（SigV4 串含密钥派生物——虽不可逆仍按凭据头脱敏，不留排查噪音）
  const logId: string = reqLogBegin({
    source: '对象存储备份', model: '', method: methodName, url: url, headers: headers, body: ''
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      usingCache: false,
      expectDataType: method === http.RequestMethod.GET ?
        http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
    };
    applyEffectiveProxy(options);
    if (body !== undefined) {
      options.extraData = body;
    }
    const resp: http.HttpResponse = await req.request(url, options);
    reqLogSetResponseHeaders(logId, resp.header);
    const failTail: string = typeof resp.result === 'string' ? resp.result : '';
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt,
      resp.responseCode < 200 || resp.responseCode >= 300 ? 'HTTP ' + resp.responseCode : '',
      resp.responseCode < 200 || resp.responseCode >= 300 ? failTail : '');
    logged = true;
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new S3StatusError(resp.responseCode, failTail);
    }
    return resp;
  } catch (e) {
    if (!logged) {
      const biz = e as BusinessError;
      const netMsg: string = typeof biz.code === 'number' ?
        '无法连接服务器(code ' + biz.code + ')' : '网络错误';
      reqLogEnd(logId, -1, Date.now() - startedAt, netMsg, '');
    }
    throw e as Error;
  } finally {
    // destroy 包 try（WebDavApi 同款：裸 destroy 抛错会把已成功的传输改写成失败）
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// ── 五操作（与 WebDavApi 一一对应；档案命名/清理语义同源，恢复发现走真列举）──

// 测试连接（ListObjectsV2 探活——桶根 max-keys=1；RikkaHub 同语义。403/404/重定向三专型
// 中文提示见 probeErrorMessage，其余状态给通用 HTTP 提示；网络层错误原样上抛）
export async function probe(cfg: S3Config): Promise<void> {
  try {
    await s3Request(http.RequestMethod.GET, 'GET', cfg, '', [['list-type', '2'],
      ['max-keys', '1']]);
  } catch (e) {
    if (e instanceof S3StatusError) {
      throw statusToError(e as S3StatusError);
    }
    throw e as Error;
  }
}

// 列举 prefix 下对象键（翻页——continuation-token 续拉至页上限，见头注释；403 专型翻译
// 上抛，其余原样）
async function listRemoteKeys(cfg: S3Config): Promise<string[]> {
  const prefix: string = objectKeyOf(cfg, '');
  const keys: string[] = [];
  let token: string = '';
  for (let page = 0; page < MAX_LIST_PAGES; page++) {
    const query: string[][] = [['list-type', '2'], ['max-keys', '1000']];
    if (prefix !== '') {
      query.push(['prefix', prefix + '/']);
    }
    if (token !== '') {
      query.push(['continuation-token', token]);
    }
    const resp: http.HttpResponse = await s3Request(http.RequestMethod.GET, 'GET', cfg, '', query);
    const text: string = util.TextDecoder.create('utf-8')
      .decodeToString(new Uint8Array(resp.result as ArrayBuffer));
    const pageData: S3ListPage = parseListPage(text);
    for (const k of pageData.keys) {
      keys.push(k);
    }
    if (pageData.nextToken === '') {
      return keys;
    }
    token = pageData.nextToken;
  }
  throw new Error('远端对象过多，列举超出上限，请更换备份目录前缀');
}

// 上传备份（PUT 当日日期档——同日重传覆盖；成功返回实际上传的档名，页面层持久化为
// lastName 供恢复链置顶。S3 无目录语义，无需 WebDAV 的 ensureDir 前置）
export async function uploadBackup(cfg: S3Config, localPath: string): Promise<string> {
  const data: ArrayBuffer = await readLocalFile(localPath);
  const name: string = remoteBackupName(0);
  await s3Request(http.RequestMethod.PUT, 'PUT', cfg, objectKeyOf(cfg, name), [], data,
    'application/zip');
  return name;
}

// 下载最近一份备份到本地（恢复链 = 列举 → 候选序 → 逐键探测；链中 404 静默继续〔列举与
// 取回之间档被清 = 规格语义〕，403 专型翻译上抛；全空抛统一提示——文案与 WebDAV 同句）
export async function downloadLatestBackup(cfg: S3Config, localPath: string,
  lastName: string): Promise<string> {
  const keys: string[] = await listRemoteKeys(cfg);
  const candidates: string[] = composeS3RestoreCandidates(keys, lastName);
  for (const key of candidates) {
    const hit: string | null = await tryGetBackup(cfg, localPath, key);
    if (hit !== null) {
      return hit;
    }
  }
  throw new Error('远端还没有备份文件，请先在任意设备上传一次');
}

// 恢复链单环探测：GET 命中写 localPath 返回键名；404 返 null 继续下一环；
// 403/401 专型翻译上抛；其余异常原样上抛（网络错/5xx 不吞——WebDavApi 同口径）
async function tryGetBackup(cfg: S3Config, localPath: string, key: string): Promise<string | null> {
  try {
    const resp: http.HttpResponse = await s3Request(http.RequestMethod.GET, 'GET', cfg, key, []);
    writeLocalFile(localPath, resp.result as ArrayBuffer);
    return key.substring(key.lastIndexOf('/') + 1);
  } catch (e) {
    if (e instanceof S3StatusError) {
      const statusErr: S3StatusError = e as S3StatusError;
      if (statusErr.status === 404) {
        return null;
      }
      throw statusToError(statusErr);
    }
    throw e as Error;
  }
}

// 滚动清理（上传成功后调用）：列举 → 删除集（保留最近 5 份备份档）→ 逐键 DELETE。
// 恒正常返回——列举失败或删除失败只 hilog.warn 静默吞（备份本体已成功，清理失败只影响
// 远端多占空间，不判整链失败——WebDavApi 同语义）
export async function pruneOldBackups(cfg: S3Config): Promise<void> {
  let keys: string[] = [];
  try {
    keys = await listRemoteKeys(cfg);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '清理列举失败，本轮放弃（备份本体已上传成功）：%{public}s',
      (e as Error).message);
    return;
  }
  const deletions: string[] = pruneDeleteKeys(keys, BACKUP_KEEP_COUNT);
  for (const key of deletions) {
    await deleteRemoteFile(cfg, key);
  }
}

// 删除远端单档（清理轮专用）。★ 尽力而为语义：一切异常静默吞（含 404/5xx/网络错）——
// 404 = 档不存在 = 目标状态已达（WebDavApi 同口径）
async function deleteRemoteFile(cfg: S3Config, key: string): Promise<void> {
  try {
    await s3Request(http.RequestMethod.DELETE, 'DELETE', cfg, key, []);
  } catch (e) {
    // 尽力而为：吞（见函数头注释）
  }
}

// ── 本地文件读写（fs 直读直写，成对关 fd——与 WebDavApi 同款小件复制，两传输通道零耦合
//    不互引 IO 面）──

async function readLocalFile(path: string): Promise<ArrayBuffer> {
  const stat: fs.Stat = fs.statSync(path);
  const ab: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
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
