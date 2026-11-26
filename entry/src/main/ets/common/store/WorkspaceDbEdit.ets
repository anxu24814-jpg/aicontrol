// 工作区文本编辑落库编排（任务书-工作区文件编辑工具-20261003 §六 S2）：
// workspace_edit 工具的 store 层编排——链内现读盘上内容 → 三级级联匹配 → 大小/容量闸 →
// 写回原文件 → 行更新（只动 size/updatedAt）。为何独立成件而非落 WorkspaceDb.ets（照
// WorkspaceDbXlsx 先例申报）：WorkspaceDb 剔头 1171+ 行已越宪法 1200 硬线软区上沿，并入即
// 越硬线；依赖方向 ChatDb → WorkspaceDbEdit → WorkspaceDb 单向（复用其查询与文件 IO 口），
// WorkspaceDb 不反向引本件，无环。
// · 写事务入全局写链（任务书硬约束 1）：「读盘 → 匹配 → 写盘 → 行更新」全段在
//   runWriteQueued 链节内——并发工具轮同一文件两编辑因此串行，后到者链内现读重匹配；
//   先读后编硬门在链外（ToolWorkspace 执行器的行为门，本件不碰 WorkspaceReadState）。
// · 闸与次序照 write 路形态（任务书硬约束 3）：名称闸 + 显示名清洗 sanitize + (dir,name)
//   定位（零/多/文件夹/非文本四态防线）+ 子文件夹段冲突与目录链检查（创建面防线对异常
//   数据态的防御位——正常态文件行在场即不可达）+ 三闸（E13 折中大小闸 + 件数/总量两闸）+
//   写序铁律「先落文件 → 后写行」+ 行写失败不自清（旧文件本就有主，照 write 覆盖路）。
// · 编辑不改归属：id / localPath / dir / name / source / conversationId 全不动，只更新
//   size 与 updatedAt；跨会话覆盖注记（第四路）在成功返回段置位（判据单源
//   workspaceOverwriteKindOf）。
// · 结果接口 WorkspaceEditOutcome 携 beforeLineCount / afterLineCount（编辑前后全文行数，
//   回执 A/B 值——两值只在本件在手〔链内读过全文〕，任务书 §五「两值皆在手零算法成本」
//   的执行面；执行笔对 §六接口清单的偏离申报见变更记录）。
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { WorkspaceFileRow, isWorkspaceDirRow, sanitizeWorkspaceName,
  workspaceNameRejectReason, workspaceDirRejectReason, workspaceDirChainReject,
  workspaceCapacityReason, workspaceKindLabel,
  relativeWorkspacePath,
  WORKSPACE_WRITE_MAX_BYTES, WORKSPACE_ROWS_READ_MAX } from '../WorkspaceUtil';
// ★ 覆盖注记族随回执组装域外迁 WorkspaceReply，判据单源改自新件引
import { workspaceOverwriteKindOf } from '../WorkspaceReply';
import { runWriteQueued } from './DbWriteQueue';
import { queryWorkspaceFilesByName, queryWorkspaceFiles, queryWorkspaceTotal,
  dirChildSegments, physicalWorkspaceDirExists, workspaceFilesDir,
  readWorkspaceFileText, writeWorkspaceText } from './WorkspaceDb';
import { replaceWorkspaceText, workspaceEditLineCount, workspaceEditSizeGateReason,
  workspaceEditNotFoundText, workspaceEditAmbiguousText } from '../WorkspaceEditUtil';

