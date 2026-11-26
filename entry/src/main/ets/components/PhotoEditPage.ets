// 「待发图片裁剪」二级页（拍照 / 相册选图后、进输入框之前）：单页裁剪，框比例跟随图片
// 且宽高各不超过屏幕 2/3，滑轨缩放 + 单指平移，确认后裁出框内区域另存 JPG 并把成品路径
// 经 pop result 交回 AttachmentPickCtrl 入列；返回键 = 放弃这张照片（不入列）；加载或裁剪
// 失败 = 中文提示后回传原图路径，按原图入列（零静默丢失）。
// 为何不能并入 ImageEditPage（反碎片下限②书面理由）：背景链是「裁剪 → 模糊/遮罩 → 写
// pageBg + 广播 + 弹回背景页」两阶段业务，本链是「裁剪 → 回传路径」单阶段，结果通道、
// 文件命名、定框比例、文案四处判据全不同；并入会把两套保存语义缠进一页。共用的只有图像
// 管线纯函数（ImageEditUtil）与裁剪阶段视图（CropStageView 经参数化复用），已在各自单源。
// 路由注册见 PageMapBuilder；★ 非设置项，不进 SettingSearch 注册表。
import { BusinessError } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { removeAttachFile, ATTACH_THUMB_EDGE_PX, PhotoEditOutcome } from '../common/AttachmentUtil';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';
import { BoxSize, cropPixelMap, decodeScaled, PHOTO_EDIT_MAX_EDGE_PX,
  photoBoxMetrics, saveJpg, visibleCropRegion } from '../common/ImageEditUtil';
import { PageShell } from '../common/PageShell';
import { ROUTE_PHOTO_EDIT_PAGE } from '../common/RouteNames';
import { CropStageView } from './CropStageView';
import { EditPlaceholder } from './EditPlaceholder';

// push 参数（ArkTS 显式接口）。pop 回执 = common 层 PhotoEditOutcome（path 三态 + 预解缩略图，
// 定义与成对释放约定见该接口注释；本页与附件控制器共用一份，禁在本页另立同名接口）
export interface PhotoEditParam {
  srcPath: string;
}

const PAGE_TITLE: string = '编辑照片';
const HINT_TEXT: string = '拖动移动图片，下方滑轨缩放。框内区域即为发送的图片';
const CONFIRM_LABEL: string = '使用这张';

@Component
export struct PhotoEditPage {
  // 顶部留白（PageMapBuilder 注入；HDS 路径内容区延伸到标题栏背后）
  topPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入，与根 Navigation 同一引用）：只用于读参与带 result 返回
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // 解码基准图（@State：异步解码完成赋值要触发渲染 + if 守卫创建裁剪视图）。生命周期内
  // 永不原地修改——保存时另解码一份执行 applyCropSync，往返裁剪幂等
  @State private origPixelMap: image.PixelMap | null = null;
  private srcPath: string = '';
  private cropBoxW: number = 0;
  private cropBoxH: number = 0;
  // 子组件上报镜像（普通成员：父不渲染这些值，仅「使用这张」映射裁剪区域时读取）
  private gmImgVpW: number = 0;
  private gmImgVpH: number = 0;
  private gmScale: number = 1;
  private gmTx: number = 0;
  private gmTy: number = 0;
  private disposed: boolean = false;
  private saving: boolean = false;

