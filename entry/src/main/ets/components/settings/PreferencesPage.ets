// 偏好设置二级页（2026-09-01 领导指令新建）：应用偏好项集中页，设置页「会话提示词」
// 卡后第 4 卡 push 进入。★ 2026-09-08 组卡化（决明指令「梳理语义换序合卡，样式参考设置页
// 组卡，板块标题/副标题参考系统提示词页」）：9 卡重排为 4 板块——聊天交互（5 开关组卡 +
// 组卡之后一张「粘贴长文本转文件」单卡〔开关与阈值滑轨合一，2026-09-23 决明拍板〕，
// 板块构成为 2026-09-22 自动重试笔 4 行增至 5 行后、2026-09-23 粘贴笔再加一卡）/ 阅读与会话（3 开关组卡）/ 界面观感（页签切换动画单卡——板块不足 2 行不组卡，规范红线 5，
// 截图「模型与服务商图标」式单卡板块同构）/ 加密会话（生物识别分段卡）；★ 2026-09-08 追加
// 第 5 板块「启动进入」（启动默认页面分段卡，决明指令「启动时默认进入新对话或对话一级页，
// 样式参考生物识别方式的分段胶囊」）——板块标题样式 =
// Theme SECTION_TITLE_FONTSIZE 规范（16fp Bold cardTitleColor + 13fp 灰副标题，系统提示词
// 页「内容/点击插入变量」同款；2026-09-08 决明反馈「主标题过小」字号 13→16 全局增大），
// 板块内间距 6vp（Theme 规范，勿加 margin）。
// 开关行复用 GroupSettingCard 开关形态（只点开关切换——组件统一形态，2026-09-08 决明拍板；
// 显示刷新 = 恒单例纪元键 ForEach〔键含本组开关值，见 chatGroupKey/readGroupKey 注释〕——
// 组件 items 为普通成员入参不随父重渲更新，必须由调用方键变重建，2026-09-08 工具页真机
// 报障同根因同修；坑57 正解，组件头注释），行副标题 = 动词开头一句简介（14fp 组卡规格；
// 原「开启后…」长说明自页面退役，详细行为见帮助中心「偏好设置」条目）。
// 全部开关即改即生效（AppStorage persistProp 键，AppPreferences.ets 单一来源），无保存键。
// 坑17 口径：本页无「保存」动作（开关即时持久化）→ 返回走无参 pop、push 不挂 onPop
//（规范「未保存/无数据变化的返回不加 result」）；偏好消费方（ChatThinkingBlock）经
// AppStorage 响应式读初始态，父页无刷新需求。
// ★ 2026-09-06 生物识别方式卡改分段胶囊（决明指令「样式参考服务商配置的协议卡」）——
// 全页两处选择型卡之一（另一处 = 2026-09-08 启动进入卡，其余为开关行）：SegmentBar 复用
//（ProviderConfigPanel 协议卡同款，光感双态内置），布尔持久键零迁移、双向映射见成员注释；
// 2026-09-08 组卡化后该卡独居「加密会话」板块（原卡内说明行上移为板块副标题，卡内留
// 标题 + SegmentBar——说明仍在操作上方，布局次序规约仍满足）。
// 页面骨架：壳在 nav/PageMapBuilder.ets（HdsNavDestination/NavDestination 双分支 + 根透明
// + PageBackground 铺底 + TITLE_S 标题栏），本组件只提供内容（AppearancePage 同款分工）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor, sliderTrackColor } from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { PASTE_THRESHOLD_DEFAULT, PASTE_THRESHOLD_MAX, PASTE_THRESHOLD_MIN, PASTE_THRESHOLD_STEP, PREF_AUTO_RETRY_KEY, PREF_BIOMETRIC_FACE_KEY, PREF_KEEP_SCREEN_ON_KEY, PREF_KEYBOARD_SEND_KEY, PREF_LAUNCH_NEW_CHAT_KEY, PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY, PREF_SESSION_ICON_KEY, PREF_SESSION_TIME_KEY, PREF_STREAM_ENGINE_KEY, PREF_STREAM_FOLLOW_KEY, PREF_TAB_SWITCH_ANIM_KEY, PREF_THINK_EXPAND_KEY, clampPasteThreshold } from '../../common/AppPreferences';
import { SETTING_TITLE_AUTO_RETRY, SETTING_TITLE_BIOMETRIC_FACE, SETTING_TITLE_KEEP_SCREEN_ON, SETTING_TITLE_KEYBOARD_SEND, SETTING_TITLE_LAUNCH_ENTRY, SETTING_TITLE_PASTE_AS_FILE, SETTING_TITLE_PASTE_AS_FILE_THRESHOLD, SETTING_TITLE_PREFERENCES, SETTING_TITLE_SESSION_ICON, SETTING_TITLE_SESSION_TIME, SETTING_TITLE_STREAM_ENGINE, SETTING_TITLE_STREAM_FOLLOW, SETTING_TITLE_TAB_SWITCH_ANIM, SETTING_TITLE_THINK_EXPAND } from '../../common/SettingSearch';
import { IMMERSIVE_LEVEL_KEY, leveledUiMaterial, overlayMaterial, resolveEffectiveLevel } from '../../common/ImmersiveLevel';
import { InputDialog } from '../chat/InputDialog';
import { InfoHintButton } from '../InfoHintButton';
import { PageShell } from '../../common/PageShell';

