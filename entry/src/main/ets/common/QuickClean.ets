// 快速清理域：清理项清单 / 现状读数 / 逐项清除编排 / 全清聚合 / 确认文案五类全在本文件，
// 零 UI——页面（components/settings/QuickCleanPage.ets）只消费本文件的类型与函数
//（StorageStats ↔ StoragePage 同款分工）。
// 独立成件理由（反碎片下限②）：不能并入 StorageStats（彼件是缓存级安全清理、承诺「不影
// 响消息与登录态」，本件是数据库与配置级全清，承诺与失败面都不同），也不能并入六个 store
// 域件（本件是跨域编排层，六项分属会话/记忆/用量/浏览器/模型/背景六域，并入即反向依赖）。
// 六项取舍（决明指令「仅限已有功能」）：竞品「清空工作区文件」「清除语音输出配置」本工程
// 无对应域不做，不为其造功能；本文件只做编排不写 SQL（各域件 SQL 单源，整表清空函数在各自域件）。
// ★ 破坏性红线（本域存在理由——六项全部不可撤销）：①现状读数先行，确认弹窗必须带数量
// 或占用；②计数为 0 的项不可点（quickCleanAvailable 纯函数——浏览器数据一项例外，判据见
// 该函数注释）；③「清除全部数据」是前六项聚合执行，不再逐项二次确认（用户已确认过范围），
// 但逐项失败不中断、结果逐项回报（best-effort，P0-1 不静默）。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clearAllConversations, sharedRdbStore } from './store/ChatDb';
import { clearAllMemories } from './store/MemoryDb';
import { clearUsageEvents } from './store/UsageStatsDb';
import { clearAllProviders } from './store/ProviderDb';
import { PROVIDER_PRESETS_SEEDED_KEY, seedProviderPresets } from './store/ProviderPresetSeed';
import { resetPageBackground } from './ImageEditUtil';
import { CleanResult, cleanWebData, formatBytes, scanWebDataBytes } from './StorageStats';

const DOMAIN: number = 0xDACC;
const TAG: string = 'QuickClean';

// ── 清理项 key（清单单源；页面、执行分派、确认文案三处同引，禁裸字符串）──
export const QUICK_CLEAN_CONV: string = 'conv';
export const QUICK_CLEAN_MEMORY: string = 'memory';
export const QUICK_CLEAN_USAGE: string = 'usage';
export const QUICK_CLEAN_WEB: string = 'web';
export const QUICK_CLEAN_MODEL: string = 'model';
export const QUICK_CLEAN_BG: string = 'bg';
export const QUICK_CLEAN_ALL: string = 'all';

// 清理项（ArkTS 禁匿名对象字面量数组，走类型化返回方法；序 = 页面卡序 = 全清聚合执行序，
// 三处同源，勿在页面另写顺序表）
export interface QuickCleanItem {
  key: string;
  title: string;
  desc: string;
}

export function quickCleanItems(): QuickCleanItem[] {
  return [
    {
      key: QUICK_CLEAN_CONV,
      title: '清除对话记录',
      desc: '删除本机保存的全部会话、消息、上下文摘要与其中的附件文件。不影响模型配置与记忆。'
    },
    {
      key: QUICK_CLEAN_MEMORY,
      title: '清空长期记忆',
      desc: '清空全局记忆库与各助手记忆库的全部条目，并删除记忆历史里的存档。不影响对话记录。'
    },
    {
      key: QUICK_CLEAN_USAGE,
      title: '清除用量统计',
      desc: '删除本机记录的模型调用 token 统计与据此折算的费用数据。对话内容不受影响。'
    },
    {
      key: QUICK_CLEAN_WEB,
      title: '清除浏览器数据',
      desc: '清除内置浏览器保存的 Cookie、网页数据与缓存。清除后各网站的登录状态会失效，需要重新登录。'
    },
    {
      key: QUICK_CLEAN_MODEL,
      title: '清除模型配置',
      desc: '删除全部服务商、模型、API Key 与价格模板。清除后回到首次安装时的预置服务商列表，密钥需要重新填写。'
    },
    {
      key: QUICK_CLEAN_BG,
      title: '恢复默认背景',
      desc: '恢复默认背景，并删除本机保存的背景图副本。'
    },
    {
      key: QUICK_CLEAN_ALL,
      title: '清除全部数据',
      desc: '依次执行以上全部六项，一次性清空本机数据。'
    }
  ];
}

