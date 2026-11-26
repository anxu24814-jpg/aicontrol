// 价格模板条卡（挂编辑模型页「模型价格」卡正上方——口径⑨取「外」）：当前服务商的价格模板
//（「选择模板」键弹半模态行卡点选套用整组覆盖）+「存为模板」通宽键（配好价格一键存下）。纯展示
// + 回调上行——不查库、不落库、不弹窗（数据编排全在宿主 ModelEditPage：套用两行序写
// applyJson/applyTick、存模板弹命名窗）。
// · 行卡半模态共享件 TemplatePickSheet（壳 / 行卡 / HDS 回退单源三处共用）；行卡副行 =
//   priceSummary 价格摘要；空态「选择模板」置灰（无模板可挑）。
// · templates 走 @Link 数组引用下发（BalanceTemplateCard.headerPairs 同款先例）：本卡挂
//   PageShell.content 内，普通成员/@Prop 传参会首帧冻结（坑16 家族）——宿主存模板后整组替换
//   @State 数组即触发本卡刷新，无需纪元键重建；行卡数据 build 期算（@Link 替换即重算）。
// · 上限（口径⑤体验端）：达 PRICE_TEMPLATE_MAX 键置灰 + 说明小字；置灰态之外宿主保存链再拦
//   一道，insertTemplate 内另有 throw 兜底——三层防线。
// · 卡宽 = CARD_PANEL_WIDTH（宿主 ModelEditPage 滚动列只带顶/底 padding，水平收窄责任在卡体；
//   原写 width('100%') = 比卡宽基准左右各宽出 16vp，违《列表卡片与组卡》§4.3 卡体链判据）。
//   钉子两条在 scripts/assert-price-template.mjs（原 63 组随拆域整块迁出）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { PriceTemplateRow, PRICE_TEMPLATE_MAX } from '../../common/store/PriceTemplateDb';
import { priceSummary } from '../../common/store/CostStatsCalc';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

@Component
export struct PriceTemplateBarCard {
  // 当前服务商模板清单（@Link 数组——宿主 @State 绑定 $ 语法，整组替换即刷新，见头注释）
  @Link templates: PriceTemplateRow[];
  // 套用回调（宿主链 A：先写 applyJson 再自增 applyTick，两行序不可颠倒）+ 存为模板回调
  //（宿主链 B：守卫 + 命名弹窗 + 落库 + 重拉）
  onApply: (name: string, priceConfig: string) => void = () => {
  };
  onSaveAsTemplate: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感双态（「存为模板」键 = 内容区行内文字键，走 fallbackButton* 四件套）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 模板选择半模态显示态（点「选择模板」键拉起；xmark/手势/点选回写 false）
  @State @Watch('onSheetVisibleChanged') private pickShow: boolean = false;
  // 关闭-再开协调（机制与官方依据单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）：关闭后
  // 离场动效在途时再点「选择模板」，直接写下的可见性 true 会被吞或被框架收尾回写压回——在途期
  // 只记开意图，等离场动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;

  // 半模态行卡数据（build 期算——@Link templates 整组替换即触发重算；行卡 = 模板名 /
  // 价格摘要副行 / 尾标空串〔填入语义无协议或币种可标〕）
  private pickRows(): TemplatePickRow[] {
    const rows: TemplatePickRow[] = this.templates.map(
      (t: PriceTemplateRow): TemplatePickRow => {
        const row: TemplatePickRow = {
          title: t.name,
          subtitle: priceSummary(t.priceConfig),
          suffix: ''
        };
        return row;
      });
    return rows;
  }

  // 半模态点选：整组套用（宿主链 A 两行序在 ModelEditPage 内钉死）后关面板——先回填后关（钉 B4）
  private onPickTemplate(index: number): void {
    if (index < 0 || index >= this.templates.length) {
      return;
    }
    const t: PriceTemplateRow = this.templates[index];
    this.onApply(t.name, t.priceConfig);
    this.requestClose();
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

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.pickShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；
  // 用户关闭必经 requestClose（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.pickShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 点选三路同调）：先清开意图 + 置离场动效在途位，再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.pickShow = false;
  }

  build() {
    Column({ space: 10 }) {
      Text('价格模板')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('点「选择模板」挑一套填入下方价格。配好价格也可存为模板，供同服务商其他模型复用。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      if (this.templates.length === 0) {
        Text('暂无模板。可在下方配好价格后存为模板。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      // 「选择模板」= 内容区淡彩次级键（fallbackButton*Tinted 族；空态置灰——无模板可挑；模板族三处统一淡彩档）
      Button('选择模板')
        .fontSize(14)
        .fontColor(fallbackButtonFontTinted(this.contentFallback))
        .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
        .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback,
          this.immersiveLevel))
        .width('100%')
        .enabled(this.templates.length > 0)
        .onClick((): void => {
          this.requestOpen();
        })
      // 「存为模板」= 本卡主操作键（fallbackButton* 四件套 primary=true——官方强调蓝 +
      // 恒白字）；达上限置灰 + 说明小字，三层防线不变
      Button('存为模板')
        .fontSize(14)
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback,
          this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback,
          this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback,
          this.immersiveLevel))
        .width('100%')
        .enabled(this.templates.length < PRICE_TEMPLATE_MAX)
        .onClick((): void => {
          this.onSaveAsTemplate();
        })
      if (this.templates.length >= PRICE_TEMPLATE_MAX) {
        Text('最多保存 ' + PRICE_TEMPLATE_MAX + ' 套模板，删除后可再添加')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    // 模板选择半模态（挂条卡根——卡自身持有 pickShow；档位 [MEDIUM, LARGE] 列表类 =
    // sheetPanelOptions 默认双停靠位。关闭链 = 可见性 `$$` 双向 + onWillDismiss 内 action.dismiss()
    // 放行 + requestClose 单入口 + 第四参 onDisappear 补开（关闭-再开协调，见字段注释））
    .bindSheet($$this.pickShow, this.PickSheet(),
      sheetPanelOptions((action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }

  // 模板选择半模态内容（共享件 TemplatePickSheet 三处消费之一；行卡副行 = priceSummary）
  @Builder
  PickSheet() {
    TemplatePickSheet({
      mainTitle: '价格模板',
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
