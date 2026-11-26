// 服务商编辑页：自包 PageShell（标题恒「服务商编辑」+ 右上角「保存」键——表单页语义）；内容 =
// 顶部服务商卡（ProviderHeadCard，仅编辑态）+「配置 / 模型 / 高级」分段 + 三面板。
// 双态：列表页「+」push 无参 = 新建（保存才落库）；携 providerId = 编辑（aboutToAppear 读行回填）。
// 保存校验 = 名称 / Base URL 非空 + http(s) 前缀；协议/自定义头随保存落库。密钥不经此链（池条目
// 即时落库）；余额配置不过此链（迁 BalanceConfigPage，本页零 updateBalanceConfig 调用，只读库态
// 跑余额查询、只写 balance_last_text）。
// 启停草稿（统一保存语义）：Key/模型启停在面板乐观更新 + 上行 ProviderToggleDraft 记草稿，保存链
// 尾 flush 统一落库，不点勾退出 = 草稿自然丢弃；成功 toast + pop({ saved: true })（列表页经 onPop
// 重拉——坑16 复活链）。★ 停用即解绑：停用/删除清三面模型选择（助手绑定/会话覆盖/功能槽），复启
// 不回填——flush 返回值 > 0 时 toast 补一句。
// ★ 裁剪口径：「分享」键不做（单家导出由列表页卡片菜单承担）；顶部卡无开关；启用开关卡整卡退役
// ——启停唯一控制面 = 列表页卡片行尾开关（即时落库），本页保存链不写 enabled 列。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  insertProvider, ModelRow, ProviderRow, queryProviders,
  setProviderKeyPickMode, updateProvider, updateProviderPromptCache
} from '../../common/store/ProviderDb';
import {
  ENDPOINT_CHAT, ENDPOINT_RESPONSES, HeaderPair, parseHeaderPairs, PROTOCOL_ANTHROPIC,
  PROTOCOL_OPENAI, serializeHeaderPairs
} from '../../common/providers/AiTypes';
import { describeMismatch, MismatchHint } from '../../common/providers/ProviderCatalog';
import { isPublicCleartextEndpoint } from '../../common/providers/EndpointPolicy';
// 余额查询链（取数只读库态 + 专用 Key 回退池首启用；落库仅 balance_last_text）
import { BalanceQuery, BalanceResult, fetchBalance } from '../../common/providers/BalanceApi';
import { BalanceState, queryBalanceState, saveBalanceText } from '../../common/store/ProviderBalanceDb';
import { firstEnabledPoolKey, KEY_PICK_RANDOM, KEY_PICK_ROTATE } from '../../common/store/ProviderKeyDb';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgOffCard, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../../common/AppPreferences';
import {
  CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING, TINT_GRADIENT_ANGLE,
  TINT_POSITIVE, cardBg, cardBorderColor, cardDescColor, cardTitleColor, SEGMENT_BAR_HEIGHT,
  tintCardBg, tintCardGradientColors, CARD_RADIUS
} from '../../common/Theme';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { PageTopSegmentBand, SegmentBar } from '../SegmentBar';
import { SwipeGroup } from '../RowSwipeDelete';
import { ProviderConfigPanel } from './ProviderConfigPanel';
import { ProviderModelsPanel } from './ProviderModelsPanel';
import { ProviderHeadersPanel } from './ProviderHeadersPanel';
import { ProviderBodyPanel } from './ProviderBodyPanel';
import { BalanceConfigParam } from './BalanceConfigPage';
import { ProviderBalanceChannel, ProviderHeadCard } from './ProviderHeadCard';
import { PROVIDER_EDIT_ID_KEY } from './ProviderKeysPanel';
import { ModelEditParam } from './ModelEditPage';

