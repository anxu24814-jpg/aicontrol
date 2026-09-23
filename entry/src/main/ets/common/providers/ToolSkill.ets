// 技能工具域（2026-09-13 技能层笔 1 起；2026-09-16 技能管理工具笔——第 17 件 create_skill
// 整体退役并入第 17 件 manage_skills，ToolPrompts 两工具先例）：第 16 件 use_skill +
// 第 17 件 manage_skills（list/get/create/update 四 action 管理类）的实现。
// ── use_skill（技能层笔 1，方案-技能层-20260913 §2.3）──
// 模型按系统提示词「可用技能」清单自主调用，把某件技能的正文（说明书
// 全文）作为工具结果读进上下文，然后按正文执行任务。
// · **模式驱动工具**（★ 与 search_memory 同为 MODE_DRIVEN_TOOLS 成员）：不走
//   assistants.tools 启用清单、不进助手工具页——声明与否由「该助手有没有启用技能」决定
//   （ChatSendCtrl 声明收集处按 assistants.skills ∩ 现存技能非空时追加）。理由与记忆工具
//   同族：工具页开关与「启用技能」开关会成为两处互相矛盾的真相互相打架。
// · **清单与声明同闸**（负向钉）：该助手零启用技能 = 不进 system 清单 + 不声明本工具，
//   请求与无技能版逐字节一致。
// · 校验/定位/回执纯逻辑全在 SkillText（零 import 直跑域，断言脚本复制直跑）；本文件只做
//   IO 编排：querySkills → 三态定位 → querySkill 取正文 → composeSkillReply。
// · 定位 = 技能名 trim 逐字相等（0 命中回「现有技能清单 + 逐字复制指引」，≥2 命中拒歧义）。
// · 恒 resolve 不 reject（ToolMemoryManage 同款外拆域件先例）：全部错误态走文本回执，
//   兜底由 executeToolCall 包装 error JSON 不炸轮次。
// · ★ 笔 2 已接（方案 §3.2）：schema 带可选 file 参数；不带 file = 正文 + `<skill_resources>`
//   附件清单段（**只列名不预读**——附件可能很大，预读进上下文是纯浪费，官方要点），带 file =
//   按 (技能名, 件名) 定位后取该附件内容。无附件的技能回执与笔 1 逐字节一致（空段不追加）。
import { ToolExecutor } from './ToolContracts';
import { SKILL_CONTENT_MAX, SKILL_DESC_MAX, SKILL_NAME_MAX, SKILL_TOTAL_MAX,
  USE_SKILL_SCHEMA_BASE, SkillArgsValidation, SkillBriefItem, SkillDocItem, SkillFileDocItem,
  SkillFileItem, SkillFileLocateOutcome, SkillLocateOutcome,
  composeSkillFileMultiHit, composeSkillFileNoHit, composeSkillFileReply, composeSkillLoadReply,
  composeSkillMultiHit, composeSkillNoHit, locateSkillByName,
  locateSkillFileByName, validateSkillArgs } from '../SkillText';
import { SKILL_MANAGE_LIST_DEFAULT_COUNT, SKILL_MANAGE_LIST_MAX_COUNT,
  ManageSkillsValidation, SkillManageListItem, composeManageSkillListReply,
  composeManageSkillUpdateReply, locateSkillByNameExcluding,
  validateManageSkillsArgs } from '../SkillManageText';
import {
  countSkills, insertSkill, querySkill, querySkillFile, querySkillFiles, querySkills,
  SkillFileRow, SkillRow, updateSkill
} from '../store/SkillDb';

// 工具名常量 TOOL_USE_SKILL 归口 ToolTypes.ets（与注册/模式驱动名单同源引用，本域不重复
// 定义防漂移）。

// 入参 schema（★ 2026-09-16 技能管理工具与加载枚举笔 B 单元落地：name 的 enum 动态约束
// 已实现——基线串上移 SkillText.USE_SKILL_SCHEMA_BASE（本域不能反向持静态基线，SkillText
// 零 import 是其断言直跑前提，反向引用即成环），动态版 composeUseSkillSchema(names) 同在
// SkillText，ChatSendCtrl 声明处按当轮清单同源集重建，取值面与 system 清单同闸同源同序；
// 「与提示缓存前缀稳定性有张力」的旧疑虑已判定消化——清单本就每请求现拼，enum 与之同源
// 同频，前缀断点位置不变、无额外抖动来源，改技能正文更不影响两者）。
// ★ 笔 2 增可选 file（方案 §3.2）：给了 file 就是「取这件技能的某个附件」——不预读附件的
// 官方要点由此闭环（模型先拿正文与附件清单，需要哪份再发一次带 file 的调用）
export const USE_SKILL_SCHEMA: string = USE_SKILL_SCHEMA_BASE;

