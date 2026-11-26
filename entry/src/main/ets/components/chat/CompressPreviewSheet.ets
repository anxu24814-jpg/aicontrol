// 压缩预览半模态：三态面板内容件（不含 bindSheet——宿主 ChatPage 页面根唯一挂载点
// sheetKind='compress' 分支，坑64 姿势；壳与档位照 ContextUsageSheet 写法）。三态：
// 生成中 / 预览（摘要正文可编辑 + 补充要求单行输入 + 采用/放弃）/ 失败（错误文案 +
// 重试键，关掉即零副作用）。
// ★ 关闭流程外移单源：关闭键与「放弃」键不自弹确认，统一上行 onRequestClose 交宿主压缩
//   接线域（ChatCompressCtrl.requestClose）据「在途/有草稿」分态确认（在途态确认即真中断
//   cancelCompressDraft）；宿主手势与系统返回同入口；草稿态经 onDraftState 上行供其选文案。
// ★ 「重新生成」键常显（S13 改判）：原「补充要求非空才渲染」令采用失败后的恢复动作不可
//   达；无补充要求时 = 同输入再生成一份，只本次有效不落库（插槽语义）。
// ★ fail-open 纪律：放弃/关闭/失败三路零副作用——生成结果只存本组件 @State，落库唯一
//   路径 = 「采用」键（adoptGraphSummary，经 onAdopted 上行宿主收口）。
// ★ S1/A-4：采用前的会话态读口失败不得静默折成 legacy（会话在图态按 legacy 采用会写与
//   图路径分叉的摘要）——保预览态 + 错误小字 + 采用键置灰（不切失败态，草稿须可达可编辑
//   可复制），复位唯一挂点 = 重新生成（采用前置条件重来）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AiConnection } from '../../common/providers/AiTypes';
import {
  COMPRESS_STATUS_BUSY, COMPRESS_STATUS_CANCELLED, COMPRESS_STATUS_CONFIG,
  COMPRESS_STATUS_INSUFFICIENT, COMPRESS_STATUS_READY,
  COMPRESS_STATUS_SKIPPED, COMPRESS_STATUS_TOO_LONG, generateCompressDraft,
  CompressDraftResult
} from '../../common/CompressGen';
import { adoptGraphSummary } from '../../common/chat/ChatGraphCommandSource';
import { conversationGraphBranch, readPathSummaryInput,
  RequestSummaryInput } from '../../common/chat/ChatContextSource';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { ChatMessage } from './ChatMessageCompose';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { readRequestHistoryRows, RequestHistoryReadResult }
  from '../../common/chat/RequestHistorySource';
import { resolveReadRows } from '../../common/chat/RequestHistoryBudget';
import { chatMessagesFromRows } from './ChatMessageProjection';
import { REQUEST_HISTORY_DECOUPLE_ENABLED } from '../../common/Theme';

// 生成输入供给（宿主闭包注入——ChatPage 只给最薄取值口，面板自持三态与草稿，子域不反向
// import 宿主）。clipLimit = 压缩素材读口预算（与实发同口径）；可选字段，宿主未注入时
// 缺省 0 =「不限制」（读口取硬上限，fail-open 宁多带不误删）
export interface CompressSheetRefs {
  conversationId: () => string;
  allMessages: () => ChatMessage[];
  conn: () => AiConnection | null;
  clipLimit?: () => number;
}

const PHASE_GENERATING: string = 'generating';
const PHASE_PREVIEW: string = 'preview';
const PHASE_FAILED: string = 'failed';

