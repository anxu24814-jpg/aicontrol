// 会话上下文用量域（2026-09-17 方案-会话上下文用量 执行笔 2）——ChatSendCtrl 贴 1200 硬线，
// 本笔功能域按宪法「域级最小拆分」独立成件（照 ChatToolRoundCtrl 先例：宿主闭包 refs +
// 宿主接口，方法体自 ChatSendCtrl 搬迁或新建，语义单源）。本文件承载：
// · 工具声明链 collectTools——自 assembleRound 原链整体搬迁（判据逐句等价），发送组装与
//   面板活算**同一链**（两处各算 = 漂移面会让「面板与实发不一致」）；
// · 锚点与校准态——pendingEstimate（发送时估算，k 分母侧）/ lastStreamPrompt（最后一流
//   真实输入，锚点）/ anchorFingerprint（连接指纹，切连接即失效）；
// · 活算 computeLive——面板打开/轮完成/切模型三处调用（方案 §3.6），产出圆环与面板共读的
//   ContextUsage（估算 × k、分段缩放同步、小值段合并、会话级缓存命中账本聚合〔2026-09-18
//   增量笔，调研-上下文统计口径 §五.2 项 2〕；★ 2026-09-23 活算纳入待发附件笔——「本轮输入」
//   段扩为 草稿 + 待发附件协议文本侧内容 + 视觉通道张数×900，附件足迹取数单源在
//   AttachmentUtil.pendingAttachFootprint，与发送链载荷组装同一实现）。
// ★ 锚点五条红线（方案 §3.2，防后人改回）：
//   ①锚点只进 k 的计算，绝不直接当「已用」显示（Cline #7383：直接显示上一轮已完成请求的
//     token 数，UI 50% 实发 100%+）——本域显示值恒 = 当前序列估算 × k；
//   ②只认 input 侧 promptTokens，不认 totalTokens（Cherry 源码注释直呼 total 是
//     "bogus anchor"）——取值点在宿主 onStreamDone；
//   ③流内多帧去重前提由 ChatStreamBase.absorbUsage 的 mergeUsage take-max 承担（sse-assert
//     56 组既有钉，Cline #10306 累加 1500 万的反面）；
//   ④k 分子分母同口径：估算序列必须全量文本（含 reasoning 回传与图片折算）——TokenEstimate
//     120 组③段逐形态钉；
//   ⑤异常值挡在 k 之外：calibrateFactor 钳制 [0.2, 5]、哨兵/NaN/≤0 回 1（LibreChat #14661）。
// ★ 两口径并存纪律（方案附录 A.5，Open WebUI #29064「有意求和」先例）：整轮累积器
//   轮级用量四值（计费口径，跨流求和；见 ChatUsageRoundCtrl 域头注释）与锚点 lastStreamPrompt（上下文规模口径，最后
//   一流胜出）语义不同**都不许「统一」**——工具轮 N 流后前者约为真实规模的 N 倍，拿它当
//   上下文规模必放大显示（Claude Code #84738 advisor 轮求和 ≈ 2× 提前压缩的同款）。
import { PendingAttachFootprint, pendingAttachFootprint } from '../../common/AttachmentUtil';
import { AiChatMessage, AiConnection, AiToolDef, AssistantAdvancedParams,
  PendingAttachment } from '../../common/providers/AiTypes';
import { TOOL_SEARCH_MEMORY, TOOL_USE_SKILL, ToolEntry,
  isModeDriven, isWebDomainTool, registerBuiltinTools, toolRegistry } from '../../common/providers/ToolTypes';
import { isCrossSessionTool } from '../../common/providers/ToolChatSearch';
import { composeUseSkillSchema } from '../../common/SkillText';
import { isMemoryToolReadMode } from '../../common/MemoryGen';
import { contextWindowForConnection } from '../../common/store/ProviderDb';
import { SessionUsageTotals, sessionUsageTotals } from '../../common/store/UsageStatsDb';
import { currentCtxFactor, saveCtxFactor } from '../../common/AppPreferences';
import { calibrateFactor, estimateSegments, estimateSnapshotTotal, mergeSmallSegments,
  ContextSegment, SendSnapshot, SendSnapshotItem } from '../../common/TokenEstimate';
import { ChatMessage } from './ChatMessageCompose';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { clipHistoryKeepingSummary } from '../../common/providers/RequestInject';

