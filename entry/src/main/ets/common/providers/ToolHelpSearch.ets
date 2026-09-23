// 帮助中心检索工具域（2026-09-08 自 ToolTypes.ets 域级最小拆分外迁——债务条登记的候选缝
// 之二，域 157 行整体迁出）。
// 一个内置工具 search_help（2026-09-05 控制台助手）：帮助中心本地检索——帮助全文不进
// 提示词，检索时本地分片取（CherryStudio「Cherry 小助手」进程内工具分片取数同构）；
// defaultEnabled=false 不进普通助手默认集合，注册与工具名常量归口 ToolTypes.ets。
// 检索纯函数自包含（groups 由调用方注入 HELP_GROUPS——零 DB 零网络零状态，断言脚本剥 TS
// 求值直跑）；零命中空态 note 教模型如实说明不编造（A3 教训）。
import { HELP_GROUPS, HelpGroup, HelpItem } from '../HelpContent';
import { ToolExecutor } from './ToolContracts';
// ── 帮助中心检索（2026-09-05 控制台助手；CherryStudio「Cherry 小助手」进程内工具分片
//   取数同构——帮助全文不进提示词，检索时本地分片取）──

// 检索结果条目（id = 分组标题::条目标题，与帮助中心页 push 参数同源，findHelpTopic 可还原）
export interface HelpSearchResult {
  id: string;
  title: string;
  desc: string;
  detail: string[];
}

// 检索工具结果载荷（results 空时带 note 教模型如实说明——A3 教训复用：空载荷须可感知）
interface HelpSearchPayload {
  query: string;
  results: HelpSearchResult[];
  note: string;
}

// 打分中间态（title 命中权重 3 / desc 2 / detail 1——标题即功能名命中最强）
interface HelpScoredItem {
  item: HelpItem;
  groupTitle: string;
  score: number;
}

// 检索停用词（疑问/口语助词，全局剥离——两字以上组合在词中间出现率低，剥断安全）；
// 单字助词另表（词中常见不可全局剥：「不存在」剥「在」会截出假词「存在」），只在
// 切词后按独立词过滤
const HELP_QUERY_STOPWORDS: string[] = ['为什么', '怎么', '怎样', '如何', '为啥', '为何',
  '哪里', '哪儿', '什么', '啥', '请问', '告诉我', '我想问', '我想', '我要', '能不能',
  '可不可以', '可以'];
const HELP_QUERY_DROP_CHARS: string[] = ['吗', '呢', '吧', '啊', '的', '了', '么', '是', '在'];

// 检索同义词组（双向：query 词含组内任一词 → 组内其余词一并入检索词——补 2-gram 覆盖
// 不了的中英与词根差异；2026-09-05 真机实锤后补，克制小表，命中不足再扩）
const HELP_SYNONYM_GROUPS: string[][] = [
  ['key', '密钥'],
  ['删除', '删掉', '移除'],
  ['图片', '照片', '图像'],
  ['语音', '音频'],
  ['联网', '上网', '网络搜索'],
  ['更换', '切换', '换']
];

// 检索词生成（query → terms）：小写归一（「key」须能命中「Key」）→ 停用词剥离 →
// 空白切词 → 同义词扩展 + 2 字滑窗泛化。★ 中文整句无空格，单纯空白切词整句成一个词，
// 子串匹配几乎必失败（2026-09-05 真机实锤：问「怎么换模型」零命中）——2-gram 滑窗是
// 中文朴素泛化的最小解，条目规模下足够（Cherry 同款朴素匹配思路）
function helpSearchTerms(query: string): string[] {
  let stripped: string = query.toLowerCase();
  for (const word of HELP_QUERY_STOPWORDS) {
    stripped = stripped.split(word).join(' ');
  }
  const terms: string[] = [];
  const seen: Set<string> = new Set<string>();
  const push = (t: string): void => {
    const v: string = t.trim();
    if (v !== '' && !seen.has(v)) {
      seen.add(v);
      terms.push(v);
    }
  };
  for (const part of stripped.split(/\s+/)) {
    if (part === '' || HELP_QUERY_DROP_CHARS.includes(part)) {
      continue;
    }
    push(part);
    for (const group of HELP_SYNONYM_GROUPS) {
      for (const syn of group) {
        if (part.includes(syn)) {
          for (const other of group) {
            push(other);
          }
          break;
        }
      }
    }
    for (let i: number = 0; i + 2 <= part.length; i++) {
      push(part.substring(i, i + 2));
    }
  }
  return terms;
}

// 帮助条目检索纯函数（自包含：groups 由调用方注入 HELP_GROUPS——零 DB 零网络零状态，
// 断言脚本剥 TS 求值后直接跑同款姿势）：terms 经 helpSearchTerms 生成后逐词三段小写
// includes 匹配；零命中返回空数组，空态语义由执行器包装
export function searchHelpTopics(groups: HelpGroup[], query: string,
  limit: number = 5): HelpSearchResult[] {
  const terms: string[] = helpSearchTerms(query);
  if (terms.length === 0) {
    return [];
  }
  const scored: HelpScoredItem[] = [];
  for (const group of groups) {
    for (const item of group.items) {
      let score: number = 0;
      const title: string = item.title.toLowerCase();
      const desc: string = item.desc.toLowerCase();
      const detailAll: string = item.detail.join('\n').toLowerCase();
      for (const term of terms) {
        if (title.includes(term)) {
          score += 3;
        }
        if (desc.includes(term)) {
          score += 2;
        }
        if (detailAll.includes(term)) {
          score += 1;
        }
      }
      if (score > 0) {
        scored.push({ item: item, groupTitle: group.title, score: score });
      }
    }
  }
  scored.sort((a: HelpScoredItem, b: HelpScoredItem): number => b.score - a.score);
  const results: HelpSearchResult[] = [];
  const count: number = Math.min(scored.length, limit);
  for (let i: number = 0; i < count; i++) {
    const top: HelpScoredItem = scored[i];
    results.push({
      id: top.groupTitle + '::' + top.item.title, title: top.item.title,
      desc: top.item.desc, detail: top.item.detail
    });
  }
  return results;
}

// 帮助中心检索执行器（控制台助手核心能力）：query 空守卫 + 结构化输出（detail 全文
// 供模型给出准确入口路径）；零命中带 note 指引模型如实说明不编造（A3 教训）
export class SearchHelpExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    let query: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    if (query === '') {
      return Promise.resolve(JSON.stringify({ error: '检索关键词不能为空' }));
    }
    const results: HelpSearchResult[] = searchHelpTopics(HELP_GROUPS, query);
    const payload: HelpSearchPayload = {
      query: query,
      results: results,
      note: results.length === 0
        ? '帮助中心没有匹配条目。建议换更短的关键词再调用一次，例如功能名或界面上的按钮名。仍没有则如实告知用户没有找到，指引用户前往 设置 → 更多信息 → 帮助中心 浏览全部条目，不要编造操作步骤。'
        : ''
    };
    return Promise.resolve(JSON.stringify(payload));
  }
}
