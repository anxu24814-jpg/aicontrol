// DS file_id 失效自愈域（DS 全家桶二期 S4 #11，自 ChatStreamFlowCtrl.onStreamError 分流出来的
// 独立编排件）。一句话职责 =「400 且错误体说 file_id 失效 → 整轮附件重传 → 同请求重发一次」。
// · 为什么独立成件：自愈要读库（message_attachments.localPath）、要上传（DsFilesClient）、
//   要改请求历史（roundHistory 活引用）、要重发（Key 池 attemptCurrent）——四件事跨四层，
//   塞进流域会让 1113 行的 ChatStreamFlowCtrl 再涨。流域只留 4 行薄接线。
// · 为什么按 attachId 而非 nodeId 取件：任务书定案写「按 attachment_refs 以 nodeId 取整轮
//   全集」，其前提是「remoteFileId 只存内存、DB 无该列，只能按轮猜」。本笔在 AiImagePart
//   上补 attachId（附件行 id，构造时带上），回写即可与附件行**一对一精确对应**——比按轮
//   位置对应更稳（多图轮不会串位把 A 的 file_id 写给 B）；拿不到 attachId 的部件（历史
//   回放行）直接跳过，不猜。
// · 只处理「零产出」的失败：已有正文增量时用户已看到内容，重发会造成重复输出（与自动重试
//   域同一红线）。
// · 上限 2 次 + 指数退避：官方 file_id 有效期 1 小时（DS_FILES_EXPIRES_AFTER_SECONDS），
//   过期后重传必然成功；连续 2 次仍失败说明不是过期而是别的问题（权限/端点/网络），继续
//   重试只会拖长失败感知。超限后原样透传服务端报错，不吞。
import { relationalStore } from '@kit.ArkData';
import { AiChatMessage, AiConnection, AiImagePart } from '../../common/providers/AiTypes';
import {
  DsFilesUploadOutcome, DsFilesUploadTarget, resolveDsUploadTarget, uploadDsFile
} from '../../common/providers/DsFilesClient';
import { sharedRdbStore } from '../../common/store/ChatDb';
import { workspaceFilesDir } from '../../common/store/WorkspaceDb';

// 自愈上限（含首次）与退避基数：第 1 次 600ms、第 2 次 1200ms
export const DS_FILE_RETRY_MAX: number = 2;
export const DS_FILE_RETRY_BASE_DELAY_MS: number = 600;

// file_id 失效判据（纯函数，断言直跑）：必须**同时**提到文件对象与失效语义，两面都命中才算。
// 只提文件（file_id is required / 附件不支持）不重传——那不是失效，重传也救不回来；
// 只提失效（invalid request / 参数错误）也不碰——与文件无关的 400 误重传是纯浪费。
// 覆盖三族措辞：官方英文（file_id / file id + invalid / not found / expired / no longer）、
// 中转英文变体（file does not exist / unknown file）、中文中转（文件 + 不存在 / 无效 /
// 过期 / 失效 / 找不到）
export function isDsFileIdInvalidMessage(message: string): boolean {
  const lower: string = message.toLowerCase();
  // ★ file 单词单列：真实报错常写「the file has expired」而不带 _id 后缀；宽松匹配的
  // 误判面（如 profile invalid）由两道闸兜住——只在**本轮确有 file 引用件**时才动作
  //（dsFilePartsOf 空即不自愈），且总次数上限 2
  const mentionsFile: boolean = lower.includes('file') || lower.includes('attachment') ||
    lower.includes('upload') || message.includes('文件') || message.includes('附件');
  if (!mentionsFile) {
    return false;
  }
  return lower.includes('invalid') || lower.includes('not found') ||
    lower.includes('does not exist') || lower.includes('no longer') ||
    lower.includes('expired') || lower.includes('expire') ||
    lower.includes('unknown file') || lower.includes('deleted') ||
    message.includes('不存在') || message.includes('无效') || message.includes('过期') ||
    message.includes('失效') || message.includes('找不到') || message.includes('已删除');
}

