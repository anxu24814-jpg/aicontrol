// ═══ 模拟 Shell 资产 · commands.js —— 命令层（命令注册表 + help 单源）═══
// 职责：内置命令的注册表（名字 + 用法行 + 一句话说明 + 纯函数实现）与 help 的唯一生成源
//   ——help 输出全部从注册表派生，加命令忘改 help 即由断言面兜住。
// 依赖方向：parse ← commands ← run（本件只用自身符号与 parse.js 的工具（如通配匹配）；
//   执行上下文 ctx 由 run.js 组装后传入）。
// ★P0 说明：本资产是宿主持有的只读 JS 资产；命令实现只做「输入（文本 / 字节）→ 输出」
//   变换与经 ctx 访问宿主面，零动态执行、零源码拼接；命令层不注册任何网络类命令。
// 命令纪律：纯函数式——不持跨调用状态；输出不得无界累积（超限由 run.js 的单段上限统一
//   截断并申报）；文件参数经宿主名称闸与两闸（读侧同样过闸）。
// 错误行格式：`命令名: 原因`（POSIX 风格）——与 stdout 合流输出（本链无独立 stderr
//   通道），退出码 1 且脚本继续（运行期失败语义）。
// ctx 接口（run.js 提供）：listFiles() → 名字数组 / listSummary() → {entries:[{name,size}],
//   total, truncated} / fileExists(name) / readFile(name) / readFileBytes(name) /
//   writeFile(name, text) / appendFile(name, text)。
// ★ 2243 笔：listSummary 的字节数直接来自 fs.list 摘要（native sandboxFsList 单源），
//   ls -l 与 du 不另请 native 能力——沙箱 fs 只有七个方法、无删除原语，故 rm / mv 仍不提供。

// ── 命令结果与错误行小件 ──
function __shellCmdFail(cmdName, message) {
  return { out: '', code: 1, errLines: [cmdName + ': ' + message] };
}

// 文本按行切分（末尾换行不算空行）
function __shellSplitLines(text) {
  if (text === '') {
    return [];
  }
  var lines = text.split('\n');
  if (lines[lines.length - 1] === '') {
    lines.pop();
  }
  return lines;
}

// 行数组 → 输出文本（空数组回空串——无输出不产生空行）
function __shellLinesOut(lines) {
  return lines.length === 0 ? '' : lines.join('\n') + '\n';
}

// 输入读取（无文件名 = 用管道输入 / stdin；有文件名 = 逐件读取拼接；文件缺失 = 错误行
// 且继续处理其余件——返回 {text, code, errLines}；错误行带命令名前缀）
function __shellReadInput(cmdName, files, stdin, ctx) {
  if (files.length === 0) {
    return { text: stdin, code: 0, errLines: [] };
  }
  var text = '';
  var code = 0;
  var errLines = [];
  for (var i = 0; i < files.length; i++) {
    var f = files[i];
    if (!ctx.fileExists(f)) {
      errLines.push(cmdName + ': ' + f + ': 没有这个文件');
      code = 1;
      continue;
    }
    text += ctx.readFile(f);
  }
  return { text: text, code: code, errLines: errLines };
}

// ── printf 小件 ──
function __shellPrintfInt(s) {
  var v = Number(s);
  if (!isFinite(v)) {
    return '0';
  }
  return String(Math.trunc(v));
}

function __shellPrintfHex(s) {
  var v = Number(s);
  if (!isFinite(v)) {
    return '0';
  }
  return Math.trunc(v).toString(16);
}

