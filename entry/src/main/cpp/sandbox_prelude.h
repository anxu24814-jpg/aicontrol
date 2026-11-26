// 沙箱预置 JS 源码内嵌（2026-10-06 代码工作台笔A——二进制与基座，任务书 §3.4）。
// · 职责：纯 V8 缺失的少数 Web API 的预置实现（TextEncoder / TextDecoder / atob / btoa）
//   ——jsvm_runner.cpp 在宿主面安装与删 WebAssembly 之后、用户代码编译之前编译运行一次；
//   失败语义 = flags 'prelude-failed' + ok=false + 中文 errorMessage（不设 js-exception
//   标志、不回填异常三件——引擎侧缺陷不得误导模型怀疑脚本，§3.4-3）。
// · 语义边界（§3.4-6 定案，改语义 = 破坏性变更须重跑 V8 对拍）：TextEncoder 只提供
//   encode（无 encodeInto）；TextDecoder 只支持 utf-8 标签族（其它 RangeError）、
//   fatal / ignoreBOM 构造选项支持、decode 第二参 {stream:true} → TypeError；atob / btoa
//   照 Web 二进制字符串口径。幂等守卫：typeof X === 'undefined' 才定义。
// · 验证证据（写书笔实跑，§3.4-7）：与本机 Node（同 V8 系）全量对拍通过——编码 14 例
//   字节级一致；解码全 1/2 字节组合 + 定向 3/4 字节 + 随机 4~6 字节共 38 万余例逐串一致；
//   BOM / fatal / stream 三态一致；Base64 非法形态一致；node --check 通过。
// ★ 2026-10-06 代码工作台笔B——易用面（任务书 §3.3）：新增第二常量 SANDBOX_PRELUDE_TOOLS_JS
//   （通用小工具五枚——hexEncode / hexDecode / b64Encode / b64Decode / csvParse）；执行位
//   由 jsvm_runner.cpp 拼接 A + 换行 + B 一次编译一次运行（A → B 顺序）；失败语义沿用
//   'prelude-failed' 通道；B 块字符串编码依赖 A 块的 TextEncoder（单源，不另起第二套
//   UTF-8 实现）；utf8 编解码不重开（A 块 TextEncoder/TextDecoder 已覆盖），hash/压缩走
//   笔A native 桥（md5/sha1/sha256/zlibCompress/zlibDecompress——单源纪律）。B 块验证
//   证据 = 出书笔 Node 全量对拍（任务书 §3.3-5：200 轮随机字节样本 × hex/b64 编解码
//   往返 + csvParse 23 向量 + 错误面与幂等面，≥1000 判据全过）。
#ifndef CODEEXEC_SANDBOX_PRELUDE_H
#define CODEEXEC_SANDBOX_PRELUDE_H

