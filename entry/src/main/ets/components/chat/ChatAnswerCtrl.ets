// 回答切换编排域。
// 域定义一句话：**轮尾「其他回答」面板的打开 / 重查 / 选择与切换失败恢复的实际编排**——
// 读图快照、纯函数归组、写入切换、视图快照发布与生命周期（请求代次 / 页面寿命 / 面板绑定）
// 全在此；**不做渲染**（渲染在 ChatAnswerSheet，纯算法在 ChatAnswerChoice，图快照读口在
// ChatBranchSource）。
// · 为什么新开本件（反碎片三问）：职责一句话成立（回答面板异步编排）；不能并进 ChatPage
//  （越 1200 硬线，明令不得继续内联答案逻辑）、不能并进 ChatPageContent（须回归「宿主 +
//   面板渲染」职责）、不能并进纯投影件（会污染零 I/O 纪律）；实逻辑非转接壳（打开链 /
//   点选链 / 代次守卫 / 失败相位恢复四段真实编排）。
// · 依赖方向（零环红线，坑50）：本件 → ChatAnswerChoice + ChatBranchSource +
//   ChatContextSource + ChatBranchPolicy + 组件层模型与 BranchSwitchResult 结果类型单向；
//   **不反向 import ChatPage / ChatPageContent**——视图发布经 sink 抽象
//  （ChatAnswerViewSink，装配处注入）。
// · 屏库两事实纪律：勾 = 屏幕已加载分支身份（dataSource.loadedBranch()）算出的当前末正文，
//   **不是**库默认 isActive；写入失败不回滚已保存的默认值，只置 needsReload 并在面板呈报
//  （可重试/重进恢复）。needsReload 跨面板关闭保留（组件重建不清屏库不一致事实）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SESSION_GRAPH, TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { conversationHasRow, conversationMigrateState }
  from '../../common/chat/ChatContextSource';
import { queryAnswerGraphSnapshot } from '../../common/chat/ChatBranchSource';
import { AnswerGraphSnapshot, buildAnswerChoices, ChatAnswerChoice, ChatAnswerChoices,
  buildQuestionChoices, ChatQuestionChoices }
  from '../../common/chat/ChatAnswerChoice';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage } from './ChatMessageCompose';
import { BranchSwitchResult } from './ChatBranchCtrl';

const DOMAIN: number = 0xD5A0;
const TAG: string = 'ChatAnswerCtrl';

  // 点选链的失效统一文案（固定：列表已变化 / 代表失效 / 点击轮不在已加载路径）
  const ANSWER_STALE_TEXT: string = '回答列表已变化，请刷新后重试';
  // 读失败兜底文案（读异常提示）
  const ANSWER_READ_FAIL_TEXT: string = '回答读取失败，请重试';
// 失败恢复提示兜底（switchToResult 未给 reason 时兜底——正常路径恒有 reason）
const ANSWER_RELOAD_FAIL_TEXT: string = '选择已保存，但对话刷新失败。可点回答重试，或重进会话';

// ── 回答版本步进域（行内 ◀x/y▶ 步进器的数据面）──
// 版本步进重算广播 tick 键（AppStorage 递增 tick——ChatStreamFlowCtrl 在轮落库回填
//〔stampNodeRef〕后发布、ChatPageContent @Watch 消费后调本控制器重算；广播键形制照
// SUGGEST_PAYLOAD_KEY 先例，避开 ChatSendRefs 加员穿三层。跨页消费无害：各页按自身
// 会话/数据源重算，值同不写零 UI 扰动）
export const ANSWER_VERSIONS_DIRTY_TICK_KEY: string = 'chatAnswerVersionsDirtyTick';

// 控制器 refs（页面装配处注入；dbReady/sending 现读闭包——首帧之后状态可能变化，不能只信
// 组件入参快照；switchTo = ChatBranchCtrl.switchToResult 结构化结果）
export interface ChatAnswerRefs {
  conversationId: () => string;
  dataSource: () => ChatDataSource;
  dbReady: () => boolean;
  sending: () => boolean;
  nodeIdOf: (msg: ChatMessage) => string;
  switchTo: (branchId: string, isCurrent: () => boolean) => Promise<BranchSwitchResult>;
  // 删除某回答版本（注入 = ChatBranchCtrl.deleteAnswerVersion 根闸包装；能力一律经 refs，
  // 本件不 import ChatBranchCtrl——头注释依赖方向纪律）
  deleteAnswerVersion: (branchId: string) => Promise<boolean>;
  toast: (text: string) => void;
}

