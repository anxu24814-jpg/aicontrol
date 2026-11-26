// 会话搜索记录区板块组件：搜索历史区（SessionHistorySection）+ 最近进入区（SessionRecentSection），
// 消费方 = 独立二级页 SessionSearchPage，机制/形态对齐 components/settings/SearchSections.ets
// 同名板块（记录区展示归板块组件，搜索主流程归页面）。独立建档不入 ChatSessionList 系宪法
// 「新增功能域不论行数一律先拆」+ SearchSections 分层先例。数据流契约：
//   · SessionHistorySection：@StorageLink(SESSION_SEARCH_HISTORY_KEY) 自读自清（清空 = 直调
//     clearSessionSearchHistory 写 AppStorage；记录由 SessionSearchPage.applySearch 提交时写，
//     AppStorage 响应式自动刷新）；词条点击 → onSearch(term) 上抛（页面直通 applySearch：
//     回填关键词 + 出结果 + 移头历史）；
//   · SessionRecentSection：id 源在 AppStorage（自持），标题/时间反查在页面
//    （SessionSearchPage.recentConvItems，依赖已加载 rows），结果经 @Prop items 下发（坑57
//     正解：@Prop 单向按值流入，rows 删改父 build 重算即刷新）；清空直调
//     clearSessionRecentConvs；卡片点击 → onOpen(id) 上抛（页面 openConv：加密守卫 + 记最近
//     进入 + 打开会话；列表页 ChatSessionList.handleOpenCard 为同链另一入口）。
//   · 空态判定由页面持键长度判断，本组件只负责「有数据时渲染」。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  clearSessionRecentConvs,
  clearSessionSearchHistory,
  MAX_SESSION_SEARCH_HISTORY,
  SESSION_RECENT_CONV_KEY,
  SESSION_SEARCH_HISTORY_KEY
} from '../../common/SessionSearch';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, CARD_RADIUS } from '../../common/Theme';

// 最近进入条目展示行（页面反查产物；id = 会话 id 供点击回调上行）
export interface SessionRecentItem {
  id: string;
  title: string;
  // 时间文本（formatConvTime 预格式化——组件零依赖 Date 逻辑）
  timeText: string;
}

// 时间展示（MM-DD HH:mm）——记录区/搜索页完整时间戳口径，自 SessionCardItem 提取共用
export function formatConvTime(ts: number): string {
  const d: Date = new Date(ts);
  const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' +
    pad(d.getMinutes());
}

// 会话卡时间标签（三档）：今天 = `HH:mm`；昨天 = `昨天 HH:mm`；更早 = `MM-DD`，跨年补年份
// `YYYY-MM-DD`。与 formatConvTime 分家——本函数只服务会话卡（时间挤在标题行右端吃标题宽度）。
// now 可注入（断言直跑用固定基准，避免「今天」随系统时钟漂移导致假红）。
export function formatSessionCardTime(ts: number, now: number = Date.now()): string {
  const d: Date = new Date(ts);
  const n: Date = new Date(now);
  const pad = (v: number): string => (v < 10 ? '0' + v : '' + v);
  const hm: string = pad(d.getHours()) + ':' + pad(d.getMinutes());
  if (d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth()
    && d.getDate() === n.getDate()) {
    return hm;
  }
  const yesterday: Date = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1);
  if (d.getFullYear() === yesterday.getFullYear() && d.getMonth() === yesterday.getMonth()
    && d.getDate() === yesterday.getDate()) {
    return '昨天 ' + hm;
  }
  if (d.getFullYear() === n.getFullYear()) {
    return pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
}

// ── 搜索历史区：标题行（左「搜索历史」+ 右垃圾桶清空）+ 词条胶囊流式排列（形态对齐
// SearchSections.HistorySection：标题 18vp 加粗 + trash 24vp；胶囊 cardBg 圆角 14）──
@Component
export struct SessionHistorySection {
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(SESSION_SEARCH_HISTORY_KEY) history: string[] = [];
  // 词条点击 → 页面 applySearch（回填关键词 + 移头历史）
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
        // 展示侧截断：@StorageLink 直读不经 getSessionSearchHistory，上限调整后旧持久化残留
        // 只在 slice 后消失；键用词条自身（去重后互异，unshift 重排时键稳定避免全量重建）
        ForEach(this.history.slice(0, MAX_SESSION_SEARCH_HISTORY), (term: string) => {
          Text(term)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(14)
            // 超长词条视觉省略：存储侧已截断 10 字，展示侧再限宽双保险（160vp ≈ 11 个 14fp 中文字）
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

// ── 最近进入区：标题行（左「最近进入」+ 右 X 清空）+ 最近进入会话卡片列表（卡片形态对齐
// SearchSections.RecentSection：官方 HdsListItemCard 前缀符号 + 两行文本；「最近使用」在
// 会话域定名「最近进入」，决明拍板）──
@Component
export struct SessionRecentSection {
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 反查后的展示条目（@Prop 单向按值流入，rows 删改父 build 重算刷新；上限截断在页面）
  @Prop items: SessionRecentItem[] = [];
  // 卡片点击 → 页面 openConv（加密守卫 + 记最近进入 + 打开会话）
  onOpen: (id: string) => void = (id: string) => {
  };

  // 最近进入卡（2026-11-04 蒙层合规笔：整卡自绘，§4.19 范式——卡底 + padding 4 + 透明
  // Button 蒙层，四缘各 4vp；卡高 72 = 4×2 + 64，内容内距 12 + 外层 4 = 原官方卡内距 16；
  // 前缀符号 24 + 间距 16 = 标题左缘卡内 52，与原官方卡排版同址）
  @Builder
  RecentCard(item: SessionRecentItem) {
    Column() {
      Button() {
        Row({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
          Column({ space: 0 }) {
            Text(item.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.timeText)
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([cardDescColor()])
            .flexShrink(0)
        }
        .width('100%')
        .height('100%')
      }
      .type(ButtonType.Normal)
      .width('100%')
      .height(64)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.onOpen(item.id);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
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

      // 卡片列表：标题行与卡片区间距走标题行 margin bottom 12，卡间走内层 Column space 10
      Column({ space: 10 }) {
        // 键 = 身份 + 行内消费的全部可变字段（坑44 同族：同 id 会话标题/时间变化须键变重建
        // ——@Builder 值参行的唯一刷新通道，否则界面静默冻结）
        ForEach(this.items, (item: SessionRecentItem) => {
          this.RecentCard(item)
        }, (item: SessionRecentItem) => item.id + '|' + item.title + '|' + item.timeText)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
  }
}
