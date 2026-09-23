// 「附件与提示词」半模态 · 助手选择面板（2026-09-01 助手域新建——ChatPromptSheet 面板三，
// 选词面板同款交互语言）：助手列表行卡 + 右侧官方开关；
// ★★ 2026-09-04 归属语义定稿（决明「跟随当前语义不明，会话必须归属于一个助手」）：
// 恒显式归属 + 默认助手兜底——面板 = **radio 联动**：开启任意助手 = 其他自动关（删强制
// 单选拒绝——拒绝存在死循环：关 X 落默认后开 B 被「已有默认开启」拒绝必须绕）；关闭非
// 默认卡 = 自动回退**内置默认助手**（落库默认 id，兜底选择）；默认助手卡恒不可关闭
//（仅默认一个时 toast「只有一个助手，必须选择一个助手」；多助手时 toast「默认助手为
// 兜底，不能关闭」= 全关违反恒归属）。
// ★★ 2026-09-04 晚锁定语义（决明「有消息会话换助手 = 前半 A 身份、后半 B 身份混搭矛盾」）：
// **行存在 = 已有消息**（会话行仅 insertMessage 懒创建 + sweepEmptyConversations 清无消息行
// ——queryConversationAssistantId 返 null 即空会话，零新查询判据）——有行会话任何开关操作
// = toast「已有消息的会话不能更换助手」+ 纪元弹回（归属锁定）；空会话（无行）保持 radio
// 联动切换 + 默认兜底；首条消息落行即锁定。提示词注入开关（面板二）不受影响（只换注入源
// 不换归属）。隐私会话（恒无行）按空会话口径允许切换（一次性会话无持久混搭问题）。
// ★ 存量 '' 行（旧跟随口径）与无行会话：开关显示 = 兜底——行 '' → 默认助手、无行 →
// boundId（面板覆盖 ?? 当前助手 ?? 默认助手）；pick 对无行会话不落库（0 行静默丢失坑）
// 只上行覆盖（ChatPromptState.boundOverride 持有，首条消息落行写入）。
// 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistants, queryConversationAssistantId,
  updateConversationAssistantId
} from '../../common/store/AssistantDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

@Component
export struct AssistantSheetPanel {
  // 目标会话 id（页面透传；进入即加载，创建后不变——坑30 口径）
  @Prop conversationId: string = '';
  // 无行兜底归属（宿主下发，创建期同步值——无行新会话时开关显示态 = 有效归属 = 面板覆盖
  // ?? 当前助手 ?? 内置默认助手——显示即发送落行实际归属；存量 '' 行已由 shownIdOf 解析
  // 为默认助手，不经本值）
  @Prop boundId: string = '';
  // 面板底部留白（尾部安全区让位行高）
  @Prop bottomPadInset: number = 0;
  // 选择变化上行（assistantName 随行——主面板卡即时显示；ChatPromptSheet 另 onPromptChanged
  // 通知页面重载注入缓存——提示词注入侧不再互斥清空，归属与注入并存）
  onPicked: (assistantId: string, assistantName: string) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private assistants: AssistantRow[] = [];
  @State private currentId: string = '';
  // 开关纪元（2026-09-04 起唯一拒绝场景 = 关默认助手卡被拒——ForEach 键含纪元全列表重建，
  // 被拒行开关随重建弹回）
  @State private switchEpoch: number = 0;
  // 会话行存在性（aboutToAppear 查询落定——★2026-09-04 自检三态化：null = 未定（查询窗口
  // 毫秒级），onSwitch 静默跳过防误伤——初值 true 实锤空会话查询落定前点开关被锁定拦截；
  // false = 无行（懒创建新会话，pick 不落库只上行覆盖）；true = 有行（已有消息锁定））
  private rowExists: boolean | null = null;
  // 滚动控制器（宿主 sheet 壳 bindToScrollable 绑标题栏渐变模糊——传引用共用同一实例）
  scroller: Scroller = new Scroller();

