// 运行参数 chip 行（dshinhm ChatParamChipBar 裁剪版：权限 chip 整块剥除——aicontrol 为
// OpenAI 兼容通用客户端无 kap 会话编排语义；状态/联网/技能入口均已迁出，思考入口在标题
// 栏「思考」热区，现 = 安全输入 chip，见文末沿革）。本文件另导出 ThinkingMenu 菜单体，
// 供标题栏（ChatPage）与助手「模型设置」页复用。
// · chip 本体 = 自绘 Row 胶囊——尺寸/字号/圆角对齐官方 Chip 组件 NORMAL 档官方资源数值
//  （chip_normal_height=36vp / chip_normal_text_padding=16 / chip_normal_icon_size=16 /
//   字号 14fp；官方 ChipV2 当前 SDK 组件表无注册不可用、旧版 Chip 无属性链——自绘 +
//   官方数值对齐）。
// · 圆角 18 = chip 高 36vp 的一半 = 半圆（官方 8vp 圆角真机呈方形感；与输入胶囊同组的
//   芯片须同「胶囊半圆」语言——圆角=高度一半）。
// · 材质：REGULAR 基准档随沉浸光感总档偏移 + interactive 按压形变；设材质后不再设背景色/
//   边框（材质铁律）；「无」档 Material.empty = 透明文字 chip。
// · 菜单：ThinkingMenu 菜单体经 bindMenu 官方菜单挂载（坑16：弹窗类绑定属性必须挂原生
//   组件）；REGULAR 官方菜单基准档；思考菜单选项集由父组件传入（选择经 ChatSendCtrl
//   进请求——四协议方言落点见 RequestCompose，'' = 默认不传）；「关闭」项仅 offOk = true
//   时显示——关闭思考是服务商官方规格差异（DeepSeek 域），非支持域不暴露。
// 纯展示组件：状态经 @Prop/@Link 入、事件经回调出。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import { menuDividerColor, fallbackGrayBg, menuEndCheck } from '../../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { uiMaterial } from '@kit.ArkUI';

// 「关闭思考」可用广播键（bool——ChatPage setConnInfo 时按 supportsThinkingOff(conn.baseUrl)
// 写入，本组件 @StorageProp 自订阅〔坑16 正解〕；只写不删：残留 bool 无害，坑15 只发生在
// 清空场景）
export const CHAT_OFF_SUPPORTED_KEY: string = 'chatOffSupported';

// 「联网开关」状态广播键（bool——值 = **本会话生效值** = 归属助手启用清单含 search_web
//（能力上限）且本会话未关（webSearchOverride !== '0'），ChatPage 解析覆盖与提示词态后同链
// 写入。联网 chip 已迁标题栏「更多」菜单，现读点 = ChatPage（自写自读 + 弹出菜单时作快照）。
// 键留本文件 = 既有先例（SearchLimits 注释引用的「中转键声明在 chip 组件文件」口径）。
// 只写不删：残留 bool 无害）
export const CHAT_WEBSEARCH_ON_KEY: string = 'chatWebSearchOn';

// 「联网开关可开启」广播键（bool——值 = 归属助手启用清单是否含 search_web，即**能不能联网
// 的能力上限**；false = 硬闸（助手内关闭 → 会话内不能再开启），不可越过、不写回助手；读点
// = ChatPage）。与 CHAT_WEBSEARCH_ON_KEY 同一次解析、同链写入——两键恒同步，勿只写其一：
// 值键决定「显示开还是关」，闸键决定「能不能点」；值键（会话覆盖可越过助手绑定「默认」）
// 与闸键（助手清单「上限」不可越）的不对称是刻意的，勿当"不一致"顺手统一。只写不删
export const CHAT_WEBSEARCH_ALLOWED_KEY: string = 'chatWebSearchAllowed';

// 「会话归属控制台助手」广播键（bool——安全输入 chip 与暂存条的显隐判据。值 = 本会话归属
// 助手是否启用 AI 配置域四件（manage_providers/manage_models/test_provider/manage_balance）
// 任一——启用该域的会话需要安全输入面板填明文。ChatPage 在提示词态 load 解析后写入，与
// 联网两键同一刷新点。只写不删：写点先 false 后真值，进页瞬间清上一会话残留，防会话切换
// 的「旧值真显示」窗口）
export const CHAT_AI_ADMIN_OWNER_KEY: string = 'chatOwnerAiAdmin';

// 思考菜单选项集广播键（string[]——画像行按模型收窄选项集〔kimi-k3 = 默认/low/high/max、
// K2.x = 默认/关闭等，派生源 ModelRegistry.thinkingOptionsFor〕；ChatPage setConnInfo 写入，
// chip @StorageProp 自订阅〔坑16 正解〕；只写不删；键未写 = [''] 仅「默认」档保守兜底）
export const CHAT_THINKING_OPTIONS_KEY: string = 'chatThinkingOptions';

