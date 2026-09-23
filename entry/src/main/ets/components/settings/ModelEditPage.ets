// 编辑模型页（2026-08-30 服务商管理域新建，图片参考形态对齐，三级页）：模型 ID
//（新建可填 / 编辑只读 + 复制键）+ 模型名称（空 = UI 兜底显示 modelId）+ 上下文窗口
//（2026-09-17 v33 新增卡，可填/可快捷档/可重置为默认参考值）+ 模型类型
//（对话/向量官方胶囊分段）+ 模型能力（五项多选胶囊 + 重置）。保存 = 标题栏键（详情页
// 同款）。
// ★ 2026-09-17 底部「删除模型」键退役（决明指令）：删除入口只留模型卡四点键菜单
//（ModelCardMenu → ProviderModelsPanel 编排），本页回归纯编辑——与「有卡片菜单删除的域
// 编辑页不设删除键」的现状对齐（服务商详情页、技能编辑页同形）；原「编删同页」形制随
// 入口收敛一并作废。
// ★ 模型能力卡已域级拆出 ModelCapsCard（2026-08-30 反馈轮 13——399 行距红线 1 行后
// 「重置键去胶囊遮罩」改动前先拆；排版定稿随组件，翻转/重置整组替换回父侧）。
// push 参数 ModelEditParam（详情页模型页签）：providerId 必填；modelRowId 空 = 新建。
// 保存校验：modelId 非空 + 同服务商内不重复（新建查重/编辑改名不存在——modelId 不可改）。
import { pasteboard } from '@kit.BasicServicesKit';
import { SegmentButtonV2Items, SymbolGlyphModifier } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import {
  effectiveCaps, insertModel, MODEL_CAP_CODES,
  ModelRow, queryModels, updateModel
} from '../../common/store/ProviderDb';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
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

function modelSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

