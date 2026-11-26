// 一级页签列表首查预热件（决明拍板「B 三读并行 + A 启动预热」）：助手页/对话页两份列表首查
// 的冷启动预热快照——EntryAbility 启动链（loadContent 成功回调，persistProp 水合后、组件
// 实例化前）发起，页面首建一次性消费（首帧一次成型），消费后进程内不再供给。治 TabContent
// 懒加载首切「组件新建 + 列表数据异步查回」两段式渲染的「闪一下再出现」；助手页原三段落屏
//（卡片先出现、模型名与会话计数各再触发一次全卡纪元重建）一并收敛为一次落屏；对话页冷启动
// 窗口亦缩短。
// ★ 规范偏离申报（规范-数据存储获取刷新方案 §2「无中间缓存层」）：本件是一次性短命快照——
// 无写路径回流、不承接后续刷新、消费即弃、只活在冷启动窗口；页面所有 reload 刷新链照旧直查
// DB，单一真源口径不变（快照是首帧一次成型的最小时序机制，非内存副本缓存层）。
// ★ 2026-11-18 侧栏首帧笔：在上述一次性预热快照之外，本件额外保留**最近一次成功取回**的
// 会话快照（lastSessionSnap，单份、旧值直接覆盖）——侧栏二级页每次 push 都是新实例，首帧可
// 同步取用该快照上屏（stale-while-revalidate：消费方仍须立即 reload 校准，真值以本次查询为
// 准），治「新页挂载 → 查库回包前列表空白」。它同样不是刷新链缓存层：无写路径、不承接续刷、
// 不做失效广播，只服务首帧；同属 §2 偏离。另加助手快照只读种子口（peekAssistantSnapshotForSeed，
// 不消费）——侧栏标题行的当前助手名首帧直显用，名字真值仍由行侧 queryAssistant 复核。
// ★ 空快照丢弃（首启 seed 竞态防御）：启动 seed（幂等插入）与预热查询异步并行——seed 落库前
// 生成的 0 行快照一律当 miss 丢弃（防首启停在「暂无助手」空态无 reload 修正）；真空列表同走
// 现查，无额外代价。
// ★ 一致性窗口与新鲜度戳：快照生成到首建消费间无本页 UI 写点，但**跨页广播写源存在**——
// 对话页签是启动首屏（先于助手页建），其会话增删/移动/主动消息/备份恢复等写点自增
// SESSION_LIST_RELOAD_KEY，广播时助手页未建（@StorageProp 初始赋值不触发 @Watch）= 错过无
// 自愈 → 助手快照 counts 停在采集时刻。助手快照随带采集时刻 tick（reloadTick），两消费点
// 统一经 assistantSnapshotStale 判新鲜，停旧即当 miss 转现查。对话快照无此面（首建与预热
// 几乎同刻，且其 reload 在途闩 + pending 尾部补跑自愈），不设戳。Web 服务写库为冻结面极端
// 竞态（2026-10-23 冻结口径），接受不设失效。
// ★ 消费纪律：peekXxx 只在页面 aboutToAppear 调（首建专用——运行期 reload 喂启动时刻快照
// 反而停旧态）；awaitXxx 的快照交付至多一次（take 语义），交付后恒现查；助手域两路交付前
// 均过新鲜度门。
// 模块定位：组合根性质数据件（import ChatDb / AssistantDb / SessionSnippet /
// ModelDisplayLabel 四叶子，仅被 EntryAbility 与两页签组件消费——无环，坑50 红线）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConversationRow, queryConversations, whenReady } from './ChatDb';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, AssistantRow,
  historyFilterIds, queryAssistants, queryAssistantConversationCounts
} from './AssistantDb';
import { queryConversationSnippets } from '../chat/SessionSnippet';
import { ModelDisplayLabel, resolveModelDisplayLabel } from './ModelDisplayLabel';
import { SESSION_LIST_RELOAD_KEY } from '../AppBroadcastKeys';

