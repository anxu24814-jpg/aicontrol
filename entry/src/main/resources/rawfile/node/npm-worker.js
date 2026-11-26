// npm 安装域 worker 入口（2026-11-24 鸿蒙 Node 运行时门 3 U3 S1 拆分笔，任务书-鸿蒙Node运行时门3
// U3-binrunner-20261124 §5 S1 后）：每 install 一个短命 worker，终态回执经 parentPort 回
// bootstrap，由其 terminate 收口；本文件另挂 unref 自退计时器兜底——npm 可能遗留 keep-alive
// 句柄与计时器，事件循环不自空。不入会话注册表、不占 NODE_SESSION_WORKER_LIMIT。
// · 分工（三件拆分）：本件 = worker 入口与生命周期编排（消息协议、终止前 flush、附注旁路、
//   安装台账写行、结果回传）+ 主线程 launchInstall 编排（派 worker / 心跳回调 / 看门狗 /
//   terminate 收口）；安装执行在 npm-install-core.js（spec 闸 / 参数钉死集 / npm lib 加载 /
//   日志尾捕获 / 容量闸 / 每包摘要 / runInstallCore）；装后扫描与回滚在 npm-scan.js。
// · 台账（门 3 U2，方案档 ⑦）：每次 install 终态追加一条（specs / ok / exitCode / 每包 name、
//   version、integrity、resolved / 时间），尾部有界——npm 原生 package.json 与
//   package-lock.json 是权威清单，台账只是审计面。被 terminate 的轮次在 worker 内写不出，
//   主线程在 terminateWith 收口时补一条（A5）。
// · 附注单字段（cleanupNote，四层同步 npm-worker → NodeBridge → NodeScheduler → ToolNodeExec）：
//   承载三类说明——安装前后清扫计数、回滚未成功项、终止时日志尾部不可得。回执按字段有界。
//   （门 3 U3 加第四类：bin 台账登记计数与同名覆盖说明；仍是同一字段、同一有界口径。）
// · 终止前 flush（A6）：主线程 terminate 之前先索要一次日志尾与当前阶段；本轮捕获与心跳实例
//   在 npm-install-core（getActiveCapture / getActiveHeartbeat 读），本件只持消息通道。运行期
//   附注（A3）经 core.setNoteSink 注入同一通道——terminate 后 worker 的回执载荷整个丢失，
//   附注必须旁路。
// · 失败与终止路同样不留二进制（Y5）：②worker 被 terminate（看门狗 / cancel / drop）时主线程
//   做一次全树二进制清扫（npm-scan.sweepBinaryFiles），计数进 cleanupNote。
// · 本文件被 bootstrap / 测试脚本直接 require：非 worker 环境只导出纯函数（结构哨兵同
//   session-worker），不启动任何监听。
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const workerThreads = require('node:worker_threads');
const core = require('./npm-install-core.js');
const scan = require('./npm-scan.js');

const errorText = core.errorText;
// 安装台账上限（追加式有界，保尾部 N 条；权威清单 = package.json / package-lock.json）
const INSTALL_LEDGER_MAX = 200;
const INSTALL_LEDGER_FILE = 'install-log.jsonl';
// 终止前 flush 日志尾的限时（A6：terminate 后 worker 内存里的日志与阶段全丢；2 s 上限只兜底
// worker 已卡死——正常 flush 是同步 postMessage，毫秒级返回）
const FLUSH_TIMEOUT_MS = 2000;

// 结构哨兵（直接 require 时不启动任何逻辑）
function isWorkerThread() {
  return workerThreads.workerData !== null && workerThreads.workerData !== undefined;
}

// 安装台账追加（尾部有界）：读失败按空档重立、写失败不阻断回执（非权威清单）
function appendInstallLedger(prefix, record) {
  const file = path.join(prefix, INSTALL_LEDGER_FILE);
  let lines = [];
  try {
    lines = fs.readFileSync(file, 'utf8').split('\n').filter((line) => line.trim() !== '');
  } catch (e) {
    lines = [];
  }
  lines.push(JSON.stringify(record));
  if (lines.length > INSTALL_LEDGER_MAX) {
    lines = lines.slice(lines.length - INSTALL_LEDGER_MAX);
  }
  try {
    fs.writeFileSync(file, lines.join('\n') + '\n');
  } catch (e) {
    // 台账只是审计面（package-lock.json 是权威清单），写失败不影响安装结果
  }
}

