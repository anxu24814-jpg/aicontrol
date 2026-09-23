// 官方生物识别门禁封装（2026-09-04 加密会话功能建；2026-09-04 深夜修「不弹窗即失败」
// 补发起前能力预检；2026-09-05 修真机 401——challenge 空数组改非空 16 字节；2026-09-05
// 二轮：决明指令「偏好设置选人脸或指纹，选定只用一种」——**恒单类型**，authType 只发
// 偏好选定类型（默认人脸，真机实测链路已通），401 自动换类型回退路径**已撤**（弹窗内
// 失败重试恒为选定类型，官方弹窗行为；换方式在偏好设置切换）。
// ★ 官方查证依据（2026-09-04，本地 SDK d.ts + 官方权限列表双源）：
// ①接口 = UserAuthenticationKit 的 userAuth.getUserAuthInstance(authParam, widgetParam)
//   → on('result') 订阅 → start() 拉起官方认证弹窗（@since 10，API 26 SDK d.ts 实锤）；
// ②权限 = ohos.permission.ACCESS_BIOMETRIC：normal 级 + system_grant 开放权限（官方
//   「应用权限列表·开放权限（系统授权）」表内，module.json5 声明即得，无需 reason）；
// ③信任级 = ATL2（应用登录档，官方场景推荐）；★选定类型 ATL2 不可用降 ATL1 再查
//（2D 人脸/低配指纹机型）——getAvailableStatus 官方定位即「发起前查能力，避免无谓的
//   认证失败」；等级降级保留（机型兼容维度，与类型选择无关），类型维度恒按偏好不回退。
// ④结果码 = UserAuthResult.result：SUCCESS(12500000) 通过；CANCELED 用户取消；FAIL
//   认证未通过；NOT_ENROLLED 未录入凭据；TYPE/TRUST_LEVEL_NOT_SUPPORT 设备不支持；
//   201（BusinessError 权限缺失，同步抛错与回调透传双路径收敛单列 PERMISSION_DENIED）
//   其余按通用失败。start() 的同步抛错（BusinessError）try-catch 收敛。
// ★ 2026-09-05 真机 code 401 实锤排障史（决明回报两轮，toast 直显 code 定位）：401 =
//   参数校验失败——①challenge 空 Uint8Array（d.ts 称 Uint8Array([]) 可传，真机拒收——
//   文档与实现偏差）改固定 16 字节非空数组（官方示例形态；本项目不校验 token，challenge
//   值无安全语义）；②authType 双类型数组嫌疑——曾加「401 自动降单类型重试」机制
//   （f99a312/4308456），真机人脸单类型通过后按决明指令撤除（35e7021）——现行 = 偏好
//   选定恒单类型、无任何类型回退，换方式在偏好设置切换。
// ★ 生命周期：UserAuthInstance 一次性（官方 NOTE——每次认证须新建实例，本封装每次调用
// 新建即弃）；on/off 成对（结果回调触发即终态，收尾 off 防御）。
import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isBiometricFacePreferred } from './AppPreferences';

const DOMAIN: number = 0x0001;
const TAG: string = 'BiometricGate';

// 认证结果（调用方按分支提示：PASSED 放行；CANCELED 静默；其余 toast 各自文案）
export enum BiometricGateOutcome {
  PASSED, // 认证通过
  CANCELED, // 用户主动取消（非失败，不提示）
  FAILED, // 认证未通过（比对失败/超时/锁定等）
  NOT_ENROLLED, // 设备未录入人脸或指纹
  NOT_SUPPORTED, // 设备不支持人脸/指纹认证
  ERROR, // 其他错误（详情入 hilog）
  PERMISSION_DENIED // 生物识别权限未生效（装机包缺权限声明——重新构建安装）
}

// 认证返回（结果 + 原始错误码）：code 直显到 toast——真机取证一步定位（2026-09-05，
// 预检修复轮未根治后的取证增强；code 语义 = onResult 结果码 / start 抛错的 BusinessError
// code / 预检短路的对应码 / 无码 -1）
export interface BiometricGateResult {
  outcome: BiometricGateOutcome;
  code: number;
}

