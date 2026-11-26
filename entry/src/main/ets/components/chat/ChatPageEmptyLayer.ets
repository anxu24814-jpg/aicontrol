// 空态三态覆盖层（自 ChatPageContent 域级拆出，方法体原样搬迁）：消息流为空时的三态覆盖层
//（错误重试 / 旧格式墓碑 / 引导空态）——仅无消息时有节点，盖住空 List；三分支互斥，层序：
// 本层之上 = 加载蒙层、再上 = 底部渐变蒙层（挂载点序见 ChatPageContent build 内注释）。
// · 为何不并入 ChatLoadingOverlay.ets（反碎片下限②申报）：彼件是「时间轴机制件」（双定时器
//   延迟出现/最短驻留 + 相位判定 + 两 @Watch 起拍，自持计时状态），本件是无状态判据渲染件
//  （dataSource 三字段判据 + 重试回调）；并入会造「时间机制 + 静态分支」混合件且名不符实。
// · 数据通道：dataSource @ObjectLink 订阅 @Track（与宿主同通道——禁 @Prop 下发热点，
//   坑16 家族）；errorText @Prop（宿主 @Prop 链再下一跳）；topPad 普通成员（构造传入不变）。
// · Scroll 包裹：内容高度加 topPad 滚动余量 + 底部同量 padding 吸收——静止观感按全屏几何
//   居中（空态图标的中心与启动页图标重合，引导语在图标下方），可滚动量 = topPad（与「内容
//   可滑入标题栏蒙层」同语义）；边缘回弹对齐消息层。
import { ChatDataSource } from './ChatDataSource';
import { cardDescColor } from '../../common/Theme';

// 空态应用图标与系统启动页同尺寸：module.json5 的 startWindowIcon 指向 startIcon.png
// （256×256，scripts/gen-app-icon.mjs verifyStart 钉死），官方口径 = 启动页按资源实际大小
// 居中显示、不随窗口尺寸缩放——本处用 UIContext.px2vp 把 256px 换算成本设备 vp，图标才与
// 启动页图标物理像素等大（直接写 vp 会随屏幕密度漂移）。
const START_ICON_PX: number = 256;
// 空态引导语：可见行与图标上方隐形对称占位共用（改文案只改这一处）
const EMPTY_HINT_TEXT: string = '开始新的对话';

@Component
export struct ChatPageEmptyLayer {
  // 消息数据源（三态判据通道：messageCount / historyLoaded / blockedNotice 经 @Track 订阅）
  @ObjectLink dataSource: ChatDataSource;
  // 初始加载失败提示（'' = 无；与 messageCount 联合判定错误态——覆盖层含「重试」）
  @Prop errorText: string = '';
  // 顶部留白（标题栏蒙层下沿——Scroll 内容高度余量与底部同量吸收）
  topPad: number = 0;
  // 错误态「重试」（重拉历史 + 重读连接，接 ChatPage 既有方法）
  onRetry: () => void = () => {
  };

  // 启动页图标在本设备的显示尺寸（vp；UIContext 版 px2vp，全局版自 API 18 废弃）
  private startIconSize(): number {
    return this.getUIContext().px2vp(START_ICON_PX);
  }

  // 内容已有结论（空会话回执或消息已装）：启动衔接图标在此刻起 300ms 淡出。
  // ★ 不用 entryFirstScreenReady——它缺省 true（DB 等待期尚未起手时恒真），会把首帧图标
  // 直接透明化；historyLoaded 才是「内容已有结论」的事实点，shellArrived 与消息区渐显
  // 同门（同拍交叉淡出）
  private contentRevealed(): boolean {
    return this.dataSource.shellArrived &&
      (this.dataSource.historyLoaded || this.dataSource.messageCount > 0);
  }

  // 衔接层可见判据：错误/墓碑另有覆盖层，衔接层必须让位。★ 用 === '' 读法，勿改成 !== ''
  // ——266/512 组按 blockedNotice !== '' 的首现位切片，改写法会挪动锚串
  private handoffVisible(): boolean {
    return this.dataSource.launchHandoff && this.errorText === '' &&
      this.dataSource.blockedNotice === '' && !this.contentRevealed();
  }

