// Node 常驻引导脚本（2026-11-23 鸿蒙 Node 运行时门 2，任务书-鸿蒙Node运行时门2-20261123
// §3.2「IPC 与鉴权」/§3.3「worker、状态、cwd 与取消」/§3.1「运行区与单飞准备」）：由
// NodeEngine.cpp 组 argv 经 node::Start 启动执行（argv[1]）。
// · 角色划分：本文件 = 控制面（listen + 鉴权 + 状态 + 动作路由 + 执行域调度）；执行域 worker
//   内核在 session-worker.js（每会话一个长期 worker，worker 内一个长期 vm context）；npm 解包
//   归 runtime-setup.js。
// · 执行域（S3）：exec 载荷 = {sessionId, code, cwd, timeoutMs}；注册表上限
//   NODE_SESSION_WORKER_LIMIT = 3，第 4 个会话淘汰最久未用的空闲 worker（运行中的 worker 不
//   淘汰）。sessionReset 描述本次执行所用 context 为何是新建的：created（会话首启）/ evicted
//   （上次被容量淘汰）/ 空串（复用既有 context）；终态回执按终态标 cancelled / timeout /
//   crashed / dropped / terminated-background / bin-reset（上次是 bin 轮，按隔离口径回收，见
//   下方 bin 运行域）。evictedSessionIds 单独列本次被淘汰的其他会话，
//   与新会话自身的 sessionReset 不混用。无 sessionId 直接错误回执，不建 worker、不建目录。
// · cwd：exec 受理后主线程 process.chdir(cwd)（worker 继承进程 cwd），回执、异常、取消、超时
//   都在 finally 恢复先前 cwd（回执 cwdRestored 如实回报）；worker 内不 chdir。cwd 只是默认
//   目录，不是文件沙箱。
// · npm 安装域（门 3 U1，任务书 §2.1/§2.2）：install 第五动作只留路由薄层——运行区准备期
//   有界等待（冷启首装不得直接回 not-ready）→ 会话标识必填（cancel/drop 归属键）→ 参数闸（spec
//   规则单源在 npm-worker.js 的 validateSpecs）→ 互斥（同刻恰一个 install，第二个回
//   install-running）→ 派 npm-worker → 注册回执回调；引擎逻辑全沉 npm-worker.js。install 不占
//   exec 串行面（npm worker 与会话 worker 物理隔离，落点走 --prefix 不碰 cwd，主线程零 chdir）；
//   不入会话注册表、不占 NODE_SESSION_WORKER_LIMIT。cancel/drop 命中 install 归属 sessionId 即
//   terminate 其 worker（请求侧收 cancelled/dropped 终态）。落点 = HOME 同级的 node/ 目录
//   （filesDir/node/，方案档 ⑬——HOME 由宿主经 Context 取后 setenv 传入，本文件只从其父级派生，
//   不拼四级沙箱前缀）。status 另透出主线程 argv/title/execPath/cwd/env 摘要（install 前后一致性
//   断言族用，不凭记忆断言）。
// · bin 运行域（门 3 U3）：run_bin 第六动作只做参数 fail-closed（sessionId 必填、bin 非空无
//   空白、args ≤16 条且每条 ≤200 字符、timeoutMs 沿用 exec 上限）与串行，执行沉在会话 worker
//   的 bin 轮（bin-runner.js 按 bin 台账 Module._load 入口，不建链接、不 spawn、不走 PATH）。
//   回执另带 bin / exitCode / durationMs / binPackage / binReplaced 五字段。
//   ★ 隔离（2026-11-24 补正）：bin 内定时器 / socket / process 监听不在会话轮的观测面内
//   （backgroundOps 恒 0），残留会拖到下轮 cwd 下触发——故 bin 轮结束一律 terminate 该会话
//   worker，下轮冷启（sessionReset = bin-reset）。代价 = 每轮多一次冷启、bin 的异步尾巴被砍。
// · 终态回执与槽位释放：cancel / drop / 超时 / worker 崩溃（含 process.exit）/ 轮末仍有已跟踪
//   后台句柄，都由本文件 terminate 对应会话 worker、等 terminate settle 后立即回终态并 settle
//   在场的 exec；迟到回执按 requestId 丢弃。删除会话或 worker 崩溃后，新执行不得被旧请求堵到
//   超时。
// · 串行：bootstrap 侧只允许一段用户代码在跑（execRunning，并发 exec 直接回 busy）——全局并发
//   1 的产品级 lane 归 ArkTS 侧 NodeScheduler，本文件只做最后一道防串行破坏（cwd 是进程级，
//   两段用户代码并发 = 相对路径落点互相污染）。cancel / drop / status 恒不经这条串行面。
// · 启动序列：读 HOME → 读 placement-spec（只为解析通道）→ 删陈旧 endpoint / socket /
//   bridge.port（ENOENT 容错，防假就绪——门 1 陈旧端口教训）→ listen（**先 listen 再解包**：
//   解包中与解包失败都能经鉴权 status 读到）→ listen 回调内原子写 bridge.endpoint（临时文件
//   + rename，mode 0600）→ 启动唯一一次解包（beginPrepare）→ 常驻消息循环。listen 之前的
//   任何失败写 <HOME>/setup-error.json（{stage,path,errno,at}，不含 token），宿主 NodeRuntime
//   超时分支读出原文透出。准备失败后本进程不可重试（node::Start 单次），下次冷启再试。
// · 启动失败处置：只写 setup-error + `process.exitCode = 1` 并放弃后续排程，**禁 process.exit**
//   （嵌入式 Node 上可能终止整个应用进程）。每条失败路径都确认过零残留 handle（未建 server /
//   server 已 close / 无计时器），事件循环自然退出，宿主见到 node::Start 返回后读 setup-error。
// · 鉴权协议：一请求一连接，一行 JSON 请求一行 JSON 回执；首包即含 {protocol,token,action,
//   requestId}；请求上限 1 MiB；token 先比 **UTF-8 字节长度**再 timingSafeEqual（长度不等直接
//   拒——按字符长度预检挡不住多字节 token，仍会抛 ERR_CRYPTO_TIMING_SAFE_EQUAL_LENGTH）；无
//   token / 错 token → unauthorized，协议不符 / 超 1 MiB → bad-request，都在执行前关闭，
//   回执不含 token（hilog 与回执均不泄漏有效 token）。
// · 字节层缓冲：请求按 Buffer 累积、换行切分在字节层完成、整行一次 decode——逐片解码再拼接
//   会把跨片的多字节字符打成 U+FFFD（中文 code / 中文 requestId 的场景）。
// · 连接寿命：连接建立到「首包完整请求行」到达之间 30 s 限时（FIRST_PACKET_TIMEOUT_MS），
//   首包到达即取消该计时；此后连接寿命交给动作自身（exec 的 timeoutMs 与终态回执），
//   **不设整条连接总时限**（否则默认 120 s、上限 300 s 的 exec 必被砍）。首包前客户端死亡
//   由计时器 destroy 收口，首包后客户端死亡由 close / error 事件收口——不产生无界连接。
// · 通道：env NODE_BRIDGE_CHANNEL（tcp|uds，非法值 = setup-error 拒启）优先，缺省读
//   placement-spec.json 的 channel（由宿主 NodeRuntime 单常量写入），再缺省 tcp。本地
//   test-runtime.cjs 经 env 覆盖实现两路受控测试入口；交付态两路最终都收敛到宿主常量。
// · HOME 定位：沿用门 1 口径 = 宿主 NodeEngine.cpp setenv("HOME",...) / 本机测试经 env 注入。
'use strict';

