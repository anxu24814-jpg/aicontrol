// HTTP 工具域·事件流窗口读取域（2026-10-01 方案-HTTP工具笔9与笔8尾-事件流长任务 §3 机制
// 吸收落码）：SSE 分帧状态机 + 窗口参数钳制 + 事件聚合格式化三件纯逻辑。职责一句话 =
// 「把事件流的字节序列变成有界的事件文本」——传输与计时在 HttpTransport（本件不碰网络），
// 事件语义解释在模型侧（本件不做）。零 import 工具域（坑50：ToolHttp 引本件，本件不引任何
// 工具域件）；全部导出供 assert-tool-domain 直跑副本做执行级验证。
// · 两种收口强度不得混用（机制吸收第 1 条）：窗口到量（时长 / 条数 / 字节任一先到）= 软
//   停止，返回已收帧 + truncated（正常结果）；idle 超时 = 硬中止，回执带专用错误字段
//（code / idleMs / timeoutMs 三字段，见 HTTP_STREAM_ERROR_CODE）。软停是「读到足够了」，
// 硬中止是「对方断了没说」——回执语义不同，调用方按 terminalReason 分流组装。
// · 分帧状态机（机制吸收第 2 条）：缓冲累积 → 按 \r\n\r\n / \n\n / \r\r 切完整帧 → 帧内
//   聚合多行 data:（\n 连接）→ 结束 flush 补尾字节、残留当末帧；分隔符被 chunk 切开由
//   「先累积后扫描」天然处理（两用例见断言）。不做事件语义解释（[DONE] 之类留给模型）。
// · 窗口参数面（定案 2）：模型可传读多久 / 读多少条，钳制到硬上限，不加用户档位——数值
//   为执行笔按既有闸风格定值（照笔 4 timeout_ms 先例：默认档下行为与「无参数可传」时代
//   等价，硬顶防灌）。数值本身进 desc/schema（模型可见数字与常量单源）。

// ── 窗口参数常量（执行笔定值，变更记录本笔登记）──
// 总窗口（读取时长，自首字节起算——首字节前的等待由 kit readTimeout 承担，不双计）：未传
// 默认 10 秒，钳 [1 秒, 60 秒]。下限 1 秒 = 钳掉 0 与负值（0 = 立刻软停读了寂寞，照
// resolveHttpTimeoutMs「钳制必须挡住退化值」同款精神；上限不必挂用户超时档——窗口是读取
// 预算不是等待上限，两参数语义不同源）
export const HTTP_STREAM_WINDOW_MS_DEFAULT: number = 10000;
export const HTTP_STREAM_WINDOW_MS_MIN: number = 1000;
export const HTTP_STREAM_WINDOW_MS_MAX: number = 60000;
// 事件条数（event-stream 专属闸）：未传默认 200，硬顶 1000
export const HTTP_STREAM_MAX_EVENTS_DEFAULT: number = 200;
export const HTTP_STREAM_MAX_EVENTS_MAX: number = 1000;
// idle 超时（硬中止；常量不可配——「读多久/读多少」是模型面，停顿判定是传输健康面）：
// 收到首字节后起算，每收到数据重置。8 秒对 SSE 心跳（通常 15~30 秒）与慢流都宽容，
// 又不至于让真断流白等一个 readTimeout
export const HTTP_STREAM_IDLE_MS: number = 8000;
// 窗口内收集字节硬顶（软停止）：防「条数少但单事件超大」的病态流灌爆内存；与同步路径
// maxLimit 2MB 同量级更紧（事件文本进回执要过 8192 预算，收集超量部分注定弃用）
export const HTTP_STREAM_WINDOW_BYTES_MAX: number = 256 * 1024;
// idle 硬中止回执的错误码字面量（模型可辨认的结构化字段值，与 idleMs / timeoutMs 同回）
export const HTTP_STREAM_ERROR_CODE: string = 'stream_idle_timeout';

// 总窗口钳制（照 resolveHttpTimeoutMs 钳制钉先例）：未传 / 非有限值 = 默认 10 秒；否则
// clamp(传值, 1 秒, 60 秒)。NaN 会同时穿透两条分支（同源教训见该函数头注释），守卫兜底
export function resolveStreamWindowMs(requestedMs: number): number {
  const wanted: number = Number.isFinite(requestedMs) ? requestedMs : 0;
  if (wanted <= 0) {
    return HTTP_STREAM_WINDOW_MS_DEFAULT;
  }
  return Math.max(Math.min(wanted, HTTP_STREAM_WINDOW_MS_MAX), HTTP_STREAM_WINDOW_MS_MIN);
}

// 条数钳制：未传 / 非有限值 = 默认 200；否则 clamp(传值, 1, 1000)
export function resolveStreamMaxEvents(requested: number): number {
  const wanted: number = Number.isFinite(requested) ? requested : 0;
  if (wanted <= 0) {
    return HTTP_STREAM_MAX_EVENTS_DEFAULT;
  }
  return Math.max(Math.min(Math.round(wanted), HTTP_STREAM_MAX_EVENTS_MAX), 1);
}

