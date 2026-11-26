// 价格模板编辑页：列表页点行卡 /「添加」键 push，param = PriceTemplateEditParam。名称卡 +
// 复用 ModelPriceCard（★ 不自绘价格表单——与编辑模型页对齐是本功能立项原话）+ 标题栏「保存」键
//（官方数组）+ 编辑态删除卡（ConfirmDialog 确认）。标题恒「编辑模板」（新建态不显示「添加模板」）。
// · ModelPriceCard 套用通道在本页是纯占位（applyJson 恒 '' / applyTick 恒 0——卡内
//   applyJson !== '' 守卫保证永不触发回填）：按组件契约必须绑定，两参给恒空值即可；
// · 保存链（顺序即拦截序）：名称 trim 非空 → 同服务商不重名（编辑改名排除自身 id）→ 价格
//   草稿 complete（不满足复用价格卡 hint 拦截）→ insert/update → toast + pop({saved:true})
//  （坑17：必带 result 才触发列表页 onPop）；
// · 编辑回填：行 price_config 原文 → @State priceJson → ModelPriceCard @Watch 草稿回填（与
//   编辑模型页同一条 refill 链——priceJson 走 @Link，PageShell.content 内 @Prop 禁令）。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PRICE_TEMPLATE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY
} from '../../common/AppPreferences';
import {
  CARD_NOTE_FONTSIZE, CARD_PANEL_WIDTH, CARD_SPACING, TINT_DANGER, cardBg, cardBorderColor,
  cardDescColor, cardTitleColor, tintCardBg, CARD_RADIUS
} from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ModelPriceCard, PriceDraftState } from './ModelPriceCard';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import {
  deleteTemplate, insertTemplate, PriceTemplateRow,
  PRICE_TEMPLATE_NAME_MAX, queryTemplatesByProvider, updateTemplate
} from '../../common/store/PriceTemplateDb';

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

@Component
export struct PriceTemplateEditPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
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
  @State private applyJson: string = '';
  @State private applyTick: number = 0;
  // 删除确认弹窗控制器（★ 组件成员位按需构造——坑7；message 依赖当前模板名故不预建）
  private confirmCtrl: CustomDialogController | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（淡染删除卡随档叠 alpha——与全站卡底同源，见 Theme.tintCardBg 注释）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  aboutToAppear(): void {
    // param 解析（providerId 缺失 = 异常栈——入口唯一且必传）
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
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
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
          if (this.departed) {
            return Promise.resolve();
          }
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
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '保存失败：' + (e as Error).message });
      });
  }

  // 保存成功：toast + pop 带 result（坑17——列表页 onPop 重拉）
  private done(): void {
    if (this.departed) {
      return; // 自检轮 1712 修正：查重/写库照常，只放弃已亡组件上的 UI
    }
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
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除模板' });
        this.pathStack.pop({ deleted: true });
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
      Column({ space: CARD_SPACING }) {
    // 名称卡：说明小字走卡脚（规范 §1.5——卡脚讲整张卡的结果，字段说明才贴框下；本卡无
    // 操作按钮行，满足硬边界）
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
          // 卡脚（hairline 上边线 + 上间距 10 + 13fp 灰字；下不额外留白）
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .margin({ top: 10 })
          Text('同一服务商内不可重名。套用时整组覆盖模型价格。')
            .fontSize(CARD_NOTE_FONTSIZE)
            .fontColor(cardDescColor())
            .width('100%')
            .margin({ top: 10 })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // 价格卡（复用 ModelPriceCard——与编辑模型页同一张卡，不自绘表单）。★ 决明指令
        //「价格卡加收起展开」只落模型编辑页：本页**不传 collapsible**（恒展开、标题行无箭头
        // ——本页主用途即编辑价格），勿顺手补齐
        ModelPriceCard({
          priceJson: $priceJson,
          applyJson: $applyJson,
          applyTick: $applyTick,
          onDraftChange: (draft: PriceDraftState): void => {
            this.priceDraft = draft;
          }
        })

        // 删除卡（编辑态）：危险动作单独成卡并与上方留间距，不再和保存键挤在同一视线里；用
        // 淡染红（K2 danger 档——同页只有这一张染色卡，一屏最多一张；边框保留 cardBorderColor
        // 不因染色而撤，规范 §1.3）
        if (this.templateId !== '') {
          Column({ space: 10 }) {
            Text('删除模板')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width('100%')
            Text('删除后不可恢复，已套用它的模型价格不受影响。')
              .fontSize(CARD_NOTE_FONTSIZE)
              .fontColor(cardDescColor())
              .width('100%')
            Button('删除模板')
              .fontSize(15)
              .fontColor($r('app.color.dialog_confirm_red'))
              .backgroundColor(cardBg(this.appColorMode))
              .borderRadius(16)
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .onClick((): void => {
                this.openDeleteConfirm();
              })
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .margin({ top: 6 })
          .backgroundColor(tintCardBg(TINT_DANGER, this.appColorMode, this.cardAlphaLevel))
          .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
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

  build() {
    PageShell({
      title: '编辑模板',
      menuHds: templateSaveMenuHds((): void => {
        this.save();
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
