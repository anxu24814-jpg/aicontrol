// manage_memory 管理族纯函数域，自 MemoryText.ets 域级最小拆分迁出（宪法「新增功能域一律
// 先拆」），函数体逐字搬迁零行为变更；执行器 = common/providers/ToolMemoryManage.ets。
// · 本件带 import（MEMORY_CONTENT_MAX 自 ./MemoryText 单向引入，MemoryText 不反向引用，
//   无环）——断言侧走「剥 import + 前置 MemoryText 源拼接」先例直跑线上同一实现
//  （assert-app-domain.mjs / assert-skill-domain.mjs；同型先例 = SkillManageText）。
import { MEMORY_CONTENT_MAX } from './MemoryText';

// ── 记忆管理（manage_memory 工具纯函数面）──
// 定位：助手对长期记忆库的管理面——list 完整查看条数/内容/顺序 + create/update/delete 三写
//（含 delete，拍板 1：记忆删除无「N 会话引用」级联链，UI 记忆页有完整管理兜底）。本节只管
// 纯逻辑，DB 读写与广播编排在 ToolMemoryManage。**内容回执恒纯文本**（记忆条目本身是自然
// 语言文本，纯文本对模型最直接，不沿用 manage_prompts 的 JSON 载荷形态）。普通助手「记忆」
// 卡可开；控制台助手已退役不再可用本件（三层闸见 ToolTypes）。
// ★ 校验拒绝例外：validate 只管给出 {ok:false,error}——「请求不合法族」（解析失败/非法
// action/缺参/超限）由执行器包 error JSON 壳返回（出错态），「定位失败/空库」等业务拒绝仍
// 原样纯文本（完成态）；包装属执行器职责。文案规约不适用于模型面。
// ★ 定位方式 = 记忆原文精确匹配（拍板 2）：update/delete 的 content 与库内条目 trim 后逐字
// 相等才命中——0 命中回名单、≥2 命中拒歧义。弃 index 序号（连续删除下漂移删错条）与行 id
//（mem-<时间戳>-<序号> 模型不可抄）——回执里的原文即下次操作的定位键。

// list 分页口径（拍板 6）：默认 30 对齐注入窗口语义（与 MemoryText 的
// MEMORY_INJECT_MAX_COUNT 同值不同源——改注入窗口时须同查本常量）；上限 50
export const MEMORY_MANAGE_LIST_DEFAULT_COUNT: number = 30;
export const MEMORY_MANAGE_LIST_MAX_COUNT: number = 50;
// 页内总字数软顶：超则自动收窄本页条数（至少 1 条）——防 clipToolResult 8192 硬顶截尾丢翻页提示
export const MEMORY_MANAGE_PAGE_SOFT_CHARS: number = 6000;

// 校验结果（纯函数可断言）：ok = true 时 action 与对应参数就绪；offset/limit 为归一后值
export interface ManageMemoryValidation {
  ok: boolean;
  action: string;
  content: string;
  newContent: string;
  offset: number;
  limit: number;
  error: string;
}

function rejectManageMemory(error: string): ManageMemoryValidation {
  return { ok: false, action: '', content: '', newContent: '', offset: 1,
    limit: MEMORY_MANAGE_LIST_DEFAULT_COUNT, error: error };
}

