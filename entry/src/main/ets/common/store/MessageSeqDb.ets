// 消息序号域（2026-09-21 消息存储机制改造笔 1，DB v37；自 ChatDb.ets 域级最小拆分；笔 2 补
// 写入侧分配器与播种）：messages 表 seq 列（会话内 0 起显式序号）的本域三件收拢本文件——
// **回填规则**（纯函数 computeSeqBackfill）与**启动补号 sweep**（backfillMessageSeq）单一
// 来源，笔 2 起再加**写入侧分配器**（nextRowSeq，全写入点单一铸造口）与**分配器播种**
// （seedMessageSeq，两挂点 = 启动链 ChatDb.doInit 的补号之后 / 导入收尾 ExportImport——
// 笔 3 起该挂点前先补号一次，两调用成对子顺序「补号 → 播种」）。
// ★ 笔 3 的读取切换**不在本域**：读取面（四读窗口 + 翻页游标）全在 ChatDb.ets——其中三个
// 单会话窗口与游标切 seq，跨会话检索窗因排序键作用域不匹配而**禁切**（见 ChatDb.
// searchMessagesAcross 注释），本域职责
// 一句话 = 把 seq 列写成权威序（回填归一 + 写入铸造 + 记账播种），读取侧只消费其产物。
// · 为什么新开本件而不并入既有件（宪法「反碎片下限」②的首问）：ChatDbMigrate.ets =
//   schema/版本/迁移域（**本笔明确迁移分支不回填**——回填是每次启动都跑的幂等数据维护，不是
//   迁移动作，语义不同域）；ChatDb.ets = 会话/消息表象主（本笔改动把它推过 1200 硬线，正是
//   本次拆分的触发原因）；AttachmentDb / UsageStatsDb / MessageVariantDb 等各为别的表主域。
// · 依赖方向（零环红线，坑50）：**本件不 import ChatDb**——库句柄由调用方（ChatDb.doInit、
//   ExportImport.importFromZip）作实参传入（AttachmentDb 同款姿势）；本件只 import @kit 系统包，
//   顶层零外部绑定求值（断言脚本剥 import 后即可直跑纯函数，见 assert-store-consistency 143/144 组）。
// · 语义红线：**sweep 只写 seq 列**（backfillMessageSeq 的 UPDATE 投影仅此一列，既有列零触碰
//   ——与 844 修复器改 createdAt 性质不同）；seq 允许 NULL（v37 建列无任何约束，理由见
//   ChatDbMigrate v37 注释），凡读本列的新代码必须容忍 NULL。★ 本条约束的是**本件 sweep 的
//   写投影**：写入侧分配器零 DB 写（纯内存记账，D2），重试成对推进（ChatDb.
//   advanceRetryTimestamps）写的是既有 createdAt 列 + seq = 既有写点扩一列，不违本条。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'MessageSeqDb';

// seq 补号 sweep 候选会话分页大小：每轮最多取 200 个候选会话。定值理由：①首启候选集 = 全库
// 会话（真机量级数十~数百会话），分页把「候选 id 列表 + 单轮处理量」压在有界范围；②单会话
// 行数才是峰值内存的决定项，而每会话的处理是「读行 → 算 → 写」独立一段、不跨会话累积（与
// 844 修复器同形制：逐会话处理、无全库行缓冲）；③每轮把已补号会话从候选集移除 ⇒ 下一轮
// 查询自然推进，**不用 OFFSET**（处理中集合在变，偏移会错位）。200 本身是「一轮读到的 id 串
// + 200 次会话内查询」的量级估计，无实测依据、不追求精确——它是安全阀不是性能调优
//（性能不许愿红线）
const SEQ_BACKFILL_CONV_PAGE: number = 200;
// 现行 seq 无值哨兵（读行侧判 NULL 用；seq 值域 0 起，-1 恒不等于任何新值 ⇒ 该行必写）
const SEQ_NONE: number = -1;
// 补号 sweep 轮次上限（2026-09-21 真机故障修复补）：正常 1~2 轮收敛（候选集随处理单调缩小，
// 首轮 ≤200 会话/轮 ⇒ 上限覆盖万级会话）；超限即响亮失败，把「候选集不收敛」这一类从
// **永久挂起**降级为**可诊断的启动失败**。定值理由与 SEQ_BACKFILL_CONV_PAGE 同款：安全阀，
// 非性能调优（性能不许愿红线）
const SEQ_BACKFILL_MAX_ROUNDS: number = 64;

