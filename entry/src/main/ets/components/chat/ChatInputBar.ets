// 聊天输入栏（2026-08-29 自 dshinhm ChatInputBar 去 kap 改造迁入）：结构 = 参数 chip 行
//（ChatParamChipRow，仅思考 chip——联网/状态入口均已迁出本行）→ 胶囊输入框（发送/停止键
// 并入胶囊内，附件条在输入行上方、attachments 非空才渲染）→ 合规提示行（藏字不塌位，见
// keyboardOn 字段注释）。回顶/回底悬浮键已退役（留档 docs/归档/退役实现-回顶回底键-20260909.md）。
// ★ busy 期发送（2026-10-17 排队插队总案 Q2 起，取代 M1「运行中不插话」）：键盘发送经 send
// 守卫自动入队；busy 且草稿非空且无附件时停止键**同键位替换为发送键**（点击即入队，零增高
// 底带），其余 busy 情形保留停止键。dbReady = DB 未就绪占位符切换 + 发送键禁点（P0-1 不静默）。
// 多行自增高（dshinhm 三改定稿）：TextArea 不设高度自适应内容，constraintSize 钳制行数——
// 展开态 2~4 排完整显示、5 排起钳顶框内滚动；收起态上下限同钉 INPUT_MIN_HEIGHT、maxLines
// 收 1 行（CLIP 截断，高度与内容无关）。显式 lineHeight 使换算确定；半圆圆角 = 单行高一半；
// 图标键底对齐贴底。
// 沉浸光感（2026-09-03 三轮实测定稿）：实底态 = Theme.fallbackGrayBg 随卡底透明度档（零实时
// 渲染——backgroundEffect 真机卡顿已撤销，实验记录见 ChatPageContent 蒙层注释）；光感态 =
// REGULAR 系统材质。实底态下背景色可设、圆角靠 borderRadius + clip；发送键 = 强调色图标
// 无底无材质，停止键 = 官方 warning 色。底部 90vp 渐变蒙层不在本组件（挂消息列表）。
// 聚焦展开（2026-09-09）：点输入框 → 单排胶囊展开为两排卡（文本行 + 工具行），失焦延时复位。
// 硬约束 = TextArea 单实例（两态共用同一个，禁放进 if 分支——重建丢焦点/光标/已输入文本）；
// ＋ 与发送·停止键 @Builder 抽一次、两态各实例化一处（按钮无状态，重建无副作用）。
// 常驻展开开关（2026-10-03，PREF_INPUT_EXPANDED_KEY）：开 = 进页静默置位展开态且失焦不收起
//（applyAlwaysExpanded，不走 setExpanded 避免永久合闸进页校正链）；键盘避让与形态解耦。
// 工具行内缩同心（TOOL_KEY_INSET）、收起态收窄（INPUT_COLLAPSED_INSET）、chip 行收起态
// 隐藏与菜单期不收（build 内 chip 行 / chipMenuOpen）——机制注释各见其处。
import { PendingAttachment } from '../../common/providers/AiTypes';
import { AttachmentStrip } from './ChatAttachmentStrip';
import { ChatQuoteBar } from './ChatQuoteBar';
import { ChatSkillBar } from './ChatSkillBar';
import { ContextUsageRing } from './ContextUsageRing';
import { ChatParamChipRow, CHAT_AI_ADMIN_OWNER_KEY } from './ChatParamChipBar';
import { SecureInputSheet } from './SecureInputSheet';
import { sheetPanelOptions } from './KimiSheetCommon';
import { clearPendingKey, keyHintOf, PENDING_KEY_SLOT_KEY } from '../../common/store/KeyStore';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { curves, KeyboardAvoidMode, uiMaterial, window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cardDescColor, fallbackGrayBg, menuDividerColor, menuEndCheck } from '../../common/Theme';
import {
  PASTE_THRESHOLD_DEFAULT, PREF_INPUT_EXPANDED_KEY, PREF_KEYBOARD_SEND_KEY, PREF_PASTE_AS_FILE_KEY,
  PREF_PASTE_AS_FILE_THRESHOLD_KEY, clampPasteThreshold, PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT,
  CHAT_PERMISSION_MODE_KEY, PREF_DEFAULT_PERMISSION_MODE_KEY
} from '../../common/AppPreferences';
import { settlePastedText, shouldInterceptInsert, shouldPasteAsFile } from './AttachmentPickCtrl';
import { AI_CONTENT_LABEL } from '../../common/AiDisclosure';
import {
  PERMISSION_MODE_CAUTIOUS, PERMISSION_MODE_STANDARD, PERMISSION_MODE_FULL,
  effectivePermissionMode, permissionModeLabel, setSessionPermissionMode
} from '../../common/chat/PermissionMode';

// 输入框几何常量（dshinhm 三改定稿值随迁）：单行高 50 = 行高 21 + 上下 padding 14.5×2；
// 上限 113 = 21×4 行 + 29——展开态底部 padding 归 0 后可视约 4.7 排，超出框内滚动；
// 半圆角 = 单行高一半
const INPUT_LINE_HEIGHT: number = 21;
const INPUT_VPAD: number = 14.5;
// 最小高度 = 收起态固定高度（决明「收起后不论有无内容高度均一致」——收起态上下限同钉本值，
// 多行内容裁到一排，见 TextArea 处注释）
const INPUT_MIN_HEIGHT: number = INPUT_LINE_HEIGHT + INPUT_VPAD * 2;
const INPUT_MAX_HEIGHT: number = INPUT_LINE_HEIGHT * 4 + INPUT_VPAD * 2;  // 113，最大高度
// 展开态行数上限 = 官方非内联模式 maxLines 默认值 UINT32_MAX（显式回填同值：两态共用一个
// maxLines 表达式，展开态行为与未设置时一致——不截断，超出 4 排仍由 constraintSize 钳顶）
const INPUT_EXPANDED_MAX_LINES: number = 4294967295;
const INPUT_CAPSULE_RADIUS: number = INPUT_MIN_HEIGHT / 2;  // 25，半圆
// 收起态左右内缩（2026-09-09 决明拍板，单侧 36vp）；展开态归 0。单旋钮：观感不够短/太短
// 只改本值；平板按绝对值收窄、不随屏宽放大，观感不足再改比例
const INPUT_COLLAPSED_INSET: number = 36;
// 输入栏图标键尺寸（＋ / 发送·停止两键同规格、两态共用；36 = 点击区，圆形按压
// 蒙层直径同此值——蒙层圆心即键中心，下面的同心内缩推算依赖本值）
const INPUT_KEY_SIZE: number = 36;
// 展开态文字区底部内边距（决明「裁切边界调小、贴工具栏」；顶部仍 INPUT_VPAD，本常量只管
// 底部）：展开态底部 padding 归 0——文字贴工具行顶边；收起态仍用 INPUT_VPAD
const EXPANDED_TEXT_BOTTOM_VPAD: number = 0;
// 聚焦展开几何：总高 94 = 文本行 50 + 工具行 44（决明「撑三排字」口径 92 基本重合）；
// 观感唯一可调点 = 工具行高与文本行上下 padding 两值（勿改结构）
const INPUT_EXPANDED_HEIGHT: number = 94;
// 工具行高（44 = 94 − 50）
const TOOL_ROW_HEIGHT: number = INPUT_EXPANDED_HEIGHT - INPUT_MIN_HEIGHT;
// 工具行内缩（2026-09-09 决明「贴边 + 点击蒙层圆与胶囊圆角同心」）：键中心与胶囊圆角弧心
// 重合——弧心距侧/底各 INPUT_CAPSULE_RADIUS(25)，键半径 18 → 左右与底部内缩同为 7；顶部由
// 行高反推 = 44 − 36 − 7 = 1（键中心与弧心同一水平线）。
// ★ 下发方式（真机报障后定）：水平内缩走工具行 padding，**垂直内缩走键/文字外边距**——
// 行高收起态为 0，行自身的垂直 padding 会把最小高度撑到 padding 之和（真机实测：收起态
// 胶囊被撑高、两键失中）；子元素外边距不改显式高度，且收起态内容被 clip 裁掉观感零差异
const TOOL_KEY_INSET: number = INPUT_CAPSULE_RADIUS - INPUT_KEY_SIZE / 2;  // 7
const TOOL_ROW_TOP_INSET: number = TOOL_ROW_HEIGHT - INPUT_KEY_SIZE - TOOL_KEY_INSET;  // 1
// 失焦收起延时（ms）：点工具行按钮若夺焦，blur 先于 click 到达——Down 取消（时序守卫，
// 见 startCollapseTimer / cancelCollapseOnTouch）
const INPUT_COLLAPSE_DELAY: number = 150;
// 输入文本区节点 id：推荐语回填时程序化聚焦的目标 key（requestFocus 按组件 id 定位），
// 聚焦成功即走既有 onFocus 链（展开 + 避让 + 弹键盘），零新机制
const INPUT_TEXTAREA_ID: string = 'chatInputTextArea';
// 键盘态底部留白切换动画时长（ms，与系统键盘动画同量级；观感可调）
const KEYBOARD_INSET_ANIM_MS: number = 250;
// 浮层行间距（外层 Column 的 space 值）：chip 行 / 胶囊 / 合规提示行之间
const BAND_ROW_SPACING: number = 8;
// 合规提示行几何：11fp 单行显示高取 16；Text 与键盘态占位共用同一常量——占位镜像文本高度，
// 浮层总高恒定（输入框零位移防闪动/被遮，见 keyboardOn 注释）
const COMPLIANCE_HINT_HEIGHT: number = 16;
// 胶囊内临时条几何（待发条退役后消费方 = 编辑态提示条 + 暂存密钥条；常量名保留旧称不改，
// 防全仓引用漂移）：容器位置与对齐照 AttachmentStrip（胶囊内顶部、左右留白 12）；条体 =
// 灰底圆角横条（Theme.fallbackGrayBg 随卡底透明度档，不接光感；禁同层再设 systemMaterial
// ——单层组合红线）。暂存密钥条内缩经外包 Column padding 下发（坑 23，2026-11-04 案甲收口）
const DESIGNATE_STRIP_HPAD: number = 12;
const DESIGNATE_STRIP_TOP: number = 12;
const DESIGNATE_STRIP_RADIUS: number = 12;
// ── 上下文用量圆环键（2026-09-17，拍板 P1/P2；2026-10-31 右移落右侧键组发送键左侧——
// 原全屏键位，全屏入口已迁输入框选择菜单）：收起态随工具行高度归零整体隐藏；环本体 =
// ContextUsageRing 共用件（形制单源）；垂直内缩同相邻键 ──

