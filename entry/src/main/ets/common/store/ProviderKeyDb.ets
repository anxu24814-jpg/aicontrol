// 服务商 Key 池域存储层（2026-08-30 多 Key 池新建）：provider_keys 表行读写 + Asset 明文
// 成对编排 + 轮询指针。自 ProviderDb.ets 域级拆出（宪法 400 行红线——ProviderDb 347 行 +
// 池 CRUD 必超线；照 ProviderBalanceDb 先例，表结构/迁移在 ChatDbMigrate.ets，本文件复用
// sharedRdbStore 同一 DB 句柄，红线同源：ResultSet 用完 close / 行级查询天然有界）。
// ★ 安全红线：key 明文禁落 DB/日志/toast——表只存元数据（label 掩码显示名/启停/排序），
// 明文经 KeyStore 进 Asset（条目名 providerId+'/'+keyId，与本表行一一对应）。
// 语义：label 新建自动编号「Key N」（N = 现存末号最大值 + 1，删除后不重号；非「Key N」
// 形态的自定名不参与取号）；2026-08-31 起 label 可重命名（行内「更多」菜单 → InputDialog，
// renameProviderKey 单列 UPDATE 覆盖——每 key 恒只存一个名称无历史堆积；即时落库不经
// 详情页保存键，领导明示「命名改动不需要点保存也能记住」；启停自同日起改草稿态经保存键，
// 两语义不同源并存）；写序 = 先 Asset 后 DB 行（行插失败
// 时资产残留可被下次迁移幂等覆盖，反序会留「行在明文无」的假条目）；删序 = 先 Asset 后行。
// 轮询指针内存态（Map，重启从头——业界常态，拍板不持久化）。★ 2026-09-17 取钥方式：
// 指针只服务 rotate 模式；模式列 providers.key_pick_mode（DB v32）由 ProviderDb 读写，
// 起始位分派收口在本文件 nextPickStart（发送链唯一入口）
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { loadPoolKey, loadProviderKey, removePoolKey, removeProviderKey, savePoolKey } from './KeyStore';

const DOMAIN: number = 0xD5A3;
const TAG: string = 'ProviderKeyDb';

// provider_keys 行（表定义与列语义见 ChatDbMigrate.ets SQL_CREATE_PROVIDER_KEYS 注释）
export interface ProviderKeyRow {
  id: string;
  providerId: string;
  label: string;
  enabled: boolean;
  sortOrder: number;
  createdAt: number;
}

// 池条目全量查询（含停用行——Keys 面板全量展示带开关；sortOrder 升序、同序按创建先后，
// 与取钥顺序一致）
export async function queryProviderKeys(providerId: string): Promise<ProviderKeyRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_keys');
  predicates.equalTo('providerId', providerId);
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  const columns: string[] = ['id', 'providerId', 'label', 'enabled', 'sortOrder', 'createdAt'];
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, columns);
  const rows: ProviderKeyRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        label: result.getString(result.getColumnIndex('label')),
        enabled: result.getLong(result.getColumnIndex('enabled')) === 1,
        sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 启用条目 keyId 序（发送轮询取钥消费；空数组 = 池无可启用 key）
export async function queryEnabledKeyIds(providerId: string): Promise<string[]> {
  const rows: ProviderKeyRow[] = await queryProviderKeys(providerId);
  return rows.filter((row: ProviderKeyRow): boolean => row.enabled)
    .map((row: ProviderKeyRow): string => row.id);
}

// 池首启用 key 明文（获取模型/余额查询的兜底 key——拍板「专用值为空回退池首」；无启用
// 条目回 '' 由调用方按未配置处理）
export async function firstEnabledPoolKey(providerId: string): Promise<string> {
  const keyIds: string[] = await queryEnabledKeyIds(providerId);
  if (keyIds.length === 0) {
    return '';
  }
  return loadPoolKey(providerId, keyIds[0]);
}

// 现存 label 末号最大值（「Key N」自动编号用——删除后不重号；非编号 label 不参与取 max）
function maxLabelNumber(rows: ProviderKeyRow[]): number {
  let max: number = 0;
  for (const row of rows) {
    const tail: string = row.label.replace('Key ', '');
    const n: number = Number(tail);
    if (row.label.startsWith('Key ') && !Number.isNaN(n) && n > max) {
      max = n;
    }
  }
  return max;
}

