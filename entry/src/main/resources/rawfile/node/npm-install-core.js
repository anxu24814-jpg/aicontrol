// npm 安装执行核心（2026-11-24 鸿蒙 Node 运行时门 3 U3 S1 拆分笔，任务书-鸿蒙Node运行时门3
// U3-binrunner-20261124 §5 S1）：从 npm-worker.js 原样迁出的「安装执行」域——spec 闸、install
// 参数钉死集、npm lib 加载、日志尾捕获、心跳阶段分类、容量闸 du 遍历、每包摘要、runInstallCore
// 终态组装。worker 入口与生命周期编排仍在 npm-worker.js（消息协议 / 终止前 flush / 附注旁路 /
// 台账写行 / launchInstall 主线程编排）。方法体原样搬迁，零逻辑改写。
// · 分层（模块环零，坑50）：本件 → npm-scan.js 单向；scan 的「无 spec 幂等重装」要用本件的
//   参数表与日志捕获（单源），由本件在载入尾经 scan.setNpmPrimitives 注入，scan 侧不抄第二份。
// · 副作用隔离（worker 内 process 线程私有，session-worker.js 头注释同源事实）：进 npm 前
//   重写 process.argv = [execPath, 'npm']（npm.js 构造器把 process.argv 前置拼接进 nopt，宿主
//   参数第 3 项起会漏进解析——aily-blockly 先例），finally 恢复 argv / title / execPath；
//   graceful-fs 的 process.cwd 猴补随 worker 消亡，不处理。
// · 编程入口（调研档 §2.4，禁 .load().exec() 链式——load() 返回普通结果对象非实例）：
//   const npm = new Npm({ stdout, stderr, argv }) → const { command, args } = await npm.load()
//   → await npm.exec(command, args)；编程路径零 process.exit（ExitHandler 只在 CLI entry.js
//   实例化），错误经 #handleError re-throw 由本文件 catch 组回执。
// · install 参数钉死集（宿主注入，用户/模型不可覆写——registry 与 fetch-timeout 不在请求
//   载荷面）：--ignore-scripts --no-audit --no-fund --no-bin-links --registry 固定 --cache
//   --prefix --fetch-timeout=60000 --fetch-retries=2 --loglevel=silly（日志尾进回执）。
//   env NODE_NPM_INSTALL_REGISTRY / NODE_NPM_INSTALL_FETCH_TIMEOUT_MS 只是本机受控测试入口
//   （同 NODE_BRIDGE_CHANNEL 口径），交付态恒走默认值。★ 实测注（2026-11-24）：npm 11.19.1
//   的 make-fetch-happen 15.0.6 全库零 timeout 消费、@npmcli/agent 把 opts.timeout 只映射成
//   idle 超时且 connection: 0——--fetch-timeout 在该版本不构成连接限时，真限时器 = bootstrap
//   侧整体看门狗（超时 terminate + 回执 timeout + 心跳阶段标注）；旗标保留是为依赖面变化时
//   自然生效（无害 Belt-and-braces）。
// · spec 闸（§2.2，规则单源在本文件——bootstrap 参数闸 require 本件调用）：只收
//   name@精确版本（含 @scope/name 与预发布号）；git+ / github: / file: / dir: / link: / URL /
//   范围 / dist-tag 一律字符串拒——git 依赖不受 --ignore-scripts 约束直派 git 二进制（调研档
//   §2.1），纯 JS 硬边界靠预检守住。
// · 心跳：npm 全部日志经 proc-log 的 process 'log' 事件广播（display.js 同机制），本文件旁听
//   分类阶段（resolve / fetch / extract / verify，关键字 best-effort），变更时节流 postMessage
//   给 bootstrap 作看门狗超时回执的阶段标注。本轮捕获与心跳实例另经 getActiveCapture /
//   getActiveHeartbeat 暴露给 npm-worker 的终止前 flush（A6）。
// · 落点（方案档 ⑬）：prefix / cache 由 bootstrap 从 HOME 父级派生（filesDir/node/ 子树）经
//   workerData 传入；HOME 由宿主经 Context 取后 setenv——本文件不拼四级沙箱前缀。
// · 容量闸（门 3 U2，方案档 ⑦）：install 前对落点子树做 du 型遍历（符号链接不下降，lstat
//   计大小），总量超上限即拒装回 quota-exceeded（提示清理、不自动删用户数据）。
// · 本件被 npm-worker.js 直接 require（设备侧 HOME 内相对解析，与 session-worker.js 由
//   bootstrap 加载同模式）；非 worker 环境零副作用（不启动监听、不写文件，纯函数可直跑）。
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const workerThreads = require('node:worker_threads');
const scan = require('./npm-scan.js');

