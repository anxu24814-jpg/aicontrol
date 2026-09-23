// 官方 openMenu 编程式菜单节点宿主基类（2026-08-30 反馈轮 13 提取——六份同构域件
// [LogPage/TabMoreMenu/ChatMoreMenu/SessionCardMenu/ProviderCardMenu/ProviderTitleMenu]
// 的 ComponentContent 节点生命周期 + openMenu 弹出组装骨架单一来源，技术债清单③偿还）。
// 各域件瘦身为薄壳继承本类：只实现抽象 buildNode（wrapBuilder 参数须直呼 @Builder 函数
// ——编译器静态校验，不能经变量中转，故 buildNode 留壳内）+ 按需一个便捷 open（拼自家
// 锚点 id/材质/targetSpace），页面侧 init/open/dispose 调用零变化。
// 语义口径（六域历史定稿，勿改）：
// · init 首建 / rebuild 弹前 dispose+重建——ComponentContent 创建时固化 UI 树，深浅色
//   切换后必须按当前主题重建（真机 Bug 档案：浅色进页切深色弹菜单字色不反色）；
// · show placement 恒 BottomRight（菜单右缘对锚点右缘、锚点下方弹出；锚点几何两套标准
//   见坑11；勿改 anchorPosition 手算——placement 失效 + 动画原点丢失 + 须写死菜单宽度
//   三副作用，dshinhm 菜单弹窗定位规范）；
// · targetSpace 缺省官方默认 8vp（卡片菜单传 5 比标题栏菜单略近——轮 8 领导拍板）；
// · dispose 与 init 成对（ComponentContent 不 dispose 泄漏——SDK d.ts NOTE）；
// · 未 init 直接 show = 编程错误，打日志可见不静默（P0-1）。
import { ComponentContent, LengthMetrics, uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 弹出可选项（缺省项 = 六域历史定稿值）
export interface AppMenuOpenOptions {
  // 锚点下沿到菜单顶间距（缺省官方默认 8vp；卡片菜单 5vp——比标题栏菜单略近）
  targetSpace?: LengthMetrics;
}

// T = 菜单回调载体类型（ComponentContent 约束须 Object 子型——各域 callbacks 接口均满足）
export abstract class AppMenuHost<T extends Object> {
  protected node: ComponentContent<T> | null = null;

  // 首次建节点（宿主 aboutToAppear；getUIContext 需组件就绪故不在构造期）
  init(uiContext: UIContext, callbacks: T): void {
    this.node = this.buildNode(uiContext, callbacks);
  }

  // 弹出前重建（dispose 旧节点 + 按当前深浅色/材质重建 UI 树）
  rebuild(uiContext: UIContext, callbacks: T): void {
    this.node?.dispose();
    this.node = this.buildNode(uiContext, callbacks);
  }

  // 弹出（锚点 id 定位；壳内便捷 open 经此落地下发）
  show(uiContext: UIContext, anchorId: string, material: uiMaterial.Material,
    options?: AppMenuOpenOptions): void {
    if (this.node === null) {
      hilog.error(0xD5A1, 'AppMenuHost', 'show before init: %{public}s', anchorId);
      return;
    }
    uiContext.getPromptAction().openMenu(this.node, { id: anchorId },
      {
        placement: Placement.BottomRight,
        targetSpace: options?.targetSpace,
        systemMaterial: material
      })
      .catch((err: Error): void => {
        hilog.error(0xD5A1, 'AppMenuHost', 'show menu failed: %{public}s', JSON.stringify(err));
      });
  }

  // 释放节点（宿主 aboutToDisappear，与 init 成对）
  dispose(): void {
    this.node?.dispose();
    this.node = null;
  }

  // 构建菜单内容节点（各域实现——wrapBuilder 须直呼自家 @Builder 函数）
  protected abstract buildNode(uiContext: UIContext, callbacks: T): ComponentContent<T>;
}
