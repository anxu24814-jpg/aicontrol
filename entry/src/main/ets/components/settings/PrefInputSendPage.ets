// 偏好设置二级页「输入与发送」：一级偏好页第 1 行入口的承载页——输入与发送行为诸项（键盘发送 / 输入框常驻
// 展开 / 粘贴长文本转文件 / 时间间隔提醒 / 图链转图 / 拍照存相册 / 添加图片时编辑 / 自动重试入口）。三板块 = 「输入 /
// 发送与重试 / 附件」，每板块 = 卡外 SectionHeader（无副标题）+ 组卡；标题与卡 SECTION_HEADER_GAP、板块间
// SECTION_GAP（Theme 三档常量）。「自动重试」已升级为入口行，点击 push 独立设置页（决明拍板「改为单独卡，
// 去掉开关，点击进下一页」）。
// ★ 两个复合卡（时间间隔提醒 / 粘贴）标题行 = 标题 + 紧邻 ⓘ + 开关开时右侧「蓝值 + 右箭头」同包一 Row 整体可点
//（点值同弹数字输入；箭头 = GroupSettingCard 入口行同款裸箭头，热区见 SliderValueCard 头注释）。
// 骨架由 PageShell 提供；全部开关即时持久化（AppStorage persistProp 键，AppPreferences 单一来源）无保存动作 →
// 返回走无参 pop、push 不挂 onPop（规范「未保存/无数据变化的返回不加 result」）。开关行刷新 = 恒单例纪元键
// ForEach 键变重建（键含本组开关值；坑57 正解）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, SECTION_GAP, SECTION_HEADER_GAP, cardBg, cardBorderColor, cardDescColor, cardTitleColor, sliderTrackColor, CARD_RADIUS } from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { SLIDER_ROW_HEIGHT, SLIDER_ROW_WIDTH } from '../SliderValueCard';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE, SETTING_ICON_ORANGE, SETTING_ICON_PURPLE } from '../GroupSettingCard';
import { PREF_DS_SAFETY_CHECK_KEY, PASTE_THRESHOLD_DEFAULT, PASTE_THRESHOLD_MAX, PASTE_THRESHOLD_MIN, PASTE_THRESHOLD_STEP, PREF_INPUT_EXPANDED_KEY, PREF_KEYBOARD_SEND_KEY, PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY, PREF_PHOTO_SAVE_GALLERY_KEY, PREF_PHOTO_EDIT_KEY, PREF_TEXT_IMAGE_FETCH_KEY, PREF_TIME_REMINDER_KEY, PREF_TIME_REMINDER_MINUTES_KEY, TIME_REMINDER_DEFAULT, TIME_REMINDER_MAX, TIME_REMINDER_MIN, TIME_REMINDER_STEP, clampPasteThreshold, clampTimeReminderMinutes } from '../../common/AppPreferences';
import { ROUTE_PREF_AUTO_RETRY_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_AUTO_RETRY, SETTING_TITLE_INPUT_EXPANDED, SETTING_TITLE_KEYBOARD_SEND, SETTING_TITLE_PASTE_AS_FILE, SETTING_TITLE_PASTE_AS_FILE_THRESHOLD, SETTING_TITLE_PHOTO_SAVE_GALLERY, SETTING_TITLE_PHOTO_EDIT, SETTING_TITLE_PREF_INPUT_SEND, SETTING_TITLE_TEXT_IMAGE, SETTING_TITLE_TIME_REMINDER } from '../../common/SettingSearch';
import { IMMERSIVE_LEVEL_KEY, leveledUiMaterial, overlayMaterial, resolveEffectiveLevel } from '../../common/ImmersiveLevel';
import { InputDialog } from '../chat/InputDialog';
import { InfoHintButton } from '../InfoHintButton';
import { PageShell } from '../../common/PageShell';