// 能力预检结果（显式接口——坑72：ArkTS 禁匿名对象字面量作结构化返回）
interface GateProbeResult {
  // 选定类型支持且已录入凭据（可发起）
  ok: boolean;
  // 类型支持但未录入（全空时区分报未录入还是不支持）
  enrolledMiss: boolean;
  // getAvailableStatus 抛 201 = 权限未生效（包缺声明/装包旧），短路直报
  permissionDenied: boolean;
}

// 发起前能力预检（官方推荐姿势——getAvailableStatus @since 9；2026-09-05 恒单类型：
// 只查偏好选定类型，抛 NOT_ENROLLED 记「可录入」、201 记权限缺失、其余忽略）
function probeType(t: userAuth.UserAuthType, level: userAuth.AuthTrustLevel): GateProbeResult {
  const result: GateProbeResult = { ok: false, enrolledMiss: false, permissionDenied: false };
  try {
    userAuth.getAvailableStatus(t, level);
    result.ok = true;
  } catch (e) {
    const biz = e as BusinessError;
    hilog.info(DOMAIN, TAG, '预检 %{public}d 不通过：code %{public}d', t,
      typeof biz.code === 'number' ? biz.code : -1);
    if (typeof biz.code === 'number' && biz.code === 201) {
      result.permissionDenied = true;
    } else if (biz.code === userAuth.UserAuthResultCode.NOT_ENROLLED) {
      result.enrolledMiss = true;
    }
  }
  return result;
}

// 认证结果 → 用户提示文案（2026-09-05 自 ChatSessionList.toastGateOutcome 抽取——加密
// 新入口第四处消费，P2-4 重复两次以上提取；文案逐字迁移）。取消 = ''（调用方静默——用户
// 主动行为非故障）；FAILED/ERROR 带 code 直显（取证增强，code 表对照见头注释）
export function gateOutcomeMessage(gate: BiometricGateResult): string {
  switch (gate.outcome) {
    case BiometricGateOutcome.CANCELED:
      return '';
    case BiometricGateOutcome.NOT_ENROLLED:
      return '请先在系统设置中录入人脸或指纹';
    case BiometricGateOutcome.NOT_SUPPORTED:
      return '当前设备不支持人脸或指纹识别';
    case BiometricGateOutcome.PERMISSION_DENIED:
      return '生物识别权限未生效，请重新构建安装应用后重试';
    case BiometricGateOutcome.FAILED:
      return '认证未通过，code ' + gate.code;
    default:
      return '认证失败，code ' + gate.code;
  }
}

