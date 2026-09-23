// 助手技能/技能选择页（2026-09-13 技能层笔 1 新建，方案-技能层-20260913 §2.5；助手编辑页
// 「技能」分区卡 push，param = 助手 id；★ 2026-09-16 单条消息指定技能笔参数化双宿主——
// hostKind：'assistant' = 助手模式〔一行一件技能 + 行尾官方 Toggle，开关即时落
// assistants.skills 列，行为逐字不变〕/ 'designate' = 指定模式〔对话页「附件与提示词」半模态
// 「技能」卡单入口 push，param = SkillDesignateParam——全库可选，点一件即指定，只用于下一条
// 消息、发完自动清、不落库〕）：
// · 助手模式：技能开关组卡（GroupSettingCard 开关行形态——只点开关切换，规范 §4.1）：行 =
//   技能图标 + 名称（副标题 = 触发描述）+ 行尾官方 Toggle；开关即时落库（SkillText.
//   serializeEnabledSkillIds 唯一序列化落点）；页顶说明句 = 生效范围与时机 + 上限
//   （2026-09-20 决明指令加首行说明，文案与依据见 Content 内注释）；
//   ★ 启用上限 SKILL_ENABLED_MAX（10）：第 11 个开关**在页面上直接拒**（toast「最多启用
//   10 个技能」+ 纪元回弹）——上限执行在开关面而非发送链，用户当场知道为什么开不上；判定
//   在写入之前做**整集合**判定；
// · 指定模式（2026-09-16 单条消息指定技能）：**全库可选**（含助手未启用的技能——有意差异，
//   竞品 Open WebUI / LibreChat 只列已启用，见调研档 §三）；每行可点——点非当前行 = 指定并
//   返回、点当前行 = 取消指定并返回、当前指定行尾打勾（GroupSettingCard.selectedMark 位）；
//   页顶说明句 + 「管理技能库」行；★ 无恢复行（旧「会话覆盖」语义随退役一并撤除）；
// · 「管理技能库」入口行：push 技能库页（deep entry 的第二入口，与设置页行卡成双入口）；
// · 空态：技能库为空时给引导语（先去技能库创建），组卡不出（空组卡无意义）；
// · 刷新链：@State enabledIds / designateId 驱动组卡重建键（键含状态——GroupSettingCard 头
//   注释「开关显示刷新责任在调用方」）；库页返回经 push 回调 reload（库内删了技能，本页清单
//   要同步——助手模式重读助手行启用集，指定模式重解析指定名并把已删 id 收敛为空）；
// · 返回带 result（坑17）——助手模式 pop({ saved: true }) 触发编辑页 onPop 重拉「已启用
//   N 个技能」摘要；指定模式统一 pop({ skillId, skillName })（未选择 = 回原值，取消 = 两空），
//   ChatPage onPop 写两 @State；
// · ★ 控制台助手：两模式入口均被 UI 闸拦（助手模式编辑页对控制台不渲染技能卡；指定模式
//   面板 openSkillPage toast 拒绝），发送链另有硬封锁（ChatPromptState.applyOwner
//   skillBlocked）——多层守卫见方案 §2.8 #4。
import { PageShell } from '../../common/PageShell';
import { CARD_SPACING, cardDescColor, CARD_PANEL_WIDTH } from '../../common/Theme';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { AssistantRow, queryAssistant, updateAssistantSkills } from '../../common/store/AssistantDb';
import { querySkills, SkillRow } from '../../common/store/SkillDb';
import {
  parseEnabledSkillIds, serializeEnabledSkillIds, SKILL_ENABLED_MAX
} from '../../common/SkillText';
import {
  ROUTE_ASSISTANT_SKILL_PAGE, ROUTE_SKILL_DESIGNATE_PAGE,
  ROUTE_SKILL_LIBRARY_PAGE
} from '../../common/RouteNames';
import { skillIconResource } from '../settings/SkillIcons';

// 指定模式路由参数（2026-09-16 单条消息指定技能）：进入时的当前指定（'' = 未指定）
export interface SkillDesignateParam {
  skillId: string;
}

// 指定模式 pop 回传载荷（两出口统一带）：'' = 取消指定 / 未选择——ChatPage onPop 写两 @State
export interface SkillDesignateResult {
  skillId: string;
  skillName: string;
}

