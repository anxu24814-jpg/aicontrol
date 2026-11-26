// 请求历史读口域：按预算从库读出「发给模型的历史」的只读口——按页循环、不碰 UI 容器、
// 不通知、不触发任何 refreshDisplay。UI 窗口（ChatDataSource.messages）退回纯渲染职责后，
// 发送 / 重试 / 离屏 web / 用量面板 / 压缩选段五处的历史输入统一走本口（五处同源）。
// · 为什么独立成件（反碎片下限申报）：不能并入 ChatContextSource——该件已按域拆过两刀且
//   承载图读写路径路由，继续塞读口会重新越硬线；本件只做「预算内历史读取」一件事。
// · 为什么不并入预算件 RequestHistoryBudget：本件有 DB 依赖（readPathPageRows），预算件
//   必须零 I/O 可被断言复制直跑——混入即断链。
// · 页大小固定 QUERY_TAIL_LIMIT（50）：adaptPathRows 的 IN 查询把整页 id 作绑定参数，按
//   SQLite 保守上限 999 计，一次传 1024 存在超限风险；50 一页恒定安全。不引入递归 CTE
//  （readPathPage 注释：官方 RDB 文档未背书前不引入）。
// · startCursor 语义：null = 从分支 head 起**含 head 自身**（重试链——head = 锚点 user，
//   天然含锚点、天然不含旧分支旧答案）；非 null = 从该节点起**不含自身**（发送链——
//   prepareRun 已把 head 前移到本条 user 节点，传该节点 id 即排除本条，防 push userReq
//   后本条重复入史；复用 readPathPage 翻页「不含游标」现成语义，与续页游标同构）。
//   翻页续读恒传「上一页最早节点 id」。
// · 读取异常上抛，由编排层（ChatRequestHistoryCtrl）决定降级——本件不吞错（P0-1）。
import { MessageRow, QUERY_TAIL_LIMIT } from '../store/ChatDb';
import { readPathPageRows } from './ChatContextSource';

export interface RequestHistoryReadResult {
  // 升序：根 → 起点，条数 = maxRows 或到顶为止
  rows: MessageRow[];
  // true = 已到会话起点或 parent 链中断；仅用于降级日志与诊断，不参与裁剪
  reachedTop: boolean;
}

// 按预算读请求历史：maxRows 由调用方经 resolveReadRows / resolveRowBudget 得出（本件不做
// 「含不含本条」的口径转换）；空会话 / 未出生会话（branchId === ''）/ maxRows ≤ 0 返回空
// 且不抛；链条中断（悬边）按已读部分返回、reachedTop = true，不假造。
export async function readRequestHistoryRows(conversationId: string,
  branchId: string, maxRows: number, startCursor: string | null): Promise<RequestHistoryReadResult> {
  if (branchId === '' || maxRows <= 0) {
    return { rows: [], reachedTop: true };
  }
  let acc: MessageRow[] = [];
  let cursor: string | null = startCursor;
  let reachedTop: boolean = false;
  while (acc.length < maxRows) {
    // 页大小恒 ≤ QUERY_TAIL_LIMIT（最后一页按剩余需求收窄；禁一次传 maxRows——IN 绑定上限）
    const want: number = Math.min(QUERY_TAIL_LIMIT, maxRows - acc.length);
    const page: MessageRow[] = await readPathPageRows(conversationId, branchId, cursor, want);
    acc = page.concat(acc); // page = 更老一页（根→起点升序），拼在已读段之前保升序
    if (page.length < want) {
      // 短页 = 到顶（会话起点或链中断——readPathPage 悬边防御按已收集部分照返）
      reachedTop = true;
      break;
    }
    cursor = page[0].id; // 下一页游标 = 本页最早节点（readPathPage 不含游标自身）
  }
  return { rows: acc, reachedTop: reachedTop };
}
