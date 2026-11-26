// HTTP 请求模板存储（DB v46 → v47 新表 http_templates——CRUD 域级单源在本件；建表 SQL
// 常量归位 ChatDbSchema：全仓建表 SQL 单一来源 + 避环——本件 ← ChatDbMigrate 会成
// ChatDb → ChatDbMigrate → 本件 → ChatDb 环，MIGRATE_ASSISTANT 常量先例同判据）。写事务
// 一律经 runWriteQueued 全局写串行链（新增写事务不入链即红——store-write-chain 断言守）。
// 表语义：
// · name = 用户起的显示名（可中文；同库唯一——定案②同名撞车 = 保存时就地拒绝，查重口
//   httpTemplateNameTaken 由 UI 在保存前调用，单写链下无竞态面）；
// · slug = 注册给模型的稳定工具名（定案③命名两分离：形如 tpl_<自增 id>，由 id 派生恒定
//   ——改名不改 slug、不注销重注册）；
// · url_template / body_template / headers_json 值内支持 {参数名} 占位（渲染纯函数在
//   HttpTemplate.assembleTemplateRequest）；headers_json = [{"name":"X","value":"..."}]
//   数组（值可含 {{凭据名称}} 引用记号，真值永不入库——同凭据库红线）；
// · params_json = 参数定义 [{"name":"city","position":"query|path|body|header",
//   "desc":"...","required":true}]（生成模型面 schema 的唯一来源）。
import { relationalStore } from '@kit.ArkData';
import { runWriteQueued } from './DbWriteQueue';
import { sharedRdbStore } from './ChatDb';

// 模板条数上限（数值授权执行笔按既有闸风格定：工具声明面每个模板一条定义，20 条 × 参数
// schema 已使声明面可观；条满后 UI 拒绝新建并提示）
export const HTTP_TEMPLATES_MAX: number = 20;
// 显示名字符上限（照 KNOWLEDGE_TITLE_MAX 档风格；名称会出现在对话工具卡标题）
export const HTTP_TEMPLATE_NAME_MAX_CHARS: number = 30;
// 单模板参数数上限（重发编辑面板按参数逐个出输入框，6 个以内对话框可承载）
export const HTTP_TEMPLATE_PARAMS_MAX: number = 6;

// 模板行（读侧形态；headers/params 保持 JSON 原串——解析在域件 HttpTemplate，存储层零业务知识）
export interface HttpTemplateRow {
  id: number;
  name: string;
  slug: string;
  method: string;
  urlTemplate: string;
  headersJson: string;
  bodyTemplate: string;
  paramsJson: string;
  createdAt: number;
  updatedAt: number;
}

// 写入形态（id/时间戳/slug 由存储层派生，调用方不给）
export interface HttpTemplateInput {
  name: string;
  method: string;
  urlTemplate: string;
  headersJson: string;
  bodyTemplate: string;
  paramsJson: string;
}

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

function rowOf(result: relationalStore.ResultSet): HttpTemplateRow {
  return {
    id: result.getLong(result.getColumnIndex('id')),
    name: result.getString(result.getColumnIndex('name')),
    slug: result.getString(result.getColumnIndex('slug')),
    method: result.getString(result.getColumnIndex('method')),
    urlTemplate: result.getString(result.getColumnIndex('url_template')),
    headersJson: result.getString(result.getColumnIndex('headers_json')),
    bodyTemplate: result.getString(result.getColumnIndex('body_template')),
    paramsJson: result.getString(result.getColumnIndex('params_json')),
    createdAt: result.getLong(result.getColumnIndex('created_at')),
    updatedAt: result.getLong(result.getColumnIndex('updated_at'))
  };
}