// 视图快照（publish 整体替换——不经 tick 广播、不经 AppStorage；Content @State 承载）
export interface ChatAnswerView {
  loading: boolean;
  switching: boolean;
  errorText: string;
  needsReload: boolean;
  selectedAnswerId: string;
  choices: ChatAnswerChoice[];
}

// 视图接收端（至多一个：Content 出现时 attach、销毁时 detach；open/close 由 Content 接
// 面板可见性协调——open 之前必先 publish 目标视图）
export interface ChatAnswerViewSink {
  publish: (view: ChatAnswerView) => void;
  open: () => void;
  close: () => void;
}

// 读图归组一步的结果：stale = 目标已作废（代次/存活失效——静默不呈报）；result 空且非
// stale = 失败（failText 为中文原因）
interface AnswerReadResult {
  result: ChatAnswerChoices | null;
  stale: boolean;
  failText: string;
}

export class ChatAnswerCtrl {
  private refs: ChatAnswerRefs;
  private sink: ChatAnswerViewSink | null = null;
  // 请求代次（每次打开/作废推进）：异步完成面复核——过期结果不 publish/open/close
  private generation: number = 0;
  private disposed: boolean = false;
  // 打开链在途闸（防连点；入口同步抢、finally 放——只放自己的代次）
  private openingBusy: boolean = false;
  // 点选链在途闸（写入期间不接受第二次点选；同步抢、finally 放）
  private switchingBusy: boolean = false;
  // 版本步进重算在途闸（防相邻触发叠加：装载收尾与轮落库广播可能连拍）＋待跑标记——
  // 在途时后到者不丢，置位后本轮收尾补跑一次（全表重算天然覆盖两次触发的并集；原实现
  // 直接丢弃后到触发，翻页批次可能整批无步进器）
  private versionsBusy: boolean = false;
  private versionsPending: boolean = false;
  // 目标身份（打开时捕获；定与切换都按它复核——不信面板保存的 branchId）
  private targetMsgId: string = '';
  private targetNodeId: string = '';
  private targetUserId: string = '';
  private capturedCid: string = '';
  private capturedPathEpoch: number = 0;
  // 视图快照成分（会驱动 UI 的值由 Content @State 承载，本组只作 publish 的当前值）
  private loading: boolean = false;
  private switching: boolean = false;
  private errorText: string = '';
  private needsReload: boolean = false;
  private selectedAnswerId: string = '';
  private choices: ChatAnswerChoice[] = [];

  constructor(refs: ChatAnswerRefs) {
    this.refs = refs;
  }

  // ── 面板绑定（至多一个；Content 出现时 attach、销毁时 detach）──

  attachView(sink: ChatAnswerViewSink): void {
    this.sink = sink;
  }

  detachView(): void {
    this.sink = null;
  }

  // 作废旧查询（用户关闭 / 换目标前的失效动作）：推进代次、清目标与读结果；面板可见性由
  // 调用方（Content 关闭协调）处置。needsReload 不清——屏库不一致事实跨关闭保留（重开按
  // loadedBranchId 与图快照 defaultBranchId 重建）
  cancelView(): void {
    this.generation++;
    this.targetMsgId = '';
    this.targetNodeId = '';
    this.targetUserId = '';
    this.choices = [];
    this.loading = false;
    this.switching = false;
    this.errorText = '';
    this.openingBusy = false;
  }

  // 页面寿命释放（页面 aboutToDisappear 调用）：清 sink / 数组 / 待办身份；在途读按代次作废
  dispose(): void {
    this.disposed = true;
    this.generation++;
    this.sink = null;
    this.choices = [];
    this.targetMsgId = '';
    this.targetNodeId = '';
    this.targetUserId = '';
    this.loading = false;
    this.switching = false;
    this.errorText = '';
    this.openingBusy = false;
  }

  // ── 打开链（任务书 §5.3）──