// 参数校验纯函数：坏 JSON / 非法 action / create·update·delete 缺 content / update 缺
// new_content / 空、超 MEMORY_CONTENT_MAX 全拒；list 的 offset/limit 脏值归默认不报错
//（模型少一轮纠错）
export function validateManageMemoryArgs(argsJson: string): ManageMemoryValidation {
  let action: string = '';
  let content: string = '';
  let newContent: string = '';
  let offset: number = 1;
  let limit: number = MEMORY_MANAGE_LIST_DEFAULT_COUNT;
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawContent: Object | undefined = parsed['content'];
    const rawNewContent: Object | undefined = parsed['new_content'];
    const rawOffset: Object | undefined = parsed['offset'];
    const rawLimit: Object | undefined = parsed['limit'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawContent === 'string') {
      content = rawContent.trim();
    }
    if (typeof rawNewContent === 'string') {
      newContent = rawNewContent.trim();
    }
    if (typeof rawOffset === 'number' && Number.isInteger(rawOffset)) {
      offset = rawOffset;
    }
    if (typeof rawLimit === 'number' && Number.isInteger(rawLimit)) {
      limit = rawLimit;
    }
  } catch (e) {
    return rejectManageMemory('参数解析失败，需要 action 参数');
  }
  if (action !== 'list' && action !== 'create' && action !== 'update' && action !== 'delete') {
    return rejectManageMemory('action 必须是 list、create、update 或 delete');
  }
  // offset/limit 归一（脏值归默认——拍板 6）
  if (offset < 1) {
    offset = 1;
  }
  if (limit < 1) {
    limit = MEMORY_MANAGE_LIST_DEFAULT_COUNT;
  }
  if (limit > MEMORY_MANAGE_LIST_MAX_COUNT) {
    limit = MEMORY_MANAGE_LIST_MAX_COUNT;
  }
  if (action === 'create' || action === 'update' || action === 'delete') {
    if (content === '') {
      return rejectManageMemory('action 为 ' + action +
        ' 时需要 content 参数，值为目标记忆全文（update/delete 为要操作的原文）');
    }
    if (content.length > MEMORY_CONTENT_MAX) {
      return rejectManageMemory('content 超过 ' + MEMORY_CONTENT_MAX + ' 字上限，当前 ' +
        content.length + ' 字，请精简');
    }
  }
  if (action === 'update') {
    if (newContent === '') {
      return rejectManageMemory('action 为 update 时需要 new_content 参数，值为修改后的记忆全文');
    }
    if (newContent.length > MEMORY_CONTENT_MAX) {
      return rejectManageMemory('new_content 超过 ' + MEMORY_CONTENT_MAX + ' 字上限，当前 ' +
        newContent.length + ' 字，请精简');
    }
  }
  return { ok: true, action: action, content: content, newContent: newContent,
    offset: offset, limit: limit, error: '' };
}

// 管理条目（定位与回执需要的最小行形态——不引 DB 类型，执行器以 MemoryRow 适配）
export interface MemoryManageItem {
  id: string;
  content: string;
}

// 定位结果三态：unique = 唯一命中（hitId/hitContent 就绪）；none = 零命中；multi = 多命中
//（hits = 全部命中条渲染行 '[全库序号] 原文'，供回执列出区分）
export interface MemoryLocateOutcome {
  state: string; // 'unique' | 'none' | 'multi'
  hitId: string;
  hitContent: string;
  hits: string[];
}

// 原文精确匹配定位（拍板 2）：两侧 trim 后逐字相等才命中；items = 库序（queryMemories 三键）
export function locateMemoryByContent(items: MemoryManageItem[],
  content: string): MemoryLocateOutcome {
  const needle: string = content.trim();
  const hits: string[] = [];
  let hitId: string = '';
  let hitContent: string = '';
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].content.trim() === needle) {
      if (hitId === '') {
        hitId = items[i].id;
        hitContent = items[i].content;
      }
      hits.push('[' + (i + 1).toString() + '] ' + items[i].content);
    }
  }
  if (hits.length === 0) {
    return { state: 'none', hitId: '', hitContent: '', hits: [] };
  }
  if (hits.length > 1) {
    return { state: 'multi', hitId: '', hitContent: '', hits: hits };
  }
  return { state: 'unique', hitId: hitId, hitContent: hitContent, hits: [] };
}

