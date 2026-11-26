// API key 凭据层：官方 Asset Store Kit（@ohos.security.asset，底层 HUKS 加密，专为密码/
// token 类短敏感数据设计）。红线（拍板）：禁明文硬编码/明文 Preferences，key 不进代码
// 不进 git，★明文不进 DB/日志/toast（掩码显示）。
// ★ 资产形态清单（现役 + 遗留；各形态细则见对应节横幅）：
// · 服务商 Key 池（v3 现役）：一服务商多条，条目名 = 'aic.p.' + providerId + '/' + keyId
//  （与 provider_keys 表行一一对应——表存元数据，Asset 存明文）；删服务商按池清
//  （removePoolKeys）。
// · 遗留 v2 服务商单 key（alias = 'aic.p.' + providerId）：只读迁移源——启动迁移
//  （ProviderKeyDb.migrateProviderKeyPools）把存量单 key 搬为池首条（k1）后删条目，幂等
//  （池无行且旧条目在才搬）。
// · 遗留 v1 单连接资产（alias = 'aicontrol.conn'）：只读——启动迁移
//  （ProviderDb.ensureProvidersMigrated）导入首服务商后不再触碰，资产不删（旧版 HAP
//   回滚后连接配置仍可用的零成本兜底）。
// · 第四形态 搜索引擎 API Key（'aic.se.' + engineId，单例按引擎分名）——saveSearchEngineKey 族。
// · 第五形态 代理密码（'aic.proxy.password'，单例）——saveProxyPassword 族。
// · 第六形态 HTTP 请求凭据（'aic.h.' + owner + '/' + credId，多条目）——saveHttpCredential 族。
// · 第八形态 S3 SecretAccessKey（'aic.s3.secret'，单例）——saveS3Secret 族。
// · 第九形态 MCP 请求头值（'aic.mcp.' + serverId + '.' + 头序号，一组多条目）——
//   saveMcpHeaderValues 族。
// · 第七形态不是 Asset：会话暂存密钥槽（文件尾）——用户「暂存」的密钥明文的**内存单槽**
//  （AppStorage 键，不 persistProp 不落任何盘面）；AI 配置工具 assign_key 从槽转运进
//   Asset（池条目），尾号掩码 keyHintOf 是明文唯一的随行形态。
// 注意：条目带 IS_PERSISTENT——卸载应用也保留（savePoolKey 注释）；清数据/恢复出厂仍会删。
// d.ts 存在 ≠ 真机可用（坑 71 教训）——M1 真机已验存取一条 key。
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
// MCP 头值组级重写的扫尾上限（第九形态——纯函数叶子，零 import 防环）
import { MCP_HEADERS_MAX } from '../McpText';

// 服务商 key 资产别名前缀（池条目再拼 providerId + '/' + keyId；短前缀控长——asset 别名
// 按字节计长，providerId 形如 'prov-<ts>-<seq>' 约 18 字节、keyId 约 20 字节，合计 ~48
// 字节，安全余量充足）
const PROVIDER_KEY_PREFIX: string = 'aic.p.';
// 遗留单连接资产别名（v1 形态，只读迁移源）
const ALIAS_TEXT: string = 'aicontrol.conn';
// asset 错误码：资产不存在（d.ts add/query 文档实锤）
const ERR_ASSET_NOT_FOUND: number = 24000002;

function encodeText(text: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(text);
}

function decodeText(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

function aliasQuery(alias: string): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, encodeText(alias));
  return query;
}

// 按别名删资产（不存在静默通过——幂等清理路径；其余错误上抛，禁静默失败）
async function removeByAlias(alias: string): Promise<void> {
  try {
    await asset.remove(aliasQuery(alias));
  } catch (e) {
    const biz = e as BusinessError;
    if (!(typeof biz.code === 'number' && biz.code === ERR_ASSET_NOT_FOUND)) {
      throw new Error('密钥资产删除失败：code ' + biz.code + ' ' + biz.message);
    }
  }
}

