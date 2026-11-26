// 环境信息单源：应用版本 + 系统版本 + API + 机型的一行文本。
// 两个消费方——反馈页（随反馈附上）与运行日志页（导出 TXT 头部：开发者拿到日志的第一问
// 就是「什么版本什么机」）。
// 为何不能并入既有件（反碎片下限②的一句话理由）：两个消费方分属反馈域与日志域，并入任一域
// 都会造成跨域依赖（common 件反向 import components 是本仓红线）；本件零状态纯函数、只读
// 官方常量（bundleManager 同步查询 + deviceInfo 只读字段），是叶子姿态。
// 版本读取失败显示「未知」不阻断（P0-1 留痕，AboutPage 同款口径）；系统版本 = deviceInfo
// 三段字段拼接（d.ts 明示优于解析 osFullName，产出「6.1.1」式纯版本），机型与 API 版本为
// 官方只读常量（均 systemGrant，非敏感项）。
import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 一行环境信息：「版本 1.6.0 · 系统 6.1.1 (API 26) · 机型 xxx」
export function envInfoLine(): string {
  let version: string = '未知';
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    version = info.versionName;
  } catch (err) {
    hilog.error(0xD5A0, 'EnvInfo', 'read bundle info failed: %{public}s', JSON.stringify(err));
  }
  const osVer: string = deviceInfo.majorVersion + '.' + deviceInfo.seniorVersion +
    '.' + deviceInfo.featureVersion;
  return '版本 ' + version + ' · 系统 ' + osVer + ' (API ' + deviceInfo.sdkApiVersion +
    ') · ' + deviceInfo.productModel;
}
