// 「权限信息」页（2026-08-29 M3 自 dshinhm 同名页改写迁移；2026-09-07 起入口自关于页
// 卡片迁为「更多信息」页行卡；参照系统
// 「设置 → 应用 → 应用详情 → 权限」页）：展示应用在 module.json5 requestPermissions 声明的
// 全部权限 + 运行期授予状态，外加「免权限功能」说明卡（无模块声明，kind=note 区分，复用
// 同款卡片样式，状态列显示固定文案）。
// aicontrol 事实基线（拍板 5：内容按本项目实际列写；2026-09-11 补齐三条声明权限）：
// · 声明权限三条（module.json5 requestPermissions 全量，均 system_grant 开放权限）：
//   - ohos.permission.INTERNET（M1 起）——连接云端 AI 服务、获取模型列表、联网搜索、
//     提交反馈；
//   - ohos.permission.STORE_PERSISTENT_DATA（API 11 起）——设备内持久保存应用数据与
//     访问密钥（KeyStore Asset IS_PERSISTENT 持久属性，卸载不清除）；
//   - ohos.permission.ACCESS_BIOMETRIC（API 6 起）——打开加密会话时验证身份
//     （BiometricGate）。
// · 背景图片选择走 photoAccessHelper.PhotoViewPicker 官方系统选择器——免权限（dshinhm
//   实测在案，先例 BackgroundPanel），做 note 说明卡；
// · 聊天附件三入口（cameraPicker saveUri 预创建 / PhotoViewPicker / DocumentViewPicker
//   context 构造）同为官方系统选择器组件——免权限（AttachmentPickCtrl 头注释实锤），
//   同做 note 说明卡（「附件选择」，2026-08-31 领导指令）；
// · ⚠️ 权限等级红线（dshinhm 2026-08-23 安装实测教训随迁：READ_IMAGEVIDEO 为
//   system_basic 受限权限，普通应用 APL=normal 声明即安装失败 code 9568289）：新增权限
//   前必须先在官方「开放权限（系统授权）」列表确认权限级别为 normal，再进 module.json5 +
//   PERMISSION_ITEMS + 帮助「权限信息」条目（三处同改），三者由
//   scripts/permission-sync-check.mjs 校验（交付门禁子检查）；
// · 底部提示句「声明权限均由系统自动授予」的成立前提 = 三条全 system_grant（声明即授予，
//   状态列恒「已授予」）。今后若新增 user_grant（用户授权）权限，本句与状态列语义须同步
//   改——permission-sync-check 检查 11 会因表外权限报红（KNOWN_SYSTEM_GRANT 表先补）。
// · 状态查询 = abilityAccessCtrl.getSelfPermissionStatus(@since 20，同步返回 PermissionStatus
//   枚举，无需 tokenID)+ 异常 try/catch（BusinessError 1210000x，不静默）。
// 数据源约定：declared 条目与 entry/src/main/module.json5 requestPermissions 同步维护——
// 新增权限时三处同改（module.json5 / 本表 / 帮助「权限信息」条目），本页自动展示；note
// 条目随免权限功能增删（无模块声明、不进 module.json5），功能定义处同步。
import { abilityAccessCtrl, ConfigurationConstant, Permissions } from '@kit.AbilityKit';
import { HdsListItemCard, SuffixText } from '@kit.UIDesignKit';
import {
  CARD_PANEL_WIDTH,
  CARD_SPACING,
  cardBg,
  cardDescColor,
  cardTitleColor
} from '../common/Theme';
import { SETTING_TITLE_PERMISSION } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';

// 权限条目（页内数据源；name 与 module.json5 同步维护——类型用官方 Permissions 联合，
// 拼错的权限名编译期即报）。kind 区分两种：declared = 模块声明权限（状态运行期查询）；
// note = 免权限功能说明卡（无 module.json5 声明，status 为固定文案，样式与声明卡一致）
interface PermissionItem {
  // 条目类型（2026-08-24 新增：附件选择/USB 连接两张说明卡）
  kind: 'declared' | 'note';
  // 权限名（kind=declared 时 = module.json5 requestPermissions 的字面量副本；note 时无）
  name?: Permissions;
  // 中文名（参考图权限主标题，使用户明白该权限用途）
  title: string;
  // 用途说明（副标题；从简短句，不做场景解释——2026-08-22 决明定稿）
  desc: string;
  // 状态文案（declared：aboutToAppear 查询后填充；note：固定文案，不查询）
  status: string;
}

