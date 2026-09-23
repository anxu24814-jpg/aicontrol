// 主动消息横幅（2026-09-12 主动消息第二笔「应用内呈现层」，任务书-主动消息二笔-呈现层；
// 方案档 docs/方案-主动消息-20260912.md；2026-09-18 横幅单行卡化与光感承载层笔〔任务书-
// 主动消息横幅单行卡化与光感承载层-20260918〕样式与材质重做）：主动消息成功落库后
// ProactiveGen 落库尾段写 PROACTIVE_BANNER_KEY（三元组 JSON 串），本组件 @StorageProp
// @Watch 消费——顶部浮出单行卡「铃铛 + 助手名 + 消息首行 + 右箭头」：点击派发
// PROACTIVE_OPEN_CMD_KEY（HomeNavigation 消费 openSession 直达该会话）并收起；不点
// 7 秒自动收起（定时器成对——aboutToDisappear 必清，内存红线）；后到覆盖前条（键变即
// 重挂重计时，不排队不堆叠）。
// 挂载 = pages/Index.ets 根 Stack 顶层（笔 2 主方案：覆盖含二级页在内的全部页面——项目
// 无应用级浮层先例，原 Column 单容器无处叠浮层改 Stack；降级方案 = 挂 HomeNavigation
// 内容区 Stack〔一级页可见二级页不可见〕，走真机异常才启用）。
// ★ 材质 = Toggle 承载层（2026-09-18 笔更正原「浮出提示类与 Toast 族同档」口径误判——
// 本横幅是根 Stack 顶层自定义浮层，Toast 豁免指 promptAction 系统弹层不含自定义 Stack
// 浮层，内容区组件挂 systemMaterial 静默失效不报错，真机 hilog 打 Material inactive:
// out of scope〔透明横幅根因〕）。豁免判定按组件类型：Toggle 在官方白名单内页面全域
// 生效，与是否承载内容无关——ToggleType.Button 作隐形承载层画材质，内容层作兄弟节点
// 叠其上；依据 = docs/归档/调研-归档-03-平台能力与架构.md 第 7 篇〔沉浸光感内容区恢复
// 做法〕+ 第 10 篇〔Toggle 承载层工程实证〕+ 官方 FAQ《沉浸光感常见问题》层级条〔材质
// 视觉层级在 backgroundColor 之下 → 材质态底色必须透明〕与顺序条〔systemMaterial 放
// 属性链末位〕。★ GPL 红线：上游 miha_hm 只借方法与形态，代码自写禁抄。承载层形态
// 五条（缺一不可，调研第 10 篇 §1.2）：①matchParent 尺寸——禁百分比（Stack 子节点百分
// 比按可用尺寸解析会顶大卡片）；②圆角恒与外壳同值（否则出现更小圆角内嵌边框；现 20
// ——2026-09-19 决明拍板横幅圆角略大不与行卡 16 统一）；③底色透明；④enabled/focusable(false) +
// accessibilityLevel('no') +
// hitTestBehavior(None) 不抢焦点不接交互；⑤属性链末位挂静态材质（interactive 恒
// false——流光须材质层自接触摸，与承载层不接触摸互斥，调研坑清单条目）。外壳
// clip(true) 让材质被圆角裁切。「无」档（resolveEffectiveLevel 归一 -1）不渲染承载层，
// 内容层垫 cardBg 实底兜底（原 comp_fallback_gray 随单行卡化改 cardBg——与设置页卡
// 深浅一致）。材质不接「光感新规范」开关（横幅非行内按钮，跟随沉浸光感总档现状语义）。
// 进场/收起 = 官方 TransitionEffect（StoragePage 先例；禁全局 animateTo——UIContext
// 纪律）。
// 横幅与红点解耦（任务书 §二）：横幅是「此刻看见」，红点（PROACTIVE_UNREAD_CONV_KEY）
// 是「事后能追」——横幅收起/被忽略不影响红点存在；横幅富交互（回复/快捷按钮）不做。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  bumpProactiveOpenCmd, parseBannerPayload, PROACTIVE_BANNER_KEY
} from '../common/ProactiveGen';
import {
  IMMERSIVE_LEVEL_KEY, resolveEffectiveLevel, resolvedUiMaterial
} from '../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../common/Theme';

// 自动收起时长（ms）
const BANNER_HIDE_MS: number = 7000;

