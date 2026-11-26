// 会话内分支与会话内历史编辑编排域。
// 域定义一句话：**分支切换与删除 / 历史消息编辑（user 与 assistant 两角色）的编排**——判据经
// ChatBranchPolicy 纯函数叶子，DB 读写经 ChatBranchSource（分支域）与 ChatContextSource
//（路由/存在性读口）单点（删除命令经 GraphTransfer 生产入口、两角色编辑落库经 GraphEditFork
// 生产入口）；重试起轮复用既有重试链（ChatRetryCtrl.retryAt）。★ user 编辑**只保存不重发**
//——不经发送链起轮，需要回答时由用户另发一条消息（决明拍板参照 rik）。
// · 为什么新开本件（反碎片三问）：职责一句话成立；无既有同域可并（ChatRetryCtrl 是图会话
//   重试域，ChatSendCtrl 与 ChatPage 均越 1200 硬线）；实逻辑非转接壳（四条入口各有守卫/
//   建分支/视图换源/错误呈报的完整编排）。
// · 依赖方向（零环红线，坑50）：本件 → ChatBranchPolicy + ChatBranchSource +
//   ChatContextSource + 组件层模型单向；**不 import ChatSendCtrl/ChatRetryCtrl**——起轮
//   能力经 refs 回调上行页面注入（loadCtrl/compressCtrl 同款 refs 闭包姿势）。
// · 附件保留口径（L2「只改新节点引用」）：编辑保留 = 把原 user 节点的附件**引用**挂到新节点
//  （复用既有资源行与本地文件，不复制、不删旧引用、不动旧行归属）；新回答只基于新提问。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { queryAttachmentsForMessages } from '../../common/store/ChatDb';
import { removeAttachmentFiles } from '../../common/store/AttachmentDb';
import { BranchLineageDeleteResult, deleteBranchLineageProd } from '../../common/store/GraphTransfer';
import { CopiedConversation, CopyPrefixInput, copyConversationPrefix }
  from '../../common/store/ConversationForkCopy';
import { AttachmentBrief, hideAttachAnnotate } from '../../common/AttachmentUtil';
import { BranchAllow, BranchTargetFacts, canDeleteAt, canEditAssistant, canEditUser,
  canForkAt, canRetryAt, canSwitchPath, identityGate, KIND_ASSISTANT, KIND_USER,
  resolveNodeIdOf, sessionGate, SESSION_GRAPH, SESSION_LEGACY, TOMBSTONE_TOAST_TEXT }
  from '../../common/chat/ChatBranchPolicy';
// ★ 拆分笔：分支域六符号改从 ChatBranchSource 取，路由/存在性两符号留 ChatContextSource
import { BranchSummary,
  insertAttachmentRefsForIds, queryConversationBranches, queryNodeParentId, switchActiveBranch }
  from '../../common/chat/ChatBranchSource';
import { conversationHasRow, conversationMigrateState }
  from '../../common/chat/ChatContextSource';
import { editAssistantForkProd, editUserForkProd, EditAssistantForkResult }
  from '../../common/store/GraphEditFork';
// 节点级谱系剪枝删除命令（命令域件，级联与 head 回退在彼件单源）
import { NodeLineageDeleteResult, deleteNodeLineageProd }
  from '../../common/store/GraphNodeDelete';
import { ChatMessage } from './ChatMessageCompose';
import { ChatDataSource } from './ChatDataSource';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';

const DOMAIN: number = 0xD5A4;
const TAG: string = 'ChatBranchCtrl';

// 页面接线集（@State 写与起轮能力经回调上行——refs 闭包延迟求值，同 loadCtrl/compressCtrl 姿势）
export interface ChatBranchRefs {
  conversationId: () => string;
  dataSource: () => ChatDataSource;
  dbReady: () => boolean;
  sending: () => boolean;
  toast: (message: string) => void;
  // 会话格式态现读（词表已收缩两值 graph/legacy；判据闸的会话态输入，读失败按 legacy 呈现
  //——可用性优先同各加载链口径）
  migrateState: () => Promise<string>;
  // 当前活动分支（'' = 非图态）
  activeBranch: () => Promise<string>;
  // 当前分支路径视图重载（重建完成后 settle——「先换源后起轮」的次序靠它；返 false =
  // 态读异常/历史读取失败，视图未换源，调用须中止后续动作）
  reloadBranchPath: () => Promise<boolean>;
  // 编辑面板开关（两角色共用：入参 = 带出原文——面板初值快照；保存按在编节点身份分流
  // submitEditMessage）
  openEditAssistant: (initial: string) => void;
}

// 阶段化切换结果——把「库默认已写入」与「屏幕确已换源」两个事实分开呈报：persisted =
// 默认分支已落库（不可回滚）；refreshed = 视图确已重载到目标分支（成功还须
// dataSource.loadedBranch() === branchId 才算）。reason = 面向用户的中文原因（'' = 无）
export interface BranchSwitchResult {
  persisted: boolean;
  refreshed: boolean;
  branchId: string;
  reason: string;
}

