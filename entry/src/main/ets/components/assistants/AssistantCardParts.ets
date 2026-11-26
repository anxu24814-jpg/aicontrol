// 助手卡共享零件：三态头像（含编辑角标）、灰字计数胶囊与编辑页参数接口三节。
//（跨页头像一镜到底已退役——官方明示共享元素须关系统默认转场，页面转场必然与其他页
// 不同，决明真机两轮验收不达标后回撤，见文件内「共享元素退役说明」节注释）
//（「当前」徽章已换共享件 StatusBadge 实底胶囊，勾号强调形随唯一消费方消失而退役——
// 本件只剩灰胶囊计数形态）。
// · 为何独立成件（反碎片下限②登记）：两页共用而交互各自不同（一级页点卡进编辑页 + 卡内
//   更多键菜单；编辑页头像热区 + 改名键），落在任一页面件里都会让另一页反向依赖页面文件；
//   头像三态分流与编辑页编排 / 存储层删助手级联共用 AvatarSpec 编码，同处一份。
// · ★ 刷新责任在调用方（GroupSettingCard「开关显示刷新责任在调用方」同款分工）：两件入参
//   均为普通成员，父状态变化**不会**自动更新本件——调用方要么让本件重建（一级页 = ForEach
//   键含 cardEpoch 纪元；编辑页 = 单元素 ForEach 键 = 头像串），要么不刷新。**禁 @Prop**
//  （规范 §3 黑名单：PageShell.content / bindSheet builder 组内组件入参 @Prop 不随父
//   @State 更新，坑16 家族实锤）。
// · 三态（avatarKind 分流，编码单源 AvatarSpec）：image 且未失败 = 图片（加载失败 onError
//   置 imageFailed 回退首字，不静默——日志留痕）；text = 文字/表情（同色底 +
//   minFontSize/maxFontSize 自适应，1 字满 28、2 字自动缩，禁按字数硬编码字号）；''
//  （默认）或 image 失败 = 首字底（空名兜底 '?'）。默认态/文字态 = 名称首字身份色 + 16
//   圆角方形（取色单源 = Theme.identityBg/identityFg——六色双档淡底深字、随 appColorMode
//   分深浅，seed = 全串散列，判据 = docs/规范-视觉色板与徽标.md）；图片态不受影响。
// · 编辑角标（仅 editable）：22×22 圆（cardBg 底 + 强调色铅笔符号），位于头像右下角，
//   **纯视觉零点击**——热区 = 外层 Stack 整块，是否响应只看 onEditClick 是否传入
//  （一级页不传 ⇒ hitTestBehavior(None) 点击穿透卡体，卡体点击仍是「进编辑页」）。
//   角标几何真机若不醒目，退路 = 照 RikkaHub 形（浅底圆 + 深图标），只改本件一处。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AVATAR_KIND_IMAGE, AVATAR_KIND_TEXT, avatarKind, avatarValue } from '../../common/AvatarSpec';
import { badgeBg, cardBg, cardDescColor, identityBg, identityFg } from '../../common/Theme';

// ═══ 共享元素退役说明（2026-11-01，两千零五十二节）═══
// 跨页头像一镜到底（geometryTransition + animateTo 弹簧 + push/pop animated:false）经两轮
// 官方 demo 形制落地仍真机不达标：页面转场与其他页不一致（关默认转场后新页弹簧展开）+
// 头像闪动不连续。官方《Navigation转场动画》明示「配置了共享元素转场的页面，同时需要关闭
// 系统默认的转场动画，否则默认动画会与共享元素动画叠加，导致效果异常」——「与其他页一致
// 的滑动转场 + 头像连续飞行」官方不可兼得，故整体回撤为普通转场。勿再为头像单件重建跨页
// morph；附件查看器（AttachmentUtil.sharedGeomId 一族）为整页模态场景，不在本退役面。

// 编辑页 push 参数（首帧种子）：编辑页异步读库前先直赋 avatar/name——进页首帧即真头像与
// 名称，防读库空窗 '?' 占位跳变；DB 仍为真相源，读库同值不触发单元素 ForEach 键变重建。
// 接口落本件（两页同用）= 避免页面互依，照 AttachmentViewerParam 先例
export interface AssistantEditParam {
  id: string;
  avatar: string;
  name: string;
}

