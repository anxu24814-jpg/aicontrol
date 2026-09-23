// 请求历史组装域（2026-09-01 自 ChatSendCtrl.dispatchSend 拆出——该文件加「回传历史思考」
// 后超 400 红线，域级最小拆分，方法体原样搬迁行为不变）：
// 输入 = 屏幕消息流（ChatDataSource 的 ChatMessage[]），输出 = 协议请求历史
//（AiChatMessage[]——role/content[/reasoning[/images]] 四元组）。
// ★ 2026-09-01「回传历史思考」（RikkaHub includeHistoryReasoning 口径）：思考块
//（kind='thinking'，linkId = 关联正文消息 id，回放/流式两路同源）先收集到 reasonByLink；
// 组装 assistant 消息时其 id 命中 → reasoning 随行；思考块本身不入协议（thinking 无独立位，
// 协议消息是 role/content[/reasoning[/images]]）。**消费方两协议**（2026-09-17 更新）：
// OpenAI chat（reasoning_content 落点在 RequestCompose.composeOpenAiBody）与 Responses
//（明文 reasoning item 落点在 composeOpenAiResponsesBody——官方端点有捕获保真项时优先，
// 本域只管把思考文本随行带上，形态选择在 compose 层）。
// ★ 仍不回传两协议：Anthropic（thinking 块须 signature 保真——官方 400 Invalid signature
// 实锤）、Gemini（thought 段回传非官方要求）——维持现状不回传 = 零回归。
// 空内容消息跳过（占位/通知语义）；notice/thinking 不入协议（thinking 仅作 reasonByLink
// 数据源）。
// ★ 2026-09-02 工具调用历史重建：kind='tool' 消息（回放自 role='tool' 行，ChatDataSource
// 合成）紧随其 assistant 轮——前看收集到 toolCalls（assistant item.toolCalls，四协议方言
// 翻译在 RequestCompose）+ 逐条 role='tool' 结果消息（toolCallId/toolName 随行）。assistant
// 行 content 可为 ''（纯工具轮不丢——OpenAI 要求 tool_calls 消息在场）；坏 JSON 工具行
// 跳过（回放容错，与库行受控写入不冲突）。流式进行中的 running 卡（未落库）不入协议——
// 全部 done 后才进续轮历史，回放行天然 done。
import { AiChatMessage, AiToolCall } from '../../common/providers/AiTypes';
import { composeCompressSummaryMessage,
  mergeConsecutiveSameRole } from '../../common/providers/RequestInject';
import { ChatMessage } from './ChatMessageCompose';

// 工具行回传载荷（ArkTS 禁内联对象字面量类型——显式接口承载）
export interface ToolCallFromMessage {
  callId: string;
  name: string;
  argsJson: string;
  result: string;
}

// 工具行字段提取（ChatMessage → 回传载荷）：字段由回放/流式两路同源填充（ChatDataSource
// 合成 / ChatSendCtrl 工具卡构造）——缺关键键 = 异常行跳过
export function toolCallFromMessage(m: ChatMessage): ToolCallFromMessage | null {
  const callId: string = m.toolCallId ?? '';
  if (callId === '' || m.toolName === '') {
    return null;
  }
  const item: ToolCallFromMessage = { callId: callId, name: m.toolName,
    argsJson: m.toolInputJson ?? '{}', result: m.toolOutputJson ?? '' };
  return item;
}