// 技能上下文的收窄视图（本文件不 import ChatSendCtrl 防环；ArkTS 禁同构双接口互传，故由
// 宿主侧显式构造本接口实例）：manifest = 清单文本（'' = 不注入）、useSkillNames = 本轮
// 启用技能名（[] = 不声明 use_skill）——两值同源于宿主 buildSkillContext 的一次计算
export interface ContextSkillSnapshot {
  manifest: string;
  useSkillNames: string[];
}

// 本轮注入侧快照（发送组装完成后定格，轮内不变）：systemText = 三级解析 + 变量替换后的
// 注入内容；toolDefsJson = 工具声明拼串（toolDefsJsonOf）；maxOutput = 预留输出（0 = 不列段）
export interface RoundStaticSnapshot {
  systemText: string;
  skillManifest: string;
  memoryBlock: string;
  toolDefsJson: string;
  maxOutput: number;
}

// 上轮实际（面板「上轮实际」卡数据源 = 末条带用量的 assistant 行——让「预估」与「实测」
// 对照可见，方案 §4.4-3；privacy 会话不挂 usage meta，恒 null = 卡不显示）
export interface LastRoundUsage {
  promptTokens: number;
  cachedTokens: number;
  completionTokens: number;
  durationMs: number;
}

// 活算产物（圆环与面板共读）。★ 可加总结构（方案 §3.4 红线）：usedTokens 与 segments 同乘
// k（k=1 时逐值不变）——「分段之和 ≤ 总量、差额 = otherTokens」，用户把各行相加能对上总数
//（Claude Code #18241 同屏矛盾的反面）；windowTokens 0 = 未知（只显已用数，不显占比与分
// 段条——已拍板 P4）；hasData false = 全空（显「暂无可统计的用量」，禁渲染 0%——0 与未知
// 必须区分，Cherry #19965 / Cline #9433）
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
  // 会话级用量累计（2026-09-18 增量笔立、同日「本会话累计」卡笔扩三值，账本
  // token_usage_events 按 conversationId 聚合——调研-上下文统计口径 §五.2 可借鉴项 2 落地）：
  // null = 无对话轮记录（隐私会话旁路落库/全零），显示面整卡隐藏；cachedTokens 0 = 有轮但
  // 零命中，显示面该行隐藏（「缓存行 >0 才显」同款零噪声口径——无缓存协议的常驻 0% 是噪声
  // 非信息）。★ 计费口径（含工具轮每轮重发），与 usedTokens 的窗口规模口径不同基——两者
  // 禁互相换算或并列同基数展示（观察项与实证见 MEMORY_DETAIL「上下文用量面板·缓存行口径」）
  sessionTotals: SessionUsageTotals | null;
}

// 宿主闭包（ChatSendCtrl 构造注入——dshinhm ChatCtrlAssembly refs 同款姿势，箭头持宿主
// this 延迟求值）；与 ChatToolRoundHost 同为「子域文件不反向 import 宿主」的环规避形制
export interface ChatContextUsageRefs {
  conn: () => AiConnection | null;
  privateMode: () => boolean;
  webDomainAllowed: () => boolean;
  memoryParticipates: () => boolean;
  buildMemoryBlock: () => Promise<string>;
  buildSkillSnapshot: () => Promise<ContextSkillSnapshot>;
  promptSystemText: (model: string) => string;
  advancedParams: () => AssistantAdvancedParams | null;
  enabledToolIds: () => string[];
  allMessages: () => ChatMessage[];
  // 会话 id（'' = 无——2026-09-18 增量笔增：会话级缓存命中的账本聚合键；与 ChatSendCtrl
  // 落库点同一取值口）
  conversationId: () => string;
  roundConn: () => AiConnection | null;
  roundHistory: () => AiChatMessage[];
}

// 占比（0~100；窗口未知或无数据回 -1 = 「仅底环」口径）——圆环与面板共用单源（两处各写
// 一遍即漂移面）；钳 100 防 used 略超窗口的显示越界
export function contextPct(usage: ContextUsage): number {
  if (!usage.hasData || usage.windowTokens <= 0) {
    return -1;
  }
  return Math.min(100, Math.round(usage.usedTokens * 100 / usage.windowTokens));
}

// 连接指纹（方案 §3.5：providerId+model+endpoint+protocol——四元任一变即锚点失效转估算；
// 「切服务商同模型名」也失效 = 保守口径，中转与官方分词可能不同）
export function contextFingerprint(conn: AiConnection): string {
  return conn.providerId + '|' + conn.model + '|' + conn.endpoint + '|' + conn.protocol;
}

