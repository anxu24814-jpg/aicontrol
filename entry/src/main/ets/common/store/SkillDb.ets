// 技能存储域：skills / skill_files 两表行读写 + 删技能联动清列 + 库页刷新广播（表结构/迁移
// 在 ChatDbMigrate v30）。一行一件技能：name **不设唯一约束**（定位按 trim 逐字相等三态，
// 多命中拒歧义——重名是「可保存但调用歧义」的弱约束）；description = 触发描述（进系统提示词
// 清单）；content = 正文（经 use_skill 工具结果通道进模型面，永不进 system）；source =
// 'user' | 'builtin'（insertSkill 恒写 'user'；'builtin' = seed 专用，直插绕开 insertSkill
// 才能写入，禁删禁改双守卫见 updateSkill/deleteSkill 首行）；sortOrder = 卡片自定义序（列表
// 序与清单选取序同源，新条目 max+1 落卡底）。
// ★ icon 列墓碑（2026-11-02 决明拍板「去掉技能库自定义图标」）：建表 SQL 的 icon 列与存量行
// 值**保留不动**（免表重建迁移），读写全撤——本域不再 SELECT/INSERT/UPDATE 该列，新行落
// SQL DEFAULT 值；复活 = 契约改判须拍板，防回流钉在 assert-skill-domain。
// · 有界红线：库内 ≤ SKILL_TOTAL_MAX 条（insert 超限拒绝——本域自带守卫，因技能有两个
//   写入口，各自拦一次 = 两处漂移面）；skill_files 一行一件纯文本附件（件名在本技能内查重
//   ——件名是模型取件的唯一定位键；每技能 ≤ SKILL_FILE_MAX_COUNT 件、单件 ≤
//   SKILL_FILE_CONTENT_MAX 字），删技能同事务级联删件（技能与附件同生共死，不留孤儿行）。
// · 删技能联动清列（拍板：删除联动清列 + 读取过滤双保险）：skills 是 JSON 串列、「是否含
//   该 id」谓词无法下推 SQL——只能全表读出逐行判、**仅命中行回写**（未命中的助手零写入）。
// · 导出导入 = ExportImport EXPORT_TABLES 含 skills / skill_files（列过滤天然跨版本兼容）；
//   纪元键 SKILL_LIST_TICK_KEY：写点 = 本域增删改收口，读点 = 技能库页 @StorageProp @Watch
//  （助手技能页不挂本键——它读 assistants.skills 列，进页取一次，两模式均无库页入口无
//   「先读后写」差）。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { runWriteQueued } from './DbWriteQueue';
import { parseEnabledSkillIds, serializeEnabledSkillIds, SKILL_CONTENT_MAX, SKILL_DESC_MAX,
  SKILL_ENABLED_MAX, SKILL_FILE_CONTENT_MAX, SKILL_FILE_MAX_COUNT,
  SKILL_NAME_MAX, SKILL_TOTAL_MAX } from '../SkillText';
import { SkillBuiltinDef, SKILL_BUILTIN_DEFS, SKILL_BUILTIN_GENERATION,
  SKILL_BUILTIN_SEEDED_KEY, SKILL_PENDING_JOIN_KEY } from '../SkillBuiltinDefs';
import { ASSISTANT_DEFAULT_ID, ensureDefaultAssistant } from './AssistantDb';

// hilog 常量（升代迁移的跳过留痕用）
const DOMAIN: number = 0xD5A4;
const TAG: string = 'SkillDb';

// 技能列表刷新广播键（AppStorage tick 递增；写点 = 本域增删改，读点 = 技能库页 @Watch 重拉）
export const SKILL_LIST_TICK_KEY: string = 'skillListTick';

// 库满拒绝文案（单一来源：库页「＋新建」与编辑页保存两处拦截同句）
export const SKILL_FULL_TIP: string = '技能库已达 ' + SKILL_TOTAL_MAX +
  ' 个上限，无法再新增。请先删除不再需要的技能。';

