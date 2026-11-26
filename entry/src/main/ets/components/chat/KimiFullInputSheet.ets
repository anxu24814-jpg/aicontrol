// Kimi 全屏输入面板：聊天输入框聚焦浮出「全屏输入」快捷条 → 本面板（全屏半模态
// bindSheet——坑64 姿势：复用 ChatPage 页面根既有 bindSheet，sheetKind='input' 分支挂载，
// 不新增挂载点）。官方查证：SDK 26 text_area/text_input 无 fullscreen/expandable 能力、
// 系统编辑菜单不可加分项——方案 = 聚焦快捷条 + 官方 bindSheet 半模态（bindPopup 语义偏
// 气泡不采用）。
// · 内容层（模型面板同构三件套）：Scroll 承载滚动视口（.clip(false) 滚动溢出穿透标题栏
//   背后被 GRADIENT_BLUR 模糊采样 + bindToScrollable 滚动感知；.align(TopStart) 坑18：
//   Scroll align 默认 Center，短内容会垂直居中）+ TextArea 不设 height（官方 d.ts：不设
//   高度自适应内容）+ constraintSize minHeight '100%'（静止铺满视口、点击任意处聚焦）/
//   maxHeight '400%'（极端长文防无界增高——数据有界红线；超限回 TextArea 内滚）；尾部
//   透明占位 Row().height(90) = 蒙层高（**调改两处同步**，坑66 方案 B——无占位则滚到底
//   最后一行被蒙层最不透明处盖住，滚到底最后行停在蒙层上方完整可见）；.edgeEffect(
//   EdgeEffect.Spring) 对齐列表面板（Scroll 默认 None，List 默认 Spring）。
// · 底部工具带：Stack 叠放（内容滚到底透到按钮后）+ **渐变蒙层 = 项目沉淀**（ChatPageContent
//   ①b 层同款 90vp / pageBgFade→page_bg 上透下实 / 深浅分治 / hitTestBehavior(None)——
//   沉淀形态 = 纯色渐变蒙层，决明拍板「模糊带观感不干净」已弃 linearGradientBlur，勿回退）
//   + 保存/发送双键（等宽并排；fallbackButton* 双态四件套 = 内容区回退开关：实底态官方
//   实底/光感态材质光感随沉浸光感总档）。
//   **「保存」= 关闭路径的显式入口**（与 xmark/下滑/系统返回同一行为：onClose 回写 live，
//   退出后面板关闭、内容保留在胶囊输入框）。
// · 顶部 = sheetTitleBarOptions 默认 5 参规格（GRADIENT_BLUR 常显 + HDS 材质随沉浸光感
//   总档，与选择模型等列表类半模态完全同款）——半模态标题栏自定义（OFF 分割线/内容延伸）
//   实测分割线仍在且下移已回退，勿再自定义半模态顶部。
// · 文本通道：TextArea onChange 实时上行 onDraftChange（父持 live）——任何关闭路径
//   （xmark/下滑/遮罩/系统返回）都回写胶囊输入框（未发送的编辑不丢）；onSend 上行父页
//   发送编排（sendPrompt 链路；发送后胶囊由父页经 fullInputCmd 清空）。发送可用 = 文本
//   非空或附件 >0（attachCount 入参——附件预览入口在胶囊输入栏）。
// · 不做（克制红线）：面板内附件条/参数 chip/思考档/字数统计——入口均在胶囊；粘贴联想等
//   系统提供。
// · 键盘避让：官方 sheet 随键盘行为优先；bottomInset 兜底（底部导航条高，模型面板先例）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  PASTE_THRESHOLD_DEFAULT, PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY,
  clampPasteThreshold
} from '../../common/AppPreferences';
import { settlePastedText, shouldInterceptInsert, shouldPasteAsFile } from './AttachmentPickCtrl';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { pageBgFade } from '../../common/Theme';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 全屏输入文本框几何（★ 观感唯一可调点：真机偏大/偏小只调这两值——
// 16fp/24 行高 = 比胶囊 15/21 略大，全屏编辑场景契合；行高与字号配套避免行高异常）
const FS_FONT_SIZE: number = 16;
const FS_LINE_HEIGHT: number = 24;

