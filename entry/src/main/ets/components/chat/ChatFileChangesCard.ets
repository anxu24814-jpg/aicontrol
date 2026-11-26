// 会话改动清单卡（任务② 会话改动文件清单 U3）：轮末合成展示项 kind='fileChanges' 的渲染件
// ——卡头「本轮改动 · N 个文件」+ 行尾红绿总统计，展开区 = 文件行列表（≤20 直排不设滚动
// 容器）+ 溢出计数行，点文件行开 ChatPage 坑64 单挂载点详情面板（onOpenDetail 上行）。
// · 数据契约：item.fileChanges = 装配期一次算成的聚合产物（ChatDisplayProjection
//   buildDisplayItems 轮末后处理遍产出、口径单源 = ChatFileChangesModel 头注释）——本卡
//   **零聚合零缓存**（宪法「组件生命周期禁高耗时」+「性能不许愿」），构建函数零解析，
//   渲染件只消费。
// · 状态最小化（坑44/80 家族红线）：item 必须 **@ObjectLink**（照 ChatProcessSegment
//   :149-150 先例）——changesExpanded 展开意愿经 @Observed 属性赋值驱动刷新（U2 装配复用
//   保延续），普通成员不订阅通知 = 展开/收起静默冻结。展开切换走 **UIContext 版 animateTo**
//   （禁全局 animateTo）；changesExpanded 不进 ForEach 键（键纪律）。
// · 形制来源：行壳 = 消息流行形制（width('100%') + 左右 BUBBLE_PAD_NEAR 内衬 + 上距
//   CARD_SPACING，与既有消息行同源——ChatChartRow / ChatProcessSegment 同款；流自备左右
//   12 边距）；卡体 = cardBg + CARD_RADIUS(20) + padding 14（任务书 U3 规格）。徽标走
//   StatusBadge 四档圆角矩形（**禁胶囊、禁消费侧写 hex、禁第七色**——色板规范 §7「操作徽
//   标 · 会话改动清单卡」已登记，映射函数本件导出单源、详情面板引用同源）。
// · 文案已过「面向用户文案写作规约」预检：本轮改动 · N 个文件 / 另有 N 个文件 /
//   徽标九短词（新建/编辑/覆盖/导入/表格/删除/移动/重命名/已删除）——无冒号分号括号连环
//   （目录副行 dir 已知才显示，空 dir 不标目录——见行内注释）。
// · 显示口径（2026-11-12 偏好开关批）：改动清单卡**恒显示**，原「显示本轮改动清单」偏好
//   已整键退役（行为固化不可关）——build 顶层只判装配产物 fileChanges 是否为空，卡内不再
//   有任何显隐成员；有改动的轮才出现，数据面零影响。
// · 展开中间帧两件（2026-11-04 两千零九十节，照 1799 节过程段出卡中间帧修复范式）：卡体补
//   clip(true) 收「展开时终位文件行画在卡外」；展开区三处条件渲染根补
//   TransitionEffect.IDENTITY 覆盖 animateTo 上下树的默认 OPACITY 淡出（收起时文字延留卡外）。
//   两者均纯绘制层，不测全文高、不冻结内容盒、不改布局——显式高度链已于 d62403d7 真机证伪
//   退役，109 组负向钉禁回流。
import { ChatDisplayItem } from './ChatDisplayProjection';
import { FileChangeEntry, OP_DELETE, OP_EDIT, OP_IMPORT, OP_MOVE,
  OP_RENAME, OP_WRITE_NEW, OP_WRITE_OVERWRITE, OP_XLSX, RoundFileChanges } from './ChatFileChangesModel';
import { StatusBadge, BadgeTone } from '../StatusBadge';
import { cardBg, cardBorderColor, cardDescColor, cardTitleColor, BUBBLE_PAD_NEAR,
  CARD_RADIUS, CARD_SPACING, DIFF_ADDITION_COLOR, DIFF_DELETION_COLOR } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';

