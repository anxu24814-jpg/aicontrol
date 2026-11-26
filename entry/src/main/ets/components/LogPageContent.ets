// 「运行日志」页内容区组件（自 LogPage.ets 拆出，拆分规则见 LogPage.ets 头注释）：
// 说明行与隐私承诺 / 空态提示 / 系统事件区块与报错区块 / 「更多」菜单隐形锚点。数据由
// LogPage 下发（eventBlocks/errorText/logMeta/usageText @Prop 单向同步、logTab @Link——
// 档位写入在 LogPage 的标题栏下方带胶囊，本组件读它做档位过滤）。数据刷新/导出/清除
// 不在本组件，见 LogPage.ets。
// 契约：分段四档（全部/崩溃/异常/报错）；事件区块生成在 LogPageDataSource.sysEventBlocks
//（七类各一区块，空类不出现），本组件只做档位过滤与渲染；显示上限走常量插值，改常量文案自动同步。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import {
  cardDescColor,
  cardTitleColor,
  MORE_MENU_ANCHOR_RIGHT,
  MORE_MENU_BUTTON_BOTTOM_INSET,
  SEGMENT_BAR_HEIGHT,
  TITLE_BAR_MASK_EXTRA_HEIGHT
} from '../common/Theme';
import {
  blockShownInTab,
  errorShownInTab,
  EVENT_KEEP_PER_KIND,
  LOG_TAB_ABNORMAL,
  LOG_TAB_CRASH,
  LOG_TAB_ERROR,
  MAX_ERROR_LINES,
  SysEventBlock
} from './LogPageDataSource';
import { LOG_MORE_MENU_ANCHOR_ID } from './LogPageMoreMenu';
import { InfoCard } from './InfoCard';

// 锚点定位几何常量（MORE_MENU_ANCHOR_RIGHT / MORE_MENU_BUTTON_BOTTOM_INSET）在
// common/Theme.ets（Kimi 聊天页「更多」菜单复用同一几何；语义注释见该文件）

// 分段选项单源（单选胶囊型，@since 18）：唯一消费方 = LogPage 的 TopSegmentBand（标题栏
// 下方带承载），本组件只按档位过滤内容、不渲染胶囊
export const LOG_TAB_ITEMS: SegmentButtonV2Items = new SegmentButtonV2Items([
  { text: '全部' },
  { text: '崩溃' },
  { text: '异常' },
  { text: '报错' }
]);

@Component
export struct LogPageContent {
  // 顶部留白（vp，LogPage 透传 PageMap 入参）：内容区延伸到标题栏背后（渐变模糊蒙层透出
  // 滚动内容），语义与 InfoPage/AppearancePage 的 topPad 一致
  topPad: number = 0;
  // 系统事件区块（LogPage @State → 本组件 @Prop 单向同步）：七类事件的（标题 + 文本 + 分组）
  @Prop eventBlocks: SysEventBlock[] = [];
  // 报错日志文本（同上）：hilog 沙箱过滤 WARN/ERROR/FATAL 行（尾部 MAX_ERROR_LINES 行）
  @Prop errorText: string = '';
  // 统计行（同上）：空态提示 / 各类条数与报错行数
  @Prop logMeta: string = '';
  // 沙箱日志占用行（同上）：数据层 logUsageText 组好（占用 + 件数 + 上限 + 本次清理）
  @Prop usageText: string = '';
  // 顶部分段分类选中项（@Link 双向同步）：0 全部 / 1 崩溃 / 2 异常 / 3 报错（常量与判据单源
  // 在 LogPageDataSource）
  @Link logTab: number;

  // 当前档位下要显示的事件区块（档位判据在 LogPageDataSource.blockShownInTab——页面导出
  // 过滤同源同函数；@Builder 内不声明局部量，故经本方法取用一次）
  private visibleBlocks(): SysEventBlock[] {
    const out: SysEventBlock[] = [];
    for (const block of this.eventBlocks) {
      if (blockShownInTab(block.group, this.logTab)) {
        out.push(block);
      }
    }
    return out;
  }

  // 报错区块是否显示（0 全部与 3 报错显示；1 崩溃与 2 异常两档下不显示——判据同源数据层）
  private showErrorBlock(): boolean {
    return errorShownInTab(this.logTab) && this.errorText !== '';
  }

  // 空态文案（四态 + 未刷新态）：崩溃与运行异常来自系统事件，官方口径是崩溃后需重新启动
  // 应用才能取到（勿写「系统生成需 30 秒~2 分钟」——官方文档无出处，已核查删除）
  private emptyText(): string {
    if (this.logMeta === '') {
      return '点击右上角「更多」按钮读取运行记录';
    }
    if (this.logTab === LOG_TAB_CRASH) {
      return '暂无崩溃与冻屏记录。崩溃后需重新启动应用，再进本页查看';
    }
    if (this.logTab === LOG_TAB_ABNORMAL) {
      return '暂无运行异常记录';
    }
    if (this.logTab === LOG_TAB_ERROR) {
      return '暂无报错日志';
    }
    return '暂无记录。崩溃与运行异常在重新启动应用后仍可查看';
  }

