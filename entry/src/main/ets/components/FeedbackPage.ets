// 「反馈与建议」页（2026-09-07 新增；同日入口定更多信息页行卡〔帮助中心行卡下方，自
// 关于页卡片移入，决明指令〕——应用内反馈，链路与选型见
// docs/调研-应用内反馈方案与Cube-Meow链路逆向-20260907.md 第六节 V2 口径：纯客户端零
// 服务器，正文 + 环境信息一行 POST 到 MeoW 推送服务（common/FeedbackMeow.ets）→ 开发者
// 手机 MeoW 弹系统推送）。
// 表单形制照 Cube 反馈页裁剪：类型 chip / 截图 / 联系方式 / 工单通知开关不做——无工单
// 后端回不了用户，只留「标题 + 正文 + 环境信息自动附」；标题 = 用户简述问题类型（选填，
// 20 字内，随反馈作为推送正文首行，见 FeedbackMeow 头注释——推送标题保持固定前缀）；
// 说明小字置操作键上方（宪法「功能设置卡布局次序」口径：先说明后操作）。
// ★ 字段版式照会话提示词编辑页（PromptEditPage「名称/内容」字段——黑色板块小标题 +
// 官方默认输入框，2026-09-07 决明指令「改成类似会话提示词编辑页形式」；标题/正文两字段
// 组同构）。
// 隐私披露三处同步：本页说明行 + 隐私政策第四节（2026-09-07 补写）+ 帮助中心条目。
// 页面骨架 PageShell；提交键 = 内容区 fallbackButton* 双态族（2026-09-03 内容区回退规约，
// CropStageView「下一步」同构，primary=true 官方强调蓝 + 恒白字）；toast 走 UIContext +
// 光感材质（AboutPage 同款）。
import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, cardTitleColor, SECTION_TITLE_FONTSIZE } from '../common/Theme';
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

// 反馈正文上限（MeoW 官方未给消息上限，500 字对问题描述足够且推送卡片长度可控）
const FEEDBACK_MAX_LENGTH: number = 500;
// 反馈标题上限（简述问题类型，20 字内——随推送作为正文首行，长度可控）
const FEEDBACK_TITLE_MAX_LENGTH: number = 20;

@Component
export struct FeedbackPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（创建后不变，普通成员——
  // 状态最小化，AboutPage 先例）
  topPad: number = 0;
  // 沉浸光感档位 + 内容区回退开关（AppStorage 自订阅：toast 材质 / 提交键双态）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 反馈标题（TextInput 双向；用户简述问题类型，选填——未填则推送正文无标题行）
  @State titleText: string = '';
  // 反馈正文（TextArea 双向）
  @State content: string = '';
  // 发送中（防重复提交：按钮禁用 + 直接 return）
  @State sending: boolean = false;
  // 环境信息行（aboutToAppear 组装一次，页面生命周期内不变；只拼进推送文本不驱动 UI
  // ——状态最小化，普通成员）
  private envLine: string = '';

  aboutToAppear(): void {
    this.envLine = this.readEnvLine();
  }

  // 环境信息：版本运行期读 bundleManager（AboutPage 同款同步 API）；系统版本 = 官方
  // deviceInfo 三段字段拼接（d.ts 明示优于解析 osFullName——无前缀无 build 串，产出
  // 「6.1.1」式纯版本；@since 6 本 SDK 可用）；机型与 API 版本 = 官方只读常量（均
  // systemGrant，非敏感项）。失败版本显示「未知」不阻断（P0-1 日志留痕，AboutPage 同款）
  private readEnvLine(): string {
    let version: string = '未知';
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      version = info.versionName;
    } catch (err) {
      console.error('read bundle info failed: ' + JSON.stringify(err));
    }
    const osVer: string = deviceInfo.majorVersion + '.' + deviceInfo.seniorVersion + '.' + deviceInfo.featureVersion;
    return '版本 ' + version + ' · 系统 ' + osVer + ' (API ' + deviceInfo.sdkApiVersion + ') · ' + deviceInfo.productModel;
  }

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

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——AboutPage 坑同款）
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 说明段（先说明后操作——宪法「功能设置卡布局次序」）
          Text('遇到问题或有改进想法都可以写在这里，发送后会直接送达开发者。')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .lineHeight(21)
            .width(CARD_PANEL_WIDTH)
          // 标题字段组（2026-09-07 新增；版式照 PromptEditPage「名称」字段——黑色板块
          // 小标题 + 官方默认 TextInput，同日决明指令改编辑页同款表单形态）；
          // 内容 = 用户简述问题类型——随反馈作为推送正文首行；选填留空——未填则无标题行
          Column({ space: 6 }) {
            Text('标题')
              .fontSize(SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .width('100%')
            TextInput({ placeholder: '简述问题类型，例如 崩溃、建议', text: this.titleText })
              .width('100%')
              .maxLength(FEEDBACK_TITLE_MAX_LENGTH)
              .onChange((value: string): void => {
                this.titleText = value;
              })
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(HorizontalAlign.Start)
          // 正文字段组（版式照 PromptEditPage「内容」字段——与标题字段组同构；
          // 同日一并改编辑页形态，两输入控件统一不分裂）
          Column({ space: 6 }) {
            Text('内容')
              .fontSize(SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .width('100%')
            TextArea({ placeholder: '描述遇到的问题或建议，例如搜索结果排版错乱', text: this.content })
              .width('100%')
              .height(160)
              .maxLength(FEEDBACK_MAX_LENGTH)
              .onChange((value: string): void => {
                this.content = value;
              })
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(HorizontalAlign.Start)
          // 两行说明小字（隐私披露，措辞受「面向用户文案写作规约」约束）
          Text('将随反馈附上应用版本、系统版本与设备型号用于定位问题，不含聊天内容与密钥。')
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .lineHeight(18)
            .width(CARD_PANEL_WIDTH)
          Text('反馈经第三方推送服务送达开发者，详见更多信息页的隐私政策。')
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .lineHeight(18)
            .width(CARD_PANEL_WIDTH)
          // 主操作键（内容区 fallbackButton* 双态族，primary=true 官方强调蓝 + 恒白字；
          // 发送中禁用 + 半透明，标签随态）
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
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（规范同 AboutPage：首元素静止时完整落在渐变模糊蒙层下方）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center——同 AboutPage）
      .align(Alignment.TopStart)
      // 官方边缘回弹：滑到边界继续滑一段距离、松手回弹
      .edgeEffect(EdgeEffect.Spring)
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
}