// 添加 key（面板「添加 Key」链）：Asset 明文 + DB 行成对；label 自动「Key N」、排序追加
// 尾部、恒启用。返回新行（UI 重拉消费）。★ 2026-08-31 领导指令：池内禁止相同 key——
// 写入前逐支明文比对（加重复守卫；查重须读明文，属添加路径的必要读取面——低频用户
// 操作 + 池有界；缺明文支 '' 跳过；trim 后等值防空格差异漏判）
export async function insertProviderKey(providerId: string, plaintext: string): Promise<ProviderKeyRow> {
  const rows: ProviderKeyRow[] = await queryProviderKeys(providerId);
  const target: string = plaintext.trim();
  for (const row of rows) {
    const existing: string = (await loadPoolKey(providerId, row.id)).trim();
    if (existing !== '' && existing === target) {
      throw new Error('已存在相同 Key，禁止重复添加');
    }
  }
  let maxOrder: number = 0;
  for (const row of rows) {
    if (row.sortOrder > maxOrder) {
      maxOrder = row.sortOrder;
    }
  }
  const keyId: string = nextMessageId('pkey');
  await savePoolKey(providerId, keyId, plaintext);
  const row: ProviderKeyRow = {
    id: keyId,
    providerId: providerId,
    label: 'Key ' + (maxLabelNumber(rows) + 1),
    enabled: true,
    sortOrder: maxOrder + 1,
    createdAt: Date.now()
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'providerId': row.providerId, 'label': row.label,
    'enabled': 1, 'sortOrder': row.sortOrder, 'createdAt': row.createdAt
  };
  try {
    await sharedRdbStore().insert('provider_keys', bucket);
  } catch (e) {
    await removePoolKey(providerId, keyId); // 行插失败回滚资产，不留孤儿明文
    throw e as Error;
  }
  return row;
}

// 导入链专用（2026-09-02 配置导出导入域）：按导出包内元数据建行（label/启停/排序原样
// 保真——不走 insertProviderKey 的自动编号与恒启用语义，否则恢复出的池与备份不符）；
// plaintext 传 null/'' = 只建行不写 Asset——导出「不含密钥」档的合法承接，行落「明文缺失」
// 态由既有重填链兜底（2026-08-31 明文最小化交付，UI 已支持）。写序同 insertProviderKey：
// 先 Asset 后行（行插失败回滚资产防孤儿明文；Asset 写失败上抛中止——行未插，无残留）
export async function importPoolKeyRow(providerId: string, label: string, enabled: boolean,
  sortOrder: number, plaintext: string | null): Promise<void> {
  const keyId: string = nextMessageId('pkey');
  const hasSecret: boolean = plaintext !== null && plaintext !== '';
  if (hasSecret) {
    await savePoolKey(providerId, keyId, plaintext as string);
  }
  const bucket: relationalStore.ValuesBucket = {
    'id': keyId, 'providerId': providerId, 'label': label,
    'enabled': enabled ? 1 : 0, 'sortOrder': sortOrder, 'createdAt': Date.now()
  };
  try {
    await sharedRdbStore().insert('provider_keys', bucket);
  } catch (e) {
    if (hasSecret) {
      await removePoolKey(providerId, keyId);
    }
    throw e as Error;
  }
}

// 启停（即时落库；停用 = 不参与轮询与兜底取钥；2026-08-31 起面板侧改草稿态经详情页
// 保存键统一落库——本函数消费方 = ProviderToggleDraft.flush 与本文件内语义不变）
export async function setProviderKeyEnabled(keyId: string, enabled: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_keys');
  predicates.equalTo('id', keyId);
  await sharedRdbStore().update(bucket, predicates);
}

// 重命名（2026-08-31 新增）：label 单列 UPDATE 覆盖——每 key 恒只存一个名称，改名即
// 覆盖旧名，无历史行/历史列堆积；即时落库（资源元数据，不经详情页保存键——领导明示
// 「命名改动不需要点保存也能记住」）；0 行更新抛错（行已删的「已重命名」假成功拦截，
// P0-1——updateTemplate 先例）；Asset 明文与名称无关零触碰。调用方改后 reload 重拉
//（ForEach 键含 label → 行重建显示新名）。
export async function renameProviderKey(keyId: string, label: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'label': label };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_keys');
  predicates.equalTo('id', keyId);
  const affected: number = await sharedRdbStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('密钥不存在或已删除');
  }
}

// 删除条目：先 Asset 后行（反序会留「行在明文无」假条目；Asset 删失败上抛，行留给重试）
export async function deleteProviderKey(providerId: string, keyId: string): Promise<void> {
  await removePoolKey(providerId, keyId);
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_keys');
  predicates.equalTo('id', keyId);
  await sharedRdbStore().delete(predicates);
}