@Component
export struct ChatInputBar {
  // 会话运行中（true = 停止键；排队总案起 busy 期键盘发送自动入队，busy 且草稿非空且无附件
  // 时本位渲染发送键〔点击入队〕，输入框仍可编辑）。@Link 归正（原 @Prop 经 PageShell.content
  // 断点，重启后冻结首帧——坑16 家族处置「同族通道升 @Link」）
  @Link busy: boolean;
  // DB 就绪（M1 既有行为：未就绪占位符切换 + 发送键禁点）
  @Prop dbReady: boolean = true;
  // 常态底部留白（页面注入 = 避让区高 + 悬浮页签让位，约 100vp；键盘升起时本组件置 0——
  // 键盘已覆盖底部系统区，注入值此时冗余，正是「不遮挡但抬起过高」的间距来源）。
  // @Prop：navBarHeight 异步实测，须状态驱动重渲染（坑57 同族）
  @Prop bottomPad: number = 0;
  // 只上报胶囊本体的窗口坐标；参数行和合规提示行不冒充正文阅读边界（浮层几何变化经宿主
  // 底带单源逐帧跟随，含展开/收起）
  onReadingTop: (top: number) => void = () => {};
  private inputFocused: boolean = false;
  // 展开态上报：true = 输入框展开 → 父组件合闸暂停进页校正链的拽底，收起动画结束时回落
  // false 开闸（展开/收起浮层高度都会变，链若存活会把列表无动画拽到底——「进会话后展开
  // 输入框页面仍上移」根因）
  onExpandState: (expanded: boolean) => void = () => {
  };
  // 待发附件（父组件 @State 持有，数组赋值触发 @Prop 刷新；非空即渲染附件条）
  @Prop attachments: PendingAttachment[] = [];
  // 思考强度（'' = 默认不传；@Link 归正——@Prop 经 PageShell.content 不随父刷新〔坑16〕，
  // 选档后 chip 回显会冻结）。菜单选项集不入参——chip 行自订阅广播键（坑16 同款正解）
  @Link thinkingValue: string;
  // 档位选择回调（父组件落值回显——占位不进请求；消费方 = 回退路径 chip）
  onPickThinking: (option: string) => void = () => {
  };
  // 标题栏思考键交互期（按压期与菜单期经 ChatPage → ChatPageContent 三级 @Link 链下行，
  // 与 chipMenuOpen / chipTouchActive 共同构成「交互期不收」守卫；@Link 因坑16——@Prop 经
  // PageShell.content 不随父刷新会冻结首帧）
  @Link thinkingHold: boolean;
  // 单条消息指定技能（'' = 未指定；@Link 三级链坑16 正解通道——@Prop 经 PageShell.content
  // 不随父刷新会冻结首帧）；id/名两链消费方 = 状态键携带态换色判据（statusIconColor）、
  // canSend 与技能条 ChatSkillBar（名链 2026-11-02 技能条笔随新条复建）
  @Link designatedSkillId: string;
  @Link designatedSkillName: string;
  // 技能条 × 键上行：取消指定（链回页面清两值；命名避开 onClearDesignate 子串——104 组负向钉）
  onRemoveSkillDesignate: () => void = () => {
  };
  // 状态键点击上行（父组件经页面 sheetCtrl 拉起会话状态半模态——纯只读入口）
  onOpenStatus: () => void = () => {
  };
  // 待发引用（null/'' = 无引用，引用条零占位）；@Link 通道理由同 designatedSkillId（坑16）。
  // 呈现与完整引用半模态全在 ChatQuoteBar（本件只挂条接线）
  @Link quoteText: string | null;
  // 引用条 × 键上行：清待发引用（链回写页面 pendingQuote = null）
  onDismissQuote: () => void = () => {
  };
  // 发送回调（text 已 trim；附件随上抛）。返回值 = 「已投递或已进入确认流程」——两处调用点
  // 按它决定清不清本地草稿（false = 被拦，文字留在条上）
  onSend: (text: string, attachments: PendingAttachment[]) => boolean = (): boolean => false;
  // 中断回调（busy 时点击停止键）
  onAbort: () => void = () => {
  };
  // 「+」点击（附件与提示词面板入口——上行父组件开 ChatPromptSheet 半模态）
  onAddFile: () => void = () => {
  };
  // 长文本粘贴上行：页面把文本转成附件入列，完成后以 settle(converted) 回报结果——**必调
  // 恰一次**（成功真、未入列假）；收口闭包据此对齐「附件与原文恰有其一」（见 onPaste 注释）。
  // ★ 默认实现 = settle(false) 而非空体：宿主漏接线时空体 = 长文本静默消失（既不入框也不转
  // 件）；settle(false) 让漏接线退化成「不转附件、原文照常落框」（P0-1 禁静默失败）
  onPasteLongText: (text: string, settle: (converted: boolean) => void) => void =
    (_text: string, settle: (converted: boolean) => void): void => {
      settle(false);
    };
  // 附件行删除（index 上行父组件从列表移除——本地状态独占，无网络副作用）
  onRemoveAttachment: (index: number) => void = () => {
  };
  // 已选未发附件点开预览（fileId 上行 → ChatPageContent 分派，与消息流附件泡同一查看器）
  onPreviewAttachment: (fileId: string) => void = () => {
  };
  // 全屏输入：点输入框文字选择菜单「全屏输入」项上行当前文本（父暂存为面板初值）——胶囊
  // 文本是本组件 @State，父页拿不到，必须随回调带出。2026-10-31 自工具行图标键迁入选择菜单
  //（决明拍板；渲染位置 = 系统二级区，见 inputTextMenu 注释）
  onFullscreen: (text: string) => void = () => {
  };
  // 上下文用量圆环值：-1 = 窗口未知或无数据（仅底环仍可点，点开面板看已用数）；0~100 =
  // 已用占比（页面侧活算刷新：发送收尾/切模型/开面板时刷，打字与生成中不刷）。@Link 三级链
  // 坑16 正解通道（@Prop 经 PageShell.content 不随父刷新会冻结首帧，同 modelLabel 先例）
  @Link ctxRingPct: number;
  // 圆环点击上行（带当前草稿文本——胶囊文本是本组件 @State，父页拿不到，须随回调带出）
  onOpenContext: (text: string) => void = () => {
  };
  // 全屏输入回写通道（父持命令制造 @Prop——cmd tick 驱动覆盖（含空串清空）；只写于两时点：
  // 面板关闭回写 / 发送清空——正常打字父不改，无输入回环；⚠️ @Watch 首次不触发（初始 0，
  // 父命令 tick 从 1 起）
  @Prop fullInputDraft: string = '';
  @Prop @Watch('onFullInputCmd') fullInputCmd: number = 0;
  // 推荐语回填命令（常规父子 @Prop 绑定）：tick 触发即覆盖文本并聚焦自身 TextArea 进入编辑
  // 态（展开 + 弹键盘由聚焦链 onFocus 自动接管）。与 fullInput 通道刻意独立：那是「静默覆盖」
  //（面板关闭回写/发送清空，不聚焦），本通道语义 = 填入并进入编辑态。
  // ⚠️ @Watch 首次不触发（初始 0，命令 tick 从 1 起）
  @Prop suggestFillDraft: string = '';
  @Prop @Watch('onSuggestFillCmd') suggestFillCmd: number = 0;
  // 当前模型名（工具行只读文字退役后，消费方 = 状态图标键「未选模型」红档判据
  // statusIconColor；'' = 未解析到连接）。@Link 三级链坑16 正解通道；不另建全局广播键
  //（新增键牵动断言白名单与键治理）
  @Link modelLabel: string;
  // 草稿文本上行（2026-10-20 会话草稿持久化）：@Watch 对 $$ 用户输入与全部程序写点（命令
  // 回填/发送清空/粘贴收口）任一赋值都上行，父页 draftTextLive 恒等于框内文本（离页保存读
  // 它）；首次初始化与同值赋值不触发，无害
  @State @Watch('onDraftTextSync') private text: string = '';
  // 草稿上行回调（每键一次，父页实现只做普通成员赋值——状态最小化，无 UI 刷新）
  onDraftTextChange: (text: string) => void = () => {
  };
  // 聚焦展开：true = 两排卡（文本行 + 工具行），false = 单排胶囊；只此一个状态，驱动工具
  // 行高度（恒存在 + 高度 0/44 切换，见 build）
  @State private expanded: boolean = false;
  // 失焦延时收起定时器（-1 = 无待收起；与组件销毁成对清理，见 aboutToDisappear）
  private collapseTimer: number = -1;
  // chip 菜单开着（真机报障：点 chip 开菜单致 TextArea 失焦〔菜单弹窗取焦〕，收起链把卡片
  // 收掉、菜单随浮层下移——故菜单开着期间一律不收）：驱动 = MenuOptions.onAppear/onDisappear
  // 经 ChatParamChipRow 上报；决明语义「展开态只有系统返回或收起键盘才收起」，菜单关闭后也
  // 不补收，等下一次失焦/键盘事件
  private chipMenuOpen: boolean = false;
  // chip 行手指按着（Down 置位、Up/Cancel 复位；与 chipMenuOpen 共同构成「chip 交互期不收」守卫）：
  // blur 若发生在 Down 之后（按钮夺焦路径），150ms 计时器会在菜单弹出前触发——Down 取消只能掐掉
  // 已存在的计时器、掐不掉 blur 之后新挂的，故用按位标志把整个按压期封住（onFocus 一并自愈）
  private chipTouchActive: boolean = false;

