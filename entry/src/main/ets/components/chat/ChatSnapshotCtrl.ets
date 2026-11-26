// 发送前快照域（自 ChatSendCtrl.ets 域级最小拆分迁出）。域定义一句话：**两块 system 注入
// 材料的读取与组装**——记忆块（buildMemoryBlock）与技能上下文（buildSkillContext，含单条
// 指定技能正文块）。两方法均为「无编排态查询」：只读 ChatPromptState 解析缓存与页面闭包
//（隐私态/助手归属），不持任何流式/轮次状态，故以普通类承载（快照取值口径 =「发送/重试
// 一刻取当下值」）。消费方三：send 链（dispatchSend 前置）、重试组装段（ChatRetryHost.
// launchRetryRound 回接）、上下文活算（ctxCalc 构造闭包）。
import { querySkill, querySkillFiles, querySkills, SkillFileRow, SkillRow } from '../../common/store/SkillDb';
import { appendDesignateId, composeSkillLoadReply, composeSkillManifest,
  selectEnabledSkills, SkillBriefItem, SkillFileItem } from '../../common/SkillText';
// 注入双封顶常量单源在 MemoryText（零 import 叶子）——记忆库管理页「窗口判定」需同值，
// 组件层私有常量不宜被 settings 域反向引用（坑50 模块环族群）；本件仅来源换件，值零变化
import {
  composeMemoryBlock, MEMORY_INJECT_MAX_CHARS, MEMORY_INJECT_MAX_COUNT, MemoryEntryItem
} from '../../common/MemoryText';
import { isMemoryEnabled, isMemoryToolReadMode } from '../../common/MemoryGen';
import { MemoryRow, queryAssistantMemories, queryMemories,
  MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatPromptState } from '../../common/chat/ChatPromptState';
import { ChatMessage } from './ChatMessageCompose';
// 知识关键词触发（匹配域纯函数 + 常量，零 import 叶子）：scanKnowledgeWindow 已退役——
// 窗口截取移入匹配器域内随条目级 scanDepth 分桶，签名 =「历史 + 草稿」原始序列
import { composeKnowledgeSystemBlock, selectKnowledgeDepthHits, KNOWLEDGE_INJECT_MAX_CHARS,
  KNOWLEDGE_INJECT_MAX_COUNT, matchKnowledgeEntries,
  KnowledgeMatchEntry } from '../../common/KnowledgeMatch';
// 启用清单解析与关键词切词（分隔符单源 KNOWLEDGE_KEYWORD_SEP 两方向之一——切词在
// KnowledgeImportText，解析在 KnowledgeText）；clampKnowledgeScan = scanDepth 脏值归一位
//（匹配器拿到的恒 1~20，脏值防御靠这一道）
import { clampKnowledgeScan, parseEnabledKnowledgeIds } from '../../common/KnowledgeText';
import { splitKnowledgeKeywords } from '../../common/KnowledgeImportText';
import { queryEntriesByBookIds, KnowledgeEntryRow } from '../../common/store/KnowledgeDb';
import { AssistantRow, queryAssistant } from '../../common/store/AssistantDb';
import { INJECT_DEPTH_MAX, INJECT_ROLE_SYSTEM, KnowledgeInjectPlan,
  PromptInjectConfig } from '../../common/providers/RequestInject';

// 深度钳位（0~INJECT_DEPTH_MAX——脏值防御，与 composeSendMessages 消费侧同值域）
function clampInjectDepth(depth: number): number {
  if (depth < 0) {
    return 0;
  }
  return depth > INJECT_DEPTH_MAX ? INJECT_DEPTH_MAX : depth;
}

// 技能上下文快照：清单文本 + 是否声明 use_skill 等——各值同源于一次「助手启用集 ∩ 库内
// 现存（∪ 指定）」计算（见 buildSkillContext），故「零启用零指定 = 零注入零声明」是结构
// 保证而非多处约定；skillNames = enabled 数组的名称投影（与 manifest 同源同序，供声明处
// composeUseSkillSchema 生成 name 动态 enum，禁二次查询另算一套）
export interface SkillSendContext {
  manifest: string;
  hasEnabled: boolean;
  // 本轮启用技能名（enabled 投影，与 manifest 同源同序）——use_skill 声明的 name.enum 取值面
  skillNames: string[];
  // 本轮指定技能的正文块（composeSkillLoadReply 产物——<skill_content name="…"> 包裹；
  // '' = 无指定/已删）——随本轮 **user 消息**注入（protocolText 首段；正文永不进 system）
  designatedBlock: string;
  // 本轮指定技能名（显示面标注句 composeSkillDesignateMark 用；'' = 无指定/已删）
  designatedName: string;
}