const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Worker } = require('node:worker_threads');
const setup = require('./runtime-setup.js');
const npmWorkerMod = require('./npm-worker.js');

const PROTOCOL = 1;
const REQUEST_LIMIT_BYTES = 1024 * 1024; // 请求上限 1 MiB
const CHANNELS = ['tcp', 'uds'];
const ENDPOINT_NAME = 'bridge.endpoint';
const ENDPOINT_TMP_SUFFIX = '.tmp';
const SOCKET_NAME = 'bridge.sock';
const STALE_PORT_NAME = 'bridge.port'; // 门 1 陈旧端口文件（冷启一并清，防假就绪）
const SETUP_ERROR_NAME = 'setup-error.json';
const UDS_MAX_PATH_BYTES = 107; // AF_UNIX sockaddr_un.sun_path 上限（双端各自校验）
const TOKEN_BYTES = 32; // 32 字节随机 → 64 hex 字符
// 首包等待上限：连接建立 → 首包完整请求行到达之间；首包到达即取消（见文件头「连接寿命」）。
// 环境变量 NODE_BRIDGE_FIRST_PACKET_TIMEOUT_MS = 本机受控测试入口（同 NODE_BRIDGE_CHANNEL 口径，
// 用短时限验语义，禁为测试真等 30 s；非法值回落默认）
const DEFAULT_FIRST_PACKET_TIMEOUT_MS = 30000;
const FIRST_PACKET_TIMEOUT_MS = readFirstPacketTimeoutMs();

// 执行域常量（任务书 §3.3）：每会话一个长期 worker，常驻上限 3；第 4 个会话淘汰最久未用的
// 空闲 worker（运行中的不淘汰）
const NODE_SESSION_WORKER_LIMIT = 3;
// sessionId 长度上限（只防无界 map 键；会话 id 由 ArkTS 侧生成）
const SESSION_ID_MAX_LENGTH = 200;
// bin 运行参数上限（传输层护栏；产品口径 16 条 / 每条 200 字符归 ArkTS 侧工具面单源）
const BIN_NAME_MAX_LENGTH = 100;
const BIN_ARGS_MAX = 16;
const BIN_ARG_MAX_LENGTH = 200;
// 执行超时上限（传输层护栏；产品口径 1~300 s 与默认 120 s 归 ArkTS 侧 NodeScheduler 单源，
// 本文件只拒绝显然失控的值——缺省/非法一律 bad-request，不替调用方猜默认值）
const EXEC_TIMEOUT_MAX_MS = 600000;
// worker 首包 ready 等待上限（worker 启动异常时尽快回错，不吊死在 shim/线程创建失败上）
const WORKER_READY_TIMEOUT_MS = 10000;
// install 整体看门狗上限（传输层护栏；默认 10 min 归 ArkTS 侧 NodeScheduler 单源，本文件只拒
// 显然失控的值——缺省/非法一律 bad-request，不替调用方猜默认值）
const INSTALL_TIMEOUT_MAX_MS = 1800000;
// install 等待准备就绪的上限（Y4）：endpoint 在 listen 回调里先写、解包在同一回调里分片让出，
// 所以冷启后的第一个 install 必然落在准备期。这里按「请求自身超时与 120 s 的较小值」有界等待
// ——准备占用的是用户可见等待时间，不该比用户给的安装超时长；120 s 与宿主 NodeRuntime 的准备
// 等待上限同量级，只是兜底（实测解包 wall 远小于此）。
const INSTALL_PREPARE_WAIT_MAX_MS = 120000;
const INSTALL_PREPARE_POLL_MS = 100;

// HOME 由宿主 NodeEngine.cpp 以 setenv 传入（六步第④步），本机测试经 env 注入
const homeDir = process.env.HOME || '';
const endpointPath = homeDir !== '' ? path.join(homeDir, ENDPOINT_NAME) : '';
const socketPath = homeDir !== '' ? path.join(homeDir, SOCKET_NAME) : '';
const stalePortPath = homeDir !== '' ? path.join(homeDir, STALE_PORT_NAME) : '';
const setupErrorPath = homeDir !== '' ? path.join(homeDir, SETUP_ERROR_NAME) : '';

// ── 小工具 ──

// 独立错误串化（不进回执只进 hilog/console；确保任何对象异常都变串）
function errorText(e) {
  if (e instanceof Error) {
    return e.message;
  }
  try {
    return String(e);
  } catch (err) {
    return 'unknown-error';
  }
}

// 首包等待上限读取（受控测试入口；缺省 / 非正整数一律回落默认，不因环境脏值改变交付语义）
function readFirstPacketTimeoutMs() {
  const raw = process.env.NODE_BRIDGE_FIRST_PACKET_TIMEOUT_MS;
  const value = raw === undefined || raw === '' ? NaN : Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    return DEFAULT_FIRST_PACKET_TIMEOUT_MS;
  }
  return value;
}

// 启动失败收口：写 setup-error + 置退出码（禁 process.exit），调用方随即放弃后续排程
function failStartup(stage, target, e) {
  writeSetupError(stage, target, e);
  process.exitCode = 1;
}

// ENOENT 容错删除（残留处置：文件不存在 = 目标态）
function unlinkQuiet(target) {
  if (target === '') {
    return;
  }
  try {
    fs.unlinkSync(target);
  } catch (e) {
    // ENOENT = 目标态；其他错误交由 hilog（不阻断启动——listen 才是真闸）
    if (e && e.code !== 'ENOENT') {
      console.error('[bootstrap] unlink failed', target, errorText(e));
    }
  }
}

// listen 之前的失败落 setup-error.json（不含 token；失败容忍——写不进去只剩 hilog）
function writeSetupError(stage, target, e) {
  const payload = {
    stage: stage,
    path: target,
    errno: e && e.code ? e.code : '',
    at: Date.now()
  };
  console.error('[bootstrap] setup failed stage=' + stage, errorText(e));
  if (setupErrorPath === '') {
    return;
  }
  try {
    fs.writeFileSync(setupErrorPath, JSON.stringify(payload), { mode: 0o600 });
  } catch (err) {
    console.error('[bootstrap] write setup-error failed', errorText(err));
  }
}

// 通道解析：env（受控测试入口）优先 → placement-spec 的 channel（宿主常量单源）→ tcp
function resolveChannel(spec) {
  const fromEnv = process.env.NODE_BRIDGE_CHANNEL;
  if (fromEnv !== undefined && fromEnv !== '') {
    if (CHANNELS.indexOf(fromEnv) >= 0) {
      return fromEnv;
    }
    throw new Error('NODE_BRIDGE_CHANNEL 非法值 ' + fromEnv);
  }
  if (spec !== null && typeof spec.channel === 'string' && CHANNELS.indexOf(spec.channel) >= 0) {
    return spec.channel;
  }
  return 'tcp';
}

