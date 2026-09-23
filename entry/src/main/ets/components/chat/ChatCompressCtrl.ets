// 上下文压缩页面接线域（2026-09-23 上下文压缩修复笔自 ChatPage 拆出——该页已连续三笔贴
// 1200 硬线，技术债务清单明写「下次实质改动前先拆其一再动手」，本笔按「域级最小拆分」
// 只拆本次改动所属域）。域定义一句话：压缩面板与页面数据流之间的接线——开面板 / 采用
// 收口 / 删除摘要收口 / **关闭确认流程**（含中断在途生成）；不持 UI 壳、不发请求、不落库
//（那三件分居 CompressPreviewSheet / CompressGen / CompressDb）。
//
// ★ 为什么新开一件而不并入三件（反碎片下限第②问）：CompressGen 头注释立了「不持页面/
//   组件引用、不触 UI」的域约束（坑50 环求值红线），本件恰恰相反——要读页面消息流、写
//   sheetKind、经 UIContext 弹确认；CompressPreviewSheet 是 UI 组件件（struct），编排类
//   塞进去会造成「组件件 + 编排件」混装。形制照 ChatPageLoadCtrl / ChatRetryCtrl /
//   ChatAutoRetryCtrl（页面编排域外迁件，宿主 implements 本件 Host 接口回接）。
//
// ★ 关闭确认单源（决明 2026-09-23 报障「压缩中退出无提示 · 提示不符 · 不能中断」）：
//   面板标题栏关闭键、面板底部「放弃」键、宿主手势与系统返回（下拉/遮罩/侧滑/三键 back
//   ——bindSheet onWillDismiss 承接）三路都走 requestClose()，按「是否有在途生成」与
//   「是否有未采用草稿」两判据分三态（pickCompressCloseAction，纯函数）：
//     · 在途 → 问「停止本次压缩？」→ 确认即 cancelCompressDraft（destroy 真中断）再关；
//     · 预览有草稿 → 问「放弃这次生成的摘要？」→ 确认即关（零副作用——草稿只存面板 @State，
//       落库唯一路径是「采用」）；
//     · 其余（失败态 / 空草稿）→ 直接关。
//   ★ 2026-09-23 半模态关闭确认笔：确认弹窗的形制（键序 / 键色 / 取消语义 / 异常不放行）升格为
//   全半模态域的单源 = `KimiSheetCommon.confirmSheetClose`，本件只供两态文案（行为逐字不变）；
//   同笔新增的获取模型与提示词编辑两站点直接消费该函数。
//   竞品依据（docs/调研-上下文压缩-20260922/00-总览与对比矩阵.md §3.4）：八家实现里四家
//   可中断（RikkaHub 压缩中确认键变取消、LobeChat abort 后回滚、Kimi Code cancel、ZCode
//   abort 收敛为「上下文压缩已中断」），Kelivo 两家明确不可关、ChatBox 与 Cherry 未找到
//   取消入口——本件取可中断阵营的形态。
import { UIContext } from '@kit.ArkUI';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { cancelCompressDraft, isCompressInflight } from '../../common/CompressGen';
import { confirmSheetClose } from './KimiSheetCommon';

// 宿主回接接口（ChatPage 实现；★ 成员一律**属性式函数签名**——照 ChatSendRefs /
// ChatPageLoadRefs 惯例；方法签名形态下宿主传对象字面量会被 ArkTS 判
// arkts-no-untyped-obj-literals 编译错，已实测）
export interface ChatCompressHost {
  conversationId: () => string;
  allMessages: () => ChatMessage[];
  removeMessages: (ids: string[]) => void;
  pushMessage: (message: ChatMessage) => void;
  setSheetKind: (kind: string) => void;
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

export class ChatCompressCtrl {
  private host: ChatCompressHost;
  // 面板态镜像（面板 phase 变化与草稿编辑经 onDraftState 上行；面板销毁上行 false）——
  // 手势关闭时面板自身不参与决策，读本镜像选确认文案。普通成员：不驱动 UI（判断用），
  // 无需 @State
  private hasDraft: boolean = false;

  constructor(host: ChatCompressHost) {
    this.host = host;
  }

  // 面板态上行（面板 aboutToAppear / 预览态建立 / 草稿编辑 / aboutToDisappear 四处调用）
  setDraftState(hasDraft: boolean): void {
    this.hasDraft = hasDraft;
  }

  // 开面板（用量面板压缩卡入口；面板打开即自动生成）
  open(): void {
    this.host.setSheetKind('compress');
  }

  // 采用收口（面板「采用」落库成功后上行）：流内追加一行持久轻提示（kind='summary'——
  // ChatMessageItem 摘要分支渲染；重进会话由回放重建）→ 关面板 → 刷新用量（环数值下降）。
  // 旧摘要行已由落库事务删除，流内若有旧提示行一并移除（重压缩场景——库里只留一条生效
  // 摘要，流里不出现多条失效提示）
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
    this.host.setSheetKind('none');
    this.host.ui().getPromptAction().showToast({ message: '已采用压缩摘要' });
    this.host.refreshUsage();
  }

  // 删除摘要收口（用量面板压缩卡「删除摘要」删行成功后上行）：移除流内提示行 → 刷新用量
  //（下一次请求回到全文，占用回升）
  summaryDeleted(summaryId: string): void {
    this.host.removeMessages([summaryId]);
    this.host.refreshUsage();
  }

  // 关闭请求（三路单源，见文件头）：直接关态不经弹窗；其余两态交 confirmClose
  requestClose(): void {
    const action: string = pickCompressCloseAction(
      isCompressInflight(this.host.conversationId()), this.hasDraft);
    if (action === COMPRESS_CLOSE_DIRECT) {
      this.hasDraft = false;
      this.host.setSheetKind('none');
      return;
    }
    this.confirmClose(action);
  }

  private async confirmClose(action: string): Promise<void> {
    const stopping: boolean = action === COMPRESS_CLOSE_STOP;
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
    this.host.setSheetKind('none');
  }
}
