// 官方分段胶囊按钮（CapsuleSegmentButtonV2，@since 18）公共封装（2026-08-21 防屎山 P2-4 提取）：
// 全项目 24 处消费 / 20 文件（2026-09-20 实测：AppearancePage「光感/背景」、LogPageContent
// 「全部/崩溃/报错」、PreferencesPage 生物识别/启动页×2、UsageStatsPage 时段、CostStatsPage
// 时段、ProviderPage 协议、ProviderDetailPage TTL/高级页分区×2、ProviderConfigPanel
// 协议/响应体×2、ModelEditPage 模型类型、SearchEnginePage 搜索区段、ChatSessionList
// 收藏/全部、ModelPickerSheet 收藏分段、MemoryPage 读取方式
// 〔2026-09-13 记忆按需读取〕、SkillEditPage「技能/正文/文件」三段页签〔2026-09-13 分段胶囊笔〕、
// KnowledgeEditPage「条目/正文/文件」三段页签〔2026-09-23 知识库文件笔——知识库条目编辑页由
// 单页表单改三段〕、
// FunctionalModelPage「系统识别/内置识别/视觉模型」引擎三态〔2026-09-16 内置识别引擎〕、
// ProviderKeysPanel「轮询/随机」取钥方式二态〔2026-09-17 取钥方式笔〕、
// MessageCopySheet「纯文本/Markdown」口径二态〔2026-09-18 消息复制优化〕、
// ToolsSettingsPage「每次确认/自动通过」确认二态×2〔2026-09-18 浏览高危确认降压阀；2026-09-20
// HTTP 请求独立域笔加第二张卡「HTTP 写操作确认」〕、
// AssistantMemoryPage「全局记忆/助手记忆」作用域二态〔2026-09-20 助手级记忆〕）——
// 参数完全一致，定稿参数从此单一来源
// （勿单独乱调）——定稿过程与官方查证见 docs/变更记录.md 2026-08-20/21 相关条目。
// ★ 2026-09-20 应用内自检全量退役：SelfCheckPage「基础自检/高级自检」消费点随页面删除
//（24 处/20 文件 → 23 处/19 文件，位移非删除）。
// ★ 2026-09-23 知识库文件笔：KnowledgeEditPage「条目/正文/文件」三段页签合法 +1
//（23 处/19 文件 → 24 处/20 文件，位移非删除）。
// ★ 2026-09-07 全项目分段按钮优化前置盘点：任何消费点改动先读本头注释与下方「四档参数速查
// 表」；消费点差异参数 = 仅 items/selectedIndex（消费侧零覆盖——grep 全量核实），尺寸/配色/
// 材质全部在本封装。
//
// ── 双档参数速查表（A 档 × 光感态 = 2 组；应用内唯一真值 = 下方各函数实现，本表为对照速查）──
// | 档位 | 背板 | 背板材质（backgroundSystemMaterial） | 选中项底色 | 选中项字色 | 尺寸 |
// | A 档（光感新规范开启，默认） | 官方灰阶实色（app.color.comp_fallback_gray，深浅分治） | 不设（undefined） | 官方默认蓝底（不传） | 官方默认白字（不传） | 32vp 胶囊 / 40vp 背板 / 四周 4vp（与光感态同参，2026-09-11 统一） |
// | 光感态·浅 | 不设（undefined） | resolvedUiMaterial(ULTRA_THIN+偏移+interactive+colorInvert) | #1A000000 | font_primary | 两态共用（同 A 档） |
// | 光感态·深 | 不设 | 同上 | #26FFFFFF | font_primary | 同上 |
// ★ A 档 = 2026-09-07 决明拍板（替代原实底态——9-06 运动健康取色批次退役，见文件头④）：
// 「开启回退兜底后的分段胶囊材质改为沉淀的不接光感的纯官方 A 档」——原零参数走官方默认
//（d.ts @since 18 逐一核实可选），不接光感；★ 2026-09-11 几何统一修订：材质/选中色/字色
// 三类仍零参数（官方默认），尺寸改两态共用的项目值（32vp 胶囊/四周 4vp，口径见 build 注释）
//——「A 档 = 官方默认」自此仅指材质与配色。
// ★ 2026-09-07 晚真机反馈追加（本笔）：A 档零参数下背板 = 官方系统资源
// segment_button_v2_tab_button_background **半透明灰、几乎全透出背后内容、可读性差**
//（官方设计 = 悬浮融合式背板，吸顶+内容滚过场景暴露）——决明拍板「未选中态改实底，
// 灰底取色权衡」→ **背板单项覆盖为官方灰阶实色 app.color.comp_fallback_gray**
//（浅 #E6E8EA / 深 #3A3A3C，官方色板值、不透明、深浅分治资源自动切换；按钮族/恢复键/
// 变量插入卡三处真机同色先例）；选中蓝底白字/尺寸仍官方默认。
// 尺寸（两态共用，2026-09-11 统一）：itemMinHeight 32vp / buttonPadding 4vp / itemPadding
// 四向 4vp——与官方默认资源 40vp 背板高/36vp 选中胶囊/padding_level1=2vp/padding_level2=4vp
// 的对应关系与修正史见下方 build 注释（2026-08-20 两轮真机 uitest 实测定稿：「32 且四周各 4」；
// 2026-09-11 起两态共用 32/四周 4，官方 36vp/2vp 默认几何退出，仅存于本史实与 build 注释）。
// 两态切换驱动：@StorageProp(CONTENT_FALLBACK_KEY)（光感新规范开关，外观页第四卡——
// 2026-09-07 由「内容区回退」更名，行为等价）——true = A 档（默认）；
// false = 光感态。官方行为差异：无材质（A 档）不支持选中项跟手拖拽，有材质（光感态）
// 支持（「SegmentButtonV2 开启沉浸光感后，支持选中项背景跟随手指拖拽，否则不支持」——
// 2026-09-07 测试页真机实证）。
// 官方标准对照（2026-09-07 测试页 A/B 段遗留参数，供优化对照）：A 纯官方默认 = 零参数
// （背板 = 官方默认系统资源色 buttonBackgroundColor 默认 $r('sys.color.segment_button_v2_tab_button_background')，
// 选中 = 官方默认 $r('sys.color.segment_button_v2_tab_selected_item_background') 蓝底 +
// font_on_primary 白字、默认 36vp 胶囊/40vp 背板——**全走官方默认值，未传任何参数**）；
// B 官方标准材质 = 仅设 backgroundSystemMaterial（ImmersiveMaterial ULTRA_THIN +
// interactive:true）+ 其余全官方默认。项目现状（C 光感态）与 B 的差异 = 半透明灰选中底 +
// font_primary + 32vp/双4vp 尺寸覆盖（2026-08-20 决明三轮真机反馈调整史，见变更记录
// 2026-08-20/21）。★ 2026-09-11 起本对照段的尺寸行仅作史实：两态几何已统一为 32vp 胶囊/
// 四周 4vp，A/B 与 C 的差异只剩材质与配色。
// ★ A 与项目「无」档的语义区别（官方开启文档原文分界）：A = backgroundSystemMaterial
// undefined = **恢复组件默认效果**（官方默认资源色背板，非材质；背板色已被官方灰阶实色
// 覆盖——2026-09-07 晚拍板，见速查表下方★追加注）；项目「无」档 = 显式传
// uiMaterial.Material.empty = **关闭沉浸光感效果** + 项目自定义其余
// 参数（半透明灰选中/取色实底/32vp 尺寸）——两者外观与语义都不同，勿混用。
//
// 官方/自定义边界（决明问「自动反色是官方实现吗」的答案，2026-08-21 本地 SDK d.ts 核实）：
// ① 材质自动反色 = 官方：backgroundSystemMaterial 第 6 参 colorInvert=true
//    （uiMaterial.ImmersiveOptions.colorInvert @since 26.0.0 默认 false；官方 SegmentButtonV2
//    文档示例 6「设置背景板材质」同款）——材质背景自动明暗反色适配前景内容；
// ② 选中项字色 = 官方系统资源自动适配：itemSelectedFontColor 显式指定 $r('sys.color.font_primary')
//    （浅色黑/深色白，框架自动切换；官方说明 26.0.0 起设置自动反色材质时字色资源自动反色）。
//    ——官方默认 font_on_primary 白字配官方蓝色强调底，底色改灰后白字不协调（2026-08-20
//    决明真机反馈）才改此值；
// ③ 选中项底色 = 项目自定义 + 手写深浅色分治：官方默认 $r('sys.color.segment_button_v2_tab_selected_item_background')
//    （系统资源自动适配，d.ts:726 核实）；决明 2026-08-20 要求蓝底改透明灰、透出背后内容，
//    官方无「选中项材质」参数（d.ts 全字段核对）且无半透明灰系统资源——传带透明度灰
//    （浅色黑 10% / 深色白 15%，参照 sliderTrackColor 风格），深浅色由本组件手写三元切换。
// ④ 实底态（内容区回退）配色 = 2026-09-06 决明供图精准取色：华为运动健康「视疲劳状态」页
//    顶部分段胶囊深浅两截图，胶囊区像素中位数取样（轨道 P95 散布 0 级纯色；取色数据见
//    docs/变更记录.md 当日条）——轨道(未选中底) 深 #212121 / 浅 #FAFBFD，选中胶囊
//    深 #373737 / 浅 #E2E2E2，均不透明；仅分段胶囊换装，fallbackButton* 按钮族配色不动。
//    ★ 2026-09-07 A 档改造退役：实底态整体替换为纯官方 A 档零参数（本文件速查表首行），
//    取色批次不再被 SegmentBar 消费（史实保留）；app.color.comp_fallback_gray 仍由
//    ImmersiveLevel.fallbackButtonBg 按钮族消费，勿删。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';