// 工具声明拼串（估算口径：name + description + parametersJson 逐条拼接；[] = '' 不列段）
export function toolDefsJsonOf(tools: AiToolDef[]): string {
  return tools.map((t: AiToolDef): string => t.name + ' ' + t.description + ' ' + t.parametersJson)
    .join('\n');
}

// 协议历史 → 快照条目（纯映射）：system 行丢弃（内容已由提示词/技能/记忆三段单列覆盖，计
// 入即双重计数——TokenEstimate 分段注释同源）；assistant 的 reasoning 与 user 的 images
// 随行映射（遍历完整性五种消息形态的入口）
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
      imageCount: m.role === 'user' && m.images !== undefined ? m.images.length : 0
    };
    items.push(item);
  }
  return items;
}

export class ChatContextUsageCalc {
  private refs: ChatContextUsageRefs;
  // 发送时估算（k 分母侧）：每次起流前 refreshEstimate 对齐「本流实际请求」——工具轮续轮
  // 历史已长、key 失败重发同序，恒与锚点同轮同源
  private pendingEstimate: number = 0;
  // 锚点（-1 = 无）：最后一条成功流的 promptTokens——「当前上下文规模」的真度量；工具轮
  // 多次 onStreamDone 后者覆盖前者 = 最后一次流胜出（结构性保证，非时序侥幸）
  private lastStreamPrompt: number = -1;
  // 锚点连接指纹（'' = 无）：与 lastStreamPrompt 成对写入成对失效
  private anchorFingerprint: string = '';
  // 本轮注入侧快照（beginRound 定格；finishStream 后残留无害——活算不读它）
  private roundStatic: RoundStaticSnapshot | null = null;

  constructor(refs: ChatContextUsageRefs) {
    this.refs = refs;
  }

  // 发送组装完成（宿主 assembleRound 末尾）：定格注入侧快照 + 首次估算（sentHistory = 截尾
  // 后的最终发送序列——与实发同链同源，方案 §六-2）
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

  // 锚点记录 + k 校准落键（宿主 onStreamDone usage!==null 分支——红线②只认 input 侧由调用
  // 方保证）：k = 锚点 ÷ 本流估算（钳制 [0.2,5]、异常回 1），按模型名前插落偏好键（上限 20）
  recordAnchor(promptTokens: number, conn: AiConnection): void {
    this.lastStreamPrompt = promptTokens;
    this.anchorFingerprint = contextFingerprint(conn);
    saveCtxFactor(conn.model, calibrateFactor(promptTokens, this.pendingEstimate));
  }

  // 发送时估算（k 分母侧）：pendingAttachText 恒 ''——sentHistory 里本轮 user 已含附件正文
  //（ChatSendCtrl.dispatchSend 的 protocolText），此处再计即双算（SendSnapshot 注释同源）
  private estimateOf(staticSnapshot: RoundStaticSnapshot, history: AiChatMessage[]): number {
    return estimateSnapshotTotal(this.snapshotOf(staticSnapshot, history, '', 0, ''));
  }

  private snapshotOf(staticSnapshot: RoundStaticSnapshot, history: AiChatMessage[],
    draftText: string, imageCount: number, pendingAttachText: string): SendSnapshot {
    const snapshot: SendSnapshot = {
      systemText: staticSnapshot.systemText,
      skillManifest: staticSnapshot.skillManifest,
      memoryBlock: staticSnapshot.memoryBlock,
      toolDefsJson: staticSnapshot.toolDefsJson,
      history: mapSnapshotItems(history),
      draftText: draftText,
      imageCount: imageCount,
      pendingAttachText: pendingAttachText,
      maxOutput: staticSnapshot.maxOutput
    };
    return snapshot;
  }

  // 待发附件足迹（面板活算侧，2026-09-23 活算纳入待发附件笔）：附件数组由页面经门面传入
  //（与草稿文本同源同时刻——都是「打开面板这一刻」的待发输入），取数实现单源在
  // AttachmentUtil.pendingAttachFootprint（发送链载荷组装同一实现，禁本件重写分流判据）。
  // ★ 文本侧含读盘（文本附件）——读失败不阻断面板：退化为「不计入 + pending 提示」，
  // 宁低勿假（静默吞错 = 面板显示假低值还告诉用户「准」，P0-1 的反面）
  private attachFootprint(atts: PendingAttachment[], hasVision: boolean): PendingAttachFootprint {
    try {
      return pendingAttachFootprint(atts, hasVision);
    } catch (e) {
      return { text: '', imageCount: 0, pending: true };
    }
  }

