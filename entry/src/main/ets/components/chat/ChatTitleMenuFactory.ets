// 聊天页标题栏键与入口胶囊常量域（自 ChatPage 拆出，纯函数与常量零状态）。
// ═══ 现态（2026-11-15 B 路线两态笔；★ 2026-11-25 五轮滑轨形态改单热区）═══
// 覆盖层恒挂官方 stackBuilder，按会话标题文本广播键两态切换中央区；中央区热区形态再按
// 「思考档位滑轨」偏好分两支：
//   · 滑轨形态（默认）= 一条热区，文字仍是「模型」「思考」两字各半，点任意位置只弹滑轨卡
//     （模型入口收进卡内顶行；标题栏不显示模型名/档位名）；
//   · 菜单形态（偏好关）= 原两热区（「模型」直开模型半模态 /「思考」弹档位菜单）。
// 两态几何：无标题（新会话）= 居中胶囊，宽度档与一级页「对话」页签顶部分段同长
// （common/Theme.ets TITLE_CENTER_ZONE_* 单源），键高 40、热区 layoutWeight(1) 等分，
// 壳体 THIN 材质 + interactive（标题栏是沉浸光感生效区）；有标题 = 居中两行（主标题 +
// 「模型 思考」副标题行），两行都不垫底不另挂材质，由官方标题栏自身 HDS 材质统一呈现。
// 右上角〔＋|⋯〕双键胶囊退役，改单圆键〔⋯更多〕，「＋新建会话」收入更多菜单首项。
// ═══ 沿革（沿革自 dshinhm KimiChatPage.build() 迁入）═══
// 原承载 HDS 菜单数组与回退 menuNav（Navigation.menus 数组）双形态菜单工厂；两路菜单数组
// 均已退役（决明「加号与更多合并成一个胶囊」）：官方 HdsNavigationMenuContentOptions.value
// 每项只渲染一个独立圆钮（本地 SDK d.ts 实查：项 = HdsNavigationBadgeIconOptions
// {content.icon/action}，无自定义 builder 位），两键无法在菜单数组内合并；合并形态只能画在
// 官方标题栏自定义区（TitleBarContentOptions.stackBuilder，官方《设置自定义区域》——页面
// 覆盖层已在用），menuHds 传 null；回退路径已随 2026-10-31 HDS 兜底撤除整笔退役。
// ★ 隐私会话 2026-09-26 已全链退役，原「隐私标记 81vp / 等长上限 95.5vp」宽度预算随之
//   作废（旧注释留在本件与 ChatTitleBarOverlay 属退役漏删，本笔一并清理）。

// 模型入口标签（滑轨形态合并热区左半 / 菜单形态左热区文案，改名只改这一处）
export const MODEL_ENTRY_LABEL: string = '模型';
// 思考入口标签（滑轨形态合并热区右半 / 菜单形态右热区文案；只此一处）
export const THINKING_ENTRY_LABEL: string = '思考';

// 会话标题文本广播键（string）：写点 = ChatPage 标题反查链（进页/历史装载收尾/重显/
// CONV_TITLE_TICK_KEY 四路），读点 = ChatTitleBarOverlay 的 @StorageProp 自订阅（坑16 正解：
// 覆盖层经官方 titleBar napi 消费，@Prop 透传不保刷新，走 AppStorage 订阅式通道）。
// 无行新会话写 ''（只写不删，防会话切换残留旧标题；写空串值非删键，无坑15 竞态）。
export const CHAT_TITLE_TEXT_KEY: string = 'chatSessionTitleText';

// 预置标题属主键（string）：记录 CHAT_TITLE_TEXT_KEY 当前值属于哪个会话——点卡进页时
// seedTitlePreset 两键成对写，ChatPage 进页 adoptPreset 比对属主（见 ChatPageTitleCtrl）。
// 2026-11-15 反馈二笔立：异步反查永远晚于首帧，预置通道让老会话首帧即两行态。
export const CHAT_TITLE_PRESET_CONV_KEY: string = 'chatSessionTitlePresetConv';

