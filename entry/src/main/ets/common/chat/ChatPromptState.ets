// 会话提示词解析域（自 ChatSendCtrl.ets 域级拆出——提示词预载域 + 助手优先级链 + 变量
// 替换落点迁此）。
// ★ 归属与注入解耦（决明拍板）：会话恒归属一个助手，提示词注入 = 独立开关——开 = 模板
// 覆盖不改归属、关 = 注入归属助手提示词；两卡可并存。
// 归属（恒显式）：行 assistantId 显式绑定 ?? 行 ''（存量未绑定 = 内置默认助手）?? 无行 =
// effectiveAssistantId()（面板覆盖 ?? 当前助手持久键 ?? 内置默认）。
// 注入优先级（load 预载——页面 aboutToAppear 打开会话时调一次 + 面板选择后刷新）：
// ①注入源 = 提示词覆盖（面板内存值恒优先）?? 行 promptId（'' = 未启用）——模板命中 →
//   模板注入（归属不变；已删 → 回退归属助手）；
// ②未启用注入 / 模板已删 → 归属助手提示词（恒 system/head/0——内置默认助手经
//   AssistantDb.syncDefaultPrompt 读时联结，系统提示词页改动下次 load 即反映，零缓存）；
// ③助手行已删或提示词空 → 系统提示词行（注入基座恒在）。
// assistantName（{{char}}）/ advanced / tools 恒取归属助手（模板注入只换提示词内容与注入
// 配置，不换归属——旧互斥语义「选模板清助手参数」已撤）。内容空/查询失败 = null 不注入
// 不阻断。config() 供发送组装时读取。
// ★ 注入**生效来源**（模板命中/归属助手/系统提示词/未注入）随回退链落点记录，与 resolved
// 同拍落笔（load 终态 seq 守卫段），statusSource() 快照整包下发（会话状态半模态「请求注入」
// 卡消费，面板零复算）。
// ★ load 并发守卫：load 双时点可能交叠——loadSeq 序号令牌，全部写状态点仅当 seq === loadSeq
// 才落笔（过期 load 短路作废），最后一次发起的 load 恒胜出，一致性由结构保证而非时序侥幸。
// ★ 无行会话（懒创建/隐私会话）：行不存在 → 归属走有效绑定（覆盖 ?? 当前）；面板选提示词
// 落不了库——promptOverride/boundOverride 内存持有（首发落行时随 insertMessage 持久化，
// 此后行查询接手）。
// ★ 变量替换：applyVariables 在发送组装时做 {{date}}/{{char}}/{{language}} 等占位符替换
//（每次发送取当下时刻；{{char}} = 归属助手名，非助手注入时保留原样；PromptVariables
// 零 import 纯函数）。
// ★ 工具轮上限/搜索条数（已全局化）：toolStepLimit()/searchResultCount() = 全局偏好键现读
//（即读即回，设置改值对下一条消息即时生效，不随 load 缓存）。
// ★ 归属 id 写库退役口径：chip 写回 assistants.tools 链已撤（会话内操作改助手配置 = 越权），
// resolvedOwnerId() 一并删除——**有意退役非漏改**；将来要按归属写库须重新论证，勿用
// effectiveAssistantId() 顶替。
// 控制台助手注入封锁 / 记忆知识高级设定封锁 / strip 函数已随 2026-10-25 控制台合并笔整段删除。
import { i18n } from '@kit.LocalizationKit';
import { PromptInjectConfig } from '../providers/RequestInject';
import {
  AssistantAdvancedParams, parseAssistantAdvancedParams
} from '../providers/AiTypes';
import { parseEnabledToolIds } from '../providers/ToolTypes';
import { parseEnabledSkillIds } from '../SkillText';
import { parseEnabledMcpServerIds } from '../McpText';
import {
  PREF_SEARCH_RESULT_COUNT_KEY, PREF_TOOL_STEP_LIMIT_KEY
} from '../AppPreferences';
import { TOOL_STEP_LIMIT_DEFAULT, resolveToolStepLimit } from '../providers/ToolLimits';
import {
  SEARCH_RESULT_COUNT_DEFAULT, resolveSearchResultCount
} from '../search/SearchLimits';
import { substitutePromptVariables, hasVolatileTimeTokens } from '../providers/PromptVariables';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  queryConversationAssistantId
} from '../store/AssistantDb';
import { TOOL_MANAGE_BALANCE, TOOL_MANAGE_MODELS, TOOL_MANAGE_PROVIDERS,
  TOOL_TEST_PROVIDER } from '../providers/ToolIds';
