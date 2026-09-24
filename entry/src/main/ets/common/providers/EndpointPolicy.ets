// 端点加密分级（2026-09-24「明文放行治理」笔 P0-1 新增；方案 = docs/优化建议-工程与代码质量-20260924.md §二）：
// 判断服务商 Base URL 的加密形态，供三处消费——①服务商编辑页保存链（公网明文 → 确认卡）
// ②服务商管理页卡片徽章（常驻「明文」标记，兼覆盖不追溯拦截的存量配置）③配置导入预览
// 对话框（报文里点名未加密的家数）。
// · 口径（决明 2026-09-24 拍板「先改本地再推开源」）：https 一律放行；http 按主机分级——
//   回环（127.x / localhost / ::1 / 0.0.0.0）与私网（10.x / 172.16~31.x / 192.168.x /
//   169.254.x / fc~fd 与 fe80 开头的 IPv6 / .local 结尾主机名）放行——自建网关
//   （one-api / LM Studio / Ollama）都在这两类地址，禁掉会打断主要场景；仅**公网明文**
//   新增一次确认与常驻标记。存量已保存的公网明文配置不追溯拦截（追溯 = 升级后打开即被挡，
//   打断既有工作流），可见性由卡片徽章承担。
// · ★ 安全要点（判据，勿改宽）：私网判定必须**整串主机名**匹配（IPv4 四段十进制且各段
//   0~255），**禁前缀匹配**——`10.0.0.1.evil.com` / `192.168.1.5.evil.com` /
//   `127.0.0.1.evil.com` 这类前缀伪装域名若被前缀法判成回环/私网，等于给攻击者留一条
//   免确认通道。本件真值表断言（182 组 A 段）专钉此形态。
// · 本文件**零 import**（叶子件，环求值红线坑50 安全）：断言脚本按 sse-assert ⑪ 组先例
//   把本件复制为副本直跑同一实现（禁双实现漂移——SseParser 同款姿势）；故本件只用可类型
//   剥离语法（无 enum / namespace / 装饰器），分级值用字符串常量族。
// · 职责边界：本件只做**判定**，不做拦截决策——拦不拦、弹不弹卡在调用方（三处消费各按
//   自身语境决定）。

// ── 分级结果（字符串常量族；调用方按常量比较，禁裸字面量）──
// 传输已加密（https 任意主机）
export const ENDPOINT_TLS: string = 'tls';
// 明文但地址在本机（回环）
export const ENDPOINT_LOCAL: string = 'local';
// 明文但地址在私网（自建网关主场景）
export const ENDPOINT_PRIVATE: string = 'private';
// 明文且地址在公网——唯一需要确认与标记的一档
export const ENDPOINT_PUBLIC_CLEARTEXT: string = 'public-cleartext';
// 不成形（非 http/https 前缀或取不到主机名）——由调用方既有的前缀校验兜底，本件不下判断
export const ENDPOINT_INVALID: string = 'invalid';

// 取主机名（小写；去 scheme、userinfo、端口、路径/查询/片段；IPv6 去方括号）。
// 取不到返回 ''
export function endpointHost(baseUrl: string): string {
  const lower: string = baseUrl.trim().toLowerCase();
  const schemeAt: number = lower.indexOf('://');
  const afterScheme: string =
    schemeAt >= 0 ? lower.substring(schemeAt + 3) : lower;
  // 只取 authority 段（首个 / ? # 之前）
  let authority: string = afterScheme;
  const stops: string[] = ['/', '?', '#'];
  for (const stop of stops) {
    const at: number = authority.indexOf(stop);
    if (at >= 0) {
      authority = authority.substring(0, at);
    }
  }
  // userinfo（user:pass@host——授权段内最后一个 @ 之后才是主机）
  const atSign: number = authority.lastIndexOf('@');
  if (atSign >= 0) {
    authority = authority.substring(atSign + 1);
  }
  if (authority === '') {
    return '';
  }
  // IPv6 字面量（[::1] / [fe80::1]）——去方括号，不再切端口
  if (authority.startsWith('[')) {
    const close: number = authority.indexOf(']');
    return close > 1 ? authority.substring(1, close) : '';
  }
  // IPv4 / 主机名——切端口（首个 : 之前）
  const colonAt: number = authority.indexOf(':');
  return colonAt >= 0 ? authority.substring(0, colonAt) : authority;
}

// IPv4 字面量判定：恰四段、各段纯十进制、值 0~255（前导零容忍——'010' 按十进制 10）
function isIpv4Literal(host: string): boolean {
  const parts: string[] = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (const part of parts) {
    if (part === '' || part.length > 3) {
      return false;
    }
    for (let i = 0; i < part.length; i++) {
      const code: number = part.charCodeAt(i);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    if (Number.parseInt(part, 10) > 255) {
      return false;
    }
  }
  return true;
}

// IPv4 段值（调用前须过 isIpv4Literal）
function ipv4Segment(host: string, index: number): number {
  const parts: string[] = host.split('.');
  return index < parts.length ? Number.parseInt(parts[index], 10) : -1;
}

// 本机（回环）判定
function isLocalHost(host: string): boolean {
  if (host === 'localhost' || host === '::1' || host === '0.0.0.0') {
    return true;
  }
  // 127.0.0.0/8（整段回环）
  return isIpv4Literal(host) && ipv4Segment(host, 0) === 127;
}

// 私网判定（RFC1918 三段 + 链路本地 169.254/16 + IPv6 ULA fc00::/7 与链路本地 fe80::/10
// + mDNS 局域网名 .local）。★ 整串匹配，禁前缀——见头注释安全要点
function isPrivateHost(host: string): boolean {
  if (host.endsWith('.local')) {
    return true;
  }
  if (host.startsWith('fc') || host.startsWith('fd') || host.startsWith('fe80')) {
    return true; // IPv6 唯一本地地址与链路本地地址
  }
  if (!isIpv4Literal(host)) {
    return false;
  }
  const a: number = ipv4Segment(host, 0);
  const b: number = ipv4Segment(host, 1);
  if (a === 10) {
    return true;
  }
  if (a === 172 && b >= 16 && b <= 31) {
    return true;
  }
  if (a === 192 && b === 168) {
    return true;
  }
  return a === 169 && b === 254;
}

// 分级主入口：返回 ENDPOINT_* 五常量之一
export function classifyEndpoint(baseUrl: string): string {
  const lower: string = baseUrl.trim().toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return ENDPOINT_INVALID;
  }
  const host: string = endpointHost(baseUrl);
  if (host === '') {
    return ENDPOINT_INVALID;
  }
  if (lower.startsWith('https://')) {
    return ENDPOINT_TLS;
  }
  if (isLocalHost(host)) {
    return ENDPOINT_LOCAL;
  }
  if (isPrivateHost(host)) {
    return ENDPOINT_PRIVATE;
  }
  return ENDPOINT_PUBLIC_CLEARTEXT;
}

// 便利判定（三处消费统一入口；只在「公网 + 明文」这一档为真，INVALID 不为真——不成形地址
// 由调用方既有的前缀校验拦，本件不重复表态）
export function isPublicCleartextEndpoint(baseUrl: string): boolean {
  return classifyEndpoint(baseUrl) === ENDPOINT_PUBLIC_CLEARTEXT;
}

// 「明文」徽章文案（唯一来源 = 本件）：服务商管理页卡片徽章行消费；与判据分家——改文案
// 不动分级，断言钉的是「卡片引本常量」这条接线，不钉文案字面
export const CLEARTEXT_BADGE_TEXT: string = '明文';