  // 工具声明链（2026-09-17 自 ChatSendCtrl.assembleRound 整体搬迁——判据逐句等价，断言
  // 121 组钉单源）：内置注册幂等 → 助手启用清单（联网域三级过滤收敛进 webDomainAllowed
  // 单判据）→ 模式驱动残留剔除 → 记忆按需读取追加 → 技能加载追加（与清单同闸同源）→
  // 跨会话检索隐私闸
  collectTools(skill: ContextSkillSnapshot): AiToolDef[] {
    registerBuiltinTools();
    let roundTools: AiToolDef[] = toolRegistry.defsFor(this.refs.enabledToolIds());
    if (!this.refs.webDomainAllowed()) {
      roundTools = roundTools.filter((t: AiToolDef): boolean => !isWebDomainTool(t.name));
    }
    roundTools = roundTools.filter((t: AiToolDef): boolean => !isModeDriven(t.name));
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
    if (this.refs.privateMode()) {
      // 跨会话读取域双件同闸（2026-09-19 深化笔：单件过滤扩为 isCrossSessionTool 单源判据
      // ——判据面在 ToolChatSearch，防「加新件忘旧件」反向漂移）
      roundTools = roundTools.filter((t: AiToolDef): boolean => !isCrossSessionTool(t.name));
    }
    return roundTools;
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

  // 活算（面板打开 / 轮完成 / 切模型，方案 §3.6——打字与生成中不刷）：异步三查与发送组装
  // 同源（记忆块 / 技能清单 / 窗口值——不新增采集链路）；同步面 = 截尾后历史（§六-2）按
  // role 分桶 + 工具声明同链。草稿文本 / 待发附件 / 主模型有无视觉由调用方带入（面板打开时
  // 取一次——与发送链同源判据，见 attachFootprint）。失败路径不抛错——各环节降级
  //（记忆 ''、技能空、窗口 0、k=1），显示面按未知口径呈现
  async computeLive(draftText: string, attachments: PendingAttachment[],
    hasVision: boolean): Promise<ContextUsage> {
    const conn: AiConnection | null = this.refs.conn();
    const footprint: PendingAttachFootprint = this.attachFootprint(attachments, hasVision);
    const memoryBlock: string = await this.refs.buildMemoryBlock();
    const skill: ContextSkillSnapshot = await this.refs.buildSkillSnapshot();
    const windowTokens: number = conn !== null ? await contextWindowForConnection(conn) : 0;
    const advanced: AssistantAdvancedParams | null = this.refs.advancedParams();
    const clipLimit: number =
      advanced !== null && advanced.contextCount !== undefined ? advanced.contextCount : 0;
    const history: AiChatMessage[] =
      clipHistoryKeepingSummary(buildRequestHistory(this.refs.allMessages()), clipLimit);
    const staticSnapshot: RoundStaticSnapshot = {
      systemText: this.refs.promptSystemText(conn !== null ? conn.model : ''),
      skillManifest: skill.manifest,
      memoryBlock: memoryBlock,
      toolDefsJson: toolDefsJsonOf(this.collectTools(skill)),
      maxOutput: advanced !== null && advanced.maxOutput !== undefined ? advanced.maxOutput : 0
    };
    // k 取该模型落键值（无记录 1.0 = 纯估算态）；锚点指纹比对决定 anchored（不换 k 值——
    // 锚点失效只影响面板说明行强调「估算」，§3.5 矩阵「k 跟模型指纹走」）
    const factor: number = conn !== null ? currentCtxFactor(conn.model) : 1;
    const anchored: boolean = conn !== null && this.lastStreamPrompt > 0 &&
      contextFingerprint(conn) === this.anchorFingerprint;
    const snapshot: SendSnapshot = this.snapshotOf(staticSnapshot, history, draftText,
      footprint.imageCount, footprint.text);
    const rawEstimate: number = estimateSnapshotTotal(snapshot);
    const segmentsRaw: ContextSegment[] = estimateSegments(snapshot);
    // 会话级用量累计（2026-09-18 增量笔）：账本按会话聚合——查失败降级 null（活算契约
    // 「失败路径不抛错、各环节降级」同族：缓存行与累计卡隐藏，估算主体不受影响）
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
    // 小值段合并只在「显分段条」的场景（窗口已知）做（P8；窗口未知面板不显分段条，原样返回）
    const segments: ContextSegment[] = windowTokens > 0 ? mergeSmallSegments(scaled, windowTokens) : scaled;
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
      sessionTotals: sessionTotals
    };
    return usage;
  }
}
