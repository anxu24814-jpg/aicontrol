// 记忆优化卡：卡头 = 标题 + ⓘ；两行 = 模型 / 提示词（无箭头）。
// 对库内已有记忆做去重与改写；两键未配置 = 不优化（不回退提取模型）。
// 自持有读取：模型两键 @StorageProp 订阅即刷，父侧零镜像零回调。
import { SETTING_TITLE_MEMORY_OPT_MODEL } from '../../common/SettingSearch';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROVIDER_KEY } from '../../common/MemoryOpt';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import { FunctionalCardHeader, PromptSettingRow, SettingValueRow } from './FunctionalSettingRows';

@Component
export struct MemoryOptModelCard {
  private departed: boolean = false;
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  @StorageProp(MEMORY_OPT_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(MEMORY_OPT_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
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
        title: SETTING_TITLE_MEMORY_OPT_MODEL,
        hint: '选择模型后，可在记忆页对已有记忆做去重与改写。未选择时不能优化。'
      })
      Column() {
        SettingValueRow({
          label: '模型',
          subtitle: '用于优化已有记忆',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: false,
          onTap: (): void => {
            this.onOpenModelSheet('memoryOptModel');
          }
        })
        PromptSettingRow({
          slotKind: 'memoryOptPrompt',
          label: '提示词',
          subtitle: '控制记忆优化规则',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('memoryOptPrompt');
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