// 粘贴设置卡 ⓘ 说明（决明「在卡片加说明，可整理收入气泡」）：设备键盘剪贴板上屏与长按粘贴是两条通路，前者若未走通即给出替代做法——不写死哪条不行，只写「没转成时怎么走」
const PASTE_CARD_HINT: string = '粘贴的长文本超过阈值会自动转成文本附件。若某次粘贴没有转成，' +
  '改用长按输入框的系统粘贴菜单即可。';

// 时间间隔提醒卡 ⓘ 说明（逐字定稿）
const TIME_REMINDER_CARD_HINT: string = '间隔超过设定值时，会在发送内容里插入一条时间提示，' +
  '内容含当时时刻与距上一条消息的时长。提示只在发送时生成，不会出现在聊天记录里。';

// 板块头：只给标题不写副标题——SectionHeader 的 subtitle 为空串时整行不渲染
const SECTION_INPUT: string = '输入';
const SECTION_SEND_RETRY: string = '发送与重试';
const SECTION_ATTACHMENT: string = '附件';

// 阈值滑轨蓝值文案（字符数直映；照 ProactivePage 三 format 纯函数先例）
function pasteThresholdFormat(chars: number): string {
  return chars + ' 字符';
}

// 时间间隔阈值蓝值文案（分钟 → 带单位换算；阈值域上限 720 ⇒ 不会出现「天」档）
function timeReminderFormat(minutes: number): string {
  if (minutes < 60) {
    return minutes + ' 分钟';
  }
  const hours: number = Math.floor(minutes / 60);
  const rem: number = minutes % 60;
  return rem === 0 ? hours + ' 小时' : hours + ' 小时 ' + rem + ' 分';
}