  build() {
    // 无分支命中时本 Stack 零尺寸零命中（ChatLoadingOverlay 同款）；三分支互斥——
    // 加载中（三支皆不命中）不画覆盖层。★ 启动衔接层在场时本 Stack 为全尺寸但仍零命中
    // （其 Column 挂 HitTestMode.None），且 DB 等待窗有意露出启动页图标——2026-11-24
    // 衔接笔的既有目标，不是「纯背景」回归
    Stack() {
      // 启动衔接层（2026-11-24 启动页衔接笔）：冷启动落点会话页首帧即画与系统启动页同图、
      // 同尺寸、同中心的图标——系统启动页在应用首帧后 200ms 透明渐隐（官方《应用启动页
      // 简介》），本层与其完全重合即无空白/无跳变；内容结论到达后与消息区渐显同拍 300ms
      // 淡出。层位 = Stack 首子节点（最底层）：错误/墓碑/空态文字永不被本层遮挡；空会话时
      // 本层图标与空态图标同位同图（空态分支在上），淡出不可见。syncLoad = 官方「加载图片
      // 出现闪烁时设 true」（本地小图适用）——图标必须进首帧，不能等异步解码空一两帧。
      // hitTest 关 = 全屏装饰层不挡列表手势（ChatLoadingOverlay 同款）
      if (this.dataSource.launchHandoff) {
        Column() {
          Image($r('app.media.startIcon'))
            .width(this.startIconSize())
            .height(this.startIconSize())
            .syncLoad(true)
            .opacity(this.handoffVisible() ? 1 : 0)
            .animation({ duration: 300, curve: Curve.EaseOut })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      if (this.errorText !== '' && this.dataSource.messageCount === 0) {
        // 初始加载失败：中文提示 + 重试（P0-1）
        Scroll() {
          Column({ space: 12 }) {
            Text(this.errorText)
              .fontSize(13)
              .fontColor(cardDescColor())
            Button('重试')
              .fontSize(14)
              .onClick(() => {
                this.onRetry();
              })
          }
          .width('100%')
          .height('calc(100% + ' + this.topPad + 'vp)')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: this.topPad })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      } else if (this.dataSource.messageCount === 0 && this.dataSource.historyLoaded &&
        this.dataSource.blockedNotice !== '') {
        // 旧格式墓碑覆盖层：非 graph 会话（旧格式 / 历史迁移残值 / graph 空分支坏库态）无可
        // 读路径——数据仍在 messages 表，静默落通用空态 = 观感数据丢失，本层显式呈报；
        // **无重试键**（迁移机制退役后重试不会改变结果，给键即欺骗——唯一出口 = 会话列表
        // 长按删除，句内已写明）。互斥推演：错误态命中时加载链置空 blockedNotice；本分支
        // historyLoaded 为 true，通用空态被 blockedNotice !== '' 挡下。文案单源 =
        // ChatBranchPolicy.TOMBSTONE_NOTICE_TEXT
        Scroll() {
          Column({ space: 12 }) {
            Text(this.dataSource.blockedNotice)
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .height('calc(100% + ' + this.topPad + 'vp)')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: this.topPad })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        // 滚动容器滚动条统一隐藏（宪法条全站口径；2026-11-18 S2 微笔存量漏网收口——与本件
        // 错误态/空态两分支既有 Off 同位补齐，三支一致）
        .scrollBar(BarState.Off)
      } else if (this.dataSource.messageCount === 0 &&
        (this.dataSource.historyLoaded || this.dataSource.freshEntry)) {
        // 空态（新对话 / 空历史会话）：应用图标 + 引导语（2026-11-18 决明拍板：原居中的
        // 应用名「AI 控制台」撤除，欢迎语上移到原应用名位置、沿用其 15fp 样式）。
        // ★ 2026-11-24 与启动页对齐：图标尺寸 = 启动页同源 startIcon 的 256 物理像素（px2vp
        // 换算），并用同文案隐形占位把图标中心顶到视口中心——启动页→空态图标位置零跳变。
        // historyLoaded 判定——进页
        // 加载中（历史查询在途）显示纯背景，确认空会话（loadHistory 成功回放，含空表）才
        // 显示引导层，转场动画中不闪现「开始新的对话」。判定经 @ObjectLink 订阅 @Track 链路
        // 与 messageCount 同通道（禁 @Prop——坑16 家族）
        // ★ 2026-11-18 乐观空态笔：freshEntry 为真时不等读库回执直接成立——本地新造 id
        // = 必然空，「空」是终态不是猜测；读库回执到达后 historyLoaded 同样为真，判据无
        // 跳变。墓碑分支不加此位（fresh 下 blockedNotice 恒空，两分支互斥不变）
        Scroll() {
          Column({ space: 12 }) {
            // 隐形对称占位（与下方引导语同文案同字号）：整组内容 = 占位 + 图标 + 引导语，
            // 图标中心恰落在整组中心 = 视口中心（与启动页图标中心重合）；系统字号放大时
            // 占位与引导语同步长高，无需测量文字高度。Visibility.Hidden 官方语义 = 隐藏但
            // 参与布局占位（RowSwipeDelete 同款先例）
            Text(EMPTY_HINT_TEXT)
              .fontSize(15)
              .visibility(Visibility.Hidden)
            // 尺寸与启动页图标同物理像素；资源自带 22.5% 圆角裁切（startSvg rx=0.225），
            // 启动页直绘原图，本处保持同形不另加裁剪；syncLoad = 本图首现即进帧（非启动
            // 落点进空会话时无衔接层兜底，异步解码会空一两帧）
            Image($r('app.media.startIcon'))
              .width(this.startIconSize())
              .height(this.startIconSize())
              .syncLoad(true)
            Text(EMPTY_HINT_TEXT)
              .fontSize(15)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .height('calc(100% + ' + this.topPad + 'vp)')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: this.topPad })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
    }
  }
}
