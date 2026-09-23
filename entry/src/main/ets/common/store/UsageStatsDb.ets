// token 用量账本域（2026-09-06 任务书-token用量统计；表 = ChatDbMigrate v18
// token_usage_events，自 ChatDb 域级拆出——ChatDb 已 461 行软引导区禁再添域，先例
// ProviderBalanceDb；复用 sharedRdbStore 同一 DB 句柄，红线同源：ResultSet 用完 close /
// 查询全部有界——聚合单行或 GROUP BY 自然小集，逐日查询行数 ≤ 时段内有记录天数天然有界）。
// ★ 2026-09-06 用量统计页改版（任务书-用量统计页改版）：usageOverview/usageByModel/
//   usageByDay 三聚合加 sinceMs 时段参（createdAt >= sinceMs；0 = 全量不过滤——近七天 /
//   近三十天 / 全部三档同源，近 N 天起点由 UsageStatsCalc.dayStartMs 给）；usageByDay 撤
//   旧 LIMIT 30 + DESC 改 ASC 升序（热力图/趋势图要完整轴，调用方补零）；usageByModel 加
//   SQL 端 LIMIT 10（排行 Top10 口径，「其余 N 个模型未展示」= overview.usedModels − 行数）。
// 账本口径（决明 2026-09-05 六拍板，采集链见 ChatSendCtrl）：
// · 一行 = 一次用户发送的整轮聚合——含工具轮 N 流与 Key 失败切换的成功流，prompt/
//   completion/durationMs 跨流**求和**（流内多帧 take-max 在 SseParser.mergeUsage，
//   跨流求和在本表落库前的轮次累积器——两个口径不混）；
// · 中断轮（手动停止等 error 收尾）同落一行（2026-09-20 拍板口径变更）——行值 = 轮内
//   已完整收尾流的消耗，被停流 usage 帧未到天然不进累积器；purpose 恒 'chat' 不另设
//   中断码（账本无 status 维度，消费方零改动；细则见 ChatSendCtrl finishStream 落库注释）；
// · durationMs = Σ 各流 start→onDone 墙钟（纯流式时间，工具执行等待不计）；
// · 只追加不更新不删（单条）；级联删仅随会话删除（ChatDb.deleteConversations 事务内联
//   ——本域 import ChatDb，禁反向依赖，不设独立级联函数，口径登记见该函数注释）；
// · 存量旧消息不统计不回填——表自 v18 起从空累积；
// · 活跃天数/逐日 = date(createdAt/1000,'unixepoch','localtime') 本地时区口径（SQLite
//   按设备当前时区归日——切时区历史逐日可漂一日，可接受，展示语义非计费语义）。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { CostEventInput } from './CostStatsCalc';

// 统计页总览九数（UsageStatsPage 总览卡/Token 卡/排行尾行消费；时段 = createdAt >=
// sinceMs）：
// · rounds = 时段内 events 行数（整轮数，一次发送一条——「每条平均」= 总 token ÷ rounds）；
// · activeConversations = 时段内有用量记录的 DISTINCT 会话（events 口径，删会话随级联缩水）；
// · messageCount = messages 表 user+assistant 行时段 COUNT（tool 行不计——用户感知口径）；
// · usedModels = 时段内 DISTINCT modelId 数；
// · activeDays = 时段内 DISTINCT 有用量日（热力图「N 天活跃」同源）；
// · totalDurationMs = 时段内 SUM(durationMs)（2026-09-07 新增——总览「累计生成时长」；
//   纯流式时间口径见头注释「durationMs = Σ 各流 start→onDone 墙钟」）；
// · 三 token 和 = 时段内 SUM（总量/输入/输出）。
// ★ 2026-09-23 首字均值落点改判：全局两列（时段 SUM 与非 0 计数）随设置页总览格同日撤除
//（决明「不要设置页的，首字平均放上下文半模态」）——首字均值改由**会话级**聚合
// `sessionUsageTotals` 产出（同列同口径，只是 WHERE 换成单会话），消费方 = 上下文用量面板
export interface UsageOverview {
  rounds: number;
  activeConversations: number;
  messageCount: number;
  usedModels: number;
  activeDays: number;
  totalDurationMs: number;
  totalTokens: number;
  totalPromptTokens: number;
  totalCompletionTokens: number;
}