// 定位失败回执（纯文本错误态，执行器原样返回）：none 附库前 10 条清单 + 逐字引用指引
//（manage_prompts 0 匹配回显名单先例同形）；multi 列出全部命中条 + 区分指引
export function composeMemoryManageNoHit(items: MemoryManageItem[]): string {
  if (items.length === 0) {
    return '记忆库为空，没有可以修改或删除的记忆。';
  }
  const previewCount: number = Math.min(10, items.length);
  const lines: string[] = [];
  for (let i: number = 0; i < previewCount; i++) {
    lines.push('[' + (i + 1).toString() + '] ' + items[i].content);
  }
  const head: string = previewCount === items.length ?
    '当前库全部 ' + items.length + ' 条：' :
    '当前库前 ' + previewCount + ' 条（共 ' + items.length + ' 条）：';
  return '没有找到这条记忆——content 必须与库内某条记忆的原文逐字一致。\n' + head + '\n' +
    lines.join('\n') + '\n请先用 list 查看全部记忆，再逐字引用要操作的那条原文。';
}

export function composeMemoryManageMultiHit(hits: string[]): string {
  return '有 ' + hits.length + ' 条内容完全相同的记忆，无法确定要操作哪一条，本次未执行。全部命中条：\n' +
    hits.join('\n') + '\n请让用户补充更长的原文片段以区分，或指引用户在 设置 → 记忆 手动处理。';
}

// list 回执（纯文本；items = 库序，编号 = 全库序号——翻页连续〔offset=31 起的本页从 [31]
// 编起〕、与注入序同源，禁页内 1..K 重编号；单条全显不截断——「完整查看内容」是需求点）。
// offset/limit 脏值在此二次归一（含 offset ≤ total 收口——越过末页的 offset 收到末条，
// 模型恒见内容不落空页）
export function composeMemoryManageList(items: MemoryManageItem[], offset: number,
  limit: number): string {
  const total: number = items.length;
  if (total === 0) {
    return '记忆库为空。';
  }
  let start: number = offset < 1 ? 1 : offset;
  if (start > total) {
    start = total;
  }
  let count: number = limit < 1 ? MEMORY_MANAGE_LIST_DEFAULT_COUNT : limit;
  if (count > MEMORY_MANAGE_LIST_MAX_COUNT) {
    count = MEMORY_MANAGE_LIST_MAX_COUNT;
  }
  // 页内切片 + 软顶收窄：累计字数超软顶即止（首条恒放行——至少 1 条）
  const lines: string[] = [];
  let shown: number = 0;
  let used: number = 0;
  while (shown < count && start - 1 + shown < total) {
    const item: MemoryManageItem = items[start - 1 + shown];
    const line: string = '[' + (start + shown).toString() + '] ' + item.content;
    if (shown > 0 && used + line.length > MEMORY_MANAGE_PAGE_SOFT_CHARS) {
      break;
    }
    lines.push(line);
    used += line.length;
    shown++;
  }
  const lastShown: number = start - 1 + shown;
  const parts: string[] = ['共 ' + total + ' 条记忆，按注入顺序排列（序号小先注入）。本页第 ' +
    start + '~' + lastShown + ' 条：'];
  parts.push(lines.join('\n'));
  if (shown < count && lastShown < total) {
    parts.push('本页因长度限制只显示前 ' + shown + ' 条');
  }
  if (lastShown < total) {
    parts.push('还有 ' + (total - lastShown) + ' 条，可用 offset=' + (lastShown + 1) + ' 继续');
  } else {
    parts.push('已到末尾');
  }
  parts.push('注：会话自动注入时最多携带前 ' + MEMORY_MANAGE_LIST_DEFAULT_COUNT + ' 条。');
  return parts.join('\n');
}

// 四写回执（纯文本——回执即向用户复述改了什么的载体；create 回执的原文用调用方传入的
// content 归一值，库内行即此串）
export function composeMemoryManageCreateReply(content: string, totalAfter: number): string {
  return '已新增记忆（现共 ' + totalAfter + ' 条）：\n' + content;
}

export function composeMemoryManageUpdateReply(oldContent: string, newContent: string): string {
  return '已修改记忆：\n旧：' + oldContent + '\n新：' + newContent;
}

export function composeMemoryManageDeleteReply(content: string, remaining: number): string {
  return '已删除记忆：\n' + content + '\n现剩余 ' + remaining + ' 条。';
}