// 全量模板（注册同步与管理页列表共用；id 升序 = 创建序稳定）
export async function queryHttpTemplates(): Promise<HttpTemplateRow[]> {
  const rows: HttpTemplateRow[] = [];
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT * FROM http_templates ORDER BY id ASC');
  try {
    while (result.goToNextRow()) {
      rows.push(rowOf(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

export async function countHttpTemplates(): Promise<number> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COUNT(*) AS n FROM http_templates');
  let n: number = 0;
  try {
    if (result.goToNextRow()) {
      n = result.getLong(result.getColumnIndex('n'));
    }
  } finally {
    result.close();
  }
  return n;
}

// 显示名查重（定案②「同名撞车 = 就地拒绝」的判据口；UI 保存前调用给中文提示）
export async function httpTemplateNameTaken(name: string): Promise<boolean> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COUNT(*) AS n FROM http_templates WHERE name = ?',
      [name]);
  let n: number = 0;
  try {
    if (result.goToNextRow()) {
      n = result.getLong(result.getColumnIndex('n'));
    }
  } finally {
    result.close();
  }
  return n > 0;
}

// 按 id 查单件（模板执行器运行时现查——模板改名/改参即时生效，不闭包旧数据；查无 =
// 模板已被删除，执行器给中文错误回执）。★ 按 id 而非 slug 列查的原因（F2）：insert 先落
// slug='' 行、同写链任务内二次 update 回填 slug——两语句间进程被杀会留 slug='' 残留行，
// 而注册面三处都按「slug 空则 tpl_<id> 兜底派生」注册，按 slug 列精确查将永远查不到该行
//（执行器报「已删除」、编辑页载入落空），数据与功能永久分叉；id 主键恒在，残留行经 id 查询
// 两侧同源。slug 派生 id 的纯函数 = HttpTemplate.templateIdOfSlug
export async function queryHttpTemplateById(id: number): Promise<HttpTemplateRow | null> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT * FROM http_templates WHERE id = ? LIMIT 1', [id]);
  try {
    if (result.goToNextRow()) {
      return rowOf(result);
    }
  } finally {
    result.close();
  }
  return null;
}

// 新建（slug = tpl_<自增 id>，insert 拿 id 后同写单元内回填——定案③改名不改 slug 的恒定
// 基础）。返回新行 id；条满抛错（UI 先查 count 给中文提示，此处为绕过 UI 的兜底）
export async function insertHttpTemplate(input: HttpTemplateInput): Promise<number> {
  return runWriteQueued('insertHttpTemplate', async (): Promise<number> => {
    const count: relationalStore.ResultSet =
      await requireStore().querySql('SELECT COUNT(*) AS n FROM http_templates');
    let n: number = 0;
    try {
      if (count.goToNextRow()) {
        n = count.getLong(count.getColumnIndex('n'));
      }
    } finally {
      count.close();
    }
    if (n >= HTTP_TEMPLATES_MAX) {
      throw new Error('HTTP_TEMPLATES_FULL');
    }
    const now: number = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'name': input.name,
      'slug': '',
      'method': input.method,
      'url_template': input.urlTemplate,
      'headers_json': input.headersJson,
      'body_template': input.bodyTemplate,
      'params_json': input.paramsJson,
      'created_at': now,
      'updated_at': now
    };
    // rowId 直取官方 insert 返回值（H3-4）：原先丢弃返回值再发 SELECT last_insert_rowid()
    // 查询——全仓孤例写法，正确性依赖「写串行链内无任何他表 insert 落在 insert 与查询之间」
    // 的全局纪律。官方契约（relationalStore.d.ts）= 成功回 rowId、失败回 -1：-1 时 update
    // 落空、slug 留 ''，由 id 主键兜底派生注册（F2 同链），行为面不劣于错值形态
    const newId: number = await requireStore().insert('http_templates', bucket);
    const slugBucket: relationalStore.ValuesBucket = { 'slug': 'tpl_' + newId };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('http_templates');
    predicates.equalTo('id', newId);
    await requireStore().update(slugBucket, predicates);
    return newId;
  });
}

// 更新（name/method/url/headers/body/params 可改；slug 与 created_at 恒不动——定案③）
export async function updateHttpTemplate(id: number, input: HttpTemplateInput): Promise<void> {
  await runWriteQueued('updateHttpTemplate', async (): Promise<void> => {
    const bucket: relationalStore.ValuesBucket = {
      'name': input.name,
      'method': input.method,
      'url_template': input.urlTemplate,
      'headers_json': input.headersJson,
      'body_template': input.bodyTemplate,
      'params_json': input.paramsJson,
      'updated_at': Date.now()
    };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('http_templates');
    predicates.equalTo('id', id);
    await requireStore().update(bucket, predicates);
  });
}

// 删除（动态注册同步由调用方随后 syncTemplateTools 收口——本件零注册表知识）
export async function deleteHttpTemplate(id: number): Promise<void> {
  await runWriteQueued('deleteHttpTemplate', async (): Promise<void> => {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('http_templates');
    predicates.equalTo('id', id);
    await requireStore().delete(predicates);
  });
}
