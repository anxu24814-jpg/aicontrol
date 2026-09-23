// 技能文本纯函数域（2026-09-13 技能层笔 1，方案-技能层-20260913 §2.1）：技能层的全部纯
// 逻辑——参数校验归位 / 系统提示词「可用技能」清单拼装（双封顶贪心 + 省略尾注）/ 技能名
// 三态定位 / use_skill 回执结构化标签 / SKILL.md 序列化（frontmatter）/ 助手启用清单
// 解析与序列化——零 import 纯函数约束（scripts/assert-app-domain.mjs 复制本文件为 .ts
// 直跑，SseParser/RequestInject/MemoryText 同款范式；IO 编排〔DB 读写/文件导出〕在
// SkillDb / ToolSkill / SkillEditPage，不在本域）。
//
// ★ 四层分工（帮助条目与代码注释同一口径，防概念混淆）：工具能做什么（ToolTypes 注册表）
// / 技能是怎么做的流程（本域 与 skills 表）/ 提示词是身份与规则（prompt_templates）/
// 记忆是用户的事实（memories）。
//
// ★ 与 tools 列的语义分界（本域最易被后人按错口径改坏的一点）：assistants.tools 的 ''
// = 默认集合（内置 defaultEnabled 项全上）；assistants.skills 的 '' = **空集合**（默认不
// 启用任何技能）。故 parseEnabledSkillIds 与 parseEnabledToolIds 形态相似而语义相反，
// **禁合并复用**（各留一份 = 有意为之的两处，不是重复代码）。
//
// ★ 模型可见面边界（负向钉，代码与断言双声明）：技能**正文**永不进 system 提示词——system
// 里只有「可用技能」清单（名称 + 触发描述），正文经 use_skill 工具结果通道按需加载。

// ── 上限常量族（拍板值，方案 §2.10；★ 2026-09-13 五百二十节前两值按官方规范对齐）──
// 名称上限（技能库页输入 maxLength 与本域校验同源）。**64 = 官方 Agent Skills 规范 name 上限**
//（agentskills.io/specification：1~64 字符）；原取 50 的紧值，后果是「规范合规的外部包」被
// 导入侧拒掉（55 字 name 在规范内、在本应用被拒），决明「对齐官方」后放开。
// ★ 有意**只对齐长度、不对齐字符集**：官方 name 限小写字母/数字/连字符且须与父目录同名，那是
// 面向目录标识符的约束；本应用的技能名是中文可读名（且是 use_skill 的逐字定位键），强套字符集
// 会把中文技能名判为非法——属**不可对齐项**，如实声明，勿当遗漏
// ★ 2026-09-15（二轮自检 F3 + N-O1 扩拒 + 同族收口）：字符面新增**唯一一处**拒绝——name 与
// 附件件名内部的**换行类字符**（整族七字符，定义与理由见 LINE_BREAK_CHARS）。它不是字符集
// 对齐（不限制任何可见字符），而是结构前提：换行会拆坏清单逐行路由表与 trim 逐字定位键，
// 见 validateSkillArgs 内注释
export const SKILL_NAME_MAX: number = 64;
// 触发描述上限（进系统提示词清单的主字段，超长直接吃掉清单预算）。**1024 = 官方规范
// description 上限**；原取 200 的紧值（立项时口径「官方上限是编码 agent 场景，聊天客户端取紧
// 值」，见调研档 §2.10 表），同因拒规范合规包而放开。代价如实记：描述是清单预算的主成分，
// 1024 字一条独占约半份 2000 字预算、清单会更快触发截断——由 composeSkillManifest 的贪心
// 选取 + 省略尾注兜底，最坏单条 = 3 + 64 + 1024 = 1091 < 2000，上界仍在（不越线）
export const SKILL_DESC_MAX: number = 1024;
// 正文上限（技能说明书全文，≤ clipToolResult 8192 保证单次加载不被截断）
export const SKILL_CONTENT_MAX: number = 8000;
// 单助手启用技能数上限（第 11 个开关面直接拒——上限执行在助手技能页）
export const SKILL_ENABLED_MAX: number = 10;
// 「可用技能」清单块字符上限（贪心选取 + 省略尾注兜底——清单常驻每次请求，token 有界）
export const SKILL_MANIFEST_MAX_CHARS: number = 2000;
// ★ 清单内**每行描述的截断档**（2026-09-13 五百二十一节，决明「可」——承五百二十节上限对齐官方
// 后的清单张力）：不加此档时，官方上限态（描述可写 1024 字）下 10 条启用技能要 ~11K 字才装得
// 全，实测 200 字档只进 8 条、1024 字档只进 **1 条**（其余全靠省略尾注遮掉）——「启用了却看不见」
// 比「看见一个截断的描述」更坏。截 120 字后：**启用满 10 条恒全部可见**（最坏行 = 2 + 名称
// 64 + 1 + 120 + 1 = 188 字，10 行 + 头行 + 尾注预留 = 1946 ≤ 2000），总量 2000 不动。
// 取 120 的依据：120 字 ≈ 官方「每技能约 100 token 元数据」的量级；清单是路由索引，正文另有
// use_skill 通道按需加载全文——**截断只发生在喂给模型的这一份**，库内值 / 编辑页 / 导入审阅
// 显示的都是描述全文
export const SKILL_MANIFEST_DESC_MAX: number = 120;
// 技能库总量上限（宪法「数据有界」；insert 超限拒绝 + 中文提示）
export const SKILL_TOTAL_MAX: number = 50;
// ★ manage_skills list 分页常量（SKILL_MANAGE_LIST_DEFAULT_COUNT / MAX_COUNT /
// PAGE_SOFT_CHARS）2026-09-16 随管理族拆出至 SkillManageText.ets，本域不再承载

// 图标候选集（12 项，全部取自工程内已实锤存在的 sys.symbol 名——「官方查证要求」条；
// 越界值为脏数据，校验时归位默认图标而非报错）。icon 是纯 UI 字段，不进模型面、不进
// 请求体，故候选集收紧不损失任何能力面
export const SKILL_ICON_CANDIDATES: string[] = ['wand_and_stars', 'lightbulb', 'book',
  'doc_text', 'text_alignleft', 'list_bullet', 'square_grid_2x2', 'person', 'clock',
  'gearshape', 'star', 'checkmark_circle'];
// 默认图标（建表 SQL 同值；脏值归位目标）
export const SKILL_ICON_DEFAULT: string = 'wand_and_stars';

// ── 清单（模型面，头行定稿）──
// 头行即调用引导：告诉模型「清单是路由表，正文要另调工具取」——工具 desc 与本节头行两处
// 同说一件事（一处是能力单源、一处是清单内联提示），缺任一模型都可能只读清单不加载正文
export const SKILL_MANIFEST_HEADER: string =
  '可用技能（任务与触发描述匹配时，先调用 use_skill 加载对应技能正文再作答）';
// 双封顶截断尾注（照 MEMORY_BLOCK_OMIT_NOTE 先例）
const SKILL_MANIFEST_OMIT_NOTE: string = '（更多技能已省略）';

// 清单/定位最小形态（零 import 域不引 DB 类型——SkillDb 侧单点适配，MemoryManageItem 同款）
export interface SkillBriefItem {
  id: string;
  name: string;
  description: string;
}

// 正文形态（use_skill 回执与 SKILL.md 导出共用）
export interface SkillDocItem {
  name: string;
  description: string;
  content: string;
}

// 校验归位结果（ok = false 时 error 为中文原因；icon 恒为可落库值）
export interface SkillArgsValidation {
  ok: boolean;
  name: string;
  description: string;
  icon: string;
  content: string;
  error: string;
}

function rejectSkillArgs(error: string): SkillArgsValidation {
  return { ok: false, name: '', description: '', icon: SKILL_ICON_DEFAULT, content: '',
    error: error };
}

