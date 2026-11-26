// 行级左滑删除横滑层（2026-10-25 四库左滑笔新建共享件）——职责一句话 =「列表行的左滑手势
// 与删除键层——滑组平移、展开吸附、长距直达删除、行间展开互斥」。消费方 = 提示词库
// PromptLibRows / 技能库 SkillLibRows / 知识库书页 BookCard / 知识库条目页 KnowledgeBookRows /
// 记忆库 MemoryLibraryRows 五面（为何独立成件不能并入：五面分属四文件三种容器机制〔Repeat V2 /
// ForEach / LazyForEach V1〕，并入任一页都会造成跨页反向依赖；会话层 ChatSessionRows 在
// chat 域且近千行，本笔禁顺手重构会话页）。
// 交互基准 = 会话页 SessionSwipeItem（ChatSessionRows.ets 头注释「侧滑笔~八笔」全口径）：
//   · 手势 PanGesture 方向锁 Horizontal、distance 8；1:1 跟手至展开量，超出极小阻尼回执；
//   · 松手吸附 = 位移过展开量 42% 或快速甩动（|velocityX| > 600），springMotion(0.32, 1)
//     临界阻尼零过冲归位/展开；展开态净反向回滑一律收起；
//   · 长距直达 = 本次手势指尖行程过屏宽一半，松手先归位再派发删除（与删除键同一条链）；
//   · 删除键 = 圆形实底键贴卡右缘随卡同移（2026-11-01 对齐笔与 SessionSwipeKeys 逐值同形制
//     ：径 40、图标 22 无文字、警告红底白图标、无障碍名 accessibilityText），收起态 Hidden
//     不绘制；点按遮罩盖卡面，展开态点卡先收起不透传行点击；
//   · 展开态是行内交互态（@Local），禁进任何容器的 Repeat/LazyForEach 键（键只写行 id，
//     会话页同口径）；行换绑 / swipeEnabled 翻 false 立即硬归位。
// 与会话层的机制差异（收敛面，勿照抄会话层三处实现）：
//   ① 只有左滑删除：库行无收藏语义，右滑仅跟手回弹、无按键无动作；
//   ② 几何 = 容器实测行宽（onAreaChange）+ cardInset 让位参推导，禁在卡层上直接实测卡宽
//     ——卡层恒满宽、卡是其内居中的窄卡，实测会量成整行宽；cardInset = 卡左右各让位量
//     （卡宽 CARD_PANEL_WIDTH 居中的页面传 16，卡体满宽的记忆库传 0——MemoryLibraryRows
//     §4.8「卡宽 = 条目宽」两处同值约束的镜像）；会话层常量式（静止位键左缘 = 行宽）依赖「卡宽恒
//     CARD_PANEL_WIDTH」不适用五面，故参数化；
//   ③ 行间互斥不经父级 @Param 单源：LazyForEach 行级刷新是键驱动的（键不变不重建、参数
//     传播不进行内），改 SwipeGroup 登记组——行起手登记自己的归位回调，容器在滚动开始 /
//     可见集重算 / 进入多选时 collapse()；行销毁 release(rowId) 对称清登记（防悬空回调
//     持有已亡行）；
//   ④ 收口窗口与会话层同构（2026-11-01 对齐笔，两千零六十一节三版定形）：卡片层外套满宽
//     静态窗口（borderRadius + clip(true) 兜底 + clipShape 圆角矩形定形），滑出时按「卡片
//     静止位圆角矩形」收口，切边恒在卡原位、两端恒圆角（旧观感 = 被视口直切成方头）。
//     ★ 差异④旧口径「不自挂裁剪」已作废——旧顾虑是「外层自裁在列表边距竖切」，新窗口只包
//     卡片层且形状按 cardX/cardW 现算（居中页 16..行宽−16、记忆库满宽 0..行宽），不依赖承载
//     容器宽度；删除键层仍在窗口外不被裁。真机三坑（clipShape 后挂 / px 单位 / 越零死区）
//     与会话层同款，防回流钉在 assert-ui-shape（库行侧滑组）。
// 拖拽共存（记忆库 LazyForEach.onMove 长按拖拽）：快横滑 = PanGesture（位移 ≥8vp 才识别）、
// 长按再拖 = 官方拖拽（按住 500ms 才浮起），两手势按类型天然互斥；共存观感待真机验证
// （BLOCKED 同笔真机清单）。
import { curves, display, PathShape } from '@kit.ArkUI';
import { CARD_RADIUS } from '../common/Theme';

