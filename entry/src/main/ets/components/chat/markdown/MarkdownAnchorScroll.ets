/** 用户点击正文锚点时的一次几何滚动；不缓存布局、不调焦点、不订阅或驱动自动跟随。 */
import { componentUtils, UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

function anchorRectangle(ui: UIContext, id: string): componentUtils.ComponentInfo {
  if (id === '') {
    throw new Error('锚点标识为空');
  }
  const rectangle: componentUtils.ComponentInfo = ui.getComponentUtils().getRectangleById(id);
  if (!Number.isFinite(rectangle.size.width) || rectangle.size.width <= 0 ||
    !Number.isFinite(rectangle.size.height) || rectangle.size.height <= 0 ||
    !Number.isFinite(rectangle.windowOffset.x) || !Number.isFinite(rectangle.windowOffset.y)) {
    throw new Error('目标组件尚未完成布局或已离场');
  }
  return rectangle;
}

function reportAnchorFailure(ui: UIContext, detail: string): void {
  hilog.warn(0xD5A0, 'MarkdownAnchorScroll', '正文锚点定位失败：%{public}s', detail);
  try {
    ui.getPromptAction().showToast({ message: '暂时无法定位这段内容，请稍后再试' });
  } catch (error) {
    hilog.warn(0xD5A0, 'MarkdownAnchorScroll', '锚点提示未能显示：%{public}s', (error as Error).message);
  }
}

/** topInset 是窗口坐标的目标上沿（vp），而非 Scroll/List 内部偏移。成功只表示已发出滚动。 */
export function markdownScrollToAnchor(ui: UIContext, scroller: Scroller,
  id: string, topInset: number): boolean {
  try {
    if (!Number.isFinite(topInset) || topInset < 0) {
      throw new Error('锚点顶部让位无效');
    }
    const rectangle: componentUtils.ComponentInfo = anchorRectangle(ui, id);
    const targetY: number = ui.px2vp(rectangle.windowOffset.y);
    const distance: number = targetY - topInset;
    if (!Number.isFinite(targetY) || !Number.isFinite(distance)) {
      throw new Error('锚点位置换算无效');
    }
    // ComponentUtils 为 px，Scroller 数字长度为 vp；不加 currentOffset，scrollBy 消费相对距离。
    scroller.scrollBy(0, distance);
    return true;
  } catch (error) {
    reportAnchorFailure(ui, (error as Error).message);
    return false;
  }
}

/** HDS内容始于窗口顶、回退页始于标题栏下；只在点击时将宿主局部让位换成窗口坐标。 */
export function markdownScrollToAnchorInViewport(ui: UIContext, scroller: Scroller,
  id: string, viewportId: string, localTopInset: number): boolean {
  let topInset: number;
  try {
    const viewport: componentUtils.ComponentInfo = anchorRectangle(ui, viewportId);
    const viewportY: number = ui.px2vp(viewport.windowOffset.y);
    const viewportHeight: number = ui.px2vp(viewport.size.height);
    if (!Number.isFinite(localTopInset) || localTopInset < 0 ||
      !Number.isFinite(viewportY) || !Number.isFinite(viewportHeight) ||
      viewportHeight <= 0 || localTopInset >= viewportHeight) {
      throw new Error('宿主可阅读区域尚不可用');
    }
    topInset = viewportY + localTopInset;
  } catch (error) {
    reportAnchorFailure(ui, (error as Error).message);
    return false;
  }
  return markdownScrollToAnchor(ui, scroller, id, topInset);
}
