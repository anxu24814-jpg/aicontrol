// 聊天页「会话设置」半模态面板域（★ 2026-10-30 更名，决明拍板；原名「附件与提示词」自
// 2026-08-30 面板新建起用。自 dshinhm 半模态沉淀 + FileSheet/KimiChatPage 对照复刻）：壳 =
// 页面根声明式 bindSheet + HdsNavigation MODAL 标题栏 + sheetTitleBarOptions（静止渐变模糊
// + 材质随沉浸光感总档——KimiSheetCommon 单源，勿另写）。
// · ★ 2026-11-25 会话设置栈化笔（决明拍板「用官方、面板内做层级」）：原「同壳换 panelMode
//   分支」改为**面板内官方 Navigation 栈**——HdsNavigation(pathStack) 首页 = 主面板，四个子
//   面板各为子页，push/pop 走系统默认转场。★ 同日标题栏同规格修笔：子页壳 = 外层
//   HdsNavDestination（只承路由/转场，hideTitleBar + page_bg 实底〔二修：透明底在转场中会透出
//   上一页与退场视差，实底遮住；见 PageMap 头注释〕）+ 内层 HdsNavigation（承标题栏与内容，
//   HdsNavigationTitleMode.MODAL = 与首页同一 80/72 带副标题规格）；HdsNavDestination 的
//   MODAL 标题固定 64/56/8、无副标题档，直接用会矮 16vp。取舍（决明拍板）：二级无返回
//   箭头，xmark 关整张、返回手势走栈 pop。关闭语义：xmark / 下拉 / 蒙层恒关整张面板（xmark
//   自绘键直调宿主关闭单入口）；返回类手势（back 键 / 侧滑 / Esc = PRESS_BACK、SLIDE）栈非空
//   = pop 回上一页且面板不关，栈空才关（分流单源 = ChatSheetCtrl.handleGestureClose）。栈本体
//   归本件（每次打开重建 = 新栈，天然归零），挂载经 registerPromptNavStack 登记到
//   ChatSheetCtrl、卸载按实例同一性注销（单窗口同一时刻至多一个会话设置面板）。
// · 动态模糊生效前提（沉淀「列表类」节）：滚动容器 **clip(false)**——滚动内容穿透标题栏
//   背后，GRADIENT_BLUR 才能透出内容（Scroll 默认裁剪 = 模糊无内容可透的根因）。
// · 面板一：上排三格方卡（SheetGridOption 规格——见 AttachGridRow 头注释；三符号旧项目
//   真机实锤——坑72 口径）——camera 拍照 / picture 照片 / folder 系统文件，点击上行 onPick
//  （面板保持打开）→ 页面交 AttachmentPickCtrl 拉选择器；下排提示词注入卡 = 自制行卡
//   SelfListCard（★ 三卡统一本形制，原 HdsListItemCard/回退双链合流退役——官方列表卡蒙层
//   几何与 cardWidth 百分比宽度不可控，真机内容层崩塌，决明拍板「改成和其他卡完全统一」）。
// · 面板二：选词子页（PromptPickPanel）——列表卡行 + 右侧官方开关；互斥取**自动切换**
//  （已开一个再开另一个直接切换，原「toast 拒绝 + 纪元弹回」退役）；开关关闭当前 = 清引用
//   回退**归属助手提示词**；点行卡不启用（启用逻辑已删）。选中 → 有行会话
//   updateConversationPromptId 落库、无行会话（新会话/隐私会话）跳库上行内存覆盖
//  （ChatPromptState.promptOverride）→ onPromptChanged 上行 + pop 回主面板。
// · 面板三：助手选择子页（AssistantSheetPanel——行卡+开关同面板二交互语言）。★ 归属与注入
//   解耦（决明拍板）：助手 = 会话恒归属（行显式绑定 ?? 面板覆盖 ?? 当前助手 ?? 内置默认
//   助手），提示词注入 = 独立开关——两卡状态可并存；注入优先级 = 会话提示词 > 助手提示词
//   > 系统提示词（解析在 ChatPromptState）；选择完成经 onPromptChanged 双参上行（promptId
//   + assistantId，未变化侧传当前值）。
// · 面板四：技能选择子页（SkillPickPanel）——原指定技能页整页 push 退役改本面板子页；每卡
//   右侧官方开关、互斥自动切换、顶部说明句沿用原页逐字；选中上行 onSkillDesignated 交
//   ChatPage 写两 @State（纯内存态不落库、不关面板，pop 回主面板）。
// · 面板五：重发文件选择子页（ReissuePickPanel，★ 2026-10-31 附件重发笔新建——主面板第五张
//   行卡「重发文件」）——双段一次拉全（本会话附件 + 工作区可发送件）+ 常显实时过滤框（★ 同日
//   搜索吸顶笔：框迁入标题栏下方带 bottomBuilder、SearchTopBand 恒光感，词真源在本壳、子件
//   @Link 同绑）+ 行窗 50 渐进渲染；行点击经 onReissuePicked 上行 ChatPage →
//   AttachmentPickCtrl.addCopiedFromFile 复制新副本入列（本页保持开、累加多选；额度与失败
//   toast 由控制器收口，本件零编排）。
// · ★ 联网卡迁入笔（2026-10-30，决明「把联网搜索从菜单移出到加号半模态页，新增行卡，可显示
//   联网引擎——关闭则显示关闭，开启则只显示引擎，点击仍弹弹窗选择」；自 ChatMoreMenu「联网」
//   项整域随迁）：主面板「提示词注入」与「技能」之间插联网卡——副标题 = 用处简述（固定句）、
//   右侧值三态（助手未启用 = 「未启用」/ 本会话关 = 「关闭」/ 开 = 引擎名；★ 2026-11-02
//   行卡改版笔：引擎名自副标题迁右侧，副标题改用处简述）；
//   点卡可用 = bindMenu 弹引擎菜单（内容 = WebSearchMenu 原样，已启用引擎清单 + 关闭垫底、
//   勾位互斥语义不变），不可用 = 指引 toast（原菜单点击守卫语义）。★ 层级依据：bindSheet
//   的 SheetMode.OVERLAY（官方默认）与弹窗类组件（bindMenu/CustomDialog/promptAction）同
//   层级、后弹者在上——菜单浮于面板之上不被遮挡（官方《半模态转场》文档实锤）；坑51/62
//   形态 = 组件内 @Builder 方法直挂 bindMenu（ChatParamChipBar.ThinkingMenuBuilder 同款
//   先例）；bindMenu 签名无 undefined 不能条件挂载，可用性二态走卡面 if/else 双分支（两
//   分支形制同 SelfListCard 规格）。三键 @StorageProp 订阅（可用性/生效值/当前引擎——本笔
//   起均驱动卡面右侧值 UI，ChatMoreMenu 期「弹出现读不设订阅」判据随 UI 面迁入作废，状态
//   最小化红线仍守：订阅的都是会变化且驱动 UI 的值）；选择动作经 onWebEnginePick/onWebClose
//   上行页面（编排体在页面闭包落 ChatSessionOverrideCtrl，本件零编排）；写点后 AppStorage
//   键即变 → 订阅自动刷卡面，无需本地镜像写。
// · 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）。
import {
  HdsNavigation, HdsNavigationTitleMode, HdsNavDestination
} from '@kit.UIDesignKit';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING, CARD_RADIUS, menuDividerColor, menuEndCheck } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial, segmentBandParams } from '../../common/ImmersiveLevel';
import { uiMaterial } from '@kit.ArkUI';
import { sheetTitleBarOptions } from './KimiSheetCommon';
// 面板内导航登记（返回分流单源 = ChatSheetCtrl.handleGestureClose；本件挂载登记自己的栈、
// 卸载按实例同一性注销）
import { registerPromptNavStack, unregisterPromptNavStack } from './ChatSheetCtrl';
// 搜索带承载件（与四库页同件：标题栏下方带搜索框恒 REGULAR 光感）
import { SearchTopBand } from '../SearchTopBand';
import { FilePickKind } from './AttachmentPickCtrl';
import { AssistantSheetPanel } from './AssistantSheetPanel';
import { PromptPickPanel } from './PromptPickPanel';
import { SkillPickPanel } from './SkillPickPanel';
import { ReissuePickPanel } from './ReissuePickPanel';
import { AttachmentListRow } from '../../common/store/AttachmentDb';
import {
  ASSISTANT_DEFAULT_ID, queryAssistant, queryConversationAssistantId
} from '../../common/store/AssistantDb';
import {
  PromptTemplateRow, queryConversationPromptId, queryTemplates
} from '../../common/store/PromptTemplateDb';
import { ConfigurationConstant } from '@kit.AbilityKit';
// 联网卡域（★ 2026-10-30 联网卡迁入笔，自 ChatMoreMenu 随迁）：联网两键（ChatParamChipBar
// 定义、refreshWebSearchFlag 同链写入）+ 引擎偏好两键 + 引擎注册表 + UIContext（toast 形参）
import { CHAT_WEBSEARCH_ALLOWED_KEY, CHAT_WEBSEARCH_ON_KEY } from './ChatParamChipBar';
import { PREF_DS_DOC_SERVER_KEY, PREF_DS_OFFICIAL_WEB_KEY, PREF_SEARCH_ENABLED_ENGINES_KEY,
  PREF_SEARCH_ENGINE_KEY } from '../../common/AppPreferences';
