// 文本图链下载与转换编排：把消息文本里的 Markdown 图链下载、压缩、编码成本轮可发送的图片
// 部件（AiImagePart[]），与手动附件走完全同一条 images 通道（协议侧四方言翻译零改动）。
// 归属调用方 = ChatSendCtrl.send 链（与 buildAttachmentPayload 并行，产物并入 payload.images）。
// 与 Kelivo 的差异：它对远程 URL 先 HEAD 探测后直传 URL（模型侧自取）+ 扫全历史——我们的
// images 通道只收 base64 必须下载，且只扫本轮新发消息（拍板 1）。
// 全静默契约（拍板 3/4）：恒 resolve 内部全捕获永不 throw——开关关 / 无视觉模型 / 文本无
// 图链候选 / 任一链失败（超时、非 2xx、解码失败、超 20MB、总预算耗尽）一律跳过该链，
// 无 toast 不中断不重试，该链接留作文本照常发送。
// 下载红线：走应用域直连族 http.createHttp()（TitleApi / ModelListApi / BalanceApi 先例），
// 不 import ToolHttp / HttpFlow / EndpointPolicy 任何一件——HTTP 工具域的白名单与落盘是
//「模型发起请求」的护栏；本功能是用户贴链的用户意图行为，与浏览器点链同质。不落盘：下载
// 字节全程内存（decodeScaled 吃 ArrayBuffer），图只存在于本轮请求。全局网络口径（UA / 代理）
// 与请求日志（ReqLog）照 TitleApi 同款接入。
// 上限 8 的截断在扫描阶段完成（TEXT_IMAGE_MAX_COUNT 单一来源在 MarkdownImageScan），
// 本件不重复截断。

import { http } from '@kit.NetworkKit';
import { AiImagePart } from './providers/AiTypes';
import { applyDefaultUserAgent, applyEffectiveProxy } from './providers/RequestIdentity';
import { REQ_LOG_SOURCE_TEXT_IMAGE, reqLogBegin, reqLogEnd } from './ReqLog';
import { encodeImageBuffer } from './AttachmentUtil';
import { scanMarkdownImageUrls } from './MarkdownImageScan';
import { isTextImageFetchEnabled } from './AppPreferences';

// 同时下载的图链数（拍板 7）
export const TEXT_IMAGE_CONCURRENCY: number = 3;
// 单链下载超时（连接与读取各一份，毫秒；拍板 7）
export const TEXT_IMAGE_TIMEOUT_MS: number = 15000;
// 整条消息的下载总预算（毫秒；拍板 7——最坏情形 = 点发送后约 30 秒才开始收到模型回复）
export const TEXT_IMAGE_TOTAL_BUDGET_MS: number = 30000;
// 单张下载字节上限（拍板 7；与 HTTP 工具域 maxLimit 同值但语义独立、互不引读——勿跨域复用）
export const TEXT_IMAGE_MAX_BYTES: number = 20 * 1024 * 1024;

