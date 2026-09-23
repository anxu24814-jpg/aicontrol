// 全量导入导出域（2026-09-03 Cube 吸收第三批③；蓝本 = cubeagent-stream-test〔chatcube
// MIT 快照〕services/ImportExportService.ets 分域 manifest + ZIP 结构，裁剪至 aicontrol 形态）：
// · 导出：EXPORT_TABLES 全行 → 分域 JSON（manifest + 各表文件 + 偏好分域）→ zlib.compressFile 打包
//   zip 落 cacheDir（分享/上传用完即删——数据有界）。
// · 导入：解压 → manifest 校验闸门（**补 Cube 缺失的坑**——Cube manifest.version 读而不校验，
//   调研卷04 §二⑨）→ 逐表写入，冲突策略两态（B2，Cube 四态裁剪为两态）：skip = 合并
//   （现状）；overwrite = INSERT OR REPLACE 同 id 整行替换（恢复语义）。
// · 通用行序列化/反序列化：PRAGMA table_info 判列型（ResultSet 无 columnType API——
//   d.ts 实查），导入按目标表现存列过滤（跨版本前向/后向兼容，多列少列都不炸）。
// · 偏好分域（2026-09-10 方案-偏好与密钥接入备份 §4.1）：zip 根 preferences.json =
//   [{key,type,value}]，键清单 = AppPreferences.BACKUP_PREF_KEYS（两分类表为唯一来源，
//   不进备份的键见 BACKUP_EXCLUDED_PREF_KEYS——2026-09-23 自检轮去数：原文写「7 键」而表已
//   增至 12 键，该数随每笔新增偏好天然漂移，故改指表不记数，防两处漂移）；导入按冲突策略
//   决定动不动——overwrite 覆盖、skip 保持本机现值（方案 §4.7 拍板），老备份无该文件走
//   缺失容忍 continue。
// · 凭据两档产物（同方案 §4.2 凭据登记块/§4.3）：不含密钥档 = providers 的三个明文敏感
//   列（balance_key / balance_headers / headers）置空；含密钥档 = 额外写 secrets.enc
//   （加密件，内含 Key 池明文 + 搜索引擎密钥 + 上述三列）。★ 两个档位的 providers.json
//   都置空——明文只进 Asset 与加密件，裸明文落盘的产物形态不存在。加密件走 ProviderShare
//   的 serializeEncryptedContainer / openEncryptedContainer（PBKDF2 + AES-GCM 单一来源），
//   本域不做第二套加密。WebDAV 密码恒不进包（通道凭据自指死锁，AppPreferences 登记 #4）。
// · hasKey 对账（同方案 §4.5）：导入偏好后按**本机 Asset 真值**回填搜索引擎 hasKey——
//   同设备恢复显示「已配置」且为真、换设备自然「未配置」，两边自动正确且用户零重填。
// · Key 明文边界：Key 池明文恒只在 Asset，DB 仅存元数据——不含密钥档导入后需重填（同
//   设备因 Asset IS_PERSISTENT 天然还在，故多数场景无需重填）；含密钥档可跨设备带走明文。
// · 附件边界（2026-09-09 附件落盘第一轮）：message_attachments 不进 EXPORT_TABLES——
//   附件元数据不与文件本体分头行动（备份带行不带文件 = 恢复后一排点不开的条目，Cube/
//   RikkaHub 均带附件文件进备份，本项目待存储管理笔拍板「同进同出」形态）。★ 后置时序
//   约束：将来导出带附件时，覆盖导入的附件清理必须发生在「写入导入的附件行」之前，或
//   清理只针对「本机有、备份无」的行——否则会把刚导入的行一起删掉。覆盖导入（overwrite）
//   现口径 = 被覆盖消息回到备份当时状态（备份无附件元数据），本机附件行与文件随之作废
//   （skip 路径零触碰）；导入成功后跑一次库盘收敛兜底。
// 层位：common/store（rdb 依赖 + 被 UI 页消费）；刷新链由页面层负责（SESSION_LIST_RELOAD_KEY
// / 列表纪元键），本域只管数据面。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import zlib from '@ohos.zlib';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sharedRdbStore } from './ChatDb';
import { backfillMessageSeq, seedMessageSeq } from './MessageSeqDb';
import { deleteAttachmentsForMessages, reconcileAttachments,
  removeAttachmentFiles } from './AttachmentDb';
import { loadPoolKey, loadSearchEngineKey, savePoolKey,
  saveSearchEngineKey } from './KeyStore';
