// 上下文压缩页面接线域（自 ChatPage 域级最小拆出）。域定义：压缩面板与页面数据流之间的
// 接线——开面板 / 采用收口 / 删除摘要收口 / **关闭确认流程**（含中断在途生成）；不持 UI 壳、
// 不发请求、不落库（分居 CompressPreviewSheet / CompressGen / CompressDb）。不并入三件的
// 理由（反碎片下限②）：CompressGen 域约束「不持页面/组件引用」（坑50 环求值红线），本件恰
// 相反要读页面消息流、写 sheetKind、经 UIContext 弹确认；CompressPreviewSheet 是 UI 组件件，
// 编排塞入会混装。形制照 ChatPageLoadCtrl 等页面编排域外迁件（宿主 implements Host 回接）。
// ★ 关闭确认单源（决明 2026-09-23 报障「压缩中退出无提示 · 提示不符 · 不能中断」）：
// 标题栏关闭键、面板「放弃」键、宿主手势与系统返回三路都走 requestClose()，按「是否有在途
// 生成」「是否有未采用草稿」两判据分三态（pickCompressCloseAction 纯函数）：在途 → 确认停止
//（cancelCompressDraft 真中断）再关；有草稿 → 确认放弃再关（草稿只存面板 @State，落库唯一
// 路径是「采用」）；其余直接关。手势路带 action 传入 requestClose(action)，三态确认通过后
// 才 closeSheet(action) 放行；自绘键不带 action 直写状态位；确认未过不放行（官方契约见
// KimiSheetCommon）。确认弹窗形制单源 = KimiSheetCommon.confirmSheetClose，本件只供两态文案。
// 竞品依据（调研-上下文压缩总览 §3.4）：八家实现四家可中断，本件取可中断阵营形态。
import { UIContext } from '@kit.ArkUI';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { cancelCompressDraft, isCompressInflight } from '../../common/CompressGen';
import { conversationGraphBranch } from '../../common/chat/ChatContextSource';
import { adoptGraphClear, isClearAtHead, readLatestClearRow, revokeGraphClear } from '../../common/chat/ContextClear';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { MessageRow } from '../../common/store/ChatDb';
import { confirmSheetClose } from './KimiSheetCommon';

// 宿主回接接口（ChatPage 实现；成员一律属性式函数签名——方法签名形态下宿主传对象字面量
// 触发 arkts-no-untyped-obj-literals 编译错，已实测）
export interface ChatCompressHost {
  conversationId: () => string;
  allMessages: () => ChatMessage[];
  removeMessages: (ids: string[]) => void;
  pushMessage: (message: ChatMessage) => void;
  // 开启 = 内容形态 + 可见性同写（openSheet）；关闭 = 放行单源（closeSheet，action 在场
  // 走官方 dismiss()、缺省直写可见性；程序化关闭如「采用」不带 action）
  openSheet: (kind: string) => void;
  closeSheet: (action?: DismissSheetAction) => void;
  refreshUsage: () => void;
  ui: () => UIContext;
}

// ── 关闭动作三态（零依赖纯函数——判断与文案选择分派的单源，断言脚本剥 import 后直跑）──
export const COMPRESS_CLOSE_STOP: string = 'stop'; // 生成在途：确认是否停止并中断
export const COMPRESS_CLOSE_DISCARD: string = 'discard'; // 预览有草稿：确认是否放弃
export const COMPRESS_CLOSE_DIRECT: string = 'direct'; // 失败态 / 空草稿：直接关

export function pickCompressCloseAction(generating: boolean, hasDraft: boolean): string {
  if (generating) {
    return COMPRESS_CLOSE_STOP;
  }
  if (hasDraft) {
    return COMPRESS_CLOSE_DISCARD;
  }
  return COMPRESS_CLOSE_DIRECT;
}

// ── 清空分界锚 ──

// 分界锚（活跃路径最后一条可证消息：nodeId 供图侧路径核验，seq 作覆盖边界）
export interface ClearAnchor {
  nodeId: string;
  seq: number;
}

