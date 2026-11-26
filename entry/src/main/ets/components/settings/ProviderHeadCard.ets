// 服务商详情 · 顶部服务商卡（自 ProviderDetailPage 域拆）：头像（家识别——baseUrl 域名命中
// DeepSeek/Kimi/智谱显示品牌 logo 底图，深色反白随 dark/media 同名资源自动切换；其余厂商与用户新建
// 统一 cloud 符号底；logo 侧底随主题卡底、cloud 侧强调蓝底）+ 名称 + baseUrl 副行 + 徽章行
//「N 模型 / 协议 / 余额（启用且查得时显示）」。
// ★ 两形态头像壳 64×64 用 64 档规范圆角 16（同助手头像，正圆已退役）——卡内距 16/16 下弧心 (32,32)
//   落卡圆角弧心的 45° 对角线（判据 = docs/规范-列表卡片与组卡.md §3.1）。
// ★ 右上角手动刷新键已退役：刷新职责 = 挂载自拉 + 纪元键重建重拉双通道（进页自动查余额，见
//   ProviderDetailPage 头注释）。
// ★ 卡底 = 淡染蓝（TINT_BRAND 档，规范 §1.3；本页唯一染色卡，作「服务商身份」视觉锚点）：几何不动
//  （CARD_PANEL_WIDTH / CARD_RADIUS 20 / padding 16），只换底色；左上深染 → 右下渐白（angle 135，满染
//   保持到 0.42；徽章行沿 135° 轴投影约 0.2~0.33 仍在满染段，保形靠徽标自身边框）。2vp 卡底色白圈包壳
//   已退役（被指「外圈白色包边」）——徽标改由 StatusBadge 自带 1vp 本档字色细边保形。
// ★ 徽章行 = StatusBadge 四档（模型数 = 强调、协议 = 弱化、余额 = 成功）；本地 Badge @Builder 退役，
//   徽标形制全站单源在 StatusBadge。
// ★ 卡底透明度档位为显式订阅（PREF_CARD_ALPHA_LEVEL_KEY）：淡染卡要与邻卡同档，用户拖滑轨时本卡
//   必须即时跟随，否则会「邻卡变透、这张还是实色」。
// ★ 数据自持有：@BuilderParam content（PageShell.content）内组件入参 @Prop 不随父 @State 更新
//  （多轮修复全中此传播链；订阅式 @Link/@StorageProp 与 ForEach 行增删正常）——卡不接收父派生展示值，
//   自身 @State + 自拉库（queryProviders/queryBalanceState/queryModels 一次拉全），自拉时机 = 挂载。
//   表单未保存的编辑不反映到卡（卡 = 库内落库状态，保存返回后纪元键整卡重建可见）。
//   例外 = 余额文本经 @ObjectLink 通道（ProviderBalanceChannel，余额防闪笔）：订阅式 @ObjectLink
//   属上方已预留的正常传播面——父页查询成功细粒度写入、徽章行实参位直读刷新（卡内自拉仍兜底）。
// ★ 坑16：徽章行 @Builder 值参直调 = 按值快照（状态更新后徽章冻结在首帧值）——徽章行改 ForEach
//  （键 = 文本 + 档位，任一变即重建子项），卡整体另由父页 headEpoch 纪元键重建重拉。
// ★ 卡挂在 if (providerId !== '') 分支——providerId 为创建期初值（无后续变化），普通成员即可；
//   派生值一律卡内 @State（自拉刷新）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PROTOCOL_OPENAI, protocolLabel } from '../../common/providers/AiTypes';
import { providerAvatarAsset } from '../../common/providers/ProviderCatalog';
import {
  ModelRow, ProviderRow, queryModels, queryProviders
} from '../../common/store/ProviderDb';
import { BalanceState, queryBalanceState } from '../../common/store/ProviderBalanceDb';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../../common/AppPreferences';
import {
  CARD_PANEL_WIDTH, DETAIL_CARD_TITLE_FONTSIZE, TINT_BRAND, TINT_GRADIENT_ANGLE, cardBg,
  cardBorderColor, cardDescColor, cardTitleColor, tintCardBg, tintCardGradientColors, CARD_RADIUS
} from '../../common/Theme';
import { BadgeTone, StatusBadge } from '../StatusBadge';

// 打点 TAG（自持有「0 模型/余额不变」定位桩：运行日志页按 TAG 过滤——赋值成功/失败/触发都有行）
const DOMAIN: number = 0xD5A4;
const TAG: string = 'ProviderHeadCard';

