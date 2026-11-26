// Node 运行时装配域（2026-11-23 鸿蒙 Node 运行时门 2，任务书-鸿蒙Node运行时门2-20261123
// §3.1「运行区与单飞准备」/§3.5「npm 文件集落位判据」）：版本化运行区落位 + rawfile 八件
// 字节拷贝与 sha256 对账 + Node 启动编排（冷启残留处置 / 运行中端点丢失拒二调）。
// · 布局：filesDir/node-24.22.3-g1/ = HOME（native setenv 与 bootstrap 路径共用该目录）；
//   八件 = bootstrap.js / session-worker.js / runtime-setup.js / npm-fileset.tar.gz /
//   npm-worker.js（门 3 U1 加第五件：npm 安装域 worker）+ npm-install-core.js / npm-scan.js
//   （门 3 U3 S1 拆出：安装执行核心与装后扫描回滚）+ bin-runner.js（门 3 U3 S4：按 bin 台账在
//   会话 worker 内跑已装包命令行入口）；均不在冻结 tar 内、非构建产物——manifest.json 与
//   golden 零动。字节数与 sha256 是本文件常量，设备侧只认常量不读 manifest——一致性由门禁侧
//   assert-node-runtime.mjs 钉守，§3.1）。
// · npm 解包与 .ready 归 Node 侧（runtime-setup.js，S2）：本文件只把 npm 条目计数与版本串
//   经 placement-spec.json 注入（files 1926 / dirs 458，§3.5 判据 1），Node 侧解包全验后写
//   `.ready`（内容 = 版本串:tar sha256），二次准备命中 .ready 只验关键件与 npm 版本。
// · 落位说明文件 placement-spec.json（HOME 下一级，Node 侧 runtime-setup 自检的期望值
//   来源）：通道 + 版本串 + npm 条目计数 + 七件名与字节/sha256——跨语言单源都在本文件常量。
// · 启动契约（§3.2 残留处置）：冷启（nodeStarted===false）先 unlink 陈旧 endpoint / socket
//   / 门 1 陈旧 bridge.port / 上次失败的 setup-error 再 start；nodeStarted===true 而 endpoint
//   不可读 = 只报「运行中端点丢失，请重启应用」，禁二调 node::Start（单进程一次）。native
//   nodeStarted 在 node::Start 调用前置位——冷启分支与置位间无「已 listen 未置位」窗口，
//   unlink 不及活端点。start 回 already-started 时先读 status：nodeStarted 为真才等 endpoint，
//   否则（Start 已返回 / 六步早期失败，dlerror 有值）直接报原文，不进 60 s 端点空等。
// · 落位快路径（P2-8）：`.ready` 在场且各件 stat 尺寸对上 → 只读校验、不重拷；`.ready` 缺失
//   但 tar 件尺寸已对上（可能正解包）→ 跳过重拷只等状态；运行中也整段跳过——解包读写与覆盖
//   写不并发，宁慢不冲突。内容级 sha256 对账仍归 Node 侧 runtime-setup。
// · P0-1 防线：各件体积逐件比对常量 + 落盘 stat 一致 + 落盘 sha256（fileIo hash，小写比对）
//   逐件对账；任一不满足即抛中文错误不降级宣称就绪。单飞照 PyRuntime.ets:274-289 形态。
import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import nodeEngine from 'libnodeengine.so';
import { NODE_BRIDGE_CHANNEL, NodeBridgeEndpoint, readNodeBridgeEndpoint } from './NodeBridge';

// 运行区版本串（与 scripts/node-runtime/manifest.json runtime.runtimeVersion 一致——一致性
// 由门禁钉守；目录名随版本换新，旧版本清扫在 Node 侧准备就绪后按 runtime-setup 的
// sweepOldVersions 执行 = filesDir 下只匹配 node-X.Y.Z-gN 且非当前版本的目录，node-data 不匹配）
export const NODE_RUNTIME_VERSION: string = '24.22.3-g1';
// 运行区目录名（filesDir 下一级 = HOME；native 与 bootstrap 都指向该目录）
export const NODE_HOME_DIR_NAME: string = 'node-' + NODE_RUNTIME_VERSION;

