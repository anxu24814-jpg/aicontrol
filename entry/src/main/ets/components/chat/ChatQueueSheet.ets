// 排队管理半模态面板内容件（★ 2026-10-17 排队插队总案 U2）。
// 域定义一句话：**排队队列的卡片管理面**——一消息一卡（上段序号 + 单行截断内容，下段
// 立即发送/编辑/删除三键）+ 队列暂停/恢复 + 清空（二次确认）+ 长按拖拽排序；数据自持有
// 读取（构造时取队列域引用 + onChange 上行刷新），零持久化逻辑（写穿全在 ChatSendQueueCtrl）。
// · 反碎片下限申报：排队管理是新功能域（宪法「新增功能域不论行数一律先拆」）；无同域既有件
//   可并（ChatBranchSheet 是分支列表、SessionMovePanel 是会话移动，均非排队）；非纯转接壳
//  （持卡列表结构分支/拖拽落定/标题栏菜单构造三块逻辑）。宿主 = ChatPage 页面根唯一
//   bindSheet 的 'queue' 分支——**复用既有挂载点不新增**，挂载点注册义务不触发（先例 =
//   KimiFullInputSheet「不新增挂载点」头注释）；关闭链四件由宿主既有机制承接。
// · 声明式 bindSheet 面板件不带 bindSheet；壳 = HdsNavigation MODAL + sheetTitleBarOptions
//   同源（禁自绘标题）。★ 标题栏 = 官方 menu 数组两枚独立圆钮（2026-10-17 二次拍板：胶囊
//   形态真机观感不理想〔与 MODAL 标题行不平齐、在半模态标题栏里割裂〕，退役改回单独圆钮，
//   勿再试）；数组序 = HDS 菜单键自右缘排布 [清空(trash), 启动/暂停(play|pause)] ⇒ 视觉左
//   启动/暂停、右清空；空队列两键均禁用（isEnabled，无对象可操作）。无 xmark——关闭 = 下拉
//   手势经宿主 onWillDismiss 既有链；真机若需要显式关闭键 → 另笔拍板。
// · 拖拽排序：List + ForEach + onMove（官方推荐；≤20 条小列表不懒加载——规范 §4.6.1）。
//   **两套条件挂结构分支**（WorkspaceFolderView 真机判例：传 undefined 摘除 onMove 不随
//   局部重渲生效）——@State dragEnabled 驱动分支重建；当前绑定面 = 常态可拖（ACTIVE 与
//   PAUSED 均可），仅 ≤1 项时走不可拖分支（无可拖意义）；将来若改暂停禁拖，把条件绑到
//   dragEnabled 即可，禁回 undefined 摘除形态。拖拽×派发互斥 = 队列域 dragHeld：
//   onDragStart 置锁 / 落定与 onDrop 解锁补一次派发试探（域件 setDragHeld 承接）；面板销毁
//   兜底解锁（防拖拽中离场）。
// · 键纪律（坑44/80）：ForEach 键生成器 = item.id + '|' + item.state + '|' + index——**三个
//   可变展示成分显式入键**（自检修复：原键只含 id|state，误假设「item 生成器声明 index 即由
//   框架自动拼入有效键」——ForEach 键 = keyGenerator 返回值，键不变即复用组件、**不重执行
//   item 生成器**，复用项的 index 参数停在旧值，删中间项/拖拽换序后序号 index+1 冻结在旧值，
//   真机必现）。item.state 入键同理（三键可用性/透明度随 state 变，裸 id 会让空转/跳队/编辑
//   态切换不建行、禁用态冻结）。text 不在键内——它的刷新由编辑保存链承接（updateItemText 后
//   clearEditing 令 state EDITING→QUEUED 触发重建，且保存后管理面板按开意图位重开重建；
//   「立即发送」路径卡片随派发离场，无需刷文本）。数据源更新只在 onMove 落定（离手后）做，
//   官方红线「离手前禁改数据源」不破；from/to 无 ±1 换算。
// · 布局红线：面板容器不设左右边距（规范-半模态 §3）；列表零水平 padding 形态 = 条目挂
//   CARD_PANEL_WIDTH + alignListItem(Center)、卡体 width('100%')（**禁两层同写**
//   CARD_PANEL_WIDTH——二次收窄成屏宽−64，规范-列表卡片 §4.8 第二件）；条目层圆角 CARD_RADIUS（20） 与卡
//   同值（拖拽预览背板按条目轮廓画）；卡壳 Button.stateEffect(false)（长按起手灰蒙层防线）；
//   List clip(false)（渐变模糊采样）+ nestedScroll(PARENT_FIRST / SELF_FIRST)（上滑优先扩
//   挡位、下滑滚到顶才轮到下拉收起）+ 尾部透明 Row 占位（Blank 在 ListItem 下
//   编译 10905201）+ 空态官方正色占位卡（禁灰置，规范-半模态 §5）。
// · 键形制（★ 2026-10-17 用户拍板「图标 + 文字、无底」）：卡内下侧三键 = 行内图标+文字键
//  （Button 内 Row(space 4){ SymbolGlyph 16 + Text 13 } + ButtonStyleMode.TEXTUAL + 三等分
//   layoutWeight(1) + 高 40 + font_secondary；禁自绘 borderRadius/底色）。同源先例 =
//   ChatMessageItem「展开全文」键（图标 16 + 文字 13 + 间距 4 + font_secondary）。原
//   fallbackButton* 四件套单行形态已废止，面板内不再有 fallbackButton* 引用。
// · 「立即发送」= queueCtrl.jumpSend（插队 + 恢复发送语义全在域件）；**受理成功即自动关闭
//   面板**（★ 2026-10-17 总指挥裁定：方案原「不自动关闭」与用户显式设计相反，用户设计优先）
//   ——关闭走宿主 closeSheet 单入口（关闭链四件：先清开意图 → 置离场在途 → 再写可见性），
//   关闭后半模态再开经既有关闭-再开协调链照常。
// · 编辑键 = 上行 onEdit（宿主 = ChatQueueHost → ChatSheetCtrl.openQueueEdit，切
//   'queueEdit' 编辑半模态并置 EDITING 占位；本件零编辑逻辑）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationMenuContentOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { ChatSendQueueCtrl, QueueItem } from './ChatSendQueueCtrl';
import { sheetTitleBarOptions } from './KimiSheetCommon';

