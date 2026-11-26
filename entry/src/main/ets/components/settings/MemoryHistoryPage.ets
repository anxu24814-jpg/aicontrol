// 记忆历史页：记忆库管理页「更多」菜单「记忆历史」项 push 的三级页——列出该库最近的改动前
// 快照（before_opt 优化前 / before_import 导入前，共用一份配额）与两份兜底槽快照
//（before_restore 恢复前 / before_sink 整理前——各每库 ≤1 份覆盖写），行卡右侧恢复键可整库回退。
// · 入口库上下文：push param 复用 MemoryLibraryParam（声明单源在 MemoryPage.ets，本页只 import
//   消费——**禁本地复写**：字段漂移编译不报错，undefined 会被 typeof 兜到 'global'，静默显示全局库）。
// · 数据：aboutToAppear + onShown 各拉一次（坑25「onShown 是可靠姿势」兜底栈下层广播）；列表
//   重建走纪元键（ForEach 键含纪元，坑16 家族防同键不刷）。顺序 = createdAt 降序——最近写入的
//   那份排最前（通常是刚触发本次进入的动作存下的兜底槽快照）。
// · 行卡形制：抄库管理页 MemoryRowCard（Button(Normal) + CARD_PANEL_WIDTH + cardBg + CARD_RADIUS
//   + padding 14）；恢复键 = 行卡右侧图标键（Button TEXTUAL + SymbolGlyph，禁垫
//   fallbackButton*/resolvedButton*——宪法「行内操作按钮官方形制」条）。
// · 恢复是破坏性动作，禁止一点即执行——必须过确认弹窗；恢复前存储层自动存兜底槽，使恢复可撤销。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_HEADER_GAP, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { SectionHeader } from '../SectionHeader';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ROUTE_MEMORY_HISTORY_PAGE, ROUTE_MEMORY_SNAPSHOT_PAGE } from '../../common/RouteNames';
import {
  countAssistantMemories, countMemories, MEMORY_SCOPE_GLOBAL, MEMORY_SNAPSHOT_KIND_IMPORT,
  MEMORY_SNAPSHOT_KIND_RESTORE, MEMORY_SNAPSHOT_KIND_SINK, MemorySnapshotRow,
  queryMemorySnapshots, restoreMemorySnapshot
} from '../../common/store/MemoryDb';
import { MemoryLibraryParam } from './MemoryPage';

// 快照详情页 push 参数载体（声明单源 = 本页（发起方），消费方 MemorySnapshotPage import）
export interface MemorySnapshotParam {
  snapshotId: string;
}

// 快照体量（主行文案——「优化前 · 12 条」/「导入前 · 12 条」/「整理前 · 12 条」/「恢复前 ·
// 12 条」；kindLabel 单源此处）。kind 取值：导入 = 'before_import'（沿用二元式会被标成
// 「优化前」，说的却是另一件事）；整理 = 'before_sink'（**中性词**——手动「立即整理」与退出
// 会话自动整理走同一条存档链，写「自动整理前」在手动场景是假话）；兜底回 '优化前'
function snapshotKindLabel(kind: string): string {
  if (kind === MEMORY_SNAPSHOT_KIND_RESTORE) {
    return '恢复前';
  }
  if (kind === MEMORY_SNAPSHOT_KIND_SINK) {
    return '整理前';
  }
  if (kind === MEMORY_SNAPSHOT_KIND_IMPORT) {
    return '导入前';
  }
  return '优化前';
}

