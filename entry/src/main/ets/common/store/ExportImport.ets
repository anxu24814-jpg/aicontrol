// 全量导出域（蓝本 = chatcube MIT 快照 ImportExportService 分域 manifest + ZIP 结构，
// 裁剪至 aicontrol 形态）。★ C2 拆分：「导入 + 密钥回填」全域已整块外迁同目录
// ExportImportApply.ets（方法体逐字搬迁）；本件留导出链 + 接口区 + 双侧共用面（下述带
// export 的共用件由彼件单向 import，本件不 import 彼件，无环）。
// · 导出：EXPORT_TABLES 全行 → 分域 JSON（manifest + 各表文件 + 偏好分域）→ zlib 打包
//   zip 落 cacheDir（用完即删——数据有界）。manifest 校验闸门在导入侧（Cube 原版读而
//   不校验的坑，本项目补上）；冲突策略两态：skip = 合并；overwrite = INSERT OR
//   REPLACE 同 id 整行替换（恢复语义）。
// · 通用行序列化：PRAGMA table_info 判列型（ResultSet 无 columnType API——d.ts 实查），
//   导入按目标表现存列过滤（跨版本前向/后向兼容，多列少列都不炸）。
// · 偏好分域：zip 根 preferences.json = [{key,type,value}]，键清单 =
//   AppPreferencesBackup.BACKUP_PREF_KEYS（两分类表唯一来源，指表不记数防漂移）；不进
//   备份的键见 BACKUP_EXCLUDED_PREF_KEYS；导入按冲突策略决定动不动——overwrite 覆盖、
//   skip 保持本机现值（拍板），老备份无该文件走缺失容忍 continue。
// · 凭据两档产物：不含密钥档 = providers 三个明文敏感列（balance_key / balance_headers /
//   headers）置空；含密钥档 = 额外写 secrets.enc（加密件，内含 Key 池明文 + 搜索引擎密钥
//   + 上述三列）。★ 两个档位的 providers.json 都置空——明文只进 Asset 与加密件，裸明文
//   落盘的产物形态不存在。加密件走 ProviderShare 的 serialize/openEncryptedContainer
//  （PBKDF2 + AES-GCM 单一来源），本域不做第二套加密。WebDAV 密码恒不进包（通道凭据
//   自指死锁）。
// · hasKey 对账：导入偏好后按**本机 Asset 真值**回填搜索引擎 hasKey——同设备恢复显示
//  「已配置」且为真、换设备自然「未配置」，两边自动正确且用户零重填。
// · Key 明文边界：Key 池明文恒只在 Asset，DB 仅存元数据——不含密钥档导入后需重填（同
//   设备因 Asset IS_PERSISTENT 天然还在，多数场景无需重填）；含密钥档可跨设备带走明文。
// · 附件边界：message_attachments 不进 EXPORT_TABLES——附件元数据不与文件本体分头行动
//  （备份带行不带文件 = 恢复后一排点不开的条目）。★ 后置时序约束：将来导出带附件时，
//   覆盖导入的附件清理必须发生在「写入导入的附件行」之前，或清理只针对「本机有、备份
//   无」的行——否则会把刚导入的行一起删掉。overwrite 现口径 = 被覆盖消息回到备份当时
//   状态，本机附件行与文件随之作废（skip 路径零触碰）；导入成功后跑一次库盘收敛兜底。
// · 沿革：
// v38（2026-09-21 世界书知识库）+ knowledge_books / knowledge_entries（依赖序书在前、
//   条目在后，两表都不随其他表级联）；v43 再增 knowledge_files 条目附件件。
// 层位：common/store（rdb 依赖 + 被 UI 页消费）；刷新链由页面层负责，本域只管数据面。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore } from './ChatDb';
import { loadPoolKey, loadSearchEngineKey } from './KeyStore';
import { collectHttpCredSecrets, HttpCredSecretEntry } from './HttpCredBackup';
import { serializeEncryptedContainer } from './ProviderShare';
import { collectGraphDomain, GraphBackupConversation } from './GraphTransfer';
import { SEARCH_ENGINES } from '../search/SearchEngineRegistry';
import { collectBackupPrefItems, serializePrefBackup } from '../AppPreferencesBackup';
import { AI_NOTICE_FILE_NAME, aiNoticeFileText } from '../AiDisclosure';

