// 聊天输入栏（2026-08-29 对话页 UI 对齐任务 2 自 dshinhm ChatInputBar **去 kap 改造**）：
// 结构 = 运行参数 chip 行（ChatParamChipBar，思考 chip——联网 chip 2026-09-19 迁标题栏
// 「更多」菜单〔决明指令〕；思考 2026-09-09 二百二十九迁标题栏「思考」热区后仅 HDS 路径
// 不渲染 chip，回退路径无 stackBuilder 画不了标题栏胶囊故保留；联网两路径都已不在本行，
// HDS 路径本行渲染空行）→ 胶囊输入框（占位
//「输入消息…」，发送/停止图标键并入胶囊内右侧；附件条并入胶囊内输入行上方，attachments
// 非空才渲染——附件链 2026-09-03 起已接线，08-29「入位不接线数组恒空」口径作废；★ 2026-09-16
// 单条消息指定技能：待发条（「技能 · X」灰底圆角条 + × 键）并入胶囊内、附件条之上，
// designatedSkillId 与 designatedSkillName 双非空才渲染——与附件条同族「本条消息携带物」，
// 故不进 chip 行）。参考主流
// AI 助手移动端形态（胶囊输入框 + 悬浮运行参数
// chip 行）。★ 2026-09-09 回顶/回底悬浮键全面退役（决明指令，全链路零残留）——键曾与 chip
// 同排（左回顶右回底），实现快照与恢复要点留档 docs/归档/退役实现-回顶回底键-20260909.md。
// ★ 2026-09-03 底部加合规提示行（「内容由 AI 生成，仅供参考」——胶囊下方一行
// 小字，常显抬高输入胶囊；键盘弹起时藏字不塌位（等高空占位镜像）——输入框零位移不闪动，
// 详见 keyboardOn 字段注释）。★ 2026-09-09 三改：「全屏输入」由 chip 行上方独立一排的
// 文字快捷条改为展开态工具行内的图标键（决明指令，见 FullscreenKey 注释）。
// 去 kap 项（aicontrol 无对应语义）：目标输入态 goalDrafting、权限模式 chip 与菜单、
// steer 插队三态（aicontrol M1 口径 = 运行中右单停止键不插话，回归红线）；★ 2026-08-31
// 任务 E：状态胶囊取消（chip 行只剩思考档，透传三参随之退役）。新增 dbReady 透传（M1
// 既有行为：DB 未就绪占位符切换 + 发送键禁点——P0-1 不静默）。
// 多行自增高（dshinhm 三改定稿）：TextArea 不设高度自适应内容（官方 d.ts），constraintSize
// 钳制行数（单行 50vp 起，超出框内滚动；★ 2026-09-09 决明口径「原来定的是最多显示 6 排，
// 现在改 4 排」；★ 同日「裁切边界调小、贴工具栏」后展开态底部 padding 归 0（顶部按复验
// 意见改回 INPUT_VPAD），同样 113vp 上限内容区变大 → 展开态 2~4 排完整显示、5 排起钳顶
//（可视 4.69 排），见 EXPANDED_TEXT_BOTTOM_VPAD）；★ 同日再定「收起后只显示一排，不论
// 有无内容收起后高度均一致」——收起态 constraintSize 上下限同钉 INPUT_MIN_HEIGHT + maxLines
// 收 1 行（CLIP 截断、不滚动）；显式 lineHeight(21)（15fp×1.4）使换算确定；
// 半圆圆角 = 单行高一半（加高后半径不变，体育场形→圆角矩形过渡）；图标键底对齐贴底。
// 沉浸光感（2026-09-03 内容区回退改造，三轮定稿）：输入胶囊外层 Column 原挂官方
// systemMaterial（THIN 基准档随沉浸光感总档）——按新规范普通内容区非弹窗组件材质
// 不生效（Material inactive: out of scope），三轮实测：①backgroundBlurStyle
// （COMPONENT_THIN）显纯白实底（官方封装蒙版色不可调 + 底部渐变蒙层抢先渐隐双因）；
// ②backgroundEffect（radius16+半透蒙版+AVERAGE 均色反色，半透可显）但 pop 转场与
// 消息滚动真机卡顿（官方 NOTE 逐帧实时渲染实锤）→ ③定稿：改官方实底
// comp_background_tertiary（官方语义色自动深浅反色，零实时渲染零性能开销）——与
// SystemPromptPage 按钮条（同日官方实底方案）同族观感；底部 90vp 渐变蒙层恢复
//（ChatPageContent ①b，消息滑入输入区渐隐职责回归蒙层接管——该层注释有完整实验记录
// 与「半透渐变」备选说明）。材质铁律作废前提（不再设材质，改设背景色合法）：背景色
// 可设；圆角仍靠 borderRadius + clip。发送键 = 强调色图标（无底无材质）；停止键 =
// 官方 warning 色深浅分治。
// ★ 2026-09-09 聚焦展开（任务书 docs/任务书-输入框优化-20260909.md，验收闭环后归卷
// docs/归档/任务书-归档-03-会话与统计功能.md「输入框优化」篇）：
// 点输入框 → 单排胶囊展开为两排卡（第一排文本、第二排工具行「＋ / 当前模型名 / 发送·停止」；
// 无旋钮、模型名只显示不可点），失焦延时复位胶囊。硬约束 = TextArea 单实例（两态共用同一个
// TextArea，禁放进 if 分支——重建丢焦点/光标/已输入文本）；＋ 与发送·停止键 @Builder 抽一次、
// 两态各实例化一处（按钮无状态，重建无副作用）。
// ★ 2026-09-09 工具行内缩改与圆角同心（决明「展开后加号与发送能否再贴边一些，大概就是他们
// 点击有圆形蒙层，圆和输入框圆角同心」）：左右 16 → 7、底 4 → 7、顶 4 → 1，键中心落在胶囊
// 圆角弧心（推导见 TOOL_KEY_INSET）；键尺寸抽常量 INPUT_KEY_SIZE。
// ★ 2026-09-09 收起态收窄（决明「收起时输入框长度比现在短，展开时高度与宽度双变化」）：收起态
// 胶囊左右各内缩 INPUT_COLLAPSED_INSET（同日复验「再短一点点」：28 → 36），展开态归 0；宽度与
// 工具行高度同一次 animateTo 弹簧插值（机制与几何见 build 内收窄容器注释）。★ 同日复验之二：
// 收起态参数 chip 行随之隐藏（恒挂 + 透明度两态，不塌位），见 build 内 chip 行注释。
// ★ 同日复验之三：展开态点 chip 开菜单不再误收起（决明「展开态点两胶囊
// 输入框都会变回收起，菜单也跟着下移」）——菜单开着期间不收，见 chipMenuOpen 字段注释。
// 底部渐变蒙层不在本组件——挂在消息列表上（ChatPageContent ①b 层 90vp 渐变蒙层）。
import { PendingAttachment } from '../../common/providers/AiTypes';
import { AttachmentStrip } from './ChatAttachmentStrip';
import { ContextUsageRing } from './ContextUsageRing';
import { ChatParamChipRow } from './ChatParamChipBar';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { curves, KeyboardAvoidMode, uiMaterial, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cardDescColor } from '../../common/Theme';
import {
  PASTE_THRESHOLD_DEFAULT, PREF_KEYBOARD_SEND_KEY, PREF_PASTE_AS_FILE_KEY,
  PREF_PASTE_AS_FILE_THRESHOLD_KEY, clampPasteThreshold
} from '../../common/AppPreferences';
import { settlePastedText, shouldInterceptInsert, shouldPasteAsFile } from './AttachmentPickCtrl';
import { AI_CONTENT_LABEL } from '../../common/AiDisclosure';