import { openEncryptedContainer, serializeEncryptedContainer } from './ProviderShare';
import { SEARCH_ENGINES, refreshEngineHasKeyFromAsset } from '../search/SearchEngineRegistry';
import { applyBackupPrefItems, collectBackupPrefItems, parsePrefBackup,
  serializePrefBackup } from '../AppPreferences';
import { AI_NOTICE_FILE_NAME, aiNoticeFileText } from '../AiDisclosure';

// 格式版本（manifest.schemaVersion —— 写入恒用当前值，读取见 ACCEPTED_SCHEMA_VERSIONS）。
// ★ 2026-09-10 自 1 升 2（方案 §4.4）：2 = 带偏好分域（+ 可选密钥档）。**只升不兼容会让
// 用户手里 09-10 之前的所有备份无法导入**（老包被闸门整体拒绝），故导入侧接受 {1,2}：
// 1 = 无偏好分域无密钥档的老包，行为与升级前逐字节一致；3 与 0 等仍拒绝（新版本应用读
// 老包可以，老版本应用读新包会被其自身的 1 版闸门拒绝并提示「先升级应用」，语义正确）
const SCHEMA_VERSION: number = 2;
const ACCEPTED_SCHEMA_VERSIONS: number[] = [1, 2];
const DOMAIN: number = 0xE17;
const TAG: string = 'ExportImport';
// 导出的表（导入顺序 = 依赖序：先服务商域后业务域；无外键约束但 id 引用语义有向）。
// v18（2026-09-06）+ token_usage_events（用量账本——导入按现存列过滤天然兼容，老备份
// 缺该分域文件走缺失容忍 continue 不炸）；
// v20（2026-09-08）+ memories（跨会话长期记忆——同上列过滤兼容；assistantId 引用已删
// 助手 = 弱链显示侧兜底，不阻导入）
// v30（2026-09-13 技能层）+ skills / skill_files（技能库与技能附件文件——技能是用户资产，
// 与提示词库/记忆库同待遇随备份走；skill_files 笔 1 恒空表、导出无害，笔 2 起有内容。
// ★ 级联语义：skill_files 行由 skillId 指向 skills——导入顺序按依赖序 skills 在前，
// skill_files 在后；两表都不随任何其他表级联）
// v35（2026-09-20 助手级记忆）+ assistant_memories（助手级记忆库——与 memories 同待遇随
// 备份走；行 assistantId 引用已删助手 = 弱链显示侧兜底不阻导入〔级联删后正常无孤儿，导入
// 侧不校验引用完整性〕；旧备份缺该分域文件走缺失容忍 continue 不炸；导入顺序 = memories
// 之后，与依赖序无涉——独立表无跨表引用）
// v38（2026-09-21 世界书知识库）+ knowledge_books / knowledge_entries（知识库与条目——用户
// 手写资产，与技能库/记忆库/提示词库同待遇随备份走。★ 级联语义：knowledge_entries 行由
// bookId 指向 knowledge_books——导入顺序按依赖序书在前、条目在后；两表都不随任何其他表
// 级联，助手行的 knowledge 启用列只是弱链 id 集，导入不校验引用完整性；旧备份缺这两张表
// = 缺失容忍 continue 不炸，恢复后知识库为空零报错）
// v43（2026-09-23 知识库文件笔）+ knowledge_files（条目附件件——纯文本资产，与知识库两表
// 同待遇随备份走。★ 级联语义：knowledge_files 行由 entryId 指向 knowledge_entries——导入
// 顺序按依赖序条目在前、附件在后；不随任何其他表级联，旧备份缺本表 = 缺失容忍 continue 不炸，
// 恢复后条目零附件零报错）
// 件内私有（2026-09-12 曾加 export 出口供跨件校验——消费方 = 应用内自检域；2026-09-20 自检
// 域全量退役后跨件消费方已删除，出口随之回收改件内私有，与 WebDavApi 的 trimSlash /
// remoteUrl 同款处理）
// ★ 清单规模改动须同笔随形 scripts/assert-ui-shape.mjs ㊽ 组引号计数钉——漏改 = 交付门禁挂红。
// 域内清单：文首逐表登记 + 导入侧按 EXPORT_TABLES 遍历）
const EXPORT_TABLES: string[] = ['providers', 'provider_models', 'provider_keys',
  'prompt_templates', 'assistants', 'conversations', 'messages', 'token_usage_events',
  'memories', 'assistant_memories', 'skills', 'skill_files',
  'knowledge_books', 'knowledge_entries', 'knowledge_files'];

