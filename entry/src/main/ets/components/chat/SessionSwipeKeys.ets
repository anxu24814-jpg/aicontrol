// 会话行侧滑操作键层（2026-10-30 自 ChatSessionRows.ets 拆出）：职责一句话 =「会话行的
// 滑出操作键——键位几何、四个键的形制与配色、显隐与灰态」。依赖单向（行卡容器 → 本件 →
// ChatDb 的 ConversationRow + Theme 的侧滑键色相表），不反向引列表件；不吃卡圆角（圆键
// 轮廓与卡角无关），无模块环（坑50 口径）。
//
// ★ 键位分工（决明 2026-10-30 拍板五键；2026-11-17 整体退役加密会话笔减为四键）：
//   左滑（卡片左移、露出卡片右侧）= 重命名 → 移动 → 删除，删除在最外侧；
//   右滑（卡片右移、露出卡片左侧）= 收藏（单键，原内嵌的加密键随功能退役撤除）。
//   长距甩动（原始手指位移过屏宽一半）仍对应最外侧一键：左向删除、右向收藏/取消收藏。
//
// 几何：圆形键径 40 / 键间距 6 / 贴卡间距 16（= 卡与屏幕边距，2026-11-05 决明拍板对齐）/
// 组边距 16（与卡片左右边距同线）、卡内垂直居中。键一律随卡片同移（x = 静态基准 + offsetX），
// 显隐按父级下发的挂载边分块条件渲染（收起态零键创建；挂载边比 offsetX 符号活得久一代——
// 归位动画跑完才卸，键才能原路划回去）。贴卡间距 = 卡屏边距 ⇒ 静止位键簇完全退到屏外
//（旧值 6 时压进屏内 10vp：稍微一滑键突然出现、回位留一截到归位动画结束才消失），滑入/
// 划出改为从屏缘连续进出。
// ★ 坐标必须在属性闭包内现算（见 keyLeft 注释）：位移经 @Builder 值参传入会在分支创建
// 时冻结，真机表现为「键定格在首次滑出位置、只剩半个键在屏内」。改值参即复发。
// 展开量按方向各算：右 1 键 = 56、左 3 键 = 148（= 贴卡间距 + 键数 × 键径 + (键数 − 1) ×
// 键间距；常量导出，父级手势层钳位、吸附与长距阈值同源消费——改键径/间距只动上面几个
// 常量，手势层零改动）。
//
// 灰态：草稿合成行（'__new__'）没有可重命名/移动/收藏的对象——除删除外三键取官方
// 置灰形制（comp_background_tertiary 底 + font_tertiary 字 + 无按压光效）且不派发，语义
// 与菜单项 enabled(false) 同族。常态底色：重命名/移动走 Theme.swipeKeyToneBg 分色表
//（数值单源在 Theme），收藏走官方强调蓝资源（HdsTabs 选中同源，2026-10-31 决明指令），
// 本件不写任何六位色值。
import { ConversationRow } from '../../common/store/ChatDb';
import { swipeKeyToneBg } from '../../common/Theme';

// ── 侧滑操作键几何（2026-10-30 改圆形图标键，高度不再对齐卡；同日两轮收窄至 40）──
// 键径 40（决明「再小些」定稿，48 → 40 收两档）＝卡高 80 的一半，也是官方最小可点热区
// 下限——再小图标会糊、点按容错变差。★ 键不再是「卡角的一层」，故不再与卡等高、也不再
// 引用 CARD_RADIUS：圆形由 ButtonType.Circle 保证，垂直居中在卡内（keyTop 现算），上下
// 各留 20vp；卡高变化只改留白，键径恒定。
// 键间距 6（随键径同比收窄）≈ 0.15 倍键径——圆键边缘收得快，间隙可比方角键更紧；
// 组边距 16 不变 = 卡片左右边距，展开到位时最外侧键缘仍贴屏 16。
// 贴卡间距 16（2026-11-05 决明拍板「靠近卡的控件与卡的间距 = 卡与屏幕边距」）：键随卡同移，
// 该间距 ≥ 卡屏边距才保证静止位键体全在屏外——旧值 6 时键簇静止位压进屏内 10vp，键层一挂载
// 就露一条、回位动画全程贴屏缘可见。库行层 RowSwipeDelete 同值同步（规范 §4.18 两侧同步
// 纪律）。
export const SWIPE_KEY_SIZE: number = 40;
export const SWIPE_KEY_GAP: number = 6;
export const SWIPE_GROUP_EDGE: number = 16;
// 贴卡间距 = 卡与屏幕边距（关系式不写字面量：边距调档时贴卡间距自动跟随）
export const SWIPE_KEY_INNER_GAP: number = SWIPE_GROUP_EDGE;
// 图标 22 ≈ 0.55 倍键径（参照图实测：图标 bbox 46×47px 对圆径 86px = **0.53~0.55**；旧值 18
// = 0.45 偏小一档，决明点名「图标内符号改大点」）；无文字——键义由图标与无障碍文案承载
const SWIPE_ICON_SIZE: number = 22;

