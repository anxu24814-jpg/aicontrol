// Node 桥接客户端（2026-11-23 鸿蒙 Node 运行时门 2 U1 笔，任务书-鸿蒙Node运行时门2-20261123
// §3.2「IPC 与鉴权」）：endpoint 文件读取解析 + token 握手 + 一请求一连接的单次请求封装。
// · 通道单常量：`NODE_BRIDGE_CHANNEL` 交付态 = 'tcp'（门 1 已证传输）。UDS 路径同笔在
//   （`constructLocalSocketInstance` pathname 模式，路径 <HOME>/bridge.sock，UTF-8 字节数
//   ≤107 双端校验，客户端不 bind 服务端路径——SDK `@ohos.net.socket.d.ts`
//   constructLocalSocketInstance :133 / LocalSocket.connect :1190），默认不走；真机 UDS
//   回执通过后才翻 'uds' 重构建，**不做运行时静默切换**（§0 代决表）。通道经
//   NodeRuntime 写入 placement-spec 传给 bootstrap（跨语言单源）。
// · 协议：一请求一连接，一行 JSON 请求一行 JSON 回执；首包即含 {protocol,token,action,
//   requestId}；连接超时 6 s；响应超时兜底（S3 执行按超时参数传入）与断连清理；回执与
//   日志不含 token。
// · 回执收口三条（P2-3/P2-6）：①回执按 **字节层** 累积、换行切分在字节层完成、整行一次
//   decode——逐片解码再拼接会把跨片的多字节字符打成 U+FFFD；②回执 requestId 与本请求不符
//   = 迟到回执，丢弃后继续等本条；③监听连接 close：断连即失败，不等响应超时。
// · 消费面 = NodeRuntimeProbePage（U1）与 NodeScheduler（U3b：exec/cancel/drop/status；门 3
//   U1 加 install——响应兜底 60 s 对 install 必须经 responseTimeoutMs 显式覆写为独立超时；门 3
//   U3 加 run_bin——载荷 {sessionId,bin,args,cwd,timeoutMs}，回执同 exec 面带 exitCode）。
//   执行载荷 `{sessionId,cwd,timeoutMs}` 与执行回执字段由 U3b 按任务书 §3.2 在本件扩展；
//   本件只做传输与形态，不判会话、不排队、不释放槽位（那些归 NodeScheduler）。
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

// 通道类型（tcp = 回环 TCP + 令牌；uds = AF_UNIX pathname + 令牌）
export type NodeBridgeChannel = 'tcp' | 'uds';

// 通道单常量（交付态 = tcp；翻 'uds' 须真机回执，改后本常量单源传导 placement-spec 与本件
// 全部通道判定——禁在别处另写通道字面量）
export const NODE_BRIDGE_CHANNEL: NodeBridgeChannel = 'tcp';

// 协议号（与 bootstrap.js PROTOCOL 逐字同源；endpoint 解析与请求首包共用）
const NODE_BRIDGE_PROTOCOL: number = 1;

// 连接超时（任务书 §3.2：连接超时 6 s）
const NODE_BRIDGE_CONNECT_TIMEOUT_MS: number = 6000;
// 响应兜底超时（即时动作默认值；exec 由 NodeScheduler 传入「执行超时 + 宽限」，见其文件头）
const NODE_BRIDGE_RESPONSE_TIMEOUT_MS: number = 60000;
// UDS 路径上限（sockaddr_un.sun_path 含 NUL 共 108；双端各自校验 UTF-8 字节数 ≤107）
const NODE_UDS_MAX_PATH_BYTES: number = 107;

// endpoint 文件形态（bootstrap.js listen 后原子写；token 只经本文件交付，禁入日志/回执）
export interface NodeBridgeEndpoint {
  protocol: number;
  channel: string;
  port?: number;
  socketPath?: string;
  token: string;
  pid: number;
  startedAt: number;
}