// 按模型聚合行（总量主行 + 输入/输出次要；SQL 端 ORDER BY 总量 DESC LIMIT 10）
export interface UsageByModelRow {
  modelId: string;
  totalTokens: number;
  promptTokens: number;
  completionTokens: number;
}

// 逐日聚合行（day = 'YYYY-MM-DD' 本地时区；ASC 升序自 2026-09-06 改版起——旧版 DESC
// LIMIT 30 + 调用方反转姿势已撤）
export interface UsageByDayRow {
  day: string;
  totalTokens: number;
  promptTokens: number;
  completionTokens: number;
}

// 落一行整轮用量（finishStream 收尾唯一点；id 进程内自增全局唯一）。totalTokens 缺省
// 回退 prompt+completion（Cube 01 卷 A3 同款兜底——上游未带 total 时保持总和口径一致）。
// cachedTokens = 整轮命中缓存读的输入 token（2026-09-10 缓存命中显示；v26 列，历史行
// DEFAULT 0 = 回放不显示缓存段——promptTokens 语义为全量输入、已含命中部分）。
// purpose = 用途码（2026-09-10 费用估计；v27 列）：'chat' 聊天发送（本调用点）/ 'title'
// 标题生成 / 'memory' 记忆整理 / 'test' 测试连接探针 / 'proactive' 主动消息生成
//（2026-09-12 主动消息第一笔）/ 'ocr' 附件文字识别（2026-09-15 附件 OCR 二期——视觉
// 引擎的识别请求记账，系统识别零请求不记）/ 'suggest' 推荐问题生成（2026-09-19 推荐问题
// 功能笔）——小任务链走 logTaskUsage 收口，不直接调本函数。
// firstTokenMs = 整轮首字耗时毫秒（2026-09-23 首字耗时笔；v44 列，缺省 0 = 无该指标）。
// ★ 只由聊天发送链给值（首个正文/思考增量到达时刻 − 流起点，跨流取首个非 0——见
// ChatUsageRoundCtrl）；小任务链与探针走 0（它们无「首字」语义）——故用量面板
// 的均值分母按 purpose='chat' + 非 0 计数双筛，两层都不放老行与无产出轮进分母
export async function insertUsageEvent(conversationId: string, messageId: string,
  providerId: string, modelId: string, promptTokens: number, completionTokens: number,
  cachedTokens: number, durationMs: number, firstTokenMs: number = 0,
  purpose: string = 'chat'): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'id': nextMessageId('usage'),
    'conversationId': conversationId,
    'messageId': messageId,
    'providerId': providerId,
    'modelId': modelId,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'cachedTokens': cachedTokens,
    'purpose': purpose,
    'totalTokens': promptTokens + completionTokens,
    'durationMs': durationMs,
    'firstTokenMs': firstTokenMs,
    'createdAt': Date.now()
  };
  await sharedRdbStore().insert('token_usage_events', bucket);
}

// 小任务用量记账（2026-09-10 费用估计；标题生成/记忆整理/测试连接三链共用收口——三处
// 同构调用提取为子程序）：usage 缺失或全零不落库（与聊天 usage>0 守卫同口径——探针
// max_tokens=1 或响应不带 usage 时零污染账本）；fire-and-forget 吞错 hilog 留痕不打扰
// 主链路（账本失败不影响标题/记忆/测试结果，ChatSendCtrl 同口径）。conversationId 随
// 语义给值：title/memory = 触发会话（删会话随级联删）、test/ocr = ''（无会话归属，
// 独立行不随任何删除走——OCR 与具体会话无绑定，2026-09-15 附件 OCR 二期）
export function logTaskUsage(purpose: string, conversationId: string, providerId: string,
  modelId: string, promptTokens: number, completionTokens: number,
  cachedTokens: number): void {
  if (promptTokens <= 0 && completionTokens <= 0) {
    return;
  }
  insertUsageEvent(conversationId, '', providerId, modelId, promptTokens, completionTokens,
    cachedTokens, 0, 0, purpose)
    .catch((e: Object): void => {
      hilog.warn(0xD5A3, 'UsageStatsDb', '小任务用量记账失败 purpose=%{public}s：%{public}s',
        purpose, (e as Error).message);
    });
}