// ── 换行类字符集（单一来源：名称/件名拒收 + 清单描述折叠 + 导入警告里的件名显示 三面共用）──
// 整族七字符 = Unicode 换行属性全集：\r \n（CR/LF）+ U+000B / U+000C（VT/FF，UAX#14 BK 类）+
// U+0085（NEL，NL 类）+ U+2028 / U+2029（LS/PS，BK 类）。取整族的理由（2026-09-15 决明「同族
// 也修吧」）：三处消费面是**同一个**结构问题——清单与附件清单都是逐行文本、名称与件名都是逐字
// 定位键，故只收 \r/\n（F3）或只收四字符（N-O1）都会留下「同一危害面用不同字符集」的自相矛盾；
// 这七字符在合法名称里没有任何正当用途，整族收口的代价只是极少数脏名被拒。**边界外**的 \t
// （U+0009）不在此列——制表符属空白不属换行，不拆行，收了反而误伤
const LINE_BREAK_CHARS: string = '\r\n\u000b\u000c\u0085\u2028\u2029';
// 折叠版（连续换行合并为一个空格；g 旗标只喂 replace——replace 恒从下标 0 起，无 test() 的
// lastIndex 残留陷阱）
const LINE_BREAK_FOLD: RegExp = /[\r\n\u000b\u000c\u0085\u2028\u2029]+/g;

// 含换行类字符否（名称与件名的拒收判据）
export function hasLineBreak(text: string): boolean {
  for (let i: number = 0; i < text.length; i++) {
    if (LINE_BREAK_CHARS.indexOf(text.charAt(i)) >= 0) {
      return true;
    }
  }
  return false;
}

// 换行类字符折叠为空格（清单描述折叠 / 导入警告里的件名显示——警告行自身不能再被换行拆开）
export function foldLineBreaks(text: string): string {
  return text.replace(LINE_BREAK_FOLD, ' ');
}

// 参数校验归位（照 MemoryText 混合口径，逐字段判）：
// · name / content —— 关键字段，空或超限**报错**（保存链据此 toast，不静默截断用户输入）；
//   name 另拒内部换行（理由与两条可达链见函数内注释）
// · description —— 可选项，允许空（空描述 = 清单行只剩名字，模型仍可按名字猜），超限报错
// · icon —— 纯 UI 字段，[] 或越界值**归位默认不报错**（脏值不该阻断保存，MemoryText
//   对 offset/limit 同款「脏值归位」哲学）
export function validateSkillArgs(name: string, description: string, icon: string,
  content: string): SkillArgsValidation {
  const trimmedName: string = name.trim();
  const trimmedDesc: string = description.trim();
  const trimmedContent: string = content.trim();
  if (trimmedName === '') {
    return rejectSkillArgs('技能名称不能为空');
  }
  // ★ 2026-09-15（技能层二轮自检 F3，决明拍板方案 a）：名称拒换行——名称是「可用技能」清单
  // 逐行路由表的行首（- 名称：描述）与 use_skill 的 trim 逐字定位键，含换行会把一条技能
  // 拆成「- 名称首段」+ 游离续行，模型照清单逐字复制名称的指引随之失灵。名称侧不走折叠
  // （描述侧的 manifestDesc 折叠只作用于喂模型的这一份文本；名称折叠 = 静默改名，库名与
  // 定位键必须逐字一致），故取明确拒。两条可达链 = manage_skills 的模型脏输出 / 外部包
  // frontmatter 的换行还原（UI 编辑页单行输入框常态无换行路径；粘贴等非常规形态未实测，
  // 由本校验一并兜住）；拒 + 中文报因让模型换名重试、导入侧明确拒收一句说清——与「越界
  // 明确拒不静默截断」同口径
  // ★ 2026-09-15（N-O1 扩拒 + 同族收口，决明拍板）：判据两步扩到**整族七字符**
  //（LINE_BREAK_CHARS）——先收 U+2028/U+2029（危害面与可达性均同 \r/\n：RFC 8259 允许两
  // 字符在 JSON 字符串里**字面**出现无须转义 → 模型 tool call 可达；SKILL.md 原文可直接写
  // 字面字符 → 导入链可达），再按「同族也修吧」把 NEL/VT/FF 一并收口（族集单一来源，与
  // 件名判据、描述折叠共用）。探针实锤：扩拒前七族形态全部放行且字符原样保留落库
  if (hasLineBreak(trimmedName)) {
    return rejectSkillArgs('技能名称不能包含换行，请改用单行名称');
  }
  if (trimmedName.length > SKILL_NAME_MAX) {
    return rejectSkillArgs('技能名称超过 ' + SKILL_NAME_MAX + ' 字上限，当前 ' +
      trimmedName.length + ' 字');
  }
  if (trimmedDesc.length > SKILL_DESC_MAX) {
    return rejectSkillArgs('触发描述超过 ' + SKILL_DESC_MAX + ' 字上限，当前 ' +
      trimmedDesc.length + ' 字');
  }
  if (trimmedContent === '') {
    return rejectSkillArgs('技能正文不能为空');
  }
  if (trimmedContent.length > SKILL_CONTENT_MAX) {
    return rejectSkillArgs('技能正文超过 ' + SKILL_CONTENT_MAX + ' 字上限，当前 ' +
      trimmedContent.length + ' 字');
  }
  return { ok: true, name: trimmedName, description: trimmedDesc,
    icon: resolveSkillIcon(icon), content: trimmedContent, error: '' };
}

// 图标归位（候选集外一律默认值——含 ''、含用户手改的任意串）
export function resolveSkillIcon(icon: string): string {
  return SKILL_ICON_CANDIDATES.includes(icon) ? icon : SKILL_ICON_DEFAULT;
}

// 启用集解析（assistants.skills 列 JSON 串 → id 数组）：
// '' / 坏 JSON / 非数组 → **空数组**（= 默认不启用任何技能，与 tools 列语义相反，见头注释）；
// 只收非空字符串项；去重（同名 id 重复出现会让「已启用 N 个」与第 11 个拒绝的门槛失真）
export function parseEnabledSkillIds(json: string): string[] {
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
  const ids: string[] = [];
  for (const item of raw) {
    if (typeof item === 'string' && item !== '' && !ids.includes(item)) {
      ids.push(item);
    }
  }
  return ids;
}

// id 数组 → assistants.skills 列 JSON 串：空集合落 ''（库列默认形态 = 不启用，新装/新建
// 助手零配置零写入——与 tools 的「全默认集合落 ''」形态相同而含义相反）
export function serializeEnabledSkillIds(ids: string[]): string {
  if (ids.length === 0) {
    return '';
  }
  return JSON.stringify(ids);
}

// ── 单条消息指定技能（2026-09-16，任务书-单条消息指定技能-20260916）──
// 指定技能 id 并入本轮 id 集：'' → 原集原样返回（零指定零开销）；已在集内 → 不重复
//（清单去重口径与 parseEnabledSkillIds 一致）；其余 → 追加。纯函数、零 import——断言脚本
// 复制本文件为 .ts 直跑（真值表四例）
export function appendDesignateId(ids: string[], designateId: string): string[] {
  if (designateId === '' || ids.includes(designateId)) {
    return ids;
  }
  return ids.concat([designateId]);
}

// 气泡/协议标注句（'' → 空串，调用方拼接时不产空段）。★ 显示面用它；协议面只在「用户零
// 文本」时代位（见 ChatSendCtrl.dispatchSend 注释）——不重复正文块里的技能名
export function composeSkillDesignateMark(name: string): string {
  return name === '' ? '' : '〔本条指定技能：' + name + '〕';
}

// 多段非空拼接（本轮文本合成的单一入口——用户文本/附件标注/指定标注三值共用一处，防两处
// 漂移）：逐段过滤空串，'\n\n' 连接；全空回 ''。纯函数、零 import（真值表：全空 / 单段 /
// 两段 / 含空段过滤 / 段序保持）
export function joinNonEmptyParts(parts: string[]): string {
  const kept: string[] = [];
  for (const part of parts) {
    if (part !== '') {
      kept.push(part);
    }
  }
  return kept.join('\n\n');
}

// 启用 ∩ 现存（发送链单点收口）：enabledIds 里在库内已不存在的 id 一律滤掉——删技能已
// 联动清列，此处是**第二道保险**（双保险拍板，方案 §1.3/行为矩阵 #3）：导入的旧备份、
// 跨设备恢复、并发删除窗口都可能留下悬空 id，悬空 id 若进清单会让模型调用必然失败的技能
export function selectEnabledSkills(items: SkillBriefItem[],
  enabledIds: string[]): SkillBriefItem[] {
  const out: SkillBriefItem[] = [];
  for (const item of items) {
    if (enabledIds.includes(item.id)) {
      out.push(item);
    }
  }
  return out;
}

