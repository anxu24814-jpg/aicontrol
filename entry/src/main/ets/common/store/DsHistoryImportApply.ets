// DS 历史导入落库域（DS 全家桶接入批 S5③）。一句话职责 =「把 DsHistoryZip 解析出的会话清单
// 逐会话单事务发布为图态新会话」——发布面单件，解析面在 DsHistoryZip（彼件不碰库）。
// · 发布形制 = 逐会话照 ConversationForkCopy.publishCopy（M5 单事务：会话行全列显式 + branches
//   父链 + messages 父链 + 附件行与 refs 同一提交单元）。导入与 fork 的先例前提差异两步必补：
//   ①writeGraphCapabilityLevel(db, 2) 前置（导入可能产生首个图会话——K2 契约「图会话落库
//   同拍」，先例 = GraphTransfer.importGraphDomain「导入前置 capability 写 2」）；
//   ②seedMessageSeq 重播种收尾（先例 = ExportImportApply finally——导入写回 seq ⇒ 进程内
//   记账过期，漏播种 = 后续发送 seq 乱序重号）。
// · 两段式资源纪律（M5① 先例）：图片文件先落附件目录、元数据后进事务——失败即拒 + 已备文件
//   清理，不发布半会话；事务回滚不得已删文件红线（rollback 只回滚行，文件由本域 catch 清）。
// · 导入映射口径（任务书 §1 代决 3/7）：会话归属默认助手（assistantId 置 ''，行侧解析默认）；
//   providerId/modelId 等配置列置默认空值（发送时走全局解析链）；createdAt/updatedAt 用 DS
//   原时间（消息 createdAt 同口径）；seq 按链序经 MessageSeqDb 分配器铸造（D1 红线 = 铸造
//   与行对象构造同同步块）；只建单分支（DS 主线即分支），runId 置空串（导入无运行）。
// · 失败口径：单会话失败整会话回滚不半导（事务 rollback + 图片清理），其余会话继续——聚合
//   呈报面与解析面同口径（DsImportApplyResult.failedSessions 分档，调用方 toast 分档呈报）。
//   hilog 对**会话落库失败**不打原始异常（RDB 错误消息可能回显 SQL 与绑定值，照
//   ExportImportApply C1 口径）；seq 播种失败例外打 message（彼口纯 JS Error 无 SQL 面，
//   照 ExportImportApply :462 先例）。
// · 弱依赖：本件 → ChatDb（id 铸造/库句柄）+ MessageBranchDb（词表常量）+ MessageSeqDb（seq
//   铸造与播种）+ ChatDbMigrate（capability 写口）+ AttachmentDb（文件清理/目录读出）+
//   DbWriteQueue（写串行链）+ DsHistoryZip（解析产物类型）单向，均不反向 import 本件。
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { attachmentFilesDir, removeAttachmentFiles } from './AttachmentDb';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { CONV_STATE_GRAPH, ORIGIN_IMPORT } from './MessageBranchDb';
import { nextRowSeq, seedMessageSeq } from './MessageSeqDb';
import { writeGraphCapabilityLevel } from './ChatDbMigrate';
import { runWriteQueued } from './DbWriteQueue';
import { DsParsedImage, DsParsedMessage, DsParsedSession, DsParsedZip } from '../chat/DsHistoryParse';

const DOMAIN: number = 0xE17;
const TAG: string = 'DsHistoryImportApply';

// 附件目录名（与 AttachmentDb.ATTACH_DIR_NAME / ConversationForkCopy.ATTACH_DIR_NAME 同值；
// 三处互不 import，靠断言钉一致——本件只用于拼图片的相对路径，文件写入自备 fd 三步法）
const ATTACH_DIR_NAME: string = 'attachments';

// ── 产物与结果类型 ──

// 单会话发布计数
interface DsSessionPublish {
  messageCount: number;
  imageCount: number;
}

// 整批应用结果（预览态 → 落库回执；failedSessions > 0 = 部分成功，分档呈报）
export interface DsImportApplyResult {
  appliedSessions: number;
  appliedMessages: number;
  appliedImages: number;
  failedSessions: number;
}

// 图片两段式准备产物（文件已落附件目录、待事务内配行；messageIndex = 所属消息下标，
// 事务内按消息取组配行）
interface DsPreparedImage {
  image: DsParsedImage;
  messageIndex: number;
  attachmentId: string;
  relPath: string; // 相对 filesDir（'attachments/<铸名>'，行列值）
}

// ── 入口 ──

