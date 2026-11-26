// 工具执行器契约（叶子模块——2026-09-13 真机启动闪退修复笔新建；★ 2026-09-26 笔1 S3 起
//   import 一处纯类型叶子 MessageContracts——执行上下文随链下传的载体类型，修订依据 =
//   任务书-消息架构整合笔1 S3「上下文类型落 MessageContracts，经注册层注入」；本文件
//   **仍禁 import 注册器与 UI**（I10 红线原样），MessageContracts 自身零 import 不会成环）。
// ★ 为什么单独成文件：ToolTypes.ets 是工具域的**聚合根**（它 import 全部工具域实现，用于
//   内置注册），而各工具域（ToolPref / ToolProvider / ...）与 MemoryGen 又要用 ToolExecutor
//   这个接口——原来从 ToolTypes.ets 引，等于「域 ← 聚合根」反向边，与聚合根→域的正向边构成
//   环（ToolTypes → ToolPref → MemoryGen → ToolTypes 等十二条）。接口本身是类型擦除的，环
//   单靠接口引用无害；**但只要环内任一模块在模块作用域读/调用对方的绑定，就会踩未初始化
//   绑定**（2026-09-13 工具补齐三件笔实锤：ToolPref 顶层白名单数组调 PROACTIVE_INTERVAL_OPTIONS
//   .map() —— 真机启动即 JsError 闪退，进程活不过 onCreate；AssertionD 见
//   scripts/assert-app-domain.mjs「域文件禁引 ToolTypes」负向钉）。
// ★ 纪律：一切工具域与 MemoryGen 等反向引用方一律
//   `from './ToolContracts'`（MemoryGen 为 `'./providers/ToolContracts'`），**禁**从 ToolTypes
//   引 ToolExecutor——引一次就把环接回来一次。
// 契约本身：入参 = 模型给出的 arguments JSON 串 + 显式执行上下文（会话/运行身份与各执行器
//   所需快照值——2026-09-26 笔1 S3 起替代进程级中转键；缺上下文由 executeToolCall 拦，
//   I9 明确失败禁回退）；返回 = 结果文本（进请求回传与卡片展示）。
// 抛错 = 执行失败（调用侧转 error JSON，不炸链路）。
import { ToolExecutionContext } from '../chat/MessageContracts';

export interface ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string>;
}

// ── 确认链预检契约（★ 落本叶子而非聚合根的理由 = 环红线：
//    两个预检实现（ToolBrowseAct / ToolHttp 域件）都要消费本类型与档位常量，落 ToolTypes
//    等于让域件反向引聚合根——正是 ToolExecutor 当年踩过的环（本文件头注释），且触
//    assert-app-domain 85 组负向钉。任务书原写落 ToolTypes，按项目环纪律改落叶子并申报。）──
// 预检返回二元组：text = 卡面主因句；level = 档位（CONFIRM_LEVEL_WRITE / _IRREVERSIBLE），
// 供卡面档位徽章与（笔 C 起）会话级允许判据读取。返回 null = 无需确认（语义与旧「空串」一致）。
export interface ConfirmPrompt {
  text: string;
  level: string;
  // 结论去向（2026-09-28 三档归并笔，可选）：CONFIRM_ROUTE_HUMAN = 预检直指人工卡（「每次确认」
  // 档——不过审批模型）；undefined 与 CONFIRM_ROUTE_MODEL = 交给审批闸（模型放行即执行、拒绝与
  // 拿不准落人工卡；槽位未配置时闸 escalate 到同一张人工卡）。★ 域知识留工具侧：编排层只按本
  // 字段分派，不认工具名（新增确认工具零改编排层）
  route?: string;
  // 结构化预览（2026-10-01 方案-HTTP工具完善 批 2 笔 2，可选）：卡面可展开的「要发什么」
  // 明细串（方法、网址、脱敏请求头、正文开头），由预检产串、编排层原样透传、卡面折叠渲染。
  // 脱敏红线在预检实现侧兑现（敏感头值 [已隐藏]、凭据只以 {{名称}} 记号形态出现）；本叶子
  // 不解读内容。undefined = 无预览（browse_act 等既有确认零变化）
  detail?: string;
  // 本次请求的目标域名（可选）：写点 = 预检实现自 URL 取 host；消费方 = 确认卡说明与
  // 等待态回放载荷。undefined/空 = 目标域名未知或非 HTTP 域确认（卡面不渲染域名行）。
  // ★ 2026-11-11 域名确认档退役后，本字段不再承担「始终允许该域名」的落档写点
  domain?: string;
}

