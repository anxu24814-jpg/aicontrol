// 会话移动半模态面板（入口 = 历史会话卡「⋯」菜单「移动到助手」）：点选助手即把会话归属改到
// 该助手下（单列 UPDATE conversations.assistantId，历史消息、图数据与会话级覆盖零改动）。
// 决策口径（决明拍板，调研档 = docs/调研-会话移动-竞品机制与落地风险-20260930.md §五推荐
// 项）：菜单入口放行、会话内「助手选择面板」保持锁定；会话级模型覆盖保留（移动不清，说明行
// 标注）；控制台助手可作目标；正打开的会话不拦截（退出重进即生效，已知限制登记 BLOCKED）。
// 形状照 AssistantSheetPanel（同交互族）：数据自持有（打开即重拉，无陈旧缓存面）；行卡 =
// person 符号 + 助手名 + 能力摘要 + 当前归属项「当前」标记（实底胶囊 StatusBadge，不置灰
// 不禁用）；点行即移动（差异 = 右侧控件由开关改「整行点击」）。
// 能力摘要（S1「让落差在点之前可见」）：模型名 · 工具已开卡/卡总数 · 技能数 · 知识库数——
// 四个口径全复用既有单源（模型名 = ProviderDb 全量模型映射；工具 = ToolTypes.toolGroupAllOn；
// 技能 = SkillText；知识库 = KnowledgeText），与助手页/编辑页 chip 逐条同源，不另造口径。
// 行为三定：①当前归属项早退（同值不写库——RikkaHub 反面教材：同值重写会顺手清文件夹）；
// ②落库复用 AssistantDb.updateConversationAssistantId（返回受影响行数，0 行 = 会话已被
// 并发删除，toast 不静默）；③失败面板保留可重试（P0-1）。
// 说明行（S2）固定显示不按行态分支；会话单独选过模型时追加一行（S4——移动后模型不跟随
// 助手，标注让读者理解）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistants,
  queryConversationAssistantId, updateConversationAssistantId
} from '../../common/store/AssistantDb';
import { ConversationOverride, queryConversationOverride } from '../../common/store/ChatDb';
import { ModelRow, queryAllModels } from '../../common/store/ProviderDb';
import { parseEnabledToolIds, ToolGroup } from '../../common/providers/ToolTypes';
import { toolGroupAllOn, visibleToolGroups } from '../../common/providers/ToolCardView';
import { parseEnabledSkillIds } from '../../common/SkillText';
import { parseEnabledKnowledgeIds } from '../../common/KnowledgeText';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from './KimiSheetCommon';
// 全站状态词徽标形制单源（当前归属标记用实底胶囊）
import { StatusBadge } from '../StatusBadge';

