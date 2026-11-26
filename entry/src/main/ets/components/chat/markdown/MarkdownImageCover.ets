/** 图片主动预览宿主；独立打开期持有可见态，关闭或换图时由父树释放。 */
// 承载（与受限预览 MarkdownPreviewCover 同构）：bindSheet 半模态（全屏单挡位）+
// HdsNavigation MODAL 壳 + sheetTitleBarOptions 官方标题栏与官方 xmark 关闭圆钮（标题 =
// 图片 alt 文本，官方单行省略接管）——照 MarkdownReadingCover 同构（规范-半模态 §1）。
import { MarkdownDocumentToken } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { MarkdownImageView } from './MarkdownImageView';
import { IMMERSIVE_LEVEL_KEY } from '../../../common/ImmersiveLevel';
import { DETENTS_FULL, sheetPanelOptions, sheetTitleBarOptions } from '../KimiSheetCommon';

@ComponentV2
export struct MarkdownImageCover {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  @Event onClosed: () => void = (): void => {};
  // 半模态可见性（关闭链①：$$ 双向目标；唯一写 true 落 aboutToAppear，宿主挂载即拉起）
  @Local private isPresent: boolean = false;
  private alive: boolean = false;
  private lifecycle: number = 0;
  // 占位空选项（aboutToAppear 必先于 build 执行，真实选项在那里按本会话代际装配）
  private panelOptions: SheetOptions = {};

  aboutToAppear(): void {
    this.alive = true;
    const lifecycle: number = ++this.lifecycle;
    // 半模态面板选项（全工程唯一 SheetOptions 构造点；全屏单挡位与原全屏 ContentCover 行为
    // 等价）。关闭链②：手势路经官方漏斗 onWillDismiss 放行后路由关闭单入口 close()（与标题
    // 栏 xmark 两路同调）；第四参 onDisappear = 离场动效结束信号 → onSheetGone 上行 onClosed
    //（父件清 imageCovers 卸载本宿主）。
    this.panelOptions = sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        if (this.alive && lifecycle === this.lifecycle) { this.close(); }
      },
      DETENTS_FULL,
      undefined,
      (): void => {
        if (this.alive && lifecycle === this.lifecycle) { this.onSheetGone(); }
      });
    // 宿主挂载即拉起：父件置 imageCovers 即开意图，本会话是新鲜宿主，无离场动效在途
    this.isPresent = true;
  }
  aboutToDisappear(): void { this.alive = false; this.lifecycle++; }

  // 关闭单入口（规范-半模态 §1：标题栏 xmark 与 onWillDismiss 两路同调；零暂存恒直关），
  // 只写可见性触发离场动效，内容树随动画走完。
  private close(): void {
    this.isPresent = false;
  }

  // 关闭-再开协调的动效结束执行点（第四参 onDisappear——d.ts「动画结束后回调」）：上行
  // onClosed，父件清 imageCovers（卸载本宿主并放开图片点击）——下一次开只可能在此之后。
  private onSheetGone(): void {
    this.onClosed();
  }

  // 标题栏材质档（V2 组件无 @StorageProp——弹出瞬间现读，MarkdownReadingCover.titleLevel
  // 同口径：面板打开期间档位不会变，无需订阅刷新）
  private titleLevel(): number {
    const level: number | undefined = AppStorage.get<number>(IMMERSIVE_LEVEL_KEY);
    return level === undefined ? 0 : level;
  }

  @Builder
  Page() {
    HdsNavigation() {
      Column() {
        Scroll() {
          MarkdownImageView({ node: this.node, token: this.token, darkMode: this.darkMode, imageHeight: 480 })
        }
        .width('100%').layoutWeight(1).align(Alignment.Center).scrollBar(BarState.Off)
        // 滚动不穿透（真机反馈，与受限预览同款）：Spring alwaysEnabled = 滚动容器
        // 恒消费手势余量（边界回弹）——半模态承载下余量不得传面板拖拽，此笔断链
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%').height('100%')
      // 不设背景色：面板底由 sheetPanelOptions 承担（材质态实底会盖掉材质，「无」档回落
      // page_bg）——MarkdownReadingCover 内容区同口径
    }
    // 官方半模态标题形制（规范-半模态 §1：HdsNavigation MODAL 壳 + sheetTitleBarOptions
    // 同源，勿自绘标题）；关闭键 = 标题栏官方 xmark 圆钮（决明拍板），与 onWillDismiss
    // 两路同调 close()。不设 bindToScrollable / ignoreLayoutSafeArea：图片居中单滚动区，
    // 无吸底键带、无内容穿透标题栏采样路径（区别于完整阅读宿主的长滚动布局）。
    .titleBar(sheetTitleBarOptions(this.node.text || '图片预览', '',
      (): void => { this.close(); }, this.titleLevel()))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
  }

  build() {
    Blank().width(0).height(0).bindSheet($$this.isPresent, this.Page(), this.panelOptions)
  }
}
