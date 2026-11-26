// 聊天页菜单层（页面「更多」+ 消息「更多」两菜单，同基类同纪律见文末）。
// 官方全局菜单 openMenu（@since 18）+ 页面内隐形锚点做 target（锚点组件见 ChatPageContent.ets
// ②层；几何常量见 common/Theme.ets）。**姿势沿用原因**：菜单弹出/关闭语义（锚点几何、弹前按
// 深浅色重建 ComponentContent、材质 REGULAR 基准）已按 openMenu 调稳，换 bindMenu 属行为
// 变更非需求不动（回退路径「更多」是系统渲染层菜单项挂不了 bindMenu；Menu 组件无编程式弹出
// API）。★「刷新」项已退役（决明确认）——动作 refreshPage 保留，唯一消费方 = 错误覆盖层
//「重试」（ChatPage.onRetry）。
// ★ 联网项已迁出（★ 2026-10-30 决明「把联网搜索从菜单移出到加号半模态页，新增行卡」）：
// 原 2026-09-19 迁入的「联网」项（含 2026-10-17 引擎化二级菜单）整域迁往加号半模态
// ChatPromptSheet（面板同日更名「会话设置」）——可用性现读/指引 toast/引擎清单快照/当前引擎
// 快照/WebSearchMenu 五件随域迁移，行卡 + bindMenu 引擎菜单承载；★ 2026-11-11 决明「标题栏
// 双键胶囊已有新建，菜单里重复」笔：「新建会话」项撤除（首项位置空缺后由「会话工作区」升首），
// 本菜单现为 会话工作区/会话轨迹/会话统计 三项，新建唯一入口 = 标题栏〔＋〕左热区。
// ★ 2026-11-15 标题栏两态笔：右上〔＋|⋯〕双键胶囊改单圆键〔⋯更多〕，〔＋新建会话〕
//   回到本菜单首项（动作链 ChatPageMenuCtrl.newSession 一字未动），菜单恢复四项。
// subMenuExpandingMode 随唯一子菜单项退役整属性删。
// 无状态：内容节点由 ChatPage 创建/持有/销毁——每次弹出前重建（ComponentContent 固化 UI 树
// 不随深浅色切换，坑69 家族）、aboutToDisappear dispose 成对释放。
import { ComponentContent, uiMaterial, SymbolGlyphModifier, UIContext, promptAction } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial, overlayMaterial } from '../../common/ImmersiveLevel';
import { MENU_UNIFIED_WIDTH, menuDividerColor } from '../../common/Theme';
import { BranchAllow } from '../../common/chat/ChatBranchPolicy';
import { CHAT_DS_CONTINUE_AVAILABLE_KEY, continueVisibleBy, requestContinue }
  from '../../common/chat/ChatContinueSupport';
import { ChatMessage } from './ChatMessageCompose';
import { ChatDataSource } from './ChatDataSource';

const DOMAIN: number = 0xD5A0;
const TAG: string = 'ChatMessageMenu';
// 删除确认正文（同族失效文案已随 body 场景退役，2026-11-05 菜单笔）：连带范围如实告知——
// 剪枝语义的非显然部分（跨分支内容一并删）必须明示；不带条数（1193 拍板）；过文案规约
//（两句号分句）
const DELETE_CONFIRM_MESSAGE: string =
  '这条消息与其后的全部对话都会删除，包括其他分支上的内容。删除后不可恢复。';

