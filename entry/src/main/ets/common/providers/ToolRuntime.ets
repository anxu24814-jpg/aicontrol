// 工具执行运行时域（2026-09-26 笔1 S3a 自 ToolTypes.ets 域级最小拆分迁出——宪法 1200 硬线：
// 本笔对 ToolTypes 有实质改动（执行器契约加执行上下文），按硬线条款先把本次改动所属功能域
// 拆到独立文件再动手）。域定义一句话：工具执行的运行时——挂起交互桥（ask_user / browse_act
// 确认，按会话分桶）+ 单调用执行包装 executeToolCall。
// 为何不能并入：ToolTypes 是工具域聚合根（注册表 + 常量 + 视图），运行时是「怎么执行」；
// 挂起桥与执行包装的消费者是编排层（ChatSendCtrl / ChatToolRoundCtrl），与注册表面互不依赖。
// clipToolResult 不随迁（★ 2026-10-06 拆分笔后此判已变更——本句只述 2026-09-26 当笔取舍）：
// 消费方 15 件中 7 件在工具域外（HelpContent / SkillText / ChatDbSchema
// 等纯文本域），迁出会强制白名单外文件改 import——当笔留在 ToolTypes；2026-10-06 拆分笔复核
// 后整域外迁 ToolClip.ets（白名单外 import 实际只两件，随拆改接线；沿革见该件头注释）。
// 沿革：挂起桥原在 ToolTypes（2026-09-24 会话维度隔离笔 D 按会话分桶），本笔方法体逐字搬迁
// 零语义变化。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { toolTitle, ToolEntry } from './ToolTypes';
import { toolErrorText } from './ToolContracts';
import { toolArgsCheckErrorText } from './ToolArgsCheck';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { scriptScheduler } from '../codeexec/ScriptEnginePick';
// Python 串行 lane 取消（门 4：与脚本调度器同停链漏斗——本会话排队条目撤回、在跑一发协作式取消）
import { cancelPyForConversation } from '../pyexec/PyScheduler';
// Node 执行域取消（门 2：同停链漏斗——只递增本会话取消代次，排队者当场出队、在跑转 bootstrap
// cancel 终止该会话 worker；其他会话不受影响）
import { cancelNodeForConversation } from '../nodeexec/NodeScheduler';

const DOMAIN: number = 0x0001;
const TAG: string = 'ToolRuntime';

// 挂起桥条目（2026-09-24 会话维度隔离笔 D，方案档 §九.4）：分栏态多会话并发确定可达
//（EXPANDED ≥840vp 左栏进入 B 会话时右栏 A 页不销毁）——挂起表按会话分桶，条目持
// conversationId 供 cancelAllPending 按会话清理；callId 全局唯一，resolveAsk/
// resolveBrowseConfirm 按 callId 直查不受分桶影响（签名不变，ChatPage 上行链零改动）
interface PendingEntry<T> {
  conversationId: string;
  resolve: (value: T) => void;
}

// ask_user 交互桥：执行轮挂起等用户作答（挂起表只存内存——进程死亡即丢，
// CubeAgent 同语义；页面销毁走 cancelAllPending 防悬挂）
export class ToolRuntime {
  private pendingAsks: Map<string, PendingEntry<string>> = new Map();
  // browse_act 确认桥（2026-09-18 P2 B 单元，照 pendingAsks 形制）：高危动作挂起等用户在
  // 确认卡上点「允许一次 / 拒绝」（pendingConfirms 同样只存内存；resolve false = 拒绝）
  private pendingConfirms: Map<string, PendingEntry<boolean>> = new Map();
  // 会话级「始终允许」白名单（2026-09-20 笔 C；方案 §2.6）——用户在确认卡点「本会话内允许」
  // 后，本会话内该工具不再弹确认卡。key = conversationId + '|' + toolName；**只存内存**：
  // 不落库、不进 AppStorage（convId 由调用方经宿主 conversationId() 快照传入，与确认链
  // 「桥内不自读中转键」同纪律——assert-app-domain 125 组负向钉守此线），进程死亡即失效。
  // ★ 结构取 Set 而非方案原文的 Map<string, boolean>：键即全部信息、值恒真，语义等价（申报）。
  // 有界性：条目数受「会话数 × 工具数」天然约束，量级 KB，不设显式上限（只进不出的是键集合，
  // 不是数据；用户切会话只增不删，故此处写明口径）
  private sessionAllows: Set<string> = new Set<string>();

