// bin 入口运行器（2026-11-24 鸿蒙 Node 运行时门 3 U3 S4，任务书-鸿蒙Node运行时门3 U3-binrunner
// -20261124 §5 S4）：按 bin 台账把一个已装包的命令行入口在本会话 worker 内跑一轮。
// · 形态依据（任务书 §1 三探针回执，不重议）：硬链接与符号链接都 EACCES ⇒ 不造 .bin 目录、不建
//   链接；子进程不可用（spawnSync /bin/sh EACCES）⇒ 不 spawn、不用 shebang、不走 PATH；故唯一
//   可行路径 = 当前 worker 内 Module._load(entry, null, true)（isMain=true 让 require.main ===
//   module 成立，与真进程入口一致）。不生成 wrapper 文件——多一层文件就多一层回滚与残留面。
// · 六项语义（逐项对应任务书）：
//   ① 解析：读台账 → 过滤条目缺失（包目录已消失即按缺失，不猜别的包）→ 拼绝对入口 → 存在性
//      校验（ENOENT → bin-missing）。
//   ② CJS 闸：扩展名优先——.mjs 恒 ESM、.cjs 恒 CJS（不受包 type 与首屏探测影响）；其余按包
//      type === 'module' / 入口首屏**行首**静态 import·export·import.meta 判据命中即
//      bin-esm-unsupported（动态 import(...) 在 CJS 合法，不计入）。**本闸首先是产品代决「只收
//      CommonJS 入口」的落点**，但有技术支撑：宿主 Node 24 的 require(esm) 实测能加载 .mjs、
//      无 type 的 export 件、甚至含顶层 await 的模块，然而 ESM 求值是异步的——Module._load 已
//      返回、轮捕获已收口，输出才落地（2026-11-24 实测：同步段捕获为零、回执「成功但无输出」）。
//      故文案按「暂不支持」写，不得声称会抛 SyntaxError。
//   ③ argv：保存并替换 process.argv = [process.execPath, entryAbs, ...args]；argv0 不动。
//   ④ require.main：Module._load(entryAbs, null, true)；跑前 delete require.cache[entryAbs]
//      （只清入口自身，不递归清 node_modules；但 bin 轮结束即回收 worker，进程级缓存随线程消失，
//      该项不再跨轮——见下方「隔离口径」）。
//   ⑤ exit 语义：替换 process.exit 为只抛哨兵的形态；捕获哨兵 → exitCode = 它带的值；自然
//      返回 → exitCode = process.exitCode ?? 0；finally 还原 argv / exit / exitCode。
//   ⑥ 异常隔离：同步抛错 → ok=false + error='bin-error' + error.code/message（跨 realm，判据
//      只认 e.code，禁 instanceof）；输出走 session-worker 既有每轮捕获（console 与
//      process.stdout.write 均覆盖）。
// · 隔离口径（2026-11-24 补正）：bin 内 require 拿到的是原生模块，不经过会话轮注入的包装视图，
//   定时器 / socket / 未决 fs / process 监听都不在轮末观测面内。故 bin 轮结束后由 bootstrap 一律
//   回收该会话 worker（terminate + 下轮冷启，见 bootstrap.js runExec 的 bin-reset 分支），残留随
//   线程消失——require.cache 只清入口的限制因此也不再跨轮。代价两项均如实登记：bin 内未完成的
//   异步尾巴被砍（与 exec「轮末不许留后台」同口径）、每轮多一次 worker 冷启。
// · 本件被 session-worker.js 在 run_bin 轮懒加载（设备侧 HOME 内相对解析）；非 worker 环境
//   零副作用（只导出纯函数，不启动监听、不写文件，可本机直跑）。
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');

// 台账结构版本（与 npm-scan.BIN_LEDGER_VERSION 同源事实；不符按可读处理，不做迁移）
const LEDGER_VERSION = 1;
// CJS 闸的入口首屏字节数（静态 import/export 探测面；只读这么长，不整件读）
const ESM_PROBE_BYTES = 2048;
// 入口文件体积上限（防异常台账把宿主指向超大件；正常 CLI 入口几十 KB 量级）
const ENTRY_MAX_BYTES = 8 * 1024 * 1024;

// 台账读取（缺件 / 坏 JSON / 结构不符一律 null——调用方回 bin-missing，不造差异文案）
function readBinLedger(ledgerPath) {
  let text = '';
  try {
    text = fs.readFileSync(ledgerPath, 'utf8');
  } catch (e) {
    return null;
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed === null || typeof parsed !== 'object') {
      return null;
    }
    if (parsed.bins === null || typeof parsed.bins !== 'object') {
      return null;
    }
    return parsed;
  } catch (e) {
    return null;
  }
}