@Component
export struct AssistantSkillPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 宿主形态（PageMapBuilder 注入；普通成员——构造后不变，坑30 口径）：'assistant' = 助手模式
  // （param = 助手 id）/ 'designate' = 指定模式（param = SkillDesignateParam）
  hostKind: string = 'assistant';
  // 库内技能清单（aboutToAppear 与库页返回时重拉）
  @State private skills: SkillRow[] = [];
  // 已启用技能 id（助手模式 = 助手行 skills 列解析产物；Toggle 上行即写库 + 写本状态驱动组卡
  // 重建）
  @State private enabledIds: string[] = [];
  // 组卡重建纪元（★ 2026-09-13 真机预演反推补，坑16 家族 / AssistantToolsPage.toggleEpoch
  // 同款）：GroupSettingCard.items 是普通成员入参，父组件重渲不更新它、组件自身无状态变化
  // → 行 Toggle 定格首帧。尤其**第 11 个开关被拒**这条：Toggle 的内部态已随用户点击翻成开，
  // 而拒绝路径不写任何数据——若纪元不自增，键不变 → 组卡不重建 → 开关停在「开」的假象上
  //（数据说没启用、界面说启用了）。故本纪元在**载入与每次开关交互（含被拒）**都自增
  @State private toggleEpoch: number = 0;
  private rowId: string = '';
  // ── 指定模式参数（hostKind === 'designate' 时 aboutToAppear 填充；进页 param 一问一答，
  //    返回时原值或新值随 pop 回传——故两值 @State）──
  // 当前指定技能 id（'' = 未指定；点当前行取消、库内已删收敛为空）
  @State private designateId: string = '';
  // 当前指定技能名（pop 回传载荷与页内显示共用；库内查不到 = 已删 → 置空）
  @State private designateName: string = '';

  aboutToAppear(): void {
    if (this.hostKind === 'designate') {
      // 指定模式（2026-09-16）：param = SkillDesignateParam（SDK 实锤 getParamByName 回
      // Array，取末项——同路由多实例时栈顶最新）
      const params: Array<SkillDesignateParam> =
        this.pathStack.getParamByName(ROUTE_SKILL_DESIGNATE_PAGE) as Array<SkillDesignateParam>;
      const param: SkillDesignateParam | undefined =
        params.length > 0 ? params[params.length - 1] : undefined;
      if (param === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '缺少选择参数' });
        this.pathStack.pop({ skillId: '', skillName: '' } as SkillDesignateResult);
        return;
      }
      this.designateId = param.skillId;
      // 库读取与失败呈报同链（P0-1 不静默）：失败 toast 在 reloadSkills 内部，名字解析在
      // 重拉完成之后（读 this.skills——不等重拉会按空清单把有效指定误收敛成空）
      this.reloadSkills().then((): void => {
        this.resolveDesignateName();
      });
      return;
    }
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_SKILL_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    queryAssistant(param)
      .then((row: AssistantRow | null): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.enabledIds = parseEnabledSkillIds(row.skills);
        this.toggleEpoch += 1; // 库读回也自增（进页即拉新值，不依赖首帧）
        this.reloadSkills();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '技能启用清单读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 技能库重拉（库页返回时调用——库内增删后本页清单同步；失败 toast 不静默 P0-1）。
  // ★ 返回 Promise（2026-09-16 自检轮 F1）：库页返回的「收敛/重读」必须等本重拉完成——
  // 不等会按旧清单跑（指定模式之名解析 / 助手模式启用集重读同此纪律）
  private reloadSkills(): Promise<void> {
    return querySkills()
      .then((rows: SkillRow[]): void => {
        this.skills = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '技能读取失败：' + (e as Error).message });
      });
  }

  // 指定技能名解析（指定模式）：从库内清单取当前指定行的名字（页内显示与 pop 回传载荷共用）；
  // 查不到（页面存活期间被删）= 两值一并收敛为空——发送链 querySkill null 降级是第二道保险
  private resolveDesignateName(): void {
    if (this.designateId === '') {
      this.designateName = '';
      return;
    }
    for (const skill of this.skills) {
      if (skill.id === this.designateId) {
        this.designateName = skill.name;
        return;
      }
    }
    this.designateId = '';
    this.designateName = '';
  }

  // 开关目标集合 + 整集合上限判定（助手模式）：返回 null = 超限已拒（toast + 纪元回弹已做）。
  // ★ 上限判定在写入之前做**整集合**判定：只按「当前个数 ≥ 上限」判会在连点/并发下漏
  //（同一刻度内两次开都通过），故按本次目标集合长度判——目标集合超限即拒，开关状态不动
  private nextToggleSet(skillId: string, isOn: boolean): string[] | null {
    const next: string[] = isOn ?
      (this.enabledIds.includes(skillId) ? this.enabledIds.slice() :
        this.enabledIds.concat([skillId])) :
      this.enabledIds.filter((item: string): boolean => item !== skillId);
    if (isOn && next.length > SKILL_ENABLED_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '最多启用 ' + SKILL_ENABLED_MAX + ' 个技能'
      });
      // 数据不动（本页是唯一控制面，无第二真相），但**纪元必须自增**——Toggle 内部态已被
      // 这次点击翻成开，纪元不动 = 键不变 = 卡不重建 = 开关停在开（假象）；自增即重建回读
      // enabledIds → 开关弹回关，与 toast 一起构成「拒了且没生效」的完整反馈
      this.toggleEpoch += 1;
      return null;
    }
    return next;
  }

  // 开关落库（助手模式；即时生效，失败 toast + 回读回滚——P0-1）
  private toggleSkill(skillId: string, isOn: boolean): void {
    const next: string[] | null = this.nextToggleSet(skillId, isOn);
    if (next === null) {
      return;
    }
    this.enabledIds = next;
    this.toggleEpoch += 1;
    const serialized: string = serializeEnabledSkillIds(next);
    updateAssistantSkills(this.rowId, serialized)
      .catch((e: Object): void => {
        this.reloadEnabledIds();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 失败回滚：库读回灌（单一真源——AssistantMemoryPage 同款理由：取反回滚在连点时会把
  // 第二笔的态一并推翻）
  private reloadEnabledIds(): void {
    queryAssistant(this.rowId)
      .then((row: AssistantRow | null): void => {
        if (row !== null) {
          this.enabledIds = parseEnabledSkillIds(row.skills);
          this.toggleEpoch += 1; // 回滚/重读也自增（「每次启用集写入都自增」这条不变量不留缺口）
        }
      })
      .catch((): void => {
      });
  }

  // 开关行数据（助手模式；GroupSettingCard 开关行：toggleValue/onToggle 两字段齐全，行尾官方
  // Toggle 唯一控制面；副标题 = 触发描述，空描述给明示——空副标题行会掉到 56vp 档观感不一致）
  private skillRows(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const skill of this.skills) {
      items.push({
        icon: skillIconResource(skill.icon),
        label: skill.name,
        secondary: skill.description !== '' ? skill.description : '未填写触发描述',
        toggleValue: (): boolean => this.enabledIds.includes(skill.id),
        onToggle: (isOn: boolean): void => {
          this.toggleSkill(skill.id, isOn);
        }
      });
    }
    return items;
  }

  // 指定行数据（指定模式；跳转行形态 = onClick + selectedMark 两字段，无 Toggle）：
  // 点非当前行 = 指定并返回；点当前行 = 取消指定并返回（两空）；当前指定行尾打勾。
  // ★ 点行即 pop——页内不累积、无确认步（与助手模式的开关即时落库同为「一次交互即生效」）
  private designateRows(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const skill of this.skills) {
      const current: boolean = skill.id === this.designateId;
      items.push({
        icon: skillIconResource(skill.icon),
        label: skill.name,
        secondary: skill.description !== '' ? skill.description : '未填写触发描述',
        selectedMark: (): boolean => current,
        onClick: (): void => {
          this.pathStack.pop(current ?
            { skillId: '', skillName: '' } as SkillDesignateResult :
            { skillId: skill.id, skillName: skill.name } as SkillDesignateResult);
        }
      });
    }
    return items;
  }

  // 「管理技能库」入口行（跳转行形态：onClick 上抛 push；两模式共用）
  private manageRow(): GroupEntryItem[] {
    return [{
      icon: $r('sys.symbol.wand_and_stars'),
      label: '管理技能库',
      secondary: '新建、编辑或删除技能',
      onClick: (): void => {
        this.openSkillLibrary();
      }
    }];
  }

  // 助手模式组卡重建键（键含启用集 + 库内清单 + **重建纪元**——任一变即重建拉新 Toggle；
  // GroupSettingCard 头注释「开关显示刷新责任在调用方」）。★ 纪元不可省：仅靠启用集内容
  // 判键，「第 11 个被拒」这种「内容没变但界面必须回弹」的场景键是不变的（见 toggleEpoch 注释）
  private switchGroupKey(): string {
    const ids: string = this.enabledIds.join(',');
    const names: string = this.skills.map((row: SkillRow): string => row.id).join(',');
    return ids + '|' + names + '|' + this.toggleEpoch;
  }

  // 指定模式组卡重建键（键含当前指定 + 库内清单：库页返回删了指定技能 → 收敛后键变重建，
  // 打勾位不残留；点行即 pop 返回，页内无第二次渲染需求）——照 switchGroupKey 姿势
  private designateGroupKey(): string {
    const names: string = this.skills.map((row: SkillRow): string => row.id).join(',');
    return this.designateId + '|' + names;
  }

  // 「管理技能库」跳转：返回时**两样都要重读**（★ 2026-09-13 真机预演反推补：原先只重读技能
  // 清单，没重读助手行的启用集——库里删掉某技能后，页内 enabledIds 里那条 id 还在内存里，
  // 下次拨任何开关都会把它随序列化一起写回库（级联清列刚清掉的白写回来）。发送链有「启用∩
  // 现存」兜底不至于出错，但库里会攒悬空 id，与「删除联动清列」的立意相抵。库页是深层入口，
  // 它可能改的两样东西这里都得跟着走）；指定模式同纪律（名字解析与收敛读 this.skills，
  // 不等重拉会按旧清单跑——2026-09-16 自检轮 F1 时序钉）
  private openSkillLibrary(): void {
    this.pathStack.pushPathByName(ROUTE_SKILL_LIBRARY_PAGE, null, (): void => {
      this.reloadSkills().then((): void => {
        if (this.hostKind === 'designate') {
          this.resolveDesignateName();
        } else {
          this.reloadEnabledIds();
        }
      });
    });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 页顶说明小字（两模式各一句，13fp 次要色 + 卡宽无卡底——空态行同款归一形态）。
        // ★ 助手模式句（2026-09-20 决明指令「可否加首行说明」）答的是「技能开关改完何时
        // 生效」——助手级配置无会话副本，开关即时落库、回到对话的下一条消息即按新集发送
        //（解析时点 = ChatPromptState.load 四时点含 onShown，见该文件头注释），页面显式
        // 告知以免误读成「会话首次启用时的快照」；上限数字随 SKILL_ENABLED_MAX 拼接不写死
        if (this.hostKind === 'designate') {
          Text('选中的技能只用于下一条消息，发完自动取消。助手页的技能设置不受影响。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          Text('这里的开关对该助手的全部会话生效。改动即时保存，不用重开会话，下一条消息就按新设置发送。最多同时启用 '
            + SKILL_ENABLED_MAX + ' 个技能。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        }
        if (this.skills.length === 0) {
          // 空态行内提示行（13fp 次要色 + 卡宽无卡底——2026-09-12 归一形态；本页不进空组卡：
          // 一张没有行的开关卡在页面上是纯噪声）
          Text('技能库还没有技能。点下方「管理技能库」新建第一个技能。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else if (this.hostKind === 'designate') {
          ForEach([this.designateGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.designateRows() })
          }, (key: string): string => key)
        } else {
          ForEach([this.switchGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.skillRows() })
          }, (key: string): string => key)
        }
        GroupSettingCard({ items: this.manageRow() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: '技能',
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17）：助手模式 = saved 信号（编辑页 onPop 重拉「已启用
        // N 个技能」摘要）；指定模式统一带当前指定两值（未选择 = 回原值，取消 = 两空）——
        // ChatPage onPop 写两 @State
        if (this.hostKind === 'designate') {
          this.pathStack.pop({
            skillId: this.designateId, skillName: this.designateName
          } as SkillDesignateResult);
          return true;
        }
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
