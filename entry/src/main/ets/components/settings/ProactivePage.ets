// 主动消息设置页：结构 = PageShell + 页首 info 蓝卡 + 单开关卡 + 三张滑轨卡（SliderValueCard 形制）
// + 说明小字。写操作即时持久化（@StorageLink 写即落盘）无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。
// · 总开关（单开关卡形制——恰 1 行开关项不组卡，规范红线 5）：标题 + 说明左列、官方 Toggle 右列
//   可点自切换 = 唯一控制面，行无点击区；关闭时调 cancelProactiveSchedule 清已排定时器即时生效，
//   已落消息不回收。
// ★ 决明指令：总开关关闭态下三张滑轨卡整体隐藏（只留开关卡 + 说明小字）——关闭态三枚参数都无消费方，
//   摆着只会诱导「关了还在调参」；开启态与现行形态逐字一致。判据 = @StorageLink proactiveEnabled
//  （写即落盘、Toggle 直切即重渲，无常驻缓存需失效）。
// · 三张滑轨卡（选择/内容卡形态——规范 §1.1 控件不套组卡行规格）：
//   ▸ 触发间隔 = 档位域 1~24 小时八档非等距，滑轨走索引映射 0~7（禁直挂小时值——等距滑轨配非等距
//     档会虚增中间档）；@State intervalIndex + @Watch 写回持久键；
//   ▸ 每日最多 = 连续域 1~10 条整数直映 + 编辑键精确输入（InputDialog 数字型，非法 toast 不静默）；
//   ▸ 静默期上限 = 档位域 1~30 分钟八档非等距，索引映射同触发间隔；实际等待在 1 分钟（写死下限）
//     与上限间随机，取 1 即固定 1 分钟；
//   ▸ @State + $ 传 @Link（坑16 家族契约——PageShell.content 内禁 @Prop 下发），滑轨 onChange 直写回
//     父 @State，@Watch 写 @StorageLink 即落盘（EntryAbility persistProp 区注册）；蓝值 = format 纯函数。
//   ▸ showEdit 分治：间隔/静默期八档离散域无中间值可输，传 false 整键隐藏；每日上限连续域默认 true
//     挂 onEdit 弹数字输入。
// · 无手动触发键（决明拍板「不做点击让 agent 发消息」）——唯一触发源 = 定时自动链；页面无档位选择
//   弹层（InputDialog 数字输入为编辑键专属）。
// · 说明小字 = InfoCard 单源件，文案守「面向用户文案写作规约」；决明「info 放到首卡」= 页首独立蓝卡、
//   总开关卡之前，关闭态恒显（恒在关闭态隐藏条件块外 = G8 断言语义不变）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { SliderValueCard } from '../SliderValueCard';
import { InputDialog } from '../chat/InputDialog';
import { InfoCard } from '../InfoCard';
import {
  SETTING_TITLE_PROACTIVE, SETTING_TITLE_PROACTIVE_DAILY_LIMIT,
  SETTING_TITLE_PROACTIVE_ENABLED, SETTING_TITLE_PROACTIVE_INTERVAL,
  SETTING_TITLE_PROACTIVE_QUIET_MAX
} from '../../common/SettingSearch';
import { cancelProactiveSchedule } from '../../common/ProactiveGen';
// 三档位键与档位域数组自零 import 叶子引（原自 ProactiveGen——与设置白名单 ToolPref 反向共享，落叶子后消环）
import {
  PROACTIVE_DAILY_LIMIT_DEFAULT, PROACTIVE_DAILY_LIMIT_KEY,
  PROACTIVE_DAILY_LIMIT_OPTIONS, PROACTIVE_ENABLED_KEY, PROACTIVE_INTERVAL_DEFAULT,
  PROACTIVE_INTERVAL_HOURS_KEY, PROACTIVE_INTERVAL_OPTIONS,
  PROACTIVE_QUIET_MAX_DEFAULT, PROACTIVE_QUIET_MAX_KEY, PROACTIVE_QUIET_MAX_OPTIONS
} from '../../common/ProactiveConfig';

// 间隔滑轨蓝值文案（索引 → 档位文案；越界防御回默认档——滑轨域 clamp 在卡内，此守卫只兜脏初值）
function intervalFormat(index: number): string {
  const hours: number = index >= 0 && index < PROACTIVE_INTERVAL_OPTIONS.length ?
    PROACTIVE_INTERVAL_OPTIONS[index] : PROACTIVE_INTERVAL_DEFAULT;
  return '每 ' + hours + ' 小时';
}

// 每日最多滑轨蓝值文案（条数直映）
function dailyLimitFormat(count: number): string {
  return '每天 ' + count + ' 条';
}