// 思考档位镜像广播键（string——侧栏形态主区标题栏覆盖层自持在 HomeNavigation 栈层
//〔DrawerHomeTitleBar〕，与 ChatPage 的 thinkingValue @State 分居两层：页面真源经镜像键
// 发布、覆盖层菜单落值经本键回 Consumption。写点 = ChatPage（@Watch 镜像 + 进页初值发布，
// '' 起步）与 DrawerHomeTitleBar（菜单落值发布）；读点 = DrawerHomeTitleBar @StorageProp
// 订阅同步到覆盖层。会话级内存态不落库，键随换会话由新实例初值发布复位。只写不删：
// 残留 string 无害，坑15 只发生在清空场景）
export const CHAT_THINKING_VALUE_KEY: string = 'chatThinkingValue';

// 思考键交互期镜像广播键（boolean——菜单开合与按压期上报，语义同 thinkingHold @Link 三级链
// 的广播化替代面：DrawerHomeTitleBar 菜单开合写键 → ChatPage @StorageProp @Watch 消费回
// @State → 经既有 @Link 三级链下发 ChatInputBar 收起守卫。写点 = DrawerHomeTitleBar 单点；
// 挂载即发布 false 清上一形态残留。只写不删：残留 bool 无害）
export const CHAT_THINKING_HOLD_KEY: string = 'chatThinkingHold';

// ═══ 思考档位菜单（自 ChatParamChipRow 内 @Builder 提取为独立组件——ChatPage 标题栏与
// 助手「模型设置」页复用同款）。选项/值/offOk/回调参数化：聊天页 offOk =
// CHAT_OFF_SUPPORTED_KEY 广播键（连接服务商判定），助手页 = 绑定服务商 baseUrl 直判
//（supportsThinkingOff）——两消费方各自传值 ═══
@Component
export struct ThinkingMenu {
  // 当前档位（@Link 双向——菜单项选中态随值刷新；''=默认不传、off=关闭、low/high/max）
  @Link value: string;
  // 菜单选项集（'' 首项为「默认」，常量 AiTypes.THINKING_OPTIONS；「关闭」项须选项含
  // 'off' 且 offOk 为 true 才渲染）
  @Prop options: string[] = [''];
  // 「关闭思考」可用（语义见上——显式传入替代原 @StorageProp 订阅，消费方各自判定）
  @Prop offOk: boolean = false;
  // 档位选择回调（父组件落值）
  onPick: (option: string) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    // 条件项 if 链逐个渲染——选项数 ≤5，Menu 内 ForEach 支持性未核实不冒进；分割线官方
    // Menu.menuItemDivider（@since 12，默认不显示须显式设置；mode 必须 EMBEDDED_IN_MENU；
    // 颜色走 menuDividerColor 深浅分治）
    // ★ 2026-11-11 决明「统一为勾在右」笔：五项的勾全部自 selected + selectIcon（官方内置勾
    // 钉在项内容行第 0 位 = 文字左侧）改 **项尾勾** menuEndCheck(选中条件)——判据与引擎取证
    // 单源在 common/Theme.ets 同名函数注释；本笔不挂 selected，故左勾不再出现
    Menu() {
      if (this.options.includes('')) {
        // 「默认」= 不带思考字段（请求侧默认行为——协议方言落点在 RequestCompose）
        MenuItem({ content: '默认', symbolEndIcon: menuEndCheck(this.value === '') })
          .onClick(() => {
            this.onPick('');
          })
      }
      if (this.options.includes('off') && this.offOk) {
        // 「关闭」= 显式关闭思考（仅支持域暴露——offEnabled 经流层进 compose：
        // openai thinking.disabled / anthropic reasoning.none，见 RequestCompose）
        MenuItem({ content: '关闭', symbolEndIcon: menuEndCheck(this.value === 'off') })
          .onClick(() => {
            this.onPick('off');
          })
      }
      if (this.options.includes('low')) {
        MenuItem({ content: 'low', symbolEndIcon: menuEndCheck(this.value === 'low') })
          .onClick(() => {
            this.onPick('low');
          })
      }
      if (this.options.includes('high')) {
        MenuItem({ content: 'high', symbolEndIcon: menuEndCheck(this.value === 'high') })
          .onClick(() => {
            this.onPick('high');
          })
      }
      if (this.options.includes('max')) {
        MenuItem({ content: 'max', symbolEndIcon: menuEndCheck(this.value === 'max') })
          .onClick(() => {
            this.onPick('max');
          })
      }
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }
}

// 思考档位显示文案（''＝默认不传 / off＝关闭 / 其余档位原文）——chip 与「会话状态」半模态
// 共用单源（禁两处各写一份；文案随档位集演进只改本处）
export function thinkingDisplayLabel(value: string): string {
  return value === '' ? '默认' :
    value === 'off' ? '关闭' : value;
}

// 思考档位滑轨面板专用文案（★ 2026-11-25 思考档位滑轨笔）：「默认」在滑轨语境里读作「自动」，
// 低/高/最高取单字短标签（轨道上方标题行只有一个词，长标签会把面板顶宽）。
// ★ 刻意不改 thinkingDisplayLabel——菜单项与设置页行尾仍显示「默认/关闭/low/high/max」原文，
// 本笔不做文案统一（菜单回退路径须逐字节零回归）。
export function thinkingLevelLabel(value: string): string {
  return value === '' ? '自动' :
    value === 'off' ? '关闭' :
    value === 'low' ? '低' :
    value === 'high' ? '高' :
    value === 'max' ? '最高' : value;
}