@Component
export struct ModelEditPage {
  @Prop topPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 类型分段选项（对话/向量——图片参考形态两型）
  private kindItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '对话' },
    { text: '向量' }
  ]);
  // 能力多选胶囊（五项码表驱动；选中态 = 强调色边框）
  @State private caps: boolean[] = [false, false, false, false, false];
  // 派生/覆盖态（2026-09-03 Cube 吸收 A1，v15）：编辑态初始 = 行 capsUserModified——
  // false = 未手改（勾选态显示 effectiveCaps 派生值 + ModelCapsCard 说明行），页内翻转即置
  // true（保存固化）；★ 2026-09-17 v33 重置语义修正后**「重置」键也回 false**——重置 =
  // 恢复自动识别（勾选态回填派生值、保存时 caps 落空串 + 标志位落 0，与「从未手改」的行
  // 完全同态），不再是把「全不勾」固化下来。新建态恒 true（勾选即用户手设，insertModel
  // 内部按 caps 非空⇒1 落值；新建后点过「重置」者随之落回派生态）
  @State private userModified: boolean = true;
  @State private kindIndex: number = 0;
  @State private modelId: string = '';
  @State private name: string = '';
  // 上下文窗口（2026-09-17 v33 模型上下文窗口配置）：contextWindow = 用户覆盖值（0 = 未配置，
  // 落 provider_models.context_window 列）；contextBaseline = 内置参考值（ModelRegistry
  // lookupContextBaseline 按模型名派生，**不落库**、只作卡面展示）。★ 载入与模型 ID 输入
  // 回调两处赋值，build 内零计算（宪法性能红线）
  @State private contextWindow: number = 0;
  @State private contextBaseline: number = 0;
  // 行 price_config 原文（2026-09-10 费用估计；★ 2026-09-11 自检轮改 @Link 绑定——本页
  // 内容的子组件一律走 @Link/广播键自订阅，禁 @Prop 下发热点：行数据异步晚到时驱动
  // ModelPriceCard 草稿回填，@Prop 在 PageShell.content 内可能首帧冻结；新建态恒 ''）
  @State private priceJson: string = '';
  // 价格卡草稿最新值（onDraftChange 上行持有；保存链消费——json 随 insert/update 落
  // price_config 列，complete=false 整体拦截）
  private priceDraft: PriceDraftState = { json: '', complete: true, hint: '' };
  // ── 价格模板条卡域（2026-09-11 价格模板；条卡挂「模型价格」卡正上方）──
  // 当前服务商模板清单（@State 数组整组替换 = 条卡 @Link 刷新；存模板后重拉替换）
  @State private priceTemplates: PriceTemplateRow[] = [];
  // 套用通道两值（@State 绑定价格卡 @Link）：先写载荷再自增纪元，两行序不可颠倒——
  // 同值 JSON 也要必触发（链 A 步 5，ModelPriceCard.applyJson 成员区注释同源）
  @State private priceApplyJson: string = '';
  @State private priceApplyTick: number = 0;
  // 命名弹窗控制器（成员位按需构造——坑7）
  private nameDialogCtrl: CustomDialogController | null = null;
  // 编辑对象行 id（'' = 新建）与所属服务商（两形态都必填——模型行必须挂在服务商下）
  private rowId: string = '';
  private providerId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条，ImageEditPage 先例）；providerId 缺失 = 异常栈
    //（入口唯一且必传）——退栈兜底
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
    // 价格模板条卡数据源（链 D：新建/编辑两态 providerId 均在场，条卡照常可用——
    // 套用与存模板只依赖 providerId + priceDraft，与 rowId 无关）
    this.reloadPriceTemplates();
    if (param.modelRowId === '') {
      return; // 新建：空表单
    }
    queryModels(this.providerId, '')
      .then((rows: ModelRow[]): void => {
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
        // 上下文窗口（2026-09-17 v33）：用户覆盖值 = 行列原样；参考值按行模型名读时派生
        //（不落库——与上面 caps 派生同构）
        this.contextWindow = row.contextWindow;
        this.contextBaseline = lookupContextBaseline(row.modelId);
        this.kindIndex = row.kind === 'embedding' ? 1 : 0;
        // 勾选态回填走生效能力（未手改行 = 模型名派生值——ModelRegistry 规则升级自动
        // 跟随；已固化行 = caps 原样），effectiveCaps 单源见 ProviderDb
        const set: string[] = effectiveCaps(row).split(',');
        for (let i = 0; i < MODEL_CAP_CODES.length; i++) {
          this.caps[i] = set.includes(MODEL_CAP_CODES[i]);
        }
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '模型读取失败：' + (e as Error).message });
      });
  }

  // （2026-08-30 刷新链路收敛：原 aboutToDisappear 的 MODEL_LIST_RELOAD_KEY 广播已删——
  // 模型清单刷新 = 详情页 openModelEdit 的 onPop 回调双纪元自增，坑16 复活自动链，
  // 保存 pop 带 result 触发（删除已随本页删除键退役移出本页，见文件头条）；口径演进见
  // ProviderDetailPage 注释）

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

  // 保存：modelId 非空（新建必填）+ 价格草稿完整（2026-09-10 费用估计——不完整整体拦截
  // toast，防半份配置静默落库）+ 同服务商查重（新建）→ insert/update → toast + pop
  private save(): void {
    const modelId: string = this.modelId.trim();
    if (modelId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '模型 ID 不能为空' });
      return;
    }
    if (!this.priceDraft.complete) {
      // 拦截原因由价格卡草稿上行时给出（主价/谷时价/谷时日各不同——2026-09-11 谷时日
      // 维度起分因提示），hint 缺失回退通用文案
      this.getUIContext().getPromptAction().showToast(
        { message: this.priceDraft.hint !== '' ? this.priceDraft.hint :
          '模型价格须为非负数字，输入价格与输出价格须同时填写' });
      return;
    }
    const kind: string = this.kindIndex === 1 ? 'embedding' : 'chat';
    // caps 落库值（2026-09-17 v33 重置语义修正）：未手改（含刚点过「重置」）= 落空串 +
    // 标志位 0，读侧 effectiveCaps 走模型名派生（规则升级自动跟随）；手改 = 原样落库
    //（含全不勾的显式清空，固化——这正是引入标志位而非约定空串的原因）
    const capsForSave: string = this.userModified ? this.capsText() : '';
    const name: string = this.name.trim();
    const priceConfig: string = this.priceDraft.json;
    const finish = (): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      // 2026-08-30 坑17：pop 带 result 触发详情页 openModelEdit onPop → 双纪元自增
      // （顶卡计数/模型清单整卡重建——onPop 触发条件 = pop 必带 result；无参不触发）
      this.pathStack.pop({ saved: true });
    };
    const fail = (e: Object): void => {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
    };
    if (this.rowId === '') {
      queryModels(this.providerId, '')
        .then((rows: ModelRow[]): Promise<void> => {
          if (rows.some((row: ModelRow): boolean => row.modelId === modelId)) {
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
      // capsUserModified 随覆盖态走（2026-09-17 v33 语义修正）：手改 = true 固化（含全不勾的
      // 显式清空）；未手改 / 刚点过「重置」= false + caps 空串 → 读侧回派生（「重置」键的
      // 目的就是这个：把模型还给自动识别）。priceConfig 随同条 UPDATE 落库（'' = 清除配置
      // 回未配置）；contextWindow 同条落库（0 = 未配置 = 跟随参考值）
      updateModel(this.rowId, name, kind, capsForSave, this.userModified, priceConfig,
        this.contextWindow)
        .then((): void => {
          finish();
        })
        .catch(fail);
    }
  }

  // （2026-09-17 删除链整段退役：openDeleteConfirm / deleteRow / confirmCtrl 成员——删除
  // 入口收进模型卡四点键菜单，编排归 ProviderModelsPanel；本页 pop 只剩保存一种 result）

  // ── 价格模板链 A/B（2026-09-11 价格模板；条卡纯展示，编排全在本页）──

  // 模板重拉（挂载 + 存模板后两调用点；数组整组替换 → 条卡 @Link 刷新）
  private reloadPriceTemplates(): void {
    queryTemplatesByProvider(this.providerId)
      .then((rows: PriceTemplateRow[]): void => {
        this.priceTemplates = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast(
          { message: '模板读取失败：' + (e as Error).message });
      });
  }

  // 链 A · 套用模板（条卡 chip 点击）：先写载荷再自增纪元（两行序不可颠倒——同值 JSON
  // 也要必触发，价格卡 applyJson 成员区注释）→ 价格卡整组回填 + 草稿上行；toast 本页发
  //（条卡纯展示）。直接整组覆盖无二次确认 = 决明拍板②
  private applyPriceTemplate(name: string, priceConfig: string): void {
    this.priceApplyJson = priceConfig; // ① 先写载荷（卡内 @Watch 读它）
    this.priceApplyTick += 1;          // ② 再自增纪元（同值 JSON 也能触发）
    this.getUIContext().getPromptAction().showToast({ message: '已填入 ' + name + ' 模板' });
  }

  // 链 B · 存为模板：守卫（上限一道 + 草稿完整一道）→ 命名弹窗 → onConfirm 落库 + 重拉
  private onSaveAsTemplate(): void {
    // 上限置灰之外再拦一道（ModelPriceCard.addSeg 双守卫先例——防将来键形制改动穿透；
    // insertTemplate 内另有 throw 兜底，共三层）
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

  // 命名确认后落库：同服务商同名查重（新建模板无自身 id，直接查全量）→ insert → 重拉
  // chips（断言⑭：重拉调用点 ≥2 = 挂载 + 存模板后）→ toast
  private insertPriceTemplate(name: string): void {
    const dup: boolean = this.priceTemplates.some((t: PriceTemplateRow): boolean => t.name === name);
    if (dup) {
      this.getUIContext().getPromptAction().showToast({ message: '已有同名模板：' + name });
      return;
    }
    insertTemplate(this.providerId, name, this.priceDraft.json)
      .then((): void => {
        this.reloadPriceTemplates();
        this.getUIContext().getPromptAction().showToast({ message: '已存为模板 ' + name });
      })
      .catch((e: Object): void => {
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
        this.getUIContext().getPromptAction().showToast({ message: '已复制模型 ID' });
      })
      .catch((e: Object): void => {
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
      Column({ space: 10 }) {
        // ── 基础卡：模型 ID / 名称 ──
        Column({ space: 12 }) {
          Text('模型')
            .fontSize(16)
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
                  // 参考值随模型名实时派生（2026-09-17 v33）——调用点在事件回调内，
                  // 不进 build（宪法性能红线：build 内零计算）
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
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // ── 上下文窗口卡（2026-09-17 v33 新增，卡序照参考图：基础信息之后、模型类型之前）
        // ——可填/可快捷档/可重置为默认参考值，值随模型行保存。★ 两值走 @Link 引用下发
        //（$ 语法）+ onCommit 回调上行：快捷档点击、输入确认、重置为默认三路都只回父侧
        // 赋值（卡不直写）；@Prop 值传在 PageShell.content 内会首帧冻结（见价格卡同注，
        // 坑16 家族）──
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
            .fontSize(16)
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
          // ★ 胶囊左右居中（2026-08-30 反馈轮 12 领导指令——卡内宽已收 16×2，容器宽
          // CARD_PANEL_WIDTH 再窄于卡内宽，Start 对齐下右侧留空不对称；alignSelf 覆盖
          // 卡 Column 的 Start 对齐、交叉轴居中，两侧等距）
          .alignSelf(ItemAlign.Center)
          Text(this.kindIndex === 1 ? '用于文本向量化，不参与聊天' : '用于聊天与助手回复')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // ── 能力卡（轮 13 域级拆出 ModelCapsCard——排版定稿随组件；翻转/重置整组替换
        // 回父侧）。★ caps/userModified 走 @Link 引用下发（$ 语法；2026-09-11 自检轮 O6——
        // 两值同为异步回填，@Prop 在 PageShell.content 内会首帧冻结，见价格卡同注）──
        ModelCapsCard({
          caps: $caps,
          userModified: $userModified,
          onToggleCap: (index: number): void => {
            // 单项翻转 + 整组一次性替换（@State 数组须整体赋值刷新）；点击即用户手改
            //（派生说明行消失，保存固化）
            this.userModified = true;
            const next: boolean[] = this.caps.slice();
            next[index] = !next[index];
            this.caps = next;
          },
          onReset: (): void => {
            // 重置 = 恢复自动识别（2026-09-17 v33 语义修正，原「全 false 固化」作废）：
            // 标志位回 false + 勾选态回填模型名派生值——保存后 caps 落空串、标志位落 0，
            // 此后规则升级自动跟随（与「从未手改」的行完全同态）；说明行随 false 自动复现
            this.userModified = false;
            const derived: string[] = effectiveCapsOf(false, '', this.modelId.trim()).split(',');
            const next: boolean[] = [false, false, false, false, false];
            for (let i = 0; i < MODEL_CAP_CODES.length; i++) {
              next[i] = derived.includes(MODEL_CAP_CODES[i]);
            }
            this.caps = next;
          }
        })

        // ── 价格模板条卡（2026-09-11 价格模板；价格卡正上方——口径⑨取「外」，条卡在
        // 模板编辑页不挂载故 ModelPriceCard 布局零扰动；templates @Link 数组引用下发，
        // 存模板后整组替换即刷新；套用与存模板编排在本页两链方法）。★ 卡宽由卡体自持
        // CARD_PANEL_WIDTH（本列容器无左右 padding，收窄责任在卡——勿在此外套宽度壳，
        // 会双重收窄）──
        PriceTemplateBarCard({
          templates: $priceTemplates,
          onApply: (name: string, priceConfig: string): void => {
            this.applyPriceTemplate(name, priceConfig);
          },
          onSaveAsTemplate: (): void => {
            this.onSaveAsTemplate();
          }
        })

        // ── 价格卡（2026-09-10 费用估计；能力卡之后、页内末卡——价格属模型行元数据
        // 编辑域，与能力卡同组；草稿即时上行、随标题栏勾键统一保存）。★ priceJson 走
        // @Link 引用下发（$ 语法）——@Prop 值传在 PageShell.content 内会首帧冻结（见上）；
        // applyJson/applyTick = 套用刷新通道（条卡 chip → 本页两行序 → 卡内 @Watch 回填，
        // 链 A）。★ 2026-09-17 决明指令「模型能力页价格卡加收起展开」：本页传 collapsible
        // 启用折叠（标题行箭头 + 整行点收起，收起态只留主副标题两行）——本页五卡同列，
        // 谷时多段时价格卡占屏很高；价格模板编辑页复用本卡但不传（恒展开）──
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
  }

  build() {
    PageShell({
      title: this.pageTitle(),
      menuHds: modelSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: modelSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content()
      }
    })
  }
}