// UDS 路径字节数校验（UTF-8 ≤107；服务端侧）
function udsPathBytesTooLong(target) {
  return Buffer.byteLength(target, 'utf8') > UDS_MAX_PATH_BYTES;
}

// ── 准备态（S2：先 listen 再解包；状态经鉴权 status 可读 running/ready/failed）──

// spec 只为解析通道先读一次；读失败不在此收口（beginPrepare 会如实转 failed + prepareError）
let spec = null;
try {
  spec = setup.readPlacementSpec(homeDir);
} catch (e) {
  console.error('[bootstrap] placement-spec 读取失败', errorText(e));
}

// 准备 handle：listen 就绪后启动，本进程只启动一次（node::Start 单次，失败不可重试）
let preparer = null;

// 准备态快照（status 与 exec 共用；listen 回调启动解包前按 running 保守呈现）
function prepareSnapshot() {
  if (preparer !== null) {
    return preparer.snapshot();
  }
  return { prepare: 'running', prepareError: '', npmVersion: '', prepareStats: null };
}

// 监听通道（listen 成功后由 startControlPlane 赋值；status 回执读它）
let channel = 'tcp';

// 鉴权令牌：随机 32 字节 hex；不进 hilog、不进回执、不进任何日志
const token = crypto.randomBytes(TOKEN_BYTES).toString('hex');
// 令牌字节形态与字节长度（比较面用字节口径——字符长度在多字节 token 上不成立）
const tokenBytes = Buffer.from(token, 'utf8');

// ── 执行域状态（S3：worker-per-session 注册表 + 会话重置原因 + 串行面）──

// 注册表：sessionId → { worker, lastUsedAt, running, terminating, inflight, requestId }。
// 顺序即 LRU 候选集：lastUsedAt 最小且未运行的空闲 worker 先淘汰
const sessions = new Map();
// 会话重置原因（下次为该会话建 context 时消费一次）：evicted / cancelled / timeout / crashed /
// terminated-background。worker 被终止后会话已不在注册表里，但下次执行仍要如实标「为何新建」；
// 表有上限，只记最近 N 个会话，防无界增长
const resetReasons = new Map();
const RESET_REASON_LIMIT = 64;
// 串行面：一段用户代码在跑时，第二个 exec 直接回 busy（产品级 lane 归 ArkTS 侧 NodeScheduler，
// 这里只护 cwd 属进程级这条物理约束——见文件头「串行」）
let execRunning = false;
// worker 脚本路径（设备侧 = <HOME>/session-worker.js；本机测试 = 临时 HOME 里的同名件）
const workerScriptPath = homeDir !== '' ? path.join(homeDir, 'session-worker.js') : '';
// 终态错误码（回执 sessionReset 与 error 同源；dropped 不在 sessionReset 值域内，回执标 cancelled）
const TERMINAL_ERRORS = ['cancelled', 'timeout', 'crashed', 'dropped', 'terminated-background'];
// ── npm 安装域状态（门 3 U1；互斥位 = 同刻恰一个 install）──
// 安装落点（方案档 ⑬）：filesDir/node/ = HOME 同级的 node 目录（HOME 由宿主经 Context 取后
// setenv 传入，这里只从其父级派生）；package.json / node_modules / lockfile / cache 都落该子树
const installRootDir = homeDir !== '' ? path.join(path.dirname(homeDir), 'node') : '';
// 在飞 install：{ worker, sessionId, stage, terminating, terminateWith }；终态/超时/取消/崩溃清空
let installFlight = null;

// ── 动作路由（全部执行前鉴权已过）──

// 主线程 env 稳定摘要（install 前后一致性断言用：只比哈希不回传 env 本体，无泄漏面）
function envDigest() {
  const keys = Object.keys(process.env).sort();
  const digest = crypto.createHash('sha256');
  for (const key of keys) {
    digest.update(key + '=' + String(process.env[key]) + '\n');
  }
  return digest.digest('hex');
}

function statusPayload() {
  const prepare = prepareSnapshot();
  const payload = {
    channel: channel,
    nodeVersion: process.version,
    npmVersion: prepare.npmVersion, // 就绪后由 npm/package.json 实读回填，空串 = 未落位
    prepare: prepare.prepare,
    workers: sessions.size,
    memory: process.memoryUsage(),
    // 主线程读数（门 3 U1 隔离断言族：install 前后这五项必须逐项一致，不凭记忆断言）
    mainArgv: process.argv.slice(),
    mainTitle: process.title,
    mainExecPath: process.execPath,
    mainCwd: process.cwd(),
    mainEnvDigest: envDigest()
  };
  if (prepare.prepareError !== '') {
    payload.prepareError = prepare.prepareError;
  }
  if (prepare.prepareStats !== null) {
    payload.prepareStats = prepare.prepareStats;
  }
  return payload;
}

function handleAuthorizedRequest(request) {
  const action = request.action;
  if (action === 'status') {
    return Object.assign({ requestId: request.requestId, ok: true }, statusPayload());
  }
  if (action === 'exec') {
    return handleExec(request); // 异步：执行时长由请求的 timeoutMs 决定
  }
  if (action === 'cancel') {
    return handleCancel(request);
  }
  if (action === 'drop') {
    return handleDrop(request);
  }
  if (action === 'install') {
    return handleInstall(request); // 异步：终态回执由 npm-worker 生命周期决定
  }
  if (action === 'run_bin') {
    return handleRunBin(request); // 异步：执行轮由会话 worker 的 bin 轮种承担
  }
  return { requestId: request.requestId, ok: false, error: 'bad-request' };
}

// ── 执行域（S3：worker-per-session、LRU、cwd、取消/超时/崩溃终态）──

function taggedError(code, cause) {
  const error = new Error(cause !== undefined && cause !== null && cause.message !== undefined
    ? cause.message : 'exec-failure');
  error.execCode = code;
  return error;
}

// 记一次「下次建 context 的原因」（容量上限内只留最近 N 个会话）
function recordResetReason(sessionId, reason) {
  if (reason === '' || reason === 'dropped') {
    return;
  }
  resetReasons.set(sessionId, reason);
  while (resetReasons.size > RESET_REASON_LIMIT) {
    const oldest = resetReasons.keys().next().value;
    resetReasons.delete(oldest);
  }
}

function consumeResetReason(sessionId) {
  const reason = resetReasons.get(sessionId);
  if (reason === undefined) {
    return '';
  }
  resetReasons.delete(sessionId);
  return reason;
}

// 从注册表摘除并记重置原因（幂等：terminate 与 exit 两条路径都会走到）
function discardEntry(entry, reason) {
  if (sessions.get(entry.sessionId) === entry) {
    sessions.delete(entry.sessionId);
  }
  recordResetReason(entry.sessionId, reason);
}

function onWorkerGone(entry) {
  discardEntry(entry, entry.terminating !== null ? entry.terminating : 'crashed');
}