export interface SkillRow {
  id: string;
  name: string;
  description: string;
  content: string;
  source: string; // 'user' | 'builtin'
  createdAt: number;
  updatedAt: number;
  sortOrder: number; // 卡片自定义序（列表序与清单选取序同源）
}

// 新增/更新入参（校验归位在纯函数层 validateSkillArgs 完成后传入，本域只存取不二次判定）
export interface SkillInput {
  name: string;
  description: string;
  content: string;
}

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

// icon 列不入清单（墓碑，见文件头）——SELECT 显式列名，多列会再建读路径
const SKILL_COLUMNS: string[] = ['id', 'name', 'description', 'content', 'source',
  'createdAt', 'updatedAt', 'sortOrder'];

function readSkillRow(result: relationalStore.ResultSet): SkillRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    name: result.getString(result.getColumnIndex('name')),
    description: result.getString(result.getColumnIndex('description')),
    content: result.getString(result.getColumnIndex('content')),
    source: result.getString(result.getColumnIndex('source')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
  };
}

// 全量技能（卡片序）。三键排序：sortOrder → createdAt → name 升序——后两键 = 并列条目确定性
// 兜底（双键并列时 SQL 返回序不定，第三键消并发插入的并列窗口）；上限 50 条自然有界无翻页
export async function querySkills(): Promise<SkillRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skills');
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  predicates.orderByAsc('name');
  const result: relationalStore.ResultSet = await requireStore().query(predicates, SKILL_COLUMNS);
  const rows: SkillRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readSkillRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 库内总条数（上限守卫用；COUNT 直查不拉行）
export async function countSkills(): Promise<number> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COUNT(*) AS n FROM skills');
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 单件技能（编辑页回填与 use_skill 取正文用；查不到返回 null——调用方按不存在兜底提示）
export async function querySkill(id: string): Promise<SkillRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skills');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, SKILL_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readSkillRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// 新增单件（上限守卫在本域：达上限抛错 + SKILL_FULL_TIP，两写入口共用一份判定）。
// sortOrder = max+1 落卡底；COALESCE 显式兜底空表（不赌 MAX 空表 NULL 的未文档化读取行为）
export async function insertSkill(input: SkillInput): Promise<SkillRow> {
  const count: number = await countSkills();
  if (count >= SKILL_TOTAL_MAX) {
    throw new Error(SKILL_FULL_TIP);
  }
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COALESCE(MAX(sortOrder), 0) AS m FROM skills');
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const row: SkillRow = {
    id: nextMessageId('skill'),
    name: input.name,
    description: input.description,
    content: input.content,
    source: 'user',
    createdAt: now,
    updatedAt: now,
    sortOrder: nextOrder
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'description': row.description,
    'content': row.content, 'source': row.source, 'createdAt': row.createdAt,
    'updatedAt': row.updatedAt, 'sortOrder': row.sortOrder
  };
  await requireStore().insert('skills', bucket);
  broadcastSkillList();
  return row;
}

// 内置行删改守卫（source='builtin' 判定，比固定 id 判定更耐将来多内置条；本域失败口径 =
// throw 中文、调用方 toast）。★ 理由 = 复活循环红线——「可删除 + 下次启动重播 seed」会让
// 删了又回来的行为循环（真机实锤同族），故内置行禁删禁改，不做「删了重播」。UI 与工具链路
// 都过这两函数 = 双入口同闸；导入链（ExportImport 直拼 SQL 不走本域 CRUD）天然绕过守卫 =
// 备份往返含 builtin 行的预期行为，无需豁免分支
async function assertSkillNotBuiltin(id: string, tip: string): Promise<void> {
  const row: SkillRow | null = await querySkill(id);
  if (row !== null && row.source === 'builtin') {
    throw new Error(tip);
  }
}

