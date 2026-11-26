// 技能文本纯函数域：参数校验归位 /「可用技能」清单拼装（双封顶贪心 + 省略尾注）/ 技能名
// 三态定位 / use_skill 回执结构化标签 / 启用清单解析与序列化——零 import 纯函数约束
//（scripts/assert-skill-domain.mjs 复制本文件为 .ts 直跑；IO 编排在 SkillDb / ToolSkill /
// SkillEditPage，不在本域）。SKILL.md 文档族已外迁 SkillMdIo.ets——单向依赖 SkillMdIo →
// 本件，本件不反向 import。
//
// ★ 四层分工：工具能做什么（ToolTypes 注册表）/ 技能是怎么做的流程（本域 与 skills 表）/
// 提示词是身份与规则（prompt_templates）/ 记忆是用户的事实（memories）。
//
// ★ 与 tools 列的语义分界（本域最易被后人按错口径改坏的一点）：assistants.tools 的 ''
// = 默认集合（内置 defaultEnabled 项全上）；assistants.skills 的 '' = **空集合**（默认不
// 启用任何技能）。故 parseEnabledSkillIds 与 parseEnabledToolIds 形态相似而语义相反，
// **禁合并复用**（各留一份 = 有意为之，不是重复代码）。
//
// ★ 模型可见面边界（负向钉）：技能**正文**永不进 system 提示词——system 里只有「可用
// 技能」清单（名称 + 触发描述），正文经 use_skill 工具结果通道按需加载。

// ── 上限常量族（拍板值；前两值对齐官方规范）──
// 名称上限（技能库页输入 maxLength 与本域校验同源）。**64 = 官方 Agent Skills 规范 name
// 上限**（agentskills.io/specification；原取 50 紧值会拒掉规范合规的外部包）。★ 有意
// **只对齐长度、不对齐字符集**：官方限小写字母/数字/连字符是面向目录标识符的约束；本应用
// 技能名是中文可读名（且是 use_skill 的逐字定位键），强套字符集会判中文技能名非法——属
//**不可对齐项**，勿当遗漏。字符面唯一一处拒绝 = 换行族（LINE_BREAK_CHARS）
export const SKILL_NAME_MAX: number = 64;
// 触发描述上限（进系统提示词清单的主字段）。**1024 = 官方规范 description 上限**（原取
// 200 紧值同因拒合规包而放开）。代价如实记：描述是清单预算的主成分，最坏单条 = 3 + 64 +
// 1024 = 1091 < 2000，上界仍由 composeSkillManifest 的贪心选取 + 省略尾注兜底（不越线）
export const SKILL_DESC_MAX: number = 1024;
// 正文上限（技能说明书全文，≤ clipToolResult 8192 保证单次加载不被截断）
export const SKILL_CONTENT_MAX: number = 8000;
// 单助手启用技能数上限（第 11 个开关面直接拒——上限执行在助手技能页）
export const SKILL_ENABLED_MAX: number = 10;
// 「可用技能」清单块字符上限（贪心选取 + 省略尾注兜底——清单常驻每次请求，token 有界）
export const SKILL_MANIFEST_MAX_CHARS: number = 2000;
// ★ 清单内**每行描述的截断档**（决明「可」）：不加此档时，官方上限态下 10 条启用技能要
// ~11K 字才装得全（实测 1024 字档只进 **1 条**，其余全靠省略尾注遮掉）——「启用了却看不见」
// 比「看见一个截断的描述」更坏。截 120 字后：**启用满 10 条恒全部可见**（最坏行 = 2 + 名称
// 64 + 1 + 120 + 1 = 188 字，10 行 + 头行 + 尾注预留 = 1946 ≤ 2000），总量 2000 不动。
// 依据：120 字 ≈ 官方「每技能约 100 token 元数据」量级；清单是路由索引，正文另有 use_skill
// 通道按需加载全文——**截断只发生在喂给模型的这一份**，库内值 / 编辑页 / 导入审阅显示的
// 都是描述全文
export const SKILL_MANIFEST_DESC_MAX: number = 120;
// 技能库总量上限（宪法「数据有界」；insert 超限拒绝 + 中文提示）
export const SKILL_TOTAL_MAX: number = 50;
// manage_skills list 分页常量已随管理族拆出至 SkillManageText.ets，本域不再承载

