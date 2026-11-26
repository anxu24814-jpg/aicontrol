// 消息行 → 视图消息投影域（2026-09-26 消息架构整合笔3 S2 新建，书3⑤ E 组授权两新件之一）。
// 域定义一句话：**rebuild / prepend / live 三链共用的行→ChatMessage 映射**（含思考块合成、
// 库序号/时刻/摘要边界回填（★ 订正 A-21：variants 多版本随退役笔3 删除）、批内链标记后处理
// （★ 2026-10-07 消息链条化展示笔）＋ 路径锚点分页游标类型（K8 anchorHeadId）。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话 = 行→视图消息的纯映射；②原映射
//   内联在 ChatDataSource.rebuildFromHistory / prepend 两处（同一段代码双份），笔3 读侧
//   路径化后 rebuild/prepend/live 三链都要同一映射——抽单源正是消重复（重复 2 次以上提取
//   为子程序）；③实逻辑非转接壳（映射与回填规则全在此，ChatDataSource 只剩容器与通知）。
// · 与 ChatDataSource 的分工：本件纯映射零状态（输入行集 → 输出消息数组），容器语义
//  （tail 维护/游标维护/通知）仍在 ChatDataSource；live 链（流式构造 ChatMessage）不经本件
//   ——live 对象由 ChatSendCtrl 直接 newChatMessage 构造，字段口径与本映射一致（rowSeq/
//   createdAt 同址回填纪律见 ChatMessage 字段注释）。
// · graph 行：经 ChatContextSource.adaptPathRows 适配后的 MessageRow[] 与 legacy 行同形
//  （variants 恒 ''、coversToSeq 来自摘要绑定投影），本映射零特判通用两态。
// ★ 2026-10-08 过程段折叠笔：原链标记批内后处理（linkAdjacentMarks）随链标记四字段整面
// 退役删除——段分组与段内连线判据改由展示投影域（ChatDisplayProjection）按展示项结构推导。
import { MessageRow } from '../../common/store/ChatDb';
import { ChatMessage, newChatMessage, dsServerCallJsonsOf } from './ChatMessageCompose';
import { serverStepNameOf, serverStepStateOf } from '../../common/providers/DsServerTools';
import { ConfirmWaitState, parseConfirmWaitPayload } from './ChatConfirmWait';

// 路径翻页锚（graph 会话触顶翻页游标——K8：游标携分支与锚点节点；seq 游标在图会话不可用
// ——fork 共享前缀使 seq 序 ≠ 路径序，翻页必须走 parent 链。类型单源在此，ChatDataSource
// 持有、ChatPageLoad 消费）
export interface PathAnchorCursor {
  branchId: string;
  oldestNodeId: string;
}

