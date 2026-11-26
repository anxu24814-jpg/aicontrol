// 临时产物区纯函数域：会话粒度易失区（filesDir/workspace-tmp/<会话id>/）的目录名/限额
// 常量单源与路径派生。独立成件不并入 WorkspaceUtil：彼件已处 1200 硬线软区上沿，且临时区
// 与正式区职责缝不同（易失区不落库不对账不备份），照 WorkspaceSearchUtil 外迁先例。
// · 零 import 纪律（照 WorkspaceUtil 叶子先例）：本文件是断言直跑的纯函数叶子——IO 面
//   （扫描/计数/删除/转存）全在 store 侧 WorkspaceDbTmp.ets（ctx 捕获与 fs 在彼）；形态
//   与数据结构（WorkspaceTmpScan 等）在此、扫描实现在彼——任务书原把列举函数列在本件，
//   执行笔按零 import 纪律改判 IO 归 store 侧（偏差已登记变更记录）。
// · 临时区三不红线：不进 workspace_files 表、不进启动对账、不进备份导出——目录独立于
//   workspace 根天然隔离，负向钉守（assert-workspace-domain 300 组）。
// · 限额常量与代码工作台书 A4 对表：WORKSPACE_TMP_MAX_TOTAL_BYTES / MAX_FILE_BYTES 是
//   脚本 fs 闸（exec_code）的单源——写入方经 ScriptRunOptions 下传。
// · 入向桥闸：workspaceTmpStageGateReason 是工作区件 → 会话临时区（workspace_stage 工具）
//   的两闸判定——总量口径与本会话临时目录合计同界（与沙箱 fs 闸 root = 会话目录同口径），
//   不入本件的 IO 面。
// · 会话粒度生命周期：随会话删除级联清（ChatDb.deleteConversations 两段式）+ 管理页手动
//   清理兜底；无启动清扫（拍板否决——保「聊一半重启接力」）。

// 临时区目录名（挂 filesDir 下，与 WORKSPACE_DIR_NAME 并列的姊妹常量——目录名单源，store
// 侧禁散写字面量）
export const WORKSPACE_TMP_DIR_NAME: string = 'workspace-tmp';
// 临时区总量上限（字节；exec_code 写入方实吃——native fs 闸、ArkTS data 落件与 staging
// 三方同闸；调整 = 改值即全链生效）
export const WORKSPACE_TMP_MAX_TOTAL_BYTES: number = 256 * 1024 * 1024;
// 临时区单件上限（字节；与上传单件同档——断言以关系钉〔=== WORKSPACE_UPLOAD_MAX_BYTES〕
// 守同值，不抄值）
export const WORKSPACE_TMP_MAX_FILE_BYTES: number = 10 * 1024 * 1024;
// 单会话列举上限（件；管理页临时段下探行有界，超出截断并置 truncated 标）
export const WORKSPACE_TMP_LIST_MAX: number = 500;

// 临时区文件简报（管理页临时段行载荷；按显示名平铺——临时区内无子目录）
export interface WorkspaceTmpFileBrief {
  name: string;
  size: number;
  mtime: number;
}

// 单会话扫描结果（truncated = 越列举上限截断，UI 如实申报）
export interface WorkspaceTmpScan {
  files: WorkspaceTmpFileBrief[];
  truncated: boolean;
}

// 临时区会话组简报（管理页临时段组列表载荷；住纯叶子而非 WorkspaceDbTmp——类型供 UI 与
// ChatDb 委托层同源引用〔照 WorkspaceFileRow 住 WorkspaceUtil 的家族形态〕，且 Node 剥离
// 直跑面下「值转出接口」会悬空，接口只经本件原生 export interface 导出）
export interface WorkspaceTmpGroupBrief {
  conversationId: string;
  fileCount: number;
  bytes: number;
  lastAt: number;
}

// 临时区绝对根（filesDir + '/workspace-tmp'；filesDir 由 store 侧 ctx 捕获传入——本件
// 零 import 不持 ctx）
export function workspaceTmpDir(filesDir: string): string {
  return filesDir + '/' + WORKSPACE_TMP_DIR_NAME;
}

// 会话临时子目录绝对路径（filesDir + '/workspace-tmp/<会话id>'）
export function workspaceTmpConversationDir(filesDir: string, conversationId: string): string {
  return workspaceTmpDir(filesDir) + '/' + conversationId;
}

// 临时区两闸预检（exec_code 的 data 落件口——ArkTS 侧写入路径在落盘前过闸；判据与 native
// sandbox_fs.cpp 写入闸同构：单件闸按内容字节量、总量闸按「现占 + 新内容」；句形与 native
// 闸句逐字同源——模型两侧观感一致。返回空串 = 通过，否则为完整中文闸句）
export function workspaceTmpWriteGateReason(contentBytes: number,
  existingTotalBytes: number): string {
  if (contentBytes > WORKSPACE_TMP_MAX_FILE_BYTES) {
    return '临时区限制：单次写入 ' + contentBytes + ' 字节 超过单件上限 ' +
      WORKSPACE_TMP_MAX_FILE_BYTES + ' 字节';
  }
  if (existingTotalBytes + contentBytes > WORKSPACE_TMP_MAX_TOTAL_BYTES) {
    return '临时区限制：写入后总量将达 ' + (existingTotalBytes + contentBytes) +
      ' 字节 超过总量上限 ' + WORKSPACE_TMP_MAX_TOTAL_BYTES + ' 字节';
  }
  return '';
}

// 入向桥两闸判定（workspace_stage 用；'' = 放行）。判据引用本件两常量，禁任何字面值——
// 文案前缀「临时区限制：」与 native 两闸同族（cpp/sandbox_fs.cpp 同前缀），模型侧口径统一。
// 与 workspaceTmpWriteGateReason 同域并列、各自独立（写入闸按「单次写入」表述，
// 入向闸按「文件「X」共 N 字节」表述并给清理指引）。
export function workspaceTmpStageGateReason(name: string, sizeBytes: number,
  existingTotalBytes: number): string {
  if (sizeBytes > WORKSPACE_TMP_MAX_FILE_BYTES) {
    return '临时区限制：文件「' + name + '」共 ' + sizeBytes + ' 字节，超过单件上限 ' +
      WORKSPACE_TMP_MAX_FILE_BYTES + ' 字节，无法放入。';
  }
  if (existingTotalBytes + sizeBytes > WORKSPACE_TMP_MAX_TOTAL_BYTES) {
    return '临时区限制：放入后本会话临时区总量将达 ' + (existingTotalBytes + sizeBytes) +
      ' 字节，超过总量上限 ' + WORKSPACE_TMP_MAX_TOTAL_BYTES +
      ' 字节。请先在文件工作区管理页的临时分段清理本会话的临时文件。';
  }
  return '';
}
