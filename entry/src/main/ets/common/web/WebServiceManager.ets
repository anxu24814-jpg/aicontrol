// Web 服务管理器（进程级单例，模块级 export const 形制——chatLiveHub 同款；禁长持 UI 组件
// 引用〔寿命匹配红线〕，EntryAbility 以惰性单例引用挂前后台两钩）。
// 职责一句话：**双栈启停编排与状态面**——持 TcpHttpStaticCarrier（:8800 静态面 + SSE 动态面
// 编解码）与 SseStreamHub（动态面会话/鉴权/下行）两件统一启停（原子启动：先静态面后 SSE 中枢，
// 任一失败整体回滚——禁半栈运行），对外四态状态机 + 状态变更监听（启动卡消费）+ pause/resume
// 前后台档（挂 EntryAbility）+ kill-switch 入口闸（prefWebServiceEnable = false 时 start()
// 直接拒绝，零端口监听）。鉴权钩由 start() 内装配（WebAuthValidator 口令校验单源）；载体
// onMessage 经 dispatchCarrierMessage 分流：直播旁路 → 无头宿主写路由（send/stop）→ 读 API。
// ★ SSE 备胎史：原 WS 动态面（WsGateway :8801）真机 2302999 起不来（取证见 SseStreamHub
// 头注释），动态面载体已整体换为 SseStreamHub（接口面零变）；WsGateway 转备用件不接线
//（重新启用步骤见其头注释），deriveWsPort 口径保留（/__cfg 仍透出该端口提示）。
// pause/resume 与 2301103 规避：退后台 2s 网络冻结、12s 释放，冻结期旧连接对象复用必报
// 2301103 Connection aborted——pause() 主动 close 两栈（server_paused 广播体归直播泵注册进
// pause 回调位，本件只保证钩子先于断连触发）；resume() 先 close 残留再 listen（两载体 stop
// 幂等清理，绝不复用冻结期旧连接/旧 server 对象）。
// 端口口径：HTTP 面缺省 8800（偏好键可改，clampWebPort 单源钳位）；WS 面 = 基数+1 派生
//（deriveWsPort 单源，不单列配置项；SSE 档下只作 /__cfg 提示字段）；bind 失败 fail-fast 返回
// 错误码**禁自动随机换口**（TCP 侧 listen 后 getLocalAddress 核验 → 载体件抛错，本件收拢为
// 错误码 + 中文 message）。
// 内存防线：状态监听者与 pause 钩均为有界 Set（成对注销）；stop 全清两载体簿记；日志直走
// hilog 不建内存缓冲。依赖纪律（零环）：只引本域载体件 + AppPreferencesWeb 叶子 +
// @kit ConnectivityKit（wifiManager 取本机 IP），禁 import UI 件与聊天域件。
// ★ 2026-10-23 起本域（common/web 九件 + AppPreferencesWeb + WebServiceSettingsPage +
// web-ui 工程 + rawfile/webui 产物）随 Web 伴生面冻结：不做专门同步与增强；改共享路径须保
// 本域编译绿与 assert-web-domain / assert-web-ui 钉绿；协议常量封闭枚举禁改名/加值/删值；
// web 缺陷登记 BLOCKED 不主动修。细则 = AGENTS.md「开发要求」节「Web 服务与 WebUI 伴生面
// 冻结」条。
import { wifiManager } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isWebServiceEnabled, isWebServiceLoopbackOnly, webServicePort } from '../AppPreferencesWeb';
import { buildWebServiceAuthValidator } from './WebAuthValidator';
import { dispatchWebApi, WebApiSender } from './WebReadApi';
import { webHeadlessHost } from './WebHeadlessHost';
import { WebLiveDownlink, webLivePump } from './WebLivePump';
import { CarrierEvents, TransportCarrier } from './TransportCarrier';
import { SseStreamHub } from './SseStreamHub';
import { TcpHttpStaticCarrier } from './TcpHttpStaticCarrier';

const WEB_LOG_DOMAIN: number = 0xD5A0;
const WEB_LOG_TAG: string = 'WebServiceManager';

// 状态监听者/pause 钩上限（有界——超限拒绝注册回 false/0 由调用方检查，禁静默）
export const WEB_STATE_LISTENER_LIMIT: number = 16;
export const WEB_PAUSE_HOOK_LIMIT: number = 4;