// ── 轮询指针（内存态；重启从头——拍板）──

const rotationPointers: Map<string, number> = new Map();

// 取本次发送的起始下标（0..enabledCount-1）并步进指针：每服务商独立轮转，重启归零；
// enabledCount ≤ 0 恒 0（调用方守卫空池）
export function nextRotationStart(providerId: string, enabledCount: number): number {
  if (enabledCount <= 0) {
    return 0;
  }
  const ptr: number = rotationPointers.get(providerId) ?? 0;
  rotationPointers.set(providerId, ptr + 1);
  return ptr % enabledCount;
}

// ── 取钥方式（2026-09-17；DB v32 providers.key_pick_mode）──

// 模式值域（单一来源：列 DEFAULT / 读侧钳位 / UI 两项标签 / 发送链分派四处共用，禁散写字面量；
// 迁移 SQL 里的一处 DEFAULT 字面量是 SQL 文本内的唯一例外）
export const KEY_PICK_ROTATE: string = 'rotate';
export const KEY_PICK_RANDOM: string = 'random';

// 起始位选择（发送轮次唯一入口，模式分派在此收口）：
// · rotate = 轮转指针（每服务商独立、重启归零——原行为逐字节不变）；
// · random = 每次发送均匀随机挑一支起始（不消费也不推进指针——指针只归 rotate 用）；
// · 其余值（未写/脏写/旧连接对象缺字段）= 按 rotate 兜底（存量语义不打折，P0-1 不静默变语义）。
// 两种模式下「一轮内不重用」的环绕尝试序都由调用侧自 start 展开，本函数只管起始位
export function nextPickStart(mode: string, providerId: string, enabledCount: number): number {
  if (enabledCount <= 0) {
    return 0;
  }
  if (mode === KEY_PICK_RANDOM) {
    return Math.floor(Math.random() * enabledCount);
  }
  return nextRotationStart(providerId, enabledCount);
}

// ── 迁移（启动一次性，EntryAbility 在 initChatDb 后编排）──

// 池无行时搬入首条（固定 keyId 'k1' / label 'Key 1' / 排序 1——任务书拍板形态）；池已有
// 行返回 false 不动（幂等守卫）。供两条迁移链共用：v2 单 key 资产搬运（本文件）与
// v1 单连接导入首服务商（ProviderDb.ensureProvidersMigrated）
export async function seedPoolKey(providerId: string, plaintext: string): Promise<boolean> {
  if (plaintext === '') {
    return false;
  }
  const rows: ProviderKeyRow[] = await queryProviderKeys(providerId);
  if (rows.length > 0) {
    return false;
  }
  await savePoolKey(providerId, 'k1', plaintext);
  const bucket: relationalStore.ValuesBucket = {
    'id': 'k1', 'providerId': providerId, 'label': 'Key 1',
    'enabled': 1, 'sortOrder': 1, 'createdAt': Date.now()
  };
  try {
    await sharedRdbStore().insert('provider_keys', bucket);
  } catch (e) {
    await removePoolKey(providerId, 'k1');
    throw e as Error;
  }
  return true;
}

// v2 单 key 资产 → 池首条目搬运（逐服务商：池无行且旧资产在才搬，迁后删旧条目——任务书
// 拍板幂等形态）。失败按家打日志不阻断启动（下次启动重试；资产删失败残留 = 无消费方的
// 无害孤儿）。provider 清单走 querySql 直查（避免回引 ProviderDb 成环）
export async function migrateProviderKeyPools(): Promise<void> {
  try {
    const result: relationalStore.ResultSet = await sharedRdbStore()
      .querySql('SELECT id FROM providers');
    const ids: string[] = [];
    try {
      while (result.goToNextRow()) {
        ids.push(result.getString(result.getColumnIndex('id')));
      }
    } finally {
      result.close();
    }
    for (const id of ids) {
      try {
        const legacy: string = await loadProviderKey(id);
        if (legacy === '') {
          continue;
        }
        if (await seedPoolKey(id, legacy)) {
          await removeProviderKey(id);
          hilog.info(DOMAIN, TAG, '单 key 已迁移为池首条：%{public}s', id);
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'key 池迁移失败（下次启动重试）：%{public}s', (e as Error).message);
      }
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'key 池迁移清单查询失败：%{public}s', (e as Error).message);
  }
}
