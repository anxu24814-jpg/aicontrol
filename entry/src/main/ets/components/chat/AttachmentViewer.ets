// 附件查看器**内容主体**：图片 Swiper + 文本 Scroll；宿主 = components/chat/AttachmentViewerPage.ets
// 页面壳（导航栈内二级页，模态退役）——顶部归官方 HDS 标题栏（决明要的「顶部光感」）、关闭归
// 官方返回链、分享键归页面壳标题栏（链本体迁 common/AttachmentUtil.shareAttachment），本件只
// 管内容：顶部自绘行 / 下滑与单击关闭 / 底部工具栏均已退役，勿回加。
// ★ 图片留白口径（决明「图片同文字默认不进入标题栏蒙层，放大后可进入，避免展示不全」）：图片
// 模式不再全出血——页件根容器顶部让出 topPad，1x 时图片整体落在标题栏下方；放大后越出该区仍
// 照常渲染、上缘可进入蒙层。留白改变图片可用区高与中心位，缩放边界（maxPanY）与捏合锚点中心
// 两处数学已按 topPad 修正——漏改即锚点偏移回归（627 段修过的坑）。
// 形参契约：items/index/onClose 三件保留（附件管理列表笔复用本件——形参只增不改红线）；
// topPad（文本模式内容顶部留白）与 onPageChange（下标上行，页面据此刷官方标题与页码，广播键
// 写点仍单源在本件 onChange）为后补形参。
// 两模式：图片 = Swiper 左右滑切（页件 AttachmentImagePage——单图变换 + 手势上报，缩放态单份
// 在本壳层〔切页即复位，微信口径〕）+ 官方标题栏覆盖层页码 n/N（在页面壳）；文本 = Scroll +
// Text 纯文本原样（等宽 + 长按复制，.md 不渲染）。文档类不进本查看器（分派点直走 Preview Kit
// 系统预览窗，共享件 AttachmentUtil.openSystemPreview）。
// 红线：Image 沙箱图必经 fileUri.getUriFromPath 转 URI；图片解码下采样由页件 `autoResize(true)`
// 承接（按显示区尺寸且**保原比例**——原「每页 sourceSize 按屏幕尺寸给解码目标」在图片原比例
// ≠ 屏比例时整幅被拉伸，已退役；「禁原图整幅入内存」不变）；文本读取只在 aboutToAppear
//（build 内零 I/O）。
// 共享元素广播键：本件只在图片模式 Swiper.onChange 随页更新；清空在页面壳 aboutToDisappear
//（写点清单与守卫见 AttachmentUtil.ets 常量注释）。
// 两模式统一纸面（决明拍板「两模式都改浅色」——原图片模式黑底退役）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AttachmentBrief, AttachmentTextSlice, clipForTextViewer, readAttachmentText,
  TEXT_VIEW_MAX_CHARS, ATTACH_SHARED_ID_KEY
} from '../../common/AttachmentUtil';
import { cardBg } from '../../common/Theme';
import { AttachmentImagePage } from './AttachmentImagePage';

// 纯函数（断言直跑）——官方《图片预览器》边界公式：某 scale 下单轴 offset 允许范围 =
// 缩放后**图片显示尺寸**与**组件尺寸**之差的一半；图片显示尺寸不超组件则该轴锁定居中（0）。
// ★ 2026-09-15 锚点与边界修复笔：原双参（图片区尺寸当图片尺寸用两次）改三参——图片有黑边
//（图比例 ≠ 屏比例）时旧口径给的边界偏松，横图放大后能竖着拖出屏幕外；官方口径的输入是
// 图片实际显示尺寸（页件 onComplete 上报 imgW/imgH，未上报时回退图片区尺寸兜底）
export function zoomOffsetRange(picLen: number, pageLen: number, scale: number): number {
  const scaled: number = picLen * scale;
  return scaled > pageLen ? (scaled - pageLen) / 2 : 0;
}

// 纯函数（断言直跑）——捏合「锚点保持不动」的偏移解（官方《图片预览器》「缩放中心百分比」
// 公式的锚点化写法）：新偏移 = 起点偏移 × 有效倍率 + 指位移 + (锚点 − 组件中心) × (1 − 有效倍率)。
// 首项乘 eff 是锚定语义的一半：起点偏移是在旧倍率下量出的量，倍率一变它必须同比放大，否则
// 图片已平移（起点偏移 ≠ 0）时再捏合会整体滑走 起点偏移 × (1 − 有效倍率)。
// ★ 2026-09-15 自检轮修（原式内联分写两轴且首项未乘 eff / 几何核验：左缘锚放大、图心应右移）。
// 官方示例代码行 (1−scale) 与其散文「左缘锚放大则图心右移」互为反号，属文档笔误不采信。
export function pinchOffset(startOffset: number, fingerOff: number,
  anchor: number, center: number, eff: number): number {
  return startOffset * eff + fingerOff + (anchor - center) * (1 - eff);
}