@Component
export struct ChatQueueSheet {
  // 队列域引用（宿主 ChatPage 经 lifecycle.queueCtrl 注入；面板自持有读取——订阅/注销
  // 在 aboutToAppear / aboutToDisappear 成对，寿命匹配红线）
  queueCtrl: ChatSendQueueCtrl | null = null;
  // 编辑上行（★ U3 已接真：ChatQueueHost → ChatSheetCtrl.openQueueEdit；本件只发意图）
  onEdit: (id: string, text: string) => void = (_id: string, _text: string): void => {
  };
  // 关闭面板上行（宿主 ChatPage.closeSheet 单入口——关闭链四件纪律：先清开意图 / 置离场
  // 在途 / 再写可见性；★ 2026-10-17 总指挥裁定「立即发送受理成功即关闭」，见件头）
  onRequestClose: () => void = (): void => {
  };
  // 底部系统导航条高（宿主 bottomPad 注入——尾部占位，坑66 方案 B）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') private appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 队列快照（onChange 上行整表替换；面板自持有读取——数据存储规范白名单）
  @State private items: QueueItem[] = [];
  // 暂停态（标题栏切换键图标 / 副行 / 列表提示行三处同源）
  @State private paused: boolean = false;
  // 拖拽可用态（两套条件挂的结构分支判据——见文件头；常态可拖，仅 ≤1 项走不可拖分支）
  @State private dragEnabled: boolean = false;
  // 拖拽在途位（面板侧；域件 dragHeld 的配对解锁用——销毁兜底防锁死派发）
  private dragActive: boolean = false;
  // onMove 落定自写数据源期间跳过 onChange 的二次整表替换（防同拍两次数组赋值扰动落位）
  private applyingOrder: boolean = false;
  private scroller: Scroller = new Scroller();

