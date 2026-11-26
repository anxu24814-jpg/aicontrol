// 会话草稿内存仓库：conversationId（或新会话单槽 '__new__'）→ DraftEntry 的模块级缓存
//（形制照 AttachmentThumbStore.ets：模块级 Map + 导出函数）。域定义一句话 = 会话草稿的
// 进程内存存取（保存/读取/清除/淘汰）与列表合成消费；条目内容 = 文本 + 附件 + 待发引用
// 三者同寿命（引用不单独开槽，随条目保存/恢复/淘汰；纯引用〔文本空〕不视为空快照）。
// · 为什么独立单例、不挂 ChatSessionRuntime：运行时是「生成运行态账本」空闲 5 秒回收
//  （IDLE_RECLAIM_MS）会把挂其上的草稿吃掉；且两域定义混不出一句话（反碎片下限①）。
//   放 components/chat = 级联删附件（cleanupAttachments）与缩略图仓同目录同层 import，
//   消费方全在 components 层。
// · 寿命匹配红线：Map 只持元数据与字符串（attachments 为纯元数据引用，不复制文件本体）、
//   零 @State/AppStorage——纯进程内存态，杀后台随进程死即「杀后台清草稿」本体；附件文件
//   残留由下次冷启动 reconcileAttachments 孤儿删收口。
// · 两档删除 API（R4-7 致命伤吸收）：发送成功路径附件文件留盘转消息资产（被
//   message_attachments 库行引用），级联删会物理损坏已发消息——故 removeDraft（仅删条目）
//   与 removeDraftWithFiles（删条目 + 级联删附件）分档。
// · 双淘汰（条数 LRU 20 + 附件总体积 1GB，一律从 updatedAt 最旧者淘汰——淘汰件未发送、
//   文件确为孤儿，走 WithFiles 档）；淘汰静默不 toast，仅 hilog 留痕。
// · 归属校验：'__new__' 单槽无会话身份，空快照转清与跨助手覆盖前按 historyFilterIds
//  （与列表过滤同口径单源）判归属，防跨助手误销毁/误恢复他助手草稿；会话键条目身份自证
//   不做归属门。
// · 删助手级联（removeDraftsOfAssistant）：deleteAssistantCascade 事务删会话行后条目失去
//   可达载体，UI 调用点（AssistantPage）显式级联——与单删/批删/清空会话三入口同族。
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PendingAttachment } from '../../common/providers/AiTypes';
import { historyFilterIds } from '../../common/store/AssistantDb';
import { cleanupAttachments } from './AttachmentPickCtrl';

// 新会话草稿单槽固定 key（「跟人不跟 id」：无 DB 行的新会话页共用一个槽，连续开新会话
// 不堆积孤儿草稿；双下划线形态与 nextMessageId 的 'conv-<时间戳>-<seq>' 永不同名）
export const NEW_DRAFT_KEY: string = '__new__';
// 条数上限（LRU，方案 §7.1）
const DRAFT_MAX_ENTRIES: number = 20;
// 附件总体积上限（字节，方案 §7.1 体积淘汰——size 取元数据累加，零 fs 扫描）
const DRAFT_ATTACH_TOTAL_LIMIT: number = 1024 * 1024 * 1024;

// 草稿条目（纯元数据：文本原样 + 附件引用数组 + 保存时刻 + 归属助手 + 待发引用全文；
// quoteText 与 text 同寿命——保存/恢复/空快照判据/淘汰一体处理，不单独开槽位）
export interface DraftEntry {
  text: string;
  attachments: PendingAttachment[];
  updatedAt: number;
  assistantId: string;
  quoteText: string;
}

const drafts: Map<string, DraftEntry> = new Map();

// 读快照（恢复链与列表合成消费；undefined = 无草稿）
export function getDraft(key: string): DraftEntry | undefined {
  return drafts.get(key);
}

// 徽标/清删判据（条目在场即「有草稿」——条目只在内容非空时落）
export function hasDraft(key: string): boolean {
  return drafts.has(key);
}

// 仅删 Map 条目，不碰附件文件与缩略图（★两档之一——发送成功路径专用：附件已被库行接管，
// 级联删损坏已发消息且 reconcile 不自愈；空快照转清同档）。条目不存在零动作
export function removeDraft(key: string): void {
  drafts.delete(key);
}

// 删条目 + 级联删附件（★两档之二——缩略图 release + 沙箱副本删除成对，经
// cleanupAttachments 单源）。条目不存在零动作
export function removeDraftWithFiles(key: string): void {
  const entry: DraftEntry | undefined = drafts.get(key);
  if (entry === undefined) {
    return;
  }
  drafts.delete(key);
  cleanupAttachments(entry.attachments);
}

// 批删（遍历走 WithFiles 档——会话删除级联用，单删传单元素数组）
export function removeDraftsWithFiles(keys: string[]): void {
  for (const key of keys) {
    removeDraftWithFiles(key);
  }
}