@Component
export struct SegmentBar {
  // 选项（纯展示，普通成员——父组件构造传入，不触发子组件重渲染；变化场景无）
  items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  // 选中项索引：@Link 与父组件 @State 双向同步（父传 $selectedIndex 语法）
  @Link selectedIndex: number;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色分治选中项底色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（AppStorage 共享，驱动背板材质，随沉浸光感总档；
  // 总档「无」时显式关闭）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 光感新规范开关（2026-09-03 立，2026-09-07 由「内容区回退」更名）：true = A 档（默认——
  // 华为新规范下内容区材质不生效，开启即官方标准形态〔材质/配色，尺寸两态共用项目值〕，
  // 见文件头④）；false = 原 backgroundSystemMaterial 光感材质（选中项半透明灰）；
  // AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  // 双态参数簇（2026-09-07 光感新规范更名 + A 档改造；2026-09-11 几何统一）：
  // contentFallback=true（默认）= A 档（背板官方灰阶实色 + 选中底/字色官方默认——
  // 2026-09-07 晚真机反馈背板透明灰可读性差，背板单项覆盖为官方灰阶实色，见速查表下方
  // ★追加注）；false = 光感态（背板材质 + 2026-08-20 定稿选中色）。尺寸三参 2026-09-11
  // 起两态共用项目值（32vp 胶囊/四周 4vp/文字边距四向 4），开关只切材质与配色。光感态背板材质
  // （参数对齐官方 SegmentButtonV2 文档示例 6「设置背景板材质」，2026-08-20 决明贴全文核对）：
  // · 基准档 ULTRA_THIN（官方示例同款最透档——分段按钮悬浮吸顶、背后内容滚动穿过，最透
  //   观感；REGULAR 通用基准在示例 6 中未采用）+ 档位偏移（弱 +1 更厚、强 -1 钳位最薄）
  // · interactive=true：按压弹性形变 + 触点光晕；colorInvert=true：自动反色（配合
  //   itemSelectedFontColor 的 font_primary 文字自动适配）
  // · applyShadow 默认 true（材质自带阴影）；lightEffect 用系统默认白色（leveledUiMaterial
  //   内 color: undefined，官方示例另一种写法为 $r('sys.color.interactive_click')）。
  // 分离构造（同对象双背板属性有二义性）：非本态属性传 undefined = 未设置，互不干扰。
  // 注：expanded 写法仅作注释载体——实际在 build 内局部变量展开，不写 spread（ArkTS 字面
  // 量 spread 受限，勿改回 `...this.xxx()` 形式）。

