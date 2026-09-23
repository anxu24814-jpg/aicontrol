// manage_skills 管理族纯函数域（2026-09-16 技能管理工具笔，任务书-技能管理工具与加载枚举
// -20260916 §3.1.4；自 SkillText.ets 域级最小拆分——管理族并入使 SkillText 达 1235 行越
// 1200 硬线，宪法「>1200 硬线：先把本次改动所属的功能域拆到独立文件再动手」条款执行；
// MemoryText 承载 manage_memory 管理族同款分工）。
// · 职责一句话：manage_skills 工具的参数校验归位 / 改名判重定位 / list 索引回执 /
//   update 回执——全部纯逻辑，IO 编排在 ToolSkill。
// · import 单向：本域 → SkillText（manifestDesc 描述摘要截断与三上限常量与两类型——
//   工具面与清单面同口径 R-A5，禁第二份截断实现）；SkillText 不反向引用本域，无环
//  （坑50 模块环求值红线复核过：ToolSkill → {SkillText, SkillManageText} 两叶子，无环）。
// · 断言通道：本域带 import，不能像 SkillText 那样复制直跑——scripts/assert-app-domain.mjs
//   108 组照 75 组先例「剥 import + SkillText 源前置拼接」为单文件直跑（线上同一实现）。
// · 零 delete 语义（缺口盘点 C 档结论维持）：删除不可逆且绕过 UI 确认链，工具面不支持，
//   desc 与错误路径恒指引 设置 → 技能库 手动删。
import { SKILL_CONTENT_MAX, SKILL_DESC_MAX, SKILL_NAME_MAX,
  SkillBriefItem, SkillLocateOutcome, manifestDesc } from './SkillText';

// ── list 分页两档（任务书 §3.1.1）——默认 20 / 上限 30。30 的依据（实数推算，防回执被截）：
// 清单口径单行最坏 = 2 + 64（名）+ 1 + 120（描述摘要）+ 字数后缀 ≈ 190 字，30 行 ≈ 5.7K <
// clipToolResult 8192 钳位线；50 件全量最坏 ≈ 9.5K 必被截尾，故封顶 30 + 分页兜底
export const SKILL_MANAGE_LIST_DEFAULT_COUNT: number = 20;
export const SKILL_MANAGE_LIST_MAX_COUNT: number = 30;
// list 页内总字数软顶（composeManageSkillListReply 双条件姿势的字符侧——照 MemoryText
// MEMORY_MANAGE_PAGE_SOFT_CHARS 先例：超则自动收窄本页件数至少 1 件，防 clipToolResult
// 硬顶截尾丢翻页提示；描述摘要截 120 后单行最坏 ≈190 字，MAX_COUNT 内最坏 5.7K 不触发
// 此线——它是 MAX_COUNT 将来调大时的结构性兜底，双条件姿势与先例一致）
export const SKILL_MANAGE_LIST_PAGE_SOFT_CHARS: number = 6000;

// 管理校验结果（纯函数可断言）：ok = true 时 action 与对应参数就绪；offset/limit 为归一后值。
// name 在 get/update 是定位键、在 create 是新技能名；newName/description/content 仅 update
// 语义「传了才改」（空串 = 未传同义，合流在执行器层做）
export interface ManageSkillsValidation {
  ok: boolean;
  action: string;
  name: string;
  newName: string;
  description: string;
  content: string;
  offset: number;
  limit: number;
  error: string;
}

function rejectManageSkills(error: string): ManageSkillsValidation {
  return { ok: false, action: '', name: '', newName: '', description: '', content: '',
    offset: 1, limit: SKILL_MANAGE_LIST_DEFAULT_COUNT, error: error };
}