// 清空全部（QuickCleanPage 清空会话成功回调触发；逐条目 WithFiles 防孤儿文件）
export function purgeAllDrafts(): void {
  const keys: string[] = [];
  for (const key of drafts.keys()) {
    keys.push(key);
  }
  for (const key of keys) {
    removeDraftWithFiles(key);
  }
}

// 删助手级联（原拍板不做后翻案——事务删会话行后条目与附件残留 = 进程内不可达；归属条目
//〔会话键与其 '__new__' 槽〕一律 WithFiles 档。调用点 = AssistantPage 删助手成功支——
// 数据层动作不豁免销毁守卫）
export function removeDraftsOfAssistant(assistantId: string): void {
  const keys: string[] = [];
  for (const key of drafts.keys()) {
    const e: DraftEntry | undefined = drafts.get(key);
    if (e !== undefined && e.assistantId === assistantId) {
      keys.push(key);
    }
  }
  for (const key of keys) {
    removeDraftWithFiles(key);
  }
}

// 条目附件体积（字节，元数据口径）
function attachBytes(entry: DraftEntry): number {
  let total: number = 0;
  for (const att of entry.attachments) {
    total += att.size;
  }
  return total;
}

// 双淘汰（条数 + 附件总体积），从 updatedAt 最旧者淘汰（方案 §7.1 定稿实现）
function enforceDraftBounds(): void {
  const ordered: string[] = [];
  for (const key of drafts.keys()) {
    ordered.push(key);
  }
  ordered.sort((a: string, b: string): number =>
    (drafts.get(a)?.updatedAt ?? 0) - (drafts.get(b)?.updatedAt ?? 0));
  let total: number = 0;
  for (const key of drafts.keys()) {
    const e: DraftEntry | undefined = drafts.get(key);
    if (e !== undefined) {
      total += attachBytes(e);
    }
  }
  for (const key of ordered) {
    if (drafts.size <= DRAFT_MAX_ENTRIES && total <= DRAFT_ATTACH_TOTAL_LIMIT) {
      break;
    }
    const entry: DraftEntry | undefined = drafts.get(key);
    if (entry === undefined) {
      continue;
    }
    total -= attachBytes(entry);
    hilog.info(0xD5A0, 'ChatDraftStore', '草稿双淘汰（条数/体积上限）key=%{public}s', key);
    removeDraftWithFiles(key);
  }
}

// 保存单源入口（leave 保存与新会话动作点保存双触发共用，幂等）：
// · 空快照（文本/附件/引用全空）→ 转清：仅当既有条目归属命中当前助手域才清（'__new__' 槽
//   防跨助手误销毁；无条目零动作）；
// · 跨助手覆盖守卫（仅 '__new__' 槽）：覆盖他助手旧槽时先级联清旧条目（含附件文件，防
//   孤儿），再落新条目；
// · 落条目后 enforceDraftBounds（条数 + 体积双淘汰）；quoteText 缺省 '' = 无引用（旧调用
//   方不传参行为逐字一致），纯引用（文本空、无附件、引用在）**不转清**，条目照落（列表
//   徽标与恢复链因此把引用算作草稿内容）
export function saveDraftSnapshot(key: string, text: string, attachments: PendingAttachment[],
  assistantId: string, quoteText: string = ''): void {
  if (text.trim() === '' && attachments.length === 0 && quoteText.trim() === '') {
    const existing: DraftEntry | undefined = drafts.get(key);
    if (existing === undefined) {
      return;
    }
    if (key === NEW_DRAFT_KEY
      && !historyFilterIds(assistantId).includes(existing.assistantId)) {
      return; // 他助手的 '__new__' 草稿：保留不清（切回该助手仍可用）
    }
    removeDraft(key);
    return;
  }
  if (key === NEW_DRAFT_KEY) {
    const existing: DraftEntry | undefined = drafts.get(key);
    if (existing !== undefined
      && !historyFilterIds(assistantId).includes(existing.assistantId)) {
      removeDraftWithFiles(key);
    }
  }
  const entry: DraftEntry = {
    text: text,
    attachments: attachments,
    updatedAt: Date.now(),
    assistantId: assistantId,
    quoteText: quoteText
  };
  drafts.set(key, entry);
  enforceDraftBounds();
}

// 剔死件（恢复链用）：fs.accessSync 逐件校验 PendingAttachment.localPath（绝对路径）剔除
// 文件缺失件——恢复的引用全部真实可达（发送路径另有载荷组装失败兜底）。纯函数，断言直跑
export function pruneDeadAttachments(atts: PendingAttachment[]): PendingAttachment[] {
  const alive: PendingAttachment[] = [];
  for (const att of atts) {
    try {
      if (fs.accessSync(att.localPath)) {
        alive.push(att);
      }
    } catch {
      // 文件不在或不可达 = 死件，剔除（try 包裹：accessSync 对不可达路径抛错非返假）
    }
  }
  return alive;
}
