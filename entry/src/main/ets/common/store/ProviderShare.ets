// 服务商配置导出/导入域：单服务商完整配置（provider 行 + 模型清单 + Key 池 + 余额配置）↔
// 可分享/备份的 JSON 文件；v2（schemaVersion 2）批量容器 MultiShare 打包全部已启用服务商。
// ★ 版本双轨（格式 = { schemaVersion, app:'aicontrol', exportedAt, encrypted, data }）：
// v1（data = ShareProvider 单个对象）恒保持——旧版应用互导不受影响、字节输出不变；v2
//（data = MultiShare）批量；导入侧两版统一解析（parseShareFile 恒返回 ShareProvider[]，
// v1 包单元素数组）；版本 > SCHEMA_VERSION 拒绝（「先升级应用」）；encrypted=true 时 data =
// EncryptedBlock（密文容器，内层再 JSON.parse）。导入恒**重新生成 id**（provider/model/
// key 三层全新 id）：导入即本地新建，天然无同 id 冲突、可重复导入为副本，原 id 不跨设备保留。
// ★ 安全设计（2026-09-02 拍板，销项 BLOCKED「导出 Key 明文设计」）：
// · 「配置文件」不含任何密钥（明文 JSON，推荐分享形态）——Key 池 secret 置 null（导入落
//   「明文缺失」行，既有重填链承接）、balance_key 与自定义请求头（含余额请求头）同级清空
//  （头值语义上可能含鉴权信息）；「加密备份」含密钥：**强制**口令加密（PBKDF2 + AES-256-
//   GCM），裸明文 Key 落盘的产物形态不存在（防呆）。加密保护的是传输链路（文件被截获不
//   泄露），不是分享行为本身——口令交给对方后对方即持有 Key 明文（额度共享，UI 说明气泡
//   呈示）。Key 明文内存缓冲用完即弃，禁进日志/toast（明文最小化红线同源）。
// · serializeEncryptedContainer / openEncryptedContainer 供 ExportImport 密钥档 secrets.enc
//   复用——加密实现单一来源仍在本文件（算法/参数未改），其它域禁新建第二套。
// 链路先例：沙箱暂存 + systemShare 分享 = LogPage 导出同款（分享面板自带「另存为文件」）；
// 文件选择 = DocumentViewPicker（免权限）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  deleteProvider, insertModel, insertProvider, ProviderRow, queryModels, queryProviders,
  setModelEnabled, setProviderEnabled, setProviderKeyPickMode, updateProviderPromptCache
} from './ProviderDb';
import {
  importPoolKeyRow, KEY_PICK_RANDOM, KEY_PICK_ROTATE, ProviderKeyRow, queryProviderKeys
} from './ProviderKeyDb';
import { loadPoolKey, removePoolKeys } from './KeyStore';
import { BalanceConfig, queryBalanceState, updateBalanceConfig } from './ProviderBalanceDb';

// ── 导出包数据模型（1/2 双轨共用；字段 = 各表列直映——DB 加列时在此补字段 + 升
// SCHEMA_VERSION，导入侧按缺省兜底向后兼容）──

export interface ShareModelRow {
  modelId: string;
  name: string;
  kind: string;
  caps: string;
  enabled: boolean;
}

export interface ShareKeyRow {
  label: string;
  enabled: boolean;
  sortOrder: number;
  // null = 导出「不含密钥」档（或导出时该行明文本就缺失——不造假象）；string = 明文
  secret: string | null;
}

export interface ShareProvider {
  name: string;
  baseUrl: string;
  enabled: boolean;
  protocol: string;
  endpoint: string;
  // 自定义请求头 JSON 串（AiTypes [{k,v}] 序列化形态；不含密钥档清空）
  headers: string;
  promptCacheEnabled: boolean;
  promptCacheTtl: string;
  bodyOverrides: string;
  // 取钥方式（DB v32；'rotate' | 'random'）。老备份无本字段——导入侧按 rotate 钳位
  //（缺字段 = 存量语义 = 轮询），字节级向后兼容
  keyPickMode: string;
  balance: BalanceConfig;
  models: ShareModelRow[];
  keys: ShareKeyRow[];
}

