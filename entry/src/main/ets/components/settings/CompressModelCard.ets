// 上下文压缩卡：卡头 = 标题 + ⓘ；两行 = 模型 / 提示词（无箭头，说明并入 ⓘ 与行副标题）。
// 语义差异保留：模型两键未配置 = 回退当前会话的模型（不是「未启用不压缩」）——
// 未配置时模型行显示「跟随当前会话」而不是「未选择」。
// 自持有读取：两键 @StorageProp 订阅即刷，父侧零镜像零回调。
import { SETTING_TITLE_COMPRESS } from '../../common/SettingSearch';
import { COMPRESS_MODEL_KEY, COMPRESS_PROVIDER_KEY } from '../../common/CompressGen';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import { FunctionalCardHeader, PromptSettingRow, SettingValueRow } from './FunctionalSettingRows';

@Component
export struct CompressModelCard {
  private departed: boolean = false;
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  @StorageProp(COMPRESS_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(COMPRESS_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
  @State private modelLabel: string = '';
  @State private missing: boolean = false;

  aboutToAppear(): void {
    this.reloadDisplay();
  }

  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  // 未配置 = 跟随当前会话（本槽回退语义）；已配置但指向行已删 = 未选择
  private displayText(): string {
    if (!this.bound()) {
      return '跟随当前会话';
    }
    if (this.missing) {
      return '未选择';
    }
    return this.modelLabel !== '' ? this.modelLabel : this.modelId;
  }

  private displayMuted(): boolean {
    return !this.bound() || this.missing;
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
        title: SETTING_TITLE_COMPRESS,
        hint: '会话页的上下文用量面板里手动压缩上下文。压缩由模型整理成交接摘要，之后的请求只带摘要和最近几轮原文。压缩消耗计入用量统计。'
      })
      Column() {
        SettingValueRow({
          label: '模型',
          subtitle: '未选时跟随会话',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: false,
          onTap: (): void => {
            this.onOpenModelSheet('compressModel');
          }
        })
        PromptSettingRow({
          slotKind: 'compressPrompt',
          label: '提示词',
          subtitle: '控制压缩摘要写法',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('compressPrompt');
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
