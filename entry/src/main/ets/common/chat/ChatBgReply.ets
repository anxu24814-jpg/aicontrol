// 后台回复保活与通知域：**生成寿命的后台保活与回复通知账本**——活跃 run 计数（运行时经
// syncActiveRuns 同步）、短时任务申请/取消（有活跃 run 即申请、全停即取消）、回复通知三态
//（正在回复/回复完成/回复已中断）、超时兜底回调分发（收口编排由运行时经 bindTimeoutInterrupt
// 注入，本件不 import 运行时——零环）。后台期间流继续跑零代码：短时任务生效期进程不被挂起、
// 网络连接不断，既有流回调照常执行。
// 三条红线（已拍板）：
// · 不引入长时任务、零新增权限——短时任务与通知发布都无需声明权限，module.json5 零改动；
// · 开关「后台回复提醒」（PREF_BG_REPLY_NOTIFY_KEY，缺省关）= 不申请短时任务也不发通知
//（「不承诺做不到的事」）；
// · 通知是增益非必需——授权未获/发布失败/取消失败一律静默降级（hilog 留痕不报错不阻断；
//   生成保活只依赖开关，不依赖通知授权——用户拒绝授权后台仍能续跑）。
// 内存防线成对（成对释放红线）：唯一申请点 requestKeepAlive ↔ 唯一取消点 cancelKeepAlive
//（计数归零、开关关闭、超时回调三路全经取消点）；超时回调内必取消（官方约束：不取消会被
// 系统管控并继续扣当日配额——系统在超时前约 6 秒回调）。
// 配额口径（官方《短时任务(ArkTS)》）：仅当应用在后台时计时——前台申请 → 前台跑完 → 全停
// 取消，消耗为 0；单次最大 3 分钟 / 单日默认 10 分钟 / 低电量 1 分钟。申请时机官方约束 =
// 前台或 onBackground 回调内——本件申请只可能来自：①运行态计数 0→≥1（发送时，前台用户
// 动作）；②开关打开时（设置页前台操作）。
// 前后台判据 = 本件 inBackground（EntryAbility onBackground/onForeground 两钩子维护）。
// 通知形制：固定 id 覆盖更新不重发；回到前台撤销；普通文本型（「进度条型」在本 SDK 无对应
// 普通通知类型——progress 字段属实况窗专有内容，实况窗已判不可用）。
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isBgReplyNotifyEnabled } from '../AppPreferences';

const DOMAIN: number = 0xD5A0;
const TAG: string = 'ChatBgReply';

export class ChatBgReply {
  // ── 通知域常量（类内字段 = 断言直跑提取自足——模块级常量会进提取作用域无注入位）──
  // 固定通知 id（完成/中断覆盖同一条，不撤销后重发——重发会多响一次提示音）
  private readonly notifyId: number = 1001;
  // 通知点击行为意图的拉起目标（官方 FAQ faqs-notification-14 形态：应用只能设置自己的
  // bundleName/abilityName；缺省拉起应用回到离开时页面——「点回应用查看」语义）
  private readonly bundleName: string = 'com.jueming.aicontrol.chat';
  private readonly abilityName: string = 'EntryAbility';

  // 活跃 run 计数（ChatSessionRuntime 每次 setSending 后现算全量同步——本件不做增量加减，
  // 自纠偏零漂移）
  private activeRuns: number = 0;
  // 短时任务 requestId（-1 = 不在场；唯一申请点 requestKeepAlive ↔ 唯一取消点 cancelKeepAlive）
  private requestId: number = -1;
  // 应用前后台（EntryAbility 两钩子写入；环节 B 发通知与环节 D 更通知同读本字段）
  private inBackground: boolean = false;
  // 本件发布的回复通知是否在场（发布成功置真、撤销/未授权置假——onReplySettled 与超时
  // 回调据此决定是否更新，用户在前台或通知未授权时零动作）
  private notifPublished: boolean = false;
  // 超时收口编排（运行时经 bindTimeoutInterrupt 注入——回调内逐活跃会话走 interrupted
  // 终态收口链，本件不持运行时引用）
  private timeoutHandler: (() => void) | null = null;

  // ── 运行态面（ChatSessionRuntime 同步）──

