// 位置工具域（2026-09-25 获取位置工具笔，决明拍板精准定位 + 默认关）：get_location——单次
// 获取设备当前位置（WGS-84 经纬度 + 精度 + 海拔 + 逆地理地址尽力而为），供模型回答与用户
// 位置有关的问题（附近推荐、当地天气、出行）。官方实现三级优先①官方 = Location Kit
// geoLocationManager（API 9 起，本工程基线 API 26；开发指导 location-guidelines 实查）。
// ★ 权限（本仓首批 user_grant）：ohos.permission.APPROXIMATELY_LOCATION + LOCATION 双声明
//（官方「申请位置权限开发指导」：单独申请 LOCATION 不允许，精准须与模糊同时申请；均
// normal + user_grant 开放权限，devdocs 权限列表实查）——module.json5 配 reason + usedScene，
// 运行期首次调用经 requestPermissionsFromUser 弹窗授权（本仓首个运行时授权路径），拒绝/
// 永久拒绝统一返错误文案引导系统设置开启，不做二次拉起。
// ★ 域纪律：本文件只 import './ToolContracts' 与系统 Kit（防环红线，ToolContracts 头注释）；
// 注册在 ToolTypes.ets 聚合根（本文件不引它）。不做项：持续定位/后台定位（不碰
// LOCATION_IN_BACKGROUND 与长时任务）、requestGlobalSwitch 拉系统开关弹窗（开关关闭时返
// 错误文案引导用户手动开）、位置数据零持久化（结果只进会话消息流，随会话存取）。
// context 注入：执行器无组件环境，requestPermissionsFromUser 需要 UIAbilityContext——
// EntryAbility onCreate 经 initLocationAccess 注入（先例 AttachmentDb.initAttachmentStore）；
// 未注入（理论不可达，启动链保证）时返错误不炸轮（executeToolCall 包底之外的自防）。
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ToolExecutor } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';

// 单次实时定位超时（官方开发指导建议 10 秒——设备环境与功耗管控下定位时延波动大）
export const LOCATION_TIMEOUT_MS: number = 10000;
// 缓存位置新鲜度窗口：getLastLocation 时间戳距今不超过该值直接用（官方推荐优先缓存省电，
// 新鲜度不足再落实时定位）
export const LOCATION_FRESH_MS: number = 5 * 60 * 1000;

// 工具入参 schema（零参数 object——与 get_time_info 同形，防 provider 校验空参缺 type）
export const GET_LOCATION_SCHEMA: string = '{"type":"object","properties":{}}';

// 模型面描述（desc = 何时调用本工具的唯一引导，能力单源红线——零 system prompt 改动；
// 缓存窗口与超时数字自常量派生，禁字面量双源）
export function buildGetLocationDesc(): string {
  const freshMinutes: number = LOCATION_FRESH_MS / 60000;
  const timeoutSeconds: number = LOCATION_TIMEOUT_MS / 1000;
  return '获取设备当前所在位置。回答与用户当前位置有关的问题（例如附近推荐、当地天气、出行）' +
    '或任务需要用户位置时调用。返回 WGS-84 坐标经纬度、精度、海拔与逆地理地址，地址尽力而为可能缺省。' +
    '优先返回 ' + freshMinutes + ' 分钟内的缓存位置，否则现场定位（最长 ' + timeoutSeconds + ' 秒）。' +
    '定位服务关闭或未授权时返回错误，此时如实告知用户原因，不要重复调用。';
}

// 定位结果载荷（ArkTS 对象字面量挂显式接口——坑59①；address 逆地理失败时缺省）
interface LocationToolResult {
  latitude: number;
  longitude: number;
  accuracy: number;
  altitude: number;
  timeStamp: number;
  coordinateSystem: string;
  address?: string;
}

// 模块级 context 单例（EntryAbility onCreate 注入，进程级不变——状态最小化，不挂装饰器）
let locationContext: common.UIAbilityContext | null = null;

export function initLocationAccess(ctx: common.UIAbilityContext): void {
  locationContext = ctx;
}

// GeoAddress → 单行中文地址（有效段直接拼接——中文地址连写惯例，可选字段 ?? 空串跳过；
// 全空返回 '' 由调用方省略 address 字段）
function composeAddress(addr: geoLocationManager.GeoAddress): string {
  return (addr.countryName ?? '') + (addr.administrativeArea ?? '') +
    (addr.locality ?? '') + (addr.subLocality ?? '') +
    (addr.roadName ?? '') + (addr.placeName ?? '');
}

