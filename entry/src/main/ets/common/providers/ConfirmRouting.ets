// 确认链三档归一叶子（2026-09-28 口径收紧笔新立）：预检原始命中 → 按「设置 → 工具调用」
// 三档配置裁决豁免与去向的共用单点，禁各预检实现各写一份。消费方 = ToolBrowseAct /
// ToolHttp 与数据管理族预检（笔 B 起）。
// ★ 为何不能并入既有件（反碎片下限②申报）：ToolContracts 被防环纪律钉守「叶子唯一
// import 源 = MessageContracts」（assert-app-domain 85 组，I10 红线）——归一要引档位常量
// （AppPreferences）即破纪律；AppPreferences 是持久域章程件（键常量 + 缺省值 + 读值封装，
// 零 import 叶子）——放确认链行为规则越其职责。本件两侧各引（契约类型 + 档位常量），
// 自身零被引面回边（只有预检实现引它），下游叶子不成环。
// ★ 2026-11-11 域名确认档退役笔（决明拍板）：原第三参 perDomain 与两条域名判序整批删除——
// 按域名的确认例外（恒问 / 恒不问）与会话权限三档同属「问不问」一根轴，留着即第二根轴。
// 写确认此后只由会话权限模式决定；判序自四条收回三条（高效放行 → auto 豁免写档 → 人工/审批）。
import { ConfirmPrompt, CONFIRM_LEVEL_WRITE, CONFIRM_ROUTE_HUMAN,
  CONFIRM_ROUTE_MODEL } from './ToolContracts';
import { APPROVE_MODE_ASK, APPROVE_MODE_AUTO } from '../AppPreferences';
import { resolveConfirmMode } from '../chat/PermissionMode';

// 归一裁决（2026-11-09 会话权限模式笔前置一层；同日三档归一笔记改判序）：先把会话权限模式
// 映射到旧域档（迁移态 = 原样沿用调用方传入的域档；谨慎 → ask、标准 → model、高效 → null
// 放行）。判序 = **高效档最优先**（决明 2026-11-09 拍板「完全权限时不设限」：写档与不可逆档
// 一律执行）→ 「一律放行」只豁免写操作档（**不可逆档仍进确认链恒问人**，2026-09-28 口径
// 收紧笔，与「本会话内允许不给不可逆档用」同源）→「每次确认」直指人工卡（不过审批模型）→
// 其余交审批闸。返回 null = 本档豁免（高效档全部组合 / 写档 + 一律放行 两种）。
// ★ mode 由调用方在预检时点一次读取传入（豁免判据、档位比较与 route 同源同值——分次读会在
// 两次读之间被用户切档时产生错配，虽窗口极小但属可避免的自相矛盾）；会话模式由本件现读，
// 消费的是同一时点的全局态，不新增第二根轴。
export function routeConfirmPrompt(prompt: ConfirmPrompt, mode: string): ConfirmPrompt | null {
  // 会话权限模式归一（2026-11-09 真完全权限笔）：迁移态 = 原样沿用调用方传入的域档，
  // 老用户零行为变化；用户切档后由单一会话模式统管三域。null = 高效档放行。
  // ★ 本函数体内唯一自由名 = resolveConfirmMode，断言直跑副本由注入区同形桩承接
  //  （桩恒回传入值 = 迁移态），既有 107/129 行为直跑钉零改判。
  const modeNow: string | null = resolveConfirmMode(mode);
  // 判序 1：高效档最优先——写档与不可逆档一律执行（决明 2026-11-09 拍板「完全权限时不设限」）。
  //   地板只剩密码恒禁（预检早退）与系统权限弹窗，二者本就不属于「问用户」的范畴。
  if (modeNow === null) {
    return null;
  }
  // 判序 2：全局「一律放行」只豁免写操作档——不可逆档（删除族）仍进确认链恒问人
  //   （2026-09-28 口径收紧笔）。
  if (modeNow === APPROVE_MODE_AUTO && prompt.level === CONFIRM_LEVEL_WRITE) {
    return null;
  }
  // 判序 3：「每次确认」直指人工卡（不过审批模型），其余交审批闸
  return { text: prompt.text, level: prompt.level,
    route: modeNow === APPROVE_MODE_ASK ? CONFIRM_ROUTE_HUMAN : CONFIRM_ROUTE_MODEL,
    detail: prompt.detail, domain: prompt.domain };
}