// 操作徽标档位映射（色板规范 §7 登记，单源 = 本函数；详情面板头部徽标引用同源）：
// 新建 = 成功（结果性新建成）/ 编辑·覆盖·导入·表格 = 强调（常规变更）/ 删除 = 危险
//（不可逆）/ 移动·重命名 = 弱化（元数据位置变更）；deleted 态行优先取弱化（「已删除」）。
export function fileChangeBadgeTone(kind: string, deleted: boolean): BadgeTone {
  if (deleted) {
    return BadgeTone.WEAK;
  }
  if (kind === OP_WRITE_NEW) {
    return BadgeTone.SUCCESS;
  }
  if (kind === OP_DELETE) {
    return BadgeTone.DANGER;
  }
  if (kind === OP_MOVE || kind === OP_RENAME) {
    return BadgeTone.WEAK;
  }
  return BadgeTone.EMPHASIS;
}

// 操作徽标短词（九短词单源 = 本函数；多操作文件取末次操作 lastOpKind）
export function fileChangeBadgeText(kind: string, deleted: boolean): string {
  if (deleted) {
    return '已删除';
  }
  if (kind === OP_WRITE_NEW) {
    return '新建';
  }
  if (kind === OP_WRITE_OVERWRITE) {
    return '覆盖';
  }
  if (kind === OP_EDIT) {
    return '编辑';
  }
  if (kind === OP_IMPORT) {
    return '导入';
  }
  if (kind === OP_XLSX) {
    return '表格';
  }
  if (kind === OP_RENAME) {
    return '重命名';
  }
  if (kind === OP_MOVE) {
    return '移动';
  }
  return '删除';
}

// 文件行键（坑44/80：键覆盖该行全部可变展示成分——六成分；changesExpanded 属卡级意愿经
// @Observed 属性驱动，**不进键**）
function fileChangeRowKey(entry: FileChangeEntry): string {
  return entry.displayName + '|' + entry.dir + '|' + entry.lastOpKind + '|' +
    String(entry.additions ?? '') + '|' + String(entry.deletions ?? '') + '|' +
    String(entry.deleted);
}

// 红绿统计对（+N / −M 两 Text 的并排行；additions/deletions 任一非空才渲染——纯元数据轮
//〔rename/move/delete〕无统计不显，与文件行「三族贡献者才显」同口径）。family = 正文字体族串
//（@Builder 全局函数按值传入——本件无组件 this 上下文，族名由调用处解析后喂进，禁本处拼串）
@Builder
function DiffStatPair(additions: number | null, deletions: number | null, family: string) {
  Row({ space: 4 }) {
    Text('+' + String(additions ?? 0))
      .fontSize(13)
      .fontFamily(family)
      .fontColor(DIFF_ADDITION_COLOR)
    Text('-' + String(deletions ?? 0))
      .fontSize(13)
      .fontFamily(family)
      .fontColor(DIFF_DELETION_COLOR)
  }
}

@Component
export struct ChatFileChangesCard {
  // 展示项（@ObjectLink 红线见头注释：普通成员 = 展开收起静默冻结，坑44 家族变体）
  @ObjectLink item: ChatDisplayItem;
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（消息列表内常驻卡即时面；档位键不进键，列表键纪律）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 正文字体两键 @StorageProp 自订阅（2026-11-04 字体补接笔）：整卡文字（卡头标题 / 文件行名 /
  // 目录副行 / 红绿统计 / 溢出计数 / 操作徽标）均属会话页消息显示面，随正文字体即时变化
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  // 文件行点击上行（ChatPageContent 构造处注入 → ChatPage 开详情半模态）
  onOpenDetail: (entry: FileChangeEntry) => void = (entry: FileChangeEntry): void => {
  };

  // 聚合产物取用（U2 装配保证非空才产卡，build 顶层判空后的取值口——断言集中在此一处）
  private changesData(): RoundFileChanges {
    return this.item.fileChanges as RoundFileChanges;
  }

  // 正文字体家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // 轮内文件总数（含溢出——卡头计数口径 = 轮总文件数）
  private totalCount(): number {
    const changes: RoundFileChanges = this.changesData();
    return changes.files.length + changes.overflowCount;
  }

