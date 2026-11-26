// 助手编辑页「模型与提示词」组卡域件（模型设置二级页退役后原页内卡就地移出成件）。
// 一句话职责 = 助手级模型绑定、思考档位与提示词入口的三行组卡（行 = 模型 / 思考强度 /
// 提示词），含选择模型半模态、思考档位菜单、提示词二级页返回重拉，以及落库与档位合法性
// 守卫、绑定名上行。
// ★ 组卡形制（决明指令）：功能模型「标题生成」卡同形——卡头 + 三行值行（无图标、无双键）：
// 模型行点按开选择半模态、思考强度行点按开官方菜单、提示词行点按进提示词页；原提示词分区
// 卡并入本卡。提示词摘要与返回重拉自持在本件（宿主不持 prompt 状态、父侧零镜像），绑定
// 显示名经 onModelLabelChange 上行喂 chip。
// ★ 为何独立成件（宪法反碎片下限①「职责缝」+ 1200 硬线）：AssistantEditPage 越硬线，本域
// 自带半模态状态机 / 三件绑定态 / DB 写链，是天然缝；组件形态而非值参 @Builder（坑16 家族：
// 值参快照不刷新）。同族先例 = AssistantCredentialsCard / CodeHttpHostsCard。
// · 选择模型 = ModelPickerSheet 半模态（与对话页同机制；打勾经 selProviderId 直传绑定值，
//   不读写全局 ACTIVE 两键）——选中即落库（updateAssistantModelBinding）并收面板；换模型后
//   档位合法性守卫（legalThinkingTier 单一源）：新绑定下非法档位（off 禁域 / 选项集收窄外）
//   → thinkLevel 归 ''。
// · 思考强度 = 行内原生 bindMenu（共享 SettingThinkingRow + ThinkingMenu，与会话页思考强度
//   控制同机制——无显隐状态，关后可再开）；选项集 thinkingOptionsFor 按绑定服务商 + 模型
//   派生，「关闭」项按 supportsThinkingOff 显隐；未绑定态行点按 toast「请先选择模型」，
//   不弹菜单。
// · 提示词行 = 摘要副行 + 状态值（只读 / 已设置 / 未设置），点按进 AssistantPromptPage；
//   子页 pop 带 result 后重查本助手行只刷 prompt。内置助手照常可进只读页。
// · 清删联动（级联 + 读侧兜底双保险）：删服务商 / 删模型 → ProviderDb 删除函数内清
//   assistants 绑定列（clearAssistantBindingByProvider/ByModel）；本件 reloadBinding 读侧行 /
//   服务商 / 模型任一缺失 → 显示「未选择」（窗口期兜底，不写库）。
// · 上行：绑定显示名变化经 onModelLabelChange 报给宿主（编辑页 chip 行消费；'' = 未选择）。
//   宿主不另查库——单源在本件。
// · 发送链（不变）：本卡绑定 = 发送链四级兜底第②级来源（会话页所选 > 助手绑定 > 全局默认
//   > 首个启用模型），解析细则见 ProviderDb.resolveActiveConnection 头注释。
// · 关闭-再开协调五件式（判据总表 = 断言 329 组）：@Watch 声明 + 在途守卫 + applyOpen 唯一
//   写 true + onSheetGone 补开 + 关闭单入口清意图先于写 false；bindSheet 手势路由
//   requestClose + 第四参 onSheetGone。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CARD_PANEL_WIDTH, cardBg, CARD_RADIUS } from '../../common/Theme';
import { THINKING_OPTIONS, supportsThinkingOff, legalThinkingTier, thinkingOptionsFor }
  from '../../common/providers/AiTypes';
import {
  ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  updateAssistantModelBinding, updateAssistantThinkLevel
} from '../../common/store/AssistantDb';
import { CONN_RESOLVE_TICK_KEY, ModelRow, ProviderRow, queryModels, queryProviders }
  from '../../common/store/ProviderDb';
import { ROUTE_ASSISTANT_PROMPT_PAGE } from '../../common/RouteNames';
import { ModelPickerSheet } from '../chat/ModelPickerSheet';
import { sheetPanelOptions, DETENTS_FULL } from '../chat/KimiSheetCommon';
import {
  FunctionalCardHeader, SettingThinkingRow, SettingValueRow
} from '../settings/FunctionalSettingRows';