  // ── 合规提示行显隐驱动（2026-09-03）──
  // ★ 键盘弹起时**藏字不塌位**（决明真机反馈「抬起后输入框偏低被遮 + 移动不连贯闪动」定稿）
  // ——只隐藏文字，布局空间由等高空占位撑住（build 内双分支同 COMPLIANCE_HINT_HEIGHT），
  // 浮层总高恒定 → 输入框**零位移**：只随窗口 RESIZE 单方向平滑上移，最终态完整暴露于键盘
  // 上方。初版「隐藏即塌陷」（提示行消失下跳 24vp）= 闪动 + 最终态过低的同一根因。
  // 驱动 = window.on('keyboardHeightChange')（官方键盘专用事件，回调直接给 px 高度，弹起/
  // 收起/切换输入法均触发；事件式零轮询——P1-2）。不用 avoidAreaChange + visible——真机
  // 实测键盘未弹也 true（提示行闪现消失）。初值经 getWindowAvoidArea 同步读兜底——事件只报
  // 「变化」，注册前已弹起的状态不会补发。判定仅驱动文字显隐 → 键盘收起恢复显示
  @State private keyboardOn: boolean = false;
  // window 句柄（off 需同一实例——aboutToDisappear 成对注销，坑33 注册/监听成对释放
  // 红线；置 null 防悬空）
  private windowRef: window.Window | null = null;
  // 组件已退场守卫：getLastWindow 异步——回调落地前组件可能已销毁，防「销毁后注册」泄漏
  private departed: boolean = false;
  // 键盘高度回调（成员引用——off(type, callback) 要求同一函数引用；px 判 >0 无需换算）。
  // ★ 2026-09-09：状态切换包进 animateTo——底部留白随之在「页面注入值 ↔ 0」间平滑过渡
  //（与系统键盘动画同量级；否则键盘尚未盖住底部区时留白已瞬降，输入栏会先向下弹一下）
  private onKeyboardHeight = (height: number): void => {
    const on: boolean = height > 0;
    if (on === this.keyboardOn) {
      return;
    }
    this.getUIContext().animateTo({ duration: KEYBOARD_INSET_ANIM_MS, curve: Curve.EaseOut }, () => {
      this.keyboardOn = on;
    });
  };

  // 恒展开对齐：开关开且当前收起 → 静默置位展开态。★ 不走 setExpanded(true)——展开即合闸
  // onExpandState（父组件暂停进页校正链拽底），而**恒展开模式没有收起动画来开闸**，进页末条
  // 定位校正链会被永久 hold 挂死；直接赋值无动画，进页首帧无突跳。★ 不做「关 → 收起」：关后
  // 已展开的框等下一次失焦自然收（收起链守卫只看本键现值，见 startCollapseTimer）
  private applyAlwaysExpanded(): void {
    if (this.alwaysExpanded && !this.expanded) {
      this.expanded = true;
    }
  }

  private onInputExpandedChanged(): void {
    this.applyAlwaysExpanded();
  }

