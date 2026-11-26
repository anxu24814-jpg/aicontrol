// 会话上下文用量域（自 ChatSendCtrl 拆出的功能域——宿主闭包 refs + 宿主接口，语义单源）。
// 本文件承载：
// · 工具声明链 collectTools——发送组装与面板活算**同一链**（两处各算 = 漂移面会让
//   「面板与实发不一致」）；
// · 锚点与校准态——pendingEstimate（发送时估算，k 分母侧）/ lastStreamPrompt（最后一流
//   真实输入，锚点）/ anchorFingerprint（连接指纹，切连接即失效）；
// · 活算 computeLive——面板打开/轮完成/切模型三处调用，产出圆环与面板共读的 ContextUsage
//  （估算 × k、分段缩放同步、全段直取上屏〔小值段合并已决明拍板整体退役〕、会话级缓存
//   命中账本聚合；「本轮输入」段 = 草稿 + 待发附件协议文本侧内容 + 视觉通道张数×900，
//   附件足迹取数单源在 AttachmentUtil.pendingAttachFootprint，与发送链载荷组装同一实现）。
// ★ 锚点五条红线（防后人改回）：
//   ①锚点只进 k 的计算，绝不直接当「已用」显示（Cline #7383：直接显示上一轮已完成请求的
//     token 数，UI 50% 实发 100%+）——本域显示值恒 = 当前序列估算 × k；
//   ②只认 input 侧 promptTokens，不认 totalTokens（Cherry 源码注释直呼 total 是
//     "bogus anchor"）——取值点在宿主 onStreamDone；
//   ③流内多帧去重前提由 ChatStreamBase.absorbUsage 的 mergeUsage take-max 承担（sse-assert
//     既有钉；Cline #10306 累加 1500 万的反面）；
//   ④k 分子分母同口径：估算序列必须全量文本（含 reasoning 回传与图片折算）；
//   ⑤异常值挡在 k 之外：calibrateFactor 钳制 [0.2, 5]、哨兵/NaN/≤0 回 1（LibreChat #14661）。
// ★ 两口径并存纪律：轮级用量四值（计费口径，跨流求和；见 ChatUsageRoundCtrl 域头注释）与
//   锚点 lastStreamPrompt（上下文规模口径，最后一流胜出）语义不同**都不许「统一」**——工具
//   轮 N 流后前者约为真实规模的 N 倍，拿它当上下文规模必放大显示（Claude Code #84738 同款）。
import { PendingAttachFootprint, pendingAttachFootprint } from '../../common/AttachmentUtil';
import { AiChatMessage, AiConnection, AiToolCall, AiToolDef, AssistantAdvancedParams,
  PendingAttachment } from '../../common/providers/AiTypes';
import { ToolEntry, isModeDriven, isWebDomainTool,
  registerBuiltinTools, toolRegistry } from '../../common/providers/ToolTypes';
import { registeredTemplateEntries } from '../../common/providers/HttpTemplate';
import { registeredMcpEntriesFor } from '../../common/providers/McpTools';
import { TOOL_SEARCH_MEMORY, TOOL_USE_SKILL, TOOL_HTTP_REQUEST,
  TOOL_ENV_LIST } from '../../common/providers/ToolIds';
import { composeUseSkillSchema } from '../../common/SkillText';
import { isMemoryToolReadMode } from '../../common/MemoryGen';
import { contextWindowForConnection } from '../../common/store/ProviderDb';
import { SessionUsageTotals, sessionUsageTotals } from '../../common/store/UsageStatsDb';
import { currentCtxFactor, saveCtxFactor } from '../../common/AppPreferences';
import { calibrateFactor, estimateSegments, estimateSnapshotTotal, estimateTokens,
  ContextSegment, SendSnapshot, SendSnapshotItem, ToolCallArgLike, ToolDefGroup }
  from '../../common/TokenEstimate';
// 工具定义预算单源 + MCP 三段名反解——collectTools 尾部收口与分组产出消费
import { applyToolDefsBudget, ToolDefsBudgetResult } from '../../common/providers/ToolLimits';
// DS 官方档判据与服务端工具声明对（S2① 单源——禁另写组合判据与字面量，见 DsServerTools 头）
import { dsOfficialWebActive, dsServerToolDefs } from '../../common/providers/DsServerTools';
import { isMcpToolName, serverNameOfMcpToolName } from '../../common/McpText';
import { ChatMessage } from './ChatMessageCompose';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { chatMessagesFromRows } from './ChatMessageProjection';
import { RequestSummaryInput, readPathSummaryInput,
  conversationGraphBranch } from '../../common/chat/ChatContextSource';