// 偏好分域文件名（zip 根；2026-09-10 方案 §4.1）
const PREF_FILE_NAME: string = 'preferences.json';
// 密钥档文件名（zip 根；仅含密钥档产出——ProviderShare 加密容器，见头注释）
const SECRETS_FILE_NAME: string = 'secrets.enc';
// providers 三个明文敏感列（凭据 #3；建表 SQL = ChatDbMigrate.ets）——两档产物都置空
const SENSITIVE_PROVIDER_COLUMNS: string[] = ['balance_key', 'balance_headers', 'headers'];

// 备份格式版本闸门（纯函数，node 断言直跑）：写入恒 SCHEMA_VERSION，读取接受
// ACCEPTED_SCHEMA_VERSIONS 全集（老包兼容是硬要求，见 SCHEMA_VERSION 注释）
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
  skipped: Record<string, number>; // 表名 → id 冲突跳过行数（含坏行失败）
  totalImported: number;
  totalSkipped: number;
  overwritten: Record<string, number>; // 表名 → 覆盖替换行数（skip 态恒 0）
  totalOverwritten: number; // 覆盖总数（skip 态恒 0）
  // 恢复的偏好项数（2026-09-10）：overwrite 态 = 实际写入条数（键未注册/类型不符被跳过的
  // 不计）；skip 态与老备份（无偏好分域）恒 0（skip = 偏好不动，方案 §4.7）
  prefCount: number;
  // 密钥档逐条回填的失败条数（2026-09-10 O2 修复）：此时表数据与偏好均已照常恢复、仅
  // 密钥部分未写入（Asset/RDB 单条失败不炸整批，与表循环逐行容错同口径——此前一条失败
  // 整体抛「恢复失败」与实况不符）；不含密钥档与回填全成恒 0，UI 据此分档呈报
  secretFailures: number;
  // 表 JSON「文件在但解析失败/非数组」的表名清单（2026-09-11 自检）：此前静默 continue 且
  // 摘要只打非零表 = 损坏分域对用户不可见（误当「备份里本来就没有」）；UI 据此如实呈报
  parseFailed: string[];
}

// ── 通用行序列化（PRAGMA 列型驱动）──

interface ColumnInfo {
  name: string;
  type: string; // 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB' | 其他
}