  aboutToAppear(): void {
    // 会话权限模式不在本件复位（2026-11-09 自检轮改）：档位按会话分别记，边界收敛到
    // ChatPage.enterConversation（只有会话 id 变了才换档）——本件在「退出重进同一会话」
    // 时会重建，若在这里清键就会把用户刚选的档抹掉（决明实报）。完全权限不跨会话继承
    // 仍由 enterConversation 的 id 判据保证。
    // 恒展开初态：进页即展开（@StorageProp 同步生效，读值即键现值；理由见 applyAlwaysExpanded）
    this.applyAlwaysExpanded();
    // 键盘监听注册（与 aboutToDisappear 的 off 成对）；注册后同步读一次补初始（事件只报
    // 「变化」，注册前已弹起的键盘状态不会补发——本 SDK getWindowAvoidArea 为同步接口）
    this.departed = false;
    const uiContext = this.getUIContext();
    const hostContext = uiContext.getHostContext();
    if (!hostContext) {
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window) => {
      if (this.departed) {
        return;
      }
      this.windowRef = win;
      win.on('keyboardHeightChange', this.onKeyboardHeight);
      this.keyboardOn = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height > 0;
    }).catch((err: Error) => {
      // 监听失败保持 keyboardOn=false（提示行常显）——纯 UI 观感降级，不影响功能；
      // 按 P0-1 不静默失败，打日志
      hilog.error(0xD5A0, 'ChatInput', 'keyboard listen failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 暂存密钥槽清出：暂存明文寿命 = 会话页，离开即弃（决明拍板「未配置不保存，跟未发送的
    // 会话附件一样」；assign_key 配出与显示条 × 键另有清点）
    clearPendingKey();
    // 键盘避让模式兜底恢复（防「聚焦态被销毁」把窗口级模式留在 RESIZE——与 onBlur 成对，
    // 幂等重复设同值无副作用）
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    // 收起定时器成对清理（与 startCollapseTimer 成对）
    this.cancelCollapseTimer();
    // 键盘监听注销（与 aboutToAppear 的 on 成对——坑33 红线）
    if (this.windowRef !== null) {
      this.windowRef.off('keyboardHeightChange', this.onKeyboardHeight);
      this.windowRef = null;
    }
  }

  // 回写命令消费（变量挂 @Watch：父 tick 一触发即用 draft 覆盖文本——含空串清空）
  private onFullInputCmd(): void {
    this.text = this.fullInputDraft;
  }

  // 草稿上行 @Watch 体（见 text 字段注释——只转发，零额外逻辑）
  private onDraftTextSync(): void {
    this.onDraftTextChange(this.text);
  }

  // 推荐语回填命令消费：覆盖文本 → 聚焦自身 TextArea（展开/避让/弹键盘全由既有 onFocus 链
  // 自动接管，零新机制）。聚焦失败降级 = 文字已填入但不展开不弹键盘（理论不可达：组件恒在
  // 树、TextArea 恒可聚焦）；P0-1 不静默（catch 兜 150001~150003，留痕 hilog）
  private onSuggestFillCmd(): void {
    this.text = this.suggestFillDraft;
    try {
      this.getUIContext().getFocusController().requestFocus(INPUT_TEXTAREA_ID);
    } catch (err) {
      hilog.warn(0xD5A0, 'ChatInput', '推荐语回填聚焦失败：%{public}s', JSON.stringify(err));
    }
  }
  // 沉浸光感档位（光感态 = REGULAR 材质随沉浸光感总档偏移）
  // 会话权限模式（2026-11-09 真完全权限笔）：两枚 @StorageProp 只作刷新驱动，值恒由
  //  effectivePermissionMode() 现读单源（会话覆盖 > 应用默认档 > '' 迁移态）。
  // ★ 用广播键自订阅而非 @Link 三级链：坑16 正解，也避开 ChatPage / ChatPageContent
  //  两张越线文件的实质改动；完全权限只存内存，不落库、不进备份表。
  @StorageProp(CHAT_PERMISSION_MODE_KEY) sessionModeTick: string = '';
  @StorageProp(PREF_DEFAULT_PERMISSION_MODE_KEY) defaultModeTick: string = '';
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：true = 胶囊官方灰实底（默认）；false = REGULAR 材质光感；订阅式切换
  // 即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 深浅模式 + 卡底透明度档位（2026-10-25）：胶囊与指定条灰底 Theme.fallbackGrayBg 随档叠
  // alpha 需两实参（订阅即刷，拖动滑轨返回立变）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 键盘发送开关：true = 键盘回车键变发送键（onSubmit 直接发送）；false = 换行键（官方默认）。
  // 订阅切换即刷（坑16 正解）
  @StorageProp(PREF_KEYBOARD_SEND_KEY) keyboardSend: boolean = false;
  // 输入框常驻展开（2026-10-03 拍板）：true = 恒展开态（失焦不收起，守卫见 startCollapseTimer）；
  // @Watch 偏好页中途切换即对齐——只做「开 → 展开」单向置位，不做「关 → 收起」（关后等下一次
  // 失焦自然收，避免会话页形态突跳）
  @StorageProp(PREF_INPUT_EXPANDED_KEY) @Watch('onInputExpandedChanged') alwaysExpanded: boolean = false;
  // 粘贴长文本转文件：开关与长度阈值两键自订阅（偏好页切换即刷，坑16 正解）。★ 阈值经
  // clampPasteThreshold 钳位后再进判定（老备份或手改值越界会让判定静默失效）
  @StorageProp(PREF_PASTE_AS_FILE_KEY) pasteAsFile: boolean = true;
  @StorageProp(PREF_PASTE_AS_FILE_THRESHOLD_KEY) pasteThreshold: number = PASTE_THRESHOLD_DEFAULT;
  // 已被 onPaste 受理的那段原文：防两条通路对同一段文本各转一次——onWillInsert 见到与它
  // 逐字相同的插入即放行。★ 生命期 = 一次受理（onPaste 收口回调里复位）——原版只写不清会让
  //「先长按粘过、再键盘剪贴板粘同段」被当重复放行；哨兵问的是「这一笔是否已被受理」
  private lastPasteHandled: string = '';

  // ── 输入框文字选择菜单扩展（2026-10-31）：系统项全保留 + 追加「全屏输入」纯文字项，机制
  // 同 MessageCopySheet.quoteMenu（editMenuOptions 挂 TextArea）。★ 渲染位置 = 系统二级区：
  // editMenuOptions 自定义项真机恒落二级，一级图标行无应用可控途径（bindSelectionMenu 自绘
  // 选择菜单仅 Text 组件支持〔text.d.ts，TextArea 无此 API，仅 selectionMenuHidden〕；d.ts
  // onCreateMenu 注释「输入与返回只含一级菜单项、二级不进回调」与真机观察互证）——决明拍板
  // 做不到一级即落二级。触发 = 长按/选中输入框内文字；空框能否唤出菜单属平台行为（真机验收
  // 项）。菜单 id 先存成员勿每击新建（TextMenuItemId.of 返回比对身份）；onFullscreen 恒接线
  //（带缺省空实现，与 onSend 同款式）──
  private fullscreenMenuId: TextMenuItemId = TextMenuItemId.of('fullscreen_input');
  private inputTextMenu: EditMenuOptions = {
    onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> => {
      menuItems.push({ content: '全屏输入', id: this.fullscreenMenuId });
      return menuItems;
    },
    onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean => {
      if (!menuItem.id.equals(this.fullscreenMenuId)) {
        return false; // 非本件菜单项 → 交还系统默认处理
      }
      this.onFullscreen(this.text); // 带出当前草稿（同原全屏键语义）
      return true;
    }
  };

  // ── 安全输入 ──：chip 显隐 = 会话归属助手启用 AI 配置域任一件（CHAT_AI_ADMIN_OWNER_KEY
  // 广播键，ChatSessionOverrideCtrl 提示词态 load 解析后写；启用 manage_providers 等四件的
  // 会话才有明文填写需求）。暂存槽订阅（写点 = 面板「暂存」保存 setPendingKey，清点 =
  // assign_key 配出 / 显示条 × 键 / 本组件 aboutToDisappear）：槽非空且启用域会话才渲染
  // 暂存条；明文不入条——只显示 keyHintOf 尾号掩码
  @StorageProp(PENDING_KEY_SLOT_KEY) pendingKeyRaw: string = '';
  @StorageProp(CHAT_AI_ADMIN_OWNER_KEY) aiAdminOwnerFlag: boolean = false;
  // 面板显隐（bindSheet 宿主首参；触发键 chip 回调与本值同组件——规范 §1 判据③）
  @State @Watch('onSheetVisibleChanged') private secureSheetShow: boolean = false;
  // ── 关闭-再开协调（机制与官方依据单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）──：
  // 关闭后离场动效在途期内再点 chip / 暂存条，直接写下的可见性 true 会被吞或被框架收尾回写
  // 压回——在途期只记开意图，等离场动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;

  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用；机制见字段注释）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.secureSheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.secureSheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；
  // 用户关闭必经 requestClose（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.secureSheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 面板内配置成功收尾三路同调）：先清开意图 + 置离场动效
  // 在途位，再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.secureSheetShow = false;
  }

  // 安全输入面板（双态：直写 = 中转键目标卡核对直存；暂存 = 写会话单槽配出即清——面板件
  // 内部分源；三件套 = $$ 双向 + onWillDismiss 放行 + 内容不复位——面板件随 bindSheet 每次
  // 打开重建，无内容形态复位面）
  @Builder
  SecureSheetBuilder() {
    SecureInputSheet({
      onClose: (): void => {
        this.requestClose();
      }
    })
  }

  // 键盘发送键：与胶囊发送键同语义——trim + 可发判定 + 清空上行。★ busy 时交 send 守卫
  // 自动入队（入队也算投递 → 返回 true 清草稿）；带附件 busy 被守卫拒绝入队（toast + false）
  // 时草稿留条。空/纯空格/DB 未就绪静默不发（与胶囊禁点等价——键盘键无法置灰）。★ 清空移到
  // 返回值判定之后——被拦时草稿留在输入框，不与胶囊键分叉
  private onKeyboardSend(): void {
    const trimmed: string = this.text.trim();
    if (!this.dbReady || !this.canSend()) {
      return;
    }
    if (this.onSend(trimmed, this.attachments)) {
      this.text = '';
    }
  }

  // 停止图标色：官方 warning 色资源（深浅分治系统接管；SDK resources.txt 查证与原手写分支
  // 逐字同值纯换源，消除「自称官方实则手写」异源）
  private abortColor(): ResourceColor {
    return $r('sys.color.ohos_id_color_warning');
  }

  // 状态图标色（三态，全用官方语义色禁自绘）：
  // ①阻断＝错误红（未解析到模型，发送链会拦；面板「模型」行同拍显「未选择」）
  // ②携带＝强调蓝（指定技能/待发附件在场——「下一条消息不是裸文本」）
  // ③常态＝次要灰。优先级 ①>②>③。★ 刻意**不接**上下文占用阈值：面板收录表无数用行，
  // 红/黄进了面板找不到原因；用量告警继续由输入条圆环独家承担，后续自检勿「顺手统一」
  private statusIconColor(): ResourceColor {
    if (this.modelLabel === '') {
      return $r('sys.color.ohos_id_color_alert');
    }
    if (this.designatedSkillId !== '' || this.attachments.length > 0) {
      return $r('sys.color.ohos_id_color_emphasize');
    }
    return $r('sys.color.font_secondary');
  }

  // 发送可用：文本非空、附件存在、或已指定技能（只指定不打字也发得出去——竞品「空消息
  // 400」防法；协议侧 user 内容由标注句兜底，见 ChatSendCtrl.dispatchSend）
  private canSend(): boolean {
    return this.text.trim() !== '' || this.attachments.length > 0 ||
      this.designatedSkillId !== '';
  }

  // 停止键位换发送键判据（单源）：busy 且草稿非空且无附件——与「文本 only」排队口径一致
  //（带附件 busy 由入口层拒绝入队并 toast，故保留停止键，防「点了才知道不行」）。两处
  // SendOrStopKey 实例同读本判据
  private queueKeyVisible(): boolean {
    return this.busy && this.text.trim() !== '' && this.attachments.length === 0;
  }

  // 展开/收起（UIContext 形态，禁全局 animateTo）：工具行高度与收窄宽度变化同帧插值。
  // ★ 物理弹簧 curves.springMotion（官方建议优先物理曲线）：动画时长由曲线参数与变化量
  // 自动计算，AnimateParam 的 duration 不生效（官方 d.ts），故不传。手感两旋钮 = response
  //（完整振荡周期，官方默认 0.55）与 dampingFraction（阻尼系数，越小越弹，官方默认 0.825）
  //——本处 0.4 / 0.55（ζ=0.55 首峰过冲约 12.6%，44vp 行程约 5.6vp、沉降约 0.44s；调手感
  // 只动 dampingFraction 一个数）
  private setExpanded(next: boolean): void {
    // 展开即合闸（父组件暂停进页校正链的拽底，见 onExpandState 注释）；收起态的开闸在
    // 动画结束时进行——收起动画期间浮层高度仍在变，同属交互窗口
    if (next) {
      this.onExpandState(true);
    }
    this.getUIContext().animateTo({
      curve: curves.springMotion(0.4, 0.55),
      onFinish: (): void => {
        if (!this.expanded && !this.departed && !this.inputFocused) { this.onExpandState(false); }
      }
    }, () => {
      this.expanded = next;
    });
  }

  // 失焦延时收起（150ms）：点工具行按钮若夺焦，blur 先于 click 到达——键 Down 取消（守卫见
  // cancelCollapseOnTouch）；一次性 UX 防误收，非轮询（P1-3 例外登记）
  private startCollapseTimer(): void {
    // 常驻展开没有收起动画，失焦须在此放开阅读闸；形态与键盘避让保持独立。
    if (this.alwaysExpanded) {
      this.onExpandState(false);
      return;
    }
    // 交互期不收（见 chipMenuOpen / chipTouchActive / thinkingHold 字段注释——菜单弹窗取焦或
    // 按压期失焦，不拦会连带把卡片收掉、菜单随浮层下移）
    if (this.chipMenuOpen || this.chipTouchActive || this.thinkingHold) {
      return;
    }
    if (this.collapseTimer !== -1) {
      clearTimeout(this.collapseTimer);
    }
    this.collapseTimer = setTimeout(() => {
      this.collapseTimer = -1;
      // 触发时复检：标题栏思考键跨组件无句柄、无法像 chip 行那样在 Down 时取消本计时器，
      // 故触发时按同一守卫复检一次（守卫期跳过本次收起，下次失焦再起计时）。恒展开同检：
      // 计时器在途期间拨开开关（alwaysExpanded 翻 true），触发时不再收起
      if (this.alwaysExpanded || this.chipMenuOpen || this.chipTouchActive || this.thinkingHold) {
        return;
      }
      this.setExpanded(false);
    }, INPUT_COLLAPSE_DELAY);
  }

  private cancelCollapseTimer(): void {
    if (this.collapseTimer !== -1) {
      clearTimeout(this.collapseTimer);
      this.collapseTimer = -1;
    }
  }

  // 键按下守卫（＋ / 发送·停止两键共用）：取消待收起——真机若确认按钮不夺焦，本守卫无害保留
  // （不删；任务书 §2.4-1）
  private cancelCollapseOnTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.cancelCollapseTimer();
    }
  }

  // 图标键外边距（两态定位差异，键本体形制零改动）：收起态在文本行内 = 缘侧 4 + 底 7（底对齐
  // 贴底，多行自增高时贴底）；展开态在工具行内 = 垂直内缩顶 1 / 底 7（键中心与胶囊圆角弧心
  // 等高，见 TOOL_KEY_INSET；水平内缩由工具行 padding 下发，不用外边距）。
  // ★ 收起态缘侧仍为 4（同心值应为 7，差 3vp）——决明口径只动展开态，且 4 → 7 往内收与
  //「贴边」方向相反故不动；如需两态一致改此一处
  private keyMargin(isLeft: boolean): Margin {
    if (this.expanded) {
      return { top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET };
    }
    if (isLeft) {
      return { left: 4, bottom: 7 };
    }
    return { right: 4, bottom: 7 };
  }

  // 「全屏输入」键（2026-09-09 三改自独立文字快捷条迁工具行、发送键左侧）2026-10-31 退役
  // ——入口迁输入框文字选择菜单「全屏输入」纯文字项（决明拍板：仿复制半模态「引用」项
  // 形制，取消直接图标键）；面板机制（openInput / 四通道 / 全屏宿主件）不变，见 inputTextMenu

  // 「+」扩展键（附件入口；无圆底无材质，次级色 icon_primary 与发送键强调色区分——扩展入口
  // 非主操作）。@Builder 抽一次两态各实例化一处：收起态在文本行内、展开态在工具行内（定位
  // 差异走 keyMargin，按钮无状态重建无副作用）
  @Builder
  AddKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .width(INPUT_KEY_SIZE)
    .height(INPUT_KEY_SIZE)
    .backgroundColor(Color.Transparent)
    .margin(this.keyMargin(true))
    .onTouch((event: TouchEvent): void => {
      this.cancelCollapseOnTouch(event);
    })
    .onClick(() => {
      this.onAddFile();
    })
  }

  // 「上下文用量」圆环键：极简圆环不显数字；环本体 = ContextUsageRing 共用件（形制/色档/
  // 仅底环口径单源在该件）。★ 点按非破坏性：onClick 只上行开面板看明细，零业务副作用
  //（「点环直接触发压缩」会被当 bug 报的反例）。渲染退路已写方案档：真机若发虚/描边断裂
  // 改自绘 strokeDashArray，按真机结果定
  @Builder
  ContextRingKey() {
    Button() {
      ContextUsageRing({ pct: this.ctxRingPct })
    }
    .width(INPUT_KEY_SIZE)
    .height(INPUT_KEY_SIZE)
    .backgroundColor(Color.Transparent)
    // 垂直内缩同相邻键（顶 1 / 底 7，键中心与胶囊圆角弧心等高，见 TOOL_KEY_INSET）
    .margin({ top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET })
    .onTouch((event: TouchEvent): void => {
      this.cancelCollapseOnTouch(event);
    })
    .onClick(() => {
      this.onOpenContext(this.text);
    })
  }

  // 当前生效档（'' = 迁移态，仍按旧三域档逐域裁决）。两枚 @StorageProp 订阅位在此参与
  // 求值，保证切档与改默认档都写即刷新；真值恒由 effectivePermissionMode 单一真源现读，
  // 禁在别处另算一份档位。
  private permissionModeNow(): string {
    if (this.sessionModeTick === '' && this.defaultModeTick === '') {
      return '';
    }
    return effectivePermissionMode();
  }

  // 权限模式图标色（三态全走官方语义色，禁自绘）：谨慎 = 强调蓝、高效 = 官方警示色、
  // 标准与迁移态 = 次要灰。与 StatusKey.statusIconColor 同族，刻意不接上下文用量阈值。
  private permissionModeIconColor(): ResourceColor {
    const mode: string = this.permissionModeNow();
    if (mode === PERMISSION_MODE_FULL) {
      return $r('sys.color.ohos_id_color_warning');
    }
    if (mode === PERMISSION_MODE_CAUTIOUS) {
      return $r('sys.color.ohos_id_color_emphasize');
    }
    return $r('sys.color.font_secondary');
  }

  // 档位切换（唯一写点 = 本键菜单）。切到高效档显式警示，代价不静默。
  private onPickPermissionMode(mode: string): void {
    setSessionPermissionMode(mode);
    if (mode === PERMISSION_MODE_FULL) {
      this.getUIContext().getPromptAction().showToast({
        message: '高效档已开启。本次会话内不可逆操作也不再询问。只对当前会话生效，重启应用后仍保留。'
      });
    }
  }

  // 档位菜单体（形态照 ChatParamChipBar.ThinkingMenu：官方 Menu + 项尾勾 +
  // menuItemDivider 官方分割线；不走 @kit.UIDesignKit，与标题栏思考菜单同源）。
  // ★ 2026-11-11 决明「统一为勾在右」笔：原 selected + selectIcon（官方内置勾 = 文字左侧）改
  // menuEndCheck(选中条件) 项尾勾，与思考档位菜单同形态；判据单源见 common/Theme.ets 同名函数
  @Builder
  private PermissionMenuBuilder() {
    Menu() {
      MenuItem({ content: permissionModeLabel(PERMISSION_MODE_CAUTIOUS),
        symbolEndIcon: menuEndCheck(this.permissionModeNow() === PERMISSION_MODE_CAUTIOUS) })
        .onClick(() => {
          this.onPickPermissionMode(PERMISSION_MODE_CAUTIOUS);
        })
      MenuItem({ content: permissionModeLabel(PERMISSION_MODE_STANDARD),
        symbolEndIcon: menuEndCheck(this.permissionModeNow() === PERMISSION_MODE_STANDARD) })
        .onClick(() => {
          this.onPickPermissionMode(PERMISSION_MODE_STANDARD);
        })
      MenuItem({ content: permissionModeLabel(PERMISSION_MODE_FULL),
        symbolEndIcon: menuEndCheck(this.permissionModeNow() === PERMISSION_MODE_FULL) })
        .onClick(() => {
          this.onPickPermissionMode(PERMISSION_MODE_FULL);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  // 「权限模式」裸图标键（工具行左侧第三键）：形制照相邻图标键（36×36 透明底 +
  // SymbolGlyph 20fp 无底无材质），图标色三态承载档位语义。菜单向上展开（屏底键位，
  // Placement.TopLeft 照输入栏 chip 时代先例），菜单期复用 chipMenuOpen 收起守卫。
  @Builder
  PermissionModeKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.lock_shield'))
        .fontSize(20)
        .fontColor([this.permissionModeIconColor()])
    }
    .width(INPUT_KEY_SIZE)
    .height(INPUT_KEY_SIZE)
    .backgroundColor(Color.Transparent)
    .margin({ top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET })
    .onTouch((event: TouchEvent): void => {
      this.cancelCollapseOnTouch(event);
    })
    .bindMenu(this.PermissionMenuBuilder, {
      placement: Placement.TopLeft,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
        this.immersiveLevel, true),
      onAppear: (): void => {
        this.chipMenuOpen = true;
        this.cancelCollapseTimer();
      },
      onDisappear: (): void => {
        this.chipMenuOpen = false;
      }
    })
  }

  // 「会话状态」裸图标键（2026-10-13 决明改形自 chip 行「状态」胶囊迁工具行、上下文圈右侧）：
  // 形制照相邻图标键（36×36 透明底 + SymbolGlyph 20fp 无底无材质，同 AddKey）
  // ——禁自创几何。图标色三态承载状态语义（判据与色义见 statusIconColor 注释），只读入口：
  // 点击上行开会话状态半模态，零业务副作用
  @Builder
  StatusKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(20)
        .fontColor([this.statusIconColor()])
    }
    .width(INPUT_KEY_SIZE)
    .height(INPUT_KEY_SIZE)
    .backgroundColor(Color.Transparent)
    // 垂直内缩同相邻键（顶 1 / 底 7，键中心与胶囊圆角弧心等高，见 TOOL_KEY_INSET）
    .margin({ top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET })
    .onTouch((event: TouchEvent): void => {
      this.cancelCollapseOnTouch(event);
    })
    .onClick(() => {
      this.onOpenStatus();
    })
  }

  // 发送键（停止键位三态替换单源）：空闲态 = 发送；busy 且草稿非空且无附件 = 同键位渲染本键
  //（点击入队，入队也算投递）——**替换不新增键位**，零增高底带（1597 底带红线不碰）。空文本
  // 且无附件置灰禁点（P0-1 不发空消息）；DB 未就绪同样禁点，入队判定单源在
  // ChatSendCtrl.sendEntry。样式 = 强调色图标无底无材质
  @Builder
  SendKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.paperplane_fill'))
        .fontSize(20)
        .fontColor([$r('sys.color.comp_background_emphasize')])
    }
    .width(INPUT_KEY_SIZE)
    .height(INPUT_KEY_SIZE)
    .backgroundColor(Color.Transparent)
    .margin(this.keyMargin(false))
    .enabled(this.dbReady && this.canSend())
    .opacity(this.dbReady && this.canSend() ? 1.0 : 0.4)
    .onTouch((event: TouchEvent): void => {
      this.cancelCollapseOnTouch(event);
    })
    .onClick(() => {
      const trimmed: string = this.text.trim();
      if (!this.canSend()) {
        return;
      }
      // 清空按返回值收尾（2026-09-15 发送链收口笔）：被拦时文字留在输入框、附件照旧在条上
      //（busy 期本键 = 入队：返回 true 清草稿，满 20 / 带附件拒绝时保留）
      if (this.onSend(trimmed, this.attachments)) {
        this.text = '';
      }
    })
  }

  // 发送/停止键（两态各一处）：busy 且草稿非空且无附件 → 同键位渲染发送键（替换而非伴生）；
  // busy 其余情况（草稿空或带附件）= 停止键；空闲 = 发送键（SendKey）。停止键样式 = 36×36
  // 无底图标键，警示红 stop_circle 深浅分治——禁圆底材质铁律
  @Builder
  SendOrStopKey() {
    if (this.busy && !this.queueKeyVisible()) {
      Button() {
        SymbolGlyph($r('sys.symbol.stop_circle'))
          .fontSize(22)
          .fontColor([this.abortColor()])
      }
      .width(INPUT_KEY_SIZE)
      .height(INPUT_KEY_SIZE)
      .backgroundColor(Color.Transparent)
      .margin(this.keyMargin(false))
      .onTouch((event: TouchEvent): void => {
        this.cancelCollapseOnTouch(event);
      })
      .onClick(() => {
        this.onAbort();
      })
    } else {
      this.SendKey()
    }
  }

  build() {
    Column({ space: BAND_ROW_SPACING }) {
      // ── 参数 chip 行（思考；收起态隐藏。联网/状态入口均已迁出本行）──
      Row({ space: 8 }) {
        // ★ 收起态隐藏（决明「收起时胶囊不显示，切换为展开态时胶囊才出现」——收起态胶囊已
        // 收窄，参数 chip 常显会相对胶囊左右外凸）：外层 Row 恒挂 + 透明度两态切换（透明度属
        // 官方可动画属性）；不用条件渲染——出现/消失不参与布局动画，且行高变化会牵动浮层
        // 高度与列表底衬。**不塌位**：组件恒挂、行高不变（chip 本体高 36 撑住）→ 浮层总高
        // 恒定、列表底衬零联动（与合规提示行「藏字不塌位」同法）；收起态不可命中 = 隐形 chip
        // 不许吃点击。★ hitTestBehavior 用 Block 不用 None（真机报障「收起时还是能点」修正）：
        // 本地 d.ts 实锤 None = 自身不响应但**不阻塞子节点**，chip 照旧收点击；Block = 阻塞子
        // 节点。本层盒只覆盖 chip 自身区域；对下层消息流的阻断与否由浮层容器决定（ChatPageContent）
        Row() {
          // 思考强度 chip（样式/菜单细则见 ChatParamChipBar 头注释；HDS 路径渲染空行、
          // 回退路径仅余思考 chip）
          ChatParamChipRow({
            thinkingValue: $thinkingValue,
            onPickThinking: (option: string): void => { this.onPickThinking(option); },
            // 菜单开合上行（收起守卫，见 chipMenuOpen 字段注释）：开菜单即取消待收起
            onMenuStateChange: (open: boolean): void => {
              this.chipMenuOpen = open;
              if (open) {
                this.cancelCollapseTimer();
              }
            },
            // 安全输入 chip（显隐 = AI 配置域归属广播键经 @Prop 下发）：点击拉起安全输入半模态
            secureInputVisible: this.aiAdminOwnerFlag,
            onSecureInputTap: (): void => {
              this.requestOpen();
            }
            // 状态入口已迁工具行 StatusKey（本处零透传）
          })
        }
        .opacity(this.expanded ? 1 : 0)
        .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.Block)
        // Down 置位并取消待收起、Up/Cancel 复位（见 chipTouchActive 注释）：与工具行三键的
        // cancelCollapseOnTouch 同族但更严——按压期整段封住，覆盖「blur 在 Down 之后」的时序
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) {
            this.chipTouchActive = true;
            this.cancelCollapseTimer();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.chipTouchActive = false;
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 收起态收窄容器（决明「收起时输入框长度比现在短，展开时高度与宽度双变化」）：胶囊自身
      // 恒 100% 宽，收窄由本层左右内缩下发——padding 属官方可动画布局属性，与工具行高度在
      // **同一次** animateTo 内插值（见 setExpanded）→ 宽高双变同源同曲线、弹簧同步；不用
      // 百分比宽度——百分比尺寸动画依赖父容器确定尺寸。chip 行与合规提示行在本容器之外：
      // 收窄只作用于胶囊，悬浮键与参数 chip 位置不动
      Column() {
        // 胶囊容器（暂存密钥条/引用条/附件条 + 文本行 + 工具行；材质/半圆圆角/clip 挂本层
        // Column——「同一子树最外层只设一次材质」；容器不设高度——附件条增删 + 文本行高度
        //（收起态恒单排 50 / 展开态自增高）+ 工具行进出全由内容自适应）
        Column() {
          // 暂存密钥条（「会话内临时携带物」灰底圆角条，同编辑提示条族）：启用 AI 配置域会话
          // 且槽非空才渲染（显隐判据见 pendingKeyRaw 字段注释）。条体点击重开面板（重粘覆盖），
          // × 键清槽（明文未配出即弃，无二次确认——本就未落任何盘面）。明文不入条：只显示
          // keyHintOf 尾号掩码（KeyStore 单源）；× 键 = 行内图标键官方形制（无底 TEXTUAL +
          // font_secondary）
          if (this.aiAdminOwnerFlag && this.pendingKeyRaw.trim() !== '') {
            // 内缩外包层（坑 23 修复同款形态）：灰底条不能用自己的 padding 收自身底色——
            // padding 收内容区不收背景盒，左右 12 / 顶 12 须外包 Column 经其 padding 下发
            //（外包层随 if 显隐，无空态死高度问题，top 可入 padding——与条族根恒挂不同）
            Column() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.key'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_secondary')])
                Text('已暂存密钥 ' + keyHintOf(this.pendingKeyRaw))
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Button() {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(16)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  clearPendingKey();
                })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(DESIGNATE_STRIP_RADIUS)
              .backgroundColor(fallbackGrayBg(this.appColorMode, this.cardAlphaLevel))
              .onClick((): void => {
                this.requestOpen();
              })
            }
            .width('100%')
            .padding({ left: DESIGNATE_STRIP_HPAD, right: DESIGNATE_STRIP_HPAD,
              top: DESIGNATE_STRIP_TOP })
          }
          // 待发引用条（暂存密钥条之后、附件条之前——引用与附件同属「待发载荷」，条序与拼装
          // 次序一致）：ChatQuoteBar 恒挂（半模态宿主判据——bindSheet 挂它自身根，条体在组件
          // 内部判空零占位），条高变化经胶囊实测逐帧跟随
          ChatQuoteBar({
            quoteText: this.quoteText,
            // 底部安全区透传：完整引用半模态的底部「删除引用」操作行自行避让——面板
            // ignoreLayoutSafeArea(BOTTOM)，不传则压手势条
            bottomInset: this.bottomPad,
            onDismissQuote: (): void => {
              this.onDismissQuote();
            }
          })
          // 技能条（2026-11-02 复建；旧「技能 · X」灰底条 2026-10-13 退役史见变更记录）：
          // 恒挂，判空在件内；负向钉仍有效——本文件零「技能 · 」「wand_and_stars」
          //「onClearDesignate」字面
          ChatSkillBar({
            skillId: this.designatedSkillId,
            skillName: this.designatedSkillName,
            onRemoveSkillDesignate: (): void => {
              this.onRemoveSkillDesignate();
            }
          })
          // 附件条：待发附件横滑条（图片真缩略图/文件图标卡 + 删除徽标；点卡片上行预览）
          if (this.attachments.length > 0) {
            AttachmentStrip({
              attachments: this.attachments,
              onRemove: (index: number): void => {
                this.onRemoveAttachment(index);
              },
              onPreview: (fileId: string): void => {
                this.onPreviewAttachment(fileId);
              }
            })
          }

          // 文本行（两态共用同一个 TextArea——单实例硬约束：放进 if 分支会随重建丢焦点/
          // 光标/已输入文本）：收起态 = ＋ | TextArea | 发送·停止（＋ 与发送键 36×36 对称、
          // 底对齐贴底）；展开态两键移入工具行，本行只剩 TextArea 占满整行
          Row() {
            if (!this.expanded) {
              this.AddKey();
            }

            TextArea({ placeholder: this.dbReady ? '输入消息…' : '数据库未就绪，暂不可发送', text: $$this.text })
              // 节点 id：推荐语回填聚焦的 requestFocus 目标 key
              .id(INPUT_TEXTAREA_ID)
              .layoutWeight(1)
              // 不设 height = 官方自适应内容高度（text_area.d.ts）；constraintSize 钳制行数
              //——收起态上下限同钉单排 50（多行内容裁到一排，高度与内容无关）/ 展开态 2~4 排
              // 完整显示、5 排起钳顶（见 EXPANDED_TEXT_BOTTOM_VPAD），再多框内滚动（TextArea
              // 天生可滚动）；显式 lineHeight 使换算确定
              .constraintSize({ minHeight: INPUT_MIN_HEIGHT,
                maxHeight: this.expanded ? INPUT_MAX_HEIGHT : INPUT_MIN_HEIGHT })
              // 收起态不滚动（决明复验「只显示一排但还能滚动，很别扭」）：maxLines 收 1 行 +
              // 官方 MaxLinesMode.CLIP——非内联模式文本按 maxLines 指定行数截断、不产生滚动区
              //（SCROLL 模式才滚动，d.ts 实锤）；展开态回填官方非内联默认值 UINT32_MAX =
              // 不截断，框内滚动行为不变
              .maxLines(this.expanded ? INPUT_EXPANDED_MAX_LINES : 1,
                { overflowMode: MaxLinesMode.CLIP })
              .fontSize(15)
              .lineHeight(INPUT_LINE_HEIGHT)
              // 透明底无边框：胶囊视觉由外层 Column 的材质承担（材质铁律，勿在此恢复背景/边框）
              .backgroundColor(Color.Transparent)
              // 内边距两态分治：顶部两态都保持 INPUT_VPAD，只底部展开态归 0；左右 16 对称
              .padding({ left: 16, right: 16,
                top: INPUT_VPAD,
                bottom: this.expanded ? EXPANDED_TEXT_BOTTOM_VPAD : INPUT_VPAD })
              // 键盘回车键形态（「键盘发送」偏好）：true = Send（右下角发送键，onSubmit 直接
              // 发送——与胶囊发送键同语义）；false = NEW_LINE 换行键（官方默认值）。★ 长按换行
              // = 系统键盘行为，官方 API 只负责键形态（text_area.d.ts：NEW_LINE 时 onSubmit
              // 不触发、Send 触发）
              .enterKeyType(this.keyboardSend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
              .onSubmit((enterKey: EnterKeyType): void => {
                if (enterKey === EnterKeyType.Send) {
                  this.onKeyboardSend();
                }
              })
              // 聚焦 = 展开两排卡 + 键盘避让切「压缩」模式；失焦 = 卡片延时收起（150ms，
              // startCollapseTimer——工具行按钮 Down 取消，防点键误收）+ 键盘避让恢复全局默认
              .onFocus(() => {
                this.inputFocused = true;
                this.cancelCollapseTimer();
                // 自愈：菜单/按压上报若因异常时序残留，回焦即清（避免之后再也不收起）；
                // thinkingHold 同（@Link 回写 ChatPage，菜单若仍开着其 onDisappear 会再复位）
                this.chipMenuOpen = false;
                this.chipTouchActive = false;
                this.thinkingHold = false;
                // ★ 真机报障修复（多行内容 + 点靠上排 → 输入框底部与键盘重叠）：全局默认
                // RESIZE_WITH_CARET 是「随光标避让」——只保证**光标**可见，卡片底部仍可落在
                // 键盘下；本页输入栏贴底，聚焦期改官方处方 KeyboardAvoidMode.RESIZE（压缩模式，
                // 解决底部操作栏被遮挡，《软键盘布局适配》），失焦即恢复（成对）——表单页的
                // 光标跟随与半模态面板（走 SheetKeyboardAvoidMode，与页面模式解耦）不受影响
                this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
                this.setExpanded(true);
              })
              .onBlur(() => {
                this.inputFocused = false;
                this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
                this.startCollapseTimer();
              })
              // 粘贴拦截：粘贴文本达到阈值时不插进输入框，改为转 .txt 附件挂上附件条。判定
              // 单源 = AttachmentPickCtrl.shouldPasteAsFile（三条件都在它里面，本处不重写避免
              // 漂移）。★ 顺序硬要求：before 快照先取、preventDefault 在回调返回前调用，收口
              // 闭包捕获本次 value 与 before（不能事后靠 this.text 反推）。★ 收口不变式 =
              // 附件与原文**恰有其一**（settlePastedText 单源判定）——preventDefault 拦不拦得住
              // 属平台行为，拦不住时由收口把重复纠正回来
              .onPaste((value: string, event: PasteEvent): void => {
                const threshold: number = clampPasteThreshold(this.pasteThreshold);
                const intercept: boolean = shouldPasteAsFile(value, this.pasteAsFile, threshold);
                // 判定留痕（用户不可见）：真机报「粘贴长文本没生效」时这四个事实就是判别面
                //——onPaste 有没有触发、开关与阈值、判定结果
                hilog.info(0xD5A0, 'ChatInput',
                  '粘贴判定 长度=%{public}d 阈值=%{public}d 开关=%{public}s 拦截=%{public}s',
                  value.length, threshold, String(this.pasteAsFile), String(intercept));
                if (!intercept) {
                  return; // 不拦：走 TextArea 原生粘贴
                }
                const before: string = this.text;
                this.lastPasteHandled = value; // 交棒给 onWillInsert 去重（同一段文本不再转第二次）
                if (event !== undefined && event.preventDefault !== undefined) {
                  event.preventDefault(); // best-effort：拦下本次插入（拦不住由收口兜底）
                }
                this.onPasteLongText(value, (converted: boolean): void => {
                  this.lastPasteHandled = ''; // 本次受理已收口 → 哨兵复位（见字段注释）
                  const settled: string = settlePastedText(this.text, before, value, converted);
                  if (settled !== this.text) {
                    this.text = settled;
                  }
                });
              })
              // 输入法通路拦截（真机情报：系统键盘剪贴板上屏的长文本不触发 onPaste——那条路
              // 走输入法输入通路）：官方 onWillInsert 正是该通路 will 钩子（将要输入时触发，
              // 返回 false 即拦下；系统自带输入法在其支持范围内）。判据与 onPaste 同源
              //（shouldInterceptInsert / shouldPasteAsFile）：单次插入达到阈值即转附件——打字
              // 恒不过线，剪贴板与语音输入等批量上屏会过线。
              // ★ 去重：**本次受理窗口内**（onPaste 起到收口回调止）同一段文本放行——防两条
              // 通路各转一次，窗口在收口处复位（见字段注释——只活一次受理）
              // ★ 拦下即「文本没落框」→ 收口闭包按 landed=false 走：转成则不留、未成则追加回框
              .onWillInsert((info: InsertValue): boolean => {
                const inserted: string = info.insertValue;
                const threshold: number = clampPasteThreshold(this.pasteThreshold);
                const intercept: boolean = shouldInterceptInsert(inserted, this.lastPasteHandled,
                  this.pasteAsFile, threshold);
                // 判定留痕（用户不可见，同 onPaste 一处）：输入法通路有没有走到、四个事实
                hilog.info(0xD5A0, 'ChatInput',
                  '输入法上屏判定 长度=%{public}d 阈值=%{public}d 开关=%{public}s 拦截=%{public}s',
                  inserted.length, threshold, String(this.pasteAsFile), String(intercept));
                if (!intercept) {
                  return true; // 不拦：正常插入
                }
                const before: string = this.text;
                this.onPasteLongText(inserted, (converted: boolean): void => {
                  const settled: string = settlePastedText(this.text, before, inserted, converted);
                  if (settled !== this.text) {
                    this.text = settled;
                  }
                });
                return false; // 拦下本次插入（文本改走附件）
              })
              // 文字选择菜单扩展（长按/选中弹出，系统项全保留）：追加「全屏输入」纯文字项
              //（真机落系统二级区，一级无途径——机制与查证结论见 inputTextMenu 注释；
              // 2026-10-31 全屏入口自工具行图标键迁入此处）
              .editMenuOptions(this.inputTextMenu)

            // 发送·停止键（收起态在文本行内，展开态移入工具行；busy 草稿态同键位渲染发送键）
            if (!this.expanded) {
              this.SendOrStopKey();
            }
          }
          .width('100%')
          // 图标键底对齐：多行加高后贴胶囊底部（单行时按钮靠下边距居中，观感不变）
          .alignItems(VerticalAlign.Bottom)

          // 工具行（★ 恒存在 + 高度 0/44 切换，不用 if 条件渲染——条件渲染的出现/消失
          // **不参与布局动画**，高度瞬跳会甩动同浮层的相邻元素；内缩同心见 TOOL_KEY_INSET：
          // 水平走本行 padding、垂直走键与文字外边距）。
          // 内容：＋ 键 | 状态裸图标键 | 权限模式裸图标键 | Blank 弹性空白（原「当前模型名」
          // 只读文字退役，模型名归会话状态半模态，几何等价）| 上下文用量圆环键 | 发送·停止键。
          // 全屏输入与引用入口已迁输入框文字选择菜单（inputTextMenu 两纯文字项），本行无全屏键。
          // 第三键为 2026-11-09 会话权限模式笔新增，左侧键组三枚，几何常量零改动。
          // ★ 出场效果实际不可见：胶囊容器 clip(true) 且不设高度（内容自适应），删行后容器
          // 高度回缩、裁剪区同步缩小，被裁掉的删除动画看不见（官方 FAQ faqs-arkui-477 实锤）
          //——故转场保持对称形态，「只淡出」在此布局无可见差异，勿再试；要真做须另立设计
          //（转场期间撤 clip / 行高动画），本期不做
          Row() {
            this.AddKey()
            // 状态裸图标键（形制与三态换色见 StatusKey / statusIconColor）
            this.StatusKey()
            // 权限模式键（会话级三档选择器，形制见 PermissionModeKey）
            this.PermissionModeKey()
            // Blank 撑开键组：＋/状态 居左、环/发送 居右，与原 layoutWeight(1) 文字位
            // 几何等价（modelLabel @Link 链保留，消费方 = statusIconColor「未选模型」红档判据）
            Blank()
            // 上下文用量圆环键（2026-10-31 自左侧键组迁入原全屏键位——发送键左侧）
            this.ContextRingKey()
            // 发送·停止键（busy 草稿态同键位渲染发送键——判据与形制单源见 SendOrStopKey）
            this.SendOrStopKey()
          }
          .width('100%')
          .height(this.expanded ? TOOL_ROW_HEIGHT : 0)
          // 高度收缩时裁剪内容（否则 0 高容器内的键仍可见）；透明度随高度同步淡入淡出
          .clip(true)
          .opacity(this.expanded ? 1 : 0)
          // 水平内缩 = 与胶囊圆角同心（见 TOOL_KEY_INSET）：左右 7 使键中心距侧边 25 与弧心
          // 同列；垂直内缩（顶 1 / 底 7）由键与文字的外边距下发——行高收起态归 0 时，行自身的
          // 垂直 padding 会把最小高度撑到 8vp（真机实测收起态胶囊被撑高、两键失中）
          .padding({ left: TOOL_KEY_INSET, right: TOOL_KEY_INSET })
        }
        .width('100%')
        // 半圆圆角 = 单行高一半（自绘外形，非官方固定值，可调）；加高后半径不变自然过渡
        .borderRadius(INPUT_CAPSULE_RADIUS)
        .clip(true)
        // 胶囊双态（2026-09-03 开关体系）：实底态 = Theme.fallbackGrayBg 随卡底透明度档叠
        // alpha（2026-10-25 起，原 comp_fallback_gray 资源退役迁 Theme 函数；零实时渲染
        // 零卡顿——backgroundEffect 真机卡顿已撤销，实验记录见头注释与 ChatPageContent）；
        // 光感态 = REGULAR 系统材质（随沉浸光感总档）。内层 TextArea 保持透明底（胶囊视觉
        // 由本层承担）
        .backgroundColor(this.contentFallback ? fallbackGrayBg(this.appColorMode, this.cardAlphaLevel) : Color.Transparent)
        .systemMaterial(this.contentFallback ? uiMaterial.Material.empty :
          resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, false))
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          if (!this.departed) { this.onReadingTop(newArea.globalPosition.y as number); }
        })
      }
      .width('100%')
      .padding({ left: this.expanded ? 0 : INPUT_COLLAPSED_INSET,
        right: this.expanded ? 0 : INPUT_COLLAPSED_INSET })

      // ── 合规提示行（文字源 = common/AiDisclosure——AI 标识「界面提示/复制/导出」三处
      // 同源）：输入胶囊下方一行居中小字；平时常显 = 输入胶囊整体适当抬高；★ 键盘弹起
      //（keyboardOn）藏字不塌位——文字换等高空占位镜像（同 COMPLIANCE_HINT_HEIGHT），浮层
      // 总高恒定：输入框零位移（无闪动、不因塌陷被键盘盖住），键盘收起恢复文字 ──
      if (!this.keyboardOn) {
        Text(AI_CONTENT_LABEL)
          .fontSize(11)
          .fontColor(cardDescColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .height(COMPLIANCE_HINT_HEIGHT)
      } else {
        Column()
          .width('100%')
          .height(COMPLIANCE_HINT_HEIGHT)
      }
    }
    .width('100%')
    // ★ 键盘态底部留白（键盘态红线口径）：常态 = 页面注入的 bottomPad 全量避让（「输入栏
    // 不压手势条」+ 悬浮页签让位）；键盘升起时置 0——键盘已覆盖底部系统区（手势条/页签均
    // 不可见），注入值此时纯属冗余，正是「抬起过高」的间距来源。切换随键盘事件在 animateTo
    // 内完成（见 onKeyboardHeight）；胶囊上沿实测用于宿主阅读边界，用户输入期间宿主冻结
    // 阅读基准
    .padding({ left: 16, right: 16, bottom: this.keyboardOn ? 0 : this.bottomPad })
    // 安全输入半模态：挂本组件根（规范 §1 三判据——①根 Column 常驻；②组件随会话页常驻不
    // 因数据销毁；③isShow 与触发键 chip 回调同组件）；零暂存形态 → onWillDismiss 直放行 +
    // 缺省直落不回弹（sheetPanelOptions 缺省档 MEDIUM/LARGE）。★ 关闭链（全站统一形态）：
    // $$ 框架回写落在关闭动画之后，动画窗口内 secureSheetShow 仍为 true，此刻再点 chip =
    // true→true 无状态转换、bindSheet 不响应——经 requestClose 单入口（清开意图 + 置在途位 +
    // 写 false）+ 第四参 onDisappear 动效结束按开意图补开（关闭-再开协调，见字段注释）
    .bindSheet($$this.secureSheetShow, this.SecureSheetBuilder(),
      sheetPanelOptions((action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      }, undefined, undefined,
      (): void => {
        this.onSheetGone();
      }))
  }
}

// ── 底部托管位几何同源别名（2026-11-08 输入位接管笔）──
// 细条与输入胶囊「同宽同高同形」、合规行同高，取值一律走本件原常量的引用而非抄值。
// ★ 不直接给原常量加 export：assert-ui-shape 的几何常量解析用行首 `^const` 正则取数，
// 加 export 会让 ㊱ 及收窄层两枚钉恒红；别名导出既保住单源又零改判。
export const DOCK_STRIP_INSET: number = INPUT_COLLAPSED_INSET;
export const DOCK_STRIP_HEIGHT: number = INPUT_MIN_HEIGHT;
export const DOCK_STRIP_RADIUS: number = INPUT_CAPSULE_RADIUS;
export const DOCK_COMPLIANCE_HEIGHT: number = COMPLIANCE_HINT_HEIGHT;
