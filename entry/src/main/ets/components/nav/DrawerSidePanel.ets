// 侧栏会话二级页（2026-11-18 决明拍板「伪侧边栏实际二级页」，2235 自绘 Overlay 抽屉整族
// 退役后定稿）：页面 = **完全正常的二级页**——PageShell 官方壳（工作区管理页同一配方：官方
// 标题栏 + 标题栏下方带 + 瞬显入场〔push animated=false，无系统转场〕），汉堡键栈空时 push，返回键/系统返回手势/右缘向内
// 左滑关闭。★ 2026-11-18 二次校正笔（真机实证）：首版自建 HdsNavDestination 壳时自加了
// titleMode(MINI) / hideBackButton / 根 translate 三个自造参数，导致标题栏不占位、带区被
// 压进状态栏与模糊区并裁切（dumpLayout 实证：徽章 21px、助手名 2px、List 节点整棵不在树里）。
// 改走 PageShell 后与工作区管理页同渲染管线，位置/材质/带高全部对齐。
// ★ 2026-11-18 2237 改判：官方返回键改经 PageShell.backKeyHidden 隐藏（官方 HdsNavDestination
// hideBackButton API，与 2235-b 自建壳自造参数不同——那次是壳本身错，这次是官方参数走官方壳），
// 返回动作自绘进标题栏右侧四键胶囊最右热区（close_sidebar 朝左图标），与首页 open_sidebar 朝右
// 进出配对；系统返回手势/右缘左滑关闭照旧。
// 页面结构（上→下）：标题栏行 = 助手行本体（首字徽章 + 助手名 + 四热区胶囊〔搜索|多选|设置|
// 返回〕，点名字区弹切换半模态；★ 2026-11-18 决明「把助手那排替换最上面标题」笔——原主标题
// 「会话」位置整栏交给本行，多选态换「已选 N 项」）→ 标题栏下带单行（「全部/收藏」分段胶囊
// + ＋新建圆键，胶囊宽 108 与四键胶囊热区同档、高 36，左右边距与标题栏键同取 16 规范）→ 会话列表
// （SideSessionList，渲染域直接复用一级会话页 SessionRows：同款 HdsListItemCard 卡片 +
// 横滑四键 + 长按菜单；原侧栏紧凑行与日期分组头随二级页化退役）→ 多选态底部批量条。多选态
// 收带（分段行让位），键位让位与批量动作集中批量条。
// 多选 + 批量删除域页内自持（2026-11-18 自 HomeNavigation 迁入——页内 @State 单源零透传）。
// · 助手切换半模态（bindSheet 挂页面根 PageShell——判据：合法树内 / 根不随数据销毁 /
//   isShow 与触发键同组件位；先例 = 工作区管理页 SheetHost）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial, ComponentContent } from '@kit.ArkUI';
import { ASSISTANT_DEFAULT_ID, ACTIVE_ASSISTANT_KEY, AssistantRow, queryAssistant }
from '../../common/store/AssistantDb';
import { AssistantListSnapshot, homeListWarmup } from '../../common/store/HomeListWarmup';
import {
  deleteConversations,
  listWorkspaceTmpGroups,
  nextMessageId
} from '../../common/store/ChatDb';
import { removeDraftsWithFiles } from '../chat/ChatDraftStore';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import {
  CHAT_FAV_SEG_ITEMS,
  SESSION_SELECT_COUNT_KEY,
  SESSION_SELECT_MODE_KEY
} from '../chat/ChatSessionList';
import { SIDE_SELECT_ALL_CMD_KEY } from '../chat/SessionMultiselectBar';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import {
  identityBg,
  identityFg,
  SEGMENT_BAR_BAND_HEIGHT,
  SEGMENT_BAR_BAND_TOP_INSET
} from '../../common/Theme';
import { SideSessionList, SIDE_FAV_ALL } from '../chat/SideSessionList';
import { searchBandContentTop } from '../SearchTopBand';
// 顶带几何常量（与工作区页同源：带底→内容间距 24 单源取 WORKSPACE_BAND_CONTENT_GAP——
// 本页带内容高改单行 36 档后不再消费两行档 88）
import { WORKSPACE_BAND_CONTENT_GAP } from '../settings/WorkspaceBreadcrumb';
import { SegmentBar } from '../SegmentBar';
import { SessionMultiselectActionBar } from '../chat/SessionMultiselectBar';
import { AssistantSwitchPanel } from '../assistants/AssistantSwitchPanel';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';
import { PageShell } from '../../common/PageShell';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import {
  TitleBarRoundKey,
  TitleBarQuadCapsule,
  TITLE_BAR_EDGE_INSET,
  TITLE_KEY_HEIGHT
} from '../TitleBarKeys';
import {
  ROUTE_ASSISTANT_PAGE,
  ROUTE_SETTINGS_PAGE,
  ROUTE_SESSION_SEARCH_PAGE
} from '../../common/RouteNames';

