// 聊天页配色公共件（自 dshinhm common/Theme.ets 按需随迁，只取消息流各件实际消费的函数）：
// 卡片背景/边框按深浅色分治；标题/描述色直接用官方语义色资源（深浅色自动切换）。
// ★ 行内操作按钮官方形制（领导拍板「接官方形状与光感，均官方灰底即可」，规范同源
// AGENTS.md「行内按钮官方形制」条）：基线写法 =
// Button(label).backgroundColor($r('sys.color.comp_background_tertiary')).stateEffect(true)
//——形状/字号/字色/按压光感全走官方默认，**禁自绘 borderRadius/fontSize/fontColor** 覆盖
// 官方形制。行内操作键（含图标钮）现走 resolvedButton 四件套（fontColor/Bg/
// systemMaterial/stateEffect，见 common/ImmersiveLevel.ets 胶囊按钮光感簇；无光感档自动
// 回退本条官方灰底）；主操作键（「保存」类）primary=true 官方强调蓝 + 恒白字。
// ★ 排除项（领导澄清）：**选项类 chips 不适用本条**——模型能力多选等是「选项」非功能按钮，
// 照 ModelCapsCard 范式（Text 圆角底 + 未选淡蓝 / 选中实底强调蓝 + 无 stateEffect）。
// ★ 拍板例外：**提示词变量插入卡**（SystemPromptPage/AssistantPromptPage 变量区，「点击
// 插入」入口语义）——官方胶囊按钮（.type(Capsule) + 显式实色，现 = Theme.fallbackBlueBg
// 随档叠 alpha，与 chip 族同底），**不接沉浸光感**（不叠 systemMaterial——Material.empty
// 也属「已配置」，历轮真机四连压实锤）；字色 = selectChipTextColor(false)（与未选 chip 同源）。
// ★ 卡外实心件白底（决明拍板「把背景上的灰底键改为白底，卡片内不动」+「变量chip 和模型
// 选择半模态搜索框也是灰底吧？改白」）：内容区**实心件**（次钮 / 半模态面板搜索框）的浅色
// 底按**所坐的面**分叉——坐**非白卡面**（页底 / 半模态面板面 / 卡外区）= 白底
//（Theme.fallbackOffCardBg）；坐**白卡面**（cardBg）= 官方灰阶实色基（Theme.fallbackGrayBg）
//——两族均随卡底透明度档位叠 alpha，「卡片内不动」指基色分叉判据不变。主钮与四件套其余
// 三件、分段胶囊均不受本条影响；深色底（全屏编辑页舞台 #121212）不适用。实现单源 =
// ImmersiveLevel.fallbackButtonBgOffCard + 同判据直取 Theme 函数；判据与消费点见
// docs/规范-行内按钮与光感.md §1。GroupSettingCard 设置页组卡件（官方「已配对设备」卡
// 实测规格复刻）见 components/GroupSettingCard.ets 头注释。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY, clampCardAlphaLevel } from './AppPreferences';

// 组卡/回退自制卡统一宽度（dshinhm 定稿 = 屏宽 −32vp，左右 16vp——卡左缘与标题栏主标题左缘
// 对齐；官方 12vp 边距版本卡过宽已废，勿再试）。官方 HDS 行卡挂 .width() 不生效，本常量只
// 用于自制卡与需对齐卡宽的非 HDS 元素
export const CARD_PANEL_WIDTH: string = 'calc(100% - 32vp)';

// 列表卡片组纵向间距（dshinhm 定稿 = 10vp，官方《设置列表卡片样式》示例 List({ space: 10 })）。
// 卡片间距一律由容器 space 管理，禁止对卡片自身挂 .margin() 管间距
export const CARD_SPACING: number = 10;

// 卡片圆角（全应用卡体单一来源，决明拍板「卡片圆角统一改大到 20」）：消费面 = 自绘卡壳
//（CARD_PANEL_WIDTH + cardBg 一族）、卡内按压蒙层、拖拽 ListItem 条目层、HDS 卡参数
// cardBorderRadius。红线 = 蒙层圆角与卡体圆角同值（单源后天然同值）。小元件各有登记档位
// 不随本常量：键值井 12 / 宫格瓦片 12 / 价格瓦片 14 / 只读井 10 / 状态徽标 6 / chips 14~18 /
// 横幅与半模态方卡 20 / 浮层 20。沿革：16 →（18 曾抬同轮撤回）→ 统一 20 单源化——字面量
// 全部改引用本常量，回退只需改本值
export const CARD_RADIUS: number = 20;

// ── 卡片层级纵向间距三档（规范条文 = docs/规范-列表卡片与组卡.md「卡片层级纵向间距」节，
// 改值先读该节）──
// 板块与上一板块（或页内上一独立块）的间距：20vp。分组要可辨，板块间距须明显大于板块内
// 卡间距（接近性原则 ≥2 倍）；20 = 官方分组列表 FAQ 示例 List({ space: 20 }) 值。消费形态 =
// 承载多个板块的页面级 Column/List 的 space；板块内卡间仍用 CARD_SPACING（页面级
// Column({ space: SECTION_GAP }) → 板块容器 Column({ space: SECTION_HEADER_GAP }) 内再包
// Column({ space: CARD_SPACING }) 堆卡，SettingsPage 版式）
export const SECTION_GAP: number = 20;
// 板块标题（SectionHeader 或同规内联板块标题）与下方首卡的间距：6vp——小于卡间距，标题
// 才读作「属于下方这组卡」。消费形态 = 板块容器 Column 的 space
export const SECTION_HEADER_GAP: number = 6;

// 消息气泡行内边距（dshinhm 定稿值；列表层已左右各 12）：近侧 4（绝对 16）、远侧 20
//（绝对 32）——用户行 near 在右 / far 在左（右对齐镜像）。★ 决明「助手的右边距缩短与
// 左边距统一」后助手侧三件（消息泡 / 思考块 / 工具卡）两侧同取 near 4/4 对称，far 现只
// 用户侧消费（用户消息泡左 + 附件泡左）。自 ChatMessageItem 上收 Theme：附件独立气泡与
// 消息泡两件同源消费（防两处漂移）
export const BUBBLE_PAD_NEAR: number = 4;
export const BUBBLE_PAD_FAR: number = 20;

// 用户消息泡宽度上限（决明「缩短为原60%左右」→「再增宽30%左右」→ 78%）：行内距不动故
// 右缘贴位不变，收窄/放宽全落在左缘；百分比基准 = 同一父容器（消息泡所在 Row 的内容宽），
// 与列表层左右 12vp 无耦合。
// ★ 消费形态 = **定宽壳的显式宽度**（见 ChatMessageItem 用户分支注释）：不挂气泡自身
// constraintSize——那只是测量后的尺寸钳制，泡内 Markdown 段落仍按父行全宽排版，长内容
// 会顶出泡右缘；移作外层壳宽即成为子组件的测量约束，段落按上限换行、高度自然增长
export const BUBBLE_USER_MAX_WIDTH: string = '78%';

// 附件泡与消息泡两泡间距：6vp < 消息间距离 CARD_SPACING(10)——小于消息间距离，两泡才成组
// 可辨；观感不适只改本常量
export const ATTACH_BUBBLE_GAP: number = 6;

// 会话轮间距（决明「用户消息和助手消息整体的间距拉大一些」+「上比下大」+「每一轮用户
// 消息和上一轮的助手消息间距再大一点」+「轮间距再大点」，终值 30）：
// · `CHAT_ROUND_SPACING` = **上一轮助手 → 本轮提问**（用户消息项的上距），30vp；
// · `CHAT_ASK_GAP` = **本轮提问 → 下一条助手消息**（用户泡下距补足，见下），14vp。
// 判据 = 两个方向不该等距：提问属于**新一段对话的起点**，前面留白大才读作「另起一题」；
// 回答紧跟提问，14 已足够，再大就把一问一答拆成两张卡（旧值两向同为 CARD_SPACING(10)，
// 轮界完全读不出来）。层级 10（轮内段间）/ 14（问答间）/ 30（轮间）分明。
// ★ 落码形态：上距直接挂用户泡 margin top；下距因助手项自持 CARD_SPACING(10)，用户泡
// margin bottom 只补差额 `CHAT_ASK_GAP - CARD_SPACING`（相邻 ListItem 的 margin 相加）。
// ★ 只动用户消息这一处：轮内「思考卡 → 正文」仍由助手项自持的 CARD_SPACING 承担，勿套本值
export const CHAT_ROUND_SPACING: number = 30;
export const CHAT_ASK_GAP: number = 14;

// 消息气泡圆角单源：用户泡 / 助手泡 / 思考半泡 / 工具卡 / 附件独立气泡五处同值（同泡化拼接
// 靠两半各自切直角配合，不改半径值；附件气泡同屏相邻同底色，圆角须同步演化，而
// AttachmentBubble 不能反向 import ChatMessageItem——反向即模块环，故并入本常量单源）。
// 现值 = CARD_RADIUS（20，决明「全部一起改」）——气泡族与卡片同值，卡圆角调整本值随动；
// 若未来气泡需独立回档，在此拆回字面量并登记
export const BUBBLE_RADIUS: number = CARD_RADIUS;

