// 提示词库管理页（设置页「会话提示词」行卡 push，自包 PageShell 壳）：
// · 清单 = 用户模板（queryTemplates 过滤 isGlobal=0）；系统提示词独立页 SystemPromptPage 由本页
//   首卡整卡点击 push 无参进入（返回无需刷新——两数据源零交集）；
// · 标题栏双键胶囊〔＋新建提示词 | ⋯更多〕= 覆盖层胶囊（menuHds 传 null）；「多选」收入
//   「更多」菜单（唯一项）；键件/菜单/锚点整域在 PromptTitleMenu.ets。多选 = 批量删除模式；
// · 行卡：编辑 = 卡本体点击，删除 = 行左滑确认链（右缘四点键菜单已退役）；多选态勾选圈贴右缘
//   （SessionCardItem 同款）；删除确认 = ConfirmDialog（组件成员位——坑7）固定文案，动态模板名
//   不入（后果提示已足够）。
// ★ 长列表 = List + Repeat.virtualScroll（V1 壳保多选/菜单/删除链，行卡渲染拆同文件 V2 渲染件，
//   规范 §4.6）；键只写 id——同 id 新对象靠 item 比对刷新（「键含 id|名称|正文全文」防线退役，
//   坑16 键载荷机制等价接替）；让位 = offset 轨；0 行壳侧 Scroll 兜底。
// ★ 搜索（常显实时框）：命中 = **名称 + 正文**（不是记忆页的「只搜正文」；纯函数在
//   common/LibrarySearch）。框在标题栏下方带（SearchTopBand 恒 REGULAR 光感），恒在场无自锁。
//   0 行两态分派单源 emptyHintText；「全选」吃**可见集**（过滤态选全量会删屏外行），与
//   ChatSessionList 取齐。
// ★ 头槽 = 系统提示词入口卡；0 行/搜索无命中同挂。多选态恒常显，多选中 push 离页返回后多选态
//   保留 = 有意行为。
import { CARD_RADIUS } from '../../common/Theme';
import { UIUtils } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PROMPT_EDIT_PAGE, ROUTE_SYSTEM_PROMPT_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_PROMPT } from '../../common/SettingSearch';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import {
  deleteTemplate, PromptTemplateRow, queryTemplates
} from '../../common/store/PromptTemplateDb';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { SessionMultiselectActionBar, isAllSelectedIn, nextSelectAllIds } from '../chat/SessionMultiselectBar';
// 行级左滑删除横滑层（交互基准 = 会话页 SessionSwipeItem；SwipeGroup 互斥口径见该件头注释）
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
// 搜索过滤纯函数（零 import 叶子件；命中 = 名称 + 正文，空词 = 全显）
import { filterPromptsByKeyword } from '../../common/LibrarySearch';
// 标题栏下方带搜索框承载件 + 内容顶让位算式
import { SearchTopBand, searchBandContentTop } from '../SearchTopBand';
// 标题栏键与「更多」菜单域（键件/菜单/锚点整域在此；行卡菜单域已退役）
import {
  PromptMoreMenuAnchor, PromptTitleBarKeys, PromptTitleMenuCallbacks, PromptTitleMenuHost
} from './PromptTitleMenu';
import { ConfigurationConstant } from '@kit.AbilityKit';

