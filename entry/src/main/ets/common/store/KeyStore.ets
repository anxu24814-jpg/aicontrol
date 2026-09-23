// API key 凭据层（2026-08-29 任务书 M1 新增；2026-08-30 服务商管理域扩容；同日多 Key 池
// v3 改制）：官方 Asset Store Kit（@ohos.security.asset，底层 HUKS 加密，专为密码/token
// 类短敏感数据设计）——任务书拍板：禁明文硬编码/明文 Preferences，key 不进代码不进 git，
// ★明文不进 DB/日志/toast（掩码显示）。
// ★ v3 三资产形态（2026-08-30 多 Key 池）：
// · 服务商 Key 池（现役）：一服务商多条，条目名 = 'aic.p.' + providerId + '/' + keyId
//   （与 provider_keys 表行一一对应——表存元数据，Asset 存明文）；删服务商时按池清
//   （removePoolKeys）。
// · 遗留服务商单 key（alias = 'aic.p.' + providerId，v2 形态）：只读迁移源——启动迁移
//   （ProviderKeyDb.migrateProviderKeyPools）把存量单 key 搬为池首条（k1）后删条目；
//   迁移幂等（池无行且旧条目在才搬）。
// · 遗留单连接资产（alias = 'aicontrol.conn'，v1 形态）：只读——启动迁移
//   （ProviderDb.ensureProvidersMigrated）导入首服务商后不再触碰，资产本身不删（旧版
//   HAP 回滚后连接配置仍可用，零成本兜底）。
// ★ 2026-09-10 多引擎一期第四形态：搜索引擎 API Key（alias = 'aic.se.' + engineId，
//   单例条目按引擎分名）——saveSearchEngineKey 族；与池条目同形制（先删后加幂等 +
//   IS_PERSISTENT），UI 侧只存 hasKey 标记（偏好 JSON），明文恒不落偏好/DB。
// 注意（规划稿已登记；2026-09-02 随 IS_PERSISTENT 加固修订）：池条目现带 IS_PERSISTENT——
// 卸载应用也保留（savePoolKey 注释）；清数据/恢复出厂仍会删。d.ts 存在 ≠ 真机可用
//（坑 71 教训）——M1 真机已验存取一条 key。
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

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

// 保存池内一条 key（先删后加：update 语义对不存在资产同样报错，删加两调最简且幂等）。
// ★ IS_PERSISTENT（2026-09-02 真机 Asset 丢失事故加固）：官方默认「卸载应用即删资产」，
// 覆盖安装本应保留但真机实测丢失（API 26 Beta2 疑似安装器行为）——加持久属性后卸载也
// 保留（重装同 alias 幂等覆盖；显式 removePoolKey 删除不受影响）。权限代价 =
// ohos.permission.STORE_PERSISTENT_DATA（module.json5 已声明；SDK PermissionDefinitions
// 实锤 normal 级 system_grant 开放权限，非受限开放——声明即授予无安装风险）
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

// ── WebDAV 应用专用密码（单例条目，非池；2026-09-03 观察⑪销项）──
// 对齐「明文最小化、凭据只进 Asset」政策：原存 webdav_config preferences 的明文密码迁入
// 本条目，preferences 只留地址/账号/目录三非敏感字段（DataSyncPage）；存量迁移在页面读链
// 一次性完成（Asset 空且旧键非空才触发），旧键即删。

// WebDAV 密码资产别名（单例——整应用仅一条 WebDAV 连接配置）
const DAV_PASSWORD_ALIAS: string = 'aic.dav.password';

// 保存 WebDAV 应用专用密码（先删后加同 savePoolKey；IS_PERSISTENT 与池条目同理 true =
// 跨卸载保留——preferences 三非敏感字段卸载即清，两者寿命不同：重装后密码条目仍在而
// 表单为空，重填地址保存即覆盖旧值，无越权使用面〔2026-09-04 自检轮注释勘误，原
// 「与 preferences 持久行为对齐」说法与两存储的实际持久性不符〕）
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

// ── 搜索引擎 API Key（单例条目按引擎 id 分名；2026-09-10 多引擎一期）──
// 形制对齐服务商 Key 池（先删后加幂等 + IS_PERSISTENT 跨卸载保留 + 明文禁入日志/toast/
// 导出）；与池条目的差别 = 别名拼引擎 id 而非 providerId/keyId，且 UI 侧只存 hasKey 标记
//（PREF_SEARCH_ENGINE_CFG_KEY JSON），明文永远只进 Asset——搜索 key 与聊天 key 同走
// 「明文最小化、凭据只进 Asset」红线（balance_key 例外是 providers 表明文列拍板，不适用
// 本域）。

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
