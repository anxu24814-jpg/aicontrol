// 出站治理纯逻辑：只承载「可被判据直跑」的纯函数与两个有界状态机——网络调用 / 回执组装 /
// 偏好读写全在消费件 providers/ToolHttp。四件事：
// ①Retry-After 解析——上游限流信号（秒数或 HTTP 日期两形态）→ 等待秒数（封顶）；
// ②retriable 分类——HTTP 状态码与 http kit 网络层码两路，回答「重发一次是否有意义」；
// ③每域名出站闸 HttpHostGate——最小间隔限速（用户可配档）+ Retry-After 熔断（上游信号
//   驱动、恒生效）两态同表；被拒请求直接回执、不发出（保护对方服务，也不烧真实往返）；
// ④会话内校验缓存 HttpValidatorCache——GET 响应的 ETag / Last-Modified 存成条件请求
//   验证器，同 URL 再请求带 If-None-Match / If-Modified-Since，对方回 304 即「未变」短回执。
//   ★ 档次边界：这是**验证器缓存**不是正文缓存——内容是否变化由对方按验证器判定，本应用
//   不替对方下新鲜度结论，不存在「拿旧正文当新事实」的窗口（kit 级 usingCache 恒 false 的
//   既有纪律不受影响，坑33）。
// 零 import 叶子（坑50——本件禁引任何工具域件）；全部导出供 assert-tool-domain 直跑副本
// 做执行级验证。
// ★ 两条纪律：①顶层零跨绑定读写（副本剥 import 后能被 Node 直接装载——两实例由消费件
//   惰性构造）；②状态表条数有界（宪法「数据有界」，见上限常量），会话维度由消费件经
//   ensureSession 对齐。

// Retry-After 上限（秒）：上游可任填（例如 86400），不封顶 = 一条响应把域名锁死一天——
// 300 秒 = 一轮对话内可恢复的量级；超出按 300 截断（宁可早放行再被限一次，不可静默长停摆）
export const HTTP_RETRY_AFTER_MAX_SECONDS: number = 300;
// 出站闸表上限（域名数）与校验缓存表上限（URL 数）：超出按最旧淘汰（见各自 evict 注释）
export const HTTP_HOST_GATE_MAX_HOSTS: number = 64;
export const HTTP_VALIDATOR_CACHE_MAX_ENTRIES: number = 32;

// Retry-After 头解析（纯函数）：RFC 9110 两形态——delta-seconds 与 HTTP 日期都收，结果
// 秒数向上取整；无信号 / 不可解析（空串 / 乱串 / 已过去的时间）一律 0 = 不熔断照常请求，
// 解析成功者封顶 HTTP_RETRY_AFTER_MAX_SECONDS。nowMs 由调用方传（纯函数不读墙钟，判据
// 可喂固定时刻）
export function parseRetryAfterSeconds(value: string, nowMs: number): number {
  const text: string = value.trim();
  if (text === '') {
    return 0;
  }
  if (/^[0-9]+$/.test(text)) {
    // 全数位串走增量秒形态（parseInt 对超长串至多给 Infinity，Math.min 收口到上限）
    return Math.min(parseInt(text, 10), HTTP_RETRY_AFTER_MAX_SECONDS);
  }
  const at: number = Date.parse(text);
  if (!Number.isFinite(at)) {
    return 0;
  }
  const deltaMs: number = at - nowMs;
  if (deltaMs <= 0) {
    return 0;
  }
  return Math.min(Math.ceil(deltaMs / 1000), HTTP_RETRY_AFTER_MAX_SECONDS);
}

// 状态码 → 「重发一次是否有意义」（纯函数）：5xx = 服务端瞬时故障可重试；4xx 里只三码可
// 重试——408 请求超时 / 425 太早 / 429 限流（语义都是「请求本身没错，时机不对」）；其余
// 4xx 重发同样失败。「不可重试」只在模型侧生效（本域无自动重试）——让模型别白撞、把原因
// 讲清；3xx 与 2xx 不属失败面恒 false（调用方只在失败回执上消费本函数）
export function httpStatusRetriable(status: number): boolean {
  if (status >= 500) {
    return true;
  }
  return status === 408 || status === 425 || status === 429;
}