// 行集 → 视图消息数组（rebuild 与 prepend 共用单源；自 ChatDataSource 两处内联映射收编，
// 语义逐字保留）：role='tool' 行 → 工具卡（坏行容错跳过）；user/assistant/summary/notice
// 行 → 正文消息（seq/coversToSeq/createdAt 投影回填；★ 订正 A-21：variants 多版本随退役笔3 删除）；reasoning 非空 → 思考块
// 合成（linkId 契约，思考在回答上方）
// ★ 2026-10-08 状态收敛笔：可选 roundIdOf = 本批行 id → 展示轮 id 映射（历史装配件产出）
// ——body 与 toolCard 写对应 id 的 displayRoundId，合成 thinking 继承其 body.displayRoundId；
// 缺省（无事实读方）零行为变化。不从 toolState 或 MessageRow.status 推轮终态（★ 解耦笔2
// 域② 起库内存在 streaming 占位行——其半截正文照常投影静显，轮终态仍只由 run 事实
// 〔mapTraceRunStatus〕给出，行级 status 不进展示判据）。
export function chatMessagesFromRows(rows: MessageRow[], roundIdOf?: Map<string, string>):
  ChatMessage[] {
  const out: ChatMessage[] = [];
  for (const row of rows) {
    const roundId: string = roundIdOf !== undefined ? (roundIdOf.get(row.id) ?? '') : '';
    if (row.role === 'tool') {
      const card: ChatMessage | null = toolCardFromRow(row);
      if (card !== null) {
        card.displayRoundId = roundId;
        out.push(card);
      }
      continue;
    }
    const body: ChatMessage = newChatMessage(row.id, row.role, row.content);
    body.displayRoundId = roundId;
    // 库序号回填（2026-09-23 上下文压缩）：row.role 直映 kind；rowSeq 供组装侧被压段判据
    // 与压缩选段（graph 行 = 入链单调序号，语义见 ChatContextSource 头注释）
    if (row.seq !== undefined) {
      body.rowSeq = row.seq;
    }
    if ((row.role === 'summary' || row.role === 'clear') && row.coversToSeq !== undefined) {
      body.coversToSeq = row.coversToSeq;
    }
    // 创建时刻回填（2026-09-24 时间间隔提醒）；思考块同刻。★ 2026-10-12 S-1 修复：本回填
    // = 库行时刻**先落**；助手侧三类在数据源安装口再按轮起始时刻归一（startMs——见
    // ChatDataSource.alignRoundStartTimes 两调用点），user 行库行时刻即终值
    if (row.createdAt !== undefined) {
      body.createdAt = row.createdAt;
    }
    // 引用全文快照回填（2026-10-21 引用功能 U-C，DB v61）：user 行有意义；NULL/缺省 =
    // 无引用不挂（rebuild/prepend/live 三链共用映射，挂值单源在此——实时链 dispatchSend
    // 同址挂值见 ChatMessage.quoteText 字段注释）
    if (row.quoteText !== undefined && row.quoteText !== '') {
      body.quoteText = row.quoteText;
    }
    // DeepSeek 服务端工具原样串回填（DS 全家桶接入批 S2⑥⑦，DB v64）：assistant 行有意义；
    // NULL/缺省 = 非官方档轮/无服务端步骤不挂。消费方 = buildRequestHistory 回传与 S3 渲染
    //（步骤行合成/来源卡——回放侧合成随 S3 接手；本挂值即「列写读投影回放一致」的投影单源）
    if (row.serverTools !== undefined && row.serverTools !== '') {
      body.serverToolsJson = row.serverTools;
    }
    if (row.reasoning !== '') {
      const think: ChatMessage = newChatMessage('think-' + row.id, 'thinking', row.reasoning);
      think.linkId = row.id;
      think.displayRoundId = body.displayRoundId; // 合成思考继承其 body 的轮归属
      if (row.createdAt !== undefined) {
        think.createdAt = row.createdAt;
      }
      out.push(think);
    }
    // DS 服务端步骤行回放合成（S3.0，屏显与库一致——任务书 §4.4 重现）：assistant 行
    // serverToolsJson 非空 → parse server_tool_calls 按步合成 serverstep 行，插在合成思考行
    // 之后、正文行之前（与实时链行序一致——thinking 先建、serverstep 事件 insertBefore
    // (liveAssistantId)）。态与名映射单源 = DsServerTools 提取函数（与实时链共引）；annotations
    // 不合成行（M1 来源卡直接吃 serverToolsJson）。合成行 kind='serverstep' 天然不入协议产物
    //（buildRequestHistory 非 user/assistant 行剔除——丙组负向钉在案）。id = 'srvstep-'+行 id+
    // 序号：确定性铸造，重建键稳定（段复用与 ForEach 键纪律）。linkId 不挂——该字段唯一消费
    // 面是 kind='thinking' 的思考回传配对（ChatHistoryBuilder），serverstep 行与实时链同形
    if (row.role === 'assistant' && row.serverTools !== undefined && row.serverTools !== '') {
      const calls: string[] = dsServerCallJsonsOf(row.serverTools);
      for (let i = 0; i < calls.length; i++) {
        const callJson: string = calls[i];
        const stepRow: ChatMessage = newChatMessage('srvstep-' + row.id + '-' + i.toString(),
          'serverstep', '', serverStepNameOf(callJson), serverStepStateOf(callJson));
        stepRow.toolOutputJson = callJson; // call 原样串（S3 渲染料——与实时链同承载字段）
        stepRow.displayRoundId = body.displayRoundId; // 轮归属继承其 body（roundIdOf 同源）
        if (row.createdAt !== undefined) {
          stepRow.createdAt = row.createdAt;
        }
        out.push(stepRow);
      }
    }
    out.push(body);
  }
  return out;
}

// ── 工具行合成（自 ChatDataSource 迁入单源；两链同用）──

// role='tool' 行 content JSON 载荷（与 ChatToolRoundCtrl.ToolEventRecord 同构——库行单一真源）
interface ToolRowRecord {
  toolCallId?: string;
  name?: string;
  argsJson?: string;
  result?: string;
  isError?: boolean;
}

