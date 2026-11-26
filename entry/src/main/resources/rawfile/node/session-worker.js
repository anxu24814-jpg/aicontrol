// 会话执行域 worker 内核（2026-11-23 鸿蒙 Node 运行时门 2 U3a 笔，任务书
// -鸿蒙Node运行时门2-20261123 §3.3「worker、状态、cwd 与取消」/§4 S3 第 1 项）。
// · 角色：bootstrap 控制面按 sessionId 建一个长期 worker（本文件）；worker 内持有一个长期
//   vm context（同会话跨轮保留顶层变量、函数与 require.cache）。主线程逐轮经 parentPort 发
//   {type:'run', requestId, code, cwd, timeoutMs}，本文件回 {type:'result', ...}。
// · 上下文注入：真实 process / Buffer / module / exports / __filename / __dirname / console /
//   print / save / require（由 createRequire(path.join(cwd,'.exec-node-entry.cjs')) 生成）+
//   Node 全局面（定时器、URL、TextEncoder/Decoder、fetch、crypto 等）。vm 语义：顶层
//   let/const/class 跨轮保留且同名重声明抛 SyntaxError（与 desc 一致），var 可重声明。
// · require 双基点回退（门 3 U1 方案档 ⑬）：会话临时区向上的 CJS 祖先链不含 filesDir/node/，
//   会话 code 直接 require('pkg') 天然不可达——先按会话临时区基点解析，MODULE_NOT_FOUND 再按
//   <filesDir>/node/node_modules/.exec-node-entry.cjs 基点解析一次（createRequire 双基点均为
//   标准 CJS 形态；基点经 bootstrap workerData 传入）。禁 NODE_PATH 运行时注入作主机制
//   （语义未验）。回退仍失败抛回退侧错误（路径即安装落点，报错可归因）。
//   ★ 回退触发面收窄（本轮）：只对**裸说明符**（不以 . / / 开头，非 node: 内置）且失败发生在
//   会话代码**顶层**（requireStack 长度 ≤1）的 MODULE_NOT_FOUND 回退——相对路径缺失不跨基点
//   解析，包内自身缺依赖也原样上抛，不拿安装落点的同名包顶替；require.resolve 同规则。
// · 输出捕获：console.*、print、process.stdout.write、process.stderr.write 全部经每轮临时
//   替换的 process.stdout/stderr.write 收口（console 与 print 都写这两条流）；stdout/stderr
//   各最多保留 1 MiB，保头截尾并带截断标记；轮末恢复原钩子、清掉本轮新建定时器——本轮之后
//   的输出不会混入下一轮。
// · 审计 events：best-effort 记录文件写与 http/https/net/fetch 网络调用，上限 50 条，回执只
//   带前 10 条（eventsTotal 报真实条数）。**事件只是可观测，可观测不是安全边界**——不宣称
//   网络、文件或进程强隔离，绕过本注入面（例如直接走原生 fd、child_process、tls 直连）的后
//   台句柄不在保证内。
// · 后台句柄：fs 异步调用、文件流、http/https 请求、net socket/server、fetch 均计入待决计数；
//   轮末若待决数 > 0，本文件在 result 里报 backgroundOps，主线程 terminate 本会话 worker 并
//   按 terminated-background 回终态（cwd 是进程级，遗留回调拖到别的会话轮内触发相对路径 I/O
//   会落进他人临时区，故只能整会话作废）。
// · save(name)：只登记本会话 cwd 内的相对文件路径，拒绝绝对路径、`..`、目录不存在、符号链接
//   逃逸与非普通文件；savedNames 每轮回执一次即清（转正由 ArkTS 侧 promoteSavedNames 统一做）。
// · bin 轮（门 3 U3，run_bin）：与 exec 轮并列、不合并——主线程发 {type:'run_bin', requestId,
//   bin, args, cwd, timeoutMs}，本文件在**同一套输出捕获与审计**下调用 bin-runner.runBin
//   （Module._load 入口，不 spawn），回执另带 bin / exitCode / binPackage / binReplaced 四字段。
//   运行器与台账路径由 bootstrap 经 workerData 注入（HOME 与安装落点根）。
//   ★ 边界（2026-11-24 补正）：bin 内 require 拿到的是原生模块，不经本文件注入的包装视图，故
//   定时器 / socket / 未决 fs / process 监听都不在本文件的轮末清理面内、backgroundOps 也恒 0。
//   处置 = bootstrap 在该轮结束后整会话回收本 worker（terminate，下轮冷启），残留随线程消失；
//   本文件不做也不应做 bin 残留清理。timeoutMs 只由主线程看门狗消费（本文件与 runBin 均不读）。
// · 取消与超时：主线程 terminate 本 worker（worker 阻塞在死循环或 Atomics.wait 时同样有效），
//   本文件不需要协作式退出钩子；process.exit 只结束当前 worker（worker 语义天然如此），主
//   控制面按 crashed 建下一轮；process.abort 与 V8 原生崩溃可能拖垮宿主进程，不在恢复保证内。
// · worker 内不得 process.chdir（本 SDK / Node 报 ERR_WORKER_UNSUPPORTED_OPERATION）；cwd 由
//   主线程在 lane 内切换，worker 只读 process.cwd() 与轮内传入的 cwd（require 与 save 的锚点）。
'use strict';

