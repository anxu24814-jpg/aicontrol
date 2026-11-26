// 引擎配置三级页：联网搜索列表页点引擎卡 push，param = 引擎 id。卡序 =（子引擎卡〔如有〕→）
// API Key 卡（需 key 引擎）→ 接口地址卡 → 测试搜索卡（→ 测试抓取卡〔如有〕），全部即时持久化、
// 无保存动作 → 返回无参 pop 不挂 onPop（坑17）。★ 原「启用开关卡」（与列表页行尾开关重复）与
//「当前引擎卡」整卡退役——启停唯一控制面 = 列表页行尾开关；全局当前引擎唯一设置面 = 对话页
//「更多」菜单「联网」项选引擎（ChatSessionOverrideCtrl.pickWebEngine）；停用/缺钥时运行时
// resolveEngineId 自动回退。
// ★ 测试搜索卡（决明拍板自「接口地址与测试」卡拆出）：地址卡只留配置项，测试卡 = 验证动作 +
//   输出，两卡同 struct 故测试卡照读 baseUrlInput（「未保存也能测」语义保留）。关键词可编辑，
//   trim 后空则回退默认词；过程信息 = 条数 + 耗时；成功但零条目单独文案（「返回 0 条结果」易被
//   误判成引擎坏了）。结果复用会话页引文卡形态，默认折叠，点条目开浏览器。
// ★ 测试结果只进组件 @State 内存态：不落盘、不进消息、不进历史、不写任何偏好键，离页即忘——
//   故无需接入存储管理页（官方「清理范围 = 统计范围」口径下不产生统计条目）。
// ★ 折叠键的两个分支各建各的（展开态才挂结果区，标签与点击行为也随态变——键变重建形态）。
// ★ 刷新链：偏好键走 AppStorage（@StorageLink），列表页订阅同键即时互刷，无需 onPop 重拉。
//   param 解析 = getParamByName 取末个，null/非串/未知 id → 空串，页面显「引擎不存在」不 pop
//（aboutToAppear 内 pop 有竞态）。描述符字段进页一次定值存普通成员（@Builder 内禁局部变量、
//   禁非空断言）。
// ★ 明文红线：API Key 明文只进 Asset（KeyStore.saveSearchEngineKey 族），保存即清空明文；已配置
//   且非更换态以只读掩码展示（非真实密钥、不可反推），右上角显配置状态徽标；长按掩码经自定义文本
//   菜单复制 Asset 真钥，明文不进日志/toast；「更换密钥」显式切回空输入框，避免掩码与输入混排。
// ★ 表单形制：卡标题即字段标签（标签在上 + 整宽输入框）；说明小字在按钮上方；子引擎四档用选项
//   宫格 OptionTileGrid（副行带单次价格，规范 §4.13），密钥状态用四档 StatusBadge（已配置 = 成功档、
//   未配置 = 弱化档）。键形制两分：主操作键 = 通宽 + fallbackButton* primary 四件套；行内次钮 =
//   内容宽非 primary 四件套；清除密钥为蓝色裸字。★ InlineBtn 入参走按引用传递（单参 + 对象字面量
//   直传，见 InlineBtnOpts；值参形态下 .enabled() 恒取首帧值）。卡内边距 16 与 Provider 系卡同款，
//   卡宽一律 CARD_PANEL_WIDTH；文案守「面向用户文案写作规约」。
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { OptionTileGrid } from '../OptionTileGrid';
import { copyTextToClipboard } from '../../common/Clipboard';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted,
  fallbackButtonFont, fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted,
  fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { PREF_SEARCH_ENGINE_CFG_KEY } from '../../common/AppPreferences';
import { SEARCH_ENGINES, SearchEngineDescriptor, EngineCfgEntry, EngineVariantOption,
  ScrapeHandler, parseEngineCfg, searchHandlerOf, scrapeHandlerOf, serializeEngineCfg }
  from '../../common/search/SearchEngineRegistry';
import { SearchEngineRuntime } from '../../common/search/ApiSearchEngines';
import { SEARCH_RESULT_COUNT_DEFAULT } from '../../common/search/SearchLimits';
import { loadSearchEngineKey, removeSearchEngineKey, saveSearchEngineKey } from '../../common/store/KeyStore';
import { WebFetchOutcome, WebSearchOutcome } from '../../common/providers/WebSearch';
import { BingResultItem } from '../../common/providers/WebSearchParse';
import { ROUTE_SEARCH_ENGINE_DETAIL_PAGE } from '../../common/RouteNames';
import { launchExternalLink } from '../../common/ExternalLink';