const errorText = scan.errorText;
const readTextIfExists = scan.readTextIfExists;

// registry 固定值（参数钉死集成员；env 覆写仅本机受控测试入口）
const REGISTRY_DEFAULT = 'https://registry.npmjs.org/';
// 网络限时（调研档 §4.2 dsh 静默卡死对冲件：fetch 挂起时按毫秒限时放弃）
const FETCH_TIMEOUT_DEFAULT_MS = 60000;
const FETCH_RETRIES = 2;
// 回执有界面：日志尾部行数与单行字符上限（§2.2 终态回执）
const LOG_TAIL_LIMIT = 200;
const LOG_LINE_MAX = 400;
// 每包摘要行上限（超出截断标注）
const PACKAGE_SUMMARY_LIMIT = 60;
// 心跳节流下限（阶段变更才发，且间隔不小于该值）
const HEARTBEAT_MIN_INTERVAL_MS = 500;
// 单次 install 的 spec 数上限（只防无界载荷）
const MAX_SPECS = 20;
// 容量闸硬上限（方案档 ⑦ 保守默认 512 MB，待拍板 §5-3；env 覆写仅本机受控测试入口）
const INSTALL_QUOTA_BYTES = 512 * 1024 * 1024;
// 包名语法（保守子集：npm 名合法字符，禁 . _ 开头与空格）
const NAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/;
const SCOPED_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]*\/[a-zA-Z0-9][a-zA-Z0-9._-]*$/;
// 精确三段式版本（允许预发布与 build 附标并存；范围与 dist-tag 天然不匹配）
const EXACT_VERSION_RE = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
// 非 registry 源标记（含即拒）
const NON_REGISTRY_MARKERS = ['git+', 'git:', 'github:', 'file:', 'dir:', 'link:', 'http://', 'https://'];

// ── 小工具 ──

function readEnvString(name, fallback) {
  const raw = process.env[name];
  return raw === undefined || raw === '' ? fallback : raw;
}

function readEnvPositiveInt(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') {
    return fallback;
  }
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

// ── spec 闸（规则单源；bootstrap 参数闸与本 worker 预检同源调用）──

function isLegalName(name) {
  if (name.startsWith('@')) {
    return SCOPED_RE.test(name.slice(1));
  }
  return NAME_RE.test(name);
}

// 单条 spec 拒因（空串 = 通过）
function specRejectReason(spec) {
  if (typeof spec !== 'string') {
    return 'spec 不是字符串';
  }
  if (spec === '') {
    return 'spec 为空';
  }
  if (/\s/.test(spec)) {
    return 'spec 含空白字符';
  }
  for (const marker of NON_REGISTRY_MARKERS) {
    if (spec.indexOf(marker) >= 0) {
      return '只支持 registry 精确版本，拒绝 ' + marker + ' 源';
    }
  }
  const at = spec.lastIndexOf('@');
  if (at <= 0) {
    return '缺版本号（只收 name@精确版本）';
  }
  const name = spec.slice(0, at);
  const version = spec.slice(at + 1);
  if (!isLegalName(name)) {
    return '包名非法 ' + name;
  }
  if (!EXACT_VERSION_RE.test(version)) {
    return '版本必须是精确三段式（收到 ' + (version === '' ? '空' : version)
      + '，范围/dist-tag/别名一律拒绝）';
  }
  return '';
}