// spec → 包名（name@精确版本，@scope/name 的 version 分隔符取最后一个 @；不合规 spec 回空串，
// 参数闸已在前面拒过，这里只服务 bin 台账的同名归属判定）
function specPackageNameOf(spec) {
  const text = String(spec);
  const at = text.lastIndexOf('@');
  return at > 0 ? text.slice(0, at) : '';
}

// ── install 本体 ──

// 台账外层收口：core 各终态路径只管回执，ledger 记录由本层统一补时间戳落盘（终态追加、
// 失败也记 exitCode；写失败不阻断回执）。notes 是本轮的附注累积（清扫计数等），统一折进
// cleanupNote 单字段（worker 侧旁路只在该字段上出一次）
async function runInstall(data) {
  const ledger = {
    specs: Array.isArray(data.specs) ? data.specs : [],
    ok: false,
    exitCode: 1,
    error: '',
    packages: [],
    time: ''
  };
  const notes = [];
  const receipt = await core.runInstallCore(data, ledger, notes);
  if (receipt.ok === true) {
    // bin 台账（门 3 U3 S3）：只有成功轮才写——失败与回滚轮留下的是半装态，登记进去会让
    // 用户按台账调到半个包；写失败不阻断回执（台账是便利面，node_modules 才是权威）
    try {
      const preferred = (Array.isArray(data.specs) ? data.specs : [])
        .map((spec) => specPackageNameOf(spec));
      const merged = scan.mergeBinLedger(String(data.prefix), preferred);
      // 措辞口径：updated = 本次全树扫描到的命令名数（安装区现存），total = 台账记录数
      // （装前不清账，可能含已消失包的条目）——两值分列，不说「本次登记」也不说「全部可用」
      if (merged.updated > 0) {
        notes.push('安装区现有 ' + merged.updated + ' 个命令行工具，安装记录共 '
          + merged.total + ' 条。');
      }
      if (merged.overwritten.length > 0) {
        notes.push('命令 ' + merged.overwritten.join('、') + ' 已改由新装的包提供。');
      }
    } catch (e) {
      console.error('[npm-worker] bin 台账写入失败', errorText(e));
    }
  }
  if (notes.length > 0) {
    receipt.cleanupNote = notes.join('');
  }
  ledger.ok = receipt.ok === true;
  ledger.exitCode = receipt.exitCode;
  ledger.error = receipt.error;
  ledger.time = new Date().toISOString();
  try {
    appendInstallLedger(String(data.prefix), ledger);
  } catch (e) {
    // 台账失败不影响安装结果（appendInstallLedger 内部已吞读写异常，这里是双保险）
  }
  return receipt;
}

// ── worker 主循环（workerData = bootstrap 派发载荷）──

