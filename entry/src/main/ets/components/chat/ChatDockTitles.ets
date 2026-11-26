// 底部托管位文案与进度纯函数单源（2026-11-08 输入位接管笔）：细条/面板头行标题、进度
// n/N 的判据同时被托管位与流内头行消费，禁两处各写一遍。放独立叶件是为了不碰
// ChatToolCard 既有的 `import { AskQuestion, ChatAskUserCard, parseQuestions }` 逐字钉面
//（138 组），且不落 ChatMessageCompose 造成与 ChatAskUserCard 的模块环。
// 只做纯计算，零 UI、零状态、零组件装饰器。
import { AskDraftState } from './ChatMessageCompose';

// 确认卡细条/面板头行统一标题：底部是「输入位接管」的统一形态，具体工具名由流内头行
// 的 confirmTitle 单源表达，底部不重复十六分支（避免复制一份标题表或改判 124 组逐位钉）
export const DOCK_CONFIRM_TITLE: string = '助手想请你确认一个操作';

// 提问卡细条/面板头行标题（单题 / 多题两态；沿用既有「助手」口径，竞品图里的「AI」不跟）
export function askDockTitle(questionCount: number): string {
  return questionCount > 1 ? '助手想跟你确认 ' + questionCount + ' 个问题' :
    '助手想跟你确认一下';
}

// 已作答题数 = chips 有选中 或 自由文本非空（与 ChatAskUserCard.isAnswered 同判据）。
// 托管位与流内头行在等待期都读 msg.askDraft 现算，不依赖子卡 onProgress 上行——卡体被
// 抑制后没有子卡实例，进度徽章仍须逐题同步。数组逐项下标读取有 ??/越界防御，坏草稿不炸。
export function askAnsweredOfDraft(draft: AskDraftState | undefined,
  questionCount: number): number {
  if (draft === undefined || questionCount <= 0) {
    return 0;
  }
  let answered: number = 0;
  for (let i = 0; i < questionCount && i < draft.drafts.length; i++) {
    const picked: string[] = draft.selections[i] ?? [];
    const typed: string = draft.drafts[i] ?? '';
    if (picked.length > 0 || typed.trim() !== '') {
      answered++;
    }
  }
  return answered;
}
