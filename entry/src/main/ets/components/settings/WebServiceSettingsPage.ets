// Web 服务二级页（设置页卡5「网络」第二行「Web 服务」入口落点）：浏览器远程访问设置页。
// 两段式：①状态首卡 = 深色渐变 + 状态标签 + 深卡徽标（22vp 圆角矩形 + 6vp 点）→ 52vp 图标瓦片
// + 固定两行说明（minHeight 40）→ 分割线 → 32vp 卡底文字动作；状态只由徽标承担，四态共用同一
// 套元素、固定块 22/52/40/32 保证卡高不跳（禁随状态增删块）；深浅两档渐变 = Theme.HERO_CARD_*
//（网络出口卡同源）。②分板块组卡 =「基础网络」（访问地址/端口/仅本机访问）+「安全保护」
//（访问密码），行几何照组卡（60vp 行 / 38vp 彩底图标 / 0.5vp 分割线 / 左缩进 66）；末段
// InfoCard。图标取色 = SETTING_ICON_* + settingIconBg/FgOf，深浅随 appColorMode，不新增 hex。
// ★ 停止态启动卡不塌陷：地址/口令行保留显示，主开关回 off（端口/口令可在关态预先配置）——与
//   「关态整页只剩入口提示」口径的偏离已在施工报告登记，取舍以任务书为准。
// 主开关契约：**唯一控制面 = 卡底动作行**，onClick 走 handleMainSwitch（写 kill-switch 键 +
// manager.start/stop）——与「派生显示态禁挂 onChange」红线不冲突（徽标是派生态）。
// 状态联动：订阅 webServiceManager 状态监听（16 上限接口）刷新徽标与警示态；注册失败或栈下层
// 不刷新时由 PageShell onShown 现读兜底；aboutToAppear 注册 ↔ aboutToDisappear 注销成对。
// 端口：显示值 portInput 与键分离（输入中途不落盘），blur/提交时 clampWebPort 单源钳位落键
//（非法值回缺省 8800）；改端口下次开启生效。
// 口令：首开启为空自动生成 6 位数字码（generateWebPasscode 单源）；「换一个」重生成（validator
// 实时读键，旧口令即刻失效）；口令空且服务运行且非仅本机 = 警示态（鉴权 fail-closed）。
// 自包 PageShell 壳，无标题栏菜单键；写即持久化 → 返回无参 pop 不挂 onPop〔坑17〕；toast 走
// getPromptAction。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageShell } from '../../common/PageShell';
import {
 CARD_PANEL_WIDTH, SECTION_GAP, SECTION_HEADER_GAP, cardBg, cardBorderColor,
  cardDescColor, cardTitleColor, menuDividerColor, CARD_RADIUS,
  HERO_CARD_ACTION_HEIGHT, HERO_CARD_BADGE_BG, HERO_CARD_BADGE_TEXT,
  HERO_CARD_COPY_MIN_HEIGHT, HERO_CARD_DIVIDER, HERO_CARD_LABEL, HERO_CARD_SUCCESS,
  HERO_CARD_TEXT, HERO_CARD_TEXT_DIM, HERO_CARD_TILE_BG, HERO_CARD_TILE_RADIUS,
  HERO_CARD_TILE_SIZE, heroCardColors, heroCardMidColor
} from '../../common/Theme';
import { clampWebPort, PREF_WEB_SERVICE_ENABLE_KEY,
  PREF_WEB_SERVICE_LOOPBACK_ONLY_KEY, PREF_WEB_SERVICE_PASSCODE_KEY,
  PREF_WEB_SERVICE_PORT_KEY, WEB_SERVICE_PORT_DEFAULT,
  webServicePort } from '../../common/AppPreferencesWeb';
import { webServiceManager, WebServiceState, WebStateListener } from '../../common/web/WebServiceManager';
import { generateWebPasscode } from '../../common/web/WebAuthValidator';
import { SETTING_TITLE_WEB_SERVICE } from '../../common/SettingSearch';
import { DIVIDER_LEFT_ICON_LARGE, SETTING_ICON_BLUE, SETTING_ICON_PURPLE,
  SettingRowIcon } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { InfoCard } from '../InfoCard';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial,
  resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { copyTextToClipboard } from '../../common/Clipboard';
import { InputDialog } from '../chat/InputDialog';

const PAGE_LOG_DOMAIN: number = 0xD5A0;
const PAGE_LOG_TAG: string = 'WebServiceSettingsPage';

// 状态监听适配器（ArkTS 组件内不能声明类——文件级实现 manager 的 WebStateListener 接口）
class WebPageStateListener implements WebStateListener {
  private readonly onState: (to: WebServiceState) => void;

