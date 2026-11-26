// 引用文本组装单源（方案档 docs/方案-引用功能全链路-20261021.md §3.1；common/chat
// 纯函数件先例 = ChatBranchPolicy / SessionSnippet）。
// 域定义一句话：**引用文本 → 用户消息 content 的 blockquote 前缀拼装与截断单源**。
// · 为何不能并入（反碎片下限②申报）：两调用点跨两域——ChatSendCtrl（发送协议面组装）
//   与 ChatHistoryBuilder（历史重建组装）；并进任一侧都会让另一侧反向依赖发送/组装域，
//   且「首发与重试轮逐字一致」的保证依赖同一函数，须第三方单源。
// · 幂等性 = 结构性（非字符串嗅探）：content 恒存用户原文、引用全文独立存 messages.
//   quote_text 列（DB v61），两源每次组装各取一次——无「拼过的再拼一遍」路径，重复调用
//   结果恒定；用户正文恰以「> 」开头不误判（不解析不剥离）。
// · blockquote 格式定稿：quoteText 先 trim、\r\n/\r 归一 \n；非空行 →「> 」+ 行内容，
//   空行 →「>」（无尾空格）；引用块与正文之间恰一个空行；引用文本自身含「> 」开头行 →
//   原样保留成嵌套 blockquote（不转义——markdown 渲染链三层封顶视觉已兜底）。选
//   blockquote 而非 fence 的理由：自描述多协议通用、引用块渲染链零新码、模型回显引用块
//   也直接渲染、历史多轮天然可见。
// · 入口截断（clampQuoteText）与组装（composeQuotedContent）分工：截断发生在 UI「引用」
//   动作挂载时刻（超限 Toast），组装发生在发送与历史重建两处——组装前数据不再二次截断
//   （挂载时已 clamp，DB 与请求面同值）。

// 单条引用全文硬上限（字符）——ZCode 同值（溯源 singleLimit 8000）
export const QUOTE_MAX_CHARS: number = 8000;

// 入口截断（UI「引用」动作调用）：超限截到 QUOTE_MAX_CHARS 字符；不 trim 内容
//（保留原样仅截断——截断是 UI 动作的一部分，引用条展示与落库共用同值）
export function clampQuoteText(text: string): string {
  // 截断点码点安全：substring 按 UTF-16 码元截，恰劈在代理对中间时尾部新造半个高代理
  // 上行落库——清掉尾孤儿高代理（MessageCopySheet 选区清理同款正则；BMP 字符与未触发
  // 截断路径零影响，至多削 1 码元且削掉的必是残半个字）。
  return text.length > QUOTE_MAX_CHARS
    ? text.substring(0, QUOTE_MAX_CHARS).replace(/[\uD800-\uDBFF]$/, '')
    : text;
}

// 组装单源（两调用点 = ChatSendCtrl.dispatchSend 协议面 / ChatHistoryBuilder user 行）：
// 返回 = 引用块（逐行「> 」前缀）+ 空行 + 用户正文；quoteText 空（含 trim 后空）→
// userText 原样返回——无引用路径零变化（protocolText 与改前逐字一致）；userText 空 →
// 返回引用块（防御性：纯引用发送上游已拦，理论不达）
export function composeQuotedContent(quoteText: string, userText: string): string {
  if (quoteText === '') {
    return userText;
  }
  // 归一：trim 首尾 + \r\n/\r → \n（引用来源是用户选区，换行风格不可控）
  const normalized: string = quoteText.trim().replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  if (normalized === '') {
    return userText;
  }
  const lines: string[] = normalized.split('\n');
  const quoted: string[] = [];
  for (const line of lines) {
    quoted.push(line === '' ? '>' : '> ' + line);
  }
  const block: string = quoted.join('\n');
  if (userText === '') {
    return block;
  }
  return block + '\n\n' + userText;
}
