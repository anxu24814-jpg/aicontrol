// 服务商详情 · 顶部服务商卡（2026-08-30 详情页改版新建，自 ProviderDetailPage 域拆——
// 详情页加高级页签与保存链后直写必超 400 红线）：头像（2026-08-31 家识别——baseUrl 域名
// 命中 DeepSeek/Kimi/智谱显对应品牌 logo 圆底图（深色反白随 dark/media 同名资源自动切换），
// 其余厂商与用户新建统一 cloud 符号圆底；历史：字母 K/Z 圆底先例 2026-08-31 已随本版
// 换品牌 logo 退役。logo 侧 48×48 圆底随主题卡底色、cloud 侧强调蓝底——两底色区分见
// BrandAvatar 注释）
// + 名称 + baseUrl 副行 + 徽章行「N 模型 / 协议 / 余额（启用且查得时显示）」+ 右上角
// 小刷新键（官方 TEXTUAL 图标键，arrow_clockwise 符号表实锤坑72 口径）。
// ★ 2026-08-30 数据自持有重构（领导「手动刷新也不对，退回设置页再回才变」驱动——根因
// 定稿：@BuilderParam content（PageShell.content）内组件入参 @Prop 不随父 @State 更新
//（多轮 @Prop/onPop/刷新键修复全中此传播链；订阅式 @Link/@StorageProp 与 ForEach 行
// 增删均正常）——结构性解 = 卡不接收父派生的展示值，自身 @State + 自拉库（queryProviders/
// queryBalanceState/queryModels 一次拉全），刷新键 = 卡内自拉——组件自身状态驱动自身
// build 重渲，无任何传播链参与。表单未保存的编辑不反映到卡（卡 = 库内落库状态，
// 保存后点刷新键可见——手动刷新语义统一）。
// ★ 坑16·2026-08-30：徽章行 @Builder 值参直调 = 按值快照（官方规则——按值传参不触发
// Builder 内 UI 刷新），状态更新后徽章冻结在首帧值（「复进正常、稳定后点刷新无效」=
// 异步赋值赶在首帧前/后的两态假象）；徽章行改 ForEach（键 = 文本本身，文本变即重建
// 子项），卡整体另由父页 headEpoch 纪元键重建重拉（余额查询/获取模型/编辑模型页返回，
// 见 ProviderDetailPage 头注释）。
// ★ 其余旧注：卡挂在 if (providerId !== '') 分支——providerId 入参为创建期初值（编辑态
// 加载先设 id 再挂卡，无后续变化），普通成员即可；派生值一律卡内 @State（自拉刷新）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PROTOCOL_OPENAI, protocolLabel } from '../../common/providers/AiTypes';
import { providerAvatarAsset } from '../../common/providers/ProviderCatalog';
import {
  ModelRow, ProviderRow, queryModels, queryProviders
} from '../../common/store/ProviderDb';
import { BalanceState, queryBalanceState } from '../../common/store/ProviderBalanceDb';
import { badgeBg, cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, DETAIL_CARD_TITLE_FONTSIZE } from '../../common/Theme';

// 打点 TAG（2026-08-30「自持有仍 0 模型/余额不变」定位桩：运行日志页按 TAG 过滤——
// 赋值成功/失败/触发都有行，复现时日志可判定「拉取未成 vs 赋值后未重渲」两分支）
const DOMAIN: number = 0xD5A4;
const TAG: string = 'ProviderHeadCard';

