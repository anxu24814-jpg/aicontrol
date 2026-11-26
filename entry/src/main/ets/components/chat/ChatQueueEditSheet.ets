// 排队项编辑半模态面板（★ 2026-10-17 排队插队施工总案 U3；方案档 = docs/方案-进会话体验
// 统一与排队插队施工总案-20261017.md §3 U3，下称方案）。
// 域定义一句话：**排队队列中单条待发消息的文本编辑面**——全屏编辑档（DETENTS_FULL）的
// 自适应文本编辑 + 吸底双键（保存 / 立即发送）；本件只渲染与上行，脏态与占位释放全在
// ChatSheetCtrl（编辑会话单源）。
// · 形制来源（同构范本 = KimiFullInputSheet / EditAssistantSheet）：HdsNavigation MODAL 壳 +
//   sheetTitleBarOptions 同源标题栏 + Stack 底对齐三层 = Scroll（.clip(false) 渐变模糊采样 +
//   TextArea 不设 height 自适应内容、constraintSize minHeight 100% 点击任意处聚焦 /
//   maxHeight 400% 防无界增高）/ 底部渐变蒙层（pageBgFade → page_bg 上透下实、深浅分治、
//   hitTest None 不拦文本长按）/ 透明吸底键带（键四件套承担实底/光感两态，条
//   hitTest Transparent 不阻断下层滚动）。Scroll 尾占位与蒙层同高（含底部安全区，单源
//   bottomFadeHeight——规范-半模态 §2：缺占位则滚到底末行被蒙层最不透明处盖住）。
// · 双键语义（方案 U3-②）：保存 = 次钮（fallbackButton* 四件套）——回写条目文本后回到排队
//   列表（宿主走关闭-再开协调，见 ChatSheetCtrl.queueEditSave）；立即发送 = 主操作键
//   （fallbackButton*(…, true)：官方强调蓝 comp_background_emphasize + font_on_primary 恒白）
//   ——回写条目文本 + jumpSend（「立即发送」= 插队 + 恢复发送，方案 U3-②；面板随之关闭，
//   与 U2「立即发送受理即关」同语义）。键称取「立即发送」而非「发送」：与排队卡行内键
//   同词，明示插队语义（方案原文「发送（以编辑后文本立即发送）」）。
// · 编辑范围（方案 U3-⑤）：只改文本——designateId 随条目原样、排队条目本身文本 only 无附件。
// · 文本通道：TextArea onChange 实时上行 onDraftChange（父页/ChatSheetCtrl 持 live——关闭
//   确认的脏态判据现读 live 与 initial 比对，非快照）；空文本两键禁点（排队域不收空文本，
//   禁把空值静默吞掉或写回）。
// · 脏态关闭（规范-半模态 §1 验收第 10 条）：本面板不自写确认——标题栏 xmark 走 onClose
//   上行宿主 requestClose 单入口，手势/系统返回走 onWillDismiss 经 ChatSheetCtrl 路由到同一
//   入口（脏 = confirmSheetClose 确认后才放行）；保存/立即发送是程序化关闭，不接确认入口。
// · 占位配对释放（方案 U3-④，rikkahub 教益5「否则队头永久卡死」）：进入编辑由宿主置
//   EDITING（G2 拦派发），保存/立即发送/取消/手势关闭四路放行 + 队列域 disposeSilent 兜底。
// · 反碎片下限②申报（为何不能并入既有件）：KimiFullInputSheet 是会话草稿输入域（回写胶囊、
//   附件可用、粘贴转附件三钩子），EditAssistantSheet 是历史助手回复编辑域（保存即分叉落库
//   切分支）；本件是排队条目编辑域（保存回写队列条目 / 立即发送走 jumpSend），行为与数据
//   目的不同，并入任一都会让两个域互相污染。宿主 = ChatQueueHost（排队面板族），复用
//   ChatPage 页面根唯一 bindSheet，**不新增挂载点**（329 组挂载点注册义务不触发）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, pageBgFade } from '../../common/Theme';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 编辑文本框几何（全屏输入 / 编辑回复面板同款：16fp/24 行高，全屏编辑场景契合）
const QUEUE_EDIT_FONT_SIZE: number = 16;
const QUEUE_EDIT_LINE_HEIGHT: number = 24;
// 底部渐隐蒙层高（vp，★ 单源：蒙层与 Scroll 尾占位同用「本值 + 安全区」，一处改两处同效；
// 90vp 沉淀高 = MessageCopySheet 键带基高 64 + 渐隐余量 26 的同款口径）
const QUEUE_EDIT_FADE_HEIGHT: number = 90;