import { MEMORY_SCOPE_GLOBAL } from '../store/MemoryDb';
import {
  PromptTemplateRow, queryConversationPromptId, queryGlobalTemplate, queryTemplate
} from '../store/PromptTemplateDb';

// 助手注入固定配置（system/head/0——助手提示词与系统提示词同形制：系统位注入）
const ASSISTANT_INJECT: PromptInjectConfig = {
  content: '', role: 'system', position: 'head', depth: 0
};

// 注入生效来源载体：load 内构造 → resolveInject / resolveOwnerFallback 两链按回退落点填充
//（template / assistant / system / none）→ **load 终态 seq 守卫段统一落笔**。写点不散在
// resolveInject 内部是刻意的：该链过首段 seq 检查后不再复检，过期 load 独立落笔来源会与
// resolved 的终态守卫错拍（面板显示来源与实际注入不一致）
interface InjectOrigin {
  kind: string;
  name: string;
}

// 会话状态快照（「会话状态」半模态「请求注入」卡的**数据单源**——解析缓存现读一次成组，
// 面板只吃本快照，禁逐项自算（防第二份判别漂移）；ChatSendCtrl 只留薄口 statusSource()）
export interface ChatStatusSource {
  promptSourceKind: string;   // 'template' | 'assistant' | 'system' | 'none'
  promptSourceName: string;   // 模板名 / 助手名（无名称来源 = ''）
  skillIds: string[];         // 本会话启用技能 id 清单（见 enabledSkillIds）
  memoryInjectEnabled: boolean;
  memoryScope: string;        // 'global' | 'assistant'
  knowledgeAutoInjectEnabled: boolean;
}