  // 挂起等用户作答（ChatToolRoundCtrl 工具轮消费；resolve 时以答案 JSON 串续跑）。
  // conversationId = 发起页会话（D 分桶键，传自宿主 conversationId()）
  waitAsk(conversationId: string, callId: string): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void) => {
      const entry: PendingEntry<string> = { conversationId: conversationId, resolve: resolve };
      this.pendingAsks.set(callId, entry);
    });
  }

  // 用户提交答案（ChatPage ask 卡上行；callId 不在挂起集 = 已取消/已答——静默吞防误触）
  resolveAsk(callId: string, answerJson: string): void {
    const entry: PendingEntry<string> | undefined = this.pendingAsks.get(callId);
    if (entry !== undefined) {
      this.pendingAsks.delete(callId);
      entry.resolve(answerJson);
    }
  }

  // 挂起在场探测（★ 解耦笔6 域⑤ 2026-10-16 新增；只读零副作用——ChatSendCtrl.resolveAsk
  // 的续答路由判据）：true = 同进程在途（原内存续跑通道）；false = 无桥（重进后的等待卡，
  // 走库侧续答编排或放弃口）
  hasPendingAsk(callId: string): boolean {
    return this.pendingAsks.has(callId);
  }

  // 挂起等用户确认高危浏览动作（工具轮域消费；resolve 值 = 是否允许本次执行；分桶同 waitAsk）
  waitBrowseConfirm(conversationId: string, callId: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      const entry: PendingEntry<boolean> = { conversationId: conversationId, resolve: resolve };
      this.pendingConfirms.set(callId, entry);
    });
  }

  // 确认挂起在场探测（2128 笔；只读零副作用——ChatSendCtrl.resolveBrowseConfirm 的续答
  // 路由判据）：true = 同进程工具轮仍在等（原内存续跑通道）；false = 重进后的确认卡
  // （无桥，走库侧回填续答——确认等待行已随 run 落库）
  hasPendingConfirm(callId: string): boolean {
    return this.pendingConfirms.has(callId);
  }

  // 用户在确认卡上作答（ChatPage 确认卡上行；callId 不在挂起集 = 已取消/已答——静默吞）
  resolveBrowseConfirm(callId: string, approved: boolean): void {
    const entry: PendingEntry<boolean> | undefined = this.pendingConfirms.get(callId);
    if (entry !== undefined) {
      this.pendingConfirms.delete(callId);
      entry.resolve(approved);
    }
  }

  // 会话级免询问授予（唯一写点 = 用户按确认卡第三键那一刻，见 ChatToolRoundCtrl.awaitBrowseConfirm）
  grantSessionAllow(conversationId: string, toolName: string): void {
    if (conversationId === '' || toolName === '') {
      return; // 空键不落（防全空串键命中一切）
    }
    this.sessionAllows.add(conversationId + '|' + toolName);
  }

  // 会话级免询问查询（唯一读点 = 门闸，见 ChatToolRoundCtrl.sessionAllowHit）
  isSessionAllowed(conversationId: string, toolName: string): boolean {
    if (conversationId === '' || toolName === '') {
      return false; // 空键恒不命中（与授予侧守卫成对；fail-safe 方向）
    }
    return this.sessionAllows.has(conversationId + '|' + toolName);
  }

  // 兜底取消（停止/销毁/轮次收尾）：**只清本会话**的未答挂起并以取消 JSON 续跑（模型可
  // 感知用户中止）；★ 确认挂起同会话连带清（resolve false = 视为拒绝，不留悬挂 Promise
  // ——内存防线成对）。★ 2026-09-24 D：原无参全量清在分栏态会连带取消他会话在途挂起
  //（B 页点停止掐断 A 页提问卡）——改按 conversationId 过滤；空会话 id 清不到任何条目
  //（fail-safe 不越界）。先收集命中键再删（forEach 内删除当前条目虽规范允许，收集法
  // 对两桶同构逻辑共享一个帮助方法）。★ 2026-10-06 代码工作台笔F：脚本（exec_code）取消
  // 纳入本停链——本会话在跑与排队的脚本一并取消（调度域内部判会话归属；无命中 no-op），
  // 宿主手动停止 / 页面销毁 / 重发停止三处漏斗经本函数自动覆盖。★ 2026-11-14 门 4：Python
  // lane 同停链接入（同漏斗自动覆盖；在跑一发为协作式取消，不承诺强杀）。★ 门 2：Node 执行域
  // 同停链接入（只影响同会话——代次递增 + 排队出队 + 在跑转 bootstrap cancel 终止该会话 worker）
  cancelAllPending(conversationId: string): void {
    this.cancelPendingBucket<string>(this.pendingAsks, conversationId,
      (entry: PendingEntry<string>): void =>
        entry.resolve(JSON.stringify({ cancelled: true, error: '用户中止了本次提问' })));
    this.cancelPendingBucket<boolean>(this.pendingConfirms, conversationId,
      (entry: PendingEntry<boolean>): void => entry.resolve(false));
    scriptScheduler().cancelForConversation(conversationId);
    cancelPyForConversation(conversationId);
    cancelNodeForConversation(conversationId);
  }

  // 挂起桶按会话清理（cancelAllPending 单点；泛型收两桶同构逻辑——P2-4 重复提取）
  private cancelPendingBucket<T>(bucket: Map<string, PendingEntry<T>>,
    conversationId: string, settle: (entry: PendingEntry<T>) => void): void {
    const hits: string[] = [];
    bucket.forEach((entry: PendingEntry<T>, callId: string): void => {
      if (entry.conversationId === conversationId) {
        hits.push(callId);
        settle(entry);
      }
    });
    for (const callId of hits) {
      bucket.delete(callId);
    }
  }
}

