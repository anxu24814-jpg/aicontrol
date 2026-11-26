// 工作区 xlsx 写出落库编排（任务书-工作区文件格式支持 · format）：xlsx 路
// 的 store 层编排——dir/名称/ext 三闸 + (dir,name) 同名定位与三层把守 + 三闸（单件/件数/
// 总量）+ 临时件拷入物理名 + 行写入/更新 + 失败自清。产出核（五部件构造与打包）在
// WorkspaceXlsx.ets（纯构建核，本件不依赖它——调用方 executor 先产出再进本编排）。
// · ★ 为什么独立成件而非落 WorkspaceDb.ets（任务书 §3 原点位，执行笔偏离申报）：开工实测
//   WorkspaceDb 剔头 1171 行（folders 笔扩后），本编排约 +110 行 = 1281 越宪法 1200 硬线
//   ——「对越线文件的实质改动须先把本次改动所属功能域拆到独立件再动手」，照
//   ToolContracts 自 ToolTypes 搬迁先例（宪法硬线条款触发）落独立件；反碎片下限②「为何
//   不能并入」= 并入即越硬线。依赖方向 WorkspaceDbXlsx → WorkspaceDb 单向（复用其查询与
//   铸造函数），WorkspaceDb 不反向引本件，无环。
// · ★ 次序注释义务（与文本路的有意分叉）：saveWorkspaceTextFile 是「先闸后写」（配额判定
//   先于写文件——文本字节数入参自带）；本函数是「先产后闸」——xlsx 是二进制，大小须压缩
//   打包后 stat 才可知（产物由 executor 先行生成，temp 路径入参），三闸判定只能在产物之后。
//   三闸判据与常量仍单源 WorkspaceUtil 零抄值。
// · 写序铁律同域：先落文件 → 后写行；行写失败自清刚拷文件（仅新建路——覆盖路旧行仍在，
//   自清会毁用户旧文件）；删临时件在拷贝成功后（executor 成败两路各删一次防御——本函数
//   成功路删、失败路的闸拒绝面由 executor 兜删）。
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { WorkspaceFileRow, buildWorkspaceRow, extOfWorkspaceName,
  relativeWorkspacePath, workspaceDirChainReject, workspaceDirRejectReason,
  workspaceNameRejectReason, sanitizeWorkspaceName, workspaceWriteGateReason,
  WORKSPACE_ROWS_READ_MAX } from '../WorkspaceUtil';
// ★ 覆盖注记族随回执组装域外迁 WorkspaceReply，判据单源改自新件引
import { workspaceOverwriteKindOf } from '../WorkspaceReply';
import { runWriteQueued } from './DbWriteQueue';
import { queryWorkspaceFilesByName, queryWorkspaceFiles, queryWorkspaceTotal,
  dirChildSegments, ensureWorkspaceDir, ensureWorkspaceDirRows,
  physicalWorkspaceDirExists, workspaceFilesDir, insertWorkspaceRow,
  WorkspaceSaveOutcome } from './WorkspaceDb';

