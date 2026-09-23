// 「运行日志」页内容区组件（2026-08-21 自 LogPage.ets 拆出，拆分规则见 LogPage.ets 头注释）：
// 显示范围说明 / 空态提示 / 崩溃与报错日志区块 / 顶部分段胶囊悬浮层 / 「更多」菜单隐形锚点。
// 数据由 LogPage 下发（crashText/errorText/logMeta @Prop 单向同步、logTab @Link 双向——
// 胶囊写、LogPage 导出逻辑读）；分段胶囊参数与档位自订阅在公共组件 SegmentBar.ets
// （2026-08-21 提取后不再经本组件 @StorageProp，见该文件头）。数据刷新/导出不在本组件，
// 见 LogPage.ets。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import {
  CARD_PANEL_WIDTH,
  cardDescColor,
  cardTitleColor,
  MORE_MENU_ANCHOR_RIGHT,
  MORE_MENU_BUTTON_BOTTOM_INSET,
  SEGMENT_BAR_HEIGHT,
  TITLE_BAR_MASK_EXTRA_HEIGHT
} from '../common/Theme';
import { MAX_ERROR_LINES, MAX_LOG_STORAGE_BYTES } from './LogPageDataSource';
import { LOG_MORE_MENU_ANCHOR_ID } from './LogPageMoreMenu';
import { SegmentBar } from './SegmentBar';

// 锚点定位几何常量（MORE_MENU_ANCHOR_RIGHT / MORE_MENU_BUTTON_BOTTOM_INSET）2026-08-23 迁至
// common/Theme.ets 公共常量（Kimi 聊天页「更多」菜单复用同一几何，P2-4 提取；语义注释见该文件）