  // 活跃 run 计数同步（setSending 每笔写后现算全量）：0→≥1 申请短时任务（有活跃 run 即
  // 申请）、≥1→0 全停取消（申请/取消唯一转场点）；计数不变零动作
  syncActiveRuns(count: number): void {
    const prev: number = this.activeRuns;
    this.activeRuns = count;
    if (count > 0 && prev === 0) {
      this.requestKeepAlive();
    } else if (count === 0 && prev > 0) {
      this.cancelKeepAlive();
    }
  }

  // 超时收口编排绑定（ChatSessionRuntime 构造期注入）：系统回调内调用——逐活跃会话
  // interrupted 收口（单活跃会话 = 恰调一次，会话 A∥B 并行 = 各调一次）
  bindTimeoutInterrupt(handler: () => void): void {
    this.timeoutHandler = handler;
  }

  // ── 前后台面（EntryAbility 两钩子调用）──

  // 切后台（onBackground）：有活跃 run 才发「正在回复」——没有回复在跑不该出现任何通知
  onAppBackground(): void {
    this.inBackground = true;
    if (this.activeRuns > 0) {
      this.publishOngoing();
    }
  }

  // 回前台（onForeground）：撤销「正在回复」通知（用户已看到界面留着是干扰；完成/中断同撤）
  onAppForeground(): void {
    this.inBackground = false;
    if (this.notifPublished) {
      this.cancelNotification();
    }
  }

  // ── 回复终态面（ChatStreamFlowCtrl.finishStream 每轮收口调用一次）──

  // 回复终态更新（terminal：'done' 完成 / 'interrupted' 超时中断 / 'cancelled' 用户停止 /
  // 'failed' 失败）：仅当本件通知在场才动作（不在场 = 用户在前台或未授权，零动作零提示）；
  // done → 「回复完成」，interrupted/failed → 「回复已中断，点回应用查看」（不承诺继续），
  // cancelled → 撤销通知（用户主动停止：撤销不发完成通知）
  onReplySettled(terminal: string): void {
    if (!this.notifPublished) {
      return;
    }
    if (terminal === 'done') {
      this.updateNotification('回复完成', '点开回到应用查看');
    } else if (terminal === 'cancelled') {
      this.cancelNotification();
    } else {
      this.updateNotification('回复已中断', '点回应用查看');
    }
  }

  // ── 开关面（PrefSessionReadPage 调用）──

  // 开关切换：开 = 有活跃 run 补申请（打开时可能已有生成在跑——此刻在设置页 = 前台，
  // 申请时机合法）；关 = 立刻取消短时任务与通知（「关 = 不申请短时任务」语义即时生效）
  onSwitchChanged(enabled: boolean): void {
    if (enabled) {
      if (this.activeRuns > 0) {
        this.requestKeepAlive();
      }
    } else {
      this.cancelKeepAlive();
      if (this.notifPublished) {
        this.cancelNotification();
      }
    }
  }

  // 通知授权申请（开关打开时顺带请求——不打开就不弹窗，避免与首启隐私弹窗抢注意力；本方法
  // 只申请不解释，授权结果由调用方回落开关并提示）。授权非必需——申请失败（含用户拒绝）
  // 返 false，调用方回落为关
  requestEnableNotify(context: common.UIAbilityContext | undefined): Promise<boolean> {
    if (context === undefined) {
      return Promise.resolve(false);
    }
    return notificationManager.requestEnableNotification(context)
      .then((): boolean => true)
      .catch((e: Object): boolean => {
        hilog.warn(DOMAIN, TAG, '通知授权申请未通过：%{public}s', (e as Error).message);
        return false;
      });
  }

  // 诊断只读（断言直跑消费：申请与取消成对的可观测面）
  isKeepAliveActive(): boolean {
    return this.requestId >= 0;
  }

  // ── 短时任务（唯一申请点/唯一取消点——成对释放红线）──

