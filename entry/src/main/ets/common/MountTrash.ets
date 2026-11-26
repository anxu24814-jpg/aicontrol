// 挂载条目「删除到系统回收站」共享叶子（决明拍板「删除走系统回收站」）。
// 立件理由（反碎片下限②，照 ExternalLink.ets 先例）：消费方横跨用户浏览页（MountBrowsePage
// 删除链路）与 AI 工具面（ToolMount.MountDeleteExecutor）两域——并入任一域都会造成跨域
// 依赖；本件零状态、只收参数出结论，是叶子姿态。
// 能力 = 官方 File Manager Service Kit 的 deleteToTrash（把公共目录条目删除到系统回收站，
// 可恢复；官方 API 页无「需要权限」条目、无「仅系统应用」字样——普通应用可用性为负向
// 证据链，真机终证；约束 = 仅中国境内 + 手机/平板/PC 2in1；官方文档只写「文件」——**文件夹
// 支持未写明**，真机首查项见 BLOCKED；对已持久授权目录 URI 的兼容性官方亦未写明，与挂载
// 各批真机项同批复测）。
// 语义口径：本域删除恒走本通道——不降级永久删除（回收站可恢复是用户拍板选定的删除语义；
// 真机若否决文件夹路径，随修复笔按当时实况补分支，见变更记录）。
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { mountChildUri } from './MountUtil';

const DOMAIN: number = 0xD5B2;
const TAG: string = 'MountTrash';

// 回收站能力系统能力位（canIUse 门；官方 Kit 简介原文 = SystemCapability.FileManagement.
// FileManagerService.Core）
const TRASH_SYSCAP: string = 'SystemCapability.FileManagement.FileManagerService.Core';

// 目标不存在错误码（官方参考 filemanagerservice-arkts-filemanagerservice 错误码表：
// 401 参数错误 / 1014000001 Operation not permitted / 1014000002 No such file or directory /
// 1014000003 No space left on device / 1014000004 System inner fail）——导出供消费方按「已不在」
// 决定是否刷新列表
export const MOUNT_TRASH_CODE_MISSING: number = 1014000002;

// 删除结论（errorText 恒为可直上屏、可直入工具回执的中文；code = 底层错误码，-1 = 能力门
// 否决，0 = 无码异常）
export interface MountTrashOutcome {
  ok: boolean;
  errorText: string;
  code: number;
}

// 单入口（dirUri = 挂载根目录 URI；relPath = 挂载内相对路径，'' 不接受——根不可删，调用方
// 先拦）。全包 try/catch 恒不抛：失败转结论如实回传（P0-1 不静默、消费方按 errorText 提示）
export async function deleteMountEntryToTrash(dirUri: string,
  relPath: string): Promise<MountTrashOutcome> {
  if (!canIUse(TRASH_SYSCAP)) {
    return { ok: false, errorText: '这台设备不支持删除到系统回收站，无法删除。', code: -1 };
  }
  let uri: string = '';
  try {
    uri = mountChildUri(dirUri, relPath);
  } catch (e) {
    hilog.error(DOMAIN, TAG, '目标 URI 拼接失败：%{public}s', (e as Error).message);
    return { ok: false, errorText: '删除失败，请重试。', code: 0 };
  }
  try {
    await fileManagerService.deleteToTrash(uri);
    return { ok: true, errorText: '', code: 0 };
  } catch (e) {
    const code: number = (e as BusinessError).code;
    hilog.error(DOMAIN, TAG, '回收站删除失败：code %{public}d %{public}s',
      typeof code === 'number' ? code : -1, (e as Error).message);
    return { ok: false, errorText: trashFailText(code), code: code };
  }
}

// 失败文案（不美化底层 code；「内容」为文件与文件夹通用词——同一函数服务两类目标）
function trashFailText(code: number): string {
  if (code === MOUNT_TRASH_CODE_MISSING) {
    return '要删除的内容已经不在这个文件夹里。';
  }
  if (code === 1014000001) {
    return '系统不允许这次删除，请稍后重试。';
  }
  return '删除失败，请重试。';
}