export const toolRuntime: ToolRuntime = new ToolRuntime();

// 逐调用执行上下文派生（★ 2026-10-06 代码工作台笔D 段一——工具结果附件通道的并行隔离面）：
// 契约全字段逐一透传（照 ToolHttp.bgCtx 显式字面量先例——ArkTS 对象展开受限，
// components/SegmentBar 有「量 spread 受限」实测注记），唯一覆写 = collectImage（本调用的
// 附件缝——闭包字段，覆写即绑新行为）；collectPageImage 原样透传（引用相等，页图路不改）。
// 入参 ctx 零改动（返回新对象——并行 lane 各自一份互不串写，这是「并行 lane 附件不串扰」
// 的唯一机制面：禁在挂载缝里用「当前调用」可变字段）。
// ★ 维护义务：MessageContracts.ToolExecutionContext 扩字段时本函数必须同步透传（漏一项 =
// 派生上下文静默缺值）；断言 assert-tool-domain 判据组钉全字段透传。
export function deriveCallContext(base: ToolExecutionContext,
  sink: (mimeType: string, data: string) => boolean): ToolExecutionContext {
  return {
    scope: base.scope,
    conversationId: base.conversationId,
    runId: base.runId,
    attemptId: base.attemptId,
    assistantId: base.assistantId,
    memoryScopeAssistantId: base.memoryScopeAssistantId,
    knowledgeAssistantId: base.knowledgeAssistantId,
    searchResultCount: base.searchResultCount,
    isRunActive: base.isRunActive,
    hasVision: base.hasVision,
    collectImage: sink,
    collectPageImage: base.collectPageImage,
    // ★ 2026-10-09 挂载 copy_in TOCTOU 笔：预检便签全字段透传随形（维护义务见上注——漏一项
    // = 派生上下文静默缺值；本字段语义 = 基值随行，写点纪律见 MessageContracts 字段注释）
    preflightMemo: base.preflightMemo
  };
}