// http kit 码 → 网络层异常是否可重试（纯函数；码源 = 本地 SDK `@ohos.net.http.d.ts` 各
// request 重载 @throws 清单）。**确定性失败报不可重试**（重发不会变好，报可重试 = 把模型
// 引进白撞循环）：证书 / 加密类 2300058 · 2300059 · 2300060（本机证书 / 套件协商 / 对方
// 证书无效）、系统策略类 2300997 · 2300998、请求与协议类 2300001 · 2300003 · 2300061、
// 重定向上限 2300047、接收超限 2300063。其余一律可重试：连接 / 解析 / 超时 / 收发失败 /
// 空响应属通信类（多为瞬态），**未知码也按瞬态处理**——误判可重试的代价 = 多试一次，误判
// 不可重试的代价 = 功能静默不可用，故码表未跟进的新码落可重试侧，方向安全
export function httpNetworkRetriable(code: number): boolean {
  if (code === 2300058 || code === 2300059 || code === 2300060) {
    return false;
  }
  if (code === 2300997 || code === 2300998) {
    return false;
  }
  if (code === 2300001 || code === 2300003 || code === 2300061 || code === 2300047 ||
    code === 2300063) {
    return false;
  }
  return true;
}

// URL → 域名键（纯函数；限速与熔断的表键）。自 scheme://[user@]host[:port]/path?q#f 取
// host[:port] 小写形：端口不同 = 不同服务（同主机两端口互不牵连）；userinfo 先删（凭据不
// 进键，也防 `a@b` 把主机名读错）；IPv6 方括号形态原样保留。**无 scheme 的裸串返 ''**——
// 解析不出可信主机就不建键（fail-open：判定不了就不限制；真请求路径上 URL 校验层另有拦截）
export function httpHostOfUrl(url: string): string {
  let rest: string = url.trim();
  const schemeAt: number = rest.indexOf('://');
  if (schemeAt < 0) {
    return '';
  }
  rest = rest.substring(schemeAt + 3);
  // 权限段 = 首个 `/`、`?`、`#` 之前的部分（三者取最先者）
  let end: number = rest.length;
  const stops: string[] = ['/', '?', '#'];
  for (const stop of stops) {
    const at: number = rest.indexOf(stop);
    if (at >= 0 && at < end) {
      end = at;
    }
  }
  let authority: string = rest.substring(0, end);
  const userAt: number = authority.lastIndexOf('@');
  if (userAt >= 0) {
    authority = authority.substring(userAt + 1);
  }
  return authority.toLowerCase();
}

// 每域名闸状态：lastSentMs = 上次真实放行时刻（-1 哨兵——不能用 0，判据直跑喂小数值时刻
// 会把 0 误判成「刚发过」），blockedUntilMs = 熔断解禁时刻（0 = 无熔断）
interface HttpHostGateState {
  lastSentMs: number;
  blockedUntilMs: number;
}

// 每域名出站闸（限速 + 熔断；模块级单例由消费件持有——作用域 = 进程，跨 run 有效）。
// 两个机制刻意独立：限速 = 主动节奏（用户档位可关），熔断 = 响应上游明示信号（恒生效）
export class HttpHostGate {
  private states: Map<string, HttpHostGateState> = new Map<string, HttpHostGateState>();

  // 放行判定：返回 0 = 放行（并登记本次发出时刻），> 0 = 暂缓的毫秒数（调用方据此出
  // 「稍后重试」回执，请求不发出）。判定次序 = 熔断 → 限速（熔断是上游明示信号，优先）。
  // ★ 被拒请求**不更新** lastSentMs——若更新，「等一会儿再试」会被自己的拒签续期而永远
  // 等不到放行（自锁）。minIntervalMs <= 0 = 关闭限速（熔断两支不受影响）
  admit(host: string, nowMs: number, minIntervalMs: number): number {
    if (host === '') {
      return 0; // 空键 fail-open（见 httpHostOfUrl 注释）
    }
    const state: HttpHostGateState = this.stateOf(host);
    if (state.blockedUntilMs > nowMs) {
      return state.blockedUntilMs - nowMs;
    }
    if (minIntervalMs > 0 && state.lastSentMs >= 0 &&
      state.lastSentMs + minIntervalMs > nowMs) {
      return state.lastSentMs + minIntervalMs - nowMs;
    }
    state.lastSentMs = nowMs;
    return 0;
  }