  aboutToAppear(): void {
    const params: Array<PhotoEditParam> =
      this.pathStack.getParamByName(ROUTE_PHOTO_EDIT_PAGE) as Array<PhotoEditParam>;
    const src: string = params.length > 0 ? params[params.length - 1].srcPath : '';
    if (src === '') {
      this.toast('缺少图片路径');
      this.finish('');
      return;
    }
    this.srcPath = src;
    // 解码窗口的占位框（2026-11-05 自检轮修）：真实框要等图片宽高出来才能定，此前 boxW/H
    // 还是 0——EditPlaceholder 会退化成「0×0 画布 + 一个悬在顶部的转圈」。先按正方形给出
    // 兜底框（photoBoxMetrics 对 1:1 的取值 = 屏宽 2/3 与内容池让位后的小者），解码完成再
    // 换成图片真实比例（该文件头「就绪后无跳位」的占位语义才有可能成立）
    const provisional: BoxSize = photoBoxMetrics(this.topPad, 1, 1);
    this.cropBoxW = provisional.w;
    this.cropBoxH = provisional.h;
    // 解码限最长边 2048（与发送链同规格，保原比例）；srcPath 恒为沙箱绝对路径，媒体库
    // 临时授权 URI 已由 AttachmentPickCtrl.enqueue 先 fd 级拷入沙箱，跨页无授权时效风险
    decodeScaled(src, PHOTO_EDIT_MAX_EDGE_PX, true)
      .then((pm: image.PixelMap): void => {
        // 迟到回调：页面已销毁则释放结果，不写 UI、不弹栈（组件异步链销毁守卫）
        if (this.disposed) {
          pm.release();
          return;
        }
        const info: image.ImageInfo = pm.getImageInfoSync();
        const box: BoxSize = photoBoxMetrics(this.topPad, info.size.width, info.size.height);
        this.cropBoxW = box.w;
        this.cropBoxH = box.h;
        this.origPixelMap = pm;
      })
      .catch((e: Object): void => {
        if (this.disposed) {
          return;
        }
        hilog.error(0xD5A0, 'PhotoEditPage', 'decode failed: %{public}s', (e as Error).message);
        this.toast('图片加载失败，将使用原图');
        this.finish(this.srcPath);
      });
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.origPixelMap !== null) {
      this.origPixelMap.release();
      this.origPixelMap = null;
    }
  }

  // 统一返回：pop 恒带 result（空串 = 放弃）。thumb = 保存后预解的缩略图（非空则入列侧免
  // 二次解码，见 PhotoEditOutcome 注释）；系统返回键由 PageShell.onBackPressed 拦截到本页，
  // 不触发无 result 的默认 pop——否则 ChatPage 的 onPop 回调读不到结果会悬挂 Promise
  private finish(resultPath: string, thumb: image.PixelMap | null = null): void {
    if (this.disposed) {
      // 页已销毁（迟到的保存回执）：预解图无人接管，当场释放防泄漏
      if (thumb !== null) {
        thumb.release();
      }
      return;
    }
    const result: PhotoEditOutcome = { path: resultPath, thumb: thumb };
    this.pathStack.pop(result);
  }

  // 「使用这张」：按当前手势镜像算裁剪 region → 另解码一份执行官方 applyCropSync → JPEG
  // q90 落盘 → 回传成品路径。原图 PixelMap 不动（往返幂等），输出实例 finally 成对释放。
  private async onUse(): Promise<void> {
    if (this.saving || this.origPixelMap === null || this.cropBoxW <= 0) {
      return;
    }
    this.saving = true;
    let out: image.PixelMap | null = null;
    let destPath: string = '';
    try {
      const region: image.Region = visibleCropRegion(this.origPixelMap, {
        imgVpW: this.gmImgVpW,
        imgVpH: this.gmImgVpH,
        scale: this.gmScale,
        tx: this.gmTx,
        ty: this.gmTy,
        boxW: this.cropBoxW,
        boxH: this.cropBoxH
      });
      destPath = this.nextDestPath();
      out = await decodeScaled(this.srcPath, PHOTO_EDIT_MAX_EDGE_PX, true);
      cropPixelMap(out, region);
      await saveJpg(out, destPath);
      // 缩略图在 pop 之前解好（规格与入列同尺，单源 ATTACH_THUMB_EDGE_PX）：旧链是入列侧
      // pop 之后再解，那次异步解码跨过返回转场的第一帧，输入栏胶囊在转场中一帧跳高 80vp
      //（真机实测入列晚于转场起点 24ms）= 观感「闪」。解不出不阻断——回执 thumb 置 null，
      // 入列侧按同一路径再解一次，那里的失败才是「图片不可解码」的判据
      let thumb: image.PixelMap | null = null;
      try {
        thumb = await decodeScaled(destPath, ATTACH_THUMB_EDGE_PX, true);
      } catch {
        thumb = null;
      }
      if (this.disposed) {
        // 页已销毁：成品与预解图都无人接管，当场回收（不弹栈，防误弹上级页）
        if (thumb !== null) {
          thumb.release();
        }
        removeAttachFile(destPath);
        return;
      }
      this.finish(destPath, thumb);
    } catch (e) {
      if (destPath !== '') {
        removeAttachFile(destPath); // 半截文件（删失败由离页整目录清扫兜底）
      }
      hilog.error(0xD5A0, 'PhotoEditPage', 'crop failed: %{public}s', String((e as BusinessError)?.message));
      if (this.disposed) {
        return;
      }
      this.toast('裁剪失败，将使用原图');
      this.finish(this.srcPath);
    } finally {
      if (out !== null) {
        out.release();
      }
      this.saving = false;
    }
  }

  // 成品落在与源图同一沙箱目录（filesDir/attachments）——入列后由附件清理链统一回收。
  // 唯一名 = 时间戳 + 随机四位，防同毫秒连续编辑覆盖，也防与原图同名被 TRUNC 截断
  private nextDestPath(): string {
    const slash: number = this.srcPath.lastIndexOf('/');
    if (slash <= 0) {
      throw new Error('图片路径无效');
    }
    return this.srcPath.substring(0, slash) + '/photo_edit_' + Date.now() + '_' +
      Math.floor(Math.random() * 10000) + '.jpg';
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: msg,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  @Builder
  StageContent() {
    if (this.origPixelMap !== null) {
      CropStageView({
        topPad: this.topPad,
        srcPixelMap: this.origPixelMap,
        cropBoxW: this.cropBoxW,
        cropBoxH: this.cropBoxH,
        // 待发图片恒「新图从 0 开始」，不恢复上次背景的缩放/平移三键
        initialScale: 0,
        initialTx: 0,
        initialTy: 0,
        hintText: HINT_TEXT,
        confirmLabel: CONFIRM_LABEL,
        onGeometryChange: (imgVpW: number, imgVpH: number, scale: number, tx: number, ty: number): void => {
          this.gmImgVpW = imgVpW;
          this.gmImgVpH = imgVpH;
          this.gmScale = scale;
          this.gmTx = tx;
          this.gmTy = ty;
        },
        onNext: (): void => {
          this.onUse();
        }
      })
    } else {
      EditPlaceholder({ topPad: this.topPad, boxW: this.cropBoxW, boxH: this.cropBoxH })
    }
  }

  build() {
    PageShell({
      title: PAGE_TITLE,
      // 纯色背景例外：裁剪预览框叠在自定义壁纸上会看不清（与背景编辑两页同款）
      bgSolid: true,
      onBackPressed: (): boolean => {
        this.finish('');
        return true;
      },
      content: (): void => {
        this.StageContent();
      }
    })
  }
}
