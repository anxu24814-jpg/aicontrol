// Web 服务域偏好键与读封装（照 AppPreferencesHttp.ets 域拆分先例）。零 import 叶子（只用
// AppStorage 全局，谁都可引、不引任何人）；BACKUP_PREF_KEYS 对本域键的收录在
// AppPreferencesBackup.ets 备份分域表内以字面量形态登记（与 prefHttp* 族同族先例，
// 键名漂移由 assert-feature-domain 54 组全覆盖钉兜住——改名即红）。
// 键族与缺省：prefWebServiceEnable（bool，false——kill-switch，
// 关 = 零端口监听零行为增量）、prefWebServicePort（number，8800——HTTP 面，WS 面为
// 基数+1 派生不单列键）、prefWebServicePasscode（string，''——首开启时为空则自动生成
// 6 位数字码；口令实现在设置页侧，本件只持键与读口）、prefWebServiceLoopbackOnly
//（bool，false——仅本机档经偏好键生效，不设 UI 行，调试/进阶用；true 时绑定
// 127.0.0.1 且免鉴权）。缺省真源在 EntryAbility persistProp 注册侧，
// 本件常量供注册与读值两侧共引（禁双源）。
// 备份档位：enable/port/loopbackOnly 三元数据键随备份走
//（BACKUP_PREF_KEYS Web 服务段）；passcode 口令类敏感值**不进备份**（登记排除表——
// 换机恢复后为空即重新自动生成，不携带旧口令跨机）。

// ★ kill-switch 总开关键：true = 允许 Web 服务启动 / false = 拒启（manager.start() 入口
// 闸，零端口监听）。fail-closed：未写/非 true 恒 false（含备份导入等第二写键方带来的任意
// 脏值）。UI 写侧 = WebServiceSettingsPage 启动卡主开关 @StorageLink（写即持久化），
// 本件不设写封装
export const PREF_WEB_SERVICE_ENABLE_KEY: string = 'prefWebServiceEnable';

// HTTP 面端口键：取值 1024~65534（clampWebPort 单源钳位，白名单外回缺省；上界 65534 而非
// 65535——WS 面 = 本键值 + 1 派生（WebServiceManager.deriveWsPort 单源，不单列配置项），
// 65535 会派生 65536 越出端口域，WS 面必启动失败）；UI 写侧 = 设置页端口编辑行 @StorageLink
export const PREF_WEB_SERVICE_PORT_KEY: string = 'prefWebServicePort';

// 端口缺省与值域（缺省真源在 persistProp 注册侧共引本常量；8800 固定，避开 8080/3000/5173
// 高碰撞段）
export const WEB_SERVICE_PORT_DEFAULT: number = 8800;
export const WEB_SERVICE_PORT_MIN: number = 1024;
// 上界 65534（WS 面 +1 派生不越 65535——原 65535 派生 WS 65536 非法）
export const WEB_SERVICE_PORT_MAX: number = 65534;

// 端口钳位（读值封装用）：整数且在值域内原样返回，否则回缺省（fail-closed——端口不可
// 用时宁可回 8800 不可拿脏值去 listen；UI 写侧另有编辑校验，此处是运行期兜底闸）
export function clampWebPort(port: number): number {
  if (!Number.isInteger(port) || port < WEB_SERVICE_PORT_MIN || port > WEB_SERVICE_PORT_MAX) {
    return WEB_SERVICE_PORT_DEFAULT;
  }
  return port;
}

// ★ 访问口令键（消费 = WebUI 首消息 {type:'auth', code:口令} 通过即转已鉴权连接；本件只
// 持键与裸读口，口令生成/校验/限速全在设置页侧。'' = 未设置（首次开启自动生成 6 位数字码
// 写入）；**不随备份走**（见文件头备份档位注记）。token 签发/验签/TTL 段不接（每连接首
// 消息带口令已闭环）
export const PREF_WEB_SERVICE_PASSCODE_KEY: string = 'prefWebServicePasscode';

// ★ 仅本机档键：true = 双栈只绑 127.0.0.1 且免鉴权（本机回环面无旁听威胁）/ false =
// 面向局域网，绑**本机 WLAN 具体 IP**（缺省；不用 0.0.0.0 通配——真机底层拒 wildcard，
// 见 WebServiceManager.resolveBindAddress 注记），配合口令鉴权。
// 无 UI 行（调试/进阶用）。fail-closed 语义注意：本键脏值归 **false**（回局域网档）与
// 开关类键的「归 false = 更保守」方向相反——因为本键 false 才是产品缺省态，true 是收窄面；
// 归 false 后仍有口令鉴权兜底，不破安全模型
export const PREF_WEB_SERVICE_LOOPBACK_ONLY_KEY: string = 'prefWebServiceLoopbackOnly';

// ── 读值封装（fail-closed；消费方 = WebServiceManager 启停编排 + 设置页显示）──

// kill-switch 读口（manager.start() 入口闸每启现读——运行中改开关对下一次启停生效）
export function isWebServiceEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_WEB_SERVICE_ENABLE_KEY) === true;
}

// HTTP 端口读口（钳位单源 clampWebPort；键未注册时 AppStorage.get 回 undefined 同落缺省）
export function webServicePort(): number {
  return clampWebPort(AppStorage.get<number>(PREF_WEB_SERVICE_PORT_KEY) ?? WEB_SERVICE_PORT_DEFAULT);
}

// 口令裸读口（'' = 未设置；结构化语义〔6 位数字码校验/token 派生〕全在设置页侧，本件不判形）
export function webServicePasscode(): string {
  return AppStorage.get<string>(PREF_WEB_SERVICE_PASSCODE_KEY) ?? '';
}

// 仅本机档读口（缺省 false = 局域网档；脏值/未写同落 false）
export function isWebServiceLoopbackOnly(): boolean {
  return AppStorage.get<boolean>(PREF_WEB_SERVICE_LOOPBACK_ONLY_KEY) === true;
}
