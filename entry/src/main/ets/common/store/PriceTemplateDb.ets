// 价格模板存储域（2026-09-11 价格模板，任务书-价格模板-20260911；照 PromptTemplateDb
// 域形态新建）：price_templates 表 CRUD（表结构/迁移在 ChatDbMigrate v28）。
// 模板 = 服务商级价格模板（一行一套 serializePriceConfig 产出的价格 JSON 串原文——
// 结构与解析单源 = CostStatsCalc，本层透传不解析不校验：保存链已保证入库前草稿
// complete，坏 JSON 不可能经本层落库）；随服务商删除事务级联清理（ProviderDb
// .deleteProvider）。
// ★ 校验分工（口径⑤「两端拦截 + 一层兜底」，与 PromptTemplateDb「名称全交调用侧」略异）：
// 名称非空/trim/同服务商查重由调用侧保证（PromptTemplateDb 同款）；上限则两端都判——
// 调用侧拦（条卡键置灰、列表页 push 前 toast）＝体验，insertTemplate 先查行数达
// PRICE_TEMPLATE_MAX 即 throw ＝数据有界红线的独立兜底（防将来键形制改动穿透）。
// ★ 不进任何导出/迁移路径（决明 2026-09-11 拍板③④：服务商「配置迁移」与「数据与同步」
// 全量导出/导入都不带模板）——技术债务登记见 docs/变更记录.md 三百九十五节。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, sharedRdbStore } from './ChatDb';

// 模板套数上限（每服务商；单源常量——条卡置灰、列表页拦截、insertTemplate 兜底三处
// 引用，禁字面量。VALLEY_SEGMENT_MAX 同款纪律）
export const PRICE_TEMPLATE_MAX: number = 20;
// 模板名称长度上限（命名弹窗与编辑页 TextInput maxLength 同值引用）
export const PRICE_TEMPLATE_NAME_MAX: number = 50;

export interface PriceTemplateRow {
  id: string;
  providerId: string;
  name: string;
  priceConfig: string;
  createdAt: number;
}

// 某服务商的模板清单（创建先后序；行数 ≤ PRICE_TEMPLATE_MAX 有界，无索引全表扫——
// 建表注释「有意为之」）
export async function queryTemplatesByProvider(providerId: string): Promise<PriceTemplateRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('price_templates');
  predicates.equalTo('providerId', providerId);
  predicates.orderByAsc('createdAt');
  const columns: string[] = ['id', 'providerId', 'name', 'priceConfig', 'createdAt'];
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, columns);
  const rows: PriceTemplateRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        name: result.getString(result.getColumnIndex('name')),
        priceConfig: result.getString(result.getColumnIndex('priceConfig')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 新增模板（名称非空由调用侧校验；返回新建行——调用侧重拉 chips 用）。★ 兜底：先查该
// 服务商现有行数，达 PRICE_TEMPLATE_MAX 即 throw（调用侧键置灰/拦截之外的独立防线，
// P0-1 数据有界不静默）
export async function insertTemplate(providerId: string, name: string,
  priceConfig: string): Promise<PriceTemplateRow> {
  const existing: PriceTemplateRow[] = await queryTemplatesByProvider(providerId);
  if (existing.length >= PRICE_TEMPLATE_MAX) {
    throw new Error('该服务商价格模板已达上限 ' + PRICE_TEMPLATE_MAX + ' 套，删除后可再添加');
  }
  const row: PriceTemplateRow = {
    id: nextMessageId('ptpl'),
    providerId: providerId,
    name: name,
    priceConfig: priceConfig,
    createdAt: Date.now()
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'providerId': row.providerId, 'name': row.name,
    'priceConfig': row.priceConfig, 'createdAt': row.createdAt
  };
  await sharedRdbStore().insert('price_templates', bucket);
  return row;
}

// 更新模板（名称/价格 JSON；名称编辑不改 createdAt）。★ 0 行 throw = P0-1 防「假成功」
//（updateTemplate 提示词同款：原生 update 静默 0 行，调用方 toast「已保存」即假成功）；
// 编辑改名查重排除自身 id 在调用侧（ModelEditPage.save 同口径）
export async function updateTemplate(id: string, name: string,
  priceConfig: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'name': name, 'priceConfig': priceConfig
  };
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('price_templates');
  predicates.equalTo('id', id);
  const affected: number = await sharedRdbStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标价格模板行不存在（已被删除），保存未生效');
  }
}

// 删除模板（编辑页底部删除键 → ConfirmDialog 确认后调用；行不在 = 静默成功——删除是
// 幂等目标态，与删除不存在的行同结果）
export async function deleteTemplate(id: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('price_templates');
  predicates.equalTo('id', id);
  await sharedRdbStore().delete(predicates);
}