// specs 数组闸（bootstrap install 参数闸调用；返回 {ok, error}）
function validateSpecs(specs) {
  if (!Array.isArray(specs) || specs.length === 0) {
    return { ok: false, error: 'specs 必须是非空字符串数组' };
  }
  if (specs.length > MAX_SPECS) {
    return { ok: false, error: '单次 install 最多 ' + MAX_SPECS + ' 个包（收到 ' + specs.length + '）' };
  }
  for (const spec of specs) {
    const reason = specRejectReason(spec);
    if (reason !== '') {
      return { ok: false, error: reason + (typeof spec === 'string' ? '（' + spec + '）' : '') };
    }
  }
  return { ok: true, error: '' };
}

// ── install argv（参数钉死集；宿主注入面，不经请求载荷）──

function buildInstallArgv(specs, options) {
  const registry = readEnvString('NODE_NPM_INSTALL_REGISTRY', REGISTRY_DEFAULT);
  const fetchTimeoutMs = readEnvPositiveInt('NODE_NPM_INSTALL_FETCH_TIMEOUT_MS', FETCH_TIMEOUT_DEFAULT_MS);
  return ['install'].concat(specs, [
    '--ignore-scripts',
    '--no-audit',
    '--no-fund',
    '--no-bin-links',
    '--registry=' + registry,
    '--cache=' + options.cacheDir,
    '--prefix=' + options.prefix,
    '--fetch-timeout=' + String(fetchTimeoutMs),
    '--fetch-retries=' + String(FETCH_RETRIES),
    '--loglevel=silly'
  ]);
}

// ── 日志捕获（Display 把格式化行写进注入的 stdout/stderr 对象；保尾部有界）──

function createLogCapture() {
  const lines = [];
  let carry = '';
  const pushLine = (raw) => {
    const line = raw.replace(/\r/g, '').trimEnd();
    if (line === '') {
      return;
    }
    lines.push(line.length > LOG_LINE_MAX ? line.slice(0, LOG_LINE_MAX) : line);
    if (lines.length > LOG_TAIL_LIMIT) {
      lines.splice(0, lines.length - LOG_TAIL_LIMIT);
    }
  };
  const record = (chunk) => {
    const text = typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
    carry += text;
    if (carry.length > LOG_LINE_MAX * 4) {
      // 无换行的连续写（进度 \r 流等）：截断保留尾段，防 carry 无界
      carry = carry.slice(-LOG_LINE_MAX);
    }
    const parts = carry.split('\n');
    carry = parts.pop();
    for (const raw of parts) {
      pushLine(raw);
    }
  };
  const makeStream = () => ({
    write(chunk, encoding, callback) {
      record(chunk);
      if (typeof callback === 'function') {
        callback();
      }
      return true;
    }
  });
  return {
    stdoutStream: makeStream(),
    stderrStream: makeStream(),
    tail() {
      if (carry !== '') {
        pushLine(carry);
        carry = '';
      }
      return lines.slice(-LOG_TAIL_LIMIT);
    }
  };
}

// ── 心跳（旁听 proc-log 的 process 'log' 事件；阶段分类 best-effort）──

// 阶段判定次序 = 后段优先（同一条日志只取最能说明当前位置的标记）
function classifyStage(level, text) {
  if (/extract/i.test(text)) {
    return 'extract';
  }
  if (level === 'http' || /\bfetch/i.test(text)) {
    return 'fetch';
  }
  if (/reify|audit|retire|verif/i.test(text)) {
    return 'verify';
  }
  if (/idealTree|placeDep|resolve|buildDeps|deprecated/i.test(text)) {
    return 'resolve';
  }
  return '';
}

function createHeartbeat() {
  const port = workerThreads.parentPort;
  let stage = 'resolve';
  let lastPostAt = 0;
  const handler = (level, ...args) => {
    const next = classifyStage(level, args.filter((part) => typeof part === 'string').join(' '));
    if (next === '' || next === stage) {
      return;
    }
    stage = next;
    const now = Date.now();
    if (now - lastPostAt < HEARTBEAT_MIN_INTERVAL_MS) {
      return;
    }
    lastPostAt = now;
    try {
      port.postMessage({ type: 'stage', stage: stage });
    } catch (e) {
      // 主线程已脱手（terminate 后）；心跳丢失无害
    }
  };
  process.on('log', handler);
  return {
    stage() {
      return stage;
    },
    off() {
      process.removeListener('log', handler);
    }
  };
}

