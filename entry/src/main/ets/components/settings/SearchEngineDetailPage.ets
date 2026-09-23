// 引擎配置三级页（2026-09-10 UI 重构对齐服务商管理：联网搜索列表页点引擎卡 push，param =
// 引擎 id）。卡序 = 启用开关卡 → 当前引擎卡 → API Key 卡（需 key 引擎）→ 接口地址卡 →
// 测试搜索卡，全部即时持久化无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。
// ★ 测试搜索卡（2026-09-10 自「接口地址与测试」卡拆出，决明拍板）：地址卡只留配置项，
//   测试卡 = 验证动作 + 输出，两卡同 struct 故测试卡照读 baseUrlInput（「未保存也能测」的
//   既有语义原样保留）。关键词可编辑，trim 后空则回退默认词；过程信息 = 条数 + 耗时；成功
//   但零条目单独文案（原文案「返回 0 条结果」易被误判成引擎坏了）。结果复用会话页引文卡
//   形态，默认折叠点「查看 N 条结果」展开，点条目开浏览器。
// ★ 测试结果只进组件 @State 内存态：不落盘、不进消息、不进历史、不写任何偏好键，离页即忘
//   ——故本功能无需接入存储管理页（官方「清理范围 = 统计范围」口径下本功能不产生统计条目）。
// ★ 折叠键的两个分支各建各的（展开态才挂结果区，两种标签与两种点击行为也不相同——保留
//   if 分支切换的键变重建形态，零新增范式）。
// ★ 刷新链与服务商管理详情页的差别：偏好四键走 AppStorage（@StorageLink），列表页订阅同键
// 即时互刷，无需 onPop 重拉。param 解析 = MemoryEditPage 同款守卫（getParamByName 取末个，
// null/非串/未知 id → 引擎定位空串，页面显示「引擎不存在」提示不 pop——aboutToAppear 内
// pop 有竞态风险）。引擎描述符字段进页一次定值存普通成员（@Builder 内禁局部变量，禁非空
// 断言——取值面收敛到成员位）。
// 语义（2026-09-10 决明拍板解耦）：启用开关 = 是否参与（含回退候选）；「设为当前」独立操作，
// 不顺手改开关——当前引擎被停用或未配置密钥时对话自动回退其他已启用引擎（resolveEngineId）。
// 明文红线：API Key 明文只进 Asset（KeyStore.saveSearchEngineKey 族），保存即清空输入框、
// 界面只显示已·未配置标记；明文不进日志/toast。
// 表单形制：卡标题即字段标签（标签在上 + 整宽输入框，ProviderConfigPanel.FieldInput 同构）；
// 说明小字在按钮上方（功能设置卡布局次序条）；**键形制两分（2026-09-10 决明指令「四键撑满
// 卡片改蓝底」）**——主操作键 = 通宽 + `fallbackButton*` primary 四件套（保存密钥 / 保存地址 /
// 测试搜索 / 设为当前引擎，功能模型页「选择模型」同形，占卡内主操作位）；行内次钮 = 内容宽 +
// 非 primary 四件套（清除密钥 / 结果折叠键——次级与展开动作不入主操作位）；★ **InlineBtn 入参
// 走按引用传递**（单参 + 对象字面量直传——见 InlineBtnOpts 注释；值参形态下 `.enabled()` 恒取
// 首帧值，本页键置灰自初版起从未真生效，2026-09-10 改造）；卡内边距 16 与
// ProviderConfigPanel/ProviderPage 卡同款（2026-09-10 自检轮对齐，原 14 无理由偏差）；
// 卡宽一律 CARD_PANEL_WIDTH（全宽占位卡同修，见 Content 内注释）；文案守「面向用户文案写作规约」。
import { ConfigurationConstant, Want, common } from '@kit.AbilityKit';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY,
  PREF_SEARCH_ENGINE_KEY } from '../../common/AppPreferences';
import { SEARCH_ENGINES, SearchEngineDescriptor, EngineCfgEntry, parseEngineCfg,
  searchHandlerOf, serializeEngineCfg } from '../../common/search/SearchEngineRegistry';
