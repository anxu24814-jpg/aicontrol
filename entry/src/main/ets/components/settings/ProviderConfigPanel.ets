// 服务商详情 · 配置页签面板：组合 = 合规提示卡 + 协议卡（三选一官方胶囊分段，openai 下另有
// 接口形态子分段）+ 基础配置卡（名称 / Base URL；卡头右上「套用模板」裸文字键 + ⓘ）+
// ProviderKeysPanel（Key 池卡）。自定义请求头 / body 面板在父页 ProviderDetailPage。
// · API 密钥字段已退役（密钥改 Key 池管理，即时落库）；「启用开关卡」已退役——启停唯一控制面
//   = 服务商管理页卡片开关（详情页改完不点保存就离开会让人以为已生效）。
// · 合规提示卡页首常驻、先于一切配置动作：「请使用已依法备案的生成式人工智能服务。」文案
//   不排除自定义地址（勿称「不能配置境外模型」）。
// · 协议卡卡面不放提示文字，说明移入右上 ⓘ 气泡（系统默认材质/圆角，sys.color 自适应）；
//   仅 openai 协议附加思考回传说明段（含 if 分支，故为专属 @Builder 不并入 InfoHintButton）。
// · 表单值（name/baseUrl/protocol/headerPairs）全在父页 @State，本面板经 @Link 直写；
//   Key 池卡例外（自身 IO 即时落库）。协议值一律引 AiTypes 常量表（禁裸字符串）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import {
  ENDPOINT_LABELS, ENDPOINT_VALUES, PROTOCOL_OPENAI, PROTOCOL_VALUES, protocolLabel
} from '../../common/providers/AiTypes';
import { CATALOG_PRESETS, CatalogPreset, familyProtocolUrl } from '../../common/providers/ProviderCatalog';
import { CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import { InfoCard } from '../InfoCard';
import { InfoHintButton } from '../InfoHintButton';
import { ProviderKeysPanel } from './ProviderKeysPanel';
import { TemplatePickRow, TemplatePickSheet } from './TemplatePickSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';
import { overlayMaterial } from '../../common/ImmersiveLevel';

// 预设模板清单单源在 ProviderCatalog.ets：四元组整组权威回填，baseUrl 为官方查证初值，落库前可改

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
  // 协议（AiTypes 常量值；父页保存时落库）——@Watch 父→子同步（异步回填晚于挂载时补正下标）
  @Link @Watch('onProtocolChanged') protocol: string;
  // 分段选中下标（与 protocol 双向映射；@Watch 子→父——SegmentBar 改下标回写协议值）
  @State @Watch('onProtoIndexChanged') protoIndex: number = 0;
  // OpenAI 接口形态（父页 @State 保存时落库）——仅 openai 协议下显示子分段（选 a/g 不渲染，
  // 值保留不丢）；@Watch 父→子同步（异步回填晚于挂载时补正下标）
  @Link @Watch('onEndpointChanged') endpoint: string;
  // 子分段选中下标（与 endpoint 双向映射；@Watch 子→父）
  @State @Watch('onRespIndexChanged') respIndex: number = 0;
  // 取钥方式分段下标（0 = 轮询 / 1 = 随机）。本值**无字符串真源**（模式值只在父页保存链尾
  // 按下标映射落库），故纯 @Link 透传给 Key 池卡，不做下标↔值互映
  @Link keyPickIdx: number;
  // 协议说明气泡显示开关（bindPopup 受控 show；系统路径关闭经 onStateChange 回写复位，保证可重开）
  @State showProtoInfo: boolean = false;
  // 子分段选项（顺序 = ENDPOINT_VALUES 顺序——值/下标映射契约，勿单独乱调）
  private endpointItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: ENDPOINT_LABELS[0] },
    { text: ENDPOINT_LABELS[1] }
  ]);
  // Key 池启停草稿链透传：ProviderToggleDraft 的 key Map 引用 + 上行回调——普通成员传引用
  // 不经状态链（@BuilderParam content 通道 @Prop 冻结坑，ProviderKeysPanel 键常量注释同族）
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
  // 模板选择半模态显示态（点基础配置卡头「套用模板」键拉起；xmark/手势/点选回写 false）
  @State @Watch('onSheetVisibleChanged') private pickShow: boolean = false;
  // ── 关闭-再开协调（机制单源 = KimiSheetCommon.sheetPanelOptions 第四参注释；在途只记开意图，动效结束补开）──
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 半模态行卡数据（CATALOG_PRESETS 单源映射，静态成员初始化一次；本面板只消费）
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
  // ★ 换协议联动 Base URL：拨档时做家内协议端点跟随（图谱有目标协议条目才改写，自定义 URL
  //   不碰；见 ProviderCatalog.familyProtocolUrl），拨回原档对称还原。守卫 target === protocol
  //   = 父页回填触发路径（非用户动作），不联动防改表单
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

  // 套用模板：整组权威回填（基址/协议/接口形态一起覆盖，防不一致态）+ 空名称补服务商名 +
  // toast 反馈（P0-1 可见）；endpoint 子分段下标由 @Watch 链自动补正
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
  // 防吞 toast / 回填丢失，钉 B4）；endpoint 子分段下标仍走 @Watch 链
  private onPickPreset(index: number): void {
    if (index < 0 || index >= CATALOG_PRESETS.length) {
      return;
    }
    this.applyPreset(CATALOG_PRESETS[index]);
    this.requestClose();
  }

  // ── 关闭-再开协调（机制说明见字段注释；applyOpen 单入口，补开两路共用）──
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.pickShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.pickShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写压回 false 时按开意图补开；用户关闭必经 requestClose
  private onSheetVisibleChanged(): void {
    if (!this.pickShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 点选三路同调）：先清开意图 + 置离场动效在途位，再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.pickShow = false;
  }

  // 协议说明气泡内容（bindPopup builder——首层容器禁 position）：毛玻璃底与圆角由系统默认样式
  // 呈现，文字用 sys.color 自适应；宽度固定 280 防超长文本单行出界
  @Builder
  protoInfoPopup() {
    Column({ space: 8 }) {
      Text('OpenAI 兼容走中转站通用接口。Anthropic 与 Gemini 走官方原生端点。OpenAI 兼容下接口形态可选 chat/completions 面向中转站，或 Responses 面向 OpenAI 官方端点。')
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(20)
      // 仅 OpenAI 协议附加说明（非兼容协议不涉及思考回传——Anthropic 思考块须 signature 保真）
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
    // 卡间距走 CARD_SPACING 单源（规范「卡片间距一律由容器 space 管理」，改间距改 Theme 一处）
    Column({ space: CARD_SPACING }) {
      // ── 合规提示卡：页首常驻，先于一切配置动作（InfoCard 单源；文案禁扩写为承诺性表述）──
      InfoCard({ text: '请使用已依法备案的生成式人工智能服务。' })
      // ── 协议卡（三选一官方胶囊分段；Anthropic/Gemini 端点与认证头随协议切换；OpenAI 兼容
      // 下另含接口形态子分段——仅 openai 显示，选 a/g 不渲染但值保留）──
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('协议')
            .fontSize(CARD_SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .layoutWeight(1)
          // 更多信息键：官方 info_circle 图标键（TEXTUAL，font_secondary 灰）；点击弹官方气泡
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
            // 弹层族材质（决明「气泡全 thick」；「无」档 = 材质关闭回落官方默认）
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
        // ── 接口形态子分段（同卡内、主分段下方；仅 openai 渲染——选 a/g 时值保留，保存照写）──
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
      .borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start)

      // ── 基础配置卡（名称 / Base URL；API 密钥字段已退役）。卡头右上 = 「套用模板」裸文字键
      // + ⓘ；行卡是共享件 TemplatePickSheet，回填链 applyPreset 不变 ──
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text('基础配置')
            .fontSize(CARD_SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .layoutWeight(1)
          Text('套用模板')
            .fontSize(13)
            .fontColor($r('sys.color.font_emphasize'))
            .onClick((): void => {
              this.requestOpen();
            })
          InfoHintButton({ text: '内置常见服务商预设，一键填好地址与协议' })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        FieldInput({ label: '名称', placeholder: '如 DeepSeek、我的服务商', text: $name })
        FieldInput({ label: 'Base URL', placeholder: 'https://api.deepseek.com/v1', text: $baseUrl })
      }
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start)

      // ── Key 池卡（启停 = 草稿态经保存键统一落库，宿主下发草稿引用与上行回调；添加/删除/
      // 重填即时落库；新建态换提示卡；providerId 改 AppStorage 订阅自感知）──
      ProviderKeysPanel({
        draftRef: this.keyDraftRef,
        onToggleDraft: this.onKeyToggleDraft,
        // 连接测试用当前表单值（@Link 链直达父页 @State——编辑后测用最新值）；endpoint 供
        // T1 自组端点与流式链分发按 responses/chat 分流
        baseUrl: $baseUrl,
        protocol: $protocol,
        endpoint: $endpoint,
        // 取钥方式分段下标（@Link 透传父页 @State，落库在父页保存链尾）
        keyPickIdx: $keyPickIdx
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 模板选择半模态（挂本面板根——坑64 声明式 bindSheet 内容属页面树，深浅色随动；档位
    // [MEDIUM, LARGE] = 列表类默认双停靠。关闭走 requestClose 单入口 + 第四参 onDisappear 补开）
    .bindSheet($$this.pickShow, this.PickSheet(),
      sheetPanelOptions((action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }

  // 模板选择半模态内容（共享件 TemplatePickSheet——壳 / 行卡 / HDS 回退单源；点选即填入即关，
  // onPick 顺序钉 B4）
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
        this.requestClose();
      }
    })
  }
}
