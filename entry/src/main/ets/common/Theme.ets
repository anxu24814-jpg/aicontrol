// 聊天页配色公共件（2026-08-29 任务书 M1 自 dshinhm common/Theme.ets 按需随迁——只取
// ChatMessageItem/ChatThinkingBlock 实际消费的四个函数，其余不带）：
// 卡片背景/边框按深浅色分治；标题/描述色直接用官方语义色资源（深浅色自动切换）。
// ★ 行内操作按钮官方形制（2026-08-30 领导拍板「接官方形状与光感，均官方灰底即可」，
// 规范同源 AGENTS.md「行内按钮官方形制」条）：统一写法 =
// Button(label).backgroundColor($r('sys.color.comp_background_tertiary')).stateEffect(true)
// ——背景用官方三级灰底；形状/字号/字色/按压光感全走官方默认，禁止自绘 borderRadius/
// fontSize/fontColor 覆盖官方形制（旧实现 borderRadius(18) 半胶囊 + 手动 fontColor 系
// 偏离，已收敛）。★ 2026-09-02 光感化演进：行内操作键（含图标钮）改 resolvedButton
// 四件套（fontColor/Bg/systemMaterial/stateEffect，见 common/ImmersiveLevel.ets 胶囊
// 按钮光感簇——材质 = REGULAR 基准 + 按压形变/触点光效 + 官方浅灰配色，随沉浸光感
// 总档〔2026-09-12 分项退役口径〕；无光感档自动回退本条官方灰底）；主操作键（「保存」类）primary=true 官方强调蓝 +
// 恒白字（AdjustStageView「保存」同构）。「禁自绘」红线不变——四件套全走官方函数。
// ★ 排除项（2026-08-30 领导澄清）：**选项类 chips 不适用本条**——
// 模型能力多选等是「选项」非功能按钮，照 ModelCapsCard 范式（Text 胶囊 +
// badgeBg 灰底 + 无 stateEffect 按压光感），勿按功能按钮接光感。
// （2026-09-11 三处模板统一半模态：原举例「套用模板预设」chips 已全退役——协议/价格/
// 余额三处模板选择改「选择模板」键 + 半模态行卡〔方案 v3，BalanceTemplateCard 为末处〕，
// 本排除项举例收窄为能力多选。）
// ★ 2026-09-07 拍板例外：**提示词变量插入卡**（SystemPromptPage/AssistantPromptPage
// 变量区——「点击插入」入口语义，非纯选项）脱离本排除项——改官方胶囊按钮
// （.type(Capsule) + 显式官方灰阶实色 app.color.comp_fallback_gray + 原生按压；
// **不接沉浸光感**（不叠 systemMaterial——Material.empty 也属「已配置」）——历轮真机
// 四连压实锤：缺省 ROUNDED_RECTANGLE 大矩形 / Material.empty 双层蒙层 / 光感透明底
// 无按钮底 / 无背景则默认强调蓝；2026-09-07 决明终拍，见变更记录）；
// 字色 = 用量统计页主蓝（usageAccentColor——2026-09-07 决明「变量卡蓝色统一为用量统计页
// 色值」拍照，原淡蓝 variableLabelColor 退役，见用量统计页色板节）；其余选项类 chips
// （ModelCapsCard 等）照旧。
// （2026-08-29 M2a 自 dshinhm 随迁；★ 2026-08-30 反馈轮 13：组卡件 GroupSettingCard 曾随
// 设置页改版退场删除——两常量留用：CARD_PANEL_WIDTH = 全应用卡宽基准 / CARD_SPACING =
// 列表卡片间距，值与注释口径 = dshinhm 同名常量；★ 2026-09-07 设置页组卡化重新引入
// GroupSettingCard（components/GroupSettingCard.ets：官方系统设置「已配对设备」卡实测
// 规格复刻——行高固定分档 56/64vp、24vp 符号、16vp 间距、14fp 副标题、0.5vp 分割线；
// 选型理由/实测表见该组件头注释，本处只留指针。）
import { ConfigurationConstant } from '@kit.AbilityKit';

