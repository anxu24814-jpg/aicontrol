// 功能模型页（2026-09-05 决明指令「设置页新增功能模型卡，点击进二级页，先放默认模型
// 行卡」；同日大卡改版「复刻参考图首卡——卡片增大，服务商胶囊移左上，唯一按钮选择模型，
// 接入光感，点击后仍弹原半模态」，并改名「默认对话模型」）：功能级模型配置集中页——
// 后续 AI 功能模型项均入此页，首项「默认对话」（2026-09-06 去「模型」二字，见下方星节）。
// · 默认对话 = 发送链四级兜底第③级来源（resolveActiveConnection：会话页所选 > 会话所属
//   助手绑定 > 全局默认 > 首个启用模型，中途不停）——DEFAULT_PROVIDER_KEY/DEFAULT_MODEL_KEY
//   两 AppStorage 持久键（EntryAbility persistProp 注册，'' = 未设置），选完即时生效，
//   无保存键无 onPop（偏好页同款口径）。
// · 卡片形态（2026-09-05 大卡改版后同日二轮调形「提示收入气泡放右上角——InfoHintButton
//   服务商配置页先例；图标与服务商胶囊改黑白灰；图标圆底；按钮官方胶囊形纵高略缩」；
//   ★ 2026-09-20 两笔收敛——先「模型名移至标题行下副标题处」，再「首卡图标与服务商都删掉」）：
//   首卡 = 顶部行（「默认对话」标题 16fp cardTitleColor + 右上角 ⓘ 气泡——说明文字收入气泡）
//   + 模型显示名（15fp，对齐 ModelSettingsPage.ModelDisplayRow 先例——决明「模型名字号小一点，
//   同步字号」）+ 通宽「选择模型」主按钮（官方默认胶囊与字号，形态对齐 DataSyncPage「导出
//   备份到本机」键——决明指令「键宽对齐」）；**图标圆底与服务商名行已删**，首卡自此与同页
//   五卡同构（标题行 → 副标题 → 卡内控件 → 操作键，只多一条通宽主键）。
//   整卡点击移除——唯一交互点 = 按钮（ⓘ 点击弹气泡）。
// ★ 2026-09-06 卡名与标题调形（决明指令）：两卡标题去「模型」二字 = 「默认对话」「标题
//   生成」（常量单源 SettingSearch，搜索 keywords 保留旧名兼容）；标题字号 13fp 灰 →
//   16fp cardTitleColor（AboutPageCards 卡标题同款形制——项目内卡片标题语义先例）；
//   标题生成卡说明小字同步收右上角 ⓘ 气泡，与默认对话卡同构（模型名显示行随之下移独立行）。
// ★ 2026-09-08 第三卡「记忆提取模型」（先行笔，任务书 §2.1/§2.2；同日决明指令取消回退）：
//   记忆整理用哪个模型从「共用标题生成模型」解耦为独立可配——两键未配置 = 不整理（与标题
//   生成同口径，**不回退标题模型**，记忆页「立即整理」前置 toast 引导）；「提示词」键开同一
//   编辑半模态（保存校验 {content}、恢复默认清键回内置——生效模板单源 MemoryGen）。
// · 按钮 = 主操作键光感四件套 + 内容区回退双态（DataSyncPage.ActionBtn 先例：fallbackButton*
//   primary=true——实底态官方强调蓝 + font_on_primary 恒白，光感态 primary 材质随
//   CONTENT_FALLBACK_KEY 开关）；点击弹 ModelPickerSheet 半模态（原半模态不变）。
// ★ 2026-09-11 决明「『标题生成』『记忆提取』『记忆优化』这 3 个选择模型的键都改成蓝底」：
//   四张卡的「选择模型」统一为主操作键 primary=true（首卡原即此形制，本笔补齐后三卡）；
//   「提示词」键与提示词面板的「恢复默认」仍为次钮。
// · 选择器 = ModelPickerSheet 半模态复用（ModelSettingsPage「同会话页」机制同款）：
//   直传 default 两键打勾（不读写会话级覆盖——两者各管一级
//   互不污染）；选中即写键收面板。
// ★ 2026-09-11 第四卡「记忆优化模型」（「记忆优化模型」二期，方案-记忆整理优化-20260911
//   §6.1）：对库内已有记忆做去重与改写的模型从提取模型解耦为独立可配——两键未配置 = 不优化
//   （不回退提取模型，同前两卡口径），卡形制同记忆提取卡。★ 同日二期收尾开放「提示词」键
//   （决明「完全对齐标题生成与记忆提取的提示词展示与编辑功能」；方案 §6.5 Q5 原推荐一期不
//   开放，本次拍板升级）——至此四卡形制齐整：首卡单键，后三卡各「选择模型」+「提示词」双键。
// ★ 2026-09-15 第五卡「文字识别」（附件 OCR 二期，任务书-附件OCR链路 §3.8）：总开关
//   （默认开）+ 引擎显示行 + 主操作键；说明气泡含出网事实（用已选模型时图片发给你配置的
//   服务商，拍板 #6）。
// ★ 2026-09-16 决明拍板「系统识别开关化」（本卡重做）：原「选择引擎」内联面板退役——首行
//   「系统识别」非模型项改由**第二枚开关**承载（系统识别：开 = 优先系统识别、关 = 用已选
//   模型；未选模型时开关禁用 + 副行说明口径），选择面板因此回归共用件 **ModelPickerSheet**
//   （搜索/收藏/当前选择卡等规范样式齐活），主键随同页四卡改「选择模型」。取舍原委 = 内联
//   面板的唯一动因就是承载不了非模型项，开关化把该动因消掉（详见变更记录六百三十七节）。
// ★ 2026-09-16 第五卡再改「内置识别引擎」（方案-内置PaddleOCR-20260916 §3.5 决明拍板③）：
//   第二枚开关退役 → **卡内三分段胶囊**「系统识别 / 内置识别 / 视觉模型」（共用件 SegmentBar，
//   参数零覆盖）。段选行为：系统/内置 = 即选即生效（写引擎三态键 OCR_ENGINE_KEY）；视觉模型
//   未配置 = 弹既有 ModelPickerSheet 半模态 + **段位程序化回退原值**（分段件 selectedIndex
//   受控，与 Toggle「被拒不回弹」不同，无坑）；内置识别段在真机 canIUse 探测为假时按官方
//   item enabled 位置灰禁选。副行三态各一句说明（文案规约：无冒号分号括号连环；不写「手写」、
//   不承诺准确率）。★ 与方案字面的一处偏差（书外补充，理由 = 验收操作单 ⑤ 要求「把视觉模型
//   指向一个故意填错 Key 的已配模型」——段选只在未配置时开面板，已配置后换模型将无路可走）：
//   「选择模型」主键不在系统/内置段显示，仅在视觉模型段保留（形制与文案不变）。
// ★ 2026-09-16 决明指令：第三、四两卡标题去「模型」二字定名「记忆提取」「记忆优化」——
//   与 2026-09-06 前两卡同款去法，卡名常量单源 SettingSearch（搜索 keywords 保留旧名兼容，
//   帮助与记忆页 toast 的卡片指代随同跟改）；本页三处卡片显示文案零改动（标题取常量、
//   ⓘ 与显示行不含卡名）。
// ★ 2026-09-17 决明指令「识图用视觉模型时只有选择模型键，能否像其他功能模型一样提供两个
//   按键（选择模型 + 编辑提示词，开放查看/编辑/恢复默认）」：文字识别卡视觉模型段由单键
//   扩为双键（「提示词」= 次钮），识别提示词入既有编辑半模态——第四提示词槽，由
//   resolvePromptSlot 按 sheetKind='ocrPrompt' 取规格（无占位符：图片以附件部件随请求发送，
//   不是文本插值，保存不校验占位符但拦空串——写 '' 会静默变回内置，观感与保存动作不符）。
//   提示词键与内置模板单源 OcrVisionApi（OCR_PROMPT_KEY / OCR_PROMPT_TEMPLATE /
//   resolveOcrPromptTemplate），本页零复写。控制台助手的 edit_title_prompt 工具同批跟上
//   第四槽（决明「接入工具」——同 2026-09-11 第三槽先例，UI 开编辑则工具面同步，见
//   ToolFunctional 头注释）。
// ★ 2026-09-22 记忆导入笔第六槽（决明「复用卡，但执行的是不同的任务和不同的提示词」）：
//   「记忆提取」卡加第三键「导入提示词」——导入整理（把外部 AI 平台的用户总结整理成条目）
//   与自动整理共用同一对模型键，但**提示词独立成第六槽**（输入域不同：一个是外部平台文本，
//   一个是本库会话记录，不能共用一份模板）。本卡布局随之由「选择模型 | 提示词」单行双键改
//   为两行（上行通宽选择模型 + 下行提示词 | 导入提示词）——三键一行的宽度实测依据见
//   MemoryModelCard 卡内注释。键与内置模板单源 MemoryImport 域（MEMORY_IMPORT_PROMPT_KEY /
//   MEMORY_IMPORT_PROMPT_TEMPLATE / resolveMemoryImportPromptTemplate），本页零复写；
//   控制台助手的 edit_title_prompt 工具同批跟上第五槽（同前两槽先例）。
// ★ 提示词槽的**三处联动铁律**（本笔再次踩到其边界）：新增一个提示词槽必须同笔改三处——
//   ①槽规格表加分支（★ 2026-09-23 关闭确认笔起该表在 `components/settings/PromptSlotSpec.ets`；
//   漏 = 未知 sheetKind 静默落默认标题槽，编辑保存会 **写到标题提示词键上**，最隐蔽的改错键）；
//   ②本页 sheetKind 值域注释；③本页 isPromptSheet() 加 `||` 项（漏 = 面板不渲染，点键没
//   反应）。三处任一漏改都能编译通过，故 58 组槽配对钉按「分支段逐个字段对表」守，不靠记性。
// ★ 2026-09-23 半模态关闭确认笔（两件事）：①**提示词槽规格表外移** `PromptSlotSpec.ets`
//   （PromptSlot + resolvePromptSlot 逐字搬迁，另加新增的 effectivePromptOf）——本页当时 1180
//   行临 1200 硬线，本次改动所属域恰是「提示词槽规格与生效值」，按宪法「域级最小拆分」外置；
//   ②**编辑面板加关闭前确认**：编辑过且未保存时（脏态 = promptContent.trim() 与
//   effectivePromptOf 现读值不等），标题栏关闭键与手势/系统返回两路都先问「放弃这次修改？」，
//   未通过则面板保持打开；未编辑直接关；点「保存」照旧直接落库并关面板（程序化关闭不经确认）。
//   两路单源 = requestClosePrompt——`onWillDismiss` 是「选择模型」与「提示词编辑」**共用的一个
//   lambda**，必须按 isPromptSheet() 分流，一刀切会让选择模型也弹确认（功能回归）。
// ★ 2026-09-20 决明指令「功能模型页把模型名移至标题行下副标题处（与标题生成卡统一），下面
//   几个有开关的卡注意卡内组件与排版」——本页六卡「当前选择」行统一到同一槽位：紧接标题行
//   之下、卡内其余组件之前，15fp（未选 / 指向行已删 = 「未选择」灰字）。改动三处 = ①首卡
//   「默认对话」模型名自图标行内上移为副标题（服务商标识行自此只留图标圆底 + 服务商名），
//   卡内间距并入 `Column({ space: 14 })` 统一律（原两处 `.margin({ top: 12 })`）；②「文字
//   识别」卡模型行自视觉模型段上移为常显副标题（引擎三段皆在——分段胶囊表达生效引擎、副标题
//   表达已选模型；视觉段此后只留双键）；③「推荐问题」卡模型行上移，卡内开关行随之下移。标题
//   生成 / 记忆提取 / 记忆优化三卡原即此槽位，零改动（副标题槽的字号、灰字判据、文案三处
//   照旧，改动纯位置）。★ 同日补笔（决明「首卡图标与服务商都删掉」）：首卡服务商标识行整行
//   删除（图标圆底 44vp + 服务商名 13fp），连带 `ModelDisplayState.providerName` 字段、
//   `providerName` @State 镜像、`badgeBg` 导入三件退役——首卡自此与其余五卡同构。
// · 显示名解析：providerId/modelId → 模型显示名（name 空兜底 modelId）；
//   指向行已删 = 显示「未选择」（读侧窗口期兜底不写键——missing 态，解析链侧另有降级，
//   两处独立）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { SegmentBar } from '../SegmentBar';
import { PageShell } from '../../common/PageShell';
import { ROUTE_FUNCTIONAL_MODEL_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_DEFAULT_MODEL, SETTING_TITLE_FUNCTIONAL_MODEL,
  SETTING_TITLE_MEMORY_MODEL, SETTING_TITLE_MEMORY_OPT_MODEL, SETTING_TITLE_OCR,
  SETTING_TITLE_TITLE_MODEL } from '../../common/SettingSearch';
