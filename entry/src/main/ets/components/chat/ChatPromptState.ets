// 会话提示词解析域（2026-08-31 思考档位接线时自 ChatSendCtrl.ets 域级拆出——该文件加
// 思考链必超 400 红线，提示词预载域整体迁此，方法体原样搬迁行为不变；2026-09-01 助手域
// 扩容：助手优先级链 + 变量替换落点迁入）。
// ★ 2026-09-04 归属与注入解耦（决明拍板：会话恒归属一个助手，提示词注入 = 独立开关——
// 开 = 模板覆盖不改归属、关 = 注入归属助手提示词；两卡可并存）：
// 归属（恒显式，★晚再修订 = 决明「跟随当前语义不明」定稿）：行 assistantId 显式绑定 ??
// 行 ''（存量未绑定，统一 = 内置默认助手，回退 2026-09-01 口径）?? 无行 = effectiveAssistantId()
// （面板覆盖 ?? 当前助手 AppStorage 持久键 ?? 内置默认助手——新会话落行实体值同源）；
// 注入优先级（load 预载——页面 aboutToAppear 打开会话时调一次 + 面板选择后刷新）：
// ①注入源 = 提示词覆盖（面板内存值恒优先）?? 行 promptId（'' = 未启用）——模板命中 →
//   模板注入（归属不变；引用跟随，查不到 = 已删 → 回退归属助手）；
// ②未启用注入 / 模板已删 → 归属助手提示词（注入配置恒默认 system/head/0——与系统提示词
//   同形制；★内置默认助手经 AssistantDb.syncDefaultPrompt 读时联结——prompt 恒 = 系统
//   提示词当前值，系统提示词页改动下次 load 即反映，零缓存）；
// ③助手行已删或提示词空 → 系统提示词行（回退注入基座恒在）。
// assistantName（{{char}} 替换值）/ advanced / tools 恒取归属助手（模板注入只换提示词
// 内容与注入配置，不换归属——2026-09-01 后旧互斥语义「选模板清助手参数」已撤）。
// 内容空/查询失败 = null 不注入不阻断。config() 供发送组装时读取。
// ★ 控制台助手注入封锁（2026-09-05 决明拍板）：归属 = 内置控制台助手时提示词注入功能
// 不开放——会话提示词引用/面板覆盖不消费（存量引用保留不删，切回其他助手即恢复引用
// 跟随），恒注入其内置只读路由提示词（prompt 经 queryAssistant 读时联结 =
// CONSOLE_ASSISTANT_PROMPT 常量，用户不可改）；UI 侧同口径 = ChatPromptSheet 注入卡
// 点击 toast 拒绝（openPick 单咽喉点），两侧防旁路。
// ★ load 并发守卫（2026-09-04 决明拍板修观察项）：load 双时点（页面 aboutToAppear 打开 +
// 面板选择后刷新）可能交叠——旧 load 晚于新 load 完成会把 resolved 与 applyOwner 写入的
// 助手名/参数/工具覆盖回旧值（面板显示已切新、注入缓存仍旧）。loadSeq 序号令牌：load 发起
// 时自增，全部写状态点仅当 seq === loadSeq 才落笔（过期 load 短路作废）——最后一次发起的
// load 恒胜出，显示与注入一致性由结构保证而非时序侥幸。
// ★ 无行会话（懒创建新会话/隐私会话）：行不存在 → 归属走有效绑定（覆盖 ?? 当前）；
// 面板选提示词落不了库——promptOverride 内存持有（首发落行时随 insertMessage 持久化
// conversations.promptId 列，此后行查询接手）；面板选助手 boundOverride 同口径。
// ★ 变量替换（2026-09-01）：applyVariables 在发送组装时对已解析内容做 {{date}} 等占位符
// 替换（每次发送取当下时刻；PromptVariables 零 import 纯函数，能力归属调研定论见该文件
// 头注释）；{{char}} = 助手名（非助手注入时保留原样）、{{language}} = 系统语言（i18n）。
// ★ 高级设定参数（2026-09-01）：advanced = 助手采样/上下文参数（与注入同链解析缓存，
// advancedParams() 供 ChatSendCtrl 消费；模板/系统提示词回退链恒 null——无助手级参数）。
// ★ 工具轮上限（2026-09-09）：toolLimit = 助手工具调用轮数上限的**生效值**（assistants
// toolStepLimit 列同链解析，0 = 不限制经 ToolLimits.resolveToolStepLimit 换算为硬顶 256；
// 无助手/查询失败 = 默认 32），toolStepLimit() 供 ChatSendCtrl 传给工具轮域。
// ★ 搜索结果条数（2026-09-10 搜索条数助手级可调）：searchCount = 助手级搜索返回条数
//（assistants.searchResultCount 列同链解析，1~25 经 SearchLimits.resolveSearchResultCount
// 换算；无助手/查询失败 = 默认 5 = 旧全局常量同值），searchResultCount() 供 ChatSendCtrl
// 写进发送链中转键（值到达搜索执行器的通道，见 SearchLimits 头注释）。
// ★ 归属 id 回读（2026-09-10 联网搜索开关归位笔）：resolvedOwnerId() = 本次 load 解析出的
// 归属助手 id，供 chip 写回 assistants.tools 用——写回目标必须与本次解析同源，**禁改用
// effectiveAssistantId()**（那只覆盖「无行新会话」，会把开关写到错误助手上）。
// ★ 2026-09-10 会话级覆盖层笔第二阶段：该写回链整体撤回（chip 改会话级覆盖，助手配置不再
// 被会话内操作改动），ownerId 成员与 resolvedOwnerId() 访问器一并删除——**这是有意的退役**，
// 不是漏改；若将来又要按归属写库，回到上一条口径重新论证，勿用 effectiveAssistantId() 顶替
import { i18n } from '@kit.LocalizationKit';
import { PromptInjectConfig } from '../../common/providers/RequestInject';
import {
  AssistantAdvancedParams, parseAssistantAdvancedParams
} from '../../common/providers/AiTypes';
import { parseEnabledToolIds } from '../../common/providers/ToolTypes';
import { parseEnabledSkillIds } from '../../common/SkillText';
import { TOOL_STEP_LIMIT_DEFAULT, resolveToolStepLimit } from '../../common/providers/ToolLimits';
import {
  SEARCH_RESULT_COUNT_DEFAULT, resolveSearchResultCount
} from '../../common/search/SearchLimits';
import { substitutePromptVariables } from '../../common/providers/PromptVariables';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_CONSOLE_ID, ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  queryConversationAssistantId
} from '../../common/store/AssistantDb';
import { MEMORY_SCOPE_GLOBAL } from '../../common/store/MemoryDb';
import {
  PromptTemplateRow, queryConversationPromptId, queryGlobalTemplate, queryTemplate
} from '../../common/store/PromptTemplateDb';