// ── 纯函数面（零 @kit 依赖，断言脚本剥 import 直跑）──

// 服务四态（stopped 停止 / starting 启动中 / running 运行 / paused 退后台暂停）
export type WebServiceState = 'stopped' | 'starting' | 'running' | 'paused';

// 状态机迁移合法性（断言直跑矩阵）：合法边 = stopped→starting、starting→running、
// starting→stopped（启动失败回滚）、running→paused、running→stopped、paused→starting、
// paused→stopped；其余全非法
export function webServiceTransitionValid(from: WebServiceState, to: WebServiceState): boolean {
  if (from === 'stopped') {
    return to === 'starting';
  }
  if (from === 'starting') {
    return to === 'running' || to === 'stopped';
  }
  if (from === 'running') {
    return to === 'paused' || to === 'stopped';
  }
  if (from === 'paused') {
    return to === 'starting' || to === 'stopped';
  }
  return false;
}

// WS 端口派生（基数+1——HTTP 8800 → WS 8801；用户心智只有一个号）
export function deriveWsPort(httpPort: number): number {
  return httpPort + 1;
}

// 绑定地址解析（仅本机档 127.0.0.1 / 局域网档 = 本机 WLAN 具体 IP；仅本机档免鉴权由鉴权
// 钩表达，地址档位本身单源在此）。★ 真机实测：局域网档绑 0.0.0.0 通配被底层拒绝（lws 不收
// wildcard，实报 2302999；d.ts 2302004 要求具体网卡），必须传 getLocalLanIp() 取到的具体地址；
// lanIp 由调用方传入保纯函数可测性，空串判定在 startBothStacks 先行 fail-fast
export function resolveBindAddress(loopbackOnly: boolean, lanIp: string): string {
  return loopbackOnly ? '127.0.0.1' : lanIp;
}

// wifiManager.getIpInfo().ipAddress 整数 → 点分十进制。字节序 = **大端（网络序高位在前）**：
// 首段取 bit31-24、末段取 bit7-0。★ 真机实锤：原实现按小端取段把 192.168.43.4 转成
// "4.43.168.192" 去 bind，socket 当场返回 2303199「address not available」——反序即路由器
// 实际网段，故小端读法确定错；官方 FAQ 只说该值「需要转换为 IP 常用格式」未给序，字节序由
// 真机取证定。非法值（0/负数/非整数/超 32 位）回 '' = 无 Wi-Fi/未连接（地址行显示引导文案）；
// 首段为 0 的一律回 ''（0.x.x.x 不可能是有效本机地址——再兜一层字节序事故）
export function wifiIpIntToDotted(ip: number): string {
  if (!Number.isInteger(ip) || ip <= 0 || ip > 0xFFFFFFFF) {
    return '';
  }
  const o1: number = (ip >>> 24) & 0xFF;
  if (o1 === 0) {
    return '';
  }
  const o2: number = (ip >>> 16) & 0xFF;
  const o3: number = (ip >>> 8) & 0xFF;
  const o4: number = ip & 0xFF;
  return o1.toString() + '.' + o2.toString() + '.' + o3.toString() + '.' + o4.toString();
}

// ── 启停结果（fail-fast 错误码 + 中文 message；code 语义见常量注记）──

export const WEB_ERR_OK: number = 0;
export const WEB_ERR_DISABLED: number = 1;
export const WEB_ERR_START_FAILED: number = 2;
export const WEB_ERR_INVALID_STATE: number = 3;

export interface WebServiceResult {
  readonly ok: boolean;
  readonly code: number;
  readonly message: string;
}

// 状态监听者接口（启动卡消费——状态翻转即时刷新徽标）
export interface WebStateListener {
  onWebServiceStateChanged(from: WebServiceState, to: WebServiceState): void;
}

// pause 钩形态（钩子可返回 Promise——pause 必须等 server_paused 真正广播完再关栈，否则多连接
// 时后续连接收不到暂停帧、前端退化为普通断线重连）
export type WebPauseHook = () => Promise<void>;

