// 服务商编辑页（2026-08-30 服务商管理域新建，图片参考形态对齐 + 项目壳规范收口）：
// 自包 PageShell 壳（标题 = 「服务商编辑」——★ 2026-08-31 领导指令统一（原「新建服务商/
// 服务商详情」双态口径作废）+ 右上角「保存」键——表单页
// 语义，ChatPage/LogPage 同款自包壳先例）；内容 = 顶部服务商卡（2026-08-30 详情
// 页改版：品牌 logo + 名称/URL + 徽章行含余额，ProviderHeadCard 域件；仅编辑态）+「配置 /
// 模型 / 高级」SegmentBar 分段（外观页同款官方胶囊）+ 三面板（细则见各自头注释）。
// 双态：列表页「+」push 无参 = 新建（保存才落库）；点卡片携 providerId = 编辑
// （aboutToAppear 读行回填）。★ 2026-09-11 方案 v3：余额配置已迁二级页 BalanceConfigPage
// （新建不预填 / 编辑不回填，载入归余额页自拉），本页保存链零触碰 balance_* 列（P0-1）。
// ★ 同日晚反馈修正笔：余额入口卡改「配置余额 + 余额查询」双键——查询链回本页
// （queryBalance：读库态配置 + 只写 balance_last_text，配置列写路径仍唯一归余额页）。
// 保存校验 = 名称/Base URL 非空 + baseUrl http(s) 前缀
// （密钥不经此链——池条目的添加/删除/重填是资源动作即时落库）；协议/自定义头随保存落库；
// 启停草稿（2026-08-31 统一保存语义，领导拍板「所有配置改后必须点右上角勾才能被保存」）：
// Key 启停/模型启停/批量启停在面板乐观更新 + 上行 ProviderToggleDraft 记草稿，保存链尾
// flush 统一落库，不点勾退出 = 页面销毁草稿自然丢弃；成功 toast + pop（列表页
// 经 onPop reload 重拉——坑16·2026-08-30 复活自动链，真凶定位见 ProviderPage 头注释）。
// ★ 裁剪口径（对照参考图）：「分享」键不做（★ 2026-09-20 核正：原理由句写「导出配置文件
// 无消费场景」，而单家导出已由列表页卡片菜单「分享」承担——本页不重复挂该键）；顶部卡
// 无开关（列表页已有）。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  insertProvider, ModelRow, ProviderRow, queryProviders,
  setProviderEnabled, setProviderKeyPickMode, updateProvider, updateProviderPromptCache
} from '../../common/store/ProviderDb';
import {
  ENDPOINT_CHAT, ENDPOINT_RESPONSES, HeaderPair, parseHeaderPairs, PROTOCOL_ANTHROPIC,
  PROTOCOL_OPENAI, serializeHeaderPairs
} from '../../common/providers/AiTypes';
import { describeMismatch, MismatchHint } from '../../common/providers/ProviderCatalog';
import { isPublicCleartextEndpoint } from '../../common/providers/EndpointPolicy';
// 余额查询链（2026-09-11 反馈修正笔：查询键自余额页移入入口卡——取数只读库态 + 专用 Key
// 回退池首启用；落库仅 balance_last_text）
import { BalanceQuery, BalanceResult, fetchBalance } from '../../common/providers/BalanceApi';
import { BalanceState, queryBalanceState, saveBalanceText } from '../../common/store/ProviderBalanceDb';
import { firstEnabledPoolKey, KEY_PICK_RANDOM, KEY_PICK_ROTATE } from '../../common/store/ProviderKeyDb';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, SEGMENT_BAR_HEIGHT } from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import { ProviderConfigPanel } from './ProviderConfigPanel';
import { ProviderModelsPanel } from './ProviderModelsPanel';
import { ProviderHeadersPanel } from './ProviderHeadersPanel';
import { ProviderBodyPanel } from './ProviderBodyPanel';
import { BalanceConfigParam } from './BalanceConfigPage';
import { ProviderHeadCard } from './ProviderHeadCard';
import { PROVIDER_EDIT_ID_KEY } from './ProviderKeysPanel';
import { ModelEditParam } from './ModelEditPage';

import { ROUTE_BALANCE_CONFIG_PAGE, ROUTE_MODEL_EDIT_PAGE, ROUTE_PRICE_TEMPLATE_PAGE, ROUTE_PROVIDER_DETAIL_PAGE } from '../../common/RouteNames';
// 保存菜单工厂（2026-08-31 域拆迁出，函数体不变）+ 启停草稿域（统一保存语义）
import { providerSaveMenuHds, providerSaveMenuNav } from './ProviderSaveMenu';
import { ProviderToggleDraft } from './ProviderToggleDraft';