// 助手注入固定配置（system/head/0——助手提示词与系统提示词同形制：系统位注入）
const ASSISTANT_INJECT: PromptInjectConfig = {
  content: '', role: 'system', position: 'head', depth: 0
};

export class ChatPromptState {
  // 注入解析结果（内容 + 注入身份/位置/深度）：null = 不注入（内容空/查询失败——不阻断）
  private resolved: PromptInjectConfig | null = null;
  // {{char}} 替换值：当前会话归属助手的名称（归属恒在；助手已删/查询失败 = ''，
  // {{char}} 保留原样）
  private assistantName: string = '';
  // 助手高级设定参数（2026-09-01 高级设定）：与注入同链解析缓存（load 预载 + 面板选择后
  // 刷新，语义同 prompt 引用跟随）；null = 未配置（发送不带任何采样字段）；
  // contextCount 截取与采样透传在 ChatSendCtrl.dispatchSend 消费
  private advanced: AssistantAdvancedParams | null = null;
  // 助手启用工具 id 清单（2026-09-02 工具调用底层，assistants.tools 列同链解析缓存）：
  // 助手分支 = 行列解析；模板/系统提示词回退链 = 默认集合（无助手级配置）。发送组装时
  // enabledToolIds() 供 ChatSendCtrl 查声明、页面 refreshWebSearchFlag 判「能不能联网」
  // 的能力上限（★ 2026-09-10 会话级覆盖层笔第二阶段：chip 已不再写回本清单，只读）
  private tools: string[] = parseEnabledToolIds('');
  // 助手工具调用轮数上限（2026-09-09 上限可设置，assistants.toolStepLimit 列同链解析
  // 缓存）：恒为「生效上限」——0（不限制）已由 resolveToolStepLimit 换算为内置硬顶 256；
  // 无助手/查询失败 = 默认 32（旧全局常量同值）。发送组装时 toolStepLimit() 供 ChatSendCtrl
  // 传给工具轮域（resetForNewSend 第二参）
  private toolLimit: number = TOOL_STEP_LIMIT_DEFAULT;
  // 助手搜索结果条数（2026-09-10 搜索条数助手级可调，assistants.searchResultCount 列同链
  // 解析缓存）：恒为「生效条数」（1~25 区间内的整数）；无助手/查询失败 = 默认 5（旧全局
  // 常量同值）。发送组装时 searchResultCount() 供 ChatSendCtrl 写进发送链中转键
  private searchCount: number = SEARCH_RESULT_COUNT_DEFAULT;
  // 助手记忆注入开关（2026-09-08 记忆域，assistants.memoryInject 列同链解析缓存）：
  // true 默认 = 会话发送时注入记忆块；发送组装时 memoryInjectEnabled() 供 ChatSendCtrl
  // 判定（总开关/隐私会话守卫在 ChatSendCtrl.buildMemoryBlock 一并判）
  private memoryInject: boolean = true;
  // 归属助手 id 与记忆作用域（v35，2026-09-20 助手级记忆，同链解析缓存）：ownerId =
  // 本次 load 解析的归属助手 id（scope='assistant' 时记忆库归属与工具执行者中转的取值源）；
  // memoryScope = assistants.memoryScope 列（'global' 默认 = 全局库 = 存量路径原样 /
  // 'assistant' = 该助手自己的库——注入/工具检索跟随）。★ 与 2026-09-10 退役的
  // resolvedOwnerId 的区别与重新论证：那次是 chip 写回 assistants.tools（会话内操作改
  // 助手配置 = 越权，故撤）；本次只读不写库，消费 = 发送链中转键（执行者身份随轮次
  // 下发给无上下文的记忆工具执行器）与注入选库——纯「读时快照」无写回面
  private ownerId: string = '';
  private memoryScopeValue: string = MEMORY_SCOPE_GLOBAL;
  // 助手启用技能 id 清单（2026-09-13 技能层，assistants.skills 列同链解析缓存）：
  // ★ 默认**空数组** = 不启用任何技能（与 tools 的「默认集合」语义刻意相反，见 SkillText
  // 头注释）；无助手/查询失败同为空数组（零启用零注入零声明的防御态）。发送组装时
  // enabledSkillIds() 供 ChatSendCtrl 与库内现存技能求交（清单与 use_skill 声明同闸）
  private skillIds: string[] = [];
  // 控制台助手技能封锁（2026-09-13 技能层笔 1 起）：归属 = 控制台时 true → enabledSkillIds
  // 最外层恒 []（链路级封锁——UI 侧技能卡入口另有 toast 拒绝，双层防旁路；与上方控制台
  // 提示词注入封锁同族）。归属判定只能在 applyOwner 里做（那里才知道归属），**三段都落值**
  //（null 查询失败 = 非控制台置 false，勿让上一次会话的 true 残留成「恒封」）
  private skillBlocked: boolean = false;
  // 会话级面板覆盖绑定（2026-09-01 会话绑定）：面板选助手后 = 覆盖值（恒非空——关闭非
  // 默认卡回退默认 id；'' 仅初始未选，★2026-09-04 晚「跟随当前」语义撤销后不落 ''）；
  // 仅无行场景消费（有效归属兜底），与提示词覆盖并存独立（不再被选词清零）
  private boundOverride: string = '';
  // 会话级面板提示词引用覆盖（2026-09-04 隐私会话开放提示词选择）：无行会话（隐私会话
  // 恒无行、新会话首发前）选提示词无可落库之行——覆盖值纯内存持有，load() 解析时优先于
  // conversations.promptId 行查询（有行会话面板落库与覆盖同值，解析结果一致零回归）；
  // '' = 未覆盖（行走既有行查询链）
  private promptOverride: string = '';
  // load 并发守卫序号（2026-09-04 观察项修复）：每次 load 发起自增；各写状态点仅当
  // seq === loadSeq 才写缓存——双时点 load 交叠时旧 load 作废，防旧结果覆盖新结果
  private loadSeq: number = 0;