// 助手行徽章（vp）：★ 2026-11-18 键换位 + 三键胶囊笔轻升 28→32——右端胶囊高 36 对 28
// 落差 12 过大，32 回到 8（= 原 36 键对 28 徽章的同档比例），头部重量只微增（决明拍板
// 「轻升一档恢复比例」案）；原「与侧栏会话项 24vp 同档」判随头部升档改判。★ 同日「助手行
// 替换标题」笔：本值随行迁入标题栏覆盖层（56vp 标题栏内 32 徽章 + 18fp 名字垂直居中，
// 窄屏 320vp 名字区仍余 ~78vp 容四字，决明「放不下可不放头像」的兜底不必启用）
const PANEL_BADGE_SIZE: number = 32;
// 侧栏「全部/收藏」分段胶囊定宽（vp，2026-11-18 优化③换装笔立 150；同日缩 20%→120；
// 2237 再缩到 108 = 三键紧凑热区基准宽〔36×3〕）：官方分段组件无宽度参数（宽度 = 父容器宽，
// 见 SegmentBar build 注释），须由外层定宽容器约束。同日最右加返回热区后四键胶囊实际宽
// 144（36×4），本值只保证两排左右缘同取 16 内距对齐，**不再是「与胶囊同宽」**——勿按
// 四键宽回改（108 下两选项各 54vp，「全部/收藏」两字仍舒展、窄屏余量更宽松）。
// ★ 禁复用 TITLE_CENTER_ZONE_*——其 '39%' 基准是宿主容器宽跨语义域值抄本陷阱（方案档 §8-4）
const SIDE_SEGMENT_WIDTH: number = 108;
// 多选批量条与导航条呼吸（vp）：条高 56 的末端让位由 SessionRows 自带
//（MULTISELECT_BAR_CLEARANCE 56 + LIST_TAIL_GAP 16 = 72，与条高 + 上下各 8 同值），本页
// 只补浮条与避让区的 8vp 呼吸
const PANEL_MULTI_BAR_GAP: number = 8;
// 标题栏覆盖层左侧内距（vp）：2237 隐藏官方返回键、返回自绘进右侧四键胶囊后，覆盖层左侧
// 不再需要给官方返回键让位——收归官方标题栏 end padding 16（TITLE_BAR_EDGE_INSET 单源）。
// 原值 = edge16 + 返回键40 + 键距8 = 64（为官方返回键留位），随本笔退役。
const SIDE_TITLE_BACK_ZONE: number = TITLE_BAR_EDGE_INSET;

// ── 批量删除确认弹窗节点宿主（V1 域编程式弹窗：全局 @Builder + wrapBuilder，先例 =
//    AppMenuHost；params 须 Object 子型满足 ComponentContent 约束；自 HomeNavigation 迁入）──
interface SideConfirmParams {
  title: string;
  message: string;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
}

@Builder
function SideConfirmHost(params: SideConfirmParams) {
  ConfirmDialog({
    title: params.title,
    message: params.message,
    confirmLabel: params.confirmLabel,
    onCancel: params.onCancel,
    onConfirm: params.onConfirm
  })
}

