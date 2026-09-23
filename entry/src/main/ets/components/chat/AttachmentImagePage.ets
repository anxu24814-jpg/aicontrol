// 查看器单页可缩放图片（2026-09-15 预览升级笔新建域件，任务书-附件预览升级 §2.3/§2.7）：
// 查看器 Swiper 的页件——单图渲染 + 变换应用 + 共享元素绑定 + 手势上报。
// 为何不能并入 AttachmentViewer（反碎片下限②书面理由）：①独立职责（单图渲染与变换应用）
// 一句话可说清；②被 Swiper 多页复用；③并入将使查看器壳（壳层手势 + 下滑关闭 + 文本模式 +
// 顶部行 + 状态栏避让）越 800 软引导线（书 §2.7 同款论证）。
// 分工：缩放态单份在壳层（切页即复位——微信口径，免每页独立态与管理成本），本件按
// 「当前页」应用变换（scale/translate），非当前页恒 1x/零偏移；手势在本件识别（官方
// 《图片预览器》最佳实践：手势绑页件——单指唯一入口，挂壳层会被 Swiper 内建 pan 抢占）
// 终值全部由壳层计算（本件零缩放逻辑，只上报事件）。
// 手势组形（官方 FAQ faqs-arkui-306 定形）：互斥组内**双击在前、单击在后**——单击在前
// 则双击永不识别；双击 = 放大/还原，单击 = 关闭。
// 共享元素（官方模态组合示例）：模态侧 Image 绑 .geometryTransition(id)（不带 follow），
// 配 .transition(opacity 0.99)——官方约束「参与转场的组件须设 transition 保证离场不析构」；
// id 判据三处同源 sharedGeomId（广播键，见 AttachmentUtil 常量注释）。
// 红线：Image 沙箱图必经 fileUri.getUriFromPath 转 URI（官方 FAQ faqs-arkui-154）+
// sourceSize 按屏幕尺寸给解码目标（禁原图整幅入内存）——两红线沿第三轮查看器不改。
// ★ 2026-09-15 锚点与边界修复笔（决明报障「双指放大不以双指锚点为中心、统一以左上角为
// 锚点」）：①捏合中点改取 pinchCenterX/Y 原值——官方 d.ts 实锤「in vp, relative to the
// original area of the current component」，原实现取 fingerList.globalDisplayX/Y 再 px2vp，
// 而该字段单位同为 vp，误转致锚点落在真实位置约 1/3 处（双指按哪都偏左上角）；②本件上报
// 图片实际显示尺寸（onComplete → 壳层平移边界基准——官方边界公式输入为图片显示尺寸）。
// ★ 2026-09-15 图片留白笔（决明「图片同文字默认不进入标题栏蒙层，放大后可进入，避免展示
// 不全」）：新增 topPad 形参（壳层下发）+ 根容器 `.padding({ top: this.topPad })`——1x 时
// 图片整体落在官方标题栏下方；放大后越出该区的部分照常渲染（官方 clip 默认 false），上缘可
// 进入蒙层。形参只增不改（既有形参语义零动，旧调用点不传 = 0 全出血）。
import { fileUri } from '@kit.CoreFileKit';
import { AttachmentBrief, ATTACH_SHARED_ID_KEY, sharedGeomId } from '../../common/AttachmentUtil';

// 单指手势 distance 两档：放大态小值抢占（拖图跟手，官方最佳实践 3）；未放大态起跟距离
// 10（书内自定——方向已限定竖直，此处只做触摸噪声门，官方 50 是「方向全向时让 Swiper 优先
// 接管水平滑」的口径，方向分档后 50 死区观感差〔起跟前 50vp 空拖〕，真机调参项）
const PAN_DIST_ZOOMED: number = 3;
const PAN_DIST_FREE: number = 10;

