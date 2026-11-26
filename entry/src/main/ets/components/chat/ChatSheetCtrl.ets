// 对话页面板开关与手势关闭路由域（自 ChatPage 域级最小拆出；形态沿革：editAssistant /
// status / queue / queueEdit 陆续加入，branch 形态已退役，现余十种）。域定义：对话页十个
// 半模态形态（model / prompt / context / compress / stats / input / editAssistant /
// status / queue / queueEdit）的**开启写序**与**手势关闭路由**编排。
// · 不持 UI 壳：SheetHost 分支链与 bindSheet 挂载仍在页面（「整段抽出约 25 参数纯转发 =
// 反碎片③禁止的转接壳」判例），本件只拆「开关与路由」逻辑层，面板组件与装配位不动；
// 新开申报：无同域既有件可并入（ChatCompressCtrl 只管压缩链、KimiSheetCommon 是共享壳函数）。
// · 开启写序（各形态开启时写什么、按什么序写——序契约单源在此）：用量面板开启带草稿刷新
//（每次打开活算一次）；全屏输入先播种 init/live 再置形态；排队编辑先播种目标项 id / 初值 /
//   live 并置 EDITING 占位再置形态；其余形态裸开。
// · 排队编辑会话：目标项 id / 初值 / 实时文本 / 队列域源四值单源在本件（面板件只渲染与
//   上行，跨面板重建存活）；脏态判据 = live 与 init **现读**比对（非打开时快照）；关闭单
//   入口 queueEditRequestClose——标题栏 xmark（无 action）与 onWillDismiss 手势（带 action）
//   两路同调，脏态先 confirmSheetClose 确认，确认通过才释放 EDITING 占位并放行；保存与立即
//   发送是程序化关闭不接确认入口——保存回写条目文本后回排队管理面（关闭-再开协调走开意图
//   位），立即发送回写文本 + jumpSend（插队语义）后关面板。
//   **EDITING 占位必须配对释放**（占位泄漏 = 队头永久卡死）：保存 / 立即发送写回后直调
//   clearEditing；取消（xmark）/ 手势关闭经 releaseQueueEdit 幂等收口；队列域 disposeSilent
//   对残留 EDITING 兜底复位（ChatSendQueueCtrl）。
// · 手势关闭路由（bindSheet onWillDismiss；官方契约 = 回调内须 action.dismiss() 放行，见
//   KimiSheetCommon 注释）：压缩形态交 ChatCompressCtrl.requestClose(action)——在途生成 /
//   未采用草稿两态先确认，确认通过才放行（确认未过面板保持打开）；编辑助手形态交
//   editAssistantRequestClose(action)——脏态（live 与 initial 现读比对）先确认，同款两路；
//   排队编辑形态交 queueEditRequestClose(action)——同款脏态确认；全屏输入形态先回写胶囊
//   （与面板 onClose 路同语句同效，未发送编辑不丢）；其余形态恒放行。放行本体 = 宿主
//   closeSheet（action 在场走官方 dismiss()、缺省直写可见性——页面侧单源）。
// · 面板内层级（★ 2026-11-25 会话设置栈化笔）：prompt 形态内嵌 HdsNavigation 栈，栈本体归
//   面板件 ChatPromptSheet（每次打开重建 = 新栈，天然归零），挂载时经 registerPromptNavStack
//   登记到本件、卸载按实例同一性注销（旧件销毁不误清交叠的新件）。返回类手势（PRESS_BACK =
//   back 键/侧滑/Esc，SLIDE = 镜像侧滑）在 handleGestureClose 首段分流：栈非空 → pop 回上
//   一页且**不调 dismiss**（官方「屏蔽部分关闭行为」：不调则面板不关）；栈空才落到既有关闭
//   收口。xmark（自绘键，不进本漏斗）/ 下拉（SLIDE_DOWN）/ 蒙层（TOUCH_OUTSIDE）恒关整张。
//   有暂存的子页须在 pop 前先走确认（当前 prompt 四个子页全零暂存，恒直接 pop）。
// · 参数面 = 宿主回接接口（refs 闭包延迟求值，照 ChatCompressCtrl / ChatPageLoadCtrl 形制）。
import { UIContext } from '@kit.ArkUI';
import { ChatSendQueueCtrl } from './ChatSendQueueCtrl';
import { confirmSheetClose } from './KimiSheetCommon';

// ── 面板内导航登记（★ 2026-11-25 会话设置栈化笔）──
// 面板件挂载时登记自己的 NavPathStack，卸载时按实例同一性注销。单窗口同一时刻至多一个会话
// 设置面板，故登记单槽；栈本体归面板件（状态就近持有），本件只持返回分流权。
let promptNavStackRef: NavPathStack | null = null;