// rawfile 内 Node 资产目录前缀
const NODE_RAW_DIR: string = 'node/';
// 落位说明文件名（本件写入、runtime-setup.js 读取）
const NODE_PLACEMENT_SPEC_NAME: string = 'placement-spec.json';
// 就绪标记文件名（Node 侧 runtime-setup 全验通过后原子写；与本件快路径判定同名同源）
const NODE_READY_NAME: string = '.ready';
// npm 文件集件名（快路径判定「是否可能正在解包」的靶件）
const NODE_TAR_FILE_NAME: string = 'npm-fileset.tar.gz';
// endpoint 与陈旧残留文件名（与 bootstrap.js 常量逐字同源）
const NODE_ENDPOINT_NAME: string = 'bridge.endpoint';
const NODE_SOCKET_NAME: string = 'bridge.sock';
const NODE_STALE_PORT_NAME: string = 'bridge.port'; // 门 1 陈旧端口文件（防假就绪一并清）
const NODE_SETUP_ERROR_NAME: string = 'setup-error.json';
// 端点等待：轮询间隔与兜底上限（60 s = 准备等待初值，真机读数后按实测 2 倍内调整——§3.1）
const NODE_PREPARE_POLL_MS: number = 200;
const NODE_PREPARE_WAIT_TIMEOUT_MS: number = 60000;

// rawfile 落位件规格（字节数与 sha256 常量；sha 计算面 = fileIo hash 落盘后小写比对）
interface NodeRawFileSpec {
  name: string;
  bytes: number;
  sha256: string;
}

// npm 文件集条目计数（§3.5 判据 1；冻结 tar 实查 = 1926 文件 + 458 目录，Node 侧解包时
// 逐类守卫 + 终态等值，防解包漏件/多件静默放过）
const NODE_NPM_FILE_COUNT: number = 1926;
const NODE_NPM_DIR_COUNT: number = 458;

const NODE_RAW_FILES: NodeRawFileSpec[] = [
  { name: 'bootstrap.js', bytes: 54231, sha256: '621ba5d3c88c200f21bd15fc3d4f0761fb86c16478c21588e0a5dfc5bd76c3d3' },
  { name: 'session-worker.js', bytes: 39567, sha256: 'ea1ac882a795b4a1932c1a9f054c4004704ad1c22857a7a1e05e294292eba7b9' },
  { name: 'runtime-setup.js', bytes: 30624, sha256: 'd19dc8bb1f790eed67a562b88394ab875cf19a65b29d6a9bc63094782e120f93' },
  { name: 'npm-fileset.tar.gz', bytes: 3065175, sha256: 'ed7b6e38de361852ff8b373c480b293dae6d890c7d3ec6fad898cdca9b094cc2' },
  { name: 'npm-worker.js', bytes: 19249, sha256: '83a1acb5bc29d4c8bb850f8c8e4cac6eb5cfd020d2d3b41966265af3d286df2c' },
  { name: 'npm-install-core.js', bytes: 23153, sha256: 'ee25ecc2c1d3c957f42d8ef02c77f3e08caed9ea116cc720b52f68766373913d' },
  { name: 'npm-scan.js', bytes: 21199, sha256: 'b244c066a177399efa788f67d241ebb3f74b847cb1f7fc4898b4f22349da279c' },
  { name: 'bin-runner.js', bytes: 13804, sha256: '988f8c548d301bf28be9873c743b788cc260373f1c69eff1b739423927aa7239' }
];

// placement-spec.json 形态（bootstrap 经 runtime-setup 读取；files 逐件 statSync 对账，
// npmEntries 与 runtimeVersion 供 .ready 内容与解包计数守卫）
interface NodeNpmEntries {
  files: number;
  dirs: number;
}

interface NodePlacementSpec {
  channel: string;
  runtimeVersion: string;
  npmEntries: NodeNpmEntries;
  files: NodeRawFileSpec[];
}