export class ChatBranchCtrl {
  private refs: ChatBranchRefs;
  // ── 编辑态（进行中的历史消息编辑；同一时刻至多一条。两角色同用一条面板链：
  // beginEditUser/beginEditAssistant 记节点与父并作废另一角色在编态，提交成功后清）
  private editNodeId: string = '';
  private editParentId: string | null = null;
  private editKeepIds: string[] = [];
  // 原提问引用全文快照（编辑引用保真笔）：编辑只改问题正文，引用是「被引用内容的已发事实」
  // 不随编辑失效——保存时随分叉写入编辑版节点（DB v61 quote_text）。来源 = 视图消息
  // quoteText（库列投影，与气泡引用标注同源）。'' = 无引用，不写列
  private editQuoteText: string = '';
  // 复制为新会话在途位（复制是查→映射→写文件→单事务发布的多秒链，原无在途闸——连点两下
  // 即两路复制并发出两个副本。入口置位、链尾 finally 复位〔成败两路〕）
  private copying: boolean = false;
  // ── 助手编辑态（与 user 编辑态共用同一面板——进入任一角色编辑时作废另一角色在编态，
  // 提交按 editNodeId 优先分流〔submitEditMessage〕，交叉残留会把保存写错角色）：节点与父由
  // beginEditAssistant 记、submitEditAssistant 在分叉与切换成功后清（自检轮修复——原「提交
  // 入口即清」：首次保存失败面板留存可重试，重试时父已清 → editAtNodeId 走 null 豁免把编辑
  // 节点落成根节点并切过去，视图静默丢全部前史）；面板取消路径不清 = 下次进入覆写（幂等无害）
  private editAssistantNodeId: string = '';
  private editAssistantParentId: string | null = null;
  // 切换在途闸：共同执行体私有布尔，入口同步占位、finally 释放——避免旧分支面板与新回答
  // 面板并发切换（同一时刻至多一路在写）
  private switching: boolean = false;

  constructor(refs: ChatBranchRefs) {
    this.refs = refs;
  }

  // ── 判据面（可见性与拒绝理由；文案单源在 ChatBranchPolicy）──

