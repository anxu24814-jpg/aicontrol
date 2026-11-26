// 注入面上限登记处（注入链治理 P1-a）：本工程「system 注入 + 工具面 + 历史面」全部长度
// 上限的**单一户籍册**——新增任何注入面上限，先在本文件登记一行再落码（防未来变胖的
// 编译期清单制）。
// ★ 零 import 叶子（模块环零风险；下游 providers/ 与组件层均可引）。
// ★ 形态定案（施工拍板，与总案改动点 3 的出入）：总案原想「常量本体搬入本件 + 旧位置
//   re-export 转出」——实测八个原位件全部有断言复制直跑 / 桩面，旧位置一旦 import 本件
//   即破「断言复制直跑即自足」纪律。保守定案 = **登记制**：常量本体单源留在原位件不动，
//   本件以注释清单登记（值 + 出处 + 判定落点），不导出第二份同名常量（两份可漂移的代码
//   值比一份注释更坏）；导出区只承载**新增**上限与本笔 P2 预算常量（无原位单源，真权威
//   定义）。若决明改拍全量搬家：先解决直跑件「前置拼接 InjectLimits 源 + 剥 import 行」
//   的断言适配（先例 = assert-skill-domain 的 MemoryManageText 拼接段）。
// ★ 收口边界：「工具结果」面只收 ToolClip 的 8192 通用截断线；各家专属工具回执上限
//   **本期不入册、留在原位**——McpText.MCP_TOOL_RESULT_MAX_CHARS(32000)、KnowledgeText.
//   KNOWLEDGE_TOOL_RESULT_MAX_*（5 条/12000 字）、ToolChatSearch.CHAT_TOOL_RESULT_MAX_*
//   （10 条/2000 字）、MemoryText.MEMORY_TOOL_RESULT_MAX_*（8 条/1500 字）；
//   KNOWLEDGE_CONTENT_MAX(6000) 同批不入册；AttachmentUtil.TEXT_ATTACH_MAX_CHARS 为附件面
//   非注入面，不在册。

// ═══ 一、既有上限登记表（单源在原位件；改值只改原位，本表随同笔更新）═══
// ── 面：系统提示词 ──
// TEMPLATE_CONTENT_MAX = 2000 字 · 原位 common/store/PromptTemplateDb.ets · 判定落点 =
//   模板编辑页保存校验（超限拒存）。
// ── 面：技能清单（system 注入）──
// SKILL_MANIFEST_MAX_CHARS = 2000 字 · 原位 common/SkillText.ets · 落点 = composeSkillManifest
//   清单总长贪心装入（头行 + 逐行「- 名称：描述」，满 10 条刚好 ≤ 2000 属设计值）。
// SKILL_MANIFEST_DESC_MAX = 120 字 · 原位 common/SkillText.ets · 落点 = 清单单行描述截断。
// ── 面：技能正文（use_skill 回执通道，不进 system）──
// SKILL_CONTENT_MAX = 8000 字 · 原位 common/SkillText.ets · 落点 = 技能编辑页校验 +
//   composeSkillReply 回执截断（SKILL_REPLY_MAX_CHARS 8192 同族在其侧，不另立行）。
// SKILL_ENABLED_MAX = 10 个 · 原位 common/SkillText.ets · 落点 = 启用集上限（清单满配
//   条数口径）。
// ── 面：记忆注入（system 注入）──
// MEMORY_INJECT_MAX_COUNT = 30 条 / MEMORY_INJECT_MAX_CHARS = 2000 字 · 原位
//   common/MemoryText.ets · 落点 = composeMemoryBlock 双封顶（发送链 / ProactiveGen /
//   沉淀链四路同源）。
// ── 面：知识注入（system 波动尾段 + 深度组）──
// KNOWLEDGE_INJECT_MAX_COUNT = 8 条 / KNOWLEDGE_INJECT_MAX_CHARS = 2000 字 · 原位
//   common/KnowledgeMatch.ets · 落点 = composeKnowledgeSystemBlock 与
//   selectKnowledgeDepthHits 两通道共用（系统块含头句与「- 标题」行；深度组只按 content）。
// ── 面：工具定义 ──
// TOOL_DEFS_BUDGET_CHARS = 32000 字 / TOOL_DEFS_DESC_TRIM = 120 字 · 原位
//   common/providers/ToolLimits.ets · 落点 = applyToolDefsBudget（collectTools 末尾单源
//   收口；P2 总预算只并入核算、不动本常量——总案不做清单）。
// TOOL_STEP_LIMIT_MAX = 32 / TOOL_STEP_HARD_CAP = 256 / TOOL_ARGS_MAX_CHARS = 100000 /
//   TOOL_ARGS_ROUND_MAX_CHARS = 400000 / TOOL_CALLS_PER_ROUND_MAX = 8 · 原位 ToolLimits ·
//   落点 = 工具轮数与单轮参数闸（ChatToolRoundCtrl 调用集合入口；行为限制随登记）。
// ── 面：工具结果（通用截断线）──
// 8192 字 · 原位 common/providers/ToolClip.ets（clipToolResult 形参默认值 +
//   TOOL_RESULT_SPILL_THRESHOLD 同值双写——零 import 直跑纪律禁 import 本件；超线走落盘
//   信封不再永弃）· 落点 = 非 MCP 工具回执截断 / 溢出落盘分流阈（TOOL_RESULT_SPILL_PREVIEW
//   档 1024 见其侧注释）。
// ── 面：历史 ──
// REQUEST_HISTORY_MAX_ROWS = 1024 条 / REQUEST_HISTORY_WINDOW_RATIO = 窗口 × 0.7 ·
//   原位 common/chat/RequestHistoryBudget.ets · 落点 = resolveRowBudget 双闸（0.85 裁剪
//   水位与闸系数同件在册，实测档，无新证据不改——总案不做清单）。
// ── 面：压缩（旁路）──
// COMPRESS_KEEP_ROUNDS = 2 轮 / COMPRESS_MIN_COMPRESSIBLE = 6 条 / COMPRESS_INPUT_RATIO_MAX
//   = 0.8 窗 / COMPRESS_MAX_OUTPUT = 20000 字 · 原位 common/CompressGen.ets · 落点 =
//   压缩就绪判定与提示词组装（手动压缩链，不经 composeSendMessages 主链）。