// 批量容器（v2 data 位；providers = 全部已启用服务商打包；导入恒新增副本，逐家独立落库
// ——单家失败不影响其余）
export interface MultiShare {
  providers: ShareProvider[];
}

// 加密封装（encrypted=true 的 data 位）：PBKDF2-HMAC-SHA256 派生 AES-256-GCM 认证加密
// ——参数随包携带（iterations/盐/IV），口令不进包
export interface EncryptedBlock {
  alg: string;
  iterations: number;
  salt: string;
  iv: string;
  tag: string;
  ct: string;
}

// 文件外层容器（data 位两态：object = ShareProvider | EncryptedBlock，解析侧按 encrypted
// 分支 as 断言——ArkTS 联合收窄限制下的项目惯用形态）
export interface ShareContainer {
  schemaVersion: number;
  app: string;
  exportedAt: number;
  encrypted: boolean;
  data: object;
}

// 加密参数（2026-09-03 定稿）：AES-256-GCM（IV 12B 官方推荐长）+ PBKDF2 60 万次迭代
//（OWASP 对 PBKDF2-HMAC-SHA256 的现行建议值，首版 10 万次偏弱随自检升级；解密恒用包内
// iterations——新旧参数文件互导兼容）+ 盐 16B + 认证标签 16B
// 当前最高 schemaVersion（解析侧拒绝 > 本值；序列化侧版本号显式传参〔v1 壳恒 1、v2 壳恒 2〕，
// 本常量只做解析侧上限判定）
const SCHEMA_VERSION: number = 2;
const APP_ID: string = 'aicontrol';
const KDF_ALG: string = 'PBKDF2|SHA256';
const KDF_ITERATIONS: number = 600000;
// 包内 iterations 合法范围（gcmOpen 校验——防手改文件构造超大迭代拖死解密线程）
const KDF_ITER_MIN: number = 10000;
const KDF_ITER_MAX: number = 10000000;
const KEY_SIZE_BYTES: number = 32;
const SALT_BYTES: number = 16;
const IV_BYTES: number = 12;
const TAG_BYTES: number = 16;
// 导入文件大小防线（P0-1 校验外部输入）：单服务商配置 JSON 量级 KB 级，5MB 足够冗余；
// 超限 = 选错文件，拒绝读取防内存无界
const MAX_IMPORT_BYTES: number = 5 * 1024 * 1024;

// Base64 编解码（util.d.ts 核实：Base64Helper 构造即用；编码 encodeToStringSync /
// 解码 decodeSync——decodeToUint8Array 为旧名不存在）
const b64: util.Base64Helper = new util.Base64Helper();

// ── 导出：收集 → 序列化/加密 ──

// 收集单服务商完整配置；includeSecrets=false 时三处敏感面同级清空（见头注释安全设计）。
// 服务商不存在（已被删）上抛由调用方 toast（P0-1 不静默）
export async function buildSharePayload(providerId: string, includeSecrets: boolean): Promise<ShareProvider> {
  const rows: ProviderRow[] = await queryProviders();
  const row: ProviderRow | undefined = rows.find((item: ProviderRow): boolean => item.id === providerId);
  if (row === undefined) {
    throw new Error('服务商不存在或已删除');
  }
  const balance: BalanceConfig = await queryBalanceState(providerId);
  const models = await queryModels(providerId, '');
  const keyRows = await queryProviderKeys(providerId);
  const keys: ShareKeyRow[] = [];
  for (const k of keyRows) {
    const secret: string | null = includeSecrets ? await loadPoolKey(providerId, k.id) : null;
    keys.push({ label: k.label, enabled: k.enabled, sortOrder: k.sortOrder, secret: secret });
  }
  return {
    name: row.name,
    baseUrl: row.baseUrl,
    enabled: row.enabled,
    protocol: row.protocol,
    endpoint: row.endpoint,
    headers: includeSecrets ? row.headers : '',
    promptCacheEnabled: row.promptCacheEnabled,
    promptCacheTtl: row.promptCacheTtl,
    bodyOverrides: row.bodyOverrides,
    keyPickMode: row.keyPickMode,
    balance: includeSecrets ? balance : clearBalanceSecrets(balance),
    models: models.map((m): ShareModelRow => {
      return { modelId: m.modelId, name: m.name, kind: m.kind, caps: m.caps, enabled: m.enabled };
    }),
    keys: keys
  };
}

