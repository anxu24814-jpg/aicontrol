// 聊天页模型选择面板：三站点共用的对话模型选择半模态（对话页标题栏 / 助手编辑页「模型设置」/
// 设置页「功能模型」；对外接口见下方成员，宿主零改动）。
// ★ 档位（决明拍板「默认展开全屏 + 取消半屏态 + 全屏下拉直接收起」）：档位是**宿主侧
//   bindSheet 参数**，不在本件内部——三站点一律传 KimiSheetCommon.DETENTS_FULL（= [LARGE]
//   全屏单挡位：开局全屏、下拉无中间停靠直达关闭）；改档位改三处宿主（值源同一常量，
//   改常量即三处同效）。
// · 布局自上而下：**搜索框在标题栏下方带（bottomBuilder，吸顶）** → 筛选 chip 行 → 当前选择
//   行卡 → 服务商分组（分组标题卡外 + 同服务商模型合并一张组卡，规格见 ModelGroupCard 注释）。
//   ★ 2026-10-31 搜索吸顶笔（决明「搜索框合入标题自定义区吸顶、走光感」）：原判据「全部在
//   滚动流内、不吸顶」针对的是**内容区固定块**——它会把 Scroll 起点顶下去，标题栏背后永远
//   没内容可透、渐变模糊空转（规范-半模态 §2）；迁入标题栏自定义区不属该形态：带属标题栏
//   自身，模糊/材质/滚动感知三件原样，滚动内容仍经 clip(false) 穿透到带下。带件 = SearchTopBand
//   （四库页同源，REGULAR 恒光感），带高 = segmentBandParams（下移 8 + 40 = 48）。
// · 当前选择行卡：与功能模型页八卡同走 resolveModelDisplayLabel 单源——行已删 = 未选择，
//   不回退 modelId 原文（原「清单内反查不到回退原文」口径作废：清单只含启用行，会把停用/
//   删除/悬空伪装成「仍选着」）；已停用目标由数据面清空两键（停用即解绑 + 启动/导入后
//   对账），本卡不另判启用态。
// · 刷新责任在调用方（组卡规范 §4.1 真机报障根因）：外层分组键 = modelGroupKey 单源
//   （providerId | 使用中 | listEpoch | 可见行集合签名，在 ModelPickFilter）——收藏/选中态
//   变化自增纪元 → 整组重建；内层行键含 favorite/selected 双态；禁只靠内层键承担刷新、
//   禁 @Prop 承载（坑16 家族）。★ 可见集必须进键（真机报障：ForEach 键不变即复用旧组件，
//   切分段/输关键词只换数组不换键，组卡沿用旧快照）。
// · chip 筛选（决明拍板，取代收藏分段 + SegmentBar）：filterKey 三态 + 官方 Chip 横滑行，
//   细节见 filterKey / FilterChipRow 注释。
// · 收藏写读链：写库成功才更新内存行 + 纪元自增（比乐观更新少一条回滚路径）；读 = 每次
//   打开重查（面板随 bindSheet 显隐重建，无跨面板缓存）。本机语义——分享/备份零改动（全量
//   备份 SELECT * 自动往返，单家分享不携带）。
// · 筛选/空态：关键词与收藏段双层内存过滤（visibleSections 派生，不重查库无防抖——P1-3
//   零冗余等待）；空态文案 = pickEmptyHint 派生（首拉在途不显——loading 闸），读取失败走
//   hintText 通道。
// · 数据 = ProviderDb（服务商详情页维护的清单；仅启用服务商 + 对话型模型）——面板只读不拉
//   网络（GET /models 在服务商详情页，职责分离）。
// · 壳形态 = KimiFullInputSheet 同款半模态三件套（HdsNavigation MODAL 标题栏 +
//   sheetTitleBarOptions 同源〔本笔起带第 7 参搜索带〕+ bindToScrollable 滚动感知 + 底部安全区延伸）。
// · 选中/使用中刷新 = ForEach 键并入状态（item 内读 @StorageProp 不触发项重建，键含态才
//   重建——ModelFetchSheet 同款正解；「键不变即复用旧组件」机理见上条 ★）。
import { CARD_RADIUS } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { Chip, LengthMetrics, TextModifier } from '@kit.ArkUI';
import { HdsListItemCard, HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  capLabels, effectiveCaps, ModelRow, ProviderRow,
  queryModels, queryProviders, setModelFavorite
} from '../../common/store/ProviderDb';
// 「当前选择」显示名单源解析器（旧口径作废判据见文件头）
import { ModelDisplayLabel, resolveModelDisplayLabel } from '../../common/store/ModelDisplayLabel';
import {
  IMMERSIVE_LEVEL_KEY, segmentBandParams
} from '../../common/ImmersiveLevel';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_GAP, cardBg, cardBorderColor, cardDescColor, cardTitleColor
} from '../../common/Theme';
import {
  FAV_FILTER_KEY, modelGroupKey, modelMatchesFilter, normalizeModelFilterKeyword,
  pickEmptyHint, sectionUnderFilter
} from '../../common/providers/ModelPickFilter';
import { sheetTitleBarOptions } from './KimiSheetCommon';
// 搜索带承载件（页面四库页同件——标题栏下方带搜索框恒 REGULAR 光感）
import { SearchTopBand } from '../SearchTopBand';
// 全站状态词徽标形制单源（分节头「使用中」= 实底胶囊）
import { StatusBadge } from '../StatusBadge';

