// 其他回答面板内容件：轮尾「其他回答」面板的展示层——候选列表（标题 + 预览 + 未完成标 +
// 右勾 + 行尾「删除」键〔危险红字档，二次确认后上行，判定全在控制器〕）与说明/失败/重试块；
// 零裸 SQL、零归组算法（数据与编排在 ChatAnswerCtrl）。形制 = 半模态三件套（规范-半模态
// §1/§3）：HdsNavigation MODAL 壳 + sheetTitleBarOptions 同源标题（勿自绘）+ bindToScrollable
// 滚动感知 + 底部安全区延伸；滚动容器 clip(false)（缺省裁剪会让渐变模糊空转）；容器不设左右
// 边距（卡宽走 CARD_PANEL_WIDTH 三线对齐）；不带 bindSheet——宿主 = ChatPageContent 根 Stack
// （与消息全文面板同一位）。
// 列表机制（规范-列表卡片 §4.6.1）：候选无固定上限 ⇒ List + Repeat.virtualScroll（V2 渲染件
// 同文件，构造处 UIUtils.enableV2Compatibility 桥接 V1 @Link 的数组）；键只写 answerNodeId
// 身份，勾/禁用态走标量 @Param 逐行下发，禁抄 ForEach 纪元键写法。视图唯一事实源 = Content
// @State 的 ChatAnswerView（@Link 直链，本件不装第二套数据）；switching 时所有选项禁用，
// 关闭键不受影响（标题栏关闭键由宿主 onClose 承担）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIUtils } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
 cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING, CARD_RADIUS
} from '../../common/Theme';
import { ChatAnswerChoice } from '../../common/chat/ChatAnswerChoice';
import { ChatAnswerView } from './ChatAnswerCtrl';
import { ConfirmDialog } from './ConfirmDialog';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 列表可视区外预创建缓冲（同会话列表先例值 5）
const ANSWER_LIST_CACHED: number = 5;
// 末行尾部让位（vp；叠加底部安全区，末卡不贴导航条）
const ANSWER_LIST_TAIL_GAP: number = 24;

@Component
export struct ChatAnswerSheet {
  // 面板唯一事实源（Content @State——打开前已由控制器 publish 落定；本件只读不写）
  @Link view: ChatAnswerView;
  // 点选上行（answerNodeId——控制器按同一 U 重算候选后落写；本件不信面板内缓存的 branchId）
  onChoose: (answerNodeId: string) => void = () => {
  };
  // 删除此版本上行（判定全在控制器；本件只做二次确认）
  onDeleteAnswer: (answerNodeId: string) => void = () => {
  };
  // 重试上行（重查候选——失败保留原列表与勾）
  onRetry: () => void = () => {
  };
  onClose: () => void = () => {
  };
  // 底部系统导航条高（尾部占位让位）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 面板内按钮双态族能力位（恒 true = 官方标准外观——行内删除键灰底三件套消费，ChatQuoteSheet 同款）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private scroller: Scroller = new Scroller();
  // 删除确认弹窗（构造在组件成员位——坑7 约束；每次打开重建，照 ChatBranchSheet 先例）
  private confirmCtrl: CustomDialogController | null = null;