import { ROUTE_BALANCE_CONFIG_PAGE, ROUTE_MODEL_EDIT_PAGE, ROUTE_PROVIDER_DETAIL_PAGE } from '../../common/RouteNames';
// 保存菜单工厂 + 启停草稿域（统一保存语义）
import { providerSaveMenuHds } from './ProviderSaveMenu';
import { ProviderToggleDraft } from './ProviderToggleDraft';

@Component
export struct ProviderDetailPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
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
  // 标题栏下方带承载（HDS 路径；几何与带内下移量单源 = 公共件 PageTopSegmentBand）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.sectionItems,
      selectedIndex: $segIndex
    })
  }
  // 编辑对象（'' = 新建）；表单字段（启用态不在本页——唯一控制面 = 列表页卡片开关）
  @State private providerId: string = '';
  // 加载完成闸（O-13 修复，同族四页统一）：读失败时表单是空初值而 providerId 停在 ''，保存会走
  // 新建分支插重名行——未加载完成不许保存（形制照 BalanceConfigPage）；普通成员
  private loaded: boolean = false;
  @State private name: string = '';
  @State private baseUrl: string = '';
  // 协议（AiTypes 常量值，新建默认 openai）与自定义请求头 kv 行（保存时序列化落库，
  // 空 k/v 行丢弃；key 明文不入此页——池在配置页签面板）
  @State private protocol: string = PROTOCOL_OPENAI;
  // OpenAI 接口形态（v5 列；仅 openai 有意义——a/g 恒 chat）；子分段胶囊在配置面板，真源在此
  @State private endpoint: string = ENDPOINT_CHAT;
  @State private headerPairs: HeaderPair[] = [];
  // 自定义 Body 覆盖 kv 行（v13 列，高级页签；k = 请求体顶层键名，v = 合法 JSON 值文本；
  // 保存时校验后随标题栏键落库，headers 同款草稿语义）
  @State private bodyPairs: HeaderPair[] = [];
  // 余额配置表单值已迁 BalanceConfigPage（页内自持 + 自保存；本页不持有、不传播任何余额配置
  // 状态，只读库态跑入口卡「余额查询」，写路径仍唯一归余额页）
  // 提示缓存草稿态（v12 列）：开关 + TTL 分段下标（0 = 5m / 1 = 1h）；随保存键统一落库，默认关
  @State private promptCacheOn: boolean = false;
  @State private promptCacheTtlIdx: number = 0;
  // 取钥方式分段下标（v32 列；0 = 轮询 / 1 = 随机）——父页真源，经 ConfigPanel @Link 透传；新建恒 0
  @State private keyPickIdx: number = 0;
  // 余额查询进行中（手动键与进页自动查询共用防连点；键显「查询中…」并置灰）
  @State private balanceQuerying: boolean = false;
  // ── 余额入口卡展示态 ──
  // 只读 balance_enabled 与 balance_last_text（写路径仍唯一归余额页）；金额与币种由 lastText 拆
  // 两段显示（大号数字是视觉锚点，整串塞进去字重与字号没法分层）。读失败按空态显示、不 toast
  @State private balEnabled: boolean = false;
  @State private balAmount: string = '';
  @State private balCurrency: string = '';
  // TTL 分段选项（官方胶囊，SegmentBar 公共封装——外观页/服务商页签同款）
  private ttlItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '5 分钟' },
    { text: '1 小时' }
  ]);
  // 顶卡/模型面板派生显示态均由域件自拉，父页不持有（根因见 ProviderHeadCard 头注释；例外 =
  // 下方余额通道——订阅式 @ObjectLink 属卡头注释已预留的传播面）
  // 余额展示通道（@Observed/@Track 细粒度刷新，余额防闪笔）：页面与顶卡共持同一实例，余额查询
  // 成功只写通道（顶卡余额徽标实参位直读 @Track 直驱刷新，卡零重建）；引用恒定不重赋，@State 仅作
  // 初始化源（@ObjectLink 编译器要求父组件装饰变量，普通成员不可传——ChatPage.anchorJudge 同形
  // 先例；ForEach 重建传同一实例）
  @State private balanceChannel: ProviderBalanceChannel = new ProviderBalanceChannel();
  // 顶卡/模型面板重建纪元（坑16：卡内徽章 @Builder 值参直调 = 按值快照不自刷，靠 ForEach 键变
  // 整卡重建重拉）。触发源三个：获取模型成功 / 编辑模型页 onPop / 余额配置页 pop（余额查询已改
  // 走上方通道细粒度刷新，撤整卡重建——同值查询零重建零闪）
  @State private headEpoch: number = 0;
  @State private modelsEpoch: number = 0;
  // 启停草稿域（统一保存语义）：面板乐观更新 + 上行记此，保存链尾 flush 落库；普通成员
  //（不驱动 UI）——契约与生命周期见 ProviderToggleDraft 头注释
  private toggles: ProviderToggleDraft = new ProviderToggleDraft();
  // 行左滑删除互斥组（仅模型行面板消费；滚动开始收口在 Scroll.onScrollStart）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  // 系统颜色模式（提示缓存卡回退卡底色 cardBg 入参；EntryAbility 写键，深浅色自动刷新）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（余额入口卡淡染底随档叠 alpha——与全站卡底同源，见 Theme.tintCardBg）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 内容区光感双态（余额卡双键 = 内容区行内文字键，fallbackButton* 四件套）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  aboutToAppear(): void {
    // push 参数 = providerId（编辑态）；null/非串/空串 = 新建态（typeof 窄化后取值，ChatPage 守卫
    // 同款——原 as Array<string> 读法把 null 当末条会误入编辑分支，出现「新建秒退」）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_PROVIDER_DETAIL_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const pid: string = typeof last === 'string' ? last : '';
    // 编辑对象广播入口同步写入（编辑 = 参数 id / 新建 = ''）。出页不清空——pop 转场未结束旧页
    // 未销毁即重进时，清空会落在本次写入之后并冻结面板（消费方只在本页内，每次进入先覆写）
    AppStorage.setOrCreate<string>(PROVIDER_EDIT_ID_KEY, pid);
    if (pid === '') {
      // 新建态直接返回（余额页自行回填库态；入口卡仅编辑态）
      this.loaded = true; // 新建态无待读行（闸只拦「加载未完成」）
      return;
    }
    this.loadEditState(pid);
  }

  // 编辑态加载：行 → 余额态 → 自动查询，顺序回填；行不存在退栈，任一步失败 toast（P0-1）
  // 且不置加载闸——读失败保存会误插重名行（见成员位）
  private async loadEditState(pid: string): Promise<void> {
    try {
      const rows: ProviderRow[] = await queryProviders();
      if (this.departed) {
        return;
      }
      const row: ProviderRow | undefined = rows.find((item: ProviderRow): boolean => item.id === pid);
      if (row === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '服务商不存在或已删除' });
        this.pathStack.pop();
        return;
      }
      this.providerId = row.id;
      this.name = row.name;
      this.baseUrl = row.baseUrl;
      this.protocol = row.protocol;
      // 接口形态回填（异常值钳位 chat——工厂同款保守语义；存量行 DEFAULT 'chat' 双保险）
      this.endpoint = row.endpoint === ENDPOINT_RESPONSES ? ENDPOINT_RESPONSES : ENDPOINT_CHAT;
      this.headerPairs = parseHeaderPairs(row.headers);
      this.bodyPairs = parseHeaderPairs(row.bodyOverrides);
      // 余额配置不在此回填——载入归 BalanceConfigPage.queryBalanceState
      // 提示缓存回填（v12 列；脏 TTL 已在解析侧钳位官方两档）
      this.promptCacheOn = row.promptCacheEnabled;
      this.promptCacheTtlIdx = row.promptCacheTtl === '1h' ? 1 : 0;
      // 取钥方式回填（v32 列；脏值已在解析侧钳位 rotate）
      this.keyPickIdx = row.keyPickMode === KEY_PICK_RANDOM ? 1 : 0;
      // 余额入口卡展示态（只读两列；与上面各段同一次编辑态载入）
      this.loadBalanceEntry();
      // 进页自动查询：余额开关已启用的服务商静默拉一次，顶卡徽章与入口卡大字随结果联动
      //（fire-and-forget——链内自兜错恒 resolve）
      this.queryBalance(true);
      this.loaded = true; // 闸放行（读成功）
    } catch (e) {
      if (this.departed) {
        return;
      }
      // 读取失败：不置闸（保持「加载未完成」）→ 保存被首拦，封死「误插重名新行」（见成员位注释）
      this.getUIContext().getPromptAction().showToast({ message: '服务商读取失败：' + (e as Error).message });
    }
  }

  // 派生显示态 = 顶部卡自拉（见 ProviderHeadCard 头注释）

  // balanceCfg() 已随余额配置迁页删除——装配归 BalanceConfigPage.balanceCfg

  // 自定义 Body 校验 + 序列化（v13）：k 非空且 v 空的行拦截（body 的值有 JSON 语义，半填行静默
  // 丢弃会误导，P0-1 显式提示）；v 须 JSON.parse 通过。返回 '' = 无覆盖
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

  // 保存（标题栏键）：校验名称/Base URL + 前缀 → 落库（新建 insert / 编辑 update）→ toast + pop。
  // 密钥、余额配置、启用态均不经此链（各有单源写点）
  private save(): void {
    // 加载完成闸（未加载完落库会误插重名新行；O-13 修复）
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
    // 自定义 Body 校验（值须合法 JSON、半填行拦截——非法不进落库链）
    const bodyJson: string | null = this.validatedBodyJson();
    if (bodyJson === null) {
      return;
    }
    // 协议-URL 匹配检查：block（跨家端点串接）= 拦截保存；warn（高风险配置）= 提示后继续
    const mismatch: MismatchHint = describeMismatch(this.protocol, this.endpoint, baseUrl);
    if (mismatch.message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: mismatch.message });
      if (mismatch.level === 'block') {
        return;
      }
    }
    // ── 端点加密闸（判据单源 = EndpointPolicy）──
    // 公网明文地址（http + 主机既非回环也非私网）新增一次确认：密钥与整轮对话会明文出网。回环/
    // 私网放行（自建网关 / LM Studio / Ollama 主场景），https 与不成形地址不进此闸；存量已保存
    // 的公网明文配置不追溯拦截，可见性由列表卡片「明文」徽章常驻承担
    if (isPublicCleartextEndpoint(baseUrl)) {
      this.confirmCleartextThenSave(name, baseUrl, bodyJson);
      return;
    }
    this.persistProvider(name, baseUrl, bodyJson);
  }

  // 公网明文确认后继续保存：确认走同一条落库链 persistProvider（禁在确认支内另抄一份）；取消/
  // 关闭（-1） = 不保存且静默；对话框失败 = 显式提示且不落库
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
      if (this.departed) {
        return;
      }
      if (choice.index !== 1) {
        return; // 取消或关闭（-1）——不落库
      }
      this.persistProvider(name, baseUrl, bodyJson);
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '确认框未弹出，请重试保存' });
    }
  }

  // 落库链（确认支与直存支共用）：提示缓存 → 取钥方式 → 启停草稿 flush → toast + pop；新建
  // insertProvider（回写 providerId 与编辑对象广播键），编辑 updateProvider（不写启用态）
  private persistProvider(name: string, baseUrl: string, bodyJson: string): void {
    const headersJson: string = serializeHeaderPairs(this.headerPairs);
    // 余额配置写点唯一归 BalanceConfigPage（本链已摘 updateBalanceConfig——残留调用会清空
    // 用户余额配置含 balance_key）
    const saveTailThenPop = (): void => {
      updateProviderPromptCache(this.providerId, this.promptCacheOn,
        this.promptCacheTtlIdx === 1 ? '1h' : '5m')
        .then((): Promise<void> =>
          // 取钥方式落库（v32 列；与启停草稿同属「随保存键落库」一族——改选只动页面态）
          setProviderKeyPickMode(this.providerId,
            this.keyPickIdx === 1 ? KEY_PICK_RANDOM : KEY_PICK_ROTATE))
        .then((): Promise<number> =>
          // 启停草稿统一落库：全成清空草稿后 pop；失败 reject 落 catch（toast 不 pop，草稿保留可
          // 重试）。★ 停用即解绑：返回值 = 本次停用解除的模型选择处数（助手绑定/会话覆盖/功能槽），
          // >0 时 toast 补一句——用户得知道槽位为何变成「未选择」；复启不回填
          this.toggles.flush())
        .then((cleared: number): void => {
          if (this.departed) {
            return;
          }
          // 坑16 + 坑17：pop 必须带 result（官方 d.ts「triggered only when the result parameter is
          // set in pop」；无参 pop = 保存后列表不刷新的历史根因）
          this.getUIContext().getPromptAction().showToast({
            message: cleared > 0 ? '已保存。停用的模型已解除相关模型选择' : '已保存'
          });
          this.pathStack.pop({ saved: true });
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    };
    if (this.providerId === '') {
      insertProvider(name, baseUrl, this.protocol, this.endpoint, headersJson, bodyJson)
        .then((row: ProviderRow): void => {
          if (this.departed) {
            return;
          }
          this.providerId = row.id;
          // 新建保存成功二次写入 '' → 新 id（Key 池/模型面板自感知；契约见 ProviderKeysPanel）
          AppStorage.setOrCreate<string>(PROVIDER_EDIT_ID_KEY, row.id);
          saveTailThenPop();
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    } else {
      updateProvider(this.providerId, name, baseUrl, this.protocol, headersJson, this.endpoint,
        bodyJson)
        .then((): void => {
          saveTailThenPop();
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    }
  }

  // 出页不清空编辑对象广播（旧页销毁滞后 pop 转场，与下次进入写入竞态，见入口注释）

  // 余额入口卡数据自拉（只读两列）；lastText 拆分规则 = 末段空格之后是币种（币种缺失整串即金额）
  private loadBalanceEntry(): void {
    queryBalanceState(this.providerId)
      .then((st: BalanceState): void => {
        if (this.departed) {
          return;
        }
        this.balEnabled = st.enabled;
        this.applyBalanceText(st.lastText);
        // 通道初值 = DB 现值（进页 loadEditState 即填充——顶卡余额徽标先显示旧值，查询成功细粒度覆盖）
        this.balanceChannel.set(st.lastText);
      })
      .catch((_e: Object): void => {
        if (this.departed) {
          return;
        }
        this.balEnabled = false;
        this.balAmount = '';
        this.balCurrency = '';
      });
  }

  // lastText → 金额 + 币种（查询成功与载入两处共用，拆分口径单源）
  private applyBalanceText(raw: string): void {
    const text: string = raw.trim();
    const cut: number = text.lastIndexOf(' ');
    if (cut > 0) {
      this.balAmount = text.substring(0, cut);
      this.balCurrency = text.substring(cut + 1);
      return;
    }
    this.balAmount = text;
    this.balCurrency = '';
  }

  // 余额查询（手动键与进页自动查询共用链）。两档差异 = 提示面：手动档三面都 toast（守卫缺配置/
  // 成功/失败，P0-1）；自动档静默（两卡数字可见即反馈，失败保持旧值即信号，缺配置跳过避免噪音），
  // 唯一判据 = 余额开关已启用（开关开着但没填全 = 静默跳过）。链 = 读库态 → 守卫 → 取钥（专用余额
  // Key 优先，空 = 池首启用）→ GET → 组合币种文本 → saveBalanceText → applyBalanceText + 余额
  // 通道写入（顶卡徽标细粒度刷新，卡零重建）。★ 只读配置、只写 balance_last_text——配置列写路径唯一归余额页
  private async queryBalance(auto: boolean): Promise<void> {
    if (this.balanceQuerying) {
      return;
    }
    this.balanceQuerying = true;
    try {
      const state: BalanceState = await queryBalanceState(this.providerId);
      if (this.departed) {
        return;
      }
      // 自动档唯一判据：开关未启用静默跳过（与入口卡「未启用」徽标同口径，不发请求不提示）
      if (auto && !state.enabled) {
        return;
      }
      const resultPath: string = state.resultPath.trim();
      if (resultPath === '') {
        // 自动档缺配置静默跳过（进页每次都弹「请先配置」成噪音）；手动档保持显式提示
        if (!auto) {
          this.getUIContext().getPromptAction().showToast(
            { message: '请先配置「结果 JSON 路径」，或套用模板' });
        }
        return;
      }
      // 端点回退：专用余额端点为空 → 服务 Base URL（本页表单值，与保存语义一致）
      const balBase: string = state.baseUrl.trim();
      const base: string = balBase !== '' ? balBase : this.baseUrl.trim();
      if (base === '') {
        if (!auto) {
          this.getUIContext().getPromptAction().showToast(
            { message: '请先配置「余额 Base URL」或在「配置」页签填写 Base URL' });
        }
        return;
      }
      const dedicated: string = state.key.trim();
      const key: string = dedicated !== '' ? dedicated : await firstEnabledPoolKey(this.providerId);
      if (this.departed) {
        return;
      }
      if (key === '') {
        if (!auto) {
          this.getUIContext().getPromptAction().showToast(
            { message: '请先填写专用余额 Key，或在「配置」页签的密钥池添加 API Key' });
        }
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
      // 落库保留（顶部卡/列表卡读库显示）+ 顶卡余额徽标经通道刷新
      await saveBalanceText(this.providerId, text);
      if (this.departed) {
        return;
      }
      // 自动档成功不弹（两卡数字可见即反馈）；手动档保留显式反馈
      if (!auto) {
        this.getUIContext().getPromptAction().showToast({ message: '已更新余额：' + text });
      }
      // 入口卡大字即时刷新（同一份 result，不重复读库）；顶卡余额徽标经通道刷新（@Track 直驱
      // 徽章行实参位，卡零重建——撤原 headEpoch 自增的整卡重建链，余额防闪笔）
      this.applyBalanceText(text);
      this.balanceChannel.set(text);
    } catch (e) {
      if (this.departed) {
        return;
      }
      // 自动档失败静默（数字保持旧值 = 失败信号）；手动档显式提示（P0-1 不静默）
      if (!auto) {
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      }
    } finally {
      this.balanceQuerying = false;
    }
  }

  // 编辑模型页入口（push 携参，row 为 null = 新建；字面量挂 ModelEditParam 接口——坑59 ①）。
  // onPop 返回即双纪元自增——顶卡计数与模型清单整卡重建重拉（坑16）
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

  // 提示缓存卡（高级页签，v12 列）：仅 anthropic 协议显示（cache_control 仅 Anthropic Messages
  // 规格，OpenAI/Gemini 官方自动缓存无此配置）；开关 + TTL 官方胶囊；草稿态直读 this（坑16 零
  // 值参），随保存键落库
  @Builder
  PromptCacheCard() {
    if (this.protocol === PROTOCOL_ANTHROPIC) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('提示缓存（cache_control）')
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('开启后在请求中标记缓存断点。多轮重复前缀命中缓存后按缓存价计费，写入 1.25 倍，读取 0.1 倍。')
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
      .borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 余额查询入口卡（高级页签首位）。★ 决明「把余额查询改成淡染，略改排版」：
  // ① 底色 = 淡染绿（K2 positive 档；本页仅此一张染色卡，符合「一屏最多一张」硬上限；边框保留）；
  // ② 排版 = 标题 + 状态点徽标 → 大字金额（+ 币种）→ 双键行，操作含义由双键自明；
  // ③ 徽标三态：查到余额 =「可用」（成功档 + 点）、启用但没查过 =「未查询」、未启用 =「未启用」
  //（弱化档不配点——弱化档加点会读成「正在跑」）。双键「配置余额」（次）+「余额查询」（主）双半行、
  // 次左主右，仅编辑态显示；push 携 BalanceConfigParam{providerId}（坑59 ①）+ onPop 自增 headEpoch
  //（坑17：无参 pop 不触发 onPop → 余额页保存返回后顶卡徽章不刷）
  @Builder
  BalanceEntryCard() {
    if (this.providerId !== '') {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text('余额查询')
            .fontSize(CARD_SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          // 用 Blank 占位把徽标推向行尾（不给标题加 layoutWeight——双键各半行的计数是断言面）
          Blank()
          // 三态徽标（if/else 分支切换即重建实例——StatusBadge 入参是普通成员，见其头注释）
          if (this.balAmount !== '') {
            StatusBadge({ text: '可用', tone: BadgeTone.SUCCESS, dot: true })
          } else if (this.balEnabled) {
            StatusBadge({ text: '未查询', tone: BadgeTone.WEAK })
          } else {
            StatusBadge({ text: '未启用', tone: BadgeTone.WEAK })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        // 金额区：大号数字 + 币种小字基线对齐。空态不摆「--」（易读成 0），改给一句指引
        if (this.balAmount !== '') {
          Row({ space: 6 }) {
            Text(this.balAmount)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.balCurrency)
              .fontSize(13)
              .fontColor(cardDescColor())
              .margin({ bottom: 5 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        } else {
          Text(this.balEnabled ? '还没查询过余额。点「查询余额」拉取一次' :
            '未启用余额查询。先在「配置余额」里填查询接口与密钥')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        Row({ space: 10 }) {
          // ★ 白底（2026-11-09 决明点名）：本键坐淡染绿卡面 = 非白卡面，按「按面分叉」
          // 判据取卡外白基；只换 bg 一件，字色 / 材质 / 按压三件与主键零改动
          Button('配置余额')
            .fontSize(14)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBgOffCard(this.contentFallback,
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
              this.queryBalance(false);
            })
        }
        .width('100%')
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      // 淡染绿底 + 左上满染 → 右下渐白（结构与色值单源在 Theme.tintCardGradientColors / tintRgb，
      // 本处只调不写值；backgroundColor 兜底，边框保留作染色卡边界补偿）
      .backgroundColor(tintCardBg(TINT_POSITIVE, this.appColorMode, this.cardAlphaLevel))
      .linearGradient({
        angle: TINT_GRADIENT_ANGLE,
        colors: tintCardGradientColors(TINT_POSITIVE, this.appColorMode, this.cardAlphaLevel)
      })
      .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })
      .borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 页面内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。分段胶囊经 PageShell
  // titleBarBottom 带承载（TopSegmentBand，背板材质在 SegmentBar 内，内容上滑从胶囊下穿过）；
  // 三面板都在滚动层内 = 整页可滚，顶部服务商卡在 Column 首位随滚动
  @Builder
  Content() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        // ── 内容滚动层：顶部留白 = 胶囊位（topPad−8 钳位 0）+ SEGMENT_BAR_HEIGHT + 28
        //（LogPageContent 同款三段构成；短内容顶对齐坑18 + 可拖回弹坑76）──
        Scroll() {
          Column({ space: CARD_SPACING }) {
            // ── 顶部服务商卡（编辑态）：卡内挂载自拉，本页传 providerId + 余额通道实例（content 内
            // @Prop 不随父更新、@ObjectLink 订阅面例外，见 ProviderHeadCard 头注释）；坑16 纪元键
            // ForEach = 获取模型 / 编辑模型页 onPop / 余额配置页 pop 三处触发整卡重建重拉（余额
            // 查询走通道细粒度刷新零重建——纪元键恒单例，通道引用在重建间恒定）──
            if (this.providerId !== '') {
              // 恒单例 ForEach（坑16 口径）
              ForEach([this.headEpoch], (epoch: number) => {
                ProviderHeadCard({
                  providerId: this.providerId,
                  balanceChannel: this.balanceChannel
                })
              }, (epoch: number): string => 'head|' + epoch)
            }
            if (this.segIndex === 0) {
              ProviderConfigPanel({
                name: $name,
                baseUrl: $baseUrl,
                protocol: $protocol,
                endpoint: $endpoint,
                // Key 池启停草稿链：引用 + 上行回调透传（契约见 ProviderToggleDraft 头注释）
                keyDraftRef: this.toggles.keyState(),
                onKeyToggleDraft: (keyId: string, on: boolean): void => {
                  this.toggles.setKey(keyId, on);
                },
                // 取钥方式分段下标（v32；@Link 透传 Key 池卡胶囊——改选只动本页态，保存链尾落库）
                keyPickIdx: $keyPickIdx
                // providerId 经 AppStorage 键订阅（@Prop 链不随父更新，见 ProviderKeysPanel）
              })
            } else if (this.segIndex === 1) {
              // 坑16：纪元键整面板重建——编辑模型页 onPop 后清单重拉（恒单例 ForEach，
              // 面板 aboutToAppear 自 reload）
              ForEach([this.modelsEpoch], (epoch: number) => {
                ProviderModelsPanel({
                  baseUrl: this.baseUrl,
                  protocol: this.protocol,
                  // 行左滑删除互斥组（本页单源下发；Scroll.onScrollStart 统一收口）
                  group: this.swipeGroup,
                  // 模型启停草稿链（统一保存语义，Key 池同款透传姿势）
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
              // ── 高级页签 = 进阶配置（请求头 / Body / 提示缓存 / 余额入口；随整页滚动）──
              Column({ space: CARD_SPACING }) {
                // ── 余额查询入口卡（配置迁 BalanceConfigPage 二级页，本卡为入口；原
                // ProviderBalancePanel 整件退役）。位置在本页签首位、紧跟顶部服务商卡；卡内自带
                // providerId 空判，新建态零渲染 ──
                this.BalanceEntryCard()
                ProviderHeadersPanel({
                  pairs: $headerPairs
                })
                // ── 自定义 Body 卡（v13：headers 同构表单——发送时顶层键覆盖/追加，落库走保存键）──
                ProviderBodyPanel({
                  pairs: $bodyPairs
                })
                // ── 提示缓存卡（v12 列：anthropic 协议才显示；随保存键落库）──
                this.PromptCacheCard()
                // （配置迁移卡 / 价格模板入口卡已退役——入口在服务商管理页标题栏「更多」菜单）
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
        .scrollBar(BarState.Off)
        // 滚动开始即收口行左滑展开态（模型行面板，会话列表同口径）
        .onScrollStart((): void => {
          this.swipeGroup.collapse();
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      // 标题恒「服务商编辑」（新建/编辑统一，常量标题不依赖 providerId 赋值时机）
      title: '服务商编辑',
      // 标题栏下方带承载（分段胶囊唯一承载位）
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      menuHds: providerSaveMenuHds((): void => {
        this.save();
      }),
      // 不传 onShown（顶卡 = 挂载自拉 + 纪元键重建，面板 = 挂载/纪元键重建；列表页 onShown 兜底见
      // ProviderPage）
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