// 菜单回调（openMenu 的 ComponentContent 参数载体；全局 @Builder 形态见文件头）
export interface ChatMoreMenuCallbacks {
  // 新建会话（★ 2026-11-15 恢复：标题栏改单圆键后 〔＋〕入口收入本菜单首项，动作链 =
  // ChatPageMenuCtrl.newSession，与一级页「对话」页签菜单首项同款）
  onNewSession: () => void;
  // ★ 2026-11-11 新建去重笔：原 onNewSession 字段随「新建会话」菜单项撤除（决明「标题栏双键
  // 胶囊有新建，更多菜单里又有，去掉菜单里的新建」）——该笔于 2026-11-15 随标题栏改单圆键回退，
  // 动作链 ChatPageMenuCtrl.newSession 全程一字未动
  // ★ 2026-10-30 联网项迁出笔：原 webSearchEnabled/onWebSearchDenied/webSubMenu 三字段随
  // 「联网」项整删（迁往 ChatPromptSheet 联网卡），见文件头
  // 会话统计项（SessionStatsSheet 半模态）：onOpenStats = 点击上行（落点 ChatPage.
  // openStatsSheet）；恒显示
  onOpenStats: () => void;
  // 设置项（★ 2026-11-16 双形态真机修复笔防困死兜底）：仅侧栏形态主区常驻态传（二级页
  // 形态有系统返回不传 = 菜单不挂该项）——侧栏域（汉堡键/手势）故障时设置页恒可达，
  // 保住「切回底栏形态」的逃生门；动作 = push 设置二级页
  onOpenSettings?: () => void;
  // 会话轨迹项（SessionTracePage 二级页）：onOpenTrace = 点击上行；与「会话统计」同族只读
  // 信息面板、恒显示，两项相邻（本项在其前）
  onOpenTrace: () => void;
  // 会话工作区项（SessionWorkspacePage 二级页）：onOpenWorkspace = 点击上行；本会话工作区
  // 文件的只读清单 + 四动作（原「联网」之后——联网项迁出后本项升为第二位，动作/导航族居前、
  // 只读信息面板垫底）
  onOpenWorkspace: () => void;
  // 上下文用量项已撤回（决明口径「只留输入框环形入口」）——字段随删；用量面板由输入条圆环
  //（主入口）与压缩摘要轻提示行两处可达
}

// 「更多」菜单锚点 id（openMenu 的 TargetInfo 定位目标组件，页面内唯一）
export const CHAT_MORE_MENU_ANCHOR_ID: string = 'chatMoreMenuAnchor';

// ★ 2026-10-30 联网项迁出笔：原联网开关域整段（可用性现读 webSearchEnabledNow / 指引 toast
// notifyWebOff / 引擎选项 WebSearchEngineOption / 引擎清单快照 enabledWebEngineOptions /
// 当前引擎快照 currentWebEngineId / 二级菜单本体 WebSearchMenu）随「联网」项迁往
// ChatPromptSheet 联网卡（域内注释与实现原样随迁），本件不再持有。