  build() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——与 InfoPage 同款结构）
    Column() {
      // Stack 叠加：内容滚动层 + 「更多」菜单隐形锚点——锚点悬浮固定，不随内容滚动
      Stack({ alignContent: Alignment.Top }) {
        // ── 内容滚动层：从屏幕顶开始（内容区延伸到标题栏背后），顶部留白 = 胶囊悬浮位置
        //（topPad - 8）+ 胶囊总高 SEGMENT_BAR_HEIGHT + 间距 28——内容初始静止在胶囊下方，
        // 滚动时滑入胶囊背后经材质模糊透出（胶囊由 LogPage 的 TopSegmentBand 承载）
        Scroll() {
          Column() {
            // 说明卡（InfoCard 单源件：报错/事件/隐私承诺三事实合并 ≤81 字，行数上限插值
            // 常量、改常量文案自动同步；占用动态文案单列下方条件态 InfoCard）
            InfoCard({ text: `报错日志页面只显示尾部 ${MAX_ERROR_LINES} 行，导出取近7天全量。` +
              `崩溃与异常来自系统事件，每类保留 ${EVENT_KEEP_PER_KIND} 条。` +
              '日志仅存本机不自动上传，分享前请检查，可能含接口地址与对话片段。', fullWidth: true })
              .margin({ bottom: 12 })
            // 占用说明卡（数据层 logUsageText 组好：占用 + 件数 + 2 MB 上限 + 本次自动清理
            // 份数），空白时不渲染——动态文案随页面 @Prop 刷新
            if (this.usageText !== '') {
              InfoCard({ text: this.usageText, fullWidth: true })
                .margin({ bottom: 12 })
            }
            // 按顶部分类过滤：刷新时数据全量拉取（eventBlocks/errorText），分类只控制显示
            if (this.visibleBlocks().length === 0 && !this.showErrorBlock()) {
              // 空态提示（未刷新 / 当前分类无内容）
              Text(this.emptyText())
                .fontSize(14)
                .fontColor(cardDescColor())
                .textAlign(TextAlign.Center)
                .margin({ top: 40 })
                .width('100%')
            } else {
              // 系统事件区块（七类各一区块，按分类表顺序；标题 + 正文，正文长按可选）
              ForEach(this.visibleBlocks(), (block: SysEventBlock) => {
                Text(block.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(cardTitleColor())
                  .width('100%')
                // 正文 = 事件时间行 + 摘要行 + 参数 JSON（页面口径为头部片段，导出含完整内容；
                // 生成与截断口径见 LogPageDataSource.sysEventBlocks）
                Text(block.text)
                  .fontSize(12)
                  .fontColor(cardDescColor())
                  .textAlign(TextAlign.Start)
                  .width('100%')
                  .lineHeight(18)
                  .margin({ top: 8, bottom: 16 })
                  .copyOption(CopyOptions.LocalDevice)
              }, (block: SysEventBlock): string => block.key)
              // 报错日志区块：WARN/ERROR/FATAL 行；长按选择同事件区块
              if (this.showErrorBlock()) {
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
              // 元信息：各类条数与行数（全量统计，切换分类不变化）
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
        .scrollBar(BarState.Off)

        // 分段胶囊不在此渲染：由 LogPage 的 TopSegmentBand 在标题栏下方带承载（选项表
        // 单源 LOG_TAB_ITEMS 为本组件导出件）

        // ── 「更多」菜单锚点（隐形 1×1，openMenu 的 TargetInfo 目标组件——官方全局菜单
        // 必须绑定一个页面内组件定位弹出位置）：**普通布局定位**（Row 全宽 + Blank 撑开 +
        // padding right 16vp）——锚点右缘 = 「更多」按钮右缘（MORE_MENU_ANCHOR_RIGHT）；
        // 锚点顶 = topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET =
        // **按钮下沿**（勿写成标题栏下沿——按钮在 56vp 栏内垂直居中，下沿比栏底高 8vp）。
        // 菜单顶 = 锚点下沿 + targetSpace 官方默认间距（≈7vp）；垂直微调走官方参数
        // targetSpace/offset（MenuOptions），勿回 anchorPosition。
        // ★ 踩坑①：.position({ x: 'calc(100% - 56vp)' }) 绝对定位——calc 字符串真机未生效
        //（x 落回 0，锚点在屏幕左上角 → 菜单贴返回按钮弹出），改 Row 普通布局后 x/y 均生效。
        // ★ 踩坑②：Placement.BottomLeft 语义是「菜单左缘贴锚点左缘」（向右下展开）方向不符；
        // 正确值 BottomRight（菜单右缘贴锚点右缘 = 按钮右缘，弹出组装见
        // LogPageMoreMenu.ets/AppMenuHost）。菜单宽度官方自适应，勿设固定宽
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