export class ChatPromptState {
  // 注入解析结果（内容 + 注入身份/位置/深度）：null = 不注入（内容空/查询失败——不阻断）
  private resolved: PromptInjectConfig | null = null;
  // {{char}} 替换值：当前会话归属助手的名称（归属恒在；助手已删/查询失败 = ''，
  // {{char}} 保留原样）
  private assistantName: string = '';
  // 助手高级设定参数：与注入同链解析缓存（语义同 prompt 引用跟随）；null = 未配置（发送
  // 不带采样字段）；contextCount 截取与采样透传在 ChatSendCtrl.dispatchSend 消费
  private advanced: AssistantAdvancedParams | null = null;
  // 助手启用工具 id 清单（assistants.tools 列同链解析缓存）：助手分支 = 行列解析；模板/
  // 系统提示词回退链 = 默认集合。enabledToolIds() 供 ChatSendCtrl 查声明、页面判「能不能
  // 联网」能力上限（chip 已不再写回本清单，只读）
  private tools: string[] = parseEnabledToolIds('');
  // 工具轮上限与搜索条数已改**全局偏好键现读**、无缓存成员（全局设置对所有助手生效，不再
  // 挂 applyOwner 助手解析链）
  // 助手记忆注入开关（assistants.memoryInject 列同链解析缓存）：true 默认 = 发送时注入记忆块
  //（总开关守卫在 ChatSnapshotCtrl.buildMemoryBlock 一并判）
  private memoryInject: boolean = true;
  // 归属助手知识自动注入开关（assistants.knowledgeAutoInject 列同链解析缓存）：false 默认 =
  // 关（与列 DEFAULT 0 一致）；knowledgeAutoInjectEnabled() 供 buildKnowledgeBlock 作最外层闸
  //（关 = 零 DB 查询零注入，请求与无此功能逐字节一致）
  private knowledgeAutoInject: boolean = false;
  // 提示词生效来源：kind = 'template' | 'assistant' | 'system' | 'none'，name = 模板名/助手名
  //（无名称来源 = ''）。与 resolved 同拍落笔（见 InjectOrigin 注释）；消费口 = statusSource()
  // 快照整包；字段名与快照字段 promptSourceKind 刻意区分（后者属 ChatStatusSource 接口）
  private promptSource: InjectOrigin = { kind: 'none', name: '' };
  // 归属助手 id 与记忆作用域（同链解析缓存）：ownerId = 本次 load 解析的归属助手 id
  //（scope='assistant' 时记忆库归属与工具执行者中转取值源）；memoryScope = assistants.
  // memoryScope 列（'global' 默认 = 全局库 / 'assistant' = 该助手自己的库——注入/工具检索
  // 跟随）。★ 只读不写库（与已退役的 chip 写回链不同——那次因越权撤回），纯「读时快照」
  private ownerId: string = '';
  private memoryScopeValue: string = MEMORY_SCOPE_GLOBAL;
  // 助手启用技能 id 清单（assistants.skills 列同链解析缓存）：★ 默认**空数组** = 不启用任何
  // 技能（与 tools 的「默认集合」语义刻意相反，见 SkillText 头注释）；无助手/查询失败同空
  // 数组（防御态）。enabledSkillIds() 供 ChatSendCtrl 与库内现存技能求交（清单与 use_skill
  // 声明同闸）
  private skillIds: string[] = [];
  // 助手绑定的 MCP 服务器 id 清单（assistants.mcpServers 列同链解析缓存）：'' 含坏 JSON =
  // 空集合（McpText 列语义单源）；★ 默认**空数组**（与 skills/knowledge 同族）。mcpServerIds()
  // 经 ChatSendCtrl refs 注入 collectTools 追加段（绑定消费单点）
  private mcpServerIdsValue: string[] = [];
  // 会话级面板覆盖绑定：面板选助手后 = 覆盖值（恒非空——关闭非默认卡回退默认 id；「跟随
  // 当前」浮动态已撤销）；仅无行场景消费（有效归属兜底），与提示词覆盖并存独立
  private boundOverride: string = '';
  // 会话级面板提示词引用覆盖：无行会话（隐私会话恒无行、新会话首发前）选提示词无可落库行
  //——覆盖值纯内存持有，load() 解析时优先于行查询（有行会话落库与覆盖同值，零回归）；
  // '' = 未覆盖（行走既有行查询链）
  private promptOverride: string = '';
  // load 并发守卫序号：每次 load 发起自增；各写状态点仅当 seq === loadSeq 才写缓存
  //（双时点 load 交叠时旧 load 作废，防旧结果覆盖新结果）
  private loadSeq: number = 0;