// 组卡/回退自制卡统一宽度（dshinhm 定稿 = 屏宽 −32vp，左右 16vp——卡左缘与标题栏主标题
// 左缘对齐；官方 12vp 边距版本卡过宽已废，勿再试）。注意：官方 HDS 行卡挂 .width() 不生效，
// 本常量只用于自制卡与需对齐卡宽的非 HDS 元素
export const CARD_PANEL_WIDTH: string = 'calc(100% - 32vp)';

// 列表卡片组纵向间距（dshinhm 定稿 = 10vp，官方《设置列表卡片样式》示例 List({ space: 10 })）。
// 卡片间距一律由容器 space 管理，禁止对卡片自身挂 .margin() 管间距
export const CARD_SPACING: number = 10;

// 消息气泡行内边距（dshinhm 二三三改定稿值；列表层已左右各 12）：近侧 4（绝对 16）、远侧
// 20（绝对 32）——用户行 near 在右 / far 在左（右对齐镜像）。★ 2026-09-16 决明「助手的
// 右边距缩短与左边距统一」后助手侧三件（消息泡 / 思考块 / 工具卡）两侧同取 near 4/4 对称，
// far 现只用户侧消费（用户消息泡左 + 附件泡左）。
// ★ 2026-09-15 预览笔自 ChatMessageItem 上收 Theme——附件独立气泡（AttachmentBubble）与
// 消息泡两件同源消费（值不变；原文件内同名常量已删，防两处漂移）
export const BUBBLE_PAD_NEAR: number = 4;
export const BUBBLE_PAD_FAR: number = 20;

// 用户消息泡宽度上限（2026-09-16 决明「消息气泡，用户的缩短为原60%左右，右边距不变」立，
// 2026-09-18 决明「再增宽30%左右」→ 60% 调 78%，即原宽的 1.3 倍；行内距不动故右缘贴位
// 不变，收窄/放宽全落在左缘）。百分比基准 = 同一父容器（消息泡所在 Row 的内容宽），
// 与列表层左右 12vp 无耦合。
// ★ 消费形态 = **定宽壳的显式宽度**（2026-09-18 换行修复笔，见 ChatMessageItem 用户分支
// 注释）：本常量不再挂气泡自身的 constraintSize——那只是测量后的尺寸钳制，泡内 Markdown
// 段落仍按父行全宽排版，长内容会顶出泡右缘；移作外层壳宽即成为子组件的测量约束，段落
// 按上限换行、高度自然增长
export const BUBBLE_USER_MAX_WIDTH: string = '78%';

// 附件泡与消息泡两泡间距（2026-09-15 预览笔，任务书-附件气泡与预览 §2.5）：初值 6vp，
// < 消息间距离 CARD_SPACING(10)——小于消息间距离，两泡才成组可辨；观感不适只改本常量
export const ATTACH_BUBBLE_GAP: number = 6;

// 消息气泡圆角（2026-09-16 思考块同泡化笔立「文件内单源」——用户泡 / 助手泡 / 思考半泡 /
// 工具卡四处同值，同泡化拼接靠两半各自切直角配合，不改半径值；★ 2026-09-17 全面自检第4轮
// 笔3 上收 Theme：附件独立气泡与消息泡同屏相邻同底色，圆角须同步演化，而 AttachmentBubble
// 不能反向 import ChatMessageItem（后者持它——反向即模块环），故并入本常量单源文件成
// 五处同源。值不变，防两处漂移——上收动因与 BUBBLE_PAD_* 2026-09-15 先例同款）
export const BUBBLE_RADIUS: number = 16;

// HDS MINI 标题栏官方默认高度 56vp（官方设计指南「窗口框架」：56vp 适用标题栏/工具栏等
// 通用控件；dshinhm 同值）。用途：内容区延伸到标题栏背后时，滚动内容顶部留白的组成项
// （titleBarInset，见 nav/HomeNavigation.ets）
export const TITLE_BAR_MINI_HEIGHT: number = 56;