const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const util = require('node:util');
const { createRequire } = require('node:module');
const workerThreads = require('node:worker_threads');

// 输出上限（stdout / stderr 各自独立）与审计事件上限（回执只带前 10 条）
const OUTPUT_LIMIT_BYTES = 1024 * 1024;
const EVENT_LIMIT = 50;
const REPLY_EVENT_LIMIT = 10;
// require 的锚点文件名（createRequire 只借它定位模块解析根，不需要真实存在）
const ENTRY_FILE_NAME = '.exec-node-entry.cjs';
// bin 轮（门 3 U3）：运行器与台账路径由 bootstrap 经 workerData 注入（HOME 内相对解析）
let binRunnerPath = '';
let binLedgerPath = '';
let binInstallRoot = '';
// npm 安装包回退解析基点（bootstrap 经 workerData 注入 = <filesDir>/node/node_modules/ 下
// 同名锚点文件；空串 = 未注入，无回退）
let npmRequireEntryPath = '';
// 回执文案（任务书 §3.3：必须写「可观测不是安全边界」）
const EVENTS_NOTE = '事件只是可观测，可观测不是安全边界';
// 截断标记（放在被截断那一侧的末尾；含「截断」字样供宿主如实转述）
const TRUNCATION_MARK = '\n……输出已截断，仅保留开头 ' + OUTPUT_LIMIT_BYTES + ' 字节\n';
// 事件行内路径等字段的长度上限（防单行撑爆回执）
const EVENT_DETAIL_MAX = 200;

// 当前轮状态（串行：主线程保证同一 worker 不会被并发投递两轮；本文件再做一次守卫）
let currentRound = null;
// 会话上下文（一个 worker 一个；cwd 变化时只重挂 require 与 __dirname/__filename）
let contextBox = null;
// 已跟踪、未结算的后台操作数（socket / http / 未决 fs / fetch）
let pendingOps = 0;

// 结构哨兵（落位自检与直接 require 探测用：非 worker 环境不启动任何监听）
function isWorkerThread() {
  return workerThreads.workerData !== null && workerThreads.workerData !== undefined;
}

// ── 后台操作计数 ──

function trackStart() {
  pendingOps++;
}

function trackDone() {
  if (pendingOps > 0) {
    pendingOps--;
  }
}

// ── 输出捕获 ──

// 按字节累积、保头截尾（越限后只置截断标志，不再拼接——尾部丢弃不占内存）
function createCapture(limitBytes) {
  const chunks = [];
  let kept = 0;
  let truncated = false;
  return {
    write(chunk, encoding) {
      const buffer = normalizeChunk(chunk, encoding);
      if (buffer.length === 0) {
        return;
      }
      const remaining = limitBytes - kept;
      if (remaining <= 0) {
        truncated = true;
        return;
      }
      const part = buffer.length > remaining ? buffer.subarray(0, remaining) : buffer;
      chunks.push(part);
      kept += part.length;
      if (part.length < buffer.length) {
        truncated = true;
      }
    },
    text() {
      const body = Buffer.concat(chunks, kept).toString('utf8');
      return truncated ? body + TRUNCATION_MARK : body;
    },
    isTruncated() {
      return truncated;
    }
  };
}

// 写入分片归一成 Buffer（字符串按 encoding 编码，非法 encoding 回落 utf8）
function normalizeChunk(chunk, encoding) {
  if (Buffer.isBuffer(chunk)) {
    return chunk;
  }
  if (chunk instanceof Uint8Array) {
    return Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
  }
  const effective = typeof encoding === 'string' && Buffer.isEncoding(encoding) ? encoding : 'utf8';
  return Buffer.from(String(chunk), effective);
}

// 每轮换掉 process.stdout/stderr.write（worker 内 process 是线程私有的，不影响宿主主线程）；
// 同时把回调异步放行，避免用户代码 await 写入回调时挂住
function installOutputHooks() {
  const originalStdoutWrite = process.stdout.write;
  const originalStderrWrite = process.stderr.write;
  process.stdout.write = function (chunk, encoding, callback) {
    if (currentRound !== null) {
      currentRound.stdout.write(chunk, encoding);
    }
    const cb = typeof encoding === 'function' ? encoding : callback;
    if (typeof cb === 'function') {
      queueMicrotask(cb);
    }
    return true;
  };
  process.stderr.write = function (chunk, encoding, callback) {
    if (currentRound !== null) {
      currentRound.stderr.write(chunk, encoding);
    }
    const cb = typeof encoding === 'function' ? encoding : callback;
    if (typeof cb === 'function') {
      queueMicrotask(cb);
    }
    return true;
  };
  return { stdout: originalStdoutWrite, stderr: originalStderrWrite };
}

function restoreOutputHooks(hooks) {
  process.stdout.write = hooks.stdout;
  process.stderr.write = hooks.stderr;
}

// ── 审计事件（best-effort，只作可观测） ──

function recordEvent(text) {
  if (currentRound === null) {
    return;
  }
  if (currentRound.events.length >= EVENT_LIMIT) {
    currentRound.eventsDropped++;
    return;
  }
  currentRound.events.push(shortenText(text, EVENT_DETAIL_MAX));
}

