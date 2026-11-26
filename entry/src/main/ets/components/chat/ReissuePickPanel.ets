// 「会话设置」半模态 · 重发文件选择面板域件（★ 2026-10-31 附件重发笔〔任务书-附件重发与
// ZIP三件Office补丁-20261031 U-A〕新建——「会话设置」主面板第五张行卡「重发文件」的子态）。
// 语义：把本会话已发过的附件或工作区里的可发送文件**复制成新副本**加入下一轮发送的附件位
//（方案A「复制入列」——与选系统文件每次重选同权：doc 类走 enqueue 重解析、大附件重新上传
// 完整内容；源文件零改动，删除单件只删副本）。
// · 双段一次拉全（数据自持有，aboutToAppear 重拉——每次打开重建即重拉，无陈旧缓存面）：
//   本会话附件段 = ChatDb.queryAttachmentsByConversation（页面与工具域一律经 ChatDb 委托口，
//   WorkspaceDb/AttachmentDb 头注释红线②；行序 rowid DESC = 最近发在前，无需另排）；
//   工作区段 = ChatDb.queryWorkspaceFiles（自带 updatedAt DESC）+ workspaceReissueSendable 过滤
//   （kind ∈ image/text/doc 且名内带扩展名——dir 行与 other 行不列、无扩展名件也不列：enqueue
//   类型闸本会拦，面板先滤免得点了才报错；2026-10-31 两小修笔 #2 补扩展名一判）。工作区 =
//   全局一盘（按会话过滤会漏上传件/导入件）。
// · 常显实时过滤框（规范-搜索交互两族判据：产物是要继续操作的列表 → 实时族）：★ 2026-10-31
//   搜索吸顶笔起，框迁入**标题栏下方自定义区**（宿主 ChatPromptSheet.ReissueSearchBand 承载，
//   SearchTopBand 恒光感、带在标题栏上吸顶）——本件只留列表；关键词真源在宿主（标题栏在宿主
//   build 里），经 @Link 双向绑定同一份词、@Watch 复位两段行窗。输入即筛、空词全显（空词口径
//   与提交式族有意相反，勿互抄）；命中字段按本面板展示面——附件段匹配名、工作区段匹配名与目录。
// · 行窗渐进渲染（解滚动三角矛盾：Scroll+Column 不回收行卡配渐变模糊，行窗 50 控默认态与
//   检索态行数有界，段尾「显示更多」追加下一批——宪法「长列表避免全量创建」由有界 + 累积
//   展开用户知情化解）。
// · 行点击 = 复制入列（累加多选、面板保持开）：onPicked(name, srcRelPath, workspacePath,
//   sourceRow) 上行 → 宿主 → Host refs → ChatPage 私有转发 → AttachmentPickCtrl.addCopiedFromFile
//  （返回是否入列——额度满/复制失败的中文 toast 由控制器收口，面板零 toast）；srcRelPath =
//   filesDir 物理路径（复制源）、workspacePath = 工作区相对路径（工作区段 joinDirName(dir,name)
//   模型面坐标，附件段空串）、sourceRow = 附件段源行（降级导入入参）；成功后该行显「已加入」态，
//   额度内同一行可再点（每次新副本）。ForEach 键含已加入位（坑44/80 家族——不进键 = 该行
//   「已加入」静默冻结）。
// · 空态：无行会话（新会话）= 附件段空态句、工作区段照常出数；过滤无命中单句（与库空两句
//   分派，规范-搜索交互 §1 空词/提交两族口径）。失败行 hintText 照 SkillPickPanel 形（失败
//   呈报原因，禁静默空列表 P0-1）。
// ★ 滚动骨架 = Scroll + Column（★ 勿改回 List，2026-10-30 决明真机报障后统一——与
// 2026-10-25 模板半模态 TemplatePickSheet 同病同修）：List 对滚出视口的行做布局级虚拟化，
// clip(false) 只管绘制裁剪、管不住行回收，行卡滑到视口上缘即整张消失；Scroll 不回收子项，
// 配 clip(false) 行卡才滑进标题栏渐变模糊区渐隐 = 记忆页选会话（ConvPickerSheet）同款形态。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, CARD_RADIUS, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { AttachmentListRow } from '../../common/store/AttachmentDb';
import {
  WorkspaceFileRow, WORKSPACE_ROWS_READ_MAX, formatWorkspaceSize, formatWorkspaceTime,
  joinDirName, workspaceReissueSendable
} from '../../common/WorkspaceUtil';
import { queryAttachmentsByConversation, queryWorkspaceFiles } from '../../common/store/ChatDb';