import { SearchEngineRuntime } from '../../common/search/ApiSearchEngines';
import { SEARCH_RESULT_COUNT_DEFAULT } from '../../common/search/SearchLimits';
import { loadSearchEngineKey, removeSearchEngineKey, saveSearchEngineKey } from '../../common/store/KeyStore';
import { WebSearchOutcome } from '../../common/providers/WebSearch';
import { BingResultItem } from '../../common/providers/WebSearchParse';
import { ROUTE_SEARCH_ENGINE_DETAIL_PAGE } from '../../common/RouteNames';

// 默认测试关键词（短且结果稳定，几乎不耗配额）——关键词输入框留空时回退用它，输入框
// placeholder 即显示此词（用户看到的提示词就是将要发出的词）
const TEST_QUERY: string = '华为 HarmonyOS';

// InlineBtn 入参（**按引用传递**，2026-09-10 自四参值参改造）——官方《@Builder装饰器：自定义
// 构建函数》参数传递规则：「按引用传递只在传入一个参数且该参数直接传入对象字面量时生效」，
// 是「状态变量改变引起 @Builder 内 UI 刷新」的两种形态之一（另一种 = UIUtils.makeBinding）；
// 值参快照下 `.enabled()` 恒取首帧值——本页键置灰自初版起就没真生效过（自检报告 O-3，本笔收口）。
// ★ 参数类型用 class 而非 interface：官方样例（指南与 FAQ faqs-arkui-1078）一律以 class 承载
//   按引用传递，照官方形态不自行变体；★ 调用点必须直传对象字面量（传变量或加第二个参数都退回
//   按值传递，sse-assert 留钉）；★ 字段全部给默认值仅因 ArkTS 要求类字段初始化——对象字面量
//   仍须补齐全四字段（缺一个即编译错），故不存在「漏传 onTap 点键无反应」的静默失败面。
class InlineBtnOpts {
  label: string = '';
  enabled: boolean = true;
  primary: boolean = false;
  onTap: () => void = (): void => {};
}

