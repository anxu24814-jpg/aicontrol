// 消息序号域：messages 表 seq 列（会话内 0 起显式序号）的本域三件单源——回填纯函数
// computeSeqBackfill / 启动补号 sweep backfillMessageSeq / 写入侧分配器 nextRowSeq 与播种
// seedMessageSeq（挂点 = 启动链 ChatDb.doInit 补号之后 / 导入收尾 ExportImport，成对顺序
// 「补号 → 播种」）。★ 笔 3 的读取切换**不在本域**：读取面（四读窗口 + 翻页游标）全在
// ChatDb.ets——跨会话检索窗禁切 seq
//（见 ChatDb.searchMessagesAcross 注释）；本域职责 = 把 seq 列写成权威序，读取侧只消费产物。
// · 新开本件（反碎片下限②）：ChatDbMigrate = schema/版本/迁移域——迁移分支不回填（回填是
//   启动幂等数据维护非迁移动作，语义不同域）；ChatDb 被改动推过 1200 硬线，正是拆分触发因。
// · 依赖方向（零环红线，坑50）：本件不 import ChatDb——库句柄由调用方作实参传入
//   （AttachmentDb 同款）；只 import @kit 系统包，顶层零外部绑定求值（断言脚本剥 import 后
//   直跑纯函数，assert-store-consistency 143/144 组）。
// · 语义红线：sweep 只写 seq 列（UPDATE 投影仅此一列，与 844 修复器改 createdAt 性质不同）；
//   seq 允许 NULL（v37 建列无约束，理由见 ChatDbMigrate v37 注释），读本列的新代码必须容忍
//   NULL。分配器零 DB 写（纯内存记账）；重试成对推进（ChatDb.advanceRetryTimestamps）写既有
//   createdAt 列 + seq 扩一列，不违本条。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runWriteQueued } from './DbWriteQueue';

const DOMAIN: number = 0x0001;
const TAG: string = 'MessageSeqDb';

// seq 补号候选会话分页大小：分页把「候选 id 列表 + 单轮处理量」压在有界范围；单会话「读行
// → 算 → 写」独立一段不跨会话累积（844 修复器同形制，无全库行缓冲）；每轮移除已补号会话 ⇒
// 自然推进**不用 OFFSET**（处理中集合在变，偏移会错位）。安全阀非性能调优（性能不许愿红线）
const SEQ_BACKFILL_CONV_PAGE: number = 200;
// 现行 seq 无值哨兵（读行侧判 NULL 用；seq 值域 0 起，-1 恒不等于任何新值 ⇒ 该行必写）
const SEQ_NONE: number = -1;
// 补号 sweep 轮次上限：正常 1~2 轮收敛（候选集单调缩小，首轮 ≤200 会话/轮 ⇒ 覆盖万级会话）；
// 超限响亮失败——把「候选集不收敛」从**永久挂起**降级为**可诊断的启动失败**（安全阀，性能不许愿）
const SEQ_BACKFILL_MAX_ROUNDS: number = 64;

// seq 补号入参行。createdAt/rowid 两列只作函数内定序依据——调用方传什么顺序都不影响产出
//（函数自带排序权威）
export interface SeqOrderRow {
  id: string;
  conversationId: string;
  createdAt: number;
  rowid: number;
}

// 补号产物行：seq = 会话内新序号（0 起）；rowid = 写库定位键——SQLite 的 TEXT PRIMARY KEY
// 不拒 NULL（非 INTEGER 主键/非 STRICT/非 WITHOUT ROWID 允许 NULL，UNIQUE 索引视多行 NULL
// 互异 ⇒ 可并存），`WHERE id = ?` 对 id IS NULL 行恒零命中；rowid 恒非 NULL 恒唯一，收敛由
// 构造保证。数组序 = 定序后行序（供真值表断言与排查读）
export interface SeqAssignedRow {
  id: string;
  seq: number;
  rowid: number;
}