  // 返回 Promise 供调用方链后置动作（load 解析异步，完成时机只有本链知道）
  load(conversationId: string): Promise<void> {
    const seq: number = ++this.loadSeq;
    // 失败清理的同源归属：第一段解析出的 ownerId 带给链尾 catch 供全量清缓存（第一段本身
    // reject 时保持 ''）。名取 parsedOwnerId——resolvedOwnerId 是已退役访问器名，负向钉禁
    // 残留勿复用
    let parsedOwnerId: string = '';
    // 生效来源载体：本 load 局部构造逐链填充（见 InjectOrigin 注释），终态 seq 守卫段连同
    // resolved 一并落笔——过期 load 的来源不落
    const origin: InjectOrigin = { kind: 'none', name: '' };
    return queryConversationAssistantId(conversationId)
      .then((rowId: string | null): Promise<PromptInjectConfig | null> => {
        if (seq !== this.loadSeq) {
          return Promise.resolve(null); // 已被新一次 load 取代——过期作废短路
        }
        // 归属（恒显式）：行显式绑定优先；行 ''（存量未绑定）= 内置默认助手；无行（新会话）
        // = 有效归属 = 面板覆盖 ?? 当前助手 ?? 默认
        const ownerId: string = rowId !== null && rowId !== '' ? rowId :
          (rowId === null ? this.effectiveAssistantId() : ASSISTANT_DEFAULT_ID);
        parsedOwnerId = ownerId;
        return this.resolveInject(conversationId, ownerId, rowId === null, seq, origin);
      })
      .then((config: PromptInjectConfig | null): void => {
        if (seq !== this.loadSeq) {
          return; // 过期 load 不写缓存（终态由最新 load 决定）
        }
        // 生效来源与 resolved 同拍落笔（同守卫——来源与实际注入恒一致）；内容空 = 实际
        // 未注入，来源归 none（不显「有来源却没内容」的假象）
        const effective: PromptInjectConfig | null =
          config === null || config.content === '' ? null : config;
        this.promptSource = effective === null ? { kind: 'none', name: '' } : origin;
        this.resolved = effective;
      })
      .catch((): void => {
        if (seq !== this.loadSeq) {
          return; // 过期 load 失败不缓存——不得清掉新 load 的结果
        }
        // 失败全量清缓存（原只置 resolved = null 会让各缓存残留上一会话的值——失败路径的
        // 发送参数错会话；对齐 resolveInject catch 的 applyOwner(null) 口径归防御态）
        this.applyOwner(null, parsedOwnerId);
        this.resolved = null; // 读取失败 = 不注入不阻断（不静默：编辑链失败另有 toast）
        // 来源同拍归「未注入」——与 resolved 同拍，面板不显旧来源
        this.promptSource = { kind: 'none', name: '' };
      });
  }