@Component
export struct PrefInputSendPage {
  // 键盘发送：true = 会话页输入框换行键替换为发送键（点击直接发送）；false = 换行键（默认）。消费方 = ChatInputBar
  // @StorageProp 订阅（切换即刷 enterKeyType）
  @StorageLink(PREF_KEYBOARD_SEND_KEY) keyboardSend: boolean = false;
  // 内容安全审核（二期 #6，决明 2026-11-14 拍板「给开关不恒开、默认关」）：true = DS 官方
  // 模型会话的请求带 safety_check:{"level":"high"} / false = 不带字段（默认）。入口只在本页
  // （会话设置面板不加）；关 ≠ 关闭审核——官方未开启时声明联网工具也可能拒答，帮助条目已写明
  @StorageLink(PREF_DS_SAFETY_CHECK_KEY) dsSafetyCheck: boolean = false;
  // 输入框常驻展开（决明拍板）：true = 会话页输入框恒为展开态（进页即两排卡全宽、工具行齐全，失焦不收起）/
  // false = 收起态胶囊（默认，现状）。消费方 = ChatInputBar（@StorageProp @Watch，进页置初态 + 中途切换即对齐）
  @StorageLink(PREF_INPUT_EXPANDED_KEY) inputExpanded: boolean = false;
  // 图片链接作为图片发送：true = 消息里的 Markdown 图链（![alt](url)，仅 http/https）发送时自动下载作为图片附件
  // 随本轮请求发给模型；false = 按普通文本发送（默认）。消费方 = TextImageFetch 发送链早退现读（发送时刻读一次）
  @StorageLink(PREF_TEXT_IMAGE_FETCH_KEY) textImageFetch: boolean = false;
  // 拍照保存到相册：true = 会话内「拍照」的照片同时存进系统相册（不传 saveUri，系统相机落媒体库再拷入沙箱供发送）；
  // false = 只落沙箱（默认）。★ 保存时机 = 拍照时刻，与是否发送无关；只影响「拍照」入口
  @StorageLink(PREF_PHOTO_SAVE_GALLERY_KEY) photoSaveGallery: boolean = false;
  // 添加图片时编辑：true = 「拍照」与「照片」两入口的图片先进待发图片裁剪页、完成后裁剪产物
  // 入列 / false = 直接入列（默认）。消费方 = AttachmentPickCtrl.pick 两分支现读（拨动即生效）；
  // 只管这两个入口，「系统文件」入口、重发、分享与粘贴件一律不进编辑页
  @StorageLink(PREF_PHOTO_EDIT_KEY) photoEdit: boolean = false;
  // 粘贴长文本转文件：true = 粘贴文本达阈值时不插进输入框，改为转成 .txt 附件挂进待发附件条；false = 照常插入。
  // 默认开 = 有意选择（理由见 AppPreferences 键注释）；消费方 = ChatInputBar 自订阅；★ 阈值段只在开关开时渲染
  @StorageLink(PREF_PASTE_AS_FILE_KEY) pasteAsFile: boolean = true;
  // 粘贴转文件的长度阈值（字符数，默认 2000）：@StorageLink 直写持久键；消费方 = ChatInputBar 判定前经 clampPasteThreshold
  @StorageLink(PREF_PASTE_AS_FILE_THRESHOLD_KEY) pasteThreshold: number = PASTE_THRESHOLD_DEFAULT;
  // 阈值编辑弹窗控制器（坑7：须组件成员位构造，弹一次 new 一次）
  private pasteThresholdEditCtrl: CustomDialogController | null = null;
  // 时间间隔提醒开关：true = 间隔超阈值时发送组装插一条时间提醒；false = 完全不插（默认——改变发出去的内容，静默生效会让用户困惑）。消费方 = ChatSendCtrl.assembleRound 每轮现读
  @StorageLink(PREF_TIME_REMINDER_KEY) timeReminder: boolean = false;
  // 提醒间隔阈值（分钟，默认 60）：@StorageLink 直写持久键；消费方同上（读取侧经 clampTimeReminderMinutes）
  @StorageLink(PREF_TIME_REMINDER_MINUTES_KEY) timeReminderMinutes: number = TIME_REMINDER_DEFAULT;
  // 阈值编辑弹窗控制器（同粘贴键形制——坑7；弹一次 new 一次）
  private timeReminderEditCtrl: CustomDialogController | null = null;
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 导航栈（本页有下级跳转——「自动重试」入口行 push 独立设置页）
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（回退卡底色；EntryAbility 已接线写键，深浅色切换自动刷新）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（两张复合卡内滑轨材质驱动；AppStorage 自订阅，与其余滑轨消费方同款）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    // 阈值归域：老备份或手工改值可能越界（滑轨停在异常位置）；赋值即触发 @StorageLink 落盘，把脏值一并归正
    this.pasteThreshold = clampPasteThreshold(this.pasteThreshold);
    this.timeReminderMinutes = clampTimeReminderMinutes(this.timeReminderMinutes);
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

  // 阈值手动输入解析（非整数才提示；越界不整句拒绝，照钳位收进域内——本域是连续域，与 ProactivePage 离散档位有意不同）；合法写 @StorageLink 即落盘
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

  // 时间间隔阈值编辑键弹窗（照粘贴键同款形制，初值预填当前值）
  private openTimeReminderEdit(): void {
    this.timeReminderEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '提醒间隔',
        initialText: String(this.timeReminderMinutes),
        placeholder: TIME_REMINDER_MIN + '~' + TIME_REMINDER_MAX + ' 的整数',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyTimeReminderInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.timeReminderEditCtrl.open();
  }