// 启停票（启停串行闸配套）：gen = 请求入队时自增的代次，release = 交还执行权；排队请求按序
// 全部执行（丢弃旧请求会制造开关态与服务态分叉），代次只用于识别「更晚的完成已先落地」的
// 过期完成
interface WebLifecycleTicket {
  readonly gen: number;
  release: () => void;
}

// 读 API 回信通道（WebApiSender 的类实现——ArkTS 不收函数字面量直赋接口；持动态面载体
// 引用转发 sendTo，sendTo 只对已鉴权会话开放、不可达会话回 false 零副作用）
class CarrierApiSender implements WebApiSender {
  private readonly carrier: TransportCarrier;

  constructor(carrier: TransportCarrier) {
    this.carrier = carrier;
  }

  send(connId: string, text: string): Promise<boolean> {
    return this.carrier.sendTo(connId, text);
  }
}

// 载体事件骨架实现：onMessage 接读 API 分发（动态面载体未鉴权拦截〔fail-closed ②〕之后的
// 消息才到达此处，本类零鉴权零簿记）。类实现而非对象字面量——arkts-no-untyped-obj-literals
// 对函数成员字面量拒收
class ManagerCarrierEvents implements CarrierEvents {
  private readonly owner: WebServiceManager;

  constructor(owner: WebServiceManager) {
    this.owner = owner;
  }

  onConnect(_connId: string): void {
  }

  onMessage(connId: string, text: string): void {
    this.owner.dispatchCarrierMessage(connId, text);
  }

  // 断连即释放该连接持有的无头会话与直播客户端条目（成对释放：订阅/引用计数/帧队列各归各件）
  onDisconnect(connId: string): void {
    webLivePump.releaseConn(connId);
    webHeadlessHost.releaseConn(connId);
  }

  onError(code: number, message: string): void {
    hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '载体错误 %{public}d：%{public}s', code, message);
  }
}

// 直播下行通道适配：镜像器只认窄接口，本类把 sendTo/broadcast 原样转动态面载体——
// 未鉴权/失联会话由载体件拒发（fail-closed ②），镜像器零感知
class CarrierLiveDownlink implements WebLiveDownlink {
  private readonly carrier: TransportCarrier;

  constructor(carrier: TransportCarrier) {
    this.carrier = carrier;
  }

  sendTo(connId: string, text: string): Promise<boolean> {
    return this.carrier.sendTo(connId, text);
  }

  broadcast(text: string): Promise<number> {
    return this.carrier.broadcast(text);
  }
}

// 直播泵随服务状态起停（状态监听）：starting = 双栈监听前挂上全局桶订阅（连接进来即
// 有下行面）；stopped/paused = 两栈与连接已收，泵退订清队列（成对释放，不留残订）
class ManagerLivePumpListener implements WebStateListener {
  private readonly owner: WebServiceManager;

  constructor(owner: WebServiceManager) {
    this.owner = owner;
  }

  onWebServiceStateChanged(_from: WebServiceState, to: WebServiceState): void {
    if (to === 'starting') {
      this.owner.startLivePump();
      return;
    }
    if (to === 'stopped' || to === 'paused') {
      this.owner.stopLivePump();
    }
  }
}

export class WebServiceManager {
  private state: WebServiceState = 'stopped';
  // 动态面中枢（SSE）：会话/鉴权/下行投递；静态面载体把 /events 与 /api/msg 委托给它
  private readonly sseHub: SseStreamHub = new SseStreamHub();
  private readonly tcpCarrier: TcpHttpStaticCarrier = new TcpHttpStaticCarrier();
  private listeners: Set<WebStateListener> = new Set<WebStateListener>();
  private pauseHooks: Set<WebPauseHook> = new Set<WebPauseHook>();
  // pause 广播钩（server_paused 广播体——只调泵，泵未挂/无连接时零动作）
  private readonly livePauseHook: WebPauseHook = (): Promise<void> => {
    return webLivePump.broadcastServerPaused();
  };
  private httpPort: number = 0;
  private bindAddress: string = '';
  // ★ 启停串行闸（尾链 Promise）+ 代次号——start/resume/stop/pause 同一时刻只有一个在跑，
  // 杜绝「回前台 resume 与用户点关交错」导致的关态运行与监听孤儿
  private lifecycleTail: Promise<void> = Promise.resolve();
  private opGeneration: number = 0;
  private lastCompletedGen: number = 0;

