// token 用量账本域（表 = ChatDbMigrate v18 token_usage_events，自 ChatDb 域级拆出——复用
// sharedRdbStore 同一 DB 句柄，红线同源：ResultSet 用完 close / 查询全部有界——聚合单行
// 或 GROUP BY 自然小集，逐日查询行数 ≤ 时段内有记录天数天然有界）。三聚合
//（usageOverview/usageByModel/usageByDay）带 sinceMs 时段参（createdAt >= sinceMs；0 = 全量
// 不过滤，近 N 天起点由 UsageStatsCalc.dayStartMs 给）；另有 usageTokenTotalBetween 单行
// SUM 查上一周期总量（左闭右开，供首卡「比前 N 天」变动行）；usageByDay ASC 升序（热力图/
// 趋势图要完整轴，补零在调用方）；usageByModel SQL 端 LIMIT 10（Top10 口径，「其余 N 个模型
// 未展示」= overview.usedModels − 行数）。
// 账本口径（决明拍板，采集链见 ChatSendCtrl）：
// · 一行 = 一次用户发送的整轮聚合——含工具轮 N 流与 Key 失败切换的成功流，prompt/
//   completion/durationMs 跨流**求和**（流内多帧 take-max 在 SseParser.mergeUsage，跨流求和
//   在落库前的轮次累积器——两个口径不混）；
// · 中断轮（手动停止等 error 收尾）同落一行（拍板口径）——行值 = 轮内已完整收尾流的消耗；
//   purpose 恒 'chat' 不另设中断码（账本无 status 维度，消费方零改动；落库单点 =
//   ChatGraphWriteCtrl.finishRound）；
// · durationMs = Σ 各流 start→onDone 墙钟（纯流式时间，工具执行等待不计）；
// · 只追加不更新不删（单条）；级联删仅随会话删除（ChatDb.deleteConversations 事务内联
//   ——本域 import ChatDb，禁反向依赖，不设独立级联函数，口径登记见该函数注释）；
// · 存量旧消息不统计不回填——表自 v18 起从空累积；
// · 活跃天数/逐日 = date(createdAt/1000,'unixepoch','localtime') 本地时区口径（SQLite 按设备
//   当前时区归日——切时区历史逐日可漂一日，可接受，展示语义非计费语义）。
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
// · totalDurationMs = 时段内 SUM(durationMs)（纯流式时间口径见头注释）；
// · 三 token 和 = 时段内 SUM（总量/输入/输出）。
// ★ 首字均值不在本接口（拍板撤除全局两列）——改由会话级聚合 sessionUsageTotals 产出
//（同列同口径，WHERE 换单会话），消费方 = 上下文用量面板
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

// 逐日聚合行（day = 'YYYY-MM-DD' 本地时区；ASC 升序——热力图/趋势图要完整轴）
export interface UsageByDayRow {
  day: string;
  totalTokens: number;
  promptTokens: number;
  completionTokens: number;
}

// 落一行整轮用量（finishStream 收尾唯一点；id 进程内自增全局唯一）。totalTokens 缺省
// 回退 prompt+completion（上游未带 total 时保持总和口径一致）。cachedTokens = 整轮命中
// 缓存读的输入 token（promptTokens 语义为全量输入、已含命中部分；历史行 DEFAULT 0 =
// 回放不显示缓存段）。purpose = 用途码（全集见 CostStatsCalc.COST_PURPOSES）：'chat'
// 聊天发送（本调用点），'title' 标题生成 / 'memory' 记忆整理 / 'test' 测试连接探针 /
// 'proactive' 主动消息生成 / 'ocr' 视觉引擎识别请求记账（系统识别零请求不记）/
// 'suggest' 推荐问题 / 'compress' 上下文压缩等小任务链走 logTaskUsage 收口，不直接调本函数。
// firstTokenMs = 整轮首字耗时毫秒（缺省 0 = 无该指标），★ 只由聊天发送链
// 给值（跨流取首个非 0——见 ChatUsageRoundCtrl）；小任务链与探针走 0（无「首字」语义）
// ——故用量面板均值分母按 purpose='chat' + 非 0 计数双筛，老行与无产出轮不进分母
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