  // 背板色：A 档 = 官方灰阶实色（app.color.comp_fallback_gray——官方色板值 #E6E8EA/#3A3A3C
  // 不透明，resources base/dark 分治自动切换，无手写深浅三元；按钮族/恢复键/变量插入卡
  // 三处真机同色先例，2026-09-03 决明为可读性亲测选定——comp_background_tertiary 语义色
  // 带透明度被否）；光感态 = 不设（材质优先）
  private backButtonBg(): ColorMetrics | undefined {
    if (this.contentFallback) {
      return ColorMetrics.resourceColor($r('app.color.comp_fallback_gray'));
    }
    return undefined;
  }

  // 选中项底色：A 档 = 不传（官方默认蓝底 $r('sys.color.segment_button_v2_tab_selected_item_background')，
  // 系统资源自动适配——2026-08-20 曾按决明反馈改透明灰，A 档回归官方默认）；
  // 光感态 = 半透明灰透出背后内容（深白 15% / 浅黑 10%，2026-08-20 定稿，见文件头③）
  private selectedItemBg(): ColorMetrics | undefined {
    if (this.contentFallback) {
      return undefined;
    }
    const dark: boolean = this.appColorMode ===
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return ColorMetrics.resourceColor(dark ? '#26FFFFFF' : '#1A000000');
  }