  // 注入解析：注入源 = 提示词覆盖（面板内存值恒优先）?? 行 promptId——模板命中 = 模板注入
  //（归属不变）；模板已删 = 回退归属；未启用注入 → 归属助手提示词（system/head/0）；助手行
  // 已删或提示词空 → 系统提示词行。assistantName/advanced/tools 恒取归属助手（模板注入只换
  // 提示词，不换归属）。seq = 并发守卫序号（applyOwner 写状态点前守卫，过期不落笔不续查）
  private resolveInject(conversationId: string, ownerId: string,
    noRow: boolean, seq: number, origin: InjectOrigin): Promise<PromptInjectConfig | null> {
    return queryAssistant(ownerId)
      .then((owner: AssistantRow | null): Promise<PromptInjectConfig | null> => {
        if (seq !== this.loadSeq) {
          return Promise.resolve(null); // 过期 load：助手参数不落笔，短路作废
        }
        this.applyOwner(owner, ownerId);
        const sourceBound: Promise<string> = this.promptOverride !== '' ?
          Promise.resolve(this.promptOverride) :
          (noRow ? Promise.resolve('') : queryConversationPromptId(conversationId));
        return sourceBound
          .then((promptId: string): Promise<PromptInjectConfig | null> => {
            if (promptId === '') {
              return this.resolveOwnerFallback(owner, origin);
            }
            return queryTemplate(promptId)
              .then((tpl: PromptTemplateRow | null): Promise<PromptInjectConfig | null> => {
                if (tpl === null) {
                  return this.resolveOwnerFallback(owner, origin); // 模板已删 → 回退归属助手
                }
                // 模板命中：来源 = 会话提示词（名随行——面板文案「会话提示词：X」）
                origin.kind = 'template';
                origin.name = tpl.name;
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
        return this.resolveOwnerFallback(null, origin); // 归属查询失败 → 系统提示词兜底
      });
  }

  // 归属回退（未启用注入 / 模板已删 / 归属查询失败）：助手行在且提示词非空 → 助手注入
  //（system/head/0——与系统提示词同形制）；否则 → 系统提示词行（手动助手空提示词亦回退，
  // 归属恒有注入基座；内置默认助手恒在兜底）
  private resolveOwnerFallback(owner: AssistantRow | null,
    origin: InjectOrigin): Promise<PromptInjectConfig | null> {
    if (owner !== null && owner.prompt !== '') {
      // 来源 = 归属助手提示词（名随行——面板文案「助手提示词：X」）
      origin.kind = 'assistant';
      origin.name = owner.name;
      return Promise.resolve({ content: owner.prompt, role: ASSISTANT_INJECT.role,
        position: ASSISTANT_INJECT.position, depth: ASSISTANT_INJECT.depth } as PromptInjectConfig);
    }
    return queryGlobalTemplate()
      .then((row: PromptTemplateRow): PromptInjectConfig | null => {
        if (row === null) {
          origin.kind = 'none'; // 基座行都没有 = 实际无注入
          origin.name = '';
          return null;
        }
        origin.kind = 'system';
        origin.name = '';
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
      this.mcpServerIdsValue = parseEnabledMcpServerIds(''); // 防御态空集合
      this.memoryInject = true; // 查询失败防御态 = 默认开（与列默认一致）
      this.knowledgeAutoInject = false; // 查询失败防御态 = 默认关（与列默认一致）
      // 查询失败防御态 = 无归属行 + 全局库（助手行不在 = 助手库不可达，全局兜底）
      this.ownerId = '';
      this.memoryScopeValue = MEMORY_SCOPE_GLOBAL;
      return;
    }
    this.assistantName = owner.name;
    this.advanced = parseAssistantAdvancedParams(owner.advancedParams);
    this.tools = parseEnabledToolIds(owner.tools);
    this.skillIds = parseEnabledSkillIds(owner.skills);
    // MCP 绑定清单装载（skills 同位）：坏 JSON 容错回空集合（McpText 解析防御态）
    this.mcpServerIdsValue = parseEnabledMcpServerIds(owner.mcpServers);
    this.memoryInject = owner.memoryInject;
    // 知识自动注入开关（===1 归一已在 AssistantDb.mapAssistantRow 完成，此处收布尔）
    this.knowledgeAutoInject = owner.knowledgeAutoInject;
    // 归属 id 与记忆作用域（脏值兜底 'global' 与 AssistantDb 读取同口径）
    this.ownerId = owner.id;
    this.memoryScopeValue = owner.memoryScope !== '' ? owner.memoryScope : MEMORY_SCOPE_GLOBAL;
  }

  config(): PromptInjectConfig | null {
    return this.resolved;
  }

  // 会话状态快照：「请求注入」卡一次取数——字段全为解析缓存直接投影，消费方零复算
  statusSource(): ChatStatusSource {
    return {
      promptSourceKind: this.promptSource.kind,
      promptSourceName: this.promptSource.name,
      skillIds: this.enabledSkillIds(),
      memoryInjectEnabled: this.memoryInject,
      memoryScope: this.memoryScopeValue,
      knowledgeAutoInjectEnabled: this.knowledgeAutoInject
    };
  }

  // 助手启用工具 id 清单（发送组装时读取；默认集合语义见 parseEnabledToolIds）
  enabledToolIds(): string[] {
    return this.tools;
  }

  // 助手绑定的 MCP 服务器 id 清单（发送组装时读取——ChatSendCtrl refs 注入 collectTools 追加段）
  mcpServerIds(): string[] {
    return this.mcpServerIdsValue;
  }

  // 助手记忆注入开关（发送组装时读取——ChatSendCtrl.buildMemoryBlock 前置条件之一）
  memoryInjectEnabled(): boolean {
    return this.memoryInject;
  }

  // 助手知识自动注入开关（发送组装时读取——buildKnowledgeBlock 最外层闸）
  knowledgeAutoInjectEnabled(): boolean {
    return this.knowledgeAutoInject;
  }

  // 归属助手记忆作用域（发送组装时读取——注入选库与工具作用域中转键共用；'global' = 全局库）
  memoryScope(): string {
    return this.memoryScopeValue;
  }

  // 归属助手 id（scope='assistant' 时记忆库归属与工具执行者中转取值源；查询失败防御态 =
  // ''——调用方按全局库兜底）
  ownerAssistantId(): string {
    return this.ownerId;
  }

  // 本会话生效技能 id 清单（会话级技能启用已退役、控制台封锁分支已随控制台退役删除）——
  // 下游 buildSkillContext 与 use_skill 声明链只吃本函数
  enabledSkillIds(): string[] {
    return this.skillIds;
  }

  // 工具调用轮数上限（发送组装时读取；全局偏好键现读恒为生效上限——0 = 不限制已换算硬顶
  // 256；改设置后下一条消息即生效，无需重进会话）
  toolStepLimit(): number {
    return resolveToolStepLimit(AppStorage.get<number>(PREF_TOOL_STEP_LIMIT_KEY) ??
      TOOL_STEP_LIMIT_DEFAULT);
  }

  // 搜索结果条数（发送组装时读取；全局偏好键现读 = 1~25 整数，未写入或脏数据已回默认 5）
  searchResultCount(): number {
    return resolveSearchResultCount(AppStorage.get<number>(PREF_SEARCH_RESULT_COUNT_KEY) ??
      SEARCH_RESULT_COUNT_DEFAULT);
  }

  // 助手高级设定参数（发送组装时读取；null = 未配置不发送）
  advancedParams(): AssistantAdvancedParams | null {
    return this.advanced;
  }

  // 面板助手选择覆盖上行（ChatPage 经 ChatSendCtrl 透传；值恒非空——关闭非默认卡上行默认
  // id；与提示词覆盖互不清空）
  setBoundOverride(assistantId: string): void {
    this.boundOverride = assistantId;
  }

  // 面板提示词引用覆盖上行（与 boundOverride 并存独立——注入源 = 覆盖 ?? 行 promptId，
  // 归属恒走 effectiveAssistantId，两非空并存态行为正确）
  setPromptOverride(promptId: string): void {
    this.promptOverride = promptId;
  }

  // 当前提示词引用覆盖（ChatPromptSheet 主面板提示词卡显示态；无行会话 = 面板落选真源）
  promptOverrideId(): string {
    return this.promptOverride;
  }

  // 有效归属（仅无行场景——行 '' 走内置默认助手不经本函数；面板覆盖优先，否则当前助手
  //（AppStorage 持久键，缺省 = 内置默认助手，恒非 ''））
  effectiveAssistantId(): string {
    if (this.boundOverride !== '') {
      return this.boundOverride;
    }
    return AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  }

  // 会话归属助手是否启用 AI 配置域任一件（启用四件任一即出安全输入 chip 与暂存条——
  // manage_providers 建占位行后需安全输入面板填明文）。判据 = tools 缓存含四件任一（查询
  // 失败防御态四件全 false → fail-closed 隐藏，方向安全）
  aiAdminToolsEnabled(): boolean {
    return this.tools.includes(TOOL_MANAGE_PROVIDERS) || this.tools.includes(TOOL_MANAGE_MODELS) ||
      this.tools.includes(TOOL_TEST_PROVIDER) || this.tools.includes(TOOL_MANAGE_BALANCE);
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
      role: config.role, position: config.position, depth: config.depth,
      // volatile 标记检测替换前原文（替换后 {{time}} 文本已消失无从检测）；透传到
      // composeAnthropicBody 消费（volatile 降级缓存断点）
      volatileTime: hasVolatileTimeTokens(config.content)
    };
  }

  // 系统语言（{{language}} 替换值；返回 BCP 47 tag 如 zh-Hans-CN；失败兜底空串 = 保留原样）
  private systemLanguage(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch (e) {
      return '';
    }
  }
}