// 更新单件（编辑页保存；sortOrder 不动 = 卡序原地，updatedAt 仅刷新为数据字段）。
// 0 行 throw = P0-1 假成功防御（行已删时调用方 toast「已保存」= 撒谎）
export async function updateSkill(id: string, input: SkillInput): Promise<void> {
  await assertSkillNotBuiltin(id, '内置技能不可修改');
  const bucket: relationalStore.ValuesBucket = {
    'name': input.name, 'description': input.description,
    'content': input.content, 'updatedAt': Date.now()
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skills');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标技能不存在（已被删除），保存未生效');
  }
  broadcastSkillList();
}

// 删除单件（技能库页删除键 → 确认弹窗后）：同一事务内 = 删技能行 + **级联删附件件** +
// 联动清各助手 skills 列引用（清列是主通道——悬空 id 会让「已启用 N 个」计数越用越不准，
// 读取过滤是第二道保险）。附件级联：skill_files 行以 skillId 指向技能，纳入同一事务
//「同生共死」不产半删态
export async function deleteSkill(id: string): Promise<void> {
  await assertSkillNotBuiltin(id, '内置技能不可删除');
  // 写串行链入链（广播在链节外 = await 之后即 commit 之后，时序不变；clearAllMemories 的
  //「广播在链节内」不同位，勿互抄）
  await runWriteQueued('deleteSkill', async (): Promise<void> => {
    const db: relationalStore.RdbStore = requireStore();
    db.beginTransaction();
    try {
      const filePredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('skill_files');
      filePredicates.equalTo('skillId', id);
      await db.delete(filePredicates);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skills');
      predicates.equalTo('id', id);
      await db.delete(predicates);
      await clearSkillRefInAssistants(db, id);
      db.commit();
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
  broadcastSkillList();
}

// ── 附件文件（skill_files）──
// 一行一件纯文本附件。写入口径与 skills 表同款（不设唯一约束的弱约束 + 定位三态），但
// **件名在本技能内查重**：件名是模型取件的唯一定位键（use_skill 的 file 参数），同名两件
// 会让「取到哪一份」不可预期——写入侧硬拒。上限与内容上限同 SkillText 常量单源

export const SKILL_FILE_FULL_TIP: string = '每个技能最多附 ' + SKILL_FILE_MAX_COUNT +
  ' 个文件，请先删除不再需要的文件。';

export interface SkillFileRow {
  id: string;
  skillId: string;
  name: string;
  content: string;
  sortOrder: number;
  createdAt: number;
}

const SKILL_FILE_COLUMNS: string[] = ['id', 'skillId', 'name', 'content', 'sortOrder',
  'createdAt'];

function readSkillFileRow(result: relationalStore.ResultSet): SkillFileRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    skillId: result.getString(result.getColumnIndex('skillId')),
    name: result.getString(result.getColumnIndex('name')),
    content: result.getString(result.getColumnIndex('content')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
    createdAt: result.getLong(result.getColumnIndex('createdAt'))
  };
}

// 某技能的全部附件（卡片序，两键确定性排序；每技能 ≤10 件自然有界无翻页）
export async function querySkillFiles(skillId: string): Promise<SkillFileRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skill_files');
  predicates.equalTo('skillId', skillId);
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('name');
  const result: relationalStore.ResultSet =
    await requireStore().query(predicates, SKILL_FILE_COLUMNS);
  const rows: SkillFileRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readSkillFileRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 单件附件（附件编辑页回填用；查不到返回 null，调用方按不存在兜底提示）
export async function querySkillFile(id: string): Promise<SkillFileRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skill_files');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet =
    await requireStore().query(predicates, SKILL_FILE_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readSkillFileRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// 新增附件（「新建文件」/「上传文件」入库）：先校验父技能仍在 → 内置行守卫 → 查同名
//（excludeId='' = 不排除自己）→ 件数上限 → sortOrder = 卡底。各处拒绝抛中文错由调用方
// toast（P0-1 不静默）。
// ★ 父技能校验必须**早于** assertSkillNotBuiltin：后者判据是「行存在且为内置」，技能行不
// 存在时静默通过——技能在文件编辑页打开期间被删即写入无父悬空行（此后没有任何删除链能清
// 掉），写入前拒。
// ★ 内置行守卫独立拦：附件写入不经 updateSkill，不拦则「技能保存被拦但附件照加」（改/删
// 附件两函数不拦——内置行无存量附件，无对象可操作）
export async function insertSkillFile(skillId: string, name: string,
  content: string): Promise<SkillFileRow> {
  const owner: SkillRow | null = await querySkill(skillId);
  if (owner === null) {
    throw new Error('技能不存在或已删除，保存未生效');
  }
  await assertSkillNotBuiltin(skillId, '内置技能不能添加附件');
  await assertFileNameFree(skillId, name, '');
  const count: number = await countSkillFiles(skillId);
  if (count >= SKILL_FILE_MAX_COUNT) {
    throw new Error(SKILL_FILE_FULL_TIP);
  }
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM skill_files WHERE skillId = ?', [skillId]);
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const row: SkillFileRow = {
    id: nextMessageId('skf'),
    skillId: skillId,
    name: name,
    content: content,
    sortOrder: nextOrder,
    createdAt: now
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'skillId': row.skillId, 'name': row.name, 'content': row.content,
    'sortOrder': row.sortOrder, 'createdAt': row.createdAt
  };
  await requireStore().insert('skill_files', bucket);
  return row;
}

// 修改附件（改内容或改名——改名同样查重，排除自己这条）。0 行 throw 同 updateSkill
export async function updateSkillFile(id: string, skillId: string, name: string,
  content: string): Promise<void> {
  await assertFileNameFree(skillId, name, id);
  const bucket: relationalStore.ValuesBucket = { 'name': name, 'content': content };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skill_files');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标文件不存在（已被删除），保存未生效');
  }
}

// 删除附件（文件组卡行内删除键）：只删这一行——**不影响助手启用清单**（助手启用的是技能
// 本身）
export async function deleteSkillFile(id: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skill_files');
  predicates.equalTo('id', id);
  await requireStore().delete(predicates);
}

// 件数（上限守卫 + 组卡计数用；COUNT 直查不拉行）
export async function countSkillFiles(skillId: string): Promise<number> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COUNT(*) AS n FROM skill_files WHERE skillId = ?', [skillId]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 同名件拒绝（写入侧硬约束；excludeId 用于「改名时排除自己」）：命中即抛中文错带件名——
// 用户知道该改哪一个，模型也永远拿不到歧义清单
async function assertFileNameFree(skillId: string, name: string,
  excludeId: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skill_files');
  predicates.equalTo('skillId', skillId);
  predicates.equalTo('name', name);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  let conflict: string = '';
  try {
    while (result.goToNextRow()) {
      const id: string = result.getString(result.getColumnIndex('id'));
      if (id !== excludeId) {
        conflict = id;
        break;
      }
    }
  } finally {
    result.close();
  }
  if (conflict !== '') {
    throw new Error('已有名为「' + name + '」的文件，请换个文件名');
  }
}

// 联动清列（调用方须在事务内调——本函数不自开事务，与删行同一原子单位）：全表读 (id,
// skills) → 逐行解析剔除目标 id → **仅命中行**回写（未命中不写）。JSON 列无法谓词下推，
// 只能全表遍历（助手小数据集代价可忽略）
async function clearSkillRefInAssistants(db: relationalStore.RdbStore,
  skillId: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  const result: relationalStore.ResultSet = await db.query(predicates, ['id', 'skills']);
  const targetIds: string[] = [];
  const targetValues: string[] = [];
  try {
    while (result.goToNextRow()) {
      const raw: string = result.getString(result.getColumnIndex('skills'));
      const ids: string[] = parseEnabledSkillIds(raw);
      if (!ids.includes(skillId)) {
        continue;
      }
      targetIds.push(result.getString(result.getColumnIndex('id')));
      targetValues.push(serializeEnabledSkillIds(ids.filter((item: string): boolean =>
        item !== skillId)));
    }
  } finally {
    result.close();
  }
  for (let i: number = 0; i < targetIds.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'skills': targetValues[i] };
    const update: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
    update.equalTo('id', targetIds[i]);
    await db.update(bucket, update);
  }
}

