// HTTP 工具域·长任务句柄表域。职责一句话 = 「后台 HTTP 请求的受理登记、终态落定与结果
// 暂存」。零 import 工具域（坑50）；全部导出供 assert-tool-domain 直跑副本执行级验证。
// · 状态机六值：running / completed / failed / timed_out / cancelled / lost。取消不另设
//   模型面入口——cancelled 由传输层掐断链写入（用户停止键 → httpAbortRun → destroy →
//   后台链按取消归类收口），判据是状态字段而非文本哨兵（每条带显式发起方字段
//   initiatorRunId）。
// · 有界三件（宪法「数据有界」）：表条数上限 32（表满先清过期、仍满拒新任务——拒绝比
//   静默淘汰诚实：淘汰会让已受理的 task_id 变成「查无此任务」）；终态条目 TTL 10 分钟
//  （过期即清，模型查询得「不存在或已过期」）；结果串 ≤8192（后台链复用同步回执
//   fitHttpResult 收敛通道，本表闸兜底防异常串入表）。
// · lost 语义（「重启后仍 running 的标 lost」）：表是进程内存态，重启后 running 任务的
//   真实下场是「连接已死、结果不可恢复」——持久化镜像只登记 running 条目（发起时写、
//   终态即删，镜像恒极小），下次进程启动恢复镜像时把其中全部条目标 lost：模型查询得到
//   明确的「应用重启导致任务中断」而非「不存在」，不假装在跑也不假装完成。镜像键 =
//   AppPreferencesHttp.PREF_HTTP_TASKS_KEY，读写封装单源 AppPreferencesHttp，本件不直接
//   摸 AppStorage（保持「可直跑纯逻辑」边界，镜像串进出都走调用方）。
// · 取结果两形态：非阻塞快照（snapshot——running 回 not_ready 面 / 终态回完整结果）与
//   有界等待（调用方轮询 snapshot，超时不是错误、返回 running 快照）——等待循环在执行器，
//   本件只出快照。超时兜底（timed_out）：后台链的 kit readTimeout 以任务上限为值、正常
//   路径必先触发；表侧 snapshot 惰性收口（超上限 + 30 秒宽限仍 running → 标 timed_out）
//   防 kit 超时万一未达（传输侧另一半 = httpAbortRun destroy 链）。

// 状态六值（字面量单源；模型可见——查询回执的 status 字段值）
export const HTTP_TASK_STATUS_RUNNING: string = 'running';
export const HTTP_TASK_STATUS_COMPLETED: string = 'completed';
export const HTTP_TASK_STATUS_FAILED: string = 'failed';
export const HTTP_TASK_STATUS_TIMED_OUT: string = 'timed_out';
export const HTTP_TASK_STATUS_CANCELLED: string = 'cancelled';
export const HTTP_TASK_STATUS_LOST: string = 'lost';

// 表条数上限：并发后台请求的现实量级是个位数，32 已富余；上限的意义是防无界
export const HTTP_TASK_MAX_ENTRIES: number = 32;
// 终态条目保留时长（供模型事后查询）：10 分钟 = 一轮对话内可回查的量级
export const HTTP_TASK_TTL_MS: number = 600000;
// 任务总时长上限（后台链的 readTimeout 值与 timed_out 判据同源）：未传默认 5 分钟，钳制
// 上限 10 分钟
export const HTTP_TASK_TIMEOUT_MS_DEFAULT: number = 300000;
export const HTTP_TASK_TIMEOUT_MS_MAX: number = 600000;
// timed_out 惰性收口宽限（kit readTimeout 正常必先触发，30 秒宽限只兜「万一未达」）
const HTTP_TASK_TIMEOUT_GRACE_MS: number = 30000;
// 有界等待上限（查询的 wait_ms 钳制顶；「超时不是错误」——到时返回 running 快照）
export const HTTP_TASK_WAIT_MS_MAX: number = 10000;

