// 服务商列表卡片段（2026-08-30 反馈轮 2 自 ProviderPage.ets 域级最小拆出——该页自包
// PageShell 壳后 402 行触 400 红线；照 SessionCardItem 先例卡片独立成件，形态/回调不变）：
// 名称 + 徽章行（协议名 / N 模型 / 余额（启用且查得时显示））+ 启用开关 + 四点菜单键。
// ★ baseUrl 副行已移除（2026-08-30 领导指令：卡不显示 API 链接——地址在详情页可见）。
// 纯展示 + 回调上行（开关落库/菜单/跳转编排在 ProviderPage）。
// ★ 2026-08-30 数据自持有重构（领导「手动刷新也不对，退回设置页再回才变」驱动——根因
// 定稿：@BuilderParam content（PageShell.content）内组件入参 @Prop 不随父 @State 更新，
// 多轮 @Prop/onPop/刷新键修复全中此传播链；订阅式 @Link/@StorageProp 与 ForEach 行增删
// 均正常）——结构性解：行显示数据（名称/protocol/模型计数/余额徽章）改卡内自持有
// @State + 自拉库（queryProviders + queryBalanceState + queryModels）。
// ★ 坑16·2026-08-30 二次修复（领导「仍 0 模型/余额不变」驱动）：tick 广播在 push 页内
// @StorageProp @Watch 实测不触发（hilog 取证从未见 tick 重拉），且徽章 @Builder 值参
// 直调 = 按值快照——状态更新时 Builder 内 UI 不重渲、冻结在首帧值（官方按值传参规则；
// 「复进管理页正常」= 异步赋值赶在首帧前混入创建值的假象）。刷新链收敛为：管理页
// reload 自增 cardEpoch → ForEach 键含纪元整卡重建（aboutToAppear 重拉）+ 详情/排序页
// onPop 回 reload；徽章行改 ForEach（键 = 文本本身，文本变即重建子项）。
// row（普通成员）仅承担行定位/开关/菜单/跳转（id/enabled），自展示字段起显示兜底
//（自拉完成前显示 row 初值或占位）。
// ★ 拖拽手柄/「使用中」/「已停用」徽章移除口径见旧注（反馈轮 6/9/11 定稿）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ModelRow, ProviderRow, queryModels, queryProviders
} from '../../common/store/ProviderDb';
import { BalanceState, queryBalanceState } from '../../common/store/ProviderBalanceDb';
import { ENDPOINT_CHAT, PROTOCOL_OPENAI, protocolLabel } from '../../common/providers/AiTypes';
import { KEY_PICK_ROTATE } from '../../common/store/ProviderKeyDb';
import { badgeBg, cardBg, cardDescColor, cardTitleColor, LIST_CARD_TITLE_FONTSIZE } from '../../common/Theme';

// （坑16·2026-08-30：PROVIDER_CARD_REFRESH_KEY tick 广播已删——push 页内
// @StorageProp @Watch 实测不触发（管理页属 Navigation push 页）；行刷新改 =
// 管理页 reload 自增 cardEpoch 进 ForEach 键整卡重建 + 详情页 onPop 回 reload，
// 见 ProviderPage 头注释）

// 打点 TAG（2026-08-30「刷新后行内数据不变」定位桩：运行日志页按 TAG 过滤）
const DOMAIN: number = 0xD5A5;
const TAG: string = 'ProviderCardItem';