// 引擎状态（契约同构：cpp/types/libnodeengine/index.d.ts 的 NodeEngineStatus——改名/加字段
// 两处同步；本单元 threadAlive 语义修正为真实存活判据，字段集不变）
interface NodeEngineStatus {
  threadAlive: boolean;
  shimInstalled: boolean;
  crashHandlerInstalled: boolean;
  envSet: boolean;
  dlopened: boolean;
  dlerror: string;
  startSymbol: boolean;
  nodeStarted: boolean;
  shimHits: number;
}

// 启动结果（homeDir + 已解析 endpoint——调用方直接拿去 bridgeRequest，不再读文件）
export interface NodeRuntimeStartOutcome {
  homeDir: string;
  endpoint: NodeBridgeEndpoint;
}

// 最小错误形态（只取 code 判 EEXIST——照 PyRuntime 同款姿势）
interface BusinessErrorLike {
  code: number;
  message: string;
}

// 建目录（目标已存在静默——mkdirSync(path, true) 仍抛 EEXIST 13900015，SkillPack 先例）
function mkdirIfExistsTolerant(path: string): void {
  try {
    fs.mkdirSync(path, true);
  } catch (e) {
    const err = e as BusinessErrorLike;
    if (err.code !== 13900015) {
      throw e as Error;
    }
  }
}

// 整件字节落盘（READ_WRITE|CREATE|TRUNC + writeSync；先例 = PyRuntime.writeAllBytes）
function writeAllBytes(path: string, bytes: Uint8Array): void {
  const file: fs.File = fs.openSync(path,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength });
  } finally {
    fs.closeSync(file);
  }
}

// 小文本落盘（placement-spec 用；TextEncoder 编码——内容纯 ASCII JSON，编码面无歧义）
function writeAllText(path: string, text: string): void {
  writeAllBytes(path, util.TextEncoder.create('utf-8').encodeInto(text));
}

// ENOENT 容错删除（残留处置：文件不存在 = 目标态）
function unlinkQuiet(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (e) {
    // 文件不存在 = 目标态，不阻断启动
  }
}

// 件是否存在（落位快路径的只读探查——命中与否都不写盘）
function fileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch (e) {
    return false;
  }
}