// SkillRow → 清单/定位最小形态（零 import 域不引 DB 类型——适配在此单点，ToolMemoryManage
// toManageItems 同款）
function toBriefItems(rows: SkillRow[]): SkillBriefItem[] {
  const items: SkillBriefItem[] = [];
  for (const row of rows) {
    items.push({ id: row.id, name: row.name, description: row.description });
  }
  return items;
}

// 附件最小形态适配（零 import 域不引 DB 类型——toBriefItems 同款单点）
function toFileItems(rows: SkillFileRow[]): SkillFileItem[] {
  const items: SkillFileItem[] = [];
  for (const row of rows) {
    items.push({ id: row.id, name: row.name });
  }
  return items;
}

// 技能加载执行器：解析 name/file → 全库定位三态 →（带 file = 取该技能某附件 / 不带 = 取
// 正文 + 附件清单段）；导出 = ToolTypes 注册引用 + 断言脚本源码形态钉
export class UseSkillExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    let name: string = '';
    let fileName: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const rawName: Object | undefined = parsed['name'];
      const rawFile: Object | undefined = parsed['file'];
      if (typeof rawName === 'string') {
        name = rawName.trim();
      }
      if (typeof rawFile === 'string') {
        fileName = rawFile.trim();
      }
    } catch (e) {
      return Promise.resolve('参数解析失败，需要 name 参数（技能名称）。');
    }
    if (name === '') {
      return Promise.resolve('name 参数不能为空，请逐字复制系统提示词可用技能清单里的技能名称。');
    }
    return querySkills().then((rows: SkillRow[]): Promise<string> => {
      const items: SkillBriefItem[] = toBriefItems(rows);
      const outcome: SkillLocateOutcome = locateSkillByName(items, name);
      if (outcome.state === 'none') {
        return Promise.resolve(composeSkillNoHit(items, name));
      }
      if (outcome.state === 'multi') {
        return Promise.resolve(composeSkillMultiHit(outcome.hits));
      }
      // 定位与取内容之间可能存在并发删除窗口（用户在技能库删掉该行）——查不到按
      // 「已不存在」如实回执，不谎报加载成功
      return querySkill(outcome.hitId).then((row: SkillRow | null): Promise<string> => {
        if (row === null) {
          return Promise.resolve('该技能刚刚被删除，未能加载。现有技能清单见系统提示词。');
        }
        if (fileName !== '') {
          return resolveSkillFile(row, fileName);
        }
        const doc: SkillDocItem = { name: row.name, description: row.description,
          content: row.content };
        // 附件清单段（方案 §3.2：只列名不预读；无附件时回执与笔 1 逐字节一致）。
        // ★ 组装走 composeSkillLoadReply（不是手工拼）——它按 SKILL_REPLY_MAX_CHARS 预算
        // 先保正文再收窄清单，防「正文顶格 + 清单段」越过 clipToolResult 被尾部截断
        return querySkillFiles(row.id).then((files: SkillFileRow[]): string =>
          composeSkillLoadReply(doc, toFileItems(files)));
      });
    });
  }
}

// 附件取件（file 参数分支）：件名三态定位 → 唯一命中回内容标签；全库/本技能查询失败或
// 三态异常都走文本回执，不 reject（外拆域件恒 resolve 口径）
function resolveSkillFile(skill: SkillRow, fileName: string): Promise<string> {
  return querySkillFiles(skill.id).then((rows: SkillFileRow[]): Promise<string> => {
    const files: SkillFileItem[] = toFileItems(rows);
    const outcome: SkillFileLocateOutcome = locateSkillFileByName(files, fileName);
    if (outcome.state === 'none') {
      return Promise.resolve(composeSkillFileNoHit(files, fileName));
    }
    if (outcome.state === 'multi') {
      return Promise.resolve(composeSkillFileMultiHit(skill.name, outcome.hits));
    }
    return querySkillFile(outcome.hitId).then((file: SkillFileRow | null): string => {
      if (file === null) {
        return '该附件刚刚被删除，未能加载。可重新调用 use_skill（不带 file）查看现有附件清单。';
      }
      const doc: SkillFileDocItem = { name: file.name, content: file.content };
      return composeSkillFileReply(skill.name, doc);
    });
  });
}