// 粘贴设置卡 ⓘ 说明（2026-09-24 决明「在卡片加说明，可整理收入气泡」）：设备键盘的剪贴板上屏
// 与长按粘贴菜单是两条不同的上屏通路，前者若未走通即给出可用的替代做法——不写死「哪条不行」，
// 只写「没转成时怎么走」（待真机确认输入法通路后再定是否收窄）
const PASTE_CARD_HINT: string = '粘贴的长文本超过阈值会自动转成文本附件。若某次粘贴没有转成，' +
  '改用长按输入框的系统粘贴菜单即可。';

// 阈值滑轨蓝值文案（字符数直映；照 ProactivePage 三 format 纯函数先例）
function pasteThresholdFormat(chars: number): string {
  return chars + ' 字符';
}

@Component
export struct PreferencesPage {
  // 默认展开思考（@StorageLink 双向绑定 AppStorage——开关拨动即写即持久化；持久注册在
  // EntryAbility loadContent 回调，先于本页任何实例，AppearancePage 沉浸三键同款契约）
  @StorageLink(PREF_THINK_EXPAND_KEY) thinkExpand: boolean = false;
  // 流式引擎开关（2026-09-02 Cube 动效渲染层移植）：false = 原生 / true = Cube 实验
  // 引擎（默认开——同日真机验收后拍板）；ChatSendCtrl 分流点 AppStorage.get 现读
  //（同键即时生效，无广播需求）
  @StorageLink(PREF_STREAM_ENGINE_KEY) cubeEngine: boolean = true;
  // 流式输出自动跟随（2026-09-02 偏好设置页第 3 项）：true = AI 输出时列表自动滚底
  //（现状）/ false = 停在当前位置（需重新开启才恢复）；ChatFollowController.maybeFollow 现读
  //（AppStorage 现读即时生效，无广播需求，与流式引擎开关同款契约）
  @StorageLink(PREF_STREAM_FOLLOW_KEY) streamFollow: boolean = true;
  // 网络自动重试（2026-09-22 聊天自动重试笔，聊天交互组第 5 行）：true = 请求因网络原因失败
  // 且本轮尚无内容产出时自动退避重发（最多 3 次，2/4/8 秒），气泡内显示次数状态行 /
  // false = 不自动重试，维持手动点底栏重试键。默认开 = 有意选择（理由见 AppPreferences
  // 键注释）。消费方 = ChatAutoRetryCtrl 判据经 ChatAutoRetryHost 回接 ChatSendCtrl 现读；
  // ★ 开关值在轮首现读一次、轮内锁定，故拨动自下一条消息生效（域件注释已载）
  @StorageLink(PREF_AUTO_RETRY_KEY) autoRetry: boolean = true;
  // 粘贴长文本转文件（2026-09-23 粘贴长文本转文件笔，聊天交互组第 6 行）：true = 会话页
  // 输入栏粘贴的文本达到阈值时不插进输入框，改为转成 .txt 附件挂进待发附件条 / false =
  // 任何粘贴照常插入。默认开 = 有意选择（理由见 AppPreferences 键注释）。消费方 =
  // ChatInputBar @StorageProp 自订阅；★ 本页阈值卡只在开关开时渲染（见 Content 板块1）
  @StorageLink(PREF_PASTE_AS_FILE_KEY) pasteAsFile: boolean = true;
  // 粘贴转文件的长度阈值（字符数，默认 2000）：开关行下方阈值卡绑定的值；@StorageLink 直写
  // 持久键（拖动或编辑弹窗改值即落盘）。消费方 = ChatInputBar 判定前经 clampPasteThreshold
  @StorageLink(PREF_PASTE_AS_FILE_THRESHOLD_KEY) pasteThreshold: number = PASTE_THRESHOLD_DEFAULT;
  // 阈值编辑弹窗控制器（CustomDialogController 须组件成员位构造——坑7 形态；弹一次 new 一次，
  // 先例 = ProactivePage.dailyLimitEditCtrl）
  private pasteThresholdEditCtrl: CustomDialogController | null = null;
  // 键盘发送（2026-09-03 偏好设置页第 4 项）：true = 会话页输入框键盘换行键替换为发送键
  //（点击直接发送——与胶囊发送键同语义）；false = 换行键（默认）。消费方 = ChatInputBar
  // @StorageProp 订阅（切换即刷 enterKeyType）
  @StorageLink(PREF_KEYBOARD_SEND_KEY) keyboardSend: boolean = false;
  // 会话页屏幕常亮（2026-09-04 偏好设置页第 5 项）：true = 进会话页设窗口常亮；false =
  // 系统息屏（默认）。消费方 = ChatPage aboutToAppear 现读 + aboutToDisappear 复位
  //（窗口属性无广播需求——下次进会话页即生效）
  @StorageLink(PREF_KEEP_SCREEN_ON_KEY) keepScreenOn: boolean = false;
  // 会话时间显示（2026-09-04 偏好设置页第 6 项）：true = 会话列表卡片显示最后消息时间
  //（默认，现状）；false = 只隐藏显示（记录照常落盘）。消费方 = SessionCardItem
  // @StorageProp 自订阅（切换标签页即刷）
  @StorageLink(PREF_SESSION_TIME_KEY) sessionTime: boolean = true;
  // 会话图标显示（2026-09-19 偏好设置页·阅读与会话组第 3 行）：true = 会话列表卡片显示
  // 左侧消息图标（默认，现状）/ false = 图标不显示，标题左移。消费方 = SessionCardItem
  // @StorageProp 自订阅（切换即刷，与会话时间开关同款契约）
  @StorageLink(PREF_SESSION_ICON_KEY) sessionIcon: boolean = true;
  // 生物识别方式（2026-09-05 偏好设置页第 8 项，决明指令「偏好选人脸或指纹，选定只用一种」；
  // ★ 2026-09-06 卡内开关改分段胶囊——决明指令「样式参考服务商配置的协议卡」，SegmentBar
  // 光感双态内置）: true = 人脸识别（默认，真机实测链路已通）；false = 指纹识别。持久键
  // 保持布尔形态零迁移（BiometricGate 现读 + set_app_preference 工具直写 + persistProp
  // 注册三契约不变）；消费方 = BiometricGate 发起时现读（下次认证即新方式，无广播需求）。
  // 分段下标与布尔键双向映射（ProviderConfigPanel protocol/protoIndex 同款姿势）：用户点
  // 分段经 onBioIndexChanged 写键，工具直写键经 onBiometricChanged 补正下标——互设守卫
  // 同值不递归
  @StorageLink(PREF_BIOMETRIC_FACE_KEY) @Watch('onBiometricChanged') biometricFace: boolean = true;
  @State @Watch('onBioIndexChanged') bioIndex: number = 0;
  // 页签切换动画（2026-09-08 偏好设置页第 9 项，决明指令「偏好设置加切换开关」）：true =
  // 底部页签点击切换带横向滑动动画（默认，2026-09-08 拍板开回的现状）/ false = 点按直达
  // 无过渡。消费方 = HomeNavigation @StorageProp 订阅（状态驱动重渲染即时生效，无广播）
  @StorageLink(PREF_TAB_SWITCH_ANIM_KEY) tabSwitchAnim: boolean = true;
  // 启动进入页面（2026-09-08 偏好设置页第 10 项，决明指令「启动时默认进入新对话或对话一级
  // 页，样式参考生物识别方式的分段胶囊」）：true = 冷启动直接进入新对话（懒创建不落库，
  // 助手随当前选择）/ false = 进入对话一级页（会话列表，默认 = 现状零回归）。消费方 =
  // HomeNavigation.aboutToAppear 现读一次（仅冷启动首帧生效，后台回前台不重进——组件不
  // 重建；切换下次启动生效，无广播需求）。分段下标与布尔键双向映射（生物识别卡同款姿势）：
  // 用户点分段经 onLaunchIndexChanged 写键，工具直写键经 onLaunchPrefChanged 补正下标——
  // 互设守卫同值不递归
  @StorageLink(PREF_LAUNCH_NEW_CHAT_KEY) @Watch('onLaunchPrefChanged') launchNewChat: boolean = false;
  @State @Watch('onLaunchIndexChanged') launchIndex: number = 1;
  // 分段选项（顺序契约：下标 0 = 人脸（键 true）/ 1 = 指纹（键 false），勿单独乱调）
  private bioItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '人脸识别' },
    { text: '指纹识别' }
  ]);
  // 分段选项（顺序契约：下标 0 = 新对话（键 true）/ 1 = 会话列表（键 false），勿单独乱调）
  private launchItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '新对话' },
    { text: '会话列表' }
  ]);
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 系统颜色模式（回退卡底色；EntryAbility 已接线写键，深浅色切换自动刷新）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（粘贴设置卡内滑轨材质驱动；AppStorage 自订阅，与其余滑轨消费方同款）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    // 分段下标与持久键初值对齐（@StorageLink 声明处默认 true 不代表键实际值——指纹存量
    // 用户进页须亮指纹段；启动进入卡同理，默认值 false = 亮「会话列表」段）
    this.bioIndex = this.biometricFace ? 0 : 1;
    this.launchIndex = this.launchNewChat ? 0 : 1;
    // 阈值归域（2026-09-23 粘贴长文本转文件笔）：老备份或手工改值可能越界，越界值会让滑轨
    // 停在异常位置；赋值即触发 @StorageLink 落盘，把脏值一并归正（ProactivePage 同款姿势）
    this.pasteThreshold = clampPasteThreshold(this.pasteThreshold);
  }

  // 阈值编辑键弹窗（InputDialog 数字型——ProactivePage 每日上限卡同款形制；初值预填当前值）
  private openPasteThresholdEdit(): void {
    this.pasteThresholdEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: SETTING_TITLE_PASTE_AS_FILE_THRESHOLD,
        initialText: String(this.pasteThreshold),
        placeholder: PASTE_THRESHOLD_MIN + '~' + PASTE_THRESHOLD_MAX + ' 的整数',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyPasteThresholdInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.pasteThresholdEditCtrl.open();
  }

  // 阈值手动输入解析（非整数才提示；越界不整句拒绝，照钳位口径收进域内——本域是连续域，
  // 与 ProactivePage 档位白名单（离散域）有意不同）。合法写 @StorageLink 即落盘，同滑轨
  private applyPasteThresholdInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim()) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 ' + PASTE_THRESHOLD_MIN + '~' + PASTE_THRESHOLD_MAX + ' 的整数'
      });
      return;
    }
    this.pasteThreshold = clampPasteThreshold(v);
  }

  // 用户点分段 → 写布尔持久键（互设守卫同值不递归）
  private onBioIndexChanged(): void {
    const face: boolean = this.bioIndex === 0;
    if (face !== this.biometricFace) {
      this.biometricFace = face;
    }
  }

  // 工具直写键（set_app_preference）/ 其他写键方 → 补正分段下标（@StorageLink 自动响应，
  // 页面在途时 UI 随键同步——ProviderConfigPanel protocol @Watch 同款契约）
  private onBiometricChanged(): void {
    const idx: number = this.biometricFace ? 0 : 1;
    if (idx !== this.bioIndex) {
      this.bioIndex = idx;
    }
  }

  // 用户点分段 → 写启动进入持久键（互设守卫同值不递归；下标 0 = 新对话 = 键 true）
  private onLaunchIndexChanged(): void {
    const newChat: boolean = this.launchIndex === 0;
    if (newChat !== this.launchNewChat) {
      this.launchNewChat = newChat;
    }
  }

  // 工具直写键 / 其他写键方 → 补正分段下标（onBiometricChanged 同款契约）
  private onLaunchPrefChanged(): void {
    const idx: number = this.launchNewChat ? 0 : 1;
    if (idx !== this.launchIndex) {
      this.launchIndex = idx;
    }
  }

  // ── 聊天交互组（5 开关，组序 = 2026-09-08 组卡化拍板 + 2026-09-22 自动重试笔追加第 5 行；
  // 行副标题 = 动词开头一句简介，详细行为见帮助中心「偏好设置」条目；toggleValue/onToggle
  // 闭包读/写上方 @StorageLink）。★ 粘贴长文本转文件**不进本组卡**——它是开关与阈值滑轨合一的
  // 单卡（2026-09-23 决明拍板「做单卡，开关与滑块合一卡，仍归属聊天板块」），渲染在组卡之后，
  // 见 Content 板块1
  private chatGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.lightbulb'),
        label: SETTING_TITLE_THINK_EXPAND,
        secondary: '自动展开新思考块',
        toggleValue: (): boolean => this.thinkExpand,
        onToggle: (isOn: boolean): void => {
          this.thinkExpand = isOn;
        }
      },
      {
        icon: $r('sys.symbol.keyboard'),
        label: SETTING_TITLE_KEYBOARD_SEND,
        secondary: '回车键直接发送',
        toggleValue: (): boolean => this.keyboardSend,
        onToggle: (isOn: boolean): void => {
          this.keyboardSend = isOn;
        }
      },
      {
        icon: $r('sys.symbol.bolt'),
        label: SETTING_TITLE_STREAM_ENGINE,
        secondary: '切换输出渲染引擎',
        toggleValue: (): boolean => this.cubeEngine,
        onToggle: (isOn: boolean): void => {
          this.cubeEngine = isOn;
        }
      },
      {
        icon: $r('sys.symbol.arrow_down_circle'),
        label: SETTING_TITLE_STREAM_FOLLOW,
        secondary: '输出时自动滚到底部',
        toggleValue: (): boolean => this.streamFollow,
        onToggle: (isOn: boolean): void => {
          this.streamFollow = isOn;
        }
      },
      // 网络自动重试（2026-09-22 新增，聊天交互组第 5 行；行副标题 = 动词开头一句简介口径，
      // 只覆盖网络异常——中途断流不自动重试的边界写在帮助中心条目与本键注释里）
      {
        icon: $r('sys.symbol.arrow_clockwise'),
        label: SETTING_TITLE_AUTO_RETRY,
        secondary: '网络异常时自动重发',
        toggleValue: (): boolean => this.autoRetry,
        onToggle: (isOn: boolean): void => {
          this.autoRetry = isOn;
        }
      }
    ];
  }

  // ── 阅读与会话组（3 开关；原行卡逻辑原样平移）
  private readGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.sun_max'),
        label: SETTING_TITLE_KEEP_SCREEN_ON,
        secondary: '会话页保持常亮',
        toggleValue: (): boolean => this.keepScreenOn,
        onToggle: (isOn: boolean): void => {
          this.keepScreenOn = isOn;
        }
      },
      {
        icon: $r('sys.symbol.clock'),
        label: SETTING_TITLE_SESSION_TIME,
        secondary: '显示最后消息时间',
        toggleValue: (): boolean => this.sessionTime,
        onToggle: (isOn: boolean): void => {
          this.sessionTime = isOn;
        }
      },
      {
        icon: $r('sys.symbol.message'),
        label: SETTING_TITLE_SESSION_ICON,
        secondary: '显示卡片消息图标',
        toggleValue: (): boolean => this.sessionIcon,
        onToggle: (isOn: boolean): void => {
          this.sessionIcon = isOn;
        }
      }
    ];
  }

  // ── 组卡重建键（2026-09-08 真机报障修复，与工具页组卡同根因同修）──
  // GroupSettingCard.items 是普通成员入参：父组件重渲不更新它、组件自身又无状态变化 →
  // 组卡 build 不重跑 → 开关 Toggle 定格首帧（拨了行、开关不动）。本键进「恒单例纪元键
  // ForEach」（规范 §3 主通道「键变重建」）：键含本组各开关当前值，任一开关变动（含工具
  // 直写 set_app_preference 触发的 @StorageLink 变更）即键变 → 组卡重建 → Toggle 拉新值
  private chatGroupKey(): string {
    return [String(this.thinkExpand), String(this.keyboardSend), String(this.cubeEngine),
      String(this.streamFollow), String(this.autoRetry)].join('|');
  }

  private readGroupKey(): string {
    return [String(this.keepScreenOn), String(this.sessionTime), String(this.sessionIcon)].join('|');
  }

  build() {
    // 页面骨架统一由 PageShell 提供（2026-09-07 迁——原 PageMapBuilder 直壳 titleBar 为
    // 入栈快照，档位变化不实时刷新，与外观页同病同修）；PageShell 已含 HDS/回退双分支 +
    // PageBackground + onShown(bumpBgShownEpoch) 内置
    PageShell({
      title: SETTING_TITLE_PREFERENCES,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 板块1 聊天交互（组卡 5 行开关 + 粘贴设置单卡；2026-09-08 组卡化，分组/组序
        // 见 chatGroup()）──
        Column({ space: 6 }) {
          SectionHeader({ title: '聊天交互', subtitle: '输入与回复过程中的默认行为' })
          // 恒单例纪元键 ForEach：键变重建刷开关（见 chatGroupKey 注释）
          ForEach([this.chatGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.chatGroup() })
          }, (key: string): string => key)
          // 粘贴设置卡（2026-09-23 粘贴长文本转文件笔，决明当日改拍板「做单卡，开关与滑块合一，
          // 仍归聊天交互板块」）：开关与长度阈值**同一张卡**——形制照同类先例 SamplingToggleCard
          //（AssistantSamplingPage 页内 4 连用提取件）：标题行 / 说明小字与开关同行（说明在左、
          // 开关居右，先说明后操作） / 开关开时下方滑块行（滑轨 + 右侧蓝值 + 编辑键，可弹数字输入
          // 取精确值）。★ 开关关时只收起**滑块段**（整卡与开关留存——关掉的门要能再打开，
          // 这是与上一版「整卡不渲染」的有意差异）。
          // ★ 卡宽自持 CARD_PANEL_WIDTH：本页宿主列容器无左右 16vp padding（同页其余卡一律
          // 同值），禁再包宽度壳（双重收窄——「怎么又是全宽」已三次报障）
          Column({ space: 12 }) {
            // 标题行 = 标题 + ⓘ 气泡（形制照 SamplingToggleCard：标题 layoutWeight 撑满、
            // 气泡落整卡右上角——2026-09-24 决明「在卡片加说明，可整理收入气泡」）
            Row() {
              Text(SETTING_TITLE_PASTE_AS_FILE)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .layoutWeight(1)
              InfoHintButton({ text: PASTE_CARD_HINT })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            Row({ space: 12 }) {
              Text('粘贴的文本过长时转成文本附件，不再插进输入框')
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.pasteAsFile })
                .onChange((isOn: boolean): void => {
                  this.pasteAsFile = isOn;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            if (this.pasteAsFile) {
              Row() {
                Text(SETTING_TITLE_PASTE_AS_FILE_THRESHOLD)
                  .fontSize(13)
                  .fontColor(cardDescColor())
                Blank()
                Text(pasteThresholdFormat(this.pasteThreshold))
                  .fontSize(15)
                  .fontColor($r('sys.color.ohos_id_color_emphasize'))
                Button() {
                  SymbolGlyph($r('sys.symbol.square_and_pencil'))
                    .fontSize(18)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  this.openPasteThresholdEdit();
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              Slider({
                value: this.pasteThreshold,
                min: PASTE_THRESHOLD_MIN,
                max: PASTE_THRESHOLD_MAX,
                step: PASTE_THRESHOLD_STEP,
                style: SliderStyle.InSet
              })
                .width('100%')
                .trackThickness(20)
                .blockSize({ width: 12, height: 12 })
                .trackBorderRadius(10)
                // 半透明滑轨色 + 沉浸光感材质（SliderValueCard / SliderRow 同款单源）
                .trackColor(sliderTrackColor(this.appColorMode))
                .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
                .borderRadius(10)
                .systemMaterial(leveledUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                  resolveEffectiveLevel(this.immersiveLevel), false))
                .onChange((v: number): void => {
                  // 整数域 + 域内钳位；@StorageLink 直写持久键 = 拖动即落盘（与滑轨卡同契约）
                  this.pasteThreshold = clampPasteThreshold(v);
                })
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        // ── 板块2 阅读与会话（组卡 3 行开关；组序见 readGroup()）──
        Column({ space: 6 }) {
          SectionHeader({ title: '阅读与会话', subtitle: '回到会话时的阅读体验' })
          ForEach([this.readGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.readGroup() })
          }, (key: string): string => key)
        }
        .width('100%')
        // ── 板块3 界面观感（页签切换动画单卡——板块不足 2 行不组卡（规范红线 5），
        // 单卡保持自绘开关卡形态；2026-09-08 决明指令「偏好设置加切换开关」）──
        Column({ space: 6 }) {
          SectionHeader({ title: '界面观感', subtitle: '应用界面与页签的显示偏好' })
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text(SETTING_TITLE_TAB_SWITCH_ANIM)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('开启后页签滑动切换。关闭后直达无过渡')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.tabSwitchAnim })
              .onChange((isOn: boolean): void => {
                this.tabSwitchAnim = isOn;
              })
          }
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        // ── 板块4 加密会话（生物识别分段卡；说明行已上移为板块副标题，卡内留标题 +
        // SegmentBar——说明仍在操作上方，布局次序规约满足；双向映射见成员注释）──
        Column({ space: 6 }) {
          SectionHeader({ title: '加密会话', subtitle: '选择加密会话验证使用的识别方式，下次认证即生效' })
          Column({ space: 10 }) {
            Column({ space: 2 }) {
              Text(SETTING_TITLE_BIOMETRIC_FACE)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            Column() {
              SegmentBar({
                items: this.bioItems,
                selectedIndex: $bioIndex
              })
            }
            .width('100%')
            .height(SEGMENT_BAR_HEIGHT)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        // ── 板块5 启动进入（启动默认页面分段卡；形制对齐上方生物识别卡——板块副标题承担
        // 说明，卡内留标题 + SegmentBar，说明仍在操作上方；双向映射见成员注释）──
        Column({ space: 6 }) {
          SectionHeader({ title: '启动进入', subtitle: '打开应用时默认进入的页面' })
          Column({ space: 10 }) {
            Column({ space: 2 }) {
              Text(SETTING_TITLE_LAUNCH_ENTRY)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            Column() {
              SegmentBar({
                items: this.launchItems,
                selectedIndex: $launchIndex
              })
            }
            .width('100%')
            .height(SEGMENT_BAR_HEIGHT)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