import { clipHistoryKeepingSummary, KnowledgeInjectPlan,
  knowledgeEstimateText, COMPRESS_SUMMARY_OPEN } from '../../common/providers/RequestInject';
// 注入段视图（请求构成卡数据——beginRound 定格的同一份快照）
import { InjectSectionView } from '../../common/chat/InjectSections';
// 面板活算历史读口 + token 闸同链（与实发共用读口与预算函数——五处同源；BudgetRow 映射单源在编排件）
import { readRequestHistoryRows } from '../../common/chat/RequestHistorySource';
import { resolveReadRows, resolveTokenBudget, clipRoundsToTokenBudget,
  applyGateCalibration } from '../../common/chat/RequestHistoryBudget';
import { toBudgetRow, fromBudgetRow } from './ChatRequestHistoryCtrl';
import { REQUEST_HISTORY_DECOUPLE_ENABLED } from '../../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 技能上下文的收窄视图（本文件不 import ChatSendCtrl 防环；ArkTS 禁同构双接口互传，由宿主
// 侧显式构造）：manifest '' = 不注入、useSkillNames [] = 不声明 use_skill——同源于宿主 buildSkillContext
export interface ContextSkillSnapshot {
  manifest: string;
  useSkillNames: string[];
}

// 本轮注入侧快照（发送组装完成后定格，轮内不变）：systemText = 三级解析 + 变量替换后的
// 注入内容；toolDefsJson = 工具声明拼串（toolDefsJsonOf）；maxOutput = 预留输出（0 = 不列
// 段）；knowledgeBlock = 知识注入估算文本（口径单源 knowledgeEstimateText，'' = 不列段）
export interface RoundStaticSnapshot {
  systemText: string;
  skillManifest: string;
  memoryBlock: string;
  knowledgeBlock: string;
  toolDefsJson: string;
  // 工具定义分组（**可选**——发送链快照不带分组：估算总量口径不变，缺省退化 'tools' 单段；
  // 仅面板活算 computeLive 填充按组列段）
  toolDefGroups?: ToolDefGroup[];
  // 注入段视图（**可选**——仅发送链 beginRound 定格携带；面板活算自建快照不带 → 读值走
  // ContextUsage.injectSections 回指发送链定格份，禁第二条计算链）
  injectSections?: InjectSectionView[];
  // P2 预算可见位（**可选**——降级段 key 表与「到顶仍超」标记随快照带进构成卡；缺省 = 未降级）
  degradedKeys?: string[];
  overBudgetAfter?: boolean;
  maxOutput: number;
}

// 上轮实际（面板数据源 = 末条带用量的 assistant 行——「预估」与「实测」对照可见；
// privacy 会话不挂 usage meta，恒 null = 卡不显示）
export interface LastRoundUsage {
  promptTokens: number;
  cachedTokens: number;
  completionTokens: number;
  durationMs: number;
}

// 活算产物（圆环与面板共读）。★ 可加总结构红线：usedTokens 与 segments 同乘 k（k=1 时逐值
// 不变）——「分段之和 ≤ 总量、差额 = otherTokens」，用户把各行相加能对上总数；windowTokens
// 0 = 未知（只显已用数，不显占比与分段条）；hasData false = 全空（禁渲染 0%——0 与未知必须区分）
export interface ContextUsage {
  hasData: boolean;
  usedTokens: number;
  rawEstimate: number;
  windowTokens: number;
  factor: number;
  anchored: boolean;
  segments: ContextSegment[];
  otherTokens: number;
  // 有附件尚未处理完（解析中/未开始 / 识别中——附件文本侧此刻不全，面板明细卡显一行提示；
  // 恒 false = 不算不显。★ 只影响提示行，不改估算口径：已处理完的部分照常计入）
  attachPending: boolean;
  lastUsage: LastRoundUsage | null;
  // 会话级用量累计（账本 token_usage_events 按 conversationId 聚合）：null = 无对话轮记录
  //（隐私会话旁路落库/全零），整卡隐藏；cachedTokens 0 = 有轮但零命中，该行隐藏（零噪声
  // 口径）。★ 计费口径（含工具轮每轮重发），与 usedTokens 的窗口规模口径不同基——两者禁
  // 互相换算或并列同基数展示（实证见 MEMORY_DETAIL「上下文用量面板·缓存行口径」）
  sessionTotals: SessionUsageTotals | null;
  // 请求构成段视图：beginRound 定格的同一份（「本次请求构成」卡数据源——面板与实发一致
  // 纪律）；null = 尚无发送轮定格（卡不显）
  injectSections: InjectSectionView[] | null;
  // 降级段 key 表与到顶 fail-open 标记，与 injectSections 同源（kill-switch 关 = 恒空/false）
  degradedKeys: string[];
  overBudgetAfter: boolean;
}