  // 选中项字色：A 档 = 不传（官方默认 font_on_primary 白字配官方蓝底，框架自动适配）；
  // 光感态 = font_primary（浅色黑/深色白——底色改半透明灰后白字不协调，2026-08-20
  // 决明真机反馈改此值）
  private selectedFontColor(): ColorMetrics | undefined {
    if (this.contentFallback) {
      return undefined;
    }
    return ColorMetrics.resourceColor($r('sys.color.font_primary'));
  }

  // 选中胶囊高度：两态共用（2026-09-11 拍板几何统一）32vp——官方默认 36vp 与本项目 32vp
  // 并存时开关会在两套几何间跳变；统一后开关只切材质与配色（定稿史见 build 注释）
  private itemMinH(): LengthMetrics {
    return LengthMetrics.vp(32);
  }

  // 背板内边距：两态共用 4vp——与 32vp 胶囊配合实现四周各 4vp 对称（须与 itemMinHeight
  // 联动修改，见 build 注释；官方默认 padding_level1=2vp 已随 2026-09-11 统一退出）
  private buttonPad(): LengthMetrics {
    return LengthMetrics.vp(4);
  }

  // 胶囊内部文字边距：两态共用四向 4vp（start/end 由官方默认 8vp 收窄——控制胶囊内文字
  // 边距，不影响胶囊相对背板位置）
  private itemPad(): LocalizedPadding {
    return {
      top: LengthMetrics.vp(4),
      bottom: LengthMetrics.vp(4),
      start: LengthMetrics.vp(4),
      end: LengthMetrics.vp(4)
    };
  }