// 建 worker（长期驻留；worker 内 vm context 由 session-worker.js 自持；npmRequireEntry =
// 安装落点的回退解析基点，门 3 U1 方案档 ⑬ 的 require 补位）
function createSessionWorker(sessionId, cwd) {
  if (workerScriptPath === '' || !fs.existsSync(workerScriptPath)) {
    throw taggedError('crashed', new Error('session-worker.js 缺失'));
  }
  const worker = new Worker(workerScriptPath, {
    workerData: {
      sessionId: sessionId,
      cwd: cwd,
      npmRequireEntry: installRootDir !== ''
        ? path.join(installRootDir, 'node_modules', '.exec-node-entry.cjs') : '',
      // bin 轮（门 3 U3）：运行器在 HOME，台账在安装落点根——两者都由本文件派生后注入
      homeDir: homeDir,
      ledgerPath: installRootDir !== ''
        ? path.join(installRootDir, 'bin-ledger.json') : ''
    }
  });
  const entry = {
    sessionId: sessionId,
    worker: worker,
    lastUsedAt: Date.now(),
    running: false,
    terminating: null,
    inflight: null,
    requestId: ''
  };
  // 常驻监听：worker 意外退出（含用户 process.exit）时同步摘册，下一轮不得被旧请求堵住
  worker.on('exit', () => {
    onWorkerGone(entry);
  });
  worker.on('error', (e) => {
    console.error('[bootstrap] session worker 异常', errorText(e));
    onWorkerGone(entry);
  });
  return entry;
}

// 等 worker 报 ready（上下文就绪；首启成本计入回执 workerStartMs）
function waitWorkerReady(entry) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      entry.worker.removeListener('message', onMessage);
      entry.worker.removeListener('exit', onExit);
      entry.worker.removeListener('error', onError);
      if (error === null) {
        resolve();
      } else {
        reject(error);
      }
    };
    const onMessage = (message) => {
      if (message !== null && typeof message === 'object' && message.type === 'ready') {
        finish(null);
      }
    };
    const onExit = (code) => {
      finish(new Error('worker 启动即退出，退出码 ' + String(code)));
    };
    const onError = (e) => {
      finish(new Error('worker 启动失败，' + errorText(e)));
    };
    const timer = setTimeout(() => {
      finish(new Error('worker 启动超时'));
    }, WORKER_READY_TIMEOUT_MS);
    entry.worker.on('message', onMessage);
    entry.worker.on('exit', onExit);
    entry.worker.on('error', onError);
  });
}

// 终态回执的统一骨架（ok=false + 空产物；elapsedMs 由调用方起点算）
function terminalOutcome(errorCode, startAt) {
  return {
    ok: false,
    error: errorCode,
    stdout: '',
    stderr: '',
    stdoutTruncated: false,
    stderrTruncated: false,
    savedNames: [],
    events: [],
    eventsKept: 0,
    eventsTotal: 0,
    eventsNote: '',
    backgroundOps: 0,
    elapsedMs: Date.now() - startAt,
    memory: process.memoryUsage()
  };
}

// 策略：只淘汰最久未用的空闲 worker；运行中（或正在终止）的不淘汰
function pickIdleVictim() {
  let victim = null;
  for (const entry of sessions.values()) {
    if (entry.running || entry.terminating !== null) {
      continue;
    }
    if (victim === null || entry.lastUsedAt < victim.lastUsedAt) {
      victim = entry;
    }
  }
  return victim;
}

// 终止一个会话 worker 并等它 settle；在场的 exec 会在 exit 时收到终态回执
async function terminateSession(sessionId, reason) {
  const entry = sessions.get(sessionId);
  if (entry === undefined) {
    return { terminated: false, stopped: false };
  }
  const stopped = entry.inflight !== null;
  entry.terminating = reason;
  sessions.delete(sessionId);
  discardEntry(entry, reason);
  try {
    await entry.worker.terminate();
  } catch (e) {
    console.error('[bootstrap] worker terminate 失败', errorText(e));
  }
  if (entry.inflight !== null) {
    // 兜底：exit 事件未按时到达也要 settle 在场 exec，禁止旧请求把新执行堵到超时
    entry.inflight.settle(terminalOutcome(reason, Date.now()));
  }
  return { terminated: true, stopped: stopped };
}

// 取/建会话 entry：复用 → 空串；淘汰他人 → 被淘汰会话标 evicted；新建 → created 或上次重置原因
async function ensureSessionEntry(sessionId, cwd, evictedSessionIds) {
  const existing = sessions.get(sessionId);
  if (existing !== undefined && existing.terminating === null) {
    existing.lastUsedAt = Date.now();
    return { entry: existing, sessionReset: '', workerStartMs: 0 };
  }
  if (existing !== undefined) {
    sessions.delete(sessionId);
  }
  if (sessions.size >= NODE_SESSION_WORKER_LIMIT) {
    const victim = pickIdleVictim();
    if (victim !== null) {
      evictedSessionIds.push(victim.sessionId);
      await terminateSession(victim.sessionId, 'evicted');
    }
    // 无空闲候选（理论上不会发生——串行面保证最多一段在跑）时不强行淘汰，宁超上限不误杀在跑会话
  }
  const remembered = consumeResetReason(sessionId);
  const sessionReset = remembered === '' ? 'created' : remembered;
  const startAt = Date.now();
  const entry = createSessionWorker(sessionId, cwd);
  sessions.set(sessionId, entry);
  try {
    await waitWorkerReady(entry);
  } catch (e) {
    discardEntry(entry, 'crashed');
    try {
      await entry.worker.terminate();
    } catch (err) {
      // worker 已死
    }
    throw taggedError('crashed', e);
  }
  return { entry: entry, sessionReset: sessionReset, workerStartMs: Date.now() - startAt };
}

