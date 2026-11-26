// 出站请求身份与代理域：全局 User-Agent 的取值、净化与写入单源 + 出站代理（三档 × 双协议）
// 的解析与写入单源。职责一句话 = 「应用以什么身份发请求、经不经过代理」——其余各链只调
// 本件动词（defaultUserAgent 拼默认 / sanitizeUserAgent 净化 / applyDefaultUserAgent 兜底
// 写入 / applyEffectiveProxy 兜底写入 options / setCachedProxyPassword 代理密码缓存写点），
// 禁在别处出现第二份「剔控制字符 / 长度截断 / 默认值拼接 / 大小写不敏感写入 / host:port
// 解析」实现。
// · 注入语义（全族一致）：协议内置头 → 全局 UA 兜底（仅当此刻头表无任何 UA 变体）→ 自定义
//   头逐条合并（UA 名走 setHeaderCaseInsensitive）——自定义头仍可覆盖全局 UA，与
//   AiConnection.headers「允许覆盖内置头」既有语义零冲突。
// · 安全面（CRLF 注入，双端净化）：UA 值来自用户输入，含 \r\n 的头值可把一条头拆成两条伪造
//   头。写侧（UI onChange）剔控制字符防输入中途出换行；取值侧（effectiveUserAgent）再净化
//   一次——防备份导入等第二写键方绕开 UI 校验，这不是防御性冗余是红线。
// · 例外链：网页抓取与 Bing local 搜索恒带浏览器 UA（WebSearch.ets 自持常量），刻意不引本
//   件——抓网页需要浏览器身份，吃全局自定义值反而更易被拒。
// · 版本读取：照 AboutPage.readBundleInfo 口径（GET_BUNDLE_INFO_WITH_APPLICATION 标志 +
//   try/catch 不静默），首次成功后缓存模块级变量（进程内 versionName 不变，禁每请求重查；
//   失败不缓存——下次调用重试，退化值不钉死进程）。
// · 顶层零外部绑定求值（坑50 红线）：本件顶层只有常量字面量；bundleManager 与 AppStorage
//   都在函数体内调用，import 面 = AbilityKit + NetworkKit（类型引用）+ AppPreferences
//   （叶子零 import）+ hilog（仅函数体内打点）无环。
// · 为何不并入既有件（反碎片下限②）：注入点横跨 providers/ 与 components/settings/ 两域，
//   且需 bundleManager；并入 AppPreferences 会破其「刻意保持零 import（叶子模块）」契约，
//   并入任一 provider 件会引入跨域依赖。
import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getNetProxyAddr, getNetProxyBypassLines, getNetProxyUser, getUserAgentPref,
  NET_PROXY_MODE_CUSTOM, NET_PROXY_MODE_DIRECT, NET_PROXY_TYPE_SOCKS5, netProxyMode,
  netProxyType } from '../AppPreferences';

// 头名单源（写入与判定共引；HTTP 头名不分大小写，比较一律经 isUserAgentName）
export const USER_AGENT_HEADER: string = 'User-Agent';
// 长度上限——与自定义头面板 ProviderHeadersPanel.HEADER_VALUE_MAX 同口径（500，该件局部
// 常量不导出；本值管 UA 全链：输入 maxLength 与 sanitize 截断共用，禁写第二份数字）
export const USER_AGENT_LEN_MAX: number = 500;
// 默认 UA 应用名（默认值 = 应用名 + '/' + 运行时 versionName，如 AiControl/1.6.0——版本号
// 禁写字面量，见 defaultUserAgent）
export const DEFAULT_UA_APP_NAME: string = 'AiControl';
// 版本名进程内缓存（'' = 未取到；只缓存成功形态，失败下次重试）
let cachedVersionName: string = '';

// 默认 UA：AiControl/<versionName>；版本经 bundleManager.getBundleInfoForSelfSync 取（照
// AboutPage.readBundleInfo 的 flag 与判空口径——WITH_APPLICATION 标志下顶层 versionName 恒
// 可用）；取不到版本退化为 AiControl。UI 说明行拼接本函数（禁硬编码版本串）
export function defaultUserAgent(): string {
  if (cachedVersionName === '') {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      if (typeof info.versionName === 'string' && info.versionName !== '') {
        cachedVersionName = info.versionName;
      }
    } catch (err) {
      hilog.error(0xD5A0, 'RequestIdentity', 'read version for default UA failed: %{public}s',
        JSON.stringify(err));
    }
  }
  return cachedVersionName !== '' ? DEFAULT_UA_APP_NAME + '/' + cachedVersionName : DEFAULT_UA_APP_NAME;
}