// 单轮格式替换（返回 {text, next}：next = 本轮消费到的参数下标）
function __shellPrintfPass(format, args, startAt) {
  var out = '';
  var idx = startAt;
  var i = 0;
  while (i < format.length) {
    var c = format.charAt(i);
    if (c === '\\') {
      var nx = i + 1 < format.length ? format.charAt(i + 1) : '';
      if (nx === 'n') {
        out += '\n';
        i += 2;
        continue;
      }
      if (nx === 't') {
        out += '\t';
        i += 2;
        continue;
      }
      if (nx === 'r') {
        out += '\r';
        i += 2;
        continue;
      }
      if (nx === '\\') {
        out += '\\';
        i += 2;
        continue;
      }
      out += '\\';
      i++;
      continue;
    }
    if (c === '%') {
      var f = i + 1 < format.length ? format.charAt(i + 1) : '';
      if (f === 's') {
        out += idx < args.length ? args[idx] : '';
        idx++;
        i += 2;
        continue;
      }
      if (f === 'd') {
        out += __shellPrintfInt(idx < args.length ? args[idx] : '0');
        idx++;
        i += 2;
        continue;
      }
      if (f === 'x') {
        out += __shellPrintfHex(idx < args.length ? args[idx] : '0');
        idx++;
        i += 2;
        continue;
      }
      if (f === '%') {
        out += '%';
        i += 2;
        continue;
      }
      out += '%';
      i++;
      continue;
    }
    out += c;
    i++;
  }
  return { text: out, next: idx };
}

// ── tr 字符集展开（支持 a-z 范围；逆范围与孤立 - 原样保留）──
function __shellTrExpand(spec) {
  var out = '';
  var i = 0;
  while (i < spec.length) {
    if (i + 2 < spec.length && spec.charAt(i + 1) === '-') {
      var lo = spec.charCodeAt(i);
      var hi = spec.charCodeAt(i + 2);
      if (lo <= hi) {
        for (var code = lo; code <= hi; code++) {
          out += String.fromCharCode(code);
        }
        i += 3;
        continue;
      }
    }
    out += spec.charAt(i);
    i++;
  }
  return out;
}

// ── 选项解析小件（-abc 组合形态；返回 true = 已识别并消费）──
function __shellMatchFlags(arg, allowed) {
  if (arg.length < 2 || arg.charAt(0) !== '-') {
    return false;
  }
  for (var i = 1; i < arg.length; i++) {
    if (allowed.indexOf(arg.charAt(i)) < 0) {
      return false;
    }
  }
  return true;
}

// ── 摘要消费小件（ls -l / du 共用；summary = run.js 的 listSummary() 形态）──
// 零原型对象：文件名可能叫 constructor / toString（★ 2026-10-07 复核轮同族坑）
function __shellSizeMap(summary) {
  var map = Object.create(null);
  for (var i = 0; i < summary.entries.length; i++) {
    map[summary.entries[i].name] = summary.entries[i].size;
  }
  return map;
}

function __shellNamesOf(summary) {
  var names = [];
  for (var i = 0; i < summary.entries.length; i++) {
    names.push(summary.entries[i].name);
  }
  return names;
}

