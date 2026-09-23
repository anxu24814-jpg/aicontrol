// 注入组装域（2026-08-30 提示词注入版创建；2026-08-31 自 RequestCompose.ets 域级拆出——
// 该文件加思考档位方言后超 400 红线，注入配置域整体迁此，方法体原样搬迁行为不变）。
// 零 import 纯函数约束照旧（scripts/sse-assert.mjs 复制本文件为 .ts 直跑——⑭⑮⑰⑳㉒㉙ 组
// 断言的线上同一实现；与 ComposeChatMessage 同构的本地接口依赖 RequestCompose 侧定义，故本
// 文件自持一份同构声明）。
// ★ 2026-09-05 工具对原子性双守卫（真机 HTTP 400 修复，任务书任务 0）：发送历史含工具轮
// （assistant(toolCalls) 行 + 相邻 N 条 role='tool' 结果行为一个原子组）后，本域两个变换
// 都可能把组撕开——①clipHistoryTail 裸 slice 尾部截取边界落进组中间 = 请求以孤儿 tool 行
// 开头；②mergeConsecutiveSameRole 合并重建对象只带 role/content/images/reasoning 四字段，
// toolCallId/toolName/toolCalls 全丢（一轮并行多工具的结果行恰为相邻同 role='tool'，system
// 注入路径必过 merge）——两形态都令四协议配对校验 400（openai「assistant message with
// 'tool_calls' must be followed by tool messages」/anthropic tool_result 无 tool_use 配对/
// gemini functionResponse 名失配/responses function_call_output 无 call）。守卫见两函数处
// 注释，断言 ㉙ 组。
// 适配口径 = 只适配协议规格不逐厂商特判；user 注入 = 拼接式（不产生新消息，交替约束与
// 缓存断点天然规避，RikkaHub #1101 教训反向实现）；assistant 注入 = 独立消息 + 连续同角色
// merge 守卫。组合语义与协议适配细则见 docs/规范-数据存储获取刷新方案.md §3.5。

// 对话消息（与 AiTypes.AiChatMessage / RequestCompose.ComposeChatMessage 同构：role 事实值
// 'system' | 'user' | 'assistant' | 'tool'；images 仅 user 消息携带——注入只动 content 字符串；
// 2026-09-01 回传历史思考：+ reasoning（仅 assistant——mergeConsecutiveSameRole 合并时
// 保留，OpenAI 路径落点；Anthropic/Gemini 无落点忽略）；
// 2026-09-05 工具对守卫补字段：+ toolCalls（仅 assistant）/ toolCallId + toolName（仅
// role='tool'）——发送历史含工具轮时由调用方随 AiChatMessage[] 结构兼容直穿，本域只判
// 在场与角色保配对完整，内容不消费（方言翻译在 RequestCompose）；
// 2026-09-06 Responses 修复补字段：+ reasoningItems（仅 assistant 工具轮——merge 重建
// 对象透传防丢，同 toolCalls 守卫一族）
interface InjectChatMessage {
  role: string;
  content: string;
  images?: InjectImagePart[];
  reasoning?: string;
  toolCalls?: InjectToolCall[];
  toolCallId?: string;
  toolName?: string;
  reasoningItems?: InjectReasoningItem[];
}

// 图片部件（与 AiTypes.AiImagePart 同构；零 import 自持）
interface InjectImagePart { mimeType: string; data: string }

// 工具调用载荷（与 AiTypes.AiToolCall 同构；零 import 自持——本域只判在场，不消费内容）
interface InjectToolCall { id: string; name: string; argsJson: string }

// reasoning 输出项（与 AiTypes.AiReasoningItem 同构；零 import 自持）
interface InjectReasoningItem { id: string; encryptedContent: string }

// ── 注入配置（与 prompt_templates 表注入三列同构——常量表全工程唯一来源，禁裸字符串，
// 供 PromptTemplateDb/PromptInjectConfig/ChatSendCtrl 引用）──
export const INJECT_ROLE_SYSTEM: string = 'system';
export const INJECT_ROLE_USER: string = 'user';
export const INJECT_ROLE_ASSISTANT: string = 'assistant';
export const INJECT_POSITION_HEAD: string = 'head';    // 系统提示位（role=system 恒此位）
export const INJECT_POSITION_DEPTH: string = 'depth';  // 在用户消息深度 N（injectDepth 生效）
export const INJECT_DEPTH_MAX: number = 4;