// ═══ 二、注入总预算安全网（P2；阈值拍板 = 总案 B 口径）═══
// 性质 = **安全网**（防无界增长与小窗爆窗），不是压缩器：常规配置（预置模型 ≥128K 窗口）
// 永不触发——固定段上限被既有常量硬封顶 ≈16000 token（system 四段各 2000 字 + 工具定义
// 32000 字符），128K 窗口的阈值 32000 恒大于它。
// kill-switch（默认 false，真机验过再开；关 = 本节全部逻辑零行为变化）：
export const INJECT_TOTAL_BUDGET_ENABLED: boolean = false;
// 固定段阈值（token）= window > 0 ? min(window × 下比例, 上封顶) : 未知兜底。
// 窗口未知（=0，未入册端点）兜底 16000——唯一会真正无界的一类（resolveTokenBudget(0)=0
// 历史侧整段不裁），B 口径只封固定段（历史侧残余风险见变更记录技术债登记）。
export const INJECT_BUDGET_WINDOW_RATIO: number = 0.25;
export const INJECT_BUDGET_CAP_TOKENS: number = 40000;
export const INJECT_BUDGET_UNKNOWN_WINDOW_TOKENS: number = 16000;
// 小窗前置检查比例：window > 0 且固定段（提示词 + 内置工具）> window × 0.6 → 开流前给
// 可读错误（failRound 错误卡）；窗口 0 不判（无窗口无从谈比例，硬判误伤未填窗口用户）。
export const INJECT_SMALL_WINDOW_RATIO: number = 0.6;

// ═══ 三、P2 实现体（零 import 纯函数，assert-inject-budget 复制直跑面；token 估算经
//     estimator 回调注入——TokenEstimate 单源红线不破，调用方传 estimateTokens）═══

// 预算段（与 common/chat/InjectSections.InjectSection 字段集全镜像——arkts-no-structural-
// typing 要求完全同构方可直传；本件零 import 不能引彼件，镜像声明同 SectionMsg 判例）
export interface InjectBudgetSection {
  key: string;
  label: string;
  target: string;
  cacheHint: string;
  content: string;
  volatileTime?: boolean;
}

