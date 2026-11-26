// 工具页卡显示态判定域（2026-10-07 工具面封顶笔自 ToolTypes.ets 域级最小拆分；★ 2026-10-25
// 控制台合并笔：控制台封顶过滤与独占卡隐藏整段随控制台助手退役删除——isConsoleAssistant
// 形参链同笔收口，本域回归「模式驱动过滤 + 联网从属压制」两判据）。域定义一句话：工具页
// 功能卡的三件显示态判定——可见卡 / 卡内可开件分母 / 整卡开关——工具页卡开关与助手编辑页
// 卡面摘要、助手列表 chip、会话移动面板摘要共用的「卡口径统一」单源（2026-09-18 卡口径
// 统一笔定义）。
// 依赖方向（坑50）：本件 → ToolTypes 单向（toolGroups + 政策判据两函数）——ToolTypes 不引
// 本件，无环；类型 ToolEntry 自叶子 ToolContracts 引（新码契约自叶子纪律），ToolGroup 归口
// ToolTypes（组视图条目类型，与 toolGroups() 同源）。
import { ToolEntry } from './ToolContracts';
import { ToolGroup, isModeDriven,
  isWebDomainTool, registerBuiltinTools, toolGroups } from './ToolTypes';
import { TOOL_SEARCH_WEB } from './ToolIds';

// ── 工具卡显示态（★ 2026-09-18 卡口径统一：工具页卡开关与助手编辑页卡面摘要**同源**）──
// 背景：工具页分类卡重组后用户可见入口 = 一组卡（一卡一枚开关），而助手编辑页「工具
// 调用」卡面摘要曾按底层逐件 id 计数（'联网开 · 12 项启用'）——两处口径不一：用户点进去只
// 看到几个开关，摘要却报十几个。故摘要改报「已开卡数 / 卡总数」，本段即「卡是否已开」的
// **唯一判定源**（AssistantToolsPage 卡开关显示态 +
// AssistantEditPage 卡面摘要同调此处，禁各自另写一套——规范 §4.2 放行逻辑单源）。语义与
// 页面显示逐条对齐：
// ① 可见卡 = 组轴按 TOOL_GROUP_ORDER，模式驱动件（isModeDriven）成员与卡两级同滤、卡内
//    滤空则整卡不出现（★ 2026-10-25 控制台合并笔：原「独占卡对非控制台整卡不出 + 控制台
//    视图剔白名单外件」两过滤随控制台助手退役删除——应用管理卡对全部助手照常出现）；
// ② 卡内**可开件**（分母）= 剔除联网压制件（从属一件 = scrape_web 在「清单不含联网搜索」
//    时不可用——浏览三件 2026-09-27 出域独立成卡不再受闸；★ 2026-10-01 总开关退役后压制
//    降为助手清单单维）后的成员；
// ③ 卡开关显示态 = 可开件非空且**全开**；④ 卡面摘要计数 = 可见卡中已开张数。

// 工具页可见卡（模式驱动件过滤——卡视图唯一入口；原 AssistantToolsPage
// .loadVisibleGroups 上迁 ToolTypes〔2026-09-18〕、2026-10-07 封顶笔随卡显示态域迁本件，
// 工具页与两处计数共用）
export function visibleToolGroups(): ToolGroup[] {
  registerBuiltinTools();
  const visible: ToolGroup[] = [];
  for (const group of toolGroups()) {
    const members: ToolEntry[] = group.members.filter((m: ToolEntry): boolean =>
      !isModeDriven(m.name));
    if (members.length === 0) {
      continue;
    }
    visible.push({ title: group.title, members: members });
  }
  return visible;
}

// 联网域从属件压制判定（纯函数形：候选集合入参——页面显示态与摘要计数同用）：
// 联网域从属件（isWebDomainTool 且非 search_web 本体）在「候选集合不含联网搜索」时整体
// 不可用；search_web 是域主件，不做自压制（判据单源 = 本函数，页面 isToolSuppressed 只补
// 默认形参）。★ 2026-10-01 总开关退役笔：原 webServiceEnabled 形参随键退役——全局恒开后
// 压制判据降为单维（候选集合是否含联网搜索）
export function isToolSuppressedInList(name: string, candidateIds: string[]): boolean {
  if (!isWebDomainTool(name) || name === TOOL_SEARCH_WEB) {
    return false;
  }
  return !candidateIds.includes(TOOL_SEARCH_WEB);
}

// 逐件可开（压制单因——卡内可开件与摘要计数共同判据；★ 2026-10-06 控制面层级化笔：原
// 「代码工作台总开关」因随键退役；★ 2026-10-25 控制台合并笔：原「console-exclusive 反向
// 拦截 + 控制台封顶」两因随控制台助手退役删除）
function isToolEnablable(name: string, candidateIds: string[]): boolean {
  return !isToolSuppressedInList(name, candidateIds);
}

// 卡内可开件（卡开关显示态的分母；求值一律传「候选集合」——卡批量开时传批后
// 目标集合，压制判定依赖候选集合是否含联网搜索）
export function enablableToolMembers(group: ToolGroup, candidateIds: string[]): ToolEntry[] {
  return group.members.filter((m: ToolEntry): boolean =>
    isToolEnablable(m.name, candidateIds));
}

// 卡开关显示态 = 可开件非空且全开（可开件 0 = 恒关）
export function toolGroupAllOn(group: ToolGroup, candidateIds: string[]): boolean {
  const enablable: ToolEntry[] = enablableToolMembers(group, candidateIds);
  return enablable.length > 0 && enablable.every((m: ToolEntry): boolean =>
    candidateIds.includes(m.name));
}
