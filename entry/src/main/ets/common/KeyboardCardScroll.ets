// 编辑态「卡底滚动定位」单源件（2026-11-05 两千一百零二笔立，两千一百零三笔补键盘上沿口径）：
// 键盘弹起后把内容卡（连同卡底变量条的说明行）整体抬到键盘上沿之上。三页共用——提示词编辑页 /
// 系统提示词页 / 助手提示词页，各页只把 Scroll 与内容卡的 Area 喂进来，定位算式与时序在本件。
// 职责一句话 = 按实测位置把内容卡底边滚到键盘上沿上方。
// · 为什么不用 scrollEdge(Edge.Bottom)：滚到底只保证「滚动内容末尾」贴底。卡下面还有别的
//   块时（编辑页 = 注入方式卡 + 提示卡）内容卡会被推过头、卡顶出视口；卡是最后一块时
//  （两提示词页）又正好差一个视口底部让位（吸底键条 + 留白），说明行仍被键条压住——
//   两头都不准，故按卡底实测位置算偏移。
// · 为什么还要读键盘避让区（两千一百零三引入，两千一百零四修订依据）：切入 RESIZE 后实测
//   页底 = 键盘上沿，正常态两者等价；保留 min 是读数兜底——页底若因导航条内缩或分屏低于
//   键盘上沿，仍以键盘上沿为准。★ 2103 当时记的「页底比键盘上沿低十几 vp」前提已被 2104
//   实测推翻（那一轮页面根本没被压缩，视口 = 全高 813vp），不作常态依据。
// · 两千一百零四真机台账（关键一条）：全局 KeyboardAvoidMode.RESIZE_WITH_CARET 在这三页上
//   **并不压缩页面**（实测视口高仍 813vp = 全高，键盘只是盖在页面上）——于是 scrollTo
//   的目标偏移超不过最大可滚距离、被钳回 0，卡底与吸底键条都停在原位被遮。处方 = 三页在
//   聚焦时切官方 RESIZE（聊天页输入栏同款）、失焦与退页复原；页面压到键盘上沿后本件的
//   定位算式才有真实参照面。
// · 量的是 Area.globalPosition（窗口坐标）与键盘区 bottomRect.top（同坐标系 px），算的是
//   「卡底超出上沿多少」的相对量——与滚动内容多长、当前滚到哪、父列内距怎么算都无关。
//   重算触发面只有三种事件（编辑态切换 / 视口高变化 / 键盘高变化），滚动本身不触发重算，
//   故不会自激。
// · 时序：键盘动画期间视口高逐帧变化，故防抖 SETTLE 后再滚（终值才准）；聚焦首滚用更长的
//   KICK；键盘高度变化由窗口事件直接驱动重算（页面没被压缩的场景——外接键盘 / 平板——
//   也能到位）。
// · 生命周期：定时器 dispose() 成对释放；页面实例只在编辑态挂进广播表，失焦/退页即摘
//  （长寿命模块表不得持有短寿命页面件）。窗口键盘监听与广播表同寿命——表空即 off，
//  下次进编辑态再 on（与 ChatInputBar 的 on/off 成对同规）。
import { UIContext, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 诊断日志域与 tag（与聊天页同域；只在异常路径打，正常链零输出）
const KB_LOG_DOMAIN: number = 0xD5A0;
const KB_LOG_TAG: string = 'KCS';

// 卡底与键盘上沿的留白（vp）：键盘上沿压线时不至于贴死，卡底投影与键盘上沿之间留一线气
export const KEYBOARD_CARD_BOTTOM_MARGIN: number = 8;

// 视口底部补白（vp）：卡是滚动内容最后一块的页面（两提示词页）必须补这段——卡下方的
// 让位空间恰好等于吸底键条高，没有补白就只能滚到「卡底贴键条上沿」，MARGIN 永远拿不到
export const KEYBOARD_CARD_TAIL: number = 12;

// 聚焦首滚延时（ms）：等键盘压缩动画走完（系统键盘动画约 250ms）
const KEYBOARD_CARD_KICK_MS: number = 260;
// 视口高落定后的防抖（ms）：键盘动画逐帧改视口高，停稳后再算终值
const KEYBOARD_CARD_SETTLE_MS: number = 90;
// 定位滚动动画时长（ms）：短促滑入，不跟键盘动画抢时长
const KEYBOARD_CARD_SCROLL_MS: number = 180;
// 卡底已在上限之内（或已滚到位）的判据阈值（vp）：亚像素抖动不触发滚动
const KEYBOARD_CARD_SLACK: number = 1;
// 键盘区上沿读数的合理性容差（vp）：正常态页底与键盘上沿只差一档导航条高度（十几 vp）；
// 超出即判读数不可信（缺省 0 / 误给屏幕高 / 页面未被压缩），退回「视口底边 = 键盘上沿」口径
const KEYBOARD_CARD_RECT_GUARD: number = 64;

// ── 键盘上沿缓读（窗口对象进程内唯一：绑定一次，之后同步读避让区）──
let kbWindow: window.Window | null = null;
let kbUi: UIContext | null = null;
let kbBindAsked: boolean = false;
// 键盘监听是否在挂：与广播表非空同寿命（最后一个编辑页离开编辑态即 off）
let kbListening: boolean = false;
// 编辑态中的定位器广播表（失焦即摘，见 setEditing/dispose——不长期持有页面件）
const kbWatchers: Set<KeyboardCardScroller> = new Set<KeyboardCardScroller>();

// 单一回调引用：on/off 必须同一个引用，注销才生效
function onKeyboardHeightChange(_height: number): void {
  kbWatchers.forEach((watcher: KeyboardCardScroller): void => {
    watcher.onKeyboardChange();
  });
}

// 挂键盘监听（有窗口且有编辑页才挂；与 releaseKeyboardListener 成对）
function attachKeyboardListener(): void {
  if (kbWindow === null || kbListening) {
    return;
  }
  try {
    kbWindow.on('keyboardHeightChange', onKeyboardHeightChange);
    kbListening = true;
  } catch (err) {
    // 监听失败只降级为「除聚焦首滚外无键盘事件驱动」，定位仍可由视口高变化承接
    hilog.error(KB_LOG_DOMAIN, KB_LOG_TAG, 'keyboard listen failed: %{public}s', JSON.stringify(err));
  }
}

// 摘键盘监听（广播表空了才摘；失败只记日志，不把异常抛进页面退出链）
function releaseKeyboardListener(): void {
  if (kbWindow === null || !kbListening || kbWatchers.size > 0) {
    return;
  }
  try {
    kbWindow.off('keyboardHeightChange', onKeyboardHeightChange);
  } catch (err) {
    hilog.error(KB_LOG_DOMAIN, KB_LOG_TAG, 'keyboard unlisten failed: %{public}s', JSON.stringify(err));
  }
  kbListening = false;
}

// 页面 aboutToAppear 调一次：取主窗口（异步，不阻塞首帧）。监听不在这里挂——由首个进入
// 编辑态的定位器触发 attach，广播表空了即 off（成对释放）。
export function bindKeyboardAvoidArea(ui: UIContext): void {
  if (kbBindAsked || kbWindow !== null) {
    return;
  }
  const host = ui.getHostContext();
  if (host === undefined) {
    // 宿主未就绪：不置位，下一次进页重试（置位会让后续页面永远拿不到键盘上沿读数）
    return;
  }
  kbBindAsked = true;
  kbUi = ui;
  window.getLastWindow(host).then((win: window.Window): void => {
    kbWindow = win;
    attachKeyboardListener();
  }).catch((err: Error): void => {
    // 取不到窗口即退回「视口底边 = 键盘上沿」口径（页面压缩得准时等价），不阻塞定位；
    // 按 P0-1 不静默失败：打日志并允许下次进页重试
    kbUi = null;
    kbBindAsked = false;
    hilog.error(KB_LOG_DOMAIN, KB_LOG_TAG, 'getLastWindow failed: %{public}s', JSON.stringify(err));
  });
}

// 键盘区上沿（窗口坐标 vp；-1 = 键盘未弹或未取到窗口）
function keyboardTopInWindow(): number {
  if (kbWindow === null || kbUi === null) {
    return -1;
  }
  try {
    const rect: window.Rect = kbWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect;
    if (rect.height <= 0) {
      return -1;
    }
    // Rect.top = 键盘区上边界（px，窗口坐标），与 Area.globalPosition 同坐标系，只差 px→vp
    return kbUi.px2vp(rect.top);
  } catch (err) {
    // 官方声明该接口可抛（窗口状态异常）：读不到按「键盘未弹」处理，退回视口口径
    hilog.error(KB_LOG_DOMAIN, KB_LOG_TAG, 'avoid area read failed: %{public}s', JSON.stringify(err));
    return -1;
  }
}

export class KeyboardCardScroller {
  private readonly scroller: Scroller;
  // 编辑态闸：非编辑态视口高变化（横竖屏、分屏）不得滚页——键盘收起后页面回全高，
  // 再按旧目标滚会把卡顶推出视口
  private editing: boolean = false;
  // 键盘上沿之下还要让出的固定高度（vp）：本页吸底键条高；无键条的页传 0
  private bottomInset: number = 0;
  // 内容卡底边 / 视口底边在窗口坐标系里的 y（-1 = 还没量到）
  private cardBottom: number = -1;
  private viewportBottom: number = -1;
  // 视口高（只用于判「变了没有」，不参与定位算式）
  private viewportHeight: number = -1;
  private timer: number = -1;
  private disposed: boolean = false;

  constructor(scroller: Scroller) {
    this.scroller = scroller;
  }

  // 编辑态开关（聚焦传 true 并给底部让位，失焦传 false）。失焦即取消在途定位并摘出广播表。
  setEditing(editing: boolean, bottomInset: number): void {
    if (this.disposed) {
      // 退页后才到的 onEditChange（焦点在销毁链上丢失）不得把已释放件重新挂回广播表
      return;
    }
    this.bottomInset = bottomInset;
    if (this.editing === editing) {
      return;
    }
    this.editing = editing;
    if (editing) {
      kbWatchers.add(this);
      attachKeyboardListener();
      this.schedule(KEYBOARD_CARD_KICK_MS);
    } else {
      kbWatchers.delete(this);
      releaseKeyboardListener();
      this.cancel();
    }
  }

  // 内容卡区域回调（挂卡体 onAreaChange）：卡底 = 卡顶窗口 y + 卡高
  onCardArea(area: Area): void {
    const bottom: number = this.sizeOf(area.globalPosition.y) + this.sizeOf(area.height);
    if (bottom > 0) {
      this.cardBottom = bottom;
    }
  }

  // 视口区域回调（挂 Scroll onAreaChange）：键盘压缩页面后视口底边≈键盘上沿
  onViewportArea(area: Area): void {
    const height: number = this.sizeOf(area.height);
    if (height > 0) {
      this.viewportBottom = this.sizeOf(area.globalPosition.y) + height;
    }
    if (Math.abs(height - this.viewportHeight) < 0.5) {
      return;
    }
    this.viewportHeight = height;
    if (this.editing) {
      this.schedule(KEYBOARD_CARD_SETTLE_MS);
    }
  }

  // 键盘高度变化（窗口事件广播）：不靠视口变化也能重算——页面未被压缩时这是唯一驱动
  onKeyboardChange(): void {
    if (this.editing && !this.disposed) {
      this.schedule(KEYBOARD_CARD_SETTLE_MS);
    }
  }

  // 页面退出：停表 + 摘表 + 摘监听（表空时）+ 关门（与 setEditing(true) / schedule 成对）
  dispose(): void {
    this.disposed = true;
    this.editing = false;
    kbWatchers.delete(this);
    releaseKeyboardListener();
    this.cancel();
  }

  // Length（number | string | Resource；Position 字段可缺省）取数值：位置与尺寸实测恒为
  // 数字（vp），非数字与缺省档不参与定位（返回 0，由 caller 的 >0 判据兜住）
  private sizeOf(value: Length | undefined): number {
    return typeof value === 'number' ? value : 0;
  }

  private schedule(delay: number): void {
    if (this.disposed) {
      return;
    }
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.reveal();
    }, delay);
  }

  private cancel(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  // 卡底超出「上沿 − 让位 − 留白」多少就滚多少；已够高则不动
  private reveal(): void {
    if (this.disposed || this.cardBottom < 0 || this.viewportBottom < 0) {
      return;
    }
    const keyboardTop: number = keyboardTopInWindow();
    // 页面压缩得准（视口底边 = 键盘上沿）两者等价；压缩偏了取键盘区兜住那一档导航条。
    // 合理性闸：键盘上沿只会「略高于视口底边」（一档导航条内），超出这个量级说明读数不是上沿
    //（缺省 0 / 误给高或给成屏幕高）——宁可退回旧口径，也不能按错数把卡顶顶出视口
    const usableKeyboardTop: boolean =
      keyboardTop > 0 && keyboardTop <= this.viewportBottom + KEYBOARD_CARD_RECT_GUARD;
    const occluderTop: number = usableKeyboardTop ?
      Math.min(this.viewportBottom, keyboardTop) : this.viewportBottom;
    const limit: number = occluderTop - this.bottomInset - KEYBOARD_CARD_BOTTOM_MARGIN;
    const delta: number = this.cardBottom - limit;
    const current: OffsetResult = this.scroller.currentOffset();
    if (delta <= KEYBOARD_CARD_SLACK) {
      return;
    }
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: current.yOffset + delta,
      animation: { duration: KEYBOARD_CARD_SCROLL_MS, curve: Curve.EaseOut }
    });
  }
}
