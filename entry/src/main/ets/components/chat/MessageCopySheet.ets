// 消息全文半模态面板：长按消息气泡弹出的复制面板——单个可选 Text 承载整条消息，选择范围
// 跨段落自由（Text 选择只能在单组件内跨行，气泡逐段多组件天然不可跨——「整条文本进面板」
// 根治）。面板内容件（不含 bindSheet——宿主 = ChatPageContent 根 Stack，规范-半模态「分支
// 根」挂点 +「面板内容件」先例）。形制 = ContextUsageSheet 同款三件套（HdsNavigation MODAL
// 壳 + sheetTitleBarOptions 5 参规格 + bindToScrollable 滚动感知 + 底部安全区延伸），滚动
// 容器 clip(false)（规范 §2——渐变模糊要有内容可透）。内容：
// · 分段胶囊（SegmentBar 共用件）——「纯文本」（去 md 标记，默认）与「Markdown」（原文）
//   两口径切换，都可长按选择复制（决明「两种可复制」）；
// · 消息文本——单 Text + copyOption(LocalDevice)（官方长按选择，菜单项由系统提供应用无需
//   实现），两口径都整块剔除表格（决明口径「表格等先不显示在半模态中」；文本准备单源 =
//   MarkdownText.buildCopySheetText）；
// · AI 标识行——助手消息常显「内容由 AI 生成，仅供参考」（《标识办法》界面呈现义务；系统
//   选择复制无法在拷贝动作上后写标识，显式标识义务由面板常显标识行承担）；
// · 「复制全文」吸底键条（决明「不随内容滚动，点键即复制全文」）：Stack 底对齐叠〔Scroll
//   全高 + 底部渐变蒙层 + 键带〕——键不随内容滚、内容从键带之后滚出经蒙层渐隐穿过；Scroll
//   尾占位 = 蒙层高，滚到底末行停在蒙层上方（「底部不能显示在按钮上」教训）。键动作 = 按
//   当前口径整条写剪贴板（显示文本单源 displayText），助手消息附显式标识（withAiContentLabel
//   ——《标识办法》复制带走的 AI 内容须带标识；用户消息原文不带）；长按选择复制路径标识
//   义务仍由常显标识行承担。
// 数据 = 快照语义（长按一刻的 msg.text 拷入宿主 @State，流式增量不跟进——面板职责是复制
// 一段定稿文字；生成中消息入口两层守卫静默不弹，本件内零闸代码）。
// 正文 Text 挂 editMenuOptions——长按菜单系统项全保留 + 追加「引用」（选中文本原始子串经
// onQuote 上行宿主 acceptQuote；未接线不追加，见 quoteMenu 注释）。
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

// 底部渐隐蒙层高（vp，★ 单源：蒙层与 Scroll 尾占位同用「本值 + 安全区」）= KimiFullInputSheet
// 沉淀同款
const COPY_BOTTOM_FADE_HEIGHT: number = 90;

@Component
export struct MessageCopySheet {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 消息全文快照（长按一刻的 msg.text；普通成员——快照语义，流式增量不跟进，见头注释）
  text: string = '';
  // 助手消息（true = 显示 AI 标识行；用户消息不带）
  fromAssistant: boolean = false;
  onClose: () => void = () => {
  };
  // 引用上行：选中文本原始子串（截断单源 clampQuoteText 在宿主 acceptQuote）。未接线时
  // 菜单不追加「引用」项（防死按钮）；唯一消费方 = ChatPageContent（copy 形态）
  onQuote: ((text: string) => void) | undefined = undefined;
  // 底部系统导航条高（vp，宿主 bottomInset 注入——吸底键带与蒙层/尾占位的安全区让位）
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

  // 面板展示文本（口径单点 = buildCopySheetText：纯文本去表格 + 剥标记 / Markdown 只去表格；
  // 吸底键复制同源本函数）
  private displayText(): string {
    return buildCopySheetText(this.text, this.modeIdx === 0);
  }

