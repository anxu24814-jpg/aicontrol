// 「权限信息」页（自 dshinhm 同名页改写迁移；参照系统「设置 → 应用 → 应用详情 → 权限」页）：
// 展示应用在 module.json5 requestPermissions 声明的全部权限 + 运行期授予状态，外加「免权限
// 功能」说明卡（无模块声明，kind=note 区分，复用同款卡片样式，状态列显示固定文案）。
// aicontrol 事实基线（内容按本项目实际列写）：
// · 声明权限十条（module.json5 requestPermissions 全量；2026-11-17 整体退役加密会话笔删
//   ACCESS_BIOMETRIC；2026-11-25 思考档位滑轨逐档触觉笔加 VIBRATE）：六条 system_grant 开放权限——
//   - ohos.permission.INTERNET——连接云端 AI 服务、获取模型列表、联网搜索、提交反馈；
//   - ohos.permission.STORE_PERSISTENT_DATA——设备内持久保存应用数据与访问密钥
//    （KeyStore Asset IS_PERSISTENT 持久属性，卸载不清除）；
//   - ohos.permission.FILE_ACCESS_PERSIST——文件夹挂载的系统目录授权写入持久化；
//   - ohos.permission.GET_WIFI_INFO——读本机 WLAN IP 供 Web 服务地址行显示
//    （wifiManager.getIpInfo；normal 级 system_grant，官方受限表无本条、无 ACL 门槛）；
//   - ohos.permission.DETECT_GESTURE（2026-10-25）——motion.on('holdingHandChanged')
//     声明权限，会话列表右下悬浮新建键随左右手握持换到同侧（消费方 components/chat/
//     SessionNewFab；normal + system_grant + since 20，本机 SDK 权限库实读）；
//   - ohos.permission.VIBRATE（2026-11-25）——Slider `enableHapticFeedback` 的声明权限，
//     思考档位滑轨每过一档一记触觉（消费方 components/chat/ThinkingLevelPanel；normal +
//     system_grant + since 7，官方「开放权限（系统授权）」页与本机 SDK 权限库双查）；
//   四枚 user_grant 开放权限（均 normal 级）——
//   - APPROXIMATELY_LOCATION / LOCATION——对话中按需获取当前位置（ToolLocation 执行器），
//     首次调用经 requestPermissionsFromUser 弹窗授权（精准必须与模糊同时申请，官方要求），
//     拒绝后错误文案引导系统设置开启；
//   - READ_CALENDAR / WRITE_CALENDAR——对话中按需查询、创建、修改与删除日程
//    （ToolCalendar 执行器；只读写本应用创建的日程，官方操作范围表口径），首次调用双权
//     一次弹窗授权，拒绝后错误文案引导系统设置开启；
// · 背景图片选择走 photoAccessHelper.PhotoViewPicker 官方系统选择器——免权限（先例
//   BackgroundPanel），做 note 说明卡；
// · 聊天附件三入口（cameraPicker saveUri 预创建 / PhotoViewPicker / DocumentViewPicker
//   context 构造）同为官方系统选择器组件——免权限（AttachmentPickCtrl 头注释实锤），
//   同做 note 说明卡；
// · 后台回复提醒：短时任务官方「导入模块，无需配置权限」+ 通知发布仅需系统授权（非权限
//   声明）——零新增权限（域④拍板红线），做 note 说明卡（本页是应用里唯一向用户解释
//   「后台还会跑」的位置）；
// · ⚠️ 权限等级红线（READ_IMAGEVIDEO 为 system_basic 受限权限，普通应用 APL=normal 声明
//   即安装失败 code 9568289——dshinhm 安装实测教训随迁）：新增权限前必须先在官方「开放
//   权限（系统授权）」列表确认权限级别为 normal，再进 module.json5 + PERMISSION_ITEMS +
//   帮助「权限信息」条目（三处同改），三者由 scripts/permission-sync-check.mjs 校验
//  （交付门禁子检查）；
// · 底部提示句语义：六条 system_grant 声明即授予 + 定位与日历四枚 user_grant 首次使用时
//   询问——「定位与日历权限在首次使用相关功能时询问授权，其余声明权限均由系统自动授予」，
//   状态列对十条都有效（user_grant 按运行期授权态显示待授权/已授予/已拒绝）。权限名单表
//   单源 = permission-sync-check.mjs KNOWN_SYSTEM_GRANT / KNOWN_USER_GRANT 两表（检查 11
//   表外即红 + 检查 12 user_grant 必配 reason/usedScene）。
// · 状态查询 = abilityAccessCtrl.getSelfPermissionStatus(@since 20，同步返回 PermissionStatus
//   枚举，无需 tokenID)+ 异常 try/catch（BusinessError 1210000x，不静默）。
// 数据源约定：declared 条目与 entry/src/main/module.json5 requestPermissions 同步维护——
// 新增权限时三处同改（module.json5 / 本表 / 帮助「权限信息」条目），本页自动展示；note
// 条目随免权限功能增删（无模块声明、不进 module.json5），功能定义处同步。
import { abilityAccessCtrl, bundleManager, common, ConfigurationConstant, Permissions, Want } from '@kit.AbilityKit';
import { HdsListItemCard, SuffixText } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CARD_PANEL_WIDTH,
  CARD_SPACING,
  cardBg,
  CARD_RADIUS
} from '../common/Theme';
import { SETTING_TITLE_PERMISSION } from '../common/SettingSearch';
import { InfoCard } from './InfoCard';
import { PageShell } from '../common/PageShell';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBgOffCard,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../common/ImmersiveLevel';

