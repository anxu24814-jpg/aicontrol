// 请求历史编排域（2026-10-22 任务书-请求历史与UI窗口解耦-20261022 阶段 B 新增）：
// 发送 / 重试两链共用的「读库 → 组装 → 降级」与「token 双闸（估算 + 按轮裁剪）」编排件。
// · 为什么不能留在 ChatSendCtrl（反碎片下限申报）：该件已远超宪法 1200 硬线，本任务属
//   新增功能域——「新增功能域不论行数一律先拆」；本件一句话职责 = 请求历史的来源编排
//   与 token 裁剪决策，不碰状态机、不碰 promptState、不碰 UI 容器。
// · 五处同源锚点（任务书 §5）：发送（dispatchSend）/ 重试（launchRetryRound）经本件；
//   离屏 web（WebHeadlessHost→sendCtrl.send 同链自动跟进）/ 用量面板（computeLive）/
//   压缩选段（CompressGen 调用方）直接调同一读口 readRequestHistoryRows 与同一套预算函数
//   （RequestHistoryBudget），禁第二份实现。
// · 读条数口径（勘察补设计，记变更记录）：发送（userReq ≠ null）= resolveReadRows
//   （预算 − 1，本条 user 由本件 push 补位；excludeNodeId = prepareRun 已前移 head 到本条
//   user 节点，传该节点 id 排除之——否则 rows 含本条 + push 即重复）；重试（userReq =
//   null，fork 后分支 head = 锚点 user、天然不含旧分支旧答案）= resolveRowBudget 全额
//   （锚点占预算内名额）——发送「N−1 + push」与重试「N 含锚点」历史条数一致。
// · 降级契约（任务书 §1.2 失败语义）：读库失败 → 用 push 之前取的窗口浅拷贝快照组装，
//   degraded = true，静默降级正常发出（不弹错、不打断发送）；快照必须在 push 之前 slice
//   ——push 之后取会把本条 user 重复带入（任务书认定唯一硬坑）。
// · 本期无缓存：读口每次现读（任务书 §4.2；性能超标处置见 BLOCKED 登记节）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiChatMessage } from '../../common/providers/AiTypes';
import { ChatMessage } from './ChatMessageCompose';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { chatMessagesFromRows } from './ChatMessageProjection';
import { RequestSummaryInput } from '../../common/chat/ChatContextSource';
import { readRequestHistoryRows } from '../../common/chat/RequestHistorySource';
import { BudgetRow, estimateRequestTokens, clipRoundsToTokenBudget,
  resolveRowBudget, resolveReadRows, applyGateCalibration } from '../../common/chat/RequestHistoryBudget';
import { COMPRESS_SUMMARY_OPEN } from '../../common/providers/RequestInject';
import { estimateTokens } from '../../common/TokenEstimate';
// k 校准闸门读值（2026-10-24 缓存统计案 U4）：AppStorage 读封装单源在 AppPreferences；本件
// 不在任何复制直跑面（assert-request-history 只复制 RequestHistoryBudget——方案 §6.2 落点
// 裁定），读值零断言代价，可测性由 RequestHistoryBudget 纯函数层 applyGateCalibration 承担
import { currentCtxFactor } from '../../common/AppPreferences';

export interface RequestHistoryResult {
  // 已含 pathSummary 置顶、已含传入的 userReq（null 时不加）；未注入、未 token 裁
  history: AiChatMessage[];
  // true = 读库失败，用了窗口快照（调用方只记日志，不弹错）
  degraded: boolean;
  // 实际历史条数（此阶段无 system 注入行，即组装后总条数）
  rowCount: number;
}

export interface TokenFitResult {
  // 裁剪后序列；未裁时与原序列同引用
  history: AiChatMessage[];
  // 输入侧估算（maxOutput = 0——输出空间由 0.7 余量承担）
  estimatedTokens: number;
  clipped: boolean;
}

