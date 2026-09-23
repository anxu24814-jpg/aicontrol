// 运行参数 chip 行（2026-08-29 对话页 UI 对齐任务 2 自 dshinhm ChatParamChipBar **裁剪版**：
// 权限 chip 整块剥除——manual/auto/yolo 三档是 kap 会话编排语义，aicontrol 为 OpenAI 兼容
// 通用客户端无对应功能；★ 2026-08-31 任务 E：状态胶囊与弹窗取消（领导指令）——现单 chip
// = 思考强度）。
// ★ 2026-09-09 二百二十九：思考入口迁标题栏「思考」热区（决明「先点思考弹思考档位菜单，
// 原输入框上思考键取消，由新键承担」）——**HDS 路径**思考 chip 不再渲染（条件 = 同一 HDS
// 能力位）；**回退路径**无 stackBuilder 机制、画不了标题栏胶囊，思考 chip 保留（避免非
// HDS 设备功能不可达，与模型入口留在回退菜单同口径）。本文件另导出 ThinkingMenu 菜单体，
// 供标题栏（ChatPage）与助手「模型设置」页复用。
// 输入胶囊上方
// 悬浮小胶囊行（普通行布局 Row + Blank 顶右——dshinhm 七十九改回退横滑定稿；★ 2026-09-16
// 会话级技能启用笔曾加「技能 N」chip，同日「单条消息指定技能」笔随覆盖退役；★ 2026-09-19
// 联网 chip 迁标题栏「更多」菜单（决明指令「全按官方…嵌套二级菜单」，官方 MenuItem builder
// 子菜单承载，落点 ChatMoreMenu/ChatPage）：HDS 路径 0 胶囊（本组件渲染空行）、回退路径
// 1 胶囊〔思考〕，仍无滚动量；将来胶囊增多若需横滑以附件条先例另起）。
// 纯展示组件：状态经 @Prop 入、事件经回调出。
// · chip 本体 = 自绘 Row 胶囊——尺寸/字号/圆角对齐官方 Chip 组件 NORMAL 档官方资源数值
//   （dshinhm 二十八改实锤：chip_normal_height=36vp / chip_normal_text_padding=16 /
//   chip_normal_icon_size=16 / 字号=ohos_id_text_size_button2=14fp；官方 ChipV2 当前 SDK
//   组件表无注册不可用、旧版 Chip 是 @Builder 函数组件无属性链——自绘 + 官方数值对齐）。
// · 圆角 18 = chip 高 36vp 的一半 = 半圆（官方 8vp 圆角真机呈方形感；与输入胶囊同组的
//   芯片须同「胶囊半圆」语言——圆角=高度一半）。
// · 材质：REGULAR 基准档随沉浸光感总档偏移 + interactive 按压形变；设材质后不再
//   设背景色/边框（材质铁律）；「无」档 Material.empty = 透明文字 chip。
// · 菜单：bindMenu 官方菜单（坑16：弹窗类绑定属性必须挂原生组件——chip 的自绘 Row）；
//   REGULAR 官方菜单基准档；chip 在页面底部，菜单向上展开。思考菜单选项集由父组件传入
//   （dshinhm 七十一改定稿回官方 MenuItem 样式；2026-08-31 任务 B 起选择经 ChatSendCtrl
//   进请求——四协议方言落点见 RequestCompose，'' = 默认不传）；★ 2026-08-31 关闭档：
//   「关闭」项仅 offOk（@StorageProp 广播键自订阅——ChatPage setConnInfo 写入，坑16
//   正解）为 true 时显示——关闭
//   思考是服务商官方规格差异（DeepSeek 域），非支持域不暴露（文档口径见协议能力矩阵）。
// ★ 2026-09-10 联网开关归位笔（决明拍板 A/B 项）：联网 chip 从「会话级独立开关」升格为
//   **归属助手启用清单（assistants.tools 含 search_web）的快捷编辑位**——值走
//   CHAT_WEBSEARCH_ON_KEY 广播键自订阅（原 @Link 三级链撤，值由助手字段派生后无需双向），
//   选择上行落库；总开关（PREF_SEARCH_SERVICE_ENABLED_KEY）关闭 = 置灰 + 点击自持 toast
//   （原 CHAT_WEBSEARCH_ALLOWED_KEY 广播键与 onWebSearchDenied 四级回调链整条删除，
//   净减代码）；两份重复 Row 的 chip 本体收进无参 @Builder WebChipBody。
// ★ 2026-09-10 会话级覆盖层笔第二阶段（决明拍板联网语义 = 第 2 种「强制关闭」）：上一笔的
//   「chip 写回助手」整条撤回，改为**两级模型**——①助手启用清单 = **能力上限**（不含
//   search_web 则 chip 置灰 + 点击提示去助手页开，会话内**不可开启**，硬闸）②上限之内
//   chip 调的是**本会话**（关闭 = 写本会话覆盖，只影响这条会话；开启 = 清覆盖跟随助手）。
//   值键 CHAT_WEBSEARCH_ON_KEY = 生效值（助手清单 ∩ 本会话覆盖）；闸键
//   CHAT_WEBSEARCH_ALLOWED_KEY = 助手清单（同页同链写入，两键恒同步）。★ 两侧不对称是
//   刻意的：模型的助手绑定是「默认」（可被会话覆盖越过），联网的助手清单是「上限」（不可
//   越过）——后续自检勿把此处当"不一致"顺手统一，语义见 docs/方案-会话级覆盖层模型与联网。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { uiMaterial } from '@kit.ArkUI';