// 权限条目（页内数据源；name 与 module.json5 同步维护——类型用官方 Permissions 联合，
// 拼错的权限名编译期即报）。kind 区分两种：declared = 模块声明权限（状态运行期查询）；
// note = 免权限功能说明卡（无 module.json5 声明，status 为固定文案，样式与声明卡一致）
interface PermissionItem {
  // 条目类型：declared = 模块声明权限（状态运行期查询）；note = 免权限功能说明卡
  //（无 module.json5 声明，status 为固定文案，样式与声明卡一致）
  kind: 'declared' | 'note';
  // 权限名（kind=declared 时 = module.json5 requestPermissions 的字面量副本；note 时无）
  name?: Permissions;
  // 中文名（使用户明白该权限用途）
  title: string;
  // 用途说明（副标题；从简短句，不做场景解释——决明定稿）
  desc: string;
  // 状态文案（declared：aboutToAppear 查询后填充；note：固定文案，不查询）
  status: string;
}

// 权限清单（顺序 = 展示顺序；★ declared 条目与 entry/src/main/module.json5 同步维护——
// 新增权限三处同改，module.json5 / 本表 / 帮助「权限信息」条目）。描述从简（决明定稿：
// 短句即可，不做场景解释——同系统权限页「条目 + 状态」形态）
const PERMISSION_ITEMS: PermissionItem[] = [
  {
    kind: 'declared',
    name: 'ohos.permission.INTERNET',
    title: '网络访问',
    desc: '连接云端 AI 服务接口',
    status: ''
  },
  // 持久化数据存储：KeyStore Asset IS_PERSISTENT 持久属性所依赖的声明权限
  {
    kind: 'declared',
    name: 'ohos.permission.STORE_PERSISTENT_DATA',
    title: '持久化数据存储',
    desc: '保存密钥等长期保留的数据',
    status: ''
  },
  // 定位双权限（user_grant）：首次在对话中使用「获取当前位置」工具时弹窗申请
  //（ToolLocation.ensurePermissions，双权一次申请）
  {
    kind: 'declared',
    name: 'ohos.permission.APPROXIMATELY_LOCATION',
    title: '模糊位置',
    desc: '对话中按需获取模糊位置',
    status: ''
  },
  {
    kind: 'declared',
    name: 'ohos.permission.LOCATION',
    title: '精准位置',
    desc: '对话中按需获取精准位置',
    status: ''
  },
  // 日历双权限（user_grant）：首次在对话中使用日程工具（查询/创建/修改/删除）时弹窗申请
  //（ToolCalendar 执行器首步，双权一次申请）
  {
    kind: 'declared',
    name: 'ohos.permission.READ_CALENDAR',
    title: '读取日历',
    desc: '对话中按需查询日程',
    status: ''
  },
  {
    kind: 'declared',
    name: 'ohos.permission.WRITE_CALENDAR',
    title: '写入日历',
    desc: '对话中按需创建与修改日程',
    status: ''
  },
  // 文件夹授权持久化（system_grant）：fileShare 持久化接口的声明权限——「文件夹挂载」页
  // 添加挂载时把系统目录选择器的临时授权写入系统数据库，重启后仍可访问（官方《授权持久化》
  // 篇；★ 上架 ACL 项——须经 AGC ACL 申请并写入发布 Profile，核对法见 permission-sync-check.mjs）
  {
    kind: 'declared',
    name: 'ohos.permission.FILE_ACCESS_PERSIST',
    title: '文件授权持久化',
    desc: '记住授权给 AI 访问的文件夹',
    status: ''
  },
  // WLAN 信息读取（system_grant）：wifiManager.getIpInfo 读本机 WLAN IP，Web 服务地址行
  // 显示用（normal 级、官方受限开放权限表无本条、无 ACL 门槛——取证件 =
  // permission-sync-check.mjs KNOWN_SYSTEM_GRANT 表注释）
  {
    kind: 'declared',
    name: 'ohos.permission.GET_WIFI_INFO',
    title: 'WLAN 信息',
    desc: '获取本机局域网地址，开启 Web 服务后供浏览器访问',
    status: ''
  },
  // 智感握姿感知（system_grant）：motion.on('holdingHandChanged') 的声明权限——会话列表
  // 右下悬浮新建键随左右手握持换到同侧（消费方 = components/chat/SessionNewFab；normal +
  // system_grant + since 20 本机 SDK 实读，provisionEnable = false 佐证无上架 ACL 门槛）
  {
    kind: 'declared',
    name: 'ohos.permission.DETECT_GESTURE',
    title: '握持姿态感知',
    desc: '新建会话键跟随左右手握持',
    status: ''
  },
  // 振动反馈（system_grant）：Slider enableHapticFeedback 的声明权限——思考档位滑轨每过一档
  // 一记触觉（消费方 = components/chat/ThinkingLevelPanel；normal + system_grant + since 7，
  // 官方「开放权限（系统授权）」页实查，provisionEnable = false 佐证无上架 ACL 门槛）
  {
    kind: 'declared',
    name: 'ohos.permission.VIBRATE',
    title: '振动反馈',
    desc: '选择思考档位时提供触感',
    status: ''
  },
  // 免权限说明卡：背景图片选择走官方系统选择器（photoAccessHelper.PhotoViewPicker），
  // 无权限声明也无授权请求（BackgroundPanel 先例）
  {
    kind: 'note',
    title: '图片选择',
    desc: '背景图片经官方系统选择器选取',
    status: '免权限'
  },
  // 免权限说明卡：聊天附件三入口 = cameraPicker（saveUri 预创建覆盖写——免相机权限）/
  // PhotoViewPicker / DocumentViewPicker（context 构造）——均官方系统选择器组件，无权限
  // 声明（AttachmentPickCtrl 头注释实锤）
  {
    kind: 'note',
    title: '附件选择',
    desc: '拍照、照片、文件经官方系统选择器选取',
    status: '免权限'
  },
  // 免权限说明卡：后台回复提醒 = 短时任务（官方无需权限）+ 通知发布（仅系统授权，非权限
  // 声明）——module.json5 与本页权限列表零新增（零新增权限为域④拍板红线）
  {
    kind: 'note',
    title: '后台回复提醒',
    desc: '开启后切到后台会继续生成，完成后发通知',
    status: '免权限'
  }
];