  // 删除确认（危险动作先确认再上行）：可删性判定全在控制器 toast 呈报——本件不预判
  private confirmDelete(answerNodeId: string): void {
    if (this.view.switching) {
      return; // 在途闸（与点选共用——在途时写入口一致忽略）
    }
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除此版本',
        message: '该回答与其后的对话将一并删除，删除后不可恢复。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.onDeleteAnswer(answerNodeId);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  build() {
    HdsNavigation() {
      Column() {
        // 说明行（列表上方不随列表滚；固定句：切换回答会切换此后对话）
        Text('切换回答也会切换此后的对话')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
          .margin({ top: 12, bottom: 10 })
        // 读取中提示（重查/重试期；列表与原勾保持不动）
        if (this.view.loading) {
          Text('正在读取回答…')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
            .margin({ bottom: 8 })
        }
        // 失败块（原列表与勾保留 + 重试；错误文案由控制器给）
        if (this.view.errorText !== '') {
          Column({ space: 8 }) {
            Text(this.view.errorText)
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width('100%')
              .textAlign(TextAlign.Start)
            Button('重试')
              .fontSize(14)
              .width('100%')
              .onClick((): void => {
                this.onRetry();
              })
          }
          .width(CARD_PANEL_WIDTH)
          .margin({ bottom: 10 })
        }
        // 候选列表（虚拟化——List 必须 layoutWeight(1) 获得有界视口，不嵌 Scroll 撑开全量）
        ChatAnswerRows({
          choices: UIUtils.enableV2Compatibility(this.view.choices),
          selectedAnswerId: this.view.selectedAnswerId,
          switching: this.view.switching,
          appColorMode: this.appColorMode,
          contentFallback: this.contentFallback,
          immersiveLevel: this.immersiveLevel,
          scroller: this.scroller,
          bottomInset: this.bottomInset,
          onChoose: (answerNodeId: string): void => {
            this.onChoose(answerNodeId);
          },
          onDeleteAnswer: (answerNodeId: string): void => {
            this.confirmDelete(answerNodeId);
          }
        })
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .titleBar(sheetTitleBarOptions('其他回答', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}

// ═══ 回答候选渲染域（同文件 @ComponentV2——V1 壳桥接数组，Repeat 懒加载要求 V2 数据源）═══
// 键只写 answerNodeId；行内显示与事件一律读 ri.item 当前值（禁构造期快照）。
@ComponentV2
struct ChatAnswerRows {
  // 候选数组（桥接见域头注释）
  @Require @Param choices: ChatAnswerChoice[];
  // 当前勾（屏幕已加载分支算出的当前末正文——不是库 isActive；标量 @Param 逐行下发）
  @Param selectedAnswerId: string = '';
  // 切换在途（true = 所有选项禁用，防写入期间第二次点选）
  @Param switching: boolean = false;
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 按钮双态族能力位（壳侧 @StorageProp 透传——删除键灰底三件套消费）
  @Param contentFallback: boolean = true;
  // 沉浸光感总档（壳侧 @StorageProp 透传——同上）
  @Param immersiveLevel: number = 0;
  // 滚动控制器（壳侧传入，bindToScrollable 绑定）
  @Param scroller: Scroller = new Scroller();
  // 末行底部让位（壳侧 bottomInset 透传）
  @Param bottomInset: number = 0;
  @Event onChoose: (answerNodeId: string) => void = () => {
  };
  // 删除此版本上行（answerNodeId——壳内二次确认后经 onDeleteAnswer 出件）
  @Event onDeleteAnswer: (answerNodeId: string) => void = () => {
  };

  // 候选行（主区卡 + 行尾删除键兄弟摆位，官方 Button(Normal) 原生按压）。删除键恒渲染、可
  // 删性判定全在控制器——行内无随行变化的可见性成分，零列表键纪律风险（坑44/80）；删除键禁
  // 嵌进卡片 Button 内容区（与整卡 onClick 同拍 = 删除与切换并发写），兄弟节点天然无此问题。
  // 主区卡外包 Column 承三件套 + padding 4（蒙层距卡外圈 4vp）；enabled 留 Button（禁用态
  // 无蒙层，行为不变）
  @Builder
  AnswerRow(ri: RepeatItem<ChatAnswerChoice>) {
    Row({ space: 8 }) {
      Column() {
        Button() {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text('回答 ' + (ri.index + 1).toString())
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                if (ri.item.incomplete) {
                  Text('未完成')
                    .fontSize(12)
                    .fontColor(cardDescColor())
                }
              }
              .width('100%')
              Text(ri.item.preview)
                .fontSize(13)
                .fontColor(cardDescColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            if (ri.item.answerNodeId === this.selectedAnswerId) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_primary')])
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
        .enabled(!this.switching)
        .onClick((): void => {
          this.onChoose(ri.item.answerNodeId);
        })
      }
      .layoutWeight(1)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(CARD_RADIUS)
      .padding(4)
      // 行尾删除键（危险文字键档：灰底三件套 + 危险红字——ChatQuoteSheet「删除引用」/
      // MountManageCard「移除」先例；行内紧凑取值，不照抄底部整宽档）
      Button('删除')
        .fontSize(14)
        .fontColor($r('app.color.dialog_confirm_red'))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .height(32)
        .padding({ left: 12, right: 12 })
        .enabled(!this.switching)
        .onClick((): void => {
          this.onDeleteAnswer(ri.item.answerNodeId);
        })
    }
    .width(CARD_PANEL_WIDTH)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    List({ space: CARD_SPACING, scroller: this.scroller }) {
      Repeat<ChatAnswerChoice>(this.choices)
        .each((ri: RepeatItem<ChatAnswerChoice>) => {
          ListItem() {
            // 保真层 Column：ListItem 子项不水平居中致卡片整列左偏（2026-09-11 实锤）
            Column() {
              this.AnswerRow(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({
              bottom: ri.index === this.choices.length - 1
                ? this.bottomInset + ANSWER_LIST_TAIL_GAP : 0
            })
          }
        })
        // 键 = answerNodeId（身份唯一；当前勾不塞键——Repeat 无键变重建语义，刷新走 @Param）
        .key((row: ChatAnswerChoice): string => row.answerNodeId)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2）
    .clip(false)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .cachedCount(ANSWER_LIST_CACHED)
    // 嵌套滚动（官例：前向 PARENT_FIRST = 面板先上拉换档，后向 SELF_FIRST = 列表先滚到底
    // 再把手势交回面板）
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }
}
