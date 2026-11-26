// 「反馈与建议」页（入口 = 更多信息页行卡，决明指令）：应用内反馈，纯客户端零服务器，
// 正文 + 环境信息一行 POST 到 MeoW 推送服务（common/FeedbackMeow.ets）→ 开发者手机 MeoW
// 弹系统推送；链路与选型见 docs/调研-应用内反馈方案与Cube-Meow链路逆向-20260907.md V2 口径。
// 表单形制照 Cube 反馈页裁剪：类型 chip / 截图 / 联系方式 / 工单通知开关不做——无工单后端
// 回不了用户，只留「标题 + 正文 + 环境信息自动附」；标题 = 用户简述问题类型（选填，20 字内，
// 随反馈作为推送正文首行——推送标题保持固定前缀，见 FeedbackMeow 头注释）。
// ★ 表单重构批 9 形制：①页首说明句改引导卡（图标块 + 标题 + 一句说明）；②标题与正文两
// 字段组同收「反馈」卡，限长与计数在字段标签行右侧；③环境信息独立成卡——只读井
//（ReadonlyField）+ 卡内说明 + 卡脚（K5：第三方推送与隐私政策出处，本卡无操作按钮行，
// 符合规范 §1.5 硬边界）；④发送键改**吸底固定键条**（Stack alignContent Bottom，长文输入
// 时不用滚回页尾；条透明、键官方实底，SystemPromptPage 同款）；⑤隐私披露并入环境卡卡脚，
// 不另挂提示卡。
// 隐私披露三处同步：本页卡脚 + 隐私政策第四节 + 帮助中心条目。
// 页面骨架 PageShell；提交键 = 内容区 fallbackButton* 双态族（primary=true 官方强调蓝 +
// 恒白字）；toast 走 UIContext + 光感材质（AboutPage 同款）。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../common/AppPreferences';
import {
 CARD_NOTE_FONTSIZE, CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING,
  cardBg, cardBorderColor, cardDescColor, cardTitleColor, fallbackBlueBg, CARD_RADIUS
} from '../common/Theme';
import { envInfoLine } from '../common/EnvInfo';
import { SETTING_TITLE_FEEDBACK } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';
import {
  CONTENT_FALLBACK_KEY,
  fallbackButtonBg,
  fallbackButtonFont,
  fallbackButtonMaterial,
  fallbackButtonStateEffect,
  IMMERSIVE_LEVEL_KEY,
  resolvedUiMaterial
} from '../common/ImmersiveLevel';
import { sendFeedbackPush } from '../common/FeedbackMeow';
import { BadgeTone, StatusBadge } from './StatusBadge';
import { ReadonlyField } from './ReadonlyField';

// 反馈正文上限（MeoW 官方未给消息上限，500 字对问题描述足够且推送卡片长度可控）
const FEEDBACK_MAX_LENGTH: number = 500;
// 反馈标题上限（简述问题类型，20 字内——随推送作为正文首行，长度可控）
const FEEDBACK_TITLE_MAX_LENGTH: number = 20;
// 吸底键条让位（条上内边距 12 + 按钮 40 + 条下内边距 bottomPad + 16——与 Content 两处同改）
const BOTTOM_BAR_RESERVE: number = 68;

@Component
export struct FeedbackPage {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（创建后不变，普通成员——
  // 状态最小化，AboutPage 先例）
  topPad: number = 0;
  // 底部留白（吸底键条让位基准；PageMap 传入）
  bottomPad: number = 0;
  // 沉浸光感档位 + 内容区回退开关（AppStorage 自订阅：toast 材质 / 提交键双态）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（引导卡图标块淡彩底随档——与全站灰面同口径）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 反馈标题（TextInput 双向；用户简述问题类型，选填——未填则推送正文无标题行）
  @State titleText: string = '';
  // 反馈正文（TextArea 双向）
  @State content: string = '';
  // 发送中（防重复提交：按钮禁用 + 直接 return）
  @State sending: boolean = false;
  // 环境信息行（aboutToAppear 组装一次，页面生命周期内不变；上屏进只读井，故走 @State）
  @State envLine: string = '';

  aboutToAppear(): void {
    this.envLine = envInfoLine();
  }

  // 环境信息行 = common/EnvInfo.envInfoLine（公共单源：运行日志页导出 TXT 头部同用这一行，
  // 两处文案永久一致；版本读取失败的「未知」兜底与只读字段口径见该件头注释）