  // 时间间隔阈值手动输入解析（同粘贴键口径：非整数才提示，越界钳位收进域内）
  private applyTimeReminderInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim()) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 ' + TIME_REMINDER_MIN + '~' + TIME_REMINDER_MAX + ' 的整数'
      });
      return;
    }
    this.timeReminderMinutes = clampTimeReminderMinutes(v);
  }

  // 输入板块组卡（键盘发送 + 输入框常驻展开；副标题 = 动词开头一句简介口径）
  private inputSendGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.keyboard'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_KEYBOARD_SEND,
        secondary: '回车键直接发送',
        toggleValue: (): boolean => this.keyboardSend,
        onToggle: (isOn: boolean): void => {
          this.keyboardSend = isOn;
        }
      },
      {
        icon: $r('sys.symbol.chevron_up'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_INPUT_EXPANDED,
        secondary: '进入会话即展开，失焦不收起',
        toggleValue: (): boolean => this.inputExpanded,
        onToggle: (isOn: boolean): void => {
          this.inputExpanded = isOn;
        }
      },
      {
        // 内容安全审核（二期 #6）：副标题只陈述生效范围，不写「关闭审核」类误导文案
        icon: $r('sys.symbol.checkmark_shield'),
        iconBg: SETTING_ICON_BLUE,
        label: '内容安全审核',
        secondary: '仅对 DeepSeek 官方模型会话生效',
        toggleValue: (): boolean => this.dsSafetyCheck,
        onToggle: (isOn: boolean): void => {
          this.dsSafetyCheck = isOn;
        }
      }
    ];
  }

  // 输入板块重建键（键含本组开关值：任一变动即键变 → 组卡重建 → Toggle 拉新值；组卡 items 普通成员不随父重渲——坑57）
  private inputSendGroupKey(): string {
    return [String(this.keyboardSend), String(this.inputExpanded),
      String(this.dsSafetyCheck)].join('|');
  }

  // 发送与重试板块组卡（「自动重试」入口行——点击 push 独立设置页，行尾 chevron 灰箭头示意可进下一页）
  private sendRetryGroup(): GroupEntryItem[] {
    return [
      {
        // 自动重试入口行（图标沿用开关期 arrow_clockwise 重试语义）；开关与判据参数都在独立设置页
        icon: $r('sys.symbol.arrow_clockwise'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_AUTO_RETRY,
        secondary: '请求失败时自动重发',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PREF_AUTO_RETRY_PAGE, null);
        }
      }
    ];
  }

  // 发送与重试板块重建键（本组只有入口行、无开关态 → 键恒稳；仍走单例 ForEach 与另两组同形装配）
  private sendRetryGroupKey(): string {
    return 'sendRetryEntry';
  }

  // 附件板块组卡（图片链接作为图片发送 + 拍照保存到相册 + 添加图片时编辑）；卡内三行统一蓝（卡内主色并列取首行）
  private attachmentGroup(): GroupEntryItem[] {
    return [
      {
        // 图标语义 = 图片（图链转图的产物形态）。★ 符号经「符号资源两道门」构建绿终证（坑72）——text_and_photo / photo 均被第一道门拦下，picture 为工程旁证在用符号
        icon: $r('sys.symbol.picture'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_TEXT_IMAGE,
        secondary: '消息里的图链自动发给模型',
        toggleValue: (): boolean => this.textImageFetch,
        onToggle: (isOn: boolean): void => {
          this.textImageFetch = isOn;
        }
      },
      {
        // 图标语义 = 拍照（与「＋」面板拍照格同符号——ChatPromptSheet 已在用，两道门已过）；副标题只述开启态行为
        icon: $r('sys.symbol.camera'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_PHOTO_SAVE_GALLERY,
        secondary: '拍照后同时存进系统相册',
        toggleValue: (): boolean => this.photoSaveGallery,
        onToggle: (isOn: boolean): void => {
          this.photoSaveGallery = isOn;
        }
      },
      {
        // 图标语义 = 编辑（square_and_pencil 为工程在多处组卡与菜单在用的符号，两道门已过）；
        // 副标题只述开启态行为，且不含冒号、分号与括号连环（面向用户文案写作规约）。
        // ★ 长度受行卡槽位约束（2026-11-05 自检轮修）：GroupSettingCard 副标题 14fp 单行省略，
        // 行内容宽约 230vp ≈ 16 字——原 20 字「拍照和选照片后先裁剪，完成后再进输入框」在
        // 360~428vp 机型都会被截断（P-2 固定容量 × 变长内容），压到 13 字以内去掉后半句
        icon: $r('sys.symbol.square_and_pencil'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_PHOTO_EDIT,
        secondary: '拍照和选照片后先进裁剪页',
        toggleValue: (): boolean => this.photoEdit,
        onToggle: (isOn: boolean): void => {
          this.photoEdit = isOn;
        }
      }
    ];
  }

  // 附件板块重建键（键含本组三个开关值；任一变动即键变 → 组卡重建 → Toggle 拉新值；坑57 正解）
  private attachmentGroupKey(): string {
    return [String(this.textImageFetch), String(this.photoSaveGallery),
      String(this.photoEdit)].join('|');
  }

  build() {
    // PageShell 提供骨架（HDS/回退双分支 + PageBackground + onShown）；标题 = 行名常量（与一级页入口行单一来源）
    PageShell({
      title: SETTING_TITLE_PREF_INPUT_SEND,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      // 板块间 SECTION_GAP、SectionHeader 与卡片间 SECTION_HEADER_GAP（Theme 三档常量；卡内 space 12 是复合卡内部行距）
      Column({ space: SECTION_GAP }) {
        // ── 板块1 输入（键盘发送 / 输入框常驻展开）──
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: SECTION_INPUT })
          // 开关组卡（恒单例纪元键 ForEach：键变重建刷开关，见 inputSendGroupKey 注释）
          ForEach([this.inputSendGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.inputSendGroup(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
        }
        .width('100%')
        // ── 板块2 发送与重试（自动重试入口组卡 + 时间间隔提醒卡）──
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: SECTION_SEND_RETRY })
          // 「自动重试」入口组卡（单行；开关与参数在独立设置页）
          ForEach([this.sendRetryGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.sendRetryGroup(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
          // 时间间隔提醒卡（改变的是发送出去的对话内容）：标题行（标题 + ⓘ + 开关开时右侧蓝值与右箭头）/ 说明小字与
          // 开关同行（说明在左、开关居右，先说明后操作——宪法「功能设置卡布局次序」）/ 开关开时 0.5vp 分割线 + 下排
          //（左侧标签 + 右侧短滑轨）。开关关时只收起蓝值、入口、分割线与下排（整卡与开关留存——关掉的门要能再打开）。
          // 阈值行标签「提醒间隔」不另立搜索注册项（内卡不逐张注册，同粘贴口径）。★ 卡宽自持 CARD_PANEL_WIDTH：
          // 宿主列容器无左右 padding，禁再包宽度壳（双重收窄）
          Column({ space: 12 }) {
            // 标题行 = 标题 + 紧邻 ⓘ + 剩余空档 + 开关开时右侧蓝值与编辑箭头（「蓝值 + 箭头」同包一 Row 整体可点）
            Row({ space: 8 }) {
              Text(SETTING_TITLE_TIME_REMINDER)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                // 窄屏不足时标题先让位（三笔起滑轨加宽与右侧热区保形配套）——ⓘ/蓝值/箭头保形
                .flexShrink(1)
                .constraintSize({ maxWidth: this.timeReminder ? '55%' : '100%' })
              InfoHintButton({ text: TIME_REMINDER_CARD_HINT })
              Blank()
              if (this.timeReminder) {
                Row({ space: 4 }) {
                  Text(timeReminderFormat(this.timeReminderMinutes))
                    .fontSize(15)
                    .fontColor($r('sys.color.ohos_id_color_emphasize'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([cardDescColor()])
                }
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.openTimeReminderEdit();
                })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            Row({ space: 12 }) {
              Text('对话隔得较久时附一条时间提示，帮助模型理解隔了多久')
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.timeReminder })
                .onChange((isOn: boolean): void => {
                  this.timeReminder = isOn;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            if (this.timeReminder) {
              Divider()
                .strokeWidth(0.5)
                .color(cardBorderColor(this.appColorMode))
                .width('100%')
              // 下排 = 左侧标签 + 右侧短滑轨（联网搜索页新版形态；行高与滑轨同挂 SLIDER_ROW_HEIGHT——24vp 装下 20vp 轨道）
              Row({ space: 12 }) {
                Text('提醒间隔')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .maxLines(1)
                Blank()
                Slider({
                  value: this.timeReminderMinutes,
                  min: TIME_REMINDER_MIN,
                  max: TIME_REMINDER_MAX,
                  step: TIME_REMINDER_STEP,
                  style: SliderStyle.InSet
                })
                  .width(SLIDER_ROW_WIDTH)
                  .height(SLIDER_ROW_HEIGHT)
                  .trackThickness(20)
                  .blockSize({ width: 12, height: 12 })
                  .trackBorderRadius(10)
                  // 半透明滑轨色 + 沉浸光感材质（粘贴卡同款单源）
                  .trackColor(sliderTrackColor(this.appColorMode))
                  .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
                  .borderRadius(10)
                  .systemMaterial(leveledUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                    resolveEffectiveLevel(this.immersiveLevel), false))
                  .onChange((v: number): void => {
                    // 整数域 + 域内钳位；@StorageLink 直写持久键 = 拖动即落盘（与粘贴卡同契约）
                    this.timeReminderMinutes = clampTimeReminderMinutes(v);
                  })
              }
              .width('100%')
              .height(SLIDER_ROW_HEIGHT)
              .alignItems(VerticalAlign.Center)
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        // ── 板块3 附件（图片链接作为图片发送 / 拍照保存到相册 + 粘贴长文本转文件卡）──
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: SECTION_ATTACHMENT })
          // 附件开关组卡（三行）
          ForEach([this.attachmentGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.attachmentGroup(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
          // 粘贴设置卡（决明拍板「做单卡，开关与滑块合一」）：形制与时间间隔提醒卡逐条同源——标题行（标题 + ⓘ +
          // 开关开时右侧蓝值与右箭头）/ 说明小字与开关同行 / 开关开时 0.5vp 分割线 + 下排（左侧「阈值」+ 右侧短滑轨）
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text(SETTING_TITLE_PASTE_AS_FILE)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                // 窄屏不足时标题先让位（三笔起滑轨加宽与右侧热区保形配套）——ⓘ/蓝值/箭头保形
                .flexShrink(1)
                .constraintSize({ maxWidth: this.pasteAsFile ? '55%' : '100%' })
              InfoHintButton({ text: PASTE_CARD_HINT })
              Blank()
              if (this.pasteAsFile) {
                Row({ space: 4 }) {
                  Text(pasteThresholdFormat(this.pasteThreshold))
                    .fontSize(15)
                    .fontColor($r('sys.color.ohos_id_color_emphasize'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([cardDescColor()])
                }
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.openPasteThresholdEdit();
                })
              }
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
              Divider()
                .strokeWidth(0.5)
                .color(cardBorderColor(this.appColorMode))
                .width('100%')
              // 下排 = 左侧「阈值」标签 + 右侧短滑轨（同上方时间卡；几何常量与滑轨卡同源）
              Row({ space: 12 }) {
                Text('阈值')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .maxLines(1)
                Blank()
                Slider({
                  value: this.pasteThreshold,
                  min: PASTE_THRESHOLD_MIN,
                  max: PASTE_THRESHOLD_MAX,
                  step: PASTE_THRESHOLD_STEP,
                  style: SliderStyle.InSet
                })
                  .width(SLIDER_ROW_WIDTH)
                  .height(SLIDER_ROW_HEIGHT)
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
              .width('100%')
              .height(SLIDER_ROW_HEIGHT)
              .alignItems(VerticalAlign.Center)
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
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
    .scrollBar(BarState.Off)
  }
}
