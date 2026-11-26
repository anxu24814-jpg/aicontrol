// Web 服务鉴权件——首消息口令鉴权的判定与口令生成（恒时比较防时序侧道 + 仅本机档免鉴权 +
// 口令空拒绝全部〔fail-closed ③〕+ 鉴权异常按未认证处理〔fail-closed ④，装配闭包内兜底〕；
// 5s 超时断连〔fail-closed ①〕与未鉴权不进业务路由〔fail-closed ②〕由载体件骨架承担，
// 本件不重复）。
// 消息契约：WebUI 连接后首消息 {"type":"auth","code":"六位口令"}，通过后该连接转已鉴权态；
// type 域判据单源在本件（wsMessageTypeOf 是传输层通用提取，本件的 parseWebAuthMessage 是
// 鉴权面的严格解析——type 须恰为 'auth' 且 code 为 string）。
// 口令为低价值局域网配对码（设置页明文展示供复制），恒时比较按防御纵深原则保留——逐位试探
// 场景下不泄露匹配位置。
// token 配对链后段（HMAC 签发/验签/TTL 30 天）**V1 不接**（拍板：每连接首消息带口令已闭环，
// token 30 天免输列入待拍板/V2 备忘）；每 IP 失败限速在本件（连续 5 次失败锁 60s，LRU 64
// 条有界）。
// 纯函数面（标记段内零 import 依赖，断言脚本剥 import 直跑）；装配面读 AppStorage 实时
// 键——改口令/换档位对下一次连接立即生效，无需重启服务。改口令不即时踢已鉴权连接（无 token
// 链、连接态不在口令变更时回收），下次重连凭旧码即失败——V2 若需即时吊销另建。
// 依赖纪律（零环）：只引本域 TransportCarrier 的钩类型 + AppPreferencesWeb 叶子，禁 import
// UI 件；不 import 任一载体实现件（SSE 中枢与 WS 备用件同用一钩）。
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { CarrierAuthValidator } from './TransportCarrier';
import { isWebServiceLoopbackOnly, webServicePasscode } from '../AppPreferencesWeb';

// ── 纯函数面（零 @kit 依赖，断言脚本剥 import 直跑）──

// 恒时比较：长度先校（不等长直接拒——长度本身非机密，口令固定 6 位），同长则逐位异或
// 累积、不在首位不匹配处短路返回——比较耗时与匹配位置无关，防「逐位试探 + 测响应时间」
// 时序侧道泄露已匹配前缀（first char 命中与全命中耗时相同）
export function constantTimeCodeEquals(actual: string, expected: string): boolean {
  if (actual.length !== expected.length) {
    return false;
  }
  let diff: number = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

// 鉴权首消息解析结果（type 恒 'auth'；code = 客户端提交的口令原文）
export interface WebAuthRequest {
  readonly type: string;
  readonly code: string;
}

// 首消息严格解析：JSON 根对象 + type 恰为 'auth' + code 为 string 才收，其余（脏 JSON /
// 非对象根 / type 不符 / code 缺失或非串）一律回 null = 拒绝（fail-closed——宁可拒不可炸）
export function parseWebAuthMessage(text: string): WebAuthRequest | null {
  try {
    const raw: Object = JSON.parse(text) as Object;
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      return null;
    }
    const rec: Record<string, Object> = raw as Record<string, Object>;
    const t: Object | undefined = rec['type'];
    const c: Object | undefined = rec['code'];
    if (typeof t !== 'string' || t !== 'auth' || typeof c !== 'string') {
      return null;
    }
    const req: WebAuthRequest = { type: t, code: c };
    return req;
  } catch (e) {
    return null;
  }
}

// 回环来源判定：connId = 'ip:port' 自合成形（WsGateway.wsConnIdOf 单源）；仅认 127.0.0.1
// （IPv4 回环——本工程双栈绑定的 loopback 地址即 127.0.0.1，resolveBindAddress 单源）
export function isLoopbackConnId(connId: string): boolean {
  return connId.startsWith('127.0.0.1:');
}

// 鉴权判定总口（断言直跑矩阵）：
// ①仅本机档且来源回环 → 免鉴权（裁定 6：回环面无旁听威胁；档位与来源双条件，局域网
//   档下即使伪造 connId 前缀也无济于事——connId 由服务端从连接对象合成，非客户端可控）；
// ②仅本机档且来源非回环 → 拒绝（档位切换后绑定地址要下次启停才收窄到 127.0.0.1——过渡
//   窗内非本机来源即使口令正确也不放行，与开关字面一致的安全收紧方向）；
// ③口令空且非免鉴权来源 → 拒绝全部（fail-closed ③——含 token 验签在内的全部放行路径
//   收敛于此判定之前）；
// ④首消息解析失败 → 拒绝；
// ⑤恒时比较口令。
export function webAuthGrants(connId: string, firstMessageText: string, passcode: string,
  loopbackOnly: boolean): boolean {
  const loopbackSource: boolean = isLoopbackConnId(connId);
  if (loopbackOnly) {
    return loopbackSource;
  }
  if (passcode === '') {
    return false;
  }
  const req: WebAuthRequest | null = parseWebAuthMessage(firstMessageText);
  if (req === null) {
    return false;
  }
  return constantTimeCodeEquals(req.code, passcode);
}