// ── 过程段步骤几何（过程壳 ChatProcessSegment 单源：图标列 + 竖线 + 内容列 + 步骤标题行）──
// 线色不设常量——恒走 cardBorderColor(appColorMode) 单源函数（与卡内分割线同色同源，
// 深浅色自动跟随，禁硬编码色值）。
// 步骤行左 gutter 宽（图标列 + 竖线通道；图标与线均水平居中于本列——图标中心 = 线位置）
export const CHAIN_GUTTER_WIDTH: number = 28;
// 竖线宽（每行画各自线段、相邻可见步骤线段在行缝处相接成视觉连通的长线）
export const CHAIN_LINE_WIDTH: number = 1;
// 步骤图标尺寸（统一档；思考 lightbulb 与工具三分支同用）
export const CHAIN_STEP_ICON_SIZE: number = 16;
// 图标垫底遮罩外扩（制造图标处断线观感，KEL 同手法）：图标外再包一层 cardBg 底的内距，
// 遮罩半高 = 图标 ÷2 + 本值 ×2÷2 —— 上下线段以此为界，禁各自算一套
export const CHAIN_ICON_MASK_PAD: number = 2;
// 统一步骤标题行高（vp；＝工具头行原值上收——思考标题行随形同值，图标中心 = 本值 ÷2，
// 两行种标题左沿/图标中心/触控高度自此同源；官方触控区最小尺寸线以上）
export const CHAIN_STEP_ROW_HEIGHT: number = 48;
// 图标中心（行顶起算，vp）= 标题行高 ÷2：竖线上下两段的分界与图标遮罩中心同用
export const CHAIN_STEP_ICON_CENTER: number = CHAIN_STEP_ROW_HEIGHT / 2;
// 图标遮罩上沿留高（vp）= 图标中心 − 遮罩半高（图标 16÷2 + 遮罩外扩 2 = 10）：图标层上内距
export const CHAIN_STEP_ICON_TOP: number =
  CHAIN_STEP_ICON_CENTER - (CHAIN_STEP_ICON_SIZE / 2 + CHAIN_ICON_MASK_PAD);
// 步骤标题行/段控制行局部按压圆角（vp）→ **定义在 SEGMENT_PRESS_INSET 之后**（同心式取值依赖
// 它；ArkTS 模块级 const 按书写顺序求值，提前引用即 TDZ）——见下方「蒙层同心笔」块

// 段卡行内容距卡缘内距（vp）：左右 8——使步骤轨道（图标列中心 = 本值 + 28÷2）落上正文首字
// 中心（决明「让竖线与正文首字的中心对齐」；右侧同值收边）；上下 4 使段首尾步骤标题行居中
// 不虚。语义改判：本值不由卡体 padding 承担（卡体 padding 改挂 SEGMENT_PRESS_INSET——蒙层
// 贴缘），改作「行内容距卡缘内距」的承载量——实现 = 卡体 padding(4) + 行内容补距
// SEGMENT_ROW_CONTENT_PAD(4)；轨道算式与全部内容坐标逐字未动
export const SEGMENT_PAD_H: number = 8;
export const SEGMENT_PAD_V: number = 4;
// 段卡按压蒙层内距（vp；决明「点击蒙层离边距过大，参考设置页组卡」）：蒙层（步骤标题行/
// 段控制行的透明 Button）距卡缘四缘均匀本值（上下由 SEGMENT_PAD_V 同值 4 承担）——
//「蒙层悬浮露白 4」组卡同款（先例 GroupSettingCard EntryRow：行缩进 4 + 蒙层圆角 = 卡圆角）
export const SEGMENT_PRESS_INSET: number = 4;
// ★ 蒙层同心笔（决明「部分消息点击蒙层不符卡片规范，间距/圆角不统一」→ 口径拍板：
//「同心 16」+「行缝脱开」）：蒙层圆角 = 卡体圆角 BUBBLE_RADIUS − 蒙层内距
// SEGMENT_PRESS_INSET（20 − 4 = **16**），与「蒙层距卡缘 4」配对 ⇒ 两弧同心，四缘露白恒 4vp。
// 旧值 = BUBBLE_RADIUS 同值 20 两病齐发：①**弧不同心**——圆角同值却内缩 4，直边露白 4vp、
// 45° 对角露白 5.66vp，四角白边粗细不均；②**形制分裂**——段控制行高 40 圆角 20 = 恰半高
// 纯胶囊，步骤标题行高 48 圆角 20 = 圆角矩形，同卡相邻两行按下去一个胶囊一个方块。
// 同心式两条同时消：两行都落在「圆角矩形 + 四角均匀露白 4」，卡圆角调整本值随动（单源不变）。
// 钉守 = assert-chat-display 333 组（同心式在场）+ ui-shape 312 / feature-domain 138（使用面在场）
export const CHAIN_STEP_PRESS_RADIUS: number = BUBBLE_RADIUS - SEGMENT_PRESS_INSET;
// 段内行缝（vp；蒙层同心笔同轮立）：相邻两行按压蒙层的上下间隙——控制行（收起 / 展开更多 /
// 摘要条）此前**零缝**贴住下方首个步骤标题行，按住任一行时蒙层像一张悬在卡中间的独立小卡。
// 本值 = 步与步之间既有缝值（ChatProcessStep 内容列 padding bottom 同取本值，单源），三处
// 行缝自此同档。**只加行缝不加蒙层内缩**：蒙层仍满行高（40 / 48），触控区与行内容垂直位置
// 逐字不动（图标中心仍 = CHAIN_STEP_ICON_CENTER 24，竖线分段算式零位移）；若改为「缩蒙层
// 高度」取值，内容会随蒙层各偏 1vp、轨道断轴（方案阶段已排除）
export const SEGMENT_ROW_GAP: number = 4;

// 段卡行内容补距（vp）= 行内容距卡缘内距 SEGMENT_PAD_H − 蒙层内距 SEGMENT_PRESS_INSET：
// 蒙层收窄 4 后，行内容（控制行符号列/标题行图标列/思考与工具正文列）以本值回添复位——
// 轨道与全部文字左沿零位移；竖线 offset 同以本值为前缀（轨心 = 卡缘 4+4+gutter÷2 恒 22）。
// 行内各内容内距写法 = SEGMENT_ROW_CONTENT_PAD + 原值（禁裸写原值——漏补即内容左移 4，
// 333 组结构链钉守）
export const SEGMENT_ROW_CONTENT_PAD: number = SEGMENT_PAD_H - SEGMENT_PRESS_INSET;
// ── 步骤内容列文本左/右内距（真机四轮收窄至安全下限，终值 4 / 8）──
// 由来：原实现内容列自 x=0 起排，标题/正文文字压在图标列之下（一轮真机实锤「文字压图标」）；
// 修复 = 内容列自 gutter 右缘起排且文本左距取本左值。三轮「竖线居中」（竖线到卡左缘 ≈ 标题
// 到竖线，两距相等 ⇔ 本值 = 卡内距）后，四轮「更小优先」**压至安全下限**：
// 标题到竖线 22 → 18，文本与图标列净距（文本左沿 − 图标遮罩右缘）= **恰 8vp**（到图标实墨约
// 11vp）——此为下限：再小即入图标列呼吸区 = 一轮「文字压图标」缺陷家族，不得擅动；再收须先
// 缩图标列/gutter 本体并经决明拍板。**「竖线居中」两距自此 22 / 18 不再严格相等——决明以
//「更小」优先**，方向关系（标题到竖线 ≤ 竖线到卡左缘）保留。
// 断言 333 组以两条关系钉守：①方向关系（本值 ≤ 卡内距 + 2vp，即标题不得比竖线离卡左缘更远）；
// ②安全下限（文本左沿 − 图标遮罩右缘 ≥ 8vp，防「再小」回落重叠缺陷）。右值同时是段级控制行
// 的右内距（内容列 / 控制行 / 标题行左沿三处同一组值，现均以 SEGMENT_ROW_CONTENT_PAD 为
// 前缀补距）
export const CHAIN_STEP_TEXT_PAD_L: number = 4;
export const CHAIN_STEP_TEXT_PAD_R: number = 8;
// 段卡行内容右内距（vp）= 行内容补距 + 文本右距：标题行 / 段控制行 / 正文列三处右内距同源
export const SEGMENT_ROW_PAD_R: number = SEGMENT_ROW_CONTENT_PAD + CHAIN_STEP_TEXT_PAD_R;
// 段卡正文/思考内容列左内距（vp）= 行内容补距 + gutter + 文本左距：工具正文列与思考两态视窗
// 同源（标题行/控制行左内距 = SEGMENT_ROW_CONTENT_PAD 裸值——首列是图标/符号列本身）
export const SEGMENT_BODY_PAD_L: number =
  SEGMENT_ROW_CONTENT_PAD + CHAIN_GUTTER_WIDTH + CHAIN_STEP_TEXT_PAD_L;

// ★ 消息流布局诊断开关（构建期常量，装机侧诊断走构建期开关——BrowseWeb.BROWSE_DEBUG 一族
// 先例）：true = 消息流各行根容器画 1vp 彩色描边（thinking 红 / tool 蓝 / assistant 绿 /
// user 橙）+ ChatPageContent 逐项 hilog 实测行高（tag ChatLayoutDebug）——一张截图 + 一段
// 日志即可判定「板块间空白」归属哪只行型。交付构建恒 false 零行为差异；诊断轮临时置 true
// 出包，取完证据改回
export const CHAT_LAYOUT_DEBUG: boolean = false;

// ★ 消息主列表底锚双态开关（构建期常量，形制同 CHAT_LAYOUT_DEBUG 一族）：true = 主 List 挂
// stackFromEnd（官方 API 19+ 聊天列表范式——布局自身从底端起算，贴底不靠事后滚动补偿），
// ChatFollowController 弹簧补偿链整体短路（三类主动滚动照旧：用户回底恢复 / 发送
// forceToBottom / 进页 jumpToBottomAt 校正链）；false = 官方默认值（属性等同未挂），贴底回到
// 补偿链 = 旧路径逐字节保留。**这是回退承诺的实现面**：观感异常时改本常量为 false 重建即回
// 旧观感（双态对照也用它）
export const CHAT_STACK_FROM_END_ENABLED: boolean = true;