// 「不含密钥」档的余额敏感面清空（key = 查询鉴权、headers = 可能含鉴权的自定义请求头）
function clearBalanceSecrets(cfg: BalanceConfig): BalanceConfig {
  const safe: BalanceConfig = {
    enabled: cfg.enabled,
    baseUrl: cfg.baseUrl,
    path: cfg.path,
    resultPath: cfg.resultPath,
    currency: cfg.currency,
    currencyPath: cfg.currencyPath,
    key: '',
    headers: ''
  };
  return safe;
}

// ── 序列化（v1 单家 / v2 批量薄壳 + 共用内核；单家输出字节与历史一致，旧版互导零回归）──

// 明文内核（v = 显式版本号：v1 壳 1、v2 壳 2；data = v1 时 ShareProvider、v2 时 MultiShare）
function serializeContainer(data: object, version: number): string {
  const container: ShareContainer = {
    schemaVersion: version,
    app: APP_ID,
    exportedAt: Date.now(),
    encrypted: false,
    data: data
  };
  return JSON.stringify(container);
}

// 加密内核（同明文内核 + 强制口令加密——裸明文 Key 落盘形态不存在，见头注释）。★ 加密
// 实现单一来源：ExportImport 密钥档复用本函数，其它域禁新建第二套；仅供复用，参数未改
export async function serializeEncryptedContainer(data: object, version: number,
  passphrase: string): Promise<string> {
  const plain: Uint8Array = util.TextEncoder.create('utf-8')
    .encodeInto(JSON.stringify(data));
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const salt: Uint8Array = (await random.generateRandom(SALT_BYTES)).data;
  const iv: Uint8Array = (await random.generateRandom(IV_BYTES)).data;
  const cipherText: EncryptedBlock = {
    alg: KDF_ALG,
    iterations: KDF_ITERATIONS,
    salt: b64.encodeToStringSync(salt),
    iv: b64.encodeToStringSync(iv),
    tag: '',
    ct: ''
  };
  const sealed = await gcmSeal(plain, passphrase, salt, iv);
  cipherText.tag = b64.encodeToStringSync(sealed.tag);
  cipherText.ct = b64.encodeToStringSync(sealed.ct);
  const container: ShareContainer = {
    schemaVersion: version,
    app: APP_ID,
    exportedAt: Date.now(),
    encrypted: true,
    data: cipherText
  };
  return JSON.stringify(container);
}

// v1 单家明文（不含密钥档——包内无任何密钥，可直接分享）
export function serializeShare(payload: ShareProvider): string {
  return serializeContainer(payload, 1);
}

// v1 单家加密（含密钥档）
export async function serializeEncryptedShare(payload: ShareProvider, passphrase: string): Promise<string> {
  return serializeEncryptedContainer(payload, 1, passphrase);
}

// v2 批量明文（已启用服务商打包；data = MultiShare）
export function serializeShares(payloads: ShareProvider[]): string {
  const multi: MultiShare = { providers: payloads };
  return serializeContainer(multi, 2);
}

// v2 批量加密（同一口令加密整个包，导入时一次解出全部）
export async function serializeEncryptedShares(payloads: ShareProvider[],
  passphrase: string): Promise<string> {
  const multi: MultiShare = { providers: payloads };
  return serializeEncryptedContainer(multi, 2, passphrase);
}

// GCM 密封产物（ct 与认证 tag 分离携带——doFinal 产物 ct||tag 的拆分形态）
interface GcmSealed {
  ct: Uint8Array;
  tag: Uint8Array;
}