// 「可用技能」清单拼装：items = 启用技能（调用方按 querySkills 三键序传入 = 卡片序）；
// items 空 → ''（= 不注入，调用方零特判）；双封顶 = SKILL_MANIFEST_MAX_CHARS 字符预算
// 贪心（至少保 1 条——首条恒放行，照 selectMemoryEntries 先例；否则极窄预算下清单会
// 退化成空头行，模型看到一句没有内容的引导语），超出的整条不进 + 尾注；
// ★ 五百二十一节起每行描述走 manifestDesc 截断（SKILL_MANIFEST_DESC_MAX）：截断后单行最坏
// 188 字，首条恒放行这条护栏由「可达路径」变为「结构性冗余」（常量若被改大它仍兜底）
export function composeSkillManifest(items: SkillBriefItem[]): string {
  if (items.length === 0) {
    return '';
  }
  const lines: string[] = [];
  // ★ 2026-09-13 全面自检轮：预算里**恒预留省略尾注的位置**（= 头行 + 尾注前的换行 + 尾注
  // 本身；与下方 buildResourcesWithin 同款理由）——尾注是「还有更多技能」的唯一说明，不能被
  // 自己顶出预算。实测：400 件短名条目走截断形态时总长 2004 > 2000，差的正是尾注那几字。
  // 首条仍恒放行（至少保 1 条，与 selectMemoryEntries 同口径）：合法值下首行最长
  // 45（头行）+ 1 + 253（50 名字 + 200 描述）= 299，远在预算内，放行不构成越线来源
  let used: number = SKILL_MANIFEST_HEADER.length + 1 + SKILL_MANIFEST_OMIT_NOTE.length;
  for (const item of items) {
    const line: string = '- ' + item.name + '：' + manifestDesc(item.description);
    if (used + 1 + line.length > SKILL_MANIFEST_MAX_CHARS && lines.length > 0) {
      break;
    }
    lines.push(line);
    used += 1 + line.length;
  }
  let block: string = SKILL_MANIFEST_HEADER + '\n' + lines.join('\n');
  if (lines.length < items.length) {
    block += '\n' + SKILL_MANIFEST_OMIT_NOTE;
  }
  return block;
}

// ── use_skill schema 动态拼装（2026-09-16 技能管理工具与加载枚举笔 B 单元，任务书 §3.3）──
// 无 enum 的静态基线串（自 ToolSkill.ets 上移——本域零 import 是其断言复制直跑的前提，
// builder 若反向引用 ToolSkill 常量即成环；ToolSkill 侧转出别名 USE_SKILL_SCHEMA =
// USE_SKILL_SCHEMA_BASE，ToolTypes import 行与两处桥桩形态零改动）。
// 串内容逐字等于上移前：name 逐字引用指引 + 可选 file（笔 2 附件取件——不预读附件的
// 官方要点由此闭环）。
export const USE_SKILL_SCHEMA_BASE: string =
  '{"type":"object","properties":{"name":{"type":"string",' +
  '"description":"技能名称，逐字取自系统提示词可用技能清单"},"file":{"type":"string",' +
  '"description":"可选。要读取的附件文件名，逐字取自上次加载该技能时返回的 ' +
  'skill_resources 清单；不填则加载技能正文"}},"required":["name"]}';

// use_skill 的 name 参数动态 enum 版 schema（每请求重建——取值 = 当轮「助手启用技能 ∩
// 库内现存（含单条消息指定）」，与 composeSkillManifest 的 enabled 数组同一次计算同序，
// ChatSendCtrl.buildSkillContext 单点供给）。行为三态：
// ①names 非空 → 基线对象挂 properties.name.enum 后 JSON.stringify——对象构造 + 序列化，
//   禁手拼串（红线 R-B1：RequestCompose.parseToolSchema 对坏 JSON 静默跳过该工具，拼串
//   出错 = 模型彻底失去技能加载能力且零报错；名字含引号/反斜杠/emoji 由 stringify
//   天然正确转义）；
// ②names 空 → 返回基线串同一份（零启用时工具本就不声明，此分支是防御与单源；
//   官方 Tip「没有任何技能时不要注册该工具」边界由调用面 hasEnabled 闸承接）；
// ③价值定位 = 给模型的闭集先验（上游不校验 enum 的端点仍靠回执自纠，不作上游保证）。
export function composeUseSkillSchema(names: string[]): string {
  if (names.length === 0) {
    return USE_SKILL_SCHEMA_BASE;
  }
  const schema: Record<string, Object> =
    JSON.parse(USE_SKILL_SCHEMA_BASE) as Record<string, Object>;
  const props: Record<string, Object> = schema['properties'] as Record<string, Object>;
  const nameSpec: Record<string, Object> = props['name'] as Record<string, Object>;
  nameSpec['enum'] = names;
  return JSON.stringify(schema);
}

// 清单行内的描述截断（超 SKILL_MANIFEST_DESC_MAX 加省略号；理由与档位依据见该常量注释）。
// 只影响清单这一份文本——库内值、编辑页回填、导入审阅显示的都仍是描述全文。
// ★ 2026-09-13 复核轮两处收紧：①**换行折叠**——清单是逐行路由表，描述含换行会把一行拆成
// 「- 名称：首行」+ 游离续行（编辑页触发描述是多行框，按回车即产生；校验只 trim 首尾、内部
// 换行照收，属易达形态）；②截断走 safeCutIndex（不劈代理对）
// ★ 2026-09-15 同族收口：折叠集从 \r\n 扩到整族七字符（foldLineBreaks / LINE_BREAK_CHARS）
// ——描述侧走**折叠**不走拒收（描述是自由文本，收窄会误伤正常写作；折叠只作用于喂模型的这
// 一份，库内值原样），与名称/件名的拒收合起来覆盖同一危害面
// ★ 2026-09-16 升 export（技能管理工具笔）：manage_skills 的 list 回执描述摘要复用本函数
//（书 §3.1.4 禁第二份截断实现——工具面与清单面同口径，改档位两处自随）
export function manifestDesc(description: string): string {
  const flat: string = foldLineBreaks(description);
  return flat.length > SKILL_MANIFEST_DESC_MAX ?
    flat.substring(0, safeCutIndex(flat, SKILL_MANIFEST_DESC_MAX)) + '…' : flat;
}

// ══════════════════════════════════════════════════════════════════════════════
// 附件文件族（笔 2，方案 §3）：文件件常量 / 扩展名窄化白名单 / 件名校验 / 附件清单段 /
// 附件回执 / 件名三态定位 / SKILL.md frontmatter 解析 / 技能包（zip）条目路径映射
// ══════════════════════════════════════════════════════════════════════════════

// 每技能附件件数上限（防无界；超限拒绝在文件编辑页「新建/上传」入口拦）
export const SKILL_FILE_MAX_COUNT: number = 10;
// 单件内容上限（< clipToolResult 8192——保证单次加载不被截断）
export const SKILL_FILE_CONTENT_MAX: number = 8000;
// 件名长度上限（含扩展名；UI 输入 maxLength 与本域校验同源）
export const SKILL_FILE_NAME_MAX: number = 60;

// 附件扩展名白名单（**独立窄化**，方案 §3 明令：不复用 AttachmentUtil.TEXT_EXTS 全集——
// 那份含 sh/bat/ps1/py/js/ts/c/h/cpp/java/css 等**脚本族**，与本域「拒脚本语义」直接矛盾；
// 本表只收无执行语义的纯数据/文档文本格式）
export const SKILL_FILE_EXTS: string[] = ['md', 'txt', 'csv', 'json', 'xml', 'yml', 'yaml',
  'toml', 'ini', 'log', 'html', 'htm'];