// ★ 进页暴露窗口（S4）及其上的 U2 退场暂停、U4 步长自适应已整域退役：一条消息 = 一个
// ListItem，行级窗口拆不开单条长消息内部的块树；超长行改由「进页收起」处置。历史文档提到
// 这三个常量属已退役机制，勿重新引入。

// ★ 装载链退出取消闸（kill-switch，单源编译期常量）：true = ChatPageLoadCtrl 页面寿命取消闸
// 生效——退出会话页后，loadHistory 历史装载残余链与补挂链（用量账本/附件简报/推荐问题）各
// 检查点早退，省掉退页后仍在跑的装配/投影/重建白做段（置闸点 = ChatPage.onBackPressed
// 及时位 + 生命周期 leave 兜底位双置；复位点 = onReShown 转场取消回显）；false = 检查点全部
// 直通 = 现行「防写不防算」行为逐字同。**闸只省算不防写**（防写职责仍在代次/会话/销毁三问
// 守卫）；取消对象 = 装载残余链与补挂链，流式链/续流/预载链零接触（预载自有取消口）。
// **真机验收异常时回退口 = 本常量一行**。闸语义细则单源 = ChatPageLoad.ets 头部取消闸注释
export const HISTORY_LOAD_CANCEL_GATE_ENABLED: boolean = false;

// ★ 进页锚初值恒锚开关（kill-switch，单源编译期常量；2026-11-25 侧栏点卡漏帧与新会话
// 滑不动笔自「锚初值非空判据」NONEMPTY 更名）：true（默认开）= ChatListAnchorJudge.reset
// 锚初值恒真（含空表——空表底锚/贴顶视觉无差；新会话首建即 stackFromEnd，流式期零翻档）；
// false = 回 COUNT_GATE(24) 条数闸旧判据（A2 回退口原样）。**A2 专属回退口 = 本常量一行**：
// 真机验收形态异常时改 false 重建即回旧判据；与总开关 CHAT_STACK_FROM_END_ENABLED 的分工
// ——总开关连 ≥24 现状一起关（贴底回补偿链旧路径），仅红线事故用，不作本单元回退口
export const CHAT_ENTRY_ANCHOR_ALWAYS_ENABLED: boolean = true;

// ★ 请求历史与 UI 窗口解耦总开关（kill-switch，单源编译期常量）：true（默认开）= 发给模型的
// 历史按「助手上下文条数 + 模型窗口 token」双闸从库独立读取（读口 readRequestHistoryRows +
// 预算 RequestHistoryBudget + 编排 ChatRequestHistoryCtrl），UI 窗口退纯渲染；发送 / 重试 /
// 离屏 web / 用量面板 / 压缩选段五处同源。false = 全部走旧链（allMessages 窗口 + 组装内二次
// 截取），行为逐字节回旧。**红线事故回退口 = 本常量一行**；读口性能超标处置见 BLOCKED
//「请求历史与UI窗口解耦」节，待真机复测拍板
export const REQUEST_HISTORY_DECOUPLE_ENABLED: boolean = true;

// HDS MINI 标题栏官方默认高度 56vp（官方设计指南「窗口框架」）。用途：内容区延伸到标题栏
// 背后时，滚动内容顶部留白的组成项（titleBarInset，见 nav/HomeNavigation.ets）
export const TITLE_BAR_MINI_HEIGHT: number = 56;

// 标题栏渐变模糊蒙层向下超出标题栏的高度（官方默认 32vp，dshinhm 真机反馈偏大调小为 16 并
// 在标题栏 maskExtraHeight 显式同步——两者必须一致，要调两处同改；与 titleBarInset 共用
// 本常量保证同源）
export const TITLE_BAR_MASK_EXTRA_HEIGHT: number = 16;

// ── 标题栏中央区宽度（39% / 130~170vp，360vp 屏 = 140.4）──
// 单源 = 一级页「对话」页签顶部分段胶囊（TabMoreMenu.ChatTabTitleBar）与聊天页新会话态
//「模型|思考」胶囊共用（2026-11-15 截断修复笔起有标题态两行标题**不再适用本组**——胶囊专档
// 只保热区可点不保标题显示，有标题态走避让全宽 + 对称内收 64，见 ChatTitleBarOverlay
// TITLE_TEXT_ZONE_INSET）。右侧空间来自「双键胶囊 → 单圆键」释放的 52vp；
// 几何账（左避让 64 = 返回键 / 右避让 56 = 更多键 40 + end padding 16）：360 → 区右缘
// 250.2、余 53.8vp；320 窄屏触下限 130、右缘 225、余 39vp（最紧）；400 = 156；约 436vp
// 起封顶 170（平板）。上限守「不超双键胶囊两倍」口径 184。改本组常量两处同步，禁各写一份。
export const TITLE_CENTER_ZONE_WIDTH: string = '39%';
export const TITLE_CENTER_ZONE_MIN_WIDTH: number = 130;
export const TITLE_CENTER_ZONE_MAX_WIDTH: number = 170;

function isDark(mode: number): boolean {
  return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
}

// ── 卡底透明度阶梯（卡底透明度全局调节笔单源层）──
// index = 档位（L0 最透明 → L4 不透明）。**唯一调参处**：真机观感验收后只改本双表常量，
// 结构与其余面零改动。浅深双表成对给值（视觉色板规范），消费侧禁散写 hex。8 位 #AARRGGBB
// 字符串 = 项目 idiom，天然避 0x00 数字形态借位坑（faqs-arkui-245）。
// ★ 表元素 = 纯两位 alpha hex（**不带 # 前缀**，'#' 只在 alphaHexPrefix 拼装处补一个——
// 带 # 会拼出 ## 双井号非法串，真机实锤 = 自绘卡透明 / Button 回落默认蓝 / HDS 卡回落默认
// 白、全站不随滑轨）
const CARD_ALPHA_LIGHT: string[] = ['80', '96', 'B0', 'D4', 'FF'];
const CARD_ALPHA_DARK: string[] = ['66', '84', 'A8', 'CC', 'FF'];

// 卡底 RGB 基色（浅 #FFFFFF / 深 #1C1C1E——现值不变，alpha 化改造只加前缀）
function cardRgbHex(mode: number): string {
  return isDark(mode) ? '1C1C1E' : 'FFFFFF';
}// 当前档位现读（缺省读键 = 非响应式，进程内哈希查表微秒级，先例 = ImmersiveLevel 材质取色链）：
// 档位变化的重渲由即时面订阅组件的刷新驱动，本函数只在构建时被调用一次
function currentCardAlphaLevel(): number {
  return clampCardAlphaLevel(AppStorage.get<number>(PREF_CARD_ALPHA_LEVEL_KEY) ?? CARD_ALPHA_DEFAULT);
}

// alpha 前缀拼装（cardBg 族与键底色族共用单源）：'#' + 当前档 alpha 两位 = 产出串前三字符；
// **'#' 只在本函数体内出现一次**（alpha 表元素不带 #，双 # 即真机三病象根因，见双表注释）；
// level 缺省 = 重建层读键，即时面组件显式传 this.cardAlphaLevel 建立刷新依赖
function alphaHexPrefix(mode: number, level?: number): string {
  const lv: number = level !== undefined ? level : currentCardAlphaLevel();
  return '#' + (isDark(mode) ? CARD_ALPHA_DARK[lv] : CARD_ALPHA_LIGHT[lv]);
}

// 卡片背景：浅色白底；深色官方语义深底 #1C1C1E。★ 双参化：level 缺省 = 体内同步读档位键
//（重建层零改动自然取新档）；即时面组件显式传 this.cardAlphaLevel（@StorageProp 订阅建立
// UI 依赖，档位变化属性级刷新）。缺省参 L4 = '#FF' + RGB，与旧 6 位返回值视觉等同
export function cardBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + cardRgbHex(mode);
}

// 卡底渐隐终点：恒 #00 全透明（与档位无关、与 RGB 源同源）——渐隐区间起点随档、终点恒透，
// 区间观感随档连续缩放（拼串上收单源：cardBg 返回 8 位后 substring 拼法会产出 10 位非法串）
export function cardBgTransparent(mode: number): string {
  return '#00' + cardRgbHex(mode);
}

// 用户消息泡底色（色值自资源迁函数——浅 #DCE8FF / 深 #2E4A73 双档原值不动，随卡底透明度
// 档位叠 alpha；基色与 statusBadgeBg 强调档淡蓝同值系独立资源条目，见 docs/规范-视觉色板
// 与徽标.md 用户气泡行）
export function chatBubbleUserBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '2E4A73' : 'DCE8FF');
}

// ── 键底色族随档叠 alpha（基色 = app 资源 comp_fallback_gray / comp_fallback_off_card /
// comp_fallback_blue 现值迁移，三资源条目已同笔退役防双源漂移）──
// 与卡底同一档位键同一 alpha 双表（ImmersiveLevel 键族 bg 函数实底分支 + 直取件消费；mode
// 由调用侧传或键族函数体内现读 AppStorage——resolvedButtonMaterial 先例）。
// ★ 主钮官方强调蓝实底**不随档**（收口动作强调锚点 + 恒白字对比不受透明度稀释）——本族只
// 覆盖灰 / 卡外白 / 淡彩蓝三底
// 灰键底（卡内次钮 / 分段胶囊背板与返回键 / 输入条键；浅 #E6E8EA / 深 #3A3A3C——官方灰阶
// 实色拍板原值）
export function fallbackGrayBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '3A3A3C' : 'E6E8EA');
}

