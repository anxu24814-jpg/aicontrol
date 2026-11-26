// 聊天页标题栏覆盖层组件（2026-09-27 域级最小拆分自 ChatPage——宪法 1200 硬线债档）。
// 域定义一句话：聊天页标题栏覆盖层的**内容装配** —— 官方 stackBuilder 恒挂，按会话标题
// 文本广播键两态切换中央区 + 右端〔⋯更多〕单圆键。
// ═══ 2026-11-15 B 路线两态笔（决明「先 b 路线吧，双热区，标题调不了就算了，模型思考调成
// 对话首页顶部分段胶囊一样长」）═══
// · 无标题（新会话，无 DB 行 ⇒ 广播键为 ''）= 中央「模型|思考」双热区胶囊：宽度档与一级页
//   「对话」页签顶部分段胶囊同长（Theme.TITLE_CENTER_ZONE_* 单源，39% / 130~170），键高 40、
//   两热区 layoutWeight(1) 等分，壳体 THIN 材质 + interactive（官方《沉浸光感简介》约束：
//   组件材质只在 Navigation/NavDestination 标题栏生效，挂在覆盖层内才出光感）；
// · 有标题 = 中央两行收进 40vp 光感胶囊（2026-11-24 决明「历史会话标题与下排思考模型也收进
//   光感胶囊，若需要可适当缩小两排间距或字号」+「高度统一，也与返回键相同」笔）：主标题
//   16fp Medium font_primary、单行省略、lineHeight 16；副标题「模型 思考」四字双热区 12fp
//   选中态强调蓝（selectedAccentBlue，与一级页顶部分段胶囊选中字同款）。壳高 40vp =
//   MODEL_ENTRY_HEIGHT = TITLE_ROUND_KEY_SIZE（返回键），半圆端头 MODEL_ENTRY_RADIUS 20 + clip
//   + THIN 材质 + interactive（与胶囊态同基准，挂覆盖层内才出光感）；「无」档壳垫官方灰底
//   （titleCapsuleBg——副标题热区 zoneBg(false) 恒透明，壳自兜底，避免语义色双层叠色）。行高账
//   = 主标题 16 + 两排间距 0 + 副标题行 16 = 32vp ⇒ 上下各 4vp 留白（同日多轮：副标题行
//   24→20→17→16、字号 14→13→12、space 0→2→1→0——末笔「缩第二排字号与两排间距、增大字跟
//   胶囊间距」，两排整体由 Column 垂直居中；左右热区宽 92 不动）。宽度定宽：内层 Column
//   .width(TITLE_CAPSULE_WIDTH = 10×16 + 2×22 = 204vp)，不随标题字数变（「胶囊改定宽」笔撤回
//   内容自适应；「是否太宽了」232→188；「改成 10 字宽」188→204——标题可用 160vp = 10 字，
//   第 11 字起 Ellipsis）。320 窄屏内容区 192 < 204，挂 maxWidth:'100%' 兜底缩到 192。
//   内距 22vp 保留为内部左右留白。字数事实见 TitleGen：AI ≤9 字 / 占位 ≤20 字符 / 用户可改名）。
//   ★ 壳只挂内层 Column，padding 留外层无壳 Row——首版把壳与全宽 padding 挂同一节点致材质
//   铺满屏盖住左右键（真机实锤），本笔修；外层 Transparent 保键可点；
// ═══ 2026-11-15 截断修复笔（决明「部分一级页显示全的标题对话内会截断」）═══
// · 有标题态中央区放开避让全宽：胶囊专档 TITLE_CENTER_ZONE_*（39% / 130~170）是「与一级页
//   分段同长」的可点热区档，只保两热区可点、不保标题显示（360 屏 140.4vp < 一级页会话卡标题
//   行可用宽 ≈196 ⇒ 列表显示全的标题进对话被截断）。改 = Column 全宽 + 左右对称内收
//   TITLE_TEXT_ZONE_INSET（64 = 返回键区右缘，TitleBarKeys 常量推导；右侧更多键区起点 56 < 64
//   天然让位），标题可用宽 360 屏 232 / 320 屏 192，与胶囊、副标题同轴心居中；胶囊态不动。
//   Column 自身矩形全宽——官方触摸测试语义：Stack 重叠时上层节点默认阻塞下层兄弟命中
//   （HitTestMode.Default：节点自身按矩形参与并阻塞兄弟，与有无事件处理器无关）。2026-11-15
//   真机实锤该乐观读不成立（旧会话首帧有标题态 ⇒ 更多键被盖点不动、新会话胶囊态不盖故正常）；
//   修复 = Column 挂 Transparent（官方 API 参考明文：Stack 重叠只有 Transparent 能让下层节点
//   触发触摸测试；None 连子件带下层一起废，勿改）。
// · 两态共用一份双热区动作：左开模型选择面板、右开思考档位菜单（含 thinkingHold 输入栏收起
//   守卫链），bindMenu 全件唯一；
// · 右上〔＋|⋯〕双热区胶囊退役改 TitleBarRoundKey 单圆键〔⋯更多〕，「＋新建会话」收入
//   更多菜单首项（ChatMoreMenu / ChatPageMenuCtrl）；菜单锚点右缘恒 = 屏宽 − 16，与键宽无关，
//   锚点零改动。
// · 几何账（360vp 屏）：左避让 64 = 返回键（16+40+8）、右避让 56 = 更多键 40 + end padding 16；
//   胶囊态中央 140.4vp ⇒ 左缘 109.8 / 右缘 250.2，两侧余 45.8 / 53.8vp；320 窄屏触下限 130 ⇒
//   左缘 95 / 右缘 225，余 31 / 39vp（最紧，与一级页同值）。有标题态标题可用宽 = 屏宽 − 128
//   （360 → 232 / 320 → 192），左右各内收 64 且与屏心同轴。
// ═══ 2026-11-15 真机反馈笔 ═══
// · 胶囊态「思考」字色与「模型」同 font_primary（原占位灰退役）；
// · 有标题两行间距收紧 = Column space 0 + 主标题 lineHeight 16（2026-11-24 高度统一笔自 18 收到
//   16）+ baselineOffset(-2)（反馈二笔定档：行框对称居中由 Stack 保证，字在框内的基线偏上由负
//   offset 回补；行高账 16+0+16=32、壳 40 ⇒ 上下各 4vp 留白，副标题行高同笔收到 16；真机微调位 =
//   offset ±1 / lineHeight 18 回退档）；
// · 进旧会话首帧即两行态 = 预置通道（反馈二笔）：列表/搜索页点卡时同步 seedTitlePreset
//   落两键（标题 + 属主会话 id），ChatPage 进页 adoptPreset 比对属主——一致首帧保留标题
//   （异步反查从此只做校正）、不一致（新建/残留/分享）写 '' 清残留；refreshIfReady 退为
//   校正与无预置路径主查（isReady 门），装载收尾首查仍兜底。
// ═══ 2026-11-15 副标题加大改蓝笔（决明「略大点…四字均改蓝色，同一级对话页顶部胶囊」）═══
// · 只大有标题态（决明拍板）：副标题字号 13→14fp（新常量 TITLE_SUBTITLE_FONTSIZE，不在
//   CARD_NOTE_FONTSIZE 顶值——那档是全应用共享常量）；胶囊态 16fp 黑字零改动。
// · 副标题四字改选中态强调蓝 = Theme.selectedAccentBlue(appColorMode) 单源（浅 #007DFF 与
//   一级页「对话」页签顶部分段胶囊选中字同值；深档 #7CB4FF 提亮保可读——副标题无蓝底承托，
//   不照搬胶囊深档白字）；两热区字色三元随形（胶囊支 font_primary 原样）。
// · 坑30/51/62 红线不变：经官方 stackBuilder 消费的 UI 必须是组件 + 组件内 @Builder 挂载
//   （全局 @Builder 被 napi 直调无视图上下文 → 启动闪退）；二级页覆盖层根须
//   hitTestBehavior(Transparent) 保返回键可点；状态经 @StorageProp/@Link 订阅（坑16 正解，
//   @Prop 沿 titleBarStack 链不保刷新）。
// ═══ 2026-11-25 思考档位滑轨笔（决明「把对话思考等级改为类似这种滑轨」+「关闭就放滑轨最左端吧」
// +「档位前不用图标，提供偏好切换开关」）═══
// · 右热区双形态：偏好 prefThinkingSlider（默认开）= bindPopup 滑轨面板（新件 ThinkingLevelPanel；
//   气泡无箭头、圆角 CARD_RADIUS、宽 280、材质 overlayMaterial、popupColor 为「无光感」档实底
//   回退）；偏好关 = 原 bindMenu 菜单，else 分支逐字保留（零回归路径）。
//   ★ 2026-11-25 滑轨观感修笔：popup 锚点自右热区 Button 改挂两热区整行——Placement.Bottom 的
//   居中口径落在整行中心（= 屏心），卡左右居中；挂 Button 会以右半热区为轴、卡整体偏右。
// · 单档闸：非推理模型只有「默认」一档时不弹面板（防单档死轨），无论偏好如何都走菜单；闸复用
//   ThinkingLevelPanel 导出的 thinkingStops 单源，本件不另写档序。
// · 落值链不变：面板 onPick → thinkingValue @Link（与菜单同一根）→ 页面 → 请求组装；值语义与
//   请求链零触碰。
// · 守卫时序差异：popup 分支 onClick 置 thinkingHold、onStateChange 关闭时放（Up 早于 popup
//   弹出，提前放守卫会让失焦收起链在弹出瞬间收掉输入栏）；菜单分支沿用按压 Down/Up +
//   onAppear/onDisappear。
// ═══ 2026-11-25 五轮·模型思考单热区 + 卡内模型入口（决明「想把模型思考热区合一，点击只弹现在
// 思考卡，档位放右侧，左侧放现有模型名和右箭头，点击弹原模型选择半模态」→ 真机两轮修笔
// 「没有打开思考卡时，标题栏那里仍然显示模型和思考、和原来一样，不要显示具体的模型名和档位」
// +「原本是两个热区，现在只保留一个，整个都是一个热区，点击只打开思考卡」）═══
// · 滑轨形态 = **一条 Button**：文字仍是「模型」「思考」两字各占一半（与旧两热区同观感），
//   点任意位置只弹滑轨卡；菜单形态（偏好关）= 原两热区 + 菜单逐字保留（零回归）。
// · 模型名与档位名只出现在**卡内顶行**（ThinkingLevelPanel）：左 = 模型名 + 右箭头（点开模型
//   半模态）、右 = 当前档位名；点模型名 = 本件先收卡并放守卫，再开半模态；关半模态不回弹。
// · 原「单档走菜单」闸从本件移除：单档域仍用滑轨形态，卡内整条 Slider 不渲染（只剩模型入口行，
//   防死轨且模型入口不丢）；档序单源仍在 ThinkingLevelPanel.thinkingStops。
// · 模型名通道：CHAT_TITLE_MODEL_KEY（AppStorage 广播，写点 = ChatPage.setConnInfo；显示名优先、
//   取不到回落模型 ID）——二级页与侧栏两种形态共用同一订阅通道，零 @Link 双接。
// ★ 隐私会话 2026-09-26 已全链退役；原头注释「左组 + 隐私标记 81vp / 等长上限 95.5vp」
//   宽度预算是退役漏删的失效注释，本笔清理。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial, resolveEffectiveLevel,
  resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { CARD_RADIUS, CARD_SECTION_TITLE_FONTSIZE, cardBg, selectedAccentBlue,
  TITLE_CENTER_ZONE_MAX_WIDTH, TITLE_CENTER_ZONE_MIN_WIDTH, TITLE_CENTER_ZONE_WIDTH } from '../../common/Theme';
