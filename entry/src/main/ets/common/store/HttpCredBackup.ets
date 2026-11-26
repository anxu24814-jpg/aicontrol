// HTTP 凭据备份域：全量备份里凭据明文的
// 采集 / 解析 / 回填三段，自 ExportImport 拆出（宪法硬线规则——ExportImport 越 1200，
// 本次改动所属功能域先拆为独立文件；一句话职责 = 凭据明文随包进出）。
// 档位 = 备份凭据登记块 #6（AppPreferences.ets）：含密钥档连值进加密件（secrets.enc），
// 普通备份只带名称清单（偏好键 PREF_HTTP_CREDENTIALS_CFG_KEY，随 BACKUP_PREF_KEYS 走）；
// 明文永不进偏好/DB/日志。
// 时序口径与导出导入主链一致：采集在导出时（元数据 + Asset 现读）；回填在导入时**偏好与
// 各表全部落库之后**（命中判定 = 本机元数据存在该 (owner, credId) 才写——旧备份带着本机
// 已删条目时不产生 Asset 孤悬；本机已有明文不动，同引擎口径）。
import { getHttpCredentialsCfgJson } from '../AppPreferencesHttp';
import { HttpCredCfg, HttpCredEntry, invalidateCredCache,
  parseHttpCredCfg } from '../providers/HttpCredentials';
import { loadHttpCredential, saveHttpCredential } from './KeyStore';

// 密钥档载荷条目（owner = 助手 id 或 'global'；名称不在 secrets 里——名称清单随普通备份
// 的偏好键走，此处只按 (owner, credId) 补值）
export interface HttpCredSecretEntry {
  owner: string;
  credId: string;
  secret: string;
}

// 载荷解析（结构容错：非数组按空、条目残缺丢弃——完整性已由 GCM 认证保证，这里只防手改
// 与跨版本的形状漂移；旧备份无本字段 = 空数组，值留空等重填）
export function parseHttpCredSecrets(raw: Object | undefined): HttpCredSecretEntry[] {
  const out: HttpCredSecretEntry[] = [];
  if (!Array.isArray(raw)) {
    return out;
  }
  for (const item of raw as Object[]) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      continue;
    }
    const e: Record<string, Object> = item as Record<string, Object>;
    const owner: Object = e['owner'];
    const credId: Object = e['credId'];
    const secret: Object = e['secret'];
    if (typeof owner === 'string' && owner !== '' && typeof credId === 'string' &&
      credId !== '' && typeof secret === 'string' && secret !== '') {
      out.push({ owner: owner, credId: credId, secret: secret });
    }
  }
  return out;
}

// 采集（导出侧）：按元数据逐条读 Asset；空明文不建条目（不造假象——Asset 里本就没有的
// 明文，包里也不该多出一条空记录，同引擎口径）
export async function collectHttpCredSecrets(): Promise<HttpCredSecretEntry[]> {
  const out: HttpCredSecretEntry[] = [];
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const owners: string[] = [];
  cfg.forEach((_entries: HttpCredEntry[], owner: string): void => {
    owners.push(owner);
  });
  for (const owner of owners) {
    const entries: HttpCredEntry[] | undefined = cfg.get(owner);
    if (entries === undefined) {
      continue;
    }
    for (const e of entries) {
      const secret: string = await loadHttpCredential(owner, e.id);
      if (secret === '') {
        continue;
      }
      out.push({ owner: owner, credId: e.id, secret: secret });
    }
  }
  return out;
}

// 回填（导入侧，逐条容错——单条失败计数跳过不炸整批，与主链 O2 口径一致）：返回失败条数；
// 写过的 owner 逐一代价失效注入缓存（导入链在此收口，防链上读到旧值）
export async function applyHttpCredSecrets(entries: HttpCredSecretEntry[]): Promise<number> {
  let failures: number = 0;
  const touchedOwners: Set<string> = new Set<string>();
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  for (const c of entries) {
    const local: HttpCredEntry[] | undefined = cfg.get(c.owner);
    if (local === undefined ||
      !local.some((e: HttpCredEntry): boolean => e.id === c.credId)) {
      continue;
    }
    try {
      if ((await loadHttpCredential(c.owner, c.credId)) !== '') {
        continue;
      }
      await saveHttpCredential(c.owner, c.credId, c.secret);
    } catch (e) {
      failures++;
      continue;
    }
    touchedOwners.add(c.owner);
  }
  const owners: string[] = [];
  touchedOwners.forEach((owner: string): void => {
    owners.push(owner);
  });
  for (const owner of owners) {
    invalidateCredCache(owner);
  }
  return failures;
}