// 参数校验纯函数（照 validateManageMemoryArgs 形制）：坏 JSON / 非法 action / get·update·
// create 缺 name / update 三个改动字段（new_name、description、content）全空 / 三类上限越界
//（名称与改名目标超 SKILL_NAME_MAX、描述超 SKILL_DESC_MAX、正文超 SKILL_CONTENT_MAX）全拒，
// 中文报因；list 的 offset/limit 脏值归默认不报错（模型少一轮纠错）。
// · 不在此查 name 换行——create/update 链下游 validateSkillArgs 会拒（名称侧校验单源不破）；
//   get 的换行名 trim 逐字匹配必然 0 命中，走定位失败回执即自纠
// · description 可空（照 validateSkillArgs 口径——空描述 = 清单行只剩名字，合法形态）；
//   content 空串在 create 语义 = 未传，下游 validateSkillArgs 拒「技能正文不能为空」
export function validateManageSkillsArgs(argsJson: string): ManageSkillsValidation {
  let action: string = '';
  let name: string = '';
  let newName: string = '';
  let description: string = '';
  let content: string = '';
  let offset: number = 1;
  let limit: number = SKILL_MANAGE_LIST_DEFAULT_COUNT;
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawName: Object | undefined = parsed['name'];
    const rawNewName: Object | undefined = parsed['new_name'];
    const rawDesc: Object | undefined = parsed['description'];
    const rawContent: Object | undefined = parsed['content'];
    const rawOffset: Object | undefined = parsed['offset'];
    const rawLimit: Object | undefined = parsed['limit'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawName === 'string') {
      name = rawName.trim();
    }
    if (typeof rawNewName === 'string') {
      newName = rawNewName.trim();
    }
    if (typeof rawDesc === 'string') {
      description = rawDesc.trim();
    }
    if (typeof rawContent === 'string') {
      content = rawContent.trim();
    }
    if (typeof rawOffset === 'number' && Number.isInteger(rawOffset)) {
      offset = rawOffset;
    }
    if (typeof rawLimit === 'number' && Number.isInteger(rawLimit)) {
      limit = rawLimit;
    }
  } catch (e) {
    return rejectManageSkills('参数解析失败，需要 action 参数');
  }
  if (action !== 'list' && action !== 'get' && action !== 'create' && action !== 'update') {
    return rejectManageSkills('action 必须是 list、get、create 或 update');
  }
  if (offset < 1) {
    offset = 1;
  }
  if (limit < 1) {
    limit = SKILL_MANAGE_LIST_DEFAULT_COUNT;
  }
  if (limit > SKILL_MANAGE_LIST_MAX_COUNT) {
    limit = SKILL_MANAGE_LIST_MAX_COUNT;
  }
  if (action !== 'list' && name === '') {
    return rejectManageSkills(action === 'create' ?
      'action 为 create 时需要 name 参数，值为新技能的名称' :
      'action 为 ' + action + ' 时需要 name 参数，值为要操作的技能名称');
  }
  if (name.length > SKILL_NAME_MAX) {
    return rejectManageSkills('技能名称超过 ' + SKILL_NAME_MAX + ' 字上限，当前 ' +
      name.length + ' 字');
  }
  if (newName.length > SKILL_NAME_MAX) {
    return rejectManageSkills('新名称超过 ' + SKILL_NAME_MAX + ' 字上限，当前 ' +
      newName.length + ' 字');
  }
  if (description.length > SKILL_DESC_MAX) {
    return rejectManageSkills('触发描述超过 ' + SKILL_DESC_MAX + ' 字上限，当前 ' +
      description.length + ' 字');
  }
  if (content.length > SKILL_CONTENT_MAX) {
    return rejectManageSkills('技能正文超过 ' + SKILL_CONTENT_MAX + ' 字上限，当前 ' +
      content.length + ' 字');
  }
  if (action === 'update' && newName === '' && description === '' && content === '') {
    return rejectManageSkills('action 为 update 时需要 new_name、description、content 至少一项');
  }
  return { ok: true, action: action, name: name, newName: newName, description: description,
    content: content, offset: offset, limit: limit, error: '' };
}

// 技能名判重定位（排除自身 id）：照 locateSkillByName 同形，命中集里剔除 selfId——update
// 改名判重的专用口（R-A3：排除自身后「改成与自己相同的名字」不再被自己的名字判重命中，
// 该形态由执行器层「与原文相同」态接住）。多命中形态在本域正常不可达（locateSkillByName
// 已在改前拒歧义），保留三态完整语义与先例同形
export function locateSkillByNameExcluding(items: SkillBriefItem[], name: string,
  selfId: string): SkillLocateOutcome {
  const needle: string = name.trim();
  const hits: string[] = [];
  let hitId: string = '';
  let hitName: string = '';
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].id === selfId) {
      continue;
    }
    if (items[i].name.trim() === needle) {
      if (hitId === '') {
        hitId = items[i].id;
        hitName = items[i].name;
      }
      hits.push('[' + (i + 1).toString() + '] ' + items[i].name);
    }
  }
  if (hits.length === 0) {
    return { state: 'none', hitId: '', hitName: '', hits: [] };
  }
  if (hits.length > 1) {
    return { state: 'multi', hitId: '', hitName: '', hits: hits };
  }
  return { state: 'unique', hitId: hitId, hitName: hitName, hits: [] };
}