// 单项元数据（执行与确认文案按 key 反查；key 非法即抛——静默返回空项会让页面渲出空标题）
export function quickCleanItemOf(key: string): QuickCleanItem {
  const hit: QuickCleanItem | undefined =
    quickCleanItems().find((item: QuickCleanItem): boolean => item.key === key);
  if (hit === undefined) {
    throw new Error('未知的清理项：' + key);
  }
  return hit;
}

// ── 现状读数（确认弹窗与可点判据共用，进页一次读）──
export interface QuickCleanOverview {
  conversations: number;
  messages: number;
  memories: number; // 全局库 + 全部助手库合计
  snapshots: number; // 记忆历史存档份数（清空记忆时一并删除）
  usageEvents: number;
  providers: number;
  webBytes: number; // 浏览器数据占用（非条数，显示与清除同域见 StorageStats.cleanWebData）
  bgOn: boolean; // 当前是否设了自定义背景
}

// COUNT 单值读出（本文件唯一的 SQL 形态：零列投影只引表名不引列名——表结构演进不影响本
// 读数；ResultSet 用完 close 为红线；读不到行按 0 计 = 空表即目标状态）
async function countOf(db: relationalStore.RdbStore, sql: string): Promise<number> {
  const rs: relationalStore.ResultSet = await db.querySql(sql);
  try {
    return rs.goToNextRow() ? rs.getLong(rs.getColumnIndex('c')) : 0;
  } finally {
    rs.close();
  }
}

// 现状读数（进页一次调用，非轮询无缓存层）。★ COUNT 直查而不逐域加计数函数：为纯展示
// 读数在各域件铺计数函数零复用价值，且 COUNT(*) 不引列名与表结构演进解耦；写侧 SQL 一律
// 归各域件（本文件不写任何 DML）
export async function readQuickCleanOverview(ctx: common.Context): Promise<QuickCleanOverview> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const conversations: number = await countOf(db, 'SELECT COUNT(*) AS c FROM conversations');
  const messages: number = await countOf(db, 'SELECT COUNT(*) AS c FROM messages');
  const memories: number = await countOf(db, 'SELECT COUNT(*) AS c FROM memories') +
    await countOf(db, 'SELECT COUNT(*) AS c FROM assistant_memories');
  const snapshots: number = await countOf(db, 'SELECT COUNT(*) AS c FROM memory_snapshots');
  const usageEvents: number = await countOf(db, 'SELECT COUNT(*) AS c FROM token_usage_events');
  // 服务商计数只数非内置：clearAllProviders 跳过内置预置行，预览口径与实删口径必须一致
  //（P0-1——预览含内置而实删不含 = 误导性确认）。本条是 countOf 零列投影纪律的唯一例外
  //（引 builtin 列名）：过滤语义由该列承载，无第二写法
  const providers: number =
    await countOf(db, 'SELECT COUNT(*) AS c FROM providers WHERE builtin = 0');
  return {
    conversations: conversations,
    messages: messages,
    memories: memories,
    snapshots: snapshots,
    usageEvents: usageEvents,
    providers: providers,
    webBytes: scanWebDataBytes(ctx),
    bgOn: (AppStorage.get<string>('pageBg') ?? '') !== ''
  };
}

// 该项当前是否有内容可清（纯函数可断言）：false = 页面键置灰不响应（空清毫无意义却要弹
// 一次确认）。
// ★ 五项计数类（会话/记忆/用量/服务商/背景）判据 = COUNT 或偏好键现值：COUNT 失败会抛错
// → 整页失败态可重试，不存在「查不到按 0 计」形态，照常按读数判灰。
// ★★ 浏览器数据**不按读数判灰**：scanWebDataBytes 为纯同步扫描，目录缺失/不可读一律返回
// 0 且永不抛出——「本机无浏览器数据」与「扫描读不到」不可区分，拿它置灰会让本项成为唯一
// 入口却恒灰、用户永远清不了。改判后空清代价 = 确认框如实报「当前占用 0 B」+ 三官方 API
// 空跑（幂等无副作用），远小于「够不着」。
export function quickCleanAvailable(key: string, ov: QuickCleanOverview): boolean {
  if (key === QUICK_CLEAN_CONV) {
    return ov.conversations > 0;
  }
  if (key === QUICK_CLEAN_MEMORY) {
    return ov.memories > 0 || ov.snapshots > 0;
  }
  if (key === QUICK_CLEAN_USAGE) {
    return ov.usageEvents > 0;
  }
  if (key === QUICK_CLEAN_WEB) {
    return true;
  }
  if (key === QUICK_CLEAN_MODEL) {
    return ov.providers > 0;
  }
  if (key === QUICK_CLEAN_BG) {
    return ov.bgOn;
  }
  // 「清除全部数据」：任一有内容可清即可点（全空时整页无事可做）。★ 本支逐字段展开而非
  // 递归调各单项：单项 web 恒 true，递归会令聚合项恒亮、空态也提供一键全清；本支的
  // webBytes 判据失败面无害（扫描读不到时聚合项置灰，单项仍可点，不产生「够不着」坏态）。
  return ov.conversations > 0 || ov.memories > 0 || ov.snapshots > 0 || ov.usageEvents > 0 ||
    ov.webBytes > 0 || ov.providers > 0 || ov.bgOn;
}

