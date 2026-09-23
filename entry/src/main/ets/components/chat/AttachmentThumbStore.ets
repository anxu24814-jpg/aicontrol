// 附件缩略图内存仓库（2026-08-24 四十七改新增）：fileId → PixelMap 的模块级缓存。
// 为什么存在（缩略图空白根因，决明真机实锤）：@Prop 对对象/数组是**深拷贝**（官方状态
// 管理文档：@Prop 装饰变量为父组件数据源的本地深拷贝）——PixelMap 是原生资源包装对象，
// 经「KimiChatPage @State → ChatInputBar @Prop → AttachmentStrip @Prop」两级深拷贝后
// 像素数据丢失/断联 → Image 渲染空白。故 PixelMap 不走组件参数，存模块级仓库，组件渲染
// 时按 fileId 直取（附件数组变化驱动 @Prop 刷新，仓库读取总是当时值，无需 @State）。
// 寿命匹配（内存防线）：模块级（长寿命）只持 PixelMap 原生资源，不持组件/页面引用 ✓。
// 成对释放（内存防线）：putThumb 入仓 / removeThumb 释放（幂等，put 同 key 先释旧）；
// 释放通道 = AttachmentPickCtrl.cleanupAttachments（删单个/发送后/页面销毁三路径）。
// 上限 MAX_ATTACHMENTS 5 张 ×192px ≈ 750KB 有界。
import { image } from '@kit.ImageKit';

const thumbs: Map<string, image.PixelMap> = new Map();

// 入仓（解码成功后、附件入列前调——保证渲染触发时仓库已就绪；同 key 先释旧防重复占用）
export function putThumb(fileId: string, thumb: image.PixelMap): void {
  removeThumb(fileId);
  thumbs.set(fileId, thumb);
}

// 按 fileId 取缩略图（渲染期直读；无 = 降级图标卡）
export function getThumb(fileId: string): image.PixelMap | undefined {
  return thumbs.get(fileId);
}

// 删除单个附件的缩略图（release 为异步释放但无需等待——释放结果不影响后续流程，
// 浮动 Promise 与项目 sendPrompt 调用先例一致）；2026-08-31 附件接线后唯一释放通道
// = AttachmentPickCtrl.cleanupAttachments（删单个/发送后/页面销毁三路径都走它）
export function removeThumb(fileId: string): void {
  const pm: image.PixelMap | undefined = thumbs.get(fileId);
  if (pm !== undefined) {
    thumbs.delete(fileId);
    pm.release();
  }
}