// 任务总时长上限解析（照 resolveHttpTimeoutMs 钳制钉先例）：未传 / 非有限值 = 默认 5 分钟；
// 否则 clamp(传值, 5 秒, 10 分钟)。上限值同时是后台链的 kit readTimeout——kit 超时先行，
// 表侧 timed_out 惰性收口只兜「万一未达」
export function resolveTaskTimeoutMs(requestedMs: number): number {
  const wanted: number = Number.isFinite(requestedMs) ? requestedMs : 0;
  if (wanted <= 0) {
    return HTTP_TASK_TIMEOUT_MS_DEFAULT;
  }
  return Math.max(Math.min(wanted, HTTP_TASK_TIMEOUT_MS_MAX), 5000);
}

// 单条记录。initiatorRunId = 显式发起方字段（取消归类按状态字段判，禁从 endReason 文本
// 反推；runId 同时是 httpAbortRun 定向掐断的匹配键，掐断命中即 cancelled）。
// conversationId = ★ 决明拍板：会话维度登记——发起轮结束后新轮停止键经
// runningRunIdsForConversation 连带取消本会话仍在跑的后台任务（发起轮 runId 已不在途、
// 按 run 匹配不到是原缺口）；镜像不带本字段（重启恢复条目一律标 lost，会话归属随真实
// 请求一并失效）
export interface HttpTaskRecord {
  taskId: string;
  status: string;
  startedAtMs: number;
  endedAtMs: number; // 0 = 未终态
  endReason: string; // 终止原因（人读：错误句 / '任务超时' / '用户取消' / '应用重启'）
  initiatorRunId: string;
  conversationId: string;
  timeoutAtMs: number; // 任务总时长上限时刻（startedAtMs + timeoutMs）
  resultJson: string; // 终态完整回执（'' = 无结果——running / lost）
}

// 持久化镜像条目（只登记 running 所需最小字段——终态即删，镜像恒极小）
export interface HttpTaskMirrorEntry {
  taskId: string;
  runId: string;
  startedAtMs: number;
  timeoutAtMs: number;
}

// 句柄表（进程内单例由消费件惰性构造——照 hostGate() 工厂先例，模块顶层不 new）
export class HttpTaskTable {
  private entries: Map<string, HttpTaskRecord> = new Map<string, HttpTaskRecord>();

  // 启动恢复（表工厂首次构造时调用一次）：镜像串里的条目 = 上个进程死时仍在 running 的
  // 任务，一律标 lost（endedAtMs 取当刻、原因「应用重启」、无结果）。脏 JSON / 非法条目
  // 剔除不抛错（偏好键宁默认不炸链）。返回恢复条数（诊断用，主链不消费）
  restore(mirrorJson: string, nowMs: number): number {
    if (mirrorJson.trim() === '') {
      return 0;
    }
    let restored: number = 0;
    try {
      const parsed: Object = JSON.parse(mirrorJson) as Object;
      if (!Array.isArray(parsed)) {
        return 0;
      }
      for (const item of parsed as Object[]) {
        if (typeof item !== 'object' || item === null || Array.isArray(item)) {
          continue;
        }
        const rec = item as Record<string, Object>;
        const taskId: Object = rec['taskId'];
        const runId: Object = rec['runId'];
        const startedAt: Object = rec['startedAtMs'];
        const timeoutAt: Object = rec['timeoutAtMs'];
        if (typeof taskId !== 'string' || taskId === '' ||
          typeof runId !== 'string' || typeof startedAt !== 'number' ||
          typeof timeoutAt !== 'number') {
          continue;
        }
        const lostRec: HttpTaskRecord = {
          taskId: taskId, status: HTTP_TASK_STATUS_LOST,
          startedAtMs: startedAt, endedAtMs: nowMs,
          endReason: '应用重启导致任务中断', initiatorRunId: runId,
          conversationId: '', timeoutAtMs: timeoutAt, resultJson: ''
        };
        this.entries.set(taskId, lostRec);
        restored++;
      }
    } catch (e) {
      return restored;
    }
    return restored;
  }

