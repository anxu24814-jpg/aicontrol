// HTTP 工具域偏好键与读封装（自 AppPreferences.ets 域拆分独立成件）：凭据元数据 / 域名准入
// 白名单 / 脚本联网域名三域 JSON 键及配套读写封装。本文件与 AppPreferences 同为**零 import
// 叶子**（只用 AppStorage 全局，谁都可引、不引任何人）；BACKUP_PREF_KEYS 对各键的收录以
// 字面量形态在 AppPreferences 备份分域表登记（键名漂移由 assert-feature-domain 全覆盖钉
// 兜住——改名即红）。
// ★ 2026-11-11 决明拍板：域名确认档（prefHttpDomainPolicies）整套退役——按域名的确认例外与
//   会话权限三档同属「问不问」一根轴，留着即第二根轴；写确认只由会话模式决定。本件只保留
//   域名归一与输入合法性两个纯函数（白名单与脚本域名两域共用）。

// ★ 凭据元数据 JSON 串结构化键（「JSON 串结构化键」立规：读值一律经 parse 封装、写值一律
// 经 serialize 封装，两者单源在 common/providers/HttpCredentials.ets，本文件只持键常量与
// 兜底读值）。结构 = owner → [{id, name, hasValue}]（owner = 助手 id 或 'global'〔KeyStore
// HTTP_CRED_OWNER_GLOBAL〕；hasValue 同搜索 key hasKey 语义只是 UI 标记）。明文红线：本键
//**只存名称与标记，凭据值明文恒不进本键**（值只进 Asset，KeyStore saveHttpCredential 族）。
// 备份档位 = 决明拍板「同搜索引擎 key 全档」：普通备份带名称清单、含密钥加密档连值导出
export const PREF_HTTP_CREDENTIALS_CFG_KEY: string = 'prefHttpCredentialsCfg';

// 兜底读值（解析在 HttpCredentials.parseHttpCredCfg；'' = 全默认无配置）
export function getHttpCredentialsCfgJson(): string {
  return AppStorage.get<string>(PREF_HTTP_CREDENTIALS_CFG_KEY) ?? '';
}

// 域名归一（白名单 / 脚本联网域名两域共用）：小写、去端口、去空白；路径与 scheme 不入键——
// 名单按 host 粒度
export function normalizeHttpPolicyHost(host: string): string {
  const trimmed: string = host.trim().toLowerCase();
  const portIdx: number = trimmed.lastIndexOf(':');
  // 只剥真端口段（IPv6 字面量含冒号——无 scheme 的裸 host 键场景下最后一个冒号后全数字
  // 才当端口；非数字原样保留，防御分支不追求完备，IPv6 用户可存带冒号原串照样精确匹配）
  if (portIdx > 0 && /^[0-9]+$/.test(trimmed.substring(portIdx + 1))) {
    return trimmed.substring(0, portIdx);
  }
  return trimmed;
}

// 域名输入合法性（准入白名单与脚本联网域名两域共用；原为准入与已退役的域名确认档两路各自
// 内联同款判断，收口提纯）：空串 / 含路径符 / 问号
// 锚点符 / 空白任一即非法，归一后判定。粘贴完整 URL 因含 '//' 已被路径符拦下，'?' '#'
// 补拦的是「api.example.com?x=1」类怪串（原样入库后与请求真实 host 永不匹配，行已添加而
// 例外不生效）。导出供断言直跑
export function httpPolicyHostInputValid(host: string): boolean {
  return host !== '' && !host.includes('/') && !host.includes('?') &&
    !host.includes('#') && !/\s/.test(host);
}

// ★ 域名准入白名单 JSON 数组结构化键（同族立规）：结构 = 归一 host 字符串数组。**留空 =
// 不限**（本键是用户主动加的收紧面，非默认闸）；只约束 http_request 工具的首跳 URL（kit
// 自动跟跳不逐跳校验，帮助条目写明）。条数上限 HTTP_ALLOWED_HOSTS_MAX 防无界（超出丢
// 尾部）；单条归一复用 normalizeHttpPolicyHost、超长丢弃。随备份走（用户安全偏好，域名非秘密）
export const PREF_HTTP_ALLOWED_HOSTS_KEY: string = 'prefHttpAllowedHosts';
export const HTTP_ALLOWED_HOSTS_MAX: number = 100;
export const HTTP_ALLOWED_HOST_MAX_CHARS: number = 200;