// 按别名读明文（不存在/字段残缺返回 ''——新建档/迁移中断的合法态，调用方按未配置处理）
async function querySecret(alias: string): Promise<string> {
  const query: asset.AssetMap = aliasQuery(alias);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  let results: asset.AssetMap[];
  try {
    results = await asset.query(query);
  } catch (e) {
    const biz = e as BusinessError;
    if (typeof biz.code === 'number' && biz.code === ERR_ASSET_NOT_FOUND) {
      return '';
    }
    throw new Error('密钥资产读取失败：code ' + biz.code + ' ' + biz.message);
  }
  if (results.length === 0) {
    return '';
  }
  const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
  if (secret === undefined) {
    return '';
  }
  return decodeText(secret as Uint8Array);
}

// ── 服务商 Key 池（v3 现役形态）──

// 保存池内一条 key（先删后加：update 对不存在资产同样报错，删加两调最简且幂等）。
// ★ IS_PERSISTENT（真机 Asset 丢失事故加固）：官方默认「卸载应用即删资产」，覆盖安装本
// 应保留但真机实测丢失——加持久属性后卸载也保留（重装同 alias 幂等覆盖；显式
// removePoolKey 删除不受影响）。权限代价 = ohos.permission.STORE_PERSISTENT_DATA
//（module.json5 已声明；SDK 实锤 normal 级 system_grant 开放权限，声明即授予无安装风险）
export async function savePoolKey(providerId: string, keyId: string, apiKey: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, encodeText(PROVIDER_KEY_PREFIX + providerId + '/' + keyId));
  attrs.set(asset.Tag.SECRET, encodeText(apiKey));
  attrs.set(asset.Tag.IS_PERSISTENT, true);
  await removePoolKey(providerId, keyId);
  await asset.add(attrs);
}

// 读取池内一条 key 明文；从未保存过返回 ''（条目与 DB 行同生命周期，正常不达）
export async function loadPoolKey(providerId: string, keyId: string): Promise<string> {
  return querySecret(PROVIDER_KEY_PREFIX + providerId + '/' + keyId);
}

// 删除池内一条 key（删条目时与 DB 行成对；不存在静默通过——幂等清理路径）
export async function removePoolKey(providerId: string, keyId: string): Promise<void> {
  await removeByAlias(PROVIDER_KEY_PREFIX + providerId + '/' + keyId);
}

// 按服务商清空池资产（删服务商级联；keyIds = 删库行前查得的池条目 id 集——Asset 无前缀
// 查询能力，按名逐条删）
export async function removePoolKeys(providerId: string, keyIds: string[]): Promise<void> {
  for (const keyId of keyIds) {
    await removePoolKey(providerId, keyId);
  }
}

// ── WebDAV 应用专用密码（单例条目，非池）──
// 对齐「明文最小化、凭据只进 Asset」政策：明文密码只进本条目，preferences 只留地址/账号/
// 目录三非敏感字段（DataSyncPage）；存量迁移在页面读链一次性完成（Asset 空且旧键非空才
// 触发），旧键即删。

// WebDAV 密码资产别名（单例——整应用仅一条 WebDAV 连接配置）
const DAV_PASSWORD_ALIAS: string = 'aic.dav.password';

// 保存 WebDAV 应用专用密码（先删后加同 savePoolKey；IS_PERSISTENT true = 跨卸载保留——
// 与 preferences 三非敏感字段寿命不同：重装后密码条目仍在而表单为空，重填保存即覆盖旧值，
// 无越权使用面）
export async function saveDavPassword(password: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, encodeText(DAV_PASSWORD_ALIAS));
  attrs.set(asset.Tag.SECRET, encodeText(password));
  attrs.set(asset.Tag.IS_PERSISTENT, true);
  await removeDavPassword();
  await asset.add(attrs);
}

// 读取 WebDAV 应用专用密码明文；未配置返回 ''
export async function loadDavPassword(): Promise<string> {
  return querySecret(DAV_PASSWORD_ALIAS);
}