// ── 清单（模型面，头行定稿）──
// 头行即调用引导：工具 desc 与头行两处同说「清单是路由表，正文另调工具取」——缺任一
// 模型都可能只读清单不加载正文
export const SKILL_MANIFEST_HEADER: string =
  '可用技能（任务与触发描述匹配时，先调用 use_skill 加载对应技能正文再作答）';
// 双封顶截断尾注（照 MEMORY_BLOCK_OMIT_NOTE 先例）。尾注用动态计数（注入链治理 P0-b）：
// 「启用了却看不见」的另一半由「名字在 use_skill 的 name.enum 里全量在场」兜底——模型缺的
// 只是「这名是干什么的」，明确告知按名调 use_skill 即得描述。N 由 composeSkillManifest
// 按省略数动态传入
export function skillManifestOmitNote(omittedCount: number): string {
  return '（另有 ' + omittedCount + ' 个技能，描述已省略，可按名加载）';
}

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

// 校验归位结果（ok = false 时 error 为中文原因）
export interface SkillArgsValidation {
  ok: boolean;
  name: string;
  description: string;
  content: string;
  error: string;
}

function rejectSkillArgs(error: string): SkillArgsValidation {
  return { ok: false, name: '', description: '', content: '', error: error };
}

// ── 换行类字符集（单一来源：名称/件名拒收 + 清单描述折叠 + 导入警告件名显示 三面共用）──
// 整族七字符 = Unicode 换行属性全集（\r \n VT FF NEL LS PS）。三处消费面是**同一个**结构
// 问题——清单与附件清单都是逐行文本、名称与件名都是逐字定位键，只收部分字符会留下「同一
// 危害面用不同字符集」的自相矛盾。边界外的 \t 不在此列——属空白不属换行，收了误伤
const LINE_BREAK_CHARS: string = '\r\n\u000b\u000c\u0085\u2028\u2029';
// 折叠版（连续换行合并为一个空格；g 旗标只喂 replace——无 test() 的 lastIndex 残留陷阱）
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
// · name / content —— 关键字段，空或超限**报错**（保存链据此 toast，不静默截断用户输入）
// · description —— 可选项，允许空（空描述 = 清单行只剩名字，模型仍可按名字猜），超限报错
export function validateSkillArgs(name: string, description: string,
  content: string): SkillArgsValidation {
  const trimmedName: string = name.trim();
  const trimmedDesc: string = description.trim();
  const trimmedContent: string = content.trim();
  if (trimmedName === '') {
    return rejectSkillArgs('技能名称不能为空');
  }
  // ★ 名称拒换行（决明拍板）：名称是「可用技能」清单逐行路由表的行首与 use_skill 的
  // trim 逐字定位键，含换行会把一条技能拆成两行、逐字复制指引失灵。名称侧不走折叠（折叠
  // = 静默改名，库名与定位键必须逐字一致），故取明确拒；判据 = **整族七字符**
  //（LINE_BREAK_CHARS，与件名判据、描述折叠共用；RFC 8259 允许 LS/PS 在 JSON 字面出现 →
  // 模型 tool call 与 SKILL.md 导入链均可达）。拒 + 中文报因让模型换名重试——与「越界
  // 明确拒不静默截断」同口径
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
    content: trimmedContent, error: '' };
}

// 启用集解析（assistants.skills 列 JSON 串 → id 数组）：
// '' / 坏 JSON / 非数组 → **空数组**（= 默认不启用任何技能，与 tools 列语义相反，见头注释）；
// 只收非空字符串项；去重（重复 id 会让「已启用 N 个」与第 11 个拒绝的门槛失真）
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

// ── 单条消息指定技能 ──
// 指定技能 id 并入本轮 id 集：'' → 原集原样返回（零指定零开销）；已在集内 → 不重复
//（去重口径与 parseEnabledSkillIds 一致）；其余 → 追加。纯函数、零 import
export function appendDesignateId(ids: string[], designateId: string): string[] {
  if (designateId === '' || ids.includes(designateId)) {
    return ids;
  }
  return ids.concat([designateId]);
}