// 宿主闭包（ChatSendCtrl 构造注入——箭头持宿主 this 延迟求值；「子域文件不反向 import
// 宿主」的环规避形制）
export interface ChatContextUsageRefs {
  conn: () => AiConnection | null;
  webDomainAllowed: () => boolean;
  memoryParticipates: () => boolean;
  buildMemoryBlock: () => Promise<string>;
  buildSkillSnapshot: () => Promise<ContextSkillSnapshot>;
  // 知识注入计划：**面板与实发共用同一 buildKnowledgeBlock**（宿主侧实现绑
  // dataSource.allMessages()；对外只露 draftText，禁第二实现——「面板与实发一致」纪律）
  buildKnowledgeBlock: (draftText: string) => Promise<KnowledgeInjectPlan>;
  promptSystemText: (model: string) => string;
  advancedParams: () => AssistantAdvancedParams | null;
  enabledToolIds: () => string[];
  // 助手绑定的 MCP 服务器 id 清单（值源 = promptState.mcpServerIds 解析缓存）：
  // collectTools 追加段绑定消费
  mcpServerIds: () => string[];
  allMessages: () => ChatMessage[];
  // 会话 id（'' = 无——会话级缓存命中的账本聚合键；与 ChatSendCtrl 落库点同一取值口）
  conversationId: () => string;
  roundConn: () => AiConnection | null;
  roundHistory: () => AiChatMessage[];
}

// 占比（0~100；窗口未知或无数据回 -1 =「仅底环」口径）——圆环与面板共用单源（两处各写
// 一遍即漂移面）；钳 100 防 used 略超窗口的显示越界
export function contextPct(usage: ContextUsage): number {
  if (!usage.hasData || usage.windowTokens <= 0) {
    return -1;
  }
  return Math.min(100, Math.round(usage.usedTokens * 100 / usage.windowTokens));
}

// 连接指纹（providerId+model+endpoint+protocol——四元任一变即锚点失效转估算；「切服务商
// 同模型名」也失效 = 保守口径，中转与官方分词可能不同）
export function contextFingerprint(conn: AiConnection): string {
  return conn.providerId + '|' + conn.model + '|' + conn.endpoint + '|' + conn.protocol;
}

// 工具声明拼串（估算口径：name + description + parametersJson 逐条拼接；[] = '' 不列段）
export function toolDefsJsonOf(tools: AiToolDef[]): string {
  return tools.map((t: AiToolDef): string => t.name + ' ' + t.description + ' ' + t.parametersJson)
    .join('\n');
}

// 待发附件是否含服务端解析件（S2① 官方档提示参的活算侧扫描——纯函数域内小函数，与
// previewLine 同族口径）：任一附件带 remoteFileId 即真。S4 落上传链前恒 false（remoteFileId
// 无生产者——互斥回退因子不触发，官方档判据不受影响）；S4 落地后自然生效
function pendingHasServerDoc(atts: PendingAttachment[]): boolean {
  for (const a of atts) {
    if (a.remoteFileId !== undefined && a.remoteFileId !== '') {
      return true;
    }
  }
  return false;
}

// 协议历史 → 快照条目（纯映射）：system 行丢弃（内容已由提示词/技能/记忆三段单列覆盖，计入
// 即双重计数）；assistant 的 reasoning 与工具调用参数、user 的 images 随行映射
export function mapSnapshotItems(history: AiChatMessage[]): SendSnapshotItem[] {
  const items: SendSnapshotItem[] = [];
  for (const m of history) {
    if (m.role === 'system') {
      continue;
    }
    const item: SendSnapshotItem = {
      role: m.role,
      text: m.content,
      reasoning: m.role === 'assistant' ? (m.reasoning ?? '') : '',
      imageCount: m.role === 'user' && m.images !== undefined ? m.images.length : 0,
      // 工具调用参数随行映射：显式构造 ToolCallArgLike——剪掉 id 不进快照（计数单源
      // toolCallsTokens 不认 id）+ 规避 ArkTS 数组直传问题
      toolCalls: m.role === 'assistant' && m.toolCalls !== undefined
        ? m.toolCalls.map((tc: AiToolCall): ToolCallArgLike =>
          ({ name: tc.name, argsJson: tc.argsJson }))
        : undefined
    };
    items.push(item);
  }
  return items;
}