function shortenText(text, max) {
  const value = String(text);
  return value.length > max ? value.slice(0, max) + '…' : value;
}

// 事件里的目标描述（路径 / 文件描述符 / 非路径参数）
function describeTarget(value) {
  if (typeof value === 'string') {
    return shortenText(value, EVENT_DETAIL_MAX);
  }
  if (Buffer.isBuffer(value)) {
    return 'Buffer ' + value.length + ' 字节';
  }
  if (value instanceof URL) {
    return shortenText(value.href, EVENT_DETAIL_MAX);
  }
  if (typeof value === 'number') {
    return '文件描述符 ' + value;
  }
  return '非路径参数';
}

// ── 轮内定时器（轮末清理；setTimeout/setInterval/setImmediate 三族） ──

function registerTimer(kind, handle) {
  if (currentRound === null) {
    return;
  }
  currentRound.timers.add({ kind: kind, handle: handle });
}

function trackedSetTimeout(callback, delay, ...args) {
  let registration = null;
  const wrapped = (...callArgs) => {
    if (currentRound !== null && registration !== null) {
      currentRound.timers.delete(registration);
    }
    if (typeof callback === 'function') {
      callback(...callArgs);
    }
  };
  const handle = setTimeout(wrapped, delay, ...args);
  registration = { kind: 'timeout', handle: handle };
  registerTimer('timeout', handle);
  return handle;
}

function trackedSetInterval(callback, delay, ...args) {
  const handle = setInterval(callback, delay, ...args);
  registerTimer('interval', handle);
  return handle;
}

function trackedSetImmediate(callback, ...args) {
  let registration = null;
  const wrapped = (...callArgs) => {
    if (currentRound !== null && registration !== null) {
      currentRound.timers.delete(registration);
    }
    if (typeof callback === 'function') {
      callback(...callArgs);
    }
  };
  const handle = setImmediate(wrapped, ...args);
  registration = { kind: 'immediate', handle: handle };
  registerTimer('immediate', handle);
  return handle;
}

// 轮末清掉本轮新建的全部定时器（已 firing 的不在其中；clear 幂等）
function clearRoundTimers() {
  if (currentRound === null) {
    return;
  }
  for (const item of currentRound.timers) {
    if (item.kind === 'interval') {
      clearInterval(item.handle);
    } else if (item.kind === 'immediate') {
      clearImmediate(item.handle);
    } else {
      clearTimeout(item.handle);
    }
  }
  currentRound.timers.clear();
}

// ── require：按模块加强可观测与后台跟踪（视图按原模块对象缓存，node:fs 与 fs 同视图） ──

const MODULE_VIEW_CACHE = new Map();
const TRACKED_SOCKETS = new WeakSet();
const TRACKED_SERVERS = new WeakSet();
const TRACKED_SERVER_LISTENS = new WeakSet();

// 回调式 fs 函数（末参为回调）：调用即计后台，回调到即结算
const FS_CALLBACK_FUNCTIONS = [
  'access', 'appendFile', 'chmod', 'chown', 'close', 'copyFile', 'cp', 'fchmod', 'fchown',
  'fdatasync', 'fstat', 'fsync', 'ftruncate', 'futimes', 'lchmod', 'lchown', 'link', 'lstat',
  'lutimes', 'mkdir', 'mkdtemp', 'open', 'opendir', 'read', 'readFile', 'readdir', 'readlink',
  'readv', 'realpath', 'rename', 'rm', 'rmdir', 'stat', 'statfs', 'symlink', 'truncate',
  'unlink', 'utimes', 'write', 'writeFile', 'writev'
];
// 同步写族：只记审计事件（同步调用不构成后台等待）
const FS_SYNC_WRITE_FUNCTIONS = [
  'appendFileSync', 'chmodSync', 'chownSync', 'copyFileSync', 'cpSync', 'fchmodSync',
  'fchownSync', 'fsyncSync', 'ftruncateSync', 'futimesSync', 'lchmodSync', 'lchownSync',
  'linkSync', 'mkdirSync', 'mkdtempSync', 'openSync', 'renameSync', 'rmSync', 'rmdirSync',
  'symlinkSync', 'truncateSync', 'unlinkSync', 'utimesSync', 'writeFileSync', 'writeSync',
  'writevSync'
];
// promisified fs（fs/promises 与 fs.promises 同一对象）
const FS_PROMISE_FUNCTIONS = [
  'access', 'appendFile', 'chmod', 'chown', 'copyFile', 'cp', 'lchmod', 'lchown', 'link',
  'lstat', 'lutimes', 'mkdir', 'mkdtemp', 'open', 'opendir', 'read', 'readFile', 'readdir',
  'readlink', 'readv', 'realpath', 'rename', 'rm', 'rmdir', 'stat', 'statfs', 'symlink',
  'truncate', 'unlink', 'utimes', 'write', 'writeFile', 'writev'
];
// 会改盘的 fs 函数基名（去掉 Sync 后比对）→ 事件动词；未列出的写族（如 fsync）统一落「fs 写」
const FS_EVENT_VERBS = {
  unlink: 'fs 删除', rm: 'fs 删除', rmdir: 'fs 删除',
  rename: 'fs 改名',
  mkdir: 'fs 建目录', mkdtemp: 'fs 建目录',
  open: 'fs 打开'
};
// 除动词表外仍要记事件的写族基名
const FS_EVENT_EXTRA = [
  'appendFile', 'chmod', 'chown', 'copyFile', 'cp', 'fchmod', 'fchown', 'fdatasync', 'fsync',
  'ftruncate', 'futimes', 'lchmod', 'lchown', 'link', 'lutimes', 'symlink', 'truncate',
  'utimes', 'write', 'writeFile', 'writev'
];

