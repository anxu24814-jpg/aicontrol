// env_list 工具域（2026-09-30 方案-HTTP工具完善 批 2 笔 1）：返回当前助手可用的 HTTP
// 凭据**名称 + 用途说明清单**（global 组 + 助手组，结构见 HttpCredentials.EnvCredGroups；
// 说明为用户在凭据编辑页填的可选备注，2026-10-07 凭据编辑页笔起随回执给模型——帮模型
// 选对凭据；说明不参与 {{名称}} 解析，引用仍按名称）。
// ★ 值永不出现在对话（硬边界，决明 2026-09-30 拍板）：工具回执会进聊天历史、随对话发
//   服务商——本工具只返回名称与用途说明；模型凭清单在 http_request 的 headers 值 / URL
//   query 参数值里写 {{名称}}，应用发出前替换真值（注入在 ToolHttp 传输层、reqLogBegin
//   之后，日志与卡面恒记模型原始输入）。同名时助手级优先于全局。
// ★ 模式驱动第三件（search_memory / use_skill 之后）：不走 assistants.tools 启用清单、
//   工具页不出页——助手启用清单含 http_request 时由 ChatContextUsage.collectTools 追加
//   声明（与 http_request 同进退：没开 HTTP 工具的助手用不到凭据，查名工具对它也无意义；
//   不占开关位 = HTTP 卡卡态不虚报，方案档「批 2 开工定案」①）。
// ★ 零改提示词纪律（控制台助手红线）：能力单源在本 desc——http_request 的 desc 侧另补
//   一句引用语法指引（同笔），无 system prompt 改动。
// 契约纪律：本件只 import 叶子（ToolContracts / MessageContracts）与同层凭据域
//（HttpCredentials），禁引 ToolTypes（坑50）。
import { ToolExecutor } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { credentialNameGroups, EnvCredGroups, EnvCredItem } from './HttpCredentials';

// 回执形态（note 两组全空时替换为指路句——回执恒可读，模型不猜语义）
interface EnvListReceipt {
  credentials: EnvCredGroups;
  note: string;
}

// 装填结果（预算内保留的两组条目 + 被省略条数）
interface FittedEnvGroups {
  kept: EnvCredGroups;
  omitted: number;
}

// 回执字符预算（工具回执 8192 硬顶〔ToolClip.clipToolResult〕减 note 与省略标注的余量——
// 取保守值，产出恒 < 8192）。★ 2026-10-07 自检轮 P1 修复：两组满配（各 50 条 × 名称 50 +
// 说明 30 + 结构开销 ≈ 每条 103 字符）可达约 10300 字符，而 clipToolResult 对本形态（无
// summary/results 键，不走结构化截断）是 substring 硬截——满配回执被腰斩成坏 JSON 给模型。
// 收口在写入点（装填守卫）而非回缩函数：按序装填、超预算即止，note 报省略数。
const ENV_RECEIPT_BUDGET: number = 7800;

// 单条目序列化成本（+1 逗号分隔）
function envItemCost(item: EnvCredItem): number {
  return JSON.stringify(item).length + 1;
}

// 预算装填（纯函数）：global 组先装、assistant 组后装（与清单展示序一致），装不下的整组
// 尾部省略；返回保留组与省略条数。外层骨架与 note 按保守常量预扣（used 初值）。
function fitEnvGroups(groups: EnvCredGroups): FittedEnvGroups {
  const kept: EnvCredGroups = { global: [], assistant: [] };
  let used: number = 160;
  for (const item of groups.global) {
    const cost: number = envItemCost(item);
    if (used + cost > ENV_RECEIPT_BUDGET) {
      break;
    }
    kept.global.push(item);
    used += cost;
  }
  for (const item of groups.assistant) {
    const cost: number = envItemCost(item);
    if (used + cost > ENV_RECEIPT_BUDGET) {
      break;
    }
    kept.assistant.push(item);
    used += cost;
  }
  const omitted: number = (groups.global.length - kept.global.length) +
    (groups.assistant.length - kept.assistant.length);
  return { kept: kept, omitted: omitted };
}

export const ENV_LIST_DESC: string =
  'List the HTTP credentials available to you: a global set shared by all ' +
  'assistants and a set private to the current assistant. Returns the name and an ' +
  'optional usage description of each credential, never the values. Use a name in ' +
  'http_request as {{name}} inside a custom header value or a URL query parameter value; ' +
  'the app substitutes the real value before sending. Credential references are not ' +
  'allowed in the URL path or the request body. If the same name exists globally and for ' +
  'this assistant, the assistant one wins. Call this before using a credential for the ' +
  'first time, or when http_request reports a missing credential.';

export const ENV_LIST_SCHEMA: string =
  '{"type":"object","properties":{},' +
  '"description":"无参数。返回 credentials.global 与 credentials.assistant 两组凭据条目，' +
  '每组条目含 name 名称与 desc 用途说明，说明可能为空。"}';

export class EnvListExecutor implements ToolExecutor {
  execute(_argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    const groups: EnvCredGroups = credentialNameGroups(ctx.assistantId);
    const empty: boolean = groups.global.length === 0 && groups.assistant.length === 0;
    if (empty) {
      const emptyReceipt: EnvListReceipt = {
        credentials: groups,
        note: '尚未配置任何凭据。请让用户在 设置 → 工具调用 → HTTP 凭据 中添加。'
      };
      return Promise.resolve(JSON.stringify(emptyReceipt));
    }
    const fitted: FittedEnvGroups = fitEnvGroups(groups);
    const note: string = '值不会出现在对话里。在 http_request 的请求头值或 URL 查询参数值中用 {{名称}} 引用。' +
      (fitted.omitted > 0 ? ' 凭据较多，另有 ' + fitted.omitted + ' 条未列出。' : '');
    const receipt: EnvListReceipt = { credentials: fitted.kept, note: note };
    return Promise.resolve(JSON.stringify(receipt));
  }
}