  constructor() {
    const pumpListener: WebStateListener = new ManagerLivePumpListener(this);
    if (!this.registerStateListener(pumpListener)) {
      hilog.error(WEB_LOG_DOMAIN, WEB_LOG_TAG, '直播泵状态监听注册失败（监听槽满）');
    }
    if (!this.registerPauseHook(this.livePauseHook)) {
      hilog.error(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'server_paused 广播钩注册失败（钩位满）');
    }
  }

  currentState(): WebServiceState {
    return this.state;
  }

  // 当前生效端口面（地址行/诊断用；stopped 态回 0）
  activeHttpPort(): number {
    return this.httpPort;
  }

  // 当前生效绑定地址（地址行用：运行中显示实际监听档，运行中切「仅本机」时不像配置键
  // 那样立刻改变显示——绑定地址下次启停才收窄；stopped 态回 ''）
  activeBindAddress(): string {
    return this.bindAddress;
  }

  // 状态监听注册（成对注销 unregisterStateListener；满员回 false 由调用方检查）
  registerStateListener(listener: WebStateListener): boolean {
    if (this.listeners.size >= WEB_STATE_LISTENER_LIMIT && !this.listeners.has(listener)) {
      return false;
    }
    this.listeners.add(listener);
    return true;
  }

  unregisterStateListener(listener: WebStateListener): void {
    this.listeners.delete(listener);
  }

  // pause 回调位（server_paused 广播体注册于此——保证先于断连触发；满员回 false）
  registerPauseHook(hook: WebPauseHook): boolean {
    if (this.pauseHooks.size >= WEB_PAUSE_HOOK_LIMIT && !this.pauseHooks.has(hook)) {
      return false;
    }
    this.pauseHooks.add(hook);
    return true;
  }

  unregisterPauseHook(hook: WebPauseHook): void {
    this.pauseHooks.delete(hook);
  }

  // 启停串行取票：入队即吞尾链，等到前一笔 release 才执行——同一时刻只有一个启停操作在跑；
  // gen = 请求时刻序号，completeLifecycle 记「已完成的最大代次」，供启动/恢复在提交 running
  // 前辨识「本次完成已被更晚完成的操作为旧」（串行链下不应发生，兜未来绕过本闸的直接调用）
  private async acquireLifecycle(): Promise<WebLifecycleTicket> {
    const gen: number = ++this.opGeneration;
    const previous: Promise<void> = this.lifecycleTail;
    let release: () => void = (): void => {
    };
    this.lifecycleTail = new Promise<void>((resolve: () => void): void => {
      release = resolve;
    });
    await previous;
    const ticket: WebLifecycleTicket = { gen: gen, release: release };
    return ticket;
  }

  // 交还执行权 + 记完成代次（finally 调用，异常路径也释放，不卡死后续启停）
  private completeLifecycle(ticket: WebLifecycleTicket): void {
    if (ticket.gen > this.lastCompletedGen) {
      this.lastCompletedGen = ticket.gen;
    }
    ticket.release();
  }

  // 过期完成判定（提交 running 前调用；正常串行链恒 false）
  private staleCompletion(ticket: WebLifecycleTicket): boolean {
    return ticket.gen < this.lastCompletedGen;
  }

  // 直播泵起停（U6——由 ManagerLivePumpListener 在状态边沿调用）：起泵 = 中枢全局桶订阅 +
  // 下行通道装配；订阅失败（中枢桶满）只留痕不阻断服务（直播面降级，读/写面照常）
  startLivePump(): void {
    if (!webLivePump.start(new CarrierLiveDownlink(this.sseHub))) {
      hilog.error(WEB_LOG_DOMAIN, WEB_LOG_TAG, '直播泵订阅中枢失败（桶满），下行直播不可用');
    }
  }

  stopLivePump(): void {
    webLivePump.stop();
  }

