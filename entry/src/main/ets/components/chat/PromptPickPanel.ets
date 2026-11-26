// 「附件与提示词」半模态 · 选词面板域件（自 ChatPromptSheet.ets 域级拆出，交互原样搬迁）：
// 模板列表行卡（图标 + 模板名 + 内容摘要 + 右侧官方开关），单注入互斥取**自动切换**——已有
// 一个开关开启再开另一个直接切换（原「toast 拒绝 + 纪元重建弹回」整段退役）。归属与注入
// 解耦：本开关 = 独立「提示词注入」开关，不清会话 assistantId；关掉当前开启的 = 清引用回退
// **归属助手提示词**（不再回退系统提示词）；未选任何行 = 注入归属助手提示词。
// ★ 无行会话（隐私会话开放提示词选择；懒创建新会话同口径，AssistantSheetPanel 先例同款）：
// 落库无行可写（0 行静默丢失坑）——跳过落库，选中值直接上行（页面 ChatPromptState.
// promptOverride 内存持有，本页生命周期内即时生效）；'' = 清引用回退归属助手提示词。
// 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）；选中上行
// onPicked(promptId, promptName)——宿主更新主面板卡状态 + onPromptChanged + 回主面板。
// ★ 滚动骨架 = Scroll + Column（★ 勿改回 List，2026-10-30 决明真机报障后统一——与
// 2026-10-25 模板半模态 TemplatePickSheet 同病同修）：List 对滚出视口的行做布局级虚拟化，
// clip(false) 只管绘制裁剪、管不住行回收，行卡滑到视口上缘即整张消失；Scroll 不回收子项，
// 配 clip(false) 行卡才滑进标题栏渐变模糊区渐隐 = 记忆页选会话（ConvPickerSheet）同款形态。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { queryConversationAssistantId } from '../../common/store/AssistantDb';
import { PromptTemplateRow, queryTemplates, updateConversationPromptId } from '../../common/store/PromptTemplateDb';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';

@Component
export struct PromptPickPanel {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
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
  // 模板清单读取失败提示（SessionMovePanel 同款形制——失败呈报原因，禁静默空列表 P0-1）
  @State private hintText: string = '';
  @State private pickCurrentId: string = '';
  // 开关纪元：唯一用途 = **落库失败时自增**——Toggle 非受控，点击已把内部态翻到新位置而库
  // 写失败不落值，纪元不动 = 键不变 = 卡不重建 = 开关停在假位置；自增即全列表重建回读
  // pickCurrentId，与失败 toast 一起构成「没生效」的完整反馈
  @State private switchEpoch: number = 0;
  // 会话行存在性（aboutToAppear 查询落定——三态取 null 判定）：无行 = 懒创建新会话/隐私
  // 会话，pick 不落库只上行覆盖；初值 true = 查询失败走既有落库链（失败有 toast 不静默丢失）
  private rowExists: boolean = true;

  aboutToAppear(): void {
    this.pickCurrentId = this.currentId;
    // 归零防御（面板重进复用宿主同一 scroller 实例；未绑定时静默无效，与原行为同构——
    // scrollToIndex 是 List/Grid/WaterFlow 专属，Scroll 骨架改 scrollTo）
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
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
        if (this.departed) {
          return;
        }
        this.templates = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.templates = [];
        // 失败呈报（SessionMovePanel 同款）：置 hintText 上列表失败行，不静默装「无模板」
        this.hintText = '提示词列表读取失败：' + (e as Error).message;
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

  // 选模板落库（归属恒在不清 assistantId；'' = 清引用回退归属助手提示词）。无行会话跳过
  // 落库、选中值直接上行（ChatPromptState.promptOverride 持有）。落库失败追加纪元自增——
  // 开关弹回真态（见 switchEpoch 注释）
  private pick(promptId: string): void {
    if (!this.rowExists) {
      this.pickCurrentId = promptId;
      this.onPicked(promptId, this.nameOf(promptId));
      return;
    }
    updateConversationPromptId(this.conversationId, promptId)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.pickCurrentId = promptId;
        this.onPicked(promptId, this.nameOf(promptId));
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.switchEpoch++;
        this.getUIContext().getPromptAction().showToast({ message: '提示词应用失败：' + (e as Error).message });
      });
  }

  // 开关切换：打开 = pick 落库（已开另一个时直接切换——pick 写新值即互斥成立，不拒绝不
  // 弹回）；关闭当前 = pick('') 清引用 → 回退**归属助手提示词**
  private onSwitch(promptId: string, toOn: boolean): void {
    if (toOn) {
      this.pick(promptId);
    } else {
      if (this.pickCurrentId === promptId) {
        this.pick('');
      }
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: CARD_SPACING }) {
        // 提示词行（右侧官方开关；ForEach 键含选中态后缀 + 开关纪元——选中变（含自动切换的
        // 前一行）/ 落库失败回弹均键变重建）
        ForEach(this.templates, (row: PromptTemplateRow) => {
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
          .width(CARD_PANEL_WIDTH)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
        }, (row: PromptTemplateRow): string => row.id +
          (this.pickCurrentId === row.id ? '|on' : '') + '@' + this.switchEpoch)
        // 失败行（hintText 非空才挂——SessionMovePanel 空态/失败行同款位次）
        if (this.hintText !== '') {
          Text(this.hintText)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width(CARD_PANEL_WIDTH)
            .padding(16)
        }
        // 尾部透明占位（底部安全区让位——Blank 在 ListItem 下编译 10905201，用 Row）
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
    // 顶对齐（Scroll 默认 Center，内容不满屏时会垂直居中——ConvPickerSheet 同款显式）
    .align(Alignment.Top)
    // ★ 动态模糊生效前提（沉淀「列表类」节）：滚动内容穿透标题栏背后（clip(false) 缺省
    // 裁剪 = 模糊无内容可透——领导实测「顶部没渐变模糊」根因）
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
