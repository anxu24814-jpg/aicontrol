// 网络设置二级页（设置页「网络」组卡的落点页）：三张内容卡——「当前出口」深色渐变卡 +「请求」卡
// （User-Agent / 请求读超时）+「代理」卡。
// · 出口卡：代理档位 / 出口延迟两行，进页自动 HEAD 探测一次、代理设置变化后 600ms 去抖重测、手动
//   「测试连接」同链（runExitProbe）；失败显示「检测失败」（探测服务在境外，不用「未连通」）。
//   深浅两套三停渐变 + 延迟主视觉 28fp；固定深色渐变卡 = K3 双页点名例外，不随卡底透明度档，第
//   三页须决明点名。createHttp ↔ finally destroy 成对，probeSeq 代次守卫旧结果，离页清定时器。
// · 「请求」卡：UA 留空 = 默认（defaultUserAgent 运行时拼版本号，禁硬编码）；读超时三档（5/10/20
//   分钟），只作用于聊天对话。
// · 「代理」卡：三档（跟随系统 / 直连 / 自定义地址）+ custom 档协议类型分段 / 账号 / 密码 / 绕过
//   列表。地址显示值与持久键分离——非法中途态只提示不落键。
// ★ 代理密码是全页唯一非「写即持久化」字段——只进 Asset（KeyStore，备份凭据块），onBlur 落盘后
//   清输入 + 状态行 + 清除键（SearchEngineDetailPage 密钥形制先例）。
// 自包 PageShell 壳，无标题栏菜单键；写即持久化（@StorageLink 一写即落盘、无保存动作 → 返回无参
// pop 不挂 onPop〔坑17〕，照 ToolsSettingsPage / PreferencesPage 滑轨卡契约）。形制照规范-列表卡片
// 与组卡 §1.1「选择/内容卡」；卡壳四件套 = CARD_PANEL_WIDTH / padding(16) / cardBg / CARD_RADIUS
//（宿主无左右 16vp padding，卡体恒挂卡宽基准，勿写 width('100%')）；说明小字在输入与操作行上方
//（宪法「功能设置卡布局次序」）；两分段卡契约照 ToolsSettingsPage 双 @Watch 互正形制。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import {
 CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING, SEGMENT_BAR_HEIGHT,
  cardBg, cardBorderColor, cardDescColor, cardTitleColor, CARD_RADIUS,
  HERO_CARD_ACTION_HEIGHT, HERO_CARD_BADGE_BG, HERO_CARD_BADGE_TEXT,
  HERO_CARD_DANGER, HERO_CARD_DIVIDER, HERO_CARD_LABEL, HERO_CARD_SUCCESS, HERO_CARD_TEXT,
  HERO_CARD_TEXT_DIM, HERO_CARD_TEXT_TESTING, heroCardColors, heroCardMidColor
} from '../../common/Theme';
import { clampNetProxyMode, clampNetReadTimeoutMinutes, NET_PROXY_MODE_CUSTOM,
  NET_PROXY_MODE_DIRECT, NET_PROXY_MODE_SYSTEM, NET_PROXY_TYPE_HTTP, NET_PROXY_TYPE_SOCKS5,
  NET_READ_TIMEOUT_MINUTES, NET_READ_TIMEOUT_MINUTES_DEFAULT, PREF_NET_PROXY_ADDR_KEY,
  PREF_NET_PROXY_BYPASS_KEY, PREF_NET_PROXY_MODE_KEY, PREF_NET_PROXY_TYPE_KEY,
  PREF_NET_PROXY_USER_KEY, PREF_NET_READ_TIMEOUT_MIN_KEY, PREF_USER_AGENT_KEY } from '../../common/AppPreferences';
import { SETTING_TITLE_NETWORK, SETTING_TITLE_PROXY, SETTING_TITLE_READ_TIMEOUT,
  SETTING_TITLE_USER_AGENT } from '../../common/SettingSearch';
import { applyEffectiveProxy, defaultUserAgent, parseNetProxyAddr,
  sanitizeUserAgent, setCachedProxyPassword, USER_AGENT_LEN_MAX } from '../../common/providers/RequestIdentity';
import { loadProxyPassword, removeProxyPassword, saveProxyPassword } from '../../common/store/KeyStore';
import { InfoCard } from '../InfoCard';
import { SegmentBar } from '../SegmentBar';