  // 返回 Promise 供调用方链后置动作（2026-09-03 联网开关：页面 load 完成后写「联网可用」
  // 广播键——load 解析异步，完成时机只有本链知道）
  load(conversationId: string): Promise<void> {
    const seq: number = ++this.loadSeq;
    return queryConversationAssistantId(conversationId)
      .then((rowId: string | null): Promise<PromptInjectConfig | null> => {
        if (seq !== this.loadSeq) {
          return Promise.resolve(null); // 已被新一次 load 取代——过期作废短路
        }
        // 归属（恒显式，2026-09-04 定稿）：行显式绑定优先；行 ''（存量未绑定）= 内置默认
        // 助手（兜底）；无行（新会话） = 有效归属 = 面板覆盖 ?? 当前助手 ?? 默认——「跟随
        // 当前」浮动态已撤销，'' 不再产生
        const ownerId: string = rowId !== null && rowId !== '' ? rowId :
          (rowId === null ? this.effectiveAssistantId() : ASSISTANT_DEFAULT_ID);
        return this.resolveInject(conversationId, ownerId, rowId === null, seq);
      })
      .then((config: PromptInjectConfig | null): void => {
        if (seq !== this.loadSeq) {
          return; // 过期 load 不写缓存（终态由最新 load 决定）
        }
        if (config === null || config.content === '') {
          this.resolved = null;
          return;
        }
        this.resolved = config;
      })
      .catch((): void => {
        if (seq !== this.loadSeq) {
          return; // 过期 load 失败不缓存——不得清掉新 load 的结果
        }
        this.resolved = null; // 读取失败 = 不注入不阻断（不静默：编辑链失败另有 toast）
      });
  }

