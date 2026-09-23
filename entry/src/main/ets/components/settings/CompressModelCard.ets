// 上下文压缩卡（2026-09-23 上下文压缩，任务书-上下文压缩-20260923 §3.4；照 SuggestModelCard
// 范式：@StorageProp 自订阅、显示名自解析、标题行 → 副标题 → 说明小字 → 双键行——宪法
// 「功能设置卡布局次序」条，说明小字在操作行上方）。与记忆两卡的语义差异（说明小字与本卡
// 缺省态都体现）：模型两键未配置 = **回退当前会话的模型**（不是「未启用不压缩」）。
// ★ 自持有读取（规范-数据存储获取刷新方案「卡片自持有读取」+ 坑16 正解——本卡居
// PageShell.content 内）：两键是 AppStorage 持久键，@StorageProp @Watch 订阅即自刷（本卡
// 落键、功能模型页选择落键、设置恢复备份三写点全部即时反映，父侧零镜像零 reload 回调）；
// 显示名解析自持（服务商行缺失 = missing「未选择」——与父页 resolveModelDisplay 同口径但
// 输出面不同：本卡不带服务商名，两实现各自成立不算重复）
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SETTING_TITLE_COMPRESS } from '../../common/SettingSearch';
import { cardDescColor, cardTitleColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';
import { COMPRESS_MODEL_KEY, COMPRESS_PROVIDER_KEY } from '../../common/CompressGen';
import { ModelRow, ProviderRow, queryModels, queryProviders } from '../../common/store/ProviderDb';

@Component
export struct CompressModelCard {
  // 半模态打开回调（父侧 sheetKind 单面板多形态宿主——本卡只发意图，ModelPickerSheet 与
  // 提示词编辑面板的装配全在父侧；构造注入后不变，坑30 口径）
  onOpenModelSheet: () => void = () => {
  };
  onOpenPromptSheet: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感回退双态 + 分项档位（双键 fallbackButton* 四件套参数——同页各卡同款）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 压缩模型两键（AppStorage 持久键；@StorageProp 订阅即自刷——本卡写点只碰 AppStorage，
  // 本地镜像自动跟随）
  @StorageProp(COMPRESS_PROVIDER_KEY) @Watch('reloadDisplay') providerId: string = '';
  @StorageProp(COMPRESS_MODEL_KEY) @Watch('reloadDisplay') modelId: string = '';
  // 模型显示名镜像 + 指向行已删标记（口径同 SuggestModelCard：missing = 行已删窗口期显示
  // 「未选择」不清两键，半模态打勾仍需原值——两键真源在 AppStorage，本处不持副本）
  @State private modelLabel: string = '';
  @State private missing: boolean = false;

  aboutToAppear(): void {
    this.reloadDisplay();
  }

  // 已选判定（两键齐 = 已配置；缺一 = 回退当前会话模型——显示行「未选择」）
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
      // 顶部行：标题 + 右上角 ⓘ 信息气泡（说明文字收入气泡——InfoHintButton 同页先例；
      // 文案规约：无冒号分号括号连环）
      Row({ space: 8 }) {
        Text(SETTING_TITLE_COMPRESS)
          .fontSize(16)
          .fontColor(cardTitleColor())
        Blank()
        InfoHintButton({
          text: '会话页的上下文用量面板里手动压缩上下文。压缩由模型整理成交接摘要，之后的请求只带摘要和最近几轮原文。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 当前选择显示行（副标题槽——未选/指向行已删 = 「未选择」灰字，同页七卡同槽同判据）
      Text(this.displayText())
        .fontSize(15)
        .fontColor(this.displayMuted() ? cardDescColor() : cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 说明小字（按钮行上方——布局次序条；「未选择时使用当前会话的模型」= 本槽回退语义，
      // 任务书拍板 8）
      Text('未选择时使用当前会话的模型。压缩消耗计入用量统计')
        .fontSize(13)
        .fontColor(cardDescColor())
      // 双键行（同宽各半行——左「选择模型」主操作键 primary=true 官方强调蓝 + 恒白字，
      // 右「提示词」次钮；记忆两卡先例）
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