// AES-256-GCM 认证加密：返回密文与认证标签（doFinal 产物 = ct||tag 尾部 16B——本地
// GcmParamsSpec.d.ts 核实；加密态 init 需 16B 占位 authTag，GCM 特有约定）
async function gcmSeal(plain: Uint8Array, passphrase: string, salt: Uint8Array, iv: Uint8Array):
  Promise<GcmSealed> {
  const key: cryptoFramework.SymKey = await deriveAesKey(passphrase, salt, KDF_ITERATIONS);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
  const params: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: iv },
    aad: { data: new Uint8Array(0) },
    authTag: { data: new Uint8Array(TAG_BYTES) }
  };
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
  const sealed: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain });
  const total: number = sealed.data.length;
  if (total <= TAG_BYTES) {
    throw new Error('加密结果异常（长度不足）');
  }
  return {
    ct: sealed.data.subarray(0, total - TAG_BYTES),
    tag: sealed.data.subarray(total - TAG_BYTES)
  };
}

// PBKDF2 派生 AES 密钥（password 按 UTF-8 编码参与派生——d.ts 核实；iterations 由调用方
// 传入——加密侧用当前常量、解密侧用包内值，见 gcmOpen）
async function deriveAesKey(passphrase: string, salt: Uint8Array, iterations: number):
  Promise<cryptoFramework.SymKey> {
  const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf(KDF_ALG);
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password: passphrase,
    salt: salt,
    iterations: iterations,
    keySize: KEY_SIZE_BYTES
  };
  const derived: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
  const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  return await generator.convertKey({ data: derived.data });
}

// 解密封装（口令错误/篡改 = GCM 认证失败，统一转「口令错误或文件已损坏」中文提示）。
// ★ iterations 恒用包内携带值（首版误用当前常量 = 未来升迭代参数旧文件全解不开的地雷）；
// 范围校验防手改文件构造超大迭代拖死解密线程
async function gcmOpen(block: EncryptedBlock, passphrase: string): Promise<Uint8Array> {
  if (typeof block.iterations !== 'number' || block.iterations < KDF_ITER_MIN ||
    block.iterations > KDF_ITER_MAX) {
    throw new Error('加密参数异常，文件已损坏');
  }
  const salt: Uint8Array = b64.decodeSync(block.salt);
  const iv: Uint8Array = b64.decodeSync(block.iv);
  const tag: Uint8Array = b64.decodeSync(block.tag);
  const ct: Uint8Array = b64.decodeSync(block.ct);
  const key: cryptoFramework.SymKey = await deriveAesKey(passphrase, salt, block.iterations);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
  const params: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: iv },
    aad: { data: new Uint8Array(0) },
    authTag: { data: tag }
  };
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
  const plain: cryptoFramework.DataBlob = await cipher.doFinal({ data: ct });
  return plain.data;
}

// ── 导入：解析 → 校验 → 落库编排 ──

// 加密容器解密（ExportImport 密钥档同用——加密实现单一来源）。只解壳不做载荷语义校验
//（载荷结构各消费域自管）；口令错误/篡改统一中文提示
export async function openEncryptedContainer(jsonText: string,
  passphrase: string): Promise<string> {
  let outer: ShareContainer;
  try {
    outer = JSON.parse(jsonText) as ShareContainer;
  } catch (e) {
    throw new Error('加密文件无法解析');
  }
  // 壳为 null（文件恰为 JSON null——手改/截断）时取属性抛英文 TypeError，前置拦成同句中文
  //（数组/字符串/数字取属性得 undefined 原就落中文分支）
  if (outer === null || typeof outer !== 'object' || Array.isArray(outer)) {
    throw new Error('加密文件无法解析');
  }
  if (outer.encrypted !== true) {
    throw new Error('文件不是加密件');
  }
  const data: Object | undefined = outer.data;
  if (data === undefined || data === null || typeof data !== 'object') {
    throw new Error('加密数据不完整，文件已损坏');
  }
  const block: EncryptedBlock = data as EncryptedBlock;
  if (typeof block.ct !== 'string' || typeof block.tag !== 'string' ||
    typeof block.salt !== 'string' || typeof block.iv !== 'string') {
    throw new Error('加密数据不完整，文件已损坏');
  }
  let plainBytes: Uint8Array;
  try {
    plainBytes = await gcmOpen(block, passphrase);
  } catch (e) {
    throw new Error('口令错误或文件已损坏');
  }
  try {
    return util.TextDecoder.create('utf-8').decodeToString(plainBytes);
  } catch (e) {
    throw new Error('文件解密后内容异常，可能已损坏');
  }
}

