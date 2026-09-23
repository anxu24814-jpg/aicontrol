// 消息全文半模态面板（2026-09-18 消息复制优化笔）：长按消息气泡弹出的复制面板——
// 单个可选 Text 承载整条消息，选择范围跨段落自由（气泡内逐段渲染的选择困局由
// 「整条文本进面板」根治——Text 选择只能在单组件内跨行，气泡逐段多组件天然不可跨）。
// 面板内容件（不含 bindSheet——宿主 = ChatPageContent 根 Stack，规范-半模态 §1 三级
// 挂点「分支根」；规范-半模态 §8「面板内容件」先例）。形制 = ContextUsageSheet 同款
// 三件套（HdsNavigation MODAL 壳 + sheetTitleBarOptions 5 参规格 + bindToScrollable
// 滚动感知 + 底部安全区延伸），滚动容器 clip(false)（规范 §2——渐变模糊要有内容可透）。
// 内容三件：
// · 分段胶囊（SegmentBar 共用件零参数覆盖）——「纯文本」（去除 md 标记）与「Markdown」
//   （原文）两口径切换，两种内容都可长按选择复制（决明 2026-09-18「分段胶囊切换去除
//   md 标记与 md 原版两种可复制」）；默认纯文本；
// · 消息文本——单 Text + copyOption(LocalDevice)（官方长按选择，LogPageContent 先例
//   口径：菜单项由系统提供应用无需实现），两口径都整块剔除表格（决明同日口径「表格等
//   先不显示在半模态中」；文本准备单源 = common/MarkdownText.buildCopySheetText）；
// · AI 标识行——助手消息常显「内容由 AI 生成，仅供参考」（《标识办法》界面呈现义务；
//   文案单源 common/AiDisclosure）。★ 与旧复制键的后缀标识差异：系统选择复制无法在
//   拷贝动作上后写标识，本面板以「面板内常显标识行」承担显式标识义务（口径变化登记
//   变更记录）。
// ★ 2026-09-18 吸底键笔（决明「底部可否加吸底键，不随内容滚动，内容可滚出下面，点键
// 即复制全文进剪贴板」）：底部加「复制全文」吸底键条——形制 = KimiFullInputSheet 同款
// （Stack 底对齐叠〔Scroll 全高 + 底部渐变蒙层 + 键带〕：键不随内容滚动，内容从键带
// 之后滚出、经蒙层渐隐穿过；Scroll 尾占位 = 蒙层高，滚到底末行停在蒙层上方——二一九改
// 教训「底部不能显示在按钮上」）。键动作 = 按当前口径整条写入剪贴板（显示文本单源
// displayText），助手消息附显式标识（withAiContentLabel——退役底栏复制键/渲染器复制
// 回调同口径，《标识办法》复制带走的 AI 生成内容须带标识；用户消息原文不带）；长按
// 选择复制路径照旧（系统菜单无法在拷贝动作上后写标识，该路径标识义务仍由面板常显
// 标识行承担）。
// 数据 = 快照语义（长按一刻的 msg.text 拷入宿主 @State，流式增量不跟进——面板职责是
// 复制一段定稿文字，非实时阅读；★ 同日流式闸笔：生成中消息入口两层守卫静默不弹，面板
// 只对停止/收口后的消息可达，本件内零闸代码）；text 普通成员快照传入（SheetHost 快照
// 参数先例 ModelPickerSheet.selProviderId）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, pageBgFade, SEGMENT_BAR_HEIGHT } from '../../common/Theme';
import { AI_CONTENT_LABEL, withAiContentLabel } from '../../common/AiDisclosure';
import { buildCopySheetText } from '../../common/MarkdownText';
import { SegmentBar } from '../SegmentBar';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 底部渐隐蒙层高（vp，★ 单源：蒙层与 Scroll 尾占位同用「本值 + 安全区」，一处改两处同效）：
// 键带基高 64（上 12 + 键 40 + 下 12）+ 26vp 渐隐余量 = KimiFullInputSheet 90vp 沉淀同款
const COPY_BOTTOM_FADE_HEIGHT: number = 90;

