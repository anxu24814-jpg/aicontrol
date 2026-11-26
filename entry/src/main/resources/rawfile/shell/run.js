// ═══ 模拟 Shell 资产 · run.js —— 管道层 + 执行器 + 入口 ═══
// 职责：管线求值（前段 stdout 接后段 stdin）、&& 与 || 短路、重定向落写、glob 展开、
//   会话态（变量 / 退出码）、输出刷出与截断申报、两遍跑法编排、入口 __shellRunMain(text)。
// 依赖方向：parse ← commands ← run（本件消费前两件的符号与注册表；反向零引用）。
// ★P0 说明：本资产是宿主持有的只读 JS 资产；用户 shell 文本经入口以实参（字符串字面量）
//   送入，只作数据 tokenize / parse / 逐段执行——本件零动态执行、零源码拼接。用户文本
//   被动态执行 = shell 注入升级为 JS 注入。
// ● 两遍跑法为何整段拒绝（对齐 Cube 行为）：第一遍全量解析校验（parse.js），未知命令与
//   不支持语法直接抛错、一条不执行；shell 脚本「半执行」对模型是误导（前几条已改盘、
//   后几条没跑，回执难自述），整段拒绝给一次干净的重试信号。
// ● 入口契约（勿改）：__shellRunMain(text) 正常结束必须返回空串（return ''）——入口调用
//   是本段脚本的末语句，其返回值即回执 value；不显式返回空串时，每次成功回执都会多出
//   一行「结果：undefined」。
// ● 与宿主面交互的失败分类（勿改）：名称闸 / 两闸拒（FenceError）与宿主桥抛错
//   （如 DigestError）一律冒泡不吞——回执走 failed / fs-gate 或 runtime，与 JS 模式同形；
//   宿主闸是硬边界，不降格为普通命令错。运行期单条命令失败（文件不存在、选项错等）走
//   错误行 + 退出码 1 且脚本继续（&& / || / $? 可判）。
// ● 输出与内存边界：单段（命令输入 / 输出）与管道中间串受 SHELL_MAX_STAGE_BYTES 上限
//   （越限截断并在输出尾部如实申报）；输出以 SHELL_FLUSH_CHUNK_BYTES 级块刷 console.log
//   （走既有日志收集链与溢出链，零新接口）。两个常量为 JS 资产内部上限，不属档位数值单源面。
// ● 退出码申报：收尾末条退出码非 0 时在输出末尾追加一行如实申报（不改判失败、不回执
//   failed——已产出的输出必须保住，任务书 §8-6）。

// ── 资产内部上限（执行笔按 32MB 堆余量校准；改值即全链生效）──
var SHELL_MAX_STAGE_BYTES = 4 * 1024 * 1024;   // 单段输出 / 管道中间串上限（字节，如实 UTF-8 计）
var SHELL_FLUSH_CHUNK_BYTES = 64 * 1024;       // 刷出块大小（约 64 KiB 一行组一条日志）

// ── fs.list 摘要解析（ls / find / glob / du 的解析底座）──
// 摘要格式（native sandboxFsList 单源）：首行「临时区共 N 个文件。」；逐行「名 · M 字节」；
// 空目录「临时区为空。」；越 500 条尾行「……仅列出前 N 个，其余 M 个已省略。」。逐行按
// **最后一个**「 · 」左取文件名（名字自身可含中点，勿按首个分隔符切）。
// ★ 2243 笔：返回 {entries:[{name,size}], total, truncated}——字节数是 ls -l / du 的唯一
// 来源（native 摘要里本就有，此前解析时被丢掉）；名字面由 listFiles() 派生，旧调用点不变。
function __shellParseFileList(summaryText) {
  var text = typeof summaryText === 'string' ? summaryText : '';
  var parsed = { entries: [], total: 0, truncated: false };
  if (text === '' || text.indexOf('临时区为空') === 0) {
    return parsed;
  }
  var lines = text.split('\n');
  var head = /^临时区共 (\d+) 个文件。$/.exec(lines[0]);
  if (head !== null) {
    parsed.total = parseInt(head[1], 10);
  }
  for (var i = 1; i < lines.length; i++) {
    var line = lines[i];
    if (line === '') {
      continue;
    }
    if (line.indexOf('……仅列出前') === 0) {
      parsed.truncated = true; // 截断尾行（原句「……仅列出前 N 个，其余 M 个已省略。」）
      continue;
    }
    var sep = line.lastIndexOf(' \u00B7 ');
    if (sep < 0) {
      continue;
    }
    var sizeText = line.substring(sep + 3);
    var size = parseInt(sizeText, 10); // 摘要句式为「123 字节」，parseInt 取前导数字
    parsed.entries.push({
      name: line.substring(0, sep),
      size: isNaN(size) ? 0 : size
    });
  }
  if (parsed.total === 0) {
    parsed.total = parsed.entries.length; // 摘要缺首行（异常态）时按实列数兜底，不虚报
  }
  return parsed;
}