// 气泡/协议标注句（'' → 空串，不产空段）。显示面用它；协议面只在「用户零文本」时代位（见
// ChatSendCtrl.dispatchSend）——不重复正文块里的技能名
export function composeSkillDesignateMark(name: string): string {
  return name === '' ? '' : '〔本条指定技能：' + name + '〕';
}

// 多段非空拼接（本轮文本合成单一入口——用户文本/附件标注/指定标注三值共用一处，防两处
// 漂移）：逐段过滤空串，'\n\n' 连接；全空回 ''。纯函数、零 import
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
// 联动清列，此处是**第二道保险**（双保险拍板）：旧备份导入、跨设备恢复、并发删除窗口都可能
// 留悬空 id，悬空 id 若进清单会让模型调用必然失败的技能
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
// 贪心（至少保 1 条——首条恒放行，照 selectMemoryEntries 先例；否则极窄预算下清单会退化成
// 空头行），超出的整条不进 + 尾注；每行描述走 manifestDesc 截断（截断后单行最坏 188 字，
// 首条恒放行护栏由「可达路径」变为「结构性冗余」兜底）
export function composeSkillManifest(items: SkillBriefItem[]): string {
  if (items.length === 0) {
    return '';
  }
  const lines: string[] = [];
  // ★ 预算里**恒预留省略尾注的位置**（= 头行 + 尾注前的换行 + 尾注本身）——尾注是「还有
  // 更多技能」的唯一说明，不能被自己顶出预算（实测曾差尾注那几字越线）。尾注动态计数后
  // 预留按**最长可能形态**（N 上界 = items.length - 1——首条恒放行后至少 1 条在场），
  // 含 N 尾注的总长恒 ≤ SKILL_MANIFEST_MAX_CHARS
  const maxOmitNote: string = skillManifestOmitNote(Math.max(items.length - 1, 1));
  let used: number = SKILL_MANIFEST_HEADER.length + 1 + maxOmitNote.length;
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
    block += '\n' + skillManifestOmitNote(items.length - lines.length);
  }
  return block;
}

// ── use_skill schema 动态拼装 ──
// 无 enum 的静态基线串（自 ToolSkill.ets 上移——本域零 import 是断言复制直跑的前提，反向
// 引用 ToolSkill 常量即成环；ToolSkill 侧转出别名 USE_SKILL_SCHEMA，桥桩零改动）。内容 =
// name 逐字引用指引 + 可选 file（不预读附件的官方要点由此闭环）
export const USE_SKILL_SCHEMA_BASE: string =
  '{"type":"object","properties":{"name":{"type":"string",' +
  '"description":"技能名称，逐字取自系统提示词可用技能清单"},"file":{"type":"string",' +
  '"description":"可选。要读取的附件文件名，逐字取自上次加载该技能时返回的 ' +
  'skill_resources 清单；不填则加载技能正文"}},"required":["name"]}';

// use_skill 的 name 参数动态 enum 版 schema（每请求重建——取值 = 当轮「助手启用技能 ∩
// 库内现存（含单条消息指定）」，与 composeSkillManifest 的 enabled 数组同一次计算同序，
// ChatSendCtrl.buildSkillContext 单点供给）。行为三态：
// ①names 非空 → 基线对象挂 properties.name.enum 后 JSON.stringify——**禁手拼串**（红线
//   R-B1：parseToolSchema 对坏 JSON 静默跳过该工具，拼串出错 = 模型彻底失去技能加载能力
//   且零报错；名字含引号/反斜杠/emoji 由 stringify 天然转义）；
// ②names 空 → 返回基线串同一份（零启用时工具本就不声明，此分支是防御与单源；「没有任何
//   技能时不要注册该工具」的官方 Tip 边界由调用面 hasEnabled 闸承接）；
// ③价值 = 给模型的闭集先验（上游不校验 enum 的端点仍靠回执自纠，不作上游保证）。
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