// 筛选 chip 行高：官方资源 chip_normal_height = 36vp（实读官方资源，即 chip 完整外框高）
// **必须显式给**：横向 Scroll 在 Column（无固定高）内不设高度会按剩余空间撑开，把 chip 行
// 拉成大片空白
const FILTER_CHIP_HEIGHT: number = 36;

// 分组间距：组间 SECTION_GAP / 组内 CARD_SPACING（Theme 常量单源），首组顶部间距由外层 Column padding 提供

// 面板数据节（服务商 + 其对话模型；加载侧组装，筛选后为副本）
interface ProviderSection {
  provider: ProviderRow;
  models: ModelRow[];
}

@Component
export struct ModelPickerSheet {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 选中回调（数据与编排在父页，本组件不落库）
  onPick: (providerId: string, modelId: string) => void = () => {
  };
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主注入——列表尾部占位，坑66：末卡滚到底停在导航条上方；
  // 缺省 0 = 无占位）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 当前选择（**一律由调用方直传**——三站点「当前」语义不同：对话页 = 会话级覆盖 ?? 助手
  // 绑定 ?? 全局默认、助手「模型设置」页 = 该助手绑定、功能模型页 = 该槽位绑定；'' = 未指定
  // → 全列表无打勾；普通成员直传 = 打开时刻快照，面板每次开重建、选中即关，无滞后窗口）。
  // ★ 勿再读全局 active 两键（已退役）——「读一个全局当前模型」正是当年会话内选择被写成
  // 全局默认 bug 的根因形态
  selProviderId: string = '';
  selModelId: string = '';
  // 系统颜色模式（卡底深浅色随动）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private sections: ProviderSection[] = [];
  @State private hintText: string = '';
  // 首拉完成闸：true = 查询在途——空态提示行不显示（防「暂无可用模型」闪现）；查询落定
  //（成功/失败）置 false
  @State private loading: boolean = true;
  // 搜索关键词（$$ 双向绑定实时过滤；空串 = 不过滤）
  @State private keyword: string = '';
  // 筛选 chip 单值档（取代 favSegment 收藏分段）：'' = 全部 / FAV_FILTER_KEY = 收藏 /
  // 服务商 id = 厂商档——语义与组级判定单源 ModelPickFilter；再点选中 chip = 回全部
  //（toggle）；切换内存过滤不重查库
  @State private filterKey: string = '';
  // 刷新纪元（组卡规范 §4.1）：收藏/选中态变化自增 → 外层分组键变重建 → 行内爱心与打勾
  // 即时刷新（内层键单独承担不了跨组重建）
  @State private listEpoch: number = 0;
  // 「当前选择」显示名：resolveModelDisplayLabel 查全库（不看启用态、不依赖已加载分组），
  // 查不到 = missing = 未选择；异步落定前按 modelId 兜底（与功能模型页八卡同窗口口径）
  @State private pickLabel: string = '';
  @State private pickMissing: boolean = false;
  private listScroller: Scroller = new Scroller();

