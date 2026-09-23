// 网络层失败自动重试域（2026-09-22 聊天自动重试任务书新建）。域定义一句话：聊天主链在
// **请求因网络原因失败、且本流尚无任何内容产出**时，按 2/4/8 秒退避重发同一请求（同 key、
// 不推进 Key 池轮次位），最多 3 次；重试期间把次数状态行写进助手气泡运行时字段，用户随时
// 可停止——本域只做三件（判据 / 退避调度 / 状态写入），不含任何传输与落库。
//
// ★ 与 ChatRetryCtrl（消息重新生成域）的分工：ChatRetryCtrl = **用户主导的整轮重生成**——
// 清空重答、旧答案保进 variants、工具轮整轮作废、渲染纪元推进、落库保底，牵动消息集合；
// 本域 = **网络自愈**——请求尚未产出任何内容，屏幕上与库里都只有那个空的占位气泡，故
// 只需重发，不动消息集合。两者唯一致命差异在此：本域**零产出**语义天然不产生内容替换，
// 因此可以全程避开「重试引起消息集合变化」那一路上的四个真机坑（见 ChatRetryCtrl 头注释
// 「2026-09-20 真机验收修复笔」四现象）。
//
// ★★ 红线（禁碰，越线即重蹈四坑）：
//  · 不 push notice 行（错误行只在重试耗尽后的最终失败路径由宿主 failRound 落一次）；
//  · 不动库行 / 不动 variants / 不动 renderEpoch / 不新建消息行——状态只走纯运行时字段；
//  · 不另造请求链：重发一律经宿主 attemptCurrent()（= ChatKeyRoundCtrl 的既有咽喉点，
//    它承诺「不动占位气泡与库行」）——本件内**零** stream.start / 零 createStreamFor /
//    零 createChatStream / 零 new *ChatStream。
//
// ★ 依赖方向（防循环依赖）：本件只持 ChatAutoRetryHost 接口，**禁 import ChatSendCtrl**
//（宿主 implements 本接口回接，照 ChatKeyRoundCtrl / ChatRetryCtrl 两先例的姿势）。
//
// ★ 判据（四条件全真，缺一不重试；来源 = 任务书 D2）：
//  ① status === -1（**传输层失败**——连接失败与手动停止两路；★ 2026-09-22 自检轮收窄语义：
//     流中错误帧走专属哨兵 STREAM_ERROR_STATUS(-2)，不再冒充 -1，故本条件恰等于「网络原因」）；
//  ② 本流零产出（onError 第三参 sawContent === false——不能拿 sawValidFrame 冒充：后者
//     含空保活帧与纯 usage 帧，会让「一个字都没显示却不重试」变成用户可见缺陷）；
//  ③ 非用户主动停止（-1 与「已手动停止」同码，此条不可省——abort() 入口须先调 markUserStop）；
//  ④ 开关开 && 本轮计数 < 上限 && isSending() && !isDisposed()。
// ★ 中途断流（屏幕上已有内容）**不自动重试**：上游可能已计费、本轮工具可能已执行，自动重发
// 会把副作用无提示地做第二遍——保留用户手动点底栏重试键。
//
// ★ 计数口径（任务书 D6）= **本轮共享上限**，不按 key 分别计——最坏请求数因此有界（3 支 key
// 各 1 次 + 3 次自动重试 = 6 次），防「每支 key 各试 3 次」的 12 次放大。
// ★ 开关取值在**轮首现读一次、轮内锁定**（照 CubeEngineCtrl 头注释「开关现读一次，轮内行为
// 不随开关中途切换」同口径），防中途切换产生不确定行为；故偏好页拨动自下一条消息生效。
//
// 消费方：ChatSendCtrl（onStreamError 接管判据 / abort 与 disposeSilent 取消 / finishStream
// 与两轮首复位 / onStreamDelta 首帧让位 / 最终失败文案装饰）。
//
// 沿革：2026-09-22 决明需求「rikka 有自动重试模型请求功能，闭源 cube 也有，描述是开启后网络
// 异常最多重试 3 次」——同日四家竞品（RikkaHub / Kelivo / ChatBox / Cherry Studio）源码
// 调研后立项成书（docs/任务书-聊天自动重试-20260922.md，行为参照 RikkaHub GenerationLoop 的
// awaitNetworkRetryOrThrow，参数不照搬而沿用本项目 TitleGen/MemoryGen/SuggestGen 现成的
// 2/4/8 秒三档）。

// 宿主接口：自动重试域引用的宿主编排能力（ChatSendCtrl implements，全部薄直通）
export interface ChatAutoRetryHost {
  isDisposed(): boolean;                // this.disposed（销毁闸）
  isSending(): boolean;                 // this.refs.sending()（轮次在场闸）
  isAutoRetryEnabled(): boolean;        // AppPreferences.isAutoRetryEnabled（偏好现读）
  attemptCurrent(): void;               // keyRound.attemptCurrent（同消息重发咽喉点）
  setRetryHint(text: string): void;     // 写助手气泡运行时字段（'' = 清空；消息不在则静默跳过）
}