// 输入框几何常量（dshinhm 三改定稿值随迁）：单行高 50 = 行高 21 + 上下 padding 14.5×2；
// 上限 113 = 21×4 行 + 29（★ 2026-09-09 决明「裁切边界调小、贴工具栏」后展开态底部
// padding 归 0，同样 113vp 内容区变大 → 展开态约 4.7 排；收起态 padding 14.5 不变 = 最多
// 4 行；超出即框内滚动）；半圆角 = 单行高一半
const INPUT_LINE_HEIGHT: number = 21;
const INPUT_VPAD: number = 14.5;
// 50：最小高度 = 收起态固定高度（2026-09-09 决明「收起后只显示一排，不论有无内容收起后
// 高度均一致」——收起态 constraintSize 上下限同钉本值，多行内容裁到一排，见 TextArea 处注释）
const INPUT_MIN_HEIGHT: number = INPUT_LINE_HEIGHT + INPUT_VPAD * 2;
const INPUT_MAX_HEIGHT: number = INPUT_LINE_HEIGHT * 4 + INPUT_VPAD * 2;  // 113，最大高度
// 展开态行数上限 = 官方非内联模式 maxLines 默认值 UINT32_MAX（显式回填同值：两态共用一个
// maxLines 表达式，展开态行为与未设置时一致——不截断，超出 4 排仍由 constraintSize 钳顶）
const INPUT_EXPANDED_MAX_LINES: number = 4294967295;
const INPUT_CAPSULE_RADIUS: number = INPUT_MIN_HEIGHT / 2;  // 25，半圆
// 收起态左右内缩（★ 2026-09-09 决明「收起时输入框长度比现在短」；同日复验「再短一点点」
// 28 → 36）：单侧 36vp——屏宽 360 时胶囊 328 → 256（短约 22%）；展开态归 0（= 原展开态宽度，
// 决明口径「展开为原来的展开态」）。单旋钮：真机觉得不够短/太短只改本值；平板下按绝对值
// 收窄、不随屏宽放大，观感不足再改比例
const INPUT_COLLAPSED_INSET: number = 36;
// 输入栏图标键尺寸（＋ / 全屏输入 / 发送·停止三键同规格、两态共用；36 = 点击区，圆形按压
// 蒙层直径同此值——蒙层圆心即键中心，下面的同心内缩推算依赖本值）
const INPUT_KEY_SIZE: number = 36;
// 展开态文字区底部内边距（2026-09-09 决明「就是裁切边界，调小，贴工具栏」；同日复验
// 「顶裁切边界改回原来」——顶部恢复 INPUT_VPAD，本常量只管底部）：展开态 TextArea 底部
// padding 由 INPUT_VPAD 归 0——文字底部直接贴 TextArea 底边（= 工具行顶边，视觉间距只剩
// 工具行内 4vp 空隙）。展开态可视行数（TextArea 高 = clamp(14.5 + 内容, 50, 113)，自检复算
// 表）：空/1 排钳到 50vp、可视 1.69 排；2~4 排按内容增高、完整显示不裁切；5 排起钳到
// 113vp、可视 4.69 排（末排露 14.5vp）。收起态仍用 INPUT_VPAD（单排胶囊文字居中观感不变）
const EXPANDED_TEXT_BOTTOM_VPAD: number = 0;
// 聚焦展开几何（2026-09-09 任务书）：展开态总高 94 = 文本行 50 + 工具行 44——★ 决明
// 「撑三排字」口径 = 3×21 + 14.5×2 = 92（输入三行内容时的高度），与 94 基本重合，观感
// 唯一可调点 = 工具行高与文本行上下 padding 两处（真机偏高/偏低只调这两值，勿改结构）
const INPUT_EXPANDED_HEIGHT: number = 94;
// 工具行高 = 展开总高 − 文本行高（44 = 94 − 50）
const TOOL_ROW_HEIGHT: number = INPUT_EXPANDED_HEIGHT - INPUT_MIN_HEIGHT;
// 工具行内缩（★ 2026-09-09 决明「展开后加号与发送能否再贴边一些，大概就是他们点击有圆形
// 蒙层，圆和输入框圆角同心」）：同心条件 = 蒙层圆心（即键中心）与胶囊圆角弧心重合——弧心
// 距侧边/底边各 INPUT_CAPSULE_RADIUS(25)，键半径 18 → 左右与底部内缩同为 7（原左右 16
// 偏内、底部 4 偏下）；顶部内缩由行高反推 = 44 − 36 − 7 = 1，使键中心距行顶 19 = 距胶囊底
// 25，与圆角弧心同一水平线（旧口径「键 36 + 上下各 4」随之作废）
// ★ 下发方式（2026-09-09 真机报障后定）：水平内缩走工具行 padding，**垂直内缩走键/文字
// 外边距**——行高收起态为 0，而组件自身的垂直 padding 会把最小高度撑到 padding 之和
//（真机实测：收起态胶囊被撑高、左右两键随之不居中）；子元素外边距不改变显式高度，且
// 收起态内容被 clip 裁掉，观感零差异
const TOOL_KEY_INSET: number = INPUT_CAPSULE_RADIUS - INPUT_KEY_SIZE / 2;  // 7
const TOOL_ROW_TOP_INSET: number = TOOL_ROW_HEIGHT - INPUT_KEY_SIZE - TOOL_KEY_INSET;  // 1
// 失焦收起延时（ms）：点工具行按钮若夺焦，blur 先于 click 到达——Down 取消（时序守卫，
// 见 startCollapseTimer / cancelCollapseOnTouch）
const INPUT_COLLAPSE_DELAY: number = 150;
// 键盘态底部留白切换动画时长（ms，与系统键盘动画同量级；观感可调）
const KEYBOARD_INSET_ANIM_MS: number = 250;
// 浮层行间距（外层 Column 的 space 值）：chip 行 / 胶囊 / 合规提示行之间
const BAND_ROW_SPACING: number = 8;
// 合规提示行几何（2026-09-03）：11fp 单行显示高取 16（≈11×1.45）；Text 与键盘态占位共用
// 同一常量——占位镜像文本高度，浮层总高恒定（输入框零位移防闪动/被遮，见 keyboardOn 注释）
const COMPLIANCE_HINT_HEIGHT: number = 16;
// 待发条几何（2026-09-16 单条消息指定技能）：容器位置与对齐口径照 AttachmentStrip（胶囊内
// 顶部、左右留白 12）；条体 = 灰底圆角横条（官方灰阶实色 comp_fallback_gray，深浅分治不透明，
// 不接光感——变量插入卡同系；禁同层再设 systemMaterial，单层组合红线）
const DESIGNATE_STRIP_HPAD: number = 12;
const DESIGNATE_STRIP_TOP: number = 12;
const DESIGNATE_STRIP_RADIUS: number = 12;
// ── 上下文用量圆环键（2026-09-17 会话上下文用量，拍板 P1/P2）──
// 落点 = 工具行「＋」与模型名之间（收起态随工具行高度归零整体隐藏，「收起态不展示」天然
// 成立）；环本体 = ContextUsageRing 共用件（2026-09-18 增量笔提取——面板总览卡同源消费，
// 官方 Progress Ring 20vp 直径 / 3vp 描边与色档三档均单源在该件）。垂直内缩同相邻键（顶 1 /
// 底 7，见 TOOL_KEY_INSET）；外框 36×36 与三键同规格（点击区与同心几何不破）

