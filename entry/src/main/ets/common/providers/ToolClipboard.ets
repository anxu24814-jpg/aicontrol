// 剪贴板工具域（2026-10-13 剪贴板写入工具笔新立）：一个内置工具 clipboard_write——把文本
// 写入系统剪贴板（零权限；写路径经 common/Clipboard.ets 单源叶子 writeTextToClipboard）。
// ★ 为何只做写、不做读（决策与证据存 docs/变更记录.md 本笔条目）：读剪贴板 API 12 起受
//   ohos.permission.READ_PASTEBOARD 管控——受限开放权限（system_basic + user_grant，须 ACL，
//   裸声明安装失败 9568289），官方可申请场景白名单（银行卡号复制 / 应用口令 / 文档编辑 /
//   系统输入法）不含 AI 助手，AGC 审核大概率驳回；官方对白名单外场景指定的替代是粘贴控件
//   （安全控件点击临时授权）。两条读取路线决明 2026-10-13 拍板均不做，只做零权限的写入。
// ★ 参考实现与差异：rikkahub / kelivo 两家的 clipboard_tool（单工具 + action 枚举 read/write，
//   描述句含「除非用户明确要求不要写」防线、不弹审批）；本工程一操作一工具惯例（日程 / 位置 /
//   挂载同族）——只做写故只此一件，防线句落 desc、默认关由注册块给（defaultEnabled: false）。
// ★ 命名区分：本件是剪贴板工具域；同目录 ToolClip.ets 是**工具结果截断域**——两件不同，勿混。
// · 依赖纪律：自 ToolContracts 引执行器契约与帮助函数、ToolIds 引 id（消费方）、
//   MessageContracts 引执行上下文、common/Clipboard 引写单源；**禁引 ToolTypes 聚合根**
//   （assert-app-domain 85 组环防线；id 只在本件被注册块间接消费，本件不引也无碍）。
// · 回执形态：成功回 {"success":true,"textChars":N} 不回抄正文——正文已在工具参数里，
//   重抄只烧 token 且超 clipToolResult 8192 线后失真；缺参 / 空串回显式错误、不写空剪贴板。
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { writeTextToClipboard } from '../Clipboard';

// clipboard_write desc（注册块引用；自包含——工具细节全在此，模型只读这一份；防线句照
// rikkahub / kelivo 两家参考的「Do NOT write … unless the user has explicitly requested it」）
export function buildClipboardWriteDesc(): string {
  return '把文本写入系统剪贴板，用户随后可在任意应用粘贴。写入会覆盖剪贴板里原有的内容。' +
    '只在用户明确要求把内容复制到剪贴板时调用，不要主动写入。text 是要写入剪贴板的完整文本。';
}

// clipboard_write schema（text 必填——缺参在 schema 与执行器空串守卫两侧各自兜底）
export const CLIPBOARD_WRITE_SCHEMA: string = '{"type":"object","properties":{' +
  '"text":{"type":"string","description":"要写入剪贴板的完整文本"}},"required":["text"]}';

// 写剪贴板执行器：解析参数（失败回帮助文案）→ 空串守卫（不写空剪贴板）→ 单源写 →
// 成功回执 textChars（异常转 error JSON——轮次不炸，编排层另有 executeToolCall 兜底）
export class ClipboardWriteExecutor implements ToolExecutor {
  execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let text: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw: Object = parsed['text'];
      if (typeof raw === 'string') {
        text = raw;
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    if (text === '') {
      return Promise.resolve(JSON.stringify({
        error: '参数 text 为空。请给出要写入剪贴板的完整文本后重试。' }));
    }
    return writeTextToClipboard(text).then((): string => {
      return JSON.stringify({ success: true, textChars: text.length });
    }).catch((e: Object): string => {
      return JSON.stringify({ error: '写入剪贴板失败：' + toolErrorText(e) });
    });
  }
}
