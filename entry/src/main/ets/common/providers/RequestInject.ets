// 注入组装域（自 RequestCompose.ets 域级拆出，方法体原样搬迁行为不变）。零 import 纯函数
// 约束（scripts/sse-assert.mjs 与 assert-app-domain / assert-skill-domain /
// assert-knowledge-domain / assert-feature-domain 各复制本文件为 .ts 直跑——线上同一实现的
// 行为判据，故本地接口自持同构声明）。
// ★ 工具对原子性双守卫（真机 HTTP 400 修复）：发送历史含工具轮（assistant(toolCalls) 行 +
// 相邻 N 条 role='tool' 结果行为一个原子组）后，本域两个变换都可能把组撕开——①clipHistoryTail
// 裸 slice 截取边界落进组中间 = 请求以孤儿 tool 行开头；②mergeConsecutiveSameRole 合并重建
// 对象只带四字段，toolCallId/toolName/toolCalls 全丢（一轮并行多工具的结果行恰为相邻同
// role='tool'，system 注入路径必过 merge）——两形态都令四协议配对校验 400。守卫见两函数处注释。
// 适配口径 = 只适配协议规格不逐厂商特判；user 注入 = 拼接式（不产生新消息，交替约束与缓存
// 断点天然规避，RikkaHub #1101 教训反向实现）；assistant 注入 = 独立消息 + 连续同角色
// merge 守卫。组合语义与协议适配细则见 docs/规范-数据存储获取刷新方案.md §3.5。

// 对话消息（与 AiTypes.AiChatMessage / RequestCompose.ComposeChatMessage 同构：role 事实值
// 'system' | 'user' | 'assistant' | 'tool'；images 仅 user 消息携带——注入只动 content 字符串）。
// 字段族均为「重建对象须随行带的防丢面」，丢一个 = 配对断裂或缓存信号静默失效：
// · reasoning（仅 assistant，回传历史思考——OpenAI 路径落点，Anthropic/Gemini 忽略）；
// · toolCalls（仅 assistant）/ toolCallId + toolName（仅 role='tool'）——发送历史含工具轮时
//   由调用方随 AiChatMessage[] 结构兼容直穿，本域只判在场与角色保配对完整，内容不消费
//   （方言翻译在 RequestCompose）；
// · reasoningItems（仅 assistant 工具轮——Responses 官方端点工具轮保真料，同 toolCalls 守卫族）；
// · volatileTime（提示词注入内容含 volatile 时间变量标记——仅发送组装期内存字段，序列化层
//   不输出；语义见 PromptInjectConfig 同字段注释）；
// · createdAt（消息创建时刻毫秒，供 injectTimeReminders 间隔判定——序列化层不输出，仅
//   user/assistant 行携带，tool 结果行不带〔间隔语义 = 距上一条对话消息〕）；
// · systemTailChars（波动 system 尾段字符数——仅发送组装期内存字段，序列化层不输出；设置点
//   唯一 = appendSystemKnowledge 覆写为知识块长度，语义见字段处注释）。
interface InjectChatMessage {
  role: string;
  content: string;
  images?: InjectImagePart[];
  reasoning?: string;
  toolCalls?: InjectToolCall[];
  toolCallId?: string;
  toolName?: string;
  reasoningItems?: InjectReasoningItem[];
  volatileTime?: boolean;
  systemTailChars?: number;
  createdAt?: number;
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
  // volatile 时间变量标记（时间感知治理）：content 原文（替换前）含 {{time}}/{{datetime}} 时
  // ChatPromptState.applyVariables 置 true——仅发送组装期内存字段，不落库不序列化；
  // composeSendMessages 透传到注入产生的消息，最终由 composeAnthropicBody 消费（volatile 降级
  // 缓存断点）。编辑页保存链不置本字段（undefined = 无标记，注入恒走 applyVariables 产新路）
  volatileTime?: boolean;
}