  async openFor(msgId: string): Promise<void> {
    if (this.disposed || this.openingBusy) {
      return; // 在途防连点（第二次点击不叠请求；旧请求完成自会收尾）
    }
    this.openingBusy = true;
    this.generation++;
    const gen: number = this.generation;
    try {
      const ds: ChatDataSource = this.refs.dataSource();
      // ②入口现读（msg 存在 / assistant / opsHost / 正文非空）
      const msg: ChatMessage | null = ds.findMessage(msgId);
      if (msg === null || msg.kind !== 'assistant' || msg.opsHost !== true ||
        msg.text.trim() === '') {
        hilog.info(DOMAIN, TAG, '回答入口现读不满足，静默收（按键可见性已挡）：%{public}s', msgId);
        return;
      }
      if (!this.refs.dbReady()) {
        this.refs.toast('数据库未就绪，请稍候再试');
        return;
      }
      if (this.refs.sending()) {
        this.refs.toast('请先停止当前回复');
        return;
      }
      const nodeId: string = this.refs.nodeIdOf(msg);
      if (nodeId === '') {
        this.refs.toast('回复位置信息还没就绪，请稍后再试');
        return;
      }
      const cid: string = this.refs.conversationId();
      const epoch: number = ds.pathEpoch();
      // ③④读图归组（有行 + 严格 graph + 一次快照 + 纯函数归组；每步存活复检）
      const read: AnswerReadResult = await this.readGrouped(gen, cid, ds, epoch, nodeId, '');
      if (read.stale) {
        return; // 面板已关/已换目标/离页——静默
      }
      if (read.result === null) {
        this.refs.toast(read.failText);
        return;
      }
      const built: ChatAnswerChoices = read.result;
      if (built.userNodeId === '') {
        this.refs.toast('这条回复没有可切换的提问轮');
        return;
      }
      if (built.choices.length < 2) {
        this.refs.toast('本轮暂无其他回答');
        return;
      }
      if (this.disposed || gen !== this.generation) {
        return;
      }
      // 屏幕身份补建（限定规则：纯函数已按真实目标节点证明「库默认路径包含目标且该 U 末正文
      // 恰为点击行」，此处只是落账；已加载值永不被动覆盖）
      if (ds.loadedBranch() === '' && built.loadedBranchId !== '') {
        ds.markLoadedBranch(built.loadedBranchId);
      }
      this.targetMsgId = msgId;
      this.targetNodeId = nodeId;
      this.targetUserId = built.userNodeId;
      this.capturedCid = cid;
      this.capturedPathEpoch = ds.pathEpoch();
      this.choices = built.choices;
      this.selectedAnswerId = built.selectedAnswerId;
      this.needsReload = built.defaultBranchId !== built.loadedBranchId;
      this.loading = false;
      this.switching = false;
      this.errorText = '';
      // ⑤发布视图 → Content 设内容形态 answers → 现有 requestOpen（open 由 sink 实现）
      this.publishView();
      if (this.sink !== null) {
        this.sink.open();
      }
    } finally {
      // 只释放自身操作的占位；代次已被推进（cancel/dispose）时不碰新请求的占位
      if (gen === this.generation && !this.disposed) {
        this.openingBusy = false;
      }
    }
  }

  // ── 点选链（任务书 §5.4）──