  // 行选中判定（打勾渲染；当前值由调用方直传，见 selProviderId 注释）
  private isSelected(providerId: string, modelId: string): boolean {
    return this.selProviderId === providerId && this.selModelId === modelId;
  }

  // 服务商「使用中」徽章判定（分节头；口径同行选中判定）
  private isProviderInUse(providerId: string): boolean {
    return this.selProviderId === providerId;
  }

  // 当前选择两键（单口径：调用方直传，语义见 selProviderId 注释）
  private currentProviderId(): string {
    return this.selProviderId;
  }

  private currentModelId(): string {
    return this.selModelId;
  }

  // 当前选择主文案（三态口径单源见文件头「当前选择行卡」条）：两键含空或 pickMissing =
  // 「未选择」；命中 = 显示名（name 空则 modelId）
  private currentPickPrimary(): string {
    const providerId: string = this.currentProviderId();
    const modelId: string = this.currentModelId();
    if (providerId === '' || modelId === '' || this.pickMissing) {
      return '未选择';
    }
    return this.pickLabel !== '' ? this.pickLabel : modelId;
  }

  // 当前选择副文案（'' = 无副行）：仅命中态显示「服务商名 · 模型 ID」
  private currentPickSecondary(): string {
    const providerId: string = this.currentProviderId();
    const modelId: string = this.currentModelId();
    if (providerId === '' || modelId === '') {
      return '';
    }
    const section: ProviderSection | undefined =
      this.sections.find((item: ProviderSection): boolean => item.provider.id === providerId);
    if (section === undefined) {
      return '';
    }
    const model: ModelRow | undefined =
      section.models.find((item: ModelRow): boolean => item.modelId === modelId);
    if (model === undefined) {
      return '';
    }
    return section.provider.name + ' · ' + model.modelId;
  }

  // 未选择判定（当前选择行卡灰字/默认色分治）：两键含空或解析不可用
  private currentPickUnselected(): boolean {
    return this.currentProviderId() === '' || this.currentModelId() === '' || this.pickMissing;
  }

  // 模型行能力标签文本（副行；'' = 不显该行——行高随之分档）。必须走 effectiveCaps
  //（派生语义单源，禁直读 model.caps）
  private capText(model: ModelRow): string {
    return capLabels(effectiveCaps(model)).join(' · ');
  }

  // 可见分节（build 内派生）：先组级 chip 筛选（sectionUnderFilter 单源），再收藏行级过滤，
  // 再关键词过滤（组内空则丢组）；不动排序
  private visibleSections(): ProviderSection[] {
    const keyword: string = normalizeModelFilterKeyword(this.keyword);
    const favOnly: boolean = this.filterKey === FAV_FILTER_KEY;
    const result: ProviderSection[] = [];
    for (const section of this.sections) {
      if (!sectionUnderFilter(section.provider.id, this.filterKey)) {
        continue;
      }
      let models: ModelRow[] = section.models;
      if (favOnly) {
        models = models.filter((model: ModelRow): boolean => model.favorite);
      }
      if (keyword !== '') {
        models = models.filter((model: ModelRow): boolean =>
          modelMatchesFilter(model.name, model.modelId, section.provider.name, keyword));
      }
      if (models.length > 0) {
        result.push({ provider: section.provider, models: models });
      }
    }
    return result;
  }