// 预算产物：sections = 降级后的段清单（不超预算 = 输入数组原引用直回，常见路径零分配）；
// degradedKeys = 已执行降级的段 key 有序表（面板尾注与断言消费）；overBudgetAfter =
// 六级到顶仍超 = fail-open 照发（可见性：面板构成卡尾注）
export interface InjectBudgetResult {
  sections: InjectBudgetSection[];
  degradedKeys: string[];
  overBudgetAfter: boolean;
}

// 固定段阈值（token，B 口径）：window > 0 走比例取小、封顶 40000；window = 0（未入册
// 端点）兜底 16000——预置模型 ≥128K 恒不触发（安全网存在感接近零）
export function injectFixedBudgetTokens(windowTokens: number): number {
  if (windowTokens <= 0) {
    return INJECT_BUDGET_UNKNOWN_WINDOW_TOKENS;
  }
  const byRatio: number = Math.round(windowTokens * INJECT_BUDGET_WINDOW_RATIO);
  return byRatio < INJECT_BUDGET_CAP_TOKENS ? byRatio : INJECT_BUDGET_CAP_TOKENS;
}

// 段总量（token）：system 段逐段 estimator 求和（分隔符与帧开销量级可忽略——与估算域
// 口径一致；estimator = 调用方注入的 TokenEstimate.estimateTokens）
function sectionsTokensOf(sections: InjectBudgetSection[],
  estimator: (text: string) => number): number {
  let total: number = 0;
  for (const s of sections) {
    if (s.target === 'system') {
      total += estimator(s.content);
    }
  }
  return total;
}

// L1 知识留标题：头句与各条「- 标题」行保留、条目正文省略（真实形态 = 知识块
// composeKnowledgeSystemBlock 的「头句 + 『- 标题』行 + 其后正文行」两行结构，正文可含
// 换行；「（另有 N 条相关知识未展开）」尾注行保留）。确定性纯函数——同输入同输出，
// 缓存前缀不抖〔R9〕
// ★ 按「标题行 + 其后正文行」折叠而非按「：」切（真实两行格式标题行可无「：」，按冒号
//   切会让 L1 空转且 degradedKeys 谎报）。按行前缀反解析属已知脆弱面（正文行若以「- 」
//   开头会被当标题）——根治需结构化入参，记技术债（变更记录 2026-10-26 一千九百一十九节）
function degradeKnowledgeTitles(content: string): string {
  const lines: string[] = content.split('\n');
  const out: string[] = [];
  let inBody: boolean = false;
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];
    if (line.startsWith('- ')) {
      out.push(line);
      out.push('（正文已省略）');
      inBody = true;
    } else if (!inBody) {
      out.push(line);
    } else if (i === lines.length - 1 && line.startsWith('（另有 ')) {
      // 未展开尾注行（composeKnowledgeSystemBlock 末尾）——保留计数，不随正文折叠
      out.push(line);
    }
  }
  return out.join('\n');
}

// L2 记忆 30→10：头行保留，条目行（'- ' 开头）保前 10 条 + 尾注（形态假设 =
// composeMemoryBlock 的「头句 + 逐条『- 内容』」结构）
function degradeMemoryToTen(content: string): string {
  const lines: string[] = content.split('\n');
  const out: string[] = [];
  let kept: number = 0;
  let omitted: number = 0;
  for (const line of lines) {
    if (line.startsWith('- ') && kept >= 10) {
      omitted++;
      continue;
    }
    if (line.startsWith('- ')) {
      kept++;
    }
    out.push(line);
  }
  return omitted > 0 ? out.join('\n') + '\n（另有 ' + omitted + ' 条记忆已省略）' : out.join('\n');
}

// L3 技能只留名字：'- 名称：描述' 行截到首个 '：'（形态假设 = composeSkillManifest 的
// 「头行 + 逐行『- 名称：触发描述』」结构；名字在 use_skill schema enum 仍全量可见）
function degradeSkillsNamesOnly(content: string): string {
  const lines: string[] = content.split('\n');
  const out: string[] = [];
  for (const line of lines) {
    if (line.startsWith('- ')) {
      const sep: number = line.indexOf('：');
      out.push(sep > 0 ? line.substring(0, sep) : line);
    } else {
      out.push(line);
    }
  }
  return out.join('\n');
}