@Component
export struct MemoryHistoryPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  // 该库全部快照（createdAt 降序；payload 不解析——列表只需 itemCount）
  @State private snapshots: MemorySnapshotRow[] = [];
  // 当前库条数（恢复确认正文要写「当前 N 条将被替换为 M 条」——N 取现读，不缓存）
  @State private currentCount: number = 0;
  // 列表重建纪元（reload 成功自增——键含「库身份 + 纪元」，坑16 家族防同键不刷）
  @State private listEpoch: number = 0;
  // 恢复确认弹窗（坑7：CustomDialogController 组件成员位按需构造——message 依赖本次快照）
  private restoreConfirmCtrl: CustomDialogController | null = null;
  private restoreTarget: MemorySnapshotRow | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push param 解析（对象形态 { libraryId }；缺省/异常 = 全局库兜底——库管理页同款守卫）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_HISTORY_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last !== null && typeof last !== 'string') {
      const parsed = last as MemoryLibraryParam;
      if (typeof parsed.libraryId === 'string' && parsed.libraryId !== '') {
        this.libraryId = parsed.libraryId;
      }
    }
    this.reload();
  }

  // 快照列表 + 当前库条数（确认正文用）两路并行取数
  private reload(): void {
    queryMemorySnapshots(this.libraryId)
      .then((rows: MemorySnapshotRow[]): void => {
        if (this.departed) {
          return;
        }
        this.snapshots = rows;
        this.listEpoch = this.listEpoch + 1;
        const readCount: Promise<number> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
          countMemories() : countAssistantMemories(this.libraryId);
        readCount
          .then((count: number): void => {
            if (this.departed) {
              return;
            }
            this.currentCount = count;
          })
          .catch((): void => {
            // 计数失败只影响确认正文的数字，不阻断列表——保持上一次值
          });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '历史读取失败：' + (e as Error).message
        });
      });
  }

  private listKey(): string {
    return 'snapshots|' + this.libraryId + '|' + this.listEpoch;
  }

  // 行卡点击 → 快照详情页（只读查看那一版有哪些条目；★ 详情页不设恢复键——恢复入口唯一）
  private openSnapshotDetail(row: MemorySnapshotRow): void {
    const param: MemorySnapshotParam = { snapshotId: row.id };
    this.pathStack.pushPathByName(ROUTE_MEMORY_SNAPSHOT_PAGE, param);
  }

  // 恢复键 → 确认弹窗（禁止一点即执行；正文按本次快照条数与当前库条数动态拼）
  private askRestore(row: MemorySnapshotRow): void {
    this.restoreTarget = row;
    this.restoreConfirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '恢复到此版本',
        message: '当前 ' + this.currentCount + ' 条记忆将被替换为 ' + row.itemCount
          + ' 条，此后新增的记忆会一并移除。恢复后可以撤销一次。',
        confirmLabel: '恢复',
        // 恢复会丢弃当前库内容，比「优化」更重——优化用 NORMAL，恢复必须红键
        confirmTone: ConfirmDialogTone.DANGER,
        onConfirm: (): void => {
          this.doRestore();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.restoreConfirmCtrl.open();
  }

  // 落库（用户确认后）：整库替换（一个事务，见 restoreMemorySnapshot）——失败抛中文错误，
  // 事务已回滚零改动；成功广播由存储层发出（两库广播键各挂读点，返回库管理页自会重拉）
  private doRestore(): void {
    const target: MemorySnapshotRow | null = this.restoreTarget;
    this.restoreTarget = null;
    if (target === null) {
      return;
    }
    restoreMemorySnapshot(target.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '已恢复到该版本。' });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        // 错误原文照上屏（禁止吞掉——P0-1，用户要知道为什么没恢复）
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({
            title: '记忆历史',
            // 页内说明：触发面已扩为「整理、优化、导入」——不更新会让用户看到「导入前」/「整理前」
            // 快照时以为来了不该来的东西
            hint: '每次整理、优化或导入记忆前会自动存档，最多保留三次。恢复某一版前也会自动存档，因此恢复可撤销一次。历史只存在本机，不随备份导出。'
          })
          if (this.snapshots.length === 0) {
            // 空态行内提示（无卡——行内提示行形制，与库管理页空态同款）
            Text('还没有历史记录。整理、优化或导入记忆前会自动存档，最多保留三次。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else {
            ForEach([this.listKey()], (_key: string) => {
              Column({ space: CARD_SPACING }) {
                ForEach(this.snapshots, (row: MemorySnapshotRow) => {
                  this.SnapshotRowCard(row)
                }, (row: MemorySnapshotRow): string => row.id)
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
    .scrollBar(BarState.Off)
  }

  // 快照行卡：主行「<kind 标签> · 12 条」（映射单源 = snapshotKindLabel）+ 副行「时间 · 摘要」+
  // 右侧恢复键；整卡点击进详情。卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding
  // 14→10 回添，几何零位移
  @Builder
  SnapshotRowCard(row: MemorySnapshotRow) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(snapshotKindLabel(row.kind) + ' · ' + row.itemCount + ' 条')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(row.note !== '' ?
              formatConvTime(row.createdAt) + ' · ' + row.note : formatConvTime(row.createdAt))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 恢复键（行卡右侧图标键：官方 TEXTUAL 无底 + font_secondary，宪法「行内操作按钮官方
          // 形制」条；符号 arrow_counterclockwise = 逆时针回退语义，SDK 符号表在册）
          Button() {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick((): void => {
            this.askRestore(row);
          })
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
        this.openSnapshotDetail(row);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    PageShell({
      title: '记忆历史',
      // 页面每次显示重拉（坑25 定稿；本页无下级写动作，纯粹为返回自愈与首帧兜底）
      onShown: (): void => {
        this.reload();
      },
      content: (): void => {
        this.Content();
      },
      // 坑17 范式（与排序页 / 记忆编辑页同）：本页能改库（行卡恢复键 = 整库替换），返回须带
      // result 才触发库管理页 onPop 重拉；本页无保存动作，故拦截官方返回链自己 pop
      //（onShown 兜底通道同挂，两条链并存是坑17 定稿口径：onPop 是可靠原语、onShown 兜底）
      onBackPressed: (): boolean => {
        this.pathStack.pop({ saved: true });
        return true;
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