  // 申请（幂等：在场即返回）：开关关 = 不申请；申请失败（配额耗尽/低电量/系统拒绝）=
  // 降级「照常发送、切后台会断」——hilog 留痕不报错不阻断
  private requestKeepAlive(): void {
    if (this.requestId >= 0) {
      return;
    }
    if (!isBgReplyNotifyEnabled()) {
      return;
    }
    try {
      const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
        '正在生成回复', (): void => {
          this.onTimeout();
        });
      this.requestId = info.requestId;
    } catch (e) {
      this.requestId = -1;
      hilog.warn(DOMAIN, TAG, '短时任务申请失败（降级照常发送，切后台会断）：%{public}s',
        (e as Error).message);
    }
  }

  // 取消（不在场零动作）：取消失败也把本地句柄归 -1（句柄已不可用，重置即降级）
  private cancelKeepAlive(): void {
    if (this.requestId < 0) {
      return;
    }
    const id: number = this.requestId;
    this.requestId = -1;
    try {
      backgroundTaskManager.cancelSuspendDelay(id);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '短时任务取消失败：%{public}s', (e as Error).message);
    }
  }

  // 超时兜底（系统在超时前约 6 秒回调）：①必取消短时任务（不取消会被系统管控继续扣配额）；
  // ②逐活跃会话 interrupted 收口（收口链 = finishStream 终态提交，本件只发指令）；③通知改
  //「回复已中断」（在场才改）；④活跃计数归零由收口链内 setSending(false) 自然完成——此处
  // 不预置，防收口未成时账目失真
  private onTimeout(): void {
    this.cancelKeepAlive();
    if (this.timeoutHandler !== null) {
      this.timeoutHandler();
    }
    if (this.notifPublished) {
      this.updateNotification('回复已中断', '点回应用查看');
    }
    hilog.info(DOMAIN, TAG, '短时任务超时回调：已取消并逐活跃会话发 interrupted 收口');
  }

  // ── 通知发布/更新/撤销（全静默降级——失败只留痕）──

  // 发布「正在回复」（仅后台切点调用）：先取点击意图（拉起应用）再发布；发布失败
  //（未授权/系统拒绝）= notifPublished 不入场，后续完成/中断零动作
  private publishOngoing(): void {
    if (!isBgReplyNotifyEnabled()) {
      return;
    }
    this.buildWantAgent().then((agent: WantAgent | null): void => {
      const request: notificationManager.NotificationRequest = {
        id: this.notifyId,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '正在回复',
            text: '回复完成后会更新这条通知'
          }
        }
      };
      if (agent !== null) {
        request.wantAgent = agent;
      }
      notificationManager.publish(request)
        .then((): void => {
          this.notifPublished = true;
        })
        .catch((e: Object): void => {
          hilog.warn(DOMAIN, TAG, '回复通知发布未生效（静默降级）：%{public}s',
            (e as Error).message);
        });
    });
  }

  // 覆盖更新（同 id；撤销后重发会多响一次提示音，禁）
  private updateNotification(title: string, text: string): void {
    const request: notificationManager.NotificationRequest = {
      id: this.notifyId,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: text }
      }
    };
    notificationManager.publish(request)
      .then((): void => {
        this.notifPublished = true;
      })
      .catch((e: Object): void => {
        this.notifPublished = false;
        hilog.warn(DOMAIN, TAG, '回复通知更新未生效（静默降级）：%{public}s',
          (e as Error).message);
      });
  }

  private cancelNotification(): void {
    this.notifPublished = false;
    notificationManager.cancel(this.notifyId)
      .catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, '回复通知撤销未生效（静默降级）：%{public}s',
          (e as Error).message);
      });
  }

  // 点击行为意图（官方 FAQ faqs-notification-14 形态：START_ABILITY + 本应用
  // bundleName/abilityName；CONSTANT_FLAG = 意图对象常驻可重复拉起）。取失败返 null——
  // 通知照发只是点击不跳（降级不停发布）
  private buildWantAgent(): Promise<WantAgent | null> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: this.bundleName, abilityName: this.abilityName }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
    };
    return wantAgent.getWantAgent(info)
      .then((agent: WantAgent): WantAgent | null => agent)
      .catch((e: Object): WantAgent | null => {
        hilog.warn(DOMAIN, TAG, '通知点击意图构造失败（通知照发、点击不跳）：%{public}s',
          (e as Error).message);
        return null;
      });
  }
}

// 进程级单例（运行时/设置页/EntryAbility 三面共享同一账本——申请与取消对称的唯一前提）
export const chatBgReply: ChatBgReply = new ChatBgReply();
