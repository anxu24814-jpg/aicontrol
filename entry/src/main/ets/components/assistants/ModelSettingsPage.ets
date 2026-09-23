// 模型设置页（2026-09-01 领导指令：助手编辑页首卡「模型设置」进入——助手级模型绑定
// 〔RikkaHub chatModelId 同语义，DB v10 assistants 三列〕）：
// · 页面形态：PageShell 自包壳（助手域各页同款），标题「模型设置」；页内单卡 = 上部
//   当前绑定显示（模型显示名 + 思考强度文案，未绑定位显示「未选择」）+ 下部双键（左
//   「选择模型」右「思考强度」，行内官方灰底形制——余额查询卡双键同款，同宽各半行）。
// · 选择模型 = ModelPickerSheet 半模态（领导指令「同会话页」；打勾经 selProviderId 直传
//   直传绑定值，不读写全局 ACTIVE 两键）——选中即落库（updateAssistantModelBinding，
//   即时生效不经保存键——重命名同款口径）并收面板；换模型后档位合法性守卫（ChatPage
//   setConnInfo 同款语义，2026-09-06 泛化为 legalThinkingTier 单一源）：新绑定下非法
//   档位（off 禁域 / 选项集收窄外）→ thinkLevel 归 ''。
// · 思考强度 = ThinkingMenu 官方菜单（2026-09-01 自 ChatParamChipBar 提取的独立组件，
//   「同会话页」机制：选项集 thinkingOptionsFor 按绑定服务商+模型派生（2026-09-06
//   模型级精化，原全量 THINKING_OPTIONS），「关闭」项按 supportsThinkingOff(baseUrl,
//   modelId) 显隐 = 菜单内容随已选模型改变的映射点）；★ 未绑定模型时点按
//   toast「请先选择模型」（领导指令新增守卫——bindMenu 仅在绑定态挂载，未绑定态走
//   onClick toast，两态 if/else 分支渲染）。
// · 刷新链：落库即本页 @State 同步（无缓存窗口）；返回 = onBackPressed 拦截
//   pop({saved:true})（坑17「无保存动作的完成返回」姿势——排序页/助手编辑页先例）→
//   编辑页 onPop 重拉卡片摘要。
// · 清删联动（级联 + 读侧兜底双保险）：删服务商/删模型 → ProviderDb 删除函数内清
//   assistants 绑定列（clearAssistantBindingByProvider/ByModel）；本页 reloadBinding
//   读侧行/服务商/模型任一缺失 → 显示「未选择」（窗口期兜底，不写库）。
// · 发送链覆盖 2026-09-05 落地（调研待办 2）：本页绑定的模型 = 发送链四级兜底第②级
//   来源（会话页所选 > 助手绑定 > 全局默认 > 首个启用模型，中途不停）——解析链细则见
//   ProviderDb.resolveActiveConnection 头注释（AssistantDb 头注释⑦同口径）。
// · 全局兜底配置 = 设置页「功能模型」页「默认模型」（2026-09-05，第③级来源）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { ROUTE_MODEL_SETTINGS_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { THINKING_OPTIONS, supportsThinkingOff, legalThinkingTier, thinkingOptionsFor } from '../../common/providers/AiTypes';
import { AssistantRow, queryAssistant, updateAssistantModelBinding, updateAssistantThinkLevel } from '../../common/store/AssistantDb';
import { CONN_RESOLVE_TICK_KEY, ModelRow, ProviderRow, queryModels, queryProviders } from '../../common/store/ProviderDb';
import { ModelPickerSheet } from '../chat/ModelPickerSheet';
import { ThinkingMenu } from '../chat/ChatParamChipBar';
import { sheetPanelOptions, DETENTS_FULL } from '../chat/KimiSheetCommon';

