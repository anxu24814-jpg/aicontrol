// 存储域全局写串行链（14800024 真机实锤后评估定稿）：
// 一条进程级 Promise 链承载**全部数据库写事务**——任何时刻至多一个事务在飞，后到者排队，
// 「写事务 × 写操作」并发互撞（官方 d.ts 14800024 口径：同库同时只容一个写事务，写事务
// 在场时其余写操作直接报错不排队）从机制上消失，替代散在调用方的重试补救。
// · 形制先例 = ChatGraphWriteCtrl.commitChain（提交串行化，本工程已
//   运行验证的链式串行模型）；两级链正交共存：graph 域链管本会话提交取号/CAS 序（内），
//   本链管跨域写互斥（外）——graph 链节调 commitRunUnit 入本链排队，无循环等待。
// · 纯排队器零 DB 依赖：work 闭包自带句柄与事务形态（旧式 beginTransaction 三件套与新式
//   createTransaction 对象事务均入本链，两套 API 不强制统一——拍板口径「排队不挑写法」）；
//   本件禁 import 任何 store 域件（被全域引用的叶子，防环）；启动维护链（doInit 内串行
//   await）入链时链为空立即执行，无初始化顺序依赖。
// · 嵌套纪律（死锁防线，两段式）：①主防 = 静态断言钉（断言组守 beginTransaction /
//   createTransaction 只许出现在入链函数体内 + InTx 后缀族「供外层事务内直调的裸原语」
//   不入链的既有约定）；②运行时 = executing 标志命中只 hilog 留痕**不抛错**——ArkTS 单
//   线程下 work 的 await 间隙可插入完全无关的 UI 事件处理器调写函数（用户在工具执行中
//   点保存是真场景），立即抛错会误杀合法排队者；真嵌套的症状 = 链挂死 + 本留痕双信号可
//   定位。flag 语义 = 链节执行期（含 await 间隙）恒真，settle 同步复位。
// · 结果与异常由调用方各自的承诺消费（链自身吞两者继续接待下一笔——commitChain 同款）；
//   排队顺序 FIFO 无优先级，长事务（导入导出秒级）期间的排队者等待——底层本就单写连接，
//   串行链不减吞吐，把「直接报错」换成「排队等待」对调用方是纯收益。
// · label 只服务 hilog 指认（「外层 X 执行中，Y 入队」），不参与逻辑。
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'DbWriteQueue';

// 链尾（哨兵 resolve 态起步）；executing/runningLabel = 当前链节的执行标志与标签（嵌套
// 观测用，见头注释——任一时刻至多一个链节在飞，单值即可）
let chain: Promise<void> = Promise.resolve();
let executing: boolean = false;
let runningLabel: string = '';

// 全局写串行链入口：全部数据库写事务（与需要跟飞行事务错开的高频裸写）经此排队。
// work 内自管事务（旧式三件套 / 新式对象事务均可）；返回 work 的结果、原样上抛 work 的
// 异常——排队语义对调用方透明。
export function runWriteQueued<T>(label: string, work: () => Promise<T>): Promise<T> {
  if (executing) {
    hilog.error(DOMAIN, TAG,
      '嵌套嫌疑：外层写 %{public}s 执行中，%{public}s 入队（UI 间隙合法调用会正常排队；若链挂死按此留痕定位）',
      runningLabel, label);
  }
  const run: Promise<T> = chain.then(async (): Promise<T> => {
    executing = true;
    runningLabel = label;
    try {
      return await work();
    } finally {
      executing = false;
      runningLabel = '';
    }
  });
  chain = run.then((): void => undefined, (): void => undefined);
  return run;
}