// 快照域构造入参（ChatPromptState 缓存承载助手/提示词解析）；**件内可见即可**——宿主按
// 对象字面量传参、不引类型名
export class ChatSnapshotCtrl {
  private promptState: ChatPromptState;

  constructor(promptState: ChatPromptState) {
    this.promptState = promptState;
  }

  // 记忆参与判定（三闸单源）：总开关 ∩ 归属助手「注入」开关。注入块与 search_memory
  // 工具声明共用本判定——读取方式只换「注入还是检索」的形态（buildMemoryBlock 加 mode
  // 守卫、声明收集处按 mode 追加），两闸不因换形态豁免（总开关关/助手关 = 既不注入也不声明）
  memoryParticipates(): boolean {
    return isMemoryEnabled() &&
      this.promptState.memoryInjectEnabled();
  }

  // 记忆块构建：隐私会话 / 总开关关 / 归属助手注入开关关 / 库内无记忆 → ''（等价不注入，
  // 请求体零变化）；有记忆 → 30 条/2000 字双封顶块（composeMemoryBlock——按卡片序
  //〔sortOrder/createdAt/content 三键〕选取与渲染，用户排定的顺序即注入顺序）。
  // ★ 读取方式：按需读取（mode='tool'）时恒 ''——记忆改为经 search_memory 工具按需检索
  //（声明追加在 dispatchSend 工具声明收集处）；inject 态产出逐字节不变。
  // 失败吞错回 ''（记忆缺席不阻断发送主链路——hilog 留痕）。
  // ★ 助手级记忆：按归属助手作用域选库——'assistant' = 该助手自己的库
  //（queryAssistantMemories），'global' = 全局库原路径；ownerId 空（助手行不在的防御态）
  // = 全局库兜底，与「全局兜底」拍板语义一致。appendSystemMemory 落点与两条顺序红线
  // 零触碰——本函数只换块的内容来源
  async buildMemoryBlock(): Promise<string> {
    if (!this.memoryParticipates() || isMemoryToolReadMode()) {
      return '';
    }
    try {
      const useAssistantLib: boolean =
        this.promptState.memoryScope() === MEMORY_SCOPE_ASSISTANT &&
        this.promptState.ownerAssistantId() !== '';
      const rows: MemoryRow[] = useAssistantLib ?
        await queryAssistantMemories(this.promptState.ownerAssistantId()) :
        await queryMemories();
      if (rows.length === 0) {
        return '';
      }
      const items: MemoryEntryItem[] = [];
      for (const row of rows) {
        items.push({ content: row.content, createdAt: row.createdAt });
      }
      return composeMemoryBlock(items, MEMORY_INJECT_MAX_COUNT, MEMORY_INJECT_MAX_CHARS);
    } catch (e) {
      hilog.warn(0x0001, 'ChatSend', '记忆块读取失败，本次发送不注入：%{public}s',
        (e as Error).message);
      return '';
    }
  }