@Component
export struct AssistantAvatar {
  // 头像编码原串（AvatarSpec 形态：'' / 'text:<内容>' / 'image:<uri>'——普通成员，
  // 刷新责任在调用方键变重建，见头注释）
  spec: string = '';
  // 头像边长 vp（默认 64 = 一级页/编辑页原固定值；消息轮头传 32。**命名禁 size**——与
  // CustomComponent 基类属性方法同名会编译报冲突实锤）。圆角与两行文字区字号按边长等比
  // 派生（圆角 64 基准 16、32 得 8；字号 64 基准 14/28、32 得 7/14）；编辑角标恒 22 不随缩
  avatarSize: number = 64;
  // 首字兜底文本（默认态与图片加载失败态都用它；编辑页传 this.name、一级页传 row.name）
  fallbackText: string = '';
  // 编辑态：true = 叠编辑角标。是否响应点击只看 onEditClick 是否传入（角标纯视觉，
  // 热区 = 本件外层 Stack 整块）
  editable: boolean = false;
  onEditClick?: () => void;
  // 图片加载失败兜底标记（网络地址失效/沙箱文件已清）——@State 驱动本件重回首字分支；
  // 本件随键变重建时自然复位
  @State private imageFailed: boolean = false;
  // 系统颜色模式（角标底色 cardBg 深浅分治）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 头像圆角（16 圆角方形，64 基准 16 / 32 得 8）——与文字区字号同走边长等比派生，消费侧禁另写半径
  private avatarRadius(): number {
    return Math.round(this.avatarSize * 16 / 64);
  }

  // 头像主体（avatarSize 方框——三态分流；build 内直读 this.spec，随本件重建取新值）
  @Builder
  AvatarBody() {
    if (avatarKind(this.spec) === AVATAR_KIND_IMAGE && !this.imageFailed) {
      Image(avatarValue(this.spec))
        .objectFit(ImageFit.Cover)
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.avatarRadius())
        .clip(true)
        .onError((): void => {
          this.imageFailed = true;
          hilog.error(0xD5A4, 'AssistantCardParts', 'avatar image load failed: %{public}s', avatarValue(this.spec));
        })
    } else if (avatarKind(this.spec) === AVATAR_KIND_TEXT) {
      Text(avatarValue(this.spec))
        .minFontSize(Math.round(this.avatarSize * 14 / 64))
        .maxFontSize(Math.round(this.avatarSize * 28 / 64))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .fontWeight(FontWeight.Medium)
        .fontColor(identityFg(this.fallbackText, this.appColorMode))
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.avatarRadius())
        .backgroundColor(identityBg(this.fallbackText, this.appColorMode))
    } else {
      // 默认态与图片失败态共用的首字底（编辑页详情卡 / 一级页助手卡 / 消息轮头三处同形，
      // 空名兜底 '?'；底色 = 名称首字身份色）
      Text(this.fallbackText !== '' ? this.fallbackText.substring(0, 1) : '?')
        .fontSize(Math.round(this.avatarSize * 28 / 64))
        .fontWeight(FontWeight.Medium)
        .fontColor(identityFg(this.fallbackText, this.appColorMode))
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.avatarRadius())
        .backgroundColor(identityBg(this.fallbackText, this.appColorMode))
        .textAlign(TextAlign.Center)
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.AvatarBody()
      if (this.editable) {
        // 编辑角标（纯视觉零点击——铅笔符号提示「可换形象」，响应面在下方 Stack 整块；
        // 底色 cardBg 与头像身份色底拉开层次，深浅随动）
        Row() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(12)
            .fontColor([$r('sys.color.ohos_id_color_emphasize')])
        }
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor(cardBg(this.appColorMode))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
    }
    // 热区 = 外层 Stack 整块（含角标——「整个头像都是编辑键热区」拍板口径）；未传
    // onEditClick（一级页）= None 点击穿透卡体，不吞「点卡进编辑页」
    .hitTestBehavior(this.onEditClick !== undefined ? HitTestMode.Default : HitTestMode.None)
    .onClick((): void => {
      if (this.onEditClick !== undefined) {
        this.onEditClick();
      }
    })
  }
}

@Component
export struct AssistantChip {
  // chip 文本（普通成员——ForEach 键 = 文本本身，文本变即重建取新值）
  text: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    // 灰字计数胶囊（服务商卡 Badge 同款——badgeBg 半透明底 / 10fp / 内边距 6-2 / 圆角 6；
    // 原勾号 + 强调色「当前」形已随实底统一笔退役，唯一消费方一级页改 StatusBadge）
    Text(this.text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }
}