@Component
export struct ChatParamChipRow {
  // 思考强度（@Link 绑定父 @State——坑16：@Prop 沿 PageShell.content（@BuilderParam）
  // 传播不随父刷新，选档后 chip 回显冻结；@Link 为订阅式官方通道。''=默认不传、off=关闭、
  // low/high/max=档位）
  @Link thinkingValue: string;
  // 思考菜单选项集（广播键自订阅——坑16：@Prop 沿 @BuilderParam 链传播在 conn 异步就绪
  // 后首帧冻结；ChatPage setConnInfo 写 CHAT_THINKING_OPTIONS_KEY 写即刷新；值 = 画像行
  // 收窄集或全量 THINKING_OPTIONS，「关闭」项另受 offOk 闸）
  @StorageProp(CHAT_THINKING_OPTIONS_KEY) thinkingOptions: string[] = [''];
  // 「关闭思考」可用（AppStorage 广播键自订阅——坑16 同款：@Prop 首帧 false 冻结〔真机
  //「选了 DeepSeek 模型仍无关闭项」实锤〕；ChatPage setConnInfo 时按 supportsThinkingOff
  // 写入写即刷新；只写不删无坑15 竞态）
  @StorageProp(CHAT_OFF_SUPPORTED_KEY) offOk: boolean = false;
  // 档位选择回调（父组件落值——驱动 chip 回显并随下次请求下发）
  onPickThinking: (option: string) => void = () => {
  };
  // 菜单开合回调：点 chip 开菜单会致 TextArea 失焦、失焦收起链把卡片收掉（真机报障）——
  // 消费方 ChatInputBar 据此在菜单开着期间压制失焦收起；驱动 = MenuOptions.onAppear/
  // onDisappear。思考 chip 撤除后本组件暂无菜单挂此回调（联网菜单在 ChatPage 页面级，收起
  // 守卫不随迁），成员保留 = ChatInputBar 构造位仍在传参。默认空实现 = 无消费方时零影响
  onMenuStateChange: (open: boolean) => void = () => {
  };
  // 安全输入 chip 显隐（值 = 会话归属助手启用 AI 配置域任一件——父组件订阅
  // CHAT_AI_ADMIN_OWNER_KEY 后经本 @Prop 下发，未启用该域的会话恒 false 恒不渲染）：点击
  // 父组件拉起 SecureInputSheet 半模态——直填/暂存两态在面板内部分源
  @Prop secureInputVisible: boolean = false;
  onSecureInputTap: () => void = () => {
  };
  // 沉浸光感档位 + 系统颜色模式（AppStorage 自订阅，PageShell 同款
  // 姿势，免逐页透传）：chip/菜单材质、菜单配色深浅分治统一驱动
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：true = chip 本体官方灰实底（新规范下内容区材质不生效）；false = 原
  // REGULAR 材质光感；bindMenu 菜单属弹窗豁免区不受本开关影响；AppStorage 订阅式切换即刷
  //（坑16 正解）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 卡底透明度档位：chip 实底灰随档叠 alpha（会话页常驻面订阅即刷）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 宽度自适应内容（★ 2026-09-09 六改：本行与悬浮键胶囊同排于调用方 Row——根节点若声明
  // width('100%') 会占满整行、把 Blank 与键胶囊挤出容器（Row 内子组件 flexShrink 默认 0，
  // 官方 d.ts）；整行占位与右侧留白由调用方的 Row + Blank 承担）
  build() {
    Row({ space: 8 }) {
      // 安全输入 chip（显隐判据见 @Prop 注释。几何/材质全参数照官方 Chip NORMAL 档数值
      //（36vp 半圆/官方数值/材质随光感档/「无」档 Material.empty，见文件头）——禁自创几何；
      // 符号 sys.symbol.key（坑 72 两道门：构建绿 + 真机实锤，不达改 sys.symbol.lock 并申报）
      if (this.secureInputVisible) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.key'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
          Text('安全输入')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(18)
        .clip(true)
        .backgroundColor(this.contentFallback ?
          fallbackGrayBg(this.appColorMode, this.cardAlphaLevel) : Color.Transparent)
        .systemMaterial(this.contentFallback ? uiMaterial.Material.empty :
          resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true))
        .onClick((): void => {
          this.onSecureInputTap();
        })
      }
      // 沿革（防回游）：联网 chip 已迁标题栏「更多」菜单「联网」项（官方二级菜单）；状态
      // chip 已改形退役——入口随迁 ChatInputBar 工具行「状态」裸图标键（三态换色判据见该件
      // statusIconColor 注释）；思考 chip 已随 HDS 回退撤除（思考入口在标题栏「思考」热区），
      // 本行现仅安全输入 chip
    }
  }
}
