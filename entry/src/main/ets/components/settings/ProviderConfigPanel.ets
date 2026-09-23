// 服务商详情 · 配置页签面板（2026-08-30 服务商管理域新建；同日多 Key 池 + 三协议改组合）：
// 组合 = 启用开关卡 + 协议卡（三选一官方胶囊分段：OpenAI 兼容 / Anthropic / Gemini——
// 分发在 ChatStreamFactory，存量默认 openai）+ 基础配置卡（名称 / Base URL 两输入——
// ★API 密钥字段退役：密钥改 Key 池管理，ProviderKeysPanel 即时落库）+ 套用模板卡
//（预设清单 = ProviderCatalog.CATALOG_PRESETS 单源——2026-09-11 改「选择模板」键 +
// 半模态行卡选择〔三处模板统一半模态，方案 v3〕，原卡内横滑 chips 退役；回填链
// applyPreset 整组权威回填不变）+
// ProviderKeysPanel（Key 池卡）+ ProviderHeadersPanel（自定义请求头卡，表单值经 @Link
// 走父页保存链）。启用开关语义 = 停用不参与聊天连接与模型选择。
// 协议卡提示（2026-09-02）：卡面不放提示文字（历史长说明全部移入右上角 ⓘ 键气泡——
// bindPopup 官方气泡：毛玻璃底/圆角/箭头均系统默认样式，文字用 sys.color 自适应深浅色）；
// 气泡内容 = 通用协议说明 + 仅 openai 协议附加的思考回传说明段（选中 OpenAI 兼容时
// 多一段——与旧卡面「openai 专属提示」语义一致）；协议卡气泡含 if 分支，为专属
// @Builder 未并入 InfoHintButton 共享件。
// 表单值（name/baseUrl/protocol/headerPairs）全在父页（ProviderDetailPage @State，保存键
// 在标题栏），本面板经 @Link 双向直写——纯展示 + 值通道；Key 池卡例外（自身 IO 即时落库，
// 模型页签同款契约）。协议值一律引 AiTypes 常量表（禁裸字符串）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import {
  ENDPOINT_LABELS, ENDPOINT_VALUES, PROTOCOL_OPENAI, PROTOCOL_VALUES, protocolLabel
} from '../../common/providers/AiTypes';
import { CATALOG_PRESETS, CatalogPreset, familyProtocolUrl } from '../../common/providers/ProviderCatalog';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import { ProviderKeysPanel } from './ProviderKeysPanel';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial
} from '../../common/ImmersiveLevel';

// 预设模板清单（套用模板卡）已迁至 ProviderCatalog.ets（服务商图谱单一来源）——
// 模板条目 = 四元组（displayName/shortName/baseUrl/protocol/endpoint），点模板整组权威
// 回填（基址/协议/接口形态一起覆盖——消除「模板基址与协议不一致」的半套状态）；
// baseUrl 均为官方文档查证值，仅作回填初值，落库前用户可改

// 输入项标签 + 输入框（名称/Base URL 同构；密码型已随单 Key 字段退役）
@Component
struct FieldInput {
  label: string = '';
  placeholder: string = '';
  @Link text: string;