// ── 确认弹窗文案（单源纯函数——页面不得自拼，免两处漂移；断言直跑）──
// 「清除全部数据」逐项列名（序同 quickCleanItems 的非聚合项）；项数由调用点取清单长度算
// （勿字面写死——两条文案同源同序，加项不会漏报）
function allItemNames(): string {
  const names: string[] = [];
  for (const item of quickCleanItems()) {
    if (item.key !== QUICK_CLEAN_ALL) {
      names.push(item.title);
    }
  }
  return names.join('、');
}

// 临时区级联提示句（conv 与 all 两支共用——2026-11-15 批量确认笔提取为常量：批量弹窗正文
// 也要按同句提示，第三处硬写必漂移，P2-4「重复 2 次以上必须提取」）。语义 = 清会话会连带
// 清工作区临时文件
export const TMP_CASCADE_HINT: string = '清除对话记录会同时清除全部临时文件。';
// 确认正文（面向用户文案写作规约：无冒号分号括号连环）。conv 与 all 两支的临时区级联句为
// 条件句——判定在调用方（QuickCleanPage 现读 listWorkspaceTmpGroups 非空），本函数第三参
// tmpPresent 承接：true 才加句，false 零提示。缺省 true 兼容断言直跑面，产品调用点恒显式
// 传实况
export function quickCleanConfirmMessage(key: string, ov: QuickCleanOverview,
  tmpPresent: boolean = true): string {
  if (key === QUICK_CLEAN_CONV) {
    return '将删除本机全部 ' + ov.conversations + ' 个会话与 ' + ov.messages +
      ' 条消息，含其中的附件文件与上下文摘要。删除后无法恢复。' +
      (tmpPresent ? TMP_CASCADE_HINT : '');
  }
  if (key === QUICK_CLEAN_MEMORY) {
    return '将清空全部 ' + ov.memories + ' 条长期记忆，全局库与助手库一并清空，记忆历史里的 ' +
      ov.snapshots + ' 份存档也会删除。删除后无法恢复。';
  }
  if (key === QUICK_CLEAN_USAGE) {
    return '将删除本机记录的 ' + ov.usageEvents +
      ' 条模型调用用量，用量统计页与费用估计页的数字随之归零。对话内容不受影响，删除后无法恢复。';
  }
  if (key === QUICK_CLEAN_WEB) {
    return '将清除内置浏览器的 Cookie、网页数据与缓存，当前占用 ' + formatBytes(ov.webBytes) +
      '。清除后各网站的登录状态会失效，需要重新登录。';
  }
  if (key === QUICK_CLEAN_MODEL) {
    return '将删除本机全部 ' + ov.providers +
      ' 个服务商及其模型、API Key 与价格模板，助手与会话上的模型绑定同时清空。清除后回到首次安装时的预置服务商列表，密钥需要重新填写。';
  }
  if (key === QUICK_CLEAN_BG) {
    return '将恢复默认背景，并删除本机保存的背景图副本。删除后无法恢复。';
  }
  if (key === QUICK_CLEAN_ALL) {
    // 项数取清单动态值（勿写字面数字，加项时字面量会说谎）；末句临时区级联提示条件显
    //（同 conv 支，判定在调用方传实况）
    return '将依次执行 ' + allItemNames() + ' 共 ' + (quickCleanItems().length - 1) + ' 项，合计 ' +
      ov.conversations + ' 个会话与 ' + ov.messages + ' 条消息、' + ov.memories + ' 条长期记忆、' +
      ov.usageEvents + ' 条用量记录、' + ov.providers + ' 个服务商与全部浏览器数据将被删除，且无法恢复。' +
      (tmpPresent ? TMP_CASCADE_HINT : '');
  }
  throw new Error('未知的清理项：' + key);
}

