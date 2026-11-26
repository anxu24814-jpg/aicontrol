// 标题生成卡：卡头 = 标题 + ⓘ；行 = 启用开关 / DeepSeek 官方标题三档（仅总开关打开时显示）/
// 模型 / 提示词（无箭头，值即入口）。
// 开启并选择模型后自动为新会话生成标题；关闭或未选择 = 零请求（TitleGen 守卫序），
// 关闭不隐藏模型与提示词行（先配好再开合法）。标题模型不进会话连接解析链，选择不广播 tick。
// 自持有读取：三键 @StorageProp 订阅即刷，父侧零镜像零回调。
import { SETTING_TITLE_TITLE_MODEL } from '../../common/SettingSearch';
import { TITLE_ENABLED_KEY, TITLE_MODEL_KEY, TITLE_PROVIDER_KEY } from '../../common/store/ProviderDb';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import {
  FunctionalCardHeader, PromptSettingRow, SettingMenuRow, SettingSwitchRow, SettingValueRow
} from './FunctionalSettingRows';
// 二期 #4：DeepSeek 官方标题三态键（入口在本卡，会话设置面板不加——决明 2026-11-14 拍板）
import {
  DS_TITLE_MODE_EVERY, DS_TITLE_MODE_FIRST, DS_TITLE_MODE_OFF, PREF_DS_TITLE_MODE_KEY
} from '../../common/AppPreferences';

@Component
export struct TitleModelCard {
  private departed: boolean = false;
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  // 总开关（缺省 true；关 = 生成链守卫序最前早退零请求，两键配置保留）
  @StorageProp(TITLE_ENABLED_KEY) titleEnabled: boolean = true;
  @StorageProp(TITLE_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(TITLE_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
  // DeepSeek 官方标题档位（缺省 'first' 真源在 EntryAbility persistProp 注册侧；本行只在
  // 标题总开关打开时渲染——标题都不生成，档位无意义）
  @StorageLink(PREF_DS_TITLE_MODE_KEY) dsTitleMode: string = DS_TITLE_MODE_FIRST;
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
        title: SETTING_TITLE_TITLE_MODEL,
        hint: '开启并选择模型后，自动为新会话生成标题。关闭开关或未选择模型时不生成。'
      })
      Column() {
        SettingSwitchRow({
          label: '启用标题生成',
          subtitle: '自动生成会话标题',
          isOn: this.titleEnabled,
          dividerTop: false,
          onToggle: (isOn: boolean): void => {
            AppStorage.setOrCreate<boolean>(TITLE_ENABLED_KEY, isOn);
          }
        })
        if (this.titleEnabled) {
          // 三档值行（照 SettingMenuRow 形制：值行点击弹菜单、勾在右、键含勾选态已在件内）；
          // 副标题写明只对 DS 官方模型会话生效——本行是设置页全局项，非 DS 会话也可见
          SettingMenuRow({
            label: 'DeepSeek 官方标题',
            subtitle: '仅对 DeepSeek 官方模型会话生效',
            value: this.dsTitleMode,
            options: [DS_TITLE_MODE_OFF, DS_TITLE_MODE_FIRST, DS_TITLE_MODE_EVERY],
            optionLabels: ['不使用', '仅首轮', '每轮'],
            dividerTop: true,
            onPick: (option: string): void => {
              this.dsTitleMode = option;
            }
          })
        }
        SettingValueRow({
          label: '模型',
          subtitle: '用于生成会话标题',
          value: this.displayText(),
          valueMuted: this.displayMuted(),
          dividerTop: true,
          onTap: (): void => {
            this.onOpenModelSheet('titleModel');
          }
        })
        PromptSettingRow({
          slotKind: 'prompt',
          label: '提示词',
          subtitle: '控制标题风格',
          dividerTop: true,
          onTap: (): void => {
            this.onOpenPromptSheet('prompt');
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