// 知识注入计划（世界书关键词触发产物——ChatSnapshotCtrl.buildKnowledgeBlock 产，
// ChatSendCtrl.assembleRound 消费）：systemBlock = 系统位命中块（composeKnowledgeSystemBlock
// 产物，'' = 无——appendSystemKnowledge 原样返回零回归）；depthInjects = 深度/非系统身份命中
// 条目（逐条 PromptInjectConfig 走 composeSendMessages 单配置路径，应用次序 = 深度降序、
// 同深度按命中序）。空 plan（两字段空）= 请求与不装本功能逐字节一致（负向钉）
export interface KnowledgeInjectPlan {
  systemBlock: string;
  depthInjects: PromptInjectConfig[];
}

// 知识注入估算文本（**面板「知识注入」分段**的数据口径单源——ChatContextUsage.computeLive
// 活算用，禁各写一份拼接循环）：systemBlock 与深度条目 content 以 '\n\n' 连接；空 plan = ''
//（分段不列）。★ 发送链 beginRound 分母侧**不用本函数**——其估算历史为最终发送序列（已含
// 深度注入的落行文本），知识段只取 plan.systemBlock，再计全量即双算；本函数是「历史为注入前
// 序列」的面板活算口径，两路总量各自恰好一遍
export function knowledgeEstimateText(plan: KnowledgeInjectPlan): string {
  let text: string = plan.systemBlock;
  for (const inject of plan.depthInjects) {
    text = text === '' ? inject.content : text + '\n\n' + inject.content;
  }
  return text;
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
    // volatileTime 随注入条透传（cache 断点降级信号——重建对象禁丢字段族）
    const injected: InjectChatMessage[] =
      [{ role: 'system', content: inject.content, volatileTime: inject.volatileTime }];
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
    // 原样随行（注入只动 content 字符串）；volatileTime 两侧或（拼接条承载双方内容，任一含
    // volatile 即标记）
    const joined: InjectChatMessage[] = [];
    for (let i = 0; i < history.length; i++) {
      if (i === target) {
        joined.push({ role: 'user', content: inject.content + '\n\n' + history[i].content,
          images: history[i].images,
          volatileTime: history[i].volatileTime === true || inject.volatileTime === true ?
            true : undefined });
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
          // merge 守卫：注入并入后邻 assistant 前部（维持交替，消息数不变）；重建对象须
          // 防丢字段全量随行带——reasoning（回传思考契约）/ toolCalls（工具对守卫——落点
          // 紧邻工具轮 assistant 时丢 toolCalls = 该轮 tool 行成孤儿，同样 400）/
          // reasoningItems（Responses 工具轮保真料，同族）/ volatileTime 两侧或
          joined.push({ role: 'assistant', content: inject.content + '\n\n' + next.content,
            images: next.images, reasoning: next.reasoning, toolCalls: next.toolCalls,
            reasoningItems: next.reasoningItems,
            volatileTime: next.volatileTime === true || inject.volatileTime === true ?
              true : undefined });
          i++; // 跳过已并入的 next
        } else {
          joined.push({ role: 'assistant', content: inject.content,
            volatileTime: inject.volatileTime });
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
// 官方拒绝连续同角色；OpenAI/Responses 无害——统一合并行为一致）：连续同角色 content 以
// '\n\n' 连接（与既有 Anthropic 多 system 连接同分隔）；images 数组同并（防御性语义——正常
// 对话不产生连续 user 带图）；reasoning 同并以 '\n\n' 连接（OpenAI 路径落点单串，
// Anthropic/Gemini 无落点忽略）。导出供 ChatHistoryBuilder 摘要置顶后过本守卫（摘要条与
// 保留段首条可能同为 user），既有调用面照旧。
// ★ 工具对守卫（真机 400 修复）：role='tool' 行与带 toolCalls 的 assistant 行不参与同角色
// 合并——合并重建的对象承载不了 toolCallId/toolName/toolCalls = 配对断裂恒 400（一轮并行
// 多工具的结果行恰为相邻同 role='tool'，system 注入路径必过本守卫）。交替约束对 tool 行
// 本就由协议 compose 层满足（anthropic/gemini 连续 tool 行聚成单条 user 消息，openai/
// responses 无交替要求，sse-assert ㉔ 组既有形态），此处不合并零副作用。
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
      // volatileTime 两侧或：合并重建丢标记 = cache 断点降级静默失效（该跳过时没跳过）
      const volatileTime: boolean | undefined =
        last.volatileTime === true || m.volatileTime === true ? true : undefined;
      // systemTailChars 取后者：合并串尾部由 m 决定——m 无标记则合并结果无尾段；勿改
      // 「两侧或」（尾段语义 = 「content 末尾 N 字符」，或运算会把 last 的旧标记错挂到新的尾部）
      merged[merged.length - 1] = { role: m.role, content: last.content + '\n\n' + m.content,
        images: images, reasoning: reasoning, volatileTime: volatileTime,
        systemTailChars: m.systemTailChars };
    } else {
      merged.push(m);
    }
  }
  return merged;
}