// 净化：剔 C0 控制字符与 \u007F（含 \r/\n，防 CRLF 注入）→ 按上限截断 → 去首尾空白。
// UI onChange 与取值侧（effectiveUserAgent）同一实现，禁第二份
export function sanitizeUserAgent(raw: string): string {
  const stripped: string = raw.replace(/[\u0000-\u001F\u007F]/g, '');
  const capped: string = stripped.length > USER_AGENT_LEN_MAX ?
    stripped.substring(0, USER_AGENT_LEN_MAX) : stripped;
  return capped.trim();
}

// 生效 UA：读偏好 → 净化（取值侧再净化，防备份导入绕开 UI 校验）→ 空串回默认值
//（「留空 = 用默认」语义，文案须写清）
export function effectiveUserAgent(): string {
  const clean: string = sanitizeUserAgent(getUserAgentPref());
  return clean !== '' ? clean : defaultUserAgent();
}

// 头名是否 UA（大小写不敏感——HTTP 头名不分大小写，自定义头可写 user-agent / USER-AGENT）
export function isUserAgentName(name: string): boolean {
  return name.trim().toLowerCase() === USER_AGENT_HEADER.toLowerCase();
}

// 大小写不敏感写入：头表已有同名变体（不论大小写）则原位覆写（保键序、防线上出现两条
// UA）；没有才按传入名新增。ArkTS 禁 delete，靠「变体至多一条」不变量（内置头零 UA +
// 自定义头全走本函数）保证不累积变体
export function setHeaderCaseInsensitive(header: Record<string, string>, name: string,
  value: string): void {
  const lower: string = name.trim().toLowerCase();
  const keys: string[] = Object.keys(header);
  for (const key of keys) {
    if (key.toLowerCase() === lower) {
      header[key] = value;
      return;
    }
  }
  header[name] = value;
}

// 全局 UA 兜底写入：此刻头表已有任何 UA 变体（含自定义头先行写入）则不动；否则写生效值。
// 注入族统一在「内置头之后、自定义头合并之前」调本函数
export function applyDefaultUserAgent(header: Record<string, string>): void {
  const keys: string[] = Object.keys(header);
  for (const key of keys) {
    if (isUserAgentName(key)) {
      return;
    }
  }
  header[USER_AGENT_HEADER] = effectiveUserAgent();
}

// ── 代理域 ──
// 三档语义（本地 d.ts + 官方 FAQ faqs-network-142 双源核对）：system = 不写 usingProxy 字段
//（走系统默认代理 = 接本域前行为逐字节一致）/ direct = usingProxy: false / custom = 按
// PREF_NET_PROXY_TYPE_KEY 分协议——http 档写 usingProxy: {host, port, exclusionList,
// username?, password?}，socks5 档写 usingSocks5Proxy: {同形}（SOCKS5 为 API 26 起原生字段，
// 本地 d.ts 实读、官方索引暂未收录专篇；★ 官方注两字段勿同配且 SOCKS5 优先，本函数互斥只写
// 其一）。exclusionList = 绕过列表（平台原生匹配，官方规则：域名标签级部分/精确匹配、IP
// 精确、单个 * 通配）。
// ★ 消费面除 UA 族六件外含两类**纯代理出口**（吃 UA 于共享构造器、自身不打的 OCR 请求与
// T1 探针；不吃 UA 的代理测试键——非 API 请求无身份语义）。例外链：网页抓取与 Bing local
//（WebSearch.ets 自持浏览器 UA，刻意不引本件）、HTTP 请求工具（ToolHttp.ets，HelpContent
// 明载不受影响）与 FeedbackMeow 反馈推送（国内推送通道直连更稳）——四处均不吃代理。断言
// 按「代理接线数 ≥ UA 调用数」逐文件关系钉守（assert-net-parse 191 组③）。原「不做代理
// 认证与 SOCKS5」边界由决明拍板解禁（三拍板：卡内嵌类型分段 / 平台原生绕过匹配 / 密码
// Asset 加密存储，实施细节见变更记录）。