function fsEventText(functionName) {
  const base = functionName.endsWith('Sync') ? functionName.slice(0, -4) : functionName;
  const verb = FS_EVENT_VERBS[base];
  if (verb !== undefined) {
    return verb;
  }
  return 'fs 写';
}

// 是否为要记事件的 fs 函数（只记写族；读不记）
function isFsEventFunction(functionName) {
  const base = functionName.endsWith('Sync') ? functionName.slice(0, -4) : functionName;
  return FS_EVENT_VERBS[base] !== undefined || FS_EVENT_EXTRA.indexOf(base) >= 0;
}

// MODULE_NOT_FOUND 判定（回退补位的触发条件之一；其他异常原样上抛）
function isModuleNotFound(e) {
  return e !== null && e !== undefined && typeof e === 'object' && e.code === 'MODULE_NOT_FOUND';
}

// 裸说明符（可回退的形态）：不以 . 或 / 开头，也不是 node: 内置。相对 / 绝对路径永不回退——
// 跨基点解析相对路径会命中安装落点里的同名包，把「用户自己的文件缺失」伪装成「模块缺依赖」
function isBareSpecifier(specifier) {
  if (typeof specifier !== 'string' || specifier === '') {
    return false;
  }
  if (specifier.startsWith('.') || specifier.startsWith('/')) {
    return false;
  }
  if (specifier.startsWith('node:')) {
    return false;
  }
  return true;
}

// 回退触发判据（收窄后）：MODULE_NOT_FOUND + 裸说明符 + 失败发生在会话代码**顶层**。
// 顶层判据 = requireStack 长度 ≤1：包（或本地文件）内部再 require 失败时栈里会多出那一层，
// 这种失败必须原样上抛给用户代码，不能拿安装落点的同名包去顶替（会静默换掉坏包并覆盖原错误）
function shouldFallbackRequire(e, specifier) {
  if (!isModuleNotFound(e) || !isBareSpecifier(specifier)) {
    return false;
  }
  const stack = e.requireStack;
  const depth = Array.isArray(stack) ? stack.length : 0;
  return depth <= 1;
}

// 注入 require：先按主基点（会话临时区）解析，只有「顶层裸说明符缺失」才按安装落点再解析一次
function makeRequire(baseRequire, fallbackRequire) {
  const requireProxy = function require(specifier) {
    let loaded;
    try {
      loaded = baseRequire(specifier);
    } catch (e) {
      if (!shouldFallbackRequire(e, specifier) || fallbackRequire === null) {
        throw e;
      }
      loaded = fallbackRequire(specifier);
    }
    return wrapLoadedModule(specifier, loaded);
  };
  // resolve 同规则（只对顶层裸说明符回退）：装好的包 require 与 require.resolve 都得通
  requireProxy.resolve = function resolve(specifier) {
    try {
      return baseRequire.resolve(specifier);
    } catch (e) {
      if (!shouldFallbackRequire(e, specifier) || fallbackRequire === null) {
        throw e;
      }
      return fallbackRequire.resolve(specifier);
    }
  };
  requireProxy.cache = baseRequire.cache;
  requireProxy.main = baseRequire.main;
  requireProxy.extensions = baseRequire.extensions;
  return requireProxy;
}

// 回退基点的 createRequire（未注入回空 = 无回退；锚点文件不需要真实存在）
function makeFallbackRequire() {
  if (npmRequireEntryPath === '') {
    return null;
  }
  return createRequire(npmRequireEntryPath);
}

// 模块名归一：node: 前缀剥掉，只对需要加强的模块返回名字
function normalizeModuleName(specifier) {
  if (typeof specifier !== 'string') {
    return '';
  }
  const name = specifier.startsWith('node:') ? specifier.slice(5) : specifier;
  const known = ['fs', 'fs/promises', 'http', 'https', 'net', 'timers'];
  return known.indexOf(name) >= 0 ? name : '';
}

function wrapLoadedModule(specifier, loaded) {
  const name = normalizeModuleName(specifier);
  if (name === '' || loaded === null || (typeof loaded !== 'object' && typeof loaded !== 'function')) {
    return loaded;
  }
  const cached = MODULE_VIEW_CACHE.get(loaded);
  if (cached !== undefined) {
    return cached;
  }
  let view = loaded;
  if (name === 'fs') {
    view = wrapFsModule(loaded);
  } else if (name === 'fs/promises') {
    view = wrapFsPromises(loaded);
  } else if (name === 'http' || name === 'https') {
    view = wrapHttpModule(loaded, name);
  } else if (name === 'net') {
    view = wrapNetModule(loaded);
  } else if (name === 'timers') {
    view = wrapTimersModule(loaded);
  }
  MODULE_VIEW_CACHE.set(loaded, view);
  return view;
}