// 分界锚选取（纯函数，直跑断言面）：从屏幕流末尾向前找最后一条带库序号的可证消息——
// 无序号行（实时流内行 / NULL 行 / 占位行）与边界行（summary | clear）都跳过：前者使请求侧
// 裁段判据（rowSeq ≤ boundary）与图侧路径核验无从成立，后者是会话级状态行，取它作锚即
//「分界点 = 上一条分界」，重复清空守卫与面板置灰双双失准（无新消息时可反复插边界节点）。
// 找不到 = null（面板据此置灰）。nodeId 缺省回退 m.id（回放链消息 id 与库节点 id 同源）。
export function pickClearAnchor(messages: ChatMessage[]): ClearAnchor | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m: ChatMessage = messages[i];
    if (m.rowSeq === undefined) {
      continue;
    }
    if (m.kind === 'summary' || m.kind === 'clear') {
      continue;
    }
    const nodeId: string = m.nodeId !== undefined && m.nodeId !== '' ? m.nodeId : m.id;
    if (nodeId === '') {
      continue;
    }
    const anchor: ClearAnchor = { nodeId: nodeId, seq: m.rowSeq };
    return anchor;
  }
  return null;
}

export class ChatCompressCtrl {
  private host: ChatCompressHost;
  // 面板态镜像（onDraftState 上行；手势关闭时面板不参与决策，读本镜像选确认文案）。
  // 普通成员：不驱动 UI，无需 @State
  private hasDraft: boolean = false;
  // 采用在途镜像（onAdoptState 上行）：采用落库的百 ms 窗口内关闭面板会让在途链照样落库
  //（「放弃后不会保存任何内容」承诺被破），requestClose 入口据此拦关（isCompressInflight
  // 只管生成在途，管不到这里）
  private adopting: boolean = false;

  constructor(host: ChatCompressHost) {
    this.host = host;
  }

  // 面板态上行（面板 aboutToAppear / 预览态建立 / 草稿编辑 / aboutToDisappear 四处调用）
  setDraftState(hasDraft: boolean): void {
    this.hasDraft = hasDraft;
  }

  // 采用在途上行（面板 adopt() 置位与 finally 复位同拍两调）
  setAdoptState(adopting: boolean): void {
    this.adopting = adopting;
  }

  // 开面板（用量面板压缩卡入口；面板打开即自动生成）
  open(): void {
    this.host.openSheet('compress');
  }

  // 采用收口（落库成功后上行）：流内追加持久轻提示（kind='summary'，重进会话由回放重建）
  // → 关面板 → 刷新用量。旧摘要行已由落库事务删除，流内旧提示行一并移除（库里只留一条
  // 生效摘要，流里不出现多条失效提示）
  adopt(rowId: string, summaryText: string, coversToSeq: number): void {
    const stale: string[] = [];
    for (const m of this.host.allMessages()) {
      if (m.kind === 'summary' && m.id !== rowId) {
        stale.push(m.id);
      }
    }
    if (stale.length > 0) {
      this.host.removeMessages(stale);
    }
    const hint: ChatMessage = newChatMessage(rowId, 'summary', summaryText);
    hint.coversToSeq = coversToSeq;
    this.host.pushMessage(hint);
    this.hasDraft = false;
    this.host.closeSheet();
    this.host.ui().getPromptAction().showToast({ message: '已采用压缩摘要' });
    this.host.refreshUsage();
  }

  // 删除摘要收口（删行成功后上行）：移除流内提示行 → 刷新用量。参数 = 图侧软删返回的
  // 路径上全部失效摘要 id（防「库里没生效、流里还挂着」口径分叉）
  summaryDeleted(summaryIds: string[]): void {
    if (summaryIds.length > 0) {
      this.host.removeMessages(summaryIds);
    }
    this.host.refreshUsage();
  }

  // ── 上下文清空 ──

  // 清空生效链：分界锚 → 落边界行（adoptGraphClear：零模型调用、消息一条不删）→ 流内
  // 分隔条维护 → 刷新用量。空会话 / 无锚各给一句 toast（文案规约：分句句号）。重复清空 =
  // 分界点没前移时不动库只呈报。返回 true = 确有一次生效写入（面板据此重载状态行）
  async clearContext(): Promise<boolean> {
    const convId: string = this.host.conversationId();
    if (convId === '') {
      this.host.ui().getPromptAction().showToast({ message: '当前会话不落库，无法清空上下文' });
      return false;
    }
    const anchor: ClearAnchor | null = pickClearAnchor(this.host.allMessages());
    if (anchor === null) {
      this.host.ui().getPromptAction().showToast({ message: '暂无可清空的内容' });
      return false;
    }
    try {
      // 重复清空守卫：已有边界且覆盖上界不早于本次分界点 ⇒ 分界没前移（期间无新消息），
      // 不再插第二个边界行（幂等）
      const existing: MessageRow | null = await readLatestClearRow(convId);
      if (existing !== null && (existing.coversToSeq ?? 0) >= anchor.seq) {
        this.host.ui().getPromptAction().showToast({ message: '之后还没有新消息，无需重复清空' });
        return false;
      }
      const branchId: string = await conversationGraphBranch(convId);
      if (branchId === '') {
        this.host.ui().getPromptAction().showToast({ message: TOMBSTONE_TOAST_TEXT });
        return false;
      }
      const clearId: string = await adoptGraphClear(convId, branchId, anchor.seq, anchor.nodeId);
      // 流内维护：旧分隔条移除（生效边界只一条，旧行库里留档、回放不投影），再推新分隔条
      const stale: string[] = [];
      for (const m of this.host.allMessages()) {
        if (m.kind === 'clear' && m.id !== clearId) {
          stale.push(m.id);
        }
      }
      if (stale.length > 0) {
        this.host.removeMessages(stale);
      }
      const hint: ChatMessage = newChatMessage(clearId, 'clear', '');
      hint.coversToSeq = anchor.seq;
      this.host.pushMessage(hint);
      this.host.ui().getPromptAction().showToast({ message: '已清空上下文' });
      this.host.refreshUsage();
      return true;
    } catch (e) {
      this.host.ui().getPromptAction().showToast({ message: '清空失败：' + (e as Error).message });
      return false;
    }
  }