  constructor(onState: (to: WebServiceState) => void) {
    this.onState = onState;
  }

  onWebServiceStateChanged(_from: WebServiceState, to: WebServiceState): void {
    this.onState(to);
  }
}

// 端口输入长度上限（5 位——上界 65534 为五位数，maxLength 预检 + clamp 兜底双闸）
const PORT_INPUT_MAX_LEN: number = 5;

@Component
export struct WebServiceSettingsPage {
  // 页面存活守卫（离页后监听回调不写状态——与成对注销双保险）
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 服务四态镜像（manager 状态监听回调刷新——驱动徽标与警示态两处 UI）
  @State mgrState: string = 'stopped';
  // 主开关 = kill-switch 总开关键（写即持久化；manager.start() 入口闸同一键）
  @StorageLink(PREF_WEB_SERVICE_ENABLE_KEY) serviceEnabled: boolean = false;
  // 端口键（显示值 portInput 分离；blur 时钳位落键）
  @StorageLink(PREF_WEB_SERVICE_PORT_KEY) portNum: number = WEB_SERVICE_PORT_DEFAULT;
  @State portInput: string = '';
  // 口令键（'' = 未生成；首开启自动生成，「换一个」重生成）
  @StorageLink(PREF_WEB_SERVICE_PASSCODE_KEY) passcode: string = '';
  // 仅本机档键（true = 绑 127.0.0.1 且免鉴权）
  @StorageLink(PREF_WEB_SERVICE_LOOPBACK_ONLY_KEY) loopbackOnly: boolean = false;
  // 启停在途闸（start/stop 异步——期间禁再点开关防状态竞）
  @State switching: boolean = false;
  // 面板材质订阅（菜单 systemMaterial 消费）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 图标外观恒彩色 + 圆角矩形（偏好已退役、底形由 SettingRowIcon 内部固化），本页不订阅开关
  // 状态监听器成员（注册 ↔ 注销成对的锚点）
  private stateListener: WebPageStateListener | null = null;
  // 本机局域网 IP 缓存（getIpInfo 是同步系统调用，禁在 @Builder 内直调——进页/回显/起服边沿取
  // 一次；'' = 无 Wi-Fi，显示引导文案）
  @State lanIp: string = '';

  aboutToAppear(): void {
    this.mgrState = webServiceManager.currentState();
    this.portInput = webServicePort().toString();
    this.lanIp = webServiceManager.getLocalLanIp();
    const listener: WebPageStateListener = new WebPageStateListener(
      (to: WebServiceState): void => {
        if (!this.departed) {
          this.mgrState = to;
          if (to === 'running') {
            // 起服边沿刷新一次（网络可能在后台期间切换）
            this.lanIp = webServiceManager.getLocalLanIp();
          }
        }
      });
    const ok: boolean = webServiceManager.registerStateListener(listener);
    if (ok) {
      this.stateListener = listener;
    }
    // 注册失败（16 上限满员）不静默：徽标靠 onShown 现读兜底刷新，启停仍可用
    if (!ok) {
      hilog.warn(PAGE_LOG_DOMAIN, PAGE_LOG_TAG, '状态监听注册失败，onShown 现读兜底');
    }
  }

  aboutToDisappear(): void {
    this.departed = true;
    if (this.stateListener !== null) {
      webServiceManager.unregisterStateListener(this.stateListener);
      this.stateListener = null;
    }
  }

  // ── 派生显示（@Builder 内直调现读，禁值参快照）──

  // 状态徽标文案（四态 → 四词：运行中 / 启动中 / 已暂停 / 已停止）
  private badgeTextOf(state: string): string {
    if (state === 'running') {
      return '运行中';
    }
    if (state === 'starting') {
      return '启动中';
    }
    if (state === 'paused') {
      return '已暂停';
    }
    return '已停止';
  }

  // 访问地址行（loopback 档显 127.0.0.1；无 Wi-Fi 显引导文案不显残址）：运行中显示**实际监听**
  // 端口/绑定档（activeHttpPort/activeBindAddress），停止/暂停态显示配置值；IP 走 lanIp 缓存
  private addressText(): string {
    const running: boolean = this.mgrState === 'running';
    const port: number = running ? webServiceManager.activeHttpPort() : webServicePort();
    const loopback: boolean = running
      ? webServiceManager.activeBindAddress() === '127.0.0.1' : this.loopbackOnly;
    if (loopback) {
      return 'http://127.0.0.1:' + port.toString();
    }
    if (this.lanIp === '') {
      return '连接 Wi-Fi 后显示地址';
    }
    return 'http://' + this.lanIp + ':' + port.toString();
  }

