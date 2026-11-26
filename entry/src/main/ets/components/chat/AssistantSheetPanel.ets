// 「会话设置」半模态 · 助手选择面板（ChatPromptSheet 面板三，选词面板同款交互语言；★
// 2026-10-30 面板自「附件与提示词」更名）：
// 助手列表行卡 + 右侧官方开关。
// ★★ 归属语义定稿（决明「会话必须归属于一个助手」）：恒显式归属 + 默认助手兜底——面板 =
// **radio 联动**：开启任意助手 = 其他自动关（删强制单选拒绝——拒绝存在「关 X 落默认后开 B
// 被拒」死循环）；关闭非默认卡 = 自动回退内置默认助手；默认助手卡恒不可关闭（仅默认一个时
// toast「只有一个助手，必须选择一个助手」；多助手时 toast「默认助手为兜底，不能关闭」）。
// ★★ 晚锁定语义（决明「有消息会话换助手 = 前后半身份混搭矛盾」）：**行存在 = 已有消息**
//（会话行仅 insertMessage 懒创建 + sweep 清无消息行——query 返 null 即空会话，零新查询
// 判据）——有行会话任何开关操作 = toast「已有消息的会话不能更换助手」+ 纪元弹回（归属
// 锁定）；空会话保持 radio 联动 + 默认兜底；首条消息落行即锁定。提示词注入开关（面板二）
// 不受影响（只换注入源不换归属）；隐私会话（恒无行）按空会话口径允许切换。
// ★ 存量 '' 行（旧跟随口径）与无行会话：开关显示 = 兜底——行 '' → 默认助手、无行 →
// boundId（面板覆盖 ?? 当前助手 ?? 默认助手）；pick 对无行会话不落库（0 行静默丢失坑）只
// 上行覆盖（ChatPromptState.boundOverride 持有，首条消息落行写入）。
// 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）。
// ★ 滚动骨架 = Scroll + Column（★ 勿改回 List，2026-10-30 决明真机报障后统一——与
// 2026-10-21 模板半模态 TemplatePickSheet / 同日 PromptPickPanel、SkillPickPanel 同病同修）：
// List 对滚出视口的行做布局级虚拟化，clip(false) 只管绘制裁剪、管不住行回收，行卡滑到视口
// 上缘即整张消失；Scroll 不回收子项，配 clip(false) 行卡才滑进标题栏渐变模糊区渐隐 =
// 记忆页选会话（ConvPickerSheet）同款形态。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistants, queryConversationAssistantId,
  updateConversationAssistantId
} from '../../common/store/AssistantDb';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';

@Component
export struct AssistantSheetPanel {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 目标会话 id（页面透传；进入即加载，创建后不变——坑30 口径）
  @Prop conversationId: string = '';
  // 无行兜底归属（宿主下发——无行新会话时显示态 = 有效归属 = 面板覆盖 ?? 当前助手 ??
  // 默认助手；存量 '' 行由 shownIdOf 解析，不经本值）
  @Prop boundId: string = '';
  // 面板底部留白（尾部安全区让位行高）
  @Prop bottomPadInset: number = 0;
  // 选择变化上行（assistantName 随行——主面板卡即时显示；提示词注入侧另经 onPromptChanged
  // 重载，归属与注入并存）
  onPicked: (assistantId: string, assistantName: string) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private assistants: AssistantRow[] = [];
  @State private currentId: string = '';
  // 开关纪元（唯一拒绝场景 = 关默认卡被拒——ForEach 键含纪元全列表重建，被拒行弹回）
  @State private switchEpoch: number = 0;
  // 会话行存在性（三态：null = 未定〔查询窗口毫秒级〕，onSwitch 静默跳过防误伤；false =
  // 无行〔pick 不落库只上行覆盖〕；true = 有行〔已有消息锁定〕）
  private rowExists: boolean | null = null;
  // 滚动控制器（宿主壳 bindToScrollable 共用同一实例）
  scroller: Scroller = new Scroller();

  // 归属兜底显示（行三态 → 显示 id）：显式绑定 = 行值；''（存量旧口径）= 默认助手；null
  //（无行新会话）= boundId（显示即发送落行实际归属）
  private shownIdOf(assistantId: string | null): string {
    if (assistantId !== null && assistantId !== '') {
      return assistantId;
    }
    return assistantId === null ? this.boundId : ASSISTANT_DEFAULT_ID;
  }