// 六级降级（先转指针再丢）：L1 知识留标题 → L2 记忆 30→10 → L3 技能只留名字 → L4 工具
// desc 降档 → L5 MCP 整件移除 → L6 内置与提示词**永不动**，到顶仍超 fail-open 照发。
// ★ L4/L5 由既有 applyToolDefsBudget 闸承接（ToolLimits 32000 预算独立运作，P2 只并入
//   核算不并常量），本函数不联动工具集（联动 = 发送与面板活算两处 collectTools 需同传
//   动态预算，制造「面板与实发」漂移面；保守第一版施工定案）。kill-switch 关 = 输入数组
//   原引用直回零行为。windowTokens 语义：>0 = 模型窗口；0 = 未入册端点（兜底 16000）。
export function applyInjectBudget(sections: InjectBudgetSection[], windowTokens: number,
  estimator: (text: string) => number): InjectBudgetResult {
  if (!INJECT_TOTAL_BUDGET_ENABLED) {
    return { sections: sections, degradedKeys: [], overBudgetAfter: false };
  }
  const budget: number = injectFixedBudgetTokens(windowTokens);
  let current: InjectBudgetSection[] = sections.slice();
  let used: number = sectionsTokensOf(current, estimator);
  if (used <= budget) {
    return { sections: sections, degradedKeys: [], overBudgetAfter: false };
  }
  const degradedKeys: string[] = [];
  // 单级降级：段不在场（未产或空）= 该级空转——不谎报 key、不算量；段在场但 fn 产出
  // 逐字相同（无可降内容）= 同样不记 key——「已执行降级」的语义必须是内容真的缩了，
  // 否则面板尾注会把未降段谎报成降级段
  const degrade = (key: string, fn: (content: string) => string): boolean => {
    let hit: boolean = false;
    for (let i = 0; i < current.length; i++) {
      if (current[i].key === key && current[i].content !== '') {
        const nextContent: string = fn(current[i].content);
        if (nextContent !== current[i].content) {
          const next: InjectBudgetSection = {
            key: current[i].key, label: current[i].label, target: current[i].target,
            cacheHint: current[i].cacheHint, content: nextContent,
            volatileTime: current[i].volatileTime };
          current[i] = next;
          hit = true;
        }
      }
    }
    if (!hit) {
      return false;
    }
    degradedKeys.push(key);
    used = sectionsTokensOf(current, estimator);
    return true;
  };
  degrade('knowledge', degradeKnowledgeTitles);
  if (used > budget) {
    degrade('memory', degradeMemoryToTen);
  }
  if (used > budget) {
    degrade('skills', degradeSkillsNamesOnly);
  }
  // L4/L5 工具侧由既有闸承接（见函数头注释）；L6 内置与提示词永不动
  return { sections: current, degradedKeys: degradedKeys, overBudgetAfter: used > budget };
}

// 小窗前置检查（开流前给可读错误而非服务商 400）：window > 0 且固定段（提示词 + 内置
// 工具——**不含 MCP**，MCP 属可降级层）> window × 0.6 → 返回错误文案；否则 ''（不拦）。
// 窗口 0 不判（B 口径拍板）；kill-switch 关 = 恒 ''。systemText = system 位提示词文本，
// builtinToolsJson = 内置工具定义拼串（toolDefsJsonOf 口径，仅非 MCP 件）
export function smallWindowBlockReason(systemText: string, builtinToolsJson: string,
  windowTokens: number, estimator: (text: string) => number): string {
  if (!INJECT_TOTAL_BUDGET_ENABLED || windowTokens <= 0) {
    return '';
  }
  const fixed: number = estimator(systemText) + estimator(builtinToolsJson);
  if (fixed <= windowTokens * INJECT_SMALL_WINDOW_RATIO) {
    return '';
  }
  return '模型窗口约 ' + windowTokens + '，提示词与内置工具已超出可承受范围。' +
    '请换用窗口更大的模型，或减少启用的工具。';
}