// ── 侧滑操作键几何（2026-11-01 对齐笔：与 ChatSessionRows.SessionSwipeKeys 逐值同形制）──
// ★ 圆形键（ButtonType.Circle）径 40 = 卡高 80 的一半，也是官方最小可点热区下限——再小
// 图标会糊、点按容错变差（会话键同判据，规范 §4.18「再小不批」）。图标 22 ≈ 0.55 倍键径
//（会话键同档），无文字——键义由图标与无障碍文案承载。
// ★ 原「SWIPE_KEY_RADIUS 引 CARD_RADIUS、键高恒等卡高」的方键口径随对齐笔退役——圆键没有
// 圆角参数，圆由 ButtonType.Circle 保证，垂直居中在卡内（keyTop 现算，上下各留 20），
// 不再与卡等高、不再引 CARD_RADIUS。
// 贴卡间距 16（2026-11-05 对齐拍板「靠近卡的控件与卡的间距 = 卡与屏幕边距」，与会话层
// SessionSwipeKeys.SWIPE_KEY_INNER_GAP 同值同步）——单键无键间间距，旧名 SWIPE_KEY_GAP(6)
// 就是贴卡间距，随拍板改值改名；静止位键体全在屏外（旧值 6 时居中页键压进屏内 10vp，起手
// 露一条、回位留一截）。展开量 = 贴卡间距 + 键径 56，展开到位键右缘与卡片原位右缘同线
//（居中页 / 满宽页均已验算与旧几何逐值一致）。
// 反向收起阈值 SWIPE_BACK_MIN 6（旧实现借贴卡间距常量表达，2026-11-05 独立保值——那 6vp
// 是收起灵敏度手感，不随贴卡间距走；会话层同义常量 SWIPE_BACK_MIN 同值）。
const SWIPE_KEY_SIZE: number = 40;
const SWIPE_KEY_INNER_GAP: number = 16;
const SWIPE_BACK_MIN: number = 6;
const SWIPE_ICON_SIZE: number = 22;
// 展开位移 = 贴卡间距 + 一枚键径
const SWIPE_OPEN_OFFSET: number = SWIPE_KEY_INNER_GAP + SWIPE_KEY_SIZE;
// 展开量之外的手指行程只做「还能再拉」的阻尼回执（上限 10vp，卡不离键）
const SWIPE_OVER_DRAG_DAMP: number = 0.08;
const SWIPE_OVER_DRAG_MAX: number = 10;
// 吸附 / 惯性 / 长距判据（会话层七笔口径：长距按本次手势指尖行程过屏宽一半）
const SWIPE_OPEN_RATIO: number = 0.42;
const SWIPE_FLING_VELOCITY: number = 600;
const SWIPE_LONG_RATIO: number = 0.5;
// 回位死区（vp，2026-11-01 对齐笔与会话层两千零六十二节同源同值）：起手不在原位的手势回到
// 原位附近时，先吃掉一段死区再从 0 连续起算——手动拖回的指尖过冲不产生位置跳变、状态也不在
// 零位移处翻转（本层右滑无按键，死区主要承接「拖回原位停一下再反向拉」的手感与会话页一致）
const SWIPE_RETURN_DEAD: number = 24;