// 余额展示通道（@Observed/@Track 细粒度刷新，先例 ChatListAnchorJudge）：页面与卡共持同一
// 实例；写点 = 页面 loadBalanceEntry/queryBalance 与卡内 load（挂载自拉）；卡内徽章 build
// 直读 text，改值即重渲（@Track 直驱），查询成功零整卡重建。定义在本件 = 卡是唯一 UI
// 消费方、页面 import 引用（防环，坑50）。
@Observed
export class ProviderBalanceChannel {
  // 当前余额展示文本（'' = 无余额徽章）
  @Track text: string = '';
  // 同值不写（余额未变时进页/查询零冗余刷新）
  set(next: string): void {
    if (next === this.text) {
      return;
    }
    this.text = next;
  }
}

// 徽章行条目（ForEach 数据源；tone 与 text 同进键——任一变化即重建子项，坑16）
interface HeadBadgeSpec {
  text: string;
  tone: number;
}

@Component
export struct ProviderHeadCard {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  // 所属服务商 id（编辑态挂载时已定；卡自拉数据的目标行）
  providerId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（显式订阅建立 UI 依赖——淡染卡与邻卡同档，见头注释）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 自持有展示数据（卡内自拉——挂载时 load()；不依赖父状态传播）
  @State private name: string = '';
  @State private baseUrl: string = '';
  @State private protocol: string = PROTOCOL_OPENAI;
  @State private modelCount: number = 0;
  @State private balanceOn: boolean = false;
  // 余额展示通道（父页持实例经构造传入；@ObjectLink 订阅 @Track 字段，余额文本经 build 实参位
  // 直读刷新——见徽章行 ForEach 位注释；卡内 load 自拉是重建后兜底写点）
  @ObjectLink balanceChannel: ProviderBalanceChannel;
  @State private loading: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  // 自拉（挂载）：服务商行 + 余额文本 + 模型计数一次拉全；失败 toast 不静默（P0-1，重进页面即重试）
  private load(): void {
    hilog.warn(DOMAIN, TAG, 'load 触发 providerId=%{public}s', this.providerId);
    if (this.providerId === '' || this.loading) {
      return;
    }
    this.loading = true;
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<void> => {
        if (this.departed) {
          return;
        }
        const row: ProviderRow | undefined =
          rows.find((item: ProviderRow): boolean => item.id === this.providerId);
        if (row === undefined) {
          hilog.warn(DOMAIN, TAG, '行不存在（可能已删）providerId=%{public}s', this.providerId);
          return;
        }
        this.name = row.name;
        this.baseUrl = row.baseUrl;
        this.protocol = row.protocol;
        this.balanceOn = row.balanceEnabled;
        const st: BalanceState = await queryBalanceState(this.providerId);
        if (this.departed) {
          return;
        }
        // 兜底写点：卡重建（模型/余额配置触发纪元键）后通道文本自动对齐 DB 现值
        this.balanceChannel.set(st.lastText);
        this.modelCount = (await queryModels(this.providerId, '')).length;
        hilog.warn(DOMAIN, TAG, '赋值完成 modelCount=%{public}d balance=%{public}s',
          this.modelCount, this.balanceChannel.text);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        hilog.error(DOMAIN, TAG, 'load 失败：%{public}s', (e as Error).message);
        this.getUIContext().getPromptAction().showToast({ message: '服务卡读取失败：' + (e as Error).message });
      })
      .finally((): void => {
        if (this.departed) {
          return;
        }
        this.loading = false;
      });
  }

  // 品牌 logo 头像（家识别命中三大家时经此 Builder 渲染；仅经 if/else if 链调用）：64×64 圆角方形
  // 16（45° 同心判据见头注释）；内嵌 logo 42×42——三张 logo 内容近方形贴边，曾有 48×48 铺满被圆头
  // 框裁四角的历史教训；圆角 16 壳下 42 安全内接（角点距最近弧心 7.1 < 16），视觉余量 11，勿再缩。
  // 底随主题卡底（品牌 logo 带固有颜色，置强烈蓝底会撞色；中性底方正反立辨）
  @Builder
  BrandAvatar(img: Resource) {
    Stack() {
      Image(img)
        .width(42)
        .height(42)
        .objectFit(ImageFit.Contain)
    }
    .width(64)
    .height(64)
    // 顶部对齐（不吃 Row 的垂直居中）——右侧三行内容高约 72 > 头像 64，居中会让头像上距 20、圆心
    // 离线 4vp；顶对齐后上距 = 左距 = 16，圆心 (48,48) 与卡圆角弧心 (20,20) 共 45° 对角线。代价 = 头像
    // 下沿比徽章行底高 8（视觉重心略偏上）；真机若读作偏上，首选把右列压到 64 同高，次选头像增至 72
    // 并同改圆角 18，禁改回居中
    .alignSelf(ItemAlign.Start)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
  }

  // 徽章清单（ForEach 数据源；顺序 = 模型计数/协议/余额；余额启用且查得时入列）。四档色：模型数 =
  // 强调（计数徽，本卡唯一「有数」的徽章）、协议 = 弱化（信息标签，不做语义）、余额 = 成功（正向状态）
  // ★ 余额文本收参纯函数化（审读裁定 1）：方法体内禁读通道字段，文本经 build 实参位直读传入
  //（this.balanceOn/modelCount/protocol 是本组件 @State，方法内读取合法）
  private badges(balanceText: string): HeadBadgeSpec[] {
    const list: HeadBadgeSpec[] = [
      { text: this.modelCount + ' 模型', tone: BadgeTone.EMPHASIS },
      { text: protocolLabel(this.protocol), tone: BadgeTone.WEAK }
    ];
    if (this.balanceOn && balanceText !== '') {
      list.push({ text: balanceText, tone: BadgeTone.SUCCESS });
    }
    return list;
  }

  build() {
    Row({ space: 12 }) {
      // 头像（providerAvatarAsset 按 baseUrl 域名判家）：三大家品牌 logo 走 BrandAvatar Builder，
      // 其余厂商与用户新建走统一 cloud 符号底（baseUrl 为 @State，保存返回后纪元键整卡重建随域名切换）
      // ★ $r 不支持动态拼资源名——按资源名分支写死字面量；BrandAvatar 参数直调不重渲（坑16 值参快照），
      // 但头像资源仅在改域名时变，整卡已随 headEpoch 重建，无独立刷新需求
      if (providerAvatarAsset(this.baseUrl) === 'deepseek_logo') {
        this.BrandAvatar($r('app.media.deepseek_logo'))
      } else if (providerAvatarAsset(this.baseUrl) === 'kimi_logo') {
        this.BrandAvatar($r('app.media.kimi_logo'))
      } else if (providerAvatarAsset(this.baseUrl) === 'zai_logo') {
        this.BrandAvatar($r('app.media.zai_logo'))
      } else {
        // 通用 cloud 符号底：64 档圆角方形 16 + 顶部对齐，与 BrandAvatar 同判据（45° 同心笔）
        Stack() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(28)
            .fontColor([$r('sys.color.font_on_primary')])
        }
        .width(64)
        .height(64)
        .alignSelf(ItemAlign.Start)
        .borderRadius(16)
        .backgroundColor($r('sys.color.ohos_id_color_emphasize'))
      }
      Column({ space: 4 }) {
        Text(this.name)
          .fontSize(DETAIL_CARD_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.baseUrl)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        // 徽章行走 ForEach 键变重建（坑16：本地 @Builder 值参直调 = 按值快照，徽章冻结在首帧值；
        // 键 = 文本 + 档位，任一变即重建子项）。StatusBadge 的 text/tone 是普通成员，刷新责任在调用方
        // ★ 余额文本经实参位直读通道 this.balanceChannel.text（@Track 直驱官方明示路径）；禁退回
        //  方法体内读通道 + ForEach 键 diff 双跳——该组合无官方明示（2026-11-02 审读裁定 1）
        Row({ space: 6 }) {
          ForEach(this.badges(this.balanceChannel.text), (badge: HeadBadgeSpec) => {
            // 徽标自带 1vp 本档字色细边（StatusBadge），淡染底上靠同色轮廓保形，不再垫卡底色
            StatusBadge({ text: badge.text, tone: badge.tone })
          }, (badge: HeadBadgeSpec): string => badge.text + '|' + badge.tone)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    // 淡染蓝卡底（§1.3）：左上满染 → 右下渐白（angle 135，满染保持到 0.42）；徽章行靠 StatusBadge
    // 1vp 同色细边保形；backgroundColor 兜底（渐变与光感/档位冲突时仍读作淡染卡）
    .backgroundColor(tintCardBg(TINT_BRAND, this.appColorMode, this.cardAlphaLevel))
    .linearGradient({
      angle: TINT_GRADIENT_ANGLE,
      colors: tintCardGradientColors(TINT_BRAND, this.appColorMode, this.cardAlphaLevel)
    })
    // 发丝描边 = 染色卡的边界补偿：浅色页底与淡染终端仅 1.045 对比，不描边时卡右半会「陷进」页底
    //（非投影替代——§1.4 否决抬升卡）；深色档页底与淡染底已有 1.22，此线同样只是勾边
    .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
