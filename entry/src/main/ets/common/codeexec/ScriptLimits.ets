// 代码工作台执行档位数值映射。
// · 单源纪律：**全工程档位数值唯一来源**——标准 / 严格两档的时限、堆上限、输出预算只在
//   本文件出现，ToolCodeExec 组装 ScriptRunOptions 时经 scriptTierValues 消费；desc 与
//   帮助文案引用定性表述（「合计约 8 KB」），禁在 C++ / 其他 .ets 散落字面值。
// · 本件兼**执行模式值域单源**（模型侧 exec_code 的 mode 参数：SCRIPT_MODE_JS /
//   SCRIPT_MODE_SHELL）；shell（模拟 Shell）恒取严格档数值组——复用映射、档位数值面零
//   新常量，映射分支即此实现。
// · import 面：只引 AppPreferences 两枚档位常量（零 @kit——供断言直跑；引 @kit 会把
//   UI 框架带进 Node 直跑面）。
// · 为何不并入 ScriptEngine.ets：破其叶子零 import 纪律（它要引 AppPreferences）；为何
//   不并入 ToolCodeExec.ets：纯数值域与执行器混居（反碎片下限②）。
// · 档位数值为代决默认值（可翻）：标准 10s / 64MB·young 16MB / 合计 8KB；严格 5s /
//   32MB·young 8MB / 合计 4KB（时限与内存各减半）。
import { CODE_WORKBENCH_MODE_STRICT } from '../AppPreferences';

// 执行模式值域（模型侧 exec_code 的 mode 参数；与用户档位正交——档位是用户面偏好，
// 执行模式是模型侧逐调用选择；shell = 模拟 Shell（应用内置受限命令解释器））
export const SCRIPT_MODE_JS: string = 'js';
export const SCRIPT_MODE_SHELL: string = 'shell';

// 档位生效数值组（ScriptRunOptions 的档位相关字段集合。新生代不落第二份数值——native
// 侧由 maxOldGenerationSize / 4 派生〔jsvm_runner.cpp 注释钉住派生关系〕）
export interface ScriptTierValues {
  timeoutMs: number;
  maxHeapBytes: number;
  maxOutputChars: number;
}

// 标准档数值（缺省档）：限时 10 秒 / 老生代堆 64MB〔新生代 native 派生 = /4〕/ 输出与日志
// 合计 8KB（8KB 与通用截断器硬顶 8192 同量级——自预算铁律要求回执恒 < 8192，8192 是含信封
// 余量的上界而非配额）
const TIER_STANDARD: ScriptTierValues = {
  timeoutMs: 10 * 1000,
  maxHeapBytes: 64 * 1024 * 1024,
  maxOutputChars: 8192
};

// 严格档数值：限时 5 秒 / 老生代堆 32MB〔新生代 native 派生 = /4〕/ 输出与日志合计 4KB（各减半）
const TIER_STRICT: ScriptTierValues = {
  timeoutMs: 5 * 1000,
  maxHeapBytes: 32 * 1024 * 1024,
  maxOutputChars: 4096
};

// 映射（唯一入口）：形参接收「档位值（standard / strict）」或「执行模式键（shell）」——
// shell 恒取严格档数值组（关系注释：shell 数值组 === 严格档数值组，断言以关系守、禁抄值）；
// 其余值域外一律回标准档（脏值兜底与 AppPreferences 缺省同向）
export function scriptTierValues(mode: string): ScriptTierValues {
  return mode === CODE_WORKBENCH_MODE_STRICT || mode === SCRIPT_MODE_SHELL
    ? TIER_STRICT : TIER_STANDARD;
}

// ── timeout 逐调用钳制（易用面：长脚本常用不满档，模型值得为「快速失败换重试」主动设
//    更短等待；安全侧不破——只缩不扩，档位仍是用户面唯一上界）──
// timeout 参数下限（秒）——越下钳制并在回执附说明句（说明句文案在 ScriptReceipt）
export const SCRIPT_TIMEOUT_MIN_SECONDS: number = 1;

// timeout 解析结果（生效毫秒 + 两个钳制旗标——说明句由装配层据旗标拼）
export interface ScriptTimeoutResolution {
  timeoutMs: number;
  clampedLow: boolean;
  clampedHigh: boolean;
}

// timeout 参数解析（唯一入口）：毫秒 = round(秒×1000)；落在 [下限, 档位时限] 内原样；
// 越下钳下限（**负数与 -Infinity 同归此路**——负值不得反拿更长等待）；越上钳档位时限
// （只缩不扩——档位是用户面安全设置，模型不得绕过）；+Infinity（经 JSON 1e999 可达）
// 与 NaN（不可达防御）归上限钳。判定序 = 先下限后上限（该序保证 -Infinity 落下限路）。
export function resolveScriptTimeoutMs(requestedSeconds: number,
  tierLimitMs: number): ScriptTimeoutResolution {
  let ms: number = Math.round(requestedSeconds * 1000);
  if (ms < SCRIPT_TIMEOUT_MIN_SECONDS * 1000) {
    return { timeoutMs: SCRIPT_TIMEOUT_MIN_SECONDS * 1000, clampedLow: true, clampedHigh: false };
  }
  if (!(ms <= tierLimitMs)) {
    return { timeoutMs: tierLimitMs, clampedLow: false, clampedHigh: true };
  }
  return { timeoutMs: ms, clampedLow: false, clampedHigh: false };
}
