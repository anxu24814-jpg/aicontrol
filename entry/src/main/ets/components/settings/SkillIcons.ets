// 技能图标资源映射域（2026-09-13 技能层笔 1 新建）：skills.icon 列存的是 sys.symbol **名字
// 字符串**（纯 UI 字段、不进模型面——SkillText.SKILL_ICON_CANDIDATES 是候选集单源），
// 上屏时须把名字还原成官方符号资源。
// ★ 为何用显式映射而不是 `$r('sys.symbol.' + name)` 动态拼名：全工程零处动态 `$r`（资源
// 名恒字面量）——本文件延续该形态（ArkTS 静态资源引用以字面量为准，动态拼名不在已验证
// 用法内）。代价 = 候选集增删时本映射必须同改，故 scripts/assert-app-domain.mjs 钉
// 「候选集 ↔ 本映射逐项覆盖」（漏一个即红），不靠人记。
// 消费方三处：技能库页行卡 / 技能编辑页图标选择网格 / 助手技能页开关行。

// 图标名 → 官方符号资源（候选集 12 项；未登记（含空串与脏值）→ 默认图标灯型 wand_and_stars，
// 与建表 SQL 的 DEFAULT 同值——兜底不抛不空渲染）
export function skillIconResource(icon: string): Resource {
  if (icon === 'wand_and_stars') {
    return $r('sys.symbol.wand_and_stars');
  }
  if (icon === 'lightbulb') {
    return $r('sys.symbol.lightbulb');
  }
  if (icon === 'book') {
    return $r('sys.symbol.book');
  }
  if (icon === 'doc_text') {
    return $r('sys.symbol.doc_text');
  }
  if (icon === 'text_alignleft') {
    return $r('sys.symbol.text_alignleft');
  }
  if (icon === 'list_bullet') {
    return $r('sys.symbol.list_bullet');
  }
  if (icon === 'square_grid_2x2') {
    return $r('sys.symbol.square_grid_2x2');
  }
  if (icon === 'person') {
    return $r('sys.symbol.person');
  }
  if (icon === 'clock') {
    return $r('sys.symbol.clock');
  }
  if (icon === 'gearshape') {
    return $r('sys.symbol.gearshape');
  }
  if (icon === 'star') {
    return $r('sys.symbol.star');
  }
  if (icon === 'checkmark_circle') {
    return $r('sys.symbol.checkmark_circle');
  }
  return $r('sys.symbol.wand_and_stars');
}