  // 技能上下文构建（清单与声明同闸的单一来源）：助手启用集 ∩ 库内现存技能 → 非空才有
  // 清单文本 + hasEnabled 标记；★ 同一次计算同时供给「system 清单注入」与「use_skill 声明
  // 追加」两处——各算一遍 = 两处漂移面，会让「清单里没有技能却声明了工具」这种自相矛盾的
  // 请求出得去。启用集为空（新装/新建助手默认 ''、全被兜底过滤）→ manifest '' 且
  // hasEnabled false = 零注入零声明，请求与无技能版逐字节一致（负向钉）。
  // ★ 单条消息指定技能：①并入 = 助手启用集 ∪ 本件指定（appendDesignateId 去重）；②两处
  // 早退判据各加「且零指定」——仅指定、零启用助手也要出正文与声明；③指定件取正文块
  //（composeSkillLoadReply——与 use_skill 回执同形；已删 = 降级为无指定 + hilog 留痕，
  // 不阻断发送）。「启用集 ∩ 库内现存」路径原样不变——并集内的悬空 id 由
  // selectEnabledSkills 自然过滤（删技能的第二道保险）。
  // ★ 形参 designateArg = send() 入口快照（F1）：本函数**禁直读页面当下指定值**（它是
  //「当下页面值」，而本轮该用的是「投递那一刻的值」——两者在组装窗口内可不同）。
  // 失败吞错回空上下文（技能缺席不阻断发送主链路——hilog 留痕，记忆块同款）
  async buildSkillContext(designateArg: string): Promise<SkillSendContext> {
    const empty: SkillSendContext = { manifest: '', hasEnabled: false, skillNames: [],
      designatedBlock: '', designatedName: '' };
    const designateId: string = designateArg;
    try {
      const enabledIds: string[] = appendDesignateId(this.promptState.enabledSkillIds(), designateId);
      if (enabledIds.length === 0) {
        return empty; // 未启用任何技能且无指定——连库都不查（零启用的常见路径零开销）
      }
      const rows: SkillRow[] = await querySkills();
      const items: SkillBriefItem[] = [];
      for (const row of rows) {
        items.push({ id: row.id, name: row.name, description: row.description });
      }
      const enabled: SkillBriefItem[] = selectEnabledSkills(items, enabledIds);
      if (enabled.length === 0 && designateId === '') {
        return empty; // 启用集里的 id 在库内全不存在（旧备份/删技能后的残留）——当未启用
      }
      let designatedBlock: string = '';
      let designatedName: string = '';
      if (designateId !== '') {
        const designateRow: SkillRow | null = await querySkill(designateId);
        if (designateRow === null) {
          // 页面存活期间被删 = 降级为无指定（该技能已不存在，本轮按无指定走；不假装成功，
          // 也不阻断发送——hilog 留痕）
          hilog.warn(0x0001, 'ChatSend', '指定技能不存在，本轮按无指定发送：%{public}s', designateId);
        } else {
          const files: SkillFileRow[] = await querySkillFiles(designateRow.id);
          const fileItems: SkillFileItem[] = [];
          for (const file of files) {
            fileItems.push({ id: file.id, name: file.name });
          }
          designatedBlock = composeSkillLoadReply(
            { name: designateRow.name, description: designateRow.description,
              content: designateRow.content }, fileItems);
          designatedName = designateRow.name;
        }
      }
      return { manifest: composeSkillManifest(enabled), hasEnabled: enabled.length > 0,
        skillNames: enabled.map((item: SkillBriefItem): string => item.name),
        designatedBlock: designatedBlock, designatedName: designatedName };
    } catch (e) {
      hilog.warn(0x0001, 'ChatSend', '技能清单读取失败，本次发送不注入：%{public}s',
        (e as Error).message);
      return empty;
    }
  }