// 费用估计事件行（v27 purpose 列接线起的新查询面；投影 = CostStatsCalc.CostEventInput
// 同源字段子集——七列只读，价格折算在 calc 层纯函数完成）
export async function queryCostEvents(sinceMs: number): Promise<CostEventInput[]> {
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT providerId, modelId, purpose, promptTokens, completionTokens, cachedTokens, ' +
    'createdAt FROM token_usage_events WHERE createdAt >= ' + sinceMs +
    ' ORDER BY createdAt ASC');
  const rows: CostEventInput[] = [];
  try {
    while (rs.goToNextRow()) {
      rows.push({
        providerId: rs.getString(rs.getColumnIndex('providerId')),
        modelId: rs.getString(rs.getColumnIndex('modelId')),
        purpose: rs.getString(rs.getColumnIndex('purpose')),
        promptTokens: rs.getLong(rs.getColumnIndex('promptTokens')),
        completionTokens: rs.getLong(rs.getColumnIndex('completionTokens')),
        cachedTokens: rs.getLong(rs.getColumnIndex('cachedTokens')),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
  } finally {
    rs.close();
  }
  return rows;
}

// 按会话查账本（历史回放挂 meta：messageId → event 映射在调用方组装；单会话行数 =
// assistant 轮数，天然有界）
export async function queryUsageByConversation(conversationId: string): Promise<UsageEventRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('token_usage_events');
  predicates.equalTo('conversationId', conversationId);
  predicates.orderByAsc('createdAt');
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates,
    ['messageId', 'totalTokens', 'completionTokens', 'durationMs', 'cachedTokens',
      'firstTokenMs']);
  const rows: UsageEventRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        messageId: result.getString(result.getColumnIndex('messageId')),
        totalTokens: result.getLong(result.getColumnIndex('totalTokens')),
        completionTokens: result.getLong(result.getColumnIndex('completionTokens')),
        durationMs: result.getLong(result.getColumnIndex('durationMs')),
        cachedTokens: result.getLong(result.getColumnIndex('cachedTokens')),
        firstTokenMs: result.getLong(result.getColumnIndex('firstTokenMs'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 账本行投影（历史回放消费的最小六列——completionTokens 供 meta 行 tok/s 分子，与流式
// 挂载口径一致；cachedTokens 供缓存段 >0 才挂（2026-09-10）；firstTokenMs 供首字耗时行
// >0 才挂（2026-09-23 首字耗时笔——存量行恒 0 = 该行无指标，天然不显示）；同 messageId
// 多 event 时调用方取最后一条〔2026-09-14 重试笔改口径——显示侧 = 该回答最新用量，
// 见 ChatPageLoad〕）
export interface UsageEventRow {
  messageId: string;
  totalTokens: number;
  completionTokens: number;
  durationMs: number;
  cachedTokens: number;
  firstTokenMs: number;
}

// 会话级用量累计行（2026-09-18 会话上下文增量笔立、同日「本会话累计」卡笔扩三值）：面板
// 总览卡「缓存命中」行与「本会话累计」卡共同的数据源——调研-上下文统计口径 §1.4/§五.2
// 可借鉴项 2 的 Cube 口径「累计缓存输入 ÷ 累计输入，按已记录用量统计」：promptTokens =
// SUM(promptTokens)（v26 列语义 = 全量输入已含命中——分母不另减）；completionTokens =
// SUM(completionTokens)；cachedTokens = SUM(cachedTokens)。★ 三值同为**计费口径**（账本行
// 值本为一次发送内跨流求和，含工具轮每轮重发的全量上下文——语义见 ChatSendCtrl
// ChatUsageRoundCtrl 域头注释），与面板「已用」的窗口规模口径不同基：一次多工具轮发送即可让
// 累计输入数倍于当前上下文，两个数不同屏并列展示同一基数。零 SQL 注入面：conversationId
// 走绑定参数（唯一 string 入参；其余聚合函数的 sinceMs 为内部 number 字面量拼接同此理由）
export interface SessionUsageTotals {
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
  // ── 三扩展值（2026-09-19 会话统计半模态笔）：同一聚合 SQL 顺带产出，原三消费者
  //（总览卡缓存率 / 累计卡）不受影响——totalTokens = SUM(totalTokens)（账本 API 报告
  // 总量真值，计费口径）；durationMs = SUM(durationMs)（生成总耗时，轮均速度分母）；
  // rounds = COUNT(*)（对话轮数——轮均 Token 分母，一次发送一账本行）
  totalTokens: number;
  durationMs: number;
  rounds: number;
  // ── 首字均值两值（2026-09-23 首字耗时笔；同日两度改判落点）：**只在非 0 行上求和与计数**
  //（CASE WHEN firstTokenMs > 0）——升级前存量行与无产出正文的轮次恒 0，混进分母即假数据；
  // 消费方 = 会话统计面板 Token 用量卡「平均首字耗时」行（CALC 层 fmtFirstTokenMs 做除零守卫）。
  // ★ 与 usageOverview 的时段口径区别：本聚合按**单会话**（WHERE conversationId = ?）
  firstTokenSumMs: number;
  firstTokenRecords: number;
}

// 会话级用量累计（单行聚合，purpose='chat' 只计对话轮——title/memory 等小任务虽挂同会话
// id 但非会话上下文演进，混入即污染分母，守卫同 usageOverview 三聚合）。无对话轮记录
//（含隐私会话旁路落库）回 null = 调用方按「未知」隐藏，0 与未知区分同面板既有口径
export async function sessionUsageTotals(conversationId: string): Promise<SessionUsageTotals | null> {
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT IFNULL(SUM(promptTokens), 0) AS p, IFNULL(SUM(completionTokens), 0) AS o, ' +
    'IFNULL(SUM(cachedTokens), 0) AS c, IFNULL(SUM(totalTokens), 0) AS t, ' +
    'IFNULL(SUM(durationMs), 0) AS d, COUNT(*) AS n, ' +
    'IFNULL(SUM(CASE WHEN firstTokenMs > 0 THEN firstTokenMs ELSE 0 END), 0) AS fs, ' +
    'SUM(CASE WHEN firstTokenMs > 0 THEN 1 ELSE 0 END) AS fn FROM token_usage_events ' +
    'WHERE conversationId = ? AND purpose = \'chat\'',
    [conversationId]);
  let promptSum: number = 0;
  let completionSum: number = 0;
  let cachedSum: number = 0;
  let totalSum: number = 0;
  let durationSum: number = 0;
  let roundCount: number = 0;
  let firstTokenSum: number = 0;
  let firstTokenCount: number = 0;
  try {
    if (rs.goToNextRow()) {
      promptSum = rs.getLong(rs.getColumnIndex('p'));
      completionSum = rs.getLong(rs.getColumnIndex('o'));
      cachedSum = rs.getLong(rs.getColumnIndex('c'));
      totalSum = rs.getLong(rs.getColumnIndex('t'));
      durationSum = rs.getLong(rs.getColumnIndex('d'));
      roundCount = rs.getLong(rs.getColumnIndex('n'));
      firstTokenSum = rs.getLong(rs.getColumnIndex('fs'));
      firstTokenCount = rs.getLong(rs.getColumnIndex('fn'));
    }
  } finally {
    rs.close();
  }
  if (promptSum <= 0) {
    return null;
  }
  const totals: SessionUsageTotals = { promptTokens: promptSum, completionTokens: completionSum,
    cachedTokens: cachedSum, totalTokens: totalSum, durationMs: durationSum, rounds: roundCount,
    firstTokenSumMs: firstTokenSum, firstTokenRecords: firstTokenCount };
  return totals;
}

// 总览八数（两条聚合 SQL 各返回单行——querySql 直写，GROUP BY/条件聚合 RdbPredicates
// 无表达能力，坑6 族无暴露：sinceMs 为内部计算的 number 字面量拼接〔0 或 dayStartMs
// 结果〕，无外部入参注入面）：events 条件聚合一炮（COUNT 行数 / DISTINCT 会话 /
// DISTINCT 模型 / DISTINCT 本地日期 / 四 SUM）+ messages 时段 COUNT
//（user+assistant 行，tool 行不计）。sinceMs = 0 即全量。★ 2026-09-10 费用估计起三聚合
//（本函数与 usageByModel/usageByDay）加 purpose='chat' 守卫——账本 v27 起新增 title/memory/
// test 三类小任务行，本页五卡口径不变仍只含聊天（get_usage_stats 工具调同组函数自动一致）；
// 存量行 DEFAULT 'chat' 回填语义正确零回归。★ 2026-09-23 首字耗时笔的末两列（fts/ftn）
// 已随同日「改判放上下文半模态」撤除——本函数回到四 SUM，首字均值改由 sessionUsageTotals 出
export async function usageOverview(sinceMs: number): Promise<UsageOverview> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const overview: UsageOverview = {
    rounds: 0, activeConversations: 0, messageCount: 0, usedModels: 0, activeDays: 0,
    totalDurationMs: 0, totalTokens: 0, totalPromptTokens: 0, totalCompletionTokens: 0
  };
  {
    const rs: relationalStore.ResultSet = await db.querySql(
      'SELECT COUNT(*) AS r, COUNT(DISTINCT conversationId) AS conv, ' +
      'COUNT(DISTINCT modelId) AS m, ' +
      'COUNT(DISTINCT date(createdAt / 1000, \'unixepoch\', \'localtime\')) AS d, ' +
      'IFNULL(SUM(totalTokens), 0) AS t, IFNULL(SUM(promptTokens), 0) AS p, ' +
      'IFNULL(SUM(completionTokens), 0) AS c, IFNULL(SUM(durationMs), 0) AS dur ' +
      'FROM token_usage_events WHERE purpose = \'chat\' AND createdAt >= ' + sinceMs);
    try {
      if (rs.goToNextRow()) {
        overview.rounds = rs.getLong(rs.getColumnIndex('r'));
        overview.activeConversations = rs.getLong(rs.getColumnIndex('conv'));
        overview.usedModels = rs.getLong(rs.getColumnIndex('m'));
        overview.activeDays = rs.getLong(rs.getColumnIndex('d'));
        overview.totalTokens = rs.getLong(rs.getColumnIndex('t'));
        overview.totalPromptTokens = rs.getLong(rs.getColumnIndex('p'));
        overview.totalCompletionTokens = rs.getLong(rs.getColumnIndex('c'));
        overview.totalDurationMs = rs.getLong(rs.getColumnIndex('dur'));
      }
    } finally {
      rs.close();
    }
  }
  {
    const rs: relationalStore.ResultSet = await db.querySql(
      'SELECT COUNT(*) AS c FROM messages WHERE role IN (\'user\', \'assistant\') AND createdAt >= '
      + sinceMs);
    try {
      if (rs.goToNextRow()) {
        overview.messageCount = rs.getLong(rs.getColumnIndex('c'));
      }
    } finally {
      rs.close();
    }
  }
  return overview;
}

// 按模型聚合 Top10（GROUP BY modelId ORDER BY 总量 DESC；2026-09-06 改版起 LIMIT 10 截断
// 在 SQL 端；空 modelId 行照列 = 快照兜底态的消耗也如实入账）。purpose='chat' 守卫同
// usageOverview（2026-09-10 费用估计）
export async function usageByModel(sinceMs: number): Promise<UsageByModelRow[]> {
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT modelId, IFNULL(SUM(totalTokens), 0) AS t, IFNULL(SUM(promptTokens), 0) AS p, ' +
    'IFNULL(SUM(completionTokens), 0) AS c FROM token_usage_events ' +
    'WHERE purpose = \'chat\' AND createdAt >= ' + sinceMs +
    ' GROUP BY modelId ORDER BY t DESC LIMIT 10');
  const rows: UsageByModelRow[] = [];
  try {
    while (rs.goToNextRow()) {
      rows.push({
        modelId: rs.getString(rs.getColumnIndex('modelId')),
        totalTokens: rs.getLong(rs.getColumnIndex('t')),
        promptTokens: rs.getLong(rs.getColumnIndex('p')),
        completionTokens: rs.getLong(rs.getColumnIndex('c'))
      });
    }
  } finally {
    rs.close();
  }
  return rows;
}