function startNpmWorker() {
  const port = workerThreads.parentPort;
  const data = workerThreads.workerData || {};
  let settled = false;
  // 附注旁路（A3）：主线程只在本轮被 terminate 时才需要这些附注（回执载荷会随 terminate 丢失）
  core.setNoteSink((message) => {
    port.postMessage(message);
  });
  // 终止前 flush（A6）：主线程 terminate 之前先索要一次日志尾与当前阶段；本处理器同步回，
  // 拿不到（worker 已卡死）由主线程按 FLUSH_TIMEOUT_MS 判「日志尾部不可得」
  port.on('message', (message) => {
    if (message === null || typeof message !== 'object' || message.type !== 'flush') {
      return;
    }
    const reply = { type: 'flush' };
    const capture = core.getActiveCapture();
    if (capture !== null) {
      reply.logTail = capture.tail();
    }
    const heartbeat = core.getActiveHeartbeat();
    if (heartbeat !== null) {
      reply.stage = heartbeat.stage();
    }
    try {
      port.postMessage(reply);
    } catch (e) {
      // 主线程已脱手；flush 丢失无害
    }
  });
  const postResult = (receipt) => {
    if (settled) {
      return;
    }
    settled = true;
    try {
      port.postMessage(Object.assign({ type: 'result', requestId: data.requestId }, receipt));
    } catch (e) {
      console.error('[npm-worker] 回执发送失败', errorText(e));
    }
    // 兜底自退：npm 遗留句柄会让事件循环不自空；bootstrap 收到回执即 terminate，这道
    // unref 计时器只在 terminate 失灵时收尾（循环已空则自然退出轮不到它）
    setTimeout(() => process.exit(0), 5000).unref();
  };
  process.on('uncaughtException', (e) => {
    console.error('[npm-worker] uncaughtException', errorText(e));
    postResult(Object.assign(core.basePayload('crashed', Date.now(), '', core.createLogCapture()),
      { errorDetail: 'uncaughtException ' + errorText(e) }));
    setTimeout(() => process.exit(1), 500).unref();
  });
  process.on('unhandledRejection', (e) => {
    console.error('[npm-worker] unhandledRejection', errorText(e));
    postResult(Object.assign(core.basePayload('crashed', Date.now(), '', core.createLogCapture()),
      { errorDetail: 'unhandledRejection ' + errorText(e) }));
    setTimeout(() => process.exit(1), 500).unref();
  });
  runInstall(data).then(postResult).catch((e) => {
    postResult(Object.assign(core.basePayload('internal-error', Date.now(), '', core.createLogCapture()),
      { errorDetail: errorText(e) }));
  });
}

if (isWorkerThread()) {
  startNpmWorker();
}

// ── 控制面编排入口（bootstrap 主线程调用：派 worker + 心跳回调 + 看门狗 + 终止收口）──
// bootstrap 只留路由薄层与互斥位（防其越 1200 硬线），本段是 install 的全部主线程编排。

// 终态回执骨架（默认值兜底；worker 回执 / 终止路径逐项覆写）
function receiptPayload(error) {
  return {
    ok: false,
    error: error,
    exitCode: error === '' ? 0 : 1,
    errorCode: '',
    errorDetail: '',
    stage: '',
    elapsedMs: 0,
    logTail: [],
    packages: [],
    packagesTotal: 0,
    packagesTruncated: false,
    wasmNote: '',
    rolledBack: false,
    violations: [],
    cleanupNote: '',
    memory: process.memoryUsage(),
    nodeVersion: process.version,
    platform: process.platform
  };
}

// worker 终态回执的透传字段白名单（type/requestId 等信封字段不混入回执）
const INSTALL_RESULT_FIELDS = ['ok', 'error', 'exitCode', 'errorCode', 'errorDetail', 'stage',
  'elapsedMs', 'logTail', 'packages', 'packagesTotal', 'packagesTruncated', 'wasmNote',
  'rolledBack', 'violations', 'cleanupNote', 'memory'];

// 终止前向 worker 索要一次日志尾与阶段（A6；限时 FLUSH_TIMEOUT_MS，取不到回 null）
function requestFlush(worker) {
  return new Promise((resolve) => {
    let done = false;
    const settle = (value) => {
      if (done) {
        return;
      }
      done = true;
      clearTimeout(timer);
      worker.removeListener('message', onMessage);
      resolve(value);
    };
    const onMessage = (message) => {
      if (message !== null && typeof message === 'object' && message.type === 'flush') {
        settle(message);
      }
    };
    const timer = setTimeout(() => {
      settle(null);
    }, FLUSH_TIMEOUT_MS);
    worker.on('message', onMessage);
    try {
      worker.postMessage({ type: 'flush' });
    } catch (e) {
      settle(null);
    }
  });
}