// 编辑结果（ok=false 时数值恒零/空串；ok=true 携回执与读态刷新所需全量——fileId/sizeBytes/
// updatedAt 供执行器 markWorkspaceRead 重登记「连改两处不被自己的首次编辑判过期」）
export interface WorkspaceEditOutcome {
  ok: boolean;
  errorText: string;
  replacements: number; // ok=true：实际替换处数
  strategy: string; // ok=true：命中级名（回执分精确/宽容两态）
  sizeBytes: number; // ok=true：编辑后字节数
  displayName: string; // ok=true：行显示名（回执按它报）
  fileId: string; // ok=true：行 id（读态重登记键）
  updatedAt: number; // ok=true：行新时间戳（读态重登记快照）
  beforeLineCount: number; // ok=true：编辑前全文行数（回执 A 值）
  afterLineCount: number; // ok=true：编辑后全文行数（回执 B 值）
  // 覆盖注记档（★ 跨会话覆盖提醒第四路）：编辑行归属非本会话时的注记档——判据单源
  // workspaceOverwriteKindOf；同会话/编辑失败态缺省 undefined（空串不注记）
  overwriteKind?: string;
}

const editFailed = (text: string): WorkspaceEditOutcome => ({ ok: false, errorText: text,
  replacements: 0, strategy: '', sizeBytes: 0, displayName: '', fileId: '',
  updatedAt: 0, beforeLineCount: 0, afterLineCount: 0 });

// 定位文案（与 read 执行器同形——E3/E4/E5；★ 单源导出：执行器链外前置定位复用同三句，
// 禁两处抄写；零命中不给文件夹升级指引，模型在编辑语境要的是重查文件名不是进目录）
export function editNoHitText(dir: string, displayName: string): string {
  return '工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
    '没有名为「' + displayName + '」的文件。请先用 workspace_list 查看该目录里的文件名。';
}

export function editMultiHitText(dir: string, displayName: string): string {
  return '工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
    '存在多个名为「' + displayName + '」的文件（数据异常），无法确定编辑哪一份。' +
    '请用户在 设置 → 文件工作区 中删除重复文件。';
}

export function editIsDirText(name: string): string {
  return '「' + name + '」是文件夹，不是文件。要看里面的内容，把 ' + name +
    ' 填入 dir 调用 workspace_list。';
}

// E6 非文本档文案（类型名单源 workspaceKindLabel——doc/image/other 三档都不可编辑）
export function editKindNotEditableText(name: string, kind: string): string {
  return '「' + name + '」是' + workspaceKindLabel(kind) +
    '文件，不能编辑内容。要查看内容用 workspace_read，要修改请让用户改用上传等方式处理。';
}