// 默认测试关键词（短且结果稳定，几乎不耗配额）——留空时回退，placeholder 即显示此词
const TEST_QUERY: string = '华为 HarmonyOS';

// 默认测试抓取地址（稳定公开页、正文简短，几乎不耗配额）——URL 留空时回退，placeholder 即显示
const TEST_FETCH_URL: string = 'https://example.com';

// 已配置密钥的输入框回显：固定圆点串，非真实密钥、不可反推。保存后明文即清；聚焦让位 placeholder，
// 失焦且未输入时恢复
const KEY_MASK_TEXT: string = '••••••••••••';

// InlineBtn 入参（**按引用传递**——官方《@Builder装饰器》「单参且直接传对象字面量才按引用」，
// 是状态变量驱动 @Builder 内 UI 刷新的形态之一；值参快照下 .enabled() 恒取首帧值，本页键置灰
// 自初版起从未真生效）。★ 参数类型用 class 而非 interface（官方样例一律 class）；★ 调用点必须
// 直传对象字面量（传变量或加第二参退回按值传递，sse-assert 留钉）；字段默认值仅为满足 ArkTS
// 初始化要求——对象字面量仍须补齐全四字段，故不存在漏传 onTap 的静默失败面。
class InlineBtnOpts {
  label: string = '';
  enabled: boolean = true;
  primary: boolean = false;
  tinted: boolean = false;
  onTap: () => void = (): void => {};
}

