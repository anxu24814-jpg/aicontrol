// 发送前快照域（2026-09-20 自 ChatSendCtrl.ets 域级最小拆分迁出——ChatSendCtrl 越宪法
// 1200 硬线，本件为继 ChatToolRoundCtrl/ChatContextUsageCalc/CubeEngineCtrl/ChatKeyRoundCtrl/
// ChatRetryCtrl 之后第六件域拆）。域定义一句话：**两块 system 注入材料的读取与组装**——
// 记忆块（buildMemoryBlock）与技能上下文（buildSkillContext，含单条指定技能正文块）。
// 两方法均为「无编排态查询」：只读 ChatPromptState 解析缓存与页面闭包（隐私态/助手归属），
// 不持任何流式/轮次状态，故以普通类承载（快照取值口径注释随方法体逐字自 ChatSendCtrl
// 搬迁——「发送/重试一刻取当下值」语义不变）。消费方三：send 链（dispatchSend 前置）、
// 重试组装段（ChatRetryHost.launchRetryRound 回接）、上下文活算（ctxCalc 构造闭包）。
import { querySkill, querySkillFiles, querySkills, SkillFileRow, SkillRow } from '../../common/store/SkillDb';
import { appendDesignateId, composeSkillLoadReply, composeSkillManifest,
  selectEnabledSkills, SkillBriefItem, SkillFileItem } from '../../common/SkillText';
import { composeMemoryBlock, MemoryEntryItem } from '../../common/MemoryText';
import { isMemoryEnabled, isMemoryToolReadMode } from '../../common/MemoryGen';
import { MemoryRow, queryAssistantMemories, queryMemories,
  MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatPromptState } from './ChatPromptState';

// 记忆注入双封顶（2026-09-08 记忆域：条数/字符双上限——宪法数据有界；注入顺序自定义笔后
// = 卡序贪心，超限保卡序前 N 条 + 省略尾注，拼装在 MemoryText.composeMemoryBlock）
const MEMORY_INJECT_MAX_COUNT: number = 30;
const MEMORY_INJECT_MAX_CHARS: number = 2000;

// 技能上下文快照（2026-09-13 技能层笔 1）：清单文本 + 是否声明 use_skill——两值同源于
// 一次「助手启用集 ∩ 库内现存」计算（见 buildSkillContext），故「零启用 = 零注入零声明」
// 是结构保证而非两处约定；★ 2026-09-16 单条消息指定技能扩两字段（designatedBlock /
// designatedName——同源于同一次计算，同闸同源不破）；★ 2026-09-16 技能管理工具与加载枚举
// 笔 B 单元扩 skillNames（清单 enabled 数组的名称投影——与 manifest 同一次计算同源同序，
// 供声明处 composeUseSkillSchema 生成 name 动态 enum，禁二次查询另算一套）
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

// 快照域构造入参（箭头闭包持页面/宿主延迟求值——ChatSendRefs 同款姿势；privateMode 为
// 隐私闸唯一页源，助手/提示词解析全在 ChatPromptState 缓存）。**件内可见即可**——宿主按
// 对象字面量传参、不引类型名（2026-09-20 自检回收「只加出口的 export」）
interface ChatSnapshotRefs {
  privateMode: () => boolean;
}

export class ChatSnapshotCtrl {
  private promptState: ChatPromptState;
  private refs: ChatSnapshotRefs;

  constructor(promptState: ChatPromptState, refs: ChatSnapshotRefs) {
    this.promptState = promptState;
    this.refs = refs;
  }

  // 记忆参与判定（2026-09-13 记忆按需读取，方案 §2.3——四闸单源）：非私密 ∩ 总开关 ∩
  // 归属助手「注入」开关。注入块与 search_memory 工具声明共用本判定——读取方式只换
  // 「注入还是检索」的形态（buildMemoryBlock 加 mode 守卫、声明收集处按 mode 追加），
  // 三闸不因换形态豁免（隐私会话/总开关关/助手关 = 既不注入也不声明）
  memoryParticipates(): boolean {
    return !this.refs.privateMode() && isMemoryEnabled() &&
      this.promptState.memoryInjectEnabled();
  }

  // 记忆块构建（2026-09-08 记忆域，任务书 §2.4）：隐私会话 / 总开关关 / 归属助手注入
  // 开关关 / 库内无记忆 → ''（等价不注入，请求体零变化）；有记忆 → 30 条/2000 字双封顶
  // 块（composeMemoryBlock——按卡片序〔sortOrder/createdAt/content 三键〕选取与渲染，
  // 用户排定的顺序即注入顺序）。
  // ★ 2026-09-13 读取方式：按需读取（mode='tool'）时恒 ''——记忆改为经 search_memory
  // 工具按需检索（声明追加在 dispatchSend 工具声明收集处）；inject 态产出逐字节不变。
  // 失败吞错回 ''（记忆缺席不阻断发送主链路——hilog 留痕）
  // ★ v35（2026-09-20 助手级记忆）：按归属助手作用域选库——'assistant' = 该助手自己的库
  //（queryAssistantMemories），'global' = 全局库原路径（存量行为逐字节不变）；ownerId 空
  //（助手行不在的防御态）= 全局库兜底，与「全局兜底」拍板语义一致。appendSystemMemory
  // 落点与两条顺序红线零触碰——本函数只换块的内容来源
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

  // 技能上下文构建（2026-09-13 技能层笔 1，方案 §2.4——清单与声明同闸的单一来源）：
  // 助手启用集 ∩ 库内现存技能 → 非空才有清单文本 + hasEnabled 标记；★ 同一次计算同时
  // 供给「system 清单注入」与「use_skill 声明追加」两处——各算一遍 = 两处漂移面，会让
  // 「清单里没有技能却声明了工具」这种自相矛盾的请求出得去。
  // 启用集为空（含新装/新建助手默认 ''、控制台助手封锁、全被兜底过滤）→ manifest ''
  // 且 hasEnabled false = 零注入零声明，请求与无技能版逐字节一致（负向钉）。
  // ★ 2026-09-16 单条消息指定技能（四处改动）：①控制台压掉（UI 闸是主通道，链路
  // 是兜底——控制台会话的指定恒被压成 ''）；②并入 = 助手启用集 ∪ 本件指定（appendDesignateId
  // 去重）；③两处早退判据各加「且零指定」——仅指定、零启用助手也要出正文与声明；④指定件
  // 取正文块（composeSkillLoadReply——与 use_skill 回执同形；已删 = 降级为无指定 + hilog
  // 留痕，不阻断发送）。★「启用集 ∩ 库内现存」路径原样不变——并集内的悬空 id 由
  // selectEnabledSkills 自然过滤（删技能的第二道保险）
  // ★ 形参 designateArg = send() 入口快照（自检轮 F1）：本函数**禁直读页面当下指定值**
  //（它是「当下页面值」，而本轮该用的是「投递那一刻的值」——两者在组装窗口内可不同）；
  // 控制台闸仍在此现读（晚读在此是**保守**方向：轮内改成控制台 = 本轮一并压掉，不泄漏）
  // 失败吞错回空上下文（技能缺席不阻断发送主链路——hilog 留痕，记忆块同款）
  async buildSkillContext(designateArg: string): Promise<SkillSendContext> {
    const empty: SkillSendContext = { manifest: '', hasEnabled: false, skillNames: [],
      designatedBlock: '', designatedName: '' };
    const designateId: string = this.promptState.skillsBlocked() ? '' : designateArg;
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
}
