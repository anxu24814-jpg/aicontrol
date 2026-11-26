// 压缩摘要存储域（任务书-上下文压缩-20260923 §2.1）：messages 表
// role='summary' 行（coversToSeq = 覆盖边界）的读写与边界查询收拢本文件。
// ★ 本域承载**边界行两类**——role='summary'（摘要，带正文）与
// role='clear'（清空，正文恒空）；边界真源同为 summary_bindings 行（表名沿历史不改，语义 =
// 「边界节点 ↔ 覆盖区间」绑定）。新增 role 取值零迁移（role 列建表无 CHECK）。
// · 为什么新开本件而不并入 ChatDb.ets（宪法「反碎片下限」三问）：①职责一句话 = 压缩摘要行
//   的读写与边界查询，有独立职责缝；②无既有同域可并——MessageSeqDb 管序号，为别表主域，
//   ChatDb.ets 剔头已近硬线；③实逻辑非转接壳。
// · 依赖方向（零环红线，坑50）：本件 → ChatDb（sharedRdbStore）单向；**禁反向**（ChatDb
//   不 import 本件）。
// · legacy 写面三方法（insertSummaryMessage / adoptCompressSummary / deleteSummaryRows）
//   随线性写路径整域退役删除；现役 = 读面查询与采用在途登记。graph 会话的摘要采用/删除 =
//   ChatGraphCommandSource.adoptGraphSummary / deleteGraphSummary（binding 同事务，K9/K4）。
// · 每会话至多一条生效摘要；更早的摘要行在请求组装侧被自然吞掉（seq <= boundary 一律
//   不进请求）。
import { relationalStore } from '@kit.ArkData';
import { MessageRow, sharedRdbStore } from './ChatDb';

// ── 采用在途登记（S7 纵深防御）──
// 缺口：生成侧有在途闸（CompressGen.inflight），采用侧原两侧皆无——「采用」键双击即两路
// 落库各跑一遍（两个摘要节点）。本登记是它的域侧收口：面板 @State adopting 只挡同一面板的
// 连击（UI 面，见 CompressPreviewSheet.adopt），跨实例与迟到路径由本登记兜底。登记键 = 会话
// id，**置位与复位在同一次 adopt 调用内成对**（try/finally），故调用方无需参与置位——面板
// 若也置位会与域侧入口检查自锁（首调即被自己拦下）。adopt 单点 = ChatGraphCommandSource.
// adoptGraphSummary（该件 import 本件取登记原语）。
const adoptInflight: Set<string> = new Set<string>();

// 在途查询（adopt 入口的写前闸：在途即拒，不排队——用户手一松再点即可重试）
export function isAdoptInflight(conversationId: string): boolean {
  return adoptInflight.has(conversationId);
}

// 置位 / 复位（'' = 无库会话，不入登记——空串登记会让所有无库会话共用一个键，误闸无关会话）
export function markAdopt(conversationId: string, on: boolean): void {
  if (conversationId === '') {
    return;
  }
  if (on) {
    adoptInflight.add(conversationId);
  } else {
    adoptInflight.delete(conversationId);
  }
}

// 按角色白名单取最新一行（三读口的共同实现；role 走参数占位，禁把角色名拼进 SQL 串）。
// ★ 原实现硬编码 role='summary'——扩出 clear 边界行后，
// 「最新摘要」（压缩卡）与「最新边界」（请求注入探针）是两问，抽本函数供三读口各取所需
async function queryLatestByRoles(conversationId: string,
  roles: string[]): Promise<MessageRow | null> {
  const placeholders: string = roles.map((_r: string): string => '?').join(', ');
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT id, conversationId, role, content, reasoning, status, createdAt, rowid, seq, ' +
    'variants, variant_active, coversToSeq FROM messages ' +
    'WHERE conversationId = ? AND role IN (' + placeholders + ') ORDER BY seq DESC LIMIT 1',
    [conversationId].concat(roles));
  try {
    if (result.goToNextRow()) {
      const row: MessageRow = {
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        role: result.getString(result.getColumnIndex('role')),
        content: result.getString(result.getColumnIndex('content')),
        reasoning: '',
        status: result.getString(result.getColumnIndex('status')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        rowid: result.getLong(result.getColumnIndex('rowid')),
        seq: result.getLong(result.getColumnIndex('seq')),
        variants: '',
        variantActive: 0
      };
      const coversIdx: number = result.getColumnIndex('coversToSeq');
      if (!result.isColumnNull(coversIdx)) {
        row.coversToSeq = result.getLong(coversIdx);
      }
      return row;
    }
    return null;
  } finally {
    result.close();
  }
}

// 最新生效摘要行（按 seq DESC 取第一条 role='summary'；无摘要 = null）。投影带 coversToSeq
// ——面板状态行与请求组装的边界判据都从本函数来（单一读取口，两消费方不各写查询）
export async function queryLatestSummary(conversationId: string): Promise<MessageRow | null> {
  return queryLatestByRoles(conversationId, ['summary']);
}

// 最新清空边界行（清空卡状态行：有无清空 + 覆盖边界；路径感知在 ChatContextSource 读口）
export async function queryLatestClear(conversationId: string): Promise<MessageRow | null> {
  return queryLatestByRoles(conversationId, ['clear']);
}

// 最新边界行（摘要或清空，两类同权）——请求注入口的廉价前置探针（有边界才走路径链上溯；
// 无边界直接回 null，与旧「先探摘要再上溯」同款省查形状）
export async function queryLatestBoundary(conversationId: string): Promise<MessageRow | null> {
  return queryLatestByRoles(conversationId, ['summary', 'clear']);
}

// 边界时间查询（面板状态行「覆盖 … 之前的内容」的时间来源）：取该 seq 行的 createdAt，
// 缺行回 0（边界行已被用户删除——面板据此退化为不带时间的形态，别为凑时间造第二个时钟源）
export async function queryBoundaryCreatedAt(conversationId: string,
  seq: number): Promise<number> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT createdAt FROM messages WHERE conversationId = ? AND seq = ? LIMIT 1',
    [conversationId, seq]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('createdAt'));
    }
    return 0;
  } finally {
    result.close();
  }
}
