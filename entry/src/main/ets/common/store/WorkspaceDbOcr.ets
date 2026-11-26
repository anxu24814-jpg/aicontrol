// 工作区识别文字存储域（方案-工作区识别文字-20261004 §3.1）：workspace_files
// 表 ocr 六列（v53）的读写口 + 指纹/状态纯函数。
// · 为何独立成件而非并入 WorkspaceDb（反碎片申报照 WorkspaceDbManage / WorkspaceDbTmp 先例）：
//   ①彼件剔头已越宪法 1200 硬线（变更记录一千三百三十二节在案续期），「越硬线新域不并入」
//   先例由其头注释与 DirOrder/Tmp/Edit/Xlsx/Manage 五拆分件自立；②本域与排序（DirOrder）/
//   编辑编排（Edit）/ 临时区（Tmp）/ xlsx（Xlsx）/ 管理页三写口（Manage）职责均不属，并入
//   任何既有拆分件都是「XX 的一部分」式错缝；③工作区 store 域拆分件已超 10（反碎片下限④），
//   本拆的额外理由 = 硬线条款强制（主件禁加实质代码，方案 §四-禁）。
// · 依赖方向（拆分件纪律，零环）：ChatDb → 本件 → DbWriteQueue 单向；本件不 import ChatDb、
//   不 import WorkspaceDb（六列读写自持 SQL，与主件零耦合）；页面侧不经本件——一律走
//   ChatDb 同名委托口。
// · ★ 覆盖即清红线（方案 §3.1，行为判据）：本件的 UPDATE 是**唯一**写 ocr 列的口；六列
//   **禁写进任何 insert/upsert 列清单**——同名覆盖走 upsertWorkspaceRow 的 INSERT OR REPLACE
//   未列列重置默认 ⇒ 覆盖天然清掉识别文本（状态回 none）。断言守（assert-workspace-domain
//   「覆盖即清」组）。
// · ★ 指纹判据（纯函数单源 ocrStateOf，断言直跑）：有效 = ocrText !== '' && ocrFileMtime ===
//   当前 stat.mtime && ocrFileSize === 当前 stat.size。指纹取**识别起始时刻**的 fs.statSync
//   （识别期间文件被换 ⇒ 完成后立即判过期，防旧版本文本配新文件）；mtime 入库形态 = 秒 ×1000
//   转 ms（本机 fs.Stat.mtime 为秒，WorkspaceDb 对账同款换算）。**禁用行 updatedAt 做指纹**
//   ——改名/移动会刷行 updatedAt（WorkspaceDb :825-829/:865-878/:977/:1010/:1026 实锤）而
//   内容未变。
// · 状态派生四态（不落状态列）：none（文本空）/ fresh（指纹命中）/ stale（文本在指纹不命中）
//   + 叠加位 edited（ocrEditedAt > 0，消费方自判）。
// · 进行中态不落库：识别中注册表 = 进程内内存 Set（单源在 WorkspaceOcrFlow.ets），杀应用即
//   消失——本件零涉及（防「识别中态落库」负向面）。
import { relationalStore } from '@kit.ArkData';
import { runWriteQueued } from './DbWriteQueue';
import { WorkspaceFileRow } from '../WorkspaceUtil';

// 识别记录（workspace_files 表 ocr 六列投影；行不存在 = null）
export interface WorkspaceOcrRecord {
  ocrText: string; // 识别文本（'' = 未识别）
  ocrEngine: string; // 产出引擎名：'system'|'builtin'|'model' | 文档解析引擎名
  ocrAt: number; // 识别完成时刻（ms）
  ocrFileMtime: number; // 识别起始时刻的文件 mtime（ms）
  ocrFileSize: number; // 识别起始时刻的文件大小（字节）
  ocrEditedAt: number; // 用户校对保存时刻（ms；0 = 未校对）
}

// 状态基态三值（叠加位 edited = record.ocrEditedAt > 0，消费方自判；DocParseState 同款
// 字面量联合形态）
export type WorkspaceOcrState = 'none' | 'fresh' | 'stale';

// 指纹/状态派生（纯函数，断言直跑；判据见头注释）：record null（行不存在）与文本空同归
// none——「未识别」与「识别对象已亡」对读侧同语义（读路兜底当场识别）
export function ocrStateOf(record: WorkspaceOcrRecord | null, curMtime: number,
  curSize: number): WorkspaceOcrState {
  if (record === null || record.ocrText === '') {
    return 'none';
  }
  return record.ocrFileMtime === curMtime && record.ocrFileSize === curSize ?
    'fresh' : 'stale';
}

// 来源标注三态（回执句单源，方案 §3.4-5；消费方 = ToolWorkspace 读路回执）：fresh 叠加
// edited = 经用户校对；fresh = 预识别；其余（当场识别路）= 现状句形（ composeWorkspaceImageReply
// ocr_text 形态既有文案承载，本函数不参与）
export function workspaceOcrSourceLabel(state: WorkspaceOcrState, edited: boolean): string {
  if (state === 'fresh') {
    return edited ? '预识别文字（经用户校对）' : '预识别文字';
  }
  return '当场识别文字';
}