// 确认档位：写操作档（browse_act 非删除族动作 / http_request 写方法）
export const CONFIRM_LEVEL_WRITE: string = 'write';
// 确认档位：不可逆档（browse_act 命中删除族词表——卡面出红徽章与风险块）
export const CONFIRM_LEVEL_IRREVERSIBLE: string = 'irreversible';

// 结论去向两值（2026-09-28 三档归并笔；与 ConfirmPrompt.route 配套，写点 = 预检实现经
// ConfirmRouting 归一，读点 = ChatToolRoundCtrl 分派）：MODEL = 先问审批模型（缺省口径），
// HUMAN = 直接等人工作答。★ 归一规则本体不落本叶子——本件是「叶子唯一 import 源 =
// MessageContracts」的防环纪律面（assert-app-domain 85 组），档位常量在 AppPreferences，
// 引它即破纪律；规则落同层新叶子 ConfirmRouting.ets（本值域两常量两岸共引）
export const CONFIRM_ROUTE_MODEL: string = 'model';
export const CONFIRM_ROUTE_HUMAN: string = 'human';

// toolConfirmResult 审批闸两值（2026-09-28 命令审批功能笔；落本叶子 = 写点 ChatToolRoundCtrl
// 与读点 ChatToolCard 两岸共引，禁散写字面量）：审批模型自动结论的卡面痕迹——aiAllowed =
// 模型允许后直接执行（无人工作答）、aiDenied = 模型拒绝即终态（理由随 toolConfirmReason）。
// 与既有 'approved'/'rejected'/'session' 三人工值同字段不同源（后者写点 = 用户在卡上作答）
export const CONFIRM_RESULT_AI_ALLOWED: string = 'aiAllowed';
export const CONFIRM_RESULT_AI_DENIED: string = 'aiDenied';

// ── 工具回执帮助函数（2026-09-29 失败回执可辨认性收口笔；落本叶子 = 十余执行器域件共引，
//   引聚合根即接回环——同 ToolExecutor 先例；两函数零 import，不触碰 85 组「唯一 import 源」钉）──

// 参数解析失败统一回执（执行器 JSON.parse catch 共用）：裸句「参数解析失败」对模型零信息
//（它事后看不见自己吐了什么参数），补收到内容开头片段供对照自纠；「只补下一步指引，不改
// 透传取向」红线内的指引句
export function toolArgsParseErrorText(argsJson: string): string {
  const compact: string = argsJson.replace(/\s+/g, ' ').trim();
  const shown: string = compact.length > 80 ? compact.substring(0, 80) + '…' : compact;
  return '参数解析失败，工具参数不是合法的 JSON 对象。收到内容开头：' + shown +
    '。请检查 JSON 格式后重试。';
}

// 异常信息安全取串：e 非 Error（BusinessError 等接口对象）时 (e as Error).message 可为
// undefined（本仓 ToolHttp 曾实证 [object Object] 进回执）——回执面禁出现 undefined/
// [object Object] 字样；底层报错原文照旧透传，本函数只兜「没带信息」的空窗。
// ★ 2026-09-29 自检轮收口：旧式对无原因拒绝（null/undefined）直接 (e as Error).message
// 会抛 TypeError——本函数被各 catch 块调用，二次抛错会把已捕获的失败升级成新异常
//（safeRun 同步 catch 场景下直破「工具失败不炸轮次」），故入参放宽并首查空原因
export function toolErrorText(e: Object | null | undefined): string {
  if (e === null || e === undefined) {
    return '异常未携带错误信息';
  }
  const msg: string | undefined = (e as Error).message;
  return typeof msg === 'string' && msg !== '' ? msg : '异常未携带错误信息';
}

// ── 回执 diff 值截断单源（2026-10-16 diff 批 U13·U-D2a；施工总案《三方案与diff覆盖施工
//   总案-20261016》§四 4.2 判据总则）──
// 六件执行器（edit_system_prompt / edit_title_prompt / manage_prompts / manage_providers /
// manage_models / manage_balance）在成功回执加 oldValue/newValue 供工具卡红绿 diff——值本可
// 长达提示词全文级别，进回执即进模型上下文与库容，故统一按本上限逐侧截断（截断标记「…」
// 让模型与用户对「值不全」可感知）；显示侧另有 ChatToolDiffBlock 的 TOOL_DIFF_MAX_* 行级
// 上限，两截断职责不同勿混。落本叶子 = 六执行器已 import 本件（同失败回执两助手先例，
// 零新环）
export const RECEIPT_DIFF_VALUE_MAX_CHARS: number = 2000;