// ★ 脚本联网预授权域名 JSON 串结构化键（照白名单键同族立规）：结构 = { [owner]: [归一
// host, …] }（owner = 助手 id〔含控制台助手 id〕或 CODE_HTTP_OWNER_GLOBAL 全局段）。
// **空 = 全禁**（fail-closed，与白名单的「空 = 不限」取向相反——脚本无人值守执行，默认
// 一个都不放；判据单源 HttpPolicy.scriptHostAllowed）。运行时判定 = **并集**（助手名单 ∪
// 全局名单，codeHttpHostsFor 单源——照「全局凭据所有助手都能用」语义，同名去重助手清单
// 在前）。归一复用 normalizeHttpPolicyHost、子域匹配复用 hostAllowedByWhitelist（零第二套）。
// 条数上限 CODE_HTTP_HOSTS_MAX 按 owner 计（E11 拍板独立取值 20，不沿用 100）；单条同档
// 200（独立常量各持单源）。消费方 = ScriptHttpBridge 域名闸（每请求现读）+ 设置侧总览/
// 管理两页 + 助手编辑页「脚本联网域名」入口卡。随备份走（用户安全偏好，域名本身非秘密）
export const PREF_CODE_HTTP_HOSTS_KEY: string = 'prefCodeHttpHosts';
// 全局命名空间段 key（与 HTTP_CRED_OWNER_GLOBAL 同值同族——段位与助手 id 空间隔离，UUID 不撞 'global'）
export const CODE_HTTP_OWNER_GLOBAL: string = 'global';

// 域名管理页 push 参数：owner = 'global' 或助手 id；readOnly = true = 助手编辑页入口的
//**只读清单**（新增/删除只在设置侧的域名总览页入口）。载体放本域（而非页面文件）= 生产方
// 与消费方跨 components 子目录，单源放公共域免组件件互引；字符串形态仍兼容旧调用（= 可管理）
export interface CodeHttpHostManageParam {
  owner: string;
  readOnly: boolean;
}

// 键 JSON 串读口（助手编辑页入口卡摘要等同步读面消费；getHttpCredentialsCfgJson 同构）
export function getCodeHttpHostsJson(): string {
  return AppStorage.get<string>(PREF_CODE_HTTP_HOSTS_KEY) ?? '';
}
// 每助手条数上限（满员回 false + UI toast 如实报因——照 addHttpAllowedHost 先例）
export const CODE_HTTP_HOSTS_MAX: number = 20;
// 单条长度上限（与 HTTP_ALLOWED_HOST_MAX_CHARS 同档 200——域名 200 字符已实际不可达；两键独立偏好不共值各持单源）
export const CODE_HTTP_HOST_MAX_CHARS: number = 200;

// 解析单 owner 清单（脏 JSON / 非串元素 / 超长条目剔除，不抛错——偏好键宁可回默认不可炸链）：
// 归一 + 去重保序。export 理由同 parseHttpAllowedHosts（设置/助手侧渲染面直引建渲染依赖）
export function parseCodeHttpHosts(json: string, owner: string): string[] {
  const out: string[] = [];
  if (json === '' || owner === '') {
    return out;
  }
  try {
    const raw = JSON.parse(json) as Record<string, Object>;
    if (Array.isArray(raw) || raw === null) {
      return out;
    }
    const list: Object[] | undefined = raw[owner] as Object[] | undefined;
    if (!Array.isArray(list)) {
      return out;
    }
    for (const item of list) {
      if (typeof item !== 'string') {
        continue;
      }
      const host: string = normalizeHttpPolicyHost(item);
      if (host === '' || host.length > CODE_HTTP_HOST_MAX_CHARS || out.includes(host)) {
        continue;
      }
      out.push(host);
    }
  } catch (e) {
    return out;
  }
  return out;
}

// 读生效清单（桥域名闸每请求现读单源）：**并集** = 助手名单在前 + 全局名单追加（保序
// 去重——跨段同名域名不重复回）。两段全空 = [] = 全禁（fail-closed 语义不变）
export function codeHttpHostsFor(assistantId: string): string[] {
  const json: string = AppStorage.get<string>(PREF_CODE_HTTP_HOSTS_KEY) ?? '';
  const own: string[] = parseCodeHttpHosts(json, assistantId);
  const global: string[] = parseCodeHttpHosts(json, CODE_HTTP_OWNER_GLOBAL);
  const out: string[] = own.slice();
  for (const h of global) {
    if (!out.includes(h)) {
      out.push(h);
    }
  }
  return out;
}

// 读全量对象（写侧内部用——增删都从全量出发回写，防并发写覆盖他助手段）
function codeHttpHostsMap(): Record<string, Object> {
  try {
    const raw = JSON.parse(AppStorage.get<string>(PREF_CODE_HTTP_HOSTS_KEY) ?? '') as
      Record<string, Object>;
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      return raw;
    }
  } catch (e) {
  }
  return {};
}

