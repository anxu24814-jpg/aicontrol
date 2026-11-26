// 余额套用模板卡（自 ProviderBalancePanel 拆出）：形态 = 自持卡壳（CARD_PANEL_WIDTH + padding16 +
// cardBg + CARD_RADIUS，同价格条卡）内「标题 + 描述 +『选择模板』通宽键（内容区 fallbackButton*
// 四件套）」，点键弹共享件半模态行卡，点选即整组回填并关面板。模板数据单源 = BalanceTemplates.ets。
// 点击整组权威回填五值 + 预置请求头（模板即权威预设，防不一致态）；★ 不动启用开关与专用余额
// Key——用户已选状态不覆盖。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HeaderPair } from '../../common/providers/AiTypes';
import { BALANCE_TEMPLATES, BalanceTemplate } from './BalanceTemplates';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_RADIUS } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

@Component
export struct BalanceTemplateCard {
  // 回填目标（父页 ProviderDetailPage @State，@Link 双向直写——BalanceField 同款契约；headerPairs = 余额请求头）
  @Link balBaseUrl: string;
  @Link balPath: string;
  @Link balResultPath: string;
  @Link balCurrency: string;
  @Link balCurrencyPath: string;
  @Link headerPairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感双态（「选择模板」键 = 内容区行内文字键，fallbackButton* 四件套——本卡挂二级页内容区，必配）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 模板选择半模态显示态（点「选择模板」键拉起；xmark/手势/点选回写 false）
  @State @Watch('onSheetVisibleChanged') private pickShow: boolean = false;
  // 关闭-再开协调（官方口径与补开两路单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）：离场动效在途时
  // 再开，可见性 true 会被吞或被框架收尾回写压回（真机报障「关面板后快点另一行，新面板立即被收起」）
  // ——在途期只记开意图，等离场动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;

  // 半模态行卡数据（BALANCE_TEMPLATES 单源映射——模板名 / 端点+路径副行 / 币种尾标；build 期算）
  private pickRows(): TemplatePickRow[] {
    const rows: TemplatePickRow[] = BALANCE_TEMPLATES.map(
      (t: BalanceTemplate): TemplatePickRow => {
        const row: TemplatePickRow = {
          title: t.name,
          subtitle: t.baseUrl + t.path,
          suffix: t.currency
        };
        return row;
      });
    return rows;
  }

  // 半模态点选：整组回填 + toast（apply 内）后关面板——先回填后关，防吞 toast / 回填丢失（钉 B4）；
  // ★ 不动启用开关与专用余额 Key 的语义不变
  private onPickTemplate(index: number): void {
    if (index < 0 || index >= BALANCE_TEMPLATES.length) {
      return;
    }
    this.apply(BALANCE_TEMPLATES[index]);
    this.requestClose();
  }

  // 整组权威回填 + toast 反馈（P0-1 可见）
  private apply(t: BalanceTemplate): void {
    this.balBaseUrl = t.baseUrl;
    this.balPath = t.path;
    this.balResultPath = t.resultPath;
    this.balCurrency = t.currency;
    this.balCurrencyPath = t.currencyPath;
    this.headerPairs = t.headers.map((p: HeaderPair): HeaderPair => {
      const next: HeaderPair = { k: p.k, v: p.v };
      return next;
    });
    this.getUIContext().getPromptAction().showToast({ message: '已填入 ' + t.name + ' 余额模板' });
  }

  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用；机制见字段注释）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.pickShow = true;
  }

  // 离场动效结束（第四参回调）：清在途位 + 按开意图补开——官方口径「等动效完全结束后才可再次拉起」
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.pickShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；用户关闭必经
  // requestClose（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.pickShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 点选三路同调）：先清开意图（撤销在途期点下的待开）+ 置离场动效在途位，
  // 再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.pickShow = false;
  }

  build() {
    Column({ space: 10 }) {
      Text('套用余额模板')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('端点与解析路径整组回填。GLM 暂无官方余额接口，未收录')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      // 「选择模板」= 淡彩次级键（模板族三处统一淡彩档；横滑 chips 已退役）
      Button('选择模板')
        .fontSize(14)
        .fontColor(fallbackButtonFontTinted(this.contentFallback))
        .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
        .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback,
          this.immersiveLevel))
        .width('100%')
        .onClick((): void => {
          this.requestOpen();
        })
    }
    // 卡体 = CARD_PANEL_WIDTH + padding16 + cardBg + CARD_RADIUS：宿主余额页容器无左右 padding，收窄责任在卡体
    //（卡壳逐项照 PriceTemplateBarCard；漏卡壳曾致无底色无内缩，规范 §4.3 判据）
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    // 模板选择半模态（挂卡根——卡自持 pickShow；档位 [MEDIUM, LARGE] = sheetPanelOptions 默认双停靠位。关闭链
    // = `$$` 双向 + onWillDismiss 内 action.dismiss() 放行 + requestClose 单入口 + 第四参 onDisappear 补开）
    .bindSheet($$this.pickShow, this.PickSheet(),
      sheetPanelOptions((action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }

  // 模板选择半模态内容（共享件 TemplatePickSheet 三处消费之一；挂卡根 = 页面内容区内，无嵌套问题）
  @Builder
  PickSheet() {
    TemplatePickSheet({
      mainTitle: '套用余额模板',
      subTitle: '点选即填入，可继续手动修改',
      rows: this.pickRows(),
      onPick: (index: number): void => {
        this.onPickTemplate(index);
      },
      onClose: (): void => {
        this.requestClose();
      }
    })
  }
}