@Component
export struct DrawerSidePanel {
  // 顶部让位（vp，PageMap 注入 = 主区同口径 titleBarInset：状态栏 + MINI 标题栏 56 +
  // 蒙层下延 16）。本值只参与 contentTop 单源算式；标题栏避让由 PageShell 自己承担
  @Prop topPad: number = 0;
  // 底部让位（vp，PageMap 注入 = 避让区高）
  @Prop bottomPad: number = 0;
  // 当前主区会话 id（★ 2026-11-18 会话卡统一笔后不再用于列表高亮——渲染域与一级页
  // SessionRows 同件、无选中态视觉；本值保留为删除「命中主区会话换轨」判据，批量删除与
  // 单行删除共用。PageMap 构造期定值——页面在场期间主区 id 只经本页动作改变〔点行即弹页 /
  // 删除走 onActiveSessionDeleted〕，无中途刷新面）
  @Prop selectedConvId: string = '';
  // 官方路由栈（PageMap 注入引用——设置/助手/会话搜索三入口与「管理助手」直持 push）
  pathStack: NavPathStack = new NavPathStack();
  // 点会话回首页上行（HomeNavigation.openSession 的 drawer 分支——revealConversation
  // 清栈回对话首页，本页随之弹出）
  onOpenSession: (conversationId: string, presetTitle?: string) => void = () => {
  };
  // 新建会话上行（助手行右端「＋」；HomeNavigation.newConversation 的 drawer 分支）
  onNewConversation: () => void = () => {
  };
  // 删除命中主区会话上行（本页删除链）：宿主只换主区会话态（markFreshConversation +
  // activeConvId），不清栈不弹页——本页留守继续操作列表
  onActiveSessionDeleted: (freshId: string) => void = () => {
  };
  // 页面存活守卫（1712 全站纪律）：退场后迟到的删除回执不写 @State、不上行（助手名查询链
  // 随行迁入标题栏覆盖层组件，其自持同款守卫）
  private departed: boolean = false;
  // 首显闸（★ 2026-11-18 侧栏首帧笔）：首次显示不重复广播重拉——列表 aboutToAppear 已发起
  // 种子 + 校准查询，再叠一次广播 = 同一列表两次查询并行（SideSessionList 未迁底栏重拉闩，
  // 见其头注释）；从子页 pop 回来的后续 onShown 照常广播（列表不重挂，必须靠它重拉）。
  // 非状态变量，不驱动 UI。
  private firstShown: boolean = true;
  // 沉浸光感总档（顶带材质随档：强档 −1 后落 THIN，与同排分段胶囊/搜索带同厚度）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 收藏分段（0 全部 / 1 收藏）：分段行在标题栏下带、列表经 @Prop 消费做内存过滤
  @State private favSegment: number = SIDE_FAV_ALL;
  // ── 多选域（2026-11-18 自 HomeNavigation 迁入，页内 @State 单源）──
  @State private multiSelectMode: boolean = false;
  @State private selectedIds: string[] = [];
  // 批量删除在途（批量条删除键禁用反馈）
  @State private deleting: boolean = false;
  // 侧栏当前可见会话行数（批量条全选两态图标判据 = 已选数与行数比对；列表上行）
  @State private visibleRowCount: number = 0;
  // 删除确认弹窗节点（编程式弹窗：open 与 dispose 成对，见 closeConfirm；autoCancel 关
  // 防遮罩绕过关闭链——确认/取消两键都经回调收口释放）
  private confirmNode: ComponentContent<SideConfirmParams> | null = null;
  // 助手快速切换半模态可见性（`$$` 双向；关闭-再开协调省略——单页低频开合无并发面）
  @State private switchSheetShow: boolean = false;

  // 列表内容顶部让位（算式单源 = searchBandContentTop；多选态分段带收起 → 归 topPad——
  // 与工作区管理页 contentTop 同款；本页带内容高 = 单行 36 档 SEGMENT_BAR_BAND_HEIGHT）
  private contentTop(): number {
    if (this.multiSelectMode) {
      return Math.max(this.topPad, 0);
    }
    return Math.max(searchBandContentTop(this.topPad, WORKSPACE_BAND_CONTENT_GAP,
      SEGMENT_BAR_BAND_HEIGHT), 0);
  }

  aboutToDisappear(): void {
    // 退场置位（与查询发起/删除链成对）：迟到的回执早退
    this.departed = true;
    // 弹窗节点释放（幂等：与 open 成对——确认/取消/关页三路收口）
    this.closeConfirm();
    // 多选广播撤销（页没了选中集不得残留——原「收起侧栏即退多选」语义承接）
    if (this.multiSelectMode) {
      this.exitMultiselect();
    }
  }