// 权限清单（顺序 = 展示顺序；★ declared 条目与 entry/src/main/module.json5 同步维护——
// 新增权限三处同改，module.json5 / 本表 / 帮助「权限信息」条目）。描述从简（dshinhm 决明
// 定稿：短句即可，不做场景解释——同系统权限页「条目 + 状态」形态）
const PERMISSION_ITEMS: PermissionItem[] = [
  {
    kind: 'declared',
    name: 'ohos.permission.INTERNET',
    title: '网络访问',
    desc: '连接云端 AI 服务接口',
    status: ''
  },
  // 持久化数据存储（2026-09-11 补齐：KeyStore Asset IS_PERSISTENT 持久属性所依赖的
  // 声明权限，此前 module.json5 已声明而本表漏列——permission-sync-check 检查 3 所指形态）
  {
    kind: 'declared',
    name: 'ohos.permission.STORE_PERSISTENT_DATA',
    title: '持久化数据存储',
    desc: '保存密钥等长期保留的数据',
    status: ''
  },
  // 生物识别（2026-09-11 补齐：加密会话身份验证所依赖的声明权限，同上漏列补齐）
  {
    kind: 'declared',
    name: 'ohos.permission.ACCESS_BIOMETRIC',
    title: '生物识别',
    desc: '验证身份以打开加密会话',
    status: ''
  },
  // 免权限功能说明卡（kind=note）：背景图片选择走官方系统选择器（photoAccessHelper.
  // PhotoViewPicker），无权限声明也无授权请求（BackgroundPanel 先例，dshinhm 实测在案）
  {
    kind: 'note',
    title: '图片选择',
    desc: '背景图片走官方系统选择器',
    status: '免权限'
  },
  // 免权限功能说明卡（kind=note 续，2026-08-31 领导指令）：聊天附件三入口 = cameraPicker
  //（saveUri 预创建覆盖写——免相机权限）/ PhotoViewPicker / DocumentViewPicker（context
  // 构造）——均官方系统选择器组件，无权限声明（AttachmentPickCtrl 头注释实锤）
  {
    kind: 'note',
    title: '附件选择',
    desc: '拍照、照片、文件走官方系统选择器',
    status: '免权限'
  }
];

@Component
export struct PermissionPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（首个控件静止时完整落在
  // 渐变模糊蒙层下方；回退路径传 0）。创建后不变，用普通成员（状态最小化）
  topPad: number = 0;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新配色；回退卡片用）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 权限条目 + 状态（aboutToAppear 查询后赋值，驱动卡片渲染）
  @State permissions: PermissionItem[] = [];
  // 官方 HDS 列表项卡片可用性：syscap 自检（HdsListItemCard 要求 HDSComponent.Full）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // 查询单条权限状态枚举（同步 API；失败返回 undefined 由上层按「未授予」处理，不静默）
  private queryPermissionStatus(name: Permissions): abilityAccessCtrl.PermissionStatus | undefined {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      return atManager.getSelfPermissionStatus(name);
    } catch (err) {
      console.error('query permission status failed: ' + JSON.stringify(err));
      return undefined;
    }
  }

  // 全量刷新（map 新数组一次性赋 @State：一次刷新，状态最小化；初始填充与
  // 权限变化事件/页面重新显示（onShown）共用）——每条约权限只查一次状态；
  // note 条目不查（status 为固定文案），原样透传
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

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——同 AboutPage 坑）
    Column() {
      Scroll() {
        Column() {
          // 分组小标题「允许"<应用名>"访问」（参考图「允许"浏览器"访问」；应用名走
          // app_name 资源不写字面量）。width(CARD_PANEL_WIDTH) 使文本区与 HDS 卡同宽、
          // 左沿对齐（HDS 卡实际渲染宽 = 容器 100%−32vp，AGENTS.md「列表卡片规范」；
          // 回退路径自制卡同用 CARD_PANEL_WIDTH，两路径左沿一致）
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
            // 权限条目（每条一张卡片；declared 状态列 = 运行期授予状态，note 状态列 =
            // 固定「免权限/无需新增」文案——渲染分支共用，样式对齐）
            ForEach(this.permissions, (item: PermissionItem) => {
              if (this.hdsListCardAvailable) {
                // normal 权限（无开关）：官方 HDS 卡片 + 右侧状态文字（官方纯文字后缀）
                HdsListItemCard({
                  textItem: {
                    primaryText: { text: item.title },
                    secondaryText: { text: item.desc }
                  },
                  suffixItem: new SuffixText({ text: item.status }),
                  cardBorderRadius: 16
                })
              } else {
                // 回退：自制白底卡片（无 HDS Full 能力；normal 权限纯展示容器）
                Row() {
                  Column({ space: 4 }) {
                    Text(item.title)
                      .fontSize(16)
                      .fontColor(cardTitleColor())
                    Text(item.desc)
                      .fontSize(13)
                      .fontColor(cardDescColor())
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(item.status)
                    .fontSize(13)
                    .fontColor(cardDescColor())
                }
                .width(CARD_PANEL_WIDTH)
                .padding(16)
                .backgroundColor(cardBg(this.appColorMode))
                .borderRadius(16)
              }
            }, (item: PermissionItem) => item.title)
          }
          .width('100%')

          // 底部提示（normal 自动授予说明；样式同前——fontSize/textAlign 是 Text 属性，
          // Column 容器不能挂（首编踩坑，见变更记录））
          Column({ space: 4 }) {
            Text('声明权限均由系统自动授予')
              .fontSize(13)
              .fontColor($r('sys.color.font_tertiary'))
              .textAlign(TextAlign.Center)
              .width('100%')
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
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支）；
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
}