// ── 管理技能工具（2026-09-16 技能管理工具笔，任务书-技能管理工具与加载枚举-20260916
//    §3.1——第 17 件内置工具 manage_skills 的实现；create_skill 整体退役并入本件）──
// 用户说「我有哪些技能 / 看看某件技能 / 把正文加一条 / 改个名」时，模型经本件直接读改技能库
// （对标 manage_memory / manage_prompts 同一形制）。技能管理卡**非独占**件：普通助手
// 技能管理卡开关可开（沿用 create_skill 现状零收窄），控制台助手 seed 默认带。
// · 四 action 无 delete（09-13 缺口盘点 C 档结论维持：删除不可逆且绕过 UI 确认链——
//   SkillLibraryPage 确认弹窗 + deleteSkill 级联三件事，工具直删会跳过；desc 与错误路径
//   恒指引 设置 → 技能库 手动删，照 manage_prompts 措辞先例）。
// · get 为必需面——「改正文」必须先读到原文，而 use_skill 只覆盖清单可见集，库内其余技能
//   模型没有读入口。
// · schema/desc 的上限数字随 SkillText 常量单源动态拼（照 MANAGE_MEMORY_SCHEMA/
//   buildManageMemoryDesc 先例——desc 不嵌任何随时间变化的值，仅常量上限，RikkaHub #1356
//   缓存教训钉）；无 icon 参数——update 时图标恒取原行值（validateSkillArgs 对 icon 有
//   越界归位默认的行为，传 '' 会把用户选的图标静默重置——红线 R-A2），工具面三字段外零扩面。
// · create 分支 = 原执行器链路原样迁移（红线 R-A1）：重名硬拒（重名会破坏 use_skill 的
//   trim 逐字定位键）、库满 catch 转文本、source 恒 'user'（insertSkill 写死不透传）、回执
//   「还未被任何助手启用」句一字不改。
// · update 合流语义：只改传入字段（空串 = 未传同义），icon 恒取原行；合流结果与原件逐字段
//   全等 = 「与原文相同，未做修改」如实回执不写库（防假更新回执）；改名判重
//   locateSkillByNameExcluding 排除自身（R-A3）；内置行（source='builtin'）的修改被
//   SkillDb.updateSkill 首行 throw 拦住，此处 catch 转中文文本回执不上抛（R-A4——上抛会被
//   executeToolCall 包成 error JSON 丢可读指引）。
// · list/get 回执不回显正文全文（除 get 单件正文外）；list 描述摘要复用 manifestDesc 同一份
//   截断（R-A5 禁第二份实现）。
// · 恒 resolve 不 reject（ToolMemoryManage / UseSkillExecutor 同口径）：全部错误态走文本回执。
// · 依赖全部已有（DB 层零改动）：querySkills / querySkill / querySkillFiles / countSkills /
//   insertSkill / updateSkill 均在 SkillDb；写口自带 broadcastSkillList（库页即时刷新，
//   工具面不需要额外广播）。

// 入参 schema（上限值随常量单源动态拼，照 MANAGE_MEMORY_SCHEMA 先例——改常量 schema 自随）
export const MANAGE_SKILLS_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["list","get","create","update"],' +
  '"description":"list 列出技能库索引，get 读取某件技能全文与附件清单，create 新建一件，' +
  'update 修改某件"},' +
  '"name":{"type":"string","description":"get 与 update 为要操作的技能名，须与技能库中的' +
  '名称逐字一致；create 为新技能名（' + SKILL_NAME_MAX + ' 字内、单行）"},' +
  '"new_name":{"type":"string","description":"update 专用可选，改名后的新名称"},' +
  '"description":{"type":"string","description":"create 与 update 可选，触发描述（' +
  SKILL_DESC_MAX + ' 字内）；update 传空串表示不修改"},' +
  '"content":{"type":"string","description":"create 与 update 可选，技能正文全文（' +
  SKILL_CONTENT_MAX + ' 字内）；update 为整体替换而不是追加"},' +
  '"offset":{"type":"integer","description":"list 专用，从第几件开始（默认 1）"},' +
  '"limit":{"type":"integer","description":"list 专用，本页件数（默认 ' +
  SKILL_MANAGE_LIST_DEFAULT_COUNT + '，最大 ' + SKILL_MANAGE_LIST_MAX_COUNT + '）"}},' +
  '"required":["action"]}';