// ── 执行上下文（会话态：变量表 / 退出码 / 文件名单缓存；写后失效）──
function __shellNewContext() {
  var ctx = {
    // 变量表用零原型对象（★ 2026-10-07 复核轮修复）：普通 {} 会把 Object.prototype 成员名
    // （constructor / toString / __proto__ 等）读成继承值——未定义变量恒展开空串的契约
    // 被破成函数源码泄漏（实测 echo $constructor 输出 'function Object() { [native code] }'）
    vars: Object.create(null),
    lastCode: 0,
    filesCache: null,
    // 摘要（含字节数与总件数）——ls -l / du 与截断申报的单源；首次访问拉一次 fs.list()
    listSummary: function() {
      if (ctx.filesCache === null) {
        ctx.filesCache = __shellParseFileList(fs.list());
      }
      return ctx.filesCache;
    },
    listFiles: function() {
      var summary = ctx.listSummary();
      var names = [];
      for (var i = 0; i < summary.entries.length; i++) {
        names.push(summary.entries[i].name);
      }
      return names;
    },
    invalidate: function() {
      ctx.filesCache = null;
    },
    fileExists: function(name) {
      return fs.exists(name) === true;
    },
    readFile: function(name) {
      return fs.read(name);
    },
    readFileBytes: function(name) {
      return fs.readBytes(name);
    },
    writeFile: function(name, text) {
      var saved = fs.write(name, text);
      ctx.invalidate();
      return saved;
    },
    appendFile: function(name, text) {
      var saved = fs.append(name, text);
      ctx.invalidate();
      return saved;
    }
  };
  // 会话变量播种（2243 笔）：临时区是平铺目录、pwd 恒为 '/'——把 PWD 与 HOME 播成 '/'，
  // 让 `echo $PWD` 与 pwd 一致（此前恒展开空串）。赋值语句仍可覆盖，与普通变量同权。
  // 边界（自检轮订正）：`$HOME/xx` 会展开成 `//xx`，仍被名称闸拒——平铺临时区本就没有
  // 子目录，正确写法是裸文件名；播种只对齐 pwd 读数，不承诺 `$HOME/xx` 可用。
  ctx.vars.PWD = '/';
  ctx.vars.HOME = '/';
  return ctx;
}

// ── 词展开（字面拼接 / 变量 / $?；glob 词按临时区文件名列表展开）──
function __shellExpandParts(parts, ctx) {
  var out = '';
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    if (p.t === 'lit') {
      out += p.v;
    } else if (p.t === 'exit') {
      out += String(ctx.lastCode);
    } else {
      var v = ctx.vars[p.name];
      out += v === undefined ? '' : v;
    }
  }
  return out;
}

function __shellExpandWord(word, ctx) {
  if (!word.glob) {
    return [__shellExpandParts(word.parts, ctx)];
  }
  var pattern = __shellPlainWord(word);
  var names = ctx.listFiles();
  var matched = [];
  for (var i = 0; i < names.length; i++) {
    if (__shellGlobMatch(pattern, names[i])) {
      matched.push(names[i]);
    }
  }
  if (matched.length === 0) {
    return [pattern]; // 无匹配原样字面（POSIX 默认）
  }
  return matched;
}

// ── 输出汇聚（总量预算 + 越限截断申报；错误行与 stdout 合流、按时间序）──
// over = 最终输出撞上限；stageCut = 管道中间串曾被截断（两者任一都触发尾部申报——
// 中间串截断不冻结后续输出，末段命令的结果仍可见）
function __shellNewSink() {
  var sink = {
    text: '',
    bytes: 0,
    over: false,
    stageCut: false,
    out: function(chunk) {
      if (chunk === '' || sink.over) {
        return;
      }
      var size = __shellUtf8Len(chunk);
      if (sink.bytes + size <= SHELL_MAX_STAGE_BYTES) {
        sink.text += chunk;
        sink.bytes += size;
        return;
      }
      var room = SHELL_MAX_STAGE_BYTES - sink.bytes;
      if (room > 0) {
        sink.text += __shellUtf8Prefix(chunk, room);
      }
      sink.over = true;
    },
    err: function(line) {
      sink.out(line + '\n');
    },
    capStage: function(chunk) {
      if (__shellUtf8Len(chunk) <= SHELL_MAX_STAGE_BYTES) {
        return chunk;
      }
      sink.stageCut = true;
      return __shellUtf8Prefix(chunk, SHELL_MAX_STAGE_BYTES);
    }
  };
  return sink;
}