  async choose(answerNodeId: string): Promise<void> {
    if (this.disposed || this.switchingBusy) {
      return; // 写入期间不接受第二次点选
    }
    if (this.targetNodeId === '' || answerNodeId === '') {
      return;
    }
    this.switchingBusy = true;
    this.switching = true;
    this.errorText = '';
    this.publishView();
    const gen: number = this.generation;
    const cid: string = this.capturedCid;
    const ds: ChatDataSource = this.refs.dataSource();
    const epoch: number = this.capturedPathEpoch;
    try {
      // ②现读守卫 + 同一 U 重算候选（目标 = 原点击轮尾节点；点选链用固定失效文案）
      const read: AnswerReadResult =
        await this.readGrouped(gen, cid, ds, epoch, this.targetNodeId, ANSWER_STALE_TEXT);
      if (read.stale) {
        return; // 面板已关/已换目标/离页——不再 publish/open/close
      }
      if (read.result === null) {
        this.errorText = read.failText; // 保留面板与原勾（sink 不动）
        return;
      }
      let hit: ChatAnswerChoice | null = null;
      for (const choice of read.result.choices) {
        if (choice.answerNodeId === answerNodeId) {
          hit = choice;
          break;
        }
      }
      if (hit === null) {
        this.errorText = ANSWER_STALE_TEXT;
        return;
      }
      // 新鲜读数回填（勾仍按屏幕身份算——不拿库 isActive 冒充）
      this.choices = read.result.choices;
      this.selectedAnswerId = read.result.selectedAnswerId;
      this.needsReload = read.result.defaultBranchId !== read.result.loadedBranchId;
      // ③正常状态点击原勾项：仅当 needsReload=false 且库默认 == 屏幕身份、候选仍一致时关闭
      if (answerNodeId === read.result.selectedAnswerId && !this.needsReload &&
        read.result.defaultBranchId === read.result.loadedBranchId) {
        this.publishView();
        if (this.sink !== null) {
          this.sink.close();
        }
        return;
      }
      // ④其余一律走结构化切换（isCurrent 闭包核目标代次/会话/数据源引用/销毁/占用；
      //    写入完成后不以旧路径代次拒绝自己的成功换源——闭包不含 pathEpoch）
      const isCurrent = (): boolean => !this.disposed && gen === this.generation &&
        this.refs.conversationId() === cid && this.refs.dataSource() === ds &&
        !ds.isDisplayDisposed() && !this.refs.sending();
      const result: BranchSwitchResult = await this.refs.switchTo(hit.branchId, isCurrent);
      if (this.disposed || gen !== this.generation) {
        return; // 离页/已换目标：作废请求不再改 UI（写入已不可取消，保留已落库默认值）
      }
      if (result.refreshed) {
        // ⑤全部成功：更新选中事实 + 清屏库差 + 关面板
        this.selectedAnswerId = answerNodeId;
        this.needsReload = false;
        this.errorText = '';
        this.publishView();
        if (this.sink !== null) {
          this.sink.close();
        }
        return;
      }
      // 失败：保留原 selectedAnswerId 与原屏勾（错误按 persisted 分相位；不静默关闭）
      if (result.persisted) {
        this.needsReload = true;
        this.errorText = result.reason !== '' ? result.reason : ANSWER_RELOAD_FAIL_TEXT;
      } else {
        this.errorText = result.reason !== '' ? result.reason : '切换失败，请重试';
      }
    } finally {
      this.switchingBusy = false;
      this.switching = false;
      if (!this.disposed && gen === this.generation) {
        this.publishView();
      }
    }
  }

  // 「删除此版本」上行（Sheet 上行 answerNodeId、重算与判定全在本编排）：照 choose 骨架
  //——现读闸 → readGrouped 重算命中行取 branchId → 选中项（正在看的回答）拒删（删除连带
  // 该回答全部后续且不可逆，正在阅读时一键删误触代价过大；「先切走再删」两步覆盖该诉求）→
  // refs 根闸删除 → 断点①被删恰为库默认分支（deleteBranch 活跃修正已同事务切落点并换源、
  // pathEpoch 前进——重查的 stillValid 恒 stale 会挂死旧列表）不重查直接收面板 → 断点②删除
  // 成功后重查回填（候选 <2 先回填再收，免关闭动画期残留已删行）；删除返回 false（根闸拒绝
  // 等）toast 已由编排层呈报、面板与列表保持原样
  async deleteAnswer(answerNodeId: string): Promise<void> {
    if (this.disposed || this.switchingBusy) {
      return; // 在途闸与点选共用——删除期间全行禁点禁删
    }
    if (this.targetNodeId === '' || answerNodeId === '') {
      return;
    }
    this.switchingBusy = true;
    this.switching = true;
    this.errorText = '';
    this.publishView();
    const gen: number = this.generation;
    const cid: string = this.capturedCid;
    const ds: ChatDataSource = this.refs.dataSource();
    const epoch: number = this.capturedPathEpoch;
    try {
      // 同一 U 重算候选命中该行（固定失效文案，同 choose）
      const read: AnswerReadResult =
        await this.readGrouped(gen, cid, ds, epoch, this.targetNodeId, ANSWER_STALE_TEXT);
      if (read.stale) {
        return; // 面板已关/已换目标/离页——静默
      }
      if (read.result === null) {
        this.errorText = read.failText; // 保留面板与原列表
        return;
      }
      let hit: ChatAnswerChoice | null = null;
      for (const choice of read.result.choices) {
        if (choice.answerNodeId === answerNodeId) {
          hit = choice;
          break;
        }
      }
      if (hit === null) {
        this.errorText = ANSWER_STALE_TEXT;
        return;
      }
      // 正在看的回答拒删（当前勾口径同 choose：勾按屏幕身份算，不信面板保存的旧勾）
      if (hit.answerNodeId === read.result.selectedAnswerId) {
        this.refs.toast('请先切换到其他回答，再删除这一版');
        return;
      }
      const deleted: boolean = await this.refs.deleteAnswerVersion(hit.branchId);
      if (this.disposed || gen !== this.generation) {
        return; // 离页/已换目标：作废请求不再改 UI
      }
      if (!deleted) {
        return;
      }
      // 断点①：屏幕已被换源（库默认分支被删、活跃修正切落点）——面板使命终结，不重查直接收
      //（步进字段由换源重载的装载收尾钩子重算；此处直调兜底「重载不经 runHistoryLoad」的
      // 形态——在途闸与装载收尾触发自然去重）
      if (ds.pathEpoch() !== epoch) {
        this.recomputeRowVersions();
        this.publishView();
        if (this.sink !== null) {
          this.sink.close();
        }
        return;
      }
      // 断点②：屏幕路径未动——重查回填（≥2 删除行经 choices 整体替换自然消失；<2 本轮已无
      // 其他回答，先回填再收）
      const after: AnswerReadResult =
        await this.readGrouped(gen, cid, ds, epoch, this.targetNodeId, ANSWER_STALE_TEXT);
      if (after.stale) {
        return; // 外部已换目标/离页——既有静默语义
      }
      if (after.result === null) {
        this.errorText = after.failText; // 读失败保留面板与原列表（重试键走 reloadChoices 自会拿到删后新列表）
        return;
      }
      this.choices = after.result.choices;
      this.selectedAnswerId = after.result.selectedAnswerId;
      this.needsReload = after.result.defaultBranchId !== after.result.loadedBranchId;
      this.publishView();
      // 屏幕路径未动——其他轮的步进计数仍需随删除收口（本轮由回填后的面板列表自然呈现）
      this.recomputeRowVersions();
      if (after.result.choices.length < 2) {
        if (this.sink !== null) {
          this.sink.close();
        }
      }
    } finally {
      this.switchingBusy = false;
      this.switching = false;
      if (!this.disposed && gen === this.generation) {
        this.publishView();
      }
    }
  }

