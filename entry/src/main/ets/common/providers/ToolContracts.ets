// 工具执行器契约（叶子模块——零 import，2026-09-13 真机启动闪退修复笔新建）。
// ★ 为什么单独成文件：ToolTypes.ets 是工具域的**聚合根**（它 import 全部工具域实现，用于
//   内置注册），而各工具域（ToolPref / ToolProvider / ...）与 MemoryGen 又要用 ToolExecutor
//   这个接口——原来从 ToolTypes.ets 引，等于「域 ← 聚合根」反向边，与聚合根→域的正向边构成
//   环（ToolTypes → ToolPref → MemoryGen → ToolTypes 等十二条）。接口本身是类型擦除的，环
//   单靠接口引用无害；**但只要环内任一模块在模块作用域读/调用对方的绑定，就会踩未初始化
//   绑定**（2026-09-13 工具补齐三件笔实锤：ToolPref 顶层白名单数组调 PROACTIVE_INTERVAL_OPTIONS
//   .map() —— 真机启动即 JsError 闪退，进程活不过 onCreate；AssertionD 见
//   scripts/assert-app-domain.mjs「域文件禁引 ToolTypes」负向钉）。
// ★ 纪律：本文件**永不 import 任何东西**（叶子）；一切工具域与 MemoryGen 等反向引用方一律
//   `from './ToolContracts'`（MemoryGen 为 `'./providers/ToolContracts'`），**禁**从 ToolTypes
//   引 ToolExecutor——引一次就把环接回来一次。
// 契约本身：入参 = 模型给出的 arguments JSON 串；返回 = 结果文本（进请求回传与卡片展示）。
// 抛错 = 执行失败（调用侧转 error JSON，不炸链路）。
export interface ToolExecutor {
  execute(argsJson: string): Promise<string>;
}

// ── 确认链预检契约（2026-09-20 审批卡视觉迁移笔 A；★ 落本叶子而非聚合根的理由 = 环红线：
//    两个预检实现（ToolBrowseAct / ToolHttp 域件）都要消费本类型与档位常量，落 ToolTypes
//    等于让域件反向引聚合根——正是 ToolExecutor 当年踩过的环（本文件头注释），且触
//    assert-app-domain 85 组负向钉。任务书原写「放 ToolTypes.ets，与 ToolEntry 同域」，
//    本笔按项目环纪律改落叶子并申报（详见 docs/变更记录.md 本笔条目）。──
// 预检返回二元组：text = 卡面主因句；level = 档位（CONFIRM_LEVEL_WRITE / _IRREVERSIBLE），
// 供卡面档位徽章与（笔 C 起）会话级允许判据读取。返回 null = 无需确认（语义与旧「空串」一致）。
export interface ConfirmPrompt {
  text: string;
  level: string;
}

// 确认档位：写操作档（browse_act 非删除族动作 / http_request 写方法）
export const CONFIRM_LEVEL_WRITE: string = 'write';
// 确认档位：不可逆档（browse_act 命中删除族词表——卡面出红徽章与风险块）
export const CONFIRM_LEVEL_IRREVERSIBLE: string = 'irreversible';
