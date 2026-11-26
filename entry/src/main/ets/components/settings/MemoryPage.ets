// 记忆页一级：顶部 info 蓝卡 +「记忆开关」板块（组卡 = 两开关行在前 +「读取方式」标题与
// 右置分段胶囊末行；2026-11-09 决明拍板换序：先决定要不要记忆，再决定怎么读）+ 状态行区
// +「记忆库」板块（库卡列表）。库列表 = 全局记忆恒列首位
// （所有助手共用 memories 表）+ 各助手记忆库（assistant_memories 表）；点库卡 push
// MemoryLibraryPage（param = { libraryId }）进库管理。
// · 作用域语义（拍板 2）：助手编辑页「记忆」子页二选一——'global' 默认全局记忆（存量行为
//   原样）/ 'assistant' 助手记忆（注入/沉淀/检索全走自己的库，不混注）；本页库列表 = 两库
//   统一巡检入口（零条库也列出，点进可新建）。
// · 刷新链：onShown 重拉（坑25 定稿姿势）；两库广播键各挂 @StorageProp @Watch（子库页写
//   操作后在场即时刷新，onShown 兜底）。
// · 总开关/自动整理/读取方式 = 全局配置（拍板 6 留一级页），消费方与语义见 MemoryGen 键族注释。
// · 组卡化：原「开关卡 + 读取方式分段卡」合为一卡；分段胶囊与标题同行左右并排（官方组件宽 =
//   父容器宽，外层取 SEGMENT_BAR_ROW_WIDTH 定宽）；分割线 = 两开关行之间一条 + 末行上方一条；
//   板块头 ⓘ 气泡退役，说明收进板块首 info 蓝卡（InfoCard 单源）。info 是页面首元素、在板块头之上。
// · 长列表 = List + Repeat.virtualScroll（V1 壳 + V2 渲染件桥接，规范 §4.6）：键只写库 id，
//   计数变化靠同 id 新对象 item 比对刷新（原纪元键 listKey 退役）；头槽挂开关区与板块头；
//   让位 offset 轨；0 行分支壳侧 Scroll 兜底（防御性——常态 ≥1 行）。
// · 操作面全部下放二级库页 MemoryLibraryPage，本页标题栏无键。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items, UIUtils } from '@kit.ArkUI';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, SEGMENT_BAR_ROW_WIDTH,
  SECTION_GAP, SECTION_HEADER_GAP, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { InfoCard } from '../InfoCard';
import { SettingSwitchRow } from './FunctionalSettingRows';
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

// 记忆开关板块 info 蓝卡正文（两处旧说明收敛的单点；文案规约：句号分句，无冒号分号括号连环）
const MEMORY_CONTROLS_INFO: string = '自动注入随请求携带记忆，按需读取由助手调用检索，需模型支持工具调用。' +
  '整理与优化分别用功能模型页「记忆提取」「记忆优化」卡的模型，未选择时对应键不可用。' +
  '两个键在各记忆库的管理页。';

// 库列表项（reload 组装——id = 'global' | 助手 id；isGlobal = 全局库卡恒列首位的标记）
interface MemoryLibraryItem {
  id: string;
  title: string;
  count: number;
  isGlobal: boolean;
}

// 助手记忆库列表 push 参数载体（export = 跨文件形态单源——消费侧必须 import 本声明，禁本地
// 复写：字段漂移编译不报错，undefined 被 typeof 兜底会静默落到全局库，D3-5 事故）
export interface MemoryLibraryParam {
  libraryId: string;
}