import { CHAT_TITLE_MODEL_KEY, CHAT_TITLE_TEXT_KEY, MODEL_ENTRY_FONTSIZE, MODEL_ENTRY_HEIGHT,
  MODEL_ENTRY_LABEL, MODEL_ENTRY_RADIUS, THINKING_ENTRY_LABEL, TITLE_SUBTITLE_FONTSIZE,
  TITLE_SUBTITLE_ROW_HEIGHT, TITLE_SUBTITLE_ROW_WIDTH } from './ChatTitleMenuFactory';
import { CHAT_OFF_SUPPORTED_KEY, CHAT_THINKING_OPTIONS_KEY, ThinkingMenu }
  from './ChatParamChipBar';
import { PREF_THINKING_SLIDER_KEY } from '../../common/AppPreferences';
import { ThinkingLevelPanel } from './ThinkingLevelPanel';
import { TITLE_BAR_EDGE_INSET, TITLE_KEY_GAP, TITLE_ROUND_KEY_SIZE, TitleBarRoundKey }
  from '../TitleBarKeys';

// 有标题态主标题左右对称内收（2026-11-15 截断修复笔）：左 = 返回键区右缘（end padding 16 +
// 圆键 40 + 键间距 8，常量单源自 TitleBarKeys 推导）；右侧更多键区起点为屏宽 − 56 < 64，
// 对称取左值天然让位，主标题与胶囊 / 副标题同轴心居中。360 屏标题可用宽 = 360 − 128 = 232，
// ≥ 一级页会话卡标题行可用宽（≈196）——一级页显示全的标题对话内不再截断；胶囊态宽度档
// TITLE_CENTER_ZONE_* 不适用于有标题态（那一档是「与一级页分段同长」的胶囊专档）。
const TITLE_TEXT_ZONE_INSET: number = TITLE_BAR_EDGE_INSET + TITLE_ROUND_KEY_SIZE + TITLE_KEY_GAP;