@Component
export struct PromptLibraryPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行（数据层意图照常完成）
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 全量模板（搜索过滤、全选可见集与重算的基；库上限有界）
  @State private templates: PromptTemplateRow[] = [];
  // 搜索词与过滤后的可见行（列表数据源）；空词 = 全显
  @State private keyword: string = '';
  @State private visibleTemplates: PromptTemplateRow[] = [];
  @State private deleteTarget: PromptTemplateRow | null = null;
  // 多选模式与选中 id 集合（坑6：本页逐个调用 deleteTemplate、无数组入参，天然规避）
  @State private multiSelect: boolean = false;
  @State private selectedIds: string[] = [];
  // 行左滑互斥组（单源：可见集重算 / 进入多选 / 滚动开始三路 collapse）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 材质档位（「更多」菜单弹出解析）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 标题栏「更多」菜单宿主
  private titleMenu: PromptTitleMenuHost = new PromptTitleMenuHost();
  // 删除确认弹窗（坑7：必须组件成员位构造——普通类 open() 静默无效真机实锤）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除提示词',
      message: '删除后引用该模板的会话将回退助手提示词。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    this.titleMenu.init(this.getUIContext(), this.titleMenuCallbacks());
    this.reload();
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.titleMenu.dispose();
  }

  // 新建：多选中不生效——多选中新建语义冲突（返回后多选态残留且与批量删除交错），
  // 会话页 newConversation 同款守卫
  private onNewTemplate(): void {
    if (this.multiSelect) {
      return;
    }
    this.editTemplate('');
  }

  // ── 标题栏「更多」菜单 ──
  private titleMenuCallbacks(): PromptTitleMenuCallbacks {
    return {
      onMultiselect: (): void => {
        this.onMultiSelect();
      }
    };
  }

  // 弹出「更多」菜单（定位 = 内容区隐形锚点 PromptMoreMenuAnchor，几何见 PromptTitleMenu.ets）。
  // 多选态让位：原键位一律让位、动作集中在批量条（技能库/记忆库/会话列表同款）
  private openMoreMenu(): void {
    if (this.multiSelect) {
      return;
    }
    this.titleMenu.open(this.getUIContext(), this.titleMenuCallbacks(), this.immersiveLevel);
  }

  private onMultiSelect(): void {
    // 已在多选态 = 幂等无操作（批量条另有「全不选」键，本键再清空就是两个入口，易误清）
    if (this.multiSelect) {
      return;
    }
    this.swipeGroup.collapse();
    this.multiSelect = true;
    this.selectedIds = [];
  }

  // 可见模板 id 集（全选两态与全选动作的共同输入——**可见集**单源，勿在别处重造）。过滤态下
  // 吃全量会把屏外行也删掉 = 危险面；与 ChatSessionList 口径取齐
  private visibleTemplateIds(): string[] {
    return this.visibleTemplates.map((row: PromptTemplateRow): string => row.id);
  }

  // 全选/全不选（批量条左端键）：全选态 → 清空；否则选中**当前可见**全部（判据纯函数在
  // SessionMultiselectBar，与会话列表共用单源）
  private toggleSelectAll(): void {
    this.selectedIds = nextSelectAllIds(this.visibleTemplateIds(), this.selectedIds);
  }

  private reload(): void {
    queryTemplates()
      .then((rows: PromptTemplateRow[]): void => {
        if (this.departed) {
          return;
        }
        this.templates = rows;
        // 关键词不因重拉被清空（搜索态下增删改后仍在同一过滤视图，记忆库页同款口径）
        this.applyFilter(rows);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '提示词读取失败：' + (e as Error).message });
      });
  }

  // 可见行重算（纯内存过滤，不查库；空词 = 全显）。两个重算点：reload 成功与搜索框 onChange
  private applyFilter(rows: PromptTemplateRow[]): void {
    // 可见集重算 → 收起左滑展开行（行对象引用不变时行侧听不到重算，由容器统一收回）
    this.swipeGroup.collapse();
    this.visibleTemplates = filterPromptsByKeyword(rows, this.keyword);
  }

  // 内容顶留白：让出带框位（算式单源 searchBandContentTop，见 SearchTopBand.ets）；多选态
  // （带收起）归 topPad
  private contentTopPad(): number {
    return !this.multiSelect
      ? searchBandContentTop(this.topPad, 28) : this.topPad;
  }

  // 0 行态提示文案（分派单源）：库空 = 新建引导原文；搜索无命中 = 单句（此时该改词，不是新建）
  private emptyHintText(): string {
    if (this.templates.length === 0) {
      return '暂无提示词。点右上角的「＋」新建，或在对话页把常用提示词保存进来。';
    }
    return '没有匹配的提示词。';
  }

  private editTemplate(rowId: string): void {
    this.pathStack.pushPathByName(ROUTE_PROMPT_EDIT_PAGE, rowId, (): void => {
      this.reload();
    });
  }

  // 勾选切换（渲染域按 id 上行；勾选圈纯视觉 + 卡片 onClick 单一通路——坑5 先例）
  private toggleSelectId(id: string): void {
    const row: PromptTemplateRow | undefined =
      this.templates.find((r: PromptTemplateRow): boolean => r.id === id);
    if (row !== undefined) {
      this.toggleSelect(row);
    }
  }

  private toggleSelect(row: PromptTemplateRow): void {
    const idx: number = this.selectedIds.indexOf(row.id);
    if (idx >= 0) {
      this.selectedIds.splice(idx, 1);
      this.selectedIds = this.selectedIds.slice();
    } else {
      this.selectedIds = this.selectedIds.concat([row.id]);
    }
  }

  // 批量删除确认（多选态底部条主操作）；文案固定（通用后果提示，不用动态引用数）
  private confirmDeleteSelected(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    this.confirmCtrl.open();
  }

  private confirmDelete(row: PromptTemplateRow): void {
    this.deleteTarget = row;
    this.confirmCtrl.open();
  }

  // 左滑删除入口：行 id → 行对象后走既有确认链（与会话页同款；行已在重拉中消失 = 静默不弹）
  private confirmDeleteById(id: string): void {
    const row: PromptTemplateRow | undefined =
      this.templates.find((r: PromptTemplateRow): boolean => r.id === id);
    if (row !== undefined) {
      this.confirmDelete(row);
    }
  }

  private doDelete(): void {
    if (this.multiSelect) {
      this.doDeleteSelected();
      return;
    }
    const target: PromptTemplateRow | null = this.deleteTarget;
    if (target === null) {
      return;
    }
    this.deleteTarget = null;
    this.deleteOne(target.id);
  }

  // 删除单条（引用数提示——被引用时文案「N 个会话引用，已回退助手提示词」）
  private deleteOne(id: string): void {
    deleteTemplate(id)
      .then((refCount: number): void => {
        if (this.departed) {
          return;
        }
        const warned: string = refCount > 0 ? '（' + refCount + ' 个会话引用，已回退助手提示词）' : '';
        this.getUIContext().getPromptAction().showToast({ message: '已删除' + warned });
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 批量删除（逐个调用——引用数求和提示；完成退出多选）
  private doDeleteSelected(): void {
    const ids: string[] = [];
    for (const id of this.selectedIds) {
      ids.push(id);
    }
    let totalRefs: number = 0;
    let done: number = 0;
    let failed: boolean = false;
    for (const id of ids) {
      deleteTemplate(id)
        .then((refCount: number): void => {
          if (this.departed) {
            return;
          }
          totalRefs += refCount;
          done++;
          if (done === ids.length) {
            if (failed) {
              this.getUIContext().getPromptAction().showToast({ message: '部分删除失败，请重试' });
            } else {
              const warned: string = totalRefs > 0 ? '（' + totalRefs + ' 个会话引用，已回退助手提示词）' : '';
              this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + ids.length + ' 个' + warned });
            }
            this.multiSelect = false;
            this.selectedIds = [];
            this.reload();
          }
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          failed = true;
          done++;
          if (done === ids.length) {
            this.multiSelect = false;
            this.selectedIds = [];
            this.getUIContext().getPromptAction().showToast({ message: '部分删除失败：' + (e as Error).message });
            this.reload();
          }
        });
    }
  }

  private exitMultiSelect(): void {
    this.multiSelect = false;
    this.selectedIds = [];
  }

  // 标题栏下方带搜索框（承载件 SearchTopBand 恒 REGULAR 光感，几何与命中透传见该件头注释）
  @Builder
  SearchBand() {
    SearchTopBand({
      keyword: $keyword,
      placeholder: '搜索名称或内容',
      onInput: (value: string): void => {
        this.keyword = value;
        this.applyFilter(this.templates);
      }
    })
  }

// 系统提示词入口卡（自设置页卡2 迁入首卡，头槽与 0 行分支两处复用）：TemplateRow 同族卡体 +
// doc_text 符号 + 标题/副标题两行；无四点键、不进多选集，整卡点击 push 独立页无参。
// ★ 2026-11-09 反馈笔：卡底与 InfoCard 同取 app.color.info_card_bg、撤 0.5vp 描边——本页
// 唯一染色卡，深浅两模式随资源色自动分治；两处复用共此 @Builder，改一处即两态生效
  @Builder
  SystemPromptEntry() {
    // 卡底 Column + 四周 padding 4 = 蒙层距卡外圈 4vp（壳 padding 回添，几何零位移）
    Column() {
      Button() {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
          Column({ space: 3 }) {
            Text('系统提示词')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
            Text('会话提示词未启用时自动注入')
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding(10)
      .onClick((): void => {
        this.pathStack.pushPathByName(ROUTE_SYSTEM_PROMPT_PAGE, null);
      })
    }
    .width(CARD_PANEL_WIDTH)
    // info 卡色（2026-11-09 反馈笔）：与 InfoCard 共用 app.color.info_card_bg 资源色，
    // 不加渐变、不叠卡底透明度档、不加描边（info 卡无形制描边）；几何与卡内元素零改动
    .backgroundColor($r('app.color.info_card_bg'))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 标题栏覆盖层（双键胶囊）——组件内 @Builder 挂载是硬约束（坑30：全局 @Builder 被
  // 官方 titleBar napi 调用时无视图上下文，启动即闪退）；键件与几何走 TitleBarKeys，胶囊与
  // 菜单在 PromptTitleMenu.ets，本页只传两动作
  @Builder
  TitleBarContent() {
    PromptTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      onAdd: (): void => {
        this.onNewTemplate();
      },
      onMore: (): void => {
        this.openMoreMenu();
      }
    })
  }

  // 行卡（多选态勾选圈 / 普通态点击进编辑）：卡体随列表迁渲染域 PromptLibRows（见文件尾），
  // 事件上行壳侧执行
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      // 「更多」菜单隐形锚点（openMenu 的 TargetInfo 定位目标；几何见 PromptTitleMenu.ets；
      // HitTest.None 不拦滚动与触摸）
      PromptMoreMenuAnchor({ topPad: this.topPad })
      if (this.visibleTemplates.length === 0) {
        // 0 行分支（Repeat 无行可挂，壳侧 Scroll 兜底）
        Scroll() {
          Column({ space: CARD_SPACING }) {
            // 0 行（库空）/ 搜索无命中两态入口卡照挂——防「列表一空、系统提示词入口跟着消失」
            this.SystemPromptEntry()
            // 两态不可混，分派单源 = emptyHintText
            Text(this.emptyHintText())
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ top: this.contentTopPad(), bottom: this.bottomPad + 16 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
      } else {
        PromptLibRows({
          // 数据源 = 过滤后的可见集
          templates: UIUtils.enableV2Compatibility(this.visibleTemplates),
          multiSelect: this.multiSelect,
          selectedIds: UIUtils.enableV2Compatibility(this.selectedIds),
          appColorMode: this.appColorMode,
          // 左滑互斥组
          group: this.swipeGroup,
          // 顶留白：让出带框位（contentTopPad）
          topPad: this.contentTopPad(),
          bottomPad: this.bottomPad,
          // 首行头槽（挂首行随内容滚——@Prop 不进 V2，故走 @BuilderParam 由壳侧渲染，
          // MemoryLibraryRows 先例）：系统提示词入口卡
          headSlot: (): void => {
            this.SystemPromptEntry()
          },
          onOpen: (row: PromptTemplateRow): void => {
            this.editTemplate(row.id);
          },
          onToggle: (id: string): void => {
            this.toggleSelectId(id);
          },
          // 左滑删除（删除键与长距直达同链，弹既有确认框；删除唯一入口 = 本链）
          onSwipeDelete: (id: string): void => {
            this.confirmDeleteById(id);
          }
        })
          .width('100%')
          .height('100%')
      }

      // 多选批量条（图标三键〔计数在确认弹窗〕）。barBottom 避让区 + 16 同会话列表口径
      if (this.multiSelect) {
        SessionMultiselectActionBar({
          // 全选两态（驱动图标 fill/描边切换）；判据与动作都吃**可见集**（过滤态下不去
          // 选屏外行）
          allSelected: isAllSelectedIn(this.visibleTemplateIds(), this.selectedIds),
          barBottom: this.bottomPad + 16,
          onCancel: (): void => {
            this.exitMultiSelect();
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
    PageShell({
      // 主标题：多选态 = 「已选 N 项」实时刷（selectedIds → build 重跑 → PageShell title 传导）；
      // 常态 = 设置搜索注册表标题常量
      title: this.multiSelect ? '已选 ' + this.selectedIds.length + ' 项' : SETTING_TITLE_PROMPT,
      // 标题栏两键 = 覆盖层合并胶囊〔＋新建提示词 | ⋯更多〕（menuHds 传 null、keepStackTitle =
      // true 保主标题）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      // 标题栏下方带搜索框。多选态带收起（经 @Prop 进壳 bandParams 早退，titleBarBottom 普通
      // 成员不能动态置空）；让位联动见 contentTopPad
      titleBarBottom: (): void => {
        this.SearchBand();
      },
      titleBarBottomHidden: this.multiSelect,
      content: (): void => {
        this.Content();
      }
    })
  }
}

// ═══ 提示词清单渲染域（同文件同域——壳引渲染件单向）═══
// List + Repeat.virtualScroll（V2）：机制与键纪律见文件头；本件纯渲染（不知「过滤」），头槽经
// @BuilderParam 挂首行随内容滚；行卡包 RowSwipeDelete（左滑删除 + 长距直达，多选态整层退化，
// 展开态不进键，滚动开始经组收起）。
@ComponentV2
struct PromptLibRows {
  // 模板清单（壳侧桥接传入——Repeat 懒加载要求 V2 观察能力；搜索态下 = 可见集）
  @Param templates: PromptTemplateRow[] = [];
  // 多选模式（标量 @Param 下行——勾选圈/行尾键互斥）
  @Param multiSelect: boolean = false;
  // 选中集（桥接数组——Checkbox select 逐行比对刷新）
  @Param selectedIds: string[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 左滑互斥组（壳侧单源）
  @Param group: SwipeGroup = new SwipeGroup();
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 首行头槽（系统提示词入口卡——壳侧 V1 Builder；@Prop 不进 V2，故走 @BuilderParam）
  @BuilderParam headSlot: () => void;
  // 事件两枚（透传壳侧回调——点卡编辑 / 勾选切换；读当前 ri.item）
  @Event onOpen: (row: PromptTemplateRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };
  // 左滑删除（删除键与长距直达共用——壳侧走既有确认链）
  @Event onSwipeDelete: (id: string) => void = () => {
  };

  // 行卡（多选态 = 勾选圈贴右缘 + 行点击切换；普通态 = 点击进编辑）。卡底 Column + padding 4 =
  // 按压蒙层距卡外圈 4vp（壳 padding 回添，几何零位移）
  @Builder
  TemplateRow(ri: RepeatItem<PromptTemplateRow>) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(ri.item.name !== '' ? ri.item.name : '无名称模板')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              // 名行单行收敛（名上限 50 字；不收敛时长名会把行卡撑高、高矮不一）
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(ri.item.content !== '' ?
              ri.item.content.substring(0, 24) + (ri.item.content.length > 24 ? '…' : '') : '无内容')
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.multiSelect) {
            // 勾选圈贴右缘（Checkbox 纯视觉 + hitTestBehavior(None) 穿透 + 卡片 onClick 单一
            // 通路——坑5）
            Checkbox()
              .select(this.selectedIds.indexOf(ri.item.id) >= 0)
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding(10)
      .onClick((): void => {
        if (this.multiSelect) {
          this.onToggle(ri.item.id);
        } else {
          this.onOpen(ri.item);
        }
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    // 卡间 CARD_SPACING 单源（本页无板块头，平铺卡栈形态，卡间即唯一纵向档）
    List({ space: CARD_SPACING }) {
      Repeat<PromptTemplateRow>(this.templates)
        .each((ri: RepeatItem<PromptTemplateRow>) => {
          ListItem() {
            // 保真层 Column 居中（CARD_PANEL_WIDTH 卡防整列左偏）
            // 首行 = 头槽（恒开，内容构成与次序见壳侧 headSlot 注释）+ 首卡（间隙同 List space 值）
            Column({ space: CARD_SPACING }) {
              if (ri.index === 0) {
                this.headSlot()
              }
              // 行卡包横滑层：多选态 swipeEnabled 翻 false 整层退化；头槽在包层外（横滑只移卡
              // 不动头槽）；删除链 = 壳侧既有确认框
              RowSwipeDelete({
                rowId: ri.item.id,
                swipeEnabled: !this.multiSelect,
                group: this.group,
                content: (): void => {
                  this.TemplateRow(ri)
                },
                onSwipeDelete: (id: string): void => {
                  this.onSwipeDelete(id);
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 模板 id（身份唯一；改名/改正文靠整体替换后 item 比对刷新，禁键载荷回潮）
        .key((row: PromptTemplateRow): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨（原 Scroll padding top/bottom 同值等价）
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 库有界（用户自建清单），5 为屏内缓冲（按页设值非全局口径）
    .cachedCount(5)
    // 竖滚开始收起左滑展开行（互斥经 SwipeGroup 单源）
    .onScrollStart((): void => {
      this.group.collapse();
    })
  }
}
