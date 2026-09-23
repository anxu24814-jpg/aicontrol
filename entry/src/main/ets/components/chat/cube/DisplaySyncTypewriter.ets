// MIT License — 本文件源自第三方 MIT 开源项目 chatcube（github.com/LongLiveY96/chatcube，
// 2026-06-05 归档快照），2026-09-02 阶段 2 文件级引入本试验副本。上游许可证全文见仓库根
// LICENSE-THIRD-PARTY.md。
// 适配点（仅此三处，其余逐行保真自 utils/DisplaySyncTypewriter.ets）：
// 1. StreamFlusher 接口自 ThrottleUtil.ets 随迁内联（ThrottleUtil 时间片类未引入——UIContext
//    恒可达场景无兜底必要，见 CubeStreamFlushers.ets 头注释）；
// 2. 上游文件头补充本版权与适配声明（源文件无头注释）；
// 3. 五条生命周期硬约束注释原样保留（下方 49-62 行）——消费方必须遵守。
import { displaySync } from '@kit.ArkGraphics2D'
import { UIContext } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0002
const TAG = 'DisplaySyncTypewriter'

// ── StreamFlusher 接口（chatcube utils/ThrottleUtil.ets L15-19 随迁；语义注释照搬）──
// 流式 emit 抽象. ThrottleUtil 与 V2 的 TypewriterFlusher 都实现此接口,
// 这样业务层可以在不改业务代码的情况下在两种节流策略之间切换.
// 语义:
//   throttle(chunk, cb): 喂入一段流式增量, 由实现决定何时调用 cb 推动 UI
//   flush(cb):           立即吐完所有积压并通过 cb 一次性回传
//   reset():             清空积压, 释放定时器/帧资源
export interface StreamFlusher {
  throttle(content: string, callback: (content: string) => void): void
  flush(callback: (content: string) => void): void
  reset(): void
}

// 帧同步打字机配置. 取值思路:
//   expectedFps = 30 大致符合人眼"匀速吐字"的感官; 低于 24 体感卡顿, 高于 60 帧间出字过快反而看不清
//   min = 24 / max = 60 给系统可变帧率留余地, 低端机或后台时下调
//   punctuationPauseFrames = 1 表示句末标点后跳过下一帧再继续出字, 产生"微在"节奏
export interface TypewriterConfig {
  expectedFps: number
  minFps: number
  maxFps: number
  punctuationPauseFrames: number
}

const DEFAULT_CONFIG: TypewriterConfig = {
  expectedFps: 30,
  minFps: 24,
  maxFps: 60,
  punctuationPauseFrames: 1
}

const PUNCTUATION_CHARS: string = '.!?。!?,，;；:：'

function resolveStepForBacklog(bufferLength: number): number {
  if (bufferLength <= 60) {
    return 1
  }
  if (bufferLength <= 200) {
    return 2
  }
  // 超过 200 字符积压时按 ceil(len/30) 倍速追赶,
  // 保证 ~1 秒内能把积压压下去, 避免延迟越来越大
  return Math.ceil(bufferLength / 30)
}

function endsWithPunctuation(chunk: string): boolean {
  if (chunk.length === 0) {
    return false
  }
  const last = chunk.charAt(chunk.length - 1)
  return PUNCTUATION_CHARS.indexOf(last) >= 0
}

/**
 * 基于 displaySync 帧同步的流式打字机。
 *
 * 与 ThrottleUtil 区别:
 *   ThrottleUtil 走固定时间片批量 emit, 优先保证长文本 Markdown 的解析/布局成本可控
 *   DisplaySyncTypewriter 跟 VSync 对齐, 按帧匀速吐字, 句末标点上有微停
 *
 * 使用约束 (违反任何一条都会失效或资源泄漏):
 *   1. 每个 streamChatRequest 必须 new 一个独立实例, 不可单例 (并发流式会错位拼字符)
 *   2. start() 必须包在 UIContext.runScopedTask 内, 否则 frame 回调可能在非 UI 上下文丢失
 *   3. dispose() 必须在请求 complete / cancel 路径被调用, 否则后台仍按 30Hz 烧帧
 *   4. flushImmediate() 用于流式结束时同步推出剩余字符, 保证 DB 拿到完整内容
 *   5. frame 回调内严禁做正则解析 / split('\n') 等重计算, 只做 substring + emit
 */
export class DisplaySyncTypewriter {
  private uiContext: UIContext
  private config: TypewriterConfig
  private displaySyncInstance: displaySync.DisplaySync | null = null
  private buffer: string = ''
  private emitListener: ((chunk: string) => void) | null = null
  private isRunning: boolean = false
  private skipFramesLeft: number = 0
  private isDisposed: boolean = false
  private boundFrameCallback: ((info: displaySync.IntervalInfo) => void) | null = null

  constructor(uiContext: UIContext, config?: Partial<TypewriterConfig>) {
    this.uiContext = uiContext
    this.config = {
      expectedFps: config?.expectedFps ?? DEFAULT_CONFIG.expectedFps,
      minFps: config?.minFps ?? DEFAULT_CONFIG.minFps,
      maxFps: config?.maxFps ?? DEFAULT_CONFIG.maxFps,
      punctuationPauseFrames: config?.punctuationPauseFrames ?? DEFAULT_CONFIG.punctuationPauseFrames
    }
  }

  setEmitListener(listener: (chunk: string) => void): void {
    this.emitListener = listener
  }

  feed(chunk: string): void {
    if (this.isDisposed || chunk === '') {
      return
    }
    this.buffer += chunk
    this.ensureRunning()
  }