// 有标题态胶囊壳内两项（2026-11-24 决明多轮微调：间距 / 定宽 / 胶囊略宽 / 缩第二排腾留白）：
// · 两排间距 0vp——主标题行框与副标题行贴合（space 2→1→0），两排整体靠 Column
//   justifyContent(Center) 垂直居中；腾出的空间全给上下留白（16+0+16=32 < 壳 40 ⇒ 各 4vp）。
// · 内距 22vp（真机反馈「胶囊略宽」笔 12→16→22）——壳定宽后本值只作标题与副标题行两侧的
//   内部留白（不再参与 minWidth 算式；内容自适应宽度已撤回）。
const TITLE_SUBTITLE_GAP: number = 0;
const TITLE_CAPSULE_INNER_PAD: number = 22;
// 胶囊定宽（vp）：2026-11-24 决明「是否太宽了，标题能到这么长吗」→「改成 10 字宽」两笔——
// 原定内容区全宽 232（标题可用 188 ⇒ 约 11.7 字）对 AI 标题 9 字上限（TitleGen 提示词硬约束）
// 偏宽两侧各空 44vp；先收 9 字 188，再按决明定 10 字：10 × 主标题字号 16 + 两侧内距 22×2
// = 204vp，标题可用 160vp = 10 字，第 11 字起 Ellipsis（占位标题 20 字符与用户手动改名同样
// 走 Ellipsis）。★ 320 窄屏内容区仅 192vp < 204 ⇒ 消费点挂 constraintSize maxWidth:'100%'
// 兜底缩到 192（标题可用 148），不溢出、不碰左右键。
const TITLE_CAPSULE_WIDTH: number = 10 * CARD_SECTION_TITLE_FONTSIZE + 2 * TITLE_CAPSULE_INNER_PAD;