  // 「引用」菜单项 id：常量先存勿每击新建（TextMenuItemId.of 返回比对身份）
  private quoteMenuId: TextMenuItemId = TextMenuItemId.of('quote');
  // 长按菜单扩展：系统项全保留 + 追加「引用」（onCreateMenu 返回数组即终菜单）。未接线
  // 不追加；命中后取选区原文上行、return true 拦截默认逻辑。选区 = displayText() 现取现切
  //（modeIdx 两口径，所见即所选，勿缓存）
  private quoteMenu: EditMenuOptions = {
    onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> => {
      if (this.onQuote !== undefined) {
        menuItems.push({ content: '引用', id: this.quoteMenuId });
      }
      return menuItems;
    },
    onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean => {
      if (this.onQuote === undefined || !menuItem.id.equals(this.quoteMenuId)) {
        return false;
      }
      const full: string = this.displayText();
      const start: number = range.start ?? 0;
      const end: number = range.end ?? full.length;
      if (end <= start) {
        return true; // 空区间不触发：吞掉点击，无动作
      }
      // 孤儿代理清理（range 单位 UTF-16，选区劈开代理对时首尾各清半个——一处单点勿两处重复）
      const sel: string = full.substring(start, end)
        .replace(/[\uD800-\uDBFF]$/, '').replace(/^[\uDC00-\uDFFF]/, '');
      this.onQuote(sel);
      return true;
    }
  };

  // 蒙层与 Scroll 尾占位高度（含底部安全区——键带底 padding 让位同源值）
  private bottomFadeHeight(): number {
    return COPY_BOTTOM_FADE_HEIGHT + this.bottomInset;
  }

  // 复制全文（吸底键动作）：助手消息附显式标识（withAiContentLabel）。空文本守卫 = 消息只
  // 含表格/图片时段落被整块剔空——静默复制空串等于假成功，显式提示（P0-1）；成功 toast，
  // 失败 hilog + toast 两头可见（显式入口无组件自带反馈）
  private copyAll(): void {
    const payload: string = this.displayText();
    if (payload === '') {
      this.getUIContext().getPromptAction().showToast({ message: '当前消息没有可复制的文字' });
      return;
    }
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
      this.fromAssistant ? withAiContentLabel(payload) : payload);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    }).catch((e: Object): void => {
      if (this.departed) {
        return;
      }
      hilog.error(0xD5A0, 'MsgCopySheet', '复制全文失败：%{public}s', (e as Error).message);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
    });
  }

  build() {
    HdsNavigation() {
      // 吸底键条层：Stack 底对齐叠〔Scroll 全高 + 渐变蒙层 + 键带〕（键不随滚动）
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            // 口径分段胶囊（SegmentBar 宽 = 父容器宽，外层包 CARD_PANEL_WIDTH 约束）
            Column() {
              SegmentBar({
                items: this.modeItems,
                selectedIndex: $modeIdx
              })
            }
            .width(CARD_PANEL_WIDTH)
            .height(SEGMENT_BAR_HEIGHT)
            // 消息全文（单个可选 Text = 跨段落选择载体；LocalDevice = 设备内复制粘贴）。
            // editMenuOptions = 长按菜单扩展（见 quoteMenu 注释）
            Text(this.displayText())
              .fontSize(15)
              .lineHeight(22)
              .fontColor(cardTitleColor())
              .textAlign(TextAlign.Start)
              .width(CARD_PANEL_WIDTH)
              .copyOption(CopyOptions.LocalDevice)
              .editMenuOptions(this.quoteMenu)
            // AI 显式标识行（助手消息常显——界面呈现义务；用户消息不带）
            if (this.fromAssistant) {
              Text(AI_CONTENT_LABEL)
                .fontSize(12)
                .fontColor(cardDescColor())
                .width(CARD_PANEL_WIDTH)
            }
            // 尾部占位 = 蒙层高（与蒙层同源 bottomFadeHeight）：滚到底末行停在蒙层上方；
            // Row 空占位——Blank 在部分容器下编译 10905201
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

        // 底部渐变蒙层（上透下实 / pageBgFade 深浅分治 / hitTestBehavior(None) 不拦滚动与
        // 长按选择）
        Column()
          .width('100%')
          .height(this.bottomFadeHeight())
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 底部吸底键带（条透明——键自身四件套承担两态；hitTestBehavior(Transparent) 条面
        // 不阻断下层滚动〔透明容器走 Default 仍拦下层手势，悬浮键死区教训〕）
        Column() {
          Row() {
            // 「复制全文」= 中性动作（复制无推进语义不占主操作蓝，灰档；fallbackButton*
            // 四件套次钮档）
            Button('复制全文')
              .width('100%')
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                this.copyAll();
              })
          }
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        // 单一 padding（ArkUI 同属性后设覆盖）
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

  aboutToDisappear(): void {
    this.departed = true;
  }
}