@Component
export struct ModelSettingsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id，编辑页传入）
  private rowId: string = '';
  // 绑定态（@State——选择/档位落库后同步刷新卡面；providerId/modelId '' = 未绑定）
  @State private providerId: string = '';
  @State private modelId: string = '';
  @State private thinkLevel: string = '';
  // 绑定展示镜像：模型显示名（name 空兜底 modelId；@State 驱动显示区重建）
  @State private modelLabel: string = '';
  // 绑定服务商 baseUrl（普通成员——offOk 判定入参，菜单每次弹出重建取当前值；无 UI 直渲染）
  private boundBaseUrl: string = '';
  // 绑定服务商协议/接口形态（2026-09-06 模型级精化：思考菜单选项集派生入参；同
  // boundBaseUrl 普通成员，resolveBoundDisplay 一并填充/清空）
  private boundProtocol: string = '';
  private boundEndpoint: string = '';
  // 模型选择半模态开关（坑64 姿势：声明式 bindSheet 挂页面根）
  @State private sheetShow: boolean = false;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条，AssistantEditPage 同款姿势）：string id（首卡
    // push 必非空；空/缺参 = 异常路径弹回）
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_MODEL_SETTINGS_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    this.reloadBinding();
  }

  // 绑定判定（交互守卫与显示共用）
  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  // 档位文案（'' = 默认不传 / off = 关闭 / 其余档位原文——ChatParamChipRow.label 同口径）
  private effortLabel(): string {
    return this.thinkLevel === '' ? '默认' :
      this.thinkLevel === 'off' ? '关闭' : this.thinkLevel;
  }

  // 思考菜单选项集派生（2026-09-06 模型级精化）：画像行收窄集或全量缺省
  //（ModelRegistry.thinkingOptionsFor 经 AiTypes 门面）；未绑定 = 全量（菜单仅绑定态
  // 挂载，无实际消费）
  private menuOptions(): string[] {
    if (!this.bound()) {
      return THINKING_OPTIONS;
    }
    return thinkingOptionsFor(this.boundProtocol, this.boundEndpoint, this.boundBaseUrl, this.modelId);
  }

  // 重读绑定行（DB 单一真源，aboutToAppear 调用；读侧兜底 = 行/服务商/模型任一缺失
  // 显示未选择——级联清列后的窗口期不写库）
  private async reloadBinding(): Promise<void> {
    let row: AssistantRow | null = null;
    try {
      row = await queryAssistant(this.rowId);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
      this.pathStack.pop();
      return;
    }
    if (row === null) {
      this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
      this.pathStack.pop();
      return;
    }
    this.providerId = row.providerId;
    this.modelId = row.modelId;
    this.thinkLevel = row.thinkLevel;
    if (this.bound()) {
      try {
        await this.resolveBoundDisplay();
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '绑定信息读取失败：' + (e as Error).message });
      }
      // 档位合法性归一（2026-09-06 模型级精化）：画像升级后存量 thinkLevel 可能非法
      //（如 kimi-k3 旧存 off）——归默认并落库，与 onPickModel 守卫同律
      //（legalThinkingTier 单一源）
      const legal: string = legalThinkingTier(this.thinkLevel,
        supportsThinkingOff(this.boundBaseUrl, this.modelId), this.menuOptions());
      if (legal !== this.thinkLevel) {
        try {
          await updateAssistantThinkLevel(this.rowId, legal);
          this.thinkLevel = legal;
        } catch (e) {
          this.getUIContext().getPromptAction().showToast({ message: '思考强度修正失败：' + (e as Error).message });
        }
      }
    }
  }

  // 绑定展示解析（providerId/modelId → 服务商 baseUrl + 模型显示名；服务商/模型行缺失
  // = 保留空显示——清删窗口期兜底）
  private async resolveBoundDisplay(): Promise<void> {
    this.boundBaseUrl = '';
    this.boundProtocol = '';
    this.boundEndpoint = '';
    this.modelLabel = '';
    const providers: ProviderRow[] = await queryProviders();
    const provider: ProviderRow | undefined =
      providers.find((p: ProviderRow): boolean => p.id === this.providerId);
    if (provider === undefined) {
      return;
    }
    this.boundBaseUrl = provider.baseUrl;
    this.boundProtocol = provider.protocol;
    this.boundEndpoint = provider.endpoint;
    const models: ModelRow[] = await queryModels(provider.id, 'chat');
    const model: ModelRow | undefined =
      models.find((m: ModelRow): boolean => m.modelId === this.modelId);
    if (model !== undefined) {
      this.modelLabel = model.name !== '' ? model.name : model.modelId;
    }
  }

  // 选择模型落库（半模态 onPick）：绑定写库 → 展示解析 → off 档位守卫 → 收面板；
  // 任一失败 toast 不静默（P0-1），面板保持打开
  private async onPickModel(providerId: string, modelId: string): Promise<void> {
    try {
      await updateAssistantModelBinding(this.rowId, providerId, modelId);
      // 广播解析输入变化（方案 a：改绑后已开着的会话页 @Watch 重解析——否则切回直接
      // 发送仍走旧 conn 缓存，自检轮 P2 缺口）
      AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
        (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
      this.providerId = providerId;
      this.modelId = modelId;
      await this.resolveBoundDisplay();
      // 档位合法性归一（2026-09-06 模型级精化泛化——原仅 off 守卫；画像行选项集收窄
      // 后存量非法档位同归默认，legalThinkingTier 单一源）
      const legal: string = legalThinkingTier(this.thinkLevel,
        supportsThinkingOff(this.boundBaseUrl, this.modelId), this.menuOptions());
      if (legal !== this.thinkLevel) {
        await updateAssistantThinkLevel(this.rowId, legal);
        this.thinkLevel = legal;
      }
      this.sheetShow = false;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '模型绑定保存失败：' + (e as Error).message });
    }
  }

  // 思考档位落库（菜单 onPick；即时生效不经保存键）
  private onPickThinking(option: string): void {
    updateAssistantThinkLevel(this.rowId, option)
      .then((): void => {
        this.thinkLevel = option;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '思考强度保存失败：' + (e as Error).message });
      });
  }

  // 模型显示行（★ 无参 @Builder 内直读 this——坑16 值参快照不自刷，绑定/名称 @State
  // 变更须驱动重建；未绑定 = 「未选择」灰字）
  @Builder
  ModelDisplayRow() {
    Row() {
      Text('模型')
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(this.bound() ? (this.modelLabel !== '' ? this.modelLabel : this.modelId) : '未选择')
        .fontSize(15)
        .fontColor(this.bound() ? cardTitleColor() : cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 思考强度显示行（口径同上——档位落库后即时回显）
  @Builder
  EffortDisplayRow() {
    Row() {
      Text('思考强度')
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(this.bound() ? this.effortLabel() : '未选择')
        .fontSize(15)
        .fontColor(this.bound() ? cardTitleColor() : cardDescColor())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 思考强度菜单（bindMenu builder 位——ThinkingMenu 独立组件挂载；offOk = 绑定服务商
  // baseUrl + 模型二维判定，选项集 = 画像行收窄派生（2026-09-06 模型级精化）——菜单
  // 弹出时构建取当前值）
  @Builder
  EffortMenuBuilder() {
    ThinkingMenu({ value: $thinkLevel, options: this.menuOptions(),
      offOk: supportsThinkingOff(this.boundBaseUrl, this.modelId),
      onPick: (option: string): void => {
        this.onPickThinking(option);
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 模型设置卡（上部绑定显示 + 下部双键；卡宽 CARD_PANEL_WIDTH 项目基准）──
        Column({ space: 14 }) {
          // 上部：当前绑定显示（绑定态 = 模型名/思考强度；未绑定 = 「未选择」）
          Column({ space: 10 }) {
            this.ModelDisplayRow()
            this.EffortDisplayRow()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          // 下部：左「选择模型」右「思考强度」双键（同宽各半行；2026-09-02 沉浸光感化 +
          // 2026-09-03 内容区回退双态）：光感态 = resolvedButton 四件套（材质随沉浸光感
          // 总档，无光感档回退官方灰底）；实底态 = fallbackButton* 官方实底（新规范下内容区
          // 材质不生效，contentFallback 开关驱动）
          Row({ space: 10 }) {
            Button('选择模型')
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.sheetShow = true;
              })
            if (this.bound()) {
              // 绑定态：挂官方菜单（REGULAR 材质基准随沉浸光感总档）
              Button('思考强度')
                .fontColor(fallbackButtonFont(this.contentFallback, false))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .layoutWeight(1)
                .bindMenu(this.EffortMenuBuilder, {
                  // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
                  systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                    this.immersiveLevel, true)
                })
            } else {
              // 未绑定态：领导指令守卫——点按 toast，不弹菜单
              Button('思考强度')
                .fontColor(fallbackButtonFont(this.contentFallback, false))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .layoutWeight(1)
                .onClick((): void => {
                  this.getUIContext().getPromptAction().showToast({ message: '请先选择模型' });
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
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

  // 半模态面板（模型选择——直传绑定值打勾，勾行为同会话页面板）
  @Builder
  SheetHost() {
    ModelPickerSheet({
      selProviderId: this.providerId,
      selModelId: this.modelId,
      onPick: (providerId: string, modelId: string): void => {
        this.onPickModel(providerId, modelId);
      },
      onClose: (): void => {
        this.sheetShow = false;
      },
      bottomInset: this.bottomPad
    })
  }

  build() {
    PageShell({
      title: '模型设置',
      // 右上角无菜单键（单卡页，无动作项）
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17「无保存动作」姿势——编辑页 onPop 重拉卡片摘要；
        // 未改动返回 reload 幂等无害）
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
      // 模型选择半模态（坑64 姿势；档位 = DETENTS_FULL 全屏单挡位——★ 2026-09-15 决明
      // 指令：选择模型面板默认展开全屏 + 取消半屏态 + 下拉直接收起，三站点同款同源）
      .bindSheet(this.sheetShow, this.SheetHost(), sheetPanelOptions((): void => {
        this.sheetShow = false;
      }, DETENTS_FULL))
  }
}
