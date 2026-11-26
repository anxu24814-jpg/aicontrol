// 轮次请求组装域（2026-10-06 域级最小拆分自 ChatSendCtrl，方法体整段原样搬迁、语义零变化）。
// 域定义一句话：**一次轮次请求的组装链**——上下文截尾 → 提示词注入 → 技能清单 → 记忆块 →
// 知识块与深度组 → 思考档位与采样 → 工具声明 → 上下文估算定格，产出 RoundRequest（终态
// 历史 + 思考档位 + 采样 + 工具声明）。
// · 为何不能并入既有同域件（反碎片下限①②申报）：既有 chat/ 域件各管一段——ChatSnapshotCtrl
//   = 注入材料的读取与组装（只读快照）/ ChatContextUsageCalc = 估算与工具声明判据链 /
//   ChatKeyRoundCtrl = 起流与 Key 池轮次——都不含本段「按序组装编排」；且本段是两消费方
//   （send 链 dispatchSend 与重试链 launchRetryRound）共用的同一组装体，是「禁第二条请求链」
//   红线的锚点。本件是**实质编排非转接壳**，宿主面只留三件依赖注入（thinking 读数闭包 +
//   promptState / ctxCalc 两引用）。
// · 依赖方向（零环红线，坑50；assert-app-domain 86 组 SCC 钉）：本件禁 import ChatSendCtrl 的
//   任何符号（含 ChatSendRefs 类型）——宿主以构造实参注入依赖；RoundRequest 为本件导出
//   类型，宿主反向 import（类型边方向 = ChatSendCtrl → 本件，chat 域既有环不增员）。

import { AiChatMessage, AiConnection, AiToolDef, AssistantAdvancedParams, SamplingParams }
  from '../../common/providers/AiTypes';
// 轮次参数解析域（档位归一 / 采样组装 / 上限联动）
import { RoundParams, resolveRoundParams } from '../../common/providers/RoundParams';
import { isTimeReminderEnabled, timeReminderMinutes } from '../../common/AppPreferences';
import { PromptInjectConfig, clipHistoryKeepingSummary, composeSendMessages,
  injectTimeReminders, KnowledgeInjectPlan, mergeConsecutiveSameRole,
  INJECT_ROLE_SYSTEM } from '../../common/providers/RequestInject';
// 注入 section 数据化域（四段产出/四路排序/落地 + 构成卡视图 sectionViewsOf）
import { InjectSection, SectionPromptLike, composeInjectSections, assembleSystemMessages,
  historyHasSystemMsg, promptAsSection, sectionViewsOf } from '../../common/chat/InjectSections';
// 注入上限登记处与预算安全网（登记清单 + applyInjectBudget 六级降级 + 小窗前置检查；kill-switch 默认关）
import { InjectBudgetResult, applyInjectBudget, smallWindowBlockReason }
  from '../../common/providers/InjectLimits';
// token 估算单源（P2 预算核算经 estimator 回调注入——禁第二套估算实现红线）
import { estimateTokens } from '../../common/TokenEstimate';
import { ChatPromptState } from '../../common/chat/ChatPromptState';
import { ChatContextUsageCalc, toolDefsJsonOf } from './ChatContextUsage';
import { SkillSendContext } from './ChatSnapshotCtrl';

// 组装域宿主读数集（箭头闭包持宿主延迟求值，组装时刻恒取当时值——思考档位属页面 @State，
// 两链均在页面挂载后执行）
export interface RoundAssemblyRefs {
  thinking: () => string;
}
// 轮次请求组装产物（两消费方 = send 链 dispatchSend + 重试链 launchRetryRound——禁第二条
// 请求链的锚点）：截尾后注入链终态历史 + 思考档位 + 采样 + 工具声明
export interface RoundRequest {
  history: AiChatMessage[];
  thinking: string;
  sampling: SamplingParams | null;
  tools: AiToolDef[];
  // 小窗前置检查拦截文案（非空 = 开流前由 ChatSendCtrl 拦下并 failRound 出错误卡，不发起
  // 请求；undefined/'' = 正常开流。kill-switch 默认关 = 恒空）
  blockReason?: string;
}

