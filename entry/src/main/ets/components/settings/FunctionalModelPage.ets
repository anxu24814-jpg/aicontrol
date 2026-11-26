// 功能模型页宿主：九张功能卡 = 功能一张卡、卡内属性行、无箭头。本页只留宿主职责——卡壳
// （CARD_PANEL_WIDTH + CARD_RADIUS + cardBg + 上下 16/4 padding）与卡序、选择模型 / 提示词
// 编辑两面板的单面板多形态（sheetKind）、选择落键、提示词保存/恢复/脏态关闭确认、关闭-再开
// 协调；**零模型镜像、零显示名解析、零逐卡 reload**（九卡自持 AppStorage 读取）。
// 行形制单源 = FunctionalSettingRows.ets；模型显示名解析单源 = ModelDisplayLabel.ets。
// ★ 提示词槽三处联动铁律（新增槽必须同笔改三处，任一漏改都能编译通过）：①PromptSlotSpec.ets
//   规格表加分支（漏 = 编辑保存写到标题提示词键）；②本页 sheetKind 值域注释；③isPromptSheet()
//   加项（漏 = 面板不渲染）；58/69 组按「分支段逐字段对表」守。
// ★ 半模态关闭链：可见性 `$$` 双向 + sheetKind 恒不复位；关闭-再开协调 = sheetClosing /
//   pendingOpen（动效在途只记开意图，第四参 onDisappear 补开，@Watch 兜底）；closePanel 单入口。
//   onWillDismiss 按 isPromptSheet() 分流——一刀切会让选择模型也弹确认（功能回归）。
// ★ 选择落键（onPickModel）：sheetKind → 模型两键单源映射（modelKeysOf）；默认对话写入后广播
//   CONN_RESOLVE_TICK_KEY；文字识别选中后翻引擎到视觉模型。各卡 @StorageProp 自刷，本页不 reload。
// ★ 提示词卡面「默认 / 已自定义」：保存/恢复默认后 bumpPromptStateEpoch()，行 @StorageProp 即刷。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_FUNCTIONAL_MODEL } from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, CARD_RADIUS } from '../../common/Theme';
import { ModelPickerSheet } from '../chat/ModelPickerSheet';
import { confirmSheetClose, sheetPanelOptions, DETENTS_FULL } from '../chat/KimiSheetCommon';
import { PromptSlot, bumpPromptStateEpoch, effectivePromptOf, resolvePromptSlot } from './PromptSlotSpec';
import { PromptSlotSheet } from './PromptSlotSheet';
import { DefaultModelCard } from './DefaultModelCard';
import { TitleModelCard } from './TitleModelCard';
import { SuggestModelCard } from './SuggestModelCard';
import { CompressModelCard } from './CompressModelCard';
import { MemoryModelCard } from './MemoryModelCard';
import { MemoryOptModelCard } from './MemoryOptModelCard';
import { OcrModelCard } from './OcrModelCard';
import { ApprovalModelCard } from './ApprovalModelCard';
import { FunctionalThinkingCard } from './FunctionalThinkingCard';
import {
  APPROVAL_MODEL_KEY, APPROVAL_PROVIDER_KEY, CONN_RESOLVE_TICK_KEY, DEFAULT_MODEL_KEY,
  DEFAULT_PROVIDER_KEY, OCR_ENGINE_KEY, OCR_ENGINE_MODEL, OCR_MODEL_KEY, OCR_PROVIDER_KEY,
  SUGGEST_MODEL_KEY, SUGGEST_PROVIDER_KEY, TITLE_MODEL_KEY, TITLE_PROVIDER_KEY
} from '../../common/store/ProviderDb';
import { MEMORY_MODEL_KEY, MEMORY_PROVIDER_KEY } from '../../common/MemoryGen';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROVIDER_KEY } from '../../common/MemoryOpt';
import { COMPRESS_MODEL_KEY, COMPRESS_PROVIDER_KEY } from '../../common/CompressGen';

// 模型两键对（选择落键与半模态打勾源共用；单源防「打勾源与落键键不同」）
interface ModelKeyPair {
  providerKey: string;
  modelKey: string;
}

// sheetKind → 模型两键（唯一映射；未知 kind 返回 undefined = 不写键，P0-1 防御）
function modelKeysOf(sheetKind: string): ModelKeyPair | undefined {
  if (sheetKind === 'model') {
    return { providerKey: DEFAULT_PROVIDER_KEY, modelKey: DEFAULT_MODEL_KEY };
  }
  if (sheetKind === 'titleModel') {
    return { providerKey: TITLE_PROVIDER_KEY, modelKey: TITLE_MODEL_KEY };
  }
  if (sheetKind === 'memoryModel') {
    return { providerKey: MEMORY_PROVIDER_KEY, modelKey: MEMORY_MODEL_KEY };
  }
  if (sheetKind === 'memoryOptModel') {
    return { providerKey: MEMORY_OPT_PROVIDER_KEY, modelKey: MEMORY_OPT_MODEL_KEY };
  }
  if (sheetKind === 'ocrModel') {
    return { providerKey: OCR_PROVIDER_KEY, modelKey: OCR_MODEL_KEY };
  }
  if (sheetKind === 'suggestModel') {
    return { providerKey: SUGGEST_PROVIDER_KEY, modelKey: SUGGEST_MODEL_KEY };
  }
  if (sheetKind === 'compressModel') {
    return { providerKey: COMPRESS_PROVIDER_KEY, modelKey: COMPRESS_MODEL_KEY };
  }
  if (sheetKind === 'approvalModel') {
    return { providerKey: APPROVAL_PROVIDER_KEY, modelKey: APPROVAL_MODEL_KEY };
  }
  return undefined;
}