// 增单条（设置/助手侧管理页添加键走本封装）：已存在 = 幂等成功（回 true，UI 清输入框即成）；
// 空串 / 超长 / 非法（httpPolicyHostInputValid 单源）回 false 供 UI 报错；满员（该 owner
// CODE_HTTP_HOSTS_MAX 条）回 false——boolean 分不了因，三态专用提示在调用方做
export function addCodeHttpHost(owner: string, host: string): boolean {
  if (owner === '') {
    return false;
  }
  const key: string = normalizeHttpPolicyHost(host);
  if (key === '' || key.length > CODE_HTTP_HOST_MAX_CHARS || !httpPolicyHostInputValid(key)) {
    return false;
  }
  const map: Record<string, Object> = codeHttpHostsMap();
  const list: string[] = parseCodeHttpHosts(JSON.stringify(map), owner);
  if (list.includes(key)) {
    return true;
  }
  if (list.length >= CODE_HTTP_HOSTS_MAX) {
    return false;
  }
  list.push(key);
  map[owner] = list;
  AppStorage.set<string>(PREF_CODE_HTTP_HOSTS_KEY, JSON.stringify(map));
  return true;
}

// 删单条（不存在 = 零动作；该 owner 清单删空时保留空数组段——语义同为全禁，少一次重序列化）
export function removeCodeHttpHost(owner: string, host: string): void {
  if (owner === '') {
    return;
  }
  const key: string = normalizeHttpPolicyHost(host);
  const map: Record<string, Object> = codeHttpHostsMap();
  const list: string[] = parseCodeHttpHosts(JSON.stringify(map), owner);
  if (!list.includes(key)) {
    return;
  }
  const fresh: string[] = [];
  for (const h of list) {
    if (h !== key) {
      fresh.push(h);
    }
  }
  map[owner] = fresh;
  AppStorage.set<string>(PREF_CODE_HTTP_HOSTS_KEY, JSON.stringify(map));
}

// ★ 脚本写请求授权键（决明改向拍板：推翻「助手级 owner-map」，改**全局单开关**——只给全局
// 不给助手）。true = 允许脚本发写请求（POST / PUT / DELETE / PATCH）；**缺省 false = 只放行
// GET**（fail-closed——脚本无人值守执行，写动作默认不开；缺省真源在 persistProp 注册侧）。
// 判据单源 = isScriptWriteMethod（HttpPolicy）× isCodeHttpWriteEnabled（本件，桥每请求现读
// ——运行中改开关对后续请求即时生效）。随备份走：用户安全偏好
export const PREF_CODE_HTTP_WRITE_KEY: string = 'prefCodeHttpWrite';

// 读口（桥写授权闸每请求现读；未写/非 true 恒 false = fail-closed——含备份导入带来的脏值）。
// 写侧 = 设置页开关卡 @StorageLink 直接写键，本件不设写封装
export function isCodeHttpWriteEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_CODE_HTTP_WRITE_KEY) === true;
}

// ★ 脚本联网域名请求模式键：'allowlist'（缺省，只向已添加域名发请求 = 现状）/'any'（允许向
// 任何域名发请求——只短路桥第⑤步脚本侧预授权闸，链内安全闸照常，见 ScriptHttpBridge 闸位
// 注释）。fail-closed：脏值/未写经 resolveCodeHttpHostMode 归一回 allowlist。UI 写侧 =
// 总览页分段卡 @StorageLink 直接写键，本件不设写封装。随备份走：用户安全偏好
export const PREF_CODE_HTTP_HOST_MODE_KEY: string = 'prefCodeHttpHostMode';
export const CODE_HTTP_HOST_MODE_ALLOWLIST: string = 'allowlist';
export const CODE_HTTP_HOST_MODE_ANY: string = 'any';

// 归一（三值恒等回 + 脏值/空串归 allowlist——照 resolveCodeWorkbenchEngine 立规）
export function resolveCodeHttpHostMode(value: string): string {
  return value === CODE_HTTP_HOST_MODE_ANY ? CODE_HTTP_HOST_MODE_ANY : CODE_HTTP_HOST_MODE_ALLOWLIST;
}

// 读口（桥域名模式闸每请求现读；非显式 'any' 恒 false = fail-closed——含备份导入带来的脏值）
export function codeHttpHostsAllowAny(): boolean {
  return AppStorage.get<string>(PREF_CODE_HTTP_HOST_MODE_KEY) === CODE_HTTP_HOST_MODE_ANY;
}

// ★ HTTP 请求页准入卡收放态键：true = 卡收起为标题行短卡 / false = 默认展开（存量零回归）。
// 纯界面展示偏好，不在偏好设置页暴露，用户点标题行经 @StorageLink 隐式写入（一写即落盘），
// 随备份走（BACKUP_PREF_KEYS 字面量登记）；缺省 false 真源在 persistProp 注册侧。
// 消费方 = HttpRequestSettingsPage 域名准入卡（2026-11-11 域名确认档退役后本页只剩一张可折卡）
export const PREF_HTTP_ALLOWLIST_CARD_COLLAPSED_KEY: string = 'prefHttpAllowlistCardCollapsed';