@Component
export struct ChatTitleBarOverlay {
  // 思考档位（双向：菜单落值写回页面 @State——refs.thinking 读值进请求）
  @Link thinkingValue: string;
  // 思考键交互期（双向：按压/菜单开合上报——页面经 @Link 三级链下发 ChatInputBar 收起守卫）
  @Link thinkingHold: boolean;
  // 左热区动作：开模型选择面板（页面 openModelSheet）
  onOpenModel: () => void = () => {};
  // 右端单圆键动作：更多菜单（页面 openMoreMenu）；〔＋新建会话〕已收入该菜单首项
  onOpenMoreMenu: () => void = () => {};
  // 左端汉堡键（★ 2026-11-16 首页布局双形态笔）：仅侧栏形态主区标题栏显示——原对话页返回
  // 键位（官方标题栏左端），点击开官方侧边栏。二级页形态不传（缺省 false），几何零影响
  showSidebarKey: boolean = false;
  onOpenSidebar: () => void = () => {};
  // 沉浸光感档位 / 思考菜单选项集 / 「关闭」档可用（@StorageProp 自订阅）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CHAT_THINKING_OPTIONS_KEY) thinkingOptions: string[] = [''];
  @StorageProp(CHAT_OFF_SUPPORTED_KEY) offOk: boolean = false;
  // 会话标题文本（两态判据 + 主标题文案）：写点 = ChatPage 标题反查链；@StorageProp 自订阅
  // 是 titleBarStack 覆盖层的可靠刷新通道（坑16 正解，勿改 @Prop 透传）。
  @StorageProp(CHAT_TITLE_TEXT_KEY) sessionTitle: string = '';
  // 深浅模式（副标题四字改蓝取色：selectedAccentBlue 深浅两档，浅 #007DFF / 深 #7CB4FF 提亮）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // ★ 2026-11-25 思考档位滑轨笔：思考热区形态偏好（true = 滑轨面板〔默认〕/ false = 原菜单）。
  // @StorageProp 自订阅 + @Watch = 拨动开关即刻切换，不用重进会话；关闭形态 = 下面 else 分支的
  // 原 bindMenu 一字未改（零回归路径）。★ 不用 @Prop 沿 titleBarStack 链透传（坑16 正解）。
  @StorageProp(PREF_THINKING_SLIDER_KEY) @Watch('onFormPrefChange') sliderForm: boolean = true;
  // 滑轨面板显隐（bindPopup 受控 show；关闭统一由 onStateChange 回写复位）
  @State private panelShow: boolean = false;
  // ★ 2026-11-25 五轮「模型思考热区合一」：当前模型显示名（卡内模型入口文案；五轮真机修笔
  // 已定标题栏热区只留「模型」「思考」两字、不显示具体模型名与档位）。写点 =
  // ChatPage.setConnInfo（显示名优先、取不到回落模型 ID，解析失败写 ''）；
  // 读侧走 @StorageProp 广播订阅——二级页形态与侧栏形态（DrawerHomeTitleBar 跨层装配）共用同一
  // 通道，避免 @Link 双形态各接一份（坑16 正解：@Prop 沿 titleBarStack 链不保刷新）。
  @StorageProp(CHAT_TITLE_MODEL_KEY) titleModelName: string = '';

  // 偏好关掉时若面板正开 = 立即收起并放掉输入栏收起守卫（形态切换不留悬空守卫）
  private onFormPrefChange(): void {
    if (!this.sliderForm && this.panelShow) {
      this.panelShow = false;
      this.thinkingHold = false;
    }
  }