@Component
export struct AssistantModelCard {
  // 归属助手 id（宿主编辑页的 rowId）
  assistantId: string = '';
  // 宿主共享 NavPathStack（提示词页 push 用）
  pathStack: NavPathStack = new NavPathStack();
  // 宿主页底部安全区（选择模型半模态的 bottomInset——与旧页同参）
  bottomPad: number = 0;
  // 绑定显示名上行（宿主 chip 行消费；'' = 未选择）
  onModelLabelChange: (label: string) => void = (_label: string): void => {
  };
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 绑定态（@State——选择/档位落库后同步刷新卡面；providerId/modelId '' = 未绑定）
  @State private providerId: string = '';
  @State private modelId: string = '';
  @State private thinkLevel: string = '';
  // 绑定展示镜像：模型显示名（name 空兜底 modelId；@State 驱动显示区重建）
  @State private modelLabel: string = '';
  // 提示词原文（提示词行摘要与状态值；宿主不再持本状态——本件 aboutToAppear / 返回重拉）
  @State private prompt: string = '';
  // 绑定服务商 baseUrl（普通成员——offOk 判定入参，菜单每次弹出重建取当前值；无 UI 直渲染）
  private boundBaseUrl: string = '';
  // 绑定服务商协议/接口形态（思考菜单选项集派生入参；同 boundBaseUrl 普通成员，
  // resolveBoundDisplay 一并填充/清空）
  private boundProtocol: string = '';
  private boundEndpoint: string = '';
  // 模型选择半模态开关（坑64 姿势：声明式 bindSheet 挂本件根；本件在宿主页常驻，不因数据销毁）
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  // ── 关闭-再开协调（机制单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）──：关闭后
  // 离场动效在途期内再点「选择模型」，直接写 true 会被吞或被框架收尾回写压回——在途期只记
  // 开意图，等离场动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    this.reloadBinding();
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  // 绑定判定（交互守卫与显示共用）
  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  // 内置助手判定（默认——提示词只读；与 AssistantEditPage.isBuiltin 同口径）
  private isBuiltinAssistant(): boolean {
    return this.assistantId === ASSISTANT_DEFAULT_ID;
  }

  // 模型显示值（未绑定 = 「未选择」；绑定但显示名未解析 = modelId 兜底）
  private modelDisplayText(): string {
    if (!this.bound()) {
      return '未选择';
    }
    return this.modelLabel !== '' ? this.modelLabel : this.modelId;
  }

  private modelDisplayMuted(): boolean {
    return !this.bound();
  }

  // 提示词行副标题：内置助手明示来源——默认助手 = 与系统提示词恒同步；用户助手 = 内容单行
  // 省略 / 空时未设置明示（发送时用系统提示词）。文案受「面向用户文案写作规约」约束。
  private promptSummary(): string {
    if (this.assistantId === ASSISTANT_DEFAULT_ID) {
      return '与系统提示词恒同步';
    }
    const prompt: string = this.prompt.trim();
    return prompt !== '' ? prompt : '未设置，发送时用系统提示词';
  }

  // 提示词行右侧状态值（内置只读；用户助手按是否已配置）
  private promptValue(): string {
    if (this.isBuiltinAssistant()) {
      return '只读';
    }
    return this.prompt.trim() !== '' ? '已设置' : '未设置';
  }

  // 只读与未设置态走灰字，已设置走正色（与值行口径一致）
  private promptValueMuted(): boolean {
    return this.isBuiltinAssistant() || this.prompt.trim() === '';
  }

  // 思考菜单选项集派生：画像行收窄集或全量缺省（thinkingOptionsFor 经 AiTypes 门面）；
  // 未绑定 = 全量（菜单仅绑定态挂载，无实际消费）
  private menuOptions(): string[] {
    if (!this.bound()) {
      return THINKING_OPTIONS;
    }
    return thinkingOptionsFor(this.boundProtocol, this.boundEndpoint, this.boundBaseUrl, this.modelId);
  }

  // 上行绑定显示名（单源在本件——宿主不另查库；'' = 未选择）
  private reportLabel(): void {
    if (this.departed) {
      return;
    }
    this.onModelLabelChange(this.modelLabel);
  }

