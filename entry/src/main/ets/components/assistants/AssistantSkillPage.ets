// 助手技能页：助手编辑页「技能」分区卡 push，param = 助手 id。
// ★ 原「指定模式」（hostKind='designate'，对话页半模态「技能」卡单入口 push 整页）
//   **整段退役**——技能选择改「附件与提示词」半模态第四子态（SkillPickPanel.ets，与提示词
//   注入同形制）；本页只余助手模式，hostKind 字段与 SkillDesignateParam/Result 两接口、
//   ROUTE_SKILL_DESIGNATE_PAGE 路由一并退役（负向钉：本文件零 'designate' / 两接口名 /
//   旧路由名残留）。
// · 助手模式：技能开关组卡（GroupSettingCard 开关行形态——只点开关切换，规范 §4.1）：行 =
//   名称（副标题 = 触发描述）+ 行尾官方 Toggle（★ 行首图标位随自定义图标功能退役 2026-11-02，
//   走官方无图标行形制）；开关即时落库
//  （serializeEnabledSkillIds 唯一序列化落点）；页顶说明句 = 生效范围与时机 + 上限。
//   ★ 启用上限 SKILL_ENABLED_MAX（10）：第 11 个开关**在页面上直接拒**（toast「最多启用
//   10 个技能」+ 纪元回弹）——上限执行在开关面而非发送链，用户当场知道为什么开不上；
//   判定在写入之前做**整集合**判定。
// · ★ 技能库管理**无本页入口**（决明指令先后撤助手模式与指定模式两入口行——唯一入口 =
//   设置 → 技能库；本页助手的启用开关照旧即改即生效）。
// · 空态：技能库为空时给引导语（设置 → 技能库），组卡不出（空组卡无意义）。
// · 刷新链：@State enabledIds 驱动组卡重建键（键含状态——GroupSettingCard 头注释「开关
//   显示刷新责任在调用方」）；本页清单只在进页拉一次。
// · 返回带 result（坑17）——pop({saved:true}) 触发编辑页 onPop 重拉「已启用 N 个技能」摘要。
import { PageShell } from '../../common/PageShell';
import { CARD_SPACING, cardDescColor, CARD_PANEL_WIDTH } from '../../common/Theme';
import { InfoCard } from '../InfoCard';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { AssistantRow, queryAssistant, updateAssistantSkills } from '../../common/store/AssistantDb';
import { querySkills, SkillRow } from '../../common/store/SkillDb';
import {
  parseEnabledSkillIds, serializeEnabledSkillIds, SKILL_ENABLED_MAX
} from '../../common/SkillText';
import { ROUTE_ASSISTANT_SKILL_PAGE } from '../../common/RouteNames';

@Component
export struct AssistantSkillPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 库内技能清单（进页时重拉）
  @State private skills: SkillRow[] = [];
  // 已启用技能 id（助手行 skills 列解析产物；Toggle 上行即写库 + 写本状态驱动组卡重建）
  @State private enabledIds: string[] = [];
  // 组卡重建纪元（坑16 家族 / AssistantToolsPage.toggleEpoch 同款）：GroupSettingCard.items
  // 是普通成员入参，父组件重渲不更新它、组件自身无状态变化 → 行 Toggle 定格首帧。尤其
  // **第 11 个开关被拒**这条：Toggle 的内部态已随用户点击翻成开，而拒绝路径不写任何数据
  //——若纪元不自增，键不变 → 组卡不重建 → 开关停在「开」的假象上（数据说没启用、界面说
  // 启用了）。故本纪元在**载入与每次开关交互（含被拒）**都自增
  @State private toggleEpoch: number = 0;
  private rowId: string = '';

  aboutToAppear(): void {
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
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '技能启用清单读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 技能库重拉（进页播种——库内增删后本页清单同步；失败 toast 不静默 P0-1）。★ 返回
  // Promise：调用方「收敛/重读」必须等本重拉完成——不等会按旧清单跑；库页入口撤净后
  // 仅剩进页一处调用（aboutToAppear），页内无第二次库读
  private reloadSkills(): Promise<void> {
    return querySkills()
      .then((rows: SkillRow[]): void => {
        if (this.departed) {
          return;
        }
        this.skills = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '技能读取失败：' + (e as Error).message });
      });
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
        if (this.departed) {
          return;
        }
        this.reloadEnabledIds();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 失败回滚：库读回灌（单一真源——AssistantMemoryPage 同款理由：取反回滚在连点时会把
  // 第二笔的态一并推翻）
  private reloadEnabledIds(): void {
    queryAssistant(this.rowId)
      .then((row: AssistantRow | null): void => {
        if (this.departed) {
          return;
        }
        if (row !== null) {
          this.enabledIds = parseEnabledSkillIds(row.skills);
          this.toggleEpoch += 1; // 回滚/重读也自增（「每次启用集写入都自增」这条不变量不留缺口）
        }
      })
      .catch((): void => {
      });
  }

  // 开关行数据（助手模式；GroupSettingCard 开关行：toggleValue/onToggle 两字段齐全，行尾官方
  // Toggle 唯一控制面；副标题 = 触发描述，空描述给明示——空副标题行会掉到 56vp 档观感不一致）。
  // ★ 无图标行形制（icon 缺省）——分割线左缩进随形取 8（DIVIDER_LEFT_NO_ICON 未导出，
  // AssistantMcpPage 同款字面量先例）
  private skillRows(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const skill of this.skills) {
      items.push({
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

  // 助手模式组卡重建键（键含启用集 + 库内清单 + **重建纪元**——任一变即重建拉新 Toggle；
  // GroupSettingCard 头注释「开关显示刷新责任在调用方」）。★ 纪元不可省：仅靠启用集内容
  // 判键，「第 11 个被拒」这种「内容没变但界面必须回弹」的场景键是不变的（见 toggleEpoch 注释）
  private switchGroupKey(): string {
    const ids: string = this.enabledIds.join(',');
    const names: string = this.skills.map((row: SkillRow): string => row.id).join(',');
    return ids + '|' + names + '|' + this.toggleEpoch;
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 页顶说明（InfoCard 单源件）：生效范围 / 保存时机 / 上限三判据
        InfoCard({ text: '这里的开关对该助手的全部会话生效。改动即时保存，不用重开会话，下一条消息就按新设置发送。最多同时启用 '
          + SKILL_ENABLED_MAX + ' 个技能。' })
        if (this.skills.length === 0) {
          // 空态行内提示行（13fp 次要色 + 卡宽无卡底；本页不进空组卡——没有行的开关卡
          // 是纯噪声）
          Text('技能库还没有技能。可在 设置 → 技能库 新建。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach([this.switchGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.skillRows(), dividerLeft: 8 })
          }, (key: string): string => key)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: '技能',
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17）：pop({ saved: true }) 触发编辑页 onPop 重拉「已启用
        // N 个技能」摘要
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