  // 口令行显示值（'' = 未生成；生成链在开关开启与「换一个」两处）
  private passcodeText(): string {
    return this.passcode === '' ? '未生成' : this.passcode;
  }

  // 警示态：口令空且服务运行且非仅本机——鉴权 fail-closed 下局域网连接全拒，如实警示
  private passcodeWarnVisible(): boolean {
    return this.mgrState === 'running' && this.passcode === '' && !this.loopbackOnly;
  }

  // ── 动作 ──

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 主开关翻转（kill-switch 键同步写 + manager 启停；失败回滚开关态）
  private handleMainSwitch(isOn: boolean): void {
    if (this.switching) {
      return;
    }
    this.switching = true;
    if (isOn) {
      // 首开启口令为空 → 自动生成 6 位数字码（写键即持久化；validator 实时读键）
      if (this.passcode === '') {
        this.passcode = generateWebPasscode();
      }
      this.serviceEnabled = true;
      webServiceManager.start().then((result): void => {
        if (!result.ok) {
          // 启动失败回滚开关（端口被占等——message 带中文原因，toast 不静默）
          this.serviceEnabled = false;
          if (!this.departed) {
            this.toast(result.message);
          }
        }
        if (!this.departed) {
          this.switching = false;
        }
      }).catch((): void => {
        this.serviceEnabled = false;
        if (!this.departed) {
          this.switching = false;
        }
      });
    } else {
      this.serviceEnabled = false;
      webServiceManager.stop().then((result): void => {
        if (!result.ok && !this.departed) {
          this.toast(result.message);
        }
        if (!this.departed) {
          this.switching = false;
        }
      }).catch((): void => {
        if (!this.departed) {
          this.switching = false;
        }
      });
    }
  }

  // 端口输入落键（blur/提交两入口）：空还原当前生效值；越界/非法经 clampWebPort 单源钳位
  //（1024~65534，界外回缺省 8800）
  private applyPortInput(): void {
    if (this.portInput === '') {
      this.portInput = webServicePort().toString();
      return;
    }
    const raw: number = parseInt(this.portInput);
    const clamped: number = clampWebPort(raw);
    if (clamped !== raw && !this.departed) {
      this.toast('端口须在 1024 到 65534 之间，已调整为 ' + clamped.toString());
    }
    this.portNum = clamped;
    this.portInput = clamped.toString();
  }

  // 「换一个」：重生成 6 位口令（旧口令即刻失效——连接须凭新码重新鉴权）
  private regeneratePasscode(): void {
    this.passcode = generateWebPasscode();
    this.toast('口令已更新');
  }

  private copyAddress(): void {
    copyTextToClipboard(this.getUIContext(), this.addressText(), '地址已复制');
  }

  private copyPasscode(): void {
    if (this.passcode === '') {
      this.toast('口令未生成，开启服务时自动生成');
      return;
    }
    copyTextToClipboard(this.getUIContext(), this.passcode, '口令已复制');
  }

  // 仅本机档翻转（键写即持久化）：绑定地址收窄在下次启停生效；运行中切换时 validator 立即
  // 拒绝非回环来源〔安全收紧〕，toast 告知重启服务完成收口
  private handleLoopbackSwitch(isOn: boolean): void {
    this.loopbackOnly = isOn;
    if (this.mgrState === 'running' || this.mgrState === 'paused') {
      this.toast('重新开启服务后仅本机生效');
    }
  }