// seq 回填纯函数（断言面 = assert-store-consistency 143 组真值表）：每会话按 createdAt ASC,
// rowid ASC 重排后连续赋 0,1,2,…；**排序权威在函数内**（入参行序不限，函数自己分组 + 组内
// 时间戳序 + 同毫秒 rowid 决胜）；换会话从 0 重起，互不串号。契约三条：
// · **整会话重算，非增量**——候选会话传全量行，既有 seq 一律被本函数结果覆盖（重号/缺号据此
//   自愈，候选判据见 backfillMessageSeq）；
// · **0 基**——会话内首行恒 0（分配器按 max(seq)+1 续号，基数一致）；
// · **纯**——不读库不写库、无外部绑定，同一会话重跑同值 = 幂等。
// ★ 与 ChatDb.computeTieRepairedRows 分工：那个重赋 createdAt 列（同毫秒并列），本函数只读
// 时间戳当序依据、只产出 seq 新值（**零既有列改动**）
export function computeSeqBackfill(rows: SeqOrderRow[]): SeqAssignedRow[] {
  const ordered: SeqOrderRow[] = rows.slice();
  ordered.sort((a: SeqOrderRow, b: SeqOrderRow): number => {
    if (a.conversationId !== b.conversationId) {
      return a.conversationId < b.conversationId ? -1 : 1;
    }
    return a.createdAt - b.createdAt || a.rowid - b.rowid;
  });
  const out: SeqAssignedRow[] = [];
  let currentConv: string = '';
  let nextSeq: number = 0;
  for (let i: number = 0; i < ordered.length; i++) {
    if (i === 0 || ordered[i].conversationId !== currentConv) {
      currentConv = ordered[i].conversationId;
      nextSeq = 0;
    }
    out.push({ id: ordered[i].id, seq: nextSeq, rowid: ordered[i].rowid });
    nextSeq++;
  }
  return out;
}

// ── 写入侧 seq 分配器 ──
// 记账 = 会话 id → 已铸最大值（无记账 = 未铸，首铸 0，与回填 0 基一致）。同步函数 + JS 单线程
// 不设锁；进程内唯一铸造口，DB 只是持久投影——重启/导入由 seedMessageSeq 回读真值重播种。
// ★ D1 红线（D4-1 真机实锤教训）：seq 必须在**构造行对象的同步点**铸造（与同一行的
// nextRowCreatedAt() 调用同位同序）。**禁** DB 侧赋值（INSERT 内 MAX(seq)+1 子查询）、**禁**
// await 后补铸——异步链「先查后插」完成序不可控，DB 侧赋值让 seq 按物理插入序而非因果序。
// ★ 记账**不设淘汰、不清空**（条目数上界 = 触及过的会话数，量级与「数据有界」红线相容）；
// **禁加「清理不在库会话」式淘汰**——淘汰 = 该会话下次铸造自 0 重号（重号有 sweep 兜底，
// 但不该主动制造）；会话 id 不复用，无失效条目可回收。
let allocatedSeq: Map<string, number> = new Map<string, number>();

// 下一序号（会话内 0 基递增，新会话首铸 0）。纯内存零 DB 往返——调用点必须与行对象构造同处
// 一个同步块（见上红线）。异常面：不抛（Map 读写零外部依赖）
export function nextRowSeq(conversationId: string): number {
  const next: number = (allocatedSeq.get(conversationId) ?? -1) + 1;
  allocatedSeq.set(conversationId, next);
  return next;
}

// 分配器播种（两挂点：启动链 = backfillMessageSeq **之后**；导入收尾 = importFromZip 的
// finally——导入保真写回 seq ⇒ 内存记账过期）。库侧真值 = 各会话 MAX(seq)（MAX 忽略 NULL：
// 全 NULL 会话不入记账，首铸 0，与 0 基一致）。★ 只升不降：await 窗口内仍可能有铸造（导入期
// 另发消息的极端序），取 max 保住已发出的号——代价只可能是缺号（空洞无害，sweep 照旧管辖）；
// 覆盖式会让已发出未落库的号复用 = 重号。依赖 idx_messages_conv_seq。失败上抛（启动链由
// doInit 捕获返假报初始化失败；导入侧 best-effort 留痕）
export async function seedMessageSeq(db: relationalStore.RdbStore): Promise<void> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT conversationId, MAX(seq) AS maxSeq FROM messages GROUP BY conversationId');
  let convCount: number = 0;
  try {
    while (result.goToNextRow()) {
      const maxIdx: number = result.getColumnIndex('maxSeq');
      if (result.isColumnNull(maxIdx)) {
        continue; // 全 NULL 会话（从未编号）：不入记账，首铸 0
      }
      const conversationId: string = result.getString(result.getColumnIndex('conversationId'));
      convCount++;
      const maxSeq: number = result.getLong(maxIdx);
      const held: number = allocatedSeq.get(conversationId) ?? -1;
      if (maxSeq > held) {
        allocatedSeq.set(conversationId, maxSeq);
      }
    }
  } finally {
    result.close();
  }
  hilog.info(DOMAIN, TAG, 'seq 分配器播种：库内 %{public}d 个会话已有号（记账 %{public}d 会话）',
    convCount, allocatedSeq.size);
}