export function registerPromptNavStack(stack: NavPathStack): void {
  promptNavStackRef = stack;
}

export function unregisterPromptNavStack(stack: NavPathStack): void {
  if (promptNavStackRef === stack) {
    promptNavStackRef = null;
  }
}
export interface ChatSheetHost {
  kind: () => string;
  openSheet: (kind: string) => void;
  closeSheet: (action?: DismissSheetAction) => void;
  refreshContextUsage: (draft: string) => void;
  fullInputLive: () => string;
  applyFullInputDraft: (text: string) => void;
  setFullInputInit: (text: string) => void;
  setFullInputLive: (text: string) => void;
  // 编辑助手面板初值快照（写序同全屏输入——先播种后置形态）
  setEditAssistantInit: (text: string) => void;
  compressRequestClose: (action?: DismissSheetAction) => void;
  // 编辑助手形态关闭请求（action 在场 = 手势路确认后 dismiss 放行，缺省 = 自绘键路确认后
  // 直写可见性；脏态确认本体在页面，两路同调一入口）
  editAssistantRequestClose: (action?: DismissSheetAction) => void;
  // UIContext（排队编辑确认弹窗用——UIContext 形态纪律）
  ui: () => UIContext;
}

export class ChatSheetCtrl {
  private host: ChatSheetHost;
  // ── 排队编辑会话（四值单源在此；面板件只渲染与上行，跨面板重建存活）──
  private queueEditId: string = '';
  private queueEditInit: string = '';
  private queueEditLive: string = '';
  // 目标队列域（ChatQueueHost 注入；释放时置空——不持无关引用）
  private queueEditSource: ChatSendQueueCtrl | null = null;

  constructor(host: ChatSheetHost) {
    this.host = host;
  }

  // ── 开启（十形态；写序契约见文件头）──

  // 模型选择（标题栏「模型」胶囊与回退路径菜单项两入口）
  openModel(): void {
    this.host.openSheet('model');
  }

  // 附件与提示词（输入栏「+」键入口）
  openPrompt(): void {
    this.host.openSheet('prompt');
  }

  // 上下文用量（输入条圆环键与摘要提示行两入口；带当前草稿文本——面板「本轮输入」段）
  openContext(draft: string): void {
    this.host.openSheet('context');
    this.host.refreshContextUsage(draft);
  }

  // 会话统计（「更多」菜单入口；不带草稿，刷新一次活算兜「久置后直开」）
  openStats(): void {
    this.host.openSheet('stats');
    this.host.refreshContextUsage('');
  }

  // 全屏输入（输入栏全屏键入口；live 同步初值——面板 aboutToAppear 再上行一次，幂等）
  openInput(initial: string): void {
    this.host.setFullInputInit(initial);
    this.host.setFullInputLive(initial);
    this.host.openSheet('input');
  }

  // 编辑助手回复（消息菜单「编辑」入口；live 由面板 aboutToAppear 上行同步——不预置防错拍）
  openEditAssistant(initial: string): void {
    this.host.setEditAssistantInit(initial);
    this.host.openSheet('editAssistant');
  }

  // 会话状态（输入栏「状态」chip 入口；裸开——refs 现读 + 自拉，无开启写序；只读，手势
  // 关闭缺省直放行）
  openStatus(): void {
    this.host.openSheet('status');
  }

  // 排队管理（QueueTopBand 入口条点击；裸开——面板自持读队列域；'queue' 分支渲染
  // ChatQueueSheet、detents 取 [MEDIUM, LARGE]）
  openQueue(): void {
    this.host.openSheet('queue');
  }

  // 排队项编辑（排队面板「编辑」键入口，经 ChatQueueHost 传入目标项与队列域源。写序 =
  // 先播种三值 + 置 EDITING 占位（拦派发，防编辑中项被自动发送带走）→ 再置形态；本处预置
  // 保证首帧正确）
  openQueueEdit(id: string, text: string, queueCtrl: ChatSendQueueCtrl | null): void {
    this.queueEditId = id;
    this.queueEditInit = text;
    this.queueEditLive = text;
    this.queueEditSource = queueCtrl;
    if (queueCtrl !== null) {
      queueCtrl.markEditing(id);
    }
    this.host.openSheet('queueEdit');
  }

  // 编辑面初值（ChatQueueHost 构造面板入参——快照语义，面板每次打开重建实例）
  queueEditInitialText(): string {
    return this.queueEditInit;
  }