@Component
export struct SearchEngineDetailPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 引擎配置键（@StorageLink，与列表页订阅同键写即回流；注册默认见 EntryAbility。★ 原启停/当前
  // 引擎两枚 @StorageLink 随两卡退役——启停唯一控制面 = 列表页行尾开关）
  @StorageLink(PREF_SEARCH_ENGINE_CFG_KEY) cfgJson: string = '';
  // 引擎定位与描述符字段（aboutToAppear 一次定值；engineId 空 = param 异常，页面显示占位）
  private engineId: string = '';
  private pageTitle: string = '搜索引擎';
  private needKey: boolean = false;
  private defaultBaseUrl: string = '';
  // key 形态提示（拼进密钥输入框 placeholder；空串 = 无前缀约定，回退通用文案）
  private keyHint: string = '';
  // 抓取能力与子引擎（aboutToAppear 一次定值——能力/选项表来自描述符）
  private canScrape: boolean = false;
  private defaultVariant: string = '';
  private variantOptions: EngineVariantOption[] = [];
  // 选项宫格三组入参（@Builder 内禁局部变量——进页一次派生；labels / subLabels / values 与
  // variants 一一对应）
  private variantLabels: string[] = [];
  private variantSubLabels: string[] = [];
  private variantValues: string[] = [];
  // 当前引擎配置区输入态（key 明文只在更换态输入，保存即清空；已配置且非更换态以只读掩码展示）
  @State keyInput: string = '';
  // 密钥更换态：false = 已配置且只读掩码；true = 空输入框待输入。未配置时恒显示输入框（showKeyInput）
  @State keyEditing: boolean = false;
  @State baseUrlInput: string = '';
  @State baseUrlStatus: string = ''; // 地址卡状态行（自 testStatus 分出——测试独立成卡后两卡各有状态位）
  @State queryInput: string = '';    // 测试关键词（离页即忘，不写任何键）
  @State testing: boolean = false;
  @State testStatus: string = '';
  @State testRefs: BingResultItem[] = []; // 测试返回条目（内存态，不落盘不进历史）
  @State resultExpanded: boolean = false; // 结果区展开态（默认折叠，点「查看 N 条结果」展开）
  @State keyStatus: string = '';
  @State working: boolean = false; // 密钥保存/清除进行中（防重入）
  // 子引擎选择态（进页从配置回填，点行即落盘——本页无保存动作口径）
  @State variantInput: string = '';
  // 测试抓取三态（仅 canScrape 引擎渲染测试卡——结果只进内存态，不落盘、不写偏好键，离页即忘）
  @State fetchUrlInput: string = '';
  @State fetchTesting: boolean = false;
  @State fetchStatus: string = '';

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
    this.canScrape = desc.canScrape;
    this.defaultVariant = desc.defaultVariant;
    this.variantOptions = desc.variants;
    this.variantLabels = desc.variants.map((opt: EngineVariantOption): string => opt.label);
    this.variantSubLabels = desc.variants.map((opt: EngineVariantOption): string => opt.desc);
    this.variantValues = desc.variants.map((opt: EngineVariantOption): string => opt.id);
    this.syncConfigInputs();
  }

  // 配置表输入框回填（进页时对齐已存值；key 输入恒空——明文不回显）
  private syncConfigInputs(): void {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(this.engineId);
    this.baseUrlInput = entry !== undefined ? entry.baseUrl : '';
    // 子引擎回填：配置值优先，空则描述符缺省
    this.variantInput = entry !== undefined && entry.variant !== '' ?
      entry.variant : this.defaultVariant;
    this.keyInput = '';
    this.keyEditing = false;
    this.keyStatus = '';
    this.baseUrlStatus = '';
    this.testStatus = '';
    this.testRefs = [];
    this.resultExpanded = false;
    this.fetchUrlInput = '';
    this.fetchStatus = '';
  }

  private hasKeyMarked(): boolean {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(this.engineId);
    return entry !== undefined && entry.hasKey;
  }

  // 密钥区形态：未配置恒显示输入框；已配置时只有「更换密钥」才切输入框，其余只读掩码展示——掩码
  // 与输入不混排，长按复制不会触发聚焦清空
  private showKeyInput(): boolean {
    return this.keyEditing || !this.hasKeyMarked();
  }

  // 只读掩码的长按文本菜单：保留系统「复制」项并拦截其点击——复制的是 Asset 里的真实密钥，不是
  // 屏幕上的假圆点；其余菜单项原样放行
  private keyEditMenu: EditMenuOptions = {
    onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> => menuItems,
    onMenuItemClick: (menuItem: TextMenuItem, _range: TextRange): boolean => {
      if (menuItem.id.equals(TextMenuItemId.COPY)) {
        this.copyStoredKey();
        return true;
      }
      return false;
    }
  };

  // 长按复制：Asset 读明文 → 单源 Clipboard 写系统剪贴板 → 明文即弃；不进状态/日志/toast
  private copyStoredKey(): void {
    if (this.engineId === '') {
      return;
    }
    loadSearchEngineKey(this.engineId)
      .then((plain: string): void => {
        if (this.departed) {
          return;
        }
        if (plain === '') {
          this.getUIContext().getPromptAction().showToast({ message: '明文缺失，无法复制' });
          return;
        }
        copyTextToClipboard(this.getUIContext(), plain, '密钥已复制');
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '密钥读取失败：' + (e as Error).message });
      });
  }

  // 更换密钥：清掉未保存输入并切到空输入框；取消则原样回只读掩码展示
  private beginKeyEdit(): void {
    this.keyInput = '';
    this.keyEditing = true;
    this.keyStatus = '';
  }

  private cancelKeyEdit(): void {
    this.keyInput = '';
    this.keyEditing = false;
    this.keyStatus = '';
  }

  // 引擎配置整键覆盖写（读经 parse、写经 serialize 整键覆盖，禁局部拼串）
  private writeCfg(patch: EngineCfgEntry): void {
    const map: Map<string, EngineCfgEntry> = parseEngineCfg(this.cfgJson);
    map.set(this.engineId, patch);
    this.cfgJson = serializeEngineCfg(map);
  }

  private entryOf(): EngineCfgEntry {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(this.engineId);
    return entry !== undefined ? entry :
      { baseUrl: '', hasKey: false, variant: this.defaultVariant };
  }

  // 子引擎选择：点行即落盘（与全页「即时持久化」口径一致），值经配置 JSON 的 variant 字段承载
  private selectVariant(variantId: string): void {
    if (this.variantInput === variantId) {
      return;
    }
    this.variantInput = variantId;
    this.writeCfg({
      baseUrl: this.entryOf().baseUrl, hasKey: this.entryOf().hasKey, variant: variantId
    });
  }

  // 保存密钥：Asset 写明文 + 偏好写 hasKey 标记；保存后清空明文、切回只读掩码；明文不进 toast
  private saveKey(): void {
    if (this.working || this.testing) {
      return;
    }
    const key: string = this.keyInput.trim();
    if (key === '') {
      // 已配置时掩码在视觉上“有内容”，但 keyInput 为空——提示说清不会覆写已有密钥
      this.keyStatus = this.hasKeyMarked() ? '密钥已配置，粘贴新密钥再保存' :
        '请先输入 API Key 再保存';
      return;
    }
    this.working = true;
    saveSearchEngineKey(this.engineId, key)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.writeCfg({ baseUrl: this.entryOf().baseUrl, hasKey: true,
          variant: this.variantInput });
        this.keyInput = '';
        this.keyEditing = false;
        this.keyStatus = '密钥已保存，已加密存入系统安全区';
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.keyStatus = '保存失败：' + (e as Error).message;
      })
      .finally((): void => {
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
        this.writeCfg({ baseUrl: this.entryOf().baseUrl, hasKey: false,
          variant: this.variantInput });
        // 清除后掩码随 hasKeyMarked() 变假而消失；顺带清掉可能存在的未保存输入
        this.keyInput = '';
        this.keyEditing = false;
        this.keyStatus = '密钥已清除';
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.keyStatus = '清除失败：' + (e as Error).message;
      })
      .finally((): void => {
        if (this.departed) {
          return;
        }
        this.working = false;
      });
  }

  // 保存自定义入口地址（留空 = 默认官方入口；此处只存地址，即时生效）
  private saveBaseUrl(): void {
    if (this.working || this.testing) {
      return;
    }
    const baseUrl: string = this.baseUrlInput.trim().replace(/\/+$/, '');
    this.writeCfg({ baseUrl: baseUrl, hasKey: this.entryOf().hasKey,
      variant: this.variantInput });
    this.baseUrlInput = baseUrl;
    this.baseUrlStatus = baseUrl === '' ? '已恢复默认地址' : '地址已保存';
  }

  // 测试搜索：不经偏好 fallback 链直测本引擎（baseUrl 用输入框当前值〔未保存也能测〕，key 用
  // Asset 已存值）；关键词留空回退默认词；耗时从发起量到返回（不含密钥读取）
  private runTest(): Promise<void> | void {
    if (this.testing || this.working) {
      return;
    }
    // 状态行与结果区同源于**同一次**测试——进入即清上一轮（含各早退路径），否则会出现「状态行说
    // 请先保存密钥、下面还挂着上一轮结果」的错配
    this.testRefs = [];
    this.resultExpanded = false;
    const handler: ((query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>) | undefined =
      searchHandlerOf(this.engineId);
    if (handler === undefined) {
      this.testStatus = '搜索引擎不可用';
      return;
    }
    // 条数恒用默认值：本页是直测引擎的调试入口，不属任何会话、不经 dispatchSearch 的条数字段——
    // 结果条数恒 = SEARCH_RESULT_COUNT_DEFAULT(5)，不吃全局 prefSearchResultCount
    const ctx: SearchEngineRuntime = {
      apiKey: '', baseUrl: this.baseUrlInput.trim(),
      resultCount: SEARCH_RESULT_COUNT_DEFAULT, variant: this.variantInput
    };
    const query: string = this.queryInput.trim() === '' ? TEST_QUERY : this.queryInput.trim();
    // ★ testing 在**异步读密钥之前**置位——否则 Asset 读取窗口内二次点击绕过防重入，造成两次真实
    // 请求（付费引擎消耗两次额度）且状态与结果互相覆盖；两条早退路径各自归位 testing=false
    this.testing = true;
    const doTest = (): Promise<void> => {
      this.testStatus = '正在测试搜索…';
      const startedAt: number = Date.now();
      return handler(query, ctx)
        .then((out: WebSearchOutcome): void => {
          if (this.departed) {
            return;
          }
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
          if (this.departed) {
            return;
          }
          this.testStatus = '测试失败：' + (e as Error).message;
        })
        .finally((): void => {
          if (this.departed) {
            return;
          }
          this.testing = false;
        });
    };
    if (this.needKey) {
      return loadSearchEngineKey(this.engineId)
        .then((plain: string): Promise<void> | void => {
          if (this.departed) {
            return;
          }
          if (plain === '') {
            this.testStatus = '请先保存 API Key 再测试';
            this.testing = false;
            return;
          }
          ctx.apiKey = plain;
          return doTest();
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.testStatus = '密钥读取失败：' + (e as Error).message;
          this.testing = false;
        });
    }
    return doTest();
  }

  // 测试抓取（仅 canScrape 引擎）：直测本引擎抓取 handler，语义同测试搜索；结果只进内存态，
  // 离页即忘。testing 在异步读密钥之前置位（同 runTest 口径）
  private async runFetchTest(): Promise<void> {
    if (this.fetchTesting || this.working || this.testing) {
      return;
    }
    const handler: ScrapeHandler | undefined = scrapeHandlerOf(this.engineId);
    if (handler === undefined) {
      this.fetchStatus = '该引擎不支持抓取';
      return;
    }
    const url: string = this.fetchUrlInput.trim() === '' ?
      TEST_FETCH_URL : this.fetchUrlInput.trim();
    this.fetchTesting = true;
    this.fetchStatus = '正在测试抓取…';
    const startedAt: number = Date.now();
    try {
      const plain: string = await loadSearchEngineKey(this.engineId);
      if (this.departed) {
        return;
      }
      if (plain === '') {
        this.fetchStatus = '请先保存 API Key 再测试';
        return;
      }
      const ctx: SearchEngineRuntime = {
        apiKey: plain, baseUrl: this.baseUrlInput.trim(),
        resultCount: SEARCH_RESULT_COUNT_DEFAULT, variant: this.variantInput
      };
      const out: WebFetchOutcome = await handler(url, ctx);
      if (this.departed) {
        return;
      }
      const costMs: number = Date.now() - startedAt;
      if (!out.success) {
        this.fetchStatus = '测试失败：' + out.errorMessage;
        return;
      }
      const title: string = out.title === '' ? '无标题' : out.title;
      this.fetchStatus = `抓取成功，标题 ${title}，正文 ${out.content.length} 字，耗时 ${costMs} ms`;
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.fetchStatus = '测试失败：' + (e as Error).message;
    } finally {
      this.fetchTesting = false;
    }
  }

  // 开浏览器（与会话页引文卡同出口 launchExternalLink，官方推荐路径；getHostContext 走 UIContext 形态）
  private openRefUrl(url: string): void {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, url);
    } catch (e) {
      // 静默（拿不到宿主 context 的边缘形态——与会话页引文卡同口径）
    }
  }

  // 结果引文卡（复用会话页引文卡形态：编号 + 标题 + 摘要 + URL，点行开浏览器——两处观感一致；
  // 条数 ≤ 默认 5 条天然有界，无需分页）
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

  // 已配置密钥的只读展示：输入框外观的灰底行，内容为固定圆点掩码；copyOption + textSelectable 让
  // 长按菜单出现，editMenuOptions 把系统「复制」拦截为复制 Asset 真钥
  @Builder
  KeyMaskDisplay() {
    Row() {
      Text(KEY_MASK_TEXT)
        .fontSize(14)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .copyOption(CopyOptions.LocalDevice)
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
        .editMenuOptions(this.keyEditMenu)
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(20)
    .alignItems(VerticalAlign.Center)
  }

  // 行内文字键 / 主操作键 / 淡彩次级键三形制（fallbackButton 四件套双态）：primary=false = 内容宽
  // 次钮；primary=true = 通宽主键（官方强调蓝 + 恒白字）；tinted=true = 淡彩次级档（测试类动作）。
  // 通宽许可依据 = 规范-列表卡片与组卡 §4.3「通宽按钮只许出现在卡内还有其他内容的语境」，本页各卡
  // 均带标题 + 说明 + 输入框，符合。
  // ★ 单参对象字面量 = 按引用传递（见 InlineBtnOpts）：`.enabled(opts.enabled)` 读入参属性，父状态
  // 变化才随 Builder 重执行；改多参或把 enabled 提成闭包变量即失效。
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
    } else if (opts.tinted) {
      Button(opts.label)
        .fontColor(fallbackButtonFontTinted(this.contentFallback))
        .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
        .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
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
          // 与全应用卡齐平）
          Text('引擎不存在或已变更，请返回列表重试')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
            .padding(24)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
        } else {
          // ★ 原「启用开关卡」与「当前引擎卡」整段退役——启停唯一控制面 = 列表页行尾开关；当前
          // 引擎唯一设置面 = 对话页「联网」菜单。
          // ── 子引擎卡（仅描述符带 variants 的引擎渲染）：点瓦片即落盘（「即时持久化」口径），
          //    选中态读 @State variantInput；宫格是「选项」不是按钮，不接行内按钮四件套 ──
          if (this.variantOptions.length > 0) {
            Column({ space: 10 }) {
              Text('检索引擎')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('基础版偏通用，高阶版多引擎协作，搜狗覆盖腾讯生态与知乎，夸克垂直内容更准。搜索质量与价格同步递增，切换后立即生效。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              OptionTileGrid({
                labels: this.variantLabels,
                subLabels: this.variantSubLabels,
                values: this.variantValues,
                selectedValue: this.variantInput,
                onPick: (value: string): void => {
                  this.selectVariant(value);
                }
              })
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
            .alignItems(HorizontalAlign.Start)
          }
          // ── API Key 卡（仅需 key 引擎；已配置时只读掩码展示，长按「复制」取 Asset 真钥；
          //    「更换密钥」才切空输入框）──
          if (this.needKey) {
            Column({ space: 10 }) {
              Row() {
                Text('API Key')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                Blank()
                if (this.hasKeyMarked()) {
                  // StatusBadge 入参为普通成员（刷新责任在调用方）：两分支各建实例，父 @State 变化随页重建即刷
                  StatusBadge({ text: '已配置', tone: BadgeTone.SUCCESS })
                } else {
                  StatusBadge({ text: '未配置', tone: BadgeTone.WEAK })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              Text('密钥在引擎官网申请，加密保存在本机，不会上传。长按已存密钥可复制。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              if (this.showKeyInput()) {
                TextInput({ text: this.keyInput,
                  placeholder: this.keyHint === '' ? '粘贴 API Key' : '粘贴 API Key，' + this.keyHint })
                  .fontSize(14)
                  .type(InputType.Password)
                  .showPasswordIcon(false)
                  .width('100%')
                  .onChange((text: string): void => {
                    this.keyInput = text;
                  })
              } else {
                this.KeyMaskDisplay()
              }
              // 更换 / 清除次动作（仅已配置时显示；更换态可取消回只读展示）
              if (this.hasKeyMarked()) {
                Row({ space: 16 }) {
                  Blank()
                  if (this.keyEditing) {
                    Text('取消更换')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_emphasize'))
                      .onClick((): void => {
                        this.cancelKeyEdit();
                      })
                  } else {
                    Text('更换密钥')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_emphasize'))
                      .onClick((): void => {
                        this.beginKeyEdit();
                      })
                  }
                  Text('清除密钥')
                    .fontSize(13)
                    .fontColor($r('sys.color.font_emphasize'))
                    .onClick((): void => {
                      this.clearKey();
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }
              // 主操作键只在输入态显示（只读展示态没有可保存内容）
              if (this.showKeyInput()) {
                this.InlineBtn({
                  label: '保存密钥',
                  enabled: !this.working && !this.testing,
                  primary: true,
                  tinted: false,
                  onTap: (): void => {
                    this.saveKey();
                  }
                })
              }
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
            .borderRadius(CARD_RADIUS)
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
              tinted: false,
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
          .borderRadius(CARD_RADIUS)
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
            // 测试类动作 → 淡彩次级档（与测试抓取同档）
            this.InlineBtn({
              label: '测试搜索',
              enabled: !this.working && !this.testing,
              primary: false,
              tinted: true,
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
                tinted: false,
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
                tinted: false,
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
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
          // ── 测试抓取卡（仅 canScrape 引擎渲染——真实抓取一次网页，按次计费；结果只进内存态）──
          if (this.canScrape) {
            Column({ space: 10 }) {
              Text('测试抓取')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('会真实抓取一次网页，按次计费。留空则用默认示例地址测试。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              TextInput({ text: this.fetchUrlInput, placeholder: TEST_FETCH_URL })
                .fontSize(14)
                .width('100%')
                .onChange((text: string): void => {
                  this.fetchUrlInput = text;
                })
              this.InlineBtn({
                label: '测试抓取',
                enabled: !this.working && !this.testing && !this.fetchTesting,
                primary: false,
                tinted: true,
                onTap: (): void => {
                  this.runFetchTest();
                }
              })
              if (this.fetchStatus !== '') {
                Text(this.fetchStatus)
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
            .alignItems(HorizontalAlign.Start)
          }
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
    .scrollBar(BarState.Off)
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