// 键值井底：与 fallbackGrayBg **分开单源**——那个是全站灰键底（按钮/面板搜索框），井是卡内
// 的大面积容器，同一灰度在大面积上会读作「脏灰」（旧值浅 vs 白卡偏闷、深 vs 卡发白）；井取
// 更浅更干净的一档（浅 #F1F3F5 = 页底同源、「卡上挖了一块页底」；深 #2A2A2C），边界靠
// 0.5vp cardBorderColor 描边交代，不靠灰度硬撑。判据与形态单源 =
// docs/规范-列表卡片与组卡.md §4.12
export function wellBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '2A2A2C' : 'F1F3F5');
}

// 卡外实心件底（页底键 / 半模态面板键；浅 #FFFFFF 比浅面亮一档才显形——卡外白底拍板口径
// 原值；深 #3A3A3C 与灰键同值深色零感知。★ 2026-10-31 面板搜索框迁标题栏下方带后恒光感，
// 不再消费本底）
export function fallbackOffCardBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '3A3A3C' : 'FFFFFF');
}

// 淡彩次级键底（推进型动作档；基色与状态徽标强调档 / 用户气泡同值系——浅 #DCE8FF /
// 深 #1B2A4A，字色配对 comp_fallback_blue_fg 资源保留不动）
export function fallbackBlueBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '1B2A4A' : 'DCE8FF');
}

// ── 侧滑操作键配色（会话行左右滑露出的五键，2026-10-30 反馈轮 4 立；2026-10-31 收藏改蓝）──
// 治什么：五键原只有「强调蓝 ×4 + 警告红 ×1」两色，同排圆键分不出动作轻重。决明给了系统
// 录音 app 的侧滑键截图「用这种色系」——**三色原值直接取自该截图**（按色域阈值定位每个圆的
// 圆心与半径，再取 0.55~0.85 倍半径环带的像素众数，避开圆心图标与边缘抗锯齿）：橙 `#EC7023` /
// 黄 `#F4CF04` / 绿 `#64BA5C`；删除 = 系统警告色 `#E84026`（截图红实测 `#E83F28`，差 2/255
// 不可辨，故沿用系统 token 以保语义与深色适配）。★ 色值一律照抄，**不做「为可读性压深」的
// 二次调色**——上一版把黄压成 `#D19A00`、绿压成 `#3FA24C` 并自造青色，被决明判「颜色还是
// 不对」；参照图的观感本身就是答案。
// 分配（档位见 SessionSwipeKeys.keyTone）：重命名 0 橙 / 移动 1 黄 / 加密 2 绿。
// 右侧三键 = 橙 → 黄 → 红，正好复刻截图「橙黄红」的连续排布；左内侧 = 绿。
// ★ 收藏键不占本表（2026-10-31 决明「把左滑收藏键改成 HdsTab 选中时那种蓝色」）：走官方
// 语义色 `sys.color.ohos_id_color_emphasize`（HdsTabs 选中同源、深浅色自动随系统），在
// SessionSwipeKeys.keyBg 的 FAVORITE 分支一处取值——表内不再重复橙，四键也不会退回单一蓝。
// 删除不进本表，走系统警告红。
// ★ 白图标对比度：橙 3.0 / 黄 **1.5** / 绿 2.4 : 1——黄档最低（参照图本身就是白图标压在亮黄
// 上，观感偏飘但可辨）。若真机觉得黄键图标糊，**只把该档图标换深色**，不要动色值。
// ★ 深浅模式同值：键是「实底彩圆 + 白图标」，对比度只由键底亮度决定、与页面底色无关；
// 强开深色表等于多一份会漂移的副本，故本函数不收 mode 参（与相邻 fallback* 函数的差异点；
// 收藏键走资源、天然分深浅，不属本表口径）。
const SWIPE_KEY_TONES: string[] = ['#EC7023', '#F4CF04', '#64BA5C'];

export function swipeKeyToneBg(tone: number): string {
  const i: number = Math.max(0, Math.min(tone, SWIPE_KEY_TONES.length - 1));
  return SWIPE_KEY_TONES[i];
}

// 卡片边框：浅色黑 12% 细线、深色白 12%
export function cardBorderColor(mode: number): string {
  return isDark(mode) ? '#1FFFFFFF' : '#1F000000';
}

// 卡片标题色/描述色：官方语义色资源（font_primary/font_secondary，深浅色自动切换）
export function cardTitleColor(): Resource {
  return $r('sys.color.font_primary');
}

export function cardDescColor(): Resource {
  return $r('sys.color.font_secondary');
}

// 滑块滑轨色（「背景」页档位滑条消费）：半透明让底层沉浸光感材质透出（不透明会完全
// 盖住材质滤镜，官方属性冲突约束——dshinhm 定稿）
export function sliderTrackColor(mode: number): string {
  return isDark(mode) ? '#14FFFFFF' : '#0D000000';
}

// 菜单项分割线色（运行日志「更多」菜单消费）：浅色 = 官方默认黑 20%，深色材质菜单上不可见
// → 换白 20%（dshinhm 真机定稿）
export function menuDividerColor(mode: number): string {
  return isDark(mode) ? '#33FFFFFF' : '#33000000';
}

// ── 思考档位滑轨面板三枚（★ 2026-11-25 思考档位滑轨笔，单源 = 本文件；面板文件内零色值字面量）──
// ★ 三轮「去掉描边」：原 thinkingBlockBorder（关闭档灰描边）退役——官方 blockBorderColor
// 默认透明 / blockBorderWidth 默认 0，应用侧整支不写即官方无描边，不再需要应用侧色值。
// 末档（最右）轨道紫：thinkingTopTrackColor——★ 五轮起不再直接当 selectedColor，改为
// thinkingTopGradient 的**终点色**（决明「最高档能改为这种渐变吗」：整条蓝→紫）；非末档一律
// selectedAccentBlue。★ 2026-11-25 滑轨观感修笔（决明「原本要最大档时滑轨条为紫色，却做成了
// 白云圆外圈紫色，不要这样」）：当时撤渐变 + 撤白球紫描边，改为实色紫——本轮渐变回归时描边
// 已不存在，不会再出现「白球套紫圈」。★ 同日二轮（决明「紫略深点」）：紫族内各加深一档
//（浅 #A855F7 → #9333EA、深 #C9A6FF → #C084FC），色相不变，深色档仍保轨道上的可读对比。
export function thinkingTopTrackColor(mode: number): ResourceColor {
  return isDark(mode) ? '#C084FC' : '#9333EA';
}

// 末档（最右）轨道渐变（★ 2026-11-25 五轮，决明「最高档能改为这种渐变吗」——参考图为蓝→紫
// 横向渐变轨道）：只在滑轨末档作为 Slider.selectedColor 用。起点 = 普通档蓝、终点 =
// `thinkingTopTrackColor` 现深紫，渐变与两档语义天然接续；中点为紫罗兰过渡色，深色档提亮一档
// 保轨道上的白球/白字可读。
// · 作用域无歧义：末档填充 100%，引擎「铺满整轨再裁切」与「只铺选中段」两种口径结果一致
//（2293 节立项时已按此论证）。
// · Slider.selectedColor 的 LinearGradient 重载自 API 18（SDK slider.d.ts 实读），minSdk 26 恒可用。
// ★★ 2026-11-25 五轮修笔（真机「渐变色没生效、又变成正常蓝底」的根因）：组件颜色类属性
//（`selectedColor` / `trackColor` / `maskColor` 一族）要的是**原生 LinearGradient 实例**——
// 官方 FAQ 明确「类型应为 LinearGradient，而非通用属性 linearGradient 中的 LinearGradientOptions」，
// 写法 = `new LinearGradient([{ color, offset }, ...])`（SDK data_panel.d.ts 的
// `declare class LinearGradient { constructor(colorStops: ColorStop[]) }`）。首版传对象字面量
// `{ angle, colors }` 编译能过但引擎不认，整条渐变被忽略、回落默认强调蓝（即「正常蓝底」）。
// · 断点颜色一律用十六进制字面量（官方样例同形；Resource 形态断点不保证被引擎接受，防「非法
//   断点值 = 渐变失效」）；起点 #007DFF = 浅色 `sys.color.font_emphasize` 同值（与
//   selectedAccentBlue 浅档同值），深档 #7CB4FF 与 selectedAccentBlue 深档同值——改蓝请两处同改。
// · 类构造器无角度参数，方向取官方默认（横向轨道即左→右）；真机若见方向异常，回退口径 =
//   改回 `thinkingTopTrackColor` 实色紫（工单 = BLOCKED「思考档位滑轨面板 真机清单」第 2 项）。
// ★ 2026-11-25 五轮二修（决明「蓝紫渐变过渡更柔和一些，但紫色更明显一些」）：四段断点、
//   紫色提前到 35% 起显、65% 起进入深紫区——前半仍从强调蓝平滑过渡，后半以紫为主；断点不
//   等距（0 / 0.35 / 0.65 / 1）= 蓝区收紧、紫区放宽，过渡段更多落在中间色。
export function thinkingTopGradient(mode: number): LinearGradient {
  const stops: ColorStop[] = [
    { color: isDark(mode) ? '#7CB4FF' : '#007DFF', offset: 0 },
    { color: isDark(mode) ? '#9F94FF' : '#5F5AFF', offset: 0.35 },
    { color: isDark(mode) ? '#B98AFF' : '#8B3AE8', offset: 0.65 },
    { color: thinkingTopTrackColor(mode), offset: 1 }
  ];
  return new LinearGradient(stops);
}

