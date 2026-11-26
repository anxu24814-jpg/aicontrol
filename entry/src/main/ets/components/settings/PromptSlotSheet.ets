// 提示词编辑半模态面板（自 FunctionalModelPage.ets 域级最小拆分外迁——面板体自 SheetHost 逐字搬迁）。职责：
// 八槽提示词编辑面板 UI——内容框（预填生效模板，点击即编辑）· 槽说明小字（hint 非空才渲染）· 恢复默认/保存
// 双键 · HdsNavigation MODAL 壳与标题栏关闭路由。
// 为何不能并入 PromptSlotSpec.ets：那是纯规格表（键/内置模板/必留占位符/面板文案/生效值现读），零 UI
// 依赖、被断言脚本剥离直读；本件是 UI 组件，并入会让规格表反向依赖 UI 组件与光感簇。
// 逻辑仍归宿主页（savePrompt / restorePrompt / requestClosePrompt 三方法未随迁——面板只发意图回调）；
// promptContent 走 @Link 双向（TextArea onChange 写回宿主 @State——坑16 家族：值参快照会丢刷新）；
// contentFallback / immersiveLevel 走 @StorageProp 自订阅；scroller 随件内聚。
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { TEMPLATE_CONTENT_MAX } from '../../common/store/PromptTemplateDb';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { cardDescColor } from '../../common/Theme';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import { resolvePromptSlot } from './PromptSlotSpec';

@Component
export struct PromptSlotSheet {
  // 槽 kind（面板标题/输入框占位/说明小字按槽取；八态判定仍在宿主 isPromptSheet）。★ 本字段**不带本地默认值**
  // ——官方 @Prop 规则「没有本地初始化则父组件必传」，漏传即编译期报错；若给默认 ''，漏传会静默落
  // resolvePromptSlot 的标题槽兜底，保存写到标题提示词键上（最隐蔽的改错键）
  @Prop sheetKind: string;
  // 编辑内容（双向：宿主 openPromptSlot 播种 / restorePrompt 回显；本件 TextArea onChange 写回）
  @Link promptContent: string;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 意图回调（逻辑单源在宿主页：恢复默认清键回内置 / 保存校验落键 / 关闭请求脏态确认）
  onRestore: () => void = () => {
  };
  onSave: () => void = () => {
  };
  onRequestClose: () => void = () => {
  };
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          // 内容框（同系统提示词页 TextArea：预填当前生效模板，点击即编辑；上限 TEMPLATE_CONTENT_MAX）
          TextArea({ placeholder: resolvePromptSlot(this.sheetKind).boxPlaceholder,
            text: this.promptContent })
            .width('100%')
            .height(240)
            .maxLength(TEMPLATE_CONTENT_MAX)
            .onChange((value: string): void => {
              this.promptContent = value;
            })
          // 槽说明小字：置于操作按钮行上方（卡布局次序规约——先说明后操作）；非空才渲染，其余七槽 '' 零布局变化
          if (resolvePromptSlot(this.sheetKind).hint !== '') {
            Text(resolvePromptSlot(this.sheetKind).hint)
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          // 输入框下双键（左恢复默认右保存；次钮 / 保存 = 主钮蓝底——fallbackButton* 四件套双态；保存 = 显式动作，收起不保存）
          Row({ space: 10 }) {
            Button('恢复默认')
              .layoutWeight(1)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                this.onRestore();
              })
            Button('保存')
              .layoutWeight(1)
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                this.onSave();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    // 标题栏（关闭键走关闭请求，脏态先确认——与 bindSheet 的 onWillDismiss 两路同源，单源方法在
    // 宿主 requestClosePrompt）
    .titleBar(sheetTitleBarOptions(resolvePromptSlot(this.sheetKind).sheetTitle, '可编辑',
      (): void => {
        this.onRequestClose();
      }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
  }
}