// ── 命令注册表（help 唯一生成源；2243 笔拍板：原 22 条 + du / tee 两条，ls 增 -l）──
var __SHELL_COMMANDS = [
  {
    name: 'pwd',
    usage: 'pwd',
    summary: '显示当前目录（恒为 /，变量 PWD 与 HOME 同值）',
    run: function(args, stdin, ctx) {
      return { out: '/\n', code: 0 };
    }
  },
  {
    name: 'cd',
    usage: 'cd [目录]',
    summary: '切换目录（只支持 /，临时区是平铺的）',
    run: function(args, stdin, ctx) {
      if (args.length === 0 || (args.length === 1 && args[0] === '/')) {
        return { out: '', code: 0 };
      }
      return __shellCmdFail('cd', '模拟 Shell 的临时区是平铺的，没有子目录，只支持 cd /');
    }
  },
  {
    name: 'echo',
    usage: 'echo [-n] 文字…',
    summary: '输出文字，-n 表示不换行',
    run: function(args, stdin, ctx) {
      var start = 0;
      var tail = '\n';
      if (args.length > 0 && args[0] === '-n') {
        start = 1;
        tail = '';
      }
      return { out: args.slice(start).join(' ') + tail, code: 0 };
    }
  },
  {
    name: 'printf',
    usage: 'printf 格式串 [参数…]',
    summary: '按格式输出，支持 %s、%d、%x 与 %%',
    run: function(args, stdin, ctx) {
      if (args.length === 0) {
        return { out: '', code: 0 };
      }
      var format = args[0];
      var rest = args.slice(1);
      var out = '';
      var idx = 0;
      do {
        var pass = __shellPrintfPass(format, rest, idx);
        out += pass.text;
        if (pass.next === idx) {
          break; // 本轮未消费任何参数——防格式串无格式符时死循环（有格式符时每轮必消费，循环天然有界）
        }
        idx = pass.next;
      } while (idx < rest.length);
      return { out: out, code: 0 };
    }
  },
  {
    name: 'true',
    usage: 'true',
    summary: '空操作，退出码 0',
    run: function(args, stdin, ctx) {
      return { out: '', code: 0 };
    }
  },
  {
    name: 'false',
    usage: 'false',
    summary: '空操作，退出码 1',
    run: function(args, stdin, ctx) {
      return { out: '', code: 1 };
    }
  },
  {
    name: 'ls',
    usage: 'ls [-l] [文件名或通配模式…]',
    summary: '列出临时区文件（-l 附带字节数；无参数时列出全部）',
    run: function(args, stdin, ctx) {
      var longForm = false;
      var names = [];
      for (var a = 0; a < args.length; a++) {
        if (args[a] === '-l') {
          longForm = true;
          continue;
        }
        if (args[a].length > 1 && args[a].charAt(0) === '-') {
          return __shellCmdFail('ls', '不支持的选项 ' + args[a] + '，可用选项为 -l');
        }
        names.push(args[a]);
      }
      var summary = ctx.listSummary();
      var sizeOf = __shellSizeMap(summary);
      if (names.length === 0) {
        if (!longForm) {
          return { out: __shellLinesOut(__shellNamesOf(summary)), code: 0 };
        }
        var lines = [];
        for (var e = 0; e < summary.entries.length; e++) {
          lines.push(String(summary.entries[e].size) + '\t' + summary.entries[e].name);
        }
        return { out: __shellLinesOut(lines), code: 0 };
      }
      var out = '';
      var code = 0;
      var errLines = [];
      for (var i = 0; i < names.length; i++) {
        if (!ctx.fileExists(names[i])) {
          errLines.push('ls: ' + names[i] + ': 没有这个文件');
          code = 1;
          continue;
        }
        // 超过摘要上限（native 500 条）的文件仍在，但字节数取不到——如实打问号，不猜 0
        var size = sizeOf[names[i]];
        out += longForm ? (size === undefined ? '?' : String(size)) + '\t' + names[i] + '\n'
          : names[i] + '\n';
      }
      return { out: out, code: code, errLines: errLines };
    }
  },
  {
    name: 'du',
    usage: 'du [文件名…]',
    summary: '统计文件字节数（无参数时逐件列出并给合计）',
    run: function(args, stdin, ctx) {
      var summary = ctx.listSummary();
      var sizeOf = __shellSizeMap(summary);
      if (args.length === 0) {
        var lines = [];
        var total = 0;
        for (var e = 0; e < summary.entries.length; e++) {
          lines.push(String(summary.entries[e].size) + '\t' + summary.entries[e].name);
          total += summary.entries[e].size;
        }
        lines.push('合计 ' + summary.entries.length + ' 个文件，' + total + ' 字节');
        if (summary.truncated) {
          // 截断时合计只是已列出部分——如实申报，不让模型把部分和当全量（P0-1 禁静默）
          lines.push('仅统计已列出的 ' + summary.entries.length + ' 个，其余 '
            + (summary.total - summary.entries.length) + ' 个未列出');
        }
        return { out: __shellLinesOut(lines), code: 0 };
      }
      var out = '';
      var code = 0;
      var errLines = [];
      for (var i = 0; i < args.length; i++) {
        if (args[i].length > 1 && args[i].charAt(0) === '-') {
          return __shellCmdFail('du', 'du 没有可用选项，参数只支持文件名，例如 du 报告.csv');
        }
        if (!ctx.fileExists(args[i])) {
          errLines.push('du: ' + args[i] + ': 没有这个文件');
          code = 1;
          continue;
        }
        var size = sizeOf[args[i]];
        out += (size === undefined ? '?' : String(size)) + '\t' + args[i] + '\n';
      }
      return { out: out, code: code, errLines: errLines };
    }
  },
  {
    name: 'find',
    usage: 'find [通配模式…]',
    summary: '按通配模式匹配临时区文件名（平铺，无目录树）',
    run: function(args, stdin, ctx) {
      var names = ctx.listFiles();
      if (args.length === 0) {
        return { out: __shellLinesOut(names), code: 0 };
      }
      var out = '';
      // 零原型对象（★ 2026-10-07 复核轮修复）：普通 {} 会把 Object.prototype 成员名
      // （constructor / toString 等）读成「已见」——同名文件被静默跳过（实测 find * 漏件）
      var seen = Object.create(null);
      for (var i = 0; i < args.length; i++) {
        for (var k = 0; k < names.length; k++) {
          if (!seen[names[k]] && __shellGlobMatch(args[i], names[k])) {
            seen[names[k]] = true;
            out += names[k] + '\n';
          }
        }
      }
      return { out: out, code: 0 };
    }
  },
  {
    name: 'cat',
    usage: 'cat [文件名…]',
    summary: '输出文件内容（无参数时原样输出输入）',
    run: function(args, stdin, ctx) {
      if (args.length === 0) {
        return { out: stdin, code: 0 };
      }
      var out = '';
      var code = 0;
      var errLines = [];
      for (var i = 0; i < args.length; i++) {
        if (!ctx.fileExists(args[i])) {
          errLines.push('cat: ' + args[i] + ': 没有这个文件');
          code = 1;
          continue;
        }
        out += ctx.readFile(args[i]);
      }
      return { out: out, code: code, errLines: errLines };
    }
  },
  {
    name: 'head',
    usage: 'head [-n 行数] [文件名]',
    summary: '显示开头若干行，缺省 10 行',
    run: function(args, stdin, ctx) {
      var count = 10;
      var files = [];
      var i = 0;
      while (i < args.length) {
        if (args[i] === '-n') {
          if (i + 1 >= args.length) {
            return __shellCmdFail('head', '-n 后面需要行数，例如 head -n 5');
          }
          var nv = parseInt(args[i + 1], 10);
          if (isNaN(nv)) {
            return __shellCmdFail('head', '-n 后面需要行数，例如 head -n 5');
          }
          count = nv;
          i += 2;
          continue;
        }
        if (/^-[0-9]+$/.test(args[i])) {
          count = parseInt(args[i].substring(1), 10);
          i++;
          continue;
        }
        files.push(args[i]);
        i++;
      }
      var input = __shellReadInput('head', files, stdin, ctx);
      if (count < 0) {
        count = 0;
      }
      var lines = __shellSplitLines(input.text);
      return { out: __shellLinesOut(lines.slice(0, count)),
        code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'tail',
    usage: 'tail [-n 行数] [文件名]',
    summary: '显示末尾若干行，缺省 10 行',
    run: function(args, stdin, ctx) {
      var count = 10;
      var files = [];
      var i = 0;
      while (i < args.length) {
        if (args[i] === '-n') {
          if (i + 1 >= args.length) {
            return __shellCmdFail('tail', '-n 后面需要行数，例如 tail -n 5');
          }
          var nv = parseInt(args[i + 1], 10);
          if (isNaN(nv)) {
            return __shellCmdFail('tail', '-n 后面需要行数，例如 tail -n 5');
          }
          count = nv;
          i += 2;
          continue;
        }
        if (/^-[0-9]+$/.test(args[i])) {
          count = parseInt(args[i].substring(1), 10);
          i++;
          continue;
        }
        files.push(args[i]);
        i++;
      }
      var input = __shellReadInput('tail', files, stdin, ctx);
      var lines = __shellSplitLines(input.text);
      var start = count < 0 ? 0 : Math.max(lines.length - count, 0);
      return { out: __shellLinesOut(lines.slice(start)),
        code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'wc',
    usage: 'wc [-l] [-w] [-c] [文件名]',
    summary: '统计行数、词数与字节数（缺省三项同印）',
    run: function(args, stdin, ctx) {
      var wantLines = false;
      var wantWords = false;
      var wantBytes = false;
      var anyFlag = false;
      var files = [];
      for (var i = 0; i < args.length; i++) {
        if (__shellMatchFlags(args[i], 'lwc')) {
          if (args[i].indexOf('l') >= 0) {
            wantLines = true;
          }
          if (args[i].indexOf('w') >= 0) {
            wantWords = true;
          }
          if (args[i].indexOf('c') >= 0) {
            wantBytes = true;
          }
          anyFlag = true;
          continue;
        }
        files.push(args[i]);
      }
      if (!anyFlag) {
        wantLines = true;
        wantWords = true;
        wantBytes = true;
      }
      var input = __shellReadInput('wc', files, stdin, ctx);
      var text = input.text;
      var parts = [];
      if (wantLines) {
        parts.push(String(__shellSplitLines(text).length));
      }
      if (wantWords) {
        var trimmed = text.replace(/^\s+|\s+$/g, '');
        parts.push(String(trimmed === '' ? 0 : trimmed.split(/\s+/).length));
      }
      if (wantBytes) {
        parts.push(String(__shellUtf8Len(text)));
      }
      return { out: parts.join(' ') + '\n', code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'grep',
    usage: 'grep (-F | -E) [-i] [-n] [-c] [-v] 模式 [文件名]',
    summary: '按固定文字（-F）或正则（-E）筛选行',
    run: function(args, stdin, ctx) {
      var fixed = false;
      var extended = false;
      var ignoreCase = false;
      var showNum = false;
      var countOnly = false;
      var invert = false;
      var pattern = null;
      var files = [];
      for (var i = 0; i < args.length; i++) {
        var a = args[i];
        if (pattern === null && __shellMatchFlags(a, 'EFinvc')) {
          if (a.indexOf('F') >= 0) {
            fixed = true;
          }
          if (a.indexOf('E') >= 0) {
            extended = true;
          }
          if (a.indexOf('i') >= 0) {
            ignoreCase = true;
          }
          if (a.indexOf('n') >= 0) {
            showNum = true;
          }
          if (a.indexOf('c') >= 0) {
            countOnly = true;
          }
          if (a.indexOf('v') >= 0) {
            invert = true;
          }
          continue;
        }
        if (pattern === null && a.length > 0 && a.charAt(0) === '-') {
          return __shellCmdFail('grep',
            '不支持的选项 ' + a + '，可用选项为 -F、-E、-i、-n、-c、-v');
        }
        if (pattern === null) {
          pattern = a;
          continue;
        }
        files.push(a);
      }
      if (pattern === null) {
        return __shellCmdFail('grep', '缺少要匹配的模式，用法见 help grep');
      }
      if (fixed && extended) {
        return __shellCmdFail('grep', '-F 与 -E 只能二选一，固定文字用 -F，正则用 -E');
      }
      if (!fixed && !extended) {
        return __shellCmdFail('grep',
          '需要 -F 或 -E 选项，固定文字用 -F，正则用 -E，例如 grep -E "a[0-9]+" 文件名');
      }
      // 正则模式（-E）：pattern 来自用户脚本，构造失败只报命令错不冒泡——整段脚本不该因为
      // 一条写错的正则被判失败；灾难性回溯由脚本时限兜底（strict 档有限时与内存上限）
      var regex = null;
      if (extended) {
        try {
          regex = new RegExp(pattern, ignoreCase ? 'i' : '');
        } catch (e) {
          return __shellCmdFail('grep',
            '正则表达式无效，例如 grep -E "a[0-9]+" 文件名');
        }
      }
      var needle = ignoreCase ? pattern.toLowerCase() : pattern;
      var input = __shellReadInput('grep', files, stdin, ctx);
      var lines = __shellSplitLines(input.text);
      var matched = [];
      var hitCount = 0;
      for (var k = 0; k < lines.length; k++) {
        var hit;
        if (regex !== null) {
          hit = regex.test(lines[k]);
        } else {
          var hay = ignoreCase ? lines[k].toLowerCase() : lines[k];
          hit = hay.indexOf(needle) >= 0;
        }
        if (invert) {
          hit = !hit;
        }
        if (hit) {
          hitCount++;
          if (!countOnly) {
            matched.push(showNum ? String(k + 1) + ':' + lines[k] : lines[k]);
          }
        }
      }
      var code = input.code;
      if (hitCount === 0 && code === 0) {
        code = 1; // 无匹配按 POSIX 惯例回退出码 1（$? 与 && / || 可判）
      }
      var out = countOnly ? String(hitCount) + '\n' : __shellLinesOut(matched);
      return { out: out, code: code, errLines: input.errLines };
    }
  },
  {
    name: 'sort',
    usage: 'sort [-r] [-n] [文件名]',
    summary: '按行排序，-r 反向、-n 按数值',
    run: function(args, stdin, ctx) {
      var reverse = false;
      var numeric = false;
      var files = [];
      for (var i = 0; i < args.length; i++) {
        if (__shellMatchFlags(args[i], 'rn')) {
          if (args[i].indexOf('r') >= 0) {
            reverse = true;
          }
          if (args[i].indexOf('n') >= 0) {
            numeric = true;
          }
          continue;
        }
        files.push(args[i]);
      }
      var input = __shellReadInput('sort', files, stdin, ctx);
      var lines = __shellSplitLines(input.text);
      lines.sort(function(a, b) {
        var r;
        if (numeric) {
          var na = parseFloat(a);
          var nb = parseFloat(b);
          if (isNaN(na)) {
            na = 0;
          }
          if (isNaN(nb)) {
            nb = 0;
          }
          r = na < nb ? -1 : (na > nb ? 1 : 0);
        } else {
          r = a < b ? -1 : (a > b ? 1 : 0);
        }
        return reverse ? -r : r;
      });
      return { out: __shellLinesOut(lines), code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'uniq',
    usage: 'uniq [-c] [文件名]',
    summary: '去掉相邻重复行，-c 附带出现次数',
    run: function(args, stdin, ctx) {
      var countFlag = false;
      var files = [];
      for (var i = 0; i < args.length; i++) {
        if (args[i] === '-c') {
          countFlag = true;
          continue;
        }
        files.push(args[i]);
      }
      var input = __shellReadInput('uniq', files, stdin, ctx);
      var lines = __shellSplitLines(input.text);
      var out = [];
      var i2 = 0;
      while (i2 < lines.length) {
        var j = i2;
        while (j + 1 < lines.length && lines[j + 1] === lines[i2]) {
          j++;
        }
        if (countFlag) {
          out.push(String(j - i2 + 1) + ' ' + lines[i2]);
        } else {
          out.push(lines[i2]);
        }
        i2 = j + 1;
      }
      return { out: __shellLinesOut(out), code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'cut',
    usage: 'cut -d 分隔符 -f 字段列表 [文件名]',
    summary: '按分隔符切分并取字段，例如 cut -d , -f 1,3',
    run: function(args, stdin, ctx) {
      var delim = '\t';
      var fieldsSpec = null;
      var files = [];
      var i = 0;
      while (i < args.length) {
        var a = args[i];
        if (a === '-d') {
          if (i + 1 >= args.length) {
            return __shellCmdFail('cut', '-d 后面需要分隔符，例如 cut -d , -f 1');
          }
          delim = args[i + 1];
          i += 2;
          continue;
        }
        if (a.indexOf('-d') === 0 && a.length > 2) {
          delim = a.substring(2);
          i++;
          continue;
        }
        if (a === '-f') {
          if (i + 1 >= args.length) {
            return __shellCmdFail('cut', '-f 后面需要字段列表，例如 cut -f 1,3');
          }
          fieldsSpec = args[i + 1];
          i += 2;
          continue;
        }
        if (a.indexOf('-f') === 0 && a.length > 2) {
          fieldsSpec = a.substring(2);
          i++;
          continue;
        }
        files.push(a);
        i++;
      }
      if (fieldsSpec === null) {
        return __shellCmdFail('cut', '需要 -f 字段列表，例如 cut -d , -f 1');
      }
      if (delim.length !== 1) {
        return __shellCmdFail('cut', '-d 需要单个字符作为分隔符');
      }
      var picks = [];
      var fieldParts = fieldsSpec.split(',');
      for (var f = 0; f < fieldParts.length; f++) {
        var num = parseInt(fieldParts[f], 10);
        if (isNaN(num) || num < 1) {
          return __shellCmdFail('cut', '字段列表需要是正整数或以逗号分隔的正整数，例如 -f 1,3');
        }
        picks.push(num - 1);
      }
      var input = __shellReadInput('cut', files, stdin, ctx);
      var lines = __shellSplitLines(input.text);
      var outLines = [];
      for (var k = 0; k < lines.length; k++) {
        var cols = lines[k].split(delim);
        var picked = [];
        for (var p = 0; p < picks.length; p++) {
          picked.push(picks[p] < cols.length ? cols[picks[p]] : '');
        }
        outLines.push(picked.join(delim));
      }
      return { out: __shellLinesOut(outLines), code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'tr',
    usage: 'tr [-d] 字符集1 [字符集2]',
    summary: '字符替换，-d 表示删除字符集1里的字符',
    run: function(args, stdin, ctx) {
      var del = false;
      var rest = [];
      for (var i = 0; i < args.length; i++) {
        if (args[i] === '-d') {
          del = true;
        } else {
          rest.push(args[i]);
        }
      }
      if (del && rest.length < 1) {
        return __shellCmdFail('tr', '-d 后面需要字符集，例如 tr -d 0-9');
      }
      // 元数上界（★ 2026-10-07 复核轮修复）：tr 只从输入读取数据——多余实参原被静默忽略
      // （tr a-z A-Z file.txt 空输出且退出码 0，模型误以为已处理该文件）
      if (del && rest.length > 1) {
        return __shellCmdFail('tr', 'tr 只从输入读取数据，不支持文件名参数，例如 cat 文件名 | tr -d 0-9');
      }
      if (!del && rest.length < 2) {
        return __shellCmdFail('tr', '需要两个字符集参数，例如 tr a-z A-Z');
      }
      if (!del && rest.length > 2) {
        return __shellCmdFail('tr', 'tr 只从输入读取数据，不支持文件名参数，例如 cat 文件名 | tr a-z A-Z');
      }
      var set1 = __shellTrExpand(rest[0]);
      var set2 = del ? '' : __shellTrExpand(rest[1]);
      if (!del && set2 === '') {
        return __shellCmdFail('tr', '第二个字符集不能为空');
      }
      var out = '';
      for (var k = 0; k < stdin.length; k++) {
        var ch = stdin.charAt(k);
        var pos = set1.indexOf(ch);
        if (del) {
          if (pos < 0) {
            out += ch;
          }
        } else if (pos < 0) {
          out += ch;
        } else {
          out += set2.charAt(Math.min(pos, set2.length - 1)); // 目标集短时按 POSIX 用末字符补足
        }
      }
      return { out: out, code: 0 };
    }
  },
  {
    name: 'cp',
    usage: 'cp 源文件名 目标文件名',
    summary: '复制文件（源文件保留）',
    run: function(args, stdin, ctx) {
      if (args.length !== 2) {
        return __shellCmdFail('cp', '需要源文件名与目标文件名两个参数');
      }
      if (!ctx.fileExists(args[0])) {
        return __shellCmdFail('cp', args[0] + ': 没有这个文件');
      }
      var text = ctx.readFile(args[0]);
      ctx.writeFile(args[1], text);
      return { out: '', code: 0 };
    }
  },
  {
    name: 'tee',
    usage: 'tee [-a] 文件名…',
    summary: '把输入写进文件并原样输出，-a 表示追加',
    run: function(args, stdin, ctx) {
      var append = false;
      var files = [];
      for (var i = 0; i < args.length; i++) {
        if (args[i] === '-a') {
          append = true;
          continue;
        }
        if (args[i].length > 1 && args[i].charAt(0) === '-') {
          return __shellCmdFail('tee', '不支持的选项 ' + args[i] + '，可用选项为 -a');
        }
        files.push(args[i]);
      }
      if (files.length === 0) {
        return __shellCmdFail('tee', '需要文件名，例如 cat a.txt | tee 副本.txt');
      }
      for (var k = 0; k < files.length; k++) {
        if (append) {
          ctx.appendFile(files[k], stdin);
        } else {
          ctx.writeFile(files[k], stdin);
        }
      }
      return { out: stdin, code: 0 };
    }
  },
  {
    name: 'base64',
    usage: 'base64 [-d] [文件名]',
    summary: 'base64 编码，-d 表示解码',
    run: function(args, stdin, ctx) {
      var decode = false;
      var files = [];
      for (var i = 0; i < args.length; i++) {
        if (args[i] === '-d') {
          decode = true;
        } else {
          files.push(args[i]);
        }
      }
      var input = __shellReadInput('base64', files, stdin, ctx);
      if (!decode) {
        return { out: b64Encode(input.text) + '\n',
          code: input.code, errLines: input.errLines };
      }
      var bytes = b64Decode(input.text.replace(/\s+/g, '')); // 非法 base64 抛错冒泡（宿主桥分类）
      var text = new TextDecoder('utf-8').decode(bytes);
      return { out: text, code: input.code, errLines: input.errLines };
    }
  },
  {
    name: 'sha256sum',
    usage: 'sha256sum [文件名]',
    summary: '计算 SHA-256 摘要（十六进制小写）',
    run: function(args, stdin, ctx) {
      if (args.length === 0) {
        return { out: sha256(stdin) + '\n', code: 0 };
      }
      var out = '';
      var code = 0;
      var errLines = [];
      for (var i = 0; i < args.length; i++) {
        if (!ctx.fileExists(args[i])) {
          errLines.push('sha256sum: ' + args[i] + ': 没有这个文件');
          code = 1;
          continue;
        }
        var bytes = ctx.readFileBytes(args[i]); // 字节直通（二进制文件可哈希）
        out += sha256(bytes) + ' ' + args[i] + '\n';
      }
      return { out: out, code: code, errLines: errLines };
    }
  },
  {
    name: 'uuidgen',
    usage: 'uuidgen',
    summary: '生成一个 UUID（v4 形态，随机强度有限）',
    run: function(args, stdin, ctx) {
      var hex = '0123456789abcdef';
      var s = '';
      for (var i = 0; i < 36; i++) {
        if (i === 8 || i === 13 || i === 18 || i === 23) {
          s += '-';
        } else if (i === 14) {
          s += '4';
        } else if (i === 19) {
          s += hex.charAt(8 + Math.floor(Math.random() * 4));
        } else {
          s += hex.charAt(Math.floor(Math.random() * 16));
        }
      }
      return { out: s + '\n', code: 0 };
    }
  },
  {
    name: 'help',
    usage: 'help [命令名]',
    summary: '查看命令列表或某条命令的说明',
    run: function(args, stdin, ctx) {
      if (args.length === 0) {
        var lines = ['可用命令如下（共 ' + __SHELL_COMMANDS.length + ' 条）'];
        for (var i = 0; i < __SHELL_COMMANDS.length; i++) {
          var c = __SHELL_COMMANDS[i];
          lines.push(c.name + '：' + c.summary);
        }
        lines.push('用 help 命令名 查看某条命令的用法与说明。');
        return { out: __shellLinesOut(lines), code: 0 };
      }
      var cmd = __shellFindCommand(args[0]);
      if (cmd === null) {
        return __shellCmdFail('help', '没有这个命令：' + args[0]);
      }
      return { out: '用法：' + cmd.usage + '\n说明：' + cmd.summary + '\n', code: 0 };
    }
  }
];

// 命令名集合（run.js 的首遍校验消费——注册表派生，零第二份名单）
function __shellCommandNames() {
  var map = {};
  for (var i = 0; i < __SHELL_COMMANDS.length; i++) {
    map[__SHELL_COMMANDS[i].name] = true;
  }
  return map;
}

function __shellFindCommand(name) {
  for (var i = 0; i < __SHELL_COMMANDS.length; i++) {
    if (__SHELL_COMMANDS[i].name === name) {
      return __SHELL_COMMANDS[i];
    }
  }
  return null;
}