// 格式版本（manifest.schemaVersion；写入恒用当前值，读取见 ACCEPTED_SCHEMA_VERSIONS）。
// 3 = 带图域分域 graph.json（graph 会话分支树/节点图列/runs/facts/bindings/refs——线性表
// SELECT * 的 NULL→0/'' 归一会破坏 parentMessageId 根语义与 seq/coversToSeq 可空语义，
// 故图侧单列分域、可空字段以 JSON null 保真）；采集与导入后处理 = GraphTransfer 同名
// 函数（域级拆分落位彼件）。演进史 1 无偏好域 → 2 +偏好+密钥档 → 3 +图域，读取口径
// 随 legacy 退役收口为仅 {3}（旧程序读 3 = 其自身闸门拒绝并提示升级，新格式不被旧程序
// 静默扁平化）
const SCHEMA_VERSION: number = 3;
// ★ 读取收口仅 {3}——格式 1/2（无图域老包）随 legacy 退役拒收（决明拍板「拒收，不再
// 支持；WebDAV 云端旧档同口径拒收，文案诚实告知」；本机与 WebDAV 两路同生效，单入口
// importFromZip；拒收 + 提示「用旧版本应用重新导出」是诚实路径）。归一段已退役删除
//（非 graph 自然呈墓碑，M4 下等价），S5 purge 覆盖清理仍在
const ACCEPTED_SCHEMA_VERSIONS: number[] = [3];
// 导出的表（导入顺序 = 依赖序：先服务商域后业务域；无外键约束但 id 引用语义有向）。
// 逐表登记（域内清单：文首逐表登记 + 导入侧按 EXPORT_TABLES 遍历）：
// · token_usage_events = 用量账本（按现存列过滤天然兼容）；
// · memories = 跨会话长期记忆（assistantId 引用已删助手 = 弱链显示侧兜底，不阻导入）；
// · skills → skill_files = 技能库与技能附件文件（用户资产随备份走；级联语义：行由
//   skillId 指向 skills，依赖序技能在前附件在后，两表不随任何其他表级联）；
// · assistant_memories = 助手级记忆库（与 memories 同待遇；memories 之后导入，独立表
//   无跨表引用）；
// · knowledge_books → knowledge_entries → knowledge_files = 知识库/条目/条目附件（用户
//   手写资产；级联语义：逐级依赖书→条目→附件，均不随其他表级联；助手行 knowledge
//   启用列只是弱链 id 集，导入不校验引用完整性）；
// · mcp_servers = MCP 服务器配置库（用户搭建资产；导入位置在 assistants 之前——服务器
//   库先恢复、助手 mcpServers 绑定列后到，弱链不校验引用完整性。★ 头值明文**不随备份**
//  （Asset 分流，对齐 HTTP 凭据先例）；headersJson 只带名称与 hasValue 标记，新设备
//   导入后编辑态按 hasValue 提示「值缺失，请填入新值」）。
// 旧备份缺任一分域文件 = 缺失容忍 continue 不炸，恢复后对应域为空零报错。
// ★ C2 拆分起出口 export——导出遍历 + 导入遍历双侧共用（域外零消费者守面 =
// assert-skill-domain 78 组改判）。清单规模改动须同笔核 scripts/assert-ui-shape.mjs ㊽
// 组导出清单关系钉（表名须为 ChatDbSchema 真实建表对象——关系形态：加表零改钉、真失
// 步恰红）。
export const EXPORT_TABLES: string[] = ['providers', 'provider_models', 'provider_keys',
  'prompt_templates', 'mcp_servers', 'assistants', 'conversations', 'messages',
  'token_usage_events', 'memories', 'assistant_memories', 'skills', 'skill_files',
  'knowledge_books', 'knowledge_entries', 'knowledge_files'];

// 偏好分域文件名（zip 根；C2 起双侧共用 export）
export const PREF_FILE_NAME: string = 'preferences.json';
// 图域分域文件名（zip 根；格式 3 起，见 SCHEMA_VERSION 注释；C2 起双侧共用）
export const GRAPH_FILE_NAME: string = 'graph.json';
// 密钥档文件名（zip 根；仅含密钥档产出——ProviderShare 加密容器；C2 起双侧共用）
export const SECRETS_FILE_NAME: string = 'secrets.enc';
// providers 三个明文敏感列（凭据 #3；建表 SQL = ChatDbMigrate.ets）——两档产物都置空
const SENSITIVE_PROVIDER_COLUMNS: string[] = ['balance_key', 'balance_headers', 'headers'];

