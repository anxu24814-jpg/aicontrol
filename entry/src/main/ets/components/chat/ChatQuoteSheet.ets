// 完整引用查看半模态·面板内容件（方案 = docs/方案-引用功能全链路-20261021.md §4.3）：待发
// 引用的**全文只读查看 + 删除引用**。宿主 = ChatQuoteBar 组件根 bindSheet（挂点「卡片根」
// 档，三判据见方案档 §4.0 与规范-半模态 §1；面板内容件独立成文件 = SecureInputSheet 同款
// 先例——宿主件贴线只留接线）。
// · 删除动作语义 = 清待发引用（与输入条 × 键同一条上行链），不做二次确认（引用可随时重新
//   选中，破坏性远低于生成物删除；对照 ContextUsageSheet「删除摘要」需确认 = 摘要要花一次
//   模型调用）。键形制 = 危险文字键灰底次钮档 + 危险红字（MountManageCard「移除」先例
//  ——破坏性动作不入主操作蓝档）。
// · 零暂存零编辑（引用增删只在输入侧 × 键与本面板删除键）；零异步（无查库无网络，departed
//   守卫无消费点不设——状态最小化）。
// · 壳 = 规范-半模态全套：HdsNavigation MODAL + sheetTitleBarOptions 同源（勿自绘标题）+
//   Scroll clip(false)（渐变模糊要有内容可透，规范 §2）+ bindToScrollable 滚动感知 + 底部
//   安全区延伸；detents **缺省**（第二参 undefined = [MEDIUM, LARGE] 半屏起双停靠，规范 §4
//  「信息查看类」档——消息全文面板同口径）。
// · 关闭链四件（规范 §1）：`$$` 双向（宿主）/ onWillDismiss 恒放行（零暂存站点，宿主
//   sheetPanelOptions 第一参 action.dismiss）/ 本件随 bindSheet 每次打开重建（无形态复位面）/
//   关闭-再开协调五件式在宿主（ChatQuoteBar）。
// · 文本 copyOption(LocalDevice) 长按可选中复制（MessageCopySheet 正文同口径）；**不挂
//   editMenuOptions**（引用面板无再引用面，防「引用的引用」递归入口）。AI 标识行不加
//  （消息全文面板常显标识行已在源头承担呈现义务，引用是用户策展选择）。
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { cardTitleColor, CARD_PANEL_WIDTH } from '../../common/Theme';

// 底部操作行底距（安全区外的基础呼吸量；真机底部安全区由 bottomInset 追加）
const FOOT_ACTION_GAP: number = 12;
// 底部键高（与面板内操作键同档——ContextUsageSheet 操作行 40）
const FOOT_BUTTON_HEIGHT: number = 40;

@Component
export struct ChatQuoteSheet {
  // 引用全文（宿主 ChatQuoteBar 以待发引用现值传入；≤8000 字符——上游 acceptQuote 已
  // clampQuoteText 截断，本件只展示不再截）
  text: string = '';
  // 底部安全区（宿主透传 ChatInputBar.bottomPad——操作行在 ignoreLayoutSafeArea 区外
  // 自行避让，ContentUsageSheet/ChatAnswerSheet 同口径）
  bottomInset: number = 0;
  // 关闭上行（标题栏 xmark 一路——宿主 requestClose 单入口）
  onClose: () => void = () => {
  };
  // 删除引用上行（底部操作行——宿主链 = 清待发引用 + 关面板；未接线时键不渲染，防死按钮）
  onDelete: (() => void) | undefined = undefined;
  // 标题栏材质随沉浸光感总档（sheetTitleBarOptions 第四参）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 面板内按钮双态族能力位（恒 true = 官方标准外观，CONTENT_FALLBACK_KEY 是能力位，
  // 用户面无入口——规范-行内按钮与光感 §3）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavigation() {
      // 纵向两段：全文滚动区（吃满剩余高度）+ 底部固定操作行（不随内容滚走）
      Column() {
        // 引用全文（单个可选 Text；多行原文逐行展示——空白归一只在输入侧摘要条做，全文
        // 保留原始换行供精读）
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            Text(this.text)
              .fontSize(15)
              .lineHeight(22)
              .fontColor(cardTitleColor())
              .textAlign(TextAlign.Start)
              .width(CARD_PANEL_WIDTH)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 12, bottom: 12 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
        .clip(false)

        // 底部操作行：删除引用（危险文字键灰底次钮档 + 危险红字——MountManageCard「移除」
        // 先例，破坏性动作不入主操作蓝档；仅 onDelete 已接线时渲染，防死按钮）
        if (this.onDelete !== undefined) {
          Row() {
            Button('删除引用')
              .fontColor($r('app.color.dialog_confirm_red'))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .width(CARD_PANEL_WIDTH)
              .height(FOOT_BUTTON_HEIGHT)
              .onClick((): void => {
                const cb: (() => void) | undefined = this.onDelete;
                if (cb !== undefined) {
                  cb();
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: FOOT_ACTION_GAP + this.bottomInset })
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(sheetTitleBarOptions('引用内容', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