@Component
export struct ProviderHeadCard {
  // 所属服务商 id（编辑态挂载时已定；卡自拉数据的目标行）
  providerId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 自持有展示数据（卡内自拉——刷新键/挂载时 load()；不依赖父状态传播）
  @State private name: string = '';
  @State private baseUrl: string = '';
  @State private protocol: string = PROTOCOL_OPENAI;
  @State private modelCount: number = 0;
  @State private balanceOn: boolean = false;
  @State private balanceText: string = '';
  @State private loading: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  // 自拉（挂载 + 刷新键）：服务商行（名称/URL/协议/余额开关）+ 余额文本 + 模型计数一次
  // 拉全；失败 toast 不静默（P0-1；用户可再点刷新键重试）
  private load(): void {
    hilog.warn(DOMAIN, TAG, 'load 触发 providerId=%{public}s', this.providerId);
    if (this.providerId === '' || this.loading) {
      return;
    }
    this.loading = true;
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<void> => {
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
        this.balanceText = st.lastText;
        this.modelCount = (await queryModels(this.providerId, '')).length;
        hilog.warn(DOMAIN, TAG, '赋值完成 modelCount=%{public}d balance=%{public}s',
          this.modelCount, this.balanceText);
        // （坑16 取证 toast 已删——结案后界面反馈 = 徽章自身刷新；失败 toast 保留不静默）
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, 'load 失败：%{public}s', (e as Error).message);
        this.getUIContext().getPromptAction().showToast({ message: '服务卡刷新失败：' + (e as Error).message });
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 小徽章（文字胶囊；ProviderCardItem 同款形态；仅经 ForEach 调用——坑16，直调值参
  // 快照不重渲）
  @Builder
  Badge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  // 品牌 logo 头像（家识别命中三大家时经此 Builder 渲染；仅经 if/else if 链调用）：
  // 64×64 圆底（★ 2026-09-01 详情卡对齐修订：48→64——与助手详情卡 DetailCard 头像同尺，
  // 两详情卡头像统一；logo 图内嵌 42×42：64 圆内切方形 = 64/√2 ≈ 45.25，42 留 3.25 余量
  // 四角完整落圆内——收缩比照 32/48 先例的 2/3 换算 64×(2/3)≈42.7，取 42），底随主题
  // （cardBg——浅色白/深色深灰，与 cloud 通用符号的强调蓝底区分——品牌 logo 带固有颜色
  // （DeepSeek 蓝鲸/K 字黑底、Z 字深灰反白），置于强烈蓝底会撞色，中性底方正反立辨）；
  // ★ 历史教训（2026-09-01 领导反馈）：logo 曾 48×48 等分铺满，三张 logo 内容本身几近
  // 方形贴边（蓝鲸 1024² / K 字 25.8² / Z 字 24²），方形四角超出圆底内切方形被圆头框裁切；
  // 内嵌 logo 边长须 ≤ 圆底/√2 才不裁（48 时 = 32、64 时 = 42——两数值同改）
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
    .borderRadius(32)
    .backgroundColor(cardBg(this.appColorMode))
  }

  // 徽章文本清单（ForEach 数据源；顺序 = 模型计数/协议/余额；余额启用且查得时入列）
  private badges(): string[] {
    const list: string[] = [this.modelCount + ' 模型', protocolLabel(this.protocol)];
    if (this.balanceOn && this.balanceText !== '') {
      list.push(this.balanceText);
    }
    return list;
  }

  build() {
    Row({ space: 12 }) {
      // 头像（家识别——providerAvatarAsset 按 baseUrl 域名判家）：DeepSeek/Kimi/智谱
      // 品牌 logo 圆底（BrandAvatar Builder；深浅色随 base|dark/media 同名资源自动反白，
      // 深色模式 Z/K 字自动翻白——dark/media 已落盘）或统一 cloud 符号圆底（其余厂商
      // 与用户新建默认；baseUrl 为 @State，保存后点刷新键头像随域名切换）
      // ★ $r 不支持动态拼资源名——按资源名分支写死字面量（项目先例踩坑）。单例 @Builder
      // 直调不重渲？BrandAvatar 为参数直调不触发刷新（坑 16 值参快照）——但头像资源随
      // baseUrl 仅在改域名刷新时变，整卡已随 headEpoch 纪元键重建，无独立刷新需求
      if (providerAvatarAsset(this.baseUrl) === 'deepseek_logo') {
        this.BrandAvatar($r('app.media.deepseek_logo'))
      } else if (providerAvatarAsset(this.baseUrl) === 'kimi_logo') {
        this.BrandAvatar($r('app.media.kimi_logo'))
      } else if (providerAvatarAsset(this.baseUrl) === 'zai_logo') {
        this.BrandAvatar($r('app.media.zai_logo'))
      } else {
        Stack() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(28)
            .fontColor([$r('sys.color.font_on_primary')])
        }
        .width(64)
        .height(64)
        .borderRadius(32)
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
        // 徽章行走 ForEach 键变重建（坑16：@Builder 值参直调 = 按值快照——父组件状态
        // 更新时 Builder 内 UI 不重渲，徽章冻结在首帧值；ForEach 键 = 文本本身，文本变
        // 即重建子项——订阅/状态驱动链恢复正常）
        Row({ space: 6 }) {
          ForEach(this.badges(), (text: string) => {
            this.Badge(text)
          }, (text: string): string => text)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右上角小刷新键（官方 TEXTUAL 图标键——复制键同款；点按 = 卡内自拉）
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .onClick((): void => {
        this.load();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
  }
}