  // 标题栏键材质档（沉浸光感总档 → 生效档位；与 hdsTitleBarOptions 同一解析）。
  // ★ 2026-11-17 对齐笔：flatKeys 档整档退役——侧栏形态标题栏上收官方 stackBuilder 插槽
  //（DrawerHomeTitleBar），键回官方生效区出材质，非生效区消费位不复存在
  private titleBarKeyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  // 双热区底色：胶囊态「无」档 = 两热区各垫官方纯色底（左半/右半拼出整胶囊，壳体不垫，
  // 防语义色透明度双层叠色内圈——坑58）；有材质档 = 透明底由壳体材质承接；副标题态恒透明。
  private zoneBg(capsule: boolean): ResourceColor {
    if (!capsule) {
      return Color.Transparent;
    }
    return this.titleBarKeyLevel() < 0 ?
      $r('sys.color.comp_background_tertiary') : Color.Transparent;
  }

  // 原生按压：仅胶囊态「无」档保留（材质生效时开原生按压会与形变/触点光效叠色——坑58）
  private zoneStateEffect(capsule: boolean): boolean {
    return capsule && this.titleBarKeyLevel() < 0;
  }

  // 有标题态胶囊壳底色（2026-11-24 高度统一笔）：副标题两热区 zoneBg(false) 恒 Transparent，
  // 壳需自己兜底——「无」档垫官方纯色灰（与胶囊态 zoneBg(true) 同值），有材质档 Transparent
  // 由 THIN 材质承接（材质铁律：设了材质不叠底色，否则语义色透明度双层叠色出内圈色块——坑58）。
  // 壳的 systemMaterial 与原生按压两属性均不随本函数变（按压在热区 Button 上，capsule=false 恒 false）。
  private titleCapsuleBg(): ResourceColor {
    return this.titleBarKeyLevel() < 0 ?
      $r('sys.color.comp_background_tertiary') : Color.Transparent;
  }

  // 热区文字两态色单源（★ 2026-11-25 五轮抽件）：胶囊态 font_primary（2026-11-15 反馈笔
  // 「思考与模型同黑」）、副标题态选中态强调蓝 selectedAccentBlue（2026-11-15「四字改蓝」笔）。
  // 两热区四字与菜单形态文案同走本函数——不各写一份三元，防字色漂移
  //（assert-ui-shape ㊲ 组钉守「除本函数外零第二份两态三元」）。
  private zoneTextColor(capsule: boolean): ResourceColor {
    return capsule ? $r('sys.color.font_primary') : selectedAccentBlue(this.appColorMode);
  }

  // 模型入口文案（★ 五轮）：显示名优先，空串回落「模型」（回落只在本件做一次——卡内模型入口
  // 文案经 ThinkingPanelHost 传入面板，面板内不再写第二份兜底）。
  private modelText(): string {
    return this.titleModelName !== '' ? this.titleModelName : MODEL_ENTRY_LABEL;
  }

  // 合并热区文案（★ 2026-11-25 五轮真机最终口径）：文字仍是「模型」「思考」四个字，各占一半宽
  // 居中（与旧两热区逐像素同观感），但**整条是一个热区**——点任意位置只弹滑轨卡，模型入口只在
  // 卡内顶行（左模型名+箭头）。副标题态同样两字各半、12fp、强调蓝。
  @Builder
  MergedZoneLabel(capsule: boolean, fontSize: number) {
    Row() {
      Text(MODEL_ENTRY_LABEL)
        .width('50%')
        .textAlign(TextAlign.Center)
        .fontSize(fontSize)
        .fontWeight(capsule ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.zoneTextColor(capsule))
      Text(THINKING_ENTRY_LABEL)
        .width('50%')
        .textAlign(TextAlign.Center)
        .fontSize(fontSize)
        .fontWeight(capsule ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.zoneTextColor(capsule))
    }
    .width('100%')
  }

  // 思考档位菜单（bindMenu builder 位——菜单体 = 共享 ThinkingMenu 组件，与助手「模型设置」
  // 页同款，选项集/关闭档可用性走广播键自订阅）。★ 坑51/62：挂本组件内 @Builder 方法。
  @Builder
  ThinkingMenuBuilder() {
    ThinkingMenu({ value: $thinkingValue, options: this.thinkingOptions, offOk: this.offOk,
      onPick: (option: string): void => {
        this.thinkingValue = option;
      }
    })
  }