// 逐日聚合（时段内有记录日全量 ASC 升序；有界红线 = 行数 ≤ 有记录天数天然有界——
// 2026-09-06 改版撤旧「DESC + LIMIT 30 + 调用方反转」，热力图/趋势图要完整轴；
// 无记录日不由本函数补零——补零在调用方 UsageStatsCalc.fillDailyRange）。
// purpose='chat' 守卫同 usageOverview（2026-09-10 费用估计）
export async function usageByDay(sinceMs: number): Promise<UsageByDayRow[]> {
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT date(createdAt / 1000, \'unixepoch\', \'localtime\') AS day, ' +
    'IFNULL(SUM(totalTokens), 0) AS t, IFNULL(SUM(promptTokens), 0) AS p, ' +
    'IFNULL(SUM(completionTokens), 0) AS c FROM token_usage_events ' +
    'WHERE purpose = \'chat\' AND createdAt >= ' + sinceMs + ' GROUP BY day ORDER BY day ASC');
  const rows: UsageByDayRow[] = [];
  try {
    while (rs.goToNextRow()) {
      rows.push({
        day: rs.getString(rs.getColumnIndex('day')),
        totalTokens: rs.getLong(rs.getColumnIndex('t')),
        promptTokens: rs.getLong(rs.getColumnIndex('p')),
        completionTokens: rs.getLong(rs.getColumnIndex('c'))
      });
    }
  } finally {
    rs.close();
  }
  return rows;
}

