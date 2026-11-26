// 服务商图谱（2026-08-30 立项：Service 模板与协议-URL 匹配检查的单一来源）：
// · CATALOG_PRESETS = 「套用模板」数据源（本文件唯一出口——ProviderConfigPanel 不再自持
//   常量；条目为五元组 {displayName, shortName, baseUrl, protocol, endpoint}——原「四元组」
//   计数与列举不符，2026-09-13 全码优化笔1 核正；点模板 = 整组权威回填，消除「模板基址与
//   协议不一致」的半套状态）；
// · ★ 2026-10-18 合规整改（公安备案问询境外模型接入；台账 = docs/上架流程清单.md 同日
//   第二条）：**两清单只收录境内服务商**——原境外 5 家 6 条模板（OpenAI / Anthropic /
//   Gemini 原生 / Gemini OpenAI 兼容 / OpenRouter / OpenCode Zen）与 5 条预置整条移除；
//   三协议能力与自定义地址不设限（用户自填任意兼容端点照旧可用）。存量设备上旧版本已
//   seed 进库的内置境外行由下方退役清单 + ProviderPresetRetire 启动清理（见
//   RETIRED_OVERSEAS_ORIGINS）。恢复收录前先过合规拍板，勿凭「补齐主流家」直觉加回。
// · BASE 值均来自各服务商官方文档查证（非猜测）：
//   - DeepSeek 官方 API 文档明示「兼容 OpenAI/Anthropic 双格式」：OpenAI = /v1（SDK 惯例），
//     Anthropic 兼容端点根 = https://api.deepseek.com/anthropic（客户端拼 /v1/messages）；
//   - 月之暗面/智谱/硅基流动 = OpenAI 兼容单格式（Anthropic 端点是否提供未查证——不收录，
//     用户可自定义）。
//   - 2026-08-31 扩容（领导拍板主流服务商全覆盖；联网官方文档查证）：
//     火山方舟（豆包）= https://ark.cn-beijing.volces.com/api/v3（docs.volcengine.com 对话
//     API，OpenAI SDK 直用）；阿里云百炼（通义）= https://dashscope.aliyuncs.com/
//     compatible-mode/v1（help.aliyun.com OpenAI 兼容指南）；MiniMax 国内 = https://
//     api.minimaxi.com/v1（platform.minimax.io OpenAI SDK 指南；★域名 minimaxi 多一个 i，
//     与 Key 归属站强绑定，国际站为 api.minimax.io/v1 不收录）。
// · describeMismatch = 保存前协议-URL 匹配检查（高置信规则的启发式判断；level='block' =
//   明确矛盾请拦截（跨家端点串接），level='warn' = 高风险但可能是高级用户有意（如中转
//   站新支持 Responses），提示不拦截；'' = 无警告）。
import {
  ENDPOINT_CHAT, ENDPOINT_RESPONSES, PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI, PROTOCOL_OPENAI
} from './AiTypes';

// 图谱模板条目（五元组 + 展示名；displayName = 「DeepSeek（OpenAI）」类——同一服务商多协议
// 条目各自展示；shortName = 空名补名用（服务商名，不带协议后缀））
export interface CatalogPreset {
  displayName: string;
  shortName: string;
  baseUrl: string;
  protocol: string;
  endpoint: string;
}