@Component
export struct MemoryPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 两持久开关（@StorageLink 写即持久化——EntryAbility persistProp 注册）
  @StorageLink(MEMORY_ENABLED_KEY) memoryEnabled: boolean = true;
  @StorageLink(MEMORY_AUTO_KEY) memoryAuto: boolean = false;
  // 读取方式（'inject' 自动注入默认 / 'tool' 按需读取；@StorageLink 写即持久化，下标与键
  // 双向映射见 onReadModeIndexChanged / onReadModeChanged）
  @StorageLink(MEMORY_READ_MODE_KEY) @Watch('onReadModeChanged') memoryReadMode: string =
    MEMORY_READ_MODE_INJECT;
  @State @Watch('onReadModeIndexChanged') readModeIndex: number = 0;
  // 分段选项（顺序契约：下标 0 = 自动注入（键 'inject'）/ 1 = 按需读取（键 'tool'），勿乱调）
  private readModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '自动注入' },
    { text: '按需读取' }
  ]);
  // 库列表（整体替换即刷——计数变化靠同 id 新对象 item 比对刷新）
  @State private libs: MemoryLibraryItem[] = [];
  // 两库广播读点（子库页写操作广播——在场时计数即时刷新；onShown 兜底栈下层）
  @StorageProp(MEMORY_LIST_TICK_KEY) @Watch('onMemoryTick') memoryTick: number = 0;
  @StorageProp(ASSISTANT_MEMORY_LIST_TICK_KEY) @Watch('onAssistantTick') assistantTick: number = 0;
  // 整理 / 优化进行中计数（起止广播——状态行区两提示行）
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

  // 库列表组装：全局计数 + 助手全量逐库计数（Promise.all 并行；顺序 = 全局第一 + 助手页顺序）
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
        if (this.departed) {
          return;
        }
        this.libs = items;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
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

  // 其他写键方 → 补正分段下标（页面在途时 UI 随键同步；当前无第二写键方，守卫留作备份导入
  // 恢复等路径的对位）
  private onReadModeChanged(): void {
    const idx: number = this.memoryReadMode === MEMORY_READ_MODE_TOOL ? 1 : 0;
    if (idx !== this.readModeIndex) {
      this.readModeIndex = idx;
    }
  }

  // 点库卡 → push 库管理页（onPop 重拉计数——坑17：子页 pop 带 result 才触发）
  private openLibrary(item: MemoryLibraryItem): void {
    const param: MemoryLibraryParam = { libraryId: item.id };
    this.pathStack.pushPathByName(ROUTE_MEMORY_LIBRARY_PAGE, param, (): void => {
      this.loadLibraries();
    });
  }

  // ── 开关区（info 蓝卡 + 板块头 + 开关组卡 + 状态行区；迁 Repeat 后抽独立 @Builder，
  //    非空分支经头槽进 V2 首行、空分支直挂）──
  @Builder
  ControlsSection() {
    Column({ space: SECTION_HEADER_GAP }) {
      // info 蓝卡（页首独立、板块头之上；InfoCard 缺省挂 CARD_PANEL_WIDTH）
      InfoCard({ text: MEMORY_CONTROLS_INFO })
      SectionHeader({ title: '记忆开关' })
      ForEach([this.switchGroupKey()], (_key: string) => {
        Column() {
          // ★ 2026-11-09 换序（决明拍板）：先决定「要不要记忆」再决定「怎么读」——
          // 两开关行在卡头，读取方式分段行移卡末。首行 dividerTop=false（卡顶不画线），
          // 其余行各带一条分割线（FunctionalSettingRows 头注释「每张卡首行 false」口径）。
          SettingSwitchRow({
            label: SETTING_TITLE_MEMORY_ENABLED,
            subtitle: '总开关，关闭后不注入也不沉淀',
            isOn: this.memoryEnabled,
            dividerTop: false,
            onToggle: (isOn: boolean): void => {
              this.memoryEnabled = isOn;
            }
          })
          SettingSwitchRow({
            label: SETTING_TITLE_MEMORY_AUTO,
            subtitle: '退出会话时自动沉淀一次记忆',
            isOn: this.memoryAuto,
            dividerTop: true,
            onToggle: (isOn: boolean): void => {
              this.memoryAuto = isOn;
            }
          })
          // 末行上方分割线（与 SettingSwitchRow.dividerTop 同形制：0.5vp + 卡内 12/8 让位）
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .margin({ left: 12, right: 8 })
          // 读取方式行：左标题 + 右置分段胶囊（官方组件宽 = 父容器宽，外层取
          // SEGMENT_BAR_ROW_WIDTH 定宽；左右 12 = 行内容左缘，与行标题同竖线、与 Toggle 同右缘）
          // 标题常量与 AI set_pref 白名单名同源（set-pref-tool-check 钉读本处消费位）
          Row() {
            Text(SETTING_TITLE_MEMORY_READ_MODE)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Column() {
              SegmentBar({
                items: this.readModeItems,
                selectedIndex: $readModeIndex
              })
            }
            .width(SEGMENT_BAR_ROW_WIDTH)
            .height(SEGMENT_BAR_HEIGHT)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText(SETTING_TITLE_MEMORY_READ_MODE)
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 4, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
      }, (key: string): string => key)
      // 行内提示行形制（13fp cardDescColor + CARD_PANEL_WIDTH，无卡底）
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
  }

  // 库列表板块头（只留标题——副标题行 2026-11-01 退役）
  @Builder
  LibsHead() {
    SectionHeader({
      title: '记忆库',
      hint: '全局记忆所有助手共用，助手编辑页可为每名助手单独选择。控制台助手不参与记忆。每个库上限 200 条。'
    })
  }

  // 非空分支头槽（开关区 + 库板块头，两板块间隙 SECTION_GAP；头槽末段到首卡间距由渲染域承担）
  @Builder
  RowsHead() {
    Column({ space: SECTION_GAP }) {
      this.ControlsSection()
      this.LibsHead()
    }
    .width('100%')
  }

  // 内容区（>0 行走渲染域 MemoryLibRows，0 行壳侧 Scroll 兜底——防御性分支，常态 ≥1 行；
  // 两分支同一套板块 Builder 单一来源）
  @Builder
  Content() {
    if (this.libs.length === 0) {
      Scroll() {
        Column({ space: SECTION_GAP }) {
          this.ControlsSection()
          Column({ space: SECTION_HEADER_GAP }) {
            this.LibsHead()
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
      .scrollBar(BarState.Off)
    } else {
      MemoryLibRows({
        libs: UIUtils.enableV2Compatibility(this.libs),
        appColorMode: this.appColorMode,
        topPad: this.topPad,
        bottomPad: this.bottomPad,
        headSlot: (): void => {
          this.RowsHead()
        },
        onOpen: (item: MemoryLibraryItem): void => {
          this.openLibrary(item);
        }
      })
        .width('100%')
        .height('100%')
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_MEMORY,
      // 页面每次显示重拉（坑25 定稿——子库页增删改/整理/优化后回本页计数随刷）
      onShown: (): void => {
        this.loadLibraries();
      },
      // 标题栏无键（操作面下放二级库页，本页 menuHds 缺省 null；menuNav 形参已随
      // 2026-10-31 撤 HDS 回退兜底笔从 PageShell 退役）
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

// ═══ 记忆库列表渲染域（迁 Repeat 拆出，同文件同域——壳引渲染件单向）═══
// List + Repeat.virtualScroll（V2）：数据源壳侧构造处桥接；键只写库 id；头槽 = 壳侧开关区 +
// 库板块头挂首行随内容滚；让位 offset 轨；0 行壳侧分支渲染。计数变化 = 同 id 新对象 item 比对。
@ComponentV2
struct MemoryLibRows {
  // 库列表（壳侧构造处桥接传入——Repeat 懒加载要求数据源具 V2 观察能力）
  @Param libs: MemoryLibraryItem[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 首行头槽（开关区 + 库板块头——壳侧 V1 Builder）
  @BuilderParam headSlot: () => void;
  // 点库卡上行（壳侧 push 库管理页；★ 读当前 ri.item，禁构造期快照）
  @Event onOpen: (item: MemoryLibraryItem) => void = () => {
  };

  // 库卡（入口卡：标题 + 副行计数 + 尾部 chevron；Button(Normal) + CARD_PANEL_WIDTH +
  // cardBg + CARD_RADIUS + 卡 padding 4 + 壳 padding 10）
  @Builder
  LibraryRowCard(ri: RepeatItem<MemoryLibraryItem>) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(ri.item.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(ri.item.isGlobal ? ri.item.count + ' 条 · 所有助手共用' : ri.item.count + ' 条')
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
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding(10)
      .onClick((): void => {
        this.onOpen(ri.item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    List({ space: CARD_SPACING }) {
      Repeat<MemoryLibraryItem>(this.libs)
        .each((ri: RepeatItem<MemoryLibraryItem>) => {
          ListItem() {
            // 首行 = 头槽 + 首卡（原库板块标题与卡间隙同构；保真层 Column 居中）
            Column({ space: SECTION_HEADER_GAP }) {
              if (ri.index === 0) {
                this.headSlot()
              }
              this.LibraryRowCard(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 库 id（'global' | 助手 id，身份唯一；计数不塞键——新对象 item 比对刷新）
        .key((item: MemoryLibraryItem): string => item.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨（原 Scroll padding top/bottom 同值等价）
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 库数 = 助手数 + 1（有界小列表），5 为屏内缓冲（按页设值非全局口径）
    .cachedCount(5)
  }
}