// 小任务用量记账（标题生成/记忆整理/测试连接等小任务链共用收口）：usage 缺失或全零不落库
//（与聊天 usage>0 守卫同口径——探针 max_tokens=1 或响应不带 usage 时零污染账本）；
// fire-and-forget 吞错 hilog 留痕不打扰主链路（账本失败不影响小任务结果，ChatSendCtrl 同
// 口径）。conversationId 随语义给值：title/memory/compress = 触发会话（删会话随级联删）、
// test/ocr = ''（无会话归属，独立行不随任何删除走——OCR 与具体会话无绑定）
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
    ['messageId', 'modelId', 'totalTokens', 'completionTokens', 'durationMs', 'cachedTokens',
      'firstTokenMs', 'serverToolsUsage']);
  const rows: UsageEventRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        messageId: result.getString(result.getColumnIndex('messageId')),
        modelId: result.getString(result.getColumnIndex('modelId')),
        totalTokens: result.getLong(result.getColumnIndex('totalTokens')),
        completionTokens: result.getLong(result.getColumnIndex('completionTokens')),
        durationMs: result.getLong(result.getColumnIndex('durationMs')),
        cachedTokens: result.getLong(result.getColumnIndex('cachedTokens')),
        firstTokenMs: result.getLong(result.getColumnIndex('firstTokenMs')),
        serverToolsUsage: result.getString(result.getColumnIndex('serverToolsUsage'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 账本行投影（历史回放消费的最小七列——completionTokens 供 meta 行 tok/s 分子，与流式
// 挂载口径一致；cachedTokens 供缓存段 >0 才挂；firstTokenMs 供首字耗时行 >0 才挂〔存量行
// 恒 0 = 无指标，天然不显示〕；modelId 供轮头行模型名〔ChatMessage.modelLabel〕的回放
// 回填源，缺省空串 = 该账本行无模型记录）；同 messageId 多 event 时调用方取最后一条
//（显示侧 = 该回答最新用量，见 ChatPageLoad）
export interface UsageEventRow {
  messageId: string;
  modelId: string;
  totalTokens: number;
  completionTokens: number;
  durationMs: number;
  cachedTokens: number;
  firstTokenMs: number;
  // 二期 #7（v65）：本轮官方服务端工具计次 JSON 串（'' = 无计次）。★ 漏进显式列投影 =
  // 重进会话读不到计次（气泡三行只在当轮可见）
  serverToolsUsage: string;
}

// 会话级用量累计行（面板总览卡「缓存命中」行与「本会话累计」卡共同的数据源——口径 =
// 「累计缓存输入 ÷ 累计输入，按已记录用量统计」：promptTokens = SUM(promptTokens)
//（语义 = 全量输入已含命中，分母不另减）；completionTokens / cachedTokens 同为 SUM）。
// ★ 三值同为**计费口径**（账本行值本为一次发送内跨流求和，含工具轮每轮重发的全量上下文
// ——语义见 ChatSendCtrl ChatUsageRoundCtrl 域头注释），与面板「已用」的窗口规模口径不同
// 基：一次多工具轮发送即可让累计输入数倍于当前上下文，两个数不同屏并列展示同一基数。
// 零 SQL 注入面：conversationId 走绑定参数（唯一 string 入参；其余聚合的 sinceMs 为内部
// number 字面量拼接同此理由）
export interface SessionUsageTotals {
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
  // 三扩展值（同一聚合 SQL 顺带产出）：totalTokens = SUM(totalTokens)（账本 API 报告总量
  // 真值，计费口径）；durationMs = SUM(durationMs)（轮均速度分母）；rounds = COUNT(*)
  //（对话轮数——轮均 Token 分母，一次发送一账本行）
  totalTokens: number;
  durationMs: number;
  rounds: number;
  // 首字均值两值：**只在非 0 行上求和与计数**（CASE WHEN firstTokenMs > 0）——存量行与
  // 无产出正文的轮次恒 0，混进分母即假数据；消费方 = 会话统计面板「平均首字耗时」行
  //（CALC 层 fmtFirstTokenMs 做除零守卫）。★ 与 usageOverview 的区别：本聚合按**单会话**
  //（WHERE conversationId = ?）
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

// 总览九数（两条聚合 SQL 各返回单行——querySql 直写，GROUP BY/条件聚合 RdbPredicates
// 无表达能力，坑6 族无暴露：sinceMs 为内部计算的 number 字面量拼接〔0 或 dayStartMs
// 结果〕，无外部入参注入面）：events 条件聚合一炮（COUNT 行数 / DISTINCT 会话 / DISTINCT
// 模型 / DISTINCT 本地日期 / 四 SUM）+ messages 时段 COUNT（user+assistant 行，tool 行
// 不计）。sinceMs = 0 即全量。★ 三聚合（本函数与 usageByModel/usageByDay）加
// purpose='chat' 守卫——账本新增 title/memory/test 等小任务行，统计页与 get_usage_stats
// 工具口径不变仍只含聊天；存量行 DEFAULT 'chat' 回填语义正确零回归
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

// 上一周期 token 总量（用量统计页首卡「比前 N 天」变动行的上期读数）：单行 SUM 聚合，
// 左闭右开 [fromMs, toMs) 与当前时段起点无缝衔接，边界时刻不重复计入。purpose='chat'
// 守卫同 usageOverview（小任务链不计入）；恒返回单行，天然有界。全部档调用方不发本查询。
export async function usageTokenTotalBetween(fromMs: number, toMs: number): Promise<number> {
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT IFNULL(SUM(totalTokens), 0) AS t FROM token_usage_events ' +
    'WHERE purpose = \'chat\' AND createdAt >= ' + fromMs + ' AND createdAt < ' + toMs);
  let total: number = 0;
  try {
    if (rs.goToNextRow()) {
      total = rs.getLong(rs.getColumnIndex('t'));
    }
  } finally {
    rs.close();
  }
  return total;
}

// 按模型聚合 Top10（GROUP BY modelId ORDER BY 总量 DESC，LIMIT 10 截断在 SQL 端；空
// modelId 行照列 = 快照兜底态的消耗也如实入账）。purpose='chat' 守卫同 usageOverview
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

// 逐日聚合（时段内有记录日全量 ASC 升序；有界红线 = 行数 ≤ 有记录天数天然有界——热力图/
// 趋势图要完整轴，不截断；无记录日不由本函数补零——补零在调用方 UsageStatsCalc.
// fillDailyRange）。purpose='chat' 守卫同 usageOverview
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

// 按日消息数行（热力图点击气泡「当天消息总数」——messages 表 user+assistant 当日 COUNT，
// 与 usageOverview.messageCount 同口径〔tool 行不计〕；day = 'YYYY-MM-DD' 本地时区，与
// 逐日聚合 date(localtime) 同口径两侧逐键可对账）
export interface UsageDayMsgRow {
  day: string;
  count: number;
}

// 按日消息数聚合（时段内 messages 日 COUNT；有界 = 行数 ≤ 时段内有记录天数；无记录日
// 由调用方/组件兜底 = 0——查询按日查表读不到即当日无消息）
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

// 清空用量账本（唯一调用方 = 快速清理页）：token_usage_events 整表删。★ 头注释口径
//「只追加不更新不删（单条）」不变——本函数是**唯一**的整表清除点，非单条删；会话级/
// 助手级仍只走各自级联（ChatDb.deleteConversations / AssistantDb.deleteAssistantCascade
// 事务内联），本函数不参与级联链。
// ★ 只清账本，不动 messages：清空后出现「有消息条数、token 为 0」是预期形态（用户清的
// 是用量统计不是对话内容；消息数一格走 messages 表 COUNT），非缺陷，勿在页面上「修」成
// 两处一致。
// ★ 副作用面（清空即失效，均在页/气泡上如实归零，无残留旧值通道）：气泡单轮用量与速度
// meta（ChatPageLoad 按 messageId 装配 → 查不到即不显示）、上下文用量面板的本会话累计与
// 缓存率（sessionUsageTotals）、只读工具 get_usage_stats / get_cost_stats、费用页全部数字。
// ★ executeSql 裸 DML 整表清空（无谓词，不涉 RdbPredicates 空条件危险区）；不返回行数，
// 清空前的条数由 quickClean 概览独立读出（见 common/QuickClean.ets）。
export async function clearUsageEvents(): Promise<void> {
  await sharedRdbStore().executeSql('DELETE FROM token_usage_events');
}
