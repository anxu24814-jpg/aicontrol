// ═══ 模拟 Shell 资产 · parse.js —— 解析层（tokenizer + parser + 第一遍全量校验）═══
// 职责：把用户 shell 文本解析为纯数据结构（语句 / 条件链 / 管线 / 重定向），并完成
//   第一遍全量校验——未知命令与不支持语法在此整段拒绝（抛 ShellError），通过后才有执行。
// 依赖方向：parse ← commands ← run（三件按序拼接为同一段脚本执行；本件只用自身符号。
//   校验函数 __shellValidate 的命令名集合由 run.js 调用时以参数传入——零反向引用）。
// ★P0 说明：本资产是宿主持有的只读 JS 资产（随应用包经 rawfile 分发，用户不可改）；
//   用户文本只作数据流经本件（字符串扫描），永不进入任何可执行位置——本件零动态执行、
//   零源码拼接。用户文本被动态执行 = shell 注入升级为 JS 注入，沙箱能力边界即失效。
// 支持面：管道 |、条件连接 && 与 ||、单双引号、$name 与 ${name} 与 $?、> 与 >> 重定向、
//   * 与 ? 通配符。不支持（整段拒绝且一条不执行）：分号 ;、后台 &、命令替换 $() 与
//   反引号、here-doc <<、输入重定向 <、进程替换 <(、循环与条件关键字（for / while /
//   until / if / case 等，以词起始的语句即拒）。
// 词法细节：\r\n 与 \n 等价；反斜杠转义只支持 \$ \" \\ 三枚（最小集，其余 \x 原样保留）；
//   双引号内可展开变量，单引号内全字面；引号段与裸字面可同词拼接（a"b"c = abc）。
// 通配符展开规则（run.js 执行）：词含 * 或 ? 且全部来自非引号字面段、且无变量段时按
//   通配模式处理（引号内不展开；含变量或引号段的词按字面）。
// 命令名限制：命令名必须是纯字面词（不能是变量引用或通配符形态）——首遍即拒（静态判
//   不了命令名，与「整段拒绝且一条不执行」口径一致）。

// ── 错误构造（ShellError：name 进回执 errorName，message 为中文拒绝原因含行号）──
function __shellLineError(line, message) {
  var e = new Error('第 ' + line + ' 行：' + message);
  e.name = 'ShellError';
  return e;
}

