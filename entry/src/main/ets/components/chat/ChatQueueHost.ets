// 排队面板族宿主：按 sheetKind 分派排队管理面（'queue' = ChatQueueSheet）与排队编辑面
//（'queueEdit' = ChatQueueEditSheet），并把编辑入口接到 ChatSheetCtrl 的编辑会话单源
//（目标项 id + 文本播种、EDITING 占位、脏态关闭）。
// · 为何新建（宪法 1200 硬线预留缝）：编辑面直连接线会把贴线的 ChatPage 推过 1200 硬线，
// 总案已预留「排队宿主域外迁」缝——两分支合并到一件按 kind 分派，ChatPage 侧只留一个挂载点。
// · 为何不并入：ChatQueueSheet / ChatQueueEditSheet 是被装配的面板本体（宿主与被宿主倒置）；
//   ChatSheetCtrl 是共享的开启写序/手势关闭路由/队列编辑会话域（本件是它的 UI 装配侧，非纯
//   转接壳：模式分派 + 编辑入口接线是实质逻辑）。面板族复用 ChatPage 页面根唯一 bindSheet，
//  **不新增挂载点**（329 组注册表义务不触发）。
// · kind 必须 @Prop（不是普通成员）：管理面 → 点「编辑」只更换 sheetKind，bindSheet 挂载点
//   与内容树不重建（关闭动画期内容恒在）——普通成员会冻结在首建值 'queue'，编辑面永不出现；
//   @Prop 单向随父 state 刷新，管理面 ↔ 编辑面切换即换分支。
// · 状态真相：编辑目标 / 初值 / live / EDITING 占位全在 ChatSheetCtrl（单源，跨本组件重建
//   存活）；本组件零状态，只做装配与回调上行。
import { ChatQueueEditSheet } from './ChatQueueEditSheet';
import { ChatQueueSheet } from './ChatQueueSheet';
import { ChatSendQueueCtrl } from './ChatSendQueueCtrl';
import { ChatSheetCtrl } from './ChatSheetCtrl';

@Component
export struct ChatQueueHost {
  // 当前形态（'queue' 管理面 / 'queueEdit' 编辑面——ChatPage 传 sheetKind；见文件头 @Prop 理由）
  @Prop kind: string = 'queue';
  // 队列域引用（管理面自持有读取；编辑入口把它随目标项一并交给 ChatSheetCtrl）
  queueCtrl: ChatSendQueueCtrl | null = null;
  // 面板开关与排队编辑会话编排域（编辑面四回调全经它上行——脏态/占位释放单源）
  sheetCtrl: ChatSheetCtrl | null = null;
  // 底部系统导航条高（透传两面板底部留白兜底——模型面板 bottomInset 先例）
  bottomInset: number = 0;
  // 管理面「立即发送」受理成功即关闭（宿主关闭单入口；编辑面保存后的再开由 ChatSheetCtrl 承接）
  onRequestClose: () => void = (): void => {
  };

  // ── 编辑面回调（全部经 ChatSheetCtrl 单源；null 守卫照 ChatPageContent 控制器注入形制）──
  private editInitial(): string {
    const ctrl: ChatSheetCtrl | null = this.sheetCtrl;
    return ctrl !== null ? ctrl.queueEditInitialText() : '';
  }

  private editLive(text: string): void {
    const ctrl: ChatSheetCtrl | null = this.sheetCtrl;
    if (ctrl !== null) {
      ctrl.setQueueEditLive(text);
    }
  }

  private editSave(text: string): void {
    const ctrl: ChatSheetCtrl | null = this.sheetCtrl;
    if (ctrl !== null) {
      ctrl.queueEditSave(text);
    }
  }

  private editSend(text: string): void {
    const ctrl: ChatSheetCtrl | null = this.sheetCtrl;
    if (ctrl !== null) {
      ctrl.queueEditSend(text);
    }
  }

  private editClose(): void {
    const ctrl: ChatSheetCtrl | null = this.sheetCtrl;
    if (ctrl !== null) {
      ctrl.queueEditRequestClose();
    }
  }

  // 管理面「编辑」键：把目标项交给 ChatSheetCtrl（置 EDITING 占位 + 播种初值 + 切 'queueEdit'）
  private openEdit(id: string, text: string): void {
    const ctrl: ChatSheetCtrl | null = this.sheetCtrl;
    if (ctrl !== null) {
      ctrl.openQueueEdit(id, text, this.queueCtrl);
    }
  }

  build() {
    if (this.kind === 'queueEdit') {
      ChatQueueEditSheet({
        initial: this.editInitial(),
        bottomInset: this.bottomInset,
        onDraftChange: (text: string): void => {
          this.editLive(text);
        },
        onSave: (text: string): void => {
          this.editSave(text);
        },
        onSend: (text: string): void => {
          this.editSend(text);
        },
        onClose: (): void => {
          this.editClose();
        }
      })
    } else {
      ChatQueueSheet({
        queueCtrl: this.queueCtrl,
        bottomInset: this.bottomInset,
        onRequestClose: this.onRequestClose,
        onEdit: (id: string, text: string): void => {
          this.openEdit(id, text);
        }
      })
    }
  }
}