// 获取当前位置执行器：开关守卫 → 运行期授权（已授零弹窗）→ 缓存优先/实时兜底 →
// 逆地理尽力而为 → JSON 载荷。业务失败统一 {error: 中文文案}（工具域统一形态，
// detectErrorResult 据此判失败态），不抛错（executeToolCall 包底之外自防可观测文案）
export class LocationExecutor implements ToolExecutor {
  async execute(_argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    const ctx: common.UIAbilityContext | null = locationContext;
    if (ctx === null) {
      return JSON.stringify({ error: '定位功能未初始化，请重启应用后重试' });
    }
    // ① 定位总开关（系统级——关着定位接口不可能成功，先拦给明确文案，模型不白耗重试）
    let enabled: boolean = false;
    try {
      enabled = geoLocationManager.isLocationEnabled();
    } catch (e) {
      enabled = false;
    }
    if (!enabled) {
      return JSON.stringify({
        error: '定位服务未开启。请让用户打开系统定位开关后重试，本次不要重复调用'
      });
    }
    // ② 运行期授权（本仓首个 user_grant 路径：已授零弹窗直通；首次调用弹一次系统授权框）
    const granted: boolean = await this.ensurePermissions(ctx);
    if (!granted) {
      return JSON.stringify({
        error: '未获得定位权限，无法获取位置。可让用户在系统设置的应用权限管理中为本应用开启位置权限后重试'
      });
    }
    // ③ 定位（缓存新鲜直用省电——官方推荐；超窗或无缓存走单次实时定位，速度优先）
    let loc: geoLocationManager.Location | null = null;
    try {
      const cached: geoLocationManager.Location = geoLocationManager.getLastLocation();
      if (Date.now() - cached.timeStamp <= LOCATION_FRESH_MS) {
        loc = cached;
      }
    } catch (e) {
      // 无缓存（错误码 3301101 系）——落下方实时定位，不静默丢
    }
    if (loc === null) {
      try {
        const request: geoLocationManager.SingleLocationRequest = {
          locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
          locatingTimeoutMs: LOCATION_TIMEOUT_MS
        };
        loc = await geoLocationManager.getCurrentLocation(request);
      } catch (err) {
        const code: number = (err as BusinessError).code;
        return JSON.stringify({ error: '定位失败，请稍后重试。错误码 ' + code });
      }
    }
    // ④ 逆地理编码（尽力而为：服务可用才调、失败静默省略 address——定位结果本体不受影响）
    let address: string = '';
    try {
      if (geoLocationManager.isGeocoderAvailable()) {
        const geoReq: geoLocationManager.ReverseGeoCodeRequest = {
          latitude: loc.latitude,
          longitude: loc.longitude,
          maxItems: 1
        };
        const addresses: geoLocationManager.GeoAddress[] =
          await geoLocationManager.getAddressesFromLocation(geoReq);
        if (addresses.length > 0) {
          address = composeAddress(addresses[0]);
        }
      }
    } catch (e) {
      // 地址尽力而为——失败省略字段，不阻断定位结果
    }
    // ⑤ 结果载荷（WGS-84 口径写进载荷，模型无需猜坐标系；时间戳毫秒 UTC）
    const result: LocationToolResult = {
      latitude: loc.latitude,
      longitude: loc.longitude,
      accuracy: loc.accuracy,
      altitude: loc.altitude,
      timeStamp: loc.timeStamp,
      coordinateSystem: 'WGS-84'
    };
    if (address !== '') {
      result.address = address;
    }
    return JSON.stringify(result);
  }

  // 双权限确保：先查后申——两权均已授零弹窗；否则 requestPermissionsFromUser 一次申请
  //（精准必须与模糊同时申请），以申请后复查为准（拒绝/永久拒绝系统不弹或直接返回拒绝，
  // 统一 false 由调用方给文案，不做二次拉起）
  private async ensurePermissions(ctx: common.UIAbilityContext): Promise<boolean> {
    const wanted: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'];
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    if (this.allGranted(atManager, wanted)) {
      return true;
    }
    try {
      await atManager.requestPermissionsFromUser(ctx, wanted);
    } catch (e) {
      return false;
    }
    return this.allGranted(atManager, wanted);
  }

  // 逐权查态（getSelfPermissionStatus @since 20 同步 API，PermissionPage 同款）；
  // 单权查询异常按未授处理（fail-safe 方向）
  private allGranted(atManager: abilityAccessCtrl.AtManager, wanted: Permissions[]): boolean {
    for (const p of wanted) {
      try {
        if (atManager.getSelfPermissionStatus(p) !== abilityAccessCtrl.PermissionStatus.GRANTED) {
          return false;
        }
      } catch (e) {
        return false;
      }
    }
    return true;
  }
}