// 备份格式版本闸门（纯函数，node 断言直跑）：写入恒 SCHEMA_VERSION，读取接受
// ACCEPTED_SCHEMA_VERSIONS 全集
export function isAcceptedBackupVersion(version: number | undefined): boolean {
  return version !== undefined && ACCEPTED_SCHEMA_VERSIONS.includes(version);
}

// 敏感列置空（导出侧对 providers 行**恒**调用——明文只进 Asset 与加密件；含密钥档的
// 真值已先行采集进 BackupSecrets）。原地改行对象（调用方紧接着写 providers.json）
export function blankSensitiveProviderColumns(rows: Record<string, Object>[]): void {
  for (const row of rows) {
    for (const col of SENSITIVE_PROVIDER_COLUMNS) {
      row[col] = '';
    }
  }
}

// ── 密钥档载荷（secrets.enc 解密后的 JSON 形态）──
// 三处凭据明文（服务商池 / 引擎 / 余额与请求头三列）——结构与采集/回填两侧共用；
// 空明文一律不建条目（不造假象：Asset 里本就没有的明文，包里也不该多出一条空记录）
export interface KeySecretEntry {
  keyId: string;
  secret: string;
}

export interface ProviderSecretEntry {
  providerId: string;
  balanceKey: string;
  balanceHeaders: string;
  headers: string;
  keys: KeySecretEntry[];
}

export interface EngineSecretEntry {
  engineId: string;
  secret: string;
}

export interface BackupSecrets {
  providers: ProviderSecretEntry[];
  engines: EngineSecretEntry[];
  httpCredentials: HttpCredSecretEntry[];
}

// 导出摘要（UI 呈报用）
export interface ExportSummary {
  path: string; // zip 产物绝对路径（cacheDir）
  fileName: string;
  counts: Record<string, number>; // 表名 → 行数
  totalRows: number;
}

// 导入冲突策略（B2 两态）：skip = 合并（冲突跳过，现状）；overwrite = 同 id 整行替换
export type ImportStrategy = 'skip' | 'overwrite';

// 导入摘要（UI 呈报用）
export interface ImportSummary {
  imported: Record<string, number>; // 表名 → 新增行数
  // 表名 → id 冲突按 skip 策略跳过行数——只表策略跳过；行级失败另账 rowFailures，
  // 绝不回流本字段
  skipped: Record<string, number>;
  totalImported: number;
  totalSkipped: number;
  overwritten: Record<string, number>; // 表名 → 覆盖替换行数（skip 态恒 0）
  totalOverwritten: number; // 覆盖总数（skip 态恒 0）
  // 表名 → 行级失败条数（转换异常 / 不可导入行〔names 空〕/ 写入被拒〔含覆盖消息单条
  // 提交单元回滚〕）——与 skipped 严格分账，一行失败只进这本账
  rowFailures: Record<string, number>;
  totalRowFailures: number; // 行级失败总数（UI「部分数据未导入」分档依据）
  // 恢复的偏好项数：overwrite 态 = 实际写入条数（键未注册/类型不符被跳过不计）；skip
  // 态与老备份（无偏好分域）恒 0（skip = 偏好不动）
  prefCount: number;
  // 密钥档逐条回填失败条数（此时表数据与偏好已照常恢复，仅密钥未写入——Asset/RDB 单条
  // 失败不炸整批）；不含密钥档与全成恒 0，UI 据此分档呈报
  secretFailures: number;
  // 表 JSON「文件在但解析失败/非数组」的表名清单——损坏分域须对用户可见（此前静默
  // continue 曾致误当「备份里本来就没有」），UI 据此如实呈报
  parseFailed: string[];
  // 图域逐会话导入失败的会话数（单会话失败跳过不炸整批；UI 据此如实分档，同
  // parseFailed 口径）；全成恒 0
  graphFailedSessions: number;
}

// ── 通用行序列化（PRAGMA 列型驱动）──

// C2 起双侧共用 export（导出侧读表 + 导入侧列过滤均消费）
export interface ColumnInfo {
  name: string;
  type: string; // 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB' | 其他
}

