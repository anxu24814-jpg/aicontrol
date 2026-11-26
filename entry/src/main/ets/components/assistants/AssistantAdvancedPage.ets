// 助手高级设定二级页：编辑页「高级设定」分区卡 push 进入，param = 助手 id。
// · 页面形态：PageShell 自包壳（助手域各页同款）+ 两张行卡（icon + 标题 + 副行摘要）：
//   「采样参数」（thermometer——SDK 符号表实锤）→ 三级页 AssistantSamplingPage（四开关
//   卡：覆盖温度/Top P/双惩罚）；「上下文与输出」（text_alignleft）→ 三级页
//   AssistantContextPage（上下文消息数/最大输出长度两滑块卡）。
// · 副行摘要（DB 单一真源）：采样 = '默认'/'已覆盖 N 项'（四采样键开启数）；上下文 =
//   '不限制 · 不限制'/'20 条 · 64K'（formatTokenText 缩写；输出侧与上下文侧统一为
//  「不限制」）。三级页保存返回经 onPop 重拉（三级页无改动无参 pop 不触发——摘要无需
//   刷新，坑17 契约）。
// · 返回 = onBackPressed 拦截 pop({saved:true})（本页无保存动作的完成返回——触发编辑页
//   onPop 刷「高级设定」卡摘要；未改动返回 reload 幂等无害）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  ROUTE_ASSISTANT_ADVANCED_PAGE, ROUTE_ASSISTANT_CONTEXT_PAGE, ROUTE_ASSISTANT_SAMPLING_PAGE
} from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import {
  AssistantAdvancedParams, parseAssistantAdvancedParams
} from '../../common/providers/AiTypes';
import { queryAssistant } from '../../common/store/AssistantDb';
import { formatTokenText } from './AssistantContextPage';

// 二级页摘要快照（两行卡副行展示；@State 驱动卡面重建）
interface AdvancedSummary {
  samplingText: string;
  contextText: string;
}

@Component
export struct AssistantAdvancedPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id，编辑页传入）
  private rowId: string = '';
  @State private summary: AdvancedSummary = { samplingText: '', contextText: '' };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条）：string id（空/缺参 = 异常路径弹回）
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_ADVANCED_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    this.refreshSummary();
  }

  // 摘要重读（DB 单一真源；三级页 onPop / 进页调用；读取失败 toast 不静默 P0-1）
  private refreshSummary(): void {
    queryAssistant(this.rowId)
      .then((row): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          return; // 助手已删（异常路径）——保留当前摘要不炸链路
        }
        const parsed: AssistantAdvancedParams | null =
          parseAssistantAdvancedParams(row.advancedParams);
        let samplingText: string = '默认';
        let contextText: string = '不限制 · 不限制';
        if (parsed !== null) {
          const count: number =
            (parsed.temperature !== undefined ? 1 : 0) + (parsed.topP !== undefined ? 1 : 0) +
            (parsed.presencePenalty !== undefined ? 1 : 0) +
            (parsed.frequencyPenalty !== undefined ? 1 : 0);
          if (count > 0) {
            samplingText = '已覆盖 ' + count + ' 项';
          }
          const ctx: number = parsed.contextCount ?? 0;
          const out: number = parsed.maxOutput ?? 0;
          contextText = (ctx === 0 ? '不限制' : ctx + ' 条') + ' · ' +
            (out === 0 ? '不限制' : formatTokenText(out));
        }
        this.summary = { samplingText: samplingText, contextText: contextText };
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '高级设定摘要读取失败：' + (e as Error).message });
      });
  }

  // 三级页跳转（onPop 重拉摘要——子页保存 pop 必带 result 坑17 契约）
  private openSamplingPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_SAMPLING_PAGE, this.rowId, (): void => {
      this.refreshSummary();
    });
  }

  private openContextPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_CONTEXT_PAGE, this.rowId, (): void => {
      this.refreshSummary();
    });
  }

  // 采样参数行卡（★ 无参 @Builder 内直读 this.summary——坑16 值参快照不自刷）。
  // ★ 蒙层边距统一：卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp（与组卡口径一致；
  // 下同，两卡同笔）
  @Builder
  SamplingCard() {
    Column() {
      Button() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.thermometer'))
            .fontSize(20)
            .fontColor([cardTitleColor()])
          Column({ space: 4 }) {
            Text('采样参数')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width('100%')
            Text(this.summary.samplingText)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openSamplingPage();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 上下文与输出行卡（形制同上）
  @Builder
  ContextCard() {
    Column() {
      Button() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.text_alignleft'))
            .fontSize(20)
            .fontColor([cardTitleColor()])
          Column({ space: 4 }) {
            Text('上下文与输出')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width('100%')
            Text(this.summary.contextText)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openContextPage();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        this.SamplingCard()
        this.ContextCard()
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
      title: '高级设定',
      // 右上角无菜单键（纯导航枢纽）；完成返回带 result——编辑页 onPop 刷「高级设定」
      // 卡摘要（坑17「无保存动作」姿势；未改动返回 reload 幂等无害）
      onBackPressed: (): boolean => {
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