@Component
export struct ChatInputBar {
  // 会话运行中（true = 发送键变停止键——M1 口径运行中不插话；输入框仍可编辑暂存）
  @Prop busy: boolean;
  // DB 就绪（M1 既有行为：未就绪占位符切换 + 发送键禁点）
  @Prop dbReady: boolean = true;
  // 常态底部留白（页面注入 = 避让区高 + 悬浮页签让位，约 100vp；键盘升起时本组件置 0——
  // 键盘已覆盖底部系统区，注入值此时冗余，正是「不遮挡但抬起过高」的间距来源）。
  // @Prop：navBarHeight 异步实测，须状态驱动重渲染（坑57 同族）
  @Prop bottomPad: number = 0;
  // 展开增量上报（2026-09-09 决明「展开输入时不管会话多少页面都不动」；同日二修/三改）：
  // 展开让浮层长高的只有工具行（44）——其高度须从消息列表底部衬距里扣掉，否则列表被同步
  // 顶上去。★ 上报值取「实测」（工具行 onAreaChange，见 reportInset）：与浮层高度实测同一次
  // 布局周期 → 展开/收起动画期间同步变化、底衬恒定。硬编码常量 + 在 animateTo 闭包内一次性
  // 设终值会与动画中的实测高度错拍（扣减先到位、卡片高度后长成，列表先沉后弹）。
  // 代价（决明拍板取舍）= 展开态卡片顶边覆盖末条下缘
  onToolRowInset: (inset: number) => void = () => {
  };
  // 展开态上报（2026-09-09 二修之三）：true = 输入框展开（用户开始操作输入栏）→ 父组件
  // 合闸暂停进页校正链的拽底；收起动画结束时回落 false 开闸。展开/收起都会让浮层高度
  // 变化，链若存活会在每次变化时把列表无动画拽到底（决明报的「有的会话进去后展开输入框
  // 页面还是上移」）
  onExpandState: (expanded: boolean) => void = () => {
  };
  // 待发附件（父组件 @State 持有；数组赋值触发 @Prop 刷新——附件链 2026-09-03 起已接线，
  // 选择入列后非空即渲染附件条）
  @Prop attachments: PendingAttachment[] = [];
  // 思考强度（2026-08-31 任务 B 起随请求下发；'' = 默认不传；★ 08-31 归正 @Link——父
  // 经 PageShell.content 传播，@Prop 不随父刷新（坑16），选档后 chip 回显冻结）。
  // 菜单选项集不入参——2026-09-06 模型级精化起 chip 行 @StorageProp 自订阅广播键
  //（CHAT_THINKING_OPTIONS_KEY，坑16 同款正解）
  @Link thinkingValue: string;
  // 档位选择回调（父组件落值回显——占位不进请求；二百二十九起消费方 = 回退路径 chip）
  onPickThinking: (option: string) => void = () => {
  };
  // 标题栏思考键交互期（★ 二百二十九：HDS 路径思考入口迁标题栏「思考」热区，其按压期与
  // 菜单期经 ChatPage → ChatPageContent 三级 @Link 链下发行至此，与 chipMenuOpen/
  // chipTouchActive 共同构成「交互期不收」守卫——本组件居 PageShell.content（@BuilderParam）
  // 内，@Prop 不随父刷新会冻结在首帧（坑16），@Link 为订阅式正常通道）
  @Link thinkingHold: boolean;
  // 单条消息指定技能（2026-09-16 单条消息指定技能）：两值 @Link 三级链（ChatPage @State →
  // ChatPageContent @Link → 本组件 @Link，坑16 正解通道——本组件居 PageShell.content
  // （@BuilderParam）内，@Prop 不随父刷新会冻结在首帧）；'' = 未指定 → 待发条不渲染
  @Link designatedSkillId: string;
  @Link designatedSkillName: string;
  // 待发条 × 键上行（父组件清两态）
  onClearDesignate: () => void = () => {
  };
  // 发送回调（text 已 trim；附件随上抛）。★ 2026-09-15 发送链收口笔：返回值 = 「已投递或已
  // 进入确认流程」——本组件两处调用点按它决定清不清本地草稿（false = 被拦，文字留在条上）
  onSend: (text: string, attachments: PendingAttachment[]) => boolean = (): boolean => false;
  // 中断回调（busy 时点击停止键）
  onAbort: () => void = () => {
  };
  // 「+」点击（附件与提示词面板入口——上行父组件开 ChatPromptSheet 半模态）
  onAddFile: () => void = () => {
  };
  // 长文本粘贴上行（2026-09-23 粘贴长文本转文件笔）：页面把这段文本转成附件入列，完成后以
  // settle(converted) 回报结果——**必调恰一次**（成功真、未入列假）。本组件的收口闭包据此按
  // settlePastedText 的单源判据把输入框文本对齐成「附件与原文恰有其一」（详见 onPaste 注释）。
  // ★ 默认实现 = settle(false) 而非空体（2026-09-24 自检轮）：两条钩子都拦下原生插入、全靠这个
  // 回调把文本还回来——宿主漏接线时空体 = 长文本静默消失（既不入框也不转件）；settle(false)
  // 让漏接线退化成「不转附件、原文照常落框」（P0-1 禁静默失败）
  onPasteLongText: (text: string, settle: (converted: boolean) => void) => void =
    (_text: string, settle: (converted: boolean) => void): void => {
      settle(false);
    };
  // 附件行删除（index 上行父组件从列表移除——本地状态独占，无网络副作用）
  onRemoveAttachment: (index: number) => void = () => {
  };
  // 已选未发附件点开预览（2026-09-15 预览第三轮，拍板 4：fileId 上行 → ChatPageContent
  // 分派——与消息流附件泡同一查看器/系统预览）
  onPreviewAttachment: (fileId: string) => void = () => {
  };
  // 全屏输入：点工具行内的全屏键上行当前文本（父暂存为面板初值）——胶囊文本是本组件
  // @State，父页拿不到，必须随回调带出
  onFullscreen: (text: string) => void = () => {
  };
  // 上下文用量圆环值（2026-09-17 会话上下文用量）：-1 = 窗口未知或无数据（仅底环仍可点，
  // 拍板 P4——点开面板看已用数）；0~100 = 已用占比（值供页面侧活算刷新，§3.6：发送收尾/
  // 切模型/开面板时刷，打字与生成中不刷）。★ @Link 三级链（ChatPage @State →
  // ChatPageContent @Link → 本组件 @Link，坑16 正解通道——本组件居 PageShell.content
  // （@BuilderParam）内，@Prop 不随父刷新会冻结在首帧，同 modelLabel 先例）
  @Link ctxRingPct: number;
  // 圆环点击上行（带当前草稿文本——面板「本轮输入」段打开时取一次，照 onFullscreen 先例
  // 带出：胶囊文本是本组件 @State，父页拿不到）
  onOpenContext: (text: string) => void = () => {
  };
  // 全屏输入回写通道（父持命令制造 @Prop——cmd tick 驱动覆盖（含空串清空）；只写于两时点：
  // 面板关闭回写 / 发送清空——正常打字父不改，无输入回环；⚠️ @Watch 首次不触发（初始 0，
  // 父命令 tick 从 1 起）
  @Prop fullInputDraft: string = '';
  @Prop @Watch('onFullInputCmd') fullInputCmd: number = 0;
  // 当前模型名（2026-09-09 工具行显示；只显示不可点——模型切换入口在标题栏「切换模型」键，
  // 本笔不新增点击/菜单）。★ @Link 三级链（ChatPage @State → ChatPageContent @Link → 本
  // 组件 @Link）：本组件居 PageShell.content（@BuilderParam）内，@Prop 不随父刷新会冻结在
  // 首帧（坑16），@Link 为订阅式正常通道；也不另建全局广播键（新增键牵动断言脚本
  // 白名单与键治理）。'' = 未解析到连接，显示「未选择」灰字
  @Link modelLabel: string;
  @State private text: string = '';
  // 聚焦展开（2026-09-09）：true = 两排卡（文本行 + 工具行），false = 单排胶囊。状态最小化
  // ——只此一个状态，驱动工具行高度（★ 同日三改：工具行改恒存在 + 高度 0/44 切换，见 build）
  @State private expanded: boolean = false;
  // 工具行实测高度（onAreaChange 回写后上报，见 reportInset）：与浮层高度实测出自同一次
  // 布局 → 展开/收起动画期间同步变化、列表底衬恒定（硬编码常量会与动画中的实测高度错拍，
  // 列表先沉后弹）
  private toolHeight: number = 0;
  // 失焦延时收起定时器（-1 = 无待收起；与组件销毁成对清理，见 aboutToDisappear）
  private collapseTimer: number = -1;
  // chip 菜单开着（★ 2026-09-09 真机报障：决明「展开态不管输入框有无内容，点击两胶囊，输入框
  // 都会变回收起，菜单也跟着下移」——点 chip 开菜单致 TextArea 失焦（菜单弹窗取焦），失焦收起链
  // 把卡片收掉、菜单随浮层一起下移）：菜单开着期间一律不收。驱动 = 官方 MenuOptions.onAppear/
  // onDisappear 经 ChatParamChipRow 上报（见 chip 行 onMenuStateChange）；决明语义「展开态只有
  // 系统返回或收起键盘才收起」，故菜单关闭后也不补收，等下一次失焦/键盘事件
  private chipMenuOpen: boolean = false;
  // chip 行手指按着（Down 置位、Up/Cancel 复位；与 chipMenuOpen 共同构成「chip 交互期不收」守卫）：
  // blur 若发生在 Down 之后（按钮夺焦路径），150ms 计时器会在菜单弹出前触发——Down 取消只能掐掉
  // 已存在的计时器、掐不掉 blur 之后新挂的，故用按位标志把整个按压期封住（onFocus 一并自愈）
  private chipTouchActive: boolean = false;

