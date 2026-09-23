// 消息多版本存储域件（DB v36，2026-09-20 消息重新生成·多版本保留；域级最小拆分自
// ChatDb.ets 迁出——ChatDb 本笔越 1200 硬线，本笔新增的多版本读写口整域外迁，照
// AttachmentDb.ets 域件先例：sharedRdbStore 句柄 + 域函数，库单源初始化在 ChatDb）。
// 语义总纲 = ChatDbMigrate.ets v36 版本注释：messages 表双列（variants 全量真源 JSON +
// variant_active 选中下标）；**content 列恒存选中版内容（投影设计）**——现役全部读方
//（回放/搜索/统计/get_chats/导出）查 content 本来就是选中版，零改动；variants 列只被
// 本域件与 ChatSendCtrl 重试链/ChatDataSource 回放装配（经 parseMessageVariants）消费。
// 消费方：ChatSendCtrl（重试基线与收尾）/ ChatToolRoundCtrl（中间收尾带版本）/
// ChatRetryCtrl（切换换版）/ ChatDataSource 与 ChatPageLoad（回放装配）。行类型
// MessageRow 的 variants/variantActive 两投影字段定义留 ChatDb（行类型本体）。
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore } from './ChatDb';

// 消息多版本结构（序列化/解析单源 = 本文件 parseMessageVariants /
// serializeMessageVariants）：content 与 reasoning 为该版全文；tokens/completion/
// durationMs/cached = 该版自己的用量快照（重试各版独立消耗如实各记，气泡 meta 与切换后
// 的显示随版本走；无用量协议全 0）；firstTokenMs = 该版首字耗时毫秒（2026-09-23 首字耗时
// 笔，与 durationMs 同为该版自己的值；0 = 该版未产出正文/思考增量或为升级前的老变体）
export interface MessageVariant {
  content: string;
  reasoning: string;
  tokens: number;
  completion: number;
  durationMs: number;
  cached: number;
  firstTokenMs: number;
}

// 多版本 JSON 解析（'' / 坏数据 / 非数组回 []——容错不炸回放；usage 五键缺省 0；坏版本
// 跳过保住其余版本）。★ firstTokenMs 缺省 0 即「该版不显示首字耗时」——升级前写下的老
// 变体 JSON 天然无此键，解析落 0 与「该版确无首字」同形，展示侧一律不显示（诚实的缺失）
export function parseMessageVariants(json: string): MessageVariant[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const list: MessageVariant[] = [];
  for (const item of raw) {
    const rec = item as Record<string, Object>;
    if (typeof rec['content'] !== 'string') {
      continue; // 坏版本跳过（保住其余版本）
    }
    list.push({
      content: rec['content'] as string,
      reasoning: typeof rec['reasoning'] === 'string' ? rec['reasoning'] as string : '',
      tokens: typeof rec['tokens'] === 'number' ? rec['tokens'] as number : 0,
      completion: typeof rec['completion'] === 'number' ? rec['completion'] as number : 0,
      durationMs: typeof rec['durationMs'] === 'number' ? rec['durationMs'] as number : 0,
      cached: typeof rec['cached'] === 'number' ? rec['cached'] as number : 0,
      firstTokenMs: typeof rec['firstTokenMs'] === 'number' ? rec['firstTokenMs'] as number : 0
    });
  }
  return list;
}

// 多版本 JSON 序列化（数组态直序列化；调用方保证 ≥1 版才落库——'' 恒代表单版）
export function serializeMessageVariants(list: MessageVariant[]): string {
  return JSON.stringify(list);
}

// 多版本行快照（重试基线构建与切换换版共用的读口）
export interface MessageVariantRow {
  content: string;
  reasoning: string;
  status: string;
  variants: string;
  active: number;
}

// 按 id 读多版本五字段（行不存在回 null——调用方守卫；重试链与切换链两消费方）
export async function queryMessageVariantRow(id: string): Promise<MessageVariantRow | null> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates,
    ['content', 'reasoning', 'status', 'variants', 'variant_active']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return {
        content: result.getString(result.getColumnIndex('content')),
        reasoning: result.getString(result.getColumnIndex('reasoning')),
        status: result.getString(result.getColumnIndex('status')),
        variants: result.getString(result.getColumnIndex('variants')),
        active: result.getLong(result.getColumnIndex('variant_active'))
      };
    }
    return null;
  } finally {
    result.close();
  }
}

// 多版本收尾落库（重试链专用 finalizeMessage 五列版）：content/reasoning/status 三列
// 与 ChatDb.finalizeMessage 同义（新终态 = 最新版即选中版），外加 variants 全量与
// variant_active 两列同条 UPDATE 原子落库（防「content 已换、active 未换」中间态）。
// 调用点两处——finishStream 重试收尾（终版）与 settleRoundAssistant 工具轮中间收尾
//（半截版，保旧答案在 variants[0] 不被覆盖丢失）
export async function finalizeMessageVariant(id: string, content: string, reasoning: string,
  status: string, variants: string, active: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'content': content,
    'reasoning': reasoning,
    'status': status,
    'variants': variants,
    'variant_active': active
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  predicates.equalTo('id', id);
  await sharedRdbStore().update(bucket, predicates);
}

// 切换换版（底栏 ‹ i/N › 切换键）：content/reasoning 投影随 variant_active 同条 UPDATE
// 换到目标版（variants 全量真源不动）；不动 status 与 createdAt（版本切换不改行生命周期）
export async function switchMessageVariant(id: string, content: string, reasoning: string,
  active: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'content': content,
    'reasoning': reasoning,
    'variant_active': active
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  predicates.equalTo('id', id);
  await sharedRdbStore().update(bucket, predicates);
}