// 删除 WebDAV 密码条目（清空密码保存时调用；不存在静默通过——幂等清理路径）
export async function removeDavPassword(): Promise<void> {
  await removeByAlias(DAV_PASSWORD_ALIAS);
}

// ── S3 对象存储 SecretAccessKey（单例条目；第八形态）──
// 形制对齐 WebDAV 密码（先删后加幂等 + IS_PERSISTENT + 明文禁入日志/toast/备份）；同为
// 备份通道凭据——恒不进包（通道凭据自指死锁，AppPreferencesBackup.ets 凭据登记块 #7），
// 换设备重填一次。Access Key ID 无独立认证面（无 Secret 不成凭据）随 s3_config 非敏感
// 偏好落盘。

// S3 SecretAccessKey 资产别名（单例——整应用仅一条 S3 连接配置）
const S3_SECRET_ALIAS: string = 'aic.s3.secret';

// 保存 S3 SecretAccessKey（先删后加同 saveDavPassword；IS_PERSISTENT true = 跨卸载保留——
// 重装后密钥条目仍在而表单为空，重填保存即覆盖旧值，无越权使用面）
export async function saveS3Secret(secret: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, encodeText(S3_SECRET_ALIAS));
  attrs.set(asset.Tag.SECRET, encodeText(secret));
  attrs.set(asset.Tag.IS_PERSISTENT, true);
  await removeS3Secret();
  await asset.add(attrs);
}

// 读取 S3 SecretAccessKey 明文；未配置返回 ''
export async function loadS3Secret(): Promise<string> {
  return querySecret(S3_SECRET_ALIAS);
}

// 删除 S3 SecretAccessKey 条目（清空密钥保存时调用；不存在静默通过——幂等清理路径）
export async function removeS3Secret(): Promise<void> {
  await removeByAlias(S3_SECRET_ALIAS);
}

// ── 搜索引擎 API Key（单例条目按引擎 id 分名；第四形态）──
// 形制对齐服务商 Key 池（先删后加幂等 + IS_PERSISTENT + 明文禁入日志/toast/导出）；差别 =
// 别名拼引擎 id 而非 providerId/keyId，且 UI 侧只存 hasKey 标记（偏好 JSON），明文永远只
// 进 Asset——同走「明文最小化、凭据只进 Asset」红线（balance_key 例外是 providers 表
// 明文列拍板，不适用本域）。

// 搜索引擎 key 资产别名前缀（拼引擎 id：'aic.se.' + 'bocha' ≈ 11 字节，余量充足）
const SEARCH_ENGINE_KEY_PREFIX: string = 'aic.se.';

// 保存引擎 API Key（先删后加同 savePoolKey；IS_PERSISTENT true = 卸载重装仍可用——
// 偏好侧 hasKey 标记与 baseUrl 卸载即清，重填即覆盖，无越权使用面）
export async function saveSearchEngineKey(engineId: string, apiKey: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, encodeText(SEARCH_ENGINE_KEY_PREFIX + engineId));
  attrs.set(asset.Tag.SECRET, encodeText(apiKey));
  attrs.set(asset.Tag.IS_PERSISTENT, true);
  await removeSearchEngineKey(engineId);
  await asset.add(attrs);
}

// 读取引擎 API Key 明文；未配置返回 ''
export async function loadSearchEngineKey(engineId: string): Promise<string> {
  return querySecret(SEARCH_ENGINE_KEY_PREFIX + engineId);
}

// 删除引擎 API Key 条目（「清除」键调用；不存在静默通过——幂等清理路径）
export async function removeSearchEngineKey(engineId: string): Promise<void> {
  await removeByAlias(SEARCH_ENGINE_KEY_PREFIX + engineId);
}