// 行间展开互斥组（每列表一个，容器单源下发）：行起手 requestExpand 登记归位回调并收起
// 上一行；容器在滚动开始 / 可见集重算 / 进入多选时 collapse()；行销毁 release 对称清登记。
// 纯命令式回调组，零状态观察依赖——V1 LazyForEach 与 V2 Repeat 两种容器下行为一致。
export class SwipeGroup {
  private expandedId: string = '';
  private collapseFn: (() => void) | null = null;

  // 行开始横滑（PanGesture onActionStart）：收起上一行（若有且不是自己）并登记自己。
  // 同行重复起手值不变（展开态继续滑是常态，不得自收）
  requestExpand(id: string, collapse: () => void): void {
    if (this.expandedId !== id && this.collapseFn !== null) {
      this.collapseFn();
    }
    this.expandedId = id;
    this.collapseFn = collapse;
  }

  // 容器侧收口（滚动开始 / 可见集重算 / 进入多选）：收起当前展开行并清登记
  collapse(): void {
    if (this.collapseFn !== null) {
      this.collapseFn();
    }
    this.expandedId = '';
    this.collapseFn = null;
  }

  // 行销毁对称清理（RowSwipeDelete.aboutToDisappear 调用）：只清自己的登记，
  // 防悬空回调持有已亡组件（寿命匹配红线）
  release(id: string): void {
    if (this.expandedId === id) {
      this.expandedId = '';
      this.collapseFn = null;
    }
  }
}

@ComponentV2
export struct RowSwipeDelete {
  // 行身份（互斥登记键 + 删除事件载荷；Repeat/LazyForEach 键 = 行 id，同节点 rowId 恒定，
  // @Monitor 兜极端换绑序）
  @Require @Param rowId: string;
  // 左滑删除可用位：false = 内置行 / 多选态等不可删形态——整层退化为纯内容直出（手势
  // 回调早退、按键层不渲染、遮罩不拦截），行卡本体照旧渲染
  @Param swipeEnabled: boolean = true;
  // 卡左右让位量（vp）：卡宽 CARD_PANEL_WIDTH 在满宽行内居中的页面传 16（卡宽 = 行宽 − 32、
  // 卡左缘 = 16，与会话层常量式逐值等价）；卡体满宽（记忆库「卡宽 = 条目宽」）传 0。
  // 几何推导单源，勿在消费方另写偏移
  @Param cardInset: number = 16;
  // 互斥组（容器单源下发；漏传时默认自组 = 退化为无互斥，功能不损）
  @Param group: SwipeGroup = new SwipeGroup();
  // 行卡内容（各渲染域 @Builder 传入——本层只管手势与按键，行内容零知识）
  @BuilderParam content: () => void;
  // 长距直达 / 删除键点按共用一条链（先归位再上行，弹各页既有删除确认框）
  @Event onSwipeDelete: (id: string) => void = () => {
  };

  // 滑组当前横向位移（vp；负 = 左滑展开删除键，上限 −SWIPE_OPEN_OFFSET；右滑无按键，
  // 仅跟手回弹）
  @Local offsetX: number = 0;
  // 内容卡实测高（遮罩与按键的高度单源；禁 height('100%')——会话层四笔实锤：Stack 未定高
  // 时百分比子项按视口解析成贯穿色条）
  @Local cardHeight: number = 0;
  // 行宽实测（卡宽/卡左缘推导基数；首帧用屏宽，分屏/窄栏在 onAreaChange 订正）
  @Local rowW: number = 0;
  // 屏宽（长距阈值基数；分屏 / 横屏支持时改 onAreaChange 按行宽重算——会话层同注）
  private screenW: number = 360;
  // 本次手势起点位移（展开态再滑的基线）
  private dragStart: number = 0;
  // 本次手势指尖行程（恒以手势起点为原点，不含 dragStart——长距判据只认本次手势拉了多少，
  // 会话层五笔自检修正口径）
  private dragPos: number = 0;
  // 本次手势的主轴方向（+1 右 / −1 左 / 0 未定）：收起态起手取首次显著行程的方向，用于判
  // 「反向越零」（见 SWIPE_RETURN_DEAD）；展开态起手直接用 dragStart 的符号，不读本字段
  private dragDir: number = 0;
  // 行换绑兜底（复用节点 @Local 不重置，起手发现 id 变了先归位——会话层同款保险）
  private boundId: string = '';