// 清单行内的描述截断（超 SKILL_MANIFEST_DESC_MAX 加省略号；档位依据见该常量注释）。
// 只影响清单这一份文本——库内值、编辑页回填、导入审阅显示的都仍是描述全文。
// ★ 两处收紧：①**换行折叠**——清单是逐行路由表，描述含换行会拆出游离续行（描述侧走
// **折叠**不走拒收——折叠只作用于喂模型的这一份，库内值原样）；②截断走 safeCutIndex
//（不劈代理对）。manage_skills 的 list 回执复用本函数（禁第二份截断实现，两面同口径）
export function manifestDesc(description: string): string {
  const flat: string = foldLineBreaks(description);
  return flat.length > SKILL_MANIFEST_DESC_MAX ?
    flat.substring(0, safeCutIndex(flat, SKILL_MANIFEST_DESC_MAX)) + '…' : flat;
}

// ════ 附件文件族：文件件常量 / 扩展名窄化白名单 / 件名校验 / 附件清单段 / 附件回执 /
// 件名三态定位 / 技能包（zip）条目路径映射（SKILL.md frontmatter 解析族已外迁
// SkillMdIo.ets）════

// 每技能附件件数上限（防无界；超限拒绝在文件编辑页「新建/上传」入口拦）
export const SKILL_FILE_MAX_COUNT: number = 10;
// 单件内容上限（< clipToolResult 8192——保证单次加载不被截断）
export const SKILL_FILE_CONTENT_MAX: number = 8000;
// 件名长度上限（含扩展名；UI 输入 maxLength 与本域校验同源）
export const SKILL_FILE_NAME_MAX: number = 60;

// 附件扩展名白名单（**独立窄化**：不复用 AttachmentUtil.TEXT_EXTS 全集——那份含 sh/bat/
// ps1/py/js 等脚本族，与本域「拒脚本语义」直接矛盾；本表只收无执行语义的纯数据/文档文本格式）
export const SKILL_FILE_EXTS: string[] = ['md', 'txt', 'csv', 'json', 'xml', 'yml', 'yaml',
  'toml', 'ini', 'log', 'html', 'htm'];