// 回执形态（status 动作扁平展开；exec 执行回执与 cancel/drop 回执字段见下方分组）
export interface NodeBridgeReply {
  requestId: string;
  ok: boolean;
  error?: string;
  // 通用执行面（exec 成功与失败回执都带；终态回执不带输出与 savedNames，见任务书 §3.2）
  stdout?: string;
  stderr?: string;
  stdoutTruncated?: boolean;
  stderrTruncated?: boolean;
  elapsedMs?: number;
  workerStartMs?: number;
  sessionReset?: string;
  evictedSessionIds?: string[];
  savedNames?: string[];
  events?: string[];
  eventsKept?: number;
  eventsTotal?: number;
  eventsNote?: string;
  backgroundOps?: number;
  cwd?: string;
  cwdRestored?: boolean;
  // status 面
  channel?: string;
  nodeVersion?: string;
  platform?: string;
  npmVersion?: string;
  prepare?: string;
  prepareError?: string;
  prepareStats?: NodeBridgePrepareStats;
  workers?: number;
  bootMs?: number;
  memory?: NodeBridgeMemory;
  // cancel / drop 面（恒直达控制面，不经执行 lane）
  action?: string;
  sessionId?: string;
  stopped?: boolean;
  workerTerminated?: boolean;
  dropped?: boolean;
  // install 面（门 3 U1：终态回执一请求一响应，不做流式；心跳只作超时回执的阶段标注）
  exitCode?: number;
  errorCode?: string;
  errorDetail?: string;
  stage?: string;
  logTail?: string[];
  packages?: string[];
  packagesTotal?: number;
  packagesTruncated?: boolean;
  wasmNote?: string;
  rolledBack?: boolean;
  violations?: string[];
  // 清理附注单字段（回滚修正与失败/终止路径清扫）：安装前后清理计数、回滚未成功项、
  // 终止时日志尾部不可得。空串 = 无附注（与 npm-worker.js cleanupNote 同名同源）
  cleanupNote?: string;
  // bin 运行面（门 3 U3：run_bin 轮回执；exec 轮不出现这几个字段）
  bin?: string;
  durationMs?: number;
  binPackage?: string;
  binReplaced?: boolean;
}

// 准备读数（status.prepareStats：runtime-setup 解包 wall/RSS/磁盘/件数；快路径命中时
// diskBytes/files/dirs 为 0 且 fastPath=true）
export interface NodeBridgePrepareStats {
  elapsedMs: number;
  rssBeforeBytes: number;
  rssAfterBytes: number;
  rssDeltaBytes: number;
  diskBytes: number;
  files: number;
  dirs: number;
  fastPath: boolean;
}

// 进程内存读数（bootstrap status memory 字段，字节）
export interface NodeBridgeMemory {
  rss: number;
  heapTotal: number;
  heapUsed: number;
  external: number;
  arrayBuffers: number;
}

// 请求附加字段（exec 必带 sessionId/code/cwd/timeoutMs 四件，见任务书 §3.2；cancel/drop 只带
// sessionId；status 不带；install 必带 specs/timeoutMs/sessionId——sessionId 是 cancel/drop 的
// 归属键，缺了它这一轮永远停不下来，bootstrap 侧按 bad-request 拒收；run_bin 必带
// sessionId/bin/cwd/timeoutMs，args 可选）
export interface NodeBridgeRequestFields {
  code?: string;
  sessionId?: string;
  cwd?: string;
  timeoutMs?: number;
  specs?: string[];
  bin?: string;
  args?: string[];
}

// 请求首包形态（本文件动作面 = exec/status/cancel/drop/install/run_bin 六值）
export interface NodeBridgeRequestLine {
  protocol: number;
  token: string;
  action: string;
  requestId: string;
  code?: string;
  sessionId?: string;
  cwd?: string;
  timeoutMs?: number;
  specs?: string[];
  bin?: string;
  args?: string[];
}