export class ChatContextUsageCalc {
  private refs: ChatContextUsageRefs;
  // 发送时估算（k 分母侧）：每次起流前 refreshEstimate 对齐「本流实际请求」——恒与锚点同轮同源
  private pendingEstimate: number = 0;
  // 锚点（-1 = 无）：最后一条成功流的 promptTokens——「当前上下文规模」的真度量；工具轮
  // 多次 onStreamDone 后者覆盖前者 = 最后一次流胜出（结构性保证，非时序侥幸）
  private lastStreamPrompt: number = -1;
  // 锚点连接指纹（'' = 无）：与 lastStreamPrompt 成对写入成对失效
  private anchorFingerprint: string = '';
  // 本轮注入侧快照（beginRound 定格；finishStream 后残留无害——活算不读它）
  private roundStatic: RoundStaticSnapshot | null = null;
  // 最近一次 collectTools 的工具定义预算摘要：发送组装与面板活算同一链各调一次（同步纯
  // 函数无竞态——面板读本成员读到的必是自己那一次调用的产物）；null = 尚未跑过
  private lastToolDefsBudget: ToolDefsBudgetResult | null = null;

  constructor(refs: ChatContextUsageRefs) {
    this.refs = refs;
  }

  // 发送组装完成（宿主 assembleRound 末尾）：定格注入侧快照 + 首次估算（sentHistory = 截尾
  // 后的最终发送序列——与实发同链同源）
  beginRound(staticSnapshot: RoundStaticSnapshot, sentHistory: AiChatMessage[]): void {
    this.roundStatic = staticSnapshot;
    this.pendingEstimate = this.estimateOf(staticSnapshot, sentHistory);
  }

  // 每次起流前刷新（宿主 attemptCurrent 咽喉点——首流/失败切换/工具续轮全经此）
  refreshEstimate(history: AiChatMessage[]): void {
    if (this.roundStatic === null) {
      return;
    }
    this.pendingEstimate = this.estimateOf(this.roundStatic, history);
  }

  // 锚点记录 + k 校准落键（宿主 onStreamDone——红线②只认 input 侧由调用方保证）：k = 锚点
  // ÷ 本流估算（钳制 [0.2,5]、异常回 1），按 (providerId, model) 双键前插落偏好键（上限 20；
  // 同模型名跨服务商不串 k，写侧顺手清退 legacy 单键条目）
  recordAnchor(promptTokens: number, conn: AiConnection): void {
    this.lastStreamPrompt = promptTokens;
    this.anchorFingerprint = contextFingerprint(conn);
    saveCtxFactor(conn.providerId, conn.model, calibrateFactor(promptTokens, this.pendingEstimate));
  }

  // 发送时估算（k 分母侧）：pendingAttachText 恒 ''——sentHistory 里本轮 user 已含附件正文，此处再计即双算
  private estimateOf(staticSnapshot: RoundStaticSnapshot, history: AiChatMessage[]): number {
    return estimateSnapshotTotal(this.snapshotOf(staticSnapshot, history, '', 0, ''));
  }

  private snapshotOf(staticSnapshot: RoundStaticSnapshot, history: AiChatMessage[],
    draftText: string, imageCount: number, pendingAttachText: string): SendSnapshot {
    const snapshot: SendSnapshot = {
      systemText: staticSnapshot.systemText,
      skillManifest: staticSnapshot.skillManifest,
      memoryBlock: staticSnapshot.memoryBlock,
      knowledge: staticSnapshot.knowledgeBlock,
      toolDefsJson: staticSnapshot.toolDefsJson,
      toolDefGroups: staticSnapshot.toolDefGroups ?? null,
      history: mapSnapshotItems(history),
      draftText: draftText,
      imageCount: imageCount,
      pendingAttachText: pendingAttachText,
      maxOutput: staticSnapshot.maxOutput
    };
    return snapshot;
  }

