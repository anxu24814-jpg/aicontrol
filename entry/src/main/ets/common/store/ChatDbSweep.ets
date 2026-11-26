// 启动数据维护清扫域（自 ChatDb.ets 域级最小拆分——主件越 1200 硬线，方法体逐字搬迁零
// 语义变化）：空会话清扫 / streaming 中断恢复 / 非终态 run 收口 / 同毫秒并列修复四件启动
// 维护（ChatDb.doInit 依次装配）+ computeTieRepairedRows 纯函数（直跑断言面）。
// · 职责一句话 = 启动期幂等数据清扫；句柄生命周期与就绪语义仍在 ChatDb。
// · 依赖方向（零环红线，坑50）：本件不 import ChatDb——库句柄由调用方（doInit）作实参
//   传入（清扫函数已全部走形参，无模块级句柄读取）。
// ★ 旧会话墓碑笔：原「存量 legacy 强迁编排 + 失败黑名单」整段与 resetStaleMigratingConversations
//   （陈旧 migrating 复位清扫）随迁移机制整件退役删除——迁移不再发生，migrating 残值与
//   非 graph 态一律按墓碑读（MessageBranchDb 词表两值），复位清扫无对象也不再需要。现存
//   四件清扫与迁移零关系。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runWriteQueued } from './DbWriteQueue';
import { nextRowSeq } from './MessageSeqDb';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatDbSweep';