// endpoint 文件读取与解析（缺失 / 不可读 / 非法 JSON / 协议号不符 / token 空 → null——
// 调用方结合 nodeStarted 区分「未就绪」与「运行中端点丢失」两态，不在本件造差异文案）
export function readNodeBridgeEndpoint(endpointPath: string): NodeBridgeEndpoint | null {
  let text: string;
  try {
    text = fs.readTextSync(endpointPath);
  } catch (e) {
    return null;
  }
  let parsed: NodeBridgeEndpoint;
  try {
    parsed = JSON.parse(text) as NodeBridgeEndpoint;
  } catch (e) {
    return null;
  }
  if (parsed.protocol !== NODE_BRIDGE_PROTOCOL || typeof parsed.token !== 'string'
    || parsed.token === '' || typeof parsed.channel !== 'string') {
    return null;
  }
  return parsed;
}

// 请求 id 生成（时间 + 序号，进程内唯一即可——回执按 id 回显，迟到回执丢弃归 S3 调度层）
let requestIdSeq: number = 0;

export function nextBridgeRequestId(): string {
  requestIdSeq++;
  return 'r' + Date.now().toString(36) + '-' + requestIdSeq.toString(36);
}

// 回执行解析（一行 JSON → NodeBridgeReply；解析失败抛错由调用方转 reject）
function parseReplyLine(line: string): NodeBridgeReply {
  const reply: NodeBridgeReply = JSON.parse(line) as NodeBridgeReply;
  if (typeof reply.requestId !== 'string' || typeof reply.ok !== 'boolean') {
    throw new Error('回执缺 requestId 或 ok 字段');
  }
  return reply;
}

// 换行字节（0x0A）定位（字节层切行；多字节字符按字节累积，跨片也不会被拆坏）
function indexOfNewlineByte(bytes: Uint8Array, from: number): number {
  for (let i: number = from; i < bytes.length; i++) {
    if (bytes[i] === 0x0A) {
      return i;
    }
  }
  return -1;
}

// 片段拼接（只在「换行出现的那一片」调用一次——避免逐片拼接的平方级拷贝）
function concatByteChunks(chunks: Uint8Array[], total: number): Uint8Array {
  const joined: Uint8Array = new Uint8Array(total);
  let offset: number = 0;
  for (let i: number = 0; i < chunks.length; i++) {
    joined.set(chunks[i], offset);
    offset += chunks[i].length;
  }
  return joined;
}

// 回执行缓冲（TCP 与 UDS 两路共用）：累积字节 → 按 0x0A 切行 → 整行一次 decode。
// 禁逐片 decode 再拼字符串：跨片多字节字符会变 U+FFFD（中文回执文案会损坏）。
class NodeBridgeLineBuffer {
  private pending: Uint8Array[] = [];
  private pendingBytes: number = 0;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  // 喂入一片字节，返回本次凑齐的完整行（返回值不含换行字节）
  feed(chunk: Uint8Array): string[] {
    const lines: string[] = [];
    this.pending.push(chunk);
    this.pendingBytes += chunk.length;
    // 换行只可能在本片内首次出现；本片无换行只入队不拼接
    if (indexOfNewlineByte(chunk, 0) < 0) {
      return lines;
    }
    const joined: Uint8Array = concatByteChunks(this.pending, this.pendingBytes);
    this.pending = [];
    this.pendingBytes = 0;
    let start: number = 0;
    while (true) {
      const newline: number = indexOfNewlineByte(joined, start);
      if (newline < 0) {
        break;
      }
      lines.push(this.decoder.decodeToString(joined.subarray(start, newline)));
      start = newline + 1;
    }
    if (start < joined.length) {
      const rest: Uint8Array = joined.subarray(start);
      this.pending.push(rest);
      this.pendingBytes = rest.length;
    }
    return lines;
  }
}