// ── 上下文消息数截取 ──
// 发送序列尾部截取（应用层参数，不进请求体）：limit ≤ 0 / ≥ 序列长度 = 原样返回（不
// 截取零回归）；否则保尾部 limit 条（★ 计数含本条 user——调用点在 push 本条之后、注入
// 之前：身份注入永不丢，首条历史被截属预期语义「只发最近 N 条」）。零 import 纯函数
// （sse-assert 同源直跑断言）。
// ★ 工具对原子性守卫（真机 400 修复）：截取边界落进工具原子组中间会让请求以孤儿 tool 行
// 开头（配对 assistant 被截——四协议配对校验 400，对话越长越易命中）。处置 = 边界向前回退
// 到组首 assistant 行保整对；取舍 = 窗口软超 limit 几条优于丢整轮（limit 本就是「至少最近
// N 条」软上限语义）。调用点在 push 本条 user 之后——尾边界恒为本条 user 不落组中，无需
// 尾侧守卫；回退撞到 0 仍是 tool 行（脏序列防御）= 全量带上不截。
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

// ── 上下文压缩·摘要包装语与截尾保活 ──
// 包装语两段常量 + 拼接函数的单一来源在本件（零 import 叶子，ChatHistoryBuilder 从本件
// import）：组装侧（置顶拼接）与截尾识别侧（首句判据）共用同一来源，**禁两处各写一份
// 字面量**。尾段续跑提示不可省——少了它模型会回一句「我已了解之前的对话，我们继续吧」。
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
// · 软超 1 条是预期语义：摘要在 limit 之外（limit 原样传给余下序列），与工具对原子守卫
//   同款取舍——勿「顺手修正」成严格 limit 内。
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

