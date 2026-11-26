// HTTP 准入与防泄露纯函数域（2026-10-01 方案-HTTP工具完善 批 2 笔 3）：域名白名单判据、
// scheme 硬化（URL 内嵌账号密码拒绝 + 云元数据地址恒拒）、出站哨兵（凭据明文扫描）与
// 四类中文错误文案。零 import 叶子（坑50 模块环红线——本件被 ToolHttp 引，禁反向引任何
// 工具域件；判定所需的一切都由调用方传入），导出供断言直跑（照 httpErrorMessage /
// fitHttpResult 四个既有先例：纯函数抽出来给断言执行级验证）。
// 边界（方案档批 2 调研吸收·已定夺）：域名白名单**只约束首跳 URL**——kit 自动跟跳
//（maxRedirects = 5）可能落到名单外域名，不做逐跳校验（帮助条目已写明此边界）；内网
// 不拦的既有口径不变（端侧打内网 = 用户自有局域网，Home Assistant 类设备控制是正当
// 用途），本件只加云元数据地址的卫生性恒拒（端侧无云元数据面，纯兜底）。
// 哨兵阈值：明文扫描只对长度达标的凭据值参与——最小长度由调用方传（单源 = ReqLog 的
// REQ_LOG_REDACT_MIN = 8，勿在本件新立第二套阈值；过短串会误伤正常正文，kelivo 同款
// 判据先例）。

// 云元数据地址表（host 精确匹配，归一后比对）：主流云厂商的实例元数据端点。端侧应用
// 打不到自家云元数据面，本表是卫生性兜底（防模型被诱导探测用户可能挂了隧道的环境）
const METADATA_HOSTS: string[] = ['169.254.169.254', 'metadata.google.internal',
  'metadata.azure.internal', '100.100.100.200'];

// 域名白名单匹配（host 与 entries 均假定已归一——小写、无端口，归一单源在
// AppPreferencesHttp.normalizeHttpPolicyHost（2026-10-01 域拆分迁址），写侧与查询侧共用）：条目 = 精确 host 或其
// 子域（条目 example.com 命中 example.com 与 api.example.com，不命中
// evilexample.com——endsWith 带 '.' 前缀保证按域界切分）。**空名单 = 全放行**（留空
// = 不限的现行口径零变化）
export function hostAllowedByWhitelist(host: string, entries: string[]): boolean {
  if (entries.length === 0) {
    return true;
  }
  for (const entry of entries) {
    if (host === entry || host.endsWith('.' + entry)) {
      return true;
    }
  }
  return false;
}

// 脚本联网预授权判据（沙箱桥，2026-10-06 代码工作台笔E）：与工具侧白名单取向相反——
// **空名单 = 全禁**（fail-closed）。安全理由：脚本无人值守执行（worker 阻塞期不能弹卡
// 问），默认必须一个都不放；名单非空时复用 hostAllowedByWhitelist 的精确/子域语义
//（单源，禁第二套匹配）
export function scriptHostAllowed(host: string, entries: string[]): boolean {
  return entries.length > 0 && hostAllowedByWhitelist(host, entries);
}

// URL 内嵌账号密码检测（scheme 硬化）：authority 段（首个 / 之前）含 @ 即 user:pass@
// 形态——明文凭据进 URL 会落请求日志、代理与对方访问日志多处，恒拒并指路改请求头。
// query 里的 @（如 ?email=a@b.com）不在 authority 段、不命中
export function urlHasEmbeddedUserInfo(url: string): boolean {
  return /^https?:\/\/[^/@]+@/i.test(url);
}

// 云元数据 host 判定（host 假定已归一；精确匹配，不带端口——端口归一在写侧）
export function isCloudMetadataHost(host: string): boolean {
  return METADATA_HOSTS.includes(host);
}

// 出站哨兵：在模型入参文本（URL 与 body）里扫凭据库明文，命中即拦。values = 名称 →
// 明文值（调用方自凭据域件装配，含助手级 + 全局两命名空间）；minLen 以下的长度的值
// 不参与（防短串误伤正常文本）。返回命中的凭据名称清单（只含名称——名称非秘密，
// 值级信息零出现）
export function scanCredentialPlaintext(texts: string[], values: Map<string, string>,
  minLen: number): string[] {
  const hits: string[] = [];
  values.forEach((value: string, name: string): void => {
    if (value.length < minLen) {
      return;
    }
    for (const text of texts) {
      if (text.includes(value)) {
        if (!hits.includes(name)) {
          hits.push(name);
        }
        break;
      }
    }
  });
  return hits;
}