// 注入配置载体（零 import 自持接口——ChatSendCtrl 解析结果 / 编辑页保存链同构）
export interface PromptInjectConfig {
  content: string;
  role: string;        // INJECT_ROLE_*；默认 'system'
  position: string;    // INJECT_POSITION_*；默认 'head'
  depth: number;       // 0~4；默认 0（仅 position='depth' 生效；0 = 最新用户消息）
}

// 注入组装：请求历史 + 注入配置 → 发送消息列表——inject 为 null / content 空 = 原样返回
//（默认行为逐字节不变，回归红线）；role=system = system 消息置首位（历史已含 system 不追加
// 防重复）；role=user = 拼接式：注入内容并进目标用户消息 content 前部（'\n\n'——不产生新
// user 消息，交替约束与缓存断点天然规避）；role=assistant = 目标用户消息之后独立插入（紧邻
// 后已有 assistant → 并入其前部 merge 守卫；无后续 = 原位插入，Anthropic 语义即官方
// prefill）。目标 = 从末尾往前第 depth 条 user（不足钳位到最早 user；无 user = 不注入不伪造）。
// 输出统一过 mergeConsecutiveSameRole（协议交替守卫）。
export function composeSendMessages(history: InjectChatMessage[],
  inject: PromptInjectConfig | null): InjectChatMessage[] {
  if (inject === null || inject.content === '') {
    return history;
  }
  const role: string = inject.role;
  if (role === INJECT_ROLE_SYSTEM) {
    for (const m of history) {
      if (m.role === 'system') {
        return history; // 历史已含 system（异常路径）——不重复注入
      }
    }
    const injected: InjectChatMessage[] = [{ role: 'system', content: inject.content }];
    for (const m of history) {
      injected.push(m);
    }
    return mergeConsecutiveSameRole(injected);
  }
  const target: number = targetUserIndex(history, inject.depth);
  if (target < 0) {
    return history; // 无 user 消息（异常序列）——不注入不伪造
  }
  if (role === INJECT_ROLE_USER) {
    // 拼接式（IN_MESSAGE）：内容并进目标 user 消息前部——不新增消息；目标带图时 images
    // 原样随行（注入只动 content 字符串）
    const joined: InjectChatMessage[] = [];
    for (let i = 0; i < history.length; i++) {
      if (i === target) {
        joined.push({ role: 'user', content: inject.content + '\n\n' + history[i].content,
          images: history[i].images });
      } else {
        joined.push(history[i]);
      }
    }
    return mergeConsecutiveSameRole(joined);
  }
  if (role === INJECT_ROLE_ASSISTANT) {
    const joined: InjectChatMessage[] = [];
    for (let i = 0; i < history.length; i++) {
      if (i === target) {
        joined.push(history[i]); // 目标 user 消息本身（勿漏——历史不丢）
        const next: InjectChatMessage | undefined =
          i + 1 < history.length ? history[i + 1] : undefined;
        if (next !== undefined && next.role === 'assistant') {
          // merge 守卫：注入并入后邻 assistant 前部（维持交替，消息数不变）；
          // reasoning 随行带（2026-09-01 回传契约——assistant 注入不丢历史思考）；
          // toolCalls 随行带（2026-09-05 工具对守卫——深度注入落点紧邻工具轮 assistant
          // 时，重建对象丢 toolCalls = 该轮 tool 行成孤儿，同样 400）；
          // reasoningItems 随行带（2026-09-06——Responses 官方端点工具轮保真料，同族防丢）
          joined.push({ role: 'assistant', content: inject.content + '\n\n' + next.content,
            images: next.images, reasoning: next.reasoning, toolCalls: next.toolCalls,
            reasoningItems: next.reasoningItems });
          i++; // 跳过已并入的 next
        } else {
          joined.push({ role: 'assistant', content: inject.content });
        }
        continue;
      }
      joined.push(history[i]);
    }
    return mergeConsecutiveSameRole(joined);
  }
  return history; // 未知 role（脏值防御）——不注入不阻断
}