  // ── 启动（kill-switch 闸 → starting → 先静态面后 SSE 中枢 → 任一失败整体回滚）──
  async start(): Promise<WebServiceResult> {
    const ticket: WebLifecycleTicket = await this.acquireLifecycle();
    try {
      if (this.state === 'starting' || this.state === 'running') {
        return this.failResult(WEB_ERR_INVALID_STATE, '服务已在启动或运行中');
      }
      // ★ kill-switch：偏好关 = 直接拒绝（入口行可见但零监听——回滚三层之软回退面）
      if (!isWebServiceEnabled()) {
        return this.failResult(WEB_ERR_DISABLED, 'Web 服务未开启（设置内开启后再启动）');
      }
      // 鉴权钩装配（口令校验单源 WebAuthValidator——每次启服注入最新闭包；键值
      // 实时读，服务不起则零装配，kill-switch 关态零行为增量）。钩注入动态面
      // 中枢（WsGateway 备用件不接线，其钩在重新启用时同源注入）
      this.sseHub.setAuthValidator(buildWebServiceAuthValidator());
      const okStart: boolean = this.transitionTo('starting');
      if (!okStart) {
        return this.failResult(WEB_ERR_INVALID_STATE, '状态机拒绝启动（当前 ' + this.state + '）');
      }
      const result: WebServiceResult = await this.startBothStacks();
      if (!result.ok) {
        // 原子启动回滚：任一栈失败整服不起（回 stopped——starting→stopped 合法边）
        this.transitionTo('stopped');
        return result;
      }
      // 完成前复检 kill-switch：启动窗口内开关被关（关路径的 stop 已在本闸后排队）——
      // 回滚不提交 running，开关态与服务态保持一致。更新请求不在此拦截：串行闸会按序执行
      // 后续操作（最后一次输入为准），中途回滚会让「开关开而服务停」的旧症状复活
      if (!isWebServiceEnabled()) {
        await this.stopBothStacks();
        this.transitionTo('stopped');
        return this.failResult(WEB_ERR_DISABLED, 'Web 服务已关闭，启动取消');
      }
      // 过期完成守卫（正常串行恒 false）：不把旧启动结果提交为 running
      if (this.staleCompletion(ticket)) {
        await this.stopBothStacks();
        this.transitionTo('stopped');
        return this.failResult(WEB_ERR_INVALID_STATE, '启动完成已被更晚的启停操作取代');
      }
      this.transitionTo('running');
      return this.okResult('Web 服务已启动');
    } finally {
      this.completeLifecycle(ticket);
    }
  }

  // 双栈编排（★ SSE 备胎形态：先静态面监听，再起 SSE 中枢；两件同端口同址，静态面的
  // /events 与 /api/msg 两路由把语义委托中枢。wsPortHint 仍按 deriveWsPort 派生下发——
  // 它是 /__cfg 的传输提示字段，前端在 transport = 'sse' 时不消费，WS 备用件重启时同值可用）
  private async startBothStacks(): Promise<WebServiceResult> {
    const httpPort: number = webServicePort();
    const wsPort: number = deriveWsPort(httpPort);
    // 局域网档绑本机 WLAN 具体 IP（★ 真机修复：lws 拒 0.0.0.0 通配的历史结论对 TCP 同样适用
    // ——绑具体地址在真机上被验证无副作用，见 resolveBindAddress 头注释）；无 WLAN 地址
    //（未连 Wi-Fi/蜂窝）先 fail-fast，给用户可理解的明确原因
    const lanIp: string = this.getLocalLanIp();
    if (!isWebServiceLoopbackOnly() && lanIp === '') {
      return this.failResult(WEB_ERR_START_FAILED, '未连接 WLAN，无法获取局域网地址。请连接 Wi-Fi 后重试');
    }
    this.bindAddress = resolveBindAddress(isWebServiceLoopbackOnly(), lanIp);
    this.httpPort = httpPort;
    const events: CarrierEvents = this.buildCarrierEvents();
    // 委托面先接线（静态面一起来就可能收到 /events 与 /api/msg）
    this.tcpCarrier.setStreamSink(this.sseHub);
    try {
      await this.tcpCarrier.start({ bindAddress: this.bindAddress, port: httpPort, wsPortHint: wsPort },
        events);
    } catch (e) {
      this.tcpCarrier.setStreamSink(null);
      await this.stopBothStacks();
      return this.failResult(WEB_ERR_START_FAILED, '静态面启动失败。' + (e as Error).message);
    }
    try {
      await this.sseHub.start({ bindAddress: this.bindAddress, port: httpPort, wsPortHint: wsPort },
        events);
    } catch (e) {
      await this.stopBothStacks();
      return this.failResult(WEB_ERR_START_FAILED, '动态面启动失败。' + (e as Error).message);
    }
    return this.okResult('');
  }