// 值截断纯函数：限内原样（含空串）；超限裁到上限并缀省略号。多行值按字符计——换行不享受
// 特殊待遇，截断点可落在行中（显示侧行切分对残缺尾行自然承接）
export function clipReceiptDiffValue(value: string): string {
  if (value.length <= RECEIPT_DIFF_VALUE_MAX_CHARS) {
    return value;
  }
  return value.substring(0, RECEIPT_DIFF_VALUE_MAX_CHARS) + '…';
}

// ── 回执尾行 envelope 组装（2026-10-16 diff 批 U14·U-D2b；契约 = 施工总案 §四 4.4）──
// 纯文本回执族「附加而非替换」：原句逐字保留 + '\n' + 单行紧凑 JSON（oldValue/newValue
// 两键）；值经 clipReceiptDiffValue 同一单源截断（值可长达正文/提示词全文级别）。双空返回
// base 原样不附加（无改动可显 = 卡面零块）；键序恒 oldValue 在前，值内换行与引号经
// JSON.stringify 转义故尾行恒单行——解析侧 ChatToolDiffBlock.receiptPairDiffFromOutput 自
// 末行向前逐行试 JSON 即认此形态（历史旧回执无尾行 → 解析 null → 无块零迁移）。
// 落本叶子 = 四执行器已 import 本件（同截断单源先例，零新环）
export function appendReceiptDiffTail(base: string, oldValue: string, newValue: string): string {
  if (oldValue === '' && newValue === '') {
    return base;
  }
  return base + '\n' + JSON.stringify({
    oldValue: clipReceiptDiffValue(oldValue),
    newValue: clipReceiptDiffValue(newValue)
  });
}

// ── 回执尾行 envelope 组装·覆盖写摘录档（2026-10-16 diff 批 U15·U-D3；契约 = 施工总案
//    §四 4.3/4.4）──
// 覆盖写两工具（workspace_write / mount_write）成功回执的两个键组组装单源：①摘录对——
// oldExcerpt/newExcerpt，旧文/新文各经 clipReceiptDiffValue 同一单源截断（2,000 字符，与
// D2a/D2b 同限）；②超阈跳过档——diffSkipped/oversize + oldLines/newLines 行数对（旧文超
// 读门槛时不带正文只报行数）。返回 '' = 无尾行（调用方空串不附加）；换行拼接由 composer 侧
// 可选参承接（envelope 形态与 D2b 同构：原句 + '\n' + 单行紧凑 JSON）。落本叶子 = 两执行器
// 已 import 本件（同截断单源先例，零新环）
export function buildReceiptDiffExcerptTail(oldText: string, newText: string): string {
  if (oldText === '' && newText === '') {
    return '';
  }
  return JSON.stringify({
    oldExcerpt: clipReceiptDiffValue(oldText),
    newExcerpt: clipReceiptDiffValue(newText)
  });
}

// 超阈跳过档（旧文超读门槛——不整载旧文、不带正文；行数口径 = split('\n') 计数，与
// workspace_read「共 N 行」/ workspace_edit「行数 A→B」回执同源，模型两侧对得上账）
export function buildReceiptDiffOversizeTail(oldLines: number, newLines: number): string {
  return JSON.stringify({ diffSkipped: 'oversize', oldLines: oldLines, newLines: newLines });
}

// 「代码工作台总开关拦截句」常量已随总开关退役（可用性全权交助手级「脚本工作台」卡，
// 拦截句失掉存在对象，六情形表「功能退役」同笔处理）