// 件名扩展名（小写、无点；无扩展名回 ''）。★ 有意自持而不 import AttachmentUtil.extOf——
// 本域零 import 约束（断言脚本复制直跑）优先于复用一行小工具，与 RequestInject 自持
// 同构接口同款取舍
export function skillFileExt(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 件名合法性（非空 + 不含换行类字符 + 长度 + 扩展名在白名单内——脚本族与二进制格式在此被拒）。
// ★ 2026-09-15 同族收口加换行判：件名与技能名是同一个结构问题（附件清单段 `- 件名` 是逐行
// 文本、件名是模型取件的逐字定位键），故同族集同判据。本函数现无应用侧消费方（O-1 家族，
// 仅断言消费），但它是纯域对外校验面，口径必须与 validateSkillFileArgs 保持一致——防后人
// 按它写新链时漏掉换行判
export function isSkillFileNameValid(name: string): boolean {
  const trimmed: string = name.trim();
  return trimmed !== '' && !hasLineBreak(trimmed) &&
    trimmed.length <= SKILL_FILE_NAME_MAX && SKILL_FILE_EXTS.includes(skillFileExt(trimmed));
}

// 件名校验结果（ok = false 时 error 为中文原因）
export interface SkillFileValidation {
  ok: boolean;
  name: string;
  content: string;
  error: string;
}

function rejectSkillFile(error: string): SkillFileValidation {
  return { ok: false, name: '', content: '', error: error };
}

// 附件件校验（并入参 = 名 + 正文；脏值不归位而是**明确拒**——与技能本体校验同一口径：
// 件名决定了模型能否按名取到，静默改名会让「清单里的名字」与「库里的名字」不一致）：
// · 件名空 / 含换行类字符 / 超长 / 扩展名不在白名单（含无扩展名、二进制、脚本族）→ 拒 + 中文原因
// · 正文空 / 超 SKILL_FILE_CONTENT_MAX → 拒
// ★ 2026-09-15 同族收口：件名拒换行（判据与族集同技能名）——附件清单段与件名定位键同受换行
// 破坏；UI 文件编辑框是单行输入，常态无换行路径，本判主要兜导入链与粘贴
export function validateSkillFileArgs(name: string, content: string): SkillFileValidation {
  const trimmedName: string = name.trim();
  const trimmedContent: string = content.trim();
  if (trimmedName === '') {
    return rejectSkillFile('文件名不能为空');
  }
  if (hasLineBreak(trimmedName)) {
    return rejectSkillFile('文件名不能包含换行，请改用单行名称');
  }
  if (trimmedName.length > SKILL_FILE_NAME_MAX) {
    return rejectSkillFile('文件名超过 ' + SKILL_FILE_NAME_MAX + ' 字上限，当前 ' +
      trimmedName.length + ' 字');
  }
  const ext: string = skillFileExt(trimmedName);
  if (ext === '') {
    return rejectSkillFile('文件名需要带扩展名，支持 ' + SKILL_FILE_EXTS.join('、'));
  }
  if (!SKILL_FILE_EXTS.includes(ext)) {
    return rejectSkillFile('不支持 .' + ext + ' 格式，仅支持纯文本文件 ' +
      SKILL_FILE_EXTS.join('、'));
  }
  if (trimmedContent === '') {
    return rejectSkillFile('文件内容不能为空');
  }
  if (trimmedContent.length > SKILL_FILE_CONTENT_MAX) {
    return rejectSkillFile('文件内容超过 ' + SKILL_FILE_CONTENT_MAX + ' 字上限，当前 ' +
      trimmedContent.length + ' 字');
  }
  return { ok: true, name: trimmedName, content: trimmedContent, error: '' };
}

// 解码乱码检出（2026-09-16 上传编码检测笔，评审 §2.6；同日晚「编码阈值收紧」笔收口自检轮
// 观察①）：上传/导入链一律以 UTF-8 强解字节（SkillPack 三个解码点），非 UTF-8 字节被解码器
// 替换成 U+FFFD（替换字符）且不报错——GBK 中文文本或二进制伪装件于是「解码成功」却整体乱码，
// 静默进编辑页/落库。判据 = **出现替换字符即判**（实测参照：GBK 中文「你好，世界」10 字节
// 经强解得 8 码元、7 枚替换字符）。判定按出现计数、不按占比：原 1% 占比阈值对「千字 ASCII
// 混少量 GBK 汉字」漏判（占比 <1% 检不出），且比率式在阈值 0 下「比值 >= 0」恒真、若把 >=
// 改 > 则一个字符回退即全员误拒——计数式无此暗雷。由调用方给中文拒收；纯函数落在本零
// import 域，断言脚本可复制直跑。
// 已知残限（有意不堵，成文防后人误当全覆盖）：UTF-16 无 BOM 且字节落在 ASCII 段（例
// 60 4F 7D 59）解出的是合法字符而非替换字符，本判据接不住——逐字节编码嗅探的复杂度与
// 误伤面都高于收益（细节 = 变更记录六百六十二节）；该残限与判定收紧无关（无替换字符可数）。
// 收紧新增边界 = 含真实 U+FFFD 的合法 UTF-8 件也会被拒（概率极低，登记见六百六十四节）
export const GARBLED_MARK_MIN: number = 1;
export function isGarbledText(text: string): boolean {
  if (text.length === 0) {
    return false; // 空件无可判（空内容由 validateSkillFileArgs 另行拒）
  }
  let marks: number = 0;
  for (let i = 0; i < text.length; i++) {
    if (text.charCodeAt(i) === 0xFFFD) {
      marks++;
    }
  }
  return marks >= GARBLED_MARK_MIN;
}

// 附件清单最小形态（零 import 域不引 DB 类型——SkillDb 侧单点适配）
export interface SkillFileItem {
  id: string;
  name: string;
}

// use_skill 回执的附件清单段（方案 §3.2：正文之后追加，**只列名字不预读内容**——官方要点：
// 附件可能很大，预读进上下文是纯浪费；模型凭清单再发一次带 file 参数的调用取件）。
// files 空 → ''（调用方据此不追加，回执形态与笔 1 逐字节一致——负向钉）
export function composeSkillResources(files: SkillFileItem[]): string {
  if (files.length === 0) {
    return '';
  }
  const lines: string[] = [];
  for (const file of files) {
    lines.push('- ' + file.name);
  }
  return '<skill_resources>\n' + lines.join('\n') + '\n</skill_resources>';
}

// 单次加载回执的字符预算（= clipToolResult 的默认线，ChatToolRoundCtrl 以默认参调用它）。
// ★ 2026-09-13 真机预演反推补出的缺口：正文上限 8000（拍板值）本身在 8192 以内，但笔 2
// 给回执**追加了附件清单段**——正文顶格（8000）+ 标签（约 40）+ 十个附件名（最长各 60 字，
// 约 620）≈ 8660 > 8192，超线后 clipToolResult 按尾截断，**被切的正是正文尾部**（说明书
// 的收尾步骤 = 任务执行依据）。
// 处置：不动任何一个拍板上限值（§8-4 的值仍归决明可调），改由本域在组装时**保正文、收窄
// 清单**——清单是索引，少列几个名字模型还能凭已列出的取件；正文被截则是依据直接丢失。
export const SKILL_REPLY_MAX_CHARS: number = 8192;
// 清单收窄时的省略尾注（与 manifest 的省略尾注同族，但指向不同的补救路径——这个指到页面）
const SKILL_RESOURCES_OMIT_NOTE: string = '（其余附件因长度未列出，可在 设置 → 技能库 查看）';

// 附件清单段按预算收窄（budget = 该段可占用的字符数）：装不下就少列几个并加省略尾注；
// 三种回 '' 的形态——①连标签本身都放不下（budget < fixed）；②一件名字都放不下（复核轮补的
// 严格预算，见下）；③调用方传空数组（其自身已短路）。回 '' 的语义恒为「只回正文，不产出
// 半个标签」，调用方零特判
function buildResourcesWithin(files: SkillFileItem[], budget: number): string {
  const openTag: string = '<skill_resources>';
  const closeTag: string = '</skill_resources>';
  // fixed 里**恒预留省略尾注的位置**（即使最终没省略）：否则「装下了第 N 行 → 因省略再补一段
  // 尾注」会把总长顶出预算——首版就栽在这里（自测实测 8218 > 8192），保守预留在尾部再加
  // 才有硬上界；代价是极端情况下少列一个名字，换来的是「绝不越线」这条可证的保证
  const fixed: number = openTag.length + 1 + closeTag.length + 1 +
    SKILL_RESOURCES_OMIT_NOTE.length + 1;
  if (budget < fixed) {
    return '';
  }
  const lines: string[] = [];
  let used: number = fixed;
  for (const file of files) {
    const line: string = '- ' + file.name;
    if (used + line.length + 1 > budget) {
      break;
    }
    lines.push(line);
    used += line.length + 1;
  }
  // ★ 2026-09-13 全面自检轮：**首行不再豁免预算**（原判据 `&& lines.length > 0` 让首行恒
  // 进块，是「绝不越线」这条保证的唯一破口——实测合法最坏形态：技能名 50 字 + 首件名 60 字
  // + 正文顶格 = 8219 > 8192，且技能名 ≥24 字起就能复现）。一件名字都放不下 → 整段不追加，
  // 调用方只回正文；比回一段尾部会被下游 clipToolResult 裁掉半截的清单干净
  if (lines.length === 0) {
    return '';
  }
  let block: string = openTag + '\n' + lines.join('\n') + '\n' + closeTag;
  if (lines.length < files.length) {
    block += '\n' + SKILL_RESOURCES_OMIT_NOTE;
  }
  return block;
}

// 单次加载回执（正文 + 附件清单段，受 SKILL_REPLY_MAX_CHARS 预算约束）：
// · 正文 ≤ 8000 恒完整（预算先扣正文与标签，剩余才给清单）——「单次加载不被截断」的承诺
//   由本函数承接，而不是靠「8000 < 8192」这一句话（那句在**没有清单段**时成立，笔 2 起不再）
// · 附件清单能全列就全列（含 10 件最长名的常规包仍在线内）；列不全则收窄 + 省略尾注
// · files 空 → 与笔 1 回执逐字节一致（负向钉不变）
export function composeSkillLoadReply(doc: SkillDocItem, files: SkillFileItem[]): string {
  const reply: string = composeSkillReply(doc);
  if (files.length === 0) {
    return reply;
  }
  const room: number = SKILL_REPLY_MAX_CHARS - reply.length - 1; // -1 = 连接换行
  if (room <= 0) {
    return reply; // 正文已顶格：清单完全放不下，宁可只给正文（不给残缺标签）
  }
  const resources: string = buildResourcesWithin(files, room);
  if (resources === '') {
    return reply;
  }
  return reply + '\n' + resources;
}

// 附件件回执（按名取到后返回其内容；标签带 name + skill 两个属性——模型能把「哪份附件」
// 与「哪次调用」对齐）
export function composeSkillFileReply(skillName: string, file: SkillFileDocItem): string {
  return '<skill_resource name="' + file.name + '" skill="' + skillName + '">\n' +
    file.content + '\n</skill_resource>';
}

// 附件正文形态（回执用）
export interface SkillFileDocItem {
  name: string;
  content: string;
}

// 件名定位三态（照 locateSkillByName 同形）。★ 库层写入侧已拒同名件（文件编辑页保存前查重），
// 本函数的多命中态是**兜底**：导入的旧包、并发写入窗口都可能造出同名件，此时如实拒歧义
// 比按 id 猜一条更安全（模型拿到的名字对不上任何一条都会困惑）
export interface SkillFileLocateOutcome {
  state: string; // 'unique' | 'none' | 'multi'
  hitId: string;
  hitName: string;
  hits: string[];
}

export function locateSkillFileByName(files: SkillFileItem[],
  name: string): SkillFileLocateOutcome {
  const needle: string = name.trim();
  const hits: string[] = [];
  let hitId: string = '';
  let hitName: string = '';
  for (let i: number = 0; i < files.length; i++) {
    if (files[i].name.trim() === needle) {
      if (hitId === '') {
        hitId = files[i].id;
        hitName = files[i].name;
      }
      hits.push('[' + (i + 1).toString() + '] ' + files[i].name);
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

// 件名未命中回执（附本技能现有附件清单 + 逐字引用指引；无附件时直说该技能没有附件）
export function composeSkillFileNoHit(files: SkillFileItem[], fileName: string): string {
  if (files.length === 0) {
    return '该技能没有附件文件，直接按技能正文执行即可。';
  }
  const lines: string[] = [];
  for (const file of files) {
    lines.push('- ' + file.name);
  }
  return '该技能没有名为「' + fileName.trim() + '」的附件。现有附件：\n' + lines.join('\n') +
    '\n请从上面的清单里逐字复制文件名再调用。';
}

export function composeSkillFileMultiHit(skillName: string,
  hits: string[]): string {
  return '技能「' + skillName + '」有 ' + hits.length + ' 个同名附件，无法确定取哪一份，' +
    '本次未加载。命中项：\n' + hits.join('\n') + '\n请让用户到 设置 → 技能库 里改名区分。';
}

// ── 导入审阅文案（方案 §3.3「入库前原文审阅提示」）──
// ★ 2026-09-13 真机预演反推补：审阅弹窗（ConfirmDialog 的 message）是**无上限 Text**——把
// 200 字正文摘录 + 十件最长 60 字的附件名 + 若干警告全塞进去，对话框会长到把「导入/取消」
// 两键顶出屏幕，而「让用户过目后点导入」正是这个弹窗存在的理由。故预览文案在**纯函数层
// 定量产出**：每段各自截断 + 段内条数封顶，最坏形态也有结构上界（SKILL_IMPORT_PREVIEW_MAX），
// 安全提示句恒在末尾恒不被截（它是「请确认内容可信」的唯一载体）。
export const SKILL_IMPORT_PREVIEW_MAX: number = 700;
const IMPORT_EXCERPT_MAX: number = 200;
const IMPORT_DESC_MAX: number = 60;
const IMPORT_NAME_LIST_MAX: number = 5;
const IMPORT_NAME_MAX: number = 20;
const IMPORT_WARN_LIST_MAX: number = 3;
const IMPORT_WARN_MAX: number = 40;
// 批量预览的件列表条数档（2026-09-22 多技能包笔：多技能包审阅弹窗列出前 N 件，其余走「等 N 件」
// 尾注——同「先保结构上界、明细留给导入后的技能库」的既有哲学，档位照 IMPORT_NAME_LIST_MAX 的量级取）
const IMPORT_BATCH_LIST_MAX: number = 8;
// 警告条内**件名段**的收窄档（2026-09-14 格式兼容笔「保原因、压件名」）：件名可长到路径形态
// （references/一组很长的目录名之下的说明文档.md），从尾部截会把「原因」整段吃掉——用户看见
// 一个被切断的名字却不知道它为什么没进来。故按首个「：」分两段：件名段收到本档（超出加省略号），
// 原因段保留；单条渲染仍守既有 40 字档（件名 20 + 省略号 + 冒号 + 原因，合法原因词最长 18 字，
// 恰好落在 40 内；超出时才由尾截兜底——**不上移任何档位，只改裁剪方向**）
const IMPORT_WARN_NAME_MAX: number = 20;
// 安全提示句（导入弹窗的最后一句，承载「正文是指令面，须过目」这件事）
export const SKILL_IMPORT_SAFETY_LINE: string =
  '技能正文会作为助手的执行说明使用，请确认内容可信后再导入。';

export interface SkillImportPreviewInput {
  name: string;
  description: string;
  content: string;
  fileNames: string[];
  warnings: string[];
}

// 单段截断（超长加省略号）
function clip(text: string, max: number): string {
  return text.length > max ?
    text.substring(0, safeCutIndex(text, max)) + '…' : text;
}

// 导入警告单条的裁剪（件名压窄、原因保留——理由与档位见 IMPORT_WARN_NAME_MAX 注释）。
// 无「：」的形态（聚合计数条如「另有 N 个附件超过…」）没有件名段，走原文尾截兜底
function clipImportWarning(warning: string): string {
  const sep: number = warning.indexOf('：');
  if (sep < 0) {
    return clip(warning, IMPORT_WARN_MAX);
  }
  const name: string = warning.substring(0, sep);
  const reason: string = warning.substring(sep + 1);
  const shown: string = name.length > IMPORT_WARN_NAME_MAX ?
    clip(name, IMPORT_WARN_NAME_MAX) : name;
  const line: string = shown + '：' + reason;
  return clip(line, IMPORT_WARN_MAX);
}

// 定长截断的安全切点（代理对防护）——返回可直接喂 substring 的下标，且仅当确需截断时才回退。
// ★ 2026-09-13 复核轮：emoji 等增补平面字符占两个码元，按定长硬切会把一对劈开、留下**孤立
// 代理字符**（实测：描述第 120 个码元处放 emoji → 清单里出现 '\uD83D'）。该字符进文件路径是
// 非法名、进请求体 JSON 是非法 Unicode——属不该出现的坏数据。判据 = 末位落在高代理项
// （0xD800~0xDBFF）时回退一位（低代理项开头必是合法配对，无需处理）
export function safeCutIndex(text: string, max: number): number {
  if (text.length <= max) {
    return text.length;
  }
  const last: number = text.charCodeAt(max - 1);
  return (last >= 0xD800 && last <= 0xDBFF) ? max - 1 : max;
}

export function composeImportPreview(input: SkillImportPreviewInput): string {
  const parts: string[] = [];
  // ★ 2026-09-13 全面自检轮：名称段同样截断——原实现唯它一段不设上界，超长名（外部包绕过
  // 校验的形态）能把预审文案顶过 SKILL_IMPORT_PREVIEW_MAX（实测 821 > 700），而「最坏形态有
  // 结构上界」是本函数对外承诺。上界取 SKILL_NAME_MAX（本该有的合法长度，超出的部分由导入侧
  // 校验先拒；此处是第二道，保证函数自身对任意输入成立）
  parts.push('名称：' + clip(input.name, SKILL_NAME_MAX));
  if (input.description !== '') {
    parts.push('触发描述：' + clip(input.description, IMPORT_DESC_MAX));
  }
  parts.push('正文：' + clip(input.content, IMPORT_EXCERPT_MAX));
  if (input.fileNames.length > 0) {
    const shown: string[] = [];
    const limit: number = Math.min(IMPORT_NAME_LIST_MAX, input.fileNames.length);
    for (let i: number = 0; i < limit; i++) {
      shown.push(clip(input.fileNames[i], IMPORT_NAME_MAX));
    }
    const more: string = input.fileNames.length > limit ?
      ' 等 ' + input.fileNames.length + ' 个' : '';
    parts.push('附件 ' + input.fileNames.length + ' 个：' + shown.join('、') + more);
  }
  if (input.warnings.length > 0) {
    const shown: string[] = [];
    const limit: number = Math.min(IMPORT_WARN_LIST_MAX, input.warnings.length);
    for (let i: number = 0; i < limit; i++) {
      shown.push(clipImportWarning(input.warnings[i]));
    }
    const more: string = input.warnings.length > limit ?
      ' 等 ' + input.warnings.length + ' 项' : '';
    parts.push('以下内容未导入：' + shown.join('；') + more);
  }
  parts.push(SKILL_IMPORT_SAFETY_LINE);
  return parts.join('\n\n');
}

// ── 多技能包审阅文案（2026-09-22 多技能包笔）──
// 单个压缩包里装多件技能时（合集包 / GitHub 技能仓库的 zip 下载），一件一段的单件预览会随件数
// 线性膨胀——同样顶掉弹窗的「导入/取消」两键。故批量形态只列**件名与附件数**（正文逐件审阅留给
// 导入后的技能库，那里的编辑页是完整正文），跳过项沿用单件预览的裁剪与封顶档（clipImportWarning），
// 安全提示句照旧恒在末尾。
export interface SkillBatchPreviewItem {
  name: string;
  fileCount: number;
}

export interface SkillBatchPreviewInput {
  items: SkillBatchPreviewItem[];
  skipped: string[];
}

export function composeBatchImportPreview(input: SkillBatchPreviewInput): string {
  const parts: string[] = [];
  const total: number = input.items.length;
  const limit: number = Math.min(IMPORT_BATCH_LIST_MAX, total);
  const lines: string[] = [];
  for (let i: number = 0; i < limit; i++) {
    const item: SkillBatchPreviewItem = input.items[i];
    const files: string = item.fileCount > 0 ? '，附件 ' + item.fileCount + ' 个' : '';
    lines.push((i + 1).toString() + '. ' + clip(item.name, IMPORT_NAME_MAX) + files);
  }
  if (total > limit) {
    lines[limit - 1] = lines[limit - 1] + ' 等 ' + total + ' 件';
  }
  parts.push('本次将导入 ' + total + ' 件技能\n' + lines.join('\n'));
  if (input.skipped.length > 0) {
    const shown: string[] = [];
    const keep: number = Math.min(IMPORT_WARN_LIST_MAX, input.skipped.length);
    for (let i: number = 0; i < keep; i++) {
      shown.push(clipImportWarning(input.skipped[i]));
    }
    const more: string = input.skipped.length > keep ?
      ' 等 ' + input.skipped.length + ' 项' : '';
    parts.push('另有 ' + input.skipped.length + ' 件未导入\n- ' + shown.join('\n- ') + more);
  }
  parts.push(SKILL_IMPORT_SAFETY_LINE);
  return parts.join('\n\n');
}

// ── SKILL.md frontmatter 解析（导入侧，方案 §3.3）──
// 导入包里的 SKILL.md 未必出自本应用（可能手写或来自其他客户端），故解析**容错且严格报因**：
// frontmatter 缺失/不可解析/name 缺失/description 键缺失 → ok=false + 中文 error（调用方
// 据此跳过该条并如实报告，不静默丢件）。允许 description 值为空串，但键必须在——
// 「键缺失」与「作者显式写了空描述」是两件事，前者多为格式错，后者是刻意留空。
export interface SkillMdParse {
  ok: boolean;
  name: string;
  description: string;
  content: string;
  error: string;
}

function rejectSkillMd(error: string): SkillMdParse {
  return { ok: false, name: '', description: '', content: '', error: error };
}

// 首尾围栏剔除：允许 BOM 与围栏前后的空白行（跨客户端产物常见形态）
const MD_FENCE: string = '---';

// YAML 块标量指示符判据（'|' / '>'，可带 chomping 与显式缩进指示：|-, >+, |2, >-2 等）。
// 整值匹配才算——值里以这两个字符开头但还有别的内容的（如「> 3 条时…」）是普通标量，
// 本域不误伤（见 parseSkillMd 内拒收点）
function isBlockScalarIndicator(value: string): boolean {
  return /^[|>][-+]?\d*$/.test(value);
}

export function parseSkillMd(text: string): SkillMdParse {
  let body: string = text;
  if (body.charCodeAt(0) === 0xFEFF) {
    body = body.substring(1); // BOM（Windows 记事本另存常见）
  }
  const lines: string[] = body.split('\n');
  let head: number = 0;
  while (head < lines.length && lines[head].trim() === '') {
    head++;
  }
  if (head >= lines.length || lines[head].replace(/\r$/, '').trim() !== MD_FENCE) {
    return rejectSkillMd('缺少 frontmatter（文件需要以 --- 开头）');
  }
  let end: number = -1;
  for (let i: number = head + 1; i < lines.length; i++) {
    if (lines[i].replace(/\r$/, '').trim() === MD_FENCE) {
      end = i;
      break;
    }
  }
  if (end < 0) {
    return rejectSkillMd('frontmatter 无法解析（缺少结束的 ---）');
  }
  let name: string | null = null;
  let description: string | null = null;
  for (let i: number = head + 1; i < end; i++) {
    const line: string = lines[i].replace(/\r$/, '');
    const colon: number = line.indexOf(':');
    if (colon < 0) {
      continue;
    }
    const key: string = line.substring(0, colon).trim();
    const rawValue: string = line.substring(colon + 1).trim();
    // ★ 2026-09-13 复核轮：**只消费 name / description 两键，其余键原样忽略**（官方 Agent
    // Skills 规范还有 license / allowed-tools / metadata / version 等键，别家包带它们是常态，
    // 本域不认也不该因此拒收整包）
    if (key !== 'name' && key !== 'description') {
      continue;
    }
    // ★ 2026-09-13 全面自检轮：YAML 多行块标量（`description: |` / `>` 及其 chomping 变体）
    // 此前被当普通标量收下——description 会变成字面量 '|'（外部手写包常见写法）静默落库，
    // 而触发描述是模型判断是否加载的主字段。宁可拒并说清「暂不支持多行」也不静默收错值；
    // 判据收窄到「整值就是块指示符」，普通标量（如「> 3 条时…」）不误伤。
    // ★ 复核轮补：本判据**只对上面这两键**生效（原版对所有键生效 = 无关键的块标量会把整包
    // 拒掉，属过度拒收——虽然本域读不懂那些键，但读不懂 ≠ 该拒，忽略才是原口径）
    if (isBlockScalarIndicator(rawValue)) {
      return rejectSkillMd('frontmatter 的 ' + key + ' 用了多行写法（' + rawValue.charAt(0) +
        '），暂不支持，请改写成一行');
    }
    if (key === 'name') {
      name = unquoteYamlScalar(rawValue);
    } else {
      description = unquoteYamlScalar(rawValue);
    }
  }
  if (name === null) {
    return rejectSkillMd('frontmatter 里缺少 name');
  }
  if (name.trim() === '') {
    return rejectSkillMd('frontmatter 里的 name 为空');
  }
  if (description === null) {
    return rejectSkillMd('frontmatter 里缺少 description');
  }
  const tail: string[] = [];
  for (let i: number = end + 1; i < lines.length; i++) {
    tail.push(lines[i].replace(/\r$/, ''));
  }
  // 围栏后的首部空行剔除（serializeSkillMd 恒写一个空行）
  let start: number = 0;
  while (start < tail.length && tail[start].trim() === '') {
    start++;
  }
  // ★ 首尾空白归位（2026-09-13 独立探针暴露的口径不一致，此处定为**有意归一**）：写入侧
  // yamlScalar 会为带首尾空白的值加引号（保住它），读取侧这里统一 trim 掉——两边合起来
  // 的净语义 = 「导入的库内值恒无首尾空白」。取此口径的理由：库内名是模型 use_skill 的
  // 逐字定位键，带隐形空白会让用户照清单重打的名字匹配不上；description 同理。写入侧的
  // 引号包裹依然必要——不留它，YAML 自己就会把前导空格吃掉，跨客户端连原文都读不回
  return { ok: true, name: name.trim(), description: description.trim(),
    content: tail.slice(start).join('\n').trim(), error: '' };
}

// YAML 标量还原（与 yamlScalar 对偶）：双引号包裹 → 剥引号 + 反转义；单引号 → 剥引号 +
// '' 还原为 '（YAML 单引号转义规则）；裸值 → 原样。注意只处理**同款引号成对**的形态，
// 半引号（只有一边）按裸值返回——比自作聪明地截断更安全
export function unquoteYamlScalar(value: string): string {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    const inner: string = value.substring(1, value.length - 1);
    let out: string = '';
    for (let i: number = 0; i < inner.length; i++) {
      const ch: string = inner.charAt(i);
      if (ch === '\\' && i + 1 < inner.length) {
        const next: string = inner.charAt(i + 1);
        if (next === 'n') {
          out += '\n';
          i++;
          continue;
        }
        if (next === 'r') {
          out += '\r';
          i++;
          continue;
        }
        if (next === 't') {
          out += '\t';
          i++;
          continue;
        }
        if (next === '"' || next === '\\') {
          out += next;
          i++;
          continue;
        }
      }
      out += ch;
    }
    return out;
  }
  if (value.length >= 2 && value.startsWith('\'') && value.endsWith('\'')) {
    return value.substring(1, value.length - 1).split('\'\'').join('\'');
  }
  return value;
}

// ── 技能包（zip 目录，方案 §3.3）──
// 包内形态 = <目录名>/SKILL.md + <目录名>/files/<附件名>；目录名取技能名的文件名安全化形态
// （跨端非法字符替换 + 截断；与导出文件名同款清洗）
export function skillPackDirName(skillName: string): string {
  const safe: string = skillName.replace(/[\\/:*?"<>|]/g, '_').trim();
  // 截断走 safeCutIndex（不劈代理对——目录名会落到文件系统路径上，孤立代理字符是非法名）
  const cut: string = safe.substring(0, safeCutIndex(safe, 40));
  // 纯点段（'.' / '..'）与空名同档归位 skill（2026-09-15 全面自检轮 P1）：清洗正则不处理
  // 点，名称恰为 '..' 时原样返回——导出链 root = staging + '/..' 解析回 cacheDir 本身，
  // 正文与 files/ 全部越界写进 cacheDir，且 compressFile(root) 会把整个 cacheDir 打包进
  // 分享件（探针 scripts/.tmp/skill-layer-check-20260915.mjs 实锤）。'...' 等多点串是
  // 合法目录名，不误伤
  return cut === '' || cut === '.' || cut === '..' ? 'skill' : cut;
}

// 包内条目语义（条目名 → 语义的**纯映射**；★ 2026-09-14 格式兼容笔改契约，见下）：
// · 'md'     —— 'SKILL.md'，技能正文与元信息。**只有包根这一处**是主文件；子目录里的同名件
//                （如 references/SKILL.md）是普通资源，不特判
// · 'file'   —— 其余非空路径 = 附件，fileName = 归一化后的件名
// · 'ignore' —— 空串 / 纯斜杠等退化形态（采集链遍历产出的相对路径恒非空，本态是该纯函数的
//                自身防御分支，写法照既有风格保留）
// ★★ 契约变更（本笔）：入参 = **相对 pack root 的路径**（原契约吃整条 zip 条目名并做「多一层
//   目录右对齐」容错——那条容错的实际落点是 SkillPack.locatePackRoot〔只下钻一级〕，不在本
//   函数，双份口径已撤除）。改名同时**接线**：SkillPack.collectPackFiles 的递归遍历逐件调用它
//   取名——2026-09-13 全面自检轮记的「无应用侧消费方」（O-1）随之消失。
// ★ 归一化规则单源在本函数（SSOT，先例 skillPackDirName）：剥一层 `files/` 前缀——自家包
//   `files/数据字典.md` → `数据字典.md`（老包行为逐字不变），`files/深/层.md` → `深/层.md`；
//   `references/api.md` 原样保留（路径名是模型取件的唯一定位键，且本技能内件名硬查重，
//   扁平化会让 references/a.md 与 assets/a.md 撞名）。**只剥一层**：`files/files/a.md` →
//   `files/a.md`，保证「导出按 files/<件名> 落盘 → 再导入」逐轮往返不叠层
export interface SkillPackEntry {
  kind: string; // 'md' | 'file' | 'ignore'
  fileName: string;
}

export function classifySkillPackEntry(entryName: string): SkillPackEntry {
  const cleaned: string[] = [];
  for (const part of entryName.split('/')) {
    if (part !== '') {
      cleaned.push(part);
    }
  }
  if (cleaned.length === 0) {
    return { kind: 'ignore', fileName: '' };
  }
  const rel: string = cleaned.join('/');
  // 'SKILL.md' 字面量（本域零 import 约束下自持；与 SkillPack.SKILL_PACK_MD_NAME 同值）
  if (rel === 'SKILL.md') {
    return { kind: 'md', fileName: '' };
  }
  return { kind: 'file', fileName: stripPackFilesPrefix(rel) };
}

// 剥一层 `files/` 前缀（只认路径开头那一段、只剥一次——见 classifySkillPackEntry 注释）
function stripPackFilesPrefix(rel: string): string {
  const prefix: string = 'files/';
  return rel.startsWith(prefix) ? rel.substring(prefix.length) : rel;
}

// 包内技能根选取（2026-09-22 多技能包笔；纯函数，可离线直跑——SkillPack 侧只负责把「包内扫到的
// 全部 SKILL.md 相对路径」喂进来，判定规则单源在本函数）：
// 输入 mdPaths = 包内所有 SKILL.md 的**相对包根路径**（'/' 分隔，如 'SKILL.md'、
// 'skill-a/SKILL.md'、'skills-main/skill-b/SKILL.md'）；输出 = 技能根目录清单（'' 表示包根），
// 按名字升序；空数组 = 无技能可导（调用方报「找不到 SKILL.md」）。
// 规则三层，自上而下短路：
// ① 包根有 SKILL.md → ['']——单技能包的既有形态不变（此时子目录里的 SKILL.md 维持「子目录同名
//    件是普通资源、按附件采集」的既有口径，不特判）
// ② 一级子目录里有 SKILL.md 的 → 全部返回（≥2 个即多技能包；平铺合集与「每个技能一个目录」的
//    合集包都落这一层）
// ③ 二级子目录（如 repo-main/skill-a/SKILL.md）→ 全部返回——GitHub 技能仓库的 zip 下载天然是
//    「一层仓库名 + 每技能一目录」，②落空时下钻这一层
// 深于两层不认（扫描侧同界，见 SkillPack.collectSkillRoots）：更深的包装多为无意产物，认了会把
// 附件目录里恰好存在的 SKILL.md 误认成一件技能
export function pickSkillRoots(mdPaths: string[]): string[] {
  const mdName: string = 'SKILL.md';
  const depth1: string[] = [];
  const depth2: string[] = [];
  for (const mdPath of mdPaths) {
    if (mdPath === mdName) {
      return [''];
    }
    const tail: string = '/' + mdName;
    if (!mdPath.endsWith(tail)) {
      continue;
    }
    const dir: string = mdPath.substring(0, mdPath.length - tail.length);
    const segs: string[] = dir.split('/');
    let empty: boolean = false;
    for (const seg of segs) {
      if (seg === '') {
        empty = true;
      }
    }
    if (empty) {
      continue;
    }
    if (segs.length === 1) {
      depth1.push(dir);
    } else if (segs.length === 2) {
      depth2.push(dir);
    }
  }
  if (depth1.length > 0) {
    return depth1.sort();
  }
  return depth2.sort();
}

// 技能名定位三态（照 locateMemoryByContent 先例）：两侧 trim 后**逐字相等**才命中——
// 库层无重名约束（改名不设唯一性），故多命中如实回三态由调用方拒歧义。命中时 hits 列出
// 全部命中行的 '[库序号] 名称'，供回执让模型/用户区分
export interface SkillLocateOutcome {
  state: string; // 'unique' | 'none' | 'multi'
  hitId: string;
  hitName: string;
  hits: string[];
}

export function locateSkillByName(items: SkillBriefItem[], name: string): SkillLocateOutcome {
  const needle: string = name.trim();
  const hits: string[] = [];
  let hitId: string = '';
  let hitName: string = '';
  for (let i: number = 0; i < items.length; i++) {
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

// use_skill 回执（官方要点 = 结构化标签包裹正文）：标签带 name 属性，让模型能把「哪份
// 说明书」与「哪次调用」对齐；正文原样不加工（技能正文是用户写的指令文本，任何改写都是
// 对用户意图的篡改）
export function composeSkillReply(doc: SkillDocItem): string {
  return '<skill_content name="' + doc.name + '">\n' + doc.content + '\n</skill_content>';
}

// 定位失败回执（0 命中——附现有清单前 10 条 + 逐字引用指引，manage_prompts 0 匹配回显
// 名单先例同形；清单为空时直接说明库空，不给空名单）
export function composeSkillNoHit(items: SkillBriefItem[], name: string): string {
  if (items.length === 0) {
    return '技能库为空，没有可以加载的技能。';
  }
  const previewCount: number = Math.min(10, items.length);
  const lines: string[] = [];
  for (let i: number = 0; i < previewCount; i++) {
    lines.push('[' + (i + 1).toString() + '] ' + items[i].name);
  }
  const head: string = previewCount === items.length ?
    '当前技能库全部 ' + items.length + ' 个：' :
    '当前技能库前 ' + previewCount + ' 个（共 ' + items.length + ' 个）：';
  return '没有名为「' + name.trim() + '」的技能可加载。现有技能：\n' + head + '\n' +
    lines.join('\n') + '\n请从系统提示词的可用技能清单里逐字复制名称后再调用。';
}

// 多命中回执（库层无重名约束，同名两件时无法确定加载哪一件——如实拒并指出这是重名问题）
export function composeSkillMultiHit(hits: string[]): string {
  return '有 ' + hits.length + ' 个同名技能，无法确定加载哪一个，本次未加载。命中项：\n' +
    hits.join('\n') + '\n请让用户在 设置 → 技能库 里改名区分后再试。';
}

// ── manage_skills 管理族（2026-09-16 技能管理工具笔）已拆出至 SkillManageText.ets ──
//（校验归位 / 改名判重定位 / list 索引回执 / update 回执四件——本文件并入该族曾达 1235 行
// 越 1200 硬线，宪法域级最小拆分条款执行迁出；清单描述摘要 manifestDesc 仍在本域供其引用，
// 单向依赖无环。拆分缘由与断言拼接通道见该文件头注释）

// ── SKILL.md 序列化（导出，方案 §2.6）──
// 形态 = YAML frontmatter（name / description 两键）+ 空行 + 正文原文——与 Agent Skills
// 开放规范同形，导出的文件外部工具可直接读取
export function serializeSkillMd(doc: SkillDocItem): string {
  return '---\nname: ' + yamlScalar(doc.name) + '\ndescription: ' +
    yamlScalar(doc.description) + '\n---\n\n' + doc.content;
}

// YAML 标量包裹（方案 §2.6 的「description 含冒号等特殊字符时双引号包裹」——name 同一
// 函数处理，理由 = 名称里的冒号同样会把 frontmatter 解析带偏，两键同规比单键特判更不易漏）：
// 含 ':' '#' '"' '\'' 反斜杠、换行、首尾空白，或以 YAML 指示符（- ? [ ] { } & * ! | > % @ ` ,）
// 开头时用双引号包裹并转义；其余原样输出（普通中文名不被引号污染，外部工具读起来清爽）
export function yamlScalar(value: string): string {
  if (!needsYamlQuote(value)) {
    return value;
  }
  let escaped: string = '';
  for (let i: number = 0; i < value.length; i++) {
    const ch: string = value.charAt(i);
    if (ch === '"' || ch === '\\') {
      escaped += '\\' + ch;
    } else if (ch === '\n') {
      escaped += '\\n';
    } else if (ch === '\r') {
      escaped += '\\r';
    } else if (ch === '\t') {
      escaped += '\\t';
    } else {
      escaped += ch;
    }
  }
  return '"' + escaped + '"';
}

// YAML 类型化标量（2026-09-13 独立探针补：跨客户端互读时，裸值会被 YAML 隐式类型解析
// 「吃掉」字符串语义——PyYAML 实测 123→int、true→bool、null/~→None、0012→八进制 10、
// .nan→float、2026-09-13→date。本应用自读无害（parseSkillMd 取原始文本），但导出件是给
// 外部 Agent Skills 客户端读的，故这几类一律加引号锁成字符串）。判据按 YAML 1.1/1.2 核心
// schema 的隐式解析规则收窄：布尔/空值词表、数字（十进制含前导零与下划线、十六进制、
// 指数）、无穷与 NaN、ISO 日期时间、文档结束标记
const YAML_TYPED_SCALARS: RegExp[] = [
  /^(?:true|false|yes|no|on|off|null|~)$/i,
  /^[-+]?(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][-+]?\d+)?$/,
  /^[-+]?0[xX][0-9a-fA-F_]+$/,
  /^[-+]?\.(?:inf|nan)$/i,
  /^\d{4}-\d{1,2}-\d{1,2}(?:[Tt ].*)?$/,
  /^\.\.\.$/
];

const YAML_INDICATORS: string = '-?:,[]{}#&*!|>\'\"%@`';
// ★ 全角冒号一并计入触发集：中文写作里「步骤：先做 A」是全角冒号，YAML 规格上它并非指示符
// （不引号也不会解析错），但本工程导出的技能文件主要给中文用户看与被外部工具搬运，统一包裹
// 的代价为零（双引号包裹恒为合法 YAML）而「有的冒号包、有的不包」反而是难解释的形态差异
const YAML_SPECIALS: string = ':#\'"\\\n\r\t：';

function needsYamlQuote(value: string): boolean {
  if (value === '') {
    return true; // 空值裸写会让 frontmatter 该键变成 null 语义——显式 '""' 更明确
  }
  if (value.trim() !== value) {
    return true; // 首尾空白：YAML 折叠规则会吃掉
  }
  for (let i: number = 0; i < value.length; i++) {
    const ch: string = value.charAt(i);
    if (YAML_SPECIALS.indexOf(ch) >= 0) {
      return true;
    }
    if (i === 0 && YAML_INDICATORS.indexOf(ch) >= 0) {
      return true;
    }
  }
  for (const pattern of YAML_TYPED_SCALARS) {
    if (pattern.test(value)) {
      return true; // 会被 YAML 隐式类型解析成非字符串——加引号锁语义
    }
  }
  return false;
}