import { SuggestModelCard } from './SuggestModelCard';
import { CompressModelCard } from './CompressModelCard';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor,
  cardTitleColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import {
  CONN_RESOLVE_TICK_KEY, DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY, OCR_ENABLED_KEY,
  OCR_ENGINE_BUILTIN, OCR_ENGINE_KEY, OCR_ENGINE_MODEL, OCR_ENGINE_SYSTEM, OCR_MODEL_KEY,
  OCR_PREFER_SYSTEM_KEY, OCR_PROVIDER_KEY, SUGGEST_MODEL_KEY,
  SUGGEST_PROVIDER_KEY, TITLE_MODEL_KEY, TITLE_PROVIDER_KEY,
  ModelRow, ProviderRow, queryModels, queryProviders, resolveOcrEngine
} from '../../common/store/ProviderDb';
// （★ 2026-09-23 关闭确认笔：提示词七槽的键 / 内置模板 / 必留占位符 / 面板标题 / 输入框占位
// 六件与新增的生效值现读 effectivePromptOf 一并移入 PromptSlotSpec.ets，本页零复写；
// 只保留模型侧键的导入）
import { MEMORY_MODEL_KEY, MEMORY_PROVIDER_KEY } from '../../common/MemoryGen';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROVIDER_KEY } from '../../common/MemoryOpt';
import { COMPRESS_MODEL_KEY, COMPRESS_PROVIDER_KEY } from '../../common/CompressGen';
import { TEMPLATE_CONTENT_MAX } from '../../common/store/PromptTemplateDb';
import { ModelPickerSheet } from '../chat/ModelPickerSheet';
import { confirmSheetClose, sheetPanelOptions, sheetTitleBarOptions,
  DETENTS_FULL } from '../chat/KimiSheetCommon';
import { InfoHintButton } from '../InfoHintButton';
import { PromptSlot, effectivePromptOf, resolvePromptSlot } from './PromptSlotSpec';

// 键值对展示态（resolveModelDisplay 产物——五卡共用；ArkTS 接口须挂显式类型）。
// ★ 2026-09-20 补笔：providerName 字段随首卡服务商行删除而退役（各卡显示行一律只显模型名）
interface ModelDisplayState {
  modelLabel: string;
  missing: boolean;
}