// 派一轮 install worker 并收口终态：resolve 回完整回执载荷（bootstrap 补 requestId 信封即可）。
// hooks.onSettled 在互斥位释放点回调（幂等）；返回的 terminateWith(reason) 供 cancel/drop/看门狗
// 落刀——落刀后无论 exit 事件是否到达都 settle（terminate 卡死不吊死请求）。
function launchInstall(request, paths, hooks) {
  const hookApi = hooks !== undefined && hooks !== null ? hooks : {};
  const startAt = Date.now();
  const noteLines = [];
  const releaseSettled = () => {
    if (typeof hookApi.onSettled === 'function') {
      hookApi.onSettled();
    }
  };
  let worker = null;
  try {
    worker = new workerThreads.Worker(path.join(paths.homeDir, 'npm-worker.js'), {
      workerData: {
        requestId: request.requestId,
        sessionId: typeof request.sessionId === 'string' ? request.sessionId : '',
        specs: request.specs,
        prefix: paths.installRootDir,
        cacheDir: path.join(paths.installRootDir, 'cache'),
        npmLibPath: path.join(paths.homeDir, 'npm', 'lib', 'npm.js')
      }
    });
  } catch (e) {
    // 派发同步抛错（脚本缺失 / 线程创建失败）不得锁死互斥位（Y4 观察）：立即释放并回
    // internal-error，后续 install 不再被 install-running 拒
    console.error('[npm-worker] worker 派发失败', errorText(e));
    releaseSettled();
    return {
      promise: Promise.resolve(Object.assign(receiptPayload('internal-error'), {
        errorDetail: 'npm worker 派发失败，' + errorText(e),
        elapsedMs: Date.now() - startAt
      })),
      terminateWith: () => {}
    };
  }
  let stage = 'resolve';
  let terminating = null;
  let terminateFlow = false;
  let settled = false;
  let timer = null;
  let settleWith = null;
  let flushTail = [];
  const promise = new Promise((resolve) => {
    settleWith = resolve;
  });
  // 终止轮次补台账（A5）：被 terminate 的轮次 worker 内台账写不出，主线程补一条审计记录
  const recordTerminateLedger = (reason) => {
    try {
      appendInstallLedger(paths.installRootDir, {
        specs: Array.isArray(request.specs) ? request.specs : [],
        ok: false,
        exitCode: 1,
        error: reason,
        packages: [],
        time: new Date().toISOString()
      });
    } catch (e) {
      console.error('[npm-worker] 终止轮次台账写入失败', errorText(e));
    }
  };
  const finish = (payload, terminateReason) => {
    if (settled) {
      return;
    }
    settled = true;
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
    worker.removeListener('message', onMessage);
    worker.removeListener('exit', onExit);
    worker.removeListener('error', onError);
    if (terminateReason !== undefined && terminateReason !== '') {
      recordTerminateLedger(terminateReason);
    }
    releaseSettled();
    settleWith(Object.assign(receiptPayload('internal-error'), payload));
    // 终态即 terminate（worker 可能残留 npm keep-alive 句柄，事件循环不自空）
    worker.terminate().catch((e) => {
      console.error('[npm-worker] terminate 失败', errorText(e));
    });
  };
  const onMessage = (message) => {
    if (message === null || typeof message !== 'object') {
      return;
    }
    if (message.type === 'stage' && typeof message.stage === 'string') {
      stage = message.stage; // 心跳阶段标记（终止回执标注用）
      return;
    }
    if (message.type === 'note' && typeof message.text === 'string') {
      noteLines.push(message.text); // 运行期附注（安装前清扫计数等），终止回执用
      return;
    }
    if (message.type === 'result' && message.requestId === request.requestId) {
      const payload = {};
      for (const key of INSTALL_RESULT_FIELDS) {
        if (message[key] !== undefined) {
          payload[key] = message[key];
        }
      }
      finish(payload);
    }
  };
  const onExit = (code) => {
    if (terminateFlow) {
      // 终止流程自己收口（flush → terminate → 清扫 → finish）；exit 只表示落刀完成，
      // 不在这里抢 settle——否则清扫与 flush 日志尾全丢（本轮实测过这个竞态）
      return;
    }
    // 意外退出（含 worker 内 process.exit / V8 崩溃）：terminate 路径按其终止原因回执
    finish(terminating !== null
      ? {
        error: terminating, stage: stage, elapsedMs: Date.now() - startAt,
        cleanupNote: noteLines.join('')
      }
      : {
        error: 'crashed', exitCode: code, stage: stage, elapsedMs: Date.now() - startAt,
        errorDetail: 'npm worker 意外退出，退出码 ' + String(code),
        cleanupNote: noteLines.join('')
      }, terminating !== null ? terminating : '');
  };
  const onError = (e) => {
    console.error('[npm-worker] worker 异常', errorText(e));
    onExit(1);
  };
  // 终止路全树二进制清扫（Y5②）：看门狗超时 / cancel / drop 留下的增量若不在此清掉，会被下一次
  // install 的 before 快照吸收 → 二进制永久留在 node_modules。只在 worker 已落刀后调用
  const sweepTerminatedRound = () => {
    const swept = scan.sweepBinaryFiles(paths.installRootDir);
    if (swept.removed.length > 0) {
      noteLines.push('终止后清理了 ' + swept.removed.length + ' 个二进制文件残留。');
    }
    if (swept.failed.length > 0) {
      noteLines.push('有 ' + swept.failed.length + ' 个残留文件没清掉。');
    }
  };
  const terminateWith = (reason) => {
    if (terminating !== null || settled) {
      return;
    }
    terminating = reason;
    terminateFlow = true;
    // 先 flush 再 terminate（A6）：terminate 之后 worker 内存里的日志尾与阶段全没了——超时 /
    // 取消回执只剩心跳阶段、logTail 恒空，用户面看不到「停在哪一步」
    requestFlush(worker).then((flush) => {
      if (flush !== null && typeof flush.stage === 'string' && flush.stage !== '') {
        stage = flush.stage;
      }
      if (flush !== null && Array.isArray(flush.logTail) && flush.logTail.length > 0) {
        flushTail = flush.logTail;
      } else {
        noteLines.push('终止时日志尾部不可得。');
      }
      return worker.terminate();
    }).catch((e) => {
      console.error('[npm-worker] 终止流程异常', errorText(e));
    }).then(() => {
      if (settled) {
        return; // 结果回执已先到（正常收尾），不做终止侧清扫与台账
      }
      sweepTerminatedRound();
      finish({
        error: reason,
        stage: stage,
        elapsedMs: Date.now() - startAt,
        logTail: flushTail,
        cleanupNote: noteLines.join('')
      }, reason);
    });
  };
  // 整体看门狗：超时 terminate + 回执带最后心跳阶段与 flush 日志尾（dsh 静默卡死对冲件，
  // 禁拖满无回执）
  timer = setTimeout(() => {
    terminateWith('timeout');
  }, request.timeoutMs);
  worker.on('message', onMessage);
  worker.on('exit', onExit);
  worker.on('error', onError);
  return { promise: promise, terminateWith: terminateWith };
}