// 解析（读值封装底层；脏 JSON / 非串元素 / 超长条目剔除，不抛错）：归一 + 去重保序。
// ★ export 理由：设置页渲染面直引自 @StorageLink 键串才有渲染依赖（读状态变量 = 建立依赖，
// 增删即刷）；经 httpAllowedHosts() 直读 AppStorage 不产生依赖，增删后须退出重进才刷新
export function parseHttpAllowedHosts(json: string): string[] {
  if (json === '') {
    return [];
  }
  const out: string[] = [];
  try {
    const raw = JSON.parse(json) as Object[];
    if (!Array.isArray(raw)) {
      return [];
    }
    for (const item of raw) {
      if (typeof item !== 'string') {
        continue;
      }
      const host: string = normalizeHttpPolicyHost(item);
      if (host === '' || host.length > HTTP_ALLOWED_HOST_MAX_CHARS || out.includes(host)) {
        continue;
      }
      out.push(host);
    }
  } catch (e) {
    return [];
  }
  return out;
}

// 读全量（执行器每请求现读 + 设置页渲染）：未写入 / '' = 空名单 = 不限
export function httpAllowedHosts(): string[] {
  return parseHttpAllowedHosts(AppStorage.get<string>(PREF_HTTP_ALLOWED_HOSTS_KEY) ?? '');
}

// 写全量（设置页增删走本封装；归一去重 + 条数上限丢尾部）
export function setHttpAllowedHosts(list: string[]): void {
  const out: string[] = [];
  for (const item of list) {
    const host: string = normalizeHttpPolicyHost(item);
    if (host === '' || host.length > HTTP_ALLOWED_HOST_MAX_CHARS || out.includes(host)) {
      continue;
    }
    out.push(host);
    if (out.length >= HTTP_ALLOWED_HOSTS_MAX) {
      break;
    }
  }
  AppStorage.set<string>(PREF_HTTP_ALLOWED_HOSTS_KEY, JSON.stringify(out));
}

// 增单条：已存在 = 幂等成功（回 true——「已在名单中」即添加语义达成态，UI 清输入框即成；
// 满员或不可存取值才回 false 供 UI 报错——此前已存在与满员同回 false，重复添加会误报满员，
// 已分态订正）。★ 超长在写入点同口径拒绝（setHttpAllowedHosts 是读入面静默剔除——本函数
// 若对超长回 true 即「添加成功但行不出现」静默失败）；UI 专用提示（域名过长）在调用方做
export function addHttpAllowedHost(host: string): boolean {
  const list: string[] = httpAllowedHosts();
  const key: string = normalizeHttpPolicyHost(host);
  if (key === '' || key.length > HTTP_ALLOWED_HOST_MAX_CHARS) {
    return false;
  }
  if (list.includes(key)) {
    return true;
  }
  if (list.length >= HTTP_ALLOWED_HOSTS_MAX) {
    return false;
  }
  list.push(key);
  setHttpAllowedHosts(list);
  return true;
}

// 删单条（不存在 = 零动作）。ArkTS 无 delete：重建过滤数组
export function removeHttpAllowedHost(host: string): void {
  const key: string = normalizeHttpPolicyHost(host);
  const list: string[] = httpAllowedHosts();
  if (!list.includes(key)) {
    return;
  }
  const fresh: string[] = [];
  for (const h of list) {
    if (h !== key) {
      fresh.push(h);
    }
  }
  setHttpAllowedHosts(fresh);
}

// ★ 长任务句柄持久化镜像 JSON 串结构化键（同族立规）：只登记**运行中**后台任务的最小身份
// 字段（taskId / runId / startedAtMs / timeoutAtMs；序列化 / 解析单源 HttpTaskTable，本文件
// 只持键常量与裸串读写），终态即从镜像消失、镜像恒极小。用途 = 「重启后仍 running 的标
// lost」：进程启动后句柄表工厂首次构造时 restore 本键、全部条目标 lost（不假装在跑也不
// 假装完成），随即以空镜像回写（restore 消费即清）。写点三处在 ToolHttp。备份档位 =
// 不进备份（后台任务是进程瞬时态，换机无恢复语义）
export const PREF_HTTP_TASKS_KEY: string = 'prefHttpTaskMirror';

// 兜底读值（'' = 无在途任务；键未注册时 AppStorage.get 回 undefined 同落此兜底）
export function getHttpTaskMirrorJson(): string {
  return AppStorage.get<string>(PREF_HTTP_TASKS_KEY) ?? '';
}

// 写全量（ToolHttp 三写点共用；串恒来自 serializeRunning 单源，本封装不做结构校验）
export function setHttpTaskMirror(json: string): void {
  AppStorage.set<string>(PREF_HTTP_TASKS_KEY, json);
}
