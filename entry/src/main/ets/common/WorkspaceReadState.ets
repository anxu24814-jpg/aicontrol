// 工作区先读后编硬门·读态表：workspace_edit 的行为门数据面——「本会话 read 过该文件 且
// 文件自读取后未被改动」的记录与判定（E11 未读 / E12 已过期的判据源；文案在 ToolWorkspace
// 执行器侧）。
// · 零 import 叶子（照 ToolIds / WorkspaceUtil 先例）：断言直跑前提，引一次就把可求值
//   依赖带回叶子。
// · 语义边界（预期行为非缺陷）：进程重启失忆（内存态不落库）；跨会话不共用记录（键含
//   conversationId）；门是**行为门不是原子门**——门过与链内重读之间的并行窗口由「链内
//   现读匹配」兜底（编辑在写链内读当前盘上内容再匹配，门只拦「明显没读就编」）。
// · 有界（数据有界红线）：WORKSPACE_READ_STATE_MAX 上限，超限逐出最旧登记
//   （Map 插入序；重登记同键刷新插入序与快照值）；逐出后语义 = 未读。
// · 消费方：ToolWorkspace.ets（read 文本路回执成功处登记 + edit 执行前校验）；
//   write / import / xlsx 三路不刷新读态（模型刚写完要编辑时会多一步 read，
//   语义简单优先——拍板）。
export const WORKSPACE_READ_STATE_MAX: number = 64;

// 读取时快照（过期判据 = 行上现成 (size, updatedAt) 任一变化即 stale）
interface WorkspaceReadSnapshot {
  sizeBytes: number;
  updatedAt: number;
}

const readState: Map<string, WorkspaceReadSnapshot> = new Map<string, WorkspaceReadSnapshot>();

// 登记读取（键 = conversationId + '|' + fileId）：重登记刷新快照与插入序（同文件连续
// 读两段，过期判据取最后一次读取时的行值）
export function markWorkspaceRead(conversationId: string, fileId: string, sizeBytes: number,
  updatedAt: number): void {
  const key: string = conversationId + '|' + fileId;
  if (readState.has(key)) {
    readState.delete(key);
  }
  readState.set(key, { sizeBytes: sizeBytes, updatedAt: updatedAt });
  while (readState.size > WORKSPACE_READ_STATE_MAX) {
    let oldest: string | undefined = undefined;
    readState.forEach((_snap: WorkspaceReadSnapshot, k: string): void => {
      if (oldest === undefined) {
        oldest = k;
      }
    });
    if (oldest === undefined) {
      break;
    }
    readState.delete(oldest);
  }
}

// 校验读取态：'ok' = 本会话读过且 (size, updatedAt) 与登记快照一致；'missing' = 未读
//（含被逐出与跨会话）；'stale' = 读过但行值已变（编辑前后失配——含「被自己的上次编辑
// 刷新了行」之外的外部改动；编辑成功处会重登记，连改两处不被自己卡）
export function checkWorkspaceRead(conversationId: string, fileId: string, sizeBytes: number,
  updatedAt: number): string {
  const snap: WorkspaceReadSnapshot | undefined =
    readState.get(conversationId + '|' + fileId);
  if (snap === undefined) {
    return 'missing';
  }
  if (snap.sizeBytes !== sizeBytes || snap.updatedAt !== updatedAt) {
    return 'stale';
  }
  return 'ok';
}

// 撤销登记（消费预留口——如用户在管理页删除文件后清残留键；暂无调用方，接口按契约
// 齐全落地）
export function dropWorkspaceRead(conversationId: string, fileId: string): void {
  readState.delete(conversationId + '|' + fileId);
}