@Component
export struct LogPageContent {
  // 顶部留白（vp，LogPage 透传 PageMap 入参）：HDS 路径内容区延伸到标题栏背后
  // （渐变模糊蒙层透出滚动内容），语义与 InfoPage/AppearancePage 的 topPad 一致；回退路径传 0
  topPad: number = 0;
  // 崩溃记录文本（LogPage @State → 本组件 @Prop 单向同步）：APP_CRASH/APP_FREEZE 事件 JSON
  @Prop crashText: string = '';
  // 报错日志文本（同上）：hilog 沙箱过滤 WARN/ERROR/FATAL 行（尾部 MAX_ERROR_LINES 行）
  @Prop errorText: string = '';
  // 日志元信息（同上）：空态提示 / 统计信息
  @Prop logMeta: string = '';
  // 顶部分段分类选中项（@Link 双向同步）：0 全部 / 1 崩溃 / 2 报错
  @Link logTab: number;
  // 分段按钮选项（单选胶囊型，@since 18）：纯展示入参，普通成员
  private logItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全部' },
    { text: '崩溃' },
    { text: '报错' }
  ]);

  // 当前分类是否显示崩溃/报错区块（2026-08-21 分类过滤；@Builder 内不允许局部变量，
  // 抽为成员方法；与 LogPage 导出过滤同规则）：0 全部 / 1 仅崩溃 / 2 仅报错
  private showCrashBlock(): boolean {
    return this.logTab !== 2 && this.crashText !== '';
  }

  private showErrorBlock(): boolean {
    return this.logTab !== 1 && this.errorText !== '';
  }

  build() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——与 InfoPage 同款结构）
    Column() {
      // Stack 叠加（2026-08-21 吸顶改造，同 AppearancePage 定稿结构）：内容滚动层 +
      // 分段胶囊悬浮固定层——胶囊不随内容滚动；内容向上滚时从胶囊背后穿过，经胶囊背板
      // 沉浸光感材质（backgroundSystemMaterial）模糊透出
      Stack({ alignContent: Alignment.Top }) {
        // ── 内容滚动层：从屏幕顶开始（HDS 路径内容区延伸到标题栏背后），顶部留白 =
        // 胶囊悬浮位置（topPad - 8）+ 胶囊总高 SEGMENT_BAR_HEIGHT + 间距 28——
        // 内容初始静止在胶囊下方，滚动时滑入胶囊背后
        Scroll() {
          Column() {
            // 显示范围说明（2026-08-21 决明需求，位置 = 分段按钮正下方、随内容滚动）：
            // 报错行数上限插值 MAX_ERROR_LINES 常量（改常量文案自动同步）；时间窗
            // LOG_WINDOW_SECONDS（7 天）与崩溃记录系统上限（HiAppEvent 每类型 10 条）
            // 为字面量，改对应常量须同步改本文案
            Text(`显示近 7 天内的日志 · 报错/警告显示尾部最多 ${MAX_ERROR_LINES} 行 · 崩溃记录最多 10 条`)
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
              .margin({ bottom: 8 })
            // 存储容量说明（2026-08-22 决明需求；2026-09-04 上限 1MB→2MB 决明定稿）：
            // 日志落盘上限 MAX_LOG_STORAGE_BYTES（2MB，超出自动清理最旧记录——应用内
            // 自动执行，无需外部干预）；容量数值插值常量换算（改常量文案自动同步）
            Text(`运行日志最多保留 ${MAX_LOG_STORAGE_BYTES / (1024 * 1024)} MB，超出自动清理最旧记录`)
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
              .margin({ bottom: 12 })
            // 按顶部分类过滤（2026-08-21 决明需求）：刷新时数据全量拉取
            // （crashText/errorText），分类只控制显示，切换不重读文件
            if (!this.showCrashBlock() && !this.showErrorBlock()) {
              // 空态提示（未刷新 / 当前分类无内容 / 崩溃事件未生成）
              Text(this.logMeta === '' ? '点击右上角「更多」按钮读取报错与崩溃日志' :
                (this.logTab === 2 ? '暂无报错日志' :
                  (this.logTab === 1 ? '暂无崩溃记录（崩溃事件系统生成需 30 秒~2 分钟，可稍后刷新）' :
                    '无报错与崩溃记录（崩溃事件系统生成需 30 秒~2 分钟，可稍后刷新）')))
                .fontSize(14)
                .fontColor(cardDescColor())
                .textAlign(TextAlign.Center)
                .margin({ top: 40 })
                .width('100%')
            } else {
              if (this.showCrashBlock()) {
                // 崩溃记录区块：事件 JSON 全文（含崩溃原因/堆栈，逐条空行分隔）。
                // 长按选择：官方 Text.copyOption（@since 9，本地 SDK text.d.ts:660 核实）——
                // 长按文本弹出系统菜单（复制/全选/搜索/分享等，菜单项由系统提供应用无需实现）；
                // 区块仅在内容非空时渲染，直接 LocalDevice（设备内应用间复制粘贴）。
                // 选择范围仅限本 Text——标题/元信息等其他组件不设 copyOption
                Text('崩溃记录')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text(this.crashText)
                  .fontSize(12)
                  .fontColor(cardDescColor())
                  .textAlign(TextAlign.Start)
                  .width('100%')
                  .lineHeight(18)
                  .margin({ top: 8, bottom: 16 })
                  .copyOption(CopyOptions.LocalDevice)
              }
              if (this.showErrorBlock()) {
                // 报错日志区块：WARN/ERROR/FATAL 行；长按选择同崩溃记录（见上注释）
                Text('报错日志')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text(this.errorText)
                  .fontSize(12)
                  .fontColor(cardDescColor())
                  .textAlign(TextAlign.Start)
                  .width('100%')
                  .lineHeight(18)
                  .margin({ top: 8, bottom: 16 })
                  .copyOption(CopyOptions.LocalDevice)
              }
              // 元信息：统计行数（全量统计，切换分类不变化）
              Text(this.logMeta)
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
          }
          .width('100%')
          // 与「更多信息」页同款对齐规则：内容从顶部开始（Scroll align 默认 Center 的坑见
          // MainMenu.ets 注释——短内容会垂直居中，显式顶对齐防回归）
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .padding({ top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28, left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)

        // ── 分段胶囊悬浮固定层：Stack 顶层（后声明在上），顶部对齐，位置 = 原静止位置
        // （topPad - 8：标题栏下沿 + 蒙层渐隐边缘 8vp；回退路径 topPad=0 钳位 0）。
        // 官方单选胶囊型分段按钮参数定稿在公共组件 components/SegmentBar.ets
        // （2026-08-21 防屎山提取：与 AppearancePage 两处参数完全一致，单一来源勿单独乱调；
        // 官方/自定义边界注释见该文件头）；本层仅负责悬浮定位与宽度约束
        Column() {
          SegmentBar({
            items: this.logItems,
            selectedIndex: $logTab
          })
        }
        .width(CARD_PANEL_WIDTH)
        .margin({ top: Math.max(this.topPad - 8, 0) })

        // ── 「更多」菜单锚点（隐形 1×1，openMenu 的 TargetInfo 目标组件——官方全局菜单
        // 必须绑定一个页面内组件来定位弹出位置）：**普通布局定位**（Row 全宽 + Blank 撑开 +
        // padding right 16vp）——锚点右缘 = 屏宽 - 16vp = 「更多」按钮右缘（标题栏 padding
        // end，MORE_MENU_ANCHOR_RIGHT 常量）；锚点顶 = margin top =
        // topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET =
        // **按钮下沿**（勿写成标题栏下沿——按钮在 56vp 栏内垂直居中，下沿比栏底高 8vp，
        // 差值即菜单偏低的距离）。菜单顶 = 锚点下沿 + targetSpace 官方默认间距（≈7vp，
        // 与华为官方应用「按钮下沿→菜单顶」间距实测一致）；垂直位置要再微调用官方参数
        // targetSpace/offset（MenuOptions），勿回 anchorPosition。回退路径 topPad=0 钳位 0。
        // ★ 2026-08-21 踩坑①：.position({ x: 'calc(100% - 56vp)' }) 绝对定位——calc 字符串
        // 真机未生效（x 落回 0，锚点在屏幕左上角 → 菜单贴着返回按钮弹出），数字 y 生效
        // （高度正常）；改 Row 普通布局后 x/y 均确定生效。
        // ★ 踩坑②：Placement.BottomLeft 语义是「菜单左缘贴锚点左缘」（向右下展开），方向
        // 不符；正确值是 Placement.BottomRight（菜单右缘贴锚点右缘 = 按钮右缘，官方动画
        // 从右上角向左下角弹出，弹出组装见 LogPageMoreMenu.ets/AppMenuHost）。菜单宽度官方
        // 自适应，勿设固定宽
        Row() {
          Blank()
          Column()
            .width(1)
            .height(1)
            .id(LOG_MORE_MENU_ANCHOR_ID)
        }
        .width('100%')
        .padding({ right: MORE_MENU_ANCHOR_RIGHT })
        .margin({ top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0) })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