@Component
export struct CompressPreviewSheet {
  refs: CompressSheetRefs = {
    conversationId: (): string => '',
    allMessages: (): ChatMessage[] => [],
    conn: (): AiConnection | null => null,
    clipLimit: (): number => 0
  };
  // 关闭请求（标题栏关闭键 / 底部「放弃」键两路——转交宿主统一确认与收口，见文件头）
  onRequestClose: () => void = () => {
  };
  // 草稿态上行（预览态且正文非空 = true）：宿主手势关闭时据此选确认文案；销毁上行 false
  onDraftState: (hasDraft: boolean) => void = () => {
  };
  // 采用在途上行（S13）：宿主据此拦关闭——在途窗口内放弃并确认后落库链仍会把摘要落库
  //（破「放弃后不会保存任何内容」承诺）；面板销毁不额外上行 false（在途时宿主已拦关
  // 不销毁；页面整体销毁属存量边界）
  onAdoptState: (adopting: boolean) => void = () => {
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
  // 采用在途闸（S7 面板层）：置位在发起落库前同步完成（不依赖重渲染），「采用」键按它
  // 置灰 + adopt() 入口早退断双击第二发；收尾三路统一由链尾 .finally 复位——漏复位即键
  // 永久置灰、草稿成死局。域侧另有同会话在途登记（CompressDb.markAdopt）兜底跨实例与迟到路径
  @State private adopting: boolean = false;
  // 边界节点 id（graph 采用核验锚——生成结果透传，'' = 无）
  private boundaryNodeId: string = '';
  @State private errorText: string = '';
  // 态读失败标记（A-4）：置位保预览态（草稿可达）+ 错误小字 + 采用键置灰（本会话不采用）；
  // 复位唯一挂点 = startGeneration 首段（重新生成 = 采用前置条件重来，下次采用重新读态）
  @State private routeFailed: boolean = false;
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
    // 态读失败复位（A-4）：重新生成 = 采用前置条件重来，下次采用重新读态——不复位则
    // 采用键永久置灰成死局
    this.routeFailed = false;
    this.errorText = '';
    this.onDraftState(false);
    // 边界库直查：压缩起点 = 最新边界之后，与请求组装侧、用量面板同源（readPathSummaryInput
    // 单一读口）；边界值是「库行 seq」坐标系，与选段行的 rowSeq 同源可比。
    // 素材源（请求历史解耦）：解耦开 = 读口预算内全段（与实发同读口同预算，更早历史可压，
    // 读口失败降级窗口旧口径）；解耦关 = 窗口旧口径
    readPathSummaryInput(this.refs.conversationId())
      .then((pathBoundary: RequestSummaryInput | null): Promise<CompressDraftResult> => {
        if (!REQUEST_HISTORY_DECOUPLE_ENABLED) {
          return generateCompressDraft(this.refs.conversationId(), this.refs.allMessages(),
            this.refs.conn(), this.supplement, pathBoundary);
        }
        return conversationGraphBranch(this.refs.conversationId())
          .then((branchId: string): Promise<RequestHistoryReadResult> =>
            readRequestHistoryRows(this.refs.conversationId(), branchId,
              resolveReadRows(this.refs.clipLimit !== undefined ?
                this.refs.clipLimit() : 0), null))
          .catch((_e: Object): null => null)
          .then((read: RequestHistoryReadResult | null): Promise<CompressDraftResult> =>
            generateCompressDraft(this.refs.conversationId(),
              read !== null ? chatMessagesFromRows(read.rows) : this.refs.allMessages(),
              this.refs.conn(), this.supplement, pathBoundary));
      })
      .then((result: CompressDraftResult): void => {
        if (this.disposed || result.status === COMPRESS_STATUS_CANCELLED) {
          return; // 面板已关（用户停止本次压缩）——结果无处可去（落库唯一路径是「采用」）
        }
        if (result.status === COMPRESS_STATUS_READY) {
          this.draftText = result.summaryText;
          this.coversToSeq = result.coversToSeq;
          this.boundaryNodeId = result.boundaryNodeId ?? '';
          this.phase = PHASE_PREVIEW;
          this.syncDraftState();
          return;
        }
        this.errorText = this.failureText(result);
        this.phase = PHASE_FAILED;
        this.syncDraftState();
      });
  }

  // 草稿态上行（phase 变化与草稿编辑两处调用；判据 = 预览态且正文非空——正文改空后
  // 关闭无需再确认）
  private syncDraftState(): void {
    this.onDraftState(this.phase === PHASE_PREVIEW && this.draftText.trim() !== '');
  }