@Component
export struct PermissionPage {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（首个控件静止时完整落在
  // 渐变模糊蒙层下方；回退路径传 0）。创建后不变，用普通成员（状态最小化）
  topPad: number = 0;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新配色；HDS 卡底取色用）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位 + 内容区回退能力位（内容区次钮四件套消费；AppStorage 订阅式切换即刷，
  // 坑16 正解）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 权限条目 + 状态（aboutToAppear 查询后赋值，驱动卡片渲染）
  @State permissions: PermissionItem[] = [];

  // 查询单条权限状态枚举（同步 API；失败返回 undefined 由上层按「未授予」处理，不静默）
  private queryPermissionStatus(name: Permissions): abilityAccessCtrl.PermissionStatus | undefined {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      return atManager.getSelfPermissionStatus(name);
    } catch (err) {
      hilog.error(0xD5A0, 'PermissionPage', 'query permission status failed: %{public}s', JSON.stringify(err));
      return undefined;
    }
  }

  // 全量刷新（map 新数组一次性赋 @State：一次刷新；初始填充与页面重新显示共用）——每条
  // declared 权限只查一次状态；note 条目不查（status 为固定文案），原样透传
  private refreshPermissions(): void {
    this.permissions = PERMISSION_ITEMS.map((item: PermissionItem): PermissionItem => {
      if (item.kind === 'note') {
        return { kind: item.kind, title: item.title, desc: item.desc, status: item.status };
      }
      const status: abilityAccessCtrl.PermissionStatus | undefined =
        this.queryPermissionStatus(item.name as Permissions);
      let statusText: string = '未知';
      switch (status) {
        case abilityAccessCtrl.PermissionStatus.GRANTED:
          statusText = '已授予';
          break;
        case abilityAccessCtrl.PermissionStatus.DENIED:
          statusText = '已拒绝';
          break;
        case abilityAccessCtrl.PermissionStatus.NOT_DETERMINED:
          statusText = '待授权';
          break;
        case abilityAccessCtrl.PermissionStatus.INVALID:
          statusText = '未声明';
          break;
        case abilityAccessCtrl.PermissionStatus.RESTRICTED:
          statusText = '受限';
          break;
        default:
          break;
      }
      return {
        kind: item.kind,
        name: item.name,
        title: item.title,
        desc: item.desc,
        status: statusText
      };
    });
  }

  aboutToAppear(): void {
    this.refreshPermissions();
  }

  // 打开系统设置的本应用权限管理页：官方 FAQ faqs-access-control-16 形态——显式拉起设置
  // 应用，uri application_info_entry + pushParams 传本应用包名；官方支持页、零权限（显式
  // Want 拉系统应用不受 API>11 三方应用跳转限制）；包名运行期读（禁写字面量）。失败
  // toast——用户主动点击场景不静默（P0-1）
  private openSystemPermissionSettings(): void {
    let bundleName: string = '';
    try {
      bundleName = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).name;
    } catch (err) {
      hilog.error(0xD5A0, 'PermissionPage', 'read bundle name failed: %{public}s', JSON.stringify(err));
    }
    if (bundleName === '') {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开系统设置，请稍后重试' });
      return;
    }
    try {
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: { pushParams: bundleName }
      };
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility(want).catch((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '无法打开系统设置，请稍后重试' });
      });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开系统设置，请稍后重试' });
    }
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——同 AboutPage 坑）
    Column() {
      Scroll() {
        Column() {
          // 分组小标题「允许"<应用名>"访问」（参考图「允许"浏览器"访问」；应用名走
          // app_name 资源不写字面量）。width(CARD_PANEL_WIDTH) 使文本区与 HDS 卡同宽、
          // 左沿对齐（HDS 卡实际渲染宽 = 容器 100%−32vp，AGENTS.md「列表卡片规范」）
          Text() {
            Span('允许"')
            Span($r('app.string.app_name'))
            Span('"访问')
          }
          .width(CARD_PANEL_WIDTH)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          // 小标题与卡片列间距（小标题非卡片，12vp 分区间距；卡片间距离仍由容器 space 管理）
          .margin({ bottom: 12 })

          // 卡片列：卡片间距统一由容器 space 管理（CARD_SPACING，先例 AboutPage/MyPage）
          Column({ space: CARD_SPACING }) {
            // 权限条目（每条一张卡片；declared 状态列 = 运行期授予状态）。note 免权限说明卡
            // 走 InfoCard 单源件；declared 条目走官方 HDS 卡
            ForEach(this.permissions, (item: PermissionItem) => {
              if (item.kind === 'note') {
                InfoCard({ title: item.title, text: item.desc + '，无需申请权限。' })
              } else {
                // normal 权限（无开关）：官方 HDS 卡片 + 右侧状态文字（官方纯文字后缀）
                HdsListItemCard({
                  textItem: {
                    primaryText: { text: item.title },
                    secondaryText: { text: item.desc }
                  },
                  suffixItem: new SuffixText({ text: item.status }),
                  cardBorderRadius: CARD_RADIUS,
                  // 卡底随全局透明档（HDS 补传 cardBg，重建层缺省参体内读键）
                  cardBackgroundColor: cardBg(this.appColorMode)
                })
              }
            }, (item: PermissionItem) => item.title)
          }
          .width('100%')

          // 前往系统设置的本应用权限管理页：次要操作非保存类——内容区次钮四件套，本键坐
          // 页底非白卡面，浅色底取白（见 ImmersiveLevel.fallbackButtonBgOffCard）；宽与卡体对齐
          Button('在系统设置中管理权限')
            .width(CARD_PANEL_WIDTH)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .margin({ top: 12 })
            .onClick((): void => {
              this.openSystemPermissionSettings();
            })

          // 底部提示（system_grant 自动授予 + user_grant 首次询问——与头部事实基线同步改；
          // ★ 宽度 = CARD_PANEL_WIDTH 与卡体对齐，禁全宽〔决明指令〕；fontSize/textAlign 是
          // Text 属性，Column 容器不能挂）
          Column({ space: 4 }) {
            Text('定位与日历权限在首次使用相关功能时询问授权，其余声明权限均由系统自动授予')
              .fontSize(13)
              .fontColor($r('sys.color.font_tertiary'))
              .textAlign(TextAlign.Center)
              .width(CARD_PANEL_WIDTH)
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（规范同 AboutPage：首元素静止时完整落在渐变模糊蒙层下方）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（2026-08-20 根因修复：Scroll align 默认 Center——同 AboutPage）
      .align(Alignment.TopStart)
      // 官方边缘回弹：滑到边界继续滑一段距离、松手回弹
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏）；
    // onShown 透传：页面每次重新显示时全量刷新（刷新通道唯一——本页无权限变化订阅）
    PageShell({
      title: SETTING_TITLE_PERMISSION,
      onShown: () => {
        this.refreshPermissions();
      },
      content: () => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