// 解析导出文件文本为配置载荷数组（v1 单元素；v2 批量逐家）。askPassphrase = 口令获取回调
//（UI 层弹窗注入——用户取消时回调 throw 直接 toast）。校验失败抛中文 Error（P0-1 拒绝静默）
export async function parseShareFile(jsonText: string,
  askPassphrase: () => Promise<string>): Promise<ShareProvider[]> {
  let outer: ShareContainer;
  try {
    outer = JSON.parse(jsonText) as ShareContainer;
  } catch (e) {
    throw new Error('不是合法的配置文件（JSON 解析失败）');
  }
  // 壳为 null 前置拦（同 openEncryptedContainer 同族守卫；数组/字符串/数字原就落中文分支）
  if (outer === null || typeof outer !== 'object' || Array.isArray(outer)) {
    throw new Error('不是 aicontrol 导出的配置文件');
  }
  if (outer.app !== APP_ID || typeof outer.schemaVersion !== 'number') {
    throw new Error('不是 aicontrol 导出的配置文件');
  }
  if (outer.schemaVersion > SCHEMA_VERSION) {
    throw new Error('文件版本过高（v' + outer.schemaVersion + '），请先升级应用');
  }
  let payloadList: ShareProvider[];
  if (outer.encrypted === true) {
    // encrypted=true 而 data 缺失/非对象（手改/截断）时取属性抛英文 TypeError，补守卫走中文
    const data: Object | undefined = outer.data;
    if (data === undefined || data === null || typeof data !== 'object') {
      throw new Error('加密数据不完整，文件已损坏');
    }
    const block = data as EncryptedBlock;
    if (typeof block.ct !== 'string' || typeof block.tag !== 'string' ||
      typeof block.salt !== 'string' || typeof block.iv !== 'string') {
      throw new Error('加密数据不完整，文件已损坏');
    }
    const passphrase: string = await askPassphrase();
    let plainBytes: Uint8Array;
    try {
      plainBytes = await gcmOpen(block, passphrase);
    } catch (e) {
      throw new Error('口令错误或文件已损坏');
    }
    let plainText: string;
    try {
      plainText = util.TextDecoder.create('utf-8').decodeToString(plainBytes);
    } catch (e) {
      throw new Error('文件解密后内容异常，可能已损坏');
    }
    let payloadData: ShareProvider | MultiShare;
    try {
      payloadData = JSON.parse(plainText) as ShareProvider | MultiShare;
    } catch (e) {
      throw new Error('文件解密后内容异常，可能已损坏');
    }
    payloadList = extractPayloads(payloadData, outer.schemaVersion);
  } else {
    payloadList = extractPayloads(outer.data as ShareProvider | MultiShare, outer.schemaVersion);
  }
  const validated: ShareProvider[] = [];
  for (let i = 0; i < payloadList.length; i++) {
    try {
      validated.push(validatePayload(payloadList[i]));
    } catch (e) {
      // 多家文件脏条目报「第 N 个配置」定位（单家不加前缀——既有 toast 文案零回归）
      throw new Error(payloadList.length > 1 ?
        '第 ' + (i + 1) + ' 个配置：' + (e as Error).message : (e as Error).message);
    }
  }
  return validated;
}

// data 位 → 载荷数组（v1 = data 即单个 ShareProvider；v2 = 须为 MultiShare 且 providers
// 非空——空包显式拒绝，P0-1 防「空文件假装成功」）
function extractPayloads(data: ShareProvider | MultiShare, version: number): ShareProvider[] {
  if (version >= 2) {
    const multi = data as MultiShare;
    if (multi === undefined || multi === null ||
      !Array.isArray(multi.providers) || multi.providers.length === 0) {
      throw new Error('文件内没有服务商配置');
    }
    return multi.providers;
  }
  return [data as ShareProvider];
}