// 档位名文字色（★ 2026-11-25 六轮，决明「把思考卡的档位颜色，关闭 自动到最高，依次为灰色、
// 黑色、浅蓝、深蓝到紫色」；★ 同日修笔「高低没区分，就这样吧，若本身就没有区分，蓝色也可以
// 都用一样的」→ 低/高合并同一强调蓝）：卡内顶行右侧档位名的档位色阶，只此一处消费（轨道
// selectedColor 仍走 thinkingTopGradient / selectedAccentBlue，未联动——决明只点名档位名）。
// · 灰/黑 = 系统语义字色（font_secondary / font_primary）。「黑」在深色档由系统自动反转为白
//  （深底黑字不可读，这是「黑」唯一合理的对偶）；浅色档 = 主字黑，与档位名原色一致。
// · 蓝 = selectedAccentBlue 单源（浅 #007DFF / 深 #7CB4FF）——低/高共用：两档蓝在真机上看不出
//  区别（决明回执「高低没区分」），不再造第二个蓝；与轨道普通档同色，观感一致。
// · 紫 = thinkingTopTrackColor 单源（浅 #9333EA / 深 #C084FC）。
// · 未知档（未来新增档位值）回落主字色——不落灰（宁可中性，不可误读成「关闭」档语义）。
// 参数 option = 源档位值（'' = 自动），不是轨道下标——收窄域增删档位时映射随值走。
export function thinkingLevelTextColor(mode: number, option: string): ResourceColor {
  if (option === 'off') {
    return $r('sys.color.font_secondary');
  }
  if (option === '') {
    return $r('sys.color.font_primary');
  }
  if (option === 'low' || option === 'high') {
    return selectedAccentBlue(mode);
  }
  if (option === 'max') {
    return thinkingTopTrackColor(mode);
  }
  return $r('sys.color.font_primary');
}

// 滑轨档位原点色（官方 showSteps 画的原点）：与 menuDividerColor 同族观感（浅黑 20% / 深白 30%
// 再压一档透明），但语义是「轨道上的刻度点」而非分割线，故不复用其函数（同值不同义，改一处
// 不该牵动另一处）。
export function sliderStepColor(mode: number): string {
  return isDark(mode) ? '#4DFFFFFF' : '#33000000';
}

// 选中态强调蓝单源（★ 2026-11-15 决明「把选中勾都改蓝，和顶部分段胶囊选中同色」笔）：
// 浅 = 官方强调字蓝 $r('sys.color.font_emphasize')（#007DFF）、深 = #7CB4FF 提亮档（系统
// font_emphasize 深色档 #5291FF 对白 20% 胶囊仅 ≈3:1，提亮到 ≈4.3:1 保可读）。三处消费 =
// SegmentBar.selectedFontColor() 光感态选中字 + 菜单项尾选中勾（menuEndCheck 全仓单源）+
// 会话标题栏副标题「模型 思考」四字（2026-11-15 加大改蓝笔）；
// 改色只动本函数，消费侧禁散抄字面量。取值依据 = docs/变更记录.md 2100 节 +
// SegmentBar.ets 头注释「2026-11-05 顶部蓝字笔」（该笔只动分段字色，本笔扩到勾并单源化）。
export function selectedAccentBlue(mode: number): ResourceColor {
  return isDark(mode) ? '#7CB4FF' : $r('sys.color.font_emphasize');
}

// 菜单项右勾（★ 2026-11-11 决明「统一为勾在右」笔，全仓口径）：官方 MenuItem 的内置勾
// （selected + selectIcon）由引擎钉在项内容行**第 0 位**——`MenuItemPattern::AddSelectIcon`
// 走 `MountToParent(row, 0)`，`END` 分支源码注释原文「The selected icon position configured at
// the end. Now tv is shown at the end」= 右置只有 TV 档；d.ts 的 MenuItemAttribute 无勾位属性，
// 应用侧改不了位置 ⇒ 要「文字最左、勾最右」只能走官方尾部图标槽条件挂，且不挂 selected /
// selectIcon（挂了会同时出左勾）。
// 用法：MenuItem({ content, symbolEndIcon 传 menuEndCheck(选中条件) })——未选中返回 undefined
// （不占位，菜单宽由最宽项定，切档不来回跳宽）；选中即项尾单勾，项目内唯一勾位形态。
// ★ 2026-11-15 勾色笔：选中勾统一 selectedAccentBlue 单源染色，与顶部分段胶囊选中同色；
// 深浅分档由菜单每次弹出前 rebuild 现读 AppStorage 承接（规范 §7 快照语义），不做组件内
// 订阅式刷新。同笔把 WorkspaceSortMenu 六档内联勾收敛进本函数——全仓 18 处选中勾
// （5 文件）**字形/勾位/颜色全单源**，改色只动此一处；新菜单禁再写 selected + selectIcon。
// 消费方五处（2026-11-14 DS 批 S1 后）：思考档位 ThinkingMenu（5 项）/ 权限模式
// PermissionMenuBuilder（3 项）/ 联网引擎 WebSearchMenu（3 项）/ 通用枚举值行
// FunctionalSettingRows.SettingMenuRow（1 项）/ 工作区排序 WorkspaceSortMenu（6 项）。
export function menuEndCheck(selected: boolean): SymbolGlyphModifier | undefined {
  if (!selected) {
    return undefined;
  }
  const colorMode: number = AppStorage.get<number>('appColorMode') ??
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  return new SymbolGlyphModifier($r('sys.symbol.checkmark'))
    .fontColor([selectedAccentBlue(colorMode)]);
}

// 分段胶囊背板高（标准档，全项目默认；悬浮层定位消费：内容滚动层顶部留白 = 悬浮位置 +
// 本常量 + 间距）
export const SEGMENT_BAR_HEIGHT: number = 40;

// 卡内卡头行右置分段胶囊定宽：官方组件宽度 = 父容器宽、不支持通用 width（见
// components/SegmentBar.ets build 注释），故与左侧标题同行并排时须由外层定宽容器约束
//——160vp = 两个 4 字选项（64/项，两项 128）+ 背板内距 8 + 余量 24，4 字项不折行不省略
//（消费项 = 全局记忆/助手记忆、自动注入/按需读取）。首例 = 记忆两页卡头行（图表卡卡头
// 右置 74vp 是紧凑档两字项先例，本常量走标准档四字项）
export const SEGMENT_BAR_ROW_WIDTH: number = 160;

// 分段胶囊紧凑档背板高（两处卡头视图切换的小尺寸档：图表卡「图表/表格」与上下文用量分段
// 明细卡「占已用/占窗口」——胶囊 22vp / 背板内边距 3vp 与之配套，恒等式 3+22+3=28，档几何
// 单源 = components/SegmentBar.ets 紧凑档注释；选中胶囊白底为全非材质态通用、非本档专属，
// 同见该件）。标准档仍 40vp（上行）。消费面三处共引本常量（勿写死数值）：SegmentBar 紧凑档
// 的背板最小高 + 图表卡卡头定宽容器高 + 上下文用量分段明细卡卡头定宽容器高
export const SEGMENT_BAR_COMPACT_HEIGHT: number = 28;

// 分段胶囊「标题带档」背板高（36vp，2026-11-18 决明「下排分段胶囊和新建键高度大小改为与
// 三键胶囊统一」笔首立）：与同排 36vp 三键紧凑胶囊（TitleBarKeys.TITLE_CAPSULE_COMPACT_HEIGHT）
// 等高——档内恒等式 4+28+4=36（胶囊 28vp / 四周 4vp / 选项字号 12fp，档几何单源 =
// components/SegmentBar.ets bandTier 分支）。消费面两处共引本常量：SegmentBar 带档背板最小高
// + 侧栏会话二级页分段行行高与带内容高（禁写死 36）
export const SEGMENT_BAR_BAND_HEIGHT: number = 36;

// 页顶分段胶囊「标题栏下方带（bottomBuilder）」承载几何（数值沿真机实测口径）：带顶 =
// 标题栏下沿（HDS 保证）。**锚点不能用 topPad**——topPad = 状态栏 + 标题栏 56 + 蒙层下延
// 16（HomeNavigation.titleBarInset），比标题栏下沿低 16vp；页顶现状写的是 margin top =
// topPad − 8 = **标题栏下沿 + 8vp**，故带内下移本值即逐像素回到内容区悬浮层位置（真机裁决：
// 测试页甲乙两变体 + 橙线探针实测确认）。消费面（现十处）：九个 PageShell 页经壳
// titleBarBottom 转交 + 日志页（LogPage 出带 / LogPageContent 出悬浮层）。★ 标题栏内嵌分段
// 笔：原「一级页『对话』页签由 HomeNavigation 直调 segmentBandParams」一处**已退役**（该页
// 分段迁入标题栏覆盖层，带整条取消——本常量只服务带内下移量，与覆盖层形态无关）
export const SEGMENT_BAR_BAND_TOP_INSET: number = 8;
// 同上，用量统计 / 费用统计两页例外：该两页现状为 margin top = topPad（不探入蒙层），比其余
// 八处低 8vp——迁移后取本值以各保各自现状（不顺手统一，改口径另行拍板）
export const SEGMENT_BAR_BAND_TOP_INSET_STATS: number = 16;