  // 重读绑定行（DB 单一真源；读侧兜底 = 行/服务商/模型任一缺失显示未选择——级联清列后的
  // 窗口期不写库）
  private async reloadBinding(): Promise<void> {
    let row: AssistantRow | null = null;
    try {
      row = await queryAssistant(this.assistantId);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
      return;
    }
    if (row === null) {
      // 宿主页负责「助手不存在即弹回」——本件只兜底停显，不重复退栈
      return;
    }
    this.providerId = row.providerId;
    this.modelId = row.modelId;
    this.thinkLevel = row.thinkLevel;
    this.prompt = row.prompt;
    if (this.bound()) {
      try {
        const resolved: boolean = await this.resolveBoundDisplay();
        if (this.departed) {
          return;
        }
        // 非抛失败（服务商行缺失）与抛异常同口径早退——读画像不完整就归一落库会把合法档位
        // 误归一默认，保持 DB 行真值显示不写库（窗口期不写库口径）
        if (!resolved) {
          return;
        }
      } catch (e) {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '绑定信息读取失败：' + (e as Error).message });
        // 读画像失败即早退：resolveBoundDisplay 开头已清 bound*，继续向下会拿空画像归一档位
        // 并落库，可能把合法档位误归一默认
        return;
      }
      // 档位合法性归一：画像升级后存量 thinkLevel 可能非法（如 kimi-k3 旧存 off）——归默认
      // 并落库，与 onPickModel 守卫同律（legalThinkingTier 单一源）
      const legal: string = legalThinkingTier(this.thinkLevel,
        supportsThinkingOff(this.boundBaseUrl, this.modelId), this.menuOptions());
      if (legal !== this.thinkLevel) {
        try {
          await updateAssistantThinkLevel(this.assistantId, legal);
          if (this.departed) {
            return;
          }
          this.thinkLevel = legal;
        } catch (e) {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '思考强度修正失败：' + (e as Error).message });
        }
      }
    }
    this.reportLabel();
  }

  // 绑定展示解析（providerId/modelId → 服务商 baseUrl + 模型显示名；服务商/模型行缺失 =
  // 保留空显示——清删窗口期兜底）。返回解析是否成功（服务商行缺失回 false 而非抛，调用方
  // 据此跳过归一守卫，窗口期不写库口径全路径成立）
  private async resolveBoundDisplay(): Promise<boolean> {
    this.boundBaseUrl = '';
    this.boundProtocol = '';
    this.boundEndpoint = '';
    this.modelLabel = '';
    const providers: ProviderRow[] = await queryProviders();
    if (this.departed) {
      return false;
    }
    const provider: ProviderRow | undefined =
      providers.find((p: ProviderRow): boolean => p.id === this.providerId);
    if (provider === undefined) {
      return false;
    }
    this.boundBaseUrl = provider.baseUrl;
    this.boundProtocol = provider.protocol;
    this.boundEndpoint = provider.endpoint;
    const models: ModelRow[] = await queryModels(provider.id, 'chat');
    if (this.departed) {
      return false;
    }
    const model: ModelRow | undefined =
      models.find((m: ModelRow): boolean => m.modelId === this.modelId);
    if (model !== undefined) {
      this.modelLabel = model.name !== '' ? model.name : model.modelId;
    }
    return true;
  }

  // 选择模型落库（半模态 onPick）：绑定写库 → 广播解析输入变化 → 展示解析 → 档位守卫 →
  // 收面板；任一失败 toast 不静默（P0-1），面板保持打开
  private async onPickModel(providerId: string, modelId: string): Promise<void> {
    try {
      await updateAssistantModelBinding(this.assistantId, providerId, modelId);
      if (this.departed) {
        return;
      }
      // 广播解析输入变化（改绑后已开着的会话页 @Watch 重解析——否则切回直接发送仍走旧 conn 缓存）
      AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
        (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
      this.providerId = providerId;
      this.modelId = modelId;
      // 解析失败（服务商行缺失非抛路径）跳过归一守卫——绑定本身已落库、面板照常收，档位
      // 保持原值待下次正常进页再守卫（窗口期不写库口径）
      if (await this.resolveBoundDisplay()) {
        const legal: string = legalThinkingTier(this.thinkLevel,
          supportsThinkingOff(this.boundBaseUrl, this.modelId), this.menuOptions());
        if (legal !== this.thinkLevel) {
          await updateAssistantThinkLevel(this.assistantId, legal);
          if (this.departed) {
            return;
          }
          this.thinkLevel = legal;
        }
      }
      if (this.departed) {
        return;
      }
      this.reportLabel();
      this.requestClose();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '模型绑定保存失败：' + (e as Error).message });
    }
  }

  // 关闭-再开协调（机制见字段注释）：开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口）
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
    this.sheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；
  // 用户关闭必经 requestClose（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 绑定落库收面板三路同调）：先清开意图 + 置离场动效在途位，
  // 再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // 思考档位落库（菜单 onPick；即时生效不经保存键）。★ 先写显示值再落库——菜单勾选与行值
  // 在点击当刻即用新档（失败再回滚 + toast），避免异步窗口内重开菜单仍显示旧勾选
  private onPickThinking(option: string): void {
    const previous: string = this.thinkLevel;
    this.thinkLevel = option;
    updateAssistantThinkLevel(this.assistantId, option)
      .then((): void => {
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.thinkLevel = previous;
        this.getUIContext().getPromptAction().showToast({ message: '思考强度保存失败：' + (e as Error).message });
      });
  }

  // 提示词页跳转：onPop 重拉本助手行只刷 prompt（子页 pop 必带 result，坑17 契约）；
  // 刷新失败 toast 不静默
  private openPromptPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_PROMPT_PAGE, this.assistantId, (): void => {
      queryAssistant(this.assistantId)
        .then((row: AssistantRow | null): void => {
          if (this.departed || row === null) {
            return;
          }
          this.prompt = row.prompt;
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '提示词摘要刷新失败：' + (e as Error).message });
        });
    });
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
        this.requestClose();
      },
      bottomInset: this.bottomPad
    })
  }

  build() {
    // 卡体 = 功能模型「标题生成」卡同形组卡（决明指令）：卡头 + 三行值行，无图标、无双键
    //——行本身即入口（模型 = 半模态 / 思考强度 = 官方菜单 / 提示词 = 二级页）
    Column({ space: 12 }) {
      FunctionalCardHeader({
        title: '模型与提示词',
        hint: '模型未选择时跟随全局默认。思考强度按所选模型支持的档位提供。提示词用于当前助手的对话。'
      })
      Column() {
        // 模型行（tap = 选择模型半模态；未选择灰字）
        SettingValueRow({
          label: '模型',
          subtitle: '用于当前助手的对话',
          value: this.modelDisplayText(),
          valueMuted: this.modelDisplayMuted(),
          dividerTop: false,
          onTap: (): void => {
            this.requestOpen();
          }
        })
        // 思考强度行（绑定态 = 原生 bindMenu；未绑定态 = 值行 + 指引 toast）
        if (this.bound()) {
          SettingThinkingRow({
            label: '思考强度',
            subtitle: '控制思考深度，仅部分模型支持',
            value: $thinkLevel,
            options: this.menuOptions(),
            offOk: supportsThinkingOff(this.boundBaseUrl, this.modelId),
            dividerTop: true,
            onPick: (option: string): void => {
              this.onPickThinking(option);
            }
          })
        } else {
          SettingValueRow({
            label: '思考强度',
            subtitle: '控制思考深度，仅部分模型支持',
            value: '未选择',
            valueMuted: true,
            dividerTop: true,
            onTap: (): void => {
              this.getUIContext().getPromptAction().showToast({ message: '请先选择模型' });
            }
          })
        }
        // 提示词行（摘要副行 + 状态值，点按进提示词页）
        SettingValueRow({
          label: '提示词',
          subtitle: this.promptSummary(),
          value: this.promptValue(),
          valueMuted: this.promptValueMuted(),
          dividerTop: true,
          onTap: (): void => {
            this.openPromptPage();
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding({ top: 16, bottom: 4 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    // 选择模型半模态（坑64 姿势；档位 = DETENTS_FULL 全屏单挡位——决明指令；关闭链统一 +
    // 关闭-再开协调见字段注释）
    .bindSheet($$this.sheetShow, this.SheetHost(), sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      }, DETENTS_FULL, undefined,
      (): void => {
        this.onSheetGone();
      }))
  }
}