// 编辑文本文件（workspace_edit 工具唯一落库口；链外先读后编硬门与 E7/E8 参数闸在执行器侧）：
// 全流程入 runWriteQueued 写串行链
export function editWorkspaceTextFile(db: relationalStore.RdbStore, dir: string, rawName: string,
  oldText: string, newText: string, replaceAll: boolean,
  conversationId: string): Promise<WorkspaceEditOutcome> {
  return runWriteQueued('editWorkspaceText', async (): Promise<WorkspaceEditOutcome> => {
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return editFailed(dirReject);
    }
    const nameReject: string = workspaceNameRejectReason(rawName);
    if (nameReject !== '') {
      return editFailed(nameReject);
    }
    const displayName: string = sanitizeWorkspaceName(rawName);
    // 链内现定位（E3/E4/E5/E6——执行器链外查过的此处重查：链排队期间的并行删除/改名在此收敛）
    const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(db, dir, displayName);
    if (matches.length === 0) {
      return editFailed(editNoHitText(dir, displayName));
    }
    if (matches.length > 1) {
      return editFailed(editMultiHitText(dir, displayName));
    }
    const row: WorkspaceFileRow = matches[0];
    if (isWorkspaceDirRow(row)) {
      return editFailed(editIsDirText(displayName));
    }
    if (row.kind !== 'text') {
      return editFailed(editKindNotEditableText(displayName, row.kind));
    }
    // 子文件夹段冲突 + 目录链逐段 + 物理探测（write 路同款防线——编辑正常态不可达的防御位：
    // 行已在场则同名文件夹段/前缀段撞文件行/目标位置物理目录三者皆为异常数据态，照 write
    // 形态保留；全表一次查两检查共用，禁 SQL LIKE〔dir 段合法含 % _ 通配注入面〕）
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    if (dirChildSegments(allRows, dir).indexOf(displayName) >= 0) {
      return editFailed('该位置已有同名文件夹，请换一个名称或先删除该文件夹。');
    }
    const chainReject: string = workspaceDirChainReject(allRows, dir);
    if (chainReject !== '') {
      return editFailed(chainReject);
    }
    if (workspaceFilesDir() !== '' && physicalWorkspaceDirExists(workspaceFilesDir() + '/' +
      relativeWorkspacePath(dir, displayName))) {
      return editFailed('该位置已有同名文件夹，请换一个名称或先删除该文件夹。');
    }
    // E15 工作区目录未就绪（新增串——现库无此串，照同族句式）
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return editFailed('工作区目录未就绪，无法编辑文件');
    }
    // 链内现读（E14 读失败中文透传）
    const absPath: string = filesDir + '/' + row.localPath;
    let content = '';
    try {
      content = readWorkspaceFileText(absPath);
    } catch (e) {
      return editFailed((e as Error).message);
    }
    // 三级级联匹配（E9 零命中 / E10 多命中在结果态映射）
    const result = replaceWorkspaceText(content, oldText, newText, replaceAll);
    if (result.status !== 'ok') {
      if (result.status === 'ambiguous') {
        return editFailed(workspaceEditAmbiguousText(displayName));
      }
      if (result.status === 'empty') {
        // 防御位（E7 在执行器前置闸，正常链路不达）
        return editFailed('要替换的原文不能为空。请从 workspace_read 的结果里选择要修改的内容。');
      }
      return editFailed(workspaceEditNotFoundText(displayName));
    }
    // 空串短路（同 WorkspaceDb.write 路——本地 d.ts 明示 encodeInto
    // 空串入参返回 undefined，读 .length 即 TypeError；edit 全文替换为空是合法路径）
    const byteLen: number = result.updated === '' ? 0 :
      util.TextEncoder.create('utf-8').encodeInto(result.updated).length;
    // 三闸：E13 折中大小闸（编辑产物 ≤ max(1MB, 原文件 size)）+ 容量两闸（件数按既有行
    // 放行、总量按「现总量 − 旧 size」折算——编辑不增件数）
    const sizeGate: string = workspaceEditSizeGateReason(byteLen, row.size,
      WORKSPACE_WRITE_MAX_BYTES);
    if (sizeGate !== '') {
      return editFailed(sizeGate);
    }
    const total = await queryWorkspaceTotal(db);
    const capacityGate: string = workspaceCapacityReason(byteLen, total.count - 1,
      total.bytes - row.size);
    if (capacityGate !== '') {
      return editFailed(capacityGate);
    }
    // 写序铁律：先落文件（truncate 覆写——内容长短可变）→ 后写行；行写失败不自清
    //（旧文件本就有主，照 write 覆盖路——库行与文件的不一致由用户重试收敛）
    try {
      writeWorkspaceText(absPath, result.updated, true);
    } catch (e) {
      return editFailed('文件写入失败：' + (e as Error).message);
    }
    const now: number = Date.now();
    const bucket: relationalStore.ValuesBucket = { 'size': byteLen, 'updatedAt': now };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('workspace_files');
    predicates.equalTo('id', row.id);
    try {
      await db.update(bucket, predicates);
    } catch (e) {
      return editFailed('工作区记录更新失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', replacements: result.replacements,
      strategy: result.strategy, sizeBytes: byteLen, displayName: displayName,
      fileId: row.id, updatedAt: now,
      beforeLineCount: workspaceEditLineCount(content),
      afterLineCount: workspaceEditLineCount(result.updated),
      // 覆盖注记档（跨会话覆盖提醒第四路）：判据只在这条成功返回段置位
      overwriteKind: workspaceOverwriteKindOf(row.conversationId, conversationId) };
  });
}
