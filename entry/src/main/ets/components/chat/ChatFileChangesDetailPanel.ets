// 会话改动文件详情半模态面板（任务② 会话改动文件清单 U5）：清单卡文件行的详情载体——
// 头部（末次操作徽标 + 目录副行〔dir 已知才显示〕）+ 该文件操作流水按消息序（每段 = 操作徽标
// + diff 渲染或回执原文说明行；无时间列——timeMs 恒为轮起始时刻非操作真实时刻，显示即失真）。
// · 宿主 = ChatPage 坑64 单挂载点 sheetKind 机 'fileChanges' 分支（无新 bindSheet 宿主——
//   关闭链五件式全承既有机，规范-半模态 §8 已登记）；面板零暂存 → 无关闭确认、下拉直落。
// · 形制 = ContextUsageSheet 同款三件套（HdsNavigation MODAL 壳 + sheetTitleBarOptions +
//   bindToScrollable + 底部安全区延伸），滚动容器 clip(false) + scrollBar(Off)（规范 §2）；
//   卡体 CARD_PANEL_WIDTH + padding 16 + CARD_RADIUS（同面板族）。
// · 「在工作区中查看」键与整条工作区定位链已退役（2026-11-04 两千零九十节）：七件写工具
//   schema 的 dir 非必填且缺省落助手默认文件夹，聚合模型只读 argsJson 原值无从复原，dir 空的
//   行点键只能弹「未定位到该文件所在目录」= 常态不可用。用户自行进 设置 → 文件工作区 查看。
//   本面板保留目录副行作纯展示（dir 已知才显示，空 dir 不标「根目录」防误导）。
// · 段视图派生时点（性能红线）：aboutToAppear **首帧前一次完成**（每段 ≤100 行/侧 =
//   ChatToolDiffBlock 既有界常数），构建函数零解析；数据面 = entry.ops 源消息引用开时重派
//   （与装配期「只取计数弃 rows」口径呼应——rows 单源在此重算）。徽标映射引用
//   ChatFileChangesCard 导出单源（fileChangeBadgeTone/Text，禁第二实现）；删除段徽标恒危险档。
// · 说明行段（import / xlsx / delete / rename / move）显**回执原文**（零新文案；回执自身
//   有界，maxLines 8 + ellipsis 兜底）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_RADIUS,
  CARD_SPACING } from '../../common/Theme';
import { ChatToolDiffBlock, TOOL_DIFF_MAX_ROW_CHARS, TOOL_DIFF_MAX_ROWS_PER_SIDE,
  ToolDiffView, deriveToolDiffRows, parseJsonRecord, receiptPairDiffFromOutput,
  workspaceEditDiffFromInput } from './ChatToolDiffBlock';
import { FileChangeEntry, FileChangeOp, OP_DELETE, OP_EDIT, OP_WRITE_NEW,
  OP_WRITE_OVERWRITE } from './ChatFileChangesModel';
import { fileChangeBadgeText, fileChangeBadgeTone } from './ChatFileChangesCard';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';

// 面板段视图（aboutToAppear 一次派生；diff = 该段 diff 视图——null = 说明行段；seq = ops
// 数组下标——ForEach 键成分，见段卡键注释）
interface PanelOpSegment {
  op: FileChangeOp;
  diff: ToolDiffView | null;
  seq: number;
}

// write 新建段的 content 取值（argsJson 坏 / 缺 content 回 ''——空内容全绿 0 行，如实）
function writeNewContentOf(inputJson: string): string {
  const parsed: Record<string, Object> | null = parseJsonRecord(inputJson);
  if (parsed === null) {
    return '';
  }
  const raw: Object | undefined = parsed['content'];
  return typeof raw === 'string' ? raw : '';
}

// 单段 diff 视图（口径与 ChatFileChangesModel.opCountsFor 同判据同源；maxRows 取
// ChatToolDiffBlock 既有界常数——开面板重派生 rows，统计与装配期计数同函数族）
function opDiffViewOf(op: FileChangeOp): ToolDiffView | null {
  if (op.kind === OP_EDIT) {
    return workspaceEditDiffFromInput(op.msg.toolInputJson ?? '',
      TOOL_DIFF_MAX_ROWS_PER_SIDE, TOOL_DIFF_MAX_ROW_CHARS);
  }
  if (op.kind === OP_WRITE_OVERWRITE) {
    return receiptPairDiffFromOutput(op.msg.toolOutputJson ?? '',
      TOOL_DIFF_MAX_ROWS_PER_SIDE, TOOL_DIFF_MAX_ROW_CHARS);
  }
  if (op.kind === OP_WRITE_NEW) {
    return deriveToolDiffRows('', writeNewContentOf(op.msg.toolInputJson ?? ''),
      TOOL_DIFF_MAX_ROWS_PER_SIDE, TOOL_DIFF_MAX_ROW_CHARS);
  }
  return null; // import / xlsx / delete / rename / move 段 = 说明行
}