module.exports = {
  isWorkerThread,
  validateSpecs: core.validateSpecs,
  launchInstall,
  snapshotInstallState: scan.snapshotInstallState,
  checkInstallSafety: scan.checkInstallSafety,
  applyRollback: scan.applyRollback,
  rollbackAfterViolation: scan.rollbackAfterViolation,
  reinstallFromManifests: scan.reinstallFromManifests,
  collectBinaryFiles: scan.collectBinaryFiles,
  sweepBinaryFiles: scan.sweepBinaryFiles,
  buildBinLedger: scan.buildBinLedger,
  mergeBinLedger: scan.mergeBinLedger,
  readBinLedger: scan.readBinLedger,
  BIN_LEDGER_FILE: scan.BIN_LEDGER_FILE,
  summarizePackages: core.summarizePackages,
  measureTreeBytes: core.measureTreeBytes,
  appendInstallLedger,
  REGISTRY_DEFAULT: core.REGISTRY_DEFAULT,
  FETCH_TIMEOUT_DEFAULT_MS: core.FETCH_TIMEOUT_DEFAULT_MS,
  INSTALL_QUOTA_BYTES: core.INSTALL_QUOTA_BYTES,
  INSTALL_LEDGER_MAX,
  VIOLATION_REPORT_MAX: scan.VIOLATION_REPORT_MAX
};
