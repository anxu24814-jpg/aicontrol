// 价格模板条卡（2026-09-11 价格模板，任务书-价格模板-20260911 执行；挂编辑模型页
// 「模型价格」卡正上方——口径⑨取「外」）：当前服务商的价格模板（「选择模板」键弹
// 半模态行卡点选套用整组覆盖）+「存为模板」通宽键（配好价格一键存下）。纯展示 +
// 回调上行——不查库、不落库、不弹窗（数据编排全在宿主 ModelEditPage：套用两行序写
// applyJson/applyTick、存模板弹命名窗）。
// · 2026-09-11（三处模板统一半模态，方案 v3）：原卡内横滑 chips 退役，改「选择模板」
//   键 + 半模态行卡（共享件 TemplatePickSheet——壳 / 行卡 / HDS 回退单源三处共用）；
//   行卡副行 = priceSummary 价格摘要；空态「选择模板」置灰（无模板可挑）；
// · templates 走 @Link 数组引用下发（BalanceTemplateCard.headerPairs 同款先例）：本卡挂
//   PageShell.content 内，普通成员/@Prop 传参会首帧冻结（坑16 家族）——宿主存模板后整组
//   替换 @State 数组即触发本卡刷新，无需纪元键重建；半模态行卡数据 build 期算（@Link
//   替换即重算）；
// · 上限（口径⑤体验端）：达 PRICE_TEMPLATE_MAX 键置灰 + 说明小字；置灰态之外宿主保存链
//   再拦一道（防将来键形制改动穿透），insertTemplate 内另有 throw 兜底——三层防线。
// · 卡宽 = CARD_PANEL_WIDTH（2026-09-11 决明「价格模板卡怎么又是全宽？对齐规范」修复）：
//   宿主 ModelEditPage 的滚动列容器只带顶/底 padding，水平收窄责任在卡体（同页基础卡/
//   类型卡与 ModelCapsCard/ModelPriceCard 四卡同值）；原写 width('100%') = 比卡宽基准左右
//   各宽出 16vp 的全宽卡，违《列表卡片与组卡》§4.3 卡体链判据。钉子两条在价格模板域
//   断言件 `scripts/assert-price-template.mjs`（原 63 组，同日随拆域整块迁出）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { PriceTemplateRow, PRICE_TEMPLATE_MAX } from '../../common/store/PriceTemplateDb';
import { priceSummary } from '../../common/store/CostStatsCalc';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

@Component
export struct PriceTemplateBarCard {
  // 当前服务商模板清单（@Link 数组——宿主 @State 绑定 $ 语法，整组替换即刷新，见头注释）
  @Link templates: PriceTemplateRow[];
  // 套用回调（宿主链 A：先写 applyJson 再自增 applyTick 两行序，顺序不可颠倒）+ 存为模板
  // 回调（宿主链 B：守卫 + 命名弹窗 + 落库 + 重拉）
  onApply: (name: string, priceConfig: string) => void = () => {
  };
  onSaveAsTemplate: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感双态（「存为模板」键 = 内容区行内文字键，走 fallbackButton* 四件套）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 模板选择半模态显示态（点「选择模板」键拉起；xmark/手势/点选回写 false）
  @State private pickShow: boolean = false;

  // 半模态行卡数据（build 期算——@Link templates 整组替换即触发本卡重算；行卡 = 模板名 /
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

  // 半模态点选：整组套用（宿主链 A 两行序——先写 applyJson 再自增 applyTick，顺序在
  // ModelEditPage.applyPriceTemplate 内钉死，本卡不动）后关面板——先回填后关，防吞
  // toast / 回填丢失（钉 B4）
  private onPickTemplate(index: number): void {
    if (index < 0 || index >= this.templates.length) {
      return;
    }
    const t: PriceTemplateRow = this.templates[index];
    this.onApply(t.name, t.priceConfig);
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
      // 「选择模板」= 内容区行内文字键（fallbackButton* 四件套，primary=false；空态置灰
      // ——无模板可挑；2026-09-11 改键 + 半模态行卡，原卡内横滑 chips 退役〔三处模板
      // 统一半模态，方案 v3〕）
      Button('选择模板')
        .fontSize(14)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBg(this.contentFallback,
          this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback,
          this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback,
          this.immersiveLevel))
        .width('100%')
        .enabled(this.templates.length > 0)
        .onClick((): void => {
          this.pickShow = true;
        })
      // 「存为模板」= 本卡主操作键（fallbackButton* 四件套 primary=true——官方强调蓝 +
      // 恒白字；2026-09-11 决明「价格模板卡，存为模板改蓝底」）；达上限置灰 + 说明小字，
      // 三层防线不变
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
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    // 模板选择半模态（挂条卡根——卡自身持有 pickShow，与协议处面板根同款机制；档位
    // [MEDIUM, LARGE] 列表类 = sheetPanelOptions 默认双停靠位；onWillDismiss = 手势关闭
    // 动画前置回写 false——KimiSheetCommon 定稿防「关了再开不弹」竞态）
    .bindSheet(this.pickShow, this.PickSheet(),
      sheetPanelOptions((): void => {
        this.pickShow = false;
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }

  // 模板选择半模态内容（共享件 TemplatePickSheet——协议 / 价格 / 余额三处消费之一；
  // 行卡副行 = priceSummary 价格摘要，长文本截断观感留真机项）
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
        this.pickShow = false;
      }
    })
  }
}
