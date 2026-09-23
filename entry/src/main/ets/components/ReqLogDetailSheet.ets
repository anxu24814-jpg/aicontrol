// 「请求日志」详情半模态面板（2026-09-23 请求日志笔）：
// 面板内容件（**不含 bindSheet**——宿主 = ReqLogPage 页面根，规范-半模态 §1 挂点「页面根」、
// §8「面板内容件」先例）。形制照 MessageCopySheet 同款三件套（HdsNavigation MODAL 壳 +
// sheetTitleBarOptions + bindToScrollable 滚动感知 + 底部安全区延伸 + 滚动容器 clip(false)）。
//
// 内容五段（响应头 / 请求体 / 错误三卡条件渲染）：概览卡（来源 / 模型 / 时间 / 方法 / URL /
// 状态 / 建议 / 耗时 / 首字节 / 请求体长度）· 请求头卡 · 响应头卡 · 请求体卡 · 错误卡（错误
// 信息 + 错误响应体尾部）。长文本一律
// copyOption(CopyOptions.LocalDevice) 长按可选；请求头与请求体两卡各配一个「复制」键——
// 报障时把整段请求粘给别人看是本功能最常见的用法，长按选择对整段长文本太费事。
//
// 数据 = **快照语义**（点行一刻的条目拷入宿主 @State 传入，面板打开期间后台回填不跟进）：
// 面板职责是看这一次请求的定稿现场，不是实时监视（MessageCopySheet 同款口径）。
// 纯展示面板，**不加关闭确认**（规范-半模态 §1「纯信息展示的面板不加确认」）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  CONTENT_FALLBACK_KEY,
  IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg,
  fallbackButtonFont,
  fallbackButtonMaterial,
  fallbackButtonStateEffect
} from '../common/ImmersiveLevel';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH } from '../common/Theme';
import { emptyReqLogEntry, REQ_LOG_HEADERS_MAX_CHARS, ReqLogEntry, reqLogAdvice,
  reqLogDurationText, reqLogFullTimeText, reqLogHasMask, reqLogStatusText } from '../common/ReqLog';
import { sheetTitleBarOptions } from './chat/KimiSheetCommon';

const DOMAIN: number = 0xD5A0;
const TAG: string = 'ReqLogSheet';

@Component
export struct ReqLogDetailSheet {
  // 条目快照（点行一刻；普通成员——快照语义，见头注释）
  entry: ReqLogEntry = emptyReqLogEntry();
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主注入——滚动尾占位让位，内容不被手势条压住）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区回退开关（复制键四件套双态驱动——KimiFullInputSheet / MessageCopySheet 同款）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  private scroller: Scroller = new Scroller();