// 助手页一次成型快照：三读（列表 / 模型显示名 / 会话计数）全回后的产物，页面单次纪元落屏
export interface AssistantListSnapshot {
  rows: AssistantRow[];
  // assistantId → 模型显示名（未绑定行不进表；解析自兜底不失败——单源 resolveModelDisplayLabel）
  labels: Map<string, string>;
  // assistantId 原始分桶 → 会话行数（卡面「会话」项数据源）
  counts: Map<string, number>;
  // false = 计数读取失败（counts 为空 Map，卡面「会话」项不出——缺数不谎报 0）
  countsOk: boolean;
  // 计数软失败文案（'' = 成功；页面落报告行用，fetch 侧拼好）
  countsError: string;
  // 新鲜度戳（assistantSnapshotStale 消费判据）：采集时刻的会话广播 tick——跨页写源在
  // 采集后自增过即停旧（见文件头「一致性窗口与新鲜度戳」）
  reloadTick: number;
}

// 对话页一次成型快照：DB 原始行 + 摘要。行合成（运行时 loading 标记 / 草稿打标 / '__new__'
// 合成行）刻意留在页面消费时刻做——loading 与草稿取「取时刻」运行态，预合成会停在启动时刻
export interface SessionListSnapshot {
  // 查询时刻的助手过滤键（页面行合成的合成参数——与行数据同一过滤口径）
  activeId: string;
  queried: ConversationRow[];
  snippets: Map<string, string>;
}

// 助手快照新鲜度判定：counts 的跨页写源 = 会话增删/移动/恢复/主动消息落库
//（SESSION_LIST_RELOAD_KEY 全部写点），这些广播可发生在助手页首建前（懒加载页签，
// @StorageProp 初始赋值不触发 @Watch → 错过无自愈）——采集时刻 tick 与当前 tick 不等即停旧，
// 消费侧当 miss 转现查。peek（页面侧）与 await（件内）两消费点统一走本判据
export function assistantSnapshotStale(snap: AssistantListSnapshot): boolean {
  return snap.reloadTick !== (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0);
}

// 模型显示名批量解析（自 AssistantPage 迁入，页面与预热共用单源）：绑行逐行走单源
// resolveModelDisplayLabel——助手行数量级小且为本地库查询，判据单源优先于批量微优化
//（缺失/失败两路都兜底裸 modelId，展示链不 reject 不阻断主链）。未绑定行跳过。
async function resolveAssistantModelLabels(rows: AssistantRow[]): Promise<Map<string, string>> {
  const labels: Map<string, string> = new Map();
  for (const row of rows) {
    if (row.providerId === '' || row.modelId === '') {
      continue;
    }
    try {
      const resolved: ModelDisplayLabel =
        await resolveModelDisplayLabel(row.providerId, row.modelId);
      labels.set(row.id, resolved.label !== '' ? resolved.label : row.modelId);
    } catch (e) {
      labels.set(row.id, row.modelId);
    }
  }
  return labels;
}

// 助手页读取链单源（页面 reload 直查与预热共用）：whenReady 就绪守卫 + 三读并行——列表与
// 计数同时发起、标签解析挂列表回执后（输入是 rows），总耗时 ≈ max(列表+标签, 计数)。
// 失败语义与改造前逐字同：列表失败 = 整体 reject（页面报告行）；计数失败 = 软失败进快照
//（chip 缺位 + countsError 文案，不拦列表落屏）；标签链自兜底永不 reject
export async function fetchAssistantListSnapshot(): Promise<AssistantListSnapshot> {
  const ok: boolean = await whenReady();
  if (!ok) {
    throw new Error('数据库初始化失败，请重启应用重试');
  }
  const listFetch: Promise<AssistantRow[]> = queryAssistants();
  const countsFetch: Promise<Map<string, number>> = queryAssistantConversationCounts();
  // 新鲜度戳采集（与两查询同刻：tick 晚于此刻自增 = counts 可能停旧，消费侧转现查）
  const reloadTick: number = AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0;
  let rows: AssistantRow[];
  try {
    rows = await listFetch;
  } catch (e) {
    throw new Error('助手列表读取失败：' + (e as Error).message);
  }
  const labels: Map<string, string> = await resolveAssistantModelLabels(rows);
  const snapshot: AssistantListSnapshot = {
    rows: rows,
    labels: labels,
    counts: new Map<string, number>(),
    countsOk: false,
    countsError: '',
    reloadTick: reloadTick
  };
  try {
    snapshot.counts = await countsFetch;
    snapshot.countsOk = true;
  } catch (e) {
    snapshot.countsError = '会话数读取失败：' + (e as Error).message;
  }
  return snapshot;
}

