// 聊天页模型选择面板（2026-08-30 服务商管理域新增，待接入清单第 1 件「模型选择」落地：
// 原标题栏模型入口点击占位 toast 换真面板）：三站点共用的对话模型选择半模态（对话页
// 标题栏 / 助手编辑页「模型设置」/ 设置页「功能模型」——对外接口见下方成员，宿主零改动）。
// ★ 2026-09-15 档位（决明指令：「默认展开全屏 + 取消半屏态 + 全屏下拉直接收起」）：档位是
// **宿主侧 bindSheet 参数**，不在本件内部——三站点一律传 KimiSheetCommon.DETENTS_FULL
// （= [LARGE] 全屏单挡位：开局全屏、下拉无中间停靠直达关闭）。改档位改那三处宿主（值源同一
// 常量，改常量即三处同效）；本件内容层不受影响。
// ★ 2026-09-08 面板重构（决明指令「参照图片，对模型选择的半模态进行功能优化」+ 四项拍板，
// 任务书-模型选择半模态优化-20260908）：自上而下（全部在滚动流内，不做吸顶——顶部固定区
// 会让滚动内容挡在标题栏外、渐变模糊失去采样内容，规范-半模态 §2）=
//   当前选择行卡（手选/绑定值在已加载清单内反查展示）
//   → 官方 Search 实时筛选 → 「全部/收藏」分段
//   → 服务商分组：分组标题（卡外）+ 组卡（同服务商模型合并一张卡）
// · 组卡规格（规范-列表卡片与组卡 §3 官方实测表 + §4.2 两区并列不嵌套）：卡宽
//   CARD_PANEL_WIDTH / 圆角 16 / 上下 padding 4 / 行缩进 = 外包 Column padding 4（禁 margin
//   写法，§5 红线 1）/ 行高有副行 64 无副行 56 固定分档 / 分割线 0.5vp 左 8 右 4 末行不显 /
//   无前导图标（不做厂商头像）；行尾 = 选中打勾（仅选中态、纯视觉不挂点击）+ 收藏爱心键
//   （TEXTUAL 无底）——打勾在爱心**左侧**，爱心恒为行尾最右键（2026-09-08 决明真机反馈：
//   原打勾在爱心右侧会把心形挤左、跨行对不齐）；左侧文本区 layoutWeight(1) + 两行文本
//   maxLines(1) 省略号，长名/长能力标签只截断不挤走右侧键。
// · 刷新责任在调用方（组卡规范 §4.1 真机报障根因）：外层分组键 = `modelGroupKey`（providerId
//   | 使用中 | listEpoch | 可见行集合签名，单源在 ModelPickFilter）——收藏/选中态变化自增
//   纪元 → 整组重建；内层行键含 favorite/selected 双态；禁只靠内层键承担刷新、禁 @Prop 承载
//   （坑16 家族）。★ 可见集必须进键（2026-09-09 决明真机报障：收藏段显示整个服务商的组卡、
//   未收藏行也在里面——ForEach 键不变即复用旧组件，切分段/输关键词只换数组不换键，组卡
//   沿用旧快照不重建）。
// · 收藏写读链：爱心键 onClick → setModelFavorite → 写库成功才更新内存行 + listEpoch++
//   （比乐观更新少一条回滚路径）；失败 toast「收藏保存失败」（P0-1 不静默）。读 = 每次打开
//   重查（面板随 bindSheet 显隐重建 → 天然无跨面板缓存）。本机语义——ProviderShare /
//   ExportImport 零改动（全量备份靠 SELECT * 自动往返，单家分享不携带）。
// · 筛选/空态：关键词与收藏段双层内存过滤（visibleSections 派生，不重查库、无防抖——
//   P1-3 零冗余等待）；空态文案 = ModelPickFilter.pickEmptyHint 派生（行内提示行，首拉
//   在途不显——loading 闸），读取失败沿用 hintText 通道。
// 数据 = ProviderDb（服务商详情页「获取模型/添加」维护的清单；仅启用服务商 + 对话型
// 模型）——面板只读不拉网络（GET /models 在服务商详情页，职责分离）。
// 壳形态 = KimiFullInputSheet 同款半模态三件套（HdsNavigation MODAL 标题栏 +
// sheetTitleBarOptions 5 参规格 + bindToScrollable 滚动感知 + 底部安全区延伸）。
// 选中/使用中刷新 = ForEach 键并入状态（2026-09-03 自检轮修正：官方 ForEach 文档非首次
// 渲染仅随数据源变化驱动——键不变即不复渲染，item 内读 @StorageProp 不触发项重建；键含
// 选中/使用中态则父页写键后对应项重建、打勾与徽章即时刷新——ModelFetchSheet 键含勾选态
// 同款正解；调用方直传的当前值下键恒稳定无重建）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items, TextModifier, uiMaterial } from '@kit.ArkUI';
import { HdsListItemCard, HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  capLabels, effectiveCaps, ModelRow, ProviderRow,
  queryModels, queryProviders, setModelFavorite
} from '../../common/store/ProviderDb';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardBorderColor, cardDescColor, cardTitleColor
} from '../../common/Theme';
import {
  modelGroupKey, modelMatchesFilter, normalizeModelFilterKeyword, pickEmptyHint
} from '../../common/providers/ModelPickFilter';
import { SegmentBar } from '../SegmentBar';
import { sheetTitleBarOptions } from './KimiSheetCommon';