// 服务商卡片（自持有展示数据 + 回调；徽章行 = 协议名 / N 模型 / 余额）
@Component
export struct ProviderCardItem {
  // 行定位与交互（id/enabled/sortOrder——自展示字段不读 row；★ 与「行在场/归段/排序」
  // 一同由父 rows 驱动，ForEach 键 = row.id 的增删序变已验有效）
  row: ProviderRow = { id: '', name: '', baseUrl: '', enabled: true, sortOrder: 0, createdAt: 0,
    balanceEnabled: false, balanceLastText: '', protocol: PROTOCOL_OPENAI, headers: '',
    endpoint: ENDPOINT_CHAT, promptCacheEnabled: false, promptCacheTtl: '5m', bodyOverrides: '',
    keyPickMode: KEY_PICK_ROTATE };
  onOpen: (row: ProviderRow) => void = () => {
  };
  onToggle: (row: ProviderRow, isOn: boolean) => void = () => {
  };
  onMenu: (row: ProviderRow) => void = () => {
  };
  // 卡片菜单锚点 id（openMenu TargetInfo 定位目标 = 本四点键——2026-08-30 反馈轮 8 领导
  // 拍板：勿锚整卡，按钮卡内垂直居中，整卡锚点使菜单低于按钮 ≈30vp 观感偏低；空串 =
  // 不定位，ProviderPage 恒传）
  menuAnchorId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // （坑16·2026-08-30：tick 广播订阅已删——push 页内 @StorageProp @Watch 实测不触发；
  // 重拉 = 父页 ForEach 键含 cardEpoch 整卡重建，见 ProviderPage 头注释）
  // 自持有展示数据（卡内自拉——不依赖父状态传播）
  @State private name: string = '';
  @State private protocol: string = PROTOCOL_OPENAI;
  @State private balanceOn: boolean = false;
  @State private balanceText: string = '';
  @State private modelCountState: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  // 自拉（挂载 + 父页 ForEach 键含 cardEpoch 触发整卡重建——坑16 后唯一刷新链）：服务商行（queryProviders 过滤——用户手建小数据集，域内
  //「查询有界」口径）→ 余额态 + 模型计数一次拉全；失败 toast 不静默（P0-1，用户再点
  // 刷新键可重试）；行已删 = 父列表 reload 移除本卡，此处静默返回
  private load(): void {
    hilog.warn(DOMAIN, TAG, 'load 触发 rowId=%{public}s', this.row.id);
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<void> => {
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
        this.balanceText = st.lastText;
        this.modelCountState = (await queryModels(row.id, '')).length;
        hilog.warn(DOMAIN, TAG, '赋值完成 modelCount=%{public}d balance=%{public}s',
          this.modelCountState, this.balanceText);
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, 'load 失败：%{public}s', (e as Error).message);
        this.getUIContext().getPromptAction().showToast({ message: '服务商卡刷新失败：' + (e as Error).message });
      });
  }

  // 小徽章（文字胶囊；badgeBg 半透明灰底，文字 cardDescColor；仅经 ForEach 调用——
  // 坑16，直调值参快照不重渲）
  @Builder
  Badge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  // 徽章文本清单（ForEach 数据源；顺序 = 协议/模型计数/余额；余额启用且查得时入列）
  private badges(): string[] {
    const list: string[] = [protocolLabel(this.protocol), this.modelCountState + ' 模型'];
    if (this.balanceOn && this.balanceText !== '') {
      list.push(this.balanceText);
    }
    return list;
  }

  build() {
    // Button(Normal) 包裹 = 官方原生按压蒙层（2026-09-12 UI 同形异构归一笔 1——与详情页
    // 各卡/会话卡同反馈；行内 Toggle 与四点键子组件先命中，嵌套点击关系不变）
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
          // 徽章行走 ForEach 键变重建（坑16：@Builder 值参直调 = 按值快照——状态更新时
          // Builder 内 UI 不重渲，徽章冻结在首帧值；ForEach 键 = 文本本身，文本变即重建）
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
        // 四点菜单键（dot_grid_2x2——对话页签更多键同符号；TEXTUAL 文字键形制）；挂菜单
        // 锚点 id（ProviderCardMenu TargetInfo 按此定位，菜单右缘对按钮右缘、按钮下沿弹出）
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
    // 卡宽 = 列表内容区 100%（List padding 左右 16 承收窄——总边距 = 屏宽-32vp 与
    // SessionCardItem 同款；★ 勿同时用 CARD_PANEL_WIDTH：与 List padding 叠加双重收窄
    // 成屏宽-64；反馈轮 2「卡不居中」由 List padding + 100% 组合修复）
    .width('100%')
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .onClick((): void => {
      this.onOpen(this.row);
    })
  }
}