  // 滑轨面板宿主（★ 2026-11-25 思考档位滑轨笔）：popup builder 必须经组件内 @Builder 转发——
  // 禁在箭头函数里直接 new 组件（ChatMessageItem「用量气泡宿主」条 TypeError 闪退实锤）；
  // 落值与菜单分支同一条链（thinkingValue @Link → 页面 @Link → 请求组装），零新增链路。
  // ★ 五轮：卡内模型入口 = 模型名（本件 modelText 统一兜底）+ onOpenModel 上行；此回调**先收本卡
  // 并放掉输入栏收起守卫**，再开模型选择半模态——半模态是全屏面板，卡不先行收起会与其叠层，
  // 且 autoCancel 关闭链的守卫回落不可依赖（面板层已先拿走焦点）。关半模态不回弹本卡（无回写）。
  @Builder
  ThinkingPanelHost() {
    ThinkingLevelPanel({
      value: this.thinkingValue,
      options: this.thinkingOptions,
      offOk: this.offOk,
      modelName: this.modelText(),
      onOpenModel: (): void => {
        this.panelShow = false;
        this.thinkingHold = false;
        this.onOpenModel();
      },
      onPick: (option: string): void => {
        this.thinkingValue = option;
      }
    })
  }

  build() {
    // Stack 叠三层：左组（汉堡键，侧栏形态才有）→ 右组（全宽占位仅右端出键）→ 中央区（上层）
    //——顺序不可反，反了则全宽组压住中央双热区的点击热区（先例 = TabMoreMenu.ChatTabTitleBar）。
    Stack({ alignContent: Alignment.Center }) {
      if (this.showSidebarKey) {
        // 左端汉堡键（侧栏形态主区常驻态）：TitleBarRoundKey 共用件（右端更多键同形制），
        // 左避让与右组对称（TITLE_BAR_EDGE_INSET）
        Row() {
          TitleBarRoundKey({
            icon: $r('sys.symbol.open_sidebar'),
            label: '打开侧栏',
            immersiveLevel: this.immersiveLevel,
            onTap: (): void => {
              this.onOpenSidebar();
            }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: TITLE_BAR_EDGE_INSET })
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        // 全宽行只负责定位，空白区不得阻塞相邻键；子按钮仍正常命中。
        .hitTestBehavior(HitTestMode.Transparent)
      }
      Row() {
        TitleBarRoundKey({
          icon: $r('sys.symbol.dot_grid_2x2'),
          label: '更多',
          immersiveLevel: this.immersiveLevel,
          onTap: (): void => {
            this.onOpenMoreMenu();
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ right: TITLE_BAR_EDGE_INSET })
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      // 本行位于左键之后。若空白区仍走 Default，会按全宽矩形截走汉堡键触摸。
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.sessionTitle === '') {
        // ── 新会话态：中央加长双热区胶囊（带沉浸光感）──
        Row() {
          this.ModelThinkingZones(true, MODEL_ENTRY_FONTSIZE);
        }
        .width(TITLE_CENTER_ZONE_WIDTH)
        .constraintSize({
          minWidth: TITLE_CENTER_ZONE_MIN_WIDTH,
          maxWidth: TITLE_CENTER_ZONE_MAX_WIDTH
        })
        .height(MODEL_ENTRY_HEIGHT)
        .borderRadius(MODEL_ENTRY_RADIUS)
        .clip(true)
        .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN,
          this.immersiveLevel, true))
      } else {
        // ── 有标题态：主标题 + 「模型 思考」副标题双热区，两行整体收进 40vp 光感胶囊
        //（2026-11-24 决明「也收进光感胶囊、高度与返回键相同」笔 + 同日真机反馈「字贴边、
        // 胶囊盖住左右键」修笔）。★ 两层结构：外层 Row 全宽只做内收与命中透传（不挂壳），内层
        // Column 才挂胶囊——壳定宽 204vp（TITLE_CAPSULE_WIDTH），仅由 constraintSize maxWidth:'100%'
        // 对 320 窄屏兜底缩到 192，不铺满屏，左右键（返回 64 / 更多 56 避让区）露在壳外可点可看。首版把
        // padding 与壳挂同一全宽 Column 上，padding 是内边距 ⇒ 材质/clip 画在整屏矩形上盖住
        // 左右键（真机实锤）。
        // 高度账 = 主标题 lineHeight 16 + 两排间距 0 + 副标题行 16 = 32vp，壳高 40vp ⇒ 上下各
        // 4vp 留白（反馈多轮：副标题行 24→20→17→16、字号 14→13→12、两排 space 0→2→1→0——
        // 末笔「缩第二排字号与两排间距、增大字跟胶囊间距」，两排整体由 Column 垂直居中；
        // 左右热区宽 92 不动）；40vp = MODEL_ENTRY_HEIGHT =
        // TITLE_ROUND_KEY_SIZE（返回键）。baselineOffset(-2)
        // 沿用 2026-11-15 反馈二笔（负 offset 把偏上的字推回行框中心，d.ts:633 正值上移负值下移）。
        // ★ 宽度定宽（同日三笔：「改定宽不随标题变」→「是否太宽了」232→188→「改成 10 字宽」
        //   188→204）：内层 .width(TITLE_CAPSULE_WIDTH = 10 字 × 16fp + 2×内距 22 = 204vp)，
        //   标题 Text .width('100%') 占满内距内 160vp = 10 字，第 11 字起 Ellipsis（占位 20 字符
        //   与用户改名同走 Ellipsis）。320 窄屏内容区 192 < 204 ⇒ maxWidth:'100%' 兜底缩到 192
        //（标题可用 148），不溢出、不碰左右键（避让区 64/56 在胶囊外）。
        // 壳 = borderRadius(MODEL_ENTRY_RADIUS 20) + clip + THIN 材质 interactive，与新会话胶囊
        // 同基准（挂覆盖层内才出光感）；「无」档由 titleCapsuleBg 垫官方灰，两态观感同源。
        Row() {
          Column({ space: TITLE_SUBTITLE_GAP }) {
            Text(this.sessionTitle)
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .lineHeight(16)
              .baselineOffset(-2)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .width('100%')
            Row() {
              this.ModelThinkingZones(false, TITLE_SUBTITLE_FONTSIZE);
            }
            .width(TITLE_SUBTITLE_ROW_WIDTH)
            .height(TITLE_SUBTITLE_ROW_HEIGHT)
          }
          .width(TITLE_CAPSULE_WIDTH)
          // 320 窄屏内容区 192 < 定宽 204：上限兜底到父内容区，不溢出、不碰左右键
          //（360 屏 204 生效；只封上限、不参与内容自适应，minWidth 仍禁）
          .constraintSize({ maxWidth: '100%' })
          .padding({ left: TITLE_CAPSULE_INNER_PAD, right: TITLE_CAPSULE_INNER_PAD })
          .height(MODEL_ENTRY_HEIGHT)
          .borderRadius(MODEL_ENTRY_RADIUS)
          .clip(true)
          .backgroundColor(this.titleCapsuleBg())
          .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN,
            this.immersiveLevel, true))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ left: TITLE_TEXT_ZONE_INSET, right: TITLE_TEXT_ZONE_INSET })
        // 全宽矩形默认 Default 阻塞下层兄弟（右 padding 区盖住更多键，真机实锤点不动）；Transparent
        // 透传空白区触点且内层胶囊内子件（双热区 Button）照常命中（None 连子件带下层一起废，
        // 勿改——官方 API 参考「触摸测试控制」示例 4：Stack 重叠只有 Transparent 能让下层响应）
        .hitTestBehavior(HitTestMode.Transparent)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    // 二级页覆盖层整栏铺在返回键上方，空白区须透传触摸（规范 §4）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 热区渲染体（组件内 @Builder，两态各调用一次、同一时刻只渲染一态）：
  // capsule=true = 40vp 胶囊热区（16fp、Medium font_primary、半圆端头）；capsule=false = 16vp
  // 副标题行（12fp、选中态强调蓝）。字色单源 = zoneTextColor（见上）。
  // ★ 2026-11-25 五轮真机最终口径（决明两轮）：「没有打开思考卡时，标题栏那里仍然显示模型和
  // 思考、和原来一样，不要显示具体的模型名和档位」+「原本是两个热区，现在只保留一个，整个都是
  // 一个热区，点击只打开思考卡」——滑轨形态 = **一条** Button，文字仍是「模型」「思考」两字各占
  // 一半（与旧两热区同观感），点任意位置只弹滑轨卡；菜单形态（偏好关）= 原两热区 + 菜单逐字保留。
  // 模型名与档位名只出现在**卡内顶行**，标题栏不显示。
  @Builder
  ModelThinkingZones(capsule: boolean, fontSize: number) {
    Row() {
      if (this.sliderForm) {
        // 单热区：点任意位置只弹滑轨卡（不弹菜单、不直开模型半模态——模型入口在卡内顶行）。
        // 按压即置收起守卫，关闭由 popup 的 onStateChange 统一回落——本分支刻意不挂 onTouch 的
        // Up 复位（Up 早于 popup 弹出，提前放守卫会让失焦收起链在弹出瞬间收掉输入栏）。
        Button() {
          this.MergedZoneLabel(capsule, fontSize)
        }
        .type(ButtonType.Normal)
        .layoutWeight(1)
        .height(capsule ? MODEL_ENTRY_HEIGHT : TITLE_SUBTITLE_ROW_HEIGHT)
        .padding(0)
        .borderRadius(capsule ? MODEL_ENTRY_RADIUS : 0)
        .backgroundColor(this.zoneBg(capsule))
        .stateEffect(this.zoneStateEffect(capsule))
        .accessibilityText('模型与思考')
        .onClick((): void => {
          this.panelShow = true;
          this.thinkingHold = true;
        })
      } else {
        // ── 菜单形态（偏好关）：原「模型|思考」两热区 + bindMenu 逐字保留（零回归路径）──
        Button() {
          Text(MODEL_ENTRY_LABEL)
            .fontSize(fontSize)
            .fontWeight(capsule ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.zoneTextColor(capsule))
        }
        .type(ButtonType.Normal)
        .layoutWeight(1)
        .height(capsule ? MODEL_ENTRY_HEIGHT : TITLE_SUBTITLE_ROW_HEIGHT)
        .padding(0)
        .borderRadius({
          topLeft: capsule ? MODEL_ENTRY_RADIUS : 0,
          bottomLeft: capsule ? MODEL_ENTRY_RADIUS : 0
        })
        .backgroundColor(this.zoneBg(capsule))
        .stateEffect(this.zoneStateEffect(capsule))
        .accessibilityText('模型')
        .onClick((): void => {
          this.onOpenModel();
        })
        Button() {
          this.ThinkingZoneLabel(capsule, fontSize)
        }
        .type(ButtonType.Normal)
        .layoutWeight(1)
        .height(capsule ? MODEL_ENTRY_HEIGHT : TITLE_SUBTITLE_ROW_HEIGHT)
        .padding(0)
        .borderRadius({
          topRight: capsule ? MODEL_ENTRY_RADIUS : 0,
          bottomRight: capsule ? MODEL_ENTRY_RADIUS : 0
        })
        .backgroundColor(this.zoneBg(capsule))
        .stateEffect(this.zoneStateEffect(capsule))
        .accessibilityText('思考')
        .bindMenu(this.ThinkingMenuBuilder, {
          // 标题栏在屏顶，菜单向下展开；材质 REGULAR 基准随沉浸光感总档（弹窗豁免区）
          placement: Placement.BottomLeft,
          // ★ 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
          systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true),
          // 菜单开合上报（输入栏收起守卫：菜单弹窗取焦致 TextArea 失焦，不收）
          onAppear: (): void => {
            this.thinkingHold = true;
          },
          onDisappear: (): void => {
            this.thinkingHold = false;
          }
        })
        // 按压期即置守卫（Down→Up 之间失焦可能先到，150ms 收起计时器须被拦；Up 后菜单
        // onAppear 接续，交互全程守卫不断）
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) {
            this.thinkingHold = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.thinkingHold = false;
          }
        })
      }
    }
    .width('100%')
    .height(capsule ? MODEL_ENTRY_HEIGHT : TITLE_SUBTITLE_ROW_HEIGHT)
    // ★ 2026-11-25 滑轨观感修笔（决明「滑轨卡左右居中」）：popup 挂在**两热区整行**而非右热区
    // Button 上——本行宽度 = 中央胶囊/副标题行宽且整体在屏心，Placement.Bottom 的水平居中口径
    // 即屏心（挂 Button 上会以右半热区中心为轴，卡整体偏右）。builder 仍经组件内 @Builder 转发
    // （见 ThinkingPanelHost）；宽度/圆角/材质/关闭链与原挂载点逐项同值，只有 anchor 与
    // placement 改判。偏好关（菜单形态）时 panelShow 恒 false，本绑定点不出现，零回归。
    .bindPopup(this.panelShow, {
      // popup builder 必须经组件内 @Builder 转发（见 ThinkingPanelHost 注释）
      builder: (): void => {
        this.ThinkingPanelHost();
      },
      // 标题栏在屏顶，面板向下展开、相对整行水平居中（= 屏心）；无箭头浮卡、圆角与气泡族同值
      placement: Placement.Bottom,
      enableArrow: false,
      radius: CARD_RADIUS,
      // 宽度显式给（popup 不显式给时按内容走，面板会被滑块撑成不定宽）；
      // 2026-11-25 四轮「卡整体略小」：296 → 280
      width: 280,
      // 菜单不压暗，面板同样不压暗；autoCancel 走官方默认 true（点外部关）
      mask: false,
      targetSpace: 8,
      // 弹层族材质单源（ULTRA_THICK 基准随沉浸光感总档）；popupColor = 「无光感」档专用
      // 实底回退（材质生效时官方忽略该值，先例 = UsageHeatMap）
      systemMaterial: overlayMaterial(),
      popupColor: cardBg(this.appColorMode),
      // 关闭链：系统路径关闭（点外部 / 自动避让）统一回写复位，守卫随之放掉
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) {
          this.panelShow = false;
          this.thinkingHold = false;
        }
      }
    })
  }

  // 思考热区文案（★ 2026-11-25 双形态笔抽件）：菜单形态用，字号/字重/字色单源
  //（防两形态漂移）。字色走 zoneTextColor（五轮起与合并热区共用同一两态三元）。
  @Builder
  ThinkingZoneLabel(capsule: boolean, fontSize: number) {
    Text(THINKING_ENTRY_LABEL)
      .fontSize(fontSize)
      .fontWeight(capsule ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.zoneTextColor(capsule))
  }
}