  // 知识注入计划构建：开关关/未绑书/未启用库/零候选/零命中五态全部空 plan（两字段空 =
  // 请求与不装本功能逐字节一致，负向钉）。链路：闸（开关，假 = 零 DB 查询）→ 归属助手
  // 启用书序 → 条目池过滤（停用 + 空关键词双排除）→ 窗口文本（落屏 user/assistant 文本
  // 正文 + 本轮草稿恒在窗口末位——「刚提到的词立刻生效」）→ 匹配（大小写不敏感子串，
  // 四键排序）→ 分流（system 身份 → 系统块；其余 → 逐条深度注入配置）。
  // ★ 面板与实发共用本方法（ChatSendCtrl 发送/重试两链与 ChatContextUsage.computeLive
  // 三消费方同源，禁第二实现——「面板与实发一致」既有纪律）。
  // history 入参 = dataSource.allMessages() 原始形态（ChatMessage：kind/text 字段——
  // 非 buildRequestHistory 产物；窗口匹配只需文本正文，工具卡/思考/notice 行不参与）。
  // 失败吞错回空 plan（知识缺席不阻断发送主链路——hilog 留痕，记忆块同款）
  async buildKnowledgeBlock(draftText: string, history: ChatMessage[]):
    Promise<KnowledgeInjectPlan> {
    const empty: KnowledgeInjectPlan = { systemBlock: '', depthInjects: [] };
    if (!this.promptState.knowledgeAutoInjectEnabled()) {
      return empty; // 闸一：开关关 = 零 DB 查询零注入
    }
    try {
      const ownerId: string = this.promptState.ownerAssistantId();
      const owner: AssistantRow | null =
        ownerId === '' ? null : await queryAssistant(ownerId);
      // 启用书序（parseEnabledKnowledgeIds 保序去重——数组序即书序，排序第一键的取值源）
      const enabledIds: string[] =
        owner !== null ? parseEnabledKnowledgeIds(owner.knowledge) : [];
      if (enabledIds.length === 0) {
        return empty;
      }
      const rows: KnowledgeEntryRow[] = await queryEntriesByBookIds(enabledIds);
      // 过滤两排除（拍板 §10-1）：enabled === 0 整条停用；关键词拆后非空才可自动注入
      const candidates: KnowledgeMatchEntry[] = [];
      for (const row of rows) {
        if (row.enabled === 0) {
          continue;
        }
        const keywords: string[] = splitKnowledgeKeywords(row.keywords);
        if (keywords.length === 0) {
          continue;
        }
        const bookIndex: number = enabledIds.indexOf(row.bookId);
        if (bookIndex < 0) {
          continue; // 悬空防御（理论不达——行自 enabledIds 集查出）
        }
        candidates.push({ id: row.id, title: row.title, keywords: keywords,
          content: row.content, bookIndex: bookIndex, sortOrder: row.sortOrder,
          createdAt: row.createdAt, injectRole: row.injectRole,
          injectPosition: row.injectPosition, injectDepth: row.injectDepth,
          // 触发精度四字段：scanDepth 在此 clampKnowledgeScan 归一（匹配器拿到的恒是
          // 1~20）；priority 透传（行写入侧已归一，直接透传不重复钳——排序脏值只影响次序
          // 不影响正确性，且 0~9999 由 UI/工具/导入三写入口全部经 clamp）
          matchCase: row.matchCase, matchWhole: row.matchWhole,
          priority: row.priority, scanDepth: clampKnowledgeScan(row.scanDepth) });
      }
      if (candidates.length === 0) {
        return empty;
      }
      const historyTexts: string[] = [];
      for (const msg of history) {
        if ((msg.kind === 'user' || msg.kind === 'assistant') && msg.text !== '') {
          historyTexts.push(msg.text);
        }
      }
      // 「历史 + 草稿」原始序列交匹配器（窗口截取与分桶缓存域内完成——方案 §4.3）
      const hits: KnowledgeMatchEntry[] = matchKnowledgeEntries(candidates,
        historyTexts, draftText);
      if (hits.length === 0) {
        return empty;
      }
      // 分流：system 身份恒系统块（position 列对该身份无消费意义——与提示词模板注入链
      // 既有语义一致：composeSendMessages 对 system 走首位/跳过分支，深度位 system 条目
      // 若走单配置路径会被「历史已含 system」守卫静默吞掉，故归系统块零丢失）；非 system
      // 身份（user/assistant）逐条走 composeSendMessages 单配置路径
      const systemHits: KnowledgeMatchEntry[] = [];
      const depthHits: KnowledgeMatchEntry[] = [];
      for (const hit of hits) {
        if (hit.injectRole === INJECT_ROLE_SYSTEM) {
          systemHits.push(hit);
        } else {
          depthHits.push(hit);
        }
      }
      // 深度组应用次序（拍板 §10-6）：深度降序、同深度按命中序（hits 序 = 四键序，
      // 下标稳定保序）
      const orderedIdx: number[] = depthHits.map((_e: KnowledgeMatchEntry, i: number): number => i);
      orderedIdx.sort((a: number, b: number): number => {
        const da: number = clampInjectDepth(depthHits[a].injectDepth);
        const db: number = clampInjectDepth(depthHits[b].injectDepth);
        return da !== db ? db - da : a - b;
      });
      // 深度组预算闸：与系统块共用同一对常量、按应用次序截停（不封顶则单轮注入量随命中数
      // 无上界——单条正文上限 6000 字）；截停语义与系统块同款（不截断单条、至少保 1 条），
      // 装载件 = selectKnowledgeDepthHits（零 import 直跑面）
      const orderedDepth: KnowledgeMatchEntry[] = [];
      for (const i of orderedIdx) {
        orderedDepth.push(depthHits[i]);
      }
      const selectedDepth: KnowledgeMatchEntry[] =
        selectKnowledgeDepthHits(orderedDepth, KNOWLEDGE_INJECT_MAX_COUNT,
          KNOWLEDGE_INJECT_MAX_CHARS);
      // 深度组省略可观测：深度组逐条注入用户消息的不同深度位，无统一拼串点，不加文案尾注
      //（硬插会污染对话流，改装载件签名 = 撕开 302 组既有真值表等价面）——省略只留日志
      //（模型侧不伪装看到全部），数字交给 P3-b 构成卡显示（届时走 beginRound 同一份快照）
      const omittedDepthCount: number = orderedDepth.length - selectedDepth.length;
      if (omittedDepthCount > 0) {
        hilog.info(0x0001, 'ChatSend',
          '知识深度组超预算截停：命中 %{public}d 条，注入 %{public}d 条，省略 %{public}d 条',
          orderedDepth.length, selectedDepth.length, omittedDepthCount);
      }
      const depthInjects: PromptInjectConfig[] = [];
      for (const entry of selectedDepth) {
        depthInjects.push({ content: entry.content, role: entry.injectRole,
          position: entry.injectPosition, depth: clampInjectDepth(entry.injectDepth) });
      }
      return { systemBlock: composeKnowledgeSystemBlock(systemHits,
        KNOWLEDGE_INJECT_MAX_COUNT, KNOWLEDGE_INJECT_MAX_CHARS), depthInjects: depthInjects };
    } catch (e) {
      hilog.warn(0x0001, 'ChatSend', '知识块读取失败，本次发送不注入：%{public}s',
        (e as Error).message);
      return empty;
    }
  }
}
