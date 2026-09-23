// 「隐私政策」二级页（2026-09-02 新增；2026-09-07 起入口自「关于」页卡片迁为「更多信息」
// 页行卡——华为应用市场上架合规要求：
// 应用内须可查看隐私政策 + 上架材料需提供隐私政策 URL；本页为应用内展示入口，★ 2026-09-03
// 在线版已托管（GitHub Pages，决明提供地址）——底部链接行点击经官方 openLink 拉起系统
// 浏览器打开，应用内版与在线版同源同步维护）。版式随 OpenSourcePage 定稿：说明段（卡外）+
// 分节（节标题 + 正文段落），无卡片背景。
// ★ 文案事实基线（2026-09-02 按项目实际行为逐项核对，改动功能须同步核对本页）：
// ★ 政策写作口径（2026-09-07 决明拍板「全量优化，避免任何小改动都需变更政策」）：正文
//   只写功能级事实（数据类型、处理目的、第三方共享），不写 UI 入口路径、页面与卡片名、
//   实现细节（协议名、存储组件名、控件名）——入口迁移、UI 改名、界面微调无需动政策；
//   数据实践本身变化（新增数据类型、新增第三方共享、权限增减）仍属政策级变更，须同步
//   核对本页并更新日期。本页与 docs/官网/privacy.html（站点版）、docs/上架素材/隐私政策.html
//   三处正文逐字同文（2026-09-10 改：原文只写「两版」漏了站点版；机械兜底 =
//   scripts/site-version-check.mjs 第四段，三副本任一处漂移即红）。
// · 开发者不收集/不上传任何用户数据，应用无自有服务器（AboutPage「无云服务器」注释实锤；
//   ★ 2026-09-07 起唯一例外 = 应用内反馈功能用户主动提交的反馈转达，见第四节）；
// · 会话/消息/助手/提示词/服务商配置/偏好 = 本地 RDB 与 AppStorage persistProp
//   （ChatDb/AssistantDb/ProviderDb/PromptTemplateDb + common/AppPreferences.ets）；
// · API 密钥 = KeyStore（Asset Store Kit 系统加密存储），明文禁落 DB（ChatDbMigrate 头注释）；
// · 聊天消息与附件（多模态 images 字段，仅 user 消息）发往用户自配的第三方 AI 服务
//   （RequestCompose 头注释）；
// · 权限三条（2026-09-11 同步 PERMISSION_ITEMS 补齐笔）= ohos.permission.INTERNET
//   （连接云端 AI 服务、获取模型列表、联网搜索、提交反馈）+ ohos.permission.
//   STORE_PERSISTENT_DATA（设备内持久保存应用数据与访问密钥）+ ohos.permission.
//   ACCESS_BIOMETRIC（打开加密会话验证身份）；附件/背景选择走官方
//   系统选择器免权限（PermissionPage 头注释）；
// · 应用数据可能被系统备份能力备份（EntryBackupAbility，module.json5 声明）；
// · ★ 用户主动备份与迁移（2026-09-10 补入第四节）：应用内可将 9 表数据 + 偏好导出为备份
//   文件，落点由用户选（本机文件或用户自配的 WebDAV 网盘）；不含密钥档包内零明文，含密钥
//   档的密钥进 ProviderShare 加密件（口令用户自设、开发者无法获知）。政策级事实 =
//   「数据可离开设备，但由用户主动发起、去向用户自选、不经开发者任何服务器」。
// · ★ 联网搜索（2026-09-10 多引擎一期本体，同日补入第四节）：模型按对话内容生成搜索
//   关键词，该关键词发往搜索引擎服务地址（默认免 key 引擎，域名 bing.com；亦可为用户
//   自配的三家 API 引擎），返回网页内容作为对话上下文再发往用户自配的 AI 服务。政策级
//   事实 = 「对话内容可经搜索关键词与网页回灌两条路径离开设备，第三方 = 用户所选或默认
//   的搜索服务提供者」——★ 此前第四节的绝对句「除上述外不外传」未覆盖该路径（三百零二
//   节自检 P1 观察项，本条即其收口）。
// · CONTACT_EMAIL = 开发者真实联系方式（2026-09-07 定稿，现行值见下方常量），正文与
//   HTML 版同步。
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH } from '../common/Theme';
import { SETTING_TITLE_PRIVACY_POLICY } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';