// 标题栏模型显示名广播键（string，★ 2026-11-25 五轮「模型思考热区合一」）：写点 =
// ChatPage.setConnInfo（值取 ActiveConnectionInfo.modelName——显示名优先、取不到回落模型 ID，
// 解析失败写 ''）；读点 = ChatTitleBarOverlay 的 @StorageProp 自订阅（坑16 正解，覆盖层经官方
// titleBar napi 消费，@Prop 透传不保刷新）。★ 只走 AppStorage、不持久化、不进备份表——会话级
// 解析结果，换页由新页面 setConnInfo 覆盖；只写不删（残留值只在无连接时被 modelText 的
// 「模型」兜底遮住，无坑15 竞态）。侧栏形态（DrawerHomeTitleBar 跨层装配）与二级页共用本键，
// 不再各接一份 @Link。
export const CHAT_TITLE_MODEL_KEY: string = 'chatTitleModelLabel';

// 预置标题播种（导航侧点卡同步调用，列表/搜索页手里就有行 title）：两键成对写——标题落
// 广播键 + 属主落预置键。title 空串/缺省时**两键都不写**（播种无意义；残留属主键若恰为
// 同一会话则保留旧值也是该会话的真标题，refreshIfReady 即刻校正）。只写不删，无坑15 竞态。
export function seedTitlePreset(conversationId: string, title?: string): void {
  if (title === undefined || title === '') {
    return;
  }
  AppStorage.setOrCreate<string>(CHAT_TITLE_TEXT_KEY, title);
  AppStorage.setOrCreate<string>(CHAT_TITLE_PRESET_CONV_KEY, conversationId);
}

// 入口胶囊几何（vp）：高 40 = 标题栏返回键/菜单键实测值，与同栏 40vp 自绘键齐平；
// 圆角 20 = 半高（半圆端头）。宽度不在此自持 —— 两态中央区统一走 Theme.TITLE_CENTER_ZONE_*。
// ★ 原「字号 16fp / 内距 7vp 对冲」（16fp 文本 32vp + 2×7 = 46vp 热区、胶囊 92vp）随胶囊
//   加长退役：两热区改等分父容器，不再用固定内距；16fp 是决明两轮拍板值，本笔原样保留。
export const MODEL_ENTRY_HEIGHT: number = 40;
export const MODEL_ENTRY_RADIUS: number = MODEL_ENTRY_HEIGHT / 2;
export const MODEL_ENTRY_FONTSIZE: number = 16;

// 有标题态副标题行紧凑宽（vp）：四字「模型 思考」两热区各 46vp；副标题行在定宽 204vp 胶囊内
// 独立收窄居中，避免四字散在标题行里。★ 2026-11-24 曾按「热区间距略小」误收 92→84，
// 决明订正其所指为**上下两排间距**而非左右热区，本值回 92；间距收排放 TITLE_SUBTITLE_GAP。
// 胶囊末笔改定宽（内层 .width(TITLE_CAPSULE_WIDTH)=204vp），本值不再参与宽度算式。
export const TITLE_SUBTITLE_ROW_WIDTH: number = 92;
// 副标题行高（vp）：2026-11-24 两行收进 40vp 光感胶囊后按真机反馈「字贴胶囊边」自 24 收 20，
// 同日再按「缩第二排字号与两排间距、增大字跟胶囊间距」收 20→17→16（字号同步 13→12、两排
// space 1→0），行高账 = 主标题 lineHeight 16 + space 0 + 本行 16 = 32vp，壳 40vp ⇒ 上下各
// 4vp 留白（两排整体由 Column justifyContent(Center) 垂直居中）；40vp 壳高与返回键
// TITLE_ROUND_KEY_SIZE 同高。两热区是标题文字入口而非行内操作键，官方最小点击热区 40vp 在
// 40vp 内与两行文字不可兼得，命中以真机为准。
export const TITLE_SUBTITLE_ROW_HEIGHT: number = 16;
// 副标题态字号（fp）：2026-11-15「略大点」笔自 13 升 14；2026-11-24 两行收进胶囊后按真机
// 反馈「字贴边」回落 14→13，同日再按「缩第二排字号与两排间距、增大字跟胶囊间距」收 13→12
//（与行高 17→16、space 1→0 同笔，合计腾出上下各 4vp 留白）；胶囊态 MODEL_ENTRY_FONTSIZE(16)
// 不动。独立常量不顶 CARD_NOTE_FONTSIZE 顶值（那档是全应用「卡内说明行」共享常量，改值 = 45 处
// 跟着跳），本常量只影响本处。副标题四字色走 Theme.selectedAccentBlue（选中态强调蓝单源）。
export const TITLE_SUBTITLE_FONTSIZE: number = 12;