// seq 补号入参行。createdAt/rowid 两列只作函数内定序依据——调用方传什么顺序都不影响产出
//（函数自带排序权威）
export interface SeqOrderRow {
  id: string;
  conversationId: string;
  createdAt: number;
  rowid: number;
}

// 补号产物行：seq = 会话内新序号（0 起）；rowid = 写库定位键（★ 2026-09-21 真机故障修复补）
// ——**不用 id 定位的理由**：SQLite 的 TEXT PRIMARY KEY 不拒 NULL（官方明载：非 INTEGER 主键 /
// 非 STRICT / 非 WITHOUT ROWID 的表允许 NULL，且 UNIQUE 索引视多行 NULL 互异 ⇒ 可并存），
// 故 `UPDATE ... WHERE id = ?` 对 id IS NULL 的行恒零行命中；rowid 恒非 NULL 恒唯一，任何行
// 都可定位，收敛由构造保证。数组序 = 定序后的行序（顺序只供真值表断言与排查读）
export interface SeqAssignedRow {
  id: string;
  seq: number;
  rowid: number;
}

// seq 回填纯函数（直跑断言面 = assert-store-consistency 143 组真值表）：把「每会话按
// createdAt ASC, rowid ASC 重排后连续赋 0,1,2,…」这条回填规则做成一个纯函数——**排序权威
// 在本函数内**（入参行序不限，函数自己按会话分组 + 组内时间戳序 + 同毫秒 rowid 决胜）；
// 换会话序号从 0 重起，会话间互不串号。
// 契约三条：
// · **整会话重算，非增量补号**——调用方对候选会话传该会话全量行，既有 seq 值一律被本函数
//   结果覆盖（重号/缺号会话据此自愈，候选判据见 backfillMessageSeq）；
// · **0 基**——会话内首行恒 0（笔 2 的分配器按「会话 max(seq)+1」续号，基数与之一致）；
// · **纯**——不读库不写库、无外部绑定，确定性输入产出确定输出（同一会话重跑同值 = 幂等）。
// ★ 与 ChatDb.computeTieRepairedRows 的分工：那个管 createdAt 列自身（同毫秒并列重赋时间
// 戳），本函数只读时间戳当序依据、只产出 seq 列的新值（**零既有列改动**）
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

// ── 写入侧 seq 分配器（2026-09-21 消息存储机制改造笔 2，D2）──
// 记账 = 会话 id → 已铸最大值（无记账 = 未铸，首铸 0——与 computeSeqBackfill 的 0 基契约一致）。
// **同步函数 + JS 单线程**（与 ChatDb.nextRowCreatedAt 同款前提，不设锁）；进程内唯一铸造口，
// DB 只是它的持久投影：进程重启由 seedMessageSeq 从库中回读真值，导入保真写回 seq 后同法重播种
//（两挂点见 seedMessageSeq）。
// ★ D1 红线（本笔第一红线；D4-1 真机实锤的教训）：seq 必须在**构造行对象的同步点**铸造——
// 与同一行的 nextRowCreatedAt() 调用同位同序。**禁** DB 侧赋值（INSERT 语句内 MAX(seq)+1 子查询）、
// **禁** await 之后再补铸：异步链中「先查后插」的完成序不可控，DB 侧赋值会让 seq 按物理插入序
// 而非因果序（正是 09-19「工具卡回放到最新消息后」与 D4-1 的缺陷形态）。
// ★ 记账生命周期（复核轮补记「为什么」，非机制改动）：**不设淘汰、不清空**——条目数上界 = 本
// 进程触及过的会话数（每条约数十字节，千会话量级仍远小于 100 KB，与宪法「数据有界」红线相容）；
// **禁加「清理不在库的会话」式淘汰**——淘汰 = 该会话下次铸造自 0 起重号，而库内该会话的行号
// 仍在（重号由启动 sweep 兜底，但不该主动制造）；会话 id 全局唯一不复用，故无失效条目可回收。
let allocatedSeq: Map<string, number> = new Map<string, number>();

