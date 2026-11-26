// 消息流内容区几何单源（自 ChatPageContent 顶侧几何域整域外迁）：**消息流内容区几何常量与
// 顶侧让位算式单源**——首帧兜底带高、末条呼吸量、排队入口条在场时的内容顶让位；底侧阅读
// 视口几何（ChatReadingViewport）与底带消费仍在 ChatPageContent（本件只供常量，不搬底带逻辑）。
// · 为何不并入既有件（反碎片下限②申报）：SearchTopBand 是搜索族带形输入件（让位算式已由
//   其导出复用，本件只做「排队带是否在场」的条件分派）；ChatReadingViewport 是底侧阅读视口
//   纯件；ChatPageContent 本件即拆分对象。新件 = 顶侧几何唯一缝。
// · 算式本体复用 SearchTopBand.searchBandContentTop——本件只加「排队带是否在场」条件分派，
//   禁重写第二份算式。
import { searchBandContentTop } from '../SearchTopBand';

// 首帧兜底口径（vp）：宿主/胶囊尚未实测时，底带整带兜底用它、resolve 衬垫用它 + bottomPad；
// 实测到位后阅读边界只用胶囊上沿实测值。
export const INPUT_BAND_HEIGHT: number = 101;

// 末条静止位呼吸量（vp；决明拍板 12）：末条气泡底边停在输入胶囊上沿**上方**本距离，不再与
// 上沿重合。加在底带单源落点（readingBand），contentEndOffset 与跟随 endInset 同挂该值恒等
//（消费点零改动）。后续调整只改本值一处。
export const CHAT_TAIL_BREATH: number = 12;

// 无泡态末条呼吸量（vp）：气泡关掉后正文底内距 10 一并归零，呼吸量在本值上加补回来——末条
// 文字离输入胶囊上沿仍恒 22vp（12 + 10），两档观感一致。算式挂 CHAT_TAIL_BREATH 推导，
// 调呼吸量或内距只改这两处源头
export const CHAT_TAIL_BREATH_NO_BUBBLE: number = CHAT_TAIL_BREATH + 10;

// 排队入口条与内容首项间距（vp）：缺省 28 = 分段承载先例间距（AppearancePage / DataSyncPage
// 同款「胶囊底 + 28」；首版 10 真机观感过短已改齐先例）。真机观感可调，只改本值一处。
export const QUEUE_BAND_GAP: number = 28;

// 内容区顶留白合成（消费点 = ChatPageContent 的 contentStartOffset / 锚判阅读跨度 / markdown
// 锚点顶界 / 更多菜单锚位四处；空态层不消费——排队非空 ⇒ 已有发送 ⇒ 空态层隐藏，共存不可达）：
// 带在场 → 带底 + 间距（算式单源 searchBandContentTop；带高缺省 SEGMENT_BAR_HEIGHT=40 与
// QueueTopBand 一致）；带隐藏 → topPad 原样（与 PageShell.titleBarBottomHidden 同源判据，
// 防「带隐藏了让位还在」错位）。HDS 带与回退内容区悬浮条同式：回退 topPad=0 时 = 0 + 40 + 28；
// 悬浮条顶取 max(topPad − 8, 0)（见 QueueTopBand），与带内容顶同口径。
export function chatContentTopPad(topPad: number, queueBandActive: boolean): number {
  return queueBandActive ? searchBandContentTop(topPad, QUEUE_BAND_GAP) : topPad;
}