import { SEARCH_ENGINES } from '../../common/search/SearchEngineRegistry';
import { UIContext } from '@kit.ArkUI';
// DeepSeek 服务端工具域（★ DS 全家桶接入批 S1，修订版任务书 S1②）：官方档可用镜像键
//（ChatPage.setConnInfo 按 kill switch × 连接判据写入）+ 菜单哨兵 id（仅回调链流转）——
// 判据单源禁散写
import { CHAT_DS_OFFICIAL_AVAILABLE_KEY, DS_OFFICIAL_WEB_ID } from '../../common/providers/DsServerTools';

// 三格附件方卡行（纯 UI 哑组件零状态；SheetGridOption 规格照旧项目一字不差：图标上+文字
// 下、圆角 20、高 88、cardBg 底、layoutWeight(1) 三等分）。★ 对齐（旧项目 FileSheet 同款）：
// 本行自带左右 padding 16——两端齐平不双重收窄
@Component
struct AttachGridRow {
  // 附件入口上行（页面交 AttachmentPickCtrl 拉选择器）
  onPick: (kind: FilePickKind) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 单格方卡（外层 Column 承卡底 + 四周 padding 4，蒙层距卡外圈 4vp；Button 高 80，
  // 格高 88 与三等分零位移）
  @Builder
  Grid(icon: Resource, label: string, kind: FilePickKind) {
    Column() {
      Button() {
        Column({ space: 8 }) {
          SymbolGlyph(icon)
            .fontSize(24)
            .fontColor([$r('sys.color.icon_primary')])
          Text(label)
            .fontSize(14)
            .fontColor(cardTitleColor())
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(20)
      .height(80)
      .onClick((): void => {
        this.onPick(kind);
      })
    }
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(20)
    .layoutWeight(1)
    .height(88)
    .padding(4)
  }

  build() {
    Row({ space: 8 }) {
      this.Grid($r('sys.symbol.camera'), '拍照', 'camera')
      this.Grid($r('sys.symbol.picture'), '照片', 'photo')
      this.Grid($r('sys.symbol.folder'), '系统文件', 'file')
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }
}

// ═══ 联网选择域（★ 2026-10-30 联网卡迁入笔，自 ChatMoreMenu 联网开关域原样随迁——域注释
// 收敛、实现零变化；迁出缘起见 ChatMoreMenu 文件头）═══ 可用性判定、指引 toast、引擎选项与
// 快照帮助函数、二级菜单本体五件收拢本件。可用性 = 助手启用联网（单源判定，总开关已退役）。
// 联网卡侧三键订阅（见 ChatPromptSheet 成员注释）；写库落点经两回调上行页面直调
// ChatSessionOverrideCtrl.pickWebEngine / pickWebSearch(false)。

// 联网可用性现读（助手清单单源）：true = 联网卡可点开引擎菜单 / false = 点击出指引 toast
export function webSearchEnabledNow(): boolean {
  return AppStorage.get<boolean>(CHAT_WEBSEARCH_ALLOWED_KEY) ?? true;
}

// 「不可用」指引 toast（唯一不可用原因 = 助手未启用联网搜索）
export function notifyWebOff(uiContext: UIContext): void {
  uiContext.getPromptAction().showToast({
    message: '当前助手未启用联网搜索，可在助手编辑页的工具调用中开启'
  });
}

// 联网菜单引擎选项（id = 引擎注册表 id 即偏好键值域，label = 菜单显示名——单源导出）
export interface WebSearchEngineOption {
  id: string;
  label: string;
}

// 已启用引擎清单快照（注册表序过滤——SEARCH_ENGINES「顺序即 UI 顺序」立规；调用点现读 =
// 弹出一刻值。空清单返回空数组——菜单只剩「关闭」如实呈现：默认启用清单为注册表全量，空
// 只能是用户显式全关，Bing 仍经 resolveEngineId 终态兜底可搜）
export function enabledWebEngineOptions(): WebSearchEngineOption[] {
  const enabled: string[] = AppStorage.get<string[]>(PREF_SEARCH_ENABLED_ENGINES_KEY) ?? [];
  const list: WebSearchEngineOption[] = [];
  for (const engine of SEARCH_ENGINES) {
    if (enabled.includes(engine.id)) {
      list.push({ id: engine.id, label: engine.label });
    }
  }
  return list;
}

// 全局当前引擎 id 现读（联网卡副标题与菜单勾选判据——联网开时勾在它名下〔若在启用清单内〕；
// 兜底 'bing_local' 与 getSearchEngineId 同向。唯一 UI 写点 = ChatSessionOverrideCtrl.
// pickWebEngine，设置页展示面已退役）
export function currentWebEngineId(): string {
  return AppStorage.get<string>(PREF_SEARCH_ENGINE_KEY) ?? 'bing_local';
}

// 当前引擎显示名（★ 迁入笔新增——联网卡右侧值「开 = 引擎名」的取名面：注册表内查
// label，查不到〔理论不可达，注册表封闭〕原样回显 id 不谎报）
export function webEngineLabel(engineId: string): string {
  for (const engine of SEARCH_ENGINES) {
    if (engine.id === engineId) {
      return engine.label;
    }
  }
  return engineId;
}

// 联网引擎菜单本体：点引擎 = 全局当前引擎 + 本会话联网开，「关闭」= 写本会话覆盖 '0'，
// 两动作经 onPickEngine/onClose 上行（联网卡转发页面 → ChatSessionOverrideCtrl）。打勾：
// 联网开勾在当前引擎名下（不在启用清单内则落空不勾——如实呈现回退生效态，不把勾挪到回退
// 引擎防误导），关闭勾在「关闭」。★ DS 官方项（DS 全家桶接入批 S1，修订版任务书 S1②）：
// 仅镜像键 true〔DS 会话〕渲染——非 DS 会话隐藏非置灰（任务书代决 3）；勾选判据 = 联网开 ×
// 官方档偏好；点击上行哨兵 id 经 pickWebEngine 分流（哨兵只在回调链流转，禁落持久层）；
// 官方档生效时自带引擎项让位不勾（勾选互斥如实），故自带项勾选与 ForEach 键均补
// !(dsAvailable && dsOfficial) 因子（坑44 家族：键必须覆盖该行全部可变展示成分）。快照
// 纪律：bindMenu 菜单树每次弹出重建，engines/currentEngineId 取普通成员（纯快照无刷新需求，
// 状态最小化红线；禁设 @StorageProp 读偏好键——那会把快照偷换成响应式），on 经宿主订阅键
// 传入即当刻值；dsAvailable/dsOfficial 两键为真广播/持久状态键（非快照面），@StorageProp
// 自订阅合法〔坑16 正解，CHAT_OFF_SUPPORTED_KEY 同款先例〕
@Component
export struct WebSearchMenu {
  // 弹出一刻的本会话联网生效值（宿主 @StorageProp 订阅键传入；true = 勾当前引擎 / false =
  // 勾「关闭」）
  @Prop on: boolean;
  // 已启用引擎清单快照（注册表序，装配点经 enabledWebEngineOptions 现读）
  engines: WebSearchEngineOption[] = [];
  // 全局当前引擎 id 快照（装配点经 currentWebEngineId 现读）
  currentEngineId: string = '';
  // 引擎选择回调（宿主转发页面上行；官方项上行哨兵 id，同一通道分流）
  onPickEngine: (engineId: string) => void = () => {
  };
  // 关闭回调（宿主转发页面上行）
  onClose: () => void = () => {
  };
  // 「DeepSeek 官方」可用镜像键（ChatPage.setConnInfo 按 kill switch × 连接判据写入；
  // false = 非 DS 会话官方项不渲染）
  @StorageProp(CHAT_DS_OFFICIAL_AVAILABLE_KEY) dsAvailable: boolean = false;
  // 官方档偏好（持久键现读；true = 官方项勾选、自带项让位不勾）
  @StorageProp(PREF_DS_OFFICIAL_WEB_KEY) dsOfficial: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Menu() {
      ForEach(this.engines, (opt: WebSearchEngineOption) => {
        MenuItem({ content: opt.label,
          symbolEndIcon: menuEndCheck(this.on && !(this.dsAvailable && this.dsOfficial) &&
            opt.id === this.currentEngineId) })
          .onClick(() => {
            this.onPickEngine(opt.id);
          })
        // 键含勾选态（坑44 家族：勾选态换了承载 —— 2026-11-11 起是条件项尾图标而非
        // selected，但项配置变仍不自动重渲，键变触发整项重建，故键里必须保留该布尔）；
        // ★ S1 起勾选因子补官方档位（官方档生效 = 自带项恒不勾），键同步含该因子——
        // 官方档翻转时自带项整项重建；禁配 symbolStartIcon——87 组图标逐文件计数红线，
        // 且与子菜单纯文字形制一致
      }, (opt: WebSearchEngineOption): string =>
        opt.id + '|' + String(this.on && !(this.dsAvailable && this.dsOfficial) &&
          opt.id === this.currentEngineId))
      // DS 官方项（仅镜像键 true 渲染；文案统一「DeepSeek 官方」不带后缀——任务书 §2）
      if (this.dsAvailable) {
        MenuItem({ content: 'DeepSeek 官方',
          symbolEndIcon: menuEndCheck(this.on && this.dsOfficial) })
          .onClick(() => {
            this.onPickEngine(DS_OFFICIAL_WEB_ID);
          })
      }
      MenuItem({ content: '关闭', symbolEndIcon: menuEndCheck(!this.on) })
        .onClick(() => {
          this.onClose();
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }
}

@Component
export struct ChatPromptSheet {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 目标会话 id（页面透传；进入即加载，创建后不变——坑30 口径）
  @Prop conversationId: string = '';
  // 底部避让区高（面板内容底部让位）
  @Prop bottomInset: number = 0;
  // 面板底部留白（BottomInset + 固定 24——面板形态内容不贴手势条）
  private bottomPadInset: number = 0;
  // 深浅色（卡片底色 cardBg 函数驱动；EntryAbility 写键）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 标题栏材质档位（@StorageProp 自订阅——页面无需透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 选择变化上行（双参：promptId / assistantId = 两面板各自选中值，未变化侧传本卡当前值
  //——ChatPage 透传 ChatSendCtrl 两覆盖 + 刷新注入缓存立即生效；'' = 关闭侧——面板三关闭
  // 非默认卡上行默认 id，'' 仅初始未选防御）
  onPromptChanged: (promptId: string, assistantId: string) => void = () => {
  };
  // 会话无行兜底归属（页面下发创建期同步值——坑30 口径）：仅会话行不存在（新会话/隐私会话）
  // 时主面板「助手」卡与助手面板的显示态（= 面板覆盖 ?? 当前助手 ?? 内置默认；存量 '' 行
  // 由行侧解析为默认助手，不经本值）
  @Prop assistantBound: string = '';
  // 会话提示词引用覆盖（页面下发创建期同步值）：会话行不存在时主面板「提示词注入」卡
  // 显示态（无行无库可查——覆盖 = 注入真源）
  @Prop promptBound: string = '';
  // 本轮指定技能名（页面下发创建期同步值——本页只显示态：'' = 「未指定」/ 非空 = 「下一条
  // 消息：X」；真源在 ChatPage 两 @State）
  @Prop designateName: string = '';
  // 本轮指定技能 id（播种 SkillPickPanel 开关初态；真源同上）
  @Prop designateId: string = '';
  // 「技能」卡选中回上（两值交 ChatPage 写 @State——内存态不落库、不关面板，已回主面板）
  onSkillDesignated: (skillId: string, skillName: string) => void = () => {
  };
  // 附件三卡入口上行（页面交 AttachmentPickCtrl 拉选择器；面板保持打开）
  onPick: (kind: FilePickKind) => void = () => {
  };
  // 重发文件行点击上行（面板五，★ 2026-10-31 附件重发笔）：两段行点击复制入列——页面交
  // AttachmentPickCtrl.addCopiedFromFile，返回是否入列（false 已 toast；「已加入」态由域件
  // 据返回值自置，本件零状态）。★ 同日重发降级笔：多带来源两参（workspacePath / sourceRow）
  //——本件纯透传，降级编排全在控制器
  onReissuePicked: (name: string, srcRelPath: string, workspacePath: string,
    sourceRow: AttachmentListRow | null) => Promise<boolean> =
    (): Promise<boolean> => Promise.resolve(false);
  // 联网卡两动作上行（★ 2026-10-30 联网卡迁入笔）：点引擎 = 全局当前引擎 + 本会话联网开，
  // 「关闭」= 本会话覆盖 '0'——编排体在页面闭包落 ChatSessionOverrideCtrl，本件零编排
  onWebEnginePick: (engineId: string) => void = () => {
  };
  onWebClose: () => void = () => {
  };
  // ── 联网卡显示三键（★ 迁入笔；三键均驱动卡面右侧值 UI → @StorageProp 订阅合法——状态
  // 最小化红线「只用于会变化且驱动 UI 的变量」仍守。写点：ALLOWED/ON 两键 = 页面
  // refreshWebSearchFlag（会话加载/换助手/面板内选择后同链刷新），ENGINE 键 =
  // ChatSessionOverrideCtrl.pickWebEngine——选择动作后键即变，订阅自动刷卡面，无需本地
  // 镜像写）──
  // 可用性：助手启用联网（false = 卡点击出指引 toast）
  @StorageProp(CHAT_WEBSEARCH_ALLOWED_KEY) webAllowed: boolean = true;
  // 本会话联网生效值（false = 「关闭」态）
  @StorageProp(CHAT_WEBSEARCH_ON_KEY) webOn: boolean = true;
  // 全局当前引擎 id（「开」态右侧值取名 + 菜单勾位判据）
  @StorageProp(PREF_SEARCH_ENGINE_KEY) webEngineId: string = 'bing_local';
  // 面板关闭上行（页面置 sheetKind='none'）
  onClose: () => void = () => {
  };
  // 子页路由名（'pick' 选词 / 'assistant' 助手 / 'skill' 技能 / 'reissue' 重发文件；主面板 =
  // 首页 navBar 内容、无路由名）——★ 2026-11-25 会话设置栈化笔：不再是同壳换分支，而是
  // HdsNavigation 内官方路由栈（四个子面板 = HdsNavDestination 子页）；push/pop 走系统默认
  // 转场，返回键 = pop，标题栏 xmark 恒关整张面板
  // 面板内导航栈（本件自持——面板随 bindSheet 每次打开重建，栈天然归零；挂载时登记到
  // ChatSheetCtrl（返回分流读同一实例），卸载按实例同一性注销）。★ 子页壳的内层
  // HdsNavigation 不持栈（纯标题栏/内容承载，无内层路由）
  private navStack: NavPathStack = new NavPathStack();
  @State private templates: PromptTemplateRow[] = [];
  @State private currentId: string = '';
  @State private currentName: string = '';
  // 会话当前助手（主面板「助手」卡状态显示）
  @State private assistantId: string = '';
  @State private assistantName: string = '';
  // 滚动控制器（每页独立实例——栈内多页可能同时存活，共用一个 Scroller 会绑错；各页
  // bindToScrollable 绑自己的实例，主面板 = 首页 HdsNavigation）
  private mainScroller: Scroller = new Scroller();
  private pickScroller: Scroller = new Scroller();
  private skillScroller: Scroller = new Scroller();
  private assistantScroller: Scroller = new Scroller();
  private reissueScroller: Scroller = new Scroller();
  // 「DeepSeek 官方」可用镜像键（★ DS 全家桶接入批 S1；ChatPage.setConnInfo 按 kill
  // switch × 连接判据写入，@StorageProp 自订阅〔坑16 正解〕）——驱动卡面官方态与文档解析
  // 行卡显隐（均会变化且驱动 UI，状态最小化红线仍守）；false = 非 DS 会话，卡面与行卡照旧
  @StorageProp(CHAT_DS_OFFICIAL_AVAILABLE_KEY) dsAvailable: boolean = false;
  // 官方档偏好（持久键现读；true = 联网卡右侧值显官方名——全局引擎键在官方档下仍存自带
  // 引擎值，直显会误导）
  @StorageProp(PREF_DS_OFFICIAL_WEB_KEY) dsOfficialWeb: boolean = true;
  // 文档服务端解析（@StorageLink 双向：点击行卡取反即写即落盘；消费方 = S4 附件分叉判据）
  @StorageLink(PREF_DS_DOC_SERVER_KEY) dsDocServerParse: boolean = false;
  // 重发面板过滤词（★ 2026-10-31 搜索吸顶笔：真源上提到宿主——搜索框迁进标题栏下方带，
  // 标题栏在宿主 build 里，子件拿不到该承载位；子件经 @Link 双向绑定同一份词。打开面板即清空
  // = 原「面板重建 keyword 归零」语义不变）
  @State private reissueKeyword: string = '';
  // （原「官方 HDS 列表卡可用性」门控已随三卡合流退役——本面板不再消费 HdsListItemCard）

  aboutToAppear(): void {
    // 返回分流登记（与 aboutToDisappear 注销成对；旧件销毁不误清交叠的新件——同一性守卫）
    registerPromptNavStack(this.navStack);
    this.bottomPadInset = this.bottomInset + 24;
    this.reload();
  }

  private reload(): void {
    queryTemplates()
      .then((rows: PromptTemplateRow[]): void => {
        if (this.departed) {
          return;
        }
        this.templates = rows;
      })
      .catch((): void => {
        if (this.departed) {
          return;
        }
        this.templates = [];
      });
    // 会话行三态为枢：有行 = 两卡读行内引用（既有链）；无行（新会话/隐私会话）= 助手卡显
    // assistantBound、提示词卡显 promptBound（页面下发内存覆盖 = 注入真源，无行无库可查）
    queryConversationAssistantId(this.conversationId)
      .then((assistantId: string | null): Promise<void> | void => {
        if (this.departed) {
          return;
        }
        const noRow: boolean = assistantId === null;
        // 有效归属（主面板「助手」卡状态；名称经 queryAssistant 取——查不到 = 已删防御显
        // 空）：行显式绑定优先；行 ''（存量未绑定）= 内置默认助手；null（无行新会话）→
        // 页面下发 assistantBound（恒显式归属，提示词注入开关不影响本卡显示）
        const shownId: string = assistantId !== null && assistantId !== '' ? assistantId :
          (assistantId === null ? this.assistantBound : ASSISTANT_DEFAULT_ID);
        this.assistantId = shownId;
        if (shownId === '') {
          this.assistantName = '';
        } else {
          queryAssistant(shownId)
            .then((row): void => {
              if (this.departed) {
                return;
              }
              this.assistantName = row !== null ? row.name : '';
              if (row === null) {
                this.assistantId = '';
              }
            })
            .catch((): void => {
              if (this.departed) {
                return;
              }
              this.assistantName = '';
            });
        }
        if (noRow) {
          this.currentId = this.promptBound;
          this.currentName = this.promptBound !== '' ? this.nameOf(this.promptBound) : '';
          return;
        }
        return queryConversationPromptId(this.conversationId)
          .then((promptId: string): void => {
            if (this.departed) {
              return;
            }
            this.currentId = promptId;
            this.currentName = promptId === '' ? '' : this.nameOf(promptId);
          });
      })
      .catch((): void => {
        if (this.departed) {
          return;
        }
        this.assistantId = '';
        this.assistantName = '';
        this.currentId = '';
        this.currentName = '';
      });
  }

  private nameOf(promptId: string): string {
    for (const row of this.templates) {
      if (row.id === promptId) {
        return row.name;
      }
    }
    return '';
  }

  // 选词面板选中上行（PromptPickPanel 域件）：更新主面板提示词卡状态 + 回主面板（pop，系统
  // 默认返回转场）+ onPromptChanged 通知页面重载注入缓存；不互斥清助手（归属侧传当前值，
  // 两卡并存）
  private onPromptPicked(promptId: string, promptName: string): void {
    this.currentId = promptId;
    this.currentName = promptId === '' ? '' : promptName;
    this.navStack.pop();
    this.onPromptChanged(promptId, this.assistantId);
  }

  // ── 面板一：三格附件方卡 + 助手卡 + 提示词注入卡 + 技能卡 ──
  @Builder
  MainPanel() {
    Column({ space: CARD_SPACING }) {
      // 三格方卡（域件自带左右 padding 16——两端齐平不双重收窄）
      AttachGridRow({
        onPick: (kind: FilePickKind): void => {
          this.onPick(kind);
        }
      })

      // 助手卡（恒显式归属 = 行绑定 ?? 行 '' 默认兜底 ?? 无行有效归属——右侧三态：id 绑定
      // 且名在显名；id 绑定而名未到或查询失败显「使用中」（id 先置名异步晚到的窗口不谎报
      // 未使用）；id 空（无归属或已删防御复位）显「未使用」；点击进面板三选择；注入优先级
      // 见 ChatPromptState——本卡与提示词注入卡可并存）
      this.SelfListCard('助手',
        (): string => '选择本会话使用的助手',
        $r('sys.symbol.person'),
        (): string => this.assistantId !== '' ? (this.assistantName !== '' ? this.assistantName : '使用中') : '未使用',
        (): void => {
          this.openAssistantPage();
        })

      // 提示词注入卡（独立注入开关：开 = 模板覆盖〔本会话不注入归属助手提示词〕；关 = 注入
      // 归属助手提示词——与助手卡状态可并存，切换经各自面板开关一次完成）
      this.SelfListCard('提示词注入',
        (): string => '发送时在内容前追加固定提示词',
        $r('sys.symbol.doc_text'),
        (): string => this.injectSuffix(),
        (): void => {
          this.openPick();
        })

      // 联网卡（★ 2026-10-30 迁入笔；位置在提示词注入与技能之间——会话覆盖类配置聚拢）。
      // bindMenu 签名无 undefined 不能条件挂载 → 可用性二态走 if/else 双分支，两分支形制同
      // SelfListCard 规格（CARD_PANEL_WIDTH / cardBg / CARD_RADIUS / padding 4 / Button
      // padding 12/9 / 图标 20 / 标题 16 Medium / 副标题 13；★ 2026-11-02 行卡改版笔：
      // 右侧值三态与 SelfListCard suffix 同形制——引擎名自副标题迁右侧，副标题改用处简述）。
      // 可用分支 Button 挂 bindMenu（坑16 弹窗类绑定属性挂原生组件）弹
      // 引擎菜单——SheetMode.OVERLAY 半模态与弹窗类同层级、菜单浮于面板之上（官方文档实锤，
      // 见文件头）；不可用分支点击出指引 toast（原菜单点击守卫语义）。图标 =
      // sys.symbol.magnifyingglass（search_web 工具页同形，sysResource 名称表实锤——坑72）
      if (this.webAllowed) {
        Column() {
          Button() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 2 }) {
                Text('联网')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                Text('回复前先联网搜索相关资料')
                  .fontSize(13)
                  .fontColor(cardDescColor())
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(this.webSuffix())
                .fontSize(14)
                .fontColor($r('sys.color.font_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .bindMenu(this.WebEngineMenuBuilder, {
            // 材质 REGULAR 基准随沉浸光感总档（全菜单统一档——ChatParamChipBar 思考菜单
            // 同款口径）
            systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
              this.immersiveLevel, true)
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
      } else {
        Column() {
          Button() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 2 }) {
                Text('联网')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                Text('回复前先联网搜索相关资料')
                  .fontSize(13)
                  .fontColor(cardDescColor())
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(this.webSuffix())
                .fontSize(14)
                .fontColor($r('sys.color.font_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .onClick((): void => {
            notifyWebOff(this.getUIContext());
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
      }

      // 文档解析行卡（★ DS 全家桶接入批 S1，修订版任务书 S1③——仅 DS 会话〔镜像键 true〕
      // 渲染，非 DS 会话隐藏非置灰；位置随联网卡 = DS 会话相关配置聚拢）。点击切换文档
      // 服务端解析偏好（@StorageLink 双向，写即落盘——消费方 = S4 附件分叉）；右侧值两态：
      //「服务端」= 开、「本地」= 关〔默认〕。★ 附件官方标记笔：副标题改两态现述当前解析方
      //（整卡含副标题本就可点切换，SelfListCard Button 包全卡——副标题随点击即变，当前生效
      //方在卡面双通道可见）。图标 doc_plaintext 全仓 5 处在用（坑72 构建前科充分），与
      // 提示词注入卡 doc_text 不撞形
      if (this.dsAvailable) {
        this.SelfListCard('文档解析',
          (): string => this.dsDocServerParse ?
            'PDF、Word 与 PPT 附件交给 DeepSeek 服务端解析' :
            'PDF、Word 与 PPT 附件在本机解析后随消息发送',
          $r('sys.symbol.doc_plaintext'),
          (): string => this.dsDocServerParse ? '服务端' : '本地',
          (): void => {
            this.dsDocServerParse = !this.dsDocServerParse;
          })
      }

      // 技能卡（副标题 = 功能描述句，右侧值两态：技能名 / 未指定；点击进技能选择子态——只对
      // 本轮生效、发完自动清，不落库）。★ 三侧不对称注释：模型 = 可越过助手且随会话存续 /
      // 联网 = 上限不可越过 / 技能 = 只此一轮不落库——三者不同构是**刻意的**（技能是用户
      // 自写的惰性说明书，只占清单 token 不引入新调用面），防后续自检「顺手统一」
      this.SelfListCard('技能',
        (): string => '为下一条消息指定一个技能',
        $r('sys.symbol.wand_and_stars'),
        (): string => this.skillSuffix(),
        (): void => {
          this.openSkillPage();
        })

      // 重发文件卡（★ 2026-10-31 附件重发笔：主面板第五张行卡——点击进面板五选择已发附件或
      // 工作区文件复制入列；suffix 最简空串不渲染——「已加入」计数等状态归子面板域件，本卡
      // 无状态面）
      this.SelfListCard('重发文件',
        (): string => '选用已发附件或工作区文件再次发送',
        $r('sys.symbol.arrow_clockwise'),
        (): string => '',
        (): void => {
          this.openReissuePage();
        })
    }
    .width('100%')
    .padding({ top: 20, bottom: this.bottomPadInset })
  }

  // 右侧值：模板名（名晚到以 nameOf 兜底，同原副标题口径）；模板已删（两源皆空）回退
  // 「使用中」状态词——注入仍生效，不谎报「未使用」
  private injectSuffix(): string {
    if (this.currentId === '') {
      return '未使用';
    }
    const name: string = this.currentName !== '' ? this.currentName : this.nameOf(this.currentId);
    return name !== '' ? name : '使用中';
  }

  // 子页推入唯一入口（★ 2026-11-25 自检轮补防重入）：push 动画期间主面板仍可点（引擎语义；
  // 先例 = ImageEditPage.nextStage 同款守卫），连点两次会重复入栈同一子页——此时选中后 pop
  // 一次只回到重复页，用户看到「选了没回主面板」。旧 panelMode 换值天生幂等，改栈后必须补
  // 本闸。栈非空 = 已有子页在场（主面板被覆盖），忽略。
  private pushChildPage(name: string): void {
    if (this.navStack.size() > 0) {
      return;
    }
    this.navStack.pushPath(new NavPathInfo(name, null));
  }

  // 打开选词子页（数据/开关逻辑在 PromptPickPanel 域件内自持有——每次打开重建即重拉播种
  // 开关态；滚动归零由域件 aboutToAppear 处理）
  private openPick(): void {
    this.pushChildPage('pick');
  }

  // 技能卡右侧值：有指定 → 技能名；未指定 →「未指定」
  private skillSuffix(): string {
    return this.designateName !== '' ? this.designateName : '未指定';
  }

  // 打开助手选择子页（数据与开关逻辑在 AssistantSheetPanel 域件内自持有）
  private openAssistantPage(): void {
    this.pushChildPage('assistant');
  }

  // 打开技能选择子页（第四子页——原第四子态；选中 = pop 回主面板）
  private openSkillPage(): void {
    this.pushChildPage('skill');
  }

  // 打开重发文件选择子页（第五子页——数据与过滤/行窗逻辑在 ReissuePickPanel 域件内自持有，
  // 每次打开重建即重拉；过滤词真源在宿主，打开即清空 = 原「子件重建 keyword 归零」同语义）。
  // 行点击复制入列后**不 pop**（面板保持开、累加多选）；离开靠返回键或 xmark。
  private openReissuePage(): void {
    this.reissueKeyword = '';
    this.pushChildPage('reissue');
  }

  // 重发子页搜索带（标题栏下方自定义区承载，吸顶）：形制/材质/几何单源 = SearchTopBand
  // （四库页同件，REGULAR 恒光感）；只挂在 reissue 子页的 HdsNavDestination 标题栏上
  // （标题栏选项逐帧重建，见 sheetTitleBarOptions 第 7 参注释），其余子页不占高度
  @Builder
  ReissueSearchBand() {
    SearchTopBand({ keyword: $reissueKeyword, placeholder: '筛选文件' })
  }

  // 右侧值四态（2026-11-02 行卡改版笔：引擎名自副标题迁右侧，副标题改功能简述；★ DS
  // 全家桶接入批 S1 增官方态）：助手未启用 = 「未启用」/ 本会话关 = 「关闭」/ 官方档生效
  //（DS 会话 × 官方档偏好）= 「DeepSeek 官方」/ 其余开态 = 引擎名（webEngineLabel 取名）。
  // 官方档下全局引擎键仍存自带引擎值，直显会误导——官方态判据与发送侧同源
  //（镜像键 × 官方档偏好），哨兵 id 不参与显示面
  private webSuffix(): string {
    if (!this.webAllowed) {
      return '未启用';
    }
    if (!this.webOn) {
      return '关闭';
    }
    if (this.dsAvailable && this.dsOfficialWeb) {
      return 'DeepSeek 官方';
    }
    return webEngineLabel(this.webEngineId);
  }

  // 引擎菜单 builder（★ 迁入笔；坑51/62 形态 = 组件内 @Builder 方法直挂 bindMenu——
  // ChatParamChipBar.ThinkingMenuBuilder 同款先例，全局 @Builder 无组件实例会运行时闪退）。
  // 引擎清单与当前引擎在 builder 体内现读 = 菜单弹出构建时刻快照（bindMenu 菜单树每次弹出
  // 重建），on 走 @StorageProp 订阅键即当刻值
  @Builder
  WebEngineMenuBuilder() {
    WebSearchMenu({ on: this.webOn,
      engines: enabledWebEngineOptions(),
      currentEngineId: currentWebEngineId(),
      onPickEngine: (engineId: string): void => {
        this.onWebEnginePick(engineId);
      },
      onClose: (): void => {
        this.onWebClose();
      } })
  }

  // 技能面板选中上行（SkillPickPanel 域件）：pop 回主面板 + 两值上抛 ChatPage 写 @State（纯
  // 内存态：不落库、不关面板——与 onPromptPicked 同款收口序）。★ 坑16/24/57 族「值参快照
  // 冻结」：@Prop 种子是打开时刻快照，卡面 SelfListCard 是值参 @Builder——不本地落值则
  // 选中后重建读到旧值、「技能」卡副标题与状态字冻结在「未指定」（坑44/80 族症状）。修法
  // = 选中即本地落两 @Prop（@Prop 允许本地写、不上行）；真源仍 = ChatPage 两 @State（发完
  // 自动清）
  private onSkillPicked(skillId: string, skillName: string): void {
    this.designateId = skillId;
    this.designateName = skillName;
    this.navStack.pop();
    this.onSkillDesignated(skillId, skillName);
  }

  // 自制行卡（主面板三卡唯一形态——原 HDS 分支 + 回退分支双链合流退役：官方列表卡蒙层
  // 几何不可控且 cardWidth '100%' 真机渲染崩塌，决明拍板「改成和其他卡完全统一」）。宽度
  // CARD_PANEL_WIDTH = 容器 −32——面板容器不设左右边距，与 HDS 卡 −32 语义同宽对齐。
  // suffix = 右侧当前值文本（font_tertiary 次要色，可空态空串不渲染，单行省略——2026-11-02
  // 行卡改版笔起右侧从二字状态字改为可变长名称，须防换行撑高卡）；图标经参数传入。卡底
  // Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding 12/9 回添，几何零位移
  // ★ 2026-10-31 值参冻结修复（坑16 族）：subtitle/suffix 改传**取字符串的回调**，不传现算
  //   字符串——官方 FAQ《@Builder装饰器参数传递限制与使用方式介绍》判据为「私有 @Builder
  //   按值传递时参数变化不触发内部 UI 刷新，按回调传递才刷新」。本面板三卡文案两源均异步
  //   落值（助手名/模板名 DB 回读），传值形态把卡面冻结在首帧（首帧 state 尚空 = 「未使用」），
  //   只有主面板整页重建才读到真值；改回调后文案在 Text 节点更新闭包里现读状态，异步落值即刷新
  @Builder
  SelfListCard(title: string, subtitle: () => string, icon: Resource, suffix: () => string,
    onTap: () => void) {
    Column() {
      Button() {
        Row({ space: 8 }) {
          SymbolGlyph(icon)
            .fontSize(20)
            .fontColor([cardTitleColor()])
          Column({ space: 2 }) {
            Text(title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text(subtitle())
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (suffix() !== '') {
            Text(suffix())
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .onClick((): void => {
        onTap();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 面板内导航路由表（★ 2026-11-25 会话设置栈化笔；★ 同日标题栏同规格修笔）：主面板 =
  // HdsNavigation 首页（navBar 内容），四个子面板各为外层 HdsNavDestination 子页——push/pop
  // 走系统默认转场。★ 子页壳双层：外层只承路由/转场（hideTitleBar + page_bg 实底），内层
  // HdsNavigation 承标题栏与内容——内层与首页同一 HdsNavigationTitleMode.MODAL 规格
  //（主+副标题 80/72/8），标题栏与一级逐像素同源；HdsNavDestinationTitleMode.MODAL 固定
  // 64/56/8、无副标题 80 档，直接用会矮 16vp（2026-11-25 真机反馈「二级标题栏偏高」）。
  // 取舍（决明拍板）：二级无返回箭头；xmark 关整张、返回手势走栈 pop（与旧版一致）。
  // ★ 子页底色 = page_bg 实底（2026-11-25 二修，决明真机反馈「转场会透、上一页移动一段停顿
  // 卡下再消失」）：① 不能用透明——外层透明时 push/pop 转场窗口内会把上一页及其系统默认退场
  // 视差原样透出（上一页小幅位移后停顿、动画结束被移除；不是两页叠加，也不是自绘动画）；
  // ② 不能回落 STANDARD 默认主题白——白底盖掉宿主面板材质，白卡与底同色不可见（同日首修）；
  // ③ 取正常页同源实底 $r('app.color.page_bg')（浅 #F1F3F5 / 深 #121212，与 PageBackground
  // 默认底、sheetPanelOptions「无」档回退同源）：新页从右滑入即完整遮住上一页，静止时白卡 /
  // 深卡在灰底上可辨，标题栏渐变模糊与正常页同条件。不另垫材质（双层材质比一级更厚）。
  // 坑51：navDestination 必须挂组件内 @Builder 方法。
  @Builder
  PageMap(name: string, _param: Object) {
    if (name === 'pick') {
      // 子页一：选词（PromptPickPanel 域件自持有数据与开关逻辑）
      HdsNavDestination() {
        HdsNavigation() {
          PromptPickPanel({
            conversationId: this.conversationId,
            currentId: this.currentId,
            bottomPadInset: this.bottomPadInset,
            scroller: this.pickScroller,
            onPicked: (promptId: string, promptName: string): void => {
              this.onPromptPicked(promptId, promptName);
            }
          })
        }
        .titleBar(sheetTitleBarOptions('选择提示词', '选择一个提示词注入本会话',
          (): void => {
            this.onClose();
          }, this.immersiveLevel))
        .titleMode(HdsNavigationTitleMode.MODAL)
        .hideBackButton(true)
        .bindToScrollable([this.pickScroller])
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === 'skill') {
      // 子页二：技能选择（互斥 = 自动切换；选中即 pop 回主面板）
      HdsNavDestination() {
        HdsNavigation() {
          SkillPickPanel({
            currentId: this.designateId,
            bottomPadInset: this.bottomPadInset,
            scroller: this.skillScroller,
            onPicked: (skillId: string, skillName: string): void => {
              this.onSkillPicked(skillId, skillName);
            }
          })
        }
        .titleBar(sheetTitleBarOptions('选择技能', '选择一个技能用于下一条消息',
          (): void => {
            this.onClose();
          }, this.immersiveLevel))
        .titleMode(HdsNavigationTitleMode.MODAL)
        .hideBackButton(true)
        .bindToScrollable([this.skillScroller])
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === 'reissue') {
      // 子页三：重发文件（行点击复制入列后不 pop，面板保持开；搜索带挂本页标题栏下方带）
      HdsNavDestination() {
        HdsNavigation() {
          ReissuePickPanel({
            conversationId: this.conversationId,
            // 过滤词真源在宿主（搜索框在标题栏带里，见 ReissueSearchBand 注释）
            keyword: $reissueKeyword,
            bottomPadInset: this.bottomPadInset,
            scroller: this.reissueScroller,
            onPicked: (name: string, srcRelPath: string, workspacePath: string,
              sourceRow: AttachmentListRow | null): Promise<boolean> =>
              this.onReissuePicked(name, srcRelPath, workspacePath, sourceRow)
          })
        }
        .titleBar(sheetTitleBarOptions('选择要重发的文件', '选用已发附件或工作区文件再次发送',
          (): void => {
            this.onClose();
          }, this.immersiveLevel, undefined, undefined,
          // 搜索带 = 标题栏下方自定义区（带高 = segmentBandParams 算式单源）
          segmentBandParams((): void => {
            this.ReissueSearchBand();
          })))
        .titleMode(HdsNavigationTitleMode.MODAL)
        .hideBackButton(true)
        .bindToScrollable([this.reissueScroller])
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === 'assistant') {
      // 子页四：助手选择（选择完成 pop 回主面板 + onPromptChanged 同一通道）
      HdsNavDestination() {
        HdsNavigation() {
          AssistantSheetPanel({
            conversationId: this.conversationId,
            // ★ boundId 必须传本组件 @State 有效归属而非 @Prop assistantBound——后者是半模态
            // 打开时刻快照，选 B 后 ChatPage 无 @State 变化不重建 → @Prop 不刷新 → 重新播种
            // 旧值（坑30/坑75 族值参快照）；@State assistantId 经 onPicked 即时更新；'' 窗口
            //（reload 未定）回落 @Prop 快照防初始闪空
            boundId: this.assistantId !== '' ? this.assistantId : this.assistantBound,
            bottomPadInset: this.bottomPadInset,
            scroller: this.assistantScroller,
            onPicked: (assistantId: string, assistantName: string): void => {
              this.onAssistantPicked(assistantId, assistantName);
            }
          })
        }
        .titleBar(sheetTitleBarOptions('选择助手', '选择一个助手绑定本会话',
          (): void => {
            this.onClose();
          }, this.immersiveLevel))
        .titleMode(HdsNavigationTitleMode.MODAL)
        .hideBackButton(true)
        .bindToScrollable([this.assistantScroller])
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    }
  }

  // 助手子页选中上行（原分支体内联，栈化笔移出 @Builder——同语句同序）：两值落本地 +
  // pop 回主面板 + onPromptChanged 通知页面
  private onAssistantPicked(assistantId: string, assistantName: string): void {
    // 上行恒非空（关闭非默认卡 = 回退默认 id，'' 不再上行）——'' 分支仅防御保留（异常上行）：
    // 显示兜底有效归属 + 异步取名，覆盖上行仍传原值
    const shownId: string = assistantId !== '' ? assistantId : this.assistantBound;
    this.assistantId = shownId;
    if (assistantId === '') {
      queryAssistant(this.assistantBound)
        .then((row): void => {
          if (this.departed) {
            return;
          }
          this.assistantName = row !== null ? row.name : '';
        })
        .catch((): void => {
          if (this.departed) {
            return;
          }
          this.assistantName = '';
        });
    } else {
      this.assistantName = assistantName;
    }
    // 解耦：归属选中不再清提示词引用——注入侧传当前值，两卡并存
    this.navStack.pop();
    this.onPromptChanged(this.currentId, assistantId);
  }

  build() {
    HdsNavigation(this.navStack) {
      // 首页 = 主面板（原有五张卡；首页标题栏 = HdsNavigation MODAL 标题栏）
      Scroll(this.mainScroller) {
        this.MainPanel()
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      // 模糊穿透（内容滚入标题栏背后——滚动容器必须 clip(false)）
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    // 标题栏（主副标题 + xmark 关闭 + AUTO 分割线 + 静止渐变模糊——sheetTitleBarOptions 单源，
    // 勿另写）。★ 2026-10-30 更名「会话设置」（决明拍板——加联网卡后原名「附件与提示词」名
    // 不副实）；★ 2026-11-25 栈化笔：首页标题固定，子页标题各自挂 PageMap 对应页
    .titleBar(sheetTitleBarOptions(
      '会话设置',
      '管理附件、助手、提示词、技能、联网搜索与重发文件',
      (): void => {
        this.onClose();
      }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.mainScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    // 面板内层级：显式 Stack（HdsNavigation.mode 默认 Auto，宽屏会分栏；本版先保障手机
    // 单栏，平板分栏形态另行评估）
    .mode(NavigationMode.Stack)
    // 子页路由表（坑51：挂组件内 @Builder 方法，禁 lambda 直挂）
    .navDestination(this.PageMap)
    .width('100%')
    .height('100%')
  }

  aboutToDisappear(): void {
    unregisterPromptNavStack(this.navStack);
    this.departed = true;
  }
}
