// 命令审批卡：卡头 = 标题 + ⓘ；三行 = 启用开关 / 模型 / 提示词（无箭头，说明并入 ⓘ 与行副标题）。
// 开启并配置模型后写操作先由审批模型审核；关闭或未选择 = 审批闸早退，照旧弹人工卡（fail-closed）。
// 关闭不隐藏模型与提示词行（先配好再开合法）。
// 自持有读取：总开关与模型两键 @StorageProp 订阅即刷，父侧零镜像零回调。
import { SETTING_TITLE_APPROVAL } from '../../common/SettingSearch';
import {
  APPROVAL_ENABLED_KEY, APPROVAL_MODEL_KEY, APPROVAL_PROVIDER_KEY
} from '../../common/store/ProviderDb';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import {
  FunctionalCardHeader, PromptSettingRow, SettingSwitchRow, SettingValueRow
} from './FunctionalSettingRows';

@Component
export struct ApprovalModelCard {
  private departed: boolean = false;
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  // 总开关（缺省 true = 存量零行为变化）
  @StorageProp(APPROVAL_ENABLED_KEY) approvalOn: boolean = true;
  @StorageProp(APPROVAL_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(APPROVAL_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
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
        title: SETTING_TITLE_APPROVAL,
        hint: '开启并配置模型后，助手改动数据的操作先由审批模型审核，通过即执行，不通过则拒绝。删除等高风险操作审核后仍会征求你的同意，除非本次会话在聊天页切到高效档。关闭或未选择模型时照旧弹卡确认。本配置是标准档的执行器设置，谨慎档与高效档不走审批闸。'
      })
      Column() {
        SettingSwitchRow({
          label: '启用命令审批',
          subtitle: '自动审核写操作',
          isOn: this.approvalOn,
          dividerTop: false,
          onToggle: (isOn: boolean): void => {
            AppStorage.setOrCreate<boolean>(APPROVAL_ENABLED_KEY, isOn);
          }
        })
        SettingValueRow({
          label: '模型',
          subtitle: '用于审核工具调用',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: true,
          onTap: (): void => {
            this.onOpenModelSheet('approvalModel');
          }
        })
        PromptSettingRow({
          slotKind: 'approvalPrompt',
          label: '提示词',
          subtitle: '控制审批规则',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('approvalPrompt');
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