// ── 执行：语句（赋值 / 条件链）→ 管线（段串联 + 重定向）──
function __shellExecStatement(stmt, ctx, sink) {
  if (stmt.kind === 'assign') {
    for (var i = 0; i < stmt.assigns.length; i++) {
      var a = stmt.assigns[i];
      ctx.vars[a.name] = __shellExpandParts(a.valueParts, ctx);
    }
    ctx.lastCode = 0;
    return;
  }
  var code = 0;
  for (var c = 0; c < stmt.chain.length; c++) {
    var link = stmt.chain[c];
    if (link.op === '&&' && code !== 0) {
      continue;
    }
    if (link.op === '||' && code === 0) {
      continue;
    }
    code = __shellExecPipeline(link.pipeline, ctx, sink);
  }
  ctx.lastCode = code;
}

function __shellExecPipeline(pipeline, ctx, sink) {
  var stdin = '';
  var code = 0;
  for (var i = 0; i < pipeline.segments.length; i++) {
    var seg = pipeline.segments[i];
    var args = [];
    for (var w = 0; w < seg.words.length; w++) {
      var vals = __shellExpandWord(seg.words[w], ctx);
      for (var v = 0; v < vals.length; v++) {
        args.push(vals[v]);
      }
    }
    var cmd = __shellFindCommand(args[0]);
    if (cmd === null) {
      // 首遍已校验命令在场——此处为防御出口（如实报错，不静默）
      throw __shellLineError(seg.line, '不支持命令「' + args[0] + '」。');
    }
    var result = cmd.run(args.slice(1), stdin, ctx);
    if (result.errLines !== undefined && result.errLines !== null) {
      for (var e = 0; e < result.errLines.length; e++) {
        sink.err(result.errLines[e]);
      }
    }
    stdin = sink.capStage(result.out);
    code = result.code;
  }
  if (pipeline.redirect !== null) {
    var target = __shellExpandParts(pipeline.redirect.word.parts, ctx);
    if (pipeline.redirect.kind === '>') {
      ctx.writeFile(target, stdin);
    } else {
      ctx.appendFile(target, stdin);
    }
  } else {
    sink.out(stdin);
  }
  return code;
}

// ── 输出刷出（按行组打包成 SHELL_FLUSH_CHUNK_BYTES 级日志条目；**一条日志条目恒为若干
//   完整行**——回执与溢出件以 '\n' join 各条目，只有整行组才能逐字复原；超长单行不切块
//   （切块会在 join 处插入伪换行、破坏「完整输出」逐字保真——★ 2026-10-07 复核轮修复，
//   原实现按块切长行，溢出件里 >64KiB 的单行被周期性伪换行腰斩）。块大小按 JS 字符串
//   长度（UTF-16 码元）计，常数名沿用任务书 §3.3 约定（ASCII 文本时即字节量级）──
function __shellFlush(text) {
  var lines = text.split('\n');
  var buf = [];
  var size = 0;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (buf.length > 0 && size + line.length + 1 > SHELL_FLUSH_CHUNK_BYTES) {
      console.log(buf.join('\n'));
      buf = [];
      size = 0;
    }
    buf.push(line);
    size += line.length + 1;
  }
  if (buf.length > 0) {
    console.log(buf.join('\n'));
  }
}

// ── 入口（契约：正常结束返回空串；解析拒绝抛 ShellError 冒泡）──
function __shellRunMain(text) {
  var source = text === undefined || text === null ? '' : String(text);
  var script = __shellParseScript(source);
  __shellValidate(script, __shellCommandNames());
  var ctx = __shellNewContext();
  var sink = __shellNewSink();
  for (var i = 0; i < script.statements.length; i++) {
    __shellExecStatement(script.statements[i], ctx, sink);
  }
  var finalText = sink.text;
  if (sink.over || sink.stageCut) {
    finalText += '输出超过单段上限，已截断。\n';
  }
  if (ctx.lastCode !== 0) {
    finalText += '脚本以退出码 ' + ctx.lastCode + ' 结束。\n';
  }
  if (finalText !== '') {
    __shellFlush(finalText);
  }
  return '';
}