// 拉起官方生物识别弹窗（认证类型 = 偏好选定恒单类型——isBiometricFacePreferred 现读，
// 默认人脸）。title = 弹窗标题（官方建议写明认证目的，如「验证身份，进入加密会话」）。
// 恒 resolve 不 reject——错误已收敛为结构化结果（outcome + 原始 code，失败码供调用方
// toast 直显取证）
export function biometricGate(title: string): Promise<BiometricGateResult> {
  return new Promise<BiometricGateResult>((resolve: (v: BiometricGateResult) => void) => {
    // ①选定类型（偏好现读——切换即时生效，下次认证即新方式）
    const preferred: userAuth.UserAuthType = isBiometricFacePreferred() ?
      userAuth.UserAuthType.FACE : userAuth.UserAuthType.FINGERPRINT;
    // ②预检选定类型（ATL2 不可用降 ATL1——机型兼容维度保留；仍无 = 不支持/未录入）
    let probeLevel: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL2;
    let probe: GateProbeResult = probeType(preferred, probeLevel);
    if (!probe.ok && !probe.permissionDenied) {
      probeLevel = userAuth.AuthTrustLevel.ATL1;
      probe = probeType(preferred, probeLevel);
    }
    if (probe.permissionDenied) {
      resolve({ outcome: BiometricGateOutcome.PERMISSION_DENIED, code: 201 });
      return;
    }
    if (!probe.ok) {
      hilog.error(DOMAIN, TAG, '预检无可用认证类型');
      resolve({ outcome: probe.enrolledMiss ? BiometricGateOutcome.NOT_ENROLLED
        : BiometricGateOutcome.NOT_SUPPORTED, code: -1 });
      return;
    }
    // ③challenge：固定 16 字节非空数组（2026-09-05 真机 code 401 实锤——空 Uint8Array
    // d.ts 称可传、真机参数校验拒收；取官方示例非空形态。本项目不校验 token，challenge
    // 值无安全语义，固定常量即可，值取 ascii 'aicontrol-gate-chal' 前 16 字节）
    const challenge: Uint8Array = new Uint8Array([
      0x61, 0x69, 0x63, 0x74, 0x72, 0x6C, 0x2D, 0x67,
      0x61, 0x74, 0x65, 0x2D, 0x63, 0x68, 0x61, 0x6C
    ]);
    // ④发起（单次，无类型回退——弹窗内失败重试恒为选定类型；同步抛错分类呈报）
    let instance: userAuth.UserAuthInstance;
    try {
      instance = userAuth.getUserAuthInstance(
        { challenge: challenge, authType: [preferred], authTrustLevel: probeLevel },
        { title: title });
    } catch (e) {
      const biz = e as BusinessError;
      const code: number = typeof biz.code === 'number' ? biz.code : -1;
      hilog.error(DOMAIN, TAG, '创建认证实例失败：code %{public}d %{public}s', code,
        (e as Error).message);
      if (code === 201) {
        resolve({ outcome: BiometricGateOutcome.PERMISSION_DENIED, code: code });
      } else {
        resolve({ outcome: BiometricGateOutcome.ERROR, code: code });
      }
      return;
    }
    // 结果回调（onResult 接口对象形态——d.ts IAuthCallback 实锤；触发即终态，实例即弃）
    const callback: userAuth.IAuthCallback = {
      onResult: (result: userAuth.UserAuthResult): void => {
        instance.off('result', callback); // 与 on 成对（终态后不再有事件，防御性解绑）
        const code: number = result.result;
        if (code === userAuth.UserAuthResultCode.SUCCESS) {
          resolve({ outcome: BiometricGateOutcome.PASSED, code: code });
        } else if (code === userAuth.UserAuthResultCode.CANCELED) {
          resolve({ outcome: BiometricGateOutcome.CANCELED, code: code });
        } else if (code === userAuth.UserAuthResultCode.NOT_ENROLLED) {
          resolve({ outcome: BiometricGateOutcome.NOT_ENROLLED, code: code });
        } else if (code === 201) {
          resolve({ outcome: BiometricGateOutcome.PERMISSION_DENIED, code: code });
        } else {
          hilog.error(DOMAIN, TAG, '认证未通过：code %{public}d', code);
          resolve({ outcome: BiometricGateOutcome.FAILED, code: code });
        }
      }
    };
    try {
      instance.on('result', callback);
      instance.start();
    } catch (e) {
      // start 同步抛错（201 权限/12500xxx 服务态）——注册已发生，成对解绑后分类呈报
      instance.off('result', callback);
      const biz = e as BusinessError;
      const code: number = typeof biz.code === 'number' ? biz.code : -1;
      hilog.error(DOMAIN, TAG, '发起认证失败：code %{public}d %{public}s', code,
        (e as Error).message);
      if (code === 201) {
        resolve({ outcome: BiometricGateOutcome.PERMISSION_DENIED, code: code });
      } else if (code === userAuth.UserAuthResultCode.NOT_ENROLLED) {
        resolve({ outcome: BiometricGateOutcome.NOT_ENROLLED, code: code });
      } else {
        resolve({ outcome: BiometricGateOutcome.ERROR, code: code });
      }
    }
  });
}
