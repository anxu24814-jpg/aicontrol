// 继续生成（#10）支持面：判据 + 端点拼装 + 不可用记忆（零 import 叶子件）。
// 一句话职责 =「续写能力的三条纯判据 + 一次失败即隐藏的进程内标记」。
// · 为什么独立成件：流域（ChatStreamFlowCtrl）与展示层（ChatMessageItem）都要读「本服务是否
//   已判定不支持续写」，而两者都不能 import ChatContinueCtrl（会经 ChatSendCtrl 形成环）。
//   叶子件零依赖，双方单向引用，零环。
// · 官方事实（guides/chat_prefix_completion）：最后一条消息 role=assistant 且 `prefix: true`，
//   `base_url` 设为 `https://api.deepseek.com/beta`；**Responses 明确不支持**；用过联网工具的
//   回复一律 400。故判据三重：官方 CC 连接 + 未用服务端工具 + 有正文。
// · 「一次失败即判定」：续写请求 404/不可达 → markContinueUnsupported() → 入口（消息「更多」
//   菜单「续写」项）隐藏并提示；不做长期探测（任务书 §1-7②拍板）。进程内标记，重启复位
//  （下次可能换了服务商）。

// 官方 beta 端点后缀（baseUrl 末尾追加；已带 /beta 不重复追加）
export const CONTINUE_BETA_SUFFIX: string = '/beta';

// 「当前连接可续写」镜像键（bool 广播，ChatPage.setConnInfo 同点写）：判据 = DS 官方 CC
// （isDsFlashConnection 且 endpoint='chat'）——官方只承诺 DeepSeek 官方 CC 的 beta 端点；
// Responses 明确不支持、第三方连接点了必 400。★ 2026-11-15 续写收入菜单笔：唯一消费面 =
// 消息「更多」菜单（ChatMoreMenu.ChatMessageMenuCtrl 组装回调时 AppStorage 现读）——原
// ChatMessageItem 行内续写键 @StorageProp 订阅随入口迁移退役
export const CHAT_DS_CONTINUE_AVAILABLE_KEY: string = 'chatDsContinueAvailable';

// 续写不可用提示（面向用户；禁冒号分号）
export const CONTINUE_UNSUPPORTED_TEXT: string = '当前服务不支持继续生成';

// 网络层不可用提示（404/不可达一次判定）
export const CONTINUE_UNREACHABLE_TEXT: string = '当前服务不支持继续生成';

// 进程内「已判定不支持」标记（模块级；无持久化 = 重启复位）
let continueUnsupported: boolean = false;

export function markContinueUnsupported(): void {
  continueUnsupported = true;
}

export function isContinueUnsupported(): boolean {
  return continueUnsupported;
}

// 测试/复位口（断言与换服务商后重置用；生产调用点 = 连接切换时的能力重判）
export function resetContinueUnsupported(): void {
  continueUnsupported = false;
}

// beta 端点拼装（纯函数）：去尾斜杠 → 去尾部 /v1（官方 beta 不带 v1）→ 追加 /beta；
// 已以 /beta 结尾原样返回。空串回 ''（调用方按无连接处理）
export function dsContinueBaseUrlOf(baseUrl: string): string {
  let base: string = baseUrl.trim();
  if (base === '') {
    return '';
  }
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.endsWith(CONTINUE_BETA_SUFFIX)) {
    return base;
  }
  if (base.endsWith('/v1')) {
    base = base.substring(0, base.length - 3);
  }
  return base + CONTINUE_BETA_SUFFIX;
}

// 续写轮连接形态判据（纯函数；官方只承诺 OpenAI 兼容 CC 的 beta 端点）：
// protocol='openai' + endpoint='chat' + baseUrl 可拼 beta。**Responses 一律不出键**。
export function canContinueOnConnection(protocol: string, endpoint: string,
  baseUrl: string): boolean {
  if (protocol !== 'openai' || endpoint !== 'chat') {
    return false;
  }
  return dsContinueBaseUrlOf(baseUrl) !== '';
}

// 答案行可续写判据（UI 判据面；纯函数——ChatMessageItem 直接调用，避免在组件里堆条件）
export function continueVisibleBy(kind: string, streaming: boolean, isTail: boolean,
  text: string, serverToolsJson: string, officialCc: boolean): boolean {
  if (kind !== 'assistant' || streaming || !isTail || text.trim() === '') {
    return false;
  }
  // officialCc（自检轮补）：非 DS 官方 CC 连接一律不出键——首版无连接判据，第三方会话也
  // 出箭头键，点了才 toast「当前服务不支持继续生成」（任务书验收①要求只在官方 CC 可见）
  return officialCc && serverToolsJson === '' && !continueUnsupported;
}

// 答案行可续写判据（纯函数）：末条 + 非流式 + 有正文 + 本轮未用服务端工具（用过必 400，
// 官方明示）+ 服务未被判定不支持。truncated/stopped 不是必要条件——任何已收尾答案都可续写
export function continueEligibleOf(isTail: boolean, streaming: boolean, text: string,
  usedServerTools: boolean): boolean {
  if (!isTail || streaming || !continueEligibleText(text) || usedServerTools) {
    return false;
  }
  return !continueUnsupported;
}

// 正文非空判据（trim 后非空——纯空白不算可续写前缀）
function continueEligibleText(text: string): boolean {
  return text.trim() !== '';
}

// 续写不可用错误判据（纯函数）：404 / 405 / 端点不存在类文案一次判定。官方 beta 端点缺失或
// 中转站不提供 /beta 时的共同形态——命中即隐藏键，不重试
export function isContinueUnsupportedError(status: number, message: string): boolean {
  if (status === 404 || status === 405) {
    return true;
  }
  // 网络层不可达（-1）才看文案族（自检轮修）：首版不问状态码，任何含 not found / unsupported
  // 的业务错误（如 model not found 400）都会把键永久隐藏；4xx 业务错误仍按服务端真实报错收尾
  if (status !== -1) {
    return false;
  }
  const lower: string = message.toLowerCase();
  return lower.includes('not found') || lower.includes('unsupported') ||
    message.includes('不支持');
}

// ── 点击通道（零 import 约束下的单向事件口）──
// 为什么不走 @Prop 回调链：ChatMessageItem 由 ChatPageContent 实例化，而 ChatPageContent 已
// 在 1200 硬线上（本批规定零触及）。登记/触发两函数把「键 → 编排」一跳收在叶子件，双方都
// 不新增跨层参数；处理器在 ChatSendCtrl 构造期登记（生产恒在场），未登记 = no-op。
let continueHandler: ((msgId: string) => void) | null = null;

export function registerContinueHandler(handler: (msgId: string) => void): void {
  continueHandler = handler;
}

export function requestContinue(msgId: string): void {
  if (continueHandler !== null) {
    continueHandler(msgId);
  }
}

// 注销口（自检轮补，成对释放）：模块级单例不得长期持有控制器闭包——发送控制器销毁时清空
export function clearContinueHandler(): void {
  continueHandler = null;
}
