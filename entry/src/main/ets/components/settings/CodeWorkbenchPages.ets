// 脚本工作台设置域：三 struct 一件（照 HttpCredentialsPage 先例）——设置页（CodeWorkbenchPage）+
// 域名总览页（CodeHttpHostsLibraryPage）+ 域名管理页（CodeHttpHostManagePage）。
// ★ 2026-11-16 改题：原「代码工作台」→「脚本工作台」（决明拍板）。理由 = 「代码」语义过宽，
//   本页只管 JavaScript 与模拟 Shell 两模式，Python 另有「Python 运行环境」独立页；标题单源
//   在 SettingSearch.SETTING_TITLE_CODE_WORKBENCH，本件只改指路句与说明文案。
// · 设置页：入口 = 工具调用页首组卡「脚本工作台」行（push 无参）。四卡：①「运行档位」（标题 +
//   右上角 ⓘ 气泡 + 精简说明 + SegmentBar）；②「脚本引擎」（三态 auto/quickjs/jsvm，形制同档位
//   卡，段控三分照 FunctionalModelPage OCR 先例；用户面自此明示引擎开关）；③「脚本联网域名」
//   入口卡（Button 包壳行卡）push 总览页；④「允许脚本发写请求」卡（写授权 = 全局单开关——只给
//   全局、不给助手开关，形制照 DataSyncPage「包含密钥」开关行）。原「总开关」已退役——可用性
//   全权随助手级「脚本工作台」卡，本页不再有布尔总开关。
// · 总览页：入口 = 设置页域名入口卡（push 无参）；页内 = 说明卡 + 全局卡 + 每助手卡（发现面——
//   零域名助手照列，照 HttpCredentialLibraryPage 形制），点击进管理页（param = owner）。
// · 管理页：入口两处 = 总览页卡 + 助手编辑页连接组卡的「脚本联网域名」行
//   （AssistantConnGroupCard；param = 本助手 id 直达）。形制照 HttpCredentialManagePage（说明卡 +
//   条目行卡 + 标题栏添加键），差异 = 域名无掩码无菜单（左滑删除是唯一删除路径且带确认）、添加
//   一步弹窗。运行时判定 = 助手名单 ∪ 全局名单（并集，codeHttpHostsFor 单源；fail-closed 两段
//   全空 = 全禁）。★ 助手页入口 push 对象 CodeHttpHostManageParam（携 readOnly = true）——只读态
//   不渲染添加键与删除入口，info 与空态指路设置侧；「添加域名」在右上角标题栏（官方单图标键 +，
//   menuHds 原样传，照 MemoryEditPage「保存」键形制）。
// 卡壳四件套 = CARD_PANEL_WIDTH / padding(16) / cardBg / 圆角 CARD_RADIUS（宿主无左右 16vp
// padding，卡体恒挂卡宽基准——规范-列表卡片与组卡 §4.3）；三页自包 PageShell 壳；无保存动作 →
// 返回无参 pop 不挂 onPop（坑17 口径——管理动作即时落库，入口页摘要刷新由其 onPop 承担；唯一
// 例外 = 管理页 onBackPressed 拦截后 pop({ saved: true }) 供入口页重拉计数）。
// ★ 状态链（照 ToolsSettingsPage / BrowserControlPage 分段卡同款契约）：@StorageLink 持久键写即
// 落盘 + @Watch 补正分段下标（备份导入等第二写键方在途时 UI 随键同步）+ 用户点分段写键（同值不
// 回写防递归）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { InfoHintButton } from '../InfoHintButton';
import { InfoCard } from '../InfoCard';
import { InputDialog } from '../chat/InputDialog';
import { ConfirmDialog } from '../chat/ConfirmDialog';
// 只留 overlayMaterial（弹窗材质）——四件套与两键订阅随管理页添加键退役已无消费点
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { CODE_WORKBENCH_ENGINE_AUTO, CODE_WORKBENCH_ENGINE_JSVM,
  CODE_WORKBENCH_ENGINE_QUICKJS, CODE_WORKBENCH_MODE_STANDARD, CODE_WORKBENCH_MODE_STRICT,
  PREF_CODE_WORKBENCH_ENGINE_KEY, PREF_CODE_WORKBENCH_MODE_KEY,
  resolveCodeWorkbenchEngine, resolveCodeWorkbenchMode } from '../../common/AppPreferences';
