// HTTP 工具域·Cookie 会话保持域。职责一句话 = 「按 host 有界存储响应 cookie、在会话内
// 回带」。零 import 工具域（坑50）；全部导出供 assert-tool-domain 直跑副本执行级验证。
// · 为什么自建：官方 enableAutoCookie（@ohos.net.http d.ts @since 26）的共享语义是
// **同一 HttpRequest 实例内**——本工具链一建一销（成对释放红线），跨请求实例不共享，官方
// 面用不上；两家竞品均无 jar 可抄，故自建裁剪版。
// · 边界：①只存「name=value」净值——expires / path / domain / secure 等 cookie 属性不解析
//  （进程内会话粒度全收全带，path 语义不做）；②进程内内存态、按会话分桶各持各表（分栏
//   并发会话互不干扰，详见类注释）、进程退出即清、零持久化；③有界 = 会话桶数 + 每 host
//   条数 / 单条字符 / host 总字符 / host 数五限，超限丢最旧或截断；④收割面 = 同步路径
//   resp.cookies（官方聚合串）且 redirectCount = 0（非重定向——kit 自动跟跳拿不到每跳
//   host，跨域重定向的 set-cookie 若按首跳 host 落表 = 记错名下、下次发给错对象，宁缺勿
//   错）；⑤回带面 = 只查本会话本请求 host 的表（天然不跨域不跨会话）；⑥用户显式给的
//   Cookie 头恒优先，jar 不覆盖（回带只补缺）。

// ── 有界常量 ──
// 每 host 条数上限与单条字符上限：对「会话型少数几个 cookie」数量级富余，防病态服务端灌表
export const HTTP_COOKIE_PER_HOST_MAX: number = 20;
export const HTTP_COOKIE_PAIR_MAX_CHARS: number = 512;
// 每 host 总字符上限（条数闸的总量补——20 条 × 512 = 10KB 理论叠乘仍偏大，4096 收口）
export const HTTP_COOKIE_HOST_TOTAL_MAX_CHARS: number = 4096;
// host 表上限：超限淘汰最旧 host（照 HttpHostGate 淘汰先例——只损失一条历史，下次响应
// 重建，保护弱一档）
export const HTTP_COOKIE_HOSTS_MAX: number = 32;
// 会话桶上限（分桶后唯一的跨桶容量闸）：超限淘汰最旧未活跃桶（LRU：storeFromResponse
// 触达即重插挪尾），只丢该会话登录态、下次响应重建，保护弱一档
export const HTTP_COOKIE_BUCKETS_MAX: number = 8;

// 响应 cookie 聚合串 → 「name=value」段清单（纯函数，直跑）。解析限条数 / 单条 / 总量
// 三闸；无 '='、空名、空值的段丢弃；★ 属性段过滤：d.ts 对 resp.cookies 只说 "Original
// cookies returned by the server" 未定义聚合形态，官方文档与社区实测均指向「原始
// Set-Cookie 串」——含 Path=/ / Domain=… / Expires=… / SameSite=… 等属性段，原实现按
//「官方已拼好键值形态」假设会把属性段当 cookie 收编并回带给服务端，已知属性名单（大小写
// 不敏感）在此过滤（已剥属性的形态名单零命中，行为不变）；同名后到覆盖先到（Map 保插入
// 序——覆盖只改值不挪位，丢最旧时牺牲的是最旧的**首次出现**，语义稳妥）。多 Set-Cookie
// 聚合分隔符若为逗号（Expires 值内含逗号有二义）无法完美处理——留真机验证（BLOCKED 清单）
const COOKIE_ATTR_NAMES: string[] = ['path', 'domain', 'expires', 'max-age', 'secure',
  'httponly', 'samesite', 'partitioned'];

export function parseCookiePairs(raw: string): string[] {
  const text: string = raw.trim();
  if (text === '') {
    return [];
  }
  const byName: Map<string, string> = new Map<string, string>();
  let used: number = 0;
  const segments: string[] = text.split(';');
  for (const seg of segments) {
    const pair: string = seg.trim();
    const eq: number = pair.indexOf('=');
    if (eq <= 0 || eq >= pair.length - 1) {
      continue;
    }
    const name: string = pair.substring(0, eq).trim();
    if (COOKIE_ATTR_NAMES.includes(name.toLowerCase())) {
      continue;
    }
    let value: string = pair.substring(eq + 1).trim();
    if (name === '' || value === '') {
      continue;
    }
    if (value.length > HTTP_COOKIE_PAIR_MAX_CHARS) {
      value = value.substring(0, HTTP_COOKIE_PAIR_MAX_CHARS);
    }
    if (!byName.has(name)) {
      used += name.length + value.length + 3;
      if (used > HTTP_COOKIE_HOST_TOTAL_MAX_CHARS || byName.size >= HTTP_COOKIE_PER_HOST_MAX) {
        break;
      }
    }
    byName.set(name, value);
  }
  const out: string[] = [];
  byName.forEach((value: string, name: string): void => {
    out.push(name + '=' + value);
  });
  return out;
}

// 段清单 → Cookie 请求头值（纯函数，直跑）：'; ' 连接（RFC 6265 Cookie 头形态）。空清单
// = 空串（调用方以空串判「不注入」）
export function buildCookieHeader(pairs: string[]): string {
  return pairs.join('; ');
}

