// 价格模板列表页（入口 = 服务商管理页「更多」菜单「价格模板」项，param = providerId）：标题栏
// 「添加」键（官方数组）+ 行卡列表（主行模板名 + 副行 priceSummary 摘要）+ 空态行内提示行 + onPop 重拉。
// · 刷新链（规范 §3）：本页无自写动作（增删改全在三级页）→ 唯一刷新 = 子页 pop 带 result 触发 onPop
//   重拉（编辑页保存/删除均 pop({saved/deleted:true})，坑17）；挂载 aboutToAppear 自拉一次。列表重建走
//   「纪元键 ForEach 整组重建」——行键 = row.id 不变时编辑改名/改价的副行不刷新，外层纪元键保证重建。
// · 上限拦截（口径⑤调用侧一端）：达 PRICE_TEMPLATE_MAX 时「添加」键 push 前 toast 拦下（push 后才发现 =
//   白进一页，禁）；insertTemplate 内另有独立兜底 throw。
// · 入口卡不显示模板计数（口径⑩）——本页重拉自会刷新，高级页无刷新链需求。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PRICE_TEMPLATE_EDIT_PAGE, ROUTE_PRICE_TEMPLATE_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { priceSummary } from '../../common/store/CostStatsCalc';
import {
  deleteTemplate, PriceTemplateRow, PRICE_TEMPLATE_MAX, queryTemplatesByProvider
} from '../../common/store/PriceTemplateDb';

// 标题栏「添加」键（官方数组——单键场景官方数组足够，勿照 MemoryPage 三键覆盖层抄）
function templateAddMenuHds(onAdd: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.plus'),
        action: onAdd
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct PriceTemplatePage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 归属服务商（push 参数；模板按服务商隔离——口径①）
  private providerId: string = '';
  @State private templates: PriceTemplateRow[] = [];
  // 列表重建纪元（reload 成功自增——MemoryPage 同款：行 id 不变的编辑保存也要整组重建，
  // 否则改名/改价后的副行摘要被键 diff 冻住）
  @State private listEpoch: number = 0;
  // 行左滑删除互斥组（RowSwipeDelete 单源下发；reload / 滚动开始两路收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  // 左滑删除确认弹窗（行级删除入口与删除链照编辑页同形：ConfirmDialog → deleteTemplate 单源）
  private confirmCtrl: CustomDialogController | null = null;
  private pendingDelete: PriceTemplateRow | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // param 解析（MemoryEditPage 同款守卫：null/非串一律 ''——异常参数退栈不静默停空页）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_PRICE_TEMPLATE_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const pid: string = typeof last === 'string' ? last : '';
    if (pid === '') {
      this.getUIContext().getPromptAction().showToast({ message: '参数缺失' });
      this.pathStack.pop();
      return;
    }
    this.providerId = pid;
    this.reload();
  }

  private reload(): void {
    queryTemplatesByProvider(this.providerId)
      .then((rows: PriceTemplateRow[]): void => {
        if (this.departed) {
          return;
        }
        this.templates = rows;
        this.listEpoch = this.listEpoch + 1;
        // 清单整组重拉即收口行左滑展开态（删行后原行销毁，双保险）
        this.swipeGroup.collapse();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '模板读取失败：' + (e as Error).message });
      });
  }

  // 列表重建键（纪元——每次 reload 自增）
  private listKey(): string {
    return 'ptpl|' + this.listEpoch;
  }

  // 「添加」键：上限拦截在 push 前（口径⑤调用侧一端；insertTemplate 另有兜底）
  private openAdd(): void {
    if (this.templates.length >= PRICE_TEMPLATE_MAX) {
      this.getUIContext().getPromptAction().showToast(
        { message: '最多保存 ' + PRICE_TEMPLATE_MAX + ' 套模板，删除后可再添加' });
      return;
    }
    this.openEditPage('');
  }

  private openEditPage(templateId: string): void {
    // onPop 回调 = 子页 pop 带 result 时重拉（坑17——无参 pop 不触发）
    this.pathStack.pushPathByName(ROUTE_PRICE_TEMPLATE_EDIT_PAGE,
      { providerId: this.providerId, templateId: templateId }, (): void => {
        this.reload();
      });
  }

  // 左滑删除确认：按 id 查行弹确认（与编辑页删除键同链并存，deleteTemplate 单源）
  private askDeleteById(id: string): void {
    const row: PriceTemplateRow | undefined =
      this.templates.find((item: PriceTemplateRow): boolean => item.id === id);
    if (row === undefined) {
      return;
    }
    this.pendingDelete = row;
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除模板',
        message: '将删除模板「' + row.name + '」，不可恢复。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.deletePending();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 删除执行（row = 弹窗载荷）：deleteTemplate → toast + reload；失败 toast 可重试（P0-1）
  private deletePending(): void {
    const row: PriceTemplateRow | null = this.pendingDelete;
    this.pendingDelete = null;
    if (row === null) {
      return;
    }
    deleteTemplate(row.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除模板' });
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '删除失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 6 }) {
        if (this.templates.length === 0) {
          // 空态行内提示行（规范 §4.3：13fp cardDescColor + CARD_PANEL_WIDTH，无卡底）
          Text('暂无模板。在编辑模型页配好价格可存为模板，或点右上角的「＋」新增。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach([this.listKey()], (_key: string) => {
            Column({ space: CARD_SPACING }) {
              ForEach(this.templates, (row: PriceTemplateRow) => {
                // 行左滑删除层（四库共享件）：行卡 CARD_PANEL_WIDTH 居中 → cardInset 16；展开态不进键
                //（键不变，编辑返回 reload 走外层纪元键整组重建）
                RowSwipeDelete({
                  rowId: row.id,
                  group: this.swipeGroup,
                  content: (): void => {
                    this.TemplateRowCard(row)
                  },
                  onSwipeDelete: (rowId: string): void => {
                    this.askDeleteById(rowId);
                  }
                })
              }, (row: PriceTemplateRow): string => row.id)
            }
            .width('100%')
          }, (key: string): string => key)
        }
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
    // 滚动开始即收口行左滑展开态（会话列表/五库同口径）
    .onScrollStart((): void => {
      this.swipeGroup.collapse();
    })
  }

  // 单条模板行卡（主行模板名 + 副行摘要，点击进编辑页；无尾部菜单——删除在本页左滑与编辑页）；
  // 卡底 Column + 四周 padding 4 让蒙层距卡外圈 4vp，壳 padding 14→10 回添，几何零位移
  @Builder
  TemplateRowCard(row: PriceTemplateRow) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(row.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(priceSummary(row.priceConfig))
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
        this.openEditPage(row.id);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    PageShell({
      title: '价格模板',
      menuHds: templateAddMenuHds((): void => {
        this.openAdd();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