// 对话页读取链单源（同族）：whenReady 就绪守卫 + 两读并行（列表 + 摘要；摘要失败软兜空 Map
// 不阻断列表——页面现行口径）。助手过滤现读 ACTIVE_ASSISTANT_KEY（缺省 = 默认助手），
// '' 存量行归默认口径在 historyFilterIds；摘要查询同用该过滤集（2026-11-16 收窄：不再全库
// 聚合，成本随当前助手会话数而非历史消息总量）
export async function fetchSessionListSnapshot(): Promise<SessionListSnapshot> {
  const ok: boolean = await whenReady();
  if (!ok) {
    throw new Error('数据库初始化失败，请重启应用重试');
  }
  const activeId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  const filterIds: string[] = historyFilterIds(activeId);
  const rowsFetch: Promise<ConversationRow[]> = queryConversations(filterIds);
  const snippetsFetch: Promise<Map<string, string>> =
    queryConversationSnippets(filterIds).catch((): Map<string, string> => new Map<string, string>());
  let queried: ConversationRow[];
  try {
    queried = await rowsFetch;
  } catch (e) {
    throw new Error('会话列表读取失败：' + (e as Error).message);
  }
  const snapshot: SessionListSnapshot = {
    activeId: activeId,
    queried: queried,
    snippets: await snippetsFetch
  };
  return snapshot;
}

// 预热单例：两域各三态（在途回调落地即清 promise，快照交付即清 snap——同域同时至多一份
// 有效供给；进程内快照各至多消费一次）
class HomeListWarmup {
  private assistantPromise: Promise<AssistantListSnapshot> | null = null;
  private assistantSnap: AssistantListSnapshot | null = null;
  private sessionPromise: Promise<SessionListSnapshot> | null = null;
  private sessionSnap: SessionListSnapshot | null = null;
  // 最近一次成功取回的会话快照（★ 2026-11-18 侧栏首帧笔，见文件头）：与 sessionSnap 的
  // 一次性预热不同，本值不被消费——侧栏二级页每次新 push 都可在首帧同步取用（消费方随即
  // 仍须 reload 校准）。单份有界、失败不覆盖（上一份好数据继续兜底首帧）。
  private lastSessionSnap: SessionListSnapshot | null = null;

  // 启动链发起（EntryAbility loadContent 成功回调调用一次）。fire-and-forget：失败置空态
  // 留日志，页面消费时自动落现查兜底（错误面由页面链承接，不算静默）；幂等——重复调用不
  // 双发。字段存 fetch 原始 promise（await 消费方共享同一条查询），快照落库副作用独立挂
  //（先于消费方回调注册 = 先执行，消费 take 时快照必已就位）
  warm(): void {
    if (this.assistantSnap === null && this.assistantPromise === null) {
      const fetch: Promise<AssistantListSnapshot> = fetchAssistantListSnapshot();
      this.assistantPromise = fetch;
      fetch.then((snap: AssistantListSnapshot): void => {
        // 0 行丢弃（首启 seed 竞态，见文件头）——快照非空才存
        this.assistantSnap = snap.rows.length > 0 ? snap : null;
        this.assistantPromise = null;
      }).catch((e: Object): void => {
        this.assistantSnap = null;
        this.assistantPromise = null;
        hilog.info(0xD5A1, 'HomeListWarmup', '助手页预热失败（页面消费时现查兜底）：%{public}s',
          (e as Error).message);
      });
    }
    if (this.sessionSnap === null && this.sessionPromise === null) {
      const fetch: Promise<SessionListSnapshot> = this.fetchAndRememberSession();
      this.sessionPromise = fetch;
      fetch.then((snap: SessionListSnapshot): void => {
        this.sessionSnap = snap.queried.length > 0 ? snap : null;
        this.sessionPromise = null;
      }).catch((e: Object): void => {
        this.sessionSnap = null;
        this.sessionPromise = null;
        hilog.info(0xD5A1, 'HomeListWarmup', '对话页预热失败（页面消费时现查兜底）：%{public}s',
          (e as Error).message);
      });
    }
  }

