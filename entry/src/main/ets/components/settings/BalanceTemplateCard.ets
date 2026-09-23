// 余额套用模板卡（2026-08-31 多预设化，自 ProviderBalancePanel 拆出；2026-09-11 方案 v3
// 随迁 BalanceConfigPage 二级页 + 改键 + 半模态行卡——原横向滚动选项 chips 退役）：形态 =
// 自持卡壳（CARD_PANEL_WIDTH + padding16 + cardBg + 圆角16，同价格条卡）内「标题 + 描述 +
// 「选择模板」通宽键（内容区双态 fallbackButton* 四件套）」，点键弹共享件半模态行卡，点选
// 即整组回填并关面板。模板数据单源 = BalanceTemplates.ets。
// 点击整组权威回填五值 + 预置请求头（模板即权威预设，防不一致态）；★ 不动启用开关与
// 专用余额 Key——用户已选状态不覆盖（原单模板 applyTemplate 拍板语义保留）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HeaderPair } from '../../common/providers/AiTypes';
import { BALANCE_TEMPLATES, BalanceTemplate } from './BalanceTemplates';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

@Component
export struct BalanceTemplateCard {
  // 回填目标（父页 ProviderDetailPage @State，@Link 双向直写——BalanceField 同款契约；
  // headerPairs = 余额请求头 kv 行，预置头整组替换）
  @Link balBaseUrl: string;
  @Link balPath: string;
  @Link balResultPath: string;
  @Link balCurrency: string;
  @Link balCurrencyPath: string;
  @Link headerPairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感双态（「选择模板」键 = 内容区行内文字键，fallbackButton* 四件套——2026-09-11
  // 起本卡挂 BalanceConfigPage 二级页内容区，光感双态必配）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 模板选择半模态显示态（点「选择模板」键拉起；xmark/手势/点选回写 false）
  @State private pickShow: boolean = false;

  // 半模态行卡数据（BALANCE_TEMPLATES 单源映射——行卡 = 模板名 / 端点+路径副行 / 币种
  // 尾标；静态数据 build 期算）
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

  // 半模态点选：整组回填 + toast（apply 内）后关面板——先回填后关，防吞 toast / 回填
  // 丢失（钉 B4）；★ 不动启用开关与专用余额 Key 的语义不变（apply 注释同款）
  private onPickTemplate(index: number): void {
    if (index < 0 || index >= BALANCE_TEMPLATES.length) {
      return;
    }
    this.apply(BALANCE_TEMPLATES[index]);
    this.pickShow = false;
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
      // 「选择模板」= 本卡主操作键（fallbackButton* 四件套 primary=true——官方强调蓝 +
      // 恒白字；2026-09-11 决明「三处模板键均改蓝底」；原横滑 chips 已于同日退役〔三处
      // 模板统一半模态，方案 v3〕）
      Button('选择模板')
        .fontSize(14)
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback,
          this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback,
          this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback,
          this.immersiveLevel))
        .width('100%')
        .onClick((): void => {
          this.pickShow = true;
        })
    }
    // 卡体 = CARD_PANEL_WIDTH + padding16 + cardBg + 圆角16（2026-09-11 反馈修正笔②）：宿主
    // 余额页容器无左右 padding，收窄责任在卡体；★ 卡壳逐项照价格条卡（PriceTemplateBarCard）——
    // 迁页时只搬了宽度、漏了卡壳，本卡在页面上成了无底色无内缩的裸块，「选择模板」键相对
    // 其余卡显成全宽（决明真机报障「选择模板与查询键又是全宽」；规范 §4.3 判据同源）
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    // 模板选择半模态（挂卡根——余额页内容区内卡自持 pickShow，与价格条卡同款机制；档位
    // [MEDIUM, LARGE] 列表类 = sheetPanelOptions 默认双停靠位；onWillDismiss = 手势关闭
    // 动画前置回写 false——KimiSheetCommon 定稿防「关了再开不弹」竞态）
    .bindSheet(this.pickShow, this.PickSheet(),
      sheetPanelOptions((): void => {
        this.pickShow = false;
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }

  // 模板选择半模态内容（共享件 TemplatePickSheet——协议 / 价格 / 余额三处消费之一；
  // 半模态挂卡根 = 页面内容区内，无嵌套问题〔判项③ 的正解形态〕）
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
        this.pickShow = false;
      }
    })
  }
}
