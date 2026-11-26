// 记忆提取卡：卡头 = 标题 + ⓘ；三行 = 模型 / 提示词 / 导入提示词（无箭头）。
// 两键未配置 = 不整理（不回退标题模型）；导入整理与自动整理共用模型两键，
// 但提示词独立成槽（输入域不同：外部平台文本 vs 本库会话记录）。
// 自持有读取：模型两键 @StorageProp 订阅即刷，父侧零镜像零回调。
import { SETTING_TITLE_MEMORY_MODEL } from '../../common/SettingSearch';
import { MEMORY_MODEL_KEY, MEMORY_PROVIDER_KEY } from '../../common/MemoryGen';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import { FunctionalCardHeader, PromptSettingRow, SettingValueRow } from './FunctionalSettingRows';

@Component
export struct MemoryModelCard {
  private departed: boolean = false;
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  @StorageProp(MEMORY_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(MEMORY_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
  @State private modelLabel: string = '';
  @State private missing: boolean = false;

  aboutToAppear(): void {
    this.reloadDisplay();
  }

  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  private displayText(): string {
    return this.bound() && !this.missing ?
      (this.modelLabel !== '' ? this.modelLabel : this.modelId) : '未选择';
  }

  private displayMuted(): boolean {
    return !(this.bound() && !this.missing);
  }

  private reloadDisplay(): void {
    this.modelLabel = '';
    this.missing = false;
    if (!this.bound()) {
      return;
    }
    resolveModelDisplayLabel(this.providerId, this.modelId)
      .then((state: ModelDisplayLabel): void => {
        if (this.departed) {
          return;
        }
        this.modelLabel = state.label;
        this.missing = state.missing;
      })
      .catch((_e: Object): void => {
        if (this.departed) {
          return;
        }
        this.modelLabel = this.modelId;
      });
  }

  build() {
    Column({ space: 12 }) {
      FunctionalCardHeader({
        title: SETTING_TITLE_MEMORY_MODEL,
        hint: '选择模型后，退出会话时自动整理使用该模型。未选择时不整理。'
      })
      Column() {
        SettingValueRow({
          label: '模型',
          subtitle: '退出会话时自动整理',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: false,
          onTap: (): void => {
            this.onOpenModelSheet('memoryModel');
          }
        })
        PromptSettingRow({
          slotKind: 'memoryPrompt',
          label: '提示词',
          subtitle: '控制记忆提取规则',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('memoryPrompt');
          }
        })
        PromptSettingRow({
          slotKind: 'memoryImportPrompt',
          label: '导入提示词',
          subtitle: '用于整理导入内容',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('memoryImportPrompt');
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