// fs 模块视图（原型链继承原模块：constants 等只读属性照旧可读）
function wrapFsModule(original) {
  const view = Object.create(original);
  for (const name of FS_CALLBACK_FUNCTIONS) {
    if (typeof original[name] === 'function') {
      view[name] = trackCallbackStyle(original[name], isFsEventFunction(name) ? fsEventText(name) : null);
    }
  }
  for (const name of FS_SYNC_WRITE_FUNCTIONS) {
    if (typeof original[name] === 'function') {
      view[name] = recordOnly(original[name], fsEventText(name));
    }
  }
  if (typeof original.createReadStream === 'function') {
    view.createReadStream = trackStreamFactory(original.createReadStream, null);
  }
  if (typeof original.createWriteStream === 'function') {
    view.createWriteStream = trackStreamFactory(original.createWriteStream, 'fs 写流');
  }
  if (original.promises !== null && typeof original.promises === 'object') {
    // fs.promises 在 fs 模块上是只读 getter（原型链继承的访问器无法直接赋值），用 defineProperty 落自有属性
    Object.defineProperty(view, 'promises', {
      value: wrapFsPromises(original.promises),
      enumerable: true,
      configurable: true
    });
  }
  return view;
}

function wrapFsPromises(original) {
  if (original === null || typeof original !== 'object') {
    return original;
  }
  const cached = MODULE_VIEW_CACHE.get(original);
  if (cached !== undefined) {
    return cached;
  }
  const view = Object.create(original);
  for (const name of FS_PROMISE_FUNCTIONS) {
    if (typeof original[name] === 'function') {
      view[name] = trackPromiseStyle(original[name], isFsEventFunction(name) ? fsEventText(name) : null);
    }
  }
  MODULE_VIEW_CACHE.set(original, view);
  return view;
}

// 回调式：末参是回调 → 计后台并在回调时结算；无回调（如 fs.watch 省略 cb）不算后台
function trackCallbackStyle(original, label) {
  return function (...args) {
    if (label !== null) {
      recordEvent(label + ' ' + describeTarget(args[0]));
    }
    const callbackAt = lastFunctionIndex(args);
    if (callbackAt < 0) {
      return original.apply(this, args);
    }
    const userCallback = args[callbackAt];
    let done = false;
    trackStart();
    args[callbackAt] = function (...callbackArgs) {
      if (!done) {
        done = true;
        trackDone();
      }
      return userCallback.apply(this, callbackArgs);
    };
    try {
      return original.apply(this, args);
    } catch (e) {
      if (!done) {
        done = true;
        trackDone();
      }
      throw e;
    }
  };
}

function trackPromiseStyle(original, label) {
  return function (...args) {
    if (label !== null) {
      recordEvent(label + ' ' + describeTarget(args[0]));
    }
    trackStart();
    let promise;
    try {
      promise = original.apply(this, args);
    } catch (e) {
      trackDone();
      throw e;
    }
    return Promise.resolve(promise).then(
      (value) => {
        trackDone();
        return value;
      },
      (error) => {
        trackDone();
        throw error;
      }
    );
  };
}

// 只记事件不改语义（同步写族）
function recordOnly(original, label) {
  return function (...args) {
    recordEvent(label + ' ' + describeTarget(args[0]));
    return original.apply(this, args);
  };
}

function lastFunctionIndex(args) {
  for (let i = args.length - 1; i >= 0; i--) {
    if (typeof args[i] === 'function') {
      return i;
    }
  }
  return -1;
}

// 文件流：建流即计后台，close / error 结算
function trackStreamFactory(original, label) {
  return function (...args) {
    const stream = original.apply(this, args);
    if (label !== null) {
      recordEvent(label + ' ' + describeTarget(args[0]));
    }
    trackStart();
    let done = false;
    const settle = () => {
      if (!done) {
        done = true;
        trackDone();
      }
    };
    stream.once('close', settle);
    stream.once('error', settle);
    return stream;
  };
}

// http/https 客户端请求：请求对象 close / error 结算（keep-alive 复用不计入——请求已完成）
function wrapHttpModule(original, protocol) {
  const view = Object.create(original);
  for (const name of ['request', 'get']) {
    if (typeof original[name] !== 'function') {
      continue;
    }
    view[name] = function (...args) {
      const request = original[name].apply(this, args);
      recordEvent(protocol + ' 请求 ' + describeHttpArguments(args));
      trackStart();
      let done = false;
      const settle = () => {
        if (!done) {
          done = true;
          trackDone();
        }
      };
      request.once('close', settle);
      request.once('error', settle);
      return request;
    };
  }
  return view;
}

function describeHttpArguments(args) {
  const first = args[0];
  if (typeof first === 'string') {
    return shortenText(first, EVENT_DETAIL_MAX);
  }
  if (first instanceof URL) {
    return shortenText(first.href, EVENT_DETAIL_MAX);
  }
  if (first !== null && typeof first === 'object') {
    const host = first.hostname !== undefined ? first.hostname
      : (first.host !== undefined ? first.host : '');
    const port = first.port !== undefined ? first.port : '';
    const target = first.path !== undefined ? first.path : '/';
    return shortenText(String(host) + ' ' + String(port) + ' ' + String(target), EVENT_DETAIL_MAX);
  }
  return '非路径参数';
}

