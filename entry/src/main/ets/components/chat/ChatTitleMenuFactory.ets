// 聊天页标题栏菜单工厂与入口胶囊常量域（2026-09-17 会话上下文用量执行笔自 ChatPage.ets
// 拆出——该文件剔头越 1200 硬线，宪法「先把本次改动所属的功能域拆到独立文件再动手」+
// 技术债务清单 ChatPage 条候选缝〔标题栏域〕；本域 = 纯函数与常量零状态，方法体与注释
// 原样搬迁行为不变，ChatPage 改 import 消费）。
// ═══ 标题栏菜单工厂（2026-08-26 夜间任务拆分自 dshinhm KimiChatPage.build() 迁入；
// 2026-09-01 自 ChatTitleMenu.ets 并回 ChatPage；2026-09-17 再外迁本件）：HDS 路径
// menuHds（官方标题栏菜单数组，间距/圆钮/材质官方排版接管）与回退路径 menuNav
//（Navigation.menus 数组）双形态，回调经参数注入（页面转发 newConversation / openMoreMenu，
// 回退路径另含 openModelSheet）。
// ★ 2026-09-09 模型入口两次换位：先自「标题栏模型名点击」改三键中键（一百八十二），
// 同日晚再改「返回键右侧『模型』胶囊」（二百一十六）——HDS 数组回双键。
// ★ 2026-09-09 二百二十七：HDS 数组整体退役（决明「加号与更多合并成一个胶囊」）——
// 官方 HdsNavigationMenuContentOptions.value 每项只渲染一个独立圆钮（本地 SDK d.ts 实查：
// 项 = HdsNavigationBadgeIconOptions{content.icon/action}，无自定义 builder 位），两键无法
// 在菜单数组内合并；合并形态只能画在官方标题栏自定义区（TitleBarContentOptions.stackBuilder，
// 官方《设置自定义区域》——页面覆盖层已在用），故两键迁入覆盖层（键件 = 共用件
// TitleBarKeys.TitleBarActionCapsule，2026-09-11 迁移）；HDS 路径 menuHds 传 null。回退路径
// 无 stackBuilder 机制，仍是官方菜单三键（形态必然不同）。═══
import { SymbolGlyphModifier } from '@kit.ArkUI';

// 隐私会话标题栏标签（两处共用同一文案：HDS 路径覆盖层标记 + 回退路径 PageShell.title
// ——回退无覆盖层机制，标记只能走标题栏文字）
export const PRIVATE_SESSION_LABEL: string = '隐私会话';

// 模型入口标签（决明 2026-09-09 指令「改模型二字」——标题栏胶囊与回退路径菜单项共用同一
// 文案，改名只改这一处）
export const MODEL_ENTRY_LABEL: string = '模型';
// 思考入口标签（★ 2026-09-09 二百二十九，决明「键内右侧放思考二字」——模型|思考双热区
// 胶囊右热区文案；只此一处）
export const THINKING_ENTRY_LABEL: string = '思考';

// 标题栏入口胶囊几何（vp）：★ 高度 40 = 标题栏返回键/菜单键实测值（真机 140px @3.5，决明
// 「高度要统一」——三键同高，二百二十九「不改变键高度」继续钉住）。★ 二百二十九改双热区
//（模型|思考，左热区开模型面板、右热区开思考档位菜单）。★ 二百三十一（决明「模型/思考
// 间距小一点，加号/更多大一点，使两胶囊长度统一，热区各自同步」）：水平内距 12 → 9。
// ★ 二百三十六（决明「字号可以稍微大一点点吗？在不改变胶囊形状的情况下…再把『模型』二字
// 字重大一点」）：字号 14 → 15fp（两字文本 28 → 30vp），水平内距 9 → **8** 对冲——单热区
// = 8 + 30 + 8 = **46vp**、胶囊 = 2 × 46 = **92vp** 不变。★ 二百三十七（决明「真机效果
// 可以，保持胶囊不变的情况下，字号能再大一点点吗？」）：字号 15 → **16fp**（文本 30 →
// 32vp），内距 8 → **7** 对冲——单热区 = 7 + 32 + 7 = 46vp、胶囊 92vp 仍不变（「不改变
// 胶囊形状」恒由「字号增量 = 内距减量 × 2」实现；内距余量见下：字号每 +1fp 内距 -0.5vp，
// 几何上到 18fp（内距 5）仍容得下，再大须改胶囊宽或热区宽）。★ 宽度预算（决明「注意
// 宽度」；二百二十七随右上角胶囊重算、二百二十八随胶囊 80→84 复核、二百二十九随本键加长
// 复核、二百三十一随两胶囊等长复核、二百三十六/二百三十七随字号调整复核）：标题栏可用宽
// = 屏宽基线 360 − 左避让 64 − 右避让 16 − 右上角胶囊 92 = 188vp；非隐私态左组 = 92vp
//（富余 96vp）；**隐私态**左组 = 92 + 间距 8 + 隐私标记 ≈81 = 181vp ≤ 188vp（余 7vp）。
// 等长上限即由该预算定：胶囊宽 W 须满足 W + 8 + 81 ≤ 360 − 64 − 16 − W → W ≤ 95.5vp，取
// 92 且四热区同宽（96 即溢出 1vp，勿再加大）。
export const MODEL_ENTRY_HEIGHT: number = 40;
export const MODEL_ENTRY_PAD_H: number = 7;
export const MODEL_ENTRY_RADIUS: number = MODEL_ENTRY_HEIGHT / 2;

// 回退路径标题栏菜单（无 HDS 时的 Navigation.menus 数组，SymbolGlyphModifier 官方符号修饰器）：
// 回退路径没有 stackBuilder 机制、画不了标题栏胶囊，模型入口保留在菜单里（语义等价，避免
// 非 HDS 设备功能不可达）；图标沿用 arrow_left_arrow_right（切换语义，SDK 符号表实锤）
export function chatTitleMenuNav(onNewChat: () => void, onSwitchModel: () => void,
  onMore: () => void): NavigationMenuItem[] {
  return [{
    value: '新建会话',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onNewChat
  } as NavigationMenuItem, {
    value: MODEL_ENTRY_LABEL,
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right')),
    action: onSwitchModel
  } as NavigationMenuItem, {
    value: '更多',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
    action: onMore
  } as NavigationMenuItem];
}