// 两侧键数（改键数必须同步改 build 里的键个数与两个键区索引，父级钳位自动跟随）
export const SWIPE_RIGHT_KEY_COUNT: number = 3;
export const SWIPE_LEFT_KEY_COUNT: number = 1;
// 展开位移（vp）= 贴卡间距 + 键数 × 键径 + (键数 − 1) × 键间距——展开到位最外侧键缘仍贴屏
// SWIPE_GROUP_EDGE（已验算：右 56 = 16+1×40 / 左 148 = 16+3×40+2×6）
export const SWIPE_OPEN_RIGHT: number = SWIPE_KEY_INNER_GAP +
  SWIPE_LEFT_KEY_COUNT * SWIPE_KEY_SIZE + (SWIPE_LEFT_KEY_COUNT - 1) * SWIPE_KEY_GAP;
export const SWIPE_OPEN_LEFT: number = SWIPE_KEY_INNER_GAP +
  SWIPE_RIGHT_KEY_COUNT * SWIPE_KEY_SIZE + (SWIPE_RIGHT_KEY_COUNT - 1) * SWIPE_KEY_GAP;

// 键动作枚举（@Builder 入参只收标量与枚举，函数经本枚举在组件内派发——避免把回调
// 作为 @Builder 值传参）
enum SwipeKeyAction {
  FAVORITE,
  RENAME,
  MOVE,
  DELETE
}

@ComponentV2
export struct SessionSwipeKeys {
  // 滑组当前横向位移（vp；左负右正）：负 = 左滑露出右侧三键，正 = 右滑露出左侧一键
  @Param offsetX: number = 0;
  // 键层挂载边（-1 = 右侧三键、+1 = 左侧一键、0 = 不挂载）：由父级手势层按位移符号跟手
  // 下发、归位动画结束后才归 0——显隐不能直接挂 offsetX 符号（animateTo 当帧已是终值 0，
  // 键层会在收起动画的第一帧被销毁，观感 = 屏缘顿住后原地消失）。本件只认这个入参
  @Param side: number = 0;
  // 卡片实测高度（vp，父级 onAreaChange 回写）：只用于键层垂直居中（键径恒定，见 keyTop）
  @Param cardHeight: number = 0;
  // 行宽（vp，父级 onAreaChange 回写）：右侧键区起点的单源（分屏/平板窄栏自适应）
  @Param rowW: number = 0;
  // 行数据：只读星标态，决定收藏键的图标与文案（文案随当前态切换）
  @Param item: ConversationRow = {
    id: '', title: '', providerId: '', createdAt: 0, updatedAt: 0,
    titleSource: '', favorite: false
  };
  // 草稿合成行（'__new__'）：除删除外三键置灰且不派发（原 favDisabled 语义扩宽——
  // 草稿不落库，重命名/移动/收藏均无对象，只有删除走草稿清链）
  @Param draftRow: boolean = false;