// 目标用户消息下标：从末尾往前第 depth 条 user（depth=0 = 最新；不足钳位到最早；
// 无 user = -1 = 调用方不注入）
function targetUserIndex(history: InjectChatMessage[], depth: number): number {
  let seen: number = 0;
  for (let i = history.length - 1; i >= 0; i--) {
    if (history[i].role === 'user') {
      if (seen === depth) {
        return i;
      }
      seen++;
    }
  }
  if (seen > 0) {
    for (let i = 0; i < history.length; i++) {
      if (history[i].role === 'user') {
        return i;
      }
    }
  }
  return -1;
}

// 协议交替守卫（Anthropic「roles must alternate」/Gemini「alternate between user and model」
// 官方拒绝连续同角色；OpenAI/Responses 无害——统一合并行为一致）：连续同角色 content
// 以 '\n\n' 连接（与既有 Anthropic 多 system 连接同分隔）；images 数组同并（双方都带图
// 时顺序拼接——正常对话不产生连续 user 带图，防御性语义）；reasoning 同并（2026-09-01
// 回传历史思考：assistant 连续合并时前一条 reasoning 不丢——'\n\n' 连接——OpenAI 路径
// 落点单串，Anthropic/Gemini 无落点忽略；后一条 reasoning 覆盖同 key 场景取并集语义）
// ★ 2026-09-23 上下文压缩笔导出：ChatHistoryBuilder 摘要置顶后过本守卫（摘要条与保留段
// 首条可能同为 user）——导出零行为变化，既有调用面照旧
// ★ 2026-09-05 工具对守卫（真机 400 修复）：role='tool' 行与带 toolCalls 的 assistant 行
// 不参与同角色合并——合并重建的对象只承载 role/content/images/reasoning，toolCallId/
// toolName/toolCalls 会丢 = 配对断裂（openai tool_call_id 空/缺答恒 400；一轮并行多工具的
// 结果行恰为相邻同 role='tool'，system 注入路径必过本守卫）。交替约束对 tool 行本就由
// 协议 compose 层满足（anthropic/gemini 连续 tool 行聚成单条 user 消息，openai/responses
// 无交替要求——sse-assert ㉔ 组既有形态），此处不合并零副作用。
export function mergeConsecutiveSameRole(msgs: InjectChatMessage[]): InjectChatMessage[] {
  const merged: InjectChatMessage[] = [];
  for (const m of msgs) {
    const last: InjectChatMessage | undefined =
      merged.length > 0 ? merged[merged.length - 1] : undefined;
    if (last !== undefined && last.role === m.role && m.role !== 'tool' &&
      m.toolCalls === undefined && last.toolCalls === undefined) {
      const images: InjectImagePart[] | undefined =
        (last.images !== undefined || m.images !== undefined) ?
          (last.images ?? []).concat(m.images ?? []) : undefined;
      const reasoning: string | undefined =
        (last.reasoning !== undefined || m.reasoning !== undefined) ?
          (last.reasoning ?? '') + '\n\n' + (m.reasoning ?? '') : undefined;
      merged[merged.length - 1] = { role: m.role, content: last.content + '\n\n' + m.content,
        images: images, reasoning: reasoning };
    } else {
      merged.push(m);
    }
  }
  return merged;
}