  /**
   * 返回 buffer 中剩余所有字符并清空; 不会触发 emitListener。
   * 用法: 流式结束时调用方拿到返回值, 自行决定是否一次性塞给 onAIMessageUpdated 以便 DB 保存完整内容。
   */
  flushImmediate(): string {
    const remaining = this.buffer
    this.buffer = ''
    this.skipFramesLeft = 0
    this.stopInstance()
    return remaining
  }

  dispose(): void {
    if (this.isDisposed) {
      return
    }
    this.isDisposed = true
    this.buffer = ''
    this.skipFramesLeft = 0
    this.stopInstance()
    if (this.displaySyncInstance !== null && this.boundFrameCallback !== null) {
      try {
        this.displaySyncInstance.off('frame', this.boundFrameCallback)
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'off frame failed: %{public}s', JSON.stringify(error))
      }
    }
    this.displaySyncInstance = null
    this.boundFrameCallback = null
    this.emitListener = null
  }

  private ensureRunning(): void {
    if (this.isDisposed || this.isRunning) {
      return
    }
    if (this.displaySyncInstance === null) {
      try {
        this.displaySyncInstance = displaySync.create()
        const range: ExpectedFrameRateRange = {
          expected: this.config.expectedFps,
          min: this.config.minFps,
          max: this.config.maxFps
        }
        this.displaySyncInstance.setExpectedFrameRateRange(range)
        this.boundFrameCallback = (info: displaySync.IntervalInfo): void => {
          this.onFrame(info)
        }
        this.displaySyncInstance.on('frame', this.boundFrameCallback)
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'displaySync init failed: %{public}s', JSON.stringify(error))
        this.displaySyncInstance = null
        this.boundFrameCallback = null
        // 兜底: 直接同步把整个 buffer 推给监听器, 退化成"无打字效果"也比无响应强
        this.drainBufferSync()
        return
      }
    }
    const instance = this.displaySyncInstance
    if (instance === null) {
      return
    }
    try {
      this.uiContext.runScopedTask((): void => {
        instance.start()
      })
      this.isRunning = true
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'displaySync start failed: %{public}s', JSON.stringify(error))
      this.drainBufferSync()
    }
  }

  private stopInstance(): void {
    if (!this.isRunning) {
      return
    }
    this.isRunning = false
    if (this.displaySyncInstance === null) {
      return
    }
    try {
      this.displaySyncInstance.stop()
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'displaySync stop failed: %{public}s', JSON.stringify(error))
    }
  }

  private drainBufferSync(): void {
    if (this.buffer === '' || this.emitListener === null) {
      this.buffer = ''
      return
    }
    const remaining = this.buffer
    this.buffer = ''
    this.emitListener(remaining)
  }

  private onFrame(_info: displaySync.IntervalInfo): void {
    if (this.isDisposed) {
      return
    }
    if (this.skipFramesLeft > 0) {
      this.skipFramesLeft -= 1
      return
    }
    if (this.buffer === '') {
      // 不再因空 buffer 主动 stopInstance: 流式块之间常有几十毫秒空档,
      // displaySync.start() 在 stop() 之后未必能可靠重启 — 实测会出现"卡在首字符"
      // (chunk1 出字后 buffer 空 → stop, chunk2 feed 后 start 静默失败, 后续帧不触发).
      // 生命周期由 dispose() / flushImmediate() / reset 统一终止, 空帧只是空跑一次回调.
      return
    }
    const step = resolveStepForBacklog(this.buffer.length)
    const chunk = this.buffer.substring(0, step)
    this.buffer = this.buffer.substring(step)
    const listener = this.emitListener
    if (listener !== null) {
      listener(chunk)
    }
    if (this.config.punctuationPauseFrames > 0 && endsWithPunctuation(chunk)) {
      this.skipFramesLeft = this.config.punctuationPauseFrames
    }
  }
}

/**
 * 把 DisplaySyncTypewriter 适配成 StreamFlusher 接口, 这样业务层可以
 * 在不改业务调用 (throttle/flush/reset) 的前提下在 V1 ThrottleUtil 与 V2 typewriter 之间切换.
 *
 * 用法约束跟 DisplaySyncTypewriter 相同:
 *   - 每次 streamChatRequest 新建一个 TypewriterFlusher 实例
 *   - reset() 等价 dispose, 调用后实例不可复用
 *   - 结束路径先调 flush(cb) 推出剩余字符, 再调 reset() 释放 displaySync
 */
export class TypewriterFlusher implements StreamFlusher {
  private typewriter: DisplaySyncTypewriter
  // 流式中业务层每次调用 throttle(chunk, cb) 都会替换最新 cb;
  // typewriter 内部的固定 listener 调用时取 latestCallback, 因此 cb 始终是"当前请求的最新业务回调"
  private latestCallback: ((content: string) => void) | null = null
  private isDisposed: boolean = false

  constructor(uiContext: UIContext, config?: Partial<TypewriterConfig>) {
    this.typewriter = new DisplaySyncTypewriter(uiContext, config)
    this.typewriter.setEmitListener((chunk: string): void => {
      if (this.latestCallback !== null) {
        this.latestCallback(chunk)
      }
    })
  }

  throttle(content: string, callback: (content: string) => void): void {
    if (this.isDisposed) {
      return
    }
    this.latestCallback = callback
    this.typewriter.feed(content)
  }

  flush(callback: (content: string) => void): void {
    if (this.isDisposed) {
      return
    }
    const remaining = this.typewriter.flushImmediate()
    if (remaining !== '') {
      callback(remaining)
    }
  }

  reset(): void {
    if (this.isDisposed) {
      return
    }
    this.isDisposed = true
    this.latestCallback = null
    this.typewriter.dispose()
  }
}