import { SETTING_TITLE_CODE_ENGINE, SETTING_TITLE_CODE_WORKBENCH,
  SETTING_TITLE_CODE_HTTP_HOSTS, SETTING_TITLE_CODE_SCRIPT_WRITE } from '../../common/SettingSearch';
import { ROUTE_CODE_HTTP_HOSTS_PAGE, ROUTE_CODE_HTTP_HOST_MANAGE_PAGE } from '../../common/RouteNames';
import { SegmentBar } from '../SegmentBar';
import { addCodeHttpHost, CODE_HTTP_HOST_MODE_ALLOWLIST, CODE_HTTP_HOST_MODE_ANY,
  CODE_HTTP_HOST_MAX_CHARS, CODE_HTTP_HOSTS_MAX, CODE_HTTP_OWNER_GLOBAL, CodeHttpHostManageParam,
  getCodeHttpHostsJson, httpPolicyHostInputValid, normalizeHttpPolicyHost,
  parseCodeHttpHosts, PREF_CODE_HTTP_HOST_MODE_KEY, PREF_CODE_HTTP_WRITE_KEY,
  removeCodeHttpHost, resolveCodeHttpHostMode } from '../../common/AppPreferencesHttp';
import { AssistantRow, queryAssistant,
  queryAssistants } from '../../common/store/AssistantDb';
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';

