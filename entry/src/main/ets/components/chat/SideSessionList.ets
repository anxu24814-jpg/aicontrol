// 侧栏会话列表壳（2026-11-16 首页布局双形态笔新建；★ 2026-11-18 会话卡统一笔改判）：
// DrawerSidePanel 内的列表数据与动作域——读取链复用 HomeListWarmup 单源（按
// ACTIVE_ASSISTANT_KEY 过滤 + 生成中/草稿行合成全在快照内，与底栏列表同源不双发）。
// ★ 渲染域改为直接复用一级会话页 SessionRows（components/chat/ChatSessionRows.ets）：
// 侧栏已是真二级页，原先为抽屉横滑同轴冲突而设的「小徽章 + 单行标题」紧凑行与日期分组头
// 整族退役——会话卡形态（HdsListItemCard：36 徽章 + 标题/摘要/时间）、横滑四键（收藏 /
// 重命名 / 移动 / 删除）与长按菜单全部与一级会话页逐项同源；本件只留数据、过滤、多选与
// 四个动作（壳/渲染分层同 ChatSessionList），不再持有任何行/卡渲染代码。
// · 过滤链与一级页同序：收藏分段 → 多选态草稿行守卫（'__new__' 不可勾选、不被全选 sweep、
//   批量删除不连带）→ 可见集赋值；「已选 ⊆ 可见」条件清照 ChatSessionList.syncVisibleRows
//   原样（段值变 / 已选含不可见行两路触发，空选短路）。
// · 简化申报：底栏的 R2-c 滚动空闲闸不随迁——侧栏无「列表滑动中整表替换」的竞态痛点，
//   滚动控制器亦不再需要（PageShell 常显带无 dynamicHide 绑定，SessionRows 用内部 List
//   控制器）。★ R2-b 在途闩必须保留（2026-11-18 自检轮改判）：awaitSessionSnapshot 只在
//   启动预热 promise 在途时共享同一查询，预热消费后每次 reload 都是独立查询——同帧多次
//   广播（标题 tick / 删除 / 收藏重拉）会并发查出、乱序落地（旧结果覆盖新结果）。
// · 单行删除与批量删除同语义（2026-11-18 自检轮修）：删除命中主区会话时上行
//   onActiveSessionDeleted 换新会话态——原单行路径漏此链，主区会停在被删会话上。
// ★ 2026-11-18 侧栏首帧笔：aboutToAppear 先同步 seed 再异步校准——种子两源 = 冷启动一次性
//   预热快照（peek 消费）+ HomeListWarmup 最近一次成功快照（只读）；命中且过滤助手一致即
//   首帧落屏，reload 照常发出（stale-while-revalidate，真值以本次查询为准）。空种子不落，
//   避免「暂无会话」空态先于校准闪一帧；页面壳首显也已不再重复广播重拉（见 DrawerSidePanel
//   onShown 首显闸），首帧只保留本次校准一条查询。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIUtils } from '@kit.ArkUI';
import { ConversationRow, countWorkspaceTmpFiles, deleteConversations, nextMessageId,
  renameConversation, setConversationFavorite } from '../../common/store/ChatDb';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID } from '../../common/store/AssistantDb';