  aboutToAppear(): void {
    this.screenW = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
    this.rowW = this.screenW;
    this.boundId = this.rowId;
  }

  aboutToDisappear(): void {
    this.group.release(this.rowId);
  }

  // 卡片视觉宽（vp）= 行宽 − 左右让位。居中页（cardInset 16）与会话层 cardPanelW 逐值等价；
  // 满宽页（cardInset 0）= 条目宽（MemoryLibraryRows §4.8 拖拽快照轮廓约束）
  private cardW(): number {
    return Math.max(this.rowW - this.cardInset * 2, 0);
  }

  // 卡片左缘（vp）= 让位量（居中页 = (行宽 − 卡宽)/2 = cardInset 恒等；满宽页 = 0）
  private cardX(): number {
    return this.cardInset;
  }

  // 删除键左缘（vp）= 卡片右缘 + 贴卡间距，随卡同移（x = 本值 + offsetX）；静止位该左缘
  // = 卡右缘外 16vp = 屏缘或更外、键体全在屏外（贴卡间距 = 卡屏边距，2026-11-05 对齐——
  // 旧值 6 时居中页键压进屏内 10vp），键用 Hidden 不绘制（会话层八笔口径）。展开到位
  //（offsetX = −SWIPE_OPEN_OFFSET）时键右缘 = 卡片原位右缘，与卡间留一贴卡间距（会话键
  // 同判据）
  private keyLeft(): number {
    return this.cardX() + this.cardW() + SWIPE_KEY_INNER_GAP;
  }

  // 键上缘（vp）：卡内垂直居中——键径恒定、不随卡高，卡高只改上下留白（夹 0 防首帧负值，
  // 会话键同式）
  private keyTop(): number {
    return Math.max((this.cardHeight - SWIPE_KEY_SIZE) / 2, 0);
  }

  // 收口形状（2026-11-01 对齐笔，会话层两千零六十一节三版同构）：**卡片静止位的圆角矩形**
  // ——左右各在 cardX / cardX + cardW、高 = 卡高实测、圆角 = CARD_RADIUS，用路径显式画
  //（Path 的坐标是绝对值，不依赖形状偏移语义：RectShape 的 offset 是否参与裁剪无官方明示，
  // 一步到位）。挂成窗口的裁剪形状后，卡片滑出时按此轮廓收口，切边位置**恒在卡片原位的
  // 左右端**（居中页 = 16..行宽−16、记忆库满宽 = 0..行宽），圆角半径与卡身同值，收口弧与
  // 卡自身圆角同形。
  // ★ 为什么用形状裁剪而不是把窗口收窄到卡缘：窗宽一改，卡内容会跟着二次变窄（会话层一版
  // 真机实锤：卡被压窄、键距走形），形状裁剪不碰任何布局。未实测卡高 / 卡宽装不下两侧圆角
  // 时返回 undefined = 不裁（首帧静止态本就无需收口，露的是窗口兜底裁剪）
  private swipeClipShape(): PathShape | undefined {
    // 几何未就绪 → undefined = 不裁（露窗口兜底裁剪）。除卡高外**卡宽也要挡**：卡宽装不下
    // 「两侧圆角」时路径退化成负宽自交矩形，裁出来是一片空白——宁可退回方角窗口，也不让
    // 卡片凭空消失
    if (this.cardHeight <= 0 || this.cardW() <= CARD_RADIUS * 2) {
      return undefined;
    }
    // ★ 单位坑（会话层真机实锤）：Path 的 commands 走 **px**，不是 vp——直接拿 vp 数值写
    // 字面量时，3 倍屏上裁剪框只剩「左上角一小条」。坐标与圆角一律经 vp2px 换算。
    const l: number = vp2px(this.cardX());
    const r: number = vp2px(CARD_RADIUS);
    const rt: number = vp2px(this.cardX() + this.cardW());
    const b: number = vp2px(this.cardHeight);
    const cmds: string = `M${l + r} 0 H${rt - r} A${r} ${r} 0 0 1 ${rt} ${r} `
      + `V${b - r} A${r} ${r} 0 0 1 ${rt - r} ${b} H${l + r} `
      + `A${r} ${r} 0 0 1 ${l} ${b - r} V${r} A${r} ${r} 0 0 1 ${l + r} 0 Z`;
    return new PathShape({ commands: cmds });
  }