// 退避参数（★ 与 TitleGen/MemoryGen/SuggestGen 同源同值——断言脚本对本件与 TitleGen 两处
// 常量现比，合法改一处参数即红；禁新造第三套参数）
const RETRY_BASE_SECONDS: number = 2;
// 本轮最多自动重试次数（同上，与 TitleGen.MAX_TITLE_RETRY 同值）
const AUTO_RETRY_MAX: number = 3;
// 状态行文案前缀（数字随次数原地更新，不新增行、不堆叠；不做逐秒倒计时——免漂移与额外定时器）
const RETRY_HINT_PREFIX: string = '网络异常，正在重试';

export class ChatAutoRetryCtrl {
  private host: ChatAutoRetryHost;
  // 本轮已自动重试次数（轮首与轮末复位）
  private count: number = 0;
  // 退避定时器句柄（null = 无在途；重排前必清旧 = 成对释放红线，照 ProactiveGen 同款）
  private timer: number | null = null;
  // 轮内用户主动停止标记（-1 与「已手动停止」同码，停止信号另置此——判据③）
  private userStopped: boolean = false;
  // 状态行当前是否在场（清空短路用：逐帧增量都回调清空检查，短路后零查表开销。状态行写在
  // 助手占位气泡上，而 findMessage 是线性查找——不加此闸即为每个增量帧一次全表扫描）
  private hintShown: boolean = false;

  constructor(host: ChatAutoRetryHost) {
    this.host = host;
  }

  // ── 轮次生命周期（宿主三处调用：dispatchSend 轮首 / launchRetryRound 轮首 / finishStream
  // 收尾）——计数与停止标记复位；状态行抹掉（**收尾兜底**：漏清则残留到下一轮）；在途退避
  // 一并取消（防陈旧定时器在新轮触发重发）──
  resetForRound(): void {
    this.cancelBackoff();
    this.clearHintIfShown();
    this.count = 0;
    this.userStopped = false;
  }

  // 用户主动停止（宿主 abort() 首行调用，早于任何 failRound）：置标记 + 取消在途退避。
  // 标记必须在 cancel 同拍置位——否则「停止后到的网络错误」会被判成可重试，用户点了停止
  // 却看见请求又发出去
  markUserStop(): void {
    this.userStopped = true;
    this.cancelBackoff();
  }

  // 取消在途退避定时器（abort / disposeSilent 两路成对释放点；幂等）
  cancelBackoff(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  // 判据 + 调度（宿主 onStreamError 在两分支之间委托）：true = 本流失败已被接管——退避中，
  // 宿主须置空 activeStream 引用并直接 return（**不得** failRound：notice 行与 finishStream
  // 收尾都留给最终失败）；false = 不接管，宿主按原路径 handle（换 Key 已在前一步判过）
  takeOver(status: number, sawContent: boolean): boolean {
    if (status !== -1) {
      return false; // ① 非网络层失败（HTTP 码类归 Key 池换钥或直接收尾）
    }
    if (sawContent) {
      return false; // ② 已上屏过内容 = 中途断流，不自动重试
    }
    if (this.userStopped) {
      return false; // ③ 用户已主动停止（与 -1 同码，靠标记区分）
    }
    if (!this.host.isAutoRetryEnabled() || this.count >= AUTO_RETRY_MAX) {
      return false; // ④ 开关关 / 本轮次数耗尽
    }
    if (!this.host.isSending() || this.host.isDisposed()) {
      return false; // ④ 轮次已收尾 / 页面已销毁
    }
    this.count++;
    // 退避等待 = 失败恢复型等待，与 TitleGen.sleep 同性，**不违 P1-3「零冗余等待」**——该条
    // 禁的是人为 sleep 与条件已满足时的空耗，本处等待是上游失败后的必要间隔（防连打限流）
    const delaySeconds: number = Math.pow(RETRY_BASE_SECONDS, this.count); // 2/4/8
    this.host.setRetryHint(RETRY_HINT_PREFIX + ' ' + this.count + '/' + AUTO_RETRY_MAX);
    this.hintShown = true;
    this.timer = setTimeout((): void => {
      this.timer = null;
      // 到点全守卫重查（退避窗口内用户可能已停止、页面可能已销毁、轮次可能已收尾）
      if (this.userStopped || this.host.isDisposed() || !this.host.isSending()) {
        return;
      }
      this.host.attemptCurrent();
    }, delaySeconds * 1000);
    return true;
  }

  // 最终失败文案装饰（宿主 failRound 前委托）：本轮重试过才追加后缀（句号分句，合规约①）；
  // 未重试过原样返回——其余失败路径文案零改动。数字取本轮实际次数（不写死上限）
  decorateFinalMessage(message: string): string {
    if (this.count === 0) {
      return message;
    }
    return message + '。已自动重试 ' + this.count + ' 次';
  }

  // 状态行让位（宿主 onStreamDelta 每帧调用）：本轮曾有状态行在场才写清空——有内容上屏即
  // 让位，状态行不与被重试后正常开头的正文并存。短路见 hintShown 字段注释
  clearHintIfShown(): void {
    if (!this.hintShown) {
      return;
    }
    this.hintShown = false;
    this.host.setRetryHint('');
  }
}