// desc（常量单源动态拼；六件事全进 desc——逐 action 用途 / list 是索引不是全文 / 改正文
// 先 get 且 update 是整体替换 / 只改传入字段 / 不支持删除指引手动 / 调用纪律与复述要求。
// 「行为约束全进 desc」照 buildManageMemoryDesc 口径，薄路径也能自足）
export function buildManageSkillsDesc(): string {
  return '管理用户的技能库。action 取 list 查看技能索引（名称、描述摘要与正文字数，分页，' +
    '每页默认 ' + SKILL_MANAGE_LIST_DEFAULT_COUNT + ' 件，索引不是全文），get 读取某件技能的' +
    '全文与附件清单，create 新建一件，update 修改某件。改正文前必须先用 get 拿到当前全文，' +
    'update 的 content 是整体替换而不是追加，只改传入的字段，未传或传空串的字段保持原值。' +
    'create 的 name 用简短中文单行名（' + SKILL_NAME_MAX + ' 字内），description 用祈使句写清' +
    '什么时候该用（' + SKILL_DESC_MAX + ' 字内），content 写步骤说明（' + SKILL_CONTENT_MAX +
    ' 字内），三参齐备后一次调用。name 与 new_name 逐字取自 list 返回的名称。不支持删除，' +
    '用户要删技能时指引其到 设置 → 技能库 手动删除，不要尝试用其他方式删除。库上限 ' +
    SKILL_TOTAL_MAX + ' 件，新建与改名遇同名会失败并返回同名清单，换名重试。创建成功后告知' +
    '用户技能还未被任何助手启用，可在助手编辑页技能分区开启。' +
    '仅在用户明确要求时调用，执行后向用户复述改了什么。';
}

// 成功回执（名称 + 现总数 + 未启用提醒——回执全文进工具卡 = 用户审计面；R-A1 原样迁移，
// 一字不改）
export function composeManageSkillCreateReply(name: string, total: number): string {
  return '已创建技能「' + name + '」（现共 ' + total + ' 件）。它还未被任何助手启用，需要时' +
    '在对应助手的编辑页技能分区开启。';
}

// SkillRow → list 索引行适配（零 import 域不引 DB 类型——toBriefItems 同款单点）
function toManageListItems(rows: SkillRow[]): SkillManageListItem[] {
  const items: SkillManageListItem[] = [];
  for (const row of rows) {
    items.push({ id: row.id, name: row.name, description: row.description,
      contentChars: row.content.length });
  }
  return items;
}

// create 分支（R-A1 原样迁移自退役 CreateSkillExecutor：校验归位 icon 传空 → 重名守卫 →
// 库满/异常 catch 转文本 → 回执）
function createSkillFlow(v: ManageSkillsValidation, items: SkillBriefItem[]): Promise<string> {
  const checked: SkillArgsValidation = validateSkillArgs(v.name, v.description, '', v.content);
  if (!checked.ok) {
    return Promise.resolve(checked.error);
  }
  // 重名守卫（含与内置行重名——定位键纯度不分来源）；multi 命中回执带清单，unique
  // 命中一句话（hits 为空数组，不拼空段）
  const outcome: SkillLocateOutcome = locateSkillByName(items, checked.name);
  if (outcome.state !== 'none') {
    const hitsLine: string = outcome.hits.length > 0 ?
      '命中项：\n' + outcome.hits.join('\n') + '\n' : '';
    return Promise.resolve('已有同名技能「' + checked.name + '」，本次未创建。' + hitsLine +
      '请换一个名称后再试。');
  }
  return countSkills().then((count: number): Promise<string> =>
    insertSkill({ name: checked.name, description: checked.description, icon: checked.icon,
      content: checked.content })
      .then((row: SkillRow): string => composeManageSkillCreateReply(row.name, count + 1))
      .catch((e: Object): string => (e as Error).message));
}