// 口令自动生成：6 位数字码 100000~999999（首位恒非 0 保六位观感）——用系统密码学随机源
// cryptoFramework（ProviderShare 同源先例），不用可预测的 Math.random（口令是局域网唯一
// 防线）；4 字节拼 uint32 后模 900000，模偏 ~2e-4（可忽略）。首开启时口令键为空由设置页
// 调用写入，「换一个」键同源重生成（旧配对全失效）
export function generateWebPasscode(): string {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const bytes: Uint8Array = random.generateRandomSync(4).data;
  const raw: number = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
  return (100000 + (raw % 900000)).toString();
}

// ── 每 IP 失败限速（5 次失败锁 60s、LRU 64 条有界）──

// 连续失败上限 / 锁定时长 / 条目上限（单源；断言源内现读，禁抄值）
export const WEB_AUTH_FAIL_MAX: number = 5;
export const WEB_AUTH_LOCK_MS: number = 60000;
export const WEB_AUTH_LRU_MAX: number = 64;

// connId → 来源 IP（'ip:port' 自合成形；IPv6 含冒号——取最后一个冒号前段；
// 无冒号 = 原样回，不抛错）
export function authIpOf(connId: string): string {
  const idx: number = connId.lastIndexOf(':');
  return idx > 0 ? connId.substring(0, idx) : connId;
}

// 失败计数条目（fails = 当前锁外累计；lockUntil = 锁定到期绝对时刻，0 = 未锁）
interface WebAuthFailureEntry {
  fails: number;
  lockUntil: number;
}

// 每 IP 失败限速器（进程级单例挂在装配闭包；纯逻辑类便于断言直跑）：
// · allow：锁定期内拒绝（不比对口令，缩短攻击窗口）；锁到期清条目重开；
// · recordFailure：累计到上限即锁 WEB_AUTH_LOCK_MS（锁期内不叠加新锁——allow 已先拒）；
// · recordSuccess：成功即清该 IP 记录（合法设备一次输对不再背历史失败）；
// · 数据有界：条目数 ≤ WEB_AUTH_LRU_MAX，新增前淘汰最旧（Map 插入序；失败访问刷新序）。
export class WebAuthFailureLimiter {
  private entries: Map<string, WebAuthFailureEntry> = new Map<string, WebAuthFailureEntry>();

  allow(ip: string, now: number): boolean {
    const entry: WebAuthFailureEntry | undefined = this.entries.get(ip);
    if (entry === undefined) {
      return true;
    }
    if (entry.lockUntil > now) {
      return false;
    }
    if (entry.lockUntil > 0) {
      this.entries.delete(ip);
    }
    return true;
  }

  recordFailure(ip: string, now: number): void {
    const entry: WebAuthFailureEntry | undefined = this.entries.get(ip);
    if (entry === undefined) {
      this.evictIfNeeded();
      const fresh: WebAuthFailureEntry = { fails: 1, lockUntil: 0 };
      this.entries.set(ip, fresh);
      return;
    }
    // 访问刷新 LRU 序（Map 插入序：先删后置）
    this.entries.delete(ip);
    this.entries.set(ip, entry);
    if (entry.lockUntil > now) {
      return;
    }
    entry.fails++;
    if (entry.fails >= WEB_AUTH_FAIL_MAX) {
      entry.lockUntil = now + WEB_AUTH_LOCK_MS;
      entry.fails = 0;
    }
  }

  recordSuccess(ip: string): void {
    this.entries.delete(ip);
  }

  // 诊断面（有界性自证；断言直跑消费）
  entryCount(): number {
    return this.entries.size;
  }

  private evictIfNeeded(): void {
    if (this.entries.size < WEB_AUTH_LRU_MAX) {
      return;
    }
    let oldest: string = '';
    this.entries.forEach((_entry: WebAuthFailureEntry, key: string): void => {
      if (oldest === '') {
        oldest = key;
      }
    });
    if (oldest !== '') {
      this.entries.delete(oldest);
    }
  }
}

// ── 装配面（manager.start() 每次启服注入——服务不起则零装配，kill-switch 关态零增量）──

// 进程级限速单例（模块加载即建；服务停启不清——攻击计数跨启停保留是更安全方向）
const authFailureLimiter: WebAuthFailureLimiter = new WebAuthFailureLimiter();

// 构造鉴权钩：键值实时读（改口令/换档位对下一次连接立即生效）；回调内异常一律按未认证
// 处理（fail-closed ④，载体骨架另有 try/catch 双保险）。★ 限速接入：免鉴权放行（仅本机档
// + 回环来源）不占限速账；其余先查锁再比对，失败记账、成功清账
export function buildWebServiceAuthValidator(): CarrierAuthValidator {
  return (connId: string, firstMessageText: string): boolean => {
    try {
      const loopbackOnly: boolean = isWebServiceLoopbackOnly();
      if (loopbackOnly && isLoopbackConnId(connId)) {
        return true;
      }
      const ip: string = authIpOf(connId);
      const now: number = Date.now();
      if (!authFailureLimiter.allow(ip, now)) {
        return false;
      }
      const granted: boolean = webAuthGrants(connId, firstMessageText,
        webServicePasscode(), loopbackOnly);
      if (granted) {
        authFailureLimiter.recordSuccess(ip);
      } else {
        authFailureLimiter.recordFailure(ip, now);
      }
      return granted;
    } catch (e) {
      return false;
    }
  };
}
