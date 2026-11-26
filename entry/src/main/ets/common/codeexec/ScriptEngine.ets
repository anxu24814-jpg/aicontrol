// 脚本引擎抽象接口与数据类型（引擎可替换的架构预留面）。
// · 零 import 纪律（叶子）：本文件只放接口与数据类型，**禁 import 任何东西**——它是
//   JsvmEngine / QuickJsEngine / ToolCodeExec / 断言族共同消费的契约叶子；引一次就把
//   可求值依赖带回叶子（坑50 家族：环内模块作用域读对方绑定 = 未初始化值）。
// · 引擎预留三步已兑现：①独立 native 目标 qjsengine 与独立 so（cpp/CMakeLists.txt 二进制
//   独立红线）；②ArkTS 实现类 QuickJsEngine implements 本接口；③分派点 = ScriptEnginePick
//   的 pickScriptEngine（按「用户引擎开关 × 档位」二维分派，判据单源 =
//   AppPreferences.codeWorkbenchUsesQuickJsEngine；开关 UI 见设置页「脚本引擎」卡）。
// · 契约同步三处：本接口 / cpp/types/libcodeexec/index.d.ts（JSVM 桥）/
//   cpp/types/libqjsengine/index.d.ts（QuickJS 桥，字段集合与本接口全等）——改名须三处
//   同步；fs.save 的待转正名单（savedNames）是执行必需的契约扩展，native 只登记，转正
//   编排与理由见 ToolCodeExec.ets 的 promoteSavedNames。

// 单次执行选项（数值全部由 ArkTS 侧单源组装后下传——档位映射单源 ScriptLimits.ets、
// 临时区两闸单源 WorkspaceTmpUtil.ets，**native 侧禁抄任何字面值**）
export interface ScriptRunOptions {
  // 沙箱 fs 根 = 会话临时区绝对路径（WorkspaceTmpUtil.workspaceTmpConversationDir 派生）
  workspaceRoot: string;
  // 限时毫秒（生效档位数值；native 只记录，到点判定由 ArkTS 侧计时器负责——ScriptScheduler）
  timeoutMs: number;
  // 堆上限字节 → CreateVMOptions.maxOldGenerationSize（生效档位数值）
  maxHeapBytes: number;
  // 结果与日志内联合计上限（生效档位数值；native 按此掐回执内联量——回执面预算）
  maxOutputChars: number;
  // 日志收集条数上限（收集与回执两预算分离的伴生字段——收集字节预算已扩至
  // tmpMaxFileBytes 量级，条数防线防病态超短行撑大 logs vector；ToolCodeExec 组装单源
  // 下发，native 侧缺省 0 = 不限条数）
  maxLogLines: number;
  // 临时区单件上限（WORKSPACE_TMP_MAX_FILE_BYTES 下传；兼任输出收集字节预算——溢出件
  // 承载完整产出，收集量与可落盘量同源）
  tmpMaxFileBytes: number;
  // 临时区总量上限（WORKSPACE_TMP_MAX_TOTAL_BYTES 下传）
  tmpMaxTotalBytes: number;
  // 溢出件名（ArkTS 生成并过名称闸后下发；无溢出路径不写盘，native 禁自造名）
  outputFileName: string;
  // 沙箱网络桥等待上限毫秒（httpGet 阻塞等待的上界——算式单源 ScriptHttpBridge.ets 的
  // scriptHttpWaitMs〔档位时限与用户上限档取小 + 余量〕构造后下传，native 零字面值；
  // 必填——防旧调用方静默落 0 使 httpGet 立即超时）
  httpWaitMs: number;
  // native per-run 取消目标键——**调度器注入，调用方不填**（ToolCodeExec 组 opts 不含
  // 该字段，可选故编译绿）；区别于 httpCtx.runId（会话运行轮 id，同轮并行 exec_code 会
  // 撞键，不得复用）——调度器内自增序号单源生成
  runKey?: string;
}

// 单次执行结果（原生回执——status / failureKind 不落 native，由装配层 ScriptReceipt 从
// 下列既有字段派生；溢出落盘回执四字段见下）
export interface ScriptRunResult {
  ok: boolean;
  // result(v) 或脚本末值（string 原样，其余 JSON.stringify，失败降级 String(v)；超内联
  // 上限时已截断）。脚本末值为 Promise 时 native 先注册捕获、排空微任务后取值（result
  // 显式设值优先；fulfilled 取完成值、rejected 归运行失败、永挂起报 PendingPromiseError）
  value: string;
  // console 输出（有界：收集面字节预算 = tmpMaxFileBytes 量级 + 条数上限 maxLogLines；
  // 超回执预算部分在溢出落盘后由 native 掐回——回执内联只保留前缀，全文在溢出件）
  logs: string[];
  // 失败时非空（SyntaxError / TypeError / FenceError / BusyError …）
  errorName: string;
  errorMessage: string;
  errorStack: string;
  // 实际耗时毫秒（native 侧计时）
  durationMs: number;
  // 标志族（全枚举——枚举源在本注释；装配层原样保留不删值）：
  // 'heap-limit' | 'output-truncated' | 'log-truncated' | 'wasm-removed' |
  // 'wasm-remove-failed'（删 WebAssembly 不可行——native 侧合成）|
  // 'js-exception'〔脚本自身抛异常——装配层据此与引擎错分家〕 |
  // 'spill-write-failed'〔溢出暂存写失败——装配层回执告知输出不完整〕 |
  // 'canceled'（收尾消费到取消标记——native 侧合成）|
  // 'deadline-hit'（计时器先到——ArkTS 侧 ScriptScheduler 合成，常量单源
  // SCRIPT_FLAG_DEADLINE_HIT）|
  // 'promise-pending'（末值 Promise 排空后仍未完成）|
  // 'prelude-failed'（沙箱预置环境初始化失败——装配层落 engine-error）
  flags: string[];
  // fs.save 登记的待转正文件名（native 只登记不落库——转正编排在 ToolCodeExec 的
  // promoteSavedNames，复用 promoteWorkspaceTmpFile 链）
  savedNames: string[];
  // 溢出件名（无溢出为空串）
  outputFileName: string;
  // 溢出件实际字节数（落盘实写量——顶闸时小于产出总量，信封如实呈现 + output-truncated
  // 旗标告知；原语义「合成全文大小」在顶闸时虚高，已改）
  outputBytes: number;
  // 头预览（约 1KB，UTF-8 边界对齐；无溢出为空串）
  outputHead: string;
  // 尾预览（约 1KB；无溢出为空串）
  outputTail: string;
}

// 引擎接口（两实现：JsvmEngine〔标准档〕/ QuickJsEngine〔严格档〕；分派 = ScriptEnginePick）。
// cancel() 供调度器对接口类型值发取消（超时到点联动中断 / 会话停止链）；native 侧本就是
// 各 so 的 cancelRunning() 模块导出（各引擎 cancel 转发）。cancel 携 runKey 定向——
// native per-run 取消块按键命中，B 路不再被 A 路的取消误杀（跨引擎并发下两 so 各自定向）。
export interface ScriptEngine {
  run(code: string, opts: ScriptRunOptions): Promise<ScriptRunResult>;
  cancel(runKey: string): void;
}