  // 载体事件面（onMessage → 读 API 分发；直播下行在此扩展）
  private buildCarrierEvents(): CarrierEvents {
    return new ManagerCarrierEvents(this);
  }

  // 载体上行消息 → 写路由（send/stop）与读 API 分发（回信走 sseHub.sendTo——未鉴权/失联
  // 会话在载体件已拦，sendTo 对不可达会话回 false 零副作用；响应体积预算在 WebReadApi 侧
  // 常量约束）。前置分流：本件只按无头宿主接管结果择路（信封 type 判据单源在
  // WebHeadlessHost；返回值 false = 非 send/stop 族），读 API 的坏信封兜底路径不变。
  // 公开方法：ManagerCarrierEvents 为独立类，跨类调用需非 private
  dispatchCarrierMessage(connId: string, text: string): void {
    // ★ 直播旁路：先喂直播镜像器（已鉴权连接的登录/窄播登记/首开 snapshot；零路由副作用），
    // 再走写路由与读 API——旁路异常不得吞掉业务消息，泵内部自兜底
    webLivePump.observeClientMessage(connId, text);
    const sender: CarrierApiSender = new CarrierApiSender(this.sseHub);
    if (webHeadlessHost.handleMessage(connId, text, sender)) {
      return;
    }
    dispatchWebApi(connId, text, sender);
  }

  // ── 停止（幂等；paused/stopped 态调用无害）──
  // 停服即无头会话全量成对释放（退订 + releaseHeadless；在途轮按编排链自然收尾，
  // 下次连接按需重建）——断连事件已覆盖逐连接释放，此处兜「连接簿记先清」的收尾序
  async stop(): Promise<WebServiceResult> {
    const ticket: WebLifecycleTicket = await this.acquireLifecycle();
    try {
      await this.stopBothStacks();
      webHeadlessHost.closeAll();
      // ★ 自检修：stopped→stopped 不是合法边（webServiceTransitionValid 拒），已停即无需
      // 迁移——否则会在「本来已停」的调用上打「非法状态迁移」error 日志（关态重复点停、开关
      // 连点、启动回滚后排队 stop 三路都会走到）
      if (this.state !== 'stopped') {
        this.transitionTo('stopped');
      }
      return this.okResult('Web 服务已停止');
    } finally {
      this.completeLifecycle(ticket);
    }
  }