// ── 注册条目契约（自 ToolTypes.ets 原样搬迁）──
// 搬迁缘由 = 宪法 1200 硬线条款：ToolTypes.ets 已越线，注册表容器要加 unregister——容器
// 与条目契约同落本叶子（ToolRegistry.ets 只引本件，零环）；上面 ToolExecutor「域件契约
// 自叶子引」的同一条纪律顺延到注册条目。
// ★ 消费方兼容：ToolTypes.ets 以 import 后再 export 的形态转出本接口（照 MemoryGen /
// AiTypes 先例），存量 `import { ToolEntry } from './ToolTypes'` 不受影响；**新码一律自
// 本件引**（坑50 纪律，勿再经聚合根）。
// 注册条目（定义 + 展示 + 执行器三合一）
export interface ToolEntry {
  name: string;
  title: string; // UI 展示名（截图口径：「获取当前时间」「向用户提问」）
  desc: string; // 请求侧 description（模型阅读——引用规范等工具细节全在此，英文原文不动）
  // 工具页分组（功能卡轴——TOOL_GROUP_* 十常量，2026-09-08 分组显示 / 2026-09-13 语义轴 /
  // 2026-09-18 分类卡轴 / 2026-09-27 位置与浏览器控制两卡拆分）：必填字段 = 新增工具忘标分组时编译期报错（比映射表少一个静默漂移面）
  group: string;
  parametersJson: string; // JSON Schema 原串（compose 内 parse 后入请求体）
  defaultEnabled: boolean; // 默认启用（ assistants.tools 列为空时的默认集合成员）
  executor: ToolExecutor;
  // 确认链预检（2026-09-19 HTTP 请求工具笔，确认链注册表化泛化）：返回 null = 直通，非 null
  // = 需弹确认卡（text 即卡面主因句，level 即档位）——工具轮 executeToolCalls 预检循环按此
  // 收集（browse_act 异步精判 / http_request 同步 async，统一走 await）；缺省 = 无确认环节。
  // ★ 2026-09-20 审批卡视觉迁移笔 A：形态由「返回串（'' = 直通）」改「说明串＋档位二元组」
  //（ConfirmPrompt，落叶子 ToolContracts——域件要消费它，落聚合根会接回环，见该文件头注释）。
  // ★ 实现契约（2026-09-19 自检 P3-5）：实现必须全包 try/catch，恒不抛——预检循环裸 await
  // 无兜底，实现抛错 = 整轮静默死、发送态永挂。编排层不代兜：抛错兜成 null 会把「预检异常」
  // 翻译成「直通执行」，对依赖预检弹卡护写动作的工具 = 绕过确认红线，比静默死更危险——
  // 契约落本注释位（后来者必读），自防责任在实现侧。
  // ★ fail-closed（2026-10-04 拍板 H3-5）：「任何异常一律返 null」自本日起收窄为分阶段口径
  //——写确认类预检（http_request 与模板两口）在「已判定写操作」之后的异常一律返保守人工
  // 确认卡（writeConfirmFallbackPrompt，恒 CONFIRM_ROUTE_HUMAN）不返 null：null = 直通，
  // 预检挂而执行成 = 写请求无卡直发；写方法不可知（模板行查询异常类）同返保守卡。坏形态
  // 阶段（参数解析失败 / 组装失败等执行器必有错误回执拦下的形态）仍返 null。browse_act 等
  // 其他存量预检件原口径留档不溯及，触碰时按本条渐进对齐
  // ctx 形参（2026-09-26 笔1 S3）：预检随链携带执行上下文（browse_act 归属前置粗判消费；
  // http_request 不消费）。实现必须全包 try/catch 的契约原样保留
  preflight?: (argsJson: string, ctx: ToolExecutionContext) => Promise<ConfirmPrompt | null>;
  // 用户允许后、执行前的授予动作（2026-09-19）：目前唯一持有者 browse_act（写单次批准戳）
  // ——函数体零改动，接线方式自编排层硬编码改注册表分发；http_request 不带（跨工具写戳 =
  // 语义污染 + 未来第三件带戳工具的误消费口子）
  onApproved?: (convId: string) => void;
  // ── 工具政策元数据（★ 2026-09-27 架构收口笔1：随注册项**就地定义**，读侧经派生函数
  //   消费）。**只描述既有行为**——缺省 = 不适用，不是新语义、更不是新放行。均为可选：
  //   仅非缺省件显式标注（给省略件补 false 属零信息增量，禁写）──
  // （consoleExclusive / consoleCore 两字段已随 2026-10-25 控制台合并笔退役——控制台助手
  //   整体退役后「独占/核心」语义失去对象，原独占 13 件中 12 件开放给全部助手、
  //   set_app_preference 整件退役；沿革 = docs/变更记录.md 对应节）
  // 模式驱动（声明与否由全局模式开关决定，不走 assistants.tools 启用清单；现役件 =
  // search_memory / use_skill / env_list / HTTP 请求模板动态工具）；缺省 / false = 走
  // assistants.tools 启用清单与助手工具页
  modeDriven?: boolean;
  // 联网域成员（随联网域可用性「助手清单 ∩ 会话开关 ∩ 总开关」同进同出；现役两件 =
  // search_web 主件 / scrape_web 从属）；缺省 / false = 不随联网三级闸门
  webDomain?: boolean;
  // （「代码工作台成员」codeWorkbench 字段已随全局总开关退役——2026-10-06 控制面层级化
  // 笔：三件脚本族工具改为 TOOL_GROUP_CODE 独立卡随助手清单进出，无全局闸）
  // 交互类别（取值 INTERACTION_ASK / INTERACTION_DIRECT；决定工具轮是否整轮串行并与用户
  // 往返——现役仅 ask_user）；缺省 = INTERACTION_DIRECT（直通注册器执行器）
  interactionKind?: string;
}