// 服务商分组间距（2026-09-03 卡片化新增）：组间 = 2 倍组内（组内 CARD_SPACING 10），
// 分组视觉分层明确——「不同厂商过近」防呆；首组顶部间距由外层 Column padding 提供
const SECTION_GAP: number = 20;

// 面板数据节（服务商 + 其对话模型；加载侧组装，筛选后为副本）
interface ProviderSection {
  provider: ProviderRow;
  models: ModelRow[];
}

@Component
export struct ModelPickerSheet {
  // 选中回调（父页写 AppStorage 后重读连接；本组件不落键——数据与编排在父页惯例，
  // 但面板需读键渲染当前项，见 aboutToAppear）
  onPick: (providerId: string, modelId: string) => void = () => {
  };
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主 bottomPad 注入——列表尾部占位，坑66 方案 B：末卡滚到
  // 底停在导航条上方；缺省 0 = 无占位（宿主未传时行为与旧版一致））
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 光感新规范开关（2026-09-08 面板重构新增：搜索框双态——开 = 官方灰阶实底、关 =
  // 沉浸光感材质；订阅式切换即刷，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 当前选择（**一律由调用方直传**——三站点各自的"当前"语义不同：对话页 = 本会话生效值
  //〔会话级覆盖 ?? 助手绑定 ?? 全局默认〕、助手「模型设置」页 = 该助手绑定、功能模型页 =
  // 该槽位绑定；'' = 未指定 → 全列表无打勾）。普通成员直传 = 打开时刻快照（面板每次开
  // 重建、选中即关，无滞后窗口）
  // ★ 2026-09-10 会话级覆盖层笔：原「对话页读全局 active 两键 / 其余站点走 useCustomSelection
  // 直传」的**双口径统一为直传单口径**——active 两键整体退役；"读一个全局当前模型"正是
  // 本笔修掉那个 bug 的根因形态（会话内的选择被写成全局默认），勿再引入
  selProviderId: string = '';
  selModelId: string = '';
  // 系统颜色模式（卡底深浅色随动——ModelFetchSheet/面板卡同款口径）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private sections: ProviderSection[] = [];
  @State private hintText: string = '';
  // 首拉完成闸（2026-09-08 新增，ChatSessionList.loaded 同款）：false = 查询在途——空态
  // 提示行不显示（防「暂无可用模型」闪现）；查询落定（成功/失败）置 false
  @State private loading: boolean = true;
  // 搜索关键词（$$ 双向绑定实时过滤；空串 = 不过滤）
  @State private keyword: string = '';
  // 收藏分段（0 = 全部 / 1 = 收藏）：切换内存过滤不重查库（visibleSections 派生）
  @State private favSegment: number = 0;
  // 刷新纪元（组卡规范 §4.1）：收藏/选中态变化自增 → 外层分组键变重建 → 行内爱心与打勾
  // 即时刷新（内层键单独承担不了跨组重建）
  @State private listEpoch: number = 0;
  // 分段选项（SegmentButtonV2Items 纯展示，普通成员——ChatSessionList favSegItems 同款；
  // 项为 { text } 对象数组，非字符串数组）
  private favSegItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全部' },
    { text: '收藏' }
  ]);
  private listScroller: Scroller = new Scroller();
  // 官方 HDS 列表卡可用性（HdsListItemCard 要求 HDSComponent.Full——SettingsPage 同款门槛）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // 行选中判定（打勾渲染；当前值由调用方直传，见 selProviderId 注释——★ 2026-09-10 会话级
  // 覆盖层笔自检：原 if(双口径分支) 结构删分支后留成 if(...) return true; return false 冗余壳，
  // 收敛为单表达式，行为等价）
  private isSelected(providerId: string, modelId: string): boolean {
    return this.selProviderId === providerId && this.selModelId === modelId;
  }

  // 服务商「使用中」徽章判定（分节头；口径同行选中判定）
  private isProviderInUse(providerId: string): boolean {
    return this.selProviderId === providerId;
  }

  // 当前选择的服务商/模型两键（单口径：调用方直传——各站点自己决定"当前"是什么）
  private currentProviderId(): string {
    return this.selProviderId;
  }

  private currentModelId(): string {
    return this.selModelId;
  }

  // 当前选择主文案（三态口径，任务书 §2.3）：命中 = 模型显示名（name 空则 modelId）；
  // 两键非空但清单内反查不到（目标已停用/删除）= modelId 原文（不谎报「未选择」）；
  // 两键含空 = 「未选择」灰字
  private currentPickPrimary(): string {
    const providerId: string = this.currentProviderId();
    const modelId: string = this.currentModelId();
    if (providerId === '' || modelId === '') {
      return '未选择';
    }
    const section: ProviderSection | undefined =
      this.sections.find((item: ProviderSection): boolean => item.provider.id === providerId);
    if (section === undefined) {
      return modelId;
    }
    const model: ModelRow | undefined =
      section.models.find((item: ModelRow): boolean => item.modelId === modelId);
    if (model === undefined) {
      return modelId;
    }
    return model.name !== '' ? model.name : model.modelId;
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

  // 未选择判定（当前选择行卡灰字/默认色分治）
  private currentPickUnselected(): boolean {
    return this.currentProviderId() === '' || this.currentModelId() === '';
  }

  // 模型行能力标签文本（副行；'' = 不显该行——行高随之分档）。必须走 effectiveCaps
  //（派生语义单源，禁直读 model.caps），全称标签不引入第二套短标签
  private capText(model: ModelRow): string {
    return capLabels(effectiveCaps(model)).join(' · ');
  }

  // 可见分节（build 内派生，ChatSessionList.visibleRows 先例）：先收藏段过滤（只留含收藏
  // 模型的分组 + 组内只留收藏行），再关键词过滤（组内空则丢组）；不动排序
  private visibleSections(): ProviderSection[] {
    const keyword: string = normalizeModelFilterKeyword(this.keyword);
    const favOnly: boolean = this.favSegment === 1;
    const result: ProviderSection[] = [];
    for (const section of this.sections) {
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
      normalizeModelFilterKeyword(this.keyword), this.favSegment === 1);
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
        this.getUIContext().getPromptAction().showToast({
          message: '收藏保存失败：' + (e as Error).message
        });
      });
  }

  aboutToAppear(): void {
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<ProviderSection[]> => {
        // 逐启用服务商拉对话模型组装分节（服务商 = 用户手建小数据集，条目级循环查询
        // 开销可忽略；分组语义不值得为它加聚合查询）；停用模型不列（模型卡开关启停的
        // 消费端之一——显示形态不变，仅数据过滤）
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
        this.sections = sections;
        this.loading = false;
      })
      .catch((e: Object): void => {
        this.hintText = '模型清单读取失败：' + (e as Error).message;
        this.loading = false;
      });
  }

  build() {
    HdsNavigation() {
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（模型面板机制，档案 6.2）；
      // Scroll+Column 嵌套分区——组间 SECTION_GAP / 组内 CARD_SPACING 分级（同面板
      // ModelFetchSheet 同源姿势；Clip false + TopStart 对齐 + Spring 见规范-半模态 §2）
      Scroll(this.listScroller) {
        Column({ space: SECTION_GAP }) {
          // ── 当前选择（分组标题 + 行卡；纯信息展示不挂点击）──
          Column({ space: CARD_SPACING }) {
            this.CurrentPickHeader()
            this.CurrentPickCard()
          }
          .width('100%')
          // ── 搜索行（官方 Search + 光感双态；随列表滚动不吸顶——模糊生效前提）──
          this.SearchRow()
          // ── 「全部/收藏」分段（收藏入口；宽度 = 父容器约束，SegmentBar 无宽度参数）──
          Column() {
            SegmentBar({
              items: this.favSegItems,
              selectedIndex: $favSegment
            })
          }
          .width(CARD_PANEL_WIDTH)
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
          // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条；bottomInset=0
          // 时高度 0 无占位）
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
    // 半模态三件套（KimiFullInputSheet 同款规格——标题栏 5 参 + MODAL + 滚动感知 + 底部
    // 安全区延伸）
    .titleBar(sheetTitleBarOptions('选择模型', '服务商 · 模型',
      (): void => {
        this.onClose();
      }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.listScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }

  // 「当前选择」分组标题（分组标题规格 = 粗体 15fp + 左缘 16 对卡缘，规范-半模态 §3）
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

  // 当前选择行卡（HDS 官方列表卡优先 + 无 Full 回退自制卡；纯信息展示不挂 onClick——
  // 避免「按得下去没反应」；HDS 卡宽度官方语义 = 容器 −32，勿挂 .width()）。
  // 主副行文案三态见 currentPickPrimary/currentPickSecondary；长名单行省略号截断
  @Builder
  CurrentPickCard() {
    if (this.hdsListCardAvailable) {
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
        cardBorderRadius: 16,
        cardBackgroundColor: cardBg(this.appColorMode)
      })
    } else {
      Column({ space: 2 }) {
        Text(this.currentPickPrimary())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.currentPickUnselected() ? cardDescColor() : cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.currentPickSecondary() !== '') {
          Text(this.currentPickSecondary())
            .fontSize(14)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
    }
  }

  // 搜索行（官方 Search 实时过滤；写法逐参数对齐 SessionSearchPage.SearchBox，去掉其
  // hdsAvailable 分支——面板内恒单路径。不挂 searchButton/defaultFocus：实时过滤无需
  // 提交式，选择器打开即弹键盘会遮住列表。材质双态 = 光感新规范开关）
  @Builder
  SearchRow() {
    Search({ value: $$this.keyword, placeholder: '筛选模型' })
      .backgroundColor(this.contentFallback ? $r('app.color.comp_fallback_gray') : Color.Transparent)
      .systemMaterial(this.contentFallback ? uiMaterial.Material.empty :
        resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN, this.immersiveLevel, false))
      .width(CARD_PANEL_WIDTH)
      .height(40)
  }

  // 分节头（服务商名 + 使用中徽章 + 模型数；分组标题规格 = 粗体 15fp + 左缘 16 对卡缘，
  // 规范-半模态 §3；上下间距交容器 space，不占 padding）
  @Builder
  SectionHeader(section: ProviderSection) {
    Row({ space: 8 }) {
      Text(section.provider.name)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.isProviderInUse(section.provider.id) ? '使用中' : section.models.length + ' 模型')
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(6)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  // 组卡（同一服务商的模型合并一张卡；官方实测规格 = 卡宽 CARD_PANEL_WIDTH + 圆角 16 +
  // 上下 padding 4；行间 0.5vp 细线末行不显；内层行键含收藏/选中双态——跨组刷新靠外层
  // 纪元键，见 listEpoch 注释）
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
    .borderRadius(16)
    .padding({ top: 4, bottom: 4 })
  }

  // 模型行（两区并列不嵌套，规范-列表卡片与组卡 §4.2）：左侧可点区 = 选模型（标题 +
  // 能力标签副行）；右侧键区 = 收藏爱心 + 选中打勾（兄弟节点，禁嵌套进左区——点击双触发）。
  // 行缩进 = 外包 Column padding 4（禁 margin，红线 1）；行高 64（有副行）/ 56 固定分档
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
        // 选中打勾（纯视觉不挂点击；未选中不占位）——★ 2026-09-08 决明真机反馈：勾在收藏
        // 键左侧（原在右侧会把爱心挤左、跨行心形对不齐）；爱心键恒为行尾最右键，打勾的
        // 出现/消失只压缩左侧可点区，心形位置不动
        if (this.isSelected(providerId, model.modelId)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([$r('sys.color.comp_background_emphasize')])
        }
        // 收藏键（行内图标键 TEXTUAL 无底——未收藏 heart/font_secondary、已收藏
        // heart_fill/font_emphasize，两色均为官方语义色非自绘；行尾最右键，恒贴卡右缘）
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
}