// ── UTF-8 字节数（如实口径：非 ASCII 按真实字节计，代理对按 4 字节）──
function __shellUtf8Len(text) {
  var bytes = 0;
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i);
    if (c < 0x80) {
      bytes += 1;
    } else if (c < 0x800) {
      bytes += 2;
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length &&
      text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

// ── UTF-8 前缀截断（按字节上限取最长前缀，不劈多字节字符）──
function __shellUtf8Prefix(text, maxBytes) {
  var bytes = 0;
  var i = 0;
  while (i < text.length) {
    var c = text.charCodeAt(i);
    var size = 1;
    if (c < 0x80) {
      size = 1;
    } else if (c < 0x800) {
      size = 2;
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length &&
      text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) {
      size = 4;
    } else {
      size = 3;
    }
    if (bytes + size > maxBytes) {
      break;
    }
    bytes += size;
    i += size === 4 ? 2 : 1;
  }
  return text.substring(0, i);
}

// ── 通配符匹配（* 任意长含空、? 恰一字符；迭代双指针，无回溯爆炸）──
function __shellGlobMatch(pattern, text) {
  var p = 0;
  var t = 0;
  var star = -1;
  var mark = 0;
  while (t < text.length) {
    if (p < pattern.length &&
      (pattern.charAt(p) === '?' || pattern.charAt(p) === text.charAt(t))) {
      p++;
      t++;
    } else if (p < pattern.length && pattern.charAt(p) === '*') {
      star = p;
      mark = t;
      p++;
    } else if (star >= 0) {
      p = star + 1;
      mark++;
      t = mark;
    } else {
      return false;
    }
  }
  while (p < pattern.length && pattern.charAt(p) === '*') {
    p++;
  }
  return p === pattern.length;
}

// ── 循环与条件关键字（语句首词命中即整段拒绝）──
var SHELL_KEYWORDS = {
  for: 1, while: 1, until: 1, do: 1, done: 1, if: 1, then: 1, elif: 1, else: 1,
  fi: 1, case: 1, esac: 1, in: 1, function: 1, select: 1, '{': 1, '}': 1
};

// ── 常见系统命令的「暂不支持」专句（mkdir / rm / mv 首批不注册，用到即整段拒绝）──
var SHELL_UNSUPPORTED = {
  mkdir: '模拟 Shell 的临时区不能创建目录',
  rm: '模拟 Shell 不能删除文件',
  mv: '模拟 Shell 不能移动或改名文件'
};

// ── 词法：文本 → 词元流 ──
// 词元：{type:'word', parts:[段], line, glob} | {type:'op', v:'|'|'||'|'&&'|'>'|'>>', line}
//      | {type:'nl', line}
// 段：{t:'lit', q:布尔(是否引号来源), v:文本} | {t:'var', name} | {t:'exit'}（=$?）
function __shellTokenize(text) {
  var tokens = [];
  var line = 1;
  var i = 0;
  var n = text.length;
  var cur = null; // { parts: [], line, lit, litQ }

  function openWord() {
    if (cur === null) {
      cur = { parts: [], line: line, lit: '', litQ: false };
    }
  }
  function closeWordLit() {
    if (cur !== null && cur.lit !== '') {
      cur.parts.push({ t: 'lit', q: cur.litQ, v: cur.lit });
      cur.lit = '';
    }
  }
  function addLit(ch, q) {
    openWord();
    if (cur.lit !== '' && cur.litQ !== q) {
      closeWordLit();
    }
    cur.litQ = q;
    cur.lit += ch;
  }
  function addQuoted(s) {
    openWord();
    closeWordLit();
    cur.parts.push({ t: 'lit', q: true, v: s }); // 空串也入段——空词不可丢
  }
  function addVar(name) {
    openWord();
    closeWordLit();
    cur.parts.push({ t: 'var', name: name });
  }
  function addExit() {
    openWord();
    closeWordLit();
    cur.parts.push({ t: 'exit' });
  }
  function endWord() {
    if (cur === null) {
      return;
    }
    closeWordLit();
    var glob = false;
    var hasDyn = false;
    for (var k = 0; k < cur.parts.length; k++) {
      var pt = cur.parts[k];
      if (pt.t === 'lit') {
        if (!pt.q && (pt.v.indexOf('*') >= 0 || pt.v.indexOf('?') >= 0)) {
          glob = true;
        }
      } else {
        hasDyn = true;
      }
    }
    tokens.push({ type: 'word', parts: cur.parts, line: cur.line,
      glob: glob && !hasDyn });
    cur = null;
  }
  function pushOp(v, atLine) {
    endWord();
    tokens.push({ type: 'op', v: v, line: atLine });
  }
  function pushNewline() {
    endWord();
    tokens.push({ type: 'nl', line: line });
  }
  // 变量引用探测（不落段）：$? / ${name} / $name；非引用形态返回 null。畸形形态就地抛错
  function scanVarRef(at) {
    if (at + 1 >= n) {
      return null;
    }
    var c1 = text.charAt(at + 1);
    if (c1 === '(') {
      throw __shellLineError(line, '不支持命令替换（$(），请改用其他写法。');
    }
    if (c1 === '?') {
      return { t: 'exit', next: at + 2 };
    }
    if (c1 === '{') {
      var close = text.indexOf('}', at + 2);
      if (close < 0) {
        throw __shellLineError(line, '变量引用没有闭合，缺少 }。');
      }
      var vn = text.substring(at + 2, close);
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(vn)) {
        throw __shellLineError(line, '变量名只能包含字母、数字与下划线。');
      }
      return { t: 'var', name: vn, next: close + 1 };
    }
    var m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.substring(at + 1));
    if (m !== null) {
      return { t: 'var', name: m[0], next: at + 1 + m[0].length };
    }
    return null;
  }
  function applyVarRef(ref) {
    if (ref.t === 'exit') {
      addExit();
    } else {
      addVar(ref.name);
    }
  }

  while (i < n) {
    var c = text.charAt(i);
    if (c === '\n') {
      line++;
      i++;
      pushNewline();
      continue;
    }
    if (c === '\r') {
      if (i + 1 < n && text.charAt(i + 1) === '\n') {
        i++;
      }
      line++;
      i++;
      pushNewline();
      continue;
    }
    if (c === ' ' || c === '\t') {
      endWord();
      i++;
      continue;
    }
    if (c === '|') {
      if (i + 1 < n && text.charAt(i + 1) === '|') {
        pushOp('||', line);
        i += 2;
      } else {
        pushOp('|', line);
        i++;
      }
      continue;
    }
    if (c === '&') {
      if (i + 1 < n && text.charAt(i + 1) === '&') {
        pushOp('&&', line);
        i += 2;
        continue;
      }
      throw __shellLineError(line, '不支持后台执行（&），请去掉单独的 & 后重试。');
    }
    if (c === '>') {
      if (i + 1 < n && text.charAt(i + 1) === '>') {
        pushOp('>>', line);
        i += 2;
      } else {
        pushOp('>', line);
        i++;
      }
      continue;
    }
    if (c === '<') {
      if (i + 1 < n && text.charAt(i + 1) === '<') {
        throw __shellLineError(line, '不支持 here-doc（<<），请改用其他写法。');
      }
      if (i + 1 < n && text.charAt(i + 1) === '(') {
        throw __shellLineError(line, '不支持进程替换（<(），请改用其他写法。');
      }
      throw __shellLineError(line, '不支持输入重定向（<），本模拟 Shell 只支持 > 与 >> 输出重定向。');
    }
    if (c === ';') {
      throw __shellLineError(line, '不支持分号分隔（;），请用换行分隔多条命令。');
    }
    if (c === '`') {
      throw __shellLineError(line, '不支持命令替换（反引号），请改用其他写法。');
    }
    if (c === "'") {
      i++;
      var sq = '';
      while (i < n && text.charAt(i) !== "'") {
        if (text.charAt(i) === '\n') {
          line++;
        }
        sq += text.charAt(i);
        i++;
      }
      if (i >= n) {
        throw __shellLineError(line, '单引号没有闭合。');
      }
      i++;
      addQuoted(sq);
      continue;
    }
    if (c === '"') {
      i++;
      var qlit = '';
      while (i < n) {
        var d = text.charAt(i);
        if (d === '"') {
          break;
        }
        if (d === '\n') {
          line++;
          qlit += d;
          i++;
          continue;
        }
        if (d === '\\') {
          var dx = i + 1 < n ? text.charAt(i + 1) : '';
          if (dx === '"' || dx === '$' || dx === '\\') {
            qlit += dx;
            i += 2;
            continue;
          }
          qlit += '\\';
          i++;
          continue;
        }
        if (d === '$') {
          var qref = scanVarRef(i);
          if (qref === null) {
            qlit += '$';
            i++;
            continue;
          }
          if (qlit !== '') {
            addQuoted(qlit); // 变量前的引号字面先落段（保顺序）
            qlit = '';
          }
          applyVarRef(qref);
          i = qref.next;
          continue;
        }
        qlit += d;
        i++;
      }
      if (i >= n) {
        throw __shellLineError(line, '双引号没有闭合。');
      }
      i++;
      addQuoted(qlit);
      continue;
    }
    if (c === '$') {
      var ref = scanVarRef(i);
      if (ref === null) {
        addLit('$', false);
        i++;
        continue;
      }
      applyVarRef(ref);
      i = ref.next;
      continue;
    }
    if (c === '\\') {
      var bx = i + 1 < n ? text.charAt(i + 1) : '';
      if (bx === '$' || bx === '"' || bx === '\\') {
        addLit(bx, false);
        i += 2;
        continue;
      }
      addLit('\\', false);
      i++;
      continue;
    }
    addLit(c, false);
    i++;
  }
  endWord();
  return tokens;
}