// 退避间隔（attempt 从 1 起）：600 / 1200，封顶 4 倍基数——重传是用户可感知的等待，间隔过
// 长会被当成卡死
export function dsFileRetryDelayMs(attempt: number): number {
  const n: number = attempt < 1 ? 1 : attempt;
  const capped: number = n > 4 ? 4 : n;
  return DS_FILE_RETRY_BASE_DELAY_MS * capped;
}

// 本轮待自愈的文件部件（纯函数）：取**最后一条 user 消息**（本轮提问；工具轮的中间 assistant
// 消息不携带附件）里 data 为空（file 引用件，非 base64 图片）且 attachId 非空的部件。
// 空数组 = 无可自愈对象（纯文本轮 / 图片走 base64 轮 / 历史回放无 attachId 轮）
export function dsFilePartsOf(history: AiChatMessage[]): AiImagePart[] {
  const out: AiImagePart[] = [];
  for (let i = history.length - 1; i >= 0; i--) {
    const m: AiChatMessage = history[i];
    if (m.role !== 'user') {
      continue;
    }
    const images: AiImagePart[] | undefined = m.images;
    if (images === undefined) {
      return out; // 末条 user 无图 = 纯文本轮，不再往前找（更早的图属上一轮）
    }
    for (const part of images) {
      if (part.data !== '') {
        continue; // base64 图片件不经 file_id
      }
      const attachId: string = part.attachId ?? '';
      if (attachId === '') {
        continue; // 拿不到附件身份就不猜（见件头「为什么按 attachId」）
      }
      out.push(part);
    }
    return out;
  }
  return out;
}

// 附件行（自愈取数面：只取重传必需的五个字段）
interface DsFileRow {
  id: string;
  name: string;
  mime: string;
  size: number;
  absPath: string;
  // 重传后回执的官方 file_id（'' = 尚未上传；uploadAll 逐件回填）
  fileIdOf: string;
}

