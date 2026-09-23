// 提示词变量替换域（2026-09-01 助手域配套，调研结论落地——docs/调研与待办-助手与提示词
// 变量.md「提示词变量」节）：注入提示词内 {{token}} 占位符在**发送前由应用层字符串替换**为静态文本
//（模型看到的已是替换后的文本）。★ 能力归属调研定论：变量替换是纯应用层能力——与手机
// 厂商无关（鸿蒙无需任何特殊系统支持）、与 LLM 服务商无关（OpenAI/Anthropic/Google 的
// Chat API 均无原生提示词模板变量语法；claude.ai/ChatGPT 官方产品也是自家服务端字符串
// 替换）；**不需要工具调用**（function calling 是另一条路线——模型主动查时间，适用于
// 时间推算类需求，业界（Open WebUI/SillyTavern/LobeChat/Cherry Studio）变量功能全部为
// 发送前替换，无一例外）。
// 语法 {{token}} 双花括号 = 全业界事实标准；未识别/无值变量保留原样（Open WebUI 同款）。
// ★ 零 import 纯函数约束（SseParser/RequestCompose 同款）：本文件禁 import 任何模块——
// node 类型剥离直跑（sse-assert ⑳ 组线上同一实现断言）；设备侧上下文（语言）由调用方
// 传入，本域不做 IO。替换对任意注入源统一生效（助手/会话提示词/系统提示词），调用唯一
// 落点 = ChatPromptState.applyVariables。
// 变量集（第一梯队——多家业界先例 + 明确聊天价值；日期一律 ISO 格式：LobeChat 按 locale
// 格式化出美式日期的教训）：date/time/weekday/datetime/timezone/language/model_name/char。

// 变量描述（UI 展示与插入用——助手编辑页变量卡 chips 数据源；sample = 展示样例非实测值）
export interface PromptVariableInfo {
  token: string;
  label: string;
  sample: string;
}

export const PROMPT_VARIABLES: PromptVariableInfo[] = [
  { token: '{{date}}', label: '日期', sample: '2026-09-01' },
  { token: '{{time}}', label: '时间', sample: '14:30' },
  { token: '{{weekday}}', label: '星期', sample: '星期二' },
  { token: '{{datetime}}', label: '日期时间', sample: '2026-09-01 14:30' },
  { token: '{{timezone}}', label: '时区', sample: 'UTC+08:00' },
  { token: '{{language}}', label: '系统语言', sample: 'zh-Hans-CN' },
  { token: '{{model_name}}', label: '当前模型', sample: 'deepseek-chat' },
  { token: '{{char}}', label: '助手名称', sample: '翻译助手' }
];

// 变量 token 追加（UI 插入区点按的共用语义——SystemPromptPage/AssistantPromptPage 两页
// 单一来源）：内容空或末尾已是空白（空格/换行）→ 直接追加；否则补一空格分隔。★ 2026-09-01
// 收敛原因：该语义曾两页各持一份，「换行结尾不补多余空格」修正需两处手改——漂移过一次，
// 收敛纯函数防再漂（sse-assert ⑳ 组线上断言）
export function appendVariableToken(content: string, token: string): string {
  return content === '' || /\s$/.test(content) ? content + token : content + ' ' + token;
}

const WEEKDAY_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

// 全部替换（split/join 逐 token——无正则依赖，确定性）：value 为空串时保留原 token
// （{{char}} 无助手语境、{{model_name}} 无连接时不应替换成空）
function replaceToken(content: string, token: string, value: string): string {
  if (value === '') {
    return content;
  }
  return content.split(token).join(value);
}

// 变量替换主函数（发送前调用，每次发送取当下时刻——不是页面加载时）：
// modelName = 当前连接模型 id；language = 系统语言（i18n，调用方传入）；charName = 助手名
// （非助手注入时传 ''，{{char}} 保留原样）；now = 时刻（参数化 = 断言可注入固定时刻）
export function substitutePromptVariables(content: string, modelName: string, language: string,
  charName: string, now: Date): string {
  const year: number = now.getFullYear();
  const month: string = pad2(now.getMonth() + 1);
  const day: string = pad2(now.getDate());
  const date: string = year + '-' + month + '-' + day;
  const time: string = pad2(now.getHours()) + ':' + pad2(now.getMinutes());
  // getTimezoneOffset = UTC − 本地（分钟，UTC+8 → -480）；取反得东经偏移
  const offset: number = -now.getTimezoneOffset();
  const sign: string = offset >= 0 ? '+' : '-';
  const absOffset: number = Math.abs(offset);
  const timezone: string = 'UTC' + sign + pad2(Math.floor(absOffset / 60)) + ':' +
    pad2(absOffset % 60);
  let result: string = content;
  result = replaceToken(result, '{{date}}', date);
  result = replaceToken(result, '{{time}}', time);
  result = replaceToken(result, '{{weekday}}', '星期' + WEEKDAY_NAMES[now.getDay()]);
  result = replaceToken(result, '{{datetime}}', date + ' ' + time);
  result = replaceToken(result, '{{timezone}}', timezone);
  result = replaceToken(result, '{{language}}', language);
  result = replaceToken(result, '{{model_name}}', modelName);
  result = replaceToken(result, '{{char}}', charName);
  return result;
}