@Component
export struct ChatQueueEditSheet {
  // 打开时条目文本快照（普通成员：面板每次打开重建实例，创建后不变——快照语义）
  initial: string = '';
  // 底部系统导航条高（面板底部留白兜底——模型面板 bottomInset 先例）
  bottomInset: number = 0;
  // 滚动控制器（KimiFullInputSheet 同款：Scroll 视口 + HdsNavigation bindToScrollable
  // 滚动感知——标题栏 AUTO 分割线跟手与 GRADIENT_BLUR 采样同源）
  private scrollController: Scroller = new Scroller();
  // 实时文本上行（宿主持 live——关闭确认的脏态判据现读；初开同步一次，未编辑关闭 = 同值不脏）
  onDraftChange: (text: string) => void = (_text: string): void => {
  };
  // 保存上行（宿主回写条目文本后关面板回排队列表——程序化关闭，不接脏态确认）
  onSave: (text: string) => void = (_text: string): void => {
  };
  // 立即发送上行（宿主回写条目文本 + jumpSend 插队；面板随宿主关闭）
  onSend: (text: string) => void = (_text: string): void => {
  };
  // 关闭上行（标题栏 xmark——宿主 requestClose 单入口：脏态先确认，确认通过才关）
  onClose: () => void = (): void => {
  };
  // 沉浸光感档位（面板壳标题栏材质 / 双键光感驱动；页面无需透传——自订阅先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（双键 fallbackButton* 四件套双态驱动——KimiFullInputSheet 同款）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（底部渐变蒙层深浅分治——pageBgFade 先例）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private text: string = '';

  aboutToAppear(): void {
    this.text = this.initial;
    // 初始即上行（live 与 initial 同步——未编辑关闭的脏判据恒 false）
    this.onDraftChange(this.text);
  }

  // 双键可用判据：排队域不收空文本（ChatSendQueueCtrl.updateItemText 亦拒空）——禁静默吞值
  private canSubmit(): boolean {
    return this.text.trim() !== '';
  }

  // 蒙层与 Scroll 尾占位高度（含底部安全区——规范-半模态 §2 尾占位与蒙层同源）
  private bottomFadeHeight(): number {
    return QUEUE_EDIT_FADE_HEIGHT + this.bottomInset;
  }

  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 内容层：Scroll 承载滚动视口（.clip(false) = 内容穿透标题栏背后供模糊采样）；
        // TextArea 不设 height（官方 d.ts：不设高度自适应内容）：minHeight '100%' = 静止
        // 铺满视口（点击任意处聚焦）/ maxHeight '400%' = 极端长文上限（数据有界红线）
        Scroll(this.scrollController) {
          Column() {
            TextArea({ placeholder: '编辑排队消息', text: $$this.text })
              .width('100%')
              .constraintSize({ minHeight: '100%', maxHeight: '400%' })
              .fontSize(QUEUE_EDIT_FONT_SIZE)
              .lineHeight(QUEUE_EDIT_LINE_HEIGHT)
              .backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 16, top: 16, bottom: 8 })
              .onChange((value: string): void => {
                // $$ 已同步 this.text，此处只上行（宿主持 live——关闭确认脏态判读源）
                this.onDraftChange(value);
              })
            // 尾部透明占位（高度 = 蒙层高，两处同源 bottomFadeHeight——滚到底末行停在
            // 蒙层顶缘上方完整可见；Row 不用 Blank，规范-半模态 §2 先例）
            Row().height(this.bottomFadeHeight())
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .clip(false)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // 底部渐变蒙层（90vp 沉淀高 + 安全区；hitTest None 不拦 TextArea 底部触摸）
        Column()
          .width('100%')
          .height(this.bottomFadeHeight())
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 吸底键带（透明条——键四件套承担实底/光感两态；Transparent = 条面不阻断下层滚动，
        // 键本体响应不衰减——规范-半模态 §2 第三条；单一 padding，两键等宽）
        Column() {
          Row({ space: 12 }) {
            // 「保存」= 次钮（不透明灰阶 / 光感态材质——fallbackButton* 四件套）
            Button('保存')
              .layoutWeight(1)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                if (!this.canSubmit()) {
                  return;
                }
                this.onSave(this.text);
              })
              .enabled(this.canSubmit())
              .opacity(this.canSubmit() ? 1.0 : 0.4)
            // 「立即发送」= 主操作键（官方强调蓝 + 恒白字——primary=true 档；与 U2 卡行
            // 「立即发送」同语义：更新文本后插队，停止当前回复并立即发出）
            Button('立即发送')
              .layoutWeight(1)
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                if (!this.canSubmit()) {
                  return;
                }
                this.onSend(this.text);
              })
              .enabled(this.canSubmit())
              .opacity(this.canSubmit() ? 1.0 : 0.4)
          }
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .padding({ top: 12, bottom: this.bottomInset + 12 })
      }
      .width('100%')
      .height('100%')
    }
    // 标题栏 = sheetTitleBarOptions 5 参默认规格（与列表类半模态同款；不自绘标题）；
    // xmark 关闭走宿主 requestClose 单入口（脏态确认两路同调，见文件头）
    .titleBar(sheetTitleBarOptions('编辑排队消息', '',
      (): void => { this.onClose(); }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scrollController])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