  // 注入解析（2026-09-04 归属与注入解耦）：注入源 = 提示词覆盖（面板内存值恒优先）??
  // 行 promptId（'' = 未启用）——模板命中 = 模板注入（归属不变）；模板已删 = 回退归属；
  // 未启用注入 → 归属助手提示词（system/head/0）；助手行已删或提示词空 → 系统提示词行。
  // assistantName/advanced/tools 恒取归属助手（模板注入只换提示词，不换归属）。
  // ★ 控制台助手封锁（2026-09-05）：归属 = 控制台助手时注入源强制走归属回退——模板/
  // 引用一概不消费（判定在 queryAssistant 返回后，覆盖与行查询两条源一并封死）。
  // seq = load 并发守卫序号——applyOwner 两处写状态点前守卫，过期 load 不落笔不续查
  private resolveInject(conversationId: string, ownerId: string,
    noRow: boolean, seq: number): Promise<PromptInjectConfig | null> {
    return queryAssistant(ownerId)
      .then((owner: AssistantRow | null): Promise<PromptInjectConfig | null> => {
        if (seq !== this.loadSeq) {
          return Promise.resolve(null); // 过期 load：助手参数不落笔，短路作废
        }
        this.applyOwner(owner, ownerId);
        // 控制台助手注入封锁（2026-09-05 决明拍板，头注释同款）：恒走归属回退 = 内置
        // 只读路由提示词（system/head/0）——覆盖与行引用不消费，模板已删回退同形制
        if (ownerId === ASSISTANT_CONSOLE_ID) {
          return this.resolveOwnerFallback(owner);
        }
        const sourceBound: Promise<string> = this.promptOverride !== '' ?
          Promise.resolve(this.promptOverride) :
          (noRow ? Promise.resolve('') : queryConversationPromptId(conversationId));
        return sourceBound
          .then((promptId: string): Promise<PromptInjectConfig | null> => {
            if (promptId === '') {
              return this.resolveOwnerFallback(owner);
            }
            return queryTemplate(promptId)
              .then((tpl: PromptTemplateRow | null): Promise<PromptInjectConfig | null> => {
                if (tpl === null) {
                  return this.resolveOwnerFallback(owner); // 模板已删 → 回退归属助手
                }
                return Promise.resolve({ content: tpl.content, role: tpl.injectRole,
                  position: tpl.injectPosition, depth: tpl.injectDepth } as PromptInjectConfig);
              });
          });
      })
      .catch((): Promise<PromptInjectConfig | null> => {
        if (seq !== this.loadSeq) {
          return Promise.resolve(null); // 过期 load 失败：不落笔不兜底续查
        }
        this.applyOwner(null, ownerId);
        return this.resolveOwnerFallback(null); // 归属查询失败 → 系统提示词兜底
      });
  }