// 代理连通性测试（键常量本页单源）：HEAD 204 端点 + 10s 双超时；端点取境外连通性检查服务——
// custom 档测通即代理出网可用，direct 档在国内网络下失败属如实呈现（帮助「代理」条目同口径）
const PROXY_TEST_URL: string = 'https://www.gstatic.com/generate_204';
const PROXY_TEST_TIMEOUT_MS: number = 10000;
// 首卡「出口延迟」自动重测去抖：代理档位/协议/地址/密码连续变化时只在停手后发一次探测
const EXIT_PROBE_DEBOUNCE_MS: number = 600;

// ── 当前出口深色卡：色值/徽标/动作行几何单源 = Theme.HERO_CARD_*（K3 双页点名例外，第三页须决明点名）──
// 延迟主视觉块最小高：28fp 数字行约 39vp、16fp 文字行约 22vp——统一到 40 后两态卡高一致
const EXIT_LATENCY_BLOCK_MIN_HEIGHT: number = 40;

@Component
export struct NetworkSettingsPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 全局 UA 自定义值（写即持久化；'' = 用默认——取值与兜底写入单源 RequestIdentity）
  @StorageLink(PREF_USER_AGENT_KEY) userAgent: string = '';
  // 请求读超时档位键（写即持久化；@Watch 补正分段下标——备份导入等第二写键方在途时 UI 随键同步）
  @StorageLink(PREF_NET_READ_TIMEOUT_MIN_KEY) @Watch('onReadTimeoutKeyChanged')
  readTimeoutMin: number = NET_READ_TIMEOUT_MINUTES_DEFAULT;
  @State @Watch('onReadTimeoutSegChanged') readTimeoutSeg: number = 1;
  // 代理档位键 + 地址键（地址显示与落键分离：输入中途不落盘，合法或清空才写；取值侧
  // parseNetProxyAddr 再校验一次双保险）
  @StorageLink(PREF_NET_PROXY_MODE_KEY) @Watch('onProxyModeKeyChanged')
  proxyMode: string = NET_PROXY_MODE_SYSTEM;
  @State @Watch('onProxySegChanged') proxySeg: number = 0;
  @StorageLink(PREF_NET_PROXY_ADDR_KEY) @Watch('onProxyAddrKeyChanged') proxyAddr: string = '';
  @State proxyAddrInput: string = '';
  @State proxyAddrInvalid: boolean = false;
  // 代理协议类型 + 认证账号 + 绕过列表：类型分段照主档键双 @Watch 契约；账号与绕过列表写即
  // 持久化；密码只进 Asset（见文件头）——输入显示值与已配置态分离
  @StorageLink(PREF_NET_PROXY_TYPE_KEY) @Watch('onProxyTypeKeyChanged')
  proxyType: string = NET_PROXY_TYPE_HTTP;
  @State @Watch('onProxyTypeSegChanged') proxyTypeSeg: number = 0;
  @StorageLink(PREF_NET_PROXY_USER_KEY) proxyUser: string = '';
  @StorageLink(PREF_NET_PROXY_BYPASS_KEY) proxyBypass: string = '';
  @State proxyPasswordInput: string = '';
  @State proxyPasswordSaved: boolean = false;
  // 代理连通性测试在途闸（测试中禁连点；兼作首卡自动探测的在途闸——自动/手动共用一条链）
  @State proxyTesting: boolean = false;
  // 出口延迟显示文案与失败态：'' 尚未检测 → 检测中… / N ms / 检测失败 / 地址无效
  @State exitLatencyLabel: string = '尚未检测';
  @State exitLatencyFailed: boolean = false;
  // 最近一次探测完成的时刻（HH:mm；'' = 尚未完成过一轮）——卡内说明行用，别让用户猜延迟何时测的
  @State lastProbeAt: string = '';
  // 探测代次（设置变化即自增，作废在途旧结果——新旧档位的延迟不混写）
  private probeSeq: number = 0;
  // 去抖定时器（一个实例一个——离页清理）与在途期间收到的重测意图
  private probeTimer: number = -1;
  private probeQueued: boolean = false;
  // 分段选项（顺序契约：读超时 0/1/2 与 NET_READ_TIMEOUT_MINUTES 的 5/10/20 天然同序；
  // 代理 0/1/2 = 跟随系统 / 直连 / 自定义地址，勿乱调）
  private readTimeoutItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '5 分钟' },
    { text: '10 分钟' },
    { text: '20 分钟' }
  ]);
  private proxyItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '跟随系统' },
    { text: '直连' },
    { text: '自定义地址' }
  ]);
  // 协议类型分段选项（顺序契约：0/1 = HTTP / SOCKS5，与 proxyTypeSeg 映射互正，勿乱调）
  private proxyTypeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: 'HTTP' },
    { text: 'SOCKS5' }
  ]);

  aboutToAppear(): void {
    // 分段下标初始化（@StorageLink 直读盘上原始值，越界/非法经映射回退默认档；消费侧
    // netReadTimeoutMinutes / applyEffectiveProxy 同样钳制，双保险）
    this.readTimeoutSeg = this.readTimeoutToSeg(this.readTimeoutMin);
    this.proxySeg = this.proxyModeToSeg(this.proxyMode);
    this.proxyAddrInput = this.proxyAddr;
    this.proxyAddrInvalid = this.proxyAddr !== '' && parseNetProxyAddr(this.proxyAddr) === null;
    this.proxyTypeSeg = this.proxyType === NET_PROXY_TYPE_SOCKS5 ? 1 : 0;
    // 首卡出口延迟进页自动探测一次（无 toast——状态直接上卡；手动键同链并带 toast）
    this.runExitProbe(false);
    // 密码已配置态（UI 标记用——请求链的密码值走 EntryAbility 启动预载进 RequestIdentity 缓存，
    // 此处不回填缓存避免第二写路径）。读失败按未配置呈现并提示，不阻断页面
    loadProxyPassword().then((pw: string): void => {
      if (this.departed) {
        return;
      }
      this.proxyPasswordSaved = pw !== '';
    }).catch((e: Object): void => {
      if (this.departed) {
        return;
      }
      const code: number | undefined = (e as BusinessError).code;
      this.getUIContext().getPromptAction().showToast({
        message: '代理密码读取失败' + (code !== undefined ? ' ' + code : '')
      });
    });
  }

  // 读超时档位 ↔ 分段下标映射（白名单与下标天然同序；越界值钳制后仍不在白名单时回退默认档）
  private readTimeoutToSeg(value: number): number {
    const idx: number = NET_READ_TIMEOUT_MINUTES.indexOf(clampNetReadTimeoutMinutes(value));
    return idx >= 0 ? idx : NET_READ_TIMEOUT_MINUTES.indexOf(NET_READ_TIMEOUT_MINUTES_DEFAULT);
  }

  // 代理模式 ↔ 分段下标映射（非三值归 0 = 跟随系统，与 clampNetProxyMode 同语义）
  private proxyModeToSeg(mode: string): number {
    if (mode === NET_PROXY_MODE_DIRECT) {
      return 1;
    }
    return mode === NET_PROXY_MODE_CUSTOM ? 2 : 0;
  }

  private onReadTimeoutSegChanged(): void {
    const value: number = clampNetReadTimeoutMinutes(NET_READ_TIMEOUT_MINUTES[this.readTimeoutSeg]);
    if (value !== this.readTimeoutMin) {
      this.readTimeoutMin = value;
    }
  }

  // 读超时键第二写键方（备份导入恢复）→ 补正分段下标（@StorageLink 自动响应）
  private onReadTimeoutKeyChanged(): void {
    const seg: number = this.readTimeoutToSeg(this.readTimeoutMin);
    if (seg !== this.readTimeoutSeg) {
      this.readTimeoutSeg = seg;
    }
  }

  private onProxySegChanged(): void {
    const mode: string = this.proxySeg === 1 ? NET_PROXY_MODE_DIRECT :
      (this.proxySeg === 2 ? NET_PROXY_MODE_CUSTOM : NET_PROXY_MODE_SYSTEM);
    if (mode !== this.proxyMode) {
      this.proxyMode = mode;
    }
  }

  // 代理档键第二写键方 → 补正分段下标 + 首卡延迟重测（先作废在途结果，再走去抖重测）
  private onProxyModeKeyChanged(): void {
    const seg: number = this.proxyModeToSeg(this.proxyMode);
    if (seg !== this.proxySeg) {
      this.proxySeg = seg;
    }
    this.invalidateExitProbe();
  }

  // 代理地址键第二写键方 → 输入框显示值与非法提示同步 + 首卡延迟重测
  private onProxyAddrKeyChanged(): void {
    this.proxyAddrInput = this.proxyAddr;
    this.proxyAddrInvalid = this.proxyAddr !== '' && parseNetProxyAddr(this.proxyAddr) === null;
    this.invalidateExitProbe();
  }

  private onProxyTypeSegChanged(): void {
    const type: string = this.proxyTypeSeg === 1 ? NET_PROXY_TYPE_SOCKS5 : NET_PROXY_TYPE_HTTP;
    if (type !== this.proxyType) {
      this.proxyType = type;
    }
  }

  // 类型键第二写键方（备份导入恢复）→ 补正分段下标 + 首卡延迟重测
  private onProxyTypeKeyChanged(): void {
    const seg: number = this.proxyType === NET_PROXY_TYPE_SOCKS5 ? 1 : 0;
    if (seg !== this.proxyTypeSeg) {
      this.proxyTypeSeg = seg;
    }
    this.invalidateExitProbe();
  }

  // 密码 onBlur 落盘：留空 = 不改动；非空先删后加写 Asset（幂等）→ 同刷 RequestIdentity 内存缓存
  // → 清输入 + 状态行（SearchEngineDetailPage 密钥形制）；失败 toast 不静默，输入保留供重试
  private async saveProxyPasswordInput(): Promise<void> {
    const pw: string = this.proxyPasswordInput;
    if (pw === '') {
      return;
    }
    try {
      await saveProxyPassword(pw);
      if (this.departed) {
        return;
      }
      setCachedProxyPassword(pw);
      this.proxyPasswordSaved = true;
      this.proxyPasswordInput = '';
      this.getUIContext().getPromptAction().showToast({ message: '代理密码已保存' });
      // 认证信息变了，出口可用性可能随之变化 → 首卡延迟重测（去抖）
      this.invalidateExitProbe();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const code: number | undefined = (e as BusinessError).code;
      this.getUIContext().getPromptAction().showToast({
        message: '代理密码保存失败' + (code !== undefined ? ' ' + code : '')
      });
    }
  }

  // 清除密码（Asset 条目删除 → 缓存清零 → 状态行复原；失败 toast 不静默）
  private async clearProxyPassword(): Promise<void> {
    try {
      await removeProxyPassword();
      if (this.departed) {
        return;
      }
      setCachedProxyPassword('');
      this.proxyPasswordSaved = false;
      this.proxyPasswordInput = '';
      // 认证信息变了，出口可用性可能随之变化 → 首卡延迟重测（去抖）
      this.invalidateExitProbe();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const code: number | undefined = (e as BusinessError).code;
      this.getUIContext().getPromptAction().showToast({
        message: '代理密码清除失败' + (code !== undefined ? ' ' + code : '')
      });
    }
  }

  private proxyModeLabel(): string {
    if (this.proxyMode === NET_PROXY_MODE_DIRECT) {
      return '直连';
    }
    return this.proxyMode === NET_PROXY_MODE_CUSTOM ? '自定义地址' : '跟随系统';
  }

  // 延迟值字色：深色卡固定色——失败 = 浅红，检测中 = 90% 白，正常 = 纯白
  private exitLatencyColor(): ResourceColor {
    if (this.exitLatencyFailed) {
      return HERO_CARD_DANGER;
    }
    return this.proxyTesting ? HERO_CARD_TEXT_TESTING : HERO_CARD_TEXT;
  }

  // 设置变化 → 作废在途探测结果 + 去抖重测（四处 @Watch 与两处密码成功回调共用）
  private invalidateExitProbe(): void {
    if (this.departed) {
      return;
    }
    this.probeSeq += 1;
    this.scheduleExitProbe();
  }

  private scheduleExitProbe(): void {
    if (this.departed) {
      return;
    }
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
    }
    this.probeTimer = setTimeout((): void => {
      this.probeTimer = -1;
      this.runExitProbe(false);
    }, EXIT_PROBE_DEBOUNCE_MS);
  }

  // 「测试连接」（与首卡自动探测共用 runExitProbe）：按当前代理档实际发一次 HEAD 连通性检查——
  // applyEffectiveProxy 统一注入（custom 写解析后地址、direct 写 usingProxy:false、system 零介入），
  // 与聊天链同一条代理路径，结论才有代表性。本出口纯代理不吃 UA
  private async testProxyConnection(): Promise<void> {
    await this.runExitProbe(true);
  }

  // 出口探测单链（自动探测 showToast=false / 手动测试 true）：
  // · custom 档地址非法 → 不探测（applyEffectiveProxy 会钳回 system 档 = 测错对象），首卡显示
  //   「地址无效」，手动测试附中文 toast；
  // · 在途不重叠（proxyTesting 唯一闸；在途期重测意图排队一次，收尾后去抖补跑）；
  // · 代次守卫（probeSeq）——设置变化后旧请求迟到返回也不写首卡；
  // · 请求成对释放：createHttp ↔ finally destroy（二次释放异常不外抛）。
  private async runExitProbe(showToast: boolean): Promise<void> {
    if (this.departed) {
      return;
    }
    if (this.proxyMode === NET_PROXY_MODE_CUSTOM && parseNetProxyAddr(this.proxyAddr) === null) {
      this.exitLatencyLabel = '地址无效';
      this.exitLatencyFailed = true;
      // 地址已失效，旧的检测时刻不再代表当前配置（卡内说明行回「修正后自动检测」）
      this.lastProbeAt = '';
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({ message: '代理地址无效，请先修正后再测试' });
      }
      return;
    }
    if (this.proxyTesting) {
      this.probeQueued = true;
      return;
    }
    this.proxyTesting = true;
    this.probeSeq += 1;
    const seq: number = this.probeSeq;
    this.exitLatencyLabel = '检测中…';
    this.exitLatencyFailed = false;
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.HEAD,
      usingCache: false,
      connectTimeout: PROXY_TEST_TIMEOUT_MS,
      readTimeout: PROXY_TEST_TIMEOUT_MS
    };
    applyEffectiveProxy(options);
    const startedAt: number = Date.now();
    try {
      const resp: http.HttpResponse = await request.request(PROXY_TEST_URL, options);
      if (this.departed || seq !== this.probeSeq) {
        return;
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        this.exitLatencyLabel = Math.round(Date.now() - startedAt) + ' ms';
        this.exitLatencyFailed = false;
        this.lastProbeAt = this.clockLabel();
        if (showToast) {
          this.getUIContext().getPromptAction().showToast({ message: '测试连接成功' });
        }
      } else {
        this.exitLatencyLabel = '检测失败';
        this.exitLatencyFailed = true;
        this.lastProbeAt = this.clockLabel();
        if (showToast) {
          this.getUIContext().getPromptAction().showToast({
            message: '测试连接失败，HTTP ' + resp.responseCode
          });
        }
      }
    } catch (e) {
      if (this.departed || seq !== this.probeSeq) {
        return;
      }
      this.exitLatencyLabel = '检测失败';
      this.exitLatencyFailed = true;
      this.lastProbeAt = this.clockLabel();
      if (showToast) {
        const code: number | undefined = (e as BusinessError).code;
        this.getUIContext().getPromptAction().showToast({
          message: '测试连接失败' + (code !== undefined ? ' ' + code : '')
        });
      }
    } finally {
      // destroy 包 try（二次释放异常不得外抛——KeyConnectTester / OcrVisionApi 同款先例）
      try {
        request.destroy();
      } catch (err) {
      }
      if (!this.departed) {
        this.proxyTesting = false;
        if (this.probeQueued) {
          this.probeQueued = false;
          this.scheduleExitProbe();
        }
      }
    }
  }

  // 出口延迟是否为数值态（'NN ms'）——数值走 28fp 主视觉，文字态走 16fp（「检测失败」放大到 28
  // 会压过整页）
  private exitLatencyNumeric(): boolean {
    return this.exitLatencyLabel.endsWith(' ms');
  }

  private exitLatencyNumber(): string {
    return this.exitLatencyNumeric() ?
      this.exitLatencyLabel.substring(0, this.exitLatencyLabel.length - 3) : this.exitLatencyLabel;
  }

  private clockLabel(): string {
    const now: Date = new Date();
    const minutes: number = now.getMinutes();
    return (now.getHours() < 10 ? '0' : '') + now.getHours() + ':' +
      (minutes < 10 ? '0' : '') + minutes;
  }

  // 出口卡说明行：地址无效时讲下一步，测过讲时刻，没测过讲自动探测口径
  private probeHintLabel(): string {
    if (this.exitLatencyLabel === '地址无效') {
      return '修正地址后自动检测';
    }
    return this.lastProbeAt !== '' ? '最近检测 ' + this.lastProbeAt :
      '进页自动检测，代理设置变化后重新检测';
  }

  // 出口卡深浅档（渐变三停/中停色单源 = Theme.heroCardColors / heroCardMidColor）
  private exitCardDark(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // 首卡：当前出口（固定深色渐变卡，K3 双页点名例外）：深底 + 模式徽标 + 延迟主视觉 + 最近检测 +
  // 卡内测试连接。不随卡底透明度档；徽标用固定深底专用色（StatusBadge 绑浅色语义板不能直落深卡）
  @Builder
  ExitStatusCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('当前出口')
          .fontSize(13)
          .fontColor(HERO_CARD_LABEL)
        Blank()
        // 模式徽标：22vp 半透明圆角矩形 + 6vp 点（与全站状态徽标同形）；点色兼作状态（失败浅红，余浅绿）
        Row({ space: 5 }) {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.exitLatencyFailed ? HERO_CARD_DANGER : HERO_CARD_SUCCESS)
          Text(this.proxyModeLabel())
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
      if (this.exitLatencyNumeric()) {
        Row({ space: 5 }) {
          Text(this.exitLatencyNumber())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.exitLatencyColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('ms')
            .fontSize(13)
            .fontColor(HERO_CARD_TEXT_DIM)
            .margin({ bottom: 5 })
        }
        .width('100%')
        .constraintSize({ minHeight: EXIT_LATENCY_BLOCK_MIN_HEIGHT })
        .alignItems(VerticalAlign.Bottom)
      } else {
        // 文字态包同高块并底对齐：与数值态共用最小高，检测中/失败/地址无效切换时卡高不跳
        Row() {
          Text(this.exitLatencyLabel)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.exitLatencyColor())
            .width('100%')
        }
        .width('100%')
        .constraintSize({ minHeight: EXIT_LATENCY_BLOCK_MIN_HEIGHT })
        .alignItems(VerticalAlign.Bottom)
      }
      Text(this.probeHintLabel())
        .fontSize(13)
        .fontColor(HERO_CARD_TEXT_DIM)
        .width('100%')
      Divider()
        .strokeWidth(0.5)
        .color(HERO_CARD_DIVIDER)
        .margin({ top: 4 })
      // 卡内测试键（原代理卡底部全宽键移入；无实心底，图标 + 文字，测试中降不透明度）
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.bolt'))
          .fontSize(16)
          .fontColor([HERO_CARD_TEXT])
        Text(this.proxyTesting ? '测试中' : '测试连接')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HERO_CARD_TEXT)
      }
      .width('100%')
      .height(HERO_CARD_ACTION_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .opacity(this.proxyTesting ? 0.6 : 1)
      .onClick((): void => {
        if (!this.proxyTesting) {
          this.testProxyConnection();
        }
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(heroCardMidColor(this.exitCardDark()))
    .linearGradient({
      angle: 135,
      colors: heroCardColors(this.exitCardDark())
    })
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        this.ExitStatusCard()
        // ── 请求卡（UA 与读超时合一张；卡标题已承担分类职责，原分区小标签已撤除）──
        Column({ space: 10 }) {
          Text('请求')
            .fontSize(CARD_SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          // User-Agent 字段：标签行（标签 + 重置键）→ 说明小字 → 输入框（说明在控件上方）
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text(SETTING_TITLE_USER_AGENT)
                .fontSize(13)
                .fontColor(cardDescColor())
              Blank()
              // 「重置为默认」= 纯 Text（照 ModelContextCard 同名键形制）；值为空 = 已是默认态，键置灰
              Text('重置为默认')
                .fontSize(13)
                .fontColor(this.userAgent === '' ? cardDescColor() :
                  $r('sys.color.font_emphasize'))
                .onClick((): void => {
                  if (this.userAgent !== '') {
                    this.userAgent = '';
                  }
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            // 默认值说明——必须常量拼接（defaultUserAgent 运行时取版本号），禁硬编码版本串
            Text('留空则使用 ' + defaultUserAgent() + '。自定义后聊天、标题生成与备份等请求都会改用它，网页抓取不受影响。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            // onChange 调 RequestIdentity 同一净化函数（完整净化在取值侧 effectiveUserAgent 再做一次，
            // 防备份导入绕开 UI 校验）
            TextInput({ placeholder: '例如 MyApp/1.0', text: this.userAgent })
              .maxLength(USER_AGENT_LEN_MAX)
              .width('100%')
              .onChange((value: string): void => {
                this.userAgent = sanitizeUserAgent(value);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
          // 请求读超时字段：标签 → 说明小字 → 分段胶囊三档（说明在控件上方——宪法「功能设置卡
          // 布局次序」）
          Column({ space: 6 }) {
            Text(SETTING_TITLE_READ_TIMEOUT)
              .fontSize(13)
              .fontColor(cardDescColor())
            Text('流式回复中两次收到数据的最长间隔。超过该间隔本次请求按网络错误处理，可以重发。只作用于聊天对话，其他请求保持各自时限。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            Column() {
              SegmentBar({
                items: this.readTimeoutItems,
                selectedIndex: $readTimeoutSeg
              })
            }
            .width('100%')
            .height(SEGMENT_BAR_HEIGHT)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 代理卡：三档分段 + custom 档地址输入（显示值与持久键分离——非法中途态只提示不落键）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_PROXY)
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('跟随系统保持默认，请求按系统网络设置的代理出网。直连不使用任何代理。自定义地址填 host 与端口，例如 192.168.1.10:7890。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Column() {
            SegmentBar({
              items: this.proxyItems,
              selectedIndex: $proxySeg
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
          if (this.proxySeg === 2) {
            // 协议类型分段（custom 档内二选，双 @Watch 互正契约与主档键同款）
            Column() {
              SegmentBar({
                items: this.proxyTypeItems,
                selectedIndex: $proxyTypeSeg
              })
            }
            .width('100%')
            .height(SEGMENT_BAR_HEIGHT)
            TextInput({ placeholder: '例如 192.168.1.10:7890', text: this.proxyAddrInput })
              .onChange((value: string): void => {
                this.proxyAddrInput = value;
                const text: string = value.trim();
                if (text === '' || parseNetProxyAddr(value) !== null) {
                  // 合法或清空 → 落键（写原输入文本，取值侧 parseNetProxyAddr 统一 trim）
                  this.proxyAddrInvalid = false;
                  if (text !== this.proxyAddr) {
                    this.proxyAddr = value;
                  }
                } else {
                  // 非法中途态 → 只提示不落键（this.proxyAddr 保持上一合法值）
                  this.proxyAddrInvalid = true;
                }
              })
            if (this.proxyAddrInvalid) {
              Text('地址无效暂未保存。格式为 host 加端口，例如 192.168.1.10:7890')
                .fontSize(13)
                .fontColor($r('sys.color.warning'))
            }
            // 认证（账号明文偏好随备份走 / 密码 Asset 不落偏好）——留空则不认证
            TextInput({ placeholder: '代理账号，留空则不认证', text: this.proxyUser })
              .maxLength(128)
              .onChange((value: string): void => {
                this.proxyUser = value.trim();
              })
            TextInput({ placeholder: this.proxyPasswordSaved ? '密码已配置，输入新密码则覆盖' : '代理密码，留空则不认证',
              text: this.proxyPasswordInput })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .maxLength(128)
              .onChange((value: string): void => {
                this.proxyPasswordInput = value;
              })
              .onBlur((): void => {
                this.saveProxyPasswordInput();
              })
            if (this.proxyPasswordSaved) {
              Row() {
                Text('密码已配置')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                Blank()
                Text('清除密码')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_emphasize'))
                  .onClick((): void => {
                    this.clearProxyPassword();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            // 绕过列表（平台原生匹配）：说明小字在控件上方；TextArea 短多行照 ProviderBodyPanel，取值侧
            // splitNetProxyBypassLines 统一拆行净化
            Text('这些域名与地址不走代理，每行一个。例如 example.com 或 192.168.1.5')
              .fontSize(13)
              .fontColor(cardDescColor())
            TextArea({ placeholder: '例如 example.com', text: this.proxyBypass })
              .width('100%')
              .height(96)
              .maxLength(2048)
              .onChange((value: string): void => {
                this.proxyBypass = value;
              })
          }
          // 「测试连接」键已上移至首卡出口卡内——代理卡不再重复入口；探测链与 proxyTesting 零改
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 页尾说明（同一页不得并列两种提示观感——走 InfoCard 单源件，条状提示条已否决）
        InfoCard({ text: '本页改动即时保存。代理密码只写入本机加密存储。' })
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
      title: SETTING_TITLE_NETWORK,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 去抖定时器成对清理（首卡探测链唯一持有者）
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
  }
}