// raw string 定界 R"JS(...)JS"——JS 内含 \ 与 " 原样承载；sizeof - 1 = 字节长度（无 NUL）
static constexpr char SANDBOX_PRELUDE_JS[] = R"JS(// ── 沙箱预置环境（每次执行在用户代码之前运行一次；只补纯 V8 缺失的少数 Web API）──
(function () {
  'use strict';

  // UTF-8 编码：字符串 → Uint8Array。孤立代理项按 Web 规范替换为 U+FFFD。
  function utf8Encode(input) {
    var s = input === undefined ? '' : String(input);
    var bytes = [];
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c < 0x80) {
        bytes.push(c);
      } else if (c < 0x800) {
        bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
      } else if (c >= 0xD800 && c <= 0xDBFF) {
        var n = i + 1 < s.length ? s.charCodeAt(i + 1) : 0;
        if (n >= 0xDC00 && n <= 0xDFFF) {
          var cp = 0x10000 + ((c - 0xD800) << 10) + (n - 0xDC00);
          bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
            0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
          i++;
        } else {
          bytes.push(0xEF, 0xBF, 0xBD);
        }
      } else if (c >= 0xDC00 && c <= 0xDFFF) {
        bytes.push(0xEF, 0xBF, 0xBD);
      } else {
        bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
      }
    }
    return new Uint8Array(bytes);
  }

  // UTF-8 解码：字节视图 → 字符串。非 fatal 时非法序列替换 U+FFFD（替换计数与 V8 逐字节
  // 对拍一致：截断与非法续字节按最大子部分替换一个；第二字节边界违规（E0/ED/F0/F4 的
  // 特判区间）只消费首字节、余下字节各自成错）；fatal 时遇首处非法即抛 TypeError。
  function utf8Decode(view, fatal) {
    function bad() {
      if (fatal) {
        var ferr = new Error('TextDecoder 解码失败：字节不是合法的 UTF-8');
        ferr.name = 'TypeError';
        throw ferr;
      }
      units.push(0xFFFD);
    }
    var n = view.length;
    var units = [];
    var i = 0;
    while (i < n) {
      var b = view[i];
      if (b < 0x80) {
        units.push(b);
        i++;
        continue;
      }
      var need = 0;
      var lo2 = 0x80;
      var hi2 = 0xBF;
      var cp = 0;
      if (b >= 0xC2 && b <= 0xDF) {
        need = 1;
        cp = b & 0x1F;
      } else if (b >= 0xE0 && b <= 0xEF) {
        need = 2;
        cp = b & 0x0F;
        if (b === 0xE0) { lo2 = 0xA0; } else if (b === 0xED) { hi2 = 0x9F; }
      } else if (b >= 0xF0 && b <= 0xF4) {
        need = 3;
        cp = b & 0x07;
        if (b === 0xF0) { lo2 = 0x90; } else if (b === 0xF4) { hi2 = 0x8F; }
      } else {
        bad();
        i++;
        continue;
      }
      var j = i + 1;
      var consumed = 0;
      var ok = true;
      for (var k = 0; k < need; k++) {
        if (j >= n) { ok = false; break; }
        var cb = view[j];
        if ((cb & 0xC0) !== 0x80) { ok = false; break; }
        if (k === 0 && (cb < lo2 || cb > hi2)) { ok = false; consumed = 0; break; }
        cp = (cp << 6) | (cb & 0x3F);
        j++;
        consumed++;
      }
      if (!ok) {
        bad();
        i += 1 + consumed;
        continue;
      }
      if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        bad();
        i += 1;
        continue;
      }
      if (cp >= 0x10000) {
        cp -= 0x10000;
        units.push(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
      } else {
        units.push(cp);
      }
      i = j;
    }
    var out = '';
    var block = [];
    for (var t = 0; t < units.length; t++) {
      block.push(units[t]);
      if (block.length >= 4096) {
        out += String.fromCharCode.apply(null, block);
        block.length = 0;
      }
    }
    if (block.length > 0) { out += String.fromCharCode.apply(null, block); }
    return out;
  }

  if (typeof TextEncoder === 'undefined') {
    globalThis.TextEncoder = function TextEncoder() {
      this.encoding = 'utf-8';
      this.encode = function (input) { return utf8Encode(input); };
    };
  }
  if (typeof TextDecoder === 'undefined') {
    globalThis.TextDecoder = function TextDecoder(label, options) {
      var norm = String(label === undefined ? 'utf-8' : label).trim().toLowerCase();
      if (norm !== 'utf-8' && norm !== 'utf8' && norm !== 'unicode-1-1-utf-8') {
        var rerr = new Error('TextDecoder 只支持 utf-8 编码，收到的是 ' + label);
        rerr.name = 'RangeError';
        throw rerr;
      }
      this.encoding = 'utf-8';
      this.fatal = !!(options && options.fatal === true);
      this.ignoreBOM = !!(options && options.ignoreBOM === true);
      var self = this;
      this.decode = function (input, decodeOptions) {
        if (decodeOptions && decodeOptions.stream === true) {
          var serr = new Error('TextDecoder 不支持流式解码，请一次性传入完整字节');
          serr.name = 'TypeError';
          throw serr;
        }
        if (input === undefined) { return ''; }
        var text;
        if (typeof input === 'string') {
          text = input;
        } else if (input instanceof Uint8Array) {
          text = utf8Decode(input, self.fatal);
        } else if (input instanceof ArrayBuffer) {
          text = utf8Decode(new Uint8Array(input), self.fatal);
        } else if (ArrayBuffer.isView(input)) {
          text = utf8Decode(new Uint8Array(input.buffer, input.byteOffset, input.byteLength), self.fatal);
        } else {
          var terr = new Error('TextDecoder.decode 需要 Uint8Array 或 ArrayBuffer，收到的是 ' + typeof input);
          terr.name = 'TypeError';
          throw terr;
        }
        // BOM：缺省忽略（照 Web）；ignoreBOM 为 true 时保留
        if (!self.ignoreBOM && text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
          text = text.substring(1);
        }
        return text;
      };
    };
  }

  // Base64（二进制字符串口径，照 Web atob / btoa）。
  var B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  if (typeof btoa === 'undefined') {
    globalThis.btoa = function (input) {
      var s = String(input);
      for (var q = 0; q < s.length; q++) {
        if (s.charCodeAt(q) > 0xFF) {
          var berr = new Error('btoa 的输入只能是码点不超过 255 的字符');
          berr.name = 'InvalidCharacterError';
          throw berr;
        }
      }
      var out = '';
      for (var p = 0; p < s.length; p += 3) {
        var b0 = s.charCodeAt(p);
        var b1 = p + 1 < s.length ? s.charCodeAt(p + 1) : 0;
        var b2 = p + 2 < s.length ? s.charCodeAt(p + 2) : 0;
        var tri = (b0 << 16) | (b1 << 8) | b2;
        out += B64_CHARS[(tri >> 18) & 0x3F] + B64_CHARS[(tri >> 12) & 0x3F] +
          (p + 1 < s.length ? B64_CHARS[(tri >> 6) & 0x3F] : '=') +
          (p + 2 < s.length ? B64_CHARS[tri & 0x3F] : '=');
      }
      return out;
    };
  }
  if (typeof atob === 'undefined') {
    globalThis.atob = function (input) {
      var s = String(input).replace(/[\t\n\f\r ]/g, '');
      if (s.length % 4 !== 0) {
        var aerr = new Error('atob 的输入长度不是 4 的倍数');
        aerr.name = 'InvalidCharacterError';
        throw aerr;
      }
      var pad = 0;
      while (pad < s.length && s.charAt(s.length - 1 - pad) === '=') { pad++; }
      if (pad > 2) {
        var perr = new Error('atob 的输入填充符过多');
        perr.name = 'InvalidCharacterError';
        throw perr;
      }
      var body = pad > 0 ? s.substring(0, s.length - pad) : s;
      if (/[^A-Za-z0-9+/]/.test(body)) {
        var cerr = new Error('atob 的输入包含非 base64 字符或位置错误的填充符');
        cerr.name = 'InvalidCharacterError';
        throw cerr;
      }
      var out = '';
      var acc = 0;
      var bits = 0;
      for (var i2 = 0; i2 < body.length; i2++) {
        acc = (acc << 6) | B64_CHARS.indexOf(body[i2]);
        bits += 6;
        if (bits >= 8) {
          bits -= 8;
          out += String.fromCharCode((acc >> bits) & 0xFF);
        }
      }
      return out;
    };
  }
})();)JS";