  // ── 合规提示行显隐驱动（2026-09-03）──
  // ★ 语义定稿（2026-09-03 决明二轮真机反馈「抬起后输入框偏低被遮 + 移动不连贯闪动」重推）：
  // 键盘弹起时**藏字不塌位**——只隐藏文字，布局空间由等高空占位撑住（build 内双分支
  // 同 COMPLIANCE_HINT_HEIGHT），浮层总高恒定 → 输入框**零位移**：键盘动画期间输入框
  // 只随窗口 RESIZE 单方向平滑上移（连贯），最终态保持平时高度（距窗口底 8+23+16+
  // bottomPad，完整暴露于键盘上方）。初版「隐藏即塌陷」（提示行消失输入框下跳 24vp）
  // = 闪动 + 最终态过低两个反馈的同一根因。
  // 驱动 = window.on('keyboardHeightChange')（★ 官方**键盘专用**事件：d.ts 实锤
  // @since 7 回调直接给 px 高度整数，语义 = 「软键盘被窗口调用且与窗口重叠时的高度
  // 变化」——弹起/收起/切换输入法均触发（社区多篇实证，官方文档
  // js-apis-window 章节明确）；事件式零轮询——P1-2 轻量检测）。
  // ★ 判定沿革：初版 avoidAreaChange + visible（真机实测键盘未弹也 true，提示行闪现
  // 消失）；二版 bottomRect.height>0（通用事件绕路）；三版即本版 keyboardHeightChange。
  // 初值经 getWindowAvoidArea 同步读兜底——键盘事件只报「变化」，注册前已弹起的状态
  // 不会补发。判定仅驱动文字显隐 → 键盘收起恢复显示
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