// 跑一轮：worker 回结果 / 超时 terminate / 崩溃 settle，三条路径都只 settle 一次。
// 超时由主线程计时器 + terminate 落刀（worker 阻塞在死循环或 Atomics.wait 时也有效）；
// 迟到回执按 requestId 丢弃。
function runSessionRound(entry, request) {
  return new Promise((resolve) => {
    const worker = entry.worker;
    const startAt = Date.now();
    let settled = false;
    let timer = null;
    const cleanup = () => {
      if (timer !== null) {
        clearTimeout(timer);
        timer = null;
      }
      worker.removeListener('message', onMessage);
      worker.removeListener('exit', onExit);
      worker.removeListener('error', onError);
      entry.inflight = null;
      entry.running = false;
    };
    const finish = (outcome) => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      outcome.elapsedMs = Date.now() - startAt;
      if (outcome.memory === undefined) {
        outcome.memory = process.memoryUsage();
      }
      resolve(outcome);
    };
    const onMessage = (message) => {
      if (message === null || typeof message !== 'object' || message.type !== 'result') {
        return;
      }
      if (message.requestId !== request.requestId) {
        return; // 迟到回执按 requestId 丢弃
      }
      finish({
        ok: message.ok === true,
        error: typeof message.error === 'string' ? message.error : '',
        stdout: typeof message.stdout === 'string' ? message.stdout : '',
        stderr: typeof message.stderr === 'string' ? message.stderr : '',
        stdoutTruncated: message.stdoutTruncated === true,
        stderrTruncated: message.stderrTruncated === true,
        savedNames: Array.isArray(message.savedNames) ? message.savedNames : [],
        events: Array.isArray(message.events) ? message.events : [],
        eventsKept: typeof message.eventsKept === 'number' ? message.eventsKept : 0,
        eventsTotal: typeof message.eventsTotal === 'number' ? message.eventsTotal : 0,
        eventsNote: typeof message.eventsNote === 'string' ? message.eventsNote : '',
        backgroundOps: typeof message.backgroundOps === 'number' ? message.backgroundOps : 0,
        exitCode: typeof message.exitCode === 'number' ? message.exitCode : undefined,
        binPackage: typeof message.binPackage === 'string' ? message.binPackage : '',
        binReplaced: message.binReplaced === true,
        memory: message.memory
      });
    };
    const onExit = () => {
      const reason = entry.terminating !== null ? entry.terminating : 'crashed';
      finish(terminalOutcome(reason, startAt));
    };
    const onError = (e) => {
      console.error('[bootstrap] session worker 异常', errorText(e));
      onExit();
    };
    worker.on('message', onMessage);
    worker.on('exit', onExit);
    worker.on('error', onError);
    entry.running = true;
    entry.requestId = request.requestId;
    entry.lastUsedAt = Date.now();
    entry.inflight = { requestId: request.requestId, settle: finish };
    timer = setTimeout(() => {
      terminateSession(entry.sessionId, 'timeout').catch((e) => {
        console.error('[bootstrap] 超时终止失败', errorText(e));
        finish(terminalOutcome('timeout', startAt));
      });
    }, request.timeoutMs);
    const roundMessage = {
      type: request.kind === 'run_bin' ? 'run_bin' : 'run',
      requestId: request.requestId,
      cwd: request.cwd,
      timeoutMs: request.timeoutMs
    };
    if (request.kind === 'run_bin') {
      roundMessage.bin = request.bin;
      roundMessage.args = request.args;
    } else {
      roundMessage.code = request.code;
    }
    worker.postMessage(roundMessage);
  });
}

// 回执骨架（§3.2 全字段；cwdRestored 在 runExec 的 finally 之后回填）。门 3 U3：bin 轮另带
// bin / exitCode / durationMs 三字段（exec 轮不出现，避免两套语义混在一个字段里）
function buildExecReply(request, outcome, sessionReset, workerStartMs, evictedSessionIds, cwd) {
  const reply = {
    requestId: request.requestId,
    ok: outcome.ok === true,
    error: outcome.error,
    stdout: outcome.stdout,
    stderr: outcome.stderr,
    stdoutTruncated: outcome.stdoutTruncated,
    stderrTruncated: outcome.stderrTruncated,
    elapsedMs: outcome.elapsedMs,
    workerStartMs: workerStartMs,
    sessionReset: sessionReset,
    evictedSessionIds: evictedSessionIds,
    savedNames: outcome.savedNames,
    events: outcome.events,
    eventsKept: outcome.eventsKept,
    eventsTotal: outcome.eventsTotal,
    eventsNote: outcome.eventsNote,
    backgroundOps: outcome.backgroundOps,
    memory: outcome.memory,
    nodeVersion: process.version,
    platform: process.platform,
    cwd: cwd,
    cwdRestored: false
  };
  if (request.kind === 'run_bin') {
    reply.bin = request.bin;
    reply.exitCode = typeof outcome.exitCode === 'number' ? outcome.exitCode : 1;
    reply.durationMs = outcome.elapsedMs;
    reply.binPackage = typeof outcome.binPackage === 'string' ? outcome.binPackage : '';
    reply.binReplaced = outcome.binReplaced === true;
  }
  return reply;
}

// 失败回执骨架（参数错误 / 会话缺失 / 运行区未就绪；不建 worker、不建目录）
function simpleFailureReply(requestId, errorCode, prepare) {
  const reply = {
    requestId: requestId,
    ok: false,
    error: errorCode,
    stdout: '',
    stderr: '',
    stdoutTruncated: false,
    stderrTruncated: false,
    elapsedMs: 0,
    workerStartMs: 0,
    sessionReset: '',
    evictedSessionIds: [],
    savedNames: [],
    events: [],
    eventsKept: 0,
    eventsTotal: 0,
    eventsNote: '',
    backgroundOps: 0,
    memory: process.memoryUsage(),
    nodeVersion: process.version,
    platform: process.platform,
    cwd: '',
    cwdRestored: true
  };
  if (prepare !== undefined) {
    reply.prepare = prepare.prepare;
    if (prepare.prepareError !== '') {
      reply.prepareError = prepare.prepareError;
    }
  }
  return reply;
}

// 执行本体：chdir → 取/建 worker → 跑一轮 → 轮末后台句柄处置；finally 恢复 cwd
async function runExec(request) {
  const previousCwd = process.cwd();
  const evictedSessionIds = [];
  let reply = null;
  let restored = false;
  try {
    try {
      process.chdir(request.cwd);
    } catch (e) {
      // 排队期间目录被删（会话临时区清理）→ bad-cwd；此时尚未动 cwd，finally 恢复是幂等的
      throw taggedError('bad-cwd', e);
    }
    const prepared = await ensureSessionEntry(request.sessionId, request.cwd, evictedSessionIds);
    const outcome = await runSessionRound(prepared.entry, request);
    const isTerminal = TERMINAL_ERRORS.indexOf(outcome.error) >= 0;
    let sessionReset = prepared.sessionReset;
    if (isTerminal) {
      sessionReset = outcome.error === 'dropped' ? 'cancelled' : outcome.error;
    }
    reply = buildExecReply(request, outcome, sessionReset, prepared.workerStartMs,
      evictedSessionIds, request.cwd);
    if (outcome.backgroundOps > 0) {
      // 轮末仍有已跟踪的非定时器后台操作（socket / http / 未决 fs）→ terminate 本会话 worker。
      // cwd 是进程级，遗留回调拖到别的会话轮内触发相对路径 I/O 会落进他人临时区，只能整会话作废；
      // 本轮已捕获的输出与 savedNames 如实带回
      await terminateSession(request.sessionId, 'terminated-background');
      reply = buildExecReply(request, Object.assign({}, outcome, {
        ok: false,
        error: 'terminated-background'
      }), 'terminated-background', prepared.workerStartMs, evictedSessionIds, request.cwd);
    }
    if (request.kind === 'run_bin') {
      // bin 轮隔离（门 3 U3 补正，2026-11-24）：bin 内 require 走 Module._load 拿原生模块，定时器 /
      // socket / 未决 fs / process 监听都不在会话轮的观测面内——backgroundOps 恒 0，上一段保护对它
      // 无效，残留回调会拖到下轮的 cwd 下触发（cwd 进程级，见上一段注释）。故 bin 轮一律整会话作废、
      // 下轮冷启（sessionReset 记 bin-reset）；runBin 已同步返回终态，本轮回执不受影响。timeout /
      // cancelled 等已 terminate 的路径再调是 no-op（sessions 里已删），reset 原因不会被覆盖
      await terminateSession(request.sessionId, 'bin-reset');
    }
  } catch (e) {
    const code = e !== null && e !== undefined && typeof e.execCode === 'string'
      ? e.execCode : 'internal-error';
    console.error('[bootstrap] exec 异常', errorText(e));
    const terminalReset = TERMINAL_ERRORS.indexOf(code) >= 0
      ? (code === 'dropped' ? 'cancelled' : code) : '';
    reply = buildExecReply(request, terminalOutcome(code, Date.now()), terminalReset,
      0, evictedSessionIds, request.cwd);
  } finally {
    try {
      process.chdir(previousCwd);
      restored = process.cwd() === previousCwd;
    } catch (e) {
      console.error('[bootstrap] cwd 恢复失败', errorText(e));
    }
  }
  reply.cwdRestored = restored;
  return reply;
}