  // 不可删形态接管（多选进入 / 内置行）：立即硬归位不走动画（多选换装是整页态变，
  // 会话层 onSelectModeChange 同口径）
  @Monitor('swipeEnabled')
  private onEnabledChange(): void {
    if (!this.swipeEnabled && this.offsetX !== 0) {
      this.offsetX = 0;
    }
  }

  // 行换绑：归位并重记身份（防旧位移挂在新行上）
  @Monitor('rowId')
  private onRowIdChange(): void {
    if (this.rowId !== this.boundId) {
      this.boundId = this.rowId;
      if (this.offsetX !== 0) {
        this.offsetX = 0;
      }
    }
  }

  // 归位 / 吸附单源：springMotion 临界阻尼 1.0 零过冲（会话层本笔口径——过冲会越过收起位
  // 把对侧键带出来；本层无对侧键，随会话层同值保守）
  private springTo(target: number): void {
    this.getUIContext().animateTo({ curve: curves.springMotion(0.32, 1) }, (): void => {
      this.offsetX = target;
    });
  }

  private handlePanStart(): void {
    if (!this.swipeEnabled) {
      return;
    }
    if (this.boundId !== this.rowId) {
      this.boundId = this.rowId;
      this.offsetX = 0;
    }
    this.dragStart = this.offsetX;
    this.dragPos = 0;
    this.dragDir = 0;
    // 互斥登记：收起上一行（组内判）并登记自己的归位回调（容器 collapse 的作用点）
    this.group.requestExpand(this.rowId, (): void => {
      this.springTo(0);
    });
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (!this.swipeEnabled) {
      return;
    }
    const raw: number = this.dragStart + event.offsetX;
    this.dragPos = event.offsetX;
    // 主轴方向：收起态起手取首次显著行程的方向（展开态起手用 dragStart 的符号，不读本字段）
    if (this.dragDir === 0 && Math.abs(event.offsetX) > SWIPE_RETURN_DEAD) {
      this.dragDir = event.offsetX > 0 ? 1 : -1;
    }
    // ★ 反向越零死区（见 SWIPE_RETURN_DEAD，会话层同款）：位移越过原点朝反方向去时，先吃掉
    // 一段死区再从 0 连续起算——手动拖回的指尖过冲不产生位置跳变（死区前后 0 → 0.1 连续，
    // 只是导数为 0 的停顿）
    let effective: number = raw;
    const ref: number = this.dragStart !== 0 ? (this.dragStart > 0 ? 1 : -1) : this.dragDir;
    const dirNow: number = raw > 0 ? 1 : (raw < 0 ? -1 : 0);
    if (ref !== 0 && dirNow === -ref) {
      effective = ref < 0 ? Math.max(0, raw - SWIPE_RETURN_DEAD) :
        Math.min(0, raw + SWIPE_RETURN_DEAD);
    }
    if (effective >= 0) {
      // 右滑（无动作向）：跟手至展开量即停、超出极小阻尼——与左滑同手感，松手必归位
      if (effective <= SWIPE_OPEN_OFFSET) {
        this.offsetX = effective;
        return;
      }
      const overRight: number = effective - SWIPE_OPEN_OFFSET;
      this.offsetX = SWIPE_OPEN_OFFSET +
        Math.min(overRight * SWIPE_OVER_DRAG_DAMP, SWIPE_OVER_DRAG_MAX);
      return;
    }
    if (effective >= -SWIPE_OPEN_OFFSET) {
      this.offsetX = effective;
      return;
    }
    // 过展开量即停（卡缘贴键），只留极小阻尼作「还能再拉」的回执
    const over: number = -effective - SWIPE_OPEN_OFFSET;
    this.offsetX = -SWIPE_OPEN_OFFSET - Math.min(over * SWIPE_OVER_DRAG_DAMP, SWIPE_OVER_DRAG_MAX);
  }