@Component
export struct AttachmentImagePage {
  // 本页附件简报（构造期定，普通成员）
  brief: AttachmentBrief = { id: '', name: '', kind: 'image', size: 0, absPath: '' };
  // 当前页标记（壳层 currentIndex 派发）：变换只应用于当前页；@Watch = 激活翻转补报图片
  // 显示尺寸（缓存页的 onComplete 早于激活——那时上报会被壳层按 id 丢弃）
  @Prop @Watch('onActiveChanged') active: boolean = false;
  // 壳层缩放态单份下发（@Prop 订阅式刷新；非当前页消费侧恒读 1/0/0）
  @Prop zoomScale: number = 1;
  @Prop zoomX: number = 0;
  @Prop zoomY: number = 0;
  // 图片解码目标（壳层 aboutToAppear 按屏算一次下发，普通成员）
  decodeW: number = 360;
  decodeH: number = 760;
  // 图片区顶部留白（壳层下发 = 状态栏 + MINI 标题栏 + 蒙层下延，与文本模式同源）：
  // 1x 时图片整体落在标题栏下方、不从渐变模糊蒙层下经过（决明「图片同文字默认不进入标题栏
  // 蒙层」）；放大后图片越出本区仍可渲染（见 build 内注释），上缘可进入蒙层——「避免展示
  // 不全」。★ 留白必须落在**本件根容器**（图片页）而不是 Swiper：Swiper 盒子缩进后会把放大
  // 后的越界部分裁在留白线下，那正是本条要避免的
  topPad: number = 0;
  // 手势回调上行（壳层统一计算终值——本件零缩放逻辑）
  onTap: () => void = () => {
  };
  onDoubleTap: () => void = () => {
  };
  onPinchStart: (centerXVp: number, centerYVp: number) => void =
    (_centerXVp: number, _centerYVp: number): void => {
    };
  onPinchUpdate: (ratio: number, offX: number, offY: number) => void =
    (_ratio: number, _offX: number, _offY: number): void => {
    };
  onPanStart: () => void = () => {
  };
  onPanUpdate: (offX: number, offY: number) => void =
    (_offX: number, _offY: number): void => {
    };
  onPanEnd: (offX: number, offY: number, velocityY: number) => void =
    (_offX: number, _offY: number, _velocityY: number): void => {
    };
  // 图片显示尺寸上报（壳层平移边界基准）：本页附件 id + 尺寸（vp）——当前页即时上报 +
  // 激活补报两路（壳层按 id 只采纳当前页，切页瞬间的迟到上报丢弃）
  onContentSize: (id: string, w: number, h: number) => void =
    (_id: string, _w: number, _h: number): void => {
    };
  // 共享元素广播键订阅（三处判据同源 sharedGeomId——气泡/输入栏/本件）
  @StorageProp(ATTACH_SHARED_ID_KEY) sharedId: string = '';
  // 图片实际显示尺寸（图片区内的绘制尺寸 vp；onComplete 实测回写，初值 0 = 尚未上报）
  private contentW: number = 0;
  private contentH: number = 0;

  // 未放大判定（缩放容差内视作 1x——手势方向/distance 分档与壳层 swipeLocked 同判据）
  private panFree(): boolean {
    return !this.active || this.zoomScale <= 1.0001;
  }

  // 激活补报（切页到本页时把已存尺寸交给壳层；未加载〔0〕不上报——壳层回退图片区尺寸兜底）
  private onActiveChanged(): void {
    if (this.active && this.contentW > 0) {
      this.onContentSize(this.brief.id, this.contentW, this.contentH);
    }
  }