  // 目标消息事实摘取（视图消息 → 判据输入）：roundOpen = 该行之后到下一轮之前仍有后续
  //（工具卡/中间轮 ⇒ 本轮未收尾）；graphIdentity = 图身份可锚（live 行看 nodeId 回填，
  // 路径窗口行 id 即节点 id）。★ roundOpen 只对 assistant 目标计算——user 行之后紧跟的
  // assistant 行是本轮答案本体（已收尾），把答案行当 roundOpen 会把「已答完」误判成「还在跑」
  //，user 消息的编辑/创建分支/复制三入口全被 settledGate 拒死。user 行的在跑态已由
  // running（sending）与 streaming 两闸覆盖，无需第三闸
  private factsOf(msg: ChatMessage, session: string): BranchTargetFacts {
    const all: ChatMessage[] = this.refs.dataSource().allMessages();
    let idx: number = -1;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === msg.id) {
        idx = i;
        break;
      }
    }
    let roundOpen: boolean = false;
    if (msg.kind !== KIND_USER) {
      for (let i = idx + 1; idx >= 0 && i < all.length; i++) {
        const k: string = all[i].kind;
        if (k === KIND_USER) {
          break; // 下一轮开始——本轮已收尾
        }
        if (k === 'tool' || k === KIND_ASSISTANT) {
          roundOpen = true;
          break;
        }
      }
    }
    return {
      kind: msg.kind,
      streaming: msg.streaming === true,
      roundOpen: roundOpen,
      graphIdentity: this.nodeIdOf(msg) !== '',
      session: session,
      running: this.refs.sending()
    };
  }

  // 目标节点的图身份（'' = 不可锚）：内存行优先取回填的 nodeId；路径窗口行的 id 即节点 id。
  // ★ 实时行与在途行一律不放行路径回退——发送准备失败的残留行永不回填 nodeId，旧判据的
  // id 回退把它当节点身份 = 伪锚（请求带伪 id 落到 DB 层）。判据单源在
  // ChatBranchPolicy.resolveNodeIdOf，本方法一行式委托，禁第二份判据
  nodeIdOf(msg: ChatMessage): string {
    return resolveNodeIdOf(msg.nodeId ?? '', msg.live === true, msg.streaming === true,
      this.refs.dataSource().oldestAnchor() !== null, msg.id);
  }

  // 会话态现读（判据闸输入；读失败按 legacy 呈现 = 新入口禁用并给墓碑句，不静默放行）。
  // 格式态词表收缩两值——graph 原样透传，**其余一律归 legacy**（非 graph 即墓碑：旧格式 /
  // 历史 migrating 残值 / 脏值 / 读失败同判）
  private sessionNow(): Promise<string> {
    return this.refs.migrateState()
      .then((state: string): string => state === SESSION_GRAPH ? SESSION_GRAPH : SESSION_LEGACY)
      .catch((e: Object): string => {
        hilog.warn(DOMAIN, TAG, '会话态读取失败，按墓碑态呈现：%{public}s', (e as Error).message);
        return SESSION_LEGACY;
      });
  }

  // ── 分支切换与删除（分支语义收敛笔：切换唯一消费面 =「其他回答」链的 switchToResult，
  // 删除唯一消费面 = deleteAnswerVersion 根闸包装）──

  // 会话级判据的空事实（切分支/删分支是会话级操作，与目标消息无关——只消费会话态与占用；
  // kind 空 = 四判据的适用性检查一律不拦，见 canSwitchPath 只过会话/占用两闸）
  private factsOfSession(session: string): BranchTargetFacts {
    return {
      kind: KIND_ASSISTANT, streaming: false, roundOpen: false, graphIdentity: true,
      session: session, running: this.refs.sending()
    };
  }

  // 阶段化切分支——「其他回答」链的唯一分支写入口（单一分支写入口 switchActiveBranch，
  // 禁第二套 SQL）。调用次序固定：①同步闸（在途 / sending / DB / branchId / 代次）→
  // ②异步校验（会话有行 + 严格 graph + 目标分支确属本会话；每次 await 后复核代次/会话/
  // 数据源引用/销毁/占用，过期即停不再写）→ ③落库默认分支（成功即 persisted=true，绝不
  // 提前改勾）→ ④写后复核（已离页 / 新一轮已开始：不重载不改 UI，也不回滚已保存的选择）→
  // ⑤同一 reloadBranchPath 重载（**同分支也必执行**，库默认不代表屏幕；成功还须
  // loadedBranch() === branchId）。isCurrent 由调用方给；写入完成后不以旧路径代次拒绝自己
  // 的成功换源。异常不返回空列表、不声称成功
  async switchToResult(branchId: string, isCurrent: () => boolean): Promise<BranchSwitchResult> {
    const reject = (reason: string): BranchSwitchResult =>
      ({ persisted: false, refreshed: false, branchId: branchId, reason: reason });
    // ①同步闸
    if (this.switching) {
      return reject('正在切换分支，请稍候');
    }
    if (this.refs.sending()) {
      return reject('请先停止当前回复');
    }
    if (!this.refs.dbReady()) {
      return reject('数据库未就绪，请稍候再试');
    }
    if (branchId === '') {
      return reject('目标分支不存在，请刷新后重试');
    }
    if (!isCurrent()) {
      return reject('');
    }
    this.switching = true;
    const cid: string = this.refs.conversationId();
    const ds: ChatDataSource = this.refs.dataSource();
    // 存活复检（每次 await 后）：目标代次 / 会话 / 数据源引用 / 销毁 / 占用
    const alive = (): boolean => isCurrent() && this.refs.conversationId() === cid &&
      this.refs.dataSource() === ds && !ds.isDisplayDisposed() && !this.refs.sending();
    try {
      // ②异步校验：会话有行（无行与 legacy 同值分义——I3 口径先判有行）
      let hasRow: boolean = false;
      try {
        hasRow = await conversationHasRow(cid);
      } catch (_e) {
        return reject('会话状态读取失败，请重试');
      }
      if (!alive()) {
        return reject('');
      }
      if (!hasRow) {
        return reject('当前会话还没有内容，暂时不能切换分支');
      }
      // 严格 graph（其余态一律 fail-closed；文案单源复用墓碑句）
      let state: string = '';
      try {
        state = await conversationMigrateState(cid);
      } catch (_e) {
        return reject('会话状态读取失败，请重试');
      }
      if (!alive()) {
        return reject('');
      }
      if (state !== SESSION_GRAPH) {
        return reject(TOMBSTONE_TOAST_TEXT);
      }
      // 目标分支归属本会话（分支域读侧单点复用——不另写裸 SQL）
      let inConversation: boolean = false;
      try {
        const branches: BranchSummary[] = await queryConversationBranches(cid);
        for (const b of branches) {
          if (b.branchId === branchId) {
            inConversation = true;
            break;
          }
        }
      } catch (_e) {
        return reject('分支信息读取失败，请重试');
      }
      if (!alive()) {
        return reject('');
      }
      if (!inConversation) {
        return reject('目标分支不存在，请刷新后重试');
      }
      // ③落库默认分支（persisted 自此不可回滚）
      try {
        await switchActiveBranch(cid, branchId);
      } catch (e) {
        return reject('切换分支失败：' + (e as Error).message);
      }
      // ④写后复核：已离页 / 新一轮开始——不重载不改 UI，不回滚已保存的选择
      if (!alive()) {
        return { persisted: true, refreshed: false, branchId: branchId,
          reason: '选择已保存，但对话状态已变化，请重进会话查看' };
      }
      // ⑤同链重载（同分支也必执行；成功还须屏幕身份确为目标分支）
      let refreshed: boolean = false;
      try {
        refreshed = await this.refs.reloadBranchPath();
      } catch (_e) {
        refreshed = false;
      }
      if (!refreshed || ds.loadedBranch() !== branchId) {
        return { persisted: true, refreshed: false, branchId: branchId,
          reason: '选择已保存，但对话刷新失败。可点回答重试，或重进会话' };
      }
      return { persisted: true, refreshed: true, branchId: branchId, reason: '' };
    } finally {
      this.switching = false;
    }
  }

  // 「其他回答」面板删除某回答版本上行——**根分支防线在本编排层**（任务书点名判据）：
  // deleteBranch 本体无根判定（原防线在退役的分支面板 UI 层），而回答面板侧经图快照拿不到
  // parentBranchId（ChatBranchSource 属存储锁内件，不为判根加列），故根闸只能落在本编排层：
  // 查分支列表取 parentBranchId，''（根分支 = 会话初始路径，删除近乎清空会话）→ toast 拒绝
  // 返回 false；非根 → 复用 deleteBranch 原样执行（谱系全删 + 活跃修正 + 附件清理）
  deleteAnswerVersion(branchId: string): Promise<boolean> {
    if (branchId === '') {
      return Promise.resolve(false);
    }
    return queryConversationBranches(this.refs.conversationId())
      .then((branches: BranchSummary[]): Promise<boolean> => {
        let isRoot: boolean = true;
        for (const b of branches) {
          if (b.branchId === branchId) {
            isRoot = b.parentBranchId === '';
            break;
          }
        }
        if (isRoot) {
          this.refs.toast('初始路径不能删除');
          return Promise.resolve(false);
        }
        return this.deleteBranch(branchId);
      })
      .catch((): boolean => false);
  }

  // 删除分支（面板行内删除键上行）：占用 + 会话态两闸（与切换同款）→ 图域删除命令（谱系
  // 全删 + 活跃分支修正同事务）→ commit 后删附件文件（回滚不得已删文件红线——路径随命令
  // 返回值出，文件删除恒在 commit 之后）→ 活跃分支在被删集时视图换源（换源失败如实呈报）。
  // 返回 true = 库态已删，面板据此重读
  deleteBranch(branchId: string): Promise<boolean> {
    if (this.refs.sending()) {
      this.refs.toast('请先停止当前回复');
      return Promise.resolve(false);
    }
    if (branchId === '') {
      return Promise.resolve(false);
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return Promise.resolve(false);
    }
    return this.sessionNow().then((session: string): Promise<boolean> => {
      const gate: BranchAllow = canSwitchPath(this.factsOfSession(session));
      if (!gate.allowed) {
        this.refs.toast(gate.reason);
        return Promise.resolve(false);
      }
      return this.runDeleteBranch(branchId);
    }).catch((e: Object): boolean => {
      this.refs.toast('删除分支失败：' + (e as Error).message);
      return false;
    });
  }

  private runDeleteBranch(branchId: string): Promise<boolean> {
    return deleteBranchLineageProd(branchId)
      .then((result: BranchLineageDeleteResult): Promise<boolean> => {
        // 附件文件删除（best-effort——单文件失败静默，启动收敛自愈；与删会话同款）
        removeAttachmentFiles(result.invalidatedLocalPaths);
        if (!result.activeBranchSwitched) {
          this.refs.toast('已删除分支');
          return Promise.resolve(true);
        }
        // 活跃分支在被删集：库态已同事务切到落点分支，此处只重载视图；换源失败不吞「已删除」
        // 事实（屏库分叉由提示语交代）
        return this.refs.reloadBranchPath().then((refreshed: boolean): boolean => {
          this.refs.toast(refreshed ? '已删除分支' : '分支已删除，但视图刷新失败，请重进会话');
          return true;
        });
      });
  }

  // ── 独立会话 fork（S3·笔5）与编辑入口（S4；会话内建分支三口已整删；user 编辑改「面板
  // 保存 + 不重发」——两角色编辑统一走 GraphEditFork 单事务分叉命令〔editAssistantFork /
  // editUserFork〕）──

  // 空锚早退的统一呈报（三入口原为静默早退，降级态零反馈）。早退保留（不可锚即错锚——
  // 建分支会落到别处、编辑会建空 head 分支），但先现读会话态给准确理由：会话态不过闸
  //（非 graph 即墓碑）用 sessionGate 文案，图态而锚缺失用 identityGate 文案——文案单源在
  // ChatBranchPolicy，本处不另抄第二份
  private rejectEmptyAnchor(): void {
    this.sessionNow().then((session: string): void => {
      const facts: BranchTargetFacts = {
        kind: '', streaming: false, roundOpen: false, graphIdentity: false,
        session: session, running: this.refs.sending()
      };
      const s: string = sessionGate(facts);
      this.refs.toast(s !== '' ? s : identityGate(facts));
    });
  }

  // 消息菜单「复制为新会话」上行（M1：物化所选前缀与附件、新会话独立拥有）：判据复用入口
  // 守卫（占用 / 会话态 / 图身份 / 收尾四闸同源，不另造第二套），过闸后交复制编排域
  //（ConversationForkCopy.copyConversationPrefix：冻结源 + 映射 + 文件准备 + 单事务发布）。
  // 视图处置 = 留在原会话 + 提示（不换源 = 不打断当前阅读位置）；刷新 = bump
  // SESSION_LIST_RELOAD_KEY（会话列表既有广播键）。★ 复制在途位：多秒链连点即并发出两个
  // 副本；置位在入口同步完成，链尾 finally 复位（成败两路，漏复位即复制键永久失效）
  copyToNewSession(nodeId: string): void {
    if (nodeId === '') {
      this.rejectEmptyAnchor();
      return;
    }
    if (this.copying) {
      this.refs.toast('正在复制，请稍候');
      return;
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return;
    }
    this.copying = true;
    // 内层链须 return（finally 挂在整链末端——原实现在 then 里起内层链不返回，复位会早于
    // 复制完成 = 在途闸形同虚设）
    this.entryGuard(nodeId, 'fork')
      .then((ok: boolean): Promise<void> => {
        if (!ok) {
          return Promise.resolve();
        }
        return this.refs.activeBranch().then((branchId: string): Promise<void> => {
          if (branchId === '') {
            this.refs.toast(TOMBSTONE_TOAST_TEXT);
            return Promise.resolve();
          }
          const input: CopyPrefixInput = {
            conversationId: this.refs.conversationId(),
            branchId: branchId,
            boundaryNodeId: nodeId,
            now: Date.now()
          };
          return copyConversationPrefix(input).then((_copied: CopiedConversation): void => {
            const tick: number = AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0;
            AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY, tick + 1);
            // 来源说明（M4：来源引用只在提示层承担，源 run/会话标识不落库）
            this.refs.toast('已复制为新会话，这条消息之前的完整历史都在副本里，可在会话列表打开它');
          });
        });
      })
      .catch((e: Object): void => {
        this.refs.toast('复制失败：' + (e as Error).message);
      })
      .finally((): void => {
        this.copying = false; // 成败两路复位（成对纪律——置位在本函数内，复位也必须在本函数内）
      });
  }

  // 消息菜单「编辑」（user 行）上行：进编辑态 → 开编辑面板（带出原文，剥附件标注 = 气泡
  // 显示面同口径）并记原附件保留集——**不预填输入条、不触发生成**；保存走 submitEditUser
  //（分叉落库 + 切分支 + 换源），取消 = 面板关闭（状态下次进入覆写，幂等无害）。★ 空锚呈报
  //（rejectEmptyAnchor）与「节点行不在库（伪锚 / 已删节点）明确拒绝」判据全保留——把 null
  // 当「父为根」会直插空 head 分支（旧会话从屏上消失）
  beginEditUser(msgId: string, nodeId: string): void {
    // 并发面收口：编辑面板是全屏模态，界面层不存在「同时开两条编辑」的路径；原输入条时代的
    // 互斥闸（isEditing 早退）已随预填链退役删除——它会把「保存/取消后残留的在编节点」
    // 误判为占用，永久阻塞后续编辑
    if (nodeId === '') {
      this.rejectEmptyAnchor();
      return;
    }
    this.entryGuard(nodeId, 'editUser').then((ok: boolean): void => {
      if (!ok) {
        return;
      }
      const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
      if (msg === null || msg.kind !== KIND_USER) {
        return;
      }
      queryNodeParentId(nodeId)
        .then((parent: string | null | undefined): Promise<void> => {
          if (parent === undefined) {
            // 节点行不存在 = 身份不可用（内存 id 伪锚 / 节点行已删）——拒绝并复用
            // identityGate 文案单源，不进编辑态（进 = 错锚建空 head 分支）
            this.refs.toast(identityGate({
              kind: KIND_USER, streaming: false, roundOpen: false, graphIdentity: false,
              session: SESSION_GRAPH, running: false
            }));
            return Promise.resolve();
          }
          this.editNodeId = nodeId;
          this.editParentId = parent;
          this.editKeepIds = [];
          // 引用快照随编辑保留（面板初值只带正文，引用独立存 quote_text——不在此快照，
          // 保存后气泡标注与后续请求前缀一并丢失）
          this.editQuoteText = msg.quoteText ?? '';
          // 另一角色在编态作废（两角色共用同一面板，submitEditMessage 按 editNodeId 优先
          // 分流——残留会把助手文本写成一个 user 提问变体）
          this.editAssistantNodeId = '';
          this.editAssistantParentId = null;
          // 附件保留候选按**节点身份**读（graph 会话归属在 attachment_refs.nodeId——
          // 视图消息 id 是内存 id，永不命中；修复 D1）
          return this.collectKeepIds(nodeId);
        })
        .then((): void => {
          if (this.editNodeId !== nodeId) {
            return; // 异步窗口内目标被改写/清空（身份拒绝路或已保存）——不开面板
          }
          this.refs.openEditAssistant(this.editDraftText(msg));
        })
        .catch((e: Object): void => {
          this.editNodeId = '';
          this.editQuoteText = '';
          this.refs.toast('进入编辑失败：' + (e as Error).message);
        });
    });
  }

  // 消息菜单「编辑」上行分流：两角色共用同一面板，提交按节点身份分流
  beginEditDispatch(msgId: string, nodeId: string): void {
    const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
    if (msg === null) {
      return;
    }
    if (msg.kind === KIND_USER) {
      this.beginEditUser(msgId, nodeId);
      return;
    }
    if (msg.kind === KIND_ASSISTANT) {
      this.beginEditAssistant(msgId, nodeId);
    }
  }

  // 消息菜单「编辑」（assistant 行）上行：过闸 → 记节点与父 → 开编辑面板（带出原文）。
  // 面板态自持，本编排只持落库所需的节点身份。★ 空正文早退在菜单判据（ChatMoreMenu
  // showEdit 的结构性区分不含正文判据——正文为空的 assistant 行〔纯工具轮宿主行〕点了也
  // 只落空编辑，提交时 content==='' 被命令层拒，此处不前置查库省一次读）
  private beginEditAssistant(msgId: string, nodeId: string): void {
    if (nodeId === '') {
      this.rejectEmptyAnchor();
      return;
    }
    this.entryGuard(nodeId, 'editAssistant').then((ok: boolean): void => {
      if (!ok) {
        return;
      }
      const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
      if (msg === null || msg.kind !== KIND_ASSISTANT) {
        return;
      }
      queryNodeParentId(nodeId)
        .then((parent: string | null | undefined): void => {
          if (parent === undefined) {
            // 节点行不存在 = 身份不可用（伪锚 / 已删）——拒绝，文案单源 identityGate
            //（同 beginEdit D3/D4 口径：不猜）
            this.refs.toast(identityGate({
              kind: KIND_ASSISTANT, streaming: false, roundOpen: false, graphIdentity: false,
              session: SESSION_GRAPH, running: false
            }));
            return;
          }
          this.editAssistantNodeId = nodeId;
          this.editAssistantParentId = parent;
          // 另一角色在编态作废（同 beginEditUser——不在此清除，残留的 user 在编节点会让
          // submitEditMessage 把本次保存走成 user 分支）
          this.editNodeId = '';
          this.editParentId = null;
          this.editKeepIds = [];
          this.editQuoteText = '';
          this.refs.openEditAssistant(msg.text);
        })
        .catch((e: Object): void => {
          this.refs.toast('进入编辑失败：' + (e as Error).message);
        });
    });
  }

  // 助手编辑提交（面板「保存」上行；返回 true = 落库与切换成功，页面据此关面板）：单事务
  // 分叉落库（fork 分支行 + 编辑版 assistant 节点 + head 指向编辑节点，见 GraphEditFork.
  // editAssistantFork）→ 切默认分支 → 视图换源重载（旧回复与其后续完整留在原分支，后续请求
  // 按活动分支路径取 = 编辑版生效；不与发送链交互——编辑只改历史，不起轮，拍板 2026-10-05）。
  // ★ 状态消费点 = 分叉与切换成功后（见成员注释）——任何失败路径状态原样留存，重试按原父
  // 节点干净重跑；下方空编辑会话守卫拦「无在编节点提交」（正常 UI 流不可达，防 future 调用
  // 点以 null 父走根节点豁免）
  submitEditAssistant(text: string): Promise<boolean> {
    if (this.refs.sending()) {
      this.refs.toast('请先停止当前回复');
      return Promise.resolve(false);
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return Promise.resolve(false);
    }
    if (text.trim() === '') {
      this.refs.toast('回复内容不能为空');
      return Promise.resolve(false);
    }
    if (this.editAssistantNodeId === '') {
      this.refs.toast('编辑会话已失效，请重新进入编辑');
      return Promise.resolve(false);
    }
    const convId: string = this.refs.conversationId();
    return this.refs.activeBranch()
      .then((sourceBranch: string): Promise<boolean> => {
        if (sourceBranch === '') {
          this.refs.toast(TOMBSTONE_TOAST_TEXT);
          return Promise.resolve(false);
        }
        return editAssistantForkProd(convId, sourceBranch, this.editAssistantParentId, text)
          .then((forked: EditAssistantForkResult): Promise<boolean> =>
            switchActiveBranch(convId, forked.branchId)
              .then((): Promise<boolean> => {
                this.editAssistantNodeId = '';
                this.editAssistantParentId = null;
                return this.refs.reloadBranchPath();
              }))
          .then((refreshed: boolean): boolean => {
            if (!refreshed) {
              // ★ D6：库态已分叉已切换而视图未换源——不谎报「已保存」，如实呈报
              this.refs.toast('已保存，但视图刷新失败，请重进会话');
              return true; // 保存语义已达成，面板照关
            }
            this.refs.toast('已保存修改，原回复留在原分支');
            return true;
          });
      })
      .catch((e: Object): boolean => {
        this.refs.toast('保存失败：' + (e as Error).message);
        return false;
      });
  }

  // 编辑预填文本（气泡显示面同口径：有附件简报则剥尾部标注，无简报原样——见 ChatMessageItem
  // .displayBodyText；只改显示与预填，不动库内文本）
  // 编辑消息提交（面板「保存」上行；两角色分流——按在编节点身份判断 user/assistant，页面只接
  // 这一口。返回 true = 落库与切换成功，页面据此关面板）
  submitEditMessage(text: string): Promise<boolean> {
    if (this.editNodeId !== '') {
      return this.submitEditUser(text);
    }
    return this.submitEditAssistant(text);
  }

  // 提问编辑提交（**只在编辑，不重发**——决明拍板参照 rik）：单事务分叉落库（fork 分支行 +
  // 编辑版 user 节点 + head 指向编辑节点，见 GraphEditFork.editUserFork）→ 切默认分支 →
  // 视图换源重载（原提问与其后续完整留在原分支）→ 原附件按引用回挂到新节点。**不起轮**：
  // 编辑只改历史，需要回答时用户再发消息；后续任何请求按活动分支路径取上下文 = 编辑版生效。
  // ★ 原引用快照随编辑版节点写入（quote_text），气泡引用标注与后续请求前缀不断链。状态
  // 消费点 = 分叉与切换成功后（同助手编辑口径）——失败路径状态原样留存，重试按原父节点
  // 干净重跑
  submitEditUser(text: string): Promise<boolean> {
    if (this.editNodeId === '') {
      this.refs.toast('编辑会话已失效，请重新进入编辑');
      return Promise.resolve(false);
    }
    if (this.refs.sending()) {
      this.refs.toast('请先停止当前回复');
      return Promise.resolve(false);
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return Promise.resolve(false);
    }
    if (text.trim() === '') {
      this.refs.toast('消息内容不能为空');
      return Promise.resolve(false);
    }
    const convId: string = this.refs.conversationId();
    const keepIds: string[] = this.editKeepIds;
    const parentNodeId: string | null = this.editParentId;
    const quoteText: string = this.editQuoteText;
    return this.refs.activeBranch()
      .then((sourceBranch: string): Promise<boolean> => {
        if (sourceBranch === '') {
          this.refs.toast(TOMBSTONE_TOAST_TEXT);
          return Promise.resolve(false);
        }
        return editUserForkProd(convId, sourceBranch, parentNodeId, text, quoteText)
          .then((forked: EditAssistantForkResult): Promise<boolean> =>
            switchActiveBranch(convId, forked.branchId)
              .then((): Promise<boolean> => {
                this.editNodeId = '';
                this.editParentId = null;
                this.editKeepIds = [];
                this.editQuoteText = '';
                if (keepIds.length === 0) {
                  return this.refs.reloadBranchPath();
                }
                // 原附件引用回挂新节点（新节点 id 由分叉命令直接返回，无需待回挂作业与末条
                // user 行猜测）。★ 必须 await 回挂完成再重载——换源链内 attachBriefsFor
                // 随即按节点 id 读 attachment_refs，先重载会漏掉改后提问的附件泡
                return insertAttachmentRefsForIds(convId, keepIds, forked.nodeId)
                  .catch((e: Object): void => {
                    this.refs.toast('原附件引用保存失败：' + (e as Error).message);
                  })
                  .then((): Promise<boolean> => this.refs.reloadBranchPath());
              }))
          .then((refreshed: boolean): boolean => {
            if (!refreshed) {
              this.refs.toast('已保存，但视图刷新失败，请重进会话');
              return true; // 保存语义已达成，面板照关
            }
            this.refs.toast('已保存修改，原提问留在原分支');
            return true;
          });
      })
      .catch((e: Object): boolean => {
        this.refs.toast('保存失败：' + (e as Error).message);
        return false;
      });
  }



  private editDraftText(msg: ChatMessage): string {
    const briefs: AttachmentBrief[] | undefined = msg.attachBriefs;
    if (briefs === undefined || briefs.length === 0) {
      return msg.text;
    }
    const names: string[] = briefs.map((b: AttachmentBrief): string => b.name);
    return hideAttachAnnotate(msg.text, names);
  }

  // 原附件 id 收集（编辑保留候选：两源联合读口按**节点身份**归并——legacy 归属与 graph refs
  // 归属同口，只读不写；失败按「无附件」降级不阻断编辑）。★ 实参必须是节点身份——graph
  // 会话附件归属在 refs.nodeId，传视图消息 id（内存 id）永不命中（修复 D1）
  private collectKeepIds(nodeId: string): Promise<void> {
    return queryAttachmentsForMessages([nodeId])
      .then((rows): void => {
        const ids: string[] = [];
        for (const row of rows) {
          ids.push(row.id);
        }
        this.editKeepIds = ids;
      })
      .catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, '原附件读取失败，编辑按不带原附件进行：%{public}s',
          (e as Error).message);
        this.editKeepIds = [];
      });
  }

  // ── 中途整轮重试入口（S3；起轮在 ChatRetryCtrl.retryAt）──

  // 重试前判据（页面在调 retryAt 前取：理由文案单源；起轮侧另有仓储锚校验兜底）
  retryAllow(msgId: string, nodeId: string): Promise<BranchAllow> {
    const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
    return this.sessionNow().then((session: string): BranchAllow => {
      const facts: BranchTargetFacts = msg !== null ? this.factsOf(msg, session)
        : this.factsOfNode(nodeId, session);
      return canRetryAt(facts);
    });
  }

  // 视图里找不到目标行时的判据事实（保守：只按会话态与占用判，身份由起轮侧仓储校验兜底）
  private factsOfNode(nodeId: string, session: string): BranchTargetFacts {
    return {
      kind: nodeId !== '' ? KIND_ASSISTANT : '', streaming: false, roundOpen: false,
      graphIdentity: nodeId !== '', session: session, running: this.refs.sending()
    };
  }

  // ── 消息删除入口（菜单「删除消息」）──

  // 删除前判据（菜单层在弹确认框前取：理由文案单源在 ChatBranchPolicy.canDeleteAt——
  // 生成中 runningGate / 流式与未收尾 settledGate / 墓碑 sessionGate / 空锚 identityGate
  // 四闸零新文案；retryAllow 同构镜像）
  deleteAllow(msgId: string, nodeId: string): Promise<BranchAllow> {
    const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
    return this.sessionNow().then((session: string): BranchAllow => {
      const facts: BranchTargetFacts = msg !== null ? this.factsOf(msg, session)
        : this.factsOfNode(nodeId, session);
      return canDeleteAt(facts);
    });
  }

  // 删除执行（确认框「删除」键上行；守卫链照 submitEditUser + 附件/换源模板照
  // runDeleteBranch）：空锚呈报 → sending 复核闸（确认弹窗开启与确认之间生成可启动）→
  // dbReady 闸 → 非图态守卫（墓碑句）→ 节点级剪枝命令（目标节点及其全部后代闭包，跨一切
  // 分支）→ commit 后附件文件清理（best-effort，回滚不得已删文件红线——删除恒在 commit
  // 之后）→ **无条件 reloadBranchPath 换源重载**（★ 裁定 E：节点命令不动 activeBranchId，
  // 条件换源模板在此恒假——照抄会使被删内容留屏 + 复用窗残留 + 降级快照泄漏，故钉死必
  // 换源）。刷新失败不吞「已删除」事实。护栏 = 直用换源重载链，删除侧零滚动/锚定代码——
  // 红线六项护栏在链内（ChatPageLoad 同链）
  deleteMessage(nodeId: string): Promise<boolean> {
    if (nodeId === '') {
      this.rejectEmptyAnchor();
      return Promise.resolve(false);
    }
    if (this.refs.sending()) {
      this.refs.toast('请先停止当前回复');
      return Promise.resolve(false);
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return Promise.resolve(false);
    }
    const convId: string = this.refs.conversationId();
    return this.refs.activeBranch()
      .then((branchId: string): Promise<boolean> => {
        if (branchId === '') {
          this.refs.toast(TOMBSTONE_TOAST_TEXT);
          return Promise.resolve(false);
        }
        return deleteNodeLineageProd(convId, nodeId)
          .then((result: NodeLineageDeleteResult): Promise<boolean> => {
            removeAttachmentFiles(result.invalidatedLocalPaths);
            return this.refs.reloadBranchPath();
          })
          .then((refreshed: boolean): boolean => {
            this.refs.toast(refreshed ? '已删除' : '已删除，但视图刷新失败，请重进会话');
            return true;
          });
      })
      .catch((e: Object): boolean => {
        this.refs.toast('删除失败：' + (e as Error).message);
        return false;
      });
  }

  // 入口守卫（fork/edit 共用）：占用 + 会话态 + 图身份 + 收尾过闸；不过闸呈报原因。
  // mode 三态（fork / editUser / editAssistant）各指到对应判据——判据单源仍在
  // ChatBranchPolicy，本处只做分派
  private entryGuard(nodeId: string, mode: string): Promise<boolean> {
    if (this.refs.sending()) {
      this.refs.toast('请先停止当前回复');
      return Promise.resolve(false);
    }
    const msg: ChatMessage | null = this.findByNode(nodeId);
    return this.sessionNow().then((session: string): boolean => {
      const facts: BranchTargetFacts = msg !== null ? this.factsOf(msg, session)
        : this.factsOfNode(nodeId, session);
      const gate: BranchAllow = mode === 'fork' ? canForkAt(facts)
        : mode === 'editAssistant' ? canEditAssistant(facts) : canEditUser(facts);
      if (!gate.allowed) {
        this.refs.toast(gate.reason);
        return false;
      }
      return true;
    });
  }

  // 按节点身份反查视图消息（fork/edit 来自行的 nodeId，回放窗口下 id 即节点 id——两法同查）
  private findByNode(nodeId: string): ChatMessage | null {
    const all: ChatMessage[] = this.refs.dataSource().allMessages();
    for (const m of all) {
      if (m.nodeId === nodeId || m.id === nodeId) {
        return m;
      }
    }
    return null;
  }
}
