// 触顶翻页编排域（2026-08-31 任务 D 自 ChatPageContent 域级拆出——复原 dshinhm 翻页链
// 该文件必超 400 红线，按宪法先拆「触发与滚动锚点保持」域；查询与状态在
// ChatPageLoadCtrl.loadOlder（ChatDb.queryMessagesBefore + ChatDataSource.prepend），
// 头部提示行 UI 在 ChatPageContent——本域只管 onReachStart 触达、锚点定格与恢复）。
// · 锚点语义（dshinhm 同款）：触发加载时定格第一个可见消息 id；头部前插后内容变长，
//   纯 offset 保持会整屏跳走——按 id 反查新下标 scrollToIndex 贴顶恢复（轻微容差可接受）。
//   锚点在下标 = List 项位（含头部提示行）；定格发生在提示行出现**之前**（守卫刚过、
//   置 loading 前），此时与 LazyForEach 数据位一一对齐——恢复时提示行已收，位序复原。
// · 防抖守卫四连：messageCount===0（空会话不翻）/ isBusy（流式停——★ 2026-09-15 决明指令
//   「在流式禁用」，判据/口径见 tryLoadOlder 内注释）/ olderLoading（加载中闸——重复触顶
//   防抖）/ olderExhausted（到底停——有界红线，禁止无界连拉）。
// · 失败路径：查询异常（loadOlder 上抛）不恢复锚点——内容未变，位置本就不动。
// · 翻页与流式/跟随共存：本域不触 followCtrl——触顶翻历史时用户已脱底（跟随早停），
//   onReachStart 与 onReachEnd 门控互不干扰。
import { ChatDataSource } from './ChatDataSource';
import { cardDescColor } from '../../common/Theme';

export class ChatOlderCtrl {
  // 延迟求值箭头闭包（持组件 this——ChatSendRefs 同款姿势；构造时组件成员未定序，
  // 调用时求值即安全）
  private getDataSource: () => ChatDataSource;
  private getScroller: () => Scroller;
  private onLoadOlder: () => Promise<void>;
  // 流式判定（★ 2026-09-15 决明指令「在流式禁用」；闭包延迟求值——调用时读总是当时值。
  // 与 ChatSendCtrl refs.sending 的差异：彼为页面 @State 直读，本处经 ChatPageContent
  // @Prop 中转——该通道实测可用，依据与迁移口径见接线点注释〔ChatPageContent.olderCtrl〕）
  private isBusy: () => boolean;
  // 第一个可见项下标（List onScrollIndex 轻量更新，非状态驱动）
  private visibleFirstIndex: number = -1;
  // 触顶时定格的锚点消息 id（'' = 无待恢复锚点）
  private anchorId: string = '';

  constructor(getDataSource: () => ChatDataSource, getScroller: () => Scroller,
    onLoadOlder: () => Promise<void>, isBusy: () => boolean) {
    this.getDataSource = getDataSource;
    this.getScroller = getScroller;
    this.onLoadOlder = onLoadOlder;
    this.isBusy = isBusy;
  }

  // List.onScrollIndex 回调入口（锚点记录用；滚动时高频轻量更新）
  onScrollIndex(first: number): void {
    this.visibleFirstIndex = first;
  }

  // 触顶入口（List.onReachStart 回调）：守卫 → 定格锚点 → 置加载态 → 上行加载 →
  // resolve 后恢复锚点；异常 toast 在 loadOlder 侧呈报，此处 catch 只收加载态
  //（失败不恢复滚动——内容未变位置本就不动）
  // ★ 2026-09-02 手感修复：用户「滑到顶停止后立刻下滑没反应，过一小会儿才恢复」——
  // 根因 = 加载完成后的 scrollToIndex 锚点恢复把用户下滑拉回（打断正在进行的手势）。
  // 修复 = 用户朝底方向滑动（onTouch 手指上移）时 cancelAnchor 取消待恢复锚点，
  // 加载完成后 restoreAnchor 判空直接跳过——用户已放弃看旧消息，不再拉回
  tryLoadOlder(): void {
    const ds: ChatDataSource = this.getDataSource();
    if (ds.messageCount === 0) {
      return;
    }
    // ★ 2026-09-15 流式禁用（决明指令「在流式禁用吧」；存量观察项销账）：流式期间触顶
    // 不翻页——走查已证「流式增量 × 头部前插」共存自愈（同 id 重挂 + 权威串在域），但
    // 交叉面按指令整体收掉。静默 return（触顶是列表隐式手势，不 toast——与同域三守卫同
    // 姿势）；守卫在 olderAttempted 置位之前 = 流式中触顶零翻页状态写入（翻页态只在非
    // 流式下演进，交叉面归零）。已知取舍：流式期间触顶被跳过，流式结束后列表仍在顶部
    // 时 onReachStart 不会自行重触发（无滚动事件），用户滑离顶部再回顶即正常翻页
    if (this.isBusy()) {
      return;
    }
    ds.olderAttempted = true; // 触达标记（「已到顶」行首次触顶才亮——见 ChatDataSource 注释）
    if (ds.olderLoading || ds.olderExhausted) {
      return;
    }
    const firstIndex: number = this.visibleFirstIndex >= 0 ? this.visibleFirstIndex : 0;
    if (ds.totalCount() <= firstIndex) {
      return; // 下标越界防御（理论不可达——onScrollIndex 恒在窗口内）
    }
    this.anchorId = ds.getData(firstIndex).id;
    ds.olderLoading = true;
    this.onLoadOlder()
      .then((): void => {
        ds.olderLoading = false;
        this.restoreAnchor();
      })
      .catch((): void => {
        ds.olderLoading = false;
      });
  }

  // 取消待恢复锚点（用户朝底方向滑动 = 放弃看旧消息——2026-09-02 手感修复配合：
  // 加载完成不再 scrollToIndex 拉回，用户下滑即时生效；不打断加载本身，仅跳过恢复）
  cancelAnchor(): void {
    this.anchorId = '';
  }

  // 锚点恢复：按 id 反查新下标（头部前插使 index 平移）→ scrollToIndex 贴顶
  private restoreAnchor(): void {
    const anchor: string = this.anchorId;
    this.anchorId = '';
    if (anchor === '') {
      return;
    }
    const ds: ChatDataSource = this.getDataSource();
    let target: number = -1;
    for (let i = 0; i < ds.totalCount(); i++) {
      if (ds.getData(i).id === anchor) {
        target = i;
        break;
      }
    }
    if (target >= 0) {
      try {
        this.getScroller().scrollToIndex(target, false);
      } catch (e) {
        // 坑63 族：未绑定/时序竞态下 scrollToIndex 可能抛——静默（内容未变，无补偿动作）
      }
    }
  }
}

// 触顶翻页头部提示行（2026-08-31 任务 D；UI 件随域迁此——ChatPageContent 超线拆分的
// 组成部分，父级 List 内 ListItem 包裹、两态经 @Prop 入）：加载中 = LoadingProgress +
// 「加载更早…」（随 olderLoading 消失）；已到顶 = 「已到顶」次要色居中行（olderExhausted
// 且查过至少一页才由父级渲染——短会话未触顶不常驻）。样式 = dshinhm 列表页尾部
// LoadingProgress 同款姿态
@Component
export struct ChatOlderRow {
  @Prop loading: boolean = false;
  @Prop exhausted: boolean = false;

  build() {
    if (this.loading) {
      Row({ space: 8 }) {
        LoadingProgress()
          .size({ width: 24, height: 24 })
        Text('加载更早…')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 8 })
    } else if (this.exhausted) {
      Text('已到顶')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 8, bottom: 8 })
    }
  }
}