  private onQueueChanged = (count: number, paused: boolean): void => {
    this.paused = paused;
    this.dragEnabled = count > 1;
    if (this.applyingOrder) {
      return;
    }
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl !== null) {
      this.items = ctrl.snapshotItems();
    }
  };

  aboutToAppear(): void {
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl === null) {
      return;
    }
    ctrl.addOnQueueChange(this.onQueueChanged);
    this.syncFromQueue(ctrl);
  }

  aboutToDisappear(): void {
    // 拖拽中离场：先解锁域件派发闸（成对释放；解锁补一次派发试探由域件承接）
    this.releaseDrag();
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl !== null) {
      ctrl.removeOnQueueChange(this.onQueueChanged);
    }
  }

  private syncFromQueue(ctrl: ChatSendQueueCtrl): void {
    this.items = ctrl.snapshotItems();
    this.paused = ctrl.isPaused();
    this.dragEnabled = this.items.length > 1;
  }

  // ── 标题栏（官方 menu 数组两枚独立圆钮；无自绘标题 / 无关闭键——数组序见文件头）──
  private menuContent(): HdsNavigationMenuContentOptions {
    const hasItems: boolean = this.items.length > 0;
    return {
      value: [{
        content: {
          icon: $r('sys.symbol.trash'),
          isEnabled: hasItems,
          action: (): void => {
            this.requestClear();
          }
        }
      }, {
        content: {
          // 图标 = 将要执行的动作：暂停中显示 play（点它恢复），自动发送中显示 pause
          icon: this.paused ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause_fill'),
          isEnabled: hasItems,
          action: (): void => {
            this.togglePause();
          }
        }
      }]
    } as HdsNavigationMenuContentOptions;
  }

  // 副行状态文案（暂停态三处一致之一；空队列单列「暂无排队消息」）
  private subtitleText(): string {
    if (this.items.length === 0) {
      return '暂无排队消息';
    }
    return this.paused ? '已暂停' : '自动发送下一条';
  }

  private togglePause(): void {
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl === null) {
      return;
    }
    if (this.paused) {
      ctrl.resume();
    } else {
      ctrl.pause();
    }
  }

  // 清空二次确认（UIContext showDialog；确认才 clear，弹窗异常不清空）
  private async requestClear(): Promise<void> {
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl === null || this.items.length === 0) {
      return;
    }
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: '清空排队消息',
        message: '将删除全部排队中的消息，删除后不可恢复。',
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '清空', color: $r('sys.color.font_primary') }
        ]
      });
      if (choice.index === 1) {
        ctrl.clearAll();
      }
    } catch (e) {
      // 弹窗异常不放行清空（宁可不删）
    }
  }

  // ── 拖拽（T10：dragHeld 锁派发 / 落定整组替换 + 换序持久化 / 解锁补派发试探）──
  private onRowDragStart = (_index: number): void => {
    this.dragActive = true;
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl !== null) {
      ctrl.setDragHeld(true);
    }
  };

  private onRowDrop = (_index: number): void => {
    this.releaseDrag();
  };

  private releaseDrag(): void {
    if (!this.dragActive) {
      return;
    }
    this.dragActive = false;
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl !== null) {
      ctrl.setDragHeld(false);
    }
  }

  // 拖拽落定：splice 后整组替换（官方 onMove 语义；from/to 无 ±1）；id/state 不变而键内
  // index 变 ⇒ 键变整表重建、序号随重建刷新（见文件头键纪律）
  private onRowMove = (from: number, to: number): void => {
    if (from === to || from < 0 || to < 0 || from >= this.items.length ||
      to >= this.items.length) {
      return;
    }
    const next: QueueItem[] = this.items.slice();
    const moved: QueueItem[] = next.splice(from, 1);
    if (moved.length === 0) {
      return;
    }
    next.splice(to, 0, moved[0]);
    this.items = next;
    const orderedIds: string[] = [];
    for (const row of next) {
      orderedIds.push(row.id);
    }
    this.applyingOrder = true;
    const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
    if (ctrl !== null) {
      ctrl.applyOrder(orderedIds);
    }
    this.applyingOrder = false;
    // 落定即解锁（onDrop 可能因整表重建迟到/缺席——域件「解锁补一次派发试探」在此兜底）
    this.releaseDrag();
  };

  // onMove 事件面（@since 20：长按/起拖/经过/离手四相；本面板只取起拖与离手——
  // 起拖上锁、离手上报索引但解锁统一走 releaseDrag 幂等）
  private dragEvents(): ItemDragEventHandler {
    return {
      onDragStart: this.onRowDragStart,
      onDrop: this.onRowDrop
    };
  }

  // ── 行内三键可用性（★ 2026-10-17 自检修复·中2：按条目状态门控——旧形态三键恒可用，
  //    编辑 JUMP_PENDING 项会绕开 G2 占位（abort 收尾直发正在编辑的消息），点 IN_FLIGHT
  //    项静默无反馈；状态门控 + 键含 state 重建 = 可见禁用态）──
  // 立即发送/编辑：仅 QUEUED（IN_FLIGHT 在飞、JUMP_PENDING 等收尾、EDITING 正在编辑均禁用）
  private rowActionsEnabled(item: QueueItem): boolean {
    return item.state === 'QUEUED';
  }

  // 删除：QUEUED / JUMP_PENDING 可用（T8「abort 在途删除跳队项」语义保留——域件按 id 删除、
  // 标记随项消亡）；IN_FLIGHT（域件拒绝）与 EDITING（编辑面板持有目标）禁用
  private rowDeleteEnabled(item: QueueItem): boolean {
    return item.state === 'QUEUED' || item.state === 'JUMP_PENDING';
  }

  // ── 排队卡（★ 2026-10-17 两段式卡笔：上段内容区 = 长按起拖热区，下段 = 三键等分操作行）──
  // · 上段 = 序号 + 单行截断内容，本段零手势绑定——长按由 ListItem 承接起拖；
  // · 下段 = 卡内下侧并排三键（图标 + 文字、无底 TEXTUAL、三等分），**无分割线**、段间靠
  //   10vp 留白分隔（用户拍板：类似参考图但不要线）；
  // · 三键是交互子组件（Button），长按按键区默认不参与 List 的拖拽长按（多层级手势子组件
  //   优先；真机若仍起拖 → 三键补 .monopolizeEvents(true)，见 BLOCKED C 组第 13 项）；
  // · 卡壳仍 Button + stateEffect(false)（规范 §4.8：长按起手灰蒙层防线）。
  @Builder
  QueueRow(item: QueueItem, index: number) {
    ListItem() {
      Button() {
        Column() {
          // ── 上段：序号 + 单行内容（长按热区）──
          Row({ space: 6 }) {
            Text((index + 1).toString())
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(20)
              .textAlign(TextAlign.Center)
            Text(item.text)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(22)
          .alignItems(VerticalAlign.Center)
          // 无分割线：段间只留 10vp 白
          .margin({ bottom: 10 })
          // ── 下段：三等分操作键（图标 + 文字、无底 TEXTUAL）──
          Row() {
            // 立即发送（↔）：插队 + 恢复发送语义；受理成功即关面板（2026-10-17 总指挥裁定）
            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_secondary')])
                Text('立即发送')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .layoutWeight(1)
            .height(40)
            .padding(0)
            .enabled(this.rowActionsEnabled(item))
            .opacity(this.rowActionsEnabled(item) ? 1.0 : 0.4)
            .accessibilityText('立即发送')
            .onClick((): void => {
              const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
              if (ctrl === null) {
                return;
              }
              ctrl.jumpSend(item.id);
              // 受理成功判据 = 项已转 JUMP_PENDING（jumpSend 同步置位并上行 notify；IN_FLIGHT /
              // 已离队项零动作、不关面板）。受理成功 → 关闭面板走宿主 closeSheet 单入口
              //（关闭链四件：先清开意图 → 置离场在途 → 再写可见性；再开经既有协调链照常）
              const submitted: QueueItem | undefined =
                this.items.find((row: QueueItem): boolean => row.id === item.id);
              if (submitted !== undefined && submitted.state === 'JUMP_PENDING') {
                this.onRequestClose();
              }
            })
            // 编辑（✎）：开编辑半模态（U3 真链 = ChatQueueHost → ChatSheetCtrl.openQueueEdit）
            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_secondary')])
                Text('编辑')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .layoutWeight(1)
            .height(40)
            .padding(0)
            .enabled(this.rowActionsEnabled(item))
            .opacity(this.rowActionsEnabled(item) ? 1.0 : 0.4)
            .accessibilityText('编辑')
            .onClick((): void => {
              this.onEdit(item.id, item.text);
            })
            // 删除（🗑）：无底 TEXTUAL + font_secondary（禁垫四件套 = 圈选观感）
            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_secondary')])
                Text('删除')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .layoutWeight(1)
            .height(40)
            .padding(0)
            .enabled(this.rowDeleteEnabled(item))
            .opacity(this.rowDeleteEnabled(item) ? 1.0 : 0.4)
            .accessibilityText('删除')
            .onClick((): void => {
              const ctrl: ChatSendQueueCtrl | null = this.queueCtrl;
              if (ctrl !== null) {
                ctrl.deleteItem(item.id);
              }
            })
          }
          .width('100%')
          .height(40)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 8 })
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(CARD_RADIUS)
      .stateEffect(false)
    }
    // 条目宽 = 卡宽（列表零水平 padding 形态；卡体 width('100%')——禁两层同写 CARD_PANEL_WIDTH）
    .width(CARD_PANEL_WIDTH)
    .borderRadius(CARD_RADIUS)
  }

  // 空态官方正色占位卡（禁灰置，规范-半模态 §5；仅开面板瞬间队列已空的瞬态可见）
  @Builder
  EmptyCard() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(24)
        .fontColor([$r('sys.color.icon_primary')])
      Text('没有排队中的消息')
        .fontSize(15)
        .fontColor(cardTitleColor())
    }
    .width('100%')
    .padding(24)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavigation() {
      List({ space: CARD_SPACING, scroller: this.scroller }) {
        // 暂停提示行（暂停态三处一致之列表份；仅暂停且非空时出现）
        if (this.paused && this.items.length > 0) {
          ListItem() {
            Text('自动发送已暂停，点标题栏播放键继续')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
              .padding({ left: 4, right: 4 })
          }
          .width(CARD_PANEL_WIDTH)
        }
        if (this.items.length === 0) {
          ListItem() {
            this.EmptyCard()
          }
          .width(CARD_PANEL_WIDTH)
        } else if (this.dragEnabled) {
          // 可拖分支：挂 onMove（两套条件挂结构分支——判例见文件头）
          ForEach(this.items, (item: QueueItem, index: number): void => {
            this.QueueRow(item, index);
          }, (item: QueueItem, index: number): string => item.id + '|' + item.state + '|' + index)
            .onMove(this.onRowMove, this.dragEvents())
        } else {
          // 不可拖分支（≤1 项）：不挂 onMove——**禁改回传 undefined 摘除形态**
          ForEach(this.items, (item: QueueItem, index: number): void => {
            this.QueueRow(item, index);
          }, (item: QueueItem, index: number): string => item.id + '|' + item.state + '|' + index)
        }
        // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条；Row 不用 Blank）
        ListItem() {
          Row()
            .height(this.bottomInset + 16)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      // 渐变模糊采样前提（规范-半模态 §2）；本列表零水平 padding，无需为拖拽再关裁剪——
      // clip(false) 同时满足拖拽浮起卡不被视口直边裁切（规范-列表卡片 §4.8 第一件）
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .alignListItem(ListItemAlign.Center)
      // 嵌套滚动（显式缺省）：上滑优先扩半模态挡位，下滑滚到顶才轮到下拉收起
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .titleBar(sheetTitleBarOptions('排队消息', this.subtitleText(), (): void => {
      // 无自绘关闭键：本回调不参与菜单构造（第 6 参 menuOverride 已整段接管）；关闭 = 下拉
      // 手势经宿主唯一 bindSheet 的 onWillDismiss 既有链（ChatSheetCtrl 手势路由 → closeSheet）
    }, this.immersiveLevel, undefined, this.menuContent()))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