// 附件段一次拉全的足额上限（单会话附件落库无上限闸、常态远小于此；分页入参只是形态、
// 本面板一次拉全不分页——上限只防极端库拖垮面板装载）
const ATTACH_ROWS_READ_MAX: number = 2000;
// 行窗（两段各默认渲染过滤后前 50 行，「显示更多」每批追加 50——渐进渲染步长）
const REISSUE_ROW_WINDOW: number = 50;

@Component
export struct ReissuePickPanel {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 目标会话 id（宿主 ChatPromptSheet @Prop 直接下传——附件段查询入参）
  @Prop conversationId: string = '';
  // 面板底部留白（尾部安全区让位行高）
  @Prop bottomPadInset: number = 0;
  // 行点击上行（宿主 → Host refs → ChatPage 私有转发 → AttachmentPickCtrl.addCopiedFromFile；
  // 返回是否已入列——true 才置「已加入」态，失败 toast 由控制器收口本面板零 toast）。
  // ★ 2026-10-31 重发降级笔：多带来源两参——workspacePath 非空 = 工作区段（源本就在工作区，
  // 降级指引直接用原相对路径、零导入）；sourceRow 非空 = 附件段（降级时导入工作区的入参）
  onPicked: (name: string, srcRelPath: string, workspacePath: string,
    sourceRow: AttachmentListRow | null) => Promise<boolean> = (): Promise<boolean> =>
    Promise.resolve(false);
  // 滚动控制器（宿主 sheet 壳 bindToScrollable 绑标题栏渐变模糊——传引用共用同一实例）
  scroller: Scroller = new Scroller();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 过滤关键词（实时族：空词 = 不过滤全显）：★ 2026-10-31 起为宿主 ChatPromptSheet 的 @State
  // 镜像（搜索框在标题栏下方带里，标题栏归宿主 build）——本件只读该词派生可见集；$$ 双向由
  // 带内 SearchTopBand 写回宿主，词一变即经 @Watch 复位两段行窗
  @Link @Watch('onKeywordChanged') keyword: string;
  @State private attachRows: AttachmentListRow[] = [];
  @State private workspaceRows: WorkspaceFileRow[] = [];
  // 两段读取失败提示（SkillPickPanel 同款形制——失败呈报原因，禁静默空列表）
  @State private attachError: string = '';
  @State private workspaceError: string = '';
  // 已加入行的键集（含段前缀防两段 id 撞键；进 ForEach 键驱动「已加入」态重建）
  @State private joinedKeys: string[] = [];
  // 两段行窗（过滤词变化即回收到首窗——检索态行数恒有界）
  @State private attachLimit: number = REISSUE_ROW_WINDOW;
  @State private workspaceLimit: number = REISSUE_ROW_WINDOW;

  aboutToAppear(): void {
    // 归零防御（面板重进复用宿主同一 scroller 实例；未绑定时静默无效，与 SkillPickPanel 同构）
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.reload();
  }

  // 过滤词变化（宿主 @State → @Link 回灌）：两段行窗回收到首窗——检索态行数恒有界，「显示
  // 更多」的累积只属于当前词（原框内 onChange 同语义，随框迁标题栏改为 @Watch 承接）
  private onKeywordChanged(): void {
    this.attachLimit = REISSUE_ROW_WINDOW;
    this.workspaceLimit = REISSUE_ROW_WINDOW;
  }