// 编排主入口：三闸早退 → 扫描 → 分批并发下载编码 → 图片部件数组。恒 resolve（内部
// 全捕获），数组可能为空（全失败 / 全被闸拦）——调用方按 length 判并入，无需降级分支。
// ★ 主流程整体包裹一层防线：downloadImagePart 的 try 边界只盖请求与编码，
// http.createHttp / UA·代理应用 / 批编排都在各链 try 之外——这些点漏网异常会沿
// Promise.all 整体 reject 穿出本函数，而调用方 send 链的 Promise.all 无 .catch 兜底 =
// run 占用悬挂 + 发送静默断裂，违本件恒 resolve 契约。故漏网异常一律按全失败静默返回
// 已收集部分（ReqLog 各链收尾在自身路径已兜，无需在此补记）
export async function fetchTextImages(text: string, hasVision: boolean): Promise<AiImagePart[]> {
  const parts: AiImagePart[] = [];
  try {
    // 闸①（拍板 5）：开关关 = 功能整体旁路，现读一次（发送时刻值）
    if (!isTextImageFetchEnabled()) {
      return parts;
    }
    // 闸②（拍板 3）：无视觉模型静默按纯文本发送，不弹确认框不报错
    if (!hasVision) {
      return parts;
    }
    // 闸③（零成本快判，照 Kelivo）：文本里连 `![` 与 `](` 都没有就不进扫描
    if (text.indexOf('![') < 0 || text.indexOf('](') < 0) {
      return parts;
    }
    const urls: string[] = scanMarkdownImageUrls(text);
    if (urls.length === 0) {
      return parts;
    }
    const start: number = Date.now();
    // 分批 3 个一组并发（拍板 7），批间检查总预算——耗尽即停，剩余链全部静默跳过
    for (let head: number = 0; head < urls.length; head += TEXT_IMAGE_CONCURRENCY) {
      if (Date.now() - start > TEXT_IMAGE_TOTAL_BUDGET_MS) {
        break;
      }
      const batch: string[] = urls.slice(head, head + TEXT_IMAGE_CONCURRENCY);
      const settled: (AiImagePart | null)[] =
        await Promise.all(batch.map((u: string): Promise<AiImagePart | null> =>
          downloadImagePart(u)));
      for (const part of settled) {
        if (part !== null) {
          parts.push(part);
        }
      }
    }
  } catch (e) {
    // 恒 resolve 最后防线：异常已按全失败静默（不留 toast 不中断——拍板 4），落已收集部分
  }
  return parts;
}

// 单链下载与编码：2xx 且结果为 ArrayBuffer 才继续编码；其余（3xx 落空、4xx/5xx、网络
// 错误、超时、解码失败）一律回 null = 该链静默跳过（不留痕迹、不重试——拍板 4）。
// 不做 HEAD 预探测（下载即探测）、不看 Content-Type——内容校验由解码承担（非图字节在
// decodeScaled 失败即弃，比 Kelivo 严一档）
async function downloadImagePart(url: string): Promise<AiImagePart | null> {
  // mime 判定的名字提示 = url path 末段文件名（无则空串经 imageOutMime 兜底）
  const noQuery: string = url.split('?')[0].split('#')[0];
  const lastSlash: number = noQuery.lastIndexOf('/');
  const nameHint: string = lastSlash >= 0 ? noQuery.substring(lastSlash + 1) : '';
  const request: http.HttpRequest = http.createHttp();
  // UA 兜底先于 options、代理兜底后置（照 TitleApi 顺序——用户设的 UA / 代理对图链下载
  // 同样生效）
  const header: Record<string, string> = {};
  applyDefaultUserAgent(header);
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: header,
    usingCache: false,
    expectDataType: http.HttpDataType.ARRAY_BUFFER,
    maxLimit: TEXT_IMAGE_MAX_BYTES,
    connectTimeout: TEXT_IMAGE_TIMEOUT_MS,
    readTimeout: TEXT_IMAGE_TIMEOUT_MS
  };
  applyEffectiveProxy(options);
  const startedAt: number = Date.now();
  const logId: string = reqLogBegin({
    source: REQ_LOG_SOURCE_TEXT_IMAGE, model: '', method: 'GET', url: url, headers: header,
    body: ''
  });
  try {
    const resp: http.HttpResponse = await request.request(url, options);
    if (resp.responseCode < 200 || resp.responseCode > 299 ||
      !(resp.result instanceof ArrayBuffer)) {
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '图链下载未返回图片数据', '');
      return null;
    }
    const part: AiImagePart = await encodeImageBuffer(resp.result as ArrayBuffer, nameHint);
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '', '');
    return part;
  } catch (e) {
    // 网络错误 / 超时 / maxLimit 超限 / 编码失败——全部走此跳过该链（任何路径都 reqLogEnd，
    // 照 TitleApi 五路共用 finish 的教训，日志不悬「进行中」）
    reqLogEnd(logId, -1, Date.now() - startedAt, '图链下载失败：' + (e as Error).message, '');
    return null;
  } finally {
    request.destroy();
  }
}