  build() {
    Column({ space: 6 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      TextInput({ placeholder: this.placeholder, text: this.text })
        .width('100%')
        .onChange((value: string): void => {
          this.text = value;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct ProviderConfigPanel {
  // 表单值（父页 @State 持有——保存动作在标题栏键；@Link 双向直写）
  @Link name: string;
  @Link baseUrl: string;
  // 启用开关（同上；父页保存时落库）——成员名避开通用属性 enabled（组件成员与
  // 通用属性方法重名 = 10505001 撞名编译错）
  @Link providerEnabled: boolean;
  // 协议（AiTypes 常量值；父页保存时落库）——@Watch 父→子同步（loadEditState 异步回填晚于
  // 本面板挂载时补正分段下标）
  @Link @Watch('onProtocolChanged') protocol: string;
  // 所属服务商 id（'' = 新建未保存——透传给 Key 池卡换提示）
  // （providerId @Prop 已删——Key 池卡改 AppStorage 订阅自感知，2026-08-30 自持有配套，
  // 见 ProviderKeysPanel PROVIDER_EDIT_ID_KEY 注释；本面板无其他 providerId 消费）
  // 分段选中下标（与 protocol 双向映射；@Watch 子→父——SegmentBar 改下标回写协议值）
  @State @Watch('onProtoIndexChanged') protoIndex: number = 0;
  // OpenAI 接口形态（2026-08-30 Responses 适配；父页 @State 保存时落库）——仅 openai 协议
  // 下显示子分段胶囊（选 a/g 不渲染），值保留不丢；@Watch 父→子同步（loadEditState 异步
  // 回填晚于本面板挂载时补正分段下标——照 protocol 同款姿势）
  @Link @Watch('onEndpointChanged') endpoint: string;
  // 子分段选中下标（与 endpoint 双向映射；@Watch 子→父——同 protoIndex 契约）
  @State @Watch('onRespIndexChanged') respIndex: number = 0;
  // 取钥方式分段下标（2026-09-17 DB v32；0 = 轮询 / 1 = 随机）。与 protocol/endpoint 不同：
  // 本值**无字符串真源**（模式值只在父页保存链尾按下标映射落库），故纯 @Link 透传给
  // Key 池卡，不做下标↔值互映——父页 loadEditState 回填 + 保存时读
  @Link keyPickIdx: number;
  // 协议说明气泡显示开关（bindPopup 受控 show；系统路径关闭——点遮罩/自适应关闭——
  // 经 onStateChange 回写复位，保证再次点击可重开）
  @State showProtoInfo: boolean = false;
  // 子分段选项（顺序 = ENDPOINT_VALUES 顺序——形态值/下标映射契约，勿单独乱调）
  private endpointItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: ENDPOINT_LABELS[0] },
    { text: ENDPOINT_LABELS[1] }
  ]);
  // Key 池启停草稿链透传（2026-08-31 统一保存语义，宿主 ProviderDetailPage 下发）：
  // ProviderToggleDraft 的 key Map 引用 + 上行回调——普通成员传引用不经状态链
  //（@BuilderParam content 通道 @Prop 冻结坑，ProviderKeysPanel 键常量注释同族）
  keyDraftRef: Map<string, boolean> = new Map();
  onKeyToggleDraft: (keyId: string, on: boolean) => void = () => {
  };
  // 分段选项（顺序 = PROTOCOL_VALUES 顺序——协议值/下标映射契约，勿单独乱调）
  private protocolItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: 'OpenAI 兼容' },
    { text: 'Anthropic' },
    { text: 'Gemini' }
  ]);
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区光感双态（「选择模板」键 = 内容区行内文字键，走 fallbackButton* 四件套）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 模板选择半模态显示态（点「选择模板」键拉起；xmark/手势/点选回写 false）
  @State private pickShow: boolean = false;
  // 半模态行卡数据（CATALOG_PRESETS 单源映射，静态数据成员初始化一次——行卡 = 模板名 /
  // 基址 / 协议尾标；数据源单源在 ProviderCatalog，本面板只消费）
  private pickRows: TemplatePickRow[] = CATALOG_PRESETS.map(
    (preset: CatalogPreset): TemplatePickRow => {
      const row: TemplatePickRow = {
        title: preset.displayName,
        subtitle: preset.baseUrl,
        suffix: protocolLabel(preset.protocol)
      };
      return row;
    });

  aboutToAppear(): void {
    this.syncIndexFromProtocol();
    this.syncIndexFromEndpoint();
  }

  // 父页回填 protocol → 补正分段下标（异常值钳位 0 = OpenAI 兼容，工厂同款兜底）
  private onProtocolChanged(): void {
    this.syncIndexFromProtocol();
  }

  private syncIndexFromProtocol(): void {
    const idx: number = PROTOCOL_VALUES.indexOf(this.protocol);
    this.protoIndex = idx >= 0 ? idx : 0;
  }

  // SegmentBar 改选 → 回写协议值（@Watch 仅值变化触发，与上互设同值不递归）。
  // ★ 换协议联动 Base URL（2026-08-31）：用户拨档时做家内协议端点跟随（图谱同家目标
  // 协议条目存在才改写，自定义 URL 不碰——映射语义见 ProviderCatalog.familyProtocolUrl）；
  // 拨回原档 URL 对称还原。守卫 target === this.protocol = syncIndexFromProtocol 程序
  // 补正路径（父页 loadEditState 回填触发的 @Watch 链）——非用户动作，不联动防改表单
  private onProtoIndexChanged(): void {
    if (this.protoIndex >= 0 && this.protoIndex < PROTOCOL_VALUES.length) {
      const target: string = PROTOCOL_VALUES[this.protoIndex];
      if (target === this.protocol) {
        return;
      }
      const mapped: string = familyProtocolUrl(this.baseUrl, target);
      if (mapped !== '' && mapped !== this.baseUrl) {
        this.baseUrl = mapped;
      }
      this.protocol = target;
    }
  }