// 单行六列读（行不存在 = null；不进任何列表投影——列表负载零变化，方案 §2.4）
export async function queryWorkspaceOcr(db: relationalStore.RdbStore,
  id: string): Promise<WorkspaceOcrRecord | null> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT ocrText, ocrEngine, ocrAt, ocrFileMtime, ocrFileSize, ocrEditedAt ' +
    'FROM workspace_files WHERE id = ?', [id]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    return {
      ocrText: result.getString(result.getColumnIndex('ocrText')),
      ocrEngine: result.getString(result.getColumnIndex('ocrEngine')),
      ocrAt: result.getLong(result.getColumnIndex('ocrAt')),
      ocrFileMtime: result.getLong(result.getColumnIndex('ocrFileMtime')),
      ocrFileSize: result.getLong(result.getColumnIndex('ocrFileSize')),
      ocrEditedAt: result.getLong(result.getColumnIndex('ocrEditedAt'))
    };
  } finally {
    result.close();
  }
}

// 单行全列读（★ 识别文字页重识别的行载荷读口——识别编排 startWorkspaceOcr 需要 name/mime/
// size/localPath；行不存在 = null。归本件而不进 WorkspaceDb：主件越硬线禁加实质代码，
// 本读口是识别域的现检/重识别专用面）
export async function queryWorkspaceFileRowById(db: relationalStore.RdbStore,
  id: string): Promise<WorkspaceFileRow | null> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, name, dir, kind, mime, size, localPath, source, conversationId, ' +
    'ownerAssistantId, createdAt, updatedAt, sortOrder FROM workspace_files WHERE id = ?', [id]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    return {
      id: result.getString(result.getColumnIndex('id')),
      name: result.getString(result.getColumnIndex('name')),
      dir: result.getString(result.getColumnIndex('dir')),
      kind: result.getString(result.getColumnIndex('kind')),
      mime: result.getString(result.getColumnIndex('mime')),
      size: result.getLong(result.getColumnIndex('size')),
      localPath: result.getString(result.getColumnIndex('localPath')),
      source: result.getString(result.getColumnIndex('source')),
      conversationId: result.getString(result.getColumnIndex('conversationId')),
      ownerAssistantId: result.getString(result.getColumnIndex('ownerAssistantId')),
      createdAt: result.getLong(result.getColumnIndex('createdAt')),
      updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
      sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
    };
  } finally {
    result.close();
  }
}

// 有识别文本的行 id 集（管理页行尾菜单两态标签的轻量位——**全文不进投影**，只投影 id；
// 方案 §3.2-1）
export async function queryWorkspaceOcrHasText(db: relationalStore.RdbStore,
  ids: string[]): Promise<string[]> {
  const hits: string[] = [];
  if (ids.length === 0) {
    return hits;
  }
  // 普通数组拷贝（@State 观察代理禁直传 in()——坑6 家族；调用方多传普通数组时零拷贝语义）
  const plain: string[] = [];
  for (const id of ids) {
    plain.push(id);
  }
  // 按批切分：行集上限 4000（WORKSPACE_ROWS_READ_MAX）下识别对象行
  // 可达千级，SQLite 变量上限 999 时单条 in() 必抛——catch 降级面会让已识别行标签静默
  // 回退「识别文字」；批 500 留余量，命中合并保序无关（消费方只做 Set 判存在）
  const batch: number = 500;
  for (let start: number = 0; start < plain.length; start += batch) {
    const slice: string[] = plain.slice(start, start + batch);
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('workspace_files');
    predicates.in('id', slice);
    predicates.notEqualTo('ocrText', '');
    const result: relationalStore.ResultSet = await db.query(predicates, ['id']);
    try {
      while (result.goToNextRow()) {
        hits.push(result.getString(result.getColumnIndex('id')));
      }
    } finally {
      result.close();
    }
  }
  return hits;
}

// 识别结果落库（识别链唯一写口；入全局写链）：写 ocrText/ocrEngine/ocrAt 与指纹两列，
// **ocrEditedAt 归 0**（新识别文本未经校对——重新识别覆盖旧校对由调用方在覆盖前自行确认，
// 方案 §3.3）；不动 updatedAt（识别不改变列表时间序）。返回 false = 行已删（幽灵写）——
// 调用方静默丢弃，不重试不报错（方案 §3.2-5：识别中允许删除该文件）
export function saveWorkspaceOcrQueued(db: relationalStore.RdbStore, id: string, text: string,
  engine: string, fileMtimeMs: number, fileSize: number): Promise<boolean> {
  return runWriteQueued('saveWorkspaceOcr', async (): Promise<boolean> => {
    const bucket: relationalStore.ValuesBucket = {
      'ocrText': text,
      'ocrEngine': engine,
      'ocrAt': Date.now(),
      'ocrFileMtime': fileMtimeMs,
      'ocrFileSize': fileSize,
      'ocrEditedAt': 0
    };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('workspace_files');
    predicates.equalTo('id', id);
    const changes: number = await db.update(bucket, predicates);
    return changes > 0;
  });
}

// 校对保存（识别文字页返回链唯一写口；入全局写链）：只写 ocrText 与 ocrEditedAt = now，
// **不动指纹列**（校对不改变「文本对应哪版文件」——文件再变仍判 stale，方案 §3.1）；
// 不动 updatedAt。返回 false = 行已删（幽灵写），调用方静默
export function saveWorkspaceOcrEditQueued(db: relationalStore.RdbStore, id: string,
  text: string): Promise<boolean> {
  return runWriteQueued('saveWorkspaceOcrEdit', async (): Promise<boolean> => {
    const bucket: relationalStore.ValuesBucket = {
      'ocrText': text,
      'ocrEditedAt': Date.now()
    };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('workspace_files');
    predicates.equalTo('id', id);
    const changes: number = await db.update(bucket, predicates);
    return changes > 0;
  });
}