  // 本页 toast 统一入口（AboutPage 同款：UIContext 形态 + 沉浸光感随沉浸光感总档）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false)
    });
  }

  // 提交：空文本拦截 → 发送中防重入 → 成功清空输入 + 提示；失败 toast 透出错误码
  //（FeedbackMeow 已组好中文消息）。finally 归位 sending——异常路径不卡死按钮（P0-1）
  private async submit(): Promise<void> {
    if (this.sending) {
      return;
    }
    const text: string = this.content.trim();
    if (text === '') {
      this.showToast('先写点内容再发送');
      return;
    }
    this.sending = true;
    try {
      const result = await sendFeedbackPush(text + '\n' + this.envLine, this.titleText.trim());
      if (this.departed) {
        return;
      }
      if (result.ok) {
        this.content = '';
        this.titleText = '';
        this.showToast('反馈已发送，感谢你的反馈');
      } else {
        this.showToast(result.errorMessage);
      }
    } finally {
      this.sending = false;
    }
  }

  // 页首引导卡：图标块 + 一句「这是干什么的、会送到哪」；中性卡底（淡染留给真正要强调的
  // 数据卡，规范 §1.3）
  @Builder
  IntroCard() {
    Row({ space: 12 }) {
      Stack() {
        Column()
          .width(44)
          .height(44)
          .borderRadius(12)
          .backgroundColor(fallbackBlueBg(this.appColorMode, this.cardAlphaLevel))
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(22)
          .fontColor([$r('sys.color.ohos_id_color_emphasize')])
      }
      .width(44)
      .height(44)
      Column({ space: 3 }) {
        Text('遇到问题或有改进想法')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text('发送后会直接送达开发者，不需要注册，也不会附带聊天内容。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  // 反馈卡（标题 + 正文同卡；字段标签行右侧带限长与计数——状态贴着字段，不靠说明猜）
  @Builder
  FormCard() {
    Column({ space: 10 }) {
      Text('反馈')
        .fontSize(CARD_SECTION_TITLE_FONTSIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text('标题')
            .fontSize(13)
            .fontColor(cardDescColor())
          Blank()
          Text('可选 · ' + FEEDBACK_TITLE_MAX_LENGTH + ' 字内')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        TextInput({ placeholder: '简述问题类型，例如 崩溃、建议', text: this.titleText })
          .width('100%')
          .maxLength(FEEDBACK_TITLE_MAX_LENGTH)
          .onChange((value: string): void => {
            this.titleText = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text('内容')
            .fontSize(13)
            .fontColor(cardDescColor())
          Blank()
          Text(this.content.length + ' / ' + FEEDBACK_MAX_LENGTH)
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        TextArea({ placeholder: '描述遇到的问题或建议，例如搜索结果排版错乱', text: this.content })
          .width('100%')
          .height(160)
          .maxLength(FEEDBACK_MAX_LENGTH)
          .onChange((value: string): void => {
            this.content = value;
          })
        Text('请描述复现步骤或想要的效果。越具体越容易定位。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 环境信息卡（只读井 + 说明 + 卡脚）：本卡无操作按钮行 → 卡脚可用（规范 §1.5 硬边界）；
  // 卡脚只放「整卡结论」= 第三方送达与隐私政策出处，字段级说明留在井下方。只读井走
  // ReadonlyField 单源件（值 2 行：环境串整行都要看见）
  @Builder
  EnvCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('环境信息')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Blank()
        StatusBadge({ text: '自动附加', tone: BadgeTone.WEAK })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      ReadonlyField({ label: '本机', value: this.envLine, valueLines: 2 })
      Text('只附加系统版本、应用版本与设备型号，不包含聊天内容、密钥或文件。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Divider()
        .strokeWidth(0.5)
        .color(cardBorderColor(this.appColorMode))
        .margin({ top: 10 })
      Text('反馈经第三方推送服务送达开发者，详见更多信息页的隐私政策。')
        .fontSize(CARD_NOTE_FONTSIZE)
        .fontColor(cardDescColor())
        .width('100%')
        .margin({ top: 10 })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    // Stack 叠加（SystemPromptPage 同款吸底结构）：滚动区全高，发送键条悬浮底部、条透明
    // 不挂材质（内容滚到条后透出）；滚动内容底部让位条高（BOTTOM_BAR_RESERVE）
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          this.IntroCard()
          this.FormCard()
          this.EnvCard()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（首元素静止时完整落在渐变模糊蒙层下方）+ 底部让位键条
        .padding({ top: this.topPad, bottom: this.bottomPad + BOTTOM_BAR_RESERVE })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)

      // 吸底发送键条（条透明；交互区 = 按钮本体，条内边距不含命中区）
      Column() {
        Button(this.sending ? '发送中' : '发送反馈')
          .width(CARD_PANEL_WIDTH)
          .enabled(!this.sending)
          .opacity(this.sending ? 0.6 : 1)
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支）
    PageShell({
      title: SETTING_TITLE_FEEDBACK,
      content: () => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
