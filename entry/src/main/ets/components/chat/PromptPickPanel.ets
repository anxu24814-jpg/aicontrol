// 「附件与提示词」半模态 · 选词面板域件（2026-09-01 助手域接入后自 ChatPromptSheet.ets
// 域级拆出——该文件必超 400 红线；交互原样搬迁）：模板列表行卡（图标 + 模板名 + 内容摘要
// + 右侧官方开关——2026-08-31 领导指令单注入语义：互斥单选，已有一个开关开启再开另一
// 个 → toast「不支持注入多提示词」拒绝 + 纪元重建弹回〔Toggle 非受控，ProviderCardItem
// 同款坑位〕；★2026-09-04 归属与注入解耦：单注入互斥撤销——不再清会话 assistantId，
// 本开关 = 独立「提示词注入」开关；关掉当前开启的开关 = 清引用回退**归属助手提示词**
// （不再回退系统提示词）；未选任何行 = 注入归属助手提示词）。
// ★ 无行会话（2026-09-04 隐私会话开放提示词选择；懒创建新会话同口径，AssistantSheetPanel
// 先例同款）：落库无行可写（0 行静默丢失坑）——跳过落库，选中值直接上行（页面
// ChatPromptState.promptOverride 内存持有，本页生命周期内即时生效）；'' = 清引用回退
// 归属助手提示词。
// 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）；选中上行
// onPicked(promptId, promptName)——宿主更新主面板卡状态 + onPromptChanged + 回主面板。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { queryConversationAssistantId } from '../../common/store/AssistantDb';
import {
  PromptTemplateRow, queryConversationPromptId, queryTemplates, updateConversationPromptId
} from '../../common/store/PromptTemplateDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

@Component
export struct PromptPickPanel {
  // 目标会话 id（宿主透传）
  @Prop conversationId: string = '';
  // 已保存的会话提示词引用（进入面板播种开关初始态；'' = 未选）
  @Prop currentId: string = '';
  // 面板底部留白（尾部安全区让位行高）
  @Prop bottomPadInset: number = 0;
  // 选中上行（宿主更新主面板两卡状态 + onPromptChanged + 回主面板）
  onPicked: (promptId: string, promptName: string) => void = () => {
  };
  // 滚动控制器（宿主 sheet 壳 bindToScrollable 绑标题栏渐变模糊——传引用共用同一实例）
  scroller: Scroller = new Scroller();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private templates: PromptTemplateRow[] = [];
  @State private pickCurrentId: string = '';
  // 开关纪元（拒绝开第二个时自增——ForEach 键含纪元全列表重建，被拒行开关随重建弹回）
  @State private switchEpoch: number = 0;
  // 会话行存在性（aboutToAppear 查询落定——三态取 null 判定；无行 = 懒创建新会话/隐私
  // 会话，pick 不落库只上行覆盖，AssistantSheetPanel 同款口径；初值 true = 查询失败走
  // 既有落库链，失败有 toast 不静默丢失）
  private rowExists: boolean = true;

  aboutToAppear(): void {
    this.pickCurrentId = this.currentId;
    this.scroller.scrollToIndex(0, true, ScrollAlign.START);
    this.reload();
    queryConversationAssistantId(this.conversationId)
      .then((assistantId: string | null): void => {
        this.rowExists = assistantId !== null;
      })
      .catch((): void => {
        // 读失败保持 true（默认走落库链——与既有失败提示语义一致）
      });
  }

  private reload(): void {
    queryTemplates()
      .then((rows: PromptTemplateRow[]): void => {
        this.templates = rows;
      })
      .catch((): void => {
        this.templates = [];
      });
  }

  private nameOf(promptId: string): string {
    for (const row of this.templates) {
      if (row.id === promptId) {
        return row.name;
      }
    }
    return '';
  }

  private preview(content: string): string {
    return content !== '' ? content.substring(0, 20) + (content.length > 20 ? '…' : '') : '无内容';
  }

  // 选模板落库（2026-09-04 归属与注入解耦：单注入互斥写序已删——不再清会话 assistantId，
  // 归属恒在；'' = 清引用回退归属助手提示词）
  // ★ 无行会话（懒创建新会话/隐私会话）：落库无行可写（0 行静默丢失）——跳过落库，
  // 选中值直接上行（ChatPromptState.promptOverride 持有）
  private pick(promptId: string): void {
    if (!this.rowExists) {
      this.pickCurrentId = promptId;
      this.onPicked(promptId, this.nameOf(promptId));
      return;
    }
    updateConversationPromptId(this.conversationId, promptId)
      .then((): void => {
        this.pickCurrentId = promptId;
        this.onPicked(promptId, this.nameOf(promptId));
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '提示词应用失败：' + (e as Error).message });
      });
  }

  // 开关切换（互斥单选仅限模板之间）：打开 = 已开另一个 → toast + 纪元弹回；允许 = pick
  // 落库；关闭当前 = pick('') 清引用 → 回退**归属助手提示词**（2026-09-04 解耦语义）
  private onSwitch(promptId: string, toOn: boolean): void {
    if (toOn) {
      if (this.pickCurrentId !== '' && this.pickCurrentId !== promptId) {
        this.getUIContext().getPromptAction().showToast({ message: '不支持注入多提示词' });
        this.switchEpoch++;
        return;
      }
      this.pick(promptId);
    } else {
      if (this.pickCurrentId === promptId) {
        this.pick('');
      }
    }
  }

  build() {
    List({ space: CARD_SPACING, scroller: this.scroller }) {
      // 提示词行（右侧官方开关；ForEach 键含选中态后缀 + 开关纪元——选中变/被拒回弹均
      // 键变重建）
      ForEach(this.templates, (row: PromptTemplateRow) => {
        ListItem() {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(20)
              .fontColor([cardTitleColor()])
            Column({ space: 2 }) {
              Text(row.name)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                // 名行单行收敛（名上限 50 字；同族行卡同款，防长名撑高行卡致面板高矮不一）
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(row.isGlobal ? '系统提示词（默认）' : this.preview(row.content))
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.pickCurrentId === row.id })
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
      }, (row: PromptTemplateRow): string => row.id +
        (this.pickCurrentId === row.id ? '|on' : '') + '@' + this.switchEpoch)
      // 尾部透明占位（底部安全区让位——Blank 在 ListItem 下编译 10905201，用 Row）
      ListItem() {
        Row()
          .height(this.bottomPadInset)
      }
    }
    .width('100%')
    .layoutWeight(1)
    // ★ 动态模糊生效前提（沉淀「列表类」节）：滚动内容穿透标题栏背后（clip(false) 缺省
    // 裁剪 = 模糊无内容可透——领导实测「顶部没渐变模糊」根因）
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    // 横向 padding 16 承收窄（ProviderCardItem 先例：卡 width 100% = 列表内容区宽，总边距
    // = 屏宽 −32 与 HDS 卡语义对齐——勿对卡再挂 CARD_PANEL_WIDTH/margin，双重收窄或叠加
    // 超宽）；顶 20 = 首卡与标题栏蒙层留白
    .padding({ top: 20, left: 16, right: 16 })
  }
}