// 文本截断提示行（与 TEXT_VIEW_MAX_CHARS 同值的中文表述——两处同改）
const TEXT_TRUNCATED_HINT: string = '文件较大，仅显示前 10 万字符';

// ── 缩放数学常量（版式笔的顶部行/下滑关闭/底栏常量均已随对应功能退役）──
// 缩放上下限与双击目标倍率（书内自定初值：1x~3x / 双击 2x——真机调）
const ZOOM_MAX: number = 3;
const ZOOM_DOUBLE_TAP: number = 2;
// 「已放大」判定的浮点容差（> 1 + 容差才算放大态——手势分档/滑切锁定/双击还原三处同源）
const ZOOM_EPSILON: number = 0.0001;
// 双击缩放的归位动画
const SETTLE_ANIM: number = 220;

@Component
export struct AttachmentViewer {
  // 查看集（图片模式 = 滑切集合；文本模式 = 单件）与起始下标——每次打开都是新实例，
  // 构造期一次性同步即可（无坑16 冻结面）；形参契约恒定（管理页复用，见头注释）
  items: AttachmentBrief[] = [];
  index: number = 0;
  // 内容顶部留白（页面壳下发；= 状态栏 + MINI 标题栏 + 蒙层下延）。★ 顶栏分享笔后**两模式
  // 共用**：文本走内容内层 padding（下述），图片下发页件（AttachmentImagePage.topPad——1x 时
  // 图片整体落在标题栏下方，放大后可越出该区进入蒙层）。图片仍不套「内容内层 padding」式的
  // 容器留白——留白必须落在页件根容器，Swiper 一旦缩进就会裁掉放大后的越界部分
  topPad: number = 0;
  // 关闭上行（页面壳实现 = pathStack.pop()）。★ 二级页化笔现状：本件内部**已无关闭触发点**
  //——返回归官方返回链（标题栏返回键 / 系统返回 / 侧滑三路由官方接手），单击关闭与下滑关闭
  // 已退役；本形参按任务书 §3 D8「三件契约保留不变」留位（两宿主复用红线：不重排/不删形参），
  // 将来件内若再现主动关闭动作（如工具栏新增「完成」类键）直接调本回调即可
  onClose: () => void = () => {
  };
  // 下标上行（页面壳据此刷官方标题栏标题与页码覆盖层——本件自绘顶部行随二级页化退役，
  // 标题与页码两处同源在页面）
  onPageChange: (index: number) => void = (_index: number): void => {
  };
  // 当前页码（Swiper.onChange 回写；内用 = 页件 active 派发与共享键随页，外用 = onPageChange
  // 上报——★ 顶栏分享笔后分享取件已不在本件，取件判据在页面壳）
  @State private currentIndex: number = 0;
  // 文本模式态（aboutToAppear 一次读盘；'' + fail = 读失败提示面）
  @State private textContent: string = '';
  @State private textFailed: boolean = false;
  // 截断标记（原文本超上限才算——恰等于上限的未截断文件不误报提示行）
  @State private textTruncated: boolean = false;
  // 深浅色（文本纸底取色；EntryAbility 写入 AppStorage）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // ── 缩放态单份（壳层持有；切页即复位——微信口径）──
  @State private zoomScale: number = 1;
  @State private zoomX: number = 0;
  @State private zoomY: number = 0;
  // ── 手势基准（普通成员——非 UI 驱动）──
  // 捏合：手势起点的缩放/偏移快照 + 锚点（双指中点的页内坐标，vp——页件直传，零换算）
  private pinchStartScale: number = 1;
  private pinchStartX: number = 0;
  private pinchStartY: number = 0;
  private anchorX: number = 0;
  private anchorY: number = 0;
  // 平移：手势起点的偏移快照
  private panStartX: number = 0;
  private panStartY: number = 0;
  // ── 图片区几何（onAreaChange 实测回写；边界分母/锚点中心的基准。普通成员——
  //    不直接驱动 UI（只喂手势数学），默认值仅首帧兜底）──
  private areaW: number = 360;
  private areaH: number = 760;
  // ── 图片实际显示尺寸（页件 onComplete 上报；0 = 未知，边界回退图片区尺寸兜底）──
  private imgW: number = 0;
  private imgH: number = 0;