// 列信息读取（PRAGMA table_info——迁移域 columnExists 同数据源；cid/name/type/notnull...）
export async function tableColumns(rdb: relationalStore.RdbStore, table: string): Promise<ColumnInfo[]> {
  const cols: ColumnInfo[] = [];
  const rs: relationalStore.ResultSet = await rdb.querySql(`PRAGMA table_info(${table})`);
  try {
    while (rs.goToNextRow()) {
      const name: string = rs.getString(rs.getColumnIndex('name'));
      let type: string = rs.getString(rs.getColumnIndex('type')).toUpperCase();
      if (type.indexOf('INT') >= 0) {
        type = 'INTEGER';
      } else if (type.indexOf('CHAR') >= 0 || type.indexOf('CLOB') >= 0 || type.indexOf('TEXT') >= 0) {
        type = 'TEXT';
      } else if (type.indexOf('REAL') >= 0 || type.indexOf('FLOA') >= 0 || type.indexOf('DOUB') >= 0) {
        type = 'REAL';
      }
      cols.push({ name: name, type: type });
    }
  } finally {
    rs.close();
  }
  return cols;
}

// 行 → JSON 对象（列型分派 getter；NULL → ''/0 归一——ArkTS Record 值域 Object，空值
// 用类型默认值保真）
async function readTableRows(rdb: relationalStore.RdbStore, table: string,
  cols: ColumnInfo[]): Promise<Record<string, Object>[]> {
  const rows: Record<string, Object>[] = [];
  const rs: relationalStore.ResultSet = await rdb.querySql(`SELECT * FROM ${table}`);
  try {
    while (rs.goToNextRow()) {
      const row: Record<string, Object> = {};
      for (const col of cols) {
        const idx: number = rs.getColumnIndex(col.name);
        if (rs.isColumnNull(idx)) {
          row[col.name] = col.type === 'INTEGER' || col.type === 'REAL' ? 0 : '';
        } else if (col.type === 'INTEGER') {
          row[col.name] = rs.getLong(idx);
        } else if (col.type === 'REAL') {
          row[col.name] = rs.getDouble(idx);
        } else {
          row[col.name] = rs.getString(idx);
        }
      }
      rows.push(row);
    }
  } finally {
    rs.close();
  }
  return rows;
}

// ── 导出 ──