// 提示词槽规格表（PromptSlot / resolvePromptSlot）与生效值现读（effectivePromptOf）★ 2026-09-23
// 关闭确认笔起在 ./PromptSlotSpec.ets——本页只经 import 消费；新增槽的联动铁律见文件头注释
@Component
export struct FunctionalModelPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 全局默认两键镜像（@State——选择落键后同步刷新行值；'' = 未设置）
  @State private providerId: string = '';
  @State private modelId: string = '';
  // 默认模型显示名镜像（'' 且已绑定 = 行已删窗口期；@State 驱动行值重建——坑16 口径：
  // 本页为普通内容区非 @BuilderParam content，@State 直读自刷）
  @State private modelLabel: string = '';
  // ★ 2026-09-20 补笔：服务商名镜像随首卡服务商行删除而退役（决明「首卡图标与服务商都删掉」）
  // 指向行已删（服务商或模型行缺失；reloadDefault 置位——行值据此显示「未选择」，
  // 不清镜像两键：半模态打勾仍需原值）
  @State private missing: boolean = false;
  // 标题生成卡四镜像（2026-09-05 第二卡；语义同上组——两键为 AppStorage 持久键，
  // missing = 指向行已删窗口期显示「未选择」不清键，半模态打勾仍需原值）
  @State private titleProviderId: string = '';
  @State private titleModelId: string = '';
  @State private titleModelLabel: string = '';
  @State private titleMissing: boolean = false;
  // 记忆提取卡四镜像（★ 2026-09-08 先行笔第三卡；语义同标题组——记忆两键未配置 =
  // 未启用不整理〔同日决明指令取消回退标题模型〕，行值显示「未选择」灰字）
  @State private memoryProviderId: string = '';
  @State private memoryModelId: string = '';
  @State private memoryModelLabel: string = '';
  @State private memoryMissing: boolean = false;
  // 记忆优化卡四镜像（★ 2026-09-11「记忆优化模型」二期第四卡；语义同记忆组——两键未配置 =
  // 不优化，行值显示「未选择」灰字。★ 同日收尾开放「提示词」键，本组镜像仍只管模型两键，
  // 提示词走下方 promptContent 共用镜像与 resolvePromptSlot 槽规格表）
  @State private memoryOptProviderId: string = '';
  @State private memoryOptModelId: string = '';
  @State private memoryOptModelLabel: string = '';
  @State private memoryOptMissing: boolean = false;
  // 文字识别卡镜像（2026-09-15 附件 OCR 二期第五卡）：ocrEnabledState 总开关镜像
  //（Toggle 现值——键值域 'true'|'false' 字符串，镜像转布尔承载开关）；ocrEngineIndex 引擎
  // 三分段下标镜像（★ 2026-09-16 内置引擎落地新增——0 系统 / 1 内置 / 2 视觉模型，值经
  // resolveOcrEngine 解析后取下标，@Watch 落键见 onOcrEngineIndexChanged）；ocr 已选模型两键
  // 镜像（'' = 未选，引擎非视觉模型时也保留作回退目标）+ 显示名与 missing（口径同标题组；
  // ★ 2026-09-16 显示行只显模型名——服务商名镜像不设，显示行不带「服务商 · 」前缀，与同页
  // 四卡统一）
  @State private ocrEnabledState: boolean = true;
  @State @Watch('onOcrEngineIndexChanged') ocrEngineIndex: number = 0;
  @State private ocrProviderId: string = '';
  @State private ocrModelId: string = '';
  @State private ocrModelLabel: string = '';
  @State private ocrMissing: boolean = false;
  // 推荐问题卡镜像组（2026-09-19 第六卡）已随域拆分迁 SuggestModelCard.ets 自持有读取
  //（@StorageProp 自订阅，父侧零镜像零 reload）——父侧只保留 sheetKind 意图回调与
  // ModelPickerSheet 打勾源（现读 AppStorage 持久键）
  // 引擎分段选项（顺序契约：下标 0 = 系统识别 / 1 = 内置识别 / 2 = 视觉模型，勿乱调——
  // 与 engineIndexOf / engineValueOf 三处同序）。内置识别段 enabled 取真机能力探测：
  // canIUse 在应用存活期内恒定，故一次构造即可（普通成员非 @State，无需驱动重渲染）
  private ocrEngineItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '系统识别' },
    { text: '内置识别', enabled: canIUse('SystemCapability.AI.MindSporeLite') },
    { text: '视觉模型' }
  ]);
  // 提示词编辑镜像（2026-09-05 开放编辑：「提示词」键打开时 = 当前生效模板
  // resolveTitlePromptTemplate() 单源初始化；保存 = 校验含 {content} 后写 TITLE_PROMPT_KEY，
  // 恢复默认 = 清键回内置——语义与生成链同一来源；★ 2026-09-08 记忆提取卡、★ 2026-09-11
  // 记忆优化卡复用本镜像与同一半模态，按 sheetKind 走 resolvePromptSlot 分流键 / 占位符 /
  // 标题 / 保留占位符）
  @State private promptContent: string = '';
  // 半模态面板开关（坑64 姿势：声明式 bindSheet 挂页面根；ChatPage sheetKind 单面板多
  // 形态同款）：'none' 关 / 'model' 默认对话卡选择 / 'titleModel' 标题卡选择 /
  // 'prompt' 标题提示词编辑 / 'memoryModel' 记忆提取卡选择 / 'memoryPrompt' 记忆提取
  // 提示词编辑 / 'memoryOptModel' 记忆优化卡选择 / 'memoryOptPrompt' 记忆优化提示词编辑 /
  // 'memoryImportPrompt' 记忆导入提示词编辑（★ 2026-09-22 第六槽——「记忆提取」卡第三键）/
  // 'ocrModel' 文字识别卡已选模型选择（2026-09-16 开关化后走共用 ModelPickerSheet）/
  // 'ocrPrompt' 文字识别卡提示词编辑（★ 2026-09-17 识别提示词开放自定义）/
  // 'suggestModel' 推荐问题卡模型选择 / 'suggestPrompt' 推荐问题提示词编辑 /
  // 'compressModel' 上下文压缩卡模型选择 / 'compressPrompt' 上下文压缩提示词编辑
  //（★ 2026-09-23 上下文压缩笔第七卡 + 第七槽）
  @State private sheetKind: string = 'none';
  // 提示词面板滚动器（标题栏渐变模糊联动）
  private promptScroller: Scroller = new Scroller();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感回退双态 + 分项档位（fallbackButton* 四件套参数——DataSyncPage 先例；
  // 订阅式声明坑16 正解，外观页开关切换即刷）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    this.reloadDefault();
    this.reloadTitleModel();
    this.reloadMemoryModel();
    this.reloadMemoryOptModel();
    this.reloadOcrEngine();
  }

  // 默认模型已设置判定（行值与半模态打勾共用；行已删窗口期的「未选择」由 missing 承担
  //——default 两键是 AppStorage 持久键无级联清理，bound() 判不出指向行已删，不能像
  // ModelSettingsPage 靠级联清列归零）
  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  // 标题模型已设置判定（口径同 bound()）
  private titleBound(): boolean {
    return this.titleProviderId !== '' && this.titleModelId !== '';
  }

  // 记忆提取模型已设置判定（口径同 bound()——记忆两键齐才算配置，缺一即未启用不整理）
  private memoryBound(): boolean {
    return this.memoryProviderId !== '' && this.memoryModelId !== '';
  }

  // 记忆优化模型已设置判定（口径同 bound()——两键齐才算配置，缺一即未启用不优化）
  private memoryOptBound(): boolean {
    return this.memoryOptProviderId !== '' && this.memoryOptModelId !== '';
  }

  // OCR 已选模型判定（两键齐 = 已选模型——**是否生效看系统识别开关**；任一空 = 未选，
  // 引擎读侧恒回落系统、卡内开关随之禁用）
  private ocrModelBound(): boolean {
    return this.ocrProviderId !== '' && this.ocrModelId !== '';
  }

  // 记忆优化卡显示行文本（口径同记忆卡：未配 / 指向行已删 = 「未选择」灰字）
  private memoryOptDisplayText(): string {
    return this.memoryOptBound() && !this.memoryOptMissing ?
      (this.memoryOptModelLabel !== '' ? this.memoryOptModelLabel : this.memoryOptModelId) :
      '未选择';
  }

  // 记忆优化卡显示行是否灰字（非「已配置且指向行在场」即灰——显示行配色判据）
  private memoryOptDisplayMuted(): boolean {
    return !(this.memoryOptBound() && !this.memoryOptMissing);
  }

  // 记忆卡显示行文本（记忆已配且指向行在场 = 模型名；未配 / 指向行已删 = 「未选择」——
  // ★ 决明指令取消回退后与标题卡同构，无「使用标题生成模型」灰字态）
  private memoryDisplayText(): string {
    return this.memoryBound() && !this.memoryMissing ?
      (this.memoryModelLabel !== '' ? this.memoryModelLabel : this.memoryModelId) : '未选择';
  }

  // 记忆卡显示行是否灰字（非「正在使用记忆模型」态即灰——显示行配色判据）
  private memoryDisplayMuted(): boolean {
    return !(this.memoryBound() && !this.memoryMissing);
  }

  // 键值对 → 展示态解析（reloadDefault / reloadTitleModel 共用——两卡同构逻辑提取，
  // P2-4）：服务商/模型行缺失 = missing（读侧窗口期兜底不写键）；查询失败 = label 兜底
  // modelId 静默降级（键值仍在，不阻断页面）
  private async resolveModelDisplay(providerId: string,
    modelId: string): Promise<ModelDisplayState> {
    const state: ModelDisplayState = { modelLabel: '', missing: false };
    const providers: ProviderRow[] = await queryProviders();
    const provider: ProviderRow | undefined =
      providers.find((row: ProviderRow): boolean => row.id === providerId);
    if (provider === undefined) {
      state.missing = true;
      return state;
    }
    // 服务商行在场即够（存在性判据）——名字不再上屏，故不取用 provider.name（2026-09-20 补笔）
    const models: ModelRow[] = await queryModels(provider.id, 'chat');
    const model: ModelRow | undefined =
      models.find((row: ModelRow): boolean => row.modelId === modelId);
    if (model !== undefined) {
      state.modelLabel = model.name !== '' ? model.name : model.modelId;
    } else {
      state.missing = true;
    }
    return state;
  }

  // 重读全局默认两键 + 解析显示名（aboutToAppear / 选择落键后两时点；指向行已删 =
  // missing 置位显示「未选择」——读侧窗口期兜底不写键，镜像两键保持原值供半模态打勾）
  private async reloadDefault(): Promise<void> {
    this.providerId = AppStorage.get<string>(DEFAULT_PROVIDER_KEY) ?? '';
    this.modelId = AppStorage.get<string>(DEFAULT_MODEL_KEY) ?? '';
    this.modelLabel = '';
    this.missing = false;
    if (!this.bound()) {
      return;
    }
    try {
      const state: ModelDisplayState = await this.resolveModelDisplay(this.providerId, this.modelId);
      this.modelLabel = state.modelLabel;
      this.missing = state.missing;
    } catch (e) {
      // 展示增强查询失败静默兜底（键值仍在，行值回退显示 modelId——不阻断页面）
      this.modelLabel = this.modelId;
    }
  }

  // 重读标题模型两键 + 解析显示名（口径同 reloadDefault；不写 CONN_RESOLVE_TICK——
  // 标题模型不进会话连接解析链）
  private async reloadTitleModel(): Promise<void> {
    this.titleProviderId = AppStorage.get<string>(TITLE_PROVIDER_KEY) ?? '';
    this.titleModelId = AppStorage.get<string>(TITLE_MODEL_KEY) ?? '';
    this.titleModelLabel = '';
    this.titleMissing = false;
    if (!this.titleBound()) {
      return;
    }
    try {
      const state: ModelDisplayState =
        await this.resolveModelDisplay(this.titleProviderId, this.titleModelId);
      this.titleModelLabel = state.modelLabel;
      this.titleMissing = state.missing;
    } catch (e) {
      this.titleModelLabel = this.titleModelId;
    }
  }

  // 重读记忆提取模型两键 + 解析显示名（口径同 reloadTitleModel；未配置不清空——行值由
  // memoryDisplayText 恒「未选择」灰字文案）
  private async reloadMemoryModel(): Promise<void> {
    this.memoryProviderId = AppStorage.get<string>(MEMORY_PROVIDER_KEY) ?? '';
    this.memoryModelId = AppStorage.get<string>(MEMORY_MODEL_KEY) ?? '';
    this.memoryModelLabel = '';
    this.memoryMissing = false;
    if (!this.memoryBound()) {
      return;
    }
    try {
      const state: ModelDisplayState =
        await this.resolveModelDisplay(this.memoryProviderId, this.memoryModelId);
      this.memoryModelLabel = state.modelLabel;
      this.memoryMissing = state.missing;
    } catch (e) {
      this.memoryModelLabel = this.memoryModelId;
    }
  }

  // 重读记忆优化模型两键 + 解析显示名（口径同 reloadMemoryModel；未配置不清空——行值由
  // memoryOptDisplayText 恒「未选择」灰字文案）
  private async reloadMemoryOptModel(): Promise<void> {
    this.memoryOptProviderId = AppStorage.get<string>(MEMORY_OPT_PROVIDER_KEY) ?? '';
    this.memoryOptModelId = AppStorage.get<string>(MEMORY_OPT_MODEL_KEY) ?? '';
    this.memoryOptModelLabel = '';
    this.memoryOptMissing = false;
    if (!this.memoryOptBound()) {
      return;
    }
    try {
      const state: ModelDisplayState =
        await this.resolveModelDisplay(this.memoryOptProviderId, this.memoryOptModelId);
      this.memoryOptModelLabel = state.modelLabel;
      this.memoryOptMissing = state.missing;
    } catch (e) {
      this.memoryOptModelLabel = this.memoryOptModelId;
    }
  }

  // 重读 OCR 总开关 + 引擎三态 + 已选模型两键 + 解析显示名（口径同 reloadTitleModel；
  // 总开关缺省/未写 = 开，与 OcrEngine.ocrEnabled 同兜底语义；引擎键缺省/未写/脏写按旧口径
  // 推导，与 OcrEngine.preferredEngine 同源——共用 ProviderDb.resolveOcrEngine，禁各写三目链）
  private async reloadOcrEngine(): Promise<void> {
    this.ocrEnabledState = (AppStorage.get<string>(OCR_ENABLED_KEY) ?? 'true') !== 'false';
    this.ocrProviderId = AppStorage.get<string>(OCR_PROVIDER_KEY) ?? '';
    this.ocrModelId = AppStorage.get<string>(OCR_MODEL_KEY) ?? '';
    this.ocrEngineIndex = this.engineIndexOf(resolveOcrEngine(
      AppStorage.get<string>(OCR_ENGINE_KEY) ?? '',
      AppStorage.get<string>(OCR_PREFER_SYSTEM_KEY) ?? '', this.ocrProviderId, this.ocrModelId));
    this.ocrModelLabel = '';
    this.ocrMissing = false;
    if (!this.ocrModelBound()) {
      return;
    }
    try {
      const state: ModelDisplayState =
        await this.resolveModelDisplay(this.ocrProviderId, this.ocrModelId);
      this.ocrModelLabel = state.modelLabel;
      this.ocrMissing = state.missing;
    } catch (e) {
      this.ocrModelLabel = this.ocrModelId;
    }
  }

  // 引擎值 ↔ 分段下标（顺序契约三处同序：ocrEngineItems / engineIndexOf / engineValueOf）
  private engineIndexOf(value: string): number {
    if (value === OCR_ENGINE_BUILTIN) {
      return 1;
    }
    if (value === OCR_ENGINE_MODEL) {
      return 2;
    }
    return 0;
  }

  private engineValueOf(index: number): string {
    if (index === 1) {
      return OCR_ENGINE_BUILTIN;
    }
    if (index === 2) {
      return OCR_ENGINE_MODEL;
    }
    return OCR_ENGINE_SYSTEM;
  }

  // 段选落键（§3.5）：系统/内置 = 即选即生效（写 OCR_ENGINE_KEY）；视觉模型未配置 = 弹既有
  // ModelPickerSheet 半模态并把**段位程序化回退到当前生效引擎**（分段件 selectedIndex 受控
  // 可回写——与 Toggle「被拒不回弹」不同，无坑）；已配置 = 直接切到它。
  // 落键判据 = 「目标值 ≠ 当前解析值」才写：页内 reload 的回显赋值（含未写状态下的等价回显）
  // 因此不会落键——保「未写 = 按旧口径推导」语义不被「打开设置页」这个动作改写；用户点选
  // 到别的引擎时两者必不相等，正常落键
  private onOcrEngineIndexChanged(): void {
    const resolved: string = resolveOcrEngine(
      AppStorage.get<string>(OCR_ENGINE_KEY) ?? '',
      AppStorage.get<string>(OCR_PREFER_SYSTEM_KEY) ?? '',
      AppStorage.get<string>(OCR_PROVIDER_KEY) ?? '',
      AppStorage.get<string>(OCR_MODEL_KEY) ?? '');
    if (this.ocrEngineIndex === 2 && !this.ocrModelBound()) {
      this.ocrEngineIndex = this.engineIndexOf(resolved);
      this.sheetKind = 'ocrModel';
      return;
    }
    const value: string = this.engineValueOf(this.ocrEngineIndex);
    if (value !== resolved) {
      AppStorage.setOrCreate<string>(OCR_ENGINE_KEY, value);
    }
  }

  // 文字识别卡副标题文本（★ 2026-09-20 起恒显——原为视觉模型段专属显示行）：已选模型名 /
  // 未选择。★ 只显模型名，不带服务商前缀，与同页四卡统一；引擎为系统/内置时本行同样在位
  //（分段胶囊表达生效引擎，本行表达「已选模型」——二者分工，系统识别失败回退正走此模型）
  private ocrEngineDisplayText(): string {
    if (!this.ocrModelBound() || this.ocrMissing) {
      return '未选择';
    }
    return this.ocrModelLabel !== '' ? this.ocrModelLabel : this.ocrModelId;
  }

  // 文字识别卡副标题是否灰字（未启用 / 未选定模型即灰——★ 2026-09-20 上移为副标题后判据
  // 原样保留：本卡有总开关，关掉后整卡不生效，副标题随灰是有效信号）
  private ocrEngineDisplayMuted(): boolean {
    if (!this.ocrEnabledState) {
      return true;
    }
    return !this.ocrModelBound() || this.ocrMissing;
  }

  // 分段副行说明（三态各一句；文案规约：无冒号分号括号连环。内置识别如实写「图片不出设备」
  // ——官方无「纯端侧」字样，勿用更绝对话术；不写「手写」、不承诺准确率）
  private ocrEngineDescText(): string {
    if (!this.ocrEnabledState) {
      return '关闭后图片与扫描件不做识别，附件按原样发送';
    }
    if (this.ocrEngineIndex === 1) {
      return '离线识别，图片不出设备，支持中英日与常用拉丁语系语言，无需配置';
    }
    if (this.ocrEngineIndex === 2) {
      return this.ocrModelBound() && !this.ocrMissing
        ? '图片会发送给你配置的服务商，识别消耗计入用量统计'
        : '点上方「视觉模型」选择要使用的模型';
    }
    return '使用系统自带识别，无需配置。系统识别失败时会改用已选模型';
  }

  // 选择落键（半模态 onPick，sheetKind 分流）：默认模型 → default 两键写入 + 解析变化
  // 广播；标题模型 → title 两键写入（不广播连接解析——不进发送链）；记忆提取模型 →
  // memory 两键写入（同不进发送链）；写键同步无失败路径
  private onPickModel(providerId: string, modelId: string): void {
    if (this.sheetKind === 'titleModel') {
      AppStorage.setOrCreate<string>(TITLE_PROVIDER_KEY, providerId);
      AppStorage.setOrCreate<string>(TITLE_MODEL_KEY, modelId);
      this.reloadTitleModel();
      this.sheetKind = 'none';
      return;
    }
    if (this.sheetKind === 'memoryModel') {
      AppStorage.setOrCreate<string>(MEMORY_PROVIDER_KEY, providerId);
      AppStorage.setOrCreate<string>(MEMORY_MODEL_KEY, modelId);
      this.reloadMemoryModel();
      this.sheetKind = 'none';
      return;
    }
    if (this.sheetKind === 'memoryOptModel') {
      AppStorage.setOrCreate<string>(MEMORY_OPT_PROVIDER_KEY, providerId);
      AppStorage.setOrCreate<string>(MEMORY_OPT_MODEL_KEY, modelId);
      this.reloadMemoryOptModel();
      this.sheetKind = 'none';
      return;
    }
    if (this.sheetKind === 'ocrModel') {
      // 文字识别卡：写已选模型两键 + 引擎翻到视觉模型（★ 选模型 = 用它——否则「选了却没生效」
      // 只能靠用户再切段位，观感 = 选了个寂寞）。★ 2026-09-16 内置引擎落地后：写引擎三态键
      // 'model'（旧偏好键自此只读，不再写——那是个退役键，写了会与引擎键形成双真源）
      AppStorage.setOrCreate<string>(OCR_PROVIDER_KEY, providerId);
      AppStorage.setOrCreate<string>(OCR_MODEL_KEY, modelId);
      AppStorage.setOrCreate<string>(OCR_ENGINE_KEY, OCR_ENGINE_MODEL);
      this.reloadOcrEngine();
      this.sheetKind = 'none';
      return;
    }
    if (this.sheetKind === 'suggestModel') {
      // 推荐问题卡：写 suggest 两键（同不进发送链不广播——单级验证在 SuggestGen 守卫序；
      // 卡面由 SuggestModelCard @StorageProp 自订阅刷新，父侧零 reload）
      AppStorage.setOrCreate<string>(SUGGEST_PROVIDER_KEY, providerId);
      AppStorage.setOrCreate<string>(SUGGEST_MODEL_KEY, modelId);
      this.sheetKind = 'none';
      return;
    }
    if (this.sheetKind === 'compressModel') {
      // 上下文压缩卡（2026-09-23）：写 compress 两键（同不进发送链不广播——生成链现读两键，
      // 未配置回退当前会话模型；卡面由 CompressModelCard @StorageProp 自订阅刷新，父侧零 reload）
      AppStorage.setOrCreate<string>(COMPRESS_PROVIDER_KEY, providerId);
      AppStorage.setOrCreate<string>(COMPRESS_MODEL_KEY, modelId);
      this.sheetKind = 'none';
      return;
    }
    AppStorage.setOrCreate<string>(DEFAULT_PROVIDER_KEY, providerId);
    AppStorage.setOrCreate<string>(DEFAULT_MODEL_KEY, modelId);
    // 广播解析输入变化（方案 a：改全局默认后已开着的会话页 @Watch 重解析——否则切回
    // 直接发送仍走旧 conn 缓存，自检轮 P2 缺口）
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
    this.providerId = providerId;
    this.modelId = modelId;
    this.reloadDefault();
    this.sheetKind = 'none';
  }

  // 半模态打勾源（按 sheetKind 取对应卡镜像；'model' = 默认对话两键——五卡共用同面板；
  // ocrModel = 文字识别卡已选模型两键——偏好为系统时也传，打勾反映「已选」而非「生效中」，
  // 与卡内显示行（生效引擎）分工）
  private pickerProviderId(): string {
    if (this.sheetKind === 'titleModel') {
      return this.titleProviderId;
    }
    if (this.sheetKind === 'memoryModel') {
      return this.memoryProviderId;
    }
    if (this.sheetKind === 'memoryOptModel') {
      return this.memoryOptProviderId;
    }
    if (this.sheetKind === 'ocrModel') {
      return this.ocrProviderId;
    }
    if (this.sheetKind === 'suggestModel') {
      // 打勾源现读持久键（镜像组已随域拆分迁子件，无需父侧副本）
      return AppStorage.get<string>(SUGGEST_PROVIDER_KEY) ?? '';
    }
    if (this.sheetKind === 'compressModel') {
      // 打勾源现读持久键（同上——卡面子件自持，父侧零副本）
      return AppStorage.get<string>(COMPRESS_PROVIDER_KEY) ?? '';
    }
    return this.providerId;
  }

  private pickerModelId(): string {
    if (this.sheetKind === 'titleModel') {
      return this.titleModelId;
    }
    if (this.sheetKind === 'memoryModel') {
      return this.memoryModelId;
    }
    if (this.sheetKind === 'memoryOptModel') {
      return this.memoryOptModelId;
    }
    if (this.sheetKind === 'ocrModel') {
      return this.ocrModelId;
    }
    if (this.sheetKind === 'suggestModel') {
      return AppStorage.get<string>(SUGGEST_MODEL_KEY) ?? '';
    }
    if (this.sheetKind === 'compressModel') {
      return AppStorage.get<string>(COMPRESS_MODEL_KEY) ?? '';
    }
    return this.modelId;
  }

  // 保存提示词（四槽同形：校验必保留占位符——缺 = 模板里没有可插内容的位置，生成或整理
  // 失效；写各自定制键全量文本，各链现读，保存即生效；toast 后收面板——保存 = 显式动作，
  // 关闭不保存为面板默认行为。记忆提取槽不校验 {maxItems}——缺失 = 用户显式去掉条数约束，
  // 解析侧上限仍兜底。★ 识别槽无占位符不校验占位符，但空串拦下——写 '' 会静默变回内置，
  // 观感 = 保存了空提示词却仍按内置跑；回内置的正当动作是「恢复默认」）
  private savePrompt(): void {
    const slot: PromptSlot = resolvePromptSlot(this.sheetKind);
    const content: string = this.promptContent.trim();
    if (slot.required !== '' && !content.includes(slot.required)) {
      this.getUIContext().getPromptAction().showToast({ message: slot.missingTip });
      return;
    }
    if (content === '') {
      this.getUIContext().getPromptAction().showToast({ message: '提示词不能为空。可点恢复默认回到内置' });
      return;
    }
    AppStorage.setOrCreate<string>(slot.key, content);
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    this.sheetKind = 'none';
  }

  // 恢复内置默认（清定制键回 ''——清删式回退，内置模板后续升级自动跟随；编辑框回显内置；
  // 各槽按 sheetKind 分流目标键与内置模板）
  private restorePrompt(): void {
    const slot: PromptSlot = resolvePromptSlot(this.sheetKind);
    AppStorage.setOrCreate<string>(slot.key, '');
    this.promptContent = slot.builtin;
    this.getUIContext().getPromptAction().showToast({ message: '已恢复为内置默认' });
  }

  // 提示词编辑入口（★ 2026-09-23 关闭确认笔：七槽单源——原七处点击回调各写「播种 + 置槽」
  // 两行，现统一到此；播种值 = 该槽生效模板现读〔effectivePromptOf〕，漏播种会以空框编辑、
  // 保存即覆盖用户定制）
  private openPromptSlot(kind: string): void {
    this.promptContent = effectivePromptOf(kind);
    this.sheetKind = kind;
  }

  // 关闭请求（★ 2026-09-23 关闭确认笔——两路单源：标题栏关闭键与手势/系统返回都调本方法）。
  // 脏态 = 现读生效值比对（不用打开时快照——「恢复默认」会即时清定制键并回显内置，快照比对
  // 会把它误报成有改动）；未编辑直接关，编辑过先问一句，未通过 / 弹窗异常一律不置 none =
  // 面板保持打开。★ 程序化关闭（保存键 savePrompt）不经本方法——保存 = 显式动作，落库后无
  // 损失可谈（判断口诀：用户主动离开 → 确认；流程自己收尾 → 直接关）
  private requestClosePrompt(): void {
    if (this.promptContent.trim() === effectivePromptOf(this.sheetKind)) {
      this.sheetKind = 'none';
      return;
    }
    confirmSheetClose(this.getUIContext(), {
      title: '放弃这次修改？',
      message: '放弃后不会保存，提示词保持原样',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃'
    }).then((approved: boolean): void => {
      if (approved) {
        this.sheetKind = 'none';
      }
    });
  }

  // 默认对话卡（★ 2026-09-20 两笔收敛后与同页五卡同构）：顶部行 = 「默认对话」标题 + 右上角
  // ⓘ 信息气泡（说明文字收入气泡——InfoHintButton 服务商配置页先例）；副标题行 = 当前选择
  // （模型名 15fp，未设置/行已删 = 「未选择」灰字——与同页五卡同槽同字号同判据）；通宽
  // 「选择模型」主按钮（官方默认胶囊形，形态对齐 DataSyncPage「导出备份到本机」键）——唯一
  // 交互点 = 按钮（ⓘ 点击弹气泡）。
  // ★ 卡内间距随本轮并入 Column space 14 统一律（原为两处 margin 12——同页五卡皆 14）
  // ★ 补笔（决明「首卡图标与服务商都删掉」）：2026-09-05「复刻参考图首卡」的图标圆底与服务商
  // 名整行删——信息面收成「标题 → 当前选择 → 操作键」三行，与标题生成/记忆两卡同序
  @Builder
  DefaultModelCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text(SETTING_TITLE_DEFAULT_MODEL)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '会话页未选择模型且所属助手未绑定模型时，发送自动使用此默认模型'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（★ 2026-09-20 上移为副标题：原在图标行内、服务商名下方）
      Text(this.bound() && !this.missing
        ? (this.modelLabel !== '' ? this.modelLabel : this.modelId) : '未选择')
        .fontSize(15)
        .fontColor(this.bound() && !this.missing ? cardTitleColor() : cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // ★ 2026-09-20 补笔（决明「首卡图标与服务商都删掉」）：原「服务商标识行」（图标圆底 44vp +
      // 服务商名 13fp）整行删除——首卡自此与同页五卡同构（标题行 → 副标题 → 操作键），
      // 圆底图标、服务商名镜像与 badgeBg 导入三件随行退役
      Button('选择模型')
        .width('100%')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.sheetKind = 'model';
        })
    }
    .alignItems(HorizontalAlign.Start)
  }

  // 标题生成卡（2026-09-05 任务 3 第二卡，样式照 ModelSettingsPage 卡片：上部显示行
  // + 说明小字 + 下部双键行——★ 2026-09-05 决明拍板「说明小字与按钮上下调换」后定型为
  // 布局次序规范，见 AGENTS.md「功能设置卡布局次序」；★ 2026-09-06 说明小字收入右上角
  // ⓘ 气泡与默认对话卡同构——显示行下移独立行）：标题两键 = AI 会话标题生成的
  // 显式开关（★ 决明拍板：未配置 = 功能未启用静默不生成——文案不得暗示会话模型兜底）；
  // 「提示词」开编辑半模态（内容框预填生效模板，恢复默认/保存双键）
  @Builder
  TitleModelCard() {
    Column({ space: 14 }) {
      // 顶部行：标题 + 右上角 ⓘ 信息气泡（说明文字收入气泡——文案规约：无冒号分号括号
      // 连环；点明未选择 = 不生成的显式开关语义）
      Row({ space: 8 }) {
        Text(SETTING_TITLE_TITLE_MODEL)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '选择模型后自动为新会话生成标题。未选择时不生成'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（未选/指向行已删 = 「未选择」灰字——ModelDisplayRow 同款）
      Text(this.titleBound() && !this.titleMissing
        ? (this.titleModelLabel !== '' ? this.titleModelLabel : this.titleModelId) : '未选择')
        .fontSize(15)
        .fontColor(this.titleBound() && !this.titleMissing ? cardTitleColor() : cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 下部：左「选择模型」右「提示词」双键（同宽各半行，fallbackButton* 四件套双态；
      // ★ 2026-09-11 决明「三张卡的选择模型键都改成蓝底」——选模型 = 本卡主操作，primary=true
      // 官方强调蓝 + 恒白字，与首卡「选择模型」同形制；「提示词」仍为次钮）
      Row({ space: 10 }) {
        Button('选择模型')
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.sheetKind = 'titleModel';
          })
        Button('提示词')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.openPromptSlot('prompt');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 记忆提取卡（★ 2026-09-08 先行笔第三卡，形制照标题生成卡）：记忆整理用哪个模型的
  // 独立配置——未选择时不整理（同日决明指令取消回退标题模型，与标题生成同口径）；
  // 「提示词」开编辑半模态（内容框预填生效模板，恢复默认/保存双键）
  @Builder
  MemoryModelCard() {
    Column({ space: 14 }) {
      // 顶部行：标题 + 右上角 ⓘ 信息气泡（文案规约：无冒号分号括号连环；点明未选不整理
      // 的显式开关语义）
      Row({ space: 8 }) {
        Text(SETTING_TITLE_MEMORY_MODEL)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '选择模型后退出会话自动整理使用该模型。未选择时不整理'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（未配 = 「未选择」灰字——见 memoryDisplayText）
      Text(this.memoryDisplayText())
        .fontSize(15)
        .fontColor(this.memoryDisplayMuted() ? cardDescColor() : cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 下部三键（★ 2026-09-22 记忆导入笔加第三键「导入提示词」，布局随之由单行改两行）：
      // **为什么不分三键一行**——本卡卡宽 = CARD_PANEL_WIDTH（100% − 32vp）、卡内 padding
      // 16vp×2，三键一行时每键分得 (卡内宽 − 2×10vp) ÷ 3 ≈ 92vp（360vp 屏），而官方胶囊键
      // 左右内边距各 16vp、默认字号 16fp：「导入提示词」五字需约 112vp（「选择模型」四字也
      // 已贴线 96vp）——硬塞必截字。故改两行：
      // · 上行「选择模型」通宽主键（fallbackButton* 第四参 primary=true 官方强调蓝 + 恒白字）
      //   ——与首卡「默认对话」的通宽主键同形，主操作独占一行；
      // · 下行「提示词 | 导入提示词」双次钮各半行（primary=false，各 ≈150vp 余量充足）。
      // ★ 新键必须叫「导入提示词」而非「提示词」：61 组「提示词」键落点序列钉按
      //   `Button('提示词')` 精确匹配收四枚，复用同字面量会被当成第五枚而使序列错位告警；
      //   本键的槽落点 'memoryImportPrompt' 由 58 组第六槽钉守（见该组）。
      Row({ space: 10 }) {
        Button('选择模型')
          .width('100%')
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.sheetKind = 'memoryModel';
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Row({ space: 10 }) {
        Button('提示词')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.openPromptSlot('memoryPrompt');
          })
        Button('导入提示词')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.openPromptSlot('memoryImportPrompt');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 记忆优化卡（★ 2026-09-11「记忆优化模型」二期第四卡，形制照记忆提取卡）：对库内已有记忆
  // 做去重与改写的模型——未选择时不优化（与提取/标题同口径，不回退提取模型）；
  // ★ 2026-09-11 二期收尾（决明「完全对齐标题生成与记忆提取的提示词展示与编辑功能」）：
  // 「提示词」键开放，形制与同页两卡逐处同构（次钮 + 编辑半模态预填生效模板 + 恢复默认/保存
  // 双键；保留占位符 = {memories} 而非 {content}——优化链插的是条目清单不是对话原文，由
  // resolvePromptSlot 按槽取）
  @Builder
  MemoryOptModelCard() {
    Column({ space: 14 }) {
      // 顶部行：标题 + 右上角 ⓘ 信息气泡（文案规约：无冒号分号括号连环；点明未选不优化的
      // 显式开关语义，并说明它改的是已有记忆而非新增）
      Row({ space: 8 }) {
        Text(SETTING_TITLE_MEMORY_OPT_MODEL)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '选择模型后可在记忆页对已有的记忆做去重与改写。未选择时不能优化'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（未配 = 「未选择」灰字——见 memoryOptDisplayText）
      Text(this.memoryOptDisplayText())
        .fontSize(15)
        .fontColor(this.memoryOptDisplayMuted() ? cardDescColor() : cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 下部：左「选择模型」右「提示词」双键（同宽各半行——与同页两卡同左缘同宽；★ 2026-09-11
      // 同前两卡：选择模型 = 主操作键蓝底，「提示词」次钮）
      Row({ space: 10 }) {
        Button('选择模型')
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.sheetKind = 'memoryOptModel';
          })
        Button('提示词')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.openPromptSlot('memoryOptPrompt');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 文字识别卡（2026-09-15 附件 OCR 二期第五卡，形制照标题生成卡 + 两开关行；★ 2026-09-16
  // 系统识别开关化后重做；★ 2026-09-20 模型行上移为副标题）：顶部行 = 标题 + ⓘ；副标题行 =
  // 已选模型（15fp，未选/行已删 = 「未选择」灰字——★ 只显模型名不带服务商前缀，与同页四卡
  // 统一；卡内开关关掉时随灰——本行沿用原显示行判据）→ 总开关（默认开）→ 引擎三分段胶囊
  // （系统/内置/视觉）→ 分段副行说明 → 视觉模型段双键（「选择模型」主键 + 「提示词」次钮）→
  // 共用 ModelPickerSheet（sheetKind='ocrModel'，见 SheetHost）。
  // ★ 副标题常显（引擎三段皆在）——原「模型行 + 双键」成对只在视觉段渲染，本笔按「模型名
  // 归副标题槽」拆开：副标题恒在，双键仍只属视觉模型段（选择动作只在用模型的段里有意义；
  // 已配置后换模型走本键，见文件头「与方案字面的一处偏差」注）
  // ⓘ 说明含出网事实（拍板 #6：用已选模型时图片会发给该服务商）
  @Builder
  OcrModelCard() {
    Column({ space: 14 }) {
      // 顶部行：标题 + 右上角 ⓘ 信息气泡（文案规约：无冒号分号括号连环）
      Row({ space: 8 }) {
        Text(SETTING_TITLE_OCR)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '开启后，图片与扫描件会在发送前识别成文字，供不支持视觉的模型阅读。识别结果只随本次请求发出。用系统识别或内置识别时图片不给服务商，用视觉模型时图片会发送给你配置的服务商'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（★ 2026-09-20 上移为副标题——原在视觉模型段与双键成对；恒显，
      // 引擎三段切换不再引起本行出现/消失）
      Text(this.ocrEngineDisplayText())
        .fontSize(15)
        .fontColor(this.ocrEngineDisplayMuted() ? cardDescColor() : cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 总开关行（规范-列表卡片与组卡 §4.1 口径：Toggle 可点自切换 = 唯一控制面，行本身
      // 不可点不设按压反馈；@State 镜像随 onChange 即时回显）
      Row() {
        Text('启用文字识别')
          .fontSize(15)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.ocrEnabledState })
          .onChange((isOn: boolean) => {
            this.ocrEnabledState = isOn;
            AppStorage.setOrCreate<string>(OCR_ENABLED_KEY, isOn ? 'true' : 'false');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 引擎三分段胶囊（★ 2026-09-16 内置引擎落地，方案 §3.5 拍板③：原「系统识别开关 +
      // 选择模型键」两件退役，引擎选中面收成卡内分段）。共用件 SegmentBar 零参数覆盖
      //（全项目唯一分段封装，几何/材质/配色单一来源——改前先读其头注释与
      // docs/规范-行内按钮与光感.md 分段胶囊节）；外层包 CARD 内通宽 + SEGMENT_BAR_HEIGHT
      //（官方组件宽度 = 父容器宽，高度定值防吸顶留白计算扰动——同 MemoryPage 读取方式段先例）
      Column() {
        SegmentBar({
          items: this.ocrEngineItems,
          selectedIndex: $ocrEngineIndex
        })
      }
      .width('100%')
      .height(SEGMENT_BAR_HEIGHT)
      // 副行说明（三态各一句 + 未启用态；13fp 说明小字，同页统一）
      Text(this.ocrEngineDescText())
        .fontSize(13)
        .fontColor(cardDescColor())
      // 视觉模型段专属块（系统/内置段不出现）：双键（左「选择模型」主操作键 + 右「提示词」
      // 次钮——★ 2026-09-17 决明指令「像其他功能模型一样提供两个按键」，形制与同页三卡逐处
      // 同构）。★ 2026-09-20 显示行已上移为副标题，本块只留动作键。
      // ★ 见文件头「与方案字面的一处偏差」注：段选只在未配置时开面板，已配置后换模型需要
      // 本键——验收操作单 ⑤ 的「把视觉模型指向一个故意填错 Key 的已配模型」正走这里
      if (this.ocrEngineIndex === 2) {
        // 双键行（同宽各半行——与同页三卡同左缘同宽；选择模型 = 主操作键蓝底恒白字，
        // 提示词 = 次钮；「提示词」开编辑半模态：内容框预填生效模板 resolveOcrPromptTemplate，
        // 恢复默认/保存双键，无占位符校验——见 resolvePromptSlot 与 savePrompt 注释）
        Row({ space: 10 }) {
          Button('选择模型')
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.sheetKind = 'ocrModel';
            })
          Button('提示词')
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.openPromptSlot('ocrPrompt');
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 默认对话卡（大卡复刻参考图首卡；卡宽 CARD_PANEL_WIDTH 项目基准）──
        Column() {
          this.DefaultModelCard()
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
        // ── 标题生成卡（2026-09-05 第二卡，样式照 ModelSettingsPage）──
        Column() {
          this.TitleModelCard()
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
        // ── 记忆提取卡（★ 2026-09-08 先行笔第三卡，形制同标题生成卡）──
        Column() {
          this.MemoryModelCard()
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
        // ── 记忆优化卡（★ 2026-09-11 二期第四卡，形制同记忆提取卡；同日收尾补「提示词」键）──
        Column() {
          this.MemoryOptModelCard()
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
        // ── 文字识别卡（2026-09-15 附件 OCR 二期第五卡；★ 2026-09-16 系统识别开关化重做）──
        Column() {
          this.OcrModelCard()
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
        // ── 推荐问题卡（2026-09-19 第六卡；域拆分独立成件 SuggestModelCard.ets 自持有
        //    读取，父侧只给半模态打开意图回调）──
        Column() {
          SuggestModelCard({
            onOpenModelSheet: (): void => {
              this.sheetKind = 'suggestModel';
            },
            onOpenPromptSheet: (): void => {
              this.openPromptSlot('suggestPrompt');
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
        // ── 上下文压缩卡（2026-09-23 第七卡；域拆分独立成件 CompressModelCard.ets 自持有
        //    读取，父侧只给半模态打开意图回调——SuggestModelCard 同款范式）──
        Column() {
          CompressModelCard({
            onOpenModelSheet: (): void => {
              this.sheetKind = 'compressModel';
            },
            onOpenPromptSheet: (): void => {
              this.openPromptSlot('compressPrompt');
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
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

  // 提示词编辑面板七态判定（SheetHost 分支条件 + 档位分发共用——两处同源防漂移；
  // ★ 2026-09-17 识别槽加入；★ 2026-09-19 推荐问题槽加入；★ 2026-09-22 记忆导入槽加入；
  // ★ 2026-09-23 上下文压缩槽加入）
  private isPromptSheet(): boolean {
    return this.sheetKind === 'prompt' || this.sheetKind === 'memoryPrompt' ||
      this.sheetKind === 'memoryOptPrompt' || this.sheetKind === 'memoryImportPrompt' ||
      this.sheetKind === 'ocrPrompt' || this.sheetKind === 'suggestPrompt' ||
      this.sheetKind === 'compressPrompt';
  }

  // 半模态面板（sheetKind 单面板多形态——ChatPage 同款分支链）：模型选择（默认/标题/
  // 记忆提取/记忆优化/文字识别五键打勾源按 sheetKind 取，选中经 onPickModel 分流落键；
  // ★ 2026-09-16 开关化后文字识别同走此支——非模型项「系统识别」已上提到卡内开关，
  // 共用件接口零改动，规范样式（搜索/收藏/当前选择卡）齐活）/ 提示词编辑半模态
  //（标题生成 / 记忆提取 / 记忆优化三槽共用同一形态，面板标题、输入框占位、保留占位符、
  // 保存目标键按 sheetKind 走 resolvePromptSlot 分流：TextArea 内容框预填生效模板 + 输入框下
  // 恢复默认/保存 双键——SystemPromptPage 编辑形态同构；HdsNavigation MODAL 壳 +
  // sheetTitleBarOptions 同源——规范-半模态，勿自绘标题）
  @Builder
  SheetHost() {
    if (this.isPromptSheet()) {
      HdsNavigation() {
        Scroll(this.promptScroller) {
          Column({ space: 12 }) {
            // 内容框（同系统提示词页 TextArea：预填当前生效模板，点击即编辑；上限与
            // 系统提示词同口径 TEMPLATE_CONTENT_MAX）
            TextArea({ placeholder: resolvePromptSlot(this.sheetKind).boxPlaceholder,
              text: this.promptContent })
              .width('100%')
              .height(240)
              .maxLength(TEMPLATE_CONTENT_MAX)
              .onChange((value: string): void => {
                this.promptContent = value;
              })
            // 输入框下双键（左恢复默认右保存；恢复默认 = 次钮 / 保存 = 主钮蓝底——
            // fallbackButton* 四件套双态，主操作键规约；保存 = 显式动作，收起面板不保存）
            Row({ space: 10 }) {
              Button('恢复默认')
                .layoutWeight(1)
                .fontColor(fallbackButtonFont(this.contentFallback, false))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .onClick((): void => {
                  this.restorePrompt();
                })
              Button('保存')
                .layoutWeight(1)
                .fontColor(fallbackButtonFont(this.contentFallback, true))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .onClick((): void => {
                  this.savePrompt();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8, bottom: 16 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
      }
      .titleBar(sheetTitleBarOptions(resolvePromptSlot(this.sheetKind).sheetTitle, '可编辑',
        (): void => {
          // ★ 2026-09-23 关闭确认笔：标题栏关闭键走关闭请求（脏态先确认）——与 bindSheet 的
          // onWillDismiss 两路同源（见 requestClosePrompt）
          this.requestClosePrompt();
        }, this.immersiveLevel))
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .bindToScrollable([this.promptScroller])
      .width('100%')
      .height('100%')
    } else {
      ModelPickerSheet({
        selProviderId: this.pickerProviderId(),
        selModelId: this.pickerModelId(),
        onPick: (providerId: string, modelId: string): void => {
          this.onPickModel(providerId, modelId);
        },
        onClose: (): void => {
          this.sheetKind = 'none';
        },
        bottomInset: this.bottomPad
      })
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_FUNCTIONAL_MODEL,
      content: (): void => {
        this.Content();
      }
    })
      // 半模态（坑64 姿势；ChatPage sheetKind 单面板多形态同款驱动）：模型选择 = DETENTS_FULL
      // 全屏单挡位（★ 2026-09-15 决明指令：默认展开全屏 + 取消半屏态 + 下拉直接收起，三站点
      // 同源）；提示词编辑面板保持官方默认双停靠 [MEDIUM, LARGE]（不在本次调整面内）
      .bindSheet(this.sheetKind !== 'none', this.SheetHost(), sheetPanelOptions((): void => {
        // 手势 / 系统返回关闭（下拉 / 侧滑 / 三键 back / ESC / 点蒙层）。★ 2026-09-23 关闭
        // 确认笔：本 lambda 是「选择模型」与「提示词编辑」共用的一个（同页 sheetKind 单面板
        // 多形态），必须按 isPromptSheet() 分流——提示词走关闭请求（脏态确认），模型选择无
        // 暂存直接关；确认未过时本回调不置 none，面板保持打开（官方：注册 onWillDismiss 后
        // 关闭由开发者在回调内决定）
        if (this.isPromptSheet()) {
          this.requestClosePrompt();
          return;
        }
        this.sheetKind = 'none';
      }, this.isPromptSheet() ? undefined : DETENTS_FULL))
  }
}