// ── 设置页（档位卡 + 引擎卡 + 域名入口卡）──
@Component
export struct CodeWorkbenchPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 档位持久键（'standard' / 'strict'，数值映射单源 ScriptLimits.ets——本页只写档位值）；
  // @StorageLink 写即持久化，备份导入恢复自动响应
  @StorageLink(PREF_CODE_WORKBENCH_MODE_KEY) @Watch('onCodeWorkbenchModeChanged')
  codeWorkbenchMode: string = CODE_WORKBENCH_MODE_STANDARD;
  // 档位段控下标镜像（@State + @Watch 双向——用户点段写档位键；键侧改〔备份导入〕补正下标）
  @State @Watch('onCodeWorkbenchSegChanged') codeWorkbenchSegIndex: number = 0;
  // 档位分段选项（顺序契约：0 = 标准（缺省）/ 1 = 严格；映射见 codeModeToSegIndex / codeSegIndexToMode）
  private codeWorkbenchItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '标准' },
    { text: '严格' }
  ]);
  // 引擎持久键（'auto' / 'quickjs' / 'jsvm'；判定单源 = AppPreferences.codeWorkbenchUsesQuickJsEngine
  // ——本页只写引擎值不落数值）；@StorageLink 写即持久化，备份导入恢复自动响应
  @StorageLink(PREF_CODE_WORKBENCH_ENGINE_KEY) @Watch('onEngineModeChanged')
  engineMode: string = CODE_WORKBENCH_ENGINE_AUTO;
  // 引擎段控下标镜像（@State + @Watch 双向——照档位段同款三步契约）
  @State @Watch('onEngineSegChanged') engineSegIndex: number = 0;
  // 引擎分段选项（顺序契约：0 = 跟随档位 auto（缺省）/ 1 = 试验引擎 quickjs / 2 = 系统引擎 jsvm
  // ——与 engineIndexOf / engineValueOf 三处同序。标签不暴露引擎内名，用词族照流式引擎与 OCR 先例）
  private engineItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '跟随档位' },
    { text: '试验引擎' },
    { text: '系统引擎' }
  ]);
  // 脚本写请求授权（全局单开关——只给全局、不给助手；@StorageLink 写即持久化，直接驱动 Toggle）
  @StorageLink(PREF_CODE_HTTP_WRITE_KEY) scriptWriteEnabled: boolean = false;

  aboutToAppear(): void {
    // 档位/引擎下标从持久键取真值（脏值经 resolve* 归一）；同值不回写防递归
    this.codeWorkbenchSegIndex = this.codeModeToSegIndex(this.codeWorkbenchMode);
    this.engineSegIndex = this.engineIndexOf(this.engineMode);
  }

  // 下标 ↔ 档位常量映射（单源；顺序契约见 codeWorkbenchItems 注释）
  private codeModeToSegIndex(mode: string): number {
    return mode === CODE_WORKBENCH_MODE_STRICT ? 1 : 0;
  }

  private codeSegIndexToMode(index: number): string {
    return index === 1 ? CODE_WORKBENCH_MODE_STRICT : CODE_WORKBENCH_MODE_STANDARD;
  }

  // 档位段控：用户点分段 → 写档位键（同值不回写防递归）
  private onCodeWorkbenchSegChanged(): void {
    const value: string = this.codeSegIndexToMode(this.codeWorkbenchSegIndex);
    if (value !== this.codeWorkbenchMode) {
      this.codeWorkbenchMode = value;
    }
  }

  // 档位第二写键方（备份导入恢复）→ 补正段下标（脏值经映射归一回标准档下标）
  private onCodeWorkbenchModeChanged(): void {
    const idx: number = this.codeModeToSegIndex(this.codeWorkbenchMode);
    if (idx !== this.codeWorkbenchSegIndex) {
      this.codeWorkbenchSegIndex = idx;
    }
  }

  // 引擎值 ↔ 分段下标（顺序契约三处同序：engineItems / engineIndexOf / engineValueOf）
  private engineIndexOf(value: string): number {
    if (value === CODE_WORKBENCH_ENGINE_QUICKJS) {
      return 1;
    }
    if (value === CODE_WORKBENCH_ENGINE_JSVM) {
      return 2;
    }
    return 0;
  }

  private engineValueOf(index: number): string {
    if (index === 1) {
      return CODE_WORKBENCH_ENGINE_QUICKJS;
    }
    if (index === 2) {
      return CODE_WORKBENCH_ENGINE_JSVM;
    }
    return CODE_WORKBENCH_ENGINE_AUTO;
  }

  // 引擎段控：用户点分段 → 写引擎键（同值不回写防递归）
  private onEngineSegChanged(): void {
    const value: string = this.engineValueOf(this.engineSegIndex);
    if (value !== this.engineMode) {
      this.engineMode = value;
    }
  }

  // 引擎第二写键方（备份导入）→ 补正段下标（脏值经 resolveCodeWorkbenchEngine 归一）
  private onEngineModeChanged(): void {
    const idx: number = this.engineIndexOf(resolveCodeWorkbenchEngine(this.engineMode));
    if (idx !== this.engineSegIndex) {
      this.engineSegIndex = idx;
    }
  }

  // 引擎分段说明（三态各一句；文案规约：无冒号分号括号连环）
  private engineDescText(): string {
    if (this.engineSegIndex === 1) {
      return '两档都使用试验引擎。';
    }
    if (this.engineSegIndex === 2) {
      return '两档都使用系统引擎。';
    }
    return '按档位自动选择。严格档用试验引擎，标准档用系统引擎。';
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 运行档位卡：标题行 + ⓘ 气泡（长说明移入，卡面只留档位语义）+ 精简说明 + SegmentBar。
        // 写即持久化无保存键，返回无参 pop 不挂 onPop（坑17）；原「总开关」已退役
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text('运行档位')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Blank()
            InfoHintButton({
              text: '模型可以编写并运行 JavaScript 脚本，用于计算与文本处理。模型也可以运行模拟 Shell 脚本，它是应用内置的受限命令解释器，不是系统终端，命令限内置清单，不支持循环与命令替换，也不提供网络命令。脚本只能读写本会话的临时区，要长期保留可让模型存进文件工作区。JavaScript 脚本的网络请求只能发往已授权的域名，在下方「脚本联网域名」配置。脚本默认只能发 GET 请求，写请求需在本页开启。单次运行有时间与内存上限。是否允许由每个助手在编辑页「工具调用」里的「脚本工作台」卡决定。'
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Text('标准档适合大多数脚本。严格档把运行时限与内存上限减半，适合只做简单计算的场景。档位只作用于 JavaScript 脚本，模拟 Shell 固定按严格档的上限运行。')
            .fontSize(13)
            .fontColor(cardDescColor())
          Column() {
            SegmentBar({
              items: this.codeWorkbenchItems,
              selectedIndex: $codeWorkbenchSegIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 脚本引擎卡（形制同档位卡；段控三分照 FunctionalModelPage OCR 三态先例）。只影响
        // JavaScript 脚本执行方式，限额与能力不受影响，切换从下一次运行起生效
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text(SETTING_TITLE_CODE_ENGINE)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Blank()
            InfoHintButton({
              text: '脚本引擎决定 JavaScript 脚本用哪种方式执行。只作用于 JavaScript 模式，模拟 Shell 不受此设置影响。脚本能做什么、限额多少都不受影响。切换后从下一次运行开始生效。遇到脚本运行异常时可以换一种引擎再试。'
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Text(this.engineDescText())
            .fontSize(13)
            .fontColor(cardDescColor())
          Column() {
            SegmentBar({
              items: this.engineItems,
              selectedIndex: $engineSegIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 脚本联网域名入口卡：跳总览页；形制与 HTTP 凭据入口卡同源（Button 包壳 + icon + 标题 +
        // 副行，官方原生按压蒙层）。卡底 padding 4 让蒙层距卡外圈 4vp，壳 padding 16→12 回添
        Column() {
          Button() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.website'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 4 }) {
                Text(SETTING_TITLE_CODE_HTTP_HOSTS)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text('JavaScript 脚本可访问的域名，分全局与每个助手。Python 运行不受此域名清单限制')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .onClick((): void => {
            this.pathStack.pushPathByName(ROUTE_CODE_HTTP_HOSTS_PAGE, null);
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
        // 允许脚本发写请求（全局单开关；形制照 DataSyncPage「包含密钥」开关行与规范 §1.1
        //「单开关卡」）。@StorageLink 直接驱动 Toggle。授权语义 = 开启后写请求不再逐次确认
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text(SETTING_TITLE_CODE_SCRIPT_WRITE)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('开启后脚本可以发 POST、PUT、DELETE 与 PATCH 请求，写请求不再逐次确认。')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.scriptWriteEnabled })
              .onChange((isOn: boolean): void => {
                if (isOn !== this.scriptWriteEnabled) {
                  this.scriptWriteEnabled = isOn;
                }
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
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

  build() {
    PageShell({
      title: SETTING_TITLE_CODE_WORKBENCH,
      content: (): void => {
        this.Content()
      }
    })
  }
}

// ── 域名总览页（发现面：说明卡 + 全局卡 + 每助手卡，零域名照列）──
@Component
export struct CodeHttpHostsLibraryPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private assistants: AssistantRow[] = [];
  @State private counts: string[] = []; // 与 assistants 同序的「N 个域名 / 未配置」副行
  @State private globalCount: number = -1; // -1 = 加载中
  pathStack: NavPathStack = new NavPathStack();
  // 请求模式持久键（@StorageLink 写即持久化，备份导入恢复自动响应；@Watch 键侧补正下标）
  @StorageLink(PREF_CODE_HTTP_HOST_MODE_KEY) @Watch('onHostModeChanged')
  hostMode: string = CODE_HTTP_HOST_MODE_ALLOWLIST;
  // 请求模式段控下标镜像（用户点段 → 写键；同值不回写防递归）
  @State @Watch('onHostModeSegChanged') hostModeSegIndex: number = 0;
  // 顺序契约：下标 0 = 仅已添加 allowlist（缺省）/ 1 = 任何域名 any——items 与两映射函数三处同序
  private hostModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '仅已添加' }, { text: '任何域名' }
  ]);

  aboutToAppear(): void {
    this.hostModeSegIndex = this.hostModeIndexOf(resolveCodeHttpHostMode(this.hostMode));
    this.reload();
  }

  private reload(): void {
    queryAssistants()
      .then((all: AssistantRow[]): void => {
        if (this.departed) {
          return;
        }
        // 全部助手照列（原「控制台助手不列域名卡」过滤已退役）
        const rows: AssistantRow[] = all;
        this.assistants = rows;
        const json: string = getCodeHttpHostsJson();
        this.globalCount = parseCodeHttpHosts(json, CODE_HTTP_OWNER_GLOBAL).length;
        const lines: string[] = [];
        for (const a of rows) {
          const n: number = parseCodeHttpHosts(json, a.id).length;
          lines.push(n > 0 ? n + ' 个域名' : '未配置');
        }
        this.counts = lines;
      })
      .catch((_e: Object): void => {
        if (this.departed) {
          return;
        }
        this.globalCount = 0;
        this.counts = [];
      });
  }

  private openManage(owner: string): void {
    // 第三参 onPop：管理页返回（pop 带 result）重拉计数——管理动作即时落库，重拉幂等
    this.pathStack.pushPathByName(ROUTE_CODE_HTTP_HOST_MANAGE_PAGE, owner, (): void => {
      this.reload();
    });
  }

  private hostModeIndexOf(value: string): number {
    return value === CODE_HTTP_HOST_MODE_ANY ? 1 : 0;
  }

  private hostModeValueOf(index: number): string {
    return index === 1 ? CODE_HTTP_HOST_MODE_ANY : CODE_HTTP_HOST_MODE_ALLOWLIST;
  }

  private onHostModeSegChanged(): void {          // 段 → 键（同值不回写）
    const value: string = this.hostModeValueOf(this.hostModeSegIndex);
    if (value !== this.hostMode) { this.hostMode = value; }
  }

  private onHostModeChanged(): void {             // 键 → 段（resolve 归一后补正）
    const idx: number = this.hostModeIndexOf(resolveCodeHttpHostMode(this.hostMode));
    if (idx !== this.hostModeSegIndex) { this.hostModeSegIndex = idx; }
  }

  // 总览页 info 两态文案（模式说明并入此处——胶囊卡无说明行）；≤81 字基准，过文案规约
  private libraryInfoText(): string {
    return this.hostMode === CODE_HTTP_HOST_MODE_ANY ?
      '当前允许 JavaScript 脚本向任何域名发请求。应用的安全拦截仍然生效。切回后名单恢复使用。' :
      'JavaScript 脚本默认只向已添加的域名及其子域名发请求。全局域名所有助手都能用。名单为空时联网请求会直接报错。Python 运行不受此域名清单限制。';
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 说明卡（InfoCard 单源；text 两态动态——模式说明并入此处，胶囊卡无说明行）
        InfoCard({
          title: SETTING_TITLE_CODE_HTTP_HOSTS,
          text: this.libraryInfoText()
        })
        // 域名请求模式卡（胶囊卡不加更多信息——模式说明并入上方 info 卡；选项文字与帮助条目、
        // 设置搜索 keywords 逐字一致）
        Column() {
          Column() {
            SegmentBar({
              items: this.hostModeItems,
              selectedIndex: $hostModeSegIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 全局卡（Button 包壳 + 官方原生按压蒙层，照 HttpCredentialLibraryPage 全局卡）。卡底
        // Column + padding 4 让蒙层距卡外圈 4vp，壳 padding 16→12 回添（下同，助手卡同款）
        Column() {
          Button() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.website'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 4 }) {
                Text('全局域名')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text(this.globalCount > 0 ? this.globalCount + ' 个域名' : '未配置')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .onClick((): void => {
            this.openManage(CODE_HTTP_OWNER_GLOBAL);
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
        // 助手卡（零域名照列——总览是发现面，形制照全局卡）
        ForEach(this.assistants, (a: AssistantRow, idx: number) => {
          Column() {
            Button() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.person_2'))
                  .fontSize(20)
                  .fontColor([cardTitleColor()])
                Column({ space: 4 }) {
                  Text(a.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(cardTitleColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(idx < this.counts.length ? this.counts[idx] : '未配置')
                    .fontSize(13)
                    .fontColor(cardDescColor())
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .alignItems(VerticalAlign.Center)
            }
            .type(ButtonType.Normal)
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(CARD_RADIUS)
            .onClick((): void => {
              this.openManage(a.id);
            })
          }
          .width(CARD_PANEL_WIDTH)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .padding(4)
        }, (a: AssistantRow) => a.id + '|' + a.name + '|' +
          (this.assistants.indexOf(a) < this.counts.length ?
            this.counts[this.assistants.indexOf(a)] : ''))
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

  build() {
    PageShell({
      title: SETTING_TITLE_CODE_HTTP_HOSTS,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

// ── 域名管理页标题栏「添加域名」键 ──
// 官方标题栏菜单数组单键（形制照 MemoryEditPage「保存」/ 凭据管理页「添加凭据」）。
// 只读态不挂。
function hostAddMenuHds(onAdd: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.plus'),
        action: onAdd
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

// ── 域名管理页（param = owner；添加一步弹窗）──
@Component
export struct CodeHttpHostManagePage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 请求模式只读消费面（单向 @StorageProp——本页无写入口；备份导入等第二写键方在途时 UI 随键同步）
  @StorageProp(PREF_CODE_HTTP_HOST_MODE_KEY) hostMode: string = CODE_HTTP_HOST_MODE_ALLOWLIST;
  @State private hosts: string[] = [];
  @State private titleText: string = SETTING_TITLE_CODE_HTTP_HOSTS;
  pathStack: NavPathStack = new NavPathStack();
  // 兜底归全局（只读面最小、与助手无耦合的命名空间——fail-safe 口径）；取到 push 参后覆盖
  private owner: string = CODE_HTTP_OWNER_GLOBAL;
  // 只读态：true = 助手编辑页入口——无添加键、无删除入口；aboutToAppear 同步定值，首帧即生效
  private readOnly: boolean = false;
  // 添加弹窗控制器（惰性构造成员位——坑7：局部变量 open() 静默无效）
  private addCtrl: CustomDialogController | null = null;
  // 删除确认弹窗控制器（惰性构造同 addCtrl 坑7 形态；只读态无删除入口）
  private delCtrl: CustomDialogController | null = null;
  private pendingDeleteHost: string = '';
  // 行左滑删除互斥组（reload / 滚动开始两路收口；只读态整层退化由 swipeEnabled 承担）
  private swipeGroup: SwipeGroup = new SwipeGroup();

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条）：string owner（'global' 或助手 id；取不到归全局）/
    // 对象 CodeHttpHostManageParam（owner + readOnly）
    try {
      const params: Array<Object | null> =
        (this.pathStack.getParamByName(ROUTE_CODE_HTTP_HOST_MANAGE_PAGE) ?? []) as Array<Object | null>;
      const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
      if (typeof last === 'string') {
        this.owner = last;
      } else if (last !== null) {
        const parsed: CodeHttpHostManageParam = last as CodeHttpHostManageParam;
        if (typeof parsed.owner === 'string' && parsed.owner !== '') {
          this.owner = parsed.owner;
        }
        this.readOnly = parsed.readOnly === true;
      }
    } catch (e) {
    }
    this.resolveTitle();
    this.reload();
  }

  private resolveTitle(): void {
    this.titleText = this.owner === CODE_HTTP_OWNER_GLOBAL ? '全局域名' : SETTING_TITLE_CODE_HTTP_HOSTS;
    if (this.owner !== CODE_HTTP_OWNER_GLOBAL) {
      queryAssistant(this.owner)
        .then((row: AssistantRow | null): void => {
          if (this.departed) {
            return;
          }
          if (row !== null) {
            this.titleText = row.name + ' 的域名';
          } else {
            this.titleText = '已删除助手的域名';
          }
        })
        .catch((_e: Object): void => {
        });
    }
  }

  // 管理页 info 2×2 组合文案（allowlist 态两 owner 逐字保留；any 态两 owner 统一指路句；
  // 只读态单独一句指路——增删入口唯一在设置侧总览页）
  private manageInfoText(): string {
    if (this.readOnly) {
      return '这里只查看这名助手的清单。新增与删除在设置 → 工具调用 → 脚本工作台 → 脚本联网域名。';
    }
    if (this.hostMode === CODE_HTTP_HOST_MODE_ANY) {
      return '当前允许向任何域名发请求，本名单暂不生效。可在 设置 → 工具调用 → 脚本工作台 → 脚本联网域名 切换请求模式。';
    }
    return this.owner === CODE_HTTP_OWNER_GLOBAL ?
      '脚本里的 httpGet 只能访问已授权的域名及其子域名。这里没有授权时，脚本联网仍可用各助手自己授权的域名。' :
      '脚本联网可访问本名单与全局域名的并集。名单为空且全局也没有授权时，脚本的联网请求会直接报错。';
  }

  // 清单重算（同步现读——解析单源 parseCodeHttpHosts，增删写键后本方法重拉即新值）
  private reload(): void {
    this.hosts = parseCodeHttpHosts(getCodeHttpHostsJson(), this.owner);
    // 清单整组重拉即收口行左滑展开态（删行后原行销毁，双保险）
    this.swipeGroup.collapse();
  }

  // 添加域名（标题栏键弹 InputDialog 一步）：校验与写侧全在 AppPreferencesHttp 单源——此处只做
  // 分态 toast（非法 / 过长先拦，写入回 false = 满员）
  private confirmAdd(text: string): void {
    const host: string = normalizeHttpPolicyHost(text);
    if (!httpPolicyHostInputValid(host)) {
      this.getUIContext().getPromptAction().showToast({
        message: '请填写纯域名，例如 api.example.com'
      });
      return;
    }
    if (host.length > CODE_HTTP_HOST_MAX_CHARS) {
      this.getUIContext().getPromptAction().showToast({
        message: '域名过长，最多 ' + CODE_HTTP_HOST_MAX_CHARS + ' 个字符'
      });
      return;
    }
    if (!addCodeHttpHost(this.owner, host)) {
      this.getUIContext().getPromptAction().showToast({
        message: '名单已满，最多 ' + CODE_HTTP_HOSTS_MAX + ' 个域名'
      });
      return;
    }
    this.reload();
  }

  private openAdd(): void {
    this.addCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '添加域名',
        placeholder: '例如 api.example.com',
        confirmLabel: '添加',
        onConfirm: (text: string): void => {
          this.confirmAdd(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.addCtrl.open();
  }

  // 删除确认（行内键已退役，左滑是唯一删除路径且带确认；惰性构造成员位——坑7）
  private askDeleteHost(host: string): void {
    this.pendingDeleteHost = host;
    this.delCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除域名',
        message: '将删除「' + host + '」，脚本将不再能访问它及其子域名。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.deleteHost(this.pendingDeleteHost);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.delCtrl.open();
  }

  // 删除执行（确认后单链——removeCodeHttpHost 即时落键 + reload）
  private deleteHost(host: string): void {
    this.pendingDeleteHost = '';
    removeCodeHttpHost(this.owner, host);
    this.reload();
  }

  // 域名条目行（RowSwipeDelete content 位，形制不变）；行内删除键已退役，左滑是唯一删除路径
  @Builder
  HostRow(host: string) {
    Row({ space: 10 }) {
      Text(host)
        .fontSize(16)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 说明卡（InfoCard 单源；title/text 随 owner 与只读态分派，见 manageInfoText）
        InfoCard({
          title: this.readOnly ? '域名只读' : this.owner === CODE_HTTP_OWNER_GLOBAL ?
            '全局域名对所有助手的脚本生效' : '域名只对这个助手的脚本生效',
          text: this.manageInfoText()
        })
        // 条目行（白卡行 + CARD_PANEL_WIDTH，照 HttpCredentialManagePage；域名非秘密直接明文展示）
        if (this.hosts.length === 0) {
          Text(this.readOnly ? '还没有授权任何域名。在设置 → 工具调用 → 脚本工作台 → 脚本联网域名里添加。' :
            '还没有授权任何域名。点右上角的加号添加。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
            .width(CARD_PANEL_WIDTH)
        }
        ForEach(this.hosts, (host: string) => {
          // 行左滑删除层：行卡 CARD_PANEL_WIDTH 居中 → cardInset 16；rowId = 域名字符串本体
          //（与 ForEach 键同源）；只读态整层退化；删除经 askDeleteHost 确认
          RowSwipeDelete({
            rowId: host,
            swipeEnabled: !this.readOnly,
            group: this.swipeGroup,
            content: (): void => {
              this.HostRow(host)
            },
            onSwipeDelete: (rowHost: string): void => {
              this.askDeleteHost(rowHost);
            }
          })
        }, (host: string): string => host)
        // 「添加域名」键在右上角标题栏（接线见 build 的 menuHds）
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
    // 滚动开始即收口行左滑展开态（会话列表/五库同口径）
    .onScrollStart((): void => {
      this.swipeGroup.collapse();
    })
  }

  build() {
    PageShell({
      title: this.titleText,
      // 右上角「添加域名」键（只读态不挂键 = menuHds null）
      menuHds: this.readOnly ? null : hostAddMenuHds((): void => {
        this.openAdd();
      }),
      // 无保存动作的完成返回（坑17 标准姿势）：pop 带 result 触发入口页 onPop 重拉摘要
      //（管理动作即时落库，重拉幂等无害）
      onBackPressed: (): boolean => {
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