  // 父页回填 endpoint → 补正子分段下标（异常值钳位 0 = chat/completions——工厂同款兜底）
  private onEndpointChanged(): void {
    this.syncIndexFromEndpoint();
  }

  private syncIndexFromEndpoint(): void {
    const idx: number = ENDPOINT_VALUES.indexOf(this.endpoint);
    this.respIndex = idx >= 0 ? idx : 0;
  }

  // 子分段改选 → 回写形态值（与 protoIndex 同契约）
  private onRespIndexChanged(): void {
    if (this.respIndex >= 0 && this.respIndex < ENDPOINT_VALUES.length) {
      this.endpoint = ENDPOINT_VALUES[this.respIndex];
    }
  }

  // 套用模板：整组权威回填（基址/协议/接口形态一起覆盖——模板即权威预设，防不一致态）
  // + 空名称补服务商名 + toast 反馈（P0-1 可见）；endpoint 随模板回填后子分段选中态由
  // @Watch 链（onEndpointChanged → syncIndexFromEndpoint）自动补正
  private applyPreset(preset: CatalogPreset): void {
    this.baseUrl = preset.baseUrl;
    this.protocol = preset.protocol;
    this.endpoint = preset.endpoint;
    if (this.name.trim() === '') {
      this.name = preset.shortName;
    }
    this.getUIContext().getPromptAction().showToast({ message: '已填入 ' + preset.displayName + ' 接口地址' });
  }

  // 半模态点选：整组回填 + toast（applyPreset 内）后关面板——顺序不可颠倒（先回填后关，
  // 防吞 toast / 回填丢失，钉 B4）；endpoint 子分段下标补正仍走 @Watch 链（applyPreset
  // 注释同款），回填链本笔零改动
  private onPickPreset(index: number): void {
    if (index < 0 || index >= CATALOG_PRESETS.length) {
      return;
    }
    this.applyPreset(CATALOG_PRESETS[index]);
    this.pickShow = false;
  }

