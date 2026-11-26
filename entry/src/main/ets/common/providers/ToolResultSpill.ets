// 工具结果溢出落盘 IO 小件（2026-10-26 注入链治理 P0-c，方案-注入链治理施工总案-20261025
// §三 P0-c + 20261026 核查修订定案）：超 8K 非 MCP 工具结果「先落临时区、再回信封」的
// IO 侧单一来源——文件名铸造（工具名 + 时间戳 + 序号防同轮并发撞名）、落盘执行、失败降级。
// · 为何独立成件而非并入 ToolClip（反碎片下限②书面理由，核查修订定案）：ToolClip 头注释
//   L12 明写「零 import（纯 JSON 字符串处理）——断言复制直跑即自足」，落盘 IO 写进 ToolClip
//   即破 assert-ui-shape 的 ToolClip 直跑面；分流判据与信封组装纯函数在 ToolClip，本件只做
//   IO 编排与三处共用（消费方 = ChatToolRoundCtrl 串行/并行两路 + ChatToolResendCtrl 重发路，
//   分属三件无法单点并入）。
// · 落盘复用 exec_code 同链：writeWorkspaceTmpTextFile（名称闸 + 两闸预检〔单件 10 MB /
//   总量 256 MB〕+ UTF-8 直写）——临时区既有读回口 exec_output_read 直接可读（ToolCodeExec
//   执行器，desc 已扩「本会话工具输出」语义）。
// · 失败降级不阻断（R2）：写失败 = 现有截断 + 「未能保存全文」告知句，禁静默截断。
// · 热路径成本：只在超 8K（罕见路径）时多一次同步写——超限结果本来就要丢，写盘是纯增益；
//   writeWorkspaceTmpTextFile 为同步 fs 形态（ToolCodeExec data 落件同链同形态）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sanitizeWorkspaceName } from '../WorkspaceUtil';
import { ensureWorkspaceTmpConversationDir, writeWorkspaceTmpTextFile }
  from '../store/WorkspaceDbTmp';
import { clipSearchPayload, clipToolResultForTool, composeToolSpillEnvelope,
  shouldBypassToolClip, shouldSpillToolResult, spillHeadPreview, spillTailPreview,
  TOOL_RESULT_SPILL_THRESHOLD, withSpillFailedNote } from './ToolClip';

const TAG: string = 'ToolResultSpill';

// 溢出件名唯一段（tool-<清洗后工具名>-<毫秒时间戳>-<自增序号>.log——同轮并行同名工具也不
// 撞名；工具名进件名让临时区管理页可辨识来源。sanitize 兜非法字符/超长/代理对三防，名称闸
// 在 writeWorkspaceTmpTextFile 内二道复核）
let spillSeq: number = 0;

function nextToolSpillFileName(toolName: string): string {
  spillSeq += 1;
  return sanitizeWorkspaceName('tool-' + toolName + '-' + Date.now() + '-' +
    spillSeq + '.log');
}

// 单点分流口（三消费方统一经此——替代直调 ToolClip.clipToolResultForTool 的落盘增强版）：
// · MCP → 原样返回（32K/4K 契约，McpText executor 自截，判据单源 shouldBypassToolClip）
// · ≤8K / 开关关 / 无会话上下文（防御：临时区按会话分目录，无会话无处落）→ 与现状逐字节
//   一致（复用 clipToolResultForTool，含搜索载荷结构化截断两态）
// · >8K 的搜索类结构化载荷（summary + results）→ 先试结构化截断：results 能装进阈值就回
//   合法 JSON、不落盘（引文卡数据源不丢——落盘信封纯文本 JSON.parse 必败 = 引文卡静默
//   消失）；装不进才继续落盘
// · >8K 且开关开 → 落盘成功回信封（文件名/原字符数/头尾预览/exec_output_read 指引）；
//   落盘失败降级现有截断 + 「未能保存全文」告知句
// ★ 2026-10-26 P6 自检修复（4）：落盘前先建会话临时目录（ensureWorkspaceTmpConversationDir
//   mkdirSync 递归 + EEXIST 容错，幂等）——此前只有跑过 exec_code / workspace_stage 的会话
//   目录在场，其余会话恒 ENOENT 降级，P0-c 主承诺不生效
// isError 语义零回归：超 8K 回执在旧路径同样拿不出完整 JSON（硬截串 parse 必败，
// detectErrorResult 兜 false），信封纯文本同判 false——两路一致
export function clipToolResultForToolSpilled(toolName: string, result: string,
  conversationId: string): string {
  if (shouldBypassToolClip(toolName)) {
    return result;
  }
  if (!shouldSpillToolResult(result) || conversationId === '') {
    return clipToolResultForTool(toolName, result);
  }
  const structured: string = clipSearchPayload(result, TOOL_RESULT_SPILL_THRESHOLD);
  if (structured !== '') {
    return structured;
  }
  try {
    ensureWorkspaceTmpConversationDir(conversationId);
    const savedName: string = writeWorkspaceTmpTextFile(conversationId,
      nextToolSpillFileName(toolName), result);
    return composeToolSpillEnvelope(savedName, result.length,
      spillHeadPreview(result), spillTailPreview(result));
  } catch (e) {
    hilog.warn(0x0001, TAG, '工具结果落盘失败，降级为截断（%{public}s）：%{public}s',
      toolName, (e as Error).message);
    return withSpillFailedNote(clipToolResultForTool(toolName, result));
  }
}