// ── 语法：词元流 → 语句数组 ──
// 语句：{kind:'assign', line, assigns:[{name, valueParts}]}
//      |{kind:'cmd', line, chain:[{op:'&&'|'||'|null, pipeline:{segments, redirect}}]}
// 段：{line, words}（首词 = 命令名）；redirect：{kind:'>'|'>>', word} | null
function __shellParseScript(text) {
  var tokens = __shellTokenize(text);
  var statements = [];
  var pos = 0;

  function peek() {
    return pos < tokens.length ? tokens[pos] : null;
  }

  // 赋值词识别：首个段是非引号字面且以「标识符=」开头 → {name, valueParts}
  function assignOf(word) {
    if (word.parts.length === 0) {
      return null;
    }
    var first = word.parts[0];
    if (first.t !== 'lit' || first.q) {
      return null;
    }
    var eq = first.v.indexOf('=');
    if (eq <= 0) {
      return null;
    }
    var name = first.v.substring(0, eq);
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
      return null;
    }
    var valueParts = [];
    var rest = first.v.substring(eq + 1);
    if (rest !== '') {
      valueParts.push({ t: 'lit', q: false, v: rest });
    }
    for (var k = 1; k < word.parts.length; k++) {
      valueParts.push(word.parts[k]);
    }
    return { name: name, valueParts: valueParts };
  }

  // 管线：段列表（| 分段）+ 可选重定向（限管线末位之后）
  function parsePipeline() {
    var segments = [];
    while (true) {
      var words = [];
      var segLine = 0;
      while (true) {
        var w = peek();
        if (w === null || w.type !== 'word') {
          break;
        }
        if (words.length === 0) {
          segLine = w.line;
        }
        words.push(w);
        pos++;
      }
      if (words.length === 0) {
        var bad = peek();
        var badLine = bad !== null ? bad.line :
          (segments.length > 0 ? segments[segments.length - 1].line : 1);
        if (segments.length === 0 && bad !== null && bad.type === 'op' &&
          (bad.v === '&&' || bad.v === '||')) {
          throw __shellLineError(badLine, '连接符（' + bad.v + '）的两侧都需要完整的命令。');
        }
        if (bad === null || bad.type === 'nl') {
          throw __shellLineError(badLine, '管道或连接符的后面缺少命令。');
        }
        throw __shellLineError(badLine, '管道符号（|）的两侧都需要完整的命令。');
      }
      segments.push({ line: segLine, words: words });
      var t = peek();
      if (t !== null && t.type === 'op' && t.v === '|') {
        pos++;
        continue;
      }
      break;
    }
    var redirect = null;
    var t2 = peek();
    if (t2 !== null && t2.type === 'op' && (t2.v === '>' || t2.v === '>>')) {
      pos++;
      var tw = peek();
      if (tw === null || tw.type !== 'word') {
        throw __shellLineError(t2.line, '重定向（' + t2.v + '）后面缺少目标文件名。');
      }
      redirect = { kind: t2.v, word: tw };
      pos++;
      var t3 = peek();
      if (t3 !== null && t3.type === 'op' && t3.v === '|') {
        throw __shellLineError(t3.line, '重定向只能放在管线的最后，请把重定向移到管道的末尾。');
      }
    }
    return { segments: segments, redirect: redirect };
  }

  while (true) {
    var t = peek();
    if (t === null) {
      break;
    }
    if (t.type === 'nl') {
      pos++;
      continue;
    }
    if (t.type === 'op') {
      throw __shellLineError(t.line, '命令不能以「' + t.v + '」开头。');
    }
    var asg = assignOf(t);
    if (asg !== null) {
      var assigns = [];
      while (true) {
        var w2 = peek();
        if (w2 === null || w2.type === 'nl') {
          break;
        }
        if (w2.type !== 'word') {
          throw __shellLineError(w2.line, '赋值语句请单独成行。');
        }
        var a2 = assignOf(w2);
        if (a2 === null) {
          throw __shellLineError(w2.line, '赋值语句不支持带空格的值，请用引号包住值，例如 x="a b"。');
        }
        assigns.push(a2);
        pos++;
      }
      statements.push({ kind: 'assign', line: t.line, assigns: assigns });
      continue;
    }
    var chain = [];
    var op = null;
    while (true) {
      var pipeline = parsePipeline();
      chain.push({ op: op, pipeline: pipeline });
      var nx = peek();
      if (nx !== null && nx.type === 'op' && (nx.v === '&&' || nx.v === '||')) {
        op = nx.v;
        pos++;
        continue;
      }
      break;
    }
    statements.push({ kind: 'cmd', line: t.line, chain: chain });
    var after = peek();
    if (after !== null && after.type !== 'nl') {
      throw __shellLineError(after.line, '命令之间请用换行或 && 与 || 连接。');
    }
  }
  return { statements: statements };
}