@Component
export struct ProviderDetailPage {
  // 顶部留白（vp，PageMapBuilder 注入——首卡落标题栏蒙层下方）
  @Prop topPad: number = 0;
  // 官方路由栈（pop 返回 / push 编辑模型页）
  pathStack: NavPathStack = new NavPathStack();
  // 分段选项（配置/模型/高级——外观页同款官方胶囊，SegmentBar 公共封装消费）
  private sectionItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '配置' },
    { text: '模型' },
    { text: '高级' }
  ]);
  @State private segIndex: number = 0;
  // 编辑对象（'' = 新建）；表单字段 + 启用开关（保存时落库）
  @State private providerId: string = '';
  // 加载完成闸（★ O-13 修复，同族四页统一：技能/记忆/提示词/服务商）：loadEditState 的 catch
  // 只 toast、页面仍可编辑——此时表单是空初值、providerId 也停在 ''，用户填完保存会走**新建分支**
  // 插一条重名服务商（用户以为在改配置，实况多出一行）。闸 = 未加载完成不许保存（形制与理由照
  // BalanceConfigPage 的 loaded 闸先例）：新建态无待读行显式置真、读成功置真、读失败保持假
  // ⇒ 保存链首拦一道显式提示；普通成员即可（不驱动 UI）
  private loaded: boolean = false;
  @State private name: string = '';
  @State private baseUrl: string = '';
  // 协议（AiTypes 常量值，新建默认 openai）与自定义请求头 kv 行（保存时序列化落库，
  // 空 k/v 行丢弃——2026-08-30 三协议改组合；key 明文不经此页——池在配置页签面板）
  @State private protocol: string = PROTOCOL_OPENAI;
  // OpenAI 接口形态（v5 列；仅 openai 有意义——a/g 恒 chat 不显示不保存语义差；子分段
  // 胶囊在配置面板，值唯一真源在此，保存时落库）
  @State private endpoint: string = ENDPOINT_CHAT;
  @State private headerPairs: HeaderPair[] = [];
  // 自定义 Body 覆盖 kv 行（v13 列，2026-09-02——高级页签；k = 请求体顶层键名，
  // v = 合法 JSON 值文本；保存时校验后随标题栏键统一落库，headers 同款草稿语义）
  @State private bodyPairs: HeaderPair[] = [];
  // 启用开关（成员名避开通用属性 enabled——10505001 撞名）
  @State private providerEnabled: boolean = true;
  // ★ 2026-09-11（方案 v3 余额配置二级页化）：余额配置表单值已从本页迁出——余额页
  // BalanceConfigPage 页内 @State 自持 + 页内自保存（P0-1：原保存链 updateBalanceConfig
  // 段已同笔删除，恒写八列不判空，残留会清空用户余额配置含 balance_key）；本页从此
  // 不持有/不传播任何余额配置状态。★ 同日晚反馈修正笔：本页只读余额态（queryBalance
  // 内的 queryBalanceState）跑入口卡「余额查询」键——写路径仍唯一归余额页
  // 提示缓存草稿态（2026-09-01 DB v12 高级页签卡）：开关 + TTL 分段下标（0 = 5m / 1 = 1h，
  // 落库映射 '5m'|'1h'）——随标题栏「保存」键统一落库（updateProviderPromptCache），与
  // 余额配置同款草稿语义；默认关 = 存量与新建零回归
  @State private promptCacheOn: boolean = false;
  @State private promptCacheTtlIdx: number = 0;
  // 取钥方式分段下标（2026-09-17 DB v32；0 = 轮询 / 1 = 随机）——父页真源，经 ConfigPanel
  // @Link 透传给 Key 池卡胶囊；新建态恒 0（草稿），落库在保存链尾
  @State private keyPickIdx: number = 0;
  // 余额查询进行中（入口卡「余额查询」键防连点；键显「查询中…」+ 置灰）
  @State private balanceQuerying: boolean = false;
  // TTL 分段选项（官方胶囊，SegmentBar 公共封装——外观页/服务商页签同款）
  private ttlItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '5 分钟' },
    { text: '1 小时' }
  ]);
  // （2026-08-30 自持有重构：balLastText/modelCount 派生显示态已随顶部服务卡自拉内聚——
  // 卡自身 @State + 刷新键自查库，父页不再持有/传播，根因见 ProviderHeadCard 头注释）
  // 顶卡/模型面板重建纪元（坑16·2026-08-30：卡内徽章 @Builder 值参直调 = 按值快照不
  // 自刷，靠 ForEach 键变整卡重建重拉。触发源三个：余额查询成功 onQueried → headEpoch /
  // 获取模型成功 onModelsChanged → headEpoch / 编辑模型页 onPop → 双纪元）
  @State private headEpoch: number = 0;
  @State private modelsEpoch: number = 0;
  // 启停草稿域（2026-08-31 统一保存语义）：Key/模型启停面板乐观更新 + 上行记此，保存链尾
  // flush 落库；普通成员即可（不驱动 UI，面板 UI 由各自 @State 数组乐观更新驱动）——
  // 契约与生命周期见 ProviderToggleDraft 头注释
  private toggles: ProviderToggleDraft = new ProviderToggleDraft();
  // 系统颜色模式（提示缓存卡回退卡底色 cardBg 入参；EntryAbility 写键，深浅色自动刷新）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感双态（价格模板入口卡「管理模板」键 = 内容区行内文字键，fallbackButton* 四件套）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  aboutToAppear(): void {
    // push 参数 = providerId（编辑态）；null/非串/空串 = 新建态（getParamByName 取末条，
    // ImageEditPage 先例）。★ 2026-08-30 反馈轮 7 修复「新建秒退」：列表页「新建」push
    // null，原读法 as Array<string> 后末条 = null ≠ '' 误入编辑分支 → 查无此行 toast
    //「服务商不存在或已删除」+ 自动 pop（push 动画中途被拉回，领导截图实锤）。读法对齐
    // ChatPage 守卫：typeof 窄化后取值，null/undefined/非串一律归 '' = 新建态
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_PROVIDER_DETAIL_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const pid: string = typeof last === 'string' ? last : '';
    // 编辑对象广播入口同步写入（编辑 = 参数 id / 新建 = ''）——页面出生即正确，不等异步
    // 回填。★ 出页不再清空（2026-08-30 竞态实锤：pop 转场未结束旧页未销毁即重进，
    // aboutToDisappear 的清空 '' 落在本次写入之后 → 面板冻结提示卡——「返回立刻重进
    // Key 池不见」根因；本键消费方只活在本页内、每次进入此处先覆写，残留不可观察）
    AppStorage.setOrCreate<string>(PROVIDER_EDIT_ID_KEY, pid);
    if (pid === '') {
      // 新建态：直接返回（★ 2026-09-11 方案 v3——原「余额预填模板清单首项 DeepSeek」已
      // 随余额配置迁页删除：余额页 BalanceConfigPage 载入时自行回填库态，新建态不预填；
      // 入口卡仅编辑态，新建页无余额入口）
      this.loaded = true; // 新建态无待读行（闸只拦「加载未完成」）
      return;
    }
    this.loadEditState(pid);
  }

  // 编辑态加载：行 → Asset key → 余额态 → 模型计数 顺序回填；行不存在退栈（不静默
  // 停空表单），任一步失败 toast（P0-1）**且不置加载闸**——读失败后表单是空初值而
  // providerId 停在 ''，保存会走新建分支误插重名行，故保存链首有 loaded 闸（O-13 修复，见成员位）
  private async loadEditState(pid: string): Promise<void> {
    try {
      const rows: ProviderRow[] = await queryProviders();
      const row: ProviderRow | undefined = rows.find((item: ProviderRow): boolean => item.id === pid);
      if (row === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '服务商不存在或已删除' });
        this.pathStack.pop();
        return;
      }
      this.providerId = row.id;
      // （编辑对象广播已前移 aboutToAppear 入口同步写入——单一写入点，见入口注释）
      this.name = row.name;
      this.baseUrl = row.baseUrl;
      this.providerEnabled = row.enabled;
      this.protocol = row.protocol;
      // 接口形态回填（异常值钳位 chat——工厂同款保守语义；存量行 DEFAULT 'chat' 双保险）
      this.endpoint = row.endpoint === ENDPOINT_RESPONSES ? ENDPOINT_RESPONSES : ENDPOINT_CHAT;
      this.headerPairs = parseHeaderPairs(row.headers);
      this.bodyPairs = parseHeaderPairs(row.bodyOverrides);
      // ★ 2026-09-11 方案 v3：余额配置回填已随迁页删除——余额配置载入归 BalanceConfigPage
      // 页内 queryBalanceState（P0-1 配套：本页保存链不再写 balance_* 配置列；同日晚反馈
      // 修正笔后本页只读余额态——查询键 queryBalance 内读库、只写 balance_last_text）
      // 提示缓存回填（v12 列；脏 TTL 已在解析侧钳位官方两档）
      this.promptCacheOn = row.promptCacheEnabled;
      this.promptCacheTtlIdx = row.promptCacheTtl === '1h' ? 1 : 0;
      // 取钥方式回填（v32 列；脏值已在解析侧钳位 rotate——下标只认 random 一档）
      this.keyPickIdx = row.keyPickMode === KEY_PICK_RANDOM ? 1 : 0;
      this.loaded = true; // 闸放行（读成功）
    } catch (e) {
      // 读取失败：不置闸（保持「加载未完成」）→ 保存被首拦，封死「误插重名新行」（见成员位注释）
      this.getUIContext().getPromptAction().showToast({ message: '服务商读取失败：' + (e as Error).message });
    }
  }

  // （refreshDerived/refreshAll 已删——派生显示态 = 顶部卡自拉，2026-08-30 自持有重构，见 ProviderHeadCard 头注释）

  // ★ 2026-09-11 方案 v3：balanceCfg() 已随余额配置迁页删除——余额配置落库值组装配归
  // 余额页 BalanceConfigPage.balanceCfg（页内自保存）

  // 自定义 Body 校验 + 序列化（2026-09-02 v13）：k 非空且 v 空的行 = 拦截（与 headers
  // 「空行丢弃」不同——body 的值有 JSON 语义，半填行静默丢弃会让用户误以为已生效，
  // P0-1 显式提示）；k 非空且 v 非空的行 JSON.parse 校验，非法 toast 返回 null。返回
  // '' = 无覆盖（空行全丢弃后无有效行）
  private validatedBodyJson(): string | null {
    const effective: HeaderPair[] = [];
    for (const pair of this.bodyPairs) {
      if (pair.k.trim() === '' && pair.v.trim() === '') {
        continue; // 全空行静默丢弃（headers 同款）
      }
      if (pair.k.trim() === '' || pair.v.trim() === '') {
        this.getUIContext().getPromptAction().showToast({ message: '自定义 Body 的键与值 JSON 均需填写' });
        return null;
      }
      try {
        JSON.parse(pair.v);
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '自定义 Body「' + pair.k + '」的值不是合法 JSON' });
        return null;
      }
      effective.push(pair);
    }
    return serializeHeaderPairs(effective);
  }

  // 保存（标题栏键）：校验名称/Base URL + 前缀 → 落库（新建 insert / 编辑 update，协议
  // 与自定义头随行写入）+ 启用开关（编辑态）→ toast + pop。任一步失败显式提示（P0-1）。
  // 密钥不经此链——Key 池条目在配置页签即时落库。★ 余额配置亦不经此链（方案 v3 迁页后
  // 归余额页页内自保存，见下方 saveTailThenPop 注释）
  private save(): void {
    // 加载完成闸（未加载完 = 表单是空初值 + providerId 停在 ''，落库即误插重名新行；
    // 闸的形状与理由照 BalanceConfigPage 先例；O-13 修复）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '服务商未加载完成，暂不能保存，请返回重进' });
      return;
    }
    const name: string = this.name.trim();
    const baseUrl: string = this.baseUrl.trim();
    if (name === '' || baseUrl === '') {
      this.getUIContext().getPromptAction().showToast({ message: '名称与 Base URL 均需填写' });
      return;
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.getUIContext().getPromptAction().showToast({ message: 'Base URL 需以 http:// 或 https:// 开头' });
      return;
    }
    // 自定义 Body 校验（v13：值须合法 JSON、半填行拦截——非法则不进入落库链）
    const bodyJson: string | null = this.validatedBodyJson();
    if (bodyJson === null) {
      return;
    }
    // 协议-URL 匹配检查（2026-08-30 服务商图谱）：block（跨家端点串接）= 拦截保存；
    // warn（Responses 非官方端点等高风险）= 提示后继续，不打断高自由度配置
    const mismatch: MismatchHint = describeMismatch(this.protocol, this.endpoint, baseUrl);
    if (mismatch.message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: mismatch.message });
      if (mismatch.level === 'block') {
        return;
      }
    }
    // ── 端点加密闸（2026-09-24 明文放行治理笔 P0-1；判据单源 = EndpointPolicy）──
    // 公网明文地址（http + 主机既非回环也非私网）新增一次确认：密钥与整轮对话会以明文
    // 出网。回环与私网放行（自建网关 one-api / LM Studio / Ollama 的主场景），https 与
    // 不成形地址不进此闸（后者由上方前缀校验拦）。存量已保存的公网明文配置不追溯拦截
    // （本闸只在改动本次配置时过），可见性由服务商管理页卡片的「明文」徽章常驻承担
    if (isPublicCleartextEndpoint(baseUrl)) {
      this.confirmCleartextThenSave(name, baseUrl, bodyJson);
      return;
    }
    this.persistProvider(name, baseUrl, bodyJson);
  }

  // 公网明文确认后继续保存（2026-09-24 P0-1）：确认走**同一条落库链** persistProvider
  // （禁在确认支内另抄一份保存逻辑——两处实现必漂移）；取消或关闭（-1 防御）= 不保存且
  // 静默（属正常取消路径）；对话框自身失败 = 显式提示（P0-1 不静默，且不落库）
  private async confirmCleartextThenSave(name: string, baseUrl: string,
    bodyJson: string): Promise<void> {
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: '地址未加密',
        message: '这个地址在公网且未启用加密连接。API 密钥与对话内容会以明文发送，同一网络中的他人可能看到。仍要保存吗？',
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '仍要保存', color: $r('sys.color.font_primary') }
        ]
      });
      if (choice.index !== 1) {
        return; // 取消或关闭（-1）——不落库
      }
      this.persistProvider(name, baseUrl, bodyJson);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '确认框未弹出，请重试保存' });
    }
  }

  // 落库链（原 save 尾段逐字搬迁，2026-09-24 P0-1 笔——确认支与直存支共用本实现）：
  // 提示缓存 → 取钥方式 → 启停草稿 flush → toast + pop；新建 insertProvider（成功后回写
  // providerId 与编辑对象广播键），编辑 updateProvider + 启用开关
  private persistProvider(name: string, baseUrl: string, bodyJson: string): void {
    const headersJson: string = serializeHeaderPairs(this.headerPairs);
    // ★ 2026-09-11 方案 v3（P0-1 双证点）：保存链头原为 updateBalanceConfig（恒写
    // balance_* 八列不判空，而余额表单值已随迁页删除——残留调用会把空配置写回库、
    // 清空用户余额配置含 balance_key）→ 已整段删除，链头改提示缓存落库；余额配置
    // 落库归余额页 BalanceConfigPage 页内自保存（updateBalanceConfig 的**界面写点**唯一在此；
    // 另一处 ProviderShare 导入配置写回是既有正当消费，与本链无关）。
    // ★ 旧名 saveBalanceThen（余额段在链时得名）随迁页失真，改现名——本函数只做
    // 保存链尾的提示缓存落库 + 草稿 flush + pop
    const saveTailThenPop = (): void => {
      updateProviderPromptCache(this.providerId, this.promptCacheOn,
        this.promptCacheTtlIdx === 1 ? '1h' : '5m')
        .then((): Promise<void> =>
          // 取钥方式落库（v32 列；与启停草稿同属「随保存键落库」一族——改选只动页面态）
          setProviderKeyPickMode(this.providerId,
            this.keyPickIdx === 1 ? KEY_PICK_RANDOM : KEY_PICK_ROTATE))
        .then((): Promise<void> =>
          // 启停草稿统一落库（2026-08-31 统一保存语义）：全成清空草稿后 pop；任一失败
          // reject 落下方 catch（toast「保存失败」不 pop——草稿保留可重试，表单已落库
          // 幂等重写，最终一致）
          this.toggles.flush())
        .then((): void => {
          // 坑16·2026-08-30 + 坑17：pop 必须带 result——管理页 onPop 触发条件
          // （官方 d.ts「triggered only when the result parameter is set in pop」；
          // 无参 pop = 保存后列表不刷新的历史根因，提示词页同款当日修复后全链统一）
          this.getUIContext().getPromptAction().showToast({ message: '已保存' });
          this.pathStack.pop({ saved: true });
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    };
    if (this.providerId === '') {
      insertProvider(name, baseUrl, this.protocol, this.endpoint, headersJson, bodyJson)
        .then((row: ProviderRow): void => {
          this.providerId = row.id;
          // 新建保存成功二次写入 '' → 新 id（Key 池/模型面板自感知，提示卡切可管理——
          // 本页生命周期内唯一的中途写入点；契约见 ProviderKeysPanel 键常量注释）
          AppStorage.setOrCreate<string>(PROVIDER_EDIT_ID_KEY, row.id);
          saveTailThenPop();
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    } else {
      updateProvider(this.providerId, name, baseUrl, this.protocol, headersJson, this.endpoint,
        bodyJson)
        .then((): Promise<void> => setProviderEnabled(this.providerId, this.providerEnabled))
        .then((): void => {
          saveTailThenPop();
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    }
  }

  // （出页清空编辑对象广播已删——旧页销毁滞后 pop 转场，与下次进入写入竞态，曾致「返回立刻重进面板冻结提示卡」；契约见 ProviderKeysPanel 键常量注释）

  // 余额查询（入口卡「余额查询」键；★ 2026-09-11 反馈修正笔自余额页移入本页——决明
  // 「查询键应放在外面余额查询卡内，配置余额与余额查询双键」）：入参 = 余额页保存落库后的
  // 配置（先保存后查询，两步显式；卡片说明小字已交代）。链 = 读库态 → 守卫
  // （结果 JSON 路径 / 端点）→ 取钥（专用余额 Key 优先，空 = 密钥池首个启用）→ GET → 组合
  // 币种文本 → saveBalanceText 落库 → toast + headEpoch 自增（顶卡徽章纪元键重建重拉，坑16
  // 复活链）；失败 toast 不静默（P0-1）。★ 本方法只读配置、只写 balance_last_text——
  // 配置列写路径仍唯一归余额页页内自保存（本页零 updateBalanceConfig 调用——钉 B2 判据）
  private async queryBalance(): Promise<void> {
    if (this.balanceQuerying) {
      return;
    }
    this.balanceQuerying = true;
    try {
      const state: BalanceState = await queryBalanceState(this.providerId);
      const resultPath: string = state.resultPath.trim();
      if (resultPath === '') {
        this.getUIContext().getPromptAction().showToast(
          { message: '请先配置「结果 JSON 路径」，或套用模板' });
        return;
      }
      // 端点回退：专用余额端点为空 → 服务 Base URL（本页表单值，与保存语义一致）
      const balBase: string = state.baseUrl.trim();
      const base: string = balBase !== '' ? balBase : this.baseUrl.trim();
      if (base === '') {
        this.getUIContext().getPromptAction().showToast(
          { message: '请先配置「余额 Base URL」或在「配置」页签填写 Base URL' });
        return;
      }
      const dedicated: string = state.key.trim();
      const key: string = dedicated !== '' ? dedicated : await firstEnabledPoolKey(this.providerId);
      if (key === '') {
        this.getUIContext().getPromptAction().showToast(
          { message: '请先填写专用余额 Key，或在「配置」页签的密钥池添加 API Key' });
        return;
      }
      const query: BalanceQuery = {
        baseUrl: base,
        path: state.path.trim(),
        key: key,
        resultPath: resultPath,
        currencyPath: state.currencyPath.trim(),
        headers: parseHeaderPairs(state.headers)
      };
      const result: BalanceResult = await fetchBalance(query);
      // 币种组合：点路径取到优先，未取到回退配置币种（currency 字段语义）
      const cur: string = result.currency !== '' ? result.currency : state.currency.trim();
      const text: string = result.text + (cur !== '' ? ' ' + cur : '');
      // 落库保留（顶部卡/列表卡读库显示）+ 顶卡徽章纪元键重建重拉
      await saveBalanceText(this.providerId, text);
      this.getUIContext().getPromptAction().showToast({ message: '已更新余额：' + text });
      this.headEpoch += 1;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
    } finally {
      this.balanceQuerying = false;
    }
  }

  // 编辑模型页入口（面板回调）：push 携参（row 为 null = 新建；字面量挂 ModelEditParam
  // 接口——坑59 ①）★ 坑16·2026-08-30 onPop 复活：返回即双纪元自增——顶卡计数与模型
  // 清单整卡重建重拉（此前「自动链不可靠」的真凶 = 徽章 @Builder 值参快照 + tick 广播
  // push 页内不触发，非 onPop 本身——回调走官方路由链不经 content 传播）
  private openModelEdit(row: ModelRow | null): void {
    const param: ModelEditParam = {
      providerId: this.providerId,
      modelRowId: row !== null ? row.id : ''
    };
    this.pathStack.pushPathByName(ROUTE_MODEL_EDIT_PAGE, param, (): void => {
      this.headEpoch += 1;
      this.modelsEpoch += 1;
    });
  }

  // 提示缓存卡（2026-09-01 高级页签，ProviderBalancePanel 之后同区——DB v12）：仅
  // anthropic 协议显示（cache_control 仅 Anthropic Messages 规格——OpenAI/Gemini 官方
  // 自动缓存无此配置）；开关 + TTL 官方胶囊分段；草稿态直读 this（坑16 零值参），随
  // 保存键落库不走即时落库
  @Builder
  PromptCacheCard() {
    if (this.protocol === PROTOCOL_ANTHROPIC) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('提示缓存（cache_control）')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('请求打缓存断点。多轮重复前缀命中后按缓存价计费，写入 1.25 倍，读取 0.1 倍')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.promptCacheOn })
            .onChange((isOn: boolean): void => {
              this.promptCacheOn = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (this.promptCacheOn) {
          Column({ space: 6 }) {
            Text('缓存有效期（TTL）')
              .fontSize(13)
              .fontColor(cardDescColor())
            SegmentBar({
              items: this.ttlItems,
              selectedIndex: $promptCacheTtlIdx
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 价格模板入口卡（2026-09-11 价格模板；高级页签末位）：标题 + 说明
  // 小字 + 通宽「管理模板」键（内容区双态 fallbackButton* primary=true——本卡主操作键，
  // 官方强调蓝 + 恒白字；2026-09-11 决明「三处模板键均改蓝底」，原 primary=false 作废）；
  // 仅编辑态显示（口径⑪：新建态服务商尚无归属，模板无家）；push 不挂 onPop（口径⑩：入口卡
  // 不显示模板计数，本页无刷新链需求——列表页自会重拉）
  @Builder
  PriceTemplateEntryCard() {
    if (this.providerId !== '') {
      Column({ space: 10 }) {
        Text('价格模板')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text('集中保存本服务商的价格配置，在编辑模型页一键填入。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        Button('管理模板')
          .fontSize(14)
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback,
            this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback,
            this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback,
            this.immersiveLevel))
          .width('100%')
          .onClick((): void => {
            this.pathStack.pushPathByName(ROUTE_PRICE_TEMPLATE_PAGE, this.providerId);
          })
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 余额查询入口卡（2026-09-11 方案 v3 余额配置二级页化；高级页签，原 ProviderBalancePanel
  // 挂载位）：标题 + 说明小字 + 双键行「配置余额」（次钮，push 二级页）/「余额查询」（主操作，
  // 官方强调蓝）——★ 反馈修正笔：查询键自余额页移出回本卡（决明「查询键应放在外面余额查询
  // 卡内，配置余额与余额查询双键」），双键同宽各半行、次钮居左主操作居右（原面板双键同款
  // 序）；仅编辑态显示（新建态服务商尚无行，余额配置无家——同价格模板入口卡口径）；
  // push 携 BalanceConfigParam{providerId}（坑59 ① 字面量挂接口）+ 挂 onPop 回调自增
  // headEpoch——余额页保存 pop 带 result 返回即刷顶卡余额徽章（坑17：无参 pop 不触发 onPop）
  @Builder
  BalanceEntryCard() {
    if (this.providerId !== '') {
      Column({ space: 10 }) {
        Text('余额查询')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text('配置保存后点「余额查询」拉取，卡片显示余额。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        Row({ space: 10 }) {
          Button('配置余额')
            .fontSize(14)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback,
              this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback,
              this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback,
              this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              const param: BalanceConfigParam = {
                providerId: this.providerId
              };
              this.pathStack.pushPathByName(ROUTE_BALANCE_CONFIG_PAGE, param, (): void => {
                this.headEpoch += 1;
              });
            })
          // 「余额查询」= 主操作（官方强调蓝——primary=true + 恒白字；查询中置灰防连点）
          Button(this.balanceQuerying ? '查询中…' : '余额查询')
            .fontSize(14)
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback,
              this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback,
              this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback,
              this.immersiveLevel))
            .layoutWeight(1)
            .enabled(!this.balanceQuerying)
            .onClick((): void => {
              this.queryBalance();
            })
        }
        .width('100%')
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 页面内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。
  // 结构 = LogPageContent 同款吸顶（2026-08-30 反馈轮 2 领导指令「参考运行日志实现」）：
  // Stack{ 内容滚动层 + 分段胶囊悬浮固定层 }——胶囊固定顶部不随内容滚，内容向上滚时
  // 从胶囊背后穿过、经背板沉浸光感材质（backgroundSystemMaterial，SegmentBar 组件内）
  // 模糊透出；三页签面板（含配置面板）统一在滚动层内 = 整页可滚（反馈轮 2 修复
  // 「配置页无法滚」——原配置面板无 Scroll 承载）；顶部服务商卡在滚动层 Column 首位
  //（随滚动，任务 4 口径）
  @Builder
  Content() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        // ── 内容滚动层：顶部留白 = 胶囊悬浮位（topPad-8 钳位 0）+ 胶囊高 + 间距 28
        //（LogPageContent 同款三段构成；短内容顶对齐坑18 + 可拖回弹坑76）──
        Scroll() {
          Column({ space: 10 }) {
            // ── 顶部服务商卡（编辑态；新建态无行可陈列——表单即本体）：2026-08-30 自持有
            // 重构 = 卡内自拉 + 刷新键，本页只传 providerId（content 内 @Prop 不随父更新，
            // 见 ProviderHeadCard 头注释）；坑16 纪元键 ForEach = 余额查询/获取模型/编辑
            // 模型页返回后整卡重建重拉（onQueried/onModelsChanged/onPop 上行自增 headEpoch）──
            if (this.providerId !== '') {
              // 恒单例 ForEach（坑16 口径）
              ForEach([this.headEpoch], (epoch: number) => {
                ProviderHeadCard({
                  providerId: this.providerId
                })
              }, (epoch: number): string => 'head|' + epoch)
            }
            if (this.segIndex === 0) {
              ProviderConfigPanel({
                name: $name,
                baseUrl: $baseUrl,
                providerEnabled: $providerEnabled,
                protocol: $protocol,
                endpoint: $endpoint,
                // Key 池启停草稿链（2026-08-31 统一保存语义）：引用 + 上行回调透传——
                // 普通成员传引用不经状态链，契约见 ProviderToggleDraft 头注释
                keyDraftRef: this.toggles.keyState(),
                onKeyToggleDraft: (keyId: string, on: boolean): void => {
                  this.toggles.setKey(keyId, on);
                },
                // 取钥方式分段下标（2026-09-17 DB v32；@Link 透传到 Key 池卡胶囊——改选只动
                // 本页态，落库在下方保存链尾 setProviderKeyPickMode）
                keyPickIdx: $keyPickIdx
                // providerId 经 AppStorage 键订阅（不传参——@Prop 链不随父更新），
                // 见 ProviderKeysPanel 键常量注释
              })
            } else if (this.segIndex === 1) {
              // 坑16：纪元键整面板重建——编辑模型页 onPop 后清单重拉（恒单例 ForEach，
              // 面板 aboutToAppear 自 reload）
              ForEach([this.modelsEpoch], (epoch: number) => {
                ProviderModelsPanel({
                  baseUrl: this.baseUrl,
                  protocol: this.protocol,
                  // 模型启停草稿链（2026-08-31 统一保存语义，Key 池同款透传姿势）
                  modelDraftRef: this.toggles.modelState(),
                  onToggleDraft: (rowId: string, on: boolean): void => {
                    this.toggles.setModel(rowId, on);
                  },
                  onOpenModel: (row: ModelRow | null): void => {
                    this.openModelEdit(row);
                  },
                  // 获取模型成功 → 顶卡计数重建重拉（坑16 复活的上行回调）
                  onModelsChanged: (): void => {
                    this.headEpoch += 1;
                  }
                })
              }, (epoch: number): string => 'models|' + epoch)
            } else {
              // ── 高级页签 = 进阶配置（2026-08-30 决策：自定义请求头自配置页签迁入——
              // Header 属进阶/兼容性设置，与基础/协议/密钥池等日常项分层；余额查询同属
              // 进阶项并列；两面板随整页滚动）──
              Column({ space: 10 }) {
                ProviderHeadersPanel({
                  pairs: $headerPairs
                })
                // ── 自定义 Body 卡（2026-09-02 DB v13：headers 同构表单——发送时顶层键
                // 覆盖/追加，四协议统一 merge，落库走标题栏保存键）──
                ProviderBodyPanel({
                  pairs: $bodyPairs
                })
                // ── 余额查询入口卡（2026-09-11 方案 v3 余额配置二级页化：原
                // ProviderBalancePanel〔余额查询卡 + 配置半模态〕整件退役——配置迁
                // BalanceConfigPage 二级页，本卡为入口，照 PriceTemplateEntryCard 形制；
                // 位置 = 原面板挂载位）──
                this.BalanceEntryCard()
                // ── 提示缓存卡（2026-09-01 DB v12：anthropic 协议才显示；随保存键落库）──
                this.PromptCacheCard()
                // ── 配置迁移卡已退役（2026-09-20 决明指令：与卡片菜单「分享」重复，只留
                // 菜单；卡 = ProviderSharePanel 整件删除——导出/导入编排仍在
                // ProviderShareFlow.ets，入口 = 服务商管理页卡片菜单「分享」+ 标题栏
                // 更多菜单「分享配置/导入配置」，链路逐字未动）──
                // ── 价格模板入口卡（2026-09-11 价格模板；高级页签末位，仅编辑态显示）──
                this.PriceTemplateEntryCard()
              }
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          // 左右不另设 padding——面板卡自带 CARD_PANEL_WIDTH（calc(100%-32vp)），
          // Column 默认水平居中；再加左右 16 会双重收窄
          .padding({
            top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28,
            bottom: 24
          })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

        // ── 分段胶囊悬浮固定层（Stack 顶层后声明在上）：位置 = 标题栏下沿 + 蒙层渐隐
        // 边缘 8vp（LogPageContent 同款）；本层仅悬浮定位与宽度约束，参数在 SegmentBar ──
        Column() {
          SegmentBar({
            items: this.sectionItems,
            selectedIndex: $segIndex
          })
        }
        .width(CARD_PANEL_WIDTH)
        .margin({ top: Math.max(this.topPad - 8, 0) })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      // 标题（★ 2026-08-31 领导指令：新建/编辑统一「服务商编辑」——原双态口径
      //「新建服务商 / 服务商详情」作废；顺带消除编辑态标题误显「新建服务商」问题
      //（原 title 依赖 providerId 赋值时机——异步赋值后无重渲驱动，常量标题不再依赖）
      title: '服务商编辑',
      menuHds: providerSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: providerSaveMenuNav((): void => {
        this.save();
      }),
      // 坑16·2026-08-30：仍不传 onShown（页显重拉无需求——顶卡 = 卡内刷新键 + 纪元键
      // 重建双通道，面板 = 挂载/纪元键重建）
      content: (): void => {
        this.Content();
      }
    })
  }
}