// ── 终止前 flush 与运行期附注（A6 / A3 的跨线程通道）──
// activeCapture / activeHeartbeat = 本轮的日志捕获与心跳（flush 请求读它们；轮末清空）。
// activeNoteSink = 主线程消息投递器（npm-worker 的 startNpmWorker 经 setNoteSink 注入），用于把
// 「安装前清扫计数」这类只可能在终止路径才需要的附注旁路回主线程——terminate 后 worker 的
// 回执载荷整个丢失。
let activeCapture = null;
let activeHeartbeat = null;
let activeNoteSink = null;

function setNoteSink(sink) {
  activeNoteSink = sink;
}

function getActiveCapture() {
  return activeCapture;
}

function getActiveHeartbeat() {
  return activeHeartbeat;
}

function postNote(text) {
  if (activeNoteSink === null || text === '') {
    return;
  }
  try {
    activeNoteSink({ type: 'note', text: text });
  } catch (e) {
    // 主线程已脱手（terminate 后）；附注丢失无害
  }
}

// ── 容量闸（门 3 U2，方案档 ⑦）──

// du 型子树遍历（字节计）：lstat 计大小、符号链接不下降（防逃逸与循环；链接本身按其
// lstat 尺寸计入，不追目标）
function measureTreeBytes(root) {
  let total = 0;
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop();
    let names = [];
    try {
      names = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      continue; // 目录不存在或不可读 = 该子树不计
    }
    for (const entry of names) {
      const abs = path.join(dir, entry.name);
      let st = null;
      try {
        st = fs.lstatSync(abs);
      } catch (e) {
        continue;
      }
      if (st.isDirectory()) {
        stack.push(abs);
      } else {
        total += st.size;
      }
    }
  }
  return total;
}

function formatMb(bytes) {
  return (bytes / (1024 * 1024)).toFixed(1);
}

// ── 每包摘要（package-lock.json 为源；tarball 字节数 = cacache 内容件实读；records = 台账
//    用的结构化每包记录，同样有界）──

function tarballBytesFor(integrity, cacheDir) {
  try {
    const parts = String(integrity).split('-');
    if (parts.length !== 2 || parts[0] !== 'sha512' || parts[1] === '') {
      return -1;
    }
    const hex = Buffer.from(parts[1], 'base64').toString('hex');
    if (hex.length < 8) {
      return -1;
    }
    // npm 11 的 cache = <cache>/_cacache/content-v2/<alg>/<2>/<2>/<rest>（实测布局）
    const contentPath = path.join(cacheDir, '_cacache', 'content-v2', parts[0],
      hex.slice(0, 2), hex.slice(2, 4), hex.slice(4));
    return fs.statSync(contentPath).size;
  } catch (e) {
    return -1;
  }
}

function summarizePackages(prefix, cacheDir) {
  const lockText = readTextIfExists(path.join(prefix, 'package-lock.json'));
  const lines = [];
  const records = [];
  let total = 0;
  if (lockText !== null) {
    let lock = null;
    try {
      lock = JSON.parse(lockText);
    } catch (e) {
      lock = null;
    }
    const packages = lock !== null && lock.packages !== null && typeof lock.packages === 'object'
      ? lock.packages : {};
    for (const location of Object.keys(packages)) {
      if (location === '') {
        continue; // 根条目
      }
      const meta = packages[location];
      const version = meta !== null && typeof meta.version === 'string' ? meta.version : '?';
      const integrity = meta !== null && typeof meta.integrity === 'string' ? meta.integrity : '';
      const shortIntegrity = integrity === '' ? '-'
        : integrity.slice(0, 20) + '…';
      const bytes = tarballBytesFor(integrity, cacheDir);
      const name = location.startsWith('node_modules/')
        ? location.slice('node_modules/'.length) : location;
      total++;
      if (lines.length < PACKAGE_SUMMARY_LIMIT) {
        lines.push(name + '@' + version + ' integrity=' + shortIntegrity
          + ' tarball=' + (bytes >= 0 ? bytes + 'B' : '未知'));
        records.push({
          name: name,
          version: version,
          integrity: integrity,
          resolved: meta !== null && typeof meta.resolved === 'string' ? meta.resolved : ''
        });
      }
    }
  }
  return { lines: lines, total: total, truncated: total > lines.length, records: records };
}