@Component
export struct KimiFullInputSheet {
  // 打开时胶囊输入框文本快照（普通成员：面板每次打开重建实例，创建后不变——快照语义）
  initial: string = '';
  // 胶囊已选附件数（发送可用判定：文本空格子 + 附件 >0 允许——与胶囊发送键同语义）
  attachCount: number = 0;
  // 底部系统导航条高（面板底部留白兜底——模型面板 bottomInset 先例）
  bottomInset: number = 0;
  // 滚动控制器（Scroll 视口 + bindToScrollable 滚动感知）——组件自持即可：面板每次打开
  // 重建实例，滚动位置无需跨开关保留（页面持有先例针对「同面板反复开关保位置」，本面板
  // 草稿语义不需要）
  private scrollController: Scroller = new Scroller();
  // 实时草稿上行（父持 live——关闭即回写胶囊，见 KimiChatPage applyFullInputDraft）
  onDraftChange: (text: string) => void = () => {
  };
  // 发送（面板文本；胶囊附件由父页组装上行——sendPrompt 链路）
  onSend: (text: string) => void = () => {
  };
  // 长文本粘贴/上屏转附件上行：页面把这段文本转成附件入列，完成后以 settle(converted)
  // 回报结果（必调恰一次，与胶囊输入栏同一契约与同一批判据）。★ 默认实现 = settle(false)
  // 而非空体——两条钩子都拦下原生插入、全靠这个回调把文本还回来，宿主漏接线时空体 = 长文
  // 本静默消失；settle(false) 退化为「不转附件、原文留在框里」（P0-1 禁静默失败）
  onPasteLongText: (text: string, settle: (converted: boolean) => void) => void =
    (_text: string, settle: (converted: boolean) => void): void => {
      settle(false);
    };
  onClose: () => void = () => {
  };
  // 沉浸光感档位（面板壳标题栏材质/发送按钮光感驱动；页面无需透传——自订阅先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 粘贴长文本转文件两键：本面板与胶囊输入栏同一套判定与偏好——面板是聊天输入的第二处
  // 输入面（决明：「全屏也拦，可加提示」），@StorageProp 自订阅
  @StorageProp(PREF_PASTE_AS_FILE_KEY) pasteAsFile: boolean = true;
  @StorageProp(PREF_PASTE_AS_FILE_THRESHOLD_KEY) pasteThreshold: number = PASTE_THRESHOLD_DEFAULT;
  // 已被 onPaste 受理的那段原文（防两条通路对同一段文本各转一次，同胶囊输入栏口径）。
  // ★ 生命期 = 一次受理：收口回调里复位（见 handOffLongText）——只写不清会让「先长按粘过
  // 某段 → 之后键盘剪贴板再粘同一段」被当重复放行（功能静默失效）
  private lastPasteHandled: string = '';
  // 内容区回退开关：实底态 = 官方实底（次钮不透明灰阶 / 主钮官方强调蓝）；光感态 = 材质
  // 光感——与其余内容区按钮簇同构（本面板原归 bindSheet 弹窗豁免未接入，决明反馈后接入）。
  // 标题栏 sheetTitleBarOptions 仍随沉浸光感总档（标题栏豁免区，不动）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（底部渐变蒙层深浅分治——pageBgFade 同 ChatPageContent ①b 层先例）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private text: string = '';

  aboutToAppear(): void {
    this.text = this.initial;
    // 初始即上行（未编辑直接关闭 = 回写胶囊同值——幂等无害；确保 live 与 initial 同步）
    this.onDraftChange(this.text);
  }

  private canSend(): boolean {
    return this.text.trim() !== '' || this.attachCount > 0;
  }

  // 长文本转附件上行（两处 hooks 共用）：settle 回报后按单源判据对齐面板文本，转成时补一句
  // 提示（面板内没有附件条，不提示 = 用户看到文字凭空消失）；★ 对齐后须 onDraftChange 上行
  //——面板文本是父页 live 草稿的唯一来源，只改 this.text 不上行会让关闭时的回写把原文又
  // 带回胶囊（与附件重复）
  private handOffLongText(text: string, before: string): void {
    this.onPasteLongText(text, (converted: boolean): void => {
      // 哨兵复位（本次受理已收口）——两通路共用本收口故复位也在此；输入法通路本不写哨兵，
      // 复位对它是零操作（字段注释：只写不清会让同内容的后续粘贴被误判成重复）
      this.lastPasteHandled = '';
      if (converted) {
        this.getUIContext().getPromptAction().showToast({ message: '已转为文本附件' });
      }
      const settled: string = settlePastedText(this.text, before, text, converted);
      if (settled !== this.text) {
        this.text = settled;
        this.onDraftChange(settled);
      }
    });
  }

