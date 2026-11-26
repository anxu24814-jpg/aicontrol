// 编辑助手回复半模态面板（2026-10-05 编辑助手回复笔新建）。
// 形态照 KimiFullInputSheet 全屏输入类面板（规范-半模态面板与卡片布局 §4「全屏输入类」
// detents [LARGE]）同构换内容：HdsNavigation MODAL 壳 + sheetTitleBarOptions 同源标题栏 +
// Stack 三层（Scroll 承载自适应 TextArea / 底部渐变蒙层 / 吸底键带单键「保存」——
// 键带形制 = MessageCopySheet 复制全文键带三层，2026-10-05 真机修复定）。
// · 与全屏输入面板的差异（克制红线，不做面板外功能）：无附件（assistant 行不带附件泡）、
//   无粘贴转附件两钩子（编辑既有文本非输入场景，原生粘贴即可）、无草稿回写胶囊——
//   脏态实时上行父页（onDraftChange）仅供关闭确认判读。
// · 单键语义（拍板 2026-10-05）：「保存」= 分叉落库切分支（编排 ChatBranchCtrl
//   .submitEditAssistant），**不触发生成**——编辑只改历史，效果在后续任何一次请求按
//   活动分支路径取上下文时生效。保存成功由父页关面板（编排返回 true），失败面板留存
//   文本可重试（P0-1 不静默）。
// · 关闭确认（规范验收清单第 10 条，有暂存面板强制）：本面板不自写——标题栏关闭键走
//   onClose 上行父页 requestClose 单入口，手势关闭走 onWillDismiss 同一入口（ChatSheetCtrl
//   路由），脏态由父页现读 live 与 initial 比对（本面板只保证 onChange 实时上行）。
//   程序化关闭（保存成功）不接确认入口——父页编排返回后直写可见性。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, pageBgFade } from '../../common/Theme';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 编辑文本框几何（全屏输入面板同款：16fp/24 行高，全屏编辑场景契合）
const FS_FONT_SIZE: number = 16;
const FS_LINE_HEIGHT: number = 24;

@Component
export struct EditAssistantSheet {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 打开时带出的原文快照（普通成员：面板每次打开重建实例，创建后不变——快照语义）
  initial: string = '';
  // 底部系统导航条高（面板底部留白兜底——模型面板 bottomInset 先例）
  bottomInset: number = 0;
  // 滚动控制器（KimiFullInputSheet 同款：Scroll 视口 + HdsNavigation bindToScrollable
  // 滚动感知——标题栏 AUTO 分割线跟手与 GRADIENT_BLUR 采样同源；面板每次打开重建实例）
  private scrollController: Scroller = new Scroller();
  // 实时内容上行（父页持 live——关闭确认脏态判读源；初开同步一次，未编辑关闭 = live 与
  // initial 同值即不脏）
  onDraftChange: (text: string) => void = () => {
  };
  // 保存上行（面板文本原样——首尾空白不剥：回复正文可能有意以空白开头；空文本键禁点）。
  // 返回 true = 落库成功（父页据此关面板）；false = 失败（面板留存，错误已由编排 toast）
  onSave: (text: string) => Promise<boolean> = (_text: string): Promise<boolean> =>
    Promise.resolve(false);
  onClose: () => void = () => {
  };
  // 沉浸光感档位（面板壳标题栏材质/保存键光感驱动；页面无需透传——自订阅先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03 接入回退控制——KimiFullInputSheet 同款四件套双态）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（底部渐变蒙层深浅分治——pageBgFade 先例）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private text: string = '';
  // 保存在途位（防连点双写分叉：保存链是建分支+切分支的多步写，在途再点 = 两次分叉落库。
  // 入口置位、Promise 链尾 finally 复位——成败两路，漏复位即保存键永久失效）
  @State private saving: boolean = false;

  aboutToAppear(): void {
    this.text = this.initial;
    // 初始即上行（live 与 initial 同步——未编辑关闭的脏判据恒 false）
    this.onDraftChange(this.text);
  }

  private canSave(): boolean {
    return this.text.trim() !== '';
  }

  private submit(): void {
    if (!this.canSave() || this.saving) {
      return;
    }
    this.saving = true;
    this.onSave(this.text).finally((): void => {
      if (this.departed) {
        return;
      }
      this.saving = false; // 成败两路复位（成对纪律——置位在本方法内，复位也在）
    });
  }

  build() {
    HdsNavigation() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 内容层：Scroll 承载滚动视口（.clip(false) 穿透标题栏背后供模糊采样——规范 §2）+
        // TextArea 不设 height（官方 d.ts：不设高度自适应内容）：minHeight '100%' = 静止铺满
        // 视口 / maxHeight '400%' = 极端长文上限（数据有界红线，超限回 TextArea 内滚）
        Scroll(this.scrollController) {
          Column() {
            TextArea({ text: $$this.text })
              .width('100%')
              .constraintSize({ minHeight: '100%', maxHeight: '400%' })
              .fontSize(FS_FONT_SIZE)
              .lineHeight(FS_LINE_HEIGHT)
              .backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 16, top: 16, bottom: 8 })
              .onChange((value: string) => {
                // $$已同步 this.text，此处只上行（父页持 live——关闭确认脏态判读源）
                this.onDraftChange(value);
              })
            // 尾部透明占位（高度 = 底部蒙层高，调改两处同步——KimiFullInputSheet 同款机制，
            // 坑66 方案 B）：滚到底最后一行停在蒙层顶缘上方完整可见
            Row().height(90)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .clip(false)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // 底部渐变蒙层（90vp 沉淀高——KimiFullInputSheet 同款；hitTestBehavior None 不拦
        // TextArea 底部触摸）
        Column()
          .width('100%')
          .height(90)
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 吸底键带（透明条——实底/光感由键四件套承担；规范 §2 吸底键条先例同款）：
        // 单键「保存」主操作形态（官方强调蓝 + 恒白字，规范-行内按钮与光感主操作键档）
        // ★ 2026-10-05 真机修复（决明「保存键不是吸底，整个竖长条居中」）：原键直接居
        // Column 且挂 layoutWeight(1)——Column 主轴为纵轴，权重把键拉满高、宽度反按内容
        // 收窄 = 整屏竖条；修正为该键带形制照 MessageCopySheet 复制全文键带（Column →
        // Row 定宽 CARD_PANEL_WIDTH → 键 width('100%')）：键宽归 Row 横轴、键高回归官方
        // 默认 40vp 吸底。键带 Transparent = 条面不阻断下层滚动（同参考件；09-04 悬浮键
        // 死区教训）
        Column() {
          Row() {
            Button(this.saving ? '正在保存…' : '保存')
              .width('100%')
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick(() => {
                this.submit();
              })
              .enabled(this.canSave() && !this.saving)
              .opacity(this.canSave() ? 1.0 : 0.4)
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
    .titleBar(sheetTitleBarOptions('编辑回复', '',
      (): void => { this.onClose(); }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scrollController])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