// ── 代理账号密码（单例条目；第五形态）──
// 形制对齐 WebDAV 密码（先删后加幂等 + IS_PERSISTENT + 明文禁入日志/toast/备份）；差别 =
// 账号（非敏感）落明文偏好 PREF_NET_PROXY_USER_KEY 随备份走，密码只进本条目（备份凭据
// 登记块 #5，AppPreferencesBackup.ets）。取值侧恒走 RequestIdentity 内存缓存
//（applyEffectiveProxy 同步取值，EntryAbility 启动预载 + 设置页写后同刷缓存），禁在请求链
// 上直接 await 本族——出站代理是同步单点收口，接异步读会拆散消费面。

// 代理密码资产别名（单例——整应用仅一份自定义代理配置）
const PROXY_PASSWORD_ALIAS: string = 'aic.proxy.password';

// 保存代理账号密码（先删后加同 saveDavPassword；IS_PERSISTENT true = 跨卸载保留——
// 卸载重装后密码条目仍在而偏好侧设置保留，语义一致）
export async function saveProxyPassword(password: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, encodeText(PROXY_PASSWORD_ALIAS));
  attrs.set(asset.Tag.SECRET, encodeText(password));
  attrs.set(asset.Tag.IS_PERSISTENT, true);
  await removeProxyPassword();
  await asset.add(attrs);
}

// 读取代理账号密码明文；未配置返回 ''
export async function loadProxyPassword(): Promise<string> {
  return querySecret(PROXY_PASSWORD_ALIAS);
}

// 删除代理密码条目（清空密码/「清除」键调用；不存在静默通过——幂等清理路径）
export async function removeProxyPassword(): Promise<void> {
  await removeByAlias(PROXY_PASSWORD_ALIAS);
}

// ── HTTP 请求凭据（多条目按 owner 分名；第六形态）──
// owner = 助手 id（助手私有凭据）或全局常量 HTTP_CRED_OWNER_GLOBAL（所有助手可引用；
// 同名冲突时助手级优先——解析在 HttpCredentials，本件不判）。credId = 凭据条目 id
//（UI 创建点生成后传入——KeyStore 不引 ChatDb，import 面最小）。形制对齐池条目：先删后
// 加幂等 + IS_PERSISTENT + 明文恒不进偏好/DB/日志/toast/卡面/回执（掩码显示）——元数据
//（名称/hasValue）只存偏好 JSON，模型以 {{名称}} 引用，注入链在
// common/providers/HttpCredentials.ets 与 ToolHttp，本件只管存取。

// 凭据资产别名前缀（再拼 owner + '/' + credId；owner 最长为助手 id 'asst-<13ts>-<seq>'
// 约 22 字节、credId 约 24 字节，合计 ~60 字节，余量充足）
const HTTP_CRED_PREFIX: string = 'aic.h.';

// 全局凭据命名空间 owner 常量（助手凭据 owner = 助手 id 本身，asst- 前缀与 'global'
// 永不撞名）
export const HTTP_CRED_OWNER_GLOBAL: string = 'global';

// 保存一条凭据（先删后加同 savePoolKey；IS_PERSISTENT true = 跨卸载保留——偏好侧元数据
// 卸载即清，重存同名即覆盖旧条目，无越权使用面〔同代理密码寿命语义〕）
export async function saveHttpCredential(owner: string, credId: string, value: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, encodeText(HTTP_CRED_PREFIX + owner + '/' + credId));
  attrs.set(asset.Tag.SECRET, encodeText(value));
  attrs.set(asset.Tag.IS_PERSISTENT, true);
  await removeHttpCredential(owner, credId);
  await asset.add(attrs);
}

// 读取一条凭据明文；从未保存过返回 ''（调用方按未配置处理）
export async function loadHttpCredential(owner: string, credId: string): Promise<string> {
  return querySecret(HTTP_CRED_PREFIX + owner + '/' + credId);
}

// 删除一条凭据（「删除」键调用；不存在静默通过——幂等清理路径）
export async function removeHttpCredential(owner: string, credId: string): Promise<void> {
  await removeByAlias(HTTP_CRED_PREFIX + owner + '/' + credId);
}