// 载荷基础校验与兜底（宽容解析：可选字段缺失用库默认值兜底——向后兼容旧版/手改文件；必填
// 项缺失显式拒绝）
function validatePayload(payload: ShareProvider): ShareProvider {
  if (payload === undefined || payload === null) {
    throw new Error('配置内容为空，文件已损坏');
  }
  if (typeof payload.name !== 'string' || payload.name.trim() === '' ||
    typeof payload.baseUrl !== 'string' || payload.baseUrl.trim() === '') {
    throw new Error('配置缺少名称或 Base URL，无法导入');
  }
  if (!payload.baseUrl.startsWith('http://') && !payload.baseUrl.startsWith('https://')) {
    throw new Error('Base URL 需以 http:// 或 https:// 开头');
  }
  if (!Array.isArray(payload.models)) {
    payload.models = [];
  }
  if (!Array.isArray(payload.keys)) {
    payload.keys = [];
  }
  if (typeof payload.enabled !== 'boolean') {
    payload.enabled = true;
  }
  if (typeof payload.protocol !== 'string' || payload.protocol === '') {
    payload.protocol = 'openai';
  }
  if (payload.endpoint !== 'responses') {
    payload.endpoint = 'chat'; // 异常值钳位（resolveActiveConnection 同款保守语义）
  }
  if (typeof payload.promptCacheEnabled !== 'boolean') {
    payload.promptCacheEnabled = false;
  }
  if (payload.promptCacheTtl !== '1h') {
    payload.promptCacheTtl = '5m';
  }
  // 取钥方式钳位（v32；老备份无本字段/手改脏值 → rotate = 存量语义——promptCacheTtl 同款）
  if (payload.keyPickMode !== KEY_PICK_RANDOM) {
    payload.keyPickMode = KEY_PICK_ROTATE;
  }
  if (typeof payload.headers !== 'string') {
    payload.headers = '';
  }
  if (typeof payload.bodyOverrides !== 'string') {
    payload.bodyOverrides = '';
  }
  if (payload.balance === undefined || payload.balance === null) {
    payload.balance = {
      enabled: false, baseUrl: '', path: '', resultPath: '',
      currency: '', currencyPath: '', key: '', headers: ''
    };
  }
  return payload;
}

// 落库编排（导入 = 本地新建，三层 id 全部重新生成——见头注释）：provider 行 → 提示缓存 →
// 余额 → 模型逐行（停用态恢复）→ Key 池逐行（明文有则成对写 Asset，无则落「明文缺失」行）。
// ★ 兜底回滚：insertProvider 成行后任一步失败 → 级联清库行（deleteProvider）+ Asset 池
// 条目成对清理（removePoolKeys），半成品零留存；回滚自身失败仅 hilog.error 不掩盖主错误
//（P0-1 主错上抛）。单语句原子性依赖不变（DB 无多域事务）
export async function applyShare(payload: ShareProvider): Promise<string> {
  const row = await insertProvider(payload.name.trim(), payload.baseUrl.trim(),
    payload.protocol, payload.endpoint, payload.headers, payload.bodyOverrides);
  try {
    if (!payload.enabled) {
      await setProviderEnabled(row.id, false);
    }
    await updateProviderPromptCache(row.id, payload.promptCacheEnabled, payload.promptCacheTtl);
    await setProviderKeyPickMode(row.id, payload.keyPickMode);
    await updateBalanceConfig(row.id, payload.balance);
    for (const m of payload.models) {
      if (typeof m.modelId !== 'string' || m.modelId.trim() === '') {
        continue; // 空模型 id 行跳过（手改文件防炸——插入会因约束失败中断全链）
      }
      // JSON 动态字段 typeof 守卫（ArkTS 严格模式禁对非空类型用 ?? 兜底，统一 typeof 姿势）
      const mName: string = typeof m.name === 'string' ? m.name : '';
      const mKind: string = m.kind === 'embedding' ? 'embedding' : 'chat';
      const mCaps: string = typeof m.caps === 'string' ? m.caps : '';
      const mr = await insertModel(row.id, m.modelId, mName, mKind, mCaps);
      if (m.enabled === false) { // 仅显式 false 才停用（字段缺失不误停——JSON 兜底语义）
        await setModelEnabled(mr.id, false);
      }
    }
    for (const k of payload.keys) {
      if (typeof k.label !== 'string' || k.label.trim() === '') {
        continue; // 无名行跳过（label 非空 = provider_keys 展示语义底线）
      }
      const order: number = typeof k.sortOrder === 'number' ? k.sortOrder : 0;
      await importPoolKeyRow(row.id, k.label, k.enabled === true, order, k.secret);
    }
    return row.id;
  } catch (e) {
    try {
      const keyRows = await queryProviderKeys(row.id);
      await deleteProvider(row.id);
      await removePoolKeys(row.id, keyRows.map((k: ProviderKeyRow): string => k.id));
    } catch (re) {
      hilog.error(0xD5A2, 'ProviderShare', 'applyShare rollback failed: %{public}s', JSON.stringify(re));
    }
    throw e as Error;
  }
}