  // ── 多选域（自 HomeNavigation 迁入；广播键仍走全局——tabs 侧多选守卫与标题栏「已选 N 项」
  //    订阅同一对键）──
  // 多选键（开关语义）：未多选 = 进入（勾选 + 广播两键，计数显式归零防残留）；多选中再点 =
  // 退出。退出通道三条——再多选键 / 批量条取消 / 关页（aboutToDisappear）
  private toggleMultiselect(): void {
    if (this.multiSelectMode) {
      this.exitMultiselect();
      return;
    }
    this.multiSelectMode = true;
    this.selectedIds = [];
    AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, true);
    AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, 0);
  }

  // 勾选切换（列表上行；计数广播随选集变化）
  private toggleSelect(id: string): void {
    if (this.selectedIds.includes(id)) {
      this.selectedIds = this.selectedIds.filter((i: string): boolean => i !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
    AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, this.selectedIds.length);
  }

  // 整组选集替换（全选指令的列表回执）：行集在列表侧（分段过滤态），全选两态判定与产集由
  // 列表经 nextSelectAllIds 算好后整组上行
  private setSelected(ids: string[]): void {
    this.selectedIds = ids;
    AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, ids.length);
  }

  // 全选/全不选（批量条左键 → 一次性命令键下发列表侧执行——行集在列表，坑3 口径多层宿主链
  // 零透传；命令键常量在 SessionMultiselectBar 导出）
  private toggleSelectAll(): void {
    AppStorage.setOrCreate<number>(SIDE_SELECT_ALL_CMD_KEY,
      (AppStorage.get<number>(SIDE_SELECT_ALL_CMD_KEY) ?? 0) + 1);
  }

  // 退出多选（取消键 / 删除成功后 / 关页兜底）：清选择 + 撤广播
  private exitMultiselect(): void {
    this.multiSelectMode = false;
    this.selectedIds = [];
    AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, false);
    AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, 0);
  }

  // 弹窗节点释放（幂等：与 open 成对——确认/取消/关页三路收口）
  private closeConfirm(): void {
    if (this.confirmNode !== null) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.confirmNode);
      } catch (e) {
        // 已关/未弹出等状态异常不打断释放链
      }
      this.confirmNode.dispose();
      this.confirmNode = null;
    }
  }

  // 批量删除确认（批量条主操作；临时区级联拦截句同底栏链）——编程式弹窗
  private confirmDeleteSelected(): void {
    if (this.selectedIds.length === 0 || this.deleting) {
      return;
    }
    const tmpGroups = listWorkspaceTmpGroups();
    let tmpHit = false;
    for (const group of tmpGroups) {
      if (this.selectedIds.indexOf(group.conversationId) >= 0) {
        tmpHit = true;
        break;
      }
    }
    this.closeConfirm();
    const ui = this.getUIContext();
    // 字面量须显式类型（arkts-no-untyped-obj-literals——wrapBuilder 泛型推断不达字面量）
    const params: SideConfirmParams = {
      title: '删除会话',
      message: '将彻底删除选中的 ' + this.selectedIds.length
      + ' 个会话及其全部聊天记录，不可恢复。'
      + (tmpHit ? '选中会话的临时文件将一并删除。' : ''),
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.closeConfirm();
        this.deleteSelected();
      },
      onCancel: (): void => {
        this.closeConfirm();
      }
    };
    this.confirmNode = new ComponentContent(ui, wrapBuilder(SideConfirmHost), params);
    ui.getPromptAction().openCustomDialog(this.confirmNode, {
      autoCancel: false,
      alignment: DialogAlignment.Center
    }).catch((e: Error): void => {
      // 弹出失败即释放节点防泄漏（组件域日志通道无先例，静默降级）
      this.closeConfirm();
    });
  }

  private async deleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0 || this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      const ids: string[] = this.selectedIds;
      await deleteConversations(ids);
      removeDraftsWithFiles(ids);
      // 数据层动作完成后、UI 写段前判存活（1712 纪律：判守只放 UI 动作前，不夹数据层之间）
      if (this.departed) {
        return;
      }
      // 删除的会话若正是主区会话：主区换新会话态（被删会话不可常驻主区）——上行宿主换轨，
      // 本页留守（不清栈不弹页）
      if (ids.indexOf(this.selectedConvId) >= 0) {
        // 替换 id 同属本地新造——顺手标记，避免主区还要走一段空白壳
        const freshReplacementId: string = nextMessageId('conv');
        this.onActiveSessionDeleted(freshReplacementId);
      }
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + ids.length + ' 个会话' });
      this.exitMultiselect();
    } catch (e) {
      if (!this.departed) {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      }
    } finally {
      this.deleting = false;
    }
  }

  // 助手切换面板内容（坑51：bindSheet builder 位挂组件内 @Builder）
  @Builder
  SwitchSheet() {
    AssistantSwitchPanel({
      bottomInset: this.bottomPad,
      onManage: (): void => {
        this.switchSheetShow = false;
        this.pathStack.pushPathByName(ROUTE_ASSISTANT_PAGE, null);
      },
      onClose: (): void => {
        this.switchSheetShow = false;
      }
    })
  }

  // ── 标题栏覆盖层（坑30/规范 §4：stackBuilder 必须是组件内 @Builder 承载的组件；整栏铺在
  //    返回键上方，空白区 Transparent 透传）──
  // 2026-11-18 决明「把助手那排替换最上面标题」笔：主标题位整栏交给助手行本体（徽章 + 名 +
  // 三热区胶囊），点名字区弹切换半模态、胶囊三键各直达；多选态换「已选 N 项」纯文字。
  // 刷新走覆盖层组件自订阅（坑16：@Prop 沿 titleBarStack 链不保刷新，见 SidePanelTitleRow）。
  @Builder
  TitleBarOverlay() {
    SidePanelTitleRow({
      onOpenSwitchSheet: (): void => {
        this.switchSheetShow = true;
      },
      onOpenSettings: (): void => {
        this.pathStack.pushPathByName(ROUTE_SETTINGS_PAGE, null);
      },
      onOpenSearch: (): void => {
        this.pathStack.pushPathByName(ROUTE_SESSION_SEARCH_PAGE, null);
      },
      onToggleMultiselect: (): void => {
        this.toggleMultiselect();
      },
      onBack: (): void => {
        this.pathStack.pop();
      }
    })
  }

  // ── 页壳标题栏下带内容（坑30：bottomBuilder 必须组件内 @Builder——builder 经官方 napi
  //    直接调用，全局化即 this undefined 闪退）──
  // 单行带（2026-11-18 键统一笔后）：仅「全部/收藏 + ＋新建」分段行；带高 = inset 8 + 内容
  // 36 = 44（SEGMENT_BAR_BAND_HEIGHT 单源给内容高）。

  // 带内分段行：分段胶囊（标题带档 36 档，与三键胶囊同高）+ ＋新建圆键（紧凑档 36×36）。
  // SegmentBar（materialPinned 恒光感——本带在标题栏生效区内）；定宽 Column 逼胶囊缩短
  //（SegmentBar 无 width 参数）。favSegment 真源链零改（@State 直传 $favSegment；过滤单源
  // 仍在 SideSessionList）。
  // ★ 2026-11-18 边距对齐笔（决明问「上面标题左右键是否按规范、若是则下排与上对齐」）：
  // 标题行左右键 = 官方返回键 / 三键胶囊，外缘均按官方标题栏 end padding 16 排版
  //（TITLE_BAR_EDGE_INSET 单源）；本行原 12/12 内收，现统一 16/16——分段胶囊左缘与返回键
  // 左缘齐、＋键右缘与三键胶囊右缘齐，两排纵向成一条边线。
  @Builder
  SegmentRowBuilder() {
    Row({ space: 8 }) {
      Column() {
        SegmentBar({
          items: CHAT_FAV_SEG_ITEMS,
          selectedIndex: $favSegment,
          materialPinned: true,
          emphasizeSelected: true,
          bandTier: true
        })
      }
      .width(SIDE_SEGMENT_WIDTH)
      .height(SEGMENT_BAR_BAND_HEIGHT)
      Blank()
      // ＋新建键：36×36 紧凑圆键与分段胶囊同高（2026-11-18 决明「高度大小改为与三键胶囊
      // 统一」）；材质基准 REGULAR（强档落 THIN），与分段胶囊同一可见厚度
      TitleBarRoundKey({
        icon: $r('sys.symbol.plus'),
        label: '新建对话',
        onTap: (): void => {
          this.onNewConversation();
        },
        immersiveLevel: this.immersiveLevel,
        materialStyle: uiMaterial.ImmersiveStyle.REGULAR,
        compact: true
      })
    }
    .width('100%')
    .height(SEGMENT_BAR_BAND_HEIGHT)
    .padding({ left: TITLE_BAR_EDGE_INSET, right: TITLE_BAR_EDGE_INSET })
  }

  // 标题栏下带根（与工作区 WorkspaceTopBand 同款三件：全高 + 顶部下移 inset + 整带命中透传）：
  // 单行内容 36 由 PageShell titleBarBottomHeight 单源给定，带高 = 8 + 36 = 44
  @Builder
  BandBottomBuilder() {
    Row() {
      this.SegmentRowBuilder()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .padding({ top: SEGMENT_BAR_BAND_TOP_INSET })
    // 整带命中透传：带体不挡下方列表拖动，行内键自身仍可点（工作区页同款）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 页面内容：会话列表铺满 + 多选批量条浮层（列表从条下穿过，条体只遮自身胶囊）。
  // ★ 结构照工作区管理页 Content（已知良好范式）：列表装进 Column 再与批量条同层进 Stack，
  // 批量条不挂 zIndex——条根自带全高透明容器 + Transparent 空白穿透，层级由 Stack 子序保证。
  // 2026-11-18 多选态滑不动修复笔：原直挂列表组件 + zIndex(2) 形态下批量条层吃掉列表拖动，
  // 改为参考页逐项同构。
  // ★ 2026-11-18 会话卡统一笔：列表渲染域换 SessionRows（与一级会话页同件），末端让位
  //（尾呼吸 16 + 多选批量条 56）由该件 contentEndOffset 自带，本页只传避让区高。
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        SideSessionList({
          topPad: this.contentTop(),
          bottomPad: this.bottomPad,
          favSegment: this.favSegment,
          multiSelectMode: this.multiSelectMode,
          selectedIds: this.selectedIds,
          // 单行删除命中主区会话时换轨（与批量删除同语义；真源 = 本页 selectedConvId）
          selectedConvId: this.selectedConvId,
          onActiveSessionDeleted: (freshId: string): void => {
            this.onActiveSessionDeleted(freshId);
          },
          onOpen: (conversationId: string, presetTitle?: string): void => {
            this.onOpenSession(conversationId, presetTitle);
          },
          onOpenNewSession: (): void => {
            this.onNewConversation();
          },
          onToggleSelect: (id: string): void => {
            this.toggleSelect(id);
          },
          onSetSelected: (ids: string[]): void => {
            this.setSelected(ids);
          },
          onVisibleCount: (count: number): void => {
            this.visibleRowCount = count;
          }
        })
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      if (this.multiSelectMode) {
        SessionMultiselectActionBar({
          allSelected: this.visibleRowCount > 0 && this.selectedIds.length === this.visibleRowCount,
          deleting: this.deleting,
          barBottom: this.bottomPad + PANEL_MULTI_BAR_GAP,
          onCancel: (): void => {
            this.exitMultiselect();
          },
          onPrimary: (): void => {
            this.confirmDeleteSelected();
          },
          onToggleAll: (): void => {
            this.toggleSelectAll();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 完全正常的二级页（工作区管理页同一配方，2026-11-18 二次校正笔）：PageShell 官方壳
    // （HdsNavDestination + PageBackground 铺底 + 官方标题栏：主标题 + 标题栏下方带）+
    // 瞬显入场〔push animated=false——系统默认转场时长不可控且无结束信号〕（撤销首版自绘
    // 反向转场——自绘位移通道需在页面根挂 translate，实测破坏标题栏避让与带高，且动画非
    // 官方观感）+ 退场走官方动画：返回键/系统返回手势关闭（右缘向内左滑等价「左滑收起」），
    // 点卡关闭 = 瞬收（revealConversation clear(false)，现状）。
    // ★ 2026-11-18 「助手行替换标题」笔：主标题位由 TitleBarOverlay 整栏接管（助手行本体
    // = 标题；多选态换「已选 N 项」），官方 mainTitle 传空串（覆盖层在位时 hdsTitleBarOptions
    // 亦会置空，双保险防旧标题缝里闪现）；多选态只收下带（分段行让位），标题位仍由覆盖层
    // 渲染计数。
    PageShell({
      title: '',
      // 2237：官方返回键隐藏——返回动作自绘进标题栏覆盖层最右热区（四键胶囊），
      // 官方返回链仍经 pathStack.pop 走（见 SidePanelTitleRow.onBack）
      backKeyHidden: true,
      titleBarStack: (): void => {
        this.TitleBarOverlay();
      },
      titleBarBottomHidden: this.multiSelectMode,
      titleBarBottom: (): void => {
        this.BandBottomBuilder();
      },
      titleBarBottomInset: SEGMENT_BAR_BAND_TOP_INSET,
      titleBarBottomHeight: SEGMENT_BAR_BAND_HEIGHT,
      // 页面显示（含从子页 pop 回来）：重拉会话列表（坑25「栈下层 @StorageProp 不刷新」
      // 口径）。★ 2026-11-18 侧栏首帧笔：首次显示跳过——列表 aboutToAppear 已发起种子与
      // 校准查询，这里再叠一次广播 = 稳态下同一列表两次查询并行；从子页返回的后续显示
      // 照常广播（列表不重挂，必须靠它重拉）。
      onShown: (): void => {
        if (this.firstShown) {
          this.firstShown = false;
          return;
        }
        AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
          (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      },
      content: (): void => {
        this.Content();
      }
    })
      // 助手切换半模态（挂页面根 PageShell——判据：合法树内 / 根不随数据销毁 / 与触发键同组件位）
      .bindSheet($$this.switchSheetShow, this.SwitchSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.switchSheetShow = false;
        }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }
}

// ═══ 标题栏行（2026-11-18 决明「把助手那排替换最上面标题」笔；★ 2237 改四键胶囊）═══
// 主标题位 = 助手行本体：首字徽章 + 助手名（点名字区弹切换半模态）+ 四热区紧凑胶囊
// 〔搜索|多选|设置|返回〕（各自直达会话搜索 / 多选开关 / 设置 / 返回；最右返回为 2237 新增，
// 设置键从右往左第二个〔2237 决明排位指令〕。官方返回键已隐藏）。多选态换「已选 N 项」纯文字、胶囊让位（多选模式契约：原键位一律让位、
// 动作集中批量条——退出走批量条取消键）。
// · 刷新独立：@StorageProp 自订阅助手 id / 列表重拉 tick / 多选两键 / 光感档 / 深浅色——
//   官方 stackBuilder 覆盖层沿 @Prop 链不保刷新（坑16 正解，先例 = ChatTitleBarOverlay），
//   页内 @State 不得直喂。列表重拉 tick 是栈下层返回的补刷通道（助手 id 的 @StorageProp
//   本地值在覆盖期间可能停旧，名字与徽章色一律现读 AppStorage）。
// · 布局：全宽全高覆盖层（官方标题栏 56vp 内垂直居中）+ 左右缘官方内距 16（SIDE_TITLE_BACK_ZONE
//   = 16，2237 官方返回键隐藏后左避让收归 16）；空白区 Transparent 透传（规范 §4）。
//   ★ 点行开半模态的 onClick 只挂名字区容器、不挂整栏根：根挂点击会与四键胶囊最左搜索键
//   同击（旧口径为左侧返回键区同击，返回键隐藏后改判）。
// · 助手名查询 = 初查 + 助手切换 @Watch 重查（与页内原链同语义迁入；页侧不再持名）。
// ★ 2026-11-18 侧栏首帧笔：侧栏页每次新 push 都是全新组件实例，名字查询是异步的——先用
//   首帧种子直显（模块级上次解析结果 / 冷启动预热助手快照），再走 queryAssistant 单行复核；
//   种子只负责首帧不空白，改名/删行由复核自动纠正。
let assistantNameCacheId: string = '';
let assistantNameCacheText: string = '';

@Component
struct SidePanelTitleRow {
  // 点名字区 → 弹助手切换半模态（可见性归页持有）
  onOpenSwitchSheet: () => void = (): void => {
  };
  // 胶囊四热区（左→右）→ 会话搜索 / 多选开关 / 设置页 / 返回（页内 toggleMultiselect 单源；
  // 设置键在从右往左第二位〔2237 决明排位〕，返回为最右热区走 onBack）
  onOpenSettings: () => void = (): void => {
  };
  onOpenSearch: () => void = (): void => {
  };
  onToggleMultiselect: () => void = (): void => {
  };
  // 最右返回热区（2237）：上行 DrawerSidePanel.pathStack.pop 走官方返回链（与隐藏前的
  // 官方返回键同结果，只是触发位从左边移到胶囊最右）
  onBack: () => void = (): void => {
  };
  // 当前助手 id（切换广播改的是 id，名字须跟着重查——@Watch 必须挂本值上：原误挂名字上时
  // 只有查询回执自己改名才触发，切换助手后头部永远显示旧名）。★ 本值只作变更触发器：
  // 栈下层页面 @StorageProp 可能停旧（项目实证），名字查询与徽章取色的真值一律经
  // readActiveAssistantId() 现读 AppStorage。
  @StorageProp(ACTIVE_ASSISTANT_KEY) @Watch('reloadName') activeAssistantId: string =
    ASSISTANT_DEFAULT_ID;
  // 列表重拉广播（页面 onShown 自增 / 后台标题与删除广播同键）：补刷通道——侧栏页被设置页 /
  // 助手页盖住期间助手可能被切换，返回时本件按现读 id 重查名字（覆盖层沿 @Prop 链不保刷新，
  // 坑16 口径同源）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('reloadName') listReloadTick: number = 0;
  // 系统深浅色（身份色双档取色；原实参写死 0 = COLOR_MODE_DARK，浅色模式亦取深档——
  // 2026-11-18 自检轮修）
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 当前显示助手 id（现读值）：徽章取色 / 名字缓存命中的单源，不依赖 @StorageProp 本地值
  @State private displayAssistantId: string = ASSISTANT_DEFAULT_ID;
  // 多选两态（页内 toggleMultiselect / 勾选链写出的广播键——本件只读订阅）
  @StorageProp(SESSION_SELECT_MODE_KEY) selectMode: boolean = false;
  @StorageProp(SESSION_SELECT_COUNT_KEY) selectCount: number = 0;
  // 沉浸光感总档（胶囊壳体材质与「无」档底随档）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 助手名（查询回执；空串时徽章兜底「助」）
  @State private assistantName: string = '';
  // 覆盖层存活守卫（退场后迟到回执不写 @State）
  private departed: boolean = false;

  aboutToAppear(): void {
    this.displayAssistantId = this.readActiveAssistantId();
    this.seedAssistantName();
    this.reloadName();
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  // 当前助手 id 现读（不用 @StorageProp 本地值——栈下层期间可能停旧；切换面板/助手页
  // 两路都写 AppStorage 真值）
  private readActiveAssistantId(): string {
    return AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  }

  // 首帧名字种子（★ 2026-11-18 侧栏首帧笔）：① 模块级上次解析结果（同 id 命中——关侧栏
  // 再开最常见路径）；② 冷启动预热助手快照里的当前助手行（只读不消费——进程内第一次打开）；
  // ③ 都没有则留空走异步查询（最差 = 旧行为）。种子只负责首帧不空白，reloadName 仍会复核。
  private seedAssistantName(): void {
    const id: string = this.readActiveAssistantId();
    if (assistantNameCacheId === id && assistantNameCacheText !== '') {
      this.assistantName = assistantNameCacheText;
      return;
    }
    const warm: AssistantListSnapshot | null = homeListWarmup.peekAssistantSnapshotForSeed();
    if (warm === null) {
      return;
    }
    const hit: AssistantRow | undefined =
      warm.rows.find((row: AssistantRow): boolean => row.id === id);
    if (hit === undefined) {
      return;
    }
    this.assistantName = hit.name;
    assistantNameCacheId = id;
    assistantNameCacheText = hit.name;
  }

  private reloadName(): void {
    // 现读 id（非 @StorageProp 本地值）：栈下层返回 / 切助手两条来路统一走这里
    const id: string = this.readActiveAssistantId();
    this.displayAssistantId = id;
    // 助手切换（@Watch）先吃缓存直显，再单行查库复核（换到看过的助手不空一帧）
    if (assistantNameCacheId === id && assistantNameCacheText !== '') {
      this.assistantName = assistantNameCacheText;
    }
    queryAssistant(id)
      .then((row: AssistantRow | null): void => {
        if (this.departed) {
          return;
        }
        // 迟到回执代次守卫：查询发起后助手又切走（或页面被盖期间再切换）即丢弃——
        // 否则旧助手的名字/缓存会覆盖新助手
        if (this.readActiveAssistantId() !== id) {
          return;
        }
        const name: string = row !== null ? row.name : '默认助手';
        this.assistantName = name;
        assistantNameCacheId = id;
        assistantNameCacheText = name;
      })
      .catch((): void => {
        if (this.departed || this.readActiveAssistantId() !== id) {
          return;
        }
        // 查询失败不写缓存（DB 未就绪等瞬态不固化错误名，下一次进入重新查）
        this.assistantName = '默认助手';
      });
  }

  build() {
    Row({ space: 8 }) {
      if (this.selectMode) {
        // 多选态：计数标题（与工作区管理页同款标题语义；胶囊让位、退出走批量条取消键）
        Text('已选 ' + this.selectCount + ' 项')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      } else {
        // 名字区（徽章 + 名；点行弹切换半模态；右端胶囊键独立命中）
        Row({ space: 10 }) {
          Text(this.assistantName !== '' ? this.assistantName.substring(0, 1) : '助')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(identityFg(this.displayAssistantId, this.appColorMode))
            .width(PANEL_BADGE_SIZE)
            .height(PANEL_BADGE_SIZE)
            .borderRadius(8)
            .backgroundColor(identityBg(this.displayAssistantId, this.appColorMode))
            .textAlign(TextAlign.Center)
          Text(this.assistantName)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .height(TITLE_KEY_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.onOpenSwitchSheet();
        })
        // 四热区紧凑胶囊〔搜索|多选|设置|返回〕（144×36，几何 = TitleBarKeys 紧凑档单源）：
        // 2237 官方返回键隐藏后，返回自绘为最右热区（close_sidebar 箭头朝左，与首页
        // open_sidebar 箭头朝右进出配对），与前三键同高同材质成一条胶囊。
        // ★ 2237 排位微调：设置键从最左改从右往左第二个（决明指令），搜索与多选顺次左移一位
        TitleBarQuadCapsule({
          leftIcon: $r('sys.symbol.magnifyingglass'),
          leftLabel: '搜索会话',
          onLeftTap: (): void => {
            this.onOpenSearch();
          },
          midIcon: $r('sys.symbol.checkmark_circle'),
          midLabel: '多选会话',
          onMidTap: (): void => {
            this.onToggleMultiselect();
          },
          rightIcon: $r('sys.symbol.gearshape'),
          rightLabel: '设置',
          onRightTap: (): void => {
            this.onOpenSettings();
          },
          backIcon: $r('sys.symbol.close_sidebar'),
          backLabel: '返回',
          onBackTap: (): void => {
            this.onBack();
          },
          immersiveLevel: this.immersiveLevel
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: SIDE_TITLE_BACK_ZONE, right: TITLE_BAR_EDGE_INSET })
    // 整栏铺在返回键上方：空白区透传（规范 §4——默认档挡返回键）
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