// ── 词级工具：纯字面拼接（含引号段；遇变量段返回 null——命令名与模式判定共用）──
function __shellPlainWord(word) {
  var out = '';
  for (var i = 0; i < word.parts.length; i++) {
    var p = word.parts[i];
    if (p.t !== 'lit') {
      return null;
    }
    out += p.v;
  }
  return out;
}

// ── 第一遍全量校验（run.js 在解析后、执行前调用；任一不合即抛——整段拒绝且一条不执行）──
function __shellValidate(script, commandNames) {
  // 通配模式不能含斜杠（临时区平铺、无子目录——与宿主名称闸同界）
  function checkGlobSlash(word) {
    if (!word.glob) {
      return;
    }
    var pat = __shellPlainWord(word);
    if (pat !== null && pat.indexOf('/') >= 0) {
      throw __shellLineError(word.line, '通配模式不能包含斜杠，临时区没有子目录。');
    }
  }
  for (var s = 0; s < script.statements.length; s++) {
    var stmt = script.statements[s];
    if (stmt.kind !== 'cmd') {
      continue;
    }
    for (var c = 0; c < stmt.chain.length; c++) {
      var pipeline = stmt.chain[c].pipeline;
      for (var g = 0; g < pipeline.segments.length; g++) {
        var seg = pipeline.segments[g];
        var w0 = seg.words[0];
        var name = __shellPlainWord(w0);
        if (name === null) {
          throw __shellLineError(w0.line, '命令名不能使用变量或通配符。');
        }
        if (name === '') {
          throw __shellLineError(w0.line, '命令名不能为空。');
        }
        if (SHELL_KEYWORDS[name] === 1) {
          throw __shellLineError(w0.line,
            '不支持「' + name + '」语句，本模拟 Shell 不支持循环与条件语句。');
        }
        // own 判定而非 `!== undefined`（★ 2026-10-07 复核轮修复）：普通 {} 的继承成员名
        // （constructor / toString / valueOf 等）会让 `!== undefined` 误真——把原型成员
        // 当「暂不支持」命令并拼出函数源码（实测 constructor 报错句含 [native code]）
        if (Object.prototype.hasOwnProperty.call(SHELL_UNSUPPORTED, name)) {
          throw __shellLineError(w0.line, name + ' 暂不支持，' + SHELL_UNSUPPORTED[name] + '。');
        }
        if (commandNames[name] !== true) {
          throw __shellLineError(w0.line,
            '不支持命令「' + name + '」，可用命令用 help 查看。');
        }
        for (var ww = 1; ww < seg.words.length; ww++) {
          checkGlobSlash(seg.words[ww]);
        }
      }
      if (pipeline.redirect !== null) {
        var rw = pipeline.redirect.word;
        if (rw.glob) {
          throw __shellLineError(rw.line, '重定向的目标文件名不能用通配符。');
        }
        checkGlobSlash(rw);
      }
    }
  }
}