// 列信息读取（PRAGMA table_info——迁移域 columnExists 同数据源；cid/name/type/notnull...)
async function tableColumns(rdb: relationalStore.RdbStore, table: string): Promise<ColumnInfo[]> {
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

// 全量导出：EXPORT_TABLES 各表 + 偏好分域 → 分域 JSON → zip。产物 = {cacheDir}/aicontrol_export_{ts}/
// aicontrol_backup_{ts}.zip（目录临时驻留——调用方用后 cleanupExportDir 清删；防「先压后写」
// 中断残留半成品）
// includeSecrets = 含密钥档（额外产 secrets.enc 加密件，passphrase 必填非空）；两档的
// providers.json 都置空三列敏感明文（见头注释）。
export async function exportAllData(ctx: common.Context, includeSecrets: boolean,
  passphrase: string): Promise<ExportSummary> {
  const rdb: relationalStore.RdbStore = sharedRdbStore();
  const stamp: string = exportStamp();
  const dir: string = ctx.cacheDir + `/aicontrol_export_${stamp}`;
  fs.mkdirSync(dir, true);
  const counts: Record<string, number> = {};
  let totalRows: number = 0;
  // 密钥档载荷（含密钥档逐表采集，循环后统一加密落盘——内存缓冲用完即弃）
  const secrets: BackupSecrets = { providers: [], engines: [] };
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
    // 偏好分域（★ 恒写：不含密钥档也要带偏好，见头注释；键清单 = AppPreferences 两分类表）
    writeFileText(`${dir}/${PREF_FILE_NAME}`, serializePrefBackup(collectBackupPrefItems()));
    // AI 显式标识随包（2026-09-10 合规上架笔）：备份含助手回复 = 导出场景，包内携带
    // 标识说明文件（文案源 = common/AiDisclosure）；导入侧只按已知表名读 JSON、
    // locateDecompressRoot 只认 manifest.json——本文件不参与恢复，老备份/新备份双向兼容
    writeFileText(`${dir}/${AI_NOTICE_FILE_NAME}`, aiNoticeFileText());
    // 密钥档加密件（仅含密钥档；口令由调用方收齐——空口令在 UI 侧已被拦，此处再兜一道）
    if (includeSecrets) {
      if (passphrase === '') {
        throw new Error('含密钥的备份必须设置口令');
      }
      await collectEngineSecrets(secrets);
      writeFileText(`${dir}/${SECRETS_FILE_NAME}`,
        await serializeEncryptedContainer(secrets, SCHEMA_VERSION, passphrase));
    }
    // 打包（★ 2026-09-03 自检修复：原用 compressFiles 绝对路径列表——zip 条目名形态
    // 未文档化，若带目录层级则解压后平铺读取失败 = 恢复链路整体坏；改 Cube 原版同构
    // compressFile 整目录打包，配套导入侧 locateDecompressRoot 双形态防御）
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

// 行单元格文本（JSON 行值域 Object；非字符串按空处理——列型错配防御）
function rowText(v: Object | undefined): string {
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

// 池明文采集（Asset 逐条读——KeyStore 单条 API 直用；ProviderShare.buildSharePayload 同款
// 循环姿势，不另造批量壳）。明文缺失（Asset 丢失/从未保存）跳过不造假象
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

// 启动兜底清扫（残留 export/import 目录与 zip——crash/中断残留；EntryAbility onCreate 调一次；
// sweepAttachDir 同款姿势，单文件失败跳过下次再清）。
// ★ 2026-09-03 补导入域：前缀清单 +aicontrol_import_/import_upload_tmp（原导入域缺兜底——
// 中断残留会在 cacheDir 堆积，数据有界红线）；同笔修复文件型残留清理不生效的连带 bug——
// cleanupDir 走 listFileSync 对 zip 文件路径抛错被静默吞（zip 型残留从未被删），现按
// statSync 分流：目录走 cleanupDir、文件走 unlinkSync
export function sweepExportTemp(ctx: common.Context): void {
  try {
    for (const name of fs.listFileSync(ctx.cacheDir)) {
      if (!(name.startsWith('aicontrol_export_') || name.startsWith('aicontrol_backup_') ||
        name.startsWith('webdav_download_') || name.startsWith('aicontrol_import_') ||
        name.startsWith('import_upload_tmp'))) {
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

function cleanupDir(dir: string): void {
  try {
    for (const name of fs.listFileSync(dir)) {
      try {
        fs.unlinkSync(dir + '/' + name);
      } catch (e) {
        // 单文件失败跳过
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

function readFileText(path: string): string {
  const stat: fs.Stat = fs.statSync(path);
  const ab: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const len: number = fs.readSync(file.fd, ab);
    return utilDecode(new Uint8Array(ab).subarray(0, len));
  } finally {
    fs.closeSync(file);
  }
}

function utilDecode(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

function exportStamp(): string {
  const d: Date = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '-' +
    pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

// ── 导入 ──

interface Manifest {
  schemaVersion?: number;
  app?: string;
}

// 解压根定位（★ 2026-09-03 自检防御：zlib zip 条目名形态未文档化——压缩目录可能平铺
// 也可能带一层导出目录名；平铺直用 dir，唯一子目录则下钻一层，两形态都兼容；多子目录/
// 无 manifest = 脏包由调用方闸门报错）
function locateDecompressRoot(dir: string): string {
  if (fileExists(`${dir}/manifest.json`)) {
    return dir;
  }
  try {
    const subs: string[] = [];
    for (const name of fs.listFileSync(dir)) {
      try {
        if (fs.statSync(`${dir}/${name}`).isDirectory()) {
          subs.push(name);
        }
      } catch (e) {
        // 单项 stat 失败跳过
      }
    }
    if (subs.length === 1) {
      return `${dir}/${subs[0]}`;
    }
  } catch (e) {
    // 目录不可列 = 按 dir 原样（读取处会报中文错误）
  }
  return dir;
}

// 从 zip 导入（zipPath = 已拷入沙箱的本地路径）：解压 → 校验 → 逐表写入。
// strategy 两态（B2）：skip = id 冲突跳过（合并）；overwrite = 冲突行走 INSERT OR REPLACE
// 整行替换（恢复语义——行内容 = 备份快照 + 现存列过滤，备份行缺的新列落表默认值）。
// 冲突策略对偏好的意义（2026-09-10 方案 §4.7 决明拍板）：overwrite = 偏好被备份值覆盖、
// skip = 偏好保持本机现值（只补记录不改设置）。对密钥档的意义见 applyBackupSecrets 注释。
// askPassphrase = 密钥档口令获取回调（UI 层注入；包内含 secrets.enc 时必调，取消返回 null
// = 整体中止且零副作用——解密发生在任何库写入之前）。
// 抛错 = 中文信息（manifest 不合法 / 解压失败 / 口令错误），调用方 toast；部分成功不回滚
//（逐表独立——与 Cube readImportFiles 容错语义一致，摘要计数可见；密钥档回填同口径逐条
// 容错，失败条数入 ImportSummary.secretFailures 供 UI 分档呈报——2026-09-10 O2 修复，
// 此前一条失败整体抛「恢复失败」与「表数据已全恢复」的实况不符）
export async function importFromZip(ctx: common.Context, zipPath: string,
  strategy: ImportStrategy,
  askPassphrase: () => Promise<string | null>): Promise<ImportSummary> {
  const stamp: string = exportStamp();
  const dir: string = ctx.cacheDir + `/aicontrol_import_${stamp}`;
  fs.mkdirSync(dir, true);
  // seq 分配器重播种句柄（2026-09-21 消息存储机制改造笔 2）：库句柄取到即登记（写入面自此
  // 可能发生）——finally 段据此决定要不要重播种（取到之前早退的路径 = 零库写入，无需播种）
  let importRdb: relationalStore.RdbStore | null = null;
  try {
    await zlib.decompressFile(zipPath, dir, {});
    const root: string = locateDecompressRoot(dir);
    const manifestText: string = readFileText(`${root}/manifest.json`);
    let manifest: Manifest;
    try {
      manifest = JSON.parse(manifestText) as Manifest;
    } catch (e) {
      throw new Error('备份文件损坏：manifest 无法解析');
    }
    // 版本闸门（Cube 缺失项补齐——调研卷04 §二⑨ 坑）：不合法即整体拒绝，防脏数据入库。
    // ★ 2026-09-10 起接受 {1,2}（老包兼容，见 SCHEMA_VERSION 注释）——闸门只在「不是本
    // 应用的包」与「版本不在接受集」两条上拒绝
    if (manifest.app !== 'aicontrol' || !isAcceptedBackupVersion(manifest.schemaVersion)) {
      throw new Error('备份文件不是本应用的合法全量备份（版本不匹配），已取消导入');
    }
    // 密钥档先解密（★ 在写任何库之前：口令错误或用户取消 = 零副作用中止，P0-1 不静默）
    const secrets: BackupSecrets | null = await readSecrets(root, askPassphrase);
    const rdb: relationalStore.RdbStore = sharedRdbStore();
    importRdb = rdb;
    const imported: Record<string, number> = {};
    const skipped: Record<string, number> = {};
    const overwritten: Record<string, number> = {};
    let totalImported: number = 0;
    let totalSkipped: number = 0;
    let totalOverwritten: number = 0;
    // messages 表覆盖行 id 收集（2026-09-09 附件落盘第一轮）：覆盖 = 该消息回到备份当时
    // 状态，本机附件元数据行与文件随之作废（表循环后统一处理）
    const replacedIds: string[] = [];
    // providers 表中「本次导入建立或覆盖」的服务商 id 集（密钥档回填范围——明文与行同源，
    // skip 态下未触动的本机服务商明文保持本机现状，见 applyBackupSecrets）
    const touchedProviders: Set<string> = new Set<string>();
    // 表 JSON 损坏（解析失败/非数组）的表名——如实呈报，防「导入完成」掩盖损坏分域
    const parseFailed: string[] = [];
    for (const table of EXPORT_TABLES) {
      const filePath: string = `${root}/${table}.json`;
      if (!fileExists(filePath)) {
        continue; // 分域缺失容忍（Cube readImportFiles 同语义——老备份缺新表文件）
      }
      let rows: Record<string, Object>[];
      try {
        rows = JSON.parse(readFileText(filePath)) as Record<string, Object>[];
      } catch (e) {
        parseFailed.push(table); // 单域解析失败跳过不炸（损坏如实呈报——此前「计数不计」对用户不可见）
        continue;
      }
      if (!Array.isArray(rows)) {
        parseFailed.push(table);
        continue;
      }
      const targetCols: ColumnInfo[] = await tableColumns(rdb, table);
      const colNames: string[] = targetCols.map((c: ColumnInfo): string => c.name);
      // 目标表现存 id 集（冲突 skip）。★ 2026-09-03 自检 P1-1 修复：全库 7 表 id 均
      // TEXT PRIMARY KEY（ChatDbMigrate 建表 SQL）——getLong 读 TEXT 列属列型错配
      //（抛错 = 整个导入挂；解析失败恒 0 = 冲突集失效靠主键约束兜底且计数失真），
      // 改 getString 与导出侧 TEXT 读法对称
      const existingIds: Set<string> = new Set<string>();
      const rs: relationalStore.ResultSet = await rdb.querySql(`SELECT id FROM ${table}`);
      try {
        while (rs.goToNextRow()) {
          existingIds.add(rs.getString(rs.getColumnIndex('id')));
        }
      } finally {
        rs.close();
      }
      let added: number = 0;
      let dup: number = 0;
      let overwrote: number = 0;
      for (const row of rows) {
        const id: Object = row['id'];
        const isConflict: boolean = id !== undefined && existingIds.has('' + id);
        if (isConflict && strategy === 'skip') {
          dup++;
          continue;
        }
        // 列过滤 + 值域映射（仅取目标表存在的列；导出行多列/少列都兼容）
        const names: string[] = [];
        const values: Array<relationalStore.ValueType> = [];
        for (const col of targetCols) {
          const v: Object | undefined = row[col.name];
          if (v === undefined) {
            continue; // 行缺该列 = 走表默认值
          }
          names.push(col.name);
          if (col.type === 'INTEGER') {
            values.push(typeof v === 'number' ? Math.round(v) : 0);
          } else if (col.type === 'REAL') {
            values.push(typeof v === 'number' ? v : 0);
          } else {
            values.push(typeof v === 'string' ? v : String(v));
          }
        }
        // v17 titleSource 兼容（2026-09-05 标题生成自检轮补）：旧版备份行无该键 → 走表默认
        // '' 会让导入的非「新对话」标题在下轮对话完成时被 AI 重生成覆盖——按 ChatDbMigrate
        // v17 回填同款启发式补值（非「新对话」保守视为手改），与升级路径口径一致
        if (table === 'conversations' && !names.includes('titleSource')) {
          const titleAt: number = names.indexOf('title');
          const importedTitle: string = titleAt >= 0 ? '' + values[titleAt] : '';
          names.push('titleSource');
          values.push(importedTitle !== '新对话' ? 'manual' : '');
        }
        if (names.length === 0) {
          continue;
        }
        const placeholders: string = names.map((_n: string): string => '?').join(',');
        try {
          // 冲突行 + overwrite = INSERT OR REPLACE（整行快照替换，单语句原子——801
          // 禁用名单仅事务控制语句，DML 冲突子句不受限，d.ts 实查）
          const verb: string = isConflict ? 'INSERT OR REPLACE INTO' : 'INSERT INTO';
          await rdb.executeSql(
            `${verb} ${table} (${names.join(',')}) VALUES (${placeholders})`, values);
          if (isConflict) {
            overwrote++; // id 已在 existingIds，不重复登记
            if (table === 'messages') {
              replacedIds.push('' + id);
            }
            if (table === 'providers') {
              touchedProviders.add('' + id);
            }
          } else {
            added++;
            if (id !== undefined) {
              existingIds.add('' + id);
              if (table === 'providers') {
                touchedProviders.add('' + id);
              }
            }
          }
        } catch (e) {
          dup++; // 单行失败按跳过计（坏行不炸批量）
        }
      }
      imported[table] = added;
      skipped[table] = dup;
      overwritten[table] = overwrote;
      totalImported += added;
      totalSkipped += dup;
      totalOverwritten += overwrote;
    }
    // 偏好回写（★ 仅 overwrite 态：skip = 偏好保持本机现值，方案 §4.7 拍板；老备份无该
    // 分域文件 = 缺失容忍跳过，本机偏好零变化、不报错）
    let prefCount: number = 0;
    if (strategy === 'overwrite') {
      const prefPath: string = `${root}/${PREF_FILE_NAME}`;
      if (fileExists(prefPath)) {
        prefCount = applyBackupPrefItems(parsePrefBackup(readFileText(prefPath)));
      }
    }
    // 密钥档回填（明文只进 Asset；逐条容错——engineWritten 决定要不要跑 hasKey 对账，
    // failures 进摘要分档文案，见 applyBackupSecrets 注释）
    let secretResult: SecretApplyResult = { engineWritten: false, failures: 0 };
    if (secrets !== null) {
      secretResult = await applyBackupSecrets(rdb, secrets, touchedProviders);
    }
    // hasKey 按本机 Asset 真值对账（方案 §4.5）：偏好被覆盖过或刚补了引擎明文，两种情形
    // 下 cfg 里的 hasKey 都可能与 Asset 真值不符，须重算一次（否则可用引擎被静默跳过、
    // 设置页显示「未配置」与实情不符）
    if (strategy === 'overwrite' || secretResult.engineWritten) {
      // ★ 2026-09-10 自检轮收口（O2 同族剩余可达实例）：本函数唯一调用点就是这里，走到此处
      // 表数据与偏好均已落库，上抛只会让 UI 报「恢复失败」而与实况不符。KeyStore.querySecret
      // 对「非条目不存在」类错误是**会上抛**的（见其 catch 分支的重抛），故这条路径确实可达。
      // 失败时 hasKey 标记保持旧值（可能显示「未配置」而明文其实在，重填一次即纠正、重填
      // 无害），留痕供排障——P0-1 不静默
      try {
        await refreshEngineHasKeyFromAsset();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'hasKey 对账失败，标记保持旧值（库数据与偏好已恢复）：%{public}s',
          (e as Error).message);
      }
    }
    // 覆盖消息附件作废（2026-09-09 附件落盘第一轮）：删被覆盖消息的附件元数据行 +
    // 常驻区文件（备份不含附件面——见头注释「附件边界」；skip 路径零触碰）
    if (replacedIds.length > 0) {
      const removedAttachPaths: string[] = await deleteAttachmentsForMessages(rdb, replacedIds);
      removeAttachmentFiles(removedAttachPaths);
    }
    // 导入后库盘一致性收敛（兜底；fire-and-forget——导入已完成，收敛失败仅留痕不回滚，
    // 下次启动再收敛）
    reconcileAttachments(ctx, rdb).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, '导入后附件收敛失败（下次启动兜底重试）：%{public}s',
        (e as Error).message);
    });
    return { imported: imported, skipped: skipped, totalImported: totalImported,
      totalSkipped: totalSkipped, overwritten: overwritten,
      totalOverwritten: totalOverwritten, secretFailures: secretResult.failures,
      parseFailed: parseFailed, prefCount: prefCount };
  } finally {
    cleanupDir(dir);
    // 导入收尾两步（★ 2026-09-21 笔 3 起成对，**顺序钉 = 补号先、播种后**）：①即时补号（笔 3
    // D3）= 导入行 seq 落 NULL（旧备份无该列）或重号（本版备份经导出侧 NULL→0 归一）时**当场**
    // 整会话重算归一（笔 3 读取权威 = seq，不补则这些行按 SQLite NULL 序跳窗口首/末 = 用户可见
    // 回归）；②分配器重播种（笔 2 D3）= 导回行 seq 保真写回 ⇒ 进程内记账可能过期（备份号可高于
    // 内存记账）⇒ 后续铸造重号，播种读①归一后的 `MAX(seq)`。两件**成败两路 + best-effort 不回抛**：
    // 本函数不设事务（逐行 executeSql 各自提交，「部分成功不回滚」是本域既定口径）⇒ 中途失败时
    // 库内已写入行照样让记账过期，旧设「失败回滚则库未变」的前提经实测不成立；上抛还会与「导入
    // 结果以本函数原语义为准」冲突（数据已恢复却报失败，同 O2 口径）。失败只留痕，兜底 = 下次
    // 启动 sweep（导入 NULL/重号本就是设计内中间态）
    if (importRdb !== null) {
      try {
        await backfillMessageSeq(importRdb);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '导入后 seq 补号失败（下次启动 sweep 兜底）：%{public}s',
          (e as Error).message);
      }
      try {
        await seedMessageSeq(importRdb);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '导入后 seq 分配器重播种失败（下次启动 sweep 兜底）：%{public}s',
          (e as Error).message);
      }
    }
  }
}

// ── 密钥档读取与回填（导入侧）──

// 密钥档读取：无该文件 = 不含密钥档（返 null，不问口令）；有则先要口令再解密。口令为空或
// 用户取消 → 抛「已取消导入」（调用方静默——正常取消路径）；口令错误/文件被篡改 =
// ProviderShare 的中文提示上抛（GCM 认证失败，两情形同一提示）
async function readSecrets(root: string,
  askPassphrase: () => Promise<string | null>): Promise<BackupSecrets | null> {
  const path: string = `${root}/${SECRETS_FILE_NAME}`;
  if (!fileExists(path)) {
    return null;
  }
  const pass: string | null = await askPassphrase();
  if (pass === null || pass === '') {
    throw new Error('已取消导入');
  }
  return parseBackupSecrets(await openEncryptedContainer(readFileText(path), pass));
}

// 密钥档载荷解析（结构容错：字段缺失按空、条目残缺丢弃——完整性已由 GCM 认证保证，
// 这里只防手改与跨版本的形状漂移）
export function parseBackupSecrets(plainText: string): BackupSecrets {
  let parsed: Object;
  try {
    parsed = JSON.parse(plainText) as Object;
  } catch (e) {
    throw new Error('密钥文件内容异常，可能已损坏');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('密钥文件内容异常，可能已损坏');
  }
  const rec: Record<string, Object> = parsed as Record<string, Object>;
  const out: BackupSecrets = { providers: [], engines: [] };
  const providerRaw: Object | undefined = rec['providers'];
  if (Array.isArray(providerRaw)) {
    for (const item of providerRaw as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const e: Record<string, Object> = item as Record<string, Object>;
      const providerId: string = rowText(e['providerId']);
      if (providerId === '') {
        continue;
      }
      const keys: KeySecretEntry[] = [];
      const keysRaw: Object | undefined = e['keys'];
      if (Array.isArray(keysRaw)) {
        for (const k of keysRaw as Object[]) {
          if (k === null || typeof k !== 'object' || Array.isArray(k)) {
            continue;
          }
          const kr: Record<string, Object> = k as Record<string, Object>;
          const keyId: string = rowText(kr['keyId']);
          const secret: string = rowText(kr['secret']);
          if (keyId !== '' && secret !== '') {
            keys.push({ keyId: keyId, secret: secret });
          }
        }
      }
      out.providers.push({
        providerId: providerId, balanceKey: rowText(e['balanceKey']),
        balanceHeaders: rowText(e['balanceHeaders']), headers: rowText(e['headers']),
        keys: keys
      });
    }
  }
  const engineRaw: Object | undefined = rec['engines'];
  if (Array.isArray(engineRaw)) {
    for (const item of engineRaw as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const e: Record<string, Object> = item as Record<string, Object>;
      const engineId: string = rowText(e['engineId']);
      const secret: string = rowText(e['secret']);
      if (engineId !== '' && secret !== '') {
        out.engines.push({ engineId: engineId, secret: secret });
      }
    }
  }
  return out;
}

// 密钥档回填结果：engineWritten = 是否写过引擎明文（供调用方决定要不要跑 hasKey 对账）；
// failures = 逐条容错累计的失败条数（进 ImportSummary.secretFailures，UI 分档呈报——
// 2026-09-10 O2 修复）
interface SecretApplyResult {
  engineWritten: boolean;
  failures: number;
}

// 密钥档回填（明文只进 Asset；三条边界）：
// ① 池明文只写「行已由本次导入建立或覆盖」的服务商（touched——行与明文同源：skip 态下
//    未触动的本机服务商明文保持本机现状，不被旧备份悄悄换掉）
// ② 三列回 providers 行（同一 touched 范围）——行导入时已被置空，此处补真值
// ③ 引擎明文只补本机缺失（Asset 是本机真相：本机已有明文就不动，免得恢复旧备份打乱刚
//    配好的引擎；缺明文才补——换机场景正好全缺）
// ★ 逐条容错（2026-09-10 O2 修复）：回填发生在各表与偏好全部落库**之后**，一条失败整体
// 上抛会让 UI 报「恢复失败」而数据其实已全部恢复（且页面刷新广播被跳过，观感「真没恢复」
// 须退出重进）——改与表循环同口径：单条 Asset/RDB 失败计数跳过不炸整批。引擎「读本机
// 明文」失败同计一条且不写（读不到 = 无法判缺失，硬写会违反边界③覆盖本机现有明文）
async function applyBackupSecrets(rdb: relationalStore.RdbStore, secrets: BackupSecrets,
  touched: Set<string>): Promise<SecretApplyResult> {
  let failures: number = 0;
  for (const p of secrets.providers) {
    if (!touched.has(p.providerId)) {
      continue;
    }
    for (const k of p.keys) {
      try {
        await savePoolKey(p.providerId, k.keyId, k.secret);
      } catch (e) {
        failures++; // 单条池明文写入失败跳过（不炸整批）
      }
    }
    if (p.balanceKey !== '' || p.balanceHeaders !== '' || p.headers !== '') {
      const values: Array<relationalStore.ValueType> =
        [p.balanceKey, p.balanceHeaders, p.headers, p.providerId];
      try {
        await rdb.executeSql(
          'UPDATE providers SET balance_key = ?, balance_headers = ?, headers = ? WHERE id = ?',
          values);
      } catch (e) {
        failures++; // 三列回填失败跳过（providers 行已导入，仅缺三列真值）
      }
    }
  }
  let engineWritten: boolean = false;
  for (const e of secrets.engines) {
    try {
      if ((await loadSearchEngineKey(e.engineId)) !== '') {
        continue; // 本机已有明文 = 保持本机现状
      }
      await saveSearchEngineKey(e.engineId, e.secret);
    } catch (err) {
      failures++; // 读失败（无法判缺失，不硬写）或写失败——同计一条跳过
      continue;
    }
    engineWritten = true;
  }
  // 失败留痕（不涉明文，只记条数）：丢失的密钥不可回捞，真机排障需要一条可查的痕迹——
  // 光靠 UI 摘要无法区分「add 失败」与「包里本就没带」。汇总一条不逐条打（防日志刷屏）
  if (failures > 0) {
    hilog.warn(DOMAIN, TAG,
      '密钥档回填有 %{public}d 项未写入（单条失败已跳过，表数据与偏好不受影响）', failures);
  }
  return { engineWritten: engineWritten, failures: failures };
}

function fileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch (e) {
    return false;
  }
}