// 全量导出：EXPORT_TABLES 各表 + 偏好分域 → 分域 JSON → zip。产物 = {cacheDir}/
// aicontrol_export_{ts}/aicontrol_backup_{ts}.zip（目录临时驻留——调用方用后
// cleanupExportDir 清删，防中断残留半成品）。includeSecrets = 含密钥档（额外产
// secrets.enc 加密件，passphrase 必填非空）；两档的 providers.json 都置空三列敏感明文。
export async function exportAllData(ctx: common.Context, includeSecrets: boolean,
  passphrase: string): Promise<ExportSummary> {
  const rdb: relationalStore.RdbStore = sharedRdbStore();
  const stamp: string = exportStamp();
  const dir: string = ctx.cacheDir + `/aicontrol_export_${stamp}`;
  fs.mkdirSync(dir, true);
  const counts: Record<string, number> = {};
  let totalRows: number = 0;
  // 密钥档载荷（含密钥档逐表采集，循环后统一加密落盘——内存缓冲用完即弃）
  const secrets: BackupSecrets = { providers: [], engines: [], httpCredentials: [] };
  try {
    // manifest
    let manifest = '{';
    manifest += `"schemaVersion":${SCHEMA_VERSION},`;
    manifest += `"app":"aicontrol",`;
    manifest += `"exportedAt":${Date.now()},`;
    manifest += '"tables":{';
    for (let i = 0; i < EXPORT_TABLES.length; i++) {
      const table: string = EXPORT_TABLES[i];
      const cols: ColumnInfo[] = await tableColumns(rdb, table);
      const rows: Record<string, Object>[] = await readTableRows(rdb, table, cols);
      // 凭据处置（★ 先采集后置空——明文只进加密件，两个档位的 providers.json 都不带）
      if (table === 'providers') {
        if (includeSecrets) {
          collectProviderSecrets(rows, secrets);
        }
        blankSensitiveProviderColumns(rows);
      }
      if (table === 'provider_keys' && includeSecrets) {
        await collectPoolSecrets(rows, secrets);
      }
      counts[table] = rows.length;
      totalRows += rows.length;
      const jsonFile: string = `${dir}/${table}.json`;
      writeFileText(jsonFile, JSON.stringify(rows));
      if (i > 0) {
        manifest += ',';
      }
      manifest += `"${table}":${rows.length}`;
    }
    manifest += `},"dbVersion":${rdb.version}}`;
    writeFileText(`${dir}/manifest.json`, manifest);
    // 图域分域（格式 3 起）：graph 会话逐会话采集（分支树/节点/可空字段 null 保真）；
    // 一致性口径 = 与既有全量表导出同一时点近似（无总事务，与既有形态一致，登记）
    if (SCHEMA_VERSION >= 3) {
      const graphConvs: GraphBackupConversation[] = await collectGraphDomain(rdb);
      writeFileText(`${dir}/${GRAPH_FILE_NAME}`, JSON.stringify(graphConvs));
      counts['graph_conversations'] = graphConvs.length;
    }
    // 偏好分域（★ 恒写：不含密钥档也要带偏好；键清单 = AppPreferencesBackup 两分类表）
    writeFileText(`${dir}/${PREF_FILE_NAME}`, serializePrefBackup(collectBackupPrefItems()));
    // AI 显式标识随包（备份含助手回复 = 导出场景，文案源 = common/AiDisclosure）；
    // 导入侧只按已知表名读 JSON——本文件不参与恢复，双向兼容
    writeFileText(`${dir}/${AI_NOTICE_FILE_NAME}`, aiNoticeFileText());
    // 密钥档加密件（仅含密钥档；口令由调用方收齐——空口令在 UI 侧已被拦，此处再兜一道）
    if (includeSecrets) {
      if (passphrase === '') {
        throw new Error('含密钥的备份必须设置口令');
      }
      await collectEngineSecrets(secrets);
      secrets.httpCredentials = await collectHttpCredSecrets();
      writeFileText(`${dir}/${SECRETS_FILE_NAME}`,
        await serializeEncryptedContainer(secrets, SCHEMA_VERSION, passphrase));
    }
    // 打包（★ 用 compressFile 整目录打包——compressFiles 绝对路径列表的 zip 条目名形态
    // 未文档化，若带目录层级则解压平铺读取失败 = 恢复链路整体坏；配套导入侧
    // locateDecompressRoot 双形态防御）
    const zipPath: string = `${ctx.cacheDir}/aicontrol_backup_${stamp}.zip`;
    await zlib.compressFile(dir, zipPath, {});
    return {
      path: zipPath, fileName: `aicontrol_backup_${stamp}.zip`,
      counts: counts, totalRows: totalRows
    };
  } catch (e) {
    cleanupDir(dir);
    throw e as Error;
  }
}

// ── 密钥档采集（导出侧；三列与池明文来自 DB 行 + Asset，空明文一律不建条目）──

// 行单元格文本（JSON 行值域 Object；非字符串按空处理——列型错配防御；C2 起双侧共用
// export——采集侧与 parseBackupSecrets 均消费）
export function rowText(v: Object | undefined): string {
  return typeof v === 'string' ? v as string : '';
}

function collectProviderSecrets(rows: Record<string, Object>[], secrets: BackupSecrets): void {
  for (const row of rows) {
    const providerId: string = rowText(row['id']);
    if (providerId === '') {
      continue;
    }
    const balanceKey: string = rowText(row['balance_key']);
    const balanceHeaders: string = rowText(row['balance_headers']);
    const headers: string = rowText(row['headers']);
    if (balanceKey === '' && balanceHeaders === '' && headers === '') {
      continue; // 三列全空 = 无明文可带（池明文由 provider_keys 行另行补入并就地建条目）
    }
    secrets.providers.push({
      providerId: providerId, balanceKey: balanceKey, balanceHeaders: balanceHeaders,
      headers: headers, keys: []
    });
  }
}

// 池明文采集（Asset 逐条读——KeyStore 单条 API 直用，不另造批量壳）；明文缺失
//（Asset 丢失/从未保存）跳过不造假象
async function collectPoolSecrets(rows: Record<string, Object>[],
  secrets: BackupSecrets): Promise<void> {
  for (const row of rows) {
    const providerId: string = rowText(row['providerId']);
    const keyId: string = rowText(row['id']);
    if (providerId === '' || keyId === '') {
      continue;
    }
    const secret: string = await loadPoolKey(providerId, keyId);
    if (secret === '') {
      continue;
    }
    secretEntryOf(secrets, providerId).keys.push({ keyId: keyId, secret: secret });
  }
}

