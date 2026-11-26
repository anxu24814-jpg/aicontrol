// 价格模板·服务商选择页（入口 = 服务商管理页标题栏「更多」菜单「价格模板」项 push 本页）：模板按
// 服务商隔离（口径①），本页 = 选服务商的过渡层——行卡列表（主行服务商名 + chevron），点行 push
// 价格模板列表页携 providerId（param 契约与旧入口逐字一致，下游 PriceTemplatePage /
// PriceTemplateEditPage 零改动）。标题恒「价格模板」（功能名下探两页同名，行卡内容区分上下文）。
// · 取数（刷新链规范 §3）：唯一取数 = aboutToAppear 自拉一次 queryProviders()（服务商全集，含停用
//   与内置——模板随服务商存续，管理面一律可见）——本页无自写动作、无派生数据可达，返回无参 pop
//   不挂 onPop（坑17 口径）。
// · 列表重建走「纪元键 ForEach 整组重建」（PriceTemplatePage 同款姿势）；无标题栏菜单键（本页无写
//   动作）；空态行内提示（规范 §4.3 同款：13fp cardDescColor + CARD_PANEL_WIDTH，无卡底）。
// · 非设置项，不进 SettingSearch 注册表——两处同步 = RouteNames + PageMap 分支。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PRICE_TEMPLATE_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { ProviderRow, queryProviders } from '../../common/store/ProviderDb';

@Component
export struct PriceTemplateProvidersPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private providers: ProviderRow[] = [];
  // 列表重建纪元（reload 成功自增——PriceTemplatePage 同款）
  @State private listEpoch: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    queryProviders()
      .then((rows: ProviderRow[]): void => {
        if (this.departed) {
          return;
        }
        this.providers = rows;
        this.listEpoch = this.listEpoch + 1;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '服务商读取失败：' + (e as Error).message });
      });
  }

  // 列表重建键（纪元——每次 reload 自增）
  private listKey(): string {
    return 'ptplp|' + this.listEpoch;
  }

  // 点行进模板列表页（param = providerId 裸串——与旧入口契约逐字一致；列表页自身处理三级编辑页回传重拉）
  private openTemplates(providerId: string): void {
    this.pathStack.pushPathByName(ROUTE_PRICE_TEMPLATE_PAGE, providerId);
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 6 }) {
        if (this.providers.length === 0) {
          // 空态行内提示行（规范 §4.3：13fp cardDescColor + CARD_PANEL_WIDTH，无卡底）
          Text('暂无服务商，先到服务商管理页新建。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach([this.listKey()], (_key: string) => {
            Column({ space: CARD_SPACING }) {
              ForEach(this.providers, (row: ProviderRow) => {
                this.ProviderRowCard(row)
              }, (row: ProviderRow): string => row.id)
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
  }

  // 单条服务商行卡（单条目入口卡：主行服务商名 + 尾部 chevron）。卡底 Column + 四周 padding 4，
  // 蒙层距卡外圈 4vp（壳 padding 10）
  @Builder
  ProviderRowCard(row: ProviderRow) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Text(row.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
        this.openTemplates(row.id);
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
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
