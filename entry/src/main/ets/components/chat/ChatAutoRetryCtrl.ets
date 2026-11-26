// 网络层失败自动重试域。域定义：聊天主链在**请求因传输层失败（-1）、服务端 5xx 或瞬态文案
// 命中、且本流尚无任何内容产出**时，按 2/4/8 秒退避重发同一请求（同 key、不推进 Key 池
// 轮次位），最多 3 次；重试期间把次数状态行写进助手气泡运行时字段，用户随时可停止——本域
// 只做三件（判据 / 退避调度 / 状态写入），不含任何传输与落库。
// ★ 与 ChatRetryCtrl（消息重新生成域）的分工：ChatRetryCtrl = 用户主导的整轮重生成（清空
// 重答、旧答案保进 variants、工具轮整轮作废、渲染纪元推进、落库保底），牵动消息集合；本域
// = **网络自愈**——请求尚未产出任何内容，屏幕上与库里只有空占位气泡，只需重发不动消息集合，
// 全程避开「重试引起消息集合变化」路上的四个真机坑（见 ChatRetryCtrl 头注释）。
// ★★ 红线（禁碰，越线即重蹈四坑）：
//  · 不 push notice 行（错误行只在重试耗尽后的最终失败路径由宿主 failRound 落一次）；
//  · 不动库行 / 不动 variants / 不动正文渲染身份（不换绑定） / 不新建消息行——状态只走
//    纯运行时字段；
//  · 不另造请求链：重发一律经宿主 attemptCurrent()（= ChatKeyRoundCtrl 既有咽喉点，它承诺
//    「不动占位气泡与库行」）——本件内**零** stream.start / 零 createStreamFor / 零
//    createChatStream / 零 new *ChatStream。
// ★ 依赖方向（防循环）：本件只持 ChatAutoRetryHost 接口，禁 import ChatSendCtrl（宿主
// implements 回接，照 ChatKeyRoundCtrl / ChatRetryCtrl 先例）。
// ★ 判据（四条件全真，缺一不重试）：
//  ① status === -1（流中错误帧走专属哨兵 STREAM_ERROR_STATUS(-2) 不冒充 -1，-1 恰等于传输层
//     失败）、配置状态码集（默认 5xx 面）或瞬态文案词表命中（overloaded / 限流 / 稍后再试类
//     即使未列码也接管；停词表先判否决）；
//  ② 本流零产出（onError 第三参 sawContent === false——不能拿 sawValidFrame 冒充：后者含空
//     保活帧与纯 usage 帧，「一个字都没显示却不重试」会是用户可见缺陷）；
//  ③ 非用户主动停止（-1 与「已手动停止」同码，此条不可省——abort() 须先调 markUserStop）；
//  ④ 开关开 && 本轮计数 < 上限 && isSending() && !isDisposed()。
// ★ 中途断流（屏幕上已有内容）**不自动重试**：上游可能已计费、本轮工具可能已执行，自动重发
// 会把副作用无提示做第二遍——保留用户手动点底栏重试键。
// ★ 计数口径 = **本轮共享上限**，不按 key 分别计——最坏请求数有界（3 支 key 各 1 次 + 3 次
// 重试 = 6 次），防「每支 key 各试 3 次」的 12 次放大。★ 开关取值轮首现读一次、轮内锁定
//（照流式引擎开关口径），偏好页拨动自下一条消息生效。
// ★★ U3a 配置化：判据参数（状态码集合 / 重试 / 停止两张词表 / 退避四参数）自编译期常量改
// 配置读——经宿主读口 autoRetryCfg 每轮首次接管时读一次并锁定（宿主未接读口回本件兜底常量
// = 改造前值，行为逐字节等价）。配置单源 = common/AppPreferencesRetry（总开关仍是旧布尔键
// prefAutoRetry 经 host.isAutoRetryEnabled 单一真源）。判据四条件序不动；Key 池换钥面
// [401,403,429]（ChatStreamFlowCtrl，先于本域判）维持独立链不并入——配置不得劫持换钥链。
// 消费方：ChatSendCtrl（abort 与 disposeSilent 取消 / 两轮首复位）；onStreamError 接管判据 /
// finishStream / onStreamDelta 首帧让位 / 最终失败文案装饰各消费点在 ChatStreamFlowCtrl。
// 沿革：决明需求「开启后网络异常最多重试 3 次」（参照 RikkaHub GenerationLoop，参数沿用
// 本项目 TitleGen/MemoryGen/SuggestGen 现成的 2/4/8 秒三档）。

// 配置结构类型（类型单源在 common/AppPreferencesRetry——本件仅类型引用，运行时数据经宿主
// 读口到达）
import { AutoRetryCfg } from '../../common/AppPreferencesRetry';