// 管理清单行形态（list 回执用——SkillBriefItem 加正文字数一列；不引 DB 类型，
// 执行器以 SkillRow 单点适配）
export interface SkillManageListItem {
  id: string;
  name: string;
  description: string;
  contentChars: number;
}

// list 索引回执（编号索引不是全文——[全库序号] 名称：描述摘要（正文 X 字））；分页与软顶
// 照 composeMemoryManageList 姿势：序号自 offset 起算全库连续（翻页不重编号）、offset 越过
// 末件收到末件（模型恒见内容不落空页）、软顶双条件（SKILL_MANAGE_LIST_MAX_COUNT 与字符预算
// 先到者收窄，至少 1 件）；描述摘要复用 manifestDesc 同一份截断（禁第二份实现）。不回显正文
// 全文（正文可 8000 字，索引回执会被 clipToolResult 切尾）
export function composeManageSkillListReply(items: SkillManageListItem[], offset: number,
  limit: number): string {
  const total: number = items.length;
  if (total === 0) {
    return '技能库为空。';
  }
  let start: number = offset < 1 ? 1 : offset;
  if (start > total) {
    start = total;
  }
  let count: number = limit < 1 ? SKILL_MANAGE_LIST_DEFAULT_COUNT : limit;
  if (count > SKILL_MANAGE_LIST_MAX_COUNT) {
    count = SKILL_MANAGE_LIST_MAX_COUNT;
  }
  const lines: string[] = [];
  let shown: number = 0;
  let used: number = 0;
  while (shown < count && start - 1 + shown < total) {
    const item: SkillManageListItem = items[start - 1 + shown];
    const line: string = '[' + (start + shown).toString() + '] ' + item.name + '：' +
      manifestDesc(item.description) + '（正文 ' + item.contentChars.toString() + ' 字）';
    if (shown > 0 && used + line.length > SKILL_MANAGE_LIST_PAGE_SOFT_CHARS) {
      break;
    }
    lines.push(line);
    used += line.length;
    shown++;
  }
  const lastShown: number = start - 1 + shown;
  const parts: string[] = ['共 ' + total + ' 件技能，序号为库内顺序。本页第 ' + start +
    '~' + lastShown + ' 件：'];
  parts.push(lines.join('\n'));
  if (shown < count && lastShown < total) {
    parts.push('本页因长度限制只显示前 ' + shown + ' 件');
  }
  if (lastShown < total) {
    parts.push('还有 ' + (total - lastShown) + ' 件，可用 offset=' + (lastShown + 1) + ' 继续');
  } else {
    parts.push('已到末尾');
  }
  parts.push('修改某件前先用 action=get 取该件当前全文，update 的 content 是整体替换。');
  return parts.join('\n');
}

// update 成功回执（列出改了哪些字段与正文字数变化，不回显正文全文——正文可 8000 字，
// 回显会被 clipToolResult 切尾；changed = 改动字段中文名数组，执行器按合流差异逐项收集）。
// 改名时头行带旧名指向（模型/用户都能对上「改的是哪一件」）
export function composeManageSkillUpdateReply(oldName: string, newName: string,
  changed: string[], beforeChars: number, afterChars: number): string {
  const renamed: boolean = oldName !== newName;
  const head: string = renamed ?
    '已修改技能「' + oldName + '」，新名称「' + newName + '」。' :
    '已修改技能「' + oldName + '」。';
  const parts: string[] = [head];
  parts.push('本次改动：' + changed.join('、') + '。');
  if (changed.includes('正文')) {
    parts.push('正文 ' + beforeChars.toString() + ' 字 → ' + afterChars.toString() + ' 字。');
  }
  parts.push('下次加载该技能即使用新版。');
  return parts.join('\n');
}