// 按日消息数行（2026-09-07 热力图点击气泡「当天消息总数」——messages 表 user+assistant
// 当日 COUNT，与 usageOverview.messageCount 同口径〔tool 行不计〕；day = 'YYYY-MM-DD'
// 本地时区，与逐日聚合 date(localtime) 同口径两侧逐键可对账）
export interface UsageDayMsgRow {
  day: string;
  count: number;
}

// 按日消息数聚合（时段内 messages 日 COUNT；有界 = 行数 ≤ 时段内 messages 有记录天数；
// 无记录日由调用方/组件兜底 = 0——查询按日查表读不到即当日无消息）
export async function usageByDayMessageCounts(sinceMs: number): Promise<UsageDayMsgRow[]> {
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT date(createdAt / 1000, \'unixepoch\', \'localtime\') AS day, COUNT(*) AS c ' +
    'FROM messages WHERE role IN (\'user\', \'assistant\') AND createdAt >= ' + sinceMs +
    ' GROUP BY day ORDER BY day ASC');
  const rows: UsageDayMsgRow[] = [];
  try {
    while (rs.goToNextRow()) {
      rows.push({
        day: rs.getString(rs.getColumnIndex('day')),
        count: rs.getLong(rs.getColumnIndex('c'))
      });
    }
  } finally {
    rs.close();
  }
  return rows;
}