// 宿主接口（ChatSendCtrl implements；实现位在 ChatHostDelegates）
export interface ChatAutoRetryHost {
  isDisposed(): boolean;                // this.disposed（销毁闸）
  isSending(): boolean;                 // this.refs.sending()（轮次在场闸）
  isAutoRetryEnabled(): boolean;        // AppPreferences.isAutoRetryEnabled（偏好现读——总开关旧布尔键单一真源）
  attemptCurrent(): void;               // keyRound.attemptCurrent（同消息重发咽喉点）
  setRetryHint(text: string): void;     // 写助手气泡运行时字段（'' = 清空；消息不在则静默跳过）
  nextAttempt(): void;                  // attempt 换代（自动重试重发 = 新 attempt，I5；2026-09-26 笔1 S2）
  // 配置读口（可选能力：生产宿主恒实现；未提供的宿主〔直跑夹具等〕回本件兜底常量）
  autoRetryCfg?(): AutoRetryCfg;
}

// 退避参数与判据面兜底常量（兼两职：①与 TitleGen/MemoryGen/SuggestGen 同源同值的关系钉
// 锚点——断言脚本对本件与 TitleGen 两处常量现比，合法改一处参数即红；②宿主未接读口时的
// 兜底底版——值与 AppPreferencesRetry 解析缺省逐字段等值，同源由 assert-retry-domain 关系
// 钉守；禁新造第三套参数）
const RETRY_BASE_SECONDS: number = 2;
// 退避倍率（第 n 次延迟 = RETRY_BASE_SECONDS×1000 × 倍率^(n-1)，默认 2/4/8 秒）
const RETRY_DELAY_MULTIPLIER: number = 2;
// 本轮最多自动重试次数（同上，与 TitleGen.MAX_TITLE_RETRY 同值）
const AUTO_RETRY_MAX: number = 3;
// 可自动重试的服务端 5xx 集合（与传输层 -1 同享退避重试）。来源 = Kelivo 集合裁剪——
// 408/425 是请求侧超时语义（本工程传输层超时以 -1 到达，不产 HTTP 408/425）、429 归 Key 池
// 分流先位（换钥优先于原地重试），均不入面；529 = 厂商过载事实标准
const RETRYABLE_5XX: number[] = [500, 502, 503, 504, 529];
// 瞬态文案词表（收敛自 Kelivo，U3a 起用户可配——本表退为兜底底版）：命中即越过状态码面
// 接管，明显瞬态的未列码失败不再漏重试；英文词大小写不敏感（命中前 toLowerCase）
const RETRY_TRANSIENT_WORDS: string[] = ['并发', '稍后', '重试', '访问量过大', '繁忙', '限流',
  'rate limit', 'too many requests', 'overloaded', 'try again', 'timeout', '超时'];
// 停词表（收敛自 Kelivo）：**先于瞬态词与状态码两族判**——「余额不足」类确定性失败即使撞上
// 瞬态词或 5xx 也不重发
const RETRY_STOP_WORDS: string[] = ['余额', '不足', '额度', '欠费', 'balance', 'insufficient',
  'quota', 'invalid api key', 'unauthorized', 'permission', '未实名'];

// 宿主未接配置读口时的兜底配置（= 改造前编译期常量行为，逐字段等值）
const AUTO_RETRY_CFG_FALLBACK: AutoRetryCfg = {
  maxRetries: AUTO_RETRY_MAX,
  initialDelayMs: RETRY_BASE_SECONDS * 1000,
  multiplier: RETRY_DELAY_MULTIPLIER,
  maxDelayMs: 8000, // 单次等待上限（改造前第 3 档 2^3 秒 = 8 秒；独立上限值，不从上式推导）
  retryStatusCodes: RETRYABLE_5XX,
  retryKeywords: RETRY_TRANSIENT_WORDS,
  stopKeywords: RETRY_STOP_WORDS
};

// 词表命中判定（逐词 includes，空串不命中；来源 = 本轮锁定配置或兜底）
function hitWordList(message: string, words: string[]): boolean {
  if (message === '') {
    return false;
  }
  const lower: string = message.toLowerCase();
  return words.some((word: string): boolean => lower.includes(word));
}

