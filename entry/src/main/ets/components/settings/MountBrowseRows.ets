// 挂载浏览页列表渲染件（自 MountBrowsePage.ets 原样拆出——渲染域（List + Repeat 行卡 + 尾行提示）
// 独立成件，方法体原样搬迁）。职责缝：挂载浏览页的条目列表渲染（行卡几何 / 图标 / 副行 / 行内键 /
// 让位轨），不含数据装载与动作执行（在页壳）。
// ★ 行尾「更多」键：行菜单（文件夹 = 在文件管理中打开 + 删除；文件 = 复制到工作区 + 删除）。键形制 =
//   行内图标键（TEXTUAL 无底 ellipsis_circle 18fp font_secondary）；锚点 id 挂键自身（前缀单源在
//   MountRowMenu，菜单按 id 定位）；只上抛 onMore（菜单宿主与动作执行在页壳——V2 件禁挂 V1 装饰器）。
// ★ 复制已收入行菜单（决明拍板）：原文件行行内独立「复制到工作区」图标键整段退役，onCopy 随键退役；
//   行卡可变入参仍 = MountBrowseRow 四字段（全在 mountBrowseRowKey 键里，列表键纪律两问已过；菜单
//   不引入行上显示值变化，键零改动；在途态走壳侧标量 @Param，§4.6.1 第 3 条）。
// ── 列表渲染件（V2：Repeat.virtualScroll 懒加载须配状态管理 V2；先例 = SessionSearchResults。
//    V2 件内禁挂 V1 装饰器 ⇒ 深浅色等订阅值一律 @Param 下行，本件仅 @Param / @Event / @Builder）──
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MountBrowseRow, mountBrowseRowKey, mountKindOf } from '../../common/MountUtil';
import { formatWorkspaceSize, formatWorkspaceTime, workspaceIconTierOf } from '../../common/WorkspaceUtil';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { MOUNT_ROW_MENU_ID_PREFIX } from './MountRowMenu';

@ComponentV2
export struct MountBrowseList {
  // 当前层条目（已排序 + 已截断；V1 壳经 UIUtils.enableV2Compatibility 传入）
  @Param rows: MountBrowseRow[] = [];
  // 内容顶让位（壳侧 contentTop 算式现算后传值——收起态与 HDS/回退两路径归一都在壳侧；本件只消费，走官方 offset 轨）
  @Param contentTop: number = 0;
  @Param bottomPad: number = 0;
  // 复制在途与删除在途（标量逐行下发——行级态由壳侧持标量 @Param，§4.6.1 第 3 条；行尾「更多」键在任一
  // 操作在途时置灰——「同一时刻只跑一件」的轻量串行口径沿复制键先例）
  @Param copying: boolean = false;
  @Param deleting: boolean = false;
  // 尾行提示（截断 / 读取失败计数；'' = 不渲染）
  @Param tailNotice: string = '';
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 滚动器（壳侧持——进层回顶复位由壳侧在数据赋值后直调）。V2 件的普通成员禁止由父构造赋值
  //（编译实锤 10905324），故走 @Param 下行（本件只读不改引用）
  @Param scroller: Scroller = new Scroller();
  @Event onOpenFolder: (row: MountBrowseRow) => void = (row: MountBrowseRow): void => {
  };
  @Event onOpenFile: (row: MountBrowseRow) => void = (row: MountBrowseRow): void => {
  };
  @Event onMore: (row: MountBrowseRow) => void = (row: MountBrowseRow): void => {
  };

  // 行首图标（八档；档位判定单源 = workspaceIconTierOf，本处只做档位→符号字面量映射——与 WorkspaceFileRowCard
  // 同表同观感；$r 须编译期字面量、禁拼接）
  private iconOf(row: MountBrowseRow): Resource {
    if (row.isDir) {
      return $r('sys.symbol.folder');
    }
    switch (workspaceIconTierOf(row.name, mountKindOf(row.name))) {
      case 'pdf':
        return $r('sys.symbol.pdf_doc');
      case 'sheet':
        return $r('sys.symbol.square_grid_2x2');
      case 'archive':
        return $r('sys.symbol.doc_zipper');
      case 'audio':
        return $r('sys.symbol.music');
      case 'video':
        return $r('sys.symbol.video');
      case 'image':
        return $r('sys.symbol.picture');
      case 'text':
        return $r('sys.symbol.doc_plaintext');
      default:
        return $r('sys.symbol.doc_text');
    }
  }

  // 副行（文件夹只显示「文件夹」；文件 = 大小 · 修改时间——格式化直引工作区单源）
  private subLineOf(row: MountBrowseRow): string {
    if (row.isDir) {
      return '文件夹';
    }
    return formatWorkspaceSize(row.size) + ' · ' + formatWorkspaceTime(row.mtimeMs);
  }

  // 行卡（可变入参 = MountBrowseRow 四字段，全在 mountBrowseRowKey 键里）。外层 Button = 官方按压
  // 反馈，内层图标键自持 onClick。卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp（壳 padding 10）
  @Builder
  RowCard(ri: RepeatItem<MountBrowseRow>) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          SymbolGlyph(this.iconOf(ri.item))
            .fontSize(24)
            .fontColor([cardDescColor()])
          Column({ space: 3 }) {
            Text(ri.item.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.subLineOf(ri.item))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 行尾「更多」键——行内图标键形制（TEXTUAL 无底 + font_secondary）；锚点 id 挂键自身
          // （MountRowMenu 前缀 + 行键，openMenu 按 id 定位，勿锚整卡）；只上抛事件
          Button() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .id(MOUNT_ROW_MENU_ID_PREFIX + mountBrowseRowKey(ri.item))
          .enabled(!this.copying && !this.deleting)
          .onClick((): void => {
            this.onMore(ri.item);
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
        if (ri.item.isDir) {
          this.onOpenFolder(ri.item);
        } else {
          this.onOpenFile(ri.item);
        }
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    List({ space: CARD_SPACING, scroller: this.scroller }) {
      Repeat<MountBrowseRow>(this.rows)
        .each((ri: RepeatItem<MountBrowseRow>) => {
          ListItem() {
            Column({ space: CARD_SPACING }) {
              this.RowCard(ri)
              // 尾行提示（截断 / 读取失败计数——同属列表内容，随末行一起滚；两因互斥）
              if (ri.index === this.rows.length - 1 && this.tailNotice !== '') {
                Text(this.tailNotice)
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width(CARD_PANEL_WIDTH)
                  .textAlign(TextAlign.Start)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        .key((row: MountBrowseRow): string => mountBrowseRowKey(row))
        .virtualScroll()
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    // 让位走官方 offset 轨：原「条体在内容流里 + 列表在其下」形态 = 视口顶挤在页面中部，内容滚不过条体也到不了
    // 标题栏背后；改视口铺满整页 + 内容起始位下移。坑9：顶/底留白禁改回容器 padding——那是视口缩进，蒙层光感会空转
    .contentStartOffset(Math.max(this.contentTop, 0))
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }
}
