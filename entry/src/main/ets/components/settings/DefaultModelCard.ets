// 默认对话卡：卡头 = 标题 + ⓘ；单行「模型 + 当前值」（整行可点、无箭头）——点击经宿主
// openSheet('model') 开共用 ModelPickerSheet。默认对话 = 发送链四级兜底第③级来源
//（DEFAULT_PROVIDER_KEY / DEFAULT_MODEL_KEY 两持久键，选完即时生效；未选 = 未选择灰字）。
// 自持有读取（坑16 正解——本卡居 PageShell.content 内）：两键 @StorageProp 订阅即刷，
// 显示名解析自持，父侧零镜像零回调。
import { SETTING_TITLE_DEFAULT_MODEL } from '../../common/SettingSearch';
import { DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY } from '../../common/store/ProviderDb';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import { FunctionalCardHeader, SettingValueRow } from './FunctionalSettingRows';

@Component
export struct DefaultModelCard {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI
  private departed: boolean = false;
  // 模型选择面板打开意图（kind = 宿主 sheetKind；卡只知道自己的落点）
  onOpenModelSheet: (kind: string) => void = () => {
  };
  @StorageProp(DEFAULT_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(DEFAULT_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
  // 显示名镜像 + 指向行已删标记（missing 窗口期显示「未选择」但不清两键——
  // 半模态打勾仍需原值；两键真源在 AppStorage，本处不持副本）
  @State private modelLabel: string = '';
  @State private missing: boolean = false;

  aboutToAppear(): void {
    this.reloadDisplay();
  }

  // 已配置判定（两键齐 = 已设置）
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

  // 显示名解析（共用件；查询失败静默兜底 modelId——键值仍在，不阻断卡面）
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
      // 卡头：标题 + 右上角 ⓘ（说明收气泡，卡面只留当前值一行）
      FunctionalCardHeader({
        title: SETTING_TITLE_DEFAULT_MODEL,
        hint: '会话页未选择模型且所属助手未绑定模型时，发送时自动使用此默认模型。'
      })
      Column() {
        SettingValueRow({
          label: '模型',
          subtitle: '会话未绑定时使用',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: false,
          onTap: (): void => {
            this.onOpenModelSheet('model');
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