// 下一序号（会话内 0 基递增，新会话首铸 0）。纯内存零 DB 往返——调用点必须与行对象构造同处
// 一个同步块（见上红线）。异常面：不抛（Map 读写零外部依赖）
export function nextRowSeq(conversationId: string): number {
  const next: number = (allocatedSeq.get(conversationId) ?? -1) + 1;
  allocatedSeq.set(conversationId, next);
  return next;
}

// 分配器播种（两挂点共用：启动链 = ChatDb.doInit 的 backfillMessageSeq **之后**；导入收尾 =
// ExportImport.importFromZip 的 finally——导入保真写回 seq ⇒ 内存记账过期，M4）。库侧真值 =
// 各会话 MAX(seq)（MAX 忽略 NULL：全 NULL 会话无行返回，不入记账，首铸 0，与整会话重算 0 基一致）。
// ★ 只升不降（合并不覆盖）：querySql 的 await 窗口内进程内仍可能有铸造（导入期另发消息的极端序），
// 取 max 保住已发出的号——代价只可能是缺号（号段有空洞语义无害，且 sweep 的重算面照旧管辖），
// 而覆盖式会让已发出未落库的号被复用 = 重号。依赖 idx_messages_conv_seq（笔 1 已建）。
// 失败上抛（调用侧各自决定语义：启动链由 doInit 捕获返假 → UI 报初始化失败；导入侧 best-effort
// 留痕——见各调用点注释）
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

// seq 回填启动 sweep（DB v37）：启动幂等数据维护第 4 件（ChatDb 侧 sweepEmptyConversations /
// markStreamingAsError / repairTiedMessageTimestamps 三先例，非版本迁移——迁移分支只加列建
// 索引，回填只此一条代码路径）。库句柄由调用方传入（见头注释依赖方向）；**只写 seq 列**。
// 候选判据两条合取（见下方 SQL 注释），命中即整会话重算 ⇒ 重算后会话内 seq 互异且无 NULL
// ⇒ 不再命中（幂等，重跑零更新）。
// 三类来源天然覆盖：迁移前存量行（建列为 NULL）/ 笔 2 上线前的新行（写入不带 = NULL）/
// 旧备份导入行（备份无 seq 字段 → 目标列交集过滤掉 → 落 NULL）。失败上抛留痕（P0-1 不半修；
// 上抛 → ChatDb.doInit 捕获返假 → UI 按「数据库初始化失败」禁用发送）
// ★ 三条真机加固（2026-09-21 故障修复补；根因/执行级复现/真机症状见变更记录 856 节——改动前
//   本函数把「回填慢或异常」一律表现为**启动永久卡死**，三条各堵一个面）：
//   ①【写定位键 = rowid】原按 `id` 定位。SQLite 的 TEXT PRIMARY KEY **不拒 NULL**（官方明载：
//     非 INTEGER 主键 / 非 STRICT / 非 WITHOUT ROWID 的表允许 NULL，UNIQUE 索引视多行 NULL
//     互异 ⇒ 可并存），故 id IS NULL 的行在 `WHERE id = ?` 下恒零行命中；而写入计数按「值不等」
//     递增（非「实际影响行数」）⇒ 本页零写判据永不成立 ⇒ 候选判据只看列值（该行 seq 恒 NULL）
//     ⇒ 每轮重取同一页 ⇒ **无限轮询**。真机症状 = whenReady 永不落定：会话/助手/服务商列表
//     全空、输入框占位符恒显「数据库未就绪」，而 store 已赋值（doInit 赋值在维护链之前）⇒
//     写路径（如建助手）照常成功、写完列表仍读不出。rowid 恒非 NULL 恒唯一 ⇒ 任何行都可定位，
//     收敛由构造保证。执行级复现（node:sqlite 同构夹具，600 行 3 会话 + 1 行 NULL id）：
//     同数据按 id 定位 **301 轮不收敛**、按 rowid 定位 **2 轮收敛**。
//   ②【事务粒度 = 单会话】原为整个 sweep 一个事务。首启全库回填在真机上是分钟级，单事务意味着
//     中途退出即整体回滚、下次启动从零重来（用户永远等不到头，且每次重启都在「重新开始」）。
//     逐会话落库后每次启动接着上次进度推进直到收敛；顺带消除「候选查询读事务内未提交写入」
//     这一可见性依赖（每轮候选查询都读已提交状态）。
//   ③【轮次上限】原守卫只防得住「整页零写」，防不住「写入计数虚增」（①的成因正是后者——守卫
//     守卫的是「零写」，而每轮都真的有写、只是写不中目标行）。上限把「候选集不收敛」整类从
//     **永久挂起**降级为**可诊断的启动失败**。
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
    // 候选轮询（分页，每轮 ≤ SEQ_BACKFILL_CONV_PAGE）：
    // · COUNT(seq) < COUNT(*) = 该会话存在 NULL seq 行（COUNT(列) 不计 NULL）；
    // · COUNT(DISTINCT seq) < COUNT(seq) = 该会话存在重号。
    // ★ 为什么重号也要进候选（本笔 U0 调查实证，非推测——见变更记录「导出导入兼容三问」）：
    // 导出侧对整数列做 NULL→0 归一（ExportImport.readTableRows 列型分派），导入侧按目标列
    // 交集把该 0 原样写回（同件导入循环 INTEGER 分支）——于是「本版导出 → 本版导回」会把
    // 一个会话里所有「未编号」行变成一排真 0（重号），只看 `seq IS NULL` 的判据永不命中 ⇒
    // 该会话永不自愈，笔 3 切读取后整会话序退化（全 0 = 无定序）。重号分支把这条路径收进
    // 候选；旧备份导入（落 NULL）仍由左分支覆盖——两支合起来才等于「三类来源全覆盖」。
    // 查询在事务外 = 读已提交状态（②的逐会话提交让下一轮判定看得到本轮推进）
    const candidate: relationalStore.ResultSet = await db.querySql(
      'SELECT conversationId FROM messages GROUP BY conversationId ' +
      'HAVING COUNT(seq) < COUNT(*) OR COUNT(DISTINCT seq) < COUNT(seq) LIMIT ?',
      [SEQ_BACKFILL_CONV_PAGE]);
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
      db.beginTransaction();
      try {
        written += await sweepConversationSeq(db, convId);
        db.commit();
      } catch (e) {
        db.rollBack();
        throw e as Error;
      }
    }
    // 收敛守卫（2026-09-21 自检轮补）：命中的候选会话必有行「现值 ≠ 产出值」（NULL 与重号
    // 两种成因各至少一行），故本页正常路径至少写 1 行。整页零写而候选仍在 = 本页候选全部
    // 无法收敛（行的 id 在库中无匹配行——如 id 为 NULL 的损坏行，UPDATE 按 id 落空），
    // 而候选判据只看列值 ⇒ 下一轮重取同一页 ⇒ **无限轮询卡死启动**（whenReady 永不落定，
    // 页面既不报错也不可用）。此处响亮失败（P0-1 不静默）：上抛 → 事务回滚 →
    // doInit 返假 → UI 报「数据库初始化失败，发送功能已禁用」，症状可诊断
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