  // 上游限流信号登记（429 / 503 回执带 Retry-After 时由消费件调用）：把该域名的解禁时刻
  // 推到 now + seconds。取 max 不缩短既有窗口——两条并发响应的信号以更晚者为准，半途缩短
  // 等于把「对方要求等多久」的解释权交给先到的那条。seconds <= 0 = 无信号零动作
  noteRetryAfter(host: string, seconds: number, nowMs: number): void {
    if (host === '' || seconds <= 0) {
      return;
    }
    const until: number = nowMs + seconds * 1000;
    const state: HttpHostGateState = this.stateOf(host);
    if (until > state.blockedUntilMs) {
      state.blockedUntilMs = until;
    }
  }

  // 取或建（表满先淘汰最旧）：淘汰只损失一条历史——该域名下次限速判定从零起算（保护弱
  // 一档）。★ 订正口径（原「熔断语义不受影响」是过宽承诺）：被淘汰者若恰带未到期熔断
  //（64 域名满表且其 lastSentMs 最旧时才可能），该域名下一次请求照发、对方会再回 429/503
  // 重建窗口——漏一次、自愈一次，代价有界，不为此加复杂度
  private stateOf(host: string): HttpHostGateState {
    const existing: HttpHostGateState | undefined = this.states.get(host);
    if (existing !== undefined) {
      return existing;
    }
    if (this.states.size >= HTTP_HOST_GATE_MAX_HOSTS) {
      this.evictOldest();
    }
    const created: HttpHostGateState = { lastSentMs: -1, blockedUntilMs: 0 };
    this.states.set(host, created);
    return created;
  }

  private evictOldest(): void {
    let oldestKey: string = '';
    let oldestMs: number = Number.MAX_SAFE_INTEGER;
    this.states.forEach((state: HttpHostGateState, key: string): void => {
      if (state.lastSentMs < oldestMs) {
        oldestMs = state.lastSentMs;
        oldestKey = key;
      }
    });
    if (oldestKey !== '') {
      this.states.delete(oldestKey);
    }
  }
}

// 条件请求验证器（一条 = 一个 URL 的 ETag / Last-Modified；两者各自可缺，全空不入表）
export interface HttpCacheValidators {
  etag: string;
  lastModified: string;
}

// 会话内校验缓存（条件请求去重；模块级单例由消费件持有）。「会话结束即失效」的落法 =
// ensureSession 按会话 id 分表——会话切换即清，防旧会话的验证器让新会话收到 304 而正文
// 从未在本会话出现过（页面临时 id 与真实会话 id 一视同仁：id 变了就清）
export class HttpValidatorCache {
  private sessionId: string = '';
  private entries: Map<string, HttpCacheValidators> = new Map<string, HttpCacheValidators>();

  ensureSession(conversationId: string): void {
    if (this.sessionId === conversationId) {
      return;
    }
    this.sessionId = conversationId;
    this.entries.clear();
  }

  lookup(url: string): HttpCacheValidators | undefined {
    return this.entries.get(url);
  }

  // 入库（GET 成功回执才该调；两值全空 = 对方不支持条件请求，不占表位）。表满 FIFO 汰旧
  //（Map 保插入序；条数上限的职责是防无界，不是命中率调优）
  store(url: string, etag: string, lastModified: string): void {
    if (url === '' || (etag === '' && lastModified === '')) {
      return;
    }
    if (!this.entries.has(url) && this.entries.size >= HTTP_VALIDATOR_CACHE_MAX_ENTRIES) {
      let firstKey: string = '';
      for (const key of this.entries.keys()) {
        firstKey = key;
        break;
      }
      if (firstKey !== '') {
        this.entries.delete(firstKey);
      }
    }
    const validators: HttpCacheValidators = { etag: etag, lastModified: lastModified };
    this.entries.set(url, validators);
  }
}