@Component
export struct SessionMovePanel {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图
  // 照常完成
  private departed: boolean = false;
  // 目标会话 id（宿主透传；进入即加载，创建后不变——坑30 口径）
  @Prop conversationId: string = '';
  // 底部系统导航条高（vp，宿主注入——面板内容尾部让位；面板内 +24 固定呼吸）
  @Prop bottomInset: number = 0;
  // 移动流程收口上行（成功与 0 行兜底两路；宿主：关面板 + 重拉列表 + SESSION_LIST_RELOAD_KEY
  // 自增——源/目标两侧「会话 N」chip 随广播刷新）
  onMoved: () => void = () => {
  };
  // 关闭上行（标题栏 xmark；宿主与 onWillDismiss 同调一个关闭入口）
  onClose: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @State private assistants: AssistantRow[] = [];
  // 当前归属显示态（行显式绑定 = 行值；行 '' 存量未绑定 = 内置默认助手兜底〔2026-09-04
  // 定稿口径〕；行缺失/读取失败 = '' 无标记——防御）
  @State private currentId: string = '';
  // 本会话单独选过模型（S4 说明行显隐）
  @State private hasModelOverride: boolean = false;
  // 助手列表读取完成闸（首拉在途不闪空态；失败经 hintText 呈报不装「暂无助手」——P0-1）
  @State private loaded: boolean = false;
  @State private hintText: string = '';
  // 行数据版本纪元（四路异步读先后落定，任一落定自增——ForEach 键含本值，行随键重建带上
  // 最新摘要与当前态；键只写身份 + 当前态后缀同源 AssistantSheetPanel 机制）
  @State private dataEpoch: number = 0;
  // 助手模型显示名映射（providerId/modelId → 名；普通成员——刷新经 dataEpoch 键变重建，
  // 非观察类型不驱动 UI）
  private modelNames: Map<string, string> = new Map();
  // 工具分类卡视图（注册表进程级不变——AssistantPage 同款一次性预读）
  private groupsNormal: ToolGroup[] = [];
  // 移动写库在途（防连点重入；写库毫秒级，无需 UI 反馈态）
  private moving: boolean = false;
  // 面板底部留白（BottomInset + 固定 24——面板形态内容不贴手势条，ChatPromptSheet 同口径）
  private bottomPadInset: number = 0;
  // 滚动控制器（宿主壳 bindToScrollable 绑标题栏渐变模糊——传引用共用同一实例）
  scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.bottomPadInset = this.bottomInset + 24;
    this.groupsNormal = visibleToolGroups();
    this.reload();
  }

  // 数据自持有（打开即重拉，无陈旧缓存面）；四路读各自落定各自自增纪元——失败落 hint 不静默
  private reload(): void {
    queryAssistants()
      .then((rows: AssistantRow[]): void => {
        if (this.departed) {
          return;
        }
        this.assistants = rows;
        this.loaded = true;
        this.dataEpoch++;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = '助手列表读取失败：' + (e as Error).message;
        this.loaded = true;
      });
    queryAllModels()
      .then((rows: ModelRow[]): void => {
        const names: Map<string, string> = new Map();
        for (const row of rows) {
          names.set(row.providerId + '/' + row.modelId, row.name !== '' ? row.name : row.modelId);
        }
        this.modelNames = names;
        this.dataEpoch++;
      })
      .catch((): void => {
        this.dataEpoch++;
      });
    queryConversationAssistantId(this.conversationId)
      .then((assistantId: string | null): void => {
        if (this.departed) {
          return;
        }
        this.currentId = assistantId !== null && assistantId !== ''
          ? assistantId : (assistantId === null ? '' : ASSISTANT_DEFAULT_ID);
        this.dataEpoch++;
      })
      .catch((): void => {
        this.dataEpoch++;
      });
    queryConversationOverride(this.conversationId)
      .then((override: ConversationOverride | null): void => {
        if (this.departed) {
          return;
        }
        this.hasModelOverride = override !== null && override.modelProviderId !== ''
          && override.modelId !== '';
        this.dataEpoch++;
      })
      .catch((): void => {
        this.dataEpoch++;
      });
  }

  // 助手模型显示名（未绑定 = 未绑定模型；绑定查无行兜底显示 modelId——不空报）
  private modelLabelOf(row: AssistantRow): string {
    if (row.providerId === '' || row.modelId === '') {
      return '未绑定模型';
    }
    const name: string | undefined = this.modelNames.get(row.providerId + '/' + row.modelId);
    return name !== undefined ? name : row.modelId;
  }

  // 能力摘要（四段拼接；★ 2026-10-25 控制台合并笔：原「控制台跳过技能项」随控制台退役删除）
  private summaryOf(row: AssistantRow): string {
    const groups: ToolGroup[] = this.groupsNormal;
    const ids: string[] = parseEnabledToolIds(row.tools);
    let on: number = 0;
    for (const group of groups) {
      if (toolGroupAllOn(group, ids)) {
        on++;
      }
    }
    let text: string = this.modelLabelOf(row) + ' · 工具 ' + on + '/' + groups.length;
    text += ' · 技能 ' + parseEnabledSkillIds(row.skills).length;
    return text + ' · 知识库 ' + parseEnabledKnowledgeIds(row.knowledge).length;
  }

  // 点选移动（面板唯一动作）：当前归属早退（同值不写库，toast + 关面板）；0 行 = 会话已被删
  //（轻量校验，走收口上行关面板重拉——幽灵卡随之消失）；成功 toast + 收口；失败保留面板可
  // 重试（P0-1 不静默）
  private pick(row: AssistantRow): void {
    if (this.moving) {
      return;
    }
    if (this.currentId === row.id) {
      this.getUIContext().getPromptAction().showToast({ message: '该会话已在此助手下' });
      this.onClose();
      return;
    }
    this.moving = true;
    updateConversationAssistantId(this.conversationId, row.id)
      .then((affected: number): void => {
        if (this.departed) {
          return;
        }
        this.moving = false;
        if (affected === 0) {
          this.getUIContext().getPromptAction().showToast({ message: '移动失败：会话已不存在' });
          this.onMoved();
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已移至「' + row.name + '」' });
        this.onMoved();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.moving = false;
        this.getUIContext().getPromptAction().showToast(
          { message: '移动失败：' + (e as Error).message });
      });
  }

  build() {
    HdsNavigation() {
      List({ space: CARD_SPACING, scroller: this.scroller }) {
        // 固定说明行（S2：不按行态分支）+ 会话级模型覆盖标注（S4：移动不清覆盖——说明行
        // 标注让读者理解模型为何不跟随新助手）
        ListItem() {
          Column({ space: 6 }) {
            Text('移动后这条会话按所选助手的模型、提示词、工具、技能与记忆继续对话，历史消息不变')
              .fontSize(13)
              .fontColor(cardDescColor())
            if (this.hasModelOverride) {
              Text('本会话单独选过模型，移动后继续使用该模型')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 4, right: 4 })
        }
        // 空态/失败行（首拉完成闸：在途不闪；失败显示原因不装「暂无助手」）
        if (this.loaded && (this.hintText !== '' || this.assistants.length === 0)) {
          ListItem() {
            Text(this.hintText !== '' ? this.hintText : '暂无助手')
              .fontSize(13)
              .fontColor(this.hintText !== ''
                ? $r('sys.color.ohos_id_color_warning') : cardDescColor())
              .width('100%')
              .padding(16)
          }
        }
        // 助手行卡（person 符号 + 名/能力摘要两行 + 当前归属标记「当前」；Button(Normal)
        // 包裹 = 官方原生按压蒙层，ConvPicker 行卡同形；键含当前态后缀 + 数据纪元——当前态
        // 或摘要数据落定即键变重建；卡底 Column + 四周 padding 4 = 蒙层距卡外圈 4vp，壳
        // padding 12/9 回添，几何零位移）
        ForEach(this.assistants, (row: AssistantRow) => {
          ListItem() {
            Column() {
              Button() {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.person'))
                    .fontSize(20)
                    .fontColor([cardTitleColor()])
                  Column({ space: 2 }) {
                    Text(row.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(cardTitleColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.summaryOf(row))
                      .fontSize(13)
                      .fontColor(cardDescColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  if (this.currentId === row.id) {
                    StatusBadge({ text: '当前' })
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }
              .type(ButtonType.Normal)
              .width('100%')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .backgroundColor(Color.Transparent)
              .borderRadius(CARD_RADIUS)
              .onClick((): void => {
                this.pick(row);
              })
            }
            .width('100%')
            .padding(4)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
          }
        }, (row: AssistantRow): string => row.id + (this.currentId === row.id ? '|cur' : '')
          + '@' + this.dataEpoch)
        // 尾部安全区让位（底部 ignoreLayoutSafeArea 后末卡不贴导航条）
        ListItem() {
          Row()
            .height(this.bottomPadInset)
        }
      }
      .width('100%')
      .height('100%')
      // 滚动内容穿透标题栏背后（clip(false) 缺省裁剪 = 渐变模糊无内容可透——规范 §2）
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .padding({ top: 20, left: 16, right: 16 })
    }
    // 标题栏（KimiSheetCommon 单源：主副标题 + xmark 关闭 + AUTO 分割线 + 静止渐变模糊 +
    // 材质随档——勿自绘标题）
    .titleBar(sheetTitleBarOptions('移动到助手', '选择这条会话要归属的助手', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