// ── 预置小工具块（★ 2026-10-06 代码工作台笔B——易用面，任务书 §3.3-3；raw string 定界
//    R"JSTOOLS(...)JSTOOLS"——JS 内含 \ 与 " 原样承载，sizeof - 1 = 字节长度（无 NUL）。
//    平铺挂 globalThis（照 A 块 atob/btoa 先例——沙箱全局无第二方共享）；幂等守卫
//    typeof X === 'undefined' 才定义（引擎自带即不覆盖，用户代码在预置之后可自行覆盖）；
//    认形口径与笔A §4.3 一致（string | TypedArray；ArrayBuffer/DataView/其余 → 中文
//    TypeError）；错误名只用 TypeError 与 InvalidCharacterError（均在笔A §4.4 表内，装配层
//    自然承接为 runtime）；块内零网络语义〔fetch/XMLHttpRequest/WebAssembly/setTimeout/
//    require——负向钉守〕）──
static constexpr char SANDBOX_PRELUDE_TOOLS_JS[] = R"JSTOOLS(// ── 沙箱预置小工具（每次执行在用户代码之前运行一次；依赖同批预置环境的 TextEncoder）──
(function () {
  'use strict';

  function toolBytes(data, fnName) {
    if (typeof data === 'string') {
      return new TextEncoder().encode(data);
    }
    if (ArrayBuffer.isView(data) && !(data instanceof DataView)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    }
    var got = 'object';
    if (data === null) {
      got = 'null';
    } else if (data instanceof ArrayBuffer) {
      got = 'ArrayBuffer';
    } else if (data instanceof DataView) {
      got = 'DataView';
    } else if (Array.isArray(data)) {
      got = 'array';
    } else if (typeof data !== 'object') {
      got = typeof data;
    }
    var err = new Error(fnName + ' 只支持字符串或 TypedArray，例如 Uint8Array，当前收到的是 ' +
      got + '。ArrayBuffer 与 DataView 请先用 new Uint8Array(...) 包一层。');
    err.name = 'TypeError';
    throw err;
  }

  function toolText(text, fnName) {
    if (typeof text !== 'string') {
      var err = new Error(fnName + ' 需要字符串输入，当前收到的是 ' + (typeof text) + '。');
      err.name = 'TypeError';
      throw err;
    }
    return text;
  }

  var HEX_CHARS = '0123456789abcdef';

  if (typeof hexEncode === 'undefined') {
    globalThis.hexEncode = function hexEncode(data) {
      var bytes = toolBytes(data, 'hexEncode');
      var out = '';
      for (var i = 0; i < bytes.length; i++) {
        out += HEX_CHARS[bytes[i] >> 4] + HEX_CHARS[bytes[i] & 0x0F];
      }
      return out;
    };
  }

  if (typeof hexDecode === 'undefined') {
    globalThis.hexDecode = function hexDecode(text) {
      var s = toolText(text, 'hexDecode');
      if (s.length % 2 !== 0) {
        var lerr = new Error('hexDecode 的输入长度不是偶数');
        lerr.name = 'InvalidCharacterError';
        throw lerr;
      }
      var bytes = new Uint8Array(s.length / 2);
      for (var i = 0; i < bytes.length; i++) {
        var hi = parseInt(s.charAt(i * 2), 16);
        var lo = parseInt(s.charAt(i * 2 + 1), 16);
        if (Number.isNaN(hi) || Number.isNaN(lo)) {
          var cerr = new Error('hexDecode 的输入包含非十六进制字符');
          cerr.name = 'InvalidCharacterError';
          throw cerr;
        }
        bytes[i] = (hi << 4) | lo;
      }
      return bytes;
    };
  }

  var B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  if (typeof b64Encode === 'undefined') {
    globalThis.b64Encode = function b64Encode(data) {
      var bytes = toolBytes(data, 'b64Encode');
      var out = '';
      for (var i = 0; i < bytes.length; i += 3) {
        var b0 = bytes[i];
        var b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
        var b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
        var tri = (b0 << 16) | (b1 << 8) | b2;
        out += B64_CHARS[(tri >> 18) & 0x3F] + B64_CHARS[(tri >> 12) & 0x3F] +
          (i + 1 < bytes.length ? B64_CHARS[(tri >> 6) & 0x3F] : '=') +
          (i + 2 < bytes.length ? B64_CHARS[tri & 0x3F] : '=');
      }
      return out;
    };
  }

  if (typeof b64Decode === 'undefined') {
    globalThis.b64Decode = function b64Decode(text) {
      var s = toolText(text, 'b64Decode').replace(/[\t\n\f\r ]/g, '');
      var pads = 0;
      while (pads < 3 && s.length > pads && s.charAt(s.length - 1 - pads) === '=') {
        pads++;
      }
      if (pads > 2) {
        var perr = new Error('b64Decode 的输入填充符过多');
        perr.name = 'InvalidCharacterError';
        throw perr;
      }
      var body = pads > 0 ? s.substring(0, s.length - pads) : s;
      if (/[^A-Za-z0-9+/]/.test(body) || body.length % 4 === 1) {
        var cerr = new Error('b64Decode 的输入不是有效的 base64 文本');
        cerr.name = 'InvalidCharacterError';
        throw cerr;
      }
      var bytes = [];
      var acc = 0;
      var bits = 0;
      for (var i = 0; i < body.length; i++) {
        acc = (acc << 6) | B64_CHARS.indexOf(body.charAt(i));
        bits += 6;
        if (bits >= 8) {
          bits -= 8;
          bytes.push((acc >> bits) & 0xFF);
        }
      }
      return new Uint8Array(bytes);
    };
  }

  if (typeof csvParse === 'undefined') {
    globalThis.csvParse = function csvParse(text) {
      var s = toolText(text, 'csvParse');
      if (s.length > 0 && s.charCodeAt(0) === 0xFEFF) {
        s = s.substring(1);
      }
      var records = [];
      var record = [];
      var field = '';
      var inQuotes = false;
      var i = 0;
      var n = s.length;
      while (i < n) {
        var ch = s.charAt(i);
        if (inQuotes) {
          if (ch === '"') {
            if (i + 1 < n && s.charAt(i + 1) === '"') {
              field += '"';
              i += 2;
              continue;
            }
            inQuotes = false;
            i += 1;
            continue;
          }
          field += ch;
          i += 1;
          continue;
        }
        if (ch === '"' && field === '') {
          inQuotes = true;
          i += 1;
          continue;
        }
        if (ch === ',') {
          record.push(field);
          field = '';
          i += 1;
          continue;
        }
        if (ch === '\r' || ch === '\n') {
          record.push(field);
          field = '';
          records.push(record);
          record = [];
          if (ch === '\r' && i + 1 < n && s.charAt(i + 1) === '\n') {
            i += 2;
          } else {
            i += 1;
          }
          continue;
        }
        field += ch;
        i += 1;
      }
      if (field !== '' || record.length > 0) {
        record.push(field);
        records.push(record);
      }
      return records;
    };
  }
})();)JSTOOLS";

#endif // CODEEXEC_SANDBOX_PRELUDE_H