  // 面板内「重试」（失败保留面板与原勾，重试重查候选——同一目标，不换生成代次）
  async reloadChoices(): Promise<void> {
    if (this.disposed || this.switchingBusy || this.openingBusy) {
      return;
    }
    if (this.targetNodeId === '' || this.targetMsgId === '') {
      return;
    }
    this.openingBusy = true;
    const gen: number = this.generation;
    const cid: string = this.capturedCid;
    const ds: ChatDataSource = this.refs.dataSource();
    const epoch: number = this.capturedPathEpoch;
    this.loading = true;
    this.errorText = '';
    this.publishView();
    try {
      const read: AnswerReadResult =
        await this.readGrouped(gen, cid, ds, epoch, this.targetNodeId, ANSWER_STALE_TEXT);
      if (read.stale) {
        return;
      }
      if (read.result === null) {
        this.errorText = read.failText;
        return;
      }
      const built: ChatAnswerChoices = read.result;
      if (built.userNodeId === '' || built.choices.length < 2) {
        this.errorText = '本轮暂无其他回答';
        return;
      }
      this.choices = built.choices;
      this.selectedAnswerId = built.selectedAnswerId;
      this.needsReload = built.defaultBranchId !== built.loadedBranchId;
    } finally {
      this.loading = false;
      if (!this.disposed && gen === this.generation) {
        this.publishView();
      }
      if (gen === this.generation && !this.disposed) {
        this.openingBusy = false;
      }
    }
  }

  // ── 读图归组一步（打开链与两条重查共用）──