// 保存 xlsx（workspace_write_xlsx 工具唯一落库口；tempPath = WorkspaceXlsx.buildXlsxToTemp
// 产物且已过 executor 反读自检）：全流程入 runWriteQueued 写串行链（查写两段原子化纪律）。
// 返回 WorkspaceSaveOutcome——回执名取 displayName（清洗后落库名，防名漂移）
export function saveWorkspaceXlsxFile(db: relationalStore.RdbStore, rawName: string,
  tempPath: string, source: string, conversationId: string,
  ownerAssistantId: string, dir: string = ''): Promise<WorkspaceSaveOutcome> {
  return runWriteQueued('saveWorkspaceXlsx', async (): Promise<WorkspaceSaveOutcome> => {
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return { ok: false, errorText: dirReject, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const reject: string = workspaceNameRejectReason(rawName);
    if (reject !== '') {
      return { ok: false, errorText: reject, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const displayName: string = sanitizeWorkspaceName(rawName);
    // ext 强校验：本口只收 xlsx（产出的就是 xlsx 包；名不带 .xlsx = 模型用错工具名）
    if (extOfWorkspaceName(displayName) !== 'xlsx') {
      return { ok: false, errorText: '文件名必须以 .xlsx 结尾。请检查文件名后重试。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    // 同名匹配（覆盖策略同文本路：唯一命中覆盖 / 零命中新建 / 多命中防线报错）
    const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(db, dir, displayName);
    if (matches.length > 1) {
      return { ok: false,
        errorText: '工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') + '存在多个名为「' +
          displayName + '」的文件（数据异常），无法保存。请用户在 设置 → 文件工作区 中删除重复文件。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const existing: WorkspaceFileRow | undefined = matches.length === 1 ? matches[0] : undefined;
    // 子文件夹段名冲突 + 目录链逐段 + 物理探测（三层把守，与文本路同款单源判据；全表一次
    // 查两检查共用，禁 SQL LIKE——dir 段合法含 % _ 通配注入面）
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    if (dirChildSegments(allRows, dir).indexOf(displayName) >= 0) {
      return { ok: false,
        errorText: '该位置已有同名文件夹，请换一个名称或先删除该文件夹。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const chainReject: string = workspaceDirChainReject(allRows, dir);
    if (chainReject !== '') {
      return { ok: false, errorText: chainReject, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    if (workspaceFilesDir() !== '' && physicalWorkspaceDirExists(workspaceFilesDir() + '/' +
      relativeWorkspacePath(dir, displayName))) {
      return { ok: false,
        errorText: '该位置已有同名文件夹，请换一个名称或先删除该文件夹。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    // 产物大小（压缩后准确值——「先产后闸」次序的理由，见头注释）与三闸
    let byteLen = 0;
    try {
      byteLen = fs.statSync(tempPath).size;
    } catch (e) {
      return { ok: false, errorText: '表格临时文件读取失败：' + (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const total = await queryWorkspaceTotal(db);
    // 覆盖路口径同文本路：count 判定按既有行放行、总量按「现总量 − 旧 size」折算
    const gateReason: string = existing !== undefined ?
      workspaceWriteGateReason(byteLen, total.count - 1, total.bytes - existing.size) :
      workspaceWriteGateReason(byteLen, total.count, total.bytes);
    if (gateReason !== '') {
      return { ok: false, errorText: gateReason, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    let dirAbs: string = '';
    try {
      dirAbs = ensureWorkspaceDir(dir);
      await ensureWorkspaceDirRows(db, dir, source, conversationId, ownerAssistantId);
    } catch (e) {
      return { ok: false, errorText: (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    if (existing !== undefined) {
      // 覆盖：沿用既有 id 与物理名（ext 同为 xlsx），拷入 → 删临时件 → 行更新
      const absPath: string = dirAbs + '/' +
        existing.localPath.substring(existing.localPath.lastIndexOf('/') + 1);
      try {
        fs.copyFileSync(tempPath, absPath);
      } catch (e) {
        return { ok: false, errorText: '文件写入失败：' + (e as Error).message,
          sizeBytes: 0, totalCount: 0, displayName: '' };
      }
      removeTempQuiet(tempPath);
      const bucket: relationalStore.ValuesBucket = {
        'size': byteLen, 'updatedAt': Date.now() };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('workspace_files');
      predicates.equalTo('id', existing.id);
      try {
        await db.update(bucket, predicates);
      } catch (e) {
        // 覆盖路不自清文件——旧文件本就有主（旧行仍在），库行与文件的不一致由重试收敛
        return { ok: false, errorText: '工作区记录更新失败：' + (e as Error).message,
          sizeBytes: 0, totalCount: 0, displayName: '' };
      }
      return { ok: true, errorText: '', sizeBytes: byteLen, totalCount: total.count,
        displayName: displayName,
        // 覆盖注记档——与文本路同款判据单源
        overwriteKind: workspaceOverwriteKindOf(existing.conversationId, conversationId) };
    }
    // 新建：铸 fileId → 拷入物理名 → 删临时件 → 写行（行写失败自清刚拷文件）
    const fileId: string = util.generateRandomUUID(true);
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, byteLen,
      source, conversationId, ownerAssistantId, Date.now(), 'doc', dir);
    const absPath: string = dirAbs + '/' +
      row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
    try {
      fs.copyFileSync(tempPath, absPath);
    } catch (e) {
      return { ok: false, errorText: '文件写入失败：' + (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    removeTempQuiet(tempPath);
    try {
      await insertWorkspaceRow(db, row);
    } catch (e) {
      try {
        fs.unlinkSync(absPath);
      } catch {
        // 自清失败留残留：「清空工作区」清整个目录兜底，不吞原始错误
      }
      return { ok: false, errorText: '工作区记录写入失败：' + (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    return { ok: true, errorText: '', sizeBytes: byteLen, totalCount: total.count + 1,
      displayName: displayName };
  });
}

// 临时件删除（best-effort——删不掉的 cacheDir 残留由系统清缓存兜底，不吞上游错误）
function removeTempQuiet(tempPath: string): void {
  try {
    fs.unlinkSync(tempPath);
  } catch {
    // 目标态静默
  }
}