// 各件 stat 尺寸是否全部与常量一致（不读全件字节：快路径的轻量证据，
// 内容级 sha256 对账仍归 Node 侧 runtime-setup，见文件头 P0-1 防线）
function rawFileSizesMatch(homeDir: string): boolean {
  for (let i: number = 0; i < NODE_RAW_FILES.length; i++) {
    const item: NodeRawFileSpec = NODE_RAW_FILES[i];
    try {
      if (fs.statSync(homeDir + '/' + item.name).size !== item.bytes) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  return true;
}

// 延时（端点轮询节奏）
function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

// 应用上下文捕获（照 PyRuntime.pyStoreCtx 先例：EntryAbility onCreate 调一次——U4 工具链
// 起接；探针页显式传 UI 上下文，同源同值）
let nodeStoreCtx: common.Context | undefined = undefined;

export function initNodeRuntimeStore(ctx: common.Context): void {
  nodeStoreCtx = ctx;
}

// 运行区目录绝对路径（状态读取用；ctx 未注入回空串——调用方判空展示未就绪）
export function nodeRuntimeHomePath(): string {
  if (nodeStoreCtx === undefined) {
    return '';
  }
  return nodeStoreCtx.filesDir + '/' + NODE_HOME_DIR_NAME;
}

// 引擎状态直读（解析失败回 null——调用方按「未启动 / 未知」处理，不造数）
function readEngineStatus(): NodeEngineStatus | null {
  try {
    return JSON.parse(nodeEngine.status()) as NodeEngineStatus;
  } catch (e) {
    return null;
  }
}

// 运行时是否已在本进程内启动（页面重进恢复判断；status 解析失败按未启动处理）
export function isNodeProcessStarted(): boolean {
  const st: NodeEngineStatus | null = readEngineStatus();
  return st !== null && st.nodeStarted;
}

// 运行区是否已释放（只读：`.ready` 在场且八件 stat 尺寸与常量一致——与快路径判据 ② 同源）。
// 管理页进页区分「已释放未启动」与「未释放」用：不启动引擎、不写盘、不重拷。刻意不复用
// shouldSkipPlacement——那件还含「运行中」与「可能正在解包」两条，语义是「跳过重拷」而非
// 「已释放」；运行中并非已释放，拿来当判据会让页面误报。ctx 未注入回 false（调用方按未释放展示）
export function nodeRuntimePlaced(): boolean {
  const home: string = nodeRuntimeHomePath();
  if (home === '') {
    return false;
  }
  return fileExists(home + '/' + NODE_READY_NAME) && rawFileSizesMatch(home);
}

// 当前进程 endpoint 只读探查（不启动、不等待、不删残留——页面重进恢复判断用；上下文未
// 注入或 endpoint 不可读回 null。「运行中端点丢失」的报错语义归 startNodeRuntime）
export function peekNodeEndpoint(ctx?: common.Context): NodeBridgeEndpoint | null {
  const effCtx: common.Context | undefined = ctx !== undefined ? ctx : nodeStoreCtx;
  if (effCtx === undefined) {
    return null;
  }
  return readNodeBridgeEndpoint(effCtx.filesDir + '/' + NODE_HOME_DIR_NAME + '/' + NODE_ENDPOINT_NAME);
}

// 落位说明写入（通道单源 = NodeBridge.NODE_BRIDGE_CHANNEL，经此传导 bootstrap 监听通道；
// 版本串与 npm 条目计数同源传导，Node 侧 .ready 内容与解包计数守卫都只认这里）
function writePlacementSpec(homeDir: string): void {
  const spec: NodePlacementSpec = {
    channel: NODE_BRIDGE_CHANNEL,
    runtimeVersion: NODE_RUNTIME_VERSION,
    npmEntries: { files: NODE_NPM_FILE_COUNT, dirs: NODE_NPM_DIR_COUNT },
    files: NODE_RAW_FILES
  };
  writeAllText(homeDir + '/' + NODE_PLACEMENT_SPEC_NAME, JSON.stringify(spec));
}

// 单件落位：rawfile 字节读出 → 体积比对常量 → 落盘 → stat 一致 → sha256 对账
async function placeRawFile(ctx: common.Context, homeDir: string, item: NodeRawFileSpec): Promise<void> {
  let bytes: Uint8Array;
  try {
    bytes = await ctx.resourceManager.getRawFileContent(NODE_RAW_DIR + item.name);
  } catch (e) {
    throw new Error('读取内置 ' + item.name + ' 失败，' + (e as Error).message);
  }
  if (bytes.byteLength !== item.bytes) {
    throw new Error('内置 ' + item.name + ' 体积异常（' + bytes.byteLength + ' B），已停止落位');
  }
  const target: string = homeDir + '/' + item.name;
  try {
    writeAllBytes(target, bytes);
  } catch (e) {
    throw new Error('写入 ' + item.name + ' 失败，' + (e as Error).message);
  }
  const written: number = fs.statSync(target).size;
  if (written !== item.bytes) {
    throw new Error(item.name + ' 落盘不完整（' + written + '/' + item.bytes + ' B）');
  }
  let diskSha: string = '';
  try {
    diskSha = (await hash.hash(target, 'sha256')).toLowerCase();
  } catch (e) {
    throw new Error(item.name + ' 落盘 sha256 计算失败，' + (e as Error).message);
  }
  if (diskSha !== item.sha256) {
    throw new Error(item.name + ' 落盘校验不符，已停止落位');
  }
}

// 按名取落位件规格（快路径按件名定位，禁按下标硬取——常量表顺序可调）
function rawFileSpecByName(name: string): NodeRawFileSpec | null {
  for (let i: number = 0; i < NODE_RAW_FILES.length; i++) {
    if (NODE_RAW_FILES[i].name === name) {
      return NODE_RAW_FILES[i];
    }
  }
  return null;
}

// 落位快路径判定（P2-8；返回 true = 跳过重拷）：三条只读判据，任一命中即不覆盖既有落位
// ①运行时已在本进程启动 → Node 侧可能正解包/读 tar，覆盖写会与解包读写冲突；
// ②`.ready` 在场且各件 stat 尺寸与常量一致 → 信任既有落位（内容级 sha256 对账归 Node 侧）；
// ③`.ready` 不在场但 tar 件尺寸已与常量一致 → 可能正处在解包中，宁慢不冲突：只等状态；
// 都不确定（缺件 / 尺寸不符）→ 走原全量落位。
function shouldSkipPlacement(homeDir: string): boolean {
  if (isNodeProcessStarted()) {
    return true;
  }
  if (fileExists(homeDir + '/' + NODE_READY_NAME)) {
    return rawFileSizesMatch(homeDir);
  }
  const tarItem: NodeRawFileSpec | null = rawFileSpecByName(NODE_TAR_FILE_NAME);
  if (tarItem === null) {
    return false;
  }
  try {
    return fs.statSync(homeDir + '/' + tarItem.name).size === tarItem.bytes;
  } catch (e) {
    return false;
  }
}

// 落位本体（快路径未命中时的全量落位：逐件覆盖拷贝 + stat + sha256 对账，兜底残缺拷贝）。
// 幂等：内容不可变，同版本重复落位结果一致；npm 解包与 .ready 归 Node 侧 runtime-setup
async function placeNodeRuntime(ctx: common.Context): Promise<string> {
  const homeDir: string = ctx.filesDir + '/' + NODE_HOME_DIR_NAME;
  mkdirIfExistsTolerant(homeDir);
  // 快路径：已就绪 / 可能正在解包 / 运行中 → 不重拷 3 MB、不重算 sha
  if (shouldSkipPlacement(homeDir)) {
    // spec 只在缺失且未运行中时补写（运行中补写会与 bootstrap 的 spec 读取交错）
    if (!fileExists(homeDir + '/' + NODE_PLACEMENT_SPEC_NAME) && !isNodeProcessStarted()) {
      writePlacementSpec(homeDir);
    }
    return homeDir;
  }
  for (let i: number = 0; i < NODE_RAW_FILES.length; i++) {
    await placeRawFile(ctx, homeDir, NODE_RAW_FILES[i]);
  }
  writePlacementSpec(homeDir);
  return homeDir;
}

// 在飞落位单飞缓存（照 PyRuntime.ensurePyRuntime 形态：并发调用共享同一 promise，防双写
// 交错；发起者 settle 后清缓存——失败后下次调用重新落位重试）
let ensurePlacementPending: Promise<string> | null = null;

// 首用落位入口（单飞外壳）：返回 homeDir。失败一律抛中文错误（调用方展示），禁静默降级
export async function ensureNodeRuntimePlacement(ctx?: common.Context): Promise<string> {
  if (ensurePlacementPending !== null) {
    return ensurePlacementPending;
  }
  const effCtx: common.Context | undefined = ctx !== undefined ? ctx : nodeStoreCtx;
  if (effCtx === undefined) {
    throw new Error('应用上下文未注入，无法准备 Node 运行区');
  }
  const task: Promise<string> = placeNodeRuntime(effCtx);
  ensurePlacementPending = task;
  try {
    return await task;
  } finally {
    ensurePlacementPending = null;
  }
}

// 端点等待（bootstrap listen 后原子写 endpoint；轮询读 + 解析成功即就绪。超时读
// setup-error.json 原文透出——禁只报「等端点超时」，§3.1）
async function waitForEndpoint(homeDir: string, deadlineMs: number): Promise<NodeBridgeEndpoint> {
  const endpointPath: string = homeDir + '/' + NODE_ENDPOINT_NAME;
  while (Date.now() <= deadlineMs) {
    const endpoint: NodeBridgeEndpoint | null = readNodeBridgeEndpoint(endpointPath);
    if (endpoint !== null) {
      return endpoint;
    }
    await delay(NODE_PREPARE_POLL_MS);
  }
  let setupDetail: string = '';
  try {
    setupDetail = fs.readTextSync(homeDir + '/' + NODE_SETUP_ERROR_NAME).trim();
  } catch (e) {
    // 无 setup-error = 单纯超时（bootstrap 未写失败档）
  }
  if (setupDetail !== '') {
    throw new Error('等待 Node 端点超时，setup-error ' + setupDetail);
  }
  throw new Error('等待 Node 端点超时，请查看 hilog 里程碑');
}

// 启动本体（冷启 / 运行中恢复两分支；单飞外壳 startNodeRuntime 串并发调用）
async function startRuntimeInner(ctx?: common.Context): Promise<NodeRuntimeStartOutcome> {
  const effCtx: common.Context | undefined = ctx !== undefined ? ctx : nodeStoreCtx;
  if (effCtx === undefined) {
    throw new Error('应用上下文未注入，无法启动 Node 运行时');
  }
  const homeDir: string = effCtx.filesDir + '/' + NODE_HOME_DIR_NAME;
  if (isNodeProcessStarted()) {
    // 运行中：只认当前 endpoint，不删、不重启（§3.2）；不可读 = 拒二调 node::Start
    const endpoint: NodeBridgeEndpoint | null =
      readNodeBridgeEndpoint(homeDir + '/' + NODE_ENDPOINT_NAME);
    if (endpoint !== null) {
      return { homeDir: homeDir, endpoint: endpoint };
    }
    throw new Error('运行中端点丢失，请重启应用');
  }
  // 冷启动：先清上个进程残留（endpoint / socket / 门 1 陈旧端口文件 / 上次失败的 setup-error
  // ——防假就绪同款教训；setup-error 不清会把上一轮失败原文当本次原因透出）
  unlinkQuiet(homeDir + '/' + NODE_ENDPOINT_NAME);
  unlinkQuiet(homeDir + '/' + NODE_SOCKET_NAME);
  unlinkQuiet(homeDir + '/' + NODE_STALE_PORT_NAME);
  unlinkQuiet(homeDir + '/' + NODE_SETUP_ERROR_NAME);
  const result: string = nodeEngine.start(homeDir);
  if (result !== 'started' && result !== 'already-started') {
    throw new Error('启动被拒绝，' + result);
  }
  if (result === 'already-started') {
    // 本进程内已调过一次 Start，两种形态必须分开：
    // ①nodeStarted=true（极端并发下的正常就绪）→ 继续等 endpoint；
    // ②node::Start 已返回或六步早期失败（threadAlive=false / nodeStarted=false，dlerror 有值）
    //   → 没有任何 endpoint 会到来，直接报错原文（含 dlerror），不进 60 s 端点等待（P2-5）
    const st: NodeEngineStatus | null = readEngineStatus();
    if (st === null || !st.nodeStarted) {
      const detail: string = st !== null && st.dlerror !== '' ? st.dlerror : '无 dlerror 详情';
      const threadText: string = st !== null && st.threadAlive ? '线程在' : '线程已退出';
      throw new Error('Node 启动未完成，' + threadText + '，错误 ' + detail);
    }
  }
  const endpoint: NodeBridgeEndpoint =
    await waitForEndpoint(homeDir, Date.now() + NODE_PREPARE_WAIT_TIMEOUT_MS);
  return { homeDir: homeDir, endpoint: endpoint };
}

// 在飞启动单飞缓存（并发 start 共享同一 promise；settle 后清）
let startPending: Promise<NodeRuntimeStartOutcome> | null = null;

// 启动编排入口（幂等：运行中直接读回当前 endpoint；冷启走残留处置 + start + 端点等待）
export async function startNodeRuntime(ctx?: common.Context): Promise<NodeRuntimeStartOutcome> {
  if (startPending !== null) {
    return startPending;
  }
  const task: Promise<NodeRuntimeStartOutcome> = startRuntimeInner(ctx);
  startPending = task;
  try {
    return await task;
  } finally {
    startPending = null;
  }
}