  // 会话闸（有行 + 严格 graph）→ 一次图快照 → 纯函数归组；每步 await 后存活复检（代次/
  // 会话/数据源引用/销毁/占用/路径代次）——过期回 stale（静默，不动 UI）；纯函数的中文判据
  // 错误按 staleText 覆写（打开链传 '' = 保留原文案；点选链传固定文案）
  private async readGrouped(gen: number, cid: string, ds: ChatDataSource, epoch: number,
    targetNodeId: string, staleText: string): Promise<AnswerReadResult> {
    const staleResult: AnswerReadResult = { result: null, stale: true, failText: '' };
    const failResult = (text: string): AnswerReadResult =>
      ({ result: null, stale: false, failText: text });
    let hasRow: boolean = false;
    try {
      hasRow = await conversationHasRow(cid);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '会话行读取失败：%{public}s', (e as Error).message);
      return failResult(ANSWER_READ_FAIL_TEXT);
    }
    if (!this.stillValid(gen, cid, ds, epoch)) {
      return staleResult;
    }
    if (!hasRow) {
      return failResult('暂无可切换回答');
    }
    let state: string = '';
    try {
      state = await conversationMigrateState(cid);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '会话态读取失败：%{public}s', (e as Error).message);
      return failResult(ANSWER_READ_FAIL_TEXT);
    }
    if (!this.stillValid(gen, cid, ds, epoch)) {
      return staleResult;
    }
    if (state !== SESSION_GRAPH) {
      return failResult(TOMBSTONE_TOAST_TEXT);
    }
    let snapshot: AnswerGraphSnapshot | null = null;
    try {
      snapshot = await queryAnswerGraphSnapshot(cid);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '回答图快照读取失败：%{public}s', (e as Error).message);
      return failResult(ANSWER_READ_FAIL_TEXT);
    }
    if (!this.stillValid(gen, cid, ds, epoch)) {
      return staleResult;
    }
    try {
      const built: ChatAnswerChoices =
        buildAnswerChoices(snapshot, ds.loadedBranch(), targetNodeId);
      return { result: built, stale: false, failText: '' };
    } catch (e) {
      const message: string = (e as Error).message;
      return failResult(staleText !== '' ? staleText :
        (message !== '' ? message : ANSWER_READ_FAIL_TEXT));
    }
  }

  // 存活复检（每次 await 后）：目标代次 / 会话 / 数据源引用 / 页面存活 / 未在发送 /
  // 路径视图代次未被外部换源推进（本次切换自身的换源在写完之后，不再复核本项）
  private stillValid(gen: number, cid: string, ds: ChatDataSource, epoch: number): boolean {
    return !this.disposed && gen === this.generation &&
      this.refs.conversationId() === cid && this.refs.dataSource() === ds &&
      !ds.isDisplayDisposed() && !this.refs.sending() && ds.pathEpoch() === epoch;
  }

  // ── 回答版本步进域（触发五面 = 装载/换源收尾〔onHistorySettled〕+ 翻页收尾〔onOlderLoaded，
  // 前插批行对象须补步进字段〕+ 轮落库回填后〔stampNodeRef 后广播 tick〕+ 面板删除成功后
  //〔deleteAnswer 内直调〕+ 步进切换成功后〔经 reloadBranchPath → 装载收尾自动覆盖，不另挂〕）──

  // 全表重算：一次图快照 + 逐轮 buildAnswerChoices/buildQuestionChoices，写 ChatMessage
  // 步进四字段（值同不写，@Observed 对象级观察驱动行内步进器渲染）。纯函数抛错 = 该轮无
  // 步进器（空正文失败轮 / 目标非当前末正文 / 坏图——宁缺勿错，与面板打开口径同源）；
  // 读失败保旧值不清（面板同口径）。await 后按「会话 / 数据源引用 / 路径代次」复核，过期
  // 快照静默弃。在途触发不丢：置 versionsPending，本轮收尾补跑一次
  async recomputeRowVersions(): Promise<void> {
    if (this.disposed) {
      return;
    }
    if (this.versionsBusy) {
      this.versionsPending = true;
      return;
    }
    const ds: ChatDataSource = this.refs.dataSource();
    if (!this.refs.dbReady() || ds.isDisplayDisposed()) {
      return;
    }
    this.versionsBusy = true;
    const cid: string = this.refs.conversationId();
    const epoch: number = ds.pathEpoch();
    try {
      // 目标行快照（快照成员外的新入列行——live 流式行不参与，等下一次触发）：assistant
      // 答案行（opsHost + 非空正文）走回答归组；user 行（编辑产出提问变体）走提问归组——
      // 两套字段互不干扰
      const targets: ChatMessage[] = [];
      for (const m of ds.allMessages()) {
        if (m.kind === 'assistant' && m.opsHost === true && m.text.trim() !== '') {
          targets.push(m);
        } else if (m.kind === 'user') {
          targets.push(m);
        } else {
          this.clearVersionFields(m);
        }
      }
      if (targets.length === 0) {
        return;
      }
      let snapshot: AnswerGraphSnapshot;
      try {
        snapshot = await queryAnswerGraphSnapshot(cid);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '版本步进图快照读取失败：%{public}s', (e as Error).message);
        return; // 读失败保旧值不清
      }
      if (this.disposed || this.refs.conversationId() !== cid ||
        this.refs.dataSource() !== ds || ds.pathEpoch() !== epoch) {
        return; // 离页/换源/换会话——快照过期静默弃
      }
      for (const m of targets) {
        const nodeId: string = this.refs.nodeIdOf(m);
        if (nodeId === '') {
          this.clearVersionFields(m);
          continue;
        }
        if (m.kind === 'user') {
          this.fillQuestionVersions(m, snapshot, ds.loadedBranch(), nodeId);
          continue;
        }
        let built: ChatAnswerChoices;
        try {
          built = buildAnswerChoices(snapshot, ds.loadedBranch(), nodeId);
        } catch (_e) {
          this.clearVersionFields(m); // 归组不可证——该轮无步进器
          continue;
        }
        let index: number = -1;
        for (let i = 0; i < built.choices.length; i++) {
          if (built.choices[i].answerNodeId === built.selectedAnswerId) {
            index = i;
            break;
          }
        }
        if (index < 0) {
          this.clearVersionFields(m);
          continue;
        }
        this.writeStepper(m, built.choices.length, index,
          index > 0 ? built.choices[index - 1].branchId : '',
          index < built.choices.length - 1 ? built.choices[index + 1].branchId : '');
      }
    } finally {
      this.versionsBusy = false;
      if (this.versionsPending) {
        this.versionsPending = false;
        this.recomputeRowVersions();
      }
    }
  }

  // 清步进字段（两套；值同不写——只在已写过时清）
  private clearVersionFields(m: ChatMessage): void {
    if (m.ansVersionCount !== undefined) {
      m.ansVersionCount = undefined;
      m.ansVersionIndex = undefined;
      m.ansPrevBranch = undefined;
      m.ansNextBranch = undefined;
    }
    if (m.qsVersionCount !== undefined) {
      m.qsVersionCount = undefined;
      m.qsVersionIndex = undefined;
      m.qsPrevBranch = undefined;
      m.qsNextBranch = undefined;
    }
  }

  // 步进字段写入器（回答步进用；值同不写——@Observed 逐字段赋值各触发一次刷新）
  private writeStepper(m: ChatMessage, count: number, index: number,
    prevBranch: string, nextBranch: string): void {
    if ((m.ansVersionCount ?? 0) !== count || (m.ansVersionIndex ?? -1) !== index ||
      (m.ansPrevBranch ?? '') !== prevBranch || (m.ansNextBranch ?? '') !== nextBranch) {
      m.ansVersionCount = count;
      m.ansVersionIndex = index;
      m.ansPrevBranch = prevBranch;
      m.ansNextBranch = nextBranch;
    }
  }

  // 提问变体填充：同 parent 的 user 兄弟归组，写 qs* 四字段
  private fillQuestionVersions(m: ChatMessage, snapshot: AnswerGraphSnapshot,
    loadedBranch: string, nodeId: string): void {
    let built: ChatQuestionChoices;
    try {
      built = buildQuestionChoices(snapshot, loadedBranch, nodeId);
    } catch (_e) {
      this.clearVersionFields(m); // 归组不可证（目标不在屏幕路径等）——无步进器
      return;
    }
    let index: number = -1;
    for (let i = 0; i < built.choices.length; i++) {
      if (built.choices[i].userNodeId === built.selectedUserNodeId) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      this.clearVersionFields(m);
      return;
    }
    const count: number = built.choices.length;
    const prevBranch: string = index > 0 ? built.choices[index - 1].branchId : '';
    const nextBranch: string = index < count - 1 ? built.choices[index + 1].branchId : '';
    if ((m.qsVersionCount ?? 0) !== count || (m.qsVersionIndex ?? -1) !== index ||
      (m.qsPrevBranch ?? '') !== prevBranch || (m.qsNextBranch ?? '') !== nextBranch) {
      m.qsVersionCount = count;
      m.qsVersionIndex = index;
      m.qsPrevBranch = prevBranch;
      m.qsNextBranch = nextBranch;
    }
  }

  // 步进切换（行内步进器左右箭头上行）：现读重算该轮候选（不信用行内缓存字段——点击一刻
  // 图可能已变），取当前勾相邻项走既有 switchToResult 切换链（落库默认分支 + 换源重载，
  // 与面板点选同一事实链）。发送中拒（切换整路径换源，不得与在途轮并行——choose 同口径）；
  // 成功零 toast（换源后装载收尾自动重算全表步进字段），失败按结构化 reason 呈报。
  // ★ 两角色同口——assistant 答案行切回答版本、user 行切提问版本（判据 = 节点身份 + 归组
  // 可证，两纯函数各自裁决）
  async stepVersion(msgId: string, direction: number): Promise<void> {
    if (this.disposed) {
      return;
    }
    if (this.refs.sending()) {
      this.refs.toast('请先停止当前回复');
      return;
    }
    const ds: ChatDataSource = this.refs.dataSource();
    const msg: ChatMessage | null = ds.findMessage(msgId);
    // 两角色同口（见方法头注释）
    if (msg === null || (msg.kind !== 'assistant' && msg.kind !== 'user')) {
      return; // 目标已失效（换源冲掉等）——静默
    }
    if (msg.kind === 'assistant' && (msg.opsHost !== true || msg.text.trim() === '')) {
      return;
    }
    const nodeId: string = this.refs.nodeIdOf(msg);
    if (nodeId === '') {
      this.refs.toast('消息位置信息还没就绪，请稍后再试');
      return;
    }
    const cid: string = this.refs.conversationId();
    const epoch: number = ds.pathEpoch();
    let snapshot: AnswerGraphSnapshot;
    try {
      snapshot = await queryAnswerGraphSnapshot(cid);
    } catch (_e) {
      this.refs.toast(ANSWER_READ_FAIL_TEXT);
      return;
    }
    if (this.disposed || this.refs.conversationId() !== cid ||
      this.refs.dataSource() !== ds || ds.pathEpoch() !== epoch || this.refs.sending()) {
      return; // await 窗口换源/起轮——静默弃
    }
    // 归组（按角色分流）：两路都归一成「相邻项的代表分支」
    let targetBranch: string = '';
    if (msg.kind === 'user') {
      let builtQ: ChatQuestionChoices;
      try {
        builtQ = buildQuestionChoices(snapshot, ds.loadedBranch(), nodeId);
      } catch (_e) {
        this.refs.toast(ANSWER_STALE_TEXT);
        return;
      }
      let qIndex: number = -1;
      for (let i = 0; i < builtQ.choices.length; i++) {
        if (builtQ.choices[i].userNodeId === builtQ.selectedUserNodeId) {
          qIndex = i;
          break;
        }
      }
      const qTarget: number = qIndex + direction;
      if (qIndex < 0 || qTarget < 0 || qTarget >= builtQ.choices.length) {
        return; // 边界外兜底（UI 边界箭头已置灰）
      }
      targetBranch = builtQ.choices[qTarget].branchId;
    } else {
      let built: ChatAnswerChoices;
      try {
        built = buildAnswerChoices(snapshot, ds.loadedBranch(), nodeId);
      } catch (_e) {
        this.refs.toast(ANSWER_STALE_TEXT);
        return;
      }
      let index: number = -1;
      for (let i = 0; i < built.choices.length; i++) {
        if (built.choices[i].answerNodeId === built.selectedAnswerId) {
          index = i;
          break;
        }
      }
      const targetIndex: number = index + direction;
      if (index < 0 || targetIndex < 0 || targetIndex >= built.choices.length) {
        return; // 边界外兜底（UI 边界箭头已置灰；过期字段误导到这即静默）
      }
      targetBranch = built.choices[targetIndex].branchId;
    }
    const isCurrent = (): boolean => !this.disposed &&
      this.refs.conversationId() === cid && this.refs.dataSource() === ds &&
      !ds.isDisplayDisposed() && !this.refs.sending();
    const result: BranchSwitchResult = await this.refs.switchTo(targetBranch, isCurrent);
    if (this.disposed) {
      return;
    }
    if (!result.refreshed) {
      this.refs.toast(result.reason !== '' ? result.reason : ANSWER_RELOAD_FAIL_TEXT);
    }
  }

  // 视图快照发布（同步整体替换——不经 tick 广播、不经 AppStorage）
  private publishView(): void {
    const sink: ChatAnswerViewSink | null = this.sink;
    if (sink === null) {
      return;
    }
    sink.publish({
      loading: this.loading,
      switching: this.switching,
      errorText: this.errorText,
      needsReload: this.needsReload,
      selectedAnswerId: this.selectedAnswerId,
      choices: this.choices
    });
  }
}