// 启动清扫空会话行（「空会话不进历史」配套，见 doInit 注释）：NOT IN 反连接取候选集后
// 逐表级联删除；无消息会话行删、其 messages 天然无（空行定义）。★ 六语句级联删包事务
//（P0-1 不半删——原「逐语句幂等、无显式事务」口径退役：重扫自愈仍成立，事务把跨语句的
// 半删窗口收成原子）；删序先子后父与 ChatDb.deleteConversations 同款同权；写事务入全局
// 写串行链（B1 契约，启动期空链零成本）。
// ★ 子查询带 conversationId IS NOT NULL（154 族反连接 NULL 坑）：子查询结果集只要出现一个
// NULL，id NOT IN (...) 对整个外层就不是真（三值逻辑）⇒ 清扫对所有会话静默失效（空会话
// 行只增不减），这类 NULL 由「备份缺 id 键」类数据引入（见 MessageSeqDb 头注释）。NULL
// conversationId 的 messages 行本就不属任何会话行，排除它不影响判定
export async function sweepEmptyConversations(db: relationalStore.RdbStore): Promise<void> {
  // ★ graph 排除（K3 启动维护分流）：迁移后的空会话（head null 空分支）是合法图态——
  // 会话行被本清扫误删会留下孤儿分支行。'graph' 字面 = MessageBranchDb.CONV_STATE_GRAPH
  // 词表值（词表冻结不漂；引常量造环，字面＋回指）；bind arg 形态零嵌套引号；两处反连接
  // 子查询均带 IS NOT NULL（族不变式）
  // ★ LB-7 修复：改「先取候选集 → 图侧五表级联 → 删行」——原单句 DELETE 只删
  // conversations 行，历史残留的「空会话带图侧行」（如迁移期空 migrating 会话被删遗留的
  // 孤儿 branches）会让图域导入的 hasGraphRows 判据误判「本机确有图侧数据」而 skip，造出
  // 有标无图。删序与五表语句 = ChatDb.deleteConversations 同款（先子后父）；幂等：中断后
  // 下一轮启动重选同批候选再删，图侧行已清则空删
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id FROM conversations WHERE id NOT IN ' +
    '(SELECT DISTINCT conversationId FROM messages WHERE conversationId IS NOT NULL) ' +
    'AND id NOT IN (SELECT id FROM conversations WHERE migrateState = ? AND id IS NOT NULL)',
    ['graph']);
  const ids: string[] = [];
  try {
    while (result.goToNextRow()) {
      ids.push(result.getString(result.getColumnIndex('id')));
    }
  } finally {
    result.close();
  }
  if (ids.length === 0) {
    return;
  }
  const marks: string = ids.map((_id: string): string => '?').join(',');
  // ★ 六语句级联删包事务 + 入链（头注释口径见上；启动维护期 store 句柄未公开、无并发者，
  // 入链零成本——与 repairTiedMessageTimestamps 同批口径统一）
  await runWriteQueued('sweepEmptyConversations', async (): Promise<void> => {
    db.beginTransaction();
    try {
      await db.executeSql('DELETE FROM attachment_refs WHERE conversationId IN (' + marks + ')', ids);
      await db.executeSql('DELETE FROM summary_bindings WHERE conversationId IN (' + marks + ')', ids);
      await db.executeSql('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
        'generation_runs WHERE conversationId IN (' + marks + '))', ids);
      await db.executeSql('DELETE FROM generation_runs WHERE conversationId IN (' + marks + ')', ids);
      await db.executeSql('DELETE FROM branches WHERE conversationId IN (' + marks + ')', ids);
      await db.executeSql('DELETE FROM conversations WHERE id IN (' + marks + ')', ids);
      db.commit();
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}

// 启动恢复：残留 streaming → error
// ★ 判据收窄（E1 #17 误伤面）：**图态会话的 streaming 行排除**——graph 会话有流中
// assistant 占位行（status='streaming'），一律改 error 会把半截正文显成「出错」。图态占位行
// 移交 sweepStaleGraphRuns 清算接管（悬空 run → interrupted + 占位行收口 done 成终答）；本口
// 只兜**非图态**残行（墓碑会话 legacy 残留——现网理论不达，保留兜底防形态回潮）。'graph'
// 字面 = MessageBranchDb.CONV_STATE_GRAPH 词表值（引常量造环，字面＋回指；bind arg 形态防
// SQL 嵌套引号撕裂）；NOT IN 子查询带 id IS NOT NULL（154 族反连接 NULL 安全不变式——
// 子查询集含 NULL 会让 NOT IN 三值逻辑对整表失效静默不命中）
export async function markStreamingAsError(db: relationalStore.RdbStore): Promise<void> {
  await db.executeSql(
    "UPDATE messages SET status = 'error' WHERE status = 'streaming' AND conversationId " +
    'NOT IN (SELECT id FROM conversations WHERE migrateState = ? AND id IS NOT NULL)',
    ['graph']);
}

// 时序修复行（repairTiedMessageTimestamps 内部行形态；role 参与组内角色优先序判据）
export interface RepairRow {
  id: string;
  role: string;
  createdAt: number;
  rowid: number;
}

// 重赋产物行（同上）：assigned = 重赋后新值；数组序 = 重赋后会话内顺序（调用方逐行按 id
// 写库，与遍历序无关——顺序只供真值表断言与排查读）
export interface RepairedRow {
  id: string;
  role: string;
  createdAt: number;
  rowid: number;
  assigned: number;
}

// 并列组重赋纯函数（直跑断言面 = assert-store-consistency 117 组真值表；入参行序 =
// createdAt ASC, rowid ASC，由调用方 SQL 保证）：同一 createdAt 为一组，组内按角色优先序
//（user < tool < assistant，同角色按 rowid）重排后自基线连续赋值 base + i；基线 =
// max(组原值, 前行新值 + 1)（前组占用推后组基线，级联安全）。契约三条：
// · 组内序取角色语义、不取物理插入序——并列组实际形态恒为「工具行 + 紧随的下一轮
//   assistant 占位行」（工具先于回复），而物理插入序不可控（insertMessage 先查询再插、
//   完成序掷硬币，根因见变更记录七百八十一节）；
// · 只治并列——单行组仅在前组占用推基线时才实际改值（健康会话零扰动；重赋后组内值互异
//   且全序严格递增 ⇒ 候选门不再命中，重跑零更新幂等）；
// · 只增不减——新值恒 ≥ 原值（重试推进值/统计/翻页游标语义只向后平移）。
// ★ 回退史防回游：本函数形态曾被 D4-1 改「物理插入序整体重赋 + 候选门放宽」，前提「物理
// 插入序即因果序」正是被根因否掉的硬币 ⇒ 会把角色序已修正的存量会话按物理倒挂改回去
//（真机复现「重进后工具卡出现在最新消息后」），已回退——判定见变更记录八百四十四节
export function computeTieRepairedRows(rows: RepairRow[]): RepairedRow[] {
  const out: RepairedRow[] = [];
  const roleRank = (role: string): number =>
    role === 'user' ? 0 : (role === 'tool' ? 1 : 2);
  let index: number = 0;
  let prevAssigned: number = 0;
  while (index < rows.length) {
    let end: number = index;
    while (end < rows.length && rows[end].createdAt === rows[index].createdAt) {
      end++;
    }
    const base: number = rows[index].createdAt > prevAssigned
      ? rows[index].createdAt : prevAssigned + 1;
    const group: RepairRow[] = rows.slice(index, end);
    group.sort((a: RepairRow, b: RepairRow): number =>
      roleRank(a.role) - roleRank(b.role) || a.rowid - b.rowid);
    for (let i: number = 0; i < group.length; i++) {
      prevAssigned = base + i;
      out.push({
        id: group[i].id, role: group[i].role, createdAt: group[i].createdAt,
        rowid: group[i].rowid, assigned: prevAssigned
      });
    }
    index = end;
  }
  return out;
}

// 非终态 run 中断收口（graph 会话启动维护，幂等）：残留 prepared/running 的 run 收口终态
// ——不重新发请求、工具未知结果不重放（tool_facts 的 dispatch_intent 原样保留＝「执行结果
// 未知」语义载体）。★ 悬空 run → **interrupted**（与「真失败」failed 全链路区分）+ 尾部
// streaming 占位行收口 done（checkpoint 已把半截写进行里，收口即成终答）+ 诊断 notice 节点
// 挂 run.diagnosticMessageId（读路径合成通道〔ChatDisplayHistory → ChatPageLoad 轮末合成〕
// 消费——与 finishRun 诊断节点同机制：挂输入锚、origin='finish_diag'、不进统计检索请求组
// 装面）。文案族对齐 finishStream 诊断：有半截 → 「应用退出，已保留部分内容」；无半截 →
//「应用退出，生成未完成」。
// · 写面与 MessageBranchDb.finishRun（interrupted 形态）逐字段对齐：status→interrupted、
// revision+1、updatedAt 推进、diagnosticMessageId 挂节点；幂等终态守卫 = WHERE status IN
// (prepared,running)。不 import 命令层防环（实测环会让类型检查崩坏）；finishRun 仍是生产
// 轮次收尾唯一写口，本函数只服务启动清扫，两处写面须同笔同步演进。
// · 诊断节点 id 自铸 'msg-' + Date.now() + '-sw<n>'（'-sw' 段避碰——启动清算期 UI 禁发送，
// 本口是唯一写者无同毫秒并发；不 import ChatDb 防环）；seq 走 MessageSeqDb.nextRowSeq。
// 只触 graph 会话（migrateState 过滤）——legacy 会话无 generation_runs 行。收尾兜底：graph
// 会话其余 streaming 残行统一收口 done，防 markStreamingAsError 收窄后图态残行无人清。
export async function sweepStaleGraphRuns(db: relationalStore.RdbStore): Promise<void> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, inputAnchorMessageId FROM generation_runs ' +
    'WHERE status IN (?, ?) AND conversationId IN ' +
    "(SELECT id FROM conversations WHERE migrateState = 'graph')",
    ['prepared', 'running']);
  interface StaleRunRow {
    id: string;
    conversationId: string;
    inputAnchorMessageId: string;
  }
  const staleRuns: StaleRunRow[] = [];
  try {
    while (result.goToNextRow()) {
      const anchorIdx: number = result.getColumnIndex('inputAnchorMessageId');
      staleRuns.push({
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        inputAnchorMessageId: result.getString(anchorIdx)
      });
    }
  } finally {
    result.close();
  }
  if (staleRuns.length === 0) {
    return; // 稳态零成本（绝大多数启动走此出口）
  }
  const now: number = Date.now();
  let sweepSeq: number = 0;
  // ★ 写串行链入链 + 事务包裹（启动维护期 store 句柄未公开、无并发者，入链零成本——
  // repairTiedMessageTimestamps 同批口径；一个 run 的「占位行收口 + 诊断节点 + run 终态」
  // 三语句原子，中断重跑幂等〔终态守卫谓词拦已收口 run〕）
  await runWriteQueued('sweepStaleGraphRuns', async (): Promise<void> => {
    db.beginTransaction();
    try {
      for (const run of staleRuns) {
        // ① 该 run 尾部 streaming 占位行收口 done（半截成终答）；有无半截决定诊断文案
        const halfResult: relationalStore.ResultSet = await db.querySql(
          "SELECT COUNT(*) AS n FROM messages WHERE runId = ? AND status = 'streaming'",
          [run.id]);
        let hasHalf: boolean = false;
        try {
          if (halfResult.goToNextRow()) {
            hasHalf = halfResult.getLong(halfResult.getColumnIndex('n')) > 0;
          }
        } finally {
          halfResult.close();
        }
        if (hasHalf) {
          await db.executeSql(
            "UPDATE messages SET status = 'done' WHERE runId = ? AND status = 'streaming'",
            [run.id]);
        }
        // ② 诊断 notice 节点（读路径合成通道消费——挂输入锚与 finishRun 同形态；空锚 run
        // 父落 NULL，照 LB-4② 防空悬边）
        sweepSeq++;
        const diagId: string = 'msg-' + now + '-sw' + sweepSeq;
        await db.executeSql(
          'INSERT INTO messages (id, conversationId, role, content, reasoning, status, ' +
          'createdAt, variants, variant_active, parentMessageId, runId, ownerAssistantId, ' +
          'stepIndex, seq, origin) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [diagId, run.conversationId, 'notice',
            hasHalf ? '应用退出，已保留部分内容' : '应用退出，生成未完成',
            '', 'done', now, '', 0,
            run.inputAnchorMessageId === '' ? null : run.inputAnchorMessageId,
            run.id, '', null, nextRowSeq(run.conversationId), 'finish_diag']);
        // ③ run → interrupted（终态守卫谓词幂等）+ 诊断挂靠
        await db.executeSql(
          "UPDATE generation_runs SET status = 'interrupted', diagnosticMessageId = ?, " +
          'revision = revision + 1, updatedAt = ? WHERE id = ? AND status IN (?, ?)',
          [diagId, now, run.id, 'prepared', 'running']);
      }
      // ④ 兜底：graph 会话其余 streaming 残行（异常残留）统一收口 done。
      // ★ awaiting_input run 的等待行**不动**——等待用户输入的 run 是活的停留态（可作答
      // 续跑/放弃收口两路在后），等待行是重进渲染等待卡的唯一库材料；一律收口 done 会把
      // 等待卡显成空结果普通卡且续答判据失效。豁免判据 = runId 属 awaiting_input run
      //（NOT IN 子查询 + id IS NOT NULL 防 NULL 三值逻辑失效——154 族反连接不变式）；
      // runId NULL/'' 残行照常收口（NOT IN 空子查询恒真，与既有行为一致）。等待行的收口
      // 只经两路：域⑤ 续答回填（UPDATE 升级终态）与放弃口。'awaiting_input' 字面 =
      // MessageBranchDb.RUN_STATUS_AWAITING_INPUT 词表值（引常量造环，同 'graph' 字面先例）
      await db.executeSql(
        "UPDATE messages SET status = 'done' WHERE status = 'streaming' AND conversationId IN " +
        "(SELECT id FROM conversations WHERE migrateState = 'graph') " +
        'AND runId NOT IN (SELECT id FROM generation_runs WHERE status = ? AND id IS NOT NULL)',
        ['awaiting_input']);
      db.commit();
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
  hilog.info(DOMAIN, TAG, '非终态 run 中断收口：%{public}d 个 run 标 interrupted（半截占位行收口 done）',
    staleRuns.length);
}

// 同毫秒并列修复清扫（启动幂等数据维护，sweepEmptyConversations 先例，非版本迁移；回退史
// 见 computeTieRepairedRows 注释）：历史落库笔在「工具行与下一轮 assistant 占位行」同一同步
// 链取 Date.now()，同毫秒并列组重进回放序取决于物理插入序（真机实锤工具卡跑到最新消息后）。
// 修复 = 逐候选会话按 createdAt 分组、组内角色优先序重排后连续重赋（三条契约），修复后
// 会话内 createdAt 严格递增、重跑零更新（幂等）。只动 createdAt 列内容零触碰；统计/翻页游标/
// 备份随值自然一致；导入旧备份若再引入并列，下次启动自愈。事务包裹（P0-1 不半修）。
// ★ 候选门 = 同毫秒并列，不猜物理插入序——「时间戳互异但物理序倒挂」的会话一律不碰
//（时间戳序即显示序，写入侧单调分配器保证；按物理序改写反而制造倒挂 = D4-1 真机故障面）
export async function repairTiedMessageTimestamps(db: relationalStore.RdbStore): Promise<void> {
  // K3 启动维护分流：graph 会话不进本件 legacy 维护（时间戳并列修复）——图会话显示序
  // 真源 = parent 链，createdAt 仅显示时刻，改写无益且越界。'graph' 字面 =
  // MessageBranchDb.CONV_STATE_GRAPH 词表值（词表冻结不漂；引常量会造
  // ChatDb→ChatDbSweep→MessageBranchDb→ChatDb 环，坑50 零环红线，故字面＋注释回指）且
  // 走 bind arg——SQL 字面量内不嵌引号（断言脚本抽取器按字面量拼接直跑，嵌套引号会撕裂
  // SQL）。★ 反连接 NULL 安全（154 族不变式，sweepEmptyConversations 同款）：子查询加
  // id IS NOT NULL——conversations.id 为 TEXT 主键不拒 NULL，子查询集含 NULL 会让
  // NOT IN 三值逻辑对整表失效（静默不命中）
  const grpResult: relationalStore.ResultSet = await db.querySql(
    'SELECT conversationId FROM messages WHERE conversationId NOT IN ' +
    '(SELECT id FROM conversations WHERE migrateState = ? AND id IS NOT NULL) ' +
    'GROUP BY conversationId, createdAt HAVING COUNT(*) > 1', ['graph']);
  const convIds: string[] = [];
  try {
    while (grpResult.goToNextRow()) {
      const convId: string = grpResult.getString(grpResult.getColumnIndex('conversationId'));
      if (!convIds.includes(convId)) {
        convIds.push(convId);
      }
    }
  } finally {
    grpResult.close();
  }
  if (convIds.length === 0) {
    return; // 稳态零成本（绝大多数启动走此出口）
  }
  let repaired: number = 0;
  // ★ 写串行链入链（启动维护期 store 句柄未公开、无并发者，入链零成本纯形态统一）
  await runWriteQueued('repairTiedMessageTimestamps', async (): Promise<void> => {
    db.beginTransaction();
    try {
      for (const convId of convIds) {
        // 行序 = createdAt ASC, rowid ASC（时间戳定组序、rowid 只做组内同角色决胜——重赋依赖
        // 此行序；禁改物理序，那等于把「物理插入序」重新扶成因果真源，见上回退说明）
        const rowResult: relationalStore.ResultSet = await db.querySql(
          'SELECT id, role, createdAt, rowid FROM messages WHERE conversationId = ? ' +
          'ORDER BY createdAt ASC, rowid ASC', [convId]);
        const rows: RepairRow[] = [];
        try {
          while (rowResult.goToNextRow()) {
            rows.push({
              id: rowResult.getString(rowResult.getColumnIndex('id')),
              role: rowResult.getString(rowResult.getColumnIndex('role')),
              createdAt: rowResult.getLong(rowResult.getColumnIndex('createdAt')),
              rowid: rowResult.getLong(rowResult.getColumnIndex('rowid'))
            });
          }
        } finally {
          rowResult.close();
        }
        // 并列组重赋（纯函数）+ 逐行比对落 UPDATE（值未变不写——幂等、事务内最少写）。
        // ★ 写定位键 = rowid（856 族登记的同类隐患）：本函数候选门是**值判据**
        //（GROUP BY conversationId, createdAt HAVING COUNT(*) > 1）⇒ 必须能改写命中会话里的
        // **任何**一行；而 id 可为 NULL（SQLite 的 TEXT PRIMARY KEY 不拒 NULL，官方明载——见
        // ChatDbMigrate v37 注释），WHERE id = ? 对这类行恒零行命中 ⇒ 并列永不修复、候选门
        // 每次启动重新命中（幂等契约破）+ 计数虚增。rowid 恒非 NULL 恒唯一 ⇒ 任何行都可
        // 定位，与 MessageSeqDb.backfillMessageSeq 同一条不变式（同族两处同修）
        const repairedRows: RepairedRow[] = computeTieRepairedRows(rows);
        for (let i: number = 0; i < repairedRows.length; i++) {
          if (repairedRows[i].assigned !== repairedRows[i].createdAt) {
            await db.executeSql('UPDATE messages SET createdAt = ? WHERE rowid = ?',
              [repairedRows[i].assigned, repairedRows[i].rowid]);
            repaired++;
          }
        }
      }
      db.commit();
      hilog.info(DOMAIN, TAG, '并列修复清扫：%{public}d 个候选会话，重赋 %{public}d 行',
        convIds.length, repaired);
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}