// 「关闭思考」可用广播键（bool——ChatPage setConnInfo 时按 supportsThinkingOff(conn.baseUrl)
// 写入，本组件 @StorageProp 自订阅（坑16「订阅式通道正常」正解）；只写不删（残留 bool
// 无害——无「出页清空滞后」类竞态，坑15 只发生在清空场景））
export const CHAT_OFF_SUPPORTED_KEY: string = 'chatOffSupported';

// 「联网开关」状态广播键（bool——★ 2026-09-10 会话级覆盖层笔第二阶段：值 = **本会话生效
// 值** = 归属助手启用清单含 search_web（能力上限）**且** 本会话未关（webSearchOverride
// !== '0'），ChatPage 解析覆盖 + 提示词态后同链写入。原 @Link 三级链下发——值改由
// 助手字段派生后不再需要双向。★ 2026-09-19 联网 chip 迁标题栏「更多」菜单后 chip 不再
// 消费本键，现读点 = ChatPage（自写自读 + 弹出菜单时作快照进 ChatMoreMenuCallbacks）。
// 键留本文件 = 既有先例（SearchLimits 注释引用的「中转键声明在 chip 组件文件」口径不变）。
// 只写不删：键残留 bool 无害——无坑15「出页清空滞后」类竞态）
export const CHAT_WEBSEARCH_ON_KEY: string = 'chatWebSearchOn';

// 「联网开关可开启」广播键（bool——★ 2026-09-10 会话级覆盖层笔第二阶段新增：值 = 归属助手
// 启用清单是否含 search_web，即**能不能联网的能力上限**。原 chip 消费判可点/置灰（false =
// 硬闸，决明拍板第 2 种语义「助手内关闭 → 会话内不能再开启」）；★ 2026-09-19 联网 chip 迁
// 标题栏「更多」菜单后，读点 = ChatPage（可用性快照 + 指引 toast 分派，语义不变——仍是
// 「不可用就是不可用」，不写回助手）。与 CHAT_WEBSEARCH_ON_KEY 同一次解析、同链写入
// ——两键恒同步，勿只写其一：值键决定「显示开还是关」，闸键决定「能不能点」。只写不删）
export const CHAT_WEBSEARCH_ALLOWED_KEY: string = 'chatWebSearchAllowed';

// 思考菜单选项集广播键（string[]——2026-09-06 模型级精化：画像行按模型收窄选项集
//〔kimi-k3 = 默认/low/high/max、K2.x = 默认/关闭等，派生源 ModelRegistry.thinkingOptionsFor〕；
// ChatPage setConnInfo 写入，ChatParamChipRow @StorageProp 自订阅——坑16 正解同
// OFF_SUPPORTED 键（原 @Prop 沿 PageShell.content @BuilderParam 链传播，conn 异步就绪后
// 首帧冻结 = 收窄集永远到不了 chip）；只写不删；键未写 = [''] 仅「默认」档保守兜底）
export const CHAT_THINKING_OPTIONS_KEY: string = 'chatThinkingOptions';