// 回执行消费（两路共用）：requestId 不符 = 迟到回执，丢弃后继续等本次回执；
// 解析失败 = 协议违规，按失败 settle（与 close/超时同走 settleFail）
function consumeReplyLines(lines: string[], request: NodeBridgeRequestLine,
  settleOk: (reply: NodeBridgeReply) => void, settleFail: (message: string) => void): void {
  for (let i: number = 0; i < lines.length; i++) {
    let reply: NodeBridgeReply;
    try {
      reply = parseReplyLine(lines[i]);
    } catch (e) {
      settleFail('回执不是合法 JSON，' + (e as Error).message);
      return;
    }
    if (reply.requestId !== request.requestId) {
      continue;
    }
    settleOk(reply);
    return;
  }
}

// TCP 单次请求（回环；探针页 probeOnce 先例升级：+ token 首包 + 响应超时 + 端点校验）
function requestOverTcp(endpoint: NodeBridgeEndpoint, request: NodeBridgeRequestLine,
  responseTimeoutMs: number): Promise<NodeBridgeReply> {
  return new Promise<NodeBridgeReply>((resolve: (value: NodeBridgeReply) => void,
    reject: (reason: Error) => void): void => {
    const port: number = endpoint.port !== undefined ? endpoint.port : 0;
    if (port <= 0) {
      reject(new Error('endpoint 端口无效，无法连接'));
      return;
    }
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const lineBuffer: NodeBridgeLineBuffer = new NodeBridgeLineBuffer();
    let settled: boolean = false;
    let timerId: number = -1;
    const cleanup = (): void => {
      if (timerId >= 0) {
        clearTimeout(timerId);
        timerId = -1;
      }
      try {
        tcp.off('message');
      } catch (e) {
        // 注销失败不阻断（socket 随即关闭）
      }
      try {
        tcp.off('error');
      } catch (e) {
        // 同上
      }
      try {
        tcp.off('close');
      } catch (e) {
        // 同上
      }
      tcp.close().catch((): void => {
        // 关闭失败不阻断
      });
    };
    const settleOk = (reply: NodeBridgeReply): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolve(reply);
    };
    const settleFail = (message: string): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      reject(new Error(message));
    };
    // 响应兜底超时（连接后到首回执之间的无响应防护）
    timerId = setTimeout((): void => {
      timerId = -1;
      settleFail('桥接响应超时');
    }, responseTimeoutMs);
    tcp.on('message', (info: socket.SocketMessageInfo): void => {
      if (settled) {
        return;
      }
      consumeReplyLines(lineBuffer.feed(new Uint8Array(info.message)), request, settleOk, settleFail);
    });
    tcp.on('error', (err: BusinessError): void => {
      settleFail('回环连接出错，' + err.message);
    });
    // 断连即失败：服务端异常退出或对端 FIN 不再等满响应超时
    tcp.on('close', (): void => {
      settleFail('桥接连接已断开');
    });
    tcp.connect({
      address: { address: '127.0.0.1', port: port, family: 1 },
      timeout: NODE_BRIDGE_CONNECT_TIMEOUT_MS
    }).then((): Promise<void> => {
      return tcp.send({ data: JSON.stringify(request) + '\n' });
    }).catch((e: Error): void => {
      settleFail('回环连接失败，' + e.message);
    });
  });
}