function ledgerEntryOf(ledger, name) {
  if (ledger === null) {
    return null;
  }
  // 只认台账自有键（坑98：__proto__ / constructor 等原型链成员名不得读成继承值）
  if (!Object.prototype.hasOwnProperty.call(ledger.bins, name)) {
    return null;
  }
  const entry = ledger.bins[name];
  return entry !== null && entry !== undefined && typeof entry === 'object' ? entry : null;
}

// package.json 读取（只取 type 判据，坏 JSON 按无 type 处理）
function readPackageType(packageDir) {
  try {
    const meta = JSON.parse(fs.readFileSync(path.join(packageDir, 'package.json'), 'utf8'));
    return meta !== null && typeof meta === 'object' && typeof meta.type === 'string'
      ? meta.type : '';
  } catch (e) {
    return '';
  }
}

// 入口所属包目录（从入口目录逐级上溯到 node_modules 根内最近的 package.json 所在目录）。
// 嵌套依赖（node_modules/a/node_modules/b）与 @scope 两形态都由上溯天然覆盖
function packageDirOf(entryAbs, prefix) {
  const root = path.join(prefix, 'node_modules');
  let dir = path.dirname(entryAbs);
  while (dir.length > root.length && dir.indexOf(root) === 0) {
    if (fs.existsSync(path.join(dir, 'package.json'))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      break;
    }
    dir = parent;
  }
  return null;
}

