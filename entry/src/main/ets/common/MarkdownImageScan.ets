// Markdown 图链扫描器：从消息文本提取可下载的 Markdown 图片链接——纯提取器，不改写文本
//（拍板 8：转图后原文全程保留，本件不产出任何改写串）。
// 蓝本 = Kelivo parseTextAndImages（只读参考，勿照搬架构）。三点差异：
// ①只收 http:// / https:// 图链（拍板 2——本地路径与 data: 前缀不收；它两者都收）；
// ②上限 TEXT_IMAGE_MAX_COUNT 截断（拍板 7，它无上限）；
// ③只收集链接、不产出改写文本（它要产出剥离/保留后的文本串——我们只取 url 清单）。
// 实现形态 = 单遍状态机（逐字符推进）：跳过围栏代码块（行首起 ``` 或 ~~~ 到对应闭合；
// 未闭合则其后全部跳过）与行内反引号串（开栏 k 连须同数闭合，未闭合其后全部跳过）；
// 候选提取为局部扫描（只在 `![` 在场才走、失败只前进一格）——全程无「对剩余后缀整体
// indexOf」的 O(n²) 形态（Kelivo 源注释明确警告项，勿回填）。
// url 口径：取第一个 `)` 前的非空子串，trim 后判前缀（同 Kelivo 限制，url 含 `)` 的
// 罕见形态不追求）；结果按出现顺序去重（同 url 只留一次）。
// 零 import（纯函数件——node 直跑断言不加剥壳，镜像机制见 assert-attach-domain 新组）。

// 一条消息最多转换的图链数（拍板 7；超过取前 N 个，余下静默留作文本发送）。单一来源
// 在本件——TextImageFetch 不重复截断，改上限只改这里
export const TEXT_IMAGE_MAX_COUNT: number = 8;

// 候选解析产物（模块内形态，不导出）：url = 第一个 `)` 前的子串；end = 形态结束位
//（exclusive——主循环从这里继续，整段消费防 url 内子串再触发候选）
interface ImageUrlMatch {
  url: string;
  end: number;
}

// 自 start 起（start 处恰为 `![`）解析 `![alt](url)` 形态；任一结构不符回 null：
// alt = 两个 `]` 之间的任意串（同正则 `[^\]]*`，可含换行）；`]` 后必须紧跟 `(`；
// url = `(` 后到第一个 `)` 的子串（同正则 `[^)]+`）。局部线性扫描，无回溯
function tryParseImageUrlAt(text: string, start: number): ImageUrlMatch | null {
  let j: number = start + 2;
  let closeBracket: number = -1;
  while (j < text.length) {
    if (text.charAt(j) === ']') {
      closeBracket = j;
      break;
    }
    j++;
  }
  if (closeBracket < 0 || closeBracket + 1 >= text.length ||
    text.charAt(closeBracket + 1) !== '(') {
    return null;
  }
  let k: number = closeBracket + 2;
  while (k < text.length) {
    if (text.charAt(k) === ')') {
      return { url: text.substring(closeBracket + 2, k), end: k + 1 };
    }
    k++;
  }
  return null;
}

// 扫描主入口：返回文本内全部可下载图链 url（http/https、按出现顺序去重、上限截断）。
// 纯函数、零副作用、恒终止（单遍推进，内层扫描只消费不改 i 的既有进度）
export function scanMarkdownImageUrls(text: string): string[] {
  const urls: string[] = [];
  const seen = new Set<string>();
  const n: number = text.length;
  let i: number = 0;
  while (i < n) {
    const ch: string = text.charAt(i);
    // ── 围栏代码块：行首起 ``` 或 ~~~（Kelivo 同款判据 i==0 或前一字符换行）──
    if ((ch === '`' || ch === '~') && (i === 0 || text.charAt(i - 1) === '\n') &&
      i + 2 < n && text.charAt(i + 1) === ch && text.charAt(i + 2) === ch) {
      i += 3;
      // 找同字符三连闭合；未闭合则内层走到底 = 其后全部跳过（拍板形态）
      while (i < n) {
        if (text.charAt(i) === ch && i + 2 < n &&
          text.charAt(i + 1) === ch && text.charAt(i + 2) === ch) {
          i += 3;
          break;
        }
        i++;
      }
      continue;
    }
    // ── 行内代码：反引号串，开栏 k 连须同数闭合（CommonMark 口径同 Kelivo 简化）──
    if (ch === '`') {
      let open: number = 0;
      while (i + open < n && text.charAt(i + open) === '`') {
        open++;
      }
      i += open;
      // 找 k 连反引号闭合；未闭合则其后全部跳过
      while (i < n) {
        if (text.charAt(i) === '`') {
          let close: number = 0;
          while (i + close < n && text.charAt(i + close) === '`') {
            close++;
          }
          i += close;
          if (close === open) {
            break;
          }
          continue;
        }
        i++;
      }
      continue;
    }
    // ── 图链候选（只在 `![` 在场才走局部扫描）──
    if (ch === '!' && i + 1 < n && text.charAt(i + 1) === '[') {
      const match: ImageUrlMatch | null = tryParseImageUrlAt(text, i);
      if (match !== null) {
        const trimmed: string = match.url.trim();
        if ((trimmed.startsWith('http://') || trimmed.startsWith('https://')) &&
          !seen.has(trimmed)) {
          seen.add(trimmed);
          urls.push(trimmed);
          if (urls.length >= TEXT_IMAGE_MAX_COUNT) {
            return urls; // 上限截断（拍板 7）：取前 N 个，余下不再扫
          }
        }
        i = match.end; // 整段消费（含不合前缀的形态——防 url 内子串再触发候选）
        continue;
      }
    }
    i++;
  }
  return urls;
}
