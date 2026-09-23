// 记忆库管理页（2026-09-20 助手级记忆，任务书-助手级记忆-20260920 §4.5——设置记忆页一级
// 改分库列表后的二级库管理页；条目管理面自 MemoryPage.ets 域级最小拆分整体搬迁，方法体
// 原样迁移只换数据源，禁顺手重排）：
// · 库参数（push param 对象 MemoryLibraryParam.libraryId）：'global' = 全局记忆库（memories
//   表——与改造前记忆页管理面逐字等价）/ 助手 id = 该助手的助手记忆库（assistant_memories
//   表）。标题随库（全局 = 「全局记忆」；助手 = 助手名，aboutToAppear 查询，行删/失败兜底
//   「助手记忆」）。
// · 标题栏〔＋|⋯〕胶囊与「更多」菜单（立即整理 / 优化记忆 / 记忆历史 / 从其他平台导入 /
//   排序）整组自一级页迁入——操作面跟库走（拍板 6「操作面一套」），键件/菜单/锚点/宿主复用
//   MemoryTitleMenu.ets 零改动。
// · 立即整理：选会话面板按库过滤（助手库 = 只列该助手的会话；全局库 = 全部非加密会话现状），
//   落库目标 = 入口库（sinkMemoryNow 第二参——产物库恒等于入口库）。
// · 优化：prepareMemoryOpt / applyMemoryOpt 带库参数——条目读取、事务落库、广播同库。
// · 排序 / 编辑：push 参数带库上下文（对象 MemorySortParam / MemoryEditParam），保存落对应库。
// · 刷新链（与原记忆页同构三通道）：本页删除即时 reload；增改/排序经子页 onPop 重拉；
//   onShown 重拉（栈下层兜底）；两库广播键各挂 @StorageProp @Watch——回调判当前库匹配才
//   重拉（@StorageProp 键为编译期常量，两键并挂分派在回调内做）。
// · 上限：库内 ≤ MEMORY_MAX_TOTAL 在「＋」push 前拦截（两库同口径库级独立计数）。
// · 行卡菜单 / 删除确认 / 优化确认 / 半模态选会话：形制与机制自 MemoryPage 原样随迁
//   （坑64 bindSheet 页面根挂载 / 坑7 弹窗成员位 / 坑17 pop 带 result）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppMenuHost } from '../../common/AppMenuHost';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, menuDividerColor
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { formatConvTime } from '../chat/SessionSearchPanels';
import {
  IMMERSIVE_LEVEL_KEY, overlayMaterial, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import {
  ROUTE_MEMORY_EDIT_PAGE, ROUTE_MEMORY_HISTORY_PAGE, ROUTE_MEMORY_IMPORT_PAGE,
  ROUTE_MEMORY_LIBRARY_PAGE, ROUTE_MEMORY_SORT_PAGE
} from '../../common/RouteNames';
import { ConversationRow, queryConversations } from '../../common/store/ChatDb';
import {
  ASSISTANT_MEMORY_LIST_TICK_KEY, deleteAssistantMemory, deleteMemory, MEMORY_LIST_TICK_KEY,
  MEMORY_MAX_TOTAL, MEMORY_SCOPE_GLOBAL, MemoryRow, queryAssistantMemories, queryMemories
} from '../../common/store/MemoryDb';
import { AssistantRow, historyFilterIds, queryAssistant } from '../../common/store/AssistantDb';
import {
  MEMORY_ENABLED_KEY, MEMORY_FULL_TIP, MEMORY_SINKING_KEY, MemoryModelPick,
  MemorySinkResult, memorySinkToastText, resolveMemoryModel, sinkMemoryNow
} from '../../common/MemoryGen';
import {
  applyMemoryOpt, MEMORY_OPT_RUNNING_KEY, MemoryOptPrepare, prepareMemoryOpt,
  resolveMemoryOptModel
} from '../../common/MemoryOpt';
import { memoryOptConfirmText, memoryOptToastText, MemoryOptOutcome,
  MemoryOptPlan, memorySourceLabel } from '../../common/MemoryText';
import { sheetPanelOptions, sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import {
  MemoryMoreMenuAnchor, MemoryTitleBarKeys, MemoryTitleMenuCallbacks,
  MemoryTitleMenuHost, memoryTitleMenuNav
} from './MemoryTitleMenu';
import { MemoryLibraryParam } from './MemoryPage';

// 记忆功能关闭时两键的前置提示（自 MemoryPage 随迁：迁标题栏菜单项后无禁用态可表达，
// 改动作内引导；两键同用一句，单源此处）
const MEMORY_OFF_TIP: string = '记忆功能已关闭，请先在「记忆开关」中打开';

// push 参数载体（编辑/排序页解析；libraryId 判据 = 'global' | 助手 id）
export interface MemoryEditParam {
  id: string;
  libraryId: string;
}

export interface MemorySortParam {
  libraryId: string;
}

// 导入页 push 参数载体（★ 声明单源 = 本页（发起方）；消费方 MemoryImportPage import 消费，
// 禁本地复写——两份声明字段漂移编译不报错，undefined 被 typeof 兜到 'global' 会静默写错库，
// MemoryLibraryParam 先例同款纪律）
export interface MemoryImportParam {
  libraryId: string;
}

// 库参数载体 MemoryLibraryParam 的声明单源在 MemoryPage.ets（push 发起方）——本文件只
// import 消费，禁本地复写（D3-5 修复：两份声明字段漂移编译不报错，undefined 被下方 typeof
// 兜到 'global'，点某助手的记忆库卡会静默进全局库管理页）

// ── 行卡四点键菜单：编辑 / 删除（自 MemoryPage 原样随迁——形制照 PromptTemplateMenu，
//    锚点 = 四点键自身勿锚整卡；随条目管理面迁入本文件）──
const MEMORY_ROW_MENU_ID_PREFIX: string = 'memoryRowMenu_';

interface MemoryRowMenuCallbacks {
  id: string;
  onEdit: () => void;
  onDelete: () => void;
}

@Builder
function MemoryRowMenuBuilder(params: MemoryRowMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '编辑' })
      .onClick(() => {
        params.onEdit();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
      .onClick(() => {
        params.onDelete();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

class MemoryRowMenuHost extends AppMenuHost<MemoryRowMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: MemoryRowMenuCallbacks): ComponentContent<MemoryRowMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(MemoryRowMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出（基类弹前重建——按当前深浅色/材质重建 UI 树；targetSpace 5 同卡片菜单口径）
  open(uiContext: UIContext, callbacks: MemoryRowMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MEMORY_ROW_MENU_ID_PREFIX + callbacks.id,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}

@Component
export struct MemoryLibraryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 库标识（aboutToAppear 从 push param 解析）：'global' = 全局库 / 助手 id = 助手库
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  // 页面标题（全局库恒「全局记忆」；助手库 = 助手名，查询失败兜底）
  @Prop title: string = '全局记忆';
  // 条目列表（当前库；排序三键 = queryMemories / queryAssistantMemories 保证）
  @State private memories: MemoryRow[] = [];
  // 列表重建纪元（reload 成功自增——键含「行身份 + 纪元」，坑16 家族防同键不刷）
  @State private listEpoch: number = 0;
  // 两库广播键各挂一路（@StorageProp 键为编译期常量；回调内按当前库分派——无关 tick 也
  // 重拉幂等，但分派可省一次无谓查询）
  @StorageProp(MEMORY_LIST_TICK_KEY) @Watch('onGlobalTick') globalTick: number = 0;
  @StorageProp(ASSISTANT_MEMORY_LIST_TICK_KEY) @Watch('onAssistantTick') assistantTick: number = 0;
  // 整理 / 优化进行中计数（自 MemoryPage 随迁——状态行区两提示行）
  @StorageProp(MEMORY_SINKING_KEY) sinkingCount: number = 0;
  @StorageProp(MEMORY_OPT_RUNNING_KEY) optRunning: number = 0;
  @StorageProp(MEMORY_ENABLED_KEY) memoryEnabled: boolean = true;
  // 选会话半模态（坑64：bindSheet 页面根挂载）
  @State private sheetOpen: boolean = false;
  @State private conversations: ConversationRow[] = [];
  // 选会话面板滚动控制器（壳 bindToScrollable 绑标题栏渐变模糊——ChatPromptSheet 同款）
  private convPickerScroller: Scroller = new Scroller();
  // 删除确认弹窗（坑7：组件成员位构造）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除记忆',
      message: '删除后不可恢复。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });
  private deleteTarget: MemoryRow | null = null;
  // 优化确认弹窗（message 依赖本次计划，openOptConfirm 内按需重建——StoragePage 先例）
  private optConfirmCtrl: CustomDialogController | null = null;
  // 待应用的优化计划（弹窗确认时取用；取消 = 弹窗关闭不回填，计划自然作废）
  private optPlan: MemoryOptPlan | null = null;
  // 行卡菜单节点宿主（openMenu：init 一次 / 弹出前重建（基类）/ dispose 成对）
  private rowMenu: MemoryRowMenuHost = new MemoryRowMenuHost();
  // 标题栏「更多」菜单节点宿主（机制同 rowMenu；菜单内容与锚点在 MemoryTitleMenu.ets）
  private titleMenu: MemoryTitleMenuHost = new MemoryTitleMenuHost();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    // push param 解析（对象形态——一级页库列表 push { libraryId }；缺省/异常 = 全局库兜底）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_LIBRARY_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last !== null) {
      const parsed = last as MemoryLibraryParam;
      if (typeof parsed.libraryId === 'string' && parsed.libraryId !== '') {
        this.libraryId = parsed.libraryId;
      }
    }
    this.rowMenu.init(this.getUIContext(), {
      id: '',
      onEdit: (): void => {
      },
      onDelete: (): void => {
      }
    });
    this.titleMenu.init(this.getUIContext(), this.titleMenuCallbacks());
    if (this.libraryId === MEMORY_SCOPE_GLOBAL) {
      this.title = '全局记忆';
      this.reload();
    } else {
      // 助手库：标题 = 助手名（查询失败兜底「助手记忆」——行删/坏 id 时页面仍可用）
      queryAssistant(this.libraryId)
        .then((row: AssistantRow | null): void => {
          this.title = row !== null ? row.name : '助手记忆';
        })
        .catch((): void => {
          this.title = '助手记忆';
        });
      this.reload();
    }
  }

  aboutToDisappear(): void {
    this.rowMenu.dispose();
    this.titleMenu.dispose();
  }

  // 当前库条目读取（唯一数据源分派点——'global' = memories 表，助手 id = assistant_memories）
  private readLibrary(): Promise<MemoryRow[]> {
    return this.libraryId === MEMORY_SCOPE_GLOBAL ?
      queryMemories() : queryAssistantMemories(this.libraryId);
  }

  private reload(): void {
    this.readLibrary()
      .then((rows: MemoryRow[]): void => {
        this.memories = rows;
        this.listEpoch = this.listEpoch + 1; // 键变重建（编辑/排序变化也刷新）
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '记忆读取失败：' + (e as Error).message });
      });
  }

  // 全局库广播读点（当前库 = 全局库才重拉——助手库 tick 与本页无关）
  private onGlobalTick(): void {
    if (this.libraryId === MEMORY_SCOPE_GLOBAL) {
      this.reload();
    }
  }

  // 助手库广播读点（当前库 = 发出广播的那个助手库才重拉——tick 不带库标识，非本库 tick
  // 重拉也是幂等查询，此处以「任一助手库 tick + 当前库为助手库」收窄；跨助手库的误刷新
  // = 一次无谓查询可忽略，不为 tick 增设库标识复杂化）
  private onAssistantTick(): void {
    if (this.libraryId !== MEMORY_SCOPE_GLOBAL) {
      this.reload();
    }
  }

  // 列表重建键（纪元——每次 reload 自增；增删改/排序变化一律重建）
  private listKey(): string {
    return 'library|' + this.libraryId + '|' + this.listEpoch;
  }

  // ── 添加 / 编辑（均 push 记忆编辑页；新增空 id、编辑带 id——库上下文随参数同传）──
  // 上限守卫在 push 前（达上限不进编辑页；编辑链不受限——不新增行）
  private openAdd(): void {
    if (this.memories.length >= MEMORY_MAX_TOTAL) {
      // 库满一句单源（MemoryGen.MEMORY_FULL_TIP——「立即整理」撞上限时弹的是同一句）
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_FULL_TIP });
      return;
    }
    this.openEditPage('');
  }

  private openEditPage(rowId: string): void {
    // onPop 回调 = 子页 pop 带 result 时重拉（坑17——无参 pop 不触发）
    const param: MemoryEditParam = { id: rowId, libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_EDIT_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 排序（标题栏「更多」菜单「排序」项 → 排序页拖定卡片序；返回经 onPop 重拉，
  // 卡片序即注入序）——库上下文随参数同传
  private openSortPage(): void {
    const param: MemorySortParam = { libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_SORT_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 记忆历史（2026-09-22 记忆优化历史：优化前自动存档的回看与整库回退入口）──
  // push 参数复用 MemoryLibraryParam（声明单源在 MemoryPage.ets，本页已 import 消费——
  // 禁本地复写：两份声明字段漂移编译不报错，会静默落错库）
  private openHistoryPage(): void {
    const param: MemoryLibraryParam = { libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_HISTORY_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 从其他平台导入（2026-09-22 记忆导入：把别的 AI 平台输出的用户总结整理成条目批量入库）──
  // 入口守卫两级（照「立即整理」onSinkKey 同序同句）：总开关关 → 「记忆功能已关闭」；提取模型
  // 两键未配 → 指路功能模型页。**守卫在打开页面前判**（不让用户白进一页再被弹回）——两处
  // toast 文案与 onSinkKey 同源（MEMORY_OFF_TIP / 同一句模型引导语）
  private openImportPage(): void {
    if (!this.memoryEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_OFF_TIP });
      return;
    }
    const picked: MemoryModelPick = resolveMemoryModel();
    if (picked.providerId === '' || picked.modelId === '') {
      this.getUIContext().getPromptAction().showToast({
        message: '请先在功能模型页的「记忆提取」卡选择模型'
      });
      return;
    }
    // onPop 回调 = 子页 pop 带 result 时重拉（坑17——无参 pop 不触发）
    const param: MemoryImportParam = { libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_IMPORT_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 标题栏「更多」菜单（立即整理 / 优化记忆 / 记忆历史 / 从其他平台导入 / 排序五键的收入处）──
  private titleMenuCallbacks(): MemoryTitleMenuCallbacks {
    return {
      onSink: (): void => {
        this.onSinkKey();
      },
      onOptimize: (): void => {
        this.onOptimizeKey();
      },
      onHistory: (): void => {
        this.openHistoryPage();
      },
      onImport: (): void => {
        this.openImportPage();
      },
      onSort: (): void => {
        this.openSortPage();
      }
    };
  }

  // 弹出「更多」菜单（标题栏末键 action 触发；弹出定位 = 内容区隐形锚点
  // MemoryMoreMenuAnchor，几何见 MemoryTitleMenu.ets）
  private openMoreMenu(): void {
    this.titleMenu.open(this.getUIContext(), this.titleMenuCallbacks(), this.immersiveLevel);
  }

  // 行卡四点键菜单（编辑 / 删除）
  private openRowMenu(row: MemoryRow): void {
    this.rowMenu.open(this.getUIContext(), {
      id: row.id,
      onEdit: (): void => {
        this.openEditPage(row.id);
      },
      onDelete: (): void => {
        this.askDelete(row);
      }
    }, this.immersiveLevel);
  }

  // ── 删除（菜单「删除」→ 确认弹窗；按库分派删除原语）──
  private askDelete(row: MemoryRow): void {
    this.deleteTarget = row;
    this.confirmCtrl.open();
  }

  private doDelete(): void {
    const target: MemoryRow | null = this.deleteTarget;
    this.deleteTarget = null;
    if (target === null) {
      return;
    }
    const del: Promise<void> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      deleteMemory(target.id) : deleteAssistantMemory(target.id);
    del
      .then((): void => {
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // ── 立即整理（半模态选会话；落库目标 = 入口库）──
  // 数据源按库收窄：全局库 = queryConversations([])（in 空数组 = 条件失效落全表，d.ts:2388
  // 原文——即全部会话，正合「最近会话」语义）；★ 助手库 = queryConversations(
  // historyFilterIds(libraryId))（该助手名下会话——默认助手含存量未绑定 '' 行，
  // historyFilterIds 单源同口径）。updatedAt 倒序取前 20 + 排除加密会话（§2.6 加密不沉淀）
  private openConvPicker(): void {
    const filterIds: string[] = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      [] : historyFilterIds(this.libraryId);
    queryConversations(filterIds)
      .then((rows: ConversationRow[]): void => {
        const usable: ConversationRow[] = [];
        for (const row of rows) {
          if (row.locked) {
            continue;
          }
          usable.push(row);
          if (usable.length >= 20) {
            break;
          }
        }
        this.conversations = usable;
        this.sheetOpen = true;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '会话读取失败：' + (e as Error).message });
      });
  }

  private onPickConversation(conv: ConversationRow): void {
    this.sheetOpen = false;
    // 整理完成即重拉 + 结果提示（可靠原语 = 组件方法回调上行；@StorageProp @Watch 广播在栈下层
    // 不刷新——PageShell.onShown 注释同口径）；目标库 = 入口库（sinkMemoryNow 第二参）
    sinkMemoryNow(conv.id, this.libraryId).then((result: MemorySinkResult): void => {
      this.reload();
      const tip: string = memorySinkToastText(result);
      if (tip !== '') {
        this.getUIContext().getPromptAction().showToast({ message: tip });
      }
    });
  }

  // ── 「更多」菜单「立即整理」项（守卫两级 = 记忆总开关 → 提取模型两键；菜单项为构造期
  // 常量表达不了禁用态，守卫落在动作里）──
  private onSinkKey(): void {
    if (!this.memoryEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_OFF_TIP });
      return;
    }
    // 未选记忆提取模型 = 不整理（决明指令取消回退，与标题生成同口径）——前置 toast 引导，
    // 不弹选会话面板（选完也发不出请求）。两键齐才算已配置（pickMemoryModel 单源语义）
    const picked: MemoryModelPick = resolveMemoryModel();
    if (picked.providerId === '' || picked.modelId === '') {
      this.getUIContext().getPromptAction().showToast({
        message: '请先在功能模型页的「记忆提取」卡选择模型'
      });
      return;
    }
    this.openConvPicker();
  }

  // ── 「更多」菜单「优化记忆」项（守卫两级同「立即整理」）──
  private onOptimizeKey(): void {
    if (!this.memoryEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_OFF_TIP });
      return;
    }
    // 两键齐才算已配置（pickMemoryOptModel 单源语义——只判 providerId 会让「服务商在、
    // 模型空」的半配置态走进请求、最后落 config 态）
    const picked: MemoryModelPick = resolveMemoryOptModel();
    if (picked.providerId === '' || picked.modelId === '') {
      this.getUIContext().getPromptAction().showToast({
        message: '请先在功能模型页的「记忆优化」卡选择模型'
      });
      return;
    }
    this.runOptimize();
  }

  // ── 优化记忆（两段式——先生成计划出确认弹窗，确认后才落库；目标库 = 本页库）──
  private runOptimize(): void {
    prepareMemoryOpt(this.libraryId).then((prep: MemoryOptPrepare): void => {
      if (prep.plan === null) {
        // 无事可做或出不去（none / config / tooLarge / failed / skipped——文案与空串不出
        // 提示的规则单源在 MemoryText.memoryOptToastText，本页只负责弹）
        const tip: string = memoryOptToastText(prep.outcome);
        if (tip !== '') {
          this.getUIContext().getPromptAction().showToast({ message: tip });
        }
        return;
      }
      this.openOptConfirm(prep.plan);
    });
  }

  // 确认弹窗（摘要单源 = MemoryText.memoryOptConfirmText：改了几条 / 合并几组，再加后果
  // 警示）——confirmTone NORMAL（批量改写非删除动作不配红，对齐 DataSyncPage 上传确认口径）
  private openOptConfirm(plan: MemoryOptPlan): void {
    this.optPlan = plan;
    this.optConfirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '优化记忆',
        message: memoryOptConfirmText(plan),
        confirmLabel: '开始优化',
        confirmTone: ConfirmDialogTone.NORMAL,
        onConfirm: (): void => {
          this.doOptimize();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.optConfirmCtrl.open();
  }

  // 落库（用户确认后）：一个事务改内容 + 删被并入行（目标库 = 本页库——plan 条目全部属于
  // 该库）；完成即重拉 + 结果提示
  private doOptimize(): void {
    const plan: MemoryOptPlan | null = this.optPlan;
    this.optPlan = null;
    if (plan === null) {
      return;
    }
    applyMemoryOpt(plan, this.libraryId).then((outcome: MemoryOptOutcome): void => {
      this.reload();
      const tip: string = memoryOptToastText(outcome);
      if (tip !== '') {
        this.getUIContext().getPromptAction().showToast({ message: tip });
      }
    });
  }

  // 标题栏覆盖层（HDS 路径：右上角合并胶囊〔＋|⋯〕）——组件内 @Builder 挂载是硬约束
  //（坑30：全局 @Builder 被官方 titleBar napi 直接调用时无视图上下文，启动即闪退）；键件
  // 与几何在 components/settings/MemoryTitleMenu.ets，本页只注入两动作
  @Builder
  TitleBarKeys() {
    MemoryTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      onAdd: (): void => {
        this.openAdd();
      },
      onMore: (): void => {
        this.openMoreMenu();
      }
    })
  }

  // 内容区（Stack 同层两件 = 「更多」菜单隐形锚点 + 内容滚动层，顶部对齐）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      // 「更多」菜单隐形锚点（openMenu 的 TargetInfo 定位目标；几何 = 日志页/服务商管理页
      // 同款「按钮下沿」公式，见 MemoryTitleMenu.ets；HitTest.None 不拦滚动与触摸）
      MemoryMoreMenuAnchor({ topPad: this.topPad })
      this.ContentScroll()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ContentScroll() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 状态行区（总开关关时的停用说明行 + 两条进行中提示；列表仍可管理——数据管理
        //    不依赖开关；自 MemoryPage 随迁）──
        Column({ space: 6 }) {
          if (!this.memoryEnabled) {
            Text('记忆功能已关闭，不注入也不沉淀。已有条目仍可查看、编辑和删除。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
          if (this.sinkingCount > 0) {
            Text('正在整理')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
          if (this.optRunning > 0) {
            Text('正在优化')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
        }
        .width('100%')

        // ── 条目列表 ──
        Column({ space: 6 }) {
          // 板块头气泡：条目库自身规则（上限 / 注入条数 / 敏感信息，与列表同域——两库同
          // 口径；标题恒「记忆条目」——当前库由页标题与分段语境表明，不再三元分叉）
          SectionHeader({
            title: '记忆条目',
            subtitle: this.memories.length + ' 条',
            hint: '不要存口令、密钥等敏感信息。库内上限 200 条，注入时最多带 30 条。'
          })
          if (this.memories.length === 0) {
            // 空态行内提示（无卡——「暂无记忆提示卡也是全宽，改」同款形制；助手库无自动
            // 整理兜底文案差异：自动整理落哪个库由助手作用域决定，此处不指路具体入口；
            // ★ 2026-09-22 记忆导入：两库都补一句导入指路——从别的 AI 平台迁用户的库多半是
            // 空库起步，空态是发现该功能的第一现场）
            Text(this.libraryId === MEMORY_SCOPE_GLOBAL ?
              '暂无记忆。退出会话自动整理，或点右上角的「＋」新增一条，也可从右上角菜单从其他 AI 平台导入。' :
              '暂无记忆。点右上角的「＋」新增一条，也可从右上角菜单从其他 AI 平台导入。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else {
            ForEach([this.listKey()], (_key: string) => {
              Column({ space: CARD_SPACING }) {
                ForEach(this.memories, (row: MemoryRow) => {
                  this.MemoryRowCard(row)
                }, (row: MemoryRow): string => row.id)
              }
              .width('100%')
            }, (key: string): string => key)
          }
        }
        .width('100%')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  // 单条记忆卡（形制对齐会话提示词库页 TemplateRow：点卡编辑 + 尾部四点键菜单——自
  // MemoryPage 原样随迁）
  @Builder
  MemoryRowCard(row: MemoryRow) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(row.content)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            // 单行截断（行卡不必展示记忆完整内容，行数上限恒定卡高才恒定）
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(memorySourceLabel(row.source) + ' · ' + formatConvTime(row.updatedAt))
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 四点键（编辑/删除菜单）：Button TEXTUAL 包裹对齐 ProviderCardItem 基准形制
        Button() {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .id(MEMORY_ROW_MENU_ID_PREFIX + row.id)
        .onClick((): void => {
          this.openRowMenu(row);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.openEditPage(row.id);
    })
  }

  // 选会话半模态（最近 20 条非加密会话；点选即整理）——壳按《规范-半模态面板与卡片布局》
  // §1/§2 接入沉浸光感样式（自 MemoryPage 原样随迁，仅加助手库归属过滤）
  @Builder
  ConvPickerSheet() {
    Column() {
      HdsNavigation() {
        Scroll(this.convPickerScroller) {
          Column({ space: CARD_SPACING }) {
            if (this.conversations.length === 0) {
              Text(this.libraryId === MEMORY_SCOPE_GLOBAL ?
                '暂无可整理的会话' : '该助手暂无可整理的会话')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width(CARD_PANEL_WIDTH)
                .padding({ top: 16, bottom: 16 })
            } else {
              ForEach(this.conversations, (conv: ConversationRow) => {
                // 会话选择行（Button(Normal) 包裹 = 官方原生按压蒙层 + 垂直内边距 13 对齐
                // 半模态行卡族——2026-09-12 UI 同形异构归一笔 2）
                Button() {
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text(conv.title !== '' ? conv.title : '新对话')
                        .fontSize(15)
                        .fontColor(cardTitleColor())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(formatConvTime(conv.updatedAt))
                        .fontSize(13)
                        .fontColor(cardDescColor())
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(14)
                      .fontColor([$r('sys.color.font_secondary')])
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
                .type(ButtonType.Normal)
                .width(CARD_PANEL_WIDTH)
                .padding({ left: 16, right: 16, top: 13, bottom: 13 })
                .backgroundColor(cardBg(this.appColorMode))
                .borderRadius(16)
                .onClick((): void => {
                  this.onPickConversation(conv);
                })
              }, (conv: ConversationRow): string => conv.id)
            }
            // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条——ModelFetchSheet 同款）
            Row()
              .width('100%')
              .height(24)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 20, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
      }
      // 标题栏（KimiSheetCommon.sheetTitleBarOptions 随迁版一字同源，勿另写——规范 §1）
      .titleBar(sheetTitleBarOptions('选择要整理的会话', '点选一个会话立即整理成记忆',
        (): void => {
          this.sheetOpen = false;
        }, this.immersiveLevel))
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .bindToScrollable([this.convPickerScroller])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: this.title,
      // 页面每次显示重拉（坑25 定稿「onShown 是可靠姿势」——广播在栈下层收不到时的兜底）
      onShown: (): void => {
        this.reload();
      },
      // 标题栏两键：【＋新建】= push 记忆编辑页 /【⋯更多】= 弹菜单（排序 / 立即整理 /
      // 优化记忆）。HDS 路径 = 官方标题栏自定义区覆盖层合并胶囊〔＋|⋯〕（menuHds 传 null，
      // keepStackTitle = true 保住主标题）；回退路径 = 官方菜单数组两键（menuNav）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarKeys();
      },
      keepStackTitle: true,
      menuNav: memoryTitleMenuNav((): void => {
        this.openAdd();
      }, (): void => {
        this.openMoreMenu();
      }),
      content: (): void => {
        this.Content();
      }
    })
      .bindSheet(this.sheetOpen, this.ConvPickerSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          this.sheetOpen = false;
        }, [SheetSize.MEDIUM, SheetSize.LARGE]))
  }
}
