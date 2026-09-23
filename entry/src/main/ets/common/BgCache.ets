// 背景图解码缓存（2026-08-21 新增，修复二级页转场闪白——坑36）：
// 根因：二级页/三级页各自 PageBackground 的 Image 首次挂载时**异步**加载壁纸，官方系统级
// push 转场（右侧滑入）期间露出浅色兜底（page_bg 浅色 #F1F3F5 近白），加载完成后才变
// 深色壁纸 → 转场滑入瞬间「闪白」（决明真机反馈；非反色/叠层问题，纯加载时序）。
// 方案：应用内唯一背景位图缓存（单张 PixelMap，限尺寸解码，decodeScaled 复用）——
// 一级页显示时即解码缓存，二级/三级页 PageBackground 挂载时同步命中即显示（零加载延迟），
// 全部页面共享同一份解码结果（内存 1 份，不再每页各自解码）。
// 生命周期（成对释放）：换图成功时「先建新后释旧」——旧图移入 prevPm 延迟释放
// （页面 @State 引用切换发生在 resolve 后，立即释放有 Use-After-Release 风险——
// 延迟到下次换图时释放，此时页面早已完成切换，安全窗口充足）；恢复默认时调用方
// （PageBackground.load）先同步置空显示引用再清空缓存，可立即释放。
// 缓存键 = 沙箱纯路径（唯一名方案下路径唯一，与 URI 等价；decodeScaled 只认纯路径——坑31，
// file:// URI 剥前缀是非法相对路径，须由调用方用 bgFileNameFromUri + filesDir 拼出）。
import { display } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { decodeScaled } from './ImageEditUtil';

let cachedPm: image.PixelMap | null = null; // 当前图（页面引用）
let cachedPath: string = '';
let prevPm: image.PixelMap | null = null; // 上一张（延迟释放，见文件头注释）
let inflight: Promise<image.PixelMap | null> | null = null; // 解码进行中（同 path 复用）
let inflightPath: string = '';

// 同步取缓存（命中返回；未命中/无缓存返回 null——调用方此时应异步 ensure）
export function getBgPixelMap(path: string): image.PixelMap | null {
  if (path.length === 0) {
    return null;
  }
  if (cachedPath === path) {
    return cachedPm;
  }
  return null;
}

// 换图窗口旧图（prevPm，延迟释放中）：新图解码未就绪时显示它兜底——新页面实例首帧/
// 转场不露纯色闪白（旧图 → 新图，无纯色间隙；2026-08-21 转场闪白残量修复）。
// 仅换图后短暂存在（下次换图时 release），返回的引用与页面 bgPm 生命周期匹配
// （页面切新图后才轮到它被释放，见 ensure 收编逻辑）
export function getFallbackBgPixelMap(): image.PixelMap | null {
  return prevPm;
}

// 确保缓存就绪：同 path 进行中复用同一 promise（防重复解码）；path 变化时解码新图、
// 成功后收编新 + 旧图移入 prevPm（延迟释放）。path 空 = 清空（调用方已先切显示引用，
// 立即释放安全；旧图同样移入 prevPm 防「调用方切引用前仍有渲染帧」的极端窗口）。
// 已知有界滞留（2026-08-22 审查登记）：恢复默认后旧图滞留 prevPm，仅下次换图成功才
// 释放——至多 1 张全屏位图、非泄漏；不主动释放是因存活页面可能仍引用它（安全优先）。
export function ensureBgPixelMap(path: string): Promise<image.PixelMap | null> {
  if (path.length === 0) {
    if (cachedPm !== null) {
      if (prevPm !== null) {
        prevPm.release();
      }
      prevPm = cachedPm;
      cachedPm = null;
      cachedPath = '';
    }
    // 2026-08-22 审查补：清空时作废在途解码——不清则在途 promise 完成仍会收编回缓存
    // （「恢复默认」后旧壁纸回灌，见下方收编条件 inflight === p）
    inflight = null;
    inflightPath = '';
    return Promise.resolve(null);
  }
  const hit = getBgPixelMap(path);
  if (hit !== null) {
    return Promise.resolve(hit);
  }
  if (inflight !== null && inflightPath === path) {
    return inflight;
  }
  // 坑37 兼容：2026-08-21 新名方案初期 filesDir 拼接缺 '/'，文件写在 filesDir 同级、
  // 文件名成了 filespage_background_*（pageBg 持久化的 URI 可能仍指向它们）——正确路径
  // 不存在时回退探测「去掉最后一个 '/'」的旧位置（仅此一次探测，换图后自然失效）
  let decodePath: string = path;
  if (!fs.accessSync(path)) {
    const idx: number = path.lastIndexOf('/');
    const fallback: string = idx > 0 ? path.substring(0, idx) + path.substring(idx + 1) : '';
    if (fallback.length > 0 && fallback !== path && fs.accessSync(fallback)) {
      decodePath = fallback;
    }
  }
  const p: Promise<image.PixelMap | null> = decodeScaled(decodePath, display.getDefaultDisplaySync().width)
    .then((pm: image.PixelMap) => {
      // 仅当期间没有被更新的 ensure 覆盖（inflight 已换）才收编；否则本实例直接释放
      if (inflight === p && inflightPath === path) {
        if (prevPm !== null) {
          prevPm.release();
        }
        prevPm = cachedPm;
        cachedPm = pm;
        cachedPath = path;
        return pm;
      }
      pm.release();
      return null;
    })
    .catch((e: Error) => {
      // 解码失败（文件缺失/损坏等）：仅日志，显示走兜底纯色（不静默失败）
      console.error('bg pixel map decode failed: ' + JSON.stringify(e));
      return null;
    })
    .finally(() => {
      if (inflight === p) {
        inflight = null;
        inflightPath = '';
      }
    });
  inflight = p;
  inflightPath = path;
  return p;
}
