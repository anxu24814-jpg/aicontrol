// 模拟 Shell 资产装配件。职责一句话 = 「资产清单顺序单源 + Context 捕获与资产读取缓存 +
// composeShellCode（用户文本以 JSON 字符串字面量注入）」。
// · 资产 = 三件纯 JS 文件落 rawfile/shell/（宿主持有、随包分发、只读）——先例 =
//   rawfile/document-parser 与 rawfile/ocr；每次运行随 code 一起编译（QuickJS 无字节码
//   缓存位，与 JS 模式预置面同款开销形态，只记录不承诺——宪法「性能不许愿」）。
// · ★P0 主闸：用户 shell 文本永不进入任何可执行位置——唯一入口 = 本件 JSON.stringify
//   生成的字符串字面量，作为解释器入口函数 __shellRunMain 的实参注入
//   （code = 资产源 + '\n' + '__shellRunMain(' + 字面量 + ');'）。资产源内零动态执行。
// · U+2028 / U+2029 显式转义：JSON 允许它们出现在字符串字面量内，个别引擎版本对行分隔符
//   的字符串字面量语义可能漂移——生成字面量后显式替换为 \u2028 / \u2029 转义序列（防御）。
// · 失败路径（P0-1 禁静默）：上下文未注入 / 读资产失败 / 解码失败一律抛中文错误，由
//   ToolCodeExec 捕获转中文错误回执（禁静默降级为 JS 执行或空资产）。
// · 缓存纪律：资产源只缓存成功（纯字符串、常驻、有界，无需释放）；attachShellAssetContext
//   为进程级一次性注入（无注销需求——照 OcrPaddle.paddleAttachContext 同款先例）。
// · import 面：只引 @kit 的 AbilityKit（Context 类型）与 ArkTS（TextDecoder）——零引
//   ToolRuntime / ToolTypes / ToolCodeExec / ToolWorkspace（坑50 依赖单向）。
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

// 资产清单顺序单源（顺序契约 = parse → commands → run，改序须过断言：钉 4）
export const SHELL_ASSET_FILES: string[] = ['shell/parse.js', 'shell/commands.js', 'shell/run.js'];

// 入口调用前缀（注入形态：'__shellRunMain(' + JSON 字面量 + ');'）
const SHELL_ENTRY_PREFIX: string = '__shellRunMain(';

// 资源管理器引用（调用点 = EntryAbility.onCreate 现捕获群——common 层拿不到 UIContext，
// 能力上下文是应用级单一真源，属组合根职责）
let shellAssetContext: common.Context | null = null;

// 资产源缓存（只缓存成功；失败不复位——同一次会话内重复失败不重付读盘，失败即报错不降级）
let shellAssetSourceCache: string | null = null;

// 上下文注入（调用点 = EntryAbility.onCreate）
export function attachShellAssetContext(ctx: common.Context): void {
  shellAssetContext = ctx;
}

// 资产源读取（按清单顺序读三件 → UTF-8 解码 → '\n' 拼接；失败抛中文错误）
export async function loadShellAssetSource(): Promise<string> {
  if (shellAssetSourceCache !== null) {
    return shellAssetSourceCache;
  }
  const ctx: common.Context | null = shellAssetContext;
  if (ctx === null) {
    throw new Error('模拟 Shell 资产上下文未注入');
  }
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  let source: string = '';
  for (const file of SHELL_ASSET_FILES) {
    let bytes: Uint8Array;
    try {
      bytes = await ctx.resourceManager.getRawFileContent(file);
    } catch (e) {
      throw new Error('读取资产 ' + file + ' 失败：' + (e as Error).message);
    }
    if (source !== '') {
      source += '\n';
    }
    source += decoder.decodeToString(bytes);
  }
  shellAssetSourceCache = source;
  return source;
}

// U+2028 / U+2029 显式转义（见头注释：行分隔符防御）
function escapeLineSeparators(json: string): string {
  return json.replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

// shell 执行码组装（★P0 主闸：用户文本只作数据——JSON 字符串字面量实参；资产在前、
// 调用行在后，入口调用是脚本末语句，其返回值即回执 value）
export async function composeShellCode(userText: string): Promise<string> {
  const source: string = await loadShellAssetSource();
  const literal: string = escapeLineSeparators(JSON.stringify(userText));
  return source + '\n' + SHELL_ENTRY_PREFIX + literal + ');';
}