  // 首建同步取用（aboutToAppear 专用，见文件头消费纪律）：已完成未消费且非空 → 取出并
  // 消费（置 null）；否则 null（调用方转 reload 异步路径）
  peekAssistantSnapshot(): AssistantListSnapshot | null {
    const snap: AssistantListSnapshot | null = this.assistantSnap;
    this.assistantSnap = null;
    return snap;
  }

  peekSessionSnapshot(): SessionListSnapshot | null {
    const snap: SessionListSnapshot | null = this.sessionSnap;
    this.sessionSnap = null;
    return snap;
  }

  // 最近一次成功会话快照（只读、不消费）——侧栏页首帧种子专用（见文件头侧栏首帧笔）：
  // 消费方必须仍走 reload 校准；快照携带 activeId，过滤助手不一致时由消费方自行丢弃。
  peekLastSessionSnapshot(): SessionListSnapshot | null {
    return this.lastSessionSnap;
  }

  // 助手快照只读种子口（不消费）——侧栏标题行当前助手名首帧直显用；AssistantPage 消费
  // 预热快照后本口自然回 null，调用方回落异步查询。名字真值仍由行侧 queryAssistant 复核。
  peekAssistantSnapshotForSeed(): AssistantListSnapshot | null {
    return this.assistantSnap;
  }

  // 现查并记录最近一次成功快照（首帧种子单源）：成功即覆盖 lastSessionSnap；失败不覆盖
  //（上一份好数据继续供下次首帧兜底）。会话预热与 await 现查两路共用。
  private fetchAndRememberSession(): Promise<SessionListSnapshot> {
    return fetchSessionListSnapshot().then((snap: SessionListSnapshot): SessionListSnapshot => {
      this.lastSessionSnap = snap;
      return snap;
    });
  }

  // 首建异步路径（peek miss 后 reload 调）：预热在途 → 等它，回执经 take 判非空且新鲜
  // 交付（空 / 失败 / 已交付 / 停旧〔采集后有过会话广播——预热窗口内 reload 拿到的快照
  // 同样是采集时刻值〕→ 现查一次）；无预热 / 已消费 → 直接现查。快照交付至多一次（take 语义）
  awaitAssistantSnapshot(): Promise<AssistantListSnapshot> {
    const inflight: Promise<AssistantListSnapshot> | null = this.assistantPromise;
    if (inflight === null) {
      return fetchAssistantListSnapshot();
    }
    return inflight.then((): Promise<AssistantListSnapshot> => {
      const taken: AssistantListSnapshot | null = this.peekAssistantSnapshot();
      return taken !== null && !assistantSnapshotStale(taken) ?
        Promise.resolve(taken) : fetchAssistantListSnapshot();
    }, (): Promise<AssistantListSnapshot> => fetchAssistantListSnapshot());
  }

  awaitSessionSnapshot(): Promise<SessionListSnapshot> {
    const inflight: Promise<SessionListSnapshot> | null = this.sessionPromise;
    if (inflight === null) {
      return this.fetchAndRememberSession();
    }
    return inflight.then((): Promise<SessionListSnapshot> => {
      const taken: SessionListSnapshot | null = this.peekSessionSnapshot();
      if (taken !== null) {
        // 预热快照交付同样进首帧种子位（下一次新页可用）
        this.lastSessionSnap = taken;
        return Promise.resolve(taken);
      }
      return this.fetchAndRememberSession();
    }, (): Promise<SessionListSnapshot> => this.fetchAndRememberSession());
  }
}

export const homeListWarmup: HomeListWarmup = new HomeListWarmup();