  aboutToAppear(): void {
    // 键盘监听注册（与 aboutToDisappear 的 off 成对；事件式零轮询）。注册后同步读一次
    // 补初始（本 SDK getWindowAvoidArea 为同步接口——事件只报「变化」，从全屏输入等
    // 触发键盘的场景返回时，注册前已弹起的键盘状态不会凭空补发）
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
      console.error('ChatInputBar keyboard listen failed: ' + JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 键盘避让模式兜底恢复（防「聚焦态被销毁」把窗口级模式留在 RESIZE——离页/销毁路径
    // 与 onBlur 成对；幂等，重复设同值无副作用）
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
  // 沉浸光感档位（2026-09-03 开关体系恢复：胶囊「光感态」＝REGULAR
  // 材质随沉浸光感总档偏移——该态与系统材质时代的驱动契约一致）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 胶囊官方灰实底（默认）；false = REGULAR 材质
  // 光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 键盘发送开关（2026-09-03 偏好设置页第 4 项）：true = 键盘回车键变发送键（onSubmit
  // 直接发送）/ false = 换行键（默认——与 text_area.d.ts enterKeyType 官方默认一致）。
  // @StorageProp 订阅 = 偏好页切换即刷（坑16 正解）
  @StorageProp(PREF_KEYBOARD_SEND_KEY) keyboardSend: boolean = false;
  // 粘贴长文本转文件（2026-09-23 粘贴长文本转文件笔）：开关与长度阈值两键——偏好设置页的
  // 开关行与阈值卡直写持久键，本组件 @StorageProp 自订阅（偏好页切换即刷，坑16 正解）。
  // ★ 阈值经 clampPasteThreshold 钳位后再进判定（老备份或手改值越界会让判定静默失效）
  @StorageProp(PREF_PASTE_AS_FILE_KEY) pasteAsFile: boolean = true;
  @StorageProp(PREF_PASTE_AS_FILE_THRESHOLD_KEY) pasteThreshold: number = PASTE_THRESHOLD_DEFAULT;
  // 已被 onPaste 受理的那段原文（2026-09-24 输入法通路笔）：防两条通路对同一段文本各转一次——
  // onWillInsert 见到与它逐字相同的插入即放行（交给 onPaste 的收口清理），不再重复转。
  // ★ 生命期 = 一次受理（2026-09-24 自检轮修）：onPaste 的收口回调里复位。原版只写不清 ⇒
  // 「先长按粘过某段 → 之后用键盘剪贴板再粘同一段」会被当重复放行（功能静默失效，且恰是
  // 真机复测的走法）——哨兵问的是「这一笔是否已被受理」，不是「这段文本历史上是否粘过」
  private lastPasteHandled: string = '';

  // 键盘发送键（2026-09-03 接偏好开关）：与胶囊发送键同语义——trim + 可发判定 + 清空上行。
  // busy 守卫 = M1 红线「运行中不插话」（busy 时胶囊键已是停止键，键盘侧 toast 说明非静默
  // ——P0-1）；空/纯空格/DB 未就绪静默不发（与胶囊禁点等价——键盘键无法置灰）。
  // ★ 2026-09-15 发送链收口笔：清空移到返回值判定之后——被拦（解析中/失败/过大/无服务商）
  // 时草稿留在输入框，不与胶囊键分叉
  private onKeyboardSend(): void {
    const trimmed: string = this.text.trim();
    if (!this.dbReady || !this.canSend()) {
      return;
    }
    if (this.busy) {
      this.getUIContext().getPromptAction().showToast({ message: '当前请求进行中，发送已暂停' });
      return;
    }
    if (this.onSend(trimmed, this.attachments)) {
      this.text = '';
    }
  }

  // 停止图标色：官方 warning 色资源（深浅分治系统接管；2026-09-12 UI 同形异构归一笔 2
  // 换源——SDK resources.txt 查证浅 #FA2A2D / 深 #E64548 与原手写分支逐字同值，纯换源零
  // 色差，消除「自称官方实则手写」异源；原 appColorMode 订阅随之失去唯一消费点已删）
  private abortColor(): ResourceColor {
    return $r('sys.color.ohos_id_color_warning');
  }

  // 发送可用：文本非空、附件存在、或已指定技能（2026-09-16 单条消息指定技能扩第三项——
  // 只指定不打字也发得出去：竞品「空消息 400」防法；协议侧 user 内容由标注句兜底，见
  // ChatSendCtrl.dispatchSend）
  private canSend(): boolean {
    return this.text.trim() !== '' || this.attachments.length > 0 ||
      this.designatedSkillId !== '';
  }

  // 展开/收起（UIContext 形态——2026-09-04 纪律禁全局 animateTo）：工具行高度 + 容器高度
  // 变化同帧插值。★ 2026-09-09 决明「先换弹簧」：曲线由传统曲线 FastOutSlowIn 换官方物理
  // 弹簧 curves.springMotion（官方《弹簧曲线》「建议优先使用物理曲线」；达终点速度为 0、
  // 不「戛然而止」，带轻微回弹）。★ 弹簧曲线动画时长由曲线参数与变化量自动计算，AnimateParam
  // 的 duration 不生效（官方 d.ts 原文），故不再传 duration。手感两旋钮 = response（一个完整
  // 振荡周期，秒；官方默认 0.55）与 dampingFraction（阻尼系数，越小越弹；官方默认 0.825）
  // ——本处 0.4 / 0.55（同日三轮调参：0.85 → 0.6「回弹幅度可否大一些」→ 0.5「弹幅再大一点」
  // → 0.55「改为现在和上一次之间」）：二阶阻尼系统首峰过冲 ≈ exp(−πζ/√(1−ζ²))，ζ=0.55 ≈ 12.6%
  //（44vp 行程约 5.6vp），沉降约 0.44s——落在 0.6（≈9.5%）与 0.5（≈16%）之间，只调这一个数
  private setExpanded(next: boolean): void {
    // 展开即合闸（父组件暂停进页校正链的拽底，见 onExpandState 注释）；收起态的开闸在
    // 动画结束时进行——收起动画期间浮层高度仍在变，同属交互窗口
    if (next) {
      this.onExpandState(true);
    }
    this.getUIContext().animateTo({
      curve: curves.springMotion(0.4, 0.55),
      onFinish: (): void => {
        if (!this.expanded) {
          // 收起动画结束：高度已归 0（恒存在节点的 onAreaChange 会报到底），此处兜底归零
          // 防极端时序残留；同时开闸
          this.toolHeight = 0;
          this.reportInset();
          this.onExpandState(false);
        }
      }
    }, () => {
      this.expanded = next;
    });
  }

  // 底衬扣减上报（实测值；调用点 = 工具行 onAreaChange + 收起兜底归零）。六改后键与 chip 同行
  // 不额外占高，扣减只含工具行（展开增量）
  private reportInset(): void {
    this.onToolRowInset(this.toolHeight);
  }

  // 失焦延时收起（150ms）：点工具行按钮若夺焦，blur 先于 click 到达——键 Down 取消（守卫见
  // cancelCollapseOnTouch）；一次性 UX 防误收，非轮询（P1-3 例外登记）
  private startCollapseTimer(): void {
    // 交互期不收（见 chipMenuOpen / chipTouchActive / thinkingHold 注释——菜单弹窗取焦或按压期
    // 失焦，不拦会连带把卡片收掉、菜单随浮层下移；thinkingHold = 标题栏思考键，二百二十九新增）
    if (this.chipMenuOpen || this.chipTouchActive || this.thinkingHold) {
      return;
    }
    if (this.collapseTimer !== -1) {
      clearTimeout(this.collapseTimer);
    }
    this.collapseTimer = setTimeout(() => {
      this.collapseTimer = -1;
      // 触发时复检（二百二十九）：标题栏思考键的按压/菜单上报无法像 chip 行那样在 Down 时
      // 取消本组件的计时器（跨组件无句柄），故已在途的计时器在此按同一守卫复检一次——守卫
      // 期跳过本次收起（下一次失焦再按正常路径起计时）
      if (this.chipMenuOpen || this.chipTouchActive || this.thinkingHold) {
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
  // 等高，见 TOOL_KEY_INSET；水平内缩由工具行 padding 左右 7 下发，不用外边距）。
  // ★ 收起态缘侧仍为 4（同心值应为 7，差 3vp）——本笔按决明口径只动展开态，且 4 → 7 是往
  // 内收，与「贴边」方向相反，故不动；如需两态一致，改此一处即可
  private keyMargin(isLeft: boolean): Margin {
    if (this.expanded) {
      return { top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET };
    }
    if (isLeft) {
      return { left: 4, bottom: 7 };
    }
    return { right: 4, bottom: 7 };
  }

  // 「全屏输入」键（★ 2026-09-09 三改：原为参数 chip 行上方独立一排的「全屏输入」文字快捷条，
  // 决明指令「既然全屏键也只在展开后出现，可否移至展开后输入框发送键左侧，用类似左下右上箭头
  // 的图标」——改挂工具行、发送键左侧，图标 = sys.symbol.arrow_up_left_and_arrow_down_right
  //（对角线双箭头 = 扩展语义，SDK 符号表实锤）。形制照 AddKey：36×36 透明底 + SymbolGlyph
  // 无底、icon_primary 次级色（扩展入口非主操作）。收益 = 浮层高度少一个变量——原来它独立
  // 占一排，出现/消失的高度变化会甩动同浮层的相邻元素）
  @Builder
  FullscreenKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .width(INPUT_KEY_SIZE)
    .height(INPUT_KEY_SIZE)
    .backgroundColor(Color.Transparent)
    // 垂直内缩同键（顶 1 / 底 7，见 TOOL_KEY_INSET）；水平位置由工具行 padding 与相邻键决定
    .margin({ top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET })
    .onTouch((event: TouchEvent): void => {
      this.cancelCollapseOnTouch(event);
    })
    .onClick(() => {
      this.onFullscreen(this.text);
    })
  }

  // 「+」扩展键（附件入口；图标即本体——同发送键无圆底无材质，次级色 icon_primary 与发送键
  // 强调色区分，+ 是扩展入口非主操作）。@Builder 抽一次两态各实例化一处：收起态在文本行内、
  // 展开态在工具行内（定位差异走 keyMargin，按钮无状态两态重建无副作用）
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

  // 「上下文用量」圆环键（2026-09-17 会话上下文用量，拍板 P1/P2）：极简圆环不显数字；
  // 环本体 = ContextUsageRing 共用件（形制/色档/仅底环口径单源在该件，2026-09-18 提取）。
  // ★ 点按非破坏性（附录 A #30，Claude Code #92570「点环直接触发压缩」被当 bug 报的反面）：
  // onClick 只上行开面板看明细，零业务副作用。★ 小尺寸 Ring 渲染退路（方案 §六-5）已写入
  // 方案档：真机若发虚/描边断裂改自绘 strokeDashArray，二选一按真机结果定
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

  // 发送/停止键（2026-09-09 起两态各一处）：运行中 = 右单停止键（M1 口径不插话，busy 中发送
  // 禁行；样式 = 36×36 无底图标键，警示红 stop_circle 深浅分治——禁圆底材质铁律）；空闲 =
  // 发送键（强调色图标无底无材质，空文本且无附件置灰禁点，DB 未就绪同样禁点）
  @Builder
  SendOrStopKey() {
    if (this.busy) {
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
      Button() {
        SymbolGlyph($r('sys.symbol.paperplane_fill'))
          .fontSize(20)
          .fontColor([$r('sys.color.comp_background_emphasize')])
      }
      .width(INPUT_KEY_SIZE)
      .height(INPUT_KEY_SIZE)
      .backgroundColor(Color.Transparent)
      .margin(this.keyMargin(false))
      // 空文本且无附件置灰禁点（P0-1 不发空消息）；DB 未就绪同样禁点（M1 行为）
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
        if (this.onSend(trimmed, this.attachments)) {
          this.text = '';
        }
      })
    }
  }

  build() {
    Column({ space: BAND_ROW_SPACING }) {
      // ── 参数 chip 行（思考；收起态隐藏。联网 chip 2026-09-19 迁标题栏「更多」菜单）──
      Row({ space: 8 }) {
        // ★ 2026-09-09 收起态隐藏（决明「收起时胶囊不显示，切换为展开态时胶囊才出现」——收起态
        // 胶囊已收窄，参数 chip 常显会相对胶囊左右外凸）：外层 Row 恒挂 + 透明度两态切换。
        // 官方依据 = 透明度属官方可动画属性（《属性动画概述》「外观：透明度、圆角、边框、阴影」）
        // + FAQ 232（声明自定义组件时设置的属性作用于其不可见包裹容器）；不用条件渲染——出现/
        // 消失不参与布局动画，且行高变化会牵动浮层高度与列表底衬（本组件工具行已踩过，见工具行
        // 注释）。**不塌位**：组件恒挂、行高不变（chip 本体高 36 撑住）→ 浮层总高恒定、
        // 列表底衬零联动（与合规提示行「藏字不塌位」同法）。收起态不可命中 = 隐形 chip 不许吃
        // 点击。★ 2026-09-09 真机报障修正（决明「收起时还是能点，挂错了吗」）：初版写
        // HitTestMode.None 无效——本地 SDK d.ts 实锤（ets/component/enums.d.ts:3328-3330）「The
        // node itself does not respond to the hit test and does not block the hit test of child
        // nodes, sibling nodes, and ancestor nodes」= 自身不响应但**不阻塞子节点**，chip 照旧收
        // 点击；改 HitTestMode.Block（同 d.ts:3305-3306「blocks the hit test of child nodes…」=
        // 阻塞子节点）。本层盒只覆盖 chip 自身区域；该条带对下层消息流的阻断与否由 ③ 浮层容器
        // 决定、本次未变（ChatPageContent）
        Row() {
          // 运行参数 chip 行（思考强度；样式/菜单细则见 ChatParamChipBar 头注释。联网 chip
          // 2026-09-19 迁标题栏「更多」菜单，本行 HDS 路径渲染空行、回退路径仅余思考 chip）
          ChatParamChipRow({
            thinkingValue: $thinkingValue,
            onPickThinking: (option: string): void => { this.onPickThinking(option); },
            // 菜单开合上行（收起守卫，见 chipMenuOpen 字段注释）：开菜单即取消待收起
            onMenuStateChange: (open: boolean): void => {
              this.chipMenuOpen = open;
              if (open) {
                this.cancelCollapseTimer();
              }
            }
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

      // 收起态收窄容器（★ 2026-09-09 决明「收起时输入框长度比现在短，展开时高度与宽度双变化」）：
      // 胶囊自身恒 100% 宽，收窄由本层左右内缩下发——padding 属官方可动画布局属性（《属性动画
      // 概述》「布局属性：位置、大小、内边距、外边距、对齐方式、权重等」），与工具行高度在
      // **同一次** animateTo 内插值（见 setExpanded）→ 宽高双变同源同曲线、弹簧同步；不用百分比
      // 宽度——百分比尺寸动画依赖父容器确定尺寸，数值内缩无此约束。chip 行与合规提示行在本
      // 容器之外：收窄只作用于胶囊，悬浮键与参数 chip 位置不动
      Column() {
        // 胶囊容器（附件条（有附件时）+ 文本行 + 工具行；材质/半圆圆角/clip 挂外层 Column——
        // 「同一子树最外层只设一次材质」；容器不设高度——附件条增删 + 文本行高度（收起态恒
        // 单排 50 / 展开态 1~4 排自增高，见 TextArea 的 constraintSize）+ 工具行进出全由内容自适应）
        Column() {
          // 待发条（2026-09-16 单条消息指定技能）：胶囊内顶部、附件条之前——与附件条同族
          // 「本条消息携带物」（chip 行是运行参数，不同族故不进 chip 行）。空名防御：id 非空
          // 而名空（技能已删）不渲染空名条——发送时链路侧 querySkill null 自然降级（第二道
          // 保险）。× 键 = 行内图标键官方形制（无底 TEXTUAL + font_secondary）
          if (this.designatedSkillId !== '' && this.designatedSkillName !== '') {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.wand_and_stars'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
              Text('技能 · ' + this.designatedSkillName)
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
                this.onClearDesignate();
              })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(DESIGNATE_STRIP_RADIUS)
            .backgroundColor($r('app.color.comp_fallback_gray'))
            // 容器留白用 margin（条体自身是完整胶囊，不借父 padding）——左右/顶部照
            // AttachmentStrip 口径；底部无（与附件条的 12 顶留白或文本行的 14.5 顶 padding 相接）
            .margin({ left: DESIGNATE_STRIP_HPAD, right: DESIGNATE_STRIP_HPAD,
              top: DESIGNATE_STRIP_TOP })
          }
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

          // 文本行（恒定，两态共用同一个 TextArea——单实例硬约束：放进 if 分支会随重建丢焦点/
          // 光标/已输入文本）：收起态 = ＋ | TextArea | 发送·停止（＋ 与发送键同规格 36×36
          // 对称、底对齐贴底）；展开态两键移入工具行，本行只剩 TextArea 占满整行
          Row() {
            if (!this.expanded) {
              this.AddKey();
            }

            TextArea({ placeholder: this.dbReady ? '输入消息…' : '数据库未就绪，暂不可发送', text: $$this.text })
              .layoutWeight(1)
              // 不设 height = 官方自适应内容高度（text_area.d.ts）；constraintSize 钳制行数——
              // 收起态上下限同钉单排（50：多行内容裁到一排，高度与内容无关，决明「不论有无内容
              // 收起后高度均一致」）/ 展开态 2~4 排完整显示、5 排起钳顶（见
              // EXPANDED_TEXT_BOTTOM_VPAD），再多框内滚动（TextArea 天生可滚动）；显式
              // lineHeight 使换算确定
              .constraintSize({ minHeight: INPUT_MIN_HEIGHT,
                maxHeight: this.expanded ? INPUT_MAX_HEIGHT : INPUT_MIN_HEIGHT })
              // 收起态不滚动（★ 2026-09-09 决明复验「虽然只显示一排，但是还能滚动，很别扭；
              // 我的要求不是收起时不能滚动吗，它现在还有滚动条」）：maxLines 收 1 行 + 官方
              // MaxLinesMode.CLIP——官方 API 参考原文「非内联模式：文本按 maxLines 指定的行数
              // 截断」，即超出部分直接截断、不产生滚动区（SCROLL 模式才滚动，d.ts text_common.d.ts
              // 「Text can be scrolled when it exceeds the maximum number of lines」）；展开态
              // 回填官方非内联默认值 UINT32_MAX = 不截断，框内滚动行为不变
              .maxLines(this.expanded ? INPUT_EXPANDED_MAX_LINES : 1,
                { overflowMode: MaxLinesMode.CLIP })
              .fontSize(15)
              .lineHeight(INPUT_LINE_HEIGHT)
              // 透明底无边框：胶囊视觉由外层 Column 的材质承担（材质铁律，勿在此恢复背景/边框）
              .backgroundColor(Color.Transparent)
              // 内边距两态分治（★ 2026-09-09 决明「裁切边界调小，贴工具栏」；同日复验「顶裁切
              // 边界改回原来」——顶部两态都保持 INPUT_VPAD，只底部展开态归 0）；左右 16 对称
              //（同日「右侧改回与左一样」——原 right 4 比左侧窄 12vp，真机实测 4vp vs 16vp）
              .padding({ left: 16, right: 16,
                top: INPUT_VPAD,
                bottom: this.expanded ? EXPANDED_TEXT_BOTTOM_VPAD : INPUT_VPAD })
              // 键盘回车键形态（2026-09-03 偏好开关「键盘发送」）：true = Send（右下角发送键，
              // 点击 onSubmit 直接发送——与胶囊发送键同语义）；false = NEW_LINE 换行键（官方
              // 默认值，存量行为）。★ 长按换行 = 系统键盘行为，官方 API 只负责键形态——
              // text_area.d.ts 实锤：NEW_LINE 时 onSubmit 不触发、Send 触发
              .enterKeyType(this.keyboardSend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
              .onSubmit((enterKey: EnterKeyType): void => {
                if (enterKey === EnterKeyType.Send) {
                  this.onKeyboardSend();
                }
              })
              // 聚焦 = 展开两排卡 + 键盘避让切「压缩」模式；失焦 = 卡片延时收起（150ms，
              // startCollapseTimer——工具行按钮 Down 取消，防点键误收）+ 键盘避让恢复全局默认
              .onFocus(() => {
                this.cancelCollapseTimer();
                // 自愈：菜单/按压上报若因异常时序残留，回焦即清（避免之后再也不收起）；
                // thinkingHold 同（@Link 回写 ChatPage，菜单若仍开着其 onDisappear 会再复位）
                this.chipMenuOpen = false;
                this.chipTouchActive = false;
                this.thinkingHold = false;
                // ★ 2026-09-09 决明真机报障修复（多行内容 + 点靠上排 → 输入框底部与键盘重叠）：
                // 全局默认 RESIZE_WITH_CARET 是「随光标避让」——官方语义「当输入框的光标位置发生
                // 变化时，系统会自动触发相应的界面避让行为，确保**光标**始终处于可视区域内」
                //（最佳实践《软键盘布局适配》），故光标在上排时系统只保证光标可见、卡片底部仍落在
                // 键盘下。本页输入栏贴底，改用官方针对「底部操作栏被遮挡」的处方：同一篇原文「可以
                // 通过设置软键盘的避让模式为 KeyboardAvoidMode.RESIZE（压缩模式），来解决底部操作
                // 栏被遮挡的问题」。仅聚焦期间生效、失焦即恢复（成对）——表单页的光标跟随与半模态
                // 面板（走 SheetKeyboardAvoidMode，与页面模式解耦）均不受影响
                this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
                this.setExpanded(true);
              })
              .onBlur(() => {
                this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
                this.startCollapseTimer();
              })
              // 粘贴拦截（2026-09-23 粘贴长文本转文件笔；同日自检轮收口）：粘贴文本达到阈值时
              // 不插进输入框，改为落盘成 .txt 附件挂上附件条。判定单源 =
              // AttachmentPickCtrl.shouldPasteAsFile（开关、纯空白、长度三条件都在它里面——
              // 本处不重写条件，避免两处漂移）。
              // ★ 顺序是硬要求：粘贴前快照 before 先取、preventDefault 在回调返回前调用，
              // 收口闭包捕获本次 value 与 before（不能事后靠 this.text 反推）。
              // ★ 收口不变式 = 附件与原文**恰有其一**（settlePastedText 单源判定）：真机实测
              // 反馈「粘贴长文本没生效」后复查——preventDefault 是可选成员、拦不拦得住原生插入
              // 属平台行为，旧版回退闭包默认「拦住了」而无条件追加，两者不一致时就会重复。
              // 拦住时 landed 恒假、行为与旧版逐字等价；拦不住时由收口把重复纠正回来
              .onPaste((value: string, event: PasteEvent): void => {
                const threshold: number = clampPasteThreshold(this.pasteThreshold);
                const intercept: boolean = shouldPasteAsFile(value, this.pasteAsFile, threshold);
                // 判定留痕（2026-09-23 自检轮加，用户不可见）：真机报「粘贴长文本没生效」时这四个
                // 事实就是判别面——onPaste 有没有触发、当时的开关与阈值各是多少、判定结果是什么
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
              // 输入法通路拦截（2026-09-24 决明真机情报）：经**系统键盘剪贴板**上屏的长文本不触发
              // onPaste（实测长按系统粘贴菜单能转、键盘剪贴板不转）——那条路走的是输入法输入通路。
              // 官方 onWillInsert 正是该通路的 will 钩子（API 参考：在将要输入时触发，返回 false 即
              // 拦下本次插入；设备实读输入法 = 系统自带 com.huawei.hmos.inputmethod，落在该 API
              // 「仅支持系统输入法输入的场景」覆盖内）。判据与 onPaste **同一个**
              // shouldPasteAsFile：单次插入达到阈值即转附件——普通打字每次 1~2 字恒不过线，
              // 输入法剪贴板与语音输入等批量上屏会过线。
              // ★ 去重：**本次受理窗口内**（onPaste 起到它的收口回调止）同一段文本放行——防
              // preventDefault 未拦下时两条通路各转一次，放行后的插入由 onPaste 的收口清理；
              // 窗口在收口处复位（见字段注释——只活一次受理）
              // ★ 拦下即「文本没落框」→ 收口闭包按 landed=false 走：转成则不留、未成则追加回框
              .onWillInsert((info: InsertValue): boolean => {
                const inserted: string = info.insertValue;
                const threshold: number = clampPasteThreshold(this.pasteThreshold);
                const intercept: boolean = shouldInterceptInsert(inserted, this.lastPasteHandled,
                  this.pasteAsFile, threshold);
                // 判定留痕（用户不可见，同 onPaste 一处）：输入法通路有没有走到、当时四个事实
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

            // 发送·停止键（收起态在文本行内；展开态移入工具行——两态各实例化一处）
            if (!this.expanded) {
              this.SendOrStopKey();
            }
          }
          .width('100%')
          // 图标键底对齐：多行加高后贴胶囊底部（单行时按钮靠下边距居中，观感不变）
          .alignItems(VerticalAlign.Bottom)

          // 工具行（★ 2026-09-09 三改：恒存在 + 高度 0/44 切换，不再用 if 条件渲染——决明
          // 复验「仍抽动」后定位：条件渲染的出现/消失**不参与布局动画**，高度瞬跳会甩动同
          // 浮层的相邻元素；改高度动画后与浮层内 chip 行同机制。
          // 高 44；内缩 7/7/1 使键中心与胶囊圆角弧心重合，见 TOOL_KEY_INSET（水平走本行
          // padding、垂直走键与文字外边距））
          // 内容：＋ 键 | 上下文用量圆环键（2026-09-17，拍板 P1 落点——＋ 与模型名之间）|
          // 当前模型名（只显示不可点——模型切换入口在标题栏「切换模型」键）| 全屏输入键 |
          // 发送·停止键。
          // ★ 2026-09-09 查证结论（决明「收起只淡出试下 + 为何不生效」）：本行的**出场**效果
          // 实际不可见——胶囊容器 `clip(true)` 且不设高度（内容自适应），删行后容器高度回缩、
          // 裁剪区同步缩小，被裁掉的删除动画看不见（官方 FAQ faqs-arkui-477 原文实锤：「clip 为
          // true 且有裁剪效果，因此被裁剪的删除动画不可见」；即决明观察到的「收起 = 高度原路回」）。
          // 故 `asymmetric(进场, 纯淡出)` 已回退为对称形态——出场纯淡出在此布局无任何可见差异
          //（死配置）。要真做出「只淡出」须另立设计（转场期间撤 clip / 行高动画等），本期不做。
          Row() {
            this.AddKey()
            this.ContextRingKey()
            Text(this.modelLabel === '' ? '未选择' : this.modelLabel)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              // 垂直内缩同键：文字中心与键中心同一水平线（距行顶 19 = 距胶囊底 25）
              .margin({ top: TOOL_ROW_TOP_INSET, bottom: TOOL_KEY_INSET })
            this.FullscreenKey()
            this.SendOrStopKey()
          }
          .width('100%')
          .height(this.expanded ? TOOL_ROW_HEIGHT : 0)
          // 高度收缩时裁剪内容（否则 0 高容器内的键仍可见）；透明度随高度同步淡入淡出
          .clip(true)
          .opacity(this.expanded ? 1 : 0)
          // 水平内缩 = 与胶囊圆角同心（见 TOOL_KEY_INSET）：左右 7 使键中心距侧边 25 与弧心同列；
          // 垂直内缩（顶 1 / 底 7）由键与文字的外边距下发——行高收起态归 0 时，行自身的垂直
          // padding 会把最小高度撑到 8vp（真机实测收起态胶囊被撑高、两键失中）
          .padding({ left: TOOL_KEY_INSET, right: TOOL_KEY_INSET })
          // 增量实测（见 reportInset）：展开/收起动画期间逐帧回写，与浮层实测同源同步
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            this.toolHeight = newArea.height as number;
            this.reportInset();
          })
        }
        .width('100%')
        // 半圆圆角 = 单行高一半（自绘外形，非官方固定值，可调）；加高后半径不变自然过渡
        .borderRadius(INPUT_CAPSULE_RADIUS)
        .clip(true)
        // 胶囊双态（2026-09-03 开关体系）：实底态 = 官方灰阶实色（app.color.comp_fallback_gray
        // 深浅分治、不透明——原官方语义色带透明度可读性差，2026-09-03 决明反馈后换；零实时
        // 渲染零卡顿——backgroundEffect 真机卡顿已撤销，头注释有完整三轮实验记录）；
        // 光感态 = REGULAR 系统材质（REGULAR 基准档随沉浸光感总档偏移，2026-09-12
        // 自 THIN 统一）。内层 TextArea 保持透明底（胶囊视觉由本层承担）
        .backgroundColor(this.contentFallback ? $r('app.color.comp_fallback_gray') : Color.Transparent)
        .systemMaterial(this.contentFallback ? uiMaterial.Material.empty :
          resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, false))
      }
      .width('100%')
      .padding({ left: this.expanded ? 0 : INPUT_COLLAPSED_INSET,
        right: this.expanded ? 0 : INPUT_COLLAPSED_INSET })

      // ── 合规提示行（2026-09-03 决明指令「内容由 AI 生成」类语句；文字源 = 2026-09-10
      // 立的 common/AiDisclosure——AI 标识「界面提示/复制/导出」三处同源）：输入胶囊下方一行
      // 小字（居中，PrivacyPolicyPage 合规口径同源）；平时常显 = 输入胶囊整体适当抬高；
      // ★ 键盘弹起（keyboardOn）藏字不塌位——文字换等高空占位镜像（同
      // COMPLIANCE_HINT_HEIGHT），浮层总高恒定：输入框零位移（无闪动、不因塌陷被键盘
      // 盖住），键盘收起恢复文字
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
    // ★ 2026-09-03 真机反馈「整体略下移」：padding bottom 8 → 0（提示行底贴浮层底）。
    // ★ 2026-09-09 键盘态底部留白归本组件（决明「现在不会遮挡，但抬起过高了，底部与键盘
    // 间距很大」）：常态 = 页面注入的 bottomPad 全量避让（08-29 定稿「输入栏不压手势条」+
    // 悬浮页签让位）；键盘升起时置 0——键盘已覆盖底部系统区（手势条/页签均不可见），注入值
    // 此时纯属冗余，正是间距来源。切换随键盘事件在 animateTo 内完成（见 onKeyboardHeight），
    // 高度变化经 onAreaChange 实测自动联动 contentEndOffset
    .padding({ left: 16, right: 16, bottom: this.keyboardOn ? 0 : this.bottomPad })
  }
}
