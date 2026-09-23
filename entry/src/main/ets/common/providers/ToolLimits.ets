// 工具调用轮数上限值域（2026-09-09 上限可设置笔；零依赖叶子模块）：assistants.toolStepLimit
// 列（DB v22）的存储值语义 + 「存储值 → 生效上限」唯一换算点。
// 值域（存储值）：0 = 不限制 / 1~TOOL_STEP_LIMIT_MAX(32) = 该助手单次发送内工具调用轮数
// 上限；默认 TOOL_STEP_LIMIT_DEFAULT(32) = 旧全局常量 MAX_TOOL_STEPS 同值，未配置助手与
// 存量助手行为逐字节零回归。
// ★ 0 不是真无限（决明 2026-09-09 拍板「0 = 不限 + 内置硬顶 256」）：模型工具死循环会无限
// 续轮扣费，故 0 档由 TOOL_STEP_HARD_CAP(256，对齐 CubeAgent/RikkaHub 公开值) 兜底；到顶
// 仍走 A2 让位轮 + 触顶 notice（ChatSendCtrl.onStreamDone），与显式设值路径同形。
// ★ 为何独立成文件而不并入 ToolTypes：存储层 AssistantDb 需引用默认值，而 ToolTypes 经
// ToolFunctional → ProviderDb 反向依赖 AssistantDb（链上再引即循环依赖，本项目明令禁）；
// 叶子模块零 import，存储层/发送链/UI 三方共用同一份常量与换算，禁各处自写一套。
export const TOOL_STEP_LIMIT_DEFAULT: number = 32;
export const TOOL_STEP_LIMIT_MAX: number = 32;
export const TOOL_STEP_HARD_CAP: number = 256;

// 存储值 → 生效上限（发送链与 UI 展示共用的唯一换算点）：0 及负值（脏数据）= 硬顶；
// 1~MAX = 原值；超 MAX（脏数据）= MAX 收口
export function resolveToolStepLimit(stored: number): number {
  if (stored <= 0) {
    return TOOL_STEP_HARD_CAP;
  }
  return Math.min(Math.round(stored), TOOL_STEP_LIMIT_MAX);
}