// 段视图派生入口（entry 防御 null 回空——面板零渲染）
function derivePanelSegments(entry: FileChangeEntry | null): PanelOpSegment[] {
  if (entry === null) {
    return [];
  }
  const out: PanelOpSegment[] = [];
  for (let i = 0; i < entry.ops.length; i++) {
    out.push({ op: entry.ops[i], diff: opDiffViewOf(entry.ops[i]), seq: i });
  }
  return out;
}

@Component
export struct ChatFileChangesDetailPanel {
  // 目标文件（清单卡 onOpenDetail 上行 → 宿主 fileDetail 快照传入；面板寿命内不变）
  entry: FileChangeEntry | null = null;
  // 关闭上行（标题栏 xmark → 宿主 closeSheet 单入口）
  onClose: () => void = () => {
  };
  // 底部系统导航条高（宿主 bottomPad 注入——尾部占位）
  bottomInset: number = 0;
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 正文字体两键 @StorageProp 自订阅（2026-11-04 字体补接笔）：面板是清单卡文件行的展开面，
  // 卡内文字（文件名 / 目录 / 回执说明行 / 定位键 / 操作徽标）与清单卡同口径随正文字体
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  private scroller: Scroller = new Scroller();
  // 段视图（aboutToAppear 首帧前一次派生——构建函数零解析；普通成员：面板寿命内一次定型）
  private segments: PanelOpSegment[] = [];

  aboutToAppear(): void {
    this.segments = derivePanelSegments(this.entry);
  }

  // 段徽标档位（面板段级口径：删除段恒危险档；其余与清单卡行徽标同源映射）
  private segTone(op: FileChangeOp): BadgeTone {
    if (op.kind === OP_DELETE) {
      return BadgeTone.DANGER;
    }
    return fileChangeBadgeTone(op.kind, false);
  }

  // 正文字体家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          // ── 头部卡：末次徽标 + 文件名 + 目录副行 ──
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              StatusBadge({
                text: fileChangeBadgeText(this.entry?.lastOpKind ?? '',
                  this.entry?.deleted ?? false),
                tone: fileChangeBadgeTone(this.entry?.lastOpKind ?? '',
                  this.entry?.deleted ?? false),
                fontFamily: this.resolveBodyFamily()
              })
              Text(this.entry?.displayName ?? '')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardTitleColor())
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            // 目录副行只在 dir 已知时显示（空 dir 语义不明——与清单卡目录段同口径，防误导）
            if (this.entry !== null && this.entry.dir !== '') {
              Text(this.entry.dir)
                .fontSize(13)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardDescColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .borderRadius(CARD_RADIUS)
          .backgroundColor(cardBg(this.appColorMode))
          .alignItems(HorizontalAlign.Start)

          // ── 操作流水段卡（时间序 = ops 消息序；段头无时间列——timeMs 全段恒为轮起始时刻
          //（stampRoundMeta 继承 + 历史链归一），非操作真实时刻，显示即失真，最小改 = 隐去）──
          ForEach(this.segments, (seg: PanelOpSegment): void => {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                StatusBadge({
                  text: fileChangeBadgeText(seg.op.kind, false),
                  tone: this.segTone(seg.op),
                  fontFamily: this.resolveBodyFamily()
                })
                Blank()
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              if (seg.diff !== null) {
                ChatToolDiffBlock({ diff: seg.diff as ToolDiffView })
              } else if (seg.op.msg.toolOutputJson !== undefined &&
                seg.op.msg.toolOutputJson !== '') {
                // 说明行段 = 回执原文（零新文案；maxLines 8 兜底数据有界）
                Text(seg.op.msg.toolOutputJson)
                  .fontSize(13)
                  .fontFamily(this.resolveBodyFamily())
                  .fontColor(cardDescColor())
                  .width('100%')
                  .maxLines(8)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .borderRadius(CARD_RADIUS)
            .backgroundColor(cardBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
            // 段键 = kind + seq（ops 数组下标）+ 计数形态：原 timeMs 成分在同轮内恒为轮起始
            // 同值（撞键源——同文件同种类同计数两操作必重），换 seq 后键唯一；稳定性 = segments
            // 为 aboutToAppear 一次派生的快照（面板寿命内不变，bindSheet 关闭销毁重开重建），
            // seq 随数组位固定不漂移
          }, (seg: PanelOpSegment): string =>
            seg.op.kind + '#' + String(seg.seq) + '#' +
            (seg.diff !== null ? String(seg.diff.additions) + '-' + String(seg.diff.deletions) : 'n'))
          // 尾部安全区让位（Row 空占位——Blank 在 ListItem 下编译 10905201，规范-半模态 §2）
          Row()
            .height(this.bottomInset)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('文件改动详情', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
