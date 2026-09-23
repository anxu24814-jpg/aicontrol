// 记忆页一级（2026-09-08 记忆域，任务书 §2.5；★ 2026-09-20 助手级记忆改造 = 一级页改
// 「库列表」）：顶部开关组卡两行（记忆功能总开关 / 退出会话后自动整理——@StorageLink 持久键）
// + 读取方式独立分段卡（★ 2026-09-13 记忆按需读取：自动注入 / 按需读取两段，说明小字在
// 操作行上方）+ 状态行区（停用说明行 + 「正在整理」「正在优化」两条进行中提示，行内提示行
// 形制）+「记忆库」板块 = 库卡列表——第一张恒「全局记忆」（所有助手共用的 memories 表，
// 现架构原样），其后为各助手（含内置两张）的助手记忆库（assistant_memories 表）——点库卡
// push MemoryLibraryPage（param = { libraryId }）进对应库管理（条目增删改/排序/立即整理/
// 优化，操作面跟库走）。
// ★ 2026-09-20 改造的搬迁去向（沿革）：原「记忆条目」列表 + 行卡菜单 + 删除确认 + 立即
//   整理（ConvPickerSheet 半模态）+ 优化（两段式确认）+ 排序入口 + 标题栏〔＋|⋯〕胶囊与
//   「更多」菜单，全部整体迁入 components/settings/MemoryLibraryPage.ets（域级最小拆分，
//   方法体原样搬迁只换数据源；MemoryTitleMenu.ets 零改动换消费方）。本页标题栏无键（操作
//   面下放二级库页 = 决明「更多菜单是否需移位」的处置：整组随操作面进二级页）。
// · 作用域语义（拍板 2）：助手在助手编辑页「记忆」子页用分段胶囊二选一（'global' 默认 =
//   全局记忆 = 存量行为原样 / 'assistant' = 助手记忆 = 注入/沉淀/检索全走自己的库，不混注）；
//   本页库列表 = 两库的统一巡检入口（全局恒列第一，助手全量列出——零条库也显示，点进可
//   新建）。
// · 刷新链：onShown 重拉（坑25 定稿姿势）；两库广播键各挂 @StorageProp @Watch（子库页
//   增删改/整理/优化后回本页，onShown 兜底 + 在场广播即时刷新）。
// · 开关组卡与读取方式分段卡：总开关/自动整理/读取方式是全局配置（拍板 6 留一级页），
//   消费方与语义零变化（见 MemoryGen 键族注释）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { SegmentBar } from '../SegmentBar';
import { PageShell } from '../../common/PageShell';
import {
  IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { SETTING_TITLE_MEMORY, SETTING_TITLE_MEMORY_AUTO,
  SETTING_TITLE_MEMORY_ENABLED, SETTING_TITLE_MEMORY_READ_MODE } from '../../common/SettingSearch';
import { ROUTE_MEMORY_LIBRARY_PAGE } from '../../common/RouteNames';
import {
  ASSISTANT_MEMORY_LIST_TICK_KEY, countAssistantMemories, countMemories,
  MEMORY_LIST_TICK_KEY, MEMORY_SCOPE_GLOBAL
} from '../../common/store/MemoryDb';
import { AssistantRow, queryAssistants } from '../../common/store/AssistantDb';
import { MEMORY_AUTO_KEY, MEMORY_ENABLED_KEY, MEMORY_READ_MODE_INJECT,
  MEMORY_READ_MODE_KEY, MEMORY_READ_MODE_TOOL, MEMORY_SINKING_KEY } from '../../common/MemoryGen';
import { MEMORY_OPT_RUNNING_KEY } from '../../common/MemoryOpt';

// 库列表项（reload 组装——id = 'global' | 助手 id；isGlobal = 全局库卡恒列首位的标记）
interface MemoryLibraryItem {
  id: string;
  title: string;
  count: number;
  isGlobal: boolean;
}

// 助手记忆库列表 push 参数载体（MemoryLibraryPage 解析；export = 跨文件形态单源——消费侧
// 必须 import 本声明，禁本地复写：两处各声明一份时字段漂移编译不报错，undefined 会被消费侧
// 的 typeof 兜底静默落到全局库，2026-09-20 D3-5 修复）
export interface MemoryLibraryParam {
  libraryId: string;
}

@Component
export struct MemoryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 两持久开关（@StorageLink 写即持久化——EntryAbility persistProp 注册）
  @StorageLink(MEMORY_ENABLED_KEY) memoryEnabled: boolean = true;
  @StorageLink(MEMORY_AUTO_KEY) memoryAuto: boolean = false;
  // 读取方式（2026-09-13 记忆按需读取：'inject' 自动注入默认 / 'tool' 按需读取；
  // @StorageLink 写即持久化——分段下标与字符串键双向映射见 onReadModeIndexChanged/
  // onReadModeChanged，PreferencesPage 启动进入卡同款契约）
  @StorageLink(MEMORY_READ_MODE_KEY) @Watch('onReadModeChanged') memoryReadMode: string =
    MEMORY_READ_MODE_INJECT;
  @State @Watch('onReadModeIndexChanged') readModeIndex: number = 0;
  // 分段选项（顺序契约：下标 0 = 自动注入（键 'inject'）/ 1 = 按需读取（键 'tool'），勿乱调）
  private readModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '自动注入' },
    { text: '按需读取' }
  ]);
  // 库列表（reload 组装——全局恒首位，其后助手按助手页顺序）
  @State private libs: MemoryLibraryItem[] = [];
  // 库列表重建纪元（reload 成功自增——键含「库身份 + 纪元 + 计数」，计数变化必重建）
  @State private listEpoch: number = 0;
  // 两库广播读点（子库页写操作广播——在场时计数即时刷新；onShown 兜底栈下层）
  @StorageProp(MEMORY_LIST_TICK_KEY) @Watch('onMemoryTick') memoryTick: number = 0;
  @StorageProp(ASSISTANT_MEMORY_LIST_TICK_KEY) @Watch('onAssistantTick') assistantTick: number = 0;
  // 整理 / 优化进行中计数（MemoryGen / MemoryOpt 起止广播——状态行区两提示行，键自
  // MemoryPage 旧版随迁）
  @StorageProp(MEMORY_SINKING_KEY) sinkingCount: number = 0;
  @StorageProp(MEMORY_OPT_RUNNING_KEY) optRunning: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    // 分段下标与持久键初值对齐（声明处默认 inject 不代表键实际值——切过按需读取的存量
    // 用户进页须亮「按需读取」段）
    this.readModeIndex = this.memoryReadMode === MEMORY_READ_MODE_TOOL ? 1 : 0;
    this.loadLibraries();
  }

  // 库列表组装：全局库计数 + 助手全量（含内置两张）逐库计数——Promise.all 并行取数，
  // 顺序恒 = 全局第一 + 助手页顺序（queryAssistants 恒列内置两张头部）
  private loadLibraries(): void {
    queryAssistants()
      .then((assistants: AssistantRow[]): Promise<MemoryLibraryItem[]> => {
        const reads: Promise<MemoryLibraryItem>[] = [countMemories().then((count: number): MemoryLibraryItem => {
          return { id: MEMORY_SCOPE_GLOBAL, title: '全局记忆', count: count, isGlobal: true };
        })];
        for (const row of assistants) {
          const assistant: AssistantRow = row;
          reads.push(countAssistantMemories(assistant.id)
            .then((count: number): MemoryLibraryItem => {
              return { id: assistant.id, title: assistant.name, count: count, isGlobal: false };
            })
            .catch((_e: Object): MemoryLibraryItem => {
              return { id: assistant.id, title: assistant.name, count: 0, isGlobal: false };
            }));
        }
        return Promise.all(reads);
      })
      .then((items: MemoryLibraryItem[]): void => {
        this.libs = items;
        this.listEpoch = this.listEpoch + 1;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '记忆库读取失败：' + (e as Error).message });
      });
  }

  // 两库广播读点（重拉幂等——子库页写操作后计数随刷）
  private onMemoryTick(): void {
    this.loadLibraries();
  }

  private onAssistantTick(): void {
    this.loadLibraries();
  }

  // 开关组卡行数据（总开关 + 自动整理；@StorageLink 写即持久化）
  private switchGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.memory_module'),
        label: SETTING_TITLE_MEMORY_ENABLED,
        secondary: '总开关，关闭后不注入也不沉淀',
        toggleValue: (): boolean => this.memoryEnabled,
        onToggle: (isOn: boolean): void => {
          this.memoryEnabled = isOn;
        }
      },
      {
        icon: $r('sys.symbol.arrow_2_circlepath'),
        label: SETTING_TITLE_MEMORY_AUTO,
        secondary: '退出会话时自动沉淀一次记忆',
        toggleValue: (): boolean => this.memoryAuto,
        onToggle: (isOn: boolean): void => {
          this.memoryAuto = isOn;
        }
      }
    ];
  }

  // 组卡重建键（§4.1 刷新责任——键含两开关值）
  private switchGroupKey(): string {
    return String(this.memoryEnabled) + '|' + String(this.memoryAuto);
  }

  // 用户点分段 → 写读取方式持久键（下标 0 = inject / 1 = tool；互设守卫同值不递归）
  private onReadModeIndexChanged(): void {
    const mode: string =
      this.readModeIndex === 1 ? MEMORY_READ_MODE_TOOL : MEMORY_READ_MODE_INJECT;
    if (mode !== this.memoryReadMode) {
      this.memoryReadMode = mode;
    }
  }

  // 其他写键方 → 补正分段下标（@StorageLink 自动响应，页面在途时 UI 随键同步——
  // PreferencesPage.onBiometricChanged 同款契约；当前无第二写键方，守卫留作备份导入
  // 恢复等路径的对位）
  private onReadModeChanged(): void {
    const idx: number = this.memoryReadMode === MEMORY_READ_MODE_TOOL ? 1 : 0;
    if (idx !== this.readModeIndex) {
      this.readModeIndex = idx;
    }
  }

  // 库列表重建键（纪元 + 各库计数——子库页增删改后计数变化必重建）
  private listKey(): string {
    let key: string = 'libs|' + this.listEpoch;
    for (const item of this.libs) {
      key += '|' + item.id + ':' + item.count;
    }
    return key;
  }

  // 点库卡 → push 库管理页（onPop 重拉计数——坑17：子页 pop 带 result 才触发）
  private openLibrary(item: MemoryLibraryItem): void {
    const param: MemoryLibraryParam = { libraryId: item.id };
    this.pathStack.pushPathByName(ROUTE_MEMORY_LIBRARY_PAGE, param, (): void => {
      this.loadLibraries();
    });
  }

  // 内容区
  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 开关组卡 + 状态行区（总开关关时的停用说明行；进行中提示自 2026-09-11 随键
        //    上移落本区——键现居子库页，两提示行随状态键保留在此全局位置）──
        Column({ space: 6 }) {
          SectionHeader({
            title: '记忆开关',
            subtitle: '注入与沉淀的全局控制',
            hint: '「立即整理」用功能模型页里「记忆提取」卡的模型，未选择时不能整理。「优化记忆」用「记忆优化」卡的模型，未选择时不能优化，它会对已有条目做去重与改写，先给出改动摘要，确认后才应用。两个键在各记忆库的管理页里。'
          })
          ForEach([this.switchGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.switchGroup() })
          }, (key: string): string => key)
          // 读取方式分段卡（2026-09-13 记忆按需读取，方案 §2.7——形制照 PreferencesPage
          // 加密会话分段卡先例；★ 说明小字在操作行上方（宪法「功能设置卡布局次序」条）；
          // 独立分段卡而非组卡加行——GroupEntryItem 无分段行形态，扩共享组件违克制）
          Column({ space: 10 }) {
            Column({ space: 2 }) {
              Text(SETTING_TITLE_MEMORY_READ_MODE)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('按需读取时不再自动携带记忆，助手需要时会调用检索。需模型支持工具调用。')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            Column() {
              SegmentBar({
                items: this.readModeItems,
                selectedIndex: $readModeIndex
              })
            }
            .width('100%')
            .height(SEGMENT_BAR_HEIGHT)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .width(CARD_PANEL_WIDTH)
          // 行内提示行形制（13fp cardDescColor + CARD_PANEL_WIDTH，无卡底）——原独立全宽
          // 卡删卡降为说明行（2026-09-09 决明对齐规范口径）
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

        // ── 记忆库列表 ──
        Column({ space: 6 }) {
          SectionHeader({
            title: '记忆库',
            subtitle: this.libs.length + ' 个',
            hint: '全局记忆所有助手共用。助手编辑页可为每名助手选择使用助手记忆或全局记忆。每个库上限 200 条。'
          })
          ForEach([this.listKey()], (_key: string) => {
            Column({ space: CARD_SPACING }) {
              ForEach(this.libs, (item: MemoryLibraryItem) => {
                this.LibraryRowCard(item)
              }, (item: MemoryLibraryItem): string => item.id)
            }
            .width('100%')
          }, (key: string): string => key)
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

  // 库卡（入口卡：标题 + 副行计数 + 尾部 chevron；形制对齐行卡族 Button(Normal) +
  // CARD_PANEL_WIDTH + cardBg + 圆角 16 + padding 14——2026-09-12 UI 同形异构归一笔口径）
  @Builder
  LibraryRowCard(item: MemoryLibraryItem) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.isGlobal ? item.count + ' 条 · 所有助手共用' : item.count + ' 条')
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_secondary')])
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
      this.openLibrary(item);
    })
  }

  build() {
    PageShell({
      title: SETTING_TITLE_MEMORY,
      // 页面每次显示重拉（坑25 定稿——子库页增删改/整理/优化后回本页计数随刷）
      onShown: (): void => {
        this.loadLibraries();
      },
      // 标题栏无键（★ 2026-09-20 操作面下放二级库页——原〔＋|⋯〕胶囊与「更多」菜单整组
      // 随迁 MemoryLibraryPage，本页 menuHds 缺省 null、menuNav 缺省空数组 = 无键）
      content: (): void => {
        this.Content();
      }
    })
  }
}