// SSE 事件（裁剪版：只聚合 data——event / id / retry 字段与冒号注释行不产出）
export interface SseEvent {
  data: string;
}

// 帧分隔符扫描产物：pos = 分隔符起点，len = 分隔符长（三种形态长度不同）
interface FrameCut {
  pos: number;
  len: number;
}

// 找最早出现的帧分隔符（\r\n\r\n / \n\n / \r\r 任一）：三形态分别 indexOf 取最小非负。
// 跨 chunk 切开的分隔符（如上一片尾 '\r\n' + 这一片头 '\r\n'）由「先累积后扫描」天然命中
// ——不必也不会在 chunk 边界做部分匹配。返回 null = 无完整帧
function nextFrameCut(buf: string): FrameCut | null {
  let best: FrameCut | null = null;
  const candidates: string[] = ['\r\n\r\n', '\n\n', '\r\r'];
  for (const sep of candidates) {
    const at: number = buf.indexOf(sep);
    if (at >= 0 && (best === null || at < best.pos)) {
      best = { pos: at, len: sep.length };
    }
  }
  return best;
}

// 单帧 → 事件（纯函数）：按行拆（\r\n / \n / \r 三形态），聚合 data 行（冒号后一个空格按
// 规范剥掉）；event / id / retry 字段与冒号开头注释行忽略；无 data 行的帧不产出事件
//（SSE 规范：无 data 的帧不派发）。多行 data 以 \n 连接——服务端用它发多行 JSON 载荷
function parseFrame(frame: string): SseEvent | null {
  const lines: string[] = frame.split(/\r\n|\n|\r/);
  const dataLines: string[] = [];
  for (const line of lines) {
    if (line === '' || line.startsWith(':')) {
      continue;
    }
    if (line.startsWith('data') && (line.length === 4 || line.charAt(4) === ':')) {
      // 规范形态「data: value」——先剥字段名后的冒号，再剥冒号后可选的一个空格；
      // 「data」后无冒号（长度恰 4）按空值处理（SSE 规范字段名后必有冒号，宽容收编）
      let value: string = line.length === 4 ? '' : line.substring(5);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      dataLines.push(value);
    }
    // 其余字段行（event: / id: / retry: 与非法字段）按机制吸收「不做事件语义解释」忽略
  }
  if (dataLines.length === 0) {
    return null;
  }
  const ev: SseEvent = { data: dataLines.join('\n') };
  return ev;
}

// SSE 分帧状态机（有状态类；一次连接一个实例——传输层持有，非全局单例，无重入面）。
// 增量喂入、逐帧产出；流结束时 flush() 把残留（末帧无空行形态）补成末帧
export class SseFrameParser {
  private buffer: string = '';
  // ★ 调研修复笔 #4（2026-10-02）：首帧 BOM 剥除（镜像聊天链 SseParser.ets bomPending 同款
  // ——util.TextDecoder 的 ignoreBOM 默认 false，解码结果含 BOM；decodeToString stream 模式
  // 只缓冲跨片多字节、不剥 BOM ⇒ 服务端流首带 \uFEFF 时首行成「\uFEFFdata:」，前缀匹配不上
  // data 字段、首个事件静默丢失）。首个**非空** chunk 剥一次后置 false——空 chunk 不消费
  // 机会（BOM 可能在更晚分片）；中间帧再出现 BOM 不特殊处理（坏帧容错已兜）
  private bomPending: boolean = true;

  // 喂入增量文本，返回本次新凑齐的完整事件（含因本片数据而补齐的跨片帧）
  feed(chunk: string): SseEvent[] {
    let text: string = chunk;
    if (this.bomPending && text !== '') {
      this.bomPending = false;
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }
    }
    this.buffer += text;
    const events: SseEvent[] = [];
    for (;;) {
      const cut: FrameCut | null = nextFrameCut(this.buffer);
      if (cut === null) {
        break;
      }
      const frame: string = this.buffer.substring(0, cut.pos);
      this.buffer = this.buffer.substring(cut.pos + cut.len);
      const ev: SseEvent | null = parseFrame(frame);
      if (ev !== null) {
        events.push(ev);
      }
    }
    return events;
  }

  // 流结束收尾：残留缓冲当末帧解析（机制吸收「结束 flush 补尾字节、残留当末帧」）；
  // 残留仅空白 = 无尾帧
  flush(): SseEvent[] {
    const rest: string = this.buffer;
    this.buffer = '';
    if (rest.trim() === '') {
      return [];
    }
    const ev: SseEvent | null = parseFrame(rest);
    return ev !== null ? [ev] : [];
  }
}

// 事件聚合 → 回执 body 串（纯函数）：各事件 data 按序以空行连接（保留事件边界——模型
// 数事件或逐事件解析都可行；不重挂「data: 」前缀，data 已是净值）。入参 = 已收事件的
// data 净值序（传输层 parser.feed / flush 产出后以 string 形态传递）。条数上限由传输层
// 按收到序截断后才进本函数，本函数只做拼接
export function aggregateEventsText(events: string[]): string {
  return events.join('\n\n');
}