// k 校准闸门键（2026-10-24 缓存统计案 U4）：最小结构 = 服务商 id + 模型名（currentCtxFactor
// 双键查 k 的入参面）。AiConnection 为本形态超集，但 ArkTS 禁结构化类型直传
//（arkts-no-structural-typing，ChatSendCtrl 唯一调用行直传 conn 编译实锤）——发送链调用行
// 以字面量显式取 conn 两字段构造（接线级零逻辑体，方案 §6.3 主案的语法适配）；缺省
// undefined → k=1 零漂移
export interface GateCalibrationKey {
  providerId: string;
  model: string;
}

// AiChatMessage → BudgetRow（裁剪 / 估算消费面全量镜像；imageCount 派生位）。导出供
// ChatContextUsage.computeLive（面板侧 token 闸）复用——AiChatMessage ↔ BudgetRow 的
// 映射单源在此，面板禁自写第二份
export function toBudgetRow(m: AiChatMessage): BudgetRow {
  const r: BudgetRow = { role: m.role, content: m.content,
    reasoning: m.reasoning !== undefined ? m.reasoning : '', imageCount: m.images !== undefined ? m.images.length : 0 };
  if (m.toolCalls !== undefined) {
    r.toolCalls = m.toolCalls;
  }
  if (m.toolCallId !== undefined) {
    r.toolCallId = m.toolCallId;
  }
  if (m.toolName !== undefined) {
    r.toolName = m.toolName;
  }
  if (m.images !== undefined) {
    r.images = m.images;
  }
  if (m.reasoningItems !== undefined) {
    r.reasoningItems = m.reasoningItems;
  }
  if (m.createdAt !== undefined) {
    r.createdAt = m.createdAt;
  }
  return r;
}

// BudgetRow → AiChatMessage（协议保真还原；BudgetRow 是 AiChatMessage 的完整结构镜像，
// 同构接口结构兼容直搬——见 RequestHistoryBudget.BudgetRow 字段注释）。导出同 toBudgetRow
export function fromBudgetRow(r: BudgetRow): AiChatMessage {
  const m: AiChatMessage = { role: r.role, content: r.content };
  if (r.reasoning !== '') {
    m.reasoning = r.reasoning;
  }
  if (r.toolCalls !== undefined) {
    m.toolCalls = r.toolCalls;
  }
  if (r.toolCallId !== undefined) {
    m.toolCallId = r.toolCallId;
  }
  if (r.toolName !== undefined) {
    m.toolName = r.toolName;
  }
  if (r.images !== undefined) {
    m.images = r.images;
  }
  if (r.reasoningItems !== undefined) {
    m.reasoningItems = r.reasoningItems;
  }
  if (r.createdAt !== undefined) {
    m.createdAt = r.createdAt;
  }
  return m;
}

export class ChatRequestHistoryCtrl {
  // 历史来源编排（发送：userReq = 本条 user；重试：userReq = null，锚点 user 已在库内）。
  // excludeNodeId 仅发送链非空（= beginSend 回执的本条 user 节点 id，读口从该节点起不含
  // 自身）；重试传 null（从分支 head 含自身，head = 锚点 user）。
  async load(conversationId: string, branchId: string, contextCount: number,
    pathSummary: RequestSummaryInput | null, windowSnapshot: ChatMessage[],
    userReq: AiChatMessage | null, excludeNodeId: string | null): Promise<RequestHistoryResult> {
    const maxRows: number = userReq !== null ?
      resolveReadRows(contextCount) : resolveRowBudget(contextCount);    let history: AiChatMessage[];
    let degraded: boolean = false;
    try {
      const read = await readRequestHistoryRows(conversationId, branchId, maxRows, excludeNodeId);
      history = buildRequestHistory(chatMessagesFromRows(read.rows), pathSummary);
    } catch (e) {
      degraded = true;
      history = buildRequestHistory(windowSnapshot, pathSummary);
      hilog.warn(0x0001, 'ChatReqHist',
        '请求历史读库失败，降级用窗口快照（%{public}s）', (e as Error).message);
    }
    if (userReq !== null) {
      history.push(userReq);
    }
    return { history: history, degraded: degraded, rowCount: history.length };
  }