// 「更多」菜单内容（openMenu 的 ComponentContent 载体）：宽度 = 项目统一固定宽
// MENU_UNIFIED_WIDTH（决明指令两页标题栏菜单统一；机制教训〔只有固定值 width 触发官方
//「子项取固定宽」规则〕见 common/Theme.ets 常量注释）。图标为官方系统符号（坑72：
// sys.symbol.image/document 等裸名不存在，选用前先核字形表）：folder / clock /
// data_proportion（plus 随 2026-11-15 新建项恢复、magnifyingglass 随联网项迁出后离场）
@Builder
export function ChatMoreMenuBuilder(params: ChatMoreMenuCallbacks) {
  Menu() {
    // ★ 2026-11-15 标题栏两态笔：右上〔＋|⋯〕双键胶囊改单圆键〔⋯更多〕，新建会话回本菜单
    // 首项（与一级页「对话」页签菜单同款；plus = 原左热区同符号，迁移后图标语义不断）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
      content: '新建会话' })
      .onClick(() => {
        params.onNewSession();
      })
    // 会话工作区项：动作/导航族居前、只读信息面板垫底；图标 sys.symbol.folder
    //（在产符号名已核，坑72）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder')),
      content: '会话工作区' })
      .onClick(() => {
        params.onOpenWorkspace();
      })
    // 会话轨迹项：「会话统计」之前——同族只读信息面板相邻；图标 sys.symbol.clock（已核，坑72）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.clock')),
      content: '会话轨迹' })
      .onClick(() => {
        params.onOpenTrace();
      })
    // 会话统计项：只读信息面板与轨迹项相邻垫底，动作项居其前；图标
    // sys.symbol.data_proportion（chart 系裸名〔chart_bar/chart_pie/gauge〕不存在，坑72）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.data_proportion')),
      content: '会话统计' })
      .onClick(() => {
        params.onOpenStats();
      })
    // 设置项（★ 2026-11-16 双形态真机修复笔防困死兜底，可选）：仅侧栏形态主区常驻态挂
    //（callbacks 传了才显示）——侧栏域故障时保住进设置页切回底栏形态的逃生门；图标
    // sys.symbol.gearshape（TabShell 设置页签同符号，坑72 已核）；会话域项之后垫底，
    // 与会话动作族分界
    if (params.onOpenSettings) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')),
        content: '设置' })
        .onClick(() => {
          if (params.onOpenSettings) {
            params.onOpenSettings();
          }
        })
    }
    // 上下文用量项已撤回（决明口径「只留输入框环形入口」，见 callbacks 接口注释）
  }
  // 主菜单挂统一固定宽 MENU_UNIFIED_WIDTH（决明指令两页标题栏菜单统一，与 TabMoreMenuBuilder
  // 同值）。★ 2026-10-30 联网项迁出笔：subMenuExpandingMode(STACK_EXPAND) 随唯一子菜单项
  //（联网）退役整属性删——本菜单再无带 builder 的项
  .width(MENU_UNIFIED_WIDTH)
  // 分割线标准姿势（menuItemDivider 默认不显示须显式设置；mode 必须 EMBEDDED_IN_MENU——
  // FLOATING 悬浮层被菜单项盖住不可见；颜色走 menuDividerColor 深浅色分治；全局 @Builder
  // 无组件实例，深浅色直接读 AppStorage——节点弹前重建，读取恒为当前深浅色）
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 「更多」菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现
// buildNode 与便捷 open，页面侧 init/open/dispose 调用零变化）
export class ChatMoreMenuHost extends AppMenuHost<ChatMoreMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ChatMoreMenuCallbacks): ComponentContent<ChatMoreMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ChatMoreMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重建 UI 树；REGULAR 基准 = 决明拍板的全菜单
  // 统一档，随沉浸光感总档在此解析，页面侧只传档位值）
  open(uiContext: UIContext, callbacks: ChatMoreMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, CHAT_MORE_MENU_ANCHOR_ID,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// ═══ 消息「更多」菜单（并入本文件——反碎片下限②：与页面「更多」同域〔聊天页 openMenu
// 菜单，同一宿主基类、同一消费方 ChatPage、同一深浅色重建纪律〕）═══
// 删除项已从 toast 占位换真实现：过闸判据 + 确认弹窗 + 执行上行全链落地（编排见
// ChatMessageMenuCtrl.deleteFromMenu/confirmDelete）。
// ★ 2026-11-15 续写收入菜单笔（决明「助手消息的续写收入更多菜单」）：行内续写键随入口迁
// 本菜单（居首，仅可续写的助手轮尾行渲染），行内键与 @StorageProp 广播订阅随迁退役——菜单
// 成唯一入口，判据单源 ChatContinueSupport 不变、点击链 requestContinue 登记通道不变。
// ⚠ 锚点在 LazyForEach 列表项内（既有六域锚点均在固定卡片上）——列表滚动中弹菜单/
// 菜单开着项滚出视口/项回收后重弹三态为真机验证项；失败路径基类 show 已 catch + hilog 不静默

// 消息菜单锚点 id 前缀（openMenu TargetInfo 定位目标 = 气泡底栏「更多」键：
// .id(前缀 + 消息 id)；前缀与本 host 拼接同源）
export const MESSAGE_MENU_ANCHOR_PREFIX: string = 'chatMsgMenu_';

// 消息菜单场景——由当前 msg.kind / text / opsHost **现读**派生：user→user（用户消息全菜单）；
// assistant+opsHost→round（轮尾宿主全菜单）；其余 none 不弹（渲染层不为 none 行挂键，此处
// 兜底拒开）。★ 2026-11-05 菜单笔：原 body 场景（中间正文「复制正文 / 查看正文」两项）随两处
// 省略号入口退役整条删除——非 opsHost 的 assistant 行不再有菜单入口，收敛为 none。
export type MessageMenuScene = 'user' | 'round' | 'none';

// 消息菜单回调。菜单形态：「编辑 / 复制为新会话 / 删除消息」〔轮尾与 user〕+「续写」〔仅
// 可续写的助手轮尾行，2026-11-15 续写收入菜单笔自行内键迁入——行内键退役，菜单成唯一入口；
// 重试项与「其他回答」随 rik 形态统一笔退役——重试唯一入口 = 气泡重试键，其他回答唯一入口 =
// 行内步进器；「创建分支」已退役；中间正文两项随 2026-11-05 菜单笔退役）。「编辑」扩两角色
//（user 走输入框、assistant 走编辑面板，分流在 ChatBranchCtrl.beginEditDispatch）。可用性
// 口径：**不做置灰项**——不可用的点击经上行处理器呈报原因 toast；结构性不适用的项整项隐藏
//（showEdit：编辑只对 user 与 assistant 消息——渲染灰项是噪声；showContinue：不可续写行
// 整项不渲染，判据单源 = ChatContinueSupport.continueVisibleBy）
export interface ChatMessageMenuCallbacks {
  // 场景（round / user 两档，动作集合相同；none = 不弹）
  scene: MessageMenuScene;
  // 「续写」：可续写的助手轮尾行（DS 官方 CC + 末条 + 非流式 + 有正文 + 未用服务端工具 +
  // 未判定不支持——判据单源 ChatContinueSupport.continueVisibleBy，连接可用性现读广播键）。
  // 点击走 requestContinue 登记通道（与原行内键同一动作链，ChatContinueCtrl 编排零改动）
  showContinue: boolean;
  onContinue: () => void;
  // 「编辑」：user 与 assistant 行（扩两角色——分流在编排域）
  showEdit: boolean;
  onEdit: () => void;
  // 独立会话 fork 项（「复制为新会话」）：物化所选前缀与附件、副本独立拥有（唯一 fork
  // 形态）。可用性不在此判：判据单源 = ChatBranchPolicy.canForkAt，点击后编排域过闸呈报
  showCopyNew: boolean;
  onCopyNew: () => void;
  // 「删除消息」：点击经 refs deleteAllow/deleteAt 两能力上行——判据单源
  // ChatBranchPolicy.canDeleteAt，确认弹窗在本件 confirmDelete，执行落
  // ChatBranchCtrl.deleteMessage
  onDeleteMsg: () => void;
}

// 消息「更多」菜单内容（形制照会话卡菜单先例 = 普通 MenuItem；删除项本仓先例不用红字——
// 红字形态本仓无先例，观感待定项登记变更记录不预写）。重试两菜单项与「其他回答」项已退役
// ——重试唯一入口 = 气泡重试键（本文件 retryFromBubble，全答案行可用），其他回答唯一入口 =
// 行内步进器（计数位开面板）。★ 2026-11-05 菜单笔：原「复制正文 / 查看正文」body 分支随两处
// 省略号入口退役整段删除。★ 2026-11-15 续写收入菜单笔：「续写」项居首（生成动作族，仅
// 可续写的助手轮尾行渲染），图标沿用原行内键 arrow_down_to_line。
@Builder
export function ChatMessageMenuBuilder(params: ChatMessageMenuCallbacks) {
  Menu() {
    // 「续写」居首（生成动作族居前、消息操作族居后）；结构性隐藏 = 不可续写行整项不渲染
    //（showContinue 判据见 callbacks 注释），user 行恒不渲染
    if (params.showContinue) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
        content: '续写' })
        .onClick(() => {
          params.onContinue();
        })
    }
    if (params.showEdit) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        content: '编辑' })
        .onClick(() => {
          params.onEdit();
        })
    }
    // 独立会话 fork 入口（物化前缀与附件为独立副本）；位置在「编辑」之后、「删除消息」之前
    if (params.showCopyNew) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.rectangle_on_rectangle')),
        content: '复制为新会话' })
        .onClick(() => {
          params.onCopyNew();
        })
    }
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      content: '删除消息' })
      .onClick(() => {
        params.onDeleteMsg();
      })
  }
  // 统一固定宽 MENU_UNIFIED_WIDTH（决明「宽度适当增大」拍板，即《菜单与二级菜单》§3.2
  //「新增消费方须先拍板」之拍板）；判据同步 assert-ui-consistency 70-14 组与规范
  //（一律同改，禁只改本处）
  .width(MENU_UNIFIED_WIDTH)
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 消息「更多」菜单节点宿主（AppMenuHost 薄壳；open 按消息 id 拼锚点——callbacks 由
// ChatPage 在点击一刻构造，可闭包捕获该消息上下文）
export class ChatMessageMenuHost extends AppMenuHost<ChatMessageMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ChatMessageMenuCallbacks): ComponentContent<ChatMessageMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ChatMessageMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（msgId = 目标消息 id，锚点 = 气泡底栏「更多」键；材质同页面「更多」菜单）
  open(uiContext: UIContext, callbacks: ChatMessageMenuCallbacks, msgId: string,
    immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MESSAGE_MENU_ANCHOR_PREFIX + msgId,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// ═══ 消息菜单接线域 ═══ 职责一句话：**消息「更多」菜单的节点生命周期、回调组装与动作上行
// + 行内重试入口编排**（气泡重试键的「过闸 → 起轮」编排落本件 retryFromBubble——判据与
// 理由文案单源在 ChatBranchPolicy〔页面经 ChatBranchCtrl 上行呈报〕，本件不重复判据）。
// 依赖方向：本件 → ChatDataSource/ChatMessageCompose（组件层视图模型）单向；不 import
// ChatBranchCtrl（动作经 refs 回调上行页面，防菜单域与编排域互缠）

// 菜单接线 refs（页面注入；闭包延迟求值，同 loadCtrl/branchCtrl 姿势）
export interface ChatMessageMenuRefs {
  dataSource: () => ChatDataSource;
  ui: () => UIContext;
  immersiveLevel: () => number;
  // 目标节点图身份（'' = 不可锚；判据单源 = ChatBranchCtrl.nodeIdOf——禁止本件另判）
  nodeIdOf: (msg: ChatMessage) => string;
  // 重试编排拆「过闸」与「起轮」两能力（branchCtrl.retryAllow / sendCtrl.retryAt）——
  // 唯一消费方 = 行内重试键（retryFromBubble）
  retryAllow: (msgId: string, nodeId: string) => Promise<BranchAllow>;
  retryAt: (nodeId: string) => void;
  onEdit: (msgId: string, nodeId: string) => void;
  // 独立会话 fork 上行（页面 → ChatBranchCtrl.copyToNewSession；边界 = 该消息节点）
  onCopyNew: (nodeId: string) => void;
  // 删除编排拆「过闸」与「执行」两能力（与 retry 同构）——判据单源 =
  // ChatBranchPolicy.canDeleteAt（页面经 ChatBranchCtrl 上行呈报），确认弹窗在本件
  //（confirmDelete），执行落 ChatBranchCtrl.deleteMessage（改库 + 换源重载）
  deleteAllow: (msgId: string, nodeId: string) => Promise<BranchAllow>;
  deleteAt: (nodeId: string) => void;
}

export class ChatMessageMenuCtrl {
  private host: ChatMessageMenuHost = new ChatMessageMenuHost();
  private refs: ChatMessageMenuRefs;

  constructor(refs: ChatMessageMenuRefs) {
    this.refs = refs;
  }

  // 首建（页面 aboutToAppear：节点就绪；callbacks 无消息上下文——open 前必然重建取真值）
  init(): void {
    this.host.init(this.refs.ui(), this.callbacksFor(null, 'none'));
  }

  // 成对释放（页面 aboutToDisappear——ComponentContent 不释放即泄漏）
  dispose(): void {
    this.host.dispose();
  }

  // 场景现读派生（单源；菜单每次打开与每个动作执行时都走本函数——不信快照）。
  // ★ 2026-11-05 菜单笔：非 opsHost 的 assistant 行由原 'body' 收敛为 'none'（无入口）
  private sceneOf(msg: ChatMessage): MessageMenuScene {
    if (msg.kind === 'user') {
      return 'user';
    }
    if (msg.kind === 'assistant') {
      if (msg.opsHost === true) {
        return 'round';
      }
      return 'none';
    }
    return 'none';
  }

  private toast(text: string): void {
    this.refs.ui().getPromptAction().showToast({ message: text });
  }

  // 弹出（页面 onMoreMenu 上行）：目标消息查不到也早退（理论不可达——菜单锚点由该行渲染）
  open(msgId: string): void {
    const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
    if (msg === null) {
      return;
    }
    // 按场景分派（round 与 user 同集合；none 拒开——渲染层本不挂键，此处兜底，禁「锚点路径
    // 还能误操作」）。★ 2026-11-05 菜单笔：body 场景已退役，分派只剩两档
    const scene: MessageMenuScene = this.sceneOf(msg);
    if (scene === 'none') {
      return;
    }
    this.host.open(this.refs.ui(), this.callbacksFor(msg, scene), msgId,
      this.refs.immersiveLevel());
  }

  // 回调组装（弹出前重建，值取弹出一刻快照）。动作闭包只捕获 msgId 与**当次 dataSource
  // 引用**，执行时重新 findMessage + 重新派生场景；消息丢失/来源已换/变为空文一律呈报不可用，
  // 禁拿捕获的旧 ChatMessage 执行
  private callbacksFor(msg: ChatMessage | null, scene: MessageMenuScene): ChatMessageMenuCallbacks {
    if (msg === null) {
      // 首建占位（open 前必重建）：show 全假 = 不渲染占位项，删除项照旧
      return {
        scene: 'none',
        showContinue: false, onContinue: (): void => {
        },
        showEdit: false, onEdit: (): void => {
        },
        showCopyNew: false, onCopyNew: (): void => {
        },
        onDeleteMsg: (): void => {
        }
      };
    }
    const nodeId: string = this.refs.nodeIdOf(msg);
    const msgId: string = msg.id;
    // 「续写」可见性现读（2026-11-15 续写收入菜单笔）：判据单源 = ChatContinueSupport.
    // continueVisibleBy（末条 + 非流式 + 有正文 + 未用工具 + 未判定不支持），连接可用性 =
    // 广播键现读（ChatPage.setConnInfo 写，菜单每次打开重建时取真值——不信快照）。user 行
    // 判据内天然为假不渲染；点击走 requestContinue 登记通道（与原行内键同一动作链）
    const continueOk: boolean = AppStorage.get<boolean>(CHAT_DS_CONTINUE_AVAILABLE_KEY) ?? false;
    const showContinue: boolean = continueVisibleBy(msg.kind, msg.streaming === true,
      msg.tail === true, msg.text, msg.serverToolsJson ?? '', continueOk);
    // 助手行的消息级操作随「本轮最终正文唯一化」收口——动作项（编辑 / 复制为新会话）对
    // 助手行只在 opsHost 为真时可见（与渲染层挂点判据同源）；user 行可见性不变
    const assistOps: boolean = msg.kind === 'user' ||
      (msg.kind === 'assistant' && msg.opsHost === true);
    return {
      scene: scene,
      showContinue: showContinue,
      onContinue: (): void => {
        requestContinue(msgId);
      },
      showEdit: assistOps,
      onEdit: (): void => {
        this.refs.onEdit(msgId, nodeId);
      },
      // （边界合法集 = user / 已收尾 assistant，判据单源在 canForkAt；
      // 此处只做结构性区分，可用性由点击后过闸呈报）
      showCopyNew: assistOps,
      onCopyNew: (): void => {
        this.refs.onCopyNew(nodeId);
      },
      onDeleteMsg: (): void => {
        this.deleteFromMenu(msgId, nodeId);
      }
    };
  }

  // 行内重试入口（重试唯一入口 = 气泡重试键——ChatPage.onRetryMsg 上行；目标 = 任意已收尾
  // 助手轮，末条底栏键 / 历史答案行键 / 空正文状态行键三形态共用）：现读目标 → 图身份解析
  // → retryRound（判据先行：理由文案单源在 ChatBranchPolicy，经 retryAllow 呈报）→ 过闸才
  // 交重试域起轮
  retryFromBubble(msgId: string): void {
    const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
    if (msg === null || msg.kind !== 'assistant') {
      return; // 目标已不在视图（重载冲掉等）——静默（键由该行渲染，理论不可达）
    }
    const nodeId: string = this.refs.nodeIdOf(msg);
    this.retryRound(msgId, nodeId);
  }

  // 重试编排：判据先行（理由文案单源在 ChatBranchPolicy，经 retryAllow 呈报），过闸经二次
  // 确认弹窗（决明拍板「点重试先弹确认再生成」——防误触起轮）才交重试域起轮
  private retryRound(msgId: string, nodeId: string): void {
    if (nodeId === '') {
      this.rejectEmptyAnchor();
      return;
    }
    this.refs.retryAllow(msgId, nodeId)
      .then((allow: BranchAllow): void => {
        if (!allow.allowed) {
          this.toast(allow.reason);
          return;
        }
        this.confirmRetry(nodeId);
      })
      .catch((e: Object): void => {
        this.toast('重试准备失败：' + (e as Error).message);
      });
  }

  // 重试二次确认（决明拍板）：过闸通过后弹官方确认弹窗——UIContext showDialog（坑64 只禁
  // showAlertDialog 槽内形态，promptAction.showDialog 聊天页已有先例）。确认键 = 「重试」
  //（NORMAL 主色——重试非破坏动作，原回复保留在原分支）；确认才起轮，取消/弹窗异常均不起轮
  //（弹层材质走 overlayMaterial 弹层族口径）。
  private confirmRetry(nodeId: string): void {
    this.refs.ui().getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '重试本轮回复',
      message: '将重新发送本轮消息并生成新回复，原回复保留。',
      buttons: [
        { text: '取消', color: $r('sys.color.font_secondary') },
        { text: '重试', color: $r('sys.color.font_primary') }
      ]
    })
      .then((choice: promptAction.ShowDialogSuccessResponse): void => {
        if (choice.index === 1) { this.refs.retryAt(nodeId); }
      })
      .catch((e: Object): void => {
        // 弹窗异常不起轮（宁可不重试，与清空排队确认同口径）；记录即走
        hilog.warn(DOMAIN, TAG, '重试确认弹窗异常：%{public}s', (e as Error).message);
      });
  }

  // 空锚的统一呈报（轮尾重生入口：不可锚即错锚——起轮会落到别处；文案单源 =
  // identityGate，与 ChatBranchCtrl.rejectEmptyAnchor 同口径）
  private rejectEmptyAnchor(): void {
    this.toast('这条消息的位置信息还没就绪，暂不可用');
  }

  // 删除编排：空锚呈报 → 目标已不在当前对话（视图找不到 = 来源已换/已被删——宁拒不猜，
  // 禁拿捕获的旧消息上下文执行）→ 判据过闸（理由文案单源在 ChatBranchPolicy，本处只透传
  // reason）→ 二次确认弹窗
  private deleteFromMenu(msgId: string, nodeId: string): void {
    if (nodeId === '') {
      this.rejectEmptyAnchor();
      return;
    }
    const msg: ChatMessage | null = this.refs.dataSource().findMessage(msgId);
    if (msg === null) {
      this.toast('这条消息已不在当前对话中');
      return;
    }
    this.refs.deleteAllow(msgId, nodeId)
      .then((allow: BranchAllow): void => {
        if (!allow.allowed) {
          this.toast(allow.reason);
          return;
        }
        this.confirmDelete(nodeId);
      })
      .catch((e: Object): void => {
        this.toast('删除准备失败：' + (e as Error).message);
      });
  }

  // 删除二次确认（confirmRetry 同构——决明拍板「菜单动作先弹确认」现行形态；正文 =
  // DELETE_CONFIRM_MESSAGE 常量单源）。★ 确认键 = 「删除」**危险红**（dialog_confirm_red）
  //——官方 showDialog 弹窗按钮挂危险红为本仓**首创形态**（危险红语义向官方弹窗的移植），
  // 观感列决明真机验收关注点；取消/弹窗异常均不执行（宁可不删，与重试确认同口径）
  private confirmDelete(nodeId: string): void {
    this.refs.ui().getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '删除这条消息',
      message: DELETE_CONFIRM_MESSAGE,
      buttons: [
        { text: '取消', color: $r('sys.color.font_secondary') },
        { text: '删除', color: $r('app.color.dialog_confirm_red') }
      ]
    })
      .then((choice: promptAction.ShowDialogSuccessResponse): void => {
        if (choice.index === 1) { this.refs.deleteAt(nodeId); }
      })
      .catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, '删除确认弹窗异常：%{public}s', (e as Error).message);
      });
  }

  // 「重新生成本轮」宿主解析链已整段退役——重试由气泡重试键承载（目标行自身即宿主，无需
  // 解析）；AnswerChoice 件的宿主解析纯函数随唯一消费方退役同批删除。
  // ★ 2026-11-05 菜单笔：中间正文「复制正文 / 查看正文」两项动作方法、查看器回调绑定与失效
  // 文案常量随 body 场景整条退役——复制与查看统一由长按全文面板（MessageCopySheet）承载。
}