@Component
export struct MessageCopySheet {
  // 消息全文快照（长按一刻的 msg.text；普通成员——快照语义，流式增量不跟进，见头注释）
  text: string = '';
  // 助手消息（true = 显示 AI 标识行；用户消息不带）
  fromAssistant: boolean = false;
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主 bottomPad 注入——吸底键带与蒙层/尾占位的安全区让位）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区回退开关（吸底键四件套双态驱动——KimiFullInputSheet 同款；2026-09-18 吸底键笔）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 口径分段（0 = 纯文本默认 / 1 = Markdown 原文；下标↔口径映射与 displayText 同源）
  @State private modeIdx: number = 0;
  // 分段选项（顺序 = 下标↔口径映射，勿单独乱调）
  private modeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '纯文本' },
    { text: 'Markdown' }
  ]);
  private scroller: Scroller = new Scroller();

  // 面板展示文本（口径单点 = buildCopySheetText：纯文本去表格 + 剥标记 / Markdown 只去
  // 表格——决明「表格等先不显示在半模态中」；吸底键复制同源本函数）
  private displayText(): string {
    return buildCopySheetText(this.text, this.modeIdx === 0);
  }

  // 蒙层与 Scroll 尾占位高度（含底部安全区——键带底 padding 让位同源值）
  private bottomFadeHeight(): number {
    return COPY_BOTTOM_FADE_HEIGHT + this.bottomInset;
  }

  // 复制全文（吸底键动作）：写剪贴板姿势照 CubeMarkdownView.copyWithAiLabel/ModelEditPage
  // 先例；助手消息附显式标识（withAiContentLabel）。空文本守卫 = 消息只含表格/图片时
  // 段落被整块剔空（buildCopySheetText 表→''）——静默复制空串等于假成功，显式提示
  // （P0-1）；成功 toast「已复制」，失败 hilog + toast 两头可见（显式入口无组件自带反馈）
  private copyAll(): void {
    const payload: string = this.displayText();
    if (payload === '') {
      this.getUIContext().getPromptAction().showToast({ message: '当前消息没有可复制的文字' });
      return;
    }
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
      this.fromAssistant ? withAiContentLabel(payload) : payload);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    }).catch((e: Object): void => {
      hilog.error(0xD5A0, 'MsgCopySheet', '复制全文失败：%{public}s', (e as Error).message);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
    });
  }

  build() {
    HdsNavigation() {
      // 吸底键条层（2026-09-18 吸底键笔）：Stack 底对齐叠〔Scroll 全高 + 底部渐变蒙层 +
      // 键带〕——KimiFullInputSheet 二一四/二一九改同款形制（键不随滚动、内容滚出到键后）
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            // 口径分段胶囊（SegmentBar 官方组件宽度 = 父容器宽，外层包 CARD_PANEL_WIDTH
            // 约束——ProviderKeysPanel 取钥胶囊同款）
            Column() {
              SegmentBar({
                items: this.modeItems,
                selectedIndex: $modeIdx
              })
            }
            .width(CARD_PANEL_WIDTH)
            .height(SEGMENT_BAR_HEIGHT)
            // 消息全文（单个可选 Text——跨段落选择的载体；LocalDevice = 设备内应用间
            // 复制粘贴，LogPageContent/AttachmentViewer 同口径）
            Text(this.displayText())
              .fontSize(15)
              .lineHeight(22)
              .fontColor(cardTitleColor())
              .textAlign(TextAlign.Start)
              .width(CARD_PANEL_WIDTH)
              .copyOption(CopyOptions.LocalDevice)
            // AI 显式标识行（助手消息常显——界面呈现义务；用户消息不带）
            if (this.fromAssistant) {
              Text(AI_CONTENT_LABEL)
                .fontSize(12)
                .fontColor(cardDescColor())
                .width(CARD_PANEL_WIDTH)
            }
            // 尾部占位 = 蒙层高（含安全区，★ 与蒙层同源 bottomFadeHeight）：滚到底末行停在
            // 蒙层上方完整可见，滚动过程中文本仍从键带之后渐隐穿过；Row 空占位——Blank 在
            // 部分容器下编译 10905201，规范-半模态 §2 先例用 Row
            Row()
              .height(this.bottomFadeHeight())
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

        // 底部渐变蒙层（纯色梯度沉淀 = KimiFullInputSheet 二一五改定稿——上透下实 /
        // pageBgFade 深浅分治 / hitTestBehavior(None) 不拦滚动与文本长按选择，二一六改同款）
        Column()
          .width('100%')
          .height(this.bottomFadeHeight())
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 底部吸底键带（条透明——键自身四件套承担实底/光感两态，无背后蒙层材料；
        // hitTestBehavior(Transparent) = 条面不阻断下层滚动（09-04 悬浮键死区教训：
        // 透明容器走 Default 仍拦下层手势），键本体响应不衰减）
        Column() {
          Row() {
            // 「复制全文」= 主操作（官方强调蓝 + font_on_primary 恒白；内容区回退双态
            // = fallbackButton* 四件套，KimiFullInputSheet 发送键同款形制）
            Button('复制全文')
              .width('100%')
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                this.copyAll();
              })
          }
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        // 单一 padding（ArkUI 同属性后设覆盖——KimiFullInputSheet 二一五改教训）
        .padding({ top: 12, bottom: this.bottomInset + 12 })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(sheetTitleBarOptions('消息全文', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