  // 自定义访问密码弹窗（构造在成员位——坑7；打开前按当前值重建）。约束 6 位数字：网页端口令
  // 输入框是 6 位数字键盘（只收数字且长度恰 6），放开长度/字符会让浏览器端输不进来。
  private passcodeCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '自定义访问密码',
      placeholder: '6 位数字',
      confirmLabel: '保存',
      number: true,
      maxLength: 6,
      onConfirm: (text: string): void => {
        this.applyCustomPasscode(text);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  private openCustomPasscode(): void {
    this.passcodeCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '自定义访问密码',
        initialText: this.passcode,
        placeholder: '6 位数字',
        confirmLabel: '保存',
        number: true,
        maxLength: 6,
        onConfirm: (text: string): void => {
          this.applyCustomPasscode(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.passcodeCtrl.open();
  }

  private applyCustomPasscode(raw: string): void {
    const text: string = raw.trim();
    if (!/^[0-9]{6}$/.test(text)) {
      this.toast('访问密码须为 6 位数字');
      return;
    }
    if (text === this.passcode) {
      return;
    }
    this.passcode = text;
    this.toast('访问密码已更新');
  }

  // 地址刷新（无 Wi-Fi 时回引导文案，不显残址——与 addressText 同判据）
  private refreshLanIp(): void {
    this.lanIp = webServiceManager.getLocalLanIp();
    this.toast(this.lanIp === '' ? '未连接 Wi-Fi' : '地址已刷新');
  }

  // ── 视图件 ──

  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // 副标题 / 主按钮文案（四态派生——@Builder 内不写分支常量）
  private statusSubtitle(): string {
    if (this.mgrState === 'running') {
      return '同一局域网的设备可用浏览器访问网页版';
    }
    if (this.mgrState === 'starting') {
      return '正在监听端口，请稍候';
    }
    if (this.mgrState === 'paused') {
      return '手机退到后台时服务暂停，回到前台自动恢复';
    }
    return '开启后可通过浏览器访问网页版，退后台即暂停';
  }

  private primaryLabel(): string {
    if (this.mgrState === 'starting') {
      return '启动中…';
    }
    return this.mgrState === 'stopped' ? '启动' : '停止';
  }

  // 动作行方向：仅 stopped 是「开启」，running/paused 都是「停止」
  private primaryTurnsOn(): boolean {
    return this.mgrState === 'stopped';
  }

  // 动作行图标：启动方向（stopped / starting）= play_fill，其余 = power（starting 也要播放方向，
  // 避免「启动中」配电源键的语义错位）
  private primaryIcon(): Resource {
    return this.primaryTurnsOn() || this.mgrState === 'starting' ?
      $r('sys.symbol.play_fill') : $r('sys.symbol.power');
  }

  // 行分割线（彩底行左缩进 66vp = 标题左缘，与组卡同口径：图标视觉右缘 53 + 间距 13）
  @Builder
  RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(cardBorderColor(this.appColorMode))
      .margin({ left: DIVIDER_LEFT_ICON_LARGE, right: 12 })
  }

  // 行尾「更多」键（点阵符号 + 官方 TEXTUAL；次级操作收进菜单，行尾只留一个入口）
  @Builder
  AddressMoreKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .bindMenu(this.AddressMenu, {
      placement: Placement.BottomRight,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
        this.immersiveLevel, true)
    })
  }

