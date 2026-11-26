// 服务商列表卡片段（自 ProviderPage 域级最小拆出，照 SessionCardItem 先例卡片独立成件）：名称 + 徽章行
//（协议名 / N 模型 / 明文标记 / 余额）+ 启用开关 + 四点菜单键；baseUrl 副行不显示（地址在详情页可见）。
// 纯展示 + 回调上行（开关落库/菜单/跳转编排在 ProviderPage）。
// ★ 数据自持有：@BuilderParam content（PageShell.content）内组件入参 @Prop 不随父 @State 更新——行显示数据
//（名称/protocol/模型计数/余额徽章）改卡内 @State + 自拉库（queryProviders + queryBalanceState + queryModels）。
// ★ 坑16：tick 广播在 push 页内 @StorageProp @Watch 实测不触发，且徽章 @Builder 值参直调 = 按值快照（冻结在
// 首帧值）。刷新链 = 管理页 reload 自增 cardEpoch → ForEach 键含纪元整卡重建（aboutToAppear 重拉）+ 详情/排序页
// onPop 回 reload；徽章行改 ForEach（键 = 文本本身，文本变即重建子项）。
// row（普通成员）仅承担行定位/开关/菜单/跳转（id/enabled），自展示字段起显示兜底（自拉完成前显示 row 初值/占位）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ModelRow, ProviderRow, queryModels, queryProviders
} from '../../common/store/ProviderDb';
import { BalanceState, queryBalanceState } from '../../common/store/ProviderBalanceDb';
import { ENDPOINT_CHAT, PROTOCOL_OPENAI, protocolLabel } from '../../common/providers/AiTypes';
import { KEY_PICK_ROTATE } from '../../common/store/ProviderKeyDb';
import { CLEARTEXT_BADGE_TEXT, isPublicCleartextEndpoint } from '../../common/providers/EndpointPolicy';
import { badgeBg, cardBg, cardDescColor, cardTitleColor, LIST_CARD_TITLE_FONTSIZE, CARD_RADIUS } from '../../common/Theme';

// 打点 TAG（「刷新后行内数据不变」定位桩：运行日志页按 TAG 过滤）
const DOMAIN: number = 0xD5A5;
const TAG: string = 'ProviderCardItem';