  // 归属回退（未启用注入 / 模板已删 / 归属查询失败）：助手行在且提示词非空 → 助手注入
  //（system/head/0——与系统提示词同形制）；否则 → 系统提示词行（手动助手空提示词亦回退，
  // 归属恒有注入基座；内置默认助手恒在兜底）
  private resolveOwnerFallback(owner: AssistantRow | null): Promise<PromptInjectConfig | null> {
    if (owner !== null && owner.prompt !== '') {
      return Promise.resolve({ content: owner.prompt, role: ASSISTANT_INJECT.role,
        position: ASSISTANT_INJECT.position, depth: ASSISTANT_INJECT.depth } as PromptInjectConfig);
    }
    return queryGlobalTemplate()
      .then((row: PromptTemplateRow): PromptInjectConfig | null => {
        if (row === null) {
          return null;
        }
        return { content: row.content, role: row.injectRole, position: row.injectPosition,
          depth: row.injectDepth };
      });
  }

  // 归属助手参数应用（恒取归属——模板注入/回退同源；null = 助手已删/查询失败 → 清空/默认）。
  // ownerId = load 解析出的归属 id（applyOwner 需在 owner null 分支也归零记忆作用域缓存，
  // 故随参传入——两处调用同值同源）
  private applyOwner(owner: AssistantRow | null, ownerId: string): void {
    if (owner === null) {
      this.assistantName = '';
      this.advanced = null;
      this.tools = parseEnabledToolIds('');
      this.skillIds = parseEnabledSkillIds('');
      // 查询失败防御态 = 非控制台（2026-09-16：勿让上一次会话的封锁标记残留成「恒封」）
      this.skillBlocked = false;
      this.memoryInject = true; // 查询失败防御态 = 默认开（与列默认一致）
      this.toolLimit = TOOL_STEP_LIMIT_DEFAULT;
      this.searchCount = SEARCH_RESULT_COUNT_DEFAULT; // 查询失败防御态 = 默认 5（与列默认一致）
      // 查询失败防御态 = 无归属行 + 全局库（助手行不在 = 助手库不可达，全局兜底）
      this.ownerId = '';
      this.memoryScopeValue = MEMORY_SCOPE_GLOBAL;
      return;
    }
    this.assistantName = owner.name;
    this.advanced = parseAssistantAdvancedParams(owner.advancedParams);
    this.tools = parseEnabledToolIds(owner.tools);
    this.skillIds = parseEnabledSkillIds(owner.skills);
    // 控制台助手技能封锁（2026-09-13 技能层笔 1，方案 §2.8 #4「一期不开放」——与上方
    // resolveInject 的控制台提示词封锁同族逻辑，落点同源）：页面入口已对控制台隐藏，本处
    // 兜住导入旧备份/手改 DB 等绕过 UI 的路径，让「一期不开放」是链路级事实而非仅界面事实
    if (owner.id === ASSISTANT_CONSOLE_ID) {
      this.skillIds = [];
      this.skillBlocked = true;
    } else {
      this.skillBlocked = false;
    }
    this.memoryInject = owner.memoryInject;
    // 存储值 → 生效上限（0 = 不限制 → 内置硬顶 256；换算单一来源 ToolLimits）
    this.toolLimit = resolveToolStepLimit(owner.toolStepLimit);
    // 存储值 → 生效条数（脏数据回默认 5、超界收口 1~25；换算单一来源 SearchLimits）
    this.searchCount = resolveSearchResultCount(owner.searchResultCount);
    // 归属 id 与记忆作用域（v35；脏值兜底 'global' 与 AssistantDb 读取同口径）
    this.ownerId = owner.id;
    this.memoryScopeValue = owner.memoryScope !== '' ? owner.memoryScope : MEMORY_SCOPE_GLOBAL;
  }

  config(): PromptInjectConfig | null {
    return this.resolved;
  }

  // 助手启用工具 id 清单（发送组装时读取；默认集合语义见 parseEnabledToolIds）
  enabledToolIds(): string[] {
    return this.tools;
  }