// ── 执行（逐项一份结果；「清除全部数据」返回六份）──
export interface QuickCleanOutcome {
  key: string;
  title: string;
  ok: boolean;
  message: string; // 成功 = 结果描述；失败 = 失败原因（P0-1 不静默，逐项如实回报）
}

// 单项执行（分派到各域件；任一步抛错即转失败结果，不中断聚合链——见 executeQuickClean）
async function runItem(key: string, ctx: common.Context): Promise<QuickCleanOutcome> {
  const item: QuickCleanItem = quickCleanItemOf(key);
  try {
    if (key === QUICK_CLEAN_CONV) {
      const removed: number = await clearAllConversations();
      return outcome(item, true, '已清除 ' + removed + ' 个会话');
    }
    if (key === QUICK_CLEAN_MEMORY) {
      await clearAllMemories();
      return outcome(item, true, '已清空长期记忆');
    }
    if (key === QUICK_CLEAN_USAGE) {
      await clearUsageEvents();
      return outcome(item, true, '已清除用量统计');
    }
    if (key === QUICK_CLEAN_WEB) {
      const res: CleanResult = cleanWebData();
      return res.failed > 0 ? outcome(item, false, res.failed + ' 项未清除，请重试') :
        outcome(item, true, '已清除浏览器数据');
    }
    if (key === QUICK_CLEAN_MODEL) {
      const removed: number = await clearAllProviders();
      // 预置回填（本工程特有：首启预置 7 家境内服务商卡，标记 '1' 后永不重跑）——清空后
      // 不重置标记，用户会停在「零服务商且永不复现预置」坏态。先清标记再 seed（seed 读完
      // 标记即写 '1'，顺序不可倒）。★ 跨域编排归本件：ProviderDb 不得 import
      // ProviderPresetSeed（后者反向 import 前者，添边即成模块环，坑50 零环红线）
      AppStorage.setOrCreate<string>(PROVIDER_PRESETS_SEEDED_KEY, '');
      await seedProviderPresets();
      return outcome(item, true, '已清除 ' + removed + ' 个服务商，预置服务商列表已恢复');
    }
    if (key === QUICK_CLEAN_BG) {
      const removed: number = resetPageBackground(ctx.filesDir);
      return outcome(item, true, removed > 0 ? '已恢复默认背景，删除 ' + removed + ' 个背景文件' :
        '已恢复默认背景');
    }
    throw new Error('未知的清理项：' + key);
  } catch (e) {
    const err: Error = e as Error;
    hilog.error(DOMAIN, TAG, '清理项执行失败 key=%{public}s：%{public}s', key, err.message);
    return outcome(item, false, err.message);
  }
}

function outcome(item: QuickCleanItem, ok: boolean, message: string): QuickCleanOutcome {
  return { key: item.key, title: item.title, ok: ok, message: message };
}

// 执行入口（页面唯一调用点）：单项 = 一份结果；「清除全部数据」= 前六项按清单序依次执行，
// 逐项结果各回一份。★ 单项失败不中断后续项（best-effort——已成功项不回滚，最后逐项回报
// 失败者；中断会让「全清」变半成品且用户不知做到哪步）。调用方须保证 DB 就绪（isReady
// 守卫在页面）
export async function executeQuickClean(key: string, ctx: common.Context): Promise<QuickCleanOutcome[]> {
  if (key !== QUICK_CLEAN_ALL) {
    return [await runItem(key, ctx)];
  }
  const results: QuickCleanOutcome[] = [];
  for (const item of quickCleanItems()) {
    if (item.key === QUICK_CLEAN_ALL) {
      continue;
    }
    results.push(await runItem(item.key, ctx));
  }
  return results;
}

// 结果汇总文案（页面 toast 单源）：全成功 = 「已完成 N 项清理」；有失败 = 逐项报失败项
// 标题，不静默也不谎报成功。空数组按无动作处理（页面不会传空，防御性返回空串）
export function quickCleanSummaryText(results: QuickCleanOutcome[]): string {
  if (results.length === 0) {
    return '';
  }
  const failed: QuickCleanOutcome[] =
    results.filter((r: QuickCleanOutcome): boolean => !r.ok);
  if (failed.length === 0) {
    return results.length === 1 ? results[0].message : '已完成 ' + results.length + ' 项清理';
  }
  const names: string[] = [];
  for (const r of failed) {
    names.push(r.title);
  }
  return failed.length + ' 项未完成。' + names.join('、') + '。可重试';
}