// 标题栏渐变模糊蒙层向下超出标题栏的高度（官方默认 32vp，dshinhm 真机反馈偏大调小为 16
// 并在标题栏 maskExtraHeight 显式同步——两者必须一致，要调两处同改；与 titleBarInset
// 共用本常量保证同源）
export const TITLE_BAR_MASK_EXTRA_HEIGHT: number = 16;

function isDark(mode: number): boolean {
  return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
}

// 卡片背景：浅色白底；深色官方语义深底 #1C1C1E（dshinhm 同款，真机验证过）
export function cardBg(mode: number): string {
  return isDark(mode) ? '#1C1C1E' : '#FFFFFF';
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

// 滑块滑轨色（2026-08-29 M2c 自 dshinhm 同名函数随迁，「外观显示」页档位滑条消费）：
// 半透明让底层沉浸光感材质透出（不透明会完全盖住材质滤镜，官方属性冲突约束——dshinhm 定稿）
export function sliderTrackColor(mode: number): string {
  return isDark(mode) ? '#14FFFFFF' : '#0D000000';
}

// 菜单项分割线色（2026-08-29 M3 自 dshinhm 随迁，运行日志「更多」菜单消费）：浅色 = 官方
// 默认黑 20%，深色材质菜单上不可见 → 换白 20%（dshinhm 真机定稿）
export function menuDividerColor(mode: number): string {
  return isDark(mode) ? '#33FFFFFF' : '#33000000';
}

// 分段胶囊背板高（2026-08-29 M3 自 dshinhm 随迁，AppearancePage/LogPageContent 悬浮层
// 定位消费：内容滚动层顶部留白 = 悬浮位置 + 本常量 + 间距）
export const SEGMENT_BAR_HEIGHT: number = 40;

// 板块标题规范（2026-09-01 领导指令沉淀——「名称/内容/点击插入变量」这类板块级标题；
// ★ 2026-09-08 决明反馈「主标题字号过小，连同系统提示词页增大」：**13fp → 16fp**——
// 原「回 13fp 勿放大、只加重」口径作废，16fp Bold 定为标准档（原本为外观显示页
// 「沉浸光感档位」节标题独立形态，随本反馈升级为标准——字号史：16 → 13（09-01 定稿）
// → 16（09-08 拍板）：
// · 字号/字重/字色 = **16fp + FontWeight.Bold + cardTitleColor()黑**；
// · 排版 = 标题与下方控件间距 6vp（Column space 体系，勿加 margin）；
// · 适用范围 = **编辑/配置/设置类页面的板块级标题**（PromptEditPage 名称/内容、
//   SystemPromptPage 点击插入变量/内容、AssistantPromptPage 同两处、偏好设置/更多信息
//   页板块头 SectionHeader、FeedbackPage 区标题、日后新页同规）；
//   ★ 不含：①表单字段标签（模型 ID/模型名称/温度类——ModelEditPage 字段标签维 13fp
//   灰 cardDescColor 普通，字段标签是「标签+输入框」二元组非板块）②列表卡内副行/选项
//   chips/页签说明等 13fp 小字维 13fp；
// · 说明性文本（区块标题下的说明行）维持 13fp cardDescColor 灰——层级 = 标题黑且重 /
//   说明灰轻。
export const SECTION_TITLE_FONTSIZE: number = 16;

// 卡内小节标题字号规范（2026-09-12 UI 同形异构归一笔 3 立档——治盘点 B1「卡内小节标题
// 15/16 两档按页分裂」）：卡内小节标题 / 表单字段标签 / 空态标题统一 **16fp +
// FontWeight.Medium + 主色（cardTitleColor()/font_primary）**；原 15fp 阵营（服务商详情/
// 模型编辑/搜索引擎详情/价格卡等）全量归一 16fp。
// · 豁免恒不动：半模态分组标题 15 Bold（规范-半模态面板与卡片布局自有档，ModelPickerSheet
//   等）、消息正文 15（CubeMarkdownView/ChatMessageItem）、滑杆右值 15（数值非标题）。
export const CARD_SECTION_TITLE_FONTSIZE: number = 16;

// 卡内说明行字号规范（同笔立档——治盘点 B2「说明小字 13/12 两档」，Theme 口径本就明定
// 「说明行 13fp」）：卡内说明行 / 字段说明 / 空态说明统一 **13fp + cardDescColor 系灰**；
// 原 12fp 说明性文字全量归一 13fp。
// · 豁免恒不动：徽章 10/11、hintText 错误提示行 12+warning、图表小字、LevelSlider 刻度 11；
// · 列表条目卡副行（TemplateRow/MemoryRowCard 12fp）→ 13 属归一范围不算豁免（笔 4 域执行）。
export const CARD_NOTE_FONTSIZE: number = 13;

// 详情卡名称规范（2026-09-01 领导指令「助手详情统一为 18，沉淀」修订版）：
// · 字号/字重/字色 = **18fp + FontWeight.Medium + cardTitleColor()黑**——详情页顶部大卡
//   主名称（对位两卡：ProviderHeadCard 服务商详情卡 / AssistantEditPage.DetailCard 助手
//   详情卡，两处均引本常量）；★ 字号收敛史：16 → 20 → **18**（曾按「详情 > 列表」三级
//   差设 20fp，领导拍板统一为 18——详情/列表同名级，20 档退役，卡片层级改由大卡体/
//   大头像尺寸承载，不靠名称字号差）；
// · 与列表卡关系：LIST_CARD_TITLE_FONTSIZE 同 18——名称层统一 18fp Medium（两级制：
//   名称 18 / 说明·字段标签 13），卡片层级（详情/列表）由卡体/头像尺寸区分；
// · 排版 = 名称下副行 12fp cardDescColor 灰（服务商 baseUrl / 助手无副行），间距
//   Column space 4；头像对位：服务商 64 圆底品牌 logo（2026-09-01 详情卡对齐 48→64）/
//   助手 64 圆底首字（列表卡同尺，2026-09-20 卡面改版起）。
export const DETAIL_CARD_TITLE_FONTSIZE: number = 18;

// 列表卡名称规范（2026-09-01 领导指令「卡也改大吧，但里面内容排版要适宜」修订为同级制）：
// · 字号/字重/字色 = **18fp + FontWeight.Medium + cardTitleColor()黑**——列表卡片主名称
//   （对位两卡：ProviderCardItem 服务商列表卡 / AssistantPage 助手列表卡，引本常量）；
// · 与详情卡同 18fp（2026-09-01 晚版「统一为 18」定稿——原「详情 20 > 列表 18」三级差
//   作废，详情/列表名称同为 18，层级由卡体尺寸区分——「改大但排版适宜」靠卡体差异、
//   不靠名称字号差）；
// · 排版 = 名称下副行/徽章行（服务商徽章 = 10fp 灰胶囊；助手卡 chip 行同款 10fp 灰胶囊，
//   ★ 2026-09-20 卡面改版——原「助手选中标记 13fp」行内文字形态退役，改 chip 行首「✓ 当前」
//   强调色胶囊），间距 Column space 4 维持——名称单行省略号兜底不撑卡高，chip 行 Flex wrap
//   防窄屏与长计数裁切。
export const LIST_CARD_TITLE_FONTSIZE: number = 18;

// 「更多」菜单隐形锚点定位几何（2026-08-29 M3 自 dshinhm 随迁，LogPageContent 锚点消费）：
// 锚点右缘 = 标题栏「更多」按钮右缘（HDS 标题栏右 padding end 16vp，dshinhm 真机量测）
export const MORE_MENU_ANCHOR_RIGHT: number = 16;

// 「更多」按钮下沿距标题栏下沿距离（MINI 标题栏 56vp 内按钮 ≈40vp 垂直居中，上下各留
// 8vp——锚点顶须对齐按钮下沿而非标题栏下沿，否则菜单整体偏低 8vp，dshinhm 真机量测）。
// ★ 2026-08-30 领导拍板（轮 7）：今后所有标题栏更多菜单弹窗一律用本「按钮下沿」几何
//（日志页/服务商管理页先例，坑11）——页签 TabMoreMenuAnchor 的 DELTA=30 为主页面存量
// 定稿，不再向任何新页扩散
export const MORE_MENU_BUTTON_BOTTOM_INSET: number = 8;

// 页面底色透明版（2026-08-29 对话页 UI 对齐任务 2 自 dshinhm 同名函数随迁，值与注释口径
// 同源）：深 #00121212 / 浅 #00F1F3F5（alpha 前置），与 $r('app.color.page_bg') 实色
// （深 #121212 / 浅 #F1F3F5，两侧同对）配对——用于「从透明渐变到页面底色」的蒙层：
// 聊天页底部渐变蒙层 + 全屏输入面板底部沉淀（消息滑入输入区渐隐）
export function pageBgFade(mode: number): string {
  return isDark(mode) ? '#00121212' : '#00F1F3F5';
}

// 半模态遮罩色（2026-08-29 对话页 UI 对齐任务 2 自 dshinhm 同名常量随迁）：面板
// SheetOptions 显式 maskColor 与页面其余弹层同源（KimiSheetCommon 消费）
export const SHEET_MASK_COLOR: string = '#33000000';

// 徽章底色（2026-08-30 服务商管理域新增：卡片内小标签「OpenAI 兼容 / N 模型 / 使用中 /
// 能力标签」统一底色）：半透明灰透出卡底，与 SegmentBar 选中胶囊同灰系（浅黑 8% / 深白
// 15%，透明度略低于选中胶囊——层级弱于选中态）；文字色消费方用 cardDescColor
export function badgeBg(mode: number): string {
  return isDark(mode) ? '#26FFFFFF' : '#14000000';
}

// ── 用量统计页色板（2026-09-06 用量统计页改版新增；★ 2026-09-07 提示词变量卡蓝统一入
// 本族——原 variableLabelColor 退役）──
// 取色来源：2026-09-06 决明供图参考稿像素实测主蓝 #0A58F6（★ 2026-09-12 UI 同形异构
// 归一笔 6 归一为 #0A59F7——对齐 ImmersiveLevel 胶囊按钮材质强调蓝基准，固定强调蓝族
// 内单源；色差 1/255 分量肉眼无感）；深色档亮蓝 #5FA8FF（暗底用亮蓝保证可读——原
// variableLabelColor 深档同款惯例；2026-09-07 决明指令「变量卡蓝色统一为用量统计页色值」
// 后该函数删除、消费方并入本函数）。

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

// 主蓝半透明阶梯（段色；2026-09-17 自 UsageRankRing 提取共用——上下文用量面板分段条同
// 手法）：第 0 段 alpha 255（最实）线性渐淡至末段 alpha 64，半透明透卡底深浅自适应
//（usageHeatColor 同族）；单段时恒 255
export function rampColor(mode: number, index: number, count: number): string {
  if (count <= 1) {
    return usageAccentColor(mode);
  }
  const alpha: number = Math.round(255 - index * (255 - 64) / (count - 1));
  const hex: string = alpha < 16 ? '0' + alpha.toString(16) : alpha.toString(16);
  return '#' + hex.toUpperCase() + usageAccentColor(mode).substring(1);
}

// 图标块底色（总览/Token 卡 36×36 图标方块）：主蓝 10% 半透明（随上条归一 #0A59F7）
export function usageIconBg(mode: number): string {
  return isDark(mode) ? '#1A5FA8FF' : '#1A0A59F7';
}