  // 归属兜底显示（行三态 → 显示归属 id）：行显式绑定 = 行值；行 ''（存量未绑定/旧跟随
  // 口径）= 内置默认助手（2026-09-04 恒显式归属定稿）；行 null（无行新会话）= boundId
  //（宿主下发：面板覆盖 ?? 当前助手 ?? 默认助手——显示即发送落行实际归属）
  private shownIdOf(assistantId: string | null): string {
    if (assistantId !== null && assistantId !== '') {
      return assistantId;
    }
    return assistantId === null ? this.boundId : ASSISTANT_DEFAULT_ID;
  }

  aboutToAppear(): void {
    queryAssistants()
      .then((rows: AssistantRow[]): void => {
        this.assistants = rows;
      })
      .catch((): void => {
        this.assistants = [];
      });
    queryConversationAssistantId(this.conversationId)
      .then((assistantId: string | null): void => {
        this.rowExists = assistantId !== null;
        this.currentId = this.shownIdOf(assistantId);
      })
      .catch((): void => {
        this.currentId = this.boundId; // 查询失败兜底显示有效归属（防御）；rowExists 保持
        // null（未定）——onSwitch 静默跳过，行态错误方向不落库不误拦
      });
  }

  // 归属落库/上行（入参恒非空——★2026-09-04 恒显式归属：关闭非默认卡由 onSwitch 翻译为
  // pick(默认助手) 兜底回退，'' 不再作为绑定值产生；开启 = 直接切换（radio 联动，其余
  // 自动关——当前Id 变即 ForEach 键重建）。无行会话（懒创建新会话）：落库无行可写（0 行
  // 静默丢失）——跳过落库，覆盖值直接上行（boundOverride 持有，首条消息落行写入）
  private pick(assistantId: string): void {
    if (this.rowExists === false) {
      this.currentId = assistantId;
      this.onPicked(assistantId, this.nameOf(assistantId));
      return;
    }
    updateConversationAssistantId(this.conversationId, assistantId)
      .then((): void => {
        this.currentId = assistantId;
        this.onPicked(assistantId, this.nameOf(assistantId));
      })
      .catch((e: Object): void => {
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

  // 开关切换（radio 联动 + 默认兜底，2026-09-04 定稿；★晚锁定拦截）：开启 = 直接切换（其他
  // 自动关——无拒绝分支，联动模型下拒绝存在「关 X 落默认后开 B 被拒」死循环）；关闭非默认
  // 卡 = 回退内置默认助手（兜底选择）；关闭默认卡 = 禁止（toast + 纪元弹回——Toggle 非受控，
  // 重建回弹）。★ 锁定优先：有行（已有消息）任何开关操作均拦截——归属不可更改
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
    List({ space: CARD_SPACING, scroller: this.scroller }) {
      if (this.assistants.length === 0) {
        ListItem() {
          Column({ space: 8 }) {
            Text('暂无助手')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('先在「助手」页签新建助手，填入名称与提示词，再到此处为会话选用')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .padding(24)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
      }
      // 锁定说明行（★2026-09-04 晚：有行 = 已有消息——归属固定，防「点了没反应」困惑；
      // 仅 rowExists === true 显示（未定 null 不显示——防空会话查询窗口期闪现））
      if (this.rowExists === true) {
        ListItem() {
          Text('该会话已有消息，归属助手固定')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
            .padding({ left: 4, right: 4 })
        }
      }
      // 助手行卡（person 符号 + 助手名 + 右侧开关——★2026-09-04 决明指令去掉提示词摘要行，
      // 只留名称；ForEach 键含选中态后缀 + 开关纪元——选中变/被拒回弹均键变重建）
      ForEach(this.assistants, (row: AssistantRow) => {
        ListItem() {
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
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
        }
      }, (row: AssistantRow): string => row.id +
        (this.currentId === row.id ? '|on' : '') + '@' + this.switchEpoch)
      // 尾部安全区让位（底部 ignoreLayoutSafeArea 后末行不贴导航条）
      ListItem() {
        Row()
          .height(this.bottomPadInset)
      }
    }
    .width('100%')
    .layoutWeight(1)
    // 滚动内容穿透标题栏背后（clip(false) 缺省裁剪 = 渐变模糊无内容可透——规范 2 节）
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .padding({ top: 20, left: 16, right: 16 })
  }
}