// ── 四类中文错误文案（模型回执面——指路改用引用 / 用户入口，禁静默）──

export function whitelistBlockedErrorText(host: string): string {
  return '该域名不在允许列表中，请求未发送。用户可在 设置 → 工具调用 → HTTP 请求 页的' +
    '「域名准入」卡添加 ' + host + ' 后重试。';
}

export function userInfoBlockedErrorText(): string {
  return 'URL 中包含账号密码段（user:pass@ 形态），请求被拒绝。请把凭据改放请求头，' +
    '例如 Authorization 头，或使用 {{凭据名}} 引用。';
}

export function metadataBlockedErrorText(): string {
  return '该地址是云服务商元数据地址，应用一律拒绝访问。';
}

export function sentinelBlockedErrorText(names: string[]): string {
  return '请求内容与凭据库保存的明文一致（凭据：' + names.join('、') +
    '）。请改用 {{凭据名}} 引用让应用在发送前注入，不要直接写值。';
}

// ── 脚本联网两态中文文案（模型回执面，2026-10-06 代码工作台笔E；消费方 = ScriptHttpBridge
//    域名闸——两态两句，指明授权入口。★ 同日控制面层级化笔改口：授权卡自助手工具页迁出，
//    现入口 = 助手编辑页「脚本联网域名」卡与 设置 → 工具调用 → 脚本工作台 → 脚本联网域名
//    总览页〔全局段〕，文案双入口都给）──

// 名单为空（助手与全局都还没有任何授权——fail-closed 首撞态；并集口径下两段全空才会到这）
export function scriptHostNoneGrantedErrorText(): string {
  return '还没有授权任何脚本联网域名，请求没有发出。请让用户在助手的编辑页「脚本联网域名」卡里添加域名，或在 设置 → 工具调用 → 脚本工作台 → 脚本联网域名 里添加全局域名后再试。';
}

// 域名越界（并集非空但 host 不在其中）
export function scriptHostBlockedErrorText(host: string): string {
  return '域名 ' + host + ' 不在脚本联网授权名单里，请求没有发出。请让用户在助手的编辑页' +
    '「脚本联网域名」卡里添加，或在 设置 → 工具调用 → 脚本工作台 → 脚本联网域名 里添加' +
    '全局域名后再试。';
}

// ── 脚本联网方法集与写请求文案（模型回执面，2026-10-07 代码工作台笔G；消费方 = 桥件
//    ScriptHttpBridge——opts 的 method 值域校验与写方法授权闸）。五值单源 = 下方
//    SCRIPT_HTTP_METHODS；与 HttpPreflight.HTTP_WRITE_METHODS 的关系 = {GET} ∪ 写集，
//    由断言关系钉守（禁在本件抄写方法字面清单之外的第二份值域）──

// 脚本内可用的方法集（不填 = GET；写方法须过全局「允许脚本发写请求」开关）
export const SCRIPT_HTTP_METHODS: string[] = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

// 是否写方法（= 方法集内非 GET 的四值——写方法须过授权开关；HEAD / OPTIONS 不在方法集内，
// 由调用方先过值域校验，本函数恒 false）
export function isScriptWriteMethod(method: string): boolean {
  return method !== 'GET' && SCRIPT_HTTP_METHODS.includes(method);
}

// 方法越界中文句（点名五值与收到的值；不含 HEAD / OPTIONS 字样——不做面不进句子）
export function scriptMethodUnknownErrorText(method: string): string {
  return 'httpGet 的 opts 里 method 只支持 GET、POST、PUT、DELETE 与 PATCH 五种，收到的是 ' +
    method + '。';
}

// 写请求未授权中文句（点名动作与收到的 method + 指路全局开关；不复述确认卡语义——由开关
// 卡说明与帮助条目承载）
export function scriptWriteDeniedErrorText(method: string): string {
  return 'httpGet 的 opts 里 method 是写请求方法 ' + method +
    '。脚本发写请求需要先在 设置 → 工具调用 → 脚本工作台 里打开「允许脚本发写请求」。';
}
