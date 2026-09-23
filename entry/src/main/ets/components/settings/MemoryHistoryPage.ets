// 记忆历史页（2026-09-22 记忆优化历史，方案-记忆优化历史-20260922 §7.2）：记忆库管理页
// 「更多」菜单「记忆历史」项 push 的三级页——列出该库最近的改动前快照（before_opt 优化前 /
// before_import 导入前，★ 2026-09-22 记忆导入笔新增第三值：两类共用同一份配额）与一份恢复前
// 兜底（before_restore），行卡右侧恢复键可整库回退到那一版。
// · 入口库上下文：push param 复用 MemoryLibraryParam（声明单源在 MemoryPage.ets，本页只
//   import 消费——**禁本地复写**：两份声明字段漂移编译不报错，undefined 会被 typeof 兜到
//   'global'，点某助手库的历史会静默显示全局库的（2026-09-20 D3-5 事故同族））。
// · 数据：aboutToAppear + onShown 各拉一次（坑25 定稿「onShown 是可靠姿势」——广播在栈下层
//   收不到时的兜底）；列表重建走纪元键（ForEach 键含纪元，坑16 家族防同键不刷）。
// · 顺序：createdAt 降序（queryMemorySnapshots 保证）——兜底槽必然排最前，因为它恒是最近
//   写入的那一份。
// · 行卡形制：抄库管理页 MemoryRowCard（Button(Normal) + CARD_PANEL_WIDTH + cardBg +
//   圆角 16 + padding 14）；恢复键 = 行卡右侧图标键（Button TEXTUAL 包裹 SymbolGlyph，
//   先例 AttachmentManagePage / AssistantPage），**禁垫 fallbackButton*/resolvedButton* 四件套**
//  （宪法「行内操作按钮官方形制」条）。
// · 恢复是破坏性动作，禁止一点即执行——必须过确认弹窗（D6），且恢复前由存储层自动把当前态
//   存进独立兜底槽，使恢复本身也可撤销（D4）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { SectionHeader } from '../SectionHeader';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ROUTE_MEMORY_HISTORY_PAGE, ROUTE_MEMORY_SNAPSHOT_PAGE } from '../../common/RouteNames';
import {
  countAssistantMemories, countMemories, MEMORY_SCOPE_GLOBAL, MEMORY_SNAPSHOT_KIND_IMPORT,
  MEMORY_SNAPSHOT_KIND_RESTORE, MemorySnapshotRow, queryMemorySnapshots, restoreMemorySnapshot
} from '../../common/store/MemoryDb';
import { MemoryLibraryParam } from './MemoryPage';

// 快照详情页 push 参数载体（声明单源 = 本页（发起方），消费方 MemorySnapshotPage import）
export interface MemorySnapshotParam {
  snapshotId: string;
}

// 快照体量（主行文案——「优化前 · 12 条」/「导入前 · 12 条」/「恢复前 · 12 条」；kindLabel
// 单源此处）。★ 2026-09-22 记忆导入笔：二元式扩三态——导入链存的快照 kind = 'before_import'
// （MEMORY_SNAPSHOT_KIND_IMPORT），若沿用原二元式会被标成「优化前」（说的是另一件事）
function snapshotKindLabel(kind: string): string {
  if (kind === MEMORY_SNAPSHOT_KIND_RESTORE) {
    return '恢复前';
  }
  if (kind === MEMORY_SNAPSHOT_KIND_IMPORT) {
    return '导入前';
  }
  return '优化前';
}

@Component
export struct MemoryHistoryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 目标库（aboutToAppear 从 push param 解析）：'global' = 全局库 / 助手 id = 助手库
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
        this.snapshots = rows;
        this.listEpoch = this.listEpoch + 1;
        const readCount: Promise<number> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
          countMemories() : countAssistantMemories(this.libraryId);
        readCount
          .then((count: number): void => {
            this.currentCount = count;
          })
          .catch((): void => {
            // 计数失败只影响确认正文的数字，不阻断列表——保持上一次值
          });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '历史读取失败：' + (e as Error).message
        });
      });
  }

  // 列表重建键（纪元——每次 reload 自增）
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
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '已恢复到该版本。' });
      })
      .catch((e: Object): void => {
        // 错误原文照上屏（禁止吞掉——P0-1，用户要知道为什么没恢复）
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        Column({ space: 6 }) {
          SectionHeader({
            title: '记忆历史',
            subtitle: this.snapshots.length + ' 份',
            // 页内说明：每库保留口径 + 兜底槽语义（两库同口径）；★ 2026-09-22 记忆导入笔：
            // 存档触发面由「优化」扩为「优化或导入」——不更新会让用户看到「导入前」快照时
            // 以为来了不该来的东西
            hint: '每次优化记忆或导入记忆前会自动存档，最多保留三次。恢复某一版之前也会自动存一份，所以恢复可以撤销一次。历史只存在本机，不随备份导出。'
          })
          if (this.snapshots.length === 0) {
            // 空态行内提示（无卡——行内提示行形制，与库管理页空态同款）
            Text('还没有历史记录。优化记忆或导入记忆前会自动存档，最多保留三次。')
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
  }

  // 快照行卡：主行「<kind 标签> · 12 条」（优化前 / 导入前 / 兜底槽 = 恢复前；映射单源 =
  // 本页 snapshotKindLabel）+ 副行「时间 · 摘要」+ 右侧恢复键；整卡点击进详情
  @Builder
  SnapshotRowCard(row: MemorySnapshotRow) {
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
        // 恢复键（行卡右侧图标键：官方 TEXTUAL 无底 + font_secondary，宪法「行内操作按钮
        // 官方形制」条；符号 arrow_counterclockwise = 逆时针箭头回退语义，SDK 符号表实锤
        // 码位 0xF00C8 + 128px 渲染核验 + 同机先例 cubeagent-stream-test「恢复内置」）
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
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.openSnapshotDetail(row);
    })
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
}