  // 空态提示行文案（'' = 不显；读取失败走顶部 hintText 通道，本行只管无可见行三态）
  private emptyHintText(): string {
    if (this.hintText !== '' || this.loading) {
      return '';
    }
    let sourceCount: number = 0;
    let visibleCount: number = 0;
    for (const section of this.sections) {
      sourceCount += section.models.length;
    }
    for (const section of this.visibleSections()) {
      visibleCount += section.models.length;
    }
    return pickEmptyHint(sourceCount, visibleCount,
      normalizeModelFilterKeyword(this.keyword), this.filterKey === FAV_FILTER_KEY);
  }

  // 收藏切换（写库成功才更新内存 + 纪元自增；失败 toast 不静默——P0-1）
  private toggleFavorite(model: ModelRow): void {
    const next: boolean = !model.favorite;
    setModelFavorite(model.id, next)
      .then((): void => {
        model.favorite = next;
        this.listEpoch++;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '收藏保存失败：' + (e as Error).message
        });
      });
  }

  aboutToAppear(): void {
    // 显示名解析（字段口径见 pickLabel 注释）；查询失败按 modelId 兜底（展示增强不阻断面板）
    if (this.selProviderId !== '' && this.selModelId !== '') {
      resolveModelDisplayLabel(this.selProviderId, this.selModelId)
        .then((state: ModelDisplayLabel): void => {
          if (this.departed) {
            return;
          }
          this.pickLabel = state.label;
          this.pickMissing = state.missing;
        })
        .catch((_e: Object): void => {
          if (this.departed) {
            return;
          }
          this.pickLabel = this.selModelId;
        });
    }
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<ProviderSection[]> => {
        // 逐启用服务商拉对话模型组装分节（用户手建小数据集，条目级循环查询开销可忽略）；
        // 停用模型不列（启停开关消费端之一——仅数据过滤，显示形态不变）
        const sections: ProviderSection[] = [];
        for (const provider of rows) {
          if (!provider.enabled) {
            continue;
          }
          const models: ModelRow[] = (await queryModels(provider.id, 'chat'))
            .filter((row: ModelRow): boolean => row.enabled);
          if (models.length > 0) {
            sections.push({ provider: provider, models: models });
          }
        }
        return sections;
      })
      .then((sections: ProviderSection[]): void => {
        if (this.departed) {
          return;
        }
        this.sections = sections;
        this.loading = false;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = '模型清单读取失败：' + (e as Error).message;
        this.loading = false;
      });
  }

  build() {
    HdsNavigation() {
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样；Scroll+Column 嵌套分区——组间
      // SECTION_GAP / 组内 CARD_SPACING 分级（clip(false) + TopStart + Spring 见规范-半模态 §2）
      Scroll(this.listScroller) {
        Column({ space: SECTION_GAP }) {
          // ── 筛选 chip 行（全部/收藏 + 服务商档，单选横滑，取代分段胶囊）──
          this.FilterChipRow()
          // ── 当前选择（分组标题 + 行卡；纯信息展示不挂点击）──
          Column({ space: CARD_SPACING }) {
            this.CurrentPickHeader()
            this.CurrentPickCard()
          }
          .width('100%')
          if (this.hintText !== '') {
            Text(this.hintText)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width(CARD_PANEL_WIDTH)
          }
          if (this.emptyHintText() !== '') {
            Text(this.emptyHintText())
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
          // ── 服务商分组（分组标题卡外 + 组卡；外层键含纪元 + 可见集 = 刷新责任在调用方）──
          ForEach(this.visibleSections(), (section: ProviderSection) => {
            Column({ space: CARD_SPACING }) {
              this.SectionHeader(section)
              this.ModelGroupCard(section)
            }
            .width('100%')
          }, (section: ProviderSection): string => modelGroupKey(section.provider.id,
            this.isProviderInUse(section.provider.id), this.listEpoch,
            section.models.map((model: ModelRow): string => model.id)))
          // 尾部安全区让位（末卡滚到底不贴导航条；bottomInset=0 时高度 0 无占位）
          Row()
            .width('100%')
            .height(Math.max(0, this.bottomInset - CARD_SPACING))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    // 半模态三件套（KimiFullInputSheet 同款规格）+ 标题栏下方搜索带（第 7 参；带高算式
    // 单源 segmentBandParams——带属标题栏、内容零手算让位，见本件头注释）
    .titleBar(sheetTitleBarOptions('选择模型', '服务商 · 模型',
      (): void => {
        this.onClose();
      }, this.immersiveLevel, undefined, undefined,
      segmentBandParams((): void => {
        this.SearchBand();
      })))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.listScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }

  // 「当前选择」分组标题（规格同分节头 SectionHeader，规范-半模态 §3）
  @Builder
  CurrentPickHeader() {
    Row() {
      Text('当前选择')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // 当前选择行卡（HDS 官方列表卡；纯信息展示不挂 onClick——避免
  // 「按得下去没反应」；HDS 卡宽度官方语义 = 容器 −32，勿挂 .width()）。主副行三态见
  // currentPickPrimary/currentPickSecondary；长名省略号截断
  @Builder
  CurrentPickCard() {
    HdsListItemCard({
      textItem: {
        primaryText: {
          text: this.currentPickPrimary(),
          modifier: this.currentPickUnselected() ?
            new TextModifier().fontColor(cardDescColor()) : undefined
        },
        secondaryText: this.currentPickSecondary() !== '' ?
          { text: this.currentPickSecondary() } : undefined
      },
      cardBorderRadius: CARD_RADIUS,
      cardBackgroundColor: cardBg(this.appColorMode)
    })
  }

  // 搜索带（标题栏下方自定义区承载，吸顶）：形制/材质/几何单源 = SearchTopBand（四库页同件
  // ——官方 Search + REGULAR 恒光感 + 整带命中透传），本件零自绘底色/材质。关键词经 $$ 双向
  // 绑定回流本组件 @State，visibleSections() 派生过滤（无提交动作、不挂 defaultFocus——进面板
  // 即弹键盘会遮列表）。★ 2026-10-31 起本带取代内容区 SearchRow（白底口径随迁退役：带在标题栏
  // 生效区内，输入族按 REGULAR 恒光感单源，见规范-行内按钮与光感 §2）
  @Builder
  SearchBand() {
    SearchTopBand({ keyword: $keyword, placeholder: '筛选模型' })
  }

  // 筛选 chip 选中底色（灰白系拍板）：浅 #FFFFFF 实底 / 深 #26FFFFFF 亮胶囊，弃官方默认
  // 强调蓝 activated 底（全站「蓝底突兀」拍板）；官方无选中底深浅分治资源，手写三元
  private chipActiveBg(): ResourceColor {
    const dark: boolean = this.appColorMode ===
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return dark ? '#26FFFFFF' : '#FFFFFF';
  }

  // 单枚筛选 chip（官方 Chip）：allowClose 默认 true **必须显式传 false**（否则每 chip 带
  // 关闭叉）；未选底不传 = 官方默认灰；再点选中档一次 = 回全部（toggle）
  @Builder
  FilterChip(chipKey: string, text: string) {
    Chip({
      label: {
        text: text,
        activatedFontColor: $r('sys.color.font_primary')
      },
      activated: this.filterKey === chipKey,
      allowClose: false,
      activatedBackgroundColor: this.chipActiveBg(),
      onClicked: (): void => {
        this.filterKey = this.filterKey === chipKey ? '' : chipKey;
      }
    })
  }

  // 筛选 chip 行：全部/收藏 + 服务商档（sections 派生——loading 期只显前两枚），单选。官方
  // Chip **无内置横滑无 overflow 处理**（d.ets 核实），外包横向 Scroll 承接；fadingEdge
  // 渐隐软化边缘裁切（决明拍板自然滚动 + 渐隐、弃 scrollSnap 吸附）。服务商 chips 键含
  // 选中态（坑44/80：activated 不进键 = 切筛选时高亮静默冻结）；行内间距 8 = ChipGroup
  // 官方默认 itemSpace 同值
  @Builder
  FilterChipRow() {
    Scroll() {
      Row({ space: 8 }) {
        this.FilterChip('', '全部')
        this.FilterChip(FAV_FILTER_KEY, '收藏')
        ForEach(this.sections, (section: ProviderSection) => {
          this.FilterChip(section.provider.id, section.provider.name)
        }, (section: ProviderSection): string =>
          section.provider.id + '|' +
            (this.filterKey === section.provider.id ? '1' : '0'))
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(16) })
    .width(CARD_PANEL_WIDTH)
    .height(FILTER_CHIP_HEIGHT)
  }

  // 分节头（服务商名 + 使用中徽章 + 模型数；标题规格 = 粗体 15fp + 左缘 16 对卡缘，规范-
  // 半模态 §3；上下间距交容器 space）。「使用中」= 实底胶囊 StatusBadge；未使用仍是灰胶囊
  // 计数（元数据非状态词）
  @Builder
  SectionHeader(section: ProviderSection) {
    Row({ space: 8 }) {
      Text(section.provider.name)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isProviderInUse(section.provider.id)) {
        StatusBadge({ text: '使用中' })
      } else {
        Text(section.models.length + ' 模型')
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  // 组卡（同一服务商的模型合并一张卡；官方实测规格 = 卡宽 CARD_PANEL_WIDTH + 圆角
  // CARD_RADIUS + 上下 padding 4 + 行缩进 = 外包 Column padding 4〔禁 margin 写法〕+
  // 行高有副行 64 无副行 56 + 行间 0.5vp 细线左 8 右 4 末行不显 + 无前导图标；内层行键含
  // 收藏/选中双态——跨组刷新靠外层纪元键，见 listEpoch 注释）
  @Builder
  ModelGroupCard(section: ProviderSection) {
    Column() {
      ForEach(section.models, (model: ModelRow, index: number) => {
        this.ModelRowItem(section.provider.id, model)
        if (index < section.models.length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .margin({ left: 8, right: 4 })
        }
      }, (model: ModelRow): string =>
        model.id + '|' + (model.favorite ? '1' : '0') + '|' +
          (this.isSelected(section.provider.id, model.modelId) ? '1' : '0'))
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 4 })
  }

  // 模型行（两区并列不嵌套，规范-列表卡片与组卡 §4.2）：左侧可点区 = 选模型（标题 + 能力
  // 标签副行）；右侧键区 = 收藏爱心 + 选中打勾（兄弟节点，禁嵌套进左区——点击双触发）
  @Builder
  ModelRowItem(providerId: string, model: ModelRow) {
    Column() {
      Row() {
        // 左侧可点区（整块命中：layoutWeight 撑满 + 满高 + onClick）
        Column({ space: 2 }) {
          Text(model.name !== '' ? model.name : model.modelId)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.capText(model) !== '') {
            Text(this.capText(model))
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .height('100%')
        .onClick((): void => {
          this.onPick(providerId, model.modelId);
        })
        // 选中打勾（纯视觉不挂点击；未选中不占位）——决明真机反馈：勾在爱心**左侧**、爱心
        // 恒为行尾最右（原勾在右侧会把心形挤左、跨行对不齐）
        if (this.isSelected(providerId, model.modelId)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([$r('sys.color.comp_background_emphasize')])
        }
        // 收藏键（行内图标键 TEXTUAL 无底；未收藏 heart / 已收藏 heart_fill，两色官方语义
        // 色非自绘；恒为行尾最右键贴卡右缘）
        Button() {
          SymbolGlyph(model.favorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(20)
            .fontColor([model.favorite ? $r('sys.color.font_emphasize') :
              $r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .onClick((): void => {
          this.toggleFavorite(model);
        })
      }
      .width('100%')
      .height(this.capText(model) !== '' ? 64 : 56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .padding({ left: 4, right: 4 })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