// net：连接（connect / createConnection / new Socket().connect）与建服务器（listen）计入后台
function wrapNetModule(original) {
  const view = Object.create(original);
  for (const name of ['connect', 'createConnection']) {
    if (typeof original[name] !== 'function') {
      continue;
    }
    view[name] = function (...args) {
      const socket = original[name].apply(this, args);
      trackSocket(socket);
      recordEvent('net 连接 ' + describeNetArguments(args));
      return socket;
    };
  }
  if (typeof original.createServer === 'function') {
    view.createServer = function (...args) {
      const server = original.createServer.apply(this, args);
      patchServerListen(server);
      return server;
    };
  }
  if (typeof original.Socket === 'function') {
    const OriginalSocket = original.Socket;
    view.Socket = class SessionSocket extends OriginalSocket {
      connect(...args) {
        trackSocket(this);
        recordEvent('net 连接 ' + describeNetArguments(args));
        return super.connect(...args);
      }
    };
  }
  if (typeof original.Server === 'function') {
    const OriginalServer = original.Server;
    view.Server = class SessionServer extends OriginalServer {
      listen(...args) {
        trackServerListen(this);
        recordEvent('net 监听');
        return super.listen(...args);
      }
    };
  }
  return view;
}

function describeNetArguments(args) {
  const first = args[0];
  if (first !== null && typeof first === 'object') {
    const host = first.host !== undefined ? first.host : '127.0.0.1';
    const port = first.port !== undefined ? first.port : '';
    const target = args.length > 1 && typeof args[1] === 'string' ? args[1] : first.path;
    return shortenText(String(host) + ' ' + String(port) + ' '
      + (target !== undefined ? String(target) : ''), EVENT_DETAIL_MAX);
  }
  return shortenText(args.map((item) => String(item)).join(' '), EVENT_DETAIL_MAX);
}

function trackSocket(socket) {
  if (socket === null || typeof socket !== 'object' || TRACKED_SOCKETS.has(socket)) {
    return;
  }
  TRACKED_SOCKETS.add(socket);
  trackStart();
  let done = false;
  const settle = () => {
    if (!done) {
      done = true;
      trackDone();
    }
  };
  socket.once('close', settle);
  socket.once('error', settle);
}

function trackServerListen(server) {
  if (server === null || typeof server !== 'object' || TRACKED_SERVER_LISTENS.has(server)) {
    return;
  }
  TRACKED_SERVER_LISTENS.add(server);
  trackStart();
  let done = false;
  server.once('close', () => {
    if (!done) {
      done = true;
      trackDone();
    }
  });
}

// createServer 返回的实例：把 listen 包一层，只有真正 listen 的服务器才计后台
function patchServerListen(server) {
  if (server === null || typeof server !== 'object' || TRACKED_SERVERS.has(server)) {
    return;
  }
  TRACKED_SERVERS.add(server);
  const originalListen = server.listen;
  if (typeof originalListen !== 'function') {
    return;
  }
  server.listen = function (...args) {
    trackServerListen(server);
    return originalListen.apply(server, args);
  };
}

function wrapTimersModule(original) {
  const view = Object.create(original);
  view.setTimeout = trackedSetTimeout;
  view.setInterval = trackedSetInterval;
  view.setImmediate = trackedSetImmediate;
  return view;
}

// fetch：返回 promise 结算即完成；未 await 的 fetch 在轮末仍待决 → terminated-background
function trackedFetch(input, init) {
  if (typeof realFetch !== 'function') {
    throw new Error('当前运行时不提供 fetch');
  }
  recordEvent('fetch 请求 ' + describeFetchTarget(input));
  trackStart();
  let promise;
  try {
    promise = realFetch(input, init);
  } catch (e) {
    trackDone();
    throw e;
  }
  return promise.then(
    (response) => {
      trackDone();
      return response;
    },
    (error) => {
      trackDone();
      throw error;
    }
  );
}

// fetch 入参可能是字符串、URL 或 Request 对象
function describeFetchTarget(input) {
  if (typeof input === 'string') {
    return shortenText(input, EVENT_DETAIL_MAX);
  }
  if (input instanceof URL) {
    return shortenText(input.href, EVENT_DETAIL_MAX);
  }
  if (input !== null && typeof input === 'object' && typeof input.url === 'string') {
    return shortenText(input.url, EVENT_DETAIL_MAX);
  }
  return 'Request 对象';
}

const realFetch = typeof globalThis.fetch === 'function' ? globalThis.fetch : null;

// ── 会话上下文 ──