// ── MCP 服务器请求头值（一组多条目按头序号分名；第九形态）──
// 头序号 = headersJson 元数据数组的下标（0 起）：序号形别名依赖「整组先删后加重写」维持
// DB 元数据与 Asset 条目一致（保存链恒走组级重写，禁单条增删）；同名重复头靠序号不撞
// 条目。DB 行 headersJson 只存名称与 hasValue 标记，值明文纪律同池条目：禁日志/toast/
// 回执/lastError（lastError 只存摘要不含头值）——MCP 客户端现取现用（每次请求经本族读值
// 拼请求头，零落任何盘面）。

// MCP 头值资产别名前缀（再拼 serverId + '.' + 头序号；serverId 为 UUID 36 字节 + 序号 1
// 字节，前缀合计 ~46 字节，余量充足——池条目同款长度论证）
const MCP_HEADER_PREFIX: string = 'aic.mcp.';

function mcpHeaderAlias(serverId: string, index: number): string {
  return MCP_HEADER_PREFIX + serverId + '.' + index;
}

// 保存一组头值（组级**先删后加整组重写**——按 MCP_HEADERS_MAX 上限区间全扫删除〔不存在
// 静默通过，removeByAlias 幂等〕后逐条 add，免增量同步漂移；空值行跳过不建条目——
// 「不造假象」：Asset 里本就没有的明文，不添空记录）。调用方 = ChatDb.addMcpServer /
// editMcpServer（先本函数后 DB 行——「先 Asset 后 DB」写序，编排收口在 ChatDb 委托层）
export async function saveMcpHeaderValues(serverId: string, values: string[]): Promise<void> {
  await removeMcpHeaderValues(serverId, MCP_HEADERS_MAX);
  for (let i = 0; i < values.length && i < MCP_HEADERS_MAX; i++) {
    if (values[i] === '') {
      continue;
    }
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, encodeText(mcpHeaderAlias(serverId, i)));
    attrs.set(asset.Tag.SECRET, encodeText(values[i]));
    attrs.set(asset.Tag.IS_PERSISTENT, true);
    await asset.add(attrs);
  }
}

// 读一组头值（count = headersJson 元数据行数；按序返回等长数组，未存条目回 ''——
// 调用方按 hasValue 标记与 '' 判「值缺失」）。消费方 = ChatDb.loadMcpServerHeaderValues
// 委托口（B6 执行器拼请求头现取现用）
export async function loadMcpHeaderValues(serverId: string, count: number): Promise<string[]> {
  const values: string[] = [];
  for (let i = 0; i < count; i++) {
    values.push(await querySecret(mcpHeaderAlias(serverId, i)));
  }
  return values;
}

// 按组清头值条目（删服务器级联的 Asset 半段；不存在静默通过——幂等清理路径。
// count 传 MCP_HEADERS_MAX 即全区间扫删——删行前元数据已不可靠时用上限区间兜底）
export async function removeMcpHeaderValues(serverId: string, count: number): Promise<void> {
  for (let i = 0; i < count; i++) {
    await removeByAlias(mcpHeaderAlias(serverId, i));
  }
}

// ── 遗留资产（只读迁移源；写侧已随池化退役）──

// 读取遗留服务商单 key（v2 形态）；从未保存过返回 ''
export async function loadProviderKey(providerId: string): Promise<string> {
  return querySecret(PROVIDER_KEY_PREFIX + providerId);
}

// 删除遗留服务商单 key（池迁移完成后清条目用）
export async function removeProviderKey(providerId: string): Promise<void> {
  await removeByAlias(PROVIDER_KEY_PREFIX + providerId);
}

// 读取遗留连接配置（v1 形态）；从未保存过返回 null（asset.query 对不存在资产抛 24000002
// 而非返回空数组）
export interface LegacyConnection {
  baseUrl: string;
  apiKey: string;
  model: string;
}