@Component
export struct SearchEngineDetailPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 偏好三键（启停/当前引擎/引擎配置——与列表页订阅同键，写这里列表即时回流；注册默认见
  // EntryAbility，本处默认值仅键缺失时生效，取降级安全值〔['bing_local'] = 免 key 引擎可用〕）
  @StorageLink(PREF_SEARCH_ENGINE_KEY) currentEngine: string = 'bing_local';
  @StorageLink(PREF_SEARCH_ENABLED_ENGINES_KEY) enabledEngines: string[] = ['bing_local'];
  @StorageLink(PREF_SEARCH_ENGINE_CFG_KEY) cfgJson: string = '';
  // 引擎定位与描述符字段（aboutToAppear 一次定值；engineId 空 = param 异常，页面显示占位）
  private engineId: string = '';
  private pageTitle: string = '搜索引擎';
  private needKey: boolean = false;
  private defaultBaseUrl: string = '';
  // key 形态提示（描述符 keyHint 消费点：拼进密钥输入框 placeholder，如「粘贴 API Key，sk- 开头」
  // ——申请时先自查格式；空串 = 该引擎无公开前缀约定，placeholder 回退通用文案）
  private keyHint: string = '';
  // 当前引擎配置区输入态（key 输入保存即清空——明文不留输入框）
  @State keyInput: string = '';
  @State baseUrlInput: string = '';
  @State baseUrlStatus: string = ''; // 地址卡状态行（自 testStatus 分出——测试独立成卡后两卡各有状态位）
  @State queryInput: string = '';    // 测试关键词（离页即忘，不写任何键）
  @State testing: boolean = false;
  @State testStatus: string = '';
  @State testRefs: BingResultItem[] = []; // 测试返回条目（内存态，不落盘不进历史）
  @State resultExpanded: boolean = false; // 结果区展开态（默认折叠，点「查看 N 条结果」展开）
  @State keyStatus: string = '';
  @State working: boolean = false; // 密钥保存/清除进行中（防重入）

  aboutToAppear(): void {
    // param 解析（MemoryEditPage 同款守卫：getParamByName 取末个，非串一律空）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_SEARCH_ENGINE_DETAIL_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const id: string = typeof last === 'string' ? last : '';
    const desc: SearchEngineDescriptor | undefined = SEARCH_ENGINES.find(
      (e: SearchEngineDescriptor): boolean => e.id === id);
    if (desc === undefined) {
      return; // 未知 id：引擎定位留空，build 显示「引擎不存在」占位（aboutToAppear 内 pop 有竞态）
    }
    this.engineId = id;
    this.pageTitle = desc.label;
    this.needKey = desc.requiresApiKey;
    this.defaultBaseUrl = desc.defaultBaseUrl;
    this.keyHint = desc.keyHint;
    this.syncConfigInputs();
  }

  // 配置表输入框回填（进页时对齐已存值；key 输入恒空——明文不回显）
  private syncConfigInputs(): void {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(this.engineId);
    this.baseUrlInput = entry !== undefined ? entry.baseUrl : '';
    this.keyInput = '';
    this.keyStatus = '';
    this.baseUrlStatus = '';
    this.testStatus = '';
    this.testRefs = [];
    this.resultExpanded = false;
  }

  private isEnabled(): boolean {
    return this.enabledEngines.includes(this.engineId);
  }

  private hasKeyMarked(): boolean {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(this.engineId);
    return entry !== undefined && entry.hasKey;
  }

  // 启用开关（替换整数组保证 @StorageLink 响应；停用当前引擎允许——resolve 链自动回退）
  private toggleEnabled(isOn: boolean): void {
    if (isOn) {
      if (!this.isEnabled()) {
        this.enabledEngines = this.enabledEngines.concat([this.engineId]);
      }
    } else {
      this.enabledEngines = this.enabledEngines.filter((id: string): boolean => id !== this.engineId);
    }
  }

  // 设为当前引擎（独立操作，不动启用开关；对话固定走当前引擎，停用/缺钥时自动回退）
  private setCurrentEngine(): void {
    if (this.engineId === '' || this.engineId === this.currentEngine) {
      return;
    }
    this.currentEngine = this.engineId;
    this.getUIContext().getPromptAction().showToast({ message: '已设为当前引擎' });
  }

  // 引擎配置整键覆盖写（JSON 串结构化键规矩——AppPreferences 立规：读经 parse、写经
  // serialize 整键覆盖，禁局部拼串）
  private writeCfg(patch: EngineCfgEntry): void {
    const map: Map<string, EngineCfgEntry> = parseEngineCfg(this.cfgJson);
    map.set(this.engineId, patch);
    this.cfgJson = serializeEngineCfg(map);
  }

  private entryOf(): EngineCfgEntry {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(this.engineId);
    return entry !== undefined ? entry : { baseUrl: '', hasKey: false };
  }

  // 保存密钥：Asset 写明文 + 偏好写 hasKey 标记；输入框即清（明文不留 UI）；明文不进 toast
  private saveKey(): void {
    if (this.working || this.testing) {
      return;
    }
    const key: string = this.keyInput.trim();
    if (key === '') {
      this.keyStatus = '请先输入 API Key 再保存';
      return;
    }
    this.working = true;
    saveSearchEngineKey(this.engineId, key)
      .then((): void => {
        this.writeCfg({ baseUrl: this.entryOf().baseUrl, hasKey: true });
        this.keyInput = '';
        this.keyStatus = '密钥已保存，已加密存入系统安全区';
      })
      .catch((e: Object): void => {
        this.keyStatus = '保存失败：' + (e as Error).message;
      })
      .finally((): void => {
        this.working = false;
      });
  }

  // 清除密钥：Asset 删条目 + 偏好清 hasKey 标记（幂等）
  private clearKey(): void {
    if (this.working || this.testing) {
      return;
    }
    this.working = true;
    removeSearchEngineKey(this.engineId)
      .then((): void => {
        this.writeCfg({ baseUrl: this.entryOf().baseUrl, hasKey: false });
        this.keyStatus = '密钥已清除';
      })
      .catch((e: Object): void => {
        this.keyStatus = '清除失败：' + (e as Error).message;
      })
      .finally((): void => {
        this.working = false;
      });
  }

  // 保存自定义入口地址（留空 = 默认官方入口；此处只存地址，即时生效）
  private saveBaseUrl(): void {
    if (this.working || this.testing) {
      return;
    }
    const baseUrl: string = this.baseUrlInput.trim().replace(/\/+$/, '');
    this.writeCfg({ baseUrl: baseUrl, hasKey: this.entryOf().hasKey });
    this.baseUrlInput = baseUrl;
    this.baseUrlStatus = baseUrl === '' ? '已恢复默认地址' : '地址已保存';
  }

  // 测试搜索：不经偏好 fallback 链直测本引擎（KeyConnectTester「表单当前值验证」同语义
  // ——baseUrl 用输入框当前值〔未保存也能测〕，key 用 Asset 已存值）。关键词取输入框，
  // 留空回退默认词；耗时从发起量到返回（不含密钥读取——量的是引擎本身响应速度）
  private runTest(): Promise<void> | void {
    if (this.testing || this.working) {
      return;
    }
    // 状态行与结果区同源于**同一次**测试——进入即清上一轮（含下面各早退路径），否则会出现
    //「状态行说请先保存密钥、下面还挂着上一轮结果」的错配（可达路径：出结果后清除密钥再测 /
    // Asset 读取失败）
    this.testRefs = [];
    this.resultExpanded = false;
    const handler: ((query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>) | undefined =
      searchHandlerOf(this.engineId);
    if (handler === undefined) {
      this.testStatus = '搜索引擎不可用';
      return;
    }
    // 条数恒用默认值（2026-09-10 搜索条数助手级可调）：本页是直测引擎的调试入口，不属于
    // 任何助手、也不经 dispatchSearch 的中转键读取——与「未配置助手」同口径，结果条数
    // 恒 = SEARCH_RESULT_COUNT_DEFAULT(5)
    const ctx: SearchEngineRuntime = {
      apiKey: '', baseUrl: this.baseUrlInput.trim(),
      resultCount: SEARCH_RESULT_COUNT_DEFAULT
    };
    const query: string = this.queryInput.trim() === '' ? TEST_QUERY : this.queryInput.trim();
    // ★ testing 在**异步读密钥之前**置位——否则 Asset 读取窗口内的二次点击绕过防重入守卫，
    //   造成两次真实请求（付费引擎消耗两次额度）且状态与结果互相覆盖。下方两条早退路径各自
    //   归位 testing=false，与 doTest 的 finally 合成完整闭环
    this.testing = true;
    const doTest = (): Promise<void> => {
      this.testStatus = '正在测试搜索…';
      const startedAt: number = Date.now();
      return handler(query, ctx)
        .then((out: WebSearchOutcome): void => {
          const costMs: number = Date.now() - startedAt;
          if (!out.success) {
            this.testStatus = '测试失败：' + out.errorMessage;
            return;
          }
          this.testRefs = out.references;
          if (out.references.length === 0) {
            // 成功但零条目单独文案（原文案「返回 0 条结果」易被误判成引擎坏了）
            this.testStatus = `测试成功，但没有返回任何结果，耗时 ${costMs} ms。换个更具体的词试试`;
          } else {
            this.testStatus = `测试成功，返回 ${out.references.length} 条结果，耗时 ${costMs} ms`;
          }
        })
        .catch((e: Object): void => {
          this.testStatus = '测试失败：' + (e as Error).message;
        })
        .finally((): void => {
          this.testing = false;
        });
    };
    if (this.needKey) {
      return loadSearchEngineKey(this.engineId)
        .then((plain: string): Promise<void> | void => {
          if (plain === '') {
            this.testStatus = '请先保存 API Key 再测试';
            this.testing = false;
            return;
          }
          ctx.apiKey = plain;
          return doTest();
        })
        .catch((e: Object): void => {
          this.testStatus = '密钥读取失败：' + (e as Error).message;
          this.testing = false;
        });
    }
    return doTest();
  }

  // 开浏览器（与会话页引文卡同一 want 形态；getHostContext 走 UIContext 形态，非全局 getContext）
  private openRefUrl(url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
        entities: ['entity.system.browsable']
      };
      (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility(want);
    } catch (e) {
      // 静默（无可处理浏览器的边缘形态——与会话页引文卡同口径）
    }
  }

  // 结果引文卡（复用会话页 ChatMessageItem 引文卡形态：编号 + 标题 + 摘要 + URL，点行开
  // 浏览器——两处观感一致，零新范式；条数 ≤ 默认 5 条〔本页测试搜索恒用默认条数，会话侧
  // 才由助手级 searchResultCount 决定〕天然有界，无需分页）
  @Builder
  ResultList(refs: BingResultItem[]) {
    Text('来源')
      .fontSize(11)
      .fontColor(cardTitleColor())
      .width('100%')
    ForEach(refs, (ref: BingResultItem): void => {
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(String(ref.index))
            .fontSize(11)
            .fontColor(cardDescColor())
            .constraintSize({ minWidth: 16 })
          Text(ref.title !== '' ? ref.title : ref.url)
            .fontSize(13)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        if (ref.snippet !== '') {
          Text(ref.snippet)
            .fontSize(11)
            .fontColor(cardDescColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Text(ref.url)
          .fontSize(10)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .onClick((): void => {
        if (ref.url !== '') {
          this.openRefUrl(ref.url);
        }
      })
    }, (ref: BingResultItem): string => ref.url + '#' + ref.index)
  }

  // 行内文字键 / 主操作键两形制（fallbackButton 四件套双态——内容区组件；DataSyncPage.ActionBtn
  // 同款两分支写法）：primary=false = 内容宽次钮（清除密钥类灰底键）；primary=true = **通宽主键**
  //（官方强调蓝 + 恒白字，功能模型页「选择模型」/ 数据同步页「导出备份到本机」同形）——
  // 2026-09-10 决明指令「4 键撑满卡片改蓝底」。通宽许可依据：规范-列表卡片与组卡 §4.3
  //「通宽按钮只许出现在卡内还有其他内容的语境」，本页四卡均带标题 + 说明 + 输入框，符合。
  // ★ 单参对象字面量 = 按引用传递（见 InlineBtnOpts 注释）：`.enabled(opts.enabled)` 读的是入参
  //   属性，父状态变化时才随 Builder 重执行刷新；改成多个参数或把 enabled 提成闭包变量即失效。
  @Builder
  InlineBtn(opts: InlineBtnOpts) {
    if (opts.primary) {
      Button(opts.label)
        .width('100%')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(opts.enabled)
        .onClick((): void => {
          opts.onTap();
        })
    } else {
      Button(opts.label)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(opts.enabled)
        .onClick((): void => {
          opts.onTap();
        })
    }
  }

  build() {
    PageShell({
      title: this.pageTitle,
      content: (): void => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        if (this.engineId === '') {
          // 未知引擎占位（param 异常守卫——不 pop，用户返回键自然退出；卡宽走 CARD_PANEL_WIDTH
          // 与全应用卡齐平——2026-09-10 决明「占位卡怎么又是全宽」全宽卡治理）
          Text('引擎不存在或已变更，请返回列表重试')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
            .padding(24)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(16)
        } else {
          // ── 启用开关卡（停用 = 不参与对话搜索与自动回退——付费引擎的费用闸；isEnabled
          //    读 @StorageLink 响应式，无需纪元键）──
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text('启用引擎')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('停用后不参与对话搜索与自动回退')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.isEnabled() })
              .onChange((isOn: boolean): void => {
                this.toggleEnabled(isOn);
              })
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(VerticalAlign.Center)
          // ── 当前引擎卡（设为当前独立操作，不顺手改开关）──
          Column({ space: 10 }) {
            Text('当前引擎')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('对话固定使用当前引擎。当前引擎停用或未配置密钥时，自动改用已启用引擎中第一个配置完整的，都没有时回 Bing。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            Text(this.engineId === this.currentEngine ? '当前使用中' : '未设为当前')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            this.InlineBtn({
              label: '设为当前引擎',
              enabled: this.engineId !== this.currentEngine && !this.working,
              primary: true,
              onTap: (): void => {
                this.setCurrentEngine();
              }
            })
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          // ── API Key 卡（仅需 key 的引擎；保存即清输入，已配置时追加清除键）──
          if (this.needKey) {
            Column({ space: 10 }) {
              Text('API Key')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('密钥在引擎官网申请，加密保存在本机，不会上传。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              TextInput({ text: this.keyInput,
                placeholder: this.keyHint === '' ? '粘贴 API Key' : '粘贴 API Key，' + this.keyHint })
                .fontSize(14)
                .type(InputType.Password)
                .width('100%')
                .onChange((text: string): void => {
                  this.keyInput = text;
                })
              // 状态行：已配置/未配置 + 清除键（清除是密钥的次级破坏性动作，留在状态行做内容宽
              // 次钮，不随四主键通宽蓝底——通宽蓝底 = 主操作语义，两者不可混）
              Row({ space: 10 }) {
                Text(this.hasKeyMarked() ? '已配置' : '未配置')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .layoutWeight(1)
                if (this.hasKeyMarked()) {
                  this.InlineBtn({
                    label: '清除密钥',
                    enabled: !this.working && !this.testing,
                    primary: false,
                    onTap: (): void => {
                      this.clearKey();
                    }
                  })
                }
              }
              .width('100%')
              // 主操作键置卡底（通宽蓝底——功能模型页「选择模型」位序同款）
              this.InlineBtn({
                label: '保存密钥',
                enabled: !this.working && !this.testing,
                primary: true,
                onTap: (): void => {
                  this.saveKey();
                }
              })
              if (this.keyStatus !== '') {
                Text(this.keyStatus)
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)
          }
          // ── 接口地址卡（地址留空 = 默认官方入口；测试已拆独立卡，本卡只留配置职责）──
          Column({ space: 10 }) {
            Text('接口地址')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('一般保持默认，使用中转服务时才需要修改。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextInput({ text: this.baseUrlInput,
              placeholder: this.defaultBaseUrl === '' ? '留空则默认 Bing 官方入口' :
              `留空则默认 ${this.defaultBaseUrl}` })
              .fontSize(14)
              .width('100%')
              .onChange((text: string): void => {
                this.baseUrlInput = text;
              })
            this.InlineBtn({
              label: '保存地址',
              enabled: !this.working && !this.testing,
              primary: true,
              onTap: (): void => {
                this.saveBaseUrl();
              }
            })
            if (this.baseUrlStatus !== '') {
              Text(this.baseUrlStatus)
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          // ── 测试搜索卡（关键词可编辑 + 测试键 + 过程信息 + 结果引文卡〔默认折叠〕）──
          Column({ space: 10 }) {
            Text('测试搜索')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('留空则用默认关键词测试。测试会真实发起一次搜索，付费引擎消耗一次搜索额度。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextInput({ text: this.queryInput, placeholder: TEST_QUERY })
              .fontSize(14)
              .width('100%')
              .onChange((text: string): void => {
                this.queryInput = text;
              })
            // 主操作键通宽蓝底（四主键之一）
            this.InlineBtn({
              label: '测试搜索',
              enabled: !this.working && !this.testing,
              primary: true,
              onTap: (): void => {
                this.runTest();
              }
            })
            if (this.testStatus !== '') {
              Text(this.testStatus)
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            // 折叠键两分支各建各的（展开态才挂结果区，标签与点击行为也随态变）；
            // 属次级展开动作非主操作，保持内容宽灰底次钮
            if (this.testRefs.length > 0 && !this.resultExpanded) {
              this.InlineBtn({
                label: `查看 ${this.testRefs.length} 条结果`,
                enabled: true,
                primary: false,
                onTap: (): void => {
                  this.resultExpanded = true;
                }
              })
            }
            if (this.testRefs.length > 0 && this.resultExpanded) {
              this.InlineBtn({
                label: '收起结果',
                enabled: true,
                primary: false,
                onTap: (): void => {
                  this.resultExpanded = false;
                }
              })
              this.ResultList(this.testRefs)
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