// 件名扩展名（小写、无点；无扩展名回 ''）。★ 有意自持而不 import AttachmentUtil.extOf
//——本域零 import 约束（断言脚本复制直跑）优先于复用一行小工具
export function skillFileExt(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 件名合法性（非空 + 不含换行类字符 + 长度 + 扩展名在白名单内——脚本族与二进制格式在此被拒）。
// 换行判与技能名同族同判据（附件清单段是逐行文本、件名是模型取件的逐字定位键）。本函数
// 现无应用侧消费方（仅断言消费），但口径必须与 validateSkillFileArgs 保持一致——防后人
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

// 附件件校验（并入参 = 名 + 正文；脏值不归位而是**明确拒**——件名决定了模型能否按名取到，
// 静默改名会让「清单里的名字」与「库里的名字」不一致）：
// · 件名空 / 含换行类字符 / 超长 / 扩展名不在白名单（含无扩展名、二进制、脚本族）→ 拒 + 中文原因
// · 正文空 / 超 SKILL_FILE_CONTENT_MAX → 拒（件名换行判主要兜导入链与粘贴——UI 单行输入
//   常态无换行路径）
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

// 解码乱码检出：上传/导入链一律以 UTF-8 强解字节（SkillPack 三个解码点），非 UTF-8 字节被
// 解码器替换成 U+FFFD 且不报错——GBK 中文文本或二进制伪装件「解码成功」却整体乱码。判据 =
//**出现替换字符即判**，按出现计数、不按占比：占比式对「千字 ASCII 混少量 GBK 汉字」漏判，
// 且比率式在阈值 0 下有恒真暗雷——计数式无此暗雷。由调用方给中文拒收；纯函数落在本零
// import 域。已知残限（有意不堵，防误当全覆盖）：UTF-16 无 BOM 且字节落在 ASCII 段解出的
// 是合法字符，本判据接不住（逐字节编码嗅探误伤面高于收益）；含真实 U+FFFD 的合法 UTF-8
// 件也会被拒（概率极低）
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

// use_skill 回执的附件清单段（正文之后追加，**只列名字不预读内容**——官方要点：附件可能
// 很大，预读进上下文是纯浪费；模型凭清单再发一次带 file 参数的调用取件）。files 空 → ''
//（调用方据此不追加）
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
// 缺口来源：正文顶格 8000 + 标签（约 40）+ 十个附件名（约 620）≈ 8660 > 8192，超线后
// clipToolResult 按尾截断，**被切的正是正文尾部**（说明书收尾步骤 = 任务执行依据）。
// 处置：不动任何拍板上限值，组装时**保正文、收窄清单**——清单是索引，少列几个名字模型
// 还能凭已列出的取件；正文被截则是依据直接丢失
export const SKILL_REPLY_MAX_CHARS: number = 8192;
// 清单收窄时的省略尾注（与 manifest 的省略尾注同族，但指向不同的补救路径——这个指到页面）
const SKILL_RESOURCES_OMIT_NOTE: string = '（其余附件因长度未列出，可在 设置 → 技能库 查看）';

// 附件清单段按预算收窄（budget = 该段可占用的字符数）：装不下就少列几个并加省略尾注；
// 连标签都放不下 / 一件名字都放不下 / 空数组三种形态都回 ''——语义恒为「只回正文，不产出
// 半个标签」，调用方零特判
function buildResourcesWithin(files: SkillFileItem[], budget: number): string {
  const openTag: string = '<skill_resources>';
  const closeTag: string = '</skill_resources>';
  // fixed 里**恒预留省略尾注的位置**（即使最终没省略）：否则「装下了第 N 行 → 因省略再补
  // 一段尾注」会把总长顶出预算——保守预留才有硬上界，代价是极端情况下少列一个名字，换来
  // 「绝不越线」这条可证保证
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
  // ★ **首行不再豁免预算**（原判据 `&& lines.length > 0` 让首行恒进块，是「绝不越线」的
  // 唯一破口——实测技能名 50 字 + 首件名 60 字 + 正文顶格 = 8219 > 8192 可复现）。一件名字
  // 都放不下 → 整段不追加，调用方只回正文——比回一段尾部会被下游裁掉半截的清单干净
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
// · 正文 ≤ 8000 恒完整（预算先扣正文与标签，剩余才给清单）——「单次加载不被截断」由本
//   函数承接，而非靠「8000 < 8192」一句话（那句在没有清单段时才成立）
// · 清单能全列就全列；列不全则收窄 + 省略尾注；files 空 → 只回正文
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
// 本函数的多命中态是**兜底**：导入旧包、并发写入窗口都可能造出同名件，此时如实拒歧义比按
// id 猜一条更安全
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

// ── 导入审阅文案 ──
// ★ 审阅弹窗（ConfirmDialog 的 message）是**无上限 Text**——预览文案须在纯函数层定量产出：
// 每段各自截断 + 段内条数封顶，最坏形态也有结构上界（SKILL_IMPORT_PREVIEW_MAX），安全提示
// 句恒在末尾恒不被截（「请确认内容可信」的唯一载体）
export const SKILL_IMPORT_PREVIEW_MAX: number = 700;
const IMPORT_EXCERPT_MAX: number = 200;
const IMPORT_DESC_MAX: number = 60;
const IMPORT_NAME_LIST_MAX: number = 5;
const IMPORT_NAME_MAX: number = 20;
const IMPORT_WARN_LIST_MAX: number = 3;
const IMPORT_WARN_MAX: number = 40;
// 批量预览的件列表条数档（多技能包审阅列出前 N 件，其余走「等 N 件」尾注——同「先保结构
// 上界、明细留给导入后的技能库」哲学）
const IMPORT_BATCH_LIST_MAX: number = 8;
// 警告条内**件名段**的收窄档（「保原因、压件名」）：件名可长到路径形态，从尾部截会把
// 「原因」整段吃掉——用户看见被切断的名字却不知道它为什么没进来。故按首个「：」分两段：
// 件名段收到本档（超出加省略号），原因段保留；单条渲染仍守 40 字档——**不上移任何档位，
// 只改裁剪方向**
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
// emoji 等增补平面字符占两个码元，按定长硬切会劈开一对、留下**孤立代理字符**（进文件路径
// 是非法名、进请求体 JSON 是非法 Unicode）。判据 = 末位落在高代理项（0xD800~0xDBFF）时
// 回退一位（低代理项开头必是合法配对，无需处理）
export function safeCutIndex(text: string, max: number): number {
  if (text.length <= max) {
    return text.length;
  }
  const last: number = text.charCodeAt(max - 1);
  return (last >= 0xD800 && last <= 0xDBFF) ? max - 1 : max;
}

export function composeImportPreview(input: SkillImportPreviewInput): string {
  const parts: string[] = [];
  // ★ 名称段同样截断——原实现唯它一段不设上界，超长名（外部包绕过校验的形态）能把预审
  // 文案顶过 SKILL_IMPORT_PREVIEW_MAX，而「最坏形态有结构上界」是本函数对外承诺。上界取
  // SKILL_NAME_MAX（此处是第二道，保证函数自身对任意输入成立）
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

// ── 多技能包审阅文案 ──
// 单个压缩包里装多件技能时（合集包 / GitHub 技能仓库 zip 下载），单件预览会随件数线性膨胀
// ——同样顶掉弹窗两键。故批量形态只列**件名与附件数**（正文逐件审阅留给导入后的技能库），
// 跳过项沿用单件预览的裁剪与封顶档（clipImportWarning），安全提示句照旧恒在末尾
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

// ── SKILL.md frontmatter 解析族与技能包目录名派生已拆出至 SkillMdIo.ets（函数体逐字
// 搬迁；单向依赖 SkillMdIo → 本件）。包内条目映射与技能根选取仍在本域 ──

// 包内条目语义（条目名 → 语义的**纯映射**）：
// · 'md' —— 'SKILL.md'，技能正文与元信息。**只有包根这一处**是主文件；子目录同名件是
//   普通资源，不特判
// · 'file' —— 其余非空路径 = 附件，fileName = 归一化后的件名
// · 'ignore' —— 空串 / 纯斜杠等退化形态（采集链恒非空，自身防御分支）
// ★ 契约：入参 = **相对 pack root 的路径**（「吃整条 zip 条目名 + 右对齐容错」已撤除——
//   那条容错的实际落点是 SkillPack.locatePackRoot）；接线 = SkillPack.collectPackFiles
//   递归遍历逐件调用它取名。
// ★ 归一化规则单源在本函数（SSOT）：剥一层 `files/` 前缀（`files/a.md` → `a.md`，老包
//   行为逐字不变）；`references/api.md` 原样保留（路径名是模型取件的唯一定位键，且技能内
//   件名硬查重，扁平化会让 references/a.md 与 assets/a.md 撞名）；**只剥一层**：
//   `files/files/a.md` → `files/a.md`，保证「导出 → 再导入」逐轮往返不叠层
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

// 包内技能根选取（纯函数——SkillPack 侧把包内全部 SKILL.md 相对路径喂进来，判定规则单源
// 在本函数）：输入 mdPaths = '/' 分隔的相对包根路径；输出 = 技能根目录清单（'' 表示包根），
// 按名字升序；空数组 = 无技能可导（调用方报「找不到 SKILL.md」）。规则三层，自上而下短路：
// ① 包根有 SKILL.md → ['']——单技能包形态不变（子目录同名件按附件采集，不特判）
// ② 一级子目录里有 SKILL.md 的 → 全部返回（≥2 个即多技能包）
// ③ 二级子目录（repo-main/skill-a/SKILL.md）→ 全部返回——GitHub zip 下载天然是「一层
//    仓库名 + 每技能一目录」，②落空时下钻这层
// 深于两层不认（扫描侧同界，见 SkillPack.collectSkillRoots）：认了会把附件目录里恰好
// 存在的 SKILL.md 误认成一件技能
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

// ── manage_skills 管理族已拆出至 SkillManageText.ets（校验归位 / 改名判重定位 / list 索引
// 回执 / update 回执四件——本文件并入该族曾越 1200 硬线，域级最小拆分迁出；清单描述摘要
// manifestDesc 仍在本域供其引用，单向依赖无环。拆分缘由见该文件头注释）──

// ── SKILL.md 序列化族（serializeSkillMd / yamlScalar / needsYamlQuote 与 YAML 类型化标量
// 判据）已拆出至 SkillMdIo.ets（函数体逐字搬迁；SkillDocItem 仍为本件导出，供其引用）──
