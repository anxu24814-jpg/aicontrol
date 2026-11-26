// 推荐问题卡：卡头 = 标题 + ⓘ；三行 = 启用开关 / 模型 / 提示词（无箭头，值即入口）。
// 卡内说明小字并入 ⓘ；未选择不生成。
// 自持有读取（坑16 正解——本卡居 PageShell.content 内）：三键 @StorageProp 订阅即刷，
// 父侧零镜像零回调；模型显示名解析走共用件 ModelDisplayLabel。
import { SETTING_TITLE_SUGGEST } from '../../common/SettingSearch';
import { SUGGEST_ENABLED_KEY, SUGGEST_MODEL_KEY, SUGGEST_PROVIDER_KEY } from '../../common/store/ProviderDb';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import {
  FunctionalCardHeader, PromptSettingRow, SettingSwitchRow, SettingValueRow
} from './FunctionalSettingRows';

@Component
export struct SuggestModelCard {
  private departed: boolean = false;
  // 面板打开意图（kind = 宿主 sheetKind；本卡只发意图，面板装配全在宿主）
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  // 总开关（默认关——决策 1）；Toggle 可点自切换 = 唯一控制面
  @StorageProp(SUGGEST_ENABLED_KEY) switchOn: boolean = false;
  @StorageProp(SUGGEST_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(SUGGEST_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
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
        title: SETTING_TITLE_SUGGEST,
        hint: '开启后 AI 回复下方显示推荐问题，每次回复完成后生成一次，消耗计入用量统计。选择用于生成的模型，未选择则不生成。'
      })
      Column() {
        SettingSwitchRow({
          label: '启用推荐问题',
          subtitle: '回复后展示推荐',
          isOn: this.switchOn,
          dividerTop: false,
          onToggle: (isOn: boolean): void => {
            AppStorage.setOrCreate<boolean>(SUGGEST_ENABLED_KEY, isOn);
          }
        })
        SettingValueRow({
          label: '模型',
          subtitle: '用于生成推荐问题',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: true,
          onTap: (): void => {
            this.onOpenModelSheet('suggestModel');
          }
        })
        PromptSettingRow({
          slotKind: 'suggestPrompt',
          label: '提示词',
          subtitle: '控制推荐问题风格',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('suggestPrompt');
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
