// 价格模板编辑页（2026-09-11 价格模板，任务书-价格模板-20260911 执行；列表页点行卡/
// 「添加」键 push，param = PriceTemplateEditParam）：名称卡 + 复用 ModelPriceCard 同一张
// 价格卡（★ 不自绘价格表单——模板编辑链路与编辑模型页对齐是本功能立项原话）+ 标题栏
// 「保存」键（官方数组双路）+ 编辑态底部「删除模板」红字键（ConfirmDialog 确认）。
// 标题恒「编辑模板」（新建态不显示「添加模板」——PromptEditPage/MemoryEditPage 同规）。
// · ModelPriceCard 套用通道在本页是纯占位（@State applyJson 恒 '' / applyTick 恒 0——
//   本页无套用入口，卡内 applyJson !== '' 守卫保证占位永不触发回填）：按组件契约必须
//   绑定，两参给恒空值即可；
// · 保存链（顺序即拦截序）：名称 trim 非空 → 同服务商不重名（编辑改名排除自身 id——
//   ModelEditPage.save 查重口径）→ 价格草稿 complete（不满足复用价格卡 hint 文案拦截）
//   → insert/update → toast + pop({saved:true})（坑17：必带 result 才触发列表页 onPop）；
// · 编辑回填：行 price_config 原文 → @State priceJson → ModelPriceCard @Watch 草稿回填
//   （与编辑模型页同一条 refill 链——priceJson 走 @Link，PageShell.content 内 @Prop 禁令）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PRICE_TEMPLATE_EDIT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ModelPriceCard, PriceDraftState } from './ModelPriceCard';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import {
  deleteTemplate, insertTemplate, PriceTemplateRow,
  PRICE_TEMPLATE_NAME_MAX, queryTemplatesByProvider, updateTemplate
} from '../../common/store/PriceTemplateDb';

// push 参数（列表页 openEditPage 构造；templateId '' = 新建）
export interface PriceTemplateEditParam {
  providerId: string;
  templateId: string;
}

function templateSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

function templateSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

@Component
export struct PriceTemplateEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 归属服务商 + 编辑对象行 id（'' = 新建）
  private providerId: string = '';
  private templateId: string = '';
  @State private name: string = '';
  // 行 price_config 原文（编辑态异步回填 → ModelPriceCard @Watch 草稿回填；新建态恒 ''）
  @State private priceJson: string = '';
  // 价格卡草稿最新值（onDraftChange 上行持有；保存链消费——complete=false 拦截）
  private priceDraft: PriceDraftState = { json: '', complete: true, hint: '' };
  // 套用通道占位（本页无套用入口：恒空值 + 卡内守卫 = 永不触发回填，见头注释）
  @State private applyJson: string = '';
  @State private applyTick: number = 0;
  // 删除确认弹窗控制器（★ 组件成员位按需构造——坑7；message 依赖当前模板名故不预建）
  private confirmCtrl: CustomDialogController | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // param 解析（ModelEditPage 同款守卫；providerId 缺失 = 异常栈——入口唯一且必传）
    const params: Array<PriceTemplateEditParam> =
      this.pathStack.getParamByName(ROUTE_PRICE_TEMPLATE_EDIT_PAGE) as Array<PriceTemplateEditParam>;
    const param: PriceTemplateEditParam | undefined =
      params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param.providerId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '参数缺失' });
      this.pathStack.pop();
      return;
    }
    this.providerId = param.providerId;
    this.templateId = param.templateId;
    if (param.templateId === '') {
      return; // 新建：空表单
    }
    queryTemplatesByProvider(this.providerId)
      .then((rows: PriceTemplateRow[]): void => {
        const row: PriceTemplateRow | undefined =
          rows.find((item: PriceTemplateRow): boolean => item.id === param.templateId);
        if (row === undefined) {
          this.getUIContext().getPromptAction().showToast({ message: '模板不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.name = row.name;
        this.priceJson = row.priceConfig;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast(
          { message: '模板读取失败：' + (e as Error).message });
      });
  }

  // 保存：名称非空 → 同服务商查重（编辑排除自身）→ 价格草稿完整 → 落库 → pop 带 result
  private save(): void {
    const name: string = this.name.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '模板名称不能为空' });
      return;
    }
    if (!this.priceDraft.complete) {
      // 拦截原因由价格卡草稿上行时给出，hint 缺失回退通用文案（ModelEditPage.save 同款）
      this.getUIContext().getPromptAction().showToast(
        { message: this.priceDraft.hint !== '' ? this.priceDraft.hint :
          '模型价格须为非负数字，输入价格与输出价格须同时填写' });
      return;
    }
    queryTemplatesByProvider(this.providerId)
      .then((rows: PriceTemplateRow[]): Promise<void> => {
        const dup: boolean = rows.some((row: PriceTemplateRow): boolean =>
          row.name === name && row.id !== this.templateId);
        if (dup) {
          this.getUIContext().getPromptAction().showToast({ message: '已有同名模板：' + name });
          return Promise.resolve();
        }
        if (this.templateId === '') {
          return insertTemplate(this.providerId, name, this.priceDraft.json)
            .then((): void => {
              this.done();
            });
        }
        return updateTemplate(this.templateId, name, this.priceDraft.json)
          .then((): void => {
            this.done();
          });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast(
          { message: '保存失败：' + (e as Error).message });
      });
  }

  // 保存成功：toast + pop 带 result（坑17——列表页 onPop 重拉）
  private done(): void {
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    this.pathStack.pop({ saved: true });
  }

  // 删除（编辑态底部键）：确认弹窗 → 删行 → toast + pop 带 result（列表页重拉）
  private openDeleteConfirm(): void {
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除模板',
        message: '将删除模板「' + this.name.trim() + '」，不可恢复。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.deleteRow();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private deleteRow(): void {
    deleteTemplate(this.templateId)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除模板' });
        this.pathStack.pop({ deleted: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast(
          { message: '删除失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 10 }) {
        // ── 名称卡 ──
        Column({ space: 6 }) {
          Text('模板名称')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          TextInput({ placeholder: '例如 DeepSeek 官方价', text: this.name })
            .width('100%')
            .maxLength(PRICE_TEMPLATE_NAME_MAX)
            .onChange((value: string): void => {
              this.name = value;
            })
          Text('同一服务商内不可重名。套用时整组覆盖模型价格。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // ── 价格卡（复用 ModelPriceCard——与编辑模型页同一张卡，不自绘表单）。★ 2026-09-17
        // 决明指令「模型能力页价格卡加收起展开」只落模型编辑页：本页**不传 collapsible**
        //（恒展开、标题行无箭头——本页主用途即编辑价格，折叠无意义），勿顺手补齐 ──
        ModelPriceCard({
          priceJson: $priceJson,
          applyJson: $applyJson,
          applyTick: $applyTick,
          onDraftChange: (draft: PriceDraftState): void => {
            this.priceDraft = draft;
          }
        })

        // ── 删除键（编辑态）──
        if (this.templateId !== '') {
          Button('删除模板')
            .fontSize(15)
            .fontColor($r('app.color.dialog_confirm_red'))
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(16)
            .width(CARD_PANEL_WIDTH)
            .padding({ top: 13, bottom: 13 })
            .onClick((): void => {
              this.openDeleteConfirm();
            })
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
  }

  build() {
    PageShell({
      title: '编辑模板',
      menuHds: templateSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: templateSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