// 本轮 user 是否带服务端解析件（S2① 官方档提示参的发送组装侧扫描——纯函数域内小函数）：
// 从历史末条 user 的 images 扫 remoteFileId（DeepSeek 文档服务端解析件——S4 落上传链前恒
// undefined = 判 false，互斥回退因子不触发；S4 落地后自然生效）。user 前无图片或历史无
// user 行 = false；判「末条」止于首个 user（更早轮的附件不随本轮——附件仅随当前轮）
function lastUserHasServerDoc(history: AiChatMessage[]): boolean {
  for (let i = history.length - 1; i >= 0; i--) {
    const m: AiChatMessage = history[i];
    if (m.role !== 'user') {
      continue;
    }
    if (m.images === undefined) {
      return false;
    }
    for (const img of m.images) {
      if (img.remoteFileId !== undefined && img.remoteFileId !== '') {
        return true;
      }
    }
    return false;
  }
  return false;
}

export class ChatRoundAssembly {
  private refs: RoundAssemblyRefs;
  private promptState: ChatPromptState;
  private ctxCalc: ChatContextUsageCalc;

  constructor(refs: RoundAssemblyRefs, promptState: ChatPromptState,
    ctxCalc: ChatContextUsageCalc) {
    this.refs = refs;
    this.promptState = promptState;
    this.ctxCalc = ctxCalc;
  }

