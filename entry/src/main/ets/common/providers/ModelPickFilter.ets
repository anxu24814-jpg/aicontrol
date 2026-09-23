// 模型选择面板检索/空态/组键纯函数域（2026-09-08 模型选择半模态优化，任务书-模型选择半模态
// 优化-20260908 §2.1；2026-09-09 补 modelGroupKey）：搜索框关键词归一 + 模型行匹配判定 +
// 空态文案选取 + 外层分组键拼装——零 import 约束（scripts/sse-assert.mjs 复制本文件为 .ts
// 直跑，MemoryText/WebSearchParse/RequestInject 同款范式；IO 与 UI 在 ModelPickerSheet，
// 不在本域）。
// 为何不并入 ProviderDb：断言脚本对「零 import 文件」可直接复制直跑，ProviderDb 带 5 组
// import（AiTypes/ChatDb/KeyStore/ProviderKeyDb/AssistantDb），剥桩脆弱且随其演进失效
//（2026-09-08 实锤的「import 耦合扇出」坑）。
// 匹配口径：关键词命中 = 模型显示名 / 模型 ID / 服务商名三字段任一包含（小写归一后子串，
// 三字段均再归一一次防调用侧漏归）；能力标签不参与匹配（展示属性，非检索维度）。

// 关键词归一（搜索框每次按键调用）：去首尾空白 + 小写；'' = 不过滤（恒显全部）
export function normalizeModelFilterKeyword(raw: string): string {
  return raw.trim().toLowerCase();
}

// 模型行是否命中（keyword 须先经 normalizeModelFilterKeyword 归一；'' = 恒命中）
export function modelMatchesFilter(name: string, modelId: string, providerName: string,
  keyword: string): boolean {
  if (keyword === '') {
    return true;
  }
  return name.toLowerCase().includes(keyword) ||
    modelId.toLowerCase().includes(keyword) ||
    providerName.toLowerCase().includes(keyword);
}

// 空态提示文案选取（'' = 不显提示）。优先级自上而下，逐条短路：
// ①无任何可用模型（库内无启用服务商模型）②有可见行（正常态）③关键词无命中
// ④收藏段内无收藏（引导去收藏）⑤其余不显
export function pickEmptyHint(sourceCount: number, visibleCount: number, keyword: string,
  favOnly: boolean): string {
  if (sourceCount === 0) {
    return '暂无可用模型。请到「设置 > 服务商管理」添加服务商并获取模型';
  }
  if (visibleCount > 0) {
    return '';
  }
  if (keyword !== '') {
    return '没有匹配的模型';
  }
  if (favOnly) {
    return '还没有收藏的模型。点模型行右侧的爱心即可收藏';
  }
  return '';
}

// 外层分组 ForEach 键（组卡重建判据）= providerId | 使用中 | 纪元 | 可见行集合签名。
// ★ 可见集必须进键（2026-09-09 决明真机报障根因）：ForEach 非首次渲染时**键不变即复用旧
// 组件**（item 生成函数不重跑，官方语义 + 坑16 家族）——原键只含 providerId/使用中/纪元，
// 切「收藏」分段或输关键词只换数组不换键，组卡沿用旧快照 → 收藏段把整个服务商的组卡连
// 未收藏行一起显示。可见集变 → 键变 → 组卡按过滤后的行重建；可见集不变 → 键同 → 不白重建
// （纪元仍承担「可见集不变但行内态变」的刷新，如全部段收藏点亮心形）。
export function modelGroupKey(providerId: string, providerInUse: boolean, listEpoch: number,
  visibleModelIds: string[]): string {
  return providerId + '|' + (providerInUse ? '1' : '0') + '|' + listEpoch + '|' +
    visibleModelIds.join(',');
}