// ── system 块追加通用函数（注入链治理 P1-b：appendSystemMemory / Skills / Knowledge 三
// 函数逐字同构合并为单函数；三者保留为薄转出，导出面与既有断言 import 面零变化）──
// 形制：block 空 = 原样返回（零注入，请求逐字节同无该块版——负向钉）；首条 role='system'
// → 合并进该条 content 尾部（'\n\n' 连接，消息数不变——交替约束与协议 system 聚合天然
// 满足，重建对象字段族全量随行带防丢）；无 system → 首位插入独立 system 条（其后首条恒
// user/assistant，无连续同角色，不走 merge）。
// ★ tailChars 语义（第三参，可选）：**仅合并路径生效**——传值 = 覆写 systemTailChars 为
// 该块长度（波动尾段标记，设置点唯一语义「本块 = system 内容末尾的波动尾段」）；缺省 =
// 透传 history[0].systemTailChars（既有值不丢）。首插路径**恒不设标记**（无论是否传
// tailChars）——无稳定前缀可挂断点，保持 content = block 现状零回归（golden「无提示词 +
// 知识块独占 system」分支用例守此）。
// ★ 调用顺序红线（三消费族互证，sse-assert / assert-app-domain 断言 + ChatRoundAssembly
//   落点注释）：①必须在 composeSendMessages **之后**——该函数 system 分支遇「历史已含
//   system」会整体跳过，提前调用会把会话/助手/系统提示词吞掉；②稳定段排序：技能清单
//   （低频稳定）→ 记忆块（库级变）→ 知识命中块（逐轮变 = 波动 system 尾段）——两块同住
//   一条 system 消息，顺序即缓存前缀命中段长度，反了会让缓存前缀从记忆块处断掉
//   （Anthropic 显式断点只覆盖稳定段，尾段变化不再连带断点失效）。mergeConsecutiveSameRole
//   的 systemTailChars 取后者语义与合并路径覆写正交（merge 只在「两条 system 相邻」时介入，
//   正常链序不达）。
export function appendSystemBlock(history: InjectChatMessage[], block: string,
  tailChars?: number): InjectChatMessage[] {
  if (block === '') {
    return history;
  }
  if (history.length > 0 && history[0].role === 'system') {
    const merged: InjectChatMessage[] = [];
    // volatileTime 随行带（防丢族——system 注入条重建防丢，丢字段 = cache 断点降级信号
    // 静默失效）；systemTailChars = 传值覆写 / 缺省透传（见函数头注释 tailChars 段）
    merged.push({ role: 'system', content: history[0].content + '\n\n' + block,
      images: history[0].images, reasoning: history[0].reasoning,
      toolCalls: history[0].toolCalls, reasoningItems: history[0].reasoningItems,
      volatileTime: history[0].volatileTime,
      systemTailChars: tailChars !== undefined ? tailChars : history[0].systemTailChars });
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

// ── 跨会话长期记忆注入（薄转出——形制与顺序红线见 appendSystemBlock 头注释；记忆块属
// 库级变稳定段，无波动尾段标记）──
export function appendSystemMemory(history: InjectChatMessage[],
  block: string): InjectChatMessage[] {
  return appendSystemBlock(history, block);
}

// ── 技能清单注入（薄转出——正文边界红线照旧：本函数只吃调用方传进来的「清单」文本，技能
// **正文**永不进 system〔只走 use_skill 工具结果通道，调用方 SkillText.composeSkillManifest
// 结构上就不含正文〕）──
export function appendSystemSkills(history: InjectChatMessage[],
  block: string): InjectChatMessage[] {
  return appendSystemBlock(history, block);
}

// ── 知识命中块注入（薄转出——合并路径覆写 systemTailChars = block.length〔波动尾段标记，
// Anthropic 组装据此拆稳定块/尾块〕；无 system 首插不设标记，见 appendSystemBlock 头注释
// tailChars 段。深度组注入不走这里——depthInjects 由调用方逐条经 composeSendMessages 应用）──
export function appendSystemKnowledge(history: InjectChatMessage[],
  block: string): InjectChatMessage[] {
  return appendSystemBlock(history, block, block.length);
}

// ── 时间间隔提醒（时间感知治理·件 4；零 import 纯函数，sse-assert 直跑面）──
// 间隔达阈值的 user 消息前插入一条合成提醒（照 RikkaHub/chatbox 形态——提醒内容由**消息
// 自身的 createdAt** 推导，不用实时墙钟 ⇒ 每次重建字节相同 ⇒ 前缀缓存友好）。
// enabled = false / thresholdMinutes ≤ 0 / 无可比前序 ⇒ 原样返回（零回归）。
// 输出末尾过 mergeConsecutiveSameRole（提醒与触发它的 user 相邻 = 连续同角色，
// Anthropic/Gemini 拒收；合并后实际形态 = 提醒并入该 user 的 content 前部，与「拼接式」
// 注入同族，四协议零特判）。
// ★ 调用顺序（ChatSendCtrl.assembleRound）：必须在 composeSendMessages **之后**（其 user
// 拼接式注入按 depth 定位目标 user 消息，提醒先插入会改变目标下标语义——提醒本身也是
// user 消息）、在 appendSystemSkills / appendSystemMemory / appendSystemKnowledge 之前
//（三者为 system 块追加不受影响）。提醒不落库不上屏——重试经 buildRequestHistory 重建
// 零累积，工具轮续轮沿用首轮产物不再重跑。
export function injectTimeReminders(history: InjectChatMessage[], enabled: boolean,
  thresholdMinutes: number): InjectChatMessage[] {
  if (!enabled || thresholdMinutes <= 0) {
    return history;
  }
  const result: InjectChatMessage[] = [];
  // 游标 = 最近一条有 createdAt 的非 system 消息时刻（推进者 = user/assistant 行；tool
  // 结果行不带 createdAt 不推进——语义 = 「距上一条对话消息」，工具轮与助手回复同刻邻近）
  let lastSeenTs: number | undefined = undefined;
  for (const m of history) {
    if (m.role === 'user' && lastSeenTs !== undefined && m.createdAt !== undefined) {
      const gap: number = m.createdAt - lastSeenTs;
      // 毫秒比较（>=，边界即触发）；createdAt 缺失的消息跳过判定、游标不变（fail-open
      // 不插不炸）；负 gap（乱序防御）恒小于阈值自然不插
      if (gap >= thresholdMinutes * 60000) {
        result.push({ role: 'user', content: formatTimeReminder(m.createdAt, gap) });
      }
    }
    if (m.role !== 'system' && m.createdAt !== undefined) {
      lastSeenTs = m.createdAt;
    }
    result.push(m);
  }
  return mergeConsecutiveSameRole(result);
}

// 星期名（零 import 自持——本文件禁 import PromptVariables，会破零 import 约束与
// sse-assert 直跑；文本与 PromptVariables.WEEKDAY_NAMES 同款「日…六」）
const REMINDER_WEEKDAY_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];

function reminderPad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

// 提醒文本（逐字定稿，纯函数可直跑断言）：时刻取该条 user 消息自身的 createdAt（本地
// 时区，YYYY-MM-DD HH:mm 两位补零 + 星期）；间隔分档 = <60 分钟「N 分钟」/ <1440 分钟
// 「N 小时〔 M 分钟〕」/ ≥1440 分钟「N 天〔 M 小时〕」（余 0 时省略余数段）
export function formatTimeReminder(createdAtMs: number, gapMs: number): string {
  const d: Date = new Date(createdAtMs);
  const date: string = d.getFullYear() + '-' + reminderPad2(d.getMonth() + 1) +
    '-' + reminderPad2(d.getDate());
  const time: string = reminderPad2(d.getHours()) + ':' + reminderPad2(d.getMinutes());
  const weekday: string = '星期' + REMINDER_WEEKDAY_NAMES[d.getDay()];
  const minutes: number = Math.floor(gapMs / 60000);
  let span: string;
  if (minutes < 60) {
    span = minutes + ' 分钟';
  } else if (minutes < 1440) {
    const hours: number = Math.floor(minutes / 60);
    const rem: number = minutes % 60;
    span = rem === 0 ? hours + ' 小时' : hours + ' 小时 ' + rem + ' 分钟';
  } else {
    const days: number = Math.floor(minutes / 1440);
    const remHours: number = Math.floor((minutes % 1440) / 60);
    span = remHours === 0 ? days + ' 天' : days + ' 天 ' + remHours + ' 小时';
  }
  return '<time_reminder>当前时间 ' + date + ' ' + time + ' ' + weekday +
    '，距上一条消息已过 ' + span + '</time_reminder>';
}