export function buildRequestHistory(source: ChatMessage[]): AiChatMessage[] {
  // ── 压缩摘要预扫（2026-09-23 上下文压缩）──
  // 找物理序最后一条 kind='summary' 行（= seq 最大 = 最新摘要），记 boundary = 其
  // coversToSeq、summaryText = 其正文。无摘要行、或 coversToSeq 缺失/非正 → 走原路径
  //（零回归，请求逐字节不变——fail-open 宁多带不可误删）。
  // ★★ 边界判据是「库行 seq ≤ coversToSeq」，**不是**「遇到摘要行就清空已收集历史」：
  // 摘要行物理位置在会话末尾（seq = 会话 max），窗口序是 [被压段 … 保留段 … 摘要行]——
  // 按「遇到即清空」实现，清掉的是「被压段 + 保留段」，请求里只剩光秃秃一条摘要，保留
  // N 轮的设计静默失效。物理位置（末尾）与请求位置（头部）解耦，正是 coversToSeq 列的用途
  let summaryText: string = '';
  let boundary: number = -1;
  for (const m of source) {
    if (m.kind === 'summary' && (m.coversToSeq ?? 0) > 0) {
      summaryText = m.text;
      boundary = m.coversToSeq ?? 0;
    }
  }
  // 思考收集：思考块 → 正文消息 id 映射（linkId 契约见 ChatMessage 字段注释；
  // 回放 = 'think-'+行 id → linkId = 行 id；流式 = 懒创建时绑 liveAssistantId）
  const reasonByLink: Map<string, string> = new Map<string, string>();
  for (const m of source) {
    if (m.kind === 'thinking' && m.linkId !== undefined && m.linkId !== '' && m.text !== '') {
      reasonByLink.set(m.linkId, m.text);
    }
  }
  // 历史组装：user/assistant 消息入协议（notice 跳过；assistant 空内容仅在有工具调用时保留）
  const history: AiChatMessage[] = [];
  for (let i = 0; i < source.length; i++) {
    const m: ChatMessage = source[i];
    if (m.kind === 'tool') {
      continue; // 工具行由 assistant 前看消费（独立循环位置不入协议）
    }
    if (m.kind !== 'user' && m.kind !== 'assistant') {
      continue; // notice / thinking / summary 都不入协议（summary 行只当边界数据源）
    }
    // 被压段裁剪：rowSeq ≤ boundary 的 user/assistant 行不进请求。rowSeq undefined（实时
    // 流内行 / 存量 seq NULL 行）一律**不裁**——fail-open 宁多带不可误删
    if (boundary >= 0 && m.rowSeq !== undefined && m.rowSeq <= boundary) {
      continue;
    }
    if (m.kind === 'user') {
      if (m.text === '') {
        continue;
      }
      history.push({ role: 'user', content: m.text });
      continue;
    }
    // assistant：前看收集工具行（紧随的 kind='tool' 连续段）
    const calls: AiToolCall[] = [];
    const results: AiChatMessage[] = [];
    let j: number = i + 1;
    while (j < source.length && source[j].kind === 'tool') {
      const call: ToolCallFromMessage | null = toolCallFromMessage(source[j]);
      j++;
      if (call === null) {
        continue;
      }
      calls.push({ id: call.callId, name: call.name, argsJson: call.argsJson });
      results.push({ role: 'tool', content: call.result, toolCallId: call.callId,
        toolName: call.name });
    }
    if (m.text === '' && calls.length === 0) {
      continue; // 空内容且无工具调用（占位/异常）——不入协议
    }
    const item: AiChatMessage = { role: 'assistant', content: m.text };
    if (reasonByLink.has(m.id)) {
      item.reasoning = reasonByLink.get(m.id);
    }
    if (calls.length > 0) {
      item.toolCalls = calls;
      history.push(item);
      for (const resultMsg of results) {
        history.push(resultMsg);
      }
      i = j - 1; // 跳过已消费的工具行
    } else {
      history.push(item);
    }
  }
  // ── 摘要置顶（对应 ZCode 的请求顺序：摘要作一条普通 user 消息插在保留段之前）──
  // 包装语在组装时拼接（composeCompressSummaryMessage 单源，不进库）。置顶后摘要条与保留
  // 段首条可能同为 user——Anthropic/Gemini 官方拒连续同角色，过 mergeConsecutiveSameRole
  // 只并头部这一对（其余序列天然交替；role='tool' 行不参与合并，配对守卫不破）
  if (boundary >= 0 && summaryText !== '') {
    const summaryMsg: AiChatMessage = { role: 'user',
      content: composeCompressSummaryMessage(summaryText) };
    const withSummary: AiChatMessage[] = [summaryMsg].concat(history);
    return mergeConsecutiveSameRole(withSummary);
  }
  return history;
}