// 工具执行（单调用包装；失败转 error JSON 不炸轮次——RikkaHub execute 同语义）：
// args 解析失败原样透传（模型自纠）；executor 抛错包装 {"error": ...}。
// ★ 本函数自身无并发防护义务——同一轮多调用在 ChatToolRoundCtrl 经 lanes（Promise.all）
// 并发执行（日志「工具并行」打点），executor 内涉及计数/快照回执的（如 manage_memory 的
// count+1）只承诺文案级一致，写冲突由 DB 行级操作与 affected-0 抛错防御兜底
// ★ ctx 形参（2026-09-26 笔1 S3）：显式执行上下文随链下传（I9）——缺上下文 = 调用方漏传，
// 明确抛错禁静默；context 形态不对（scope 缺失）同抛。调用点两文件（2026-10-24 修正过时
// 「唯一调用点」表述）：主链 ChatToolRoundCtrl.runRegistered 四路与重发链
// ChatToolResendCtrl.executeAndSettle（2026-10-22 引入）——本函数内的新前置层两链自动全覆盖
export async function executeToolCall(entry: ToolEntry, argsJson: string,
  ctx: ToolExecutionContext): Promise<string> {
  if (ctx === null || ctx === undefined) {
    // I9 红线：已迁调用方缺执行上下文必须明确失败，禁默认回退全局当前值掩盖漏传
    throw new Error('工具 ' + entry.name + ' 缺少执行上下文（ToolExecutionContext 未传递）');
  }
  // （控制台独占件 / 封顶件两道执行层拦截已随 2026-10-25 控制台合并笔退役——控制台助手
  // 整体退役后归属判据失去对象，原独占 13 件中 12 件对全部助手开放、写面安全由确认链与
  // 助手工具页开关承接；沿革 = 变更记录对应节）
  // 执行前统一参数校验（2026-10-24 工具易用性案 U-P0，前置新增层——存量执行器逐字段守卫
  // 一律不动，纵深防御）：四项校验（顶层对象 / required 缺失一次列全 / 类型不匹配〔type 六类
  // 单值才查，数组形态与野值跳过——MCP schema 容错〕/ enum 越界）对注册表 schema（entry.
  // parametersJson）逐项过；fail-closed 字段级回执教模型自纠（字段名 + 期望 + 收到值开头片段
  // + 重试指引）；校验器（ToolArgsCheck）自包 try 恒不抛、自损返 null 放行执行器兜底。挂
  // 函数体内 = 主链 ChatToolRoundCtrl.runRegistered 与重发链 ChatToolResendCtrl.
  // executeAndSettle 两调用文件全覆盖。回执 {error} 同形（与未声明闸 / 未知工具闸 / 执行器
  // 抛错包装一致），下游 role:'tool' 回传 / detectErrorResult error 态卡面 / 截断三环零改动。
  // kill 开关 = ToolArgsCheck.TOOL_ARGS_CHECK_ENABLED（功能保险类，同 TOOL_DEFS_BUDGET_
  // ENABLED 族）。**挂 try 之前自行 return**——不依赖外层 catch（其文案经 toolErrorText 会失真）
  const argsCheckError: string | null = toolArgsCheckErrorText(entry.parametersJson, argsJson);
  if (argsCheckError !== null) {
    hilog.warn(DOMAIN, TAG, '工具 %{public}s 参数校验未过：%{public}s', entry.name, argsCheckError);
    return JSON.stringify({ error: argsCheckError });
  }
  try {
    return await entry.executor.execute(argsJson, ctx);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '工具 %{public}s 执行失败：%{public}s', entry.name, toolErrorText(e));
    return JSON.stringify({ error: toolErrorText(e) });
  }
}
