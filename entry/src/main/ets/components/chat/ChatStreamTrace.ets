/**
 * 构建期流式显示观测。正式包关闭，不记录正文/地址/凭据，不逐token输出。
 * 发布与消费只更新标量，布局回调合并一条摘要；手势事件保留顺序号。
 * didLayout不是GPU呈现帧。单窗口诊断单例不持UI对象，离场清空，尾环最多2048条。
 * ★ RIK 组D 真机轨迹诊断包已于 2026-11-13 回置 false（变更记录两千一百五十四节，决明令）：
 * 需 hilog 轨迹复诊时临时置 true 重出诊断包，协议 = BLOCKED「RIK A第二轮真机块」条目（字面
 * 无空格，grep 可中）的复现条款（hilog 过滤 ChatStreamTrace），用完随笔回置。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

export const CHAT_STREAM_TRACE_ENABLED: boolean = false;
const RING_LIMIT: number = 2048;

export class ChatStreamTrace {
  private static ring: string[] = [];
  private static origin: number = 0;
  private static sequence: number = 0;
  private static binding: string = '';
  private static document: string = '';
  private static tailBottom: number = 0;
  private static viewport: number = 0;
  private static generation: number = 0;
  private static revision: number = 0;
  private static received: number = 0;
  private static published: number = 0;
  private static consumed: number = 0;
  private static consumeMs: number = 0;
  private static requested: number = 0;
  private static scrolledDistance: number = 0;
  private static height: number = 0;
  private static offset: number = 0;
  private static target: number = 0;
  private static velocity: number = 0;
  private static owner: string = 'idle';
  private static following: boolean = true;
  private static touching: boolean = false;
  private static moving: boolean = false;
  private static terminal: string = '';
  private static dirty: boolean = false;

  static begin(binding: string): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    if (ChatStreamTrace.ring.length > 0) { ChatStreamTrace.dump('next-stream'); }
    ChatStreamTrace.release();
    ChatStreamTrace.origin = Date.now();
    ChatStreamTrace.binding = binding;
  }

  static recv(units: number): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.received += units;
    ChatStreamTrace.dirty = true;
  }

  static publish(len: number, binding: string = ''): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.published = len;
    if (binding !== '' && binding !== ChatStreamTrace.binding) {
      ChatStreamTrace.binding = binding;
      ChatStreamTrace.document = '';
      ChatStreamTrace.generation = 0;
      ChatStreamTrace.revision = 0;
      ChatStreamTrace.consumed = 0;
      ChatStreamTrace.consumeMs = 0;
    }
    ChatStreamTrace.dirty = true;
  }

  static consume(kind: string, len: number, ms: number, binding: string = '', generation: number = 0,
    revision: number = 0, document: string = ''): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    if (binding !== '' && binding !== ChatStreamTrace.binding) { return; }
    ChatStreamTrace.consumed = len;
    ChatStreamTrace.consumeMs += ms;
    ChatStreamTrace.document = document;
    ChatStreamTrace.generation = generation;
    ChatStreamTrace.revision = revision;
    ChatStreamTrace.dirty = true;
  }

  static follow(note: string): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.moving = true;
    ChatStreamTrace.dirty = true;
  }

  static geometry(height: number, offset: number, target: number, velocity: number,
    tailBottom: number = 0, viewport: number = 0): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.tailBottom = tailBottom;
    ChatStreamTrace.viewport = viewport;
    ChatStreamTrace.height = height;
    ChatStreamTrace.offset = offset;
    ChatStreamTrace.target = target;
    ChatStreamTrace.velocity = velocity;
    ChatStreamTrace.dirty = true;
  }

  static displacement(offset: number, remaining: number, distance: number): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.requested += distance;
    ChatStreamTrace.offset = offset;
    ChatStreamTrace.target = offset + remaining;
    ChatStreamTrace.dirty = true;
  }

  static scrolled(distance: number): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.scrolledDistance += distance;
    ChatStreamTrace.dirty = true;
  }

  static input(event: string, owner: string, following: boolean, touching: boolean): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.owner = owner;
    ChatStreamTrace.following = following;
    ChatStreamTrace.touching = touching;
    ChatStreamTrace.push('input ' + event + ' owner=' + owner + ' follow=' + following + ' touch=' + touching);
    ChatStreamTrace.dirty = true;
  }

  static frame(epoch: number, owner: string = ChatStreamTrace.owner,
    following: boolean = ChatStreamTrace.following, touching: boolean = ChatStreamTrace.touching): void {
    if (!CHAT_STREAM_TRACE_ENABLED || !ChatStreamTrace.dirty) { return; }
    ChatStreamTrace.owner = owner;
    ChatStreamTrace.following = following;
    ChatStreamTrace.touching = touching;
    ChatStreamTrace.push('layout epoch=' + epoch + ' binding=' + ChatStreamTrace.binding +
      ' doc=' + ChatStreamTrace.document + ' gen=' + ChatStreamTrace.generation + ' rev=' + ChatStreamTrace.revision +
      ' recv=' + ChatStreamTrace.received + ' pub=' + ChatStreamTrace.published +
      ' consume=' + ChatStreamTrace.consumed + ' ms=' + ChatStreamTrace.consumeMs +
      ' height=' + ChatStreamTrace.height + ' bottom=' + ChatStreamTrace.tailBottom +
      ' viewport=' + ChatStreamTrace.viewport + ' offset=' + ChatStreamTrace.offset +
      ' target=' + ChatStreamTrace.target + ' velocity=' + ChatStreamTrace.velocity +
      ' request=' + ChatStreamTrace.requested + ' actual=' + ChatStreamTrace.scrolledDistance +
      ' owner=' + ChatStreamTrace.owner + ' follow=' + ChatStreamTrace.following +
      ' touch=' + ChatStreamTrace.touching);
    ChatStreamTrace.consumeMs = 0;
    ChatStreamTrace.requested = 0;
    ChatStreamTrace.scrolledDistance = 0;
    ChatStreamTrace.dirty = false;
    if (ChatStreamTrace.terminal !== '' && !ChatStreamTrace.moving) {
      ChatStreamTrace.dump('terminal-layout:' + ChatStreamTrace.terminal);
    }
  }

  static cancel(reason: string): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.moving = false;
    ChatStreamTrace.push(reason);
    if (ChatStreamTrace.terminal !== '') { ChatStreamTrace.frame(-1); ChatStreamTrace.dump(reason); }
  }

  static finish(status: string): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.terminal = status;
    ChatStreamTrace.dirty = true;
    ChatStreamTrace.push('terminal:' + status);
  }

  static dump(reason: string): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    if (ChatStreamTrace.ring.length === 0) { return; }
    hilog.info(0xD5A0, 'ChatStreamTrace', '摘要 %{public}s 尾环=%{public}d', reason, ChatStreamTrace.ring.length);
    for (let index: number = 0; index < ChatStreamTrace.ring.length; index++) {
      hilog.info(0xD5A0, 'ChatStreamTrace', '%{public}s', ChatStreamTrace.ring[index]);
    }
    ChatStreamTrace.ring = [];
    ChatStreamTrace.terminal = '';
  }

  static release(): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.ring = [];
    ChatStreamTrace.origin = 0;
    ChatStreamTrace.sequence = 0;
    ChatStreamTrace.binding = '';
    ChatStreamTrace.document = '';
    ChatStreamTrace.tailBottom = 0;
    ChatStreamTrace.viewport = 0;
    ChatStreamTrace.generation = 0;
    ChatStreamTrace.revision = 0;
    ChatStreamTrace.received = 0;
    ChatStreamTrace.published = 0;
    ChatStreamTrace.consumed = 0;
    ChatStreamTrace.consumeMs = 0;
    ChatStreamTrace.requested = 0;
    ChatStreamTrace.scrolledDistance = 0;
    ChatStreamTrace.height = 0;
    ChatStreamTrace.offset = 0;
    ChatStreamTrace.target = 0;
    ChatStreamTrace.velocity = 0;
    ChatStreamTrace.owner = 'idle';
    ChatStreamTrace.following = true;
    ChatStreamTrace.touching = false;
    ChatStreamTrace.moving = false;
    ChatStreamTrace.terminal = '';
    ChatStreamTrace.dirty = false;
  }

  private static push(event: string): void {
    if (ChatStreamTrace.origin === 0) { ChatStreamTrace.origin = Date.now(); }
    if (ChatStreamTrace.ring.length >= RING_LIMIT) { ChatStreamTrace.ring.shift(); }
    ChatStreamTrace.ring.push((++ChatStreamTrace.sequence).toString() + ' +' +
      (Date.now() - ChatStreamTrace.origin).toString() + 'ms ' + event);
  }
}