// Cookie jar（进程内单例由消费件惰性构造——模块顶层不 new：assert 副本剥 import 后顶层
// 求值会炸，坑50 家族纪律）
// ★ 并发修复改形：单表「id 变即清」改按会话分桶（convId → host → name=value）——jar 是
// 进程级单例而 executeFlow 每次都 ensureSession，分栏双会话交替跑工具时互清对方 cookie
//（A 请求在途时 B 的 ensureSession 清掉 A 刚收的）；分桶后互不干扰，会话隔离由「回带/
// 收割都带会话键、只碰本会话桶」承担（跨会话串发与互清同根同修），ensureSession 只剩
// 触达当前桶一职。同会话行为（桶内四限、属性过滤、同名覆盖序）逐字不变
export class HttpCookieJar {
  private buckets: Map<string, Map<string, Map<string, string>>> =
    new Map<string, Map<string, Map<string, string>>>();

  // 会话对齐（触达当前桶，不清任何桶——旧会话的登录态不带给新会话由回带侧「只查本会话
  // 桶」保证；无行会话的页面临时 id 与真实 id 一视同仁，各归各桶）
  ensureSession(conversationId: string): void {
    this.touchBucket(conversationId);
  }

  // 收割入库（同步路径非重定向响应才调——见文件头边界④）：按会话键落本会话桶；
  // host = 请求 host（收割归属判据，执行链传 policyHost）。空 host / 空串零动作
  storeFromResponse(conversationId: string, host: string, rawCookies: string): void {
    if (host === '' || rawCookies.trim() === '') {
      return;
    }
    const bucket: Map<string, Map<string, string>> = this.touchBucket(conversationId);
    let store: Map<string, string> | undefined = bucket.get(host);
    if (store === undefined) {
      if (bucket.size >= HTTP_COOKIE_HOSTS_MAX) {
        this.evictOldestHost(bucket);
      }
      store = new Map<string, string>();
      bucket.set(host, store);
    }
    const pairs: string[] = parseCookiePairs(rawCookies);
    for (const pair of pairs) {
      const eq: number = pair.indexOf('=');
      store.set(pair.substring(0, eq), pair.substring(eq + 1));
    }
    // 累积有界（原实现只闸条数——多次响应的异名 cookie 各自合规、合计可越限）：条数或
    // 总字符任一越限即删最早插入的条目（Map 插入序首个），直至两闸都回线
    for (;;) {
      let totalChars: number = 0;
      store.forEach((v: string, k: string): void => {
        totalChars += k.length + v.length + 3;
      });
      if (store.size <= HTTP_COOKIE_PER_HOST_MAX &&
        totalChars <= HTTP_COOKIE_HOST_TOTAL_MAX_CHARS) {
        break;
      }
      let firstKey: string = '';
      for (const key of store.keys()) {
        firstKey = key;
        break;
      }
      if (firstKey === '') {
        break;
      }
      store.delete(firstKey);
    }
  }

  // 回带头值（只查本会话本请求 host——跨域天然不回带；只读不触达：无 cookie 的会话不占
  // 桶，LRU 序由收割面驱动）：无记录 = 空串（调用方以空串判「不注入」，无 cookie 请求
  // 零开销零改动）
  cookieHeaderFor(conversationId: string, host: string): string {
    const bucket: Map<string, Map<string, string>> | undefined =
      this.buckets.get(conversationId);
    if (bucket === undefined) {
      return '';
    }
    const store: Map<string, string> | undefined = bucket.get(host);
    if (store === undefined || store.size === 0) {
      return '';
    }
    const pairs: string[] = [];
    store.forEach((value: string, name: string): void => {
      pairs.push(name + '=' + value);
    });
    return buildCookieHeader(pairs);
  }

  // 触达会话桶：在则重插挪尾（LRU），不在则建（超桶上限先汰最旧）
  private touchBucket(conversationId: string): Map<string, Map<string, string>> {
    const existing: Map<string, Map<string, string>> | undefined =
      this.buckets.get(conversationId);
    if (existing !== undefined) {
      this.buckets.delete(conversationId);
      this.buckets.set(conversationId, existing);
      return existing;
    }
    if (this.buckets.size >= HTTP_COOKIE_BUCKETS_MAX) {
      this.evictOldestBucket();
    }
    const fresh: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
    this.buckets.set(conversationId, fresh);
    return fresh;
  }

  // 汰最旧桶：哨兵用 undefined 判「表空」而非判 !== ''——桶键是 conversationId，契约允许
  // 空串（TOOL_SCOPE_SYSTEM 预留 + 无行会话临时 id 同款），空串桶按空串键正常参与淘汰；
  // 若用 '' 哨兵，空串桶沉到首位时每次被选中却被守卫拒删，新桶照建 = 桶数越闸无界
  //（evictOldestHost 的 '' 哨兵无此问题——host 键有调用口空串早退保底）
  private evictOldestBucket(): void {
    let oldestKey: string | undefined = undefined;
    for (const key of this.buckets.keys()) {
      oldestKey = key;
      break;
    }
    if (oldestKey !== undefined) {
      this.buckets.delete(oldestKey);
    }
  }

  private evictOldestHost(bucket: Map<string, Map<string, string>>): void {
    let oldestKey: string = '';
    for (const key of bucket.keys()) {
      oldestKey = key;
      break;
    }
    if (oldestKey !== '') {
      bucket.delete(oldestKey);
    }
  }
}