  // token 双闸（入参 = assembleRound 产出的最终序列〔含 system 注入〕+ 工具声明串 + 预算）：
  // 只做「估算 + 按轮裁剪」纯计算与还原，不重新注入（注入位置已落定，重跑 assembleRound
  // 徒增成本且可能因 targetUserIndex 重算引入偏差——任务书 §4.3）。budget ≤ 0（无窗口参考值）
  // 或估算入预算 → 原引用返回不裁。
  // ★ k 校准进闸门（2026-10-24 缓存统计案 U4）：gateKey 在场时按 (providerId, model) 读一次
  // 落键 k，预算经 applyGateCalibration（g = clamp(k, 0.7, 5) 双向钳制）换算后才作闸门值——
  // gateKey 缺省 / k 未积累（=1）→ 逐字节同现状零漂移；估算与裁剪全程原始估算单位，只预算侧
  // 换算。面板 computeLive 同一 helper 校准（「面板与实发一致」纪律，只校准一侧即分叉，禁）
  fitTokens(history: AiChatMessage[], toolDefsJson: string, budget: number,
    gateKey?: GateCalibrationKey): TokenFitResult {
    // U4 预算校准：k 非法由 applyGateCalibration 内部视 1（此处 gateKey 缺省直接 1，读值侧
    // currentCtxFactor 无记录回 1 同语义）；预算 ≤ 0 校准后仍 0 = 直通语义不变
    const gateK: number = gateKey !== undefined ?
      currentCtxFactor(gateKey.providerId, gateKey.model) : 1;
    const gatedBudget: number = applyGateCalibration(budget, gateK);
    // 头部连续 system 行抽出单列（与 appendSystem* 的 '\n\n' 合并形态一致；BudgetRow 侧
    // system 行内容跳过防双计）
    const sysTexts: string[] = [];
    for (const m of history) {
      if (m.role !== 'system') {
        break;
      }
      sysTexts.push(m.content);
    }
    const systemText: string = sysTexts.join('\n\n');
    const rows: BudgetRow[] = history.map(toBudgetRow);
    const estAll: number =
      estimateRequestTokens({ systemText: systemText, history: rows,
        toolDefsJson: toolDefsJson, maxOutput: 0 });
    if (gatedBudget <= 0 || estAll <= gatedBudget) {
      return { history: history, estimatedTokens: estAll, clipped: false };
    }
    // history 侧可用预算 = 总预算 − system/tools 固定量（clipRoundsToTokenBudget 只看行侧）
    const fixed: number = estimateTokens(systemText) + estimateTokens(toolDefsJson);
    const clippedRows: BudgetRow[] =
      clipRoundsToTokenBudget(rows, gatedBudget - fixed, COMPRESS_SUMMARY_OPEN);
    if (clippedRows === rows) {
      // 未裁（单轮超预算 fail-open 或 history 预算 ≤ 0）——整序保留，超窗照发（既有 400
      // 错误链呈报），记警告供排查
      hilog.warn(0x0001, 'ChatReqHist',
        'token 裁剪 fail-open：单轮或固定段超预算（估算 %{public}d / 预算 %{public}d）',
        estAll, gatedBudget);
      return { history: history, estimatedTokens: estAll, clipped: false };
    }
    const out: AiChatMessage[] = clippedRows.map(fromBudgetRow);
    const est: number =
      estimateRequestTokens({ systemText: systemText, history: clippedRows,
        toolDefsJson: toolDefsJson, maxOutput: 0 });
    return { history: out, estimatedTokens: est, clipped: true };
  }
}