  // 编辑面实时文本上行（脏态判据 = live 与 init 现读比对——非打开时快照）
  setQueueEditLive(text: string): void {
    this.queueEditLive = text;
  }

  // 编辑面关闭请求单入口（规范-半模态 §1 新码硬约束：标题栏 xmark 与 onWillDismiss 手势
  // 两路同调）：脏态先 confirmSheetClose 确认（确认未过不关、EDITING 占位保持）；通过后
  // 释放占位再放行。程序化关闭（保存 / 立即发送）不接本入口
  queueEditRequestClose(action?: DismissSheetAction): void {
    if (this.queueEditLive !== this.queueEditInit) {
      confirmSheetClose(this.host.ui(), {
        title: '放弃修改？',
        message: '尚未保存的修改将丢失',
        cancelLabel: '继续编辑',
        confirmLabel: '放弃修改'
      }).then((approved: boolean): void => {
        if (!approved) {
          return;
        }
        this.releaseQueueEdit();
        this.host.closeSheet(action);
      });
      return;
    }
    this.releaseQueueEdit();
    this.host.closeSheet(action);
  }

  // 编辑面「保存」（程序化关闭）：只改文本（空文本/未改动不写）→ 释放占位 → 关编辑面并按
  // 开意图位重开排队管理面（离场动效结束由宿主 onSheetGone 补开）
  queueEditSave(text: string): void {
    const trimmed: string = text.trim();
    const ctrl: ChatSendQueueCtrl | null = this.queueEditSource;
    if (ctrl !== null && this.queueEditId !== '') {
      if (trimmed !== '' && trimmed !== this.queueEditInit) {
        ctrl.updateItemText(this.queueEditId, trimmed);
      }
      ctrl.clearEditing(this.queueEditId);
    }
    this.clearQueueEditTarget();
    this.host.closeSheet();
    this.host.openSheet('queue');
  }

  // 编辑面「立即发送」（程序化关闭）：更新文本 → 释放占位 → jumpSend（插队 + 恢复发送，
  // abort 在途时 jump 标记由域件承接）→ 关面板（受理即关，不重开管理面）
  queueEditSend(text: string): void {
    const trimmed: string = text.trim();
    const ctrl: ChatSendQueueCtrl | null = this.queueEditSource;
    const id: string = this.queueEditId;
    if (ctrl !== null && id !== '') {
      if (trimmed !== '' && trimmed !== this.queueEditInit) {
        ctrl.updateItemText(id, trimmed);
      }
      ctrl.clearEditing(id);
      ctrl.jumpSend(id);
    }
    this.clearQueueEditTarget();
    this.host.closeSheet();
  }

  // 释放 EDITING 占位（保存 / 立即发送 / 取消 / 手势四路共用；幂等——clearEditing 只在
  // EDITING 态动作，save/send 路径先自行清算后本方法再调为零操作）
  private releaseQueueEdit(): void {
    const ctrl: ChatSendQueueCtrl | null = this.queueEditSource;
    if (ctrl !== null && this.queueEditId !== '') {
      ctrl.clearEditing(this.queueEditId);
    }
    this.clearQueueEditTarget();
  }

  private clearQueueEditTarget(): void {
    this.queueEditId = '';
    this.queueEditSource = null;
  }

  // ── 手势关闭路由（bindSheet onWillDismiss；两路放行时机见文件头）──
  handleGestureClose(action: DismissSheetAction): void {
    // 面板内层级（2026-11-25）：返回类手势栈非空 = pop 回上一页，不调 dismiss（面板不关）；
    // 栈空才落既有关闭收口。xmark / 下拉 / 蒙层不进本分支（恒关整张，见文件头）。
    const isBack: boolean = action.reason === DismissReason.PRESS_BACK ||
      action.reason === DismissReason.SLIDE;
    const promptStack: NavPathStack | null = promptNavStackRef;
    if (isBack && this.host.kind() === 'prompt' && promptStack !== null &&
      promptStack.size() > 0) {
      promptStack.pop();
      return;
    }
    if (this.host.kind() === 'compress') {
      this.host.compressRequestClose(action);
      return;
    }
    if (this.host.kind() === 'editAssistant') {
      this.host.editAssistantRequestClose(action);
      return;
    }
    if (this.host.kind() === 'queueEdit') {
      this.queueEditRequestClose(action);
      return;
    }
    if (this.host.kind() === 'input') {
      this.host.applyFullInputDraft(this.host.fullInputLive());
    }
    this.host.closeSheet(action);
  }
}