// UDS 单次请求（pathname 模式；客户端不 bind 服务端路径——直接 connect）
function requestOverUds(endpoint: NodeBridgeEndpoint, request: NodeBridgeRequestLine,
  responseTimeoutMs: number): Promise<NodeBridgeReply> {
  return new Promise<NodeBridgeReply>((resolve: (value: NodeBridgeReply) => void,
    reject: (reason: Error) => void): void => {
    const socketPath: string = endpoint.socketPath !== undefined ? endpoint.socketPath : '';
    if (socketPath === '') {
      reject(new Error('endpoint 缺 socketPath，无法连接'));
      return;
    }
    if (util.TextEncoder.create('utf-8').encodeInto(socketPath).byteLength > NODE_UDS_MAX_PATH_BYTES) {
      reject(new Error('UDS 路径超出 107 字节上限，无法连接'));
      return;
    }
    const local: socket.LocalSocket = socket.constructLocalSocketInstance();
    const lineBuffer: NodeBridgeLineBuffer = new NodeBridgeLineBuffer();
    let settled: boolean = false;
    let timerId: number = -1;
    const cleanup = (): void => {
      if (timerId >= 0) {
        clearTimeout(timerId);
        timerId = -1;
      }
      try {
        local.off('message');
      } catch (e) {
        // 注销失败不阻断（socket 随即关闭）
      }
      try {
        local.off('error');
      } catch (e) {
        // 同上
      }
      try {
        local.off('close');
      } catch (e) {
        // 同上
      }
      local.close().catch((): void => {
        // 关闭失败不阻断
      });
    };
    const settleOk = (reply: NodeBridgeReply): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolve(reply);
    };
    const settleFail = (message: string): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      reject(new Error(message));
    };
    timerId = setTimeout((): void => {
      timerId = -1;
      settleFail('桥接响应超时');
    }, responseTimeoutMs);
    local.on('message', (info: socket.LocalSocketMessageInfo): void => {
      if (settled) {
        return;
      }
      consumeReplyLines(lineBuffer.feed(new Uint8Array(info.message)), request, settleOk, settleFail);
    });
    local.on('error', (err: BusinessError): void => {
      settleFail('UDS 连接出错，' + err.message);
    });
    // 断连即失败（与 TCP 同口径）
    local.on('close', (): void => {
      settleFail('桥接连接已断开');
    });
    local.connect({
      address: { address: socketPath },
      timeout: NODE_BRIDGE_CONNECT_TIMEOUT_MS
    }).then((): Promise<void> => {
      return local.send({ data: JSON.stringify(request) + '\n' });
    }).catch((e: Error): void => {
      settleFail('UDS 连接失败，' + e.message);
    });
  });
}

// 单次鉴权请求（一请求一连接；通道按 endpoint.channel 分流，不做运行时静默切换）。
// fields 逐项按「有值才发」填装——bootstrap 侧对 exec 四件 fail-closed 校验，缺字段即 bad-request。
export function requestNodeBridge(endpoint: NodeBridgeEndpoint, action: string,
  fields: NodeBridgeRequestFields, responseTimeoutMs?: number): Promise<NodeBridgeReply> {
  const request: NodeBridgeRequestLine = {
    protocol: NODE_BRIDGE_PROTOCOL,
    token: endpoint.token,
    action: action,
    requestId: nextBridgeRequestId()
  };
  if (fields.code !== undefined) {
    request.code = fields.code;
  }
  if (fields.sessionId !== undefined) {
    request.sessionId = fields.sessionId;
  }
  if (fields.cwd !== undefined) {
    request.cwd = fields.cwd;
  }
  if (fields.timeoutMs !== undefined) {
    request.timeoutMs = fields.timeoutMs;
  }
  if (fields.specs !== undefined) {
    request.specs = fields.specs;
  }
  if (fields.bin !== undefined) {
    request.bin = fields.bin;
  }
  if (fields.args !== undefined) {
    request.args = fields.args;
  }
  const timeout: number = responseTimeoutMs !== undefined ? responseTimeoutMs
    : NODE_BRIDGE_RESPONSE_TIMEOUT_MS;
  if (endpoint.channel === 'uds') {
    return requestOverUds(endpoint, request, timeout);
  }
  return requestOverTcp(endpoint, request, timeout);
}

// 只带代码的单次请求（探针页与一次性诊断的便捷入口；执行域走 requestNodeBridge 带全字段）
export function bridgeRequest(endpoint: NodeBridgeEndpoint, action: string,
  code?: string, responseTimeoutMs?: number): Promise<NodeBridgeReply> {
  const fields: NodeBridgeRequestFields = {};
  if (code !== undefined) {
    fields.code = code;
  }
  return requestNodeBridge(endpoint, action, fields, responseTimeoutMs);
}