  build() {
    HdsNavigation() {
      // Stack 叠放（内容滚到底透到按钮后 + 底部渐变蒙层沉淀，口径见文件头）
      Stack({ alignContent: Alignment.Bottom }) {
        // 内容层（Scroll 视口 + 自适应 TextArea，三件套与几何口径见文件头）；
        // 位置参数 Scroller（官方 d.ts：Scroll(scroller?)——非 List 的对象参数形制）
        Scroll(this.scrollController) {
          Column() {
            TextArea({ placeholder: '输入消息…', text: $$this.text })
              .width('100%')
              .constraintSize({ minHeight: '100%', maxHeight: '400%' })
              .fontSize(FS_FONT_SIZE)
              .lineHeight(FS_LINE_HEIGHT)
              .backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 16, top: 16, bottom: 8 })
              .onChange((value: string) => {
                // $$已同步 this.text，此处只上行（父持 live——关闭回写通道）
                this.onDraftChange(value);
              })
              // 粘贴拦截：判定单源 = AttachmentPickCtrl.shouldPasteAsFile，收口判据单源 =
              // settlePastedText（与胶囊输入栏完全同一套，禁在本件另写条件）
              .onPaste((value: string, event: PasteEvent): void => {
                const threshold: number = clampPasteThreshold(this.pasteThreshold);
                const intercept: boolean = shouldPasteAsFile(value, this.pasteAsFile, threshold);
                // 判定留痕（用户不可见；与胶囊输入栏同款、同域名同 tag——真机判定要两输入面
                // 都有证据面，缺一面则该面「没转」时分不清是钩子没到还是判定没过）
                hilog.info(0xD5A0, 'ChatInput',
                  '粘贴判定(面板) 长度=%{public}d 阈值=%{public}d 开关=%{public}s 拦截=%{public}s',
                  value.length, threshold, String(this.pasteAsFile), String(intercept));
                if (!intercept) {
                  return; // 不拦：走原生粘贴
                }
                const before: string = this.text;
                this.lastPasteHandled = value; // 交棒给 onWillInsert 去重
                if (event !== undefined && event.preventDefault !== undefined) {
                  event.preventDefault();
                }
                this.handOffLongText(value, before);
              })
              // 输入法通路拦截（系统键盘剪贴板上屏的长文本不走 onPaste——见胶囊输入栏同段注释）
              .onWillInsert((info: InsertValue): boolean => {
                const inserted: string = info.insertValue;
                const threshold: number = clampPasteThreshold(this.pasteThreshold);
                const intercept: boolean = shouldInterceptInsert(inserted, this.lastPasteHandled,
                  this.pasteAsFile, threshold);
                // 判定留痕（同胶囊输入栏；用户不可见）
                hilog.info(0xD5A0, 'ChatInput',
                  '输入法上屏判定(面板) 长度=%{public}d 阈值=%{public}d 开关=%{public}s 拦截=%{public}s',
                  inserted.length, threshold, String(this.pasteAsFile), String(intercept));
                if (!intercept) {
                  return true; // 不拦：正常插入（含 onPaste 已受理的同一段文本）
                }
                this.handOffLongText(inserted, this.text);
                return false; // 拦下本次插入（文本改走附件）
              })
            // 尾部透明占位（高度 = 底部蒙层高，**调改两处同步**——坑66 方案 B；机制见文件头
            // 内容层节：占位后滚到底 = 最后一行停在蒙层顶缘上方完整可见，滚动中仍从按钮后
            // 渐隐穿过）
            Row().height(90)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        // 穿透两件套（模型面板 List 同款）：不裁滚动溢出内容（透到标题栏背后）+ 顶对齐
        .clip(false)
        .align(Alignment.TopStart)
        // 长文位置指示（Scroll 默认无滚动条、List 默认 Auto——对齐列表面板观感）
        .scrollBar(BarState.Off)
        // 顶/底边缘回弹（Scroll 默认 edgeEffect None，显式 Spring 对齐列表面板）
        .edgeEffect(EdgeEffect.Spring)

        // 底部渐变蒙层 = 项目沉淀（90vp / pageBgFade→page_bg / 深浅分治，口径见文件头；
        // 层级 = TextArea 之上、按钮带之下——按钮带透明底，光感由按钮材质承担）。
        // ★ hitTestBehavior(None) 必须有——缺则 90vp 蒙层区域拦截 TextArea 底部触摸
        //（光标定位/长按选择），①b 层先例同款
        Column()
          .width('100%')
          .height(90)
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 底部工具带（透明底；按钮双态 = fallbackButton* 四件套，口径见文件头）
        Column() {
          Row({ space: 12 }) {
            // 「保存」= 执行返回操作（退回原界面、输入内容留在输入框——与 xmark/下滑/
            // 系统返回的关闭路径同一行为，显式入口）
            Button('保存')
              .layoutWeight(1)
              // 双态四件套：实底态 = 不透明灰阶实底（次钮）/ 光感态 = 透明底 + 材质光感
              //（先透明再设材质的官方姿势）
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick(() => {
                this.onClose();
              })
            // 「发送」官方主按钮（先透明底再设材质；文字 font_on_primary 恒白；草稿随发送
            // 清空，父页经 fullInputCmd 回写）
            Button('发送')
              .layoutWeight(1)
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick(() => {
                if (!this.canSend()) {
                  return;
                }
                this.onSend(this.text.trim());
              })
              // 发送为空禁点（P0-1；附件-only 由 attachCount 放行——语义同胶囊发送键）
              .enabled(this.canSend())
              .opacity(this.canSend() ? 1.0 : 0.4)
          }
          .width('100%')
          // ★ 单一 padding——ArkUI 同属性后设覆盖（两个 .padding() 串联会令左右 16vp 被
          // 后设 bottom 覆盖 = 「按钮顶到屏幕边缘」，已修教训）
          .padding({ left: 16, right: 16, top: 12, bottom: this.bottomInset + 12 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    // 标题栏 = sheetTitleBarOptions 默认规格（与选择模型等列表类半模态完全同款；勿再自定义
    // 半模态顶部——OFF 分割线/内容延伸实测分割线仍在且下移已回退，教训见 KimiSheetCommon
    // 头注释）；bindToScrollable = 三件套最后一件（标题栏感知 Scroll 滚动，AUTO 分割线跟手）
    .titleBar(sheetTitleBarOptions('全屏输入', '',
      (): void => { this.onClose(); }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scrollController])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
