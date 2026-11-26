// 「字体」三级页（原外观显示页「字体」段独立成页，随偏好与外观重梳笔迁址）：ChatFontSection
// 整页承载——字体展示卡 + 正文字体 / 代码字体选择组卡 + 自定义字体管理卡 + 字体生效范围分段卡，
// 段件内容零改动（原 AppearancePage 三段分段胶囊结构整体退役，本页为普通滚动页）。
// 骨架：壳由 PageShell 提供；段件自持全部 @StorageLink 订阅与交互（选字体 / 导入 / 删除 /
// 生效范围），本页无状态 → push 无参、返回无参 pop 不挂 onPop（坑17 口径）。
import { ChatFontSection } from './ChatFontSection';
import { SETTING_TITLE_TAB_FONT } from '../../common/SettingSearch';
import { PageShell } from '../../common/PageShell';

@Component
export struct PrefFontPage {
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;

  build() {
    // 页面骨架统一由 PageShell 提供（自带档位实时刷新，勿自绘 titleBar）
    PageShell({
      title: SETTING_TITLE_TAB_FONT,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      // 段件自持 CARD_PANEL_WIDTH 居中：内容区不设左右边距，留白由控件自身宽度产生
      Column() {
        ChatFontSection()
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