// 状态行文案前缀（数字随次数原地更新不堆叠；不做逐秒倒计时免额外定时器；前缀中性覆盖
// 传输层与服务端两族失败）
const RETRY_HINT_PREFIX: string = '请求失败，正在重试';

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
  // 本轮配置快照（首次接管读一次并锁定，resetForRound 清缓存；null = 尚未锁定）
  private cfgLocked: AutoRetryCfg | null = null;

  constructor(host: ChatAutoRetryHost) {
    this.host = host;
  }

  // 配置快照（惰性取：宿主接读口用其值，未接〔直跑夹具等〕回兜底常量）
  private retryCfg(): AutoRetryCfg {
    if (this.cfgLocked === null) {
      this.cfgLocked = this.host.autoRetryCfg !== undefined ?
        this.host.autoRetryCfg() : AUTO_RETRY_CFG_FALLBACK;
    }
    return this.cfgLocked;
  }

  // ── 轮次生命周期（宿主三处调用：dispatchSend 轮首 / launchRetryRound 轮首 / finishStream
  // 收尾）——计数与停止标记复位；状态行抹掉（收尾兜底，漏清残留到下一轮）；在途退避一并
  // 取消（防陈旧定时器新轮触发重发）──
  resetForRound(): void {
    this.cancelBackoff();
    this.clearHintIfShown();
    this.count = 0;
    this.userStopped = false;
    this.cfgLocked = null;
  }

  // 用户主动停止（宿主 abort() 首行调用，早于任何 failRound）：置标记 + 取消在途退避。
  // 标记须与 cancel 同拍置位——否则停止后到的网络错误被判成可重试，用户点了停止却见请求
  // 又发出去
  markUserStop(): void {
    this.userStopped = true;
    this.cancelBackoff();
  }

  // 轮内停止标记只读口：宿主 onStreamError 末端 failRound 的 notice 分类用——停止轮须传
  // 0 无码哨值（禁按 -1 挂跳网络设置页动作）；标记私有，写点唯一 = markUserStop
  isUserStopped(): boolean {
    return this.userStopped;
  }

  // 取消在途退避定时器（abort / disposeSilent 两路成对释放点；幂等）
  cancelBackoff(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  // 判据 + 调度（宿主 onStreamError 在两分支之间委托）：true = 已接管（退避中）——宿主须
  // 置空 activeStream 引用并直接 return（**不得** failRound：notice 行与 finishStream 收尾留
  // 给最终失败）；false = 不接管，宿主按原路径 handle（换 Key 已在前一步判过）。判据族 =
  // 状态码族（-1 传输层 + 配置状态码集）+ 瞬态文案族（词表命中即越过状态码面）；message
  // 省缺 = '' = 文案面不命中
  takeOver(status: number, sawContent: boolean, message: string = ''): boolean {
    // 判据参数自本轮锁定配置取（首次接管读一次，轮内不漂移）
    const cfg: AutoRetryCfg = this.retryCfg();
    // 停词否决（先于两族判据——「余额不足」类确定性失败即使撞上瞬态词或 5xx 也不重发）
    if (hitWordList(message, cfg.stopKeywords)) {
      return false;
    }
    if (status !== -1 && !cfg.retryStatusCodes.includes(status) &&
      !hitWordList(message, cfg.retryKeywords)) {
      return false; // ① 非重试面失败（状态码族与瞬态文案族两族都不命中；其余 HTTP 码类归 Key 池换钥或直接收尾）
    }
    if (sawContent) {
      return false; // ② 已上屏过内容 = 中途断流，不自动重试
    }
    if (this.userStopped) {
      return false; // ③ 用户已主动停止（与 -1 同码，靠标记区分）
    }
    if (!this.host.isAutoRetryEnabled() || this.count >= cfg.maxRetries) {
      return false; // ④ 开关关 / 本轮次数耗尽
    }
    if (!this.host.isSending() || this.host.isDisposed()) {
      return false; // ④ 轮次已收尾 / 页面已销毁
    }
    this.count++;
    // 退避等待 = 失败恢复型等待（P1-3 禁的是人为 sleep 与空耗，此处是上游失败后的必要间隔
    // 防连打限流，不违）。第 n 次延迟 = initial × multiplier^(n-1) 封顶 maxDelay（默认 2/4/8 秒）
    const delayMs: number = Math.min(cfg.initialDelayMs *
      Math.pow(cfg.multiplier, this.count - 1), cfg.maxDelayMs);
    this.host.setRetryHint(RETRY_HINT_PREFIX + ' ' + this.count + '/' + cfg.maxRetries);
    this.hintShown = true;
    this.timer = setTimeout((): void => {
      this.timer = null;
      // 到点全守卫重查（退避窗口内用户可能已停止、页面可能已销毁、轮次可能已收尾）
      if (this.userStopped || this.host.isDisposed() || !this.host.isSending()) {
        return;
      }
      this.host.nextAttempt(); // 自动重试重发 = 换 attempt
      this.host.attemptCurrent();
    }, delayMs);
    return true;
  }

  // 最终失败文案装饰（宿主 failRound 前委托）：本轮重试过才追加后缀（句号分句）；未重试或
  // 用户已停止原样返回——停止轮的「已手动停止」是独立陈述，再拼重试次数会把两种性质缝进
  // 一句。数字取本轮实际次数
  decorateFinalMessage(message: string): string {
    if (this.count === 0 || this.userStopped) {
      return message;
    }
    return message + '。已自动重试 ' + this.count + ' 次';
  }

  // 状态行让位（宿主 onStreamDelta 每帧调用）：有内容上屏即让位——状态行不与正文并存；
  // 短路见 hintShown 注释
  clearHintIfShown(): void {
    if (!this.hintShown) {
      return;
    }
    this.hintShown = false;
    this.host.setRetryHint('');
  }
}