// 服务商卡片（自持有展示数据 + 回调；徽章行 = 协议名 / N 模型 / 余额）
@Component
export struct ProviderCardItem {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  // 行定位与交互（id/enabled/sortOrder——自展示字段不读 row；行在场/归段/排序由父 rows 驱动，
  // ForEach 键 = row.id 的增删序变已验有效）
  row: ProviderRow = { id: '', name: '', baseUrl: '', enabled: true, sortOrder: 0, createdAt: 0,
    balanceEnabled: false, balanceLastText: '', protocol: PROTOCOL_OPENAI, headers: '',
    endpoint: ENDPOINT_CHAT, promptCacheEnabled: false, promptCacheTtl: '5m', bodyOverrides: '',
    keyPickMode: KEY_PICK_ROTATE, builtin: false };
  onOpen: (row: ProviderRow) => void = () => {
  };
  onToggle: (row: ProviderRow, isOn: boolean) => void = () => {
  };
  onMenu: (row: ProviderRow) => void = () => {
  };
  // 卡片菜单锚点 id（openMenu TargetInfo 定位目标 = 本四点键——勿锚整卡：按钮卡内垂直居中，整卡锚点使菜单
  // 低于按钮 ≈30vp；空串 = 不定位，ProviderPage 恒传）
  menuAnchorId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 自持有展示数据（卡内自拉——不依赖父状态传播；tick 广播订阅已删，重拉经父页 ForEach 键含 cardEpoch）
  @State private name: string = '';
  @State private protocol: string = PROTOCOL_OPENAI;
  @State private balanceOn: boolean = false;
  @State private balanceText: string = '';
  @State private modelCountState: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  // 自拉（挂载 + 父页 ForEach 键含 cardEpoch 整卡重建——坑16 后唯一刷新链）：queryProviders 过滤本行 →
  // 余额态 + 模型计数一次拉全（用户手建小数据集，域内「查询有界」）；失败 toast 不静默（P0-1）；
  // 行已删 = 父列表 reload 移除本卡，此处静默返回
  private load(): void {
    hilog.warn(DOMAIN, TAG, 'load 触发 rowId=%{public}s', this.row.id);
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<void> => {
        if (this.departed) {
          return;
        }
        const row: ProviderRow | undefined =
          rows.find((item: ProviderRow): boolean => item.id === this.row.id);
        if (row === undefined) {
          hilog.warn(DOMAIN, TAG, '行不存在（可能已删）rowId=%{public}s', this.row.id);
          return;
        }
        this.name = row.name;
        this.protocol = row.protocol;
        this.balanceOn = row.balanceEnabled;
        const st: BalanceState = await queryBalanceState(row.id);
        if (this.departed) {
          return;
        }
        this.balanceText = st.lastText;
        this.modelCountState = (await queryModels(row.id, '')).length;
        hilog.warn(DOMAIN, TAG, '赋值完成 modelCount=%{public}d balance=%{public}s',
          this.modelCountState, this.balanceText);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        hilog.error(DOMAIN, TAG, 'load 失败：%{public}s', (e as Error).message);
        this.getUIContext().getPromptAction().showToast({ message: '服务商卡刷新失败：' + (e as Error).message });
      });
  }

  // 小徽章（文字胶囊；badgeBg 半透明灰底，文字 cardDescColor；仅经 ForEach 调用——坑16，直调值参快照不重渲）
  @Builder
  Badge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  // 徽章文本清单（ForEach 数据源；顺序 = 协议/模型计数/明文标记/余额；余额启用且查得时入列）。
  // ★「明文」标记：端点属「公网 + 明文」时常驻——存量配置不追溯拦截，可见性由本徽章承担（判据单源 =
  // EndpointPolicy，文案单源 = CLEARTEXT_BADGE_TEXT）；地址取 row.baseUrl（父列表页构造，改地址必伴 reload）
  private badges(): string[] {
    const list: string[] = [protocolLabel(this.protocol), this.modelCountState + ' 模型'];
    if (isPublicCleartextEndpoint(this.row.baseUrl)) {
      list.push(CLEARTEXT_BADGE_TEXT);
    }
    if (this.balanceOn && this.balanceText !== '') {
      list.push(this.balanceText);
    }
    return list;
  }

  build() {
    // Button(Normal) 包裹 = 官方原生按压蒙层（与详情页各卡/会话卡同反馈；行内 Toggle 与四点键先命中）。
    // ★ 拖拽例外：本卡所在列表可拖拽 ⇒ 外壳 Button 关原生按压（stateEffect(false)）——长按起手时按压态
    // 仍「按下」，而拖拽预览由条目节点实时渲染 ⇒ 蒙层跟着浮起、越过点击阈值才变白（灰→白跳变）；反馈改由
    // 「浮起」本身承担（坑58 同族：一处反馈已覆盖时另一处要关）。行内 Toggle/四点键不受影响（stateEffect 是
    // 逐组件属性）；同页其它卡不在拖拽面，保持原按压蒙层——勿据此「统一」全仓
    Button() {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.name !== '' ? this.name : this.row.name)
            .fontSize(LIST_CARD_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          // 徽章行走 ForEach 键变重建（坑16：@Builder 值参直调 = 按值快照，徽章冻结在首帧值；键 = 文本本身）
          Row({ space: 6 }) {
            ForEach(this.badges(), (text: string) => {
              this.Badge(text)
            }, (text: string): string => text)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 启用开关（停用 = 不参与聊天连接解析与模型选择；不弹确认——开关语义即时可逆）
        Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })
          .onChange((isOn: boolean): void => {
            this.onToggle(this.row, isOn);
          })
        // 四点菜单键（dot_grid_2x2——对话页签更多键同符号；TEXTUAL 文字键形制）；挂菜单锚点 id（菜单右缘对
        // 按钮右缘、按钮下沿弹出）
        Button() {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .id(this.menuAnchorId)
        .onClick((): void => {
          this.onMenu(this.row);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    // 卡宽 = 列表内容区 100%（List padding 左右 16 承收窄——与 SessionCardItem 同款；勿同时用 CARD_PANEL_WIDTH：
    // 与 List padding 叠加会双重收窄成屏宽-64）
    .width('100%')
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    // 关原生按压蒙层（理由见 build 头注释：按压态会跟浮起进拖拽预览；点开的按压反馈由页面转场承担）
    .stateEffect(false)
    .onClick((): void => {
      this.onOpen(this.row);
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