function buildContext(cwd) {
  const entryPath = path.join(cwd, ENTRY_FILE_NAME);
  const baseRequire = createRequire(entryPath);
  const fallbackRequire = makeFallbackRequire();
  const moduleObject = {
    exports: {},
    id: '.',
    filename: entryPath,
    loaded: true
  };
  const sandbox = {
    process: process,
    Buffer: Buffer,
    console: console,
    print: printValue,
    save: sessionSave,
    require: makeRequire(baseRequire, fallbackRequire),
    module: moduleObject,
    exports: moduleObject.exports,
    __filename: entryPath,
    __dirname: cwd,
    setTimeout: trackedSetTimeout,
    clearTimeout: clearTimeout,
    setInterval: trackedSetInterval,
    clearInterval: clearInterval,
    setImmediate: trackedSetImmediate,
    clearImmediate: clearImmediate,
    queueMicrotask: queueMicrotask,
    URL: URL,
    URLSearchParams: URLSearchParams,
    TextEncoder: TextEncoder,
    TextDecoder: TextDecoder,
    Blob: Blob,
    FormData: FormData,
    Headers: Headers,
    Request: Request,
    Response: Response,
    fetch: trackedFetch,
    AbortController: AbortController,
    AbortSignal: AbortSignal,
    performance: performance,
    structuredClone: structuredClone,
    atob: atob,
    btoa: btoa
  };
  if (typeof globalThis.crypto === 'object') {
    sandbox.crypto = globalThis.crypto;
  }
  const context = vm.createContext(sandbox);
  vm.runInContext('globalThis.global = globalThis;', context);
  return {
    context: context,
    sandbox: sandbox,
    moduleObject: moduleObject,
    cwd: cwd,
    entryPath: entryPath
  };
}

// cwd 变化（同会话换临时区）时只重挂 require 与 __dirname/__filename，保住顶层状态；
// 常规路径下 ArkTS 每个会话的 cwd 恒定，本分支是防御
function rebindContextCwd(box, cwd) {
  const entryPath = path.join(cwd, ENTRY_FILE_NAME);
  box.sandbox.require = makeRequire(createRequire(entryPath), makeFallbackRequire());
  box.sandbox.__dirname = cwd;
  box.sandbox.__filename = entryPath;
  box.moduleObject.filename = entryPath;
  box.cwd = cwd;
  box.entryPath = entryPath;
}

function ensureContext(cwd) {
  if (contextBox === null) {
    contextBox = buildContext(cwd);
    return contextBox;
  }
  if (contextBox.cwd !== cwd) {
    rebindContextCwd(contextBox, cwd);
  }
  return contextBox;
}

// print：与 console.log 同格式（换行结尾），经 process.stdout.write 进捕获面
function printValue(...args) {
  process.stdout.write(util.format(...args) + '\n');
}

// save：登记会话 cwd 内的相对文件（不拷贝；转正由 ArkTS 侧统一做）
function sessionSave(name) {
  if (currentRound === null) {
    throw new Error('save 只能在代码执行轮内调用');
  }
  if (typeof name !== 'string' || name.trim() === '') {
    throw new Error('save 需要非空文件名字符串');
  }
  if (name.indexOf('\0') >= 0) {
    throw new Error('save 文件名含非法字符');
  }
  if (path.isAbsolute(name)) {
    throw new Error('save 不接受绝对路径');
  }
  const segments = name.split(/[\\/]+/);
  for (const segment of segments) {
    if (segment === '..') {
      throw new Error('save 不接受 .. 路径');
    }
  }
  const cwd = currentRound.cwd;
  let realCwd;
  try {
    realCwd = fs.realpathSync(cwd);
  } catch (e) {
    throw new Error('save 会话目录不可读');
  }
  const target = path.resolve(cwd, name);
  const parentDir = path.dirname(target);
  let realParent;
  try {
    realParent = fs.realpathSync(parentDir);
  } catch (e) {
    throw new Error('save 目录不存在 ' + name);
  }
  if (realParent !== realCwd && realParent.indexOf(realCwd + path.sep) !== 0) {
    throw new Error('save 路径越出会话目录 ' + name);
  }
  let stat;
  try {
    stat = fs.lstatSync(target);
  } catch (e) {
    throw new Error('save 文件不存在 ' + name);
  }
  if (stat.isSymbolicLink()) {
    throw new Error('save 不接受符号链接文件 ' + name);
  }
  if (!stat.isFile()) {
    throw new Error('save 目标不是普通文件 ' + name);
  }
  const normalized = path.normalize(name);
  if (currentRound.savedNames.indexOf(normalized) < 0) {
    currentRound.savedNames.push(normalized);
  }
}

// ── 轮执行 ──

// bin 运行器懒加载（只 run_bin 轮才载入；缺失/载入失败限在本轮，不影响 exec 轮）
let binRunnerModule = null;

function loadBinRunner() {
  if (binRunnerModule === null) {
    binRunnerModule = require(binRunnerPath);
  }
  return binRunnerModule;
}

function beginRound(message) {
  currentRound = {
    requestId: message.requestId,
    cwd: typeof message.cwd === 'string' && message.cwd !== '' ? message.cwd : process.cwd(),
    stdout: createCapture(OUTPUT_LIMIT_BYTES),
    stderr: createCapture(OUTPUT_LIMIT_BYTES),
    timers: new Set(),
    savedNames: [],
    events: [],
    eventsDropped: 0
  };
  return currentRound;
}

// 异常串化（脚本异常进 stderr；不回显宿主内部状态以外的信息）
function errorText(error) {
  if (error !== null && typeof error === 'object' && typeof error.stack === 'string' && error.stack !== '') {
    return error.stack;
  }
  if (error instanceof Error) {
    return error.name + ' ' + error.message;
  }
  try {
    return String(error);
  } catch (e) {
    return '未知错误';
  }
}