  // 失败文案（既有错误映射风格；域件带回的 errorMessage 已是中文）
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
      // 同会话上一次生成仍在途：面板关闭三路都会释放在途位，本态来自未走关闭确认的收尾
      //（页面销毁等）——不能报成「会话未就绪」误导用户去查库/会话态
      return '上一次生成还在进行，稍等片刻再试';
    }
    return result.errorMessage !== '' ? result.errorMessage : '压缩生成失败，请重试';
  }

  // 采用（唯一落库触发）：空摘要拦下；成功上行宿主收口（追加流内提示行、刷新用量、关
  // 面板）；失败只 toast 不关面板（草稿还在，可重试采用）。graph 会话走 adoptGraphSummary
  //（边界节点核验 + 摘要节点挂尾 + binding 同事务，K9/K4）；无分支（旧格式墓碑/坏库态）
  // fail-closed 拒用呈报
  private adopt(): void {
    if (this.adopting) {
      return; // 双击第二发：第一发的落库尚未收尾（域侧同会话在途闸另有一道，见字段注释）
    }
    const text: string = this.draftText.trim();
    if (text === '') {
      this.getUIContext().getPromptAction().showToast({ message: '摘要为空，请编辑后再采用' });
      return;
    }
    const boundaryNodeId: string = this.boundaryNodeId;
    const convId: string = this.refs.conversationId();
    // 态读失败标记（S1）：态读不出来时不采用且面板呈报——见 catch 注释
    let routeReadFailed: boolean = false;
    this.adopting = true;
    this.onAdoptState(true); // 在途上行（S13）：宿主据此拦关闭，「放弃不保存」承诺成立
    conversationGraphBranch(convId)
      .catch((e: Object): string => {
        // 态读失败不得静默折成 legacy（会写与图路径分叉的摘要——用户以为压了实际没压）：
        // 置 routeFailed 面板呈报并禁采用，草稿编辑不复位（失败是「采用时态读」的事），
        // 口径见文件头 S1/A-4 条
        routeReadFailed = true;
        this.routeFailed = true;
        this.errorText = '会话状态读取失败，' + (e as Error).message;
        this.syncDraftState();
        return '';
      })
      .then((branchId: string): Promise<string> => {
        if (routeReadFailed) {
          return Promise.resolve('');
        }
        if (branchId !== '') {
          return adoptGraphSummary(convId, branchId, text, this.coversToSeq, boundaryNodeId);
        }
        // legacy 采用支已随线性写路径退役——无分支（旧格式墓碑/坏库态）fail-closed 拒用
        // 呈报（文案单源 ChatBranchPolicy），草稿留在面板可重试
        this.getUIContext().getPromptAction().showToast({ message: TOMBSTONE_TOAST_TEXT });
        return Promise.resolve('');
      })
      .then((rowId: string): void => {
        if (routeReadFailed || rowId === '') {
          return; // 拒用分支：无采用可收口（已呈报）
        }
        this.onAdopted(rowId, text, this.coversToSeq);
      })
      .catch((e: Object): void => {
        // 采用失败与态读失败分治：采用失败保住预览态（草稿还在，可重试采用），只 toast
        this.getUIContext().getPromptAction().showToast({
          message: '采用失败：' + (e as Error).message });
      })
      .finally((): void => {
        // 收尾复位（成对纪律，见 adopting 字段注释）——漏复位即采用键永久置灰、草稿死局
        this.adopting = false;
        this.onAdoptState(false); // 在途镜像复位（S13：与置位同拍成对）
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
            .borderRadius(CARD_RADIUS)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Center)
          } else if (this.phase === PHASE_PREVIEW) {
            // 预览：摘要正文（可编辑，初值 = 生成结果）+ 补充要求 + 常显「重新生成」（S13，
            // 见文件头）+ 底部双键
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
            .borderRadius(CARD_RADIUS)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
            // 态读失败错误小字（A-4）：预览态内呈报——草稿保可达（可编辑/可复制/可重新
            // 生成带走），采用键置灰；照面板既有错误行形制
            if (this.routeFailed) {
              Text(this.errorText)
                .fontSize(14)
                .fontColor(cardDescColor())
            }
            Column({ space: 10 }) {
              TextInput({ text: this.supplement, placeholder: '补充要求（可选）' })
                .width('100%')
                .onChange((value: string): void => {
                  this.supplement = value;
                })
              // 常显（S13，口径见文件头）；在途采用时置灰（生成与采用并发会互相拆台）
              Text('补充要求只影响本次生成，不保存。对结果不满意可重新生成')
                .fontSize(12)
                .fontColor(cardDescColor())
              Button('重新生成')
                .width('100%')
                .fontColor(fallbackButtonFontTinted(this.contentFallback))
                .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
                .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .enabled(!this.adopting)
                .onClick((): void => {
                  this.startGeneration();
                })
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .borderRadius(CARD_RADIUS)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
            // 底部双键：左「放弃」次钮（走宿主确认流程）+ 右「采用」主操作键（true 档 =
            // 官方强调蓝恒白字）。S13：在途采用时放弃键置灰——防确认放弃后落库链仍把摘要
            // 写进去（「放弃后不会保存任何内容」承诺被破）
            Row({ space: 10 }) {
              Button('放弃')
                .fontColor(fallbackButtonFont(this.contentFallback, false))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .enabled(!this.adopting)
                .layoutWeight(1)
                .onClick((): void => {
                  this.onRequestClose();
                })
              Button('采用')
                .fontColor(fallbackButtonFont(this.contentFallback, true))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .enabled(!this.adopting && !this.routeFailed) // 态读失败置灰（A-4）：本会话不采用
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
            .borderRadius(CARD_RADIUS)
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