// ── 上下文消息数截取（2026-09-01 助手高级设定·上下文与输出页）──
// 发送序列尾部截取（应用层参数，不进请求体）：limit ≤ 0 / ≥ 序列长度 = 原样返回（不
// 截取零回归）；否则保尾部 limit 条（★ 计数含本条 user——调用点在 push 本条之后、注入
// 之前：system 头注与深度注入在截取后的序列上计算，身份注入永不丢——首条历史被截属
// 预期语义「只发最近 N 条」）。零 import 纯函数（sse-assert 同源直跑断言）。
// ★ 2026-09-05 工具对原子性守卫（真机 400 修复）：一轮工具调用 = assistant(toolCalls)
// 行 + 相邻 N 条 role='tool' 结果行为一个原子组，截取边界落进组中间会让请求以孤儿 tool
// 行开头（配对 assistant 被截——四协议配对校验 400；对话越长越易命中）。处置 = 边界向
// 前回退到组首 assistant 行保整对；取舍 = 窗口软超 limit 几条优于丢整轮（模型保留工具
// 上下文），limit 本就是软上限语义（「至少最近 N 条」）。调用点在 push 本条 user 之后
// ——尾边界恒为本条 user 不落组中，无需尾侧守卫；回退撞到 0 仍是 tool 行（脏序列防御）
// = 全量带上不截。
export function clipHistoryTail(history: InjectChatMessage[], limit: number): InjectChatMessage[] {
  if (limit <= 0 || history.length <= limit) {
    return history;
  }
  let start: number = history.length - limit;
  while (start > 0 && history[start].role === 'tool') {
    start--;
  }
  return history.slice(start);
}

// ── 上下文压缩·摘要包装语与截尾保活（2026-09-23 任务书-上下文压缩-20260923）──
// 包装语两段常量 + 拼接函数的单一来源在本件（零 import 叶子，ChatHistoryBuilder 从本件
// import）：组装侧（置顶拼接）与截尾识别侧（首句判据）共用同一来源，**禁两处各写一份
// 字面量**。照 ZCode buildCompactSummaryMessage 的开头语 + suppressFollowup 续跑提示写的
// ——少了续跑提示，模型会回一句「我已了解之前的对话，我们继续吧」。
export const COMPRESS_SUMMARY_OPEN: string =
  '本次对话延续自上一段超出上下文上限的对话，下面的摘要覆盖了此前的内容。\n\n';
export const COMPRESS_SUMMARY_TAIL: string =
  '\n\n继续对话，不要复述这份摘要，不要询问我是否继续，直接接着上面的内容回应。';

// 摘要条内容拼接（组装时用；不进库、不可编辑——库里 content 列存的是纯摘要正文）
export function composeCompressSummaryMessage(summaryText: string): string {
  return COMPRESS_SUMMARY_OPEN + summaryText + COMPRESS_SUMMARY_TAIL;
}

// 摘要永不被裁的截尾：先把摘要条摘出来 → 余下序列走既有 clipHistoryTail（工具对原子守卫
// 原样保留）→ 摘要条拼回最前。**两处调用点同换**（ChatSendCtrl.assembleRound 发送组装与
// ChatContextUsage.computeLive 面板活算——不同链即「面板与实发不一致」，本仓既有硬纪律）。
// · 摘要条识别契约（单一判据，别自创第二种）：history[0].role === 'user' 且 content 以
//   包装语首句常量 COMPRESS_SUMMARY_OPEN 开头；非此形态原样走 clipHistoryTail（零回归）。
// · 软超 1 条是预期语义：摘要在 limit 之外（limit 原样传给余下序列），与 clipHistoryTail
//   的工具对原子守卫同款取舍——窗口软超胜过丢整块，勿「顺手修正」成严格 limit 内。
export function clipHistoryKeepingSummary(history: InjectChatMessage[],
  limit: number): InjectChatMessage[] {
  if (history.length === 0 || history[0].role !== 'user' ||
    !history[0].content.startsWith(COMPRESS_SUMMARY_OPEN)) {
    return clipHistoryTail(history, limit);
  }
  const summary: InjectChatMessage = history[0];
  const rest: InjectChatMessage[] = history.slice(1);
  const clipped: InjectChatMessage[] = clipHistoryTail(rest, limit);
  const out: InjectChatMessage[] = [summary];
  return out.concat(clipped);
}