// seq 回填启动 sweep（v37）：启动幂等数据维护（ChatDb 侧三 sweep 先例同族，非版本迁移——
// 迁移分支只加列建索引，回填只此一条代码路径）。库句柄由调用方传入；**只写 seq 列**。
// 候选判据两条合取（见 SQL 注释），命中即整会话重算 ⇒ 重算后 seq 互异且无 NULL ⇒ 不再命中
//（幂等，重跑零更新）。三类来源覆盖：迁移前存量行 / 分配器上线前新行（均落 NULL）/ 旧备份
// 导入行（列交集过滤落 NULL）。失败上抛留痕（P0-1 不半修 → doInit 返假 → UI 禁用发送）
// ★ 三条真机加固（根因/执行级复现/真机症状见变更记录 856 节——原实现把「回填慢或异常」一律
//   表现为**启动永久卡死**，三条各堵一个面）：
//   ①【写定位键 = rowid】TEXT PRIMARY KEY 不拒 NULL，id IS NULL 行在 `WHERE id = ?` 下恒零
//     命中，而写入计数按「值不等」递增 ⇒ 零写判据永不成立 ⇒ 每轮重取同一页 = **无限轮询**
//     （真机症状 = whenReady 永不落定、列表全空但写路径照常成功）。rowid 恒非 NULL 恒唯一，
//     收敛由构造保证（node:sqlite 夹具复现：id 定位 301 轮不收敛、rowid 2 轮收敛）。
//   ②【事务粒度 = 单会话】整 sweep 单事务时首启分钟级、中途退出整体回滚永远从零重来；逐会话
//     落库后接着上次进度推进到收敛，且候选查询恒读已提交状态。
//   ③【轮次上限】原守卫只防「整页零写」，防不住「写入计数虚增」（每轮真有写但写不中目标行）。
export async function backfillMessageSeq(db: relationalStore.RdbStore): Promise<void> {
  let convCount: number = 0;
  let written: number = 0;
  let rounds: number = 0;
  while (true) {
    rounds++;
    if (rounds > SEQ_BACKFILL_MAX_ROUNDS) {
      throw new Error('seq 补号清扫轮次超限（已 ' + rounds.toString() +
        ' 轮）：候选集未随处理收敛，疑似存在无法写入的候选会话');
    }
    // 候选轮询（分页 ≤ SEQ_BACKFILL_CONV_PAGE）：COUNT(seq) < COUNT(*) = 有 NULL 行（COUNT(列)
    // 不计 NULL）；COUNT(DISTINCT seq) < COUNT(seq) = 有重号。
    // ★ 重号也进候选（U0 实证，见变更记录「导出导入兼容三问」）：导出侧整数列 NULL→0 归一 +
    // 导入按列交集原样写回 ⇒「导出→导回」把未编号行变成一排真 0，只看 `seq IS NULL` 永不命中
    // ⇒ 会话永不自愈；与 NULL 支合起来才等于「三类来源全覆盖」。查询在事务外 = 读已提交
    // 状态（②）。
    // ★ K3 分流：graph 会话不进本 sweep——图会话 seq 随提交铸造（MessageBranchDb）、历史行迁移
    // 保值，残缺由导入链自补（图会话行被 legacy 维护改写 = K3 越界）。'graph' 字面 =
    // MessageBranchDb.CONV_STATE_GRAPH 词表值（词表冻结不漂；引常量造环坑50，字面＋回指，
    // 纪律同 ChatDbSweep）；子查询带 id IS NOT NULL = 反连接 NULL 安全（154 族不变式）
    const candidate: relationalStore.ResultSet = await db.querySql(
      'SELECT conversationId FROM messages WHERE conversationId NOT IN ' +
      '(SELECT id FROM conversations WHERE migrateState = ? AND id IS NOT NULL) ' +
      'GROUP BY conversationId ' +
      'HAVING COUNT(seq) < COUNT(*) OR COUNT(DISTINCT seq) < COUNT(seq) LIMIT ?',
      ['graph', SEQ_BACKFILL_CONV_PAGE]);
    const convIds: string[] = [];
    try {
      while (candidate.goToNextRow()) {
        convIds.push(candidate.getString(candidate.getColumnIndex('conversationId')));
      }
    } finally {
      candidate.close();
    }
    if (convIds.length === 0) {
      break; // 无候选 = 收敛（稳态：每启动一次判定查询后零写退出）
    }
    // 本轮写入计数基线（收敛守卫用，见本页处理后的判据）
    const writtenBefore: number = written;
    for (const convId of convIds) {
      // ★ 写串行链入链（启动维护期无并发者，入链零成本纯形态统一）
      await runWriteQueued('backfillMessageSeq', async (): Promise<void> => {
        db.beginTransaction();
        try {
          written += await sweepConversationSeq(db, convId);
          db.commit();
        } catch (e) {
          db.rollBack();
          throw e as Error;
        }
      });
    }
    // 收敛守卫：命中候选必有行「现值 ≠ 产出值」（NULL 与重号各至少一行），本页正常至少写
    // 1 行；整页零写而候选仍在 = 本页候选全部无法收敛（如 id 为 NULL 的损坏行 UPDATE 落空），
    // 而候选判据只看列值 ⇒ 下轮重取同一页 = **无限轮询卡死启动**。此处响亮失败（P0-1 不静默：
    // 上抛 → doInit 返假 → UI 报初始化失败禁用发送）
    if (written === writtenBefore) {
      throw new Error('seq 补号清扫未收敛：本页 ' +
        convIds.length.toString() + ' 个候选会话零写入');
    }
    convCount += convIds.length;
    hilog.info(DOMAIN, TAG, 'seq 补号清扫：第 %{public}d 轮 %{public}d 个候选会话，编号 %{public}d 行',
      rounds, convIds.length, written - writtenBefore);
  }
  hilog.info(DOMAIN, TAG, 'seq 补号清扫完成：%{public}d 个候选会话，编号 %{public}d 行，%{public}d 轮',
    convCount, written, rounds);
}