// 单会话 seq 归一并落库（返回实际写入行数）。事务由调用方按「每会话一个」粒度包裹（见
// backfillMessageSeq ②）——提取本函数的理由 = 让事务边界落在调用点一眼可见处。
// ★ 写定位键用 rowid 而非 id（理由见 backfillMessageSeq ①）：id 仍随行读出（供
// computeSeqBackfill 产出与真值表断言消费），但**不参与写库定位**。id 判 NULL 后取空串
//（ArkTS string 非空类型；显式判空后取值，免掉「依赖 getString 对 NULL 列的宽容度」）
async function sweepConversationSeq(db: relationalStore.RdbStore, convId: string): Promise<number> {
  // 行序 = createdAt ASC, rowid ASC（定序权威；函数内自带排序，此处 ORDER BY 只为读取确定性
  // ——ChatDb.repairTiedMessageTimestamps 同款读法含 rowid 显式投影）
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
    // 值未变不写（事务内最少写：重号候选会话里绝大多数行本就正确，只补差异行）。写量 =
    // 会话内「序号会变的行」——纯追加窗口 = 新增行数；会话里有删除空洞时空洞之后的行
    // 整体前移，写量含这批 ⇒ 恒远小于整会话行数（本节首轮全库回填除外）
    if (currentSeq.get(row.rowid) !== row.seq) {
      await db.executeSql('UPDATE messages SET seq = ? WHERE rowid = ?', [row.seq, row.rowid]);
      wrote++;
    }
  }
  return wrote;
}
