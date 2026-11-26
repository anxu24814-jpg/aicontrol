/** Kit 边界只执行已捕获的阅读出口。不持组件/AST、不弹迟到 toast，结果由当前票据所有者接纳。 */
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export type MarkdownReadingActionStatus = 'success' | 'cancelled' | 'stale' | 'failed';

export interface MarkdownReadingActionResult {
  status: MarkdownReadingActionStatus;
  message: string;
  uri: string;
  bytesWritten: number;
  fileTouched: boolean;
}

function readingResult(status: MarkdownReadingActionStatus): MarkdownReadingActionResult {
  return { status: status, message: '', uri: '', bytesWritten: 0, fileTouched: false };
}

function readingFailure(result: MarkdownReadingActionResult, error: Error, stage: string): void {
  result.status = 'failed';
  result.message += (result.message === '' ? '' : '\n') + stage + '失败。' + error.message;
  hilog.error(0xD5A0, 'MarkdownReading', '%{public}s失败：%{public}s', stage, error.message);
}

export async function markdownReadingCopy(text: string,
  accepts: () => boolean): Promise<MarkdownReadingActionResult> {
  const result: MarkdownReadingActionResult = readingResult('stale');
  try {
    if (!accepts()) { return result; }
    const content: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    if (!accepts()) { return result; }
    await pasteboard.getSystemPasteboard().setData(content);
    // 已提交系统的复制无法撤销；旧结果只是不允许回填新绑定 UI。
    result.status = accepts() ? 'success' : 'stale';
  } catch (failure) {
    readingFailure(result, failure as Error, '复制');
  }
  return result;
}

// 保存骨架：picker → 预检 → 分块写 → 关闭。文本保存与二进制保存（图表 PNG）共用同一份
// 写盘/取消/短写/关闭纪律，避免第二套实现漂移；相对原 markdownReadingSave 只把「文本编码」
// 上移到调用方，其余检查与次序保持原样。
async function saveReadingBytes(context: common.UIAbilityContext, bytes: Uint8Array, fileName: string,
  suffixLabel: string, suffix: string, accepts: () => boolean): Promise<MarkdownReadingActionResult> {
  const result: MarkdownReadingActionResult = readingResult('stale');
  let file: fs.File | null = null;
  try {
    if (!accepts()) { return result; }
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = [suffixLabel + '|' + suffix];
    // API23+，避免 Picker 等待期间失效却预置空文件。空选择单独按取消处理，异常保留失败。
    options.autoCreateEmptyFile = false;
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    if (!accepts()) { return result; }
    const uris: string[] = await documentPicker.save(options);
    if (uris.length === 0) {
      result.status = 'cancelled';
      return result;
    }
    if (!accepts()) { return result; }
    if (uris.length !== 1 || uris[0] === '') {
      throw new Error('保存位置无效');
    }
    result.uri = uris[0];
    if (!accepts()) { return result; }
    // open(TRUNC) 是第一个文件不可逆边界；紧前校验，await 后再次校验。
    result.fileTouched = true;
    file = await fs.open(result.uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    while (result.bytesWritten < bytes.byteLength && accepts()) {
      const end: number = Math.min(bytes.byteLength, result.bytesWritten + 65536);
      const chunk: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset + result.bytesWritten,
        bytes.byteOffset + end) as ArrayBuffer;
      if (!accepts()) { break; }
      const count: number = await fs.write(file.fd, chunk, { offset: result.bytesWritten, length: chunk.byteLength });
      if (!Number.isSafeInteger(count) || count <= 0 || count > chunk.byteLength) {
        throw new Error('文件写入未取得有效进展');
      }
      result.bytesWritten += count;
      if (!accepts()) { break; }
    }
    result.status = accepts() && result.bytesWritten === bytes.byteLength ? 'success' : 'stale';
  } catch (failure) {
    readingFailure(result, failure as Error, '保存');
  } finally {
    if (file !== null) {
      // 无论失效/失败都关闭。close 失败推翻 success，不吞异常，也不删除可能覆盖的用户文件。
      try {
        await fs.close(file);
      } catch (failure) {
        readingFailure(result, failure as Error, '关闭文件');
      }
    }
  }
  if (result.status === 'success' && !accepts()) { result.status = 'stale'; }
  if (result.fileTouched && result.status !== 'success') {
    hilog.warn(0xD5A0, 'MarkdownReading', '导出未完整确认，已写入 %{public}d 字节，请检查所选文件',
      result.bytesWritten);
  }
  return result;
}

export async function markdownReadingSave(context: common.UIAbilityContext, text: string,
  fileName: string, csv: boolean, accepts: () => boolean): Promise<MarkdownReadingActionResult> {
  const bytes: Uint8Array = text === '' ? new Uint8Array(0) : new util.TextEncoder().encodeInto(text);
  return saveReadingBytes(context, bytes, fileName, csv ? 'CSV 表格' : '纯文本', csv ? '.csv' : '.txt', accepts);
}

/** 二进制保存：图表 PNG 导出与文本保存共用同一出口纪律。 */
export async function markdownReadingSaveBytes(context: common.UIAbilityContext, bytes: Uint8Array,
  fileName: string, accepts: () => boolean): Promise<MarkdownReadingActionResult> {
  return saveReadingBytes(context, bytes, fileName, 'PNG 图片', '.png', accepts);
}