// 工具行 → 工具卡消息合成（回放路径；坏 JSON/缺键回 null 跳过——容错不炸历史重建）。
// 中止载荷映射（2026-09-24 中止卡落库笔 B）：result 带 cancelled 键 = 用户中止。
// ★ 域①（2026-10-16）：cancelled 判据与 isError 解耦（中止是状态不是失败——新写中止行
// isError=false、存量中止行 isError=true，两者都按 cancelled 键判）；态位三分 error/done
// 之外增 cancelled（头部「已中止」中性徽标）。存量真失败行（无 cancelled 键）照旧 error
// 零回归。★ 2026-10-06 代码工作台笔D 注释随形：工具结果附件（缩略图）不参与回放合成——
// 库行 content JSON 恒五键（serializeToolRecord 白名单），回放卡天然无 toolMediaParts
// （运行时字段口径，零行为改动）
// ★ U11 域⑤（2026-10-16）：态位分流抽为可直跑纯函数 toolCardStateOf（+「行 streaming →
// running」映射——等待行回放产出**等待卡**：ask 卡渲染判据 toolState==='running' 成立，
// 跨重启续答的可作答入口；行级 status 只在 streaming 一处进判据，其余态仍由载荷键判）
function toolCardFromRow(row: MessageRow): ChatMessage | null {
  let record: ToolRowRecord | null = null;
  try {
    record = JSON.parse(row.content) as ToolRowRecord;
  } catch (e) {
    return null;
  }
  if (record === null || typeof record.toolCallId !== 'string' || typeof record.name !== 'string') {
    return null;
  }
  const argsJson: string = typeof record.argsJson === 'string' ? record.argsJson : '{}';
  const result: string = typeof record.result === 'string' ? record.result : '';
  const isError: boolean = record.isError === true;
  const cancelled: boolean = isCancelledResult(result);
  const displayLine: string = cancelled ? '已中止' : previewLine(result, 60);
  const state: string = toolCardStateOf(row.status, result, isError);
  const msg: ChatMessage = newChatMessage(row.id, 'tool',
    isError && !cancelled ? displayLine : '', record.name, state);
  msg.toolCallId = record.toolCallId;
  msg.toolInputJson = argsJson;
  msg.toolInputText = previewLine(argsJson, 40);
  msg.toolOutputJson = result;
  msg.toolDisplayText = displayLine;
  // 确认等待载荷回放（2128 笔）：等待行的 result 位承载「等用户确认」的卡面状态——解出后
  // 重建 toolConfirm* 运行时字段，isConfirmAwaiting 判据才成立（跨进程/回收重进仍可作答）。
  // 载荷不是结果：输出位清空，免卡面把它当工具输出渲染；结算后 result 被真实结果覆盖，
  // 本分支自然不再命中
  const confirmWait: ConfirmWaitState | null = parseConfirmWaitPayload(result);
  if (confirmWait !== null) {
    msg.toolConfirmText = confirmWait.text;
    msg.toolConfirmLevel = confirmWait.level;
    msg.toolConfirmDetail = confirmWait.detail;
    msg.toolConfirmDomain = confirmWait.domain;
    msg.toolConfirmAiNote = confirmWait.aiNote;
    msg.toolOutputJson = '';
    msg.toolDisplayText = '';
  }
  // 创建时刻回填（2026-10-12 消息时间头笔）：段首步为工具卡时轮头行取本值当轮起始时刻
  // ——与正文行的回填口径同源（role 行自带 createdAt 列，此前仅正文/思考回填）；★ 同笔
  // S-1 修复：装入时按轮起始时刻归一（同上方 body 注释）
  if (row.createdAt !== undefined) {
    msg.createdAt = row.createdAt;
  }
  return msg;
}

// 工具行态位分流（纯函数——直跑断言面；★ U11 域⑤ 自 toolCardFromRow 抽为单源）：
// ①行 status='streaming' → 'running'（图态进行中行——等待行/占位行回放；ask 卡据此渲染
// 等待作答交互区）；②cancelled 载荷键 → 'cancelled'（域① 中止是状态不是失败）；
// ③isError → 'error'；④其余 → 'done'。优先级固定（行态先于载荷键——等待行 result 恒空串，
// 载荷键判据天然不成立，两态不并存的防御次序）
export function toolCardStateOf(rowStatus: string, result: string, isError: boolean): string {
  if (rowStatus === 'streaming') {
    return 'running';
  }
  const cancelled: boolean = isCancelledResult(result);
  return cancelled ? 'cancelled' : (isError ? 'error' : 'done');
}

// 单行紧凑预览（空白压一空格 + 超长截断；与 ChatToolRoundCtrl.compactPreview 同语义——
// 两处各自域内小函数，不跨层共享避免组件域反向依赖）
function previewLine(text: string, maxChars: number): string {
  const line: string = text.replace(/\s+/g, ' ').trim();
  return line.length > maxChars ? line.substring(0, maxChars) + '…' : line;
}

// 中止载荷判据（2026-09-24 中止卡落库笔 B）：合法 JSON 且带 cancelled 键。
// ★ 2026-10-02 重发件自检修复 F3 导出：实时结算（ChatToolResendCtrl.settleWithResult）与
// 回放本函数消费同一单源——两链中止卡卡面文案恒一致，禁第二份实现
export function isCancelledResult(result: string): boolean {
  try {
    const parsed: object = JSON.parse(result);
    const rec = parsed as Record<string, Object>;
    return rec['cancelled'] !== undefined;
  } catch (e) {
    return false; // 非 JSON 结果（纯文本）恒非中止
  }
}