  @Builder
  PasscodeMoreKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .bindMenu(this.PasscodeMenu, {
      placement: Placement.BottomRight,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
        this.immersiveLevel, true)
    })
  }

  // 地址菜单：复制 / 刷新（刷新用于换网络后不再退出重进）
  @Builder
  AddressMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_filled_on_doc')),
        content: '复制地址'
      })
        .onClick((): void => {
          this.copyAddress();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')),
        content: '刷新地址'
      })
        .onClick((): void => {
          this.refreshLanIp();
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  // 口令菜单：复制 / 随机生成 / 自定义（自定义仍收 6 位数字，与网页端输码口径一致）
  @Builder
  PasscodeMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_filled_on_doc')),
        content: '复制密码'
      })
        .onClick((): void => {
          this.copyPasscode();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')),
        content: '随机生成'
      })
        .onClick((): void => {
          this.regeneratePasscode();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        content: '自定义密码…'
      })
        .onClick((): void => {
          this.openCustomPasscode();
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  // 状态首卡（固定块 22/52/40/32 保证四态卡高不跳；动作行 = kill-switch 唯一控制面）
  @Builder
  StatusCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('服务状态')
          .fontSize(13)
          .fontColor(HERO_CARD_LABEL)
        Blank()
        // 深卡徽标：22vp 半透明圆角矩形 + 6vp 点（与网络出口卡同形）；StatusBadge 四档绑浅色
        // 语义板、不能落深卡，故徽标内联读 mgrState
        Row({ space: 5 }) {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.mgrState === 'running' ? HERO_CARD_SUCCESS : HERO_CARD_TEXT_DIM)
          Text(this.badgeTextOf(this.mgrState))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(HERO_CARD_BADGE_TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .height(22)
        .padding({ left: 8, right: 8 })
        .borderRadius(6)
        .backgroundColor(HERO_CARD_BADGE_BG)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 图标瓦片 52 定主行高；说明块 minHeight 40 让 starting 单行与其余两行态同高
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.website'))
            .fontSize(26)
            .fontColor([HERO_CARD_TEXT])
        }
        .width(HERO_CARD_TILE_SIZE)
        .height(HERO_CARD_TILE_SIZE)
        .borderRadius(HERO_CARD_TILE_RADIUS)
        .backgroundColor(HERO_CARD_TILE_BG)
        .justifyContent(FlexAlign.Center)
        Column() {
          Text(this.statusSubtitle())
            .fontSize(13)
            .fontColor(HERO_CARD_LABEL)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: HERO_CARD_COPY_MIN_HEIGHT })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Divider()
        .strokeWidth(0.5)
        .color(HERO_CARD_DIVIDER)
        .margin({ top: 4 })
      Row({ space: 6 }) {
        SymbolGlyph(this.primaryIcon())
          .fontSize(16)
          .fontColor([HERO_CARD_TEXT])
        Text(this.primaryLabel())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HERO_CARD_TEXT)
      }
      .width('100%')
      .height(HERO_CARD_ACTION_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .opacity(this.switching ? 0.6 : 1)
      .onClick((): void => {
        if (!this.switching) {
          this.handleMainSwitch(this.primaryTurnsOn());
        }
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(heroCardMidColor(this.isDarkMode()))
    .linearGradient({
      angle: 135,
      colors: heroCardColors(this.isDarkMode())
    })
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 基础网络卡：访问地址（只读 + 复制）/ 端口 / 仅本机访问
  @Builder
  NetworkCard() {
    Column() {
      Row({ space: 16 }) {
        SettingRowIcon($r('sys.symbol.website'), SETTING_ICON_BLUE, this.isDarkMode(), 3)
        Column({ space: 2 }) {
          Text('访问地址')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.addressText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        this.AddressMoreKey()
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      this.RowDivider()
      Row({ space: 16 }) {
        SettingRowIcon($r('sys.symbol.list_number'), SETTING_ICON_BLUE, this.isDarkMode(), 3)
        Column({ space: 2 }) {
          Text('端口')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('修改后重新开启服务生效')
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        TextInput({ placeholder: '8800', text: this.portInput })
          .type(InputType.Number)
          .maxLength(PORT_INPUT_MAX_LEN)
          .width(76)
          .height(36)
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .onChange((value: string): void => {
            // 只留数字（数字键盘仍可能带入非数字字符——预检一道，钳位兜底在 blur）
            this.portInput = value.replace(/[^0-9]/g, '');
          })
          .onBlur((): void => {
            this.applyPortInput();
          })
          .onSubmit((): void => {
            this.applyPortInput();
          })
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      this.RowDivider()
      Row({ space: 16 }) {
        SettingRowIcon($r('sys.symbol.wifi'), SETTING_ICON_BLUE, this.isDarkMode(), 3)
        Column({ space: 2 }) {
          Text('仅本机访问')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('只接受本机连接，可免口令')
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.loopbackOnly })
          .onChange((on: boolean): void => {
            this.handleLoopbackSwitch(on);
          })
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .width(CARD_PANEL_WIDTH)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  // 安全保护卡：访问密码（显示 + 换一个 + 复制）
  @Builder
  SecurityCard() {
    Column() {
      Row({ space: 16 }) {
        SettingRowIcon($r('sys.symbol.key'), SETTING_ICON_PURPLE, this.isDarkMode(), 3)
        Column({ space: 2 }) {
          Text('访问密码')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.passcode === '' ? '未生成，开启服务时自动生成' : this.passcodeText())
            .fontSize(13)
            .fontColor(this.passcode === '' ? cardDescColor() : cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        this.PasscodeMoreKey()
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .width(CARD_PANEL_WIDTH)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  @Builder
  Content() {
    Scroll() {
      // 间距三档走 Theme 常量（SECTION_GAP / SECTION_HEADER_GAP，禁写字面量；条文 = 列表卡规范）
      Column({ space: SECTION_GAP }) {
        this.StatusCard()
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: '基础网络' })
          this.NetworkCard()
        }
        .width('100%')
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: '安全保护' })
          this.SecurityCard()
          if (this.passcodeWarnVisible()) {
            Text('口令未设置，局域网连接将被全部拒绝')
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width(CARD_PANEL_WIDTH)
              .padding({ left: 4 })
          }
        }
        .width('100%')
        InfoCard({
          text: '服务默认关闭。开启后同一局域网内的设备均可尝试连接，口令是唯一防线，请勿在不可信网络开启。'
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_WEB_SERVICE,
      // onShown 现读兜底（栈下层 @StorageProp 不刷新 + 监听注册失败的替代姿势；IP 同点刷新——
      // 离开期间网络可能变化，回显时取一次）
      onShown: (): void => {
        this.mgrState = webServiceManager.currentState();
        this.lanIp = webServiceManager.getLocalLanIp();
      },
      content: (): void => {
        this.Content()
      }
    })
  }
}
