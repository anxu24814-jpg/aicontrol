// 直播失效信号旁路发布口。职责一句话：**conv_invalidate 的进程级发布间接位**——收尾域
//（ChatStreamFlowCtrl）在终态落库完成后一跳提交会话列表失效信号，中枢（ChatLiveHub）在
// 模块加载时登记真正的发布实现。
// 为什么不能并入既有件（反碎片判据）：ChatStreamFlowCtrl import ChatLiveHub = 反向依赖 +
// 模块环（中枢已 type-only 引用流控件的 tap 契约，坑50）；而本信号是**列表级**的——chat
// 的会话 wire 只覆盖 web 已打开的会话，列表页从未打开任何会话，走 wire 会让「手机新会话/
// 手机轮收尾」永远刷不动列表。故单立零 import 叶子：收尾域只调本件，中枢登记实现，两域
// 零直接依赖。
// 生命周期与有界性：单槽登记（进程内恰一个中枢；重复登记后者胜）；未登记 = no-op（web 域
// 未加载 / 单测环境 / kill-switch 关态零行为增量）。成对清理口 registerChatLivePublish(null)
// 供替换/测试；生产链无注销（中枢进程级单例，与运行态同寿命，不挂页面对象）。
export type ChatLivePublishFn = (conversationId: string) => void;

let livePublishSink: ChatLivePublishFn | null = null;

// 登记发布实现（中枢模块加载期调用；null = 摘除）
export function registerChatLivePublish(fn: ChatLivePublishFn | null): void {
  livePublishSink = fn;
}

// 提交会话列表失效（收尾落库完成后调用；空 id / 未登记全 no-op——禁静默失败由调用方
// 判空，本处 no-op 是「无 web 域」的合法退化而非错误）
export function publishChatLiveInvalidate(conversationId: string): void {
  if (conversationId === '' || livePublishSink === null) {
    return;
  }
  livePublishSink(conversationId);
}
