// 会话列表渲染域（自 ChatSessionList.ets 拆出）：职责一句话 =「会话列表区域渲染——Repeat
// 列表容器 + 会话行卡 + 读取失败提示行」。与业务壳 ChatSessionList.ets 分家（壳 = 数据读取 /
// 菜单 / 弹窗 / 删除 / 多选状态，本件 = 纯渲染 + 事件上抛），依赖方向单向（壳引本件、
// 本件不引壳），无模块环（坑50 口径）。行类型与派生纯函数已拆至 ChatSessionRowModel.ets
// （2026-11-16 P0 域级拆出，类型属主 = 行模型件；断言语料读点随迁）——本件只消费
// SessionListRow 并画卡，禁在此重新定义行字段/合成/比对逻辑。
// ★ Repeat 机制要点（官方《Repeat：可复用的循环渲染》实读 + 本地 d.ts 签名核对）：
//   ① 懒加载模式（.virtualScroll()）必须与状态管理 V2 配合——数据源由壳侧以
//      UIUtils.enableV2Compatibility(V1 @State) 在构造处传入（变量整体赋值时需再次手动调用）；
//   ② Repeat 子节点复用不复走 aboutToRecycle / aboutToReuse（官方明示；创建/销毁路径的
//      aboutToAppear/aboutToDisappear 照常），故卡片禁在构造期快照任何数据——卡内显示与
//      事件一律读 RepeatItem 当前值（官方要求 RepeatItem 类型整体传参）；
//   ③ 键只写会话 id 身份（.key）；★ 禁把选中态 / 未读态 / 时间后缀塞回键里当刷新手段——
//      Repeat 不做「键变重建」（「仅改变键值不改变 item 不会触发刷新」），行级交互态的刷新
//      走 V2 @Param 传播（选中 / 多选 / 未读 / 时间与图标开关 / 深浅色全部为壳侧标量或数组
//      @Param 下发，链 = V1 @StorageProp/@State → V2 @Param → 卡内 @Param）。
// ★ 头尾让位 = List 的 contentStartOffset / contentEndOffset（自首末行 padding 改，官方内容
// 轨随内容滚；不采用空占位 ListItem——官方「滚动容器组件内只能包含一个 Repeat，不建议同时
// 包含 ListItem、ForEach、LazyForEach」）。
// ★ 侧滑（决明拍板「左滑唤出控件，实底圆角方形」；★ 2026-10-30 定五键、2026-11-17 整体
// 退役加密会话后为四键：左滑露卡片右侧三键「重命名 → 移动 → 删除」，右滑露卡片左侧一键
// 「收藏」，两侧最外侧键分别对应长距甩动的删除/收藏）：侧滑只加在 ListItem 层，卡片与 Repeat 机制零改动（键仍只写
// 会话 id，展开态不进键）。多选态不挂侧滑
//（按钮层不渲染、手势回调早退），侧滑与批量选择互斥。原生 ListItem.swipeAction 换成自研横滑层
//（SessionSwipeItem）：原生按钮区与卡片同层平移（FAQ faqs-arkui-1121）、edgeEffect 只有
// Spring 多段弹跳 / None 无惯性两档、start/end 是「有控件才响应」——分向多键口径由自研手势
// 直接表达；curves.springMotion 单次过冲兼得惯性回弹与一次归位。
// 几何口径：卡片层 translateX 跟手；操作键一律随卡同移（等价一个滑组，但不建超屏宽的组
// 容器——避免按键命中区被父约束裁掉）。键位几何、四键形制与草稿行灰态全部落在拆件
// SessionSwipeKeys.ets（本件只持手势与位移）；展开量按方向各算 = 贴卡间距 16 + 键数 × 键径 40
// + (键数 − 1) × 间距 6，右 1 键 56 / 左 3 键 148（常量自拆件导入）。位移上限锁在该向展开量
//（卡缘与最内侧键间恒留贴卡间距、不再随长距滑离）；
// 长距阈值按原始手指位移判（屏宽一半），过阈值松手直接归位并触发该向最外侧键的动作
//（左 = 删除确认框、右 = 收藏/取消收藏）。
// ★ 2026-11-01 圆角收口（两千零六十一节）：卡片层外套一层**静态**窗口，窗口不随位移——卡片
// 滑出时按**形状裁剪**（`clipShape` + `PathShape`）收口，裁剪形状 = 卡片静止位的圆角矩形
//（左右各让 16vp、圆角 = CARD_RADIUS、高 = 卡高），故切边恒在卡片原位的左右端、两端恒为圆角
//（旧观感 = 被屏缘直切成方头）。窗口只包卡片层：键层与横滑手势均不受影响。
// ★ 三条真机坑（禁重犯）：①`clipShape` 必须挂在 `.clip(true)` **之后**，否则被布尔裁剪盖掉
//（观感 = 切边落回屏缘）；②`PathShape.commands` 单位是 **px 不是 vp**，坐标与圆角一律经
// `vp2px()`，否则 3 倍屏上裁剪框只剩「左上角一小条」；③窗口**禁收窄**到卡缘——窗口一窄，
// 官方行卡会跟着二次变窄，补宽（calc + offset）真机不生效、排版走形。
// 首尾让位改 List 内容轨的原因：原首行 padding 式让位会把侧滑按钮区拉成「顶到屏顶的超长
// 矩形」（真机反馈）。
// 手势与列表滚动：PanGesture 方向锁 Horizontal，竖向滑动不识别、List 照常滚；列表滚动开始
//（onScrollStart）收起展开行。行组件复用时 @Monitor 归位（Repeat 复用不走
// aboutToRecycle，见机制②）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { curves, display, PathShape } from '@kit.ArkUI';
import { HdsListItemCard, SuffixCustomBuilder } from '@kit.UIDesignKit';
import { ConversationRow } from '../../common/store/ChatDb';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, favoriteStarColor, identityBg,
  identityFg, CARD_RADIUS
} from '../../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { formatSessionCardTime } from './SessionSearchPanels';
// 全站状态词徽标形制单源（草稿徽标裁定形上提共享件，本件消费）
import { StatusBadge } from '../StatusBadge';
// 新会话草稿单槽 key（合成行身份判据——无菜单键/无侧滑/点击走新建链，均以 id 判；键纪律 =
// Repeat 键仍只写 id，'__new__' 与 DB id 永不同名）
import { NEW_DRAFT_KEY } from './ChatDraftStore';
// 行模型（类型与派生纯函数；2026-11-16 P0 域级拆出，本件只消费类型并画卡）
import { SessionListRow } from './ChatSessionRowModel';
// 侧滑操作键层（2026-10-30 拆件：四键形制 + 键位几何；展开量与该向键间距常量同源供
// 手势钳位与净反向判据消费）
import {
  SessionSwipeKeys, SWIPE_OPEN_LEFT, SWIPE_OPEN_RIGHT, SWIPE_GROUP_EDGE
} from './SessionSwipeKeys';
// 卡片菜单域（2026-10-30 拆件：五项菜单内容 + 长按上下文菜单参数）
import { SessionCardMenuBuilder, SessionCardMenuCallbacks, sessionCardMenuOptions } from './SessionCardMenu';

// 行类型与派生纯函数已拆至 ChatSessionRowModel.ets（2026-11-16 P0 域级拆分）——本件只引
// SessionListRow 并画卡，禁在此重新定义行字段/合成/比对逻辑（类型属主 = 行模型件）。

// 尾行让位（vp）：末卡下留白 16（原 Scroll 容器 padding bottom 式同值）+ 多选中批量条让位
// 56（挂 selectMode 三目——与壳侧 SessionMultiselectBar 悬浮贴屏底对应；原式同值）
const LIST_TAIL_GAP: number = 16;
const MULTISELECT_BAR_CLEARANCE: number = 56;
// List 可视区外预创建缓冲（实验分支真机值 5，任务书 §2.2「缓存可沿用实验 5」——转正时按
// 真机手感定稿）
const LIST_CACHED_COUNT: number = 5;