  // 待发附件足迹（面板活算侧）：附件数组由页面经门面传入，取数实现单源在
  // AttachmentUtil.pendingAttachFootprint（发送链载荷组装同一实现，禁本件重写分流判据）。
  // ★ 文本侧含读盘——读失败不阻断面板：退化为「不计入 + pending 提示」，宁低勿假（静默吞错
  // = 面板显示假低值还告诉用户「准」）
  private attachFootprint(atts: PendingAttachment[], hasVision: boolean): PendingAttachFootprint {
    try {
      return pendingAttachFootprint(atts, hasVision);
    } catch (e) {
      return { text: '', imageCount: 0, pending: true };
    }
  }

  // 工具声明链（自 ChatSendCtrl.assembleRound 整体搬迁，判据逐句等价，断言钉单源）：内置
  // 注册幂等 → 助手启用清单（联网域过滤收敛进 webDomainAllowed 单判据）→ 模式驱动残留剔除
  // → 记忆按需读取追加 → 技能加载追加 → 末尾预算收口（超预算先 description 分档降档、仍超
  // MCP 尾端优先整件移除，内置永不移除——见 applyToolDefsBudget）→ ★ DS 官方档声明段
  //（S2①，2026-11-14：官方档成立 = 联网域两件剔除 + 末尾 concat 两 server def——**预算
  // 收口之后**，server def 不参与降档；「声明/估算/token 闸/执行」四面同源不变量保持——
  // 估算侧 toolDefsJsonOf 消费同一返回值，server def 以 serverType 标记）。
  // （原跨会话检索隐私闸已随隐私会话笔退役删除）
  // ★ S2① 提示参（官方档路由的两个本轮因子——判据单源 dsOfficialWebActive）：
  // roundConn = 本轮连接（缺省回落 refs.conn()——发送组装传 roundConn 参数、面板活算传
  // refs.conn()）；hasServerDoc = 本轮 user 是否带服务端解析件（S4 落生产链——S2 期扫描
  // AiImagePart.remoteFileId，无生产者恒 false = 互斥回退因子不触发）。
  collectTools(skill: ContextSkillSnapshot, roundConn?: AiConnection | null,
    hasServerDoc?: boolean): AiToolDef[] {
    registerBuiltinTools();
    let roundTools: AiToolDef[] = toolRegistry.defsFor(this.refs.enabledToolIds());
    if (!this.refs.webDomainAllowed()) {
      roundTools = roundTools.filter((t: AiToolDef): boolean => !isWebDomainTool(t.name));
    }
    roundTools = roundTools.filter((t: AiToolDef): boolean => !isModeDriven(t.name));
    // （原代码工作台总开关过滤段已随键退役——三件脚本族改随助手清单进出，声明面无需全局过滤）
    if (this.refs.memoryParticipates() && isMemoryToolReadMode()) {
      const def: ToolEntry | undefined = toolRegistry.get(TOOL_SEARCH_MEMORY);
      if (def !== undefined) {
        roundTools.push({ name: def.name, description: def.desc,
          parametersJson: def.parametersJson });
      }
    }
    if (skill.useSkillNames.length > 0) {
      const skillDef: ToolEntry | undefined = toolRegistry.get(TOOL_USE_SKILL);
      if (skillDef !== undefined) {
        roundTools.push({ name: skillDef.name, description: skillDef.desc,
          parametersJson: composeUseSkillSchema(skill.useSkillNames) });
      }
    }
    // HTTP 凭据查名追加：助手启用清单含 http_request 时随行声明 env_list（与 HTTP 工具同
    // 进退；判定取助手清单而非 defsFor 产物——语义 = 「这个助手配了 HTTP 能力」）
    if (this.refs.enabledToolIds().includes(TOOL_HTTP_REQUEST)) {
      const envDef: ToolEntry | undefined = toolRegistry.get(TOOL_ENV_LIST);
      if (envDef !== undefined) {
        roundTools.push({ name: envDef.name, description: envDef.desc,
          parametersJson: envDef.parametersJson });
      }
      // HTTP 请求模板随行（slug = tpl_*）：与 env_list 同闸同进退——助手开了 http_request
      // 即可使用全部模板；本处只读注册表现值（同步链零 IO，同步性由启动兜底与写侧保证）
      for (const tplEntry of registeredTemplateEntries()) {
        roundTools.push({ name: tplEntry.name, description: tplEntry.desc,
          parametersJson: tplEntry.parametersJson });
      }
    }
    // MCP 工具追加段：绑定口径 = 助手勾选服务器（assistants.mcpServers，经 refs.mcpServerIds）
    // ∩ 服务器 enabled（停用条目已由 syncMcpTools 注销），经 registeredMcpEntriesFor 读注册表
    // 现值——**同步读零 IO**（发送链热路径；原「控制台一行闸」已随控制台退役，绑定面单层）
    for (const mcpEntry of registeredMcpEntriesFor(this.refs.mcpServerIds())) {
      roundTools.push({ name: mcpEntry.name, description: mcpEntry.desc,
        parametersJson: mcpEntry.parametersJson });
    }
    // 预算收口（降级只发生在本单源内——声明 / 估算 / token 闸 / 执行「未声明不执行」四面
    // 自动同源）：超预算先全量 description 分档降档，仍超按 MCP 尾端优先整件移除；摘要留
    // 成员供面板活算拼组行尾注
    const budgeted: ToolDefsBudgetResult = applyToolDefsBudget(roundTools);
    this.lastToolDefsBudget = budgeted;
    // DS 官方档声明段（S2①）：官方档成立（kill × 偏好 × 连接四合一 × 联网域允许 × 无服务端
    // 解析件——互斥回退因子在判据末位）= 联网域两件剔除 + 末尾 concat 两 server def。剔除在
    // 预算收口之后（预算吃全量含自带联网两件——剔除只改声明面不改降档序）；server def 短串
    // 零参数，token 闸免降档（不参与 applyToolDefsBudget）
    const officialConn: AiConnection | null =
      roundConn !== undefined ? roundConn : this.refs.conn();
    if (dsOfficialWebActive(officialConn, this.refs.webDomainAllowed(), hasServerDoc === true)) {
      return budgeted.tools.filter((t: AiToolDef): boolean => !isWebDomainTool(t.name))
        .concat(dsServerToolDefs());
    }
    return budgeted.tools;
  }