// 单会话 seq 归一并落库（返回实际写入行数）；事务由调用方按「每会话一个」粒度包裹（见②，
// 提取本函数 = 让事务边界落在调用点一眼可见处）。★ 写定位键用 rowid 而非 id（理由见①）：
// id 随行读出供 computeSeqBackfill 产出与真值表断言消费，但**不参与写库定位**；id 判 NULL 后
// 取空串（ArkTS string 非空类型，不依赖 getString 对 NULL 列的宽容度）
async function sweepConversationSeq(db: relationalStore.RdbStore, convId: string): Promise<number> {
  // 行序 = createdAt ASC, rowid ASC（排序权威在 computeSeqBackfill，此处 ORDER BY 只为读取确定性）
  const rowResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, createdAt, rowid, seq FROM messages ' +
    'WHERE conversationId = ? ORDER BY createdAt ASC, rowid ASC', [convId]);
  const rows: SeqOrderRow[] = [];
  const currentSeq: Map<number, number> = new Map<number, number>();
  try {
    while (rowResult.goToNextRow()) {
      const idIdx: number = rowResult.getColumnIndex('id');
      const rid: number = rowResult.getLong(rowResult.getColumnIndex('rowid'));
      rows.push({
        id: rowResult.isColumnNull(idIdx) ? '' : rowResult.getString(idIdx),
        conversationId: convId,
        createdAt: rowResult.getLong(rowResult.getColumnIndex('createdAt')),
        rowid: rid
      });
      const seqIdx: number = rowResult.getColumnIndex('seq');
      currentSeq.set(rid, rowResult.isColumnNull(seqIdx) ? SEQ_NONE : rowResult.getLong(seqIdx));
    }
  } finally {
    rowResult.close();
  }
  const assigned: SeqAssignedRow[] = computeSeqBackfill(rows);
  let wrote: number = 0;
  for (const row of assigned) {
      // 值未变不写（最少写：重号会话多数行本就正确只补差异行；写量 = 序号会变的行，恒远小于
      // 整会话行数——首轮全库回填除外）
    if (currentSeq.get(row.rowid) !== row.seq) {
      await db.executeSql('UPDATE messages SET seq = ? WHERE rowid = ?', [row.seq, row.rowid]);
      wrote++;
    }
  }
  return wrote;
}
