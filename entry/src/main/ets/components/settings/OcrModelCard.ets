// 文字识别卡（功能模型页行化笔自 FunctionalModelPage 外移 + 自持有读取）：卡头 = 标题 + ⓘ；卡内 = 启用开关行
// → 引擎三分段 + 副行说明 → 模型行 + 提示词行（两行都只在视觉模型段渲染，2026-10-31 决明拍板：模型行
// 不再恒显）。开关行 Toggle 唯一控制面，分段件唯一选择面。引擎三态即选即生效；视觉模型未配置 = 段位
// 程序化回退原值并开既有模型选择面板；系统识别失败回退已选模型的行为链不变（resolveOcrEngine 不动），
// 仅该配置行在系统/内置段不再显示。自持有：总开关 + 引擎键 + 模型两键 @StorageProp 订阅即刷，父侧零镜像
// 零回调；段选落键判据 = 目标值 ≠ 当前解析值才写（页内回显不落键，保「未写 = 按旧口径推导」语义）。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { SegmentBar } from '../SegmentBar';
import { SETTING_TITLE_OCR } from '../../common/SettingSearch';
import { SEGMENT_BAR_HEIGHT, cardDescColor } from '../../common/Theme';
import {
  OCR_ENABLED_KEY, OCR_ENGINE_BUILTIN, OCR_ENGINE_KEY, OCR_ENGINE_MODEL, OCR_ENGINE_SYSTEM,
  OCR_MODEL_KEY, OCR_PREFER_SYSTEM_KEY, OCR_PROVIDER_KEY, resolveOcrEngine
} from '../../common/store/ProviderDb';
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import {
  FunctionalCardHeader, PromptSettingRow, SettingSwitchRow, SettingValueRow
} from './FunctionalSettingRows';