  aboutToAppear(): void {
    queryAssistants()
      .then((rows: AssistantRow[]): void => {
        if (this.departed) {
          return;
        }
        this.assistants = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        // 查询失败按空列表呈现 + hilog 留痕（P0-1 禁静默——降级面「暂无助手」与真无助手
        // 同观感，不留痕则故障无从取证）
        hilog.warn(0xD5A0, 'AssistantSheetPanel', '助手列表查询失败，按空列表呈现：%{public}s',
          (e as Error).message);
        this.assistants = [];
      });
    queryConversationAssistantId(this.conversationId)
      .then((assistantId: string | null): void => {
        if (this.departed) {
          return;
        }
        this.rowExists = assistantId !== null;
        this.currentId = this.shownIdOf(assistantId);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        hilog.warn(0xD5A0, 'AssistantSheetPanel', '会话归属查询失败，按无行兜底呈现：%{public}s',
          (e as Error).message);
        this.currentId = this.boundId; // 兜底显示有效归属（防御）；rowExists 保持 null
        //（未定）——onSwitch 静默跳过，不落库不误拦
      });
  }

  // 归属落库/上行（入参恒非空——关闭非默认卡由 onSwitch 翻译为 pick(默认助手) 兜底，'' 不
  // 再作绑定值）。无行会话跳过落库，覆盖值直接上行（boundOverride 持有，首条消息落行写入）
  private pick(assistantId: string): void {
    if (this.rowExists === false) {
      this.currentId = assistantId;
      this.onPicked(assistantId, this.nameOf(assistantId));
      return;
    }
    updateConversationAssistantId(this.conversationId, assistantId)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.currentId = assistantId;
        this.onPicked(assistantId, this.nameOf(assistantId));
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '助手应用失败：' + (e as Error).message });
      });
  }

  private nameOf(assistantId: string): string {
    for (const row of this.assistants) {
      if (row.id === assistantId) {
        return row.name;
      }
    }
    return '';
  }

  // 开关切换（radio 联动 + 默认兜底 + 晚锁定拦截）：开启 = 直接切换（无拒绝分支——联动
  // 模型下拒绝有死循环）；关闭非默认卡 = 回退默认助手；关闭默认卡 = 禁止（toast + 纪元
  // 弹回——Toggle 非受控，重建回弹）。★ 锁定优先：有行任何开关操作均拦截——归属不可更改
  private onSwitch(assistantId: string, toOn: boolean): void {
    if (this.rowExists === null) {
      return; // 行态未定（查询窗口毫秒级）——静默跳过本次操作，用户重试；误方向不落库不误拦
    }
    if (this.rowExists) {
      this.getUIContext().getPromptAction().showToast({ message: '已有消息的会话不能更换助手' });
      this.switchEpoch++;
      return;
    }
    if (toOn) {
      this.pick(assistantId);
    } else {
      if (this.currentId !== assistantId) {
        return; // 非当前开关异动（防御）
      }
      if (assistantId === ASSISTANT_DEFAULT_ID) {
        this.getUIContext().getPromptAction().showToast({ message:
          this.assistants.length <= 1 ? '只有一个助手，必须选择一个助手' : '默认助手为兜底，不能关闭' });
        this.switchEpoch++;
        return;
      }
      this.pick(ASSISTANT_DEFAULT_ID);
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: CARD_SPACING }) {
        if (this.assistants.length === 0) {
          Column({ space: 8 }) {
            Text('暂无助手')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('先到「助手」页签新建助手，再回到此处为会话选用')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width(CARD_PANEL_WIDTH)
          .padding(24)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
        }
        // 锁定说明行（有行 = 已有消息——防「点了没反应」困惑；仅 true 显示，未定不显示防
        // 查询窗口期闪现）
        if (this.rowExists === true) {
          Text('该会话已有消息，归属助手固定')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
            .padding({ left: 4, right: 4 })
        }
        // 助手行卡（person 符号 + 助手名 + 右侧开关；ForEach 键含选中态后缀 + 开关纪元——
        // 选中变/被拒回弹均键变重建）
        ForEach(this.assistants, (row: AssistantRow) => {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.person'))
              .fontSize(20)
              .fontColor([cardTitleColor()])
            Text(row.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.currentId === row.id })
              .onChange((on: boolean): void => {
                this.onSwitch(row.id, on);
              })
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
        }, (row: AssistantRow): string => row.id +
          (this.currentId === row.id ? '|on' : '') + '@' + this.switchEpoch)
        // 尾部安全区让位（底部 ignoreLayoutSafeArea 后末行不贴导航条）
        Row()
          .width('100%')
          .height(this.bottomPadInset)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      // 容器零左右边距，卡宽 CARD_PANEL_WIDTH 自理（规范-半模态 §3，ConvPickerSheet 同形；
      // 原 List padding left/right 16 + 卡 100% 的等价搬迁——几何零位移）；顶 20 = 首卡与
      // 标题栏蒙层留白（原 List padding top 同值）
      .padding({ top: 20 })
    }
    .width('100%')
    .height('100%')
    // 顶对齐（Scroll 缺省 Center，内容不满屏会垂直居中——ConvPickerSheet 同款显式防坑）
    .align(Alignment.Top)
    // 滚动内容穿透标题栏背后（clip(false) 缺省裁剪 = 渐变模糊无内容可透——规范 2 节）
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