  private handlePanEnd(event: GestureEvent): void {
    if (!this.swipeEnabled) {
      return;
    }
    // 长距直达：本次手势指尖行程过屏宽一半 → 先归位再派发删除（行不停在划出态，
    // 会话层七笔口径）。★ 长距闸（会话层两千零六十二节同款）：只认「朝该向拉开」的手势
    // ——起手在右滑橡皮筋态（dragStart > 0）时，回撤整段路过左向阈值，不做删除派发
    const delArm: boolean = this.dragStart <= 0;
    if (delArm && this.dragPos <= -this.screenW * SWIPE_LONG_RATIO) {
      this.springTo(0);
      this.onSwipeDelete(this.rowId);
      return;
    }
    // 右滑无动作向：一律归位
    if (this.offsetX > 0) {
      this.springTo(0);
      return;
    }
    // 展开态净反向回滑（位移过 SWIPE_BACK_MIN 或反向甩动）一律收起，不再按吸附判据弹回
    if (this.dragStart < 0 &&
      (event.offsetX > SWIPE_BACK_MIN || event.velocityX > SWIPE_FLING_VELOCITY)) {
      this.springTo(0);
      return;
    }
    // 吸附判据（只左向）：位移过展开量 42% 或快速甩动即展开，否则归位
    const pull: number = Math.abs(this.offsetX);
    const flung: boolean = event.velocityX < -SWIPE_FLING_VELOCITY;
    const shouldOpen: boolean = pull > SWIPE_OPEN_OFFSET * SWIPE_OPEN_RATIO ||
      (flung && pull > 8);
    this.springTo(shouldOpen ? -SWIPE_OPEN_OFFSET : 0);
  }

  private handlePanCancel(): void {
    if (!this.swipeEnabled) {
      return;
    }
    this.springTo(0);
  }