@Component
export struct ProactiveBanner {
  // 顶部安全区（vp，Index 实测下发——横幅贴状态栏下方；@Prop：异步值状态驱动重渲染，坑57）
  @Prop statusBarHeight: number = 0;
  // 横幅驱动键（值变即重挂：解析新载荷 → 显示 → 重起收起定时器；'' = 无横幅）
  @StorageProp(PROACTIVE_BANNER_KEY) @Watch('onBannerKey') bannerPayload: string = '';
  // 沉浸光感档位（横幅材质随沉浸光感总档与总档解析——弹层族双键）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 卡底深浅色（「无」档 cardBg 实底用——ProactivePage 同款写法）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 当前横幅三元组（@Watch 解析落位；visible false = 无横幅零渲染零命中）
  @State private convId: string = '';
  @State private assistantName: string = '';
  @State private preview: string = '';
  @State private visible: boolean = false;
  // 自动收起定时器（-1 = 未排；重挂/点击收起/组件销毁三处必清——成对释放红线；
  // ChatInputBar.collapseTimer 同款哨兵范式）
  private hideTimer: number = -1;

  aboutToDisappear(): void {
    this.cancelHideTimer();
  }

  // 驱动键变化（后到覆盖前条：先清旧定时器再解析挂新；解析失败 = 收起不显示）
  private onBannerKey(): void {
    this.cancelHideTimer();
    const payload = parseBannerPayload(this.bannerPayload);
    if (payload === null) {
      this.visible = false;
      return;
    }
    this.convId = payload.convId;
    this.assistantName = payload.name;
    this.preview = payload.text;
    this.visible = true;
    this.hideTimer = setTimeout((): void => {
      this.hideTimer = -1;
      this.visible = false;
    }, BANNER_HIDE_MS);
  }

  private cancelHideTimer(): void {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  // 点击：派发直达命令 + 收起（用户点击即取消自动收起——先清定时器再收起；
  // HomeNavigation 对 convId 判空兜底）
  private onBannerTap(): void {
    this.cancelHideTimer();
    this.visible = false;
    bumpProactiveOpenCmd(this.convId);
  }

  // 是否材质态（「无」档 resolveEffectiveLevel 归一 -1 → 承载层不渲染 + 内容层 cardBg
  // 实底兜底；材质态内容层底色恒透明——材质视觉层级在 backgroundColor 之下，官方 FAQ）
  private materialActive(): boolean {
    return resolveEffectiveLevel(this.immersiveLevel) >= 0;
  }

  build() {
    // 空 Stack = 无横幅时零尺寸零命中（不设 width/height 即内容自适应）；横幅挂顶层条件渲染
    Stack() {
      if (this.visible) {
        // 卡体外壳（clip(true) 让承载层材质被圆角裁切——承载层形态红线）
        Stack() {
          // Toggle 承载层（仅材质态渲染；ToggleType.Button 官方豁免白名单——形态五条见头注释）
          if (this.materialActive()) {
            Toggle({ type: ToggleType.Button, isOn: false }) { }
              .width(LayoutPolicy.matchParent)
              .height(LayoutPolicy.matchParent)
              .borderRadius(20)
              .backgroundColor(Color.Transparent)
              .enabled(false)
              .focusable(false)
              .accessibilityLevel('no')
              .hitTestBehavior(HitTestMode.None)
              // 属性链末位挂静态材质（官方 FAQ：systemMaterial 须在背景色等样式属性之后）
              .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
                this.immersiveLevel, false))
          }
          // 内容层（唯一点击层；行规格 = docs/规范-列表卡片与组卡.md §3 官方实测表——
          // 图标 24vp 标题色 + 标题 16fp Medium + 预览 14fp layoutWeight(1) + 右箭头 14fp）
          Row({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.bell'))
              .fontSize(24)
              .fontColor([cardTitleColor()])
            Text(this.assistantName)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
            Text(this.preview)
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          // 底色双态：材质态透明；「无」档 cardBg 实底（comp_fallback_gray 随单行卡化退役）
          .backgroundColor(this.materialActive() ? Color.Transparent : cardBg(this.appColorMode))
          .onClick((): void => {
            this.onBannerTap();
          })
        }
        .width(CARD_PANEL_WIDTH)
        .borderRadius(20)
        .clip(true)
        .margin({ top: this.statusBarHeight + 8 })
        // 官方 TransitionEffect 进出场（translate 上方 ±60vp 滑入滑出 + 渐隐；StoragePage
        // OPACITY 先例 + translate 组合，d.ts common.d.ts:5389 实锤）
        .transition(TransitionEffect.translate({ y: -60 })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: 250, curve: Curve.EaseOut }))
      }
    }
  }
}