  // ── 退后台暂停（先触发 pause 钩〔server_paused 广播〕再主动 close 两栈——
  // 主动断优于被杀；在途 web 轮在既有短时任务窗内照跑，web 端断线等回前台 snapshot 补齐）──
  async pause(): Promise<WebServiceResult> {
    const ticket: WebLifecycleTicket = await this.acquireLifecycle();
    try {
      if (this.state !== 'running') {
        return this.okResult('服务未运行，无需暂停');
      }
      // ★ 钩子逐个 await——server_paused 广播必须真正发出后才关栈（fire-and-forget 时多连接
      // 下后发连接随 close 丢失，前端退化为普通断线重连）
      const hooks: WebPauseHook[] = [];
      this.pauseHooks.forEach((hook: WebPauseHook): void => {
        hooks.push(hook);
      });
      for (const hook of hooks) {
        try {
          await hook();
        } catch (e) {
          hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'pause 钩异常（%{public}s）', (e as Error).message);
        }
      }
      await this.stopBothStacks();
      // 退后台连接已断（onDisconnect 逐连接释放），此处兜全量——在途 web 轮不掐（只
      // 释放引用计数，收尾照跑；回前台重连后按需重建会话）
      webHeadlessHost.closeAll();
      this.transitionTo('paused');
      return this.okResult('Web 服务已暂停（回前台自动恢复）');
    } finally {
      this.completeLifecycle(ticket);
    }
  }

  // ── 回前台恢复（先 close 残留再 listen——2301103 规避：绝不复用冻结期连接对象；暂停态
  // 间开关被关 = 不复活，落 stopped 回 DISABLED）──
  async resume(): Promise<WebServiceResult> {
    const ticket: WebLifecycleTicket = await this.acquireLifecycle();
    try {
      if (this.state !== 'paused') {
        return this.okResult('服务未在暂停态');
      }
      // close 残留（幂等——两载体 stop 清各自连接簿记与监听）
      await this.stopBothStacks();
      if (!isWebServiceEnabled()) {
        this.transitionTo('stopped');
        return this.failResult(WEB_ERR_DISABLED, 'Web 服务已关闭（暂停期间开关被关，不自动恢复）');
      }
      const okStart: boolean = this.transitionTo('starting');
      if (!okStart) {
        return this.failResult(WEB_ERR_INVALID_STATE, '状态机拒绝恢复（当前 ' + this.state + '）');
      }
      const result: WebServiceResult = await this.startBothStacks();
      if (!result.ok) {
        this.transitionTo('stopped');
        return result;
      }
      // 更新请求不在此拦截：串行闸按序执行后续操作（如紧随的 stop 会立即收栈），
      // 中途回滚反而制造开关态与服务态分叉；过期完成守卫兜绕过串行闸的直接调用
      if (this.staleCompletion(ticket)) {
        await this.stopBothStacks();
        this.transitionTo('stopped');
        return this.failResult(WEB_ERR_INVALID_STATE, '恢复完成已被更晚的启停操作取代');
      }
      this.transitionTo('running');
      return this.okResult('Web 服务已恢复');
    } finally {
      this.completeLifecycle(ticket);
    }
  }

  // 本机局域网 IP（地址行数据源；'' = 无 Wi-Fi/未连接——显示引导文案不显残址）
  getLocalLanIp(): string {
    try {
      const info: wifiManager.IpInfo = wifiManager.getIpInfo();
      const dotted: string = wifiIpIntToDotted(info.ipAddress);
      // 原始值随日志留痕（字节序类问题只看点分串难归因，看图整数一行即知）
      hilog.info(WEB_LOG_DOMAIN, WEB_LOG_TAG, '本机 WLAN 地址 %{public}s（getIpInfo 原值 %{public}d）',
        dotted === '' ? '（无）' : dotted, info.ipAddress);
      return dotted;
    } catch (e) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'getIpInfo 异常（%{public}s）',
        (e as Error).message);
      return '';
    }
  }

  // 状态迁移（单点：先验合法性再落态再通知——非法迁移拒绝并回 false，断言矩阵直跑同判据）
  private transitionTo(to: WebServiceState): boolean {
    const from: WebServiceState = this.state;
    if (!webServiceTransitionValid(from, to)) {
      hilog.error(WEB_LOG_DOMAIN, WEB_LOG_TAG, '非法状态迁移 %{public}s → %{public}s', from, to);
      return false;
    }
    this.state = to;
    const snapshot: WebStateListener[] = [];
    this.listeners.forEach((listener: WebStateListener): void => {
      snapshot.push(listener);
    });
    for (const listener of snapshot) {
      try {
        listener.onWebServiceStateChanged(from, to);
      } catch (e) {
        hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '状态监听回调异常（%{public}s）',
          (e as Error).message);
      }
    }
    hilog.info(WEB_LOG_DOMAIN, WEB_LOG_TAG, '状态 %{public}s → %{public}s', from, to);
    return true;
  }

  private async stopBothStacks(): Promise<void> {
    // 先收动态面（会话表清空、流关），再收静态面（连接与监听全清）
    await this.sseHub.stop();
    await this.tcpCarrier.stop();
    this.tcpCarrier.setStreamSink(null);
    // 停栈即复位生效端口面（activeHttpPort 的「stopped 态回 0」契约由本处兑现——否则地址
    // 行/诊断会读到上一轮陈旧端口）
    this.httpPort = 0;
    this.bindAddress = '';
  }

  private failResult(code: number, message: string): WebServiceResult {
    const result: WebServiceResult = { ok: false, code: code, message: message };
    return result;
  }

  private okResult(message: string): WebServiceResult {
    const result: WebServiceResult = { ok: true, code: WEB_ERR_OK, message: message };
    return result;
  }
}

// 进程级单例（模块级单例形制——chatLiveHub/chatSessionRuntime 先例；EntryAbility 前后台
// 两钩、设置页、镜像器经此同一实例）
export const webServiceManager: WebServiceManager = new WebServiceManager();