import { CONV_TITLE_TICK_KEY } from '../../common/TitleGen';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { cardDescColor } from '../../common/Theme';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../../common/AppPreferences';
import { recordSessionRecentConv } from '../../common/SessionSearch';
import { PROACTIVE_UNREAD_CONV_KEY, SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { homeListWarmup, SessionListSnapshot } from '../../common/store/HomeListWarmup';
import { SessionListRow, reconcileSessionRows } from './ChatSessionRowModel';
import { SessionRows } from './ChatSessionRows';
import { SessionMovePanel } from './SessionMovePanel';
import { ConfirmDialog } from './ConfirmDialog';
import { InputDialog } from './InputDialog';
import { sheetPanelOptions, SheetDetents } from './KimiSheetCommon';
import { NEW_DRAFT_KEY, removeDraftsWithFiles } from './ChatDraftStore';
import { hasHiddenSelection, nextSelectAllIds, SIDE_SELECT_ALL_CMD_KEY } from './SessionMultiselectBar';

// 收藏分段两值（侧栏自持——与底栏 favSegment 语义同源不同时在场，不共享状态）。
// ★ 2026-11-17 顶带笔导出：分段行迁到 DrawerSidePanel 的沉浸顶带（与助手行同一条
// 模糊区），状态提升到面板、本件经 @Prop 接收——值与过滤单源仍在本件纯函数
export const SIDE_FAV_ALL: number = 0;
export const SIDE_FAV_FAVORITE: number = 1;

@Component
export struct SideSessionList {
  // 页面存活守卫（退场迟到异步回调不写状态不上行；写库等数据层意图照常完成——
  // 判守只许放 UI 动作前，禁夹在数据层动作之间，1713 纪律）
  private departed: boolean = false;
  // 重拉在途闩 + 尾部补跑意图（与底栏 ChatSessionList R2-b 同机制）：awaitSessionSnapshot
  // 只在启动预热 promise 在途时共享查询，预热消费后每次 reload 都是独立查询——标题 tick /
  // 删除广播 / 收藏重拉等同帧多请求不叠发并发查询（乱序落地会让旧结果覆盖新结果），只记
  // 意图；收尾必补跑一次（禁丢弃：在途那查可能取不到意图背后的新写入）。
  private reloadInFlight: boolean = false;
  private reloadPending: boolean = false;
  // 列表顶部让位（vp，侧栏页头部排版下发——已含标题带 36 + 带底呼吸 24 的 contentTop 口径）
  @Prop topPad: number = 0;
  // 列表底部让位（vp；页壳下发避让区高。尾呼吸 16 与多选批量条 56 由 SessionRows
  // contentEndOffset 自带，本件不重复叠加）
  @Prop bottomPad: number = 0;
  // 多选态与已选 id（DrawerSidePanel 多选域下发——批量条在页面底部，勾选动作经
  // onToggleSelect 上行）。★ @Watch 挂 syncVisibleRows：可见集合成消费本值
  //（草稿行多选守卫），不挂则进出多选时 @Prop 更新只刷渲染面、可见集不重算——草稿行仍
  // 可见可勾、全选仍 sweep '__new__'（2226 D1 修复主路径断裂教训；先例 = 底栏
  // ChatSessionList selectMode @Watch('syncVisibleRows') 自挂）
  @Prop @Watch('syncVisibleRows') multiSelectMode: boolean = false;
  @Prop selectedIds: string[] = [];
  // 点行进会话上行（DrawerSidePanel.openSession 分支：标题预置 + 换主区会话 + 弹页）
  onOpen: (conversationId: string, presetTitle?: string) => void = () => {
  };
  // 草稿合成行点击上行（DrawerSidePanel.newConversation 分支）
  onOpenNewSession: () => void = () => {
  };
  // 多选勾选上行（DrawerSidePanel.toggleSelect）
  onToggleSelect: (id: string) => void = () => {
  };
  // 整组选集替换上行（全选指令回执——DrawerSidePanel.setSelected）
  onSetSelected: (ids: string[]) => void = () => {
  };
  // 可见行数上行（批量条全选两态图标判据——DrawerSidePanel.visibleRowCount）
  onVisibleCount: (count: number) => void = () => {
  };
  // 主区当前会话 id（DrawerSidePanel.selectedConvId 下发）：单行删除命中它时须与批量删除
  // 同语义换轨——否则主区留在已删会话上（DB 行已无，发送链会把它当无行会话复活）
  @Prop selectedConvId: string = '';
  // 删除命中主区会话上行（新造会话 id；宿主持新造标记 + 主区换轨，本页留守继续操作）
  onActiveSessionDeleted: (freshId: string) => void = () => {
  };
  // 收藏分段（状态提升到 DrawerSidePanel 沉浸顶带，本件只消费；@Watch 汇聚
  // syncVisibleRows 重算可见集——切换内存过滤不重查库）
  @Prop @Watch('syncVisibleRows') favSegment: number = SIDE_FAV_ALL;
  // 上次已同步的分段值（条件清判据①——syncVisibleRows 内逐次比较；初值 = 缺省段，挂载
  // 首帧无差异故不清空；非状态变量不驱动 UI。对应底栏 ChatSessionList.lastSyncedSegment
  // 同名成员同款手法）
  private lastSyncedSegment: number = SIDE_FAV_ALL;
  // 全选指令（DrawerSidePanel 批量条「全选」键下发；行集在本件——nextSelectAllIds 两态
  // 产集后整组上行）
  @StorageProp(SIDE_SELECT_ALL_CMD_KEY) @Watch('onSelectAllCmd') selectAllCmd: number = 0;
  // 刷新广播（与底栏同键：退页不断流收尾钩子 / 标题写回 / 移动落库 / 删除广播全族驱动重拉）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onReloadTick') reloadTick: number = 0;
  @StorageProp(CONV_TITLE_TICK_KEY) @Watch('onReloadTick') titleTick: number = 0;
  // 主动消息未读会话（红点判据，只读订阅）
  @StorageProp(PROACTIVE_UNREAD_CONV_KEY) unreadConvId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感总档（长按菜单材质与横滑键光感——SessionRows 标量透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 卡底透明度档位（与一级会话页同键同缺省；SessionRows 标量透传）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 全量行（快照产物；@Watch 汇聚重算可见集）
  @State @Watch('syncVisibleRows') private rows: SessionListRow[] = [];
  // 可见行（分段过滤 + 多选草稿守卫产物，渲染域数据源）
  @State private visibleRows: SessionListRow[] = [];
  @State private hintText: string = '';
  // 首拉完成闸（false = 首查在途——空态不闪现）
  @State private loaded: boolean = false;
  // 会话移动（长按菜单「移动到助手」：目标 id + 半模态，SessionMovePanel 整件复用零改动）
  @State private moveTargetId: string = '';
  @State private moveSheetShow: boolean = false;
  // 删除确认/重命名弹窗控制器（组件成员位——坑7：普通类成员构造 open 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  private renameCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 首帧种子先落（同步），随后照常现查校准（见文件头侧栏首帧笔）
    this.seedFromSnapshot();
    this.reload();
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  // 当前过滤助手 id（现读；与 HomeListWarmup.fetchSessionListSnapshot 的取值口径逐字同源，
  // 快照 activeId 直接比对即可）
  private activeAssistantId(): string {
    return AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  }

  // 首帧种子：冷启动一次性预热快照（消费）优先，miss 再取最近一次成功快照（只读）——命中
  // 且过滤助手一致即同步落屏。空种子不落（避免空态卡先于本次校准闪一帧；真「无会话」由
  // reload 回包后正常出空态）。种子只负责首帧不空白，reload 仍会校准（见文件头）。
  private seedFromSnapshot(): void {
    const activeId: string = this.activeAssistantId();
    // 预热快照一次性消费（与底栏 ChatSessionList 同语义）；助手不一致 = 旧助手行，丢弃后
    // 再试最近一次成功快照（后者可能属于当前助手）
    const warm: SessionListSnapshot | null = homeListWarmup.peekSessionSnapshot();
    if (warm !== null && warm.activeId === activeId) {
      this.applySeed(warm);
      return;
    }
    const last: SessionListSnapshot | null = homeListWarmup.peekLastSessionSnapshot();
    if (last !== null && last.activeId === activeId) {
      this.applySeed(last);
    }
  }

  // 种子落屏（空种子不落：避免空态卡先于本次校准闪一帧；真「无会话」由 reload 回包后正常出）
  private applySeed(seed: SessionListSnapshot): void {
    const rows: SessionListRow[] | null = reconcileSessionRows(this.rows, seed.queried,
      seed.activeId, seed.snippets);
    if (rows === null || rows.length === 0) {
      return;
    }
    this.commitRows(rows, seed, 'seed ok');
  }

  // 重拉（两广播键共用回调；同帧多请求由 reload 在途闩收敛，见成员注释）
  private onReloadTick(): void {
    this.reload();
  }

  private reload(): void {
    if (this.departed) {
      return;
    }
    // 在途闩：同帧多请求只记意图（机制见成员注释）；收尾单点必补跑一次
    if (this.reloadInFlight) {
      this.reloadPending = true;
      return;
    }
    this.reloadInFlight = true;
    homeListWarmup.awaitSessionSnapshot()
      .then((snap: SessionListSnapshot): void => {
        if (this.departed) {
          return;
        }
        // 行合成走单源 reconcileSessionRows（DB 行 + 运行态生成中标记 + 草稿打标与 '__new__'
        // 合成行——与底栏同链；按 id 逐行复用旧行，返回 null = 无变化跳过赋值）
        const rows: SessionListRow[] | null = reconcileSessionRows(this.rows, snap.queried,
          snap.activeId, snap.snippets);
        this.commitRows(rows, snap, 'reload ok');
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = (e as Error).message;
        this.loaded = true;
        hilog.error(0xD5A1, 'SideSessionList', 'reload failed: %{public}s', (e as Error).message);
      })
      .finally((): void => {
        this.finishReload();
      });
  }

  // 重拉收尾单点（成功 / 失败 / 种子覆盖三路汇合）：释闩 + 意图在场必补跑一次。
  // 退场后不再补跑（页面已死，查询无消费方）。
  private finishReload(): void {
    this.reloadInFlight = false;
    if (this.departed) {
      this.reloadPending = false;
      return;
    }
    if (this.reloadPending) {
      this.reloadPending = false;
      this.reload();
    }
  }

  // 快照落屏单点（种子同步路径与 reload 异步路径共用）：行赋值 + loaded 置真 + 清失败提示。
  // 空列表取证日志同帧落（★ 全空白排查笔）：行数与过滤助手同帧输出——侧栏全空时一眼区分
  //「快照 0 行（助手过滤/数据问题）」与「有行但没渲染（布局问题）」。
  private commitRows(rows: SessionListRow[] | null, snap: SessionListSnapshot,
    source: string): void {
    if (rows !== null) {
      this.rows = rows;
    }
    this.hintText = '';
    this.loaded = true;
    hilog.info(0xD5A1, 'SideSessionList',
      '%{public}s active=%{public}s queried=%{public}d rows=%{public}d fav=%{public}d',
      source, snap.activeId, snap.queried.length,
      rows !== null ? rows.length : this.rows.length, this.favSegment);
  }

  // 可见集重算（rows / favSegment / multiSelectMode 三 @Watch 汇聚唯一入口；可见会话行数
  // 同步上行——批量条全选两态判据的行集分母）。顺序与一级页 ChatSessionList 同构：
  // 收藏分段 → 多选草稿守卫 → 条件清 → 赋值。
  private syncVisibleRows(): void {
    const segmentRows: SessionListRow[] = this.favSegment === SIDE_FAV_FAVORITE
      ? this.rows.filter((row: SessionListRow): boolean => row.favorite)
      : this.rows;
    // 多选守卫（与 favSegment 过滤同位，底栏先例原样）：多选态草稿行整行滤出可见集——
    // 全选产集、删除 sweep 两面自动同口径（都基于滤后可见集）
    const guarded: SessionListRow[] = this.multiSelectMode
      ? segmentRows.filter((row: SessionListRow): boolean => row.id !== NEW_DRAFT_KEY)
      : segmentRows;
    // ★ 条件清不变量（照底栏 ChatSessionList.syncVisibleRows 原样——禁无条件清：多选中
    // 后台刷新即清空选集是 bug）：保「已选 ⊆ 可见」。两路触发 = ①段值变 ②已选含不可见
    // 行（换助手 reload 按 ACTIVE_ASSISTANT_KEY 重过滤、他处删行等段值不变而可见集整体
    // 换掉的源，hasHiddenSelection 单源 = SessionMultiselectBar）；rows 单纯「增长」
    //（主动消息落库 / 标题写回重拉）不触发——已选仍在可见集内，用户手上的选择不被后台
    // 写入打断。空选短路使非多选态零开销；清空动作 = onSetSelected([]) 上行（侧栏
    // selectedIds 真源在宿主 @Prop，本件不直写）
    const segmentChanged: boolean = this.favSegment !== this.lastSyncedSegment;
    this.lastSyncedSegment = this.favSegment;
    if (segmentChanged || (this.selectedIds.length > 0
      && hasHiddenSelection(guarded.map((row: SessionListRow): string => row.id),
        this.selectedIds))) {
      this.onSetSelected([]);
    }
    this.visibleRows = guarded;
    this.onVisibleCount(guarded.length);
  }

  // 全选指令回执（一次性命令键）：可见行集两态产集（全选 ⇄ 清空）整组上行
  private onSelectAllCmd(): void {
    const visibleIds: string[] = this.visibleRows
      .map((row: SessionListRow): string => row.id);
    this.onSetSelected(nextSelectAllIds(visibleIds, this.selectedIds));
  }

  // ── 长按菜单四动作（与一级页 ChatSessionList 同语义独立成装——确认弹窗/级联删）──

  // 收藏开关（菜单「收藏/取消收藏」唯一入口）：落库 → toast + 重拉
  private async toggleFavorite(row: ConversationRow): Promise<void> {
    try {
      await setConversationFavorite(row.id, !row.favorite);
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast(
        { message: row.favorite ? '已取消收藏' : '已收藏' });
      this.reload();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast(
        { message: (row.favorite ? '取消收藏失败：' : '收藏失败：') + (e as Error).message });
    }
  }

  // 重命名弹窗（InputDialog 组件成员位——坑7）
  private openRenameDialog(row: ConversationRow): void {
    this.renameCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名会话',
        initialText: row.title !== '' ? row.title : '新对话',
        placeholder: '会话名称',
        onConfirm: (text: string): void => {
          this.applyRename(row.id, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.renameCtrl.open();
  }

  private async applyRename(id: string, text: string): Promise<void> {
    try {
      await renameConversation(id, text);
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
      this.reload();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '重命名失败：' + (e as Error).message });
    }
  }

  // 删除确认（单条；'__new__' 合成行 = 删草稿本体，底栏同判据）
  private confirmDeleteOne(row: ConversationRow): void {
    if (row.id === NEW_DRAFT_KEY) {
      this.openDeleteConfirm('将删除该草稿，不可恢复。', (): void => {
        removeDraftsWithFiles([NEW_DRAFT_KEY]);
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '草稿已删除' });
      });
      return;
    }
    const tmpCount: number = countWorkspaceTmpFiles(row.id);
    this.openDeleteConfirm('将彻底删除会话「'
      + (row.title !== '' ? row.title : '新对话')
      + '」及其全部聊天记录，不可恢复。'
      + (tmpCount > 0 ? '删除后该会话的 ' + tmpCount + ' 个临时文件将一并删除。' : ''),
      (): void => {
        this.deleteOne(row.id);
      });
  }

  private openDeleteConfirm(message: string, onConfirm: () => void): void {
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除会话',
        message: message,
        confirmLabel: '删除',
        onConfirm: (): void => {
          onConfirm();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private async deleteOne(id: string): Promise<void> {
    try {
      await deleteConversations([id]);
      // 数据层动作先完成再判存活：草稿文件级联不得因退场跳过（1713 判守纪律——判守只许
      // 放 UI 动作前，禁夹在数据层动作之间；与批量删除 deleteSelected 同顺序）
      removeDraftsWithFiles([id]);
      if (this.departed) {
        return;
      }
      // 删除命中主区会话：与批量删除同语义上行换轨（新造 id 由本页生成，宿主只落标记与
      // 换 id——主区重建后本页留守继续操作列表）
      if (id === this.selectedConvId) {
        this.onActiveSessionDeleted(nextMessageId('conv'));
      }
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已删除 1 个会话' });
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  // 移动面板（长按菜单「移动到助手」）：SessionMovePanel 整件复用，关闭与落库广播同底栏
  private openMoveSheet(row: ConversationRow): void {
    this.moveTargetId = row.id;
    this.moveSheetShow = true;
  }

  // ── 点行进会话（底栏 handleOpenCard 同语义：合成行走新建链，其余记最近进入后直达）──
  private handleOpenCard(row: ConversationRow): void {
    if (row.id === NEW_DRAFT_KEY) {
      this.onOpenNewSession();
      return;
    }
    recordSessionRecentConv(row.id);
    this.onOpen(row.id, row.title);
  }

  // 移动面板内容（坑51：bindSheet builder 位挂组件内 @Builder）
  @Builder
  MoveSheet() {
    SessionMovePanel({
      conversationId: this.moveTargetId,
      bottomInset: this.bottomPad,
      onMoved: (): void => {
        this.moveSheetShow = false;
        this.reload();
        AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
          (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      },
      onClose: (): void => {
        this.moveSheetShow = false;
      }
    })
  }

  // 空态文案（分段分治，与一级页同档；侧栏额外给助手切换提示——顶部助手行点名字区可用）
  private emptyText(): string {
    return this.favSegment === SIDE_FAV_FAVORITE ? '暂无收藏会话'
      : '该助手暂无会话。点上方助手名可切换助手。';
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 列表主体（★ 2026-11-18 会话卡统一笔：渲染域 = 一级会话页 SessionRows 同件——
      // 卡形态/横滑四键/长按菜单全同源；topPad 已含标题带 + 带底呼吸，额外让位传 0）。
      // 数组经 enableV2Compatibility 桥接——Repeat 懒加载要求 V2 观察能力
      SessionRows({
        visibleRows: UIUtils.enableV2Compatibility(this.visibleRows),
        hintText: this.hintText,
        topPad: this.topPad,
        topClearance: 0,
        bottomPad: this.bottomPad,
        selectMode: this.multiSelectMode,
        selectedIds: UIUtils.enableV2Compatibility(this.selectedIds),
        unreadConvId: this.unreadConvId,
        appColorMode: this.appColorMode,
        cardAlphaLevel: this.cardAlphaLevel,
        immersiveLevel: this.immersiveLevel,
        onOpen: (row: ConversationRow): void => {
          this.handleOpenCard(row);
        },
        onToggle: (id: string): void => {
          this.onToggleSelect(id);
        },
        onFavorite: (row: ConversationRow): void => {
          this.toggleFavorite(row);
        },
        onRename: (row: ConversationRow): void => {
          this.openRenameDialog(row);
        },
        onMove: (row: ConversationRow): void => {
          this.openMoveSheet(row);
        },
        onDelete: (row: ConversationRow): void => {
          this.confirmDeleteOne(row);
        }
      })
        .width('100%')
        .height('100%')

      // 空态卡（与一级页同形：全高居中 13fp 次要色；首拉在途 / 加载失败不显示）
      if (this.loaded && this.hintText === '' && this.visibleRows.length === 0) {
        Column() {
          Text(this.emptyText())
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: this.topPad })
      }

      // 读取失败提示 · 0 行兜底（>0 行时由 SessionRows 随末卡尾行呈现；位置与首行同源）
      if (this.visibleRows.length === 0 && this.hintText !== '') {
        Text(this.hintText)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('calc(100% - 32vp)')
          .margin({ top: this.topPad })
      }
    }
    .width('100%')
    .height('100%')
    // 会话移动半模态（挂本件根；档位 [MEDIUM, LARGE] 半屏起——选择器/列表类规范档）
    .bindSheet($$this.moveSheetShow, this.MoveSheet(), sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        this.moveSheetShow = false;
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }
}