async function executeRound(message) {
  const round = beginRound(message);
  const box = ensureContext(round.cwd);
  const hooks = installOutputHooks();
  let ok = true;
  let errorCode = '';
  let binResult = null;
  try {
    if (message.type === 'run_bin') {
      // bin 轮（门 3 U3）：执行与输出捕获共用本轮的钩子与上限；运行器同步返回终态。
      // 不传 timeoutMs——runBin 是同步语义，中途无可中断点，超时由 bootstrap 主线程看门狗
      // terminate 本 worker（见 bootstrap runSessionRound 的 setTimeout + terminateSession）
      try {
        binResult = loadBinRunner().runBin({
          prefix: binInstallRoot,
          ledgerPath: binLedgerPath,
          name: message.bin,
          args: message.args
        });
      } catch (e) {
        binResult = {
          ok: false,
          bin: typeof message.bin === 'string' ? message.bin : '',
          exitCode: 1,
          durationMs: 0,
          error: 'bin-error',
          errorCode: '',
          errorDetail: '命令行运行器不可用，' + errorText(e),
          packageName: '',
          replaced: false
        };
      }
      ok = binResult.ok === true;
      if (!ok) {
        errorCode = typeof binResult.error === 'string' && binResult.error !== ''
          ? binResult.error : 'bin-error';
        if (typeof binResult.errorDetail === 'string' && binResult.errorDetail !== '') {
          round.stderr.write(binResult.errorDetail + '\n', 'utf8');
        }
      }
    } else {
      const value = vm.runInContext(message.code, box.context, {
        filename: box.entryPath,
        displayErrors: true
      });
      if (value !== null && value !== undefined && typeof value.then === 'function') {
        await value;
      }
    }
  } catch (e) {
    ok = false;
    errorCode = 'script-error';
    round.stderr.write(errorText(e) + '\n', 'utf8');
  } finally {
    restoreOutputHooks(hooks);
    clearRoundTimers();
  }
  const payload = {
    ok: ok,
    error: errorCode,
    stdout: round.stdout.text(),
    stderr: round.stderr.text(),
    stdoutTruncated: round.stdout.isTruncated(),
    stderrTruncated: round.stderr.isTruncated(),
    savedNames: round.savedNames.slice(),
    events: round.events.slice(0, REPLY_EVENT_LIMIT),
    eventsKept: round.events.length,
    eventsTotal: round.events.length + round.eventsDropped,
    eventsNote: EVENTS_NOTE,
    backgroundOps: pendingOps,
    memory: process.memoryUsage()
  };
  if (binResult !== null) {
    payload.bin = message.bin;
    payload.exitCode = binResult.exitCode;
    payload.binPackage = binResult.packageName;
    payload.binReplaced = binResult.replaced === true;
  }
  // savedNames 读回即清（下一轮不得再回同一批文件名）
  round.savedNames.length = 0;
  currentRound = null;
  return payload;
}

// 主线程逐轮投递（串行保证：主控制面一次只投一轮；本文件再守一道，防半实现被误用）
function runSessionLoop() {
  const port = workerThreads.parentPort;
  npmRequireEntryPath = typeof workerThreads.workerData.npmRequireEntry === 'string'
    ? workerThreads.workerData.npmRequireEntry : '';
  const rawHomeDir = typeof workerThreads.workerData.homeDir === 'string'
    ? workerThreads.workerData.homeDir : '';
  binRunnerPath = rawHomeDir !== '' ? path.join(rawHomeDir, 'bin-runner.js') : '';
  binLedgerPath = typeof workerThreads.workerData.ledgerPath === 'string'
    ? workerThreads.workerData.ledgerPath : '';
  // 安装落点根 = 台账文件所在目录（<filesDir>/node/bin-ledger.json → <filesDir>/node）；
  // 不在此重推 HOME 的父级，避免与 bootstrap 的 installRootDir 派生写两份
  binInstallRoot = binLedgerPath !== '' ? path.dirname(binLedgerPath) : '';
  const initialCwd = typeof workerThreads.workerData.cwd === 'string'
    && workerThreads.workerData.cwd !== ''
      ? workerThreads.workerData.cwd
      : process.cwd();
  // 先建上下文再报 ready：workerStartMs 才能如实包含 vm context 建立成本
  ensureContext(initialCwd);
  port.on('message', (message) => {
    if (message === null || typeof message !== 'object'
      || (message.type !== 'run' && message.type !== 'run_bin')) {
      return;
    }
    if (currentRound !== null) {
      return;
    }
    executeRound(message).then((payload) => {
      port.postMessage(Object.assign({ type: 'result', requestId: message.requestId }, payload));
    }).catch((e) => {
      currentRound = null;
      port.postMessage({
        type: 'result',
        requestId: message.requestId,
        ok: false,
        error: 'worker-internal-error',
        stdout: '',
        stderr: errorText(e),
        stdoutTruncated: false,
        stderrTruncated: false,
        savedNames: [],
        events: [],
        eventsKept: 0,
        eventsTotal: 0,
        eventsNote: EVENTS_NOTE,
        backgroundOps: pendingOps,
        memory: process.memoryUsage()
      });
    });
  });
  port.postMessage({ type: 'ready' });
}

// worker 环境才启动主循环（直接 require 本文件时只导出结构哨兵）
if (isWorkerThread()) {
  runSessionLoop();
}

module.exports = { isWorkerThread, runSessionLoop };