  // 助手记忆注入开关（发送组装时读取——ChatSendCtrl.buildMemoryBlock 前置条件之一）
  memoryInjectEnabled(): boolean {
    return this.memoryInject;
  }

  // 归属助手记忆作用域（v35，2026-09-20 助手级记忆；发送组装时读取——ChatSendCtrl.
  // buildMemoryBlock 注入选库与工具作用域中转键共用本值；'global' = 全局库 = 存量路径）
  memoryScope(): string {
    return this.memoryScopeValue;
  }

  // 归属助手 id（v35；scope='assistant' 时的记忆库归属与工具执行者中转取值源；查询失败
  // 防御态 = ''——调用方按全局库兜底）
  ownerAssistantId(): string {
    return this.ownerId;
  }

  // 本会话生效技能 id 清单（2026-09-16 会话级技能启用随「单条消息指定技能」笔退役，
  // 三段回两段）：①控制台助手 → [] 恒零（链路级封锁——UI 侧技能卡入口另有 toast 拒绝，
  // 双层防旁路）；②其余 → 助手启用集。下游 buildSkillContext 与 use_skill 声明链零改动
  //（它们只吃本函数）
  enabledSkillIds(): string[] {
    if (this.skillBlocked) {
      return [];
    }
    return this.skillIds;
  }

  // 控制台技能封锁读取口（2026-09-16：卡入口 UI 闸与发送链压掉的共同判据）
  skillsBlocked(): boolean {
    return this.skillBlocked;
  }

  // 助手工具调用轮数上限（发送组装时读取；恒为生效上限，0 已换算为硬顶 256）
  toolStepLimit(): number {
    return this.toolLimit;
  }

  // 助手搜索结果条数（发送组装时读取；恒为生效条数 = 1~25 整数，脏数据已回默认 5）
  searchResultCount(): number {
    return this.searchCount;
  }

  // 助手高级设定参数（发送组装时读取；null = 未配置不发送）
  advancedParams(): AssistantAdvancedParams | null {
    return this.advanced;
  }

  // 面板助手选择覆盖上行（ChatPage.onPromptChanged 经 ChatSendCtrl 透传；值 = 面板选择
  // 归属 id，恒非空——关闭非默认卡上行默认 id；'' 仅初始未选防御——2026-09-04 恒显式
  // 归属定稿后与提示词覆盖互不清空）
  setBoundOverride(assistantId: string): void {
    this.boundOverride = assistantId;
  }

  // 面板提示词引用覆盖上行（2026-09-04；与 boundOverride 并存独立——解析侧注入源 =
  // 覆盖 ?? 行 promptId，归属恒走 effectiveAssistantId，两非空并存态行为正确）
  setPromptOverride(promptId: string): void {
    this.promptOverride = promptId;
  }

  // 当前提示词引用覆盖（ChatPromptSheet 主面板提示词卡显示态；无行会话 = 面板落选真源）
  promptOverrideId(): string {
    return this.promptOverride;
  }

  // 有效归属（无行新会话一致性兜底 + 面板显示共用；★2026-09-04 恒显式归属定稿——行 '' 已
  // 不走本函数〔load/显示侧行 '' = 内置默认助手〕，本函数仅无行场景：面板覆盖优先，否则
  // 当前助手（AppStorage 持久键，缺省 = 内置默认助手——恒非 ''））
  effectiveAssistantId(): string {
    if (this.boundOverride !== '') {
      return this.boundOverride;
    }
    return AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  }

  // 变量替换（发送组装时调——每次发送取当下时刻；配置其余字段原样，仅替换 content）：
  // modelName = 当前连接模型 id（{{model_name}}）；language = 系统语言（{{language}}）
  applyVariables(config: PromptInjectConfig | null, modelName: string): PromptInjectConfig | null {
    if (config === null) {
      return null;
    }
    return {
      content: substitutePromptVariables(config.content, modelName, this.systemLanguage(),
        this.assistantName, new Date()),
      role: config.role, position: config.position, depth: config.depth
    };
  }

  // 系统语言（{{language}} 替换值；i18n.System.getSystemLanguage 返回 BCP 47 tag 如
  // zh-Hans-CN——@ohos.i18n.d.ts 实锤；失败兜底空串 = 保留 {{language}} 原样）
  private systemLanguage(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch (e) {
      return '';
    }
  }
}