  // 复制一段文本（请求头 / 请求体两卡共用）：姿势照 MessageCopySheet.copyAll——写剪贴板
  // then/catch 两头可见，空串守卫不静默成功（P0-1）
  private copyText(payload: string, label: string): void {
    if (payload === '') {
      this.getUIContext().getPromptAction().showToast({ message: label + '为空，没有可复制的内容' });
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, payload);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    }).catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '复制失败：%{public}s', (e as Error).message);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
    });
  }

  // 键值行（概览卡用；值可长按选择复制）
  @Builder
  InfoLine(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(60)
      Text(value)
        .fontSize(13)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // 文本段卡（请求头 / 请求体 / 错误体三卡共用：标题行 + 复制键 + 等宽长文本）
  @Builder
  TextSection(title: string, payload: string, hint: string) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Blank()
        // 复制键（内容区组件走 fallbackButton* 双态——ProviderModelsPanel 同款形制）
        Button('复制')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.copyText(payload, title);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(payload)
        .fontSize(13)
        .lineHeight(20)
        .fontColor(cardTitleColor())
        .textAlign(TextAlign.Start)
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
      if (hint !== '') {
        Text(hint)
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  // 排查建议（纯函数在 ReqLog.reqLogAdvice——面板只做呈现；@Builder 内不声明本地量，
  // 故经本方法取用一次）
  private adviceText(): string {
    return reqLogAdvice(this.entry.status, this.entry.respHeadersText);
  }

  // 概览卡（一次请求的全部元数据）
  @Builder
  OverviewCard() {
    Column({ space: 6 }) {
      this.InfoLine('来源', this.entry.source)
      // 模型名（2026-09-23 扩充笔）：拉模型清单这类不针对模型的请求为空，显示「—」
      this.InfoLine('模型', this.entry.model !== '' ? this.entry.model : '—')
      this.InfoLine('时间', reqLogFullTimeText(this.entry.at))
      this.InfoLine('请求', this.entry.method + ' ' + this.entry.url)
      this.InfoLine('状态', reqLogStatusText(this.entry.status))
      // 归因行（有建议才出）：抓包工具假设使用者懂 HTTP，本页面向的是把 key 粘进来的普通
      // 用户——「这条报错是什么意思」在这里就地回答
      if (this.adviceText() !== '') {
        this.InfoLine('建议', this.adviceText())
      }
      this.InfoLine('耗时', reqLogDurationText(this.entry.durationMs) !== '' ?
        reqLogDurationText(this.entry.durationMs) : '—')
      // 首字节（只在流式链有值——非流式链首字节即总时长，记了无意义；见 common/ReqLog.ets
      // 文件头扩充笔第二条）。与总耗时并排看才能分辨「连不上」与「连上了但半天不出字」
      if (this.entry.firstByteMs > 0) {
        this.InfoLine('首字节', reqLogDurationText(this.entry.firstByteMs))
      }
      this.InfoLine('请求体', this.entry.bodyLength > 0 ? this.entry.bodyLength + ' 字符' : '无')
      // 打码提示（有打码痕才出）：用户看到 ab••••cd 需要一个就地解释，否则会以为密钥坏了
      if (reqLogHasMask(this.entry)) {
        Text('密钥等敏感内容已自动打码')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          this.OverviewCard()
          // 请求头（已掩码——掩码在写入日志时完成，本面板只展示，见 common/ReqLog.ets）。
          // 截断提示：头文本不存原长字段，改用**上限关系**判定——clipText 的截断产物恒为
          // 「前 N + '…'」= N+1 字符，故「长于上限」即「被截断」；恰好等于上限则未截断
          this.TextSection('请求头', this.entry.headersText,
            this.entry.headersText.length > REQ_LOG_HEADERS_MAX_CHARS ?
              '已截断，请求头过长或过多' : '')
          // 响应头（2026-09-23 扩充笔；**白名单**——只记排障要的几类，见 common/ReqLog.ets
          // 「响应头白名单」节）。空串 = 本条没命中白名单头，不渲染此卡
          if (this.entry.respHeadersText !== '') {
            this.TextSection('响应头', this.entry.respHeadersText,
              this.entry.respHeadersText.length > REQ_LOG_HEADERS_MAX_CHARS ?
                '已截断，响应头过多' : '')
          }
          // 请求体（超长已截断；截断提示只在真发生截断时出现）。空体不渲染此卡——概览卡已
          // 写「请求体 无」，同屏再摆一张空卡是重复且与错误卡「为空即不显」的同件口径相抵
          if (this.entry.bodyText !== '') {
            this.TextSection('请求体', this.entry.bodyText,
              this.entry.bodyLength > this.entry.bodyText.length ?
                '已截断，原文共 ' + this.entry.bodyLength + ' 字符' : '')
          }
          // 错误卡（错误信息或错误响应体尾部任一非空即出）
          if (this.entry.error !== '' || this.entry.responseTail !== '') {
            this.TextSection('错误响应', this.entry.responseTail !== '' ?
              this.entry.responseTail : this.entry.error,
              this.entry.error !== '' && this.entry.responseTail !== '' ? this.entry.error : '')
          }
          // 尾部占位 = 底部手势条让位（内容滚到底不被系统导航条压住）
          Row()
            .height(this.bottomInset + 12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('请求详情', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