// ── 终态回执骨架 ──

function basePayload(error, startAt, stage, capture) {
  return {
    ok: false,
    error: error,
    exitCode: error === '' ? 0 : 1,
    errorCode: '',
    errorDetail: '',
    stage: stage,
    elapsedMs: Date.now() - startAt,
    logTail: capture.tail(),
    packages: [],
    packagesTotal: 0,
    packagesTruncated: false,
    wasmNote: '',
    rolledBack: false,
    violations: [],
    cleanupNote: '',
    memory: process.memoryUsage()
  };
}

function exitCodeOf(e) {
  if (e !== null && typeof e === 'object' && typeof e.code === 'number') {
    return e.code;
  }
  return 1;
}

// terminate / 崩溃残留的 cacache tmp 无害；下次 install 前清空
function cleanCacheTmp(cacheDir) {
  try {
    fs.rmSync(path.join(cacheDir, 'tmp'), { recursive: true, force: true });
  } catch (e) {
    // 清不掉不阻断（tmp 项与目标同挂载，npm 自身也会复用/覆写）
  }
}

// ── install 本体（终态回执组装；台账写行在 npm-worker.js 的 runInstall 收口）──

async function runInstallCore(data, ledger, notes) {
  const startAt = Date.now();
  const prefix = String(data.prefix);
  const cacheDir = String(data.cacheDir);
  const npmLibPath = String(data.npmLibPath);
  const capture = createLogCapture();
  const heartbeat = createHeartbeat();
  const savedTitle = process.title;
  const savedExecPath = process.execPath;
  const savedArgv = process.argv.slice();
  let before = null;
  activeCapture = capture;
  activeHeartbeat = heartbeat;
  try {
    // 预检（与 bootstrap 参数闸同源；worker 侧再守一道，防绕过控制面直投）
    const verdict = validateSpecs(data.specs);
    if (!verdict.ok) {
      return Object.assign(basePayload('bad-request', startAt, heartbeat.stage(), capture),
        { errorDetail: verdict.error });
    }
    fs.mkdirSync(prefix, { recursive: true });
    fs.mkdirSync(cacheDir, { recursive: true });
    cleanCacheTmp(cacheDir);
    // 容量闸（门 3 U2，方案档 ⑦）：装前查落点子树总量（含 node_modules 与 cache），超限
    // 拒装并提示清理——不自动删用户数据；env 覆写仅本机受控测试入口
    const quotaBytes = readEnvPositiveInt('NODE_NPM_INSTALL_QUOTA_BYTES', INSTALL_QUOTA_BYTES);
    const usedBytes = measureTreeBytes(prefix);
    if (usedBytes > quotaBytes) {
      return Object.assign(basePayload('quota-exceeded', startAt, heartbeat.stage(), capture), {
        errorDetail: 'Node 安装区已用 ' + formatMb(usedBytes) + ' MB，超过 '
          + formatMb(quotaBytes) + ' MB 上限，请清理不再使用的包后重试'
      });
    }
    // 装前全树二进制清扫（Y5③）：历史残留（含失败 / 被 terminate 的轮次留下的）若不清，会被
    // 本轮 before 快照吸收 → 之后永远不在增量里，二进制边界可被永久绕过
    const sweepBefore = scan.sweepBinaryFiles(prefix);
    if (sweepBefore.removed.length > 0) {
      console.error('[npm-worker] 安装前清扫历史二进制残留 ' + sweepBefore.removed.length + ' 个');
      notes.push('安装前清理了 ' + sweepBefore.removed.length + ' 个历史残留的二进制文件。');
      postNote(notes[notes.length - 1]);
    }
    if (sweepBefore.failed.length > 0) {
      notes.push('有 ' + sweepBefore.failed.length + ' 个历史残留文件没清掉。');
    }
    before = scan.snapshotInstallState(prefix);
    // 锁版本的深路径（v8 起无契约内部路径，npm 11.19.1 冻结文件集内——调研档 §2.4）
    const Npm = require(npmLibPath);
    // 进 npm 前重写 argv：npm.js 把 process.argv 前置拼接，宿主参数不得漏进 nopt
    process.argv = [savedExecPath, 'npm'];
    const argv = buildInstallArgv(data.specs, { prefix: prefix, cacheDir: cacheDir });
    const npm = new Npm({ stdout: capture.stdoutStream, stderr: capture.stderrStream, argv: argv });
    const loaded = await npm.load();
    if (loaded === null || typeof loaded !== 'object' || loaded.exec !== true
      || typeof loaded.command !== 'string' || loaded.command === '') {
      throw new Error('npm load 未解析出可执行命令');
    }
    await npm.exec(loaded.command, loaded.args);
    // 装后纯 JS 扫描（命中即按 Y0 规则回滚 + 修复 + 复扫）
    const safety = scan.checkInstallSafety(prefix, before);
    if (safety.violations.length > 0) {
      const result = await scan.rollbackAfterViolation(prefix, cacheDir, before, safety, npmLibPath);
      return Object.assign(basePayload('binary-rejected', startAt, heartbeat.stage(), capture), {
        rolledBack: result.rolledBack,
        violations: result.rolledBack ? safety.violations.slice(0, scan.VIOLATION_REPORT_MAX)
          : result.failures,
        errorDetail: '装后扫描命中二进制文件，已按回滚规则处理'
      });
    }
    const summary = summarizePackages(prefix, cacheDir);
    ledger.packages = summary.records; // 台账每包记录（有界，同摘要行上限）
    const payload = Object.assign(basePayload('', startAt, heartbeat.stage(), capture), {
      ok: true,
      packages: summary.lines,
      packagesTotal: summary.total,
      packagesTruncated: summary.truncated
    });
    if (safety.wasmFiles.length > 0) {
      payload.wasmNote = '检出 ' + safety.wasmFiles.length
        + ' 个 .wasm 文件，jitless 设备不可用';
    }
    return payload;
  } catch (e) {
    const npmError = errorText(e);
    // npm 失败路同样扫增量（Y5①）：命中二进制按同一套规则回滚并改判 binary-rejected（附 npm
    // 原错误摘要）；没命中就维持 install-failed，半装态交下一次幂等重装
    if (before !== null) {
      const safety = scan.checkInstallSafety(prefix, before);
      if (safety.violations.length > 0) {
        const result = await scan.rollbackAfterViolation(prefix, cacheDir, before, safety, npmLibPath);
        return Object.assign(basePayload('binary-rejected', startAt, heartbeat.stage(), capture), {
          rolledBack: result.rolledBack,
          violations: result.rolledBack ? safety.violations.slice(0, scan.VIOLATION_REPORT_MAX)
            : result.failures,
          errorDetail: 'npm 安装失败，装后扫描还命中二进制文件，已按回滚规则处理。npm 原始错误 '
            + (npmError.length > 200 ? npmError.slice(0, 200) + '…' : npmError)
        });
      }
    }
    return Object.assign(basePayload('install-failed', startAt, heartbeat.stage(), capture), {
      exitCode: exitCodeOf(e),
      errorCode: e !== null && typeof e === 'object' && typeof e.code === 'string' ? e.code : '',
      errorDetail: npmError
    });
  } finally {
    activeCapture = null;
    activeHeartbeat = null;
    // 副作用恢复（契约 §2.2；worker 随即消亡，恢复是双保险）
    process.argv = savedArgv;
    try {
      process.title = savedTitle;
    } catch (e) {
      // 恢复尽力而为
    }
    try {
      process.execPath = savedExecPath;
    } catch (e) {
      // 同上
    }
    heartbeat.off();
  }
}

// 注入（模块环零）：npm-scan 的重装修复步用本件参数表与日志捕获，不在下层抄第二份
scan.setNpmPrimitives({ buildArgv: buildInstallArgv, createCapture: createLogCapture });

module.exports = {
  validateSpecs,
  runInstallCore,
  basePayload,
  createLogCapture,
  errorText,
  measureTreeBytes,
  summarizePackages,
  setNoteSink,
  getActiveCapture,
  getActiveHeartbeat,
  REGISTRY_DEFAULT,
  FETCH_TIMEOUT_DEFAULT_MS,
  INSTALL_QUOTA_BYTES
};