// 列表刷新广播（tick 递增——@Watch 对同值不触发，递增保证每次触发）
export function broadcastSkillList(): void {
  AppStorage.setOrCreate<number>(SKILL_LIST_TICK_KEY,
    (AppStorage.get<number>(SKILL_LIST_TICK_KEY) ?? 0) + 1);
}

// ── 内置技能 seed 与升代 ──
// 全部内置技能的 id/名称/描述/正文/autoEnable 唯一来源 = SkillBuiltinDefs.
// SKILL_BUILTIN_DEFS，本文件只保留持久化执行面，禁再出现第二条同义常量防双源漂移。
// · ① 逐条幂等插入：querySkill(固定 id) → null 才插（已存在零写入，updatedAt 不动），
//   每次启动调一次。★ 直插不走 insertSkill——其 source 写死 'user' 且带上限守卫与广播，
//   均非 seed 语义（不查 SKILL_TOTAL_MAX〔上限语义属用户写入口，库满计数已含 builtin 行〕、
//   不广播〔启动链先于 UI〕、source='builtin'、id 用定义常量）。
// · ② 升代迁移（SKILL_BUILTIN_SEEDED_KEY 代数标记，标记值 = 字符串数字，'' = 从未迁移）：
//   标记代数 < SKILL_BUILTIN_GENERATION 才执行，完成推进到当前代——内置内容修订随版本对
//   已装用户生效；标记 NaN 视为损坏落入重迁移自愈（全幂等）；标记超前（跨版本备份把新代
//   标记带进旧版）只升不降。迁移三件事：
//   a) 内置行按定义刷新（字段有变化才 UPDATE，内容未变的行不碰 updatedAt）；
//   b) sortOrder 一次性排前——内置若落卡底，清单预算紧张时最先被截出模型视野，故整组提到
//      用户行最小序之前（内置相对顺序 = 定义序；用户行最小序 COALESCE 回 1，内置落其前负
//      序段，未来用户行 max+1 永在内置之后）；
//   c) 默认助手启用 autoEnable 条自 D5-3 起移出本函数 = flushPendingAutoEnable（每次启动
//      都跑、不受标记门限）——不启用则内置技能对模型完全不可见 = 冷启动死库；只并**登记在
//      册**的条目（SKILL_PENDING_JOIN_KEY 只由 seed 新插路径写入——换机恢复时启用集随备份
//      还原，重并全量会翻案用户显式关闭），并入既有启用集保序 union，超 SKILL_ENABLED_MAX
//      整组跳过不部分加（登记保留下次补跑），控制台助手不掺与。
//   ★ 升代判据用代数比较而非恰等匹配：技能内置行被 assertSkillNotBuiltin 三写口锁死，
//   用户改不出「恰似旧代」的值，代数比较已充分。任一步抛错标记不写，下次启动重试。
//   ★ 启用步骤首步 await ensureDefaultAssistant() 兜行——默认助手行未就绪时启用更新会 0 行
//   生效却照推标记，启用永久丢失。
// · ③ 门闩：标记键经 PersistentStorage 持久（EntryAbility loadContent 回调注册），读前必须
//   等 builtinSeedKeyRegistered 放行——onCreate 迁移链尾早于 loadContent，无门闩会读到
//   AppStorage 缺省值误判代数。

