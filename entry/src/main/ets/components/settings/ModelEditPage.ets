// 编辑模型页（三级页）：模型 ID（新建可填 / 编辑只读 + 复制键）+ 模型名称（空 = UI 兜底显示 modelId）+
// 上下文窗口（可填/可快捷档/可重置为默认参考值）+ 模型类型（对话/向量官方胶囊分段）+ 模型能力（五项多选
// 胶囊 + 重置）。保存 = 标题栏键。
// ★ 「删除模型」键已退役：删除唯一入口 = 模型行左滑（ProviderModelsPanel 编排），本页保持纯编辑——与「删除
// 走列表行的域编辑页不设删除键」对齐（服务商详情页、技能编辑页同形）。
// ★ 模型能力卡已域拆 ModelCapsCard（排版定稿随组件，翻转/重置整组替换回父侧）。
// push 参数 ModelEditParam：providerId 必填；modelRowId 空 = 新建。保存校验 = modelId 非空 + 同服务商内不重复
//（编辑改名不存在——modelId 不可改）。
import { pasteboard } from '@kit.BasicServicesKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import {
  effectiveCaps, insertModel, MODEL_CAP_CODES,
  ModelRow, queryModels, updateModel
} from '../../common/store/ProviderDb';
import {
 CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING, cardBg, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { SegmentBar } from '../SegmentBar';
import { effectiveCapsOf, lookupContextBaseline } from '../../common/providers/AiTypes';
import { ModelCapsCard } from './ModelCapsCard';
import { ModelContextCard } from './ModelContextCard';
import { ModelPriceCard, PriceDraftState } from './ModelPriceCard';
import { PriceTemplateBarCard } from './PriceTemplateBarCard';
import { InputDialog } from '../chat/InputDialog';
import {
  insertTemplate, PriceTemplateRow, PRICE_TEMPLATE_MAX,
  PRICE_TEMPLATE_NAME_MAX, queryTemplatesByProvider
} from '../../common/store/PriceTemplateDb';

import { ROUTE_MODEL_EDIT_PAGE } from '../../common/RouteNames';

// push 参数（ProviderDetailPage.openModelEdit 构造；modelRowId '' = 新建）
export interface ModelEditParam {
  providerId: string;
  modelRowId: string;
}

function modelSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
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
export struct ModelEditPage {
  // 页面存活守卫（销毁守卫治理）：置位后迟到异步回调不写状态、不碰 UI、不上行；写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 类型分段选项（对话/向量——图片参考形态两型）
  private kindItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '对话' },
    { text: '向量' }
  ]);
  // 能力多选胶囊（五项码表驱动；选中态 = 强调色边框）
  @State private caps: boolean[] = [false, false, false, false, false];
  // 派生/覆盖态：编辑态初始 = 行 capsUserModified——false = 未手改（勾选态显示 effectiveCaps 派生值 + 说明行），
  // 页内翻转即置 true（保存固化）；★「重置」键也回 false——重置 = 恢复自动识别（勾选态回填派生值、保存时 caps
  // 落空串 + 标志位落 0，与「从未手改」完全同态），不再把「全不勾」固化下来。新建态恒 true（insertModel 按 caps
  // 非空⇒1 落值；点过「重置」者随之落回派生态）
  @State private userModified: boolean = true;
  @State private kindIndex: number = 0;
  @State private modelId: string = '';
  @State private name: string = '';
  // 上下文窗口：contextWindow = 用户覆盖值（0 = 未配置，落 context_window 列）；contextBaseline = 内置参考值
  //（按模型名派生，不落库、只作卡面展示）。★ 载入与模型 ID 输入回调两处赋值，build 内零计算（宪法性能红线）
  @State private contextWindow: number = 0;
  @State private contextBaseline: number = 0;
  // 行 price_config 原文（@Link 绑定——PageShell.content 内禁 @Prop 下发热点：异步晚到时首帧冻结；新建态恒 ''）
  @State private priceJson: string = '';
  // 价格卡草稿最新值（onDraftChange 上行持有；保存链消费——json 随 insert/update 落 price_config，complete=false 整体拦截）
  private priceDraft: PriceDraftState = { json: '', complete: true, hint: '' };
  // 价格模板条卡域（条卡挂「模型价格」卡正上方）；模板清单 @State 数组整组替换 = 条卡 @Link 刷新
  @State private priceTemplates: PriceTemplateRow[] = [];
  // 套用通道两值（绑定价格卡 @Link）：先写载荷再自增纪元，两行序不可颠倒——同值 JSON 也必触发
  @State private priceApplyJson: string = '';
  @State private priceApplyTick: number = 0;
  // 命名弹窗控制器（成员位按需构造——坑7）
  private nameDialogCtrl: CustomDialogController | null = null;
  // 编辑对象行 id（'' = 新建）与所属服务商（两形态都必填——模型行必须挂在服务商下）
  private rowId: string = '';
  private providerId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条）；providerId 缺失 = 异常栈（入口唯一且必传）——退栈兜底
    const params: Array<ModelEditParam> =
      this.pathStack.getParamByName(ROUTE_MODEL_EDIT_PAGE) as Array<ModelEditParam>;
    const param: ModelEditParam | undefined =
      params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param.providerId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '参数缺失' });
      this.pathStack.pop();
      return;
    }
    this.providerId = param.providerId;
    // 价格模板条卡数据源（新建/编辑两态 providerId 均在场，条卡照常可用——套用与存模板只依赖 providerId +
    // priceDraft，与 rowId 无关）
    this.reloadPriceTemplates();
    if (param.modelRowId === '') {
      return; // 新建：空表单
    }
    queryModels(this.providerId, '')
      .then((rows: ModelRow[]): void => {
        if (this.departed) {
          return;
        }
        const row: ModelRow | undefined =
          rows.find((item: ModelRow): boolean => item.id === param.modelRowId);
        if (row === undefined) {
          this.getUIContext().getPromptAction().showToast({ message: '模型不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.rowId = row.id;
        this.userModified = row.capsUserModified;
        this.modelId = row.modelId;
        this.name = row.name;
        this.priceJson = row.priceConfig;
        // 上下文窗口：用户覆盖值 = 行列原样；参考值按行模型名读时派生（不落库——与 caps 派生同构）
        this.contextWindow = row.contextWindow;
        this.contextBaseline = lookupContextBaseline(row.modelId);
        this.kindIndex = row.kind === 'embedding' ? 1 : 0;
        // 勾选态回填走生效能力（未手改行 = 模型名派生值——规则升级自动跟随；已固化行 = caps 原样；effectiveCaps 单源见 ProviderDb）
        const set: string[] = effectiveCaps(row).split(',');
        for (let i = 0; i < MODEL_CAP_CODES.length; i++) {
          this.caps[i] = set.includes(MODEL_CAP_CODES[i]);
        }
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '模型读取失败：' + (e as Error).message });
      });
  }

  // 模型清单刷新 = 详情页 openModelEdit 的 onPop 回调双纪元自增（坑16），保存 pop 带 result 触发；原
  // MODEL_LIST_RELOAD_KEY 广播已删。口径演进见 ProviderDetailPage 注释

  // caps 布尔数组 → 逗号码串
  private capsText(): string {
    const parts: string[] = [];
    for (let i = 0; i < MODEL_CAP_CODES.length; i++) {
      if (this.caps[i]) {
        parts.push(MODEL_CAP_CODES[i]);
      }
    }
    return parts.join(',');
  }

  // 保存：modelId 非空（新建必填）+ 价格草稿完整（不完整整体拦截 toast，防半份配置静默落库）+ 同服务商查重
  //（新建）→ insert/update → toast + pop
  private save(): void {
    const modelId: string = this.modelId.trim();
    if (modelId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '模型 ID 不能为空' });
      return;
    }
    if (!this.priceDraft.complete) {
      // 拦截原因由价格卡草稿上行时给出（主价/谷时价/谷时日各不同），hint 缺失回退通用文案
      this.getUIContext().getPromptAction().showToast(
        { message: this.priceDraft.hint !== '' ? this.priceDraft.hint :
          '模型价格须为非负数字，输入价格与输出价格须同时填写' });
      return;
    }
    const kind: string = this.kindIndex === 1 ? 'embedding' : 'chat';
    // caps 落库值：未手改（含刚点过「重置」）= 落空串 + 标志位 0，读侧 effectiveCaps 走模型名派生（规则升级自动
    // 跟随）；手改 = 原样落库（含全不勾的显式清空，固化——这正是引入标志位而非约定空串的原因）
    const capsForSave: string = this.userModified ? this.capsText() : '';
    const name: string = this.name.trim();
    const priceConfig: string = this.priceDraft.json;
    const finish = (): void => {
      if (this.departed) {
        return; // 自检轮 1712 修正：写库照常（insert/update 不判守），只放弃已亡组件上的 UI
      }
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      // pop 带 result 触发详情页 openModelEdit onPop → 双纪元自增（坑17：onPop 触发条件 = pop 必带 result，无参不触发）
      this.pathStack.pop({ saved: true });
    };
    const fail = (e: Object): void => {
      if (this.departed) {
        return; // 自检轮 1712 修正：同上，失败 toast 也只在页面存活时给
      }
      this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
    };
    if (this.rowId === '') {
      queryModels(this.providerId, '')
        .then((rows: ModelRow[]): Promise<void> => {
          if (rows.some((row: ModelRow): boolean => row.modelId === modelId)) {
            if (this.departed) {
              return Promise.resolve();
            }
            this.getUIContext().getPromptAction().showToast({ message: '该模型已存在：' + modelId });
            return Promise.resolve();
          }
          return insertModel(this.providerId, modelId, name, kind, capsForSave, priceConfig,
            this.contextWindow)
            .then((): void => {
              finish();
            });
        })
        .catch(fail);
    } else {
      // capsUserModified 随覆盖态走：手改 = true 固化（含全不勾的显式清空）；未手改 / 刚点过「重置」= false +
      // caps 空串 → 读侧回派生（把模型还给自动识别）。priceConfig 随同条 UPDATE 落库（'' = 清除配置回未配置）；
      // contextWindow 同条落库（0 = 未配置 = 跟随参考值）
      updateModel(this.rowId, name, kind, capsForSave, this.userModified, priceConfig,
        this.contextWindow)
        .then((): void => {
          finish();
        })
        .catch(fail);
    }
  }

  // （删除链已整段退役——编排归 ProviderModelsPanel，本页 pop 只剩保存一种 result）

  // 价格模板链 A/B（条卡纯展示，编排全在本页）

  // 模板重拉（挂载 + 存模板后两调用点；数组整组替换 → 条卡 @Link 刷新）
  private reloadPriceTemplates(): void {
    queryTemplatesByProvider(this.providerId)
      .then((rows: PriceTemplateRow[]): void => {
        if (this.departed) {
          return;
        }
        this.priceTemplates = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '模板读取失败：' + (e as Error).message });
      });
  }

  // 链 A · 套用模板（条卡 chip 点击）：先写载荷再自增纪元（同值 JSON 也必触发）→ 价格卡整组回填 + 草稿上行；
  // toast 本页发（条卡纯展示）。直接整组覆盖无二次确认 = 决明拍板
  private applyPriceTemplate(name: string, priceConfig: string): void {
    this.priceApplyJson = priceConfig; // ① 先写载荷（卡内 @Watch 读它）
    this.priceApplyTick += 1;          // ② 再自增纪元（同值 JSON 也能触发）
    this.getUIContext().getPromptAction().showToast({ message: '已填入 ' + name + ' 模板' });
  }

  // 链 B · 存为模板：守卫（上限一道 + 草稿完整一道）→ 命名弹窗 → onConfirm 落库 + 重拉
  private onSaveAsTemplate(): void {
    // 上限置灰之外再拦一道（ModelPriceCard.addSeg 双守卫先例；insertTemplate 内另有 throw 兜底，共三层）
    if (this.priceTemplates.length >= PRICE_TEMPLATE_MAX) {
      this.getUIContext().getPromptAction().showToast(
        { message: '最多保存 ' + PRICE_TEMPLATE_MAX + ' 套模板，删除后可再添加' });
      return;
    }
    // 草稿前置 = complete && json 非空（口径⑥；hint 优先直显，缺失回退通用文案）
    if (this.priceDraft.json === '' || !this.priceDraft.complete) {
      this.getUIContext().getPromptAction().showToast(
        { message: this.priceDraft.hint !== '' ? this.priceDraft.hint :
          '请先填写完整的模型价格，再存为模板' });
      return;
    }
    this.nameDialogCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '存为价格模板',
        initialText: '',
        placeholder: '例如 DeepSeek 官方价',
        confirmLabel: '保存',
        maxLength: PRICE_TEMPLATE_NAME_MAX,
        onConfirm: (name: string): void => {
          this.insertPriceTemplate(name);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.nameDialogCtrl.open();
  }

  // 命名确认后落库：同服务商同名查重（新建模板无自身 id，直接查全量）→ insert → 重拉 chips（挂载 + 存模板后）→ toast
  private insertPriceTemplate(name: string): void {
    const dup: boolean = this.priceTemplates.some((t: PriceTemplateRow): boolean => t.name === name);
    if (dup) {
      this.getUIContext().getPromptAction().showToast({ message: '已有同名模板：' + name });
      return;
    }
    insertTemplate(this.providerId, name, this.priceDraft.json)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.reloadPriceTemplates();
        this.getUIContext().getPromptAction().showToast({ message: '已存为模板 ' + name });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '存为模板失败：' + (e as Error).message });
      });
  }

  // 复制模型 ID（官方粘贴板；Promise 失败 toast 不静默）
  private copyModelId(): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.modelId);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已复制模型 ID' });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '复制失败：' + (e as Error).message });
      });
  }

  // 标题（新建/编辑双形态）
  private pageTitle(): string {
    return this.rowId === '' ? '添加模型' : '编辑模型';
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 基础卡：模型 ID / 名称 ──
        Column({ space: 12 }) {
          Text('模型')
            .fontSize(CARD_SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          if (this.rowId === '') {
            Column({ space: 6 }) {
              Text('模型 ID')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              TextInput({ placeholder: '如 deepseek-chat，服务商模型名', text: this.modelId })
                .width('100%')
                .onChange((value: string): void => {
                  this.modelId = value;
                  // 参考值随模型名实时派生——调用点在事件回调内，不进 build（宪法性能红线：build 内零计算）
                  this.contextBaseline = lookupContextBaseline(value);
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          } else {
            // 编辑态：modelId = 行身份不可改；复制键粘贴板直拷
            Column({ space: 6 }) {
              Text('模型 ID')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              Row({ space: 8 }) {
                Text(this.modelId)
                  .fontSize(16)
                  .fontColor(cardTitleColor())
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Button() {
                  SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
                    .fontSize(16)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  this.copyModelId();
                })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          Column({ space: 6 }) {
            Text('模型名称，可选，展示用')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextInput({ placeholder: '如 DeepSeek 对话', text: this.name })
              .width('100%')
              .onChange((value: string): void => {
                this.name = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // 上下文窗口卡（基础信息之后、模型类型之前；值随模型行保存）。★ 两值走 @Link（$ 语法）+ onCommit 上行——
        // 快捷档点击 / 输入确认 / 重置三路都只回父侧赋值（卡不直写）；@Prop 在 PageShell.content 内会首帧冻结（坑16）
        ModelContextCard({
          value: $contextWindow,
          baseline: $contextBaseline,
          onCommit: (v: number): void => {
            // 直接覆盖用户值（0 = 清值回未配置，展示自动回参考值态）
            this.contextWindow = v;
          }
        })

        // ── 类型卡：对话/向量分段（官方胶囊）──
        Column({ space: 10 }) {
          Text('模型类型')
            .fontSize(CARD_SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Column() {
            SegmentBar({
              items: this.kindItems,
              selectedIndex: $kindIndex
            })
          }
          .width(CARD_PANEL_WIDTH)
          // ★ 胶囊左右居中（卡内宽已收 16×2，容器宽 CARD_PANEL_WIDTH 再窄于卡内宽，Start 对齐下右侧留空不对称；
          // alignSelf 覆盖卡 Column 的 Start 对齐、交叉轴居中，两侧等距）
          .alignSelf(ItemAlign.Center)
          Text(this.kindIndex === 1 ? '用于文本向量化，不参与聊天' : '用于聊天与助手回复')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // 能力卡（域拆 ModelCapsCard——排版定稿随组件，翻转/重置整组替换回父侧）。★ caps/userModified 走 @Link
        //（$ 语法；两值同为异步回填，@Prop 在 PageShell.content 内会首帧冻结，见价格卡同注）
        ModelCapsCard({
          caps: $caps,
          userModified: $userModified,
          onToggleCap: (index: number): void => {
            // 单项翻转 + 整组一次性替换（@State 数组须整体赋值刷新）；点击即用户手改（派生说明行消失，保存固化）
            this.userModified = true;
            const next: boolean[] = this.caps.slice();
            next[index] = !next[index];
            this.caps = next;
          },
          onReset: (): void => {
            // 重置 = 恢复自动识别（原「全 false 固化」作废）：标志位回 false + 勾选态回填模型名派生值——保存后
            // caps 落空串、标志位落 0，此后规则升级自动跟随（与「从未手改」完全同态）；说明行随 false 自动复现
            this.userModified = false;
            const derived: string[] = effectiveCapsOf(false, '', this.modelId.trim()).split(',');
            const next: boolean[] = [false, false, false, false, false];
            for (let i = 0; i < MODEL_CAP_CODES.length; i++) {
              next[i] = derived.includes(MODEL_CAP_CODES[i]);
            }
            this.caps = next;
          }
        })

        // 价格模板条卡（价格卡正上方——条卡在模板编辑页不挂载故 ModelPriceCard 布局零扰动；templates @Link 引用
        // 下发，存模板后整组替换即刷新）。★ 卡宽由卡体自持 CARD_PANEL_WIDTH（本列容器无左右 padding，收窄责任在卡
        // ——勿在此外套宽度壳，会双重收窄）
        PriceTemplateBarCard({
          templates: $priceTemplates,
          onApply: (name: string, priceConfig: string): void => {
            this.applyPriceTemplate(name, priceConfig);
          },
          onSaveAsTemplate: (): void => {
            this.onSaveAsTemplate();
          }
        })

        // 价格卡（能力卡之后、页内末卡——价格属模型行元数据编辑域；草稿即时上行、随标题栏勾键统一保存）。★
        // priceJson 走 @Link（$ 语法）——@Prop 值传在 PageShell.content 内会首帧冻结；applyJson/applyTick = 套用
        // 刷新通道（条卡 chip → 本页两行序 → 卡内 @Watch 回填）。★ collapsible 启用折叠（标题行箭头 + 整行点收起）
        // ——本页多卡同列、谷时多段时价格卡占屏很高；价格模板编辑页复用本卡但不传（恒展开）
        ModelPriceCard({
          priceJson: $priceJson,
          applyJson: $priceApplyJson,
          applyTick: $priceApplyTick,
          collapsible: true,
          onDraftChange: (draft: PriceDraftState): void => {
            this.priceDraft = draft;
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18）+ 可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: this.pageTitle(),
      menuHds: modelSaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