// 逐会话发布解析产物（预览与落库两消费方共用同一份 DsParsedZip——本函数只消费 sessions，
// report 归预览呈报面）。次序 = capability 写 2 前置 → 逐会话两段式发布 → seq 重播种收尾。
export async function applyDsHistoryImport(parsed: DsParsedZip): Promise<DsImportApplyResult> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  // 两步必补①：capability 写 2（幂等只升不降——本机已是 2 零写；全部会话失败时标记已升，
  // 无害：能力级 ≥ 实际图用量恒成立的只升不变量）
  await writeGraphCapabilityLevel(db, 2);
  const result: DsImportApplyResult = {
    appliedSessions: 0, appliedMessages: 0, appliedImages: 0, failedSessions: 0
  };
  for (const session of parsed.archive.sessions) {
    try {
      const published: DsSessionPublish = await publishDsSession(db, session);
      result.appliedSessions++;
      result.appliedMessages += published.messageCount;
      result.appliedImages += published.imageCount;
    } catch (e) {
      // 整会话已回滚（事务内 rollback）+ 已备图片已清——分账继续下一会话（不打原始异常，
      // RDB 错误消息可能回显 SQL 与绑定值）
      result.failedSessions++;
      hilog.warn(DOMAIN, TAG, 'DS 导入会话落库失败（整会话已回滚，其余会话继续）：第 %{public}d 个',
        result.failedSessions);
    }
  }
  // 两步必补②：seq 分配器重播种（会话内 seq 已显式落库 ⇒ 记账可能与库真值漂移——读 MAX(seq)
  // 归一，漏播种 = 后续发送 seq 乱序重号；失败留痕不吞，下次启动 sweep 兜底）
  try {
    await seedMessageSeq(db);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'DS 导入后 seq 分配器重播种失败（下次启动 sweep 兜底）：%{public}s',
      (e as Error).message);
  }
  hilog.info(DOMAIN, TAG,
    'DS 导入完成：会话 %{public}d 个（失败 %{public}d），消息 %{public}d 行，图片 %{public}d 张',
    result.appliedSessions, result.failedSessions, result.appliedMessages, result.appliedImages);
  return result;
}

// ── 单会话发布（两段式：文件先行 → 单事务）──

async function publishDsSession(db: relationalStore.RdbStore,
  session: DsParsedSession): Promise<DsSessionPublish> {
  const conversationId: string = nextMessageId('conv');
  // ① 铸造面先行（同步块内铸齐节点 id：DS 消息 id → 本应用消息 id；分支 head 与消息行共用，
  //    分支行先于消息行入事务，head 必须在开事务前定）
  const nodeIdOf: Map<number, string> = new Map<number, string>();
  for (const msg of session.messages) {
    nodeIdOf.set(msg.dsId, nextMessageId('msg'));
  }
  // 活动分支 = head 指向当前停留点的那条（解析面保证 currentDsId 必在一个 branchHeads 里；
  // 兜底取第一条，不产无分支会话）
  let activeBranchId: string = '';
  const branchIds: Map<number, string> = new Map<number, string>();
  for (const br of session.branches) {
    branchIds.set(br.headDsId, nextMessageId('br'));
  }
  const activeId: string | undefined = branchIds.get(session.currentDsId);
  if (activeId !== undefined) {
    activeBranchId = activeId;
  } else if (session.branches.length > 0) {
    activeBranchId = branchIds.get(session.branches[0].headDsId) ?? '';
  }
  // ② 图片资源先行（M5①：文件在元数据事务之前；present = false 的缺失图解析面已计数，
  //    落库面跳过不产行——缺失图只留名称大小的口径由「无行」天然成立）
  const prepared: DsPreparedImage[] = [];
  try {
    for (let m = 0; m < session.messages.length; m++) {
      for (const img of session.messages[m].images) {
        if (!img.present) {
          continue;
        }
        const attachmentId: string = nextMessageId('att');
        const relPath: string = copyImportedImage(img.sourceAbs,
          attachmentId + extWithDotOf(img.name));
        prepared.push({ image: img, messageIndex: m, attachmentId: attachmentId,
          relPath: relPath });
      }
    }
    // ③ 单事务发布（IMMEDIATE；写串行链入链照 publishCopy）
    const imageTotal: number = prepared.length;
    const publish: DsSessionPublish = await runWriteQueued('publishDsSession',
      async (): Promise<DsSessionPublish> => {
        const tx: relationalStore.Transaction =
          await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
        try {
          // 会话行（全列显式照 publishCopy：migrateState 与 activeBranchId 显式落 graph 态；
          // assistantId 置 '' = 默认助手〔代决 7〕；providerId/modelId 等配置列置默认 =
          // 发送时走全局解析链；titleSource 照备份导入启发式——非「新对话」视为手改防覆盖）
          await tx.insert('conversations', {
            'id': conversationId,
            'title': session.title,
            'providerId': '',
            'createdAt': session.createdAtMs,
            'updatedAt': session.updatedAtMs,
            'promptId': '',
            'assistantId': '',
            'titleSource': session.title !== '' && session.title !== '新对话' ? 'manual' : '',
            'favorite': 0,
            'modelProviderId': '',
            'modelId': '',
            'webSearchOverride': '',
            'suggestions': '',
            'activeBranchId': activeBranchId,
            'migrateState': CONV_STATE_GRAPH
          });
          // 分支行（每版本一条；head = 该版本选中链最深节点或当前停留点。兄弟版本由此进入
          // 现有行内版本步进器——零新显示组件）
          for (const br of session.branches) {
            await tx.insert('branches', {
              'id': branchIds.get(br.headDsId) ?? nextMessageId('br'),
              'conversationId': conversationId,
              'parentBranchId': null,
              'headMessageId': nodeIdOf.get(br.headDsId) ?? null,
              'name': '',
              'createdAt': br.createdAtMs
            });
          }
          // 消息行全树（seq 按 DS id 升序铸造 = 父先于子；parentMessageId = 归档父映射，
          // 父不在树内/根 = NULL）+ 图片行与 refs（同一提交单元——不经 AttachmentDb.
          // insertAttachments：彼口收 RdbStore，事务对象与之不同型，照 publishCopy 同款直写）
          for (let m = 0; m < session.messages.length; m++) {
            const msg: DsParsedMessage = session.messages[m];
            let parentMessageId: string | null = null;
            if (msg.parentDsId !== null) {
              parentMessageId = nodeIdOf.get(msg.parentDsId) ?? null;
            }
            const row: relationalStore.ValuesBucket = {
              'id': nodeIdOf.get(msg.dsId) as string,
              'conversationId': conversationId,
              'role': msg.role,
              'content': msg.content,
              'reasoning': msg.reasoning,
              'status': msg.status,
              'createdAt': msg.createdAtMs,
              'variants': '',
              'variant_active': 0,
              'parentMessageId': parentMessageId,
              'runId': '',
              'ownerAssistantId': '',
              'stepIndex': null,
              'origin': ORIGIN_IMPORT,
              'seq': nextRowSeq(conversationId)
            };
            // v64 服务端工具列：有联网过程才写键（'' 不写 = 列落 NULL，与实时链同口径）
            if (msg.serverToolsJson !== '') {
              row['server_tools'] = msg.serverToolsJson;
            }
            await tx.insert('messages', row);
            for (const p of prepared) {
              if (p.messageIndex !== m) {
                continue;
              }
              await tx.insert('message_attachments', {
                'id': p.attachmentId,
                'messageId': nodeIdOf.get(msg.dsId) as string,
                'conversationId': conversationId,
                'kind': 'image',
                'name': p.image.name,
                'mime': p.image.mime,
                'size': p.image.sizeBytes,
                'localPath': p.relPath,
                'parsedText': '',
                'createdAt': msg.createdAtMs
              });
              await tx.insert('attachment_refs', {
                'id': nextMessageId('ref'),
                'conversationId': conversationId,
                'attachmentId': p.attachmentId,
                'nodeId': nodeIdOf.get(msg.dsId) as string,
                'createdAt': msg.createdAtMs
              });
            }
          }
          await tx.commit();
          return { messageCount: session.messages.length, imageCount: imageTotal };
        } catch (e) {
          await tx.rollback();
          throw e as Error;
        }
      });
    return publish;
  } catch (e) {
    // 失败不发布半会话（M12 同款）——已备新文件清理（best-effort；清理失败者由启动孤儿
    // 收敛兜底，照 ConversationForkCopy 失败口径）
    removeAttachmentFiles(prepared.map((p: DsPreparedImage): string => p.relPath));
    throw e as Error;
  }
}