// 代理密码进程内缓存（'' = 未配置或尚未载入）。Asset 读取是异步而出站代理写入是同步单点
//（applyEffectiveProxy 被各出口在 request 前同步调用），故 Asset 明文只在两处写点回填本
// 缓存：EntryAbility 启动预载（onCreate 内 await，消除首请求认证竞态）+ 设置页保存/清除在
// Asset 落定后同刷。禁在请求链上直接 await KeyStore 读密码——会把同步收口拆散
let cachedProxyPassword: string = '';

// 密码缓存写点（唯一入口：KeyStore.saveProxyPassword / removeProxyPassword 的调用方在
// Asset 写成后调用；预载链同走本函数）
export function setCachedProxyPassword(password: string): void {
  cachedProxyPassword = password;
}

// host:port 解析产物（纯数据接口，HttpProxy 的 UI 侧预检形态）
export interface NetProxyEndpoint {
  host: string;
  port: number;
}

// host:port 解析（纯函数；UI 输入校验与 applyEffectiveProxy 取值侧同函数双端一致——UA
// 双端净化同款红线，防备份导入等第二写键方绕开 UI 校验）。最后一个冒号分界，host 非空、
// port 为纯十进制数字且在 [0, 65535]（connection.d.ts 实读合法域）。返回 null = 非法。
// IPv6 字面量 host 兼容：lastIndexOf 取最后一冒号，'::1:7890' 解出 host '::1'
export function parseNetProxyAddr(raw: string): NetProxyEndpoint | null {
  const text: string = raw.trim();
  const idx: number = text.lastIndexOf(':');
  if (idx <= 0 || idx >= text.length - 1) {
    return null;
  }
  const host: string = text.substring(0, idx).trim();
  const portText: string = text.substring(idx + 1).trim();
  if (host === '' || !/^\d+$/.test(portText)) {
    return null;
  }
  const port: number = Number.parseInt(portText, 10);
  if (port > 65535) {
    return null;
  }
  return { host: host, port: port };
}

// 生效代理兜底写入（applyDefaultUserAgent 同形动词）：注入族统一在 options 构造后、发起
// 请求前调本函数。分支语义——direct → usingProxy: false；system 档或地址解析失败 → 零介入
//（options 保持原样，坏配置不至于让请求整体不可用）；custom → 按协议类型互斥写 usingProxy
//（http）或 usingSocks5Proxy（socks5），二者均挂绕过列表与认证字段（账号密码齐全才写——
// username 无 password 在平台侧不生效，connection.d.ts 字段注实读；两接口字段同名但型异，
// ArkTS 不做联合写入，各自赋值）
export function applyEffectiveProxy(options: http.HttpRequestOptions): void {
  const mode: string = netProxyMode();
  if (mode === NET_PROXY_MODE_DIRECT) {
    options.usingProxy = false;
    return;
  }
  if (mode !== NET_PROXY_MODE_CUSTOM) {
    return;
  }
  const endpoint: NetProxyEndpoint | null = parseNetProxyAddr(getNetProxyAddr());
  if (endpoint === null) {
    return;
  }
  const bypass: string[] = getNetProxyBypassLines();
  const username: string = getNetProxyUser();
  const authed: boolean = username !== '' && cachedProxyPassword !== '';
  if (netProxyType() === NET_PROXY_TYPE_SOCKS5) {
    const proxy: http.Socks5Proxy = { host: endpoint.host, port: endpoint.port,
      exclusionList: bypass };
    if (authed) {
      proxy.username = username;
      proxy.password = cachedProxyPassword;
    }
    options.usingSocks5Proxy = proxy;
    return;
  }
  const proxy: http.HttpProxy = { host: endpoint.host, port: endpoint.port,
    exclusionList: bypass };
  if (authed) {
    proxy.username = username;
    proxy.password = cachedProxyPassword;
  }
  options.usingProxy = proxy;
}
