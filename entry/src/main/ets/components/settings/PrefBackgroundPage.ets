// 「背景」三级页（原外观显示页「背景」段独立成页，随偏好与外观重梳笔迁址）：BackgroundPanel
// 整页承载——预览框 + 「选择图片 / 编辑图片」双键 + 背景生效范围分段卡 + 卡底透明度滑轨卡 +
// 恢复默认，面板内容零改动（原 AppearancePage 三段分段胶囊结构整体退役，本页为普通滚动页）。
// 骨架：壳由 PageShell 提供；本页无状态 → push 无参（pathStack 透传面板）、返回无参 pop 不挂
// onPop（坑17 口径）。面板内部「选择图片/编辑图片」push 图片编辑页，编辑保存后 ImageAdjustPage
// popToName 一次弹两级回本页（pageBg 预览经显示纪元键补刷，机制在面板内部）。
import { BackgroundPanel } from '../BackgroundPanel';
import { SETTING_TITLE_TAB_BACKGROUND } from '../../common/SettingSearch';
import { PageShell } from '../../common/PageShell';

@Component
export struct PrefBackgroundPage {
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首件落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：面板「选择/编辑图片」push 编辑二级页
  pathStack: NavPathStack = new NavPathStack();

  build() {
    // 页面骨架统一由 PageShell 提供（自带档位实时刷新，勿自绘 titleBar）
    PageShell({
      title: SETTING_TITLE_TAB_BACKGROUND,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      // 面板自持 CARD_PANEL_WIDTH 居中：内容区不设左右边距，留白由控件自身宽度产生
      Column() {
        BackgroundPanel({ pathStack: this.pathStack })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }
}