  // 删除键（圆形实底，左滑呼出——2026-11-01 对齐笔与 SessionSwipeKeys 逐值同形制：径 40、
  // 图标 22 无文字、警告红底白图标、stateEffect 按压光效；键义由图标与无障碍文案承载，
  // 禁给圆键补 borderRadius 或写文字组件）。点击先收起再上行（弹所在页既有删除确认框）
  @Builder
  SwipeDeleteKeyBuilder() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(SWIPE_ICON_SIZE)
        .fontColor([$r('sys.color.font_on_primary')])
    }
    .width(SWIPE_KEY_SIZE)
    .height(SWIPE_KEY_SIZE)
    .padding(0)
    .backgroundColor($r('sys.color.ohos_id_color_warning'))
    .stateEffect(true)
    // 贴卡右缘外一个贴卡间距、随卡同移（展开到位时键右缘 = 卡片原位右缘）；卡内垂直居中
    //（y 现算，键径恒定不随卡高）
    .position({ x: this.keyLeft() + this.offsetX, y: this.keyTop() })
    // 收起态 / 右滑态整键不绘制（Hidden 保布局、不绘制、不受触摸——收起时键在卡右缘外
    // 会露弧边，会话层八笔同款机制）
    .visibility(this.offsetX < 0 ? Visibility.Visible : Visibility.Hidden)
    // 无文字形态的无障碍名（读屏按此处播报，图标本身不提供语义；会话键同款）
    .accessibilityText('删除')
    .onClick((): void => {
      this.springTo(0);
      this.onSwipeDelete(this.rowId);
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ★ 卡片收口窗口（2026-11-01 对齐笔，会话层同构）：满幅静态窗口（宽 = 行宽），**不随
      // 位移**——卡片层在窗口内平移、越出部分按窗口轮廓裁切，两端因此恒为圆角，不再被视口
      // 直切成方头。只包卡片层：删除键留在窗口外（键不被裁、坐标原点仍是行左上角），横滑
      // 手势仍挂在最外层 Stack（本窗口不接管手势）
      Column() {
        // 卡片层（跟手平移）。遮罩必须放在本层内随卡同移：只盖卡面视觉宽，不挡删除键
        Column() {
          Stack() {
            // 行卡内容（各渲染域行组件，本层零知识；width('100%') 恒定——卡宽收窄一律由
            // 卡自身既有宽度承担〔CARD_PANEL_WIDTH 或记忆库 100%〕，本层不改卡几何）
            Column() {
              this.content()
            }
            .width('100%')
            // 点按遮罩（常驻、盖卡面）：收起态 hitTest None 全穿透（行卡与卡内键照常点）；
            // 展开 / 滑动中切 Default——点卡任意处先收起，不误进行点击、不误触卡内键
            if (this.cardHeight > 0) {
              Column()
                .width(this.cardW())
                .height(this.cardHeight)
                .position({ x: this.cardX(), y: 0 })
                .hitTestBehavior(!this.swipeEnabled || this.offsetX === 0 ?
                  HitTestMode.None : HitTestMode.Default)
                .onClick((): void => {
                  this.springTo(0);
                })
            }
          }
          .width('100%')
        }
        // 行宽与卡高实测（本行唯一几何来源；差值阈值防亚像素抖动反复回写）。★ 卡宽禁在此
        // 实测——卡层恒满宽、卡是其内居中的窄卡，实测会量成整行宽（见文件头差异②）
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const h: number = newArea.height as number;
          if (Math.abs(h - this.cardHeight) > 0.5) {
            this.cardHeight = h;
          }
          const w: number = newArea.width as number;
          if (Math.abs(w - this.rowW) > 0.5) {
            this.rowW = w;
          }
        })
        // 卡片层命中档：收起态 Default（防点卡右缘外误触）；展开态 Transparent（按键在上层，
        // 卡层不阻塞删除键点击）
        .hitTestBehavior(!this.swipeEnabled || this.offsetX === 0 ?
          HitTestMode.Default : HitTestMode.Transparent)
        .translate({ x: this.offsetX })
      }
      .width('100%')
      .borderRadius(CARD_RADIUS)
      // 兜底裁剪：按窗口轮廓（= 承载容器缘）+ 圆角——形状裁剪万一不生效，退回视口观感，
      // 不会出现卡片压住键或滑出无裁的裸奔态
      .clip(true)
      // ★ 收口形状裁剪（定形）必须挂在 .clip(true) **之后**：两者同属裁剪属性，后挂者覆盖
      // 前挂者的裁剪区域——挂前面会被布尔裁剪盖掉（会话层真机实锤，观感 = 切边退回视口缘）。
      // 形状 = 卡片静止位圆角矩形（见 swipeClipShape），未实测卡高前 undefined = 不裁
      .clipShape(this.swipeClipShape())

      // 删除键层（不可删形态 / 未实测到卡高时不渲染）
      if (this.swipeEnabled && this.cardHeight > 0) {
        this.SwipeDeleteKeyBuilder()
      }
    }
    .width('100%')
    // 不自挂 clip：收口已由内层窗口按卡片原位定形（见文件头差异④）；外层自裁会把滑出卡在
    // 列表边距处竖切——收口切边必须落在卡片静止位，不是容器缘
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
}
