// 联网搜索运行参数值域：全局偏好键 prefSearchResultCount 与 prefSearchTimeoutSec（键与
// 注释单一来源 AppPreferences.ets）的存储值语义 + 「存储值 → 生效值」唯一换算点 + 已退役
// 中转键常量位。零依赖。
// 值域（存储值）：1~SEARCH_RESULT_COUNT_MAX(25) 条；默认 SEARCH_RESULT_COUNT_DEFAULT(5) =
// 旧全局常量 SEARCH_RESULT_COUNT 同值，未配置与存量行为逐字节零回归。
// ★ 载体沿革（压记 1 行防回游）：原载体 = assistants.searchResultCount 列（DB v25，按助手
// 存）已退役为墓碑列（库内保留、代码面零读写，见 ChatDbSchema 同列注释），本键接管全局
// 唯一来源——参数层级由决明拍板上收为全局，不再是「开关在助手级、参数在全局」分裂形态。
// ★ 为何需要本模块（值到达执行器的通道）：搜索执行器接口是 execute(argsJson: string)
//（ToolTypes.ets）——只有参数字符串，无助手/会话 id 可反查库，而条数在执行器层消费（拼进
// 请求体 + 解析上限）。故走**执行上下文携带**：ChatSendCtrl 在接纳时把本次解析出的条数写
// 进 ToolExecutionContext.searchResultCount（随链显式下传，一次快照，执行器只读上下文），
// SearchEngineRegistry.dispatchSearch 读回填进引擎运行时 ctx。原 AppStorage 中转键
//（CHAT_SEARCH_COUNT_KEY，本文件下方常量位）已全仓零读写、仅留位兼容。
// ★ 为何独立成叶子文件而不并入 WebSearch/ApiSearchEngines：零依赖叶子模块，发送链
//（components 层）/ 搜索编排（common/search 层）/ UI 三方共用同一份常量与换算，禁各处
// 自写一套（ToolLimits.ets 头注释记录了同款理由）；存储层不再引用本文件（两列退役，
// 默认值不由存储层落库）。
// ★ 消费面：条数在协议侧与解析侧都已是现成形状——博查请求体 count、秘塔 size、Serper
// num、智谱 count（经 zhipuCountFor），解析器签名本就是 parseXxxResults(json, maxCount)。
// ★★ 红线：本文件**必须保持零 import**——scripts/sse-assert.mjs 把本文件复制成
// .tmp/SearchLimits.ts 后**直接 import 求值**（同 ToolLimits 先例）。一旦本文件引入任何
// import 或顶层运行期错误，**整套断言脚本会整体崩掉并停止打印计数行**（不是单条变红，
// 实测复现）；门禁判据「无计数无标志行 → FAIL」能兜住不假绿，但代价是全部断言一起失效。
// 需要新常量就写在零依赖的叶子模块里，勿在此文件引入外部依赖。
export const SEARCH_RESULT_COUNT_DEFAULT: number = 5;
export const SEARCH_RESULT_COUNT_MIN: number = 1;
export const SEARCH_RESULT_COUNT_MAX: number = 25;

// 发送链中转键（AppStorage 进程级键）——★ 已退役（曾用于：条数值由发送链现写、编排侧
// 读回）。现行通道 = ToolExecutionContext.searchResultCount 随链显式携带（接纳时一次
// 快照，执行器只读上下文、禁回读全局键）；原两处消费点均已删。键位保留仅作兼容，
// **全仓零读写**——勿按现役口径新增任何 AppStorage 读写
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

// ── 联网请求超时 ──
// 值 = 联网搜索与读取网页每次请求的等待上限（秒）。覆盖全部联网取回请求：Bing local 搜索
//（主/备用两入口）、博查 / 秘塔 / Serper 三家 API 引擎、scrape_web 网页抓取——原共用一个
// 写死常量 SEARCH_TIMEOUT_MS(=20000)，现同吃本键（生效值 = 默认 20 秒，存量行为零回归；
// 取值范围 = 请求入口取一次后形参下传，见 WebSearch 文件头「用法契约」）。
// ★ 与「网络设置」页「请求读超时」（prefNetReadTimeoutMin，分钟级 5/10/20）刻意分链：
// 那条管等模型回复（ChatStreamBase 起流读），本条管等网页/接口响应——两组常量互不干涉，
// 两键零共享（AppPreferences 同键注释互指）。
export const SEARCH_TIMEOUT_SECONDS_DEFAULT: number = 20;
export const SEARCH_TIMEOUT_SECONDS_MIN: number = 5;
export const SEARCH_TIMEOUT_SECONDS_MAX: number = 60;

// 存储值 → 生效秒数（UI 展示与执行侧计时共用的唯一换算点）：<= 0（脏数据）与非有限数
// （NaN/Infinity）= 默认 20（= 旧写死常量 SEARCH_TIMEOUT_MS 20000 同值，未配置与存量行为
// 零回归）；非整数四舍五入；结果收口到 5~60——上界防脏数据把失败等待拉长，下界保证换算回
// 毫秒后恒 > 0（失败文案「请求超时（N 秒）」不会出现 0 秒）
export function resolveSearchTimeoutSeconds(stored: number): number {
  if (!Number.isFinite(stored) || stored <= 0) {
    return SEARCH_TIMEOUT_SECONDS_DEFAULT;
  }
  return Math.min(Math.max(Math.round(stored), SEARCH_TIMEOUT_SECONDS_MIN),
    SEARCH_TIMEOUT_SECONDS_MAX);
}