// ═══ 思考档位菜单（2026-09-01 自 ChatParamChipRow 内 @Builder 提取为独立组件——助手
// 「模型设置」页复用同款菜单〔领导指令「同会话页」〕；原逻辑逐项搬迁零行为变更）。
// 选项/值/offOk/回调参数化：聊天页 offOk = CHAT_OFF_SUPPORTED_KEY 广播键（连接服务商
// 判定），助手页 = 绑定服务商 baseUrl 直判（supportsThinkingOff）——两消费方各自传值 ═══
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
    Menu() {
      if (this.options.includes('')) {
        // 「默认」= 不带思考字段（请求侧默认行为——协议方言落点在 RequestCompose）
        MenuItem({ content: '默认' })
          .selected(this.value === '')
          .selectIcon(true)
          .onClick(() => {
            this.onPick('');
          })
      }
      if (this.options.includes('off') && this.offOk) {
        // 「关闭」= 显式关闭思考（仅支持域暴露——offEnabled 经流层进 compose：
        // openai thinking.disabled / anthropic reasoning.none，见 RequestCompose）
        MenuItem({ content: '关闭' })
          .selected(this.value === 'off')
          .selectIcon(true)
          .onClick(() => {
            this.onPick('off');
          })
      }
      if (this.options.includes('low')) {
        MenuItem({ content: 'low' })
          .selected(this.value === 'low')
          .selectIcon(true)
          .onClick(() => {
            this.onPick('low');
          })
      }
      if (this.options.includes('high')) {
        MenuItem({ content: 'high' })
          .selected(this.value === 'high')
          .selectIcon(true)
          .onClick(() => {
            this.onPick('high');
          })
      }
      if (this.options.includes('max')) {
        MenuItem({ content: 'max' })
          .selected(this.value === 'max')
          .selectIcon(true)
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

@Component
export struct ChatParamChipRow {
  // 思考强度（@Link 绑定父 @State——★ 2026-08-31 归正：原 @Prop 沿 PageShell.content
  //（@BuilderParam）传播不随父刷新（坑16），选档后 chip 回显冻结；@Link 为订阅式
  // 官方通道。''=默认不传、off=关闭、low/high/max=档位）
  @Link thinkingValue: string;
  // 思考菜单选项集（'' 首项为「默认」；2026-09-06 模型级精化起改广播键自订阅——原
  // @Prop 沿 PageShell.content（@BuilderParam）链传播，conn 异步就绪后首帧冻结
  //（坑16，offOk 同款事故路径）；ChatPage setConnInfo 写 CHAT_THINKING_OPTIONS_KEY，
  // 写即刷新。值 = 画像行收窄集或全量 THINKING_OPTIONS，「关闭」项另受 offOk 闸）
  @StorageProp(CHAT_THINKING_OPTIONS_KEY) thinkingOptions: string[] = [''];
  // 「关闭思考」可用（★ 2026-08-31 修复：原 @Prop 沿 PageShell.content（@BuilderParam）
  // 传播——坑16 定稿「内容组件入参 @Prop 不随父 @State 更新」，conn 就绪后首帧 false 冻结
  //（真机「选了 DeepSeek 模型仍无关闭项」实锤）；改 AppStorage 广播键自订阅（ChatPage
  // setConnInfo 时按 supportsThinkingOff(conn.baseUrl) 写入，写即刷新——只写不删无坑15
  // 竞态；页面残留 bool 无害）
  @StorageProp(CHAT_OFF_SUPPORTED_KEY) offOk: boolean = false;
  // 档位选择回调（父组件落值——驱动 chip 回显并随下次请求下发）
  onPickThinking: (option: string) => void = () => {
  };
  // 菜单开合回调（★ 2026-09-09 真机报障：决明「展开态点两胶囊，输入框都会变回收起，菜单也跟着
  // 下移」——点 chip 开菜单会致 TextArea 失焦，失焦收起链把卡片收掉）。消费方 ChatInputBar 据此
  // 在菜单开着期间压制失焦收起；驱动 = 官方 MenuOptions.onAppear/onDisappear（d.ts @since 10）。
  // ★ 2026-09-19 联网 chip 迁标题栏「更多」菜单后本组件只剩思考 chip 一处菜单挂此回调（联网
  // 菜单在 ChatPage 页面级，收起守卫不随迁——登记变更记录观察）。默认空实现 = 无消费方时零影响
  onMenuStateChange: (open: boolean) => void = () => {
  };
  // 沉浸光感档位 + 系统颜色模式（AppStorage 自订阅，PageShell 同款
  // 姿势，免逐页透传）：chip/菜单材质、菜单配色深浅分治统一驱动
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = chip 本体官方灰实底（新规范下内容区材质不生效）；
  // false = 原 REGULAR 材质光感；bindMenu 菜单属弹窗豁免区不受本开关影响；AppStorage 订阅式
  // 切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 官方 HDS 导航可用性（与 ChatPage/PageShell 同一能力位）：true = 思考入口在标题栏
  // 「思考」热区（HDS 路径），本行无 chip 渲染（联网 2026-09-19 迁更多菜单、思考在标题栏）；
  // false = 回退路径，思考 chip 保留（二百二十九，见文件头注释；能力位运行期不变，普通成员即可）
  private hdsAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Core');

  // 思考档位菜单（bindMenu builder 位——菜单体 2026-09-01 提取为独立 ThinkingMenu 组件
  //（助手模型设置页同款复用），@Builder 壳仅做组件实例化挂载；坑16：弹窗类绑定属性
  // 挂原生组件——chip 的自绘 Row）
  @Builder
  ThinkingMenuBuilder() {
    ThinkingMenu({ value: $thinkingValue, options: this.thinkingOptions, offOk: this.offOk,
      onPick: (option: string): void => {
        this.onPickThinking(option);
      }
    })
  }

  // chip 档位文案（''＝默认不传 / off＝关闭 / 其余档位原文）
  private label(): string {
    return this.thinkingValue === '' ? '默认' :
      this.thinkingValue === 'off' ? '关闭' : this.thinkingValue;
  }

  // 宽度自适应内容（★ 2026-09-09 六改：本行与悬浮键胶囊同排于调用方 Row——根节点若声明
  // width('100%') 会占满整行、把 Blank 与键胶囊挤出容器（Row 内子组件 flexShrink 默认 0，
  // 官方 d.ts）；整行占位与右侧留白由调用方的 Row + Blank 承担）
  build() {
    Row({ space: 8 }) {
      // 思考强度 chip（「胶囊只保留等级」——档位原文/默认/关闭；样式见文件头）。★ 二百二十九：
      // **回退路径专用**——HDS 路径思考入口在标题栏「思考」热区（见文件头注释），此处不渲染
      if (!this.hdsAvailable) {
        Row({ space: 4 }) {
          Text(this.label())
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(18)
        .clip(true)
        // chip 本体双态（2026-09-03 内容区回退）：实底态 = 官方灰阶实色（app.color.
        // comp_fallback_gray 深浅分治、不透明——原官方语义色带透明度可读性差，2026-09-03
        // 决明反馈后换；无按压形变——选项类 chip 口径同 ModelCapsCard 范式）；光感态 = 原
        // REGULAR 材质（interactive 按压形变/触点光效）；bindMenu 菜单属弹窗豁免区不受本开关影响
        .backgroundColor(this.contentFallback ? $r('app.color.comp_fallback_gray') : Color.Transparent)
        .systemMaterial(this.contentFallback ? uiMaterial.Material.empty :
          resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true))
        .bindMenu(this.ThinkingMenuBuilder, {
          placement: Placement.TopLeft,
          // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
          systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true),
          onAppear: (): void => {
            this.onMenuStateChange(true);
          },
          onDisappear: (): void => {
            this.onMenuStateChange(false);
          }
        })
      }
      // ★ 2026-09-19 联网 chip 整段退役（迁标题栏「更多」菜单「联网」项 + 官方二级菜单，
      // 决明指令；HDS 路径本行渲染空行、回退路径仅余上方思考 chip——沿革见文件头注释）
    }
  }
}
