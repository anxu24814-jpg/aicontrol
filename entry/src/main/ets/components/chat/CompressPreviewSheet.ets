// 压缩预览半模态（2026-09-23 上下文压缩，任务书-上下文压缩-20260923 §3.2）：三态面板
// 内容件（不含 bindSheet——宿主 ChatPage 页面根唯一挂载点 sheetKind='compress' 分支，坑64
// 姿势；规范-半模态 §8「面板内容件」先例，壳与档位照 ContextUsageSheet 写法）。
// 三态：生成中（LoadingProgress + 一句「正在整理上下文…」）/ 预览（摘要正文可编辑 +
// 补充要求单行输入 + 采用/放弃）/ 失败（错误文案 + 重试键，关掉即零副作用）。
// ★ 关闭流程（2026-09-23 修复笔外移单源）：关闭键与「放弃」键不再自弹确认，统一上行
//   onRequestClose 交宿主压缩接线域（ChatCompressCtrl.requestClose）——它据「在途/有草稿」
//   分态确认，在途态确认即真中断（CompressGen.cancelCompressDraft），且宿主手势与系统返回
//   走同一入口；面板只把「有无未采用草稿」经 onDraftState 上行供其选文案。
// ★ 补充要求的生效路径（书外补充，偏差已登记变更记录）：生成在开面板时自动发起，预览态
//   才可填补充要求——「拼进提示词插槽」要生效必须有一条重生成路径，故预览态在补充要求
//   非空时出第三键「重新生成」（只本次有效不落库，照任务书 §3.2 插槽语义）。
// ★ fail-open 纪律：放弃/关闭/失败三路零副作用——生成结果只存本组件 @State，落库唯一
//   路径 = 「采用」键（CompressDb.adoptCompressSummary，经 onAdopted 上行宿主后由宿主收口）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AiConnection } from '../../common/providers/AiTypes';
import {
  COMPRESS_STATUS_BUSY, COMPRESS_STATUS_CANCELLED, COMPRESS_STATUS_CONFIG,
  COMPRESS_STATUS_FAILED, COMPRESS_STATUS_INSUFFICIENT, COMPRESS_STATUS_READY,
  COMPRESS_STATUS_SKIPPED, COMPRESS_STATUS_TOO_LONG, generateCompressDraft,
  CompressDraftResult
} from '../../common/CompressGen';
import { adoptCompressSummary } from '../../common/store/CompressDb';
import { ChatMessage } from './ChatMessageCompose';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 生成输入供给（宿主闭包注入——ChatPage 只给最薄取值口，本面板自持三态与草稿；
// 照 ChatContextUsageRefs 的「子域不反向 import 宿主」环规避形制。★ 2026-09-23 输出
// 上限治理笔删 advancedParams 供给——压缩上限已脱挂会话助手，改传域件常量）
export interface CompressSheetRefs {
  conversationId: () => string;
  allMessages: () => ChatMessage[];
  conn: () => AiConnection | null;
}

// 三态相位（生成中 / 预览 / 失败）
const PHASE_GENERATING: string = 'generating';
const PHASE_PREVIEW: string = 'preview';
const PHASE_FAILED: string = 'failed';