// 入口静态 import / export 探测（只读首 2 KiB）。**行首启发式**：按行首关键词判，躲开字符串里的
// 同名词；行内的 import.meta / export（如 `const u = import.meta.url`）不拦——这类文件在宿主
// Node 24 上经 require(esm) 能跑，但求值异步、输出会越出轮捕获窗口（回执空），属已知偏差。
// 三处边界（2026-11-24 实测）：动态 import(...) 在 CJS 合法（懒加载常用），不计入；
// import.meta 与顶层 export 是 ESM 语法，按代决计入（技术理由见文件头 ②）
function looksLikeEsm(source) {
  const lines = source.slice(0, ESM_PROBE_BYTES).split('\n');
  for (const line of lines) {
    const text = line.trim();
    if (text === '' || text.startsWith('//') || text.startsWith('*') || text.startsWith('/*')) {
      continue;
    }
    if (/^import\s*[{*'"]/.test(text) || /^import\s+[A-Za-z_$]/.test(text)
      || /^import\s*\./.test(text)) {
      return true;
    }
    if (/^export\s/.test(text)) {
      return true;
    }
  }
  return false;
}

function esmReject(name) {
  return {
    ok: false,
    error: 'bin-esm-unsupported',
    detail: '命令 ' + name + ' 只支持 CommonJS 入口，这个包提供的是 ES 模块入口，暂不能运行。'
  };
}

// ①解析 + ②CJS 闸：返回 { ok:true, abs, entry } 或 { ok:false, error, detail }
function resolveBin(options) {
  const name = typeof options.name === 'string' ? options.name : '';
  const prefix = typeof options.prefix === 'string' ? options.prefix : '';
  if (name === '' || prefix === '') {
    return { ok: false, error: 'bin-missing', detail: '命令名或安装区路径缺失。' };
  }
  const ledger = readBinLedger(options.ledgerPath);
  if (ledger === null) {
    return {
      ok: false,
      error: 'bin-missing',
      detail: '安装记录还不存在，先安装提供命令 ' + name + ' 的包。'
    };
  }
  if (ledger.version !== undefined && ledger.version !== LEDGER_VERSION) {
    return {
      ok: false,
      error: 'bin-missing',
      detail: '安装记录版本不认识，重新安装一次即可重建。'
    };
  }
  const entry = ledgerEntryOf(ledger, name);
  if (entry === null) {
    return {
      ok: false,
      error: 'bin-missing',
      detail: '安装记录里没有命令 ' + name + '，先安装提供它的包。'
    };
  }
  const relative = typeof entry.entry === 'string' ? entry.entry : '';
  const segments = relative.split(/[\\/]+/);
  if (relative === '' || path.isAbsolute(relative) || segments.indexOf('..') >= 0) {
    return { ok: false, error: 'bin-missing', detail: '安装记录里的入口路径不合法。' };
  }
  const abs = path.join(prefix, 'node_modules', relative);
  let stat = null;
  try {
    stat = fs.statSync(abs);
  } catch (e) {
    stat = null;
  }
  if (stat === null || !stat.isFile()) {
    // 读取侧过滤：包目录已消失（被卸载 / 回滚 / 换代）→ 按缺失处理
    return {
      ok: false,
      error: 'bin-missing',
      detail: '命令 ' + name + ' 对应的包已不在安装区，重新安装后再试。'
    };
  }
  if (stat.size > ENTRY_MAX_BYTES) {
    return { ok: false, error: 'bin-missing', detail: '命令 ' + name + ' 的入口文件异常偏大。' };
  }
  // ② CJS 闸（扩展名优先：.cjs 恒 CJS、.mjs 恒 ESM，两者不受包 type 与首屏探测影响——2026-11-24
  //   实测 type:module 包内 .cjs 入口曾被误拒；其余走台账快判 → 包 type → 首屏三判据，运行时
  //   再核一遍防包被替换）
  const ext = path.extname(abs).toLowerCase();
  if (ext === '.mjs') {
    return esmReject(name);
  }
  if (ext !== '.cjs') {
    if (entry.cjs === false) {
      return esmReject(name);
    }
    const packageDir = packageDirOf(abs, prefix);
    if (packageDir !== null && readPackageType(packageDir) === 'module') {
      return esmReject(name);
    }
    let head = '';
    try {
      head = fs.readFileSync(abs, 'utf8');
    } catch (e) {
      head = '';
    }
    if (looksLikeEsm(head)) {
      return esmReject(name);
    }
  }
  return { ok: true, abs: abs, entry: entry };
}

// 异常串化（跨 realm 安全：只读字段，不判 instanceof）
function describeError(e) {
  if (e !== null && typeof e === 'object') {
    if (typeof e.stack === 'string' && e.stack !== '') {
      return e.stack;
    }
    if (typeof e.message === 'string' && e.message !== '') {
      const name = typeof e.name === 'string' && e.name !== '' ? e.name : 'Error';
      return name + ': ' + e.message;
    }
  }
  try {
    return String(e);
  } catch (err) {
    return '未知错误';
  }
}

// 跑一轮 bin：同步执行（Module._load 是同步语义），终态一律用返回值表达，不外抛
function runBin(options) {
  const startAt = Date.now();
  const name = typeof options.name === 'string' ? options.name : '';
  const args = Array.isArray(options.args) ? options.args.map((item) => String(item)) : [];
  const resolved = resolveBin({
    prefix: options.prefix,
    ledgerPath: options.ledgerPath,
    name: name
  });
  if (!resolved.ok) {
    return {
      ok: false,
      bin: name,
      exitCode: 1,
      durationMs: Date.now() - startAt,
      error: resolved.error,
      errorCode: resolved.error,
      errorDetail: resolved.detail,
      packageName: '',
      replaced: false
    };
  }
  const entryInfo = resolved.entry;
  const savedArgv = process.argv;
  const savedExit = process.exit;
  const savedExitCode = process.exitCode;
  // Module._load(isMain=true) 会把 process.mainModule 指向 bin 入口（实测 Node 24），
  // 它同时是后续 createRequire 视图里 require.main 的来源——不还原就把 bin 变成「主模块」，
  // 跨轮污染用户代码对 require.main 的判断
  const savedMainModule = process.mainModule;
  let exitCode = 0;
  let ok = true;
  let error = '';
  let errorCode = '';
  let errorDetail = '';
  // ③ argv：与真进程入口同形（argv[0] = execPath，argv[1] = 入口绝对路径）；argv0 不动
  process.argv = [process.execPath, resolved.abs].concat(args);
  // ⑤ exit 语义：先清掉上一轮可能残留的退出码，让自然返回的默认值是 0
  process.exitCode = undefined;
  process.exit = function binExit(code) {
    const marker = new Error('bin-exit');
    marker.__binExit = true;
    if (typeof code === 'number' && Number.isFinite(code)) {
      marker.exitCode = code;
    } else if (typeof process.exitCode === 'number') {
      marker.exitCode = process.exitCode;
    } else {
      marker.exitCode = 0;
    }
    throw marker;
  };
  try {
    // ④ 只清入口自身缓存（代决：不递归清 node_modules）
    delete require.cache[resolved.abs];
    Module._load(resolved.abs, null, true);
    exitCode = typeof process.exitCode === 'number' ? process.exitCode : 0;
  } catch (e) {
    if (e !== null && typeof e === 'object' && e.__binExit === true) {
      exitCode = typeof e.exitCode === 'number' ? e.exitCode : 1;
    } else {
      // ⑥ 异常隔离：错误码判据只认 e.code（跨 realm 禁 instanceof）
      ok = false;
      exitCode = 1;
      error = 'bin-error';
      errorCode = e !== null && typeof e === 'object' && typeof e.code === 'string' ? e.code : '';
      errorDetail = describeError(e);
    }
  } finally {
    process.argv = savedArgv;
    process.exit = savedExit;
    process.exitCode = savedExitCode;
    process.mainModule = savedMainModule;
  }
  return {
    ok: ok,
    bin: name,
    exitCode: exitCode,
    durationMs: Date.now() - startAt,
    error: error,
    errorCode: errorCode,
    errorDetail: errorDetail,
    packageName: typeof entryInfo.package === 'string' ? entryInfo.package : '',
    replaced: entryInfo.replaced === true
  };
}

module.exports = {
  runBin,
  resolveBin,
  readBinLedger,
  LEDGER_VERSION
};