// ── 会话卡身份徽章几何（2026-10-26 45° 同心笔单源）──
// 徽章 36 / 圆角 12（视觉规范 §4 阶梯特例）；垂直居中于内容区 48 → 上距 = 卡内距 16 +
// (48−36)/2 = 22，圆心 y = 40。同心判据要求圆心 x = 圆心 y → 视觉左距 22 → translate +6
// （布局左距仍 16）；translate 不占位，故徽章与内容列的 Row space 由 8 补到 14 抵回视觉
// 间距 8。三值同改才成立：只挪 offset 会使间距读成 2vp，只改 space 会把文字再推 6。
const SESSION_BADGE_SIZE: number = 36;
const SESSION_BADGE_OFFSET_X: number = 6;
const SESSION_BADGE_TEXT_GAP: number = 14;

// ── 侧滑手势判据（键宽/间距/组边距/展开量等键位几何已迁 SessionSwipeKeys.ets）──
// 展开量之外的手指行程只做「还能再拉」的手感回执——极小阻尼、上限 10vp，卡片不离开按钮；
// 双向同款；该段行程同时计入长距阈值（屏宽一半），松手过阈值直接走删除 / 收藏
const SWIPE_OVER_DRAG_DAMP: number = 0.08;
const SWIPE_OVER_DRAG_MAX: number = 10;
// 吸附/惯性判据：滑过该向展开量的 42% 或快速甩动（|velocityX| > 600vp/s）即展开；
// 长距 = 原始手指位移过「该向展开量 + 余量」与「行宽一半」的较大者（七笔起长距不再靠卡片
// 位移表达，卡片始终停在该向展开位；两向同构但展开量不同，故分向各算）
const SWIPE_OPEN_RATIO: number = 0.42;
const SWIPE_FLING_VELOCITY: number = 600;
const SWIPE_LONG_RATIO: number = 0.5;
// 净反向收起判据（vp）：反手越过半个键间距即认定「往回划」。★ 独立成常量、不再借键间距
// 用——键尺寸（键径 52 / 间距 12）改档时这一档手感不该跟着漂
const SWIPE_BACK_MIN: number = 6;
// 回位死区（vp，2026-11-01 决明真机实报「手动拖回原位时把另一侧控件带一点出来」后立；该症状
// 的几何根因已于 2026-11-05 贴卡间距对齐笔消除——键簇静止位全在屏外，位移符号翻转挂起对侧
// 键层也不再露）。现留死区承接手动拖回的指尖过冲：起手不在原位的手势回到原位附近时，先吃掉
// 一段死区再从 0 连续起算，滑组不产生位置跳变、状态不在零位移处翻转。值取 24：明显大于自然
// 过冲、又小于单键步长 46——反向确属「有意继续拉」时仍照常跟手
const SWIPE_RETURN_DEAD: number = 24;
// 长距余量（vp）：必须明显大于展开量，否则「拉开展开三键」与「甩到底直接执行」两档会合并
const SWIPE_LONG_MARGIN: number = 40;

// ═══ 会话卡片（自 V1 卡迁 V2）═══
// 形态 = 官方 HdsListItemCard（唯一渲染路径——canIUse 能力位与无 HDS 设备回退自制卡已撤，
// HDS 组件自 API 20 系统内置、minSdk 26 恒可用）：prefix 恒不传，B 区自绘「身份徽章 36 +
// 标题/摘要两行」，C 区自绘功能键。卡宽不挂 .width（官方姿势 = 容器 100% − 内部 16vp×2 =
// CARD_PANEL_WIDTH 三线对齐）。
// 功能矩阵（迁移前 V1 卡逐项对齐，零削减）：
//   · 点击 = 进会话（多选中 = 切换勾选；记最近进入在壳侧 handleOpenCard，上行
//     onOpen(row) 不变）；
//   · 收藏星 = 身份徽章右下 14vp 角标（会话图标恒显示，原「徽章关时回落摘要行」分支随
//     图标开关退役删除）；摘要行状态位恒两态（草稿 → 转圈，位序随规范 §4.10/§5）；
//   · C 区（右缘）普通态为空（右缘 2x2 四点更多键 2026-10-30 退役，菜单改长按卡片）；多选态
//     官方 Checkbox + hitTestBehavior(None) 纯视觉（坑5：Checkbox 自带点击会消费事件）+
//     40vp 占位基准；
//   · 未读红点在**标题行右端**（时间左侧）——与身份徽章解耦，图标恒显示后仍独立成宿主；草稿
//     徽标 / 转圈 / 锁在**摘要行右端**（状态位右对齐，草稿在前）；
//   · 身份徽章 36（首字 + conversationId 取色 + 收藏星角标）在 B 区第一列，官方 prefix 恒不传
//     （20vp 符号位放不下 36）——2026-11-12 偏好开关批后徽章恒显示（图标开关已退役）；
//   · 标题 16fp（maxLines(1)+Ellipsis + layoutWeight(1)）/ 时间 12fp / 摘要 13fp 单行省略；
//   · 内容区恒高 48（B 区 Row height），有无摘要、有无状态都不跳。★ 卡总高不是 80：2026-11-04
//     真机实测官方卡卡高 64（内距上下各 8），本节沿用的「内距 16 / 卡高 80 / 摘要起点屏缘 82」
//     是 10-20 自制卡口径——**动几何前先读规范 §4.10「真机实测口径」段与变更记录 2092**，
//     勿拿 80/82 当现状。
@ComponentV2
struct SessionCardItem {
  // 行数据（★ RepeatItem 整体传入——官方要求；卡内显示与事件一律读 this.ri.item 当前值，
  // 禁构造期快照：复用的节点不重走构造，也不走 aboutToReuse / aboutToRecycle；创建/销毁路径
  // 的 aboutToAppear 与 aboutToDisappear 照常——勿扩写成「任何生命周期都不跑」）
  @Require @Param ri: RepeatItem<SessionListRow>;
  // 多选模式（C 区只挂勾选圈 + 红点互斥）
  @Param selectMode: boolean = false;
  // 本卡是否选中（驱动 Checkbox select 回显）
  @Param selected: boolean = false;
  // 未读标记（壳侧判定 = row.id === unreadConvId；多选互斥在 showUnreadDot 内）
  @Param unread: boolean = false;
  // 系统颜色模式（卡底 cardBg / 徽章身份色取色消费）
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（V2 组件不挂 V1 @StorageProp——沿 appColorMode 同链由壳订阅后标量下发；
  // 收藏星底与卡底两消费点）
  @Param cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 事件两枚（★ @Event 允许传入的函数类型 = 箭头函数，调用侧一律箭头形式传入）：
  // 点卡片（普通 = 进会话；多选中 = 切换勾选）、勾选切换——更多键点击事件随更多键退役
  @Event onOpen: (row: ConversationRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };

  // ★ 更多键已退役（2026-10-30 决明拍板）：原卡片右缘 2x2 四点键（dot_grid_2x2 + 锚点
  // id + onMenu 上行）整块删除，菜单改由长按卡片弹出（SessionCardMenu.ets），五项操作
  // 另经左右滑四键直达。勿按旧形制补回可见入口——卡片右缘不再有任何键位。
  // 勾选圈（C 区自绘，多选态）：官方 Checkbox + hitTestBehavior(None) 纯视觉指示器（点击
  // 穿透落到行卡 onClick 单一通路切换勾选）；40vp 占位 = 两态统一基准
  @Builder
  CheckKeyBuilder() {
    Column() {
      Checkbox()
        .select(this.selected)
        .hitTestBehavior(HitTestMode.None)
    }
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  // 未读红点显隐判定（多选模式不显示——与勾选圈键位互斥）
  private showUnreadDot(): boolean {
    return !this.selectMode && this.unread;
  }

  // 生成中标记显隐判定（★ U9 会话列表 loading；多选互斥同红点口径）
  private showLoading(): boolean {
    return !this.selectMode && this.ri.item.loading;
  }

  // 草稿徽标显隐判定（2026-10-20 会话草稿持久化；多选互斥同红点/loading 口径）
  private showDraftMark(): boolean {
    return !this.selectMode && this.ri.item.draft;
  }

  // 身份徽章：36vp 圆角方块 + 标题首字 + 六色身份色，角标贴右下。取色 seed = conversationId
  //（**不取标题**——AI 生成标题会换首字，取标题会让色块跳变）；显示字符 = 标题首字（空标题
  // 兜底「新」）。收藏星 = 右下 14vp 角标，白/深卡底 + 细环，溢出徽章 2vp。为什么用 Stack：
  // 角标要压住徽章右下角，BottomEnd + offset 最省事，且 Stack 不裁剪溢出子项——真机须验官方
  // 卡 B 区容器是否自带 clip（§4.10 已知未验证项）。关「会话图标」开关 = 整块不渲染（红点
  // 已与徽章解耦、不受影响）。
  // ★ 45° 同心定稿（决明「一级页对话头像也改成共一条 45° 直线」；首稿顶对齐被真机否掉
  //「上圆角齐了、下圆角不齐，整个头像偏上」）= **垂直居中不动 + 视觉右移 6**：徽章保持原
  // 垂直居中（内容区 48 内居中 → 上距 = (48−36)/2 = 6，上下对称）；徽章**布局**左距 = 官方卡
  // 内距（真机实测 8，旧自制卡 16）、**translate x:+6**（与设置入口图标 SettingRowIcon 的同心
  // 偏移同值同法）→ 圆心到卡左边 = 到卡上边 = 内距 + 24（实测 32、旧口径 40），落在卡圆角弧心
  // (20,20) 出发的 45° 对角线上（判据 = docs/规范-列表卡片与组卡.md §3.1/§4.10）。**关系恒成立
  // 的前提 = 卡内距四向相等**，内距换值只动数值不动结论；下列旧算式里的 16/22/40/82 是按自制卡
  // 内距 16 推的，实测口径见 §4.10「真机实测口径」段。为何不用顶对齐：卡总高小于 80 时顶对齐的
  // 上方留白与下方空隙更不对称，卡片视觉重心偏上；居中 + 右移是唯一同时满足「重心对称」与
  //「45° 共线」的写法（几何推导见 §4.10）。translate 不改布局占位，故 Row space 由 8
  // 补到 14 抵回视觉间距 8（摘要起点因此由卡内 60 → 66，相对屏缘由 76 → 82）。
  @Builder
  IdentityBadgeBuilder() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Text(this.ri.item.title !== '' ? this.ri.item.title.substring(0, 1) : '新')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(identityFg(this.ri.item.id, this.appColorMode))
        .width(SESSION_BADGE_SIZE)
        .height(SESSION_BADGE_SIZE)
        .borderRadius(12)
        .backgroundColor(identityBg(this.ri.item.id, this.appColorMode))
        .textAlign(TextAlign.Center)
      if (this.ri.item.favorite) {
        Row() {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(9)
            .fontColor([favoriteStarColor(this.appColorMode)])
        }
        .width(14)
        .height(14)
        .borderRadius(7)
        .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .offset({ x: 2, y: 2 })
      }
    }
    .width(SESSION_BADGE_SIZE)
    .height(SESSION_BADGE_SIZE)
    // 视觉右移 6（布局占位不变）——圆心 x = 16+6+18 = 40 = 圆心 y（22+18），45° 同心判据
    // 成立；消费侧 Row space 8→14 抵回视觉间距，见本 Builder 头注释与 §4.10 算式
    .translate({ x: SESSION_BADGE_OFFSET_X })
  }

  // 草稿徽标（胶囊「草稿」二字；2026-10-20 视觉规范落码起形制与配色单源 = 共享件 StatusBadge
  // ——淡底深字、强调档，改形制改那件一处全站跟随）。徽标非按钮非选项 chip，不受行内按钮
  // 形制条约束。位置 = 摘要行右端状态位首（§4.10）
  @Builder
  DraftMarkBuilder() {
    StatusBadge({ text: '草稿' })
  }

  // 生成中转圈（官方 LoadingProgress 小号；中性次要色——非警示语义。判据同源 showLoading）
  @Builder
  LoadingMarkBuilder() {
    LoadingProgress()
      .width(14)
      .height(14)
      .color($r('sys.color.font_secondary'))
  }

  // B 区自定义内容（判据 = docs/规范-列表卡片与组卡.md §4.10）：官方 TextItemOptions.
  // customBuilder 承载整块，本块恒高 48（卡总高由官方内距决定——真机实测 64，见文件头几何段
  // 与规范 §4.10「真机实测口径」，勿按 80 反推），所有会话行同高（有无摘要、有无状态都不跳）。结构 = Row[徽章 36 | Column[行1 标题+未读点+时间 |
  // 行2 摘要+状态位右对齐]]，徽章与文字间距 8（45° 同心后 Row space 8→14 抵回视觉间距 8，
  // 摘要起点〔布局〕= 卡内 16 + 36 + 14 = 卡内 66〔相对屏缘 82〕；改 space 与 translate 必须
  // 成对，漏一侧即间距读成 2 或 20）。
  // 状态位右置（不放行首）：摘要起点恒为「徽章视觉右缘 58 + 8」，纵向成一条线；放行首会让
  // 每条卡起跑线不同。放右只压摘要右端，宽度预算一点都不少。
  // 未读点固定在行 1 右端（时间左侧），与徽章解耦——图标恒显示，红点恒有宿主；右对齐笔起标题
  // layoutWeight(1) 吃满余量，点+时间簇恒贴行尾（C 区零足迹，范式 = 坑76/红线8）。
  // 摘要空态显示「暂无消息摘要」（55% 透明），占住行 2 高度不塌卡。
  @Builder
  TextItemBuilder() {
    Row({ space: SESSION_BADGE_TEXT_GAP }) {
      // 会话图标恒显示——偏好键已退役、行为固化为不可关闭，徽章不再有隐藏态
      this.IdentityBadgeBuilder()
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.ri.item.title !== '' ? this.ri.item.title : '新对话')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.showUnreadDot()) {
            Circle({ width: 8, height: 8 })
              .fill($r('sys.color.warning'))
              .flexShrink(0)
          }
          // 会话时间恒显示——偏好键已退役、行为固化为不可关闭，时间文本不再有隐藏态
          Text(formatSessionCardTime(this.ri.item.updatedAt))
            .fontSize(12)
            .fontColor(cardDescColor())
            .flexShrink(0)
        }
        .width('100%')
        Row({ space: 6 }) {
          Text(this.snippetText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .opacity(this.ri.item.snippet === '' && !this.ri.item.draft ? 0.55 : 1)
            .fontWeight(this.ri.item.draft ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.showDraftMark() || this.showLoading()) {
            Row({ space: 6 }) {
              if (this.showDraftMark()) {
                this.DraftMarkBuilder()
              }
              if (this.showLoading()) {
                this.LoadingMarkBuilder()
              }
            }
            .flexShrink(0)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(48)
  }

  // ★ 2026-11-12 偏好开关批：会话图标显示开关退役、图标恒显示——收藏星恒由徽章角标承载，
  // 原「徽章关时回落摘要行状态位」的 showFallbackStar 判据与 FallbackStarBuilder 整支删除
  //（回落分支已无触发条件，留着即恒 false 死代码 + 永不渲染的 builder）。

  // 摘要文本（空态兜底「暂无消息摘要」；草稿行由壳侧把草稿正文填进 snippet，不另取源）
  private snippetText(): string {
    if (this.ri.item.snippet !== '') {
      return this.ri.item.snippet;
    }
    return '暂无消息摘要';
  }

  // C 区键行（官方分支专用；多选态 = 勾选圈）。★ 115 版机制实锤：官方行卡 C 区 = **左锚 +
  // 内容自适应宽**——区内任何布局宽都参与测量并把键右推（星/锁 44vp 实锤）。
  // ★ 徽标落位沿革（前三稿失败面留档防回潮）：一稿 Stack + 徽标直挂 + translate −46（C 区宽
  // +8 键右移、间距按臆测键宽取错）；二稿官方浮层 overlay 真机两连败（align+offset 压住键左
  // 两点、width('100%') 跑到键下方）——**浮层在 HDS 自定义 C 区内的落位口径不可信，禁再回
  // 此路**；三稿整栈补偿数学自洽但残留四个未验面（首帧跳动/文字区恒窄/C 区三次翻车史/菜单
  // 锚点疑点——键被 translate 移渲染位，菜单按锚点 id 取布局矩形还是变换后矩形无官方保证）
  //——给不出「确保」。四稿定稿（决明 fallback 令「放标题最后一个字的右边」）= **徽标撤出
  // C 区**：C 区回到纯键行（与无徽标行逐像素同键位，零补偿零实测），徽标进 B 区标题行。
  // ★ CustomBuilder lambda 体内禁声明式组件尾随闭包——抽本 @Builder 方法，suffixItem lambda
  // 只做调用。C 区不承载任何菜单入口（更多键 2026-10-30 退役，菜单改长按卡片；合成行的
  // 「仅删除可点、其余置灰」在侧滑层与长按菜单各自处理，不在此处）
  @Builder
  SuffixRowBuilder() {
    // 普通态 C 区为空（更多键退役）：B 区吃满整行、时间簇直接贴行尾——把 suffixItem 传
    // undefined（工程内已有 8 处省略 C 区的先例）。
    if (this.selectMode) {
      this.CheckKeyBuilder()
    }
  }

  build() {
    // 官方行卡（搜索页 ResultCard 同款骨架）：**恒不传 prefix**——官方前缀位固定 20vp
    // 符号框，放不下 36vp 身份徽章；徽章改由 B 区第一列自绘（IdentityBadgeBuilder），
    // 会话图标开关改控徽章显隐。C 区只剩勾选圈（普通态为空）。
    HdsListItemCard({
      prefixItem: undefined,
      // B 区整体自绘（四稿定稿：徽标挂标题行文本右侧；customBuilder 优先级高于其它接口，
      // 标题/时间/星/锁全部进 builder，lambda 体内禁组件尾随闭包——只调用 @Builder）
      textItem: {
        customBuilder: (): void => {
          this.TextItemBuilder();
        }
      },
      // 红点 + 键分支收敛在 SuffixRowBuilder（lambda 体内禁组件尾随闭包，见其注释）。
      // 普通态整个 C 区不挂（更多键退役）——undefined 让官方行卡 B 区吃满整行；多选态才
      // 挂勾选圈
      suffixItem: this.selectMode ? new SuffixCustomBuilder((): void => {
        this.SuffixRowBuilder()
      }) : undefined,
      cardBorderRadius: CARD_RADIUS,
      // 卡底随全局透明档（@Param 链由壳订阅下发，档位变化经 @Param 传播即刷）
      cardBackgroundColor: cardBg(this.appColorMode, this.cardAlphaLevel),
      onClick: (): void => {
        if (this.selectMode) {
          this.onToggle(this.ri.item.id);
          return;
        }
        this.onOpen(this.ri.item);
      }
    })
  }
}

// ═══ 会话行横滑层（替代原生 ListItem.swipeAction）═══
// 职责一句话 =「会话行的横滑手势与位移——滑组平移、按向吸附、长距删除、长距收藏（键本身
// 在拆件 SessionSwipeKeys.ets）」。
// 与卡片分家：卡片 = 内容与点击（SessionCardItem 零横滑知识），本层 = 手势与位移层；与
// 容器分家：容器 = 列表与数据，本层 = 单行位移（父级只下发展开行 id 做互斥）。
// 层序（Stack）：外层满宽裁剪 → 卡片层（translateX 跟手，遮罩同层）→ 操作键层（四键，
// 键位与显隐在拆件内按 offsetX 自算）→ 点按遮罩（卡片层内，展开态透明层，点卡片先收起而
// 不是进会话）。
// 分向口径（决明 2026-10-30 定五键、2026-11-17 退出加密后为四键「右边删除/重命名/移动，
// 左边收藏，长距两向各对应最外侧一键」）：左滑露右侧三键、右滑露左侧一键，展开量按向
// 各取常量（右 1 键 56 / 左 3 键 148）；两向都
// 1:1 跟手，长距左滑 = 删除、长距右滑 = 收藏/取消收藏（草稿合成行 draftRow 不吃该动作，
// 只归位）。
// 长按：整行挂 bindContextMenu（普通态），标准官方上下文菜单——无预览浮起、无蒙层；多选态不挂。
// 手势：PanGesture 方向锁 Horizontal（竖向不识别，List 竖滚不受影响）；distance 8 略大于
// 系统默认 5，避免轻点抖动被误判为横滑。位移口径：两向都 1:1 跟手至该向展开量即停（超出只给
// 极小阻尼回执），展开态再滑以 dragStart 为基线连续跟手。松手：原始手指位移过长距阈值
//（屏宽一半）→ 归位并向该向派发动作（左 = 删除确认，右 = 收藏）；否则按「位移过该向展开量
// 42% 或快速甩动」吸附展开/收起，两向都临界阻尼零过冲（右滑原是橡皮筋、0.86 过冲会越过
// 收起位把对侧键带出来，真控件形态下统一零过冲）。
// 复用纪律：Repeat 复用不走 aboutToRecycle（文件头机制②），@Monitor 四路 + 进会话收口共五路
// 归位——行对象替换（收藏/重命名 reload）、展开权转移（滑了别的行）、切多选、可见集重算
//（切分段 / 多选进出 / 重拉换行时行对象可能原样复用，行侧监听听不到，由容器侧 visibleRows
// 监听收回）、进会话（push 期间列表留在栈内，返回重拉常与当前相等，故在 onOpen 包装里先
// 收起——返回时行不会停在展开态）。
@ComponentV2
struct SessionSwipeItem {
  @Require @Param ri: RepeatItem<SessionListRow>;
  @Param selectMode: boolean = false;
  @Param selected: boolean = false;
  @Param unread: boolean = false;
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（同 appColorMode 链下发——透传 SessionCardItem）
  @Param cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 沉浸光感档位（长按菜单背板材质随总档——@Param 标量下发，本件构造菜单参数时消费）
  @Param immersiveLevel: number = 0;
  // 草稿合成行（'__new__'，原 favDisabled 改名扩义）：侧滑除删除外三键置灰不派发、菜单
  // 前三项置灰（原语义只管收藏键，2026-10-30 五键笔扩到全部非删除动作；2026-11-17 退出
  // 加密后键数减一，判据不变）
  @Param draftRow: boolean = false;
  // 当前展开行 id（父级单源互斥：本行开始滑动时上行，父级改值即让上一行动画归位）
  @Param swipeOwner: string = '';
  @Event onOpen: (row: ConversationRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };
  // 四个动作（侧滑四键与长按菜单共用同一批：壳侧动作方法零分叉）
  @Event onFavorite: (row: ConversationRow) => void = () => {
  };
  @Event onRename: (row: ConversationRow) => void = () => {
  };
  @Event onMove: (row: ConversationRow) => void = () => {
  };
  @Event onDelete: (row: ConversationRow) => void = () => {
  };
  @Event onSwipeBegin: (id: string) => void = () => {
  };

  // 滑组当前横向位移（vp；左负右正）：负 = 左滑露出右侧三键（重命名/移动/删除），正 = 右滑
  // 露出左侧一键（收藏），上限按方向各取该向展开量（不再滑出屏外）
  @Local offsetX: number = 0;
  // 键层挂载边（-1 = 左滑向三键、+1 = 右滑向两键、0 = 不挂载）。★ 退场必须「原路划回」：
  // 键层的显隐分支不能挂在 offsetX 的符号上——animateTo 一进去 offsetX 已是终值 0，条件分支
  // 当帧就销毁键层，观感 = 键在屏缘顿住后原地消失（决明真机实报）。故挂载态跟手跟到位移符
  // 号、收敛在归位动画 onFinish；静止 0 = 零键创建，条件渲染的收益不丢
  @Local keysSide: number = 0;
  // 卡片实测高度（vp，onAreaChange 回写）：操作键层与点按遮罩的高度单源。★ 不能用
  // height('100%')——Stack 未定高时百分比子项按父约束（List 视口）解析，会把 Stack 反向
  // 撑到整屏，按钮变成贯穿上下的超长色条（真机实锤）
  @Local cardHeight: number = 0;
  // 屏宽（vp；长距阈值基数，两向同用。分屏/横屏支持时改 onAreaChange 按行宽重算）
  private screenW: number = 360;
  // 行宽（vp；本层几何单源：卡层宽 = 行宽、静止位最内侧键左缘 = 行宽〔键体全在屏外〕）。初值取屏宽，外层
  // onAreaChange 实测订正（分屏 / 平板窄栏自适应）
  @Local rowW: number = 0;
  // 本次手势起点位移（展开态再滑的基线，避免位移跳变）
  private dragStart: number = 0;
  // 本次手势的指尖行程（vp；恒以手势起点为原点，不含 dragStart——★ 长距删除判据必须只认
  // 本次手势拉了多少，混入展开态基线 = 展开行再左拉 40vp 即越「屏宽一半」阈值弹删除框，
  // 与真机清单「手指原始位移过屏宽一半」不符）
  private dragPos: number = 0;
  // 本次手势的主轴方向（+1 右 / −1 左 / 0 未定）：收起态起手时取首次显著行程的方向，用于判
  // 「反向越零」（见 SWIPE_RETURN_DEAD）；展开态起手直接用 dragStart 的符号，不读本字段
  private dragDir: number = 0;
  // 位移所属会话 id（Repeat 复用兜底：复用节点的 @Local 不重置，手势起点发现 id 变了即归零
  //——@Monitor('ri.item') 是首选路径，本字段防该监听在极端复用序下漏拍）
  private boundId: string = '';

  aboutToAppear(): void {
    this.screenW = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
    this.rowW = this.screenW;
    this.boundId = this.ri.item.id;
  }

  // 键位几何（卡片视觉宽 / 右键左缘 / 左键左缘）随四键形制一并迁 SessionSwipeKeys.ets
  // ——本件只留滑组位移与其吸附判据，不重复计算键坐标。

  // 展开权转移：父级改 swipeOwner 且不是本行 → 归位（上一行自动收起）
  @Monitor('swipeOwner')
  private onSwipeOwnerChange(): void {
    if (this.swipeOwner !== this.ri.item.id && this.offsetX !== 0) {
      this.springTo(0);
    }
  }

  // 切多选：侧滑层整层退役，位移立即归零（不走动画——多选换装是整页态变）
  @Monitor('selectMode')
  private onSelectModeChange(): void {
    if (this.selectMode && this.offsetX !== 0) {
      this.offsetX = 0;
    }
    if (this.selectMode) {
      this.keysSide = 0;
    }
  }

  // 行对象替换（收藏/重命名/loading 收尾 reload）：收起，避免旧位移挂在新行上
  @Monitor('ri.item')
  private onRowChange(): void {
    if (this.offsetX !== 0) {
      this.offsetX = 0;
    }
    this.keysSide = 0;
  }

  // 归位/吸附单源：两向统一 springMotion 临界阻尼 1.0（零过冲）。沿革 = 五笔曾按决明
  //「取消左滑时弹簧，右滑保留」分向取 0.86 过冲——当时右滑只是无控件的橡皮筋；右滑有真
  // 控件后过冲会越过收起位把对侧删除键带出来闪一下，故随橡皮筋形态退役统一零过冲。
  // ★ onFinish 才卸键层（动画期间 keysSide 保持，键跟着位移一起划回去）；归位途中被新手势
  // 打断时 offsetX 已非 0，此处的 0 判定天然跳过，不误卸
  private springTo(target: number): void {
    this.getUIContext().animateTo({
      curve: curves.springMotion(0.32, 1),
      onFinish: (): void => {
        if (this.offsetX === 0) {
          this.keysSide = 0;
        }
      }
    }, (): void => {
      this.offsetX = target;
    });
  }

  private handlePanStart(): void {
    if (this.selectMode) {
      return;
    }
    // 复用兜底：节点换了会话而 @Monitor 没赶上时，先把旧位移清掉再起手
    if (this.boundId !== this.ri.item.id) {
      this.boundId = this.ri.item.id;
      this.offsetX = 0;
    }
    this.dragStart = this.offsetX;
    // 长距判据原点归零（只量本次手势）——展开态起手时 dragStart 已带展开量，若把它算进
    // dragPos，「再拉 40vp」就会被判成「已过屏宽一半」
    this.dragPos = 0;
    this.dragDir = 0;
    this.onSwipeBegin(this.ri.item.id);
  }

  // 跟手位移（vp；raw = 起手位移 + 本次指尖行程，正 = 右滑方向）：1:1 跟手至该向展开量，
  // 超出只给极小阻尼作「还能再拉」的手感回执（两向展开量不同：右 2 键 102 / 左 3 键 148）
  private followOffset(raw: number): number {
    if (raw >= 0) {
      if (raw <= SWIPE_OPEN_RIGHT) {
        return raw;
      }
      const overRight: number = raw - SWIPE_OPEN_RIGHT;
      return SWIPE_OPEN_RIGHT + Math.min(overRight * SWIPE_OVER_DRAG_DAMP, SWIPE_OVER_DRAG_MAX);
    }
    if (raw >= -SWIPE_OPEN_LEFT) {
      return raw;
    }
    // 过展开量即停（卡缘贴最内侧键）
    const over: number = -raw - SWIPE_OPEN_LEFT;
    return -SWIPE_OPEN_LEFT - Math.min(over * SWIPE_OVER_DRAG_DAMP, SWIPE_OVER_DRAG_MAX);
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (this.selectMode) {
      return;
    }
    const raw: number = this.dragStart + event.offsetX;
    // 指尖行程单独记账（只取 event.offsetX = 本次手势自起点的累计行程；raw 是滑组视觉
    // 位置、含展开态基线，只能进位移不能进阈值）——展开量之外的手指行程不进滑组位移，
    // 但要参与长距阈值判定（两向同口径）
    this.dragPos = event.offsetX;
    // 主轴方向：收起态起手取首次显著行程的方向（展开态起手用 dragStart 的符号，不读本字段）
    if (this.dragDir === 0 && Math.abs(event.offsetX) > SWIPE_RETURN_DEAD) {
      this.dragDir = event.offsetX > 0 ? 1 : -1;
    }
    // ★ 反向越零死区（见 SWIPE_RETURN_DEAD）：位移越过原点朝反方向去时，先吃掉一段死区再从
    // 0 连续起算——手动拖回（非惯性）时的指尖过冲不会把对侧键层挂起来，也不会产生位置跳变
    // （死区前后 0 → 0.1 连续，只是导数为 0 的停顿）
    let effective: number = raw;
    const ref: number = this.dragStart !== 0 ? (this.dragStart > 0 ? 1 : -1) : this.dragDir;
    const dirNow: number = raw > 0 ? 1 : (raw < 0 ? -1 : 0);
    if (ref !== 0 && dirNow === -ref) {
      effective = ref < 0 ? Math.max(0, raw - SWIPE_RETURN_DEAD) :
        Math.min(0, raw + SWIPE_RETURN_DEAD);
    }
    this.offsetX = this.followOffset(effective);
    // 键层挂载边跟手跟到位移符号（0 = 已回到收起位，键层随即可卸）
    this.keysSide = this.offsetX < 0 ? -1 : (this.offsetX > 0 ? 1 : 0);
  }

  private handlePanEnd(event: GestureEvent): void {
    if (this.selectMode) {
      return;
    }
    // ★ 长距阈值按向算（2026-10-30 五键笔自查退化面）：底值 = 行宽一半（原「屏宽一半」口径，
    // 行宽实测后改用 rowW 更准），下限 = 该向展开量 + 余量。左向展开量 148 在常规 360 行宽上
    // 低于底值 180（单一底值不会误判），但窄行（行宽 ≤ 296）时底值跌到展开量之下——无下限则
    // 「轻拉展开」直接被判成长距删除、右侧三键永远点不到。
    const longBase: number = this.rowW * SWIPE_LONG_RATIO;
    const longLeft: number = Math.max(longBase, SWIPE_OPEN_LEFT + SWIPE_LONG_MARGIN);
    const longRight: number = Math.max(longBase, SWIPE_OPEN_RIGHT + SWIPE_LONG_MARGIN);
    // ★ 长距闸（决明真机实报「左滑展开后把卡拖回原位松手 → 会话被加上收藏」）：长距只认
    //「朝该向拉开」的手势。起手在展开态时，回撤方向的指尖行程必然整段路过对侧阈值——左展开
    // 148 在窄行（行宽 ≤ 296）上已不低于右向长距（= 行宽一半），拖回原位正好 +148、落手即判
    // 收藏。反向不发作只是右展开 102 恒小于左向长距下限 188 的非对称掩盖，不是没病。判据 =
    // 收藏须起手在收起态或右展开态，删除须起手在收起态或左展开态（同侧继续拉开照常长距触发）
    const favArm: boolean = this.dragStart >= 0;
    const delArm: boolean = this.dragStart <= 0;
    if (delArm && this.dragPos <= -longLeft) {
      // 长距判据按本次手势的指尖行程（原点修正见 dragPos 注释）；不播滑出动画——行先
      // 归位、同帧弹既有确认框（与删除键 onSettle + onDelete 同一条链，取消后不留划出态）
      this.springTo(0);
      this.onDelete(this.ri.item);
      return;
    }
    if (favArm && this.dragPos >= longRight) {
      // 长距右滑 = 收藏 / 取消收藏（与收藏键同一条链：先归位再上行，壳侧 reload 换行对象时
      // 行不停在划出态）。草稿合成行 draftRow = 只归位不派发
      this.springTo(0);
      if (!this.draftRow) {
        this.onFavorite(this.ri.item);
      }
      return;
    }
    // 净反向收起（决明「左滑后小距离右滑不能收起会弹回」）：本次手势净反向（位移过半间距
    // 或反向甩动）且起手时是展开态 → 一律收起，不再按「展开过四成」弹回展开位；两向同判
    //（起手右展开态向左回滑同判）；起手收起态的滑动照常走吸附判据
    const backToList: boolean = (this.dragStart < 0 &&
      (event.offsetX > SWIPE_BACK_MIN || event.velocityX > SWIPE_FLING_VELOCITY)) ||
      (this.dragStart > 0 &&
        (event.offsetX < -SWIPE_BACK_MIN || event.velocityX < -SWIPE_FLING_VELOCITY));
    if (backToList) {
      this.springTo(0);
      return;
    }
    // 吸附判据按方向取符号（位移正 = 右展开收藏一键，负 = 左展开重命名/移动/删除三键）
    const dir: number = this.offsetX >= 0 ? 1 : -1;
    // 该向展开量（两向键数不同：右 1 键 56 / 左 3 键 148）
    const openAmount: number = dir > 0 ? SWIPE_OPEN_RIGHT : SWIPE_OPEN_LEFT;
    const pull: number = Math.abs(this.offsetX);
    const flung: boolean = dir > 0 ?
      event.velocityX > SWIPE_FLING_VELOCITY : event.velocityX < -SWIPE_FLING_VELOCITY;
    const shouldOpen: boolean = pull > openAmount * SWIPE_OPEN_RATIO ||
      (flung && pull > 8);
    this.springTo(shouldOpen ? dir * openAmount : 0);
  }

  private handlePanCancel(): void {
    if (this.selectMode) {
      return;
    }
    this.springTo(0);
  }

  // 操作键形制（收藏/删除两键的实底圆角方形、图标上文字下、显隐互斥、灰态）连同新增的
  // 重命名/移动两键（与收藏/删除同批）一并迁 SessionSwipeKeys.ets——本件不再持有任何键 builder。

  // 收口形状（2026-11-01 圆角收口·三版）：**卡片静止位的圆角矩形**——左右各让 SWIPE_GROUP_EDGE
  //（= 官方行卡内部 16×2 边距）、高 = 卡高实测、圆角 = CARD_RADIUS，用路径显式画（不依赖形状
  // 偏移语义：RectShape 的 offset 是否参与裁剪无官方明示，Path 的坐标是绝对 vp，一步到位）。
  // 挂成窗口的裁剪形状后，卡片滑出时按此轮廓收口，切边位置**恒在卡片原位的左右端**（二版窗口
  // 取满幅、切边落在屏缘，本版订正）；圆角半径与卡身同值，收口弧与卡自身圆角同形。
  // ★ 为什么用形状裁剪而不是把窗口收窄到卡缘：窗宽一改，官方行卡会跟着二次变窄（一版真机
  // 实锤：卡被压窄、徽章贴边、键距走形），形状裁剪不碰任何布局。未实测卡高前返回 undefined
  // = 不裁（首帧静止态本就无需收口，露的是窗口兜底裁剪）
  private swipeClipShape(): PathShape | undefined {
    // 几何未就绪 → undefined = 不裁（露窗口兜底裁剪）。除卡高外**行宽也要挡**：行宽尚为 0
    //（转场首帧实测确有 0 宽的帧）或窄到装不下「左右让边 16 + 两侧圆角 20」时，路径会退化成
    // 负宽自交矩形，裁出来是一片空白——宁可退回方角窗口，也不让卡片凭空消失
    if (this.cardHeight <= 0 || this.rowW <= (SWIPE_GROUP_EDGE + CARD_RADIUS) * 2) {
      return undefined;
    }
    // ★ 单位坑（真机实锤）：Path 的 commands 走 **px**，不是 vp——直接拿 vp 数值写字面量时，
    // 3 倍屏上裁剪框只剩「左上角一小条」（80vp 高按 80px 裁 ≈ 27vp）。坐标与圆角一律经 vp2px 换算。
    const l: number = vp2px(SWIPE_GROUP_EDGE);
    const r: number = vp2px(CARD_RADIUS);
    const rt: number = vp2px(this.rowW - SWIPE_GROUP_EDGE);
    const b: number = vp2px(this.cardHeight);
    const cmds: string = `M${l + r} 0 H${rt - r} A${r} ${r} 0 0 1 ${rt} ${r} `
      + `V${b - r} A${r} ${r} 0 0 1 ${rt - r} ${b} H${l + r} `
      + `A${r} ${r} 0 0 1 ${l} ${b - r} V${r} A${r} ${r} 0 0 1 ${l + r} 0 Z`;
    return new PathShape({ commands: cmds });
  }

  // 行本体（卡片层 + 操作键层 + 行宽/行高实测 + 横滑手势）：普通态与多选态共用同一份，
  // 差异只在 build 是否给外层挂长按菜单（条件渲染两分支，避免多选勾选中误弹菜单）
  @Builder
  RowLayer() {
    // 外层：满宽裁剪层（裁切线 = 屏宽）——按键只在最外侧这里自然出屏；卡片左右缘改由内层
    // 收口窗口管（见下）
    Stack({ alignContent: Alignment.TopStart }) {
      // ★ 卡片收口窗口（2026-11-01 圆角分割线笔）：满幅静态窗口（宽 = 行宽、圆角
      // CARD_RADIUS、高 = 卡高），**不随位移**——卡片层在窗口内平移、越出部分按窗口轮廓裁切，
      // 左右两端因此恒为圆角，不再被屏缘直切成方头。只包卡片层：键层留在窗口外（键不被裁、
      // 坐标原点仍是行左上角），横滑手势仍挂在最外层 Stack（本窗口不接管手势）
      Column() {
        // 卡片层（跟手平移；卡片自带不透明底）。遮罩必须放在本层内：只盖卡片视觉宽，
        // 不挡右侧按键点击
        Column() {
          Stack() {
            SessionCardItem({
              ri: this.ri,
              selectMode: this.selectMode,
              selected: this.selected,
              unread: this.unread,
              appColorMode: this.appColorMode,
              cardAlphaLevel: this.cardAlphaLevel,
              onOpen: (row: ConversationRow): void => {
                this.onOpen(row);
              },
              onToggle: (id: string): void => {
                this.onToggle(id);
              }
            })
            // 点按遮罩（常驻、宽 = 卡片视觉宽）：收起态 hitTest None 全穿透（卡片与卡内键
            // 照常点）；展开/滑动中切 Default——点卡片任意处先收起，不误进会话、不误触卡内键。
            // ★ 宽度取 CARD_PANEL_WIDTH 而非 100%：操作键在卡片视觉宽之外（两向键区都在卡缘
            // 外），取 100% 会盖住操作键；高度取实测值（禁用百分比）
            if (this.cardHeight > 0) {
              Column()
                .width(CARD_PANEL_WIDTH)
                .height(this.cardHeight)
                .hitTestBehavior(this.selectMode || this.offsetX === 0 ?
                  HitTestMode.None : HitTestMode.Default)
                .onClick((): void => {
                  this.springTo(0);
                })
            }
          }
          .width('100%')
        }
        // ★ 本层保持满幅原样（width 100%）：★ 首版曾按窗口宽 +32 反补、再左移 16 把卡片
        // 钉回 16..行宽−16，真机实测卡片被压窄 ~22vp、卡内徽章左移贴边、键与卡缘间距走形
        //（官方行卡内部 16×2 自留与反补量不叠加，补偿前提不成立）——已回退，禁再上补偿写法
        .width('100%')
        // 卡片高度实测（本行唯一几何来源；差值阈值防亚像素抖动反复回写）
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const h: number = newArea.height as number;
          if (Math.abs(h - this.cardHeight) > 0.5) {
            this.cardHeight = h;
          }
        })
        // 卡片层命中档：收起态 Default（挡按键区、防点卡片右缘 16 边距误触）；展开态
        // Transparent（按键在上层，卡层不阻塞按键点击）
        .hitTestBehavior(this.selectMode || this.offsetX === 0 ?
          HitTestMode.Default : HitTestMode.Transparent)
        .translate({ x: this.offsetX })
      }
      .width('100%')
      .borderRadius(CARD_RADIUS)
      // 兜底裁剪：按窗口轮廓（= 屏缘）+ 圆角——形状裁剪万一不生效，退回二版屏缘观感，
      // 不会出现卡片压住键或滑出无裁的裸奔态
      .clip(true)
      // ★ 收口形状裁剪（三版）必须挂在 .clip(true) **之后**：两者同属裁剪属性，后挂者覆盖
      // 前挂者的裁剪区域——挂前面会被布尔裁剪盖掉，真机复现为「切边仍落在屏缘」。
      // 形状 = 卡片静止位圆角矩形（见 swipeClipShape），未实测卡高前 undefined = 不裁
      .clipShape(this.swipeClipShape())

      // 操作键层（四键：左滑露「重命名/移动/删除」，右滑露「收藏」；键位几何、形制与
      // 草稿行灰态全在拆件，本层只传位移与实测尺寸 + 四个动作上行）
      if (!this.selectMode && this.cardHeight > 0) {
        SessionSwipeKeys({
          offsetX: this.offsetX,
          side: this.keysSide,
          cardHeight: this.cardHeight,
          rowW: this.rowW,
          item: this.ri.item,
          draftRow: this.draftRow,
          onFavorite: (row: ConversationRow): void => {
            this.onFavorite(row);
          },
          onRename: (row: ConversationRow): void => {
            this.onRename(row);
          },
          onMove: (row: ConversationRow): void => {
            this.onMove(row);
          },
          onDelete: (row: ConversationRow): void => {
            this.onDelete(row);
          },
          onSettle: (): void => {
            this.springTo(0);
          }
        })
      }
    }
    .width('100%')
    // 行宽实测（键位左缘的单源；首帧用屏宽，分屏 / 窄栏在此订正）
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: number = newArea.width as number;
      if (Math.abs(w - this.rowW) > 0.5) {
        this.rowW = w;
      }
    })
    .clip(true)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
        .onActionStart((): void => {
          this.handlePanStart();
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.handlePanUpdate(event);
        })
        .onActionEnd((event: GestureEvent): void => {
          this.handlePanEnd(event);
        })
        .onActionCancel((): void => {
          this.handlePanCancel();
        })
    )
  }

  // 长按菜单参数桥：全局菜单 @Builder 无组件实例，数据与四个动作在这里按「按下当刻」的
  // 行对象现场组装（星标/收藏态即取即准，与旧 openCardMenu 的 menuCallbacks 同职责）
  private menuParams(): SessionCardMenuCallbacks {
    const params: SessionCardMenuCallbacks = {
      item: this.ri.item,
      onDelete: (row: ConversationRow): void => {
        this.onDelete(row);
      },
      onRename: (row: ConversationRow): void => {
        this.onRename(row);
      },
      onMove: (row: ConversationRow): void => {
        this.onMove(row);
      },
      onToggleFavorite: (row: ConversationRow): void => {
        this.onFavorite(row);
      }
    };
    return params;
  }

  // 长按菜单内容（CustomBuilder 只做调用，声明式组件在全局 @Builder 内）
  @Builder
  CardMenu() {
    SessionCardMenuBuilder(this.menuParams())
  }

  build() {
    if (this.selectMode) {
      // 多选态不挂长按菜单：勾选中长按误弹菜单会与批量条/勾选语义打架（原更多键也在多选
      // 态隐藏，判据同源）；横滑层本身在多选态已整层退役
      Column() {
        this.RowLayer()
      }
      .width('100%')
    } else {
      Column() {
        this.RowLayer()
      }
      .width('100%')
      // 长按 = 标准官方上下文菜单（2026-10-30 反馈轮 6~7 去预览浮起）：无预览卡、无蒙层；
      // 锚点固定 = 卡片左下角下方 8vp（卡高实测值传入），不跟触点。参数与材质在拆件
      // SessionCardMenu.ets；options 的 aboutToAppear（动效前）先把横滑展开态归位，
      // 避免菜单挂着一个已滑开的行
      .bindContextMenu(this.CardMenu, ResponseType.LongPress,
        sessionCardMenuOptions(this.immersiveLevel, (): void => {
          this.springTo(0);
        }, this.cardHeight))
    }
  }
}