// 内置 seed 标记键门闩（consoleToolsKeyRegistered 同款实现）
let releaseBuiltinSeedGate: (() => void) | null = null;
const builtinSeedKeyRegistered: Promise<void> = new Promise<void>(
  (resolve: () => void): void => {
    releaseBuiltinSeedGate = resolve;
  });

// EntryAbility 在标记键 persistProp 注册完成后调用（loadContent 回调 persistProp 区）
export function notifySkillSeedKeyRegistered(): void {
  if (releaseBuiltinSeedGate !== null) {
    releaseBuiltinSeedGate();
  }
}

async function insertBuiltinRow(def: SkillBuiltinDef): Promise<void> {
  const maxResult: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COALESCE(MAX(sortOrder), 0) AS m FROM skills');
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const now: number = Date.now();
  const bucket: relationalStore.ValuesBucket = {
    'id': def.id, 'name': def.name, 'description': def.description,
    'content': def.content, 'source': 'builtin',
    'createdAt': now, 'updatedAt': now, 'sortOrder': nextOrder
  };
  await requireStore().insert('skills', bucket);
}

// ── 待并入登记（键形态见 SkillBuiltinDefs.SKILL_PENDING_JOIN_KEY）──

// 登记读取：'' / 坏 JSON / 非数组一律回空表——本键是「补跑信号」不是数据真相，损坏退化为
//「无待并入」（零副作用：行不丢，仅自动启用不补）
function readPendingJoin(): string[] {
  const raw: string = AppStorage.get<string>(SKILL_PENDING_JOIN_KEY) ?? '';
  if (raw === '') {
    return [];
  }
  try {
    const parsed: Object = JSON.parse(raw) as Object;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const out: string[] = [];
    for (const item of parsed as Object[]) {
      if (typeof item === 'string' && item !== '') {
        out.push(item);
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

// 登记写回（AppStorage 写即经 persistProp 落盘；值恒为 JSON 数组串）
function writePendingJoin(ids: string[]): void {
  AppStorage.setOrCreate<string>(SKILL_PENDING_JOIN_KEY, JSON.stringify(ids));
}

// 自动并入（每次启动跑一次，登记为空即零开销；调用点 = ensureBuiltinSkills 内、标记门限
// 之前——超限跳过与抛错窗口的补跑不受「标记已推进」阻挡）：
// · 只并「登记在册 ∧ 未启用 ∧ autoEnable」——登记只由 seed 新插路径写入，恢复备份还原的
//   已存在行（用户显式关闭态）不在此列，不翻案（765 F1）；
// · 超 SKILL_ENABLED_MAX 整组跳过但登记保留——名额腾出后下次启动自动补跑；
// · 任一步抛错 = 登记不消费下次重试；并入成功才清登记（此后用户关闭不翻案——件已不在登记
//   面内）
async function flushPendingAutoEnable(): Promise<void> {
  const pending: string[] = readPendingJoin();
  if (pending.length === 0) {
    return;
  }
  // 默认助手行就绪前置：兜行失败直接抛（行未就绪时启用 0 行生效却照推标记 = 永久丢失）
  await ensureDefaultAssistant();
  const assistPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistants');
  assistPredicates.equalTo('id', ASSISTANT_DEFAULT_ID);
  const assistResult: relationalStore.ResultSet =
    await requireStore().query(assistPredicates, ['id', 'skills']);
  let rawSkills: string = '';
  try {
    if (assistResult.goToNextRow()) {
      rawSkills = assistResult.getString(assistResult.getColumnIndex('skills'));
    }
  } finally {
    assistResult.close();
  }
  const enabled: string[] = parseEnabledSkillIds(rawSkills);
  const missing: string[] = SKILL_BUILTIN_DEFS
    .filter((def: SkillBuiltinDef): boolean => def.autoEnable && !enabled.includes(def.id) &&
      pending.includes(def.id))
    .map((def: SkillBuiltinDef): string => def.id);
  if (missing.length === 0) {
    writePendingJoin([]); // 登记项均已定局（已启用 / 非 autoEnable 件）——清登记收口
    return;
  }
  if (enabled.length + missing.length > SKILL_ENABLED_MAX) {
    hilog.warn(DOMAIN, TAG, '内置技能默认启用跳过——默认助手启用集 ' + enabled.length +
      ' 件加 ' + missing.length + ' 件将超上限 ' + SKILL_ENABLED_MAX + '，待并入登记保留');
    return; // 整组跳过：部分加入会造出「只启用了一部分内置」的怪状态；登记保留下次补跑
  }
  const bucket: relationalStore.ValuesBucket = {
    'skills': serializeEnabledSkillIds(enabled.concat(missing))
  };
  const updatePredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistants');
  updatePredicates.equalTo('id', ASSISTANT_DEFAULT_ID);
  await requireStore().update(bucket, updatePredicates);
  writePendingJoin([]); // 并入成功才清登记——此后用户关闭不翻案
}

// 升代迁移两件事（内容刷新 / 排前），全幂等——抛错由调用方不推标记下次重试。默认助手启用
// 并入自 D5-3 起移出本函数（= flushPendingAutoEnable，每次启动都跑、不受标记门限）
async function migrateBuiltinGeneration(): Promise<void> {
  for (const def of SKILL_BUILTIN_DEFS) {
    const row: SkillRow | null = await querySkill(def.id);
    if (row !== null && (row.name !== def.name || row.description !== def.description ||
      row.content !== def.content)) {
      const bucket: relationalStore.ValuesBucket = {
        'name': def.name, 'description': def.description,
        'content': def.content, 'updatedAt': Date.now()
      };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('skills');
      predicates.equalTo('id', def.id);
      await requireStore().update(bucket, predicates);
    }
  }
  const minResult: relationalStore.ResultSet = await requireStore().querySql(
    "SELECT COALESCE(MIN(sortOrder), 1) AS m FROM skills WHERE source = 'user'");
  let userMin: number = 1;
  try {
    if (minResult.goToNextRow()) {
      userMin = minResult.getLong(minResult.getColumnIndex('m'));
    }
  } finally {
    minResult.close();
  }
  for (let i: number = 0; i < SKILL_BUILTIN_DEFS.length; i++) {
    const bucket: relationalStore.ValuesBucket = {
      'sortOrder': userMin - SKILL_BUILTIN_DEFS.length + i
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('skills');
    predicates.equalTo('id', SKILL_BUILTIN_DEFS[i].id);
    await requireStore().update(bucket, predicates);
  }
}

// 内置技能 seed 与升代（启动一次性幂等，失败下次启动重试；挂点 = EntryAbility 初始化链，
// DB 就绪后）。新插 id 先落进待并入登记（持久化）：自动并入只认登记在册条目，已存在的行
//（恢复备份还原）不重并不翻案用户显式关闭态；登记使「超限跳过 / 抛错」两窗口下次启动可补
export async function ensureBuiltinSkills(): Promise<void> {
  await builtinSeedKeyRegistered;
  const freshIds: string[] = [];
  for (const def of SKILL_BUILTIN_DEFS) {
    if (await querySkill(def.id) === null) {
      await insertBuiltinRow(def);
      freshIds.push(def.id);
    }
  }
  if (freshIds.length > 0) {
    // 先登记后其余步骤：登记落盘即幸存，后续任一步抛错下次启动凭它补并入
    const pending: string[] = readPendingJoin();
    for (const id of freshIds) {
      if (!pending.includes(id)) {
        pending.push(id);
      }
    }
    writePendingJoin(pending);
  }
  // 自动并入（登记为空即零开销；超限/抛错时登记保留下次补跑）
  await flushPendingAutoEnable();
  const mark: string = AppStorage.get<string>(SKILL_BUILTIN_SEEDED_KEY) ?? '';
  const markNum: number = mark === '' ? 0 : Number(mark);
  if (!Number.isNaN(markNum) && markNum >= SKILL_BUILTIN_GENERATION) {
    return; // 只升不降：标记不落后即零迁移，内置内容刷新只随代数推进发生
  }
  await migrateBuiltinGeneration();
  AppStorage.setOrCreate<string>(SKILL_BUILTIN_SEEDED_KEY, String(SKILL_BUILTIN_GENERATION));
}