// 开发者联系方式（正文与注释两处同步；2026-09-07 决明换号）
const CONTACT_EMAIL: string = '335164137@qq.com';
// 政策更新日期（文案修订时同步；2026-09-11 第五节补齐三条声明权限的用途、第八节补访问
// 密钥卸载不清除的例外口径——权限披露面与卸载口径两处政策级变更，日期随之更新）
const POLICY_DATE: string = '2026-09-11';
// 在线版政策托管地址（2026-09-03 决明提供：GitHub Pages，上架材料用；本页底部链接行
// 点击经官方 openLink 拉起系统浏览器打开）
const PRIVACY_URL: string = 'https://anxu24814-jpg.github.io/aicontrol-privacy/';

// 政策分节（节标题 + 正文；节间间距由容器 space 管理）
interface PolicySection {
  title: string;
  body: string;
}

const POLICY_SECTIONS: PolicySection[] = [
  {
    title: '一、引言',
    body: '本隐私政策适用于「AI 控制台」（以下简称"本应用"）。本应用是一款本地 AI 对话客户端：您自行配置 AI 服务的接入地址与访问密钥，本应用仅作为客户端协助您与该服务交互，不提供任何 AI 计算服务，也未运营任何服务器。使用本应用即表示您同意本政策的约定；如您不同意，请停止使用。'
  },
  {
    title: '二、我们收集的信息',
    body: '本应用无账号体系，不需要注册与实名信息。本应用的开发者不收集、不上传、不存储您的任何个人信息、聊天内容、附件或访问密钥——这些数据全部只存在于您的设备本地（详见下文）。本应用不含统计埋点、广告组件或第三方追踪组件。'
  },
  {
    title: '三、数据的本地存储',
    body: '您的会话与消息记录、助手与提示词等配置、AI 服务设置及应用偏好等数据，以加密数据库的形式保存在您的设备内；API 访问密钥使用系统安全加密存储保管，不会明文写入数据库或普通文件；您设置的背景图片、选择的附件等文件亦仅保存在设备本地。以上数据不会离开您的设备，除非您主动使用下文所述功能。'
  },
  {
    title: '四、数据对外传输',
    body: '仅当您在应用内发起 AI 对话时，本次会话的上下文消息会发送至您自行配置的第三方 AI 服务地址，以获取回复；如果您附加了图片或文件且所配置的模型支持多模态输入，附件将一并发送给该服务。该服务的数据处理受其提供者的规则约束，与本应用无关——请在配置前了解并信任您选择的服务商。若您开启并使用联网搜索功能，模型会根据对话内容生成搜索关键词，该关键词会发送至搜索引擎服务地址以获取结果，返回的网页内容随后作为对话上下文发送给您配置的 AI 服务；该搜索服务默认为无需密钥的必应搜索服务，您也可以改用自行配置密钥与地址的搜索引擎。上述搜索传输同样由您主动使用该功能触发，并受对应服务提供者的规则约束。除此之外，本应用不会向任何第三方传输您的数据；您配置的访问密钥仅作为所属请求的认证信息自动附带在上述发送行为中，不以其他形式流出，除非您主动将其纳入备份文件。若您使用应用内反馈功能主动提交反馈，您填写的反馈内容与自动附带的环境信息（应用版本、系统版本、设备型号）会经第三方推送服务 api.chuckfang.com 转达给开发者，仅用于处理反馈；不提交反馈则不发生该项传输。此外，本应用提供由您主动发起的备份与迁移功能：您可以将会话与消息记录、助手与提示词等配置、AI 服务设置与应用偏好导出为备份文件，保存到您的设备或您指定的位置，也可以上传到您自行配置的网络存储服务。备份默认不包含访问密钥；您也可以选择将访问密钥一并纳入备份，此时密钥内容会先经您设置的备份口令加密再打包，没有该口令无法读取，口令仅由您自己保管，开发者无法获知。上述导出与上传均由您主动发起，去向由您选择，数据不经过开发者的任何服务器；备份文件的保管与去向请您自行负责。'
  },
  {
    title: '五、权限使用',
    body: '本应用声明「网络访问」权限，用于连接您配置的 AI 服务、获取模型列表、执行联网搜索与提交反馈。声明「持久化数据存储」权限，用于在您的设备内持久保存应用数据与访问密钥，这些数据不会上传至开发者。声明「生物识别」权限，用于打开加密会话时验证您的身份，指纹与人脸信息由系统管理，本应用不获取、不存储、不上传任何生物特征数据。选择图片、文件与拍照均通过系统官方选择器完成，不需要存储或相机权限。'
  },
  {
    title: '六、AI 生成内容',
    body: '聊天回复由第三方 AI 模型生成，可能存在不准确或不符合预期的内容，仅供参考，请勿将其作为医疗、法律、投资等专业决策的唯一依据。'
  },
  {
    title: '七、运行日志',
    body: '应用维护的本地运行日志仅用于故障排查，保存在设备本地并设有容量上限，不会自动上传。'
  },
  {
    title: '八、数据删除',
    body: '您可以删除单个会话或全部会话记录，也可以在应用内删除访问密钥；卸载应用将删除本应用本地的全部数据（如需保留系统备份，见下节）。例外是保存在系统持久化存储中的访问密钥，卸载应用不会将其清除，需在应用内删除密钥，或在设备恢复出厂设置、重装系统时一并清除。'
  },
  {
    title: '九、系统备份',
    body: '本应用支持系统的应用数据备份能力（如华为云备份）：若您在系统设置中开启了相关功能，应用数据可能由系统统一备份与恢复，方便您换机或系统迁移；该备份由系统管理，您可随时在系统设置中关闭。'
  },
  {
    title: '十、未成年人保护',
    body: '若您未满 14 周岁，请在监护人陪同并同意本政策后使用本应用。'
  },
  {
    title: '十一、政策更新',
    body: '本政策可能因功能或法规要求调整而更新，更新后会在本应用内公布并标注新日期；重大变更将以显著方式提示。'
  },
  {
    title: '十二、联系我们',
    body: '如您对本政策或本应用的数据处理有任何疑问，请通过邮箱 ' + CONTACT_EMAIL + ' 与我们联系。'
  }
];