  // 撤销清空：软删该边界行绑定 → 回到清空前边界状态（更早边界若仍生效按「最后一条胜出」
  // 自然重新生效）；移除流内分隔条。撤销门槛：清空后已发新内容（head 已前移）不可撤——
  // 面板键已按同判据隐藏，此守卫兜面板停留旧态的误调（revokeGraphClear 内还有最后一道）。
  // 返回 true = 确有一次撤销（面板据此重载状态行）
  async revokeClear(): Promise<boolean> {
    const convId: string = this.host.conversationId();
    if (convId === '') {
      return false;
    }
    try {
      const row: MessageRow | null = await readLatestClearRow(convId);
      if (row === null) {
        this.host.ui().getPromptAction().showToast({ message: '当前没有清空记录' });
        return false;
      }
      if (!(await isClearAtHead(convId, row.id))) {
        this.host.ui().getPromptAction().showToast({ message: '清空后已发送新消息，无法撤销' });
        return false;
      }
      const removed: string[] = await revokeGraphClear(convId, row.id);
      if (removed.length === 0) {
        // 幂等空集（路径已变无可撤）：如实呈报零动作——不动流内分隔条（没撤成功就移行会把
        // 还在生效的边界提示从屏上抹掉）
        this.host.ui().getPromptAction().showToast({ message: '当前没有可撤销的清空' });
        return false;
      }
      this.host.removeMessages(removed);
      this.host.ui().getPromptAction().showToast({ message: '已撤销清空' });
      this.host.refreshUsage();
      return true;
    } catch (e) {
      this.host.ui().getPromptAction().showToast({ message: '撤销失败：' + (e as Error).message });
      return false;
    }
  }

  // 关闭请求（三路单源，见文件头）：直接关态不经弹窗；其余两态交 confirmClose。采用在途
  // 先拦（理由见 adopting 镜像注释）；窗口百 ms 级 toast 呈报即可，采用收尾后自然恢复可关
  requestClose(action?: DismissSheetAction): void {
    if (this.adopting) {
      this.host.ui().getPromptAction().showToast({ message: '正在保存摘要，请稍候' });
      return;
    }
    const next: string = pickCompressCloseAction(
      isCompressInflight(this.host.conversationId()), this.hasDraft);
    if (next === COMPRESS_CLOSE_DIRECT) {
      this.hasDraft = false;
      this.host.closeSheet(action);
      return;
    }
    this.confirmClose(next, action);
  }

  private async confirmClose(closeAction: string, action?: DismissSheetAction): Promise<void> {
    const stopping: boolean = closeAction === COMPRESS_CLOSE_STOP;
    // 形制单源（键序 [取消, 确认] / 键色 / 取消与异常一律不放行）见 KimiSheetCommon.confirmSheetClose
    const approved: boolean = await confirmSheetClose(this.host.ui(), {
      title: stopping ? '停止本次压缩？' : '放弃这次生成的摘要？',
      message: stopping ? '停止后不会保存任何内容，之后可以重新压缩' :
        '放弃后不会保存任何内容，会话保持原样',
      cancelLabel: stopping ? '继续压缩' : '继续编辑',
      confirmLabel: stopping ? '停止' : '放弃'
    });
    if (!approved) {
      return;
    }
    if (stopping) {
      cancelCompressDraft(this.host.conversationId());
    }
    this.hasDraft = false;
    this.host.closeSheet(action);
  }
}
