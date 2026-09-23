// 推荐问题卡（2026-09-19 推荐问题功能，任务书-推荐问题-20260919 §7.5；同日自
// FunctionalModelPage 域级最小拆分独立成件——第六卡落位后该页剔头 1212 越 1200 硬线，
// 按宪法「硬线文件实质改动须先拆本功能域」条把本卡整域迁出，方法体原样搬迁）。
// 模型显示行（★ 2026-09-20 决明指令「模型名移至标题行下副标题处」，自开关行下方上移——未配
// = 「未选择」灰字，与同页五卡同槽同字号）+ 总开关行（Toggle 唯一控制面，默认关——决策 1）
// + 说明小字（按钮行上方，宪法「功能设置卡布局次序」条）+ 双键（「选择模型」主操作键
// primary 蓝底恒白字 + 「提示词」次钮，记忆两卡先例；卡壳由父侧统一 Column 包裹）。
// ★ 自持有读取（规范-数据存储获取刷新方案「卡片自持有读取」先例 + 坑16 正解——本卡居
// PageShell.content 内）：总开关与已选模型两键都是 AppStorage 持久键，@StorageProp @Watch
// 订阅即自刷（本卡 Toggle 落键、功能模型页选择落键、设置恢复备份三写点全部即时反映，
// 父侧零镜像零 reload 回调）；显示名解析自持（服务商行缺失 = missing「未选择」——与
// 父页 resolveModelDisplay 同口径但输出面不同：本卡不带服务商名，两实现各自成立不算重复）。
// ⓘ 说明 = 任务书定稿文案；未选择模型 = 开关开着也零请求（SuggestGen 守卫序）
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SETTING_TITLE_SUGGEST } from '../../common/SettingSearch';
import { cardDescColor, cardTitleColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';
import { SUGGEST_ENABLED_KEY, SUGGEST_MODEL_KEY, SUGGEST_PROVIDER_KEY,
  ModelRow, ProviderRow, queryModels, queryProviders } from '../../common/store/ProviderDb';

@Component
export struct SuggestModelCard {
  // 半模态打开回调（父侧 sheetKind 单面板多形态宿主——本卡只发意图，ModelPickerSheet 与
  // 提示词编辑面板的装配全在父侧；构造注入后不变，坑30 口径）
  onOpenModelSheet: () => void = () => {
  };
  onOpenPromptSheet: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感回退双态 + 分项档位（双键 fallbackButton* 四件套参数—— FunctionalModelPage
  // 各卡同款；订阅式声明坑16 正解，外观页开关切换即刷）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 总开关 + 已选模型两键（AppStorage 持久键；@StorageProp 订阅即自刷——本卡写点只碰
  // AppStorage，本地镜像自动跟随）
  @StorageProp(SUGGEST_ENABLED_KEY) @Watch('reloadDisplay') switchOn: boolean = false;
  @StorageProp(SUGGEST_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(SUGGEST_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
  // 模型显示名镜像 + 指向行已删标记（口径同父页各卡：missing = 行已删窗口期显示「未选择」
  // 不清两键，半模态打勾仍需原值——两键真源在 AppStorage，本处不持副本）
  @State private modelLabel: string = '';
  @State private missing: boolean = false;

  aboutToAppear(): void {
    this.reloadDisplay();
  }

  // 已选模型判定（两键齐 = 已配置；缺一即未启用不生成——SuggestGen 守卫序同判据）
  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  // 显示行文本（未配 / 指向行已删 = 「未选择」灰字）
  private displayText(): string {
    return this.bound() && !this.missing ?
      (this.modelLabel !== '' ? this.modelLabel : this.modelId) : '未选择';
  }

  // 显示行是否灰字（非「已配置且指向行在场」即灰——显示行配色判据）
  private displayMuted(): boolean {
    return !(this.bound() && !this.missing);
  }

  // 显示名解析（自持）：服务商行缺失 = missing；模型行缺失 = missing；查询失败 label
  // 兜底 modelId 静默降级（展示增强不阻断卡面）
  private reloadDisplay(): void {
    this.modelLabel = '';
    this.missing = false;
    if (!this.bound()) {
      return;
    }
    queryProviders()
      .then((providers: ProviderRow[]): Promise<ModelRow[]> => {
        const provider: ProviderRow | undefined =
          providers.find((row: ProviderRow): boolean => row.id === this.providerId);
        if (provider === undefined) {
          this.missing = true;
          return Promise.resolve([]);
        }
        return queryModels(provider.id, 'chat');
      })
      .then((models: ModelRow[]): void => {
        if (models.length === 0) {
          return; // 服务商行缺失已置位（空集无模型可解析）
        }
        const model: ModelRow | undefined =
          models.find((row: ModelRow): boolean => row.modelId === this.modelId);
        if (model !== undefined) {
          this.modelLabel = model.name !== '' ? model.name : model.modelId;
        } else {
          this.missing = true;
        }
      })
      .catch((_e: Object): void => {
        this.modelLabel = this.modelId;
      });
  }

  build() {
    Column({ space: 14 }) {
      // 顶部行：标题 + 右上角 ⓘ 信息气泡（说明文字收入气泡——InfoHintButton 服务商
      // 配置页先例；ⓘ 说明 = 任务书定稿文案，决明拍板）
      Row({ space: 8 }) {
        Text(SETTING_TITLE_SUGGEST)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '开启后 AI 回复下方显示推荐问题。选择用于生成的模型，未选择则不生成。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（★ 2026-09-20 上移为副标题——原在总开关行下方；未选/指向行已删 =
      // 「未选择」灰字，ModelDisplayRow 同款）
      Text(this.displayText())
        .fontSize(15)
        .fontColor(this.displayMuted() ? cardDescColor() : cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 总开关行（规范-列表卡片与组卡 §4.1 口径：Toggle 可点自切换 = 唯一控制面，行本身
      // 不可点不设按压反馈；落键后 @StorageProp 自动回流刷新——OCR 总开关行同款）
      Row() {
        Text('启用推荐问题')
          .fontSize(15)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.switchOn })
          .onChange((isOn: boolean) => {
            AppStorage.setOrCreate<boolean>(SUGGEST_ENABLED_KEY, isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 说明小字（按钮行上方——布局次序条；文案规约：无冒号分号括号连环）
      Text('回复完成后生成一次，消耗计入用量统计。未选择模型时不生成')
        .fontSize(13)
        .fontColor(cardDescColor())
      // 双键行（同宽各半行——与同页各卡同左缘同宽；左「选择模型」主操作键 primary=true
      // 官方强调蓝 + 恒白字（fallbackButton* 四件套双态，2026-09-11 决明「选择模型的键都
      // 改成蓝底」口径），右「提示词」次钮 = 记忆两卡先例）
      Row({ space: 10 }) {
        Button('选择模型')
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.onOpenModelSheet();
          })
        Button('提示词')
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.onOpenPromptSheet();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