  // 背板材质：A 档 = 不传（无材质，背板即官方默认资源色）；光感态 = 沉浸光感材质
  //（参数解析见上方双态参数簇注释）
  private backMaterial(): uiMaterial.Material | undefined {
    return this.contentFallback ? undefined :
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.ULTRA_THIN,
        this.immersiveLevel, true, true, true);
  }

  build() {
    // 官方单选胶囊型分段按钮（CapsuleSegmentButtonV2，@since 18——「分段按钮组件用于创建
    // 页签型、单选或多选的胶囊型分段按钮」，官方文档 ohos-arkui-advanced-segmentbuttonv2）。
    // ★ 宽度：官方无宽度参数且不支持通用属性（width 无效），组件宽度 = 父容器宽度
    // （选项等分撑满）——使用处外层包 CARD_PANEL_WIDTH 容器居中约束（2026-08-20 定稿，
    // 见 common/Theme.ets CARD_PANEL_WIDTH 注释）。
    // ★ 选中胶囊尺寸与四周等距（2026-08-20 两轮真机 uitest 实测修正定稿；2026-09-11 起
    // 两态共用本几何——A 档原官方默认 36vp 胶囊/2vp 边距，0+36+2*2=40 官方布局本自对称，
    // 已随统一退出）：
    // 官方布局 = 胶囊（选项区）与背板「内边距对齐」（顶对齐 + buttonPadding 顶部间隙），
    // 不做垂直居中；背板高 = max(buttonMinHeight 官方资源 40vp, buttonPadding×2 + 项高)。
    // ① 首版缩至 32vp 未动 buttonPadding（默认 2vp）：顶距 2vp、底距 40−2−32=6vp → 偏上
    // 4vp（决明反馈根因）；② 恢复 36vp 官方默认：2+36+2=40 上下对称但胶囊偏大；
    // ③ 光感态定稿：32vp + buttonPadding 4vp——4+32+4=40 恰好等于背板最小高、不撑高，
    // 选中胶囊相对背板上下左右各 4vp 完全对称（决明要求「32 且四周各 4」）。
    // ④ 2026-09-11 几何统一（决明「把官方的蓝色选中胶囊大小与光感的统一，这样两者就只有
    // 材质差异」）：A 档尺寸三参改为与光感态完全同参（32vp 胶囊/四周 4vp/文字边距四向 4），
    // 恒等式 4+32+4=40 保证背板恒 40vp（SEGMENT_BAR_HEIGHT 与悬浮层留白计算零扰动）——
    // 开关自此只切材质与配色。
    // itemPadding 四周 4vp（top/bottom 恰为官方默认 padding_level2=4vp，start/end 由官方
    // 默认 padding_level4=8vp 收窄为 4vp）——控制胶囊内部文字边距，不影响胶囊相对背板位置；
    // 文字在胶囊内垂直居中（官方实现，实测 32vp 胶囊内文字上下 ~0.3vp 偏差）。
    // 官方资源数值（SDK previewer resources.txt 核实）：背板高 40vp
    // （segment_button_v2_singleline_background_height）、选中胶囊默认高 36vp
    // （segment_button_v2_singleline_selected_height）、padding_level1=2vp、padding_level2=4vp
    CapsuleSegmentButtonV2({
      items: this.items,
      selectedIndex: this.selectedIndex,
      $selectedIndex: (index: number) => {
        this.selectedIndex = index;
      },
      // 外观双态（2026-09-07 A 档改造：contentFallback=true = 材质/选中底/字色官方默认
      // 零参数——传 undefined 即不设置，d.ts 全可选；尺寸 2026-09-11 起两态共用项目值恒传；
      // 参数解析见上方双态参数簇注释；ColorMetrics 需 resourceColor 包装，参数类型为
      // ColorMetrics 不接受裸字符串）
      itemSelectedBackgroundColor: this.selectedItemBg(),
      itemSelectedFontColor: this.selectedFontColor(),
      itemMinHeight: this.itemMinH(),
      // 背板内边距（四周统一，两态共用 4vp）：与 32vp 胶囊配合实现四周各 4vp 对称
      //（见上注释），须与 itemMinHeight 联动修改
      buttonPadding: this.buttonPad(),
      itemPadding: this.itemPad(),
      // 双态材质（2026-09-07 更名口径）：A 档 = 背板官方灰阶实色（backButtonBg——官方
      // 默认资源背板半透明、吸顶滚过场景可读性差，2026-09-07 晚真机反馈拍板覆盖为不透明
      // 官方灰阶）+ 不设材质；光感态 = backgroundSystemMaterial 材质 + 不设背板色；
      // 非本态传 undefined（可选属性 = 未设置）
      buttonBackgroundColor: this.backButtonBg(),
      backgroundSystemMaterial: this.backMaterial()
    })
  }
}