@Component
export struct OcrModelCard {
  private departed: boolean = false;
  onOpenModelSheet: (kind: string) => void = () => {
  };
  onOpenPromptSheet: (kind: string) => void = () => {
  };
  // 总开关（字符串键 'true'|'false'，缺省开）；读侧统一走 ocrEnabled()
  @StorageProp(OCR_ENABLED_KEY) ocrEnabledRaw: string = 'true';
  // 引擎三态键（'' = 按旧口径推导；显式值 = 系统/内置/视觉模型）
  @StorageProp(OCR_ENGINE_KEY) @Watch('onEngineKeyChanged') engineKey: string = '';
  @StorageProp(OCR_PROVIDER_KEY) @Watch('onOcrModelChanged') providerId: string = '';
  @StorageProp(OCR_MODEL_KEY) @Watch('onOcrModelChanged') modelId: string = '';
  // 分段下标镜像（顺序契约：0 系统 / 1 内置 / 2 视觉，与 engineIndexOf / engineValueOf 三处同序，勿乱调）。
  // 内置段 enabled 取真机能力探测：canIUse 在应用存活期内恒定，一次构造即可
  @State @Watch('onEngineIndexChanged') engineIndex: number = 0;
  private ocrEngineItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '系统识别' },
    { text: '内置识别', enabled: canIUse('SystemCapability.AI.MindSporeLite') },
    { text: '视觉模型' }
  ]);
  @State private modelLabel: string = '';
  @State private missing: boolean = false;

  aboutToAppear(): void {
    this.syncEngineIndex();
    this.reloadDisplay();
  }

  private ocrEnabled(): boolean {
    return this.ocrEnabledRaw !== 'false';
  }

  private bound(): boolean {
    return this.providerId !== '' && this.modelId !== '';
  }

  // 当前生效引擎（与 OcrEngine.preferredEngine / 生成链读侧同源）
  private resolveCurrentEngine(): string {
    return resolveOcrEngine(this.engineKey,
      AppStorage.get<string>(OCR_PREFER_SYSTEM_KEY) ?? '', this.providerId, this.modelId);
  }

  // 持久键 / 模型变化 → 分段下标回灌（读到什么显示什么；不写键）
  private syncEngineIndex(): void {
    this.engineIndex = this.engineIndexOf(this.resolveCurrentEngine());
  }

  private onEngineKeyChanged(): void {
    this.syncEngineIndex();
  }

  private onOcrModelChanged(): void {
    this.reloadDisplay();
    this.syncEngineIndex();
  }

  private engineIndexOf(value: string): number {
    if (value === OCR_ENGINE_BUILTIN) {
      return 1;
    }
    if (value === OCR_ENGINE_MODEL) {
      return 2;
    }
    return 0;
  }

  private engineValueOf(index: number): string {
    if (index === 1) {
      return OCR_ENGINE_BUILTIN;
    }
    if (index === 2) {
      return OCR_ENGINE_MODEL;
    }
    return OCR_ENGINE_SYSTEM;
  }

  // 段选落键：系统 / 内置即选即生效；视觉模型未配置 = 段位回退原值 + 开既有模型选择面板；落键判据 =
  // 目标值 ≠ 当前解析值才写（回显赋值不落键）。★ 回显与点选分叉（进页自动弹面板修复）：下标已等于解析值 =
  // 回显或点回当前段，直接早退——缺这条时「引擎键为视觉模型而模型两键空」会在每次进页自动弹面板
  private onEngineIndexChanged(): void {
    const resolved: string = this.resolveCurrentEngine();
    if (this.engineIndex === this.engineIndexOf(resolved)) {
      return;
    }
    if (this.engineIndex === 2 && !this.bound()) {
      this.engineIndex = this.engineIndexOf(resolved);
      this.onOpenModelSheet('ocrModel');
      return;
    }
    const value: string = this.engineValueOf(this.engineIndex);
    if (value !== resolved) {
      AppStorage.setOrCreate<string>(OCR_ENGINE_KEY, value);
    }
  }

  // 模型显示名（只显模型名不带服务商前缀；未选 / 指向行已删 = 未选择）
  private displayText(): string {
    if (!this.bound() || this.missing) {
      return '未选择';
    }
    return this.modelLabel !== '' ? this.modelLabel : this.modelId;
  }

  private displayMuted(): boolean {
    if (!this.ocrEnabled()) {
      return true;
    }
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

  // 分段副行说明（三态各一句 + 未启用态；文案规约：无冒号分号括号连环，内置识别如实写「图片不出设备」，
  // 不写「手写」、不承诺准确率）
  private ocrEngineDescText(): string {
    if (!this.ocrEnabled()) {
      return '关闭后图片与扫描件不做识别，附件按原样发送';
    }
    if (this.engineIndex === 1) {
      return '离线识别，图片不出设备，支持中英日与常用拉丁语系语言，无需配置';
    }
    if (this.engineIndex === 2) {
      return this.bound() && !this.missing
        ? '图片会发送给你配置的服务商，识别消耗计入用量统计'
        : '点下方「模型」行选择要使用的模型';
    }
    // 系统段副行不再提「失败时改用已选模型」——模型行只在视觉段渲染，本段无该配置行可指
    //（回退行为本身仍在，见头注释）
    return '使用系统自带识别，无需配置';
  }

  build() {
    Column({ space: 12 }) {
      FunctionalCardHeader({
        title: SETTING_TITLE_OCR,
        hint: '开启后，图片与扫描件在发送前识别成文字，供不支持视觉的模型阅读。识别结果只随本次请求发出。系统识别与内置识别在本机完成，图片不发给服务商。视觉模型识别会把图片发给你配置的服务商。'
      })
      // 开关 / 分段 / 属性行同组无空隙——分段块自带左右 12vp 与上下呼吸位，行分割线紧邻分段块下缘
      Column() {
        SettingSwitchRow({
          label: '启用文字识别',
          subtitle: '发送前识别图片',
          isOn: this.ocrEnabled(),
          dividerTop: false,
          onToggle: (isOn: boolean): void => {
            AppStorage.setOrCreate<string>(OCR_ENABLED_KEY, isOn ? 'true' : 'false');
          }
        })
        Column({ space: 10 }) {
          Column() {
            SegmentBar({
              items: this.ocrEngineItems,
              selectedIndex: $engineIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
          Text(this.ocrEngineDescText())
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
        // 模型行 + 提示词行都只在视觉模型段渲染（2026-10-31 决明拍板：模型行不再恒显；
        // 整块条件渲染——空 Column 留在 space:12 父容器里会多出一段缝）
        if (this.engineIndex === 2) {
          Column() {
            SettingValueRow({
              label: '模型',
              subtitle: '视觉识别时使用',
              value: this.displayText(),
              valueMuted: this.displayMuted(),
              dividerTop: true,
              onTap: (): void => {
                this.onOpenModelSheet('ocrModel');
              }
            })
            PromptSettingRow({
              slotKind: 'ocrPrompt',
              label: '提示词',
              subtitle: '控制识别输出格式',
              dividerTop: true,
              onTap: (): void => {
                this.onOpenPromptSheet('ocrPrompt');
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
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
