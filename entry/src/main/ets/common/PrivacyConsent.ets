// 首启隐私政策同意与政策 URL 单源。
// 官方依据（本地 devdocs 直连官方门户实查）：
// · AGC 审核 FAQ「AGC审核驳回：在同意隐私政策前，应用获取了用户的个人信息」
//   （faqs-appgallery-33）原文：「应用首次运行时需通过弹窗向用户申请授权展示隐私政策，
//   用户同意隐私政策前应用不应该有任何调用权限 API 的行为」——本件配套的
//   PrivacyConsentGate 即该弹窗。
// · 未同意处置口径 = faqs-appgallery-50「方式二：用户选择不同意隐私政策，应用退出」——
//   用户拒绝后 terminateSelf 终止实例 + module.json5 abilities 的
//   removeMissionAfterTerminate 清除任务快照；同篇「若用户首次未同意隐私政策，不允许通过
//   多次弹窗强制用户操作」——本弹窗同一会话内不重复弹（同意即写键，拒绝即退出）。
// ★ AGC 侧配套（上架前必核，决明操作面）：版本信息 → 隐私声明须选「自定义隐私政策」。
//   若同时在 AGC 开启隐私托管，首次安装会触发两个隐私弹窗（faqs-appgallery-84）——
//   系统托管一个 + 本弹窗一个，本弹窗即重复来源。二选一取自定义（政策正文由本仓三副本
//   维护，换版无需在 AGC 政策编辑器重录）。
// ★ 存量用户不弹（升级零骚扰）：判定 = 预置服务商 seed 标记已落 '1'
//   （PROVIDER_PRESETS_SEEDED_KEY——凡装过旧版的设备必然为 '1'，删过预置卡也不回填改
//   标记）；新装设备该键为空串 → 首次启动弹窗。判定单点 =
//   EntryAbility 持久键注册尾部（migratePrivacyConsentForExistingUsers），只跑一次幂等。
// ★ 隐私政策 URL 单源迁此：现址 jueming-aicontrol.top（HTTPS 自动续期，境内可达）；原
//   GitHub Pages 地址指向境外托管，且 AGC 审核政策把「隐私政策链接为博客、微博、GitHub 和
//   云笔记」列为潜在拒因——换址顺带消解该风险（旧 GitHub 链接保留可访问，不回落）。应用内
//   政策页底部链接与首启弹窗「查看隐私政策全文」两处同引本常量（禁各写一份）。
// 本件零 import 叶子（模块环红线，坑50）：只持键常量、URL 与读写封装，不碰 UI
// （AppStorage 为 ArkUI 全局声明，无需 import——ProactiveConfig / BusyOverlay 同款）。

// 已同意隐私政策（boolean 持久键，缺省 false = 未同意）。写点 = PrivacyConsentGate 同意键
// 与存量迁移判定两处；读点 = PrivacyConsentGate @StorageProp 订阅（写即弹窗消失）。
// 随偏好备份走与否：**不随备份**（换机恢复后应重新征得同意——同意是设备侧法律状态，
// 与「恢复用户偏好」不同性质；登记在备份排除表）。
export const PREF_PRIVACY_AGREED_KEY: string = 'prefPrivacyAgreed';

// 隐私政策在线地址（单源：应用内政策页底部链接 + 首启弹窗「查看隐私政策全文」同引）
export const PRIVACY_POLICY_URL: string = 'https://jueming-aicontrol.top/privacy.html';

// 存量用户迁移判定的历史键**由宿主传值**（本件零 import 叶子，不引 ProviderPresetSeed；
// 键名与读值单源 = 调用方 EntryAbility 引其 PROVIDER_PRESETS_SEEDED_KEY 常量——
// ★ 首版本文曾在此手写字面量且写错（'prefProviderPresetsSeeded' ≠ 实际
// 'provider_presets_seeded'），若留着会让存量迁移永不触发、全量老用户升级即弹窗；
// 改传参后键名不可能再分叉）

// 是否已同意（读封装：键未注册时按未同意处理——合规面宁严不宽）
export function isPrivacyAgreed(): boolean {
  return AppStorage.get<boolean>(PREF_PRIVACY_AGREED_KEY) === true;
}

// 写同意（单写点封装；写后 @StorageProp 订阅方自刷）
export function markPrivacyAgreed(): void {
  AppStorage.setOrCreate<boolean>(PREF_PRIVACY_AGREED_KEY, true);
}

// 存量用户迁移判定（EntryAbility 持久键注册尾部调用一次，幂等）：
// 未同意 且 预置服务商 seed 标记为 '1' → 视为已同意并补写本键（老用户升级不弹窗）。
// seededMark 由宿主传入（单源见上方注释）；时机约束同上——必须在两键 persistProp 之后
//（磁盘值已进 AppStorage）、页面组件实例化之前。
// 新装设备：seed 标记此刻仍是 ''（seed 链异步尚未完成）→ 不补写 → 首启弹窗。✓
export function migratePrivacyConsentForExistingUsers(seededMark: string): void {
  if (isPrivacyAgreed()) {
    return;
  }
  if (seededMark === '1') {
    markPrivacyAgreed();
  }
}
