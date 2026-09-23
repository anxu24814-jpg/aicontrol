// 搜索结果条数值域（2026-09-10 搜索结果条数助手级可调笔；零依赖叶子模块）：
// assistants.searchResultCount 列（DB v25）的存储值语义 + 「存储值 → 生效条数」唯一换算点 +
// 发送链中转键名。
// 值域（存储值）：1~SEARCH_RESULT_COUNT_MAX(25) 条；默认 SEARCH_RESULT_COUNT_DEFAULT(5) =
// 旧全局常量 SEARCH_RESULT_COUNT 同值，未配置助手与存量助手行为逐字节零回归。
// ★ 为何是「助手级」而不是全局偏好键：条数是行为参数（怎么搜），与 assistants.toolStepLimit
// （助手级工具轮上限）同类；同功能的「联网开关」本就在助手级（assistants.tools 里
// search_web 的启停），参数留在全局会造成「同一功能开关在助手级、参数在全局」的分裂。详见
// docs/方案-搜索条数助手级可调-20260910.md §二。
// ★ 为何需要本模块（值到达执行器的通道）：搜索执行器的接口是 execute(argsJson: string)
// （ToolTypes.ets）——只有参数字符串，既不知道助手也不知道会话，没有 id 可反查库；而条数在
// 执行器层消费（拼进请求体 + 解析上限），不在轮次控制器层。故走**发送链中转键**：ChatSendCtrl
// 发送时把本次解析出的助手级条数写进 AppStorage，SearchEngineRegistry.dispatchSearch 读回填进
// 引擎运行时 ctx（先例 = 同族的 CHAT_WEBSEARCH_ON_KEY 中转键机制）。这不改 ToolExecutor 接口
// （改接口要动全部 4 个实现与将来每个新执行器）。
// ★ 中转键名为何放这里而不放 UI 文件：既有先例 CHAT_WEBSEARCH_ON_KEY 声明在 chip 组件文件
// （ChatParamChipBar.ets）里，键名落在 UI 层并不理想——本模块让发送链（components 层）与搜索
// 编排（common/search 层）同源引用同一常量，方向天然合法、零双源。
// ★ 为何独立成叶子文件而不并入 WebSearch/ApiSearchEngines：存储层 AssistantDb 需引用默认值，
// 而搜索域既有文件带 NetworkKit kit 依赖（存储层引 search 域会牵入网络栈）；叶子模块零 import，
// 存储层/发送链/搜索编排/UI 四方共用同一份常量与换算，禁各处自写一套（ToolLimits.ets 头注释
// 记录了同款理由）。
// ★ 消费面：条数在协议侧与解析侧都已是现成形状——博查请求体 count、秘塔 size、Serper num
// 今天就把常量拼在请求体里；三个解析器签名本就是 parseXxxResults(json, maxCount)。本笔只换
// 它们传的实参。
// ★★ 红线（2026-09-10 自检轮加）：本文件**必须保持零 import**——scripts/sse-assert.mjs 55 组
// 把本文件复制成 .tmp/SearchLimits.ts 后**直接 import 求值**（同 ToolLimits 先例）。一旦本文件
// 引入任何 import 或顶层运行期错误，**整套断言脚本会整体崩掉并停止打印计数行**（不是单条变红，
// 实测复现）；门禁判据「无计数无标志行 → FAIL」能兜住不假绿，但代价是全部 1007 条一起失效。
// 需要新常量就写在零依赖的叶子模块里，勿在此文件引入外部依赖。
export const SEARCH_RESULT_COUNT_DEFAULT: number = 5;
export const SEARCH_RESULT_COUNT_MIN: number = 1;
export const SEARCH_RESULT_COUNT_MAX: number = 25;

// 发送链中转键（AppStorage 进程级键；写点 = ChatSendCtrl 发送时，读点 = SearchEngineRegistry
// .dispatchSearch 组装引擎运行时 ctx 时。键缺失 = 非会话路径调用，读侧回默认 5）
export const CHAT_SEARCH_COUNT_KEY: string = 'chatSearchCount';

// 存储值 → 生效条数（发送链与 UI 展示共用的唯一换算点）：<= 0（脏数据）与非有限数（NaN/
// Infinity）= 默认 5；非整数四舍五入；结果再收口到 1~25——上界防脏数据放大花销，下界防
// 「0.4 轮成 0 条」这类取整后越界
export function resolveSearchResultCount(stored: number): number {
  if (!Number.isFinite(stored) || stored <= 0) {
    return SEARCH_RESULT_COUNT_DEFAULT;
  }
  return Math.min(Math.max(Math.round(stored), SEARCH_RESULT_COUNT_MIN), SEARCH_RESULT_COUNT_MAX);
}