// ═══ 会话列表容器（Scroll+Column+ForEach → List+Repeat）═══
// 容器参数 = List({ space: CARD_SPACING }) + edgeEffect Spring（短内容可拖拽回弹，坑76）+
// scrollBar Off（对齐原 Scroll 无滚动条观感）+ cachedCount（可视区外预创建缓冲）。头尾让位
// 走 List 的 contentStartOffset / contentEndOffset（自首末行 padding 改——官方内容轨随内容
// 滚、不进 ListItem 几何；padding 式让位会把首行侧滑按钮区拉成顶到屏顶的超长矩形）。读取
// 失败提示行 = 随末卡尾行（>0 行）/ 0 行时由壳侧兜底渲染（Repeat 无行可挂——壳侧同常量定位）。
@ComponentV2
export struct SessionRows {
  // 可见行（壳侧已按「全部/收藏」分段过滤；构造处经 UIUtils.enableV2Compatibility 传入
  //——Repeat 懒加载要求数据源具 V2 观察能力，见文件头机制①；行型 = SessionListRow〔DB 行 +
  // 生成中标记〕——loading 随行整体替换流动，见该接口注释）
  @Param visibleRows: SessionListRow[] = [];
  // 读取失败提示行（壳侧 hintText；>0 行时随末卡尾行渲染——定位同原 Scroll 内容尾部）
  @Param hintText: string = '';
  // 顶部让位（vp，宿主 titleBarInset 下发：内容区延伸到标题栏背后，首卡静止时完整落在
  // 渐变模糊蒙层下方）
  @Param topPad: number = 0;
  // 顶部额外让位（vp）：分段胶囊在标题栏覆盖层内，无带可让，只留呼吸间距——真值归壳侧
  // 单源常量 ChatSessionList.TITLE_BAR_ROWS_GAP = 8（构造处恒传，本件只认参数，同 topPad
  // 契约）；多选态恒 0（selectMode 三目在 contentStartOffset 处）。缺省 8 与壳侧常量同值
  @Param topClearance: number = 8;
  // 底部留白（vp，宿主下发——悬浮页签让位；多选中另加批量条让位）
  @Param bottomPad: number = 0;
  @Param selectMode: boolean = false;
  // 选中会话 id（逐行判 selected——点卡片切换勾选，勾选圈随 @Param 传播刷新）
  @Param selectedIds: string[] = [];
  // 主动消息未读会话 id（逐行判 unread = id 相等；多选互斥在卡片内）
  @Param unreadConvId: string = '';
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（同 appColorMode 链下发——透传 SessionSwipeItem → SessionCardItem）
  @Param cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 沉浸光感档位（长按菜单背板材质随总档——壳侧 @StorageProp 订阅后标量下发）
  @Param immersiveLevel: number = 0;
  // 事件两枚（透传壳侧回调——箭头函数形态；触摸预载已随 ChatHistoryPreload 整件退役）
  @Event onOpen: (row: ConversationRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };
  // 四个动作（侧滑四键与长按菜单共用同一批，壳侧动作方法零分叉）：收藏 = 切换收藏态
  //（壳侧 toggleFavorite），删除 = 确认弹窗 + 级联删除，其余两项 = 重命名弹窗 / 移动半模态。
  // 四事件只上行，不在此执行业务。
  @Event onFavorite: (row: ConversationRow) => void = () => {
  };
  @Event onRename: (row: ConversationRow) => void = () => {
  };
  @Event onMove: (row: ConversationRow) => void = () => {
  };
  @Event onDelete: (row: ConversationRow) => void = () => {
  };
  // 滚动起止上行：壳侧在滑动期间推迟整表重查与快照赋值，停止后合并补跑
  @Event onScrollingChanged: (scrolling: boolean) => void = () => {
  };

