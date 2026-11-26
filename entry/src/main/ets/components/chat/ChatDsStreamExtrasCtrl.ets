// DS 流式扩展字段收尾消费域（DS 全家桶二期 S2；任务书 §6-S2 新件清单）。
// 一句话职责 =「消费响应末尾才确定的两类扩展信息：服务端标题写库 + 拒答处置」。
// · 为何两件合成一件（宪法反碎片下限②申报）：两者都是「响应末尾才确定的扩展信息」，同一
//   收尾时机消费，拆两件就是纯转接壳。
// · 标题（#4 官方会话标题）：CC 末 chunk `delta.title` / Responses 结束事件 `response.title`
//   → 非空且来源非 `manual` 时 setConversationTitle(id, title, 'ds')；空标题**不写库**
//  （回落 TitleGen 兜底，官方「不一定带标题」），不写空串、不占 titleSource。
//   ★ 时序红线：写库须在轮末 `generateTitleForConversation` 之前 await 完成——调用方
//   （ChatStreamFlowCtrl）在 `graphFinishRound` 发起前串接本件 writeTitle 的承诺；否则轮末
//   TitleGen 先判「无标题」白跑一次 TitleApi 请求。
// · 拒答（#6 内容安全）：两种信号分开处置（官方语义不同，禁合并文案）——
//   ① `finish_reason=content_filter` = **回答被过滤**：撤下已流式展示的正文、气泡改显
//     DS_REFUSAL_TEXT、按失败轮落库（正文空 + 错误态 + 重试键），与续写判据互斥；
//   ② `delta.refusal` / `message.refusal` = **图片**未通过审核（官方原文「指出被拦截的
//     图片」）：**不撤正文**，单独呈报一句，与①文案分开。
// · 本件不碰流传输与 UI：只做「记录 + 写库 + 判据查询」；展示与落库由 ChatStreamFlowCtrl
//   消费（薄接线①）。kill switch = 调用方不喂数据（非 DS 流 delta 无三键，本件全程空转）。
import { SseDelta } from '../../common/providers/SseParser';
import { queryConversationTitleSource, setConversationTitle } from '../../common/store/ChatDb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatDsExtras';

// 输出侧拒答（回答被内容审核撤下）——文案拍板定死（方案档 §4.5，禁改写）
export const DS_REFUSAL_TEXT: string = '该回答因内容安全审核未能展示';

// 图片未过审呈报（与 DS_REFUSAL_TEXT 分开——官方语义是「指出被拦截的图片」不是「回答被撤」）
export const DS_IMAGE_REFUSAL_TEXT: string = '本轮图片未通过内容安全审核';

// 输入侧拦截（400 Content Exists Risk）——文案拍板定死（方案档 §4.5，禁改写）
export const DS_INPUT_RISK_TEXT: string = '输入内容未通过内容安全审核，请修改后重试';

// 工具共存自适应停用标注（自检轮补）：首流 400 提到工具冲突 → 剔除客户端 function 工具
// 重发一次，本轮须让用户知道客户端工具失效（任务书 §1-7「在该轮标注工具已停用」）。
// 放本件理由 = DS 官方能力面文案同源（三条 DS 用户面文案同处，消费方 = ChatStreamFlowCtrl）
export const DS_TOOL_DROP_TEXT: string = '本轮官方联网与客户端工具冲突，已停用客户端工具重试';

export class ChatDsStreamExtrasCtrl {
  private pendingTitle: string = '';
  private filtered: boolean = false;
  private imageRefusal: boolean = false;

  // 流内增量入口（薄接线①）：只记录不写库。title 取最后一次非空（末 chunk 才带，若有多个
  // 以最后为准）；filtered 一旦置真不再回退（拒答轮终态不可变）；
  // refusal 字符串不直接展示（官方文案面向开发者、可能含英文细节），只作为「图片被拦」的
  // 事实位——用户面文案统一取本件常量
  noteDelta(delta: SseDelta): void {
    if (delta.title !== undefined && delta.title !== '') {
      this.pendingTitle = delta.title;
    }
    if (delta.contentFiltered === true) {
      this.filtered = true;
    }
    if (delta.refusal !== undefined && delta.refusal !== '') {
      this.imageRefusal = true;
    }
  }

  // 输出侧拒答判据（收尾消费：true = 撤正文 + 改显拒绝文案 + 失败轮落库）
  isFiltered(): boolean {
    return this.filtered;
  }

  // 图片未过审判据（收尾消费：不撤正文，单独呈报一句）
  hasImageRefusal(): boolean {
    return this.imageRefusal;
  }

  // 待写标题（'' = 本轮无标题）——只读，供调用方判「是否还需要轮末 TitleGen 兜底」的观察面
  titleOf(): string {
    return this.pendingTitle;
  }

  // 标题写库（调用方在 graphFinishRound 前 await；本方法自身吞错留痕不阻断轮收尾——
  // 标题是增益非必需，官方的兜底链 TitleGen 仍在）。守卫：空标题不写（回落 TitleGen）、
  // 行来源 manual = 用户手改终胜出不覆盖（唯一防覆盖闸，与 TitleGen 同源判据）
  async writeTitle(conversationId: string): Promise<void> {
    const title: string = this.pendingTitle;
    if (title === '' || conversationId === '') {
      return;
    }
    try {
      const source: string = await queryConversationTitleSource(conversationId);
      if (source === 'manual') {
        return;
      }
      await setConversationTitle(conversationId, title, 'ds');
      this.pendingTitle = ''; // 消费即清（防同轮重复写、防下一轮误用旧标题）
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'DS 官方标题写库失败（回落 TitleGen 兜底）：%{public}s',
        (e as Error).message);
    }
  }
}