// exec 入口：运行区就绪 → 参数 fail-closed 校验（无 sessionId 不建 worker/目录）→ 串行面
async function handleExec(request) {
  const prepare = prepareSnapshot();
  if (prepare.prepare === 'failed') {
    return simpleFailureReply(request.requestId, 'prepare-failed', prepare);
  }
  if (prepare.prepare !== 'ready') {
    return simpleFailureReply(request.requestId, 'not-ready', prepare);
  }
  if (typeof request.sessionId !== 'string' || request.sessionId === ''
    || request.sessionId.length > SESSION_ID_MAX_LENGTH) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  if (typeof request.code !== 'string' || request.code === '') {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  if (!Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0
    || request.timeoutMs > EXEC_TIMEOUT_MAX_MS) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  if (typeof request.cwd !== 'string' || request.cwd === '') {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  let cwdStat = null;
  if (path.isAbsolute(request.cwd)) {
    try {
      cwdStat = fs.statSync(request.cwd);
    } catch (e) {
      cwdStat = null;
    }
  }
  if (cwdStat === null || !cwdStat.isDirectory()) {
    return simpleFailureReply(request.requestId, 'bad-cwd');
  }
  if (execRunning) {
    return simpleFailureReply(request.requestId, 'busy');
  }
  execRunning = true;
  try {
    return await runExec(request);
  } finally {
    execRunning = false;
  }
}

// 取消：只终止同会话 worker；在跑的 exec 收到 cancelled 终态回执后释放槽位（install 归属
// 同 sessionId 时一并 terminate，其请求收 cancelled 终态）
async function handleCancel(request) {
  const sessionId = typeof request.sessionId === 'string' ? request.sessionId : '';
  if (sessionId === '' || sessionId.length > SESSION_ID_MAX_LENGTH) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  const stoppedInstall = stopInstallIfOwned(sessionId, 'cancelled');
  const result = await terminateSession(sessionId, 'cancelled');
  return {
    requestId: request.requestId,
    ok: true,
    action: 'cancel',
    sessionId: sessionId,
    stopped: result.stopped || stoppedInstall,
    workerTerminated: result.terminated || stoppedInstall
  };
}

// 释放（删会话/助手）：终止并摘册；drop 后该会话再执行 = 全新会话（created）
async function handleDrop(request) {
  const sessionId = typeof request.sessionId === 'string' ? request.sessionId : '';
  if (sessionId === '' || sessionId.length > SESSION_ID_MAX_LENGTH) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  const stoppedInstall = stopInstallIfOwned(sessionId, 'dropped');
  const result = await terminateSession(sessionId, 'dropped');
  resetReasons.delete(sessionId);
  return {
    requestId: request.requestId,
    ok: true,
    action: 'drop',
    sessionId: sessionId,
    dropped: result.terminated || stoppedInstall,
    stopped: result.stopped || stoppedInstall
  };
}

// ── bin 运行域（门 3 U3：按台账在会话 worker 内跑已装包的命令行入口）──
// 与 exec 同一条串行面（execRunning）与同一套会话 worker：bin 轮与代码轮都是进程级 cwd 与
// 会话上下文的使用者，两套并行会互相污染。排队（lane）与确认档归 ArkTS 侧 NodeScheduler /
// 工具面，本文件只做参数 fail-closed、串行与终态回执。
async function handleRunBin(request) {
  const prepare = prepareSnapshot();
  if (prepare.prepare === 'failed') {
    return simpleFailureReply(request.requestId, 'prepare-failed', prepare);
  }
  if (prepare.prepare !== 'ready') {
    return simpleFailureReply(request.requestId, 'not-ready', prepare);
  }
  if (typeof request.sessionId !== 'string' || request.sessionId === ''
    || request.sessionId.length > SESSION_ID_MAX_LENGTH) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  if (typeof request.bin !== 'string' || request.bin === ''
    || request.bin.length > BIN_NAME_MAX_LENGTH || /\s/.test(request.bin)) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  const args = request.args === undefined ? [] : request.args;
  if (!Array.isArray(args) || args.length > BIN_ARGS_MAX
    || args.some((item) => typeof item !== 'string' || item.length > BIN_ARG_MAX_LENGTH)) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  if (!Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0
    || request.timeoutMs > EXEC_TIMEOUT_MAX_MS) {
    return simpleFailureReply(request.requestId, 'bad-request');
  }
  let cwdStat = null;
  if (typeof request.cwd === 'string' && path.isAbsolute(request.cwd)) {
    try {
      cwdStat = fs.statSync(request.cwd);
    } catch (e) {
      cwdStat = null;
    }
  }
  if (cwdStat === null || !cwdStat.isDirectory()) {
    return simpleFailureReply(request.requestId, 'bad-cwd');
  }
  if (execRunning) {
    return simpleFailureReply(request.requestId, 'busy');
  }
  execRunning = true;
  try {
    return await runExec(Object.assign({}, request, { kind: 'run_bin', args: args }));
  } finally {
    execRunning = false;
  }
}

// ── npm 安装域（门 3 U1：路由薄层，引擎与 worker 编排都在 npm-worker.js；契约见文件头）──

// install 失败回执（参数闸 / 互斥 / 未就绪等不派 worker 的早退路径；终态回执由 npm-worker 组装）
function installFailureReply(requestId, error, detail) {
  const reply = {
    requestId: requestId,
    ok: false,
    error: error,
    exitCode: 1,
    errorCode: '',
    errorDetail: detail !== undefined && detail !== '' ? detail : '',
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
  return reply;
}

// 跑一轮 install：编排（派 worker / 心跳 / 看门狗 / 终止收口）沉在 npm-worker.launchInstall，
// 本文件只持互斥位与回执信封；终态 / 超时 / 取消 / 崩溃四路都只 settle 一次
function runInstallRound(request) {
  const flight = {
    sessionId: typeof request.sessionId === 'string' ? request.sessionId : '',
    terminateWith: null
  };
  installFlight = flight;
  const launcher = npmWorkerMod.launchInstall(request,
    { homeDir: homeDir, installRootDir: installRootDir },
    {
      onSettled: () => {
        if (installFlight === flight) {
          installFlight = null;
        }
      }
    });
  flight.terminateWith = launcher.terminateWith;
  return launcher.promise.then((payload) => Object.assign({ requestId: request.requestId }, payload));
}

// cancel/drop 对 install worker 的入口：命中归属 sessionId 才落刀（幂等）
function stopInstallIfOwned(sessionId, reason) {
  if (installFlight === null || installFlight.sessionId !== sessionId) {
    return false;
  }
  installFlight.terminateWith(reason);
  return true;
}

// 有界等待准备终态（Y4）：轮询到 prepare 不再是 running 就立即返回；到点仍 running 回 running
// （调用方据此回 not-ready）。轮询而非 await preparer.promise，是为了同时兜住「listen 回调尚未
// 跑到 startPrepare」的极小窗口（那时 preparer 还是 null）
function waitForPrepareOutcome(limitMs) {
  const deadline = Date.now() + limitMs;
  return new Promise((resolve) => {
    const tick = () => {
      const snapshot = prepareSnapshot();
      if (snapshot.prepare !== 'running' || Date.now() >= deadline) {
        resolve(snapshot);
        return;
      }
      setTimeout(tick, INSTALL_PREPARE_POLL_MS);
    };
    tick();
  });
}

// install 入口：运行区就绪（未就绪则有界等待）→ 会话标识 → 互斥 → 参数闸（spec 规则单源在
// npm-worker）→ 派 worker
async function handleInstall(request) {
  let prepare = prepareSnapshot();
  if (prepare.prepare !== 'ready') {
    // 冷启首个 install 落在准备期不得直接拒（Y4）：按请求超时与上限的较小值等准备终态
    const waitLimitMs = Number.isInteger(request.timeoutMs) && request.timeoutMs > 0
      ? Math.min(request.timeoutMs, INSTALL_PREPARE_WAIT_MAX_MS) : INSTALL_PREPARE_WAIT_MAX_MS;
    prepare = await waitForPrepareOutcome(waitLimitMs);
  }
  if (prepare.prepare === 'failed') {
    return installFailureReply(request.requestId, 'prepare-failed', prepare.prepareError);
  }
  if (prepare.prepare !== 'ready') {
    return installFailureReply(request.requestId, 'not-ready', '等待 Node 运行区准备就绪超时');
  }
  // sessionId 是 cancel / drop 的归属键（Y5 观察：缺了它这一轮永远停不下来），必填
  if (typeof request.sessionId !== 'string' || request.sessionId === ''
    || request.sessionId.length > SESSION_ID_MAX_LENGTH) {
    return installFailureReply(request.requestId, 'bad-request',
      '安装请求必须带会话标识，否则无法中途停止');
  }
  if (installFlight !== null) {
    return installFailureReply(request.requestId, 'install-running');
  }
  const verdict = npmWorkerMod.validateSpecs(request.specs);
  if (!verdict.ok) {
    return installFailureReply(request.requestId, 'bad-request', verdict.error);
  }
  if (!Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0
    || request.timeoutMs > INSTALL_TIMEOUT_MAX_MS) {
    return installFailureReply(request.requestId, 'bad-request',
      '安装超时必须是正整数毫秒，且不超过 ' + (INSTALL_TIMEOUT_MAX_MS / 60000) + ' 分钟');
  }
  if (installRootDir === '' || !fs.existsSync(path.join(homeDir, 'npm-worker.js'))
    || !fs.existsSync(path.join(homeDir, 'npm', 'lib', 'npm.js'))) {
    return installFailureReply(request.requestId, 'internal-error', 'npm 运行件缺失');
  }
  return runInstallRound(request);
}

// ── 连接处理：一请求一连接；首包鉴权失败即回执并关，不执行任何动作 ──

function authorize(firstLine) {
  let request;
  try {
    request = JSON.parse(firstLine);
  } catch (e) {
    return { ok: false, reply: { requestId: '', ok: false, error: 'bad-request' } };
  }
  if (request === null || typeof request !== 'object') {
    return { ok: false, reply: { requestId: '', ok: false, error: 'bad-request' } };
  }
  const requestId = typeof request.requestId === 'string' ? request.requestId : '';
  // 协议号不符 = bad-request（在鉴权前判——协议层门卫）
  if (request.protocol !== PROTOCOL) {
    return { ok: false, reply: { requestId: requestId, ok: false, error: 'bad-request' } };
  }
  // token：先比 **UTF-8 字节长度**再 timingSafeEqual（字符数等长不算数——64 个多字节字符
  // 字节数不等，直接送进 timingSafeEqual 会抛 ERR_CRYPTO_TIMING_SAFE_EQUAL_LENGTH）
  if (typeof request.token !== 'string') {
    return { ok: false, reply: { requestId: requestId, ok: false, error: 'unauthorized' } };
  }
  const presentedBytes = Buffer.from(request.token, 'utf8');
  if (presentedBytes.length !== tokenBytes.length
    || !crypto.timingSafeEqual(presentedBytes, tokenBytes)) {
    return { ok: false, reply: { requestId: requestId, ok: false, error: 'unauthorized' } };
  }
  if (typeof request.action !== 'string' || typeof request.requestId !== 'string') {
    return { ok: false, reply: { requestId: requestId, ok: false, error: 'bad-request' } };
  }
  return { ok: true, request: request };
}

function onConnection(socket) {
  // 请求字节按片累积；换行切分在字节层做，整行一次 decode（多字节字符跨片不打碎）
  const chunks = [];
  let buffered = 0;
  let done = false;
  let firstPacketTimer = null;
  const clearFirstPacketTimer = () => {
    if (firstPacketTimer !== null) {
      clearTimeout(firstPacketTimer);
      firstPacketTimer = null;
    }
  };
  // 回执并结束连接（end = 写出后 FIN，保证回执先落对端再关——不用 destroy 丢包）
  const replyAndClose = (reply) => {
    if (done) {
      return;
    }
    done = true;
    clearFirstPacketTimer();
    // 回执恒不含 token（unauthorized/bad-request 文案是固定错误码，无回显面）
    socket.end(JSON.stringify(reply) + '\n');
  };
  // 首包前限时：连接建立到「首包完整请求行」到达之间 30 s；首包到达即取消（见文件头
  // 「连接寿命」——exec 的 120~300 s 长执行不被这条计时砍掉；客户端不发首包死亡则由这里收口）
  firstPacketTimer = setTimeout(() => {
    firstPacketTimer = null;
    if (!done) {
      done = true;
      socket.destroy();
    }
  }, FIRST_PACKET_TIMEOUT_MS);
  socket.on('close', () => {
    // 首包后客户端死亡 = 断连收口（清掉可能仍在的首包计时器，不留悬空计时）
    clearFirstPacketTimer();
    done = true;
  });
  socket.on('data', (chunk) => {
    if (done) {
      return;
    }
    chunks.push(chunk);
    buffered += chunk.length;
    // 超限先于换行判定：无换行也拒（防无界累积；口径 = 字节数）
    if (buffered > REQUEST_LIMIT_BYTES) {
      replyAndClose({ requestId: '', ok: false, error: 'bad-request' });
      return;
    }
    // 换行只可能在本次 chunk 内首次出现；本片无换行就不拼接（避免大请求逐片 concat 的 O(n²)）
    if (chunk.indexOf(0x0A) < 0) {
      return;
    }
    const joined = chunks.length === 1 ? chunks[0] : Buffer.concat(chunks, buffered);
    const newline = joined.indexOf(0x0A);
    if (newline < 0) {
      return;
    }
    // 首包（完整请求行）到达 → 取消首包限时；后续寿命交给动作自身的超时与终态回执
    clearFirstPacketTimer();
    const firstLine = joined.subarray(0, newline).toString('utf8');
    const verdict = authorize(firstLine);
    if (!verdict.ok) {
      replyAndClose(verdict.reply);
      return;
    }
    // 动作可以是同步回执（status / 参数错）或 Promise（exec / cancel / drop——执行时长与
    // terminate 等待都由动作自身决定）；两种形态都在回执后关闭连接
    const outcome = handleAuthorizedRequest(verdict.request);
    if (outcome !== null && typeof outcome === 'object' && typeof outcome.then === 'function') {
      outcome.then((reply) => {
        replyAndClose(reply);
      }).catch((e) => {
        console.error('[bootstrap] 动作异常', errorText(e));
        replyAndClose({ requestId: verdict.request.requestId, ok: false, error: 'internal-error' });
      });
      return;
    }
    replyAndClose(outcome);
  });
  socket.on('error', (e) => {
    console.error('[bootstrap] socket error', errorText(e));
  });
}

// ── 启动：listen → listen 回调内原子写 endpoint（bootMs = listen 完成耗时）──

// bootMs 口径修正（任务书 §2 第 3 条）：listen 完成回调内计算（进程起 → listen 就绪），
// 不再在模块载入时预写
let bootMs = 0;

// 控制面启动（全部启动期失败路径都走 failStartup + return：不建 listen、不留计时器；
// 已建 server 的失败路径先 close 再 return，事件循环自然退出而不是 process.exit 硬杀）
function startControlPlane() {
  // 陈旧残留处置（ENOENT 容错）：endpoint / socket / 门 1 陈旧端口文件
  unlinkQuiet(endpointPath);
  unlinkQuiet(socketPath);
  unlinkQuiet(stalePortPath);

  // 通道解析：env（受控测试入口）优先 → placement-spec → tcp；非法值 = 拒启（此时零 handle）
  try {
    channel = resolveChannel(spec);
  } catch (e) {
    failStartup('channel-resolve', process.env.NODE_BRIDGE_CHANNEL || '', e);
    return;
  }
  if (channel === 'uds' && udsPathBytesTooLong(socketPath)) {
    failStartup('socket-path-length', socketPath, { code: 'ENAMETOOLONG' });
    return;
  }

  const server = net.createServer(onConnection);
  server.on('error', (e) => {
    // listen 失败（含 UDS 残留 socket 非常规形态）= 控制面无法就位 → setup-error + 退出码；
    // listen 未成功的 server 无存活句柄，close 幂等（防个别平台留下半开 handle 悬住事件循环）
    failStartup('listen', channel === 'uds' ? socketPath : '127.0.0.1:0', e);
    try {
      server.close();
    } catch (err) {
      console.error('[bootstrap] server close failed', errorText(err));
    }
  });
  if (channel === 'uds') {
    server.listen(socketPath); // pathname 模式（启动前已 unlink 陈旧 socket）
  } else {
    server.listen(0, '127.0.0.1'); // 只绑回环、临时端口
  }

  server.on('listening', () => {
    bootMs = Math.round(Date.now() - performance.timeOrigin);
    const address = server.address();
    const port = address !== null && typeof address === 'object' ? address.port : 0;
    // endpoint 载荷：协议号 + 通道 + 寻址 + 令牌 + 进程身份；token 只经 0600 文件交付宿主
    const endpoint = {
      protocol: PROTOCOL,
      channel: channel,
      pid: process.pid,
      startedAt: Date.now(),
      token: token
    };
    if (channel === 'uds') {
      endpoint.socketPath = socketPath;
    } else {
      endpoint.port = port;
    }
    // 原子写：临时文件 + rename（半写不会以 endpoint 名在场——防假就绪同款教训）
    try {
      const tmpPath = endpointPath + ENDPOINT_TMP_SUFFIX;
      fs.writeFileSync(tmpPath, JSON.stringify(endpoint), { mode: 0o600 });
      fs.renameSync(tmpPath, endpointPath);
    } catch (e) {
      // endpoint 写失败 = 宿主永远读不到就绪态 → setup-error + 退出码，关掉监听后不再排解包
      failStartup('endpoint-write', endpointPath, e);
      try {
        server.close();
      } catch (err) {
        console.error('[bootstrap] server close failed', errorText(err));
      }
      return;
    }
    // hilog 里程碑：只打通道与端口，不打 token
    console.log('[bootstrap] listening channel=' + channel + ' port=' + port
      + ' bootMs=' + bootMs + ' prepare=' + prepareSnapshot().prepare);
    // 先 listen 再解包（§3.1）：解包在事件循环里分片让出，期间 status 仍可应答
    startPrepare();
  });
}

// 启动唯一一次准备（解包 + 全验 + .ready + 旧版本清扫）；失败状态由 runtime-setup 收口，
// 本进程不重试（准备失败后用户侧提示重启应用）
function startPrepare() {
  try {
    preparer = setup.beginPrepare(homeDir);
  } catch (e) {
    const failure = 'prepare 启动异常，' + errorText(e);
    preparer = {
      snapshot: () => ({ prepare: 'failed', prepareError: failure, npmVersion: '', prepareStats: null }),
      promise: Promise.resolve()
    };
    console.error('[bootstrap] ' + failure);
    return;
  }
  preparer.promise.then(() => {
    const snap = preparer.snapshot();
    const stats = snap.prepareStats;
    console.log('[bootstrap] prepare ' + snap.prepare
      + ' elapsedMs=' + (stats !== null ? stats.elapsedMs : '-')
      + (snap.npmVersion !== '' ? ' npm=' + snap.npmVersion : '')
      + (snap.prepareError !== '' ? ' error=' + snap.prepareError : ''));
  }).catch((e) => {
    console.error('[bootstrap] prepare 异常', errorText(e));
  });
}

// HOME 未设 = 无处写 setup-error、无处落 endpoint：置退出码后不建任何 handle，事件循环空转退出
// （宿主见 node::Start 返回，dlerror/hilog 里有本行诊断；禁 process.exit）
if (homeDir === '') {
  console.error('[bootstrap] HOME 未设置，无法启动控制面');
  process.exitCode = 1;
} else {
  startControlPlane();
}

process.on('uncaughtException', (e) => {
  console.error('[bootstrap] uncaughtException', errorText(e));
});
process.on('unhandledRejection', (e) => {
  console.error('[bootstrap] unhandledRejection', errorText(e));
});