export async function loadConnection(): Promise<LegacyConnection | null> {
  const query: asset.AssetMap = aliasQuery(ALIAS_TEXT);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  let results: asset.AssetMap[];
  try {
    results = await asset.query(query);
  } catch (e) {
    const biz = e as BusinessError;
    if (typeof biz.code === 'number' && biz.code === ERR_ASSET_NOT_FOUND) {
      return null;
    }
    throw new Error('连接配置读取失败：code ' + biz.code + ' ' + biz.message);
  }
  if (results.length === 0) {
    return null;
  }
  const first: asset.AssetMap = results[0];
  const secret: asset.Value | undefined = first.get(asset.Tag.SECRET);
  const baseUrl: asset.Value | undefined = first.get(asset.Tag.DATA_LABEL_NORMAL_1);
  const model: asset.Value | undefined = first.get(asset.Tag.DATA_LABEL_NORMAL_2);
  if (secret === undefined || baseUrl === undefined || model === undefined) {
    return null; // 字段残缺视为未配置（写入路径三字段同写，正常不可达）
  }
  const conn: LegacyConnection = {
    baseUrl: decodeText(baseUrl as Uint8Array),
    apiKey: decodeText(secret as Uint8Array),
    model: decodeText(model as Uint8Array)
  };
  return conn;
}

// ── 会话暂存密钥槽（第七形态）：**内存态非 Asset**——安全输入面板「暂存」的密钥明文的
// 会话内单槽，供 AI 配置工具 assign_key 读取并转运进 Asset（池条目）。寿命 = 当前会话页：
// 配出（assign_key 成功）或显示条 × 键即清；离开会话页由 ChatInputBar aboutToDisappear
// 清；重启即清（内存态，不 persistProp）。一次只暂存一条（决明拍板：无引用号牌体系、
// 不做囤积区——配了即进服务商密钥池 = 终态存放处，与手动重填同终态）。
// ★ 明文纪律：槽值零日志零 toast 零回执——回执/确认卡/显示条只带 keyHintOf 尾号掩码。

export const PENDING_KEY_SLOT_KEY: string = 'providerPendingKeySlot';

// 读暂存密钥明文；空槽返回 ''
export function getPendingKey(): string {
  return AppStorage.get<string>(PENDING_KEY_SLOT_KEY) ?? '';
}

// 写暂存密钥明文（安全输入面板「暂存」保存点——单槽覆盖写，重复粘贴即替换）
export function setPendingKey(value: string): void {
  AppStorage.setOrCreate(PENDING_KEY_SLOT_KEY, value);
}

// 清暂存槽（assign_key 成功 / 显示条 × 键 / 离开会话页三处调用）
export function clearPendingKey(): void {
  AppStorage.setOrCreate(PENDING_KEY_SLOT_KEY, '');
}

// 尾号掩码（纯函数——断言直跑）：trim 后 ≤8 字符全遮，否则「····」+ 尾 4 字符。
// 消费方 = 暂存显示条 / 发送说明句 / assign_key 确认卡与回执——明文永不随行
export function keyHintOf(plain: string): string {
  const v: string = plain.trim();
  if (v.length <= 8) {
    return '····';
  }
  return '····' + v.substring(v.length - 4);
}

// 发送说明句（纯函数——断言直跑）：暂存槽非空时随本轮 user 协议文本尾段（仅本轮随请求，
// 同附件语义历史轮不重发），让模型知道有待配密钥与可用动作；空槽返回 ''（零开销）。
// 文案面向模型不面向用户，不适用「面向用户文案写作规约」
export function composePendingKeyNote(raw: string): string {
  const v: string = raw.trim();
  if (v === '') {
    return '';
  }
  return '用户已通过输入区的「安全输入」暂存了一条密钥（尾号 ' + keyHintOf(v) +
    '），可用 manage_providers 的 assign_key 动作把它配置到指定服务商，配置成功后暂存自动清出。';
}