  private reload(): void {
    // 附件段：一次拉全（limit 传足额，rowid DESC = 最近发在前）
    queryAttachmentsByConversation(this.conversationId, ATTACH_ROWS_READ_MAX, 0)
      .then((rows: AttachmentListRow[]): void => {
        if (this.departed) {
          return;
        }
        this.attachRows = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.attachRows = [];
        this.attachError = '附件清单读取失败：' + (e as Error).message;
      });
    // 工作区段：一次拉全 + 可发送类型过滤（dir 行与 other 行不列）
    queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX)
      .then((rows: WorkspaceFileRow[]): void => {
        if (this.departed) {
          return;
        }
        this.workspaceRows = rows.filter((row: WorkspaceFileRow): boolean =>
          workspaceReissueSendable(row.kind, row.name));
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.workspaceRows = [];
        this.workspaceError = '工作区文件读取失败：' + (e as Error).message;
      });
  }

  // 过滤关键词归一（trim + 小写——空串 = 不过滤）
  private normalizedKeyword(): string {
    return this.keyword.trim().toLowerCase();
  }

  // 附件段可见集（命中字段 = 名；空词全显）
  private visibleAttachRows(): AttachmentListRow[] {
    const kw: string = this.normalizedKeyword();
    if (kw === '') {
      return this.attachRows;
    }
    return this.attachRows.filter((row: AttachmentListRow): boolean =>
      row.name.toLowerCase().includes(kw));
  }

  // 工作区段可见集（命中字段 = 名与目录——两列都是行内展示成分）
  private visibleWorkspaceRows(): WorkspaceFileRow[] {
    const kw: string = this.normalizedKeyword();
    if (kw === '') {
      return this.workspaceRows;
    }
    return this.workspaceRows.filter((row: WorkspaceFileRow): boolean =>
      row.name.toLowerCase().includes(kw) || row.dir.toLowerCase().includes(kw));
  }

  // 行点击（两段同法）：上行复制入列，成功才置「已加入」态；额度内同一行可再点（每次新副本，
  // 已加入态只标一次）。sourceRow 非空 = 附件段（其 localPath 是沙箱副本路径）；null = 工作
  // 区段。★ workspacePath 由 RowCard 显式传入（2026-10-31 自检修复笔）：工作区段 =
  // joinDirName(row.dir, row.name) 工作区相对路径（模型面坐标——workspace_read 等 workspace
  // 族工具全按 (dir, name) 显示名定位，行 localPath 是 filesDir 物理路径带 fileId 铸名，模型
  // 面不可解析）；附件段恒空串（降级时按导入回查重取）。srcRelPath 只承担复制源职责
  private async pick(rowKey: string, name: string, srcRelPath: string, workspacePath: string,
    sourceRow: AttachmentListRow | null): Promise<void> {
    const ok: boolean = await this.onPicked(name, srcRelPath, workspacePath, sourceRow);
    if (this.departed) {
      return;
    }
    if (ok && !this.joinedKeys.includes(rowKey)) {
      this.joinedKeys = this.joinedKeys.concat([rowKey]);
    }
  }

  // 类型图标（中性灰 SymbolGlyph——不引入身份色，规范-视觉色板零义务路径；三符号均仓内在产）
  private kindIcon(kind: string): Resource {
    if (kind === 'image') {
      return $r('sys.symbol.picture');
    }
    if (kind === 'doc') {
      return $r('sys.symbol.doc_text');
    }
    return $r('sys.symbol.doc_plaintext');
  }

  // 段空态两句（库空与过滤无命中分派——空词 = 库空原文案、有词无命中 = 单句，勿混用）
  private attachEmptyText(): string {
    return this.normalizedKeyword() === '' ? '本会话还没有发过附件' : '没有匹配的文件。';
  }

  private workspaceEmptyText(): string {
    return this.normalizedKeyword() === '' ? '工作区没有可发送类型的文件' : '没有匹配的文件。';
  }

  // 附件行副标题：大小 · 时间（formatWorkspaceTime 本地时区分档）
  private attachSubtitleOf(row: AttachmentListRow): string {
    return formatWorkspaceSize(row.size) + ' · ' + formatWorkspaceTime(row.createdAt);
  }

  // 工作区行副标题：目录 · 大小（根目录行只显大小）
  private workspaceSubtitleOf(row: WorkspaceFileRow): string {
    return row.dir === '' ? formatWorkspaceSize(row.size) :
      row.dir + ' · ' + formatWorkspaceSize(row.size);
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: CARD_SPACING }) {
        // 页顶说明句（13fp 次要色无卡底，SkillPickPanel 同款位次；搜索框已上提标题栏带，
        // 本句留守内容区首项说明筛选与「已加入」语义）
        Text('输入关键词筛选。点击文件加入下一轮发送。已加入的文件发送后自动取消。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)

        // ── 段一：本会话附件 ──
        Text('本会话附件')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width(CARD_PANEL_WIDTH)
        if (this.attachError !== '') {
          Text(this.attachError)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width(CARD_PANEL_WIDTH)
            .padding(16)
        } else if (this.visibleAttachRows().length === 0) {
          Text(this.attachEmptyText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach(this.visibleAttachRows().slice(0, this.attachLimit), (row: AttachmentListRow) => {
            this.RowCard('a|' + row.id, row.name, row.localPath,
              this.attachSubtitleOf(row), this.kindIcon(row.kind), row, '')
          }, (row: AttachmentListRow): string =>
            'a|' + row.id + (this.joinedKeys.includes('a|' + row.id) ? '|joined' : ''))
          this.MoreRow(this.visibleAttachRows().length, this.attachLimit, (): void => {
            this.attachLimit += REISSUE_ROW_WINDOW;
          })
        }

        // ── 段二：工作区文件 ──
        Text('工作区文件')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width(CARD_PANEL_WIDTH)
        if (this.workspaceError !== '') {
          Text(this.workspaceError)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width(CARD_PANEL_WIDTH)
            .padding(16)
        } else if (this.visibleWorkspaceRows().length === 0) {
          Text(this.workspaceEmptyText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach(this.visibleWorkspaceRows().slice(0, this.workspaceLimit), (row: WorkspaceFileRow) => {
            this.RowCard('w|' + row.id, row.name, row.localPath,
              this.workspaceSubtitleOf(row), this.kindIcon(row.kind), null,
              joinDirName(row.dir, row.name))
          }, (row: WorkspaceFileRow): string =>
            'w|' + row.id + (this.joinedKeys.includes('w|' + row.id) ? '|joined' : ''))
          this.MoreRow(this.visibleWorkspaceRows().length, this.workspaceLimit, (): void => {
            this.workspaceLimit += REISSUE_ROW_WINDOW;
          })
        }

        // 尾部透明占位（底部安全区让位——Blank 在 ListItem 下编译 10905201，用 Row）
        Row()
          .width('100%')
          .height(this.bottomPadInset)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      // 容器零左右边距，卡宽 CARD_PANEL_WIDTH 自理（规范-半模态 §3，SkillPickPanel 同形）；
      // 顶 20 = 首卡与标题栏蒙层留白
      .padding({ top: 20 })
    }
    .width('100%')
    .height('100%')
    // 顶对齐（Scroll 默认 Center，内容不满屏时会垂直居中——面板族同款显式）
    .align(Alignment.Top)
    // ★ 动态模糊生效前提（沉淀「列表类」节）：滚动内容穿透标题栏背后（clip(false) 缺省
    // 裁剪 = 模糊无内容可透——SkillPickPanel 同款）
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  // 行卡（两段共用；点击 = 复制入列，卡形照 SkillPickPanel 行卡 + Button 壳原生按压反馈）。
  // sourceRow 只随「本会话附件」段传入（工作区段 null）——降级导入的源行入参。workspacePath
  // 只随工作区段传入（附件段空串）——工作区相对路径（joinDirName(dir, name)），降级指引的
  // 模型面坐标；与 srcRelPath（filesDir 物理路径，复制源职责）分参不混用
  @Builder
  RowCard(rowKey: string, name: string, srcRelPath: string, subtitle: string, icon: Resource,
    sourceRow: AttachmentListRow | null, workspacePath: string) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          SymbolGlyph(icon)
            .fontSize(20)
            .fontColor([cardDescColor()])
          Column({ space: 2 }) {
            Text(name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(subtitle)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.joinedKeys.includes(rowKey)) {
            Text('已加入')
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding({ left: 16, right: 16, top: 13, bottom: 13 })
      .onClick((): void => {
        this.pick(rowKey, name, srcRelPath, workspacePath, sourceRow);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 段尾「显示更多」行（visible > limit 才挂；点击追加下一批——渐进渲染，非分页查询）
  @Builder
  MoreRow(visible: number, limit: number, onMore: () => void) {
    if (visible > limit) {
      Column() {
        Button() {
          Text('显示更多。已显示 ' + limit + ' 件。')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .type(ButtonType.Normal)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius(CARD_RADIUS)
        .padding({ top: 13, bottom: 13 })
        .onClick((): void => {
          onMore();
        })
      }
      .width(CARD_PANEL_WIDTH)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(CARD_RADIUS)
      .padding(4)
    }
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
