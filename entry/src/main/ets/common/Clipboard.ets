// 剪贴板写单源：纯文本写系统剪贴板的唯一实现面——成功 toast 一句（文案由调用方给）、
// 失败 hilog + 通用失败提示（两处反馈齐，照 MessageCopySheet 先例口径；toast 走 UIContext
// 形态，禁全局 promptAction——宪法「UI 弹层与上下文一律 UIContext 形态」条）。
// ★ 无 toast 叶子 writeTextToClipboard 供工具执行器用（工具执行器在 common 层、无
// UIContext，不能复用带 toast 的 copyTextToClipboard）——copy 版改调叶子，全工程写剪贴板
// 仍单源（两入口同一实现）；写剪贴板零权限依据 = 官方 FAQ「复制内容是系统默认支持的能力，
// 不需要额外申请权限」。
// 为何独立成文件：消费方 = 密钥复制两处入口（服务商密钥池行 ProviderKeysPanel /
// HTTP 凭据行 HttpCredentialsPage），分属两页；common/ 下无剪贴板类同域件可并，职责
// 一句话可述（纯文本写剪贴板与两头反馈）。既有内联复制调用点（MessageCopySheet /
// ReqLogDetailSheet / ModelEditPage / MemoryImportPage 等）不动，收拢留待专笔
//（禁顺手大重构）。
// ★ 明文纪律（密钥类调用方必读）：本件只把调用方给的文本过一道手写进剪贴板——不落
// 日志（失败日志只记错误 message）、不驻留、不进 toast；调用方须保证明文不留在任何
// 状态与回执里（toast 只报名称与结果）。
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';

const DOMAIN: number = 0xD5A0;
const TAG: string = 'Clipboard';

// 写纯文本到系统剪贴板（Promise<void> 叶子——反馈由调用方在 then/catch 面给）：零权限、
// 零日志、零驻留；写入为替换式（系统剪贴板同一时间只有一份内容，本函数不读旧值不回抄）
export function writeTextToClipboard(text: string): Promise<void> {
  const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  return pasteboard.getSystemPasteboard().setData(data);
}

// 写纯文本到系统剪贴板（Promise 形态——照既有复制先例）：成功 toast okMessage，
// 失败 hilog + 「复制失败，请重试」；uiContext 由调用方传（UIContext 形态纪律）
export function copyTextToClipboard(uiContext: UIContext, text: string, okMessage: string): void {
  writeTextToClipboard(text).then((): void => {
    uiContext.getPromptAction().showToast({ message: okMessage });
  }).catch((e: Object): void => {
    hilog.error(DOMAIN, TAG, '写剪贴板失败：%{public}s', (e as Error).message);
    uiContext.getPromptAction().showToast({ message: '复制失败，请重试' });
  });
}