  // 当前展开行 id（侧滑互斥单源）：行开始滑动时上行 id，上一行收到 swipeOwner 变化即弹簧
  // 归位；列表开始竖滚、可见集重算（切分段/多选/重拉）、进会话均置空
  @Local swipeOwner: string = '';

  // 行开始滑动：单源改本行 id（同一行重复开始值不变，@Monitor 不触发，无副作用）
  private beginSwipe(id: string): void {
    if (this.swipeOwner !== id) {
      this.swipeOwner = id;
    }
  }

  // 收起展开行（单源）：可见集重算与「进会话」两处调用——swipeOwner 置空后各行
  // @Monitor('swipeOwner') 弹簧归位（与竖滚收起同一条通道）
  private collapseSwipe(): void {
    if (this.swipeOwner !== '') {
      this.swipeOwner = '';
    }
  }

  // 可见集重算 → 收起展开行（1756 真机清单「切全部/收藏分段无残留」的落点）。切分段 /
  // 多选进出 / 重拉换行时，仍在场的行**对象引用不变**——Repeat 按 id 复用节点、行侧
  // @Monitor('ri.item') 不触发，展开位移会整段残留
  @Monitor('visibleRows')
  private onVisibleRowsChange(): void {
    this.collapseSwipe();
  }

  build() {
    List({ space: CARD_SPACING }) {
      Repeat<SessionListRow>(this.visibleRows)
        .each((ri: RepeatItem<SessionListRow>) => {
          ListItem() {
            // 保真层 Column：alignItems Center 保真写法（实锤：ListItem 子项不水平居中致
            // 窄卡整列左偏；卡片现恒撑满，居中语义无损保留）。首末让位已上移
            // List 内容轨，本层只剩卡片与读取失败提示行——侧滑按钮区高度 = 卡片高度
            Column() {
              // 合成行（'__new__'）与普通行同走侧滑层，draftRow 置灰除删除外三键（合成行不
              // 落库，重命名/移动/收藏都无对象，删除键走壳侧草稿确认链）；行内差异全在
              // draftRow 一参——该参同时管「三键灰态 + 长距右滑不派发 + 菜单前三项置灰」。
              // each 块内 collapseSwipe 先于 onOpen 出现的次序判据（372 组）随单分支自然保序
              SessionSwipeItem({
                ri: ri,
                selectMode: this.selectMode,
                selected: this.selectedIds.includes(ri.item.id),
                unread: ri.item.id === this.unreadConvId,
                appColorMode: this.appColorMode,
                cardAlphaLevel: this.cardAlphaLevel,
                immersiveLevel: this.immersiveLevel,
                draftRow: ri.item.id === NEW_DRAFT_KEY,
                swipeOwner: this.swipeOwner,
                onOpen: (row: ConversationRow): void => {
                  // 进会话即收回展开权（决明报障「拉出控件后进另一个会话再返回，原控件未
                  // 收起」）：push 期间本页仍在栈内、返回时 reload 结果常与当前相等（R2-a
                  // 跳过赋值，visibleRows 不换），行会停在展开态；收起必须发生在离开列表的
                  // 这一刻，不能指望返回时的重拉
                  this.collapseSwipe();
                  this.onOpen(row);
                },
                onToggle: (id: string): void => {
                  this.onToggle(id);
                },
                onFavorite: (row: ConversationRow): void => {
                  this.onFavorite(row);
                },
                onRename: (row: ConversationRow): void => {
                  this.onRename(row);
                },
                onMove: (row: ConversationRow): void => {
                  this.onMove(row);
                },
                onDelete: (row: ConversationRow): void => {
                  this.onDelete(row);
                },
                onSwipeBegin: (id: string): void => {
                  this.beginSwipe(id);
                }
              })
              if (ri.index === this.visibleRows.length - 1 && this.hintText !== '') {
                Text(this.hintText)
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_warning'))
                  .width('calc(100% - 32vp)')
                  .margin({ top: CARD_SPACING })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 会话 id（身份唯一；★ 交互态不塞键——Repeat 不做键变重建，刷新走 @Param 传播，
        // 见文件头机制③；重复键行为未定义，conversations.id 主键保证唯一）
        .key((row: SessionListRow): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 头/尾让位 = 官方内容轨（原首末行 padding 改此，见容器头注释）。首行多选档：多选中
    // 分段面收起（标题栏覆盖层 showSegment = false），让位同步归零防死空隙——与末行批量条
    // 档同族对称。常态让位吃 topClearance（壳侧 TITLE_BAR_ROWS_GAP = 8 呼吸间距）
    .contentStartOffset(this.topPad + (this.selectMode ? 0 : this.topClearance))
    .contentEndOffset(this.bottomPad + LIST_TAIL_GAP +
      (this.selectMode ? MULTISELECT_BAR_CLEARANCE : 0))
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .cachedCount(LIST_CACHED_COUNT)
    // 竖滚开始即收起展开行（原生 swipeAction 同款行为；自研层由 swipeOwner 单源驱动）。
    // 起止成对上行，壳侧重查与落快照只在滚动空闲时执行（官方 onScrollStop 含惯性停止）
    .onScrollStart((): void => {
      this.onScrollingChanged(true);
      if (this.swipeOwner !== '') {
        this.swipeOwner = '';
      }
    })
    .onScrollStop((): void => {
      this.onScrollingChanged(false);
    })
  }
}