export const CATALOG_PRESETS: CatalogPreset[] = [
  { displayName: 'DeepSeek（OpenAI）', shortName: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT },
  { displayName: 'DeepSeek（Anthropic）', shortName: 'DeepSeek', baseUrl: 'https://api.deepseek.com/anthropic', protocol: PROTOCOL_ANTHROPIC, endpoint: ENDPOINT_CHAT },
  { displayName: '月之暗面 Kimi', shortName: '月之暗面', baseUrl: 'https://api.moonshot.cn/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT },
  { displayName: '智谱 GLM', shortName: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT },
  { displayName: '硅基流动', shortName: '硅基流动', baseUrl: 'https://api.siliconflow.cn/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT },
  { displayName: '火山方舟（豆包）', shortName: '火山方舟', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT },
  { displayName: '阿里云百炼（通义）', shortName: '阿里云百炼', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT },
  { displayName: 'MiniMax（国内）', shortName: 'MiniMax', baseUrl: 'https://api.minimaxi.com/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT }
];

// 预置卡条目（2026-08-31 二期：首启 seed 进 providers 表的清单单源；唯一消费方 =
// ProviderPresetSeed.ets）。结构与 CATALOG_PRESETS 同构 + enabled 初值；baseUrl/protocol/
// endpoint 照上方对应模板条目原值复制（多协议家只收录一条主条目——拍板：DeepSeek 用
// OpenAI 条，其余多协议需求走模板选择 / 自建）。displayName 字段预置场景无消费方（seed
// 落库用 shortName 作服务商名），保留 = 与 CatalogPreset 同构、便于逐条人工对照上方查证
// 出处。启用组三家 = 领导 2026-08-31 指定，其余四家默认停用（停用 = 插入时 enabled 传
// false 随行落库）。★ 2026-10-18 合规整改：境外五条预置随模板清单一并移除，本清单只含
// 境内 7 家。
export interface ProviderPreset extends CatalogPreset {
  enabled: boolean;
}

export const PROVIDER_PRESETS: ProviderPreset[] = [
  // ── 启用组（enabled=1）──
  { displayName: 'DeepSeek（OpenAI）', shortName: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: true },
  { displayName: '月之暗面 Kimi', shortName: '月之暗面', baseUrl: 'https://api.moonshot.cn/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: true },
  { displayName: '智谱 GLM', shortName: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: true },
  // ── 停用组（enabled=0）──
  { displayName: '火山方舟（豆包）', shortName: '火山方舟', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: false },
  { displayName: '阿里云百炼（通义）', shortName: '阿里云百炼', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: false },
  { displayName: '硅基流动', shortName: '硅基流动', baseUrl: 'https://api.siliconflow.cn/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: false },
  { displayName: 'MiniMax（国内）', shortName: 'MiniMax', baseUrl: 'https://api.minimaxi.com/v1', protocol: PROTOCOL_OPENAI, endpoint: ENDPOINT_CHAT, enabled: false }
];

// 已退役的境外内置家（2026-10-18 合规整改①）：只服务「存量内置行清理」一个用途——旧版本
// 首启 seed 已把这几家落进用户库且标 builtin=1，数据层禁删，用户无法自行移除；退役执行器
// （common/store/ProviderPresetRetire.ets）按本清单的**域名**认行（URL 是家的客观标识，
// 改名不改域），逐行连密钥 / 模型 / 绑定级联删除。★ 与上方两清单分隔：本条不参与模板展示
// 与 seed，勿把域名单混回 CATALOG_PRESETS / PROVIDER_PRESETS。
export const RETIRED_OVERSEAS_ORIGINS: string[] = [
  'https://api.openai.com',
  'https://api.anthropic.com',
  'https://generativelanguage.googleapis.com',
  'https://openrouter.ai',
  'https://opencode.ai'
];

// 命中判定（精确域或域内路径；scheme 锚定 + 域边界非子串——同 AiTypes 官方域判定的伪装域
// 防线：api.openai.com.evil.com 与 xx-api.openai.com.proxy.xx 都不命中）
export function isRetiredOverseasOrigin(baseUrl: string): boolean {
  const url: string = baseUrl.trim().toLowerCase();
  return RETIRED_OVERSEAS_ORIGINS.some((origin: string): boolean =>
    url === origin || url.startsWith(origin + '/'));
}

// 家识别头像资源（2026-08-31 领导指令续：ds/km/glm 服务商卡换对应品牌 logo——DeepSeek
// 鲸鱼 / Kimi K / 智谱 Z.ai 几何 Z，其余厂商与用户新建统一默认头像）：按 baseUrl 域名
// 识别家（URL 是家的客观标识，用户改名不改域、预置/模板/手建同判据；中转/自定义 URL
// 不命中 = 统一头像）；'' = 走统一头像（消费方 ProviderHeadCard 圆底 + 通用符号）。
// ★ 返回值 = 品牌 logo 资源名，消费方依 app.media.<资源名> 取图（三家家源见 media/ 与
// dark/media/：deepseek_logo.png 深浅通用、kimi_logo.svg 与 zai_logo.svg 深色反白）；
// 消费方按资源名分支写死 $r 字面量——$r 不支持动态拼接资源名（项目先例踩坑）。
export function providerAvatarAsset(baseUrl: string): string {
  const url: string = baseUrl.toLowerCase();
  if (url.includes('api.deepseek.com')) {
    return 'deepseek_logo';
  }
  if (url.includes('api.moonshot.cn')) {
    return 'kimi_logo';
  }
  if (url.includes('open.bigmodel.cn')) {
    return 'zai_logo';
  }
  return '';
}

// 内置家开放平台控制台（2026-10-29 卡片菜单「打开官网」笔）：菜单目标一律 = 各家「申请 API Key
// 的那一页」，即开放平台控制台，不是品牌首页（决明 2026-10-29 拍板「控制台即可」）。条目与
// PROVIDER_PRESETS 七家一一对应（assert-app-domain 304 组守一一对应，增减家须同改）。
// domain = 命中判据（baseUrl 子串），与 providerAvatarAsset 同一「URL 是家的客观标识」口径
// ——用户改名不改域，故不按名称判家。
export interface ProviderOfficialSite {
  domain: string;
  siteUrl: string;
}

export const PROVIDER_OFFICIAL_SITES: ProviderOfficialSite[] = [
  { domain: 'api.deepseek.com', siteUrl: 'https://platform.deepseek.com' },
  { domain: 'api.moonshot.cn', siteUrl: 'https://platform.moonshot.cn' },
  { domain: 'open.bigmodel.cn', siteUrl: 'https://open.bigmodel.cn' },
  { domain: 'ark.cn-beijing.volces.com', siteUrl: 'https://console.volcengine.com/ark' },
  { domain: 'dashscope.aliyuncs.com', siteUrl: 'https://bailian.console.aliyun.com' },
  { domain: 'api.siliconflow.cn', siteUrl: 'https://cloud.siliconflow.cn' },
  { domain: 'api.minimaxi.com', siteUrl: 'https://platform.minimaxi.com' }
];

// 官网地址查询：'' = 未收录。★ fail-safe 护栏——内置行的 Base URL 用户可在详情页改写，
// 改成中转站后域名不再代表这家，此时返回空串、调用方据此隐藏入口：宁可不给入口，也不把人
// 送到别的服务商站点。判定方式沿用上方 providerAvatarAsset 的子串匹配，不另立一套解析。
export function providerOfficialSite(baseUrl: string): string {
  const url: string = baseUrl.trim().toLowerCase();
  const hit: ProviderOfficialSite | undefined = PROVIDER_OFFICIAL_SITES.find(
    (site: ProviderOfficialSite): boolean => url.includes(site.domain));
  return hit !== undefined ? hit.siteUrl : '';
}

// 匹配检查结果：level '' = 无警告 / 'block'（明确矛盾，调用方应拦截保存）/ 'warn'
// （高风险但可能是有意配置，提示不拦截）
export interface MismatchHint {
  level: string;
  message: string;
}

// 家内协议端点映射（2026-08-31 换协议联动 Base URL——配置页协议分段切档时调用）：
// 当前 baseUrl 精确命中图谱某条目 → 取其 shortName 归「家」，找**同家**目标协议条目，
// 返回其 baseUrl；两步任一落空（自定义/中转 URL 未命中、单协议家无目标协议条目）返回 ''。
// ★ 只做家内跟随、不做跨家猜测：openai 协议在图谱对应多家不同 base，无唯一目标值；
// 自定义 URL 一律不碰（用户输入优先）。当前图谱内有多协议条目的家 = DeepSeek
//（o↔a 双端点）一组，联动即双向对称可逆（2026-10-18 合规整改后 Gemini 双条目已移除，
// 原生↔OpenAI 兼容联动随之失效——用户自填 Gemini 地址时不再自动换端点）。
export function familyProtocolUrl(currentBaseUrl: string, targetProtocol: string): string {
  const home: CatalogPreset | undefined = CATALOG_PRESETS.find(
    (preset: CatalogPreset): boolean => preset.baseUrl === currentBaseUrl);
  if (home === undefined) {
    return '';
  }
  const target: CatalogPreset | undefined = CATALOG_PRESETS.find(
    (preset: CatalogPreset): boolean =>
      preset.shortName === home.shortName && preset.protocol === targetProtocol);
  return target !== undefined ? target.baseUrl : '';
}

const NO_MISMATCH: MismatchHint = { level: '', message: '' };

export function describeMismatch(protocol: string, endpoint: string, baseUrl: string): MismatchHint {
  const url: string = baseUrl.toLowerCase();
  // ① 跨家端点串接（明确矛盾）：Anthropic 协议配 OpenAI/Google 域名；Gemini 原生配
  // Anthropic/OpenAI 域名——官方端点互不兼容，属 100% 配置错误
  if (protocol === PROTOCOL_ANTHROPIC &&
    (url.includes('api.openai.com') || url.includes('googleapis.com'))) {
    return {
      level: 'block',
      message: 'Base URL 与 Anthropic 协议不匹配。Anthropic 端点应为 https://api.anthropic.com 或服务商兼容端点，例如 https://api.deepseek.com/anthropic'
    };
  }
  if (protocol === PROTOCOL_GEMINI &&
    (url.includes('api.anthropic.com') || url.includes('api.openai.com'))) {
    return {
      level: 'block',
      message: 'Base URL 与 Gemini 原生协议不匹配。原生端点应为 https://generativelanguage.googleapis.com。OpenAI 兼容端点请改选「OpenAI 兼容」协议，例如 https://generativelanguage.googleapis.com/v1beta/openai'
    };
  }
  // ② Responses 形态仅 OpenAI 官方端点有把握支持（第三方兼容中转普遍不实现
  // /v1/responses）——高置信但非绝对（个别中转新支持），提示不拦截
  if (protocol === PROTOCOL_OPENAI && endpoint === ENDPOINT_RESPONSES &&
    !url.includes('api.openai.com')) {
    return {
      level: 'warn',
      message: '注意：Responses 接口目前仅 OpenAI 官方端点 api.openai.com 有支持保障，第三方兼容服务普遍不实现 /v1/responses'
    };
  }
  return NO_MISMATCH;
}