  // 受理登记：表满先清过期，仍满回 false（调用方回「后台任务已达上限」中文回执——拒绝
  // 而非静默淘汰，见文件头）。conversationId = 发起会话（连带取消的查询维度）
  register(taskId: string, runId: string, timeoutMs: number, nowMs: number,
    conversationId: string): boolean {
    this.sweepExpired(nowMs);
    if (this.entries.size >= HTTP_TASK_MAX_ENTRIES) {
      return false;
    }
    const rec: HttpTaskRecord = {
      taskId: taskId, status: HTTP_TASK_STATUS_RUNNING,
      startedAtMs: nowMs, endedAtMs: 0, endReason: '',
      initiatorRunId: runId, conversationId: conversationId,
      timeoutAtMs: nowMs + timeoutMs, resultJson: ''
    };
    this.entries.set(taskId, rec);
    return true;
  }

  // 终态落定（后台执行链收尾时调用；未知 taskId 零动作——表被清过时后台链迟到收尾不该崩）
  finish(taskId: string, status: string, resultJson: string, reason: string, nowMs: number): void {
    const rec: HttpTaskRecord | undefined = this.entries.get(taskId);
    if (rec === undefined || rec.status !== HTTP_TASK_STATUS_RUNNING) {
      return;
    }
    rec.status = status;
    rec.endedAtMs = nowMs;
    rec.endReason = reason;
    rec.resultJson = resultJson.length > 8192 ? resultJson.substring(0, 8192) : resultJson;
  }

  // 快照（取结果两形态的读点）：先惰性收口 timed_out（超上限 + 宽限仍 running），再查
  // TTL（终态过期即清，查无）
  snapshot(taskId: string, nowMs: number): HttpTaskRecord | undefined {
    const rec: HttpTaskRecord | undefined = this.entries.get(taskId);
    if (rec === undefined) {
      return undefined;
    }
    if (rec.status === HTTP_TASK_STATUS_RUNNING && nowMs > rec.timeoutAtMs + HTTP_TASK_TIMEOUT_GRACE_MS) {
      rec.status = HTTP_TASK_STATUS_TIMED_OUT;
      rec.endedAtMs = nowMs;
      rec.endReason = '任务超时';
    }
    if (rec.status !== HTTP_TASK_STATUS_RUNNING && nowMs - rec.endedAtMs > HTTP_TASK_TTL_MS) {
      this.entries.delete(taskId);
      return undefined;
    }
    return rec;
  }

  // 清过期（register 与查询路径顺手调；终态超 TTL 即删）
  sweepExpired(nowMs: number): void {
    const dead: string[] = [];
    this.entries.forEach((rec: HttpTaskRecord, key: string): void => {
      if (rec.status !== HTTP_TASK_STATUS_RUNNING &&
        nowMs - rec.endedAtMs > HTTP_TASK_TTL_MS) {
        dead.push(key);
      }
    });
    for (const key of dead) {
      this.entries.delete(key);
    }
  }

  // ★ 决明拍板：本会话在跑后台任务的发起轮 runId 清单（去重）——停止键连带取消的查询面。
  // 发起轮结束后该 runId 已不在途但仍是在途项的匹配键（后台链登记的就是发起轮 runId），
  // 调用方逐 id 走 httpAbortRun 掐断链即可命中
  runningRunIdsForConversation(conversationId: string): string[] {
    const runIds: string[] = [];
    this.entries.forEach((rec: HttpTaskRecord): void => {
      if (rec.status === HTTP_TASK_STATUS_RUNNING && rec.conversationId === conversationId &&
        rec.initiatorRunId !== '' && !runIds.includes(rec.initiatorRunId)) {
        runIds.push(rec.initiatorRunId);
      }
    });
    return runIds;
  }

  // 持久化镜像序列化（只取 running 条目——见文件头 lost 语义；终态即从镜像消失）
  serializeRunning(): string {
    const list: HttpTaskMirrorEntry[] = [];
    this.entries.forEach((rec: HttpTaskRecord): void => {
      if (rec.status === HTTP_TASK_STATUS_RUNNING) {
        list.push({ taskId: rec.taskId, runId: rec.initiatorRunId,
          startedAtMs: rec.startedAtMs, timeoutAtMs: rec.timeoutAtMs });
      }
    });
    if (list.length === 0) {
      return '';
    }
    return JSON.stringify(list);
  }
}
