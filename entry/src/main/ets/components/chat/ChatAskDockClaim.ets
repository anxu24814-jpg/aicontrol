// 输入位托管的认领判定域（2026-11-08 两千一百二十八笔自 ChatPageContent 域级最小拆分）。
// 职责一句话：决定「当前该由哪张等待卡接管底部输入位」——认领优先级、身份校验、重进装载
// 时的复用残留复位，全在本件；ChatPageContent 只把结果写进 @State 与普通成员。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话 = 等待卡认领判定；②无既有
//   同域可并——ChatDockTitles 是文案/进度纯函数叶件、ChatAskDock 是托管位 UI 壳，两者都不
//   该承载「数据源扫描 + 接管优先级」；③实逻辑非转接壳：本件持托管真源（held），承载
//   重进复用对象的标记复位与最靠后卡扫描（根因修复点）。
// · 根因（2026-11-08 真机报障「离页再进托管位丢失、输入框重现」）：等待卡期间 busy 恒真，
//   重进走 remountLive 复用同一批 ChatMessage 对象、不读库重建——上一页留下的
//   dockOwned=true 让 ChatToolCard 的认领守卫（&& dockOwned !== true）短路，而新页
//   dockVisible 初值 false，于是托管位与流内卡体双灭。方案档 §4.4「离页不回写标记」的
//   契约不变：复位改在**装载侧**（本件 sync），不再指望「新对象天然 undefined」。
// · 依赖方向：本件 → ChatDataSource / ChatMessageCompose 单向；页面与卡件禁反向 import 本件
//   （零环红线，坑50）。
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage, isStepAwaitingUser } from './ChatMessageCompose';

export class ChatAskDockClaimCtrl {
  // 托管真源（null = 未托管）；dockOwned 标记由本件写，页面只镜像 held 到 dockMsg
  private held: ChatMessage | null = null;

  // 认领（幂等 + 只托管最靠后一张）：非等待态 / 不在数据源 / 比在管卡更靠前 → 原样返回；
  // 残留标记（held 之外对象上的 dockOwned=true）不阻止接管——那是上一页复用的脏值
  claim(ds: ChatDataSource, msg: ChatMessage): ChatMessage | null {
    if (!isStepAwaitingUser(msg)) {
      return this.held;
    }
    if (ds.findMessage(msg.id) !== msg) {
      // 孤儿（换源后旧对象被移出数据源）：若正是在管卡则释放，否则忽略
      if (this.held === msg) {
        this.dismiss();
      }
      return this.held;
    }
    if (this.held !== null && this.held !== msg &&
      ds.listIndexForMessage(this.held.id) > ds.listIndexForMessage(msg.id)) {
      return this.held; // 在管卡更靠后：不被更早的卡抢位
    }
    if (this.held !== null && this.held !== msg) {
      this.held.dockOwned = false;
    }
    this.held = msg;
    msg.dockOwned = true;
    return this.held;
  }

  // 释放（单入口）：作答同帧、终态兜底、换源/离页清位共用；只清自己持有的那张
  dismiss(): void {
    if (this.held !== null) {
      this.held.dockOwned = false;
    }
    this.held = null;
  }

  // 装载同步（页面 aboutToAppear 首扫一处调用；换源/分支重建不另触发——由列表项挂载认领
  // 钩子补位认领、数据源 clearStaleDockMarkers 清扫残留，见 2128 自检轮勘误）：①在管卡若已终态或
  // 已成孤儿 → 释放；②清复用对象上的残留托管标记（离页不回写，装载侧复位）；③从后往前
  // 找最靠后的等待卡认领。返回应托管对象（null = 无卡可托管，页面据此恢复输入栏）
  sync(ds: ChatDataSource): ChatMessage | null {
    if (this.held !== null) {
      if (!isStepAwaitingUser(this.held) || ds.findMessage(this.held.id) !== this.held) {
        this.dismiss();
      } else {
        return this.held; // 仍在管且仍等待：保持原状（不因一次刷新重置展开态）
      }
    }
    const all: ChatMessage[] = ds.allMessages();
    for (const m of all) {
      if (m.kind === 'tool' && m.dockOwned === true) {
        m.dockOwned = false;
      }
    }
    for (let i = all.length - 1; i >= 0; i--) {
      if (isStepAwaitingUser(all[i])) {
        return this.claim(ds, all[i]);
      }
    }
    return this.held;
  }
}
