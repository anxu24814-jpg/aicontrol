// 会话搜索记录区板块组件（2026-09-08 会话搜索记录区，决明指令「样式与设置搜索对齐」；
// 同日改版后消费方 = 独立二级页 SessionSearchPage——搜索 UI 自 ChatSessionList 一级页内嵌
// 态全量迁出，本文件职责/契约不变）：
// 搜索历史区（SessionHistorySection）+ 最近进入区（SessionRecentSection），机制/形态逐环
// 对齐 components/settings/SearchSections.ets 同名板块（该文件拆分先例：记录区展示归板块
// 组件，搜索主流程归页面 SessionSearchPage）。为何独立建档不入 ChatSessionList：该组件曾
// 895+ 行软引导区（技术债务清单在档），历史/最近进入为新增功能域——宪法「新增功能域不论
// 行数一律先拆」+ SearchSections 分层先例。数据流契约同 SearchSections：
//   · SessionHistorySection：@StorageLink(SESSION_SEARCH_HISTORY_KEY) 自读自清（清空 = 直调
//     clearSessionSearchHistory 写 AppStorage；记录由 SessionSearchPage 在 applySearch
//    （提交式）时写，AppStorage 响应式自动刷新本组件——双向同步零传参）；
//     词条点击 → onSearch(term) 上抛（SessionSearchPage 直通 applySearch：回填关键词 +
//     出结果 + 移头历史）；
//   · SessionRecentSection：id 源在 AppStorage（自持），标题/时间反查依赖页面已加载 rows
//     ——反查在页面（SessionSearchPage.recentConvItems），结果经 @Prop items 下发（坑57
//     正解：@Prop 单向按值流入，rows 变化（删会话/切助手）父 build 重算即刷新，先例
//     ChatInputBar attachments: PendingAttachment[]）；清空直调 clearSessionRecentConvs；
//     卡片点击 → onOpen(id) 上抛（SessionSearchPage.openConv：加密守卫 + 记最近进入 +
//     onOpenSession 上行打开会话——列表页 ChatSessionList.handleOpenCard 为同链另一入口）。
//   · 空态判定（记录区全空引导）由 SessionSearchPage 持键长度判断（页面级编排，SearchPage
//     同构），本组件只负责「有数据时渲染」。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsListItemCard, PrefixIcon } from '@kit.UIDesignKit';
import {
  clearSessionRecentConvs,
  clearSessionSearchHistory,
  MAX_SESSION_SEARCH_HISTORY,
  SESSION_RECENT_CONV_KEY,
  SESSION_SEARCH_HISTORY_KEY
} from '../../common/SessionSearch';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

// 最近进入条目展示行（页面反查产物；id = 会话 id 供点击回调上行）
export interface SessionRecentItem {
  id: string;
  title: string;
  // 时间文本（formatConvTime 预格式化——组件零依赖 Date 逻辑）
  timeText: string;
}

// 时间展示（MM-DD HH:mm；2026-09-08 自 SessionCardItem.fmtTime 提取——记录区卡片复用同
// 口径，P2-4 重复两次提取为公共函数，卡片侧改消费本函数零行为变化）
export function formatConvTime(ts: number): string {
  const d: Date = new Date(ts);
  const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' +
    pad(d.getMinutes());
}

// ── 搜索历史区：标题行（左「搜索历史」+ 右垃圾桶清空）+ 词条胶囊流式排列 ──
// 形态对齐 SearchSections.HistorySection（dshinhm 定稿随迁）：标题 18vp 加粗 + 垃圾桶
// sys.symbol.trash 24vp；胶囊 cardBg 圆角 14、展示侧 maxWidth + 单行省略双保险
@Component
export struct SessionHistorySection {
  // 系统颜色模式（深浅色切换自动刷新胶囊/标题配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 搜索历史（AppStorage 持久化；清空直接写 AppStorage，自动刷新）
  @StorageLink(SESSION_SEARCH_HISTORY_KEY) history: string[] = [];
  // 词条点击回调（ChatSessionList：回填关键词 + 移头历史）
  onSearch: (term: string) => void = (term: string) => {
  };

  build() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => {
            clearSessionSearchHistory();
          })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap }) {
        // 展示侧截断：@StorageLink 直读 AppStorage、不经 getSessionSearchHistory——上限调整
        // 后旧持久化残留只在本次 slice 后消失（SearchSections 同款姿势）；
        // keyGenerator 用词条自身（历史去重后互异，键稳定避免 unshift 重排时全量重建）
        ForEach(this.history.slice(0, MAX_SESSION_SEARCH_HISTORY), (term: string) => {
          Text(term)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(14)
            // 超长词条视觉省略：存储侧已在 SessionSearch 截断 10 字，展示侧再限宽双保险
            //（160vp ≈ 11 个中文 14fp 字，SearchSections 同值）
            .constraintSize({ maxWidth: 160 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.onSearch(term);
            })
        }, (term: string) => term)
      }
      .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
  }
}

// ── 最近进入区：标题行（左「最近进入」+ 右 X 清空）+ 最近进入会话卡片列表 ──
// 卡片形态对齐 SearchSections.RecentSection（官方 HdsListItemCard 前缀符号 + 两行文本；
// 回退自制卡片同构）；「最近使用」在会话域定名「最近进入」（2026-09-08 决明拍板）
@Component
export struct SessionRecentSection {
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 反查后的展示条目（@Prop——rows 删改后父 build 重算即刷新；上限截断在页面 recentConvItems）
  @Prop items: SessionRecentItem[] = [];
  // 卡片点击回调（ChatSessionList.handleOpenCard：加密守卫 + 记最近进入 + 进入）
  onOpen: (id: string) => void = (id: string) => {
  };
  // 官方 HDS 列表项卡片可用性（HDSComponent.Full，与设置搜索记录卡同一能力位）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // 最近进入卡片（官方 HdsListItemCard 宽度姿势 = 不设 width，实际 CARD_PANEL_WIDTH 对齐
  // 搜索框与记录区；回退自制卡片同 SearchSections.RecentCard）
  @Builder
  RecentCard(item: SessionRecentItem) {
    if (this.hdsListCardAvailable) {
      HdsListItemCard({
        prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.message') } }),
        textItem: {
          primaryText: { text: item.title },
          secondaryText: { text: item.timeText }
        },
        cardBorderRadius: 16,
        onClick: () => {
          this.onOpen(item.id);
        }
      })
    } else {
      // 回退自制卡（Button(Normal) 包裹 = 官方原生按压蒙层，2026-09-12 UI 同形异构归一
      // 笔 1——与 HDS 分支官方卡按压反馈对齐；SearchSections.RecentCard 同构）
      Button() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(20)
            .fontColor([cardTitleColor()])
          Column({ space: 4 }) {
            Text(item.title)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.timeText)
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .borderRadius(16)
      .backgroundColor(cardBg(this.appColorMode))
      .onClick(() => {
        this.onOpen(item.id);
      })
    }
  }

  build() {
    Column() {
      Row() {
        Text('最近进入')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => {
            clearSessionRecentConvs();
          })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ bottom: 12 })

      // 卡片列表：内层 Column space（标题行与卡片区间距走标题行 margin bottom 12，
      // SearchSections 同款双层间距姿势）
      Column({ space: 10 }) {
        ForEach(this.items, (item: SessionRecentItem) => {
          this.RecentCard(item)
        }, (item: SessionRecentItem) => item.id)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
  }
}