// 板块标题规范（「模型接入/待导入条目」这类卡外板块级标题；2026-11-01 决明拍板改档
//——字号字重与组卡行副标题同档、颜色改官方强调蓝，旧「16fp Bold cardTitleColor 黑」档退役）：
// · 字号/字重/字色 = **14fp + 常规字重（不设 fontWeight）+ $r('sys.color.ohos_id_color_emphasize')
//   官方强调蓝**（HdsTabs 选中同源，浅 #007DFF / 深 #006CDE 深浅随系统；消费侧用资源引用禁写 hex）；
// · 排版 = 标题与下方控件间距 6vp（Column space 体系，勿加 margin）；
// · 适用范围 = **编辑/配置/设置类页面的卡外板块级标题**——组件单源 = components/SectionHeader.ets
//   （设置/偏好/信息/记忆族/助手工具页等 13 文件消费），自绘存量仅三处同三值（MemoryImportPage
//   「粘贴其他平台的输出」、ChatFontSection 字体三节标题、ChatUsagePopup 气泡标题〔决明拍板
//   跟随〕）；★ 编辑页卡内标题（内容/条目/注入方式/技能正文等 2026-10-25 表单重构包卡的）
//   已随本笔迁 CARD_SECTION_TITLE_FONTSIZE 档，禁再引本常量；
//   ★ 不含：①表单字段标签（「标签+输入框」二元组非板块，维 13fp 灰 cardDescColor 普通）
//   ②列表卡内副行/选项 chips/页签说明等 13fp 小字维 13fp ③卡内小节标题（16fp Medium，
//   CARD_SECTION_TITLE_FONTSIZE 档）④半模态分组标题 15 Bold ⑤搜索页族标题 18 Bold；
// · 板块头副标题行已退役（2026-11-01 决明「去掉所有板块副标题」——板块面只留标题，说明与
//   计数由卡面行副标题、空态行与 ⓘ 气泡承接）；卡内说明行仍 13fp cardDescColor 灰
export const SECTION_TITLE_FONTSIZE: number = 14;

// 卡内小节标题字号规范（治「卡内小节标题 15/16 两档按页分裂」）：卡内小节标题 / 表单字段
// 标签 / 空态标题统一 **16fp + FontWeight.Medium + 主色（cardTitleColor()/font_primary）**。
// · 豁免恒不动：半模态分组标题 15 Bold（规范-半模态面板与卡片布局自有档）、消息正文 15
//（MarkdownBlockView/ChatMessageItem）、滑杆右值 15（数值非标题）
export const CARD_SECTION_TITLE_FONTSIZE: number = 16;

// 卡内说明行字号规范（治「说明小字 13/12 两档」）：卡内说明行 / 字段说明 / 空态说明统一
//**13fp + cardDescColor 系灰**。
// · 豁免恒不动：徽章 10/11、hintText 错误提示行 12+warning、图表小字；
// · 列表条目卡副行 → 13 属归一范围不算豁免
export const CARD_NOTE_FONTSIZE: number = 13;

// 详情卡名称规范（领导指令「助手详情统一为 18，沉淀」）：
// · 字号/字重/字色 = **18fp + FontWeight.Medium + cardTitleColor()黑**——详情页顶部大卡
//   主名称（ProviderHeadCard / AssistantEditPage.DetailCard 两处均引本常量；曾按「详情 >
//   列表」设 20fp，拍板统一 18——卡片层级改由大卡体/大头像尺寸承载，不靠名称字号差）；
// · 与列表卡关系：LIST_CARD_TITLE_FONTSIZE 同 18——名称层两级制（名称 18 / 说明·字段标签
//   13），卡片层级由卡体/头像尺寸区分；
// · 排版 = 名称下副行 12fp cardDescColor 灰，间距 Column space 4；头像 = 64 圆底（服务商
//   品牌 logo / 助手首字，列表卡同尺）
export const DETAIL_CARD_TITLE_FONTSIZE: number = 18;

// 列表卡名称规范（领导指令「卡也改大吧，但里面内容排版要适宜」修订为同级制）：
// · 字号/字重/字色 = **18fp + FontWeight.Medium + cardTitleColor()黑**——列表卡片主名称
//（ProviderCardItem / AssistantPage 助手列表卡，引本常量）；
// · 与详情卡同 18fp（原「详情 20 > 列表 18」三级差作废，层级由卡体尺寸区分）；
// · 排版 = 名称下副行/徽章行（灰胶囊 10fp；助手卡 chip 行同款 10fp 灰胶囊，★ 2026-09-20
//   卡面改版——原「助手选中标记 13fp」行内文字形态退役，改 chip 行首「✓ 当前」强调色胶囊），
//   间距 Column space 4 维持——名称单行省略号兜底不撑卡高，chip 行 Flex wrap 防窄屏与长计数裁切
export const LIST_CARD_TITLE_FONTSIZE: number = 18;

// 「更多」菜单隐形锚点定位几何（LogPageContent 锚点消费）：锚点右缘 = 标题栏「更多」按钮
// 右缘（HDS 标题栏右 padding end 16vp，dshinhm 真机量测）
export const MORE_MENU_ANCHOR_RIGHT: number = 16;

// 「更多」按钮下沿距标题栏下沿距离（MINI 标题栏 56vp 内按钮 ≈40vp 垂直居中，上下各留
// 8vp——**锚点顶须对齐按钮下沿而非标题栏下沿**，否则菜单整体偏低 8vp，dshinhm 真机量测）。
// ★ 领导拍板：所有标题栏更多菜单弹窗一律用本「按钮下沿」几何（日志页/服务商管理页
// 先例，坑11）。★ 2026-11-18 对齐笔：页签主页面 TabMoreMenuAnchor 的旧 DELTA=30 定稿
// 退役——全站（含页签主页面）统一本公式，原「主页面 / 二级页两套几何」规废止
export const MORE_MENU_BUTTON_BOTTOM_INSET: number = 8;

// 菜单统一固定宽（决明指令「三处标题栏菜单统一」；原 TabMoreMenu 私有常量上提至此，单一
// 来源防再复制魔数）：值 180 = 排序子菜单折行四轮真机定案（子项内容需求 ≈128vp + 余量，
// 覆盖字体渲染差异与缩放）。
// ★ 机制教训（四轮实证，勿回退成 constraintSize）：官方《菜单和菜单项宽度计算规则》的
//「设宽时子项取固定宽 = 配置宽 − padding」**只对 Menu 的 width 属性生效**——
// `constraintSize` 实测只撑宽菜单底板（子项与分割线均不跟随）、`width('100%')` 为百分比
// 非固定宽，两形态已证无效勿回填。定案 = 固定值 width，主菜单与子菜单同值同默认 padding
// ⇒ 两侧子项宽天然一致。
// ★ 适用边界：普通菜单仍走**官方默认自适应**（不设宽 = 2 栅格基准 160vp + 内容超量撑开，
// 上限约屏宽 67%，官方引擎 SelectTheme `menu_default_width` 实读）——本常量只用于「已定
// 统一宽」的菜单（清单 = docs/规范-菜单与二级菜单.md §3，现四处含工作区「更多」菜单）；
// 给短项菜单写死宽度会留大片空白，新增消费方须先拍板
export const MENU_UNIFIED_WIDTH: number = 180;

// 页面底色透明版：深 #00121212 / 浅 #00F1F3F5（alpha 前置），与 $r('app.color.page_bg')
// 实色（深 #121212 / 浅 #F1F3F5）配对——用于「从透明渐变到页面底色」的蒙层：聊天页底部
// 渐变蒙层 + 全屏输入面板底部沉淀（消息滑入输入区渐隐）
export function pageBgFade(mode: number): string {
  return isDark(mode) ? '#00121212' : '#00F1F3F5';
}

// 半模态遮罩色：面板 SheetOptions 显式 maskColor 与页面其余弹层同源（KimiSheetCommon 消费）
export const SHEET_MASK_COLOR: string = '#33000000';

// 只读小标签 / 灰档徽标底色：服务商卡与模型卡的只读信息标、ChatToolCard「写操作」等灰档
// 徽标共用；**可选 / 操作 chip 不走本函数**（走 selectChipBg 蓝底族）。半透明灰透出卡底，
// 与 SegmentBar 选中胶囊同灰系（浅黑 8% / 深白 15%，透明度略低于选中胶囊——层级弱于选中态）；
// 文字色消费方用 cardDescColor
export function badgeBg(mode: number): string {
  return isDark(mode) ? '#26FFFFFF' : '#14000000';
}

// ── 选项 / 操作 chip 底色（灰底 → 助手「当前」同档蓝底）──
// 未选 / 操作 chip = 淡彩蓝底（fallbackBlueBg，与状态强调档、助手「当前」徽标同值）；
// 选中 = 官方强调蓝实底 + 白字（字色由 selectChipTextColor 给出）。1vp 透明边仍是布局占位，
// 防切换时整块跳动——选中态靠实底区分，不靠描边。消费侧禁再写 chip 底色 / 字色。
export function selectChipBg(selected: boolean, mode: number, level?: number): ResourceColor {
  return selected ? $r('sys.color.ohos_id_color_emphasize') : fallbackBlueBg(mode, level);
}

export function selectChipBorderColor(selected: boolean): ResourceColor {
  // 两态都透明：选中实底已足够，保留 1vp 宽度占位防跳动（selected 参保留调用签名）
  return Color.Transparent;
}

export function selectChipTextColor(selected: boolean, mode: number): ResourceColor {
  // 字色单源 = 强调档字色（未选）/ 纯白（选中实底），与状态徽标强调档同值
  return selected ? Color.White : statusBadgeFg(0, mode);
}

