// 会话列表摘要域。职责一句话 =「每会话一句可读摘要的取数、清洗与截断」。
// 判据 = docs/规范-列表卡片与组卡.md §4.10（摘要行 19vp、单行省略）。
// · 为何独立成件：ChatDb 与 ChatSessionList 两处已近或越 1200 硬线，不宜再添新功能；
//   本件只做摘要一件事，纯函数 cleanSnippet 可被断言直跑。
// · 为何按会话逐个取（2026-11-16 收窄）：逐会话查最后一条若走应用层 N+1 是 200 次 IO，但
//   原「全库 messages 一次聚合 + 壳侧过滤」的 GROUP BY 子查询会扫全表 messages——成本随历史
//   消息总量增长，与列表页可见量无关；退页重拉落在滑动窗口时与 UI 争 CPU/IO。现改为外层只扫
//   当前助手的 conversations、内层用 idx_messages_conv_seq(conversationId, seq) 逐会话索引
//   寻址取 MAX(seq)，成本随可见会话数而非消息总量。截断仍在 SQL 内做（substr 240），不把长
//   正文搬进内存。实测（2026-11-16 合成库 SQLite 3.50：140k 消息 / 290 会话 / 当前助手 80
//   会话）旧 SQL 17.8ms → 新 SQL 0.12ms；真机数字待 BLOCKED 同名清单验收。
// · 为何用 seq 不用 createdAt：同一毫秒可写多条，时间戳并列时无法决胜；seq 是写入侧分配的
//   会话内 0 基序号（ChatDbMigrate v37），唯一。seq 为 NULL 的老消息被 MAX 忽略，该会话退回
//   「暂无消息摘要」，不报错。
// · 只取 user / assistant：tool 回执与 notice 系统提示不是用户想看的「最后一句」。
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore } from '../store/ChatDb';

// 摘要目标长度（中文 ≈ 11~12 字/40vp 的会话卡一行可容 15 字上下，留余量给状态位）
export const SNIPPET_MAX_LEN: number = 60;

// 清洗：把 markdown 正文压成一句可读纯文本。规则顺序有讲究——先删代码块与图片（整段无意义），
// 再留链接文字、去行首标记、去强调符号，最后压平空白并截断。
export function cleanSnippet(raw: string, maxLen: number): string {
  if (raw === '') {
    return '';
  }
  let text: string = raw;
  // 围栏代码块（含语言标记与内容）——摘要里给代码没意义，整段吞掉
  text = text.replace(/```[\s\S]*?(```|$)/g, ' ');
  // 图片整段去（alt 与地址都不是人读的）
  text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, ' ');
  // 链接只留文字
  text = text.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
  // 行首标记：标题井号 / 引用 / 列表符 / 有序列表（多行模式）
  text = text.replace(/^[ \t]{0,3}(#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+|\d+[.)][ \t]+)/gm, '');
  // 行内代码去反引号留内容
  text = text.replace(/`([^`]*)`/g, '$1');
  // 强调符号（粗体 / 斜体 / 删除线）
  text = text.replace(/[*_~]{1,3}/g, '');
  // 残留 HTML 标签（模型偶尔回 <br> / <p>）
  text = text.replace(/<[^>]{1,40}>/g, ' ');
  // 压平所有空白（含换行）成单空格
  text = text.replace(/\s+/g, ' ').trim();
  if (text.length <= maxLen) {
    return text;
  }
  // 截断点恰落代理对高位半区（emoji 等增补平面字符前半）时退一位——substring 按 UTF-16 单元
  // 切，硬切会把代理对劈开，摘要末尾渲染成 U+FFFD 破字符
  const tail: number = text.charCodeAt(maxLen - 1);
  const cut: number = (tail >= 0xD800 && tail <= 0xDBFF) ? maxLen - 1 : maxLen;
  return text.substring(0, cut) + '…';
}

// 批量取摘要（key = conversationId，value = 已清洗的一句）。assistantIds = 当前助手过滤集
//（historyFilterIds 单源；默认助手含 '' 存量行），传纯数组（Rdb 绑参不接收观察代理）。DB 未
// 就绪时抛错，调用侧已有 whenReady 守卫语义（与 queryConversations 同链）。
// ★ 查询收窄（2026-11-16，见文件头）：外层限定当前助手，内层逐会话 MAX(seq) 走 seq 索引。
export async function queryConversationSnippets(assistantIds: string[]): Promise<Map<string, string>> {
  const out: Map<string, string> = new Map<string, string>();
  // 空集防御：IN () 是非法 SQL（产品调用方 historyFilterIds 恒非空，此处只防未来误用）
  if (assistantIds.length === 0) {
    return out;
  }
  const marks: string = assistantIds.map((): string => '?').join(',');
  const sql: string = 'SELECT c.id AS cid, ' +
    '(SELECT substr(m.content, 1, 240) FROM messages m ' +
    'WHERE m.conversationId = c.id ' +
    "AND m.role IN ('user','assistant') " +
    'AND m.seq = (SELECT MAX(seq) FROM messages m2 ' +
    "WHERE m2.conversationId = c.id AND m2.role IN ('user','assistant')) " +
    'LIMIT 1) AS c ' +
    'FROM conversations c WHERE c.assistantId IN (' + marks + ')';
  const rs: relationalStore.ResultSet = await sharedRdbStore().querySql(sql, assistantIds);
  try {
    const cidIndex: number = rs.getColumnIndex('cid');
    const contentIndex: number = rs.getColumnIndex('c');
    while (rs.goToNextRow()) {
      // 无 user/assistant 消息（含 seq 全 NULL 的老行）时子查询为 NULL——不出摘要
      if (rs.isColumnNull(contentIndex)) {
        continue;
      }
      const cid: string = rs.getString(cidIndex);
      const cleaned: string = cleanSnippet(rs.getString(contentIndex), SNIPPET_MAX_LEN);
      if (cleaned !== '') {
        out.set(cid, cleaned);
      }
    }
  } finally {
    rs.close();
  }
  return out;
}