  // 四个动作一律上行，本件不执行业务（与壳侧 ChatSessionList 的同名方法一一对应）
  @Event onFavorite: (row: ConversationRow) => void = () => {
  };
  @Event onRename: (row: ConversationRow) => void = () => {
  };
  @Event onMove: (row: ConversationRow) => void = () => {
  };
  @Event onDelete: (row: ConversationRow) => void = () => {
  };
  // 点击任一键先归位（父级滑组弹簧回 0）：动作落库后会 reload 换行对象，行不该停在划出态；
  // 归位先于动作派发（与原两键 onClick 的 springTo(0) → 动作 次序一致）
  @Event onSettle: () => void = () => {
  };

  // 卡片视觉宽（vp）= 行宽 − 左右边距（官方行卡吃容器宽、内部自留 16×2，故这一步与父级
  // cardPanelW 同式——两侧各自算同一值，避免跨件传中间量）
  private cardPanelW(): number {
    return Math.max(this.rowW - SWIPE_GROUP_EDGE * 2, 0);
  }

  // 右侧键区某键左缘：innerIndex 0 = 贴卡片右缘的重命名键、2 = 最外侧的删除键（贴卡那份
  // 间距用 SWIPE_KEY_INNER_GAP，键与键之间用 SWIPE_KEY_GAP）
  private rightKeyX(innerIndex: number): number {
    return SWIPE_GROUP_EDGE + this.cardPanelW() + SWIPE_KEY_INNER_GAP
      + innerIndex * (SWIPE_KEY_SIZE + SWIPE_KEY_GAP) + this.offsetX;
  }

  // 左侧键区某键左缘：innerIndex 0 = 贴卡片左缘的收藏键（左侧单键）
  private leftKeyX(innerIndex: number): number {
    return SWIPE_GROUP_EDGE + this.offsetX - SWIPE_KEY_INNER_GAP - SWIPE_KEY_SIZE
      - innerIndex * (SWIPE_KEY_SIZE + SWIPE_KEY_GAP);
  }

  // 键上缘（vp）：卡内垂直居中——键径恒定、不随卡高，卡高只改上下留白（夹 0 防首帧负值）
  private keyTop(): number {
    return Math.max((this.cardHeight - SWIPE_KEY_SIZE) / 2, 0);
  }

  // 键动作派发（枚举 → 上行事件；本件不碰业务）
  private dispatch(action: SwipeKeyAction): void {
    if (action === SwipeKeyAction.RENAME) {
      this.onRename(this.item);
      return;
    }
    if (action === SwipeKeyAction.MOVE) {
      this.onMove(this.item);
      return;
    }
    if (action === SwipeKeyAction.FAVORITE) {
      this.onFavorite(this.item);
      return;
    }
    this.onDelete(this.item);
  }

  // 键左缘（vp）：按动作反查槽位现算——★ 必须留在属性闭包内取值（闭包内读 this.offsetX
  // 才建立刷新依赖）。真机实锤：坐标若经 @Builder 值参传入，值参在方向分支创建那一刻就
  // 冻结，此后每帧 offsetX 都推不进 Button 属性 → 键定格在首次滑出的位置（屏内只剩最
  // 内侧键半个边），卡片照常平移、其余键看不见也点不了。改回值参即复发。
  private keyLeft(action: SwipeKeyAction): number {
    if (action === SwipeKeyAction.FAVORITE) {
      return this.leftKeyX(0);
    }
    if (action === SwipeKeyAction.MOVE) {
      return this.rightKeyX(1);
    }
    if (action === SwipeKeyAction.DELETE) {
      return this.rightKeyX(2);
    }
    return this.rightKeyX(0);
  }

  // 灰态判据（草稿合成行除删除外三键置灰，删除走草稿清链恒可点）——同 keyLeft，闭包内现读
  private keyDisabled(action: SwipeKeyAction): boolean {
    return this.draftRow && action !== SwipeKeyAction.DELETE;
  }

  // 键配色档位（0 橙 / 1 黄 / 2 绿，色值照抄决明给的参照图）：按动作语义分配——重命名 0 橙
  //（改名）/ 移动 1 黄（位移）。★ 收藏不占本表（2026-10-31 决明「收藏键改成 HdsTab 选中时
  // 那种蓝色」→ 官方强调蓝资源，见 keyBg 的 FAVORITE 分支）；删除亦不在本表（破坏性语义走
  // 系统警告红）；2 绿档原属加密键，已随功能退役无键可达，保留为新增键兜底
  private keyTone(action: SwipeKeyAction): number {
    if (action === SwipeKeyAction.RENAME) {
      return 0;
    }
    if (action === SwipeKeyAction.MOVE) {
      return 1;
    }
    // 兜底 = 绿档（当前无键可达；FAVORITE/DELETE 已在 keyBg 前置分支处理）
    return 2;
  }