// ── 跨会话长期记忆注入（2026-09-08 记忆域，任务书 §2.4）──
// 记忆块并入发送序列的 system 位：block 空 = 原样返回（无记忆/开关关/隐私会话 = 零回归
// 逐字节不变）；首条 role='system'（composeSendMessages 的提示词注入产物）→ 合并进该条
// content 尾部（'\n\n' 连接，消息数不变——交替约束与协议 system 聚合天然满足，其余字段
// images/reasoning/toolCalls 原样随行）；无 system → 首位插入独立 system 条（其后首条
// 恒 user/assistant，无连续同角色，不走 merge）。
// ★ 调用顺序红线（sse-assert 断言 + ChatSendCtrl 落点注释互证）：必须在
// composeSendMessages **之后**调用——该函数的 system 分支遇「历史已含 system」会整体跳过，
// 若提前调用记忆块会把会话/助手/系统提示词吞掉。
// ★ 2026-09-13 技能层笔补第二条：记忆块必须在技能清单 appendSystemSkills **之后**调用
//（稳定块在前、易变块在后——两块同住一条 system 消息，顺序即缓存前缀命中段的长度；
// 理由与判据见下方 appendSystemSkills 头注释）。
export function appendSystemMemory(history: InjectChatMessage[],
  block: string): InjectChatMessage[] {
  if (block === '') {
    return history;
  }
  if (history.length > 0 && history[0].role === 'system') {
    const merged: InjectChatMessage[] = [];
    merged.push({ role: 'system', content: history[0].content + '\n\n' + block,
      images: history[0].images, reasoning: history[0].reasoning,
      toolCalls: history[0].toolCalls, reasoningItems: history[0].reasoningItems });
    for (let i = 1; i < history.length; i++) {
      merged.push(history[i]);
    }
    return merged;
  }
  const injected: InjectChatMessage[] = [{ role: 'system', content: block }];
  for (const m of history) {
    injected.push(m);
  }
  return injected;
}

// ── 技能清单注入（2026-09-13 技能层笔 1，方案-技能层-20260913 §2.4）──
// 「可用技能」清单（名称 + 触发描述）并入发送序列的 system 位：表单 = 头行调用引导 + 逐行
// 「- 名称：触发描述」。形态与 appendSystemMemory 完全同构（合并进首条 system 尾部
// '\n\n' 连接、消息数不变；无 system 则首位插入独立 system 条）——两函数的**差别只在调用
// 顺序**，而顺序就是本笔的设计点：
// ★ 调用顺序红线（sse-assert/assert-app-domain 断言 + ChatSendCtrl 落点注释三处互证）：
//   ①必须在 composeSendMessages **之后**（该函数 system 分支遇「历史已含 system」会整体
//     跳过——提前调用会把会话/助手/系统提示词吞掉，appendSystemMemory 同一条红线）；
//   ②必须在 appendSystemMemory **之前**——知识块稳定性排序：技能清单是低频稳定块（只在
//     技能库/助手启用集变更时变），记忆块是高频易变块（每次自动整理都可能变），稳定块放
//     前 = 请求前缀缓存（Anthropic cache_control 等）命中段更长。两块同住一条 system 消息，
//     顺序反了会让缓存前缀从记忆块处就断掉。
// block 空 = 原样返回（无启用技能 = 零注入，请求与无技能版逐字节一致——负向钉）；
// ★ 正文边界：本函数只吃调用方传进来的「清单」文本，技能**正文**永不进 system（只走
// use_skill 工具结果通道）——调用方 SkillText.composeSkillManifest 结构上就不含正文。
export function appendSystemSkills(history: InjectChatMessage[],
  block: string): InjectChatMessage[] {
  if (block === '') {
    return history;
  }
  if (history.length > 0 && history[0].role === 'system') {
    const merged: InjectChatMessage[] = [];
    merged.push({ role: 'system', content: history[0].content + '\n\n' + block,
      images: history[0].images, reasoning: history[0].reasoning,
      toolCalls: history[0].toolCalls, reasoningItems: history[0].reasoningItems });
    for (let i = 1; i < history.length; i++) {
      merged.push(history[i]);
    }
    return merged;
  }
  const injected: InjectChatMessage[] = [{ role: 'system', content: block }];
  for (const m of history) {
    injected.push(m);
  }
  return injected;
}