// ── 件内私有助手 ──

// 扩展名（含点；无扩展名回 ''）——照 ConversationForkCopy.extOfLocalPath 同语义（彼件收
// localPath 本件收原始文件名，逻辑同源不互 import）
function extWithDotOf(name: string): string {
  const cut: number = name.lastIndexOf('.');
  if (cut < 0 || cut < name.lastIndexOf('/')) {
    return '';
  }
  return name.substring(cut);
}

// 图片资源复制（cacheDir 绝对源 → 附件目录相对路径）。fd 三步法与失败自清照
// AttachmentDb.copyAttachmentResource :475-513 形制——彼件源路径锚 filesDir 相对，
// DS 导入源在 cacheDir 解压临时目录（绝对路径传彼函数会拼错前缀），故按同形制自写：
// openSync(READ_ONLY) → openSync(CREATE|READ_WRITE) → copyFileSync(fd, fd) → 成对 closeSync；
// 失败自清「本次创建」的半截目标。
function copyImportedImage(sourceAbs: string, newFileName: string): string {
  const filesDir: string = attachmentFilesDir();
  if (filesDir === '') {
    throw new Error('附件目录未就绪，无法导入图片');
  }
  if (!fs.accessSync(sourceAbs)) {
    throw new Error('源图片在本机已找不到');
  }
  if (fs.statSync(sourceAbs).size <= 0) {
    throw new Error('源图片内容为空，已损坏');
  }
  const newRel: string = ATTACH_DIR_NAME + '/' + newFileName;
  const destAbs: string = filesDir + '/' + newRel;
  const destExisted: boolean = fs.accessSync(destAbs);
  const srcFile: fs.File = fs.openSync(sourceAbs, fs.OpenMode.READ_ONLY);
  try {
    const destFile: fs.File = fs.openSync(destAbs,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.copyFileSync(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(destFile);
    }
  } catch (e) {
    if (!destExisted) {
      try {
        fs.unlinkSync(destAbs);
      } catch (cleanupErr) {
        // 删不掉（占用/权限）留残留：启动孤儿收敛兜底，不吞原始错误
      }
    }
    throw e as Error;
  } finally {
    fs.closeSync(srcFile);
  }
  return newRel;
}