  // 键底色四路（禁用灰 / 删除警告红 / 收藏强调蓝 / 其余走三色相分色表）。显式标 ResourceColor：
  // 三条分支分别是 Resource 与 string，写在三元里会让推断类型漂移——抽成方法把并集钉在签名上，
  // 也便于断言钉按「一处取值」核验。同 keyLeft，必须在属性闭包内调用（读 this.draftRow）。
  // ★ 收藏蓝 = sys.color.ohos_id_color_emphasize（系统强调色，HdsTabs 页签选中同源、深浅随
  //   系统）——本件唯一一处该资源，其余三键禁回单一强调蓝
  private keyBg(action: SwipeKeyAction): ResourceColor {
    if (this.keyDisabled(action)) {
      return $r('sys.color.comp_background_tertiary');
    }
    if (action === SwipeKeyAction.DELETE) {
      return $r('sys.color.ohos_id_color_warning');
    }
    if (action === SwipeKeyAction.FAVORITE) {
      return $r('sys.color.ohos_id_color_emphasize');
    }
    return swipeKeyToneBg(this.keyTone(action));
  }

  // 键形制单源（四个键只差图标/色阶档/位置/方向）：圆形实底、只有图标（无文字，键义由图标
  // 承载、无障碍名走 accessibilityText），按压态由 stateEffect 提供；禁用态换官方灰底灰字且
  // 无按压光效。可见性不在这里判——build 按挂载边分块条件渲染，块内键恒可见。入参只收逐键
  // 恒定的三项，凡是随位移/行态变化的（坐标、上下留白、灰态、底色）一律在属性闭包内现算
  // （见 keyLeft / keyBg）
  @Builder
  SwipeKey(icon: Resource, label: string, action: SwipeKeyAction) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon)
        .fontSize(SWIPE_ICON_SIZE)
        .fontColor([this.keyDisabled(action) ? $r('sys.color.font_tertiary') :
          $r('sys.color.font_on_primary')])
    }
    .width(SWIPE_KEY_SIZE)
    .height(SWIPE_KEY_SIZE)
    .padding(0)
    .backgroundColor(this.keyBg(action))
    .stateEffect(!this.keyDisabled(action))
    // 键随卡同移（x = 静态基准 + offsetX，现算）、卡内垂直居中（y 现算）
    .position({ x: this.keyLeft(action), y: this.keyTop() })
    // 无文字形态的无障碍名（读屏按此处播报，图标本身不提供语义）
    .accessibilityText(label)
    .onClick((): void => {
      this.onSettle();
      if (!this.keyDisabled(action)) {
        this.dispatch(action);
      }
    })
  }

  build() {
    // 零尺寸定位基准：四键一律 position 绝对定位，坐标原点 = 行的左上角（父级 Stack 以
    // TopStart 排列本件）；宽高 0 不占列表布局，越界部分由父级 clip(true) 按行裁切。
    // 显隐按挂载边分块条件渲染：负向（左滑）只建右侧三键、正向（右滑）只建左侧一键，
    // 收起态零键创建。★ 判据只能是挂载边，不能是 offsetX 符号——理由见 side 注释
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.side < 0) {
        this.SwipeKey($r('sys.symbol.square_and_pencil'), '重命名', SwipeKeyAction.RENAME)
        this.SwipeKey($r('sys.symbol.arrowshape_right'), '移动', SwipeKeyAction.MOVE)
        this.SwipeKey($r('sys.symbol.trash'), '删除', SwipeKeyAction.DELETE)
      }
      if (this.side > 0) {
        this.SwipeKey(this.item.favorite ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
          this.item.favorite ? '取消收藏' : '收藏', SwipeKeyAction.FAVORITE)
      }
    }
    .width(0)
    .height(0)
  }
}