  build() {
    Column() {
      Image(fileUri.getUriFromPath(this.brief.absPath))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .sourceSize({ width: this.decodeW, height: this.decodeH })
        // 实际绘制尺寸实测（壳层平移边界基准——官方《图片预览器》边界公式输入 = 图片显示
        // 尺寸而非组件尺寸）。loadingStatus===1（解码完成）该组字段才有效（官方 d.ts），
        // 单位 px 转 vp；未变则重复上报无副作用。形参用官方具名类型 ImageLoadResult
        //（字段与 Image.onComplete 内联类型一致；ArkTS 禁对象字面量作类型声明，
        // arkts-no-obj-literals-as-types 实测）
        .onComplete((event?: ImageLoadResult): void => {
          if (event === undefined || event.loadingStatus !== 1) {
            return;
          }
          this.contentW = this.getUIContext().px2vp(event.contentWidth);
          this.contentH = this.getUIContext().px2vp(event.contentHeight);
          if (this.active) {
            this.onContentSize(this.brief.id, this.contentW, this.contentH);
          }
        })
        // 变换只应用于当前页（非当前页恒 1x/零偏移——切页即复位的消费侧）
        .scale({
          x: this.active ? this.zoomScale : 1,
          y: this.active ? this.zoomScale : 1
        })
        .translate({
          x: this.active ? this.zoomX : 0,
          y: this.active ? this.zoomY : 0
        })
        // 共享元素模态侧（官方模态组合示例：模态侧不带 follow）
        .geometryTransition(sharedGeomId(this.brief.id, this.sharedId))
        // 官方约束：参与转场的组件须设 transition 防离场立即析构（opacity 0.99 同官方示例）
        .transition(TransitionEffect.opacity(0.99))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 图片区顶部留白（★ 2026-09-15 图片留白笔）：1x 时图片整体位于官方标题栏下方（不从渐变
    // 模糊蒙层下经过——「图片同文字」）；放大后 Image 的 scale/translate 越出本容器仍照常
    // 渲染（官方 clip 默认 false，本件与父级 Swiper 均不设裁剪），上缘可进入蒙层，即「放大后
    // 可进入，避免展示不全」。★ 手势坐标系不受影响：本容器（挂手势者）盒子仍是整页——留白是
    // 内部 padding，故 pinchCenterX/Y 与壳层 areaH 同坐标系，壳层锚点数学只需按 topPad 平移
    // 图片中心（见 AttachmentViewer.onPinchUpdate）
    .padding({ top: this.topPad })
    // 手势互斥组（FAQ 定形：双击在前单击在后；捏合/平移各按指数自然区分）
    .gesture(GestureGroup(GestureMode.Exclusive,
      PinchGesture({ fingers: 2, distance: 1 })
        .onActionStart((e: GestureEvent): void => {
          // 锚点 = 双指中点（pinchCenterX/Y：vp、相对本组件原始区域——官方 d.ts 实锤口径；
          // 组件即整页，语义与壳层页内坐标同源，壳层不再做任何换算）。★ 原取
          // fingerList 自算中点再 px2vp 的路径已删（该字段单位亦为 vp，误转偏左上；
          // 且 fingerList 有空槽——官方原文「未参与手势的手指对应位置为空」）
          this.onPinchStart(e.pinchCenterX, e.pinchCenterY);
        })
        .onActionUpdate((e: GestureEvent): void => {
          this.onPinchUpdate(e.scale, e.offsetX, e.offsetY);
        }),
      TapGesture({ count: 2 })
        .onAction((): void => {
          this.onDoubleTap();
        }),
      TapGesture({ count: 1 })
        .onAction((): void => {
          this.onTap();
        }),
      PanGesture({
        fingers: 1,
        direction: this.panFree() ? PanDirection.Vertical : PanDirection.All,
        distance: this.panFree() ? PAN_DIST_FREE : PAN_DIST_ZOOMED
      })
        .onActionStart((): void => {
          this.onPanStart();
        })
        .onActionUpdate((e: GestureEvent): void => {
          this.onPanUpdate(e.offsetX, e.offsetY);
        })
        .onActionEnd((e: GestureEvent): void => {
          this.onPanEnd(e.offsetX, e.offsetY, e.velocityY);
        })
    ))
  }
}