// 按附件行 id 取本地原件（DB 读；localPath 入库是 filesDir 相对路径，此处拼绝对）
async function queryFileRows(ids: string[]): Promise<DsFileRow[]> {
  if (ids.length === 0) {
    return [];
  }
  const filesDir: string = workspaceFilesDir();
  if (filesDir === '') {
    return []; // ctx 未捕获（进程早期）——无原件可传，交调用方原样透传报错
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const marks: string = ids.map((_id: string): string => '?').join(',');
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, name, mime, size, localPath FROM message_attachments WHERE id IN (' + marks + ')',
    ids);
  const rows: DsFileRow[] = [];
  try {
    while (result.goToNextRow()) {
      const localPath: string = result.getString(result.getColumnIndex('localPath'));
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        mime: result.getString(result.getColumnIndex('mime')),
        size: result.getLong(result.getColumnIndex('size')),
        absPath: filesDir + '/' + localPath,
        fileIdOf: ''
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 宿主面（流域注入；全部单方法薄闭包，与 ChatRetryHost / ChatAutoRetryHost 同形）
export interface ChatFileRetryHost {
  conversationId: () => string;
  // 当前轮连接（判官方档 + 供上传目标解析的 liveConn 通道）
  liveConn: () => AiConnection | null;
  // 本轮请求历史**活引用**（回写 remoteFileId 后 attemptCurrent 重发即生效）
  roundHistory: () => AiChatMessage[];
  // 同 key 重发当前请求（Key 池咽喉点，禁另起请求链）
  attemptCurrent: () => void;
  // 最终失败收尾（自检轮补：重传自身失败时本件须能把轮次收掉——首版只 toast，onStreamError
  // 已提前 return，轮次停在流式态直到用户手点停止）
  failRound: (message: string, status: number) => void;
  toast: (message: string) => void;
}

export class ChatFileRetryCtrl {
  private host: ChatFileRetryHost;
  private attempts: number = 0;
  // 在途标记：一次自愈未完成前不接第二次（重传是秒级 IO，期间重复进入会并发上传同一批文件）
  private inflight: boolean = false;
  // 退避定时器句柄（自检轮补：首版裸 setTimeout 无句柄——上一轮的延时链会在新轮/停止后
  // 照常跑完重传；句柄在轮首复位时清掉，链路自身的 attemptCurrent 还有令牌闸兜底）
  private timer: number = -1;

  constructor(host: ChatFileRetryHost) {
    this.host = host;
  }

  // 轮次复位（起流/收尾两处调用）：次数与在途态归零 + 掐掉上一轮残留的退避定时器
  reset(): void {
    this.attempts = 0;
    this.inflight = false;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  // 分流入口（流域 onStreamError 调用）：true = 已接管（本次失败不上屏、不 failRound，
  // 重传完成后由 attemptCurrent 重新起流）；false = 不接管（调用方照常走后续判据）
  takeOver(status: number, sawContent: boolean, message: string): boolean {
    if (status !== 400 || sawContent || this.inflight) {
      return false;
    }
    if (!isDsFileIdInvalidMessage(message)) {
      return false;
    }
    if (this.attempts >= DS_FILE_RETRY_MAX) {
      // 超限：不吞原报错（用户要看到服务端到底说了什么），只补一句已尽力
      this.host.toast('文件重新上传后仍失败，请重新选择该文件');
      return false;
    }
    const parts: AiImagePart[] = dsFilePartsOf(this.host.roundHistory());
    if (parts.length === 0) {
      return false; // 无可重传对象（纯文本轮 / 回放行无 attachId）——原样透传
    }
    this.attempts++;
    this.inflight = true;
    this.run(parts, this.attempts);
    return true;
  }

  // 自愈执行链（异步；失败一律回落到「不重发 + 可见提示」——静默重试是 P0 级体验缺陷）
  private run(parts: AiImagePart[], attempt: number): void {
    const convId: string = this.host.conversationId();
    const liveConn: AiConnection | null = this.host.liveConn();
    this.timer = setTimeout((): void => {
      this.timer = -1;
      queryFileRows(parts.map((p: AiImagePart): string => p.attachId ?? ''))
        .then((rows: DsFileRow[]): Promise<DsFileRow[]> => {
          if (rows.length === 0) {
            throw new Error('本地原件已不存在，请重新选择该文件');
          }
          return resolveDsUploadTarget(convId, liveConn).then(
            (target: DsFilesUploadTarget | null): Promise<DsFileRow[]> => {
              if (target === null) {
                throw new Error('未能定位 DeepSeek 官方连接，请确认当前会话模型与服务商密钥后重试');
              }
              // 逐个重传（串行：并发 multipart 会被服务端按连接数限流，且失败归因更难）
              return this.uploadAll(target, rows);
            });
        })
        .then((uploaded: DsFileRow[]): void => {
          // 回写：按附件行 id 与部件 attachId 一对一写入（同 id 多部件同值）
          for (const row of uploaded) {
            for (const part of parts) {
              if ((part.attachId ?? '') === row.id) {
                part.remoteFileId = row.fileIdOf;
              }
            }
          }
          this.inflight = false;
          this.host.attemptCurrent(); // 同 key 重发（新 file_id 已在请求历史活引用里）
        })
        .catch((e: Object): void => {
          this.inflight = false;
          // 不重发且**必须收尾**（自检轮修）：onStreamError 在 takeOver 处已提前 return，
          // 原「流域随后收尾」不成立——首版只 toast，轮次永久停在流式态。failRound 落
          // notice + finishStream('error')，状态码传 0（无码哨值，不挂跳转动作）
          this.host.failRound((e as Error).message, 0);
          // attempts 不回收——同一轮不无限重传
        });
    }, dsFileRetryDelayMs(attempt));
  }

  // 串行上传全部行：任一件失败即整体中止（半套新 id 重发 = 一半失效一半有效，服务端报错更难读）
  private uploadAll(target: DsFilesUploadTarget, rows: DsFileRow[]): Promise<DsFileRow[]> {
    let chain: Promise<void> = Promise.resolve();
    const done: DsFileRow[] = [];
    for (const row of rows) {
      chain = chain.then((): Promise<void> =>
        uploadDsFile(target, row.absPath, row.name, row.mime, row.size)
          .then((outcome: DsFilesUploadOutcome): void => {
            if (!outcome.ok) {
              throw new Error('「' + row.name + '」重新上传失败，' + outcome.errorText);
            }
            row.fileIdOf = outcome.fileId;
            done.push(row);
          }));
    }
    return chain.then((): DsFileRow[] => done);
  }
}