  aboutToAppear(): void {
    this.currentIndex = this.index;
    if (this.items.length > 0 && this.items[0].kind !== 'image') {
      // 文本模式：一次性同步读，读取量有界在 TEXT_ATTACH_MAX_CHARS（AttachmentUtil
      // readAttachmentText 单源——与发送链、上下文面板活算同一实现）；下方
      // TEXT_VIEW_MAX_CHARS 是**显示裁剪**的另一层，两层独立
      try {
        const slice: AttachmentTextSlice = readAttachmentText(this.items[0].absPath);
        this.textTruncated = slice.text.length > TEXT_VIEW_MAX_CHARS;
        this.textContent = clipForTextViewer(slice.text);
        this.textFailed = false;
      } catch (e) {
        // 读失败 → 中文提示面 + hilog 留痕（P0-1 禁静默）
        this.textContent = '';
        this.textFailed = true;
        hilog.warn(0xD5A0, 'AttachViewer', '文本附件读取失败：%{public}s', (e as Error).message);
      }
    }
  }

  private isImageMode(): boolean {
    return this.items.length > 0 && this.items[0].kind === 'image';
  }

  // 图片实际可用区高（★ 2026-09-15 图片留白笔）：图片页根容器顶部让出 topPad，图片的布局区
  // = 页面高 − topPad（页件根容器 padding 内层）——平移边界分母/图片尺寸未知时的兜底都用它；
  // 非正时回 1 兜底（P0-1：空/负分母不得进除法与比较）
  private imageAreaH(): number {
    const v: number = this.areaH - this.topPad;
    return v > 0 ? v : 1;
  }

  // 图片中心在页件坐标系里的 Y（★ 图片留白笔）：页件根容器盒子仍是整页（留白是内层 padding），
  // 而图片居中于被留白压缩后的布局区 ⇒ 中心 = (topPad + areaH) / 2——捏合锚点「保持不动」的
  // 解含本项（pinchOffset 的 center 参），漏改即锚点纵向偏移 topPad/2（627 段锚点坑复发形态）
  private imageCenterY(): number {
    return (this.topPad + this.areaH) / 2;
  }

  // ── 缩放态判定与滑切锁定 ──
  private isZoomed(): boolean {
    return this.zoomScale > 1 + ZOOM_EPSILON;
  }

  // 边界取界（官方公式输入 = 图片实际显示尺寸 + 组件尺寸；图片尺寸未上报〔0〕时回退图片区
  // 尺寸兜底——未加载语义，与旧口径同值）。★ 图片留白笔：Y 轴分母改 imageAreaH（= 页面高 −
  // topPad，图片实际布局区）——仍用 areaH 会把纵向可平移范围压小 topPad/2，放大后图片边角
  // 到不了视口边（「展示不全」的另一面）；X 轴无留白、照旧用 areaW
  private maxPanX(scale: number): number {
    return zoomOffsetRange(this.imgW > 0 ? this.imgW : this.areaW, this.areaW, scale);
  }

  private maxPanY(scale: number): number {
    const areaH: number = this.imageAreaH();
    return zoomOffsetRange(this.imgH > 0 ? this.imgH : areaH, areaH, scale);
  }