@Component
export struct PrivacyPolicyPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（首个控件静止时完整落在
  // 渐变模糊蒙层下方；回退路径传 0）。创建后不变，用普通成员（状态最小化）
  topPad: number = 0;
  // 沉浸光感档位（本页 toast 材质随沉浸光感总档——AboutPage 同款自订阅先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // 本页 toast 统一入口（2026-09-03 openLink 失败提示新增）：材质随沉浸光感总档
  //（基准 THICK = 官方默认档，AboutPage 同款）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false)
    });
  }

  // 在线版政策 → 系统浏览器（官方 UIAbilityContext.openLink，@since 12，d.ts 实锤；
  // 失败给中文提示——用户主动点击场景不静默（P0-1），与 ChatMessageItem 引文
  //「非关键路径静默」场景不同）
  private openPrivacyUrl(): void {
    (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(PRIVACY_URL)
      .catch((err: Error): void => {
        this.showToast('无法打开链接，请稍后重试');
      });
  }

  // 单个政策分节（标题 + 正文；纯静态展示无卡片背景）
  @Builder
  SectionBlock(section: PolicySection) {
    Column() {
      Text(section.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(section.body)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(22)
    }
    .width(CARD_PANEL_WIDTH)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——同 AboutPage 坑）
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 政策说明段（更新日期 + 宽 CARD_PANEL_WIDTH 与正文左沿对齐）
          Text('更新日期：' + POLICY_DATE)
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .width(CARD_PANEL_WIDTH)
            .margin({ bottom: 2 })

          ForEach(POLICY_SECTIONS, (section: PolicySection) => {
            this.SectionBlock(section)
          }, (section: PolicySection) => section.title)

          // 在线版政策链接行（2026-09-03）：一行 URL 文本，点击经官方 openLink 拉起系统
          // 浏览器打开（上架材料用——应用内展示入口 + 在线版同源；官方链接语义色深浅
          // 分治 + 下划线表可点；宽度/左沿同「更新日期」行口径）
          Text(PRIVACY_URL)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_hyperlink'))
            .decoration({ type: TextDecorationType.Underline })
            .width(CARD_PANEL_WIDTH)
            // ★ 长 URL 断行：Text 默认 BREAK_WORD 按词断（无空格长串整词换行可溢出）——
            // 显式 BREAK_ALL 按字符断（text.d.ts 实锤；URL 53 字符 > CARD_PANEL_WIDTH 必折行）
            .wordBreak(WordBreak.BREAK_ALL)
            // 2026-09-03 决明反馈「链接左右居中」：URL 文本在页面宽度内居中显示
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.openPrivacyUrl();
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
      title: SETTING_TITLE_PRIVACY_POLICY,
      content: () => {
        this.Content()
      }
    })
  }
}