  // 工具定义分组：把 collectTools 产物按来源分桶——非 MCP 件归「工具·内置」，MCP 件按三段
  // 名反解服务器名归「工具·MCP·<服务器名>」；组序 = 追加序首见序。每组拼串复用
  // toolDefsJsonOf（分组段和 = 旧单段，加总红线由 TokenEstimate 锚定）；空组不列段。该
  // server 超预算整件移除时 label 尾注被移除件数（读 lastToolDefsBudget，与入参出自同一次
  // collectTools 调用，配套不漂）
  private toolDefGroupsOf(toolDefs: AiToolDef[]): ToolDefGroup[] {
    const keys: string[] = [];
    const piles: AiToolDef[][] = [];
    for (const t of toolDefs) {
      const key: string = isMcpToolName(t.name) ? serverNameOfMcpToolName(t.name) : '';
      let idx: number = keys.indexOf(key);
      if (idx < 0) {
        keys.push(key);
        piles.push([]);
        idx = keys.length - 1;
      }
      piles[idx].push(t);
    }
    const budget: ToolDefsBudgetResult | null = this.lastToolDefsBudget;
    const groups: ToolDefGroup[] = [];
    for (let i: number = 0; i < keys.length; i++) {
      const defsJson: string = toolDefsJsonOf(piles[i]);
      if (defsJson === '') {
        continue;
      }
      let label: string = keys[i] === '' ? '工具·内置' : '工具·MCP·' + keys[i];
      if (keys[i] !== '' && budget !== null) {
        let dropped: number = 0;
        for (const serverName of budget.droppedServerNames) {
          if (serverName === keys[i]) {
            dropped += 1;
          }
        }
        if (dropped > 0) {
          label += '（' + dropped + ' 件超预算未带）';
        }
      }
      groups.push({ key: keys[i] === '' ? 'tools_builtin' : 'tools_mcp',
        label: label, defsJson: defsJson });
    }
    return groups;
  }

  // 上轮实际（末条带用量的 assistant 行；输入 = 总量 − 输出——ChatMessageItem.usagePromptCount
  // 同口径，负值防御归零）
  private lastRoundUsage(): LastRoundUsage | null {
    const messages: ChatMessage[] = this.refs.allMessages();
    for (let i = messages.length - 1; i >= 0; i--) {
      const m: ChatMessage = messages[i];
      if (m.kind === 'assistant' && m.usageTokens !== undefined) {
        const total: number = m.usageTokens;
        const completion: number = m.usageCompletionTokens ?? 0;
        const usage: LastRoundUsage = {
          promptTokens: total - completion > 0 ? total - completion : 0,
          cachedTokens: m.usageCachedTokens ?? 0,
          completionTokens: completion,
          durationMs: m.usageDurationMs ?? 0
        };
        return usage;
      }
    }
    return null;
  }