  // 协议说明气泡内容（bindPopup CustomPopupOptions.builder——首层容器禁 position 属性）：
  // 毛玻璃底与圆角由系统 Popup 默认样式呈现（popupColor 不设 = API 11+ 官方形态），
  // 文字用 sys.color 系统自适应色（深浅色自动跟随）；宽度固定 280 防超长文本单行出界
  @Builder
  protoInfoPopup() {
    Column({ space: 8 }) {
      Text('OpenAI 兼容走中转站通用接口。Anthropic 与 Gemini 走官方原生端点。OpenAI 兼容下接口形态可选 chat/completions 面向中转站，或 Responses 面向 OpenAI 官方端点。')
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(20)
      // 仅 OpenAI 兼容协议附加说明（旧卡面「openai 专属提示」语义随迁：非兼容协议
      // 不涉及思考回传——Anthropic 思考块须 signature 保真、Gemini 非官方要求）
      if (this.protocol === PROTOCOL_OPENAI) {
        Text('发送时会回传历史思考过程，这是 DeepSeek 等思考模式服务商的要求。不支持思考的模型自动忽略。')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(20)
      }
    }
    .width(280)
    .padding(12)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 }) {
      // ── 启用开关卡 ──
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('启用服务商')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          Text('停用后不参与聊天连接与模型选择')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.providerEnabled })
          .onChange((isOn: boolean): void => {
            this.providerEnabled = isOn;
          })
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(VerticalAlign.Center)

      // ── 协议卡（三选一官方胶囊分段；Anthropic/Gemini 端点与认证头随协议切换；
      // OpenAI 兼容下另含接口形态子分段（chat/completions 中转站通用 / Responses 官方新接口）
      // ——仅 openai 显示，选 a/g 不渲染但值保留）──
      Column({ space: 10 }) {
        Row() {
          Text('协议')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .layoutWeight(1)
          // 更多信息键（2026-09-02）：官方 info_circle 图标键（图标钮形态照卡内双键
          // ——ButtonStyleMode.TEXTUAL，font_secondary 灰）；点击弹官方气泡
          Button() {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick((): void => {
            this.showProtoInfo = !this.showProtoInfo;
          })
          .bindPopup(this.showProtoInfo, {
            builder: (): void => {
              this.protoInfoPopup();
            },
            placement: Placement.BottomRight,
            // 弹层族材质（2026-09-22 决明指令「气泡全 thick」；「无」档 = 材质关闭回落官方默认）
            systemMaterial: overlayMaterial(),
            onStateChange: (event: PopupStateChangeParam): void => {
              if (!event.isVisible) {
                this.showProtoInfo = false;
              }
            }
          })
        }
        .width('100%')
        Column() {
          SegmentBar({
            items: this.protocolItems,
            selectedIndex: $protoIndex
          })
        }
        .width('100%')
        .height(SEGMENT_BAR_HEIGHT)
        // ── 接口形态子分段（2026-08-30 Responses 适配；同卡片内、主分段下方；仅 openai
        // 协议下渲染——选 a/g 时 if 分支不执行，endpoint 值保留（父页真源，保存照写）──
        if (this.protocol === PROTOCOL_OPENAI) {
          Column() {
            SegmentBar({
              items: this.endpointItems,
              selectedIndex: $respIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)

      // ── 基础配置卡（名称 / Base URL；API 密钥字段已退役——Key 池卡管理）──
      Column({ space: 12 }) {
        Text('基础配置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        FieldInput({ label: '名称', placeholder: '如 DeepSeek、我的服务商', text: $name })
        FieldInput({ label: 'Base URL', placeholder: 'https://api.deepseek.com/v1', text: $baseUrl })
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)

      // ── 套用模板卡（预设端点回填；2026-09-11 改「选择模板」键 + 半模态行卡——原卡内
      // 横滑 chips 一屏放不下、条目藏得深找起来不便捷〔三处模板统一半模态，方案 v3〕；
      // 行卡 = 共享件 TemplatePickSheet，点选即填入即关；回填链 applyPreset 不变）──
      Column({ space: 10 }) {
        Text('套用模板')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text('内置常见服务商预设，一键填好地址与协议')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        // 「选择模板」= 本卡主操作键（fallbackButton* 四件套 primary=true——官方强调蓝 +
        // 恒白字；2026-09-11 决明「三处模板键均改蓝底」，原 primary=false 灰底作废）
        Button('选择模板')
          .fontSize(14)
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback,
            this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback,
            this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback,
            this.immersiveLevel))
          .width('100%')
          .onClick((): void => {
            this.pickShow = true;
          })
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)

      // ── Key 池卡（启停 = 草稿态经保存键统一落库（2026-08-31 统一保存语义，宿主下发
      // 草稿引用与上行回调透传）；添加/删除/重填即时落库；新建态换提示卡；providerId 改
      // AppStorage 订阅自感知，见 ProviderKeysPanel 键常量注释）──
      ProviderKeysPanel({
        draftRef: this.keyDraftRef,
        onToggleDraft: this.onKeyToggleDraft,
        // 连接测试用当前表单值（@Link 链直达父页 @State——编辑后测用最新值）；endpoint 于
        // 2026-09-21 能力三项测试笔补透传（T1 自组端点与流式链分发都要按 responses/chat 分流）
        baseUrl: $baseUrl,
        protocol: $protocol,
        endpoint: $endpoint,
        // 取钥方式分段下标（2026-09-17 DB v32——@Link 透传父页 @State，落库在父页保存链尾）
        keyPickIdx: $keyPickIdx
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 模板选择半模态（挂本面板根——同页 ProviderModelsPanel 页签面板内挂半模态先例；
    // 坑64 声明式 bindSheet 内容属页面树，深浅色随动；档位 [MEDIUM, LARGE] 列表类 =
    // sheetPanelOptions 默认双停靠位；onWillDismiss = 手势关闭动画前置回写 false——
    // KimiSheetCommon 定稿防「关了再开不弹」竞态）
    .bindSheet(this.pickShow, this.PickSheet(),
      sheetPanelOptions((): void => {
        this.pickShow = false;
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }

  // 模板选择半模态内容（共享件 TemplatePickSheet——壳 / 行卡 / HDS 回退单源，协议 / 价格 /
  // 余额三处消费之一；点选即填入即关，onPick 顺序钉 B4）
  @Builder
  PickSheet() {
    TemplatePickSheet({
      mainTitle: '套用模板',
      subTitle: '点选即填入，可继续手动修改',
      rows: this.pickRows,
      onPick: (index: number): void => {
        this.onPickPreset(index);
      },
      onClose: (): void => {
        this.pickShow = false;
      }
    })
  }
}
