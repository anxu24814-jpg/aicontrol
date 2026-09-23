// 会话列表多选批量条（2026-08-29 会话多选删除 自 dshinhm SessionMultiselectBar.ets 迁入，
// dshinhm 二二一改域级最小拆分先例；组件通用——主操作文案由使用方注入，本项目用法 =
// 「删除 N 个会话」，dshinhm 用法 = 批量归档）：
// · 形态 = 悬浮无实底容器（仅按钮本体有材质/底色）、取消（次，官方普通灰）+ 主操作（蓝灰，
//   font_on_primary 恒白）等宽并排——AdjustStageView「上一步/保存」双键沉淀姿势；
// · 容器 HitTestMode.Transparent（官方 d.ts 实锤：自身与子组件响应命中、不拦兄弟节点）
//   ——按钮可点、空白区触摸穿透到下层列表可继续滚动； Blank 把按钮压到容器底部；
// · 按钮四件套随「内容区回退开关」(contentFallback) 双态：光感态 = 原材质随沉浸光感
//   总档（resolvedButton*）；实底态 = fallbackButton* 官方实底（新规范下内容区材质不生效）。
//   均 @StorageProp 自订阅——归档页/全屏输入面板同款姿势，页面无需透传。
import {
  CONTENT_FALLBACK_KEY,
  IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg,
  fallbackButtonFont,
  fallbackButtonMaterial,
  fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';

@Component
export struct SessionMultiselectBar {
  // 主操作文案（「删除 N 个会话」/「删除中…」——计数与请求态由页面注入;N=0 显示
  // 「删除会话」，空选点击由页面 deleteSelected 首行守卫拦住，与 dshinhm 归档页同款
  // 不加禁用态）。
  // ★ @Prop（dshinhm 二二四改）：普通成员「入参不重渲染」（坑57）——父组件选中数/请求态
  // 变化后按钮文案停在初始值，勾选数与执行中状态全部不刷新；@Prop 单向按值流入,
  // 父 build 重算即刷新按钮文本
  @Prop barText: string = '';
  // 取消（退出多选）/ 主操作（执行批量删除）——回调上行页面
  onCancel: () => void = () => {
  };
  onPrimary: () => void = () => {
  };
  // 批量条距屏底（vp，宿主传 navBarHeight + 16——悬浮在页签上方）
  barBottom: number = 96;
  // 沉浸光感档位（按钮材质随沉浸光感总档——自订阅先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  build() {
    Column() {
      Blank()
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick(() => {
            this.onCancel();
          })
        Button(this.barText)
          .layoutWeight(1)
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick(() => {
            this.onPrimary();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .padding({ bottom: this.barBottom })
  }
}
