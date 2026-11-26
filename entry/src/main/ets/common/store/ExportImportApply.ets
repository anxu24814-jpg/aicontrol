// 备份导入与密钥回填域（自 ExportImport.ets 导入链整块外迁，方法体逐字搬迁零行为变化；导入域
// 全景叙述仍以彼件为源）。一句话职责 =「把一份全量备份 zip 安全落回本机库与 Asset（含偏好回写
// 与密钥档回填）」。
// 依赖方向单向：本件 import ExportImport（版本闸门 / EXPORT_TABLES·三文件名·tableColumns 等
// 双侧共用面 / 接口 BackupSecrets·ImportSummary·ImportStrategy·KeySecretEntry）；ExportImport
// 不 import 本件——导入链只被页面层消费方调用，无环。导出链与密钥采集留在 ExportImport。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sharedRdbStore } from './ChatDb';
import { runWriteQueued } from './DbWriteQueue';
import { backfillMessageSeq, seedMessageSeq } from './MessageSeqDb';
import { deleteAttachmentsForMessages, reconcileAttachments,
  removeAttachmentFiles, AttachmentGraphCleanup } from './AttachmentDb';
import { loadSearchEngineKey, savePoolKey, saveSearchEngineKey } from './KeyStore';
import { applyHttpCredSecrets, parseHttpCredSecrets } from './HttpCredBackup';
import { openEncryptedContainer } from './ProviderShare';
import { BuiltinImportGuard, keepBuiltinImportRow,
  removeRedundantBuiltinAfterImport } from './ProviderBuiltinDedup';
// 功能槽引用维护：备份内置行被跳过时把槽位 provider 键映到本机承接行（见 slotRemap 注释）
import { remapSlotProvider } from './FunctionalSlotBinding';
// 模型选择对账：导入把备份两键原样写回，可能指向本机已停用/已删的目标，收尾跑一次与启动同口径对账
import { reconcileModelBindings } from './ModelBindingReconcile';
import { importGraphDomain, buildAttachmentGraphCleanup,
  GraphBackupConversation, GraphImportOutcome } from './GraphTransfer';
import { refreshEngineHasKeyFromAsset } from '../search/SearchEngineRegistry';
import { applyBackupPrefItems, parsePrefBackup } from '../AppPreferencesBackup';
// 会话格式态词表（随导入链自 ExportImport 迁来）：现只消费覆盖收集判据〔importedState !==
// graph 即清本机图侧行〕。写值侧单源引用，禁在本件抄 'legacy'/'graph' 字面量；本件 →
// MessageBranchDb 单向无环（其只引 ChatDb/MessageSeqDb，均不引本件）
import { CONV_STATE_GRAPH, CONV_STATE_LEGACY } from './MessageBranchDb';
import { BackupSecrets, KeySecretEntry, ImportSummary, ImportStrategy,
  isAcceptedBackupVersion, EXPORT_TABLES, PREF_FILE_NAME, GRAPH_FILE_NAME,
  SECRETS_FILE_NAME, ColumnInfo, tableColumns, rowText, exportStamp,
  cleanupDir } from './ExportImport';

// 域常量（随导入链迁来，取值原样——日志 DOMAIN/TAG 与拆分前同字面，日志面零变化）
const DOMAIN: number = 0xE17;
const TAG: string = 'ExportImport';

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

// ── 导入 ──

interface Manifest {
  schemaVersion?: number;
  app?: string;
}