  // 活算（面板打开 / 轮完成 / 切模型——打字与生成中不刷）：异步三查与发送组装同源（记忆块
  // / 技能清单 / 窗口值）；同步面 = 截尾后历史按 role 分桶 + 工具声明同链。草稿 / 待发附件 /
  // 有无视觉由调用方带入。失败路径不抛错——各环节降级（记忆 ''、技能空、窗口 0、k=1），
  // 显示面按未知口径呈现
  async computeLive(draftText: string, attachments: PendingAttachment[],
    hasVision: boolean): Promise<ContextUsage> {
    const conn: AiConnection | null = this.refs.conn();
    const footprint: PendingAttachFootprint = this.attachFootprint(attachments, hasVision);
    const memoryBlock: string = await this.refs.buildMemoryBlock();
    const skill: ContextSkillSnapshot = await this.refs.buildSkillSnapshot();
    // 知识注入计划：与 memoryBlock 同序列同源取值（面板与实发共用同一 buildKnowledgeBlock）
    const knowledgePlan: KnowledgeInjectPlan = await this.refs.buildKnowledgeBlock(draftText);
    const windowTokens: number = conn !== null ? await contextWindowForConnection(conn) : 0;
    const advanced: AssistantAdvancedParams | null = this.refs.advancedParams();
    const clipLimit: number =
      advanced !== null && advanced.contextCount !== undefined ? advanced.contextCount : 0;
    // ★ 估算侧同请求侧补路径摘要库直查——图摘要滑出读窗时估算口径与请求/面板合流（否则
    // 窗口滑出 = 估算按全文不减，与面板「已压缩」分叉）
    const pathSummary: RequestSummaryInput | null = await readPathSummaryInput(
      this.refs.conversationId());
    // 工具声明同链取一次：同一次 collectTools 产出同时喂 toolDefsJson 与分组（发送链快照
    // 不带分组的缺省退化见 RoundStaticSnapshot.toolDefGroups 注释）。★ S2① 官方档提示参：
    // 本轮连接 = refs.conn()；待发附件现值扫服务端解析件（S4 落生产链——remoteFileId 无
    // 生产者恒 false，互斥回退因子不触发；扫描 helper 域内小函数，与 previewLine 同族口径）
    const toolDefs: AiToolDef[] = this.collectTools(skill, this.refs.conn(),
      pendingHasServerDoc(attachments));
    // ★ 已知口径差（登记制，不强行同源化）：本活算的 skillManifest / memoryBlock /
    // knowledgeBlock 取**原始块**、未过 applyInjectBudget——P2 开关开启且触发降级时，明细卡
    // 数值与降级后的实发/构成卡不同。不修复理由：computeLive 缺少预算所需的同构输入（无
    // 提示词 role / 系统位判据），强行套用会制造第三种口径；kill-switch 默认关
    //（INJECT_TOTAL_BUDGET_ENABLED=false）= 当前零影响，待 P2 真机回证后定。
    const staticSnapshot: RoundStaticSnapshot = {
      systemText: this.refs.promptSystemText(conn !== null ? conn.model : ''),
      skillManifest: skill.manifest,
      memoryBlock: memoryBlock,
      knowledgeBlock: knowledgeEstimateText(knowledgePlan),
      toolDefsJson: toolDefsJsonOf(toolDefs),
      toolDefGroups: this.toolDefGroupsOf(toolDefs),
      maxOutput: advanced !== null && advanced.maxOutput !== undefined ? advanced.maxOutput : 0
    };
    // k 取该 (服务商,模型) 双键落键值（无记录 1.0 = 纯估算态；双键精确匹配，legacy 单键不
    // 命中）。★ token 闸预算经 applyGateCalibration 以同一 k 校准（与实发 fitTokens 同一
    // helper——「面板与实发一致」纪律）；显示缩放仍用原 factor（闸门与显示两角色禁混用）
    const factor: number = conn !== null ? currentCtxFactor(conn.providerId, conn.model) : 1;
    // ★ 历史来源（解耦开 = 同一读口 + 同一预算，五处同源——面板显示裁剪后的真实值）；面板
    // 无本条 userReq，读「预算 − 1」条（本条之位由 draft 段对位，与实发 rowCount 同口径）。
    // token 闸同链：固定量 = 面板注入五段拼串 + 工具声明；深度注入 user 拼接的边界差为已知
    // 近似，k 校准吸收。读口失败或解耦关 = 旧口径（窗口 + clipHistoryKeepingSummary 二次
    // 截取，kill 态逐字同旧链；降级静默不打扰面板）
    let history: AiChatMessage[] = clipHistoryKeepingSummary(
      buildRequestHistory(this.refs.allMessages(), pathSummary), clipLimit);
    if (REQUEST_HISTORY_DECOUPLE_ENABLED) {
      try {
        const branchId: string = await conversationGraphBranch(this.refs.conversationId());
        const read = await readRequestHistoryRows(this.refs.conversationId(), branchId,
          resolveReadRows(clipLimit), null);
        let rowsHistory: AiChatMessage[] =
          buildRequestHistory(chatMessagesFromRows(read.rows), pathSummary);
        const tokenBudget: number =
          applyGateCalibration(resolveTokenBudget(windowTokens), factor);
        if (tokenBudget > 0) {
          const mergedSystem: string = [staticSnapshot.systemText, staticSnapshot.skillManifest,
            staticSnapshot.memoryBlock, staticSnapshot.knowledgeBlock]
            .filter((s: string): boolean => s !== '').join('\n\n');
          const fixed: number = estimateTokens(mergedSystem) +
            estimateTokens(staticSnapshot.toolDefsJson);
          const budgetRows = rowsHistory.map(toBudgetRow);
          const clippedRows = clipRoundsToTokenBudget(budgetRows,
            tokenBudget - fixed, COMPRESS_SUMMARY_OPEN);
          if (clippedRows !== budgetRows) {
            rowsHistory = clippedRows.map(fromBudgetRow);
          }
        }
        history = rowsHistory;
      } catch (e) {
        hilog.warn(0x0001, 'ChatUsage', '面板历史读口降级（%{public}s）', (e as Error).message);
      }
    }
    // 锚点指纹比对决定 anchored（不换 k 值——锚点失效只影响面板说明行强调「估算」）
    const anchored: boolean = conn !== null && this.lastStreamPrompt > 0 &&
      contextFingerprint(conn) === this.anchorFingerprint;
    const snapshot: SendSnapshot = this.snapshotOf(staticSnapshot, history, draftText,
      footprint.imageCount, footprint.text);
    const rawEstimate: number = estimateSnapshotTotal(snapshot);
    const segmentsRaw: ContextSegment[] = estimateSegments(snapshot);
    // 会话级用量累计：账本按会话聚合——查失败降级 null（活算契约「失败路径不抛错、各环节
    // 降级」同族：缓存行与累计卡隐藏，估算主体不受影响）
    let sessionTotals: SessionUsageTotals | null = null;
    const convId: string = this.refs.conversationId();
    if (convId !== '') {
      try {
        sessionTotals = await sessionUsageTotals(convId);
      } catch (e) {
        sessionTotals = null;
      }
    }
    // 缩放同步（可加总红线）：usedTokens 与各段同乘 k；命名段和 ≤ 总量，差额入 otherTokens
    const usedTokens: number = Math.round(rawEstimate * factor);
    const scaled: ContextSegment[] = segmentsRaw.map((s: ContextSegment): ContextSegment => {
      const scaledSeg: ContextSegment = { key: s.key, label: s.label,
        tokens: Math.round(s.tokens * factor) };
      return scaledSeg;
    });
    let namedSum: number = 0;
    for (const s of scaled) {
      namedSum += s.tokens;
    }
    const otherTokens: number = usedTokens - namedSum > 0 ? usedTokens - namedSum : 0;
    // 全段直取上屏（决明拍板：小值段合并整体退役——全豁免免看不出合并了什么；防回流由
    // sse-assert 守）
    const segments: ContextSegment[] = scaled;
    const usage: ContextUsage = {
      hasData: rawEstimate > 0,
      usedTokens: usedTokens,
      rawEstimate: rawEstimate,
      windowTokens: windowTokens,
      factor: factor,
      anchored: anchored,
      segments: segments,
      otherTokens: otherTokens,
      attachPending: footprint.pending,
      lastUsage: this.lastRoundUsage(),
      sessionTotals: sessionTotals,
      injectSections: this.roundStatic !== null && this.roundStatic.injectSections !== undefined ?
        this.roundStatic.injectSections : null,
      degradedKeys: this.roundStatic !== null && this.roundStatic.degradedKeys !== undefined ?
        this.roundStatic.degradedKeys : [],
      overBudgetAfter: this.roundStatic !== null && this.roundStatic.overBudgetAfter === true
    };
    return usage;
  }
}