  // 图片显示尺寸上报受理（只采纳当前页——切页瞬间的迟到上报丢弃，防拿错页尺寸算边界）
  private acceptContentSize(id: string, w: number, h: number): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.items.length ||
      this.items[this.currentIndex].id !== id) {
      return;
    }
    this.imgW = w;
    this.imgH = h;
  }

  // 已放大且贴 X 边界 → 放行滑切（官方最佳实践：贴边后水平滑动让 Swiper 切页）
  private atPanBoundaryX(): boolean {
    const maxX: number = this.maxPanX(this.zoomScale);
    return maxX <= 0 || Math.abs(this.zoomX) >= maxX - 0.5;
  }

  // Swiper 滑切锁定：放大态锁、贴 X 边界放行（判据单源）
  private swipeLocked(): boolean {
    return this.isZoomed() && !this.atPanBoundaryX();
  }

  // 缩放态复位（切页即复位——微信口径；静默赋值：页切换本身已由 Swiper 动画承接）。
  // 图片显示尺寸随页清空（新页激活补报再填——未知期边界回退图片区尺寸）
  private resetZoom(): void {
    this.zoomScale = 1;
    this.zoomX = 0;
    this.zoomY = 0;
    this.imgW = 0;
    this.imgH = 0;
  }

  // ── 手势回调（页件上行；终值全在本层算——单指唯一入口的收口点）──

  // 捏合起点：快照缩放/偏移 + 锚点（双指中点的页内坐标，vp——页件 pinchCenterX/Y 语义即
  // 「相对组件原始区域」，组件即整页，此处零换算。★ 原减图片区全局位的换算是屏幕坐标口径
  // 的残留，随单位修复一并退役：与 vp 原值混用会把锚点再偏一次）
  private onPinchStart(centerXVp: number, centerYVp: number): void {
    this.pinchStartScale = this.zoomScale;
    this.pinchStartX = this.zoomX;
    this.pinchStartY = this.zoomY;
    this.anchorX = centerXVp;
    this.anchorY = centerYVp;
  }

  // 捏合更新：缩放钳在 1x~3x；锚点保持不动（pinchOffset 纯函数——官方「缩放中心百分比」
  // 公式锚点化；★ 自检轮修：原式首项未乘 eff，图片已平移时再捏合整体滑走 基准×(1−eff)）；
  // 偏移实时钳边界（官方边界公式 zoomOffsetRange）。临时变量算完一次赋值（性能红线）。
  // ★ 图片留白笔：Y 轴中心改 imageCenterY（图片布局区被顶部留白压缩后中心下移 topPad/2，
  // 用 areaH/2 即漏掉这段，捏合锚点纵向跟着偏——公式的 center 参就是图片中心）
  private onPinchUpdate(ratio: number, offX: number, offY: number): void {
    const target: number = this.pinchStartScale * ratio;
    const nextScale: number = Math.min(Math.max(target, 1), ZOOM_MAX);
    const eff: number = this.pinchStartScale > 0 ? nextScale / this.pinchStartScale : 1;
    const maxX: number = this.maxPanX(nextScale);
    const maxY: number = this.maxPanY(nextScale);
    const rawX: number = pinchOffset(this.pinchStartX, offX, this.anchorX, this.areaW / 2, eff);
    const rawY: number = pinchOffset(this.pinchStartY, offY, this.anchorY, this.imageCenterY(), eff);
    this.zoomScale = nextScale;
    this.zoomX = Math.min(Math.max(rawX, -maxX), maxX);
    this.zoomY = Math.min(Math.max(rawY, -maxY), maxY);
  }

  // 平移起点：偏移快照（放大态平移到本层算终值）
  private onPanStart(): void {
    this.panStartX = this.zoomX;
    this.panStartY = this.zoomY;
  }

  // 平移更新：放大态 = 平移（官方公式 + 实时钳边界）；未放大态空转（页件手势方向已限定
  // 竖直，本层不消费 = 无副作用）
  private onPanUpdate(offX: number, offY: number): void {
    if (!this.isZoomed()) {
      return;
    }
    const maxX: number = this.maxPanX(this.zoomScale);
    const maxY: number = this.maxPanY(this.zoomScale);
    this.zoomX = Math.min(Math.max(this.panStartX + offX, -maxX), maxX);
    this.zoomY = Math.min(Math.max(this.panStartY + offY, -maxY), maxY);
  }

  // 双击：放大态还原 / 未放大放大到目标倍率（居中）
  private onDoubleTap(): void {
    const target: number = this.isZoomed() ? 1 : ZOOM_DOUBLE_TAP;
    this.getUIContext().animateTo({ duration: SETTLE_ANIM, curve: Curve.Friction }, (): void => {
      this.zoomScale = target;
      this.zoomX = 0;
      this.zoomY = 0;
    });
  }

  // ★ 二级页化笔：单击关闭（onTapClose）与下滑跟手淡出（dragFade）两方法与顶部行一并退役
  //——页面形态下关闭归官方返回链（标题栏返回键 / 系统返回 / 侧滑）；页件仍照旧上报单击与
  // 平移，本件对未放大态的单击/平移不再消费（页件只上报、不判断，故其全件零改动）

  build() {
    Column() {
      // ── 本 Column 只剩内容一件：顶部标题栏 / 底部工具栏均已退役，顶底归页面壳（见文件头）──
      if (this.isImageMode()) {
        // ── 图片模式：Swiper 滑切（loop 关 / indicator 自绘页码 / cachedCount 1），页件 =
        //    AttachmentImagePage（变换 + 手势）。滑切锁定 = 放大未贴 X 边界（官方 disableSwipe
        //    通道）；Swiper 自身仍自 y=0 起铺满（**禁给它挂留白**：盒子一缩，放大后的越界
        //    部分就被裁在留白线下）；顶部留白下发页件、落在图片页根容器内层——1x 图片落在
        //    标题栏下方，放大后可越出该区进入蒙层──
        Swiper() {
          ForEach(this.items, (brief: AttachmentBrief, i: number) => {
            AttachmentImagePage({
              brief: brief,
              active: i === this.currentIndex,
              zoomScale: this.zoomScale,
              zoomX: this.zoomX,
              zoomY: this.zoomY,
              topPad: this.topPad,
              onDoubleTap: (): void => {
                this.onDoubleTap();
              },
              onPinchStart: (centerXVp: number, centerYVp: number): void => {
                this.onPinchStart(centerXVp, centerYVp);
              },
              onPinchUpdate: (ratio: number, offX: number, offY: number): void => {
                this.onPinchUpdate(ratio, offX, offY);
              },
              onPanStart: (): void => {
                this.onPanStart();
              },
              onPanUpdate: (offX: number, offY: number): void => {
                this.onPanUpdate(offX, offY);
              },
              onContentSize: (id: string, w: number, h: number): void => {
                this.acceptContentSize(id, w, h);
              }
            })
          }, (brief: AttachmentBrief) => brief.id)
        }
        .index(this.index)
        .loop(false)
        .indicator(false)
        .cachedCount(1)
        .layoutWeight(1)
        .disableSwipe(this.swipeLocked())
        .onChange((i: number): void => {
          this.currentIndex = i;
          this.resetZoom();
          // 共享广播键随页更新（关闭返场目标 = 当前页缩略图；文本模式不进本分支）
          if (i >= 0 && i < this.items.length) {
            AppStorage.setOrCreate<string>(ATTACH_SHARED_ID_KEY, this.items[i].id);
          }
          this.onPageChange(i);
        })
        // 页面区几何实测（X 边界分母与两轴锚点中心的基准；Y 边界分母 = 本值 − topPad，
        // 见 imageAreaH；普通成员回写）
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.areaW = newArea.width as number;
          this.areaH = newArea.height as number;
        })
      } else {
        // ── 文本模式：浅色纸面（主题卡底 cardBg 深浅两态）+ Scroll + Text 纯文本原样 ──
        if (this.textFailed) {
          Column({ space: 12 }) {
            Text('文件读取失败，请重试')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Text(this.textContent)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .lineHeight(22)
                // 等宽观感：fontFamily 通用族名 'monospace'（官方文档未列系统等宽族名——
                // 不支持时静默回落默认字体无副作用，等宽观感成立与否为真机观察项）
                .fontFamily('monospace')
                // 长按复制（LogPageContent 先例——选择范围仅限本 Text）
                .copyOption(CopyOptions.LocalDevice)
                .width('100%')
                // 截断提示行（尾部，次要色区分正文）
                if (this.textTruncated) {
                  Text(TEXT_TRUNCATED_HINT)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .margin({ top: 12 })
                }
            }
            .alignItems(HorizontalAlign.Start)
            // 顶部留白走**内容内层** padding（topPad = 状态栏 + MINI 标题栏 + 蒙层下延）——
            // 滚动容器本身铺满整页（自 y=0 起），文字上滑时滑入标题栏蒙层透出（规范《行内
            // 按钮与光感》§5 硬规则 1：容器禁挂 topPad padding，留白只许在内容内层）
            .padding({ left: 16, right: 16, top: this.topPad, bottom: 24 })
          }
          .scrollBar(BarState.Off)
          // ★ Scroll 的 edgeEffect 官方默认 None（官方 d.ts 口径）——不写即无回弹；显式补
          // Spring + alwaysEnabled（短文本不足一屏同样可拖拽回弹——坑76，InfoPage 等正文页
          // 同款主导写法）
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.TopStart)
        }
      }

    }
    .width('100%')
    .height('100%')
    // 两模式统一纸面（决明拍板「两模式都改浅色」——原图片模式黑底退役）
    .backgroundColor(cardBg(this.appColorMode))
    // 根层无 .transition：入/离场归官方页面转场，飞行侧由参与转场的 Image 自持（官方约束
    // 「参与转场的组件须设 transition」在页件侧已满足）
  }
}