// 引擎明文采集（需 key 引擎逐条读 Asset——四家封顶的有界循环）
async function collectEngineSecrets(secrets: BackupSecrets): Promise<void> {
  for (const engine of SEARCH_ENGINES) {
    if (!engine.requiresApiKey) {
      continue;
    }
    const secret: string = await loadSearchEngineKey(engine.id);
    if (secret === '') {
      continue;
    }
    secrets.engines.push({ engineId: engine.id, secret: secret });
  }
}

// 取服务商秘密条目（无则就地建空条目再返回——池明文可能先于余额三列落条目）
function secretEntryOf(secrets: BackupSecrets, providerId: string): ProviderSecretEntry {
  const found: ProviderSecretEntry | undefined = secrets.providers.find(
    (e: ProviderSecretEntry): boolean => e.providerId === providerId);
  if (found !== undefined) {
    return found;
  }
  const created: ProviderSecretEntry = {
    providerId: providerId, balanceKey: '', balanceHeaders: '', headers: '', keys: []
  };
  secrets.providers.push(created);
  return created;
}

// 导出临时目录清删（zip 已成 / 导出失败两路调用——数据有界）
export function cleanupExportDir(ctx: common.Context, stamp: string): void {
  cleanupDir(`${ctx.cacheDir}/aicontrol_export_${stamp}`);
}

// 启动兜底清扫（cacheDir 内 export/import/xlsx 前缀的残留目录与 zip——crash/进程中断
// 残留；EntryAbility onCreate 调一次；正常路径成败两路均自清，本清单兜底，数据有界
// 红线；单文件失败跳过下次再清）。★ 清理按 statSync 分流：目录走 cleanupDir、文件走
// unlinkSync（zip 文件路径进 cleanupDir 的 listFileSync 会抛错被静默吞——文件型残留
// 曾因此从未被删）
export function sweepExportTemp(ctx: common.Context): void {
  try {
    for (const name of fs.listFileSync(ctx.cacheDir)) {
      // ★ DS 历史导入族（自检轮补）：ds_import_<时间戳> 解压目录与 ds_import_upload_tmp.zip
      // 在导入中途杀进程时无人释放（最大 512MB 解压目录），此前不在白名单 = 「重启自清」
      // 注释不成立；补前缀后目录走 cleanupDir、文件走 unlink 分流同款处置
      if (!(name.startsWith('aicontrol_export_') || name.startsWith('aicontrol_backup_') ||
        name.startsWith('webdav_download_') || name.startsWith('aicontrol_import_') ||
        name.startsWith('import_upload_tmp') || name.startsWith('xlsx_build_') ||
        name.startsWith('ds_import_'))) {
        continue;
      }
      const path: string = `${ctx.cacheDir}/${name}`;
      try {
        if (fs.statSync(path).isDirectory()) {
          cleanupDir(path);
        } else {
          fs.unlinkSync(path);
        }
      } catch (e) {
        // 单文件失败跳过（下次启动再清）
      }
    }
  } catch (e) {
    // cacheDir 不可列 = 环境异常，静默（下次启动再试）
  }
}

// 递归删目录树（★ 必须递归——只删顶层条目时嵌套子树〔如 xlsx_build_ 暂存目录〕永远清
// 不掉；与 WorkspaceDb.removeWorkspaceTree 同构姿势，平铺消费方行为不变）。深度不设闸：
// 内容恒应用自产固定形态，不收外部输入。C2 起双侧共用 export（导出/清扫 + 导入收尾）
export function cleanupDir(dir: string): void {
  try {
    for (const name of fs.listFileSync(dir)) {
      const child: string = dir + '/' + name;
      try {
        if (fs.statSync(child).isDirectory()) {
          cleanupDir(child);
        } else {
          fs.unlinkSync(child);
        }
      } catch (e) {
        // 单项失败跳过
      }
    }
    fs.rmdirSync(dir);
  } catch (e) {
    // 目录不存在 = 目标状态
  }
}

function writeFileText(path: string, content: string): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE |
    fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
}

// C2 起双侧共用 export（导出目录戳 + 导入目录戳）
export function exportStamp(): string {
  const d: Date = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '-' +
    pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

// ── 导入（已外迁）──
// 「导入 + 密钥回填」全域（含读侧工具）已整块外迁同目录 ExportImportApply.ets（方法体
// 逐字搬迁，消费方 DataSyncPage / S3SyncCard 的 importFromZip import 路径随迁改指彼件）；
// DOMAIN/TAG 日志常量随迁彼件（取值原样），本件已无 hilog 调用。