// 解压根定位（★ zlib zip 条目名形态未文档化——压缩目录可能平铺也可能带一层导出目录名；
// 平铺直用 dir，唯一子目录则下钻一层，两形态都兼容；多子目录/无 manifest = 脏包由调用方闸门报错）
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
// 整行替换（恢复语义——行内容 = 备份快照 + 现存列过滤，备份行缺的新列落表默认值）。对偏好
//（决明拍板）：overwrite = 偏好被备份值覆盖、skip = 偏好保持本机现值（只补记录不改设置）。
// 对密钥档的意义见 applyBackupSecrets 注释。askPassphrase = 口令获取回调（UI 层注入；包内含
// secrets.enc 时必调，取消返回 null = 整体中止且零副作用——解密发生在任何库写入之前）。
// 抛错 = 中文信息（manifest 不合法 / 解压失败 / 口令错误），调用方 toast；**部分成功不回滚**
//（逐表独立——与 Cube readImportFiles 容错语义一致，摘要计数可见；密钥档回填同口径逐条容错，
// 失败条数入 ImportSummary.secretFailures 供 UI 分档呈报）。
// 行级失败分账（C1）：单行转换异常 / 不可导入行（names 空）/ 写入被拒（含覆盖消息单元回滚）
// 计 rowFailures（按表 + 总数），与 skipped（策略跳过）严格分账、绝不回流；逐表聚合一条
// hilog.warn 留痕，逐行 catch 禁打原始异常（RDB 错误消息可能回显 SQL 与绑定值）
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
    // 版本闸门：不合法即整体拒绝，防脏数据入库。app 不符与版本不符分两句呈报——版本过旧
    // 给可行动指引（格式 1/2 已拒收，见 ACCEPTED_SCHEMA_VERSIONS 注释）
    if (manifest.app !== 'aicontrol') {
      throw new Error('备份文件不是本应用的合法全量备份，已取消导入');
    }
    if (!isAcceptedBackupVersion(manifest.schemaVersion)) {
      throw new Error('备份版本过旧，无法导入。请先用能打开该备份的旧版本应用，重新导出后再试');
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
    // 行级失败分账（C1）：与 skipped（策略跳过）严格分账，一行失败只进这本账
    const rowFailures: Record<string, number> = {};
    let totalRowFailures: number = 0;
    // messages 表覆盖行 id 收集（2026-09-09 附件落盘第一轮）：覆盖 = 该消息回到备份当时
    // 状态，本机附件元数据行与文件随之作废（表循环后统一处理）
    const replacedIds: string[] = [];
    // 覆盖消息的作废附件路径（单条提交单元在事务内作废元数据行、commit 后交出文件路径；与收尾
    // deleteAttachmentsForMessages 的兜底路径去重合并后统一删——文件删除恒在所有 commit 之后）
    const unitInvalidatedPaths: string[] = [];
    // providers 表中「本次导入建立或覆盖」的服务商 id 集（密钥档回填范围——明文与行同源，
    // skip 态下未触动的本机服务商明文保持本机现状，见 applyBackupSecrets）
    const touchedProviders: Set<string> = new Set<string>();
    // 功能槽 provider 键重映射表（备份服务商 id → 本机承接行 id）：唯一写点 = 备份 builtin 行
    // 命中本机同名手建行被跳过时（偏好仍按备份写，会指向不存在的 id）；应用时点必须在偏好
    // 回写之后（覆盖策略下槽位两键来自备份）
    const slotRemap: Map<string, string> = new Map<string, string>();
    // 表 JSON 损坏（解析失败/非数组）的表名——如实呈报，防「导入完成」掩盖损坏分域
    const parseFailed: string[] = [];
    // 旧格式备份**覆盖**的会话 id 集（★ 2026-09-26 S5）：conversations 行无 migrateState 列
    // （格式 1/2 旧备份）+ 覆盖已有行 ⇒ REPLACE 整行后该列落表默认 legacy——本机原 graph
    // 会话被反向重置且图侧行成孤儿；收尾统一清图侧（见 purgeLegacyResetGraphRows 调用点）
    const legacyResetConvIds: string[] = [];
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
      // 目标表现存 id 集（冲突 skip）。★ 全库 7 表 id 均 TEXT PRIMARY KEY——getLong 读
      // TEXT 列属列型错配（抛错 = 整个导入挂；解析失败恒 0 = 冲突集失效），改 getString
      // 与导出侧 TEXT 读法对称
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
      let failed: number = 0; // 行级失败表内计数（C1——循环后随形入 rowFailures/总数）
      for (const row of rows) {
        const id: Object = row['id'];
        const isConflict: boolean = id !== undefined && existingIds.has('' + id);
        if (isConflict && strategy === 'skip') {
          dup++;
          continue;
        }
        // ★ 备份 builtin=1 行命中本机用户手建同名家（builtin=0）时跳过（用户配置优先；查重键
        // = name+baseUrl——内置 id 每台设备随机，按 id 查重对内置行天然失效）。命中全为
        // builtin=1 不在此拦：备份行先落库再让位（见下方 inserted 钩子），失败方向 = 残留
        // 重复行由启动收敛自愈，不丢数据。★ 被跳过时记「备份 id → 本机手建 id」，偏好回写后
        // 把功能槽 provider 键映过去——否则覆盖策略下槽位两键指向不存在的备份 id，卡片显示
        //「未选择」而选择半模态仍回退显示原模型
        if (table === 'providers' && !isConflict && '' + row['builtin'] === '1') {
          const guard: BuiltinImportGuard =
            await keepBuiltinImportRow('' + row['name'], '' + row['baseUrl']);
          if (!guard.keep) {
            if (guard.remapTo !== '' && id !== undefined) {
              slotRemap.set('' + id, guard.remapTo);
            }
            dup++;
            continue;
          }
        }
        // 列过滤 + 值域映射（importRowColumns 件内私有纯函数；C1 起以 try 包住：单行转换
        // 异常计行级失败后 continue，不再逃出整批由 UI 报整体「恢复失败」）
        let names: string[] = [];
        let values: Array<relationalStore.ValueType> = [];
        try {
          const columns: ImportedRowColumns = importRowColumns(table, row, targetCols);
          names = columns.names;
          values = columns.values;
        } catch (e) {
          // 行级转换失败分账（C1；不打原始异常与行内容——诊断看逐表聚合留痕）
          failed++;
          continue;
        }
        // ★ 迁移机制退役后 migrateState 只余 graph / legacy 两值**语义**（非 graph 即墓碑），
        // 备份带来的任何值（legacy / 历史 migrating 残值 / 空串等脏值）导入后都自然按墓碑读
        //（ChatContextSource.conversationWritableRoute 单源判据），无需归一改写；下方 purge
        // 判据不受影响——三种值都在其外，走同一删除路径。
        // 覆盖收集（S5；判据扩面 C2①）：判据 = **导入行有效态**（缺列按表默认 legacy 计）≠
        // graph——格式 3 备份里明写 legacy 的行同样 REPLACE 掉本机 graph 态，只按「缺
        // migrateState 列」收集会让它们漏进 purge 集：本机原 graph 会话被反向重置而图侧行
        // 留成幽灵。skip 态冲突在循环头已 continue，此处 isConflict 恒 = overwrite 形态
        const importedState: string = names.includes('migrateState')
          ? '' + values[names.indexOf('migrateState')]
          : CONV_STATE_LEGACY;
        if (table === 'conversations' && isConflict && importedState !== CONV_STATE_GRAPH) {
          legacyResetConvIds.push('' + id);
        }
        if (names.length === 0) {
          // 不可导入行（键名全不在目标表列集）= 行级失败分账（C1——原零计数静默跳过）
          failed++;
          continue;
        }
        const placeholders: string = names.map((_n: string): string => '?').join(',');
        try {
          if (table === 'messages' && isConflict) {
            // 覆盖消息 = 单条提交单元：消息行替换 + 该消息旧附件元数据作废**同一事务**完成，
            // 文件仍 commit 之后删——消「行已替换提交、附件元数据未作废」分离窗口；单元抛错在
            // 下方 catch 按行级失败分账跳过（坏行不炸批量，单元事务已回滚，行与元数据同回滚）
            const invalidated: string[] =
              await replaceImportedMessageUnit(rdb, '' + id, names, values);
            for (const p of invalidated) {
              unitInvalidatedPaths.push(p);
            }
          } else {
            // 冲突行 + overwrite = INSERT OR REPLACE（整行快照替换，单语句原子——801
            // 禁用名单仅事务控制语句，DML 冲突子句不受限，d.ts 实查）
            const verb: string = isConflict ? 'INSERT OR REPLACE INTO' : 'INSERT INTO';
            await rdb.executeSql(
              `${verb} ${table} (${names.join(',')}) VALUES (${placeholders})`, values);
          }
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
          // ★ 备份 builtin 行已落库 → 让位删除本机同名 builtin=1 重复行（内部全吞错留痕，
          // 残留由启动收敛兜底——先插后删的次序理由见 ProviderBuiltinDedup 头注释）
          if (table === 'providers' && !isConflict && '' + row['builtin'] === '1') {
            await removeRedundantBuiltinAfterImport('' + row['name'], '' + row['baseUrl'],
              '' + id);
          }
        } catch (e) {
          // 行级写入失败分账（C1——原 dup++ 混进策略跳过账；不打原始异常：RDB 错误消息
          // 可能回显 SQL 与绑定值。含覆盖消息单元回滚上抛，单元事务回滚语义不变）
          failed++;
        }
      }
      // 行级失败逐表聚合留痕（只含表名 + 条数，逐行 catch 不打原始异常防敏感值泄漏）
      if (failed > 0) {
        hilog.warn(DOMAIN, TAG,
          `${table} 表有 %{public}d 行未导入（单行失败已跳过，部分成功不回滚）`, failed);
      }
      imported[table] = added;
      skipped[table] = dup;
      overwritten[table] = overwrote;
      rowFailures[table] = failed;
      totalImported += added;
      totalSkipped += dup;
      totalOverwritten += overwrote;
      totalRowFailures += failed;
    }
    // 图域后处理（格式 3 且带 graph.json）：修复线性导入的 NULL 归一破坏面（parentMessageId
    // 根语义/seq/stepIndex/coversToSeq）+ 重建图侧五行 + 会话态置 graph。skip 态下目标已
    // graph 的会话整体跳过（图级冲突规则，J8 同源）；导入前置 capability 写 2（图态落库先于
    // 或同于能力标记）。格式 1/2 无该文件 = 缺失容忍跳过（旧备份恢复后走会话级迁移发布，K10）。
    // ★ 出参 GraphImportOutcome——成功/失败双计（失败会话数进摘要分档），作废附件的**文件
    // 清单**由本函数在全部导入动作之后删
    let graphFailedSessions: number = 0;
    const graphInvalidatedPaths: string[] = [];
    if (manifest.schemaVersion !== undefined && manifest.schemaVersion >= 3 &&
      isAcceptedBackupVersion(manifest.schemaVersion)) {
      const graphPath: string = `${root}/${GRAPH_FILE_NAME}`;
      if (fileExists(graphPath)) {
        let graphConvs: GraphBackupConversation[] = [];
        try {
          graphConvs = JSON.parse(readFileText(graphPath)) as GraphBackupConversation[];
        } catch (e) {
          graphConvs = [];
          parseFailed.push(GRAPH_FILE_NAME);
        }
        if (Array.isArray(graphConvs) && graphConvs.length > 0) {
          const graphOutcome: GraphImportOutcome =
            await importGraphDomain(rdb, graphConvs, strategy);
          imported['graph_conversations'] = graphOutcome.applied;
          graphFailedSessions = graphOutcome.failed;
          for (const p of graphOutcome.invalidatedLocalPaths) {
            graphInvalidatedPaths.push(p);
          }
        }
      }
    }
    // 覆盖重置的图侧残留清理（S5；收集判据扩面见 C2①）：把被 REPLACE 写回非 graph 态的会话
    // 收口成干净起点（图侧五行清空）——不主动反向也不留孤儿。★ 订正：原「之后由首开/写入触发
    // 的既有迁移链重建」随迁移机制退役**已不成立**——非 graph 行导入后恒为墓碑（M4：非 graph
    // 即墓碑，conversationWritableRoute 单源判读），本段清理即其终点（用户出口 = 会话列表
    // 长按删除）。失败留痕跳过不炸整批（「部分成功不回滚」既定口径，孤儿留存不劣于导入前）。
    // ★ 次序：本段在图域导入**之后**——同一备份若同时携带该会话的 graph.json（图域导入已把
    // 行重建并置回 graph 态），清理按状态守卫跳过，不误删刚导入的图行
    if (legacyResetConvIds.length > 0) {
      await purgeLegacyResetGraphRows(rdb, legacyResetConvIds);
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
    // 功能槽 provider 键重映射：必须在偏好回写之后——覆盖策略下槽位两键刚从备份写入，可能
    // 指向被跳过的备份内置行，此处映到本机同名手建行；skip 策略下偏好保持本机值，零命中零写
    let slotRemapped: number = 0;
    slotRemap.forEach((toId: string, fromId: string): void => {
      slotRemapped += remapSlotProvider(fromId, toId);
    });
    if (slotRemapped > 0) {
      hilog.info(DOMAIN, TAG, '备份导入功能槽重映射 %{public}d 处（内置行被跳过，映到本机手建行）',
        slotRemapped);
    }
    // 模型选择对账：偏好已按备份写回（覆盖策略），备份两键可能指向本机已停用/已删/类别不符
    // 的目标——只靠下次冷启动对账会让本次会话卡面继续显示旧模型（发送链却已回退），与 1970
    //「停用即回到未选择」矛盾。跑一次与启动同口径的对账清成未选择（助手绑定被清时对账内部
    // 自带广播）；失败只留痕——库数据与偏好均已落库，不把一次对账失败报成「恢复失败」
    try {
      await reconcileModelBindings();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '导入后模型选择对账失败（下次启动兜底重试）：%{public}s',
        (e as Error).message);
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
      // ★ 本函数唯一调用点就是这里，走到此处表数据与偏好均已落库，上抛只会让 UI 报「恢复失败」
      // 而与实况不符（KeyStore.querySecret 对「非条目不存在」类错误会上抛，路径确实可达）。
      // 失败时 hasKey 标记保持旧值（可能显示「未配置」而明文其实在，重填一次即纠正），留痕排障
      try {
        await refreshEngineHasKeyFromAsset();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'hasKey 对账失败，标记保持旧值（库数据与偏好已恢复）：%{public}s',
          (e as Error).message);
      }
    }
    // 覆盖消息附件作废：走上方单条提交单元的行，附件元数据行已在单元事务内作废——此处
    // deleteAttachmentsForMessages 命中 0 行属正常（对未走单元的行兜底，如历史分支形态）；
    // 文件删除 = 单元交出路径与本处兜底路径**去重合并**，全部 commit 之后统一删。skip 路径
    // 零触碰
    if (replacedIds.length > 0) {
      const removedAttachPaths: string[] = await deleteAttachmentsForMessages(rdb, replacedIds);
      for (const p of removedAttachPaths) {
        unitInvalidatedPaths.push(p);
      }
    }
    if (unitInvalidatedPaths.length > 0) {
      const seenPaths: Set<string> = new Set<string>();
      const finalPaths: string[] = [];
      for (const p of unitInvalidatedPaths) {
        if (!seenPaths.has(p)) {
          seenPaths.add(p);
          finalPaths.push(p);
        }
      }
      removeAttachmentFiles(finalPaths);
    }
    // 图域作废附件的文件（S8②）：行已在图域事务内删（commit 才把清单交出来），文件在此删
    // ——时点与本段同口径（全部导入动作之后）。空集零开销
    if (graphInvalidatedPaths.length > 0) {
      removeAttachmentFiles(graphInvalidatedPaths);
    }
    // 导入后库盘一致性收敛（兜底；fire-and-forget——失败仅留痕不回滚，下次启动再收敛）。
    // 第三参 = 图侧清理判定面（本机能力现读构造，AttachmentDb 禁 import 图域件故由调用方
    // 注入；能力<2 时构造器返 null = 空串行保护不删）
    const graphCleanup: AttachmentGraphCleanup | null = await buildAttachmentGraphCleanup(rdb);
    reconcileAttachments(ctx, rdb, graphCleanup).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, '导入后附件收敛失败（下次启动兜底重试）：%{public}s',
        (e as Error).message);
    });
    return { imported: imported, skipped: skipped, totalImported: totalImported,
      totalSkipped: totalSkipped, overwritten: overwritten,
      totalOverwritten: totalOverwritten, rowFailures: rowFailures,
      totalRowFailures: totalRowFailures, secretFailures: secretResult.failures,
      graphFailedSessions: graphFailedSessions,
      parseFailed: parseFailed, prefCount: prefCount };
  } finally {
    cleanupDir(dir);
    // 导入收尾两步（★ 成对，**顺序钉 = 补号先、播种后**）：①即时补号 = 导入行 seq 落 NULL（旧
    // 备份无该列）或重号（导出侧 NULL→0 归一）时**当场**整会话重算归一（读取权威 = seq，不补则
    // 这些行按 SQLite NULL 序跳窗口首/末 = 用户可见回归）；②分配器重播种 = 导回行 seq 保真写回
    // ⇒ 进程内记账可能过期（备份号可高于内存记账）⇒ 后续铸造重号，播种读①归一后的 MAX(seq)。
    // 两件**成败两路 + best-effort 不回抛**：本函数不设事务（逐行 executeSql 各自提交，「部分
    // 成功不回滚」既定口径）⇒ 中途失败时库内已写入行照样让记账过期；上抛还会与「导入结果以
    // 原语义为准」冲突（数据已恢复却报失败，同 O2 口径）。失败只留痕，兜底 = 下次启动 sweep
    //（导入 NULL/重号本就是设计内中间态）
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

// 行 → 列组装（件内私有纯函数，行循环中唯一无 IO 纯逻辑，抽出后供 node 断言面直跑——断言按
// 源码形态钉直读，不设无消费出口）。映射逻辑零改写：仅取目标表存在的列（行缺列走表默认值）+
// INTEGER 四舍五入 / REAL 数值直用非数值落 0 / TEXT 直通（非字符串 String(v)、显式 null → ''，
// C3 口径）+ conversations titleSource 启发式
interface ImportedRowColumns {
  names: string[];
  values: Array<relationalStore.ValueType>;
}

function importRowColumns(table: string, row: Record<string, Object>,
  targetCols: ColumnInfo[]): ImportedRowColumns {
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
      // ★ JSON null 不得经 String(null) 写成字面量 'null'——外部编辑过的备份可把
      // migrateState 写成 'null'（非 graph 即墓碑 = 永久不可写），其余 TEXT 列同理；
      // 显式 null 按空串落库（与「行缺该列走表默认」区分：列在、值为空）
      values.push(v === null ? '' : (typeof v === 'string' ? v : String(v)));
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
  return { names: names, values: values };
}

// ── 覆盖消息单条提交单元（件内私有——唯一消费方 = importFromZip 覆盖行分支，断言按源码
// 形态钉直读，不设无消费出口）──
// 形制照 MessageBranchDb.replaceMessageUnit：一个 IMMEDIATE 事务内完成「先取旧附件 id 与
// 本地路径 → 删 attachment_refs（图侧引用随资源行同亡，空集跳过）→ 删 message_attachments
// 元数据行 → INSERT OR REPLACE 替换消息行 → commit」，返回作废附件的本地路径集，**文件由
// 调用方 commit 之后删**（回滚不得已删文件红线——事务回滚则行与元数据同回滚、文件不动，
// 无「消息已替换但旧附件未作废」的半成态）。
// ★ 列过滤 / 值域映射 / titleSource 补值仍在调用方逐行组装（本函数只收「事务 + 附件作废 +
// 替换落库」这一段，不复制任何映射逻辑，两处漂移面为零）。SQL 经 Transaction.execute 执行
//（Transaction 对象无 executeSql——d.ts 实读方法集）。
// ★ 单行失败原样上抛（rollback 归 catch），调用方按行级失败分账计 rowFailures。
async function replaceImportedMessageUnit(db: relationalStore.RdbStore, messageId: string,
  names: string[], values: Array<relationalStore.ValueType>): Promise<string[]> {
  // ★ 2026-09-29 写串行链入链
  return runWriteQueued('replaceImportedMessageUnit', async (): Promise<string[]> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      // 旧附件收集（事务内读——与写入同一快照；先取路径再删行）
      const oldResult: relationalStore.ResultSet = await tx.querySql(
        'SELECT id, localPath FROM message_attachments WHERE messageId = ?', [messageId]);
      const oldIds: string[] = [];
      const localPaths: string[] = [];
      try {
        while (oldResult.goToNextRow()) {
          oldIds.push(oldResult.getString(oldResult.getColumnIndex('id')));
          localPaths.push(oldResult.getString(oldResult.getColumnIndex('localPath')));
        }
      } finally {
        oldResult.close();
      }
      if (oldIds.length > 0) {
        await tx.execute('DELETE FROM attachment_refs WHERE attachmentId IN (' +
          oldIds.map((_id: string): string => '?').join(',') + ')', oldIds);
        const attachPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('message_attachments');
        attachPredicates.in('id', oldIds);
        await tx.delete(attachPredicates);
      }
      const placeholders: string = names.map((_n: string): string => '?').join(',');
      await tx.execute(
        `INSERT OR REPLACE INTO messages (${names.join(',')}) VALUES (${placeholders})`, values);
      await tx.commit();
      return localPaths;
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// ── 覆盖重置的图侧残留清理 ──

// 被覆盖写回非 graph 态的会话，清空图侧五行回到干净 legacy 起点（★ REPLACE 整行替换不清理
// 图侧行，残留 branches 会成幽灵分支进面板、残留 bindings/refs 会在重建后重复——原「归一后
// migrating / 追加式迁移器重建」叙述随迁移机制退役失实）。messages 图列无需动：REPLACE 整行
// 已把图身份列落默认值。逐会话单事务，失败留痕跳过（「部分成功不回滚」口径——孤儿留存不劣于
// 导入前）；删除面与 importGraphDomain 事务内清理段同族（attachment_refs → tool_facts（经
// runs）→ generation_runs → summary_bindings → branches）。
// ★ 守卫：本函数在**图域导入之后**调用——备份若同时携带该会话的 graph.json，图域导入已把行
// 重建并置回 graph 态，此时不得再清图行（清了 = 有标无图）。逐会话现读 migrateState，已
// graph 者跳过；读失败按原口径继续清（不吞主职责）
async function purgeLegacyResetGraphRows(rdb: relationalStore.RdbStore,
  convIds: string[]): Promise<void> {
  for (const cid of convIds) {
    let currentState: string = '';
    try {
      const stateRs: relationalStore.ResultSet = await rdb.querySql(
        'SELECT migrateState FROM conversations WHERE id = ?', [cid]);
      try {
        if (stateRs.goToNextRow()) {
          currentState = stateRs.getString(stateRs.getColumnIndex('migrateState'));
        }
      } finally {
        stateRs.close();
      }
    } catch (e) {
      // 读不出就按非 graph 处理（与收集时判据一致）——清理失败另有逐会话留痕，不在此吞
      currentState = '';
    }
    if (currentState === CONV_STATE_GRAPH) {
      continue;
    }
    // ★ 2026-09-29 写串行链入链（态读段留链外；失败留痕跳过语义不变——catch 在 work 内）
    await runWriteQueued('purgeLegacyResetGraphRows', async (): Promise<void> => {
      rdb.beginTransaction();
      try {
        await rdb.executeSql('DELETE FROM attachment_refs WHERE conversationId = ?', [cid]);
        await rdb.executeSql('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
          'generation_runs WHERE conversationId = ?)', [cid]);
        await rdb.executeSql('DELETE FROM generation_runs WHERE conversationId = ?', [cid]);
        await rdb.executeSql('DELETE FROM summary_bindings WHERE conversationId = ?', [cid]);
        await rdb.executeSql('DELETE FROM branches WHERE conversationId = ?', [cid]);
        rdb.commit();
      } catch (e) {
        rdb.rollBack();
        hilog.warn(DOMAIN, TAG, '旧格式覆盖会话 %{public}s 的图侧残留清理失败（孤儿留存，' +
          '不劣于导入前）：%{public}s', cid, (e as Error).message);
      }
    });
  }
}

// ── 密钥档读取与回填（导入侧）──

// 密钥档读取：无该文件 = 不含密钥档（返 null，不问口令）；有则先要口令再解密。口令为空或
// 用户取消 → 抛「已取消导入」（调用方静默——正常取消路径）；口令错误/文件被篡改 =
// ProviderShare 中文提示上抛（GCM 认证失败，两情形同一提示）
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
  const out: BackupSecrets = { providers: [], engines: [], httpCredentials: [] };
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
  // HTTP 凭据明文（凭据登记 #6）：解析与回填在 HttpCredBackup 域件；旧备份（无本字段）不产
  // 条目——元数据侧照常由偏好恢复，值留空等重填
  out.httpCredentials = parseHttpCredSecrets(rec['httpCredentials']);
  return out;
}

// 密钥档回填结果：engineWritten = 是否写过引擎明文（供调用方决定要不要跑 hasKey 对账）；
// failures = 逐条容错累计的失败条数（进 ImportSummary.secretFailures，UI 分档呈报）
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
// ★ 逐条容错：回填发生在各表与偏好全部落库**之后**，一条失败整体上抛会让 UI 报「恢复失败」
// 而数据其实已全部恢复——改与表循环同口径：单条 Asset/RDB 失败计数跳过不炸整批。引擎「读本机
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
  // HTTP 凭据回填（凭据登记 #6）：命中判定 / 本机明文优先 / 缓存失效三段全在
  // HttpCredBackup.applyHttpCredSecrets，失败条数并入本链失败计数（逐条容错不炸整批）
  failures += await applyHttpCredSecrets(secrets.httpCredentials);
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