// get 分支（定位命中后取正文 + 附件清单段——复用 composeSkillLoadReply 既有回执，禁新写
// 副本；并发删除窗口照 UseSkillExecutor 先例如实回执）
function getSkillFlow(skillId: string): Promise<string> {
  return querySkill(skillId).then((row: SkillRow | null): Promise<string> => {
    if (row === null) {
      return Promise.resolve('该技能刚刚被删除，未能读取。现有技能清单见系统提示词。');
    }
    return querySkillFiles(row.id).then((files: SkillFileRow[]): string =>
      composeSkillLoadReply({ name: row.name, description: row.description,
        content: row.content }, toFileItems(files)));
  });
}

// update 分支：取原行 → 合流（未传/空串保持原值，icon 恒取原行 R-A2）→ 与原件逐字段对比
//（全等 = 「未做修改」不写库防假更新回执）→ 改名判重排除自身 R-A3 → 校验归位（原 icon
// 原样过 validateSkillArgs）→ 落库（内置行 throw 由 catch 转中文文本 R-A4）→ 回执
function updateSkillFlow(v: ManageSkillsValidation, items: SkillBriefItem[],
  skillId: string): Promise<string> {
  return querySkill(skillId).then((row: SkillRow | null): Promise<string> => {
    if (row === null) {
      return Promise.resolve('该技能刚刚被删除，未能修改。');
    }
    const finalName: string = v.newName !== '' ? v.newName : row.name;
    const finalDesc: string = v.description !== '' ? v.description : row.description;
    const finalContent: string = v.content !== '' ? v.content : row.content;
    const changed: string[] = [];
    if (finalName !== row.name) {
      changed.push('名称');
    }
    if (finalDesc !== row.description) {
      changed.push('触发描述');
    }
    if (finalContent !== row.content) {
      changed.push('正文');
    }
    if (changed.length === 0) {
      // 传了字段但与现值全等（含 new_name 与现名一致）——如实回执不写库
      return Promise.resolve('传入内容与「' + row.name + '」当前内容相同，未做修改。');
    }
    if (finalName !== row.name) {
      const rename: SkillLocateOutcome =
        locateSkillByNameExcluding(items, finalName, row.id);
      if (rename.state !== 'none') {
        const hitsLine: string = rename.hits.length > 0 ?
          '命中项：\n' + rename.hits.join('\n') + '\n' : '';
        return Promise.resolve('已有同名技能「' + finalName + '」，本次未修改。' + hitsLine +
          '请换一个名称后再试。');
      }
    }
    const checked: SkillArgsValidation =
      validateSkillArgs(finalName, finalDesc, row.icon, finalContent);
    if (!checked.ok) {
      return Promise.resolve(checked.error);
    }
    return updateSkill(row.id, { name: checked.name, description: checked.description,
      icon: checked.icon, content: checked.content })
      .then((): string => composeManageSkillUpdateReply(row.name, checked.name, changed,
        row.content.length, checked.content.length))
      .catch((e: Object): string => (e as Error).message);
  });
}

// 管理技能执行器：校验 → 按 action 分路（list 索引 / get 单件全文 / create 原链迁移 /
// update 合流改写）。导出 = ToolTypes 注册引用 + 断言脚本源码形态钉
export class ManageSkillsExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: ManageSkillsValidation = validateManageSkillsArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(v.error);
    }
    if (v.action === 'list') {
      return querySkills().then((rows: SkillRow[]): string =>
        composeManageSkillListReply(toManageListItems(rows), v.offset, v.limit));
    }
    return querySkills().then((rows: SkillRow[]): Promise<string> => {
      const items: SkillBriefItem[] = toBriefItems(rows);
      if (v.action === 'create') {
        return createSkillFlow(v, items);
      }
      const outcome: SkillLocateOutcome = locateSkillByName(items, v.name);
      if (outcome.state === 'none') {
        return Promise.resolve(composeSkillNoHit(items, v.name));
      }
      if (outcome.state === 'multi') {
        return Promise.resolve(composeSkillMultiHit(outcome.hits));
      }
      if (v.action === 'get') {
        return getSkillFlow(outcome.hitId);
      }
      return updateSkillFlow(v, items, outcome.hitId);
    });
  }
}