// ── 沙箱暂存（分享面板前置；LogPageDataSource.exportLogsToSandbox 同款链路）──

// 写导出文件到应用沙箱 filesDir（分享面板需要 App file URI）：文件名 = aicontrol-<服务商
// 名清洗>-<时间戳>.json；写前清理历史导出（数据有界红线）；清理失败仅记录不阻断；成对
// 释放 fd（try/finally 防泄漏）。返回路径供 URI 转换
export function writeShareFile(context: common.Context, content: string, providerName: string): string {
  const now: Date = new Date();
  const pad = (n: number): string => (n < 10 ? '0' + n : String(n));
  const stamp: string = pad(now.getFullYear()) + pad(now.getMonth() + 1) + pad(now.getDate()) +
    '-' + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());
  // 服务商名清洗文件名非法字符（Windows/鸿蒙保留字符集——跨端另存不炸）
  const safeName: string = providerName.replace(/[\\/:*?"<>|]/g, '_').substring(0, 40);
  const fileName: string = 'aicontrol-' + safeName + '-' + stamp + '.json';
  const dir: string = context.filesDir;
  const path: string = dir + '/' + fileName;
  // 成对释放 fd（try/finally 防泄漏）；TRUNC（时间戳仅秒级，同秒二次导出同名——不截断
  // 会残留旧尾部）
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
  // 清理历史导出文件（数据有界；先写后清——原「先清后写」在写入失败时连旧文件一起损失；
  // 清理失败仅记录不阻断导出）
  try {
    for (const f of fs.listFileSync(dir)) {
      if (f.startsWith('aicontrol-') && f.endsWith('.json') && f !== fileName) {
        fs.unlinkSync(dir + '/' + f);
      }
    }
  } catch (err) {
    hilog.error(0xD5A2, 'ProviderShare', 'clean old share files failed: %{public}s', JSON.stringify(err));
  }
  return path;
}

// ── 导入文件读取 ──

// 从文档选择器 URI 读文本（先 openSync 取 fd 再 stat/read——媒体库 URI 直接传路径解析
// 不可靠）；超限拒绝（防选错大文件，见 MAX_IMPORT_BYTES）。★ readSync 的 buffer 只接受
// ArrayBuffer（本地 fs.d.ts:2744 实锤——传 Uint8Array 真机报 13900020）
export async function readShareFileText(uri: string): Promise<string> {
  const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat: fs.Stat = fs.statSync(file.fd);
    if (stat.size > MAX_IMPORT_BYTES) {
      throw new Error('文件过大（' + Math.round(stat.size / 1024) + 'KB），不是有效的配置文件');
    }
    const ab: ArrayBuffer = new ArrayBuffer(stat.size);
    const readLen: number = fs.readSync(file.fd, ab);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(ab).subarray(0, readLen));
  } finally {
    fs.closeSync(file);
  }
}