// ── 视觉色板单源（唯一判据 = docs/规范-视觉色板与徽标.md）──
// 身份色六组，每组 [浅底, 浅字, 深底, 深字]：浅色档淡底 + 深字，深色档深底 + 亮字。
// ★ 现值参照 RIK（决明「图标干脆完全参照 Rik 的颜色」）：六组整体换成 RikkaHub
// minimal 预设 container 原值与同规律派生——蓝/黄/石板 = minimal 直抄（与 GroupSettingCard
// 设置图标蓝黄灰**同值**），玫 = errorContainer 同族（浅档直抄；深档 2026-11-01 决明真机
// 反馈「深色模式红底太显眼」改取 M3 基线 errorContainer #8C1D18、弃 minimal 抄来的高对比
// 变体 #93000A——同明度压色度，与同组深容器气质对齐；复算两保留线全过，规范 §2 已回写），
// 青按 M3 规律派生，紫与设置图标紫同值。
//**两套语义、一套色源**：本表按 seed 散列识别「哪个助手」、设置图标按功能域取五色，机制
// 不动；旧「浅底对卡底 ≥1.35」可见线随该笔退役（minimal 卡底本就是纯白，Rik 原生观感即
// 淡底压白卡，决明拍板接受）。保留线：字对底 ≥4.5、深底对 #1C1C1E ≥1.35（现值全过）。
// 用途：助手头像（列表 / 编辑页 / 消息轮头）与会话列表首字徽章——同一 seed 同色，跨页一致。
// 取色粒度 = 全串散列（31 进制滚动哈希；原「首码点」实现会让同前缀 id 全部同色，已修正——
// conversationId 一律 conv- 开头、首字符全是 'c' 曾致会话徽章全部同色）。
// 会话卡 seed 取 conversationId（**不取标题**——AI 生成标题会换首字导致色块跳变）。消费侧禁再写 hex。
const IDENTITY_PALETTE: string[][] = [
  ['#E7F0FE', '#1B4ACB', '#1D3E7F', '#D9E4FF'],
  ['#E2DEF5', '#4B4886', '#413A73', '#D6CEF7'],
  ['#DDF4F0', '#085F67', '#12474D', '#C4EAED'],
  ['#FCEFCE', '#6A5008', '#5B4400', '#FFE6AA'],
  ['#FDE7E5', '#A31710', '#8C1D18', '#FFDAD6'],
  ['#EFF0F2', '#3B3E44', '#3A3D43', '#E2E4E8']
];

// 全串散列实现（取色粒度理由与「首码点」缺陷见上色板块注释）
function identitySlot(seed: string): string[] {
  const chars: string[] = Array.from(seed);
  if (chars.length === 0) {
    return IDENTITY_PALETTE[0];
  }
  let hash: number = 0;
  for (let i = 0; i < chars.length; i++) {
    hash = (hash * 31 + (chars[i].codePointAt(0) ?? 0)) % 100000007;
  }
  return IDENTITY_PALETTE[hash % IDENTITY_PALETTE.length];
}

// 身份色 · 底（浅色档淡底 / 深色档深底）
export function identityBg(seed: string, mode: number): string {
  const slot: string[] = identitySlot(seed);
  return isDark(mode) ? slot[2] : slot[0];
}

// 身份色 · 字（浅色档深字 / 深色档亮字）
export function identityFg(seed: string, mode: number): string {
  const slot: string[] = identitySlot(seed);
  return isDark(mode) ? slot[3] : slot[1];
}

// 状态徽标四档（淡底 + 深字，同屏多颗不抢注意力）：
// 0 = 强调（草稿 / 当前 / 内置 / 使用中 / 助手写入 / 深度注入）；1 = 弱化（已停用 / 未配置 /
// 历史态）；2 = 成功（已保存 / 已连接 / 余额查得）；3 = 危险（密钥失效 / 明文缺失）。
// ★ 拍板「徽标只扩充淡绿淡红」：四档到此为止，**琥珀警示档明确不开**（最容易滥用成
//「什么都警示」）；两新档禁挪作身份色 / 入口图标 / 按钮底（规范 §8 禁用清单）。
// ★ 提浓笔（决明「徽标不够醒目，且和图标色类似」）：**浅色档加深底、深色档提亮底**——
// 同一判据「让色块离卡面更远」在两个模式下的相反操作，不是二选一。四档底对白卡 1.20~1.25
// 提到 **1.29（弱化）/ 1.36（其余三档）**，字色同幅压深保 4.5:1。为何要动：①1.23 在白卡上
// 读作「泛了一点点光」，色块立不住；②强调档字与设置入口图标蓝符号色相全同、同屏几乎不可
// 分——提浓后拉开分层，「浓块 = 状态 / 淡圆 = 功能」。为何不再往上推：浓度必须按**面积**
// 定——徽标 60×20 是标记，1.36 恰到好处；再深就成色块，故 chatBubbleUserBg 与
// fallbackBlueBg 两处**刻意不跟提浓**（三面同值关系至此只剩文字约束，登记于规范 §10）。
export function statusBadgeBg(tone: number, mode: number): string {
  if (tone === 1) {
    return isDark(mode) ? '#2C323B' : '#DFE3E8';
  }
  if (tone === 2) {
    return isDark(mode) ? '#1A3A31' : '#C9E3D9';
  }
  if (tone === 3) {
    return isDark(mode) ? '#552828' : '#F6D5D5';
  }
  return isDark(mode) ? '#1E3157' : '#CEDEFD';
}

export function statusBadgeFg(tone: number, mode: number): string {
  if (tone === 1) {
    return isDark(mode) ? '#C2CBD6' : '#4E5A69';
  }
  if (tone === 2) {
    return isDark(mode) ? '#B4F0D4' : '#125238';
  }
  if (tone === 3) {
    return isDark(mode) ? '#FFC0C0' : '#B01C1C';
  }
  return isDark(mode) ? '#B4CFFF' : '#1440C4';
}

// ── 淡染卡三档（规范条文 = docs/规范-列表卡片与组卡.md §1.3，改值先读该节）──
// 用途：一页挑**一张**卡，卡底掺语义色，充当「这张卡有一个值得先看的数」的视觉锚点；
// 承接原「反转深卡」的全部场景（决明「反转卡用淡染代替」，深色暗块方案已否决）。
// 判据三条缺一不可：①整页信息重心 ②一屏最多一张 ③卡内不放「只有暗底才成立」的元素。
// 形态硬口径：几何完全沿用邻卡（CARD_PANEL_WIDTH / 圆角 CARD_RADIUS / padding），**只换底色**
//——不加投影、不加第二层描边、不改圆角字号；边框保留 cardBorderColor() 不因染色而撤。
// 取值规则：浅色 = 语义色实色叠白取整（蓝 14% / 绿 **24%** / 红 14%）；深色 = 20%（绿红）/
// 22%（蓝）叠 #1C1C1E——同一比例在深色上只有 1.10 出头，肉眼读作没上色，故深色单独反推。
// 沿革：原 10% 真机读作「白卡泛了一点点光」，提到 14%（绿档后经「再绿一些」反馈单独提至 24%）。
// **绿档改色的真因是色相不是浓度**：原色相 H157 与徽标成功档同族读作「薄荷灰绿」，「再绿
// 一些」落在色相上（H157 → H144）；明度是**压**不是提——提亮会更不绿也让渐变更弱。
// 验收线 = 底 vs 卡面 **1.16~1.34**（上限防「大面积色块压住正文」，下限防「染了等于没染」；
// 卡上文字是深色主文字，1.30 量级影响不到正文对比）。
// 卡上文字仍用官方语义色（font_primary / font_secondary 一族），不为染色另开字色。
// ★ 2026-11-09 反馈笔例外（决明「淡蓝卡色脏、有描边而 info 无」）：三张点名首卡
//（提示词库系统提示词入口卡 / 用量统计 Token 首卡 / 费用估计费用总览首卡）改与 InfoCard
// 同取 `app.color.info_card_bg` 资源色且零描边，**不再消费本族 tintCardBg**。上面的
//「边框保留」口径此后只约束本族剩余消费面；资源色深浅两模式自动分治、不叠卡底透明度档
//（与 InfoCard 同形制）。改判全文见 docs/规范-列表卡片与组卡.md §1.3 与变更记录。
export const TINT_BRAND: number = 0;
export const TINT_POSITIVE: number = 1;
export const TINT_DANGER: number = 2;

function tintRgb(kind: number, mode: number): string {
  if (kind === TINT_POSITIVE) {
    return isDark(mode) ? '203B2D' : 'CDE8D8';
  }
  if (kind === TINT_DANGER) {
    return isDark(mode) ? '402227' : 'F8E4E6';
  }
  return isDark(mode) ? '1C2747' : 'DFE6FA';
}

// 淡染卡终端色（随卡底透明度档位叠 alpha——与全站中性卡同口径，避免用户调低档位后淡染卡
// 成为全页唯一不透的卡；规范 §1.3 该条为「首版跟随」，真机若确认低档染色读不出，再改
//「淡染卡恒实色」并登记，不许多页各写一套）。消费侧禁写 hex、禁临时调淡。
export function tintCardBg(kind: number, mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + tintRgb(kind, mode);
}

// 淡染卡渐变（★ 绿档单独结构）：左上满染 → 右下渐白，角度 135° = 左上到右下；backgroundColor
// 保留作兜底。
// · 蓝 / 红档 = 满染 0.0 → 满染 0.42 → 卡底 1.0（首停不加深，保住头卡 baseUrl 次要字对比）；
// · **绿档 = 浓 0.0 → 半染 0.5 → 卡底 1.0**：原与另两档同款，但满染端只到 1.19，「前 42%
//   完全不变 + 后 58% 渐到 1.00」两端差太小，观感是「一块绿 + 一块白」而不是「颜色在流动」；
//   中停换半染并挪到 0.5 后三段均匀下降——**加深满染端只解决一半，改结构才是主因**。
// 消费侧两处（服务商头卡 = 蓝档 / 余额入口卡 = 绿档）共用本函数，禁各写一套 stops。
export const TINT_GRADIENT_ANGLE: number = 135;