  // 展开/收起切换（卡头整行可点；UIContext 版 animateTo——禁全局形态）
  private toggleExpanded(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.item.changesExpanded = !this.item.changesExpanded;
    });
  }

  build() {
    // 改动清单卡恒显示——偏好键已退役、不再有隐藏态；仅按装配产物是否为空决定是否建卡
    if (this.item.fileChanges !== null) {
      Column() {
        Column() {
          // ── 卡头行（收起态即全卡；整行可点切换展开）──
          Row() {
            SymbolGlyph(this.item.changesExpanded ?
              $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
            Text('本轮改动 · ' + String(this.totalCount()) + ' 个文件')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.resolveBodyFamily())
              .fontColor(cardTitleColor())
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 6 })
            if (this.changesData().totalAdditions > 0 ||
              this.changesData().totalDeletions > 0) {
              DiffStatPair(this.changesData().totalAdditions,
                this.changesData().totalDeletions, this.resolveBodyFamily())
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.toggleExpanded();
          })

          // ── 展开区：文件行列表（≤20 直排，不设滚动容器）──
          if (this.item.changesExpanded) {
            ForEach(this.changesData().files,
              (entry: FileChangeEntry): void => {
                Divider()
                  .strokeWidth(0.5)
                  .color(cardBorderColor(this.appColorMode))
                  .margin({ top: 6, bottom: 6 })
                  // 条件渲染根挂 IDENTITY：animateTo 内上下树未配 transition 会被官方加默认
                  // OPACITY 淡出（ts-transition-animation-component API 参考），收起时旧文件行
                  // 在动画窗内延留卡外；IDENTITY 令其立即离场
                  .transition(TransitionEffect.IDENTITY)
                Row() {
                  StatusBadge({
                    text: fileChangeBadgeText(entry.lastOpKind, entry.deleted),
                    tone: fileChangeBadgeTone(entry.lastOpKind, entry.deleted),
                    fontFamily: this.resolveBodyFamily()
                  })
                  Column() {
                    Text(entry.displayName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.resolveBodyFamily())
                      .fontColor(cardTitleColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // 目录副行只在 dir 已知时显示：空 dir = 模型省略 dir 参数（工具执行侧缺省
                    // 解析为助手默认文件夹，模型侧无从复原），不标「根目录」防误导（P1 修复笔）
                    if (entry.dir !== '') {
                      Text(entry.dir)
                        .fontSize(13)
                        .fontFamily(this.resolveBodyFamily())
                        .fontColor(cardDescColor())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 8, right: 8 })
                  if (entry.additions !== null || entry.deletions !== null) {
                    DiffStatPair(entry.additions, entry.deletions, this.resolveBodyFamily())
                  }
                  // 行尾视觉指示（非独立键——整行可点开详情）
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.font_secondary')])
                    .margin({ left: 4 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.onOpenDetail(entry);
                })
                .transition(TransitionEffect.IDENTITY)
              }, (entry: FileChangeEntry): string => fileChangeRowKey(entry))
            if (this.changesData().overflowCount > 0) {
              Text('另有 ' + String(this.changesData().overflowCount) + ' 个文件')
                .fontSize(13)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardDescColor())
                .width('100%')
                .margin({ top: 6 })
                .transition(TransitionEffect.IDENTITY)
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
        .borderRadius(CARD_RADIUS)
        // ★ 展开中间帧不出卡（1799 节同族）：200ms 布局类高度动画的内容按官方 FAQ
        //   faqs-arkui-1400 直接到终点态，卡高在途时终位文件行会画在卡外页灰底上；官方
        //   clip(value: boolean)（API 12+，本地 common.d.ts:21161）按本卡圆角轮廓裁掉超界
        //   绘制，只裁绘制不参与测量与布局，稳态卡高恒等于内容高零影响
        .clip(true)
      }
      .width('100%')
      .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
      .margin({ top: CARD_SPACING })
    }
  }
}