// 静默期滑轨蓝值文案（索引 → 档位文案；越界防御回默认档——同 intervalFormat 口径）
function quietMaxFormat(index: number): string {
  const minutes: number = index >= 0 && index < PROACTIVE_QUIET_MAX_OPTIONS.length ?
    PROACTIVE_QUIET_MAX_OPTIONS[index] : PROACTIVE_QUIET_MAX_DEFAULT;
  return '最长 ' + minutes + ' 分钟';
}

// 每日上限域最大值（档位域尾元素——滑轨 max 与编辑弹窗 placeholder/校验三处共用，禁写死双源）
const DAILY_LIMIT_MAX: number =
  PROACTIVE_DAILY_LIMIT_OPTIONS[PROACTIVE_DAILY_LIMIT_OPTIONS.length - 1];

@Component
export struct ProactivePage {
  // 顶部/底部留白（vp，导航壳下发）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // pathStack（PageMap 形态对齐记忆分支——本页无 push 动作，纯占位成员）
  pathStack: NavPathStack = new NavPathStack();
  // 单开关卡卡底深浅色（自绘卡先例成员——PreferencesPage 界面观感卡同款）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 持久键（@StorageLink 写即持久化——EntryAbility persistProp 区注册；两滑轨 @State 写回这里）
  @StorageLink(PROACTIVE_ENABLED_KEY) proactiveEnabled: boolean = false;
  @StorageLink(PROACTIVE_INTERVAL_HOURS_KEY) intervalHours: number = PROACTIVE_INTERVAL_DEFAULT;
  @StorageLink(PROACTIVE_DAILY_LIMIT_KEY) dailyLimit: number = PROACTIVE_DAILY_LIMIT_DEFAULT;
  @StorageLink(PROACTIVE_QUIET_MAX_KEY) quietMaxMinutes: number = PROACTIVE_QUIET_MAX_DEFAULT;
  // 滑轨域状态（@State + $ 传 @Link——坑16 契约；@Watch 写回持久键 = 写即落盘；初值仅占位，
  // aboutToAppear 从持久键取真值）
  @State @Watch('onIntervalSliderChange') intervalIndex: number =
    PROACTIVE_INTERVAL_OPTIONS.indexOf(PROACTIVE_INTERVAL_DEFAULT);
  @State @Watch('onDailySliderChange') sliderDailyLimit: number = PROACTIVE_DAILY_LIMIT_DEFAULT;
  @State @Watch('onQuietSliderChange') quietIndex: number =
    PROACTIVE_QUIET_MAX_OPTIONS.indexOf(PROACTIVE_QUIET_MAX_DEFAULT);
  // 每日上限编辑弹窗控制器（CustomDialogController 须组件成员位构造——坑7；弹一次 new 一次，无 dispose 面）
  private dailyLimitEditCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 间隔索引从持久键取（脏持久值不在档位域 → 回默认档；赋值即触发 @Watch 把脏值归正落盘）
    const idx: number = PROACTIVE_INTERVAL_OPTIONS.indexOf(this.intervalHours);
    this.intervalIndex = idx >= 0 ? idx :
      PROACTIVE_INTERVAL_OPTIONS.indexOf(PROACTIVE_INTERVAL_DEFAULT);
    // 每日最多同口径白名单守卫（脏持久值如 99 直赋会让蓝值出「99 条」而守卫③按 1 兜底，
    // UI 与实际行为脱钩且无自愈；赋默认档即触发 @Watch 把持久键一并归正）
    this.sliderDailyLimit = PROACTIVE_DAILY_LIMIT_OPTIONS.includes(this.dailyLimit) ?
      this.dailyLimit : PROACTIVE_DAILY_LIMIT_DEFAULT;
    // 静默期上限同口径白名单守卫（脏持久值不进滑轨域，resolveQuietMaxMinutes 按 5 兜底）
    const quietIdx: number = PROACTIVE_QUIET_MAX_OPTIONS.indexOf(this.quietMaxMinutes);
    this.quietIndex = quietIdx >= 0 ? quietIdx :
      PROACTIVE_QUIET_MAX_OPTIONS.indexOf(PROACTIVE_QUIET_MAX_DEFAULT);
  }

  // 间隔滑轨 → 持久键（索引换算小时档写入；写即落盘）
  private onIntervalSliderChange(): void {
    this.intervalHours = PROACTIVE_INTERVAL_OPTIONS[this.intervalIndex];
  }

  // 每日最多滑轨 → 持久键（条数直映）
  private onDailySliderChange(): void {
    this.dailyLimit = this.sliderDailyLimit;
  }

  // 静默期滑轨 → 持久键（索引换算分钟档写入；写即落盘）
  private onQuietSliderChange(): void {
    this.quietMaxMinutes = PROACTIVE_QUIET_MAX_OPTIONS[this.quietIndex];
  }

  // 每日上限编辑键弹窗（InputDialog 数字型；初值预填当前值，成员位 Ctrl 弹一次 new 一次）
  private openDailyLimitEdit(): void {
    this.dailyLimitEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: SETTING_TITLE_PROACTIVE_DAILY_LIMIT,
        initialText: String(this.sliderDailyLimit),
        placeholder: '1~' + DAILY_LIMIT_MAX + ' 的整数',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyDailyLimitInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.dailyLimitEditCtrl.open();
  }

  // 每日上限手动输入解析（整数 + 白名单域校验，与页面/守卫③同口径；非法 toast 不静默）。
  // 合法写 @State 即触发 @Watch 落盘，与滑轨 onChange 同路
  private applyDailyLimitInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() ||
      !PROACTIVE_DAILY_LIMIT_OPTIONS.includes(v)) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 1~' + DAILY_LIMIT_MAX + ' 的整数'
      });
      return;
    }
    this.sliderDailyLimit = v;
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // info 蓝卡（决明「info 放到首卡」= 像其他页放页面顶部）：页首独立蓝卡、总开关卡之前；
        // 关闭态恒显——它讲的是这个开关干什么，关闭态正是最需要它的时候；恒在条件块外 =
        // G8 断言语义不变；InfoCard 缺省挂 CARD_PANEL_WIDTH（宿主无水平 padding，规范 §4.3）
        InfoCard({ text: '开启后应用在前台时助手会偶尔主动发来消息。触发间隔、每日最多与静默期上限都在本页调整，所用模型与记忆整理相同，在功能模型页设置。关闭后立即停发，已收到的消息保留。' })
        // 总开关（单开关卡形制——规范红线 5 恰 1 行开关项不组卡；Toggle 可点自切换 = 唯一控制面，
        // 无行点击区）
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_PROACTIVE_ENABLED)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('助手偶尔主动发来一条消息')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.proactiveEnabled })
            .onChange((isOn: boolean): void => {
              this.proactiveEnabled = isOn;
              if (!isOn) {
                // 关闭即时生效：清已排检查（§二.10——开启开关不触发立即发送，关闭反过来撤掉排着的检查）
                cancelProactiveSchedule();
              }
            })
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 三张滑轨卡（关总开关时整体隐藏——见头注释；说明小字不随之隐藏，故三卡入条件分支后小字
        // 自然上移到总开关卡下方）
        if (this.proactiveEnabled) {
          // 触发间隔滑轨卡（档位域 1~24 八档非等距 → 索引 0~7 映射；档位数组即域单源）
          SliderValueCard({
            title: SETTING_TITLE_PROACTIVE_INTERVAL, value: $intervalIndex,
            min: 0, max: PROACTIVE_INTERVAL_OPTIONS.length - 1, step: 1,
            format: intervalFormat,
            desc: '两次主动消息之间的最短间隔。间隔越短，消息越频繁',
            rowLabel: '间隔',
            showEdit: false
          })
          // 每日最多滑轨卡（连续域 1~10 整数直映 + 编辑键精确输入——域扩宽见头注释）
          SliderValueCard({
            title: SETTING_TITLE_PROACTIVE_DAILY_LIMIT, value: $sliderDailyLimit,
            min: PROACTIVE_DAILY_LIMIT_OPTIONS[0],
            max: DAILY_LIMIT_MAX,
            step: 1,
            format: dailyLimitFormat,
            desc: '每天主动消息的条数上限。调低不回收当天已发的消息',
            rowLabel: '每日上限',
            onEdit: (): void => {
              this.openDailyLimitEdit();
            }
          })
          // 静默期上限滑轨卡（档位域 1~30 分钟八档非等距 → 索引 0~7 映射；实际等待在 1 分钟
          // 与上限间随机）
          SliderValueCard({
            title: SETTING_TITLE_PROACTIVE_QUIET_MAX, value: $quietIndex,
            min: 0, max: PROACTIVE_QUIET_MAX_OPTIONS.length - 1, step: 1,
            format: quietMaxFormat,
            desc: '回前台后先静默一段时间再发消息。实际等待在上限内随机，上限越大越不易触发',
            rowLabel: '静默上限',
            showEdit: false
          })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（Scroll align 默认 Center——坑18）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_PROACTIVE,
      content: (): void => {
        this.Content();
      }
    })
  }
}