@Component
export struct CompressPreviewSheet {
  refs: CompressSheetRefs = {
    conversationId: (): string => '',
    allMessages: (): ChatMessage[] => [],
    conn: (): AiConnection | null => null
  };
  // 关闭请求（标题栏关闭键 / 底部「放弃」键两路——转交宿主压缩接线域统一确认与收口，
  // 见文件头「关闭流程外移单源」；面板不再自弹确认）
  onRequestClose: () => void = () => {
  };
  // 草稿态上行（预览态且有非空正文 = true）：宿主手势关闭时据此选确认文案；面板销毁
  // 上行 false（无草稿可丢）
  onDraftState: (hasDraft: boolean) => void = () => {
  };
  // 采用上行（rowId + 摘要正文 + 覆盖边界——宿主负责追加流内提示行、刷新用量、关面板）
  onAdopted: (rowId: string, summaryText: string, coversToSeq: number) => void = () => {
  };
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 三态与草稿（全部本组件自持——放弃即销毁，零副作用由结构保证）
  @State private phase: string = PHASE_GENERATING;
  @State private draftText: string = '';
  @State private supplement: string = '';
  @State private coversToSeq: number = -1;
  @State private errorText: string = '';
  private scroller: Scroller = new Scroller();
  // 销毁闸（迟到结果不写已销毁组件的状态——用户在生成中关掉面板时命中）
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.startGeneration();
  }

  aboutToDisappear(): void {
    // 销毁即无草稿（宿主的关闭确认在面板销毁前已完成，此处只做镜像复位）；生成中的请求
    // 由宿主关闭流程中断（cancelCompressDraft），未经该路的迟到结果凭 disposed 丢弃
    this.disposed = true;
    this.onDraftState(false);
  }

  // 生成发起（开面板自动一次 + 「重新生成」带补充要求再来——同一入口，在途闸在域件）
  private startGeneration(): void {
    this.phase = PHASE_GENERATING;
    this.onDraftState(false);
    generateCompressDraft(this.refs.conversationId(), this.refs.allMessages(),
      this.refs.conn(), this.supplement)
      .then((result: CompressDraftResult): void => {
        if (this.disposed || result.status === COMPRESS_STATUS_CANCELLED) {
          return; // 面板已关（用户停止本次压缩）——结果无处可去（落库唯一路径是「采用」）
        }
        if (result.status === COMPRESS_STATUS_READY) {
          this.draftText = result.summaryText;
          this.coversToSeq = result.coversToSeq;
          this.phase = PHASE_PREVIEW;
          this.syncDraftState();
          return;
        }
        this.errorText = this.failureText(result);
        this.phase = PHASE_FAILED;
        this.syncDraftState();
      });
  }

  // 草稿态上行（phase 变化与草稿编辑两处调用；判据 = 预览态且正文非空——用户把正文改空
  // 后关闭无需再确认）
  private syncDraftState(): void {
    this.onDraftState(this.phase === PHASE_PREVIEW && this.draftText.trim() !== '');
  }

  // 失败文案（既有错误映射风格——不新造文案体；域件带回的 errorMessage 已是中文）
  private failureText(result: CompressDraftResult): string {
    if (result.status === COMPRESS_STATUS_CONFIG) {
      return '模型不可用。请检查服务商与模型配置，或在功能模型页选择上下文压缩模型';
    }
    if (result.status === COMPRESS_STATUS_INSUFFICIENT) {
      return '历史还短，暂时不用压缩';
    }
    if (result.status === COMPRESS_STATUS_TOO_LONG) {
      return '历史太长，本次压不动';
    }
    if (result.status === COMPRESS_STATUS_SKIPPED) {
      return '会话未就绪，请稍后再试';
    }
    if (result.status === COMPRESS_STATUS_BUSY) {
      // 同会话上一次生成仍在途（请求读超时最长 5 分钟）：面板关闭三路都会中断并立即释放在途位，
      // 故本态来自未走关闭确认的收尾（页面销毁等）——不能报成「会话未就绪」（那是库/会话态
      // 问题，用户会去查不该查的地方）
      return '上一次生成还在进行，稍等片刻再试';
    }
    return result.errorMessage !== '' ? result.errorMessage : '压缩生成失败，请重试';
  }

  // 采用（唯一落库触发）：空摘要拦下（采用空摘要无意义）；落库（一次事务插新删旧）成功后
  // 上行宿主收口（追加流内提示行、刷新用量、关面板）——失败 toast 不关面板（草稿还在，
  // 用户可重试采用）
  private adopt(): void {
    const text: string = this.draftText.trim();
    if (text === '') {
      this.getUIContext().getPromptAction().showToast({ message: '摘要为空，请编辑后再采用' });
      return;
    }
    adoptCompressSummary(this.refs.conversationId(), text, this.coversToSeq)
      .then((rowId: string): void => {
        this.onAdopted(rowId, text, this.coversToSeq);
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '采用失败：' + (e as Error).message });
      });
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          if (this.phase === PHASE_GENERATING) {
            // 生成中：加载指示 + 一句说明（关闭键走宿主确认流程，确认即停止本次压缩）
            Column({ space: 12 }) {
              LoadingProgress()
                .width(40)
                .height(40)
              Text('正在整理上下文…')
                .fontSize(14)
                .fontColor(cardDescColor())
            }
            .width(CARD_PANEL_WIDTH)
            .padding(24)
            .borderRadius(16)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Center)
          } else if (this.phase === PHASE_PREVIEW) {
            // 预览：摘要正文（可编辑，初值 = 生成结果）+ 补充要求 + 双键（+ 补充要求非空时
            // 的「重新生成」——见文件头书外补充说明）
            Column({ space: 14 }) {
              Text('摘要正文（可编辑）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(cardTitleColor())
              TextArea({ text: this.draftText, placeholder: '摘要正文' })
                .width('100%')
                .height(220)
                .onChange((value: string): void => {
                  this.draftText = value;
                  this.syncDraftState();
                })
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .borderRadius(16)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
            Column({ space: 10 }) {
              TextInput({ text: this.supplement, placeholder: '补充要求（可选）' })
                .width('100%')
                .onChange((value: string): void => {
                  this.supplement = value;
                })
              Text('补充要求只影响本次生成，不保存。填写后可点重新生成')
                .fontSize(12)
                .fontColor(cardDescColor())
              if (this.supplement.trim() !== '') {
                Button('重新生成')
                  .width('100%')
                  .fontColor(fallbackButtonFont(this.contentFallback, false))
                  .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                  .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                  .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                  .onClick((): void => {
                    this.startGeneration();
                  })
              }
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .borderRadius(16)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
            // 底部双键（左「放弃」次钮 + 右「采用」主操作键 primary=true 官方强调蓝恒白字——
            // 任务书 §3.2；放弃走宿主确认流程）
            Row({ space: 10 }) {
              Button('放弃')
                .fontColor(fallbackButtonFont(this.contentFallback, false))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .layoutWeight(1)
                .onClick((): void => {
                  this.onRequestClose();
                })
              Button('采用')
                .fontColor(fallbackButtonFont(this.contentFallback, true))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .layoutWeight(1)
                .onClick((): void => {
                  this.adopt();
                })
            }
            .width(CARD_PANEL_WIDTH)
            .alignItems(VerticalAlign.Center)
          } else {
            // 失败：错误文案 + 重试键；关掉即零副作用
            Column({ space: 12 }) {
              Text(this.errorText)
                .fontSize(14)
                .fontColor(cardDescColor())
              Divider()
                .strokeWidth(1)
                .color(cardBorderColor(this.appColorMode))
              Button('重试')
                .width('100%')
                .fontColor(fallbackButtonFont(this.contentFallback, true))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .onClick((): void => {
                  this.startGeneration();
                })
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .borderRadius(16)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
          }
          Row()
            .height(this.bottomInset)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('压缩预览', '', (): void => {
      this.onRequestClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