export function tintCardGradientColors(kind: number, mode: number, level?: number):
  Array<[ResourceColor, number]> {
  if (kind === TINT_POSITIVE) {
    // 半染 = 满染浓度的一半（浅 24% → 12% / 深同法叠 #1C1C1E）
    return [[tintCardBg(kind, mode, level), 0.0],
      [alphaHexPrefix(mode, level) + (isDark(mode) ? '1E2C25' : 'E6F3EB'), 0.5],
      [cardBg(mode, level), 1.0]];
  }
  return [[tintCardBg(kind, mode, level), 0.0], [tintCardBg(kind, mode, level), 0.42],
    [cardBg(mode, level), 1.0]];
}

// ── 卡内统计格底（2026-11-09 视觉批次：用量/费用两页 StatGrid 格底灰改淡蓝）──
// 与首卡 TINT_BRAND 同色相但**淡一档**（浅 #EEF3FF / 深 #232E4A）：首卡是满染的视觉锚点，
// 格底若同浓度会同屏糊成一片蓝；格是卡内元素、不算 §1.3 的「第二张淡染卡」。随卡底透明度
// 档叠 alpha（与 tintCardBg 同口径，低档位不出现整页唯一不透的格）。消费侧禁写 hex。
export function statCellBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '232E4A' : 'EEF3FF');
}

// ── 纸黄展示卡底（2026-11-09 决明点名「字体页顶部展示卡换纸黄色底」）──
// 第四档淡染、语义中性（不进 TINT_BRAND/POSITIVE/DANGER 三档），**只服务字体展示卡**：
// 低饱和暖纸色配深色主文字，样字对比不受影响；深色按淡染卡口径单独反推（浅 #FBF4E3 /
// 深 #322C1E），不照搬浅色浓度。内滚区 0.5vp 分割线仍走 cardBorderColor。
// 新增页面消费本档须决明点名，禁据「好看」自行扩散。
export function paperCardBg(mode: number, level?: number): string {
  return alphaHexPrefix(mode, level) + (isDark(mode) ? '322C1E' : 'FBF4E3');
}

// ── 首卡深色渐变（K3 页级点名例外）──
// 颜色消费面仅三页：NetworkSettingsPage 当前出口卡 + WebServiceSettingsPage 状态首卡 +
// PyRuntimePage 运行环境卡（均决明点名；第三处 = 2026-11-16 首卡渐变笔）。K3 通用形态仍否决
//（规范-列表卡片与组卡 §1.4），第四页须决明点名。本组固定
// 深色、不随卡底透明度档；深色模式为基线，浅色模式顶/底各提亮提饱和一档（白页底会削弱卡内
// 色距）。消费侧禁写 hex；改值只改本节。瓦片/主视觉块几何见下组注释，动作行高三页共用。
export const HERO_CARD_BG_TOP_DARK: string = '#26355F';
export const HERO_CARD_BG_MID_DARK: string = '#1A2C42';
export const HERO_CARD_BG_BOTTOM_DARK: string = '#10473A';
export const HERO_CARD_BG_TOP_LIGHT: string = '#2E4278';
export const HERO_CARD_BG_MID_LIGHT: string = '#1C3049';
export const HERO_CARD_BG_BOTTOM_LIGHT: string = '#0E5140';
export const HERO_CARD_LABEL: string = '#B3FFFFFF';
export const HERO_CARD_TEXT: string = '#FFFFFF';
export const HERO_CARD_TEXT_TESTING: string = '#D9FFFFFF';
export const HERO_CARD_TEXT_DIM: string = '#99FFFFFF';
export const HERO_CARD_DIVIDER: string = '#1FFFFFFF';
export const HERO_CARD_BADGE_BG: string = '#26FFFFFF';
export const HERO_CARD_BADGE_TEXT: string = '#F2FFFFFF';
export const HERO_CARD_SUCCESS: string = '#8FE2BC';
export const HERO_CARD_DANGER: string = '#FFB6BC';
// 卡底文字动作行高：网络卡「测试连接」/ Web 卡启停动作同档（40 → 32 真机反馈后）
export const HERO_CARD_ACTION_HEIGHT: number = 32;
// 卡内瓦片与主视觉块：瓦片 52 定主行高（Web 状态卡）；主视觉/说明块 minHeight 40 让单行态与
// 多行态占同高，卡高不跳（Web 状态卡说明块 + PyRuntimePage 主视觉块同用）；maxLines(2) 防
// 窄屏三行撑高。
export const HERO_CARD_TILE_SIZE: number = 52;
export const HERO_CARD_TILE_RADIUS: number = 16;
export const HERO_CARD_TILE_BG: string = '#24FFFFFF';
export const HERO_CARD_COPY_MIN_HEIGHT: number = 40;

// 渐变三停（左上 → 右下，angle 135）：深色基线 / 浅色提亮一档；backgroundColor 兜底取中停。
export function heroCardColors(dark: boolean): Array<[ResourceColor, number]> {
  return [[dark ? HERO_CARD_BG_TOP_DARK : HERO_CARD_BG_TOP_LIGHT, 0.0],
    [dark ? HERO_CARD_BG_MID_DARK : HERO_CARD_BG_MID_LIGHT, 0.5],
    [dark ? HERO_CARD_BG_BOTTOM_DARK : HERO_CARD_BG_BOTTOM_LIGHT, 1.0]];
}

export function heroCardMidColor(dark: boolean): string {
  return dark ? HERO_CARD_BG_MID_DARK : HERO_CARD_BG_MID_LIGHT;
}

// 收藏星色（会话卡身份徽章右下角标 + 关图标回落星）：色板青档符号对（浅 #085F67 / 深
// #C4EAED，2026-10-31 决明拍板），功能固定色双档成对，与未读点 sys.color.warning 同类先例。
// 原暖琥珀退役——琥珀压深保白圆底可读即发棕，提亮到金亮又跌破 3:1 图形线（#E8A317 仅
// 2.2:1），可读的金物理上就是棕金。青与同卡面的草稿徽标（强调蓝）、未读红点全不撞色相
// ——收藏是正向标记，不与既有语义抢色。
export function favoriteStarColor(mode: number): string {
  return isDark(mode) ? '#C4EAED' : '#085F67';
}

// 引用块底色：RIK surfaceVariant 20% 混合后明度差约 2~4%，换算取黑 4%/白 5% 近似档保双态
// 可见——badgeBg 同手法半透明透底、深浅自适应
export function quoteBlockBg(mode: number): string {
  return isDark(mode) ? '#0DFFFFFF' : '#0A000000';
}

// 引用块左条色：主蓝半透明透底——浅色 45% / 深色 70%，白底上约 #8FB4FA、深底上约 #4B7EBC，
// 与视觉色板淡蓝同族。半透明而非实色：引用块会出现在白卡与用户淡蓝气泡两种底上，透底自动
// 适配（badgeBg 同手法）。深色档取 70% 而非 45%，是为在 #1C1C1E 卡底上保住 3vp 细线的可见度。
export function quoteBarColor(mode: number): string {
  return isDark(mode) ? '#B35FA8FF' : '#730A59F7';
}

// ── diff 红绿固定色（立于 MarkdownCodeText，后上收本件——markdown 代码块 diff 着色与工具卡
// 变更 diff 块两处同源消费防漂移；固定色不随主题是既有拍板〔RIK 缺省钉死〕）──
// + 行字色 / - 行字色；±行同色 12% 半透明行底（与 cardBorderColor 的 12% 同口径）
export const DIFF_ADDITION_COLOR: string = '#4CAF50';
export const DIFF_DELETION_COLOR: string = '#EF5350';
export const DIFF_ADDITION_LINE_BG: string = '#1F4CAF50';
export const DIFF_DELETION_LINE_BG: string = '#1FEF5350';

// ── 用量统计页色板（提示词变量卡蓝已统一入本族）──
// 取色来源：参考稿像素实测主蓝，后归一为 #0A59F7（对齐 ImmersiveLevel 胶囊按钮材质强调蓝
// 基准，固定强调蓝族内单源）；深色档亮蓝 #5FA8FF（暗底用亮蓝保证可读）。

// 主强调蓝（统计行数字 / 排名 1~3 / 峰值 / 柱体 / 图标 glyph）：浅 #0A59F7 / 深 #5FA8FF
export function usageAccentColor(mode: number): string {
  return isDark(mode) ? '#5FA8FF' : '#0A59F7';
}

// 热力图四档色（level 1~4）：主蓝 ARGB 半透明阶梯（54/85/B8/FF——半透明透卡底自动深浅
// 适配，badgeBg 同手法）；level 0 空档 = badgeBg(mode)（参考稿空格灰 ≈ badgeBg 叠白底观感）
export function usageHeatColor(mode: number, level: number): string {
  if (level <= 0) {
    return badgeBg(mode);
  }
  const alphas: string[] = ['#54', '#85', '#B8', '#FF'];
  const idx: number = level > 4 ? 3 : level - 1;
  return alphas[idx] + usageAccentColor(mode).substring(1);
}

// 主蓝半透明阶梯（段色；上下文用量面板分段条同手法）：第 0 段 alpha 255（最实）线性渐淡
// 至末段 alpha 64，半透明透卡底深浅自适应（usageHeatColor 同族）；单段时恒 255
export function rampColor(mode: number, index: number, count: number): string {
  if (count <= 1) {
    return usageAccentColor(mode);
  }
  const alpha: number = Math.round(255 - index * (255 - 64) / (count - 1));
  const hex: string = alpha < 16 ? '0' + alpha.toString(16) : alpha.toString(16);
  return '#' + hex.toUpperCase() + usageAccentColor(mode).substring(1);
}

// 图标块底色（总览/Token 卡 36×36 图标方块）：主蓝 10% 半透明（#0A59F7 单源）；任务框底色
// 消费同值（RIK「primary 10% 底」换算——不另开）
export function usageIconBg(mode: number): string {
  return isDark(mode) ? '#1A5FA8FF' : '#1A0A59F7';
}
