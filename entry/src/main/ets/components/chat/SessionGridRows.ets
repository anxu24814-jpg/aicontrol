// 会话宫格视图渲染域（用户面名称 = 会话宫格视图，2026-11-11 定名；内部代号 = 方块档 / 方块卡，
// 本文余下注释沿用内部代号，改用户面文案只看正文不搜代号）。2026-11-11 新增，决明拍板
//「偏好开关 + 两列方块卡」：职责一句话 =
//「会话列表方块档的 WaterFlow 容器 + 方块卡体」。与列表档 ChatSessionRows.ets 并列，两档由
// 壳 ChatSessionList 按偏好整页切换（禁在既有 List 档里分叉，顺手大重构是禁区）。
//
// ★ 卡壳不自绘（AGENTS.md「HDS 单路径」）：沿用列表档同款官方 HdsListItemCard，白底 / 圆角 /
// 按压态 / 材质由 HDS 给；prefixItem 与 suffixItem 恒 undefined，B 区 textItem.customBuilder
// 整块自建内容（列表档 2026-10-30 四稿定稿同款姿势，官方 CustomBuilder 优先级高于其它接口）。
// 整卡自绘（自制卡）是被条款点名的非 HDS 回退形态，勿改回。
//
// ★ 卡高两档 + 错落（决明 2026-11-11 拍板）：**不传 cardHeight、不写死 B 区高度**——B 区
// Column 由标题行 + 摘要（maxLines(2) 自然换行）+ 日期徽标行叠成，短摘要一行 = 矮卡，长摘要
// 两行 = 高卡，卡高随内容自然分两档；官方 WaterFlow「从第二行起每个子节点放到当前总高度最小
// 的列」把两张不同高的卡错开，这才是「卡与卡错落」。等高就做不到错落，故原「卡高固定两排、
// 第二排空出」规格随本笔改判为「一行就矮一截」。官方依据 =《创建瀑布流 (WaterFlow)》
// 《Repeat：可复用的循环渲染》「仅有 List、ListItemGroup、Grid、Swiper 以及 WaterFlow 支持
// Repeat 懒加载」，本地 SDK 26 component/water_flow.d.ts:246/373/509/586/599/679 核对。
//
// ★ 取色口径 A（决明 2026-11-11 拍板）：色条 seed = conversationId 全串散列六色，与列表档
// 身份徽章同源（Theme.identityFg）。**不取标题首字**——AI 生成标题会换首字导致色条跳变，
// 首码点取色亦已因「一屏全同色」被 2026-10-20 真机推翻，判据 = docs/规范-视觉色板与徽标.md
// §3。色条只出色不显首字（供图形态）。会话图标开关沿用控制色条显隐，语义与列表档徽章一致。
//
// ★ 交互（决明 2026-11-11 拍板「仍做长按菜单，增加更多键，不做左右滑」）：普通态卡上四点键
// dot_grid_2x2 + 无底 TEXTUAL + font_secondary（AGENTS.md:52 行内图标键形制，SDK 26
// sysResource.js:3868 符号在位），点击 bindMenu 弹**同一份**四项菜单；长按卡体 bindContextMenu
// 弹同一份菜单（SessionCardMenu.ets 参数与材质单源）。**本档整层不挂 SessionSwipeItem**，
// 左右滑四键在此档不存在；列表档维持 2026-10-30「更多键退役」拍板不动。卡片只读展示，
// 不做内联编辑 / 拖拽排序。多选态沿用「不挂菜单 + 勾选圈」判据。
//
// ★ 键纪律（AGENTS.md:60 / 规范 §2）：Repeat 键只写会话 id 身份；标题 / 摘要 / 时间 / 星标 /
// 未读 / 生成中 / 草稿全部随 SessionListRow 对象整体替换或经 V2 @Param 传播，禁塞回键里当刷新
// 手段（Repeat 不做键变重建）。RepeatItem 整体传参、卡内一律读 ri.item 当前值，禁构造期快照。
// ★ 新增滚动容器必带 .scrollBar(BarState.Off)（AGENTS.md:54，全站统一，新增漏设 = 违宪）。
//
// 真机待验（BLOCKED 同名节）：①HDS 卡不传 cardHeight 时是否严格按 B 区内容分两档高（列表档
// 实测「B 区 48 + 内距 16 = 卡高 64」为本判据依据，方块档未实测）；②四点键 bindMenu 与卡体
// onClick 是否命中互斥（列表档四点键有同款先例，HDS 卡内未实测）；③不等高卡在
// columnsTemplate('1fr 1fr') 下的错落观感与窄卡内日期徽标行是否溢出；④负边距补偿后卡缘是否
// 精确落在 16vp（若 HDS 内置边距非整 16，卡会被列框裁掉右侧圆弧——风险登记 BLOCKED 首项）。
//
// ★★ 几何两件（2026-11-11 决明报障后改判，两处都属「切换卡样式不得改页面观感」的实现面）：
// ①**头尾让位走内容轨偏移，禁走容器 padding**：上一稿判「WaterFlow 无 contentStartOffset」
// 是**错读**——两项挂在 ScrollableCommonMethod 上（`common.d.ts:25367` contentStartOffset
// @since 22；WaterFlowAttribute 继承它见 `water_flow.d.ts:489`），官方滚动文档亦明写
// 「Starting from API version 22, the Grid and WaterFlow components also support setting
// contentStartOffset and contentEndOffset」（`scroll.d.ts:492`）。而容器 padding 在本项目 =
// **视口缩进**（坑9）：内容被裁在 padding 边界，滚动时首/末排卡被平直切一刀（真机截图
// 2026-11-11 16:27 实锤：首排卡只剩摘要行、色条与标题切在视口外，末排卡半截）——观感上
// 就是「顶部底部各一条分割线」，且卡片滚不进标题栏蒙层、也滚不到底部页签后面。故本档与
// 单列档同轨：padding 只留左右，顶/底让位交给 offset（属内容轨，滚动时可滚走）。
// ②**卡宽要抵消 HDS 卡自带的 32vp 宽度内缩**：官方 HdsListItemCard 渲染宽 = 容器 100% −
// 32vp（左右各 16vp 内建外边距；项目实锤见 AiAssistPage.ets 头注释与 Theme.ets
// CARD_PANEL_WIDTH 条，2026-11-11 截图实测亦合：容器内缩 16 + 卡自带 16 = 卡左缘 32vp）。
// 上一稿同时留着容器左右 16vp，于是卡左缘落在 32vp（比标题「对话」左缘多缩一格）、两列中缝
// 10+16+16 = 42vp，卡反而只 129vp 宽。现行 = 自建外层 Column 撑宽 32vp + 左右各 −16 负边距
// 把卡自带的两侧外边距吃掉：卡体回到列宽、左缘 = 16vp 与标题左缘对齐、右缘对称、中缝 =
// 列间距 CARD_SPACING。负边距只挂**自建外层**，禁挂 HDS 卡本体（官方「属性」节明示卡本体挂
// padding/margin 会与内置属性冲突导致布局异常或失效）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { HdsListItemCard } from '@kit.UIDesignKit';
import { ConversationRow } from '../../common/store/ChatDb';
import { CARD_RADIUS, CARD_SPACING, cardBg, cardDescColor, favoriteStarColor, identityFg }
  from '../../common/Theme';
import { CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { StatusBadge } from '../StatusBadge';
import { SessionListRow } from './ChatSessionRowModel';
import { formatSessionCardTime } from './SessionSearchPanels';
import { SessionCardMenuBuilder, SessionCardMenuCallbacks, sessionCardMenuOptions }
  from './SessionCardMenu';

// 方块档几何（本档域内单源，勿与列表档徽章/侧滑常量互借——两档形制不同）
// 页左右内缩 = 卡屏边距 16（与标题「对话」左缘同轴）
const GRID_SIDE_INSET: number = 16;
// HDS 列表卡自带左右各 16vp 内建外边距（渲染宽 = 容器 − 32vp，取证见文件头几何②）。方块档要
// 「卡左缘 16vp 对齐标题、中缝 = CARD_SPACING」，就把这 32vp 用负边距从自建外层吃掉——
// 撑宽量 = 两侧各一份，卡体随后正好回到列宽
const GRID_HDS_CARD_SIDE_INSET: number = 16;
const GRID_CARD_FRAME_WIDTH: string = 'calc(100% + 32vp)'; // = 2 × GRID_HDS_CARD_SIDE_INSET
const GRID_BAR_WIDTH: number = 3;
// 色条高 = 标题文字高：16fp 中文字身约 0.87em ≈ 14vp。2026-11-11 决明报障「竖条顶上比文字高、
// 高度不平齐」——原 16 取的是字号而非字身，比字身高约 2vp，且顶对齐故只在上端露头
const GRID_BAR_HEIGHT: number = 14;
// 标题行高显式钉死（默认 ≈1.4em 仅差 0.x vp，观感不变）：色条靠它在标题行内居中，行高不显式
// 则居中基准随字体行高浮动
const GRID_TITLE_LINE_HEIGHT: number = 22;
// 色条上偏 = 行高与色条高之差的一半（居中于标题行 = 上下与文字齐平；禁写字面量，改行高 / 条高
// 自动随动）
const GRID_BAR_TOP_OFFSET: number = (GRID_TITLE_LINE_HEIGHT - GRID_BAR_HEIGHT) / 2;
// 内容顶内距：HDS 卡自带上下各 8vp（2026-11-11 截图实测卡顶到首元素 8vp），本档再补 6 → 合计 14。
// 取值沿革：决明「标题离顶部间距太小」→ 补 8 合计 16，随后「间距又大了，略小点」→ 收到 6（合计 14，
// 比列表卡「内距 16」紧 2vp，仍比原生的 8 松 6vp）
const GRID_CONTENT_TOP_PAD: number = 6;
const GRID_SNIPPET_LINE_HEIGHT: number = 18;
const GRID_MORE_ICON_SIZE: number = 14;
const GRID_MORE_KEY_SIZE: number = 20;
const GRID_TAIL_GAP: number = 16;
const MULTISELECT_BAR_CLEARANCE: number = 56;
// 与列表档 LIST_CACHED_COUNT 同值（两列可视区卡数更多，缓存按「列数 × 屏内行数」自然扩，
// 不另凭感觉加码——性能不许愿，实测卡顿再调）
const GRID_CACHED_COUNT: number = 5;

// ═══ 方块卡卡体（官方 HDS 壳 + B 区自建内容）═══
@ComponentV2
struct SessionGridCardItem {
  @Require @Param ri: RepeatItem<SessionListRow>;
  @Param selectMode: boolean = false;
  @Param selected: boolean = false;
  @Param unread: boolean = false;
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Param cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  @Param immersiveLevel: number = 0;
  @Event onOpen: (row: ConversationRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };
  @Event onFavorite: (row: ConversationRow) => void = () => {
  };
  @Event onRename: (row: ConversationRow) => void = () => {
  };
  @Event onMove: (row: ConversationRow) => void = () => {
  };
  @Event onDelete: (row: ConversationRow) => void = () => {
  };

  private showUnreadDot(): boolean {
    return !this.selectMode && this.unread;
  }

  private showLoading(): boolean {
    return !this.selectMode && this.ri.item.loading;
  }

  private showDraftMark(): boolean {
    return !this.selectMode && this.ri.item.draft;
  }

  // 摘要空态与列表档同文案（55% 透明）；方块档靠这行决定卡高归属，空态也占住一行不塌卡
  private snippetText(): string {
    if (this.ri.item.snippet !== '') {
      return this.ri.item.snippet;
    }
    return '暂无消息摘要';
  }

  @Builder
  DraftMarkBuilder() {
    StatusBadge({ text: '草稿' })
  }

  @Builder
  LoadingMarkBuilder() {
    LoadingProgress()
      .width(13)
      .height(13)
      .color($r('sys.color.font_secondary'))
  }

  // 多选勾选圈（方块档底行 20vp 位，点击穿透落到卡体 onClick 单一通路，坑5 口径）
  @Builder
  CheckKeyBuilder() {
    Checkbox()
      .select(this.selected)
      .hitTestBehavior(HitTestMode.None)
      .width(GRID_MORE_KEY_SIZE)
      .height(GRID_MORE_KEY_SIZE)
  }

  // 四项菜单参数现场组装（按下当刻的行对象，星标态即取即准；与列表档 menuParams 同职责）
  private menuParams(): SessionCardMenuCallbacks {
    const params: SessionCardMenuCallbacks = {
      item: this.ri.item,
      onDelete: (row: ConversationRow): void => {
        this.onDelete(row);
      },
      onRename: (row: ConversationRow): void => {
        this.onRename(row);
      },
      onMove: (row: ConversationRow): void => {
        this.onMove(row);
      },
      onToggleFavorite: (row: ConversationRow): void => {
        this.onFavorite(row);
      }
    };
    return params;
  }

  // 长按与四点键共用同一份菜单内容（CustomBuilder 只做调用，声明式组件在全局 @Builder 内）
  @Builder
  CardMenu() {
    SessionCardMenuBuilder(this.menuParams())
  }

  // B 区内容：左侧身份色条 + 标题 / 两行摘要 / 日期徽标行。★ 整块不写 .height——卡高随
  // 摘要行数自然分两档，写死即退化成等高、WaterFlow 错落失效（见文件头）。
  @Builder
  GridContentBuilder() {
    Row({ space: 8 }) {
      // 身份色条恒显示——偏好键已退役、行为固化为不可关闭，图标不再有隐藏态
      Column()
        .width(GRID_BAR_WIDTH)
        .height(GRID_BAR_HEIGHT)
        // 上偏 = (行高 − 条高)/2：色条在标题行内垂直居中，上下缘与文字齐平
        .margin({ top: GRID_BAR_TOP_OFFSET })
        .borderRadius(GRID_BAR_WIDTH / 2)
        .backgroundColor(identityFg(this.ri.item.id, this.appColorMode))
        .flexShrink(0)
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(this.ri.item.title !== '' ? this.ri.item.title : '新对话')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .lineHeight(GRID_TITLE_LINE_HEIGHT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.showUnreadDot()) {
            Circle({ width: 8, height: 8 })
              .fill($r('sys.color.warning'))
              .flexShrink(0)
          }
        }
        .width('100%')
        Text(this.snippetText())
          .fontSize(13)
          .fontColor(cardDescColor())
          // 空态 55% 透明 / 草稿正文 Medium——与列表档 TextItemBuilder 同判据同值（本件显隐
          // 注释「摘要空态与列表档同文案〔55% 透明〕」的实现面，2026-11-11 自检轮补齐，勿只留注释）
          .opacity(this.ri.item.snippet === '' && !this.ri.item.draft ? 0.55 : 1)
          .fontWeight(this.ri.item.draft ? FontWeight.Medium : FontWeight.Normal)
          .lineHeight(GRID_SNIPPET_LINE_HEIGHT)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        // 底行：日期 + 徽标 + 更多键（右下）。日期可收缩截断，徽标与键恒占位——窄卡下
        // 先牺牲日期尾部，不让操作键被挤出（项目「状态位右置」口径的方块档变体）
        Row({ space: 6 }) {
          // 会话时间恒显示——偏好键已退役、行为固化为不可关闭，日期文本不再有隐藏态
          Text(formatSessionCardTime(this.ri.item.updatedAt))
            .fontSize(12)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.showDraftMark() || this.showLoading() || this.ri.item.favorite) {
            Row({ space: 6 }) {
              if (this.showDraftMark()) {
                this.DraftMarkBuilder()
              }
              if (this.showLoading()) {
                this.LoadingMarkBuilder()
              }
              if (this.ri.item.favorite) {
                SymbolGlyph($r('sys.symbol.star_fill'))
                  .fontSize(13)
                  .fontColor([favoriteStarColor(this.appColorMode)])
              }
            }
            .flexShrink(0)
          }
          Blank()
          if (this.selectMode) {
            this.CheckKeyBuilder()
          } else {
            // 四点更多键：行内图标键官方形制（无底 TEXTUAL + font_secondary），点击弹同一份
            // 四项菜单。bindMenu 是组件属性形态，不新增全局 promptAction 调用（UIContext 纪律）
            Button() {
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(GRID_MORE_ICON_SIZE)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .width(GRID_MORE_KEY_SIZE)
            .height(GRID_MORE_KEY_SIZE)
            .padding(0)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .bindMenu(this.CardMenu, {
              placement: Placement.BottomRight,
              // 第三参 true = 交互形变 + 触点流光（全站菜单同款，勿回改 false）
              systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                this.immersiveLevel, true)
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    // 顶部呼吸（HDS 8 + 本档 6 = 14）：卡高随之 +6，两档错落不受影响（高度仍由摘要行数决定）
    .padding({ top: GRID_CONTENT_TOP_PAD })
  }

  // 卡体（两分支共用同一 builder，避免重复构造）：官方 HDS 壳，A/C 区不挂让 B 区吃满整行
  @Builder
  CardBody() {
    HdsListItemCard({
      prefixItem: undefined,
      textItem: {
        customBuilder: (): void => {
          this.GridContentBuilder();
        }
      },
      suffixItem: undefined,
      cardBorderRadius: CARD_RADIUS,
      cardBackgroundColor: cardBg(this.appColorMode, this.cardAlphaLevel),
      onClick: (): void => {
        if (this.selectMode) {
          this.onToggle(this.ri.item.id);
          return;
        }
        this.onOpen(this.ri.item);
      }
    })
  }

  build() {
    if (this.selectMode) {
      // 多选态不挂长按菜单（勾选中误弹与批量语义打架，列表档同判据）
      Column() {
        this.CardBody()
      }
      // 外层撑宽 32vp + 左右 −16 = 抵消 HDS 卡自带的左右各 16vp（文件头几何②；负边距挂
      // 自建外层，不挂 HDS 卡本体）
      .width(GRID_CARD_FRAME_WIDTH)
      .margin({
        left: -GRID_HDS_CARD_SIDE_INSET,
        right: -GRID_HDS_CARD_SIDE_INSET
      })
    } else {
      Column() {
        this.CardBody()
      }
      .width(GRID_CARD_FRAME_WIDTH)
      .margin({
        left: -GRID_HDS_CARD_SIDE_INSET,
        right: -GRID_HDS_CARD_SIDE_INSET
      })
      // 长按上下文菜单：cardHeight 传 0 = 回官方默认定位。方块档卡高两档且随内容变，
      // 固定锚点（卡片左下角下方 8vp）拿不到可靠实测值，按拆件既有口径不下发 anchorPosition。
      // 无横滑展开态需归位，aboutToAppear 回调传空实现。
      .bindContextMenu(this.CardMenu, ResponseType.LongPress,
        sessionCardMenuOptions(this.immersiveLevel, (): void => {
        }, 0))
    }
  }
}

// ═══ 方块档容器（WaterFlow + Repeat.virtualScroll）═══
@ComponentV2
export struct SessionGridRows {
  @Param visibleRows: SessionListRow[] = [];
  @Param hintText: string = '';
  @Param topPad: number = 0;
  @Param topClearance: number = 8;
  @Param bottomPad: number = 0;
  @Param selectMode: boolean = false;
  @Param selectedIds: string[] = [];
  @Param unreadConvId: string = '';
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Param cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  @Param immersiveLevel: number = 0;
  @Event onOpen: (row: ConversationRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };
  @Event onFavorite: (row: ConversationRow) => void = () => {
  };
  @Event onRename: (row: ConversationRow) => void = () => {
  };
  @Event onMove: (row: ConversationRow) => void = () => {
  };
  @Event onDelete: (row: ConversationRow) => void = () => {
  };
  // 与列表档共用壳侧滚动空闲闸：滑动中不整表重查、不落快照
  @Event onScrollingChanged: (scrolling: boolean) => void = () => {
  };

  // 读取失败提示行：官方 WaterFlow footer（容器选项，不算 Repeat 之外的第二个子组件——
  //「滚动容器组件内只能包含一个 Repeat」红线）。列表档随末卡尾行，两档位置不同但文案同源。
  // ★ 判据必须带「有行」（2026-11-11 自检轮修）：0 行时壳 ChatSessionList 已有同文案兜底行
  //（build「读取失败提示行 · 0 行兜底」段，同定位常量），footer 不判行数会与它同屏双行。
  // 互斥契约 = BLOCKED「会话方块卡 真机清单」第 12 项；列表档同判据在末卡（ri.index === length-1）。
  @Builder
  HintFooter() {
    if (this.hintText !== '' && this.visibleRows.length > 0) {
      Text(this.hintText)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_warning'))
        .width('100%')
        .margin({ top: CARD_SPACING })
    }
  }

  build() {
    WaterFlow({ footer: (): void => {
      this.HintFooter();
    } }) {
      Repeat<SessionListRow>(this.visibleRows)
        .each((ri: RepeatItem<SessionListRow>) => {
          FlowItem() {
            SessionGridCardItem({
              ri: ri,
              selectMode: this.selectMode,
              selected: this.selectedIds.includes(ri.item.id),
              unread: ri.item.id === this.unreadConvId,
              appColorMode: this.appColorMode,
              cardAlphaLevel: this.cardAlphaLevel,
              immersiveLevel: this.immersiveLevel,
              onOpen: (row: ConversationRow): void => {
                this.onOpen(row);
              },
              onToggle: (id: string): void => {
                this.onToggle(id);
              },
              onFavorite: (row: ConversationRow): void => {
                this.onFavorite(row);
              },
              onRename: (row: ConversationRow): void => {
                this.onRename(row);
              },
              onMove: (row: ConversationRow): void => {
                this.onMove(row);
              },
              onDelete: (row: ConversationRow): void => {
                this.onDelete(row);
              }
            })
          }
          .width('100%')
        })
        // 键只写会话 id（身份唯一）；可变展示成分走行对象整体替换 + V2 @Param 传播，
        // 见文件头键纪律两问
        .key((row: SessionListRow): string => row.id)
        .virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(CARD_SPACING)
    .rowsGap(CARD_SPACING)
    .width('100%')
    .height('100%')
    // 左右内缩与列表档卡屏边距同值 16（padding 只留左右——纵向 padding = 视口缩进，会把首末排
    // 卡平直切一刀，见文件头几何①）
    .padding({
      left: GRID_SIDE_INSET,
      right: GRID_SIDE_INSET
    })
    // 头尾让位 = 内容轨偏移，与单列档逐参数同源（topPad + topClearance / bottomPad +
    // GRID_TAIL_GAP + 多选批量条让位）：属内容轨故随内容滚走——首排卡可滑入标题栏蒙层、
    // 末排卡可滑到页签后面，两档滚动观感与「光感」一致。API 22 起 WaterFlow 支持（取证见
    // 文件头几何①）
    .contentStartOffset(this.topPad + (this.selectMode ? 0 : this.topClearance))
    .contentEndOffset(this.bottomPad + GRID_TAIL_GAP +
      (this.selectMode ? MULTISELECT_BAR_CLEARANCE : 0))
    // 回弹与单列档同款（WaterFlow 官方默认 EdgeEffect.None，不挂则两档手感不一）
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .cachedCount(GRID_CACHED_COUNT)
    // 滚动通用事件与 List 档同契约，停止后壳侧统一兑现最新重拉意图/回包
    .onScrollStart((): void => {
      this.onScrollingChanged(true);
    })
    .onScrollStop((): void => {
      this.onScrollingChanged(false);
    })
  }
}