@Component
export struct FunctionalModelPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 半模态面板开关（坑64：声明式 bindSheet 挂页面根）。值域 = 'none' 关 / 八个模型站
  //（'model' 默认对话、'titleModel'、'memoryModel'、'memoryOptModel'、'ocrModel'、
  // 'suggestModel'、'compressModel'、'approvalModel'）+ 八个提示词槽（'prompt'、
  // 'memoryPrompt'、'memoryOptPrompt'、'memoryImportPrompt'、'ocrPrompt'、'suggestPrompt'、
  // 'compressPrompt'、'approvalPrompt'）。★ 铁律：新增槽必须同步 isPromptSheet() 与本注释
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  @State private sheetKind: string = 'none';
  // 提示词编辑镜像（打开时播种该槽生效模板；保存 / 恢复默认后回显）
  @State private promptContent: string = '';
  // ── 关闭-再开协调（机制单源 = KimiSheetCommon.sheetPanelOptions 第四参注释；字段注释见 sheetClosing）──
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 选择落键（半模态 onPick 单入口）：两键按 sheetKind 映射写入——各卡 @StorageProp 自刷
  private onPickModel(providerId: string, modelId: string): void {
    const keys: ModelKeyPair | undefined = modelKeysOf(this.sheetKind);
    if (keys === undefined) {
      this.closePanel();
      return;
    }
    AppStorage.setOrCreate<string>(keys.providerKey, providerId);
    AppStorage.setOrCreate<string>(keys.modelKey, modelId);
    if (this.sheetKind === 'model') {
      // 广播解析输入变化（已开会话页 @Watch 重解析，否则切回直接发送仍走旧 conn 缓存）
      AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
        (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
    }
    if (this.sheetKind === 'ocrModel') {
      // 选模型 = 用它——否则「选了却没生效」只能靠用户再切段位
      AppStorage.setOrCreate<string>(OCR_ENGINE_KEY, OCR_ENGINE_MODEL);
    }
    this.closePanel();
  }

  // 半模态打勾源（现读持久键——各卡自持显示名，父侧不持副本）
  private pickerProviderId(): string {
    const keys: ModelKeyPair | undefined = modelKeysOf(this.sheetKind);
    return keys === undefined ? '' : (AppStorage.get<string>(keys.providerKey) ?? '');
  }

  private pickerModelId(): string {
    const keys: ModelKeyPair | undefined = modelKeysOf(this.sheetKind);
    return keys === undefined ? '' : (AppStorage.get<string>(keys.modelKey) ?? '');
  }

  // 保存提示词（八槽同形：校验必保留占位符；写各自定制键，各链现读即生效；记忆提取槽不校
  // {maxItems}——缺失 = 显式去掉条数约束；识别槽拦空串——写 '' 会静默变回内置）
  private savePrompt(): void {
    const slot: PromptSlot = resolvePromptSlot(this.sheetKind);
    const content: string = this.promptContent.trim();
    const missing: string[] = slot.requiredList
      .filter((p: string): boolean => !content.includes(p));
    if (missing.length > 0) {
      const message: string = slot.requiredList.length === 1 ? slot.missingTip :
        '提示词缺少占位符 ' + missing.join('、') + '，缺少时保存会被拦截';
      this.getUIContext().getPromptAction().showToast({ message: message });
      return;
    }
    if (content === '') {
      this.getUIContext().getPromptAction().showToast({ message: '提示词不能为空。可点恢复默认回到内置' });
      return;
    }
    AppStorage.setOrCreate<string>(slot.key, content);
    bumpPromptStateEpoch();
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    this.closePanel();
  }

  // 恢复内置默认（清定制键回 ''——清删式回退，内置模板后续升级自动跟随；编辑框回显内置）
  private restorePrompt(): void {
    const slot: PromptSlot = resolvePromptSlot(this.sheetKind);
    AppStorage.setOrCreate<string>(slot.key, '');
    bumpPromptStateEpoch();
    this.promptContent = slot.builtin;
    this.getUIContext().getPromptAction().showToast({ message: '已恢复为内置默认' });
  }

  // 面板开启单源（可见性 + 内容形态两写同点，防漏写一边；可见性走 requestOpen 协调）
  private openSheet(kind: string): void {
    this.sheetKind = kind;
    this.requestOpen();
  }

  // ── 关闭-再开协调（机制说明见字段注释；与会话轨迹页 / 请求日志页同配方）──
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

  // 离场动效结束（sheetPanelOptions 第四参）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写压回 false 时按开意图补开；用户关闭必经
  // closePanel（先清开意图），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 关闭放行单源（手势路带 action 先官方 dismiss；自绘键 / 程序化路直写可见性）。关闭恒不
  // 复位 sheetKind——内容形态随下次开启改写（关闭动画期内容树恒在）
  private closePanel(action?: DismissSheetAction): void {
    if (action !== undefined) {
      action.dismiss();
    }
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // 提示词编辑入口（播种值 = 该槽生效模板现读——漏播种会以空框编辑、保存即覆盖用户定制）
  private openPromptSlot(kind: string): void {
    this.promptContent = effectivePromptOf(kind);
    this.openSheet(kind);
  }

  // 关闭请求（标题栏关闭键与手势 / 系统返回都调本方法）。脏态 = 现读生效值比对（不用打开时
  // 快照——「恢复默认」会即时清定制键并回显内置）；未编辑直接关，编辑过先问一句，未通过 /
  // 异常一律不放行 = 面板保持打开。程序化关闭（保存键）不经本方法。
  private requestClosePrompt(action?: DismissSheetAction): void {
    if (this.promptContent.trim() === effectivePromptOf(this.sheetKind)) {
      this.closePanel(action);
      return;
    }
    confirmSheetClose(this.getUIContext(), {
      title: '放弃这次修改？',
      message: '放弃后不会保存，提示词保持原样',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃'
    }).then((approved: boolean): void => {
      if (this.departed) {
        return;
      }
      if (approved) {
        this.closePanel(action);
      }
    });
  }

  // 提示词编辑面板八态判定（SheetHost 分支条件 + 档位分发共用——两处同源防漂移）
  private isPromptSheet(): boolean {
    return this.sheetKind === 'prompt' || this.sheetKind === 'memoryPrompt' ||
      this.sheetKind === 'memoryOptPrompt' || this.sheetKind === 'memoryImportPrompt' ||
      this.sheetKind === 'ocrPrompt' || this.sheetKind === 'suggestPrompt' ||
      this.sheetKind === 'compressPrompt' || this.sheetKind === 'approvalPrompt';
  }

  @Builder
  Content() {
    Scroll() {
      // 卡间 CARD_SPACING 单源（本页无板块头、九卡平铺，全站卡间档统一 10——列表卡规范）
      Column({ space: CARD_SPACING }) {
        // ── 默认对话（单行：模型）──
        Column() {
          DefaultModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 功能思考档位（全局项，第二卡；单行弹菜单，菜单锚点 = 右侧档位值）──
        Column() {
          FunctionalThinkingCard()
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 标题生成（开关 / 模型 / 提示词）──
        Column() {
          TitleModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 推荐问题（开关 / 模型 / 提示词）──
        Column() {
          SuggestModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 上下文压缩（模型 / 提示词；未选 = 跟随当前会话）──
        Column() {
          CompressModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 记忆提取（模型 / 提示词 / 导入提示词）──
        Column() {
          MemoryModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 记忆优化（模型 / 提示词）──
        Column() {
          MemoryOptModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 文字识别（开关 / 引擎分段 / 模型 / 提示词——唯一保留内容卡控件的卡）──
        Column() {
          OcrModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // ── 命令审批（开关 / 模型 / 提示词）──
        Column() {
          ApprovalModelCard({
            onOpenModelSheet: (kind: string): void => {
              this.openSheet(kind);
            },
            onOpenPromptSheet: (kind: string): void => {
              this.openPromptSlot(kind);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
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
    .scrollBar(BarState.Off)
  }

  @Builder
  SheetHost() {
    if (this.isPromptSheet()) {
      PromptSlotSheet({
        sheetKind: this.sheetKind,
        promptContent: $promptContent,
        onRestore: (): void => {
          this.restorePrompt();
        },
        onSave: (): void => {
          this.savePrompt();
        },
        onRequestClose: (): void => {
          this.requestClosePrompt();
        }
      })
    } else {
      ModelPickerSheet({
        selProviderId: this.pickerProviderId(),
        selModelId: this.pickerModelId(),
        onPick: (providerId: string, modelId: string): void => {
          this.onPickModel(providerId, modelId);
        },
        onClose: (): void => {
          this.closePanel();
        },
        bottomInset: this.bottomPad
      })
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_FUNCTIONAL_MODEL,
      content: (): void => {
        this.Content();
      }
    })
      // 半模态（坑64 姿势）：模型选择 = DETENTS_FULL 全屏单挡位；提示词编辑保持官方默认
      // 双停靠 [MEDIUM, LARGE]。关闭按 isPromptSheet() 分流：提示词走脏态确认，模型选择恒放行
      .bindSheet($$this.sheetShow, this.SheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          if (this.isPromptSheet()) {
            this.requestClosePrompt(action);
            return;
          }
          this.closePanel(action);
        }, this.isPromptSheet() ? undefined : DETENTS_FULL, this.isPromptSheet(),
        (): void => {
          this.onSheetGone();
        }))
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