  // 轮次请求组装（两消费方 = dispatchSend + launchRetryRound〔重试组装段，ChatRetryHost
  // 回接〕——禁第二条请求链的锚点）：上下文截尾 → 提示词注入（变量替换随每次组装取当下
  // 时刻）→ 技能清单/记忆块/知识块（★ 序 = 技能 → 记忆 → 知识〔波动尾段排最尾〕）→
  // 深度组逐条注入 → 思考档位门控 → 采样五字段 → 工具声明全链（联网三级过滤 + 模式驱动
  // 两件 + 跨会话隐私闸）。
  // history 入口 = 落屏历史 + 本条 userReq（发送）或纯落屏流（重试——目标行 text 已清空，
  // 空内容跳过自然截断到该轮 user）；knowledge = 知识注入计划（空 plan = 全链零回归）。
  // windowTokens = 模型窗口 token（0 = 未入册端点，预算走 B 口径 16000 兜底、小窗检查不判）
  assembleRound(conn: AiConnection, history: AiChatMessage[], memoryBlock: string,
    skillCtx: SkillSendContext, knowledge: KnowledgeInjectPlan,
    windowTokens: number = 0): RoundRequest {
    // 上下文消息数截取：助手参数 contextCount > 0 时发送序列保尾部 N 条（★ 计数含本条
    // user）；截取在注入之前——system 头注与深度注入基于截后序列计算，身份注入永不丢
    //（首条历史被截 = 「只发最近 N 条」预期语义）
    const advanced: AssistantAdvancedParams | null = this.promptState.advancedParams();
    const clipLimit: number =
      advanced !== null && advanced.contextCount !== undefined ? advanced.contextCount : 0;
    const clipped: AiChatMessage[] = clipHistoryKeepingSummary(history, clipLimit);
    // 提示词注入：promptState 非空 → 按配置组装（身份/位置/深度，协议交替守卫在组装层）；
    // null = 原样默认不变。解析优先级 = 会话提示词 > 助手提示词 > 系统提示词
    //（ChatPromptState——归属恒在，注入开关只换注入源）；applyVariables 发送前做
    // {{date}}/{{char}} 等变量替换（每次发送取当下时刻，任意注入源统一生效——应用层替换，
    // 无需工具调用）。applied 单独持变量——注入内容同时是上下文估算的「提示词」段输入
    const applied: PromptInjectConfig | null =
      this.promptState.applyVariables(this.promptState.config(), conn.model);
    // ★ system 注入链 section 数据化：提示词〔system 位〕+ 技能清单 + 记忆块 + 知识命中块
    // 四段先产 section 数组（顺序由 sortInjectSections 四路排序给出，不再靠调用序），再由
    // assembleSystemMessages 一次落地；等价性（四协议请求体逐字节不变）由 sse-assert golden
    // 组并行互比守，含「无提示词 + 知识块独占 system」分支（首插不设 systemTailChars 红线
    // 形态）。提示词分流（promptAsSection 单源判据）：system 位且可注入 → 走 section（跳过
    // composeSendMessages——避免二次注入）；user/assistant 位与不可注入态 → 照旧老路
    //（消息级注入，composeSendMessages 的异常防御与 merge 守卫零漂移）。SectionPromptLike
    // 显式构造 = ArkTS 结构化禁令适配（PromptInjectConfig 字段集更宽，直传即编译错）
    const hasSys: boolean = historyHasSystemMsg(clipped);
    const promptLike: SectionPromptLike | null = applied !== null ?
      { role: applied.role, content: applied.content,
        volatileTime: applied.volatileTime } : null;
    // promptAsSection 分支跳过 composeSendMessages 时仍须过协议交替守卫
    //（mergeConsecutiveSameRole）——否则失败轮后直发（历史 user→user）不合并，
    // Anthropic / Gemini 对连续同角色可能 400；本支路为等价补位（正常交替序列逐字节
    // 无变化，golden 四场景不受影响）
    const finalHistory: AiChatMessage[] = promptAsSection(promptLike, hasSys) ?
      mergeConsecutiveSameRole(clipped) : composeSendMessages(clipped, applied);
    // 时间间隔提醒：★ 在 composeSendMessages 之后、system 块落地之前（顺序红线见
    // RequestInject 头注释）；开关阈值每轮现读
    const reminded: AiChatMessage[] = injectTimeReminders(finalHistory, isTimeReminderEnabled(), timeReminderMinutes());
    // 四段产出（空段不产——负向钉与老链逐字同口径）；sections 同时是预算核算与构成卡的
    // 数据源（「面板与实发一致」纪律：都吃这一份）
    const sections: InjectSection[] = composeInjectSections({
      prompt: promptLike, historyHasSystem: hasSys,
      skills: skillCtx.manifest, memory: memoryBlock,
      knowledge: knowledge.systemBlock
    });
    // 固定段总预算安全网（kill-switch 默认关 = 原引用直回零行为）：超阈逐级降级（知识留
    // 标题 → 记忆 30→10 → 技能只留名字；工具 desc 降档与 MCP 移除由既有 applyToolDefsBudget
    // 闸承接；内置与提示词永不动；到顶 fail-open）；降级后段重新落地，预算与落地吃同一份
    // sections（「面板与实发一致」纪律）
    const budget: InjectBudgetResult = applyInjectBudget(sections, windowTokens, estimateTokens);
    const knowledgeHistory: AiChatMessage[] =
      assembleSystemMessages(reminded, budget.sections);
    // 知识深度组注入：非 system 身份命中条目逐条走 composeSendMessages 单配置路径（与提示词
    // 模板注入同一条代码路——user 拼接式不新增 user 消息、assistant 独立插入，连续应用
    // targetUserIndex 定位稳定；system 身份已归系统块见 ChatSnapshotCtrl 分流注）。应用次序
    // = 深度降序、同深度按命中序（拍板，depthInjects 已在快照域排好序）
    let depthHistory: AiChatMessage[] = knowledgeHistory;
    for (const inject of knowledge.depthInjects) {
      depthHistory = composeSendMessages(depthHistory, inject);
    }
    const finalSentHistory: AiChatMessage[] = depthHistory;
    // 思考档位 + 采样五字段 + 上限联动：整域在 common/providers/RoundParams，本处只留取值
    const rp: RoundParams = resolveRoundParams(conn, this.refs.thinking(), advanced);
    const thinking: string = rp.thinking;
    const sampling: SamplingParams | null = rp.sampling;

    // 工具声明：单源 = ChatContextUsageCalc.collectTools（发送组装与面板活算同一链，两处
    // 漂移即「面板与实发不一致」；三级过滤 + 模式驱动两件 + 跨会话隐私闸的完整判据链见
    // calc 注释）。空清单 = []（请求体不带 tools 字段零回归）。★ S2① 官方档提示参：
    // 本轮 conn 透传；本轮 user 服务端解析件扫描（末条 user 的 images 扫 remoteFileId——
    // S4 落上传链前恒 false，字段落地后自然生效；helper 见下方 lastUserHasServerDoc）
    const roundTools: AiToolDef[] = this.ctxCalc.collectTools({
      manifest: skillCtx.manifest,
      useSkillNames: skillCtx.hasEnabled ? skillCtx.skillNames : []
    }, conn, lastUserHasServerDoc(history));
    // 上下文估算定格：注入侧快照 + 截尾后最终序列（截尾后的才是真发送序列——k 校准分母侧
    // 与本轮实发同链同源）。★ 分母侧注入段口径 = **只计不落进历史行的部分**（两段去重）：
    // 估算历史 = finalSentHistory，深度组注入与 user/assistant 提示词定投已落消息行（消息段
    // 已计）——知识段只取系统块（再取全量即双算；全量文本是面板活算口径，其历史为注入前
    // 序列无此类重复）；提示词段仅 system 身份注入计（它落 system 行、历史分桶丢 system 行）。
    // ★ 面板与实发一致：三段快照取**降级后**的 budget.sections（超预算降级时面板构成与实发
    // 同源；prompt 段永不降级，systemText 维持原估算口径不动）；构成卡数据同吃
    // budget.sections，禁第二条计算链
    const budgetSecOf = (key: string): string => {
      for (const sec of budget.sections) {
        if (sec.key === key) {
          return sec.content;
        }
      }
      return '';
    };
    this.ctxCalc.beginRound({
      systemText: applied !== null && applied.role === INJECT_ROLE_SYSTEM ?
        applied.content : '',
      skillManifest: budgetSecOf('skills'),
      memoryBlock: budgetSecOf('memory'),
      knowledgeBlock: budgetSecOf('knowledge'),
      toolDefsJson: toolDefsJsonOf(roundTools),
      // 请求构成卡数据（同一份快照定格——面板经 ContextUsage.injectSections 读回，禁第二条
      // 计算链；token 估算同 estimator 单源）；预算可见位 = 消费降级段标记与到顶说明
      //（与实发同一份降级结果，kill-switch 关 = 显示面零变化）
      injectSections: sectionViewsOf(budget.sections, estimateTokens),
      degradedKeys: budget.degradedKeys,
      overBudgetAfter: budget.overBudgetAfter,
      maxOutput: advanced !== null && advanced.maxOutput !== undefined ? advanced.maxOutput : 0
    }, finalSentHistory);
    // 小窗前置检查（开流前可读错误而非服务商 400）：固定段 = system 位提示词 + 内置工具
    //（不含 MCP——可降级层）；窗口 0 / 开关关 = 恒空不拦（B 口径拍板）。拦截出口 = 调用方
    // 判 blockReason → failRound 错误卡，不发起请求
    const builtinTools: AiToolDef[] = roundTools.filter((t: AiToolDef): boolean =>
      !t.name.startsWith('mcp__'));
    const blockReason: string = smallWindowBlockReason(
      applied !== null && applied.role === INJECT_ROLE_SYSTEM ? applied.content : '',
      toolDefsJsonOf(builtinTools), windowTokens, estimateTokens);
    return { history: finalSentHistory, thinking: thinking, sampling: sampling,
      tools: roundTools, blockReason: blockReason };
  }

}
